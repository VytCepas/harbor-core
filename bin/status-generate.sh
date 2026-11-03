#!/usr/bin/env sh
# STATUS (harbor#3 follow-on) — generate docs/generated/status.md, the ONE place Harbor states
# a number about itself.
#
# One author for every number Harbor states about itself (harbor#3): this script DERIVES each count from the repo, docs/generated/status.md is generated and never hand-edited,
# lint T1 fails when it is stale and T2 fails when another document states a countable claim.
# Removed notes: docs/explanation/code-cases/bin-status-generate.md
#   sh status-generate.sh              # print docs/generated/status.md to stdout
#   sh status-generate.sh --check      # exit 1 if docs/generated/status.md differs (RUNS the suites)
#   sh status-generate.sh --check-fast # repo-counted fields only — no suite runs
#   sh status-generate.sh --apply      # write docs/generated/status.md + regenerate the observed report
#   sh status-generate.sh --observed   # THIS MACHINE's state — never committed
#   sh status-generate.sh --json       # both halves, machine-readable
#   sh status-generate.sh --json-fast  # ditto, suite totals read from docs/generated/status.md
#   HARBOR_STATUS_SUITE_COUNTS='floor-test=1095'   a count a real run already printed, so --check does not re-run it (see suite_count()).
#
# Two kinds of fact (harbor#91): docs/generated/status.md holds repo-derived counts only (identical on every machine, safe for CI to diff); machine state
# (what is installed, whether live bin/ lags) goes to build/observed.md, gitignored and regenerated on demand. --json carries both halves for status-dashboard-generate.sh.
# --check runs all three suites (minutes: right for CI); --check-fast skips the assertion totals and is what the linter uses.
set -eu
# --help BEFORE ANY WORK (S4, harbor#140): the first executable line, because a script that treats the flag as a request to do work makes a --help sweep run for minutes.
# The text is the header, read out of this file at runtime so it cannot drift.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
# WHERE IT WRITES (harbor#1275): docs/generated/status.md is a dev-layer file (contracts/layers.tsv). A checkout that has the layer table but
# not the file is harbor-core, whose tree is read-only at runtime, so its docs/generated/status.md and build/ go to the state directory.
# HARBOR_STATUS_IN_TREE=1 forces the tree (a dev checkout that has lost its docs/generated/status.md); a tree with no layer table is a fixture.
OUTD="$ROOT"
if [ -f "$ROOT/contracts/layers.tsv" ] && [ ! -f "$ROOT/docs/generated/status.md" ] && [ "${HARBOR_STATUS_IN_TREE:-}" != 1 ]; then
  OUTD="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}/status"
fi
# stdout is the generated document or JSON, so the run log is on stderr (contracts/logging.md). The library is
# read from this script's own directory, because HARBOR_SCOPE_ROOT may name a tree that has none.
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
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
LIVE="${HARBOR_DEPLOY_LIVE_DIR:-$HOME/.claude}"

# Each number below is COUNTED, never typed: a wrong counting method is wrong everywhere at once, one author and one blast radius.
n_rules="$(grep -c '^rule "' "$ROOT/bin/lint-conventions.sh" 2>/dev/null || echo 0)"
n_skills="$(find "$ROOT/vendor/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
# README.md is the index, not a contract (lint C1 excludes it by name too). "frozen contracts" still counts seam rows the table itself calls proposed or not first-class;
# narrowing needs a per-seam status key the README does not carry (a format change to a contract read by three repos).
n_contracts="$(find "$ROOT/contracts" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"
# The guards are the admission family's (harbor#961 W6): not the admission-hook.sh wrapper, the shared tools or a rename shim, and not library-admission.sh (a library that vetoes nothing).
n_guards="$(find "$ROOT/bin" -maxdepth 1 -type f -name 'admission-*.sh' 2>/dev/null \
  | grep -cvE '/admission-(hook|deny-hash|mutation-tier|observe-report|deny|equivalence|install|observe|remove|verify)[.]sh$' || :)"
n_cases="$( (jq '.cases | length' "$ROOT/fixtures/marker/cases.json" 2>/dev/null || echo 0) )"
# harbor#594: properties whose failure is on record and that nothing watches (contracts/unwatched.txt). REVIEW lines are not counted.
n_unwatched="$(awk '!/^#/ && $2=="UNWATCHED"' "$ROOT/contracts/unwatched.txt" 2>/dev/null | wc -l | tr -d ' ')"

# Suite sizes come from RUNNING the suites, not parsing them: a suite that no longer runs reports 0, not a stale number that looks healthy.
FAST="${FAST:-0}"

