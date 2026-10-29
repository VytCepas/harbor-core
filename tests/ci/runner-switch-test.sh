#!/usr/bin/env sh
# runner-switch.sh against a stubbed gh (harbor#865). The stub serves the billing usage, the private-repo
# list and the HARBOR_RUNNER variable from fixture files, records every write, and fails on any call it was
# not told about, so the real billing API and the real repo variable are never reached. Each verdict has
# a planted case that must flip and a control that must not.
. "$(dirname "$0")/../lib/core.sh"; t_init
FX="$T_TMP/fx"; CACHE="$T_TMP/cache"; GH="$T_TMP/gh"; VAR="$FX/var"; WRITES="$FX/writes.log"; CALLS="$FX/calls.log"
mkdir -p "$FX" "$CACHE"
cat > "$GH" <<'STUB'
#!/bin/sh
echo "$*" >> "$FX/calls.log"
case "$*" in
  "api user --jq .plan.name")
    [ -f "$FX/plan.fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX/plan" ;;
  "api /users/o/settings/billing/usage?year="*|"api /users/someone/settings/billing/usage?year="*)
    [ -f "$FX/billing.fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX/billing.json" ;;
  "api /orgs/SomeOrg/settings/billing/usage?year="*)
    [ -f "$FX/orgbill.fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX/orgbill.json" ;;
  "api /user/repos?visibility=private"*)
    [ -f "$FX/repos.fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX/repos.txt" ;;
  "variable get HARBOR_RUNNER -R o/r")
    [ -f "$FX/var.fail" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    if [ -f "$FX/var" ]; then cat "$FX/var"; else echo "variable HARBOR_RUNNER was not found" >&2; exit 1; fi ;;
  "variable set HARBOR_RUNNER --body "*" -R o/r")
    echo "$5" >> "$FX/writes.log"; printf '%s\n' "$5" > "$FX/var" ;;
  *) echo "UNEXPECTED gh call: $*" >> "$FX/unexpected.log"; exit 1 ;;
esac
STUB
chmod +x "$GH"

NOW=1790000000   # 2026-09-21 UTC
FIRST=1793491200 # 2026-11-01 00:00 UTC
# usage <repo:minutes> ... — a billing answer; Actions Linux minutes per repo, plus rows that must NOT count
usage() {
  _j="[]"
  for _p in "$@"; do
    _j="$(printf '%s' "$_j" | jq -c --arg r "${_p%%:*}" --argjson q "${_p#*:}" \
      '. + [{product:"actions", sku:"Actions Linux", unitType:"Minutes", quantity:$q, repositoryName:$r}]')"
  done
  # rows the filter must drop: storage, a non-Actions product, a public repo, and a Copilot line in the same repo
  _j="$(printf '%s' "$_j" | jq -c '. + [
    {product:"actions", sku:"Actions storage", unitType:"GigabyteHours", quantity:5000, repositoryName:"priv"},
    {product:"copilot", sku:"Copilot Premium Request", unitType:"Requests", quantity:5000, repositoryName:"priv"},
    {product:"actions", sku:"Actions Linux", unitType:"Minutes", quantity:5000, repositoryName:"pub"}]')"
  printf '{"usageItems":%s}\n' "$_j" > "$FX/billing.json"
}
run() { FX="$FX" HARBOR_GH="$GH" HARBOR_SWITCH_REPO="o/r" HARBOR_CACHE_DIR="$CACHE" HARBOR_NOW="${AT:-$NOW}" \
          sh "$T_ROOT/bin/runner-switch.sh" "$@" 2>&1; }
reset() { rm -f "$FX/var" "$WRITES" "$CALLS" "$FX/billing.fail" "$FX/repos.fail" "$FX/var.fail" "$FX/plan.fail" "$FX/unexpected.log" \
            "$CACHE/runner-switch.json" "$CACHE/checks.log" "$CLAUDE_CONFIG_DIR/.harbor-ci-budget"
          AT=$NOW; printf 'priv\n' > "$FX/repos.txt"; printf 'pro\n' > "$FX/plan"; }
