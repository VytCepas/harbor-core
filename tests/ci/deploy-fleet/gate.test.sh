#!/usr/bin/env sh
# harbor ship against the approval gate's REAL gate-classify.sh and gate-queue.sh (#1127, contract v1.2 §5b.9), not stubs.
# They land in another PR: FX_GATE_SRC names a dir holding them (e.g. a checkout of that branch's bin/); in a tree without
# them the suite says it did not run. Installed under the sandboxed config dir, as gate_init demands.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/deploy-fleet/fixture.sh"
G="${FX_GATE_SRC:-$T_ROOT/bin}"
if [ ! -f "$G/gate-queue.sh" ] || [ ! -f "$G/gate-classify.sh" ] || [ ! -f "$G/gate-lib.sh" ]; then
  t_section "the approval gate's scripts are not in this tree: NOT RUN (FX_GATE_SRC=<dir> runs it)"
  t_eq "gate-queue.sh is absent from $G" absent "$([ -f "$G/gate-queue.sh" ] && echo present || echo absent)"
  t_done
fi
real_gate() { for _f in gate-classify.sh gate-queue.sh gate-lib.sh; do cp "$G/$_f" "$CLAUDE_CONFIG_DIR/bin/$_f"; done
  cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/fs-lib.sh" "$T_ROOT/bin/event-bus.sh" "$CLAUDE_CONFIG_DIR/bin/"; chmod +x "$CLAUDE_CONFIG_DIR"/bin/*.sh; }
Q="$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR" && pwd -P)/bin/gate-approve.sh"

t_section "night 1 through the real gate: a protected PR and the first deploy are queued by gate-queue.sh"
fx_world; real_gate; fx_pr api 11 src/a.txt alpha; fx_pr api 12 secrets/key hunter2; H12="$(fx_tip api pr-12)"
t_eq "exit 0" 0 "$(ship night)"
t_eq "the unprotected PR merged, the protected one did not" "merge api #11 " "$(fx_merged)"
M1="$(fx_tip api)"
t_eq "the real queue holds both, with the contract's ids" "deploy-acme_api-$(echo "$M1" | cut -c1-12) merge-acme_api-12-$(echo "$H12" | cut -c1-12)" \
  "$(fx_queue | jq -r .id | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "...and the gate's own approve command for the merge" "$Q merge acme/api 12 $H12" "$(fx_queue | jq -r 'select(.kind == "merge") | .command')"
t_has "the report's command is the same string" "$(fx_report)" "\`$Q merge acme/api 12 $H12\` (queue id merge-acme_api-12-"
t_eq "each add is an approval.open on the bus" 2 "$(cat "$T_TMP"/events/*.jsonl | jq -r 'select(.kind == "approval.open") | .subject' | grep -c .)"
t_eq "a second night queues nothing twice" "0 2" "$(ship night) $(fx_queue | jq -r .id | sort -u | grep -c .)"

t_section "the real classifier reads the register the runner took from origin: docs/* added on main protects docs/x.md"
fx_world; real_gate; fx_git web "protect docs" sh -c 'printf "docs/*\tdocs\treview\n" >> .agents/protected-paths.tsv'; fx_pr web 22 docs/x.md d
t_eq "exit 0" 0 "$(ship night)"
t_eq "not merged" "" "$(fx_merged)"
t_has "queued as protected by origin's register" "$(fx_report)" "docs/x.md (docs)"
t_done
