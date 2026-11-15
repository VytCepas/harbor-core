#!/usr/bin/env sh
# Hub context rules on a member laptop (harbor#1278): a company pack carries pure-note rules, the signed hub decides which are live, and the member engine reads them only from
# the hub's delivered folder (a state folder the agent cannot write), never from the pack's install in ~/.claude. Three cases, each seen red by a mutant of the code that holds it:
# 1 a hub note fires; 2 a hub rule with run: or spoke: is refused at the gate, at pack time, at delivery and at load; 3 an unlisted, tampered or unsigned hub rule is silent.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MH="$T_TMP/member-home"; HOME="$MH"; export HOME
. "$T_ROOT/tests/member/e2e/fixture.sh"
unset CLAUDE_CONFIG_DIR
API=http://127.0.0.1:9
e_hub; e_policy .; e_root; e_env; e_token
. "$T_ROOT/tests/member/pack/fixture.sh"
RD="$HS/rules"; MARK="$T_TMP/marker"

# rp <id>: a rules pack with one pure note; rule <id> <file> <front-matter lines> <body>: a rule file in it; bm regenerates its manifest (provides: skill, as the fixture has it)
rp() {
  rm -rf "$PK/$1"; mkdir -p "$PK/$1/harbor-pack/context-rules/user"
  printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "a hub rules fixture"\n' "$1" > "$PK/$1/harbor-pack/pack.toml"
  rule "$1" note 'event: UserPromptSubmit
when: always
once: never' 'HUB-NOTE use the company warehouse connector for data questions.'
}
rule() { printf -- '---\n%s\n---\n\n%s\n' "$3" "$4" > "$PK/$1/harbor-pack/context-rules/user/$2.md"; }
bmr() { bm "$1"; jq '.provides = ["rule"]' "$PK/$1/extension.json" > "$PK/$1/e.new" && mv "$PK/$1/e.new" "$PK/$1/extension.json"; }
# fire <event> <payload>: the engine's own entry of the managed settings for that event, as Claude Code runs it; F_OUT is its stdout
fire() {
  _cmd="$(jq -r --arg e "$1" '[.hooks[$e][]?.hooks[].command | select(contains("injection-rule.sh"))][0] // empty' "$MFILE")"
  [ -n "$_cmd" ] || { F_OUT=''; return 0; }
  printf '%s' "$2" > "$T_TMP/fire.in"
  F_OUT="$(cd "$W" && /bin/sh -c "$_cmd" < "$T_TMP/fire.in" 2>/dev/null || true)"
}
UPS='{"session_id":"hub-s","hook_event_name":"UserPromptSubmit","prompt":"how many sessions did we have last week"}'
fresh() { rm -rf "$HOME/.local/state/harbor/inject" "$CLAUDE_CONFIG_DIR/state" "$MH/.claude/state"; }
mutant() { # <file> <from> <to> <name>: a copy of the root's script with one rule cut, pinned again, as the root would be installed
  rulecut "$T_ROOT/$1" "$2" "$3" "$T_TMP/cut.$4"; cat "$T_TMP/cut.$4" > "$MB/${1##*/}"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
}
restore() { cat "$T_ROOT/$1" > "$MB/${1##*/}"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"; }

t_section "1 - a hub note fires"
rp r1; bmr r1; laptop_leg r1
t_eq "the signed policy pins the pack: its note is delivered into the hub's state" yes "$([ -f "$RD/r1/note.md" ] && echo yes || echo no)"
fresh; fire UserPromptSubmit "$UPS"
t_has "the engine speaks it at a prompt, stamped with the rule id" "$F_OUT" 'HUB-NOTE use the company warehouse connector'
t_has "...as an additionalContext of that event" "$F_OUT" '"hookEventName":"UserPromptSubmit"'
t_eq "the pack's own install in ~/.claude is not where the engine reads: a pure note placed there by hand is silent" 0 "$(
  mkdir -p "$MH/.claude/context-rules/user"; printf -- '---\nevent: UserPromptSubmit\nwhen: always\nonce: never\n---\nHAND-PLACED\n' > "$MH/.claude/context-rules/user/hand.md"
  fresh; fire UserPromptSubmit "$UPS"; printf '%s' "$F_OUT" | grep -c HAND-PLACED)"
rm -f "$MH/.claude/context-rules/user/hand.md"

