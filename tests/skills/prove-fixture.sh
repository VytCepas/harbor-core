# tests/skills/prove-fixture.sh — what the prove suites share (R5, contracts/gates.md). Source after
# t_init. The fixtures are built at run time and are never the engine's own: two implementations
# sharing a fixture can drift into agreement (spec §9/§10). _prove sets RC, O (stdout) and $ERR.
ENGINE="$T_ROOT/skills/test-strength/bin/prove.sh"
[ -f "$ENGINE" ] || { echo "$T_NAME: no engine at $ENGINE" >&2; exit 1; }
for _dep in jq cmp shasum; do
  command -v "$_dep" >/dev/null 2>&1 || { echo "$T_NAME: $_dep is required" >&2; exit 1; }
done
T="$T_TMP/p"; OUT="$T/out"; ERR="$T/err"; RC=0; O=""
mkdir -p "$T/work"
# HR is HARBOR_ROOT as the engine sees it, PTH its PATH: only the tripwire and hasher arms move them.
_defaults() { PT="$T/targets"; BUD=900; EXT=1; WRK="$T/work"; CNT=/dev/null; HR="$T_ROOT"; PTH="$PATH"; }
_defaults
_run_engine() { # <engine> <args…> — a VAR=x prefix on a function call persists under /bin/sh
  _eng=$1; shift; RC=0
  env PATH="$PTH" HARBOR_ROOT="$HR" PROVE_TARGETS="$PT" PROVE_WORK="$WRK" PROVE_BUDGET="$BUD" \
    PROVE_ALLOW_EXTERNAL="$EXT" PROVE_TEST_COUNT="$CNT" sh "$_eng" "$@" >"$OUT" 2>"$ERR" || RC=$?
  O="$(cat "$OUT")"; _defaults
}
_prove() { _run_engine "$ENGINE" "$@"; }
rc() { t_eq "$2" "exit $1" "exit $RC"; }  # <want> <label>
re() { [ -s "$OUT" ] || { echo empty; return; }; /usr/bin/grep -qE -- "$1" "$OUT" && echo yes || echo no; }  # <ERE>
genfield() { # <label> — the number before a label on the GENERATED line, e.g. the 0 in `0 inert`
  awk -v lab="$1" '/^  GENERATED/ { for (i = 1; i <= NF; i++) if ($i == lab) { print $(i-1); exit } }' "$OUT"
}
# demo (spec §10): SEC has two sites, both killed; DATE survives; ANCH has no site; HDR-1 and the
# canary are killed. runs = 1 + 1 + 1 + 4 = 7, counted from outside via PROVE_TEST_COUNT.
mkdir -p "$T/targets/demo" "$T/targets/clean" "$T/targets/odd"
cat > "$T/targets/demo/seed.md" <<'SEED'
# DEMO

## Alpha
| hop | owner | verified |
|---|---|---|
| one | org | 2026-01-01 |

## Beta
Body text.
SEED
cat > "$T/targets/demo/check.sh" <<'CHK'
#!/usr/bin/env sh
set -u
printf 'x\n' >> "${PROVE_TEST_COUNT:-/dev/null}"
/usr/bin/grep -q '^## Alpha$' "$1" || exit 1
/usr/bin/grep -q '^## Beta$' "$1" || exit 1
exit 0
CHK
# The over-broad rule: the same greps plus the seed row. It kills every mutant and refuses the control.
cat > "$T/targets/demo/overbroad-check.sh" <<'CHK'
#!/usr/bin/env sh
set -u
/usr/bin/grep -q '^## Alpha$' "$1" || exit 1
/usr/bin/grep -q '^## Beta$' "$1" || exit 1
/usr/bin/grep -qF '| one | org | 2026-01-01 |' "$1" || exit 1
exit 0
CHK
cat > "$T/targets/demo/control-odd.md" <<'CTL'
# DEMO

## Alpha
Ordinary prose, no table at all — a lawful shape.
A hop cell literally named `ORG \| PANDORA SHOPIFY \| LT`, and a Lithuanian ž.

## Beta
Body text.
CTL
cat > "$T/targets/demo.target" <<'TGT'
# demo — the shared self-test fixture (spec §10).
target        demo
subject-kind  markdown-contract
lane          fast
cost          1
seed          demo/seed.md
place         $WORK/doc.md
checker-cmd   sh $TDIR/demo/check.sh $WORK/doc.md
green         0
red           1

mutate  SEC   section-delete
mutate  DATE  date-shift +400d
mutate  ANCH  anchor-break

plant   HDR-1  sed -e 's/^## Beta$/**Beta**/' "$SEED" > "$MUTANT"
        why:   a heading demoted to bold keeps every token and loses the structure the contract is about

manual  WORLD-1  the doc names a vendor whose contract ended; no textual mutation says that

control C-ODD  file demo/control-odd.md
        varies: lexical
        why:    a lawful section with an escaped pipe and a diacritic and no table at all

