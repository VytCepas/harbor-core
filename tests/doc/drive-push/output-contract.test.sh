#!/usr/bin/env sh
# deliver-drive's output follows contracts/logging.md (harbor#1149): the Drive link is the only thing on stdout, so the
# log is on stderr; a refusal is FAIL, its fix, the summary, and the exit code the tool documents (2 usage, 3 no mount,
# 4 no id yet). Hermetic: a fixture mount and a stub xattr.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/doc-drive-push.sh"; export T_TMP
M="$T_TMP/mount"; mkdir -p "$M/My Drive/Artefacts/_shared" "$M/My Drive/Artefacts/_private"
D="$T_TMP/Deliverables/2026-10-11-example-audit"; mkdir -p "$D"; printf 'x\n' > "$D/report.html"
printf '#!/bin/sh\nif [ -n "${STUB_ID:-}" ]; then printf "%%s" "$STUB_ID"; else exit 1; fi\n' > "$T_BIN/xattr"; chmod +x "$T_BIN/xattr"
run() { "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }
dd() { env HARBOR_DOC_DRIVE_MOUNT="$M" HARBOR_DOC_DRIVE_WAIT=1 "$@"; }

t_section "a delivery: the link alone on stdout, the log on stderr"
t_eq "it delivers" "exit 0" "$(run dd STUB_ID=abc123 sh "$TOOL" "$D" --shared)"
t_eq "stdout is the link and nothing else" "https://drive.google.com/drive/folders/abc123" "$(OUT)"
t_has "the copy is an ok line" "$(ERR)" "  ok: copied 2026-10-11-example-audit -> _shared"
t_eq "the summary is the last stderr line" "deliver-drive: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "the folder landed in the shared tier" yes "$([ -f "$M/My Drive/Artefacts/_shared/2026-10-11-example-audit/report.html" ] && echo yes)"
t_eq "--private lands in the other tier" "exit 0" "$(run dd STUB_ID=p1 sh "$TOOL" "$D" --private)"
t_eq "and the file is there" yes "$([ -f "$M/My Drive/Artefacts/_private/2026-10-11-example-audit/report.html" ] && echo yes)"

t_section "Drive has not assigned an id yet: FAIL, the command that reads it later, exit 4"
t_eq "exit 4" "exit 4" "$(run dd sh "$TOOL" "$D" --shared)"
t_eq "nothing on stdout" "" "$(OUT)"
t_has "the FAIL says the copy is made" "$(ERR)" "  FAIL: copied, but Drive has not assigned an id after 1s"
t_has "its fix reads the attribute" "$(after_fail)" "  fix: xattr -p 'com.google.drivefs.item-id#S'"
t_eq "and the summary ends it" "deliver-drive: 1 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "the refusals: FAIL, fix, summary, the documented exit"
t_eq "no destination flag" "exit 2" "$(run dd sh "$TOOL" "$D")"
t_has "its FAIL" "$(ERR)" "  FAIL: say --shared or --private"
t_has "its fix names both" "$(after_fail)" "--shared"
t_eq "a bare file" "exit 2" "$(run dd sh "$TOOL" "$D/report.html" --shared)"
t_has "its FAIL" "$(ERR)" "report.html is not a directory"
mkdir -p "$T_TMP/plain"
t_eq "an undated folder that exists" "exit 2" "$(run dd sh "$TOOL" "$T_TMP/plain" --shared)"
t_has "its FAIL names the shape" "$(ERR)" "  FAIL: plain is not <YYYY-MM-DD>-<slug>"
t_has "its fix renames it" "$(after_fail)" "  fix: mv "
t_eq "no mount" "exit 3" "$(run env HARBOR_DOC_DRIVE_MOUNT="$T_TMP/none" sh "$TOOL" "$D" --shared)"
t_has "its FAIL" "$(ERR)" "  FAIL: no Drive mount at $T_TMP/none/My Drive/Artefacts"
t_eq "every refusal ends with the summary" "deliver-drive: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy deliver-drive: prefix is left" 0 "$(ERR | grep -c '^deliver-drive: [^0-9]')"
t_eq "stdout stays empty on a refusal" "" "$(OUT)"

t_section "--self-test is a run"
t_eq "it passes" "exit 0" "$(run sh "$TOOL" --self-test)"
t_eq "its summary is the library's" 1 "$(ERR | tail -1 | grep -c '^deliver-drive: [0-9][0-9]* ok, 0 failed, 0 warnings$')"
t_eq "and the old PASS shape is gone" 0 "$(ERR | grep -c '^  PASS  ')"
t_done