t_section "2 - a hub rule that runs something is refused, four times over"
rp r2; rule r2 runs 'event: UserPromptSubmit
when: always
once: never
run: x.sh' 'RUN-NOTE'; printf 'touch "%s"\necho RAN\n' "$MARK" > "$PK/r2/harbor-pack/context-rules/user/x.sh"
rule r2 spokes 'event: UserPromptSubmit
when: always
once: never
spoke: x.sh' 'SPOKE-NOTE'; bmr r2
gate_leg r2
t_eq "the hub gate refuses the pack" 1 "$G_RC"
t_has "...because every laptop would skip it, for the rule's script" "$G_OUT" 'run: or spoke:'
laptop_leg r2
t_has "pack.sh refuses it on a laptop too, with no gate in front" "$L_OUT" 'run: or spoke:'
t_exit "...and nothing of it landed in ~/.claude" 1 test -e "$MH/.claude/context-rules/user/pack-r2--runs.md"
t_eq "hub.sh delivers none of its rules (the pack is skipped, and each rule is checked again at delivery)" 0 "$(find "$RD" -type f 2>/dev/null | wc -l | tr -d ' ')"
# the engine's own refusal, with the delivery step out of the way: files placed in the delivered folder as a bypass would place them
mkdir -p "$RD/bypass"; cp "$PK/r2/harbor-pack/context-rules/user/runs.md" "$PK/r2/harbor-pack/context-rules/user/spokes.md" "$PK/r2/harbor-pack/context-rules/user/x.sh" "$RD/bypass/"
rm -f "$MARK"; fresh; fire UserPromptSubmit "$UPS"
t_eq "the engine refuses a run: or spoke: rule at load: no note, no script" "0 no" "$(printf '%s' "$F_OUT" | grep -c 'RUN-NOTE\|SPOKE-NOTE') $([ -f "$MARK" ] && echo yes || echo no)"
rm -rf "$RD/bypass"

t_section "3 - an unlisted, tampered or unsigned hub rule is silent"
rp r3; rule r3 extra 'event: UserPromptSubmit
when: always
once: never' 'UNLISTED-NOTE'; bmr r3
jq '.files |= map(select(.path | test("extra") | not))' "$PK/r3/extension.json" > "$PK/r3/e.new" && mv "$PK/r3/e.new" "$PK/r3/extension.json"
laptop_leg r3
t_has "a rule file the manifest does not list: the pack is skipped (no sha256 vouches for it)" "$L_OUT" 'does not list it'
fresh; fire UserPromptSubmit "$UPS"
t_eq "...and its note is silent" 0 "$(printf '%s' "$F_OUT" | grep -c 'UNLISTED-NOTE\|HUB-NOTE')"
# a pack the policy does not pin
rp r4; bmr r4; cp -R "$PK/r4" "$HUBDIR/packs/"; e_git add -Af; e_git commit -qm 'r4 unpinned'; e_policy '.packs = []'; e_session start
t_exit "a pack the signed policy does not pin delivers nothing" 1 test -e "$RD/r4"
# unlisted at delivery: the manifest lists the file, but the bytes at the pin differ (the manifest is what the hub vouched for)
rp r5; bmr r5; printf 'TAMPERED-NOTE\n' >> "$PK/r5/harbor-pack/context-rules/user/note.md"
laptop_leg r5
fresh; fire UserPromptSubmit "$UPS"
t_eq "a rule whose bytes differ from the manifest's sha256 is silent" 0 "$(printf '%s' "$F_OUT" | grep -c 'TAMPERED-NOTE')"
t_exit "...and not delivered" 1 test -e "$RD/r5/note.md"
# unsigned: a policy edited after signing pins a pack no signature covers
rp r6; bmr r6; cp -R "$PK/r6" "$HUBDIR/packs/"; e_git add -Af; e_git commit -qm 'r6'
e_policy '.'; jq --arg c "$(e_git rev-parse HEAD)" '.packs = [{id:"r6",commit:$c}]' "$HUBDIR/policy.json" > "$T_TMP/p.new" && cat "$T_TMP/p.new" > "$HUBDIR/policy.json"
e_git add -A; e_git commit -qm 'policy edited after signing'; e_session start
t_exit "a policy whose signature does not cover its pins delivers no rule" 1 test -e "$RD/r6"
fresh; fire UserPromptSubmit "$UPS"
t_eq "...and the engine says nothing" 0 "$(printf '%s' "$F_OUT" | grep -c 'HUB-NOTE')"

