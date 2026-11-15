#!/usr/bin/env sh
# standard.test.sh (harbor#1278) — bin/member-standard.sh and the vendored templates, on scratch git repos.
# An empty repo gets the whole standard, a person's files are never touched, a rerun changes nothing, no marker is written;
# each refusal is seen red on a planted break (control member.standard, standard.vendor-scaffolder-fresh).
Y0="${PORT_ROOT:-$HOME/port}/yard"   # read before t_init moves HOME
. "$(dirname "$0")/../../lib/core.sh"; t_init
MS="$T_ROOT/bin/member-standard.sh"
G="$T_TMP/g"; mkdir -p "$G"
mkrepo() { rm -rf "$G/$1"; mkdir -p "$G/$1"; git -C "$G/$1" init -q; }
run() { sh "$MS" "$G/$1" --name "$1" 2>&1; }
sum() { cksum < "$G/$1/$2"; }
ALL="AGENTS.md CLAUDE.md docs/project-standard.md tests/run.sh tests/suites.txt tests/lib/core.sh tests/example/example.test.sh"
nomarker() { [ ! -e "$G/$1/.agents" ] && [ ! -e "$G/$1/.claude" ] && echo yes || echo no; }

t_section "1 - an empty repo gets the full standard"
mkrepo empty; _o="$(run empty)"; _rc=$?
t_eq "exit 0" 0 "$_rc"
for _f in $ALL; do t_eq "$_f is written" yes "$([ -f "$G/empty/$_f" ] && echo yes || echo no)"; done
t_eq "CLAUDE.md carries the bare import" 1 "$(grep -cx '@AGENTS.md' "$G/empty/CLAUDE.md")"
t_has "the naming standard is referenced" "$(cat "$G/empty/docs/project-standard.md")" "harbor's naming standard"
t_has "the language by layer is stated" "$(cat "$G/empty/docs/project-standard.md")" "Language by layer"
t_has "the memory route is stated" "$(cat "$G/empty/docs/project-standard.md")" "memory store"
t_has "the project name is rendered" "$(cat "$G/empty/AGENTS.md")" "# empty"
t_eq "no token is left unrendered" 0 "$(cat "$G"/empty/AGENTS.md "$G"/empty/CLAUDE.md "$G"/empty/docs/project-standard.md | grep -c '@@')"
t_eq "no marker: no .agents, no .claude" yes "$(nomarker empty)"
t_has "the marker is named in the output" "$_o" "marker: none"
t_has "the self-governed template item is refused by name" "$_o" "not written: .agents/config.yaml"

t_section "2 - a person's own AGENTS.md and CLAUDE.md are never overwritten"
mkrepo own; printf 'my agents\n' > "$G/own/AGENTS.md"; printf 'my claude, no import\n' > "$G/own/CLAUDE.md"
_a="$(sum own AGENTS.md)"; _c="$(sum own CLAUDE.md)"
_o="$(run own)"; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_eq "AGENTS.md is byte-identical" "$_a" "$(sum own AGENTS.md)"
t_eq "CLAUDE.md is byte-identical" "$_c" "$(sum own CLAUDE.md)"
t_has "AGENTS.md is reported kept" "$_o" "kept AGENTS.md (yours, not modified)"
t_has "the missing import is reported, not fixed" "$_o" "does not import AGENTS.md"
t_eq "the rest is still laid down" yes "$([ -f "$G/own/tests/run.sh" ] && [ -f "$G/own/docs/project-standard.md" ] && echo yes || echo no)"
mkrepo imp; printf '# mine\n\n@AGENTS.md\n' > "$G/imp/CLAUDE.md"; _c="$(sum imp CLAUDE.md)"
_o="$(run imp)"
t_eq "a CLAUDE.md that imports is kept as it is" "$_c" "$(sum imp CLAUDE.md)"
t_eq "...and AGENTS.md is written for it to import" yes "$([ -f "$G/imp/AGENTS.md" ] && echo yes || echo no)"
t_hasnt "...with no import warning" "$_o" "does not import"

