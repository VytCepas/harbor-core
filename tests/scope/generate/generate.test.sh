#!/usr/bin/env sh
# scope-repos-generate.sh (harbor#966): the lists of repos are generated from the one registry, and --check is red when
# one of them is not. Everything is a fixture: HOME, PORT_ROOT and the private layer.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/scope-repos-generate.sh"
T="$(CDPATH='' cd -P -- "$T_TMP" && pwd -P)"; TAB="$(printf '\t')"
unset PORT_ROOT HARBOR_SCOPE_PRIVATE
export HOME="$T/home"; P="$HOME/port"; V="$P/harbor-private"
mkdir -p "$P/alpha" "$P/yard" "$P/fleet" "$P/group/beta" "$V/context-rules/user"
HDR='id	path	kind	remote	topology	interaction	note	domain	governed	owner	covers
'
# alpha: governed tracking workload; yard/fleet: the platform roles under their NEW names; beta: nested, ungoverned; gamma: not yet described.
printf '%s' "$HDR" > "$V/repos.tsv"
cat >> "$V/repos.tsv" <<ROWS
alpha	alpha	workload	-	stream-aligned	x-as-a-service	-	tracking	yes	operator	tags and pixels
yard	yard	scaffolder	-	platform	-	-	-	yes	operator	the scaffolder
fleet	fleet	fleet-controller	-	platform	-	-	-	yes	operator	the fleet controller
beta	group/beta	workload	-	enabling	collaboration	-	ops	no	operator	a nested scratch repo
gamma	gamma	workload	-
ROWS
TBL="$T/roots.tsv"
cp "$T_ROOT/contracts/roots.tsv" "$TBL"
gen() { PORT_ROOT="$P" HARBOR_SCOPE_PRIVATE="$V" HARBOR_SCOPE_ROOTS_TABLE="$TBL" sh "$TOOL" "$@"; }

t_section "--projects: governed rows with a covers text, home-relative paths"
_out="$(gen --projects 2>/dev/null)"
t_has "a governed row is listed with its covers" "$_out" "alpha${TAB}~/port/alpha${TAB}tags and pixels"
t_has "...a platform row too" "$_out" "yard${TAB}~/port/yard${TAB}the scaffolder"
t_hasnt "an ungoverned row is not" "$_out" "beta"
t_hasnt "a row with no description is not" "$_out" "gamma"
t_hasnt "no absolute home reaches the output" "$_out" "$HOME"

t_section "--roots: the role rows follow the registry's paths, nothing else moves"
_roots="$(gen --roots 2>/dev/null)"
t_has "the scaffolder row names its new checkout" "$_roots" "HARBOR_SCOPE_SCAFFOLDER${TAB}REPOS${TAB}yard${TAB}"
t_has "the fleet controller row too" "$_roots" "HARBOR_SCOPE_FLEET_CONTROLLER${TAB}REPOS${TAB}fleet${TAB}"
t_has "the fleet file follows its controller" "$_roots" "HARBOR_SCOPE_FLEET_FILE${TAB}REPOS${TAB}fleet/fleet.yaml${TAB}"
t_has "the second name for the scaffolder follows too" "$_roots" "PROJECT_INIT_SRC${TAB}REPOS${TAB}yard${TAB}"
t_eq "the harbor row and the BOX rows are untouched" "$(grep -E '^(HARBOR_SCOPE_REPO|HARBOR_SCOPE_LOCAL_BIN)'"$TAB" "$TBL")" "$(printf '%s\n' "$_roots" | grep -E '^(HARBOR_SCOPE_REPO|HARBOR_SCOPE_LOCAL_BIN)'"$TAB")"
printf '%s\n' "$_roots" > "$T/roots.gen"
t_eq "only the four registry-owned rows differ from the table" 4 "$(diff "$TBL" "$T/roots.gen" | grep -c '^>')"

t_section "--fleet and --readme"
t_has "the fleet stanza names the workspace root" "$(gen --fleet 2>/dev/null)" "  - $P"
t_has "...and every nested checkout the depth-1 scan cannot see" "$(gen --fleet 2>/dev/null)" "  - $P/group/beta"
_rd="$(gen --readme 2>/dev/null)"
t_has "the README groups by domain" "$_rd" "## tracking"
t_has "...lists the repo with what it covers" "$_rd" '| `alpha` | workload | yes | tags and pixels |'
t_has "...and says plainly when a row has no description" "$_rd" "not yet written"

t_section "--check: red when a list is missing a row, green once it is put in place"
t_exit "nothing is in place yet: ABSENT is red" 1 gen --check
t_has "...and names which list" "$(gen --check 2>&1)" "project registry"
gen --out "$T/out" >/dev/null 2>&1
cp "$T/out/projects.tsv" "$V/context-rules/user/projects.tsv"; cp "$T/out/README.md" "$P/README.md"; cp "$T/out/roots.tsv" "$TBL"
# fleet.yaml lives in the fleet checkout: the registry's fleet row resolves HARBOR_SCOPE_FLEET_FILE to fleet/fleet.yaml
cp "$T/out/fleet.yaml" "$P/fleet/fleet.yaml"
t_exit "all four in place: green" 0 gen --check
printf 'omega\t~/port/omega\ta row the registry never had\n' >> "$V/context-rules/user/projects.tsv"
t_exit "a row in projects.tsv the registry lacks is red" 1 gen --check
t_has "...naming it" "$(gen --check 2>&1)" "omega"
cp "$T/out/projects.tsv" "$V/context-rules/user/projects.tsv"
grep -v '^alpha' "$V/context-rules/user/projects.tsv" > "$T/p2"; cp "$T/p2" "$V/context-rules/user/projects.tsv"
t_exit "a registry row projects.tsv lacks is red" 1 gen --check
t_has "...naming it" "$(gen --check 2>&1)" "alpha"
cp "$T/out/projects.tsv" "$V/context-rules/user/projects.tsv"
t_exit "back to green" 0 gen --check

t_section "renaming the scaffolder in the registry changes the roots table and nothing else (harbor#966, #999)"
sed 's/^yard\tyard\t/yard\tyard-renamed\t/' "$V/repos.tsv" > "$T/rn"; mv "$T/rn" "$V/repos.tsv"; mkdir -p "$P/yard-renamed"
t_has "the roots output follows the new path" "$(gen --roots 2>/dev/null)" "HARBOR_SCOPE_SCAFFOLDER${TAB}REPOS${TAB}yard-renamed${TAB}"
t_exit "--check is red on the stale roots table: the rename window must carry it" 1 gen --check

t_section "it never reads a missing registry as a clean one"
rm -f "$V/repos.tsv"
t_exit "no registry: exit 3, not a pass" 3 gen --check
printf '%s' "$HDR" > "$V/repos.tsv"
printf 'plain\tplain\tworkload\t-\n' >> "$V/repos.tsv"
t_exit "a registry with no governed row: exit 3" 3 gen --check
t_exit "...and --projects says the same" 3 gen --projects
printf 'bad\t/abs\tworkload\t-\n' >> "$V/repos.tsv"
t_exit "a refused registry: exit 2" 2 gen --check
t_exit "an unknown argument: exit 2" 2 gen --nonsense
t_done
