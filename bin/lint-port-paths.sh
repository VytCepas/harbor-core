#!/usr/bin/env sh
# lint-port-paths.sh (harbor#629, harbor#619) — literals naming a repo at its PRE-MOVE address.
# That is ~/<repo>, $HOME/<repo> or <home>/<repo>, where the repo now lives
# under ${PORT_ROOT:-$HOME/port}. Registered in docs/reference/checks.md as `lint.port-paths`.
#   sh bin/lint-port-paths.sh              inventory: one TSV row per hit, exit 0
#   sh bin/lint-port-paths.sh --verify     gate: exit 1 if ANY CODE row remains; logs
#                                     note: CODE=n DOC=n EXEMPT=n (stale: n)
#                                     exit 3 if the scan itself failed (D-29 unchecked: nothing was judged;
#                                     before D-49 it was 2, now a bad argument)
#   sh bin/lint-port-paths.sh --selftest   the matcher, classify() and exemption cases
# Environment: PORT_ROOT (default $HOME/port); PORT_PATHS_EXEMPT (default
# contracts/port-paths-exempt.tsv in this repo, then the private layer's
# port-paths-exempt.tsv; set, it is the only table read); CLAUDE_CONFIG_DIR.
#
# One scan for both: harbor#619's last criterion is "no script or config names a pre-move repo path", and a re-runnable scan closes it where a checklist cannot. Graduated from ~/Deliverables/2026-09-22-r2-workspace-root/ (harbor#629); suite: tests/lint/port-paths/port-paths.test.sh.
# Deliberately one file (lint G1, docs/explanation/modularity.md): the surface list and the matcher are one contract.
# Removed notes: docs/explanation/code-cases/bin-lint-port-paths.md
#
# The match: (~|$HOME|<home>)/<repo> followed by a separator or end. SKILL.md files write ~/<repo>, shell defaults $HOME/<repo>, plists the absolute form (launchd expands nothing). The bare repo NAME would be useless: harbor appears in every com.harbor.* label.
# Grep is ugrep here and the config dir is a git repo, so `grep -r` skips gitignored files and reports a false absence: every scan builds a file list with `find` and greps one file at a time.
# Not covered, on purpose: eval fixtures and historical run logs (evals/, skills/*/EVALS/) record a past run, and rewriting them falsifies it.
# The exclusion pathspec is `:!*/EVALS/*`: a git pathspec with a wildcard is fnmatched against the WHOLE path, so `:!skills/*/EVALS` reads right and excludes nothing (it inflated CODE by 61 historical rows, §2.11). --selftest asserts the exclusion fires because the rows look like real findings.
set -eu

# --help before any work (S4, harbor#140): the first header paragraph, read from this file.
MODE=inventory
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
  --verify)   MODE=verify ;;
  --selftest) MODE=selftest ;;
  '') ;;
  *) HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
     . "$HERE/library-log.sh"; log_init port-paths; LOG_FD=2
     log_fail "unknown argument $1: nothing was scanned"
     log_fix "sh $0 --help"
     log_end || :; exit 2 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The inventory is TSV on stdout, so the log is log-lib's on stderr; --verify and --selftest are runs and log to
# stdout (contracts/logging.md).
. "$ROOT/bin/library-log.sh"
log_init port-paths; LOG_FD=2
[ "$MODE" = inventory ] || LOG_FD=1
HOME_DIR="${HOME:?}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# Every scan reads the physical home, $PORT, never $HOME_DIR/<repo>: the old addresses are bridges that phase C deletes, and every scan is guarded by `[ -d ] || continue`, so the gate would have reported CODE=0 from looking at nothing.
PORT="${PORT_ROOT:-$HOME_DIR/port}"
FLEETF="$(sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/scope-roots.sh" --get HARBOR_SCOPE_FLEET_FILE)" || exit 3   # harbor#966

