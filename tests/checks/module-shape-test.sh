#!/usr/bin/env sh
# module-shape.sh (M11, harbor#379). It mis-measured four times, each caught here and each flattering
# a split, so every case is a control. Hermetic: synthetic codebases in a temp dir, none of the real
# tree. One file on purpose (DOCTRINE/modularity.md): real boundaries nothing outside crosses.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/module-shape.sh"; FX="$T_TMP/fx"; mkdir -p "$FX"
# One value from the JSON form, the contract a caller uses; the human form would test the renderer.
field() { sh "$TOOL" --json "$1" | sed -n "s/.*\"$2\":\([^,}]*\).*/\1/p" | tr -d '"'; }            # <dir> <key>
sfield() { sh "$TOOL" --json --seam "$1" "$2" | sed -n "s/.*\"$3\":\([^,}]*\).*/\1/p" | tr -d '"'; }  # <file> <dir> <key>
holds() { awk "BEGIN{exit !($1)}" && echo yes || echo no; }  # <awk condition>
# distinct lines, so compression cannot collapse them and the null model stays honest
body() { awk -v n="$1" -v o="${2:-0}" 'BEGIN{for(i=0;i<n;i++){k=i+o;
  printf "  _v%d=$(( (%d * 7 + %d) %% %d )); [ \"$_v%d\" -gt %d ] && _acc=$((_acc + _v%d))\n",
  k,k,k*3,k+11,k,k%5,k}}'; }
mk() { mkdir -p "$FX/$1"; }

mk q1; { echo '#!/usr/bin/env sh'; echo 'q1_run() { _acc=0'; body 140
        echo '  printf "%s" "$_acc"; }'; echo 'q1_report() { q1_run; }'; } > "$FX/q1/all.sh"
mk q2; o=0; for m in validate transform enrich score render emit; do
  { echo '#!/usr/bin/env sh'; echo "${m}_do() { _acc=0"; body 60 "$o"
    echo '  printf "%s" "$_acc"; }'; } > "$FX/q2/$m.sh"; o=$((o+60)); done
{ echo '#!/usr/bin/env sh'
  echo 'q2_run() { validate_do; transform_do; enrich_do; score_do; render_do; emit_do; }'; } > "$FX/q2/main.sh"
mk q3; { echo '#!/usr/bin/env sh'; i=0
  while [ "$i" -lt 40 ]; do echo "q3_step$i() { _acc=\$((_acc + $i))"; body 3 $((i*3)); echo '  :; }'; i=$((i+1)); done
  } > "$FX/q3/all.sh"
mk q4; o=0; for m in validate transform enrich score render emit; do
  { echo '#!/usr/bin/env sh'; j=0
    while [ "$j" -lt 8 ]; do echo "${m}_p$j() { _acc=\$((_acc + $j))"; body 2 $((o+j*2)); echo '  :; }'; j=$((j+1)); done
    for x in validate transform enrich score render emit; do [ "$m" = "$x" ] && continue
      echo "${m}_x_$x() { ${x}_p0; ${x}_p1; }"; done
  } > "$FX/q4/$m.sh"; o=$((o+16)); done
mk q5; o=0; for m in alpha beta gamma delta epsilon zeta; do
  { echo '#!/usr/bin/env sh'; echo "${m}_main() { _acc=0"; body 60 "$o"
    echo '  printf "%s" "$_acc"; }'; } > "$FX/q5/$m.sh"; o=$((o+60)); done
mk q6; for m in reporter_a reporter_b; do
  { echo '#!/usr/bin/env sh'; echo "${m}_run() { _acc=0"; body 70
    echo '  printf "%s" "$_acc"; }'; } > "$FX/q6/$m.sh"; done
mk q7; { echo '#!/usr/bin/env sh'; i=0
  while [ "$i" -lt 30 ]; do echo "god_helper$i() { _acc=\$((_acc + $i)); }"; i=$((i+1)); done; } > "$FX/q7/god.sh"
for c in one two three four five six; do
  { echo '#!/usr/bin/env sh'; echo "${c}_main() {"; i=0
    while [ "$i" -lt 10 ]; do echo "  god_helper$i"; i=$((i+1)); done; echo '}'; } > "$FX/q7/$c.sh"; done
