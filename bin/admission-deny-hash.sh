#!/usr/bin/env sh
# M7 · DeriveDenyHashes (harbor#44) — a leak filter over the operator's OWN private
# strings that never contains one of them in the clear.
#
#   sh admission-deny-hash.sh --propose [--live | <cfg>]        candidate terms, printed only
#   sh admission-deny-hash.sh --derive  --live | <cfg>          terms file -> digest filter
#   sh admission-deny-hash.sh --scan    [--live | <cfg>] [file...]   stdin or files; exit 1 on a hit
#   ... --json
#
# THE GAP IT CLOSES. `admission-egress.sh` knows generic secret SHAPES — `sk-`, `ghp_`,
# PEM headers. It cannot know *your* secrets, so it cannot catch an API key with an
# unusual prefix, or a client's name. This closes that without the filter becoming
# the leak: only salted, truncated digests are stored.
#
# ── THE TERMS ARE DECLARED, NOT INFERRED, AND THAT IS THE DESIGN ─────────────
#
# The obvious build reads the private corpus and decides for itself which tokens
# are secret. That is a policy guess with a cost in both directions: guess narrow
# and the filter misses the thing it exists to catch, giving false confidence;
# guess wide and it blocks ordinary work, which is how a control gets switched off
# (policy/constitution.md §2.11).
#
# So the source of truth is `<cfg>/.helm-deny-terms`, authored by the operator: one
# term per line, `#` comments ignored. `--propose` reads the corpus and PRINTS
# candidates for review, writing nothing. That is the constitution's rule made
# concrete — the system may observe continuously and propose in batch, and may not
# promote its own observations into a control without a person approving them.
#
# ── WHAT IT DELIBERATELY IS NOT ──────────────────────────────────────────────
#
# NOT WIRED INTO A GUARD. `admission-egress.sh` is a B6 hash-pinned control surface, so
# making it consult this filter needs a re-pin and is the operator's act (owner
# decision 2026-08-05). This ships the filter and an offline scanner, so the
# detection exists and is measurable before anything blocks a tool call on it.
#
# SINGLE-TOKEN TERMS ONLY. Scanning digests each whitespace-delimited token of the
# input and tests membership, so a multi-word phrase cannot match. Said out loud
# because a filter that silently ignores half its terms is worse than one that
# refuses them: `--derive` REJECTS a term containing whitespace rather than storing
# a digest nothing will ever match.
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): three modes over one digest
# primitive and one filter format. Splitting them would put two spellings of the
# filter format in two files, and the format is the whole contract.
set -eu

# stdout is data here (--propose's candidate terms, --scan --json), so the log is on stderr (LOG_FD=2,
# contracts/logging.md, harbor#771).
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SELF/library-log.sh"
log_init deny-hash; LOG_FD=2
# die <what failed> <fix> [exit] — FAIL, its fix, the summary, then the exit code the tool always had (2).
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-2}"; }

MODE=""
JSON=0
DIR=""
LIVE_OK=0
LIVE_DIR="$HOME/.claude"
# OPERANDS STAY IN "$@", NEVER IN A SPACE-JOINED STRING (PR #127 review). The first
# cut accumulated `FILES="$FILES $1"` and later expanded it unquoted, so a filename
# containing a space was split into two nonexistent paths — and because the reader
# swallowed errors, the scan then reported CLEAN. Re-queueing each operand onto the
# positional list preserves it byte-for-byte, whatever is in it.
_argc=$#
_seen=0
while [ "$_seen" -lt "$_argc" ]; do
  _a="$1"; shift; _seen=$((_seen + 1))
  case "$_a" in
    --propose) MODE=propose ;;
    --derive)  MODE=derive ;;
    --scan)    MODE=scan ;;
    --json)    JSON=1 ;;
    --live)    LIVE_OK=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "unknown option $_a: nothing was scanned or written" "sh $0 --help" ;;
    *)  if [ -z "$DIR" ] && [ -d "$_a" ]; then DIR="$_a"; else set -- "$@" "$_a"; fi ;;
  esac
done
[ -n "$MODE" ] || die "one of --propose/--derive/--scan is required" "sh $0 --help"

