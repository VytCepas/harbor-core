#!/usr/bin/env sh
case "${1:-}:${HARBOR_ADMISSION_DISABLE:-${HELM_DISABLE_FLOOR:-0}}" in --box:1) exit 0 ;; esac
# govern-hook.sh (harbor#7) — just-in-time governance. Inject the rule at the
# moment it applies, instead of paying for it in every session's prefix.
#
#   echo '<hook json>' | sh bin/govern-hook.sh          read the event from stdin
#   sh bin/govern-hook.sh --self-test                   parse + emit, no harness
#   echo '<hook json>' | sh <cfg>/bin/govern-hook.sh --box   the box-wired merge gate (harbor#516)
#
# THE ARGUMENT IS TIMING, NOT TOKEN ECONOMY, and getting that backwards is how
# this design would be justified on a false premise. A hook that fires N times
# costs N injections landing AFTER the cached prefix; ~/.claude/CLAUDE.md is paid
# once inside it. On raw tokens the hook can easily lose. What it buys instead is
# measured: a constraint in the ambient surface is read past, and the same
# constraint delivered in-turn changes behaviour. This box produced both halves
# on 2026-08-07 — the `HELM FLOOR: instruction surfaces changed since pinning`
# banner fired at SessionStart and was ignored, while a guard-bash.sh denial
# arriving mid-turn redirected the work immediately. Plus the part no prefix can
# do at all: CLAUDE.md cannot stop a commit and a hook can.
#
# CONDITIONAL OR NOTHING. Every branch below computes its text from real state
# and prints ABSOLUTELY NOTHING when it finds none. CONSTITUTION §2.11 — a false
# positive is a defect, not safety; a guard that fires on ordinary work is a
# guard that gets switched off. A post-merge reminder that appears after a
# no-op merge is exactly that, so the reminders here are restricted to
# MERGE-CONSEQUENT local state (branches and worktrees the merge just retired)
# rather than a generic hygiene checklist that would be true at any moment.
#
# STATELESS, BY DESIGN AND BY MEASUREMENT. It reads stdin and the git index and
# writes no file, no lock, no counter. Four to five Claude Code sessions run
# concurrently on this machine and `hostname` here is unstable — it answers
# `Mac` intermittently, which has already forked host-sharded ledgers in this
# estate. Any hook that accumulated shared state would inherit that fork.
#
# NO guard-lib.sh, DELIBERATELY. This is plugin payload for a repo, not floor
# payload for the box: contracts/host-profile.md's D7 says a governed repo must
# work with no upstream platform installed, and sourcing the floor's library would make
# this hook require the floor. It reimplements the two lines it needs.
#
# --box (harbor#516): floor-install ALSO wires this file box-level, on PreToolUse
# Bash, because the repo pack only reaches sessions whose project dir is this
# repo, and every merge in 30 days ran from somewhere else. In that mode the
# target repo comes from the call: a `-R` slug mapped to its checkout under the
# port root, else the call's working folder. Only REGISTERED projects
# (inject.d/projects.tsv) run their bin/gate-merge-check.sh, and a session standing in
# the repo is left to the repo pack, so the merge is checked once.
#
# FAIL-OPEN EVERYWHERE. No jq, malformed JSON, a git call that errors, a
# detached HEAD, a non-repo cwd — every one of them exits 0 having printed
# nothing. A hook whose failure mode is noise is a hook that gets removed.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<3{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
# ── stdin, and the reason there is no jq hard dependency ────────────────────
# annotate-web.sh takes the same position: without jq we cannot BUILD valid JSON
# for arbitrary text, so the choice is a fixed safe string or silence. Here it
# is silence, because unlike the external-content banner nothing here is a
# safety boundary — a missed reminder costs a reminder.
#
# `--note` PRINTS THE TEXT AND NOT THE ENVELOPE (harbor#173). hooks/injection-rule/injection-rule.sh
# is the engine that now carries every other just-in-time rule in this estate,
# and its `run:` contract is "stdout is the note". This branch computes exactly
# what it always computed and skips the jq wrapper, so the merge governance below
# reaches a session through the same declarative pack mechanism as everything
# else instead of needing its own line in a settings file. Nothing else changes:
# the same matcher, the same conditionals, the same silence.
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

