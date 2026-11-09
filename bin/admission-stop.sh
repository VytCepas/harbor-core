#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# SG (harbor#291) — the ONE Stop-event gate: the mechanism for №2 Verification, narrowed to what a shell script can decide without judgement (docs/reference/coverage.md recorded "no Stop gate at all").
# Removed notes: docs/explanation/code-cases/bin-admission-stop.md
#
# TWO RULES DERIVED FROM THE TRANSCRIPT AND NOTHING ELSE:
#   SG-1  a floor surface was edited this session and the floor suite did not
#         run after the last such edit (every part of it, harbor#727)
#   SG-2  a suite this session RAN reported failures, and no later run of that
#         same suite reported none
# AND ONE THAT JUDGES THE COMMAND THE FINAL MESSAGE HANDS OVER (harbor#1284):
#   SG-3  it will not run where it lands; warn by default, see its block below
#
# The transcript is the evidence, not the wording: a gate reading the assistant's prose is satisfied by a rewrite, the opposite of №2. Teeth are defensible here (unlike M5's FailureCapture) because both predicates are orderings over tool calls that happened or did not, not a judgement.
#
# `Stop` is the end of a TURN, not of a session (binary 2.1.241: Stop "Right before Claude concludes its response", SessionEnd "When a session is ending"). At every-turn firing an unverified floor edit would refuse every later turn until a five-minute suite run (§2.11), hence the verdict block records state and refuses ONCE per distinct defect. SessionEnd cannot hold a session open, and `stop_hook_active` names Stop/SubagentStop only.
#
# The harness bounds the blocking (2.1.241): `stop_hook_active` is in the payload (honoured on the first live line below), there is a block cap (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP), and `decision:"block"` carries a `reason` fed back to Claude.
#
# Fail open on every error path, the floor's polarity deliberately inverted: this runs at the end of EVERY turn, so a fail-closed internal error refuses every turn, and HARBOR_ADMISSION_DISABLE is read at startup so it cannot rescue a refusal under way. Missing jq, unreadable transcript, bad JSON: allow. Nothing else in the floor may depend on this gate having fired.
#
# Not caught: a floor surface mutated through Bash (`sed -i`, a redirect, `cp`) inside a CHECKOUT. The tool route carries the path as a field; the Bash route carries text no reliable rule separates from a read (guard-bash withdrew its write rule after six false positives). The config dir's Bash route is already blocked, so the gap is checkout-only and pinned as a PASS in the suite.
set -u
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin

# The loop guard, first: every later line can be skipped safely, this one cannot. `.stop_hook_active` is a JSON boolean and floor_field maps `false` to empty, so a bare string compare is the test.
if [ "$(floor_field '.stop_hook_active')" = "true" ]; then
  floor_log_decision session allow stop-reentry.meta || :
  exit 0
fi

# No stand-down inside a governed repo (harbor#676): this is a GATE for №2, and the five constitutional rules never yield there (harbor#581); contracts/marker.md lists every stand-down site and lint M2 holds it to the code. No session id means allow: there is nowhere to record the one-shot verdict, and the harness always sends one.
[ -n "$(floor_field '.session_id')" ] || exit 0

