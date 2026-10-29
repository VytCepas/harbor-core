#!/usr/bin/env sh
# observe-report.sh --fp (harbor#560): harbor's own probe and suite traffic never ranks as an operator
# false-positive candidate. The digests come from failure-capture.sh --exclusion-set, the derivation
# FC-5 uses; the fixture and the independent digest oracle are failure-capture's.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/failure-capture-fixture.sh"
OR="$SRC/observe-report.sh"
fp() { _fd="$1"; shift; CLAUDE_CONFIG_DIR="$_fd" sh "$OR" --fp "$@" 2>&1; }   # <dir> [flag…]

D_OP="$(digest_of 'an operator command that no harbor tool fires')"
F="$(mkfixture fp)"; unseal "$F"; census "$F" 2
# The measured shape (2026-09-20): one probe digest repeated far above the first real candidate.
recn 30 "$F" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$D_PROBE_T"
recn  3 "$F" bash block mutate-onto-surface "2026-08-02T12:00:00Z" "$D_OP"
seal "$F"

t_section "failure-capture --exclusion-set names the probe digest"
t_eq "a probe subject is derived from floor-verify.sh" yes "$([ -n "$PROBE_SUBJ" ] && echo yes || echo no)"
t_has "the probe digest is in the set" "$(sh "$FC" "$F" --exclusion-set 2>/dev/null)" "probe $D_PROBE_T"
t_hasnt "the operator digest is not" "$(sh "$FC" "$F" --exclusion-set 2>/dev/null)" "$D_OP"
t_exit "it refuses --json beside it" 2 sh "$FC" "$F" --exclusion-set --json

t_section "--fp drops the probe rows and keeps the operator's"
OUT="$(fp "$F")"
t_hasnt "the probe digest is not a candidate" "$OUT" "digest $D_PROBE_T"
t_has "the operator's row is the top candidate" "$(printf '%s\n' "$OUT" | grep ' x ' | head -1)" "digest $D_OP"
t_has "what was dropped is counted on screen" "$OUT" "dropped 30 block record(s) under 1 digest(s)"

t_section "--with-probes shows them again, so the exclusion can be audited"
OUTW="$(fp "$F" --with-probes)"
t_has "the probe row is back, on top" "$(printf '%s\n' "$OUTW" | grep ' x ' | head -1)" "30 x  pipe-to-shell"
t_hasnt "and nothing claims a drop" "$OUTW" "dropped"

t_section "an exclusion that cannot be derived is said out loud, never read as clean"
FN="$(mkfixture nosalt)"; unseal "$FN"; census "$FN" 2
recn 30 "$FN" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$D_PROBE_T"; seal "$FN"
rm -f "$FN/.helm-obs-salt"
OUTN="$(fp "$FN")"
t_has "the rows stay" "$OUTN" "digest $D_PROBE_T"
t_has "and the report says it could not separate them" "$OUTN" "WARN: harbor's own probe and suite traffic could NOT be separated"

t_section "--fp counts a deny or an ask as a refusal (harbor#319)"
D_ASK="$(digest_of 'a command the operator keeps approving')"
FA="$(mkfixture fpask)"; unseal "$FA"; census "$FA" 2
recn 3 "$FA" destroy ask git-worktree-remove-force "2026-08-02T12:00:00Z" "$D_ASK"; seal "$FA"
t_has "a recurring ask is a candidate" "$(fp "$FA")" "3 x  git-worktree-remove-force"
FD="$(mkfixture fpdeny)"; unseal "$FD"; census "$FD" 2
recn 3 "$FD" deliverables deny home-loose "2026-08-02T12:00:00Z" "$D_ASK"; seal "$FD"
t_has "a recurring deny is a candidate" "$(fp "$FD")" "3 x  home-loose"

t_section "the report keeps the logging contract's shape"
t_has "a header per section" "$OUT" "── observe-report · false-positive CANDIDATES"
t_has "one summary line" "$(printf '%s\n' "$OUT" | tail -1)" "observe-report: 0 ok, 0 failed"
t_exit "no ledger is a FAIL with exit 1" 1 env CLAUDE_CONFIG_DIR="$TMP/absent" sh "$OR" --fp