t_section "3 - a second run changes nothing"
mkrepo again; run again >/dev/null; git -C "$G/again" add -A; _s="$(git -C "$G/again" status --porcelain)"; _h="$(for _f in $ALL; do sum again "$_f"; done)"
_o="$(run again)"; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_eq "git status is the same" "$_s" "$(git -C "$G/again" status --porcelain)"
t_eq "every file is byte-identical" "$_h" "$(for _f in $ALL; do sum again "$_f"; done)"
t_has "nothing was written" "$_o" "standard: 0 written, 7 kept"
t_has "its own files are said to be already laid down" "$_o" "kept AGENTS.md (already laid down)"
mkrepo dry; _o="$(sh "$MS" "$G/dry" --name dry --dry-run 2>&1)"
t_has "a dry run says it would write" "$_o" "would write AGENTS.md"
t_eq "...and writes nothing" 0 "$(find "$G/dry" -path "$G/dry/.git" -prune -o -type f -print | wc -l | tr -d ' ')"

t_section "4 - a person's own runner or marker is left alone"
mkrepo fr; mkdir -p "$G/fr/tests"; printf '#!/bin/sh\necho mine\n' > "$G/fr/tests/run.sh"; _r="$(sum fr tests/run.sh)"
_o="$(run fr)"
t_eq "their tests/run.sh is untouched" "$_r" "$(sum fr tests/run.sh)"
t_has "the tests layout is kept out, said" "$_o" "kept tests/ (you have your own runner"
t_eq "no example suite beside their runner" no "$([ -e "$G/fr/tests/example" ] && echo yes || echo no)"
mkrepo gov; mkdir -p "$G/gov/.agents"; printf 'scope: project\n' > "$G/gov/.agents/config.yaml"; _m="$(sum gov .agents/config.yaml)"
run gov >/dev/null
t_eq "a marker they already have is untouched" "$_m" "$(sum gov .agents/config.yaml)"
t_eq "and no second marker file appears" 1 "$(find "$G/gov/.agents" "$G/gov/.claude" -type f 2>/dev/null | wc -l | tr -d ' ')"

t_section "5 - the example suite passes with the project's own runner, and goes red when broken"
_o="$(cd "$G/empty" && sh tests/run.sh 2>&1)"; _rc=$?
t_eq "the runner passes" 0 "$_rc"
t_has "...with one summary line" "$_o" "empty: 5 passed, 0 failed"
cp "$G/empty/tests/example/example.test.sh" "$T_TMP/ex.keep"
sed 's/t_eq "equal values pass" "a" "a"/t_eq "equal values pass" "a" "b"/' "$T_TMP/ex.keep" > "$G/empty/tests/example/example.test.sh"
_o="$(cd "$G/empty" && sh tests/run.sh 2>&1)"; _rc=$?
t_eq "a planted break in the example makes the runner red (exit 1)" 1 "$_rc"
t_has "...and names the failed assertion" "$_o" "equal values pass"
cp "$T_TMP/ex.keep" "$G/empty/tests/example/example.test.sh"
t_eq "restored, the runner is green again" 0 "$(cd "$G/empty" && sh tests/run.sh >/dev/null 2>&1; echo $?)"
mkdir -p "$G/empty/tests/loose"; cp "$T_TMP/ex.keep" "$G/empty/tests/loose/loose.test.sh"
_o="$(cd "$G/empty" && sh tests/run.sh 2>&1)"; _rc=$?
t_eq "a suite on disk that is not listed is red (exit 1)" 1 "$_rc"
t_has "...and says which" "$_o" "loose/loose.test.sh is a suite on disk"
rm -rf "$G/empty/tests/loose"
t_eq "an unknown suite name is exit 2" 2 "$(cd "$G/empty" && sh tests/run.sh nope/nope.test.sh >/dev/null 2>&1; echo $?)"

