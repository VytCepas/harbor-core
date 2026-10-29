#!/usr/bin/env sh
# alert-probe.sh, the probe (harbor#9, E1). Every case builds a fixture config dir that looks like
# the live box: floor-install wires each guard as its own entry with the guard passed to
# floor-hook.sh, so a one-line fixture could not tell a complete floor from a partial one.
# The wiring matrix and the floor predicate are copies (of floor-install.sh, status-generate.sh);
# the drift and agreement cases fail when a copy drifts. The notifier is pulse-notify-test.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_TEST_IN_SUITE HARBOR_IN_SUITE  # t_init keeps status-gen's re-entry marker; this suite runs status-gen at top level (harbor#773)
P="$T_ROOT/bin/alert-probe.sh"; TMP="$T_TMP/pulse"; mkdir -p "$TMP"
mkcfg() { # <name> <deny: sentinel|unrelated|empty> <hooks: full|no-mcp|no-advis|bash-only|shim|odd|none> <missing-guard|->
  _d="$TMP/$1"; mkdir -p "$_d/bin" "$_d/cache"
  for _g in floor-hook.sh guard-lib.sh guard-bash.sh guard-egress.sh guard-selfedit.sh annotate-web.sh floor-normalize.awk; do
    [ "$_g" = "$4" ] || echo '# guard' > "$_d/bin/$_g"
  done
  case "$2" in
    sentinel)  _deny="$(jq -n --arg a 'Edit(~/.claude/.helm-floor-teeth)' --arg b 'Edit(//**/.github/workflows/**)' '[$a,$b]')" ;;
    unrelated) _deny='["Bash(rm -rf /*)","Read(./.env)"]' ;;
    *)         _deny='[]' ;;
  esac
  # The eight (event, matcher, guard) triples floor-install.sh wires through floor-hook.sh (Monitor: pass 14 E-4;
  # Grep: harbor#1313 L6).
  _mk_full='[{"e":"PreToolUse","m":"Bash","g":"guard-bash.sh"},
             {"e":"PreToolUse","m":"Monitor","g":"guard-bash.sh"},
             {"e":"PreToolUse","m":"Monitor","g":"guard-egress.sh"},
             {"e":"PreToolUse","m":"Grep","g":"guard-egress.sh"},
             {"e":"PreToolUse","m":"Bash|Write|Edit|MultiEdit","g":"guard-egress.sh"},
             {"e":"PreToolUse","m":"mcp__.*|Task|Agent|WebFetch|WebSearch|NotebookEdit","g":"guard-egress.sh"},
             {"e":"PreToolUse","m":"Write|Edit|MultiEdit","g":"guard-selfedit.sh"},
             {"e":"PostToolUse","m":"WebFetch|WebSearch|ToolSearch|mcp__.*","g":"annotate-web.sh"}]'
  case "$3" in
    full|odd)  _trip="$_mk_full" ;;
    no-mcp)    _trip="$(jq -n --argjson t "$_mk_full" '$t | map(select(.m != "mcp__.*|Task|Agent|WebFetch|WebSearch|NotebookEdit"))')" ;;
    no-advis)  _trip="$(jq -n --argjson t "$_mk_full" '$t | map(select(.e != "PostToolUse"))')" ;;
    bash-only) _trip="$(jq -n --argjson t "$_mk_full" '$t | map(select(.g == "guard-bash.sh"))')" ;;
    *)         _trip='[]' ;;
  esac
  _pre="  "; [ "$3" = odd ] || _pre=""
  _cmds="$(jq -n --arg d "$_d" --arg pre "$_pre" --argjson t "$_trip" \
    '$t | map({event:.e, matcher:.m, command:($pre + "/bin/sh " + $pre + $d + "/bin/floor-hook.sh "
      + (if .e == "PostToolUse" then "--advisory " else "" end) + $d + "/bin/" + .g)})')"
  [ "$3" = shim ] && _cmds="$(jq -n --arg d "$_d" '[{event:"PreToolUse", matcher:"Bash", command:("/bin/sh " + $d + "/bin/prod-guard-ambient.sh")}]')"
  jq -n --argjson deny "$_deny" --argjson cmds "$_cmds" \
    '{permissions:{deny:$deny}, hooks:($cmds | group_by(.event)
      | map({key: .[0].event, value: map({matcher:.matcher, hooks:[{type:"command", command:.command}]})}) | from_entries)}' > "$_d/settings.json"
  printf '%s' "$_d"
}
run() { CLAUDE_CONFIG_DIR="$1" HARBOR_SCOPE_CACHE_DIR="$1/cache" sh "$P" --json 2>/dev/null; }
runv() { _c="$1"; shift; env CLAUDE_CONFIG_DIR="$_c" HARBOR_SCOPE_CACHE_DIR="$_c/cache" "$@" sh "$P" --json 2>/dev/null; }  # <cfg> VAR=… …
verdict() { printf '%s' "$1" | jq -r --arg k "$2" '.checks[$k].verdict // "ABSENT"'; }
detail()  { printf '%s' "$1" | jq -r --arg k "$2" '.checks[$k].detail // ""'; }
sg() { FAST=1 HARBOR_DEPLOY_LIVE_DIR="$1" sh "$T_ROOT/bin/status-generate.sh" --json-fast 2>/dev/null | jq -r ".observed.$2" 2>/dev/null || echo '?'; }

