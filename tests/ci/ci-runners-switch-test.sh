#!/usr/bin/env sh
# bin/ci-runners.sh switch, rerun-refused and tick against stubbed gh and docker (harbor#1060): the fleet-wide
# CI_RUNS_ON follows the minutes rule runner-switch.sh already decided, billing-refused runs are re-run once,
# and nothing here ever writes to billing. Each flip has a planted case and a control that must not move.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
verdict() { # <runner> [at] [unread] — what runner-switch.sh left in its cache
  printf '{"at":%s,"runner":"%s","unread":%s,"used":2700,"allowance":3000}\n' "${2:-$NOW}" "$1" "${3:-false}" > "$CACHE/runner-switch.json"; }
fleet() { reset; container alpha-linux port-linux-runner:interim running; runner alpha online false; }
varnow() { cat "$FX/var/$1" 2>/dev/null || echo unset; }
writes() { nlines "$FX/writes.log"; }
ago() { date -u -r "$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((NOW - $1))" +%Y-%m-%dT%H:%M:%SZ; }
REFUSED='[{"message":"The job was not started because recent account payments have failed or your spending limit needs to be increased"}]'
# plantrun <repo> <run-id> <conclusion> <age-seconds> <annotation-json> — a run, its failed job and the job's annotations
plantrun() {
  mkdir -p "$FX/runs" "$FX/jobs" "$FX/ann"; _f="$FX/runs/$1.json"; [ -f "$_f" ] || echo '[]' > "$_f"
  jq -c --argjson id "$2" --arg c "$3" --arg at "$(ago "$4")" \
    '. + [{databaseId:$id, conclusion:$c, createdAt:$at, headBranch:"main", name:"CI"}]' "$_f" > "$_f.n" && mv "$_f.n" "$_f"
  printf '{"jobs":[{"id":%s,"conclusion":"%s"}]}\n' "$(($2 * 10))" "$3" > "$FX/jobs/$2.json"
  printf '%s\n' "$5" > "$FX/ann/$(($2 * 10)).json"
}

t_section "switch: the minutes rule says self-hosted"
fleet; verdict self-hosted; OUT="$(run switch --apply)"
t_eq "a repo with a local runner gets CI_RUNS_ON=self-hosted" self-hosted "$(varnow alpha)"
t_eq "a fleet repo with no local runner is left alone" unset "$(varnow beta)"
t_eq "...and so is a repo that does not read the variable" unset "$(varnow plain)"
t_eq "one write" 1 "$(writes)"
t_eq "one checks.log line for the change" 1 "$(nlog)"
t_has "...saying which repo and which way" "$(cat "$CACHE/checks.log")" "alpha CI_RUNS_ON unset -> self-hosted"
t_has "...and quoting the registry id" "$(cat "$CACHE/checks.log")" "[check:ci-runners]"
run switch --apply >/dev/null; run switch --apply >/dev/null
t_eq "control: two more ticks write nothing" 1 "$(writes)"
t_eq "control: ...and log nothing" 1 "$(nlog)"
fleet; verdict self-hosted; run switch >/dev/null
t_eq "control: the dry run writes nothing" 0 "$(writes)"
fleet; verdict self-hosted; runner alpha offline false; run switch --apply >/dev/null
t_eq "control: a runner that is offline is not sent the fleet's jobs" unset "$(varnow alpha)"
fleet; verdict self-hosted; : > "$FX/containers"; run switch --apply >/dev/null
t_eq "control: no container, no switch" unset "$(varnow alpha)"
fleet; verdict self-hosted; printf 'hold alpha other-mac serves it\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run switch --apply >/dev/null
t_eq "control: a repo on hold is not switched" unset "$(varnow alpha)"

