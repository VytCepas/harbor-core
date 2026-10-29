#!/usr/bin/env sh
# gcloud-creds's output follows CONTRACTS/logging.md (harbor#771): stdout is `list`'s file names and only that; every
# status line is log-lib's, on stderr; a FAIL is followed by its fix and the run ends with the summary. Hermetic: the
# credential store is a fixture with fake files, `secret` is a stub holding one blob, and gcx is a stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/gcloud-creds"; ST="$T_TMP/gcloud"; V="$T_TMP/vault"; mkdir -p "$V"
printf '#!/bin/sh\ncase "$1" in\n putfile) cp "$3" "$VAULT/blob" ;;\n withfile) shift 3; a=""; for x in "$@"; do [ "$x" = "{}" ] && x="$VAULT/blob"; a="$a $x"; done; [ -f "$VAULT/blob" ] || exit 1; exec $a ;;\nesac\n' > "$T_BIN/secret-stub"
printf '#!/bin/sh\n[ "${GCX_MINT:-1}" = 1 ]\n' > "$T_BIN/gcx"
chmod +x "$T_BIN/secret-stub" "$T_BIN/gcx"
export VAULT="$V"
mkstore() {
  rm -rf "$ST"; mkdir -p "$ST/identities/alpha" "$ST/identities/tools" "$ST/logs"
  printf '{"refresh_token":"FAKE-ALPHA"}\n' > "$ST/identities/alpha/application_default_credentials.json"
  printf '{"refresh_token":"FAKE-TOOLS"}\n' > "$ST/identities/tools/application_default_credentials.json"
}
run() { env GCLOUD_CREDS_ROOT="$ST" GCLOUD_CREDS_SECRET=zz-test GCLOUD_CREDS_SECRET_BIN="$T_BIN/secret-stub" sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "snapshot of a populated store: ok line, notes, summary, stdout empty"
mkstore
t_eq "exit 0" "exit 0" "$(run snapshot)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the ok line" "$(ERR)" "  ok: snapshot stored as secret.zz-test"
t_has "the count is a note" "$(ERR)" "  note: credentials captured: 2 ADC file(s)"
t_eq "the summary ends it" "gcloud-creds: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy REFUSING or bare prefix line" 0 "$(ERR | grep -c '^gcloud-creds: [^0-9]\|REFUSING')"

t_section "list is data on stdout and logs nothing"
t_eq "exit 0" "exit 0" "$(run list)"
t_has "the snapshot's file names" "$(OUT)" "identities/alpha/application_default_credentials.json"
t_eq "nothing is logged" "" "$(ERR)"

t_section "an empty store is refused: FAIL, its fix, the summary, exit 1"
rm -rf "$ST"; mkdir -p "$ST/identities/alpha"
t_eq "exit 1" "exit 1" "$(run snapshot)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL says what it protects" "$(ERR)" "  FAIL: $ST holds no credentials, so a snapshot now would overwrite a good backup with an empty one"
t_eq "the next line is its fix" "  fix: gcloud-creds restore" "$(after_fail)"
t_eq "the summary ends it" "gcloud-creds: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a restore that would clobber is refused; a restore into a wiped store is an ok"
mkstore
t_eq "exit 1" "exit 1" "$(run restore)"
t_has "the FAIL names the count" "$(ERR)" "  FAIL: $ST already holds 2 credential(s), so a restore would overwrite them with the snapshot"
t_eq "its fix is the override" "  fix: gcloud-creds restore --force" "$(after_fail)"
rm -rf "$ST"
t_eq "restore into a wiped store exits 0" "exit 0" "$(run restore)"
t_has "the ok line counts what came back" "$(ERR)" "  ok: restored into $ST (2 ADC file(s) now present)"
t_eq "the summary" "gcloud-creds: 1 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "check: an ok per role; a missing ADC is a FAIL with a fix; --mint tells present from answering"
t_eq "a good store exits 0" "exit 0" "$(run check)"
t_has "a role is an ok line" "$(ERR)" "  ok: alpha: adc present"
t_eq "the summary" "gcloud-creds: 2 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
rm -f "$ST/identities/alpha/application_default_credentials.json"
t_eq "a missing ADC exits 1" "exit 1" "$(run check)"
t_has "the FAIL names the role" "$(ERR)" "  FAIL: alpha: no ADC at "
t_has "and has a fix" "$(after_fail)" "  fix: gcloud-creds restore --force"
t_eq "the summary counts both" "gcloud-creds: 1 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
mkstore
t_eq "--mint with an answering credential exits 0" "exit 0" "$(run check --mint)"
t_has "mints is an ok line" "$(ERR)" "  ok: alpha: mints"
t_eq "--mint with a dead credential exits 1" "exit 1" "$(env GCX_MINT=0 GCLOUD_CREDS_ROOT="$ST" GCLOUD_CREDS_SECRET_BIN="$T_BIN/secret-stub" sh "$TOOL" check --mint >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "the FAIL says it will not mint" "$(ERR)" "  FAIL: alpha: ADC present but will not mint"
t_has "and its fix is the login" "$(after_fail)" "gcx alpha gcloud auth application-default login"

t_section "an unknown verb: FAIL, its fix, the summary, exit 1"
t_eq "exit 1" "exit 1" "$(run frobnicate)"
t_has "the FAIL names it" "$(ERR)" "  FAIL: unknown verb 'frobnicate'"
t_eq "the fix is help" "  fix: gcloud-creds help" "$(after_fail)"
t_done
