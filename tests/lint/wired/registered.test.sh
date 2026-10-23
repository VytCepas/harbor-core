#!/usr/bin/env sh
# admission.wired-registered: every hook script the box wires is the engine of a controls.tsv row (harbor#1272).
# Each case is a throwaway root with this checkout's bin/ and controls.tsv, so the wired set is the real one.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
W=admission.wired-registered
mk() { # <name> → a root holding bin/ and standards/naming/controls.tsv
  _d="$T_TMP/$1"; mkdir -p "$_d/standards/naming"
  cp -R "$T_ROOT/bin" "$_d/bin"; cp "$T_ROOT/standards/naming/controls.tsv" "$_d/standards/naming/"
  printf '%s' "$_d"
}
drop() { # <root> <engine> → controls.tsv without that engine's rows
  awk -F'\t' -v e="$2" '$4 != e' "$1/standards/naming/controls.tsv" > "$1/c" && mv "$1/c" "$1/standards/naming/controls.tsv"
}

t_section "the repo's own wiring: every wired script has a row"
D="$(mk clean)"
t_eq "the wired set is not empty (control)" yes "$([ "$(sh "$D/bin/decider-set.sh" | grep -c .)" -ge 10 ] && echo yes || echo no)"
t_eq "no advisory" "" "$(advs "$W" "$D")"

t_section "a wired script with no row is named"
D="$(mk planted)"; drop "$D" bin/guard-destroy.sh
t_has "guard-destroy, whose rows are gone" "$(advs "$W" "$D")" "bin/guard-destroy.sh is wired as a hook and no standards/naming/controls.tsv row names it"
t_eq "...and only it" 1 "$(advs "$W" "$D" | grep -c 'ADVISORY')"
drop "$D" bin/event-hook.sh
t_has "a recorder counts too" "$(advs "$W" "$D")" "bin/event-hook.sh"

t_section "a missing input is a violation, never a clean run"
D="$(mk nocontrols)"; rm "$D/standards/naming/controls.tsv"
t_has "no controls.tsv" "$(viol "$W" "$D")" "cannot be checked"

t_done
