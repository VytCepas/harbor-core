#!/usr/bin/env sh
# lint-port-paths.sh, the gate that no script or config names a repo at its pre-move address
# (harbor#629, #619, #653). Everything is a fixture, $HOME included, and a scan that could not
# look (no harbor, an unreadable repo, nothing under PORT_ROOT, a dead scan) is never green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/lint-port-paths.sh"
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"  # physical: the scanner compares path strings
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE XDG_CONFIG_HOME PORT_ROOT PORT_PATHS_EXEMPT
export GIT_CONFIG_NOSYSTEM=1
H="$T/home"; C="$T/cfg"; P="$H/port"; X="$T/exempt.tsv"  # C is deliberately NOT $H/.claude
mkdir -p "$H/.claude" "$C" "$P" "$H/Library/LaunchAgents"; export HOME="$H"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }  # <file> <content>
repo() { mkdir -p "$1"; git -C "$1" init -q; }
track() { git -C "$1" add -A; }  # git grep reads the index: untracked is unseen
run_pp() { # <home> <cfg> <port> <exempt> [args] — assignments on `sh`, never on a function
  __h="$1" __c="$2" __p="$3" __x="$4"; shift 4
  HOME="$__h" CLAUDE_CONFIG_DIR="$__c" PORT_ROOT="$__p" PORT_PATHS_EXEMPT="$__x" sh "$TOOL" "$@"
}
HC="$T/home-clean"; CC="$T/cfg-clean"; mkdir -p "$HC" "$CC"
pp() { run_pp "$H" "$C" "$@"; }; ppc() { run_pp "$HC" "$CC" "$@"; }  # ppc: the row under test is the only CODE row
hit() { awk -F'\t' -v s="$2" -v c="$3" -v f="$4" -v l="$5" '$1 == s && $2 == c && $3 == f && $4 == l { h = 1 } END { print h ? "yes" : "no" }' "$1"; }
none() { awk -F'\t' "NR > 1 && ($2) { h = 1 } END { print h ? \"found\" : \"none\" }" "$1"; }  # <inv> <awk-cond>
summary() { printf '%s\n' "$1" | grep -F 'note: CODE='; }

repo "$P/harbor"
put "$P/harbor/bin/tool.sh"   'REPO="$HOME/harbor"'
put "$P/harbor/bin/longer.sh" 'X="$HOME/harborage/x"
cd ~/zorbcorpal/CLIENTS
cd ~/zorbcorp-wt-x/foo
cd ~/notes/x'
put "$P/harbor/skills/x/EVALS/run-1/returns.jsonl" '{"p":"~/harbor/x"}'
put "$P/harbor/evals/r.txt"                   'cd ~/harbor/y'
put "$P/harbor/registries/coverage-incidents.tsv"             "a${TAB}~/harbor/z"
put "$P/harbor/bin/lint-port-paths.sh"                  'cd ~/harbor'
put "$P/harbor/tests/lint/port-paths/port-paths.test.sh"   'cd ~/zorbcorp'
put "$P/harbor/contracts/port-paths-exempt.tsv"    "zorbcorp/x${TAB}~/harbor${TAB}why"
track "$P/harbor"
repo "$P/zorbcorp"
put "$P/zorbcorp/run.sh"   'cd ~/zorbcorp/CLIENTS && ls
# see ~/zorbcorp/README
cd ~/harbor # pinned'
put "$P/zorbcorp/other.sh" 'cd ~/harbor # pinned'
put "$P/zorbcorp/LOG.txt"  '# history: ~/harbor/x
cd ~/harbor/bin'
put "$P/zorbcorp/sentence.sh" 'echo "it moved out of ~/zorbcorp."
cat ~/harbor.md'
put "$P/zorbcorp/home.sh" "cd $H/zorbcorp # pinned"
track "$P/zorbcorp"
mkdir -p "$P/plumb"; repo "$P/plumb/APP"; put "$P/plumb/APP/profiles.yml" 'path: ~/plumb/APP/x'; track "$P/plumb/APP"
repo "$P/plumb/APP-wt-y"; put "$P/plumb/APP-wt-y/a.sh" 'cd ~/plumb/APP'; track "$P/plumb/APP-wt-y"
repo "$P/zorbcorp-wt-x"; put "$P/zorbcorp-wt-x/a.sh" 'cd ~/zorbcorp/x'; track "$P/zorbcorp-wt-x"
put "$P/notes/notes.sh" 'cd ~/zorbcorp'  # a directory holding no repo
put "$C/settings.json"        '{"x": "~/harbor/bin/y"}'
put "$H/.claude/settings.json" '{"x": "~/zorbcorp/decoy"}'  # NOT the config dir here
put "$H/.claude.json"         "{\"$H/zorbcorp\": {}}"
put "$H/Library/LaunchAgents/com.test.x.plist" "<string>$H/zorbcorp/run.sh</string>"
printf 'file\ttext\twhy\nzorbcorp/run.sh\tcd ~/harbor # pinned\tpinned on purpose\nzorbcorp/LOG.txt\t*\ta dated record\nzorbcorp/home.sh\tcd @HOME@/zorbcorp # pinned\tpinned, written as lint HP1 requires\n' > "$X"
INV="$T/inv.tsv"; pp "$P" "$X" > "$INV" 2>"$T/inv.err"; c=$?

