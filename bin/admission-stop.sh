#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-${HELM_DISABLE_FLOOR:-0}}" = "1" ] && exit 0
# SG (harbor#291) — the ONE Stop-event gate. docs/reference/coverage.md:86 read "Harbor has no
# Stop gate at all", and docs/reference/coverage.md:38 read "№2 Verification is Harbor's longest
# constitutional rule and has no mechanism, in a file that says 'a rule with no
# mechanism is a wish'". This is that mechanism, narrowed to the part a shell
# script can decide without judgement.
#
# TWO RULES DERIVED FROM THE TRANSCRIPT AND NOTHING ELSE:
#   SG-1  a floor surface was edited this session and the floor suite did not
#         run after the last such edit (every part of it, harbor#727)
#   SG-2  a suite this session RAN reported failures, and no later run of that
#         same suite reported none
# AND ONE THAT JUDGES THE COMMAND THE FINAL MESSAGE HANDS OVER (harbor#1284):
#   SG-3  it will not run where it lands; warn by default, see its block below
#
# THE TRANSCRIPT IS THE EVIDENCE, NOT THE WORDING. That is upstream's whole
# insight and docs/reference/coverage.md:250 records it: "VerificationGate.hook.ts grades
# evidence FROM THE TRANSCRIPT, not from the message's wording, so rewording
# never passes it." A gate that read the assistant's prose would be satisfied by
# a rewrite, which is the opposite of №2.
#
# WHY TEETH ARE DEFENSIBLE HERE AND WERE NOT FOR M5. FailureCapture declined to
# block because "a failure worth healing" is a judgement and fails
# policy/constitution.md's `deterministic` criterion. Neither rule below is a judgement:
# what counts as evidence is defined by the repo (its own suite), and both
# predicates are orderings over tool calls that either happened or did not.
#
# `Stop` IS THE END OF A TURN, NOT THE END OF A SESSION, and everything about the
# cadence below follows from that. Measured, from the binary's own event summaries
# at 2.1.241:
#     Stop:        "Right before Claude concludes its response"
#     SessionEnd:  "When a session is ending"
# The first cut of this gate was designed and documented against the wrong one of
# those. The blocking mechanism was unaffected — the binary's operator-facing
# string is "A hook blocked the turn from ending" — but the CADENCE was: at
# every-turn firing, an unverified floor edit would refuse every subsequent turn
# until a five-minute suite run, including the turn spent writing the assertion
# for it. That is §2.11 in one paragraph, which is why the verdict block records
# state and refuses ONCE per distinct defect.
#
# SessionEnd was considered and is the wrong event even though its name fits: a
# session that is already ending cannot be held open, and the reference's
# `stop_hook_active` contract names Stop/SubagentStop only. A nudge nobody can act
# on is a log line, not a gate.
#
# THE HARNESS BOUNDS THE BLOCKING, not this script's care. Measured against the
# binary at 2.1.241, all four facts from its embedded reference:
#   • the payload carries `stop_hook_active`, and the documented pattern is
#     "For Stop/SubagentStop hooks, check stop_hook_active in the input and
#     return success while it's true" — honoured on the FIRST live line below
#   • there is a block cap, raisable with CLAUDE_CODE_STOP_HOOK_BLOCK_CAP and
#     counted as `tengu_stop_hook_block_count`
#   • `decision:"block"` carries a `reason` that is "fed back to Claude"
#   • the operator sees "A hook blocked the turn from ending"
#
# FAIL OPEN ON EVERY ERROR PATH, and this is the one place the floor's usual
# polarity is deliberately inverted. admission-integrity.sh is fail-CLOSED at
# SessionStart and that is right there: a session that will not START costs one
# restart. Here the blast radius of the opposite choice is worse than it first
# looks — this hook runs at the end of EVERY turn, so a fail-closed internal error
# refuses every turn for the rest of the session, and HARBOR_ADMISSION_DISABLE is read
# at startup so it cannot rescue a refusal already under way. Missing jq,
# unreadable transcript, bad JSON, any surprise ⇒ allow. The cost is a missed
# nudge; that is the correct trade at this event, and it is why nothing else in
# the floor may depend on this gate having fired.
#
# WHAT IT DOES NOT CATCH, enumerated rather than left to be discovered. A floor
# surface mutated through Bash (`sed -i`, a redirect, `cp`) inside a CHECKOUT is
# invisible here: the tool route (Write/Edit/NotebookEdit) carries the path as a
# field, and the Bash route carries it as text that no reliable rule separates
# from a read of the same path — "is this command WRITING that file?" is the
# question guard-bash withdrew a rule over after six false positives in pass 10.
# Inside the CONFIG dir the floor already blocks that route, so the gap is
# checkout-only. It is a real gap and pinned as a PASS in the suite, so the day
# one of those starts blocking, this rule has stopped being path-scoped.
set -u
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin

