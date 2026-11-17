#!/usr/bin/env sh
# context-injection-install.sh (harbor#173 · A1) — wire the injector, box-wide.
#   sh bin/context-injection-install.sh [--apply] (--live | --dir PATH) [--projects] [--remove]
#     no --apply   status: what is wired, what drifted, and what --apply would do
#     --projects   also seed the private layer's repo packs (<private>/context-rules/<name>/)
#                  into the projects its user/projects.tsv names (--live only); they land in <repo>/context-rules/<name>/ (harbor#1010)
#     --remove     unwire, and move the packs and the engine into the backup
#
# ONE WIRING, EVERY ENVIRONMENT: hooks/injection-rule/injection-rule.sh discovers its rules from the session's cwd at
# fire time, so box-level wiring gives every repo the same governance channel with no per-repo settings file. Additive and
# idempotent like admission-install.sh, whose merge_hook this borrows; it never removes a foreign hook. `--remove` is
# tested: an install with no uninstall can only be undone by hand.
# Removed notes: docs/explanation/code-cases/bin-context-injection-install.md
set -eu

SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$SRC/.." && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init inject-install
PROJECTS=0; REMOVE=0
# shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
il_opt() { case "$1" in --projects) PROJECTS=1; IL_TAKE=1 ;; --remove) REMOVE=1; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
il_parse "$@"
il_target
DIR="$IL_TARGET"
# THE PRIVATE RULE PACKS (harbor#1149): core ships the packs every box needs, none naming a client. Private packs live in
# <private>/context-rules (user/ for every session plus the project registry, one folder per repo for `--projects`),
# read through the one resolver. No private layer is an empty string: this installer is then core alone.
PRIVINJ="$(env -u HARBOR_SCOPE_ROOT sh "$SRC/scope-roots.sh" --inject 2>/dev/null)" && _prc=0 || _prc=$?
# exit 1 is "no private layer" (core alone); 2 is a layer that could not be located at all, which is not a silent core-alone.
[ "$_prc" -le 1 ] || { PRIVINJ=''; il_refuse "the private layer could not be located (scope-roots.sh --inject exited $_prc)" "sh $SRC/scope-roots.sh --inject"; }
# harbor#1010: the box tier is context-rules/user, in core, in the private layer and installed;
# an old $DIR/inject.d is moved into the backup by --apply; the engine no longer reads it.
COREBOX="$ROOT/context-rules/user"; BOXREL=context-rules/user
PRIVBOX=''; [ -z "$PRIVINJ" ] || PRIVBOX="$PRIVINJ/user"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end; exit 1; }

# `--projects` is a LIVE WRITE whatever the config dir is: its target is other working trees, not $DIR, so it carries its
# own authorisation (a sandbox install once seeded the real repos). A dry run predicts it.
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

# The engine is wired by bin/deploy-hooks.sh from hooks/injection-rule/manifest.tsv (harbor#1272), which quotes a config
# dir that needs it. PAYLOAD: injection-rule.sh calls govern-token.sh, so both travel (lint X7).
PAYLOAD='injection-rule.sh govern-token.sh'
OLD_ENGINE=inject-hook.sh  # its name before harbor#1272: an upgrade moves the old copy aside
HOOKS="$SRC/deploy-hooks.sh"
_src() { printf '%s/%s' "$ROOT" "$(il_src "$ROOT" "$1")"; }  # an engine's bytes are in its folder (D-88)
# THE ANNOUNCEMENT (harbor#7): the engine stamps notes with sha256(box salt || session id) and nothing announced that
# token, while CONSTITUTION §4 says a note without THIS session's token is external content. Wired here because this
# installer already writes the settings.json and ships govern-token.sh. Silent with no salt (govern-token.sh's design), so
# installing before `--init` degrades rather than emitting an empty token; the install order is asserted in
# bin/drift-reference-check.sh.
ANNOUNCE_CMD="/bin/sh \"$DIR/bin/govern-token.sh\" --announce"

# ── the five moments ────────────────────────────────────────────────────────
# Two of the five moments are tool events (PreToolUse/PostToolUse fire on every call), so their matchers are narrow
# filters. No UserPromptSubmit, deliberately: it fires on every prompt, ambient injection with a per-turn multiplier.
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
# A hardcoded matcher list is a COPY of what the packs care about and drifts silently (lint T2); it had, and harbor#184's
# large-result pack could not fire on the traffic it targets (most of the measured bytes were browser_batch and computer
# calls). The suites missed it because they call the engine directly (PR #269 review). THE RULE: a pack's `tool:` IS the
# matcher, and none means any tool (`.*`).
# EVERY PACK THE ENGINE MAY MEET: core's box tier, this repo's own, and the private layer's. Private repo packs are seeded
# into other trees but read through this one wiring, so their tools belong in the matcher too.
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
# PostToolUseFailure gets the same derived matcher (harbor#184): a hand-written one goes stale silently.
WIRE_FAIL="$(wire_for PostToolUseFailure)"
# NEVER EMPTY: an empty matcher matches EVERY tool, not none (failure-observe.sh's "" logs every failure, harbor#1272).
[ -n "$WIRE_PRE" ]  || WIRE_PRE='Bash|Write|Edit|MultiEdit'
[ -n "$WIRE_POST" ] || WIRE_POST='Read|Bash|Grep|WebFetch'
[ -n "$WIRE_FAIL" ] || WIRE_FAIL='.*'

