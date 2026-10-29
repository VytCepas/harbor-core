#!/usr/bin/env sh
# lint-port-paths.sh (harbor#629, harbor#619) — literals naming a repo at its PRE-MOVE address.
# That is ~/<repo>, $HOME/<repo> or <home>/<repo>, where the repo now lives
# under ${PORT_ROOT:-$HOME/port}. Registered in docs/reference/checks.md as `port-paths`.
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
# WHY ONE SCRIPT FOR BOTH. harbor#619's last acceptance criterion is "No script
# or config names a pre-move repo path". A checklist cannot close that; a
# re-runnable scan can, and the same scan that enumerates the work before the
# move proves the absence after it. Run it now, fix what it lists, run it again.
# It graduated here from ~/Deliverables/2026-09-22-r2-workspace-root/ (harbor#629)
# so that it cannot regress unnoticed; its suite is tests/lint/port-paths/port-paths.test.sh.
#
# DELIBERATELY ONE FILE (lint G1, docs/explanation/modularity.md): the surface list and
# the matcher are one contract — splitting them puts the question and the answer
# in two files that drift.
#
# THE MATCH. A repo path is (~|$HOME|<home>)/<repo> followed by a separator or
# end. The prefix alternation matters: SKILL.md files write ~/<repo>, shell
# defaults write $HOME/<repo>, and plists must write the absolute form because
# launchd expands nothing. Matching the bare repo NAME would be useless —
# "harbor" appears in every com.harbor.* launchd label and every .helm-* filename.
#
# GREP IS UGREP HERE, and the config dir IS A GIT REPO, so a plain `grep -r` over
# it SKIPS every gitignored file and reports a false absence. Every scan below is
# therefore a `find` that builds an explicit file list, piped to grep one file at
# a time. Never replace this with `grep -r`.
#
# NOT COVERED, on purpose: eval fixtures and historical run logs
# (harbor evals/, skills/*/EVALS/) carry literal paths that are a record of
# a past run, not live configuration. Rewriting them would falsify the record.
#
# THE EXCLUSION PATHSPEC IS LOAD-BEARING AND WAS WRONG. `:!skills/*/EVALS`
# READS correctly and excludes NOTHING: a git pathspec carrying a wildcard is
# fnmatched against the WHOLE path, and that pattern has no trailing `/*`, so
# `skills/topology/EVALS/RUN-2026-08-30/returns.jsonl` never matches it. The
# form that fires is `:!*/EVALS/*`. Measured 2026-09-23: the broken spelling
# inflated CODE by 61 rows, every one of them a historical eval record that
# must NOT be rewritten — a gate demanding 61 falsifications of a past run is a
# gate that gets switched off (CONSTITUTION No.2.11). --selftest now asserts the
# exclusion fires, because the failure is invisible in the output: the rows look
# exactly like real findings.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the text is the first header
# paragraph, read out of THIS file, so it cannot drift from what the script is.
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
# EVERY SCAN READS THE PHYSICAL HOME, $PORT, never $HOME_DIR/<repo>. Until
# 2026-09-23 this read the repos at their old addresses, which after phase A are
# bridges — and phase C deletes the bridges. Every scan here is guarded by
# `[ -d … ] || continue`, so on the day the gate matters most it would have
# looked at nothing and reported CODE=0. Measured by reading, before phase C ran.
PORT="${PORT_ROOT:-$HOME_DIR/port}"
FLEETF="$(sh "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/scope-roots.sh" --get HARBOR_FLEET_FILE)" || exit 3   # harbor#966

# THE REPOS ARE DERIVED FROM $PORT, NEVER LISTED. The Deliverables copy carried a
# hand-written list of thirteen names, and a hand list of what lives in a
# directory went stale within the hour during the move: repos arrive, worktrees
# come and go, and a name missing from the list is a repo whose old address is
# never matched — a silent green. So the list is read off the directory:
#
#   a directory directly under $PORT with a `.git` is a repo          (<repo>)
#   one without, holding repos one level down, is a container        (<root>)
#   a sibling worktree, `<repo>-wt-<name>`, is neither — it is a second view of
#   a repo already counted, so scanning it would count every row twice, and its
#   name is not an address anything was ever moved from.
#   SO IS A WORKTREE WITH ANY OTHER NAME (harbor#629). Measured 2026-09-24:
#   another session created ~/port/<repo>-<topic> with `git worktree add`, the
#   name matched no `-wt-` rule, and it was scanned as a repo of its own — away
#   from the measurement repo's exemption rows — turning --verify RED with 8 CODE and 41 DOC
#   rows that repo itself had already settled. The name was a convention; the
#   STRUCTURE is the fact: a `.git` FILE whose common directory lies under $PORT
#   is a view of a repo counted here. One whose repository lives elsewhere is
#   still scanned — that is how a branch is measured before it merges (case 17).
#
# TARGETS are what 1b scans (relative to $PORT: <repo>, <root>/<repo>, …); NAMES are
# the first path components — the names a pre-move literal carries (<root>, not
# <root>/<repo>). Names are dropped into an ERE unescaped: repo names are
# [A-Za-z0-9_.-], where the only metacharacter, `.`, over-matches — the safe side.
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

