#!/usr/bin/env sh
# The floor suite, part confinement (harbor#1298, #555 P1): deploy-confinement.sh composes core then private rows into
# the `sandbox` block, merges it into managed-settings.json, and reads it back. No test needs root:
# HARBOR_MANAGED_SETTINGS moves the file, HARBOR_CONFINEMENT_PRIVATE names the layer, HARBOR_CONFINEMENT_OS the platform.
. "$(dirname "$0")/../lib/core.sh"; t_init
INST="$T_ROOT/bin/deploy-confinement.sh"
PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT"; export PORT_ROOT
PRIV="$T_TMP/priv"; mkdir -p "$PRIV"
cmp_() { HARBOR_CONFINEMENT_PRIVATE="$1" HARBOR_CONFINEMENT_OS="${2:-Darwin}" sh "$INST" --compose 2>&1; }
q() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

t_section "compose: core alone, then the private layer after it"
CORE="$(cmp_ '')"
t_eq "no layer and a layer without the two files compose byte for byte alike" "$CORE" "$(cmp_ "$PRIV")"
t_eq "core hosts are first, GitHub leading" github.com "$(q "$CORE" '.network.allowedDomains[0]')"
t_eq "the domain lock is on" true "$(q "$CORE" '.network.allowManagedDomainsOnly')"
t_eq "local binding stays off: Chrome is reached through the harbor_chrome MCP server (harbor#1301)" false "$(q "$CORE" '.network.allowLocalBinding')"
t_eq "the retry stays open for P1's week" true "$(q "$CORE" '.allowUnsandboxedCommands')"
t_eq "failIfUnavailable: no silent unconfined run" true "$(q "$CORE" '.failIfUnavailable')"
_rp="$(CDPATH= cd -P -- "$PORT_ROOT" && pwd)"
t_eq "@PORT_ROOT@ resolves to the resolved workspace root" "$_rp" "$(q "$CORE" '.filesystem.allowWrite[0]')"
t_eq "@DELIVERABLES@ falls back to ~/Deliverables" '~/Deliverables' "$(q "$CORE" '.filesystem.allowWrite[1]')"
t_has "a repo's .git/hooks is write-denied anywhere in the zone" "$(q "$CORE" '.filesystem.denyWrite[]')" "$_rp/**/.git/hooks"
t_has "the system CA bundle is read-allowed" "$(q "$CORE" '.filesystem.allowRead[]')" "/etc/ssl/cert.pem"
t_eq "no @token survives composition" "" "$(printf '%s' "$CORE" | grep -o '@[A-Z_]*@' || :)"
printf '# why: a workload API\napi.example.com\ngithub.com\n' > "$PRIV/confinement-hosts.txt"
printf 'write ~/.config/example\nread /opt/example/cacert.pem\n' > "$PRIV/confinement-paths.txt"
WITH="$(cmp_ "$PRIV")"
t_eq "a private host comes after core's" api.example.com "$(q "$WITH" '.network.allowedDomains[-1]')"
t_eq "a host both lists name appears once" 1 "$(q "$WITH" '[.network.allowedDomains[] | select(. == "github.com")] | length')"
t_eq "a private write path is appended" '~/.config/example' "$(q "$WITH" '.filesystem.allowWrite[-1]')"
t_eq "a private read path is appended" /opt/example/cacert.pem "$(q "$WITH" '.filesystem.allowRead[-1]')"

t_section "a row that does not compose refuses, naming it"
printf 'not a host!\n' > "$PRIV/confinement-hosts.txt"
OUT="$(cmp_ "$PRIV")"; RC=$?
t_has "a bad host row is a FAIL naming the row" "$OUT" "a row that does not compose: not a host!"
t_exit "...and exit 1" 1 sh -c 'HARBOR_CONFINEMENT_PRIVATE="$1" sh "$2" --compose >/dev/null 2>&1' _ "$PRIV" "$INST"
rm -f "$PRIV/confinement-hosts.txt"; printf 'write relative/path\n' > "$PRIV/confinement-paths.txt"
t_has "a relative path row is a FAIL" "$(cmp_ "$PRIV")" "a row that does not compose: write relative/path"
rm -f "$PRIV/confinement-paths.txt"; mkdir "$PRIV/confinement-paths.txt"
t_has "a file that exists and cannot be read (a directory) refuses" "$(cmp_ "$PRIV")" "exists but cannot be read"
rmdir "$PRIV/confinement-paths.txt"

t_section "platform: the weaker-isolation key is Darwin's alone"
t_eq "Darwin: written" true "$(q "$(cmp_ '' Darwin)" '.enableWeakerNetworkIsolation')"
t_eq "Linux: absent" null "$(q "$(cmp_ '' Linux)" '.enableWeakerNetworkIsolation')"
t_has "the header declares it" "$(head -n 30 "$INST")" "# platform: enableWeakerNetworkIsolation is written on Darwin only"

