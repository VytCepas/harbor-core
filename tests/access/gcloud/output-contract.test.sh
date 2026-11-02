#!/usr/bin/env sh
# The gcloud wrapper's output follows contracts/logging.md (harbor#1149): a refusal is a header, a FAIL, its fix lines
# and the summary on stderr, exit 77; every other call is the real gcloud's, byte for byte, and loads no library.
# Hermetic: fixture identity dirs and a stub real gcloud that echoes its argv.
. "$(dirname "$0")/../../lib/core.sh"; t_init
WRAP="$T_ROOT/bin/gcloud"; H="$T_TMP/h"; ROOT="$H/.config/gcloud/identities"
mkdir -p "$T_TMP/wbin" "$T_TMP/realbin" "$ROOT"
ln -s "$WRAP" "$T_TMP/wbin/gcloud"
printf '#!/bin/sh\nprintf "REAL"; for a in "$@"; do printf " [%%s]" "$a"; done; printf "\\n"\n' > "$T_TMP/realbin/gcloud"; chmod +x "$T_TMP/realbin/gcloud"
mkw() { mkdir -p "$ROOT/$1/configurations"; printf 'default\n' > "$ROOT/$1/active_config"
  if [ -n "$2" ]; then printf '[core]\naccount = %s\n' "$2" > "$ROOT/$1/configurations/config_default"; else printf '[core]\n' > "$ROOT/$1/configurations/config_default"; fi; }
mkw me me@example.invalid; mkw tools tools@example.invalid; mkw blank ''
PATHW="$T_TMP/wbin:$T_TMP/realbin:/usr/bin:/bin"
g() { # [CLOUDSDK_CONFIG-dir] is set through GC; the wrapper is run by its link name
  ( HOME="$H"; PATH="$PATHW"; export HOME PATH; if [ -n "${GC:-}" ]; then CLOUDSDK_CONFIG="$GC"; export CLOUDSDK_CONFIG; fi
    gcloud "$@" ) >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }
GC=''

t_section "a bare login: header, FAIL, a fix per CLI identity, the note, the summary, exit 77"
t_eq "refused" "exit 77" "$(g auth login)"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the first line is the header" "── gcloud · auth login" "$(ERR | head -1)"
t_has "the FAIL says what is wrong" "$(ERR)" "  FAIL: refusing \`gcloud auth login\` outside a gcx identity dir"
t_has "the next line is a fix" "$(after_fail)" "  fix: gcx "
t_has "me is offered with its account" "$(ERR)" "  fix: gcx me gcloud auth login me@example.invalid"
t_has "tools is offered with its account" "$(ERR)" "  fix: gcx tools gcloud auth login tools@example.invalid"
t_eq "an ownerless dir is not offered" 0 "$(ERR | grep -c 'gcx blank ')"
t_has "the descent is a note" "$(ERR)" "  note: after 'Reauthentication failed'"
t_eq "the last line is the summary" "gcloud: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no legacy gcloud (harbor#546) prefix is left" 0 "$(ERR | grep -c '^gcloud (harbor')"

t_section "inside a dir: the other refusals carry one fix each"
GC="$ROOT/me"
t_eq "an unnamed account" "exit 77" "$(g auth login)"
t_has "its FAIL" "$(ERR)" "  FAIL: a login must NAME the account, or the browser picks it; role 'me' belongs to me@example.invalid"
t_eq "its fix is the exact command" "  fix: gcx me gcloud auth login me@example.invalid" "$(after_fail)"
t_eq "another account" "exit 77" "$(g auth login tools@example.invalid)"
t_has "its FAIL says whose dir it is" "$(ERR)" "belongs to me@example.invalid, not tools@example.invalid"
t_has "and offers the others" "$(ERR)" "  fix: gcx tools gcloud auth login tools@example.invalid"
GC="$ROOT/blank"
t_eq "a dir with no owner" "exit 77" "$(g auth login a@example.invalid)"
t_has "its FAIL" "$(ERR)" "  FAIL: role 'blank' records no account"
t_has "its fix says how to pin" "$(after_fail)" "expected-account"
t_eq "each refusal ends with the summary" "gcloud: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "every other call is the real gcloud's, and the wrapper says nothing"
GC="$ROOT/me"
t_eq "the owner's login passes" "exit 0" "$(g auth login me@example.invalid)"
t_eq "stdout is the real gcloud's" "REAL [auth] [login] [me@example.invalid]" "$(OUT)"
t_eq "stderr is empty" "" "$(ERR)"
GC=''
t_eq "version passes" "exit 0" "$(g version)"
t_eq "and prints only the real output" "REAL [version]" "$(OUT)"
t_eq "with nothing on stderr" "" "$(ERR)"

t_section "the library is loaded only when there is something to say"
mkdir -p "$T_TMP/lone" "$T_TMP/lonebin"; cp "$WRAP" "$T_TMP/lone/gcloud"; ln -s "$T_TMP/lone/gcloud" "$T_TMP/lonebin/gcloud"
PATHW="$T_TMP/lonebin:$T_TMP/realbin:/usr/bin:/bin"
t_eq "with no library beside it a plain call still reaches the real gcloud" "exit 0" "$(g version)"
t_eq "and prints only the real output" "REAL [version]" "$(OUT)"
t_eq "a refusal cannot be logged, so it exits 77 and says why" "exit 77" "$(g auth login)"
t_has "naming the missing library" "$(ERR)" "gcloud: library-log.sh is missing beside"

t_section "no real gcloud after the wrapper"
PATHW="$T_TMP/wbin:/usr/bin:/bin"
. "$T_ROOT/tests/lib/linux-sim.sh"; ( PATH=/usr/bin:/bin; linux_path "$T_TMP/nogcloud" gcloud )
PATHW="$T_TMP/wbin:$T_TMP/nogcloud"
t_eq "exit 127" "exit 127" "$(g version)"
t_has "the FAIL names the wrapper" "$(ERR)" "  FAIL: no real gcloud on PATH after this wrapper"
if [ "$(uname -s)" = Darwin ]; then _gc_want='brew install --cask google-cloud-sdk'; else _gc_want='see https://cloud.google.com/sdk/docs/install'; fi
t_has "its fix says how to get one on this host" "$(after_fail)" "  fix: $_gc_want"
mkdir -p "$T_TMP/unamelx"; printf '#!/bin/sh\necho Linux\n' > "$T_TMP/unamelx/uname"; chmod +x "$T_TMP/unamelx/uname"
PATHW="$T_TMP/unamelx:$T_TMP/wbin:$T_TMP/nogcloud"; g version >/dev/null
t_has "Linux: its fix is the SDK install page, not a brew cask (harbor#618)" "$(after_fail)" "  fix: see https://cloud.google.com/sdk/docs/install"
t_hasnt "Linux: and never says brew" "$(ERR)" brew
t_eq "and the summary ends it" "gcloud: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_done
