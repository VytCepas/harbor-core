#!/usr/bin/env sh
# The three rules harbor#1430 and #1436 add, born warn: context.repo-sources-agree, standard.kit-complete and scope.system-register.
# Each is shown red on a fixture that breaks what it guards and green once restored; the deeper cases are in the suites named by the
# controls' red_proof (tests/scope/repo/sources.test.sh, tests/standard/kit/kit.test.sh, tests/scope/system/system.test.sh).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
M="$T/mini"; mkdir -p "$M/bin" "$M/contracts" "$M/standards/naming"
cp "$T_ROOT"/bin/*.sh "$T_ROOT/bin/harbor" "$M/bin/"; cp "$T_ROOT"/contracts/roots.tsv "$T_ROOT"/contracts/systems.tsv "$M/contracts/"; cp "$T_ROOT"/standards/naming/*.tsv "$M/standards/naming/"

t_section "standard.kit-complete: a register with no kit row is red, its row green"
t_hasnt "the real registers: no advisory" "$(lint1 standard.kit-complete "$M")" "ADVISORY"
cp "$M/standards/naming/schemas.tsv" "$T/schemas.keep"
printf 'standards/naming/ghost.tsv\trow\tid note\tid\t\tstandard\t-\ta register with no kit row\n' >> "$M/standards/naming/schemas.tsv"
t_has "a schema row with no kit row is red" "$(lint1 standard.kit-complete "$M")" "ADVISORY [standard.kit-complete] register standards/naming/ghost.tsv has no kit row"
cp "$T/schemas.keep" "$M/standards/naming/schemas.tsv"
t_hasnt "restored, green" "$(lint1 standard.kit-complete "$M")" "ADVISORY"

t_section "scope.system-register: a row that shadows a frozen verb is red, removed green"
t_hasnt "the real register: no advisory" "$(lint1 scope.system-register "$M")" "ADVISORY"
printf 'status\tx\tbin:status-generate.sh\tno\ts\n' >> "$M/contracts/systems.tsv"
t_has "a system named like a verb is red" "$(lint1 scope.system-register "$M")" "ADVISORY [scope.system-register] system status shadows"
cp "$T_ROOT/contracts/systems.tsv" "$M/contracts/systems.tsv"
t_hasnt "restored, green" "$(lint1 scope.system-register "$M")" "ADVISORY"

t_section "context.repo-sources-agree: a repo missing from a source is red, restored green"
PORT_ROOT="$T/port"; export PORT_ROOT; PV="$PORT_ROOT/harbor-private"; mkdir -p "$PV/context-rules/user" "$PORT_ROOT/solo/.agents" "$PORT_ROOT/solo/.claude"
: > "$PORT_ROOT/solo/.agents/config.yaml"
printf '#!/bin/sh\n[ "$1" = projects ] && printf "solo  (none, %s)\\n" "%s"\nexit 0\n' '%s' "$PORT_ROOT/solo" > "$T/fleet"; chmod +x "$T/fleet"; HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$T/fleet"; export HARBOR_SCOPE_FLEET_CONTROLLER_BIN
printf 'id\tpath\tkind\tremote\ttopology\tinteraction\tnote\tdomain\tgoverned\towner\tcovers\nsolo\tsolo\tworkload\t-\t-\t-\t-\t-\tyes\t-\twhy solo exists\n' > "$PV/repos.tsv"
printf 'solo\t~/port/solo\twhy solo exists\n' > "$PV/context-rules/user/projects.tsv"; : > "$PORT_ROOT/solo/.claude/project-init.md"
t_hasnt "four sources agree: no advisory" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY"
rm "$PORT_ROOT/solo/.claude/project-init.md"
t_has "a governed repo with no marker is red" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY [context.repo-sources-agree] solo present: registry,projects.tsv,fleet, missing: marker"
: > "$PORT_ROOT/solo/.claude/project-init.md"
t_hasnt "restored, green" "$(lint1 context.repo-sources-agree "$M")" "ADVISORY"

t_done
