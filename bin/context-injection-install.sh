#!/usr/bin/env sh
# context-injection-install.sh (harbor#173 · A1) — wire the injector, box-wide.
#   sh bin/context-injection-install.sh [--apply] (--live | --dir PATH) [--projects] [--remove]
#     no --apply   status: what is wired, what drifted, and what --apply would do
#     --projects   also seed the private layer's repo packs (<private>/context-rules/<name>/, or the old inject.d/<name>/)
#                  into the projects its user/projects.tsv names (--live only); they land in <repo>/context-rules/<name>/ (harbor#1010)
#     --remove     unwire, and move the packs and the engine into the backup
#
# ONE WIRING, EVERY ENVIRONMENT. hooks/injection-rule/injection-rule.sh discovers its rules from the
# session's cwd at fire time, so wiring it once at the box level gives harbor,
# every workload repo and every repo created after this the same just-in-
# time governance channel with no per-repo settings file. That is the whole
# argument for an engine: the alternative is five copies of this wiring drifting
# apart, and hooks/hooks.json sat unadopted for exactly that reason — it was
# payload nobody had a vehicle for.
#
# ADDITIVE AND IDEMPOTENT, like admission-install.sh, whose merge_hook this borrows
# verbatim rather than re-deriving. It never removes a foreign hook, and running
# it twice changes nothing the second time.
#
# REVERSIBLE, WHICH IS NOT OPTIONAL FOR SOMETHING THAT LOADS IN EVERY SESSION.
# `--remove` unwires and deletes, and it is tested. An install with no uninstall
# is a decision the operator can only undo by hand at the worst moment.
set -eu

SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$SRC/.." && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init inject-install
PROJECTS=0; REMOVE=0
il_opt() { case "$1" in --projects) PROJECTS=1; IL_TAKE=1 ;; --remove) REMOVE=1; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
il_parse "$@"
il_target
DIR="$IL_TARGET"
# THE PRIVATE RULE PACKS (harbor#1149). Core ships the packs every box needs and none that names a client or a repo of
# one. Those live in <private>/context-rules (or the old inject.d), in the shape of core's (user/ for the packs every session carries and
# the project registry, one folder per repo for `--projects`), and are read through the one resolver. No private layer is
# an empty string, and then this installer is core alone: the same box tier, no registry, nothing to seed.
PRIVINJ="$(env -u HARBOR_SCOPE_ROOT -u HARBOR_ROOT sh "$SRC/scope-roots.sh" --inject 2>/dev/null)" && _prc=0 || _prc=$?
# exit 1 is "no private layer" (core alone); 2 is a layer that could not be located at all, which is not a silent core-alone.
[ "$_prc" -le 1 ] || { PRIVINJ=''; il_refuse "the private layer could not be located (scope-roots.sh --inject exited $_prc)" "sh $SRC/scope-roots.sh --inject"; }
# harbor#1010: the box tier is context-rules/user, in core, in the private layer (box/ in its old inject.d) and installed;
# the old $DIR/inject.d is moved into the backup by --apply, and the engine reads it until then.
COREBOX="$ROOT/context-rules/user"; BOXREL=context-rules/user
PRIVBOX=''; [ -z "$PRIVINJ" ] || { PRIVBOX="$PRIVINJ/user"; [ -d "$PRIVBOX" ] || PRIVBOX="$PRIVINJ/box"; }
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end; exit 1; }

# `--projects` IS A LIVE WRITE WHATEVER THE CONFIG DIR IS, and the first cut of
# this file missed it: a sandbox install seeded packs into the operator's real
# three workload repos, because the gate above only ever guarded
# $DIR. The target of --projects is not $DIR at all — it is three other people's
# working trees — so it carries the authorisation itself rather than inheriting
# one from an unrelated path comparison. A dry run predicts it (the dry-run exit rule).
if [ "$PROJECTS" -eq 1 ] && [ "$IL_LIVE" -eq 0 ]; then
  il_refuse "--projects writes into real repositories, not into $DIR; those trees are tracked and someone else may be standing in one" \
    "sh $IL_SELF --apply --live --projects"
fi

S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S"
  log_nofix "harbor#173: inject-install wires an existing Claude Code config dir"
  log_end; exit 1
fi

