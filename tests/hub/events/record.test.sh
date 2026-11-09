#!/usr/bin/env sh
# record.test.sh (harbor#1278) — hub-events.sh record: only closed values reach the outbox, ts is the hour, a bad record is counted.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
be_up
E="$BE_BIN/hub-events.sh"; O="$BE_HS/outbox.jsonl"
lines() { if [ -f "$O" ]; then wc -l < "$O" | tr -d ' '; else echo 0; fi; }
drops() { if [ -f "$BE_HS/dropped" ]; then wc -c < "$BE_HS/dropped" | tr -d ' '; else echo 0; fi; }

t_section "1 - every kind records"
be_reset
sh "$E" record refusal rule=admission.rm-root tier=very-high target=command count=1
sh "$E" record ask rule=prod-bucket tier=high target=cloud outcome=not-run count=2
sh "$E" record request id=r-0123456789abcdef rule=prod-bucket tier=very-high target=cloud outcome=opened
sh "$E" record check check=floor-integrity outcome=failed
sh "$E" record token days_left=6 outcome=expiring
sh "$E" record heartbeat core=0123456789ab contract=1 floor=0123456789abcdef serial=1 mode=shadow refusals=2 asks=1 requests=0 packs=fixture-pack,other-pack
t_eq "six kinds, six lines" 6 "$(lines)"
t_eq "no drops" 0 "$(drops)"
t_eq "numbers stay numbers" number "$(jq -rs '.[1].count | type' "$O")"
t_eq "packs are a list" 2 "$(jq -s '.[5].packs | length' "$O")"
t_eq "the member is the managed login" alice "$(jq -rs '.[0].member' "$O")"
if sh "$BE_BIN/hub-format.sh" event "$O" >/dev/null 2>&1 || jq -s . "$O" > "$T_TMP/all.json" && sh "$BE_BIN/hub-format.sh" event "$T_TMP/all.json"; then t_pass; else t_fail "the outbox doesn't pass the format"; fi

t_section "2 - ts is the hour"
# A mid-hour clock on its own PATH entry: the suite watchdog reads `date` too.
mkdir -p "$T_TMP/clock"
printf '#!/bin/sh\ncase "$*" in *%%H:00:00Z*) printf "2026-11-07T10:00:00Z\\n" ;; *) printf "2026-11-07T10:13:22Z\\n" ;; esac\n' > "$T_TMP/clock/date"; chmod +x "$T_TMP/clock/date"
be_reset
PATH="$T_TMP/clock:$PATH" sh "$E" record check check=floor-integrity outcome=passed
t_eq "no minutes or seconds" 2026-11-07T10:00:00Z "$(jq -r .ts "$O")"

t_section "3 - a payload with content is dropped and counted, never kept"
content() { # <label> <args...>
  _l="$1"; shift
  be_reset
  sh "$E" record "$@"
  t_eq "$_l: exit 0" 0 "$?"
  t_eq "$_l: not kept" 0 "$(lines)"
  t_eq "$_l: counted" 1 "$(drops)"
}
content "a command in a rule" refusal 'rule=rm -rf gs://prod-acme/client-list' tier=very-high target=command count=1
content "a free-text key" refusal rule=admission.rm-root tier=very-high target=command count=1 'note=the client said'
content "a target off the list" refusal rule=admission.rm-root tier=very-high target=client-list count=1
content "a file path as a check" check 'check=/Users/alice''/clients/acme.xlsx' outcome=failed
content "prose as a count" refusal rule=admission.rm-root tier=very-high target=command count=many
content "a member-chosen pack name" heartbeat core=0123456789ab contract=1 floor=0123456789abcdef serial=1 mode=shadow refusals=0 asks=0 requests=0 'packs=Acme Client Stuff'
content "a kind that isn't one" transcript text=hello
content "a missing key" refusal rule=admission.rm-root
content "an argument with no value" refusal rule=admission.rm-root tier=very-high target=command count=1 loose
content "a caller's exact time" check check=floor-integrity outcome=failed ts=2026-11-07T10:13:22Z
content "a caller's member" check check=floor-integrity outcome=failed member=bob

t_section "4 - a flood stops at the cap, counted"
be_reset
mkdir -p "$BE_HS"
awk 'BEGIN { for (i = 0; i < 11000; i++) print "{\"v\":1,\"kind\":\"refusal\",\"ts\":\"2026-11-07T10:00:00Z\",\"member\":\"alice\",\"rule\":\"admission.rm-root\",\"tier\":\"very-high\",\"target\":\"command\",\"count\":1}" }' > "$O"
n0="$(lines)"
sh "$E" record check check=floor-integrity outcome=passed
t_eq "past the cap a record isn't kept" "$n0" "$(lines)"
t_eq "and is counted" 1 "$(drops)"

t_section "5 - standalone does nothing"
be_reset
HARBOR_MEMBER_ROLE='' sh "$E" record check check=floor-integrity outcome=passed
t_eq "no outbox" 0 "$(lines)"
t_eq "no state" no "$([ -e "$BE_HS" ] && echo yes || echo no)"
t_eq "send is a no-op too" 0 "$(HARBOR_MEMBER_ROLE='' be_rc sh "$E" send)"

be_down
t_done
