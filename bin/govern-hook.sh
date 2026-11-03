#!/usr/bin/env sh
case "${1:-}:${HARBOR_ADMISSION_DISABLE:-0}" in --box:1) exit 0 ;; esac
# govern-hook.sh (harbor#7) — just-in-time governance. Inject the rule at the
# moment it applies, instead of paying for it in every session's prefix.
#
#   echo '<hook json>' | sh bin/govern-hook.sh          read the event from stdin
#   sh bin/govern-hook.sh --self-test                   parse + emit, no harness
#   echo '<hook json>' | sh <cfg>/bin/govern-hook.sh --box   the box-wired merge gate (harbor#516)
#
# Timing, not token economy: a hook costs N injections after the cached prefix, so on raw tokens it can lose. What it buys: a constraint delivered in-turn changes behaviour where the same one in the ambient surface is read past, and CLAUDE.md cannot stop a commit while a hook can.
# Conditional or nothing (§2.11): every branch computes its text from real state and prints nothing when it finds none; post-merge reminders cover merge-consequent local state only.
# Stateless: reads stdin and the git index, writes no file, lock or counter (concurrent sessions, an unstable `hostname`).
# No hard dependency on library-admission.sh (contracts/host-profile.md D7: a governed repo must work with no platform installed); _log reads it lazily and is silent without it.
# --box (harbor#516): floor-install also wires this box-level on PreToolUse Bash, since the repo pack only reaches sessions in this repo. The target repo comes from a `-R` slug mapped to its checkout under the port root, else the call's working folder; only REGISTERED projects (the box tier's projects.tsv, see _registered) run their bin/gate-merge-check.sh, and a session in the repo is left to the repo pack, so a merge is checked once.
# Fail-open everywhere: no jq, bad JSON, a failing git call, a detached HEAD or a non-repo cwd all exit 0 printing nothing.
# Removed notes: docs/explanation/code-cases/bin-govern-hook.md
set -eu

# --help before any work (S4, harbor#140); the text is this file's own header, read at runtime.
case "${1:-}" in
  -h|--help) awk 'NR<3{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# stdin, and no hard jq dependency: without jq we cannot build valid JSON, so the choice is silence, and nothing here is a safety boundary (a missed reminder costs a reminder).
# `--note` prints the text, not the envelope (harbor#173): hooks/injection-rule/injection-rule.sh's `run:` contract is "stdout is the note". Same matcher, conditionals and silence.
NOTE_ONLY=0
BOX=0
PAYLOAD=''
case "${1:-}" in
  --note)      NOTE_ONLY=1; PAYLOAD="$(cat)" ;;
  --box)       BOX=1; PAYLOAD="$(cat)" ;;
  --self-test) PAYLOAD="$(cat)" ;;
  '')          PAYLOAD="$(cat)" ;;
  *)           exit 0 ;;
esac
[ -n "$PAYLOAD" ] || exit 0
# --box runs before EVERY Bash call, so no fork until the word is there: the
# matcher needs a literal `merge`, so this filter drops nothing it would fire on.
if [ "$BOX" = 1 ]; then case "$PAYLOAD" in *merge*) ;; *) exit 0 ;; esac; fi
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$PAYLOAD" | jq -r "$1 // empty" 2>/dev/null || true; }

