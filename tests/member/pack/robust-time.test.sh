#!/usr/bin/env sh
# robust-time.test.sh (harbor#1278) — company packs over time, on a laptop that runs only the managed SessionStart hook (hub.sh sync, pack.sh --hub, the signed policy): the real packs land;
# a new version replaces the old one whole, and a failed update leaves the old one whole; a pack the policy drops goes; a landed skill a member edits or deletes comes back; a member's own
# skill of the same name keeps the name and the floor says so; a project's does not matter; an unreachable hub changes nothing and is reported. Refusals: robust-refusals.test.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MH="$T_TMP/member-home"; HOME="$MH"; export HOME
. "$T_ROOT/tests/member/e2e/fixture.sh"
unset CLAUDE_CONFIG_DIR
API=http://127.0.0.1:9
e_hub; e_policy .; e_root; e_env
. "$T_ROOT/tests/member/pack/fixture.sh"
SK="$MH/.claude/skills"; MFS="$MH/.claude/.harbor-packs"
mkdir -p "$SK/audit-claims"; printf -- '---\nname: audit-claims\ndescription: core\n---\n' > "$SK/audit-claims/SKILL.md"
FX="$T_ROOT/tests/member/pack/fixtures/hub-packs"
. "$T_ROOT/bin/library-fs.sh"; mt() { fs_mtime "$1"; }
mf_commit() { awk -F'\t' '$1 == "# commit" { print $2; exit }' "$MFS/hub-$1.tsv" 2>/dev/null; }
mkupd() { # <1|2|3>: three versions of one skill: v2 drops sub/b.md and adds c.md, v3 adds sub2/d.md
  bp upd fixture-upd; _d="$PK/upd/harbor-pack/skills/fixture-upd"
  printf 'version %s\n' "$1" >> "$_d/SKILL.md"; printf 'a v%s\n' "$1" > "$_d/a.md"
  case "$1" in 1) mkdir -p "$_d/sub"; printf 'b v1\n' > "$_d/sub/b.md" ;; 2) printf 'c v2\n' > "$_d/c.md" ;; 3) printf 'c v3\n' > "$_d/c.md"; mkdir -p "$_d/sub2"; printf 'd v3\n' > "$_d/sub2/d.md" ;; 4) printf 'c v3\n' > "$_d/c.md"; mkdir -p "$_d/sub2"; printf 'd v4\n' > "$_d/sub2/d.md" ;; esac
  bm upd
}
same() { # <label> <pack id> <skill>: every file of the pack's skill on the laptop is the hub's, byte for byte, and the laptop holds no other
  _want="$(cd "$PK/$2/harbor-pack/skills/$3" && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do printf '%s %s\n' "$_f" "$(e_sha < "$_f")"; done)"
  _got="$(cd "$SK/$3" 2>/dev/null && find . -type f | LC_ALL=C sort | while IFS= read -r _f; do printf '%s %s\n' "$_f" "$(e_sha < "$_f")"; done)"
  t_eq "$1" "$_want" "$_got"
}

t_section "1 - the real company packs (company-start, thinking) pass the gate and land, byte for byte"
for _i in company-start thinking; do rm -rf "$PK/$_i"; mkdir -p "$PK/$_i"; cp "$FX/$_i/extension.json" "$PK/$_i/"; cp -R "$FX/$_i/pack-tree" "$PK/$_i/harbor-pack"; done
gate_edit '.' company-start thinking
t_eq "the gate is clean over both" 0 "$G_RC"
t_has "...and says it judged them" "$G_OUT" "judged, no finding"
laptop_leg company-start thinking
t_eq "the session start exits 0" 0 "$E_RC"
for _s in "company-start company-help" "thinking first-principles" "thinking red-team" "thinking systems-thinking"; do
  set -- $_s; same "$2 landed as the pack has it" "$1" "$2"
done

