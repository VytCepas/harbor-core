#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: the document rules — TS1 and T3/K1's link extractor
# (harbor#6), T4/T5/T7's citations (harbor#82, #83, #86, #255), T2's counts and T12's dates
# (harbor#520). Every arm points one rule at a throwaway repo-shaped root (harbor#667).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

TSR="$TMP/tsroot"; mkdir -p "$TSR/policy" "$TSR/tools/memory" "$TSR/contracts"
cat > "$TSR/tools/memory/good-module.ts" <<'TS'
// memory (harbor#6) — a well-formed module.
import { readFileSync } from "node:fs";
import { tokenize } from "./tokenize.ts";
export const ok = () => process.stdout.write(String(readFileSync));
TS
printf '// harbor#6\nimport g from "graphology";\n'            > "$TSR/tools/memory/off-disk.ts"
printf '// nothing here names a ticket\nconst a = 1;\n'        > "$TSR/tools/memory/no-ticket.ts"
printf '// harbor#6\nimport {writeFileSync} from "node:fs";\n' > "$TSR/tools/memory/writes.ts"
printf '// harbor#6\n'                                         > "$TSR/tools/memory/BadName.ts"
# A two-link line whose FIRST link dangles: a greedy sed saw only the last link on a line.
printf '# probe\nUp-link to [a file that is not there](../NOPE.md).\nTwo on one line: [gone](./ALSO-NOPE.md) then [present](./probe.md).\n' \
  > "$TSR/contracts/probe.md"
# docs/ and standards/ are swept too (harbor#1149): a dev-layer link in docs/README.md was invisible to a 4-glob sweep.
mkdir -p "$TSR/docs/decisions" "$TSR/standards"
printf '# probe\nSee [gone](../GONE-FROM-DOCS.md) and [here](./probe.md).\n' > "$TSR/docs/probe.md"
printf '# probe\nSee [gone](../../GONE-FROM-DECISIONS.md).\n'                > "$TSR/docs/decisions/0001.md"
printf '# probe\nSee [gone](../GONE-FROM-STANDARDS.md).\n'                   > "$TSR/standards/probe.md"

# The sweep is every markdown file, not a list of directories (harbor#1149): ~500 exported files sat outside the old list.
for _d in skills/probe commands inject.d/box vendor/skills/probe patches fixtures/memory/corpus/KNOWLEDGE/Research fixtures/other deep/er/still; do mkdir -p "$TSR/$_d"; done
printf '# probe\nSee [gone](../../GONE-FROM-SKILL.md).\n'       > "$TSR/skills/probe/SKILL.md"
printf '# probe\nSee [gone](../GONE-FROM-COMMAND.md).\n'         > "$TSR/commands/probe.md"
printf '# probe\nSee [gone](../../GONE-FROM-INJECT.md).\n'       > "$TSR/inject.d/box/10-probe.md"
printf '# probe\nSee [gone](../../GONE-FROM-VENDOR.md).\n'       > "$TSR/vendor/skills/probe/SKILL.md"
printf '# probe\nSee [gone](../GONE-FROM-PATCHES.md).\n'         > "$TSR/patches/probe.md"
printf '# probe\nSee [gone](../../../../../GONE-DEEP.md).\n'      > "$TSR/deep/er/still/probe.md"
# the one fixture that cites a dead path on purpose is exempt BY NAME; a sibling that does the same is not
printf '# probe\nSee [gone](./ON-PURPOSE.md).\n'                 > "$TSR/fixtures/memory/corpus/KNOWLEDGE/Research/dead-path-citer.md"
printf '# probe\nSee [gone](../NOT-ON-PURPOSE.md).\n'            > "$TSR/fixtures/other/probe.md"
# a git root judges the TRACKED docs: a note nobody committed (build output, a scratch file) is not a shipped document
TSG="$TMP/tsgit"; mkdir -p "$TSG/skills" "$TSG/build"
printf '# probe\nSee [gone](../GONE-TRACKED.md).\n'              > "$TSG/skills/probe.md"
printf '# probe\nSee [gone](../GONE-UNTRACKED.md).\n'            > "$TSG/build/note.md"
git -C "$TSG" init -q . && git -C "$TSG" add skills/probe.md

