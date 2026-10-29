#!/usr/bin/env sh
# injection-rule.sh (harbor#173 · A1; renamed from inject-hook.sh, harbor#1272) — the injector. One engine, many rule packs.
#
#   echo '<hook json>' | sh hooks/injection-rule/injection-rule.sh        read the event from stdin
#   sh hooks/injection-rule/injection-rule.sh --list                      what packs exist, and where
#   sh hooks/injection-rule/injection-rule.sh --explain < payload.json    which rules matched, and why
#
# DELIBERATELY ONE FILE (lint G1, docs/explanation/modularity.md): splitting the
# predicate vocabulary from the pack loader would put the two halves of one
# contract in two files, and the thing this replaces is exactly that scatter.
#
# WHY AN ENGINE AND NOT ANOTHER HOOK SCRIPT. bin/govern-hook.sh is 360 lines of
# shell for four rules, and every rule a second repo wants is a second script
# with its own matcher, its own fail-open discipline and its own bugs. That does
# not scale past one repo, and the operator's environment is already four —
# harbor and its workload repos — with more coming. So the shell is written
# ONCE and the rules become DATA: a repo declares `context-rules/<repo>/<id>.md` and
# gets just-in-time governance with no shell of its own.
#
# WHAT MAKES THIS WORTH THE BYTES, MEASURED. E6 (docs/reports/evals.md) ran the same sentence
# two ways: as prose inside a runbook the model had already opened it scored
# 0/4, and injected at the tool call it scored 4/4. E8 then showed that volume in
# the prefix changes nothing — a 595 B constitution and a 17,845 B one both score
# 3.00/3. The variable is not how much you write or where in the prefix you put
# it. It is whether the rule is RESIDENT when the model acts, or has to be
# fetched. Every repo here has a CLAUDE.md whose whole content is "the real
# instructions are in AGENTS.md, read it first", which is the fetch-required
# shape, so those instructions do not bind. This is the fix for that.
#
# INFORM BY DEFAULT, AND THAT IS MEASURED. E6 ran a veto arm and an inform arm
# against the same trap: inform 4/4, veto 3/4, and the veto's one miss was a
# session that stopped to ask instead of acting. Vetoing belongs to the floor
# (guard-bash.sh, guard-egress.sh) where the question is "may this happen at
# all", and a pack that merely wants attention must never reach for it.
#
# THERE IS ONE OPT-IN DENY, AND THIS PARAGRAPH USED TO SAY THERE WAS NONE. It
# said "deliberately no `deny` mode here" for the whole of the time the mode
# existed: PR #262 added the `HARBOR-DECISION deny:` sentinel because a real
# gate had been silently disarmed — bin/govern-hook.sh computes a blocking merge
# verdict, and reaching it through this engine wrapped that verdict as prose,
# which cannot stop a Bash call. Suite green, every red PR merged. A header that
# denies the existence of the blocking path is worse than no header, because a
# reader deciding whether a pack CAN block gets a confident wrong answer. The
# sentinel is exact, opt-in, `run:`-only and PreToolUse-only; the rules that keep
# it from becoming a second floor are stated where it is implemented, below.
#
# CONDITIONAL OR NOTHING (CONSTITUTION §2.11). Every path prints nothing when it
# has nothing true to say. A false positive is a defect, not safety: a guard that
# fires on ordinary work is a guard that gets switched off, and this one is
# especially exposed because it rides on the Bash tool.
#
# FAIL-OPEN EVERYWHERE. No jq, malformed JSON, an unreadable pack, an unknown
# predicate, a `run:` script that errors — every one exits 0 having printed
# nothing. A hook whose failure mode is noise is a hook that gets removed.
set -eu

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left SELF_DIR at the cwd, running ./govern-token.sh from it.
case "$0" in */*) SELF_DIR="${0%/*}" ;; *) SELF_DIR=. ;; esac
[ ! -f "$SELF_DIR/manifest.tsv" ] || SELF_DIR="$SELF_DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries

MODE=hook
case "${1:-}" in
  '')         MODE=hook ;;
  --explain)  MODE=explain ;;
  --list)     MODE=list ;;
  -h|--help)  sed -n '3,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)          printf '  FAIL: injection-rule: unknown flag %s\n  fix: sh %s --help\n' "$1" "$0" >&2; exit 2 ;;
esac

# ── pack discovery ──────────────────────────────────────────────────────────
# TWO TIERS, AND THE ORDER IS THE PRECEDENCE. Box packs carry rules true in every
# session on this machine (the subagent contract, what survives compaction, that
# fetched content is data). Repo packs carry rules true only inside one tree.
#
# THE REPO IS RESOLVED FROM THE SESSION'S CWD, NOT FROM THIS SCRIPT'S LOCATION.
# The installed copy lives in the box config dir and must serve whatever repo the
# session is standing in; resolving from $0 would make every session load
# harbor's rules. CLAUDE_PROJECT_DIR is what the harness sets; cwd is the
# fallback for a hand-run.
REPO="$(cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO" ] || REPO="${CLAUDE_PROJECT_DIR:-$PWD}"

# THE TWO TIERS CAN BE THE SAME DIRECTORY, and then every box pack fires twice.
# Measured, not imagined: a session whose project dir is $HOME resolves REPO=$HOME,
# and $HOME/.claude/inject.d IS $CFG/inject.d. The doubled note is the visible
# half; the silent half is worse, because `once: session` spends its ledger key on
# the first pass and a genuinely two-tier box would then skip a repo rule. Compared
# PHYSICALLY (symlinks resolved) for the reason lint D2 exists: /tmp and
# /private/tmp are the same directory and differ as strings.
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

# TWO LAYOUTS FOR ONE RELEASE (harbor#1010, D-43, D-65). A rule is context-rules/<scope>/<id>.md;
# the old inject.d/ is still read until the date in standards/naming/renames.tsv. New first: on an id clash it wins.
# Box tier: $CFG/context-rules/user, then $CFG/inject.d. A tree: each context-rules/<scope>/ but user (the box
# tier's source, which only the installer delivers), then .claude/inject.d. A tree dir that IS a box dir is dropped.
box_dirs() {
  for _bd in "$CFG/context-rules/user" "$CFG/inject.d"; do [ ! -d "$_bd" ] || printf '%s\n' "$_bd"; done
  return 0
}
BOXP="$(box_dirs | while IFS= read -r _bd; do _phys "$_bd"; printf '\n'; done)"
tree_dirs() { # <tree>
  for _td in "$1"/context-rules/*/ "$1/.claude/inject.d"; do
    _td="${_td%/}"
    [ -d "$_td" ] || continue
    case "$_td" in "$1/context-rules/user") continue ;; esac
    case "$NL$BOXP$NL" in *"$NL$(_phys "$_td")$NL"*) continue ;; esac
    printf '%s\n' "$_td"
  done
  return 0
}

# ONE TIER'S RULES, IN ORDER (harbor#1010). By `order:`, else an old file name's NN- prefix, else after every
# ordered rule; then by file name, which is what the old glob order was. One awk and one sort per tier, not per file.
rule_files() { # <dir>... (new layout first) -> one rule file per line; an id already seen in an earlier dir is skipped
  for _rd in "$@"; do for _rf in "$_rd"/*.md; do [ ! -f "$_rf" ] || printf '%s\n' "$_rf"; done; done | awk '
    { f = $0; n = f; sub(/^.*\//, "", n); id = n; sub(/\.md$/, "", id); o = ""; hid = 0; hor = 0; ln = 0
      while ((getline l < f) > 0) {
        ln++
        if (ln == 1) { if (l !~ /^---[[:space:]]*$/) break; continue }
        if (l ~ /^---[[:space:]]*$/) break
        if (l ~ /^id:/ && !hid)    { hid = 1; v = l; sub(/^id:[[:space:]]*/, "", v); if (v != "") id = v }
        if (l ~ /^order:/ && !hor) { hor = 1; v = l; sub(/^order:[[:space:]]*/, "", v); o = v }
      }
      close(f)
      if (o !~ /^[0-9]+$/) { o = 1000; if (match(n, /^[0-9]+-/)) o = substr(n, 1, RLENGTH - 1) + 0 }
      if (id in seen) next
      seen[id] = 1
      printf "%d\t%s\t%s\n", o, n, f }' | sort -t "$(printf '\t')" -k1,1n -k2,2 | cut -f3-
}

