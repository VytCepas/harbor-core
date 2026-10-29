#!/usr/bin/env sh
# telemetry-report.sh (harbor#1181 lane 7): approval latency from the bus, tokens per opened PR joined to the session
# rows (and "unknown" where no row exists), and skill and memory-read counts.
. "$(dirname "$0")/../lib/core.sh"; t_init
X="$(cd "$(dirname "$0")/../.." && pwd)/bin/telemetry-report.sh"
B="$T_TMP/bus"; mkdir -p "$B"; U="$T_TMP/sessions.jsonl"
ev() { printf '{"id":"%s","ts":"%s","src":"t","kind":"%s","subject":"%s","repo":"","cause":"","data":%s}\n' "$1" "$2" "$3" "$4" "$5" >> "$B/2026-10-09.jsonl"; }
ev 1 2026-10-09T10:00:00Z approval.open  appr-1 '{}'
ev 2 2026-10-09T10:07:30Z approval.close appr-1 '{}'
ev 3 2026-10-09T11:00:00Z approval.open  appr-2 '{}'
ev 4 2026-10-09T12:00:00Z pr.opened o/r#1 '{"session_id":"s1"}'
ev 5 2026-10-09T12:05:00Z pr.opened o/r#2 '{"session_id":"s1"}'
ev 6 2026-10-09T12:10:00Z pr.opened o/r#3 '{"session_id":"s9"}'
ev 7 2026-10-09T13:00:00Z skill.call artifact-design '{"session_id":"s1"}'
ev 8 2026-10-09T13:01:00Z skill.call artifact-design '{"session_id":"s1"}'
ev 9 2026-10-09T13:02:00Z memory.read MEMORY.md '{"session_id":"s1"}'
printf '{"session":"s1","inp":1000,"out":400,"cc":200,"cr":9000}\n' > "$U"
r() { sh "$X" "$@" --bus "$B" 2>/dev/null; }

t_eq "a closed approval has its latency in seconds" 450 "$(r approvals | awk -F'\t' '$1=="appr-1"{print $4}')"
t_eq "an unclosed one says open, with no latency" "open|" "$(r approvals | awk -F'\t' '$1=="appr-2"{print $3 "|" $4}')"
t_eq "a session's tokens are shared across its PRs" "2 500 200" "$(r pr-tokens --usage "$U" | awk -F'\t' '$1=="o/r#1"{print $3, $4, $5}')"
t_eq "a PR whose session has no usage row says unknown, never zero" unknown "$(r pr-tokens --usage "$U" | awk -F'\t' '$1=="o/r#3"{print $4}')"
t_eq "skill calls are counted by skill" "artifact-design	2" "$(r skills | sed -n 2p)"
t_eq "memory reads are counted by note" "MEMORY.md	1" "$(r memory | sed -n 2p)"
printf '{"cost_usd_by_session":{"s1":1.0}}\n' > "$T_TMP/cc-summary.json"
t_eq "a session's dollars are shared across its PRs" "2 0.5" "$(r pr-cost --summary "$T_TMP/cc-summary.json" | awk -F'\t' '$1=="o/r#1"{print $3, $4}')"
t_eq "a session the receiver never priced says unknown" unknown "$(r pr-cost --summary "$T_TMP/cc-summary.json" | awk -F'\t' '$1=="o/r#3"{print $4}')"
t_eq "no summary file is a clear failure, not an empty report" 1 "$(sh "$X" pr-cost --bus "$B" --summary "$T_TMP/none.json" >/dev/null 2>&1; echo $?)"
t_eq "an empty bus reports a header and nothing else" 1 "$(mkdir -p "$T_TMP/empty"; sh "$X" approvals --bus "$T_TMP/empty" 2>/dev/null | grep -c .)"
t_eq "an unknown report is a usage error" 2 "$(sh "$X" bogus --bus "$B" >/dev/null 2>&1; echo $?)"
t_done