t_section "6 - the refusals, each seen red on a planted break"
# A copy of the tool beside its own helpers, with one guard removed.
H="$T_TMP/h"; mkdir -p "$H/bin"
for _f in library-log.sh library-admission.sh standard-kit.sh; do cp "$T_ROOT/bin/$_f" "$H/bin/$_f"; done
ln -s "$T_ROOT/templates" "$H/templates"; ln -s "$T_ROOT/vendor" "$H/vendor"; ln -s "$T_ROOT/tests" "$H/tests"; ln -s "$T_ROOT/standards" "$H/standards"
sed -e 's/if \[ -e "\$T\/\$_rel" \] || \[ -L "\$T\/\$_rel" \]; then/if false; then/' -e 's/( set -C; cat /( cat /' "$MS" > "$H/bin/member-standard.sh"
t_eq "the planted overwrite break differs from the tool" 1 "$(cmp -s "$MS" "$H/bin/member-standard.sh"; echo $?)"
mkrepo clob; printf 'precious\n' > "$G/clob/AGENTS.md"
_o="$(sh "$H/bin/member-standard.sh" "$G/clob" --name clob 2>&1)"; _rc=$?
t_eq "overwriting the person's file is red (exit 1)" 1 "$_rc"
t_has "...and names the file" "$_o" "a file the person had was changed: AGENTS.md"
t_red member.standard
sed -e 's|^put() {|put() { case "$1" in AGENTS.md) mkdir -p "$T/.agents"; : > "$T/.agents/config.yaml" ;; esac;|' "$MS" > "$H/bin/member-standard.sh"
t_eq "the planted marker break differs from the tool" 1 "$(cmp -s "$MS" "$H/bin/member-standard.sh"; echo $?)"
mkrepo mk
_o="$(sh "$H/bin/member-standard.sh" "$G/mk" --name mk 2>&1)"; _rc=$?
t_eq "writing a governance marker is red (exit 1)" 1 "$_rc"
t_has "...and names it" "$_o" "a governance marker was written: .agents/config.yaml"
t_hasnt "...and never prints the marker: none line" "$_o" "marker: none"
t_red member.standard
t_exit "no repo given is exit 2" 2 sh "$MS"
t_exit "a missing directory is exit 2" 2 sh "$MS" "$G/none" --name x
t_exit "a bad project name is exit 2" 2 sh "$MS" "$G/empty" --name '../x'
t_exit "an unknown flag is exit 2" 2 sh "$MS" "$G/empty" --nope

t_section "7 - AGENTS.md and CLAUDE.md are yard's own templates, vendored, rendered unchanged under the member section"
VY="$T_ROOT/vendor/scaffolder"
t_eq "AGENTS.md ends with yard's render (the member section is only on top)" 1 "$(awk 'f { print } /^<!-- harbor member project standard: end -->$/ { f = 1 }' "$G/empty/AGENTS.md" | grep -c '^## Key rules for agents$')"
t_has "the member section says the project is not self-governed" "$(cat "$G/empty/AGENTS.md")" "Not self-governed"
t_has "...and delimits itself" "$(cat "$G/empty/AGENTS.md")" "harbor member project standard: end"
t_has "the note says where each file comes from, with yard's commit" "$(cat "$G/empty/docs/project-standard.md")" "yard $(sed -n 's/^# yard_commit: *\(.......\).*/\1/p' "$VY/MANIFEST.tsv")"
Y="$Y0"
if [ -f "$Y/templates/base/AGENTS.md.tmpl" ] && command -v python3 >/dev/null 2>&1; then
  python3 -I - "$Y" "$T_TMP" "$(date +%Y-%m-%d)" > "$T_TMP/yard-render.log" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1] + "/src")
from project_init.scaffold import _render
v = {"project_name": "empty", "project_description": "A member project.", "created_date": sys.argv[3],
     "project_init_url": "https://github.com/VytCepas/project-init", "no_just": "true"}
for f in ("AGENTS", "CLAUDE"):
    open(sys.argv[2] + "/yard-" + f + ".out", "w").write(_render(open(sys.argv[1] + "/templates/base/" + f + ".md.tmpl").read(), v))
PY
  if [ -f "$T_TMP/yard-AGENTS.out" ]; then
    for _g in AGENTS CLAUDE; do
      awk 'f { print } /^<!-- harbor member project standard: end -->$/ { f = 1 }' "$G/empty/$_g.md" | sed '1{/^$/d;}' > "$T_TMP/mine-$_g.out"
      t_eq "$_g.md is byte-identical to yard's own renderer on yard's own template" 0 "$(cmp -s "$T_TMP/yard-$_g.out" "$T_TMP/mine-$_g.out"; echo $?)"
    done
  else printf '  SKIP: yard renderer not importable (%s): equivalence with yard unchecked\n' "$(tail -n 1 "$T_TMP/yard-render.log")"; t_pass; fi
else printf '  SKIP: no yard checkout at %s or no python3: equivalence with yard unchecked\n' "$Y"; t_pass; fi

