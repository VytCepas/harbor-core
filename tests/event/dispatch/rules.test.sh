#!/usr/bin/env sh
# bin/event-dispatch.sh on (harbor#1044): a rule exists only with a docs/reference/checks.md row naming its trigger and its
# disable command; it fires once per event id, debounced per (rule, subject), never on its own output coming
# back round or past the cause chain's depth, at most --rate times an hour, and at least once per --backstop.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
H="$T_TMP/handler.sh"
printf 'printf "%%s %%s\\n" "$HARBOR_EVENT_RULE" "$HARBOR_EVENT_SUBJECT" >> "%s"\n' "$OUT" > "$H"
handler default "$H"   # what the installed stand-in handler (fixture.sh) runs for every rule here
ran() { awk -v r="$1" '$1 == r { print $2 }' "$OUT" 2>/dev/null | tr '\n' ' '; }
dispatch_once   # the first start: offsets at the end of an empty bus

t_section "on: a rule exists only with its docs/reference/checks.md row"
register event.test-a test.a
register event.no-disable test.a; sed -i.bak 's/; off: `harbor event on --off event.no-disable`//' "$CKS"; record docs/reference/checks.md
register event.wrong-kind test.other
t_exit "an id with no register row is refused" 1 sh "$ED" on '"kind":"test\.a"' --id event.unregistered -- sh "$HND"
t_exit "a row that does not name the trigger is refused" 1 sh "$ED" on '"kind":"test\.a"' --id event.wrong-kind -- sh "$HND"
t_exit "a row without the disable command is refused" 1 sh "$ED" on '"kind":"test\.a"' --id event.no-disable -- sh "$HND"
t_exit "a pattern that names no event kind is refused" 1 sh "$ED" on '.' --id event.test-a -- sh "$HND"
t_exit "a registered kind widened by an alternation is refused (review r3 #10)" 1 sh "$ED" on '"kind":"test\.a"|.' --id event.test-a -- sh "$HND"
t_exit "...and by a regex kind" 1 sh "$ED" on '"kind":"(test\.a|.*)"' --id event.test-a -- sh "$HND"
t_exit "an id that is not event.<object> is a usage error" 2 sh "$ED" on '"kind":"test\.a"' --id test-a -- sh "$HND"
t_exit "the dispatcher's own id is not a rule's" 2 sh "$ED" on '"kind":"test\.a"' --id event.dispatch -- sh "$HND"
t_exit "a spawned agent that could write is refused" 2 sh "$ED" on '"kind":"test\.a"' --id event.test-a --spawn hi --tools Read,Bash
t_exit "a rate outside 1-60 an hour is refused" 2 sh "$ED" on '"kind":"test\.a"' --id event.test-a --rate 0 -- sh "$HND"
t_eq "nothing refused left a rule behind" "" "$(ls "$GT/rules" 2>/dev/null)"
sh "$ED" on '"kind":"test\.a"' --id event.test-a --debounce 0 -- sh "$HND" 2>"$T_TMP/on.err"; rc=$?
t_eq "a registered rule is accepted" 0 "$rc"
t_has "...and says how to turn it off" "$(cat "$T_TMP/on.err")" "off: harbor event on --off event.test-a"
t_has "--list shows it" "$(sh "$ED" on --list)" "event.test-a"

t_section "idempotent by event id"
emit test.a one >/dev/null; emit test.a two >/dev/null
dispatch_once; dispatch_once
t_eq "two events, two runs" "one two " "$(ran event.test-a)"
printf 'dispatch %s 0\n' "$D" > "$ST/offsets"; dispatch_once
t_eq "the day read again from byte 0: still two" "one two " "$(ran event.test-a)"

t_section "debounced per (rule, subject)"
register event.test-deb test.deb
sh "$ED" on '"kind":"test\.deb"' --id event.test-deb --debounce 60 -- sh "$HND" 2>/dev/null
emit test.deb x >/dev/null; emit test.deb x >/dev/null; emit test.deb y >/dev/null
dispatch_once
t_eq "x once and y once, inside one window" "x y " "$(ran event.test-deb)"
t_eq "the repeat is recorded as debounced" "done:0=2 skip:debounce=1 " "$(outcomes event.test-deb)"
HARBOR_EVENT_BUS_SKEW=$((NOON + 61)) emit test.deb x >/dev/null; dispatch_once
t_eq "x again once its window has passed" "x y x " "$(ran event.test-deb)"