[ -n "$DIR" ] || { [ "$LIVE_OK" -eq 1 ] && DIR="$LIVE_DIR"; }
CFG="${DIR:-${CLAUDE_CONFIG_DIR:-$LIVE_DIR}}"

# THE HASHER IS DERIVED, NEVER RE-IMPLEMENTED. floor_obs_digest owns the algorithm
# — salt, separator, truncation length — and a second spelling here would drift
# silently and stop matching, which for a leak filter fails toward MISSING a hit.
#
# SOURCED FROM THE SIBLING, NEVER FROM THE INSPECTED DIRECTORY. Sourcing
# `<cfg>/bin/library-admission.sh` executes a file out of the tree under inspection; a
# hostile copy could redefine the digest to a constant and every scan would come
# back clean. `$SELF/library-admission.sh` is the same trust domain as this script. The
# SALT still comes from the inspected dir, which is data, not code.
[ -r "$SELF/library-admission.sh" ] || die "library-admission.sh is not readable beside this script: $SELF" "git checkout -- bin/library-admission.sh"
# shellcheck source=/dev/null
. "$SELF/library-admission.sh"

TERMS="$CFG/.helm-deny-terms"
FILTER="$CFG/.helm-deny-hashes"

digest_of() { # <term> -> 16 hex chars, or `-` when the box cannot hash
  FLOOR_OBS_SUBJECT="$1" floor_obs_digest "$CFG"
}

# ── ONE TOKEN ALPHABET, USED BY BOTH SIDES (PR #127 review) ──────────────────
# `--derive` hashes whole terms; `--scan` hashes the tokens it finds in the input.
# If those two disagree about what a token IS, a term can be stored and never
# matched — `--derive` reports coverage for something no scan can ever hit, which
# is the same silently-inert failure the multi-word refusal exists to prevent.
# Measured examples that the first cut accepted and could never match:
# `client:api/key` (`:` and `/` are separators to the scanner) and a base64 token
# ending in `=`.
#
# So the alphabet is defined ONCE, here, and both the round-trip check and the scan
# tokenizer read it. A second spelling is the drift the T rules exist for.
TOKEN_CLASS='A-Za-z0-9._@+-'

# term_roundtrips <term> — 0 iff the scanner's tokenizer yields this term, whole.
# Compared against the FIRST token and the token COUNT: a term that tokenizes into
# two pieces whose first piece equals the term would otherwise pass.
term_roundtrips() {
  _rt="$(printf '%s' "$1" | tr -cs "$TOKEN_CLASS" '\n' | sed '/^$/d')"
  [ "$_rt" = "$1" ]
}