# One alternation, built once: (~|$HOME|<home>)/(repo)(separator|end). The tail
# group is what refuses a LONGER name — ~/harborage, ~/zorbcorpal — and what
# refuses a sibling worktree's address (~/zorbcorp-wt-x), because `-` is not a
# separator. --selftest proves both.
#
# A FULL STOP ENDING A SENTENCE IS A SEPARATOR; one starting a suffix is not.
# `.` sits in the name class so that ~/harbor.md and ~/harbor.bak stay unmatched,
# and until 2026-09-23 that also hid every path that ends a sentence — "moved
# out of ~/harbor." Measured that day against the same exemption table: nine
# rows this box had never shown, five in harbor's tracked files and one CODE.
# So `.` counts when whitespace, end of line, or a closing quote, backtick or
# parenthesis follows it.
alt_of() { __a=''; for __r in $1; do __a="${__a:+$__a|}$__r"; done; printf '%s' "$__a"; }
pat_of() { printf '(~|\\$HOME|%s)/(%s)(/|[^A-Za-z0-9_.-]|$|\\.([[:space:]]|$|["'"'"'`)]))' "$HOME_DIR" "$(alt_of "$1")"; }
ALT="$(alt_of "$NAMES")"
PAT="$(pat_of "$NAMES")"

# CODE or DOC. A gate that demands every prose mention of a repo be rewritten
# lists every README line, and a guard that blocks ordinary work gets switched off
# (CONSTITUTION No.2.11) — so only CODE gates. DOC is a real follow-up list
# (harbor#629) and is reported separately, never as a blocker.
#
# The shell-comment rule is the one from memory `guard-satisfied-by-its-own-comment`
# read backwards: a path inside a `#` comment cannot break anything at runtime,
# exactly as a rule inside a comment cannot enforce anything. Four refinements,
# each from a run that got it wrong:
#   A SHEBANG IS CODE. `#!/Users/…/.venv/bin/python` begins with '#', and the
#   comment rule would file the one line that decides which interpreter runs as
#   documentation. Found by reading, 2026-09-23, before the venv scan ran.
#   THE OTHER REPOS COMMENT IN OTHER LANGUAGES. Scanning them (1b) put 3 JavaScript
#   `//` lines and 3 `--` SQL comments into CODE on the first run — every
#   one prose. Scoped by extension, because `--` opening a line of a SHELL script
#   is an argument continuation, and that is code.
#   A PATH ROOT IN MARKDOWN IS CODE (harbor#653). A `**Path root:**` line is
#   parsed, not read: drift-reference-check.sh REF-5 takes its first backticked token
#   as the root every `./` citation in the document resolves against. Filed as
#   DOC, the installed constitution's `~/harbor` root sat under a green gate on
#   2026-09-23 while REF-5 reported all 11 of its citations resolving nowhere.
#   Scoped to .md: the same text in a shell comment documents the format.
#
# EXEMPT. A row the operator decided to keep, listed with its reason in
# contracts/port-paths-exempt.tsv. Matched per LINE (file relative to $PORT, plus
# fixed text on the line), so a new literal in an exempted file is still counted.
# ONE widening, for DOC only: text `*` exempts a whole file, because a dated
# record (an archive, an audit, a run log) is history in every line, and listing
# its lines one by one would be a copy of the file. A `*` row never exempts
# CODE — a file of records that grows an executed path must show.
#   `@HOME@` in a row's text stands for this box's home directory, rendered when
# the table is read. The table is TRACKED, and lint HP1 refuses a tracked file
# that names its author's home, which the rows quoting a plist or a provenance
# stamp otherwise have to (harbor#602); the same placeholder floor-equiv renders.
#
# CLASSIFY, EXEMPT AND FORMAT ARE ONE awk PROGRAM, RUN ONCE OVER EVERY ROW. The
# Deliverables copy did all three as shell pipelines per row — about twenty
# processes a row, and is_exempt() re-read the whole table for every one — so
# the cost was rows x table. Measured 2026-09-23 on this box: its --verify, which
# also ran the whole scan twice, took 126 s; this one scans once, in about 12 s,
# and on one table the two inventories were byte-identical row for row (before
# the full-stop change to the matcher above). Here the table is read once and a
# row costs no process at all. The shell functions classify()
# and is_exempt() below are one-row wrappers over THIS program, so --selftest
# exercises the code the scan runs rather than a copy of it.
#
# LC_ALL=C, because macOS awk (20200816) is byte-based in substr() and dies on a
# regex over a lone UTF-8 continuation byte. trunc() counts CHARACTERS itself —
# a byte in \200-\277 continues one — which is what `cut -c1-120` did, so the
# literal column is unchanged and never ends in half a character.
EXEMPT_FILE="${PORT_PATHS_EXEMPT:-$ROOT/contracts/port-paths-exempt.tsv}"
# The rows that name a client's directory are the private layer's own (harbor#1149), a table in the same
# columns beside the core one. PORT_PATHS_EXEMPT names the only table read, so a suite's fixture stays
# hermetic. An absent or unreadable overlay, or no layer, is the core table alone: those rows then count again.
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
  # AN INSTALLED COPY IS JUDGED BY THE ROWS OF ITS SOURCE (harbor#629). $CFG/skills
  # and $CFG/bin are what skills-install and runtime-install ship out of harbor
  # skills/ and bin/, so a line the operator kept in the source is the same line,
  # kept for the same reason, in the copy. Before this, the table matched only
  # paths under $PORT, and on 2026-09-23 all 46 DOC rows reported for the config
  # dir were lines already exempted in harbor — a DOC count 85% phantom, which is
  # how a count stops being read. Those two subtrees map, and so does CLAUDE.md,
  # which constitution-install ships out of harbor policy/constitution.md (harbor#653):
  # settings, .claude.json and MEMORY/ are not copies of anything. NO
  # APOSTROPHES in this program: it is one single-quoted shell string.
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

