#!/usr/bin/env sh
# memory-secret-scan.sh (harbor#25) — the work-log's whole-history gitleaks scan, nightly beside the range-only pre-push (124ey1kjcu0 P3).
#   sh memory-secret-scan.sh [--repo DIR]   scan every commit of DIR (default <config dir>/MEMORY)
#   exit 0 clean · 1 a finding, or no gitleaks (fail-closed) · 2 usage · 3 stood down: DIR is no git repo
# worklog/pre-push scans only what a push sends; a secret already on the remote is found here. The verdict is the receipt
# <config dir>/cache/checks/memory.secret-scan.json and one [check:memory.secret-scan] line in cache/checks.log; never the finding's text.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd -P)"
. "$HERE/library-log.sh"
log_init memory-secret-scan
CFG="${CLAUDE_CONFIG_DIR:-$(CDPATH='' cd -- "$HERE/.." && pwd -P)}"
REPO="$CFG/MEMORY"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || { log_fail "--repo needs a directory"; log_nofix "sh bin/memory-secret-scan.sh --help"; exit 2; }; REPO="$2"; shift 2 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) log_fail "unknown argument $1"; log_nofix "sh bin/memory-secret-scan.sh --help"; exit 2 ;;
  esac
done
ID=memory.secret-scan
RD="$(receipt_dir "$CFG")"
note() { printf '[check:%s] %s %s\n' "$ID" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" >> "$CFG/cache/checks.log" 2>/dev/null || :; }
if ! command -v gitleaks >/dev/null 2>&1; then
  log_fail "gitleaks is not on PATH, so the work-log history is unscanned"; log_fix "$(pkg_hint gitleaks)"
  log_receipt "$RD" "$ID" red "gitleaks missing" || :; note "red: gitleaks missing"; log_end || :; exit 1
fi
if ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  log_skip "$REPO is not a git repository: nothing to scan"
  log_receipt "$RD" "$ID" stood-down || :; note "stood down: no repository"; log_end || :; exit 3
fi
# The two dialects, as worklog/pre-push and floor_gitleaks_tree spell them (8.18.4 has no `git` verb).
_rc=0
if gitleaks git --help >/dev/null 2>&1; then gitleaks git --no-banner --exit-code 1 "$REPO" >/dev/null 2>&1 || _rc=$?
else gitleaks detect --no-banner --exit-code 1 --source "$REPO" >/dev/null 2>&1 || _rc=$?; fi
if [ "$_rc" -eq 0 ]; then
  log_ok "no secret in the history of $REPO"; log_receipt "$RD" "$ID" green || :; note "green"; log_end; exit 0
fi
log_fail "gitleaks found a secret in the history of $REPO (exit $_rc)"
log_fix "gitleaks git --no-banner $REPO   # read the finding from your own terminal, then rewrite or rotate"
log_receipt "$RD" "$ID" red "gitleaks exit $_rc" || :; note "red: gitleaks exit $_rc"; log_end || :; exit 1
