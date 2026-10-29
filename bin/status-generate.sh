#!/usr/bin/env sh
# STATUS (harbor#3 follow-on) — generate docs/generated/status.md, the ONE place Harbor states
# a number about itself.
#
# WHY THIS EXISTS. A coverage sweep on 2026-07-26 found the same fact stated
# differently in three documents, repeatedly:
#   contracts/README.md said "18 rules" and "492 assertions"  (actual: 21, 573)
#   docs/reference/provenance.md said "19 skills"                            (actual: 28)
#   docs/reports/qa-plan.md §6 listed risks OPEN that §7 of the same file said had shipped
# None of these were lies when written. They rotted, because a count in prose is
# a copy of a fact that lives somewhere else, and copies drift.
#
# The fix is not to check the copies harder. It is to stop making them:
#   • this script DERIVES every count from the repo,
#   • docs/generated/status.md is generated and never hand-edited,
#   • lint rule T1 fails when docs/generated/status.md is stale,
#   • lint rule T2 fails when any OTHER document states a countable claim.
#
# So "how many lint rules are there" has exactly one answer with exactly one
# author, and a doc that wants to say it links instead of copying.
#
#   sh status-generate.sh              # print docs/generated/status.md to stdout
#   sh status-generate.sh --check      # exit 1 if docs/generated/status.md differs (RUNS the suites)
#   sh status-generate.sh --check-fast # repo-counted fields only — no suite runs
#   sh status-generate.sh --apply      # write docs/generated/status.md + regenerate the observed report
#   sh status-generate.sh --observed   # THIS MACHINE's state — never committed
#   sh status-generate.sh --json       # both halves, machine-readable
#   sh status-generate.sh --json-fast  # ditto, suite totals read from docs/generated/status.md
#
#   HARBOR_SUITE_COUNTS='floor-test=1095'   # a count a real run already printed,
#                                           # so --check does not re-run it. See
#                                           # the block above suite_count().
#
# ── TWO KINDS OF FACT, AND ONLY ONE OF THEM BELONGS IN GIT (harbor#91) ───────
#
# docs/generated/status.md used to carry an "Observed on this machine" section — which layers of
# the floor are installed, whether the live bin/ lags the repo. That is MACHINE
# STATE inside a version-controlled file that CI diffs, and CI runs on a
# self-hosted runner which IS this Mac, so every deploy moved one of the values:
#
#   1. change a bin/ script  → the committed value goes stale (lagging N)
#   2. deploy it             → stale the other way (lagging 0)
#   3. regenerate, commit again
#
# Measured cost in one day: three regenerate-and-commit cycles and one red main
# (cbe9783 — T1 plus every job downstream of it). Silent until push, because the
# pre-commit hook runs --check-fast while CI runs the full check. The workaround
# was "deploy before regenerating", an ordering nothing enforces, which is exactly
# the shape this repo converts into a rule rather than a habit.
#
# WHY NOT JUST DROP THE SECTION FROM T1. Because it earns its keep: "built" and
# "running" are different facts, Harbor's prose has conflated them repeatedly, and
# this table caught the floor row reading **yes** with none of the floor
# installed. Excluding it from the check would let the observed rows rot silently
# — the very defect they exist to prevent.
#
# So the two are SPLIT rather than merged or dropped:
#   • docs/generated/status.md          repo-derived counts only. Deterministic, identical on
#                        every machine, safe for CI to diff. T1 now checks
#                        something that CANNOT vary by host.
#   • build/observed.md  machine state. Generated, gitignored, regenerated on
#                        demand, never committed, and therefore never stale in
#                        the only sense that matters — it is written the moment
#                        it is read.
#
# The observed rows lose nothing by leaving git: nobody diffs them across
# machines, and `--json` still carries both halves for status-dashboard-generate.sh.
#
# --json exists so a SECOND view (bin/status-dashboard-generate.sh) can render these numbers
# without becoming a copy of them. T2 forbids another document stating a count in
# prose; the same reasoning applies to a chart, and a chart is worse — nobody
# greps a chart for the stale number. One author, many views.
#
# --check runs all three suites, which takes minutes. That is right for CI and
# wrong for a pre-commit hook, so the linter uses --check-fast: it compares
# everything countable from the tree and skips the three assertion totals. CI
# runs the full check, so a suite that silently stops reporting is still caught —
# just at push time rather than at commit time.
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
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
# WHERE IT WRITES (harbor#1275): docs/generated/status.md is a dev-layer file (contracts/layers.tsv). A checkout that has the layer table but
# not the file is harbor-core, whose tree is read-only at runtime, so its docs/generated/status.md and build/ go to the state directory.
# HARBOR_STATUS_IN_TREE=1 forces the tree (a dev checkout that has lost its docs/generated/status.md); a tree with no layer table is a fixture.
OUTD="$ROOT"
if [ -f "$ROOT/contracts/layers.tsv" ] && [ ! -f "$ROOT/docs/generated/status.md" ] && [ "${HARBOR_STATUS_IN_TREE:-}" != 1 ]; then
  OUTD="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}/status"
