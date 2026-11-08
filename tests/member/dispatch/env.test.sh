#!/usr/bin/env sh
# env.test.sh (harbor#1278, F9, M7) — nothing the environment says changes a verdict on a member box: a settings `env` block reaches every hook, so the dispatcher
# keeps four names and a pinned PATH, and rollout shadow comes from the signed policy, never the launch switch.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
DD="$(m_bash 'dd if=/dev/zero of=/dev/sda')"
m_env() { # <VAR=value>...: m_call under that environment
  printf '%s' "$DD" > "$MIN"
  M_RC=0; (cd "$W" && env "$@" sh "$MB/member-dispatch.sh" < "$MIN" > "$T_TMP/m.out" 2>/dev/null) || M_RC=$?
  M_DEC="$(jq -r '.hookSpecificOutput.permissionDecision // "silent"' "$T_TMP/m.out" 2>/dev/null)"; [ -n "$M_DEC" ] || M_DEC=silent
}

t_section "1 - a switch or override in the environment changes nothing"
awk -F'\t' 'BEGIN { OFS = "\t" } /^#/ { print; next } { $2 = "off"; print }' "$T_ROOT/standards/naming/controls.tsv" > "$T_TMP/all-off.tsv"
printf '#!/bin/sh\nprintf "off\\tadmission.x\\tregister\\t\\n"\n' > "$T_TMP/decide-off.sh"
m_reset; m_enforce
for _e in HARBOR_ADMISSION_DISABLE=1 HARBOR_ADMISSION_SHADOW=1 "FLOOR_DECIDE=$T_TMP/decide-off.sh" "FLOOR_CONTROLS=$T_TMP/all-off.tsv" \
          FLOOR_GREP=/usr/bin/false FLOOR_JQ=/usr/bin/false FLOOR_AWK=/dev/null FLOOR_MAX_NORM=1 CLOUD_POSTURE=ask \
          HARBOR_ADMISSION_MEMBER_RECORDS=/dev/null HARBOR_ADMISSION_SEG_TAB_KEY=x HARBOR_SCOPE_MANAGED_SETTINGS=/nonexistent; do
  m_env "$_e"
  t_eq "$_e" deny "$M_DEC"
done
m_env HARBOR_ADMISSION_DISABLE=1 HARBOR_ADMISSION_SHADOW=1 "FLOOR_DECIDE=$T_TMP/decide-off.sh" "FLOOR_CONTROLS=$T_TMP/all-off.tsv"
t_eq "all at once" deny "$M_DEC"

t_section "2 - a PATH in the environment isn't used"
mkdir -p "$T_TMP/evil"
for _b in jq grep awk sed cat sh; do printf '#!/bin/sh\necho "%s" >> "%s/used"\nexit 0\n' "$_b" "$T_TMP" > "$T_TMP/evil/$_b"; chmod +x "$T_TMP/evil/$_b"; done
m_reset; m_enforce
printf '%s' "$DD" > "$MIN"
_rc=0; (cd "$W" && PATH="$T_TMP/evil:$PATH" /bin/sh "$MB/member-dispatch.sh" < "$MIN" > "$T_TMP/m.out" 2>/dev/null) || _rc=$?
t_eq "still denied" deny "$(jq -r '.hookSpecificOutput.permissionDecision' "$T_TMP/m.out")"
if [ -e "$T_TMP/used" ]; then t_fail "a binary from the planted PATH ran: $(sort -u "$T_TMP/used" | tr '\n' ' ')"; else t_pass; fi

t_section "3 - what a guard actually receives"
printf '#!/bin/sh\nenv > "%s/guard.env"\nexit 0\n' "$T_TMP" > "$MB/env-probe.sh"
printf '.*\tenv-probe.sh\n' >> "$MB/member-guards.tsv"
m_reset; m_enforce
m_env HARBOR_ADMISSION_DISABLE=1 HARBOR_HUB_REPO=fixture-hub/x HARBOR_MEMBER_ROOT=/opt/x HARBOR_ADMISSION_CLASSES=x FLOOR_ANYTHING=1 BASH_ENV=/x
t_eq "only the managed names and the record file" \
  "HARBOR_ADMISSION_MEMBER_RECORDS HARBOR_HUB_REPO HARBOR_MEMBER_LOGIN HARBOR_MEMBER_ROLE HARBOR_MEMBER_ROOT " \
  "$(sed -n -e 's/^\(HARBOR_[A-Z_]*\)=.*/\1/p' -e 's/^\(FLOOR_[A-Z_]*\)=.*/\1/p' "$T_TMP/guard.env" | sort | tr '\n' ' ')"