nwrites() { if [ -f "$WRITES" ]; then wc -l < "$WRITES" | tr -d ' '; else echo 0; fi; }
varnow() { cat "$FX/var" 2>/dev/null || echo unset; }
get() { jq -r "$1" "$CACHE/runner-switch.json"; }
nlog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:runner-switch' "$CACHE/checks.log"; else echo 0; fi; }

t_section "below the threshold: no write"
reset; usage priv:2699; echo github-hosted > "$FX/var"
run >/dev/null
t_eq "2699 of 3000 is under 90 percent, so the variable is left alone" 0 "$(nwrites)"
t_eq "...and it still says github-hosted" github-hosted "$(varnow)"
t_eq "the cache records the usage the sum came to" 2699 "$(get .used)"
t_eq "the cache records the allowance" 3000 "$(get .allowance)"
t_eq "no switch, so no checks.log line" 0 "$(nlog)"
t_eq "only private-repo Actions minutes were summed: storage, Copilot and the public repo are not" 2699 "$(get .used)"

t_section "at the threshold: a flip to self-hosted"
reset; usage priv:2700; echo github-hosted > "$FX/var"
OUT="$(run)"
t_eq "2700 of 3000 is 90 percent, so it writes" 1 "$(nwrites)"
t_eq "...self-hosted" self-hosted "$(varnow)"
t_eq "the switch is one line in checks.log" 1 "$(nlog)"
t_has "...that says which way and why" "$(cat "$CACHE/checks.log")" "github-hosted -> self-hosted"
t_has "...and quotes the registry id" "$(cat "$CACHE/checks.log")" "[check:runner-switch]"
t_has "...and the usage" "$(cat "$CACHE/checks.log")" "2700/3000"
t_eq "the cache says the runner is self-hosted" self-hosted "$(get .runner)"
t_eq "the cache says it is a fallback, for the statusline" true "$(get .fallback)"
run >/dev/null; run >/dev/null
t_eq "control: two more ticks at the same usage write nothing" 1 "$(nwrites)"
t_eq "control: ...and add no checks.log line" 1 "$(nlog)"

t_section "an unset variable already means self-hosted: no write to say so"
reset; usage priv:2800
run >/dev/null
t_eq "the workflow defaults to self-hosted, so setting it again changes nothing" 0 "$(nwrites)"
t_eq "...and the cache still says self-hosted" self-hosted "$(get .runner)"

t_section "the budget moves the threshold"
reset; usage priv:2846; echo github-hosted > "$FX/var"; printf 'minutes 500\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-budget"
run >/dev/null
t_eq "2846 of 3500 (3000 plus a 500-minute budget) is under 90 percent" 0 "$(nwrites)"
t_eq "...the allowance says so" 3500 "$(get .allowance)"
reset; usage priv:2846; echo github-hosted > "$FX/var"; printf 'usd 4\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-budget"
run >/dev/null
t_eq "a 4 dollar budget at 0.008 a minute is 500 minutes" 3500 "$(get .allowance)"
reset; usage priv:2846; echo github-hosted > "$FX/var"
run >/dev/null
t_eq "control: the same usage with no budget (default 0) flips" self-hosted "$(varnow)"

