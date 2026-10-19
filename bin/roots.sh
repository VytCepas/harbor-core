#!/usr/bin/env sh
# roots.sh — resolve the named roots in CONTRACTS/roots.tsv, and check that the
# tree's own defaults agree with them. harbor#630.
#
#   sh roots.sh --list         every row, resolved against this box
#   sh roots.sh --get <VAR>    one resolved path, for a script to consume
#   sh roots.sh --repos        each governed repo once: <name> TAB <resolved checkout> (harbor#829)
#   sh roots.sh --check        every ${VAR:-...} default matches, honours PORT_ROOT, is registered; a shared path has a reason
#   sh roots.sh --repo <id>    one repo's checkout from the registry (PORT_ROOT/<id> with no registry; exit 1, empty, when a registry lacks it) (harbor#966)
#   sh roots.sh --remote <id>  one repo's clone URL from the registry's remote column; exit 1, empty, with no registry, no such row, or remote '-' (harbor#966)
#   sh roots.sh --registry-check   every repos.tsv row valid: id, path and symlinks inside PORT_ROOT, kind known
#   sh roots.sh --port-root | --private   the workspace root, the private layer's directory
#   sh roots.sh --access       the access register (<private>/access, or $ACCESS_DIR); exit 1, empty, when there is none
#   sh roots.sh --inject       the private rule packs (<private>/inject.d); exit 1, empty, when there is none
#   sh roots.sh --projects     the project registry (<private>/inject.d/box/projects.tsv); exit 1, empty, when there is none
#   sh roots.sh --conf <key>   one value from harbor.toml (an array prints one element per line)
#   sh roots.sh --conf-keys    core's own harbor.toml keys, one per line (a pack's keys come from its conf-keys.txt)
#   sh roots.sh --base <BOX|REPOS>   what a base is on this box ($HOME, or the workspace root): the text a launchd template's @HOME@ fills (harbor#630)
#
# THE REGISTRY (CONTRACTS/private-layer.md). <private>/repos.tsv is id/path/kind/remote and the one
# reader of it is this file; --repos and --repo answer from it, and from the table below when it is
# absent (--repo then prints PORT_ROOT/<id>, the old literal), so a box with no private layer behaves as before.
#
# WHY. Measured 2026-09-23: 91 non-comment, non-markdown lines here name a repo
# root and 13 go through an override variable. Those 13 were written one at a
# time, and two of them (PROJECT_INIT_SRC, HARBOR_PROJECT_INIT) are different
# names for one repo. A default written at its use site reads correctly forever
# while drifting from every sibling, because nothing ever compares them.
#
# THE MOVE IS WHY THE BASE IS SYMBOLIC. harbor#619 moves every governed repo
# under PORT_ROOT. With the base named rather than spelled, that is ONE edit in
# repos_prefix() below; without it, it is an edit at each site plus a hunt for
# the ones that never used a variable at all.
#
# DELIBERATELY NOT READ BY THE FLOOR. bin/guard-lib.sh keeps its own literal
# default for PORT_ROOT, and ROOT1 checks the two agree. The floor is POSIX,
# hash-pinned per file (B6) and must answer with no I/O it does not control; a
# guard that resolves its stop by reading a TSV gains a file that can be absent,
# truncated or edited between the pin and the call. One source of TRUTH does not
# require one source of BYTES — it requires a check, and that is ROOT1.
set -eu

# ${0%/*}, not $(dirname -- "$0"): a failed fork or dirname off PATH makes the
# dirname call empty, `cd -- ""` silently stays put, and SRC becomes whatever
# the SESSION's cwd happened to be (harbor#810, #813).
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
TABLE="${HARBOR_ROOTS_TABLE:-$ROOT/CONTRACTS/roots.tsv}"
# CONTRACTS/logging.md channel 1. LOG_FD=2: --get and --list print DATA on stdout (a value, a
# table), and --check's success line is that same protocol — every log-lib line stays on stderr.
. "$SRC/log-lib.sh"
LOG_FD=2

[ -f "$TABLE" ] || { echo "roots: no table at $TABLE" >&2; exit 2; }

