#!/usr/bin/env sh
# id.test.sh (harbor#1278) — `harbor hub id`: the person reads their laptop's random id (legal/dpia.md R12), exactly what the
# install wrote, on stdout alone, and the command never makes, changes or guesses one.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MD="$T_TMP/managed"; MR="$MD/harbor"; MB="$MR/bin"
mkdir -p "$MB" "$MD/harbor-ids"
for _f in hub.sh library-log.sh library-hub.sh library-pack-version.sh hub-sync.sh; do cp "$T_ROOT/bin/$_f" "$MB/"; done
: > "$MB/harbor-member-mode"
printf 'hub=fixture-org/fixture-hub\nlogin=alice\nhome=%s\n' "$HOME" > "$MR/member.conf"
LID="0f1e2d3c4b5a69788796a5b4c3d2e1f0"; IDF="$MD/harbor-ids/$(id -un).id"
printf '%s\n' "$LID" > "$IDF"; chmod 0444 "$IDF"
run() { _rc=0; sh "$MB/hub.sh" id > "$T_TMP/out" 2> "$T_TMP/err" || _rc=$?; }

t_section "1 - it shows the id the install wrote"
run
t_eq "exit 0" 0 "$_rc"
t_eq "stdout is the id alone" "$LID" "$(cat "$T_TMP/out")"
t_has "no receipt yet, and it says so" "$(cat "$T_TMP/err")" "sends no counts"
: > "$MR/notice-received"
run
t_has "with the receipt it says counts go under this id" "$(cat "$T_TMP/err")" "under this id only"

t_section "2 - read only"
_before="$(ls -l "$IDF" | awk '{ print $1 }') $(cat "$IDF")"
run; run
t_eq "the file is untouched" "$_before" "$(ls -l "$IDF" | awk '{ print $1 }') $(cat "$IDF")"
rm -f "$IDF"
run
t_eq "no id: exit 1" 1 "$_rc"
t_eq "...and none is made" no "$([ -e "$IDF" ] && echo yes || echo no)"
t_eq "...and nothing printed as an id" "" "$(cat "$T_TMP/out")"
printf 'alice\n' > "$IDF"
run
t_eq "a file holding anything but 32 hex is not shown" "1 " "$_rc $(cat "$T_TMP/out")"

t_section "3 - not a member laptop"
rm -f "$MB/harbor-member-mode"
printf '%s\n' "$LID" > "$IDF"
run
t_eq "no marker: exit 1, no id" "1 " "$_rc $(cat "$T_TMP/out")"
t_done