t_section "P4 and P5 are harbor.toml keys, off by default, and a refused harbor.toml refuses"
t_has "CI workflows are write-denied in the zone (the P3 baseline's condition)" "$(q "$CORE" '.filesystem.denyWrite[]')" "$_rp/**/.github/workflows"
t_eq "default: no credentials block" null "$(q "$CORE" '.credentials')"
mkdir -p "$PORT_ROOT/harbor-private"; printf 'confinement_strict = "true"\nconfinement_credentials = "true"\n' > "$PORT_ROOT/harbor-private/harbor.toml"
ON="$(cmp_ '')"
t_eq "confinement_strict closes the retry (P4)" false "$(q "$ON" '.allowUnsandboxedCommands')"
t_eq "confinement_credentials writes the secret rows as deny (P5)" deny "$(q "$ON" '.credentials.files[0].mode')"
t_has "...naming the key stores" "$(q "$ON" '.credentials.files[].path')" "~/.ssh"
printf 'confinement_strict = true\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_has "an unquoted value is a refused harbor.toml, never a silent false" "$(cmp_ '')" "harbor.toml cannot be read for confinement_strict"
t_exit "...and the compose exits 1" 1 sh -c 'HARBOR_CONFINEMENT_PRIVATE= sh "$1" --compose >/dev/null 2>&1' _ "$INST"
rm -f "$PORT_ROOT/harbor-private/harbor.toml"