fi
# stdout is the generated document or JSON, so the run log is on stderr (contracts/logging.md). The library is
# read from this script's own directory, because HARBOR_ROOT may name a tree that has none.
LOG_FD=2
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init status-gen
# A suite that prints no count is recorded here by suite_count(), which runs in a `$( )` subshell whose log
# counters would be lost; the run reports them from this shell, once, as WARNs (_sg_unmeasured).
_SG_UNM="${TMPDIR:-/tmp}/.harbor-sgen-unm-$$"
_sg_clean() { rm -f "$_SG_UNM"; }
trap '_sg_clean' EXIT INT TERM HUP
_sg_unmeasured() {
  [ -s "$_SG_UNM" ] || return 0
  _sg_tab="$(printf '\t')"
  while IFS="$_sg_tab" read -r _u_path _u_rc _u_label _u_first; do
    log_warn "$_u_path printed NO parseable assertion count (exit $_u_rc; its first line of output was: ${_u_first:-none}): $_u_label is UNMEASURED, not zero, so nothing is cached and --apply will refuse a docs/generated/status.md carrying this row"
    log_fix "sh $ROOT/$_u_path"
  done < "$_SG_UNM"
  : > "$_SG_UNM"
}
LIVE="${HARBOR_DEPLOY_LIVE_DIR:-${HELM_LIVE_DIR:-$HOME/.claude}}"

# Each number below is COUNTED, never typed. If a counting method is wrong the
# number is wrong everywhere at once, which is the failure mode we want: one
# author, one blast radius.
n_rules="$(grep -c '^rule "' "$ROOT/bin/lint-conventions.sh" 2>/dev/null || echo 0)"
n_skills="$(find "$ROOT/vendor/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
# README.md IS THE INDEX, NOT A CONTRACT, and counting it made this row disagree
# with the table it summarises: 11 against the README's 10 seam rows. Lint C1
# already excludes it by name for exactly this reason
# (lint-conventions.sh:764 — `[ "$b" = "README.md" ] && continue`), so this is the
# existing precedent applied to the count rather than a new judgement.
#
# WHAT THIS ROW STILL OVERSTATES, said here because the honest number is not
# derivable: three of the ten seam rows describe themselves as "not yet
# first-class — freeze here" or "proposed", so "frozen contracts" counts as frozen
# three things the table itself says are not. Narrowing it needs a per-seam status
# key the README does not carry, which is a format change to a tracked contract
# read by three repos — filed, not guessed at here.
n_contracts="$(find "$ROOT/contracts" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
# guard-lib.sh matches `guard-*.sh` and is a 45 KB LIBRARY, not a guard: it
# vetoes nothing, is wired to no hook, and is sourced by the others (and by the
# worklog hooks). Counting it reported one floor guard more than exists, so any
# document quoting that number promised a guard that is not there and any
# "guards N/M" indicator carried an unreachable target. A glob is not a census.
n_guards="$(find "$ROOT/bin" -name 'guard-*.sh' ! -name 'guard-lib.sh' 2>/dev/null | wc -l | tr -d ' ')"
n_cases="$( (jq '.cases | length' "$ROOT/fixtures/marker/cases.json" 2>/dev/null || echo 0) )"
# harbor#594: properties whose failure is on record and that nothing watches. The
# list is contracts/unwatched.txt; the number is here so git history is its trend,
# and a sweep never has to rediscover it. REVIEW lines are judgements no machine
# can watch and are not counted.
n_unwatched="$(awk '!/^#/ && $2=="UNWATCHED"' "$ROOT/contracts/unwatched.txt" 2>/dev/null | wc -l | tr -d ' ')"

# Suite sizes come from RUNNING the suites, not from parsing them. A suite that
# no longer runs reports 0 here rather than a stale number that looks healthy —
# which is the same "prove it by firing it" discipline floor-verify.sh uses.
FAST="${FAST:-0}"

# ── A COUNT SOMEBODY ALREADY PAID FOR (harbor#120) ───────────────────────────
#
# `--check` catches a suite that silently stops reporting, and it did that by
# RUNNING each suite. In CI that means floor-test.sh executes TWICE per run:
# once as the `security-floor suite` job, once again here. Measured 2026-08-05
# on run 30951660497 — 254s there and 243s here, inside a 16m41s wall clock. The
# second execution measures nothing the first one did not.
#
# So a count may be SUPPLIED by whoever already paid for it:
#
#   HARBOR_SUITE_COUNTS='floor-test=1095 normalize-test=94' sh status-generate.sh --check
#
# Separators are whitespace or commas. The suite is named WITHOUT `.sh`, the way
# docs/generated/status.md names it.
#
# THE GUARANTEE IS UNCHANGED, and that is the whole reason the number is taken
# from a run rather than from a parse: the value still has to come from a suite
# that actually printed it. A suite that stops reporting prints no count line,
# the supplier passes an empty value, and the validator below refuses it. It is
# strictly STRONGER than the status quo in one way — today's second run can
# disagree with the first and nothing compares them.
#
# A MALFORMED VALUE IS A HARD ERROR, NEVER A FALLBACK. Quietly running the suite
# on a typo'd suite name would leave this optimisation permanently inert while
# reading as applied: CI stays slow, the operator believes it is fixed, and
# nothing ever goes red. That is the "green test that cannot fail" shape
# policy/constitution.md §2.11 exists for, so a bad key or a non-integer exits 2.
#
# suite_files <suite-without-.sh> — the file(s) that suite runs as, one per line.
# harbor#727: bin/<name>.sh until it moves. The keys stay the old suite names, which CI passes in
# HARBOR_SUITE_COUNTS; harbor#961 W2 moved the files: floor-test is tests/admission/baseline/baseline.test.sh
# plus its <part>.test.sh siblings (the count is the parts' sum), normalize-test and marker-test one file each.
suite_files() {
  if [ -f "$ROOT/bin/$1.sh" ]; then printf '%s\n' "$ROOT/bin/$1.sh"; return 0; fi
  case "$1" in
    floor-test) _sf="$ROOT/tests/admission/baseline/baseline.test.sh" ;;
    normalize-test) _sf="$ROOT/tests/admission/normalize/normalize.test.sh" ;;
    marker-test) _sf="$ROOT/tests/scope/marker/marker.test.sh" ;;
    *) return 1 ;;
  esac
  [ -f "$_sf" ] || return 1
  printf '%s\n' "$_sf"
  [ "$1" = floor-test ] || return 0
  find "${_sf%/*}" -name '*.test.sh' ! -name baseline.test.sh 2>/dev/null | sort
}

