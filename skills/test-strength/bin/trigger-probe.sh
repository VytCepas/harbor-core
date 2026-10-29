#!/usr/bin/env sh
# trigger-probe.sh — does a REAL session route a REAL request to this skill?
# Ticket: R5 / contracts/gates.md. The checker behind `subject-kind
# trigger-routing` in skills/test-strength/bin/prove.sh.
#
#   sh trigger-probe.sh --card <SKILL.md> --queries <file> [flags]
#
# WHY THIS EXISTS. Every other checker in this repo reads an artefact and
# reports whether it is shaped right. None of them can tell you whether a skill
# FIRES when somebody types a sentence at it. skills/topology's routing is
# asserted today only by check-topology.sh --detect, which is our own string
# matcher tested by our own string assertions — we assert the router routes,
# using the router. This runs the sentence through a real `claude -p` session
# and watches whether the skill was actually invoked.
#
# WHAT IT IS NOT. This prints counts of sessions, never a quality score. A
# skill that fires on every query it should fire on may still be a bad skill;
# a published study puts the correlation between a structural-scan score and
# real quality at Spearman rho = 0.14, and the same caution applies here with
# more force, because a trigger rate says nothing at all about what the skill
# does after it triggers. Read every number below as "how often did routing go
# the declared way", nothing more.
#
# PRIOR ART, AND WHAT WAS TAKEN FROM IT. Anthropic's skill-creator ships
# scripts/run_eval.py, which plants a command file under a project's
# .claude/commands/ so the skill appears in the session's available-skills
# list, runs `claude -p` with the raw query, and decides from the stream events
# whether the skill was read. The planting trick, the `<name>-skill-<token>`
# unique id, the CLAUDECODE strip and the tool_use detection are all from
# there. What is added here: declared NEGATIVE queries (a router that fires on
# everything scores a flawless positive rate), the ABLATION arm (below), and
# could-not-look as a distinct exit code so an absent binary can never read as
# a pass.
#
# THE ABLATION ARM AND WHY IT IS NOT OPTIONAL. `--absent` runs the same
# queries with NO command file planted. The planted token then cannot appear in
# any transcript, so the honest result is zero fires. If a fire is reported
# anyway, this script's detector is matching something other than an
# invocation — the token echoed in the session's own skill listing, say, which
# is present in the `system` init event of every run — and every number it
# prints above is noise. That is the endogeneity check: without it, a detector
# that always says "fired" scores 100 % and reads as a perfect router.
#
# NON-DETERMINISM IS REAL AND IS NOT SMOOTHED AWAY. A model is sampled, so one
# query can route on one run and not the next. `--runs N` repeats each query;
# a query whose fires are neither 0 nor N is reported UNSTABLE and named. The
# pass rule is the fired RATE against `--threshold` (default 50), which is
# run_eval.py's rule, and a single-run probe therefore has no stability
# evidence at all — it is a spot check, and the summary line says how many runs
# stood behind it so nobody has to guess.
#
# COST IS REAL MONEY. Every query-run is one billed session. The summary line
# carries the measured `cost_usd` summed from each session's own result event,
# and `--max-usd` is passed to `claude --max-budget-usd` so one runaway session
# cannot empty an account. Measured 2026-08-30 on this box: a cold session with
# --model haiku cost USD 0.032, a warm one USD 0.007.
#
# WRITES NOTHING THAT SURVIVES. The planted command file goes in a mktemp
# project root, never in the repo and never under the operator's ~/.claude;
# `--no-session-persistence` stops the child writing a transcript there. The
# workspace is removed on every exit path unless --keep-work is given.
#
# WHAT THE CHILD SESSION DOES INHERIT, STATED RATHER THAN WISHED AWAY. It reads
# the operator's ~/.claude: global CLAUDE.md, memory, the project registry, and
# the SessionStart hooks, which fire once per session (measured 2026-08-31:
# seven of them, ~17 s of the wall clock). That is FIDELITY — it is the context
# a real request actually lands in — and it is also why a run here is not
# portable between boxes and why the sweep is not free. The obvious isolation,
# pointing CLAUDE_CONFIG_DIR at a scratch directory, was MEASURED and does not
# work: OAuth credentials live under ~/.claude, so the child comes back "Not
# logged in" while still printing a well-formed success-shaped result event.
# Isolation therefore needs an ANTHROPIC_API_KEY and `--bare`, which is a
# different credential the operator has not granted. Until then the inheritance
# is the deal, and ISOENV below is the one seam where a future key would go.
#
# BSD/POSIX NOTES. No `local`, no arrays, no `[[`, no bash case conversion, no
# `timeout` on this box (hence the poll-and-kill watchdog below). `set -e` is
# NOT set: this script runs commands that are expected to fail. Every negative
# assertion uses /usr/bin/grep, because `grep` here is ugrep with -I
# --ignore-files and may decline to look rather than find nothing.
set -u

