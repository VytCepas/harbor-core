#!/usr/bin/env sh
# M5 · FailureCapture (harbor#44) — JUDGE the guard-decision ledger.
#
#   sh audit-triage.sh [--live | <config-dir>] [--json] [--with-probes]
#   sh audit-triage.sh [--live | <config-dir>] --exclusion-set   (harbor#560: the digests FC-5 drops)
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): ten independent rules over one parsed record set; splitting would fork the reader, which must have exactly one implementation.
# Exit 0 = nothing in the ledger says the floor is failing. Exit 1 = something does. Exit 2 = bad usage.
# Read-only with respect to the inspected tree: it writes only inside a `mktemp -d` under umask 077 (never a guessable path), and tests/audit/triage/triage.test.sh compares the tree before and after.
# It executes no code from the directory under inspection: library-admission.sh is sourced from beside this script (same trust domain, B6-pinned), never from <dir>/bin.
# Why it exists: the L1 ledger (harbor#41) is printed by admission-observe-report.sh and judged by nothing. Scope is the ledger and the sink's own state only; hooks, dependencies, the config surface, citations and doc staleness belong to drift-reference-check.sh, deploy-doctor.sh, alert-probe.sh, lint K1/T3 and doc-freshness.sh.
# The probe list is read from the sibling admission-verify.sh at runtime, never copied (a copy drifts, and the literals tripped guard-egress secret-to-disk).
# Severities: crit = the floor is broken or blind; warn = the rules may be wrong; unknown = a source could not be read, never rendered as ok. Vocabulary is alert-probe.sh's.
# It never repairs anything: every finding points at a surface admission-self-edit.sh protects, and a system may not promote its own observations into a guard (constitution). Each finding carries its repair as text.
# Citations into admission-observe.sh and library-admission.sh name functions, not lines (harbor#119 moves every line number).
# What it cannot see is what never reached the ledger: an unwired guard (drift-reference-check.sh REF-1, alert-probe.sh), a session under HARBOR_ADMISSION_DISABLE. It also does NOT detect total silence: FC-1 needs an asymmetry between two writers, so a wiped bin/ stops both and reads clean. A clock-based "nothing lately" rule was rejected: an idle machine looks dead (No.2.11).
# Removed notes: docs/explanation/code-cases/bin-audit-triage.md
set -u

SELF="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || SELF=""
# The human report is in contracts/logging.md's line shape (harbor#771); --json and --exclusion-set are data and print no log line.
_LOGLIB=0
if [ -n "$SELF" ] && [ -f "$SELF/library-log.sh" ]; then . "$SELF/library-log.sh"; log_init failure-capture; _LOGLIB=1; fi
DIR=""
JSON=0
PROBES=0
EXCL_SET=0
for a in "$@"; do
  case "$a" in
    --live)        [ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    --json)        JSON=1 ;;
    --with-probes) PROBES=1 ;;
    --exclusion-set) EXCL_SET=1 ;;
    -h|--help)
      printf 'usage: audit-triage.sh [--live | <config-dir>] [--json] [--with-probes]\n'
      printf '  Judges the guard-decision ledger L1 writes. Exit 1 = a finding.\n'
      printf '  --with-probes  keep the verifier own probe shapes in the recurrence count\n'
      printf '  --exclusion-set  print the probe and suite digests FC-5 drops, one "<source> <digest>" per line;\n'
      printf '                   exit 1 when they cannot be derived (no ledger, no salt, no admission-verify.sh)\n'
      exit 0 ;;
    -*) printf 'failure-capture: unknown option: %s\n' "$a" >&2
        printf 'usage: audit-triage.sh [--live | <config-dir>] [--json] [--with-probes]\n' >&2
        exit 2 ;;
    *)  [ -n "$DIR" ] && { printf 'failure-capture: more than one config dir given\n' >&2; exit 2; }
        DIR="$a" ;;
  esac
done
if [ "$EXCL_SET" = 1 ] && { [ "$PROBES" = 1 ] || [ "$JSON" = 1 ]; }; then
  printf 'failure-capture: --exclusion-set prints digests only; it takes neither --with-probes nor --json\n' >&2
  exit 2
fi
[ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${DIR%/}" != "$DIR" ] && [ "$DIR" != "/" ]; do DIR="${DIR%/}"; done

# An absent config dir is an ANSWER, not a misuse — drift-reference-check.sh:57-63 and
# admission-verify.sh:44 make the same call. Nothing is installed, so nothing failed.
if [ ! -d "$DIR" ]; then
  if [ "$JSON" = 1 ]; then printf '{"dir":"%s","installed":false,"worst":"ok","findings":[]}\n' "$DIR"
  else printf 'failure-capture: no config dir at %s — nothing is installed here.\n' "$DIR" >&2; fi
  exit 0
fi

# B9: a missing jq must never read as a clean run. Exit 1, not 2: a caller filters 2 out as a usage error.
if ! command -v jq >/dev/null 2>&1; then
  printf 'failure-capture: jq not found — the ledger cannot be read.\n' >&2
  printf '  This is NOT a clean result. Install jq, then re-run.\n' >&2
  exit 1
fi

# ── the recency horizon (harbor#211) ────────────────────────────────────────
# Recurrence rules used to read the whole retained ledger and call the answer current state, leaving a standing crit for drift that had been fixed (FC-2, FC-3).
# The horizon decides severity, not existence: an older recurrence is demoted to warn carrying its date, not deleted (a verdict with no human-visible surface is FC-4's lesson).
# Seven days, because fourteen would have left the motivating pair (gates 11 days apart) in one window.
# HARBOR_AUDIT_TRIAGE_NOW pins today so fixtures do not age out. If neither date dialect resolves, FC_CUTOFF stays empty and every rule reverts to all-history: an unreadable clock must never silence a crit.
FC_HORIZON="${HARBOR_AUDIT_TRIAGE_HORIZON_DAYS:-7}"
case "$FC_HORIZON" in ''|*[!0-9]*|0) FC_HORIZON=7 ;; esac
FC_TODAY="${HARBOR_AUDIT_TRIAGE_NOW:-$(date -u +%F 2>/dev/null || true)}"
case "$FC_TODAY" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) FC_TODAY="" ;;
esac
FC_CUTOFF=""
if [ -n "$FC_TODAY" ]; then
  FC_CUTOFF="$(date -u -j -v-"${FC_HORIZON}"d -f '%Y-%m-%d' "$FC_TODAY" +%F 2>/dev/null \
            || date -u -d "$FC_TODAY - $FC_HORIZON days" +%F 2>/dev/null \
            || true)"
  case "$FC_CUTOFF" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) FC_CUTOFF="" ;;
  esac
fi

# FC-4's "still raising it" bound: yesterday or today. The 7d horizon is how far to LOOK for recurrence, not how stale an advisory may be and still count as standing. Empty = no clock: warn loudly.
FC_RECENT=""
[ -z "$FC_TODAY" ] || FC_RECENT="$(date -u -j -v-1d -f '%Y-%m-%d' "$FC_TODAY" +%F 2>/dev/null \
                 || date -u -d "$FC_TODAY - 1 day" +%F 2>/dev/null || true)"
case "$FC_RECENT" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) FC_RECENT="" ;; esac

OBS="$DIR/MEMORY/OBSERVABILITY"
SETTINGS="$DIR/settings.json"

# ── the supersession mark: when was THE FLOOR last installed ────────────────
# A wrapper deny says "a guard file was absent at time T", and floor-install replaces every guard wholesale, so a record predating it describes a floor that no longer exists (No.2.11).
# The mark is the floor-install LINE in the stamp, not the file's mtime: deploy-install-stamp.sh rewrites the whole file for any installer, so mtime moves on installs that replaced no guard.
# The stamp's clock is the commit date, earlier than the install itself, so supersession is under-stated and a crit may be kept that could have been demoted: the safe direction.
# Date granularity on purpose: `.ts[0:10]` is what FC_CUTOFF compares, and full-precision comparison needs BSD-only `date -j -f`.
FC_INSTALL_DATE=""
_fc_stamp="$DIR/.helm-install-stamp"
if [ -f "$_fc_stamp" ] && [ ! -L "$_fc_stamp" ]; then
  _fc_iw="$(awk '$1 == "floor-install" { print $3; exit }' "$_fc_stamp" 2>/dev/null || true)"
  case "${_fc_iw:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) FC_INSTALL_DATE="$(printf '%s' "$_fc_iw" | cut -c1-10)" ;;
  esac
  case "$FC_INSTALL_DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) FC_INSTALL_DATE="" ;;
  esac