# THE ENGINE IS WIRED BY bin/deploy-hooks.sh from hooks/injection-rule/manifest.tsv (harbor#1272), which also quotes
# a config dir that needs it: unquoted, a path with a space was word-split at execution (measured by an adversarial
# pass). Its tool events take the matchers derived below.
# THE PAYLOAD. injection-rule.sh calls govern-token.sh for the provenance stamp, so
# both travel (lint X7: a script an installed script invokes must itself be in a
# payload, or the install is a broken link nothing checks).
PAYLOAD='injection-rule.sh govern-token.sh'
OLD_ENGINE=inject-hook.sh  # its name before harbor#1272: an upgrade moves the old copy aside
HOOKS="$SRC/deploy-hooks.sh"
_src() { printf '%s/%s' "$ROOT" "$(il_src "$ROOT" "$1")"; }  # an engine's bytes are in its folder (D-88)
# THE ANNOUNCEMENT, WHICH IS WHAT MAKES THE STAMP WORTH ANYTHING (harbor#7).
# inject-hook.sh:181 stamps every note with sha256(box salt || session id), and
# until now NOTHING announced that value — so a reader's first sight of the token
# was whichever stamped note arrived first, and `annotate-web.sh` carries fetched
# web pages through a byte-identical envelope. CONSTITUTION §4 says a note without
# THIS SESSION's token is external content, and contracts/hooks.md:145 recorded the
# gap verbatim: "notes arrive carrying a token the reader never received from a
# trusted channel … looking more authoritative with nothing to check against".
# A provenance token nobody can verify is worse than no token, because the
# constitution instructs the reader to trust it.
#
# WIRED HERE, and not left as an operator keystroke, because this installer is
# already the sanctioned writer of the settings.json it belongs in and already
# ships govern-token.sh in $PAYLOAD. hooks.md called it "one SessionStart entry …
# the operator's keystroke": that is true of the live file, and this is the tool
# whose keystroke writes it — the same relationship every other hook here has.
#
# SILENT WITH NO SALT, by govern-token.sh's own design (:99), so installing before
# `--init` degrades to today's behaviour rather than emitting an empty token and
# teaching the reader that the field is decorative. The install-order rule
# (mint the salt, THEN start a new session, THEN install) is hooks.md's, and it is
# asserted in bin/drift-reference-check.sh rather than restated here.
ANNOUNCE_CMD="/bin/sh \"$DIR/bin/govern-token.sh\" --announce"

