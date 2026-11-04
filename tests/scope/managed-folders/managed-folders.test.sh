#!/usr/bin/env sh
# scope-managed-folders.sh (harbor#1442): renders contracts/main-folders.txt as Edit deny rows, merges them into the
# managed file without touching another installer's keys, removes only its own rows, and --missing is the verifier:
# remove a row and it names it, restore the row and it is silent. HARBOR_SCOPE_MANAGED_SETTINGS: no root.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$(cd "$(dirname "$0")/../../.." && pwd)"
S="$R/bin/scope-managed-folders.sh"
M="$T_TMP/managed/managed-settings.json"; mkdir -p "$T_TMP/managed"
PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT"; export PORT_ROOT
run() { HARBOR_SCOPE_MANAGED_SETTINGS="$M" sh "$S" "$@" >/dev/null 2>&1; echo $?; }
miss() { HARBOR_SCOPE_MANAGED_SETTINGS="$M" sh "$S" --missing 2>/dev/null; }
n() { printf '%s\n' "$1" | grep -c . || :; }

t_section "the rows come from the contract, Edit and home-anchored"
ROWS="$(sh "$S" --rows)"
t_has "Desktop is a row" "$ROWS" "Edit(~/Desktop/**)"
t_has "Documents is a row" "$ROWS" "Edit(~/Documents/**)"
t_has "the persistence folder is a row" "$ROWS" "Edit(~/Library/LaunchAgents/**)"
t_hasnt "no Write(...) row: the harness never consults one" "$ROWS" "Write("
t_eq "one row per contract line" "$(grep -vc '^[[:space:]]*\(#\|$\)' "$R/contracts/main-folders.txt")" "$(n "$ROWS")"

t_section "install merges, never clobbers"
t_eq "CONTROL: no managed file: every row is missing" "$(n "$ROWS")" "$(n "$(miss)")"
printf '{"disableSideloadFlags":true,"permissions":{"deny":["Bash(curl:*)"],"allow":["Read"]}}\n' > "$M"
t_eq "install exits 0" 0 "$(run)"
t_eq "another installer's key survives" true "$(jq -c .disableSideloadFlags "$M")"
t_eq "and its deny row and allow list" '["Bash(curl:*)"] ["Read"]' "$(jq -c '.permissions.deny | map(select(startswith("Bash")))' "$M") $(jq -c .permissions.allow "$M")"
t_eq "nothing is missing after the install" 0 "$(n "$(miss)")"
run >/dev/null
t_eq "a second install adds no duplicate" "$(( $(n "$ROWS") + 1 ))" "$(jq '.permissions.deny | length' "$M")"
t_eq "the file is 0644" "-rw-r--r--" "$(ls -l "$M" | cut -c1-10)"

t_section "red then green: --missing is the verifier"
cp "$M" "$T_TMP/good.json"
jq '.permissions.deny -= ["Edit(~/Desktop/**)"]' "$T_TMP/good.json" > "$M"
t_eq "a row removed: --missing names exactly it" "Edit(~/Desktop/**)" "$(miss)"
cp "$T_TMP/good.json" "$M"
t_eq "restored: silent" 0 "$(n "$(miss)")"
printf 'not json' > "$M"
t_exit "an unreadable managed file is unchecked (3), never an empty list" 3 env HARBOR_SCOPE_MANAGED_SETTINGS="$M" sh "$S" --missing
cp "$T_TMP/good.json" "$M"

t_section "dry run and uninstall"
printf '{"permissions":{"deny":["Bash(curl:*)"]}}\n' > "$M"
t_has "a dry run prints the merged JSON" "$(HARBOR_SCOPE_MANAGED_SETTINGS="$M" sh "$S" --dry-run 2>/dev/null)" "Edit(~/Desktop/**)"
t_eq "and writes nothing" '["Bash(curl:*)"]' "$(jq -c .permissions.deny "$M")"
cp "$T_TMP/good.json" "$M"
t_eq "uninstall exits 0" 0 "$(run --uninstall)"
t_eq "it removes only its own rows" '["Bash(curl:*)"]' "$(jq -c .permissions.deny "$M")"
printf '{"disableSideloadFlags":true}\n' > "$M"; run >/dev/null; run --uninstall >/dev/null
t_eq "a file it created the permissions block for ends without it" '{"disableSideloadFlags":true}' "$(jq -c . "$M")"

t_section "the private layer adds folders; a bad row is refused"
mkdir -p "$PORT_ROOT/harbor-private"
printf '# why\n~/Sites\n' > "$PORT_ROOT/harbor-private/main-folders.txt"
t_has "a private row is rendered after the core rows" "$(sh "$S" --rows)" "Edit(~/Sites/**)"
printf '/etc\n' > "$PORT_ROOT/harbor-private/main-folders.txt"
t_eq "a row that is not home-relative is refused" 1 "$(run --rows)"
printf '~/Sites/*\n' > "$PORT_ROOT/harbor-private/main-folders.txt"
t_eq "and a glob in a row" 1 "$(run --rows)"
rm -rf "$PORT_ROOT/harbor-private"

t_section "refusals"
printf 'not json' > "$M"
t_eq "an install onto a file that is not a JSON object is refused" 1 "$(run)"
t_eq "and leaves it untouched" "not json" "$(cat "$M")"
t_eq "an unknown argument is a usage error" 2 "$(run --bogus)"
t_done