# VALIDATED HERE, AT TOP LEVEL, and deliberately not inside suite_count():
# suite_count() runs inside a `$( )` command substitution, where `exit 2` ends
# only the subshell and the caller carries on with an empty string — so a
# rejected value would have been indistinguishable from "the suite reported 0".
if [ -n "${HARBOR_SUITE_COUNTS:-}" ]; then
  for _pair in $(printf '%s' "$HARBOR_SUITE_COUNTS" | tr ',' ' '); do
    case "$_pair" in
      *=*) ;;
      *) log_fail "HARBOR_SUITE_COUNTS: $_pair is not <suite>=<count>"; log_fix "unset HARBOR_SUITE_COUNTS"; log_end || :; exit 2 ;;
    esac
    _k="${_pair%%=*}"; _v="${_pair#*=}"
    # The key must name a suite that EXISTS. Without this a typo falls through to
    # running the suite, which is the silently-inert case described above.
    if ! suite_files "$_k" >/dev/null; then
      log_fail "HARBOR_SUITE_COUNTS: no such suite bin/$_k.sh, nor floor-test, normalize-test or marker-test"; log_fix "unset HARBOR_SUITE_COUNTS"; log_end || :; exit 2
    fi
    case "$_v" in
      ''|*[!0-9]*)
        log_fail "HARBOR_SUITE_COUNTS: $_pair is not an integer count"; log_fix "unset HARBOR_SUITE_COUNTS"; log_end || :; exit 2 ;;
    esac
  done
fi

# ── THE OVERRIDE IS SCOPED TO `--check`, AND NOTHING ELSE (PR #121 review) ───
#
# The first cut honoured HARBOR_SUITE_COUNTS in EVERY generation mode. So an
# operator who exported the variable — in a shell profile, or once for a CI
# experiment — would find `--apply` writing those numbers straight into docs/generated/status.md
# without running anything. That corrupts the one file the T rules make the single
# source of truth, silently, while reporting success. The whole point of deriving
# counts by RUNNING a suite is lost the moment the writer accepts them on trust.
#
# Read from `$1` rather than the later MODE variable on purpose: MODE is assigned
# far below, after the render that calls suite_count(), so gating on it would read
# an empty string and permit everything.
INVOKED_AS="${1:-}"

# suite_supplied <suite-without-.sh> — print the supplied count, or return 1.
suite_supplied() {
  [ -n "${HARBOR_SUITE_COUNTS:-}" ] || return 1
  # `--check` is the only mode that merely COMPARES. Every other mode either
  # writes docs/generated/status.md or answers a question about it, and neither may rest on a
  # number this process did not watch a suite print.
  [ "$INVOKED_AS" = "--check" ] || return 1
  for _p in $(printf '%s' "$HARBOR_SUITE_COUNTS" | tr ',' ' '); do
    case "$_p" in "$1"=*) printf '%s' "${_p#*=}"; return 0 ;; esac
  done
  return 1
}

