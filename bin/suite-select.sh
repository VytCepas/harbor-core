#!/usr/bin/env sh
# suite-select.sh — which suites must a changeset run? (CI-2, harbor#150)
#
#   sh suite-select.sh <suite>        exit 0 = must run, 1 = may stand down
#   sh suite-select.sh --list         every manifest suite, its verdict, its reason
#   sh suite-select.sh --changed      print the changeset being judged
#   sh suite-select.sh --why-all      exit 0 saying why when every suite runs, else exit 1 (harbor#1288)
#   sh suite-select.sh --run <suite>  decide, then run it if selected (the CI entry)
#   sh suite-select.sh --sum <ran>:<count>...  one CI job's suite counts, summed
#
#   A failed --run ends with `log: <path>`, the file that keeps the suite's output (harbor#774).
#
#   HARBOR_CHANGED   newline-separated changed paths; overrides the git diff
#   HARBOR_BASE      base ref for the diff (default: origin/main)
#   HARBOR_CI_HEAD   head ref for the diff (default: HEAD)
#
# WHAT THIS IS FOR. No path filters anywhere in governance.yml and one serialised
# self-hosted runner: a SKILL.md typo has always cost what a guard rewrite costs. The
# declarations live in CONTRACTS/suite-paths.txt and the reasoning lives there
# too; this file is only the decision procedure.
#
# THE ONE THING THAT MATTERS. Every uncertainty resolves to RUN EVERYTHING. An
# unreadable declaration file, an undeterminable changeset, a changed path no
# declaration mentions, a suite with no declaration, a changeset that touches the
# selector's own inputs — all of them select every suite. The saving is real but
# it is never the fallback, because the failure this design has to prevent is a
# floor change quietly taking the cheap lane, and that failure is SILENT: the run
# comes back green and shorter, which reads as an improvement.
#
# NOT A GATE, AND DELIBERATELY SO. `--run` stands a suite down from INSIDE its
# job, so the job still reports a real verdict to the branch-protection rule. The
# alternative — a job-level `if:` — reports the check as `skipped`, and this repo
# has already argued that case down once, in the comment above the `status` job:
# a skipped required check does not block a merge, so the gate reads as satisfied
# because it never ran. Standing down inside the job costs a checkout and buys
# not depending on that semantics at all.
#
# `-f` IS LOAD-BEARING, not tidiness. Globs reach `_matches` as an UNQUOTED
# variable so that they field-split into separate patterns — and in `sh` an
# unquoted expansion in argument position is split AND pathname-expanded. Without
# noglob, `skills/*` expanded against the working directory into the real
# `skills/<name> skills/…` before `case` ever saw it, so `skills/<name>/SKILL.md` came
# back UNCLASSIFIED and every suite ran. Measured 2026-08-06 on the first run of
# this file: the "everything runs" fallback hid the defect behind a correct-
# looking verdict, which is precisely why the fallback direction is the safe one.
# `case` patterns are unaffected by `-f`; nothing here relies on expansion.
set -euf

ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
DECL="$ROOT/CONTRACTS/suite-paths.txt"
MAN="$ROOT/CONTRACTS/suites.txt"
BASE="${HARBOR_BASE:-origin/main}"

case "${1:-}" in
  -h|--help|'') sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
# Its own failures are log-lib lines (CONTRACTS/logging.md); a usage error stays a plain exit 2.
# Beside this file, never under $ROOT: HARBOR_ROOT may name a tree with no bin/ of its own.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
log_init suite-select

_output() { # publish a step output when running under Actions
  [ -n "${GITHUB_OUTPUT:-}" ] || return 0
  printf '%s\n' "$1" >> "$GITHUB_OUTPUT"
}

