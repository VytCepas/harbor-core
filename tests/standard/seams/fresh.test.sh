#!/usr/bin/env sh
# bin/standard-seams-fresh.sh (harbor#1425) with the comparison stubbed: a stale copy is a finding, the report is the delta with
# ages, a fix is reported fixed, a receipt reaches the findings channel (a ticket, never a red PR), and a comparison that could
# not run is exit 3 and no green receipt. The comparison itself (a copy one commit behind turns red) is fleet's seams tests.
. "$(dirname "$0")/../../lib/core.sh"; t_init
CFG="$T_TMP/cfg"; mkdir -p "$CFG"
SEAMS="$T_TMP/seams.tsv"; TAB="$(printf '\t')"
printf 'id\tkind\tproducer\tconsumer\tcopy_path\tpin\tschema\tfreshness\towner\tallowed_lag\treason\npkg\tvendor\ta\tb\tv/\tM#c\t-\tcheck.seam-fresh\tstandard\t0\t-\n' > "$SEAMS"
STALE="$T_TMP/stale.sh"; printf '#!/bin/sh\nprintf "pkg\\tstale\\t6 file(s) differ, %s commit(s) behind\\n" "${BEHIND:-1}"\nexit 1\n' > "$STALE"
FRESH="$T_TMP/fresh.sh"; printf '#!/bin/sh\nexit 0\n' > "$FRESH"
BROKEN="$T_TMP/broken.sh"; printf '#!/bin/sh\necho boom >&2\nexit 3\n' > "$BROKEN"
UNCH="$T_TMP/unch.sh"; printf '#!/bin/sh\nprintf "pkg\\tunchecked\\tno checkout of a\\n"\nexit 0\n' > "$UNCH"
run() { sh "$T_ROOT/bin/standard-seams-fresh.sh" --register "$SEAMS" --root harbor="$T_ROOT" --checker "sh $1" --config-dir "$CFG" --today "$2" 2>&1; }
code() { sh "$T_ROOT/bin/standard-seams-fresh.sh" --register "$SEAMS" --root harbor="$T_ROOT" --checker "sh $1" --config-dir "$CFG" --today "$2" >/dev/null 2>&1; echo "exit $?"; }

t_section "a stale copy is a new finding"
_o="$(run "$STALE" 2026-11-02)"; rm -f "$CFG/cache/standard-seams-fresh.tsv"; _c="$(code "$STALE" 2026-11-02)"
t_has "stamped with the check id" "$_o" "[check:standard.seam-fresh]"
t_has "the seam and kind are the subject" "$_o" "check.seam-fresh pkg: stale"
t_has "the detail rides on the new line" "$_o" "6 file(s) differ"
t_eq "new finding exits 1" "exit 1" "$_c"

t_section "a second run with the producer further ahead is the same finding, not a new one"
_o="$(BEHIND=9 run "$STALE" 2026-11-09)"
t_has "nothing new" "$_o" "nothing new"
t_has "standing, with its age" "$_o" "oldest 7 day(s)"
t_eq "exits 0" "exit 0" "$(BEHIND=9 code "$STALE" 2026-11-09)"

t_section "the receipt is the findings channel's input: a ticket"
_r="$CFG/cache/checks/standard.seam-fresh.json"
t_has "red" "$(cat "$_r")" '"status":"red"'
t_has "fresh for a weekly check" "$(cat "$_r")" '"fresh_days":9'
t_has "naming the seam" "$(cat "$_r")" "check.seam-fresh pkg: stale"

t_section "a re-vendor is reported fixed, and green"
_o="$(run "$FRESH" 2026-11-16)"
t_has "fixed" "$_o" "  fixed "
t_has "green" "$(cat "$_r")" '"status":"green"'

t_section "a comparison that could not run is not a green"
rm -rf "$CFG/cache"
sh "$T_ROOT/bin/standard-seams-fresh.sh" --register "$SEAMS" --root harbor="$T_ROOT" --checker "sh $BROKEN" --config-dir "$CFG" --today 2026-11-23 >/dev/null 2>&1
t_eq "exit 3" "3" "$?"
t_hasnt "no green receipt" "$(cat "$CFG/cache/checks/standard.seam-fresh.json" 2>/dev/null)" '"status":"green"'

t_section "a seam whose checkout was missing keeps its earlier finding standing"
rm -rf "$CFG/cache"; run "$STALE" 2026-11-02 >/dev/null
_o="$(run "$UNCH" 2026-11-09)"
t_hasnt "not reported fixed" "$_o" "  fixed "
t_has "named as not judged" "$_o" "not judged"
t_done