# The one line the ~/port move edits. Returns the LITERAL TEXT a default is
# expected to spell, not a resolved path — ROOT1 compares source text, and
# `$HOME` in a script is four characters, not a directory.
#
# harbor#619 moved every governed repo to $HOME/port on 2026-09-23, so this is
# that edit. It is the DEFAULT's spelling, and a site may spell it two ways, both
# read by --check: flat (the home-relative text, which IGNORES an exported PORT_ROOT and
# is refused for a REPOS row, harbor#630) or nested
# (PORT_ROOT with that text as its own default, which honours it). --check reads a default with a
# pattern that steps over ONE nested ${...}, and normalises the nested spelling
# back to this text before comparing, so the table still holds one spelling.
repos_prefix() { printf '%s' '$HOME/port'; }
box_prefix()   { printf '%s' '$HOME'; }

prefix_for() { # <base> → the TEXT a default spells (what --check compares)
  case "$1" in
    REPOS) repos_prefix ;;
    BOX)   box_prefix ;;
    *)     echo "roots: unknown base '$1'" >&2; return 1 ;;
  esac
}

# The same base as a PATH on this box. REPOS is the workspace root, so it honours an exported
# PORT_ROOT; the text above is for comparing source, this is for resolving it (harbor#630: a
# fresh machine with another root used to get the home-relative default from --get, --list and --repos).
resolved_prefix() { # <base>
  case "$1" in
    REPOS) port_root ;;
    BOX)   [ -n "${HOME:-}" ] || { echo "roots: HOME is unset, so the BOX base has no path" >&2; return 2; }
           printf '%s' "${HOME%/}" ;;
    *)     echo "roots: unknown base '$1'" >&2; return 1 ;;
  esac
}

# The rows, comments and the header stripped. One reader, so a change to the
# file's shape lands in one place.
rows() { sed 's/#.*//' "$TABLE" | awk -F'\t' 'NF>=4 && $1!="var" && $1!=""'; }

expected_for() { # <var> → the literal default text, or empty if not a known root
  rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
    [ "$__v" = "$1" ] || continue
    printf '%s/%s' "$(prefix_for "$__b")" "$__r"
    return 0
  done
}

default_for() { # <var> → the default as a path on this box, or empty if not a known root
  rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
    [ "$__v" = "$1" ] || continue
    __rp="$(resolved_prefix "$__b")" || exit 2
    printf '%s/%s' "$__rp" "$__r"
    return 0
  done
}

# ── the private layer: registry and config (harbor#966, CONTRACTS/private-layer.md) ──────────────
# Built in two steps, not ${PORT_ROOT:-$HOME/port}: --check above cannot parse a nested default.
port_root() {
  __pr="${PORT_ROOT:-}"
  if [ -z "$__pr" ]; then
    [ -n "${HOME:-}" ] || { echo "roots: HOME is unset and PORT_ROOT is empty, so there is no workspace" >&2; return 2; }
    __pr="$HOME/port"
  fi
  # A TAB, newline or other control character would split a registry row or a printed path.
  if [ -n "$(printf '%s' "$__pr" | LC_ALL=C tr -d '[:print:]')" ]; then
    echo "roots: PORT_ROOT contains a control character (TAB, newline), which a path cannot carry" >&2; return 2
  fi
  printf '%s' "${__pr%/}"
}
private_dir() {
  __pv="${HARBOR_SCOPE_PRIVATE:-}"
  if [ -z "$__pv" ]; then __pv="$(port_root)/harbor-private" || return 2; fi
  printf '%s' "${__pv%/}"
}

# The access register: account, role and route cards (CONTRACTS/access-card.md). They name accounts,
# so they are private data and core ships none. $ACCESS_DIR, when set, wins as every override here
# does. A register that is not there is exit 1 with nothing on stdout and the reason on stderr, so a
# reader says "no register" and never cd's, reads or passes against an empty path (harbor#1149).
access_dir() {
  __ad="${ACCESS_DIR:-}"
  if [ -n "$__ad" ]; then
    [ -d "$__ad" ] || { echo "roots: ACCESS_DIR is $__ad, which is not a directory" >&2; return 1; }
  else
    __pv="$(private_dir)" || return 2
    [ -d "$__pv" ] || { echo "roots: no private layer at $__pv, so there is no access register (CONTRACTS/private-layer.md)" >&2; return 1; }
    __ad="$__pv/access"
    [ -d "$__ad" ] || { echo "roots: the private layer at $__pv has no access/ directory (CONTRACTS/private-layer.md)" >&2; return 1; }
  fi
  printf '%s' "${__ad%/}"
}

