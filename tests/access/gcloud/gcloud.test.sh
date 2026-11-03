#!/usr/bin/env sh
# bin/gcloud (harbor#546): a bare `gcloud auth login` is refused and the way back names the identity dir to use;
# everything else reaches the real gcloud with its argv intact. Hermetic: a stub "real" gcloud that echoes argv first on the
# wrapper cases' own PATH; REAL in the output means the call went through. The gcx half of this suite moved to the
# measurement pack with bin/gcx (harbor#1149); gcx run under this wrapper is that pack's case W15.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset GCX_QUIET GCLOUD_WRAPPER_ROOT STUB_EMAIL
WRAP="$T_ROOT/bin/gcloud"
ex()  { printf 'exit %s' "$STATUS"; }

t_section "W the gcloud wrapper (harbor#546)"
WH="$T_TMP/w"; WROOT="$WH/.config/gcloud/identities"
mkdir -p "$T_TMP/wbin" "$T_TMP/wbin2" "$T_TMP/realbin" "$T_TMP/elsewhere"
ln -s "$WRAP" "$T_TMP/wbin/gcloud"; ln -s "$WRAP" "$T_TMP/wbin2/gcloud"
printf '#!/bin/sh\nprintf REAL; for a in "$@"; do printf " [%%s]" "$a"; done; printf "\\n"\n' > "$T_TMP/realbin/gcloud"
chmod +x "$T_TMP/realbin/gcloud"
mkw() { # <role> <CLI account|''> <pin|''>
  mkdir -p "$WROOT/$1/configurations"; printf 'default\n' > "$WROOT/$1/active_config"
  if [ -n "$2" ]; then printf '[core]\naccount = %s\n' "$2" > "$WROOT/$1/configurations/config_default"
  else printf '[core]\n' > "$WROOT/$1/configurations/config_default"; fi
  if [ -n "$3" ]; then printf '%s\n' "$3" > "$WROOT/$1/expected-account"; fi
}
mkw me owner@example.com ''; mkw tools tools@example.com tools@example.com; mkw drift analytics@example.com tools@example.com
mkw alpha '' analytics@example.com; mkw empty '' ''
WPATH="$T_TMP/wbin:$T_TMP/realbin:/usr/bin:/bin"; WCFG=''
wrun() { # <gcloud args…> -> OUT, STATUS; WCFG, when set, is CLOUDSDK_CONFIG
  OUT="$( ( HOME="$WH"; PATH="$WPATH"; export HOME PATH
            if [ -n "$WCFG" ]; then CLOUDSDK_CONFIG="$WCFG"; export CLOUDSDK_CONFIG; fi
            gcloud "$@" ) 2>&1 )"; STATUS=$?; }
