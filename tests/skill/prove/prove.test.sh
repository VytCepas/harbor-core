#!/usr/bin/env sh
# prove, the detector-recall engine (skills/test-strength/bin/prove.sh, R5 · contracts/gates.md).
# This is the only place its verdict vocabulary is pinned from outside the engine: an engine that
# applies no mutant and credits every kill would certify a checker that cannot fail. Part 1: P1 (the
# null checker) and P2 (vacuity guards). Parts: prove.engine- (P3, P4), prove.report- (P5, P6),
# prove.cli- (P7 to P10) and prove.watchdog-test.sh (P11). Fixtures: prove-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/skills/prove-fixture.sh"

t_section "P1 · the self-referential assertion: an engine crediting uncheckable kills"
_prove always-green
rc 4 'P1-1 a checker that CANNOT FAIL must be COULD-NOT-LOOK, never PROVEN'
t_has 'P1-2 the surviving canary is named, not folded into a survivor count' "$O" 'CANARY     SURVIVED'
# Anchored to the verdict line: a bare PROVEN is a substring of the UNPROVEN header.
t_hasnt 'P1-3 a run that could not look prints no PROVEN verdict' "$O" '  VERDICT    PROVEN'
t_hasnt 'P1-4 and no killed fraction, which would read as coverage' "$O" '  GENERATED  1/1 killed'
_prove clean
rc 0 'P1-5 a checker that DOES discriminate reaches PROVEN, or P1-1 is not about the canary'
t_has 'P1-6 and its canary reads as killed' "$O" 'CANARY     KILLED'
_prove --self-test
rc 0 'P1-7 prove.sh --self-test passes on the shipped engine'
_st_p=$(awk '$1 == "prove:" { print $2; exit }' "$OUT")
t_eq 'P1-8 --self-test printed a non-zero numeric pass count' yes "$([ "${_st_p:-x}" -gt 0 ] 2>/dev/null && echo yes || echo no)"
t_eq 'P1-9 --self-test reported 0 failed' 0 "$(awk '$1 == "prove:" { print $4; exit }' "$OUT")"

t_section "P2 · vacuity guards: a declaration that is not gate-shaped is REFUSED"
# The control first: an engine that refuses everything passes every refusal below.
BASEOK="$(_mk_case ok basegood < /dev/null)"
_base basegood > "$BASEOK/basegood.target"
PT="$BASEOK" _prove --all
rc 0 'P2-1 the shared BASE declaration is ACCEPTED, or every refusal below is vacuous'
t_has 'P2-2 and proven, not merely tolerated' "$O" '  VERDICT    PROVEN'
t_eq 'P2-3 the base run reports zero inert' 0 "$(genfield inert)"
t_eq 'P2-4 the base run reports zero capped' 0 "$(genfield capped)"

PT="$(mk_nocontrol)" _prove --all
rc 5 'P2-5 a target with no control is REFUSED'
t_has 'P2-6 and the refusal says why' "$O" 'no control declared'
D="$(_base tautology | _mk_case bad tautology)"; cp "$D/seed.md" "$D/control.md"
PT="$D" _prove --all
rc 5 'P2-7 a control byte-identical to the seed is REFUSED'
# In markdown a blank line is whitespace but a # line is a heading: P2-37 owns the other side.
D="$(_base blankonly | _mk_case bad blankonly)"; awk '{ print; print "" }' "$D/seed.md" > "$D/control.md"
PT="$D" _prove --all
rc 0 'P2-8 a markdown control varying only by blank lines is ACCEPTED, not refused'
PT="$(_base cmdnosub | sed 's|^control C-1   file control.md|control C-1   cmd true|' | _mk_case bad cmdnosub)" _prove --all
rc 5 'P2-9 a cmd control not referencing $SUBJECT is REFUSED'
PT="$(mk_cmdok)" _prove --all
rc 0 'P2-10 a cmd control that DOES reference $SUBJECT is accepted and green'
# A data subject whose only control is a cmd: the checker is never invoked on a lawful input.
PT="$(_base cmdonly | sed 's|^control C-1   file control.md|control C-1   cmd [ -f "$SUBJECT" ]|' | _mk_case bad cmdonly)" _prove --all
rc 5 'P2-10b a markdown target whose only control is a cmd control is REFUSED'
PT="$(_base nowhy | sed '/^        why:/d' | _mk_case bad nowhy)" _prove --all
rc 5 'P2-11 a control with no why: is REFUSED'
PT="$(_base novaries | sed '/^        varies:/d' | _mk_case bad novaries)" _prove --all
rc 5 'P2-12 a control with no varies: is REFUSED'
D="$({ _base plantnowhy
       printf '\nplant   P-1   sed -e %ss/^## Alpha$/**Alpha**/%s "$SEED" > "$MUTANT"\n' "$Q" "$Q"
     } | _mk_case bad plantnowhy)"