t_section "an advise record reaches a report a human runs (harbor#303)"
FV="$(mkfixture adv)"; unseal "$FV"; census "$FV" 2
recn 4 "$FV" integrity advise integrity-advisory "2026-08-02T12:00:00Z" -
recn 1 "$FV" integrity advise integrity-advisory "2026-08-03T09:00:00Z" -; seal "$FV"
OUTV="$(CLAUDE_CONFIG_DIR="$FV" sh "$OR" --advise 2>&1)"
t_has "--advise groups them by what raised them, with the last day" "$OUTV" "5  integrity/integrity-advisory         last 2026-08-03"
t_has "the default report counts them beside the verdicts" "$(CLAUDE_CONFIG_DIR="$FV" sh "$OR" 2>&1)" " · 5 advise · "
t_has "integrity advisories carry the harbor verify hint" "$OUTV" "read it with \`harbor verify\`"
FW="$(mkfixture advweb)"; unseal "$FW"; census "$FW" 2
recn 2 "$FW" web advise web-annotated "2026-08-02T12:00:00Z" -; seal "$FW"
t_hasnt "web advisories alone carry no integrity hint" "$(CLAUDE_CONFIG_DIR="$FW" sh "$OR" --advise 2>&1)" "read it with \`harbor verify\`"
t_has "an empty ledger of advisories says so" "$(fp "$F" >/dev/null; CLAUDE_CONFIG_DIR="$F" sh "$OR" --advise 2>&1)" "(no advisories recorded)"

t_section "--reroute joins a refusal to the same session's next call (harbor#309)"
rr() { # <dir> <ts> <g> <d> <tool> <session key> [rule]
  printf '{"v":1,"ts":"%s","g":"%s","d":"%s","r":"%s","s":"meta","t":"%s","h":"-","sk":"%s"}\n' \
    "$2" "$3" "$4" "${7:-x}" "$5" "$6" >> "$(SINK_OF "$1")"
}
T0=2026-08-02T12:00
SA=aaaaaaaaaaaaaaaa; SB=bbbbbbbbbbbbbbbb; SC=cccccccccccccccc
FR="$(mkfixture reroute)"; unseal "$FR"; census "$FR" 2
# A: refused Bash, then Bash, then Edit. B interleaves a Write between A's first two calls, so a
# join that ignored the key would read A's refusal as followed by a Write.
rr "$FR" "$T0:01Z" bash block Bash "$SA" pipe-to-shell; rr "$FR" "$T0:01Z" egress allow Bash "$SA"
rr "$FR" "$T0:03Z" egress allow Write "$SB"
rr "$FR" "$T0:05Z" egress allow Bash "$SA"
rr "$FR" "$T0:06Z" egress allow Bash "$SB"
rr "$FR" "$T0:08Z" egress allow Edit "$SA"
rr "$FR" "$T0:09Z" egress allow Bash "$SB"
# C: a refused Bash whose egress record lands first, then a Write: a reroute.
rr "$FR" "$T0:20Z" egress allow Bash "$SC"; rr "$FR" "$T0:20Z" prod deny Bash "$SC" prod-delete
rr "$FR" "$T0:25Z" egress allow Write "$SC"
# An ask is neither a refusal nor a control, and a refusal with no call record cannot be joined.
rr "$FR" "$T0:30Z" egress allow Bash "$SC"; rr "$FR" "$T0:30Z" prod ask Bash "$SC"
rr "$FR" "$T0:33Z" egress allow Edit "$SC"
rr "$FR" "$T0:40Z" bash block Bash "$SC"
# Two parallel Bash calls in one second and one block: one refused call, not two.
rr "$FR" "$T0:50Z" egress allow Bash "$SC"; rr "$FR" "$T0:50Z" egress allow Bash "$SC"
rr "$FR" "$T0:50Z" bash block Bash "$SC" pipe-to-shell
rr "$FR" "$T0:55Z" egress allow Bash "$SC"
# D: two parallel Bash calls and two blocks from one guard: each block takes its own call.
SD=dddddddddddddddd
rr "$FR" 2026-08-02T12:01:10Z egress allow Bash "$SD"; rr "$FR" 2026-08-02T12:01:10Z egress allow Bash "$SD"
rr "$FR" 2026-08-02T12:01:10Z bash block Bash "$SD" rm-rf-root; rr "$FR" 2026-08-02T12:01:10Z bash block Bash "$SD" rm-rf-root
rr "$FR" 2026-08-02T12:01:15Z egress allow Write "$SD"
seal "$FR"
OUTR="$(CLAUDE_CONFIG_DIR="$FR" sh "$OR" --reroute 2>&1)"
t_has "the refusals are joined within their own session, one call each" "$OUTR" "refused Bash calls: 5, next call Write/Edit: 2 (40%)"
t_has "the control is the allowed Bash calls, an ask excluded" "$OUTR" "allowed Bash calls (control): 3, next call Write/Edit: 1 (33.3%)"
t_has "a parallel call in the refusal's second is counted as ambiguous" "$OUTR" "3 refusal(s) had parallel calls of the same tool in the same second"
t_has "a refusal with no call record is counted, not dropped silently" "$OUTR" "1 refusal(s) matched no egress record within a second"
t_has "a small sample withholds the ratio" "$OUTR" "(ratio withheld: fewer than 20 calls on a side)"
t_has "the refusals are broken down by rule" "$OUTR" "    pipe-to-shell: 2, 0 (0%)"
t_has "two blocks from one guard in one second go to two calls" "$OUTR" "    rm-rf-root: 2, 1 (50%)"
t_has "what followed a refusal is listed" "$OUTR" "next call after a refused Bash call: Bash 3, Write 2"
t_has "records with no key are counted as sitting out" "$OUTR" "23 of 27 records carry a session key, across 4 session(s)"
t_has "the report says what it cannot see" "$OUTR" "what this cannot see: tools the floor does not hook"
t_has "the default report carries the section" "$(CLAUDE_CONFIG_DIR="$FR" sh "$OR" 2>&1)" "── observe-report · reroute after a refusal (harbor#309)"
# The ratio, once both sides reach the minimum: 20 refusals (10 rerouted), 20 allowed (5 to a Write).
FRB="$(mkfixture reroute-big)"; unseal "$FRB"; census "$FRB" 2
_i=10
while [ "$_i" -lt 50 ]; do
  _m="$(printf %02d $((_i / 2)))"; _s=$((_i % 2 * 30))
  if [ "$_i" -lt 30 ]; then
    rr "$FRB" "2026-08-02T13:$_m:$((_s + 10))Z" bash block Bash "$SA" rm-rf-root
    rr "$FRB" "2026-08-02T13:$_m:$((_s + 10))Z" egress allow Bash "$SA"
    if [ $((_i % 2)) = 0 ]; then _nt=Write; else _nt=WebFetch; fi
  else
    rr "$FRB" "2026-08-02T13:$_m:$((_s + 10))Z" egress allow Bash "$SA"
    if [ $((_i % 4)) = 0 ]; then _nt=Write; else _nt=WebFetch; fi
  fi
  rr "$FRB" "2026-08-02T13:$_m:$((_s + 20))Z" egress allow "$_nt" "$SA"
  _i=$((_i + 1))
