#!/usr/bin/env sh
# bin/eval-redteam-corpus.sh (harbor#1313) on a synthetic corpus of harmless commands: a miss, a false positive, a cleared
# and a new miss, the baseline ratchet, a skipped corpus that is red, a pinned refresh from a local upstream, the ccg
# adapter through a stand-in harness, and the rule that no case text reaches stdout, checks.log or the state files.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/eval-redteam-corpus.sh"
C="$T_TMP/corp"; CACHE="$T_TMP/cache"; BL="$T_TMP/baseline.tsv"; SRC="$T_TMP/sources.tsv"
G="$C/shguard/tests/golden"; mkdir -p "$G" "$CACHE"
printf 'name\turl\tcommit\n' > "$SRC"
printf 'corpus\tid\treason\n' > "$BL"
# the marker is case text: it must never be printed or stored. Every command here is harmless and none is executed.
MARK=rtcanary-7f3a
corpus() { # <file> <decision:command>… — one JSONL line each
  _cf="$G/$1.jsonl"; shift; : > "$_cf"
  for _l in "$@"; do jq -nc --arg d "${_l%%:*}" --arg c "${_l#*:}" '{command: $c, decision: $d}' >> "$_cf"; done
}
BUS="$HOME/.local/state/harbor/events"  # the sandbox HOME's bus, handed over: the cache here is not the live one
run() { HARBOR_EVENT_DIR="${BUSX-$BUS}" HARBOR_REDTEAM_DIR="$C" HARBOR_CACHE_DIR="${CACHEX:-$CACHE}" HARBOR_REDTEAM_BASELINE="$BL" HARBOR_REDTEAM_SOURCES="$SRC" \
          HARBOR_NODE="${NODEBIN:-/nonexistent/node}" HARBOR_NOW="${AT:-1790000000}" sh "$TOOL" "$@" > "$T_TMP/out" 2>&1
        _rr=$?; cat "$T_TMP/out" >> "$T_TMP/all.out"; echo "exit $_rr"; }
OUT() { cat "$T_TMP/out"; }
st() { cut -f1 "$CACHE/redteam/shguard.guardfall.misses" | tr '\n' ' '; }
lastlog() { grep 'shguard/guardfall' "$CACHE/checks.log" | tail -1; }

t_section "first run: a miss and a false positive, both new and not accepted, so red"
corpus guardfall "Block:echo $MARK" "Allow:git status" "Allow:git reset --hard"
t_eq "it exits 1" "exit 1" "$(run --no-refresh)"
t_eq "the labelled-Block echo that Harbor allows is miss:1; the ask before a discard is fp:3" "miss:1 fp:3 " "$(st)"
t_has "checks.log carries the registry id and the delta" "$(lastlog)" "[check:redteam-corpus] "
t_has "...new 2, cleared 0, standing 2 of 3" "$(lastlog)" "new=2 cleared=0 standing=2 of 3 unaccepted=2"
t_has "the run names the corpus and its counts" "$(OUT)" "shguard/guardfall: 1 miss(es), 1 false positive(s) of 3"
t_has "node absent: ccg is skipped" "$(OUT)" "ccg: skipped - node is not installed"
t_has "...and a skipped corpus is a FAIL, never green" "$(OUT)" "  FAIL: ccg: skipped"

t_section "the obligation a new finding opens is due in a week, the check's cadence, not the default day"
_ev="$(find "$HOME/.local/state/harbor/events" -type f 2>/dev/null | xargs cat 2>/dev/null | grep '"obligation.open"' | grep '"redteam-corpus"' | tail -1)"
t_eq "the open event's deadline is the run plus 7 days, in the ISO form the ledger reads" "$(jq -nr '(1790000000 + 604800) | todate')" "$(printf '%s' "$_ev" | jq -r '.data.deadline_ts')"
t_has "a fix line names the command a person can run, not a temp clone" \
  "$(HARBOR_REDTEAM_SELF='sh bin/eval-redteam-corpus.sh' run --print >/dev/null; OUT)" "  fix: sh bin/eval-redteam-corpus.sh"