# \034 rather than a tab as the internal field separator, for the reason
# prove.sh records: `read` collapses runs of an IFS WHITESPACE character, so a
# tab-delimited row with an empty middle column silently loses a field and every
# column after it shifts left. A query text may legitimately contain tabs.
SEP="$(printf '\034')"

CARD=""; QFILE=""; RUNS=1; THRESH=50; MODEL=""; STIMEOUT=120; MAXUSD="0.25"
ABSENT=0; KEEPWORK=0; VERBOSE=0; EARLYSTOP=1
CLAUDE_BIN="${TRIGGER_PROBE_CLAUDE:-claude}"
# The one seam for a future isolated credential (see the header). Empty by
# default and deliberately unquoted at the call site so an empty value adds no
# argument; nothing in this repo sets it today.
ISOENV="${TRIGGER_PROBE_ENV:-}"

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  printf '\nflags:\n'
  printf '  --card <path>        the routing surface: a SKILL.md-shaped file with YAML frontmatter\n'
  printf '  --queries <path>     one query per line, "+ text" must route, "- text" must not\n'
  printf '  --runs <n>           repetitions per query (default 1; 1 gives no stability evidence)\n'
  printf '  --threshold <pct>    fired-rate at or above which a positive passes (default 50)\n'
  printf '  --model <name>       model for the child session (default: the account default)\n'
  printf '  --session-timeout <s>  wall-clock bound per session (default 120)\n'
  printf '  --max-usd <amount>   per-session spend cap, passed to --max-budget-usd (default 0.25)\n'
  printf '  --absent             plant nothing — the ablation arm; every fire is a detector fault\n'
  printf '  --keep-work          keep the workspace and print its path\n'
  printf '  --verbose            echo each session command before running it\n'
  printf '  --no-early-stop      let every session run to completion — the only way cost_usd is a TOTAL\n'
  printf '\nexit: 0 every query routed as declared · 1 at least one did not · 9 could not look\n'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --card)    shift; CARD="${1:-}" ;;
    --queries) shift; QFILE="${1:-}" ;;
    --runs)    shift; RUNS="${1:-}" ;;
    --threshold) shift; THRESH="${1:-}" ;;
    --model)   shift; MODEL="${1:-}" ;;
    --session-timeout) shift; STIMEOUT="${1:-}" ;;
    --max-usd) shift; MAXUSD="${1:-}" ;;
    --absent)  ABSENT=1 ;;
    --keep-work) KEEPWORK=1 ;;
    --verbose) VERBOSE=1 ;;
    --no-early-stop) EARLYSTOP=0 ;;
    -h|--help) usage ;;
    *) printf 'trigger-probe: unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------- refusals