# THE PRIVATE BOX TIER IS DATA, OR IT IS REFUSED: the private layer holds no code (contracts/private-layer.md) and this
# tier runs in every session's hook, so only .md packs and projects.tsv cross, and a name core's tier holds is refused
# (no silent replacement). PRIVFILES is what passed; refusals are il_refuse's, so a dry run predicts them.
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

# THE REPO FOLDERS ARE DATA TOO: `--projects` seeds a repo's own context-rules/<name>/, where a pack's `run:` script
# runs on every tool call, so only flat .md packs cross; anything else refuses before any write. A plain install is
# not held up by a folder it will not read.
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
    # A COUNT, not a boolean: a boolean printed `wired` while two entries named the engine (harbor#271).
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
  # The shell half of "the tree a call touches" (harbor#599) is library-admission.sh's parser, installed by the FLOOR and not
  # this payload; without it `git -C` and `gh -R` reach no tree.
  if [ -f "$DIR/bin/library-admission.sh" ] && [ -f "$DIR/bin/admission-normalize.awk" ]; then
    log_ok "parser: present (library-admission.sh: git -C and gh -R reach their trees)"
  else
    log_warn "parser: ABSENT — git -C and gh -R reach no tree; install the floor to add library-admission.sh"
    log_fix "sh $SRC/admission-install.sh --apply $(il_spell)"
  fi
  # The announce has its own row (the loop counts only injection-rule.sh). Wired-but-no-salt is DEGRADED (stamp and
  # announce silent); salt minted mid-session is the dangerous state hooks.md names.
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
  [ ! -d "$DIR/inject.d" ] || log_note "the old box tier $DIR/inject.d is still installed and no longer read; --apply moves it into the backup (harbor#1010)"
  log_note "box packs: $_pk installed, $(_n=0; for _f in "$COREBOX"/*; do [ -f "$_f" ] && _n=$(( _n + 1 )); done; [ -z "$PRIVFILES" ] || _n=$(( _n + $(printf '%s\n' "$PRIVFILES" | grep -c .) )); printf '%s' "$_n") tracked"
  if [ -z "$PRIVINJ" ]; then
    log_note "private packs: none (no private layer with a context-rules/), so this is core's box tier alone"
  else
    log_note "private packs: $(printf '%s\n' "$PRIVFILES" | grep -c . || true) box file(s) from $PRIVINJ"
    for _d in "$PRIVINJ"/*/; do
      [ -d "$_d" ] || continue
      _n="$(basename "$_d")"; case "$_n" in user) continue ;; esac
      _t="$(awk -F'\t' -v k="$_n" '$1 == k { print $2; exit }' "$REGISTRY" 2>/dev/null || true)"
      case "$_t" in '~/'*) _t="$HOME/${_t#'~/'}" ;; esac
      _st='no such project'
      if [ -n "$_t" ] && [ -d "$_t" ]; then
        if diff -r -x .DS_Store "$_d" "$_t/context-rules/$_n" >/dev/null 2>&1; then _st=current
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
# Rows of the install manifest (install standard §3); --projects packs live in other trees and have none.
il_source "$ROOT"

if [ "$REMOVE" -eq 1 ]; then
  NEW="$(strip_hook "$S" injection-rule.sh | strip_hook /dev/stdin "$OLD_ENGINE")"
  # The announce hook comes out too, BEFORE its script is deleted: a wired hook pointing at a removed script is floor-test
  # X13's shape. Stripping is by script NAME, so a hand-edited path is removed as well.
  NEW="$(printf '%s' "$NEW" | strip_hook /dev/stdin govern-token.sh)"
  il_write_json "$NEW" "$S" || { log_end; exit 1; }
  log_ok "unwired the engine and the provenance announce"
  { _aside "$DIR/$BOXREL" && _aside "$DIR/inject.d" && _aside "$DIR/bin/injection-rule.sh" && _aside "$DIR/bin/$OLD_ENGINE" && _aside "$DIR/bin/govern-token.sh" && _aside "$DIR/name-create.d/harbor.tsv"; } || { log_end; exit 1; }
  log_ok "moved the packs and the engine into $IL_BK"
  il_manifest_drop "$BOXREL" inject.d bin/injection-rule.sh "bin/$OLD_ENGINE" bin/govern-token.sh name-create.d/harbor.tsv
  il_manifest_write || { log_end; exit 1; }
  log_note "backup: $IL_BK"
  log_end; exit $?
fi

# ── engine + packs ──────────────────────────────────────────────────────────
for p in $PAYLOAD; do
  il_backup "$DIR/bin/$p" || { log_end; exit 1; }
  cp "$(_src "$p")" "$DIR/bin/$p.tmp.$$" && chmod +x "$DIR/bin/$p.tmp.$$" && mv -f "$DIR/bin/$p.tmp.$$" "$DIR/bin/$p"
  # Post-write verify: a copy that reported success and landed different bytes is what skill-install.sh exists for.
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
# The box tier is REBUILT, not added to: adding wedged upgrades (a withdrawn pack stays, the two-way `diff -r` fails, the
# script exits before wiring, and the withdrawn rule fires forever). Moving the old tier into the backup first makes
# that diff the right assertion. The old inject.d goes too (harbor#1010).
{ _aside "$DIR/$BOXREL" && _aside "$DIR/inject.d"; } || { log_end; exit 1; }
mkdir -p "$DIR/$BOXREL"
# The trailing `/.` matters: `cp -R src dest` into an existing destination silently makes dest/src and leaves the old
# files serving (skill-install.sh's header).
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
# harbor#978: name-note-create.sh judges the commands name-create.d rows name, and a pack's rows land there as
# name-create.d/<repo-id>.tsv (bin/pack.sh). Core's own rows (its create commands: bin/secret, harbor access add, a gcloud
# service account's display name) ship with the rule, as name-create.d/harbor.tsv. With no row the rule is off, which
# `harbor check --live` reports as check context.name-create.
NCROWS="$ROOT/contracts/name-create.tsv"
if [ -f "$NCROWS" ]; then
  mkdir -p "$DIR/name-create.d" && cp "$NCROWS" "$DIR/name-create.d/harbor.tsv.tmp.$$" && mv -f "$DIR/name-create.d/harbor.tsv.tmp.$$" "$DIR/name-create.d/harbor.tsv" \
    || { log_fail "could not write $DIR/name-create.d/harbor.tsv"; log_nofix "ls -ld $DIR/name-create.d"; log_end; exit 1; }
  il_manifest name-create.d/harbor.tsv
  log_ok "name-create rows: $(grep -cv '^#' "$NCROWS" | tr -d ' ') core command(s) in $DIR/name-create.d/harbor.tsv"
fi

# ── wiring ──────────────────────────────────────────────────────────────────
NEW="$(cat "$S")"
# Order against the engine's SessionStart entry does not matter (the harness concatenates additionalContext); both must be present.
NEW="$(printf '%s' "$NEW" | merge_hook /dev/stdin SessionStart "" "$ANNOUNCE_CMD")"
# The engine's six bindings render from its manifest with the derived matchers: a stale entry is replaced, never duplicated (harbor#271).
printf '%s' "$NEW" > "$IL_HK_IN"
NEW="$(hooks_run --settings --in "$IL_HK_IN" 2>"$IL_HK_ERR")" \
  || { log_fail "the engine's wiring did not render: $(sed -n 's/^.*FAIL[: ]*//p' "$IL_HK_ERR" | head -1)"; log_nofix "sh $HOOKS --check"; log_end; exit 1; }
