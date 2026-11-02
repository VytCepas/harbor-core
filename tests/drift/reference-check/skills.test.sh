#!/usr/bin/env sh
# drift-reference-check.sh (M8, harbor#44), part 2: the installed SKILL surface REF-9, skills/synced/, the
# denominators (harbor#467) and REF-10, with the mutants that prove each is load-bearing. A reference
# dead at the source AND one green at the source but dead once installed must both go red (#462).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/reference-check-fixture.sh"
mksynced() { # <fixture-dir> → one harness-synced skill carrying deep-research's citation template
  _yd="$1/skills/synced/bucket-1/deep-research/references"; mkdir -p "$_yd"
  printf -- '- {Fact} — [Source](URL); contradicted by [Source B](URL)\n' > "$_yd/researcher.md"
}
ex_of() { sh "$RC" "$1" --json 2>/dev/null | jq -r --arg r "$2" '.examined[]? | select(.rule==$r) | .count'; }  # <dir> <rule>
CLEAN="$(mkfixture clean)"

t_section "REF-9: a skill citing a path that exists NOWHERE is red"
F9A="$(mkfixture ref9-absent)"; mkskill "$F9A" alpha '[x](./nope-does-not-exist.md)'
t_eq "REF-9 fires on a wholly absent path" yes "$(fired "$(rules_of "$F9A")" REF-9)"

t_section "REF-9: a citation green at the SOURCE and dead once INSTALLED is red"
# ../../contracts/x.md resolves inside the repo and nowhere in a deployed tree, which this fixture is.
F9B="$(mkfixture ref9-escape)"; mkskill "$F9B" beta '[cu](../../contracts/cu.md)'
t_eq "REF-9 fires on a ../../ escape" yes "$(fired "$(rules_of "$F9B")" REF-9)"

t_section "REF-9 STAYS GREEN: a reference that ships beside the skill"
F9C="$(mkfixture ref9-beside)"; mkskill "$F9C" gamma '[r](references/r.md)'
mkdir -p "$F9C/skills/gamma/references"; printf 'r\n' > "$F9C/skills/gamma/references/r.md"
t_eq "a beside-the-skill reference is not REF-9" no "$(fired "$(rules_of "$F9C")" REF-9)"

t_section "REF-9: a link inside a code span is an example, not a citation (harbor#1018)"
# cu.md's `[86cbattww](…/t/86cbattww)` was REF-9's one live red. The second case is the fix being too WIDE.
F9K="$(mkfixture ref9-codespan)"; mkskill "$F9K" kappa 'stored as `[id](…/t/id)` on the way in'
t_eq "a link quoted in backticks is not REF-9" no "$(fired "$(rules_of "$F9K")" REF-9)"
F9L="$(mkfixture ref9-codespan-beside)"; mkskill "$F9L" lambda 'stored as `[id](…/t/id)`; see [x](./nope-does-not-exist.md)'
t_eq "a dead link beside a code span still fires REF-9" yes "$(fired "$(rules_of "$F9L")" REF-9)"

t_section "REF-9: a declared root redeems the escape, and binds ./ ONLY"
mkdir -p "$TMP/declroot9/contracts"; printf 'cu\n' > "$TMP/declroot9/contracts/cu.md"
F9D="$(mkfixture ref9-declared)"
mkskill "$F9D" delta "> **Path root:** \`$TMP/declroot9\`