# harbor's tracked files, through ONE pathspec — scan 1 and --selftest both call
# this, because a selftest that asserted its own COPY of the pathspec would stay
# green while the scan's spelling broke, which is the exact defect above.
#   registries/coverage-incidents.tsv is excluded for the EVALS reason: it is a dated sweep
#   (its own header says "Swept 2026-09-22"), and its evidence column quotes code
#   and handoff notes as they read that day. Rewriting a quote to make a gate
#   green falsifies the record the gate exists to protect.
#   THIS INSTRUMENT'S OWN FILES are excluded for the same reason: the script's
#   selftest vectors, its suite's fixtures and the exemption table ARE pre-move
#   literals, quoted as data; scanned, they turn the gate red on its own test
#   data (suite case 8). The cost, named: a real pre-move default written here would
#   go unseen here — its defaults derive from PORT_ROOT and HOME instead.
#   ONE LIST, applied to every repo scan (1b too): harbor-core mirrors these files and the private layer keeps its own
#   exemption table, and scanned there they were 157 of 159 CODE rows on 2026-10-27, the gate red on its own data. The
#   suite split into tests/install/port-paths/ is listed beside the file it came from.
INSTRUMENT_SPEC=':!bin/lint-port-paths.sh :!tests/lint/port-paths/port-paths.test.sh :!tests/install/port-paths/* :!contracts/port-paths-exempt.tsv :!port-paths-exempt.tsv'
harbor_grep() { # <repo> <git-grep-flags>
  # shellcheck disable=SC2086  # INSTRUMENT_SPEC is pathspecs with no spaces, split on purpose
  git -C "$1" grep "$2" "$PAT" -- . ':!evals' ':!*/EVALS/*' ':!registries/coverage-incidents.tsv' $INSTRUMENT_SPEC 2>/dev/null
}

