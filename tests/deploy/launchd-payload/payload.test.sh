#!/usr/bin/env sh
# payload.test.sh (harbor#1582) — every launchd template runs a script some installer ships.
# Measured 2026-11-20: com.harbor.status.network was installed by deploy and failed every 60 s with "No such file", because
# bin/status-network.sh was in no installer payload. The payloads are read out of the installers, never restated here.
. "$(dirname "$0")/../../lib/core.sh"; t_init

payload() { # the words of every FILES/GUARDS/RECOVERY/REFRESH_ONLY assignment in the installers
  # Either quote: deploy-runtime-install.sh spells its lists with ", admission-install.sh with '.
  awk -v q="'" '$0 ~ "^(FILES|GUARDS|RECOVERY|REFRESH_ONLY)=[\"" q "]" { f = 1 } f { print } f && $0 ~ "[\"" q "][[:space:]]*$" && $0 !~ "=[\"" q "]$" { f = 0 }' \
    "$T_ROOT/bin/deploy-runtime-install.sh" "$T_ROOT/bin/admission-install.sh" | tr -s " \"'=\\\\" '\n'
}
P="$(payload)"

t_section "the payload is read, not empty"
t_has "the runtime installer's list is found" "$P" "agent-idle-check.sh"
t_has "the floor installer's list is found" "$P" "admission-ask.sh"

t_section "each launchd template's script is shipped"
_n=0
for _pl in "$T_ROOT"/launchd/*.plist; do
  for _s in $(grep -o '@HOME@/\.claude/bin/[A-Za-z0-9._-]*' "$_pl" | sed 's|.*/||' | sort -u); do
    _n=$((_n + 1))
    if printf '%s\n' "$P" | grep -qxF "$_s"; then t_pass
    else t_fail "${_pl##*/} runs ~/.claude/bin/$_s, which no installer payload ships (add it to FILES in bin/deploy-runtime-install.sh)"; fi
  done
done
t_eq "templates name scripts at all (the scan read something)" yes "$([ "$_n" -gt 5 ] && echo yes || echo no)"
t_has "the network guard is among them" "$(grep -l 'status-network.sh' "$T_ROOT"/launchd/*.plist)" "com.harbor.status.network.plist"
t_done
