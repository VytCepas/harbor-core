#!/usr/bin/env sh
# scope-roots.sh — resolve the named roots in contracts/roots.tsv, and check that the
# tree's own defaults agree with them. harbor#630.
#
#   sh scope-roots.sh --list         every row, resolved against this box
#   sh scope-roots.sh --get <VAR>    one resolved path, for a script to consume
#   sh scope-roots.sh --aliases      old TAB new, the renamed rows --get answers by their old names until 2026-11-15 (harbor#961 W5; W9's until 2026-12-01)
#   sh scope-roots.sh --repos        each governed repo once: <name> TAB <resolved checkout> (harbor#829)
#   sh scope-roots.sh --check        every ${VAR:-...} default matches, honours PORT_ROOT, is registered; a shared path has a reason
#   sh scope-roots.sh --id <VAR>     the repo a REPOS row names: a role row's (scaffolder, fleet controller) registry id by kind, else the table's (harbor#966)
#   sh scope-roots.sh --repo <id>    one repo's checkout from the registry (PORT_ROOT/<id> with no registry; exit 1, empty, when a registry lacks it) (harbor#966)
#   sh scope-roots.sh --remote <id>  one repo's clone URL from the registry's remote column; exit 1, empty, with no registry, no such row, or remote '-' (harbor#966)
#   sh scope-roots.sh --get <VAR>    (above) follows repos.tsv for a REPOS row: the registry's path replaces the row's first segment; a role row finds its repo by kind (harbor#966)
#   sh scope-roots.sh --registry-check   every repos.tsv row valid: id, path and symlinks inside PORT_ROOT, kind, topology and interaction known; an optional 7th column is a free note (`proposed`: a guessed value awaiting a yes)
#   sh scope-roots.sh --rows         every validated row, all eleven columns (id path kind remote topology interaction note domain governed owner covers; '-' where a short row has none): what bin/scope-repos-generate.sh reads (harbor#966)
#   sh scope-roots.sh --topology <id>    one repo's topology TAB interaction mode from the registry ('-' TAB '-' on a four-column row); exit 1, empty, with no registry or no such row (harbor#966)
#   sh scope-roots.sh --platform-ids     the platform's own repos, one id per line: registry rows of a platform kind (control-plane, scaffolder,
#                                    fleet-controller), else the roots table's HARBOR_SCOPE_REPO / _SCAFFOLDER / _FLEET_CONTROLLER rows (harbor#966)
#   sh scope-roots.sh --port-root | --private   the workspace root, the private layer's directory
#   sh scope-roots.sh --access       the access register (<private>/access, or $ACCESS_DIR); exit 1, empty, when there is none
#   sh scope-roots.sh --inject       the private rules (<private>/context-rules); exit 1, empty, when there is none
#   sh scope-roots.sh --projects     the project registry (<rules>/user/projects.tsv); exit 1, empty, when there is none
#   sh scope-roots.sh --conf <key>   one value from harbor.toml (an array prints one element per line)
#   sh scope-roots.sh --conf-keys    core's own harbor.toml keys, one per line (a pack's keys come from its conf-keys.txt)
#   sh scope-roots.sh --base <BOX|REPOS>   what a base is on this box ($HOME, or the workspace root): the text a launchd template's @HOME@ fills (harbor#630)
#   sh scope-roots.sh --hub          a member box's hub clone, from member.conf beside the marker, else managed env; exit 1, empty, elsewhere or before a clone (harbor#1278)
#
# THE REGISTRY (contracts/private-layer.md). <private>/repos.tsv is id/path/kind/remote and the one
# reader of it is this file; --repos and --repo answer from it, and from the table below when it is
# absent (--repo then prints PORT_ROOT/<id>, the old literal), so a box with no private layer behaves as before.
# Why (harbor#630, measured 2026-09-23): 91 lines name a repo root and 13 go through an override variable, written one at a
# time (PROJECT_INIT_SRC and HARBOR_SCOPE_SCAFFOLDER name one repo twice); a default at its use site drifts from its siblings
# because nothing compares them. The base is symbolic so harbor#619's move under PORT_ROOT is one edit in repos_prefix().
# Deliberately not read by the floor: bin/library-admission.sh keeps its own literal PORT_ROOT default (POSIX, hash-pinned per
# file by B6, no I/O it does not control) and ROOT1 checks the two agree. One source of truth needs a check, not one source of bytes.
# Removed notes: docs/explanation/code-cases/bin-scope-roots.md
set -eu

