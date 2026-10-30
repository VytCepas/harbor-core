#!/usr/bin/env sh
# bin/scope-roots.sh --access: the one resolver of the access register, a private-layer directory (harbor#1149); and --inject/--projects, the same shape for the private rule packs.
# Each case builds a throwaway layer; stdout and stderr are captured apart, because stdout must hold the path or nothing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
RS() { sh "$T_ROOT/bin/scope-roots.sh" --access 2>"$T_TMP/err"; }   # → stdout; stderr in $T_TMP/err
rc() { sh "$T_ROOT/bin/scope-roots.sh" --access >/dev/null 2>&1; echo $?; }

t_section "a private layer with access/ answers its path"
PV="$T_TMP/pv"; mkdir -p "$PV/access"; export HARBOR_SCOPE_PRIVATE="$PV"
t_eq "prints <private>/access" "$PV/access" "$(RS)"
t_eq "...and exits 0" "0" "$(rc)"
export HARBOR_SCOPE_PRIVATE="$PV/"
t_eq "a trailing slash on the layer is dropped" "$PV/access" "$(RS)"
unset HARBOR_SCOPE_PRIVATE; export PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT/harbor-private/access"
t_eq "with no override the layer is PORT_ROOT/harbor-private" "$PORT_ROOT/harbor-private/access" "$(RS)"
t_has "--private agrees on the layer" "$(sh "$T_ROOT/bin/scope-roots.sh" --private)" "$PORT_ROOT/harbor-private"

t_section "ACCESS_DIR wins, as every override does"
mkdir -p "$T_TMP/elsewhere"; export HARBOR_SCOPE_PRIVATE="$PV" ACCESS_DIR="$T_TMP/elsewhere/"
t_eq "the override is the answer, slash dropped" "$T_TMP/elsewhere" "$(RS)"
export ACCESS_DIR="$T_TMP/not-a-dir"
t_eq "an override that is not a directory is not a register: exit 1" "1" "$(rc)"
t_eq "...with nothing on stdout" "" "$(RS)"
t_has "...and the reason on stderr" "$(cat "$T_TMP/err")" "ACCESS_DIR is $T_TMP/not-a-dir, which is not a directory"
unset ACCESS_DIR

t_section "no register is exit 1, empty stdout, a reason: never a path to read"
export HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer"
t_eq "no private layer: exit 1" "1" "$(rc)"
t_eq "...stdout empty" "" "$(RS)"
t_has "...and says there is no private layer" "$(cat "$T_TMP/err")" "no private layer at $T_TMP/no-layer, so there is no access register"
mkdir -p "$T_TMP/bare"; export HARBOR_SCOPE_PRIVATE="$T_TMP/bare"
t_eq "a layer without access/: exit 1" "1" "$(rc)"
t_eq "...stdout empty" "" "$(RS)"
t_has "...and names the missing directory" "$(cat "$T_TMP/err")" "has no access/ directory"
touch "$T_TMP/bare/access"
t_eq "access as a FILE is not a register" "1" "$(rc)"
t_eq "a control character in PORT_ROOT is refused: exit 2" "2" "$(HARBOR_SCOPE_PRIVATE= PORT_ROOT="$(printf 'a\tb')" rc)"

t_section "--inject and --projects: the private rule packs and the project registry (harbor#1149)"
RI() { sh "$T_ROOT/bin/scope-roots.sh" --inject 2>"$T_TMP/err"; }
RJ() { sh "$T_ROOT/bin/scope-roots.sh" --projects 2>"$T_TMP/err"; }
ric() { sh "$T_ROOT/bin/scope-roots.sh" --inject >/dev/null 2>&1; echo $?; }
rjc() { sh "$T_ROOT/bin/scope-roots.sh" --projects >/dev/null 2>&1; echo $?; }
PI="$T_TMP/pi"; mkdir -p "$PI/inject.d/box"; export HARBOR_SCOPE_PRIVATE="$PI"
t_eq "--inject prints <private>/inject.d" "$PI/inject.d" "$(RI)"
t_eq "...and exits 0" "0" "$(ric)"
t_eq "--projects with inject.d/ and no registry: exit 1" "1" "$(rjc)"
t_eq "...stdout empty" "" "$(RJ)"
t_has "...and the missing file is named" "$(cat "$T_TMP/err")" "no project registry at $PI/inject.d/box/projects.tsv"
printf '# name\tpath\tcovers\nx\t~/x\ta fixture\n' > "$PI/inject.d/box/projects.tsv"
t_eq "--projects prints the registry's path once it exists" "$PI/inject.d/box/projects.tsv" "$(RJ)"
export HARBOR_SCOPE_PRIVATE="$PI/"
t_eq "a trailing slash on the layer is dropped" "$PI/inject.d" "$(RI)"
export HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer"
t_eq "no private layer: --inject exit 1" "1" "$(ric)"
t_eq "...stdout empty" "" "$(RI)"
t_has "...and says there are no private rule packs" "$(cat "$T_TMP/err")" "no private layer at $T_TMP/no-layer, so there are no private rule packs"
t_eq "no private layer: --projects exit 1, stdout empty" "1 " "$(rjc) $(RJ)"
mkdir -p "$T_TMP/bare-inj"; export HARBOR_SCOPE_PRIVATE="$T_TMP/bare-inj"
t_eq "a layer without context-rules/ or inject.d/: --inject exit 1" "1" "$(ric)"
t_has "...naming the missing directory" "$(RI >/dev/null; cat "$T_TMP/err")" "has no context-rules/ or inject.d/ directory"
t_eq "...and --projects agrees" "1" "$(rjc)"
t_section "harbor#1010: the new layout, context-rules/{user,<repo>}/, wins over the old inject.d/"
PN="$T_TMP/pn"; mkdir -p "$PN/inject.d/box" "$PN/context-rules/user"; export HARBOR_SCOPE_PRIVATE="$PN"
printf 'old\t~/o\told\n' > "$PN/inject.d/box/projects.tsv"
t_eq "--inject prints <private>/context-rules when it exists" "$PN/context-rules" "$(RI)"
t_eq "--projects with context-rules/ and no registry: exit 1, the old registry is not borrowed" "1" "$(rjc)"
printf 'new\t~/n\tnew\n' > "$PN/context-rules/user/projects.tsv"
t_eq "--projects prints context-rules/user/projects.tsv" "$PN/context-rules/user/projects.tsv" "$(RJ)"
t_eq "a control character in PORT_ROOT is refused by both: exit 2" "2 2" "$(HARBOR_SCOPE_PRIVATE= PORT_ROOT="$(printf 'a\tb')" ric) $(HARBOR_SCOPE_PRIVATE= PORT_ROOT="$(printf 'a\tb')" rjc)"

t_section "the floor never reads the private layer"
for _f in "$T_ROOT"/bin/admission-*.sh "$T_ROOT"/bin/library-admission.sh "$T_ROOT"/bin/floor-*.sh "$T_ROOT"/bin/floor-normalize.awk; do
  t_eq "$(basename "$_f") does not name the register or the layer" "" \
    "$(/usr/bin/grep -nE -e '--access|harbor-private|HARBOR_SCOPE_PRIVATE|ACCESS_DIR|repos\.tsv' "$_f")"
done
t_done