t_section "Linux preflight: bubblewrap must start for the operator, or the install refuses"
STUB="$T_TMP/stub"; SYS="$T_TMP/sys"; mkdir -p "$STUB" "$SYS"
# The system's tools minus bwrap: a hosted Ubuntu image ships it in /usr/bin, so "without bwrap" must not rest on the image.
for _f in /bin/* /usr/bin/*; do case "${_f##*/}" in bwrap|socat) ;; *) [ -e "$SYS/${_f##*/}" ] || ln -s "$_f" "$SYS/${_f##*/}" ;; esac; done
pf() { PATH="$STUB:$SYS" sh -c 'CONFINEMENT_LIB=1; . "$0"; PATH="$1"; confine_preflight "$2"' "$INST" "$STUB:$SYS" "$1" 2>&1; echo "exit $?"; }
t_has "Darwin: Seatbelt ships with the OS, nothing to check" "$(pf Darwin)" "exit 0"
printf '#!/bin/sh\nexit 0\n' > "$STUB/socat"; chmod +x "$STUB/socat"
t_has "Linux without bwrap: refused, naming the package" "$(pf Linux)" "missing: bwrap"
printf '#!/bin/sh\necho "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted" >&2; exit 1\n' > "$STUB/bwrap"; chmod +x "$STUB/bwrap"
OUT="$(pf Linux)"
t_has "Linux where bwrap cannot start (stock Ubuntu 24.04): refused" "$OUT" "bubblewrap cannot start an isolated network namespace"
t_has "...naming the AppArmor profile fix" "$OUT" "/etc/apparmor.d/bwrap"
t_has "...and exit 1" "$OUT" "exit 1"
printf '#!/bin/sh\nexit 0\n' > "$STUB/bwrap"
t_has "CONTROL: Linux where bwrap starts: passes" "$(pf Linux)" "exit 0"

t_section "installer: dry run, merge, uninstall"
# Darwin pinned: these arms test the write, and the Linux preflight has its own section (a CI runner has no bwrap).
M="$T_TMP/managed/managed-settings.json"; export HARBOR_MANAGED_SETTINGS="$M" HARBOR_CONFINEMENT_PRIVATE='' HARBOR_CONFINEMENT_OS=Darwin
DRY="$(sh "$INST" --dry-run 2>&1)"
t_has "dry run names the target" "$DRY" "$M"
t_has "dry run prints the sandbox block" "$DRY" '"allowManagedDomainsOnly": true'
t_eq "dry run writes nothing" absent "$([ -e "$M" ] && echo present || echo absent)"
mkdir -p "$(dirname "$M")"; printf '{"disableSideloadFlags":true,"model":"x"}\n' > "$M"
OUT="$(sh "$INST" 2>&1)"; RC=$?
t_eq "install exits 0" 0 "$RC"
t_has "...and says it read the file back" "$OUT" "and read it back"
t_eq "install writes the block" true "$(jq -r '.sandbox.enabled' "$M")"
t_eq "merge keeps a sibling installer's key" true "$(jq -r '.disableSideloadFlags' "$M")"
t_eq "merge keeps a foreign key" x "$(jq -r '.model' "$M")"
t_eq "install leaves the ledger's marker beside the file" present "$([ -f "$(dirname "$M")/harbor-confinement" ] && echo present || echo absent)"
MK="$(dirname "$M")/harbor-confinement"
t_eq "the marker carries no P3 skip by default" 0 "$(grep -c '^skip=' "$MK")"
mkdir -p "$PORT_ROOT/harbor-private"; printf 'confinement_skip = "true"\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_eq "--marker prints the skip line once harbor.toml turns it on (P3, harbor#1300)" skip=covered "$(sh "$INST" --marker 2>/dev/null | tail -1)"
sh "$INST" >/dev/null 2>&1
t_eq "...and the install writes it into the marker" 1 "$(grep -cx 'skip=covered' "$MK")"
printf 'confinement_skip = true\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_exit "an unquoted skip value refuses, never a silent off" 1 sh -c 'sh "$1" --marker >/dev/null 2>&1' _ "$INST"
rm -f "$PORT_ROOT/harbor-private/harbor.toml"; sh "$INST" >/dev/null 2>&1
t_eq "CONTROL: re-installed without it, the skip is gone" 0 "$(grep -c '^skip=' "$MK")"
printf 'confinement_skip = "true"\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_has "the install says the P3 skip is on, every time" "$(sh "$INST" 2>&1)" "P3 skip: ON"
rm -f "$PORT_ROOT/harbor-private/harbor.toml"
t_has "...and says off when it is" "$(sh "$INST" 2>&1)" "P3 skip: off"
sh "$INST" --uninstall >/dev/null 2>&1
t_eq "uninstall removes the block" null "$(jq -r '.sandbox // "null"' "$M")"
t_eq "...and the marker" absent "$([ -f "$(dirname "$M")/harbor-confinement" ] && echo present || echo absent)"
t_eq "uninstall keeps the sibling's key" true "$(jq -r '.disableSideloadFlags' "$M")"
printf 'not a host!\n' > "$PRIV/confinement-hosts.txt"
OUT="$(HARBOR_CONFINEMENT_PRIVATE="$PRIV" sh "$INST" 2>&1 >/dev/null)"
t_has "a refused compose during install shows its FAIL on stderr, never swallowed into the block" "$OUT" "a row that does not compose: not a host!"
t_eq "...and the managed file is left as it was" null "$(jq -r '.sandbox // "null"' "$M")"
rm -f "$PRIV/confinement-hosts.txt"
printf 'not json' > "$M"
t_exit "a managed file that is not a JSON object is never touched" 1 sh "$INST"
t_eq "...and stays as it was" 'not json' "$(cat "$M")"

t_section "the write is read back: a write that lands nowhere is a FAIL, not a green exit (harbor#457)"
mkdir -p "$T_TMP/noop"; cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/roots.sh" "$T_TMP/noop/"
sed 's/chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"/chmod 0644 "$TMPF"/' "$INST" > "$T_TMP/noop/deploy-confinement.sh"
mkdir -p "$T_TMP/CONTRACTS"; cp "$T_ROOT/CONTRACTS/confinement-hosts.txt" "$T_ROOT/CONTRACTS/confinement-paths.txt" "$T_ROOT/CONTRACTS/roots.tsv" "$T_TMP/CONTRACTS/"
t_eq "the sabotaged copy differs from the original" differs "$(cmp -s "$INST" "$T_TMP/noop/deploy-confinement.sh" && echo same || echo differs)"
export HARBOR_MANAGED_SETTINGS="$T_TMP/e2e/managed-settings.json"
OUT="$(sh "$T_TMP/noop/deploy-confinement.sh" 2>&1)"; RC=$?
t_eq "a write that lands nowhere exits 1" 1 "$RC"
t_has "...with the read-back FAIL" "$OUT" "read-back: $HARBOR_MANAGED_SETTINGS is missing or not JSON after the write"
t_exit "CONTROL: the real script writes it and exits 0" 0 sh "$INST"

t_section "root refuses caller-chosen targets and content (decision function, no root needed)"
rr() { env "$2=${3:-}" sh -c 'CONFINEMENT_LIB=1; . "$0"; confine_refuse_override "$1"' "$INST" "$1" >/dev/null 2>&1; echo $?; }
for _v in HARBOR_MANAGED_SETTINGS HARBOR_CONFINEMENT_PRIVATE HARBOR_CONFINEMENT_OS; do
  t_eq "uid 0 with $_v set: refused" 1 "$(rr 0 "$_v" x)"
done
t_eq "CONTROL: uid 0 with none set: allowed" 0 "$(env -u HARBOR_MANAGED_SETTINGS -u HARBOR_CONFINEMENT_PRIVATE -u HARBOR_CONFINEMENT_OS sh -c 'CONFINEMENT_LIB=1; . "$0"; confine_refuse_override 0' "$INST" >/dev/null 2>&1; echo $?)"
t_eq "CONTROL: non-root with an override (the test path): allowed" 0 "$(rr 501 HARBOR_MANAGED_SETTINGS x)"
t_has "PATH is pinned before anything runs" "$(sed -n '1,/^HERE=/p' "$INST")" 'PATH=/usr/bin:/bin:/usr/sbin:/sbin'
t_done