done
seal "$FRB"
OUTRB="$(CLAUDE_CONFIG_DIR="$FRB" sh "$OR" --reroute 2>&1)"
t_has "the ratio is printed when both sides reach the minimum" "$OUTRB" "ratio: 2x"
# harbor#976: a refusal whose guard ran 2 s behind egress keeps its call out of the control.
FRL="$(mkfixture reroute-lag)"; unseal "$FRL"; census "$FRL" 2
rr "$FRL" "$T0:01Z" bash block Bash "$SA" pipe-to-shell; rr "$FRL" "$T0:03Z" egress allow Bash "$SA"
rr "$FRL" "$T0:20Z" egress allow Write "$SA"
rr "$FRL" "$T0:40Z" egress allow Bash "$SA"; rr "$FRL" "$T0:45Z" egress allow Bash "$SA"
rr "$FRL" "$T0:50Z" egress allow Edit "$SA"
rr "$FRL" "$T0:52Z" bash shadow Bash "$SB"; rr "$FRL" "$T0:52Z" egress allow Bash "$SB"
rr "$FRL" "$T0:54Z" egress allow Write "$SB"; seal "$FRL"
OUTRL="$(CLAUDE_CONFIG_DIR="$FRL" sh "$OR" --reroute 2>&1)"
t_has "a lagging refusal's call leaves the control, as does a shadow would-block" "$OUTRL" "allowed Bash calls (control): 2, next call Write/Edit: 1 (50%)"
t_has "the call it took is counted as unknown" "$OUTRL" "1 call(s) within 10 s of such a refusal sit out of the control as unknown"
t_has "the refusers the ledger cannot see are named" "$OUTRL" "govern-hook denies"
# Both sides at the minimum and no control call to a Write: the ratio is undefined, not withheld.
FRZ="$(mkfixture reroute-zero)"; unseal "$FRZ"; census "$FRZ" 2
_i=10
while [ "$_i" -lt 50 ]; do
  _m="$(printf %02d $((_i / 2)))"; _s=$((_i % 2 * 30))
  [ "$_i" -lt 30 ] && rr "$FRZ" "2026-08-02T13:$_m:$((_s + 10))Z" bash block Bash "$SA" rm-rf-root
  rr "$FRZ" "2026-08-02T13:$_m:$((_s + 10))Z" egress allow Bash "$SA"
  if [ "$_i" -lt 30 ]; then _nt=Write; else _nt=WebFetch; fi
  rr "$FRZ" "2026-08-02T13:$_m:$((_s + 20))Z" egress allow "$_nt" "$SA"
  _i=$((_i + 1))