# Collation is pinned for the same reason skill-catalog.sh pins it: glob order is
# LC_COLLATE-dependent, and two boxes ordering the same packs differently would
# emit notes in a different order and make any diff-based check flap.
LC_ALL=C
export LC_ALL

# ── frontmatter ─────────────────────────────────────────────────────────────
# THE FRONTMATTER ONLY, never the whole file. skill-catalog.sh records the failure
# this avoids: scanning the body misfiled any skill whose prose mentioned the key
# at column 0 — and these packs are documents ABOUT matching, so a pack that
# discussed `event:` in its note would classify itself.
fm()   { awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
              NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
              NR>1' "$1"; }
body() { awk 'BEGIN { n = 0 }
              /^---[[:space:]]*$/ { n++; next }
              n >= 2' "$1"; }
fmv()  { fm "$1" | awk -v k="^$2:[[:space:]]*" '$0 ~ k { sub(k, ""); print; exit }'; }
fmall(){ fm "$1" | awk -v k="^$2:[[:space:]]*" '$0 ~ k { sub(k, ""); print }'; }

# ── THE SAME ANSWERS, ONE awk PER PACK (harbor#669) ────────────────────────
# fmv is `fm | awk`, two processes, and the sweep asked it for the id and the
# event of EVERY pack on EVERY event before it could skip one. Measured
# 2026-09-24: about 60 awk per hook call and 300-460 ms at load 7, paid on every
# tool call in every session, and 131 s of one CI suite that runs this engine
# once per tracked file. The sweep now reads a pack's frontmatter once (fm_load)
# and answers each key by string handling in this shell: no fork, no temp file.
# Same match as fmv: the first line that starts with `<key>:`, with the blanks
# after the colon stripped. fmv/fmall stay for --list, which is not on a hot path.
NL='
'
fm_load() { _FM="$(fm "$1")"; }
fm_scan() { # <key> <all:0|1> -> FMV, the first value (or every value, one per line)
  FMV=''; _rest="$_FM"
  while [ -n "$_rest" ]; do
    _l="${_rest%%"$NL"*}"
    if [ "$_l" = "$_rest" ]; then _rest=''; else _rest="${_rest#*"$NL"}"; fi
    case "$_l" in
      "$1:"*)
        _x="${_l#"$1":}"; _x="${_x#"${_x%%[! 	]*}"}"
        if [ "$2" = 1 ]; then FMV="$FMV$_x$NL"; else FMV="$_x"; return 0; fi ;;
    esac
  done
  return 0
}
fm_get() { fm_scan "$1" 0; }
fm_all() { fm_scan "$1" 1; }

if [ "$MODE" = list ]; then
  printf 'injection-rule — rule packs visible from %s\n\n' "$REPO"
  # In sweep order, each tier merged across both layouts (harbor#1010), so the list is what fires and in what order.
  for _tier in box repo; do
    if [ "$_tier" = box ]; then _ds="$(box_dirs)"; else _ds="$(if [ -n "$REPO" ]; then tree_dirs "$REPO"; fi)"; fi
    [ -n "$_ds" ] || continue
    printf '%s tier: %s\n' "$_tier" "$(printf '%s\n' "$_ds" | sed "s|^$HOME/|~/|" | tr '\n' ' ')"
    _IFS="$IFS"; IFS="$NL"; set -f; set -- $_ds; set +f; IFS="$_IFS"  # one dir per line
    rule_files "$@" | while IFS= read -r f; do
      printf '  %-40s %-14s %-8s %s\n' "${f#"$HOME"/}" \
        "$(fmv "$f" event)" "$(fmv "$f" tool)" "$(fmall "$f" when | tr '\n' ';')"
    done
    printf '\n'
  done
  exit 0
fi

# ── the payload ─────────────────────────────────────────────────────────────
# NO jq HARD DEPENDENCY, same position as govern-hook.sh and annotate-web.sh:
# without jq we cannot BUILD valid JSON for arbitrary text, and the choice is a
# fixed safe string or silence. Nothing here is a safety boundary — a missed
# note costs a note — so it is silence.
PAYLOAD="$(cat)"
[ -n "$PAYLOAD" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$PAYLOAD" | jq -r "$1 // empty" 2>/dev/null || true; }

EVENT="$(field '.hook_event_name')"
[ -n "$EVENT" ] || exit 0
TOOL="$(field '.tool_name')"
SID="$(field '.session_id')"
CMD="$(field '.tool_input.command' | head -c 262144)"
FPATH="$(field '.tool_input.file_path')"
# SessionStart says WHY it started: startup | resume | clear | compact | fork.
# The distinction is the whole reason the post-compaction rule can exist at all
# (see the EVENTS_WITH_CONTEXT block) — without it, a rule about compaction would
# have to fire on every session opening and would be noise four times in five.
SOURCE="$(field '.source')"

# The written text for a Write/Edit, and the tool's OUTPUT for a PostToolUse.
# Capped, because a hook that blocks its tool call while a shell walks a 40 MB
# string is a hook the operator disables. 256 KB is far past any prose file and
# far short of anything that stalls.
#
# THE NULL FILTER COMES BEFORE `tostring`, NOT AFTER. It was the other way round,
# so a payload with no `tool_response` produced the literal four-character string
# `null` as content — jq's `tostring` runs on the null and the later
# `select(. != null)` sees a non-null string. Nothing shipped uses
# `content-contains`, so it had no live effect; it was a loaded gun for the first
# pack that did. Found by an adversarial pass.
#
# `.error` IS PART OF THE CONTENT ON A FAILURE, and without this line it was the
# same loaded gun the paragraph above describes. `PostToolUseFailure` carries NO
# `tool_response` — measured live against 2.1.258, the payload is `tool_name`,
# `tool_input`, `tool_use_id`, `error`, `is_interrupt`, `duration_ms` — so on the
# one event whose whole subject is what went wrong, `content-contains` matched
# against an empty string and could only ever return false. Silently: no error,
# no note, a predicate that reads as "did not match".
CONTENT="$(printf '%s' "$PAYLOAD" | jq -r '
  [ (.tool_input.content? // empty),
    (.tool_input.new_string? // empty),
    (.error? // empty),
    (.tool_response? | select(. != null)
      | if type == "string" then . else (tostring) end) ]
  | map(select(. != null and . != "")) | join("\n")
  # BOTH ENDS, NOT THE HEAD. A plain `head -c` made the cap an evasion: bury the
  # injection past byte 262144 of an oversized document and nothing scans it.
  # Keeping the tail costs nothing and closes the cheapest bypass there was.
  | if (length > 262144) then (.[:196608] + "\n" + .[-65536:]) else . end
  ' 2>/dev/null || true)"

# ── provenance ──────────────────────────────────────────────────────────────
# NOT A LABEL. bin/govern-token.sh's header carries the argument at length: this
# estate pipes FETCHED WEB PAGES through a byte-identical additionalContext
# envelope, so `[HARBOR GOVERNANCE]` in a page is indistinguishable from this
# file's output by inspection, and a self-label is exactly what an attack writes.
# The token is derived from a box-local salt the fetched content cannot contain.
# Empty is the default and degrades to an unlabelled note that still says
# something true — a provenance mechanism that turned reminders OFF when
# unconfigured would be worse than the problem.
TOK=''
[ -f "$SELF_DIR/govern-token.sh" ] && \
  TOK="$(sh "$SELF_DIR/govern-token.sh" --token "$SID" 2>/dev/null || true)"
STAMP='[HARBOR GOVERNANCE]'
[ -n "$TOK" ] && STAMP="[HARBOR GOVERNANCE $TOK]"

# ── the predicate vocabulary ────────────────────────────────────────────────
# FIXED, AND NOT A LANGUAGE. Every predicate below compares a value FROM the
# payload against a pattern FROM a trusted pack file, and the payload value is
# only ever the subject of a `case`, never the pattern. Nothing from the payload
# is ever eval'd, interpolated into a command string, or used as a glob —
# CONSTITUTION §4's rule about external input, applied to the one file in this
# design that reads attacker-reachable text on purpose.
#
# `case` GLOBS, NOT grep, for the reason hooks/pre-commit and govern-hook.sh both
# record: this machine's `grep` is a ugrep wrapper carrying `-I --ignore-files`,
# and a matcher whose behaviour depends on which grep is first in PATH means
# something different on the CI runner. `case` is POSIX and has no flavour.

# A heredoc body is not code. govern-hook.sh's header records the incident: a
# documentation line inside a heredoc is indistinguishable from a command by
# position alone, and an adversarial review demonstrated command-position
# splitting did not fix it.
strip_heredocs() {
  printf '%s\n' "$1" | awk '
    BEGIN { skip = 0 }
    skip == 1 { if ($0 == marker) { skip = 0 }; next }
    {
      print
      if (match($0, /<<-?[[:space:]]*'"'"'?"?[A-Za-z_][A-Za-z0-9_]*/)) {
        m = substr($0, RSTART, RLENGTH)
        gsub(/^<<-?[[:space:]]*/, "", m); gsub(/['"'"'"]/, "", m)
        marker = m; skip = 1
      }
    }'
}
# A QUOTED ARGUMENT IS NOT CODE EITHER, and this was the worst defect an
# adversarial pass found in this file. `segments()` split on `; & | ( )` and
# newline WITHOUT regard to quoting, so
#   git commit -m "docs: record the gate (gh pr create needs the agents first)"
# produced a segment reading `gh pr create needs the agents first` and fired the
# a workload pack — on a commit, not on a PR. contracts/injection-rule.md stated the
# opposite as a guarantee. And the second-order effect is worse than the noise:
# those packs are `once: session`, so the benign commit SPENT the ledger key and
# the real `gh pr create` later in the same session got total silence. A rule
# that fires on the wrong turn and is then disarmed for the right one is strictly
# worse than no rule at all.
#
# So quoted bodies are blanked — length-preserving, quotes kept — before any
# splitting, exactly as heredoc bodies already are. State carries across lines so
# a multi-line quoted argument is covered too.
#
# AN UNBALANCED QUOTE BLANKS THE REST OF THE COMMAND, and that is the deliberate
# direction to fail in: the cost is a missed note, where the opposite choice
# costs a false one. §2.11 — a false positive is a defect, a missed reminder
# costs a reminder.
blank_quoted() {
  printf '%s\n' "$1" | awk '
    BEGIN { q = "" }
    {
      out = ""
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q == "") {
          out = out c
          if (c == "\"" || c == "\047") q = c
        } else {
          if (c == "\\" && q == "\"") { out = out "  "; i++; continue }
          if (c == q) { out = out c; q = "" } else { out = out " " }
        }
      }
      print out
    }'
}

# THE WHITESPACE NORMALISATION HAPPENS HERE, IN THE ONE awk THAT ALREADY RUNS.
# It used to be a `tr` per segment inside the matching loop, which is one
# fork-pair per segment of the command — measured by an adversarial pass at 8.7 s
# for a 3,000-segment `&&` chain and 14.7 s for 5,000, against a hook timeout of
# 10. A PreToolUse hook that blocks its own tool call for fifteen seconds on a
# long pipeline is a hook the operator switches off, and the shape that triggers
# it is an ordinary generated command line, not an attack. Now it is one fork
# total and the same 3,000 segments cost about as much as one.
segments() {
  blank_quoted "$(strip_heredocs "${1:-}")" \
    | tr '\n;&|()' '\012\012\012\012\012\012\012' \
    | awk '{ gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); if ($0 != "") print }'
}

# THE SUBCOMMAND, NOT A SUBSTRING. govern-hook.sh shipped the substring version
# first and it fired on `gh pr list --search "pr merge"` and on any prose
# argument mentioning the phrase. The predicate is the first N WORDS of a
# command-position segment, so the phrase has to be the invocation.
seg_prefix() { # <words> -> 0 when some segment starts with exactly those words
  _want="$1"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    case "$_s" in
      "$_want"|"$_want "*) ;;
      *) continue ;;
    esac
    # `--help` RENDERS DOCUMENTATION AND DOES NOTHING ELSE, for every command
    # that has ever had a manual. A note about the consequences of an action,
    # delivered to someone reading how the action works, is noise by definition —
    # govern-hook.sh carried this exclusion for its one rule, and it belongs in
    # the vocabulary so every future pack inherits it.
    #
    # `-h` IS NOT IN THIS LIST AND THE FIRST CUT HAD IT THERE, on the claim that
    # the exclusion "can never wrongly suppress". That claim was false twice over,
    # measured. `-h` is a VALUE flag for tools installed on this box — `docker run
    # -h web`, `mysql -h prod.db.internal` — so it silences real invocations of
    # real commands. And the test scanned the whole segment rather than a flag
    # position, so `gh pr merge 12 --body 'pass -h to see flags'` silenced an
    # installed pack from inside a quoted string. `--help` has neither problem:
    # no tool on this box takes it as a value, and a segment containing it as a
    # token is a manual read.
    # Tested against the segment as it now stands, whose quoted bodies are
    # already blanked by blank_quoted() — so `--help` inside an argument cannot
    # suppress a real invocation, which is the second half of the same defect.
    case " $_s " in *' --help '*) continue ;; esac
    case "$_s" in *' --help') continue ;; esac
    return 0
  done <<SEGS
