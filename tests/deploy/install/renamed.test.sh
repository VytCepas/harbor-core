#!/usr/bin/env sh
# A deploy across a rename (harbor#949): a box installed before W3 holds bin/restore.sh, bin/log-lib.sh, … and their
# B6 pins. The installers that ship the new names must leave B6, floor-verify and install-drift green with no step in
# between: the old name becomes the checkout's shim and its pin goes, both backed up. Measured on 6da7ceca: B6 blocked
# on four stale pins and install-drift read 35 old copies stale, so the deploy restored itself.
# The pre-rename box is built from HEAD alone (public CI's clone has no harbor history): this tree's install, plus a
# copy under every old name renames.tsv still shims, recorded in the manifest and pinned where the new name is, as a
# pre-rename install left them.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EMPTY='{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}'
SB="$T_ROOT/bin"
_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
b6msg() { CLAUDE_CONFIG_DIR="$1" sh "$1/bin/admission-integrity.sh" </dev/null 2>/dev/null | jq -r '.systemMessage // ""' 2>/dev/null; }
inst() { # <box> — runtime then floor, as deploy orders them; the output of both
  env -u CLAUDE_CONFIG_DIR sh "$SB/deploy-runtime-install.sh" --dir "$1" --apply 2>&1
  env -u CLAUDE_CONFIG_DIR sh "$SB/floor-install.sh" --dir "$1" --apply --with-b6 2>&1
}
drift() { sh "$SB/drift-install.sh" --dir "$1" --ref HEAD 2>&1 | sed -n 's/.*\(stale=[0-9]* modified=[0-9]*\).*/\1/p' | tail -1; }
# The old names: renames.tsv bin rows whose old path the checkout keeps as a shim.
OLDS="$(awk -F'\t' '$2 ~ /^bin\/[^\/]+$/ && $3 ~ /^bin\/[^\/]+$/ { print substr($2, 5) " " substr($3, 5) }' \
          "$T_ROOT/standards/naming/renames.tsv" | while read -r _o _n; do [ -L "$SB/$_o" ] && printf '%s %s\n' "$_o" "$_n"; done)"
old_box() { # <box> — this tree installed, then each installed new name's bytes planted under its old name
  mkdir -p "$1/bin"; printf '%s\n' "$EMPTY" > "$1/settings.json"; inst "$1" >/dev/null
  printf '%s\n' "$OLDS" | while read -r _o _n; do
    [ -n "$_o" ] && [ -f "$1/bin/$_n" ] || continue
    cp "$1/bin/$_n" "$1/bin/$_o"
    printf '%s 100755 bin/%s runtime-install -\n' "$(git hash-object --no-filters "$1/bin/$_o")" "$_o" >> "$1/.harbor-manifest"
    [ ! -f "$1/.helm-pins/$_n.sha256" ] || _sha < "$1/bin/$_o" > "$1/.helm-pins/$_o.sha256"
    printf '%s\n' "$_o"
  done
}
phys() { CDPATH= cd -P -- "$T_TMP" && printf '%s/%s' "$(pwd -P)" "$1"; }

t_section "the box before: old-name copies and pins beside this tree's install"
D="$(phys box)"; PL="$(old_box "$D")"
t_eq "the renames.tsv shims are readable (>= 30 planted), or every loop below is vacuous" yes \
  "$([ "$(printf '%s\n' "$PL" | grep -c .)" -ge 30 ] && echo yes || echo "no: $(printf '%s\n' "$PL" | grep -c .)")"
PP="$(for _o in $PL; do [ -f "$D/.helm-pins/$_o.sha256" ] && printf '%s ' "$_o"; done)"
t_has "control: restore.sh is planted and pinned" " $PP" " restore.sh "
t_has "control: B6 blocks on it, as the W3 deploy measured" "$(b6msg "$D")" 'kill-switch missing from restore.sh'

t_section "this tree's installers onto it"
OUT="$(inst "$D")"
t_eq "B6 does not block the next session" "" "$(b6msg "$D")"
FV="$(env -u CLAUDE_CONFIG_DIR sh "$SB/floor-verify.sh" --dir "$D" 2>&1 || true)"
t_has "floor-verify passes" "$(printf '%s\n' "$FV" | grep '^floor-verify: ' | tail -1)" ' 0 failed'
t_eq "install-drift reads no stale or modified copy (deploy's verify)" 'stale=0 modified=0' "$(drift "$D")"
_bad=''; _nopin=''; _nobk=''
for _o in $PL; do
  [ "$(readlink "$D/bin/$_o" 2>/dev/null)" = "$(readlink "$SB/$_o")" ] || _bad="$_bad $_o"
  [ -n "$(find "$D/backups" -path "*/bin/$_o" -type f)" ] || _nobk="$_nobk $_o"
done
for _o in $PP; do
  [ ! -e "$D/.helm-pins/$_o.sha256" ] || _nopin="$_nopin $_o"
  [ -n "$(find "$D/backups/floor-install" -path "*/.helm-pins/$_o.sha256")" ] || _nobk="$_nobk pin:$_o"
done
t_eq "every old name is the checkout's shim" "" "$_bad"
t_eq "every old pin is gone" "" "$_nopin"
t_eq "every old copy and pin is in a backup" "" "$_nobk"
t_exit "the shim still runs the library under its old name" 0 sh -c ". '$D/bin/log-lib.sh' && command -v log_ok"
t_has "floor-install names what it retired" "$OUT" 'old name'
t_eq "the manifest records the shim as a link" 120000 "$(awk '$3 == "bin/restore.sh" { print $2 }' "$D/.harbor-manifest" | tail -1)"

t_section "a second run changes nothing"
P1="$(ls "$D/.helm-pins")"; OUT2="$(inst "$D")"
t_eq "no old name is left to retire" 0 "$(printf '%s\n' "$OUT2" | grep -c 'old name')"
t_eq "the pin set is unchanged" "$P1" "$(ls "$D/.helm-pins")"

t_section "box-only work under an old name is kept, and B6 still says so"
E="$(phys edited)"; old_box "$E" >/dev/null
printf '# a local edit\n' >> "$E/bin/restore.sh"
EOUT="$(inst "$E")"
t_exit "the edited restore.sh is still a file" 0 test -f "$E/bin/restore.sh" -a ! -L "$E/bin/restore.sh"
t_exit "...holding the edit" 0 grep -q 'a local edit' "$E/bin/restore.sh"
t_has "the installer names it" "$EOUT" 'bin/restore.sh'
t_exit "its pin stays, so B6 is not blinded to it" 0 test -f "$E/.helm-pins/restore.sh.sha256"
t_has "B6 blocks on it" "$(b6msg "$E")" 'restore.sh'
t_exit "the unedited old names were still retired" 0 test -L "$E/bin/log-lib.sh"

t_section "a box with no old names: nothing retired, nothing said"
F="$(phys fresh)"; mkdir -p "$F/bin"; printf '%s\n' "$EMPTY" > "$F/settings.json"; inst "$F" >/dev/null
FOUT="$(inst "$F")"
t_eq "no line about old names" 0 "$(printf '%s\n' "$FOUT" | grep -c 'old name')"
t_eq "no old-name shim is created where there was no old copy" "" "$(find "$F/bin" -type l)"
t_eq "B6 is silent" "" "$(b6msg "$F")"
t_done