t_section "the loop guard: a rule never fires on its own output coming back round"
register event.test-loop test.loop
printf 'sh "%s" emit test.loop again >/dev/null 2>&1; printf "%%s\\n" "$HARBOR_EVENT_SUBJECT" >> "%s"\n' "$EB" "$T_TMP/loop.out" > "$T_TMP/loop.sh"
handler event.test-loop "$T_TMP/loop.sh"
sh "$ED" on '"kind":"test\.loop"' --id event.test-loop --debounce 0 --rate 60 -- sh "$HND" 2>/dev/null
seed="$(emit test.loop seed)"
dispatch_once; dispatch_once; dispatch_once
t_eq "the handler ran once, on the seed" "seed" "$(cat "$T_TMP/loop.out")"
t_has "its own emit carried the seed as its cause, with no --cause passed" "$(cat "$BUSDIR/$D.jsonl")" "\"subject\":\"again\",\"repo\":\"\",\"cause\":\"$seed\""
t_eq "the echo is recorded as a loop" "done:0=1 skip:loop=1 " "$(outcomes event.test-loop)"

t_section "the loop guard: depth of the cause chain"
register event.test-depth test.depth
sh "$ED" on '"kind":"test\.depth"' --id event.test-depth --debounce 0 -- sh "$HND" 2>/dev/null
a1="$(emit test.anc a1)"; a2="$(emit test.anc a2 --cause "$a1")"; a3="$(emit test.anc a3 --cause "$a2")"
emit test.depth two-up --cause "$a2" >/dev/null; emit test.depth three-up --cause "$a3" >/dev/null
dispatch_once
t_eq "two ancestors fire, three do not (HARBOR_EVENT_MAX_DEPTH 3)" "two-up " "$(ran event.test-depth)"
t_eq "the deep one is recorded" "done:0=1 skip:depth=1 " "$(outcomes event.test-depth)"

t_section "rate-limited per rule"
register event.test-rate test.rate
sh "$ED" on '"kind":"test\.rate"' --id event.test-rate --debounce 0 --rate 2 -- sh "$HND" 2>/dev/null
for s in r1 r2 r3 r4 r5; do emit test.rate "$s" >/dev/null; done
dispatch_once 2>/dev/null
t_eq "two fire in the hour, three are held" "r1 r2 " "$(ran event.test-rate)"
t_eq "...and recorded" "done:0=2 skip:rate=3 " "$(outcomes event.test-rate)"

t_section "a backstop runs a rule whose trigger never came"
register event.test-back test.never
register event.test-spy rule.backstop
sh "$ED" on '"kind":"test\.never"' --id event.test-back --debounce 0 --backstop 300 -- sh "$HND" 2>/dev/null
sh "$ED" on '"kind":"rule\.backstop"' --id event.test-spy --debounce 0 -- sh "$HND" 2>/dev/null
dispatch_once; dispatch_once
t_eq "not due inside its window" "" "$(ran event.test-back)"
export HARBOR_EVENT_BUS_SKEW=$((NOON + 400))
dispatch_once; dispatch_once; dispatch_once
t_eq "due after it: exactly one run" "event.test-back " "$(ran event.test-back)"
t_has "its event is on the bus" "$(sh "$EB" tail 50)" '"kind":"rule.backstop","subject":"event.test-back"'
t_eq "a rule whose pattern names rule.backstop is never handed another rule's" "" "$(ran event.test-spy)"
emit rule.backstop event.test-spy >/dev/null; dispatch_once
t_eq "...while its own backstop does reach it" "event.test-spy " "$(ran event.test-spy)"