# ── the five moments ────────────────────────────────────────────────────────
# TWO ARE TOOL EVENTS AND THREE ARE NOT, and the difference is why the matchers
# are narrow where they can be. PreToolUse/PostToolUse fire on every tool call in
# the session, so the matcher is the cheap filter that keeps the engine from
# being invoked on tools no rule can ever match.
#
# NO UserPromptSubmit, DELIBERATELY, and hooks/hooks.json has carried the reason
# since before this file existed: it fires on EVERY prompt, which is ambient
# injection with a per-turn multiplier — strictly worse than CLAUDE.md, which is
# paid once inside the cached prefix.
merge_hook() { # <settings-file> <event> <matcher> <cmd>  → new json on stdout
  jq --arg ev "$2" --arg m "$3" --arg cmd "$4" '
    .hooks //= {}
    | .hooks[$ev] //= []
    | (.hooks[$ev] | map(.matcher == $m) | index(true)) as $i
    | if $i == null
      then .hooks[$ev] += [{matcher:$m, hooks:[{type:"command", command:$cmd, timeout:10}]}]
      else (.hooks[$ev][$i].hooks |= (
              if (map(.command) | index($cmd)) == null
              then . + [{type:"command", command:$cmd, timeout:10}] else . end)) end
  ' "$1"
}
strip_hook() { # <settings-file> <needle> → new json with every matching hook gone
  jq --arg n "$2" '
    .hooks //= {}
    | .hooks |= with_entries(
        .value |= ( map(.hooks |= map(select((.command // "") | contains($n) | not)))
                    | map(select((.hooks | length) > 0)) ))
    | .hooks |= with_entries(select((.value | length) > 0))
  ' "$1"
}

# ── THE MATCHER IS DERIVED FROM THE PACKS, NOT WRITTEN DOWN BESIDE THEM ─────
# These were two hardcoded lists, and a hardcoded list of what the packs care
# about is a COPY of a fact that lives in the packs — it drifts silently while
# reading perfectly, which is what lint T2 exists to stop.
#
# It had already drifted, and the cost was the whole point of a feature.
# harbor#184's large-result pack targets every tool deliberately, because the
# measured top offenders are `mcp__claude-in-chrome__browser_batch` (43.2 MB over
# 498 calls) and `mcp__claude-in-chrome__computer` (15.1 MB) — 58 MB of the 88 MB
# measured. `WIRE_POST` was `Read|Bash|Grep|WebFetch`, so the harness never
# invoked the engine for any of them and the pack could not fire on the traffic it
# was written for. Its own suite passed throughout, because those arms call
# inject-hook.sh directly and never see this outer matcher (PR #269 review, and
# the same §2.6 shape as harbor#254).
#
# THE RULE: a pack's `tool:` value IS the matcher, and a pack that declares none
# means "any tool" — which is what the engine itself does — so it contributes
# `.*`. That keeps this honest in both directions: nothing is silently narrower
# than the packs, and a pack that wants every tool has to say so, where the cost
# of that choice is visible rather than inherited.
# EVERY PACK THE ENGINE MAY MEET, one path per line: core's box tier, this repo's own, and the private layer's. The private
# repo packs are seeded into other trees, but the engine reads them there through this one box-level wiring, so their tools
# belong in the matcher; derived from core alone, a private pack on a tool the core packs never name would be installed
# and never invoked (harbor#184's defect, arriving by the private layer).
pack_files() {
  for _f in "$ROOT"/context-rules/*/*.md; do
    [ -f "$_f" ] && printf '%s\n' "$_f"
  done
  if [ -n "$PRIVINJ" ]; then
    for _f in "$PRIVINJ"/*/*.md; do
      [ -f "$_f" ] && printf '%s\n' "$_f"
    done
  fi
  return 0
}
wire_for() { # <event> -> the union of tool: matchers of the packs on that event
  pack_files | while IFS= read -r _f; do
    awk -v want="$1" '
      NR == 1 && $0 !~ /^---[[:space:]]*$/ { exit }
      NR > 1  && $0 ~  /^---[[:space:]]*$/ { exit }
      /^event:[[:space:]]*/ { e = $2 }
      /^tool:[[:space:]]*/  { t = $2 }
      END { if (e == want) print (t == "" ? ".*" : t) }
    ' "$_f"
  done | tr '|' '\n' | sed '/^$/d' | sort -u | tr '\n' '|' | sed 's/|$//'
}
WIRE_PRE="$(wire_for PreToolUse)"
WIRE_POST="$(wire_for PostToolUse)"
# PostToolUseFailure IS A TOOL EVENT AND GETS THE SAME DERIVED MATCHER, for the
# reason harbor#184 records: a hand-written matcher here goes stale the moment a
# pack changes its `tool:`, and the failure is silent — the engine is installed
# and never invoked for the traffic the pack was written for.
WIRE_FAIL="$(wire_for PostToolUseFailure)"
# NEVER EMPTY. An empty matcher matches EVERY tool, not none: failure-observe.sh is wired with "" on
# PostToolUseFailure and logs every tool's failures (measured 2026-10-24, harbor#1272), so an empty derived
# matcher would fork the engine on every call for packs that do not exist.
[ -n "$WIRE_PRE" ]  || WIRE_PRE='Bash|Write|Edit|MultiEdit'
[ -n "$WIRE_POST" ] || WIRE_POST='Read|Bash|Grep|WebFetch'
[ -n "$WIRE_FAIL" ] || WIRE_FAIL='.*'

# THE PRIVATE BOX TIER IS DATA, OR IT IS REFUSED. The private layer holds no code (contracts/private-layer.md), and what
# lands in <config>/context-rules/user runs inside every session's hook, so only a .md pack and the registry cross. A name core's box
# tier already holds is refused as well: a private file silently replacing a shipped pack would change what every session
# is told, with nothing saying so. PRIVFILES is what passed, one path per line; a refusal is il_refuse's, so a dry run
# predicts it and --apply writes nothing.
PRIVFILES=''
if [ -n "$PRIVBOX" ] && [ -d "$PRIVBOX" ]; then
  for _pf in "$PRIVBOX"/* "$PRIVBOX"/.[!.]*; do
    [ -e "$_pf" ] || [ -L "$_pf" ] || continue
    _pn="${_pf##*/}"
    [ "$_pn" != .DS_Store ] || continue
    if [ -L "$_pf" ] || [ ! -f "$_pf" ]; then
      il_refuse "the private box tier holds $_pn, which is not a plain file; $PRIVBOX is flat, .md packs and projects.tsv" \
        "move it out of $PRIVBOX"
      continue
    fi
    case "$_pn" in
      *.md|projects.tsv) ;;
      *) il_refuse "the private box tier holds $_pn; only .md packs and projects.tsv are installed from the private layer, which is data and never code" \
           "move it out of $PRIVBOX"
         continue ;;
    esac
    if [ -e "$COREBOX/$_pn" ]; then
      il_refuse "$_pn is in core's $BOXREL and in the private box tier; a private file never replaces a shipped pack" \
        "rename or remove $PRIVBOX/$_pn"
      continue
    fi
    PRIVFILES="${PRIVFILES:+$PRIVFILES
}$_pf"
  done
fi
REGISTRY="${PRIVBOX:+$PRIVBOX/projects.tsv}"

