#!/usr/bin/env sh
# drift-port-root.sh (harbor#966, check id `drift.port-root`) - every directory under PORT_ROOT is a registered repo or an exempt kind.
#
#   sh drift-port-root.sh            list each unregistered directory (one per line, with its age), exit 1 if any
#   sh drift-port-root.sh --names    just the names, for a script
#   sh drift-port-root.sh --status   the reconcile records (contracts/reconcile.md): a row per directory, its age; exit 3 when it cannot look
#
# Registered: a repo of `scope-roots.sh --repos` (the private registry, else the roots table), a directory a REPOS row of
# `scope-roots.sh --list` names, and the first path segment of either (a container such as data-flow/). Exempt kinds:
# a dot-directory (.worktrees, .scratch), `harbor-private` (the private layer), `history` (the registered
# archives), and `<registered id>-wt-<x>` (a sibling worktree). Files are not judged. A lookup that fails is exit 2,
# never an empty list read as clean.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init drift-port-root
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2

NAMES=0; STATUS=0
for _a in "$@"; do
  case "$_a" in
    --names) NAMES=1 ;;
    --status) STATUS=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "drift-port-root: unknown argument '$_a'" >&2; exit 2 ;;
  esac
done
[ "$STATUS" = 0 ] || [ "$NAMES" = 0 ] || { echo "drift-port-root: --status takes no --names" >&2; exit 2; }
[ "$STATUS" = 0 ] || status_init drift.port-root "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" || exit 3

# A lookup that fails is exit 2 in the plain run and exit 3, unchecked, in --status (harbor#1031).
die() { log_fail "$1"; log_fix "$2"; log_end || :; [ "$STATUS" = 0 ] || { status_unjudged "$1" || :; exit 3; }; exit 2; }

PR="$(sh "$SRC/scope-roots.sh" --port-root)" || die "scope-roots.sh could not resolve the workspace root" "sh bin/scope-roots.sh --port-root"
[ -d "$PR" ] || die "no workspace at $PR, so nothing was inspected" "set PORT_ROOT to the workspace root"
REPOS="$(sh "$SRC/scope-roots.sh" --repos)" || die "scope-roots.sh --repos refused the registry" "sh bin/scope-roots.sh --registry-check"
LIST="$(sh "$SRC/scope-roots.sh" --list)" || die "scope-roots.sh --list failed" "sh bin/scope-roots.sh --list"

# The first segment under PR of every registered or table-named checkout, one per line.
KNOWN="$( { printf '%s\n' "$REPOS" | awk -F'\t' 'NF >= 2 { print $2 }'
            printf '%s\n' "$LIST" | awk 'NR > 1 && $2 == "REPOS" { print $3 }'; } |
          P="$PR" awk '{ p = ENVIRON["P"] "/"; if (index($0, p) != 1) next
                         s = substr($0, length(p) + 1); sub(/\/.*/, "", s); if (s != "") print s }' | sort -u)"
IDS="$(printf '%s\n' "$REPOS" | awk -F'\t' 'NF >= 2 { print $1 }')"

DRIFT=""
for d in "$PR"/* ; do
  [ -d "$d" ] || continue                       # an unmatched glob stays literal and is not a directory
  n="${d##*/}"
  case "$n" in harbor-private|history) [ "$STATUS" = 0 ] || status_ok; continue ;; esac
  case "
$KNOWN
" in *"
$n
"*) [ "$STATUS" = 0 ] || status_ok; continue ;; esac
  wt=0
  for id in $IDS; do case "$n" in "$id"-wt-?*) wt=1 ;; esac; done
  [ "$wt" = 0 ] || { [ "$STATUS" = 0 ] || status_ok; continue; }
  DRIFT="$DRIFT$n
"
  [ "$STATUS" = 0 ] || status_drift "$n" "a registered repo or an exempt kind" "an unregistered directory, modified $(date -r "$d" +%Y-%m-%d 2>/dev/null || echo unknown)" "register it in the private repos.tsv, move it under history/ or .worktrees/, or delete it"
done
if [ "$STATUS" = 1 ]; then _rc=0; status_end || _rc=$?; exit "$_rc"; fi

if [ -z "$DRIFT" ]; then
  [ "$NAMES" = 1 ] || { log_ok "every directory under $PR is a registered repo or an exempt kind"; log_end; }
  exit 0
fi
if [ "$NAMES" = 1 ]; then printf '%s' "$DRIFT"; exit 1; fi
FIX="register it in the private repos.tsv (harbor scope install --seed-from-projects), move it under history/ or .worktrees/, or delete it"
while IFS= read -r n; do
  [ -n "$n" ] || continue
  log_fail "$PR/$n is not a registered repo or an exempt kind (modified $(date -r "$PR/$n" +%Y-%m-%d 2>/dev/null || echo unknown))"
  log_fix "$FIX"
done <<EOF2
$DRIFT
EOF2
log_end || :
exit 1