# The private rule packs (CONTRACTS/private-layer.md, harbor#1149): <private>/inject.d, the shape of core's inject.d/ -
# box/ for the packs every session on the box carries (and the project registry), one folder per repo for the packs
# `inject-install.sh --projects` seeds. They name clients and repos, so core ships none. Nothing in it is code: the
# installer takes .md packs and projects.tsv only. Absent is exit 1 with nothing on stdout and the reason on stderr,
# so a reader says "no private packs" and never reads or seeds an empty path.
inject_dir() {
  __pv="$(private_dir)" || return 2
  [ -d "$__pv" ] || { echo "roots: no private layer at $__pv, so there are no private rule packs (CONTRACTS/private-layer.md)" >&2; return 1; }
  [ -d "$__pv/inject.d" ] || { echo "roots: the private layer at $__pv has no inject.d/ directory (CONTRACTS/private-layer.md)" >&2; return 1; }
  printf '%s' "$__pv/inject.d"
}
projects_file() {
  __id="$(inject_dir)" || return $?
  [ -f "$__id/box/projects.tsv" ] || { echo "roots: no project registry at $__id/box/projects.tsv (CONTRACTS/private-layer.md)" >&2; return 1; }
  printf '%s' "$__id/box/projects.tsv"
}

# A file as lines, with a UTF-8 BOM and trailing CRs removed (an editor on Windows writes both) and a
# note on stderr when it did. Line numbers are kept so every message still names the right line.
clean_lines() { # <file>
  awk -v f="$1" '
    # length(), not 3: gawk in a UTF-8 locale reads the BOM as ONE character (the hosted runner, harbor-core CI)
    FNR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, length("\357\273\277") + 1); bom = 1 }
    /\r$/ { sub(/\r$/, ""); cr = 1 }
    { print }
    END { if (bom || cr) printf "roots: note: %s had %s%s%s; read as plain text\n", f, bom ? "a BOM" : "", (bom && cr) ? " and " : "", cr ? "CRLF line endings" : "" > "/dev/stderr" }' "$1"
}