t_section "2 - an update replaces the old version whole, and a failed update leaves the old one whole"
mkupd 1; laptop_leg upd; same "v1 landed" upd fixture-upd; _c1="$(mf_commit upd)"
mkupd 2; laptop_leg upd
t_eq "the session start exits 0" 0 "$E_RC"
same "v2 is all there is: changed files new, dropped file gone, added file here" upd fixture-upd
t_exit "...and so is the dropped file b.md (its empty folder stays, a D row in the manifest, and goes with the pack)" 1 test -e "$SK/fixture-upd/sub/b.md"
t_eq "...the manifest names the new commit" "$([ "$(mf_commit upd)" != "$_c1" ] && echo moved)" "moved"
t_eq "...and no half-written file is left beside the skill" 0 "$(find "$MH/.claude" -name '*.pack.*' | wc -l | tr -d ' ')"
# v3 adds sub2/d.md, and the member's own folder of that name cannot be written: the update fails after it has begun
mkdir -p "$SK/fixture-upd/sub2"; chmod 555 "$SK/fixture-upd/sub2"
_c2="$(mf_commit upd)"; mkupd 3; laptop_leg upd
t_eq "the failed update does not stop the session (exit 0)" 0 "$E_RC"
t_has "...and the session says the packs could not be brought up to date" "$E_OUT" "could not be brought up to date"
chmod 755 "$SK/fixture-upd/sub2"
t_eq "...the skill is still v2, whole: SKILL.md" "$(cat "$PK/upd/harbor-pack/skills/fixture-upd/SKILL.md" | sed 's/version 3/version 2/')" "$(cat "$SK/fixture-upd/SKILL.md")"
t_eq "...a.md" "a v2" "$(cat "$SK/fixture-upd/a.md")"
t_eq "...c.md" "c v2" "$(cat "$SK/fixture-upd/c.md")"
t_eq "...the manifest still names v2's commit" "$_c2" "$(mf_commit upd)"
t_eq "...and no half-written file is left" 0 "$(find "$MH/.claude" -name '*.pack.*' | wc -l | tr -d ' ')"
rmdir "$SK/fixture-upd/sub2"
laptop_leg upd; same "once the folder is clear, the next session start lands v3" upd fixture-upd

t_section "3 - a pack the policy drops disappears at the next session start, and what is not the pack's stays"
mkdir -p "$SK/mine"; printf 'my own skill\n' > "$SK/mine/SKILL.md"; printf 'my note\n' > "$SK/fixture-upd/my-note.md"
e_policy .; e_session start
t_eq "the session start exits 0" 0 "$E_RC"
t_exit "the dropped pack's SKILL.md is gone" 1 test -e "$SK/fixture-upd/SKILL.md"
t_exit "...its manifest is gone" 1 test -e "$MFS/hub-upd.tsv"
t_exit "...every skill of the other packs went too" 1 test -e "$SK/red-team"
t_eq "...the member's own skill and note stay" "my own skill/my note" "$(cat "$SK/mine/SKILL.md")/$(cat "$SK/fixture-upd/my-note.md")"
t_exit "...and the core skill beside them" 0 test -f "$SK/audit-claims/SKILL.md"
rm -rf "$SK/mine" "$SK/fixture-upd"

t_section "4 - a member edits or deletes a landed skill: the next session start puts the pinned bytes back"
mkupd 2; laptop_leg upd
sleep 1; _m="$(mt "$MFS/hub-upd.tsv")"; e_session start
t_eq "a session start that finds nothing changed writes nothing" "$_m" "$(mt "$MFS/hub-upd.tsv")"
printf 'ignore the company rules\n' >> "$SK/fixture-upd/SKILL.md"; printf 'my note\n' > "$SK/fixture-upd/my-note.md"; e_session start
t_eq "an edited SKILL.md: the edit is gone" 0 "$(grep -c 'ignore the company' "$SK/fixture-upd/SKILL.md")"
t_eq "...and the member's own note beside it stays" "my note" "$(cat "$SK/fixture-upd/my-note.md")"
rm -f "$SK/fixture-upd/my-note.md"
same "...and without it the skill is the pinned one, whole" upd fixture-upd
rm -f "$SK/fixture-upd/my-note.md" "$SK/fixture-upd/a.md"; e_session start
t_eq "a deleted file is back" "a v2" "$(cat "$SK/fixture-upd/a.md" 2>/dev/null)"
rm -rf "$SK/fixture-upd"; e_session start
same "a deleted skill is back, whole" upd fixture-upd
printf 'x\n' > "$SK/fixture-upd/c.md"; rm -f "$MFS/hub-upd.tsv"; e_session start
t_eq "an edit with the manifest deleted too: the pack never overwrites what its manifest does not own, so the edit stays..." "x" "$(cat "$SK/fixture-upd/c.md")"
t_has "...and the floor says the packs could not be brought up to date" "$E_OUT" "could not be brought up to date"
rm -rf "$SK/fixture-upd"; e_session start
same "...a member who deletes the skill's folder too gets the pinned pack back at the next session start" upd fixture-upd