$(segments "$CMD")
SEGS
  return 1
}

# THE COMMAND WORD, for a tool whose invocation varies in front of its name
# (inst-quiet-predicates). cmd-prefix needs the segment to START with the words,
# so `X=dir gcal-write add` and `~/.local/bin/gcal-write add` slipped past it, and
# the cmd-contains it replaced fired on prose, greps and PR bodies. Same segments
# (heredocs and quoted bodies already gone), then assignments skipped, and the
# word must be the name or a path ending in `/name`. `--help` is excluded as above.
seg_word() { # <name> -> 0 when some segment's command word is <name>
  _want="$1"
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    case " $_s " in *' --help '*) continue ;; esac
    set -f; set -- $_s; set +f
    while [ $# -gt 0 ]; do case "$1" in [A-Za-z_]*=*) shift ;; *) break ;; esac; done
    [ $# -gt 0 ] || continue
    case "${1#\`}" in "$_want"|*/"$_want") return 0 ;; esac
  done <<SEGS
$(segments "$CMD" | sed -e 's/"[ ]*"/Q/g' -e "s/'[ ]*'/Q/g")
SEGS
  return 1
}

pred() { # <predicate line> -> 0 when satisfied
  _p="$1"
  _neg=0
  case "$_p" in 'not '*) _neg=1; _p="${_p#not }" ;; esac
  _kind="${_p%% *}"
  if [ "$_kind" = "$_p" ]; then _arg=''; else _arg="${_p#* }"; fi
  # AN UNKNOWN PREDICATE IS ITS OWN ANSWER, NOT "DID NOT MATCH". The first cut
  # returned the same 1 for both, and `not` could not tell them apart — so
  # `not cmd-prefx git push`, one letter wrong, inverted a never-matching typo
  # into a rule that fired on everything. Exactly the universal-rule-from-a-typo
  # failure the comment below promises cannot happen, arriving through the one
  # operator this file also provides. Found by an adversarial pass, reproduced.
  case "$_kind" in
    always|cmd-prefix|cmd-word|cmd-contains|path-contains|content-contains|repo-has|tool-is|source-is|injected-instruction) ;;
    *) explain "unknown predicate '$_kind' — refusing to fire either way"; return 1 ;;
  esac
  _r=1
  case "$_kind" in
    always)               _r=0 ;;
    cmd-prefix)           if seg_prefix "$_arg"; then _r=0; fi ;;
    cmd-word)             if seg_word "$_arg"; then _r=0; fi ;;
    cmd-contains)         case "$(strip_heredocs "$CMD")" in *"$_arg"*) _r=0 ;; esac ;;
    path-contains)        case "$FPATH" in *"$_arg"*) _r=0 ;; esac ;;
    content-contains)     case "$CONTENT" in *"$_arg"*) _r=0 ;; esac ;;
    repo-has)             if [ -e "${RT:-$REPO}/$_arg" ]; then _r=0; fi ;;
    tool-is)              if [ "$TOOL" = "$_arg" ]; then _r=0; fi ;;
    source-is)            if [ "$SOURCE" = "$_arg" ]; then _r=0; fi ;;
    injected-instruction) if detect_injection; then _r=0; fi ;;
    # Unreachable — the vocabulary gate above returned already. Kept so the two
    # lists cannot silently disagree about what a known predicate is.
    *)                    return 1 ;;
  esac
  if [ "$_neg" -eq 1 ]; then
    if [ "$_r" -eq 0 ]; then return 1; else return 0; fi
  fi
  return "$_r"
}