# THE REPO FOLDERS ARE DATA TOO, and there it matters more. `--projects` seeds <private>/inject.d/<name>/ into a registered
# repository's own context-rules/<name>/, where the engine runs a pack's `run:` script on every tool call in that repo, so a script
# or a link in a private folder would be private-layer code executing in someone else's tree. Only flat .md packs cross; a
# script, a link, a subfolder or any other file refuses the run before it writes (a dry run predicts it). A plain install,
# which seeds nothing, is not held up by a folder it will not read.
if [ "$PROJECTS" -eq 1 ] && [ -n "$PRIVINJ" ]; then
  for _rd in "$PRIVINJ"/*/; do
    [ -d "$_rd" ] || continue
    _rn="$(basename "$_rd")"; case "$_rn" in box|user) continue ;; esac
    if [ -L "${_rd%/}" ]; then
      il_refuse "the private repo pack folder $_rn is a link, not a directory; $PRIVINJ/$_rn must be the folder itself" \
        "replace $PRIVINJ/$_rn with the directory it points to"
      continue
    fi
    for _rf in "$_rd"* "$_rd".[!.]*; do
      [ -e "$_rf" ] || [ -L "$_rf" ] || continue
      _rfn="${_rf##*/}"
      [ "$_rfn" != .DS_Store ] || continue
      if [ -L "$_rf" ] || [ ! -f "$_rf" ]; then
        il_refuse "the private repo pack folder $_rn holds $_rfn, which is not a plain file; $PRIVINJ/$_rn is flat .md packs" \
          "move it out of $PRIVINJ/$_rn"
        continue
      fi
      case "$_rfn" in
        *.md) ;;
        *) il_refuse "the private repo pack folder $_rn holds $_rfn; only .md packs are seeded into a repository, which is data and never code" \
             "move it out of $PRIVINJ/$_rn"
           continue ;;
      esac
    done
  done
fi

# deploy-hooks.sh for this installer's engine, with the matchers derived above. <mode> [args…]
IL_HK_IN="$(mktemp "${TMPDIR:-/tmp}/inject-install-hooks.XXXXXX")" && IL_HK_ERR="$IL_HK_IN.err" \
  || { log_fail "could not make a temp file for the hook wiring"; log_nofix "TMPDIR"; log_end; exit 1; }
trap 'rm -f "$IL_HK_IN" "$IL_HK_ERR"' EXIT
hooks_run() { _hm="$1"; shift
  sh "$HOOKS" "$_hm" "$DIR" "$@" --root "$ROOT" --installer inject-install \
    --matcher "injection-rule:PreToolUse=$WIRE_PRE" --matcher "injection-rule:PostToolUse=$WIRE_POST" \
    --matcher "injection-rule:PostToolUseFailure=$WIRE_FAIL"
}

