#!/usr/bin/env sh
# lint-siblings.sh (harbor#966, harbor#1149) - the ratchet on occurrences of another repo's path in core.
#
#   sh lint-siblings.sh --count    the number of sibling-path literals (occurrences, not files)
#   sh lint-siblings.sh --list     each one as file:line TAB literal
#   sh lint-siblings.sh --check    red if the count is above CONTRACTS/lint-siblings-baseline.txt;
#                                     green but says to lower the baseline when it is below
#
# A literal is a workspace-root spelling followed by /<x>: ~/port, $HOME/port in any quoting, $PORT_ROOT
# (braced, defaulted with - or :-), $(... --port-root), $PORT, or an absolute /Users/<u>/port or /home/<u>/port. x is not harbor,
# harbor-private or a workspace dir. Scope: every tracked file, plus untracked ones git does not ignore,
# minus tests, fixtures, EVALS-DATA and skills/test-strength/targets. Core reaches a sibling through
# `roots.sh --repo <id>`; the baseline only goes down.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
BASE="${SIBLING_BASELINE:-$ROOT/CONTRACTS/lint-siblings-baseline.txt}"
. "$SRC/log-lib.sh"
log_init lint-siblings
LOG_FD=2

# git grep, not grep: grep here is ugrep and skips gitignored files. --untracked adds a new unstaged
# file; a staged or edited one is read from the working tree. [$] keeps this file from matching itself.
PAT='(~/port|[$][{]?HOME[}]?"?/port"?|[$]PORT_ROOT"?|[$][{]PORT_ROOT(:?-[^}]*)?[}]"?|[$][{]?PORT[}]?"?|[$][(][^)]*--port-root[^)]*[)]"?|/(Users|home)/[^/]+/port)/"?[A-Za-z0-9._-]+'
files() { # file:line TAB literal, one per occurrence
  git -C "$ROOT" grep -I --untracked -n -oE -e "$PAT" -- . \
      ':!tests/**' ':!fixtures/**' ':!EVALS-DATA/**' ':!**/tests/**' ':!**/fixtures/**' ':!**/EVALS-DATA/**' ':!skills/test-strength/targets/**' \
      ':!hooks/*/*.test.sh' 2>/dev/null |  # a hook engine's tests sit in its folder (D-88)
    awk -F: '{ l = $0; sub(/^[^:]*:[^:]*:/, "", l); x = l; sub(/^.*\//, "", x); gsub(/"/, "", x)
               if (x == "harbor" || x == "harbor-private" || x == ".worktrees" || x == ".scratch" || x == "history") next
               printf "%s:%s\t%s\n", $1, $2, l }' | sort
}

case "${1:-}" in
  --count) git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "sibling-literals: $ROOT is not a git checkout" >&2; exit 2; }
           files | wc -l | tr -d ' ' ;;
  --list)  files ;;
  --check)
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-siblings.sh"; log_end || :; exit 2; }
    WANT="$(grep -vE '^[[:space:]]*(#|$)' "$BASE" 2>/dev/null | head -1 | tr -d ' ')" || WANT=""
    case "$WANT" in ''|*[!0-9]*) log_fail "no numeric baseline in ${BASE#$ROOT/}"; log_fix "write the current count (sh bin/lint-siblings.sh --count) into it"; log_end || :; exit 1 ;; esac
    GOT="$(files | wc -l | tr -d ' ')"
    if [ "$GOT" -gt "$WANT" ]; then
      log_fail "$GOT sibling-path literal(s) in the tree, baseline is $WANT"
      log_fix "reach the sibling with 'sh bin/roots.sh --repo <id>' instead of a literal path (CONTRACTS/private-layer.md)"
      # The delta, not the census: files this branch touched that hold a literal.
      __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
      files | cut -f1 | cut -d: -f1 | sort -u | while IFS= read -r f; do
        case "
$__chg
" in *"
$f
"*) log_note "changed and holds a literal: $f" ;; esac
      done
    elif [ "$GOT" -lt "$WANT" ]; then
      log_ok "$GOT literal(s), under the baseline of $WANT"
      log_note "lower ${BASE#$ROOT/} to $GOT so the gain is kept"
    else
      log_ok "$GOT sibling-path literal(s), equal to the baseline"
    fi
    log_end ;;
  -h|--help|help|'') sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "sibling-literals: unknown argument '$1'" >&2; exit 2 ;;
esac