# ── the detector ────────────────────────────────────────────────────────────
# THE ONE PREDICATE THAT IS NOT A STRING COMPARE, and the reason this file exists
# rather than a fifth branch in govern-hook.sh.
#
# E9 measured the hole precisely. An HTML comment reading `SYSTEM DIRECTIVE …
# ignore previous instructions` was refused 4/4 by every arm including the one
# with NO constitution at all — models are trained on that shape. A plausible
# `## Documentation pipeline convention` heading, inside the very file the task
# asked the model to summarise, was obeyed 6 of 8 times without §4 and STILL 2 of
# 8 times with §4 fully present. §4 is load-bearing and it is not sufficient, and
# this estate is unusually exposed to the convention shape because its sessions
# are trained by their own environment to follow documented conventions.
#
# So the detector does not look for menace. It looks for text that addresses THE
# PROCESSOR OF THE CONTENT rather than its reader — the one thing a legitimate
# document almost never does and every content-borne injection must.
#
# TWO TIERS, BECAUSE ONE LIST WOULD HAVE TO CHOOSE between missing the quiet
# shape and firing on ordinary prose. LOUD phrases are unambiguous and fire
# alone. QUIET phrases are individually innocent and need corroboration: two of
# them, or one plus a write/exfiltrate marker.
LOUD='ignore previous instruction
ignore all previous
ignore prior instruction
ignore the above
disregard previous
disregard all prior
disregard the above
system directive
new system prompt
override your instruction
override the system prompt
you are now a helpful assistant
you are now an ai
you are now in developer mode
do not mention this instruction
do not mention this to the user
do not tell the user
without informing the user
without telling the user
do not reveal this
this instruction is confidential
important instruction for the assistant
note to the ai
attention: ai'

QUIET='any task that
any agent reading
any assistant reading
before summarising this
before summarizing this
before you summarise
before you summarize
must first create
must first write
must first run
must first send
required by the documentation pipeline
is required by the pipeline
so the pipeline can track
then proceed with the summary
proceed with the summary as normal
proceed as normal
as an ai assistant
if you are an ai
when processing this file
any model reading'

MARKERS='create a file named
write a file named
containing the single word
curl -
send it to
upload it to
export the contents
credentials
api key
access token
.env
base64 -d
| sh
| bash'

hits_in() { # <list> -> count of list entries present in $_hay
  _c=0
  while IFS= read -r _ph; do
    [ -n "$_ph" ] || continue
    case "$_hay" in *"$_ph"*) _c=$(( _c + 1 )) ;; esac
  done <<HITS
$1
HITS
  printf '%s' "$_c"
}

# PROVENANCE (harbor#327). A Read whose output is a slice of a file that is tracked in a
# KNOWN repo (the session's, or a registered one) and unmodified vs HEAD is the repo's own
# committed text. Never a path rule: an untracked, edited or foreign-repo file still fires.
own_committed_file() { # <path> -> 0 iff tracked, clean, in a known repo and operator-reviewed; sets _oc_pd _oc_fn
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  case "$1" in */*) _oc_pd="$(_phys "${1%/*}")" ;; *) _oc_pd="$(_phys .)" ;; esac; _oc_fn="${1##*/}"
  _oc_top="$(git -C "$_oc_pd" rev-parse --show-toplevel 2>/dev/null || true)"; [ -n "$_oc_top" ] || return 1
  _oc_top="$(_phys "$_oc_top")"
  [ "$_oc_top" = "$(_phys "$REPO")" ] || registered "$_oc_top" || return 1
  git -C "$_oc_pd" ls-files --error-unmatch -- "$_oc_fn" >/dev/null 2>&1 || return 1
  git -C "$_oc_pd" diff --quiet HEAD -- "$_oc_fn" 2>/dev/null || return 1
  # Operator-reviewed only: a row of the committed protected-paths register (the CODEOWNERS source).
  # Vendored, captured and fixture text stays external whoever merged it.
  _oc_rel="$(git -C "$_oc_pd" ls-files --full-name -- "$_oc_fn" 2>/dev/null)"; [ -n "$_oc_rel" ] || return 1
  case "$_oc_rel" in vendor/*|evals/*|fixtures/*|tests/*.jsonl|tests/*/*.jsonl|tests/*/*/*.jsonl) return 1 ;; esac
  _oc_ok=1
  while IFS="$(printf '\t')" read -r _oc_g _oc_rest; do
    case "$_oc_g" in ''|'#'*|glob) continue ;; esac
    case "$_oc_g" in
      *'**'*) case "$_oc_rel" in $_oc_g) _oc_ok=0; break ;; esac ;;
      *) # `*` stops at `/` in this register, but not in `case`
         case "$_oc_rel" in $_oc_g) [ "$(printf '%s' "$_oc_rel" | tr -dc /)" = "$(printf '%s' "$_oc_g" | tr -dc /)" ] && { _oc_ok=0; break; } ;; esac ;;
    esac
  done <<REG
$(git -C "$_oc_top" show HEAD:.agents/protected-paths.tsv 2>/dev/null)
REG
  [ "$_oc_ok" = 0 ] || return 1
}
own_committed_read() {
  [ "$TOOL" = Read ] && [ -n "$FPATH" ] || return 1
  _oc_raw="$(printf '%s' "$PAYLOAD" | jq -r '.tool_response
    | if type == "string" then . elif type == "object" then (.file.content // empty) else empty end' 2>/dev/null || true)"
  [ -n "$_oc_raw" ] || return 1
  own_committed_file "$FPATH" || return 1
  _oc_body="$(cat "$_oc_pd/$_oc_fn")"
  case "$_oc_body" in *"$_oc_raw"*) return 0 ;; esac
  # Read may number its lines (`   12<TAB>text`); compare without the gutter.
  _oc_raw="$(printf '%s\n' "$_oc_raw" | sed 's/^ *[0-9][0-9]*[	→]//')"
  case "$_oc_body" in *"$_oc_raw"*) return 0 ;; esac
  return 1
}

