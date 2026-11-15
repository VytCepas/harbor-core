#!/usr/bin/env sh
# skill-landing.test.sh (harbor#1278, P1) — a hub pack's skill lands where Claude Code reads a personal skill, <member HOME>/.claude/skills/<name>/SKILL.md,
# through the real path: the managed SessionStart hook, hub.sh sync and pack.sh --live, with CLAUDE_CONFIG_DIR unset and HOME taken from member.conf. It goes
# when the policy drops the pack. Section 2 is the red: a pack.sh whose skill row lands elsewhere is caught. Whether Claude Code then lists the skill is not
# tested here (P2, a real laptop). No GitHub: fixture.sh points the hub at a local git path, and the board stays down, which a session start tolerates.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MH="$T_TMP/member-home"; HOME="$MH"; export HOME   # the laptop is built in the member's home, as on WSL
. "$T_ROOT/tests/member/e2e/fixture.sh"
unset CLAUDE_CONFIG_DIR   # fixture.sh sets it; a laptop's hook runs without it (bin/member-managed.sh does not set it)
API=http://127.0.0.1:9    # e_seams needs an address for the board: nothing listens there
e_hub; e_policy .; e_root; e_env
SK="$MH/.claude/skills"
# deploy --member installs the core skills, so the folder Claude Code watches exists before the first session
mkdir -p "$SK/audit-claims"; printf -- '---\nname: audit-claims\ndescription: core\n---\n' > "$SK/audit-claims/SKILL.md"
ELSE="$T_TMP/elsewhere"; mkdir -p "$ELSE"
WANT="{id:\"fixture-tools\",commit:\"$E_PACK_COMMIT\"}"
start() { HOME="$ELSE" e_session start; }   # the shell's HOME is not the member's: member.conf must decide
fm() { awk -v k="$1" 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$2"; }

t_section "1 - the skill lands in the member's ~/.claude/skills, and goes when the policy drops it"
t_eq "the managed env block sets no CLAUDE_CONFIG_DIR" false "$(jq '.env | has("CLAUDE_CONFIG_DIR")' "$MFILE")"
t_eq "and neither does this shell" unset "${CLAUDE_CONFIG_DIR-unset}"
t_eq "member.conf names the member's home" "home=$MH" "$(grep '^home=' "$MR/member.conf")"
e_policy ".packs = [$WANT]"; start
t_eq "the session start exits 0" 0 "$E_RC"
t_exit "the skill is at <member HOME>/.claude/skills/fixture-skill/SKILL.md" 0 test -f "$SK/fixture-skill/SKILL.md"
t_eq "...byte for byte the hub's file at the pinned commit" "$(e_git show "$E_PACK_COMMIT:packs/fixture-tools/harbor-pack/skills/fixture-skill/SKILL.md")" "$(cat "$SK/fixture-skill/SKILL.md" 2>/dev/null)"
t_eq "nothing landed under the shell's own HOME" 0 "$(find "$ELSE" -type f | wc -l | tr -d ' ')"
t_eq "its front matter name is its folder" fixture-skill "$(fm name "$SK/fixture-skill/SKILL.md" 2>/dev/null)"
_d="$(fm description "$SK/fixture-skill/SKILL.md" 2>/dev/null)"
t_eq "its description is there and under 400 characters" yes "$([ -n "$_d" ] && [ "${#_d}" -lt 400 ] && echo yes || echo "no (${#_d})")"
t_eq "the manifest says it came from the hub" hub "$(awk -F'\t' '$1 == "# source" { print $2 }' "$MH/.claude/.harbor-packs/hub-fixture-tools.tsv" 2>/dev/null)"
start; t_exit "a second session start keeps it" 0 test -f "$SK/fixture-skill/SKILL.md"
e_policy .; start
t_exit "the policy drops the pack: the skill is gone" 1 test -e "$SK/fixture-skill"
t_exit "...and its manifest" 1 test -e "$MH/.claude/.harbor-packs/hub-fixture-tools.tsv"
t_exit "...and the core skill beside it stays" 0 test -f "$SK/audit-claims/SKILL.md"

t_section "2 - red: a pack.sh whose skill row lands elsewhere is caught"
cp "$MB/pack.sh" "$T_TMP/pack.keep"
awk '/^      skills\/\*\/\*\)/ { s = 1 } s && /printf .*"\$_r" >> "\$WORK\/plan"/ { sub(/"\$_r" >>/, "\"skills.d/${_r#skills/}\" >>"); s = 0 } { print }' "$T_TMP/pack.keep" > "$T_TMP/pack.mut"
t_eq "the mutant differs from pack.sh in one line" 1 "$(diff "$T_TMP/pack.keep" "$T_TMP/pack.mut" | grep -c '^>')"
cat "$T_TMP/pack.mut" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
e_policy ".packs = [$WANT]"; start
t_exit "the mutant ran: the skill went to skills.d/" 0 test -f "$MH/.claude/skills.d/fixture-skill/SKILL.md"
t_exit "and the check above sees no skill where Claude Code reads one" 1 test -f "$SK/fixture-skill/SKILL.md"
e_policy .; start
cat "$T_TMP/pack.keep" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
t_exit "restored, the mutant's install was taken back" 1 test -e "$MH/.claude/skills.d/fixture-skill"
t_done
