#!/usr/bin/env sh
# ticket-note.sh, the Stop-hook reminder: it speaks on a GitHub ticket and stays silent on
# the measured false positives, dedups per session, never fails the turn, and its
# off switch works both ways (harbor#354, #362). Transcripts are fixtures written here.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/ticket-note.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$T/cfg"
fixture() { printf '%s\n' "$2" > "$T/$1.jsonl"; }
pay() { # <session-id> <fixture> [stop_hook_active] → the payload file
  printf '{"session_id":"%s","transcript_path":"%s/%s.jsonl","stop_hook_active":%s}' \
    "$1" "$T" "$2" "${3:-false}" > "$T/payload.json"
}
# run <sid> <fixture> [active] — the hook the way the harness runs it; stdout in $T/out, rc in $RC.
run() { pay "$@"; CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2> "$T/err" < "$T/payload.json"; RC=$?; }
msg() { cat "$T/out"; }

fixture none      '{"m":"refactor the parser, colour #86ab, index 86"}'
fixture third     '{"m":"read https://github.com/apache/superset/issues/13003"}'
fixture ghview    '{"m":"ran gh issue view 13003 -R apache/superset"}'
fixture ghclose   '{"m":"ran gh issue close 152"}'
fixture mine      '{"m":"see https://github.com/VytCepas/harbor/issues/152"}'
fixture both      '{"m":"ran gh issue close 7 after https://github.com/VytCepas/harbor/issues/152"}'
fixture adjacent  '{"m":"https://github.com/VytCepas/harbor/issues/1, https://github.com/VytCepas/harbor/issues/2 and https://github.com/VytCepas/harbor/pull/3"}'
fixture evil      '{"m":"https://github.com/VytCepas/harbor/issues/152 $(touch TICKET_NOTE_PWNED) and `touch TICKET_NOTE_BQ`"}'

t_section "a ticket id speaks; the measured false positives stay silent"
run t2 none;     t_eq "T-2 a session with no ticket says nothing" "" "$(msg)"
run t5 third;    t_eq "T-5 a third-party issue URL is not the operator's ticket" "" "$(msg)"
run t6 ghview;   t_eq "T-6 gh issue view is research, not ticket work" "" "$(msg)"
run t7 ghclose;  t_has "T-7 gh issue close is ticket work" "$(msg)" 'gh#152'
run t8 mine;     t_has "T-8 an issue URL under a known owner names the repo" "$(msg)" 'VytCepas/harbor#152'

t_section "the note's shape"
run t9a mine
t_has "T-9 the note carries the GitHub block" "$(msg)" 'gh issue close'
run t10b both  # both GitHub forms in one note
t_has "T-10 an attributed URL and a bare gh close both render" "$(msg)" 'VytCepas/harbor#152, gh#7'
_len=$(msg | wc -c | tr -d ' '); _lines=$(msg | wc -l | tr -d ' ')
t_eq "T-10b the note is at most 300 bytes (got ${_len}B)" yes "$([ "$_len" -le 300 ] && echo yes)"
t_eq "T-10b the note is at most 4 lines (got $_lines)" yes "$([ "$_lines" -le 4 ] && echo yes)"

t_section "dedup and the loop guard"
run t11 mine; run t11 mine
t_eq "T-11 a second turn on the same tickets is silent" "" "$(msg)"
run t12 mine; run t12 both
t_has "T-12 a new ticket entering the session re-arms it" "$(msg)" 'gh#7'
run t13 mine true
t_eq "T-13 stop_hook_active stands it down" "" "$(msg)"

