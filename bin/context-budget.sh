#!/usr/bin/env sh
# context-budget.sh — measure what Harbor costs EVERY session.
# harbor#5 / M3, method from upstream `BudgetCheck` @ a4e8e74 (PROVENANCE.md).
#   sh bin/context-budget.sh            the full report, every always-on row
#   sh bin/context-budget.sh --check    fail if the DELIBERATE surface has moved
#                                       off the last row of CONTEXT-BASELINE.tsv
#   sh bin/context-budget.sh --record   append today's figure + instrument id; you write the why
#   sh bin/context-budget.sh --check --kind   also print kind=<match|grew|shrank|instrument-changed|
#                                       no-baseline|unreadable|malformed> last on stdout: X3's subject (harbor#585)
# (the --help extractor stops at the first blank comment line, so the usage block
#  sits above it rather than after — S4 is satisfied by what it PRINTS, not by
#  what the header contains.)
#
# THE VERDICT IS A RECORDED PRIOR MEASUREMENT, NOT A CEILING (harbor#183). The
# 24,000 B ceiling was the gate for a year and its own definition called itself
# "a round, arguable number rather than a derived one"; #183 measured the three
# things it could have protected — capacity, cost, dilution — and found none of
# them. Regrowth is the real concern, and regrowth needs a prior number.
#
# Upstream's words: "backpressure against always-on context re-accretion. Without
# a ceiling those files regrow: memory proposals auto-append, ISAs accrete, rules
# stack."
#
# Harbor is about to do exactly that. C1 puts CONSTITUTION.md into
# ~/.claude/CLAUDE.md, L2 (harbor#43) adds TELOS + IDENTITY, D adds memory
# injection — all always-on, none of them bounded by anything. Upstream hit this
# wall and built a ceiling; Harbor had not noticed the wall existed.
#
# Every byte here is spent before the user's first word, in every session,
# forever. That is the most expensive kind of byte in the system.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
MODE=report; KIND=0
case "${1:-}" in
  --check)  MODE=check
            case "${2:-}" in
              --kind) KIND=1 ;;
              '')     ;;
              *)      printf 'context-budget: unknown flag %s after --check (try --help)\n' "$2" >&2; exit 2 ;;
            esac ;;
  --record) MODE=record ;;
  '')       ;;
  *)        printf 'context-budget: unknown flag %s (try --help)\n' "$1" >&2; exit 2 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The --check failures speak in the house line shape (CONTRACTS/logging.md, LOG1). stderr, as before.
LOG_FD=2; . "$(dirname -- "$0")/log-lib.sh"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# THE BASELINE, AND WHY IT IS A FILE AND NOT A NUMBER IN THIS SCRIPT (harbor#183).
# A recorded prior measurement is the one denominator that is not invented. It
# lives in the repo so that growth is a DIFF with a reason in the commit message —
# which is what "backpressure against re-accretion" actually needs, and what a
# constant in a variable can never give.
#
# WHERE IT LIVES (harbor#1275, harbor#1149): the user's state directory, never the checkout. A harbor-core clone has no
# CONTEXT-BASELINE.tsv, and a file written at its root is one `git add -A` away from a PR. An in-tree file is only a SEED:
# read while the state file is absent, and copied there before the first --record, so nothing is ever written into the tree.
_STATE="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
_STATE_BL="$_STATE/context-baseline.tsv"
_BL_SEED=0
if [ -n "${HARBOR_CONTEXT_BASELINE:-}" ]; then BASELINE="$HARBOR_CONTEXT_BASELINE"
elif [ -e "$_STATE_BL" ] || [ -L "$_STATE_BL" ] || [ ! -f "$ROOT/CONTEXT-BASELINE.tsv" ]; then BASELINE="$_STATE_BL"
else BASELINE="$ROOT/CONTEXT-BASELINE.tsv"; _BL_SEED=1; fi