PT="$D" _prove --all
rc 5 'P2-13 a plant with no why: is REFUSED'
PT="$(mk_noop)" _prove --all
rc 4 'P2-14 an INERT mutant is COULD-NOT-LOOK, never a kill, never a survivor'
t_has 'P2-15 and the report names inertness' "$O" 'inert'
PT="$(mk_baselinered)" _prove --all
rc 4 'P2-16 a checker that rejects the SEED is COULD-NOT-LOOK'
t_has 'P2-17 and the baseline is reported RED' "$O" 'BASELINE   RED'
PT="$(mk_exit9)" _prove --all
rc 4 'P2-18 a checker exit that is neither green nor red is COULD-NOT-LOOK'
D="$T/bad/nosites"; rm -rf "$D"; mkdir -p "$D"
printf 'ANCHORWORD, and nothing that looks like a heading.\n' > "$D/seed.md"
printf 'ANCHORWORD in different but equally lawful prose.\n'   > "$D/control.md"
printf '#!/usr/bin/env sh\nset -u\n/usr/bin/grep -q ANCHORWORD "$1" || exit 1\nexit 0\n' > "$D/check.sh"
_base nosites > "$D/nosites.target"
PT="$D" _prove --all
rc 4 'P2-19 zero mutants applied is COULD-NOT-LOOK, not a clean sweep'

# Grammar: an unknown token refuses the FILE, or one typo silently deletes a mutator class.
PT="$(_base badmutator | sed 's/section-delete/section-eviscerate/' | _mk_case bad badmutator)" _prove --all
rc 5 'P2-20 an unknown mutator name refuses the file'
PT="$({ _base baddirective; printf '\nnosuchdirective  value\n'; } | _mk_case bad baddirective)" _prove --all
rc 5 'P2-21 an unknown directive refuses the file'
PT="$({ _base badkey; printf '        nosuchkey: value\n'; } | _mk_case bad badkey)" _prove --all
rc 5 'P2-22 an unknown continuation key refuses the file'
PT="$(_base badlane | sed 's/^lane          fast/lane          turbo/' | _mk_case bad badlane)" _prove --all
rc 5 'P2-23 an unknown lane refuses the file'
PT="$(_base badkind | sed 's/^subject-kind  markdown-contract/subject-kind  xml-contract/' | _mk_case bad badkind)" _prove --all
rc 5 'P2-24 an unknown subject-kind refuses the file'
PT="$(_base other | _mk_case bad namemismatch)" _prove --all
rc 5 'P2-25 target != file basename refuses the file'
PT="$(_base missinghdr | sed '/^green /d' | _mk_case bad missinghdr)" _prove --all
rc 5 'P2-26 a missing mandatory header refuses the file'
PT="$({ _base duphdr; printf 'lane          fast\n'; } | _mk_case bad duphdr)" _prove --all
rc 5 'P2-27 a duplicated mandatory header refuses the file'
D="$({ _base dupid
       printf '\ncontrol C-1   file control.md\n        varies: shape\n        why:    the same id twice\n'
     } | _mk_case bad dupid)"
PT="$D" _prove --all
rc 5 'P2-28 a duplicate id within a target refuses the file'
PT="$(_base noseed | sed 's|^seed          seed.md|seed          nosuch.md|' | _mk_case bad noseed)" _prove --all
rc 5 'P2-29 a seed path that does not exist refuses the file'

# stage is a fixed verb list, never eval'd, confined to $WORK; the lawful side shows it runs.
PT="$(_base stageverb 'stage         chmod $WORK/x' | _mk_case bad stageverb)" _prove --all
rc 5 'P2-30 an unknown stage verb refuses the file'
OUTSIDE="$T/outside-stage"; rm -rf "$OUTSIDE"
PT="$(_base stageout "stage         mkdir $OUTSIDE" | _mk_case bad stageout)" _prove --all
rc 5 'P2-31 a stage destination outside $WORK refuses the file'
t_eq 'P2-32 the refused stage was not executed' absent "$([ -d "$OUTSIDE" ] && echo present || echo absent)"
D="$(_base stageok 'stage         mkdir $WORK/sub' | _mk_case ok stageok)"
rm -rf "$T/w1"; mkdir -p "$T/w1"
PT="$D" WRK="$T/w1" _prove stageok --keep
rc 0 'P2-33 a lawful stage under $WORK is accepted'
WS1=$(awk '$1 == "workspace" { print $2; exit }' "$OUT")
t_eq 'P2-34 and the lawful stage actually RAN' present "$([ -d "${WS1:-/nonexistent}/sub" ] && echo present || echo absent)"
rm -rf "$T/w1"
mkdir -p "$T/emptydir"
PT="$T/emptydir" _prove --all
rc 5 'P2-35 --all over a directory with no *.target is REFUSED, never a green empty run'