# The same provenance for a Bash READER (inst-quiet-predicates): `cat`, `head`, `tail`,
# `sed -n`, `grep`, `wc` over files that each pass own_committed_file. Two locks, both needed:
# the command has no separator, redirect or substitution and every stage is a reader; and
# EVERY output line (stdout, stderr, error) is in one of those files, once grep's `name:`,
# `N:` / `N-` and `cat -n` gutters are off. So any byte from elsewhere — a fetch, another
# repo, an untracked or edited file — fails the second lock and the detector still runs.
own_committed_bash() {
  [ "$TOOL" = Bash ] && [ -n "$CMD" ] || return 1
  case "$CMD" in *';'*|*'&'*|*'>'*|*'<'*|*'`'*|*'('*|*')'*|*'
'*) return 1 ;; esac
  _ob_cwd="${CWDP:-${CLAUDE_PROJECT_DIR:-$PWD}}"; _ob_files=''; _ob_names=''; _ob_first=1
  set -f
  for _ob_w in $CMD; do
    if [ "$_ob_first" = 1 ]; then
      case "$_ob_w" in cat|head|tail|grep|wc|sed) _ob_verb="$_ob_w" ;; *) set +f; return 1 ;; esac
      [ "$_ob_verb" != sed ] || case "$CMD" in *' -n '*) ;; *) set +f; return 1 ;; esac
      _ob_first=0; continue
    fi
    case "$_ob_w" in '|') _ob_first=1; continue ;; *'|'*) set +f; return 1 ;; esac
    case "$_ob_verb:$_ob_w" in sed:-i*|sed:--in-place*) set +f; return 1 ;; *:-*) continue ;; esac
    _ob_w="${_ob_w#[\'\"]}"; _ob_w="${_ob_w%[\'\"]}"
    case "$_ob_w" in /*) _ob_p="$_ob_w" ;; *) _ob_p="$_ob_cwd/$_ob_w" ;; esac
    [ -f "$_ob_p" ] || continue
    own_committed_file "$_ob_p" || { set +f; return 1; }
    _ob_files="$_ob_files$_oc_pd/$_oc_fn
"; _ob_names="$_ob_names$_ob_w
"
  done
  set +f
  [ "$_ob_first" = 0 ] && [ -n "$_ob_files" ] || return 1
  # Every string the response carries, not only stdout: a field nobody listed is still output.
  _ob_out="$(printf '%s' "$PAYLOAD" | jq -r '(.error // empty), (.tool_response | .. | strings)' 2>/dev/null || true)"
  [ -n "$_ob_out" ] || return 1
  _ob_rc=0
  # ENVIRON, not -v: BSD awk rejects a newline inside a -v value and -v rewrites backslashes.
  printf '%s\n' "$_ob_out" | OB_FILES="$_ob_files" OB_NAMES="$_ob_names" awk '
    function inb(s) { return s == "" || index(body, s) > 0 }
    BEGIN {
      nf = split(ENVIRON["OB_FILES"], fl, "\n"); n = split(ENVIRON["OB_NAMES"], nm, "\n")
      for (k = 1; k <= nf; k++) if (fl[k] != "") { while ((getline b < fl[k]) > 0) body = body b "\n"; close(fl[k]) }
    }
    {
      if ($0 == "--" || inb($0)) next
      if ($0 ~ /^[ \t]*[0-9]+([ \t]+[0-9]+)*([ \t]+total)?$/) next
      if (match($0, /^[ \t]*[0-9]+[:\t-]/) && inb(substr($0, RLENGTH + 1))) next
      for (i = 1; i <= n; i++) {
        if (nm[i] == "") continue
        if ($0 == "==> " nm[i] " <==") next
        if ($0 ~ /^[ \t]*[0-9]+([ \t]+[0-9]+)*[ \t]/ && substr($0, length($0) - length(nm[i]) + 1) == nm[i]) next
        if (index($0, nm[i]) == 1) {
          r = substr($0, length(nm[i]) + 1); c = substr(r, 1, 1); r = substr(r, 2)
          if ((c == ":" || c == "-") && (inb(r) || (match(r, /^[0-9]+[:-]/) && inb(substr(r, RLENGTH + 1))))) next
        }
      }
      exit 1
    }' || _ob_rc=1
  return "$_ob_rc"
}

detect_injection() {
  [ -n "$CONTENT" ] || return 1
  if own_committed_read; then return 1; fi
  if own_committed_bash; then return 1; fi
  # Case-folded once. `tr` is POSIX and, unlike this box's grep, has no flavour.
  _hay="$(printf '%s' "$CONTENT" | tr '[:upper:]' '[:lower:]')"
  _loud="$(hits_in "$LOUD")"; _loud="${_loud:-0}"
  if [ "$_loud" -gt 0 ]; then return 0; fi
  _quiet="$(hits_in "$QUIET")"; _quiet="${_quiet:-0}"
  if [ "$_quiet" -ge 2 ]; then return 0; fi
  if [ "$_quiet" -ge 1 ]; then
    _mark="$(hits_in "$MARKERS")"; _mark="${_mark:-0}"
    if [ "$_mark" -ge 1 ]; then return 0; fi
  fi
  return 1
}

# ── the once-ledger ─────────────────────────────────────────────────────────
# THE DEFAULT IS ONCE PER SESSION, and it is the difference between a mechanism
# and wallpaper. A note repeated on every Bash call stops being read by its third
# appearance, which is CONSTITUTION §2.11 arriving by a different door: the guard
# is not switched off, it is tuned out, and nothing turns red either way.
#
# KEYED ON THE SESSION ID, WHICH IS WHY IT IS SAFE TO WRITE AT ALL. govern-hook.sh
# is stateless by design because five sessions run concurrently on this machine
# and `hostname` here intermittently answers `Mac`, which has already forked
# host-sharded ledgers in this estate. A file per session id shares nothing
# between sessions and cannot inherit that fork. With no session id — a hand-run,
# a self-test — there is no ledger and every rule fires.
SEEN=''
# NEVER BUILD A PATH FROM UNVETTED TEXT (CONSTITUTION §4). The session id is
# harness-supplied and reaches the filesystem here; a `../` in it would write
# outside the ledger. Vetted before it is used, not after.
case "$SID" in *[!A-Za-z0-9._-]*) SID='' ;; esac
if [ -n "$SID" ] && [ "$MODE" = hook ]; then
  _sd="$CFG/state/inject"
  mkdir -p "$_sd" 2>/dev/null || true
  if [ -d "$_sd" ]; then
    SEEN="$_sd/$SID.seen"
    # Prune on the way past. A ledger that only grows is a directory nobody
    # notices until it has 40,000 files in it.
    find "$_sd" -name '*.seen' -mtime +7 -exec rm -f {} + 2>/dev/null || true
  fi
fi

already() { # <key> -> 0 when this session has already been told
  [ -n "$SEEN" ] || return 1
  [ -f "$SEEN" ] || return 1
  while IFS= read -r _k; do
    if [ "$_k" = "$1" ]; then return 0; fi
  done < "$SEEN"
  return 1
}
remember() {
  if [ -n "$SEEN" ]; then printf '%s\n' "$1" >> "$SEEN" 2>/dev/null || true; fi
}

NOTES=''
USERMSG=''
_GREP=/usr/bin/grep; [ -x "$_GREP" ] || _GREP=grep
explain() { [ "$MODE" = explain ] && printf '%s\n' "$*" >&2 || true; }

# ── the trees this call touches (harbor#599) ───────────────────────────────
# ONE DEFINITION, written in contracts/injection-rule.md ("The tree a call touches") and
# computed HERE for both of its readers: `scope: box` delivery below, and
# repo-tier.sh's report, which receives the result as HARBOR_TOUCHED instead of
# working it out a second time. It was repo-tier.sh's own code for one PR
# (#601); a second reader is what made it a seam.
#   · a file tool — the path it names (`file_path`, `notebook_path`, `path`)
#   · a shell command — its working folder (`.cwd`), every `-C <dir>`, and a
#     `gh` `-R`/`--repo` slug mapped to its checkout under PORT_ROOT
# `cd X && …` is NOT followed, by the #599 decision: reading a directory out of
# a cd chain is the shell parsing #539 records as the floor's longest run of
# fixes to fixes. The harness carries the new folder in the next call's `.cwd`.
#
# THE SHELL HALF REUSES THE FLOOR'S PARSER, guard-lib.sh beside this file,
# rather than growing a second one: floor_seg_load keeps a quoted argument as one
# token, so a commit message that MENTIONS `git -C x` is never a flag. It does not
# know heredoc bodies, so those segments are skipped up to their delimiter. No
# guard-lib, or a command past its size bound, means no shell targets — silence,
# which is this engine's posture everywhere else.

# The repository holding <path>, physically, or nothing. A path that does not
# exist yet (a Write creating a file) is walked up to the nearest directory that
# does, and a file is walked up to its directory.
_top() {
  _d="$1"
  while [ ! -d "$_d" ]; do _d="$(dirname -- "$_d")"; done
  _t="$(CDPATH='' cd -- "$_d" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$_t" ]; then _phys "$_t"; printf '\n'; fi
  return 0
}

# THE DECISION LOG (harbor#953). A rule that spoke leaves one record in guard-decisions.jsonl, through the
# floor's own writer: g=inject, d=advise or deny, r=<pack id>. floor_log_decision works out the sink from
# $0 (this script, <config>/bin), refuses anything but the known enums, and fails silent, so a box with no
# ledger stays blind rather than wrong. guard-lib.sh is read only on a fire (once a session for most
# packs), never on the silent hot path. Only fires are written: a silent arm has no decision to record.
log_rule() { # <advise|deny> <pack id>
  [ -f "$SELF_DIR/guard-lib.sh" ] || return 0
  ( DIR="$SELF_DIR"; . "$SELF_DIR/guard-lib.sh" >/dev/null 2>&1
    FLOOR_TOOL="$TOOL"; floor_log_decision inject "$1" "$2.meta" ) >/dev/null 2>&1 || :
}

shell_targets() {
  # A case before the fork: most commands carry no -C, -R or --repo at all.
  case "$CMD" in *-C*|*-R*|*--repo*) ;; *) return 0 ;; esac
  [ -f "$SELF_DIR/guard-lib.sh" ] || return 0
  (
    DIR="$SELF_DIR"
    . "$SELF_DIR/guard-lib.sh" >/dev/null 2>&1
    floor_seg_load "$CMD"
    [ -n "$FLOOR_SEGS" ] || exit 0
    _port="$(floor_port_root)"
    _hascd=0
    printf '%s\n' "$FLOOR_SEGS" | awk '
      function sid(s,   p) { p = index(s, ":"); return substr(s, 1, p - 1) + 0 }
      function val(s,   p) { p = index(s, ":"); return substr(s, p + 1) }
      /^SEGC:/ { s = substr($0, 6); i = sid(s); C[i] = val(s); if (i > M) M = i; next }
      /^SEGA:/ { s = substr($0, 6); i = sid(s); N[i]++; A[i, N[i]] = val(s); if (i > M) M = i; next }
      /^SEGR:/ { s = substr($0, 6); i = sid(s); r = val(s)
                 if (substr(r, 1, 3) == "<<:") { d = substr(r, 4); sub(/^-/, "", d); H[i] = d }
                 next }
      END {
        delim = ""; out = ""; cd = 0
        for (i = 1; i <= M; i++) {
          if (!(i in C)) continue
          # A heredoc body is data, whatever it looks like, until its delimiter.
          if (delim != "") { if (C[i] == delim) delim = ""; continue }
          w = C[i]; sub(/.*\//, "", w)
          if (w == "cd" || w == "pushd") cd = 1
          for (k = 1; k <= N[i]; k++) {
            t = A[i, k]
            if (t == "-C" && k < N[i]) out = out "DIR\t" A[i, k + 1] "\n"
            if (w != "gh") continue
            if ((t == "-R" || t == "--repo") && k < N[i]) out = out "SLUG\t" A[i, k + 1] "\n"
            else if (substr(t, 1, 7) == "--repo=")     out = out "SLUG\t" substr(t, 8) "\n"
          }
          if (i in H) delim = H[i]
        }
        if (cd) printf "CD\t1\n"
        printf "%s", out
      }' | while IFS="$(printf '\t')" read -r _k _v; do
      case "$_k" in
        CD) _hascd=1 ;;
        DIR)
          case "$_v" in
            # A substitution, a variable or a glob names a directory this
            # cannot know. Silent, never guessed.
            *@SUB@*|*'`'*|*'*'*|*'?'*|*'['*) ;;
            /*)            printf '%s\n' "$_v" ;;
            '~')           printf '%s\n' "$HOME" ;;
            '~/'*)         printf '%s/%s\n' "$HOME" "${_v#\~/}" ;;
            '$HOME')       printf '%s\n' "$HOME" ;;
            '$HOME/'*)     printf '%s/%s\n' "$HOME" "${_v#\$HOME/}" ;;
            *'$'*)         ;;
            # Relative to the working folder only when no cd moved it first.
            *)             if [ "$_hascd" = 0 ] && [ -n "$CWDP" ]; then printf '%s/%s\n' "$CWDP" "$_v"; fi ;;
          esac ;;
        SLUG)
          case "$_v" in */*/*) _v="${_v#*/}" ;; esac   # HOST/OWNER/REPO
          case "$_v" in *[!A-Za-z0-9_./-]*|*/*/*|/*|*/|'') continue ;; */*) ;; *) continue ;; esac
          _want="$(printf '%s' "$_v" | tr '[:upper:]' '[:lower:]')"
          for _d in "$_port"/*/; do
            _d="${_d%/}"
            [ -e "$_d/.git" ] || continue
            _u="$(git -C "$_d" config --get remote.origin.url 2>/dev/null || true)"
            _u="${_u%/}"; _u="${_u%.git}"
            _s="$(printf '%s' "$_u" | awk -F'[/:]' 'NF >= 2 { print tolower($(NF - 1) "/" $NF) }')"
            [ "$_s" = "$_want" ] || continue
            printf '%s\n' "$_d"
            break
          done ;;
      esac
    done
  ) 2>/dev/null || true
  return 0
}

