#!/usr/bin/env sh
# scope-layers.sh (harbor#1149) - reads contracts/layers.tsv: which paths are core (exported) and which stay dev.
#
#   scope-layers.sh --check        red on a tracked path matching no row or two rows, or on a malformed row
#   scope-layers.sh --core         stdin paths → those matching exactly one core row (the rest are not exported)
#   scope-layers.sh --classify     stdin paths → path TAB core|dev|none|multi
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
LAYERS="${LAYERS_FILE:-$ROOT/contracts/layers.tsv}"
. "$SRC/library-log.sh"
log_init layers
LOG_FD=2

# classify: stdin paths → path TAB core|dev|none|multi on stdout; a malformed row is named on stderr and exits 1.
classify() {
  awk -F'\t' -v lf="$LAYERS" '
    BEGIN {
      while ((getline line < lf) > 0) {
        rn++; sub(/\r$/, "", line)
        if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) continue
        m = split(line, F, "\t")
        if (!hdr) { hdr = 1; if (F[1] != "path" || F[2] != "layer") { print "layers.tsv line " rn ": the header is not path, layer, note" > "/dev/stderr"; bad = 1 }; continue }
        if (m < 2 || F[1] == "" || (F[2] != "core" && F[2] != "dev")) { print "layers.tsv line " rn ": expected a path and a layer of core or dev" > "/dev/stderr"; bad = 1; continue }
        n++; P[n] = F[1]; L[n] = F[2]
      }
    }
    {
      hit = 0; lay = ""
      for (i = 1; i <= n; i++) {
        if (substr(P[i], length(P[i])) == "/" ? index($0, P[i]) == 1 : $0 == P[i]) { hit++; lay = L[i] }
      }
      printf "%s\t%s\n", $0, (hit == 0 ? "none" : (hit > 1 ? "multi" : lay))
    }
    END { exit bad }'
}

case "${1:-}" in
  -h|--help) sed -n "2,6p" "$0" | sed 's/^# \{0,1\}//' ;;
  --classify) classify ;;
  --core) classify | awk -F'\t' '$NF == "core" { sub(/\t[^\t]*$/, ""); print }' ;;
  --check)
    [ -f "$LAYERS" ] || { log_fail "no contracts/layers.tsv"; log_fix "create it (contracts/layers.tsv header documents the columns)"; log_end || :; exit 1; }
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/scope-layers.sh"; log_end || :; exit 2; }
    OUT="$(git -C "$ROOT" ls-files | classify)" || { log_fail "contracts/layers.tsv is malformed"; log_fix "correct the rows named above"; log_end || :; exit 1; }
    BAD="$(printf '%s\n' "$OUT" | awk -F'\t' '$NF == "none" || $NF == "multi"')"
    if [ -n "$BAD" ]; then
      printf '%s\n' "$BAD" | awk -F'\t' '{ printf "%s matches %s\n", $1, ($2 == "none" ? "no row" : "more than one row") }' | head -20 |
        while IFS= read -r _l; do log_fail "$_l"; done
      log_fix "edit contracts/layers.tsv so each tracked path matches exactly one row"; log_end || :; exit 1
    fi
    log_ok "every tracked path matches exactly one row"; log_end || :; exit 0 ;;
  *) echo "usage: scope-layers.sh --check | --core | --classify (paths on stdin)" >&2; exit 2 ;;
esac
