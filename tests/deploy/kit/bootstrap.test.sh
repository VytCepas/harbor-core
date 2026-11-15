#!/usr/bin/env sh
# A clean box bootstraps a whole system from the core share (harbor#1436): `harbor scope install` creates the private layer, and the
# installer `harbor deploy` runs for the core share (deploy-runtime-install.sh, the one runtime-install.test.sh drives too: the full
# `harbor deploy --apply` refuses a session and a linked worktree) leaves an empty but valid register set: schemas, controls.tsv with
# the core controls, the kit, and the tools that read them. Everything runs in a throwaway HOME and PORT_ROOT; the live box is never read.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
B="$T_ROOT/bin"
HOME="$T/home"; PORT_ROOT="$T/home/port"; CLAUDE_CONFIG_DIR="$T/home/.claude"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"; export HOME PORT_ROOT CLAUDE_CONFIG_DIR
printf '{}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
CFG="$CLAUDE_CONFIG_DIR"

t_section "harbor scope install makes the private layer, empty"
sh "$B/scope.sh" install > "$T/scope.out" 2>&1
t_eq "scope install exits 0" "exit 0" "$(sh "$B/scope.sh" install >/dev/null 2>&1; echo "exit $?")"
t_eq "the registry is a header and nothing else" 1 "$(grep -c . "$PORT_ROOT/harbor-private/repos.tsv")"
t_eq "…and there is one check register, empty" yes "$([ -f "$PORT_ROOT/harbor-private/checks.md" ] && echo yes || echo no)"
t_eq "…and the registry reads as valid" "exit 0" "$(sh "$B/scope-roots.sh" --registry-check >/dev/null 2>&1; echo "exit $?")"

t_section "the core install leaves the core share's registers and tools"
t_eq "the installer exits 0" "exit 0" "$(env -u CLAUDE_CONFIG_DIR sh "$B/deploy-runtime-install.sh" --live --apply >/dev/null 2>&1; echo "exit $?")"
REGS="$CFG/bin/standards/naming"
t_eq "every core-share register is installed (the kit's own list)" "$(sh "$B/standard-kit.sh" --core | sort | tr '\n' ' ')" "$(ls "$REGS" | sort | tr '\n' ' ')"
t_eq "controls.tsv holds the core controls and no hub control" 0 "$(awk -F'\t' '!/^#/ && $1 != "id" { split($1, a, "."); if (a[1] != "name") n++ } END { print n + 0 }' "$REGS/controls.tsv")"
t_eq "…and there are core controls in it" yes "$([ "$(awk -F'\t' '!/^#/ && $1 ~ /^name\./' "$REGS/controls.tsv" | wc -l | tr -d ' ')" -gt 10 ] && echo yes || echo no)"
t_eq "schemas.tsv names only the registers the system holds" 0 "$(awk -F'\t' '!/^#/ && $1 != "id" && $1 !~ /^standards\/naming\// { n++ } END { print n + 0 }' "$REGS/schemas.tsv")"
t_eq "exemptions.tsv carries no legacy row" 0 "$(awk -F'\t' '!/^#/ && $1 != "id"' "$REGS/exemptions.tsv" | wc -l | tr -d ' ')"
for tool in $(sh "$B/standard-kit.sh" --core-tools); do t_eq "the tool $tool is installed" yes "$([ -f "$CFG/bin/$tool" ] && echo yes || echo no)"; done
t_eq "the kit installed with the core share is self-consistent" "exit 0" "$(sh "$CFG/bin/standard-kit.sh" --root "$T/sys" --registry "$REGS" --check >/dev/null 2>&1; echo "exit $?")"

t_section "the installed set is valid: every lint is green on a system built from it"
SYS="$T/sys"; mkdir -p "$SYS/bin"; cp -R "$CFG/bin/standards" "$SYS/standards"
for tool in $(sh "$B/standard-kit.sh" --core-tools); do cp "$CFG/bin/$tool" "$SYS/bin/$tool"; done
LN="sh $CFG/bin/lint-name.sh"
_o="$($LN --root "$SYS" 2>&1)"; _rc=$?
t_eq "lint-name exits 0" 0 "$_rc"
t_has "…with no failure" "$_o" "0 failed"
for cls in standard.register-declared standard.reference-resolves name.control-shape name.registry-shape name.control-unregistered; do t_hasnt "…and no $cls finding" "$_o" "[$cls]"; done
t_eq "the register reader judges every register against its schema" "exit 0" "$(sh "$CFG/bin/standard-register.sh" --root "$SYS" check >/dev/null 2>&1; echo "exit $?")"

t_section "a fixture control with no row turns name.control-unregistered red; its row turns it green"
# A system declares where its controls are found by giving a type a census; the first engine is this fixture's lint rules.
awk -F'\t' -v OFS='\t' '$1 == "lint" { $4 = "lint-rules:bin/lint-conventions.sh" } { print }' "$SYS/standards/naming/registers.tsv" > "$T/registers.new"; cp "$T/registers.new" "$SYS/standards/naming/registers.tsv"
printf '#!/bin/sh\nrule "lint.ghost-rule a rule no row holds"\n' > "$SYS/bin/lint-conventions.sh"
_o="$($LN --root "$SYS" --check registry standards/naming 2>&1)"
t_has "the rule with no row is red" "$_o" "[name.control-unregistered] lint:lint.ghost-rule"
printf 'lint.ghost-rule\twarn\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\ta rule that now has its row\n' >> "$SYS/standards/naming/controls.tsv"
t_hasnt "…and with its row it is not" "$($LN --root "$SYS" --check registry standards/naming 2>&1)" "[name.control-unregistered]"

t_section "a register added with no kit row is red on the box that has the kit"
printf 'standards/naming/ghost.tsv\trow\tid note\tid\t\tstandard\t-\ta register with no kit row\n' >> "$SYS/standards/naming/schemas.tsv"
t_has "the kit check names it" "$(sh "$CFG/bin/standard-kit.sh" --root "$SYS" --registry "$SYS/standards/naming" --check 2>&1)" "register standards/naming/ghost.tsv has no kit row"

t_done