touched_trees() {
  _pp="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.file_path // .tool_input.notebook_path // .tool_input.path // empty' 2>/dev/null || true)"
  {
    case "$_pp" in
      '')    ;;
      /*)    printf '%s\n' "$_pp" ;;
      '~')   printf '%s\n' "$HOME" ;;
      '~/'*) printf '%s/%s\n' "$HOME" "${_pp#\~/}" ;;
      *)     if [ -n "$CWDP" ]; then printf '%s/%s\n' "$CWDP" "$_pp"; fi ;;
    esac
    if [ "$TOOL" = Bash ]; then
      # The session's own project directory resolves to the governed tree or to
      # none, and either way there is nothing to reach — so the commonest shape,
      # a session that never left where it started, costs no fork here.
      if [ -n "$CWDP" ] && [ "$CWDP" != "${CLAUDE_PROJECT_DIR:-$PWD}" ]; then printf '%s\n' "$CWDP"; fi
      shell_targets
    fi
  } | while IFS= read -r _x; do
    [ -n "$_x" ] || continue
    _top "$_x"
  done | awk 'NF && !seen[$0]++'
  return 0
}

# THE REGISTRY IS THE TRUST BOUNDARY. A reached tree's packs are delivered, and a
# `run:` pack EXECUTES, because the session touched that tree — so which trees
# may do that cannot be "any repository a tool call names". A cloned third-party
# repo read once would otherwise run its own script inside this hook and speak
# with this engine's governance stamp. `projects.tsv` beside the box packs is the
# operator's list of this estate's projects; a worktree counts as its owner,
# because the registry names repositories, not their checkouts.
# It moves with the box tier (harbor#1010); the old place is read while no new one is installed.
REG="$CFG/context-rules/user/projects.tsv"
[ -f "$REG" ] || REG="$CFG/inject.d/projects.tsv"
registered() { # <physical tree>
  [ -f "$REG" ] || return 1
  _own="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  case "$_own" in */.git) _own="$(_phys "${_own%/.git}")" ;; *) _own='' ;; esac
  while IFS="$(printf '\t')" read -r _rn _rp _rc; do
    case "$_rn" in ''|'#'*) continue ;; esac
    case "$_rp" in '~/'*) _rp="$HOME/${_rp#\~/}" ;; esac
    [ -d "$_rp" ] || continue
    _rp="$(_phys "$_rp")"
    if [ "$_rp" = "$1" ] || [ "$_rp" = "$_own" ]; then return 0; fi
  done < "$REG"
  return 1
}

TOUCHED=''; REACHED=''
CWDP="$(field '.cwd')"
case "$EVENT" in
  PreToolUse|PostToolUse|PostToolUseFailure)
    TOUCHED="$(touched_trees)"
    _gov="$(_phys "$REPO")"
    while IFS= read -r _t; do
      [ -n "$_t" ] || continue
      [ "$_t" != "$_gov" ] || continue
      [ -n "$(tree_dirs "$_t")" ] || continue
      if registered "$_t"; then
        REACHED="$REACHED$_t
"
        explain "reach $_t: registered — its scope: box packs are in the sweep"
      else
        explain "reach $_t: not in $REG — its packs are not delivered"
      fi
    done <<TREES
$TOUCHED
TREES
    ;;