t_section "the allowance follows the plan (harbor#1060): Free 2,000, Pro 3,000"
reset; usage priv:1800; echo github-hosted > "$FX/var"; printf 'free\n' > "$FX/plan"
run >/dev/null
t_eq "on Free the allowance is 2000" 2000 "$(get .allowance)"
t_eq "...so 1800 minutes is 90 percent and flips" self-hosted "$(varnow)"
t_has "...logged against the Free allowance" "$(cat "$CACHE/checks.log")" "1800/2000"
t_eq "the cache records the plan" free "$(get .plan)"
reset; usage priv:1800; echo github-hosted > "$FX/var"
run >/dev/null
t_eq "control: the same 1800 minutes on Pro (3000) flips nothing" github-hosted "$(varnow)"
reset; usage priv:1800; echo github-hosted > "$FX/var"; printf 'Free\n' > "$FX/plan"
run >/dev/null
t_eq "the plan name is read case-blind" 2000 "$(get .allowance)"
reset; usage priv:2900; echo github-hosted > "$FX/var"; printf 'enterprise-ish\n' > "$FX/plan"
OUT="$(run)"
t_eq "a plan it does not know flips nothing" 0 "$(nwrites)"
t_has "...and says which plan" "$OUT" "enterprise-ish"
t_eq "...and marks the cache unread" true "$(get .unread)"
reset; usage priv:2900; echo github-hosted > "$FX/var"; : > "$FX/plan.fail"
run >/dev/null
t_eq "a plan read that fails flips nothing" 0 "$(nwrites)"
t_eq "...and marks the cache unread" true "$(get .unread)"
reset; usage priv:2900; echo self-hosted > "$FX/var"; AT=$FIRST; : > "$FX/plan.fail"
run >/dev/null
t_eq "control: on the 1st an unreadable plan still lets CI go back to hosted" github-hosted "$(varnow)"

t_section "usage drops below the threshold: back to github-hosted"
reset; usage priv:100; echo self-hosted > "$FX/var"
run >/dev/null
t_eq "100 minutes on a self-hosted variable flips it back" github-hosted "$(varnow)"
t_eq "...as one write" 1 "$(nwrites)"
t_has "...and one line" "$(cat "$CACHE/checks.log")" "self-hosted -> github-hosted"
t_eq "the cache is no fallback now" false "$(get .fallback)"

t_section "the 1st of the month: a flip back, whatever the billing API says"
reset; usage priv:2900; echo self-hosted > "$FX/var"; AT=$FIRST
run >/dev/null
t_eq "on the 1st the variable goes back to github-hosted" github-hosted "$(varnow)"
t_has "...logged as a month reset" "$(cat "$CACHE/checks.log")" "new month"
reset; usage priv:2900; echo self-hosted > "$FX/var"; AT=$FIRST; : > "$FX/billing.fail"
run >/dev/null
t_eq "even with the billing API down, because the month's usage is a day old at most" github-hosted "$(varnow)"
reset; usage priv:2900; echo self-hosted > "$FX/var"; AT=$((FIRST + 86400)); : > "$FX/billing.fail"
run >/dev/null
t_eq "control: the 2nd with the billing API down flips nothing" self-hosted "$(varnow)"

t_section "a billing API error: no flip, a warning"
reset; echo github-hosted > "$FX/var"; : > "$FX/billing.fail"
OUT="$(run)"; RC=$?
t_eq "an unreadable bill writes nothing" 0 "$(nwrites)"
t_has "...and says so" "$OUT" "WARN"
t_has "...naming the billing read" "$OUT" "billing"
t_eq "...and the variable is untouched" github-hosted "$(varnow)"
t_eq "the cache is marked unread" true "$(get .unread)"
t_eq "the first failure is one checks.log line" 1 "$(nlog)"
run >/dev/null
t_eq "a second failed tick adds no line: a standing state is not a change" 1 "$(nlog)"
rm -f "$FX/billing.fail"; run >/dev/null
t_eq "the first good read after says so once, so the log does not end on the failure" 1 "$(grep -c 'read answers again' "$CACHE/checks.log")"
_n="$(nlog)"; run >/dev/null
t_eq "...and a second good read adds nothing" "$_n" "$(nlog)"
reset; usage priv:2900; echo github-hosted > "$FX/var"; : > "$FX/billing.fail"
run >/dev/null
t_eq "control: high usage in the file does not matter when the API errored" 0 "$(nwrites)"
reset; echo github-hosted > "$FX/var"; : > "$FX/repos.fail"; usage priv:2900
run >/dev/null
t_eq "a failed private-repo list is the same: no flip" 0 "$(nwrites)"
reset; usage priv:2900; : > "$FX/var.fail"
run >/dev/null
t_eq "a failed variable read is the same: no write" 0 "$(nwrites)"
printf '{"usageItems":"oops"}\n' > "$FX/billing.json"; reset; printf '{"usageItems":"oops"}\n' > "$FX/billing.json"; echo github-hosted > "$FX/var"
run >/dev/null
t_eq "an answer that is not the bill's shape is an error, not zero" 0 "$(nwrites)"
t_eq "...and is marked unread" true "$(get .unread)"
reset; usage priv:100; echo github-hosted > "$FX/var"
run >/dev/null
t_eq "control: a good read after the errors clears the mark" false "$(get .unread)"