# ${0%/*}, not $(dirname -- "$0"): a failed dirname makes `cd -- ""` stay put and SRC become the session cwd (harbor#810, #813).
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
TABLE="${HARBOR_SCOPE_ROOTS_TABLE:-$ROOT/contracts/roots.tsv}"
# Installed (harbor#966): no contracts/ above bin/, so the table ships beside this file as roots.tsv.
[ -f "$TABLE" ] || [ -n "${HARBOR_SCOPE_ROOTS_TABLE:-}" ] || ! [ -f "$SRC/roots.tsv" ] || TABLE="$SRC/roots.tsv"
# contracts/logging.md channel 1. LOG_FD=2: --get and --list print DATA on stdout (a value, a
# table), and --check's success line is that same protocol — every log-lib line stays on stderr.
. "$SRC/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2

[ -f "$TABLE" ] || { echo "roots: no table at $TABLE" >&2; exit 2; }

# harbor#961 W5: the roots that took registered names (standards/naming/renames.tsv), old TAB new. Until 2026-11-15 the old name
# is still asked for and read as an override when the new one is unset (the dual-read window); past it, delete the line.
W5_ALIASES='HARBOR_ORCHESTRATOR	HARBOR_SCOPE_FLEET_CONTROLLER
HARBOR_PROJECT_INIT	HARBOR_SCOPE_SCAFFOLDER
HARBOR_ORCH_BIN	HARBOR_SCOPE_FLEET_CONTROLLER_BIN'
# harbor#967 W9: the red-team corpus root took the eval family's name; the same window, until 2026-12-01.
W9_ALIASES=''
ROOT_ALIASES="$W5_ALIASES
$W9_ALIASES"
w5_new() { printf '%s\n' "$ROOT_ALIASES" | awk -F'\t' -v n="$1" '$1 == n { print $2; f = 1 } END { if (!f) print n }'; }
w5_old() { printf '%s\n' "$ROOT_ALIASES" | awk -F'\t' -v n="$1" '$2 == n { print $1 }'; }

# The one line the ~/port move edits (harbor#619, 2026-09-23). Returns the LITERAL TEXT a default is expected to spell, since
# ROOT1 compares source text and `$HOME` in a script is four characters. A site may spell it flat (which IGNORES an exported
# PORT_ROOT and is refused for a REPOS row, harbor#630) or nested (PORT_ROOT with that text as default, which honours it);
# --check steps over one nested ${...} and normalises it back to this text.
repos_prefix() { printf '%s' '$HOME/port'; }
box_prefix()   { printf '%s' '$HOME'; }

prefix_for() { # <base> → the TEXT a default spells (what --check compares)
  case "$1" in
    REPOS) repos_prefix ;;
    BOX)   box_prefix ;;
    *)     echo "roots: unknown base '$1'" >&2; return 1 ;;
  esac
}