EVENT="$(field '.hook_event_name')"
# The box wiring is PreToolUse only: the post-merge notes stay with the repo pack.
[ "$BOX" = 0 ] || [ "$EVENT" = PreToolUse ] || exit 0
# ${0%/*}, not $(dirname): a hook must not fall back to the session's cwd (harbor#810).
case "$0" in */*) _sd="${0%/*}" ;; *) _sd=. ;; esac
SELF_DIR="$(CDPATH='' cd -- "$_sd" 2>/dev/null && pwd || printf '%s' "$_sd")"

# PROVENANCE: every note is stamped with this session's token from govern-token.sh (box-local salt plus session id), because annotate-web.sh carries fetched pages through a byte-identical envelope and a self-label is exactly what an attack writes. With no salt the stamp is omitted and notes still say something true.
SID="$(field '.session_id')"
TOK=''
[ -x "$SELF_DIR/govern-token.sh" ] || [ -f "$SELF_DIR/govern-token.sh" ] && \
  TOK="$(sh "$SELF_DIR/govern-token.sh" --token "$SID" 2>/dev/null || true)"
STAMP='[HARBOR GOVERNANCE]'
[ -n "$TOK" ] && STAMP="[HARBOR GOVERNANCE $TOK]"

# PreCompact and SubagentStart left this file (harbor#173 A1): they are universal and live as packs under inject.d/box/. What stays is computed: which local branches the merge retired, which a worktree pins, how far behind origin the checkout is. A PR merge is server-side, so no local `post-merge` hook ever fires (contracts/hooks.md); hooks/injection-rule/injection-rule.sh calls back here through `--note`.
TOOL="$(field '.tool_name')"
case "$TOOL" in Bash|Monitor) ;; *) exit 0 ;; esac   # Monitor runs a shell command too (pass 14 E-4)
CMD="$(field '.tool_input.command')"
[ -n "$CMD" ] || exit 0

# the matcher (probe P4): heredoc bodies are stripped, segments split on ; && || | & parens and newline, and the predicate is the first three WORDS being `gh pr merge`, not a substring. Each step fixed a reproduced false positive: a heredoc line reading `gh pr merge 172 ...`, `gh pr list --search "pr merge"`, prose in `gh issue comment --body`.
# `case` globs, not grep: grep here is a ugrep wrapper, and a matcher that depends on which grep is first in PATH means something else on CI.
# Known holes, each asserted as a MISS in tests/context/govern-hook/govern-hook.test.sh: a shell alias or function, the program in a variable (`$GH pr merge`), backslash-newline inside the phrase, a segment reached only through xargs or find -exec.
# Heredoc bodies are dropped between `<<MARKER` and the marker line.
strip_heredocs() {
  printf '%s\n' "$1" | awk '
    BEGIN { skip = 0 }
    skip == 1 { if ($0 == marker) { skip = 0 }; next }
    {
      print
      if (match($0, /<<-?[[:space:]]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*/)) {
        m = substr($0, RSTART, RLENGTH)
        gsub(/^<<-?[[:space:]]*/, "", m); gsub(/['"'"'"]/, "", m)
        marker = m; skip = 1
      }
    }'
}
segments() { # split into candidate command-position segments
  strip_heredocs "$1" | tr '\n;&|()' '\012\012\012\012\012\012\012'
}
# The subcommand, not a substring: the first three WORDS of the segment, so the phrase has to be the invocation rather than an argument.
is_merge_cmd() { # <segment> -> 0 when this is genuinely `gh pr merge …`
  _s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  _s="${_s# }"
  case "$_s" in
    'gh pr merge'|'gh pr merge '*) ;;
    *) return 1 ;;
  esac
  # `--help` renders documentation and merges nothing.
  case " $_s " in *' --help '*|*' -h '*|*' --help'|*' -h') return 1 ;; esac
  return 0
}
# merge_target <segment> -> repo TAB target, either possibly empty. The target is gh's first positional, so the parser must know which flags consume the next word. That value-taking flag list is a copy of gh's interface (T2): tests/context/govern-hook/govern-hook.test.sh reads `gh pr merge --help` and fails when gh grows one this list lacks.
merge_target() {
  printf '%s' "$1" | tr -s '[:space:]' '\012' | awk '
    BEGIN { skip = 0; repo = ""; tgt = ""; n = 0
            split("-R --repo --subject --body -b --body-file -F --match-head-commit --author-email", v, " ")
            for (i in v) val[v[i]] = 1 }
    # Empty records do not count: a segment after `&&` arrives with a leading space, which becomes an empty first field and would push `merge` into the positional slot (the incident command of harbor#254).
    /^$/ { next }
    { n++ }
    n <= 3 { next }                       # gh, pr, merge
    skip == 1 { skip = 0; next }
    /^-/ {
      # `-Rowner/repo`: cobra accepts the attached short form, and it named no repo here.
      if ($0 ~ /^-R[^-=]/) { repo = substr($0, 3); next }
      k = $0; sub(/=.*/, "", k)
      if (k == "-R" || k == "--repo") {
        if ($0 ~ /=/) { r = $0; sub(/^[^=]*=/, "", r); repo = r } else { want_repo = 1 }
        next
      }
      if ((k in val) && $0 !~ /=/) skip = 1
      next
    }
    want_repo == 1 { repo = $0; want_repo = 0; next }
    tgt == "" { tgt = $0 }
    END { printf "%s\t%s", repo, tgt }'
}