t_section "switch: the minutes rule says github-hosted"
fleet; verdict github-hosted; echo self-hosted > "$FX/var/alpha"; run switch --apply >/dev/null
t_eq "the variable is unset again, so the workflow falls back to hosted" unset "$(varnow alpha)"
t_has "one line for the change" "$(cat "$CACHE/checks.log")" "alpha CI_RUNS_ON self-hosted -> unset"
t_eq "...and only one" 1 "$(nlog)"
run switch --apply >/dev/null
t_eq "control: unset already, nothing to write" 1 "$(writes)"
fleet; verdict github-hosted; echo self-hosted > "$FX/var/beta"; run switch --apply >/dev/null
t_eq "control: a repo with no local runner keeps what it has (zorbcorp, served by a Mac)" self-hosted "$(varnow beta)"

t_section "switch: a verdict that cannot be trusted flips nothing"
fleet; verdict self-hosted "$((NOW - 2000))"; run switch --apply >/dev/null
t_eq "a verdict older than 900 seconds" unset "$(varnow alpha)"
fleet; verdict self-hosted "$NOW" true; run switch --apply >/dev/null
t_eq "a verdict runner-switch marked unread" unset "$(varnow alpha)"
fleet; run switch --apply >/dev/null
t_eq "no verdict at all" unset "$(varnow alpha)"
fleet; verdict self-hosted; : > "$FX/runners.fail"; run switch --apply >/dev/null
t_eq "a GitHub that does not answer about the runner" unset "$(varnow alpha)"

t_section "rerun-refused: a run refused for billing is re-run once, after the switch"
fleet; echo self-hosted > "$FX/var/alpha"
plantrun alpha 101 failure 3600 "$REFUSED"
plantrun alpha 102 failure 3600 '[{"message":"Process completed with exit code 1."}]'
plantrun alpha 103 failure 216000 "$REFUSED"
plantrun alpha 104 success 3600 '[]'
OUT="$(run rerun-refused)"
t_has "the dry run names the refused run" "$OUT" "101"
t_hasnt "...not the run that failed for its own reasons" "$OUT" "102"
t_hasnt "...not the refused run that is 60 hours old" "$OUT" "103"
t_eq "...and re-runs nothing" 0 "$(nlines "$FX/reruns.log")"
run rerun-refused --apply >/dev/null
t_eq "apply re-runs run 101 and only it" "rerun 101 VytCepas/alpha" "$(cat "$FX/reruns.log")"
t_eq "the re-run is one checks.log line" 1 "$(nlog)"
run rerun-refused --apply >/dev/null; run rerun-refused --apply >/dev/null
t_eq "once only: later ticks re-run nothing, though the run is still refused" 1 "$(nlines "$FX/reruns.log")"
t_has "what was re-run is remembered" "$(cat "$CACHE/ci-reruns.tsv")" "alpha 101"
fleet; plantrun alpha 101 failure 3600 "$REFUSED"; run rerun-refused --apply >/dev/null
t_eq "control: the variable is not self-hosted, so nothing is re-run" 0 "$(nlines "$FX/reruns.log")"
fleet; echo self-hosted > "$FX/var/alpha"; plantrun alpha 105 failure 3600 "$REFUSED"; runner alpha offline false; run rerun-refused --apply >/dev/null
t_eq "control: no online runner to take the job, so nothing is re-run" 0 "$(nlines "$FX/reruns.log")"
t_eq "gh was never asked about billing, budgets or the spending limit" 0 "$(cat "$FX/gh.log" | grep -c -i -e 'settings/billing' -e budget -e spending_limit || true)"