scanner prove-absent-scanner prove-absent-scanner --scan $WORK/doc.md
TGT
cat > "$T/targets/overbroad.target" <<'TGT'
target        overbroad
subject-kind  markdown-contract
lane          fast
cost          1
seed          demo/seed.md
place         $WORK/doc.md
checker-cmd   sh $TDIR/demo/overbroad-check.sh $WORK/doc.md
green         0
red           1

mutate  SEC   section-delete
mutate  DATE  date-shift +400d
mutate  ANCH  anchor-break

plant   HDR-1  sed -e 's/^## Beta$/**Beta**/' "$SEED" > "$MUTANT"
        why:   a heading demoted to bold keeps every token and loses the structure

manual  WORLD-1  the doc names a vendor whose contract ended; no textual mutation says that

control C-ODD  file demo/control-odd.md
        varies: lexical
        why:    a lawful section with an escaped pipe and a diacritic and no table at all
TGT
# The null checker: it cannot fail, and the canary is what turns that into a refusal.
printf '#!/usr/bin/env sh\nexit 0\n' > "$T/targets/always-green.sh"
cat > "$T/targets/always-green.target" <<'TGT'
target        always-green
subject-kind  markdown-contract
lane          fast
cost          1
seed          demo/seed.md
place         $WORK/doc.md
checker-cmd   sh $TDIR/always-green.sh
green         0
red           1

mutate  SEC   section-delete

plant   HDR-1  sed -e 's/^## Beta$/**Beta**/' "$SEED" > "$MUTANT"
        why:   a heading demoted to bold keeps every token and loses the structure

control C-ODD  file demo/control-odd.md
        varies: lexical
        why:    a lawful section with no table at all
TGT
# clean is demo without the survivor: the PROVEN side of every survivor threshold.
cp "$T/targets/demo/seed.md" "$T/targets/clean/seed.md"
cat > "$T/targets/clean.target" <<'TGT'
target        clean
subject-kind  markdown-contract
lane          fast
cost          1
seed          clean/seed.md
place         $WORK/doc.md
checker-cmd   sh $TDIR/demo/check.sh $WORK/doc.md
green         0
red           1

mutate  SEC   section-delete
mutate  ANCH  anchor-break

plant   HDR-1  sed -e 's/^## Beta$/**Beta**/' "$SEED" > "$MUTANT"
        why:   a heading demoted to bold keeps every token and loses the structure

control C-ODD  file demo/control-odd.md
        varies: lexical
        why:    a lawful section with an escaped pipe and a diacritic and no table at all

scanner prove-absent-scanner prove-absent-scanner --scan $WORK/doc.md
TGT
# odd: lawful, and shaped like nothing else in the set (comments, blank lines, sites:, non-ASCII).
cat > "$T/targets/odd/seed.md" <<'SEED'
# ODD

## Alpha
Teisėta bet neįprasta forma — a hop cell named `ORG \| PANDORA` and no table.

## Beta
Body text.
SEED
cat > "$T/targets/odd/control.md" <<'CTL'
# ODD

## Alpha
Kita teisėta forma: a 48-character label against a 48-character cap.

## Beta
Body text.
CTL
cat > "$T/targets/odd.target" <<'TGT'
#
# odd — a lawful declaration wearing an unusual shape.

target        odd
subject-kind  markdown-contract

# a comment sitting between two header directives

lane          fast
cost          1
seed          odd/seed.md
place         $WORK/doc.md
checker-cmd   sh $TDIR/demo/check.sh $WORK/doc.md
green         0
red           1

mutate  SEC   section-delete
        sites: 8

mutate  ANCH  anchor-break

plant   HDR-1  sed -e 's/^## Beta$/**Beta**/' "$SEED" > "$MUTANT"
        why:   antraštė paversta paryškinimu — every token kept, all structure gone

manual  WORLD-1  pasaulio žinios: no textual mutation of the file can express this

control C-ODD  file odd/control.md
        varies: leksinė
        why:    teisėta forma — an escaped pipe `A \| B`, a diacritic, and no table at all
TGT
# shell: the posix-shell kind. shreal names a real control; shcomment one that rewords a comment only.
# The checker bounds the ceiling on both sides (10 accepted, 11 refused), so comparison-flip is visible.
mkdir -p "$T/shell"
cat > "$T/shell/seed.sh" <<'SEED'
#!/usr/bin/env sh
# guard.sh — refuses a file over the ten-line ceiling
set -u
_n=$(wc -l < "$1")
if [ "$_n" -gt 10 ]; then
  echo "too long"
  exit 1
fi
exit 0
SEED
sed 's|over the ten-line ceiling|over the ceiling (reworded comment, identical code)|' \
  "$T/shell/seed.sh" > "$T/shell/control-comment.sh"