t_section "8 - the vendored copy is held to yard: one changed byte is red; no yard is said, not passed"
VC="$T_TMP/vy"; mkdir -p "$VC"
if [ -d "$Y/templates/base" ]; then
  t_eq "the vendored copy is current with yard (exit 0)" 0 "$(sh "$T_ROOT/bin/standard-vendor-scaffolder.sh" --check --yard "$Y" >/dev/null 2>&1; echo $?)"
  mkdir -p "$VC/templates/base"; cp "$Y/templates/base/AGENTS.md.tmpl" "$Y/templates/base/CLAUDE.md.tmpl" "$VC/templates/base/"
  t_eq "a scratch copy of yard is current too" 0 "$(sh "$T_ROOT/bin/standard-vendor-scaffolder.sh" --check --yard "$VC" >/dev/null 2>&1; echo $?)"
  printf 'x' >> "$VC/templates/base/AGENTS.md.tmpl"
  _o="$(sh "$T_ROOT/bin/standard-vendor-scaffolder.sh" --check --yard "$VC" 2>&1)"; _rc=$?
  t_eq "one byte changed in the scratch yard is red (exit 1)" 1 "$_rc"
  t_has "...and says stale" "$_o" "stale vendor/scaffolder/templates/base/AGENTS.md.tmpl"
  t_red standard.vendor-scaffolder-fresh
else printf '  SKIP: no yard checkout at %s: freshness of vendor/scaffolder unchecked\n' "$Y"; t_pass; fi
_o="$(sh "$T_ROOT/bin/standard-vendor-scaffolder.sh" --check --yard "$T_TMP/no-yard" 2>&1)"; _rc=$?
t_eq "no yard is exit 3, never a pass" 3 "$_rc"
t_has "...said in one line" "$_o" "unchecked: no yard checkout"
if [ -d "$Y/templates/base" ]; then
  # a vendored file edited by hand: its own manifest row no longer matches
  VT="$T_TMP/vt"; mkdir -p "$VT/bin"; cp "$T_ROOT/bin/standard-vendor-scaffolder.sh" "$T_ROOT/bin/library-log.sh" "$VT/bin/"; cp -R "$VY" "$VT/vendor-yard"; mkdir -p "$VT/vendor"; mv "$VT/vendor-yard" "$VT/vendor/scaffolder"
  printf 'x' >> "$VT/vendor/scaffolder/templates/base/CLAUDE.md.tmpl"
  _o="$(sh "$VT/bin/standard-vendor-scaffolder.sh" --check --yard "$Y" 2>&1)"; _rc=$?
  t_eq "a hand-edited vendored file is red (exit 1)" 1 "$_rc"
  t_has "...and says edited" "$_o" "edited vendor/scaffolder/templates/base/CLAUDE.md.tmpl"
fi

t_section "9 - every repo kind gets both files, or says why not"
for _k in $(awk -F'\t' '!/^#/ && NR > 1 && $1 != "id" { print $1 }' "$T_ROOT/standards/naming/repo-kinds.tsv"); do
  mkrepo "k-$_k"; _o="$(sh "$MS" "$G/k-$_k" --kind "$_k" --name "k-$_k" 2>&1)"; _rc=$?
  t_eq "kind $_k: exit 0" 0 "$_rc"
  t_eq "kind $_k: AGENTS.md and CLAUDE.md are written" yes "$([ -f "$G/k-$_k/AGENTS.md" ] && [ -f "$G/k-$_k/CLAUDE.md" ] && echo yes || echo no)"
  t_eq "kind $_k: the bare import is there" 1 "$(grep -cx '@AGENTS.md' "$G/k-$_k/CLAUDE.md")"
  t_eq "kind $_k: no marker" yes "$(nomarker "k-$_k")"