# ── THE LOOP GUARD, FIRST, BEFORE ANY OTHER TEST ────────────────────────────
# Not merely early — first. Every line after this one can be skipped safely; this
# one cannot, and putting it anywhere else invites a later edit to insert work
# above it. `.stop_hook_active` is a JSON boolean, and floor_field's `// empty`
# maps `false` to the empty string, so a bare string compare is the whole test.
if [ "$(floor_field '.stop_hook_active')" = "true" ]; then
  floor_log_decision session allow stop-reentry.meta || :
  exit 0
fi

# IT DOES NOT STAND DOWN INSIDE A GOVERNED REPO (harbor#676). This line was
# `floor_engine_stand_down && exit 0`, copied from the two work-log Stop hooks
# (worklog-push.sh, memory-harvest.sh). Those are ENGINE hooks: standing down
# means not acting, and no rule is withdrawn. This is a GATE for №2 Verification,
# and harbor#581 decided the five constitutional rules never yield inside a
# governed repo. contracts/marker.md lists every stand-down site and lint M2
# holds that list to the code, so re-adding a stand-down here fails the lint
# unless it is declared, with a ticket.
#
# NO SESSION ID ⇒ ALLOW. The stand-down used to cover this too: with no id there
# is nowhere to record the one-shot verdict, so the gate would refuse at every turn
# end. The harness always sends session_id; fail open on the shape it never sends.
[ -n "$(floor_field '.session_id')" ] || exit 0

