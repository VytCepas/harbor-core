#!/usr/bin/env sh
# audit-triage-run.sh's output follows contracts/logging.md (harbor#771): stdout carries only the cache body, the log is
# on stderr, a FAIL is followed by its fix, the run ends with the summary, and the exit codes (0, 1 judge or
# write failure, 2 refused) are the ones it always had. The judge is a stub: no model is ever called.
. "$(dirname "$0")/../../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/jr"; mkdir -p "$T/bin" "$T/cfg"
cp "$T_ROOT/bin/audit-triage-run.sh" "$T_ROOT/bin/library-log.sh" "$T/bin/"
TOOL="$T/bin/audit-triage-run.sh"
printf '#!/bin/sh\ncat "$(dirname "$0")/fc.json"\n' > "$T/bin/audit-triage.sh"
printf '%s\n' '{"dir":"/x","installed":true,"records":7,"worst":"crit","findings":[{"rule":"FC-2","severity":"crit","subject":"s","breaks":"b","repair":"r"}]}' > "$T/bin/fc.json"
jr() { sh "$TOOL" "$@" >"$T/out" 2>"$T/err"; echo "exit $?"; }
OUT() { cat "$T/out"; }; ERR() { cat "$T/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T/err"; }
shaped() { ERR | grep -vcE '^(  (ok|FAIL|WARN|note|skip|fix): |judge-run: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "--apply: stdout is the cache body, stderr is the log"
t_eq "it exits 0" "exit 0" "$(jr "$T/cfg" --apply)"
t_has "stdout carries the verdict header" "$(OUT | head -1)" "worst=crit crit=1 warn=0 records=7"
t_eq "stdout holds no log line" 0 "$(OUT | grep -cE '^  (ok|FAIL|WARN|note|skip|fix): |^judge-run: ')"
t_has "the write is an ok line" "$(ERR)" "  ok: wrote $T/cfg/.helm-judge"
t_eq "the summary ends stderr" "judge-run: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "a dry run says so as a note"
rm -f "$T/cfg/.helm-judge"
t_eq "it exits 0" "exit 0" "$(jr "$T/cfg")"
t_has "the note" "$(ERR)" "  note: DRY RUN — would write $T/cfg/.helm-judge (pass --apply)"
t_eq "the summary ends it" "judge-run: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "nothing was written" no "$([ -f "$T/cfg/.helm-judge" ] && echo yes || echo no)"

t_section "a garbage verdict: FAIL, its fix, the summary, exit 1, nothing on stdout"
printf 'Traceback: the judge died\n' > "$T/bin/fc.json"
t_eq "it exits 1" "exit 1" "$(jr "$T/cfg" --apply)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL says the cache was not written" "$(ERR)" "  FAIL: the judge produced no parseable JSON — cache NOT written"
t_has "its fix reruns the judge" "$(after_fail)" "  fix: sh $T/bin/audit-triage.sh $T/cfg --json"
t_eq "the summary ends it" "judge-run: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "no judge beside the script: FAIL, its fix, exit 1"
mv "$T/bin/audit-triage.sh" "$T/bin/failure-capture.off"
t_eq "it exits 1" "exit 1" "$(jr "$T/cfg" --apply)"
t_has "the FAIL names the judge" "$(ERR)" "  FAIL: no judge beside this script ($T/bin/audit-triage.sh)"
t_has "its fix installs it" "$(after_fail)" "  fix: sh bin/deploy-runtime-install.sh"
mv "$T/bin/failure-capture.off" "$T/bin/audit-triage.sh"

t_section "refusals exit 2: the live gate, a missing target, an unknown flag"
mkdir -p "$HOME/.claude"
t_eq "--apply on the live dir exits 2" "exit 2" "$(jr "$HOME/.claude" --apply)"
t_has "the FAIL is the live gate" "$(ERR)" "  FAIL: refusing --apply on the live config dir without an explicit --live"
t_eq "its fix names --live" "  fix: sh $TOOL --live --apply" "$(after_fail)"
t_eq "a missing target exits 2" "exit 2" "$(jr "$T/nope" --apply)"
t_has "its FAIL names it" "$(ERR)" "  FAIL: not a directory: $T/nope"
t_eq "an unknown flag exits 2" "exit 2" "$(jr --nonsuch)"
t_has "its FAIL names the flag" "$(ERR)" "  FAIL: unknown flag --nonsuch: nothing was judged"
t_eq "its fix reads the help" "  fix: sh $TOOL --help" "$(after_fail)"
t_eq "the summary ends it" "judge-run: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_done
