#!/usr/bin/env sh
# lint.review-config-shape (harbor#1497, B3): each refusal goes red on its own fixture, valid-but-unusual blocks stay green,
# and the rule in lint-conventions turns a bad .agents/config.yaml into a finding at the row's mode.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
CHECK="$T_ROOT/bin/audit-review-config.sh"; RP="$T_TMP/rc"
chk() { printf '%s\n' "$1" > "$RP.yaml"; sh "$CHECK" check "$RP.yaml" 2>&1; }
refused() { _o="$(chk "$2")"; t_has "refused: $1" "$_o" "$3"; }
clean() { t_eq "clean: $1" 0 "$(chk "$2" | grep -c 'FAIL:')"; }

t_section "malformed blocks are red, each for its own reason"
refused "an unknown key" 'review:
  tierr: deep' 'unknown key: tierr'
refused "a tier outside the list" 'review:
  tier: huge' 'tier: not quick'
refused "verify off" 'review:
  verify: off' 'verify: off is refused'
refused "verify false" 'review:
  verify: false' 'verify: off is refused'
refused "verify with another word" 'review:
  verify: maybe' 'verify: not on'
refused "zero lenses, standard" 'review:
  standard-lenses: 0' '0 lenses is refused'
refused "zero lenses, quick" 'review:
  quick-lenses: 0' 'quick-lenses: 0 lenses'
refused "more lenses than exist" 'review:
  deep-lenses: 7' 'more than 6'
refused "a non-numeric lens count" 'review:
  deep-lenses: many' 'not an integer'
refused "a non-numeric cap" 'review:
  max-inline: lots' 'max-inline: not an integer'
refused "a cap past 50" 'review:
  max-inline: 51' 'max-inline: not an integer'
refused "a negative line threshold" 'review:
  quick-under-lines: -1' 'quick-under-lines: not a non-negative'
refused "a wildcard author" 'review:
  exclude-authors:
    - "*[bot]"' 'is a wildcard'
refused "a bare star author" 'review:
  exclude-authors:
    - "*"' 'is a wildcard'
refused "an author with a space" 'review:
  exclude-authors:
    - dependa bot' 'is not a login'
refused "an unbalanced glob" 'review:
  docs-paths:
    - "docs/[a"' 'unbalanced ['
refused "a glob that matches every path" 'review:
  generated-paths:
    - "*"' 'matches every path'
refused "an absolute glob" 'review:
  deep-paths:
    - /etc/*' 'starts with /'
refused "a glob that climbs" 'review:
  docs-paths:
    - ../x' 'holds ..'
refused "an empty list item" 'review:
  docs-paths:
    -' 'an empty item'
refused "an inline list with items" 'review:
  docs-paths: [a, b]' 'a list is block items'
refused "a repeated key" 'review:
  tier: deep
  tier: quick' 'set twice'
refused "a repeated block" 'review:
  tier: deep
review:
  tier: quick' 'review: appears twice'
refused "an inline block value" 'review: deep' 'inline value'
refused "a tab indent" 'review:
	tier: deep' 'tab indents'
refused "a wrong indent" 'review:
    tier: deep' 'indent is 2 spaces'
refused "an item outside a list" 'review:
  - dependabot' 'outside a list'
t_has "refused: a file that is not there" "$(sh "$CHECK" check "$RP.absent" 2>&1)" 'no such file'

t_section "valid but unusual input stays green"
clean "a login with brackets" 'review:
  exclude-authors:
    - dependabot[bot]
    - renovate[bot]'
clean "empty excludes" 'review:
  exclude-authors: []
  docs-paths: []
  generated-paths: []'
clean "an empty block" 'review: {}'
clean "no block at all" 'context: repo
scope: project'
clean "a block with only comments" 'review:
  # nothing set'
clean "quoted values and trailing comments" 'review:
  tier: "deep"  # strict
  exclude-authors:
    - "svc-acct"  # service account'
clean "a cap of zero" 'review:
  max-inline: 0'
clean "one lens everywhere (a lens and a verifier, not zero)" 'review:
  quick-lenses: 1
  standard-lenses: 1
  deep-lenses: 1
  verify: on'
clean "a glob with a class" 'review:
  generated-paths:
    - "src/gen[0-9]/*"'
clean "keys around the block" 'context: repo
review:
  tier: quick
scope: project'
t_exit "clean exits 0" 0 sh "$CHECK" check "$T_ROOT/.agents/config.yaml"
chk 'review:
  verify: off' >/dev/null
t_exit "a finding exits 1" 1 sh "$CHECK" check "$RP.yaml"
t_exit "no file named exits 2" 2 sh "$CHECK" check

t_section "the rule: a bad .agents/config.yaml is a finding at the row's mode"
reg() { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\nlint.review-config-shape\t%s\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\tfixture\n' "$1" > "$RP.reg"; }
runr() { reg "$1"; HARBOR_LINT_CONTROLS="$RP.reg" HARBOR_SCOPE_ROOT="$2" sh "$LINT" --only lint.review-config-shape 2>&1; printf 'exit=%s\n' "$?"; }
fx() { rm -rf "$1"; mkdir -p "$1/.agents"; printf '%s\n' "$2" > "$1/.agents/config.yaml"; }
fx "$RP.a" 'review:
  verify: off'
_o="$(runr block "$RP.a")"
t_has "block: the finding fails the run" "$_o" 'VIOLATION [lint.review-config-shape]'
t_has "block: it names the reason" "$_o" 'verify: off is refused'
t_has "block: exit 1" "$_o" 'exit=1'
_o="$(runr warn "$RP.a")"
t_has "warn: an advisory" "$_o" 'ADVISORY [lint.review-config-shape]'
t_has "warn: exit 0" "$_o" 'exit=0'
fx "$RP.b" 'review:
  exclude-authors:
    - dependabot[bot]'
_o="$(runr block "$RP.b")"
t_hasnt "a valid block has no finding" "$_o" '[lint.review-config-shape]'
t_has "a valid block exits 0" "$_o" 'exit=0'
rm -rf "$RP.c"; mkdir -p "$RP.c"
_o="$(runr block "$RP.c")"
t_hasnt "no config file, no finding" "$_o" 'VIOLATION [lint.review-config-shape]'
t_has "no config file exits 0" "$_o" 'exit=0'
t_red lint.review-config-shape
t_done