# ── A count somebody already paid for (harbor#120) ──
# HARBOR_STATUS_SUITE_COUNTS='floor-test=1095 normalize-test=94' sh status-generate.sh --check (whitespace or commas, suite named WITHOUT .sh) supplies a count a real run
# already printed, so CI does not execute floor-test twice. It must still come from a suite that printed it. A malformed value (bad key, non-integer) is a hard error, exit 2,
# never a fallback: that would leave the optimisation silently inert.
#
# suite_files <suite-without-.sh>: the file(s) that suite runs as. Keys stay the old suite names (CI passes them); floor-test is the baseline part files, summed (harbor#727, harbor#961 W2).
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

# Validated at top level, not in suite_count(): inside `$( )` an `exit 2` ends only the subshell and the caller sees an empty string.
if [ -n "${HARBOR_STATUS_SUITE_COUNTS:-}" ]; then
  for _pair in $(printf '%s' "${HARBOR_STATUS_SUITE_COUNTS:-}" | tr ',' ' '); do
    case "$_pair" in
      *=*) ;;
      *) log_fail "HARBOR_STATUS_SUITE_COUNTS: $_pair is not <suite>=<count>"; log_fix "unset HARBOR_STATUS_SUITE_COUNTS"; log_end || :; exit 2 ;;
    esac
    _k="${_pair%%=*}"; _v="${_pair#*=}"
    # The key must name an existing suite; a typo would otherwise fall through to running the suite.
    if ! suite_files "$_k" >/dev/null; then
      log_fail "HARBOR_STATUS_SUITE_COUNTS: no such suite bin/$_k.sh, nor floor-test, normalize-test or marker-test"; log_fix "unset HARBOR_STATUS_SUITE_COUNTS"; log_end || :; exit 2
    fi
    case "$_v" in
      ''|*[!0-9]*)
        log_fail "HARBOR_STATUS_SUITE_COUNTS: $_pair is not an integer count"; log_fix "unset HARBOR_STATUS_SUITE_COUNTS"; log_end || :; exit 2 ;;
    esac
  done
fi

# The override is scoped to `--check` (PR #121): --apply must never write counts it did not watch a suite print.
# Read from $1, not MODE, which is assigned after the render that calls suite_count().
INVOKED_AS="${1:-}"

# suite_supplied <suite-without-.sh> — print the supplied count, or return 1.
suite_supplied() {
  [ -n "${HARBOR_STATUS_SUITE_COUNTS:-}" ] || return 1
  # --check only compares; every other mode writes docs/generated/status.md or answers about it, and must not rest on a number no suite printed.
  [ "$INVOKED_AS" = "--check" ] || return 1
  for _p in $(printf '%s' "${HARBOR_STATUS_SUITE_COUNTS:-}" | tr ',' ' '); do
    case "$_p" in "$1"=*) printf '%s' "${_p#*=}"; return 0 ;; esac
  done
  return 1
}

