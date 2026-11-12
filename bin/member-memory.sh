#!/usr/bin/env sh
# member-memory.sh (harbor#1278, lane E) - where a registered project's agent memory lands on a member laptop, and the privacy gate on writing it.
#
#   sh member-memory.sh where [<dir>]     the route directory of the registered project holding <dir> (default: here); exit 1 when none
#   sh member-memory.sh seed              make the one store when it is missing or empty (a fresh member has none, so memory-route.sh stands down)
#   sh member-memory.sh add <slug> [--replace]   write the note on stdin as <route>/<slug>.md and append ONE pointer line to MEMORY.md (never
#                                         rewritten, never duplicated). Refused: a slug that is not [A-Za-z0-9._-] starting alnum or is MEMORY; an
#                                         existing slug without --replace; a body identical to another note (the refusal names it); a project with
#                                         no route; and a body with a credential shape, a password/secret/token assignment, an absolute or home path,
#                                         or a link that leaves the store (../, file:, a path). Exit 0 written, 1 refused, 2 usage
#   sh member-memory.sh check [<dir>]     the same body gate over the route's notes; exit 1 on a hit, 3 when it could not look
#   sh member-memory.sh note [<dir>]      the sentence the session start tells the agent (nothing when <dir> is in no registered project)
#
# THE ROUTE is memory-route.sh's, never a new store: <config>/projects/<harness key of the project root>/memory, a link at the one store under
# the home key (contracts/memory-format.md; one store with many doors). `harbor hub project register` runs memory-route.sh --apply; on a member
# the store did not exist yet, so the route was never made. `seed` is the one thing added: a MEMORY.md index in the home store.
# NOT CAUGHT, said plainly: bare prose ("my password is ..."), values made of letters only, quoted values containing spaces, values under 8 characters.
# So never paste a credential in any form; the gate is a net, not a wall.
# EVERYTHING it prints carries [check:memory.member-notes], the id of its row in standards/naming/controls.tsv (delete that row and this file to retire it).
# THE GATE reads contracts/credential-patterns.tsv (the shapes lint-secrets.sh and access.sh read). A missing pattern file refuses: a gate that
# cannot look must not pass. The write lands only inside the route's own directory and only as <slug>.md.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh; stdout is data
LOG_FD=2; . "$SRC/library-log.sh"; log_init member-memory
. "$SRC/library-fs.sh"   # fs_session_key, the harness's key (as memory-route.sh)

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
PATS=''
for _p in "$SRC/credential-patterns.tsv" "$SRC/../contracts/credential-patterns.tsv"; do [ -f "$_p" ] && { PATS="$_p"; break; }; done
TAB="$(printf '\t')"

TAG='[check:memory.member-notes]'
LOG_TOOL="member-memory $TAG"   # the summary line names the check too (LOG_TOOL names only the summary here: log_file is not used)
ok() { log_ok "$TAG $1"; }
note_() { log_note "$TAG $1"; }
usage() { awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SRC/member-memory.sh"; }
die() { log_fail "$TAG $1"; log_fix "${2:-sh $0 --help}   # $TAG"; log_end || :; exit "${3:-2}"; }
phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P; }
HOME_STORE="$CFG/projects/$(fs_session_key "$(phys "$HOME")")/memory"

