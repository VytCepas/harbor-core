#!/usr/bin/env sh
# compaction-digest — the traps THIS session sprang, from its own ledger rows (harbor#569).
#   sh compaction-digest.sh [--keys <session-id>] < SessionStart payload
# Counts and rule ids only: the ledgers hold hashes, never commands. Fail-open and silent when the
# session hit nothing. --keys prints the two ledger keys (sk, s) for a session id, for tests.
set -u
case "${1:-}" in -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
CFG="$(CDPATH= cd -- "${0%/*}/.." 2>/dev/null && pwd -P)" || exit 0
CAP=9   # plus the header line: 10 lines at most
command -v jq >/dev/null 2>&1 || exit 0
if [ "${1:-}" = --keys ]; then SID="${2:-}"; else SID="$(cat | jq -r '.session_id // empty' 2>/dev/null)" || exit 0; fi
case "$SID" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
[ "${#SID}" -le 64 ] || exit 0
[ -f "$CFG/bin/guard-lib.sh" ] || exit 0
. "$CFG/bin/guard-lib.sh" >/dev/null 2>&1 || exit 0
HOST=unknown-host
if [ -f "$CFG/.helm-obs-host" ] && [ ! -L "$CFG/.helm-obs-host" ]; then
  _h=""; { IFS= read -r _h < "$CFG/.helm-obs-host"; } 2>/dev/null || :
  case "$_h" in ''|*[!A-Za-z0-9_-]*) ;; *) HOST="$_h" ;; esac
fi
OD="$CFG/MEMORY/OBSERVABILITY/$HOST"
SK="$(floor_obs_digest "$CFG" "sid:$SID" 2>/dev/null)" || SK=-
FS="$(FLOOR_OBS_SUBJECT="session:$SID" floor_obs_digest "$CFG" 2>/dev/null)" || FS=-
case "$SK" in *[!0-9abcdef]*|'') SK=- ;; esac
case "$FS" in *[!0-9abcdef]*|'') FS=- ;; esac

# One "<signature>\t<count>" line per trap. Signatures come from fixed enums (g:r, a cd failure class),
# never from a field that could carry text, so nothing a row holds can reach the output.
ROWS="$(
  if [ "$SK" != - ]; then
    for f in "$OD"/guard-decisions.jsonl "$OD"/guard-decisions.jsonl.1; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      jq -r --arg sk "$SK" 'select(.sk == $sk and (.d == "block" or .d == "deny") and (.g|test("^[a-z]+$")) and (.r|test("^[a-z0-9-]+$"))) | "\(.g):\(.r)"' "$f" 2>/dev/null
    done
  fi
  if [ "$FS" != - ]; then
    for f in "$OD"/tool-failures.jsonl "$OD"/tool-failures.jsonl.1; do
      [ -f "$f" ] && [ ! -L "$f" ] || continue
      jq -r --arg s "$FS" 'select(.s == $s and .t == "Bash" and .k == "cd" and (.e == "blocked" or .e == "permission")) | "shell:cd-refused"' "$f" 2>/dev/null
    done
  fi
)"
[ "${1:-}" = --keys ] && { printf '%s %s\n' "$SK" "$FS"; exit 0; }
[ -n "$ROWS" ] || exit 0

fix() {
  case "$1" in
    bash:interpreter-at-surface|bash:python-c-exec|bash:ruby-perl-e-exec) echo "write the script to a file and run that file" ;;
    bash:pipe-to-shell|bash:eval-fetched-subst) echo "download to a file, read it, then run it" ;;
    bash:force-push*|bash:merge-raw|bash:deploy-raw) echo "use the gated route, not the raw command" ;;
    bash:cd-cfg-*) echo "use absolute operands, no cd into the config dir" ;;
    shell:cd-refused) echo "cd to an absolute path or \$HOME/..., never ~/..." ;;
    *) echo "change the approach; the same call is refused again" ;;
  esac
}

LINES="$(printf '%s\n' "$ROWS" | sort | uniq -c | sort -rn | head -n "$CAP" | while read -r n sig; do
  printf '%s x%s: %s\n' "$sig" "$n" "$(fix "$sig")"
done)"
[ -n "$LINES" ] || exit 0
printf 'Traps this session already sprang before the compaction (floor rule id, count, fix):\n'
printf '%s\n' "$LINES" | head -n "$CAP"
