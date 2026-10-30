#!/usr/bin/env sh
# doc-cite-verify.sh — fetch every external URL Harbor's docs cite, report status.
# harbor#5 (workstream C), method from upstream `Research`/UrlVerificationProtocol @ a4e8e74.
#
# NETWORK. Not wired into CI and not run by a hook — lint rule T7 does the
# offline half (is every cited URL listed in docs/reference/citations.md at all). This does the
# half that needs the wire.
#
# What it CANNOT do, by construction: decide whether the content supports the
# claim it was cited for. That is the column in docs/reference/citations.md a human fills in,
# and the whole point of the upstream protocol — a 200 is evidence the URL
# exists, never evidence the citation is honest.
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
. "$ROOT/bin/library-log.sh"
log_init cite-verify
# UNKNOWN FLAG → 2 (contracts/cli.md:70). This script took NO arguments and read
# none, so `harbor cite --json` — a flag the table says it does not have — did a
# full network sweep and exited 0 as though the flag had been honoured. It is the
# most misleading of the three cases measured on 2026-08-14, because the output of a
# successful run looks exactly like the output of an ignored flag.
#
# It accepts nothing, so ANY argument is a usage error. Stated as a case rather than
# `[ $# -eq 0 ]` so the accepted set is visible in the code and grows by editing one
# line if this ever takes a flag.
case "${1:-}" in
  '') ;;
  *) log_fail "unknown flag $1 (this command takes no arguments)"; log_fix "sh $0"; log_end || :; exit 2 ;;
esac

# ONE LIST, READ FROM THE RULE THAT OWNS IT (harbor#255 follow-on). This was a
# second copy of T7's `_fx` in bin/lint-conventions.sh, and the copy drifted the
# moment #255 added the glob discriminator to T7 ALONE. T7's comment said the two
# scripts used "the same list" while they differed by exactly `https?://[^ ]*\*`,
# so this script fetched `https://mcp.facebook.com/*` — the value inside a
# `deniedMcpServers` config example, not a source — got a 404 by construction, and
# exited 1. A false positive in the tool whose entire worth is that its verdict is
# believed, produced by the copy the doc-truth rules exist to prevent.
#
# IT FAILS LOUD IF THE READ FAILS. Falling back to a built-in default would
# reintroduce the copy silently and pass, which is the shape where a weaker check
# reads as a passing one.
# EXACTLY ONE DEFINITION, OR REFUSE. `| head -1` alone answered a second `_fx=`
# line by silently taking the first — the one shape out of ten in which this
# derivation returned a WRONG pattern instead of no pattern (edge pass
# 2026-08-29). Every other unreadable shape already exited 2; this one exited 0
# on a skip-list that was not the linter's, which is precisely the failure the
# derivation replaced a hardcoded copy to prevent, wearing different clothes.
# Counting first costs one `grep -c` and converts it into the same loud refusal.
_fxn="$(grep -c "^_fx='" "$ROOT/bin/lint-conventions.sh" 2>/dev/null || echo 0)"
FIXTURE="$(sed -n "s/^_fx='\(.*\)'\$/\1/p" "$ROOT/bin/lint-conventions.sh" | head -1)"
[ "$_fxn" = 1 ] && [ -n "$FIXTURE" ] || {
  log_fail "expected exactly one _fx= definition in bin/lint-conventions.sh, found $_fxn"
  log_nofix "bin/doc-cite-verify.sh (the fixture-URL list is read from lint rule T7's _fx=)"
  log_end || :; exit 2
}

urls="$(cd "$ROOT" && git grep -ohE 'https?://[^ )>"`]+' -- '*.md' ':!vendor/*' 2>/dev/null \
        | sed 's/[.,;]*$//' \
        | grep -vE "$FIXTURE" \
        | sort -u)"

[ -n "$urls" ] || { log_note "no external citations found"; log_end; exit $?; }

# An anonymous GET is the WRONG VERIFIER for a private repo. harbor is private,
# so curl returns 404 for its own issue URLs while `gh` returns them fine — and
# reporting that as a broken citation is a false positive, which policy/constitution.md
# calls a defect rather than caution. Use the authenticated client where the
# host has one, and SAY which verifier answered: "404 to an anonymous fetcher"
# and "does not exist" are different facts.
probe() { # <url> -> "<code> <verifier>"
  case "$1" in
    https://github.com/*)
      if command -v gh >/dev/null 2>&1; then
        _p="${1#https://github.com/}"
        case "$_p" in
          */issues/*|*/pull/*)
            _r="$(printf '%s' "$_p" | cut -d/ -f1,2)"
            _n="$(printf '%s' "$_p" | sed 's|.*/||')"
            gh api "repos/$_r/issues/$_n" --jq .number >/dev/null 2>&1 \
              && { printf '200 gh'; return 0; } ;;
          *)
            gh repo view "$(printf '%s' "$_p" | cut -d/ -f1,2)" >/dev/null 2>&1 \
              && { printf '200 gh'; return 0; } ;;
        esac
      fi ;;
  esac
  printf '%s curl' "$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 15 "$1" 2>/dev/null || echo 000)"
}

# THE VERDICT IS DRIFT, NOT 200-NESS (2026-07-30). Two citations added with
# skills/<name> are authenticated API endpoints: an anonymous GET gets 401 from
# an accounts endpoint and 400 from oauth2 tokeninfo. Both codes ARE the
# verification — the server routed the request and demanded a credential or a
# parameter, which is exactly the "this endpoint exists" fact being cited — and
# calling them broken is the same false positive this script already fixed for
# private-repo GitHub URLs, which CONSTITUTION §2.11 classes as a defect.
#
# So the recorded HTTP column in docs/reference/citations.md becomes part of the fact: a
# citation passes when it answers 2xx/3xx OR when it answers exactly what was
# recorded and reviewed. A citation that CHANGES its answer is the interesting
# event, and this now reports that instead of reporting non-2xx.
recorded() { # <url> -> the HTTP code docs/reference/citations.md records, or empty
  awk -F'|' -v u="$1" '
    $0 ~ /^\|/ {
      gsub(/^[ \t]*`|`[ \t]*$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $2)
      gsub(/^[ \t]+|[ \t]+$/, "", $3)
      if ($2 == u) { print $3; exit }
    }' "$ROOT/docs/reference/citations.md" 2>/dev/null
}

log_head "$(printf '%s\n' "$urls" | wc -l | tr -d ' ') cited URL(s)"
for u in $urls; do
  r="$(probe "$u")"
  code="${r% *}"; via="${r#* }"
  case "$code" in
    2*|3*) log_ok "$u  http=$code via $via" ;;
    *)
      _exp="$(recorded "$u")"
      if [ -n "$_exp" ] && [ "$_exp" = "$code" ]; then
        log_ok "$u  http=$code via $via — matches the code recorded in docs/reference/citations.md, reviewed, not broken"
      else
        log_fail "$u  http=$code via $via — UNEXPECTED (recorded: ${_exp:-none}); a broken citation is a defect, not cosmetics"
        log_fix "curl -sIL $u  # then fix the citation, or record the code in docs/reference/citations.md once reviewed"
      fi ;;
  esac
done

log_note "a resolving URL is existence, NOT support: the 'cited for' column in docs/reference/citations.md is the claim, and only a human closes it"
log_end; exit $?