TX="$(floor_field '.transcript_path')"
[ -n "$TX" ] || exit 0
[ -f "$TX" ] || exit 0
[ -r "$TX" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# The event stream: one jq pass (~93 ms over an 1854-line transcript; a Stop hook that costs a second gets turned off). A tool result or prompt is split into lines only when it holds a literal one of its line rules requires (harbor#559: the same stream, 1.15 -> 0.71 s over 100 MB). Three record kinds, each carrying the tool_use id. The id is what makes SG-2 a fact: a verdict line is believed only when it came out of a command that RAN that suite, else `cat` of an old build log reads as a red suite. The RES branch filters inside jq (a tool result can be a whole file). `.text? // ""` and the array/scalar test on `.content`: both shapes occur. BGT carries a background task id and a Read of a task output file is a CMD record, so a background run pairs through the later read (SG_PAIR). A Read result `N<tab>` prefix is stripped.
STREAM="$(jq -r '
  if .type=="assistant" then
    (.message.content[]? | select(.type=="tool_use") |
      if (.name=="Write" or .name=="Edit" or .name=="NotebookEdit")
        then "MUT\t-\t" + (.input.file_path // "")
      elif .name=="Bash"
        then "CMD\t" + (.id // "-") + "\t" + ((.input.command // "") | gsub("[\n\t]"; " "))
      elif .name=="Read" and ((.input.file_path // "") | test("/tasks/[A-Za-z0-9]+\\.output$"))
        then "CMD\t" + (.id // "-") + "\t" + .input.file_path
      else empty end)
  elif .type=="user" and (.message.content|type)=="string" then
    (.message.content | select(test("erged pull request ")) | split("\n")[]
      | select(test("[Mm]erged pull request [^ ]*#[0-9]+"))
      | "PRM\t-\t" + (capture("[Mm]erged pull request (?<r>[^ ]*)#(?<n>[0-9]+)") | .r + "#" + .n))
  elif .type=="user" then
    (.message.content[]? | select(.type=="tool_result") |
      (.tool_use_id // "-") as $id |
      (if (.content|type)=="array"
         then ([.content[]? | .text? // ""] | join("\n"))
         else (.content|tostring) end)
      | select(test("Output is being written to: |passed, |rules, | results: /|github\\.com/|erged pull request "))
      | split("\n")[] | sub("^ *[0-9]+\t"; "")
      | if test("^Command .*Output is being written to: [^ ]*/tasks/[A-Za-z0-9]+\\.output") then "BGT\t" + $id + "\t" + (capture("/tasks/(?<t>[A-Za-z0-9]+)\\.output") | .t)
        elif test("^[a-z][a-z0-9 .-]*: [0-9]+ (passed|rules), [0-9]+ (failed|violations)") then "RES\t" + $id + "\t" + .
        elif test("^ *note: [0-9]+ passed.* results: /") then "RSF\t" + $id + "\t" + (capture(" results: (?<p>/[^ ]+)") | .p)
        elif test("github\\.com/[^ ]+/pull/[0-9]+") then "PRU\t" + $id + "\t" + (capture("github\\.com/(?<r>[^/ ]+/[^/ ]+)/pull/(?<n>[0-9]+)") | .r + "#" + .n)
        elif test("[Mm]erged pull request [^ ]*#[0-9]+") then "PRM\t-\t" + (capture("[Mm]erged pull request (?<r>[^ ]*)#(?<n>[0-9]+)") | .r + "#" + .n)
        else empty end)
  else empty end' "$TX" 2>/dev/null)" || exit 0

# ── SG-3 · a command handed to the operator will not run where it lands (harbor#1284) ─
# The one rule here that reads the MESSAGE, and that is not a breach of "evidence, not
# wording": the handed-over command IS the artefact, so its text is what is judged. A
# handover is a `! …` line (a fence opened by one stays `!` to its end); P4 also reads
# fenced lines, because the terminal handover it judges is written without the `!`.
#   P1 a `!` command waits on a terminal answer `!` cannot give: deploy takes No, sudo fails
#   P2 a `!` command outlasts 2 minutes: `!` moves it to the background, where the operator
#      loses it (replay 2026-10-17: "is it on?" three times, the same merge chain re-run)
#   P3 a `!` command calls bare gh, which the shim runs as the App (bang-gh-runs-as-the-app)
#   P4 an install or deploy runs while a PR this session opened is unmerged: it installs main
# `gcloud auth login` (its browser flow ran to exit 0 under `!`) and `cd ~/` under `!` (ran clean in the transcripts) are NOT predicates.
# SG3_TTY names every bin/ script that prompts, with the flag that makes it prompt; the
# suite fails when a bin/*.sh reads /dev/tty or prints [y/N] and is missing here.
# Mode: warn tells the operator (systemMessage) and holds nothing; block refuses once like
# SG-1/SG-2. HARBOR_ADMISSION_SG3=off|warn|block, read from the session's env.
SG3_TTY='deploy.sh --apply'
SG3_MODE="${HARBOR_ADMISSION_SG3:-warn}"
case "$SG3_MODE" in off|warn|block) ;; *) SG3_MODE=warn ;; esac
SG3=""
if [ "$SG3_MODE" != off ]; then
  SG3_MSG="$(floor_field '.last_assistant_message')"
  # an older payload carries no message: the last assistant text in the transcript is it
  [ -n "$SG3_MSG" ] || SG3_MSG="$(tail -n 400 "$TX" | jq -rs '[.[] | select(.type=="assistant")
    | [.message.content[]? | select(.type=="text") | .text] | select(length > 0) | join("\n")] | last // empty' 2>/dev/null)"
fi
if [ -n "${SG3_MSG:-}" ]; then
  # opened = a /pull/N printed by a `pr create` this session ran; merged = any "Merged pull request …#N"
  SG3_OPEN="$(printf '%s\n' "$STREAM" | awk -F '\t' '
    $1 == "CMD" && $3 ~ /(^|[ \t])pr[ \t]+create([ \t]|$)/ { pc[$2] = 1 }
    $1 == "PRU" && ($2 in pc) { open[$3] = 1 }
    $1 == "PRM" { delete open[$3] }
    END { for (n in open) printf "%s ", n }')"
  export SG3_OPEN SG3_TTY
  SG3="$(printf '%s\n' "$SG3_MSG" | awk '
    BEGIN { n = split(ENVIRON["SG3_OPEN"], a, " "); for (i = 1; i <= n; i++) if (a[i] != "") open[a[i]] = 1
            n = split(ENVIRON["SG3_TTY"], a, ";"); for (i = 1; i <= n; i++) { split(a[i], b, " "); if (b[1] != "") tty[b[1]] = b[2] } }
    # a PR the message names before the install is one it has sequenced ("merge #77, then deploy")
    function name(r,   k) { while (match(r, /(#|pull\/)[0-9]+/)) { k = substr(r, RSTART, RLENGTH); sub(/^[^0-9]*/, "", k); named[k] = 1; r = substr(r, RSTART + RLENGTH) } }
    function say(p, s) { s = substr(s, 1, 120); if (!((p SUBSEP s) in seen)) { seen[p, s] = 1; print p "\t" s } }
    function check(s, bang,   t, n, w, w2, base, k, num) {
      sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s)
      while (s ~ /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/) sub(/^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/, "", s)
      if (s ~ /^env[ \t]/) { sub(/^env[ \t]+/, "", s)
        while (s ~ /^(-u[ \t]+[^ \t]+|-[A-Za-z]+|[A-Za-z_][A-Za-z0-9_]*=[^ \t]*)[ \t]+/) sub(/^(-u[ \t]+[^ \t]+|-[A-Za-z]+|[A-Za-z_][A-Za-z0-9_]*=[^ \t]*)[ \t]+/, "", s) }
      sub(/^(command|exec|time|nohup)[ \t]+/, "", s)
      n = split(s, t, /[ \t]+/); w = t[1]; w2 = (n > 1) ? t[2] : ""
      if (w == "") return
      if (w == "sh" || w == "bash" || w == "zsh") { w = w2; w2 = (n > 2) ? t[3] : "" }
      if (w ~ /(^|\/)harbor$/ && w2 ~ /^[a-z]+$/) w = w2 ".sh"
      base = w; sub(/^.*\//, "", base)
      if (s ~ /(^|[ \t])pr[ \t]+merge[ \t]+[0-9]+/) { k = s; sub(/^.*pr[ \t]+merge[ \t]+/, "", k); sub(/[^0-9].*$/, "", k); merged[k] = 1 }
      if (bang) {
        if ((base in tty) && (tty[base] == "-" || s ~ ("(^|[ \t])" tty[base] "([ \t=]|$)"))) say("P1", s)
        else if (w == "sudo" || (base == "gh" && w2 == "auth" && t[3] == "login" && s !~ /--with-token/)) say("P1", s)
        if (s ~ /(^|[ \t])--watch([ \t=]|$)/ || w == "watch" || w == "until" || w == "while" || base == "wait-for" \
            || (base == "gh" && w2 == "run" && t[3] == "watch") || (w == "tail" && s ~ /[ \t]-[A-Za-z]*[fF]/) \
            || (w == "sleep" && (w2 + 0 >= 120 || w2 ~ /^[0-9.]+[mhd]$/))) say("P2", s)
        if (w == "gh") say("P3", s)
      }
      if ((base ~ /^(deploy|[a-z-]+-install)\.sh$/ && s ~ /(^|[ \t])--apply([ \t=]|$)/) || (w == "just" && w2 == "install" && s !~ /--check/))
        for (k in open) { num = k; sub(/^.*#/, "", num); if (!(num in merged) && !(num in named)) say("P4", k " " s) }
    }
    /^[ \t]*(```|~~~)/ { fence = !fence; fb = 0; next }
    { l = $0; sub(/^[ \t>]*(([-*+]|[0-9]+[.)])[ \t]+)?/, "", l)
      if (substr(l, 1, 2) == "`!") { l = substr(l, 2); i = index(l, "`"); if (i) l = substr(l, 1, i - 1) }
      bang = 0
      if (l ~ /^![ \t]/) { bang = 1; l = substr(l, 2); if (fence) fb = 1 }
      else if (fence && fb) bang = 1
      if (!bang && !fence) { name($0); next }
      q = "\047"; gsub(q "[^" q "]*" q, "Q", l); gsub(/"[^"]*"/, "Q", l)  # a quoted --command runs elsewhere
      gsub(/&&|\|\||\$\(|[;|(`]/, "\n", l)
      ns = split(l, seg, "\n"); for (j = 1; j <= ns; j++) check(seg[j], bang)
      name($0) }')"
  # P4's "unmerged" is read live: a merge made in the browser never reaches the transcript, and
  # the week's replay flagged PRs merged a day before. No answer within 4s drops the finding.
  _sg3_state() { # <owner/repo> <n> -> OPEN | MERGED | CLOSED, or nothing
    _sf="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX" 2>/dev/null)" || return 0
    ( gh pr view "$2" -R "$1" --json state -q .state > "$_sf" 2>/dev/null ) &
    _sp=$!; _si=0
    while kill -0 "$_sp" 2>/dev/null && [ "$_si" -lt 40 ]; do sleep 0.1; _si=$((_si + 1)); done
    kill "$_sp" 2>/dev/null; cat "$_sf" 2>/dev/null; rm -f "$_sf"
  }
  SG3_KEEP=" "
  for _k in $(printf '%s\n' "$SG3" | awk -F '\t' '$1 == "P4" { sub(/ .*/, "", $2); print $2 }' | sort -u); do
    case "$_k" in */*'#'[0-9]*) ;; *) continue ;; esac
    [ "$(_sg3_state "${_k%#*}" "${_k##*#}")" = OPEN ] && SG3_KEEP="$SG3_KEEP$_k "
  done
  export SG3_KEEP
  SG3="$(printf '%s\n' "$SG3" | awk -F '\t' '$1 != "P4" { if (NF) print; next } { k = $2; sub(/ .*/, "", k); if (index(ENVIRON["SG3_KEEP"], " " k " ")) print }')"
fi
[ -n "$STREAM" ] || [ -n "$SG3" ] || exit 0

# One suite-name key, shared by SG-1 and SG-2 (harbor#1176): a labelled summary `<label> <rc> <verdict>` puts its label before the suite name; strip through the last ` <rc> `.
SG_SUITE_FN='function suite_key(s) { sub(/^.* [0-9]+ /, "", s); return s }'

# ── WHICH TOOL CALLS PRODUCED A VERDICT, SHARED BY SG-1 AND SG-2 ────────────
# A suite command (foreground), or a read of the task output file of a background
# suite command this session launched: a `cat` of any other log pairs with nothing.
# `[-.]test`: hooks/injection-rule/packs.test.sh is a suite too.
SG_PAIR='
  $1 == "CMD" { if ($3 ~ /([-.]test|suite-run|lint-conventions|floor-equiv|admission-equivalence|pass-score)[a-z-]*\.sh/) ran[$2] = 1
                else for (t in bg) if (index($3, "tasks/" t ".output")) ran[$2] = 1 }
  $1 == "BGT" && ($2 in ran) { bg[$3] = 1 }'

# ── SG-1 · a floor surface was edited and the suite did not run after it ────
# Path-scoped to the floor's own file set: bin/admission-*.sh, bin/library-admission.sh, bin/floor-*.sh, bin/admission-normalize.awk and the old guard-*.sh names (harbor#961 W6); `bin/` is required.
# Only the FULL suite counts as evidence: since harbor#727 that is tests/admission/baseline/baseline.test.sh plus every <part>.test.sh, a verdict line from EVERY part, from a suite-invoking command, after the edit (one part is a fraction, harbor#679). The pre-commit smoke prints another name and is refused (№2.7: unavailable verifier means defer, never substitute). AFTER, not merely PRESENT: a run before the edit verified the code it replaced.
# Harbor's floor surfaces only (harbor#676): once the gate stopped standing down in governed repos, a project's own bin/guard-auth.sh matched the pattern and demanded Harbor's floor-test (§2.11). A path counts only when the tree above its bin/ holds tests/admission/baseline/baseline.test.sh, or it is the installed floor in the config dir; the parts owed are that tree, or for the config dir the cwd, else the main part alone. Every other MUT record is dropped before the rule reads; SG-2 reads the unfiltered stream.
# The root check runs once per distinct path, not per stream line (the first cut cost +215 ms per turn end): one awk pass lists floor-shaped paths and the approved set reaches the rule through ENVIRON, the one channel POSIX awk does not escape-process.
_sg_cfgbin="$(floor_config_dir)/bin"
_sg_cwd="$(floor_field '.cwd')"
_sg_cands="$(printf '%s\n' "$STREAM" | awk -F '\t' '
  $1 == "MUT" && $3 ~ /(^|\/)bin\/((guard|floor|admission)-[a-z-]*\.(sh|awk)|library-admission\.sh)$/ { print $3 }' | sort -u)"
_sg_parts() { # <tree> -> the floor parts' names, space-separated (harbor#727)
  for _f in "$1"/tests/admission/baseline/*.test.sh; do
    [ -f "$_f" ] && printf '%s ' "$(basename "$_f" .sh)"
  done
  return 0
}
SG1_OK=""; SG1_PARTS=""
while IFS= read -r _p; do
  [ -n "$_p" ] || continue
  _a="$_p"; case "$_a" in /*) ;; *) _a="${_sg_cwd%/}/$_a" ;; esac
  if [ -f "${_a%/bin/*}/tests/admission/baseline/baseline.test.sh" ]; then
    SG1_OK="$SG1_OK$_p
"; SG1_PARTS="$SG1_PARTS $(_sg_parts "${_a%/bin/*}")"
  elif [ "${_a%/*}" = "$_sg_cfgbin" ]; then
    SG1_OK="$SG1_OK$_p
"
  fi
done <<EOF
$_sg_cands
EOF
[ -n "${SG1_PARTS# }" ] || { [ -n "$_sg_cwd" ] && SG1_PARTS="$(_sg_parts "$_sg_cwd")"; }
[ -n "${SG1_PARTS# }" ] || SG1_PARTS="baseline.test"   # harbor#961 W2: the main part, by the label it prints
export SG1_OK SG1_PARTS
# A background run launched before the edit verified the code it replaced: the edit drops it.
SG1="$(printf '%s\n' "$STREAM" | awk -F '\t' "$SG_SUITE_FN$SG_PAIR"'
  BEGIN { n = split(ENVIRON["SG1_OK"], a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") ok[a[i]] = 1
          n = split(ENVIRON["SG1_PARTS"], a, " "); for (i = 1; i <= n; i++) if (a[i] != "") need[a[i]] = 1 }
  $1 == "MUT" && ($3 in ok) { mut = NR; path = $3; split("", seen); split("", bg); split("", rsf) }
  $1 == "RES" && mut > 0 && ($2 in ran) { c = index($3, ":"); if (c > 1) { k = suite_key(substr($3, 1, c - 1)); if (k in need) seen[k] = 1 } }
  $1 == "RSF" && mut > 0 && ($2 in ran) { rsf[$3] = 1 }
  END { if (mut > 0) { for (k in need) if (!(k in seen)) miss = miss " " k
          if (miss != "") { print "P\t" path; print "M\t" miss; for (f in rsf) print "F\t" f } } }
')"
# harbor#1392: test-suite-run.sh prints no per-suite verdict line, so a part it ran is read from the
# --results file its own summary named after the edit: a `pass` row clears that part, any other row does not.
if [ -n "$SG1" ]; then
  _sg1_miss="$(printf '%s\n' "$SG1" | awk -F '\t' '$1 == "M" { print $2 }')"
  _sg1_pass="$(printf '%s\n' "$SG1" | awk -F '\t' '$1 == "F" { print $2 }' | while IFS= read -r _f; do
    [ -f "$_f" ] && awk -F '\t' '$1 == "pass" && $5 ~ /(^|\/)tests\/admission\/baseline\/[^\/]+\.sh$/ {
      s = $5; sub(/^.*\//, "", s); sub(/\.sh$/, "", s); print s }' "$_f" 2>/dev/null
  done)"
  export _sg1_pass
  _sg1_left="$(printf '%s\n' "$_sg1_miss" | awk 'BEGIN { n = split(ENVIRON["_sg1_pass"], a, "\n"); for (i = 1; i <= n; i++) p[a[i]] = 1 }
    { for (i = 1; i <= NF; i++) if (!($i in p)) print $i }')"
  if [ -n "$_sg1_left" ]; then SG1="$(printf '%s\n' "$SG1" | awk -F '\t' '$1 == "P" { print $2 }')"; else SG1=""; fi
fi

# ── SG-2 · a suite THIS SESSION RAN went red and no later run of it went green ─
# Keyed on the suite NAME, so a green normalize-test cannot vouch for a red floor-test. Last verdict per name wins, so fix-and-rerun is invisible. `floor-test --smoke` and `floor-test` are different keys: folding them would let a smoke clear a red full run (№2.7). The id gate comes first: a verdict whose tool_use id belongs to no suite command (SG_PAIR) was READ, not produced.
SG2="$(printf '%s\n' "$STREAM" | awk -F '\t' "$SG_SUITE_FN$SG_PAIR"'
  $1 == "RES" && ($2 in ran) {
    line = $3
    n = index(line, ":")
    if (n < 2) next
    name = suite_key(substr(line, 1, n - 1))
    rest = substr(line, n + 1)
    bad = 0
    if (match(rest, /[0-9]+ (failed|violations)/)) {
      tok = substr(rest, RSTART, RLENGTH)
      if (tok + 0 > 0) bad = 1
    }
    last[name] = bad
    text[name] = line
  }
  END { for (k in last) if (last[k]) print text[k] }
')"

if [ -z "$SG1" ] && [ -z "$SG2" ] && [ -z "$SG3" ]; then
  floor_log_decision session allow stop-clean.meta || :
  exit 0
fi

# ── ONCE PER STATE, NOT ONCE PER TURN ──────────────────────────────────────
# Stop fires at the end of every turn (SessionEnd cannot block), so demanding a ~5-minute suite run after the edit AND after writing its assertion would get the gate switched off (§2.11). So block ONCE per distinct unverified state: the key is a digest of the offending path and the red verdicts, so ignoring the nudge does not trap the turn while a NEW unverified edit is a new state. The cost, deliberate: the model may proceed after one refusal; the alternative traps a session and the harness cap would end it anyway. Keyed on the path, three floor files edited unverified are refused three times.
# SG-2 keys on the red suites' NAMES, not their counts, so a re-run that moves the counts is the same state. Given up: a different new failure in that suite goes unflagged until it is green once.
SG2_NAMES="$(printf '%s\n' "$SG2" | awk "$SG_SUITE_FN"'{ c = index($0, ":"); if (c > 1) print suite_key(substr($0, 1, c - 1)) }' | sort -u | tr '\n' ';')"
SG_KEY="$(printf 'SG1:%s|SG2:%s|SG3:%s' "$SG1" "$SG2_NAMES" "$(printf '%s' "$SG3" | sort | tr '\n' ';')" | floor_sha 2>/dev/null)"
SG_SID="$(floor_field '.session_id')"
case "$SG_SID" in ''|*[!A-Za-z0-9_-]*) SG_SID='' ;; esac
SG_SEEN=""
if [ -n "$SG_KEY" ] && [ -n "$SG_SID" ]; then
  # Digests and a session id only, never a path or command text: this file lives under the private config dir.
  SG_SEEN="$(floor_config_dir)/.helm-stop-gate/$SG_SID"
  if [ -f "$SG_SEEN" ] && "$FLOOR_GREP" -qxF -- "$SG_KEY" "$SG_SEEN" 2>/dev/null; then
    floor_log_decision session allow stop-already-said.meta || :
    exit 0
  fi
fi

# ── THE VERDICT ────────────────────────────────────────────────────────────
# One block carrying BOTH findings (two would spend the harness cap on one turn's work). The escape hatch named is the true one: HARBOR_ADMISSION_DISABLE is read at session start and cannot lift a refusal under way; what bounds this is the harness cap.
MSG="HELM STOP GATE — the turn was BLOCKED because this session's own transcript does not carry the evidence №2 requires."
if [ -n "$SG1" ]; then
  MSG="$MSG SG-1: ${SG1} was edited this session and the floor suite did not run after that edit: every part, tests/admission/baseline/baseline.test.sh and each tests/admission/baseline/<part>.test.sh. Run them — a T_SMOKE=1 run does not count, it is the smoke and not the suite — or say plainly which assertion you are deferring and why."
fi
if [ -n "$SG2" ]; then
  MSG="$MSG SG-2: the last verdict for a suite this session ran is not clean — $(printf '%s' "$SG2" | tr '\n' ';'). Re-run it green, or say which run was a deliberate mutation and what it proved."
fi
MSG="$MSG (Stop fires at the end of every turn, so this refusal is raised ONCE for this state and the next turn is not held; a new unverified edit is a new state. HARBOR_ADMISSION_DISABLE) is read at session start and cannot lift a refusal already under way.)"

# The state is recorded BEFORE the verdict is emitted, so a caller that reads stdout and exits cannot leave the next turn refused for the same reason. Best-effort: if the record cannot be written the gate still blocks; `|| :` keeps that from becoming a non-zero exit.
if [ -n "$SG_SEEN" ]; then
  { mkdir -p "$(dirname "$SG_SEEN")" && printf '%s\n' "$SG_KEY" >> "$SG_SEEN"; } 2>/dev/null || :
fi

# SG-3 speaks to the operator, who is the one about to run the command. In warn mode it
# holds nothing: alone it is a systemMessage, beside SG-1/SG-2 it rides their block.
SG3T=""
if [ -n "$SG3" ]; then
  SG3T="SG-3 [stop:handover-shell] a command handed over will not run where it lands:$(printf '%s\n' "$SG3" | awk -F '\t' '
    $1 == "P1" { printf " `%s` waits on a terminal answer `!` cannot give: run it in a terminal;", $2 }
    $1 == "P2" { printf " `%s` can run past 2 minutes, and `!` then moves it out of sight to the background: run it in a terminal, or leave the waiting to me;", $2 }
    $1 == "P3" { printf " `%s` calls bare gh, which under `!` runs as the App: use /opt/homebrew/bin/gh;", $2 }
    $1 == "P4" { n = $2; sub(/ .*/, "", n); c = $2; sub(/^[^ ]* /, "", c); printf " `%s` installs main while PR %s this session opened is unmerged: merge it first;", c, n }')"
fi
if [ -n "$SG1$SG2" ] || [ "$SG3_MODE" = block ]; then
  [ -n "$SG1$SG2" ] || MSG="HELM STOP GATE — the turn was BLOCKED."
  [ "$SG3_MODE" != block ] || [ -z "$SG3T" ] || MSG="$MSG $SG3T"
  jq -cn --arg m "$MSG" --arg o "$MSG${SG3T:+ }$([ "$SG3_MODE" = block ] || printf '%s' "$SG3T")" \
    '{decision:"block", reason:$m, systemMessage:$o}' 2>/dev/null || exit 0
else
  jq -cn --arg o "$SG3T" '{systemMessage:$o}' 2>/dev/null || exit 0
fi

# One ledger record PER RULE that fired, not a fused id: audit-triage.sh ranks by rule token and a compound would rank as a never-before-seen rule.
[ -n "$SG1" ] && { floor_log_decision session gate floor-edited-unverified.meta || :; }
[ -n "$SG2" ] && { floor_log_decision session gate suite-red-at-exit.meta || :; }
if [ -n "$SG3" ]; then
  if [ "$SG3_MODE" = block ]; then floor_log_decision session gate handover-shell.meta || :
  else floor_log_decision session advise handover-shell.meta || :; fi
fi
exit 0