il_write_json "$NEW" "$S" || { log_end; exit 1; }
log_ok "settings.json: the engine and the announce wired"
hooks_run --record >/dev/null 2>"$IL_HK_ERR" \
  || log_warn "settings.json is written, but what is wired was not recorded, so a binding removed by hand may come back: $(sed -n 's/^.*FAIL[: ]*//p' "$IL_HK_ERR" | head -1)"

# ── repo packs ──────────────────────────────────────────────────────────────
# SEEDED, NOT SYNCED: the packs are that repo's to edit afterwards. --projects overwrites (the old copy goes into the
# backup first), so status reports drift instead of healing it.
if [ "$PROJECTS" -eq 1 ] && [ -z "$PRIVINJ" ]; then
  log_skip "no private layer with a context-rules/: core ships no repo packs, so there is nothing to seed"
elif [ "$PROJECTS" -eq 1 ]; then
  REG="$REGISTRY"
  for _d in "$PRIVINJ"/*/; do
    [ -d "$_d" ] || continue
    _n="$(basename "$_d")"; case "$_n" in user) continue ;; esac
    _t="$(awk -F'\t' -v k="$_n" '$1 == k { print $2; exit }' "$REG" 2>/dev/null || true)"
    case "$_t" in '~/'*) _t="$HOME/${_t#'~/'}" ;; esac
    if [ -z "$_t" ] || [ ! -d "$_t" ]; then
      log_skip "$_n: no such project in the private projects.tsv"; continue
    fi
    # The repo's own scope folder (harbor#1010, D-65): context-rules/<name>/, which the engine reads in that repo.
    _tg="$_t/context-rules/$_n"
    for _old in "$_tg"; do
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
      [ ! -d "$_t/.claude/inject.d" ] || log_note "$_n: ${_t#"$HOME"/}/.claude/inject.d is still there and no longer read; the repo removes it"
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
  # The pinner's gate is not ours to pass: re-pinning blesses whatever the instruction surfaces say, so an installer run
  # from a session never does it (admission-install.sh). The claim must also be true: ask pin-instructions --check (the
  # manifest the SessionStart gate reads) rather than asserting a change, because this installer is idempotent and a
  # spurious re-pin demand is a false positive (§2.11). No pin or cannot check is said plainly. Under deploy the re-pin is
  # deploy's own step (#285).
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