# Rows validated and printed as id TAB path TAB kind TAB remote. A row that would resolve outside
# PORT_ROOT, repeat an id or a path (case-insensitively) or has other than four fields refuses the
# whole read (exit 2): a lookup that skips a bad row answers "unknown" for a repo that is only
# mistyped. One trailing / on a path is dropped. This pass is lexical; confine() follows symlinks.
# Kinds are judged only when a kinds file is given, so a lookup never fails over a vocabulary edit.
registry_rows() { # <repos.tsv, or /dev/stdin> [<repo-kinds.tsv>] — the file name in messages is $RF
  RF="${RF:-$1}" KF="${2:-}" awk -F'\t' '
    function bad(m) { printf "roots: %s:%d: %s\n", ENVIRON["RF"], NR, m > "/dev/stderr"; err = 1 }
    BEGIN { kf = ENVIRON["KF"]
            if (kf != "") while ((getline l < kf) > 0) { if (l ~ /^#/ || l ~ /^id\t/) continue; split(l, f, "\t"); if (f[1] != "") kind[f[1]] = 1 } }
    /^[ \t]*#/ || /^[ \t]*$/ || $1 == "id" { next }
    { if (NF != 4) { bad("expected id, path, kind, remote (tab-separated), got " NF " field(s)"); next }
      if ($1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) { bad("id \"" $1 "\" is not a repo name"); next }
      if ($1 in seen) { bad("duplicate id \"" $1 "\""); next }
      p = $2; sub(/\/$/, "", p)
      if (p == "" || p ~ /^[\/~$]/ || p !~ /^[A-Za-z0-9._\/-]+$/) { bad("path \"" $2 "\" must be relative to PORT_ROOT"); next }
      n = split(p, seg, "/"); esc = 0
      for (i = 1; i <= n; i++) if (seg[i] == ".." || seg[i] == "." || seg[i] == "") esc = 1
      if (esc) { bad("path \"" $2 "\" escapes PORT_ROOT or is not a clean relative path"); next }
      lp = tolower(p)
      if (lp in pathseen) { bad("duplicate path \"" p "\" (same checkout as id \"" pathseen[lp] "\", case ignored)"); next }
      if (kf != "" && !($3 in kind)) { bad("kind \"" $3 "\" is not in " kf); next }
      seen[$1] = 1; pathseen[lp] = $1
      printf "%s\t%s\t%s\t%s\n", $1, p, $3, $4 }
    END { exit err ? 2 : 0 }' "$1"
}

# A row whose checkout exists must resolve, symlinks followed, to a directory inside PORT_ROOT, and no
# two rows may resolve to one directory. A path that does not exist yet is not a failure.
confine() { # <port root> ; rows (id TAB path ...) on stdin as $2
  __rr="$(cd -P -- "$1" 2>/dev/null && pwd -P)" || return 0
  __seen="
"
  while IFS="$(printf '\t')" read -r __id __p __rest; do
    [ -n "$__id" ] && [ -d "$1/$__p" ] || continue
    __rp="$(cd -P -- "$1/$__p" 2>/dev/null && pwd -P)" || continue
    case "$__rp/" in "$__rr"/?*) ;; *) echo "roots: repo '$__id': $__p resolves to $__rp, outside PORT_ROOT ($__rr)" >&2; return 2 ;; esac
    case "$__seen" in *"
$__rp
"*) echo "roots: repo '$__id': $__p resolves to $__rp, the checkout of another row" >&2; return 2 ;; esac
    __seen="$__seen$__rp
"
  done <<EOF
$2
EOF
}

registry_load() { # <repos.tsv> → the validated rows, id TAB path TAB kind TAB remote (the one read of the file)
  __lr="$(port_root)" || return 2
  __clean="$(clean_lines "$1")" || return 2
  __rows="$(printf '%s\n' "$__clean" | RF="$1" registry_rows /dev/stdin)" || return 2
  confine "$__lr" "$__rows" || return 2
  printf '%s\n' "$__rows"
}

# The one list of repos: the registry when it exists, otherwise the roots table as before.
repos_list() { # → id TAB resolved checkout
  __reg="$(private_dir)/repos.tsv" || return 2
  if [ -f "$__reg" ]; then
    __all="$(registry_load "$__reg")" || return 2
    __root="$(port_root)" || return 2
    printf '%s\n' "$__all" | R="$__root" awk -F'\t' 'NF >= 2 { printf "%s\t%s/%s\n", $1, ENVIRON["R"], $2 }'
    return 0
  fi
  # A REPOS row's first path segment is the checkout; harbor/ACCESS and harbor are one repo.
  __root="$(port_root)" || return 2
  rows | awk -F'\t' '$2 == "REPOS" { n = $3; sub(/\/.*/, "", n); if (n != "" && !seen[n]++) print n }' |
    while IFS= read -r __n; do
      case "$__n" in *[!A-Za-z0-9._-]*|.*) echo "roots: '$__n' is not a repo name" >&2; exit 2 ;; esac
      printf '%s\t%s/%s\n' "$__n" "$__root" "$__n"
    done
}