t_section "the inventory: header, CODE, DOC, per-line exemptions"
t_eq "the inventory" 0 "$c"
t_eq "its TSV header" "surface${TAB}class${TAB}file${TAB}line${TAB}literal" "$(head -1 "$INV")"
t_eq "a repo's tracked literal is CODE" yes "$(hit "$INV" repo:zorbcorp CODE "$P/zorbcorp/run.sh" 1)"
t_eq "harbor's tracked literal is CODE" yes "$(hit "$INV" harbor-tracked CODE "$P/harbor/bin/tool.sh" 1)"
t_eq "a literal in a # comment is DOC" yes "$(hit "$INV" repo:zorbcorp DOC "$P/zorbcorp/run.sh" 2)"
t_eq "the line the table names is EXEMPT" yes "$(hit "$INV" repo:zorbcorp EXEMPT "$P/zorbcorp/run.sh" 3)"
t_eq "the same text in another file stays CODE" yes "$(hit "$INV" repo:zorbcorp CODE "$P/zorbcorp/other.sh" 1)"
t_eq "an @HOME@ row matches the home-dir line (HP1)" yes "$(hit "$INV" repo:zorbcorp EXEMPT "$P/zorbcorp/home.sh" 1)"
t_eq "a * row exempts a DOC line" yes "$(hit "$INV" repo:zorbcorp EXEMPT "$P/zorbcorp/LOG.txt" 1)"
t_eq "a * row never exempts a CODE line" yes "$(hit "$INV" repo:zorbcorp CODE "$P/zorbcorp/LOG.txt" 2)"

t_section "what is scanned: derived repos, the matcher, excluded records"
t_eq "a repo inside a container (plumb/APP) is scanned" yes "$(hit "$INV" repo:plumb/APP CODE "$P/plumb/APP/profiles.yml" 1)"
t_eq "a <repo>-wt-* sibling is not scanned" none "$(none "$INV" "\$1 ~ /-wt-/ || index(\$3, \"$P/zorbcorp-wt-x/\") == 1 || index(\$3, \"$P/plumb/APP-wt-y/\") == 1")"
t_eq "a directory holding no repo is not scanned" none "$(none "$INV" "index(\$3, \"$P/notes/\") == 1")"
t_eq "longer names do not match" none "$(none "$INV" "\$3 == \"$P/harbor/bin/longer.sh\"")"
t_eq "'~/zorbcorp.' ending a sentence matches" yes "$(hit "$INV" repo:zorbcorp CODE "$P/zorbcorp/sentence.sh" 1)"
t_eq "'~/harbor.md' does not" none "$(none "$INV" "\$3 == \"$P/zorbcorp/sentence.sh\" && \$4 == 2")"
t_eq "EVALS, records and the instrument's own files are excluded" none "$(none "$INV" "index(\$3, \"$P/harbor/\") == 1 && \$3 != \"$P/harbor/bin/tool.sh\"")"
t_eq "settings come from CLAUDE_CONFIG_DIR" yes "$(hit "$INV" settings CODE "$C/settings.json" 1)"
t_eq "not from \$HOME/.claude" none "$(none "$INV" "\$3 == \"$H/.claude/settings.json\"")"
t_eq "\$HOME/.claude.json is scanned" yes "$(hit "$INV" claude-json CODE "$H/.claude.json" 1)"
t_eq "LaunchAgents are scanned" yes "$(hit "$INV" launchd CODE "$H/Library/LaunchAgents/com.test.x.plist" 1)"