t_section "floor: the predicate"
WIRED="$(mkcfg wired sentinel full -)"
t_eq "a fully wired floor is ok" ok "$(verdict "$(run "$WIRED")" floor)"
O="$(run "$(mkcfg gone sentinel full guard-egress.sh)")"
t_eq "a hook at a missing guard file is crit" crit "$(verdict "$O" floor)"
t_has "the detail says what is missing" "$(detail "$O" floor)" "missing"
t_eq "deny live, nothing wired is warn" warn "$(verdict "$(run "$(mkcfg denyonly sentinel none -)")" floor)"
NAKED="$(mkcfg naked empty none -)"
t_eq "nothing wired and no deny is crit" crit "$(verdict "$(run "$NAKED")" floor)"
# The 2026-08-01 false green: prod-guard-ambient.sh matches test("guard-") but is not floor-hook.sh.
O="$(run "$(mkcfg shim sentinel shim -)")"
t_eq "a prod_guard shim is not a wired floor" warn "$(verdict "$O" floor)"

t_section "floor: partial layers are not a floor (REVIEW #106)"
O="$(run "$(mkcfg unrelated unrelated full -)")"
t_eq "an unrelated deny rule is not the B1 layer" warn "$(verdict "$O" floor)"
t_has "the detail names the missing sentinel" "$(detail "$O" floor)" "sentinel"
O="$(run "$(mkcfg bashonly sentinel bash-only -)")"
t_eq "one wired guard out of three is crit" crit "$(verdict "$O" floor)"
t_has "the detail names what is unwired" "$(detail "$O" floor)" "guard-egress"
O="$(run "$(mkcfg nomcp sentinel no-mcp -)")"
t_eq "the second egress matcher missing is crit" crit "$(verdict "$O" floor)"
t_has "the detail names the unwired guard" "$(detail "$O" floor)" "egress"
t_eq "the PostToolUse advisory counts as wiring" crit "$(verdict "$(run "$(mkcfg noadv sentinel no-advis -)")" floor)"
# floor-install's rows are its floor_hooks table (harbor#766): <event>;<matcher>;<argv>;…
_inst="$(awk -F';' '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit }
    f && ($1 == "PreToolUse" || $1 == "PostToolUse") && $3 ~ /^floor-hook\.sh / {
      n = split($3, a, " "); printf "%s\t%s\t%s\n", $1, $2, a[n] }' "$T_ROOT/bin/floor-install.sh" | sort)"
_mine="$(awk -F'\t' 'NF == 3 && ($1 == "PreToolUse" || $1 == "PostToolUse") { print }' "$P" | sort)"
t_has "the extractor finds floor-install's wiring rows" "$_inst" "guard-bash.sh"
t_eq "alert-probe.sh's wiring matrix matches floor-install.sh" "$_inst" "$_mine"

t_section "floor: unknown and the valid-but-unusual control"
BARE="$TMP/bare"; mkdir -p "$BARE/cache"
t_eq "a missing settings.json is unknown" unknown "$(verdict "$(run "$BARE")" floor)"
t_eq "an absolute hook path with extra whitespace stays ok" ok "$(verdict "$(run "$(mkcfg odd sentinel odd -)")" floor)"