t_section "tick: switch, re-run and a drift report in one run, logged on change"
fleet; verdict self-hosted; plantrun alpha 101 failure 3600 "$REFUSED"; printf "hold held other-mac serves it\n" > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
run tick >/dev/null
t_eq "tick applies the switch" self-hosted "$(varnow alpha)"
t_eq "...and the re-run" "rerun 101 VytCepas/alpha" "$(cat "$FX/reruns.log")"
t_eq "...and writes its cache" beta-linux "$(jq -r '.missing | join(" ")' "$CACHE/ci-runners.json")"
t_eq "...with the repos that want a runner" 3 "$(jq -r '.desired' "$CACHE/ci-runners.json")"
t_eq "a missing runner is one drift line on the way in" 1 "$(grep -c 'missing beta-linux' "$CACHE/checks.log")"
run tick >/dev/null; run tick >/dev/null
t_eq "...and not one per tick" 1 "$(grep -c 'missing beta-linux' "$CACHE/checks.log")"
t_eq "tick creates no container" 0 "$(grep -c '^run -d' "$FX/docker.log" || true)"
t_eq "tick asks for no registration token" 0 "$(nlines "$FX/token.asked")"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "per owner: the org follows its own verdict, the personal repos theirs (harbor#1060)"
orgverdict() { # <runner> [at] [unread] — what runner-switch.sh --org SomeOrg left in its cache
  printf '{"at":%s,"owner":"SomeOrg","runner":"%s","unread":%s,"used":2000,"allowance":2000}\n' "${2:-$NOW}" "$1" "${3:-false}" > "$CACHE/runner-switch.SomeOrg.json"; }
ofleet() { fleet; orgconf; container someorg-linux port-linux-runner:local running; orgrunner online false; }
ofleet; verdict github-hosted; orgverdict self-hosted; run switch --apply >/dev/null
t_eq "org over its cap, personal under: the org-level variable is set" self-hosted "$(varnow org.SomeOrg)"
t_has "...as an org variable every private repo of the org reads" "$(cat "$FX/gh.log")" "variable set CI_RUNS_ON --body self-hosted --org SomeOrg --visibility private"
t_eq "...and the personal repo is left on hosted" unset "$(varnow alpha)"
t_eq "...and the org's repo gets no variable of its own" unset "$(varnow orgrepo)"
t_has "one line, naming the org and its minutes" "$(cat "$CACHE/checks.log")" "SomeOrg CI_RUNS_ON unset -> self-hosted (2000/2000 minutes)"
ofleet; verdict self-hosted; orgverdict github-hosted; echo self-hosted > "$FX/var/org.SomeOrg"; run switch --apply >/dev/null
t_eq "personal over, org under: the personal repo is set" self-hosted "$(varnow alpha)"
t_eq "...and the org-level variable is deleted" unset "$(varnow org.SomeOrg)"
t_has "...at the org" "$(cat "$FX/gh.log")" "variable delete CI_RUNS_ON --org SomeOrg"
ofleet; verdict self-hosted; run switch --apply >/dev/null
t_eq "control: no org verdict, the org is untouched while the personal repo flips" "unset self-hosted" "$(varnow org.SomeOrg) $(varnow alpha)"
ofleet; verdict self-hosted; orgverdict self-hosted "$((NOW - 2000))"; run switch --apply >/dev/null
t_eq "control: a stale org verdict flips nothing at the org" unset "$(varnow org.SomeOrg)"
ofleet; orgverdict self-hosted "$NOW" true; run switch --apply >/dev/null
t_eq "control: an org verdict marked unread flips nothing" unset "$(varnow org.SomeOrg)"
ofleet; orgverdict self-hosted; orgrunner offline false; run switch --apply >/dev/null
t_eq "control: an org runner that is offline is not sent the org's jobs" unset "$(varnow org.SomeOrg)"
ofleet; orgverdict self-hosted; printf 'hold someorg the org waits\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run switch --apply >/dev/null
t_eq "control: a held org is not switched" unset "$(varnow org.SomeOrg)"
ofleet; orgverdict self-hosted; run switch >/dev/null
t_eq "control: the dry run writes nothing" 0 "$(writes)"

