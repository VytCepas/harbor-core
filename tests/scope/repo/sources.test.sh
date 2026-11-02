#!/usr/bin/env sh
# The four places a repo is known (harbor#1430): repos.tsv, projects.tsv, yard markers and fleet discovery. scope-repo-sources.sh prints
# each repo present in one and missing from another, and context.repo-sources-agree reads the same verdict as an advisory. The fleet CLI
# is a stub that lists every top-level directory carrying .agents/config.yaml, as fleet's own discovery does.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
S="$T_ROOT/bin/scope-repo-sources.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
TAB='	'
PORT_ROOT="$T/port"; export PORT_ROOT
PV="$PORT_ROOT/harbor-private"; RULES="$PV/context-rules/user"; mkdir -p "$RULES"
cat > "$T/fleet" <<'STUB'
#!/bin/sh
[ "$1" = projects ] || exit 0
[ -z "$fleet_stub_down" ] || exit 1
shift; while [ $# -gt 0 ]; do [ "$1" = --root ] && root="$2"; shift; done
for d in "$root"/*/; do [ -f "${d}.agents/config.yaml" ] && printf '%s  (none, %s)\n' "$(basename "$d")" "${d%/}"; done
exit 0
STUB
chmod +x "$T/fleet"; HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$T/fleet"; export HARBOR_SCOPE_FLEET_CONTROLLER_BIN
run() { sh "$S" "$@" 2>/dev/null; }
code() { sh "$S" "$@" >/dev/null 2>&1; echo "exit $?"; }
mkrepo() { mkdir -p "$PORT_ROOT/$1/.agents"; : > "$PORT_ROOT/$1/.agents/config.yaml"; [ "${2:-marker}" != marker ] || { mkdir -p "$PORT_ROOT/$1/.claude"; : > "$PORT_ROOT/$1/.claude/project-init.md"; }; }
# id path kind remote topology interaction note domain governed owner covers
row() { printf '%s\t%s\t%s\t-\t-\t-\t-\t-\t%s\t-\t%s\n' "$1" "$2" "${3:-workload}" "${4:-yes}" "${5:--}"; }

t_section "no registry, or no governed row, is unchecked and never a green"
t_eq "no registry at all" "exit 3" "$(code)"
printf 'id\tpath\tkind\tremote\n' > "$PV/repos.tsv"
t_eq "an empty registry" "exit 3" "$(code)"
{ printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n'; row ungov ungov workload no; } > "$PV/repos.tsv"; mkrepo ungov
t_eq "a registry with no governed row" "exit 3" "$(code)"

t_section "four sources that agree print nothing and exit 0"
mkrepo alpha; mkrepo beta
{ printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\n'
  row alpha alpha workload yes "what alpha answers"; row beta beta workload yes "what beta answers"; row ungov ungov workload no; } > "$PV/repos.tsv"
printf 'alpha\t~/port/alpha\twhat alpha answers\nbeta\t~/port/beta\twhat beta answers\n' > "$RULES/projects.tsv"
t_eq "exit 0" "exit 0" "$(code)"
t_eq "…and no delta line" "" "$(run)"
t_eq "the matrix shows alpha in all four" "alpha${TAB}alpha${TAB}workload${TAB}yes${TAB}yes${TAB}yes${TAB}yes${TAB}yes" "$(run --matrix | grep '^alpha')"
t_eq "an ungoverned repo is expected in the registry alone" "" "$(run | grep ungov)"

t_section "a repo present in one source and missing from another is a line naming both"
rm "$PORT_ROOT/beta/.claude/project-init.md"
t_eq "a governed repo with no yard marker" "beta${TAB}present: registry,projects.tsv,fleet${TAB}missing: marker" "$(run)"
t_eq "…exit 1" "exit 1" "$(code)"
: > "$PORT_ROOT/beta/.claude/project-init.md"
printf 'alpha\t~/port/alpha\twhat alpha answers\n' > "$RULES/projects.tsv"
t_eq "a governed repo with covers and no projects.tsv row" "beta${TAB}present: registry,marker,fleet${TAB}missing: projects.tsv" "$(run)"
printf 'alpha\t~/port/alpha\twhat alpha answers\nbeta\t~/port/beta\twhat beta answers\n' > "$RULES/projects.tsv"
rm "$PORT_ROOT/beta/.agents/config.yaml"
t_eq "a governed repo fleet's discovery does not find" "beta${TAB}present: registry,projects.tsv,marker${TAB}missing: fleet" "$(run)"
: > "$PORT_ROOT/beta/.agents/config.yaml"
mkrepo zarija
t_eq "a marker and a fleet berth with no registry row (the zarija shape)" "zarija${TAB}present: marker,fleet${TAB}missing: registry" "$(run)"
rm -rf "$PORT_ROOT/zarija"
printf 'alpha\t~/port/alpha\twhat alpha answers\nbeta\t~/port/beta\twhat beta answers\nghost\t~/port/ghost\tnothing\n' > "$RULES/projects.tsv"
t_eq "a projects.tsv name the registry lacks" "ghost${TAB}present: projects.tsv${TAB}missing: registry" "$(run)"
printf 'alpha\t~/port/alpha\twhat alpha answers\nbeta\t~/port/beta\twhat beta answers\n' > "$RULES/projects.tsv"
t_eq "restored, it is green again" "exit 0" "$(code)"

t_section "an unreachable fleet CLI leaves that column unchecked and the others compared"
t_eq "exit 0 with the fleet down and the rest agreeing" "exit 0" "$(fleet_stub_down=1 code)"
rm "$PORT_ROOT/alpha/.claude/project-init.md"
t_has "…and a real delta is still found" "$(fleet_stub_down=1 run)" "alpha${TAB}present: registry,projects.tsv${TAB}missing: marker"
: > "$PORT_ROOT/alpha/.claude/project-init.md"

t_section "the lint rule context.repo-sources-agree is an advisory over the same verdict"
. "$T_ROOT/tests/checks/lint-fixture.sh"
M="$T/mini"; mkdir -p "$M/bin" "$M/contracts" "$M/standards/naming"; cp "$T_ROOT"/bin/*.sh "$M/bin/"; cp "$T_ROOT"/contracts/roots.tsv "$M/contracts/"; cp "$T_ROOT"/standards/naming/*.tsv "$M/standards/naming/"
t_hasnt "agreeing sources: no advisory" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY"
t_eq "…and no violation" 0 "$(vcount "$(lint1 context.repo-sources-agree "$M")")"
rm "$PORT_ROOT/alpha/.claude/project-init.md"
t_has "a disagreement is an advisory naming the repo and the source" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY [context.repo-sources-agree] alpha present: registry,projects.tsv,fleet, missing: marker"
t_eq "…and never a violation (born warn)" 0 "$(vcount "$(lint1 context.repo-sources-agree "$M")")"
: > "$PORT_ROOT/alpha/.claude/project-init.md"
rm -rf "$PV"
t_hasnt "with no registry the rule says nothing (it did not look; the tool exits 3)" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY"

t_done