# Ceiling in bytes. NO LONGER THE VERDICT (harbor#183), AND SINCE 2026-09-20 NO
# LONGER ANOTHER TOOL'S BASIS EITHER (harbor#316). It used to govern exactly one
# thing — store-check.sh's index allowance, `ceiling - (spent - index)` — and that
# coupling is now cut: store-check derives its bound from the index's own pointer
# count. What this number still does is set the percentage and the OVER/headroom
# line THIS tool prints, and nothing else in the repo reads it.
#
# SO ITS HONEST STATUS IS "A RECORDED PRIOR MEASUREMENT WITH A CONSUMER OF ONE",
# and that is worth stating rather than leaving a 40,000 that reads like a bound
# somebody chose. Its own first comment admitted the problem: "deliberately a
# round, arguable number rather than a derived one". The backpressure that
# actually works is `--check` against CONTEXT-BASELINE.tsv, which is a diff with a
# reason in a commit; this constant is the legacy headline beside it.
#
# THE ARITHMETIC BEHIND 40,000, KEPT BECAUSE IT IS WHERE 150 CAME FROM. On
# 2026-08-28 the non-index always-on surface measured 19,381 B (constitution plus
# ambient descriptions) and the index was a routing table of one pointer per note,
# 133 notes at a 139 B mean. Allowing 150 B a pointer gives 19,950 B plus ~600 B
# of section structure: 19,381 + 20,550 = 39,931, taken to 40,000. store-check.sh
# now applies that 150-and-600 directly to the file it was always about, which is
# why this paragraph stays here as the provenance of those two numbers.
#
# AND #316 SHOWED WHY THE OLD COUPLING HAD TO GO, rather than the ceiling being
# re-guessed again: counting the plugin, command and injection surfaces added
# 19,494 B that every session was already paying, the derived allowance fell from
# 9,477 B to 799 B, and store-check began demanding a five-pointer index. Nothing
# about the memory store had changed. A bound that moves because a different
# surface was measured more honestly is pointed at the wrong thing.
CEIL="${HARBOR_CONTEXT_CEILING:-40000}"

bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

# THE WHOLE `description:` VALUE, NOT ITS FIRST LINE. The harness lists the
# description its author wrote, and YAML lets that be a block scalar running over
# many lines. Reading only the first line undercounts exactly the expensive case:
# `pr-review-toolkit`'s `code-simplifier` carries three worked `<example>`
# transcripts under `description:`, which a first-line read prices at 14 B against
# a true 2,348. NO SKILL ON THIS BOX USES THE BLOCK FORM TODAY — measured
# 2026-09-20, first-line and full-value totals are both 7,991 B — so this changes
# no number that was ever reported and removes the trap for the next author who
# writes one. It is shared with the plugin-agent row below, where the block form
# is already in use, so the two surfaces cannot be measured by two rules.
desc_bytes() { # <file> -> bytes of the whole description: value
  [ -f "$1" ] || { echo 0; return; }
  awk '/^description:/            { inb=1; t=length($0); next }
       inb && /^[A-Za-z_-]+:/     { exit }
       inb && /^---[[:space:]]*$/ { exit }
       inb                        { t += length($0) + 1 }
       END                        { print t+0 }' "$1"
}

# A CHECK THAT PRINTS A TABLE IS A CHECK NOBODY READS IN CI. The rows are emitted
# as the measurement runs, so --check and --record keep fd 3 for their one line
# and send the report to /dev/null rather than buffering it.
exec 3>&1
[ "$MODE" = report ] || exec 1>/dev/null

total=0
printf '%-46s %8s  %s\n' SOURCE BYTES STATE
_rule='─────────────────────────────────────────────────────────────────────'; printf '%s\n' "$_rule"

row() { # <label> <bytes> <state>
  printf '%-46s %8s  %s\n' "$1" "$2" "$3"
  total=$(( total + $2 ))
}

# ── the root constitution ───────────────────────────────────────────────────
if [ -f "$CFG/CLAUDE.md" ]; then
  row "~/.claude/CLAUDE.md" "$(bytes "$CFG/CLAUDE.md")" live
else
  row "CONSTITUTION.md (would become ~/.claude/CLAUDE.md)" "$(bytes "$ROOT/CONSTITUTION.md")" "NOT INSTALLED — projected"
fi