t_section "robustness"
# With /usr/bin/grep absent the hook falls back to the grep on PATH (ugrep here) and still matches.
sed 's|^GREP=/usr/bin/grep$|GREP=/nonexistent/grep|' "$TOOL" > "$T/ug.sh"
t_eq "T-14 the fallback copy really pins grep away" 1 "$(grep -c '^GREP=/nonexistent/grep$' "$T/ug.sh")"
pay t14 mine; CLAUDE_CONFIG_DIR="$CFG" sh "$T/ug.sh" > "$T/out" 2>/dev/null < "$T/payload.json"
t_has "T-14 a PATH grep still finds the ticket" "$(msg)" 'VytCepas/harbor#152'
run t15 adjacent
for _id in harbor#1 harbor#2 harbor#3; do t_has "T-15 adjacent ids are all reported: $_id" "$(msg)" "$_id"; done
( cd "$T" && pay t16 evil && CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" >/dev/null 2>&1 < "$T/payload.json" )
t_eq "T-16 transcript \$(…) never executes" no "$([ -e "$T/TICKET_NOTE_PWNED" ] && echo yes || echo no)"
t_eq "T-16 transcript backticks never execute" no "$([ -e "$T/TICKET_NOTE_BQ" ] && echo yes || echo no)"
run t17 mine
t_eq "T-17 output is one systemMessage string" 0 \
  "$(jq -e 'has("systemMessage") and (.systemMessage|type=="string") and (keys|length==1)' "$T/out" >/dev/null 2>&1; echo $?)"
_ro="$T/ro"; mkdir -p "$_ro"; chmod 500 "$_ro"
pay t18b mine; CLAUDE_CONFIG_DIR="$_ro" sh "$TOOL" > "$T/out" 2>/dev/null < "$T/payload.json"; chmod 700 "$_ro"
t_has "T-18 an unwritable state dir degrades loudly" "$(msg)" 'not writable'
pay t19b mine; CLAUDE_CONFIG_DIR="$CFG" TICKET_NOTE_SCAN_MAX=10 sh "$TOOL" > "$T/out" 2>/dev/null < "$T/payload.json"
t_eq "T-19 a 10-byte window cannot reach the id, so it is silent" "" "$(msg)"
printf '%s\n{"m":"see https://github.com/VytCepas/harbor/issues/152"}\n' "$(awk 'BEGIN{while (i++ < 200) printf "x"}')" > "$T/padded.jsonl"
pay t19c padded; CLAUDE_CONFIG_DIR="$CFG" TICKET_NOTE_SCAN_MAX=60 sh "$TOOL" > "$T/out" 2>/dev/null < "$T/payload.json"
t_has "T-19 a truncated window that still finds a ticket declares the truncation" "$(msg)" 'only the last'

t_section "T-20 every path exits 0: a Stop hook must never fail the turn"
run t20a mine;         t_eq "a ticket" 0 "$RC"
run t20b none;         t_eq "no ticket" 0 "$RC"
run t20c mine true;    t_eq "the loop guard" 0 "$RC"
printf '{"session_id":"t20d","transcript_path":"/nope/nope.jsonl","stop_hook_active":false}' > "$T/p20.json"
t_exit "a missing transcript" 0 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" < "$T/p20.json"
printf 'not json at all' > "$T/p20b.json"
t_exit "malformed JSON" 0 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" < "$T/p20b.json"
t_exit "empty stdin" 0 env CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" < /dev/null

t_section "T-21 the off switch, both directions, a fresh session id per arm (harbor#362)"
TICKET_NOTE= run t21-control mine
t_has "control: the gate unset, a note appears" "$(msg)" 'VytCepas/harbor#152'
t_eq "control: exit" 0 "$RC"
for _v in off OFF 0 no false; do
  pay "t21-env-$_v" mine
  TICKET_NOTE="$_v" CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2> "$T/err" < "$T/payload.json"; RC=$?
  t_eq "TICKET_NOTE=$_v silences it" "" "$(msg)"
  t_eq "TICKET_NOTE=$_v still exits 0" 0 "$RC"
  t_eq "TICKET_NOTE=$_v writes nothing to stderr" "" "$(cat "$T/err")"
done
pay t21-typo mine; TICKET_NOTE=offf CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" > "$T/out" 2>/dev/null < "$T/payload.json"
t_has "TICKET_NOTE=offf, a near-miss value, leaves it on" "$(msg)" 'VytCepas/harbor#152'
_scfg="$T/cfg-off"; mkdir -p "$_scfg"; : > "$_scfg/ticket-note.off"
pay t21-sentinel mine; CLAUDE_CONFIG_DIR="$_scfg" sh "$TOOL" > "$T/out" 2> "$T/err" < "$T/payload.json"; RC=$?
t_eq "the sentinel file silences it" "" "$(msg)"
t_eq "the sentinel: exit" 0 "$RC"
rm -f "$_scfg/ticket-note.off"
pay t21-sentinel-gone mine; CLAUDE_CONFIG_DIR="$_scfg" sh "$TOOL" > "$T/out" 2>/dev/null < "$T/payload.json"
t_has "removing the sentinel restores the note" "$(msg)" 'VytCepas/harbor#152'
t_done