# The repos are derived from $PORT, never listed: a hand list went stale within the hour during the move, and a missing name is a repo whose old address is never matched, a silent green.
# A directory under $PORT with a `.git` is a repo (<repo>); one without, holding repos one level down, is a container (<root>); a worktree is neither, being a second view of a repo already counted. The name was a convention (`<repo>-wt-<name>`); the STRUCTURE is the fact (harbor#629): a `.git` FILE whose common directory lies under $PORT is a view. One whose repository lives elsewhere is still scanned, so a branch can be measured before it merges (case 17).
# TARGETS are what 1b scans (relative to $PORT); NAMES are the first path components, the names a pre-move literal carries. Names go into an ERE unescaped: repo names are [A-Za-z0-9_.-] and the only metacharacter, `.`, over-matches, the safe side.
__phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P; }
__PORTP="$(__phys "$PORT" || printf '%s' "$PORT")"
# is_view <dir> — true when <dir> is a linked worktree of a repository that
# itself lives under $PORT, i.e. a second view of a repo counted already.
is_view() {
  [ -f "$1/.git" ] || return 1
  __cd="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$__cd" in /*) ;; *) __cd="$1/$__cd" ;; esac
  __cdp="$(__phys "$__cd")" || return 1
  case "$__cdp" in "$__PORTP"/*) return 0 ;; esac
  return 1
}
TARGETS=''
NAMES=''
for __d in "$PORT"/*; do
  [ -d "$__d" ] || continue
  __n="${__d##*/}"
  case "$__n" in *-wt-*) continue ;; esac
  is_view "$__d" && continue
  if [ -e "$__d/.git" ]; then
    TARGETS="$TARGETS $__n"; NAMES="$NAMES $__n"; continue
  fi
  __has=0
  for __c in "$__d"/*; do
    [ -d "$__c" ] && [ -e "$__c/.git" ] || continue
    case "${__c##*/}" in *-wt-*) continue ;; esac
    is_view "$__c" && continue
    TARGETS="$TARGETS $__n/${__c##*/}"; __has=1
  done
  [ "$__has" = 0 ] || NAMES="$NAMES $__n"
done

# One alternation, built once. The tail group refuses a LONGER name (~/harborage) and a sibling worktree address (~/zorbcorp-wt-x), since `-` is not a separator; --selftest proves both. `.` is a name character so ~/harbor.md stays unmatched, but a full stop ending a sentence counts as a separator: whitespace, end of line or a closing quote, backtick or paren after it (that hid nine rows before).
alt_of() { __a=''; for __r in $1; do __a="${__a:+$__a|}$__r"; done; printf '%s' "$__a"; }
pat_of() { printf '(~|\\$HOME|%s)/(%s)(/|[^A-Za-z0-9_.-]|$|\\.([[:space:]]|$|["'"'"'`)]))' "$HOME_DIR" "$(alt_of "$1")"; }
ALT="$(alt_of "$NAMES")"
PAT="$(pat_of "$NAMES")"

# CODE or DOC: only CODE gates (a gate demanding every prose mention be rewritten gets switched off, §2.11); DOC is a follow-up list (harbor#629), reported, never a blocker. A path inside a `#` comment cannot break anything at runtime. Refinements, each from a run that got it wrong:
# A shebang is CODE (it decides which interpreter runs).
# Other repos comment in other languages: JS `//` and SQL `--` lines were CODE on the first run. Scoped by extension, because `--` opening a line of a shell script is an argument continuation.
# A path root in markdown is CODE (harbor#653): a `**Path root:**` line is parsed, not read (drift-reference-check.sh REF-5), and filed as DOC the installed constitution's stale root sat under a green gate. Scoped to .md.
# EXEMPT: a row the operator decided to keep, with its reason, in contracts/port-paths-exempt.tsv, matched per LINE (file relative to $PORT plus fixed text), so a new literal in an exempted file still counts. One widening, for DOC only: text `*` exempts a whole file (a dated record is history in every line); it never exempts CODE.
# `@HOME@` in a row's text stands for this box's home, rendered when the table is read: the table is tracked and lint HP1 refuses a tracked file naming its author's home (harbor#602).
#
# Classify, exempt and format are ONE awk program run once over every row (per-row shell pipelines cost rows x table: 126 s for --verify against about 12 s). classify() and is_exempt() are one-row wrappers over it, so --selftest exercises the scan's own code.
# LC_ALL=C: macOS awk is byte-based in substr() and dies on a regex over a lone UTF-8 continuation byte; trunc() counts characters itself so the literal column never ends in half a character.
EXEMPT_FILE="${PORT_PATHS_EXEMPT:-$ROOT/contracts/port-paths-exempt.tsv}"
# The private layer's own rows (clients' directories, harbor#1149) live in a table with the same columns beside the core one. PORT_PATHS_EXEMPT names the only table read, so a fixture stays hermetic; an absent overlay is the core table alone.
EXEMPT_PRIV=''
if [ -z "${PORT_PATHS_EXEMPT:-}" ]; then
  __pd="$(sh "$ROOT/bin/scope-roots.sh" --private 2>/dev/null || :)"
  if [ -n "$__pd" ] && [ -f "$__pd/port-paths-exempt.tsv" ] && [ -r "$__pd/port-paths-exempt.tsv" ]; then EXEMPT_PRIV="$__pd/port-paths-exempt.tsv"; fi