done
seal "$FRZ"
OUTRZ="$(CLAUDE_CONFIG_DIR="$FRZ" sh "$OR" --reroute 2>&1)"
t_has "a zero control rate says so" "$OUTRZ" "(ratio undefined: the control rate is 0)"
t_hasnt "and does not claim a small sample" "$OUTRZ" "fewer than 20"
FR0="$(mkfixture reroute-old)"; unseal "$FR0"; census "$FR0" 2
rec "$FR0" bash block pipe-to-shell "2026-08-02T12:00:00Z"; seal "$FR0"
OUTR0="$(CLAUDE_CONFIG_DIR="$FR0" sh "$OR" --reroute 2>&1)"
t_has "a ledger from before the key joins nothing" "$OUTR0" "(no refused Bash call with a key and a next call yet: nothing to join)"
t_has "and compares no rate without a control" "$OUTR0" "no control, so no rate is compared"
t_hasnt "and prints no ratio" "$OUTR0" "ratio"


t_section "--confinement: the escape rate the #555 stop rule reads (harbor#1298)"
crec() { # <dir> <n> <ts> <c> [guard] — guard-bash's one record per Bash call, carrying the confinement field
  _i=0; while [ "$_i" -lt "$2" ]; do
    printf '{"v":1,"ts":"%s","g":"%s","d":"allow","r":"bash-clean","s":"meta","t":"Bash","h":"-","sk":"-","c":"%s"}\n' \
      "$3" "${5:-bash}" "$4" >> "$(SINK_OF "$1")"; _i=$((_i+1)); done
}
FC1="$(mkfixture conf)"; unseal "$FC1"; census "$FC1" 2
crec "$FC1" 98 "2026-10-20T09:00:00Z" confined;   crec "$FC1" 2 "2026-10-20T10:00:00Z" unconfined
crec "$FC1" 9  "2026-10-21T09:00:00Z" confined;   crec "$FC1" 1 "2026-10-21T10:00:00Z" unconfined
crec "$FC1" 4  "2026-10-19T09:00:00Z" off
crec "$FC1" 5  "2026-10-21T11:00:00Z" unconfined egress   # a second guard's record of the same calls
rec "$FC1" bash allow bash-clean "2026-10-18T09:00:00Z"     # written before the field existed
seal "$FC1"
OUTC="$(CLAUDE_CONFIG_DIR="$FC1" sh "$OR" --confinement 2>&1)"
t_has "a day's rate" "$OUTC" "2026-10-20        98           2   2.0%"
t_has "each day on its own row" "$OUTC" "2026-10-21         9           1  10.0%"
t_hasnt "a day with no confinement has no row" "$OUTC" "2026-10-19"
t_has "the total, against the stop line" "$OUTC" "all days: 3 of 110 (2.7%) against the 2% stop line: OVER, so P3 does not ship"
t_has "calls with no confinement sit out, counted" "$OUTC" "4 Bash call(s) ran with no confinement installed"
t_has "the default report carries the section" "$(CLAUDE_CONFIG_DIR="$FC1" sh "$OR" 2>&1)" "confinement escape rate (harbor#555 decision 10a)"
printf '{"v":1,"ts":"2026-10-21T12:00:00Z","g":"bash","d":"covered","r":"redirect-floor-surface","s":"flat","t":"Bash","h":"-","sk":"-","c":"confined"}\n' >> "$(SINK_OF "$FC1")"
OUTCV="$(CLAUDE_CONFIG_DIR="$FC1" sh "$OR" --confinement 2>&1)"
t_has "P3: blocks left to the sandbox are reported" "$OUTCV" "left to the sandbox (P3, covered), by rule:"
t_has "...counted per rule" "$OUTCV" "       1  redirect-floor-surface"
t_hasnt "and none is claimed where there are none" "$(CLAUDE_CONFIG_DIR="$FC2" sh "$OR" --confinement 2>&1)" "left to the sandbox"
FC2="$(mkfixture conf-under)"; unseal "$FC2"; census "$FC2" 2
crec "$FC2" 99 "2026-10-20T09:00:00Z" confined; crec "$FC2" 1 "2026-10-20T10:00:00Z" unconfined; seal "$FC2"
t_has "1 in 100 is under the line" "$(CLAUDE_CONFIG_DIR="$FC2" sh "$OR" --confinement 2>&1)" "all days: 1 of 100 (1.0%) against the 2% stop line: under"
FC3="$(mkfixture conf-off)"; unseal "$FC3"; census "$FC3" 2; crec "$FC3" 3 "2026-10-20T09:00:00Z" off; seal "$FC3"
t_has "a box that never installed it says so, with no rate" "$(CLAUDE_CONFIG_DIR="$FC3" sh "$OR" --confinement 2>&1)" "(3 Bash call(s), none with the confinement installed)"
t_hasnt "and prints no rate" "$(CLAUDE_CONFIG_DIR="$FC3" sh "$OR" --confinement 2>&1)" "stop line"
OUTC0="$(CLAUDE_CONFIG_DIR="$FR0" sh "$OR" --confinement 2>&1)"
t_has "a ledger from before the field reads as no data, never as 0%" "$OUTC0" "(no Bash record carries the confinement field yet"

t_done