t_section "4 - red: each rule cut out of the code that holds it lets its case through"
# 4a delivery's run: check cut, and the engine's cut too: the bypass runs
rp r7; rule r7 runs 'event: UserPromptSubmit
when: always
once: never
run: x.sh' 'RUN-NOTE'; printf 'touch "%s"\necho RAN\n' "$MARK" > "$PK/r7/harbor-pack/context-rules/user/x.sh"; bmr r7
mkdir -p "$RD/bypass"; cp "$PK/r7/harbor-pack/context-rules/user/runs.md" "$PK/r7/harbor-pack/context-rules/user/x.sh" "$RD/bypass/"
# the engine refuses twice (its fast exit and its load check), so both are cut
rulecut "$T_ROOT/hooks/injection-rule/injection-rule.sh" 'if [ -n "$_mrun" ] || [ -n "$FMV" ]; then' 'if false; then' "$T_TMP/cut.e1"
rulecut "$T_TMP/cut.e1" 'else if ($0 ~ /^(run|spoke):/) r = 1' 'else if (0) r = 1' "$T_TMP/cut.e2"
cat "$T_TMP/cut.e2" > "$MB/injection-rule.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
rm -f "$MARK"; fresh; fire UserPromptSubmit "$UPS"
t_eq "mutant: with the engine's load check cut, a run: rule in the delivered folder runs its script" yes "$([ -f "$MARK" ] && echo yes || echo no)"
restore hooks/injection-rule/injection-rule.sh; rm -rf "$RD/bypass"
# 4b the manifest hash check cut
mutant bin/hub.sh '[ "$(hub_sha256 < "$_tmp")" = "$_rh" ] &&' ':' hub-sha
rulecut "$T_ROOT/bin/pack.sh" '= "$_eh" ] || refuse "extension.json lists' '= "$_eh" ] || : "extension.json lists' "$T_TMP/cut.pack1"; cat "$T_TMP/cut.pack1" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
rp r5; bmr r5; printf 'TAMPERED-NOTE\n' >> "$PK/r5/harbor-pack/context-rules/user/note.md"
[ -n "$BASE" ] || BASE="$(e_git rev-parse HEAD)"
rm -rf "$HUBDIR/packs/r5"; cp -R "$PK/r5" "$HUBDIR/packs/"; e_git add -Af; e_git commit -qm 'r5 again' || :
e_policy ".packs = [{id:\"r5\",commit:\"$(e_git rev-parse HEAD)\"}]"; e_session start
t_exit "mutant: with the manifest's byte checks cut (pack.sh's and delivery's), the tampered rule is delivered" 0 test -f "$RD/r5/note.md"
restore bin/hub.sh; restore bin/pack.sh
# 4c delivery's run: check cut, and pack.sh's refusal cut too: the pack's run: rule is delivered
mutant bin/hub.sh '! tr -d '"'"'\r'"'"' < "$_tmp" | awk '"'"'/^[ \t]*(run|spoke)[ \t]*:/ { f = 1 } END { exit !f }'"'"'' ':' hub-run
rulecut "$T_ROOT/bin/pack.sh" '(run|spoke)[ \t]*:/ { f = 1 } END { exit f }' '(never)[ \t]*:/ { f = 1 } END { exit f }' "$T_TMP/cut.pack"; cat "$T_TMP/cut.pack" > "$MB/pack.sh"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
printf 'run\nspoke\n' >> "$MB/pack-frontmatter-keys.txt"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"   # the key allowlist is a third refusal: cut too
rp r2; rule r2 runs 'event: UserPromptSubmit
when: always
once: never
run: x.sh' 'RUN-NOTE'; bmr r2
laptop_leg r2
t_exit "mutant: with pack.sh's and hub.sh's checks cut, the run: rule is delivered" 0 test -f "$RD/r2/runs.md"
printf 'touch "%s"\necho RAN\n' "$MARK" > "$RD/r2/x.sh"   # a script beside it, as a pack that could carry one would
rm -f "$MARK"; fresh; fire UserPromptSubmit "$UPS"
t_eq "...and only the engine's own load check keeps its script from running" no "$([ -f "$MARK" ] && echo yes || echo no)"
restore bin/hub.sh; restore bin/pack.sh; cat "$T_ROOT/contracts/pack-frontmatter-keys.txt" > "$MB/pack-frontmatter-keys.txt"; sh "$MB/member-integrity.sh" hash > "$MR/floor.pin"
# 4d the delivery step cut: the pinned pack's note never fires
mutant bin/hub.sh '  sync_rules "$_pol" || _src=1' ':' hub-nosync
rm -rf "$RD"; rp r1; bmr r1; laptop_leg r1
fresh; fire UserPromptSubmit "$UPS"
t_eq "mutant: with delivery cut out of the sync, the pinned note is silent" 0 "$(printf '%s' "$F_OUT" | grep -c 'HUB-NOTE')"
restore bin/hub.sh
laptop_leg r1; fresh; fire UserPromptSubmit "$UPS"
t_has "restored, the note fires again" "$F_OUT" 'HUB-NOTE'
t_done