t_eq "PATH is pinned" "PATH=/usr/bin:/bin:/usr/sbin:/sbin" "$(grep '^PATH=' "$T_TMP/guard.env")"
t_hasnt "no shell start file" "$(cut -d= -f1 "$T_TMP/guard.env" | tr '\n' ' ')" "BASH_ENV"
t_eq "the values kept are the managed ones" "HARBOR_MEMBER_LOGIN=alice" "$(grep '^HARBOR_MEMBER_LOGIN=' "$T_TMP/guard.env")"
t_eq "the file's hub, not the one in env" "HARBOR_HUB_REPO=fixture-org/fixture-hub" "$(grep '^HARBOR_HUB_REPO=' "$T_TMP/guard.env")"
m_env HARBOR_MEMBER_LOGIN=mallory HARBOR_MEMBER_ROLE=standalone HOME=/nonexistent XDG_STATE_HOME=/nonexistent
t_eq "the file's login" "HARBOR_MEMBER_LOGIN=alice" "$(grep '^HARBOR_MEMBER_LOGIN=' "$T_TMP/guard.env")"
t_eq "the file's role" "HARBOR_MEMBER_ROLE=member" "$(grep '^HARBOR_MEMBER_ROLE=' "$T_TMP/guard.env")"
t_eq "the file's home" "HOME=$HOME" "$(grep '^HOME=' "$T_TMP/guard.env")"
t_eq "no state location at all" '' "$(grep '^XDG_STATE_HOME=' "$T_TMP/guard.env")"
t_section "3b - git, curl and TLS steering never reaches a hook; the managed settings' proxy and CA do"
NET='GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.https://elsewhere.test/.insteadOf GIT_CONFIG_VALUE_0=https://github.com/ GIT_SSH_COMMAND=/x GIT_PROXY_COMMAND=/x
  GIT_ASKPASS=/x GIT_SSL_NO_VERIFY=1 GIT_SSL_CAINFO=/x HTTPS_PROXY=http://elsewhere.test:1 https_proxy=http://elsewhere.test:1 HTTP_PROXY=http://elsewhere.test:1
  http_proxy=http://elsewhere.test:1 ALL_PROXY=http://elsewhere.test:1 all_proxy=http://elsewhere.test:1 NO_PROXY=* no_proxy=* CURL_HOME=/x CURL_CA_BUNDLE=/x
  SSL_CERT_FILE=/x SSL_CERT_DIR=/x SSLKEYLOGFILE=/x REQUESTS_CA_BUNDLE=/x NODE_EXTRA_CA_CERTS=/x XDG_CONFIG_HOME=/x XDG_DATA_HOME=/x NETRC=/x'
netnames() { sed -n 's/^\([A-Za-z_]*\)=.*/\1/p' "$T_TMP/guard.env" | grep -E '^(GIT_|CURL_|SSL|REQUESTS_|NODE_EXTRA|XDG_CONFIG|XDG_DATA|NETRC)|_PROXY$|_proxy$' | LC_ALL=C sort | tr '\n' ' '; }
# shellcheck disable=SC2086 # NET is words on purpose
m_env $NET
t_eq "none of them, with no managed settings beside the root" '' "$(netnames)"
MS="${MR%/*}/managed-settings.json"
printf 'ca\n' > "$T_TMP/corp-ca.crt"; chmod 444 "$T_TMP/corp-ca.crt"; printf 'ca\n' > "$T_TMP/open-ca.crt"
jq -n --arg ca "$T_TMP/corp-ca.crt" --arg open "$T_TMP/open-ca.crt" '{env: {HTTPS_PROXY: "http://proxy.corp.test:3128", NO_PROXY: "localhost",
  https_proxy: "http://proxy.corp.test:3128", SSL_CERT_FILE: $ca, CURL_CA_BUNDLE: $open, GIT_SSL_CAINFO: "relative.pem", ALL_PROXY: "http://a\nb",
  GIT_SSH_COMMAND: "/x", HARBOR_MEMBER_ROLE: "member"}}' > "$MS"
# shellcheck disable=SC2086 # as above
m_env $NET
t_eq "the managed proxy and a CA file the member can't write come back, nothing else" "HTTPS_PROXY NO_PROXY SSL_CERT_FILE https_proxy " "$(netnames)"
t_eq "the managed proxy, not the planted one" "HTTPS_PROXY=http://proxy.corp.test:3128" "$(grep '^HTTPS_PROXY=' "$T_TMP/guard.env")"
t_eq "and its CA" "SSL_CERT_FILE=$T_TMP/corp-ca.crt" "$(grep '^SSL_CERT_FILE=' "$T_TMP/guard.env")"
m_env HARBOR_ADMISSION_DISABLE=1
t_eq "with nothing planted, the same" "HTTPS_PROXY NO_PROXY SSL_CERT_FILE https_proxy " "$(netnames)"
rm -f "$MS"
sed -i.bak '$d' "$MB/member-guards.tsv"; rm -f "$MB/member-guards.tsv.bak"

t_section "4 - member mode comes from the file beside the guard, never env"
m_reset; m_enforce
mv "$MB/harbor-member-mode" "$T_TMP/marker"
m_env HARBOR_MEMBER_ROLE=member
t_eq "no marker: refused, role or no role" 2 "$M_RC"
mv "$T_TMP/marker" "$MB/harbor-member-mode"
mv "$MR/member.conf" "$T_TMP/conf"
m_reset; m_enforce
HARBOR_HUB_REPO=fixture-org/fixture-hub m_call "$(m_bash 'ls')"
t_eq "a marker with no member.conf: refused, whatever env offers, on a call nothing else stops" 2 "$M_RC"
mv "$T_TMP/conf" "$MR/member.conf"