fi
exempt_rows() { cat "$EXEMPT_FILE" 2>/dev/null || :; if [ -n "$EXEMPT_PRIV" ]; then cat "$EXEMPT_PRIV" 2>/dev/null || :; fi; }
FINISH_AWK='
function lstrip(s) { sub(/^[[:space:]]+/, "", s); return s }
function trunc(s, n,   i, k) {
  k = 0
  for (i = 1; i <= length(s); i++)
    if (substr(s, i, 1) !~ /^[\200-\277]$/ && ++k > n) return substr(s, 1, i - 1)
  return s
}
function after(s, n,   k) { for (k = 0; k < n; k++) s = substr(s, index(s, "\t") + 1); return s }
function classify(f, t,   h) {
  if (f ~ /\.(json|yaml|yml|plist)$/) return "CODE"
  if (f ~ /\.md$/) return (index(t, "**Path root:**") > 0 ? "CODE" : "DOC")
  h = substr(lstrip(t), 1, 2)
  if (h == "#!") return "CODE"
  if (f ~ /\.(js|mjs|cjs|ts|tsx)$/ && (h == "//" || h == "/*" || h == "* ")) return "DOC"
  if (f ~ /\.sql$/ && h == "--") return "DOC"
  if (substr(h, 1, 1) == "#") return "DOC"
  return "CODE"
}
function exempt(f, t, c,   rel, i) {
  # An installed copy is judged by the rows of its source (harbor#629): $CFG/skills and $CFG/bin ship out of harbor skills/ and bin/, and CLAUDE.md out of policy/constitution.md (harbor#653); settings, .claude.json and MEMORY/ are copies of nothing. No apostrophes in this program: it is one single-quoted shell string.
  if (cfg != "" && (index(f, cfg "/skills/") == 1 || index(f, cfg "/bin/") == 1))
    rel = "harbor/" substr(f, length(cfg) + 2)
  else if (cfg != "" && f == cfg "/CLAUDE.md") rel = "harbor/policy/constitution.md"
  else if (index(f, port "/") == 1) rel = substr(f, length(port) + 2)
  else return 0
  for (i = 1; i <= nx; i++) {
    if (xf[i] != rel) continue
    if (xt[i] == "*") { if (c == "DOC") return 1; continue }
    if (xt[i] != "" && index(t, xt[i]) > 0) return 1
  }
  return 0
}
BEGIN {
  FS = "\t"; nx = 0
  for (k = 1; k <= 2; k++) {
    f = (k == 1 ? ex : ex2)
    if (f != "") while ((getline l < f) > 0) {
      if (l ~ /^#/) continue
      if (split(l, a, "\t") < 3 || a[1] == "file") continue
      gsub(/@HOME@/, home, a[2])
      nx++; xf[nx] = a[1]; xt[nx] = a[2]
    }
    close(f)
  }
}
mode == "class"  { print classify($1, after($0, 1)); next }
mode == "exempt" { print (exempt($2, after($0, 2), $1) ? "yes" : "no"); next }
{
  t = after($0, 4)
  if ($1 != "?") { printf "%s\t%s\t%s\t%s\t%s\n", $2, $1, $3, $4, t; next }
  c = classify($3, t)
  if (exempt($3, t, c)) c = "EXEMPT"
  printf "%s\t%s\t%s\t%s\t%s\n", $2, c, $3, $4, trunc(lstrip(t), 120)
}'
finish() { LC_ALL=C awk -v mode="$1" -v port="$PORT" -v cfg="$CFG" -v home="$HOME_DIR" -v ex="$2" -v ex2="$EXEMPT_PRIV" "$FINISH_AWK"; }
classify() { printf '%s\t%s\n' "$1" "$2" | finish class ''; }  # <file> <line-text>
is_exempt() { # <abs-file> <line-text> <class>
  [ -f "$EXEMPT_FILE" ] || [ -n "$EXEMPT_PRIV" ] || return 1
  [ "$(printf '%s\t%s\t%s\n' "$3" "$1" "$2" | finish exempt "$EXEMPT_FILE")" = yes ]
}

# A raw row: `?` (classify me) or a fixed class, then surface, file, line, text.
raw() { printf '?\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }

# Scan an explicit list of files, one at a time — never `grep -r`.
scan() {
  __surface="$1"; shift
  for __f in "$@"; do
    [ -f "$__f" ] || continue
    grep -nE "$PAT" "$__f" 2>/dev/null | while IFS=: read -r __ln __txt; do
      raw "$__surface" "$__f" "$__ln" "$__txt"
    done
  done
}

# harbor tracked files, through ONE pathspec: scan 1 and --selftest both call it, since a selftest asserting its own copy would stay green while the scan broke.
# registries/coverage-incidents.tsv is excluded for the EVALS reason (a dated sweep quoting code as it read that day).
# This instrument's own files are excluded too: selftest vectors, suite fixtures and the exemption table ARE pre-move literals quoted as data (suite case 8). Cost: a real pre-move default written here goes unseen; its defaults derive from PORT_ROOT and HOME.
# One list for every repo scan (1b too): harbor-core mirrors these files and the private layer keeps its own exemption table, and scanned there they were 157 of 159 CODE rows. The suite split into tests/install/port-paths/ is listed beside the file it came from.
INSTRUMENT_SPEC=':!bin/lint-port-paths.sh :!tests/lint/port-paths/port-paths.test.sh :!tests/install/port-paths/* :!contracts/port-paths-exempt.tsv :!port-paths-exempt.tsv'
harbor_grep() { # <repo> <git-grep-flags>
  # shellcheck disable=SC2086  # INSTRUMENT_SPEC is pathspecs with no spaces, split on purpose
  git -C "$1" grep "$2" "$PAT" -- . ':!evals' ':!*/EVALS/*' ':!registries/coverage-incidents.tsv' $INSTRUMENT_SPEC 2>/dev/null
}

# --selftest. The load-bearing parts are the regex and classify(); each case was watched FAIL on a mutant (§2.10): dropping the trailing separator group makes "harborage" match, removing the `#` arm of classify() turns the commented case CODE. The matcher is built from FIXED names, so cases do not depend on which repos this box holds.
if [ "$MODE" = selftest ]; then
  PAT="$(pat_of 'harbor zorbcorp quux-core')"
  log_head "selftest"
  t_match() { # description, text, expect-match(1|0)
    if printf '%s' "$2" | grep -qE "$PAT"; then __g=1; else __g=0; fi
    if [ "$__g" = "$3" ]; then log_ok "match: $1"; else log_fail "match: $1"; log_fix "sh $0 --selftest, then read the case in bin/lint-port-paths.sh"; fi
  }
  t_class() { # description, filename, text, expected
    __g="$(classify "$2" "$3")"
    if [ "$__g" = "$4" ]; then log_ok "class: $1"; else log_fail "class: $1 (got $__g want $4)"; log_fix "sh $0 --selftest, then read the case in bin/lint-port-paths.sh"; fi
  }

  # `:=`, not `:-`: lint ROOT1 (scope-roots.sh --check) reads every `${VAR:-<home>/…}`
  # in the tree as a root default, and this is a test vector, not a root.
  t_match 'shell default with $HOME'     'REPO="${HARBOR_SCOPE_REPO:=$HOME/harbor}"'          1
  t_match 'tilde form in a skill'        'read ~/zorbcorp/CLIENTS/ACME/TOPOLOGY.md'       1
  t_match 'absolute form in a plist'     '<string>'"$HOME_DIR"'/zorbcorp</string>'        1
  t_match 'launchd LABEL is not a path'  '<string>com.harbor.audit.triage</string>'             0
  t_match 'helm ledger name'             'CFG/.helm-harbor-state'                        0
  t_match 'repo name with no prefix'     'cd harbor && git status'                       0
  # These three are the only cases that exercise the trailing separator group; the ones above fail on the prefix alternation whatever the tail does.
  t_match 'prefixed but a LONGER name'   "$HOME_DIR/harborage/x"                         0
  t_match 'prefixed, longer, tilde form' '~/zorbcorpal/CLIENTS'                           0
  t_match 'prefixed exact name, at end'  "$HOME_DIR/harbor"                              1
  t_match 'a sibling worktree address'   '~/zorbcorp-wt-docs/x'                           0
  # The full stop: the first two were missed before; the last two are why `.` is still a name character elsewhere.
  t_match 'a path ending a sentence'     'it moved out of ~/harbor. Then'                1
  t_match 'full stop, then end of line'  'see ~/zorbcorp.'                                1
  t_match 'full stop, then a paren'      '(it lived at ~/harbor.)'                       1
  t_match 'a suffix is not a full stop'  'cat ~/harbor.md'                               0
  t_match 'a dotted longer name'         '~/harbor.bak/x'                                0

  t_class 'plist is always CODE'  'a.plist'   '<string>x</string>'            CODE
  t_class 'json is always CODE'   'a.json'    '"/Users/x"'                    CODE
  t_class 'markdown is DOC'       'SKILL.md'  'read ~/harbor/ACCESS'          DOC
  t_class 'shell comment is DOC'  'a.sh'      '  # see $HOME/harbor/bin/x'    DOC
  t_class 'shell code is CODE'    'a.sh'      'REPO="$HOME/harbor"'           CODE
  t_class 'a shebang is CODE'     'dbt'       "#!$HOME_DIR/.venv/bin/python"  CODE
  t_class 'a JS comment is DOC'   'a.mjs'     '// see ~/harbor/docs/reference/checks.md'     DOC
  t_class 'JS code is CODE'       'a.mjs'     'const p = "~/zorbcorp"'        CODE
  t_class 'a SQL comment is DOC'  'a.sql'     '--   ~/quux-core/models'        DOC
  t_class 'a shell -- line is CODE' 'a.sh'    '  --dir ~/quux-core/models'     CODE
  t_class 'a markdown Path root is CODE' 'CLAUDE.md' '> **Path root:** `~/harbor` — x' CODE
  t_class 'a Path root in a shell comment is DOC' 'a.sh' '#   > **Path root:** `~/harbor`' DOC

  # Exemptions are per line, against a scratch table: the exact line is exempt; another line in the same file, and the same text in another file, are not.
  __xt="${TMPDIR:-/tmp}/port-paths-xt.$$"
  printf 'file\ttext\twhy\nrepo/a.sh\tcd ~/zorbcorp # pinned\tbecause\nrepo/LOG.md\t*\ta record\nharbor/skills/demo/SKILL.md\tsee ~/zorbcorp/MAP.md\ta record\nharbor/policy/constitution.md\tthe tree then at ~/zorbcorp\ta record\n' > "$__xt"
  t_ex() { # description, file (relative to $PORT, or absolute), text, expect(1|0)
    case "$2" in /*) __xf="$2" ;; *) __xf="$PORT/$2" ;; esac
    if EXEMPT_FILE="$__xt" is_exempt "$__xf" "$3" "${5:-CODE}"; then __g=1; else __g=0; fi
    if [ "$__g" = "$4" ]; then log_ok "exempt: $1"; else log_fail "exempt: $1"; log_fix "sh $0 --selftest, then read the case in bin/lint-port-paths.sh"; fi
  }
  t_ex 'the listed line is exempt'           'repo/a.sh' 'x; cd ~/zorbcorp # pinned' 1
  t_ex 'another line in that file is not'    'repo/a.sh' 'cd ~/harbor'             0
  t_ex 'the same text elsewhere is not'      'repo/b.sh' 'cd ~/zorbcorp # pinned'   0
  t_ex 'a whole-file record exempts DOC'  'repo/LOG.md' 'see ~/harbor/x'  1 DOC
  t_ex 'a whole-file record never exempts CODE' 'repo/LOG.md' 'cd ~/harbor' 0 CODE
  # The installed copy of a skill is judged by its source row; a different line is not; a config-dir file outside skills/ and bin/ is a copy of nothing.
  t_ex 'an installed copy takes its source row'  "$CFG/skills/demo/SKILL.md" 'see ~/zorbcorp/MAP.md now' 1 DOC
  t_ex 'another line in the copy is not'         "$CFG/skills/demo/SKILL.md" 'see ~/blorp/X'           0 DOC
  t_ex 'a config file outside skills/ is not'    "$CFG/settings.json"        'see ~/zorbcorp/MAP.md'     0 CODE
  # The installed constitution takes policy/constitution.md's rows; a MEMORY/ document is a copy of nothing.
  t_ex 'the installed constitution takes its source row' "$CFG/CLAUDE.md" 'measured on the tree then at ~/zorbcorp: x' 1 DOC
  t_ex 'a MEMORY document takes no harbor row'   "$CFG/MEMORY/IDENTITY.md"   'the tree then at ~/zorbcorp'  0 DOC
  rm -f "$__xt"

  # The exclusion, asserted through harbor_grep (the function scan 1 runs, not a copy of its pathspec). It SKIPS loudly where harbor is absent; where present it is the only thing between a wrong pathspec and 61 phantom rows.
  if [ -e "$PORT/harbor/.git" ]; then
    __ev="$(harbor_grep "$PORT/harbor" -lE | grep -c '/EVALS/' || true)"
    if [ "$__ev" = 0 ]; then log_ok "excl: no eval record survived the exclusion"; else
      log_fail "excl: $__ev eval record(s) survived the exclusion"
      log_fix "fix the pathspec in harbor_grep (bin/lint-port-paths.sh)"
    fi
  else
    log_skip "excl: no harbor clone at $PORT/harbor, so the exclusion was NOT checked"
  fi

  log_end
  exit $?
fi

# --verify. Run the inventory once, count it, give back only the verdict. A scan that died is exit 3 (D-29 unchecked), never a count: through a pipe its status was lost and a half-finished scan would have counted its rows and printed a green.
if [ "$MODE" = verify ]; then
  log_head "verify"
  if ! __inv="$(sh "$0")"; then
    log_fail "the inventory scan failed: nothing was judged, and this is not a green"
    log_fix "sh $0 >/dev/null   # runs the scan alone and shows where it dies"
    log_end || :; exit 3
  fi
  __all="$(printf '%s\n' "$__inv" | tail -n +2)"
  __code="$(printf '%s\n' "$__all" | awk -F'\t' '$2=="CODE"' | grep -c . || true)"
  __doc="$(printf '%s\n' "$__all" | awk -F'\t' '$2=="DOC"' | grep -c . || true)"
  __ex="$(printf '%s\n' "$__all" | awk -F'\t' '$2=="EXEMPT"' | grep -c . || true)"
  # A STALE exemption (its line is gone) is reported, never silently kept. A whole-file `*` row is stale when its file names no pre-move path at all (searching for a literal `*` is satisfied forever by one bold word).
  __stale=''
  if [ -f "$EXEMPT_FILE" ] || [ -n "$EXEMPT_PRIV" ]; then
    __stale="$(exempt_rows | grep -v '^#' | awk -F'\t' 'NF>=3 && $1!="file"' |
      while IFS="$(printf '\t')" read -r __ef __et __ew; do
        __er="$__et"
        # `(pattern)`: this loop runs inside $( ), where bash 3.2 reads a bare
        # `pattern)` as the end of the substitution.
        case "$__et" in (*@HOME@*) __er="$(printf '%s' "$__et" | sed "s|@HOME@|$HOME_DIR|g")" ;; esac
        # The file of the row AND the installed copy the scan maps onto it (FINISH_AWK): a retired but still installed skill kept its row live and was reported stale.
        # No apostrophe in a comment here: inside $( ) bash 3.2 reads one as an open quote.
        set -- "$PORT/$__ef"
        case "$__ef" in
          (harbor/skills/*|harbor/bin/*) [ -z "$CFG" ] || set -- "$@" "$CFG/${__ef#harbor/}" ;;
          (harbor/policy/constitution.md) [ -z "$CFG" ] || set -- "$@" "$CFG/CLAUDE.md" ;;
        esac
        __live=0
        for __eg in "$@"; do
          if [ "$__et" = '*' ]; then grep -qE "$PAT" "$__eg" 2>/dev/null && __live=1
          else grep -qF -- "$__er" "$__eg" 2>/dev/null && __live=1; fi
        done
        [ "$__live" = 0 ] || continue
        echo "$__ef$(printf '\t')$__et"
      done)"
  fi
  __stale_n=0
  if [ -n "$__stale" ]; then
    __stale_n="$(printf '%s\n' "$__stale" | grep -c .)"
    while IFS="$(printf '\t')" read -r __sf __st; do
      log_warn "STALE exemption: $__sf — \"$__st\" no longer appears"
      log_fix "delete that row from the table it lives in (contracts/port-paths-exempt.tsv, or the private layer's)"
    done <<STALE
$__stale
STALE
  fi
  log_note "CODE=$__code DOC=$__doc EXEMPT=$__ex (stale: $__stale_n)"
  if [ "$__code" -gt 0 ]; then
    log_fail "$__code executable or config literal(s) still name a pre-move path"
    log_fix "sh $0 | awk -F'\t' '\$2 == \"CODE\"'"
  else
    log_ok "no CODE literal names a pre-move path ($__doc DOC mention(s) remain, not blocking)"
  fi
  log_end
  exit $?
fi

printf 'surface\tclass\tfile\tline\tliteral\n'

# 0 · nothing derived is a CODE row, never an empty scan: with no repo under $PORT every scan would look at nothing and read green.
if [ -z "$ALT" ]; then
  printf 'port-root\tCODE\t%s\t-\tNO REPO under PORT_ROOT — nothing was scanned\n' "$PORT"
  exit 0
fi

# Every scan writes RAW rows into one file and finish() classifies them in one pass. A file, not a pipe: a brace group redirected to a file runs in this shell, so a failed scan stops the script and --verify turns it into exit 3.
__raw="$(mktemp "${TMPDIR:-/tmp}/port-paths.XXXXXX")"
trap 'rm -f "$__raw"' EXIT
trap 'rm -f "$__raw"; exit 130' INT TERM
{
# 1 · harbor tracked files. git grep reads the index, sidestepping the ugrep gitignore problem. A missing checkout is a CODE row, never a silent skip. `-e`, not `-d`: a worktree .git is a file.
if [ -e "$PORT/harbor/.git" ]; then
  harbor_grep "$PORT/harbor" -nE |
    while IFS=: read -r __f __ln __txt; do
      raw harbor-tracked "$PORT/harbor/$__f" "$__ln" "$__txt"
    done
else
  printf 'CODE\tharbor-tracked\t%s/harbor\t-\tNO CHECKOUT — nothing was scanned\n' "$PORT"
fi

# 1b · every OTHER moved repo tracked files (74 CODE literals across five workload repos when first scanned). A target git cannot read is a CODE row, like a missing harbor checkout.
for __r in $TARGETS; do
  [ "$__r" = harbor ] && continue
  __d="$PORT/$__r"
  if ! git -C "$__d" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'CODE\trepo:%s\t%s\t-\tNO READABLE CHECKOUT — nothing was scanned\n' "$__r" "$__d"
    continue
  fi
  # Dated audits (docs/reports/, AUDITS/ before its October 2026 rename) are excluded for the EVALS reason.
  # shellcheck disable=SC2086
  git -C "$__d" grep -nE "$PAT" -- . ':!*/EVALS/*' ':!docs/reports/*' $INSTRUMENT_SPEC 2>/dev/null |
    while IFS=: read -r __f __ln __txt; do
      raw "repo:$__r" "$__d/$__f" "$__ln" "$__txt"
    done
done

# 2 · the installed runtime and the skills — in the config dir Claude Code is
#     actually reading, which is $CLAUDE_CONFIG_DIR when it is set (lint D1).
scan claude-bin    $(find "$CFG/bin" -maxdepth 1 -type f 2>/dev/null)
scan claude-skills $(find "$CFG/skills" -maxdepth 3 \( -name '*.md' -o -name '*.sh' \) \
                       -not -path '*/EVALS/*' 2>/dev/null)

# 2b · the installed constitution and top-level MEMORY documents (harbor#653): CLAUDE.md is what every session loads, and a stale `**Path root:**` kills every `./` citation. MEMORY/ is read at depth 1 only; WORK/ and USAGE/ are session logs quoting paths as they were.
scan claude-instructions "$CFG/CLAUDE.md"
scan claude-memory $(find "$CFG/MEMORY" -maxdepth 1 -type f -name '*.md' 2>/dev/null)

# 3 · settings and Claude Code per-cwd state. `.claude.json` sits beside the config dir at $HOME/.claude.json when CLAUDE_CONFIG_DIR is unset, so it is named through $HOME_DIR, not $CFG.
scan settings "$CFG/settings.json" "$CFG/settings.local.json"
scan claude-json "$HOME_DIR/.claude.json"

# 4 · fleet discovery. Gitignored, so no version history, and register() drops fields and comments (po#305): edit by hand.
scan fleet "$FLEETF"
# The roots line names $HOME itself, which PAT cannot see (no repo name); scanning $HOME at depth 1 after phase C finds zero projects without error, so it is checked by value.
grep -nE "^[[:space:]]*-[[:space:]]*${HOME_DIR}/?[[:space:]]*\$" "$FLEETF" 2>/dev/null |
  while IFS=: read -r __ln __txt; do
    printf 'CODE\tfleet\t%s\t%s\t%s (roots: must be %s)\n' "$FLEETF" "$__ln" "$(printf '%s' "$__txt" | sed 's/^[[:space:]]*//')" "$PORT"
  done

# 5 · launchd. These cannot use $HOME, so every path here is unavoidably absolute.
scan launchd $(find "$HOME_DIR/Library/LaunchAgents" -maxdepth 1 -name '*.plist' 2>/dev/null)

# 6 · symlinks in ~/.local/bin — the target, not the file content.
for __l in $(find "$HOME_DIR/.local/bin" -maxdepth 1 -type l 2>/dev/null); do
  __t="$(readlink "$__l" 2>/dev/null || true)"
  case "$__t" in
    "$HOME_DIR"/*)
      printf '%s' "$__t" | grep -qE "^${HOME_DIR}/($ALT)(/|\$)" &&
        printf 'CODE\tlocal-bin-symlink\t%s\t-\t-> %s\n' "$__l" "$__t"
      ;;
  esac
done

# 7 · git worktree admin files (the worktree .git and the owner .git/worktrees/<n>/gitdir). A row only when a pointer NAMES a pre-move path; `git worktree repair` leaves a pointer alone while it still resolves, through a bridge too, and that is the case this finds. Owners are every derived target, not a hand list.
# `|| continue`, never `[ -f … ] && scan`: under `set -e` a `while` whose last body command is a false test takes the script down (the first run died on a repo with no worktrees).
# `-e`, not `-d`: a target that is itself a worktree has a `.git` FILE.
for __o in $TARGETS; do
  __d="$PORT/$__o"
  [ -e "$__d/.git" ] || continue
  git -C "$__d" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{print substr($0, 10)}' | while IFS= read -r __w; do
      [ -f "$__w/.git" ] || continue
      scan git-worktree "$__w/.git"
    done
  for __g in "$__d"/.git/worktrees/*/gitdir; do
    [ -f "$__g" ] || continue
    scan git-worktree "$__g"
  done
done

# 8 · virtualenvs inside a moved repo: not relocatable, their activate scripts, shebangs and .pth files carry the absolute build path. The fix is a rebuild (`uv sync`), not a rewrite of this list.
for __cfg in $(find "$PORT" "$HOME_DIR/.local/lib" -maxdepth 5 -name pyvenv.cfg \
                 -not -path '*/node_modules/*' 2>/dev/null); do
  __v="$(dirname "$__cfg")"
  scan venv $(find "$__v/bin" -maxdepth 1 -type f 2>/dev/null) \
            $(find "$__v/lib" -maxdepth 4 \( -name '*.pth' -o -name direct_url.json \) 2>/dev/null)
done
} > "$__raw"

finish rows "$EXEMPT_FILE" < "$__raw"
exit 0
