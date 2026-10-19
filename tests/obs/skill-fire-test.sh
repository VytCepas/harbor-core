#!/usr/bin/env sh
# skill-fire.sh (harbor#293). The case loop fed `claude -p` the case file on stdin, so the
# 2026-08-28 sweep handed every session its answer key, silently and with exit 0. A stubbed
# claude records its stdin and prompt, and these assertions read the recordings.
. "$(dirname "$0")/../lib/core.sh"; t_init
S="$T_ROOT/bin/skill-fire.sh"; TMP="$T_TMP/sf"
mkdir -p "$TMP/rec" "$HOME/.claude" "$TMP/skills"
cat > "$T_BIN/claude" <<'STUB'
#!/usr/bin/env sh
set -u
REC="${SF_REC:?}"
p=''
while [ $# -gt 0 ]; do case "$1" in -p) shift; p="$1" ;; esac; shift; done
n=$(( $(cat "$REC/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$REC/n"
cat > "$REC/stdin.$n"
printf '%s' "$p" > "$REC/prompt.$n"
sid="sess-$n"
d="${CLAUDE_CONFIG_DIR:?}/projects/stub"; mkdir -p "$d"
: > "$d/$sid.jsonl"
for f in $(printf '%s' "$p" | tr ' ' '\n' | sed -n 's/^FIRE://p'); do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}\n' "$f" >> "$d/$sid.jsonl"
done
for f in $(printf '%s' "$p" | tr ' ' '\n' | sed -n 's/^READ://p'); do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat ~/.claude/skills/%s/SKILL.md"}}]}}\n' "$f" >> "$d/$sid.jsonl"
done
printf '{"session_id":"%s"}\n' "$sid"
STUB
chmod +x "$T_BIN/claude"
for n in red-team evals; do
  mkdir -p "$TMP/skills/$n"
  printf -- '---\nname: %s\ndisable-model-invocation: true\n---\nbody\n' "$n" > "$TMP/skills/$n/SKILL.md"
done
CASES="$TMP/cases.tsv"
{ printf '# a comment row that must never reach a prompt\n'
  printf 'hit\tred-team\tplease FIRE:red-team now\n'
  printf 'missed\tevals\tthis one fires FIRE:red-team instead\n'
  printf 'opencase\t?\tanything goes FIRE:evals here\n'
  printf 'control\tNONE\tstay quiet please\n'
} > "$CASES"
sf() { _c="$1"; _cfg="$2"; shift 2; SF_REC="$TMP/rec" CLAUDE_CONFIG_DIR="$_cfg" sh "$S" --cases "$_c" --skills "$TMP/skills" "$@"; }
row() { printf '%s\n' "$1" | grep "^ *$2 "; }  # <report> <case id> — that case's row
score() { row "$1" "$2" | awk '{ print $NF }'; }  # its last field: "invoked" contains "ok"

t_section "a sweep with one deliberate MISS runs to the end"
OUT="$(sf "$CASES" "$TMP/cfg" --apply 2>"$TMP/err")"; rc=$?
t_eq "exit 1, for the fixture's one MISS" 1 "$rc"
t_has "the summary line" "$OUT" "roster of 2 — "

t_section "1 · every child received an empty stdin (the regression itself)"
leak=0; n=0
for f in "$TMP"/rec/stdin.*; do [ -f "$f" ] || continue; n=$((n + 1)); [ -s "$f" ] && leak=$((leak + 1)); done
t_eq "four sessions ran" 4 "$n"
t_eq "no session received the case file on stdin" 0 "$leak"

t_section "2 · the prompt is exactly the third field"
t_eq "prompt.1, byte for byte" 'please FIRE:red-team now' "$(cat "$TMP/rec/prompt.1" 2>/dev/null)"

t_section "3 · no comment row ever became a case"
t_eq "no fifth session" no "$([ -f "$TMP/rec/prompt.5" ] && echo yes || echo no)"

t_section "4 · the three expectation kinds each score"
t_eq "named and matched is ok" ok "$(score "$OUT" hit)"
t_eq "named and unmatched is MISS" MISS "$(score "$OUT" missed)"
t_eq "? is open" open "$(score "$OUT" opencase)"
t_eq "a silent control is ok" ok "$(score "$OUT" control)"

t_section "5 · a control that fires is a FALSE-FIRE"
C2="$TMP/cases2.tsv"; printf 'control\tNONE\tthis one FIRE:evals talks\n' > "$C2"
t_eq "a firing control" FALSE-FIRE "$(score "$(sf "$C2" "$TMP/cfg2" --apply 2>/dev/null)" control)"

t_section "5b · a SKILL.md read counts as reaching the skill"
C4="$TMP/cases4.tsv"
{ printf 'byread\tred-team\tconsult READ:red-team please\n'; printf 'control\tNONE\tstay quiet\n'; } > "$C4"
O4="$(sf "$C4" "$TMP/cfg5" --apply 2>/dev/null)"
t_has "the read column names the skill" "$(row "$O4" byread)" "read=red-team"
t_has "a read is not an invocation" "$(row "$O4" byread)" "invoked=-"
t_eq "reading the skill satisfies the expectation" ok "$(score "$O4" byread)"
C5="$TMP/cases5.tsv"; printf 'control\tNONE\tsneaky READ:evals here\n' > "$C5"
t_eq "a control that read a SKILL.md is not silent" FALSE-FIRE "$(score "$(sf "$C5" "$TMP/cfg6" --apply 2>/dev/null)" control)"

t_section "6 · a cases file with no control is refused"
C3="$TMP/cases3.tsv"; printf 'only\t?\tno control here\n' > "$C3"
t_exit "no NONE case" 1 sf "$C3" "$TMP/cfg3" --apply
t_has "the refusal names the missing control" "$(sf "$C3" "$TMP/cfg3" --apply 2>&1)" "no NONE case"

t_section "7 · the live gate (lint D2), both directions"
LIVE_REFUSAL='refusing the live config dir'
t_exit "the live dir without --live" 1 sf "$CASES" "$HOME/.claude" --apply
t_has "the live dir is refused by the gate" "$(sf "$CASES" "$HOME/.claude" --apply 2>&1)" "$LIVE_REFUSAL"
# This fixture exits 1 for its MISS either way, so the message is the discriminator.
t_hasnt "a non-live dir is not refused" "$(sf "$CASES" "$TMP/cfg4" --apply 2>&1)" "$LIVE_REFUSAL"

t_section "8 · the hide flag is stripped in the copy and never at the source"
t_eq "the source keeps its hide flag" 1 "$(grep -c '^disable-model-invocation: true$' "$TMP/skills/red-team/SKILL.md")"
t_done
