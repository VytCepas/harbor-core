#!/usr/bin/env sh
# tests/lib/run.sh — `just test` (contracts/test-contract.md rule 3, harbor#734): every suite in
# contracts/suites.txt in manifest order, or the ones named, then one total line a fleet runner reads.
#   sh tests/lib/run.sh [suite …]   a suite is its path, or its name as in `cu` for tests/cli/cu-test.sh
# Exit 0 iff every suite exited 0 and none counted a failure; 1 otherwise; 2 on an unknown suite.
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
MANIFEST="$ROOT/contracts/suites.txt"
LINE_RE='^[A-Za-z0-9._-]+: [0-9]+ passed, [0-9]+ failed$'
[ -f "$MANIFEST" ] || { printf 'run: no suite manifest at %s\n' "$MANIFEST" >&2; exit 2; }
_td="${TMPDIR:-/tmp}"; LOGS="$(mktemp -d "${_td%/}/harbor-test.XXXXXX")" || exit 2
manifest() { sed 's/#.*//; s/[[:space:]]*$//' "$MANIFEST" | awk 'NF'; }

# A name resolves through the manifest, so a suite outside it cannot be run as though it were in.
resolve() { # <path-or-name> → the manifest line
  manifest | awk -v a="$1" '$0 == a || $0 ~ ("/" a "-test\\.sh$") { print; exit }'
}
LIST="$LOGS/list"
if [ $# -eq 0 ]; then manifest > "$LIST"; else
  : > "$LIST"
  for a in "$@"; do
    s="$(resolve "$a")"
    [ -n "$s" ] || { printf 'run: %s is not a suite in contracts/suites.txt\n' "$a" >&2; rm -rf "$LOGS"; exit 2; }
    printf '%s\n' "$s" >> "$LIST"
  done
fi

P=0; F=0; BAD=0
while IFS= read -r s; do
  printf '── %s\n' "$s"
  log="$LOGS/$(printf '%s' "$s" | tr '/' '_').log"
  # One CPU slot per suite through bin/ci-governor.sh (a plain run where it has no state dir); its waits go to stderr.
  if [ -f "$ROOT/bin/ci-governor.sh" ]; then ( cd "$ROOT" && sh bin/ci-governor.sh run --out "$log" -- sh "$s" ) </dev/null; rc=$?
  else ( cd "$ROOT" && sh "$s" ) </dev/null > "$log" 2>&1; rc=$?; fi
  line="$(grep -aE "$LINE_RE" "$log" | tail -1)"
  if [ -n "$line" ]; then
    printf '%s\n' "$line"
    p="$(printf '%s' "$line" | sed 's/.*: \([0-9]*\) passed, .*/\1/')"
    f="$(printf '%s' "$line" | sed 's/.* passed, \([0-9]*\) failed$/\1/')"
  else p=0; f=0; fi
  # Exit and summary must agree (rule 3): no summary line, or a non-zero exit that counted nothing, is one failure.
  [ -n "$line" ] || f=1
  [ "$rc" -eq 0 ] || [ "$f" -gt 0 ] || f=1
  P=$((P + p)); F=$((F + f))
  if [ "$rc" -ne 0 ] || [ "$f" -gt 0 ]; then
    BAD=1
    grep -aE '^  FAIL: ' "$log" | head -20 >&2
    printf '  FAIL: %s exited %s — its full output is kept at %s\n' "$s" "$rc" "$log" >&2
    [ -n "$line" ] || printf '  FAIL: %s printed no summary line\n' "$s" >&2
    printf '  fix: none automatic — see %s\n' "$s" >&2
  else rm -f "$log"; fi
done < "$LIST"
rm -f "$LIST"; [ "$BAD" -eq 1 ] || rm -rf "$LOGS"
printf 'harbor: %d passed, %d failed\n' "$P" "$F"
[ "$BAD" -eq 0 ] && [ "$F" -eq 0 ]
