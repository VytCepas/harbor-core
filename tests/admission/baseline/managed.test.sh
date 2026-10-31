#!/usr/bin/env sh
# The floor suite, part managed (harbor#1022): the managed-settings mods lockdown. The installer
# writes only the keys the issue names and merges; floor-verify's row warns for a missing file (the operator's sudo install
# has not run yet) and goes red for each unset key, and a file that is not root-owned. No test needs root: HARBOR_MANAGED_SETTINGS
# moves the path, HARBOR_MANAGED_OWNER_UID says which owner counts as root for the fixture.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
INST="$SRC/scope-managed-mods.sh"
ME="$(id -u)"
M="$TMP/managed/managed-settings.json"
KEY='cc-plugin-sec-default@builtin'
fv() { # run floor-verify against the sandbox config dir with the managed path moved; stdout only
  HARBOR_MANAGED_SETTINGS="$M" HARBOR_MANAGED_OWNER_UID="${OWNER:-$ME}" sh "$SRC/floor-verify.sh" --dir "$CFG" 2>&1 | grep 'managed'
}
good() { mkdir -p "$(dirname "$M")"; jq -n --arg k "$KEY" \
  '{pluginConfigs:{($k):{options:{allowManagedModsOnly:true}}},disableSideloadFlags:true}' > "$M"; }

t_section "floor-verify row: green only for the whole lockdown"
rm -f "$M"; OUT="$(fv)"
t_has "absent file is a warning, with the install command" "$OUT" 'WARN'
t_has "...naming the fix" "$OUT" 'scope-managed-mods.sh'
t_hasnt "...and not a FAIL: a box before the operator's sudo install is not broken" "$OUT" 'FAIL'
good; OUT="$(fv)"
t_has "CONTROL: both keys set, owner counts as root: ok" "$OUT" 'ok:'
t_hasnt "CONTROL: no FAIL when whole" "$OUT" 'FAIL'
good; jq 'del(.disableSideloadFlags)' "$M" > "$M.t" && mv "$M.t" "$M"
t_has "disableSideloadFlags unset is FAIL" "$(fv)" 'FAIL'
good; jq 'del(.pluginConfigs)' "$M" > "$M.t" && mv "$M.t" "$M"
t_has "allowManagedModsOnly unset is FAIL" "$(fv)" 'FAIL'
good; jq '.pluginConfigs[$k].options.allowManagedModsOnly=false' --arg k "$KEY" "$M" > "$M.t" && mv "$M.t" "$M"
t_has "allowManagedModsOnly false is FAIL" "$(fv)" 'FAIL'
good; OWNER=$((ME + 1)); t_has "file not owned by root is FAIL" "$(fv)" 'FAIL'; OWNER=
printf 'not json' > "$M"; t_has "unparseable file is FAIL" "$(fv)" 'FAIL'

t_section "installer: dry run, merge, never allowManagedHooksOnly, uninstall"
rm -rf "$TMP/managed"
export HARBOR_MANAGED_SETTINGS="$M"
DRY="$(sh "$INST" --dry-run 2>&1)"
t_has "dry run names the target" "$DRY" "$M"
t_has "dry run prints the keys" "$DRY" 'disableSideloadFlags'
t_eq "dry run writes nothing" absent "$([ -e "$M" ] && echo present || echo absent)"
sh "$INST" >/dev/null 2>&1
t_eq "install: modsOnly" true "$(jq -r --arg k "$KEY" '.pluginConfigs[$k].options.allowManagedModsOnly' "$M")"
t_eq "install: sideload" true "$(jq -r '.disableSideloadFlags' "$M")"
t_eq "install: registers a directory marketplace" directory "$(jq -r '.extraKnownMarketplaces[]?.source.source' "$M" | head -1)"
t_eq "install: allowManagedHooksOnly NOT set" null "$(jq -r '.allowManagedHooksOnly // "null"' "$M")"
t_has "install: its own row is green" "$(fv)" 'ok:'
jq '.model="x" | .pluginConfigs["other@y"]={"options":{"a":1}}' "$M" > "$M.t" && mv "$M.t" "$M"
sh "$INST" >/dev/null 2>&1
t_eq "merge keeps a foreign top-level key" x "$(jq -r '.model' "$M")"
t_eq "merge keeps a foreign plugin config" 1 "$(jq -r '.pluginConfigs["other@y"].options.a' "$M")"
sh "$INST" --uninstall >/dev/null 2>&1
t_eq "uninstall keeps the foreign key" x "$(jq -r '.model' "$M")"
t_eq "uninstall removes sideload" null "$(jq -r '.disableSideloadFlags // "null"' "$M")"
t_eq "uninstall removes modsOnly" null "$(jq -r --arg k "$KEY" '.pluginConfigs[$k] // "null"' "$M")"
t_has "after uninstall the row is a warning again" "$(fv)" 'WARN'