# A MISSING INPUT IS EXIT 2 (the command line is wrong); A MISSING CAPABILITY
# IS EXIT 9 (nobody could look). The two are never merged, because their
# repairs point at different people.
[ -n "$CARD" ]  || { printf 'trigger-probe: --card is required\n' >&2; exit 2; }
[ -n "$QFILE" ] || { printf 'trigger-probe: --queries is required\n' >&2; exit 2; }
case "$RUNS"   in ''|*[!0-9]*) printf 'trigger-probe: --runs must be an integer\n' >&2; exit 2 ;; esac
case "$THRESH" in ''|*[!0-9]*) printf 'trigger-probe: --threshold must be an integer\n' >&2; exit 2 ;; esac
case "$STIMEOUT" in ''|*[!0-9]*) printf 'trigger-probe: --session-timeout must be an integer\n' >&2; exit 2 ;; esac
[ "$RUNS" -ge 1 ] || { printf 'trigger-probe: --runs must be at least 1\n' >&2; exit 2; }

_cnl() { printf 'trigger-probe: COULD-NOT-LOOK  %s\n' "$1"; exit 9; }

[ -f "$CARD" ]  || _cnl "the card does not exist: $CARD"
[ -f "$QFILE" ] || _cnl "the query file does not exist: $QFILE"
command -v "$CLAUDE_BIN" >/dev/null 2>&1 \
  || _cnl "no '$CLAUDE_BIN' on PATH — absence is not a pass, so this is not a zero"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/trigprobe.XXXXXX")" \
  || _cnl "cannot create a workspace under ${TMPDIR:-/tmp}"
# harbor#743: `kill -9` on the subshell left the `claude` under it running, and
# billing, on PID 1. A copy of prove.sh's _kill_tree: each file runs on its own.
_kill_tree() { # $1 = root pid
  _kt_all=" $1 "; _kt_new="$1"
  while [ -n "$_kt_new" ]; do
    kill -STOP $_kt_new 2>/dev/null
    _kt_new=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v all="$_kt_all" \
      'index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }')
    _kt_all="$_kt_all$_kt_new"
  done
  kill -9 $_kt_all 2>/dev/null
}
SESS_PID=""
_cleanup() {
  [ -n "$SESS_PID" ] && { _kill_tree "$SESS_PID"; wait "$SESS_PID" 2>/dev/null; SESS_PID=""; }  # harbor#743
  [ "$KEEPWORK" = 1 ] && return 0; [ -d "$WORK" ] && rm -rf "$WORK"; return 0
}
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM HUP

PROOT="$WORK/proj"
mkdir -p "$PROOT/.claude" "$WORK/t"

