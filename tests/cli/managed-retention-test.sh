#!/usr/bin/env sh
# managed-retention.sh (harbor#1181 lane 6): pins cleanupPeriodDays by merging into the managed file, never
# clobbers the keys another installer wrote, and removes only its own key. HARBOR_MANAGED_SETTINGS: no root.
. "$(dirname "$0")/../lib/core.sh"; t_init
S="$(cd "$(dirname "$0")/../.." && pwd)/bin/managed-retention.sh"
M="$T_TMP/managed/managed-settings.json"
run() { HARBOR_MANAGED_SETTINGS="$M" sh "$S" "$@" >/dev/null 2>&1; echo $?; }
key() { jq -c "$1" "$M" 2>/dev/null; }

t_section "install"
t_eq "a fresh install exits 0" 0 "$(run)"
t_eq "it pins 365 days" 365 "$(key .cleanupPeriodDays)"
printf '{"disableSideloadFlags":true,"cleanupPeriodDays":30}\n' > "$M"
t_eq "an existing file is merged" 0 "$(run)"
t_eq "another installer's key survives" true "$(key .disableSideloadFlags)"
t_eq "and a lower retention is raised" 365 "$(key .cleanupPeriodDays)"
t_eq "the file is 0644" "-rw-r--r--" "$(ls -l "$M" | cut -c1-10)"

t_section "dry run and uninstall"
printf '{"cleanupPeriodDays":30}\n' > "$M"
t_has "a dry run prints the merged JSON" "$(HARBOR_MANAGED_SETTINGS="$M" sh "$S" --dry-run 2>/dev/null)" '"cleanupPeriodDays": 365'
t_eq "and writes nothing" 30 "$(key .cleanupPeriodDays)"
printf '{"disableSideloadFlags":true,"cleanupPeriodDays":365}\n' > "$M"
t_eq "uninstall exits 0" 0 "$(run --uninstall)"
t_eq "it removes only its own key" '{"disableSideloadFlags":true}' "$(key .)"

t_section "refusals"
printf 'not json' > "$M"
t_eq "a file that is not a JSON object is refused" 1 "$(run)"
t_eq "and left untouched" "not json" "$(cat "$M")"
t_eq "an unknown argument is a usage error" 2 "$(run --bogus)"
t_done