t_section "--verify and --selftest"
o="$(pp "$P" "$X" --verify 2>"$T/v.err")"; c=$?
t_eq "--verify with CODE rows" 1 "$c"
t_eq "the exact summary" '  note: CODE=9 DOC=1 EXEMPT=3 (stale: 0)' "$(summary "$o")"
t_has "a FAIL line names the CODE rows" "$o" "FAIL: 9 executable or config literal(s)"
N=$(( $(awk '/^[[:space:]]*t_(match|class|ex) /' "$TOOL" | wc -l) + 1 ))  # + the EVALS exclusion, not a t_* call
o="$(pp "$P" "$X" --selftest 2>&1)"; c=$?
t_eq "--selftest" 0 "$c"
t_eq "every selftest case ran" 1 "$(printf '%s\n' "$o" | grep -cxF "port-paths: $N ok, 0 failed, 0 warnings")"
t_eq "--selftest skipped nothing" 0 "$(printf '%s\n' "$o" | grep -c '^  skip:')"

t_section "it cannot look and say green: missing, unreadable, empty"
P2="$T/port2"; repo "$P2/zorbcorp"; put "$P2/zorbcorp/a.sh" 'echo fine'; track "$P2/zorbcorp"
ppc "$P2" /dev/null > "$T/inv2.tsv" 2>/dev/null
t_eq "no harbor checkout is a CODE row" yes "$(hit "$T/inv2.tsv" harbor-tracked CODE "$P2/harbor" -)"
o="$(ppc "$P2" /dev/null --verify 2>/dev/null)"; c=$?
t_eq "no harbor: --verify" 1 "$c"; t_eq "no harbor: summary" '  note: CODE=1 DOC=0 EXEMPT=0 (stale: 0)' "$(summary "$o")"
P3="$T/port3"; repo "$P3/harbor"; put "$P3/harbor/a.sh" 'echo fine'; track "$P3/harbor"
mkdir -p "$P3/broken"; printf 'gitdir: %s/nowhere\n' "$T" > "$P3/broken/.git"
ppc "$P3" /dev/null > "$T/inv3.tsv" 2>/dev/null
t_eq "a repo git cannot read is a CODE row" yes "$(hit "$T/inv3.tsv" repo:broken CODE "$P3/broken" -)"
o="$(ppc "$P3" /dev/null --verify 2>/dev/null)"; c=$?
t_eq "unreadable repo: --verify" 1 "$c"; t_eq "unreadable repo: summary" '  note: CODE=1 DOC=0 EXEMPT=0 (stale: 0)' "$(summary "$o")"
mkdir -p "$T/port-empty"
for p in "$T/port-empty" "$T/port-absent"; do
  ppc "$p" /dev/null > "$T/inv-none.tsv" 2>/dev/null
  t_eq "no repo under ${p##*/} is a CODE row" yes "$(hit "$T/inv-none.tsv" port-root CODE "$p" -)"
  o="$(ppc "$p" /dev/null --verify 2>/dev/null)"; c=$?
  t_eq "${p##*/}: --verify" 1 "$c"; t_eq "${p##*/}: summary" '  note: CODE=1 DOC=0 EXEMPT=0 (stale: 0)' "$(summary "$o")"