# ------------------------------------------------------- the routing surface
# THE CARD IS PARSED, NEVER RESTATED. Everything planted below is read out of
# the file at $CARD, so a mutation of that file is a mutation of what the
# session sees — which is the only reason mutating it measures anything.
#
# AN EMPTY CARD IS A LAWFUL INPUT, NOT AN ERROR. prove.sh's canary truncates
# the subject to zero bytes; the honest response is to plant a skill with no
# name and no description, which is exactly what a session would then be shown.
# The fallback name is the neutral token `probe` rather than the real skill's,
# so an emptied card leaves NO routing signal at all — a real name would leave
# one and the canary would be measuring the name instead of the description.
_frontmatter() { awk 'NR == 1 && $0 != "---" { exit } NR == 1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1"; }
_frontmatter "$CARD" > "$WORK/fm"

NAME=$(awk -F': *' '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }' "$WORK/fm")
[ -n "$NAME" ] || NAME=probe
# The description is either the rest of the `description:` line (bare or
# double-quoted) or, when that rest is a `|`/`>` block-scalar marker, the
# indented lines under it. Both shapes ship in this repo, so both are read.
awk '
  /^description:[[:space:]]*/ && !seen {
    seen = 1
    v = $0; sub(/^description:[[:space:]]*/, "", v)
    if (v == "|" || v == ">" || v == "|-" || v == ">-") { block = 1; next }
    gsub(/^"|"$/, "", v); print v; next
  }
  block && /^[[:space:]]+/ { sub(/^[[:space:]]+/, ""); print; next }
  block { block = 0 }
' "$WORK/fm" > "$WORK/desc"
DESC=$(tr '\n' ' ' < "$WORK/desc" | sed -e 's/[[:space:]]*$//')

TOK=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
[ -n "$TOK" ] || TOK=$$
CLEAN="$NAME-skill-$TOK"

# THE PLANT IS A PROJECT SKILL, NOT A COMMAND FILE, AND THE PRIOR ART IS OUT
# OF DATE HERE. run_eval.py writes .claude/commands/<name>.md on the stated
# premise that this makes the skill "appear in Claude's available_skills list".
# Measured 2026-08-31 against claude 2.1.251 by dumping the session's own init
# event: a planted command file appears in `slash_commands` and NOT in
# `skills`, and `skills` is the list the Skill tool can reach. So a
# command-file plant can never be invoked by the model, and every query scores
# a clean-looking MISS — a whole sweep of false negatives that reads exactly
# like a weak description. Planting .claude/skills/<name>/SKILL.md puts the
# name in BOTH lists, which the same init dump confirms.
if [ "$ABSENT" = 0 ]; then
  mkdir -p "$PROOT/.claude/skills/$CLEAN"
  # The YAML block scalar keeps a description carrying quotes, colons and
  # newlines from breaking the file — run_eval.py's shape, for the same reason.
  { printf -- '---\nname: %s\ndescription: |\n' "$CLEAN"
    if [ -n "$DESC" ]; then printf '  %s\n' "$DESC"; else printf '  \n'; fi
    printf -- '---\n\n# %s\n\nThis skill handles: %s\n' "$CLEAN" "$DESC"
  } > "$PROOT/.claude/skills/$CLEAN/SKILL.md"
fi

# ------------------------------------------------------------- the queries
# `+` MUST route, `-` MUST NOT. The negative half is the one that catches an
# over-broad description, and a declaration carrying only positives is refused
# rather than scored: a router that fires on everything passes a positives-only
# sweep perfectly, which is the exact shape of the over-broad guard that
# test-strength check 2 exists to catch.
: > "$WORK/q"
while IFS= read -r _l || [ -n "$_l" ]; do
  _l=$(printf '%s' "$_l" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -n "$_l" ] || continue
  case "$_l" in '#'*) continue ;; esac
  _sign=$(printf '%s' "$_l" | cut -c1)
  _text=$(printf '%s' "$_l" | cut -c2- | sed -e 's/^[[:space:]]*//')
  case "$_sign" in
    '+'|'-') ;;
    *) _cnl "query line does not begin with + or -: $_l" ;;
  esac
  [ -n "$_text" ] || _cnl "query line has a sign and no text: $_l"
  printf '%s\034%s\n' "$_sign" "$_text" >> "$WORK/q"
done < "$QFILE"

NPOS=$(awk -F"$SEP" '$1 == "+" { n++ } END { print n + 0 }' "$WORK/q")
NNEG=$(awk -F"$SEP" '$1 == "-" { n++ } END { print n + 0 }' "$WORK/q")
[ "$NPOS" -ge 1 ] || _cnl "no + query declared — nothing to measure"
[ "$NNEG" -ge 1 ] || _cnl "no - query declared — a positives-only sweep cannot fail an always-firing router"

# --------------------------------------------------------------- one session
# A WATCHDOG, BECAUSE THIS BOX HAS NO timeout(1). A hung session is reported as
# an ERROR, never as a no-fire: "nobody watched it finish" and "it declined to
# fire" are different facts and merging them manufactures a negative result.
if sleep 0.2 2>/dev/null; then _NAP=0.2; _NAPS=5; else _NAP=1; _NAPS=1; fi
SESSIONS=0
ERRORS=0
TRUNCATED=0

