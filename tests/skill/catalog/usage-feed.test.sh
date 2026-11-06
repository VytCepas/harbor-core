#!/usr/bin/env sh
# bin/skill-catalog.sh usage --json (harbor#1480): the skills feed of the Harbor pane. Tier and the skill list are the
# installed book's own; uses and last_used are counted at read time from fixture transcripts under a throwaway config dir.
# Counted: a Skill tool_use naming the skill, or a user message STARTING with <command-name>/<skill>. Not counted: a quote
# mid-message, a request echo, a record outside the window, a duplicate of a record already counted. No transcript text and no
# file may come out of a run: a sentinel rides in every fixture line, and the tree is compared before and after.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$T_TMP/root"; mkdir -p "$R/bin" "$R/skills/alpha" "$R/vendor/skills/vend" "$R/contracts"
cp "$T_ROOT/bin/skill-catalog.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$R/bin/"
cp "$T_ROOT/contracts/roots.tsv" "$T_ROOT/contracts/catalog-non-tools.tsv" "$R/contracts/"
CFG="$T_TMP/ucfg"; mkdir -p "$CFG/skills/alpha" "$CFG/skills/vend" "$CFG/skills/boxonly" "$CFG/skills/packed" "$CFG/skills/longdesc" "$CFG/.harbor-packs" "$CFG/projects/-fx" "$CFG/projects/-fy"
sk() { printf -- '---\nname: %s\ndescription: "%s"\n%s---\n' "$1" "$2" "${3:+disable-model-invocation: true
}" > "$CFG/skills/$1/SKILL.md"; }
sk alpha "Alpha does the first thing. USE WHEN alpha work." hidden; cp "$CFG/skills/alpha/SKILL.md" "$R/skills/alpha/"
sk vend "Vendored one. USE WHEN vend work."; cp "$CFG/skills/vend/SKILL.md" "$R/vendor/skills/vend/"
sk boxonly "Box only, no period at the end"
sk packed "Packed. USE WHEN packed work."
printf 'pack\tskills/packed/SKILL.md\n' > "$CFG/.harbor-packs/p.tsv"
LONG="A description that runs on and on without a full stop so that it must be cut at one hundred characters, no more than that"
sk longdesc "$LONG"

now_minus() { jq -n -r --argjson s "$1" '(now - $s) | todate'; }   # seconds ago, as an ISO stamp
D1="$(now_minus 86400)"; D2="$(now_minus 172800)"; D40="$(now_minus 3456000)"
S='SENTINEL-TRANSCRIPT-TEXT'
tu() { printf '{"type":"assistant","uuid":"u-%s","timestamp":"%s","message":{"content":[{"type":"text","text":"%s"},{"type":"tool_use","id":"%s","name":"Skill","input":{"skill":"%s"}}]}}\n' "$1" "$2" "$S" "$1" "$3"; }
cmd() { printf '{"type":"user","uuid":"%s","timestamp":"%s","message":{"role":"user","content":"<command-name>/%s</command-name>\\n<command-args>%s</command-args>"}}\n' "$1" "$2" "$3" "$S"; }
{ tu t1 "$D1" alpha; tu t2 "$D2" alpha; tu t3 "$D2" packed; tu t4 "$D1" vend
  cmd c1 "$D2" boxonly; cmd c2 "$D2" compact
  tu told "$D40" boxonly                                                         # a record outside the window, in a file inside it
  printf '{"type":"user","uuid":"q1","timestamp":"%s","message":{"role":"user","content":"run <command-name>/alpha</command-name> %s"}}\n' "$D1" "$S"   # a quote mid-message
  printf '{"type":"user","uuid":"q2","timestamp":"%s","message":{"role":"user","content":"\\"name\\":\\"Skill\\" alpha %s"}}\n' "$D1" "$S"                  # prose naming the tool
  printf '{"type":"api-request-blob","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t9","name":"Skill","input":{"skill":"alpha"}}]}}\n' "$D1"   # a request echo
  printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t8","name":"Skill","input":{"skill":'"'"'\n' "$D1"     # a truncated line
} > "$CFG/projects/-fx/a.jsonl"
{ tu t1 "$D1" alpha                                                                # a resumed session copies t1: one use, not two
  tu t5 "$D1" no-such-skill; tu t6 "$D1" '/vend'                                   # unknown is dropped; a leading slash is the same skill
} > "$CFG/projects/-fy/b.jsonl"
{ tu t7 "$D1" alpha; } > "$CFG/projects/-fy/old.jsonl"                             # a file untouched past the window
touch -t "$(jq -n -r '(now - 4000000) | strftime("%Y%m%d%H%M")')" "$CFG/projects/-fy/old.jsonl"
tree() { find "$CFG" "$T_TMP/tmp" "$T_TMP/home" -type f 2>/dev/null | sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done; }
usage() { (cd "$R" && unset CLAUDE_CONFIG_DIR && sh "$R/bin/skill-catalog.sh" usage "$@"); }
TOOL_COPY="$R/bin/skill-catalog.sh"