t_section "second run a day later: the miss clears, a new one appears, the standing one keeps its age"
corpus guardfall "Allow:echo $MARK" "Allow:git status" "Allow:git reset --hard" "Block:pwd"
AT=1790086400 run --no-refresh >/dev/null
t_eq "miss:1 is gone, miss:4 is new, fp:3 stands" "fp:3 miss:4 " "$(st)"
t_has "new 1, cleared 1" "$(lastlog)" "new=1 cleared=1 standing=2 of 4"
t_has "the oldest standing finding is a day old" "$(lastlog)" "oldest=1d"
t_eq "fp:3 keeps its first-seen epoch" "1790000000" "$(grep '^fp:3' "$CACHE/redteam/shguard.guardfall.misses" | cut -f2)"

t_section "the ratchet: --print is red until every finding is accepted, then green"
t_eq "two unaccepted: --print exits 1" "exit 1" "$(AT=1790086400 run --print)"
t_has "...and says how many are not accepted" "$(OUT)" "shguard/guardfall: 1 miss(es) and 1 false positive(s) of 4, 2 not accepted"
printf 'shguard/guardfall\tfp:3\tthe deliberate ask before a discard\n' >> "$BL"
t_eq "one still unaccepted: still exit 1" "exit 1" "$(AT=1790086400 run --print)"
printf 'shguard/guardfall\tmiss:4\tsynthetic\n' >> "$BL"
t_has "both accepted: the corpus line is ok" "$(AT=1790086400 run --print; OUT)" "  ok: shguard/guardfall:"
t_has "...but ccg was skipped, so --print stays red" "$(OUT)" "  FAIL: ccg: skipped"

t_section "stale: a pin changed since the run makes --print red"
printf 'shguard\t%s\t0000000000000000000000000000000000000000\n' "$T_TMP/nowhere" >> "$SRC"
t_eq "--print exits 1" "exit 1" "$(run --print)"
t_has "...naming why" "$(OUT)" "stale: the guards or the pins changed since the last run"
printf 'name\turl\tcommit\n' > "$SRC"

t_section "never run: --print exits 3"
t_eq "an empty cache" "exit 3" "$(CACHEX="$T_TMP/empty" run --print)"

t_section "refresh: the pinned commit of a local upstream, exported without .git, .github or .claude"
U="$T_TMP/upstream"; mkdir -p "$U/tests/golden" "$U/.github" "$U/.claude"
jq -nc '{command: "git status", decision: "Allow"}' > "$U/tests/golden/guardfall.jsonl"
: > "$U/.github/x"; : > "$U/.claude/x"
git -C "$U" init -q && git -C "$U" add -A && git -C "$U" -c user.name=t -c user.email=t@t commit -qm one
PIN="$(git -C "$U" rev-parse HEAD)"
printf 'shguard\t%s\t%s\n' "$U" "$PIN" >> "$SRC"
mv "$C/shguard" "$T_TMP/old-shguard"
run >/dev/null
t_eq "the corpus is in place" "yes" "$([ -f "$C/shguard/tests/golden/guardfall.jsonl" ] && echo yes)"
t_eq "...with no .git, .github or .claude" "" "$(ls -A "$C/shguard" | grep -E '^\.(git|github|claude)$')"
t_eq "...and its SOURCE records the pin" "$PIN" "$(cut -d' ' -f1 "$C/shguard.SOURCE")"
printf 'name\turl\tcommit\nshguard\t%s\t0000000000000000000000000000000000000000\n' "$U" > "$SRC"
run >/dev/null
t_has "a pin the upstream does not have: the refresh FAILs" "$(OUT)" "the pinned commit 0000000000000000000000000000000000000000 is not in"
t_has "...and the corpus is skipped, red" "$(OUT)" "FAIL: shguard/guardfall: skipped - the refresh failed"
printf 'name\turl\tcommit\n' > "$SRC"; rm -rf "$C/shguard" "$C/shguard.SOURCE"; mv "$T_TMP/old-shguard" "$C/shguard"

t_section "ccg: its harness spawns the adapter, which calls back into --judge"
if NODEBIN="$(command -v node)"; then
  mkdir -p "$C/ccg/tests"
  # a stand-in for ccg's tests/red-team.js: the same --hook/--json contract, two harmless cases
  cat > "$C/ccg/tests/red-team.js" <<'EOF'