done

t_section "green at CODE=0, stale rows named, a dead scan is exit 3 (D-29 unchecked)"
P4="$T/port4"; X4="$T/exempt4.tsv"; repo "$P4/harbor"
put "$P4/harbor/a.sh" '# was ~/harbor/bin'
put "$P4/harbor/b.md" 'a **bold** note that names no path'
put "$P4/harbor/c.sh" "# was $HC/harbor/bin"
track "$P4/harbor"
printf 'file\ttext\twhy\nharbor/a.sh\tno longer here\tgone\nharbor/a.sh\t*\trecord\nharbor/b.md\t*\trecord\nharbor/c.sh\t@HOME@/harbor/bin\trecord\n' > "$X4"
o="$(ppc "$P4" "$X4" --verify 2>"$T/v4.err")"; c=$?; E4="$o"; SE='STALE exemption: harbor'
t_eq "--verify at CODE=0" 0 "$c"; t_eq "counts two stale rows" '  note: CODE=0 DOC=0 EXEMPT=2 (stale: 2)' "$(summary "$o")"
t_has "says green" "$o" "ok: no CODE literal names a pre-move path"
t_has "names the stale * row of a file that names no path" "$E4" "$SE/b.md"
t_has "names the stale line row" "$E4" "$SE/a.sh — \"no longer here\""
t_hasnt "a * row whose file still names a path is not stale" "$E4" "$SE/a.sh — \"*\""
t_hasnt "an @HOME@ row whose line is there is not stale" "$E4" "$SE/c.sh"
# A skill retired from the tree but still installed: its row exempts the installed copy, so it is not stale.
mkdir -p "$CC/skills/gone"; printf 'see ~/harbor/MAP.md\n' > "$CC/skills/gone/SKILL.md"
printf 'harbor/skills/gone/SKILL.md\tsee ~/harbor/MAP.md\trecord\n' >> "$X4"
t_hasnt "a row whose line lives on in the installed copy is not stale" "$(ppc "$P4" "$X4" --verify 2>&1)" "$SE/skills/gone"
rm -rf "$CC/skills/gone"
t_has "...and is, once the installed copy is gone too" "$(ppc "$P4" "$X4" --verify 2>&1)" "$SE/skills/gone"
o="$(TMPDIR="$T/no-such-dir" HOME="$HC" CLAUDE_CONFIG_DIR="$CC" PORT_ROOT="$P4" PORT_PATHS_EXEMPT="$X4" sh "$TOOL" --verify 2>&1)"; c=$?
t_eq "a scan with nowhere to write" 3 "$c"; t_has "says it is not a green" "$o" "not a green"
o="$(ppc "$T/port-absent" /dev/null --help 2>&1)"; c=$?
t_eq "--help" 0 "$c"; t_has "--help describes --verify" "$o" "--verify"
t_eq "an unknown argument" 2 "$(pp "$P" "$X" --no-such-flag >/dev/null 2>&1; echo $?)"