# --sum (harbor#727) replaces --shard: each floor part is its own `--run` step, and
# a job sums its steps' `ran:count` outputs here. All must agree on ran; a ran part
# with no count is refused, never summed as 0 (status-gen would then pass on it).
if [ "${1:-}" = "--sum" ]; then
  shift
  [ $# -gt 0 ] || { echo "suite-select: --sum needs at least one <ran>:<count>" >&2; exit 2; }
  _ran=""; _tot=0; _terms=""
  for _pc in "$@"; do
    _r="${_pc%%:*}"; _c="${_pc#*:}"
    case "$_pc:$_r" in
      *:*:true|*:*:false) ;;
      *) printf 'suite-select: --sum wants <ran>:<count>, got %s\n' "$_pc" >&2; exit 2 ;;
    esac
    if [ -n "$_ran" ] && [ "$_ran" != "$_r" ]; then
      LOG_FD=2; log_fail "--sum: the suites disagree on whether they ran: $*"
      log_nofix "harbor#727 — the --run steps one job sums are selected together"; log_end; exit 1
    fi
    _ran="$_r"
    [ "$_r" = true ] || continue
    case "$_c" in ''|*[!0-9]*)
      LOG_FD=2; log_fail "--sum: a suite that ran published no count: $_pc"
      log_nofix "harbor#727 — a suite that ran ends with its '<name>: N passed, M failed' line"; log_end; exit 1 ;;
    esac
    _tot=$((_tot + _c)); _terms="$_terms${_terms:+ + }$_c"
  done
  _output "ran=$_ran"
  if [ "$_ran" = true ]; then
    _output "count=$_tot"
    printf 'summed %s suite count(s): %s = %s\n' "$#" "$_terms" "$_tot"
  else
    printf 'every suite stood down; no count to sum\n'
  fi
  exit 0
fi

