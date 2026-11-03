#!/usr/bin/env sh
# lint-port-paths.sh reads the private layer's port-paths-exempt.tsv after the core table (harbor#1149): the rows that quote
# a client's directory are data in the private layer, and with no layer they simply count again. Everything is a fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE XDG_CONFIG_HOME PORT_ROOT PORT_PATHS_EXEMPT
export GIT_CONFIG_NOSYSTEM=1
# A private copy of the tool, so the core table it reads is the fixture's own.
R="$T/root"; mkdir -p "$R/bin" "$R/contracts"
cp "$T_ROOT/bin/lint-port-paths.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$R/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$R/contracts/"
TOOL="$R/bin/lint-port-paths.sh"
H="$T/home"; C="$T/cfg"; P="$H/port"; PV="$T/priv"
mkdir -p "$H/.claude" "$C" "$P" "$PV"; export HOME="$H"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
repo() { mkdir -p "$1"; git -C "$1" init -q; }
repo "$P/harbor"; put "$P/harbor/bin/a.sh" 'echo fine'; git -C "$P/harbor" add -A
repo "$P/zorbcorp"
put "$P/zorbcorp/CLIENTS/ACME/run.sh" 'cd ~/harbor # pinned'
put "$P/zorbcorp/CLIENTS/ACME/notes.md" 'moved out of ~/harbor/bin'
put "$P/zorbcorp/tool.sh" 'cd ~/harbor # pinned'
git -C "$P/zorbcorp" add -A
printf 'file\ttext\twhy\nzorbcorp/tool.sh\tcd ~/harbor # pinned\tpinned in core\n' > "$R/contracts/port-paths-exempt.tsv"
OVER="file${TAB}text${TAB}why
zorbcorp/CLIENTS/ACME/run.sh${TAB}cd ~/harbor # pinned${TAB}a client script, pinned
zorbcorp/CLIENTS/ACME/notes.md${TAB}*${TAB}a dated record
zorbcorp/CLIENTS/ACME/gone.sh${TAB}no longer here${TAB}a row whose line is gone"
pp() { HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" HARBOR_SCOPE_PRIVATE="$PV" sh "$TOOL" "$@"; }
cls() { pp 2>/dev/null | awk -F'\t' -v f="$P/zorbcorp/$1" -v l="$2" '$3 == f && $4 == l { print $2 }'; }  # <file> <line> → class
sum() { pp --verify 2>&1 | sed -n 's/^  note: \(CODE=.*\)$/\1/p'; }

t_section "no private table: only the core table is read, and the client lines count again"
rm -f "$PV/port-paths-exempt.tsv"
t_eq "a core row exempts its line" EXEMPT "$(cls tool.sh 1)"
t_eq "a client script line is CODE" CODE "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "a client document line is DOC" DOC "$(cls CLIENTS/ACME/notes.md 1)"
t_eq "the summary counts them" "CODE=1 DOC=1 EXEMPT=1 (stale: 0)" "$(sum)"
t_eq "a layer that does not exist is the same" "CODE=1 DOC=1 EXEMPT=1 (stale: 0)" "$(HARBOR_SCOPE_PRIVATE="$T/no-layer" sum)"

t_section "the instrument's own files are data in every repo, not only in harbor"
# A mirror of harbor (harbor-core) carries the script, its suites and a table; a private layer keeps a table at its root.
repo "$P/quux-core"
put "$P/quux-core/bin/lint-port-paths.sh" 'cd ~/harbor # a selftest vector'
put "$P/quux-core/tests/install/port-paths/x.test.sh" 'put a.sh "cd ~/harbor"'
put "$P/quux-core/contracts/port-paths-exempt.tsv" 'quux/bin/x.sh	cd ~/harbor	quoted'
put "$P/quux-core/port-paths-exempt.tsv" 'quux/bin/x.sh	cd ~/harbor	quoted'
put "$P/quux-core/bin/real.sh" 'cd ~/harbor'
git -C "$P/quux-core" add -A
qcls() { pp 2>/dev/null | awk -F'\t' -v f="$P/quux-core/$1" '$3 == f { print $2; exit }'; }
t_eq "a mirror's copy of the script is not scanned" "" "$(qcls bin/lint-port-paths.sh)"
t_eq "...nor its suite's fixtures" "" "$(qcls tests/install/port-paths/x.test.sh)"
t_eq "...nor an exemption table, in contracts/ or at the root" "" "$(qcls contracts/port-paths-exempt.tsv)$(qcls port-paths-exempt.tsv)"
t_eq "...while a real script beside them is still CODE" CODE "$(qcls bin/real.sh)"
rm -rf "$P/quux-core"

t_section "a private table exempts its rows beside the core's"
printf '%s\n' "$OVER" > "$PV/port-paths-exempt.tsv"
t_eq "the client script line is EXEMPT" EXEMPT "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "a * row exempts the client document" EXEMPT "$(cls CLIENTS/ACME/notes.md 1)"
t_eq "the core row still exempts its line" EXEMPT "$(cls tool.sh 1)"
t_eq "the summary has no CODE left" "CODE=0 DOC=0 EXEMPT=3 (stale: 1)" "$(sum)"
t_eq "--verify is green" 0 "$(pp --verify >/dev/null 2>&1; echo $?)"
t_has "a stale private row is a WARN that names the file" "$(pp --verify 2>&1)" "WARN: STALE exemption: zorbcorp/CLIENTS/ACME/gone.sh"
t_has "and gives the fix" "$(pp --verify 2>&1)" "fix: delete that row from the table it lives in"

t_section "a private row exempts only its own file and line"
put "$P/zorbcorp/CLIENTS/ACME/other.sh" 'cd ~/harbor # pinned'; git -C "$P/zorbcorp" add -A
t_eq "the same text in another client file stays CODE" CODE "$(cls CLIENTS/ACME/other.sh 1)"
put "$P/zorbcorp/CLIENTS/ACME/run.sh" 'cd ~/harbor/new'; git -C "$P/zorbcorp" add -A
t_eq "a new literal in an exempted client file is CODE" CODE "$(cls CLIENTS/ACME/run.sh 1)"
put "$P/zorbcorp/CLIENTS/ACME/run.sh" 'cd ~/harbor # pinned'; rm -f "$P/zorbcorp/CLIENTS/ACME/other.sh"; git -C "$P/zorbcorp" add -A

t_section "an unusable private table is the core table alone"
rm -f "$PV/port-paths-exempt.tsv"; mkdir "$PV/port-paths-exempt.tsv"
t_eq "a directory where the table should be: the client line is CODE again" CODE "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "and the core row still works" EXEMPT "$(cls tool.sh 1)"
rmdir "$PV/port-paths-exempt.tsv"; printf '%s\n' "$OVER" > "$PV/port-paths-exempt.tsv"; chmod 000 "$PV/port-paths-exempt.tsv"
if [ -r "$PV/port-paths-exempt.tsv" ]; then echo "  SKIP unreadable table: this user reads a mode-000 file"
else t_eq "an unreadable table: the client line is CODE again" CODE "$(cls CLIENTS/ACME/run.sh 1)"; fi
chmod 644 "$PV/port-paths-exempt.tsv"

t_section "PORT_PATHS_EXEMPT names the only table read"
t_eq "with the override set the private table is not read" CODE "$(PORT_PATHS_EXEMPT="$R/contracts/port-paths-exempt.tsv" cls CLIENTS/ACME/run.sh 1)"
t_eq "and the override's own rows still work" EXEMPT "$(PORT_PATHS_EXEMPT="$R/contracts/port-paths-exempt.tsv" cls tool.sh 1)"

t_section "the layer is found through the resolver when HARBOR_SCOPE_PRIVATE is not set"
mkdir -p "$P/harbor-private"; cp "$PV/port-paths-exempt.tsv" "$P/harbor-private/port-paths-exempt.tsv"
t_eq "PORT_ROOT/harbor-private/port-paths-exempt.tsv is read" EXEMPT "$(HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" sh "$TOOL" 2>/dev/null | awk -F'\t' -v f="$P/zorbcorp/CLIENTS/ACME/run.sh" '$3 == f && $4 == 1 { print $2 }')"
t_done