# _pr_of_ref <repo> <url-or-branch> -> the PR number, or empty. A URL is parsed, not fetched (a round-trip can turn a verdict into a fault); a branch needs gh.
_pr_of_ref() {
  case "$2" in
    *://*/pull/*)
      _n="${2##*/pull/}"; _n="${_n%%[!0-9]*}"
      case "$_n" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$_n" ;; esac
      return 0 ;;
  esac
  _pr_of_branch "$1" "$2"
}

# _pr_of_branch <repo> <branch-or-empty> -> the PR number for that ref, or empty.
_pr_of_branch() {
  command -v gh >/dev/null 2>&1 || { printf ''; return 0; }
  if [ -n "$1" ]; then
    _n="$(cd "${_TDIR:-$REPO}" 2>/dev/null && gh pr view ${2:+"$2"} --repo "$1" --json number -q .number 2>/dev/null || true)"
  else
    _n="$(cd "${_TDIR:-$REPO}" 2>/dev/null && gh pr view ${2:+"$2"} --json number -q .number 2>/dev/null || true)"
  fi
  case "$_n" in ''|*[!0-9]*) printf '' ;; *) printf '%s' "$_n" ;; esac
}

matches() { # <prog> <phrase> — kept for the call sites; delegates to the above
  _hit=1
  while IFS= read -r _seg; do
    [ -n "$_seg" ] || continue
    is_merge_cmd "$_seg" && _hit=0
  done <<SEGS
$(segments "$CMD")
SEGS
  return "$_hit"
}

# ── repo resolution ─────────────────────────────────────────────────────────
# CLAUDE_PROJECT_DIR is what the harness sets for plugin hooks; cwd is the
# fallback for a hand-run or a self-test. Not a repo → nothing to say.
PROJ="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
REPO="$PROJ"
if [ "$BOX" = 1 ]; then
  # --box: the call's working folder outranks the project dir, which is where the
  # session started rather than where the merge runs. Empty is fine here: a `-R`
  # slug can still name the repo.
  _cwd="$(field '.cwd')"
  _ct="$(cd "${_cwd:-/nonexistent}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -z "$_ct" ] || REPO="$_ct"
else
  [ -n "$REPO" ] || exit 0
fi
BASE="${HARBOR_CI_BASE_BRANCH:-main}"

emit() { # <event> <model-text> [user-line] — or nothing at all
  [ -n "$2" ] || return 0
  # --note: the caller's contract is "stdout is the note"; the systemMessage half has no equivalent there and is dropped rather than put in the model's copy.
  if [ "$NOTE_ONLY" = 1 ]; then printf '%s\n' "$2"; return 0; fi
  # `systemMessage` goes to the human, not the model, so a line the operator reads never has to be believed by the model; the model's copy stays a FINDING, not an instruction (P1: a session correctly refused tool-channel text as a directive).
  if [ -n "${3:-}" ]; then
    jq -cn --arg e "$1" --arg c "$STAMP $2" --arg m "$3" \
      '{systemMessage:$m,hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
  else
    jq -cn --arg e "$1" --arg c "$STAMP $2" \
      '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
  fi
}