t_section "1 · the shape, and the tiers the installed book derives"
BEFORE="$(tree)"
OUT="$(usage --json --dir "$CFG" 2>"$T_TMP/err")"
t_eq "the output is one JSON object" 1 "$(printf '%s' "$OUT" | jq -s 'length')"
t_eq "days defaults to 30" 30 "$(printf '%s' "$OUT" | jq '.days')"
t_eq "ts is an ISO UTC stamp" true "$(printf '%s' "$OUT" | jq '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")')"
t_eq "each skill carries exactly the contract's keys" '["description","hidden","last_used","name","tier","uses"]' "$(printf '%s' "$OUT" | jq -c '[.skills[] | keys] | unique | .[0]')"
t_eq "the skills are the installed ones" '["alpha","boxonly","longdesc","packed","vend"]' "$(printf '%s' "$OUT" | jq -c '[.skills[].name] | sort')"
f() { printf '%s' "$OUT" | jq -r --arg n "$1" ".skills[] | select(.name == \$n) | $2"; }
t_eq "a skills/ skill is core" core "$(f alpha .tier)"
t_eq "a vendor/skills skill is vendored" vendored "$(f vend .tier)"
t_eq "a skill a pack manifest lists is pack" pack "$(f packed .tier)"
t_eq "a skill nothing tracks is box" box "$(f boxonly .tier)"
t_eq "disable-model-invocation: true is hidden" true "$(f alpha .hidden)"
t_eq "...and its absence is not" false "$(f vend .hidden)"

t_section "2 · descriptions: the first sentence, at most 100 characters"
t_eq "the first sentence, USE WHEN dropped with the rest" "Alpha does the first thing." "$(f alpha .description)"
t_eq "no full stop: the whole line" "Box only, no period at the end" "$(f boxonly .description)"
t_eq "a long one is cut to 100 characters" true "$(f longdesc '(.description | length) <= 100 and (.description | endswith("…"))')"

t_section "3 · the counts: what is a use, and what is not"
t_eq "two Skill tool_uses, a copy of one in another file, a quote, an echo and a stale file: 2" 2 "$(f alpha .uses)"
t_eq "...and last_used is the newest of them" "$(printf '%s' "$D1" | cut -c1-19)Z" "$(f alpha .last_used)"
t_eq "a typed /command counts, and an old record in a fresh file does not" 1 "$(f boxonly .uses)"
t_eq "a Skill call and a leading-slash one both count" 2 "$(f vend .uses)"
t_eq "a pack skill's call counts" 1 "$(f packed .uses)"
t_eq "an unused skill is 0 with a null last_used" '0 null' "$(f longdesc '"\(.uses) \(.last_used)"')"
t_hasnt "a name no skill carries (compact, no-such-skill) is not in the output" "$OUT" 'compact'

t_section "4 · --days is the window"
t_eq "--days 1 keeps nothing older than a day" 0 "$(usage --json --days 1 --dir "$CFG" | jq '[.skills[] | select(.name == "boxonly")][0].uses')"
t_eq "--days 60 reaches the old record in the fresh file, and the stale file" 3 "$(usage --json --days 60 --dir "$CFG" | jq '[.skills[] | select(.name == "alpha")][0].uses')"
t_eq "--days is echoed" 60 "$(usage --json --days 60 --dir "$CFG" | jq '.days')"

t_section "5 · privacy: names, counts and timestamps only, and nothing written"
t_hasnt "no transcript text comes out" "$OUT" "$S"
t_hasnt "no session or record id comes out" "$OUT" 'toolu'
t_eq "a run writes no file anywhere: the config dir, the temp dir and home are the same tree" "$BEFORE" "$(tree)"
t_eq "stderr is empty on a good run" "" "$(cat "$T_TMP/err")"

t_section "6 · refusals: unavailable is never zero, and the form is read-only"
t_exit "no --json is a usage error" 2 usage --dir "$CFG"
t_exit "--apply is refused" 2 usage --json --apply --dir "$CFG"
t_exit "--days 0 is refused" 2 usage --json --days 0 --dir "$CFG"
t_exit "--days abc is refused" 2 usage --json --days abc --dir "$CFG"
t_exit "no target is a usage error" 2 usage --json
mkdir -p "$T_TMP/nostore/skills/alpha"; cp "$CFG/skills/alpha/SKILL.md" "$T_TMP/nostore/skills/alpha/"
NS="$(usage --json --dir "$T_TMP/nostore" 2>&1)"
t_exit "a config dir with no transcript store exits 1" 1 usage --json --dir "$T_TMP/nostore"
t_hasnt "...and prints no JSON zeros" "$NS" '"uses"'

t_section "7 · red proof: break the count and this suite goes red"
sed 's/group_by(\.key)/map([.])/' "$TOOL_COPY" > "$R/bin/mut.sh"
t_eq "the mutation applied" 1 "$(grep -c 'map(\[\.\])' "$R/bin/mut.sh")"
MUT="$(cd "$R" && unset CLAUDE_CONFIG_DIR && sh "$R/bin/mut.sh" usage --json --dir "$CFG" | jq -r '.skills[] | select(.name == "alpha") | .uses')"
t_eq "without the de-duplication alpha counts 3, not 2: the assertion in section 3 can fail" 3 "$MUT"
t_done
