#!/usr/bin/env sh
# skill-usage.sh (harbor#248, #518): the report states the window it measured, never claims
# "never" over a garbage-collected store, and tells ambient skills from invoked-only ones.
# Transcripts are hand-written with set mtimes, so the window is a number this file chose.
# a.jsonl's record says 08-12 while its mtime says 08-10: last-seen must read the record.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/skill-usage.sh"
TMP="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$TMP/su"
mkdir -p "$CFG/projects/-fixture" "$CFG/skills/used-ambient" "$CFG/skills/idle-ambient" "$CFG/skills/idle-hidden"
skill() { # <dir> <description> [hidden]
  { printf -- '---\nname: %s\ndescription: %s\n' "$(basename "$1")" "$2"
    [ "${3:-}" = hidden ] && printf 'disable-model-invocation: true\n'
    printf -- '---\n\n# %s\n' "$(basename "$1")"; } > "$1/SKILL.md"
}
skill "$CFG/skills/used-ambient" "a skill something actually asked for"
skill "$CFG/skills/idle-ambient" "an ambient skill nothing asked for in this window"
skill "$CFG/skills/idle-hidden"  "a hidden skill nothing asked for" hidden
# a.jsonl has fractional seconds and b.jsonl none; c.jsonl has no timestamp and must still count.
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-12T09:00:00.123Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-ambient"}}]}}' > "$CFG/projects/-fixture/a.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","message":{"content":"<command-name>/harbor-merge</command-name>"}}' > "$CFG/projects/-fixture/b.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"notimestamp-probe"}}]}}' > "$CFG/projects/-fixture/c.jsonl"
touch -t 202608100000 "$CFG/projects/-fixture/a.jsonl"
touch -t 202608160000 "$CFG/projects/-fixture/b.jsonl"
touch -t 202608120000 "$CFG/projects/-fixture/c.jsonl"
run() { CLAUDE_CONFIG_DIR="$CFG" sh "$TOOL" "$@" 2>&1; }
row() { printf '%s\n' "$1" | grep -E "^ +([0-9]+ +)?$2 "; }  # <report> <skill> — that skill's row

t_section "1 · the window is stated, and it is the measured one"
t_has "the header names the span" "$(run --unused | head -1)" "spanning 6 day(s) of transcripts"
touch -t 202608010000 "$CFG/projects/-fixture/a.jsonl"
t_has "move the fixture and the span moves" "$(run --unused | head -1)" "spanning 15 day(s) of transcripts"
touch -t 202608100000 "$CFG/projects/-fixture/a.jsonl"
OUT="$(run --unused)"
VERDICT="$(printf '%s\n' "$OUT" | grep 'installed skill(s)')"
t_has "the verdict is about the window" "$VERDICT" "had NO invocation in the window above"
t_hasnt "the verdict does not claim never" "$VERDICT" "never"
t_has "the footer says the window is a ceiling" "$OUT" "CEILING on what this source can"

t_section "2 · the report still discriminates by tier and by usage"
t_has "an unused ambient skill is AMBIENT" "$(row "$OUT" idle-ambient)" "AMBIENT"
t_has "an unused hidden skill costs nothing" "$(row "$OUT" idle-hidden)" "invoked-only (costs nothing)"
t_hasnt "a skill with a recorded Skill call is not unused" "$OUT" "used-ambient"
_want="$(awk '/^description:/{print length($0); exit}' "$CFG/skills/idle-ambient/SKILL.md")"
t_has "the ambient byte total charges only idle-ambient" "$OUT" "costing $_want B in EVERY session"
t_has "an unused ambient skill is SILENT" "$(row "$OUT" idle-ambient)" "SILENT"
t_has "an unused invoked-only skill is DORMANT" "$(row "$OUT" idle-hidden)" "DORMANT"

t_section "3 · count mode, and the typed-command shape"
OUT_C="$(run)"
t_has "count mode names the span too" "$(printf '%s\n' "$OUT_C" | head -1)" "spanning 6 day(s) of transcripts"
t_has "a typed slash command counts" "$(row "$OUT_C" harbor-merge)" "harbor-merge"

t_section "4 · last seen, and the state it implies (harbor#518)"
t_has "last seen is the record's date, not the file's mtime" "$(row "$OUT_C" used-ambient)" "2026-08-12"
t_has "a fractional-second stamp yields a state" "$(row "$OUT_C" used-ambient)" "STALE"
t_has "the newest skill is ACTIVE" "$(row "$OUT_C" harbor-merge)" "ACTIVE"
t_has "a hit with no timestamp still counts" "$(row "$OUT_C" notimestamp-probe)" "notimestamp-probe"
t_has "an invoked ambient skill carries a per-use tax" "$(row "$OUT_C" used-ambient)" "B/use"
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-15T09:00:00.123Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"used-ambient"}}]}}' > "$CFG/projects/-fixture/a.jsonl"
touch -t 202608100000 "$CFG/projects/-fixture/a.jsonl"
_moved="$(row "$(run)" used-ambient)"
t_has "re-stamp the record: the date moves" "$_moved" "2026-08-15"
t_has "and STALE becomes ACTIVE" "$_moved" "ACTIVE"

