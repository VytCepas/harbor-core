#!/usr/bin/env sh
# payload.test.sh (harbor#1582) — every launchd template runs a script its installer ships.
# Measured 2026-11-20: com.harbor.status.network was installed by deploy and failed every 60 s with "No such file", because
# bin/status-network.sh was in no installer payload. The payloads are read out of the installers, never restated here.
. "$(dirname "$0")/../../lib/core.sh"; t_init

payload() { # the words of every FILES/GUARDS/RECOVERY/REFRESH_ONLY assignment in the user-tier installers
  # Either quote: deploy-runtime-install.sh spells its lists with ", admission-install.sh with '.
  awk -v q="'" '$0 ~ "^(FILES|GUARDS|RECOVERY|REFRESH_ONLY)=[\"" q "]" { f = 1 } f { print } f && $0 ~ "[\"" q "][[:space:]]*$" && $0 !~ "=[\"" q "]$" { f = 0 }' \
    "$T_ROOT/bin/deploy-runtime-install.sh" "$T_ROOT/bin/admission-install.sh" | tr -s " \"'=\\\\" '\n'
}
# The root-owned collector copies its own files into @BIN@ with one `step cp "$HERE/<f>" ... "$BIN/"` line.
collector() { awk '/step cp .*"\$BIN\/"/' "$T_ROOT/bin/audit-collector-install.sh" | grep -o '\$HERE/[A-Za-z0-9._-]*' | sed 's|.*/||'; }
P="$(payload)"; B="$(collector)"

t_section "the payloads are read, not empty"
t_has "the runtime installer's list is found" "$P" "agent-idle-check.sh"
t_has "the floor installer's list is found" "$P" "admission-ask.sh"
t_has "the collector installer's copy line is found" "$B" "audit-collector.sh"
t_eq "the network guard is in the runtime payload" yes "$(printf '%s\n' "$P" | grep -qxF status-network.sh && echo yes || echo no)"

t_section "each launchd template's script is shipped by its installer"
_n=0
for _pl in "$T_ROOT"/launchd/*.plist; do
  _named=0
  for _s in $(grep -o '@HOME@/\.claude/bin/[A-Za-z0-9._-]*' "$_pl" | sed 's|.*/||' | sort -u); do
    _n=$((_n + 1)); _named=1
    if printf '%s\n' "$P" | grep -qxF "$_s"; then t_pass
    else t_fail "${_pl##*/} runs ~/.claude/bin/$_s, which no installer payload ships (add it to FILES in bin/deploy-runtime-install.sh)"; fi
  done
  for _s in $(grep -o '@BIN@/[A-Za-z0-9._-]*' "$_pl" | sed 's|.*/||' | sort -u); do
    _n=$((_n + 1)); _named=1
    if printf '%s\n' "$B" | grep -qxF "$_s"; then t_pass
    else t_fail "${_pl##*/} runs @BIN@/$_s, which bin/audit-collector-install.sh does not copy into \$BIN"; fi
  done
  # A template that names its script some third way is not judged: say so rather than pass it silently.
  [ "$_named" = 1 ] || t_fail "${_pl##*/} names no script under @HOME@/.claude/bin/ or @BIN@/: this test cannot judge it"
done
t_eq "templates name scripts at all (the scan read something)" yes "$([ "$_n" -gt 5 ] && echo yes || echo no)"
t_done
