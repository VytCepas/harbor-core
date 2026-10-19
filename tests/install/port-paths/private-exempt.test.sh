#!/usr/bin/env sh
# port-paths.sh reads the private layer's port-paths-exempt.tsv after the core table (harbor#1149): the rows that quote
# a client's directory are data in the private layer, and with no layer they simply count again. Everything is a fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE XDG_CONFIG_HOME PORT_ROOT PORT_PATHS_EXEMPT
export GIT_CONFIG_NOSYSTEM=1
# A private copy of the tool, so the core table it reads is the fixture's own.
R="$T/root"; mkdir -p "$R/bin" "$R/CONTRACTS"
cp "$T_ROOT/bin/port-paths.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/roots.sh" "$R/bin/"; cp "$T_ROOT/CONTRACTS/roots.tsv" "$R/CONTRACTS/"
TOOL="$R/bin/port-paths.sh"
H="$T/home"; C="$T/cfg"; P="$H/port"; PV="$T/priv"
mkdir -p "$H/.claude" "$C" "$P" "$PV"; export HOME="$H"
put() { mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; }
repo() { mkdir -p "$1"; git -C "$1" init -q; }
repo "$P/harbor"; put "$P/harbor/bin/a.sh" 'echo fine'; git -C "$P/harbor" add -A
repo "$P/azimuth"
put "$P/azimuth/CLIENTS/ACME/run.sh" 'cd ~/harbor # pinned'
put "$P/azimuth/CLIENTS/ACME/notes.md" 'moved out of ~/harbor/bin'
put "$P/azimuth/tool.sh" 'cd ~/harbor # pinned'
git -C "$P/azimuth" add -A
printf 'file\ttext\twhy\nazimuth/tool.sh\tcd ~/harbor # pinned\tpinned in core\n' > "$R/CONTRACTS/port-paths-exempt.tsv"
OVER="file${TAB}text${TAB}why
azimuth/CLIENTS/ACME/run.sh${TAB}cd ~/harbor # pinned${TAB}a client script, pinned
azimuth/CLIENTS/ACME/notes.md${TAB}*${TAB}a dated record
azimuth/CLIENTS/ACME/gone.sh${TAB}no longer here${TAB}a row whose line is gone"
pp() { HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" HARBOR_SCOPE_PRIVATE="$PV" sh "$TOOL" "$@"; }
cls() { pp 2>/dev/null | awk -F'\t' -v f="$P/azimuth/$1" -v l="$2" '$3 == f && $4 == l { print $2 }'; }  # <file> <line> → class
sum() { pp --verify 2>&1 | sed -n 's/^  note: \(CODE=.*\)$/\1/p'; }

t_section "no private table: only the core table is read, and the client lines count again"
rm -f "$PV/port-paths-exempt.tsv"
t_eq "a core row exempts its line" EXEMPT "$(cls tool.sh 1)"
t_eq "a client script line is CODE" CODE "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "a client document line is DOC" DOC "$(cls CLIENTS/ACME/notes.md 1)"
t_eq "the summary counts them" "CODE=1 DOC=1 EXEMPT=1 (stale: 0)" "$(sum)"
t_eq "a layer that does not exist is the same" "CODE=1 DOC=1 EXEMPT=1 (stale: 0)" "$(HARBOR_SCOPE_PRIVATE="$T/no-layer" sum)"

t_section "a private table exempts its rows beside the core's"
printf '%s\n' "$OVER" > "$PV/port-paths-exempt.tsv"
t_eq "the client script line is EXEMPT" EXEMPT "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "a * row exempts the client document" EXEMPT "$(cls CLIENTS/ACME/notes.md 1)"
t_eq "the core row still exempts its line" EXEMPT "$(cls tool.sh 1)"
t_eq "the summary has no CODE left" "CODE=0 DOC=0 EXEMPT=3 (stale: 1)" "$(sum)"
t_eq "--verify is green" 0 "$(pp --verify >/dev/null 2>&1; echo $?)"
t_has "a stale private row is a WARN that names the file" "$(pp --verify 2>&1)" "WARN: STALE exemption: azimuth/CLIENTS/ACME/gone.sh"
t_has "and gives the fix" "$(pp --verify 2>&1)" "fix: delete that row from the table it lives in"

t_section "a private row exempts only its own file and line"
put "$P/azimuth/CLIENTS/ACME/other.sh" 'cd ~/harbor # pinned'; git -C "$P/azimuth" add -A
t_eq "the same text in another client file stays CODE" CODE "$(cls CLIENTS/ACME/other.sh 1)"
put "$P/azimuth/CLIENTS/ACME/run.sh" 'cd ~/harbor/new'; git -C "$P/azimuth" add -A
t_eq "a new literal in an exempted client file is CODE" CODE "$(cls CLIENTS/ACME/run.sh 1)"
put "$P/azimuth/CLIENTS/ACME/run.sh" 'cd ~/harbor # pinned'; rm -f "$P/azimuth/CLIENTS/ACME/other.sh"; git -C "$P/azimuth" add -A

t_section "an unusable private table is the core table alone"
rm -f "$PV/port-paths-exempt.tsv"; mkdir "$PV/port-paths-exempt.tsv"
t_eq "a directory where the table should be: the client line is CODE again" CODE "$(cls CLIENTS/ACME/run.sh 1)"
t_eq "and the core row still works" EXEMPT "$(cls tool.sh 1)"
rmdir "$PV/port-paths-exempt.tsv"; printf '%s\n' "$OVER" > "$PV/port-paths-exempt.tsv"; chmod 000 "$PV/port-paths-exempt.tsv"
if [ -r "$PV/port-paths-exempt.tsv" ]; then echo "  SKIP unreadable table: this user reads a mode-000 file"
else t_eq "an unreadable table: the client line is CODE again" CODE "$(cls CLIENTS/ACME/run.sh 1)"; fi
chmod 644 "$PV/port-paths-exempt.tsv"

t_section "PORT_PATHS_EXEMPT names the only table read"
t_eq "with the override set the private table is not read" CODE "$(PORT_PATHS_EXEMPT="$R/CONTRACTS/port-paths-exempt.tsv" cls CLIENTS/ACME/run.sh 1)"
t_eq "and the override's own rows still work" EXEMPT "$(PORT_PATHS_EXEMPT="$R/CONTRACTS/port-paths-exempt.tsv" cls tool.sh 1)"

t_section "the layer is found through the resolver when HARBOR_SCOPE_PRIVATE is not set"
mkdir -p "$P/harbor-private"; cp "$PV/port-paths-exempt.tsv" "$P/harbor-private/port-paths-exempt.tsv"
t_eq "PORT_ROOT/harbor-private/port-paths-exempt.tsv is read" EXEMPT "$(HOME="$H" CLAUDE_CONFIG_DIR="$C" PORT_ROOT="$P" sh "$TOOL" 2>/dev/null | awk -F'\t' -v f="$P/azimuth/CLIENTS/ACME/run.sh" '$3 == f && $4 == 1 { print $2 }')"
t_done