t_section "one impossible date must not age every other skill (2026-09-16)"
CFG3="$TMP/cfg-future"
mkdir -p "$CFG3/projects/-fixture" "$CFG3/skills/future-skill" "$CFG3/skills/current-skill"
for _s in future-skill current-skill; do printf -- '---\nname: %s\ndescription: d\n---\n\n# %s\n' "$_s" "$_s" > "$CFG3/skills/$_s/SKILL.md"; done
printf '%s\n' '{"type":"assistant","timestamp":"2099-01-01T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"future-skill"}}]}}' > "$CFG3/projects/-fixture/a.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-16T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"current-skill"}}]}}' > "$CFG3/projects/-fixture/b.jsonl"
touch -t 202608100000 "$CFG3/projects/-fixture/a.jsonl"; touch -t 202608160000 "$CFG3/projects/-fixture/b.jsonl"
OUT_F="$(CLAUDE_CONFIG_DIR="$CFG3" sh "$TOOL" 2>&1)"
t_has "a 2099 record leaves a current skill ACTIVE" "$(row "$OUT_F" current-skill)" "ACTIVE"
t_has "the clamp is announced" "$OUT_F" "dated later than any file in the store"

t_section "a QUOTED marker is not an invocation; typed and local_command shapes are (harbor#521)"
CFG4="$TMP/su-quoted"; mkdir -p "$CFG4/projects/-fixture" "$CFG4/skills"
M='<command-name>/NAME</command-name>'
# Quoting shapes: a tool result echo, assistant prose, an attachment, a marker mid-string.
printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","toolUseResult":{},"message":{"content":[{"type":"tool_result","content":"'"${M%NAME*}"'quoted-echo'"${M#*NAME}"'"}]}}' > "$CFG4/projects/-fixture/q1.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-08-16T09:00:00Z","message":{"content":[{"type":"text","text":"'"${M%NAME*}"'quoted-prose'"${M#*NAME}"'"}]}}' > "$CFG4/projects/-fixture/q2.jsonl"
printf '%s\n' '{"type":"attachment","timestamp":"2026-08-16T09:00:00Z","attachment":{"type":"edited_text_file","snippet":"'"${M%NAME*}"'quoted-attach'"${M#*NAME}"'"}}' > "$CFG4/projects/-fixture/q3.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","message":{"content":"see '"${M%NAME*}"'quoted-inline'"${M#*NAME}"' in the ticket"}}' > "$CFG4/projects/-fixture/q4.jsonl"
# Genuine shapes: a typed command, and the harness-written system/local_command record.
printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","message":{"content":"'"${M%NAME*}"'typed-real'"${M#*NAME}"'"}}' > "$CFG4/projects/-fixture/g1.jsonl"
printf '%s\n' '{"type":"system","subtype":"local_command","timestamp":"2026-08-16T09:00:00Z","content":"'"${M%NAME*}"'local-real'"${M#*NAME}"'"}' > "$CFG4/projects/-fixture/g2.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","message":{"content":"<command-message>msg-first</command-message>\n<command-name>/msg-first</command-name>"}}' > "$CFG4/projects/-fixture/g3.jsonl"
touch -t 202608160000 "$CFG4"/projects/-fixture/*.jsonl
OUT_Q="$(CLAUDE_CONFIG_DIR="$CFG4" sh "$TOOL" 2>&1)"
# Control: the same four names, TYPED, are counted, so their absence above is the quoting and not the names.
CFG5="$TMP/su-control"; mkdir -p "$CFG5/projects/-fixture" "$CFG5/skills"
for _q in quoted-echo quoted-prose quoted-attach quoted-inline; do
  printf '%s\n' '{"type":"user","timestamp":"2026-08-16T09:00:00Z","message":{"content":"'"${M%NAME*}$_q${M#*NAME}"'"}}' > "$CFG5/projects/-fixture/$_q.jsonl"
done
touch -t 202608160000 "$CFG5"/projects/-fixture/*.jsonl
OUT_K="$(CLAUDE_CONFIG_DIR="$CFG5" sh "$TOOL" 2>&1)"
t_has "control: typed quoted-echo is counted" "$OUT_K" "quoted-echo"
t_has "control: typed quoted-prose is counted" "$OUT_K" "quoted-prose"
t_has "control: typed quoted-attach is counted" "$OUT_K" "quoted-attach"
t_has "control: typed quoted-inline is counted" "$OUT_K" "quoted-inline"
t_hasnt "a tool-result echo of a marker is not counted" "$OUT_Q" "quoted-echo"
t_hasnt "assistant prose quoting a marker is not counted" "$OUT_Q" "quoted-prose"
t_hasnt "an attachment quoting a marker is not counted" "$OUT_Q" "quoted-attach"
t_hasnt "a marker mid-sentence in a user turn is not counted" "$OUT_Q" "quoted-inline"
t_has "a typed command still counts" "$OUT_Q" "typed-real"
t_has "a typed command led by <command-message> still counts" "$OUT_Q" "msg-first"
t_has "a system/local_command record still counts" "$OUT_Q" "local-real"

t_section "an empty store is refused with a message, not a false zero"
CFG2="$TMP/cfg-nostore"; mkdir -p "$CFG2/skills"
t_exit "a missing store" 1 env CLAUDE_CONFIG_DIR="$CFG2" sh "$TOOL" --unused
t_has "the refusal says why" "$(CLAUDE_CONFIG_DIR="$CFG2" sh "$TOOL" --unused 2>&1)" "no session store"
t_done
