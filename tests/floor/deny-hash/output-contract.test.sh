#!/usr/bin/env sh
# deny-hash.sh's output follows CONTRACTS/logging.md (harbor#771): stdout carries only data (--propose's candidate
# terms, --scan --json) and the log is on stderr; a FAIL is followed by its fix, the run ends with the summary,
# and the exit codes (0 clean, 1 hit or live gate, 2 refused) are the ones the tool always had.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/deny-hash.sh"; B="$T_TMP"
CFG="$B/dh"; mkdir -p "$CFG"
printf '0123456789abcdef0123456789abcdef\n' > "$CFG/.helm-obs-salt"
T1=acme-corp-internal; T2=vytautas@example-client.lt
printf '%s\n%s\nmulti word term\n' "$T1" "$T2" > "$CFG/.helm-deny-terms"; chmod 600 "$CFG/.helm-deny-terms"
printf 'notes: reach %s for the handover\n' "$T2" > "$B/hit.txt"
printf 'ordinary content, nothing private\n' > "$B/clean.txt"
dh() { sh "$TOOL" "$@" >"$B/out" 2>"$B/err"; echo "exit $?"; }
OUT() { cat "$B/out"; }; ERR() { cat "$B/err"; }
after_fail() { awk '/^  (FAIL|WARN):/ { f = 1; next } f { print; exit }' "$B/err"; }
shaped() { ERR | grep -vcE '^(  (ok|FAIL|WARN|note|skip|fix): |deny-hash: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "--derive: the multi-word term is a WARN with its fix, the summary, exit 0"
t_eq "it exits 0" "exit 0" "$(dh --derive "$CFG")"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the refusal is a WARN" "$(ERR)" "  WARN: refusing multi-word term (scanning is token-wise): multi word term"
t_has "its fix edits the terms file" "$(after_fail)" "  fix: edit $CFG/.helm-deny-terms"
t_has "the write is an ok line" "$(ERR)" "  ok: wrote 2 digest(s) -> $CFG/.helm-deny-hashes"
t_eq "the summary counts the warning" "deny-hash: 1 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "--scan on clean content: ok line and summary on stderr, nothing on stdout"
t_eq "it exits 0" "exit 0" "$(dh --scan "$CFG" "$B/clean.txt")"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the verdict is an ok line" "$(ERR)" "  ok: clean ("
t_eq "the summary ends it" "deny-hash: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--scan on a hit: FAIL by digest, its fix, the summary, exit 1"
t_eq "it exits 1" "exit 1" "$(dh --scan "$CFG" "$B/hit.txt")"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the FAIL names a digest and a length, never the term" 1 "$(ERR | grep -cE '^  FAIL: HIT digest=[0-9a-f]{16} length=[0-9]+$')"
t_hasnt "the term is not in the output" "$(ERR)" "$T2"
t_has "its fix is on the next line" "$(after_fail)" "  fix: none automatic — see CONTRACTS/helm-state.md"
t_eq "the summary counts the failure" "deny-hash: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "--scan --json: stdout is the JSON and only that, the log stays on stderr"
t_eq "it exits 1" "exit 1" "$(dh --scan --json "$CFG" "$B/hit.txt")"
t_eq "stdout parses and counts the hit" 1 "$(OUT | jq -r '.hit_count' 2>/dev/null)"
t_eq "stdout is one line" 1 "$(OUT | wc -l | tr -d ' ')"
t_eq "the summary is on stderr" "deny-hash: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "--propose: stdout is the candidate terms, the log is on stderr"
PROP="$B/prop"; mkdir -p "$PROP/MEMORY"; cp "$CFG/.helm-obs-salt" "$PROP/"
printf 'goal: work with %s and reach %s\n' "$T1" "$T2" > "$PROP/MEMORY/IDENTITY.md"
t_eq "it exits 0" "exit 0" "$(dh --propose "$PROP")"
t_eq "stdout holds only comments and terms" 0 "$(OUT | grep -vcE '^(#|[A-Za-z0-9._@+-]+$)')"
t_has "a term is proposed" "$(OUT)" "$T2"
t_eq "the summary is on stderr" "deny-hash: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "refusals: FAIL, its fix, the summary, and the exit code the tool always had"
t_eq "an unknown option exits 2" "exit 2" "$(dh --nonsuch)"
t_has "the FAIL names it" "$(ERR)" "  FAIL: unknown option --nonsuch"
t_eq "its fix reads the help" "  fix: sh $TOOL --help" "$(after_fail)"
t_eq "the summary ends it" "deny-hash: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no mode exits 2" "exit 2" "$(dh)"
t_has "its FAIL" "$(ERR)" "  FAIL: one of --propose/--derive/--scan is required"
LIVE="$HOME/.claude"; mkdir -p "$LIVE"
t_eq "--derive on the live dir exits 1" "exit 1" "$(dh --derive "$LIVE")"
t_has "its FAIL is the live gate" "$(ERR)" "  FAIL: refusing to write the LIVE filter without an explicit --live"
t_eq "its fix names --live" "  fix: sh $TOOL --derive --live" "$(after_fail)"
NOFILT="$B/nofilter"; mkdir -p "$NOFILT"; cp "$CFG/.helm-obs-salt" "$NOFILT/"
t_eq "a scan with no filter exits 2" "exit 2" "$(dh --scan "$NOFILT" "$B/hit.txt")"
t_has "its FAIL" "$(ERR)" "  FAIL: no filter at $NOFILT/.helm-deny-hashes"
t_eq "its fix derives one" "  fix: sh $TOOL --derive $NOFILT" "$(after_fail)"
t_done