# ── PROVENANCE, AND WHY A LABEL WOULD NOT HAVE DONE ─────────────────────────
# Every note below is stamped with this session's governance token, derived by
# the sibling govern-token.sh from a box-local salt plus the session id. The
# reason is a measured one: bin/annotate-web.sh carries FETCHED WEB PAGES
# through a byte-identical `hookSpecificOutput.additionalContext` envelope, so
# a page containing `[HARBOR GOVERNANCE]` is indistinguishable from this file's
# output by inspection. A self-label is exactly what an attack writes. The salt
# is not in the fetched content and cannot be.
#
# EMPTY IS FINE AND IS THE DEFAULT. With no salt initialised the stamp is
# omitted and every note still says something true. A provenance mechanism that
# turned reminders OFF when unconfigured would be a worse failure than the one
# it prevents.
SID="$(field '.session_id')"
TOK=''
[ -x "$SELF_DIR/govern-token.sh" ] || [ -f "$SELF_DIR/govern-token.sh" ] && \
  TOK="$(sh "$SELF_DIR/govern-token.sh" --token "$SID" 2>/dev/null || true)"
STAMP='[HARBOR GOVERNANCE]'
[ -n "$TOK" ] && STAMP="[HARBOR GOVERNANCE $TOK]"

# ── PreCompact AND SubagentStart LEFT THIS FILE (harbor#173 · A1) ───────────
# They were here, they worked, and they were in the wrong building. Both are
# UNIVERSAL — every session compacts and every session spawns subagents, in every workload repo
# exactly as in harbor — while this file is harbor
# payload that only ever runs where harbor is the repo. Wired here they reached
# one repo of four; as declarative packs under `inject.d/box/` they reach every
# session on the box, and their text is one sentence to edit rather than a shell
# branch to re-test.
#
# WHAT IS LEFT IS THE PART THAT COULD NOT MOVE. The merge notes are computed —
# which local branches this merge just retired, which of those a worktree is
# pinning, how far behind origin the checkout now is — and contracts/hooks.md
# gives the reason no other layer can reach it: a PR merge is server-side, so no
# local git process runs and no `post-merge` git hook fires, in this repo or any
# repo, ever. hooks/injection-rule/injection-rule.sh calls back into this file through `--note`.
TOOL="$(field '.tool_name')"
case "$TOOL" in Bash|Monitor) ;; *) exit 0 ;; esac   # Monitor runs a shell command too (pass 14 E-4)
CMD="$(field '.tool_input.command')"
[ -n "$CMD" ] || exit 0