_verdict() {  # $1 = log ; prints FIRE | SHADOW | NOFIRE | "" (undecided)
  # A THINKING-ONLY ASSISTANT EVENT IS NOT A DECISION, AND TREATING IT AS ONE
  # WOULD HAVE INVERTED EVERY LIVE RESULT. Measured 2026-08-31 on a session
  # that DID route: the assistant events arrive as
  # [thinking] [tool_use] [thinking] [tool_use] … — the model thinks in its own
  # event before it acts. A verdict taken on the first assistant line would
  # therefore have read NOFIRE on every firing session and FIRE on none, while
  # looking entirely reasonable. Only an event carrying a tool_use or a text
  # block is a decision; thinking is skipped.
  awk -v tok="$CLEAN" -v nm="$NAME" '
    index($0, "\"type\":\"assistant\"") == 0 { next }
    {
      tu = index($0, "\"type\":\"tool_use\"")
      tx = index($0, "\"type\":\"text\"")
      if (!tu && !tx) next
      sk = index($0, "\"name\":\"Skill\"") || index($0, "\"name\":\"Read\"")
      if (tu && sk && index($0, tok))                       { print "FIRE"; exit }
      # ONE-TRUE-AWK ENDS A STATEMENT AT A NEWLINE UNLESS THE LINE ENDS IN AN
      # OPERATOR, so every continuation below ends with ||, never begins with
      # one. Written the other way this program is a SYNTAX ERROR, and with the
      # stderr redirect at the bottom of this function it was a SILENT one:
      # measured 2026-08-31, awk printed nothing, every verdict came back
      # undecided, and the run fell through to the result-event path and
      # reported a clean `pos 0/2` — a whole sweep of false negatives from a
      # checker that had not parsed. The suite arm that asserts a FIRE is
      # DETECTED is what turns this from silent into red.
      sh1 = index($0, "\"skill\": \"" nm "\"") ||
            index($0, "\"skill\":\"" nm "\"") ||
            index($0, "/skills/" nm "/") ||
            index($0, "/" nm "/SKILL.md")
      if (tu && sk && sh1)                                  { print "SHADOW"; exit }
      # THE MODEL HAS DECIDED. Either it reached for a different tool first, or
      # it answered in text with no tool at all; run_eval.py treats the first
      # non-Skill/Read tool the same way, and for the same reason — routing is
      # the FIRST decision of the turn and everything after it is spend with no
      # signal in it.
      print "NOFIRE"; exit
    }
  ' "$1" 2>/dev/null
}

