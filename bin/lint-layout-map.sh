#!/usr/bin/env sh
# lint-layout-map.sh (harbor#1272, #949) - every tracked top-level entry is in CONTRACTS/layout-map.tsv, and the map names nothing else.
#
#   sh lint-layout-map.sh --check   red on: a tracked top-level entry with no row, a row whose entry is not tracked (in an export
#                                   that tracks no dev entry, a dev row excepted), a duplicate row,
#                                   a kind that is neither a kinds.tsv id nor on the map's `# unregistered-kinds:` line, a layer
#                                   outside source/generated/deployed/record/report, a malformed row. Exit 2 outside a checkout.
#   sh lint-layout-map.sh --list    entry TAB kind TAB layer TAB core|dev|none|multi; the last from layers.tsv, never stored in the map
#
# Why a check and not a note: a folder added at the root with no kind and layer is the drift #1272 measured (54 entries, mixed kinds).
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
MAP="${LAYOUT_MAP:-$ROOT/CONTRACTS/layout-map.tsv}"
KINDS="${KINDS_FILE:-$ROOT/standards/naming/kinds.tsv}"
. "$SRC/log-lib.sh"
log_init lint-layout-map
LOG_FD=2
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT

entries() { git -C "$ROOT" ls-files | awk '{ i = index($0, "/"); print (i ? substr($0, 1, i) : $0) }' | sort -u; }

# map rows: entry kind layer, CR stripped, comments and blanks and the header dropped
rows() { sed 's/\r$//' "$MAP" | grep -vE '^[[:space:]]*(#|$)' | sed 1d; }

check() {
  [ -f "$MAP" ] || { echo "lint-layout-map: no ${MAP#$ROOT/}" >&2; return 2; }
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "lint-layout-map: $ROOT is not a checkout, nothing was inspected" >&2; return 2; }
  entries > "$T/tracked"
  [ -s "$T/tracked" ] || { echo "lint-layout-map: no tracked file, nothing was inspected" >&2; return 2; }
  { sed 's/\r$//' "$KINDS" | grep -vE '^[[:space:]]*(#|$)' | sed 1d | cut -f1
    sed -n 's/^# unregistered-kinds:[[:space:]]*//p' "$MAP" | tr ' ' '\n' | grep -v '^$' || :; } | sort -u > "$T/kinds"
  # An export tracks no dev-layer entry (CONTRACTS/layers.tsv), so there the map's dev rows name nothing and are not stale;
  # a checkout tracking any dev entry is judged on every row (harbor#1149).
  : > "$T/devrows"
  if ! sh "$ROOT/bin/layers.sh" --classify < "$T/tracked" | cut -f2 | grep -qx dev; then
    rows | cut -f1 | sh "$ROOT/bin/layers.sh" --classify | awk -F'\t' '$2 == "dev" { print $1 }' > "$T/devrows"
  fi
  rows | awk -F'\t' -v kf="$T/kinds" -v tf="$T/tracked" -v df="$T/devrows" '
    BEGIN {
      while ((getline k < kf) > 0) K[k] = 1
      while ((getline e < tf) > 0) { E[e] = 1 }
      while ((getline d < df) > 0) { D[d] = 1 }
      split("source generated deployed record report", L, " "); for (i in L) LAY[L[i]] = 1
    }
    NF != 4 || $1 == "" { printf "map row %d is not entry, kind, layer, note\n", NR; bad = 1; next }
    { if ($1 in seen) { printf "%s has two rows in the map\n", $1; bad = 1 }; seen[$1] = 1
      if (!($1 in E) && !($1 in D)) { printf "the map names %s, which is not a tracked top-level entry\n", $1; bad = 1 }
      if (!($2 in K)) { printf "%s has kind %s, which is not a kinds.tsv id or an unregistered-kind\n", $1, $2; bad = 1 }
      if (!($3 in LAY)) { printf "%s has layer %s, not source, generated, deployed, record or report\n", $1, $3; bad = 1 } }
    END { for (e in E) if (!(e in seen)) { printf "%s is tracked and not in the map\n", e; bad = 1 }; exit bad }' > "$T/out" || {
      sort "$T/out" | while IFS= read -r _l; do log_fail "$_l"; done
      log_fix "add or remove the row in CONTRACTS/layout-map.tsv (entry, kind, layer, note)"; log_end || :; return 1; }
  log_ok "layout map covers $(wc -l < "$T/tracked" | tr -d ' ') tracked top-level entries"; log_end || :
}

case "${1:-}" in
  -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  --check) check ;;
  --list)
    [ -f "$MAP" ] || { echo "lint-layout-map: no ${MAP#$ROOT/}" >&2; exit 2; }
    rows | cut -f1-3 > "$T/rows"
    cut -f1 "$T/rows" | sh "$ROOT/bin/layers.sh" --classify | cut -f2 > "$T/ship"
    paste "$T/rows" "$T/ship" ;;
  *) echo "usage: lint-layout-map.sh --check | --list" >&2; exit 2 ;;
esac