# deny <reason> — the ONE blocking output in this file, PreToolUse only (contracts/hooks.md). Exit stays 0: the decision travels on stdout, as in admission-cloud.sh; exit 2 is the floor's channel and this is repo payload.
# Deny, not ask: an approved `ask` leaves no record that a red PR was merged deliberately, while `gate-merge-check.sh --merge --force` writes that into the merge commit; a deny routes to it and still binds a subagent.
# It must survive the installed route: production goes through context-rules/harbor/merge-note.sh, which execs `govern-hook.sh --note`, so a deny once degraded to prose and every red PR still merged under a green suite. `--note` therefore prints a sentinel line that hooks/injection-rule/injection-rule.sh turns back into a real permissionDecision on PreToolUse (contracts/injection-rule.md).
deny() {
  if [ "$NOTE_ONLY" = 1 ]; then printf 'HARBOR-DECISION deny: %s\n' "$1"; return 0; fi
  jq -cn --arg r "$STAMP $1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null || true
}

# THE DECISION LOG (harbor#957 item 4). Under --note the caller is inject-hook, which records the fire as
# g=inject; every other route records it here as g=govern, through the floor's writer. Read lazily and
# in a subshell, so the library cannot touch the verdict, and silent when there is no ledger.
_log() { # <deny|advise> <rule>
  [ "$NOTE_ONLY" = 1 ] && return 0
  [ -f "$SELF_DIR/library-admission.sh" ] || return 0
  # shellcheck disable=SC2034 # FLOOR_IN, FLOOR_TOOL: read by library-admission.sh
  ( set +eu; FLOOR_TOOL="${TOOL:-}"; FLOOR_IN="$PAYLOAD"; . "$SELF_DIR/library-admission.sh"
    floor_log_decision govern "$1" "$2.meta" ) >/dev/null 2>&1 || :
}

# ── --box: which repo a merge belongs to (harbor#516) ───────────────────────
# _registered <tree>: a row in the box tier's projects.tsv, or a worktree of one. The
# registry is the trust boundary, as for inject-hook's `scope: box`: a merge
# naming a cloned third-party repo must not run that repo's script in a hook.
_registered() {
  # Beside the box tier (harbor#1010).
  _reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-rules/user/projects.tsv"
  [ -f "$_reg" ] || return 1
  _me="$(cd "$1" 2>/dev/null && pwd -P || true)"
  _own="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$_own" in */.git) _own="$(cd "${_own%/.git}" 2>/dev/null && pwd -P || true)" ;; *) _own='' ;; esac
  while IFS="$(printf '\t')" read -r _rn _rp _rc; do
    case "$_rn" in ''|'#'*) continue ;; esac
    case "$_rp" in '~/'*) _rp="$HOME/${_rp#\~/}" ;; esac
    [ -d "$_rp" ] || continue
    _rp="$(cd "$_rp" 2>/dev/null && pwd -P || true)"
    if [ -n "$_rp" ] && { [ "$_rp" = "$_me" ] || [ "$_rp" = "$_own" ]; }; then return 0; fi
  done < "$_reg"
  return 1
}
# _checkout_of <[HOST/]OWNER/REPO>: the main checkout under the port root whose
# origin is that slug, or nothing. A worktree's .git is a file, so it is skipped.
_checkout_of() {
  _sl="$1"; case "$_sl" in */*/*) _sl="${_sl#*/}" ;; esac
  case "$_sl" in *[!A-Za-z0-9_./-]*|*/*/*|/*|*/|'') return 0 ;; */*) ;; *) return 0 ;; esac
  _want="$(printf '%s' "$_sl" | tr '[:upper:]' '[:lower:]')"
  for _d in "${PORT_ROOT:-$HOME/port}"/*/; do
    _d="${_d%/}"
    [ -d "$_d/.git" ] || continue
    _u="$(git -C "$_d" config --get remote.origin.url 2>/dev/null || true)"
    _u="${_u%/}"; _u="${_u%.git}"
    _us="$(printf '%s' "$_u" | awk -F'[/:]' 'NF >= 2 { print tolower($(NF - 1) "/" $NF) }')"
    [ "$_us" = "$_want" ] || continue
    (cd "$_d" 2>/dev/null && pwd -P) || true
    return 0
  done
  return 0
}
# _box_target <slug-or-empty>: the repo whose backstop judges this merge, or
# nothing. Nothing when it has no gate-merge-check.sh, is unregistered, or is the
# session's own repo with the merge pack in it (that pack checks it already).
_box_target() {
  if [ -n "$1" ]; then _bt="$(_checkout_of "$1")"; else _bt="$REPO"; fi
  [ -n "$_bt" ] || return 0
  # The OWNER's backstop decides: a worktree's copy can be stale or half-edited,
  # and a `.git` file naming a registered repo must not get its own script run.
  _bt="$(_owner "$_bt")"
  [ -n "$_bt" ] && [ -f "$_bt/bin/gate-merge-check.sh" ] || return 0
  _registered "$_bt" || return 0
  # Once: a session in that repo, or a worktree of it, with the merge pack is the pack's.
  if [ -n "$PROJ" ] && [ "$(_owner "$PROJ")" = "$_bt" ]; then
    for _mn in "$PROJ"/context-rules/*/merge-note.sh; do [ ! -f "$_mn" ] || return 0; done
  fi
  printf '%s' "$_bt"
}
# _owner <tree>: the main checkout it belongs to, physical; itself when it is one.
_owner() {
  _oc="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$_oc" in */.git) (cd "${_oc%/.git}" 2>/dev/null && pwd -P) || true ;; esac
  return 0
}