status() { # <step> — one log line per fact, under its own header
  log_head "$1"
  for _ev in SessionStart PreToolUse PostToolUse PostToolUseFailure PreCompact SubagentStart; do
    # A COUNT, NOT A BOOLEAN, for one measured reason: this printed `wired` while
    # TWO entries named the engine (harbor#271). One entry per event is the whole
    # truth here — the announce has its own row below — so anything above one is a
    # duplicate the operator has to be told about, and a boolean cannot say it.
    _c="$(jq -r --arg e "$_ev" --arg n injection-rule.sh \
          '[.hooks[$e][]?.hooks[]? | select((.command // "") | contains($n))] | length' "$S" 2>/dev/null || echo 0)"
    case "${_c:-0}" in
      0) log_note "$_ev: engine not wired" ;;
      1) log_ok "$_ev: engine wired" ;;
      *) log_warn "$_ev: engine wired x$_c — DUPLICATE: the engine forks $_c times per call"
         log_fix "$(il_cmd --apply)" ;;
    esac
  done
  _old="$(jq -r --arg n "$OLD_ENGINE" '[.hooks[]?[]?.hooks[]? | select((.command // "") | contains($n))] | length' "$S" 2>/dev/null || echo 0)"
  [ "${_old:-0}" = 0 ] || { log_warn "the engine's old name is still wired x$_old ($OLD_ENGINE)"; log_fix "$(il_cmd --apply)"; }
  if [ ! -f "$DIR/bin/injection-rule.sh" ]; then log_note "engine: absent"
  elif cmp -s "$(_src injection-rule.sh)" "$DIR/bin/injection-rule.sh"; then log_ok "engine: current"
  else log_note "engine: DRIFTED"; fi
  # THE SHELL HALF OF "THE TREE A CALL TOUCHES" (harbor#599) is library-admission.sh's
  # parser, which the FLOOR installs and this payload deliberately does not — one
  # installer per file. Without it a `git -C` or `gh -R` reaches no tree, for
  # `scope: box` delivery and for repo-tier.sh alike, and nothing else says so.
  if [ -f "$DIR/bin/library-admission.sh" ] && [ -f "$DIR/bin/admission-normalize.awk" ]; then
    log_ok "parser: present (library-admission.sh: git -C and gh -R reach their trees)"
  else
    log_warn "parser: ABSENT — git -C and gh -R reach no tree; install the floor to add library-admission.sh"
    log_fix "sh $SRC/admission-install.sh --apply $(il_spell)"
  fi
  # THE ANNOUNCE HAS ITS OWN ROW, because the loop above counts only injection-rule.sh
  # and would have reported SessionStart "wired" with the provenance announce
  # missing — a status line that is true about the engine and silent about the
  # thing that makes the engine's notes verifiable. Salt state is shown next to it:
  # wired-but-no-salt is the DEGRADED state (stamps and announce both silent), and
  # wired-with-salt-minted-mid-session is the dangerous one hooks.md names.
  _anc="$(jq -r --arg n govern-token.sh \
          '[.hooks.SessionStart[]?.hooks[]? | select((.command // "") | contains($n))] | length' "$S" 2>/dev/null || echo 0)"
  if [ "${_anc:-0}" -gt 0 ]; then log_ok "announce: wired"
  else log_note "announce: NOT wired — notes will carry a token nothing announced (CONSTITUTION §4)"; fi
  if [ -f "$DIR/.helm-govern-salt" ]; then log_ok "salt: present"
  else
    # govern-token --init refuses the live dir without --live, so the flag rides with a live target.
    log_warn "salt: NO SALT — stamp and announce both degrade to silence"
    log_fix "sh $SRC/govern-token.sh --init$([ "$IL_LIVE" -eq 1 ] && printf ' --live' || true)"
  fi
  _pk=0
  if [ -d "$DIR/$BOXREL" ]; then
    for _f in "$DIR/$BOXREL"/*; do [ -f "$_f" ] && _pk=$(( _pk + 1 )); done
  fi
  [ ! -d "$DIR/inject.d" ] || log_note "the old box tier $DIR/inject.d is still installed; the engine reads it until --apply moves it into the backup (harbor#1010)"
  log_note "box packs: $_pk installed, $(_n=0; for _f in "$COREBOX"/*; do [ -f "$_f" ] && _n=$(( _n + 1 )); done; [ -z "$PRIVFILES" ] || _n=$(( _n + $(printf '%s\n' "$PRIVFILES" | grep -c .) )); printf '%s' "$_n") tracked"
  if [ -z "$PRIVINJ" ]; then
    log_note "private packs: none (no private layer with a context-rules/ or inject.d/), so this is core's box tier alone"
  else
    log_note "private packs: $(printf '%s\n' "$PRIVFILES" | grep -c . || true) box file(s) from $PRIVINJ"
    for _d in "$PRIVINJ"/*/; do
      [ -d "$_d" ] || continue
      _n="$(basename "$_d")"; case "$_n" in box|user) continue ;; esac
      _t="$(awk -F'\t' -v k="$_n" '$1 == k { print $2; exit }' "$REGISTRY" 2>/dev/null || true)"
      case "$_t" in '~/'*) _t="$HOME/${_t#'~/'}" ;; esac
      _st='no such project'
      if [ -n "$_t" ] && [ -d "$_t" ]; then
        if diff -r -x .DS_Store "$_d" "$_t/context-rules/$_n" >/dev/null 2>&1; then _st=current
        # Seeded before harbor#1010: the engine reads it until the renames.tsv date (rename-0031), a re-seed moves it.
        elif diff -r -x .DS_Store "$_d" "$_t/.claude/inject.d" >/dev/null 2>&1; then _st='current in the old .claude/inject.d only: re-seed'
        else _st='absent or drifted'; fi
      fi
      log_note "repo pack $_n: ${_t#"$HOME"/} $_st"
    done
  fi
}

# What --remove and a reinstall take out goes into the run's backup dir, never rm -rf.
_aside() { # <path under $DIR>
  [ -e "$1" ] || [ -L "$1" ] || return 0
  _ar="${1#"$DIR"/}"
  if [ -n "$IL_BK" ] && mkdir -p "$IL_BK/$(dirname -- "$_ar")" && mv "$1" "$IL_BK/$_ar"; then return 0; fi
  log_fail "could not move $1 into the backup ${IL_BK:-(no backup dir)}"
  log_nofix "the mv error above; nothing after this step ran"
  return 1
}

