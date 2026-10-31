#!/usr/bin/env sh
# deploy-doctor.sh — probe the external tools Harbor's doctrine depends on.
# harbor#3 (workstream B) + M1, method from upstream `Doctor` @ a4e8e74 (docs/reference/provenance.md).
#
# WHY THIS EXISTS, precisely. B9 was filed because a missing `jq` made every
# guard exit 0 on 'rm -rf /' — the floor did not fail loudly, it failed OPEN and
# silently. B9 fixed that one dependency. Nothing enumerates the other nineteen.
#
# So each row here names WHAT BREAKS, not just whether the binary is present. A
# prober that prints "gitleaks: missing" and stops has told you the cheap half.
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
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
JSON=0
case "${1:-}" in --json) JSON=1 ;; esac
# The probe table and --json are the report (deploy-live-verify.sh reads the rows), so the run log is on stderr.
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init doctor

miss=0; degraded=0
rows=''

probe() { # <bin> <severity: fatal|degraded|optional> <what breaks>
  _b="$1"; _sev="$2"; _why="$3"
  if _p="$(command -v "$_b" 2>/dev/null)"; then
    _st=ok
  else
    _st=missing
    case "$_sev" in
      fatal)    miss=$(( miss + 1 )) ;;
      degraded) degraded=$(( degraded + 1 )) ;;
    esac
    _p=''
  fi
  rows="$rows$_b|$_st|$_sev|$_p|$_why
"
}

# ── fatal: the floor fails OPEN or the recovery path cannot run ─────────────
probe jq       fatal    "every guard parses its hook payload with jq; without it admission-hook.sh is the only thing between a missing parse and a silent allow (B9)"
probe grep     fatal    "the rule interpreter itself. FLOOR_GREP pins /usr/bin/grep precisely so PATH cannot change a security verdict"
probe awk      fatal    "admission-normalize.awk builds the segment table every Bash rule reads"
probe sed      fatal    "used throughout the guards and the installer"
probe git      fatal    "deploy-restore.sh, baseline pinning, doc-freshness.sh and the work-log all assume it"

# ── degraded: a real control silently stops protecting ──────────────────────
probe gitleaks degraded "the work-log push gate is FAIL-CLOSED by design (worklog-push.sh refuses to push unscanned), AND bin/eval-replay-corpus.sh refuses to build a corpus it can only vet with its own scrubber — measured: gitleaks caught 5 records the scrubber passed"
# The description deliberately does NOT spell the bash ANSI-C quoting construct
# out: F12 scans this file too, and a literal example inside the string is a
# finding. Same shape as harbor#226's probe-becomes-the-finding, third instance
# in this pass.
probe shellcheck degraded "lint rule F12 is the only mechanism against a bashism reaching a dash box, and without this it verifies NOTHING and says so. One bash ANSI-C quoted string in normalize-test.sh made that whole suite unparseable under dash — it reported 0 assertions where docs/generated/status.md claimed 173, and status-gen wrote the 0"
probe gh       degraded "doc-cite-verify.sh falls back to anonymous curl, which 404s on this PRIVATE repo and reports live citations as broken"
probe curl     degraded "doc-cite-verify.sh cannot verify anything"
probe find     degraded "status-generate.sh counts, test-sandbox-make.sh, marker fixtures"
probe diff     degraded "recover-test.sh proves byte-identity after a restore; without it the restore is unverified"
# CI-only until 2026-07-29, when governance.yml moved to a self-hosted runner and
# these stopped being someone else's problem. A hosted runner installs what it
# needs; a self-hosted one has whatever the box has, so a missing binary here is
# a job that fails at preflight — or worse, a suite that skips quietly. doctor
# passing while CI cannot start is the exact gap this file exists to close.
probe perl     degraded "floor-test.sh bounds every hang-test with 'perl -e alarm' because timeout AND gtimeout are both absent on macOS; without perl the FIFO reproductions (O-22) cannot fail, which is worse than not running them"
probe mkfifo   degraded "the O-22 FIFO plant and the DE-11 spinner. Without it the hang reproductions silently do not reproduce anything"

# ── optional: a named feature is unavailable, nothing lies ──────────────────
probe bun      optional "skill-tools (telos, prompting, evals, context-search, knowledge) and the memory engine. The floor is deliberately zero-Bun, so this stays optional — but tests/memory/memory/memory.test.sh runs 56 engine assertions only when it can find bun, and 'optional' is why nobody noticed CI skipping all 56 on a box that HAS it: the runner service's PATH omits ~/.bun/bin (harbor#165, patches/governance-bun.patch.md). Absent here means the memory front door answers on its grep rung, which is a supported degrade, not a break"
probe python3  optional "yard's prod_guard and the trio's own tooling"
# launchctl is macOS's: Linux/WSL2 runs that job under systemd, and a "launchctl missing" note there is noise (harbor#618).
if [ "$(uname -s)" = Darwin ]; then probe launchctl optional "the fleet-snapshot refresh job (macOS only)"; fi
probe mktemp   optional "test harnesses"