Read \`./contracts/cu.md\` for the rest."
t_eq "a declared root redeems a ./ citation that resolves there" no "$(fired "$(rules_of "$F9D")" REF-9)"
F9E="$(mkfixture ref9-mixed)"
mkskill "$F9E" epsilon "> **Path root:** \`$TMP/declroot9\`

\`./contracts/cu.md\` and [r](references/r.md)"
mkdir -p "$F9E/skills/epsilon/references"; printf 'r\n' > "$F9E/skills/epsilon/references/r.md"
t_eq "the declared root is not applied to a beside-the-file reference" no "$(fired "$(rules_of "$F9E")" REF-9)"

t_section "REF-9: out of scope, and a bad root"
F9F="$(mkfixture ref9-absolute)"; mkskill "$F9F" zeta '[icon](/favicon.png)'
t_eq "an absolute (web) path is not REF-9" no "$(fired "$(rules_of "$F9F")" REF-9)"
F9G="$(mkfixture ref9-badroot)"
mkskill "$F9G" eta "> **Path root:** \`$TMP/no-such-root-9\`

\`./contracts/cu.md\`"
t_eq "a declared root that is not a directory fires REF-9" yes "$(fired "$(rules_of "$F9G")" REF-9)"
t_eq "no skills/ dir is not REF-9" no "$(fired "$(rules_of "$CLEAN")" REF-9)"

t_section "REF-9 and skills/synced/, the harness's tree"
# REF-9's first live run found only deep-research's `[Source](URL)` template, in files the next sync
# overwrites. The cases after the first are the ways the exclusion could be too WIDE.
F9S="$(mkfixture ref9-synced)"; mksynced "$F9S"
t_eq "a placeholder citation inside skills/synced/ is not REF-9" no "$(fired "$(rules_of "$F9S")" REF-9)"
t_eq "the synced tree is counted in the verdict" true "$(sh "$RC" "$F9S" --json 2>/dev/null \
  | jq '[.examined[] | select(.rule=="REF-9") | .what | test("1 under skills/synced/ counted, not examined")] | any')"
F9S2="$(mkfixture ref9-synced-owned)"; mksynced "$F9S2"; mkskill "$F9S2" alpha '[x](./nope-does-not-exist.md)'
t_eq "beside a synced tree, REF-9 reports exactly the owned skill's dead citation" '["skills/alpha/"]' \
  "$(sh "$RC" "$F9S2" --json 2>/dev/null | jq -c '[.findings[] | select(.rule=="REF-9") | .subject | .[0:13]]')"
F9S3="$(mkfixture ref9-synced-prefix)"; mkskill "$F9S3" synced-notes '[x](./nope-does-not-exist.md)'
t_eq "a skill merely NAMED synced-* is still examined" yes "$(fired "$(rules_of "$F9S3")" REF-9)"
F9S4="$(mkfixture ref9-synced-r10)"; mksynced "$F9S4"; mkskill "$F9S4" plain 'no citations in this one'
t_eq "citation-shaped text only inside skills/synced/ is not REF-10" no "$(fired "$(rules_of "$F9S4")" REF-10)"

t_section "the report states what it EXAMINED, not only what it found (harbor#467)"
# Derived from the extractor, never typed: a literal would pass after the fixture changed under it.
want="$(awk -f "$SRC/doc-cited-paths.awk" "$CLEAN/CLAUDE.md" | sort -u | awk 'NF{n++} END{print n+0}')"
t_eq "the clean fixture has citations to count" yes "$([ "$want" -gt 0 ] && echo yes || echo no)"
t_eq "REF-5's denominator is the extractor's row count" "$want" "$(ex_of "$CLEAN" REF-5)"
t_eq "REF-1 reports how many hook paths it examined" yes "$([ "$(ex_of "$CLEAN" REF-1)" -gt 0 ] 2>/dev/null && echo yes || echo no)"
t_eq "REF-4 reports how many pins it examined" yes "$([ "$(ex_of "$CLEAN" REF-4)" -gt 0 ] 2>/dev/null && echo yes || echo no)"
t_has "a CLEAN human report states what it examined" "$(sh "$RC" "$CLEAN" 2>/dev/null)" "examined $want citation(s) extracted from CLAUDE.md"

t_section "REF-10: an extractor that read NOTHING from a cited document is red"
F10="$(mkfixture ref10)"
printf '# c\n\nMethod, incidents and failure modes: see docs/explanation/grilling.md.\n' > "$F10/CLAUDE.md"
t_eq "REF-10 fires where the extractor returned zero over a citing document" yes "$(fired "$(rules_of "$F10")" REF-10)"
t_exit "the REF-10 fixture exits" 1 sh "$RC" "$F10"
t_eq "the blind case reports a denominator of 0" 0 "$(ex_of "$F10" REF-5)"
F10B="$(mkfixture ref10b)"
printf '# c\n\nThis document states rules in prose and cites nothing at all.\n' > "$F10B/CLAUDE.md"
t_eq "a document with nothing to cite is not REF-10" no "$(fired "$(rules_of "$F10B")" REF-10)"
F10C="$(mkfixture ref10c)"
printf '# c\n\n[home](https://example.com/x)\n' > "$F10C/CLAUDE.md"
t_eq "a URL-only document is not REF-10" no "$(fired "$(rules_of "$F10C")" REF-10)"
F10D="$(mkfixture ref10d)"; mkskill "$F10D" delta 'The rest of the contract is in contracts/cu.md.'
t_eq "a skill corpus the extractor reads nothing from fires REF-10" yes "$(fired "$(rules_of "$F10D")" REF-10)"
t_eq "REF-9 reports a zero denominator over that corpus" 0 "$(ex_of "$F10D" REF-9)"

t_section "mutation: the ZERO is load-bearing in REF-10"
MUTZ="$(mkmut mut-ref10-zero)"
sed 's/\[ "\$CITED_CLAUDE" -eq 0 \]/[ "$CITED_CLAUDE" -eq -1 ]/' "$RC" > "$MUTZ"
t_eq "the zero mutant differs from the source" yes "$(differs "$RC" "$MUTZ")"
t_eq "with its zero predicate neutered REF-10 stops firing" no "$(fired "$(rules_by "$MUTZ" "$F10")" REF-10)"

t_section "mutation: the SHAPE PROBE is load-bearing in REF-10"
MUTL="$(mkmut mut-ref10-probe)"
sed 's/END { exit !found }/END { exit 0 }/' "$RC" > "$MUTL"
t_eq "the probe mutant differs from the source" yes "$(differs "$RC" "$MUTL")"
t_eq "a probe that answers yes to everything fires on a citation-free document" yes "$(fired "$(rules_by "$MUTL" "$F10B")" REF-10)"

t_section "mutation: REF-9's resolution is load-bearing"
MUT9="$(mkmut mut-ref9)"
sed 's|^    \*)   printf .%s/%s. "\$2" "\$_ct_p" ;;.*$|    *)   printf "%s" "$_ct_p" ;;|' "$RC" > "$MUT9"
t_eq "the resolution mutant differs from the source" yes "$(differs "$RC" "$MUT9")"
t_eq "breaking _cite_target's relative arm makes the beside fixture REF-9" yes "$(fired "$(rules_by "$MUT9" "$F9C")" REF-9)"

t_section "mutation: the skills/synced/ prune is load-bearing, and exact"
MUTS="$(mkmut mut-synced)"
sed 's| -path "\$DIR/skills/synced" -prune -o||' "$RC" > "$MUTS"
t_eq "the prune mutant differs from the source" yes "$(differs "$RC" "$MUTS")"
t_eq "without the prune the placeholder fixture is REF-9" yes "$(fired "$(rules_by "$MUTS" "$F9S")" REF-9)"
MUTP="$(mkmut mut-synced-prefix)"
sed 's|-path "\$DIR/skills/synced" -prune|-path "$DIR/skills/synced*" -prune|' "$RC" > "$MUTP"
t_eq "the prefix mutant differs from the source" yes "$(differs "$RC" "$MUTP")"
t_eq "a prefix-wide prune swallows synced-notes" no "$(fired "$(rules_by "$MUTP" "$F9S3")" REF-9)"

t_section "mutation: REF-10's probe walks the SAME corpus as REF-9"
# Removing the shared prune cannot test this: REF-9 fires first and REF-10 is never reached.
MUTR="$(mkmut mut-r10-corpus)"
sed 's|_r10_hit="\$(_owned_skill_md -print |_r10_hit="$(find "$DIR/skills" -name "*.md" |' "$RC" > "$MUTR"
t_eq "the corpus mutant differs from the source" yes "$(differs "$RC" "$MUTR")"
t_eq "walking the whole skills tree in REF-10 makes its fixture red" yes "$(fired "$(rules_by "$MUTR" "$F9S4")" REF-10)"
t_done