# ── ambient skill descriptions ──────────────────────────────────────────────
# Only AMBIENT skills cost per-session: the harness lists their description so
# the model can match on it. `disable-model-invocation: true` keeps a skill out
# of that listing entirely, which is why I1-ext put seven skills in that tier.
sk_dir="$CFG/skills"; [ -d "$sk_dir" ] || sk_dir="$ROOT/vendor/skills"
amb=0; ambn=0; invn=0
for d in "$sk_dir"/*/; do
  [ -d "$d" ] || continue
  f="$d/SKILL.md"; [ -f "$f" ] || continue
  if grep -q '^disable-model-invocation:[[:space:]]*true' "$f" 2>/dev/null; then
    invn=$(( invn + 1 )); continue
  fi
  ambn=$(( ambn + 1 ))
  amb=$(( amb + $(desc_bytes "$f") ))
done
row "ambient skill descriptions ($ambn ambient, $invn invoked-only)" "$amb" "${sk_dir#$HOME/}"

# ── plugin agent and command descriptions (harbor#316) ──────────────────────
# THE MOST EXPENSIVE ALWAYS-ON ROWS ON THIS BOX WERE ON A SURFACE THIS FILE DID
# NOT NAME. Before 2026-09-20 there was no occurrence of `plugin`, `agent`,
# `command` or `mcp` anywhere in this script — an undeclared blind spot, not a
# declared exclusion, which is the distinction that matters when a reader is
# deciding whether a missing number means "zero" or "never looked".
#
# A subagent's `description:` is listed in EVERY session's prefix so the model can
# match a task to it, exactly like an ambient skill's. Measured 2026-09-20:
# `pr-review-toolkit` charges 6,360 B a session for six roles with TEN all-time
# invocations, four of them fired once each on one day. Five of the six are more
# expensive per use than any ambient skill on the box.
#
# RESOLVED FROM `installed_plugins.json`, NEVER BY GLOBBING THE CACHE. The cache
# holds 17 version directories for this one plugin and the harness de-duplicates
# to one; a glob would charge the prefix four to seventeen times over and the row
# would be the loudest wrong number in the report. The register says which path is
# installed, and only `scope: user` entries are charged — a `scope: project` entry
# is another repo's session, not this one's.
plug=0; plugn=0
_reg="$CFG/plugins/installed_plugins.json"
if [ -f "$_reg" ]; then
  # `tr ',' '\n'` FIRST, so the parse does not depend on the writer's formatting.
  # The harness pretty-prints this file today and a line-based awk read it fine —
  # until the suite handed it the same JSON on one line and the row silently
  # reported 0, which is a wrong number wearing the costume of an absent surface.
  # Splitting on commas makes every `"key": "value"` its own record either way.
  for _p in $(tr ',' '\n' < "$_reg" | awk '
      /"scope"/       { s=$0; sub(/.*"scope"[^"]*"/,"",s); sub(/".*/,"",s) }
      /"installPath"/ { p=$0; sub(/.*"installPath"[^"]*"/,"",p); sub(/".*/,"",p)
                        if (s == "user") print p }' | sort -u); do
    [ -d "$_p" ] || continue
    for _f in "$_p"/agents/*.md "$_p"/commands/*.md; do
      [ -f "$_f" ] || continue
      _d="$(desc_bytes "$_f")"
      [ "$_d" -gt 0 ] || continue
      plug=$(( plug + _d )); plugn=$(( plugn + 1 ))
    done
  done
fi
[ "$plugn" -gt 0 ] && row "plugin agent + command descriptions ($plugn)" "$plug" "installed_plugins.json, scope user"

# ── local slash-command descriptions ────────────────────────────────────────
# Same listing, same prefix, authored here rather than vendored. Small today
# (556 B over five commands, 2026-09-20) and counted because the reason it is
# small is that nobody has written many, which is not a property of the surface.
cmd=0; cmdn=0
for _c in "$CFG"/commands/*.md; do
  [ -f "$_c" ] || continue
  _d="$(desc_bytes "$_c")"
  [ "$_d" -gt 0 ] || continue
  cmd=$(( cmd + _d )); cmdn=$(( cmdn + 1 ))
done
[ "$cmdn" -gt 0 ] && row "local slash-command descriptions ($cmdn)" "$cmd" "${CFG#$HOME/}/commands"

# ── the cwd-keyed auto-memory index ─────────────────────────────────────────
# THE LARGEST ALWAYS-ON ITEM WAS THE ONE THIS TOOL DID NOT MEASURE. Until now
# the file had zero references to projects/*/memory, so it reported 22,035 B —
# 91% of ceiling with headroom — while the true figure was 32,506 B, 135% and
# over. A ceiling that undercounts by 10 KB is not a loose ceiling, it is a
# ceiling pointed at the wrong surface, and every decision priced off it (which
# skills to trim, whether a hook's per-fire cost beats CLAUDE.md's one-time
# cost) was priced against a number that was wrong by more than the entire
# ambient skill surface.
#
# MEASURED, NOT ASSUMED. The claim "this loads in every session" is behavioural
# and was verified behaviourally: on 2026-08-07 a session whose cwd was
# ~/harbor-unify carried the ~/.claude/projects/-Users-someone/ index in its
# own prefix, delivered as `user's auto-memory, persists across conversations`.
# That is one observation of the harness doing it, not a reading of a doc.
#
# THE KEY IS THE CWD PATH WITH `/` → `-`, AND THERE IS NO WALK-UP. The first cut
# climbed to the nearest ancestor with a store, on the strength of an observation
# that turned out to be a misreading: a session "whose cwd was ~/harbor-unify"
# carried the `-Users-someone` index, but that session's working directory was
# `$HOME` — a DIRECT slug hit, needing no climb. The walk was invented to explain
# something that never happened.
#
# FALSIFIED BEHAVIOURALLY, which is the only way this could have been settled. A
# real session started in a workload repo was asked whether it carried an auto-memory index
# and answered ABSENT, listing exactly what it did carry. Meanwhile this tool,
# walking up, was charging that session 10,908 B for a file it never loads. The
# walk made the budget OVERCOUNT by the largest single item on the box, in every
# repo — the mirror image of the undercount it was added to fix.
#
# So: direct slug match only, and the resolved path is PRINTED rather than
# summarised, because that is what makes this row falsifiable at a glance.
mem_idx="$CFG/projects/$(printf '%s' "$PWD" | tr '/' '-')/memory/MEMORY.md"
mem_local=0
if [ -f "$mem_idx" ]; then
  mem_local="$(bytes "$mem_idx")"
  row "auto-memory index (cwd-keyed)" "$mem_local" "${mem_idx#$HOME/}"
else
  printf '%-46s %8s  %s\n' "auto-memory index (cwd-keyed)" 0 "no store for this cwd — not charged"
fi

# ── THE WORST CASE, NOT THE LOCAL ONE (harbor#243) ──────────────────────────
# The row above is honest and the verdict built on it was not. The index is
# cwd-keyed with NO WALK-UP, so a session started in a repo that has no store is
# charged nothing for one — and lint X3 runs where CI runs, inside this checkout.
# It therefore measured the CHEAPEST POSSIBLE SESSION and reported a reassuring
# percentage about it: 91% with headroom from ~/harbor, 186% and over from $HOME,
# same tool, same minute. That is a check that passes because it looks in the
# place where the condition cannot occur, and it contradicted harbor#183 — the
# ticket whose whole subject is the overage — while looking more authoritative
# than the ticket, because it is automated and the ticket is prose.
#
# So the VERDICT is the worst case: the largest store on the box, whichever cwd
# owns it, because that is a session someone actually starts. The local row stays
# because it is the true answer to "what does THIS session cost". `SPENT EVERY
# SESSION` keeps its exact shape, and its last reader went away in harbor#316 —
# store-check.sh no longer parses it — so the shape is now held by this tool's own
# suite rather than by a consumer. Kept deliberately: it is a stable line other
# things have been built on before and the suite is where that promise now lives.
#
# BOUNDED ON PURPOSE: the scan covers the memory index only, not the repo-scoped
# surfaces below. A store is named by a SLUG (`/` -> `-`) and the mapping does not
# invert — `-Users-someone-harbor-ci` is `~/harbor-ci` or `~/harbor/ci` and
# nothing here can tell which — so charging a decoded cwd's CLAUDE.md would be a
# guess. The worst case is therefore a LOWER bound on the worst case, which is the
# right direction for a ceiling to be wrong in, and it is said here rather than
# discovered later.
mem_max=0
mem_max_path=""
for _i in "$CFG"/projects/*/memory/MEMORY.md; do
  [ -f "$_i" ] || continue
  _b="$(bytes "$_i")"
  if [ "$_b" -gt "$mem_max" ]; then
    mem_max="$_b"
    mem_max_path="$_i"
  fi
done
if [ -n "$mem_max_path" ] && [ "$mem_max" -gt "$mem_local" ]; then
  printf '%-46s %8s  %s\n' "  ↳ largest store on this box (not this cwd)" "$mem_max" "${mem_max_path#$HOME/}"
fi

# ── repo-scoped surfaces, which DO load and were never counted ──────────────
# `.claude/rules/*.md` every one of the 19 on this box declares
# `alwaysApply: false` with a `globs:` predicate, and a review reading that
# frontmatter concluded they cost nothing. They cost 6,450 B in one workload repo. Measured
# the only way that settles it: a fresh headless session started in that repo, asked
# with no file reads whether the rules were present, quoted BOTH of them
# verbatim and then listed all three by name.
#
# So the frontmatter is inert here — a file that declares itself conditional
# loads unconditionally. Documentation refutes documentation; only measurement
# refutes behaviour, and the flag is documentation about behaviour.
#
# Repo `CLAUDE.md` is in the same position: injected in that session, never
# counted here. AGENTS.md is deliberately NOT counted — whether the harness
# reads it is unmeasured, and a budget that guesses is the defect this whole
# section exists to repair.
repo_amb=0; repo_n=0
if [ -f "$PWD/CLAUDE.md" ]; then
  repo_amb=$(( repo_amb + $(bytes "$PWD/CLAUDE.md") )); repo_n=$(( repo_n + 1 ))
fi
for _r in "$PWD"/.claude/rules/*.md; do
  [ -f "$_r" ] || continue
  repo_amb=$(( repo_amb + $(bytes "$_r") )); repo_n=$(( repo_n + 1 ))
done
[ "$repo_n" -gt 0 ] && row "repo-scoped (CLAUDE.md + .claude/rules, $repo_n file(s))" "$repo_amb" "${PWD#$HOME/}"

# ── the SessionStart injection (harbor#316) ─────────────────────────────────
# THE TOOL'S OWN HEADLINE IS "what this session costs before the first word", and
# the injection is delivered into the prefix before the first word — as
# `attachment.type=hook_additional_context` on a transcript's record 9. It was
# never counted. #316 put the omission at 11,389 B.
#
# ASK THE INJECTOR, DO NOT RE-IMPLEMENT ITS DISPATCH. Which packs fire for
# SessionStart is decided by frontmatter predicates in inject-hook.sh, and a
# second copy of that logic here would be a copy that drifts while reading
# correctly — the thing DOCTRINE/doc-truth.md is about. So this feeds the engine a
# real SessionStart payload and measures what comes back: same path the session
# takes, which is CONSTITUTION §2.6. The probe writes nothing on a box whose
# governance salt already exists, and creates only that salt on one that has not
# run a session yet.
#
# AND THE ANSWER DEPENDS ON THE DIRECTORY, BY SEVEN TIMES. Measured 2026-09-20:
#
#     $HOME                      11,804 B      ~/harbor      1,660 B
#     ~/Deliverables/<a folder>   2,172 B      ~/<repo>      1,666 B
#
# `inject.d/repo-skills.sh` emits 9,682 B at home and ZERO inside a governed repo.
# So the largest single injected item on the box — the index to the 38 skills the
# model cannot see — reaches only sessions started outside a repo, which is the
# opposite of where the memory index lands, and both are invisible to a reader of
# the old report. The local row is what THIS session pays; the verdict takes the
# worst case, for the reason harbor#243 gives about the memory index: lint X3 runs
# from inside this checkout, which is the cheapest directory on the box.
inj_local=0; inj_max=0; inj_max_where=""
_injector="$ROOT/hooks/injection-rule/injection-rule.sh"
_inject_bytes() { # <cwd> -> bytes the SessionStart injection would deliver there
  [ -d "$1" ] || { echo 0; return; }
  # `CLAUDE_CONFIG_DIR="$CFG"` IS LOAD-BEARING, NOT TIDINESS. inject-hook.sh reads
  # its packs from that variable, so without it the probe measures the LIVE box
  # from inside a fixture — which is how this first shipped and how the suite
  # caught it: two under-ceiling cases went OVER because a synthetic config dir
  # was charged ~/.claude's 11 KB of packs. It is also what makes the shadow-dir
  # method work, the one that measures a proposed demotion without a single write
  # to the live instruction surface.
  ( cd "$1" 2>/dev/null || exit 0
    printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"context-budget-probe","cwd":"%s"}' "$1" \
      | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$1" sh "$_injector" 2>/dev/null | wc -c | tr -d ' ' ) 2>/dev/null || echo 0
}
# ONLY FOR THE LIVE CONFIG DIR, AND THE REASON IS A PROPERTY OF THE INJECTOR.
# `CLAUDE_CONFIG_DIR` does NOT isolate this surface: inject-hook.sh loads packs
# from two tiers, and when the second — `$REPO/.claude/inject.d`, where REPO
# falls back to the probed directory — resolves under $HOME, the LIVE packs load
# whatever $CFG says. Measured 2026-09-20: an empty config dir still returned
# 11,791 B at $HOME. So a shadow-dir run would charge the fixture the real box's
# injection, which is how the suite caught this: two under-ceiling cases went
# OVER by ~11 KB they do not own. It also means the shadow-config-dir method that
# falsified the skill demotions does NOT isolate the injection — only the
# constitution and the skill listing. Said here because the next person to reach
# for that method will assume it isolates everything.
# `LIVE_DIR=` is lint D1's sanctioned idiom for NAMING the live dir rather than
# reading state through a hardcoded path, and naming it is the entire operation
# here: nothing is read from it, it is only compared against $CFG so the probe can
# refuse. Physically, because /tmp and /private/tmp are one directory and two
# strings — the same reason D2 exists.
LIVE_DIR="$HOME/.claude"
_cfg_is_live=0
[ "$(cd -P -- "$CFG" 2>/dev/null && pwd -P)" = "$(cd -P -- "$LIVE_DIR" 2>/dev/null && pwd -P)" ] && _cfg_is_live=1
if [ "$_cfg_is_live" -eq 0 ]; then
  printf '%-46s %8s  %s\n' "SessionStart injection" 0 "NOT MEASURABLE — \$CLAUDE_CONFIG_DIR is not the live dir"
elif [ -f "$_injector" ] && [ "${HARBOR_BUDGET_NO_PROBE:-0}" != 1 ]; then
  inj_local="$(_inject_bytes "$PWD")"; : "${inj_local:=0}"
  row "SessionStart injection (this cwd)" "$inj_local" "probed via hooks/injection-rule/injection-rule.sh"
  # The worst case is a session started where no repo governs — the case that
  # carries the full hidden-skill listing. Probed rather than asserted, and named
  # in the report so the claim is falsifiable at a glance.
  inj_max="$(_inject_bytes "$HOME")"; : "${inj_max:=0}"
  inj_max_where='$HOME (no repo — carries the hidden-skill index)'
  if [ "$inj_max" -le "$inj_local" ]; then inj_max="$inj_local"; inj_max_where="this cwd"; fi
  [ "$inj_max" -gt "$inj_local" ] && \
    printf '%-46s %8s  %s\n' "  ↳ largest injection on this box (not this cwd)" "$inj_max" "$inj_max_where"
else
  printf '%-46s %8s  %s\n' "SessionStart injection" 0 "NOT PROBED — no injector, or HARBOR_BUDGET_NO_PROBE=1"
fi

# ── what L2 and D WILL add — projected, and counted separately ──────────────
# THESE ARE NOT SPENT YET, and calling them `live` made this tool cry wolf. When
# harbor#43's content landed on 2026-07-31 the four files appeared and X3 jumped
# from 96% to 133% — over by 8 KB that no session pays, because NOTHING INJECTS
# THEM: the SessionStart hooks are session-verdicts and
# context-resolve, and neither reads TELOS or IDENTITY. The telos skill
# loads its corpus on invocation, which is the invoked-only cost this tool already
# treats as free.
#
# That is the built-vs-running conflation STATUS.md exists to stop, reproduced in a
# different tool — and a ceiling that reports bytes nobody is spending gets raised
# or ignored, which is CONSTITUTION §2.11's false positive.
#
# So: two totals. The ceiling binds what is SPENT; the projection is the
# backpressure upstream built this for, printed next to it and never mistaken for
# it. BELIEFS.md is here too — it was missing while its three siblings were listed,
# so the projection understated itself.
proj=0
projn=0
for p in "$CFG/MEMORY/TELOS/TELOS.md" "$CFG/MEMORY/TELOS/GOALS.md" \
         "$CFG/MEMORY/TELOS/BELIEFS.md" "$CFG/IDENTITY.md" "$CFG/MEMORY/IDENTITY.md"; do
  if [ -f "$p" ]; then
    _b="$(bytes "$p")"
    printf '%-46s %8s  %s\n' "${p#$HOME/}" "$_b" "projected — nothing injects it today"
    proj=$(( proj + _b )); projn=$(( projn + 1 ))
  fi
done

# The worst case swaps THIS cwd's index for the largest one on the box. Where
# this cwd already owns the largest store — or the box has none at all — the two
# numbers are equal and the verdict says so by naming this cwd, so a box with no
# stores still reports a real measurement rather than a silent 0%.
# ── THE DELIBERATE SURFACE, WHICH IS THE HALF A BASELINE CAN BIND ───────────
# harbor#183 asked what a byte CEILING protects, and the answer measured out to
# nothing: capacity is refuted arithmetically (this surface is ~11k tokens, 1.1%
# of a 1M window), cost is refuted by harbor#184 (~$190/yr, ~3% of the bill, and
# it says outright the ceiling is not a cost lever), and dilution is refuted by
# E8, where 595 B and 17,845 B both score 3.00/3 — "volume is free".
#
# What the tool WAS built for is in its own header, quoting upstream:
# "backpressure against always-on context re-accretion … those files regrow". The
# concern is REGROWTH, and regrowth needs no invented absolute — it needs a prior
# measurement. So the gate becomes T1's mechanism applied to this surface: a
# recorded baseline that must match, and changing it is a commit that says why.
#
# THE SPLIT IS THE WHOLE DESIGN. Only the DELIBERATE surface is baselined —
# CLAUDE.md plus ambient skill descriptions plus repo-scoped files — because
# those change only when somebody deploys something. The memory index is excluded
# and deliberately so: it changes every time a memory is written, so baselining it
# would fire on ordinary work within a day, and §2.11 makes that the defect rather
# than the safety. store-check.sh already owns the index, with its own bound.
#
# THE INJECTION IS EXCLUDED FROM THE BASELINE FOR THE SAME REASON, AND IT IS A
# DIFFERENT ONE FROM "it changes often": it changes with the CALLER'S DIRECTORY,
# by 10 KB. A baselined number that moves when the tool is invoked from somewhere
# else is not a baseline, it is a report about the caller — the defect harbor#243
# already recorded against the verdict. It is charged to SPENT and to the WORST
# CASE, where it is true, and kept out of the row a commit has to justify.
# Plugin and command descriptions are NOT excluded: they are the same in every
# directory, and a plugin that auto-updates its agent descriptions has changed
# the prefix of every future session, which is precisely what a baseline is for.
deliberate=$(( total - mem_local - inj_local ))

worst=$(( total - mem_local + mem_max - inj_local + inj_max ))
if [ -n "$mem_max_path" ]; then
  # RESOLVE THE SYMLINK OR THE LABEL LIES. `memory-route.sh` routes governed repos
  # to the ONE $HOME silo by symlink — 25 of 200 store directories are links and
  # the 200 MEMORY.md files have 3 distinct inodes (measured 2026-09-20). The
  # loop above takes the first slug of equal size, so it reported
  # `-Users-someone-.local-lib-<tool>` for a file that IS `-Users-someone`.
  # That mattered little while the worst case was one surface; it matters now that
  # it is paired with the injection probed at $HOME, because a reader has to be
  # able to see that both maxima land in the SAME session and the compound is a
  # directory someone actually starts in, not two unrelated maxima added together.
  _mm_real="$(cd -P -- "$(dirname -- "$mem_max_path")" 2>/dev/null && pwd -P)/$(basename -- "$mem_max_path")"
  worst_where="${mem_max_path#$HOME/}"
  [ "$_mm_real" != "$mem_max_path" ] && worst_where="${mem_max_path#$HOME/} -> ${_mm_real#$HOME/}"
else
  worst_where="this cwd (${PWD#$HOME/}) — no memory store on this box"
fi

# ── THE BASELINE VERDICT (harbor#183) ───────────────────────────────────────
# --check fails when the DELIBERATE surface no longer matches the last recorded
# row; --record appends today's measurement. Placed before the report so both
# modes exit having said one thing, not two.
_bl_last=''; _bl_inst=''; _bl_bad=''
# A baseline that is there and cannot be read is not "no baseline" (review #971): --record cannot fix it.
if [ -e "$BASELINE" ] || [ -L "$BASELINE" ]; then
  if [ ! -f "$BASELINE" ]; then _bl_bad="is not a regular file"
  elif [ ! -r "$BASELINE" ]; then _bl_bad="is not readable"; fi
fi
if [ -z "$_bl_bad" ] && [ -f "$BASELINE" ]; then
  _bl_row="$(grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$' | tail -1)"
  _bl_last="$(printf '%s' "$_bl_row" | cut -f2)"
  _bl_inst="$(printf '%s' "$_bl_row" | cut -f4)"
fi
# INSTRUMENT IDENTITY (harbor#585). A byte count means nothing without the ruler:
# #316 widened the scope and the +7,018 B it brought in read as regrowth, because
# the row recorded a number and not what produced it. Identity = the surface set
# counted into `deliberate` + a digest of the two measuring functions, so a scope
# change and a method change both change it, and neither needs a human to remember.
_surf="$( [ -f "$CFG/CLAUDE.md" ] && printf claude-md || printf constitution-projected )+skills"
[ "$plugn" -gt 0 ] && _surf="$_surf+plugins"
[ "$cmdn" -gt 0 ] && _surf="$_surf+commands"
[ "$repo_n" -gt 0 ] && _surf="$_surf+repo"
_digest="$( { grep '^bytes()' "$0"; sed -n '/^desc_bytes()/,/^}/p' "$0"; } | cksum | cut -d' ' -f1 )"
INSTRUMENT="$_surf@$_digest"
case "$MODE" in
  record)
    # THE REASON IS NOT GENERATED. A row whose "why" this script wrote would be a
    # machine restating the number in the column beside it, which is the copy T2
    # exists to stop. It writes a placeholder that is obviously unfinished.
    if [ "$_BL_SEED" = 1 ]; then
      # Migration: the first record moves the history to the state directory and appends there.
      mkdir -p "$_STATE" && cp "$BASELINE" "$_STATE_BL" && BASELINE="$_STATE_BL" || { echo "context-budget: could not seed $_STATE_BL" >&2; exit 1; }
    fi
    mkdir -p "${BASELINE%/*}"
    printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$deliberate" \
      "REPLACE THIS with why the surface changed" "$INSTRUMENT" >> "$BASELINE"
    printf 'recorded %s B in %s — now write the reason in that row.\n' \
      "$deliberate" "${BASELINE#$ROOT/}" >&3
    exit 0 ;;
  check)
    # THE KIND IS THE FINDING'S SUBJECT, NOT ITS MESSAGE (harbor#585, CONTRACTS/finding.md). One
    # subject for every failure filed an instrument change and regrowth as the same finding, so
    # accepting one silenced the other. Printed only under --kind, last, on its own line.
    kind() { [ "$KIND" = 0 ] || printf 'kind=%s\n' "$1" >&3; }
    if [ -n "$_bl_bad" ]; then
      log_fail "context-budget: the baseline ${BASELINE#$ROOT/} $_bl_bad, so nothing was compared"
      log_fix "ls -l ${BASELINE#$ROOT/}   # restore it from the in-tree seed: cp CONTEXT-BASELINE.tsv ${_STATE_BL}"
      log_end || :
      kind unreadable; exit 1
    fi
    if [ -z "$_bl_last" ]; then
      log_fail "context-budget: no baseline recorded in ${BASELINE#$ROOT/}"
      log_fix "sh bin/context-budget.sh --record"
      log_end || :
      kind no-baseline; exit 1
    fi
    # A byte count that is not an integer makes -eq and -gt error out, and the fall-through once read
    # it as `shrank`, the kind most likely to be accepted as harmless (review #971).
    case "$_bl_last" in
      *[!0-9]*)
        log_fail "context-budget: the last row of ${BASELINE#$ROOT/} records '$_bl_last', not a byte count; nothing was compared"
        log_fix "sh bin/context-budget.sh --record   # then write the reason, and say the previous row was malformed"
        log_end || :
        kind malformed; exit 1 ;;
    esac
    if [ "$INSTRUMENT" != "$_bl_inst" ]; then
      # Not a delta: two numbers from two rulers have no difference to print.
      log_fail "INSTRUMENT CHANGED: last row measured with ${_bl_inst:-no instrument recorded}, this run with $INSTRUMENT; refusing to compare $_bl_last B with $deliberate B"
      log_fix "sh bin/context-budget.sh --record   # then state the split, instrument vs regrowth, in the row"
      log_end || :
      kind instrument-changed; exit 1
    fi
    if [ "$deliberate" -eq "$_bl_last" ]; then
      printf 'the deliberate always-on surface is %s B, matching the recorded baseline.\n' "$deliberate" >&3
      kind match; exit 0
    fi
    log_fail "DELIBERATE SURFACE MOVED: $_bl_last B recorded, $deliberate B measured ($( [ "$deliberate" -gt "$_bl_last" ] && printf '+' )$(( deliberate - _bl_last )) B). Every session pays this."
    log_fix "sh bin/context-budget.sh --record   # and write the reason in the row"
    log_end || :
    if [ "$deliberate" -gt "$_bl_last" ]; then kind grew; elif [ "$deliberate" -lt "$_bl_last" ]; then kind shrank; fi
    exit 1 ;;
esac

printf '%s\n' "$_rule"
printf '%-46s %8s  %s\n' "DELIBERATE SURFACE (baselined)" "$deliberate" \
  "$( [ -n "$_bl_last" ] && printf 'recorded %s' "$_bl_last" || printf 'no baseline recorded' )"
# THE `ceiling <n>` TOKEN IS AN INTERFACE, NOT A VERDICT. store-check.sh seds this
# exact line to derive the memory index's allowance, and a first cut of harbor#183
# replaced the token with prose — which made store-check print "No verdict on
# size: the allowance is derived … and it did not yield one". It degraded honestly,
# which is the only reason that was a five-minute regression instead of a silent
# wrong bound. The annotation goes AFTER the number, where store-check's trailing
# `.*` absorbs it.
printf '%-46s %8s  ceiling %s — an allowance basis, NOT a surface bound (harbor#183)\n' \
  "SPENT EVERY SESSION" "$total" "$CEIL"
printf '%-46s %8s  %s\n' "WORST CASE (largest store, any cwd)" "$worst" "$worst_where"
# THE ROW THAT USED TO BE HERE IS GONE, AND WHY IT WENT IS THE POINT. A first cut
# of #316 printed "the index allowance this leaves store-check", because counting
# the plugin, command and injection surfaces dropped `ceiling - (spent - index)`
# from 9,477 B to 799 B and would have made store-check demand a five-pointer
# index — §2.11's false positive, arrived at by measuring something ELSE more
# honestly. store-check.sh no longer uses that arithmetic (harbor#316, second
# half): its allowance is `always-on pointers x 150 + 600`, derived from the index
# it is measuring. So this tool has nothing to warn about, and a row describing
# another tool's formula would now be a copy of something that is no longer true.
# Removing it in the same change is the doctrine that produced the change.
[ "$projn" -gt 0 ] && printf '%-46s %8s  %s\n' "PROJECTED if D lands (memory injection)" "$(( worst + proj ))" "$projn file(s)"
printf '\n'

# THE VERDICT IS THE WORST CASE (harbor#243). It used to be $total, which made
# the answer depend on the directory the tool was invoked from — and the one
# caller that runs unattended, lint X3, is invoked from the cheapest directory on
# the box. A number that changes with the caller's cwd is not a ceiling.
pct=$(( worst * 100 / CEIL ))
lpct=$(( total * 100 / CEIL ))
if [ "$worst" -gt "$CEIL" ]; then
  echo "OVER by $(( worst - CEIL )) bytes (${pct}% of ceiling) in: $worst_where"
  [ "$worst" -ne "$total" ] && echo "This cwd costs $total (${lpct}%); the verdict is the worst case, not the local one."
  echo "Trim, or raise HARBOR_CONTEXT_CEILING deliberately and say why in the commit."
  exit 1
fi
echo "${pct}% of ceiling, $(( CEIL - worst )) bytes of headroom, worst case in: $worst_where"
[ "$worst" -ne "$total" ] && echo "This cwd costs $total (${lpct}%)."
if [ "$projn" -gt 0 ]; then
  ppct=$(( (worst + proj) * 100 / CEIL ))
  echo "Projected ${ppct}% once memory injection lands — that is the wall upstream"
  echo "built this ceiling for, and $projn file(s) are already written and waiting."
  [ "$ppct" -gt 100 ] && echo "The projection is ALREADY over. Decide before D lands, not after."
fi
if [ "$pct" -gt 75 ]; then
  echo "Above 75% on the SPENT line alone, before injection."
fi
exit 0