# The control rule is per subject-kind: in markdown # is a heading (content), in a shell script a comment.
D="$(_base ctlhead | _mk_case ok ctlhead)"
{ cat "$D/seed.md"; printf '\n# Appendix\n'; } > "$D/control.md"
t_exit 'P2-36 the target checker accepts the heading-varying control' 0 sh "$D/check.sh" "$D/control.md"
PT="$D" _prove --all
rc 0 'P2-37 a markdown control differing from the seed only in an added heading is ACCEPTED'
t_has 'P2-38 and was actually exercised, green' "$O" '  CONTROLS   1/1 green'
PT="$T/shell" _prove shcomment
rc 5 'P2-39 a posix-shell control differing from the seed only in a reworded comment is REFUSED'

# An empty mutant is the canary wearing a mutant name: a recipe that failed must not bank a kill.
D="$({ _base emptyplant
       printf '\nplant   EMP-1  /usr/bin/grep -q NOTHING-MATCHES-HERE "$SEED" > "$MUTANT"\n'
       printf '        why:    a recipe that fails and leaves an empty file behind\n'
     } | _mk_case bad emptyplant)"
PT="$D" _prove --all
rc 4 'P2-40 a DECLARED mutant of zero bytes is COULD-NOT-LOOK'
t_hasnt 'P2-41 and is never banked as a kill' "$O" '  DECLARED   1/1 killed'
t_has 'P2-42 and the report names the plant' "$O" 'EMP-1'
D="$({ _base goodplant
       printf '\nplant   P-1   sed -e %ss/^## Alpha$/**Alpha**/%s "$SEED" > "$MUTANT"\n' "$Q" "$Q"
       printf '        why:    a heading demoted to bold loses the structure the checker counts\n'
     } | _mk_case ok goodplant)"
PT="$D" _prove --all
rc 0 'P2-42b the same plant slot with a recipe that applies reaches a verdict'
t_has 'P2-42c and is banked as a kill, or P2-41 proves nothing' "$O" '  DECLARED   1/1 killed'
mkgen() { # <slug> <seed text> — one section; the checker wants exactly one ## heading
  _gd="$T/gen/$1"; rm -rf "$_gd"; mkdir -p "$_gd"; printf '%b' "$2" > "$_gd/seed.md"
  printf '%b' "$2" | sed 's/Alpha body\./Kitokia teiseta proza./' > "$_gd/control.md"
  printf '#!/usr/bin/env sh\nset -u\n_n=$(/usr/bin/grep -c "^## " "$1" || true)\n[ "${_n:-0}" = "1" ] || exit 1\nexit 0\n' > "$_gd/check.sh"
  _base "$1" > "$_gd/$1.target"; printf '%s' "$_gd"
}
PT="$(mkgen emptygen '## Alpha\nAlpha body.\n')" _prove --all
rc 4 'P2-43 a GENERATED mutant of zero bytes is COULD-NOT-LOOK'
t_hasnt 'P2-44 and is never banked as a kill' "$O" '  GENERATED  1/1 killed'
PT="$(mkgen onesec '# ONE\n\n## Alpha\nAlpha body.\n')" _prove --all
rc 0 'P2-44b one section under a title leaves a non-empty mutant, and the run reaches a verdict'
t_has 'P2-44c that mutant is banked as a kill, or P2-44 and P1-4 prove nothing' "$O" '  GENERATED  1/1 killed'

# An unreadable control was never exercised: the seed already at $PLACE would be scored twice.
D="$(_base ctlunread | _mk_case bad ctlunread)"
chmod 000 "$D/control.md" 2>/dev/null
t_eq 'P2-45a chmod 000 makes the control unreadable (not running as root)' unreadable \
  "$([ -r "$D/control.md" ] && echo readable || echo unreadable)"
PT="$D" _prove --all
rc 4 'P2-45 an unreadable control file is COULD-NOT-LOOK'
t_hasnt 'P2-46 and is never counted green' "$O" '  CONTROLS   1/1 green'
t_eq 'P2-47 and the REASON line names the control' yes "$(re '^  REASON .*C-1')"
chmod 644 "$D/control.md" 2>/dev/null
PT="$D" _prove --all
rc 0 'P2-48 the same control readable again reaches a verdict'
t_done