# _sc_fingerprint — one hash over everything a suite result depends on.
#
# EVERY bin/ SCRIPT, NOT JUST THE SUITE FILE. floor-test builds its fixture from
# the guards in bin/ and reports how many assertions PASSED, so a guard change
# can move the number without touching the suite. Keying on the suite alone
# would serve a confident, wrong count for exactly the change most worth
# catching.
#
# Cost is two forks and ~10ms against 292s, so there is no reason to narrow it.
# Empty output means no key, and no key means no cache — the slow, correct path.
# harbor#727: tests/ too, since the count-bearing suites and their harness moved there.
_sc_fingerprint() {
  # The workflow too: tests/admission/baseline/shards.test.sh reads it, or HARBOR_WORKFLOW's proposal (harbor#727).
  # harbor#961 W2: a suite is tests/<family>/<subject>/<aspect>.test.sh, one level deeper than tests/*/.
  cat "$ROOT"/bin/*.sh "$ROOT"/bin/*.awk "$ROOT"/hooks/*/*.sh "$ROOT"/tests/*/*.sh "$ROOT"/tests/*/*/*.sh \
      "${HARBOR_WORKFLOW:-$ROOT/.github/workflows/governance.yml}" 2>/dev/null \
    | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } \
    | awk '{print $1; exit}'
}

suite_count() { # <suite> <label>
  # In fast mode reuse whatever docs/generated/status.md already records, so the diff is
  # confined to the fields fast mode actually recomputes. Checked BEFORE the
  # supplied count so every pre-existing path stays byte-identical: the
  # pre-commit hook's --check-fast must not change behaviour because some
  # unrelated environment happens to carry the variable.
  if [ "$FAST" = "1" ] && [ -f "$OUTD/docs/generated/status.md" ]; then
    # docs/generated/status.md names the suite WITHOUT its .sh — matching on "$1" verbatim
    # found nothing, so fast mode reported 0 and disagreed with the full check.
    _p="$(grep -F "\`${1%.sh}\`" "$OUTD/docs/generated/status.md" 2>/dev/null | grep -oE '\| [0-9]+ \|' | grep -oE '[0-9]+' | head -1)"
    printf '%s' "${_p:-0}"; return 0
  fi
  if _s="$(suite_supplied "${1%.sh}")"; then printf '%s' "$_s"; return 0; fi
  # ── CONTENT-KEYED CACHE, BECAUSE floor-test IS FIVE MINUTES ────────────────
  # `--apply` ran every suite to scrape one integer each, and `floor-test.sh`
  # alone is 292s of that — measured 2026-08-22, 1438 assertions at ~200ms
  # apiece. Regeneration is not an occasional act: T1 and T1b fail on a stale
  # docs/generated/status.md, so any commit that changes a counted fact needs one, and at five
  # minutes it gets backgrounded, killed, and left half-written. This tool left
  # a docs/generated/status.md.tmp.<pid> behind twice in one session that way. A gate that slow
  # is a gate people route around (§2.11), and the count was never the thing
  # worth waiting for.
  #
  # WHAT THE CACHE DOES NOT DO IS BELIEVE ITSELF. A recorded count is used only
  # when the bytes it was measured against are unchanged. The key is the content
  # of everything a suite result depends on — the suite file AND the bin/
  # scripts it exercises, because "N passed" drops when a guard regresses, not
  # only when an assertion is added. Miss, and the suite runs. Editing one
  # character anywhere in bin/ is a miss.
  #
  # THIS IS A REAL RELAXATION OF THE RULE ABOVE, stated rather than smuggled.
  # suite_supplied() refuses a supplied count outside `--check` because "neither
  # may rest on a number this process did not watch a suite print". A cache hit
  # is exactly that: a number some EARLIER process watched. What makes it
  # honest is that the earlier process ran against byte-identical inputs, and
  # the record is machine state in build/ — never committed, so nothing here
  # travels to another box claiming to be measured there.
  _sc_key="$(_sc_fingerprint)"
  _sc_file="$OUTD/build/suite-counts.tsv"
  if [ -n "$_sc_key" ] && [ -f "$_sc_file" ]; then
    _sc_hit="$(awk -F'\t' -v s="$1" -v k="$_sc_key" '$1==s && $2==k {print $3; exit}' "$_sc_file")"
    case "$_sc_hit" in ''|*[!0-9]*) ;; *) printf '%s' "$_sc_hit"; return 0 ;; esac
  fi
  # ── THE RE-ENTRY GUARD, AND IT IS THE LAST BRANCH ON PURPOSE (harbor#288) ──
  # The floor suite runs this tool (VIZ-1 and STATUS-1's `_obs`, in its status
  # part), and this line runs the floor suite. That is a cycle with no base case,
  # and on 2026-08-23 it reached 1,396 processes and load 35.6 from one stale copy of
  # the tree. It did not stop on its own, and `pkill` by pattern could not
  # converge — kill rate matched spawn rate at ~650 for twelve rounds.
  #
  # WHAT USED TO BOUND IT WAS NEVER A GUARD. Three earlier branches answer without
  # running anything — the FAST read of docs/generated/status.md, a supplied count, the
  # content-keyed cache — and in a normal checkout one of them always hits, so the
  # cycle was invisible for as long as it existed. Measured with a stub in place of
  # the suite: a copied `bin/` with nothing beside it has no docs/generated/status.md to read and
  # no cache to hit, and control arrives here. A cache is a performance measure and
  # a `-f docs/generated/status.md` test is a question about a directory; neither can express
  # "I am already inside a run of myself". This can, because the marker travels
  # with the PROCESS.
  #
  # IT YIELDS 0 RATHER THAN FAILING, and that is a deliberate, bounded choice. An
  # `exit` here would not propagate: suite_count() runs inside `$( )`, which the
  # note at the head of this file already records as the reason HARBOR_SUITE_COUNTS
  # is validated at top level. Every nested caller that exists today is answered by
  # one of the three branches above — VIZ-1 and `_obs` are `--json-fast` against a
  # tree that has docs/generated/status.md, `_sgen --apply` carries FAST=1 and a seeded fixture,
  # `_sgc --check` supplies its counts — so this arm is reached only in the shape
  # that used to fork-bomb, where a loud 0 is the correct answer and a running
  # suite is not. The stderr line is not decoration: it is the only thing that
  # distinguishes "the suite reports zero" from "no suite was run".
  if [ -n "${HARBOR_IN_SUITE:-}" ]; then
    log_note "NOT running bin/$1: already inside a suite run (HARBOR_IN_SUITE set), and running it here is harbor#288 (the suite runs this tool, and this tool runs the suite); reporting 0 for $2 rather than recursing, no count was measured"
    printf '0'
    return 0
  fi
  # THE MARKER IS SET ON THE CHILD, NOT EXPORTED HERE. A per-command assignment
  # scopes it to exactly the process that must not come back — this shell keeps
  # whatever it was handed, so a second suite counted in the same generation is
  # judged on its own and not on its predecessor's marker.
  # A SUITE THAT COULD NOT RUN IS NOT A SUITE THAT COUNTED ZERO. This was
  #
  #   _o="$(... sh "$ROOT/bin/$1" 2>/dev/null | grep -oE ... | head -1)"
  #   _o="${_o:-0}"
  #
  # which discards the suite's exit status (it is a pipeline, so `$?` is grep's),
  # sends every diagnostic it printed to /dev/null, and then coerces "no summary
  # line was found" to the number 0. The comment forty lines up already states the
  # distinction this line erased — "the only thing that distinguishes 'the suite
  # reports zero' from 'no suite was run'" — and makes it for the recursion arm
  # while leaving it unmade here.
  #
  # MEASURED 2026-09-06, and it is not hypothetical. bin/normalize-test.sh could
  # not be PARSED by dash (one `$'…'`), so on Linux it printed a syntax error to
  # the stderr this line threw away, matched nothing, and `--apply` wrote
  # `| normalize-test assertions | 0 |` into docs/generated/status.md over the correct 173 —
  # silently, reporting success. floor-test and marker-test were written low the
  # same way. The generator that exists so no count is ever hand-typed had put
  # three wrong numbers in the file every other document must link to instead of
  # restating.
  #
  # SO: keep the output, keep the status, and treat an unparseable result as
  # UNMEASURED. It still yields 0 and still returns, for the reason the recursion
  # arm records — `exit` cannot propagate out of the `$( )` this runs inside — but
  # it is now loud, and the two consequences below are closed:
  #   · it is NOT cached, so build/suite-counts.tsv cannot serve the bad number to
  #     every later --check-fast (the pre-commit hook) until someone deletes it;
  #   · --apply REFUSES to write a file carrying a 0 assertion count (see the
  #     guard beside the `-s` test in the write path), so the zero cannot land.
  # `|| _sc_rc=$?` AND NOT `; _sc_rc=$?`. This file runs under `set -e`, and
  # suite_count() runs inside `$( )` — a subshell — so a bare `cmd; rc=$?` aborts
  # that subshell the instant the suite exits non-zero, before the assignment
  # happens. The substitution then yields the EMPTY STRING and the rendered row
  # reads `| |`, which is a different wrong answer from the `| 0 |` this change is
  # about and slips past a guard written for the digit. Caught by running it:
  # the first cut of this patch produced exactly that. An AND-OR list suspends
  # `set -e` for this one simple command, which is what makes the status readable.
  # `_sc_rc` is seeded because `set -u` would otherwise abort on the success path,
  # where the `||` branch never runs.
  # harbor#727: one run per file suite_files names, each read by its own label
  # (`floor.b6-test: N passed`), summed. One unparseable file unmeasures the suite.
  _sc_raw="${TMPDIR:-/tmp}/.harbor-sgen-$$.out"
  _sc_measured=1; _o=0
  _sc_list="$(suite_files "${1%.sh}")" || _sc_list=""
  [ -n "$_sc_list" ] || _sc_list="$ROOT/bin/$1"
  while IFS= read -r _sc_f; do
    _sc_rc=0
    HARBOR_IN_SUITE=1 sh "$_sc_f" > "$_sc_raw" 2>&1 || _sc_rc=$?
    _sc_n="$(awk -v k="$(basename "$_sc_f" .sh):" '$1 == k && $3 == "passed," { print $2; exit }' "$_sc_raw" 2>/dev/null)"
    case "${_sc_n:-}" in
      ''|*[!0-9]*)
        _sc_measured=0
        printf '%s\t%s\t%s\t%s\n' "${_sc_f#"$ROOT"/}" "$_sc_rc" "$2" "$(head -1 "$_sc_raw" 2>/dev/null | tr '\t' ' ')" >> "$_SG_UNM" ;;
      *) _o=$((_o + _sc_n)) ;;
    esac
  done <<EOF
$_sc_list
EOF
  [ "$_sc_measured" = 1 ] || _o=0
  rm -f "$_sc_raw"
  if [ "$_sc_measured" = 1 ] && [ -n "$_sc_key" ]; then
    mkdir -p "$OUTD/build"
    # Rewrite rather than append: a stale row for this suite must not outlive
    # the run that replaced it, or a later fingerprint collision reads the old
    # one. The file is a cache, not a ledger — nothing reads its history.
    if [ -f "$_sc_file" ]; then
      awk -F'\t' -v s="$1" '$1!=s' "$_sc_file" > "$_sc_file.tmp.$$" 2>/dev/null || : > "$_sc_file.tmp.$$"
      mv "$_sc_file.tmp.$$" "$_sc_file"
    fi
    printf '%s\t%s\t%s\n' "$1" "$_sc_key" "$_o" >> "$_sc_file"
  fi
  printf '%s' "$_o"
}

# ── OBSERVED STATE, computed on demand ──────────────────────────────────────
# Wrapped in a function rather than run at top level (harbor#91). These probes
# fork jq four times and `cmp` once per script in bin/, and the pre-commit hook's
# --check-fast path does not use a single one of them — it now compares only the
# repo-derived half, so paying for a full drift scan on every commit was pure
# latency in the one place a slow gate gets disabled.
#
# The live install is part of the truth. Harbor's docs have repeatedly conflated
# "built" with "running", and that distinction decides whether a control
# protects anything.
compute_observed() {
#
# MATCH THE ENTRYPOINT AS A WHOLE PATH SEGMENT, never a bare substring. Every
# B2–B6 guard is wired THROUGH floor-hook.sh (floor-install.sh:89-100 and
# :153-157), so that basename is the one string this layer cannot be installed
# without. The predicate here used to be test("guard-"), and on 2026-08-01 the
# ambient prod_guard shim — `prod-guard-ambient.sh`, which is NOT part of the
# floor — put the substring `guard-` into the hook list and flipped this row to
# **yes** on a machine carrying none of B2–B6. DEAD-ENDS DE-22 already recorded
# "a bare substring standing in for a control"; this file re-committed it, in
# the one field whose whole job is to tell built from running.
#
# WIRING ALONE IS NOT ENOUGH. A hook entry pointing at a guard that is not on
# disk is exactly the silent shape this table exists to expose, so the row only
# reads "yes" when the scripts are also present — the same pairing floor-verify
# checks in its sections 1 and 2.
_hook_re='(^|/)floor-hook[.]sh([[:space:]]|$)'
floor_installed="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e --arg re "$_hook_re" \
       '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test($re))) | length > 0' \
       "$LIVE/settings.json" >/dev/null 2>&1; then
    # EVERY CONTROL THE ROW NAMES, not a subset. annotate-web.sh is the B4
    # PostToolUse guard and floor-install.sh wires it alongside the others; it
    # was absent from this list, so a live dir missing it still reported the
    # row as satisfied — the same partial-install-reads-as-complete shape this
    # predicate exists to prevent, one level in. Raised by review on #80.
    _missing=0
    for _g in floor-hook.sh guard-lib.sh guard-bash.sh guard-egress.sh \
              guard-selfedit.sh annotate-web.sh floor-normalize.awk; do
      [ -s "$LIVE/bin/$_g" ] || _missing=$((_missing + 1))
    done
    if [ "$_missing" -eq 0 ]; then
      floor_installed="yes"
    else
      floor_installed="wired, but $_missing guard file(s) MISSING"
    fi
  fi
fi

# B6 IS A SEPARATE INSTALL AND GETS A SEPARATE ROW. floor-install.sh ships it
# only under --with-b6, and floor-verify prints "B6 not installed (expected
# until the floor is verified)" — so folding it into the row above would make a
# correct, complete B2–B5 install report "no", which is the false-negative half
# of the same defect. The row above is narrowed to B2–B5 for the same reason:
# a row must claim exactly what it checks.
b6_installed="no"
if [ -s "$LIVE/bin/guard-integrity.sh" ]; then
  b6_installed="present, not wired"
  if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1 \
     && jq -e '[.hooks.SessionStart[]?.hooks[]?.command]
               | map(select(test("guard-integrity[.]sh"))) | length > 0' \
          "$LIVE/settings.json" >/dev/null 2>&1; then
    b6_installed="yes"
  fi
fi

# prod_guard is NOT part of the floor at all. The floor deliberately omits the
# cloud/data corpus (guard-bash.sh:6-8) because yard's guard owns it, so
# this is a separate control with a separate install path and it gets its own
# row. Giving it one is also what stops the floor's row from borrowing its
# evidence, which is precisely how the substring defect above stayed invisible.
prod_guard_live="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command]
            | map(select(test("(^|/)prod-guard-ambient[.]sh([[:space:]]|$)"))) | length > 0' \
       "$LIVE/settings.json" >/dev/null 2>&1; then prod_guard_live="yes"; fi
fi
# B1 has NO hooks, so the check above reports "no" for a host where the deny layer
# is fully live. Ask the deny list directly, via an entry only floor-deny.sh
# writes. Also report whether the live list still carries the harbor#53
# mis-anchored spellings: floor-deny.sh is append-only, so re-running the fixed
# tool ADDS the working patterns and leaves the dead ones behind, and a reader
# who greps for "workflows" would find a hit either way.
deny_installed="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _dl='(.permissions.deny // [])'
  if jq -e "$_dl | index(\"Edit(~/.claude/.helm-floor-teeth)\")" "$LIVE/settings.json" >/dev/null 2>&1; then
    if jq -e "$_dl | index(\"Edit(//**/.github/workflows/**)\")" "$LIVE/settings.json" >/dev/null 2>&1; then
      deny_installed="yes"
    else
      deny_installed="yes, but pre-harbor#53 spellings (re-run \`floor-deny.sh --live --apply\`)"
    fi
  fi
fi
constitution_live="no"; [ -f "$LIVE/CLAUDE.md" ] && constitution_live="yes"
n_drift=0
if [ -d "$LIVE/bin" ]; then
  for f in "$ROOT"/bin/*.sh $(sh "$ROOT/bin/deploy-hooks.sh" --engines --root "$ROOT" 2>/dev/null); do
    b="$(basename "$f")"; [ -f "$LIVE/bin/$b" ] || continue
    cmp -s "$f" "$LIVE/bin/$b" || n_drift=$((n_drift + 1))
  done
fi
}

# docs/generated/status.md — REPO-DERIVED ONLY. Every value below is computed from tracked files
# and is therefore identical on every machine that checks the tree out, which is
# the property that makes it safe for CI to diff (harbor#91).
gen() {
cat <<EOF
# STATUS — generated, do not edit

Every number Harbor states about itself lives here and nowhere else.
Regenerate with \`sh bin/status-generate.sh --apply\`; lint rule **T1** fails if this
file is stale, and **T2** fails if another document states one of these counts
in prose.

This exists because the same fact was found stated three different ways across
three documents on 2026-07-26 — none of them wrong when written, all of them
copies of a fact that lives in the code.

Everything here is **counted from the repo**, so it reads the same on every
machine. What is true of THIS machine — which layers of the floor are actually
installed, whether the live \`bin/\` lags — is a different kind of fact and is
deliberately not in git: it moved on every deploy and reddened CI until someone
regenerated it. Ask for it when you want it:

\`\`\`
sh bin/status-generate.sh --observed      # or: harbor status --observed
\`\`\`

## Counted from the repo

| | |
|---|---|
| lint rules | $n_rules |
| vendored skills | $n_skills |
| frozen contracts | $n_contracts |
| floor guards | $n_guards |
| shared marker fixtures | $n_cases |
| recorded failures nothing watches | $n_unwatched |
| \`floor-test\` assertions | $(suite_count floor-test.sh floor-test) |
| \`normalize-test\` assertions | $(suite_count normalize-test.sh normalize-test) |
| \`marker-test\` assertions | $(suite_count marker-test.sh marker-test) |
EOF
}

# THE OBSERVED HALF — generated, gitignored, never committed. It carries its own
# timestamp because that is the one thing a machine-state report must say: an
# undated observation is indistinguishable from a stale one, and staleness is
# precisely what moving it out of git is meant to make impossible.
gen_observed() {
compute_observed
cat <<EOF
# OBSERVED — this machine, $(date -u '+%Y-%m-%dT%H:%M:%SZ')

Generated by \`sh bin/status-generate.sh --observed\`. **Not tracked** (\`build/\` is
gitignored) and never committed: these values move on every deploy, and a copy of
them in git is stale the moment it lands. Regenerate rather than trust a saved one.

These are the rows that decide whether a control protects anything. "Built" and
"running" are different facts and Harbor's prose has conflated them before.

The floor installs in two independent layers and one boolean hid that: B1 is a
\`permissions.deny\` list with no hooks, so on 2026-07-29 B1 went live and this
table still read "installed: no" — the same built-vs-running conflation one level
down. Each layer gets its own row.

| | |
|---|---|
| B1 deny layer installed (harness, pre-hook) | **$deny_installed** |
| B2–B5 guard hooks installed | **$floor_installed** |
| B6 integrity gate installed (separate \`--with-b6\` step) | **$b6_installed** |
| B10 ambient \`prod_guard\` wired (cloud/data — not part of the floor) | **$prod_guard_live** |
| constitution in force (\`~/.claude/CLAUDE.md\`) | **$constitution_live** |
| live \`bin/\` scripts lagging the repo | **$n_drift** |

Repo-derived counts live in [docs/generated/status.md](../docs/generated/status.md), which IS tracked.
EOF
}

# jq --arg for every string, never a printf'd JSON literal: `deny_installed`
# carries backticks, parentheses and a quoted command, and hand-built JSON with
# operator-visible strings in it is the injection shape CONSTITUTION №4 names.
json() {
  # --json carries BOTH halves and always has. It is not committed, so the
  # harbor#91 split does not reach it: status-dashboard-generate.sh consumes the observed
  # keys and would otherwise lose the rows it draws.
  compute_observed
  jq -n \
    --argjson rules    "$n_rules" \
    --argjson skills   "$n_skills" \
    --argjson contracts "$n_contracts" \
    --argjson guards   "$n_guards" \
    --argjson cases    "$n_cases" \
    --argjson unwatched "$n_unwatched" \
    --argjson floor    "$(suite_count floor-test.sh floor-test)" \
    --argjson norm     "$(suite_count normalize-test.sh normalize-test)" \
    --argjson marker   "$(suite_count marker-test.sh marker-test)" \
    --argjson drift    "$n_drift" \
    --arg deny         "$deny_installed" \
    --arg hooks        "$floor_installed" \
    --arg prodguard    "$prod_guard_live" \
    --arg b6           "$b6_installed" \
    --arg constitution "$constitution_live" \
    '{counted: {lint_rules: $rules, vendored_skills: $skills, frozen_contracts: $contracts,
                floor_guards: $guards, marker_fixtures: $cases, unwatched: $unwatched},
      assertions: {"floor-test": $floor, "normalize-test": $norm, "marker-test": $marker},
      observed: {b1_deny: $deny, guard_hooks: $hooks, b6_gate: $b6, prod_guard: $prodguard,
                 constitution: $constitution, live_bin_lagging: $drift}}'
}

# `;;&` is a bashism and this file runs under /bin/sh — set the flag in its own
# case, then dispatch.
MODE="${1:-}"
case "$MODE" in --check-fast|--json-fast) FAST=1 ;; esac
case "$MODE" in
  # TEMP-THEN-mv, and this is not hygiene — it is a reproduction. `gen > docs/generated/status.md`
  # let the SHELL truncate the file to zero before `gen` ran, so a mid-generation
  # failure (gen runs three suites under `set -eu`) left docs/generated/status.md EMPTY, and the
  # `;` meant "wrote ..." printed anyway. Observed 2026-07-29: a run under load
  # emptied it, and the damage compounds — suite_count()'s FAST path READS the
  # existing docs/generated/status.md, so a truncated file makes every subsequent `--check-fast`
  # (the pre-commit hook) report 0 assertions per suite and agree with itself.
  # A generator that destroys its own source of truth on failure, then reports
  # success, is the exact shape floor-deny.sh's write_settings() exists for.
  --apply)
    # `gen > "$_o"` BARE, not `if ! gen`, and not `gen || {...}`. Both of those
    # put gen inside an AND-OR/condition context, where POSIX suspends `set -e`
    # FOR THE WHOLE FUNCTION BODY — so a failure mid-generation stops aborting,
    # gen runs on with bad data, and a plausible-but-wrong docs/generated/status.md gets written
    # and reported as success. That is strictly worse than the truncation this
    # block replaced: a zero-byte file is obviously broken, a wrong one is not.
    # Measured both ways before choosing.
    #
    # Bare, `set -e` still armed inside gen: a failure kills the script HERE,
    # the trap removes the temp, and docs/generated/status.md is never opened at all.
    log_head "apply"
    mkdir -p "$OUTD/docs/generated"
    _o="$OUTD/docs/generated/status.md.tmp.$$"
    trap 'rm -f "$_o"; _sg_clean' EXIT INT TERM HUP
    gen > "$_o"
    _sg_unmeasured
    [ -s "$_o" ] || { log_fail "generation produced an EMPTY file: docs/generated/status.md left UNCHANGED"; log_fix "sh $0 --apply"; log_end || :; exit 1; }
    # AND A ZERO ASSERTION COUNT IS AS BROKEN AS AN EMPTY FILE, for the same
    # reason one line up: a zero-byte docs/generated/status.md is obviously wrong, and a
    # plausible-but-wrong one is not. No suite in this repo has zero assertions,
    # so the row can only mean the suite did not run — which suite_count() now
    # says out loud, and this refuses to commit to disk. Measured 2026-09-06: an
    # unparseable normalize-test wrote `| 0 |` here and reported success.
    #
    # The check reads the RENDERED TEXT rather than a flag from suite_count(),
    # because that function runs inside `$( )` and cannot set a variable in this
    # shell — the same constraint the recursion arm and the top-level
    # HARBOR_SUITE_COUNTS validation are both shaped by. It therefore also catches
    # the recursion arm's deliberate 0, which is correct: that 0 is a safe answer
    # to give a caller, never a number to write into the file others link to.
    # NOT `grep '| 0 |'`. The value can also come out EMPTY — see the `||` note in
    # suite_count() — so the test is "is this a positive integer", never "is this
    # the digit zero". Splitting on `|` puts the count in field 3.
    _sg_bad="$(awk -F'|' '/assertions \|/ {
                 v = $3; gsub(/[ \t]/, "", v)
                 if (v !~ /^[1-9][0-9]*$/) printf "  line %s: %s\n", NR, $0
               }' "$_o")"
    if [ -n "$_sg_bad" ]; then
      log_fail "an assertion count is not a positive integer: docs/generated/status.md left UNCHANGED (no suite here has zero assertions, so one did not run; the WARN lines above name which)"
      log_fix "sh $0 --apply  # after the suite named above prints its count"
      printf '%s\n' "$_sg_bad" | while IFS= read -r _sg_l; do log_note "$_sg_l"; done
      log_end || :; exit 1
    fi
    mv "$_o" "$OUTD/docs/generated/status.md"
    trap '_sg_clean' EXIT INT TERM HUP
    log_ok "wrote $OUTD/docs/generated/status.md"
    # The observed half rides along, so one command still refreshes everything a
    # reader wants — it simply lands somewhere git does not follow. Failure here
    # must NOT fail the docs/generated/status.md write that already succeeded: the report is a
    # convenience, and `build/` may be absent or read-only on a checkout that has
    # never rendered anything.
    if mkdir -p "$OUTD/build" 2>/dev/null; then
      _ob="$OUTD/build/observed.md.tmp.$$"
      if gen_observed > "$_ob" 2>/dev/null && [ -s "$_ob" ]; then
        mv "$_ob" "$OUTD/build/observed.md"
        log_ok "wrote $OUTD/build/observed.md (gitignored, machine state)"
      else
        rm -f "$_ob"
        log_warn "could not render build/observed.md (docs/generated/status.md is written and correct)"
        log_fix "sh $0 --observed"
      fi
    fi
    log_end; exit $? ;;
  --observed)
    log_head "observed"
    gen_observed
    log_ok "rendered the machine-state report to stdout"
    log_end; exit $? ;;
  --check|--check-fast)
    log_head "check"
    if [ ! -f "$OUTD/docs/generated/status.md" ]; then log_fail "docs/generated/status.md is missing ($OUTD/docs/generated/status.md)"; log_fix "sh $0 --apply"; log_end || :; exit 1; fi
    _t="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; gen > "$_t"
    _sg_unmeasured
    if cmp -s "$_t" "$OUTD/docs/generated/status.md"; then rm -f "$_t"; log_ok "docs/generated/status.md is current"; log_end; exit $?; fi
    log_fail "docs/generated/status.md is stale ($OUTD/docs/generated/status.md)"
    log_fix "sh $0 --apply"
    diff "$OUTD/docs/generated/status.md" "$_t" | head -20 | while IFS= read -r _sg_l; do log_note "diff: $_sg_l"; done || true
    rm -f "$_t"; log_end || :; exit 1 ;;
  --json|--json-fast)
    log_head "json"
    json
    _sg_unmeasured
    log_ok "wrote the counts as JSON to stdout"
    log_end; exit $? ;;
  *)
    log_head "generate"
    gen
    _sg_unmeasured
    log_ok "wrote the docs/generated/status.md text to stdout"
    log_end; exit $? ;;
esac