# ── --derive · terms -> filter ───────────────────────────────────────────────
if [ "$MODE" = "derive" ]; then
  # WRITES, SO IT IS GATED (lint D2). The default target is the active config dir,
  # which on the operator's machine IS the live one — so a bare --derive would
  # write a filter into ~/.claude because nobody named anywhere else. Resolved-path
  # compare, because a trailing slash or a symlinked route spells the same
  # directory differently.
  if [ "$LIVE_OK" -eq 0 ]; then
    _phys="$(CDPATH= cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"
    _live="$(CDPATH= cd -P -- "$LIVE_DIR" 2>/dev/null && pwd -P || printf '%s' "$LIVE_DIR")"
    if [ "$_phys" = "$_live" ]; then
      die "refusing to write the LIVE filter without an explicit --live" "sh $0 --derive --live" 1
    fi
  fi
  [ -f "$TERMS" ] || die "no terms file at $TERMS" "sh $0 --propose"
  # ── THE TERMS FILE IS THE SECRET, AND IT IS PLAINTEXT ──────────────────────
  # The FILTER contains no secret in the clear, which is the ticket's promise. The
  # TERMS file necessarily does: the operator wrote the strings into it. So this
  # design does not remove a plaintext secret from the box, it adds one — and
  # saying so is the difference between a control and a comforting story.
  #
  # Warned, never silently fixed: chmod-ing a file the operator authored is
  # modifying their content. Neither this file nor the filter is in
  # `permissions.deny` or the file-tool guard's protected set today; by M10's tier
  # table both are tier 0, so closing that is an operator act.
  if [ -r "$TERMS" ]; then
    _tmode="$(ls -l "$TERMS" 2>/dev/null | cut -c1-10)"
    case "$_tmode" in
      -rw-------|-r--------) : ;;
      *) log_warn "$TERMS is $_tmode — it holds your terms IN PLAINTEXT; consider a deny entry: Edit(~/.claude/.helm-deny-terms)"
         log_fix "chmod 600 $TERMS" ;;
    esac
  fi
  _probe="$(digest_of harbor-deny-hash-selftest)"
  [ "$_probe" != "-" ] || \
    die "cannot hash on this box — no usable salt or sha256; refusing to write an EMPTY filter, which would read as \"nothing to block\"" "sh bin/deploy-doctor.sh"

  _tmp="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -f "$_tmp"' EXIT INT TERM
  _n=0; _skipped=0
  while IFS= read -r _line || [ -n "$_line" ]; do
    case "$_line" in ''|\#*) continue ;; esac
    # A TERM WITH WHITESPACE IS REFUSED, NOT SILENTLY STORED. Scanning is
    # token-wise, so a phrase's digest could never match anything and the operator
    # would believe it was covered.
    case "$_line" in *[[:space:]]*)
      log_warn "refusing multi-word term (scanning is token-wise): $_line"
      log_fix "edit $TERMS: one token per line, then sh $0 --derive $CFG"
      _skipped=$((_skipped+1)); continue ;;
    esac
    # …and the general case the whitespace check only covers a slice of: any
    # separator outside the scan alphabet splits the term, so its stored digest
    # could never be produced from real content.
    if ! term_roundtrips "$_line"; then
      log_warn "refusing term the scanner cannot reproduce as one token (it would be stored and never matched): $_line"
      log_fix "edit $TERMS: split the term, or drop the separators, then sh $0 --derive $CFG"
      _skipped=$((_skipped+1)); continue
    fi
    _d="$(digest_of "$_line")"
    [ "$_d" = "-" ] && die "could not hash a term; aborting" "sh bin/deploy-doctor.sh"
    printf '%s\n' "$_d" >> "$_tmp"
    _n=$((_n+1))
  done < "$TERMS"

  sort -u "$_tmp" > "$_tmp.s" && mv "$_tmp.s" "$_tmp"
  # 0600: the filter is not a secret, but it is a fingerprint OF one, and an
  # offline dictionary attack over a guessable term space is cheap.
  ( umask 077; cp "$_tmp" "$FILTER" )
  chmod 0600 "$FILTER" 2>/dev/null || :
  log_ok "wrote $(wc -l < "$FILTER" | tr -d ' ') digest(s) -> $FILTER"
  [ "$_skipped" -eq 0 ] || log_note "$_skipped term(s) refused (see above)"
  log_end; exit $?
fi

# ── --propose · candidates, printed and never written ────────────────────────
if [ "$MODE" = "propose" ]; then
  # READ-ONLY BY CONSTRUCTION: this mode has no write path at all. It prints
  # high-signal shapes out of the private corpus for the operator to curate into
  # the terms file. It does NOT decide what is secret — see the header.
  # Corpus paths are collected onto the positional list rather than a space-joined
  # string, for the reason recorded at the argument loop: a path containing a space
  # becomes two nonexistent paths, and the reader then finds nothing.
  set --
  for _c in "$CFG/MEMORY/IDENTITY.md" "$CFG/MEMORY/TELOS"/*.md "$CFG/MEMORY/TELOS"/*/*.md; do
    [ -f "$_c" ] && set -- "$@" "$_c"
  done
  [ "$#" -gt 0 ] || die "no private corpus under $CFG/MEMORY" "ls $CFG/MEMORY"
  printf '# candidate terms from the private corpus — REVIEW, then copy into:\n'
  printf '#   %s\n' "$TERMS"
  printf '# Nothing here is written anywhere by this mode.\n'
  printf '# Shapes only: email-like, domain-like, and long mixed-class tokens.\n#\n'
  cat -- "$@" 2>/dev/null \
    | tr -cs "$TOKEN_CLASS" '\n' \
    | awk '
        length($0) >= 8 {
          if ($0 ~ /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z][A-Za-z]+$/) { print; next }
          if ($0 ~ /^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$/ && $0 ~ /\.[A-Za-z][A-Za-z]+$/) { print; next }
          if (length($0) >= 16 && $0 ~ /[0-9]/ && $0 ~ /[A-Za-z]/) { print; next }
        }' \
    | sort -u
  log_ok "proposed candidate terms from the private corpus; nothing was written"
  log_end; exit $?