t_section "floor: pulse and status-gen agree on the same fixture"
t_eq "wired: status-gen guard_hooks = pulse floor" "yes=ok" "$(sg "$WIRED" guard_hooks)=$(verdict "$(run "$WIRED")" floor)"
t_has "wired: status-gen sees the B1 sentinel pulse reads" "$(sg "$WIRED" b1_deny)" "yes"
t_eq "naked: status-gen guard_hooks = pulse floor" "no=crit" "$(sg "$NAKED" guard_hooks)=$(verdict "$(run "$NAKED")" floor)"
t_eq "naked: status-gen sees no B1 sentinel either" no "$(sg "$NAKED" b1_deny)"
# The guard-file half: a five-file predicate would agree with status-gen on a full fixture.
PARTIAL="$(mkcfg partial sentinel full annotate-web.sh)"
t_has "partial: status-gen sees the missing B4 guard" "$(sg "$PARTIAL" guard_hooks)" "MISSING"
t_eq "partial: pulse calls it crit" crit "$(verdict "$(run "$PARTIAL")" floor)"

t_section "floor: a zero-byte settings.json is unknown, never healthy (REVIEW #106)"
EMPTY="$(mkcfg emptycfg sentinel full -)"
: > "$EMPTY/settings.json"
t_eq "zero bytes" unknown "$(verdict "$(run "$EMPTY")" floor)"
printf '   \n\n' > "$EMPTY/settings.json"
t_eq "whitespace only" unknown "$(verdict "$(run "$EMPTY")" floor)"
printf '{' > "$EMPTY/settings.json"
t_eq "malformed (the control that was always caught)" unknown "$(verdict "$(run "$EMPTY")" floor)"

t_section "deps"
mkdir -p "$TMP/minpath"
for _t in sh jq mktemp stat date git sed wc tr cat; do _w="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_w" "$TMP/minpath/$_t"; done
O="$(runv "$WIRED" PATH="$TMP/minpath")"
t_eq "no gitleaks or sink is warn" warn "$(verdict "$O" deps)"
t_has "the detail names gitleaks" "$(detail "$O" deps)" "gitleaks"
t_has "...and the missing desktop notifier" "$(detail "$O" deps)" "desktop-notifier"
printf '#!/bin/sh\nexit 0\n' > "$TMP/minpath/gitleaks"; printf '#!/bin/sh\nexit 0\n' > "$TMP/minpath/notify-send"
chmod +x "$TMP/minpath/gitleaks" "$TMP/minpath/notify-send"
t_eq "Linux: notify-send is a sink, so gitleaks and it present is ok (harbor#618)" ok "$(verdict "$(runv "$WIRED" PATH="$TMP/minpath")" deps)"
rm -f "$TMP/minpath/gitleaks" "$TMP/minpath/notify-send" "$TMP/minpath/git"
t_eq "no git at all is crit" crit "$(verdict "$(runv "$WIRED" PATH="$TMP/minpath")" deps)"

t_section "fleet"
SNAP="$WIRED/cache/fleet-snapshot.json"
t_eq "no snapshot is unknown" unknown "$(verdict "$(run "$WIRED")" fleet)"
jq -n '[{descriptor:{name:"a"},hooks:"ok"},{descriptor:{name:"b"},hooks:"missing"},{descriptor:{name:"c"},hooks:"missing"}]' > "$SNAP"
O="$(run "$WIRED")"
t_eq "hooks:missing is warn" warn "$(verdict "$O" fleet)"
t_has "the count is the count" "$(detail "$O" fleet)" "2 of 3"
jq -n '[{descriptor:{name:"a"},hooks:"ok"},{descriptor:{name:"b"},hooks:"-"}]' > "$SNAP"
t_eq "'-' is not missing (the false positive that shipped first)" ok "$(verdict "$(run "$WIRED")" fleet)"
echo '[]' > "$SNAP"
t_eq "an empty fleet is valid" ok "$(verdict "$(run "$WIRED")" fleet)"
jq -n '[{descriptor:{name:"a"},hooks:"ok"}]' > "$SNAP"; touch -t 202601010000 "$SNAP"
t_eq "a snapshot older than the window is warn" warn "$(verdict "$(run "$WIRED")" fleet)"
touch "$SNAP"
t_eq "the same file inside the window is ok" ok "$(verdict "$(run "$WIRED")" fleet)"
echo '{"repos":[]}' > "$SNAP"
t_eq "a snapshot that is not an array is unknown" unknown "$(verdict "$(run "$WIRED")" fleet)"
jq -n '[{descriptor:{name:"a"},hooks:"ok"}]' > "$SNAP"; touch -t 202601010000 "$SNAP"
t_eq "stale after a sleep (our own last run is as old) is unknown" unknown "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_LAST_RUN=1)" fleet)"
t_eq "stale while the probe kept running is warn" warn "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_LAST_RUN="$(date +%s)")" fleet)"
touch "$SNAP"