# BEFORE `gh pr merge` — PreToolUse (channel confirmed by probe P1: a nonce came back through a real `claude -p` session). Not a blanket permissionDecision ask, which would interrupt every merge to deliver a reminder.
# harbor#254: the backstop refused PR #253 and it merged in the same command, `gate-merge-check.sh 253 2>&1 | tail -2 && gh pr merge 253`: a pipeline's status is its last command's, so `tail`'s 0 satisfied the `&&`. A gate that relies on the caller reading the right exit status works until somebody writes a pipeline, so the verdict is computed HERE, at the merge, where no caller composes it. It does not become a dismissed interrupt: silent on a pass; deny on a refusal with merge-check's own text naming --force; fail-open when gh, the PR number, the network or the tool is absent. Cost: one `gh pr checks` round-trip per merge. The oracle stays gate-merge-check.sh, not a second reading of the same checks (T2).
if [ "$EVENT" = PreToolUse ] && matches gh 'pr merge'; then
  note=''; user=''
  # Conditional on the tool existing: with no gate-merge-check.sh there is no advice to give.
  if [ "$BOX" = 1 ] || [ -f "$REPO/bin/gate-merge-check.sh" ]; then
    note="A PR merge is about to run. This repo owns bin/gate-merge-check.sh, the backstop for the day branch protection lapses silently — a private repo on a free plan gets 403 from the protection endpoint and every rule stops applying with nothing turning red. It answers both questions: sh bin/gate-merge-check.sh <pr> and sh bin/gate-merge-check.sh --protection."
    case " $(printf '%s' "$CMD" | tr -s '[:space:]' ' ') " in
      *' --admin '*|*' --admin')
        note="$note GitHub's --admin bypasses required checks and leaves no record of the decision anywhere but the audit log; gate-merge-check.sh --merge --force writes the override into the merge commit instead, which is where the question 'was this merged red, and did someone decide that?' is answerable six weeks later." ;;
    esac

    # Every invocation, and its own target (PR #262 review): one greedy sed over the whole command kept the first number it found, so `gh pr merge 10 && gh pr merge 20` ran 10 unchecked, a URL fell back to the current branch's PR, and `-R other/repo 7` checked #7 here. Each merge segment is now parsed with its own `-R`, and the loop denies on the first refusal.
    _verdict=''; _vpr=''; _vtext=''; _passed=''; _faults=''; _scoped=''; _vdir=''
    while IFS= read -r _seg; do
      [ -n "$_seg" ] || continue
      is_merge_cmd "$_seg" || continue
      # `--disable-auto` does not merge: denying it would block cancelling a queued auto-merge on a red PR (§2.11, the gate blocking the remedy). `--auto` stays in scope: it merges later.
      case " $(printf '%s' "$_seg" | tr -s '[:space:]' ' ') " in
        *' --disable-auto '*|*' --disable-auto') continue ;;
      esac
      _t="$(merge_target "$_seg")"
      _trepo="${_t%%	*}"; _tgt="${_t#*	}"
      _TDIR="$REPO"
      if [ "$BOX" = 1 ]; then
        _TDIR="$(_box_target "$_trepo")"
        [ -n "$_TDIR" ] || continue
        _scoped=1
      fi
      # An unresolvable target is neither a pass nor the current branch: only an invocation with NO operand means this branch's PR; anything else that will not resolve is reported, not guessed.
      _pr=''
      case "$_tgt" in
        '')            _pr="$(_pr_of_branch "$_trepo" '')" ;;
        *[!0-9]*)      _pr="$(_pr_of_ref "$_trepo" "$_tgt")" ;;
        *)             _pr="$_tgt" ;;
      esac
      if [ -z "$_pr" ]; then
        _faults="$_faults ${_tgt:-<this branch>}"
        continue
      fi
      # Captured, never piped (piping is the defect this arm closes); under `set -e` a failing substitution would end the hook and fail open silently.
      if [ -n "$_trepo" ]; then
        _mc="$(cd "$_TDIR" && HARBOR_SCOPE_REPO="$_trepo" sh bin/gate-merge-check.sh "$_pr" 2>&1)" && _rc=0 || _rc=$?
      else
        _mc="$(cd "$_TDIR" && sh bin/gate-merge-check.sh "$_pr" 2>&1)" && _rc=0 || _rc=$?
      fi
      # A verdict is exit 1; everything else is a fault, and a fault FAILS OPEN and says so in the note. Collapsing them makes a broken tool block every merge (a stub gate-merge-check.sh exited 127 and the first draft denied on it, §2.11).
      # 1 refused: a real verdict about a real PR
      # 2 usage or tooling: gh absent, no PR number, repo unresolvable
      # other: the script itself is broken
      if [ "$_rc" -eq 1 ]; then
        _verdict=refuse; _vpr="$_pr"; _vtext="$_mc"; _vdir="$_TDIR"
        break
      elif [ "$_rc" -eq 0 ]; then
        _passed="$_passed #$_pr"
      else
        _faults="$_faults #$_pr(exit $_rc)"
      fi
    done <<MERGESEGS
