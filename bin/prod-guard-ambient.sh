#!/usr/bin/env sh
set -eu
# B10 (harbor#56) — the ambient shim for yard's `prod_guard.py`.
#
# WHY A SHIM AND NOT A FORK. `prod_guard.py` is yard's file and owns the
# cloud/data destruction corpus by contract (bin/guard-bash.sh:6-8, which is why
# the floor's Bash guard deliberately omits that class). Editing an installed
# copy to add deferral would fork it, and a scaffolded copy silently diverging
# from its plugin is the exact defect fleet#199 exists to fix.
# So the copy stays byte-identical to the marketplace version — assertable, and
# asserted by prod-guard-test.sh — and the deferral lives here, in Helm, where
# the detect-and-defer doctrine (CONTRACTS/marker.md) already lives.
#
# WHY IT DEFERS AT ALL. Measured on Claude Code 2.1.220 (harbor#56, the run
# table): two PreToolUse hooks that both return `ask` produce ONE prompt, and
# the `permissionDecisionReason` the operator reads is the one from whichever
# hook COMPLETED LAST. The losing hook's reason is discarded silently. So two
# copies guarding one command is not a double prompt — it is a nondeterministic
# message, and a rule that fired but lost the race is indistinguishable from a
# rule that never fired. Exactly one guard must own the message per command.
#
# WHY NOT `permissionDecision: "defer"`. The docs list it, and it looks like the
# obvious mechanism. Measured, it is a distinct third code path: `defer` next to
# a project `ask` produced no tool_result at all, num_turns 1, subtype success.
# What an operator sees there is UNVERIFIED — headless cannot observe a prompt.
# Standing down silently at exit 0 with no output is the floor's own idiom
# (floor_engine_stand_down, bin/guard-lib.sh:614) and its behaviour is known.
#
# THE PREDICATE IS WIRING, NOT MARKER PRESENCE. floor_in_repo() defers on marker
# presence, which is right for the floor. It is WRONG here: every governed repo
# on this machine has a marker and NONE of them wires prod_guard (harbor#56, the
# machine-wide sweep — 0 files), so deferring on the marker would stand down
# over precisely the repos that have no cloud guard of their own. The question
# this shim must ask is the narrower one: does THIS repo already run a
# prod_guard? And it must ask it of the RENDERED settings file the harness
# actually reads, never of the template — reading the template and generalising
# to the repo is the mistake that made this ticket's own premise wrong.