real() { case "$OUT" in *REAL*) echo "REAL ran" ;; *) echo "no REAL" ;; esac; }
refused() { t_eq "$1" "exit 77, no REAL" "exit $STATUS, $(real)"; }       # exit 77 and the real gcloud never ran
passed()  { t_eq "$1" "exit 0: $2" "exit $STATUS: $OUT"; }                # exit 0 and exactly this output
wrun auth login;                          refused 'W1 a bare auth login is refused'
t_has 'W1 names me with its account'      "$OUT" 'gcx me gcloud auth login owner@example.com'
t_has 'W1 names tools with its account'   "$OUT" 'gcx tools gcloud auth login tools@example.com'
t_has 'W1 points at the REST descent'     "$OUT" 'ROUTING.md'
t_hasnt 'W2 an ADC-only dir is not offered a CLI login' "$OUT" 'gcx alpha '
t_hasnt 'W2 an ownerless dir is not offered'            "$OUT" 'gcx empty '
t_has 'W3 a drifted dir is offered its pin'             "$OUT" 'gcx drift gcloud auth login tools@example.com'
wrun auth login tools@example.com;             refused 'W4 a bare login naming an account'
wrun --project p auth login;              refused 'W5 a value flag before the group'
wrun --quiet auth login owner@example.com; refused 'W5 a boolean flag before the group'
wrun --project=p auth login;              refused 'W5 flag=value before the group'
wrun auth login --help;                   passed 'W6 --help is not a login' 'REAL [auth] [login] [--help]'
wrun auth login -h;                       passed 'W6 -h is not a login'     'REAL [auth] [login] [-h]'
wrun version;                             passed 'W7 version'               'REAL [version]'
wrun auth list;                           passed 'W7 auth list'             'REAL [auth] [list]'
wrun config set x 'a b';                  passed 'W7 argv intact'           'REAL [config] [set] [x] [a b]'
wrun auth application-default login;      passed 'W7 ADC login is out of scope' 'REAL [auth] [application-default] [login]'
wrun --project auth login;                passed 'W7 a project named auth is not a login' 'REAL [--project] [auth] [login]'
WCFG="$WROOT/me"
wrun auth login owner@example.com;         passed 'W8 the own account in its dir' 'REAL [auth] [login] [owner@example.com]'
wrun auth login;                          refused 'W9 an unnamed account in a dir'
t_has 'W9 names the account to use' "$OUT" 'gcx me gcloud auth login owner@example.com'
wrun auth login tools@example.com;             refused 'W10 another account in a dir'
t_has 'W10 says whose dir it is' "$OUT" 'belongs to owner@example.com'
WCFG="$WROOT/drift"
wrun auth login analytics@example.com;         refused 'W11 the drifted-in account is refused (pin wins)'
wrun auth login tools@example.com;             passed 'W11 the pinned account passes' 'REAL [auth] [login] [tools@example.com]'
WCFG="$WROOT/empty"
wrun auth login a@b.c;                    refused 'W12 an ownerless dir'
t_has 'W12 says how to pin' "$OUT" 'expected-account'
# The ambient config carries an account, so only the direct-child rule refuses it (mutation, 2026-09-18).
mkdir -p "$WH/.config/gcloud/configurations"; printf 'default\n' > "$WH/.config/gcloud/active_config"
printf '[core]\naccount = owner@example.com\n' > "$WH/.config/gcloud/configurations/config_default"
WCFG="$T_TMP/elsewhere";           wrun auth login a@b.c;            refused 'W13 an unrelated dir'
WCFG="$WH/.config/gcloud";         wrun auth login owner@example.com; refused 'W13 the ambient config dir, with its own account'
WCFG="$WROOT";                     wrun auth login a@b.c;            refused 'W13 the identity root itself'
WCFG="$WROOT/me/configurations";   wrun auth login owner@example.com; refused 'W13 a nested dir'
WCFG="$WROOT/tools/../me";         wrun auth login owner@example.com; passed 'W13 .. collapses to the real dir' 'REAL [auth] [login] [owner@example.com]'
WCFG="$WROOT/nosuch";              wrun auth login a@b.c;            refused 'W13 a nonexistent dir'
WCFG=''
WPATH="$T_TMP/wbin2:$T_TMP/wbin:$T_TMP/realbin:/usr/bin:/bin"
wrun version;                             passed 'W14 the real gcloud is found past two links to the wrapper' 'REAL [version]'
# /usr/bin minus gcloud: a hosted runner installs one there (harbor#865).
. "$T_ROOT/tests/lib/linux-sim.sh"; ( PATH=/usr/bin:/bin; linux_path "$T_TMP/nogcloud" gcloud )
WPATH="$T_TMP/wbin:$T_TMP/nogcloud"
wrun version; t_eq "W14 no real gcloud on PATH fails loudly" "exit 127" "$(ex)"
WPATH="$T_TMP/wbin:$T_TMP/realbin:/usr/bin:/bin"
t_section "W2's control: the dirs it keeps out are offered once they hold a CLI account"
mkw alpha analytics@example.com analytics@example.com; mkw empty x@example.com ''
wrun auth login
t_has 'W2 control: the ADC-only dir, given a CLI account, is offered its pin' "$OUT" 'gcx alpha gcloud auth login analytics@example.com'
t_has 'W2 control: the ownerless dir, given a CLI account, is offered' "$OUT" 'gcx empty gcloud auth login x@example.com'
t_done
