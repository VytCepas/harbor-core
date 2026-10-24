#!/usr/bin/env sh
# runners/linux: the entrypoint's contract with the provisioning lane, and what the image must carry (harbor#1060).
# The entrypoint runs against stub config.sh/run.sh in a throwaway RUNNER_HOME, so no docker and no GitHub.
. "$(dirname "$0")/../lib/core.sh"; t_init
DF="$T_ROOT/runners/linux/Dockerfile"; EP="$T_ROOT/runners/linux/entrypoint.sh"
H="$T_TMP/home"; LOG="$T_TMP/log"

fresh() { # a runner home with stubs; config.sh logs its argv and writes .runner, run.sh logs its env
  rm -rf "$H" "$LOG"; mkdir -p "$H"
  printf '#!/bin/sh\necho "config $*" >> "%s"\n: > .runner\n' "$LOG" > "$H/config.sh"
  printf '#!/bin/sh\necho "run token=${RUNNER_TOKEN:-unset}" >> "%s"\n' "$LOG" > "$H/run.sh"
  chmod +x "$H/config.sh" "$H/run.sh"
}
ep() { env -u RUNNER_URL -u RUNNER_NAME -u RUNNER_LABELS -u RUNNER_TOKEN RUNNER_HOME="$H" "$@" sh "$EP" 2>&1; }

t_section "the files exist and are the runner image's source"
t_eq "the Dockerfile is tracked" yes "$([ -f "$DF" ] && echo yes)"
t_eq "the entrypoint is tracked" yes "$([ -f "$EP" ] && echo yes)"
[ -f "$EP" ] || { t_done; exit; }

t_section "defaults: the harbor runner, with only the token supplied"
fresh; ep RUNNER_TOKEN=tok >/dev/null
t_has "url defaults to the harbor repo" "$(cat "$LOG")" "--url https://github.com/VytCepas/harbor "
t_has "name defaults to harbor-linux" "$(cat "$LOG")" "--name harbor-linux "
t_has "labels default to self-hosted,Linux,ARM64" "$(cat "$LOG")" "--labels self-hosted,Linux,ARM64 "
t_has "no default labels, so the label list is exactly ours" "$(cat "$LOG")" "--no-default-labels"
t_has "the token reaches config.sh" "$(cat "$LOG")" "--token tok "

t_section "every parameter is overridable"
fresh; ep RUNNER_TOKEN=t2 RUNNER_URL=https://github.com/o/r RUNNER_NAME=r-linux RUNNER_LABELS=self-hosted,Linux >/dev/null
t_has "url" "$(cat "$LOG")" "--url https://github.com/o/r "
t_has "name" "$(cat "$LOG")" "--name r-linux "
t_has "labels" "$(cat "$LOG")" "--labels self-hosted,Linux "

t_section "the token is for the first configure only"
t_has "run.sh does not see it" "$(cat "$LOG")" "run token=unset"
n() { cat "$LOG" 2>/dev/null | grep -c "^$1 " || :; }  # how many times the stub $1 was called
t_eq "a restart with .runner present does not configure again" 1 "$(ep RUNNER_TOKEN=tok >/dev/null; n config)"
t_eq "and a restart needs no token at all" 3 "$(ep >/dev/null; n run)"
fresh; out="$(ep)"
t_eq "first start with no token configures nothing" 0 "$(n config)"
t_eq "and never runs" 0 "$(n run)"
t_has "and says which variable is missing" "$out" "RUNNER_TOKEN"

t_section "the runner home defaults to the runner user's HOME, so the image needs no path baked in"
fresh; env -u RUNNER_URL -u RUNNER_NAME -u RUNNER_LABELS -u RUNNER_HOME HOME="$H" RUNNER_TOKEN=tok sh "$EP" > /dev/null 2>&1
t_eq "with RUNNER_HOME unset it configures and runs from HOME" "1 1" "$(n config) $(n run)"

t_section "the image carries what the suites and the setup actions need, with no job-time install"
d="$(cat "$DF")"; apt="$(grep "apt-get install" "$DF") "
t_has "built on the official runner" "$d" "FROM ghcr.io/actions/actions-runner"
t_has "runs as the runner user" "$d" "USER runner"
t_has "the entrypoint is the contract file" "$d" 'ENTRYPOINT ["/entrypoint.sh"]'
for p in jq dash shellcheck git perl gawk curl ca-certificates python3 procps util-linux file xz-utils unzip zstd; do
  t_has "apt carries $p" "$apt" " $p "
done
t_has "node, for bin/browser-*.mjs" "$d" "nodejs.org/dist"
t_has "gitleaks, for the governance preflight" "$d" "gitleaks"
# Scaffolded validate-pr jobs and project-init's suite call gh; the scaffold's hook needs `gitleaks git` (8.19+).
t_has "gh, pinned and checksummed per architecture" "$d" 'gh_${GH_VERSION}_linux_${gh_arch}.tar.gz'
t_eq "gh is checksummed for both architectures" 2 "$(grep -c 'gh_sha=[0-9a-f]\{64\}' "$DF")"
gl="$(sed -n 's/^ARG GITLEAKS_VERSION=\([0-9]*\)\.\([0-9]*\)\..*/\1 \2/p' "$DF")"
t_eq "gitleaks is 8.19 or newer (has the git subcommand)" yes "$(echo "$gl" | awk '{print ($1 > 8 || ($1 == 8 && $2 >= 19)) ? "yes" : "no"}')"
t_eq "the base is the only FROM" 1 "$(grep -c "^FROM" "$DF")"

t_section "no suite is macOS-only: the runner is gone and browser-test runs in the Linux pool (harbor#1060)"
t_eq "browser-test is in the manifest the pool runs" 1 "$(grep -c '^tests/cli/browser-test.sh' "$T_ROOT/CONTRACTS/suites.txt")"

t_section "browser-test on a host with no node: the node arms skip loudly, the rest still runs (harbor#1060)"
. "$T_ROOT/tests/lib/linux-sim.sh"; linux_path "$T_TMP/nonode" node
NN="$(env PATH="$T_TMP/nonode" /bin/sh "$T_ROOT/tests/cli/browser-test.sh" 2>&1; echo "RC=$?")"
t_has "it passes, not fails, where the image has no node yet" "$NN" "RC=0"
t_has "and the skip names node" "$NN" "SKIP the node arms: no node on PATH"
t_has "and the arms that need no node still ran" "$NN" "agent: the guardrails"
t_done