fi

# ── the sibling library, sourced ONCE ────────────────────────────────────────
# Two rules need it: FC-5 (floor_obs_digest) and FC-9 (floor_host_token, harbor#119). Sourced once here: inside FC-5's block, --with-probes silently took floor_host_token away from FC-9.
# The sibling, never the inspected directory (see the header).
GL="$SELF/library-admission.sh"
GL_OK=0
if [ -n "$SELF" ] && [ -f "$GL" ] && [ ! -L "$GL" ]; then
  # shellcheck source=/dev/null
  { . "$GL"; } 2>/dev/null && GL_OK=1
fi
WORST=ok
FINDINGS=""   # one `rule<TAB>severity<TAB>subject<TAB>breaks<TAB>repair` per line
# `mktemp -d` under umask 077, never ${TMPDIR:-/tmp}/fcap.$$: `mkdir -p` succeeds on a pre-planted symlink at a predictable path, so working files landed in the attacker's target.
umask 077
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/fcap.XXXXXXXX" 2>/dev/null)" \
  || { printf 'failure-capture: cannot create a work dir\n' >&2; exit 1; }
case "$TMPD" in /*) ;; *) printf 'failure-capture: refusing a relative work dir\n' >&2; exit 1 ;; esac
trap 'rm -rf "$TMPD" 2>/dev/null' EXIT INT TERM HUP

# ok < unknown < warn < crit: "I could not look" is worse than "I looked and it was fine" (alert-probe.sh ordering; DEAD-ENDS DE-14, DE-18).
rank() { case "$1" in ok|info) echo 0 ;; unknown) echo 1 ;; warn) echo 2 ;; crit) echo 3 ;; *) echo 1 ;; esac; }
finding() { # <rule> <severity> <subject> <what-breaks> <repair>
  [ "$(rank "$2")" -gt "$(rank "$WORST")" ] && WORST="$2"
  FINDINGS="$FINDINGS$1	$2	$3	$4	$5
"
}
# Digits or zero: one empty jq result must not abort the arithmetic below.
num() { case "${1:-}" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

# ── is the floor wired at all? ───────────────────────────────────────────────
# FC-0 predicate: whole-path-segment match on admission-hook.sh, never a bare `guard-` substring (the ambient prod_guard shim satisfies it; DE-22).
FLOOR_WIRED=no
if [ -f "$SETTINGS" ] && jq -e '[.hooks.PreToolUse[]?.hooks[]?.command]
      | map(select(test("(^|/)admission-hook[.]sh([[:space:]]|$)"))) | length > 0' \
      "$SETTINGS" >/dev/null 2>&1; then FLOOR_WIRED=yes; fi

# ── read the ledger ──────────────────────────────────────────────────────────
# Rotated generations first so the series reads oldest to newest; file order is authoritative (the sink is bounded by size, not date).
# Read per host partition and tag each record with an in-flight `_host`: a census and "the drift came back" are per-machine facts, and pooling two hosts diluted a 67% drop into an 11% warn.
# Reader defects found by review, all a source that could not be read rendering as a healthy zero (DE-14):
#   - Match the two names the writer can create, not a `guard-decisions.jsonl*` glob that also reads .bak/.orig copies and double-counts.
#   - `awk 1` per file, never `cat $list`: the unquoted list word-split on a path with a space (silently zero records), and `cat` fuses a torn newline-less tail onto the next file's first line.
LEDGERS=""
if [ -d "$OBS" ]; then
  find "$OBS" -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
    2>/dev/null | sort -r > "$TMPD/ledgers" || :
  LEDGERS="$(awk 'END{print NR+0}' "$TMPD/ledgers")"
  case "$LEDGERS" in ''|0) LEDGERS="" ;; esac
fi
NREC=0
REC="$TMPD/rec.jsonl"
: > "$REC"
# read_ledgers <host-label> <file-list-path> <dest>: concatenate with the record boundary preserved, tag each record with its partition, drop what will not parse.
read_ledgers() {
  while IFS= read -r _f; do
    [ -n "${_f:-}" ] || continue
    # `awk 1 < file`, not `awk 1 -- file`: BSD awk treats `--` as a filename and every record silently vanished.
    awk 1 < "$_f" 2>/dev/null
  done < "$2" \
    | jq -c -R --arg h "$1" 'fromjson? // empty | . + {_host:$h}' >> "$3" 2>/dev/null || :
}
if [ -n "$LEDGERS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    find "$_hd" -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
      2>/dev/null | sort -r > "$TMPD/hostfiles" || :
    [ -s "$TMPD/hostfiles" ] || continue
    read_ledgers "$(basename "$_hd")" "$TMPD/hostfiles" "$REC"
  done
  # A ledger directly under OBSERVABILITY belongs to no partition (hand-placed, or a partition that lost its directory): it is read, labelled unattributed so the census rules skip it.
  find "$OBS" -maxdepth 1 -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
    2>/dev/null | sort -r > "$TMPD/loosefiles" || :
  [ -s "$TMPD/loosefiles" ] && read_ledgers "(unpartitioned)" "$TMPD/loosefiles" "$REC"
  NREC="$(num "$(awk 'END{print NR+0}' "$REC")")"
fi

# ── the SECOND ledger: tool outcomes (harbor#465) ───────────────────────────
# guard-decisions.jsonl records what the floor decided, not what the call then did, so dead pointers (harbor#462: ten followed for 34 days) were invisible.
# Read independently of the guard ledger: failure-observe.sh needs only the sink admission-observe.sh prepares, not a floor.
NTF=0
TFREC="$TMPD/tf.jsonl"
: > "$TFREC"
if [ -d "$OBS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    find "$_hd" -type f \( -name 'tool-failures.jsonl' -o -name 'tool-failures.jsonl.[0-9]*' \) \
      2>/dev/null | sort -r > "$TMPD/tffiles" || :
    [ -s "$TMPD/tffiles" ] || continue
    read_ledgers "$(basename "$_hd")" "$TMPD/tffiles" "$TFREC"
  done
  NTF="$(num "$(awk 'END{print NR+0}' "$TFREC")")"
fi

# Same whole-path-segment shape as FLOOR_WIRED.
TF_WIRED=no
if [ -f "$SETTINGS" ] && jq -e '[.hooks.PostToolUseFailure[]?.hooks[]?.command]
      | map(select(test("(^|/)failure-observe[.]sh([[:space:]]|\"|$)"))) | length > 0' \
      "$SETTINGS" >/dev/null 2>&1; then TF_WIRED=yes; fi

# ── FC-0 · the floor is wired and the ledger says nothing ────────────────────
# This tool's own blind spot: every rule reads $REC, so an empty ledger would exit 0 (drift-reference-check.sh hit the same hole, REF-6).
# The predicate is the wiring, not the directory: a box with no floor correctly has no ledger, and flagging it is a false positive (No.2.11).
if [ "$FLOOR_WIRED" = yes ] && [ "$NREC" -eq 0 ]; then
  if [ -z "$LEDGERS" ]; then
    finding FC-0 crit "$OBS" \
      "the floor is wired and no ledger exists — every guard decision on this box is unrecorded, and every other rule here reports clean" \
      "admission-observe.sh is the only component allowed to create the sink, at SessionStart: confirm it is wired, start a session, re-run"
  else
    finding FC-0 crit "$OBS" \
      "the floor is wired, ledger files exist, and not one record parses — the recorder is running and producing nothing readable" \
      "read the newest guard-decisions.jsonl by hand; a zero-byte or non-JSONL sink means floor_log_decision refused every write"
  fi
fi

# --exclusion-set on an empty ledger: there is nothing to match a digest against.
[ "$EXCL_SET" = 0 ] || [ "$NREC" -gt 0 ] || exit 1

if [ "$NREC" -gt 0 ]; then
  # One pass per question, each into a file: `printf | while read ... finding` runs in a subshell where FINDINGS and WORST die (shipped three times: lint CLI1, K1, TS1).
  count_of() { jq -r "select($1)|1" "$REC" 2>/dev/null | awk 'END{print NR+0}'; }

  # ── FC-8 · the ledger speaks a schema this tool does not know ──────────────
  # `v` is the record schema version: always 1 today, but a v:2 writer would make every count below confidently wrong. Severity `unknown` (could not read; No.2.7), reported first because it qualifies the rest.
  N_UNKNOWN_V="$(num "$(count_of '(.v|tostring) != "1"')")"
  if [ "$N_UNKNOWN_V" -gt 0 ]; then
    _vseen="$(jq -r 'select((.v|tostring) != "1")|.v|tostring' "$REC" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
    finding FC-8 unknown "schema version(s) $_vseen ($N_UNKNOWN_V of $NREC records)" \
      "this tool reads schema v1 only, so every count below was computed over records whose fields may no longer mean what it assumes" \
      "update this reader for the new record shape before believing any finding in this run"
  fi

  N_WRAPDENY="$(num "$(count_of '.g=="wrapper" and .d=="deny"')")"
  N_BLOCK="$(num "$(count_of '.d=="block"')")"
  N_DEADDG="$(num "$(count_of '.d=="block" and .h=="-"')")"

  # ── probe-digest derivation · a prerequisite for BOTH FC-1 and FC-5 ────────
  # Hoisted above the per-host rules: FC-1 needs the verify-run count and FC-5 the exclusion set (defined below FC-1 they aborted on an unbound variable under `set -u`).
  # The digest is salted, so probe digests are computable only here. The hasher is floor_obs_digest, never re-implemented (a second spelling drifts toward reporting probes as findings).
  # It comes from the SIBLING library-admission.sh, never the inspected tree (a stub there redefined finding() and turned three crits into exit 0); only the salt is read from the inspected dir, as data.
  # If the live library lags the repo copy, probes are reported rather than excluded: the safe direction, and lint X2 notices the lag.
  # `&`, `|` and `\` are escaped because the value lands on a sed REPLACEMENT side,
  # where `&` means "the whole match".
  _dirsafe="$(printf '%s' "$DIR" | sed 's/[&|\\]/\\&/g')"
  _homesafe="$(printf '%s' "${HOME:-}" | sed 's/[&|\\]/\\&/g')"
  PROBE_DIGESTS=""
  PROBE_OK=0
  FV="$SELF/admission-verify.sh"
  if [ "$PROBES" = 0 ] && [ "$GL_OK" = 1 ] && [ -f "$FV" ] && [ ! -L "$FV" ]; then
    if true; then
      # Each `probe` line is one hook payload as JSON; jq names the field each guard digests (.tool_input.command for guard-bash and guard-egress, the RESOLVED file_path for guard-selfedit via floor_norm_path).
      # One pipeline whose only output is the digest list: payloads are never written to disk (one carries a provider-token shape that guard-egress blocked as secret-to-disk).
      # `&` and `|` in $DIR are escaped before the sed substitution, or `&` corrupts the selfedit path and a probe leaks into FC-5 while the output claims exclusion.
      # The leading `(` on the case pattern below is REQUIRED: a bare pattern's `)` closes the command substitution early. Keep comments out of the substitution too (bash 3.2 re-breaks the parse).
      _pd="$(awk '/^probe[[:space:]]/ {
                    s = $0
                    i = index(s, "{"); if (i == 0) next
                    s = substr(s, i)
                    j = 0; for (k = length(s); k > 0; k--) if (substr(s, k, 1) == "}") { j = k; break }
                    if (j == 0) next
                    print substr(s, 1, j)
                  }' "$FV" 2>/dev/null \
             | sed 's/\\"/"/g' \
             | while IFS= read -r _pj; do
                 [ -n "$_pj" ] || continue
                 _pj="$(printf '%s' "$_pj" | sed "s|\$DIR|$_dirsafe|g")"
                 _subj="$(printf '%s' "$_pj" | jq -r '.tool_input.command // empty' 2>/dev/null)"
                 if [ -z "$_subj" ]; then
                   _fp="$(printf '%s' "$_pj" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
                   [ -n "$_fp" ] && _subj="$(floor_norm_path "$_fp")"
                 fi
                 [ -n "$_subj" ] || continue
                 _d="$(FLOOR_OBS_SUBJECT="$_subj" floor_obs_digest "$DIR" 2>/dev/null || printf -- -)"
                 case "$_d" in
                   ([0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) printf '%s\n' "$_d" ;;
                 esac
               done)"
      PROBE_DIGESTS="$(printf '%s' "$_pd" | tr '\n' ' ')"
      [ -n "$PROBE_DIGESTS" ] && PROBE_OK=1
    fi
  fi

  # ── suite-digest derivation · FC-5's SECOND exclusion source ───────────────
  # The floor suite fires the real guards too, so each expect_block case appends a genuine block record with the live salt, indistinguishable from an operator hitting a wall. Same argument as the probes, one source further on.
  # Kept in a separate file from $TMPD/probes: FC-1 derives the verify-run count from the probes' peak occurrence, and folding suite digests in would inflate _vruns and silence a real FC-1. FC-5 gets the union.
  # Sibling-only, and no payload reaches disk (the suite carries destructive commands and token shapes).
  # Two payload shapes: `bash_j '<cmd>'` digests the raw command, `edit_j <Tool> "<path>"` the path through floor_norm_path. Only single-quoted literals are taken; anything interpolated stays IN the count (over-reporting is the safe direction).
  # Lazy on purpose: ~690 payloads fork a hasher each and eager derivation doubled a --live run, which audit-triage-run.sh keeps short to stay off the session path (No.2.11). FC-5 filters with the probe digests first and calls this only if a row survives.
  SUITE_DIGESTS=""
  SUITE_OK=0
  SUITE_TRIED=0
  FT="$SELF/../tests/admission/baseline/baseline.test.sh"  # harbor#727: the floor suite is that part plus its siblings
  # Two sources for one fact: the suite is not on an installed box, and shipping it (474K, invoking scripts no installer ships) is the wrong repair, so the installer derives the payload strings at install time and writes them beside the scripts as data (lint X7 does not scan it).
  # It lives in $SELF, not the config root, as a security property: a wrong salt only makes exclusions MISS (over-reporting), but anyone who can append to this file could name the preimage of their own blocked command and hide it from the judge. $SELF is this script's trust domain.
  FM="$SELF/.helm-suite-payloads"
  # One extraction, two origins (suite file or manifest): the digest loop cannot tell them apart, so there is one spelling of the parse.
  _suite_lines() {
    if [ -f "$FT" ] && [ ! -L "$FT" ]; then
      for _ftf in "${FT%/*}"/fixture.sh "$FT" "${FT%/*}"/*.test.sh; do   # harbor#961 W2 layout
        { [ -f "$_ftf" ] && [ ! -L "$_ftf" ]; } || continue
        sed -n "s/.*bash_j '\\([^']*\\)'.*/C\\1/p" "$_ftf" 2>/dev/null
        sed -n 's/.*edit_j [A-Za-z][A-Za-z]* "\([^"]*\)".*/P\1/p' "$_ftf" 2>/dev/null
      done
    elif [ -f "$FM" ] && [ ! -L "$FM" ]; then
      cat "$FM" 2>/dev/null
    fi
  }
  _derive_suite() {
    [ "$SUITE_TRIED" = 0 ] || return 0
    SUITE_TRIED=1
    [ "$PROBES" = 0 ] && [ "$GL_OK" = 1 ] || return 0
    { [ -f "$FT" ] && [ ! -L "$FT" ]; } || { [ -f "$FM" ] && [ ! -L "$FM" ]; } || return 0
    _sd="$( _suite_lines \
         | sort -u \
         | while IFS= read -r _sl; do
             [ -n "$_sl" ] || continue
             _skind="$(printf '%.1s' "$_sl")"; _sraw="${_sl#?}"
             # $DIR and $HOME appear verbatim in the suite paths; substituted with `&` and `|` escaped (see _dirsafe).
             _sraw="$(printf '%s' "$_sraw" | sed "s|\$DIR|$_dirsafe|g; s|\$HOME|$_homesafe|g")"
             # A leading open paren on the case pattern is REQUIRED, as in the probe half. A payload with an unresolved dollar sign cannot be reconstructed, so it stays in the count.
             case "$_sraw" in (*'$'*) continue ;; esac
             if [ "$_skind" = P ]; then _sraw="$(floor_norm_path "$_sraw")"; fi
             [ -n "$_sraw" ] || continue
             _d="$(FLOOR_OBS_SUBJECT="$_sraw" floor_obs_digest "$DIR" 2>/dev/null || printf -- -)"
             case "$_d" in
               ([0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) printf '%s\n' "$_d" ;;
             esac
           done)"
    SUITE_DIGESTS="$(printf '%s' "$_sd" | tr '\n' ' ')"
    [ -n "$SUITE_DIGESTS" ] && SUITE_OK=1
    printf '%s\n' "$SUITE_DIGESTS" | tr ' ' '\n' | awk 'NF' | sort -u > "$TMPD/suite"
    # FC-5's exclusion set is the UNION; FC-1 keeps "$TMPD/probes" alone. One file, so the awk below keeps the single-`pf` FILENAME==pf shape.
    sort -u "$TMPD/probes" "$TMPD/suite" > "$TMPD/excl" 2>/dev/null || :
    return 0
  }

  printf '%s\n' "$PROBE_DIGESTS" | tr ' ' '\n' | awk 'NF' | sort -u > "$TMPD/probes"
  # The exclusion set starts as the probes alone; _derive_suite widens it only if FC-5 finds something the probes did not explain.
  cp "$TMPD/probes" "$TMPD/excl" 2>/dev/null || : > "$TMPD/excl"
  : > "$TMPD/suite"
  # --exclusion-set (harbor#560): the same two derivations, handed to observe-report --fp. One derivation, two readers.
  if [ "$EXCL_SET" = 1 ]; then
    [ "$PROBE_OK" = 1 ] || exit 1
    _derive_suite
    awk 'NF { print "probe " $1 }' "$TMPD/probes"
    awk 'NF { print "suite " $1 }' "$TMPD/suite"
    exit 0
  fi
  # Horizoned on LAST occurrence, counted over ALL history (harbor#211). The retained window is bounded by bytes, not days, so how much time it spans is an accident of traffic.
  # The count stays all-history: a command blocked three times over a month, the third yesterday, is a live wall. An unresolvable clock reverts to all-history.
  # A refusal is block, deny OR ask (harbor#319). A record with no digest (`-`, as every prod_guard ask) cannot be counted per command; FC-6 watches dead digests on blocks only.
  jq -r 'select((.d=="block" or .d=="deny" or .d=="ask") and .h!="-")|"\(.h) \(.r) \(.ts[0:10])"' "$REC" 2>/dev/null \
    | awk -v c="$FC_CUTOFF" '{ k = $1 " " $2; n[k]++; if ($3 > last[k]) last[k] = $3 }
                             END { for (k in n) if (c == "" || last[k] >= c) printf "%7d %s\n", n[k], k }' \
    | sort -rn > "$TMPD/recur"

  # ── DID THE EXCLUSION ACTUALLY EXCLUDE ANYTHING? ────────────────────────────
  # A digest is salted and nothing in a record says which salt, so computing six digests proves only that the salt parses NOW. test-sandbox-make.sh copies MEMORY but not the salt, so a sandbox mints a fresh one and probe shapes came through as FC-5 findings while the output claimed exclusion.
  # Decidable without the salt: if NO derived digest appears among the ledger's block digests, the exclusion removed nothing. The wording carries the innocent readings (verify never ran; salt replaced) next to the alarming one.
  _pmatch=0
  if [ -s "$TMPD/probes" ]; then
    # Block-only on purpose, unlike the recurrence count (harbor#319): every probe fires a block.
    jq -r 'select(.d=="block" and .h!="-")|.h' "$REC" 2>/dev/null | sort -u > "$TMPD/blockdg"
    _pmatch="$(num "$(awk -v pf="$TMPD/probes" \
      'FILENAME==pf{p[$1]=1;next} ($1 in p){n++} END{print n+0}' "$TMPD/probes" "$TMPD/blockdg")")"
  fi

  # Unavailable verifier means defer, never substitute (No.2.7): candidates are still reported (under-reporting is worse), but the finding says so and `probe_traffic_excluded` stays false.
  _caveat=""
  if [ "$PROBES" = 1 ]; then
    _caveat=" (--with-probes: the verifier's own shapes are INCLUDED in this count)"
    PROBE_OK=0
  elif [ "$PROBE_OK" = 0 ]; then
    _caveat=" (WARNING: the verifier's own shapes could NOT be separated — admission-verify.sh, the sibling library-admission.sh or the salt was unreadable — so the top rows may be this box's own probe traffic)"
  elif [ "$_pmatch" -eq 0 ]; then
    _caveat=" (NOTE: the verifier's probe digests were computed and NONE of them appears in this ledger, so nothing was excluded — either \`harbor verify\` has never run against it, or the salt was replaced after these records were written, in which case a probe shape can still be sitting in the rows below)"
    PROBE_OK=0
  fi

  # ── the three PER-HOST rules ───────────────────────────────────────────────
  # FC-1, FC-3 and FC-4 are evaluated per partition (a census and "came back the next day" are per-machine facts); the rest are host-agnostic, since the salt is per-install.
  # A here-doc feeds `while read`, never `printf | while read` (the subshell loses FINDINGS and WORST) and never `for _h in $PARTITIONS` (a hand-made directory name with a space splits into phantom hosts).
  count_h() { # <filter> <host>
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|1" "$REC" 2>/dev/null | awk 'END{print NR+0}'
  }
  days_h() {  # <filter> <host>
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|.ts[0:10]" "$REC" 2>/dev/null \
      | sort -u | awk 'END{print NR+0}'
  }
  # The `_r` variants ask the same questions inside the horizon (harbor#211); use them wherever severity depends on recurrence. The unwindowed pair stays for messages that say how far back it goes.
  # $FC_CUTOFF empty means no window: the filter passes everything, so an unreadable clock cannot silence a crit. The `$c==""` arm is belt-and-braces (jq's `.ts >= ""` is already true); a suite row asserts the fallback directly.
  count_hr() { # <filter> <host> — inside the horizon
    jq -r --arg h "$2" --arg c "$FC_CUTOFF" \
      "select(._host==\$h)|select(\$c==\"\" or .ts[0:10] >= \$c)|select($1)|1" \
      "$REC" 2>/dev/null | awk 'END{print NR+0}'
  }
  days_hr() { # <filter> <host> — distinct days inside the horizon
    jq -r --arg h "$2" --arg c "$FC_CUTOFF" \
      "select(._host==\$h)|select(\$c==\"\" or .ts[0:10] >= \$c)|select($1)|.ts[0:10]" \
      "$REC" 2>/dev/null | sort -u | awk 'END{print NR+0}'
  }
  last_h() { # <filter> <host> — the most recent date, for a message that must
             # say WHEN, because a demoted finding with no date is unauditable.
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|.ts[0:10]" "$REC" 2>/dev/null \
      | sort | awk 'END{print $0}'
  }
  latest_h() { # <filter> <host> — "<ts> <decision>" of the NEWEST matching record.
               # Sorted by ts, not file order (the sink is not chronological across partitions). Empty means "no evidence", never a verdict.
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|\"\(.ts) \(.d)\"" "$REC" 2>/dev/null \
      | sort | awk 'END{print $0}'
  }
  PARTITIONS="$(jq -r '._host' "$REC" 2>/dev/null | sort -u | awk '$0 != "(unpartitioned)"')"
  NPART="$(num "$(printf '%s\n' "$PARTITIONS" | awk 'NF{n++} END{print n+0}')")"

  while IFS= read -r _h; do
    [ -n "${_h:-}" ] || continue
    _tag=""; [ "$NPART" -gt 1 ] && _tag="$_h · "
    # FC-1 is deliberately NOT horizoned (harbor#211 audit). Its counts are cumulative, but windowing it was measured against the live ledger and made it fire on ordinary `harbor verify` and hand runs:
    # the window shrinks the _vruns correction faster than the gap. Making FC-1 clearable needs a ledger field separating SessionStart from hand invocation, which is a schema change.
    N_SESSION="$(num "$(count_h '.g=="session"' "$_h")")"
    N_INTEGRITY="$(num "$(count_h '.g=="integrity"' "$_h")")"
    N_GATE="$(num "$(count_h '.g=="integrity" and .d=="gate"' "$_h")")"
    N_ADVISE="$(num "$(count_h '.g=="integrity" and .d=="advise"' "$_h")")"

    # ── FC-1 · the writer is dropping records ──────────────────────────────────
    # Two independent censuses of the same event: both hooks write one record per SessionStart. floor_log_decision drops records silently by design (property 1: logging never changes a verdict).
    # Fires only when INTEGRITY exceeds SESSION: the reverse is the normal state of a box where B6 was installed after L1.
    # Verify runs are subtracted first: `harbor verify` calls admission-integrity.sh directly, which records, so each run adds an integrity record with no session record. A run fires every probe once, so the highest probe-digest occurrence count is the run count.
    # When the probe digests do not match this ledger (PROBE_OK) the denominator is uncorrectable and the rule does NOT fire (No.2.7).
    # Warn, never crit, for what survives: admission-install.sh --with-b6 and a command deploy-runtime-install.sh prints also call admission-integrity.sh, and no field tells them from a SessionStart.
    _vruns=0
    if [ "$PROBE_OK" = 1 ] && [ -s "$TMPD/probes" ]; then
      # Unwindowed, with the two counts it corrects (windowing only this half made FC-1 fire on a healthy box).
      jq -r --arg h "$_h" 'select(._host==$h and .d=="block" and .h!="-")|.h' "$REC" 2>/dev/null \
        | sort | uniq -c > "$TMPD/hostdg" || :
      _vruns="$(num "$(awk -v pf="$TMPD/probes" \
        'FILENAME==pf{p[$1]=1;next} ($2 in p && $1+0>m){m=$1+0} END{print m+0}' \
        "$TMPD/probes" "$TMPD/hostdg")")"
    fi
    _adj=$((N_INTEGRITY - _vruns))
    [ "$_adj" -lt 0 ] && _adj=0
    if [ "$PROBE_OK" != 1 ]; then
      : # the verify-run count is unavailable, so the census is uncorrectable here
    elif [ "$_adj" -ge 3 ] && [ "$N_SESSION" -eq 0 ]; then
      # After taking verify runs out, guard-integrity recorded SessionStarts and admission-observe.sh none, ever: no denominator, so observe-report cannot compute an override rate.
      finding FC-1 crit "${_tag}no session census exists" \
        "$_adj session-start records from the integrity gate that verify runs do not explain, and NOT ONE from admission-observe.sh — so there is no denominator, and observe-report refuses the override rate rather than printing one" \
        "check that admission-observe.sh is wired at SessionStart and reaches its last line; it exits 0 on every failure path by design, so a broken run looks exactly like a quiet one"
    elif [ "$((_adj - N_SESSION))" -ge 3 ]; then
      _gap=$((_adj - N_SESSION))
      finding FC-1 warn "${_tag}session census does not reconcile" \
        "$N_SESSION session records against $N_INTEGRITY from the integrity gate, of which $_vruns are accounted for by \`harbor verify\` runs — leaving $_gap SessionStart(s) recorded by one hook and not the other. Either admission-observe.sh is dropping records silently (it exits 0 on every failure path by design), or admission-integrity.sh was invoked by hand — admission-install.sh --with-b6 and deploy-runtime-install.sh both do that, and no field in the record tells them apart" \
        "reconcile per day (jq over .g and .ts[0:10], counting a probe digest per verify run) before suspecting the hook; admission-observe.sh holds the host dir at 0700 between its own chmods, so a record landing inside a CONCURRENT session's window is refused by the [ ! -w ] gate"
    fi

    # ── FC-3 · the integrity gate blocked a session ────────────────────────────
    # The only control that can stop a whole session, and it exits 0 (it denies via {"continue":false}). One episode is the control working; a return on a later day means the recovery it printed did not clear the drift.
    # Clustered by DAY, not raw count: four gates inside twelve minutes were one drift and one operator fixing it, and calling that a failed recovery is a No.2.11 false positive. The day count is taken inside the horizon (harbor#211), so two episodes eleven days apart are not one drift that survived a night.
    if [ "$N_GATE" -gt 0 ]; then
      _gdays="$(num "$(days_h  '.g=="integrity" and .d=="gate"' "$_h")")"
      _gdaysr="$(num "$(days_hr '.g=="integrity" and .d=="gate"' "$_h")")"
      _ngater="$(num "$(count_hr '.g=="integrity" and .d=="gate"' "$_h")")"
      _glast="$(last_h '.g=="integrity" and .d=="gate"' "$_h")"
      # Recurrence is necessary but not sufficient for crit: the ledger's own newest integrity verdict must still be a gate. Two independent drifts, each cleared within the hour, were once reported as one unresolved drift while every verdict since read clean.
      # `advise` and `allow` both count as cleared: admission-integrity.sh reaches either only when no blocking drift was found. A gate-only ledger stays crit (latest_h returns "gate"); demotion needs a POSITIVE clean record, never absence of evidence.
      _glatest="$(latest_h '.g=="integrity"' "$_h")"
      _gldec="${_glatest##* }"; _glts="${_glatest%% *}"
      if [ "$_gdaysr" -ge 2 ] && [ "$_gldec" = gate ]; then
        finding FC-3 crit "${_tag}integrity gate (x$_ngater on $_gdaysr separate days in the last ${FC_HORIZON}d, still gating)" \
          "the B6 drift gate has BLOCKED a session at start on $_gdaysr different days inside ${FC_HORIZON} days, and the most recent integrity verdict in the ledger is STILL a gate — the drift is not cleared" \
          "read the drift class in the gate's own message, then act from your OWN terminal: deploy-restore.sh to undo the change, or re-pin deliberately if it was intended"
      elif [ "$_gdaysr" -ge 2 ]; then
        # Recurrence inside the window but the gate is demonstrably clear: warn, dated on both ends so it can be falsified.
        finding FC-3 warn "${_tag}integrity gate (x$_ngater on $_gdaysr separate days in the last ${FC_HORIZON}d), last fired $_glast — clear since $_glts" \
          "the B6 drift gate blocked on $_gdaysr separate days inside the window, but the ledger's most recent integrity verdict is \`$_gldec\`, not a gate — separate drifts, each cleared, rather than one that is still returning. Recurrence is evidence the recovery is not holding only while the gate is STILL firing" \
          "no action: B6 read clean at $_glts. This returns to crit the moment a gate blocks again and stays the newest integrity verdict — which is the state that means your recovery did not hold."
      elif [ "$_gdays" -ge 2 ]; then
        # History, not state: warn keeps the record where a human reviews it, off the SessionStart channel.
        finding FC-3 warn "${_tag}integrity gate (x$N_GATE on $_gdays days, none since $_glast)" \
          "the B6 drift gate has blocked on $_gdays separate days in the retained ledger, but NOT inside the last ${FC_HORIZON} days — separate episodes, each apparently cleared, rather than one drift that is still returning" \
          "no action: this is history. It returns to crit the moment a gate blocks on two days inside the window."
      elif [ "$_gdaysr" -ge 1 ]; then
        finding FC-3 warn "${_tag}integrity gate (x$_ngater in one day)" \
          "a session was BLOCKED at start by the B6 drift gate — one episode, which is the gate working; a second day would mean the recovery it printed is not clearing the drift" \
          "no action if you resolved it; if it returns tomorrow, the recovery the gate names is not the one that clears your drift class"
      fi
    fi

    # ── FC-4 · a standing advisory nobody has cleared ──────────────────────────
    # An advisory repeating across days is drift the operator has stopped reading (observe-report grew --advise in harbor#303; this finding says it is STANDING).
    # Horizoned (harbor#211) as the predicate, not a severity split: an advisory that stopped days ago has been cleared and is no longer a finding.
    if [ "$N_ADVISE" -gt 0 ]; then
      _days="$(num "$(days_hr '.g=="integrity" and .d=="advise"' "$_h")")"
      _nadvr="$(num "$(count_hr '.g=="integrity" and .d=="advise"' "$_h")")"
      _advlast="$(last_h '.g=="integrity" and .d=="advise"' "$_h")"
      # A cause fixed days ago leaves history that still spans two days; only a recent advisory says it is standing.
      if [ "$_days" -ge 2 ] && { [ -z "$FC_RECENT" ] || [ "$(printf '%s\n%s\n' "$_advlast" "$FC_RECENT" | sort | tail -n1)" = "$_advlast" ]; }; then
        finding FC-4 warn "${_tag}integrity advisory (x$_nadvr over ${_days}d)" \
          "the integrity gate has raised an advisory on $_days separate days inside the last ${FC_HORIZON} and is still raising it" \
          "list them with admission-observe-report.sh --advise and read the cause with harbor verify; for pin drift, review the changed surfaces and re-pin from your own terminal"
      fi
    fi

  done <<PARTITION_LIST
