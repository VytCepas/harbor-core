#!/usr/bin/env sh
# skill-fire.sh's output follows contracts/logging.md (harbor#771): the per-case table and the score line stay on
# stdout as the report readers consume them, the log is on stderr, a MISS or a FALSE-FIRE is a FAIL followed by
# its fix, the run ends with the summary, and the exit codes (0, 1 a MISS or an environment failure, 2 usage)
# are the ones it always had. `claude` is a stub: no model is ever called.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/skill-fire.sh"; TMP="$T_TMP/sf"
mkdir -p "$TMP/rec" "$HOME/.claude" "$TMP/skills"
cat > "$T_BIN/claude" <<'STUB'
#!/usr/bin/env sh
p=''
while [ $# -gt 0 ]; do case "$1" in -p) shift; p="$1" ;; esac; shift; done
sid="sess-$$"
d="${CLAUDE_CONFIG_DIR:?}/projects/stub"; mkdir -p "$d"
: > "$d/$sid.jsonl"
for f in $(printf '%s' "$p" | tr ' ' '\n' | sed -n 's/^FIRE://p'); do
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}\n' "$f" >> "$d/$sid.jsonl"
done
printf '{"session_id":"%s"}\n' "$sid"
STUB
chmod +x "$T_BIN/claude"
for n in red-team evals; do
  mkdir -p "$TMP/skills/$n"; printf -- '---\nname: %s\n---\nbody\n' "$n" > "$TMP/skills/$n/SKILL.md"
done
GOOD="$TMP/good.tsv"; MISS="$TMP/miss.tsv"; NOCTL="$TMP/noctl.tsv"
printf 'hit\tred-team\tplease FIRE:red-team now\ncontrol\tNONE\tstay quiet\n' > "$GOOD"
printf 'hit\tred-team\tplease FIRE:red-team now\nmissed\tevals\tFIRE:red-team instead\ncontrol\tNONE\tstay quiet\n' > "$MISS"
printf 'only\t?\tno control here\n' > "$NOCTL"
sf() { _c="$1"; shift; sh "$S" --cases "$_c" --skills "$TMP/skills" "$@" >"$TMP/out" 2>"$TMP/err"; echo "exit $?"; }
OUT() { cat "$TMP/out"; }; ERR() { cat "$TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$TMP/err"; }
shaped() { ERR | grep -vcE '^(── |  (ok|FAIL|WARN|note|skip|fix): |skill-fire: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)'; }

t_section "the plan: a log on stderr, nothing on stdout, no session started"
t_eq "it exits 0" "exit 0" "$(sf "$GOOD")"
t_eq "stdout is empty" "" "$(OUT)"
t_eq "the header" "── skill-fire · DRY RUN" "$(ERR | head -1)"
t_has "the roster is a note" "$(ERR)" "  note: roster      2 skill(s)"
t_eq "the summary ends it" "skill-fire: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "a clean sweep: the table on stdout unchanged, ok lines on stderr, exit 0"
t_eq "it exits 0" "exit 0" "$(sf "$GOOD" --apply)"
t_eq "the case row keeps its shape on stdout" 1 "$(OUT | grep -cE '^  hit +want=red-team +invoked=red-team +read=- +ok$')"
t_has "the score line is on stdout" "$(OUT)" "roster of 2 — 2 ok, 0 missed, 0 false fire(s), 0 open over 2 case(s)"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -cE '^  (ok|FAIL|WARN|note|skip|fix): |^skill-fire: ')"
t_has "a case is an ok line on stderr" "$(ERR)" "  ok: case hit: wanted red-team, fired red-team"
t_eq "the summary ends it" "skill-fire: 2 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "every stderr line is the log's shape" 0 "$(shaped)"

t_section "a MISS: the FAIL, its fix, the summary, exit 1"
t_eq "it exits 1" "exit 1" "$(sf "$MISS" --apply)"
t_eq "the MISS row is still on stdout" 1 "$(OUT | grep -cE '^  missed +want=evals .* MISS$')"
t_has "the FAIL names the case" "$(ERR)" "  FAIL: case missed: wanted evals, fired red-team"
t_has "its fix is on the next line" "$(after_fail)" "  fix: sed -n '1,12p' $TMP/skills/evals/SKILL.md"
t_eq "the summary counts the failure" "skill-fire: 2 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "--json keeps its exit 0" "exit 0" "$(sf "$MISS" --apply --json)"
t_eq "--json: stdout ends in the JSON report" 1 "$(OUT | sed -n '/^{/,$p' | jq -r '.cases | length' | grep -c '^3$')"
t_eq "--json: the summary still counts the MISS" "skill-fire: 2 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"

t_section "refusals: FAIL, its fix, the summary, and the exit code the tool always had"
t_eq "no control exits 1" "exit 1" "$(sf "$NOCTL" --apply)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL says why" "$(ERR)" "  FAIL: no NONE case in $NOCTL"
t_has "its fix appends one" "$(after_fail)" "  fix: printf 'control"
t_eq "the live dir exits 1" "exit 1" "$(CLAUDE_CONFIG_DIR="$HOME/.claude" sf "$GOOD" --apply)"
t_has "its FAIL is the live gate" "$(ERR)" "  FAIL: refusing the live config dir without an explicit --live"
t_eq "its fix names --live" "  fix: sh $S --cases $GOOD --skills $TMP/skills --apply --live" "$(after_fail)"
t_eq "an unknown flag exits 2" "exit 2" "$(sf "$GOOD" --nonsuch)"
t_has "its FAIL names the flag" "$(ERR)" "  FAIL: unknown flag --nonsuch: no session was started"
t_eq "its fix reads the help" "  fix: sh $S --help" "$(after_fail)"
t_eq "a missing cases file exits 1" "exit 1" "$(sf "$TMP/nope.tsv")"
t_has "its FAIL names it" "$(ERR)" "  FAIL: no cases file at $TMP/nope.tsv"
t_eq "the summary ends it" "skill-fire: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_done