t_section "TS1: tools/*.ts are kebab-case, ticketed, on-disk and read-only (harbor#6)"
OUT_TS="$(viol TS1 "$TSR")"
t_has "a non-kebab-case tools/ filename is reported" "$OUT_TS" 'not kebab-case: tools/memory/BadName.ts'
t_has "a .ts with no ticket in the first 4 lines is reported" "$OUT_TS" \
  'no ticket reference in the first 4 lines: tools/memory/no-ticket.ts'
t_eq "an off-disk import is reported" yes "$(hasre "$OUT_TS" 'off-disk import.*tools/memory/off-disk\.ts')"
t_has "a filesystem write is reported" "$OUT_TS" 'filesystem write in tools/memory/writes.ts'
t_hasnt "a well-formed module is silent, process.stdout.write included" "$OUT_TS" 'good-module.ts'

t_section "T3: every ./path a doc cites resolves"
OUT_T3="$(viol T3 "$TSR")"
t_has "a dangling ../ link is reported" "$OUT_T3" "$DEAD ../NOPE.md"
t_has "the FIRST of two links on one line is not skipped" "$OUT_T3" "$DEAD ./ALSO-NOPE.md"
t_hasnt "a link that resolves stays silent" "$OUT_T3" "$DEAD ./probe.md"
t_has "a dangling link in docs/ is reported" "$OUT_T3" "docs/probe.md $DEAD ../GONE-FROM-DOCS.md"
t_has "...in docs/<dir>/ too" "$OUT_T3" "docs/decisions/0001.md $DEAD ../../GONE-FROM-DECISIONS.md"
t_has "...in standards/ too" "$OUT_T3" "standards/probe.md $DEAD ../GONE-FROM-STANDARDS.md"
t_hasnt "...and a resolving link in docs/ stays silent" "$OUT_T3" "docs/probe.md $DEAD ./probe.md"
t_has "a dangling link in skills/<dir>/ is reported" "$OUT_T3" "skills/probe/SKILL.md $DEAD ../../GONE-FROM-SKILL.md"
t_has "...in commands/ too" "$OUT_T3" "commands/probe.md $DEAD ../GONE-FROM-COMMAND.md"
t_has "...in inject.d/<dir>/ too" "$OUT_T3" "inject.d/box/10-probe.md $DEAD ../../GONE-FROM-INJECT.md"
t_has "...in vendor/skills/<dir>/ too" "$OUT_T3" "vendor/skills/probe/SKILL.md $DEAD ../../GONE-FROM-VENDOR.md"
t_has "...in patches/ too" "$OUT_T3" "patches/probe.md $DEAD ../GONE-FROM-PATCHES.md"
t_has "...at any depth" "$OUT_T3" "deep/er/still/probe.md $DEAD ../../../../../GONE-DEEP.md"
t_has "a fixture that is not the deliberate one is judged" "$OUT_T3" "fixtures/other/probe.md $DEAD ../NOT-ON-PURPOSE.md"
t_hasnt "the fixture that cites a dead path on purpose is exempt by name" "$OUT_T3" "dead-path-citer.md"
OUT_T3G="$(viol T3 "$TSG")"
t_has "a git root: a tracked doc is judged" "$OUT_T3G" "skills/probe.md $DEAD ../GONE-TRACKED.md"
t_hasnt "...and an untracked one is not" "$OUT_T3G" "GONE-UNTRACKED"

