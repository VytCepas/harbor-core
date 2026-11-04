#!/usr/bin/env sh
# doc-cite-verify.sh — fetch every external URL Harbor's docs cite, report status.
# harbor#5 (workstream C), method from upstream `Research`/UrlVerificationProtocol @ a4e8e74.
#
# NETWORK; not in CI or a hook (lint T7 does the offline half: is every cited URL listed in
# docs/reference/citations.md). It cannot decide whether the content supports the claim cited;
# that column is a human's. A 200 is evidence the URL exists, never that the citation is honest.
# Removed notes: docs/explanation/code-cases/bin-doc-cite-verify.md
set -eu

# --help before any work (S4, harbor#140): the text is this header, read at runtime.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/library-log.sh"
log_init cite-verify
# Unknown flag is 2 (contracts/cli.md:70): an ignored `--json` once ran a full network sweep and exited 0.
# This takes no arguments, so a case keeps the accepted set visible.
case "${1:-}" in
  '') ;;
  *) log_fail "unknown flag $1 (this command takes no arguments)"; log_fix "sh $0"; log_end || :; exit 2 ;;
esac

# The fixture list is read from lint rule T7's `_fx=` (harbor#255), not copied: the copy drifted and this
# script fetched a `deniedMcpServers` example URL, a false positive. A failed read is loud, never a
# built-in default. Exactly one definition or refuse: `head -1` alone took the first of two silently.
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

# An anonymous GET is the wrong verifier for a private repo (404 for harbor's own issue URLs), so use
# `gh` where the host has one and SAY which verifier answered.
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

# The verdict is drift, not 200-ness: authenticated endpoints answer 401/400 anonymously, which IS the
# "endpoint exists" fact. A citation passes on 2xx/3xx or on exactly the code recorded in
# docs/reference/citations.md; a CHANGED answer is the event reported.
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