mk q8; o=0; for L in data logic view; do
  { echo '#!/usr/bin/env sh'; j=0
    while [ "$j" -lt 12 ]; do echo "${L}_op$j() { _acc=\$((_acc + $j))"; body 2 $((o+j*2)); echo '  :; }'; j=$((j+1)); done
  } > "$FX/q8/$L.sh"; o=$((o+24)); done
{ echo '#!/usr/bin/env sh'; echo 'q8_run() { data_op0; logic_op0; view_op0; }'; } > "$FX/q8/main.sh"
mk q9; { echo '#!/usr/bin/env sh'; echo 'parse_input() { _acc=0'; body 70 0; echo '  :; }'
  echo 'render_chart() { _s=""'
  awk 'BEGIN{for(i=0;i<70;i++) printf "  _s=\"$_s$(printf \047%%s\047 chart_row_%d)\"; _w%d=${#_s}\n", i, i}'
  echo '  :; }'; } > "$FX/q9/all.sh"
mk q10; { echo '#!/usr/bin/env sh'; echo 'storage_put() { backend_put "$@"; }'
  echo 'storage_get() { backend_get "$@"; }'; } > "$FX/q10/storage.sh"
{ echo '#!/usr/bin/env sh'; echo 'backend_put() { _acc=0'; body 45 0; echo '  :; }'
  echo 'backend_get() { _acc=0'; body 45 100; echo '  :; }'; } > "$FX/q10/backend.sh"
{ echo '#!/usr/bin/env sh'; echo 'q10_run() { storage_put x; storage_get x; }'; } > "$FX/q10/main.sh"

t_section "MS-1 · every case lands in the quadrant it was constructed for"
for c in "q1 DEEP+MONO" "q2 DEEP+MICRO" "q3 SHALLOW+MONO" "q4 SHALLOW+MICRO" \
         "q5 DEEP+MICRO" "q6 DEEP+MICRO" "q7 SHALLOW+MICRO" "q8 SHALLOW+MICRO" \
         "q9 DEEP+MONO" "q10 SHALLOW+MICRO"; do
  set -- $c
  t_eq "MS-1 $1 quadrant" "$2" "$(field "$FX/$1" quadrant)"
done

t_section "MS-2 · density separates a mesh from a pipeline; an edge COUNT cannot"
d4=$(field "$FX/q4" density); d2=$(field "$FX/q2" density)
t_eq "MS-2a mesh density $d4 >= 0.40 and pipeline $d2 < 0.10" yes "$(holds "$d4 >= 0.40 && $d2 < 0.10")"
t_eq "MS-2b q4 is a MESH" MESH "$(field "$FX/q4" topology)"
t_eq "MS-2c independent tools are not MESH" yes "$([ "$(field "$FX/q5" topology)" != MESH ] && echo yes || echo no)"
# The god object carries many edges all landing on one file: without these two, replacing density
# with a scaled edge count passes the whole suite.
t_eq "MS-2d a star-shaped god object is not MESH" yes "$([ "$(field "$FX/q7" topology)" != MESH ] && echo yes || echo no)"
t_eq "MS-2e the god object is a HUB" HUB "$(field "$FX/q7" topology)"

t_section "MS-3 · hub share alone cannot tell a god object from a good hub; depth can"
g=$(field "$FX/q7" depth); s=$(field "$FX/q2" depth)
t_eq "MS-3a god-object depth $g < 10 and service depth $s >= 25" yes "$(holds "$g < 10 && $s >= 25")"
h=$(field "$FX/q7" hub)
t_eq "MS-3b the god object's hub share $h >= 0.25" yes "$(holds "$h >= 0.25")"

t_section "MS-4 · duplication is high split cost at LOW density — not a fake seam"
sc=$(field "$FX/q6" split_cost); d6=$(field "$FX/q6" density)
t_eq "MS-4 split cost $sc >= 0.40 at density $d6 < 0.10" yes "$(holds "$sc >= 0.40 && $d6 < 0.10")"