t_section "K1: policy/constitution.md's citations, both link forms"
printf '# probe constitution\nTwo on one line: [gone](./K1-NOPE.md) then [present](./policy/constitution.md).\nA URL is not a repo path: [web](https://example.com/k1).\n' > "$TSR/policy/constitution.md"
OUT_K1="$(viol K1 "$TSR")"
t_has "the FIRST of two links on one line is not skipped" "$OUT_K1" "$DEAD K1-NOPE.md"
t_hasnt "a link that resolves stays silent" "$OUT_K1" "$DEAD policy/constitution.md"
t_hasnt "only ./ citations are repo paths: a URL link is not one" "$OUT_K1" 'example.com/k1'
cat > "$TSR/policy/constitution.md" <<'MD'
# probe constitution
A repo-only doc: `./K1-BACKTICK-NOPE.md` and a real one: `./policy/constitution.md`.
Not paths, and must never be read as any: `permissions.deny`, `harbor#44`,
`absent  CLAUDE.md`, `jq -e .`, `--live`.
MD
OUT_K1B="$(viol K1 "$TSR")"
t_has "a dead BACKTICKED ./citation is caught" "$OUT_K1B" "$DEAD K1-BACKTICK-NOPE.md"
t_hasnt "a resolving backticked citation stays silent" "$OUT_K1B" "$DEAD policy/constitution.md"
t_hasnt "backticked prose is not a path: permissions.deny" "$OUT_K1B" 'permissions.deny'
t_hasnt "backticked prose is not a path: harbor#44" "$OUT_K1B" 'harbor#44'
t_hasnt "backticked prose is not a path: CLAUDE.md" "$OUT_K1B" 'CLAUDE.md'
t_hasnt "backticked prose is not a path: --live" "$OUT_K1B" '--live'

t_section "MAG1: a magnitude in policy/constitution.md carries the command that derives it (harbor#583)"
MAGR="$TMP/magroot"; mkdir -p "$MAGR/policy"
printf '# probe\n\nOf 52 files, 36 carry real boundaries.\n\nAn unrelated later paragraph.\n' > "$MAGR/policy/constitution.md"
t_has "RED: a bare magnitude is reported with its line" "$(viol MAG1 "$MAGR")" "policy/constitution.md:3 states the magnitude '52'"
printf '# probe\n\nOf 52 files, 36 carry real boundaries:\n\n```sh\nsh bin/lint-module-shape.sh bin\n```\n' > "$MAGR/policy/constitution.md"
t_eq "GREEN: the same sentence with a fenced command beside it is silent" "" "$(viol MAG1 "$MAGR")"
printf '# probe\n\nOf 52 files, 36 carry real boundaries.\n\n```sh\nsh bin/lint-module-shape.sh bin\n```\n' > "$MAGR/policy/constitution.md"
t_eq "a fence in the NEXT paragraph counts" "" "$(viol MAG1 "$MAGR")"
printf '# probe\n\n- first bullet says 52 files\n- second bullet\n\n```sh\ntrue\n```\n' > "$MAGR/policy/constitution.md"
t_has "a fence under a different bullet is not borrowed" "$(viol MAG1 "$MAGR")" 'policy/constitution.md:3'
printf '# probe\n\nMeasured 2026-09-16, harbor#583, №2, No.2.12, Rule 3, (1) then (2), a 2×2, `10 of 10`, C2, pass one.\n1. a list marker\n' > "$MAGR/policy/constitution.md"
t_eq "dates, refs, №N, Rule N, enumerators, backticks and list markers are not magnitudes" "" "$(viol MAG1 "$MAGR")"
t_has "the denominator is printed, so zero examined cannot read as clean" "$(lint1 MAG1 "$MAGR")" '0 digit magnitude(s) examined'
rm -f "$MAGR/policy/constitution.md"
t_has "a missing policy/constitution.md is red, not a pass" "$(viol MAG1 "$MAGR")" 'is missing'
t_eq "the real policy/constitution.md is clean" "" "$(viol MAG1 "$T_ROOT")"

DOCFIX="$TMP/docs"; mkdir -p "$DOCFIX/contracts" "$DOCFIX/docs/reference"
cp "$ROOT/contracts/cli.md" "$DOCFIX/contracts/cli.md"; cp "$ROOT/docs/reference/citations.md" "$DOCFIX/docs/reference/citations.md"
printf '# contracts index\n' > "$DOCFIX/contracts/README.md"