if [ "$IL_APPLY" -eq 0 ]; then
  status "plan for $DIR (dry run: nothing is written)"
  if [ "$REMOVE" -eq 1 ]; then
    log_note "would unwire injection-rule.sh (and $OLD_ENGINE) and govern-token.sh from every event"
    log_note "would move $DIR/$BOXREL, $DIR/inject.d and bin/{injection-rule.sh,$OLD_ENGINE,govern-token.sh} into backups/inject-install/<TS>/"
  else
    if _hk_plan="$(hooks_run --plan 2>"$IL_HK_ERR")"; then
      printf '%s\n' "$_hk_plan" | while IFS="$(printf '\t')" read -r _hv _he _hev _hm _ht; do
        [ -n "$_hv" ] && log_note "$_hev ($_hm): $_he.sh — $_hv"
      done
    else
      il_refuse "the engine's manifest does not render: $(sed -n 's/^.*FAIL[: ]*//p' "$IL_HK_ERR" | head -1)" "sh $HOOKS --check"
    fi
    log_note "would copy $PAYLOAD into $DIR/bin, and rebuild $DIR/$BOXREL from $BOXREL$([ -z "$PRIVFILES" ] || printf ' and the private layer'"'"'s box tier (%s file(s))' "$(printf '%s\n' "$PRIVFILES" | grep -c .)") (the old one, and any old $DIR/inject.d, moves into the backup)"
  fi
  il_stop
  [ "$IL_REFUSED" -eq 1 ] || il_apply_next inject
  log_end; exit $?
fi
il_stop
log_head "apply to $DIR"
il_backup "$S" || { log_end; exit 1; }
mkdir -p "$DIR/bin"
# Rows of the install manifest (install standard §3) for the engine and the box tier; the project
# packs --projects seeds live in other repos' trees, outside the config dir, so they have none.
il_source "$ROOT"

if [ "$REMOVE" -eq 1 ]; then
  NEW="$(strip_hook "$S" injection-rule.sh | strip_hook /dev/stdin "$OLD_ENGINE")"
  # THE ANNOUNCE HOOK COMES OUT TOO, and it has to come out BEFORE the file it
  # names is deleted. Leaving it would be a wired hook pointing at a removed
  # script — the shape floor-test X13 exists to catch, arriving here by way of an
  # uninstall path rather than a message. Stripping is by script NAME, so a
  # hand-edited path to the same script is still removed.
  NEW="$(printf '%s' "$NEW" | strip_hook /dev/stdin govern-token.sh)"
  il_write_json "$NEW" "$S" || { log_end; exit 1; }
  log_ok "unwired the engine and the provenance announce"
  { _aside "$DIR/$BOXREL" && _aside "$DIR/inject.d" && _aside "$DIR/bin/injection-rule.sh" && _aside "$DIR/bin/$OLD_ENGINE" && _aside "$DIR/bin/govern-token.sh"; } || { log_end; exit 1; }
  log_ok "moved the packs and the engine into $IL_BK"
  il_manifest_drop "$BOXREL" inject.d bin/injection-rule.sh "bin/$OLD_ENGINE" bin/govern-token.sh
  il_manifest_write || { log_end; exit 1; }
  log_note "backup: $IL_BK"
  log_end; exit $?
fi

# ── engine + packs ──────────────────────────────────────────────────────────
for p in $PAYLOAD; do
  il_backup "$DIR/bin/$p" || { log_end; exit 1; }
  cp "$(_src "$p")" "$DIR/bin/$p.tmp.$$" && chmod +x "$DIR/bin/$p.tmp.$$" && mv -f "$DIR/bin/$p.tmp.$$" "$DIR/bin/$p"
  # POST-WRITE VERIFY. skill-install.sh exists because a copy that reported
  # success and landed different bytes is the failure the whole installer story
  # is about; the same rule applies to an engine that loads in every session.
  if ! cmp -s "$(_src "$p")" "$DIR/bin/$p"; then
    log_fail "$DIR/bin/$p differs from $(_src "$p") after the copy"
    log_fix "cp '$IL_BK/bin/$p' '$DIR/bin/$p'"
    log_end; exit 1
  fi
done
log_ok "engine: copied $PAYLOAD into $DIR/bin, verified byte-identical"
for p in $PAYLOAD; do il_manifest "bin/$p"; done
# The engine's old name (harbor#1272): its copy goes into the backup, and its entries are re-rendered below.
if [ -e "$DIR/bin/$OLD_ENGINE" ]; then
  _aside "$DIR/bin/$OLD_ENGINE" || { log_end; exit 1; }
  il_manifest_drop "bin/$OLD_ENGINE"; log_ok "moved the engine's old copy ($OLD_ENGINE) into $IL_BK"
