#!/usr/bin/env sh
# audit-review-config.sh (harbor#1497, B3) — the per-repo review config: the `review:` block of .agents/config.yaml.
#
#   sh bin/audit-review-config.sh read   --base <rev> [--repo <dir>]     effective config, key=value lines
#   sh bin/audit-review-config.sh decide --base <rev> [--repo <dir>] --author <login> --lines <n>   changed paths on stdin
#   sh bin/audit-review-config.sh check  <file>...                       lint.review-config-shape: FAIL line per finding
#
# read and decide take the config from `git show <rev>:.agents/config.yaml`, never the working tree or the PR head, so a PR
# cannot silence its own review. An absent file or block means the defaults. A block that fails `check` is refused (exit 1).
# decide prints `skip<TAB><why>` or `review<TAB>tier=..<TAB>lenses=..<TAB>verify=on<TAB>max-inline=..`. Globs are case patterns,
# `*` crosses `/`. No tier is one agent: every lens count is 1 or more and verify cannot be turned off.
# Exit 0 ok, 1 refused or finding, 2 usage. Block shape: docs/how-to/review-config.md.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init audit-review-config
LOG_FD=2   # stdout carries data (read, decide); the log goes to stderr
FIXLINE='correct the review: block per docs/how-to/review-config.md, then: sh bin/audit-review-config.sh check .agents/config.yaml'

DEF_TIER=standard; DEF_MAX_INLINE=10; DEF_QUICK_LINES=30
DEF_LENSES_QUICK=1; DEF_LENSES_STANDARD=4; DEF_LENSES_DEEP=6
DEF_AUTHORS='dependabot[bot]|renovate[bot]'
DEF_DOCS='docs/*|*.md'
DEF_GENERATED='*.lock|*-lock.json|docs/generated/*'

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "${1:-}" in -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; '') usage ;; esac