# The selector must not judge its own change. A changeset touching the
# declarations, this script, its suite, the linter that enforces the format, or
# the workflow runs everything — otherwise the first thing a broken selector can
# do is exempt the change that broke it. bin/suite-run.sh and its quick list decide
# what CI runs and where, so they are the selector's inputs too, as are the lists the
# workflow reads its required groups and dash suites from (harbor#961).
#
# `.github/workflows/*`, not `.github/*` (harbor#150): .github/CODEOWNERS decides who reviews,
# never what runs, and a lane that adds a protected file regenerates it (21 of the last 60 merged
# PRs, to 2026-10-13). It is declared like any path now (classify.test.sh checks it is current);
# anything else that lands under .github/ is unclassified, so it still runs everything.
SELF='CONTRACTS/suite-paths.txt CONTRACTS/suites.txt bin/suite-select.sh
tests/ci/suite-select-test.sh bin/lint-conventions.sh .github/workflows/* .github/actions/*
bin/suite-run.sh bin/suite-cache.sh CONTRACTS/suites-quick.txt
CONTRACTS/suites-tally.txt CONTRACTS/suites-dash.txt'

# THE ONE EXCEPTION TO SELF: ROWS APPENDED, NOTHING ELSE (harbor#150). Every lane that adds a
# suite appends one row to each of these two files, and that alone used to run all of them. A row
# whose KEY IS NEW cannot change any other suite's verdict: lookup is by key, the first row for a
# key wins, and an appended key has no earlier row. So when the diff from the merge base removes
# or edits no line in them, and every row it adds names a key the base did not have:
#   - the appended suites run, and so do APPEND_SUITES (the selector's own suites);
#   - the two files are judged as ordinary changed paths (their readers declare them);
#   - an appended row may classify a path this changeset ADDS, never one that already existed:
#     a change must not be able to classify its own previously unclassified file.
# AND A ROW THAT ONLY GROWS (harbor#1149). In suite-paths.txt, a row edited in place whose globs keep every
# word they had and add more can only select its suite MORE often; nothing else reads it. That suite runs,
# and so do APPEND_SUITES; for a path this changeset does not add, the row classifies with its BASE globs,
# so a grown row cannot classify its own previously unclassified file either. Never for an `@` key (a
# grown @no-suite would hide paths), a row that is or becomes `always`, or a key the base lists twice.
# Anything else — a removed or edited line, a reused key, a git that cannot show the diff, a
# changeset that names the file while git sees no change in it — is SELF again: everything runs.
APPENDABLE='CONTRACTS/suites.txt CONTRACTS/suite-paths.txt'
APPEND_SUITES='tests/ci/suite-select-test.sh tests/ci/suite-run-test.sh tests/checks/lint.suites-test.sh'
HEADREF="${HARBOR_CI_HEAD:-HEAD}"

_lines() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || :; }

# The globs declared for one key, or empty. Comment and blank lines can never
# collide with a key: `#` is not a suite name and an empty $1 matches nothing.
_globs() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$DECL" 2>/dev/null || :; }

# The manifest is the authority on which suites EXIST; suite-paths.txt only says
# what selects them. Reading the list from the declarations instead would let a
# suite drop out of CI by being deleted from the file that is supposed to be
# checked against it (C5 enforces both directions for the same reason).
_manifest() { _lines "$MAN"; }

_matches() { # <path> <glob>...
  _p="$1"; shift
  for _g in "$@"; do
    # UNQUOTED ON PURPOSE — a `case` pattern, not a word. Note that `*` crosses
    # `/` here, unlike the same string used as a shell glob, so `bin/*` is
    # everything under bin/ at any depth.
    case "$_p" in $_g) return 0 ;; esac
  done
  return 1
}

# ── the changeset ───────────────────────────────────────────────────────────
# `A...B` (three dots) diffs from the merge base, which is what makes this the
# PR's own changes rather than everything main has learned since. It needs
# `origin/main` to be present, so a shallow checkout produces NO changeset — and
# that resolves to running everything rather than to running nothing. --no-renames: a moved file
# lists BOTH paths, so the old path still selects its declarers (a rename shows only the new one).
CHANGED=""
if [ -n "${HARBOR_CHANGED+x}" ]; then
  CHANGED="$HARBOR_CHANGED"
else
  if CHANGED="$(git -C "$ROOT" diff --name-only --no-renames "$BASE...$HEADREF" 2>/dev/null)"; then
    # Uncommitted work counts when judging the local HEAD: before the first commit the committed diff is empty, and
    # empty selects EVERY suite (399 for a 13-file change, 2026-10-27). Only once the base resolved, so an
    # unreachable base still runs everything.
    if [ "$HEADREF" = HEAD ]; then
      _wt="$( { git -C "$ROOT" diff --name-only --no-renames HEAD && git -C "$ROOT" ls-files --others --exclude-standard; } 2>/dev/null)" || _wt=""
      CHANGED="$(printf '%s\n%s\n' "$CHANGED" "$_wt" | awk 'NF && !s[$0]++')"
    fi
  else
    CHANGED=""
  fi
fi

# <file> → `A<TAB>key` per row the diff from the merge base ADDS to it and `G<TAB>key<TAB>base globs` per
# row it only GROWS (suite-paths.txt only); exit 1 when the diff removes or edits any other line, re-adds a
# key the base had, or cannot be read. `-U0` with no context: after the first `@@`, every `-` line is a removal.
_appended() {
  _mb="$(git -C "$ROOT" merge-base "$BASE" "$HEADREF" 2>/dev/null)" || return 1
  [ -n "$_mb" ] || return 1
  _bf="$(git -C "$ROOT" show "$_mb:$1" 2>/dev/null)" || return 1
  _df="$(git -C "$ROOT" diff --no-color --no-ext-diff --no-renames -U0 "$_mb" "$HEADREF" -- "$1" 2>/dev/null)" || return 1
  # ENVIRON, not -v: -v would interpret a backslash in a glob as an escape.
  _grow=0; [ "$1" != CONTRACTS/suite-paths.txt ] || _grow=1
  printf '%s\n' "$_df" | _B="$_bf" _G="$_grow" awk '
    function key(s) { sub(/^[[:space:]]+/, "", s); split(s, f, /[[:space:]]+/); return f[1] }
    function rest(s) { sub(/^[[:space:]]+/, "", s); sub(/^[^[:space:]]+[[:space:]]*/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function words(s, w,   n, a, i) { delete w; n = split(s, a, /[[:space:]]+/); for (i = 1; i <= n; i++) if (a[i] != "") w[a[i]] = 1 }
    BEGIN { n = split(ENVIRON["_B"], b, "\n")
            for (i = 1; i <= n; i++) if (b[i] !~ /^[[:space:]]*(#|$)/) { k = key(b[i]); had[k]++ } }
    /^@@/ { hunk = 1; next }
    !hunk { next }
    /^\\/ { bad = 1; exit }
    /^-/ { r = substr($0, 2); k = key(r)
           if (ENVIRON["_G"] != 1 || r ~ /^[[:space:]]*(#|$)/ || k ~ /^@/ || had[k] != 1 || (k in gone)) { bad = 1; exit }
           gone[k] = rest(r); next }
    /^\+/ { r = substr($0, 2); if (r ~ /^[[:space:]]*(#|$)/) next
            k = key(r); if (k in seen) { bad = 1; exit }
            seen[k] = 1
            if (k in gone) { grew[k] = rest(r); next }
            if (k in had) { bad = 1; exit }
            print "A\t" k; next }
    END { if (bad || !hunk) exit 1
          for (k in gone) {
            if (!(k in grew)) exit 1
            o = gone[k]; nw = grew[k]
            if ((" " o " ") ~ / always / || (" " nw " ") ~ / always /) exit 1
            words(nw, NW); words(o, OW)
            for (x in OW) if (!(x in NW)) exit 1
            print "G\t" k "\t" o }
          exit 0 }'
}

# ALL_WHY non-empty means every suite runs, and says why in one line.
ALL_WHY=""
if [ -z "$CHANGED" ]; then
  # Empty is ambiguous — an unreachable base looks exactly like a no-op commit,
  # and on a push to `main` it is the normal case. Both want everything.
  ALL_WHY="changeset is empty or undeterminable (base: $BASE)"
elif [ ! -r "$DECL" ]; then
  ALL_WHY="no readable declarations at CONTRACTS/suite-paths.txt"
fi

# APPENDED: the keys appended to an APPENDABLE file (one per line); APPEND_ON=1 when the changeset
# touches one. ADDED: the paths this changeset creates, which appended rows may classify.
APPENDED=""; APPEND_ON=0; ADDED=""; GROWN=""   # GROWN: `key<TAB>base globs` per row that only grew
if [ -z "$ALL_WHY" ]; then
  # shellcheck disable=SC2086
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _matches "$_p" $SELF || continue
    if ! _matches "$_p" $APPENDABLE; then
      ALL_WHY="changeset touches the selector's own inputs ($_p)"; break
    fi
    if ! _k="$(_appended "$_p")"; then
      ALL_WHY="changeset touches the selector's own inputs ($_p: a line removed or edited, a key reused, or no diff git can show against $BASE)"
      break
    fi
    APPEND_ON=1
    _ka="$(printf '%s\n' "$_k" | awk -F'\t' '$1 == "A" { print $2 }')"
    _kg="$(printf '%s\n' "$_k" | awk -F'\t' '$1 == "G" { print $2 "\t" $3 }')"
    APPENDED="$APPENDED${_ka:+$_ka
}"; GROWN="$GROWN${_kg:+$_kg
}"
  done <<CHANGES
$CHANGED
CHANGES
fi
if [ -z "$ALL_WHY" ] && { [ -n "$APPENDED" ] || [ -n "$GROWN" ]; }; then
  ADDED="$(git -C "$ROOT" diff --name-only --no-renames --diff-filter=A "$BASE...$HEADREF" 2>/dev/null)" \
    || ALL_WHY="rows were appended to the selector's inputs and git cannot list the paths this changeset adds"
  # New files not yet committed are added paths too (see the changeset above).
  [ -n "$ALL_WHY" ] || [ "$HEADREF" != HEAD ] || [ -n "${HARBOR_CHANGED+x}" ] \
    || ADDED="$ADDED${ADDED:+
}$( { git -C "$ROOT" diff --name-only --no-renames --diff-filter=A HEAD; git -C "$ROOT" ls-files --others --exclude-standard; } 2>/dev/null)"
fi
NL='
'
_in() { case "$NL$2$NL" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }  # <line> <lines>: quoted, so literal
_grown_base() { printf '%s\n' "$GROWN" | awk -F'\t' -v k="$1" '$1 == k { print $2; f = 1; exit } END { exit !f }'; }  # <key> → its base globs

if [ -z "$ALL_WHY" ]; then
  _nosuite="$(_globs '@no-suite')"
  # shellcheck disable=SC2086
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _matches "$_p" $APPENDABLE && continue  # judged above, and matched as a path in decide()
    _new=0; { [ -z "$APPENDED" ] && [ -z "$GROWN" ]; } || ! _in "$_p" "$ADDED" || _new=1
    _seen=0
    _matches "$_p" $_nosuite && _seen=1
    if [ "$_seen" -eq 0 ]; then
      while IFS= read -r _s; do
        [ -n "$_s" ] || continue
        # An appended row classifies only a path this changeset adds (see APPENDABLE above).
        [ "$_new" -eq 1 ] || [ -z "$APPENDED" ] || ! _in "$_s" "$APPENDED" || continue
        # A grown row classifies a path this changeset did not add with its base globs (see APPENDABLE above).
        if [ "$_new" -eq 0 ] && [ -n "$GROWN" ] && _gb="$(_grown_base "$_s")"; then _g="$_gb"; else _g="$(_globs "$_s")"; fi
        [ -n "$_g" ] || continue
        # shellcheck disable=SC2086
        if _matches "$_p" $_g; then _seen=1; break; fi
      done <<MANIFEST
$(_manifest)
MANIFEST
    fi
    if [ "$_seen" -eq 0 ]; then
      ALL_WHY="no declaration mentions $_p — an unclassified path runs everything"
      break
    fi
  done <<CHANGES
$CHANGED
CHANGES
fi

# ── the decision ────────────────────────────────────────────────────────────
# Sets REASON. 0 = run, 1 = stand down.
REASON=""
decide() {
  if [ -n "$ALL_WHY" ]; then REASON="$ALL_WHY"; return 0; fi
  if _in "$1" "$APPENDED"; then REASON="appended to the selector's inputs by this changeset"; return 0; fi
  if [ -n "$GROWN" ] && _grown_base "$1" >/dev/null; then REASON="its declaration only grew in this changeset"; return 0; fi
  # shellcheck disable=SC2086
  if [ "$APPEND_ON" -eq 1 ] && _matches "$1" $APPEND_SUITES; then
    REASON="the selector's own suite: this changeset appends to its inputs"; return 0
  fi
  _d="$(_globs "$1")"
  if [ -z "$_d" ]; then
    REASON="no declaration in CONTRACTS/suite-paths.txt — undeclared means always"
    return 0
  fi
  if [ "$_d" = "always" ]; then REASON="declared always"; return 0; fi
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    # shellcheck disable=SC2086
    if _matches "$_p" $_d; then REASON="$_p matches its declaration"; return 0; fi
  done <<CHANGES
$CHANGED
CHANGES
  REASON="no changed path matches [$_d]"
  return 1
}

# harbor#774: a red --run names the file that keeps its suite's output, as its last line.
_kept() { log_end || :; printf 'log: %s\n' "$_out"; }

_summary() { # append to the CI job summary when there is one to append to
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"
}

case "$1" in
  --changed)
    printf '%s\n' "$CHANGED"
    ;;

  --why-all) # bin/suite-cache.sh asks: a run that selects everything is never served from a cache
    [ -n "$ALL_WHY" ] || exit 1
    printf '%s\n' "$ALL_WHY"
    ;;

  --list)
    while IFS= read -r _s; do
      [ -n "$_s" ] || continue
      if decide "$_s"; then printf 'RUN   %-26s %s\n' "$_s" "$REASON"
      else                  printf 'SKIP  %-26s %s\n' "$_s" "$REASON"; fi
    done <<MANIFEST
$(_manifest)
MANIFEST
    ;;

  --run)
    [ $# -ge 2 ] || { echo "suite-select: --run needs a suite name" >&2; exit 2; }
    _s="$2"
    # A MANIFEST ENTRY MAY BE A REPO PATH (harbor#695). A bare name is a suite in
    # bin/; anything with a slash is relative to the repo root, which is how a
    # skill's own suite reaches CI without moving out of its skill.
    case "$_s" in */*) _sp="$ROOT/$_s" ;; *) _sp="$ROOT/bin/$_s" ;; esac
    [ -f "$_sp" ] || { printf 'suite-select: no such suite: %s\n' "${_sp#$ROOT/}" >&2; exit 2; }
    # --shard K/N is retired (harbor#727): the floor's parts are separate suites, so
    # a leftover `--shard` must fail here, not run the whole of something.
    [ $# -eq 2 ] || { printf 'suite-select: --run takes one suite; --shard was retired in harbor#727 (each floor part is its own --run)\n' >&2; exit 2; }
    # The count label and the count-bearing test key on the suite's own name.
    _b="${_s##*/}"
    if ! decide "$_s"; then
      printf 'STOOD DOWN  %s\n  reason: %s\n' "$_s" "$REASON"
      printf '  changeset:\n'
      printf '%s\n' "$CHANGED" | sed 's/^/    /'
      _summary "- **$_s** stood down — $REASON"
      _output 'ran=false'
      exit 0
    fi
    printf 'RUN  %s\n  reason: %s\n\n' "$_s" "$REASON"
    # REDIRECTED, NEVER PIPED. `sh -e` takes a pipeline's status from its LAST
    # command, so `sh suite | tee` hands the job tee's success and a red suite
    # merges. The log is printed either way, just after the run rather than
    # during it. This is the same reasoning governance.yml carried in three
    # copies before this file existed.
    _td="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"  # a TMPDIR ending in / would print a // path
    _out="${_td%/}/$(printf '%s' "$_s" | tr '/' '_').out"
    if sh "$_sp" > "$_out" 2>&1; then _rc=0; else _rc=$?; fi
    cat "$_out"
    _output 'ran=true'
    if [ "$_rc" -ne 0 ]; then
      _summary "- **$_s** FAILED"
      log_head "${_sp#"$ROOT"/}"
      log_fail "${_sp#"$ROOT"/} exited $_rc — its full output is kept at $_out"
      log_nofix "${_sp#"$ROOT"/}"
      _kept; exit "$_rc"
    fi
    # Publish the assertion count the suite printed, for the STATUS.md check.
    # An empty one is refused rather than published as 0: status-gen would then
    # compare a real STATUS.md against nothing and pass.
    # Keyed on the BASENAME (harbor#727): tests/floor/floor.b6-test.sh prints
    # `floor.b6-test: N passed`, and a floor part's count is part of the floor's.
    _n="$(awk -v k="${_b%.sh}:" '$1 == k { print $2; exit }' "$_out")"
    if [ -n "$_n" ]; then
      _output "count=$_n"
    else
      case "$_b" in
        floor-test.sh|floor.*-test.sh|normalize-test.sh|marker-test.sh)
          log_head "${_sp#"$ROOT"/}"
          log_fail "$_s printed no assertion count; refusing to publish an empty one"
          log_nofix "${_sp#"$ROOT"/}: a count-bearing suite ends with its '${_b%.sh}: N passed, M failed' line"
          _kept; exit 1 ;;
      esac
    fi
    _summary "- \`$_s\` ran — $REASON"
    ;;

  -*)
    printf 'suite-select: unknown option: %s (see --help)\n' "$1" >&2
    exit 2
    ;;

  *)
    decide "$1" || { printf 'stand down: %s\n' "$REASON"; exit 1; }
    printf 'run: %s\n' "$REASON"
    ;;
esac