usage() { printf '  FAIL: usage: prod-guard-ambient.sh <installed-prod_guard.py>\n  fix: none automatic — see bin/prod-guard-install.sh, which wires it\n' >&2; exit 2; }
[ $# -eq 1 ] || usage
GUARD="$1"

PAYLOAD="$(cat)"

# ── the ledger (harbor#320) ─────────────────────────────────────────────────
# THIS GUARD WAS THE ONLY ONE ON THE BOX WHOSE DECISIONS NOBODY COULD SEE. Every
# other wired guard routes through floor_log_decision, so the statusline, the
# block counter and the false-positive detector all read a census this shim was
# simply absent from -- and "absent" and "never fired" are the same reading. A
# guard that cannot be audited for over-blocking is the one you cannot switch off
# with evidence, which is §2.11 with no way to test it.
#
# LAZY, SUBSHELLED AND REDIRECTED, and each of the three is load-bearing:
#
#   LAZY   guard-lib.sh is 2k lines and this runs on EVERY Bash call. Sourcing it
#          costs ~8.7ms measured here, against ~39ms for the python3 fork the
#          delegate path already pays -- affordable, but only paid at the moment
#          a decision is actually recorded, never on the way to making one. That
#          ordering is the point: the library is loaded AFTER the verdict exists,
#          so it cannot participate in reaching it.
#   SUBSHELL  guard-lib sets FLOOR_GREP/FLOOR_JQ/FLOOR_AWK at top level. In a
#          subshell none of that reaches this script's own logic, and `set +eu`
#          inside means a future unset-variable reference in the library cannot
#          abort the shim. An aborted PreToolUse hook is not a stand-down; it is
#          a hard block on every Bash call (see _broken below for the same trap).
#   REDIRECT  the hook's stdout IS its verdict. A single stray byte from the
#          library corrupts the JSON the harness parses, and the failure mode of
#          unparseable hook output is silent-allow. Sourcing writes nothing today
#          -- verified -- and this keeps that true without depending on it.
#
# ALSO ABSENT: a `prod` token in FLOOR_OBS_GUARDS, which would have coerced every
# record here to g=other and reproduced harbor#320 in a shape that LOOKS logged.
# Added in the same change, and lint C7 now holds the two ends together.
# harbor#813: no dirname fork (a failed one read /guard-lib.sh).
case "$0" in */*) _LIB="${0%/*}/guard-lib.sh" ;; *) _LIB=./guard-lib.sh ;; esac
_log() { # <verdict> <rule.shape>; FLOOR_IN gives the record its session key (harbor#309)
  [ -f "$_LIB" ] || return 0
  ( set +eu; FLOOR_TOOL=Bash; FLOOR_IN="$PAYLOAD"; . "$_LIB"; floor_log_decision prod "$1" "$2" ) \
    >/dev/null 2>&1 || :
}

# The session cwd the harness sends, preferred over this process's $PWD, which
# is only incidentally the same (same reasoning as guard-lib.sh:59-64).
d=""
if command -v jq >/dev/null 2>&1; then
  d="$(printf '%s' "$PAYLOAD" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$d" ] || d="${CLAUDE_PROJECT_DIR:-$PWD}"

# Up-walk for a rendered settings file that wires a prod_guard. Symlink
# discipline follows guard-lib.sh:45-48 (marker-forgery, 2026-07-24): a
# symlinked settings file is writable from outside the repo's own review, so it
# must not be able to talk this guard into standing down.
# MODE `other` EXCLUDES THIS SHIM'S OWN COMMAND, NOT THE WHOLE DIRECTORY. Raised by
# Codex review on #77, and it is reachable: prod-guard-install.sh merges additively
# (`merge_hook`: `. + [{type:"command", …}]`), so a prod_guard the operator had wired
# in the ambient settings.json BEFORE installing this shim survives the install and
# genuinely does own the message. Skipping every prod_guard in that directory makes
# it invisible, both guards then return `ask`, and that is precisely the
# nondeterministic-visible-reason race the stand-down exists to prevent. Matching on
# the shim's own BASENAME rather than a path: the wiring may spell the path via
# CLAUDE_CONFIG_DIR, a symlink or a different case, and any command that invokes
# prod-guard-ambient.sh is this shim (or an equivalent copy) whatever the spelling.
wires_prod_guard() { # <settings-file> [other]
  _s="$1"; _mode="${2:-any}"
  [ -f "$_s" ] && [ ! -L "$_s" ] || return 1
  # Cheap gate first: this runs on every Bash call, and the common case is a
  # settings file with no mention of it at all. jq only runs on a hit.
  grep -q 'prod_guard' "$_s" 2>/dev/null || return 1
  # No jq: cannot tell our own wiring from a foreign one. For a PROJECT that is
  # still a defer (a guard is there). For the AMBIENT dir the two errors are not
  # symmetric — deferring wrongly is a silent stand-down with nothing guarding,
  # while not deferring wrongly is a duplicated prompt on a command that stays
  # gated either way. So stay armed.
  command -v jq >/dev/null 2>&1 || { [ "$_mode" = any ]; return; }
  if [ "$_mode" = other ]; then
    # A TOKEN'S BASENAME, not a substring of the whole command. Codex review on #77
    # again: a whole-line `grep -v prod-guard-ambient` rejects a foreign guard merely
    # because some PATH COMPONENT carries that name — its example is a $HOME called
    # `prod-guard-ambient-user`, giving `…/prod-guard-ambient-user/.claude/hooks/
    # prod_guard.py`. The independent hook is then invisible, this shim stays armed,
    # both run, and the competing-`ask` race the exclusion exists to prevent is back.
    # So split the command into tokens, reduce each to its basename, and call it ours
    # only when a token IS the shim. BOTH quote characters are stripped, because
    # quoting is not tokenisation: an unstripped trailing quote leaves the basename as
    # `prod-guard-ambient.sh'`, our OWN command is then classified foreign, `other`
    # succeeds, and the shim stands down with nothing evaluating anything. Codex
    # review on #77 caught exactly that after the first version stripped only `"` —
    # the failure direction this comment had already named. `\047` is the portable
    # octal escape for a single quote; a literal one cannot appear inside the awk
    # program because the program itself is single-quoted.
    # ONE COMMAND MUST BE ONE awk RECORD. A hook command may itself contain newlines
    # — shell continuations between its tokens — and `jq -r` emits them verbatim, so
    # awk then sees one record per LINE. Only the line carrying prod_guard.py matches
    # /prod_guard/, it cannot see the shim token on the line above, our own command is
    # classified foreign and the shim stands down with nothing running. Codex review on
    # #77 (P1), reproduced. `gsub` inside jq collapses whitespace WITHIN each command,
    # which keeps the one-record-per-command grouping the token test depends on;
    # collapsing after jq (`tr`) would instead merge separate commands into one.
    jq -r '.hooks.PreToolUse[]?.hooks[]?.command // empty | gsub("[[:space:]]+";" ")' \
      "$_s" 2>/dev/null \
      | awk '
          /prod_guard/ {
            self = 0
            for (i = 1; i <= NF; i++) {
              t = $i; gsub(/["\047]/, "", t); sub(/^.*\//, "", t)
              if (t == "prod-guard-ambient.sh") self = 1
            }
            if (!self) other = 1
          }
          END { exit(other ? 0 : 1) }'
  else
    printf '%s' "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | join(" ")' "$_s" 2>/dev/null || true)" \
      | grep -q 'prod_guard'
  fi
}

# THE UP-WALK MUST NOT FIND ITSELF. The ambient config dir is `~/.claude` by
# default, and `~/.claude/settings.json` is the file that wires THIS shim. It is
# also an ancestor `.claude` of every path under $HOME, so the unguarded walk
# matched it, read its own wiring as "some repo owns the message", and stood down
# — for all work under $HOME, which is all real work. Measured 2026-07-31 on a
# live install: `terraform destroy -auto-approve` returned empty/exit 0 from
# ~/Documents/projects and a correct `ask` from /tmp. Same guard, same payload,
# only cwd differed.
#
# Derived from the guard path the harness passes, NOT from $HOME: the shim is
# invoked as `prod-guard-ambient.sh <cfg>/hooks/prod_guard.py`, so two dirnames
# up is the config dir that installed it. That stays correct under
# CLAUDE_CONFIG_DIR, and it keeps the suite hermetic — a stub guard in a fixture
# tree derives a fixture config dir, never the operator's.
#
# Deferring to a project's own copy is still right and still happens; deferring
# to yourself never is. This cannot reintroduce the double-prompt race the
# stand-down exists to prevent, because the skipped directory is by construction
# the one whose only guard is this process.
# `/bin/pwd -P`, NOT the shell's `pwd` builtin, and this is the whole reason the
# comparison is trustworthy. After `cd -P -- <dir>`, bash 3.2 (which is /bin/sh on
# macOS) returns the LEXICALLY canonicalised ARGUMENT from its builtin `pwd` —
# even with -P — rather than calling getcwd(). On a case-insensitive volume, which
# is the macOS default, `<x>/FAKEHOME/.claude` and `<x>/fakehome/.claude` are ONE
# directory (same dev:inode, verified with `stat -f '%d:%i'`) but the builtin
# returns two different strings, both string-compares below pass, and the shim
# reads its own wiring and stands down on `gcloud sql instances delete` again.
# `/bin/pwd` calls getcwd(), so it returns the name as stored on disk and the two
# spellings collapse to one. Reachable from a single case typo in
# CLAUDE_CONFIG_DIR or in the installer's guard argument — no exotic state needed.
# `stat -f '%d:%i'` also works and is what a reviewer will suggest; it is rejected
# because `-f` is BSD-only and the floor is pure POSIX that must also run on GNU.
# `CDPATH=''` not the bare `CDPATH=` used elsewhere in bin/: identical in sh, but
# the linter reads the bare form as a typo'd assignment (SC1007) — pass-score.sh:17
# already uses this spelling. (A comment line may not START with the linter's own
# name: it is then parsed as a directive, and SC1072 silently stops the analysis of
# the whole file — which is how this very block hid itself for one round.)
_canon() {
  ( CDPATH='' cd -P -- "$1" 2>/dev/null && { /bin/pwd -P 2>/dev/null || pwd; } ) ||
    printf '%s\n' "$1"
}

# TWO IDENTITIES FOR THE SAME DIRECTORY, and the union is the skip set. The guard
# argument is what the installer passes today (`<cfg>/hooks/prod_guard.py`), so
# two dirnames up is the config dir — and that is the route the hermetic fixture
# exercises. But it is only as good as the argument's shape: pass a guard from
# outside the config dir and the derivation yields something else entirely, which
# silently resurrects the self-defer. So also resolve the config dir directly,
# in lint D1's idiom. Either match is the ambient dir; neither alone is enough.
ambient_cfg="$(_canon "$(dirname "$(dirname "$GUARD")")")"

# `${HOME:-}` and not `$HOME`. Under `set -u` an UNSET HOME aborts the shim right
# here, before the up-walk — it emits no verdict and exits non-zero, and a
# PreToolUse hook exiting non-zero is not a stand-down, it is a hard block on
# every Bash call. An EMPTY HOME is the other half: it collapses this identity to
# "/.claude", which names nothing but is still a string that can compare equal to
# the wrong thing. Neither is hypothetical — `env -u HOME` reproduces both. An
# unusable candidate falls back to the argv-derived identity rather than inventing
# a path, because the argv identity is the one the installer actually guarantees.
_cfg_candidate="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}"
case "$_cfg_candidate" in
  /.claude | /.claude/ | .claude | '') live_cfg="$ambient_cfg" ;;
  *) live_cfg="$(_canon "$_cfg_candidate")" ;;
esac

while [ -n "$d" ] && [ "$d" != "/" ]; do
  if [ -d "$d/.claude" ] && [ ! -L "$d/.claude" ]; then
    c="$(_canon "$d/.claude")"
    if [ "$c" != "$ambient_cfg" ] && [ "$c" != "$live_cfg" ]; then
      # A project: ANY prod_guard wired there owns the message.
      # `armed` IS THE HONEST VERDICT FOR A STAND-DOWN, not `allow`. This shim did
      # not decide the command was safe -- it decided somebody else owns the
      # message for it, and a guard that is standing down is exactly a guard that
      # is armed and quiet. Recording it as `allow` would put this shim's name on
      # a permission it never granted, and the whole point of the ledger is that
      # the `r` field says WHICH surface answered.
      if wires_prod_guard "$d/.claude/settings.json"; then
        _log armed prod-project-owns.meta
        exit 0   # this repo owns the message for these commands
      fi
      if wires_prod_guard "$d/.claude/settings.local.json"; then
        _log armed prod-project-owns.meta
        exit 0
      fi
    else
      # The ambient config dir: only a prod_guard that is NOT this shim owns it.
      if wires_prod_guard "$d/.claude/settings.json" other; then
        _log armed prod-ambient-owns.meta
        exit 0
      fi
      if wires_prod_guard "$d/.claude/settings.local.json" other; then
        _log armed prod-ambient-owns.meta
        exit 0
      fi
    fi
  fi
  d="$(dirname "$d")"
done

# No project copy owns it — this one does.
#
# DEPENDENCY FAILURE IS NOT `exit 2` HERE, and this is a deliberate departure
# from floor-hook.sh. That wrapper converts a broken dependency into a loud deny
# because the guards it wraps are vetoes: exit 2 blocks the class they already
# block. This guard's posture is `ask` on ~0.4% of Bash traffic (harbor#56: 46
# matching calls in 11,505), so exit 2 on a missing python3 would deny 100% of
# Bash instead — a guard that blocks ordinary work gets switched off, and a
# disabled guard protects nothing (§2.11). Silent exit 0 is the other trap: that
# is precisely the silent-allow class floor-hook.sh was built to kill.
#
# So: announce it as an `ask` ONCE per session, then stand down for the rest of
# that session. The operator sees the diagnosis and cannot mistake it for a
# working guard; they do not get prompted on every subsequent command.
_broken() { # <reason>
  _sid="$(printf '%s' "$PAYLOAD" | jq -r '.session_id // empty' 2>/dev/null || true)"
  _stamp="${TMPDIR:-/tmp}/prod-guard-broken.${_sid:-nosession}"
  if [ -e "$_stamp" ]; then
    # BOTH BROKEN PATHS LOG, and the second one is the one that matters. After the
    # once-per-session stamp this guard is silent by design, so from outside it is
    # indistinguishable from a guard that is working and finding nothing -- which
    # is the whole reason the ledger exists. The RULE token separates them so a
    # reader can count how long the box ran unguarded, not merely that it did.
    #
    # `advise` AND NOT `ask`, because this branch emits no permissionDecision at
    # all -- it writes a diagnostic to stderr and stands down. The FIRST broken
    # call really does ask and is logged as `ask` below; recording this one the
    # same way would report a prompt the operator never saw, which is the reverse
    # of the honesty the ledger is for. `advise` is guard-integrity's token for
    # exactly this shape: something was said, nothing was gated.
    _log advise prod-broken-silenced.meta
    printf '  WARN: prod-guard-ambient: %s (already reported this session)\n  fix: none automatic — see the first report this session\n' "$1" >&2
    exit 0
  fi
  : > "$_stamp" 2>/dev/null || true
  _log ask prod-broken.meta
  # The corpus as prod_guard.py's DENY_RULES hold it, bq and gsutil included since yard ff2749d (PI-916);
  # checked 2026-10-23 at yard 22852b9: each bq, gsutil and gcloud storage removal verb asks (harbor#954 item 8).
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"prod-guard-ambient is INSTALLED BUT NOT FUNCTIONING: %s. Nothing is evaluating terraform/tofu destroy, kubectl/helm delete, aws/gcloud/az delete, warehouse table and dataset removal, recursive bucket removal, SQL DROP/TRUNCATE or rm -rf. Reported once per session; it will stand down silently for the rest of this session."}}\n' "$1"
  exit 0
}
[ -f "$GUARD" ] || _broken "no guard file at $GUARD"
command -v python3 >/dev/null 2>&1 || _broken "python3 not on PATH"

# THE DELEGATED VERDICT, and this is the only place the shim touches the data
# path, so it is written to be byte-transparent and is asserted that way.
#
# prod_guard.py's contract, read from the authoritative copy
# (yard plugins/project-init-workflow/hooks/prod_guard.py:1028-1040):
# it writes ONE json.dumps object with NO trailing newline on a verdict, writes
# NOTHING at all on an allow, and returns 0 on every path including its own
# internal exception handler. Diagnostics go to stderr, which `$(...)` does not
# capture, so they still reach the operator unchanged.
#
# THE `X` SENTINEL IS NOT A FLOURISH. `$(...)` strips every trailing newline, so
# the plain spelling is transparent only for as long as the guard happens not to
# emit one -- true of prod_guard.py today (`sys.stdout.write`), NOT true of the
# `print()` spelling one edit away, and not something this shim should depend on
# a file it deliberately does not own. Appending a byte and removing it makes the
# stream survive the round trip whatever the guard writes, and turns
# "byte-transparent" from a hope into something a test can assert on both shapes.
#
# `exit "$_r"` INSIDE the substitution for the same reason in the other channel:
# without it `$?` would be printf's status and every crash would be laundered
# into a success. THIS SHIM'S EXIT CODE IS NOT COSMETIC -- a non-zero PreToolUse
# hook is a hard block on every Bash call, not a stand-down (the trap _broken
# above exists to avoid), so a crashing python3 must keep the code it had.
#
# `set +e` INSIDE, because the subshell inherits this file's `set -e`: a failing
# pipeline would abort it before the sentinel was ever appended, which is exactly
# the crash path the two lines above are here to carry.
_pout=""; _prc=0
_pout="$( set +e; printf '%s' "$PAYLOAD" | python3 "$GUARD"; _r=$?; printf X; exit "$_r" )" || _prc=$?
_pout="${_pout%X}"

# CLASSIFIED BY TIER, NOT BY RULE, and the honesty matters more than the detail.
# Which rule fired lives inside prod_guard.py's reason prose; parsing it here
# would fork this shim's understanding of a corpus it deliberately does not own
# (see WHY A SHIM AND NOT A FORK, top of file), and a rule name that drifts is
# worse in a ledger than a tier that does not. Both json.dumps spacings are
# matched because the shim's own _broken printf emits the compact one.
case "$_pout" in
  '')                                                                _pv=allow; _pr=prod-clean.meta ;;
  *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*)   _pv=deny;  _pr=prod-gated.argv ;;
  *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*)     _pv=ask;   _pr=prod-gated.argv ;;
  # `other` IS DELIBERATE AND IS NOT A GAP. The guard wrote something this shim
  # cannot classify, and floor_log_decision's verdict enum coerces exactly that
  # to `other` -- so passing it explicitly records "output arrived, tier unknown"
  # rather than guessing a tier. The rule token is what makes it actionable:
  # `prod-unparsed` in the ledger means prod_guard.py changed its output shape.
  *)                                                                 _pv=other; _pr=prod-unparsed.meta ;;
esac
_log "$_pv" "$_pr"

printf '%s' "$_pout"
exit "$_prc"