# --selftest. The two load-bearing parts are the regex and classify(); everything
# else is a file list. Each case below was watched FAIL on a deliberate mutant
# (CONSTITUTION No.2.10): dropping the trailing separator group from PAT makes
# "harborage" and "com.harbor.judge" match, and removing the '#' arm of
# classify() turns the commented case CODE. The matcher is built from FIXED
# names here, not from $PORT, so the cases test the construction and do not
# depend on which repos this box happens to hold.
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
  t_match 'shell default with $HOME'     'REPO="${HARBOR_REPO:=$HOME/harbor}"'          1
  t_match 'tilde form in a skill'        'read ~/zorbcorp/CLIENTS/ACME/TOPOLOGY.md'       1
  t_match 'absolute form in a plist'     '<string>'"$HOME_DIR"'/zorbcorp</string>'        1
  t_match 'launchd LABEL is not a path'  '<string>com.harbor.judge</string>'             0
  t_match 'helm ledger name'             'CFG/.helm-harbor-state'                        0
  t_match 'repo name with no prefix'     'cd harbor && git status'                       0
  # These three are the ONLY cases that exercise the trailing separator group.
  # The three above do not: they have no ~/ or $HOME/ prefix, so they fail on the
  # prefix alternation whatever the tail does. Measured — a mutant that deleted
  # the separator group passed all 12 tests until these were added.
  t_match 'prefixed but a LONGER name'   "$HOME_DIR/harborage/x"                         0
  t_match 'prefixed, longer, tilde form' '~/zorbcorpal/CLIENTS'                           0
  t_match 'prefixed exact name, at end'  "$HOME_DIR/harbor"                              1
  t_match 'a sibling worktree address'   '~/zorbcorp-wt-docs/x'                           0
  # The full stop. The first two were MISSED before 2026-09-23; the last two
  # are why `.` is still a name character everywhere else.
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

  # EXEMPTIONS are per line. Against a scratch table, so the live one's rows
  # neither help nor hurt: the exact line is exempt; another line in the SAME
  # file, and the same text in ANOTHER file, are not.
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
  # The installed copy of harbor/skills/demo/SKILL.md is judged by that row; a
  # different line in the copy is not; and a config-dir file outside skills/ and
  # bin/ is a copy of nothing, so no harbor row can reach it.
  t_ex 'an installed copy takes its source row'  "$CFG/skills/demo/SKILL.md" 'see ~/zorbcorp/MAP.md now' 1 DOC
  t_ex 'another line in the copy is not'         "$CFG/skills/demo/SKILL.md" 'see ~/blorp/X'           0 DOC
  t_ex 'a config file outside skills/ is not'    "$CFG/settings.json"        'see ~/zorbcorp/MAP.md'     0 CODE
  # The installed constitution is policy/constitution.md shipped by constitution-install,
  # so it takes that file's rows; a MEMORY/ document is a copy of nothing.
  t_ex 'the installed constitution takes its source row' "$CFG/CLAUDE.md" 'measured on the tree then at ~/zorbcorp: x' 1 DOC
  t_ex 'a MEMORY document takes no harbor row'   "$CFG/MEMORY/IDENTITY.md"   'the tree then at ~/zorbcorp'  0 DOC
  rm -f "$__xt"

  # The EXCLUSION, asserted through harbor_grep — the function scan 1 runs, never
  # a copy of its pathspec. Not a pure-function test like the two above, so it
  # SKIPS loudly rather than failing where harbor is absent — but where harbor IS
  # present this is the only thing standing between a wrong pathspec and 61
  # phantom rows, and the wrong pathspec reads correctly.
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

# --verify. The inventory is the input to the count, not the deliverable: run it
# once, count it, and give back only the verdict. Printing every row and then a
# verdict buries the verdict, which is the whole point of a gate. (The
# Deliverables copy ran the whole scan twice here, once into /dev/null.)
#
# A SCAN THAT DIED IS EXIT 3 (D-29 UNCHECKED), NEVER A COUNT. Through a pipe the inventory's exit
# status was lost, so a scan that aborted half-way under `set -e` would have
# counted the rows it got to — possibly none — and printed a green.
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
  # A STALE exemption — its line is gone — is reported, never silently kept: a
  # rule that can no longer match anything is how a list of reasons rots.
  # A WHOLE-FILE `*` row is stale when its file names no pre-move path at all.
  # The Deliverables copy searched such a file for a literal `*`, which any
  # markdown file with one bold word satisfies for ever.
  __stale=''
  if [ -f "$EXEMPT_FILE" ] || [ -n "$EXEMPT_PRIV" ]; then
    __stale="$(exempt_rows | grep -v '^#' | awk -F'\t' 'NF>=3 && $1!="file"' |
      while IFS="$(printf '\t')" read -r __ef __et __ew; do
        __er="$__et"
        # `(pattern)`: this loop runs inside $( ), where bash 3.2 reads a bare
        # `pattern)` as the end of the substitution.
        case "$__et" in (*@HOME@*) __er="$(printf '%s' "$__et" | sed "s|@HOME@|$HOME_DIR|g")" ;; esac
        # The file of the row AND the installed copy the scan maps onto it (FINISH_AWK: skills/, bin/, CLAUDE.md):
        # a skill retired from the tree but still installed kept its row live, and was reported stale (2026-10-27).
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