t_section "MS-5 · splitting moves ONE axis"
mkdir -p "$FX/m1"; awk -v d="$FX/m1" '{print > (d "/part" int(NR/22) ".sh")}' "$FX/q1/all.sh"
mkdir -p "$FX/m2"; cat "$FX/q2"/*.sh > "$FX/m2/all.sh"
t_eq "MS-5a splitting a deep module keeps its depth" "$(field "$FX/q1" depth)" "$(field "$FX/m1" depth)"
t_eq "MS-5b merging services keeps their depth" "$(field "$FX/q2" depth)" "$(field "$FX/m2" depth)"
t_eq "MS-5c the split monolith is MICRO" DEEP+MICRO "$(field "$FX/m1" quadrant)"
t_eq "MS-5d the merged services are MONO" DEEP+MONO "$(field "$FX/m2" quadrant)"

t_section "MS-6 · seam mode: q1 and q9 share every shape metric; only the null model parts them"
t_eq "MS-6a q1 and q9 share a quadrant" "$(field "$FX/q1" quadrant)" "$(field "$FX/q9" quadrant)"
t_eq "MS-6b two unrelated subsystems in one file show a real seam" true "$(sfield "$FX/q9/all.sh" "$FX/q9" real)"
t_eq "MS-6c a coherent deep module shows no real seam" false "$(sfield "$FX/q1/all.sh" "$FX/q1" real)"

t_section "MS-7 · a real boundary with no external caller is NOT an earned split"
t_eq "MS-7a a real but PRIVATE boundary is not earned" false "$(sfield "$FX/q9/all.sh" "$FX/q9" earned)"
t_eq "MS-7b a corpus of one file has no external callers" 0 "$(sfield "$FX/q9/all.sh" "$FX/q9" external_callers)"

t_section "MS-8 · the three measurement defects, as regressions"
# D1 a name defined in MANY files is not a shared symbol: two files define `helper`, a third names it.
mkdir -p "$FX/d1"
for f in a b; do printf '#!/usr/bin/env sh\nhelper() { :; }\n' > "$FX/d1/$f.sh"; done
printf '#!/usr/bin/env sh\nc_run() { helper; }\n' > "$FX/d1/c.sh"
t_eq "MS-8/D1 a colliding name produces no edge" 0.000 "$(field "$FX/d1" density)"
# D2 a name under three characters is dropped even at command position, where the fixture puts it
# so the mutation removing the filter goes red; the control is one character longer.
mkdir -p "$FX/d2" "$FX/d2b"
printf '#!/usr/bin/env sh\nn() { :; }\n' > "$FX/d2/owner.sh"
printf '#!/usr/bin/env sh\nuser_run() { n; }\n' > "$FX/d2/user.sh"
printf '#!/usr/bin/env sh\nnow() { :; }\n' > "$FX/d2b/owner.sh"
printf '#!/usr/bin/env sh\nuser_run() { now; }\n' > "$FX/d2b/user.sh"
t_eq "MS-8/D2 a one-letter symbol at command position produces no edge" 0.000 "$(field "$FX/d2" density)"
t_eq "MS-8/D2 the three-character control finds an edge" yes "$(holds "$(field "$FX/d2b" density) > 0")"
# D3 a mention is not a call: the word must stand at command position.
mkdir -p "$FX/d3" "$FX/d3b"
printf '#!/usr/bin/env sh\nrender_table() { :; }\n' > "$FX/d3/owner.sh"
printf '#!/usr/bin/env sh\nuser_run() { echo "see render_table for details"; }\n' > "$FX/d3/user.sh"
cp "$FX/d3/owner.sh" "$FX/d3b/owner.sh"
printf '#!/usr/bin/env sh\nuser_run() { render_table; }\n' > "$FX/d3b/user.sh"
t_eq "MS-8/D3 a symbol named inside a string is not a call" 0.000 "$(field "$FX/d3" density)"
t_eq "MS-8/D3 the same symbol at command position is seen" yes "$(holds "$(field "$FX/d3b" density) > 0")"

t_section "MS-9 · usage contract"
t_exit "MS-9a --help" 0 sh "$TOOL" --help
t_exit "MS-9b no arguments" 2 sh "$TOOL"
t_exit "MS-9c an unknown flag" 2 sh "$TOOL" --nonsense "$FX/q1"
t_exit "MS-9d a missing path" 2 sh "$TOOL" "$FX/nope"
t_done