t_section "fleet: a GNU-shaped stat that prints and fails is not an age (REVIEW #106)"
mkdir -p "$TMP/statstub"
for _t in sh jq mktemp date git sed wc tr cat; do _w="$(command -v "$_t" 2>/dev/null)" && ln -sf "$_w" "$TMP/statstub/$_t"; done
printf '#!/bin/sh\ncase "$1" in\n  -f) echo "  File: \\"/x\\"  ID: 0 Namelen: 255  Type: apfs"; exit 1 ;;\n  -c) echo 1700000000; exit 0 ;;\nesac\nexit 1\n' > "$TMP/statstub/stat"
chmod +x "$TMP/statstub/stat"
O="$(runv "$WIRED" PATH="$TMP/statstub")"
t_eq "the probe still emits JSON" object "$(printf '%s' "$O" | jq -r type 2>/dev/null)"
# The stub's fallback mtime is 2023, so only a used fallback reads stale; garbage read fresh.
t_eq "the fallback mtime is used" warn "$(verdict "$O" fleet)"

t_section "cudoctor: liveness first, then the receipt's verdict"
cud() { printf '{"ran_at":"%s","status":"%s","gates_failing":%s}\n' "$1" "$2" "${3:-0}" > "$WIRED/cache/cu-doctor-state.json"; }
cudv() { verdict "$(run "$WIRED")" cudoctor; }
NOWZ="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
rm -f "$WIRED/cache/cu-doctor-state.json"
t_eq "an absent receipt is unknown" unknown "$(cudv)"
cud "$NOWZ" green 0
t_eq "a fresh green receipt is ok" ok "$(cudv)"
cud "$NOWZ" failing 2
O="$(run "$WIRED")"
t_eq "a failing receipt is warn" warn "$(verdict "$O" cudoctor)"
t_has "the failing count is carried" "$(detail "$O" cudoctor)" "2 ticket gate"
cud "$NOWZ" error null
t_eq "error (nothing was checked) is crit" crit "$(cudv)"
cud "2020-01-01T00:00:00Z" green 0
O="$(run "$WIRED")"
t_eq "an ancient green receipt is warn: staleness outranks it" warn "$(verdict "$O" cudoctor)"
t_has "the stale detail says the job stopped" "$(detail "$O" cudoctor)" "stopped firing"
cud "$NOWZ" green 0
t_eq "a receipt minutes old is not stale" ok "$(cudv)"
# A 60-second margin, never a sub-second one: age 0 flaked 3 of 5 runs (2026-09-02).
cud "$(date -u -r $(( $(date +%s) - 120 )) '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '120 seconds ago' '+%Y-%m-%dT%H:%M:%SZ')" green 0
t_eq "a two-minute-old receipt under the 3-day default" ok "$(cudv)"
t_eq "HARBOR_ALERT_PROBE_CLICKUP_DOCTOR_MAX_AGE=60 moves the window" warn "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_CLICKUP_DOCTOR_MAX_AGE=60)" cudoctor)"
cud "$NOWZ" someday 0
t_eq "a status the writer does not emit is unknown" unknown "$(cudv)"
printf 'not json at all' > "$WIRED/cache/cu-doctor-state.json"
t_eq "an unparseable receipt is unknown" unknown "$(cudv)"
cud "2020-01-01T00:00:00Z" green 0; touch "$WIRED/cache/cu-doctor-state.json"
t_eq "the age is ran_at, not mtime" warn "$(cudv)"
cud "$NOWZ" green 0