t_section "--org: an organisation's own verdict against its cap (harbor#1060)"
# orgusage <repo:minutes> ... — the org's bill: Linux minutes per repo, plus storage and Copilot rows that must not count
orgusage() {
  _j="[]"
  for _p in "$@"; do
    _j="$(printf '%s' "$_j" | jq -c --arg r "${_p%%:*}" --argjson q "${_p#*:}" \
      '. + [{product:"actions", sku:"Actions Linux", unitType:"Minutes", quantity:$q, repositoryName:$r, organizationName:"SomeOrg"}]')"
  done
  _j="$(printf '%s' "$_j" | jq -c '. + [
    {product:"actions", sku:"Actions storage", unitType:"GigabyteHours", quantity:5000, repositoryName:"a"},
    {product:"copilot", sku:"Copilot Premium Request", unitType:"Requests", quantity:5000, repositoryName:"a"}]')"
  printf '{"usageItems":%s}\n' "$_j" > "$FX/orgbill.json"
}
orun() { run --org SomeOrg "$@"; }
oget() { jq -r "$1" "$CACHE/runner-switch.SomeOrg.json"; }
olog() { if [ -f "$CACHE/checks.log" ]; then grep -c 'check:runner-switch-org' "$CACHE/checks.log"; else echo 0; fi; }
oreset() { reset; rm -f "$CACHE/runner-switch.SomeOrg.json" "$FX/orgbill.fail" "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; }
oreset; orgusage a:1000 gone:999; orun >/dev/null
t_eq "1999 of a 2000-minute cap is under it: hosted" github-hosted "$(oget .runner)"
t_eq "...summing every repo's minutes, a deleted repo's too, and no storage or Copilot" 1999 "$(oget .used)"
t_eq "...against the default cap" 2000 "$(oget .allowance)"
t_eq "the org verdict sets no variable" 0 "$(grep -c variable "$CALLS" || true)"
t_eq "...and writes no personal verdict" no "$([ -f "$CACHE/runner-switch.json" ] && echo yes || echo no)"
oreset; orgusage a:1000 b:1000; orun >/dev/null
t_eq "2000 of 2000 is at the cap: self-hosted" self-hosted "$(oget .runner)"
t_eq "...one checks.log line under its own id" 1 "$(olog)"
t_has "...saying which way and why" "$(cat "$CACHE/checks.log")" "SomeOrg none -> self-hosted (2000/2000 minutes, at or over the cap)"
orun >/dev/null; orun >/dev/null
t_eq "control: two more runs at the same usage add no line" 1 "$(olog)"
orgusage a:100; orun >/dev/null
t_eq "usage back under the cap: hosted again" github-hosted "$(oget .runner)"
t_has "...one more line" "$(cat "$CACHE/checks.log")" "SomeOrg self-hosted -> github-hosted"
oreset; orgusage a:2400; printf 'org SomeOrg 2500\n' > "$CLAUDE_CONFIG_DIR/.harbor-ci-runners"; orun >/dev/null
t_eq "the cap is the org line's number: 2400 of 2500 is under it" "github-hosted 2500" "$(oget '"\(.runner) \(.allowance)"')"
oreset; orgusage a:2400; orun >/dev/null
t_eq "control: the same usage against the default cap is over it" self-hosted "$(oget .runner)"
oreset; orgusage a:2400; AT=$FIRST; : > "$FX/orgbill.fail"; orun >/dev/null
t_eq "the 1st: hosted without reading the bill" "github-hosted true" "$(oget '"\(.runner) \(.new_month)"')"
oreset; orgusage a:2400; orun >/dev/null; : > "$FX/orgbill.fail"; orun >/dev/null
t_eq "a failed read keeps the last verdict" self-hosted "$(oget .runner)"
t_eq "...marked unread, which ci-runners.sh does not trust" true "$(oget .unread)"
t_eq "...one line on the way in" 2 "$(olog)"
orun >/dev/null
t_eq "...and none for a standing failure" 2 "$(olog)"
oreset; printf '{"usageItems":"oops"}\n' > "$FX/orgbill.json"; orun >/dev/null
t_eq "an answer that is not the bill's shape is unread, not zero" true "$(oget .unread)"
oreset; orgusage a:2400; OUT="$(orun --print)"
t_has "--print says the usage and the verdict" "$OUT" "SomeOrg used 2400 of its 2000-minute cap"
t_eq "...and writes no cache" no "$([ -f "$CACHE/runner-switch.SomeOrg.json" ] && echo yes || echo no)"
t_exit "an --org with no name is refused" 2 env FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/runner-switch.sh" --org
t_exit "an --org that is not a name is refused" 2 env FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" sh "$T_ROOT/bin/runner-switch.sh" --org 'a;b'

t_section "harbor's own repository is derived, never spelled (harbor#1149)"
# a copy beside no checkout and no pin names no repository: an unread, nothing written
reset; usage priv:2700; echo github-hosted > "$FX/var"
mkdir -p "$FX/inst/bin"; cp "$T_ROOT/bin/runner-switch.sh" "$T_ROOT/bin/log-lib.sh" "$FX/inst/bin/"
OUT="$(FX="$FX" HARBOR_GH="$GH" HARBOR_CACHE_DIR="$CACHE" HARBOR_NOW="$NOW" sh "$FX/inst/bin/runner-switch.sh" 2>&1)"
t_eq "with no name for the repository nothing is written" 0 "$(nwrites)"
t_has "...and the note says it could not be derived" "$OUT" "repository name"
# HARBOR_BILLING_USER names the billed account; without it the billed account is the repo's owner
reset; usage priv:100; echo github-hosted > "$FX/var"; run >/dev/null
t_has "the billing read goes to the repository's owner" "$(cat "$CALLS")" "/users/o/settings/billing"
reset; usage priv:100; echo github-hosted > "$FX/var"
FX="$FX" HARBOR_GH="$GH" HARBOR_SWITCH_REPO="o/r" HARBOR_BILLING_USER=someone HARBOR_CACHE_DIR="$CACHE" HARBOR_NOW="$NOW" sh "$T_ROOT/bin/runner-switch.sh" >/dev/null 2>&1
t_has "HARBOR_BILLING_USER still names the billed account" "$(cat "$CALLS")" "/users/someone/settings/billing"

t_section "the stub is the only gh, and it was told every call"
t_eq "no unexpected gh call across the whole suite" "none" "$(cat "$FX/unexpected.log" 2>/dev/null || echo none)"
reset; usage priv:100; echo github-hosted > "$FX/var"; run >/dev/null
t_has "control: the stub records the billing read it served" "$(cat "$CALLS")" "billing/usage?year=2026&month=9"
t_hasnt "control: ...and nothing wrote" "$(cat "$CALLS")" "variable set"
t_done