t_section "T5: the CLI is harbor, and the Kubernetes helm stays writable (harbor#83)"
printf '%s\n' 'Verified behaviourally: `helm uninstall api --namespace prod` returns ask.' \
  '`helm install`, `helm list`, `helm status` and `helm upgrade` are the same program.' > "$DOCFIX/DOC.md"
t_eq "the Kubernetes package manager's verbs are silent" "" "$(viol T5 "$DOCFIX")"
printf '%s\n' 'Run `helm observe` to read the ledger, then `helm doctor`.' \
  'Type the `helm` command to manage the floor.' > "$DOCFIX/DOC.md"
t_eq "a Harbor verb under the old name still goes red" yes "$(nonempty "$(viol T5 "$DOCFIX")")"

t_section "T4: a repo exists when docs/reference/citations.md cites it (harbor#86)"
printf '| `https://github.com/VytCepas/sample-repo` | 200 | gh | 2026-08-01 | A fixture repo. |\n' >> "$DOCFIX/docs/reference/citations.md"
printf 'The two tools live in VytCepas/sample-repo.\n' > "$DOCFIX/DOC.md"
t_eq "a cited repo is not called nonexistent" "" "$(viol T4 "$DOCFIX")"
printf 'See VytCepas/does-not-exist for details.\n' > "$DOCFIX/DOC.md"
t_has "a repo cited nowhere goes red" "$(viol T4 "$DOCFIX")" 'does-not-exist'
printf 'The two tools live in VytCepas/sample-repo.\n' > "$DOCFIX/DOC.md"
grep -v 'VytCepas/sample-repo' "$DOCFIX/docs/reference/citations.md" > "$DOCFIX/CITATIONS.new" && mv "$DOCFIX/CITATIONS.new" "$DOCFIX/docs/reference/citations.md"
t_has "DERIVED: remove the citation row and the same repo goes red" "$(viol T4 "$DOCFIX")" 'sample-repo'
cp "$ROOT/docs/reference/citations.md" "$DOCFIX/docs/reference/citations.md"

t_section "T7: every external URL a doc cites is in docs/reference/citations.md (harbor#82)"
printf 'See help.example-source.io for the tag behaviour.\n' > "$DOCFIX/DOC.md"
t_has "a bare hostname not on the list goes red" "$(viol T7 "$DOCFIX")" 'help.example-source.io'
{ cat "$ROOT/docs/reference/citations.md"; printf '| `https://help.example-source.io` | 200 | curl | 2026-08-02 | fixture |\n'; } > "$DOCFIX/docs/reference/citations.md"
OUT_T7G="$(viol T7 "$DOCFIX")"
t_hasnt "the same hostname passes once the ledger carries it" "[$OUT_T7G]" 'help.example-source.io'
cp "$ROOT/docs/reference/citations.md" "$DOCFIX/docs/reference/citations.md"
printf 'Deny it with `"serverUrl": "https://mcp.example-source.io/*"` in settings.\n' > "$DOCFIX/DOC.md"
OUT_T7W="$(viol T7 "$DOCFIX")"
t_hasnt "a URL with a glob is a pattern, not a citation (harbor#255)" "[$OUT_T7W]" 'mcp.example-source.io/*'
printf 'The behaviour is documented at `https://docs.example-source.io/tags`.\n' > "$DOCFIX/DOC.md"
t_has "a real URL in inline backticks is still reported" "$(viol T7 "$DOCFIX")" 'docs.example-source.io/tags'
cat > "$DOCFIX/DOC.md" <<'MD'
The `permissions.deny` block covers `compute.instances.delete` and
`storage.objects.delete`. See `guard-lib.sh`, `config.yaml`, `README.md`,
`settings.json` and `floor-normalize.awk` — e.g. version 3.0.18, i.e. the pin.
Mail goes to someone@mail.example-source.io, and the bare host in the fence below is skipped.

```
also.a-fake-host.io
```
MD
t_eq "dotted tokens that are not hostnames stay silent" "" "$(viol T7 "$DOCFIX")"