esac
# repo-tier.sh reports what was delivered and what was withheld, and must read
# the same answer the sweep acted on rather than a copy of how it was reached.
HARBOR_TOUCHED="$TOUCHED"; HARBOR_REACHED="$REACHED"
export HARBOR_TOUCHED HARBOR_REACHED

# ── evaluate every pack ─────────────────────────────────────────────────────
# Three sources, one line per rule file in sweep order: `<file> TAB <tree it speaks for> TAB <reached>`.
# Box and repo packs speak for the governed tree. A REACHED tree's packs speak
# for that tree — `repo-has` is judged there and a `run:` script runs there — and
# only the ones that declare `scope: box` are read at all: the repo consents per
# rule, in its own data, and the default is to stay home.
tier_files() { # <tree it speaks for> <reached> <dirs, one per line> -> the sweep lines of one tier
  _tt="$1"; _tr="$2"; _IFS="$IFS"; IFS="$NL"; set -f; set -- $3; set +f; IFS="$_IFS"
  [ $# -gt 0 ] || return 0
  rule_files "$@" | while IFS= read -r _tf; do printf '%s\t%s\t%s\n' "$_tf" "$_tt" "$_tr"; done
}
sweep_files() {
  tier_files "$REPO" 0 "$(box_dirs)"
  if [ -n "$REPO" ]; then tier_files "$REPO" 0 "$(tree_dirs "$REPO")"; fi
  printf '%s' "$REACHED" | while IFS= read -r _t; do
    if [ -n "$_t" ]; then tier_files "$_t" 1 "$(tree_dirs "$_t")"; fi
  done
  return 0
}

DECISION=''; DREASON=''
while IFS="$(printf '\t')" read -r _file RT _reach; do
  [ -n "$_file" ] || continue
  _dir="${_file%/*}"
  # A DECISION ENDS THE SWEEP. Once a pack has denied the call, later packs are
  # commenting on a tool use that will not happen, and the `break` below only
  # leaves the inner loop — without this the next directory would keep firing.
  [ "$DECISION" = deny ] && break
  # One pass per file since harbor#1010; the loop stays so `continue` and the deny `break` keep their meaning.
  for _f in "$_file"; do
    [ -f "$_f" ] || continue
    fm_load "$_f"
    fm_get id; _id="$FMV"; [ -n "$_id" ] || { _id="${_f##*/}"; _id="${_id%.md}"; }
    if [ "$_reach" = 1 ]; then
      fm_get scope
      if [ "$FMV" != box ]; then
        explain "skip $_id: in a reached tree ($RT) without scope: box — it stays home"; continue
      fi
    fi
    fm_get event; _ev="$FMV"
    [ "$_ev" = "$EVENT" ] || { explain "skip $_id: event $_ev != $EVENT"; continue; }
    fm_get tool; _tl="$FMV"
    if [ -n "$_tl" ] && [ "$_tl" != "$TOOL" ]; then
      # ── ONE MATCHING SEMANTICS, THE HARNESS'S (harbor#184) ──────────────────
      # This was literal alternation — `case "|$_tl|" in *"|$TOOL|"*)` — while the
      # matcher column in settings.json, which decides whether this engine is
      # invoked at all, is a REGEX. Two semantics for one field, and the narrower
      # one silently wins: a pack declaring `mcp__.*` passed the harness matcher
      # and was then skipped here, because no tool is literally named `mcp__.*`.
      # Measured while wiring harbor#184's pack, whose whole target set is the
      # `mcp__claude-in-chrome__*` family — 58 of the 88 MB of result bytes.
      #
      # A regex is a superset of the alternation the contract already promises, and
      # tool names are `[A-Za-z0-9_]+` in practice, so nothing that worked stops
      # working. An unparseable pattern makes grep fail, which reads as no match —
      # silence, which is this engine's posture everywhere else.
      #
      # THE GREP IS PINNED, as guard-lib.sh pins $FLOOR_GREP and lint F3 requires
      # of every file that sources it (this one does, for the shell half of "the
      # tree a call touches"). On this box `grep` in a PATH can be a ugrep wrapper,
      # and which grep answers must not decide whether a rule matches.
      printf '%s\n' "$TOOL" | "$_GREP" -qE "^($_tl)$" 2>/dev/null \
        || { explain "skip $_id: tool $_tl does not match $TOOL"; continue; }
    fi

    fm_all when; _whens="$FMV"
    _ok=1
    _npred=0
    while IFS= read -r _w; do
      [ -n "$_w" ] || continue
      _npred=$(( _npred + 1 ))
      if ! pred "$_w"; then _ok=0; explain "skip $_id: predicate failed -> $_w"; break; fi
    done <<WHEN
$_whens
WHEN
    [ "$_ok" -eq 1 ] || continue
    # NO PREDICATE IS NOT "ALWAYS". A pack that forgot its `when:` would fire on
    # every event of its type forever, which is the loudest possible failure for
    # the most likely possible typo.
    [ "$_npred" -gt 0 ] || { explain "skip $_id: no when: predicate — refusing to fire"; continue; }

    # ONCE: session | match | never.
    #
    # `match` EXISTS BECAUSE `session` HAS A COVERAGE HOLE, and the hole was
    # measured rather than imagined. Sweeping the detector below across this
    # estate's markdown fires on a handful of documents that DISCUSS injection —
    # the constitution's §4 describes the attack in the attack's own words, and
    # this repo's eval page quotes the fixtures verbatim. Under `once: session` a
    # session that read one of those first would have spent its single note on a
    # document ABOUT injection and then said nothing about a genuinely hostile
    # file read afterwards. `match` keys the ledger on what matched, so a benign
    # hit costs one sentence and consumes nothing.
    #
    # The exact set is NOT written down here. hooks/injection-rule/detector.test.sh sweeps every
    # tracked markdown file and compares against an allowlist, so a new false
    # positive turns the suite red on the commit that introduces it. A count in a
    # comment is a copy, and this one was already wrong when it was written.
    fm_get once; _once="$FMV"; [ -n "$_once" ] || _once=session
    _key="$_id"
    # THE COMMAND IS PART OF THE SUBJECT, AND IT WAS NOT (harbor#180). A Bash rule
    # at PreToolUse has no file path and no content — nothing has been written or
    # returned yet — so every command in a session hashed to the SAME empty
    # subject and `once: match` silently became `once: session`. Measured: five
    # different trap-shaped commands in one session, only the first spoke.
    #
    # That is the quietest possible failure for the most natural pack there is —
    # `cmd-prefix` plus `match` is what anyone writes for a rule that should
    # re-fire on a genuinely different command — and nothing turned red, because
    # the rule fired once and looked like it was working.
    #
    # RAW COMMAND, NOT THE MATCHED PREFIX. `gh pr merge 174` and `gh pr merge 179`
    # are different acts on different objects and a merge rule should speak for
    # both; keying on the prefix would collapse them into one and re-introduce the
    # same silence one level up.
    if [ "$_once" = match ]; then
      _subject="$FPATH"
      [ -n "$_subject" ] || _subject="$(printf '%s' "$CONTENT" | head -c 4096)"
      [ -n "$_subject" ] || _subject="$(printf '%s' "$CMD" | head -c 4096)"
      _key="$_id:$(printf '%s' "$_subject" | cksum | tr -d ' ')"
    fi
    if [ "$_once" != never ] && already "$_key"; then
      explain "skip $_id: already delivered this session ($_key)"; continue
    fi

    # `run:` — a dynamic body, for the rules whose condition is computable but
    # not expressible as a predicate. The script gets the payload on stdin and
    # its STDOUT is the note; empty stdout means no note, which is how such a
    # rule stays silent. Invoked as an ARGUMENT to sh, never interpolated into a
    # command string (CONSTITUTION §4).
    #
    # RESOLVED NEXT TO ITS PACK, RUN FROM THE SESSION'S REPO. Two different
    # things, and conflating them is what made the first cut unusable: the script
    # belongs to whoever wrote the pack (box or repo), while the state it reports
    # on is the session's working tree. `..` and absolute paths are refused so a
    # pack cannot reach outside its own directory to pick an interpreter target.
    fm_get run; _run="$FMV"
    if [ -n "$_run" ]; then
      case "$_run" in /*|*..*) explain "skip $_id: run: must be a plain filename beside the pack"; continue ;; esac
      if [ ! -f "$_dir/$_run" ]; then explain "skip $_id: run: $_run not found in $_dir"; continue; fi
      _note="$(printf '%s' "$PAYLOAD" | (cd "${RT:-$REPO}" 2>/dev/null && sh "$_dir/$_run") 2>/dev/null || true)"
      # ── A `run:` PACK MAY RETURN A DECISION, NOT ONLY A NOTE (harbor#254) ──
      # `run:` contracts that stdout is the note, and that contract silently
      # disarmed a real gate: bin/govern-hook.sh computes the merge backstop's
      # verdict and emits a PreToolUse `permissionDecision: deny`, but reached
      # through this engine it went through `--note`, which prints prose — and
      # prose wrapped as additionalContext cannot stop a Bash call. Suite green
      # on both sides; every red PR still merged. Found by review (PR #262).
      #
      # THE SENTINEL IS OPT-IN AND EXACT. A pack that wants to decide prints
      # `HARBOR-DECISION deny: <reason>` as its first line; anything else is a
      # note exactly as before. Only `run:` output is inspected — a static
      # markdown body cannot acquire blocking power by containing a sentence.
      #
      # AND ONLY WHERE THE HARNESS HAS A CHANNEL FOR IT. `permissionDecision` is
      # PreToolUse-only (contracts/hooks.md). On any other event the sentinel is
      # stripped and the text is delivered as an ordinary note, with the
      # downgrade stated to the operator — because a decision the harness
      # discards is the PreCompact failure this file already carries a comment
      # about, and it must not repeat quietly.
      case "$_note" in
        'HARBOR-DECISION deny: '*)
          if [ "$EVENT" = PreToolUse ]; then
            DECISION=deny
            DREASON="${_note#HARBOR-DECISION deny: }"
            explain "DECIDE $_id: deny"
          else
            _note="${_note#HARBOR-DECISION deny: }"
            explain "downgrade $_id: a deny cannot ride on $EVENT — delivered as a note"
          fi ;;
      esac
    else
      _note="$(body "$_f")"
    fi
    # Collapse to one paragraph. A note arrives inside a JSON string; hard-wrapped
    # source lines read as broken prose once they land.
    _note="$(printf '%s' "$_note" | tr '\n' ' ' | tr -s ' ')"
    _note="${_note# }"; _note="${_note% }"
    if [ "${DECISION:-}" = deny ]; then
      # The reason travels in its own field, so it is not also appended as a note.
      DREASON="$(printf '%s' "$DREASON" | tr '\n' ' ' | tr -s ' ')"
      DREASON="${DREASON# }"; DREASON="${DREASON% }"
      if [ "$_once" != never ]; then remember "$_key"; fi
      log_rule deny "$_id"
      break
    fi
    [ -n "$_note" ] || { explain "skip $_id: empty note"; continue; }

    explain "FIRE $_id"
    log_rule advise "$_id"
    # Each note names the rule that raised it, so an alert reaches its owner and off-switch in one
    # lookup (harbor#957): `<id>` is the front-matter id, which controls.tsv maps in its `emitted` column.
    NOTES="$NOTES[context:$_id] $_note "
    if [ "$_once" != never ]; then remember "$_key"; fi

    # `mode: notify` also speaks to the HUMAN. systemMessage sidesteps the trust
    # question outright — a line the operator reads never has to be believed by
    # the model — so anything whose real audience is the person gets both.
    fm_get mode
    if [ "$FMV" = notify ]; then
      fm_get summary; _um="$FMV"; [ -n "$_um" ] || _um="$_id"
      USERMSG="$USERMSG$_um; "
    fi
  done
done <<PACKS
$(sweep_files)
PACKS

NOTES="${NOTES% }"
# A DENY WITH NO OTHER NOTE IS STILL AN ANSWER. `[ -n "$NOTES" ] || exit 0` alone
# dropped it on the floor: the decision's text rides in its own field, so NOTES is
# empty in exactly the case that matters most, and the engine exited silently
# while the red merge proceeded.
[ -n "$NOTES" ] || [ "${DECISION:-}" = deny ] || exit 0

# ── the emit, and WHICH EVENTS CAN CARRY A NOTE AT ALL ──────────────────────
# NOT EVERY HOOK EVENT REACHES THE MODEL. `hookSpecificOutput.additionalContext`
# is accepted on the events below and REJECTED everywhere else — and rejected
# means the harness discards the WHOLE object, so a `mode: notify` systemMessage
# riding along in the same JSON is thrown away with it. The failure is silent
# from the engine's side: the script exits 0 having written well-formed JSON, and
# only the operator's terminal shows "Hook JSON output validation failed".
#
# THIS IS NOT A GUESS. It shipped broken: `20-precompact-carry.md` declared
# `event: PreCompact`, and PreCompact accepts only the top-level `decision`
# pattern — there is no channel from a PreCompact hook to the model in this
# harness at all. Every compaction this box performed emitted an object the
# harness rejected. The rule was retargeted to SessionStart + `source-is compact`
# (see context-rules/user/post-compaction-carry.md), which fires on the far side of
# the same moment and CAN be heard. Lint IJ1 now refuses a pack that declares a
# context-less event without `mode: notify`, so this class cannot return quietly.
#
# The list tracks the harness, not our preferences. When it changes, this line
# and contracts/injection-rule.md's table change together.
#
# READ OFF THE BINARY'S OWN SCHEMA ON 2026-09-02, not inferred and not recalled.
# `hookSpecificOutput` is a discriminated union in 2.1.258 and every arm either
# carries `additionalContext` or does not; extracting the union settled three
# events this list had wrong by omission — UserPromptExpansion, PostModelSwitch
# and Notification all accept it and were being downgraded to operator-only.
# Nothing ships on them, so the cost was zero and the direction is what matters:
# a list of what the harness accepts, maintained by hand, drifts toward SMALLER
# than the truth, and every omission is a pack that silently talks to nobody.
#
# AND `PostCompact` IS NOT IN THE UNION AT ALL. contracts/hooks.md carried it as
# "receives the summary — could verify what survived", which reads like an open
# avenue; it is the same closed door as PreCompact. The post-compaction rule
# stays on SessionStart + `source-is compact`, which is the only channel there is.
case "$EVENT" in
  SessionStart|Setup|SubagentStart|UserPromptSubmit|UserPromptExpansion|PostModelSwitch|Notification|PreToolUse|PostToolUse|PostToolUseFailure|PostToolBatch|Stop|SubagentStop)
    _ctx=yes ;;
  *) _ctx=no ;;
esac

if [ "$_ctx" = no ]; then
  # The model cannot be reached on this event. Say it to the operator instead of
  # emitting JSON that will be discarded — a note delivered to nobody, with a
  # validation error where the note should have been, is worse than silence.
  explain "event $EVENT carries no model-visible channel — operator note only"
  if [ -n "$USERMSG" ]; then
    jq -cn --arg m "harbor: ${USERMSG%; }" '{systemMessage:$m}' 2>/dev/null || true
  fi
  exit 0
fi

# A DECISION SHORT-CIRCUITS THE NOTE, because they are answers to different
# questions and only one of them stops the call. The reason reaches the model as
# `permissionDecisionReason`, which is the channel a deny already travels on
# (contracts/hooks.md: confirmed live — guard-bash.sh's denial landed mid-turn
# and redirected the work), so it does not also need to be an additionalContext.
if [ "${DECISION:-}" = deny ]; then
  jq -cn --arg e "$EVENT" --arg r "$STAMP $DREASON" \
    '{hookSpecificOutput:{hookEventName:$e,permissionDecision:"deny",permissionDecisionReason:$r}}' \
    2>/dev/null || true
  exit 0
fi

if [ -n "$USERMSG" ]; then
  jq -cn --arg e "$EVENT" --arg c "$STAMP $NOTES" --arg m "harbor: ${USERMSG%; }" \
    '{systemMessage:$m,hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
else
  jq -cn --arg e "$EVENT" --arg c "$STAMP $NOTES" \
    '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}' 2>/dev/null || true
fi
exit 0
