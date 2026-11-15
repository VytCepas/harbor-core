#!/usr/bin/env sh
# `harbor <system> <verb>` dispatched by register (harbor#1436): a system is a row of contracts/systems.tsv, so a fixture system with one
# verb row is callable without editing bin/harbor; `harbor yard <verb>` and `harbor fleet <verb>` pass through to their own CLIs and
# exit with the tool's code; the cli-tree render lists the dispatch table; lint.cli-contract stays green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
H="sh $T_ROOT/bin/harbor"; SS="$T_ROOT/bin/scope-system.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
out() { "$@" 2>&1; }
code() { "$@" >/dev/null 2>&1; echo "exit $?"; }

# Stubs for the two real CLIs: they print their argv and exit with the code the case chose.
mkdir -p "$T/stubs"
printf '#!/bin/sh\nprintf "yard-cli %%s\\n" "$*"\nexit "${STUB_RC:-0}"\n' > "$T/stubs/project-init"
printf '#!/bin/sh\nprintf "fleet-cli %%s\\n" "$*"\nexit "${STUB_RC:-0}"\n' > "$T/stubs/projects-orchestrator"
printf '#!/bin/sh\nprintf "demo-tool %%s\\n" "$*"\nexit 3\n' > "$T/stubs/demo"
chmod +x "$T/stubs/"*
export HARBOR_SCOPE_SCAFFOLDER_BIN="$T/stubs/project-init" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$T/stubs/projects-orchestrator"

t_section "harbor yard <verb> and harbor fleet <verb> pass through, with the tool's own exit code"
t_eq "harbor yard new --dry-run runs the scaffolder's new with the flag" "yard-cli new --dry-run" "$(out $H yard new --dry-run)"
t_eq "harbor fleet audit runs the fleet CLI's audit" "fleet-cli audit" "$(out $H fleet audit)"
t_eq "an unlisted yard verb goes through whole (the * row)" "yard-cli doctor --strict" "$(out $H yard doctor --strict)"
t_eq "arguments keep their words intact" "fleet-cli audit a b --root /x y" "$(out $H fleet audit a b --root '/x y')"
t_eq "the tool's exit 0 is ours" "exit 0" "$(STUB_RC=0 code $H fleet audit)"
t_eq "…its exit 1 is ours" "exit 1" "$(STUB_RC=1 code $H fleet audit)"
t_eq "…and its exit 4 is ours, not remapped" "exit 4" "$(STUB_RC=4 code $H yard new --dry-run)"
t_eq "--json is refused where the row says no" "exit 2" "$(code $H yard doctor --json)"
t_has "…and the refusal says so" "$(out $H yard doctor --json)" "has no --json"
t_eq "…and passed on where the row says yes (fleet)" "fleet-cli audit --json" "$(out $H fleet audit --json)"
t_eq "yard new takes --json (its row says yes)" "yard-cli new x --json" "$(out $H yard new x --json)"
t_eq "a tool that is not installed is 127 with the fix" "exit 127" "$(HARBOR_SCOPE_SCAFFOLDER_BIN="$T/stubs/missing" code $H yard new)"
t_has "…and names the root to look at" "$(HARBOR_SCOPE_SCAFFOLDER_BIN="$T/stubs/missing" out $H yard new)" "sh $T_ROOT/bin/scope-roots.sh --get HARBOR_SCOPE_SCAFFOLDER_BIN"

t_section "a fixture system with one verb row is callable without editing bin/harbor"
printf 'system\tverb\trun\tjson\tsummary\ndemo\thello\ttool:DEMO_TOOL say\tno\ta fixture system\n' > "$T/systems.tsv"
export HARBOR_SCOPE_SYSTEMS_TABLE="$T/systems.tsv" DEMO_TOOL="$T/stubs/demo"
t_eq "harbor demo hello runs the row's command, the row's fixed word first" "demo-tool say a b" "$(out $H demo hello a b)"
t_eq "…and its exit status is ours" "exit 3" "$(code $H demo hello)"
t_eq "a verb the system has no row for is a usage error" "exit 2" "$(code $H demo goodbye)"
t_has "…that lists the verbs it has" "$(out $H demo goodbye)" "has no verb 'goodbye' (it has: hello"
t_has "harbor help lists the registered system" "$(out $H help)" "demo "
t_eq "bin/harbor was not edited for it: the word is no verb of its table" 0 "$(grep -c '^demo' "$T_ROOT/bin/harbor" || :)"
t_eq "a word that is neither a verb nor a system is still unknown" "exit 2" "$(code $H nosuch)"
unset HARBOR_SCOPE_SYSTEMS_TABLE DEMO_TOOL