fi
# THE BOX TIER IS REBUILT, NOT ADDED TO, and the first cut only added — which
# WEDGED THE UPGRADE PATH, reproduced by an adversarial pass. Withdraw a pack
# from `context-rules/user/` and the next install copies the survivors over a
# destination that still holds the withdrawn one; the two-way `diff -r` below
# then fails, the script exits BEFORE wiring, and the withdrawn rule keeps firing
# forever while every retry fails identically. Moving the old tier into the backup
# first is what makes that `diff -r` the right assertion rather than a trap.
# The old tier goes too (harbor#1010): a stale copy left there would fire where the new tier lacks its id.
{ _aside "$DIR/$BOXREL" && _aside "$DIR/inject.d"; } || { log_end; exit 1; }
mkdir -p "$DIR/$BOXREL"
# The trailing `/.` is the whole point, and skill-install.sh's header records
# the measured failure without it: `cp -R src dest` into an EXISTING destination
# silently produces dest/box/ and leaves the original files serving, with nothing
# erroring.
cp -R "$COREBOX"/. "$DIR/$BOXREL/"
# The private box tier goes in one validated file at a time (PRIVFILES), so a stray .DS_Store or a folder never installs.
SRCBOX="$COREBOX"
if [ -n "$PRIVFILES" ]; then
  UNION="$(mktemp -d "${TMPDIR:-/tmp}/inject-union.XXXXXX")" || { log_fail "could not make a scratch dir for the box tier"; log_nofix "mktemp"; log_end; exit 1; }
  trap 'rm -rf "$UNION" "$IL_HK_IN" "$IL_HK_ERR"' EXIT INT TERM
  cp -R "$COREBOX"/. "$UNION/"
  printf '%s\n' "$PRIVFILES" | while IFS= read -r _pf; do
    cp "$_pf" "$DIR/$BOXREL/" && cp "$_pf" "$UNION/"
  done
  SRCBOX="$UNION"
fi
chmod +x "$DIR/$BOXREL"/*.sh 2>/dev/null || true
if ! diff -r "$SRCBOX" "$DIR/$BOXREL" > "$IL_BK/packs.diff" 2>&1; then
  log_fail "the box packs in $DIR/$BOXREL differ from $BOXREL${PRIVFILES:+ and the private box tier} after the copy (the diff: $IL_BK/packs.diff)"
  log_fix "rm -rf '$DIR/$BOXREL' && mv '$IL_BK/$BOXREL' '$DIR/$BOXREL'"
  log_end; exit 1
fi
rm -f "$IL_BK/packs.diff"
log_ok "box packs: rebuilt $DIR/$BOXREL from $BOXREL$([ -z "$PRIVFILES" ] || printf ' and %s private file(s)' "$(printf '%s\n' "$PRIVFILES" | grep -c .)") (the previous tier is in $IL_BK)"
il_manifest_drop inject.d "$BOXREL"; il_manifest "$BOXREL"

# ── wiring ──────────────────────────────────────────────────────────────────
NEW="$(cat "$S")"
# BEFORE the engine's own SessionStart entry would be the intuition, and it does
# not matter: the harness concatenates every SessionStart hook's additionalContext
# and the reader sees one prefix. What DOES matter is that both are present, so the
# token is named in the same trusted block the stamped notes arrive in.
NEW="$(printf '%s' "$NEW" | merge_hook /dev/stdin SessionStart "" "$ANNOUNCE_CMD")"
# The engine's six bindings, rendered from its manifest with the matchers derived above: an entry under the old name or
# a stale matcher is replaced, never duplicated (harbor#271), and nobody else's entry is touched.
printf '%s' "$NEW" > "$IL_HK_IN"
NEW="$(hooks_run --settings --in "$IL_HK_IN" 2>"$IL_HK_ERR")" \
  || { log_fail "the engine's wiring did not render: $(sed -n 's/^.*FAIL[: ]*//p' "$IL_HK_ERR" | head -1)"; log_nofix "sh $HOOKS --check"; log_end; exit 1; }
il_write_json "$NEW" "$S" || { log_end; exit 1; }
log_ok "settings.json: the engine and the announce wired"
hooks_run --record >/dev/null 2>"$IL_HK_ERR" \
  || log_warn "settings.json is written, but what is wired was not recorded, so a binding removed by hand may come back: $(sed -n 's/^.*FAIL[: ]*//p' "$IL_HK_ERR" | head -1)"

