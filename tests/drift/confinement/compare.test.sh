#!/usr/bin/env sh
# drift.confinement (harbor#1299): drift-confinement.sh compares the installed sandbox block with a fresh compose.
# A fixture managed file stands in for the root-owned one (HARBOR_MANAGED_SETTINGS); the install that writes it is
# deploy-confinement.sh itself, so the check is proven against the writer's own output, never a hand-built copy.
# Also: every floor file is covered by an Edit deny rule (the ticket's last criterion).
. "$(dirname "$0")/../../lib/core.sh"; t_init
DC="$T_ROOT/bin/drift-confinement.sh"; INST="$T_ROOT/bin/deploy-confinement.sh"
PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT"; export PORT_ROOT
PRIV="$T_TMP/priv"; mkdir -p "$PRIV"
M="$T_TMP/managed/managed-settings.json"; mkdir -p "$T_TMP/managed"
export HARBOR_MANAGED_SETTINGS="$M" HARBOR_CONFINEMENT_PRIVATE="$PRIV" HARBOR_CONFINEMENT_OS=Darwin HARBOR_RECEIPTS="$T_TMP/receipts"
dc() { sh "$DC" "$@" 2>&1; }
rc() { sh "$DC" >/dev/null 2>&1; echo $?; }
state() { sh "$DC" --state 2>/dev/null; }
receipt() { jq -r .status "$HARBOR_RECEIPTS/drift.confinement.json" 2>/dev/null; }

t_section "not installed is a stood-down state, never drift"
t_eq "no managed file: exit 0" 0 "$(rc)"
t_eq "...and the state says not-installed" not-installed "$(state)"
t_eq "...and the receipt is stood-down" stood-down "$(receipt)"
printf '{"disableSideloadFlags":true}\n' > "$M"
t_eq "a managed file with no sandbox block and no marker: not-installed" not-installed "$(state)"

t_section "installed by deploy-confinement.sh: green"
sh "$INST" >/dev/null 2>&1
t_eq "CONTROL: the install wrote a sandbox block" true "$(jq 'has("sandbox")' "$M" 2>/dev/null)"
OUT="$(dc)"
t_eq "freshly installed: exit 0" 0 "$(rc)"
t_has "...and a matched ok line, stamped with the check id" "$OUT" "ok: [check:drift.confinement] the installed sandbox block matches the compose"
t_eq "...the state says match" match "$(state)"
t_eq "...the receipt is green" green "$(receipt)"
t_eq "--state keeps stdout to the one word" match "$(sh "$DC" --state 2>/dev/null | tr -d '\n')"
rm -f "$HARBOR_RECEIPTS/drift.confinement.json"; state >/dev/null
t_eq "--state (floor-verify's read) writes no receipt: a verifier writes nothing" absent "$([ -e "$HARBOR_RECEIPTS/drift.confinement.json" ] && echo present || echo absent)"
t_eq "CONTROL: a direct run writes it" green "$(rc >/dev/null; receipt)"
cp "$M" "$T_TMP/good.json"
jq '.sandbox.network.allowedDomains |= reverse' "$T_TMP/good.json" > "$M"
t_eq "the order of rows is not policy: a reversed host list still matches" match "$(state)"
cp "$T_TMP/good.json" "$M"

t_section "the ticket's falsifier: the sandbox block removed goes red, restored goes green"
jq 'del(.sandbox)' "$T_TMP/good.json" > "$M"
OUT="$(dc)"
t_eq "block removed, marker left: exit 1" 1 "$(rc)"
t_has "...naming the marker without its block" "$OUT" "note: [check:drift.confinement] the marker is present but $M holds no sandbox block"
t_has "...and each missing leaf" "$OUT" "the installed block lacks: network.allowedDomains[]=github.com"
t_has "...with the install as the fix" "$OUT" "fix: sudo sh $T_ROOT/bin/deploy-confinement.sh"
t_has "CONTROL: log-lib names a FAIL left without a fix this way" "$(sh -c '. "$1"; log_init x; log_fail y; log_end' _ "$T_ROOT/bin/log-lib.sh" 2>&1)" "no fix line followed"
t_hasnt "...a fix line after the FAIL, as CONTRACTS/logging.md asks" "$OUT" "no fix line followed"
t_eq "...the receipt is red" red "$(receipt)"
t_has "...naming its subjects" "$(jq -r '.subjects[]' "$HARBOR_RECEIPTS/drift.confinement.json")" "marker-without-block"
cp "$T_TMP/good.json" "$M"
t_eq "restored: green again" "0 match" "$(rc) $(state)"