_one_session() {  # $1 = query text ; $2 = log path ; sets FIRED/SHADOW/ERR
  ERR=0; FIRED=0; SHADOW=0
  SESSIONS=$((SESSIONS + 1))
  _log="$2"
  # CLAUDECODE is stripped because the binary refuses to nest inside an
  # interactive Claude Code session; the guard is about terminal conflicts and
  # a programmatic subprocess is the case it was never aimed at (run_eval.py
  # does the same, for the same reason).
  #
  # --no-session-persistence keeps the child from writing a transcript under
  # the operator's ~/.claude. --mcp-config with an empty server set plus
  # --strict-mcp-config keeps MCP servers from loading, which is both cost and
  # a source of noise in the tool stream.
  #
  # --disallowedTools IS A SAFETY GATE, NOT AN OPTIMISATION, and it has already
  # earned its place. Measured 2026-08-31: a live session on the account
  # default model routed correctly and then went on to do the work, ending in
  # `Write {"file_path":"$HOME/<repo>/CLIENTS/ACME/TOPOLOGY.md"}`. The
  # write was refused by this list and the directory does not exist. A sweep is
  # dozens of unattended sessions with the operator's whole filesystem in
  # reach, so the list is the boundary. Skill and Read stay allowed because
  # they ARE the signal.
  set -- -p "$1" \
    --output-format stream-json --verbose \
    --no-session-persistence \
    --mcp-config '{"mcpServers":{}}' --strict-mcp-config \
    --max-budget-usd "$MAXUSD" \
    --disallowedTools Bash Edit Write NotebookEdit WebSearch WebFetch Task
  [ -n "$MODEL" ] && set -- "$@" --model "$MODEL"
  [ "$VERBOSE" = 1 ] && printf '  + %s %s\n' "$CLAUDE_BIN" "$*" >&2

  # STDIN IS /dev/null, AND THE REASON COST A LIVE RUN. This loop reads its
  # queries with `while read < $WORK/q`, so a child launched inside it inherits
  # that file as stdin — and `claude -p "text"` APPENDS piped stdin to the
  # prompt. Measured 2026-08-31: every session was sent the whole query file,
  # so the model saw the positive and the negative query at once and reasoned
  # about the + and - markers as if they were syntax. Both queries then scored
  # against one contaminated prompt. A probe whose prompt is not the query it
  # names is not measuring routing at all.
  ( cd "$PROOT" && env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT $ISOENV "$CLAUDE_BIN" "$@" ) \
    < /dev/null > "$_log" 2> "$_log.err" &
  _wpid=$!
  SESS_PID=$_wpid
  _polls=0; _wmax=$((STIMEOUT * _NAPS)); _early=""
  # STOP AT THE DECISION, AND THE BILL IS THE REASON. Measured 2026-08-31: one
  # positive query on the account default model routed on its FIRST tool call
  # and then spent USD 0.77 doing the work it had routed to, hitting
  # --max-budget-usd and returning `is_error:true` — a correct measurement that
  # the run then had to discard. Reading the verdict off the transcript as it
  # streams and killing at the decision costs a fraction of that and keeps the
  # answer. A watchdog kill is still a kill, so a session bounded this way is
  # reported as truncated rather than as a clean completion.
  while kill -0 "$_wpid" 2>/dev/null; do
    _v=""
    [ "$EARLYSTOP" = 1 ] && _v=$(_verdict "$_log")
    if [ -n "$_v" ]; then
      _kill_tree "$_wpid"
      wait "$_wpid" 2>/dev/null
      _early="$_v"
      TRUNCATED=$((TRUNCATED + 1))
      break
    fi
    if [ "$_polls" -ge "$_wmax" ]; then
      _kill_tree "$_wpid"
      wait "$_wpid" 2>/dev/null
      SESS_PID=""
      ERR=1; ERRORS=$((ERRORS + 1)); return 0
    fi
    sleep "$_NAP"
    _polls=$((_polls + 1))
  done
  [ -n "$_early" ] || wait "$_wpid"
  SESS_PID=""

  if [ -z "$_early" ]; then
    # A SESSION THAT DID NOT RUN IS AN ERROR, NEVER A NO-FIRE. This is the
    # difference between "the skill did not trigger" and "nothing was
    # measured", and only one of those is a finding.
    #
    # THE RESULT EVENT'S PRESENCE IS NOT ENOUGH, AND THAT COST A MEASURED RUN.
    # 2026-08-31, pointing the child at an empty CLAUDE_CONFIG_DIR to isolate
    # it from the operator's config: the session emitted a well-formed result
    # event carrying `"subtype":"success"`, `"total_cost_usd":0` and
    # `"result":"Not logged in · Please run /login"`. An unauthenticated box
    # would therefore have reported `pos 0/N` — a clean-looking, entirely false
    # negative over sessions that never reached the API. `is_error` is the only
    # field that discriminates; `subtype` says success either way.
    #
    # THE ORDER MATTERS AND IS DELIBERATE: the verdict is read FIRST. A session
    # that routed and was then cut off by --max-budget-usd carries `is_error`
    # true, and it has still answered the only question being asked.
    _early=$(_verdict "$_log")
    if [ -z "$_early" ]; then
      if ! /usr/bin/grep -q '"type":"result"' "$_log" 2>/dev/null; then
        ERR=1; ERRORS=$((ERRORS + 1)); return 0
      fi
      if ! /usr/bin/grep -q '"is_error":false' "$_log" 2>/dev/null; then
        ERR=1; ERRORS=$((ERRORS + 1)); return 0
      fi
      _early=NOFIRE
    fi
  fi

  case "$_early" in
    FIRE)   FIRED=1 ;;
    # THE SHADOW. The child inherits the operator's ~/.claude, so if the skill
    # under test is ALREADY INSTALLED there the session has two candidates: the
    # plant and the original, and a session that routes to the original scores
    # as a MISS while having routed perfectly well. Measured 2026-08-31 on the
    # account default model, a session whose plant was NOT the winner: its
    # decisions ran Skill{skill-catalog} → Glob ~/.claude/skills → Read
    # ~/.claude/skills/topology/SKILL.md. Note what that means for the rule
    # above: under the first-decision rule that session is NOFIRE, because its
    # FIRST decision was the operator's index skill, not the installed twin.
    # This check therefore fires only in the narrower case where the twin wins
    # the first decision outright — it is a guard against one specific way the
    # number lies, not a general correction for a contaminated environment.
    # The general one does not exist while ~/.claude is inherited, which is why
    # the header says so in those words.
    SHADOW) SHADOW=1 ;;
  esac
  return 0
}

