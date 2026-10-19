#!/usr/bin/env sh
# bin/ci-runners.sh past one runner a repo (harbor#1060): governance N, org runners N, a hold on an org, memory and cpu limits per
# runner, and the memory budget against the VM. Split from tests/ci/ci-runners-test.sh at the 500-line budget (tests/README.md T2);
# the same stubbed gh and docker, from tests/ci/ci-runners-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
row() { jq -r --arg r "$1" ".[] | select(.repo == \$r) | $2" "$FX/list.json"; }
list() { run list --json > "$FX/list.json"; }
hold() { printf 'hold held other-mac serves it until its suites pass on Linux\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
cfg() { printf '%s\n' "$@" >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
# RH: the image user's HOME, never spelt whole: on CI it is $HOME, and lint.no-home-path greps for that
MROOT="$(cd -P "$T_TMP" && pwd -P)"; MH="$MROOT/home"; RU=runner; RH="/home/$RU"; mkdir -p "$MH/.claude/skills/topology" "$MH/port/harbor"
EV2="$T_TMP/gov-events-real"; mkdir -p "$EV2"
gfx() { reset; hold; container harbor-linux port-linux-runner:local running; stale harbor-linux; runner harbor online false 55
        printf '4294967296\n' > "$FX/memory.harbor-linux"; printf '%s\n' "$EV2" > "$FX/events.harbor-linux"; }
t_section "governance N: a second runner, harbor-linux-2, made as harbor-linux is (harbor#1060)"
CONFF="$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
g2() { printf '{"runners":[{"id":55,"name":"harbor-linux","status":"online","busy":%s,"labels":[{"name":"self-hosted"}]}%s]}\n' "${1:-false}" "${2:-}" > "$FX/runners/harbor.json"; }
rname() { grep -c -e "--name $1 " "$FX/docker.log" || true; }
gfx; g2; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; run list > "$FX/n1.default"; run up > "$FX/n1.up"
printf 'governance 1\n' >> "$CONFF"; run list > "$FX/n1.one"; run up > "$FX/n1.up1"
t_eq "governance 1 lists exactly as no governance line" 0 "$(cmp -s "$FX/n1.default" "$FX/n1.one"; echo $?)"
t_eq "...and up says the same" 0 "$(cmp -s "$FX/n1.up" "$FX/n1.up1"; echo $?)"
t_eq "...one governance row" 1 "$(grep -c governance "$FX/n1.one" || true)"
t_eq "a governance value that is no digit 1-9 is 1" 1 "$(gfx; g2; printf 'governance two\n' >> "$CONFF"; list; jq '[.[] | select(.governance)] | length' "$FX/list.json")"
gfx; g2; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; printf 'governance 2\n' >> "$CONFF"; list
t_eq "governance 2: list has both governance rows" "harbor:harbor-linux harbor-2:harbor-linux-2" "$(jq -r '[.[] | select(.governance) | "\(.repo):\(.name)"] | join(" ")' "$FX/list.json")"
t_eq "...harbor-linux-2 absent, not wanted as a fleet repo" "absent false" "$(row harbor-2 '"\(.container) \(.want)"')"
OUT="$(run up --include-governance)"; RC=$?
t_has "the dry run says what it would create, as harbor-linux has it" "$OUT" "would create harbor-linux-2 for VytCepas/harbor: labels self-hosted,Linux,ARM64,harbor-pool, image port-linux-runner:local, cpus 1, memory 4294967296b, events $EV2:/gov-events"
t_eq "...touches nothing, asks for no token, exits 0" "0 0 0" "$(rname harbor-linux-2) $(nlines "$FX/token.asked") $RC"
gfx; g2; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; run up --apply >/dev/null
t_eq "without governance N, up --apply never makes it, and with N=1 nothing" 0 "$(rname harbor-linux-2)"
printf 'governance 2\nlinux_min 3\n' > /dev/null
gfx; g2; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; printf 'governance 2\n' >> "$CONFF"; printf 'linux_min = 2\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
OUT="$(run up --apply --include-governance)"; RC=$?
rm -f "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
RUNLINE="$(grep '^run -d.*--name harbor-linux-2 ' "$FX/docker.log")"
t_eq "up --apply --include-governance creates harbor-linux-2 once and leaves harbor-linux alone" "1 0 0" "$(rname harbor-linux-2) $(grep -c -e '^rm -f harbor' -e '^stop harbor' "$FX/docker.log" || true) $(nlines "$FX/deletes.log")"
t_has "...named harbor-linux-2" "$RUNLINE" "--name harbor-linux-2 "
t_has "...restart policy, linux_min as cpus, harbor-linux's memory" "$RUNLINE" "--restart unless-stopped --cpus 2 --memory 4294967296b"
t_has "...the events mount harbor-linux has, so the governor's trigger file sees its job events" "$RUNLINE" "-v $EV2:/gov-events"
t_has "...the job-started hook" "$RUNLINE" "-e ACTIONS_RUNNER_HOOK_JOB_STARTED=/gov-events/ci-governor-hook.sh"
t_has "...the job-completed hook" "$RUNLINE" "-e ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh"
t_has "...on the configured tag" "$RUNLINE" "port-linux-runner:local"
t_eq "...with no other bind" "$EV2:/gov-events" "$(printf '%s\n' "$RUNLINE" | grep -o -e '-v [^ ]*' | sed 's/^-v //')"
t_has "...RUNNER_NAME=harbor-linux-2" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=harbor-linux-2"
t_has "...registered on the governance repo" "$(cat "$FX/envfile.captured")" "RUNNER_URL=https://github.com/VytCepas/harbor"
t_has "...with the same labels" "$(cat "$FX/envfile.captured")" "RUNNER_LABELS=self-hosted,Linux,ARM64"
t_eq "...a token for harbor, env file mode 600" "1 600" "$(grep -c '^harbor$' "$FX/token.asked") $(cat "$FX/envfile.mode")"
t_hasnt "...no token on an argv or the screen" "$(cat "$FX/docker.log" "$FX/gh.log") $OUT" "TOKEN-SECRET"
t_has "...one checks.log line" "$(cat "$CACHE/checks.log")" "harbor-linux-2 created for VytCepas/harbor"
t_eq "...exits 0" 0 "$RC"
run up --apply --include-governance >/dev/null
t_eq "a second run adopts it: no second create" 1 "$(rname harbor-linux-2)"
t_eq "a stopped harbor-linux-2 is started, not recreated" "start harbor-linux-2" "$(gfx; g2; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; printf 'governance 2\n' >> "$CONFF"; container harbor-linux-2 port-linux-runner:local exited; run up --apply --include-governance >/dev/null; grep '^start' "$FX/docker.log")"
t_eq "up --include-governance leaves a busy runner alone" 0 "$(gfx; g2 false ',{"id":56,"name":"harbor-linux-2","status":"online","busy":true,"labels":[]}'; printf 'governance 2\n' >> "$CONFF"; container harbor-linux-2 port-linux-runner:local exited; run up --apply --include-governance >/dev/null; grep -c '^start harbor-linux-2' "$FX/docker.log" || true)"

gfx2() { gfx; g2; container harbor-linux-2 port-linux-runner:local running; stale harbor-linux-2; printf '4294967296\n' > "$FX/memory.harbor-linux-2"
         printf '%s\n' "$EV2" > "$FX/events.harbor-linux-2"; printf 'governance 2\n' >> "$CONFF"
         printf '{"runners":[{"id":55,"name":"harbor-linux","status":"online","busy":false,"labels":[]},{"id":56,"name":"harbor-linux-2","status":"online","busy":%s,"labels":[]}]}\n' "${1:-false}" > "$FX/runners/harbor.json"; }
gfx2; OUT="$(run refresh --apply --include-governance)"; RC=$?
t_eq "refresh --include-governance recreates both stale idle rows, each once" "rm -f harbor-linux rm -f harbor-linux-2 2" "$(grep '^rm ' "$FX/docker.log" | tr '\n' ' ')$(grep -c '^run -d' "$FX/docker.log")"
t_eq "...deleting each old registration by its id" "55 56" "$(sed 's#.*runners/##' "$FX/deletes.log" | tr '\n' ' ' | sed 's/ $//')"
t_eq "...each registered under its own name" 1 "$(rname harbor-linux-2)"
t_eq "...exits 0" 0 "$RC"
gfx2 true; run refresh --apply --include-governance >/dev/null
t_eq "a busy harbor-linux-2 is skipped, harbor-linux is still recreated" "rm -f harbor-linux 1" "$(grep '^rm ' "$FX/docker.log") $(grep -c '^run -d' "$FX/docker.log")"
gfx2; mkdir -p "$FX/queue"; echo '{"workflow_runs":[{"id":903}]}' > "$FX/queue/harbor.queued.json"; run refresh --apply --include-governance >/dev/null
t_eq "a queued harbor run holds both rows back" 0 "$(grep -c -e '^rm ' -e '^run ' "$FX/docker.log" || true)"
gfx2; OUT="$(run refresh --include-governance)"
t_has "the refresh dry run names harbor-linux-2 too" "$OUT" "would recreate harbor-linux-2 for VytCepas/harbor"
t_eq "down of a governance row is refused, naming the operator's way" "2" "$(run down harbor-2 --apply >/dev/null; echo $?)"
t_has "...with the command" "$(run down harbor-2 --apply)" "docker rm -f harbor-linux-N"
t_eq "...and touches nothing" 0 "$(grep -c -e '^rm ' "$FX/docker.log" || true)"
gfx2; run up --apply >/dev/null; run switch --apply >/dev/null; run tick >/dev/null
t_eq "up, switch and tick never act on harbor-linux-2 without the flag" 0 "$(grep -c -e '^rm -f harbor-linux-2' -e '^run .*--name harbor-linux-2 ' -e '^start harbor-linux-2' "$FX/docker.log" || true)"
t_eq "...the cache does not name it" "" "$(jq -r '[.ok, .missing, .offline, .stopped, .held, .extra] | add | map(select(startswith("harbor"))) | join(" ")' "$CACHE/ci-runners.json")"
t_eq "...no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "org runners N: <org>-linux, <org>-linux-2, each registered at the org (harbor#1060, 2026-10-13)"
# o2 [N] — SomeOrg on `runners N` (default 2), every repo runner present so only org runners can be made; someorg-linux exists
o2() { reset; hold; printf 'org SomeOrg 2000 runners %s\n' "${1:-2}" >> "$CONFF"
       container alpha-linux port-linux-runner:local running; runner alpha online false
       container beta-linux port-linux-runner:local running; runner beta online false
       container someorg-linux port-linux-runner:local running; orgrunner online false; }
o2 1; mv "$CONFF" "$FX/conf.n1"; sed 's/ runners 1$//' "$FX/conf.n1" > "$CONFF"
run list > "$FX/o.plain"; run list --json > "$FX/o.plain.json"; run up > "$FX/o.plainup"
cp "$FX/conf.n1" "$CONFF"; run list > "$FX/o.n1"; run list --json > "$FX/o.n1.json"; run up > "$FX/o.n1up"
t_eq "runners 1 lists byte for byte as an org line without it" 0 "$(cmp -s "$FX/o.plain" "$FX/o.n1"; echo $?)"
t_eq "...in --json too" 0 "$(cmp -s "$FX/o.plain.json" "$FX/o.n1.json"; echo $?)"
t_eq "...and up says the same" 0 "$(cmp -s "$FX/o.plainup" "$FX/o.n1up"; echo $?)"
t_eq "...one org row" someorg "$(jq -r '[.[] | select(.slug == "SomeOrg") | .repo] | join(" ")' "$FX/o.n1.json")"
t_eq "a runners value that is no digit 1-9 is 1" someorg "$(o2 two; list; jq -r '[.[] | select(.slug == "SomeOrg") | .repo] | join(" ")' "$FX/list.json")"
t_eq "...and runners 0 is 1" someorg "$(o2 0; list; jq -r '[.[] | select(.slug == "SomeOrg") | .repo] | join(" ")' "$FX/list.json")"
o2; list
t_eq "runners 2: two org rows, each wanted, the second on <org>-linux-2" "someorg:someorg-linux:true someorg-2:someorg-linux-2:true" \
  "$(jq -r '[.[] | select(.slug == "SomeOrg") | "\(.repo):\(.name):\(.want)"] | join(" ")' "$FX/list.json")"
t_eq "...the first ok, the second missing" "ok missing" "$(row someorg .verdict) $(row someorg-2 .verdict)"
t_eq "...the org's repo is still served by the org, no container of its own" "false org" "$(row orgrepo '"\(.want) \(.verdict)"')"
t_eq "...GitHub's org runner list is read once, not once a row" 1 "$(grep -c '^api orgs/SomeOrg/actions/runners$' "$FX/gh.log")"
t_eq "...and the org variable once" 1 "$(grep -c '^variable get CI_RUNS_ON --org SomeOrg$' "$FX/gh.log")"
o2; OUT="$(run up)"
t_has "the dry run names only the missing second runner" "$OUT" "would create someorg-linux-2 for SomeOrg"
t_hasnt "...never the first" "$OUT" "would create someorg-linux "
t_has "control: with the first runner absent the same dry run names it" "$(o2; grep -v '^someorg-linux ' "$FX/containers" > "$FX/c.n"; mv "$FX/c.n" "$FX/containers"; run up)" "would create someorg-linux "
o2; OUT="$(run up --apply)"; RC=$?
t_eq "up --apply creates exactly the missing second runner" "--name someorg-linux-2" "$(grep '^run -d' "$FX/docker.log" | grep -o -e '--name [a-z0-9-]*')"
t_eq "...and never removes, stops or recreates the first" 0 "$(grep -c -e '^rm .*someorg-linux' -e '^stop someorg-linux' "$FX/docker.log" || true)"
t_eq "...one token, asked of the org" org.SomeOrg "$(cat "$FX/token.asked")"
t_has "...registered at the org's URL" "$(cat "$FX/envfile.captured")" "RUNNER_URL=https://github.com/SomeOrg"
t_has "...under its own name" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=someorg-linux-2"
t_has "...with the same labels" "$(cat "$FX/envfile.captured")" "RUNNER_LABELS=self-hosted,Linux,ARM64"
t_eq "...the env file 0600 and deleted" "600 no" "$(cat "$FX/envfile.mode") $([ -e "$(cat "$FX/envfile.path")" ] && echo yes || echo no)"
t_hasnt "...the token on no argv, not on the screen, not in checks.log" "$(cat "$FX/docker.log" "$FX/gh.log" "$CACHE/checks.log") $OUT" "TOKEN-SECRET"
t_has "...one checks.log line" "$(cat "$CACHE/checks.log")" "someorg-linux-2 created for SomeOrg"
t_eq "...exits 0" 0 "$RC"
orgrunners online false online false; run up --apply >/dev/null
t_eq "idempotent: a second apply creates nothing more" 1 "$(grep -c '^run -d' "$FX/docker.log")"
t_eq "...and both rows are ok" "ok ok" "$(list; echo "$(row someorg .verdict) $(row someorg-2 .verdict)")"
o2; container someorg-linux-2 port-linux-runner:local running; orgrunners online false online false; stale someorg-linux-2; OUT="$(run refresh --apply)"
t_eq "refresh recreates a stale second runner, only that one" "rm -f someorg-linux-2" "$(grep '^rm ' "$FX/docker.log")"
t_eq "...deleting its own registration at the org" "api -X DELETE orgs/SomeOrg/actions/runners/10" "$(cat "$FX/deletes.log")"
t_has "...and registering it again by its own name" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=someorg-linux-2"
o2; container someorg-linux-2 port-linux-runner:local running; orgrunners online false online true; run down someorg-2 --apply >/dev/null
t_eq "down someorg-2 refuses a busy second runner" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
o2; container someorg-linux-2 port-linux-runner:local running; orgrunners online false online false; run down someorg-2 --apply >/dev/null
t_eq "down someorg-2 removes the second runner and nothing else" "rm -f someorg-linux-2" "$(grep '^rm ' "$FX/docker.log")"
t_eq "...and deletes its registration at the org by id" "api -X DELETE orgs/SomeOrg/actions/runners/10" "$(cat "$FX/deletes.log")"
o2 1; container someorg-linux-2 port-linux-runner:local running; orgrunners online false online false; list
t_eq "runners lowered to 1: the second container left behind is extra, row someorg-2" "extra someorg-linux-2 false" "$(row someorg-2 '"\(.verdict) \(.name) \(.want)"')"
run down someorg-2 --apply >/dev/null
t_eq "...and down someorg-2 still finds it, at the org" "rm -f someorg-linux-2|api -X DELETE orgs/SomeOrg/actions/runners/10" "$(grep '^rm ' "$FX/docker.log")|$(cat "$FX/deletes.log")"
o2; cfg "mount someorg $MH/port/harbor ~/port/harbor"; rm -f "$FX/containers"; run up --apply >/dev/null
t_eq "a mount line for the org reaches each of its runners" "2" "$(grep '^run -d.*--name someorg-linux' "$FX/docker.log" | grep -c -e "-v $MH/port/harbor:$RH/port/harbor:ro")"
OUT="$(run list)"
t_has "...and list checks it on each" "$OUT" "ok on someorg-linux-2"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "hold <org> holds every runner of the org, not only the first (harbor#1060)"
swv() { printf '{"at":%s,"owner":"SomeOrg","runner":"self-hosted","unread":false,"used":2000,"allowance":2000}\n' "$NOW" > "$CACHE/runner-switch.SomeOrg.json"; }   # the org is over its minutes
orgw() { if [ -f "$FX/writes.log" ]; then grep -c '^set org.SomeOrg ' "$FX/writes.log" || true; else echo 0; fi; }   # writes to the org's variable
o2h() { o2; container someorg-linux-2 port-linux-runner:local running; orgrunners online false online false; swv; }
o2h; list
t_eq "control: with no hold line both org rows are ok" "ok ok" "$(row someorg .verdict) $(row someorg-2 .verdict)"
run switch --apply >/dev/null
t_eq "control: ...and switch --apply sets the org's variable" 1 "$(orgw)"
o2h; cfg "hold someorg paused while X"; list
t_eq "hold someorg holds the first runner and the second" "hold hold" "$(row someorg .verdict) $(row someorg-2 .verdict)"
run switch --apply >/dev/null
t_eq "...so switch --apply writes nothing for the held org" 0 "$(orgw)"
o2; cfg "hold someorg paused while X"; OUT="$(run up --apply)"
t_eq "...and up --apply creates no second runner for it" 0 "$(grep -c '^run -d' "$FX/docker.log" || true)"
t_has "...saying the org is on hold" "$OUT" "someorg is on hold"

t_section "limits: memory and cpus per runner, own line, then group, then global, then 1g / 1 (harbor#1060)"
reset; hold; cfg "memory 3g" "cpus 2" "limits beta memory 2g cpus 4" "org SomeOrg runners 2" "limits someorg memory 2g" \
  "limits someorg-linux-2 cpus 3 memory 5g" "repo VytCepas/zarija"
container alpha-linux port-linux-runner:local running; runner alpha online false
OUT="$(run up)"
t_has "the dry run names each new container's limits" "$OUT" "would create beta-linux for VytCepas/beta (image port-linux-runner:local, 0 read-only mounts) at cpus 4, memory 2g"
run up --apply >/dev/null
lim() { grep "^run -d.*--name $1 " "$FX/docker.log" | grep -o -e '--cpus [^ ]* --memory [^ ]*'; }
t_eq "a repo's own limits line" "--cpus 4 --memory 2g" "$(lim beta-linux)"
t_eq "an org's group line for memory, the global cpus line" "--cpus 2 --memory 2g" "$(lim someorg-linux)"
t_eq "a container's own line beats its org's: cpus and memory" "--cpus 3 --memory 5g" "$(lim someorg-linux-2)"
t_eq "no limits line: the global memory and cpus lines" "--cpus 2 --memory 3g" "$(lim zarija-linux)"
t_has "the creation line names them" "$(cat "$CACHE/checks.log")" "someorg-linux-2 created for SomeOrg (image port-linux-runner:local) at cpus 3, memory 5g"
reset; hold; cfg "limits beta memory lots cpus x"; run up --apply >/dev/null
t_eq "a value that is not a size or a number is ignored: the defaults" "--cpus 1 --memory 1g" "$(lim beta-linux)"

t_section "limits on an adopted container: drift in list, set LIVE by up --apply, never recreated (harbor#1060)"
GB=1073741824
# ad <limits-line...> — alpha-linux and beta-linux exist at 1g, idle; the lines are the config
ad() { reset; hold; container alpha-linux port-linux-runner:local running; runner alpha online false; echo "$GB" > "$FX/memory.alpha-linux"
       container beta-linux port-linux-runner:local running; runner beta online false; echo "$GB" > "$FX/memory.beta-linux"
       [ "$#" = 0 ] || cfg "$@"; }
ad; OUT="$(run list)"
t_has "control: no memory line, no drift: the default is never enforced on what exists" "$OUT" "alpha-linux            1.0g   no memory line: made at 1g, never changed"
t_hasnt "...no DRIFT" "$OUT" "DRIFT"
ad "limits alpha memory 2g"; OUT="$(run list)"; RC=$?
t_has "a cap that differs from its limits line is drift" "$OUT" "alpha-linux            1.0g   config 2g: DRIFT"
t_has "...named with the command that sets it live" "$OUT" "alpha-linux: memory 1.0g, config 2g"
t_has "...the command" "$OUT" "up --apply (docker update, live; no recreate)"
t_has "...the matching one is ok" "$OUT" "beta-linux             1.0g   no memory line"
t_eq "...list answers 0 and wrote nothing" "0 0" "$RC $(grep -c -e '^update ' -e '^run ' -e '^rm ' "$FX/docker.log" || true)"
ad "memory 2g"; t_has "the global memory line is enforced too, on every fleet runner" "$(run list)" "beta-linux             1.0g   config 2g: DRIFT"
ad "limits alpha memory 2g"; OUT="$(run up)"
t_has "the dry run says what it would set" "$OUT" "would set alpha-linux memory 1.0g -> 2g live (docker update, no recreate)"
t_eq "...and sets nothing" 0 "$(grep -c '^update ' "$FX/docker.log" || true)"
ad "limits alpha memory 2g"; OUT="$(run up --apply)"; RC=$?
t_eq "up --apply raises it live: one docker update, swap twice the memory" "update --memory 2147483648 --memory-swap 4294967296 alpha-linux" "$(grep '^update ' "$FX/docker.log")"
t_eq "...nothing recreated, stopped or removed" 0 "$(grep -c -e '^run ' -e '^rm ' -e '^stop ' "$FX/docker.log" || true)"
t_eq "...one checks.log line" 1 "$(grep -c 'memory 1.0g -> 2g' "$CACHE/checks.log")"
t_has "...saying it was live" "$(cat "$CACHE/checks.log")" "alpha-linux memory 1.0g -> 2g (docker update, live)"
t_eq "...exits 0" 0 "$RC"
t_has "...list reads it ok now" "$(run list)" "alpha-linux            2.0g   config 2g: ok"
run up --apply >/dev/null
t_eq "idempotent: a second apply updates nothing" 1 "$(grep -c '^update ' "$FX/docker.log")"
ad "limits alpha memory 2g"; runner alpha online true; : > "$FX/busy.alpha-linux"; run up --apply >/dev/null
t_eq "a busy runner's memory is raised (a raise kills nothing)" 1 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log")"
t_eq "...and nothing is recreated" 0 "$(grep -c -e '^run ' -e '^rm ' -e '^stop ' "$FX/docker.log" || true)"
t_has "...the line says it was under a job" "$(cat "$CACHE/checks.log")" "(docker update, live, under a job)"
ad "limits alpha memory 512m" "limits beta memory 2g"; echo $((GB * 3 / 4)) > "$FX/memcur.alpha-linux"; OUT="$(run up --apply)"; RC=$?
t_eq "a lowering below what it uses now is refused: no update of it" 0 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log" || true)"
t_has "...saying why" "$OUT" "alpha-linux: memory 1.0g -> 512m is below what it uses now (0.8g): refused"
t_eq "...and carries on: the other runner is raised" 1 "$(grep -c '^update .* beta-linux$' "$FX/docker.log")"
t_eq "...exits 1" 1 "$RC"
ad "limits alpha memory 512m"; echo $((GB / 4)) > "$FX/memcur.alpha-linux"; run up --apply >/dev/null
t_eq "a lowering above what it uses is applied" "update --memory 536870912 --memory-swap 1073741824 alpha-linux" "$(grep '^update ' "$FX/docker.log")"
ad "limits alpha memory 512m"; run up --apply >/dev/null
t_eq "a lowering whose usage cannot be read is refused" 0 "$(grep -c '^update ' "$FX/docker.log" || true)"
ad "limits alpha memory 512m"; echo $((GB / 4)) > "$FX/memcur.alpha-linux"; runner alpha online true; OUT="$(run up --apply)"
t_eq "a lowering under a job is refused" 0 "$(grep -c '^update ' "$FX/docker.log" || true)"
t_has "...saying so" "$OUT" "is a lowering and it is running a job: refused"
# a lowering is decided on the state NOW, not on the rows read at the start of the run
ad "limits alpha memory 512m"; : > "$FX/containers"
container alpha-linux port-linux-runner:local exited; container beta-linux port-linux-runner:local running
OUT="$(run up --apply)"; RC=$?
t_has "control: up --apply starts the stopped runner first" "$OUT" "alpha-linux started"
t_eq "a runner up has just started is running now: its usage is read, and unread it is refused (no update)" 0 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log" || true)"
t_has "...saying why" "$OUT" "alpha-linux: memory 1.0g -> 512m is a lowering and what it uses now could not be read: refused"
t_eq "...exits 1" 1 "$RC"
ad "limits alpha memory 512m"; : > "$FX/containers"; container alpha-linux port-linux-runner:local exited; container beta-linux port-linux-runner:local running
echo $((GB / 4)) > "$FX/memcur.alpha-linux"; run up --apply >/dev/null
t_eq "control: the same start, usage readable and below the new cap: the lowering is applied" 1 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log")"
ad "limits alpha memory 512m"; echo $((GB / 4)) > "$FX/memcur.alpha-linux"; echo 1 > "$FX/busyafter.alpha-linux"; OUT="$(run up --apply)"; RC=$?
t_eq "a job taken after the rows were read: refused, no update" 0 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log" || true)"
t_has "...saying it is running a job" "$OUT" "alpha-linux: memory 1.0g -> 512m is a lowering and it is running a job: refused"
t_eq "...exits 1" 1 "$RC"
ad "limits alpha memory 512m"; echo $((GB / 4)) > "$FX/memcur.alpha-linux"; run up --apply >/dev/null
t_eq "control: with no job taken the same lowering is applied" 1 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log")"

ad "limits alpha memory 2g"; touch "$FX/update.fail"; OUT="$(run up --apply)"; RC=$?
t_has "docker refusing the update is a failure, said" "$OUT" "alpha-linux: docker update refused memory 2g"
t_eq "...exits 1, logs no change" "1 0" "$RC $(if [ -f "$CACHE/checks.log" ]; then grep -c 'memory 1.0g' "$CACHE/checks.log" || true; else echo 0; fi)"

t_section "list: a held or an extra runner's cap is not offered a fix up --apply would not make (harbor#1060)"
ad "hold alpha paused while X" "limits alpha memory 2g"; OUT="$(run list)"
t_has "a held runner whose cap differs is said to be left as it is" "$OUT" "alpha-linux            1.0g   config 2g: differs, on hold: left as it is"
t_hasnt "...not DRIFT" "$OUT" "DRIFT"
t_hasnt "...with no warning and no fix" "$OUT" "alpha-linux: memory 1.0g, config 2g"
run up --apply >/dev/null
t_eq "...and up --apply indeed leaves it" 0 "$(grep -c '^update .* alpha-linux$' "$FX/docker.log" || true)"
ad "org SomeOrg runners 1" "limits someorg memory 2g"; container someorg-linux port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux"
container someorg-linux-2 port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux-2"; orgrunners online false online false; OUT="$(run list)"
t_has "an extra org runner is said to be left as it is" "$OUT" "someorg-linux-2        1.0g   config 2g: differs, extra runner: left as it is"
t_has "control: the wanted org runner beside it is still DRIFT" "$OUT" "someorg-linux          1.0g   config 2g: DRIFT"
t_hasnt "...and the extra one has no drift warning" "$OUT" "someorg-linux-2: memory"
ad "org SomeOrg runners 2" "limits someorg memory 2g"; container someorg-linux port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux"
container someorg-linux-2 port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux-2"; orgrunners online false online false
t_has "control: the same second runner, wanted (runners 2), does get the drift warning" "$(run list)" "someorg-linux-2: memory 1.0g, config 2g"
ad "org SomeOrg runners 1" "limits someorg memory 2g"; container someorg-linux port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux"
container someorg-linux-2 port-linux-runner:local running; echo $GB > "$FX/memory.someorg-linux-2"; orgrunners online false online false
run up --apply >/dev/null
t_eq "...up --apply raises the wanted one only" "update --memory 2147483648 --memory-swap 4294967296 someorg-linux" "$(grep '^update ' "$FX/docker.log")"

t_section "limits: a governance runner only when a limits line names it, and only with --include-governance"
gl() { ad "$@"; container harbor-linux port-linux-runner:local running; runner harbor online false 55; echo $((GB * 4)) > "$FX/memory.harbor-linux"; }
gl "memory 8g"; run up --apply --include-governance >/dev/null
t_eq "the global memory line never reaches harbor-linux" 0 "$(grep -c '^update .* harbor-linux$' "$FX/docker.log" || true)"
t_has "...list says it is kept as made" "$(run list)" "harbor-linux           4.0g   no limits line names it: kept as made"
gl "limits harbor memory 6g"; run up --apply >/dev/null
t_eq "a limits line for it, without --include-governance: untouched" 0 "$(grep -c '^update ' "$FX/docker.log" || true)"
t_has "...but list reports the drift, with the flag it needs" "$(run list)" "up --apply --include-governance (docker update, live; no recreate)"
run up --apply --include-governance >/dev/null
t_eq "...with --include-governance it is raised live" "update --memory 6442450944 --memory-swap 12884901888 harbor-linux" "$(grep '^update ' "$FX/docker.log")"
gl "limits harbor memory 6g" "governance 2"; run up --apply --include-governance >/dev/null
t_has "a new governance runner is made at the limits line's memory" "$(grep '^run -d.*--name harbor-linux-2 ' "$FX/docker.log")" "--memory 6g"

t_section "list: the memory budget, every running runner's cap against the VM"
ad; echo $((GB * 2)) > "$FX/memory.alpha-linux"; container harbor-linux port-linux-runner:local running; echo $((GB * 4)) > "$FX/memory.harbor-linux"
container someorg-linux port-linux-runner:local exited; echo $((GB * 2)) > "$FX/memory.someorg-linux"; echo $((GB * 8)) > "$FX/vmmem"
OUT="$(run list)"
t_has "three running caps (7g) in an 8g VM fit; a stopped one is not counted" "$OUT" "budget: 3 running runner containers cap 7.0g against the VM's 8.0g (docker info): fits, 1.0g spare"
echo $((GB * 6)) > "$FX/vmmem"; OUT="$(run list)"
t_has "...in a 6g VM they are overcommitted, said plainly" "$OUT" "cap 7.0g against the VM's 6.0g (docker info): OVERCOMMITTED 1.2x"
echo 0 > "$FX/memory.beta-linux"; OUT="$(run list)"
t_has "a container with no cap is counted apart" "$OUT" "budget: 3 running runner containers cap 6.0g (+1 with no cap)"
t_has "...and listed as none" "$OUT" "beta-linux             none"
t_eq "list --json carries no budget: still one array of rows" array "$(run list --json | jq -r type)"
t_has "the VM is read from docker info" "$(cat "$FX/docker.log")" "info --format {{.MemTotal}}"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"
t_done