t_section "T7: an access card's route line is an address, not a citation (2026-09-15, private since harbor#1149)"
# The cards live in the private layer, outside the tree under test; the rule finds them through scope-roots.sh.
PRIVFIX="$TMP/docs-private"; mkdir -p "$PRIVFIX/access" "$DOCFIX/skills/access-ledger/bin"; export HARBOR_SCOPE_PRIVATE="$PRIVFIX"
routes() { printf '#!/usr/bin/env sh\nREQUIRED_FIELDS=%s\n' "'$1'" > "$DOCFIX/skills/access-ledger/bin/check-routes.sh"; }
routes 'identity
via
use
check
verified'
: > "$DOCFIX/DOC.md"
printf '# Fixture card\n\n    identity: someone\n    via:      browser\n    use:      https://route.example-source.io/store/thing\n    check:    open https://route.example-source.io/\n    verified: 2026-09-15\n' \
  > "$PRIVFIX/access/fixture.md"
OUT_T7RT="$(viol T7 "$DOCFIX")"
t_hasnt "a card's route fields demand no citation row" "[$OUT_T7RT]" 'route.example-source.io'
printf '\nThe threshold wording comes from https://docs.example-source.io/limits.\n' >> "$PRIVFIX/access/fixture.md"
t_has "a card's PROSE citation is still reported" "$(viol T7 "$DOCFIX")" 'docs.example-source.io/limits'
printf '# Fixture card\n\n    use:      https://route.example-source.io/store/thing\n' > "$PRIVFIX/access/fixture.md"
routes 'identity
via
check
verified'
t_has "DERIVED: drop use from the checker's schema and the same line goes red" "$(viol T7 "$DOCFIX")" 'route.example-source.io'
rm -f "$DOCFIX/skills/access-ledger/bin/check-routes.sh"
t_has "no checker means no carve-out, never a silent skip" "$(viol T7 "$DOCFIX")" 'route.example-source.io'
routes 'identity
via
use
check
verified'
rm -f "$PRIVFIX/access/fixture.md"
printf '<!-- generated by check-routes.sh --dispatch — do not edit; edit the route cards -->\n\n# Dispatch\n\n| system | via | first move |\n|---|---|---|\n| thing | browser | https://table.example-source.io/manage |\n\nThe ladder itself is argued at https://prose.example-source.io/ladder.\n' \
  > "$PRIVFIX/access/DISPATCH.md"
OUT_T7DP="$(viol T7 "$DOCFIX")"
t_hasnt "DISPATCH.md's generated table rows are skipped" "$OUT_T7DP" 'table.example-source.io'
t_has "…and its prose is not" "$OUT_T7DP" 'prose.example-source.io/ladder'
rm -f "$PRIVFIX/access/DISPATCH.md"
printf '# Fixture card\n\nA prose source: https://absent-layer.example-source.io/limits.\n' > "$PRIVFIX/access/fixture.md"
t_has "with the layer present, the card is judged in place" "$(lint1 T7 "$DOCFIX")" 'absent-layer.example-source.io/limits'
t_hasnt "...and the rule does not claim to have skipped it" "$(lint1 T7 "$DOCFIX")" 'skipped: no private layer'
unset HARBOR_SCOPE_PRIVATE
OUT_T7NP="$(lint1 T7 "$DOCFIX")"
t_has "with no private layer, the rule says it skipped the cards" "$OUT_T7NP" 'skipped: no private layer, so the access cards were not scanned'
t_hasnt "...and judges nothing it could not read" "$OUT_T7NP" 'absent-layer.example-source.io'
printf '# Not a card\n\n    use:      https://not-a-card.example-source.io/x\n' > "$DOCFIX/DOC.md"
t_has "...and no document is mistaken for a card: a route-shaped line outside the register is still reported" "$(lint1 T7 "$DOCFIX")" 'not-a-card.example-source.io'
: > "$DOCFIX/DOC.md"
rm -f "$PRIVFIX/access/fixture.md"
printf '%s\n' 'The consent request asks for https://www.googleapis.com/auth/cloud-platform and' \
  'https://www.googleapis.com/auth/adwords, then calls' 'https://www.googleapis.com/discovery/v1/apis to enumerate.' > "$DOCFIX/DOC.md"
