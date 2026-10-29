#!/usr/bin/env sh
# A deploy across a rename (harbor#949): a box installed before W3 holds bin/restore.sh, bin/log-lib.sh, … and their
# B6 pins. The installers that ship the new names must leave B6, floor-verify and install-drift green with no step in
# between: the old name becomes the checkout's shim and its pin goes, both backed up. Measured red on 6da7ceca, where
# B6 blocked on four stale pins and install-drift read 35 old copies stale (the deploy then restored itself).
. "$(dirname "$0")/../../lib/core.sh"; t_init
BASE=cbdd75fa   # the box's commit on 2026-10-29: the last main before the W3 bin renames (harbor#1395)
EMPTY='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
b6msg() { CLAUDE_CONFIG_DIR="$1" sh "$1/bin/guard-integrity.sh" </dev/null 2>/dev/null | jq -r '.systemMessage // ""' 2>/dev/null; }
inst() { # <bin dir> <box> — runtime then floor, as deploy orders them; the output of both
  _rt="$1/deploy-runtime-install.sh"; [ -f "$_rt" ] || _rt="$1/runtime-install.sh"   # its name before W3
  env -u CLAUDE_CONFIG_DIR sh "$_rt" --dir "$2" --apply 2>&1
  env -u CLAUDE_CONFIG_DIR sh "$1/floor-install.sh" --dir "$2" --apply --with-b6 2>&1
}
box() { mkdir -p "$1/bin"; printf '%s\n' "$EMPTY" > "$1/settings.json"; }
drift() { sh "$T_ROOT/bin/drift-install.sh" --dir "$1" --ref HEAD 2>&1 | sed -n 's/.*\(stale=[0-9]* modified=[0-9]*\).*/\1/p' | tail -1; }

if ! git -C "$T_ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null; then
  t_fail "$BASE is not in this clone: the upgrade cannot be reproduced (CI checks out with fetch-depth 0)"; t_done
fi
OLD="$T_TMP/old"; mkdir -p "$OLD"
git -C "$T_ROOT" archive "$BASE" -- ':(exclude).github' | tar -x -C "$OLD"
OB="$OLD/bin"

t_section "the box before: $BASE's runtime and floor"
D="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/box"; box "$D"
inst "$OB" "$D" >/dev/null
t_eq "control: $BASE's own install starts a session" "" "$(b6msg "$D")"
t_exit "control: it pinned the old name restore.sh" 0 test -f "$D/.helm-pins/restore.sh.sha256"
t_exit "control: and copied it as a file" 0 test -f "$D/bin/restore.sh"

t_section "this tree's installers onto it"
OUT="$(inst "$T_ROOT/bin" "$D")"
t_eq "B6 does not block the next session" "" "$(b6msg "$D")"
FV="$(env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/floor-verify.sh" --dir "$D" 2>&1 || true)"
t_has "floor-verify passes" "$(printf '%s\n' "$FV" | grep '^floor-verify: ' | tail -1)" ' 0 failed'
t_eq "install-drift reads no stale or modified copy (deploy's verify)" 'stale=0 modified=0' "$(drift "$D")"
for _o in restore.sh sec0-harden.sh log-lib.sh install-lib.sh; do
  _n="$(awk -F'\t' -v o="bin/$_o" '$2 == o { sub(/^bin\//, "", $3); print $3 }' "$T_ROOT/standards/naming/renames.tsv")"
  t_eq "$_o is the checkout's shim, -> $_n" "$(readlink "$T_ROOT/bin/$_o")" "$(readlink "$D/bin/$_o" 2>/dev/null)"
  t_exit "$_o's B6 pin is gone" 1 test -e "$D/.helm-pins/$_o.sha256"
  t_exit "$_o's old copy is in floor-install's backup" 0 test -n "$(find "$D/backups/floor-install" -path "*/bin/$_o" -type f)"
  t_exit "$_o's old pin is in floor-install's backup" 0 test -n "$(find "$D/backups/floor-install" -path "*/.helm-pins/$_o.sha256")"
done
t_eq "a runtime-only old name (fleet-glyph.sh) is a shim too" "$(readlink "$T_ROOT/bin/fleet-glyph.sh")" "$(readlink "$D/bin/fleet-glyph.sh" 2>/dev/null)"
t_exit "...whose old copy runtime-install backed up" 0 test -n "$(find "$D/backups/runtime-install" -path '*/bin/fleet-glyph.sh' -type f)"
t_exit "the shim still runs the library under its old name" 0 sh -c ". '$D/bin/log-lib.sh' && command -v log_ok"
t_has "floor-install names what it retired" "$OUT" 'old name'
t_eq "the manifest records the shim as a link" 120000 "$(awk '$3 == "bin/restore.sh" { print $2 }' "$D/.harbor-manifest" | tail -1)"

t_section "a second run changes nothing"
P1="$(ls "$D/.helm-pins")"; OUT2="$(inst "$T_ROOT/bin" "$D")"
t_eq "no old name is left to retire" 0 "$(printf '%s\n' "$OUT2" | grep -c 'old name')"
t_eq "the pin set is unchanged" "$P1" "$(ls "$D/.helm-pins")"

t_section "box-only work under an old name is kept, and B6 still says so"
E="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/edited"; box "$E"; inst "$OB" "$E" >/dev/null
printf '# a local edit\n' >> "$E/bin/restore.sh"
EOUT="$(inst "$T_ROOT/bin" "$E")"
t_exit "the edited restore.sh is still a file" 0 test -f "$E/bin/restore.sh" -a ! -L "$E/bin/restore.sh"
t_exit "...holding the edit" 0 grep -q 'a local edit' "$E/bin/restore.sh"
t_has "the installer names it" "$EOUT" 'bin/restore.sh'
t_exit "its pin stays, so B6 is not blinded to it" 0 test -f "$E/.helm-pins/restore.sh.sha256"
t_has "B6 blocks on it, the verdict it gave before this fix" "$(b6msg "$E")" 'restore.sh'
t_exit "the unedited old names were still retired" 0 test -L "$E/bin/log-lib.sh"

t_section "a box with no old names: nothing retired, nothing said"
F="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/fresh"; box "$F"; inst "$T_ROOT/bin" "$F" >/dev/null
FOUT="$(inst "$T_ROOT/bin" "$F")"
t_eq "no line about old names" 0 "$(printf '%s\n' "$FOUT" | grep -c 'old name')"
t_eq "no old-name shim is created where there was no old copy" "" "$(find "$F/bin" -type l)"
t_eq "B6 is silent" "" "$(b6msg "$F")"
t_done