t_section "every load re-checks a rule: a file edited or written by hand after on is refused (review #2)"
: > "$GT/spawn.on"; rm -f "$T_TMP/claude.argv"
register event.test-tools test.tools
sh "$ED" on '"kind":"test\.tools"' --id event.test-tools --debounce 0 --spawn 'Summarise.' 2>/dev/null
sed -i.bak 's/^tools=.*/tools=Bash,Write,WebFetch/' "$GT/rules/event.test-tools.rule"; rm -f "$GT/rules/event.test-tools.rule.bak"
emit test.tools t1 >/dev/null; dispatch_once 2>/dev/null
t_eq "tools edited to Bash,Write,WebFetch: no agent was spawned" no "$([ -e "$T_TMP/claude.argv" ] && echo yes || echo no)"
t_eq "...recorded as refused" "refused=1 " "$(outcomes event.test-tools)"
t_has "...and --list says so" "$(sh "$ED" on --list 2>/dev/null)" "REFUSED: tools Bash is not one of"
printf 'id=event.ghost\npattern="kind":"test\\.ghost"\ndebounce=0\nrate=60\nbackstop=300\ncwd=%s\ncreated=0\nkind=cmd\nargv=sh\nargv=%s\n' "$T_TMP" "$HND" > "$GT/rules/event.ghost.rule"
emit test.ghost g1 >/dev/null; dispatch_once 2>/dev/null
t_eq "a hand-written rule with no docs/reference/checks.md row runs nothing" "" "$(ran event.ghost)"
t_eq "...recorded as refused" "refused=1 " "$(outcomes event.ghost)"
t_has "...with one checks.log line naming it" "$(cat "$CACHE/checks.log")" "rule event.ghost is refused"
emit test.ghost g2 >/dev/null; dispatch_once 2>/dev/null
t_eq "...and only one a day" 1 "$(grep -c 'rule event.ghost is refused' "$CACHE/checks.log")"
t_hasnt "...nor does it get a backstop" "$(sh "$EB" tail 200)" '"subject":"event.ghost"'
register event.wide test.a
printf 'id=event.wide\npattern="kind":"test\\.a"|.\ndebounce=0\nrate=60\nbackstop=0\ncreated=0\nkind=cmd\nargv=sh\nargv=%s\n' "$HND" > "$GT/rules/event.wide.rule"
emit unrelated.kind w1 >/dev/null; dispatch_once 2>/dev/null
t_eq "a rule file widened by hand to \"kind\":\"test\\.a\"|. does not fire on another kind (r3 probe)" "" "$(ran event.wide)"
t_eq "...recorded as refused" "refused=1 " "$(outcomes event.wide)"
rm -f "$GT/rules/event.wide.rule"
register event.test-kind test.kind
sh "$ED" on '"kind":"test\.kind"' --id event.test-kind --debounce 0 -- sh "$HND" 2>/dev/null
sed -i.bak 's/^kind=cmd$/kind=exec/' "$GT/rules/event.test-kind.rule"; rm -f "$GT/rules/event.test-kind.rule.bak"
emit test.kind k1 >/dev/null; dispatch_once 2>/dev/null
t_eq "kind edited to something that is not cmd or spawn: refused" "refused=1 " "$(outcomes event.test-kind)"
printf 'id=event.test-kind\npattern="kind":"test\\.kind"\ndebounce=0\nrate=60\nbackstop=0\ncreated=0\nkind=cmd\nargv=sh\nargv=%s\n' "$H" > "$GT/rules/event.test-kind.rule"
emit test.kind k2 >/dev/null; dispatch_once 2>/dev/null
t_eq "argv edited to a script that is not {cfg}/bin/<allowlisted> (review r2 #1): refused" "refused=2 " "$(outcomes event.test-kind)"
t_hasnt "...and it did not run" "$(cat "$OUT")" "event.test-kind k2"
cp "$HND" "$T_TMP/hnd.keep"; printf 'echo tampered\n' >> "$HND"
emit test.a tampered >/dev/null; dispatch_once 2>/dev/null
t_hasnt "the allowlisted script's bytes changed after on: the load refuses it (the manifest's blob)" "$(cat "$OUT")" "event.test-a tampered"
t_has "...and --list says why" "$(sh "$ED" on --list 2>/dev/null)" "is not the bytes runtime-install recorded"
cp "$T_TMP/hnd.keep" "$HND"
cp "$GT/rules/event.test-a.rule" "$GT/rules/event.alias.rule"
emit test.a four >/dev/null; dispatch_once 2>/dev/null
t_eq "a rule file whose name is not its id runs nothing" "one two four " "$(ran event.test-a)"
t_has "...and is recorded under its file name" "$(cut -f4,5 "$LEDGER")" "invalid:event.alias.rule	refused"
rm -f "$GT/rules/event.alias.rule" "$GT/rules/event.ghost.rule" "$GT/spawn.on"

t_section "on --off removes a rule"
sh "$ED" on --off event.test-a 2>/dev/null; rc=$?
t_eq "exit 0" 0 "$rc"
emit test.a three >/dev/null; dispatch_once
t_eq "it no longer fires" "one two four " "$(ran event.test-a)"
t_exit "removing it twice says so" 1 sh "$ED" on --off event.test-a
t_done