$(segments "$CMD")
MERGESEGS

    # --box names the repo, since the session may be standing anywhere.
    _vwhere=''
    [ "$BOX" = 0 ] || _vwhere=" (in $_vdir)"
    if [ "$_verdict" = refuse ]; then
      _log deny merge-backstop
      deny "[check:gate.merge-backstop] The merge backstop refuses this merge, so it was not run.

$_vtext

Route$_vwhere: sh bin/gate-merge-check.sh --merge $_vpr — it re-checks and merges in ONE process, so no pipeline can drop the refusal (harbor#254; on 2026-08-21 one did, and the PR merged over a pending check). If the refusal is the wrong answer, sh bin/gate-merge-check.sh --merge $_vpr --force overrides it and writes the override into the merge commit, which is where 'was this merged red, and did someone decide that?' is answerable six weeks later."
      exit 0
    fi
    # --box with no in-scope merge: the repo pack or nothing speaks, never both.
    if [ "$BOX" = 1 ] && [ -z "$_scoped" ]; then exit 0; fi
    [ -n "$_passed" ] && note="$note The backstop was consulted for$_passed just now and passed."
    [ -n "$_faults" ] && note="$note The backstop could NOT be consulted for$_faults, so nothing was verified about that merge."
  fi

  # No doc-staleness gate here, by measurement: one was built and cut the same hour (docs/reports/rejected-approaches.md). "A tracked doc cites a path this branch changed" selected 20 documents on a 13-file branch, and narrowing it to markdown links made it 40. The computable part is already three lint rules at commit time.

  [ -z "$note" ] || _log advise merge-note
  emit PreToolUse "$note" "$user"
  exit 0
fi

# AFTER `gh pr merge` — PostToolUse. The one place a harness hook is strictly necessary: a PR merge is server-side, so no local git hook fires. Channel confirmed on this box (annotate-web.sh injects through it).
if [ "$EVENT" = PostToolUse ] && matches gh 'pr merge'; then
  # The command ran is not the merge succeeded: a refused merge once produced the full cleanup list. Matched on the tool_response text because the Bash hook payload carries no exit code; the predicate is conservative (a missed reminder costs a reminder, a false one costs the hook).
  _resp="$(printf '%s' "$PAYLOAD" | jq -r '(.tool_response|tostring) // empty' 2>/dev/null || true)"
  case "$_resp" in
    *"not mergeable"*|*"Pull request is not"*|*"GraphQL"*|*"failed to"*|*"could not be"*|*"is not open"*|*"already merged"*|*"error:"*|*"HTTP 4"*|*"HTTP 5"*)
      exit 0 ;;
  esac
  # Merge-consequent state only: a hygiene checklist is equally true before the merge, after a failed one and on a Tuesday, and turns into wallpaper. What a merge changes locally is which branches and worktrees are retired.
  # No network: the comparison is against the origin/<base> ref on disk, which can be stale, and the note says so.
  cd "$REPO" 2>/dev/null || exit 0
  git rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 || exit 0

  # By content, not ancestry (harbor#213): `merge-base --is-ancestor` cannot see a squash merge, so every squash-merged branch was omitted and the reminder read as a quiet week. One call for all branches: gate-merged-check.sh builds its patch-id index once per invocation.
  _mc="$SELF_DIR/gate-merged-check.sh"
  if [ -f "$_mc" ]; then
    _brs="$(git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null \
            | while IFS= read -r b; do
                [ -n "$b" ] || continue
                [ "$b" = "$BASE" ] && continue
                printf '%s\n' "$b"
              done || true)"
    if [ -n "$_brs" ]; then
      # shellcheck disable=SC2086
      merged="$(sh "$_mc" --repo "$REPO" "origin/$BASE" $_brs 2>/dev/null \
                | awk '$1 == "merged" { printf "%s ", $2 }' || true)"
    else
      merged=""
    fi
  else
    # The predicate is missing rather than wrong. Say nothing instead of falling
    # back to the ancestry test, whose answer here is known to be false.
    merged=""
  fi
  merged="${merged% }"

  # A worktree standing on a merged branch pins it undeletable: `git worktree prune` does not clear one while its directory exists.
  held=''
  if [ -n "$merged" ]; then
    for b in $merged; do
      _w="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$b" '
              /^worktree /{w=$2} /^branch /{ if ($2 == b) print w }' || true)"
      [ -n "$_w" ] && held="$held $b"
    done
    held="${held# }"
  fi

  behind="$(git rev-list --count "HEAD..origin/$BASE" 2>/dev/null || printf 0)"
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')"

  note=''
  [ -n "$merged" ] && note="Merged and still present locally: $merged. Delete with git branch -d, or sh bin/worktree.sh gc for the ones held by a worktree."
  if [ -n "$held" ]; then
    note="$note A worktree is standing on: $held. git worktree prune does not clear a worktree while its directory exists, so the branch stays undeletable until the worktree is retired — sh bin/worktree.sh retire."
  fi
  if [ "$behind" -gt 0 ] 2>/dev/null; then
    note="$note This checkout ($cur) is $behind commit(s) behind origin/$BASE as of the last fetch — this hook does no network I/O, so that count is only as fresh as your last fetch."
  fi
  # Delimited, not substring: `*"$cur"*` called an unmerged `feat/x` merged whenever a merged `feat/xy` existed. `$merged` is space-joined, so compare against padded delimiters.
  case " $merged " in
    *" $cur "*) [ -n "$cur" ] && note="$note You are standing on $cur, which is itself merged." ;;
  esac

  # The silent path is the common one: a merge of an already pruned branch from a current checkout prints nothing. The operator is the audience for `systemMessage` here: deleting a branch or retiring a worktree is their act.
  _user=''
  [ -n "$merged" ] && _user="harbor: merged and still local — $merged"
  [ -z "${note# }" ] || _log advise merged-local
  emit PostToolUse "${note# }" "$_user"
  exit 0
fi

exit 0