# harbor.toml, the flat subset: key = "value" or key = ["a", "b"] on one line, # comments, no tables.
# Unknown keys, tables, duplicate keys, a backslash or an empty string inside a value and any other
# shape are refused (exit 2): a typo read as "unset" would silently install the default. Values print
# raw; an array prints one per line.
toml_get() { # <file> <key>
  clean_lines "$1" | WANT="$2" RF="$1" KNOWN="$(conf_keys)" awk '
    function bad(m) { printf "roots: %s:%d: %s\n", ENVIRON["RF"], NR, m > "/dev/stderr"; err = 1; exit 2 }
    function quoted(s,   e, t) { if (substr(s, 1, 1) != "\"") return -1; e = index(substr(s, 2), "\""); if (!e) return -1
      t = substr(s, 2, e - 1); if (index(t, "\\") > 0) bad("a backslash in a string is not supported"); return e }
    BEGIN { want = ENVIRON["WANT"]; n = split(ENVIRON["KNOWN"], kk, " "); for (i = 1; i <= n; i++) known[kk[i]] = 1 }
    { line = $0; sub(/^[ \t]+/, "", line)
      if (line == "" || line ~ /^#/) next
      if (line ~ /^\[/) bad("tables are not supported")
      if (!match(line, /^[a-z_]+[ \t]*=[ \t]*/)) bad("expected key = value")
      key = substr(line, 1, RLENGTH); sub(/[ \t]*=[ \t]*$/, "", key); rest = substr(line, RLENGTH + 1)
      if (!(key in known)) bad("unknown key \"" key "\"")
      if (key in have) bad("duplicate key \"" key "\"")
      have[key] = 1; out = ""; n = 0
      if (substr(rest, 1, 1) == "\"") {
        e = quoted(rest); if (e < 0) bad("unterminated string")
        out = substr(rest, 2, e - 1); n = 1; rest = substr(rest, e + 2)
      } else if (substr(rest, 1, 1) == "[") {
        rest = substr(rest, 2)
        while (1) {
          sub(/^[ \t]+/, "", rest)
          if (substr(rest, 1, 1) == "]") { rest = substr(rest, 2); break }
          e = quoted(rest); if (e < 0) bad("an array holds quoted strings, closed on the same line")
          if (e == 1) bad("an empty array element")
          out = out (n ? "\n" : "") substr(rest, 2, e - 1); n++; rest = substr(rest, e + 2)
          sub(/^[ \t]+/, "", rest)
          if (substr(rest, 1, 1) == ",") rest = substr(rest, 2)
          else if (substr(rest, 1, 1) != "]") bad("expected , or ] in the array")
        }
      } else bad("a value is a quoted string or a one-line array of them")
      sub(/^[ \t]+/, "", rest)
      if (rest != "" && rest !~ /^#/) bad("text after the value")
      if (key == "channel" && out != "main" && out != "stable") bad("channel is \"" out "\", not main or stable")
      if (key == want) { val = out; cnt = n }
    }
    END { if (!err && cnt != "") print val }'
}

# The harbor.toml keys: core's own, then every key an installed pack declares in its conf-keys.txt
# (installed at <config dir>/conf-keys.d/<repo-id>.txt by bin/pack.sh), so core names no pack's key
# (#949, CONTRACTS/pack.md). CONF_KEYS_LEGACY were core keys before that: still read, for one release,
# so a box whose harbor.toml carries them keeps working until its pack declares them; then they go.
CONF_KEYS_CORE='packs components channel deliverables_dir worklog_repo mail_account github_owners browser_live_url live_walk_repo confinement_strict confinement_credentials confinement_skip'
CONF_KEYS_LEGACY='reconcile_bq_project antibot_trap_param gads_secret_project'
conf_keys() {
  __ck="$CONF_KEYS_CORE $CONF_KEYS_LEGACY"
  for __kf in "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/conf-keys.d/*.txt; do
    [ -f "$__kf" ] || continue
    __ck="$__ck $(tr -d '\r' < "$__kf" | awk '/^[a-z][a-z0-9_]*$/ { printf "%s ", $0 }')"
  done
  printf '%s' "$__ck"
}

conf_get() { # <key> → value; channel defaults to main; every other key, components included, exits 1 when unset (harbor#1149)
  case " $(conf_keys) " in
    *" $1 "*) ;;
    *) echo "roots: '$1' is not a harbor.toml key ($(conf_keys | sed 's/ *$//; s/ /, /g'))" >&2; return 2 ;;
  esac
  __cf="$(private_dir)/harbor.toml" || return 2
  __v=""
  if [ -f "$__cf" ]; then __v="$(toml_get "$__cf" "$1")" || return 2; fi
  if [ -z "$__v" ]; then
    case "$1" in channel) __v=main ;; *) return 1 ;; esac
  fi
  printf '%s\n' "$__v"
}

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  --list)
    printf '%-24s %-6s %s\n' VAR BASE RESOLVED
    # Resolved for a human, PORT_ROOT honoured: the answer --get would give with no override set.
    rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
      __p="$(resolved_prefix "$__b")" || exit 2
      printf '%-24s %-6s %s\n' "$__v" "$__b" "$__p/$__r"
    done
    ;;
  --get)
    [ -n "${2:-}" ] || { echo "roots: --get needs a variable name" >&2; exit 2; }
    [ -n "$(expected_for "$2")" ] || { echo "roots: $2 is not in $TABLE" >&2; exit 2; }
    # The caller's own override still wins — the table supplies the DEFAULT,
    # never the answer. A resolver that ignored an exported value would make
    # every override in the tree a lie. The name is a table row (matched
    # exactly above), so the indirection below cannot be handed a command.
    eval "__ov=\"\${$2:-}\""
    if [ -n "$__ov" ]; then printf '%s\n' "$__ov"
    else
      __d="$(default_for "$2")"
      [ -n "$__d" ] || { echo "roots: $2 has no default on this box (HOME and PORT_ROOT are both unset)" >&2; exit 2; }
      printf '%s\n' "$__d"
    fi
    ;;
  --repos)
    __out="$(repos_list)" || exit $?
    [ -z "$__out" ] || printf '%s\n' "$__out"
    ;;
  --repo)
    [ -n "${2:-}" ] || { echo "roots: --repo needs a repo id" >&2; exit 2; }
    case "$2" in *[!A-Za-z0-9._-]*|.*) echo "roots: '$2' is not a repo name" >&2; exit 2 ;; esac
    __rf="$(private_dir)/repos.tsv" || exit 2
    __out="$(repos_list)" || exit $?
    # Unknown is non-zero and prints nothing on stdout: an empty path must never reach a caller's cd.
    __hit="$(printf '%s\n' "$__out" | I="$2" awk -F'\t' '$1 == ENVIRON["I"] { print $2; exit }')"
    # No registry on this box is the old literal, PORT_ROOT/<id>, whether or not it exists; "not
    # registered" is only said when a registry exists and lacks the row (harbor#966).
    if [ -z "$__hit" ] && [ ! -f "$__rf" ]; then __hit="$(port_root)/$2" || exit 2; fi
    [ -n "$__hit" ] || { echo "roots: no repo '$2' in the registry" >&2; exit 1; }
    printf '%s\n' "$__hit"
    ;;
  --base)
    # The base a table row hangs off, as a path: what bin/launchd-render.sh fills @HOME@ with. The same resolved_prefix --list uses.
    [ -n "${2:-}" ] || { echo "roots: --base needs BOX or REPOS" >&2; exit 2; }
    __bp="$(resolved_prefix "$2")" || exit 2
    printf '%s\n' "$__bp"
    ;;
  --remote)
    [ -n "${2:-}" ] || { echo "roots: --remote needs a repo id" >&2; exit 2; }
    case "$2" in *[!A-Za-z0-9._-]*|.*) echo "roots: '$2' is not a repo name" >&2; exit 2 ;; esac
    __rf="$(private_dir)/repos.tsv" || exit 2
    [ -f "$__rf" ] || { echo "roots: no registry at $__rf, so no repo has a remote" >&2; exit 1; }
    __all="$(registry_load "$__rf")" || exit 2
    __row="$(printf '%s\n' "$__all" | I="$2" awk -F'\t' '$1 == ENVIRON["I"] { print "row\t" $4; exit }')"
    [ -n "$__row" ] || { echo "roots: no repo '$2' in the registry" >&2; exit 1; }
    __hit="${__row#row?}"
    # '-' is the registry's "none": the caller falls back to its own rule, so nothing reaches stdout.
    case "$__hit" in ''|-) echo "roots: repo '$2' has no remote in the registry" >&2; exit 1 ;; esac
    printf '%s\n' "$__hit"
    ;;
  --port-root) port_root || exit $?; printf '\n' ;;
  --private) private_dir || exit $?; printf '\n' ;;
  --access) __out="$(access_dir)" || exit $?; printf '%s\n' "$__out" ;;
  --inject) __out="$(inject_dir)" || exit $?; printf '%s\n' "$__out" ;;
  --projects) __out="$(projects_file)" || exit $?; printf '%s\n' "$__out" ;;
  --registry-check)
    # Optional file ("-" is stdin): harbor scope install validates a registry it has not written yet.
    __reg="${2:-$(private_dir)/repos.tsv}"
    [ "$__reg" = - ] && __reg=/dev/stdin
    [ -f "$__reg" ] || [ "$__reg" = /dev/stdin ] || { echo "roots: no registry at $__reg (nothing to check)" >&2; exit 1; }
    __clean="$(clean_lines "$__reg")" || exit 2
    __rows="$(printf '%s\n' "$__clean" | RF="$__reg" registry_rows /dev/stdin "$ROOT/standards/naming/repo-kinds.tsv")" || exit 2
    [ "$__reg" = /dev/stdin ] || confine "$(port_root)" "$__rows" || exit 2
    printf 'roots --registry-check: green - every row of %s is valid\n' "$__reg"
    ;;
  --conf-keys) printf '%s\n' $CONF_KEYS_CORE ;;   # core's own keys, one per line, for bin/pack.sh (a legacy key a pack may declare)
  --conf)
    [ -n "${2:-}" ] || { echo "roots: --conf needs a key" >&2; exit 2; }
    conf_get "$2" || exit $?
    ;;
  --check)
    FAIL=0; CHECKED=0
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
      echo "roots: $ROOT is not a git checkout — NO file was inspected, and this is not a pass" >&2
      exit 2; }

    # 1 · every site's default equals the table.
    #     Reading the INDEX via git grep, not the working tree: grep here is
    #     ugrep and skips gitignored files, which would report a clean tree by
    #     not looking at it.
    TMPF="${TMPDIR:-/tmp}/harbor-roots.$$"
    trap 'rm -f "$TMPF"' EXIT INT TERM
    rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
      printf '%s\t%s\n' "$__v" "$(prefix_for "$__b")/$__r"
    done > "$TMPF"

    while IFS="$(printf '\t')" read -r VAR WANT; do
      [ -n "$VAR" ] || continue
      # Every occurrence of ${VAR:-...}, whatever surrounds it.
      # One nested ${...} is stepped over (the PORT_ROOT spelling); [^}$] and \$[^{}] keep the
      # alternation unambiguous, so a flat default and a nested one both read to their own end.
      git -C "$ROOT" grep -hoE '\$\{'"$VAR"':-(\$\{[^}]*\}|[^}$]|\$[^{}])*\}' -- . \
          ':!EVALS-DATA' ':!*/EVALS/*' 2>/dev/null |
        sort -u |
        while IFS= read -r HIT; do
          GOT="${HIT#\$\{$VAR:-}"; GOT="${GOT%\}}"
          RAW="$GOT"
          GOT="$(printf '%s' "$GOT" | sed 's|\${PORT_ROOT:-\$HOME/port}|$HOME/port|')"
          # THREE SHAPES ARE NOT A DISAGREEMENT, and each was measured on this
          # tree before the list existed. A rule that flagged them would fire on
          # correct code, and a rule that fires on correct code gets switched
          # off (CONSTITUTION No.2.11) — taking the real disagreements with it.
          case "$GOT" in
            '')     continue ;;   # ${VAR:-} — a presence test, not a path
            *'$('*) continue ;;   # a SELF-LOCATING default, e.g. memory-route.sh
                                  # deriving the repo from $0. Strictly better
                                  # than a literal: it survives the move with no
                                  # edit at all, which is the outcome this table
                                  # is trying to buy.
            */*)    ;;            # path-shaped — the only shape to compare
            *)      continue ;;   # ${HARBOR_REPO:-none}, a printf placeholder
          esac
          CHECKED=$((CHECKED + 1))
          if [ "$GOT" = "$WANT" ]; then
            # Equal as text is not enough for a REPOS row: spelled flat, the site answers
            # $HOME/port on a machine whose workspace is elsewhere (harbor#630).
            case "$WANT:$RAW" in
              '$HOME/port/'*:'$HOME/port/'*)
                log_fail "$VAR default is spelled flat ($RAW) and ignores PORT_ROOT"
                log_nofix "spell it \${PORT_ROOT:-\$HOME/port}/${WANT#\$HOME/port/} so an exported PORT_ROOT is honoured"
                echo x >> "$TMPF.fail" ;;
            esac
            continue
          fi
          log_fail "$VAR default is $GOT, table says $WANT"
          log_nofix "${TABLE#$ROOT/} — edit the drifted default, or the site above, to match"
          echo x >> "$TMPF.fail"
        done
    done < "$TMPF"

    # 2 · a ${VAR:-...} naming a governed repo whose VAR is NOT in the table.
    #     This is the arm that catches the NEXT one, and the reason the table is
    #     a gate rather than a list: a list only records what someone remembered.
    #     The repo ids are the registry's (repos_list), never a list here (harbor#1273): no registry is the
    #     roots table's repos alone, so this arm sees fewer repos and says so. Ids are [A-Za-z0-9._-]; dots escaped.
    __ids="$(repos_list)" || exit 2
    REPOS_RE="$(printf '%s\n' "$__ids" | awk -F'\t' 'NF { gsub(/\./, "\\.", $1); printf "%s%s", (n++ ? "|" : ""), $1 }')"
    [ -f "$(private_dir)/repos.tsv" ] || log_note "no repo registry: arm 2 checks the roots table's repos only ($REPOS_RE)"
    KNOWN="$(rows | awk -F'\t' '{printf "%s|", $1}')KNOWN_NONE"
    #     Anchored on a default that STARTS with the home prefix: `${BIN:-$_self_dir,
    #     $HOME/port/harbor/bin}` in bin/harbor is a help STRING listing where it
    #     looked, not a root, and flagging it would be the false positive above
    #     wearing a different hat.
    #     `(port/)?` BECAUSE THE BASE MOVED (harbor#619). Anchored on `$HOME/<repo>`
    #     alone, this arm went blind the day every default became
    #     `$HOME/port/<repo>`: an unregistered root spelled the NEW way matched
    #     nothing and the check stayed green. Optional rather than required, so a
    #     new variable still spelling the pre-move address is caught too.
    #     And the nested spelling, for the same reason: a root written
    #     `${PORT_ROOT:-$HOME/port}/<repo>` must not hide from the arm that finds new ones.
    #     The repo name ends at / or the closing brace: `.../harbor-private` is the private
    #     layer (roots.sh --private), a different root, not a spelling of harbor.
    git -C "$ROOT" grep -hoE '\$\{[A-Z_]+:-(\$HOME/(port/)?|\$\{PORT_ROOT:-\$HOME/port\}/)('"$REPOS_RE"')(/[^}]*)?\}' -- . \
        ':!EVALS-DATA' ':!*/EVALS/*' 2>/dev/null |
      sed -E 's/^\$\{([A-Z_]+):-.*/\1/' | sort -u |
      while IFS= read -r V; do
        [ -n "$V" ] || continue
        case "|$KNOWN|" in *"|$V|"*) continue ;; esac
        log_fail "$V names a governed repo and is not in ${TABLE#$ROOT/}"
        log_nofix "${TABLE#$ROOT/} — add a row for $V"
        echo x >> "$TMPF.fail"
      done

    # 3 · a table row nothing uses. A dead row is not harmless: it is a rule
    #     that can never fire, and a suite of rules that can never fire is how a
    #     green run stops meaning anything.
    rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
      git -C "$ROOT" grep -qE "\\\$\\{$__v:-" -- . ':!EVALS-DATA' ':!*/EVALS/*' 2>/dev/null && continue
      log_fail "$__v is in the table and used nowhere"
      log_nofix "${TABLE#$ROOT/} — remove the $__v row"
      echo x >> "$TMPF.fail"
    done

    # 4 · two variables for one path need a stated reason. The table showed
    #     PROJECT_INIT_SRC and HARBOR_PROJECT_INIT as one repo under two names, and
    #     nothing recorded whether that was a decision (harbor#630). Merging them
    #     changes an env contract suites and operators set by hand, so the pair
    #     stays; what is refused is a pair nobody explained. The reason is the fifth
    #     column of EVERY row sharing the path (no # in it: a # starts a comment).
    rows | awk -F'\t' '{ k = $2 SUBSEP $3; n[k]++; if ($5 == "") miss[k] = miss[k] " " $1; who[k] = who[k] " " $1 }
        END { for (k in n) if (n[k] > 1 && miss[k] != "") { gsub(/^ /, "", who[k]); gsub(/^ /, "", miss[k]); print who[k] "\t" miss[k] } }' |
      while IFS="$(printf '\t')" read -r __who __miss; do
        log_fail "$__who name one path; no reason on: $__miss (fifth column)"
        log_nofix "${TABLE#$ROOT/} — merge the names, or give each row a reason the pair is deliberate"
        echo x >> "$TMPF.fail"
      done

    if [ -f "$TMPF.fail" ]; then
      N="$(wc -l < "$TMPF.fail" | tr -d ' ')"; rm -f "$TMPF.fail"
      # The per-hit FAILs above are printed live, from inside a piped subshell (harbor#630's own
      # fix for the same problem this file's loops have): their counts do not survive back to this
      # shell. This FAIL, called here in the parent, is what log_end actually tallies and exits on.
      log_fail "$N disagreement(s) against ${TABLE#$ROOT/} — see the FAIL lines above"
      log_nofix "${TABLE#$ROOT/} — edit the drifted defaults, sites or rows named above"
      log_end; exit $?
    fi
    # --check's success line is protocol (CONTRACTS/logging.md): byte-identical stdout, so a caller
    # that only reads stdout (bin/live-verify.sh, lint ROOT1) keeps working unchanged.
    _rc=0
    log_ok "every root default matches ${TABLE#$ROOT/}"
    log_end || _rc=$?
    printf 'roots --check: green — every root default matches %s\n' "${TABLE#$ROOT/}"
    exit "$_rc"
    ;;
  -h|--help|'') usage ;;
  *) echo "roots: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
esac