$PARTITIONS
PARTITION_LIST

  # ── FC-2 · the floor could not reach a verdict ─────────────────────────────
  # The wrapper's own denies: "the floor is broken", not "a rule fired". Without them a jq outage reads as a quiet drop in blocks; on the --advisory path it does not deny at all, so a record is the only witness (admission-hook.sh).
  # The wording must not say "N calls were blocked": fail-closed and advisory wiring write the identical `d:"deny"` record, the tool is always `t:"none"`, and every rc outside {0,2} collapses to one token. Enough to alarm, not to diagnose.
  # Horizoned (harbor#211): one wrapper deny from days earlier was reported at crit for ten days under a repair that could not change it. Split by date, not filtered: inside the horizon a crit with the repair, outside a warn that NAMES THE DATE; both halves run the identical awk.
  # The repair routes before it prescribes: it names `harbor verify` as the check and the installer as conditional on what it says, because guard presence is floor-verify's and REF-1's question (header: the scope is the ledger). It prints the date the row goes quiet so the claim can be falsified by waiting.
  if [ "$N_WRAPDENY" -gt 0 ]; then
    _fc2_rows() { # <jq-date-predicate> <severity> <suffix> <repair-suffix> [as-of-date] [demote-date]
      jq -r --arg c "$FC_CUTOFF" --arg i "$FC_INSTALL_DATE" "select(.g==\"wrapper\" and .d==\"deny\")|select($1)|.r" "$REC" 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk -v sev="$2" -v sfx="$3" -v rsfx="$4" -v when="${5:-}" -v clears="${6:-}" '{ n=$1; r=$2
                 repair = "run `harbor verify` and read which guard fails to reach a verdict"
                 if (r ~ /no-jq/)         repair = "install jq — without it every floor_field returns empty and a guard sees an empty command"
                 if (r ~ /guard-missing/) repair = "run `harbor verify` first — admission-install.sh only helps if that reports a guard absent or unwired, and a green floor means this record is spent"
                 if (r ~ /no-grep/)       repair = "grep is unresolvable from the hook environment: check PATH and /usr/bin/grep"
                 if (r ~ /no-verdict/)    repair = "the guard exited outside {0,2}: run it by hand against a payload and read stderr"
                 if (when != "") {
                   repair = "recorded " when ", not now: " repair
                   if (clears != "") repair = repair "; clears " clears " if nothing new lands"
                 }
                 printf "FC-2\t%s\t%s (x%d)%s\tthe floor could not EVALUATE a tool call: on fail-closed wiring it denied one with no rule behind it, and on the advisory wiring it recorded this and let the call through — the record is identical either way, and carries neither the tool nor the exit code\t%s%s\n", sev, r, n, sfx, repair, rsfx }'
    }
    _fc2_last="$(jq -r 'select(.g=="wrapper" and .d=="deny")|.ts[0:10]' "$REC" 2>/dev/null | sort | awk 'END{print $0}')"
    # The day the row goes quiet, computed so the reader can check it: a record dated D leaves the crit half on D + horizon + 1. Same BSD -v / GNU -d idiom as FC_CUTOFF; empty when neither resolves, and the clause is then not printed.
    _fc2_clears=""
    case "$_fc2_last" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        _fc2_clears="$(date -u -j -v+"$((FC_HORIZON + 1))"d -f '%Y-%m-%d' "$_fc2_last" +%F 2>/dev/null \
                    || date -u -d "$_fc2_last + $((FC_HORIZON + 1)) days" +%F 2>/dev/null \
                    || true)"
        case "$_fc2_clears" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
          *) _fc2_clears="" ;;
        esac ;;
    esac
    # The crit half carries both dates; the warn half carries neither (its suffixes already name the date, and a past demote date would read as a promise about nothing).
    # Three buckets, disjoint and exhaustive: crit only while BOTH inside the horizon AND not superseded by an install (supersession is the stronger statement). With both marks empty the crit arm takes everything: fail toward crit.
    # Only the classes whose artefact an install replaces are superseded: guard-missing and no-verdict are about the guard FILE, which floor-install overwrites. A reinstall cannot restore a missing jq or grep, and superseding those would quiet an interpreter outage that only SessionStart's crit channel surfaces.
    _fc2_replaced='(.r|startswith("wrapper-guard-missing") or startswith("wrapper-no-verdict"))'
    { _fc2_rows "(\$c==\"\" or .ts[0:10] >= \$c) and (\$i==\"\" or .ts[0:10] >= \$i or ($_fc2_replaced|not))" crit '' '' "$_fc2_last" "$_fc2_clears"
      # SUPERSEDED: names the install rather than the calendar, because that is what the reader can act on.
      _fc2_rows "\$i!=\"\" and .ts[0:10] < \$i and $_fc2_replaced" info \
        ", last on $_fc2_last — before the floor was reinstalled" \
        " — and the guard file this names was REPLACED by the floor-install of ${FC_INSTALL_DATE}, so it no longer exists in the state this record describes: history unless it recurs"
      # The old half exists only when a horizon resolved (with $FC_CUTOFF empty the first call took every record) and excludes what the supersession arm took.
      [ -n "$FC_CUTOFF" ] && _fc2_rows ".ts[0:10] < \$c and (\$i==\"\" or .ts[0:10] >= \$i or ($_fc2_replaced|not))" warn \
        ", last on $_fc2_last — outside the ${FC_HORIZON}d window" \
        " — but nothing has been recorded since $_fc2_last, so verify before acting: this is history unless it recurs"
    } > "$TMPD/fc2" 2>/dev/null || :
    while IFS='	' read -r r s j w p; do [ -n "${r:-}" ] && finding "$r" "$s" "$j" "$w" "$p"; done < "$TMPD/fc2"
  fi

  # ── FC-6 · the recurrence counter is dead ──────────────────────────────────
  # Ordered before FC-5 because it decides whether FC-5 can be believed: `h="-"` means blocks are counted but no longer correlated (salt absent or malformed, or no hasher; see floor_obs_digest).
  if [ "$N_BLOCK" -gt 0 ] && [ "$N_DEADDG" -gt 0 ]; then
    _sev=warn; [ "$N_DEADDG" -eq "$N_BLOCK" ] && _sev=crit
    finding FC-6 "$_sev" "dead digests ($N_DEADDG of $N_BLOCK blocks)" \
      "these blocks carry no digest, so FC-5 and observe-report --fp cannot tell them apart and both under-report recurrence without saying so" \
      "check that the per-install salt holds 32 hex characters and that a sha256 binary resolves at one of the absolute paths floor_obs_digest pins"
  fi

  # awk, not grep: a negative must never rest on a grep this script does not control (on this Mac `grep` is ugrep with -I --ignore-files, and a skipped line DROPS a finding).
  # One finding per RULE, not per digest: ungrouped, the first live run printed eight FC-5 rows for four things to look at, and six commands walled by one rule is evidence about the rule.
  # `FILENAME==pf`, never `NR==FNR`: with no probe digests the first file is empty and NR==FNR then holds for the first record of the second file, silently consuming the loudest finding.
  # Two passes: filter with the probe digests alone, and only if a row survives derive the suite digests (see _derive_suite) and re-run the same filter, so the two passes cannot disagree.
  _fc5_filter() { # <exclusion-file>
    awk -v pf="$1" 'FILENAME==pf{p[$1]=1;next} { n=$1; d=$2; r=$3; if (!(d in p) && n+0>=3) printf "%s\t%d\t%s\n", r, n, d }' \
        "$1" "$TMPD/recur"
  }
  _fc5_filter "$TMPD/excl" > "$TMPD/fc5cand" 2>/dev/null || :
  if [ -s "$TMPD/fc5cand" ]; then
    _derive_suite
    _fc5_filter "$TMPD/excl" > "$TMPD/fc5cand" 2>/dev/null || :
  fi
  # The suite caveat is added HERE, not in the block above: the derivation is lazy, so SUITE_OK is still 0 on a healthy box at caveat-building time. Said only when there is a finding to attach it to.
  if [ "$PROBES" = 0 ] && [ "$SUITE_TRIED" = 1 ] && [ "$SUITE_OK" = 0 ]; then
    _caveat="$_caveat (NOTE: the floor suite (tests/admission/baseline/) could not be read beside this script, so the SUITE's own payloads — which fire the real guards and land in this ledger exactly as an operator's commands do — are still counted in the rows below)"
  fi
  cat "$TMPD/fc5cand" \
    | sort -k1,1 -k2,2nr \
    | awk -F'\t' '{ c[$1]++; if ($2+0 > worst[$1]) worst[$1]=$2+0
                    if (c[$1] <= 3) top[$1] = (top[$1] == "" ? $3 "(x" $2 ")" : top[$1] " " $3 "(x" $2 ")") }
                  END { for (r in c) printf "%s\t%d\t%d\t%s\n", r, c[r], worst[r], top[r] }' \
    | sort -t'	' -k3,3nr > "$TMPD/fc5"
  while IFS='	' read -r r ndist wmax tops; do
    [ -n "${r:-}" ] || continue
    _plural=""; _about=""
    # The count spans the whole retained ledger; only the most recent block must be inside the window. Say so.
    _recent=""
    [ -n "$FC_CUTOFF" ] && _recent=" — still recurring inside the ${FC_HORIZON}d window (the count itself spans the whole retained ledger)"
    if [ "$ndist" -gt 1 ]; then
      _plural="s"
      # The distinct-command count indicts the RULE: one command blocked four times can be one stubborn operator.
      _about=" — and $ndist DIFFERENT commands walled by one rule is evidence about the rule, not about any of them"
    fi
    finding FC-5 warn "$r · $ndist distinct command$_plural refused >=3x (worst x$wmax)" \
      "the same command reaching the same rule again is either the operator re-hitting a wall, which №2.11 makes a defect rather than safety, or a script retrying into the floor$_about$_recent$_caveat" \
      "reproduce from the digests [$tops] by re-running what you were doing, then fix the rule or the command — never widen a rule to silence a count"
  done < "$TMPD/fc5"
