#!/usr/bin/env sh
# port-drift.sh (harbor#966): a directory under PORT_ROOT that is neither registered nor an exempt kind is red.
# Everything is a fixture: PORT_ROOT, the private layer and HOME.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/port-drift.sh"
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
unset PORT_ROOT HARBOR_SCOPE_PRIVATE
P="$T/port"; V="$T/priv"; mkdir -p "$P" "$V" "$T/home"; export HOME="$T/home"
# Six columns (topology, interaction; harbor#966) beside a four-column row: both are registered.
printf 'id\tpath\tkind\tremote\ttopology\tinteraction\nalpha\talpha\tworkload\t-\tstream-aligned\tx-as-a-service\nbeta\tgroup/beta\tworkload\t-\n' > "$V/repos.tsv"
mkdir -p "$P/alpha" "$P/group/beta" "$P/.worktrees/x" "$P/.scratch" "$P/history/old" "$P/harbor-private" \
         "$P/alpha-wt-fix" "$P/vendor-src" "$P/harbor"
printf 'note\n' > "$P/loose-file.md"
drift() { PORT_ROOT="$P" HARBOR_SCOPE_PRIVATE="$V" sh "$TOOL" "$@"; }

t_section "a tree of registered repos and exempt kinds is green"
t_exit "registered, container, dot-dirs, history, private layer, -wt- sibling, table root, loose file" 0 drift
t_eq "no names listed" "" "$(drift --names 2>/dev/null)"

t_section "a planted unregistered directory is red and named"
mkdir -p "$P/stray-repo"
t_exit "exit 1" 1 drift
t_has "names the directory" "$(drift 2>&1)" "stray-repo"
t_eq "only the planted one" "stray-repo" "$(drift --names 2>/dev/null)"
mkdir -p "$P/zeta-wt-x"
t_eq "a -wt- dir of an UNregistered id is not exempt" "stray-repo
zeta-wt-x" "$(drift --names 2>/dev/null)"

t_section "a registry that cannot be read is never green"
printf 'id\tpath\tkind\tremote\nbad\t/abs\tworkload\t-\n' > "$V/repos.tsv"
t_exit "exit 2 on a refused registry" 2 drift
t_done