# ── the matcher (probe P4), and what it deliberately does not claim ─────────
# THREE FILTERS, AND THE FIRST VERSION OF THIS COMMENT OVERSTATED WHAT ONE OF
# THEM DID. Command-position splitting alone was claimed to handle a heredoc body
# quoting the phrase; it does not, because segments() splits on newline and a
# documentation line looks exactly like a command. An adversarial review
# reproduced that, plus `gh pr list --search "pr merge"` and prose inside
# `gh issue comment --body`. So: heredoc bodies are stripped, segments are split
# on ; && || | & and both parens plus newline, and the predicate is the first
# three WORDS being `gh pr merge` rather than a substring anywhere in the
# segment.
#
# `case` GLOBS, NOT grep, for the reason hooks/pre-commit already records at
# length: this machine's `grep` is a ugrep wrapper carrying `-I --ignore-files`.
# It reads stdin fine, but a matcher whose behaviour depends on which grep is
# first in PATH is a matcher that means something different on the CI runner,
# and `case` is POSIX shell that forks nothing and has no flavour.
#
# KNOWN HOLES, ENUMERATED RATHER THAN PAPERED OVER (P4). Not caught: a shell
# alias or function (`ghm 172`), the program in a variable (`$GH pr merge`),
# backslash-newline continuation inside the phrase, and a segment reached only
# through `xargs` or `find -exec`. Each is asserted as a MISS in
# tests/context/govern-hook/govern-hook.test.sh, so the hole is a pinned fact rather than an
# assumption someone later mistakes for coverage.
# THE HEREDOC BODY IS NOT CODE, and stripping it is the only thing that makes
# the rest of this honest. segments() splits on newline, so a documentation line
# reading `gh pr merge 172 --squash is what we ran yesterday` inside a heredoc is
# indistinguishable from a command by position alone — this file's own comment
# claimed command-position splitting fixed that, and an adversarial review
# demonstrated it did not. Bodies are dropped between `<<MARKER` and the marker
# line, which is the shape git commit messages, notes files and inline scripts
# actually use here.
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
# THE SUBCOMMAND, NOT A SUBSTRING. The first cut asked whether a `gh` segment
# CONTAINED `pr merge` anywhere, which fired on `gh pr list --search "pr merge"`,
# on `gh issue comment --body "…to pr merge this"`, and on any API call whose
# payload mentioned merging. Verified, all three. The predicate is now the first
# three WORDS of the segment, so the phrase has to be the invocation rather than
# an argument.
is_merge_cmd() { # <segment> -> 0 when this is genuinely `gh pr merge …`
  _s="$(printf '%s' "$1" | tr -s '[:space:]' ' ')"
  _s="${_s# }"
  case "$_s" in
    'gh pr merge'|'gh pr merge '*) ;;
    *) return 1 ;;
  esac
  # `--help` renders documentation and merges nothing. A reminder about the merge
  # backstop delivered to someone reading the manual is noise by definition.
  case " $_s " in *' --help '*|*' -h '*|*' --help'|*' -h') return 1 ;; esac
  return 0
}
# ── WHAT A SINGLE `gh pr merge` INVOCATION IS ACTUALLY AIMED AT ─────────────
# merge_target <segment> -> "<repo>\t<target>", either half possibly empty.
#
# gh's own synopsis is `gh pr merge [<number> | <url> | <branch>] [flags]`, so the
# target is the FIRST POSITIONAL — and finding the first positional means knowing
# which flags consume the next word, or `--subject 42 261` reports #42.
#
# THE VALUE-TAKING FLAG LIST IS A COPY OF gh's INTERFACE, which is the kind of
# copy that rots silently (T2). It is not left to rot: tests/context/govern-hook/govern-hook.test.sh reads
# `gh pr merge --help` and fails when gh grows a value-taking flag this list does
# not carry, so the drift is loud instead of a wrong verdict about a wrong PR.
merge_target() {
  printf '%s' "$1" | tr -s '[:space:]' '\012' | awk '
    BEGIN { skip = 0; repo = ""; tgt = ""; n = 0
            split("-R --repo --subject --body -b --body-file -F --match-head-commit --author-email", v, " ")
            for (i in v) val[v[i]] = 1 }
    # EMPTY RECORDS DO NOT COUNT. `segments()` splits on `;&|()`, so a segment
    # after `&&` arrives with a LEADING SPACE, which `tr` turns into a leading
    # newline and awk into an empty first field — pushing `merge` itself into the
    # positional slot and making the target the literal word "merge". That is the
    # incident command from harbor#254, and it degraded to a note while the
    # simple spelling denied correctly. Caught by running the installed path.
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

# _pr_of_ref <repo> <url-or-branch> -> the PR number, or empty.
# A URL is parsed rather than fetched — `…/pull/N` is the number, and asking the
# network for something already written down is a round-trip that can fail and
# turn a real verdict into a fault. A BRANCH has to be resolved, and gh is the
# only thing that can.
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
BASE="${HARBOR_CI_BASE_BRANCH:-${HARBOR_BASE_BRANCH:-main}}"

emit() { # <event> <model-text> [user-line] — or nothing at all
  [ -n "$2" ] || return 0
  # --note: the caller is hooks/injection-rule/injection-rule.sh, whose contract is "stdout is the
  # note". The systemMessage half has no equivalent there and is dropped rather
  # than smuggled into the model's copy — a line written for the operator that
  # arrives as model context is a line addressed to the wrong reader.
  if [ "$NOTE_ONLY" = 1 ]; then printf '%s\n' "$2"; return 0; fi
  # `systemMessage` GOES TO THE HUMAN, NOT THE MODEL, and it is available on
  # every event. It was missed on the first pass and it matters more than any
  # other field here, because it sidesteps the trust question outright: a line
  # the operator reads never has to be believed by the model. So anything whose
  # real audience is the person gets both channels, and the model's copy stays
  # a FINDING rather than an instruction — P1 measured a session correctly
  # refusing to take tool-channel text as a directive, and that is the right
  # behaviour to design around rather than to argue with.
  if [ -n "${3:-}" ]; then
    jq -cn --arg e "$1" --arg c "$STAMP $2" --arg m "$3" \
      '{systemMessage:$m,hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
  else
    jq -cn --arg e "$1" --arg c "$STAMP $2" \
      '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
  fi
}

# deny <reason> — the ONE blocking output in this file, PreToolUse only
# (contracts/hooks.md: "the only one that can block"; `permissionDecision` is
# accepted on no other event). Exit status stays 0 — a decision travels on
# stdout, exactly as guard-cloud.sh and guard-destroy.sh emit theirs; exit 2
# would be the floor's channel, and this file is repo payload, not floor payload.
#
# WHY `deny` AND NOT `ask`. An `ask` prompts the operator, and an operator who
# wants this merge will approve it — leaving no record anywhere that a red PR was
# merged deliberately. `gate-merge-check.sh --merge --force` writes that decision into
# the merge commit, which is the one place it survives the scrollback, so the
# deny's job is to route to it rather than to substitute for it. It also survives
# a subagent, where an `ask` with no human attached is toothless.
#
# ── AND IT HAS TO SURVIVE THE ROUTE THE OPERATOR ACTUALLY RUNS ───────────────
# Found by review, not by this file's suite, and it is §2.6 exactly: the suite
# fired the hook DIRECTLY while production goes through
# `context-rules/harbor/merge-note.sh`, which execs `govern-hook.sh --note` because
# `run:` packs contract that stdout IS the note. So a deny degraded to prose,
# `inject-hook.sh` wrapped that prose as additionalContext, and every red PR
# still merged — with a green suite either side of it. A gate that is inert on
# the installed path is the decorative gate harbor#254 is about, one layer down.
#
# The sentinel is the fix: `--note` prints a line the ENGINE recognises, and
# hooks/injection-rule/injection-rule.sh turns it back into a real permissionDecision on PreToolUse
# (and refuses to pretend on every other event, where the harness has no channel
# for one). contracts/injection-rule.md carries the contract.
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
  [ -f "$SELF_DIR/guard-lib.sh" ] || return 0
  ( set +eu; FLOOR_TOOL="${TOOL:-}"; FLOOR_IN="$PAYLOAD"; . "$SELF_DIR/guard-lib.sh"
    floor_log_decision govern "$1" "$2.meta" ) >/dev/null 2>&1 || :
}