t_section "the private layer may add a system and never replace a row"
export PORT_ROOT="$T/pr"; mkdir -p "$PORT_ROOT/harbor-private"
printf 'system\tverb\trun\tjson\tsummary\nlab\tping\ttool:DEMO_TOOL ping\tno\ta workload system\nyard\tnew\ttool:DEMO_TOOL hijack\tno\tnot allowed to replace\n' > "$PORT_ROOT/harbor-private/systems.tsv"
export DEMO_TOOL="$T/stubs/demo"
t_eq "the private row is callable" "demo-tool ping" "$(out $H lab ping)"
t_eq "…and does not replace core's row for the same system and verb" "yard-cli new" "$(out $H yard new)"
unset DEMO_TOOL PORT_ROOT

t_section "the register is checked: a row that resolves nothing, repeats or shadows a verb is red"
t_eq "the real register is green" "exit 0" "$(code sh "$SS" --check)"
chk() { printf 'system\tverb\trun\tjson\tsummary\n%s\n' "$1" > "$T/bad.tsv"; HARBOR_SCOPE_SYSTEMS_TABLE="$T/bad.tsv" sh "$SS" --check 2>&1; }
t_has "a system named like a frozen verb" "$(chk 'status	x	bin:status-generate.sh	no	s')" "system status shadows the frozen harbor verb"
t_has "a repeated system and verb" "$(chk 'zed	a	bin:status-generate.sh	no	s
zed	a	bin:status-generate.sh	no	s')" "zed a is registered twice"
t_has "a bin script that is not there" "$(chk 'zed	a	bin:no-such.sh	no	s')" "bin script no-such.sh does not exist"
t_has "a root that roots.tsv lacks" "$(chk 'zed	a	tool:HARBOR_SCOPE_NO_SUCH_ROOT	no	s')" "root HARBOR_SCOPE_NO_SUCH_ROOT is not a row of roots.tsv"
t_has "a run cell that is neither" "$(chk 'zed	a	curl evil	no	s')" "neither bin:<script> nor tool:<VAR>"
t_has "a json cell outside yes and no" "$(chk 'zed	a	bin:status-generate.sh	maybe	s')" "json is maybe"

t_section "the lint rule scope.system-register reads the same verdict; lint.cli-contract stays green"
. "$T_ROOT/tests/checks/lint-fixture.sh"
M="$T/mini"; mkdir -p "$M/bin" "$M/contracts" "$M/standards/naming"; cp "$T_ROOT"/bin/*.sh "$T_ROOT/bin/harbor" "$M/bin/"; cp "$T_ROOT"/contracts/roots.tsv "$T_ROOT"/contracts/systems.tsv "$T_ROOT/contracts/cli.md" "$M/contracts/"; cp "$T_ROOT"/standards/naming/*.tsv "$M/standards/naming/"
t_eq "scope.system-register is green on the real table" 0 "$(vcount "$(lint1 scope.system-register "$M")")"
t_hasnt "…with no advisory" "$(lint1 scope.system-register "$M")" "ADVISORY"
printf 'status\tx\tbin:status-generate.sh\tno\ts\n' >> "$M/contracts/systems.tsv"
t_has "a system shadowing a verb is an advisory" "$(lint1 scope.system-register "$M")" "ADVISORY [scope.system-register] system status shadows"
cp "$T_ROOT/contracts/systems.tsv" "$M/contracts/systems.tsv"
t_eq "lint.cli-contract is green with the systems register in place" 0 "$(vcount "$(lint1 CLI1 "$M")")"
cp "$T_ROOT/bin/harbor" "$T/harbor.keep"
grep -v '^repo	' "$T_ROOT/bin/harbor" > "$M/bin/harbor"
t_has "…and red when a verb is taken out of the dispatcher (the control)" "$(lint1 CLI1 "$M")" "VIOLATION [lint.cli-contract]"

t_section "the cli-tree render lists the dispatch table"
cp "$T_ROOT/bin/harbor" "$M/bin/harbor"
sh "$M/bin/lint-name.sh" --gen cli-tree --root "$M" >/dev/null 2>&1
_tree="$(cat "$M/build/naming/cli-tree.txt")"
t_has "yard's new" "$_tree" "harbor yard new    <- tool:HARBOR_SCOPE_SCAFFOLDER_BIN new"
t_has "fleet's pass-through" "$_tree" "harbor fleet <verb>    <- tool:HARBOR_SCOPE_FLEET_CONTROLLER_BIN"
t_has "scope-system.sh tree prints the same rows" "$(out sh "$SS" tree)" "harbor fleet <verb> [--json]    <- tool:HARBOR_SCOPE_FLEET_CONTROLLER_BIN"

t_done
