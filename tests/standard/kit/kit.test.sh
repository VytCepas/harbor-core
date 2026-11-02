#!/usr/bin/env sh
# The kit manifest (harbor#1436): standards/naming/kit.tsv says what a repo of each kind inherits. standard-kit.sh --check holds it to
# the registers both ways (a register or a control family with no row is red, so is a row that names nothing), --render hands yard a
# kind's items, --package is what standard-vendor.sh copies, and --carries holds a repo to its kind's list.
. "$(dirname "$0")/../../lib/core.sh"; t_init
K="$T_ROOT/bin/standard-kit.sh"; REG="$T_ROOT/standards/naming"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
kit() { sh "$K" --root "$T_ROOT" "$@" 2>&1; }
code() { sh "$K" --root "$T_ROOT" "$@" >/dev/null 2>&1; echo "exit $?"; }
regcopy() { rm -rf "$T/reg"; mkdir -p "$T/reg"; cp "$REG"/*.tsv "$T/reg/"; }   # a registry directory to break

t_section "the real kit covers every register and control family and every row resolves"
t_has "--check is green" "$(kit --check)" "the kit covers every register ("
t_eq "…and exits 0" "exit 0" "$(code --check)"
_nreg="$(awk -F'\t' '!/^#/ && $1 != "id"' "$REG/schemas.tsv" | grep -c .)"
t_eq "the register rows equal the schema table's rows (the derived count, not a typed one)" "$_nreg" "$(awk -F'\t' '!/^#/ && $2 == "register"' "$REG/kit.tsv" | grep -c .)"

t_section "a register with no kit row is red (the new-register falsifier)"
regcopy; printf 'standards/naming/ghost.tsv\trow\tid note\tid\t\tstandard\t-\ta register nobody put in the kit\n' >> "$T/reg/schemas.tsv"
t_has "the schema row with no kit row is named" "$(kit --check --registry "$T/reg")" "register standards/naming/ghost.tsv has no kit row"
t_eq "…and --check exits 1" "exit 1" "$(code --check --registry "$T/reg")"
regcopy; printf 'ghost.fresh\twarn\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tstandard\t-\t-\ta control family nobody put in the kit\n' >> "$T/reg/controls.tsv"
t_has "a control in a family with no kit row is named" "$(kit --check --registry "$T/reg")" "control family ghost has no kit row"

t_section "a kit row that names nothing, or says nonsense, is red"
regcopy; printf 'register.ghost\tregister\tstandards/naming/nowhere.tsv\t*\tcore\tyes\tx\n' >> "$T/reg/kit.tsv"
t_has "a register that schemas.tsv lacks" "$(kit --check --registry "$T/reg")" "schemas.tsv has no such row"
regcopy; printf 'control.ghost\tcontrol\tghostfam\t*\tcore\tno\tx\n' >> "$T/reg/kit.tsv"
t_has "a control family that controls.tsv lacks" "$(kit --check --registry "$T/reg")" "names the control family ghostfam"
regcopy; printf 'tool.ghost\ttool\tbin/ghost-tool.sh\t*\tcore\tyes\tx\n' >> "$T/reg/kit.tsv"
t_has "a tool that bin/ lacks" "$(kit --check --registry "$T/reg")" "names bin/ghost-tool.sh and the tree has no such file"
regcopy; printf 'pin.ghost\tpin\tnoaxis\t*\tcore\tyes\tx\n' >> "$T/reg/kit.tsv"
t_has "a pin axis versions.tsv lacks" "$(kit --check --registry "$T/reg")" "names the axis noaxis"
regcopy; printf 'check.kind\tcheck\t.agents/c.md\tghostkind\tcore\tno\tx\n' >> "$T/reg/kit.tsv"
t_has "a repo kind repo-kinds.tsv lacks" "$(kit --check --registry "$T/reg")" "names the repo kind ghostkind"
regcopy; printf 'check.share\tcheck\t.agents/d.md\t*\tmoon\tno\tx\n' >> "$T/reg/kit.tsv"
t_has "a share outside core, hub, workload, personal" "$(kit --check --registry "$T/reg")" "share moon"
regcopy; printf 'check.vend\tcheck\t.agents/e.md\t*\tcore\tyes\tx\n' >> "$T/reg/kit.tsv"
t_has "a template or check marked vendored" "$(kit --check --registry "$T/reg")" "yard renders it, so vendored is no"
regcopy; grep -m1 '^register\.' "$T/reg/kit.tsv" >> "$T/reg/kit.tsv"
t_has "an id used twice" "$(kit --check --registry "$T/reg")" "is used twice"

t_section "the lint rule standard.kit-complete reads the same verdict"
. "$T_ROOT/tests/checks/lint-fixture.sh"
M="$T/mini"; mkdir -p "$M/bin" "$M/standards/naming"; cp "$T_ROOT"/bin/*.sh "$M/bin/"; cp "$REG"/*.tsv "$M/standards/naming/"
t_eq "green on the real registers" 0 "$(vcount "$(lint1 standard.kit-complete "$M")")"
t_hasnt "…and prints no advisory" "$(lint1 standard.kit-complete "$M")" "ADVISORY"
printf 'standards/naming/ghost.tsv\trow\tid note\tid\t\tstandard\t-\ta register nobody put in the kit\n' >> "$M/standards/naming/schemas.tsv"
t_has "a register with no kit row is an advisory (born warn)" "$(lint1 standard.kit-complete "$M")" "ADVISORY [standard.kit-complete] register standards/naming/ghost.tsv has no kit row"

t_section "--render hands yard a kind's items"
_w="$(kit --render workload)"; _c="$(kit --render control-plane)"
t_has "a workload gets the justfile template" "$_w" "template.justfile	template	justfile"
t_has "…the check register fragment" "$_w" "check.register	check	.agents/checks.md"
t_has "…and the vendored terms register" "$_w" "register.terms	register	standards/naming/terms.tsv	core	yes"
t_hasnt "the control plane gets no template (it is not scaffolded)" "$_c" "template.justfile"
t_has "…but carries the hub registers" "$_c" "register.contracts-seams"
t_hasnt "a workload carries no hub-only register" "$_w" "register.contracts-layers"
t_eq "an unknown kind is a usage error" "exit 2" "$(code --render nokind)"
for k in $(awk -F'\t' '!/^#/ && NR > 1 { print $1 }' "$REG/repo-kinds.tsv" | grep -v '^id$'); do
  t_eq "every kind in repo-kinds.tsv renders (kind $k lists at least one item)" yes "$([ -n "$(kit --render "$k")" ] && echo yes || echo no)"
done

t_section "--package is what the vendored copy ships, and standard-vendor.sh builds it from the kit"
t_eq "the package equals the vendored manifest's files" "$(grep -v '^#' "$T_ROOT/vendor/naming/MANIFEST.tsv" | cut -f1 | sort | tr '\n' ' ')" "$(kit --package | cut -f1 | sort | tr '\n' ' ')"
regcopy; grep -v '^register.terms	' "$T/reg/kit.tsv" > "$T/reg/kit.new"; mv "$T/reg/kit.new" "$T/reg/kit.tsv"
t_hasnt "a register whose kit row is gone is no longer in the package" "$(kit --package --registry "$T/reg" | cut -f1)" "registry/terms.tsv"

t_section "a fixture repo scaffolded for each kind carries every item its kind lists (--carries)"
mkrepo() { # <dir> <kind>: what yard renders for the kind
  mkdir -p "$1/.agents"; printf 'repo-kind: %s\n' "$2" > "$1/.agents/config.yaml"
  sh "$K" --root "$T_ROOT" --render "$2" | while IFS='	' read -r _i _it _ref _s _v; do
    case "$_it" in template|check) mkdir -p "$1/$(dirname "$_ref")"; [ -e "$1/$_ref" ] || printf '%s\n' "$_i" > "$1/$_ref" ;; esac
  done
  sh "$T_ROOT/bin/standard-vendor.sh" "$1" >/dev/null 2>&1
}
for k in control-plane scaffolder fleet-controller workload data; do
  mkrepo "$T/r-$k" "$k"
  t_eq "$k: --carries is green" "exit 0" "$(sh "$K" --carries "$T/r-$k" >/dev/null 2>&1; echo "exit $?")"
  t_eq "$k: the vendored copy is current with its manifest" "exit 0" "$(sh "$T/r-$k/vendor/naming/standard-vendor.sh" --check --offline "$T/r-$k" >/dev/null 2>&1; echo "exit $?")"
  t_eq "$k: the repo's own vendored kit check is green" "exit 0" "$(sh "$T/r-$k/vendor/naming/standard-kit.sh" --check >/dev/null 2>&1; echo "exit $?")"
done
R="$T/r-workload"
rm "$R/vendor/naming/registry/versions.tsv"
_o="$(sh "$K" --carries "$R" 2>&1)"
t_has "a vendored register removed is named" "$_o" "register.versions lacks vendor/naming/registry/versions.tsv"
t_has "…and the pins that read it" "$_o" "pin.runtime lacks a runtime row"
sh "$T_ROOT/bin/standard-vendor.sh" "$R" >/dev/null 2>&1
rm "$R/justfile"
t_has "a template removed is named" "$(sh "$K" --carries "$R" 2>&1)" "template.justfile lacks justfile"
printf 'x\n' > "$R/justfile"; rm "$R/.agents/checks.md"
t_has "the check register fragment removed is named" "$(sh "$K" --carries "$R" 2>&1)" "check.register lacks .agents/checks.md"
rm "$R/vendor/naming/standard-kit.sh"
t_has "a vendored tool removed is named" "$(sh "$K" --carries "$R" 2>&1)" "tool.standard-kit lacks vendor/naming/standard-kit.sh"
t_eq "…and --carries exits 1" "exit 1" "$(sh "$K" --carries "$R" >/dev/null 2>&1; echo "exit $?")"
mkdir -p "$T/nokind"; t_eq "a repo that declares no kind is unchecked, never green" "exit 3" "$(sh "$K" --carries "$T/nokind" >/dev/null 2>&1; echo "exit $?")"

t_done
