#!/usr/bin/env sh
# integrity.test.sh (harbor#1278, F12) — member-integrity.sh hashes the managed root and managed settings by content and relative name, so a stage and the real path agree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
I="$MB/member-integrity.sh"; S="$T_TMP/managed/ClaudeCode"
printf '{"env":{"HARBOR_MEMBER_ROLE":"member"}}\n' > "$S/managed-settings.json"
pin() { sh "$I" hash > "$MR/floor.pin"; }
moved() { # <label>: after a change, check fails; then re-pin for the next case
  t_exit "$1" 1 sh "$I" check
  pin
  t_exit "CONTROL: re-pinned, $1 passes" 0 sh "$I" check
}

t_section "1 - the hash"
H="$(sh "$I" hash)"
t_eq "16 hex" 1 "$(printf '%s\n' "$H" | grep -cE '^[0123456789abcdef]{16}$')"
t_eq "stable" "$H" "$(sh "$I" hash)"
t_eq "the pin isn't in it" "$H" "$(printf x > "$MR/floor.pin"; sh "$I" hash)"
t_eq "nor core-source: IT adds it to steer the updater, which refuses a floor failing check" "$H" "$(printf 'https://example.test/core.git\n' > "$MR/core-source"; sh "$I" hash)"
rm -f "$MR/core-source"

t_section "2 - check"
rm -f "$MR/floor.pin"
t_exit "no pin" 1 sh "$I" check
: > "$MR/floor.pin"
t_exit "an empty pin" 1 sh "$I" check
pin
t_exit "a match" 0 sh "$I" check

t_section "3 - what moves it"
printf '# x\n' >> "$MB/admission-bash.sh"; moved "a changed guard"
printf 'x' > "$MB/new-file.sh"; moved "a new file"
printf 'login=mallory\n' >> "$MR/member.conf"; moved "a changed member.conf"
mv "$MR/member.conf" "$T_TMP/conf"; moved "a removed member.conf"
mv "$T_TMP/conf" "$MR/member.conf"; moved "a member.conf put back"
rm -f "$MB/new-file.sh"; moved "a removed file"
chmod 666 "$MB/hub-tier.sh"
t_exit "a world-writable file fails check" 1 sh "$I" check
chmod 644 "$MB/hub-tier.sh"; chmod 775 "$MB"
t_exit "a group-writable folder fails check" 1 sh "$I" check
chmod 755 "$MB"
t_exit "CONTROL: tightened, check passes" 0 sh "$I" check
ln -s /etc/hosts "$MB/link"; moved "a new link"
rm -f "$MB/link"; ln -s /etc/passwd "$MB/link"; moved "a re-pointed link"
printf '{"env":{}}\n' > "$S/managed-settings.json"; moved "changed managed settings"

t_section "3b - what the updater and the ledger write doesn't move it"
pin
mkdir -p "$MR/MEMORY/OBSERVABILITY/h"
printf 'x\n' > "$MR/MEMORY/OBSERVABILITY/h/guard-decisions.jsonl"; printf 'c\n' > "$MR/core.commit"; printf '2\n' > "$MR/pin.serial"; printf 'f\n' > "$MB/.core-files"
chmod 777 "$MR/MEMORY/OBSERVABILITY/h"
t_exit "the ledger, core.commit, pin.serial, .core-files" 0 sh "$I" check
mkdir -p "$S/managed-settings.d"; printf '{}\n' > "$S/managed-settings.d/10-x.json"
t_exit "another writer's drop-in" 0 sh "$I" check

t_section "3c - a stage and the real path agree"
ST="$T_TMP/stage"; mkdir -p "$ST/harbor"; cp -R "$MB" "$ST/harbor/bin"; cp "$MR/member.conf" "$ST/harbor/"
cp "$S/managed-settings.json" "$ST/settings-elsewhere.json"
_stage="$(env HARBOR_MEMBER_ROOT="$ST/harbor" HARBOR_SCOPE_MANAGED_SETTINGS="$ST/settings-elsewhere.json" sh "$ST/harbor/bin/member-integrity.sh" hash)"
t_eq "the install's call" "$(sh "$I" hash)" "$_stage"
t_eq "the root named by env, from the script elsewhere" "$(sh "$I" hash)" "$(env HARBOR_MEMBER_ROOT="$MR" HARBOR_SCOPE_MANAGED_SETTINGS="$S/managed-settings.json" sh "$ST/harbor/bin/member-integrity.sh" hash)"
chmod 644 "$ST/harbor/bin/hub-tier.sh"; chmod 755 "$MB/hub-tier.sh"
t_eq "modes are out of the hash: a stage's cp and the land's chmod differ" "$(sh "$I" hash)" "$(env HARBOR_MEMBER_ROOT="$ST/harbor" HARBOR_SCOPE_MANAGED_SETTINGS="$ST/settings-elsewhere.json" sh "$ST/harbor/bin/member-integrity.sh" hash)"
printf '# x\n' >> "$ST/harbor/bin/hub-tier.sh"
[ "$(sh "$I" hash)" != "$(env HARBOR_MEMBER_ROOT="$ST/harbor" sh "$ST/harbor/bin/member-integrity.sh" hash)" ] && t_pass || t_fail "the env root was read, not the script's"

t_section "4 - env moves nothing"
pin
t_exit "a root with no bin in it" 1 env HARBOR_MEMBER_ROOT=/nonexistent sh "$I" check
sed "s|'/mnt/c/Program Files/ClaudeCode/harbor')|'/mnt/c/Program Files/ClaudeCode/harbor'\|'$MR')|" "$I" > "$T_TMP/pinned.sh"; cp "$I" "$T_TMP/i.keep"; cp "$T_TMP/pinned.sh" "$I"
pin
t_exit "at a real root, a user env block can't aim check at a copy" 0 env HARBOR_SCOPE_MANAGED_SETTINGS="$ST/settings-elsewhere.json" HARBOR_MEMBER_ROOT="$ST/harbor" sh "$I" check
printf '{"tampered":1}\n' > "$S/managed-settings.json"
t_exit "...so a changed managed file still fails, whatever env says" 1 env HARBOR_SCOPE_MANAGED_SETTINGS="$ST/settings-elsewhere.json" sh "$I" check
cp "$T_TMP/i.keep" "$I"
t_exit "a bad verb" 2 sh "$I" nonsense
t_red admission.member-integrity
t_section "5 - a file floor.extra names must be there: a re-pinned hash can't see one lost (N3)"
printf 'u\n' > "$MB/upterm"; printf 'harbor-member-mode\nupterm\n' > "$MR/floor.extra"; pin
t_exit "CONTROL: with upterm there, check passes" 0 sh "$I" check
rm "$MB/upterm"; pin
t_exit "upterm gone, even with the pin hashed again over what is left (what the old updater did): check fails" 1 sh "$I" check
ln -s /bin/sh "$MB/upterm"; pin
t_exit "a link in its place fails too" 1 sh "$I" check
rm "$MB/upterm"; printf 'harbor-member-mode\n../x\n' > "$MR/floor.extra"; pin
t_exit "a floor.extra row that is not a plain name fails" 1 sh "$I" check
rm "$MR/floor.extra"; pin
t_exit "CONTROL: no floor.extra, nothing to look for" 0 sh "$I" check
t_done
