#!/usr/bin/env sh
# lint-constitution.sh (harbor#1273) - the constitution states rules, never their cases: no ISO date, ticket, absolute
# home path or workload repo name outside a code fence. The cases are law, in docs/explanation/case-law.md or a workload's pack.
#
#   sh lint-constitution.sh [--check]   red on any specific in policy/constitution.md, one FAIL per hit with its line
#   sh lint-constitution.sh --help
#
# Workload names come from the private layer's project registry ($HARBOR_SCOPE_PRIVATE/context-rules/user/projects.tsv, or the old inject.d/box/), so
# core never lists them; Harbor's own repos (OWN) are not workloads. With no registry, as in public CI, names are not
# judged and the run says so. The `**Path root:**` line is exempt: bin/drift-reference-check.sh reads the root from it.
# Env: HARBOR_SCOPE_ROOT, HARBOR_SCOPE_PRIVATE, CONSTITUTION_FILE (default policy/constitution.md). Exit 0 clean, 1 a hit, 2 usage.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
. "$SRC/library-log.sh"
log_init lint-constitution
LOG_FD=2

case "${1:---check}" in
  --check) ;;
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "lint-constitution: unknown argument '$1'" >&2; exit 2 ;;
esac

DOC="${CONSTITUTION_FILE:-$ROOT/policy/constitution.md}"
PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
REG="$PRIV/context-rules/user/projects.tsv"; [ -f "$REG" ] || REG="$PRIV/inject.d/box/projects.tsv"  # harbor#1010
# The platform's own repos (control plane, yard, fleet): never workloads. Their ids come from the registry (harbor#966).
_pids="$(env -u HARBOR_SCOPE_ROOT -u HARBOR_ROOT sh "$SRC/scope-roots.sh" --platform-ids)" || { log_fail "scope-roots.sh --platform-ids failed"; log_nofix "bin/scope-roots.sh"; log_end || :; exit 2; }
OWN=" $(printf '%s' "$_pids" | tr '\n' ' ') "
FIX="move the case to docs/explanation/case-law.md (a workload's case to its pack) and point to it by section"

[ -f "$DOC" ] || { log_fail "no ${DOC#$ROOT/}"; log_fix "run from a harbor checkout, or set CONSTITUTION_FILE"; log_end || :; exit 1; }
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT

# The judged text: line number TAB line, outside ``` fences, minus the path-root declaration.
awk '/^[[:space:]]*```/ { f = !f; next } !f && !/\*\*Path root:\*\*/ { print NR "\t" $0 }' "$DOC" > "$T/text"

hit() { # <kind> <ERE> [-i]: one FAIL per matching line
  grep -E ${3:-} -e "$2" "$T/text" > "$T/m" 2>/dev/null || return 0
  while IFS="$(printf '\t')" read -r n l; do
    m="$(printf '%s\n' "$l" | grep -oE ${3:-} -e "$2" | head -n 1)"
    m="$(printf '%s' "$m" | sed 's/^[^A-Za-z0-9~#/]//')"
    log_fail "${DOC#$ROOT/}:$n: $1 \`$m\`"; log_fix "$FIX"
  done < "$T/m"
}

hit "a date" '(^|[^0-9])20[0-9]{2}-[01][0-9]-[0-3][0-9]'
hit "a ticket" '[A-Za-z0-9_.-]+#[0-9]+|(^|[ (])#[0-9]{2,}'
hit "an absolute home path" '(^|[^A-Za-z0-9_.~$-])/(Users|home|Library|private|var/folders)/[^ `]*'
if [ -f "$REG" ]; then
  sed 's/\r$//' "$REG" | grep -vE '^[[:space:]]*(#|$)' | cut -f1 | while read -r id; do
    case "$OWN" in *" $id "*) continue ;; esac
    printf '%s\n' "$id"
  done > "$T/ids"
  while read -r id; do
    hit "a workload repo name" "(^|[^A-Za-z0-9_-])$id([^A-Za-z0-9_-]|\$)" -i
  done < "$T/ids"
  log_ok "workload names judged against $(wc -l < "$T/ids" | tr -d ' ') registered workload repo(s)"
else
  log_note "no project registry at ${REG#$HOME/}: workload names were not judged (dates, tickets and paths were)"
fi
[ "$_LOG_FAILED" -gt 0 ] || log_ok "${DOC#$ROOT/} states no date, ticket, absolute path or workload name"
log_end