t_section "dispatch: the event dispatcher's receipt (harbor#1044 review r3 #4)"
dsp() { printf '{"status":"%s","at":1,"pid":%s,"reason":"%s"}\n' "$1" "$2" "${3-}" > "$WIRED/cache/event-dispatch-state.json"; }
rm -f "$WIRED/cache/event-dispatch-state.json"
t_eq "no receipt is ok: the dispatcher ships inert" ok "$(verdict "$(run "$WIRED")" dispatch)"
dsp down 1 'jq is not on PATH'
O="$(run "$WIRED")"
t_eq "down is crit" crit "$(verdict "$O" dispatch)"
t_has "...and says why" "$(detail "$O" dispatch)" "NOT FOLLOWING: jq is not on PATH"
dsp following "$$"
t_eq "following, its pid alive, is ok" ok "$(verdict "$(run "$WIRED")" dispatch)"
sleep 30 & _dp=$!; kill "$_dp"; wait "$_dp" 2>/dev/null
dsp following "$_dp"
t_eq "following, its pid gone, is warn" warn "$(verdict "$(run "$WIRED")" dispatch)"
dsp off 1; t_eq "off is ok" ok "$(verdict "$(run "$WIRED")" dispatch)"
printf 'not json' > "$WIRED/cache/event-dispatch-state.json"
t_eq "an unreadable receipt is unknown" unknown "$(verdict "$(run "$WIRED")" dispatch)"
rm -f "$WIRED/cache/event-dispatch-state.json"

t_section "worklog: no store is unknown; unpushed is warn; in sync is ok"
t_eq "an absent work-log is unknown" unknown "$(verdict "$(run "$WIRED")" worklog)"
( set -e
  git init -q --initial-branch=main --bare "$TMP/remote.git" 2>/dev/null || git init -q --bare "$TMP/remote.git"
  git clone -q "$TMP/remote.git" "$WIRED/MEMORY" 2>/dev/null
  cd "$WIRED/MEMORY" || exit 1; git config user.email t@t; git config user.name t
  echo one > a; git add a; git commit -qm one
  git push -q origin HEAD:refs/heads/main 2>/dev/null
  git branch -q --set-upstream-to=origin/main 2>/dev/null || true
) >/dev/null 2>&1
t_exit "the fixture work-log has an upstream" 0 git -C "$WIRED/MEMORY" rev-parse '@{u}'
t_eq "a pushed work-log is ok" ok "$(verdict "$(run "$WIRED")" worklog)"
( cd "$WIRED/MEMORY" && echo two > b && git add b && git commit -qm two ) >/dev/null 2>&1
O="$(run "$WIRED")"
t_eq "an unpushed record is warn" warn "$(verdict "$O" worklog)"
t_has "the unpushed count" "$(detail "$O" worklog)" "1 session record"
t_eq "a work-log that committed nothing inside the window is warn" warn "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_WORKLOG_MAX_AGE=0)" worklog)"

t_section "worklog: an unrelated commit does not refresh its age (REVIEW #106)"
# The dates must differ, or the scoped and unscoped readings agree and nothing discriminates.
( cd "$WIRED/MEMORY" && mkdir -p WORK/sessions/h && echo r > WORK/sessions/h/1.md && git add WORK/sessions \
  && GIT_AUTHOR_DATE='2026-01-01T00:00:00' GIT_COMMITTER_DATE='2026-01-01T00:00:00' git commit -qm 'an old session record' ) >/dev/null 2>&1
( cd "$WIRED/MEMORY" && echo i > IDEAS.md && git add IDEAS.md && git commit -qm 'a fresh idea' ) >/dev/null 2>&1
( cd "$WIRED/MEMORY" && git push -q origin HEAD:refs/heads/main ) >/dev/null 2>&1  # else the ahead-count answers first
t_eq "a fresh IDEAS.md commit leaves the session-record age stale" warn "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_WORKLOG_MAX_AGE=3600)" worklog)"
t_eq "a window covering the old record is ok" ok "$(verdict "$(runv "$WIRED" HARBOR_ALERT_PROBE_WORKLOG_MAX_AGE=99999999)" worklog)"

t_section "the envelope: unknown is not counted as an answer"
O="$(run "$BARE")"
t_eq "an empty config dir answers fewer checks than it runs" yes "$([ "$(printf '%s' "$O" | jq -r '.checks_run')" -gt "$(printf '%s' "$O" | jq -r '.inputs_seen')" ] 2>/dev/null && echo yes || echo no)"
t_hasnt "a run that read nothing is not worst=ok" "$(printf '%s' "$O" | jq -r '.worst')" "ok"
t_eq "the envelope carries ran_at and generated" true "$(printf '%s' "$O" | jq -c '(.ran_at and .generated) // false')"
t_done