# ── --box: which repo a merge belongs to (harbor#516) ───────────────────────
# _registered <tree>: a row in the box tier's projects.tsv, or a worktree of one. The
# registry is the trust boundary, as for inject-hook's `scope: box`: a merge
# naming a cloned third-party repo must not run that repo's script in a hook.
_registered() {
  # Beside the box tier, which moved in harbor#1010; the old place is read while no new one is installed.
  _reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-rules/user/projects.tsv"
  [ -f "$_reg" ] || _reg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/inject.d/projects.tsv"
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
  if [ -n "$PROJ" ] && [ "$(_owner "$PROJ")" = "$_bt" ]; then  # either layout carries the pack (harbor#1010)
    for _mn in "$PROJ"/context-rules/*/merge-note.sh "$PROJ/.claude/inject.d/merge-note.sh"; do [ ! -f "$_mn" ] || return 0; done
  fi
  printf '%s' "$_bt"
}
# _owner <tree>: the main checkout it belongs to, physical; itself when it is one.
_owner() {
  _oc="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$_oc" in */.git) (cd "${_oc%/.git}" 2>/dev/null && pwd -P) || true ;; esac
  return 0
}

# ════════════════════════════════════════════════════════════════════════════
# BEFORE `gh pr merge` — PreToolUse
#
# THIS CHANNEL IS CONFIRMED — probe P1 passed 2026-08-07, a nonce injected here
# came back verbatim through a real `claude -p --settings` session. (This comment
# said the opposite until an adversarial review found it contradicting
# contracts/hooks.md inside the same commit.)
#
# The failure mode was still chosen before the feature, and it is why P1 failing
# would have cost nothing: an unavailable channel means the merge proceeds
# exactly as today. NOT a blanket permissionDecision:"ask" — that one also works
# and would interrupt EVERY merge to deliver a reminder, buying a gate nobody
# asked for at the price of being routinely dismissed.
#
# ── harbor#254 · THE REMINDER BECAME A VERDICT, AND ONLY WHEN THERE IS ONE ───
# On 2026-08-21 the backstop refused PR #253 and the PR merged in the same
# command:
#
#   sh bin/gate-merge-check.sh 253 2>&1 | tail -2 && gh pr merge 253 --squash …
#
# A pipeline's exit status is its LAST command's, so `tail`'s 0 satisfied the
# `&&` and the refusal was decorative. Nothing was wrong with gate-merge-check.sh —
# it found the pending check, printed REFUSED and exited nonzero. The defect is
# the TWO-STEP: a gate that depends on the caller reading the exit status of the
# right process is a gate that works until somebody writes a pipeline. A note
# reminding the caller that a backstop exists cannot fix that, because the caller
# had already run it.
#
# BOTH REMEDIES THE TICKET PROPOSED WERE ALREADY IN THE TREE, which is why this
# arm is the fix instead of a new script. `bin/merge.sh <pr>` — "one command that
# runs the backstop and merges only on a pass" — is `gate-merge-check.sh --merge`,
# which has done exactly that in one process since 6e038d3. And `REFUSED` has
# been on stderr since that same commit: the incident redirected `2>&1` INTO the
# pipe, so moving it would have changed nothing. Both are recorded on the issue.
#
# So the verdict is computed HERE, at the moment of the merge, where no caller
# composes it and no pipeline can drop it. The three properties that keep it from
# becoming the dismissed interrupt the comment above rejects:
#
#   silent on a pass    a green PR sees the same note it saw before, no decision
#   deny on a refusal   with merge-check's own text, naming --force as the route
#   fail-open           no gh, no PR number, offline, the tool absent → note only
#
# The cost is one `gh pr checks` round-trip per merge (~1s, once), and the oracle
# stays gate-merge-check.sh rather than a second reading of the same checks (T2).
# ════════════════════════════════════════════════════════════════════════════
if [ "$EVENT" = PreToolUse ] && matches gh 'pr merge'; then
  note=''; user=''
  # Conditional on the tool EXISTING. In a repo with no gate-merge-check.sh there is
  # no advice to give, and inventing one would be a citation to nothing.
  if [ "$BOX" = 1 ] || [ -f "$REPO/bin/gate-merge-check.sh" ]; then
    note="A PR merge is about to run. This repo owns bin/gate-merge-check.sh, the backstop for the day branch protection lapses silently — a private repo on a free plan gets 403 from the protection endpoint and every rule stops applying with nothing turning red. It answers both questions: sh bin/gate-merge-check.sh <pr> and sh bin/gate-merge-check.sh --protection."
    case " $(printf '%s' "$CMD" | tr -s '[:space:]' ' ') " in
      *' --admin '*|*' --admin')
        note="$note GitHub's --admin bypasses required checks and leaves no record of the decision anywhere but the audit log; gate-merge-check.sh --merge --force writes the override into the merge commit instead, which is where the question 'was this merged red, and did someone decide that?' is answerable six weeks later." ;;
    esac

    # ── EVERY INVOCATION, AND ITS OWN TARGET (PR #262 review, P1) ────────────
    # The first cut ran one greedy `sed` over the WHOLE command and kept the
    # first number it found. Three ways that is wrong, and each one decides about
    # a PR that is not the one being merged:
    #
    #   gh pr merge 10 && gh pr merge 20     greedy `.*` keeps only 20, and 10
    #                                        executes FIRST, unchecked
    #   gh pr merge https://…/pull/5         no bare digit, so it silently fell
    #                                        back to the CURRENT BRANCH's PR
    #   gh pr merge -R other/repo 7          checked #7 in THIS repo
    #
    # A gate that reports on the wrong PR is worse than none: it prints a verdict
    # the reader believes. So each merge segment is parsed on its own, with its
    # own `-R`, and the loop denies on the FIRST refusal it finds.
    _verdict=''; _vpr=''; _vtext=''; _passed=''; _faults=''; _scoped=''; _vdir=''
    while IFS= read -r _seg; do
      [ -n "$_seg" ] || continue
      is_merge_cmd "$_seg" || continue
      # `--disable-auto` DOES NOT MERGE (PR #262 review, P2). gh's own help:
      # "Disable auto-merge for this pull request". Denying it stops the operator
      # from CANCELLING a queued auto-merge at exactly the moment the PR is red,
      # which is the §2.11 false positive in its purest form — the gate blocking
      # the remedy. `--auto` is left in scope deliberately: it merges later, on
      # someone else's schedule, which is the case for checking now.
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
      # AN UNRESOLVABLE TARGET IS NOT A PASS AND NOT THE CURRENT BRANCH. Only an
      # invocation with NO operand at all means "the PR of this branch", which is
      # gh's documented behaviour; anything else that will not resolve is a
      # question this hook cannot answer, and it says so instead of guessing.
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
      # Captured, never piped: piping is the defect this arm exists to close, and
      # under `set -e` a nonzero exit inside a substitution would end the hook
      # and fail OPEN silently — the one failure mode a gate cannot have.
      if [ -n "$_trepo" ]; then
        _mc="$(cd "$_TDIR" && HARBOR_SCOPE_REPO="$_trepo" sh bin/gate-merge-check.sh "$_pr" 2>&1)" && _rc=0 || _rc=$?
      else
        _mc="$(cd "$_TDIR" && sh bin/gate-merge-check.sh "$_pr" 2>&1)" && _rc=0 || _rc=$?
      fi
      # ── A VERDICT IS EXIT 1. EVERYTHING ELSE IS A FAULT ────────────────────
      # gate-merge-check.sh already separates the two and this arm has to honour the
      # distinction, because collapsing them makes a broken tool block every
      # merge — §2.11's false positive, on the gate. Measured while building
      # this: a fixture whose gate-merge-check.sh was a one-line stub exited 127
      # (`x: command not found`) and the first draft denied on it, which would
      # deny every merge in any repo whose backstop is missing a dependency.
      #   1  refused — a real verdict about a real PR
      #   2  usage or tooling: gh absent, no PR number, repo unresolvable
      #   *  the script itself is broken
      # A fault FAILS OPEN, and says so in the note: a gate that cannot run and
      # stays quiet is indistinguishable from one that passed, which is the same
      # "unknown is not ok" argument gate-merge-check.sh makes about protection.
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

  # NO DOC-STALENESS GATE HERE, AND THAT IS A MEASURED DECISION rather than an
  # omission. One was built and cut the same hour; docs/reports/rejected-approaches.md carries the
  # numbers. Short version: "a tracked doc cites a path this branch changed"
  # selected 20 documents on a 13-file branch, and narrowing it to a markdown
  # link — harbor's own T3 citation form — made it WORSE at 40, because T3
  # requires cited paths to resolve and the docs therefore link bin/ scripts
  # everywhere on purpose. The computable part of "the docs drifted" is already
  # three lint rules that run at COMMIT time, which is earlier and cheaper than
  # merge.

  [ -z "$note" ] || _log advise merge-note
  emit PreToolUse "$note" "$user"
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# AFTER `gh pr merge` — PostToolUse
#
# THE ONLY MOMENT WHERE A HARNESS HOOK IS STRICTLY NECESSARY. A PR merge happens
# server-side: no local git process runs, so no `post-merge` git hook can fire —
# not in this repo, not in any repo, ever. Everything else in the layer split
# has a git hook that reaches context for free through the Bash tool result.
#
# This channel IS confirmed on this box: annotate-web.sh injected its external
# content banner twice during the session that designed this.
# ════════════════════════════════════════════════════════════════════════════
if [ "$EVENT" = PostToolUse ] && matches gh 'pr merge'; then
  # THE COMMAND RAN IS NOT THE MERGE SUCCEEDED. This branch read the command and
  # never the result, so a refused merge — "Pull request is not mergeable" —
  # produced the full post-merge cleanup list. The header of this very file names
  # that as the failure it avoids: state "equally true before the merge, after a
  # FAILED merge, and on a Tuesday". It did it anyway, and an adversarial review
  # reproduced it in one call. `tool_response` is available on PostToolUse and
  # costs one field read.
  #
  # Matched on the RESPONSE rather than an exit code because the Bash tool's hook
  # payload does not carry one; gh's own refusal text is the available signal, so
  # the predicate is conservative — anything that smells like a refusal silences
  # the branch. A missed reminder costs a reminder; a false one costs the hook.
  _resp="$(printf '%s' "$PAYLOAD" | jq -r '(.tool_response|tostring) // empty' 2>/dev/null || true)"
  case "$_resp" in
    *"not mergeable"*|*"Pull request is not"*|*"GraphQL"*|*"failed to"*|*"could not be"*|*"is not open"*|*"already merged"*|*"error:"*|*"HTTP 4"*|*"HTTP 5"*)
      exit 0 ;;
  esac
  # MERGE-CONSEQUENT STATE ONLY. The tempting version of this hook prints a
  # hygiene checklist — uncommitted changes, stale docs/generated/status.md, unpushed commits —
  # and every one of those is equally true before the merge, after a failed
  # merge, and on a Tuesday. Firing on all of them would make the reminder
  # unfalsifiable and, worse, indistinguishable from wallpaper by its third
  # appearance. What a merge actually changes locally is which branches and
  # worktrees are now retired, so that is the entire subject.
  #
  # NO NETWORK. A hook must not fetch: it would add seconds to a tool call and
  # surprise a user on a metered link. The comparison is against the
  # origin/<base> ref already on disk, which can be stale — said out loud rather
  # than implied, because a reminder that quietly measured yesterday's remote is
  # a reminder that will be wrong exactly when it matters.
  cd "$REPO" 2>/dev/null || exit 0
  git rev-parse --verify --quiet "origin/$BASE" >/dev/null 2>&1 || exit 0

  # BY CONTENT, NOT ANCESTRY (harbor#213). `merge-base --is-ancestor` cannot see a
  # squash merge, which is how every PR in this repo lands, so this listing
  # silently under-reported: it named as "merged" only branches that arrived by
  # some other route, and every squash-merged branch — i.e. all of them — was
  # omitted. Unlike the other two sites this one refused nothing, which is why it
  # went unnoticed longest: an under-reporting reminder reads as a quiet week.
  #
  # ONE CALL FOR ALL BRANCHES, not one per branch. This runs at SessionStart, and
  # gate-merged-check.sh builds its patch-id index once per invocation — a call per
  # branch would rebuild it per branch and pay the cost that made memory-lint a
  # gate nobody could afford to run.
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

  # A worktree standing on a merged branch is the specific failure this estate
  # has already hit: `git worktree prune` does not clear one while its directory
  # exists, so an orphan from a dead session pins a merged branch undeletable.
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
  # DELIMITED, NOT SUBSTRING. `case "$merged" in *"$cur"*)` reported that an
  # UNMERGED `feat/x` was merged whenever a merged `feat/xy` existed — a false
  # factual claim about the operator's checkout, in the one branch whose entire
  # job is reporting real state. Reproduced in a scratch repo by an adversarial
  # review. `$merged` is a space-joined list, so the compare has to be against
  # padded delimiters.
  case " $merged " in
    *" $cur "*) [ -n "$cur" ] && note="$note You are standing on $cur, which is itself merged." ;;
  esac

  # THE SILENT PATH IS THE COMMON ONE AND THAT IS THE POINT. A merge of a branch
  # already pruned, from a checkout already current, prints nothing.
  # THE OPERATOR IS THE RIGHT AUDIENCE FOR THIS ONE. Deleting a branch or
  # retiring a worktree is their act, not the model's, and `systemMessage` puts
  # it in front of them without asking the model to believe anything. This
  # channel had been described as the most important field here while being
  # unreachable — `user` lost its only assignment when the doc gate was cut.
  _user=''
  [ -n "$merged" ] && _user="harbor: merged and still local — $merged"
  [ -z "${note# }" ] || _log advise merged-local
  emit PostToolUse "${note# }" "$_user"
  exit 0
fi

exit 0
