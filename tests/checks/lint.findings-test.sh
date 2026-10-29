#!/usr/bin/env sh
# lint FL1 and FL2, and the finding emitter (harbor#590, CONTRACTS/finding.md). FL1: lanes are declared
# once, by a person, and every row joins. FL2: every ADVISORY line records its subject. The emitter:
# with HARBOR_FINDINGS_OUT set a run writes R/A lines, and a count never reaches a subject.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

# lanes_root <name> — a root holding the real contract, CHECKS.md and the scripts its HEAL rows name
lanes_root() {
  _r="$TMP/$1"; mkdir -p "$_r/CONTRACTS" "$_r/bin"
  cp "$T_ROOT/CONTRACTS/finding.md" "$_r/CONTRACTS/"; cp "$T_ROOT/CHECKS.md" "$_r/"
  : > "$_r/bin/skill-catalog.sh"; : > "$_r/bin/memory-route.sh"; : > "$_r/bin/ci-runners.sh"
  printf '%s' "$_r"
}
# row <root> <row> — append a row inside the lanes block
row() { awk -v r="$2" '/^<!-- lanes:end -->$/ { print r } { print }' "$1/CONTRACTS/finding.md" > "$1/f.md" && mv "$1/f.md" "$1/CONTRACTS/finding.md"; }

t_section "FL1 is green on this checkout and on a root holding the real contract"
t_eq "this checkout" 0 "$(vcount "$(lint1 FL1 "$T_ROOT")")"
G="$(lanes_root green)"
t_eq "the fixture root" 0 "$(vcount "$(lint1 FL1 "$G")")"
t_has "it counts the HEAL rows" "$(lint1 FL1 "$G")" "4 in HEAL"

t_section "FL1 refuses a row that does not join"
R1="$(lanes_root unreg)"; row "$R1" '| HEAL | `lint/NOPE9` | `*` | `sh bin/skill-catalog.sh` | #590 |'
t_has "a lint key with no rule" "$(viol FL1 "$R1")" "names no lint rule"
R2="$(lanes_root nocheck)"; row "$R2" '| DECIDE | `check/no-such-check` | `*` | `-` | #590 |'
t_has "a check key with no CHECKS.md row" "$(viol FL1 "$R2")" "names no CHECKS.md row"
R4="$(lanes_root priv)"; cp "$T_ROOT/bin/check-registry-generate.sh" "$T_ROOT/bin/log-lib.sh" "$R4/bin/"; row "$R4" '| DECIDE | `check/acme-feed` | `*` | `-` | #590 |'
PVL="$TMP/pv-fl1"; mkdir -p "$PVL"
printf '## Register\n\n| `acme-feed` | the Acme feed | hourly | desktop | the feed stopped |\n\n## Platforms\n\n| acme-feed | macOS only | w | d |\n' > "$PVL/checks.md"
t_eq "a private check's key joins the composed register (harbor#1149)" "" "$(HARBOR_SCOPE_PRIVATE="$PVL" viol FL1 "$R4")"
t_has "...and with no layer it names no CHECKS.md row" "$(HARBOR_SCOPE_PRIVATE="$TMP/no-layer" viol FL1 "$R4")" "names no CHECKS.md row"
printf '## Register\n\n| `acme-feed` |\n' > "$PVL/checks.md"
t_has "a layer that does not compose is a violation, not a silent core read" "$(HARBOR_SCOPE_PRIVATE="$PVL" viol FL1 "$R4")" "does not compose into the register"
R3="$(lanes_root tier)"; row "$R3" '| DECIDE | `ci/floor` | `*` | `-` | #590 |'
t_has "a tier FL1 cannot join" "$(viol FL1 "$R3")" "in a tier FL1 cannot join yet"

t_section "FL1 names the successor of a key filed under a deprecated letter (harbor#957)"
R12="$(lanes_root letter)"; row "$R12" '| DECIDE | `lint/X3` | `*` | `-` | #590 |'
t_has "a letter key is refused, and its successor named" "$(viol FL1 "$R12")" "'lint/X3' names a deprecated id — its successor is lint/context.budget-ceiling"