t_section "the write is read back: a write that lands nowhere is a FAIL, not a green exit (harbor#457)"
rb() { HARBOR_MANAGED_SETTINGS="$M" sh -c 'MANAGED_MODS_LIB=1; . "$0"; managed_verify "$@"' "$INST" "$@" 2>&1; echo "exit $?"; }
MD="$TMP/rb/harbor-mods"; M="$TMP/rb/managed-settings.json"; rm -rf "$TMP/rb"; mkdir -p "$MD/.claude-plugin"
printf '{"b":2,"a":1}\n' > "$M"; : > "$MD/.claude-plugin/marketplace.json"
t_has "CONTROL: the file holds the JSON meant, key order aside: ok" "$(rb install "$M" '{"a":1,"b":2}' "$MD")" "exit 0"
t_has "other JSON on disk than the one meant: FAIL" "$(rb install "$M" '{"a":1,"b":3}' "$MD")" "read-back: $M is not the JSON this run meant to write"
t_has "...and exit 1" "$(rb install "$M" '{"a":1,"b":3}' "$MD")" "exit 1"
rm -f "$M.gone"
t_has "no file at all: FAIL" "$(rb install "$M.gone" '{}' "$MD")" "is missing or not JSON after the write"
printf 'not json' > "$M.bad"
t_has "a file that is not JSON: FAIL" "$(rb install "$M.bad" '{}' "$MD")" "is missing or not JSON after the write"
rm -f "$MD/.claude-plugin/marketplace.json"
t_has "an install whose marketplace file is missing: FAIL" "$(rb install "$M" '{"a":1,"b":2}' "$MD")" "the marketplace file $MD/.claude-plugin/marketplace.json is missing after the write"
t_has "CONTROL: an uninstall owes no marketplace file" "$(rb uninstall "$M" '{"a":1,"b":2}' "$MD")" "exit 0"
# End to end: a copy whose final mv is a no-op exits 0 without the check, and 1 with it. The copy must differ from the original, or this proves nothing.
mkdir -p "$TMP/noop"; cp "$SRC/scope-managed-mods.sh" "$SRC/library-log.sh" "$TMP/noop/"
sed 's/chmod 0644 "$TMPF"; mv "$TMPF" "$FILE"; trap - EXIT/chmod 0644 "$TMPF"; trap - EXIT/' "$SRC/scope-managed-mods.sh" > "$TMP/noop/scope-managed-mods.sh"
t_eq "the sabotaged copy differs from the original (the no-op is really in it)" differs "$(cmp -s "$SRC/scope-managed-mods.sh" "$TMP/noop/scope-managed-mods.sh" && echo same || echo differs)"
export HARBOR_MANAGED_SETTINGS="$TMP/e2e/managed-settings.json"; rm -rf "$TMP/e2e"
OUT="$(sh "$TMP/noop/scope-managed-mods.sh" 2>&1)"; RC=$?
t_eq "a write that lands nowhere exits 1" 1 "$RC"
t_has "...with the read-back FAIL" "$OUT" "read-back: $HARBOR_MANAGED_SETTINGS is missing or not JSON after the write"
t_eq "...and the file really is absent" absent "$([ -e "$HARBOR_MANAGED_SETTINGS" ] && echo present || echo absent)"
rm -rf "$TMP/e2e"
OUT="$(sh "$INST" 2>&1)"; RC=$?
t_eq "CONTROL: the real script writes it and exits 0" 0 "$RC"
t_has "...and says it read it back" "$OUT" "and read it back"
M="$TMP/managed/managed-settings.json"; export HARBOR_MANAGED_SETTINGS="$M"

t_section "root refuses a caller-chosen path (decision function, no root needed)"
rr() { HARBOR_MANAGED_SETTINGS="${2-}" sh -c 'MANAGED_MODS_LIB=1; . "$0"; managed_refuse_override "$1"' "$INST" "$1" >/dev/null 2>&1; echo $?; }
t_eq "uid 0 with the override set: refused" 1 "$(rr 0 /tmp/x.json)"
t_eq "CONTROL: uid 0 without the override: allowed" 0 "$(rr 0 '')"
t_eq "CONTROL: non-root with the override (the test path): allowed" 0 "$(rr 501 /tmp/x.json)"
t_has "PATH is pinned at the top" "$(sed -n '1,/^HERE=/p' "$INST")" 'PATH=/usr/bin:/bin:/usr/sbin:/sbin'
t_done