# 0 · NOTHING DERIVED IS A CODE ROW, never an empty scan. With no repo under
#     $PORT there is no name to match, so every scan below would look at nothing
#     and the gate would read green on the day PORT_ROOT points at the wrong
#     directory.
if [ -z "$ALT" ]; then
  printf 'port-root\tCODE\t%s\t-\tNO REPO under PORT_ROOT — nothing was scanned\n' "$PORT"
  exit 0
fi

# Every scan writes RAW rows into one file, and finish() classifies them in one
# pass at the end. A file and not a pipe: a brace group redirected to a file
# runs in THIS shell, so a scan that fails under `set -e` stops the script with a
# non-zero exit that --verify turns into exit 3 — through a pipe, awk's 0 would
# have been the only status anyone saw.
__raw="$(mktemp "${TMPDIR:-/tmp}/port-paths.XXXXXX")"
trap 'rm -f "$__raw"' EXIT
trap 'rm -f "$__raw"; exit 130' INT TERM
{
# 1 · harbor's tracked files. git grep sidesteps the ugrep gitignore problem
#     entirely: it reads the index, not the working tree's ignore rules.
#     A MISSING CHECKOUT IS A CODE ROW, never a silent skip: this is the scan
#     that covers the most literals, and "looked at nothing" must not read as
#     "found nothing". `-e`, not `-d`: a WORKTREE's `.git` is a file, and the
#     Deliverables copy's `-d` printed NO CHECKOUT for a PORT_ROOT whose harbor
#     was a worktree, so a branch could not be measured before it merged.
if [ -e "$PORT/harbor/.git" ]; then
  harbor_grep "$PORT/harbor" -nE |
    while IFS=: read -r __f __ln __txt; do
      raw harbor-tracked "$PORT/harbor/$__f" "$__ln" "$__txt"
    done
else
  printf 'CODE\tharbor-tracked\t%s/harbor\t-\tNO CHECKOUT — nothing was scanned\n' "$PORT"
fi

# 1b · every OTHER moved repo's tracked files. Not scanned at all until
#      2026-09-23, when a sweep found 74 CODE literals across five workload
#      repos — justfiles, scripts and configs that
#      name ~/<repo>/bin/gcx or ~/<repo> and work today only through a bridge.
#      A target git cannot read — a worktree whose admin directory is gone — is
#      a CODE row for the same reason a missing harbor checkout is.
for __r in $TARGETS; do
  [ "$__r" = harbor ] && continue
  __d="$PORT/$__r"
  if ! git -C "$__d" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'CODE\trepo:%s\t%s\t-\tNO READABLE CHECKOUT — nothing was scanned\n' "$__r" "$__d"
    continue
  fi
  #    estate's AUDITS/<date>-data/ is excluded for the EVALS reason: a dated
  #    audit's findings.json quotes the paths it measured on that day.
  # shellcheck disable=SC2086
  git -C "$__d" grep -nE "$PAT" -- . ':!*/EVALS/*' ':!AUDITS/*' $INSTRUMENT_SPEC 2>/dev/null |
    while IFS=: read -r __f __ln __txt; do
      raw "repo:$__r" "$__d/$__f" "$__ln" "$__txt"
    done
done

# 2 · the installed runtime and the skills — in the config dir Claude Code is
#     actually reading, which is $CLAUDE_CONFIG_DIR when it is set (lint D1).
scan claude-bin    $(find "$CFG/bin" -maxdepth 1 -type f 2>/dev/null)
scan claude-skills $(find "$CFG/skills" -maxdepth 3 \( -name '*.md' -o -name '*.sh' \) \
                       -not -path '*/EVALS/*' 2>/dev/null)

# 2b · the installed constitution and the top-level MEMORY documents (harbor#653).
#      CLAUDE.md is what every session loads, and a stale `**Path root:**` in it
#      turns every `./` citation into a dead one. The green of 2026-09-23 read
#      bin/ and skills/ and never opened it. MEMORY/ is read at depth 1 only: its
#      WORK/ and USAGE/ subtrees are session logs that quote paths as they were
#      (the EVALS reason). Its other subtrees were not examined when this landed,
#      so widen this when one is shown to be read as live instruction.
scan claude-instructions "$CFG/CLAUDE.md"
scan claude-memory $(find "$CFG/MEMORY" -maxdepth 1 -type f -name '*.md' 2>/dev/null)

# 3 · settings and Claude Code's own per-cwd state. `.claude.json` is NOT inside
#     the config dir: with CLAUDE_CONFIG_DIR unset — every live session on this
#     box — Claude Code keeps it beside the dir, at $HOME/.claude.json, and that
#     is the file remove-bridges.sh carries over in phase C. It is therefore
#     named through $HOME_DIR and not through $CFG; D1's concern, a config dir
#     hardcoded instead of resolved, does not apply to a file outside it.
scan settings "$CFG/settings.json" "$CFG/settings.local.json"
scan claude-json "$HOME_DIR/.claude.json"

# 4 · fleet discovery. Gitignored by design (.gitignore:68), so it has NO version
#     history — and po#305 measured that register() silently drops two fields and
#     every comment. Edit it by hand, never by tool.
scan fleet "$FLEETF"
#     The root line names $HOME itself, which PAT cannot see — it carries no
#     repo name. Scanning $HOME at depth 1 after phase C finds zero projects and
#     raises no error (roots.tsv, HARBOR_FLEET_FILE), so it is checked by value.
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

# 7 · git worktree admin files. Two per worktree, both absolute: the worktree's
#     `.git` file and the owner's `.git/worktrees/<n>/gitdir`. A row only when a
#     pointer NAMES a pre-move path. Until 2026-09-23 this printed one row per
#     worktree whatever the pointers said — a pre-move enumeration, which after
#     the move reported 17 phantom rows for pointers `git worktree repair` had
#     already fixed, and would have kept the gate red forever.
#     `repair` leaves a pointer alone while it still RESOLVES, and through a
#     bridge it does: measured 2026-09-23, ~/.local/lib/<tool>/.git still named
#     the old address after repair and was fixed by hand. That is the case this
#     finds. The owners are every derived target, not a hand list: the
#     Deliverables copy named six, and four more repos had grown worktrees by the
#     time it graduated. A target with no worktrees costs one `git` call.
#     `|| continue`, NEVER `[ -f … ] && scan`: the loop's last body command is
#     its status, a pipeline's last element runs in a subshell, and under
#     `set -e` a `while` that ends on a false test takes the whole script down.
#     The Deliverables copy had the `&&` form and survived only because each of
#     its six owners happened to list a worktree last; derived owners include a
#     repo with none (the main checkout's `.git` is a directory), and the first
#     run died there.
#     `-e`, not `-d`: a target that is itself a worktree (PORT_ROOT pointed at a
#     branch under review) has a `.git` FILE, and `git worktree list` answers
#     from it just the same.
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

# 8 · virtualenvs inside a moved repo. A venv is not relocatable: its activate
#     scripts, console-script shebangs and editable-install .pth files carry the
#     absolute path it was built at. Measured 2026-09-23: five venvs (three workload repos and
#     the two Harbor tools) name the old
#     address in 76 bin/ files, and work today only through a bridge. The fix is
#     a rebuild (`uv sync` against the lock), not a rewrite of this list.
for __cfg in $(find "$PORT" "$HOME_DIR/.local/lib" -maxdepth 5 -name pyvenv.cfg \
                 -not -path '*/node_modules/*' 2>/dev/null); do
  __v="$(dirname "$__cfg")"
  scan venv $(find "$__v/bin" -maxdepth 1 -type f 2>/dev/null) \
            $(find "$__v/lib" -maxdepth 4 \( -name '*.pth' -o -name direct_url.json \) 2>/dev/null)
done
} > "$__raw"

finish rows "$EXEMPT_FILE" < "$__raw"
exit 0