const { spawnSync } = require('child_process'); const a = process.argv.slice(2); const hook = a[a.indexOf('--hook') + 1];
const ev = (c) => ({ tool_name: 'Bash', tool_input: { command: c } });
const cases = [['BLOCK', ev('echo rtcanary-7f3a')], ['ALLOW', ev('git status')]].map(([want, e]) => {
  const r = spawnSync(process.execPath, [hook], { input: JSON.stringify(e), encoding: 'utf8' });
  const blocked = r.status === 2; return { label: e.tool_input.command, expected: want, pass: (want === 'BLOCK') === blocked };
});
console.log(JSON.stringify({ total: cases.length, cases }));
EOF
  export NODEBIN; run --no-refresh >/dev/null; unset NODEBIN
  t_eq "the allowed BLOCK case is miss:1, the benign one passes" "miss:1 " "$(cut -f1 "$CACHE/redteam/ccg.misses" | tr '\n' ' ')"
  t_has "...and the log line counts 2 cases" "$(grep ' ccg ' "$CACHE/checks.log" | tail -1)" "standing=1 of 2"
else
  t_fail "node is not installed here, so the ccg adapter was not exercised"
fi

t_section "parallel: RT_JOBS workers judge the shguard cases at once, and the findings equal the serial run's"
_keep="$(cat "$G/guardfall.jsonl")"
corpus guardfall "Block:echo $MARK" "Allow:git status" "Allow:git reset --hard" "Block:pwd" "Allow:ls" "Block:echo $MARK two"
RT_JOBS=1 CACHEX="$T_TMP/cache-serial" run --no-refresh >/dev/null
_serial="$(cut -f1 "$T_TMP/cache-serial/redteam/shguard.guardfall.misses" | tr '\n' ' ')"
: > "$T_TMP/trace"
RT_CASE_TRACE="$T_TMP/trace" RT_JOBS=4 CACHEX="$T_TMP/cache-par" run --no-refresh >/dev/null
t_eq "4 workers, 6 cases: the first four trace lines are all starts (serial would alternate start, end)" "s s s s" "$(head -4 "$T_TMP/trace" | cut -d' ' -f1 | tr '\n' ' ' | sed 's/ $//')"
t_eq "the findings, in case order, equal the serial run's" "$_serial" "$(cut -f1 "$T_TMP/cache-par/redteam/shguard.guardfall.misses" | tr '\n' ' ')"
t_has "...and are non-empty, so the comparison compares something" "$_serial" "miss:1"
printf '%s\n' "$_keep" > "$G/guardfall.jsonl"

t_section "the handoff: only new findings not yet accepted open it, and only a run on the live state talks to the bus"
opens() { cat "$BUS"/*.jsonl 2>/dev/null | grep '"obligation.open"' | grep -c '"redteam-corpus"'; }
_o="$(opens)"
CACHEX="$T_TMP/cache-acc" run --no-refresh >/dev/null
t_has "control: a fresh cache reads both accepted findings as new" "$(grep 'shguard/guardfall' "$T_TMP/cache-acc/checks.log" | tail -1)" "new=2"
t_eq "...and opens no handoff, since both are accepted" "$_o" "$(opens)"
sed -i.bak '/miss:4/d' "$BL"
( BUSX='' CACHEX="$T_TMP/cache-borrowed" run --no-refresh >/dev/null )  # a subshell: sh keeps an assignment before a function
t_has "control: a borrowed cache, no bus handed over, finds miss:4 new and not accepted" "$(OUT)" "new 2, cleared 0, 1 not accepted"
t_eq "...and leaves the bus alone" "$_o" "$(opens)"
CACHEX="$T_TMP/cache-handed" run --no-refresh >/dev/null
t_eq "the same run with a bus handed over opens it" "$((_o + 1))" "$(opens)"
t_has "...titled with what waits" "$(cat "$BUS"/*.jsonl | grep '"obligation.open"' | tail -1 | jq -r .data.title)" "redteam-corpus: 1 new to adjudicate, harbor#1313"
mkdir -p "$CLAUDE_CONFIG_DIR/cache"
( BUSX='' CACHEX="$CLAUDE_CONFIG_DIR/cache" run --no-refresh >/dev/null )
t_eq "the weekly job's shape, the live cache and no bus handed over, opens it too" "$((_o + 2))" "$(opens)"
mv "$BL.bak" "$BL"

t_section "no case text anywhere: stdout, checks.log, the state files"
t_has "every run's output was kept" "$(grep -c 'redteam-corpus: ' "$T_TMP/all.out")" "1"
t_eq "the marker is in no output or state" "" "$(grep -rl "$MARK" "$T_TMP/all.out" "$CACHE" 2>/dev/null)"
t_has "...while the corpus file does carry it, so the grep can match" "$(cat "$G/guardfall.jsonl")" "$MARK"
t_done
