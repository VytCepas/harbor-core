#!/usr/bin/env sh
# bin/gh-plan.sh against a stubbed gh (harbor#1060): the account plan and main's protection, one checks.log line
# per CHANGE and never per tick, an alarm that holds until a person acknowledges the new state, and an unreadable
# answer that changes nothing. The stub fails on any call it was not told about, so no real API is reached.
. "$(dirname "$0")/../lib/core.sh"; t_init
FX="$T_TMP/fx"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"
mkdir -p "$FX" "$CACHE"
cat > "$GH" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/calls.log"
case "$*" in
  "api user --jq .plan.name")
    [ -f "$FX/plan.fail" ] && { echo "gh: HTTP 502" >&2; exit 1; }
    cat "$FX/plan" ;;
  "api repos/o/r/branches/main/protection")
    case "$(cat "$FX/prot")" in
      github) echo '{"required_status_checks":{"strict":true,"contexts":["Governance gate"]}}' ;;
      weak)   echo '{"required_status_checks":{"strict":false,"contexts":[]}}' ;;
      local)  echo '{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","status":"403"}'
              echo 'gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)' >&2; exit 1 ;;
      absent) echo '{"message":"Branch not protected","status":"404"}'; echo 'gh: Branch not protected (HTTP 404)' >&2; exit 1 ;;
      *)      echo 'error connecting to api.github.com' >&2; exit 1 ;;
    esac ;;
  *) echo "UNEXPECTED gh call: $*" >> "$FX/unexpected.log"; exit 1 ;;
esac
STUB
chmod +x "$GH"
NOW=1790000000
run() { FX="$FX" HARBOR_GH="$GH" HARBOR_PLAN_REPO=o/r HARBOR_CACHE_DIR="$CACHE" HARBOR_NOW="${AT:-$NOW}" sh "$T_ROOT/bin/gh-plan.sh" "$@" 2>&1; }
state() { printf '%s\n' "$1" > "$FX/plan"; printf '%s\n' "$2" > "$FX/prot"; }
reset() { rm -f "$CACHE/gh-plan.json" "$CACHE/checks.log" "$FX/plan.fail" "$FX/calls.log"; state pro github; }
nlog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:gh-plan' "$CACHE/checks.log"; else echo 0; fi; }
last() { tail -n 1 "$CACHE/checks.log"; }
get() { jq -r "$1" "$CACHE/gh-plan.json"; }

t_section "the state Harbor was built on: Pro, protection requiring checks"
reset; run >/dev/null
t_eq "the first reading is one line, so a box that is already degraded says so once" 1 "$(nlog)"
t_has "...stamped with the registry id" "$(last)" "[check:gh-plan]"
t_has "...naming the plan and the gate" "$(last)" "plan pro, gate github"
t_eq "the cache has the plan" pro "$(get .plan)"
t_eq "...and the gate" github "$(get .gate)"
t_eq "Pro with protection is the default acknowledged state: no alarm" false "$(get .alarm)"
run >/dev/null; run >/dev/null
t_eq "control: two more ticks with nothing changed add no line" 1 "$(nlog)"

t_section "the 2026-10-05 lapse: Pro -> Free, protection 403"
state free local; run >/dev/null
t_eq "the change is one line" 2 "$(nlog)"
t_has "...saying the plan moved" "$(last)" "plan pro -> free"
t_has "...and the gate moved to the local fallback" "$(last)" "gate github -> local"
t_has "...and why" "$(last)" "HTTP 403"
t_eq "the alarm is up" true "$(get .alarm)"
run >/dev/null; run >/dev/null
t_eq "a standing state is not a change: no line per tick" 2 "$(nlog)"
t_eq "...but the alarm holds: nobody has acknowledged it" true "$(get .alarm)"

t_section "ack: a person accepts the new state, and the alarm clears until it moves again"
OUT="$(run ack)"
t_eq "ack is one line" 3 "$(nlog)"
t_has "...that says what was accepted" "$(last)" "acknowledged: plan free, gate local"
t_eq "the alarm is down" false "$(get .alarm)"
run >/dev/null
t_eq "control: the next tick keeps it down and adds no line" "false 3" "$(get .alarm) $(nlog)"
state pro github; run >/dev/null
t_has "back to Pro is a change too" "$(last)" "plan free -> pro"
t_eq "...and alarms, because it is not what was acknowledged" true "$(get .alarm)"

t_section "the other gates merge-check tells apart"
reset; state pro weak; run >/dev/null
t_eq "protection that requires no checks is weak" weak "$(get .gate)"
t_eq "...and alarms" true "$(get .alarm)"
reset; state pro absent; run >/dev/null
t_eq "a 404 is absent" absent "$(get .gate)"

t_section "an answer that cannot be read changes nothing"
reset; run >/dev/null; : > "$FX/plan.fail"; OUT="$(run)"
t_has "a failed plan read warns" "$OUT" "WARN"
t_eq "...marks the cache unread" true "$(get .unread)"
t_eq "...keeps the last good plan" pro "$(get .plan)"
t_eq "...and is one line on the way in" 2 "$(nlog)"
run >/dev/null
t_eq "a second failed tick adds no line" 2 "$(nlog)"
rm -f "$FX/plan.fail"; run >/dev/null
t_eq "control: a good read clears the mark" false "$(get .unread)"
t_eq "...and, nothing having changed, adds no line" 2 "$(nlog)"
reset; run >/dev/null; state pro broken; run >/dev/null
t_eq "a protection read that is neither 200, 403 nor 404 is unread, never a gate" "true github" "$(get .unread) $(get .gate)"
reset; printf '\n' > "$FX/plan"; run >/dev/null
t_eq "an empty plan is unread, not a plan" true "$(get .unread)"

t_section "--print reads and writes nothing"
reset; state free local; OUT="$(run --print)"
t_has "it names the plan" "$OUT" "plan free"
t_has "...and says it would alarm" "$OUT" "alarm"
t_eq "...and writes no cache" no "$([ -f "$CACHE/gh-plan.json" ] && echo yes || echo no)"
t_eq "...and no line" 0 "$(nlog)"

t_section "the stub is the only gh"
t_eq "no unexpected gh call across the suite" none "$(cat "$FX/unexpected.log" 2>/dev/null || echo none)"
t_eq "no billing, budget or spending-limit call" 0 "$(cat "$FX"/calls.log 2>/dev/null | grep -c -i -e billing -e budget -e spending || true)"
t_done
