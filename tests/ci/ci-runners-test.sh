#!/usr/bin/env sh
# bin/ci-runners.sh list, up and down against stubbed gh and docker (harbor#1060): the desired set read from
# the fleet snapshot, the actual set read from docker and GitHub, adoption of containers that already exist,
# and the registration token that must never reach an argv, a log or the screen.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/ci/ci-runners-fixture.sh"
row() { jq -r --arg r "$1" ".[] | select(.repo == \$r) | $2" "$FX/list.json"; }
list() { run list --json > "$FX/list.json"; }
hold() { printf 'hold held other-mac serves it until its suites pass on Linux\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
state() { reset; hold; container alpha-linux port-linux-runner:interim running; runner alpha online false
          printf 'self-hosted\n' > "$FX/var/alpha"; container orphan-linux port-linux-runner:interim running; }

t_section "list: desired against actual"
state; list
t_eq "the fleet repos that read vars.CI_RUNS_ON are desired: alpha, beta, held" "alpha beta held" "$(jq -r '[.[]|select(.want)|.repo]|join(" ")' "$FX/list.json")"
t_eq "a repo whose workflows hard-code ubuntu is not desired" "" "$(row plain .repo)"
t_eq "a repo under another owner is listed as foreign, never wanted" "foreign false" "$(row orgrepo '"\(.verdict) \(.want)"')"
t_eq "a repo whose manifest says ci_runner: hosted is not desired" "" "$(row opted .repo)"
t_eq "a repo with no GitHub remote is not desired: nothing to register a runner to" "" "$(row unpushed .repo)"
t_eq "an existing container is read as present" running "$(row alpha .container)"
t_eq "...with its image" port-linux-runner:interim "$(row alpha .image)"
t_eq "...registered and online on GitHub" online "$(row alpha .runner)"
t_eq "...and the repo's CI_RUNS_ON" self-hosted "$(row alpha .ci_runs_on)"
t_eq "alpha is ok" ok "$(row alpha .verdict)"
t_eq "a desired repo with no container is missing" missing "$(row beta .verdict)"
t_eq "...and its CI_RUNS_ON reads as unset" unset "$(row beta .ci_runs_on)"
t_eq "a *-linux container with no desired repo is extra" extra "$(row orphan .verdict)"
t_eq "a stopped container is not ok" stopped "$(reset; container alpha-linux port-linux-runner:interim exited; list; row alpha .verdict)"
t_eq "a running container whose runner GitHub says is offline is not ok" offline \
  "$(reset; container alpha-linux port-linux-runner:interim running; runner alpha offline false; list; row alpha .verdict)"
t_eq "a repo on hold is reported as hold, not missing" hold \
  "$(reset; hold; list; row held .verdict)"
state; OUT="$(run list)"
t_has "the text table names the missing repo" "$OUT" "beta"
t_has "...and the verdict" "$OUT" "missing"
t_eq "list wrote nothing to GitHub" 0 "$(grep -c -e 'POST' -e 'variable set' -e 'DELETE' "$FX/gh.log" || true)"
t_eq "list called docker only to read" 0 "$(grep -c -e '^run ' -e '^rm ' -e '^start ' "$FX/docker.log" || true)"
t_eq "neither stub was called off script" 0 "$(nlines "$FX/unexpected.log")"
t_eq "a snapshot that is absent is an error, not an empty fleet" 2 "$(rm -f "$CACHE/fleet-snapshot.json"; run list >/dev/null; echo $?)"
cp "$FX/snap.json" "$CACHE/fleet-snapshot.json"

t_section "up: dry run by default, adoption of what exists"
t_has "control: with no container for alpha the same dry run does name it" "$(reset; hold; run up)" "would create alpha-linux"
state; OUT="$(run up)"
t_has "the dry run says it would create beta-linux" "$OUT" "would create beta-linux"
t_hasnt "...and does not recreate alpha, which exists" "$OUT" "would create alpha-linux"
t_eq "a dry run starts nothing" 0 "$(grep -c '^run ' "$FX/docker.log" || true)"
t_eq "a dry run asks GitHub for no token" 0 "$(nlines "$FX/token.asked")"
t_eq "a dry run logs nothing to checks.log" 0 "$(nlog)"

t_section "up --apply: creates only the missing container, as provision.sh did"
state; OUT="$(run up --apply)"
t_eq "exactly one container is created" 1 "$(grep -c '^run -d' "$FX/docker.log")"
RUNLINE="$(grep '^run -d' "$FX/docker.log")"
t_has "named <repo>-linux" "$RUNLINE" "--name beta-linux"
t_has "restarted unless stopped" "$RUNLINE" "--restart unless-stopped"
t_has "one core" "$RUNLINE" "--cpus 1"
t_has "one gigabyte" "$RUNLINE" "--memory 1g"
t_has "the governor's events mount" "$RUNLINE" "-v $EVENTS:/gov-events"
t_has "the job-started hook" "$RUNLINE" "ACTIONS_RUNNER_HOOK_JOB_STARTED=/gov-events/ci-governor-hook.sh"
t_has "the job-completed hook" "$RUNLINE" "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh"
t_has "the image is the configured default, port-linux-runner:local" "$RUNLINE" "port-linux-runner:local"
t_eq "the hook the containers run is installed in the events mount, equal to bin's" yes \
  "$(cmp -s "$T_ROOT/bin/ci-governor-hook.sh" "$EVENTS/ci-governor-hook.sh" && echo yes)"
t_eq "...and readable by the container's runner user" -rw-r--r-- "$(ls -l "$EVENTS/ci-governor-hook.sh" | cut -c1-10)"
t_eq "the token was asked for beta only" beta "$(cat "$FX/token.asked")"
t_eq "the env file was 0600 when docker read it" 600 "$(cat "$FX/envfile.mode")"
ENVF="$(cat "$FX/envfile.captured")"
t_has "...it carried the token" "$ENVF" "RUNNER_TOKEN=TOKEN-SECRET-4242"
t_has "...the repo URL" "$ENVF" "RUNNER_URL=https://github.com/VytCepas/beta"
t_has "...the runner name" "$ENVF" "RUNNER_NAME=beta-linux"
t_has "...and the labels" "$ENVF" "RUNNER_LABELS=self-hosted,Linux,ARM64"
t_eq "the env file was deleted afterwards" no "$([ -e "$(cat "$FX/envfile.path")" ] && echo yes || echo no)"
t_hasnt "the token is on no docker argv" "$(cat "$FX/docker.log")" "TOKEN-SECRET"
t_hasnt "...on no gh argv" "$(cat "$FX/gh.log")" "TOKEN-SECRET"
t_hasnt "...not on the screen" "$OUT" "TOKEN-SECRET"
t_hasnt "...and not in checks.log" "$(cat "$CACHE/checks.log")" "TOKEN-SECRET"
t_eq "the creation is one checks.log line" 1 "$(grep -c 'created for' "$CACHE/checks.log")"
t_eq "...beside the first install of the job hook" 2 "$(nlog)"
t_has "...that quotes the registry id and the container" "$(cat "$CACHE/checks.log")" "[check:ci-runners]"
run up --apply >/dev/null
t_eq "idempotent: a second apply creates nothing more" 1 "$(grep -c '^run -d' "$FX/docker.log")"
t_eq "...asks for no second token" 1 "$(nlines "$FX/token.asked")"
t_eq "...and logs no further line (the hook is current, so not even that)" 2 "$(nlog)"
echo stale > "$EVENTS/ci-governor-hook.sh"; run up >/dev/null
t_eq "a dry run leaves a stale hook alone" stale "$(cat "$EVENTS/ci-governor-hook.sh")"
run tick >/dev/null
t_eq "tick replaces a stale hook" yes "$(cmp -s "$T_ROOT/bin/ci-governor-hook.sh" "$EVENTS/ci-governor-hook.sh" && echo yes)"

t_section "up: the image is a config value, and a missing image creates nothing"
state; printf 'image port-linux-runner:interim\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; run up --apply >/dev/null
t_has "the config file's image is used" "$(grep '^run -d' "$FX/docker.log")" "port-linux-runner:interim"
state; : > "$FX/images"; OUT="$(run up --apply)"; RC=$?
t_eq "no image, no container" 0 "$(grep -c '^run -d' "$FX/docker.log" || true)"
t_eq "...and no token is asked for" 0 "$(nlines "$FX/token.asked")"
t_has "...the log says which image to build or configure" "$OUT" "port-linux-runner:local"
t_eq "an unreadable events dir creates nothing" 0 "$(state; EVDIR=/nonexistent/x run up --apply >/dev/null; grep -c '^run -d' "$FX/docker.log" || true)"

t_section "up: a stopped container is started, a busy one is never touched"
reset; hold; container beta-linux port-linux-runner:interim exited; container alpha-linux port-linux-runner:interim running
runner alpha online true; run up --apply >/dev/null
t_has "the stopped container is started" "$(cat "$FX/docker.log")" "start beta-linux"
t_hasnt "the busy one is not started, stopped or removed" "$(grep -e alpha-linux "$FX/docker.log" | grep -v -e '^ps' -e '^top' -e '^inspect' || echo none)" "alpha-linux"
t_eq "...and nothing was created" 0 "$(grep -c '^run -d' "$FX/docker.log" || true)"

t_section "down: refuses a busy container, removes the container and the registration"
state; runner alpha online true; OUT="$(run down alpha --apply)"; RC=$?
t_eq "busy per GitHub: refused" 1 "$RC"
t_eq "...the container stays" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
t_eq "...the registration stays" 0 "$(nlines "$FX/deletes.log")"
state; : > "$FX/busy.alpha-linux"; run down alpha --apply >/dev/null
t_eq "busy per its own Runner.Worker, GitHub saying idle: refused too" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
state; OUT="$(run down alpha)"
t_has "the dry run says what it would remove" "$OUT" "would remove alpha-linux"
t_eq "...and removes nothing" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
state; runner alpha online false 21; OUT="$(run down alpha --apply)"
t_has "idle: the container is removed" "$(cat "$FX/docker.log")" "rm -f alpha-linux"
t_has "...and the registration is deleted by id, with no token" "$(cat "$FX/deletes.log")" "repos/VytCepas/alpha/actions/runners/21"
t_eq "...as one checks.log line" 1 "$(nlog)"
t_exit "harbor-linux is not a fleet runner: refused" 2 env FX="$FX" HARBOR_GH="$GH" HARBOR_DOCKER="$DOCKER" HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/ci-runners.sh" down harbor --apply
t_exit "a repo name that is not a name is refused" 2 env FX="$FX" HARBOR_GH="$GH" HARBOR_DOCKER="$DOCKER" HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/ci-runners.sh" down 'a;b' --apply

t_section "an org runner and an extra repo: listed (harbor#1060)"
reset; orgconf; list
t_eq "the org is one desired row, its runner not there yet" "true missing someorg-linux" "$(row someorg '"\(.want) \(.verdict) \(.name)"')"
t_eq "...its slug is the bare org" SomeOrg "$(row someorg .slug)"
t_eq "the org's fleet repo is served by the org runner, with no container of its own" "false org someorg-linux" "$(row orgrepo '"\(.want) \(.verdict) \(.name)"')"
t_eq "an owner no config names stays foreign" foreign "$(row stranger .verdict)"
t_eq "a repo named by a repo line, though the fleet does not list it, is desired" "true missing VytCepas/zarija" "$(row zarija '"\(.want) \(.verdict) \(.slug)"')"
t_has "the org's runners are read at the org" "$(cat "$FX/gh.log")" "api orgs/SomeOrg/actions/runners"
t_has "...and its CI_RUNS_ON is the org-level variable" "$(cat "$FX/gh.log")" "variable get CI_RUNS_ON --org SomeOrg"
reset; list
t_eq "control: with no org line there is no org row" "" "$(row someorg .repo)"
t_eq "control: ...and the org's repo is foreign" foreign "$(row orgrepo .verdict)"
reset; container zarija-linux port-linux-runner:local running; list
t_eq "control: with no repo line, a zarija-linux container is extra" extra "$(row zarija .verdict)"
reset; orgconf; container zarija-linux port-linux-runner:local running; runner zarija online false; list
t_eq "with the repo line the same container is owned, and ok" ok "$(row zarija .verdict)"

t_section "up --apply: the org runner is registered at the org"
reset; hold; orgconf; OUT="$(run up --apply)"
t_has "the org token is asked of the org" "$(cat "$FX/gh.log")" "api -X POST orgs/SomeOrg/actions/runners/registration-token"
t_eq "tokens were asked for the missing repos, zarija and the org, nothing else" "alpha beta org.SomeOrg zarija" "$(sort "$FX/token.asked" | tr '\n' ' ' | sed 's/ $//')"
t_has "a container named <org lower-cased>-linux is created" "$(cat "$FX/docker.log")" "--name someorg-linux"
t_has "...and one for the extra repo" "$(cat "$FX/docker.log")" "--name zarija-linux"
t_has "the org container carries the governor's events mount" "$(grep 'name someorg-linux' "$FX/docker.log")" "-v $EVENTS:/gov-events"
t_hasnt "no token on any argv" "$(cat "$FX/docker.log" "$FX/gh.log")" "TOKEN-SECRET"
t_hasnt "...nor on the screen" "$OUT" "TOKEN-SECRET"
t_eq "no container for the org's repo itself" 0 "$(grep -c 'name orgrepo-linux' "$FX/docker.log" || true)"
reset; orgconf; container someorg-linux port-linux-runner:local running; orgrunner online false; run up --apply >/dev/null
t_eq "idempotent: an org container that exists is adopted, no token asked for it" "" "$(grep org.SomeOrg "$FX/token.asked" 2>/dev/null || true)"
reset; printf 'org SomeOrg\n' >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; hold
container alpha-linux port-linux-runner:local running; container beta-linux port-linux-runner:local running; run up --apply >/dev/null
t_eq "with every repo runner present, only the org's is created" "--name someorg-linux" "$(grep '^run -d' "$FX/docker.log" | grep -o -e '--name [a-z-]*')"
t_has "...registered at the org's URL" "$(cat "$FX/envfile.captured")" "RUNNER_URL=https://github.com/SomeOrg"
t_has "...under the org runner's name" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=someorg-linux"

t_section "down: the org runner and the extra repo"
reset; orgconf; container someorg-linux port-linux-runner:local running; orgrunner online true; run down someorg --apply >/dev/null
t_eq "a busy org runner is refused" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
reset; orgconf; container someorg-linux port-linux-runner:local running; orgrunner online false 31; run down someorg --apply >/dev/null
t_has "an idle org container is removed" "$(cat "$FX/docker.log")" "rm -f someorg-linux"
t_has "...and its registration deleted at the org" "$(cat "$FX/deletes.log")" "orgs/SomeOrg/actions/runners/31"
reset; orgconf; container zarija-linux port-linux-runner:local running; runner zarija online false 41; run down zarija --apply >/dev/null
t_has "an extra repo's container is removed" "$(cat "$FX/docker.log")" "rm -f zarija-linux"
t_has "...and its registration deleted on the repo" "$(cat "$FX/deletes.log")" "repos/VytCepas/zarija/actions/runners/41"
t_eq "no stub call was off script: OtherOrg was never asked about" 0 "$(nlines "$FX/unexpected.log")"

t_section "mount lines: read-only binds into the repo's own container, refused when they would mount empty"
# RH: the image user's HOME, never spelt whole: on CI it is $HOME, and lint.no-home-path greps for that
MROOT="$(cd -P "$T_TMP" && pwd -P)"; MH="$MROOT/home"; RU=runner; RH="/home/$RU"; mkdir -p "$MH/.claude/skills/topology" "$MH/port/harbor"
cfg() { printf '%s\n' "$@" >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
mounts() { cfg "mount beta $MH/.claude/skills/topology ~/.claude/skills/topology" "mount beta $MH/port/harbor ~/port/harbor"; }
created() { grep "^run -d.*--name $1-linux" "$FX/docker.log" || true; }
reset; hold; mounts; OUT="$(run up)"
t_has "the dry run counts the mounts it would add" "$OUT" "would create beta-linux for VytCepas/beta (image port-linux-runner:local, 2 read-only mounts)"
reset; hold; mounts; OUT="$(run up --apply)"; BETA="$(created beta)"
t_has "a mount line binds the host path at the runner's HOME, read-only" "$BETA" "-v $MH/.claude/skills/topology:$RH/.claude/skills/topology:ro"
t_has "...every line of that repo" "$BETA" "-v $MH/port/harbor:$RH/port/harbor:ro"
t_eq "...and no bind on the argv is writable but the governor's events dir" "$EVENTS:/gov-events" \
  "$(printf '%s\n' "$BETA" | grep -o -e '-v [^ ]*' | sed 's/^-v //' | grep -v ':ro$')"
t_eq "another repo's container gets none of them" "$EVENTS:/gov-events" "$(created alpha | grep -o -e '-v [^ ]*' | sed 's/^-v //')"
t_has "the creation line counts them" "$(cat "$CACHE/checks.log")" "beta-linux created for VytCepas/beta (image port-linux-runner:local, 2 read-only mounts)"
OUT="$(run list)"
t_eq "list: the container up made matches the config, line by line" 2 "$(printf '%s\n' "$OUT" | grep -c -e "-> $RH/.* ok\$")"
t_hasnt "...and reports no drift" "$OUT" "DRIFT"

t_section "mount drift: an adopted container is reported, never recreated"
reset; hold; mounts; container beta-linux port-linux-runner:local running; runner beta online false; OUT="$(run list)"; RC=$?
t_has "a container made without the mounts is drift" "$OUT" "-> $RH/port/harbor  DRIFT: not on beta-linux"
t_has "...named once, with the way to recreate it" "$OUT" "beta-linux: its mounts differ from the config"
t_eq "...list still answers 0" 0 "$RC"
run up --apply >/dev/null
t_eq "up does not recreate, stop or remove it" 0 "$(grep -c -e '^run .*beta-linux' -e '^rm .*beta-linux' -e '^stop .*beta-linux' "$FX/docker.log" || true)"
t_eq "control: up did create the missing alpha in the same run" 1 "$(grep -c '^run .*alpha-linux' "$FX/docker.log" || true)"
printf '%s %s true\n' "$MH/port/harbor" "$RH/port/harbor" > "$FX/mounts.beta-linux"
printf '%s %s false\n' "$MH/.claude/skills/topology" "$RH/.claude/skills/topology" >> "$FX/mounts.beta-linux"
printf '%s %s false\n' "$MH" "$RH/everything" >> "$FX/mounts.beta-linux"
OUT="$(run list)"
t_has "a mount the container has read-write is drift" "$OUT" "-> $RH/port/harbor  DRIFT: read-write on beta-linux"
t_has "a mount the config does not name is drift" "$OUT" "-> $RH/everything  DRIFT: on beta-linux (ro), not in the config"
t_has "control: the matching line is ok" "$OUT" "-> $RH/.claude/skills/topology  ok"
reset; hold; container alpha-linux port-linux-runner:local running; printf '%s /x false\n' "$MH" > "$FX/mounts.alpha-linux"
t_has "a container with binds and no mount lines at all is drift too" "$(run list)" "DRIFT: on alpha-linux (ro), not in the config"
reset; hold; cfg "mount ghost $MH/port/harbor ~/port/harbor"; OUT="$(run list)"; RC=$?
t_has "a mount line for a repo with no container is listed" "$OUT" "ghost                  $MH/port/harbor -> $RH/port/harbor  no container"
t_eq "...and is not an error" 0 "$RC"

t_section "mount lines refused: nothing is created, no token is asked"
refused() { # <expected reason> <mount line...> — the line refuses beta's container, and alpha is still created
  reset; hold; cfg "$@"; OUT="$(run up --apply)"
  t_has "refused: $1" "$OUT" "beta-linux: mount refused, so it is not created:"
  t_eq "...no beta-linux" "" "$(created beta)"
  t_eq "...no token for beta" "alpha" "$(cat "$FX/token.asked" | tr '\n' ' ' | sed 's/ $//')"
}
refused "a host path outside the shared root" "mount beta /etc ~/etc"
t_has "...says why: Colima would mount it empty" "$OUT" "/etc is outside $MROOT/: Colima shares only that into its VM"
refused "a host path that does not exist" "mount beta $MH/port/flow ~/port/flow"
t_has "...says it would mount empty" "$OUT" "$MH/port/flow does not exist: it would mount empty"
refused "a mode field: mounts are always read-only" "mount beta $MH/port/harbor ~/port/harbor rw"
refused "a .. segment that walks out of the root" "mount beta $MH/../../etc ~/etc"
ln -s /etc "$MH/elsewhere"
refused "a symlink that resolves outside the root" "mount beta $MH/elsewhere ~/etc"
refused "a container path that is not absolute" "mount beta $MH/port/harbor port/harbor"
reset; hold; cfg "mount beta /etc ~/etc"; OUT="$(MROOT= run up --apply)"
t_has "the default shared root is /Users/" "$OUT" "/etc is outside /Users/: Colima shares only that into its VM"
reset; hold; cfg "mount beta /etc ~/etc"; OUT="$(run up)"; RC=$?
t_has "a dry run names the refusal too" "$OUT" "beta-linux: mount refused, so it is not created:"
t_eq "...and fails" 1 "$RC"
reset; hold; cfg "mount beta /etc ~/etc"; OUT="$(run list)"; RC=$?
t_has "list shows a refused line" "$OUT" "/etc -> ~/etc  refused: /etc is outside"
t_eq "...and answers 0" 0 "$RC"

t_section "stale image: list flags it, refresh recreates only idle stale rows (harbor#1075)"
# alpha: stale and idle; beta: stale and busy; harbor-linux: stale and no fleet row
fx() { state; container beta-linux port-linux-runner:local running; runner beta online false 22; stale alpha-linux; stale beta-linux
       container harbor-linux port-linux-runner:local running; stale harbor-linux; }
fxbusy() { fx; runner beta online true 22; }
touched() { grep -e "$1" "$FX/docker.log" | grep -c -e '^rm ' -e '^run ' -e '^stop ' -e '^start ' || true; }
fxbusy; list
t_eq "an online container on an older image is stale" stale "$(row alpha .verdict)"
t_eq "...a busy one too, and busy stays visible" "stale true" "$(row beta '"\(.verdict) \(.busy)"')"
t_eq "control: a container on the tag's current image stays ok" ok "$(reset; container alpha-linux port-linux-runner:local running; runner alpha online false; list; row alpha .verdict)"
t_eq "control: a stopped container on an old image is reported stopped, the louder verdict" stopped \
  "$(reset; container alpha-linux port-linux-runner:local exited; stale alpha-linux; list; row alpha .verdict)"
t_eq "the tag moved and a container made from the new build is not flagged" ok \
  "$(reset; container alpha-linux port-linux-runner:local running; runner alpha online false; printf 'sha256:new\n' > "$FX/tagid"; printf 'sha256:new\n' > "$FX/cid.alpha-linux"; list; row alpha .verdict)"
fxbusy; OUT="$(run list)"
t_has "the text verdict names the fix command" "$OUT" "refresh --apply"
t_has "harbor-linux is a governance row, stale, and the text names how to refresh it" "$OUT" "governance, stale (read-only: sh"
t_eq "list wrote nothing to docker" 0 "$(grep -c -e '^run ' -e '^rm ' -e '^start ' "$FX/docker.log" || true)"

fxbusy; OUT="$(run refresh)"; RC=$?
t_has "the dry run says it would recreate alpha-linux" "$OUT" "would recreate alpha-linux for VytCepas/alpha: image old -> cur"
t_has "...skips the busy beta-linux, naming why" "$OUT" "beta-linux is running a job"
t_eq "...and harbor-linux is no target of it" 0 "$(touched harbor-linux)"
t_has "...says harbor-linux is left unless asked for by name" "$OUT" "harbor-linux (governance) is on an older image too; refresh leaves it unless --include-governance"
t_eq "...exits 0" 0 "$RC"
t_eq "...removes and creates nothing, asks for no token, deletes no registration" "0 0 0 0" \
  "$(grep -c '^run ' "$FX/docker.log" || true) $(grep -c '^rm ' "$FX/docker.log" || true) $(nlines "$FX/token.asked") $(nlines "$FX/deletes.log")"
t_eq "...and logs nothing to checks.log" 0 "$(nlog)"

fxbusy; OUT="$(run refresh --apply)"; RC=$?
t_eq "apply: exactly one container is removed, alpha-linux" "rm -f alpha-linux" "$(grep '^rm ' "$FX/docker.log")"
t_eq "...and exactly one created" 1 "$(grep -c '^run -d' "$FX/docker.log")"
RUNLINE="$(grep '^run -d' "$FX/docker.log")"
t_has "...named alpha-linux" "$RUNLINE" "--name alpha-linux"
t_has "...restart policy, one core, one gigabyte" "$RUNLINE" "--restart unless-stopped --cpus 1 --memory 1g"
t_has "...the governor's events mount" "$RUNLINE" "-v $EVENTS:/gov-events"
t_has "...the job-started hook" "$RUNLINE" "ACTIONS_RUNNER_HOOK_JOB_STARTED=/gov-events/ci-governor-hook.sh"
t_has "...the job-completed hook" "$RUNLINE" "ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh"
t_has "...the tag" "$RUNLINE" "port-linux-runner:local"
t_has "...its old registration was deleted by id" "$(cat "$FX/deletes.log")" "repos/VytCepas/alpha/actions/runners/7"
t_eq "...a token was asked for alpha only" alpha "$(cat "$FX/token.asked")"
t_has "...carrying the runner name" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=alpha-linux"
t_hasnt "...the token is on no argv and not on the screen" "$(cat "$FX/docker.log" "$FX/gh.log") $OUT" "TOKEN-SECRET"
t_eq "...the busy beta-linux was not touched" 0 "$(touched beta-linux)"
t_eq "...harbor-linux was not touched" 0 "$(touched harbor-linux)"
t_eq "...one checks.log line for the refresh and one for the creation" 2 "$(nlog)"
t_eq "...exits 0" 0 "$RC"
t_eq "...alpha is ok now and beta is still stale" "ok stale" "$(list; echo "$(row alpha .verdict) $(row beta .verdict)")"
run refresh --apply >/dev/null
t_eq "idempotent: a second apply recreates nothing more" 1 "$(grep -c '^run -d' "$FX/docker.log")"

fx; : > "$FX/busy.alpha-linux"; OUT="$(run refresh --apply)"
t_eq "busy per its own Runner.Worker while GitHub says idle: skipped, the idle one is recreated" "rm -f beta-linux" "$(grep '^rm ' "$FX/docker.log")"
fxbusy; touch "$FX/runners.fail"; OUT="$(run refresh --apply)"; RC=$?
t_eq "GitHub not answering: nothing is removed" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
t_has "...and it says why" "$OUT" "GitHub did not answer, so it cannot be told whether the runner is busy"
t_eq "...and fails" 1 "$RC"

fx; touch "$FX/docker.runfail"; OUT="$(run refresh --apply)"; RC=$?
t_eq "a create that fails stops the loop: one run attempted" 1 "$(grep -c '^run -d' "$FX/docker.log")"
t_eq "...only alpha was removed, beta is untouched" "rm -f alpha-linux" "$(grep '^rm ' "$FX/docker.log")"
t_has "...it says what is gone and what is left" "$OUT" "alpha-linux was removed and not recreated; the rest are untouched"
t_eq "...and exits 1" 1 "$RC"
fx; : > "$FX/images"; run refresh --apply >/dev/null
t_eq "an image that is not on the box refuses before removing anything" 0 "$(grep -c '^rm ' "$FX/docker.log" || true)"
t_eq "neither stub was called off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "governance row: harbor-linux in list, read-only (harbor#1083)"
EV2="$T_TMP/gov-events-real"; mkdir -p "$EV2"
gfx() { reset; hold; container harbor-linux port-linux-runner:local running; stale harbor-linux; runner harbor online false 55
        printf '4294967296\n' > "$FX/memory.harbor-linux"; printf '%s\n' "$EV2" > "$FX/events.harbor-linux"; }
gtouched() { [ -f "$FX/docker.log" ] || { echo 0; return; }; grep -e 'harbor-linux' "$FX/docker.log" | grep -c -e '^rm ' -e '^run ' -e '^stop ' -e '^start ' || true; }
gfx; list
t_eq "list carries a governance row for harbor-linux, not wanted as a fleet repo" "harbor false governance harbor-linux" "$(row harbor '"\(.repo) \(.want) \(.verdict) \(.name)"')"
t_eq "...with container state, image and stale" "running port-linux-runner:local true true" "$(row harbor '"\(.container) \(.image) \(.stale) \(.governance)"')"
t_eq "...and the runner GitHub names harbor-linux, online and idle" "online false 55" "$(row harbor '"\(.runner) \(.busy) \(.runner_id)"')"
t_eq "the fleet rows keep their fields and say governance false, stale false" "false false" "$(state; list; row alpha '"\(.governance) \(.stale)"')"
gfx; : > "$FX/busy.harbor-linux"; list
t_eq "busy comes from docker top when GitHub says idle" true "$(row harbor .busy)"
gfx; runner harbor online true 55; list
t_eq "...and from GitHub when docker top shows no Worker" true "$(row harbor .busy)"
t_eq "a current-image harbor-linux is a governance row that is not stale" "governance false" "$(gfx; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; list; row harbor '"\(.verdict) \(.stale)"')"
t_eq "GitHub not answering reads as unknown, not idle" unknown "$(gfx; touch "$FX/runners.fail"; list; row harbor .runner)"
gfx; OUT="$(run list)"
t_has "the text table shows harbor-linux with the refresh command" "$OUT" "refresh --apply --include-governance"
t_eq "list asked GitHub for harbor's runners and wrote nothing" 0 "$(grep -c -e POST -e DELETE "$FX/gh.log" || true)"
t_eq "...and docker only read" 0 "$(gtouched)"

t_section "refresh: harbor-linux only with --include-governance, idle, and no queued run (harbor#1083)"
gfx; OUT="$(run refresh --apply)"
t_eq "without the flag --apply never touches harbor-linux" "0 0" "$(gtouched) $(nlines "$FX/deletes.log")"
t_hasnt "...and asks for no token" "$(cat "$FX/token.asked" 2>/dev/null || echo none)" "harbor"
gfx; OUT="$(run refresh --include-governance)"
t_has "the dry run says what it would recreate, with the values it reproduces" "$OUT" "would recreate harbor-linux for VytCepas/harbor: image old -> cur, cpus 1, memory 4294967296b, events $EV2:/gov-events"
t_eq "...and touches nothing" "0 0 0" "$(gtouched) $(nlines "$FX/deletes.log") $(nlines "$FX/token.asked")"
gfx; runner harbor online true 55; OUT="$(run refresh --apply --include-governance)"
t_has "a busy runner (GitHub): skipped, naming why" "$OUT" "harbor-linux is running a job"
t_eq "...nothing touched" 0 "$(gtouched)"
gfx; : > "$FX/busy.harbor-linux"; run refresh --apply --include-governance >/dev/null
t_eq "a Runner.Worker in the container while GitHub says idle: skipped" 0 "$(gtouched)"
mkdir -p "$FX/queue"
gfx; mkdir -p "$FX/queue"; echo '{"workflow_runs":[{"id":901}]}' > "$FX/queue/harbor.queued.json"; OUT="$(run refresh --apply --include-governance)"
t_has "an idle runner with a queued harbor run: skipped, naming why" "$OUT" "VytCepas/harbor has queued or in-progress runs"
t_eq "...nothing touched, no token asked" "0 0" "$(gtouched) $(nlines "$FX/token.asked")"
gfx; mkdir -p "$FX/queue"; echo '{"workflow_runs":[{"id":902}]}' > "$FX/queue/harbor.in_progress.json"; run refresh --apply --include-governance >/dev/null
t_eq "an idle runner with an in-progress harbor run: skipped too" 0 "$(gtouched)"
gfx; touch "$FX/queue.fail"; OUT="$(run refresh --apply --include-governance)"; RC=$?
t_eq "GitHub not answering about the runs: nothing is removed" 0 "$(gtouched)"
t_has "...and it says it cannot be told the checks are idle" "$OUT" "cannot be told its checks are idle"
t_eq "...and fails" 1 "$RC"
gfx; touch "$FX/runners.fail"; run refresh --apply --include-governance >/dev/null
t_eq "GitHub not answering about the runner: nothing is removed" 0 "$(gtouched)"
gfx; printf 'sha256:cur\n' > "$FX/cid.harbor-linux"; run refresh --apply --include-governance >/dev/null
t_eq "a harbor-linux on the current image is left" 0 "$(gtouched)"

gfx; printf 'linux_min = 2\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"; OUT="$(run refresh --apply --include-governance)"; RC=$?
rm -f "$CLAUDE_CONFIG_DIR/.harbor-ci-governor"
t_eq "idle, no queue, stale: harbor-linux is removed and created, once each" "rm -f harbor-linux 1" "$(grep '^rm ' "$FX/docker.log") $(grep -c '^run -d' "$FX/docker.log")"
RUNLINE="$(grep '^run -d' "$FX/docker.log")"
t_has "...named harbor-linux" "$RUNLINE" "--name harbor-linux"
t_has "...restart policy, the governor's linux_min as cpus, and the old container's memory" "$RUNLINE" "--restart unless-stopped --cpus 2 --memory 4294967296b"
t_has "...the events mount at /gov-events from where the old one had it, read-write" "$RUNLINE" "-v $EV2:/gov-events"
t_has "...the job-started hook" "$RUNLINE" "-e ACTIONS_RUNNER_HOOK_JOB_STARTED=/gov-events/ci-governor-hook.sh"
t_has "...the job-completed hook" "$RUNLINE" "-e ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh"
t_has "...on the configured tag" "$RUNLINE" "port-linux-runner:local"
t_eq "...with no other bind" "$EV2:/gov-events" "$(printf '%s\n' "$RUNLINE" | grep -o -e '-v [^ ]*' | sed 's/^-v //')"
t_has "...registered on the governance repo by the runner's own name" "$(cat "$FX/envfile.captured")" "RUNNER_URL=https://github.com/VytCepas/harbor"
t_has "...named harbor-linux" "$(cat "$FX/envfile.captured")" "RUNNER_NAME=harbor-linux"
t_has "...with the labels it had, plus the pool label" "$(cat "$FX/envfile.captured")" "RUNNER_LABELS=self-hosted,Linux,ARM64,harbor-pool"
t_eq "...a token was asked for harbor only" harbor "$(cat "$FX/token.asked")"
t_has "...its old registration was deleted by id" "$(cat "$FX/deletes.log")" "repos/VytCepas/harbor/actions/runners/55"
t_hasnt "...the token is on no argv and not on the screen" "$(cat "$FX/docker.log" "$FX/gh.log") $OUT" "TOKEN-SECRET"
t_eq "...exits 0" 0 "$RC"
t_has "...one checks.log line says it was the governance runner" "$(cat "$CACHE/checks.log")" "harbor-linux refreshed (governance)"
t_eq "a create that fails is reported with the way back, and the next run makes it" "1" "$(gfx; touch "$FX/docker.runfail"; run refresh --apply --include-governance | grep -c 'removed and not recreated')"
rm -f "$FX/docker.runfail"; run refresh --apply --include-governance >/dev/null
t_has "an absent harbor-linux is made again by the same command" "$(grep '^run -d' "$FX/docker.log" | tail -n 1)" "--name harbor-linux"
t_has "...with the defaults for what it cannot read: 4g and the configured events dir" "$(grep '^run -d' "$FX/docker.log" | tail -n 1)" "--memory 4g"
t_has "...the events dir" "$(grep '^run -d' "$FX/docker.log" | tail -n 1)" "-v $EVENTS:/gov-events"
t_exit "--include-governance on any other command is refused" 2 env FX="$FX" HARBOR_GH="$GH" HARBOR_DOCKER="$DOCKER" HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/ci-runners.sh" switch --apply --include-governance

t_section "up, switch, down and the cache never act on the governance row (harbor#1083)"
gfx; run up --apply >/dev/null; run switch --apply >/dev/null; run tick >/dev/null
t_eq "up, switch and tick leave harbor-linux alone" 0 "$(gtouched)"
t_eq "...the cache does not name it" "" "$(jq -r '[.ok, .missing, .offline, .stopped, .held, .extra] | add | map(select(. == "harbor" or . == "harbor-linux")) | join(" ")' "$CACHE/ci-runners.json")"
t_eq "...and no registration of harbor was deleted, no variable of it written" 0 "$(nlines "$FX/deletes.log")$(grep -c harbor "$FX/writes.log" 2>/dev/null || true)"
gfx; run down harbor --apply >/dev/null || :
t_eq "down harbor is refused, and touches nothing" 0 "$(gtouched)"
t_eq "...no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"
gfx; run refresh --apply --include-governance >/dev/null   # the last run's gh calls are what the billing check below reads

t_section "refresh re-checks busy right before each rm (rows are read once at the start)"
fx; echo 1 > "$FX/busyafter.alpha-linux"; OUT="$(run refresh --apply)"
t_eq "a fleet runner idle at the read but busy at the rm is not removed" 0 "$(grep -c '^rm -f alpha-linux' "$FX/docker.log" || true)"
t_has "...and the skip says why" "$OUT" "alpha-linux took a job since the list was read"
fx; run refresh --apply >/dev/null
t_eq "the same runner, idle throughout, is still recreated" 1 "$(grep -c '^rm -f alpha-linux' "$FX/docker.log" || true)"
gfx; echo 1 > "$FX/busyafter.harbor-linux"; OUT="$(run refresh --apply --include-governance)"
t_eq "harbor-linux busy only by the rm: not removed, no registration deleted" "0 0" "$(grep -c '^rm -f harbor-linux' "$FX/docker.log" || true) $(nlines "$FX/deletes.log")"
t_has "...and the skip says why" "$OUT" "harbor-linux took a job since the list was read"
gfx; runner harbor online false 55; echo 1 > "$FX/ghflip.harbor"; run refresh --apply --include-governance >/dev/null
t_eq "...a GitHub .busy flip alone (docker shows no Worker) is caught too" 0 "$(grep -c '^rm -f harbor-linux' "$FX/docker.log" || true)"
fx; echo 1 > "$FX/ghflip.alpha"; run refresh --apply >/dev/null
t_eq "...and for a fleet runner" 0 "$(grep -c '^rm -f alpha-linux' "$FX/docker.log" || true)"

t_section "gate runners: gate N, the gate and pool labels (harbor#1286)"
gcfg() { reset; hold; for _l in "$@"; do printf '%s\n' "$_l" >> "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; done; }
glist() { run list --json > "$FX/list.json"; }
gate_rows() { jq -r '[.[] | select(.gate) | .name] | join(" ")' "$FX/list.json"; }
gcfg; glist
t_eq "no gate line: no gate row (default 0)" "" "$(gate_rows)"
gcfg "gate 2"; glist
t_eq "gate 2: rows harbor-gate and harbor-gate-2" "harbor-gate harbor-gate-2" "$(gate_rows)"
t_eq "...absent, verdict gate, read-only (governance false, want false)" "absent gate false false" "$(row harbor-gate '"\(.container) \(.verdict) \(.governance) \(.want)"')"
t_has "...the text table shows the gate row" "$(run list)" "gate"
t_eq "gate 0, gate 10 and gate x are all no gate runner" "" "$(for v in 0 10 x; do gcfg "gate $v"; glist; gate_rows; done)"
gcfg "gate 1"; OUT="$(run up --include-governance)"
t_has "dry run: names the gate runner, its label, cpus and memory" "$OUT" "would create harbor-gate for VytCepas/harbor: labels self-hosted,Linux,ARM64,harbor-gate, image port-linux-runner:local, cpus 1, memory 2g"
t_eq "...and runs nothing for it" 0 "$(grep -c '^run -d.*harbor-gate' "$FX/docker.log" || true)"
gcfg "gate 1"; run up --apply >/dev/null
t_eq "up --apply without --include-governance never creates a gate runner" 0 "$(grep -c 'harbor-gate' "$FX/docker.log" || true)"
gcfg "gate 2" "limits harbor-gate-2 memory 3g cpus 2"; OUT="$(run up --apply --include-governance)"
GRUN="$(grep '^run -d' "$FX/docker.log" | grep -e '--name harbor-gate ')"
t_has "up --apply --include-governance creates harbor-gate at cpus 1, memory 2g" "$GRUN" "--restart unless-stopped --cpus 1 --memory 2g"
t_has "...with the events mount and both hooks, as a governance runner" "$GRUN" "-e ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/gov-events/ci-governor-hook.sh"
t_eq "...and no read-only mount" 0 "$(printf '%s\n' "$GRUN" | grep -c ':ro')"
t_has "harbor-gate-2 takes its own limits line (cpus 2, memory 3g)" "$(grep '^run -d' "$FX/docker.log" | grep -e '--name harbor-gate-2 ')" "--cpus 2 --memory 3g"
t_eq "...the last registration is harbor-gate-2 on the governance repo, labelled harbor-gate" "RUNNER_URL=https://github.com/VytCepas/harbor RUNNER_NAME=harbor-gate-2 RUNNER_LABELS=self-hosted,Linux,ARM64,harbor-gate" \
  "$(grep -e RUNNER_URL -e RUNNER_NAME -e RUNNER_LABELS "$FX/envfile.captured" | tr '\n' ' ' | sed 's/ $//')"
t_eq "...two gate runners made" 2 "$(grep '^run -d' "$FX/docker.log" | grep -c -e "--name harbor-gate")"
t_eq "...no token reached an argv or the screen" 0 "$(printf '%s %s' "$(cat "$FX/docker.log" "$FX/gh.log")" "$OUT" | grep -c TOKEN-SECRET)"
gcfg; run up --apply --include-governance >/dev/null
t_eq "a governance runner is registered with the pool label too" "RUNNER_NAME=harbor-linux RUNNER_LABELS=self-hosted,Linux,ARM64,harbor-pool" \
  "$(grep -e RUNNER_NAME -e RUNNER_LABELS "$FX/envfile.captured" | tr '\n' ' ' | sed 's/ $//')"
t_eq "a fleet runner carries neither label" "RUNNER_LABELS=self-hosted,Linux,ARM64" "$(gcfg; run up --apply >/dev/null; grep RUNNER_LABELS "$FX/envfile.captured")"
gcfg "gate 1"; container harbor-gate port-linux-runner:local running; run up --apply --include-governance >/dev/null
t_eq "a gate runner that exists is adopted, not recreated" 0 "$(grep -c '^rm \|^run -d.*--name harbor-gate ' "$FX/docker.log" || true)"
gcfg "gate 1"; container harbor-gate port-linux-runner:local exited; run up --apply --include-governance >/dev/null
t_eq "...a stopped one is started" 1 "$(grep -c '^start harbor-gate' "$FX/docker.log" || true)"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"

t_section "no billing call, ever"
t_eq "gh was never asked about billing, budgets or the spending limit" 0 "$(cat "$FX"/gh.log | grep -c -i -e billing -e budget -e spending || true)"
t_eq "the script does not contain such a call" 0 "$(grep -v '^#' "$T_ROOT/bin/ci-runners.sh" | grep -c -i -e 'settings/billing' -e 'budgets' -e 'spending_limit' || true)"
t_eq "no stub call was off script" 0 "$(nlines "$FX/unexpected.log")"
t_done