# sha256: EITHER spelling is fine, neither is not.
if command -v shasum >/dev/null 2>&1 || command -v sha256sum >/dev/null 2>&1; then
  rows="${rows}sha256|ok|fatal|$(command -v shasum 2>/dev/null || command -v sha256sum)|baseline pinning and the B6 integrity gate
"
else
  rows="${rows}sha256|missing|fatal||baseline pinning and the B6 integrity gate CANNOT VERIFY — the gate would have nothing to compare
"
  miss=$(( miss + 1 ))
fi

# The install command for a probe that is missing: a package name where it differs from the binary.
_fixcmd() { pkg_hint "$1"; }  # <bin>: the package manager this OS has (harbor#618)

# One log line per probe, in the library's shape: a present tool is ok, a missing fatal one is a FAIL with its
# install command, a missing degraded one a WARN with the same, a missing optional one a note.
_log_probes() {
  log_head "dependencies"
  while IFS='|' read -r b st sev p why; do
    [ -n "$b" ] || continue
    if [ "$st" = ok ]; then log_ok "$b present (${p:-—})"; continue; fi
    case "$sev" in
      fatal)    log_fail "$b missing — $why"; log_fix "$(_fixcmd "$b")" ;;
      degraded) log_warn "$b missing — $why"; log_fix "$(_fixcmd "$b")" ;;
      *)        log_note "$b missing — $why" ;;
    esac
  done <<ROWS
$rows
ROWS
}

if [ "$JSON" = "1" ]; then
  printf '{"missing_fatal":%d,"missing_degraded":%d,"probes":[' "$miss" "$degraded"
  _first=1
  printf '%s' "$rows" | while IFS='|' read -r b st sev p why; do
    [ -n "$b" ] || continue
    [ "$_first" = "1" ] || printf ','
    _first=0
    printf '{"tool":"%s","status":"%s","severity":"%s","path":"%s"}' "$b" "$st" "$sev" "$p"
  done
  printf ']}\n'
  _log_probes
  log_end; exit $?
fi

# The rule under the column header is part of the table (data), not a log header.
_RULE='──────────────────────────────────────────────────────────────'
printf '%-11s %-8s %-9s %s\n' TOOL STATUS SEVERITY PATH
printf '%s\n' "$_RULE"
printf '%s' "$rows" | while IFS='|' read -r b st sev p why; do
  [ -n "$b" ] || continue
  printf '%-11s %-8s %-9s %s\n' "$b" "$st" "$sev" "${p:-—}"
done
_log_probes

# Which grep actually answers matters more than whether one exists.
#
# ASK THE LIBRARY, DO NOT SCRAPE IT (harbor#371). This line used to
# sed the FLOOR_GREP assignment out of library-admission.sh and print what was left. That
# assignment is `FLOOR_GREP="${_fg:-$( [ -x /usr/bin/grep ] && echo … )}"`, so the
# scrape returned the SUBSTITUTION EXPRESSION and the report printed
#     FLOOR_GREP pin : $( [ -x /usr/bin/grep ] && echo /usr/bin/grep || echo grep )
# where the floor actually resolves /usr/bin/grep. A report whose stated purpose
# is "which grep actually answers" was printing source instead of the answer —
# the same copy-versus-derive defect the T-rules police in prose, one layer down
# in the tool that is supposed to detect it.
#
# Sourced in a SUBSHELL so guard-lib's definitions cannot leak into this script,
# and with a visible fallback: if the library cannot be read the line says so
# rather than printing an empty pin, which would read as "unset" and is a
# different and much more alarming claim.
_fg_pin="$(sh -c '. "$1/bin/library-admission.sh" >/dev/null 2>&1 && printf %s "${FLOOR_GREP:-}"' _ "$ROOT" 2>/dev/null)"
log_head "the interpreter that decides verdicts"
log_note "FLOOR_GREP pin : ${_fg_pin:-<could not resolve — bin/library-admission.sh unreadable>}"
log_note "first in PATH  : $(command -v grep)"

# THE CAVEAT IS UNCONDITIONAL, AND IT WAS NOT. It sat on the all-present branch
# alone, so it printed only when nothing was missing and nothing was degraded —
# and doctor-test asserts on it, which made that arm fail on every box carrying a
# single gap. Backwards twice over: a reader looking at a table of mostly-`ok`
# rows with one MISSING is the one most at risk of reading availability as
# correctness, and a suite arm that can only pass on a perfect box is an arm that
# reports the box rather than the code. Measured 2026-09-06 — doctor-test was
# 11/1 here and on main, for this reason alone.
if [ "$miss" -gt 0 ]; then
  log_note "$miss fatal dependency missing — the floor cannot be trusted to fail closed"
elif [ "$degraded" -gt 0 ]; then
  log_note "$degraded degraded — a control is present but cannot do its job; read the WARN lines"
fi
log_note "This is availability, not correctness — admission-verify.sh is what answers whether the floor actually blocks anything."
log_end; exit $?