fi

# ── FC-9 · the ledger is sharded under more than one host key ────────────────
# One config dir is one install, so more than one host partition means the host key MOVED and the history is in fragments (harbor#119: `hostname -s` answered `Mac` offline and forked a ledger 21917 records against 54).
# This tool unions the partitions, so its own totals are right, which is why the fork has to be SAID: every other reader opens one directory and reports a fragment as the history.
if [ -d "$OBS" ]; then
  _nhost=0
  for _hd in "$OBS"/*; do [ -d "$_hd" ] && _nhost=$((_nhost + 1)); done
  if [ "$_nhost" -gt 1 ]; then
    _hlist=""
    for _hd in "$OBS"/*; do
      [ -d "$_hd" ] || continue
      _hn="$(basename "$_hd")"
      _hc="$(num "$(jq -r --arg h "$_hn" 'select(._host==$h)|1' "$REC" 2>/dev/null | awk 'END{print NR+0}')")"
      _hlist="$_hlist $_hn($_hc)"
    done
    # floor_host_token (harbor#119) is the one definition of the partition key; ask it rather than re-deriving. It splits the two states an operator acts on differently:
    #   ONGOING     newest record is in a NON-canonical partition: running code still writes the old key and readers lose data now. crit.
    #   HISTORICAL  newest record is canonical: the other partitions are orphaned history, to fold at leisure. warn.
    # Without the split the finding is permanent and unactionable once the fix lands (a standing warn gets muted, No.2.11).
    _canon=""
    [ "$GL_OK" = 1 ] && _canon="$(floor_host_token 2>/dev/null || printf '')"
    _newest_host="$(jq -rs 'max_by(.ts)._host // empty' "$REC" 2>/dev/null || printf '')"
    if [ -n "$_canon" ] && [ -n "$_newest_host" ] && [ "$_newest_host" != "$_canon" ]; then
      finding FC-9 crit "$_nhost host partitions, still writing under \`$_newest_host\` (canonical is \`$_canon\`):$_hlist" \
        "the newest record is NOT in the canonical partition, so the code writing this ledger still derives the old key — the fork is growing, and every reader that opens one directory is losing data now" \
        "deploy the stable-key fix (harbor#119) so writes resume under \`$_canon\`, then fold the orphaned partition(s); an installer is the operator's act, and until it runs the split widens every session"
    elif [ -n "$_canon" ]; then
      finding FC-9 warn "$_nhost host partitions, canonical is \`$_canon\`:$_hlist" \
        "writes are landing under the canonical key, so this is orphaned HISTORY rather than a growing fork — but the record is still in fragments, and every other reader of that tree opens ONE directory and reports a fragment as the whole record" \
        "fold the orphaned partition(s) under \`$_canon\`, or move them out of OBSERVABILITY/ — note the guard ledger's records are per-event and unique, unlike the work-log's, where harbor#119 measured all 38 as duplicates"
    else
      # floor_host_token unavailable: the count is still true, the attribution is not.
      finding FC-9 warn "$_nhost host partitions (canonical key UNKNOWN):$_hlist" \
        "one config dir is one install, so the host key moved and the history is in fragments — and the sibling library-admission.sh could not be read, so this cannot say which partition is the canonical one" \
        "run this from the repo so floor_host_token is reachable; the fix for the key itself is harbor#119, and a ledger copied in from another machine looks identical from here — the sink is machine-local by design"
    fi
  fi
fi

# ── FC-7 · the sink's own state ──────────────────────────────────────────────
# The writer's safety gates make it blind when they drift: floor_log_decision refuses to write unless the host directory is NON-writable (property 2; it is what makes a FIFO plant unwinnable) and returns 0 when it refuses, so the failure state is silence, which every reader renders as health.
if [ -d "$OBS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    _host="$(basename "$_hd")"
    if [ -w "$_hd" ]; then
      finding FC-7 crit "$_host/ is writable" \
        "floor_log_decision refuses to write while the host directory is writable, so every guard decision from now on is dropped and no reader can tell that from a quiet day" \
        "restore the mode from your own terminal (0500 on the host directory); admission-observe.sh re-applies it at the next SessionStart"
    fi
    _sink="$_hd/guard-decisions.jsonl"
    if [ -e "$_sink" ] && { [ ! -f "$_sink" ] || [ -L "$_sink" ]; }; then
      finding FC-7 crit "$_host/guard-decisions.jsonl is not a regular file" \
        "the hot path type-checks the sink and refuses a symlink or a FIFO, so the ledger is permanently empty — and admission-observe.sh refuses to reuse it rather than overwrite whatever it points at" \
        "inspect what the path IS before removing anything: a FIFO or symlink here was planted, and its target may be a file you care about"
    fi
    if [ -f "$_sink" ] && [ ! -L "$_sink" ]; then
      _sz="$(num "$(wc -c < "$_sink" 2>/dev/null | tr -d ' ')")"
      # admission-observe.sh ROTATE_BYTES rotates above 5 MiB and is the only rotator; a sink well past that means its SessionStart hook is not reaching rotation. The headroom keeps a mid-session overshoot out of the report.
      if [ "$_sz" -gt 6291456 ]; then
        finding FC-7 warn "$_host/guard-decisions.jsonl is $((_sz / 1048576)) MiB" \
          "it is past the rotation threshold, and admission-observe.sh is the only thing that rotates it, so that hook is not reaching its rotation line" \
          "confirm admission-observe.sh runs to completion at SessionStart; do not rotate by hand from a session — the sink is a surface guard-selfedit protects"
      fi
    fi
  done
fi

# ── FC-10 · a tool failure that keeps coming back (harbor#465) ──────────────
# The threshold is the whole rule: the same failure in three separate sessions is ONE finding naming the tool and input, and a failure that happens once raises nothing (a ledger that reports every transient gets muted, No.2.11).
#   >= 3 RECORDS   the first count at which "it happened again" is a pattern.
#   >= 2 SESSIONS  does the work: three failures inside one session is a retry loop the operator is already handling; the same failure in a second session means the first fix did not happen or hold (harbor#462 survived 34 days this way).
# `blocked` is excluded: a floor block is already a guard-decisions record, and counting it here would double-report the floor doing its job.
# `handoff` likewise: browser-agent refusing by its own rules and naming the operator's next step.
if [ "$NTF" -gt 0 ]; then
  # Horizoned on last occurrence like FC-2 to FC-5: the ledger is bounded by bytes, not days, so a failure last seen weeks ago was reported as current.
  jq -s -r --arg c "$FC_CUTOFF" '
      map(select(.e != "blocked" and .e != "handoff" and (.h // "-") != "-"))
    | group_by(.h)
    # Label from the NEWEST record: the oldest one of a long-lived group can predate a recorder fix (bare `mcp` before #1381).
    | map((sort_by(.ts // "") | .[-1]) as $n | { t: $n.t, k: $n.k, e: $n.e,
            n: length, s: (map(.s) | unique | length), last: (map(.ts // "" | .[0:10]) | max) })
    | map(select(.n >= 3 and .s >= 2))
    | map(select($c == "" or .last >= $c))
    | sort_by(-.n)[]
    | [.t, .k, .e, (.n|tostring), (.s|tostring)] | @tsv' \
    "$TFREC" 2>/dev/null > "$TMPD/fc10" || : > "$TMPD/fc10"
  while IFS='	' read -r _ft _fk _fe _fn _fs; do
    [ -n "${_ft:-}" ] || continue
    # A dead pointer that now resolves is repaired: the ledger keeps the "not found" records for its whole retention, so a created target stayed crit for days. Only a path key (~/ or /) can be probed; other keys stay reported. If the path vanishes again the finding returns.
    if [ "$_fe" = "not-found" ]; then
      case "$_fk" in "~/"*) _fp="$HOME/${_fk#"~/"}" ;; /*) _fp="$_fk" ;; *) _fp="" ;; esac
      [ -z "$_fp" ] || [ ! -e "$_fp" ] || continue
    fi
    # `not-found` across 3+ sessions is harbor#462's shape and the one class whose repair is a one-line edit; everything else is warn, since a non-zero exit may be how the operator works.
    _sev=warn
    [ "$_fe" = "not-found" ] && [ "$_fs" -ge 3 ] && _sev=crit
    _fr="if the subject is a path, resolve or delete the pointer to it; the ledger is at MEMORY/OBSERVABILITY/<host>/tool-failures.jsonl and this tool repairs nothing"
    _fsub="$_ft → $_fk"
    case "$_ft" in
      mcp__*) # an MCP server: no path to resolve, and the ledger keeps no tool name, so the remedy is to look at the server
        _fsub="MCP server ${_ft#mcp__}"; [ "$_fk" = - ] || _fsub="$_fsub → $_fk"
        _fr="check that MCP server's own state (is it attached and healthy?) and the first error of the failing call; the ledger keeps the server only, not the tool, and this tool repairs nothing" ;;
    esac
    finding FC-10 "$_sev" "$_fsub" \
      "failed $_fn time(s) across $_fs session(s) with the same input, error class '$_fe' — each session found it independently and none of them left a record the next one could read" \
      "$_fr"
  done < "$TMPD/fc10"
fi

# ── FC-11 · the recorder is wired and has nowhere to write ──────────────────
# FC-0's shape for the second ledger. The predicate is NOT "the ledger is empty" (a box with no failed tool calls is healthy) but "the hook is wired and the SINK DOES NOT EXIST": admission-observe.sh never prepared it, so failures are being dropped.
# Warn, not crit: an installed-but-not-restarted box legitimately has no sink until the next SessionStart, and a crit that clears by waiting teaches the reader to wait.
if [ "$TF_WIRED" = yes ] && [ -d "$OBS" ]; then
  _tf_sinks="$(find "$OBS" -type f -name 'tool-failures.jsonl' 2>/dev/null | awk 'END{print NR+0}')"
  _tf_hosts="$(find "$OBS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | awk 'END{print NR+0}')"
  if [ "$_tf_hosts" -gt 0 ] && [ "$_tf_sinks" -eq 0 ]; then
    finding FC-11 warn "$OBS/tool-failures.jsonl" \
      "failure-observe.sh is wired at PostToolUseFailure and no sink exists in any host partition, so every failed tool call is being dropped — and this ledger's other rules would report clean, because a ledger that was never written looks exactly like a box that never failed" \
      "admission-observe.sh is the only component allowed to create it, at SessionStart: confirm it is wired, start a session, re-run. If it was only just installed, one restart is the whole fix — and if the floor was UNINSTALLED here on purpose, admission-observe.sh went with it, so unwire failure-observe.sh from PostToolUseFailure rather than leaving a recorder that can never record"
  fi
fi

# ── report ───────────────────────────────────────────────────────────────────
NFIND="$(printf '%s' "$FINDINGS" | awk 'NF{n++} END{print n+0}')"
# info rows are history: reported, never counted toward the exit status or the clean verdict.
NACT="$(printf '%s' "$FINDINGS" | awk -F'\t' 'NF && $2!="info"{n++} END{print n+0}')"
: "${PROBE_OK:=0}"
# Same reason: the per-host loop sets both, and a box with no host partition never enters it.
: "${SUITE_OK:=0}"

if [ "$JSON" = 1 ]; then
  # One dataset, two renderers: a second pass for JSON could disagree with the report. `worst` uses alert-probe.sh's vocabulary.
  printf '%s' "$FINDINGS" | jq -R -s \
    --arg dir "$DIR" --arg worst "$WORST" --argjson records "$NREC" \
    --argjson toolfails "$NTF" \
    --argjson probes "$PROBE_OK" --argjson suite "$SUITE_OK" '
    { dir: $dir, installed: true, records: $records, tool_failures: $toolfails,
      worst: $worst,
      probe_traffic_excluded: ($probes == 1),
      suite_traffic_excluded: ($suite == 1),
      findings: [ split("\n")[] | select(length > 0) | split("\t")
                  | {rule: .[0], severity: .[1], subject: .[2], breaks: .[3], repair: .[4]} ] }
    | . + {clean: (([.findings[] | select(.severity != "info")] | length) == 0)}'
elif [ "$_LOGLIB" = 0 ]; then
  # A copy with no library-log.sh beside it says so rather than printing half a report. --json needs none.
  printf 'failure-capture: library-log.sh is missing beside %s, so this copy cannot print its report; --json still works\n' "${SELF:-?}" >&2
else
  log_head "$OBS"
  # Both denominators, always (harbor#467): one ledger reading zero is a different fact from the other reading zero.
  log_note "$NREC guard decision(s) · $NTF tool failure(s) read · worst: $WORST"
  if [ "$NFIND" -eq 0 ]; then
    # Both ledgers, or the sentence is false: this once printed "no ledger to judge" over five tool-failure records (harbor#467 reappearing).
    if [ "$NREC" -eq 0 ] && [ "$NTF" -eq 0 ] && [ "$FLOOR_WIRED" = no ]; then
      log_skip "no floor is wired here and no tool failure is recorded, so there is nothing to judge"
    else
      log_ok "nothing in either ledger says the floor or a tool is failing"
      [ "$PROBE_OK" = 1 ] || log_note "the verifier's own probe shapes were NOT separated from the recurrence count"
    fi
  else
    # One line per finding (crit FAIL, warn and unknown WARN; the repair is its fix line), read from a file not a pipe so log_end's counters survive the loop.
    printf '%s' "$FINDINGS" > "$TMPD/report"
    while IFS='	' read -r r s j w p; do
      [ -n "${r:-}" ] || continue
      case "$s" in
        crit) log_fail "$r $j — $w"; log_fix "$p" ;;
        warn) log_warn "$r $j — $w"; log_fix "$p" ;;
        info) log_note "$r [info] $j — $w" ;;
        *)    log_warn "$r [$s] $j — $w"; log_fix "$p" ;;
      esac
    done < "$TMPD/report"
    log_note "$NFIND finding(s). NOTHING here is repaired by this tool: every surface it names is one admission-self-edit.sh protects, so a version that could fix them would be a version that can disable the floor. Each fix line is for a human at their own terminal."
  fi
  log_end || :
fi

[ "$NACT" -eq 0 ] || exit 1
exit 0