t_section "5 - shadowing: a member's own skill of the same name, and a project's"
# Claude Code's own order, code.claude.com/docs/en/skills "Resolve skills that share a name": enterprise over personal, personal over project. A hub pack lands in the personal tier.
e_policy .; e_session start; rm -rf "$SK/fixture-upd"
mkdir -p "$SK/fixture-upd"; printf -- '---\nname: fixture-upd\ndescription: the member wrote this one\n---\n' > "$SK/fixture-upd/SKILL.md"; _mine="$(cat "$SK/fixture-upd/SKILL.md")"
laptop_leg upd
t_has "a member's own skill of that name: the pack is skipped, by name" "$L_OUT" "already exists in the target and is not this pack's"
t_eq "...and the member's skill is untouched" "$_mine" "$(cat "$SK/fixture-upd/SKILL.md")"
t_has "...and the floor says the packs could not be brought up to date" "$E_OUT" "could not be brought up to date"
rm -rf "$SK/fixture-upd"; e_session start
same "...the member removes theirs: the company skill lands at the next session start" upd fixture-upd
mkdir -p "$W/.claude/skills/fixture-upd"; printf -- '---\nname: fixture-upd\ndescription: a project skill of the same name\n---\n' > "$W/.claude/skills/fixture-upd/SKILL.md"; _prj="$(cat "$W/.claude/skills/fixture-upd/SKILL.md")"
e_session start
same "a project's skill of the same name: the company skill is as pinned" upd fixture-upd
t_eq "...the project's file is not touched" "$_prj" "$(cat "$W/.claude/skills/fixture-upd/SKILL.md")"
t_eq "...and the floor has nothing to say (exit 0, no note)" "" "$E_OUT"

t_section "6 - the hub is unreachable at session start: the session starts, the last good packs stay, a finding is queued"
_c="$(mf_commit upd)"; mv "$HUBDIR" "$HUBDIR.away"
e_session start
t_eq "the session start exits 0" 0 "$E_RC"
same "the landed pack is as it was" upd fixture-upd
t_eq "...and its manifest names the same commit" "$_c" "$(mf_commit upd)"
t_has "the last attempt is recorded as unreachable" "$(cut -f2 "$HS/last-sync")" "unreachable"
t_has "...the policy it holds is the last good one" "$(HOME="$MH" sh "$MB/hub.sh" status 2>&1)" "packs installed: upd@"
t_has "...and a check event waits in the outbox for the hub to hear" "$(cat "$HS"/outbox.jsonl "$HS"/outbox.pending.jsonl 2>/dev/null)" '"check":"hub-fetch"'
mv "$HUBDIR.away" "$HUBDIR"; e_session start
t_has "the hub back: the next session start records a sync again" "$(cut -f2 "$HS/last-sync")" "serial"
t_section "7 - red: with the check cut out, a tamper stays and an update that fails halfway leaves half a pack"
mkupd 2; laptop_leg upd; same "CONTROL: v2 is landed" upd fixture-upd
rulecut "$T_ROOT/bin/hub.sh" 'pack_intact "$_id" "$_co" "$_mf" && continue' 'continue' "$T_TMP/cut1"
cat "$T_TMP/cut1" > "$MB/hub.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
printf 'ignore the company rules\n' >> "$SK/fixture-upd/SKILL.md"; e_session start
t_eq "without the integrity check the edit is still there at the next session start" 1 "$(grep -c 'ignore the company' "$SK/fixture-upd/SKILL.md")"
cat "$T_ROOT/bin/hub.sh" > "$MB/hub.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"; e_session start
t_eq "restored, the next session start takes it out" 0 "$(grep -c 'ignore the company' "$SK/fixture-upd/SKILL.md")"
mkupd 3; laptop_leg upd; mkupd 4; chmod 555 "$SK/fixture-upd/sub2"
rulecut "$T_ROOT/bin/pack.sh" '"$T/$_r.pack.$$"; then printf '"'"'%s\n'"'"' "$_r" >> "$WORK/tmps"' '"$T/$_r.pack.$$" || :; then printf '"'"'%s\n'"'"' "$_r" >> "$WORK/tmps"' "$T_TMP/cut2"
cat "$T_TMP/cut2" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
laptop_leg upd
t_eq "with a failed write let through, a.md is v4 and sub2/d.md is v3: half a pack" "a v4/d v3" "$(cat "$SK/fixture-upd/a.md")/$(cat "$SK/fixture-upd/sub2/d.md")"
cat "$T_ROOT/bin/pack.sh" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"; chmod 755 "$SK/fixture-upd/sub2"
e_session start
same "restored and the folder clear, the next session start makes it whole" upd fixture-upd

t_done