# ------------------------------------------------------------------ the sweep
: > "$WORK/rows"
_qn=0
while IFS= read -r _row; do
  [ -n "$_row" ] || continue
  _sign=$(printf '%s' "$_row" | awk -F"$SEP" '{print $1}')
  _text=$(printf '%s' "$_row" | awk -F"$SEP" '{print $2}')
  _qn=$((_qn + 1))
  _fired=0; _err=0; _shad=0
  _r=1
  while [ "$_r" -le "$RUNS" ]; do
    _one_session "$_text" "$WORK/t/q$_qn-r$_r.jsonl"
    if [ "$ERR" = 1 ]; then _err=$((_err + 1)); else
      [ "$FIRED" = 1 ]  && _fired=$((_fired + 1))
      [ "$SHADOW" = 1 ] && _shad=$((_shad + 1))
    fi
    _r=$((_r + 1))
  done
  printf '%s\034%s\034%s\034%s\034%s\034%s\n' "$_sign" "$_fired" "$RUNS" "$_err" "$_shad" "$_text" >> "$WORK/rows"
done < "$WORK/q"

# ------------------------------------------------------------------ scoring
# THE PASS RULE IS THE FIRED RATE, AND IT INVERTS UNDER --absent. With nothing
# planted the token cannot be invoked, so the ONLY correct result is zero fires
# on every query, positive and negative alike; any fire means this script's
# detector is matching something that is not an invocation.
COST=$(awk '
  { while (match($0, /"total_cost_usd":[0-9.eE+-]+/)) {
      s = substr($0, RSTART + 18, RLENGTH - 18) + 0; t += s
      $0 = substr($0, RSTART + RLENGTH) } }
  END { printf "%.4f", t + 0 }
' "$WORK"/t/*.jsonl 2>/dev/null)
[ -n "$COST" ] || COST=0.0000

POSF=0; NEGF=0; UNSTABLE=0; BAD=0; SHADOWED=0; UNSTABLE_IDS=""
: > "$WORK/detail"
_qn=0
while IFS= read -r _row; do
  [ -n "$_row" ] || continue
  _sign=$(printf '%s' "$_row" | awk -F"$SEP" '{print $1}')
  _f=$(printf   '%s' "$_row" | awk -F"$SEP" '{print $2}')
  _n=$(printf   '%s' "$_row" | awk -F"$SEP" '{print $3}')
  _e=$(printf   '%s' "$_row" | awk -F"$SEP" '{print $4}')
  _sh=$(printf  '%s' "$_row" | awk -F"$SEP" '{print $5}')
  _tx=$(printf  '%s' "$_row" | awk -F"$SEP" '{print $6}')
  _qn=$((_qn + 1))
  _ok=$(( _n - _e ))
  if [ "$_ok" -le 0 ]; then
    printf '  %-6s %s  %s\n' 'ERROR' "$_sign 0/$_n" "$_tx" >> "$WORK/detail"
    BAD=$((BAD + 1)); continue
  fi
  _rate=$(( _f * 100 / _ok ))
  [ "$_f" -gt 0 ] && [ "$_f" -lt "$_ok" ] && { UNSTABLE=$((UNSTABLE + 1)); UNSTABLE_IDS="$UNSTABLE_IDS Q$_qn"; }
  if [ "$_sign" = '+' ]; then POSF=$((POSF + _f)); else NEGF=$((NEGF + _f)); fi
  if [ "$ABSENT" = 1 ]; then
    if [ "$_f" -eq 0 ]; then _v=ok; else _v=FIRED; BAD=$((BAD + 1)); fi
  elif [ "$_sign" = '+' ]; then
    if [ "$_rate" -ge "$THRESH" ]; then _v=ok
    elif [ "$_sh" -gt 0 ]; then _v=SHADOW; BAD=$((BAD + 1)); SHADOWED=$((SHADOWED + 1))
    else _v=MISS; BAD=$((BAD + 1)); fi
  else
    if [ "$_rate" -lt "$THRESH" ]; then _v=ok; else _v=OVER; BAD=$((BAD + 1)); fi
  fi
  printf '  %-6s %s %s/%s  %s\n' "$_v" "$_sign" "$_f" "$_ok" "$_tx" >> "$WORK/detail"
done < "$WORK/rows"

# THE SUMMARY LINE IS A CONTRACT, not a convenience: prove.sh reads `pos` off
# it to compute the ablation delta, and contracts/prove-targets.md pins the
# shape. One line, first on stdout, always emitted.
printf 'trigger-probe: pos %d/%d  neg %d/%d  unstable %d  shadowed %d  truncated %d  errors %d  sessions %d  cost_usd %s\n' \
  "$POSF" "$((NPOS * RUNS))" "$NEGF" "$((NNEG * RUNS))" "$UNSTABLE" "$SHADOWED" "$TRUNCATED" "$ERRORS" "$SESSIONS" "$COST"
printf '  arm        %s  runs=%d  threshold=%d  model=%s\n' \
  "$( [ "$ABSENT" = 1 ] && printf 'ABLATION (nothing planted)' || printf 'planted as %s' "$CLEAN" )" \
  "$RUNS" "$THRESH" "${MODEL:-account-default}"
cat "$WORK/detail"
# COST IS A FLOOR WHENEVER A SESSION WAS CUT OFF, AND SAYING SO IS THE POINT.
# A session killed at the routing decision never emits its result event, so its
# spend is real and uncounted. Printing the floor as if it were the total is
# the same class of error as printing a recall figure over a run that did not
# happen, one layer down.
[ "$TRUNCATED" -gt 0 ] && printf '  COST      cost_usd is a FLOOR, not a total: %d of %d sessions were stopped at the routing decision and never billed a result event. --no-early-stop bills them in full and reports the true sum.\n' "$TRUNCATED" "$SESSIONS"
[ -n "$UNSTABLE_IDS" ] && printf '  UNSTABLE  %s — fired on some runs and not others; one run is a spot check, not a rate\n' "$(printf '%s' "$UNSTABLE_IDS" | sed -e 's/^ //')"
[ "$KEEPWORK" = 1 ] && printf '  workspace %s\n' "$WORK"

# ERRORS ARE COULD-NOT-LOOK AND OUTRANK EVERYTHING. A sweep in which any
# session failed to run has not measured the queries it names, and reporting a
# rate over the survivors is how a half-collected number becomes a fact.
if [ "$ERRORS" -gt 0 ]; then
  printf 'trigger-probe: COULD-NOT-LOOK  %d of %d sessions did not run (no result event, or is_error true — an unauthenticated session looks like a clean zero)\n' "$ERRORS" "$SESSIONS"
  exit 9
fi
# A SHADOWED POSITIVE IS NOT A MISS. The session routed; it routed to a skill of
# the same name already installed in the operator's ~/.claude, which this probe
# planted nothing of and can claim nothing about. Reporting that as a failed
# trigger would blame the card for the environment.
if [ "$SHADOWED" -gt 0 ]; then
  printf 'trigger-probe: COULD-NOT-LOOK  %d positive quer(y|ies) routed to an INSTALLED skill named %s rather than the plant — the card was not the only candidate, so this run measures the box, not the card\n' "$SHADOWED" "$NAME"
  exit 9
fi
[ "$BAD" -eq 0 ] && exit 0
exit 1