OUT_T7SC="$(viol T7 "$DOCFIX")"
t_hasnt "an OAuth scope is a URN, not a citation" "$OUT_T7SC" 'googleapis.com/auth/'
t_has "…while a googleapis ENDPOINT still is" "$OUT_T7SC" 'googleapis.com/discovery/v1/apis'

t_section "T2: the numeral and the phrase, however they are spaced"
T2R="$TMP/t2root"; mkdir -p "$T2R"
t2() { printf '%s\n' "$1" > "$T2R/PROBE.md"; viol T2 "$T2R" | grep -c . ; }
t_eq "one space — the shape that always worked" 1 "$(t2 'There are 7 floor guards.')"
t_exit "…and the violation fails the run" 1 env HARBOR_ROOT="$T2R" sh "$LINT" --only T2
t_eq "two spaces — the reflow that used to escape" 1 "$(t2 'There are 7  floor guards.')"
t_eq "a tab between numeral and phrase (a table cell)" 1 "$(t2 "$(printf 'There are 7\tfloor guards.')")"
# No docs/generated/status.md on the probe line: T2 drops such lines from its printout, which hid a lost anchor.
t_eq "the phrase alone, no numeral, stays silent" 0 "$(t2 'The floor guards are listed in the status file.')"
t_eq "a numeral that is not a count stays silent" 0 "$(t2 'Issue harbor#255 closed on 2026-08-24.')"
t_eq "a near-miss noun stays silent (five exact phrases)" 0 "$(t2 'There are 7 guards.')"

t_section "T12: a magnitude quoted beside a tool names its date (harbor#520)"
T12R="$TMP/t12"; mkdir -p "$T12R/bin" "$T12R/skills" "$T12R/contracts" "$T12R/docs/explanation"
printf '#!/usr/bin/env sh\n# t12 fixture (harbor#520)\nprintf "%%s\\n" ok\n' > "$T12R/bin/doctor.sh"
chmod +x "$T12R/bin/doctor.sh"
t12() { printf '# x\n\n%s\n' "$1" > "$T12R/docs/explanation/x.md"; viol T12 "$T12R"; }
t_has "an undated magnitude beside a tool is reported" \
  "$(t12 '| Layer | Verdict |
|---|---|
| Dependencies | `doctor` — 4 of 4 |')" 'docs/explanation/x.md:5'
t_eq "a date in the same paragraph satisfies it" "" "$(t12 '| Layer | Verdict (measured 2026-09-16) |
|---|---|
| Dependencies | `doctor` — 4 of 4 |')"
t_has "a dated bullet does not shelter an undated one beside it" "$(t12 '- Something measured on 2026-09-16 that is fine.
- `doctor` — 4 of 4, with no date of its own.')" 'docs/explanation/x.md:4'
t_eq "…and a bullet carrying its own date passes" "" "$(t12 '- Something measured on 2026-09-16 that is fine.
- `doctor` — 4 of 4, measured 2026-09-16.')"
t_eq "a date on a wrapped item's continuation line counts" "" "$(t12 '- `doctor` — 4 of 4, and the date is on the
  continuation line, 2026-09-16.')"
t_eq "a magnitude with no tool named does not fire (the narrowing control)" "" \
  "$(t12 'New non-floor code: **300 lines** is the advisory line, and 1 of 3 diagrams
carried a caption. An over-broad rule that refuses everything scores 100 %.')"
t_eq "a tool named with no magnitude does not fire" "" \
  "$(t12 'Run `doctor` and read what it prints; this table carries no copy of the number.')"
t_eq "a magnitude inside a fenced block is exempt" "" "$(t12 '```
| Dependencies | `doctor` — 4 of 4 |
```')"

t_done