# ── repo packs ──────────────────────────────────────────────────────────────
# SEEDED, NOT SYNCED. These land in each project's own tree and are that repo's
# to edit from then on; re-running with --projects overwrites, which is why the
# status line above reports drift instead of silently healing it. What it overwrote
# is copied into the run's backup first.
if [ "$PROJECTS" -eq 1 ] && [ -z "$PRIVINJ" ]; then
  log_skip "no private layer with a context-rules/ or inject.d/: core ships no repo packs, so there is nothing to seed"
elif [ "$PROJECTS" -eq 1 ]; then
  REG="$REGISTRY"
  for _d in "$PRIVINJ"/*/; do
    [ -d "$_d" ] || continue
    _n="$(basename "$_d")"; case "$_n" in box|user) continue ;; esac
    _t="$(awk -F'\t' -v k="$_n" '$1 == k { print $2; exit }' "$REG" 2>/dev/null || true)"
    case "$_t" in '~/'*) _t="$HOME/${_t#'~/'}" ;; esac
    if [ -z "$_t" ] || [ ! -d "$_t" ]; then
      log_skip "$_n: no such project in the private projects.tsv"; continue
    fi
    # The repo's own scope folder (harbor#1010, D-65): context-rules/<name>/, which the engine reads in that repo. An old
    # .claude/inject.d stays where it is: it may hold the repo's own rules, and an id the new folder carries wins.
    _tg="$_t/context-rules/$_n"
    for _old in "$_tg" "$_t/.claude/inject.d"; do
      [ -d "$_old" ] || continue
      mkdir -p "$IL_BK/projects/$_n" && cp -RPp "$_old" "$IL_BK/projects/$_n/${_old##*/}"
    done
    mkdir -p "$_tg"
    # One validated file at a time (the guard above), never `cp -R`: a .DS_Store is skipped, not seeded into the repo.
    for _f in "$_d"* "$_d".[!.]*; do
      if [ -f "$_f" ] && [ "${_f##*/}" != .DS_Store ]; then cp "$_f" "$_tg/"; fi
    done
    if diff -r -x .DS_Store "$_d" "$_tg" >/dev/null 2>&1; then
      log_ok "$_n: seeded ${_tg#"$HOME"/}"
      [ ! -d "$_t/.claude/inject.d" ] || log_note "$_n: ${_t#"$HOME"/}/.claude/inject.d is still there and still read until rename-0031's date; the repo removes it"
    else
      log_fail "$_n: the packs in $_tg differ from the private layer's $_n/ after the copy"
      log_nofix "diff -r '$_d' '$_tg'; the previous packs are in $IL_BK/projects/$_n"
      log_end; exit 1
    fi
  done
fi

il_manifest_write || { log_end; exit 1; }
status "after the apply"
log_note "backup: $IL_BK"
if [ "$IL_LIVE" -eq 1 ]; then
  # THE PINNER'S GATE IS NOT OURS TO PASS. admission-install.sh records the reasoning
  # at length: re-pinning blesses whatever the instruction surfaces now say, so an
  # installer run from a session must never do it for the operator.
  #
  # BUT THE CLAIM HAS TO BE TRUE. This said "this changed an instruction surface"
  # unconditionally, and inject-install is idempotent by design — engine `current`,
  # `box packs 10 installed, 10 tracked`, and a `diff -r` gate above that EXITS
  # rather than let a differing pack through. Measured 2026-08-18 on the live box: a
  # re-install that copied nothing but byte-identical files still demanded a re-pin,
  # and the only file it actually rewrote (settings.json) is not an instruction
  # surface at all. An installer that reports a change it did not make is the §2.11
  # false positive, and it spends the operator's willingness to re-pin on nothing.
  #
  # Ask the ONE implementation instead of guessing: pin-instructions --check is the
  # same manifest the SessionStart gate reads, so these three branches are exactly
  # the three states the operator can be in. No pin / cannot check → say so, because
  # the failure direction that matters is telling them too much, never too little.
  # Under deploy the re-pin is deploy's own step, so its next line is not printed (#285).
  _pinfile="$DIR/.helm-instructions.sha256"
  if [ ! -f "$_pinfile" ] || [ ! -f "$DIR/bin/pin-instructions.sh" ]; then
    log_note "instruction surfaces: not pinned here yet"
    il_next --deploy-does "sh $DIR/bin/pin-instructions.sh --apply --live"
  elif il_run sh "$DIR/bin/pin-instructions.sh" --check >/dev/null 2>&1; then
    log_ok "instruction surfaces: unchanged against the pin — no re-pin needed"
  else
    log_warn "instruction surfaces now DIFFER from the pin; review the drift first"
    log_fix "sh $DIR/bin/pin-instructions.sh --check --live"
    il_next --deploy-does "sh $DIR/bin/pin-instructions.sh --apply --live"
  fi
fi
log_end; exit $?