cat > "$T/shell/control-real.sh" <<'CTL'
#!/usr/bin/env sh
# guard.sh — refuses a file over the ten-line ceiling
set -u
_n=$(awk 'END{print NR}' "$1")
[ "$_n" -gt 10 ] && { echo "too long"; exit 1; }
exit 0
CTL
cat > "$T/shell/check.sh" <<'CHK'
#!/usr/bin/env sh
set -u
_mk() { _i=0; : > "$2"; while [ "$_i" -lt "$1" ]; do printf 'x\n' >> "$2"; _i=$((_i + 1)); done; }
_mk 1  "$2/n1.txt"; _mk 10 "$2/n10.txt"; _mk 11 "$2/n11.txt"
sh "$1" "$2/n1.txt"  >/dev/null 2>&1 || exit 1
sh "$1" "$2/n10.txt" >/dev/null 2>&1 || exit 1
sh "$1" "$2/n11.txt" >/dev/null 2>&1 && exit 1
exit 0
CHK
_shtgt() {  # _shtgt <slug> <control-file>
  printf 'target        %s\n' "$1"
  printf 'subject-kind  posix-shell\nlane          fast\ncost          1\n'
  printf 'seed          seed.sh\nplace         $WORK/guard.sh\n'
  printf 'checker-cmd   sh $TDIR/check.sh $WORK/guard.sh $WORK\ngreen         0\nred           1\n'
  printf '\nmutate  CMP   comparison-flip\nmutate  EXIT  exit-neuter\n'
  printf '\ncontrol C-1   file %s\n' "$2"
  printf '        varies: shape\n'
  printf '        why:    the same ten-line ceiling, reached by a different route\n'
}
_shtgt shreal    control-real.sh    > "$T/shell/shreal.target"
_shtgt shcomment control-comment.sh > "$T/shell/shcomment.target"
# The shared BASE: a three-section subject, a lawful control and a section-counting checker. _base
# prints a valid declaration; every P2 arm is that base plus exactly one defect.
_mk3() {  # _mk3 <dir>
  mkdir -p "$1"
  cat > "$1/seed.md" <<'SEED'
# BASE

## Alpha
Alpha body.

## Beta
Beta body.

## Gamma
Gamma body.
SEED
  cat > "$1/control.md" <<'CTL'
# BASE

## Alpha
Kitokia teisėta proza po tomis pačiomis antraštėmis.

## Beta
Different but lawful body, under the same three headings.

## Gamma
Still lawful.
CTL
  cat > "$1/check.sh" <<'CHK'
#!/usr/bin/env sh
set -u
_n=$(/usr/bin/grep -c '^## ' "$1" || true)
[ "${_n:-0}" = "3" ] || exit 1
exit 0
CHK
}
_base() {  # _base <slug> [one-extra-header-line]
  printf 'target        %s\n' "$1"
  printf 'subject-kind  markdown-contract\n'
  printf 'lane          fast\n'
  printf 'cost          1\n'
  printf 'seed          seed.md\n'
  printf 'place         $WORK/doc.md\n'
  printf 'checker-cmd   sh $TDIR/check.sh $WORK/doc.md\n'
  printf 'green         0\n'
  printf 'red           1\n'
  if [ -n "${2:-}" ]; then printf '%s\n' "$2"; fi
  printf '\nmutate  SEC   section-delete\n\n'
  printf 'control C-1   file control.md\n'
  printf '        varies: shape\n'
  printf '        why:    a lawful map with different prose under the same three headings\n'
}
# A single quote cannot sit inside a single-quoted string, so plant recipes use %s for it.
Q="'"
_mk_case() {  # _mk_case <group> <slug>  — .target body on stdin; echoes the dir
  _d="$T/$1/$2"; rm -rf "$_d"; mkdir -p "$_d"; _mk3 "$_d"
  cat > "$_d/$2.target"
  printf '%s' "$_d"
}
# P2's one-defect cases, which the engine and read-only parts drive too.
mk_nocontrol() { _base nocontrol | sed '/^control /,$d' | _mk_case bad nocontrol; }
mk_noop() {
  { _base noop
    printf '\nplant   NOOP-1  sed -e %ss/NOTHING-MATCHES-HERE/x/%s "$SEED" > "$MUTANT"\n' "$Q" "$Q"
    printf '        why:    a recipe whose pattern is absent from the seed\n'
  } | _mk_case bad noop
}
mk_baselinered() {
  _bd="$(_base baselinered | _mk_case bad baselinered)"
  printf '#!/usr/bin/env sh\nexit 1\n' > "$_bd/check.sh"; printf '%s' "$_bd"
}
mk_exit9() { # the canary stays killable (empty file → red), so exit 4 is about the odd exit code
  _bd="$(_base exit9 | _mk_case bad exit9)"
  cat > "$_bd/check.sh" <<'CHK'
#!/usr/bin/env sh
set -u
_n=$(/usr/bin/grep -c '^## ' "$1" || true)
if [ "${_n:-0}" = "3" ]; then exit 0; fi
if [ ! -s "$1" ]; then exit 1; fi
exit 9
CHK
  printf '%s' "$_bd"
}
mk_cmdok() { # a cmd control ADDED beside the file control: the floor target declares only cmd controls
  _base cmdok | { cat; printf 'control C-2   cmd sh $TDIR/check.sh $SUBJECT\n        varies: form — a command rather than a file\n        why:    the floor target declares only cmd controls; refusing the form outright would make it undeclarable\n'; } \
    | _mk_case ok cmdok
}