t_section "each kind of drift reads as drift"
printf 'api.example.com\n' > "$PRIV/confinement-hosts.txt"
t_has "a new private host the install has not taken" "$(dc)" "lacks: network.allowedDomains[]=api.example.com"
rm -f "$PRIV/confinement-hosts.txt"
jq '.sandbox.network.allowedDomains += ["evil.example"]' "$T_TMP/good.json" > "$M"
t_has "a hand-added host" "$(dc)" "has what the compose does not: network.allowedDomains[]=evil.example"
jq '.sandbox.allowUnsandboxedCommands = false' "$T_TMP/good.json" > "$M"
t_eq "a flipped key is drift" drift "$(state)"
cp "$T_TMP/good.json" "$M"
mkdir -p "$PORT_ROOT/harbor-private"; printf 'confinement_strict = "true"\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_has "harbor.toml closing the retry before the install re-runs" "$(dc)" "lacks: allowUnsandboxedCommands=false"
rm -f "$PORT_ROOT/harbor-private/harbor.toml"
printf 'confinement_skip = "true"\n' > "$PORT_ROOT/harbor-private/harbor.toml"
t_has "harbor.toml turning the P3 skip on before the install re-runs" "$(dc)" "the marker's P3 skip is not what harbor.toml asks for now (the install would write it on)"
sh "$INST" >/dev/null 2>&1
t_eq "re-installed: the marker carries the skip, and the check is green" "match skip=covered" "$(state) $(grep -x 'skip=covered' "$T_TMP/managed/harbor-confinement")"
rm -f "$PORT_ROOT/harbor-private/harbor.toml"
t_eq "the skip turned off in harbor.toml is drift too" drift "$(state)"
sh "$INST" >/dev/null 2>&1
t_eq "CONTROL: re-installed without it, green" match "$(state)"
cp "$T_TMP/managed/harbor-confinement" "$T_TMP/marker.good"; rm -f "$T_TMP/managed/harbor-confinement"
t_has "a block with its marker gone: the ledger would read every call as off" "$(dc)" "holds a sandbox block but the marker is missing"
cp "$T_TMP/marker.good" "$T_TMP/managed/harbor-confinement"
t_eq "CONTROL: back to green" match "$(state)"

t_section "could not judge is unchecked (3), never green"
printf 'not a host!\n' > "$PRIV/confinement-hosts.txt"
t_eq "a compose that fails: exit 3" 3 "$(rc)"
t_has "...saying it had nothing to compare against" "$(dc)" "WARN: [check:drift.confinement] unchecked: the compose failed"
t_eq "...state unchecked" unchecked "$(state)"
rm -f "$PRIV/confinement-hosts.txt"
printf '{not json' > "$M"
t_eq "an unparseable managed file: exit 3" 3 "$(rc)"
cp "$T_TMP/good.json" "$M"
t_exit "an unknown argument is a usage error" 2 sh "$DC" --nope

t_section "permissions.deny covers Edit on every floor file (harbor#1299)"
# The floor's files: everything runtime-install.sh puts in <cfg>/bin, and every <cfg> row of CONTRACTS/helm-state.md.
# The rules: what floor-deny.sh would add to an empty settings.json, so a WITHDRAWN entry does not count.
FD="$T_TMP/fdcfg"; mkdir -p "$FD"; printf '{}\n' > "$FD/settings.json"
RULES="$(CLAUDE_CONFIG_DIR="$FD" sh "$T_ROOT/bin/floor-deny.sh" --dir "$FD" 2>&1 | sed -n 's/.*+ Edit(\(.*\))$/\1/p')"
t_eq "CONTROL: floor-deny names Edit rules" yes "$([ "$(printf '%s\n' "$RULES" | grep -c .)" -ge 20 ] && echo yes || echo no)"
FILES="$(sed -n 's/^FILES="\(.*\)"/\1/p' "$T_ROOT/bin/runtime-install.sh" | tr ' ' '\n' | sed '/^$/d; s|^|~/.claude/bin/|')"
STATE_ROWS="$(awk '/^## The table/ { s = 1; next } s && /^## / { s = 0 }
  s && /^\| `/ { split($0, c, "|"); gsub(/^[ \t]+|[ \t]+$|`/, "", c[4]); gsub(/^[ \t]+|[ \t]+$/, "", c[3])
                 if (c[4] == "integrity") { w = c[3]; sub(/^`/, "", w); sub(/`.*/, "", w); sub(/\/$/, "", w); print w } }' "$T_ROOT/CONTRACTS/helm-state.md" \
  | sed -n 's|^<cfg>/|~/.claude/|p')"
t_eq "CONTROL: runtime-install names files" yes "$([ "$(printf '%s\n' "$FILES" | grep -c .)" -ge 20 ] && echo yes || echo no)"
t_eq "CONTROL: helm-state names integrity paths" yes "$([ "$(printf '%s\n' "$STATE_ROWS" | grep -c .)" -ge 5 ] && echo yes || echo no)"
# covered <path>: a rule equal to it, or a `<dir>/**` rule above it
covered() { printf '%s\n' "$RULES" | awk -v p="$1" '$0 == p { f = 1 } /\/\*\*$/ { d = substr($0, 1, length($0) - 3); if (index(p, d) == 1 || p == substr(d, 1, length(d) - 1)) f = 1 } END { exit !f }'; }
_unc=""
for _p in $FILES $STATE_ROWS ~/.claude/settings.json; do
  case "$_p" in '~/'*) ;; *) _p="~/${_p#"$HOME"/}" ;; esac
  covered "$_p" || _unc="$_unc $_p"
done
t_eq "every floor file has an Edit deny rule" "" "$_unc"
t_exit "CONTROL: a path outside the floor is not covered" 1 covered "~/.claude/projects/x/memory/a.md"
t_done