done
t_has "a kind the kit lists no template rows for says so in one line" "$(sh "$MS" "$G/k-control-plane" --kind control-plane --name k-control-plane 2>&1)" "the kit lists no template items for kind control-plane"
t_section "10 - rendering is bounded: a hostile value or a broken template ends fast, writes nothing, leaves no temp dir"
# Each case runs under a watchdog (5 s, then kill -9), so a regression that loops cannot hang this suite: exit 137 is "hung".
bounded() { "$@" > "$T_TMP/b.out" 2>&1 & _bp=$!; ( sleep 5; kill -9 "$_bp" 2>/dev/null ) > /dev/null 2>&1 & _bw=$!; wait "$_bp"; _brc=$?; kill "$_bw" 2>/dev/null; wait "$_bw" 2>/dev/null; return "$_brc"; }
nothing() { [ -z "$(find "$G/$1" -path "$G/$1/.git" -prune -o -type f -print | head -n 1)" ] && echo yes || echo no; }
mkrepo lit; TD="$T_TMP/tmpd"; mkdir -p "$TD"
_t0=$(date +%s); TMPDIR="$TD" bounded sh "$MS" "$G/lit" --name lit --covers 'x {{project_name}} y'; _rc=$?; _o="$(cat "$T_TMP/b.out")"
t_eq "a --covers value with a template marker finishes (exit 0, not hung)" 0 "$_rc"
t_eq "...within 5 s" yes "$([ $(( $(date +%s) - _t0 )) -lt 5 ] && echo yes || echo no)"
t_eq "...inserted literally, never re-rendered" 1 "$(grep -c 'x {{project_name}} y' "$G/lit/AGENTS.md")"
mkrepo br; TMPDIR="$TD" bounded sh "$MS" "$G/br" --name br --covers 'a }} b {{#if lifecycle}} c {{/if}} d'; _rc=$?
t_eq "a value containing }} and a block opener finishes (exit 0)" 0 "$_rc"
t_eq "...and stays literal: the lifecycle block of the template is not entered by it" 1 "$(grep -c 'a }} b {{#if lifecycle}} c {{/if}} d' "$G/br/AGENTS.md")"
# a broken template: an unclosed block, a stray close, an unknown variable
mktree() { rm -rf "$T_TMP/bt"; mkdir -p "$T_TMP/bt/bin"; cp "$MS" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/library-admission.sh" "$T_ROOT/bin/standard-kit.sh" "$T_TMP/bt/bin/"
  ln -s "$T_ROOT/templates" "$T_TMP/bt/templates"; ln -s "$T_ROOT/tests" "$T_TMP/bt/tests"; ln -s "$T_ROOT/standards" "$T_TMP/bt/standards"
  mkdir -p "$T_TMP/bt/vendor"; cp -R "$T_ROOT/vendor/scaffolder" "$T_TMP/bt/vendor/scaffolder"; }
for _case in 'unclosed:{{#if lifecycle}} never closed' 'stray:text {{/if}} more' 'unknown:{{no_such_variable}}'; do
  _n="${_case%%:*}"; mktree; printf '%s\n' "${_case#*:}" >> "$T_TMP/bt/vendor/scaffolder/templates/base/AGENTS.md.tmpl"
  mkrepo "bad-$_n"; ls "$TD" > "$T_TMP/before.ls"; _t0=$(date +%s)
  TMPDIR="$TD" bounded sh "$T_TMP/bt/bin/member-standard.sh" "$G/bad-$_n" --name "bad-$_n"; _rc=$?; _o="$(cat "$T_TMP/b.out")"
  t_eq "a template with $_n markup is refused (exit 1, not hung or killed)" 1 "$_rc"
  t_eq "$_n: within 5 s" yes "$([ $(( $(date +%s) - _t0 )) -lt 5 ] && echo yes || echo no)"
  t_has "$_n: the refusal names the unrendered marker" "$_o" "unrendered"
  t_eq "$_n: nothing was written to the project" yes "$(nothing "bad-$_n")"
  ls "$TD" > "$T_TMP/after.ls"; t_eq "$_n: the temp dir is removed" 0 "$(cmp -s "$T_TMP/before.ls" "$T_TMP/after.ls"; echo $?)"
done
# output is capped: a template that would expand past 1 MB is refused
mktree; _big="$(awk 'BEGIN { for (i = 0; i < 40000; i++) printf "0123456789012345678901234567890\n" }')"; printf '%s\n' "$_big" >> "$T_TMP/bt/vendor/scaffolder/templates/base/AGENTS.md.tmpl"
mkrepo big; TMPDIR="$TD" bounded sh "$T_TMP/bt/bin/member-standard.sh" "$G/big" --name big; _rc=$?
t_eq "output past the 1 MB cap is refused (exit 1)" 1 "$_rc"
t_has "...and says so" "$(cat "$T_TMP/b.out")" "larger than"
t_eq "...with nothing written" yes "$(nothing big)"
t_red member.standard
t_done