# The same base as a PATH: REPOS is the workspace root and honours an exported PORT_ROOT (harbor#630).
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
    # A REPOS row follows the private registry when it holds the repo (harbor#966), so a renamed or moved
    # checkout is one edit there; with no registry, or no such row, the table's own path stands.
    if [ "$__b" = REPOS ]; then
      __id="${__r%%/*}"
      # A role repo by its kind first, so a renamed scaffolder or fleet controller is found under its new id.
      if __rr="$(role_row "$__id")"; then __hit="${__rr#*	}"; else __hit="$(repo_path "$__id")" || __hit=""; fi
      if [ -n "$__hit" ]; then
        case "$__r" in */*) printf '%s/%s' "$__hit" "${__r#*/}" ;; *) printf '%s' "$__hit" ;; esac
        return 0
      fi
    fi
    printf '%s/%s' "$__rp" "$__r"
    return 0
  done
}

# ── the private layer: registry and config (harbor#966, contracts/private-layer.md) ──────────────
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

# The hub clone of a member box (harbor#1278, F3, M5). Off the marker, role and repo come from managed env, never harbor.toml (inside the write zone a session
# can change) and never a scope override. Beside the marker, from <managed root>/member.conf through library-hub.sh's hub_facts, as every floor script reads
# them: a launch environment can beat settings env. Exit 1 on any other box. Always run in a $(...), so the facts it sets stay there.
hub_dir() {
  if [ -e "$SRC/harbor-member-mode" ]; then
    case "$0" in */*) ;; *) return 1 ;; esac   # hub_facts finds the root from $0
    [ -f "$SRC/library-hub.sh" ] || return 1
    . "$SRC/library-hub.sh"
    hub_marker && hub_facts || return 1
  fi
  [ "${HARBOR_MEMBER_ROLE:-}" = member ] && [ -n "${HARBOR_HUB_REPO:-}" ] || return 1
  __hs="${XDG_STATE_HOME:-${HOME:+$HOME/.local/state}}"
  [ -n "$__hs" ] && [ -d "$__hs/harbor/hub/repo" ] || return 1
  printf '%s' "$__hs/harbor/hub/repo"
}

# The access register (contracts/access-card.md) names accounts, so it is private and core ships none; $ACCESS_DIR wins.
# Absent is exit 1 with nothing on stdout, so a reader never cds into or passes against an empty path (harbor#1149).
access_dir() {
  __ad="${ACCESS_DIR:-}"
  if [ -n "$__ad" ]; then
    [ -d "$__ad" ] || { echo "roots: ACCESS_DIR is $__ad, which is not a directory" >&2; return 1; }
  else
    __pv="$(private_dir)" || return 2
    [ -d "$__pv" ] || { echo "roots: no private layer at $__pv, so there is no access register (contracts/private-layer.md)" >&2; return 1; }
    __ad="$__pv/access"
    [ -d "$__ad" ] || { echo "roots: the private layer at $__pv has no access/ directory (contracts/private-layer.md)" >&2; return 1; }
  fi
  printf '%s' "${__ad%/}"
}

# The private rules (contracts/private-layer.md, harbor#1149): <private>/context-rules, shaped like core's context-rules/ (user/
# plus one folder per repo, seeded by `context-injection-install.sh --projects`). They name clients, so core ships none;
# the installer takes .md packs and projects.tsv only. Absent is exit 1 with nothing on stdout.
inject_dir() {
  __pv="$(private_dir)" || return 2
  [ -d "$__pv" ] || { echo "roots: no private layer at $__pv, so there are no private rule packs (contracts/private-layer.md)" >&2; return 1; }
  [ -d "$__pv/context-rules" ] || { echo "roots: the private layer at $__pv has no context-rules/ directory (contracts/private-layer.md)" >&2; return 1; }
  printf '%s' "$__pv/context-rules"
}
projects_file() {
  __id="$(inject_dir)" || return $?
  __pf="$__id/user/projects.tsv"
  [ -f "$__pf" ] || { echo "roots: no project registry at $__pf (contracts/private-layer.md)" >&2; return 1; }
  printf '%s' "$__pf"
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

# Rows validated and printed as id TAB path TAB kind TAB remote TAB topology TAB interaction TAB note TAB domain TAB governed TAB
# owner TAB covers (a shorter row prints '-' for what it lacks, harbor#966). A row resolving outside PORT_ROOT, repeating an id or
# path (case-insensitively), or with other than four, six, seven or eleven fields refuses the whole read (exit 2): skipping a bad
# row answers "unknown" for a mistyped repo. One trailing / is dropped; this pass is lexical, confine() follows symlinks. Kinds,
# topologies and modes are judged only when a kinds file is given (--registry-check).
registry_rows() { # <repos.tsv, or /dev/stdin> [<repo-kinds.tsv>] — the file name in messages is $RF
  RF="${RF:-$1}" KF="${2:-}" awk -F'\t' '
    function bad(m) { printf "roots: %s:%d: %s\n", ENVIRON["RF"], NR, m > "/dev/stderr"; err = 1 }
    BEGIN { kf = ENVIRON["KF"]; tf = ENVIRON["TF"]
            if (kf != "") while ((getline l < kf) > 0) { if (l ~ /^#/ || l ~ /^id\t/) continue; split(l, f, "\t"); if (f[1] != "") kind[f[1]] = 1 }
            if (tf != "") while ((getline l < tf) > 0) { if (l ~ /^#/) continue; split(l, f, "\t"); if (f[2] ~ /(^|,)domain(,|$)/) dom[f[1]] = 1 } }
    /^[ \t]*#/ || /^[ \t]*$/ || $1 == "id" { next }
    { if (NF != 4 && NF != 6 && NF != 7 && NF != 11) { bad("expected id, path, kind, remote[, topology, interaction[, note[, domain, governed, owner, covers]]] (tab-separated), got " NF " field(s)"); next }
      tp = (NF >= 6) ? $5 : "-"; im = (NF >= 6) ? $6 : "-"
      nt = (NF >= 7) ? $7 : "-"; dm = (NF == 11) ? $8 : "-"; gv = (NF == 11) ? $9 : "-"; ow = (NF == 11) ? $10 : "-"; cv = (NF == 11) ? $11 : "-"
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
      if (kf != "" && tp !~ /^(platform|stream-aligned|enabling|complicated-subsystem|-)$/) { bad("topology \"" tp "\" is not platform, stream-aligned, enabling, complicated-subsystem or -"); next }
      if (kf != "" && im !~ /^(x-as-a-service|collaboration|facilitating|-)$/) { bad("interaction \"" im "\" is not x-as-a-service, collaboration, facilitating or -"); next }
      if (NF == 11) {
        if (dm == "" || gv == "" || ow == "" || cv == "") { bad("domain, governed, owner and covers are never empty; write - for none"); next }
        if (dm != "-" && dm !~ /^[a-z][a-z0-9-]*$/) { bad("domain \"" dm "\" is not a lowercase word or -"); next }
        if (tf != "" && dm != "-" && !(dm in dom)) { bad("domain \"" dm "\" is not a domain term in " tf); next }
        if (gv !~ /^(yes|no|-)$/) { bad("governed \"" gv "\" is not yes, no or -"); next }
        if (ow != "-" && ow !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) { bad("owner \"" ow "\" is not a name or -"); next }
        if (length(cv) > 300) { bad("covers is " length(cv) " characters, over the 300 a one-line routing hint keeps"); next }
      }
      seen[$1] = 1; pathseen[lp] = $1
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, p, $3, $4, tp, im, nt, dm, gv, ow, cv }
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

repo_path() { # <id> → the registry's checkout for that id; exit 1, empty, with no registry or no such row
  [ -f "$(private_dir)/repos.tsv" ] || return 1
  repos_list | I="$1" awk -F'\t' '$1 == ENVIRON["I"] { print $2; f = 1; exit } END { exit f ? 0 : 1 }'
}

# A ROLE REPO FOLLOWS THE REGISTRY BY KIND (harbor#966): a rename changes a registry row's id and path but not its kind, so
# the table's id would answer the old name. Exactly one row of the kind is the answer; none or two fall back to the id.
role_kind() { # <id, a REPOS row's first segment> → the kind its role row names, or nothing
  rows | I="$1" awk -F'\t' '$2 == "REPOS" { n = $3; sub(/\/.*/, "", n); if (n != ENVIRON["I"]) next
    if ($1 == "HARBOR_SCOPE_SCAFFOLDER") { print "scaffolder"; exit }
    if ($1 == "HARBOR_SCOPE_FLEET_CONTROLLER") { print "fleet-controller"; exit } }'
}
role_row() { # <id> → id TAB checkout of the one registry row of its role's kind; exit 1 otherwise, 2 on a refused registry
  __k="$(role_kind "$1")"; [ -n "$__k" ] || return 1
  __rf="$(private_dir)/repos.tsv" || return 2
  [ -f "$__rf" ] || return 1
  __all="$(registry_load "$__rf")" || return 2
  __root="$(port_root)" || return 2
  printf '%s\n' "$__all" | K="$__k" R="$__root" awk -F'\t' '$3 == ENVIRON["K"] { n++; o = $1 "\t" ENVIRON["R"] "/" $2 }
    END { if (n == 1) print o; exit n == 1 ? 0 : 1 }'
}