t_section "worktrees: measured when the owner is outside, skipped when inside (harbor#629)"
W="$T/wtsrc"; P5="$T/port5"; repo "$W/harbor-main"
put "$W/harbor-main/bin/tool.sh" 'REPO="$HOME/harbor"'
put "$W/harbor-main/skills/x/EVALS/r/a.jsonl" '{"p":"~/harbor/x"}'
track "$W/harbor-main"; git -C "$W/harbor-main" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
git -C "$W/harbor-main" worktree add -q -b fixture-branch "$W/harbor-wt-b" 2>/dev/null
mkdir -p "$P5"; ln -s "$W/harbor-wt-b" "$P5/harbor"
t_eq "the fixture is a real worktree" yes "$([ -f "$W/harbor-wt-b/.git" ] && echo yes)"
ppc "$P5" /dev/null > "$T/inv5.tsv" 2>/dev/null
t_eq "a harbor worktree is scanned" yes "$(hit "$T/inv5.tsv" harbor-tracked CODE "$P5/harbor/bin/tool.sh" 1)"
t_eq "and not reported NO CHECKOUT" none "$(none "$T/inv5.tsv" '$5 ~ /NO CHECKOUT/')"
o="$(ppc "$P5" /dev/null --selftest 2>&1)"; c=$?
t_eq "--selftest on a worktree" 0 "$c"; t_eq "checks the EVALS exclusion there" 0 "$(printf '%s\n' "$o" | grep -c '^  skip:')"
P7="$T/port7"; repo "$P7/az"; put "$P7/az/a.sh" 'cd ~/az/x'; track "$P7/az"
git -C "$P7/az" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
git -C "$P7/az" worktree add -q -b feat "$P7/az-feature" 2>/dev/null
t_eq "the fixture is a real worktree, named without -wt-" yes "$([ -f "$P7/az-feature/.git" ] && echo yes)"
ppc "$P7" /dev/null > "$T/inv7.tsv" 2>/dev/null
t_eq "the owner repo is scanned" yes "$(hit "$T/inv7.tsv" repo:az CODE "$P7/az/a.sh" 1)"
t_eq "its worktree is not a repo of its own" none "$(none "$T/inv7.tsv" '$1 ~ /az-feature/')"

t_section "the installed constitution and MEMORY/ are read (harbor#653)"
H6="$T/home6"; C6="$T/cfg6"; P6="$T/port6"; X6="$T/exempt6.tsv"; mkdir -p "$H6"; repo "$P6/harbor"
put "$P6/harbor/policy/constitution.md" '> **Path root:** `~/port/harbor` — every ./ path resolves there
Measured on the tree then at `~/harbor/bin`: done'
track "$P6/harbor"
put "$C6/CLAUDE.md" '> **Path root:** `~/harbor` — every ./ path resolves there
Measured on the tree then at `~/harbor/bin`: done'
put "$C6/MEMORY/IDENTITY.md" 'select one per command via `~/harbor/bin/gcx <role>`:'
put "$C6/MEMORY/WORK/s1.md"  'cd ~/harbor'
printf 'file\ttext\twhy\nharbor/policy/constitution.md\tthe tree then at `~/harbor/bin`\ta dated measurement\n' > "$X6"
run_pp "$H6" "$C6" "$P6" "$X6" > "$T/inv6.tsv" 2>/dev/null
t_eq "a pre-move Path root in CLAUDE.md is CODE" yes "$(hit "$T/inv6.tsv" claude-instructions CODE "$C6/CLAUDE.md" 1)"
t_eq "CLAUDE.md is judged by policy/constitution.md's rows" yes "$(hit "$T/inv6.tsv" claude-instructions EXEMPT "$C6/CLAUDE.md" 2)"
t_eq "the same row exempts policy/constitution.md" yes "$(hit "$T/inv6.tsv" harbor-tracked EXEMPT "$P6/harbor/policy/constitution.md" 2)"
t_eq "MEMORY/*.md is DOC" yes "$(hit "$T/inv6.tsv" claude-memory DOC "$C6/MEMORY/IDENTITY.md" 1)"
t_eq "MEMORY/WORK/ is not scanned" none "$(none "$T/inv6.tsv" "index(\$3, \"$C6/MEMORY/WORK/\") == 1")"
o="$(run_pp "$H6" "$C6" "$P6" "$X6" --verify 2>/dev/null)"; c=$?
t_eq "stale installed root: --verify" 1 "$c"; t_eq "stale installed root: summary" '  note: CODE=1 DOC=1 EXEMPT=2 (stale: 0)' "$(summary "$o")"
cp "$P6/harbor/policy/constitution.md" "$C6/CLAUDE.md"
o="$(run_pp "$H6" "$C6" "$P6" "$X6" --verify 2>/dev/null)"; c=$?
t_eq "installed caught up: --verify" 0 "$c"; t_eq "installed caught up: summary" '  note: CODE=0 DOC=1 EXEMPT=2 (stale: 0)' "$(summary "$o")"
t_done
