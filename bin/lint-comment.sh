#!/usr/bin/env sh
# lint-comment.sh (harbor#978) — file header line 2 and the comment rule, judged on the lines a branch adds.
#
#   sh bin/lint-comment.sh [--root DIR] [--base REF] [--registry DIR]
#   sh bin/lint-comment.sh --help
#
#   lint.file-header     a file the branch ADDS opens `# <name> (<repo>#N) — <purpose>` on line 1, or on line 2 under
#                        a shebang; <name> is the file's own basename; `//` instead of `#` in .ts, .js and .mjs
#   lint.comment-added   a run of more than 3 ADDED comment lines is flagged, outside a new file's own header block
#
# Only added lines are read (git diff -U0 against the merge-base), so a legacy comment block nobody touched is never
# flagged and the backlog stops growing without a rewrite. Each rule's mode is a cell of standards/naming/controls.tsv
# (warn when the row is missing): block exits 1, warn prints, shadow only records. LINT_REDLOG gets the rule id.
#   exit  0 pass, warn and shadow findings allowed · 1 a block finding · 2 usage · 3 unchecked (no base to compare)
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
LOG_FD=2
. "$HERE/library-log.sh"
log_init lint-comment
usage() { awk 'NR < 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$HERE/${0##*/}"; }
ROOT=""; REG=""; BASE="${HARBOR_BASE:-origin/main}"
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --root|--registry|--base) [ $# -ge 2 ] || { echo "lint-comment: $1 needs a value" >&2; exit 2; }
      case "$1" in --root) ROOT="$2" ;; --registry) REG="$2" ;; --base) BASE="$2" ;; esac; shift ;;
    *) echo "lint-comment: unknown argument: $1 (sh $0 --help)" >&2; exit 2 ;;
  esac
  shift
done
ROOT="$(CDPATH='' cd -- "${ROOT:-$HERE/..}" 2>/dev/null && pwd)" || { echo "lint-comment: no such root" >&2; exit 2; }
REG="${REG:-$ROOT/standards/naming}"
mb="$(git -C "$ROOT" merge-base HEAD "$BASE" 2>/dev/null)" || {
  log_fail "no base to compare against ($BASE): lint-comment judged NOTHING"; log_fix "sh $0 --base <ref>"; log_end || :; exit 3; }
mode_of() { # <rule id> -> its controls.tsv mode, warn when the row is absent
  _m="$(awk -F'\t' -v id="$1" '$1 == id { print $2; exit }' "$REG/controls.tsv" 2>/dev/null)"
  case "$_m" in shadow|warn|block) printf '%s' "$_m" ;; *) printf warn ;; esac
}
T="$(mktemp -d "${TMPDIR:-/tmp}/lint-comment.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM HUP
git -C "$ROOT" diff --no-color --no-renames -U0 --diff-filter=AM "$mb" -- > "$T/diff"
git -C "$ROOT" diff --no-renames --name-only --diff-filter=A "$mb" -- > "$T/added"
# One record per finding: <rule> TAB <path:line> TAB <message>. The awk reads the diff once.
awk -v added="$T/added" '
  function leader(p,   e) {
    e = p; sub(/^.*\./, "", e)
    if (e ~ /^(sh|bash|py|awk|rb)$/) return "#"
    if (e ~ /^(ts|js|mjs)$/) return "//"
    return ""
  }
  function flush() { if (run > 3) printf "lint.comment-added\t%s:%d\t%d comment lines added in a row (budget 3): say what the code guards in 3 lines and cite the issue\n", path, start, run
                     run = 0 }
  BEGIN { while ((getline l < added) > 0) NEW[l] = 1 }
  /^\+\+\+ / { flush(); path = substr($0, 7); lead = leader(path); next }
  /^@@ / { flush(); split($3, a, ","); ln = substr(a[1], 2) + 0; next }
  /^\+/ { text = substr($0, 2); isc = (lead != "" && index(text, lead) == 1 && text !~ /^#!/)
          hdr = (path in NEW) && ln <= 8   # a new file may carry its own header block
          if (isc && !hdr) { if (run == 0) start = ln; run++ } else flush()
          ln++; next }
  END { flush() }' "$T/diff" > "$T/findings"
# header line 2 of every added script: read the file as it is in the working tree
while IFS= read -r f; do
  [ -f "$ROOT/$f" ] || continue
  case "$f" in fixtures/*|*/fixtures/*) continue ;; *.sh|*.bash|*.py|*.awk|*.rb) lead='#' ;; *.ts|*.js|*.mjs) lead='//' ;; *) continue ;; esac
  want="${f##*/}"
  awk -v f="$f" -v lead="$lead" -v want="$want" '
    NR == 1 && /^#!/ { shebang = 1; next }
    { if (NR == 1 + shebang) {
        pre = lead " " want " ("
        if (index($0, pre) != 1 || $0 !~ / \([a-z0-9-]+#[0-9]+\) — ./)
          printf "lint.file-header\t%s:%d\tline %d must read `%s %s (<repo>#N) — <purpose>`\n", f, NR, NR, lead, want
        exit } }
    END { if (NR == 0) printf "lint.file-header\t%s:1\tempty file has no header\n", f }' "$ROOT/$f" >> "$T/findings"
done < "$T/added"
rc=0; n=0
while IFS="$(printf '\t')" read -r rule where msg; do
  [ -n "$rule" ] || continue
  n=$((n + 1)); mode="$(mode_of "$rule")"
  [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$rule" >> "$LINT_REDLOG" 2>/dev/null || :
  case "$mode" in
    shadow) ;;
    block) log_fail "[$rule] $where — $msg"; log_nofix "standards/naming.md §10.7"; rc=1 ;;
    *) log_warn "[$rule] $where — $msg" ;;
  esac
done < "$T/findings"
[ "$n" -gt 0 ] && log_note "$n finding(s)" || log_ok "no added header or comment run breaks the rule (since $(printf %.8s "$mb"))"
log_end || :
exit "$rc"