# The registered project root holding <dir>: the longest projects.tsv path that is <dir> or a parent of it. Prints the root.
project_root() {
  _d="$(phys "${1:-.}")" || return 1
  _pf="$(env -u HARBOR_SCOPE_ROOT sh "$SRC/scope-roots.sh" --projects 2>/dev/null)" || return 1
  [ -f "$_pf" ] || return 1
  _best=''
  while IFS="$TAB" read -r _n _path _rest; do
    case "$_n" in ''|\#*) continue ;; esac
    [ -n "${_path:-}" ] || continue
    _abs="$(printf '%s' "$_path" | sed "s|^~|$HOME|")"
    _abs="$(phys "$_abs")" || continue
    case "$_d/" in "$_abs"/*) [ "${#_abs}" -gt "${#_best}" ] && _best="$_abs" ;; esac
  done < "$_pf"
  [ -n "$_best" ] && printf '%s\n' "$_best"
}
route_of() { # <dir> -> the route dir, when the project is registered and the route holds notes
  _root="$(project_root "$1")" || return 1
  _r="$CFG/projects/$(fs_session_key "$_root")/memory"
  [ -d "$_r" ] || return 1
  printf '%s\n' "$_r"
}
# credential_hits <file>: ids of the credential shapes found in the file, one per line.
credential_hits() {
  [ -n "$PATS" ] || return 3
  while IFS="$TAB" read -r _id _ere _note; do
    case "$_id" in ''|\#*|id) continue ;; esac
    grep -E -q -- "$_ere" "$1" 2>/dev/null && printf '%s\n' "$_id"
  done < "$PATS"
  return 0
}

# body_findings <file>: what in a note a member's memory must not carry, one id per line (credential shapes, then the rules below).
#   assign   a password / secret / token / api key assigned a value          path   an absolute path, ~/ or $HOME/ path
#   link     a markdown link or URL that leaves the store (../, file:, a path)
# The absolute-path shape is the leak gate's home-path (contracts/leak-patterns.tsv) widened to any rooted path: a note's path is no person's.
body_findings() {
  credential_hits "$1"; [ -n "$PATS" ] || return 3
  # assign: a password/secret/token/api key assigned ONE run of 8+ characters that mixes letters with digits or symbols; prose after the colon is not a value
  tr -d '\r' < "$1" | awk '
    { l = $0
      while (match(tolower(l), /(password|passwd|passphrase|pwd|pw|secret|client_secret|token|bearer|api[_-]?key)[a-z_]*[ \t]*[:=][ \t]*["'"'"'`]?[^ \t"'"'"'`]+/)) {
        seg = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
        sub(/^[^:=]*[:=][ \t]*["'"'"'`]?/, "", seg); sub(/[.,;)]+$/, "", seg)
        if (length(seg) >= 8 && seg ~ /[A-Za-z]/ && seg ~ /[0-9!@#$%^&*+=\/\\|~?]/) { found = 1 }
      }
      # an Authorization scheme: Bearer or Basic followed by ONE value-shaped run
      l = $0
      while (match(tolower(l), /(bearer|basic)[ \t]+[^ \t]+/)) {
        seg = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
        sub(/^[A-Za-z]+[ \t]+/, "", seg); sub(/[.,;)]+$/, "", seg)
        if (length(seg) >= 8 && seg ~ /[A-Za-z]/ && seg ~ /[0-9!@#$%^&*+=\/\\|~?]/) { found = 1 }
      } }
    END { exit !found }' && printf 'assign\n'
  grep -E -q '(^|[^A-Za-z0-9])[A-Za-z]:(\\|/[A-Za-z0-9._-])' "$1" 2>/dev/null && printf 'path\n'
  grep -E -q '(^|[[:space:](`"'"'"'=])(~|\$HOME|\$\{HOME\}|/[A-Za-z0-9._-]+)/' "$1" 2>/dev/null && printf 'path\n'
  # link: every markdown link target must stay in the store or be http(s), mailto or an anchor; file:// anywhere is out
  { grep -i -q 'file://' "$1" 2>/dev/null && printf 'link\n'
    grep -o -E '\]\([^)]*\)' "$1" 2>/dev/null | sed 's/^](//; s/)$//' | while IFS= read -r _t; do
      _t="${_t#<}"; _t="${_t%>}"
      case "$(printf '%s' "$_t" | tr '[:upper:]' '[:lower:]')" in http://*|https://*|mailto:*|'#'*) continue ;; esac
      case "$_t" in ../*|*/../*|..|/*|'~'*|*:*) printf 'link\n' ;; esac
    done; } | sort -u
  return 0
}

SUB="${1:-}"; [ $# -eq 0 ] || shift
case "$SUB" in
  -h|--help|help|'') usage; [ -n "$SUB" ] && exit 0; exit 2 ;;
  where)
    r="$(route_of "${1:-.}")" || { log_end || :; exit 1; }
    printf '%s\n' "$r"; exit 0 ;;
  note)
    r="$(route_of "${1:-.}")" || exit 0
    printf '[check:memory.member-notes] Memory for this project: notes live in %s (one store, shared across your projects). Read MEMORY.md there at the start. Save a durable lesson by piping it to: sh ~/port/harbor/bin/member-memory.sh add <slug> (it refuses a line shaped like a credential and writes only into that folder). Never paste a credential in any form: the gate misses bare prose (my password is ...), letters-only values, quoted values with spaces and values under 8 characters.' "$r"
    exit 0 ;;
  seed)
    n="$(find -P "$(phys "$HOME_STORE" || echo "$HOME_STORE")" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c .)"
    if [ "$n" -gt 0 ]; then ok "the store already holds $n note(s)"; log_end || :; exit 0; fi
    mkdir -p "$HOME_STORE" || die "cannot create the store" "mkdir -p the store under $CFG/projects" 1
    printf '# Memory\n\nOne index of the notes in this folder. One line per note: [title](file.md) - what it is for.\n' > "$HOME_STORE/MEMORY.md" || die "cannot write the index" "check the permissions of the store" 1
    ok "made the store with its index"; log_end || :; exit 0 ;;
  add)
    slug="${1:-}"; [ $# -eq 0 ] || shift
    REPLACE=0; [ "${1:-}" != --replace ] || REPLACE=1
    case "$slug" in ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) die "'$slug' is not a note name ([A-Za-z0-9][A-Za-z0-9._-]*)" ;; esac
    [ "$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')" != memory ] || die "MEMORY is the index, not a note: it is never written by name" "pick another slug" 1
    r="$(route_of .)" || die "no memory route here: this folder is in no registered project" "harbor hub project register <name>" 1
    W="$(mktemp "${TMPDIR:-/tmp}/member-memory.XXXXXX")" || die "cannot create a temp file" "df -h" 1
    trap 'rm -f "$W"' EXIT INT TERM
    cat > "$W"
    [ -s "$W" ] || die "an empty note is not written"
    hits="$(body_findings "$W")"; _rc=$?
    [ "$_rc" -ne 3 ] || die "no credential-patterns.tsv beside this tool: nothing was checked, so nothing is written" "reinstall the member floor" 1
    [ -z "$hits" ] || die "the note carries $(printf '%s' "$hits" | tr '\n' ' '): not written (credential, assign, path, link)" "describe it instead: no value, no path, no link out of the store (bin/secret keeps credentials)" 1
    # one note per slug (case-insensitive: the store may sit on a case-folding disk), and one note per body
    for f in "$r"/*.md; do
      [ -f "$f" ] || continue
      _b="${f##*/}"; _b="${_b%.md}"
      [ "$(printf '%s' "$_b" | tr '[:upper:]' '[:lower:]')" != memory ] || continue
      if [ "$(printf '%s' "$_b" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')" ]; then
        [ "$REPLACE" = 1 ] || die "$_b.md exists: not overwritten" "pass --replace to replace it, or pick another slug" 1
        continue
      fi
      if cmp -s "$W" "$f"; then die "the same note is already saved as $_b.md: not written twice" "update $_b.md with --replace if it changed" 1; fi
    done
    dest="$r/$slug.md"
    [ ! -L "$dest" ] || die "$slug.md is a link: not written through it" "pick another slug" 1
    cp "$W" "$dest" || die "cannot write $dest" "check the permissions of the store" 1
    # the index gets ONE pointer line: appended for a new note, refreshed in place under --replace, never duplicated
    idx="$r/MEMORY.md"
    desc="$(sed -n 's/^description:[[:space:]]*//p' "$W" | head -n 1)"
    [ -n "$desc" ] || desc="$(awk 'NR==1 && $0=="---" {fm=1; next} fm && $0=="---" {fm=0; next} !fm && NF {print; exit}' "$W")"
    # plain text: a link is its label, a heading or list mark goes, what is left of the brackets goes
    desc="$(printf '%s' "$desc" | sed -E 's/\[\[([^]]*)\]\]/\1/g; s/\[([^]]*)\]\([^)]*\)/\1/g; s/^[#>*-]+[[:space:]]*//; s/[][]//g' | cut -c1-100)"
    line="$(printf -- '- [%s](%s.md) - %s' "$slug" "$slug" "${desc:-note}")"
    if grep -F -q -e "- [$slug]($slug.md)" "$idx" 2>/dev/null; then
      if [ "$REPLACE" = 1 ]; then
        awk -v key="- [$slug]($slug.md)" -v new="$line" 'index($0, key) == 1 { if (!done) print new; done = 1; next } { print }' "$idx" > "$W.idx" \
          && cat "$W.idx" > "$idx" && rm -f "$W.idx" || die "wrote the note but could not refresh its line in MEMORY.md" "check the permissions of the store" 1
      fi
    else
      [ -f "$idx" ] && [ -z "$(tail -c1 "$idx")" ] || printf '\n' >> "$idx"
      printf '%s\n' "$line" >> "$idx" || die "wrote the note but could not list it in MEMORY.md" "check the permissions of the store" 1
    fi
    ok "wrote $slug.md into the route of the project and listed it"; log_end || :; exit 0 ;;
  check)
    r="$(route_of "${1:-.}")" || { note_ "no route here: nothing was checked"; log_end || :; exit 3; }
    [ -n "$PATS" ] || { note_ "no credential-patterns.tsv: nothing was checked"; log_end || :; exit 3; }
    bad=0
    for f in "$r"/*.md; do
      [ -f "$f" ] || continue
      h="$(body_findings "$f")"
      [ -z "$h" ] || { log_fail "$TAG ${f##*/}: $(printf '%s' "$h" | tr '\n' ' ')"; bad=$((bad + 1)); }
    done
    [ "$bad" -eq 0 ] || { log_fix "remove the offending text from the note; rotate a credential   # $TAG"; log_end || :; exit 1; }
    ok "no credential, assignment, path or outside link in the route's notes"; log_end || :; exit 0 ;;
  *) die "unknown verb '$SUB' (where, seed, add, check, note)" ;;
esac
