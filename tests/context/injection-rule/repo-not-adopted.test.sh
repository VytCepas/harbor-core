#!/usr/bin/env sh
# repo-not-adopted.test.sh (harbor#1278) — the session-start finding through the real engine. A git checkout at depth 1 of
# PORT_ROOT with no registry row, or with a governed=no row, is named with its `harbor repo adopt` command; a governed repo,
# a directory with no .git, the private layer and a dot directory are not; nothing at all is said when none is left. The list
# is bin/scope-repo-sources.sh --not-adopted's, and a copy of it with the .git test broken turns the fire case silent.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE
T="$T_TMP"; CFG="$CLAUDE_CONFIG_DIR"; U="$T_ROOT/context-rules/user"; BOX="$CFG/context-rules/user"
mkdir -p "$BOX" "$CFG/bin"
cp "$U/repo-not-adopted.md" "$U/repo-not-adopted.sh" "$BOX/"
cp "$T_ROOT/hooks/injection-rule/injection-rule.sh" "$T_ROOT/bin/library-admission.sh" "$CFG/bin/"
# The installed pack finds the harbor checkout by HARBOR_SCOPE_REPO, as on a box whose checkout is not PORT_ROOT/harbor.
HARBOR_SCOPE_REPO="$T_ROOT"; export HARBOR_SCOPE_REPO
PORT_ROOT="$HOME/port"; export PORT_ROOT
PV="$PORT_ROOT/harbor-private"; mkdir -p "$PV"
gitdir() { mkdir -p "$PORT_ROOT/$1"; git -C "$PORT_ROOT/$1" init -q . 2>/dev/null; }
# id path kind remote topology interaction note domain governed owner covers
row() { printf '%s\t%s\t%s\t-\t-\t-\t-\t-\t%s\t-\t-\n' "$1" "$1" "$2" "$3"; }
gitdir gov; gitdir newproj; gitdir legacy; gitdir harbor-private; gitdir .hidden; mkdir -p "$PORT_ROOT/notrepo/.agents"
{ printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n'
  row gov workload yes; row legacy data no; } > "$PV/repos.tsv"
N=0
start() { # → the engine's note for one fresh session start, in $NOTE
  N=$((N + 1))
  NOTE="$(printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"rna%s"}' "$N" \
    | CLAUDE_PROJECT_DIR="$T" /bin/sh "$CFG/bin/injection-rule.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
}

t_section "a repo harbor does not govern is named, with the command that adopts it"
start
t_has "the note is the pack's" "$NOTE" "[context:repo-not-adopted]"
t_has "a git dir with no registry row is named with its adopt command" "$NOTE" \
  "newproj (no registry row): harbor repo adopt newproj --kind <repo-kind>"
t_has "a governed=no row is named with the kind the registry holds" "$NOTE" \
  "legacy (registered, governed=no): harbor repo adopt legacy --kind data"
t_has "…and says adopt leaves its governed cell to the operator" "$NOTE" "its governed cell stays no"
t_has "the kinds are the register's" "$NOTE" "<repo-kind> is one of: control-plane data fleet-controller scaffolder workload."
t_has "the workspace root is shown as ~, never an absolute home" "$NOTE" "Repos under ~/port that harbor does not govern yet"
t_has "the run is left to the operator" "$NOTE" "leave the run to them"

t_section "what is governed, not a repo, or never a registry row stays silent"
t_hasnt "a governed repo" "$NOTE" "gov ("
t_hasnt "a directory with no .git" "$NOTE" "notrepo"
t_hasnt "the private layer (a reserved id, never a repos.tsv row)" "$NOTE" "harbor-private"
t_hasnt "a dot directory (.worktrees, .hidden)" "$NOTE" ".hidden"

t_section "nothing is said when every repo is governed, or when nothing can be compared"
{ printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n'
  row gov workload yes; row legacy data yes; row newproj workload yes; } > "$PV/repos.tsv"
start
t_eq "every repo governed: no note" "" "$NOTE"
rm "$PV/repos.tsv"
start
t_eq "no registry (scope-repo-sources exits 3): no note" "" "$NOTE"
printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n' > "$PV/repos.tsv"
start
t_has "a registry with a header and no row (a fresh box) names every git dir, as the disk is all there is to compare" "$NOTE" "newproj (no registry row)"
rm "$PV/repos.tsv"
{ printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n'
  row gov workload yes; row legacy data no; } > "$PV/repos.tsv"
HARBOR_SCOPE_REPO="$T/no-such-checkout"
start
t_eq "no harbor checkout to read: no note" "" "$NOTE"
HARBOR_SCOPE_REPO="$T_ROOT"

t_section "the finding rests on the disk scan: a scan with its .git test broken goes silent"
M="$T/mini"; mkdir -p "$M/bin" "$M/contracts" "$M/standards/naming"
cp "$T_ROOT"/bin/*.sh "$M/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$M/contracts/"; cp "$T_ROOT"/standards/naming/*.tsv "$M/standards/naming/"
sed 's|\[ -e "\$_d.git" \]|[ -e "$_d.no-such-git" ]|' "$T_ROOT/bin/scope-repo-sources.sh" > "$M/bin/scope-repo-sources.sh"
t_eq "the mutant differs from the shipped script (the sed hit)" "yes" \
  "$(cmp -s "$T_ROOT/bin/scope-repo-sources.sh" "$M/bin/scope-repo-sources.sh" && echo no || echo yes)"
HARBOR_SCOPE_REPO="$M"
start
t_eq "the broken scan finds no git dir, so the whole note goes silent" "" "$NOTE"
HARBOR_SCOPE_REPO="$T_ROOT"
start
t_has "restored, it is named again" "$NOTE" "newproj (no registry row)"

t_done