# _sc_fingerprint: one hash over everything a suite result depends on, EVERY bin/ script (a guard change moves floor-test's count without touching the suite file) plus tests/.
# Empty output means no key and no cache, the slow correct path.
_sc_fingerprint() {
  # The workflow too: tests/admission/baseline/shards.test.sh reads it, or HARBOR_STATUS_WORKFLOW's proposal (harbor#727).
  # harbor#961 W2: a suite is tests/<family>/<subject>/<aspect>.test.sh, one level deeper than tests/*/.
  cat "$ROOT"/bin/*.sh "$ROOT"/bin/*.awk "$ROOT"/hooks/*/*.sh "$ROOT"/tests/*/*.sh "$ROOT"/tests/*/*/*.sh \
      "${HARBOR_STATUS_WORKFLOW:-$ROOT/.github/workflows/governance.yml}" 2>/dev/null \
    | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null; } \
    | awk '{print $1; exit}'
}

suite_count() { # <suite> <label>
  # In fast mode reuse what docs/generated/status.md records. Checked BEFORE the supplied count so --check-fast stays byte-identical whatever the environment carries.
  if [ "$FAST" = "1" ] && [ -f "$OUTD/docs/generated/status.md" ]; then
    # status.md names the suite WITHOUT its .sh; matching on "$1" verbatim found nothing and fast mode reported 0.
    _p="$(grep -F "\`${1%.sh}\`" "$OUTD/docs/generated/status.md" 2>/dev/null | grep -oE '\| [0-9]+ \|' | grep -oE '[0-9]+' | head -1)"
    printf '%s' "${_p:-0}"; return 0
  fi
  if _s="$(suite_supplied "${1%.sh}")"; then printf '%s' "$_s"; return 0; fi
  # ── Content-keyed cache: floor-test alone is ~5 minutes and a stale status.md fails T1/T1b, so --apply must be cheap ──
  # A recorded count is used only when its key (the suite file AND the bin/ scripts it exercises) is unchanged; a miss runs the suite.
  # This deliberately relaxes the rule in suite_supplied(): the earlier process ran on byte-identical inputs, and the record is machine state in build/, never committed.
  _sc_key="$(_sc_fingerprint)"
  _sc_file="$OUTD/build/suite-counts.tsv"
  if [ -n "$_sc_key" ] && [ -f "$_sc_file" ]; then
    _sc_hit="$(awk -F'\t' -v s="$1" -v k="$_sc_key" '$1==s && $2==k {print $3; exit}' "$_sc_file")"
    case "$_sc_hit" in ''|*[!0-9]*) ;; *) printf '%s' "$_sc_hit"; return 0 ;; esac
  fi
  # ── Re-entry guard, the last branch on purpose (harbor#288) ──
  # The floor suite runs this tool and this line runs the floor suite: a cycle with no base case (one stale tree reached 1,396 processes). The earlier branches usually answer first,
  # so the cycle hid; only a marker that travels with the PROCESS can say "already inside a run of myself". It yields 0 rather than failing because `exit` cannot propagate out of this `$( )`;
  # the stderr note is what separates "the suite reports zero" from "no suite was run".
  if [ -n "${HARBOR_TEST_IN_SUITE:-}" ]; then
    log_note "NOT running bin/$1: already inside a suite run (HARBOR_TEST_IN_SUITE set), and running it here is harbor#288 (the suite runs this tool, and this tool runs the suite); reporting 0 for $2 rather than recursing, no count was measured"
    printf '0'
    return 0
  fi
  # The marker is set on the child (a per-command assignment), not exported, so a second suite counted in the same run is not judged on its predecessor's marker.
  # A suite that could not run is not a suite that counted zero: keep the output and the status, and treat an unparseable result as UNMEASURED (yields 0, loudly, is NOT cached,
  # and --apply refuses to write a 0 count; see the guard in the write path). Measured: an unparseable normalize-test wrote `| 0 |` over the correct count.
  # `|| _sc_rc=$?`, not `; _sc_rc=$?`: under `set -e` in this `$( )` subshell a bare assignment aborts it on a non-zero suite exit and yields an empty row. _sc_rc is seeded for `set -u`.
  # harbor#727: one run per file suite_files names, each read by its own label
  # (`floor.b6-test: N passed`), summed. One unparseable file unmeasures the suite.
  _sc_raw="${TMPDIR:-/tmp}/.harbor-sgen-$$.out"
  _sc_measured=1; _o=0
  _sc_list="$(suite_files "${1%.sh}")" || _sc_list=""
  [ -n "$_sc_list" ] || _sc_list="$ROOT/bin/$1"
  while IFS= read -r _sc_f; do
    _sc_rc=0
    HARBOR_TEST_IN_SUITE=1 sh "$_sc_f" > "$_sc_raw" 2>&1 || _sc_rc=$?
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
    # Rewrite rather than append: a stale row must not outlive the run that replaced it. The file is a cache, not a ledger.
    if [ -f "$_sc_file" ]; then
      awk -F'\t' -v s="$1" '$1!=s' "$_sc_file" > "$_sc_file.tmp.$$" 2>/dev/null || : > "$_sc_file.tmp.$$"
      mv "$_sc_file.tmp.$$" "$_sc_file"
    fi
    printf '%s\t%s\t%s\n' "$1" "$_sc_key" "$_o" >> "$_sc_file"
  fi
  printf '%s' "$_o"
}

# ── OBSERVED STATE, computed on demand (harbor#91) ──
# A function, not top-level: these probes fork jq four times and cmp per script, and --check-fast uses none of them. Built is not running, and that decides whether a control protects anything.
compute_observed() {
# Match the entrypoint as a whole path segment, never a bare substring: every B2-B6 guard is wired THROUGH admission-hook.sh (admission-install.sh), and a bare `guard-` once flipped
# this row to yes on a machine with none of B2-B6. Wiring alone is not enough: the row reads yes only when the scripts are also present.
_hook_re='(^|/)admission-hook[.]sh([[:space:]]|$)'
floor_installed="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e --arg re "$_hook_re" \
       '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test($re))) | length > 0' \
       "$LIVE/settings.json" >/dev/null 2>&1; then
    # Every control the row names, not a subset (annotate-web.sh is the B4 PostToolUse guard): a partial install must not read as complete.
    _missing=0
    for _g in admission-hook.sh library-admission.sh admission-bash.sh admission-egress.sh \
              admission-self-edit.sh annotate-web.sh admission-normalize.awk; do
      [ -s "$LIVE/bin/$_g" ] || _missing=$((_missing + 1))
    done
    if [ "$_missing" -eq 0 ]; then
      floor_installed="yes"
    else
      floor_installed="wired, but $_missing guard file(s) MISSING"
    fi
  fi
fi

# B6 is a separate install (admission-install.sh --with-b6) and gets its own row, so a complete B2-B5 install is not reported "no"; each row claims exactly what it checks.
b6_installed="no"
if [ -s "$LIVE/bin/admission-integrity.sh" ]; then
  b6_installed="present, not wired"
  if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1 \
     && jq -e '[.hooks.SessionStart[]?.hooks[]?.command]
               | map(select(test("admission-integrity[.]sh"))) | length > 0' \
          "$LIVE/settings.json" >/dev/null 2>&1; then
    b6_installed="yes"
  fi
fi

# prod_guard is not part of the floor (yard's guard owns the cloud/data corpus, admission-bash.sh), so it gets its own row; sharing evidence is how the substring defect stayed invisible.
prod_guard_live="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '[.hooks.PreToolUse[]?.hooks[]?.command]
            | map(select(test("(^|/)prod-guard-ambient[.]sh([[:space:]]|$)"))) | length > 0' \
       "$LIVE/settings.json" >/dev/null 2>&1; then prod_guard_live="yes"; fi
fi
# B1 has no hooks, so the check above says "no" for a host with the deny layer live: ask the deny list directly via an entry only admission-deny.sh writes,
# and report whether the harbor#53 mis-anchored spellings remain (the tool is append-only).
deny_installed="no"
if [ -f "$LIVE/settings.json" ] && command -v jq >/dev/null 2>&1; then
  _dl='(.permissions.deny // [])'
  if jq -e "$_dl | index(\"Edit(~/.claude/.helm-floor-teeth)\")" "$LIVE/settings.json" >/dev/null 2>&1; then
    if jq -e "$_dl | index(\"Edit(//**/.github/workflows/**)\")" "$LIVE/settings.json" >/dev/null 2>&1; then
      deny_installed="yes"
    else
      deny_installed="yes, but pre-harbor#53 spellings (re-run \`admission-deny.sh --live --apply\`)"
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

# docs/generated/status.md: repo-derived only, identical on every machine, safe for CI to diff (harbor#91).
gen() {
cat <<EOF
---
kind: generated-doc
owner: harbor#3
status: generated
source: sh bin/status-generate.sh --apply
---
<!-- generated-by: sh bin/status-generate.sh --apply -->
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

# The observed half: generated, gitignored, never committed, and carries its own timestamp (an undated observation is indistinguishable from a stale one).
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

# jq --arg for every string, never a printf'd JSON literal: deny_installed carries backticks and a quoted command (CONSTITUTION 4).
json() {
  # --json carries BOTH halves: status-dashboard-generate.sh consumes the observed keys.
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

# `;;&` is a bashism and this file runs under /bin/sh: set the flag in its own case, then dispatch.
MODE="${1:-}"
case "$MODE" in --check-fast|--json-fast) FAST=1 ;; esac
case "$MODE" in
  # Temp-then-mv: `gen > status.md` truncated the file before gen ran, so a mid-generation failure left it EMPTY and every later --check-fast then read 0 assertions (observed).
  # A generator must not destroy its own source of truth and report success.
  --apply)
    # `gen > "$_o"` BARE, not `if ! gen` or `gen || {...}`: those suspend `set -e` for the whole function body, so a failure mid-generation keeps going and writes a plausible-but-wrong file.
    # Bare, a failure kills the script HERE, the trap removes the temp and status.md is never opened.
    log_head "apply"
    mkdir -p "$OUTD/docs/generated"
    _o="$OUTD/docs/generated/status.md.tmp.$$"
    trap 'rm -f "$_o"; _sg_clean' EXIT INT TERM HUP
    gen > "$_o"
    _sg_unmeasured
    [ -s "$_o" ] || { log_fail "generation produced an EMPTY file: docs/generated/status.md left UNCHANGED"; log_fix "sh $0 --apply"; log_end || :; exit 1; }
    # A zero assertion count is as broken as an empty file: no suite here has zero assertions, so the row can only mean the suite did not run (a plausible-but-wrong file is worse than an empty one).
    # Checked on the RENDERED TEXT because suite_count() runs in `$( )` and cannot set a variable; this also catches the re-entry arm's deliberate 0. The test is "positive integer" (the value can be empty), not "is zero".
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
    # The observed half rides along, but its failure must not fail the status.md write that already succeeded (build/ may be absent or read-only).
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