t_section "per owner: rerun-refused walks the org's repos once the org is self-hosted"
ofleet; echo self-hosted > "$FX/var/org.SomeOrg"; plantrun orgrepo 201 failure 3600 "$REFUSED"; run rerun-refused --apply >/dev/null
t_eq "the org's refused run is re-run on its repo" "rerun 201 SomeOrg/orgrepo" "$(cat "$FX/reruns.log")"
t_eq "...and nothing was asked of an owner no config names" 0 "$(nlines "$FX/unexpected.log")"
ofleet; plantrun orgrepo 201 failure 3600 "$REFUSED"; run rerun-refused --apply >/dev/null
t_eq "control: the org variable is not self-hosted, so nothing is re-run" 0 "$(nlines "$FX/reruns.log")"
ofleet; echo self-hosted > "$FX/var/org.SomeOrg"; orgrunner offline false; plantrun orgrepo 201 failure 3600 "$REFUSED"; run rerun-refused --apply >/dev/null
t_eq "control: the org runner is offline, so nothing is re-run" 0 "$(nlines "$FX/reruns.log")"

t_section "an org with two runners: one variable, switched once, its repos walked once (harbor#1060)"
o2fleet() { fleet; verdict github-hosted; printf 'org SomeOrg runners 2\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"
            container someorg-linux port-linux-runner:local running; container someorg-linux-2 port-linux-runner:local running; }
o2fleet; orgrunners offline false online false; orgverdict self-hosted; run switch --apply >/dev/null
t_eq "the first runner offline, the second online: the org is switched" self-hosted "$(varnow org.SomeOrg)"
t_eq "...with one write" 1 "$(grep -c 'set org.SomeOrg' "$FX/writes.log")"
t_eq "...and one line" 1 "$(grep -c 'SomeOrg CI_RUNS_ON' "$CACHE/checks.log")"
o2fleet; orgrunners online false online false; orgverdict self-hosted; run switch --apply >/dev/null
t_eq "both online: still one write, not one a runner" 1 "$(grep -c 'set org.SomeOrg' "$FX/writes.log")"
o2fleet; orgrunners online false online false; orgverdict github-hosted; echo self-hosted > "$FX/var/org.SomeOrg"; run switch --apply >/dev/null
t_eq "back under the cap: one delete, not one a runner" 1 "$(grep -c 'delete org.SomeOrg' "$FX/writes.log")"
o2fleet; orgrunners offline false offline false; orgverdict self-hosted; run switch --apply >/dev/null
t_eq "control: neither online, no switch" unset "$(varnow org.SomeOrg)"
o2fleet; echo self-hosted > "$FX/var/org.SomeOrg"; orgrunners online false online false; plantrun orgrepo 201 failure 3600 "$REFUSED"; run rerun-refused --apply >/dev/null
t_eq "rerun-refused re-runs the org's refused run once" "rerun 201 SomeOrg/orgrepo" "$(cat "$FX/reruns.log")"
t_eq "...listing the org repo's runs once, not once a runner" 1 "$(grep -c '^run list -R SomeOrg/orgrepo' "$FX/gh.log")"

t_section "per owner: tick reports a missing org runner as drift"
fleet; orgconf; verdict github-hosted; run tick >/dev/null
t_has "the missing org runner is in the drift line" "$(cat "$CACHE/checks.log")" "someorg-linux"
t_has "...beside the missing extra repo's" "$(cat "$CACHE/checks.log")" "zarija-linux"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "tick with docker down: a repo still falls back to hosted, and no drift is invented"
fleet; verdict github-hosted; echo self-hosted > "$FX/var/alpha"; : > "$FX/docker.fail"
run tick >/dev/null
t_eq "its runner is on GitHub's list, so CI_RUNS_ON is unset" unset "$(varnow alpha)"
t_eq "...and a dead docker is not reported as three missing containers" 0 "$(grep -c 'drift' "$CACHE/checks.log" || true)"
fleet; verdict self-hosted; : > "$FX/docker.fail"; run tick >/dev/null
t_eq "control: the other way needs a running container, so nothing is switched" unset "$(varnow alpha)"
t_eq "docker down fails list outright" 2 "$(run list >/dev/null; echo $?)"
t_done