TX="$(floor_field '.transcript_path')"
[ -n "$TX" ] || exit 0
[ -f "$TX" ] || exit 0
[ -r "$TX" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# ── THE EVENT STREAM ───────────────────────────────────────────────────────
# One jq pass, order preserved, three record kinds, each carrying the tool_use id
# where there is one. Measured at 93ms over an 1854-line transcript on this box,
# which is why this is a single pass and not a grep-per-rule: a Stop hook that
# costs a second is a Stop hook the operator turns off.
#
# THE ID IS WHAT MAKES SG-2 A FACT RATHER THAN A HEURISTIC. A verdict line is
# only believed when it came out of a command that RAN that suite. Without the
# pairing, `cat` of an old build log — or of a commit message quoting one — reads
# as a red suite this session ran, which is a false positive on a rule whose
# whole job is to be believed.
#
# The RES branch filters INSIDE jq. A tool result can be a whole file, and
# emitting them all to be filtered in the shell was the first shape — it moved
# megabytes through a pipe to keep a dozen lines.
#
# `.text? // ""` and the array/scalar test on `.content`: both shapes occur, and
# a missing `.text` on a non-text block must not abort the whole extraction.
#
# BGT carries a background task's id (launched so, or moved there at the timeout),
# and a Read of a task output file is a
# CMD record, so a run in the background pairs through the later read of its own
# output file (SG_PAIR below). A Read result's `N<tab>` line prefix is stripped.
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
    (.message.content | split("\n")[]
      | select(test("[Mm]erged pull request [^ ]*#[0-9]+"))
      | "PRM\t-\t" + (capture("[Mm]erged pull request (?<r>[^ ]*)#(?<n>[0-9]+)") | .r + "#" + .n))
  elif .type=="user" then
    (.message.content[]? | select(.type=="tool_result") |
      (.tool_use_id // "-") as $id |
      (if (.content|type)=="array"
         then ([.content[]? | .text? // ""] | join("\n"))
         else (.content|tostring) end)
      | split("\n")[] | sub("^ *[0-9]+\t"; "")
      | if test("^Command .*Output is being written to: [^ ]*/tasks/[A-Za-z0-9]+\\.output") then "BGT\t" + $id + "\t" + (capture("/tasks/(?<t>[A-Za-z0-9]+)\\.output") | .t)
        elif test("^[a-z][a-z0-9 .-]*: [0-9]+ (passed|rules), [0-9]+ (failed|violations)") then "RES\t" + $id + "\t" + .
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
# `gcloud auth login` is NOT P1: its browser flow ran to exit 0 under `!` (replay, 7419e469).
# `cd ~/` under `!` was in the issue and is NOT a predicate: `! cd ~/port/… && …` ran
# clean in the transcripts, and the trap it names is the model's own tool calls.
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

# ── ONE SUITE-NAME KEY, SHARED BY SG-1 AND SG-2 (harbor#1176) ───────────────
# A labelled summary `<label> <rc> <verdict>` puts its label before the suite name.
# Both rules key verdicts by name, so both take the key through this one function,
# prepended to each awk program: strip through the last ` <rc> `.
SG_SUITE_FN='function suite_key(s) { sub(/^.* [0-9]+ /, "", s); return s }'

# ── WHICH TOOL CALLS PRODUCED A VERDICT, SHARED BY SG-1 AND SG-2 ────────────
# A suite command (foreground), or a read of the task output file of a background
# suite command this session launched: a `cat` of any other log pairs with nothing.
# `[-.]test`: hooks/injection-rule/packs.test.sh is a suite too.
SG_PAIR='
  $1 == "CMD" { if ($3 ~ /([-.]test|lint-conventions|floor-equiv|pass-score)[a-z-]*\.sh/) ran[$2] = 1
                else for (t in bg) if (index($3, "tasks/" t ".output")) ran[$2] = 1 }
  $1 == "BGT" && ($2 in ran) { bg[$3] = 1 }'

# ── SG-1 · a floor surface was edited and the suite did not run after it ────
# PATH-SCOPED, and the pattern is the floor's own file set: bin/admission-*.sh, bin/library-admission.sh,
# bin/floor-*.sh, bin/floor-normalize.awk, and the old guard-*.sh names (harbor#961 W6). `bin/` is required, so a note called
# guard-notes.sh in a docs dir is not a floor surface.
#
# ONLY THE FULL SUITE COUNTS AS EVIDENCE. Since harbor#727 the floor suite is
# tests/admission/baseline/baseline.test.sh plus every tests/admission/baseline/<part>.test.sh, so the
# evidence is a verdict line from EVERY part, from a suite-invoking command, after
# the edit: one part is a fraction, as a shard was (harbor#679). The pre-commit
# smoke prints `baseline.test smoke: …`, another name, so it is refused like the
# `--smoke` it replaced (№2.7 — "unavailable verifier means defer, never
# substitute"): it is the right depth for a commit gate, not for "verified".
#
# AFTER, not merely PRESENT. A run that happened BEFORE the edit verified the
# code the edit replaced. Ordering is the predicate, and it is pinned in both
# directions.
#
# HARBOR'S floor surfaces, not every file with a floor-shaped NAME (harbor#676,
# found by review on #684). Once this gate stopped standing down inside governed
# repos, a project's own bin/guard-auth.sh matched the pattern, and the gate
# demanded Harbor's floor-test for code that suite never touches — §2.11. So a
# path counts only when the tree above its bin/ holds tests/admission/baseline/baseline.test.sh (a
# Harbor checkout or worktree, wherever it lives: the tree whose suite would verify
# the edit), or when it is the installed floor in the config dir. The parts owed
# are that tree's; the config dir has none beside it, so it owes the cwd's, else
# the main part alone. Every other MUT
# record is dropped before the rule reads the stream; SG-2 reads the unfiltered one.
#
# THE ROOT CHECK RUNS ONCE PER DISTINCT PATH, never once per stream line. The
# first cut filtered the whole stream in a shell loop and cost +215 ms per turn
# end on a 7,606-line transcript. So one awk pass lists the few floor-shaped
# paths, the shell tests each once, and the rule reads the approved set through
# ENVIRON: that is the only channel POSIX awk offers that does not
# escape-process the value.
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
  $1 == "MUT" && ($3 in ok) { mut = NR; path = $3; split("", seen); split("", bg) }
  $1 == "RES" && mut > 0 && ($2 in ran) { c = index($3, ":"); if (c > 1) { k = suite_key(substr($3, 1, c - 1)); if (k in need) seen[k] = 1 } }
  END { if (mut > 0) for (k in need) if (!(k in seen)) { print path; exit } }
')"

# ── SG-2 · a suite THIS SESSION RAN went red and no later run of it went green ─
# Keyed on the suite NAME, so a green normalize-test cannot vouch for a red
# floor-test. Last verdict per name wins; a later green clears an earlier red,
# which is what makes an ordinary fix-and-rerun cycle invisible to this rule.
#
# `floor-test --smoke` and `floor-test` are DIFFERENT keys on purpose: they are
# runs at different depths, and folding them would let the smoke clear a red full
# run — №2.7 again, from the other side.
#
# The id gate is the first clause: a verdict whose tool_use id belongs to no
# suite-invoking command, nor to a read of a background suite's own output file
# (SG_PAIR), is a verdict this session READ, not one it produced.
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
# `Stop` is NOT the session-end event. The binary's own summary is "Right before
# Claude concludes its response" — it fires at the end of EVERY turn, and
# SessionEnd ("When a session is ending") is the other one and cannot block. The
# first cut of this gate was written against the wrong premise and would have
# blocked every turn until the suite ran.
#
# WHY THAT WOULD HAVE BEEN A GUARD PEOPLE SWITCH OFF. Working on a guard is: edit
# it, write the assertion, run the suite. floor-test is ~5 minutes. A gate that
# refuses the turn after the edit AND the turn after the assertion is demanding
# two five-minute runs to do one piece of work, and §2.11 says exactly what
# happens next.
#
# So: block ONCE per distinct unverified state. The key is a digest of what is
# wrong — the offending path, and the red verdicts — so ignoring the nudge does
# not trap the turn, while a NEW unverified edit is a new state and says so. The
# nudge also lands at the earliest moment anything can be done about it, which is
# strictly better than the session-end firing this was designed for.
#
# THE COST, STATED: the model may proceed after one refusal. That is deliberate.
# The alternative traps a session, and the harness's own cap would end the
# refusal anyway — at which point the gate would have spent its credibility
# instead of its one useful sentence.
#
# Bounded chattiness: keyed on the path, so a session editing three floor files
# without running the suite is refused three times, not once and not thirty.
# Precision beats quiet here — each refusal names a different real defect.
# SG-2 keys on the red suites' NAMES, not their counts, so a re-run that moves the counts is the
# same state. Given up: a different new failure in that suite goes unflagged until it is green once.
SG2_NAMES="$(printf '%s\n' "$SG2" | awk "$SG_SUITE_FN"'{ c = index($0, ":"); if (c > 1) print suite_key(substr($0, 1, c - 1)) }' | sort -u | tr '\n' ';')"
SG_KEY="$(printf 'SG1:%s|SG2:%s|SG3:%s' "$SG1" "$SG2_NAMES" "$(printf '%s' "$SG3" | sort | tr '\n' ';')" | floor_sha 2>/dev/null)"
SG_SID="$(floor_field '.session_id')"
case "$SG_SID" in ''|*[!A-Za-z0-9_-]*) SG_SID='' ;; esac
SG_SEEN=""
if [ -n "$SG_KEY" ] && [ -n "$SG_SID" ]; then
  # DIGESTS AND A SESSION ID ONLY — never a path, never command text. This file
  # lives under the config dir §3 calls private, and a state record that carried
  # the path would put transcript content into a second place with its own
  # lifetime.
  SG_SEEN="$(floor_config_dir)/.helm-stop-gate/$SG_SID"
  if [ -f "$SG_SEEN" ] && "$FLOOR_GREP" -qxF -- "$SG_KEY" "$SG_SEEN" 2>/dev/null; then
    floor_log_decision session allow stop-already-said.meta || :
    exit 0
  fi
fi

# ── THE VERDICT ────────────────────────────────────────────────────────────
# ONE block carrying BOTH findings. Two Stop blocks in a row would spend the
# harness's cap on what is a single turn's worth of work, and the second refusal
# would arrive after the model had already been told to fix the first.
#
# THE ESCAPE HATCH NAMED HERE IS THE TRUE ONE. The PreToolUse guards print their
# own narrow remedy since harbor#482, and the kill-switch would be a lie at this
# event anyway: the variable is read when the session starts, so it cannot lift a
# refusal already under way. What actually bounds this is the harness's own cap,
# so that is what is said.
MSG="HELM STOP GATE — the turn was BLOCKED because this session's own transcript does not carry the evidence №2 requires."
if [ -n "$SG1" ]; then
  MSG="$MSG SG-1: ${SG1} was edited this session and the floor suite did not run after that edit: every part, tests/admission/baseline/baseline.test.sh and each tests/admission/baseline/<part>.test.sh. Run them — a T_SMOKE=1 run does not count, it is the smoke and not the suite — or say plainly which assertion you are deferring and why."
fi
if [ -n "$SG2" ]; then
  MSG="$MSG SG-2: the last verdict for a suite this session ran is not clean — $(printf '%s' "$SG2" | tr '\n' ';'). Re-run it green, or say which run was a deliberate mutation and what it proved."
fi
MSG="$MSG (Stop fires at the end of every turn, so this refusal is raised ONCE for this state and the next turn is not held; a new unverified edit is a new state. HARBOR_ADMISSION_DISABLE (or HELM_DISABLE_FLOOR) is read at session start and cannot lift a refusal already under way.)"

# THE STATE IS RECORDED BEFORE THE VERDICT IS EMITTED, so a caller that reads
# stdout and exits cannot leave this turn refused and the next one refused again
# for the same reason. Best-effort: if the record cannot be written the gate still
# blocks, which is the one place it is stricter than fail-open — the alternative
# is a refusal it has no memory of, i.e. once per turn, i.e. the shape this whole
# block exists to avoid. `|| :` keeps that failure from becoming a non-zero exit.
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

# One ledger record PER RULE that fired, not a fused id. A compound token would
# be a rule name that appears in no source file, and audit-triage.sh ranks by
# rule token — a fused id would rank as its own never-before-seen rule every
# time the pair coincided.
[ -n "$SG1" ] && { floor_log_decision session gate floor-edited-unverified.meta || :; }
[ -n "$SG2" ] && { floor_log_decision session gate suite-red-at-exit.meta || :; }
if [ -n "$SG3" ]; then
  if [ "$SG3_MODE" = block ]; then floor_log_decision session gate handover-shell.meta || :
  else floor_log_decision session advise handover-shell.meta || :; fi
fi
exit 0