# Parse the review block of a stream on stdin. Prints `K<TAB>key<TAB>value` (a list item once per item), `L<TAB>key` for a
# list that is present even when empty, and `E<TAB>reason` for each defect.
parse() { awk '
  function err(m) { printf "E\t%s\n", m }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function uncomment(s,   i) { i = index(s, " #"); if (i) s = substr(s, 1, i - 1); if (substr(s, 1, 1) == "#") s = ""; return trim(s) }
  function unquote(s,   a, z) { a = substr(s, 1, 1); z = substr(s, length(s), 1)
    if (length(s) >= 2 && (a == "\"" || a == "\047") && a == z) s = substr(s, 2, length(s) - 2); return s }
  function isint(s) { return s ~ /^[0-9]+$/ }
  function glob_ok(g,   i, c, d) {
    if (g == "") return "is empty"
    if (g ~ /[ \t]/) return "holds whitespace"
    if (substr(g, 1, 1) == "/") return "starts with /"
    if (index(g, "..")) return "holds .."
    if (g ~ /^[*\/]+$/) return "matches every path"
    d = 0
    for (i = 1; i <= length(g); i++) { c = substr(g, i, 1); if (c == "[") d++; else if (c == "]") d--; if (d < 0) return "has an unbalanced ]" }
    if (d != 0) return "has an unbalanced ["
    return "" }
  function login_ok(l,   b) {
    b = l; if (length(b) > 5 && substr(b, length(b) - 4) == "[bot]") b = substr(b, 1, length(b) - 5)
    if (b ~ /^[A-Za-z0-9][A-Za-z0-9-]*$/) return ""
    if (index(l, "*") || index(l, "?")) return "is a wildcard: name each login"
    return "is not a login" }
  BEGIN { inb = 0; seenb = 0; list = ""
    LIST_OK["exclude-authors"] = 1; LIST_OK["docs-paths"] = 1; LIST_OK["generated-paths"] = 1; LIST_OK["deep-paths"] = 1 }
  /^[ \t]*(#.*)?$/ { next }
  /^[^ \t#]/ {
    inb = 0
    if ($0 ~ /^review:/) {
      if (seenb) { err("review: appears twice"); next }
      seenb = 1; inb = 1; v = uncomment(substr($0, 8))
      if (v != "" && v != "{}") err("review: holds an inline value; use an indented block or {}")
    }
    next }
  inb {
    line = $0
    if (line ~ /^\t/) { err("a tab indents a line; use spaces"); next }
    ind = match(line, /[^ ]/) - 1
    body = uncomment(substr(line, ind + 1))
    if (body == "") next
    if (substr(body, 1, 2) == "- " || body == "-") {
      if (list == "") { err("a list item outside a list: " body); next }
      it = unquote(trim(substr(body, 2)))
      w = (list == "exclude-authors") ? login_ok(it) : glob_ok(it)
      if (it == "") err(list ": an empty item")
      else if (w != "") err(list ": " it " " w)
      else printf "K\t%s\t%s\n", list, it
      next }
    if (ind != 2) { err("indent is 2 spaces under review:, got: " body); list = ""; next }
    c = index(body, ":")
    if (!c) { err("not a key: " body); list = ""; next }
    k = substr(body, 1, c - 1); v = unquote(trim(substr(body, c + 1))); list = ""
    if (k in SEEN) { err(k ": set twice"); next }
    SEEN[k] = 1
    if (k in LIST_OK) {
      if (v == "[]") printf "L\t%s\n", k
      else if (v == "") { list = k; printf "L\t%s\n", k }
      else err(k ": a list is block items (- item) or []; got: " v)
      next }
    if (k == "tier") { if (v ~ /^(quick|standard|deep)$/) printf "K\ttier\t%s\n", v; else err("tier: not quick, standard or deep: " v); next }
    if (k == "verify") {
      if (v ~ /^(on|true|yes)$/) printf "K\tverify\ton\n"
      else if (v ~ /^(off|false|no|0)$/) err("verify: off is refused; every finding needs a separate verifier")
      else err("verify: not on: " v)
      next }
    if (k == "max-inline") { if (isint(v) && v + 0 <= 50) printf "K\tmax-inline\t%d\n", v; else err("max-inline: not an integer 0..50: " v); next }
    if (k == "quick-under-lines") { if (isint(v)) printf "K\tquick-under-lines\t%d\n", v; else err("quick-under-lines: not a non-negative integer: " v); next }
    if (k ~ /^(quick|standard|deep)-lenses$/) {
      if (!isint(v)) err(k ": not an integer: " v)
      else if (v + 0 < 1) err(k ": 0 lenses is refused; no tier is single-agent or empty")
      else if (v + 0 > 6) err(k ": more than 6; only 6 lenses exist")
      else printf "K\t%s\t%d\n", k, v
      next }
    err("unknown key: " k) }
'; }

# Effective config from the block on stdin: key=value lines with defaults filled in. Exit 1 on any defect.
effective() {
  _p="$(parse)"
  _e="$(printf '%s\n' "$_p" | awk -F'\t' '$1 == "E" { print $2 }')"
  [ -z "$_e" ] || { printf '%s\n' "$_e" | while IFS= read -r _l; do log_fail "$_l"; done; log_fix "$FIXLINE"; return 1; }
  printf '%s\n' "$_p" | awk -F'\t' -v dt="$DEF_TIER" -v dm="$DEF_MAX_INLINE" -v dq="$DEF_QUICK_LINES" \
    -v lq="$DEF_LENSES_QUICK" -v ls="$DEF_LENSES_STANDARD" -v ld="$DEF_LENSES_DEEP" \
    -v da="$DEF_AUTHORS" -v dd="$DEF_DOCS" -v dg="$DEF_GENERATED" '
    function emit(key, defs,   i, c, a) {
      if (key in LS) { for (i = 1; i <= n[key]; i++) printf "%s=%s\n", key, I[key, i]; return }
      c = split(defs, a, "|"); for (i = 1; i <= c; i++) if (a[i] != "") printf "%s=%s\n", key, a[i] }
    function sc(key, d) { printf "%s=%s\n", key, (key in S) ? S[key] : d }
    $1 == "L" { LS[$2] = 1 }
    $1 == "K" { if ($2 in LS) { n[$2]++; I[$2, n[$2]] = $3 } else S[$2] = $3 }
    END { sc("tier", dt); sc("verify", "on"); sc("max-inline", dm); sc("quick-under-lines", dq)
          sc("quick-lenses", lq); sc("standard-lenses", ls); sc("deep-lenses", ld)
          emit("exclude-authors", da); emit("docs-paths", dd); emit("generated-paths", dg); emit("deep-paths", "") }'
}

safe_rev() { case "$1" in ''|-*|*[!A-Za-z0-9._/~^@-]*) return 1 ;; esac; return 0; }

# config_at <repo> <rev>: the file at the rev; nothing when the rev has none; 2 when the rev is unknown.
config_at() {
  git -C "$1" rev-parse --verify --quiet "$2^{commit}" >/dev/null 2>&1 || { printf 'audit-review-config: unknown rev: %s\n' "$2" >&2; return 2; }
  git -C "$1" cat-file -e "$2:.agents/config.yaml" 2>/dev/null || return 0
  git -C "$1" show "$2:.agents/config.yaml"
}

CMD="$1"; shift
case "$CMD" in
  read|decide)
    BASE=''; REPO=.; AUTHOR=''; LINES=''
    while [ $# -gt 0 ]; do
      case "$1" in
        --base) [ $# -ge 2 ] || usage; BASE="$2"; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO="$2"; shift 2 ;;
        --author) [ $# -ge 2 ] || usage; AUTHOR="$2"; shift 2 ;;
        --lines) [ $# -ge 2 ] || usage; LINES="$2"; shift 2 ;;
        *) usage ;;
      esac
    done
    if [ -z "$BASE" ] || ! safe_rev "$BASE"; then printf 'audit-review-config: --base <rev> is required and must be a plain rev\n' >&2; exit 2; fi
    RAW="$(config_at "$REPO" "$BASE")" || exit 2
    CFG="$(printf '%s\n' "$RAW" | effective)" || exit 1
    if [ "$CMD" = read ]; then printf '%s\n' "$CFG"; exit 0; fi
    case "$LINES" in ''|*[!0-9]*) usage ;; esac
    [ -n "$AUTHOR" ] || usage
    val() { printf '%s\n' "$CFG" | sed -n "s/^$1=//p"; }
    # An excluded login is skipped before anything else.
    if printf '%s\n' "$CFG" | grep -qxF "exclude-authors=$AUTHOR"; then printf 'skip\tauthor\n'; exit 0; fi
    PATHS="$(cat)"
    [ -n "$PATHS" ] || { printf 'skip\tno-files\n'; exit 0; }
    # matches <key> <path>: 0 when a glob of the key matches the path.
    matches() { val "$1" | while IFS= read -r _g; do
        # shellcheck disable=SC2254
        case "$2" in $_g) echo hit; break ;; esac; done | grep -q hit; }
    ALLGEN=1; ALLDOC=1; ANYDEEP=0
    while IFS= read -r _f; do
      [ -n "$_f" ] || continue
      matches generated-paths "$_f" || ALLGEN=0
      matches docs-paths "$_f" || ALLDOC=0
      matches deep-paths "$_f" && ANYDEEP=1
    done <<EOF
$PATHS
EOF
    T="$(val tier)"
    if [ "$ALLGEN" = 1 ]; then printf 'skip\tgenerated\n'; exit 0; fi
    if [ "$ANYDEEP" = 1 ]; then T=deep
    elif [ "$ALLDOC" = 1 ]; then T=quick
    elif [ "$LINES" -lt "$(val quick-under-lines)" ]; then T=quick; fi
    printf 'review\ttier=%s\tlenses=%s\tverify=on\tmax-inline=%s\n' "$T" "$(val "$T-lenses")" "$(val max-inline)"
    ;;
  check)
    [ $# -gt 0 ] || usage
    BAD=0
    for F in "$@"; do
      [ -f "$F" ] || { log_fail "$F: no such file"; log_fix "$FIXLINE"; BAD=1; continue; }
      _o="$(parse < "$F" | awk -F'\t' '$1 == "E" { print $2 }')"
      if [ -z "$_o" ]; then log_ok "$F"
      else BAD=1; printf '%s\n' "$_o" | while IFS= read -r _l; do log_fail "$F: $_l"; done; log_fix "$FIXLINE"; fi
    done
    log_end >/dev/null; exit "$BAD"
    ;;
  *) usage ;;
esac
