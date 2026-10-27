#!/usr/bin/env sh
# context-budget.sh --ratchet and its deploy.sh preflight wiring: the always-on core surface may only go down.
# Fixture trees only: the ratchet reads CONSTITUTION.md and tracked skills, never ~/.claude.
# RT_TOOL: run this suite against another build of the script (red proof).
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="${RT_TOOL:-$T_ROOT/bin/context-budget.sh}"
F="$T_TMP/tree"; mkdir -p "$F/bin" "$F/skills/amb" "$F/skills/hid" "$F/vendor/skills/vend"
cp "$TOOL" "$F/bin/context-budget.sh"; cp "$T_ROOT/bin/log-lib.sh" "$F/bin/log-lib.sh"
fill() { _n=0; : > "$1"; while [ "$_n" -lt "$2" ]; do printf 'c' >> "$1"; _n=$((_n+1)); done; }  # <file> <bytes>
skill() { printf -- '---\nname: %s\ndescription: %s\n%s---\n' "$2" "$3" "$4" > "$1/SKILL.md"; }  # <dir> <name> <desc> <extra>
fill "$F/CONSTITUTION.md" 1000
skill "$F/skills/amb" amb "an ambient core skill" ''
skill "$F/skills/hid" hid "a hidden skill that must cost nothing" 'disable-model-invocation: true
'
skill "$F/vendor/skills/vend" vend "a vendored ambient skill" ''
rt() { ( cd "$F" && HARBOR_RATCHET_BASELINE="${RB:-$F/CONTEXT-RATCHET.tsv}" sh bin/context-budget.sh --ratchet ) > "$T_TMP/out" 2>&1; }
want=$(( 1000 + $(printf 'description: an ambient core skill' | wc -c) + $(printf 'description: a vendored ambient skill' | wc -c) ))
base() { printf '# header\n%s\t2026-10-26\twhy\n' "$1" > "$F/CONTEXT-RATCHET.tsv"; }  # <bytes>

t_section "1 · at and under the baseline it passes"
base "$want"; rt; RC=$?
t_eq "at the baseline: exit" 0 "$RC"
t_has "...and says so" "$(cat "$T_TMP/out")" "at the $want B recorded in CONTEXT-RATCHET.tsv"
base $(( want + 500 )); rt; RC=$?
t_eq "under the baseline: exit" 0 "$RC"
t_has "...and prints the lower number to record" "$(cat "$T_TMP/out")" "set CONTEXT-RATCHET.tsv to $want"

t_section "2 · over the baseline it refuses, and names what to cut"
base $(( want - 10 )); rt; RC=$?
t_eq "over the baseline: exit" 1 "$RC"
OUT="$(cat "$T_TMP/out")"
t_has "the growth is stated" "$OUT" "(+10 B)"
t_has "the baseline file is named" "$OUT" "CONTEXT-RATCHET.tsv"
t_has "the largest contributor is named with its bytes" "$OUT" "top contributor: 1000 B  CONSTITUTION.md"
t_has "a tracked ambient skill is a contributor" "$OUT" "skill description: vend"
t_has "the fix line says how to raise it deliberately" "$OUT" "say why in the commit"
t_hasnt "a hidden skill costs nothing and is not listed" "$OUT" "skill description: hid"
skill "$F/skills/hid" hid "a hidden skill that must cost nothing" ''; rt
t_has "control: the same skill, once ambient, is listed" "$(cat "$T_TMP/out")" "skill description: hid"
skill "$F/skills/hid" hid "a hidden skill that must cost nothing" 'disable-model-invocation: true
'

t_section "3 · the number counts what the checkout controls and nothing else"
base "$want"; mkdir -p "$F/home/.claude/projects/x/memory"; fill "$F/home/.claude/projects/x/memory/MEMORY.md" 9000
( cd "$F" && HOME="$F/home" CLAUDE_CONFIG_DIR="$F/home/.claude" sh bin/context-budget.sh --ratchet ) > "$T_TMP/out" 2>&1; RC=$?
t_eq "a 9 KB memory index on the box does not move it" 0 "$RC"
fill "$F/CONSTITUTION.md" 1001; rt; RC=$?
t_eq "one byte of CONSTITUTION.md does" 1 "$RC"
fill "$F/CONSTITUTION.md" 1000

t_section "4 · a missing or unreadable baseline refuses rather than passing"
rm -f "$F/CONTEXT-RATCHET.tsv"; rt; RC=$?
t_eq "no baseline file: exit" 1 "$RC"
t_has "...and says nothing was compared" "$(cat "$T_TMP/out")" "nothing was compared"
printf '# header\nlots\t2026-10-26\twhy\n' > "$F/CONTEXT-RATCHET.tsv"; rt; RC=$?
t_eq "a non-numeric baseline: exit" 1 "$RC"

t_section "5 · deploy.sh runs it in preflight, and a refusal is a deploy FAIL"
D="$(cat "$T_ROOT/bin/deploy.sh")"
t_has "deploy.sh calls context-budget.sh --ratchet" "$D" 'context-budget.sh" --ratchet'
t_has "...and turns its failure into a preflight _bad" "$D" "_bad 'context ratchet:"
t_eq "the in-tree baseline passes today" "exit 0" "exit $(cd "$T_ROOT" && sh bin/context-budget.sh --ratchet >/dev/null 2>&1; echo $?)"
t_done