t_section "5 - shadow comes from the policy (M7)"
m_reset; m_enforce
m_env HARBOR_ADMISSION_SHADOW=1
t_eq "the launch switch does not make a shadow" deny "$M_DEC"
m_reset; m_policy '.'
m_env HARBOR_ADMISSION_DISABLE=0
t_eq "rollout.mode does" silent "$M_DEC"

t_section "6 - an exported function in the hook's environment changes nothing (N2)"
# The hook command the managed settings carry, run as Claude Code runs it. bash, as macOS /bin/sh is, defines BASH_FUNC_<name>%% before any line of ours.
HARBOR_SCOPE_MANAGED_SETTINGS="${MR%/*}/managed-settings.json" sh "$T_ROOT/bin/member-managed.sh" --hub fixture-org/fixture-hub --login alice --root "$MR" > "$T_TMP/ms.json"
PRE="$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$T_TMP/ms.json")"
PLANT='() { case "$1" in *hub-tier.sh) [ "$2" != mode ] || echo shadow ;; esac; return 0; }'
fn_call() { # <command> <plant 0|1>: M_DEC
  printf '%s' "$DD" > "$MIN"
  M_RC=0
  if [ "$2" = 1 ]; then (cd "$W" && env "BASH_FUNC_sh%%=$PLANT" /bin/sh -c "$1" < "$MIN" > "$T_TMP/m.out" 2>/dev/null) || M_RC=$?
  else (cd "$W" && /bin/sh -c "$1" < "$MIN" > "$T_TMP/m.out" 2>/dev/null) || M_RC=$?; fi
  M_DEC="$(jq -r '.hookSpecificOutput.permissionDecision // "silent"' "$T_TMP/m.out" 2>/dev/null)"; [ -n "$M_DEC" ] || M_DEC=silent
}
m_reset; m_enforce
fn_call "$PRE" 0
t_eq "CONTROL: the managed command denies dd" deny "$M_DEC"
if env "BASH_FUNC_sh%%=() { echo planted; }" /bin/sh -c 'sh' 2>/dev/null | grep -q planted; then
  fn_call "/bin/sh '$MB/member-dispatch.sh'" 1
  t_eq "CONTROL: this /bin/sh imports the plant, and it silences a bare /bin/sh hook" silent "$M_DEC"
else
  printf "  note: this /bin/sh imports no function from env, so the plant's control is moot here\n" >&2
fi
fn_call "$PRE" 1
t_eq "the managed command still denies with the plant in its environment" deny "$M_DEC"
t_eq "every managed hook starts from an empty environment" 0 "$(jq -r '.hooks[][].hooks[].command' "$T_TMP/ms.json" | grep -cv "^/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin ")"

t_section "7 - member.conf decides, however a script beside the marker is started (N9)"
# As member-support.sh opens: its own folder, then hub_env_clean. A person may start it from inside the root, with no slash in \$0.
printf '#!/bin/sh\ncase "$0" in */*) HERE="${0%%/*}" ;; *) HERE=. ;; esac\n. "$HERE/library-hub.sh"\nhub_env_clean || :\nprintf "%%s %%s %%s\\n" "$HARBOR_MEMBER_ROLE" "${HARBOR_MEMBER_LOGIN:-}" "${HARBOR_HUB_REPO:-}"\n' > "$MB/conf-probe.sh"
ENVROLE='HARBOR_MEMBER_ROLE=member HARBOR_MEMBER_LOGIN=mallory HARBOR_HUB_REPO=evil/hub'
# shellcheck disable=SC2086 # ENVROLE is words on purpose
t_eq "by its path" "member alice fixture-org/fixture-hub" "$(cd "$W" && env $ENVROLE sh "$MB/conf-probe.sh")"
# shellcheck disable=SC2086 # as above
t_eq "from inside the root, with no slash in \$0" "member alice fixture-org/fixture-hub" "$(cd "$MB" && env $ENVROLE sh conf-probe.sh)"
cp "$MR/member.conf" "$T_TMP/conf.keep"
printf 'login=mallory\n' >> "$MR/member.conf"
# shellcheck disable=SC2086 # as above
t_eq "a key twice: the file is refused, whichever line a reader takes" "fault  " "$(cd "$W" && env $ENVROLE sh "$MB/conf-probe.sh")"
m_reset; m_enforce
m_call "$(m_bash 'ls')"
t_eq "...and the dispatcher refuses every call" 2 "$M_RC"
cat "$T_TMP/conf.keep" > "$MR/member.conf"
printf 'hub=fixture-org/fixture-hub\n' >> "$MR/member.conf"
# shellcheck disable=SC2086 # as above
t_eq "even a repeat of the same value" "fault  " "$(cd "$W" && env $ENVROLE sh "$MB/conf-probe.sh")"
cat "$T_TMP/conf.keep" > "$MR/member.conf"
rm -f "$MB/conf-probe.sh"
t_done