# harbor.toml, the flat subset: key = "value" or key = ["a", "b"] on one line, no tables. Anything else (unknown or duplicate
# keys, a backslash or empty string in a value) is refused (exit 2): a typo read as "unset" would silently install the default.
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

# Core's own keys, then every key an installed pack declares in <config dir>/conf-keys.d/<repo-id>.txt (bin/pack.sh; #949, contracts/pack.md).
CONF_KEYS_CORE='packs components channel deliverables_dir worklog_repo mail_account github_owners browser_live_url live_walk_repo confinement_strict confinement_credentials confinement_skip'
conf_keys() {
  __ck="$CONF_KEYS_CORE"
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
  --aliases) printf '%s\n' "$ROOT_ALIASES" ;;   # old TAB new: names --get still answers until 2026-11-15 (W5) or 2026-12-01 (W9)
  --get)
    [ -n "${2:-}" ] || { echo "roots: --get needs a variable name" >&2; exit 2; }
    # harbor#961 W5: the old names of two repo roots are still read as overrides until 2026-11-15 (renames.tsv dual-read window).
    __gv="$2"; __go=""
    __gv="$(w5_new "$__gv")"; __go="$(w5_old "$__gv")"
    [ -n "$(expected_for "$__gv")" ] || { echo "roots: $2 is not in $TABLE" >&2; exit 2; }
    # The caller's own override wins: the table supplies the DEFAULT, never the answer. The name is a table row (matched
    # exactly above), so the indirection below cannot be handed a command.
    eval "__ov=\"\${$__gv:-}\""
    [ -n "$__ov" ] || [ -z "$__go" ] || eval "__ov=\"\${$__go:-}\""
    if [ -n "$__ov" ]; then printf '%s\n' "$__ov"
    else
      __d="$(default_for "$__gv")"
      [ -n "$__d" ] || { echo "roots: $2 has no default on this box (HOME and PORT_ROOT are both unset)" >&2; exit 2; }
      printf '%s\n' "$__d"
    fi
    ;;
  --id)
    # The repo a REPOS row names, by id: the registry's row for a role (by kind), else the table's first segment.
    # An override names a checkout, not a repo, so it is not read here.
    [ -n "${2:-}" ] || { echo "roots: --id needs a variable name" >&2; exit 2; }
    __gv="$(w5_new "$2")"
    __rel="$(rows | V="$__gv" awk -F'\t' '$1 == ENVIRON["V"] && $2 == "REPOS" { print $3; exit }')"
    [ -n "$__rel" ] || { echo "roots: $2 is not a REPOS row of $TABLE" >&2; exit 2; }
    __id="${__rel%%/*}"
    if __rr="$(role_row "$__id")"; then printf '%s\n' "${__rr%%	*}"; else printf '%s\n' "$__id"; fi
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
    # The base a table row hangs off, as a path: what bin/deploy-launchd-render.sh fills @HOME@ with. The same resolved_prefix --list uses.
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
  --rows)
    __rf="$(private_dir)/repos.tsv" || exit 2
    [ -f "$__rf" ] || { echo "roots: no registry at $__rf, so there are no rows" >&2; exit 1; }
    registry_load "$__rf" || exit 2
    ;;
  --topology)
    [ -n "${2:-}" ] || { echo "roots: --topology needs a repo id" >&2; exit 2; }
    case "$2" in *[!A-Za-z0-9._-]*|.*) echo "roots: '$2' is not a repo name" >&2; exit 2 ;; esac
    __rf="$(private_dir)/repos.tsv" || exit 2
    [ -f "$__rf" ] || { echo "roots: no registry at $__rf, so no repo has a topology" >&2; exit 1; }
    __all="$(registry_load "$__rf")" || exit 2
    __row="$(printf '%s\n' "$__all" | I="$2" awk -F'\t' '$1 == ENVIRON["I"] { print $5 "\t" $6; exit }')"
    [ -n "$__row" ] || { echo "roots: no repo '$2' in the registry" >&2; exit 1; }
    printf '%s\n' "$__row"
    ;;
  --platform-ids)
    # The platform's own repos by KIND, not by topology: a workload may be a platform for its users
    # (topology), and is still not harbor's. No registry: the three role rows of the roots table.
    __rf="$(private_dir)/repos.tsv" || exit 2
    if [ -f "$__rf" ]; then
      __all="$(registry_load "$__rf")" || exit 2
      printf '%s\n' "$__all" | awk -F'\t' '$3 ~ /^(control-plane|scaffolder|fleet-controller)$/ { print $1 }'
    else
      rows | awk -F'\t' '$2 == "REPOS" && $1 ~ /^(HARBOR_SCOPE_REPO|HARBOR_SCOPE_SCAFFOLDER|HARBOR_SCOPE_FLEET_CONTROLLER)$/ {
        n = $3; sub(/\/.*/, "", n); if (n != "" && !seen[n]++) print n }'
    fi
    ;;
  --port-root) port_root || exit $?; printf '\n' ;;
  --private) private_dir || exit $?; printf '\n' ;;
  --access) __out="$(access_dir)" || exit $?; printf '%s\n' "$__out" ;;
  --hub) __out="$(hub_dir)" || exit 1; printf '%s\n' "$__out" ;;
  --inject) __out="$(inject_dir)" || exit $?; printf '%s\n' "$__out" ;;
  --projects) __out="$(projects_file)" || exit $?; printf '%s\n' "$__out" ;;
  --registry-check)
    # Optional file ("-" is stdin): harbor scope install validates a registry it has not written yet.
    __reg="${2:-$(private_dir)/repos.tsv}"
    [ "$__reg" = - ] && __reg=/dev/stdin
    [ -f "$__reg" ] || [ "$__reg" = /dev/stdin ] || { echo "roots: no registry at $__reg (nothing to check)" >&2; exit 1; }
    __clean="$(clean_lines "$__reg")" || exit 2
    # The kinds register: the checkout's, or (installed, no standards/ above bin/) the copy runtime-install ships beside this file.
    __kinds="$ROOT/standards/naming/repo-kinds.tsv"
    [ -f "$__kinds" ] || __kinds="$SRC/repo-kinds.tsv"
    [ -f "$__kinds" ] || { echo "roots: no kinds register at $ROOT/standards/naming/repo-kinds.tsv or $SRC/repo-kinds.tsv: no kind can be judged (redeploy: deploy-runtime-install.sh ships it)" >&2; exit 2; }
    # A domain is judged against the terms register when this is a checkout; installed there is none, and the shape check stands.
    __terms="$ROOT/standards/naming/terms.tsv"; [ -f "$__terms" ] || __terms=""
    __rows="$(printf '%s\n' "$__clean" | RF="$__reg" TF="$__terms" registry_rows /dev/stdin "$__kinds")" || exit 2
    [ "$__reg" = /dev/stdin ] || confine "$(port_root)" "$__rows" || exit 2
    printf 'roots --registry-check: green - every row of %s is valid\n' "$__reg"
    ;;
  --conf-keys) printf '%s\n' $CONF_KEYS_CORE ;;   # core's own keys, one per line, for bin/pack.sh (a legacy key a pack may declare)
  --conf)
    [ -n "${2:-}" ] || { echo "roots: --conf needs a key" >&2; exit 2; }
    conf_get "$2" || exit $?
    ;;
  --check)
    CHECKED=0
    git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || {
      echo "roots: $ROOT is not a git checkout — NO file was inspected, and this is not a pass" >&2
      exit 2; }

    # 1 · every site's default equals the table, read via git grep on the INDEX: grep here is ugrep and skips gitignored files.
    TMPF="${TMPDIR:-/tmp}/harbor-roots.$$"
    trap 'rm -f "$TMPF"' EXIT INT TERM
    rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
      printf '%s\t%s\n' "$__v" "$(prefix_for "$__b")/$__r"
    done > "$TMPF"

    while IFS="$(printf '\t')" read -r VAR WANT; do
      [ -n "$VAR" ] || continue
      # Every occurrence of the VAR default form; one nested ${...} is stepped over (the PORT_ROOT spelling).
      git -C "$ROOT" grep -hoE '\$\{'"$VAR"':-(\$\{[^}]*\}|[^}$]|\$[^{}])*\}' -- . \
          ':!evals' ':!*/EVALS/*' 2>/dev/null |
        sort -u |
        while IFS= read -r HIT; do
          GOT="${HIT#\$\{$VAR:-}"; GOT="${GOT%\}}"
          # harbor#961 W5: a dual-read reader is ${NEW:-${OLD:-<default>}} until 2026-11-15; the default is the inner one
          __vo="$(w5_old "$VAR")"
          if [ -n "$__vo" ] && [ "${GOT#\$\{$__vo:-}" != "$GOT" ]; then
            GOT="${GOT#\$\{$__vo:-}"
            case "$GOT" in *'${'*) ;; *'}') GOT="${GOT%\}}" ;; esac   # a flat inner default: the match took its closing brace
          fi
          RAW="$GOT"
          GOT="$(printf '%s' "$GOT" | sed 's|\${PORT_ROOT:-\$HOME/port}|$HOME/port|')"
          # Three shapes are not a disagreement: a rule flagging correct code gets switched off (No.2.11).
          case "$GOT" in
            '')     continue ;;   # ${VAR:-} — a presence test, not a path
            *'$('*) continue ;;   # a SELF-LOCATING default, e.g. memory-route.sh
            */*)    ;;            # path-shaped — the only shape to compare
            *)      continue ;;   # ${HARBOR_SCOPE_REPO:-none}, a printf placeholder
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

    # 2 · a default naming a governed repo whose VAR is NOT in the table: the arm that catches the NEXT one. The repo ids are
    # the registry's (repos_list), never a list here (harbor#1273); no registry means the roots table's repos alone.
    __ids="$(repos_list)" || exit 2
    REPOS_RE="$(printf '%s\n' "$__ids" | awk -F'\t' 'NF { gsub(/\./, "\\.", $1); printf "%s%s", (n++ ? "|" : ""), $1 }')"
    [ -f "$(private_dir)/repos.tsv" ] || log_note "no repo registry: arm 2 checks the roots table's repos only ($REPOS_RE)"
    KNOWN="$(rows | awk -F'\t' '{printf "%s|", $1}')KNOWN_NONE"
    KNOWN="$KNOWN|$(printf '%s\n' "$ROOT_ALIASES" | cut -f1 | paste -sd'|' -)"   # harbor#961 W5: old names, read inside their new rows' readers until 2026-11-15
    # Anchored on a default that STARTS with the home prefix: a help STRING listing where bin/harbor looked is not a root.
    # `(port/)?` because the base moved (harbor#619): anchored on `$HOME/<repo>` alone this arm went blind. The nested spelling
    # is matched too. The repo name ends at / or the closing brace: `.../harbor-private` is the private layer, a different root.
    git -C "$ROOT" grep -hoE '\$\{[A-Z_]+:-(\$HOME/(port/)?|\$\{PORT_ROOT:-\$HOME/port\}/)('"$REPOS_RE"')(/[^}]*)?\}' -- . \
        ':!evals' ':!*/EVALS/*' 2>/dev/null |
      sed -E 's/^\$\{([A-Z_]+):-.*/\1/' | sort -u |
      while IFS= read -r V; do
        [ -n "$V" ] || continue
        case "|$KNOWN|" in *"|$V|"*) continue ;; esac
        log_fail "$V names a governed repo and is not in ${TABLE#$ROOT/}"
        log_nofix "${TABLE#$ROOT/} — add a row for $V"
        echo x >> "$TMPF.fail"
      done

    # 3 · a table row nothing uses is a rule that can never fire.
    rows | while IFS="$(printf '\t')" read -r __v __b __r __x; do
      git -C "$ROOT" grep -qE "\\\$\\{$__v:-" -- . ':!evals' ':!*/EVALS/*' 2>/dev/null && continue
      log_fail "$__v is in the table and used nowhere"
      log_nofix "${TABLE#$ROOT/} — remove the $__v row"
      echo x >> "$TMPF.fail"
    done

    # 4 · two variables for one path need a stated reason (harbor#630: PROJECT_INIT_SRC and HARBOR_SCOPE_SCAFFOLDER); merging them
    # changes an env contract, so the pair stays. The reason is the fifth column of EVERY row sharing the path (no # in it).
    rows | awk -F'\t' '{ k = $2 SUBSEP $3; n[k]++; if ($5 == "") miss[k] = miss[k] " " $1; who[k] = who[k] " " $1 }
        END { for (k in n) if (n[k] > 1 && miss[k] != "") { gsub(/^ /, "", who[k]); gsub(/^ /, "", miss[k]); print who[k] "\t" miss[k] } }' |
      while IFS="$(printf '\t')" read -r __who __miss; do
        log_fail "$__who name one path; no reason on: $__miss (fifth column)"
        log_nofix "${TABLE#$ROOT/} — merge the names, or give each row a reason the pair is deliberate"
        echo x >> "$TMPF.fail"
      done

    if [ -f "$TMPF.fail" ]; then
      N="$(wc -l < "$TMPF.fail" | tr -d ' ')"; rm -f "$TMPF.fail"
      # Per-hit FAILs print from a piped subshell (harbor#630) and do not count; this FAIL in the parent is what log_end tallies.
      log_fail "$N disagreement(s) against ${TABLE#$ROOT/} — see the FAIL lines above"
      log_nofix "${TABLE#$ROOT/} — edit the drifted defaults, sites or rows named above"
      log_end; exit $?
    fi
    # --check's success line is protocol (contracts/logging.md): byte-identical stdout, so a caller
    # that only reads stdout (bin/deploy-live-verify.sh, lint ROOT1) keeps working unchanged.
    _rc=0
    log_ok "every root default matches ${TABLE#$ROOT/}"
    log_end || _rc=$?
    printf 'roots --check: green — every root default matches %s\n' "${TABLE#$ROOT/}"
    exit "$_rc"
    ;;
  -h|--help|'') usage ;;
  *) echo "roots: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
esac