t_section "FL1 refuses a malformed row"
R4="$(lanes_root lane)"; row "$R4" '| AUTO | `lint/context.budget-ceiling` | `*` | `-` | #590 |'
t_has "an unknown lane" "$(viol FL1 "$R4")" "has lane 'AUTO'"
R5="$(lanes_root dup)"; row "$R5" '| DECIDE | `lint/skill.book-current` | `*` | `-` | #590 |'
t_has "a key declared twice" "$(viol FL1 "$R5")" "'lint/skill.book-current' is declared twice"
R6="$(lanes_root ticket)"; row "$R6" '| DECIDE | `lint/context.budget-ceiling` | `*` | `-` | soon |'
t_has "a row with no ticket" "$(viol FL1 "$R6")" "cites no ticket"
R7="$(lanes_root norepair)"; row "$R7" '| HEAL | `lint/context.budget-ceiling` | `*` | `-` | #590 |'
t_has "a HEAL row with no repair" "$(viol FL1 "$R7")" "names no repair"
R8="$(lanes_root gone)"; rm -f "$R8/bin/memory-route.sh"
t_has "a HEAL repair whose script is gone" "$(viol FL1 "$R8")" "repairs with bin/memory-route.sh, which does not exist"

t_section "FL1: the contract is the only place a lane is written"
R9="$(lanes_root elsewhere)"; printf '<!-- lanes:begin -->\n| HEAL | `lint/X3` | `*` | `sh x` | #1 |\n<!-- lanes:end -->\n' > "$R9/CONTRACTS/other.md"
t_has "a second declaration" "$(viol FL1 "$R9")" "CONTRACTS/other.md declares lanes"
R10="$(lanes_root twice)"; cat "$R10/CONTRACTS/finding.md" "$R10/CONTRACTS/finding.md" > "$R10/f.md" && mv "$R10/f.md" "$R10/CONTRACTS/finding.md"
t_has "two blocks in the contract" "$(viol FL1 "$R10")" "has 2 lanes blocks"
R11="$TMP/nocontract"; mkdir -p "$R11/bin"; : > "$R11/bin/findings.sh"
t_has "findings.sh with no contract" "$(viol FL1 "$R11")" "CONTRACTS/finding.md does not"

t_section "FL2: every ADVISORY line records its subject"
t_eq "this checkout" 0 "$(vcount "$(lint1 FL2 "$T_ROOT")")"
F2="$TMP/fl2"; mkdir -p "$F2/bin"
printf '%s\n' "_adv drift.sandbox-copy a; printf '  ADVISORY [drift.sandbox-copy] paired\\n'" "  # printf '  ADVISORY [drift.launchd-plist] a comment is not a site'" > "$F2/bin/lint-conventions.sh"
t_eq "a paired line and a comment" 0 "$(vcount "$(lint1 FL2 "$F2")")"
printf '%s\n' "printf '  ADVISORY [drift.sandbox-copy] unpaired\\n'" >> "$F2/bin/lint-conventions.sh"
t_has "an unpaired line" "$(viol FL2 "$F2")" "bin/lint-conventions.sh:3 prints ADVISORY [drift.sandbox-copy]"
printf '%s\n' "_adv drift.config-bin a; echo \"  ADVISORY [drift.sandbox-copy] wrong id\"" > "$F2/bin/lint-conventions.sh"
t_has "a line paired with another rule's id" "$(viol FL2 "$F2")" "prints ADVISORY [drift.sandbox-copy] with no"

t_section "the emitter: records with HARBOR_FINDINGS_OUT, nothing without it"
E="$TMP/emit"; mkdir -p "$E/bin"
{ echo '#!/usr/bin/env sh'; _i=0; while [ "$_i" -lt 330 ]; do echo "echo line $_i"; _i=$((_i + 1)); done; } > "$E/bin/big.sh"
: > "$TMP/emit.tsv"
HARBOR_FINDINGS_OUT="$TMP/emit.tsv" HARBOR_ROOT="$E" sh "$LINT" --only G1 >/dev/null 2>&1
t_eq "the rule that ran, and its subject, under its id" "R lint.long-file-reason|A lint.long-file-reason bin/big.sh|" "$(tr '\t\n' ' |' < "$TMP/emit.tsv")"
t_hasnt "the line count stays in the message" "$(cat "$TMP/emit.tsv")" "330"
t_has "and the census still prints it" "$(lint1 G1 "$E")" "ADVISORY [lint.long-file-reason] bin/big.sh is 330 lines"
t_eq "unset, nothing is written anywhere" "" "$(cd "$E" && HARBOR_ROOT="$E" sh "$LINT" --only G1 >/dev/null 2>&1; find "$E" -newer "$TMP/emit.tsv" -type f)"

t_done