fi

# ── --scan · read-only detection ─────────────────────────────────────────────
[ -f "$FILTER" ] || die "no filter at $FILTER" "sh $0 --derive $CFG"
_probe="$(digest_of harbor-deny-hash-selftest)"
# The silent-pass shape this refuses to produce.
[ "$_probe" != "-" ] || die "cannot hash on this box — a scan would report CLEAN over every input" "sh bin/deploy-doctor.sh"

_in="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -f "$_in" "$_in.t"' EXIT INT TERM

# AN UNREADABLE INPUT IS REFUSED, NEVER SCANNED AS EMPTY (PR #127 review). The
# first cut ran `cat $FILES … 2>/dev/null || :`, so a missing path, a permission
# error, or a filename split on a space left the buffer empty or partial — and the
# scanner then printed `clean` and exited 0 over content it had never read. For a
# leak filter that is the worst available outcome: a confident all-clear on an
# unexamined file. Checked BEFORE reading, so the refusal names the path.
if [ "$#" -gt 0 ]; then
  for _f in "$@"; do
    [ -e "$_f" ] || die "no such input: $_f" "ls -l \"$_f\""
    [ -d "$_f" ] && die "input is a directory: $_f" "sh $0 --scan $CFG <a file>"
    [ -r "$_f" ] || die "input is not readable: $_f" "chmod u+r \"$_f\""
  done
  cat -- "$@" > "$_in" || die "failed reading the inputs — refusing to report" "ls -l <the inputs>"
else
  cat > "$_in" || die "failed reading stdin — refusing to report" "sh $0 --scan $CFG <a file>"
fi

# Tokens deduped BEFORE hashing: one sha256 fork per distinct token, not per
# occurrence. No length floor is applied: --derive is the only writer of the filter
# and it stores whatever the operator declared, so skipping short tokens here could
# hide a hit.
tr -cs "$TOKEN_CLASS" '\n' < "$_in" | sort -u > "$_in.t"

_hits=0
if [ "$JSON" = "1" ]; then printf '{"hits":['; fi
_sep=""
while IFS= read -r _tok; do
  [ -n "$_tok" ] || continue
  _d="$(digest_of "$_tok")"
  [ "$_d" = "-" ] && continue
  # $FLOOR_GREP, NEVER a bare grep (lint F3), and here it is load-bearing rather
  # than stylistic: this box's grep is a ugrep wrapper carrying -I --ignore-files,
  # which silently skips inputs it judges binary or ignored. A skipped filter file
  # makes every membership test MISS, and for a leak filter that is the dangerous
  # direction — a scan that reports clean over content full of declared terms.
  if "$FLOOR_GREP" -qxF -- "$_d" "$FILTER" 2>/dev/null; then
    _hits=$((_hits+1))
    # THE MATCH IS REPORTED BY DIGEST, NEVER BY VALUE. Printing the token would
    # make this tool the leak it exists to prevent — including into a CI log.
    [ "$JSON" != "1" ] || { printf '%s{"digest":"%s","length":%s}' "$_sep" "$_d" "${#_tok}"; _sep=","; }
    log_fail "HIT digest=$_d length=${#_tok}"
    log_nofix "contracts/control-plane-state.md — remove the declared private term from the scanned content, then re-run sh $0 --scan"
  fi
done < "$_in.t"

[ "$JSON" != "1" ] || printf '],"hit_count":%s,"filter":"%s"}\n' "$_hits" "$FILTER"
if [ "$_hits" -eq 0 ]; then
  log_ok "clean ($(wc -l < "$_in.t" | tr -d ' ') distinct token(s) checked against $(wc -l < "$FILTER" | tr -d ' ') digest(s))"
else
  log_note "$_hits hit(s) — a declared private term appears in the scanned content"
fi
log_end; exit $?
