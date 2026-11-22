#!/usr/bin/env sh
# access-redact.sh (harbor#1597) — mask credentials in text an agent is about to read (contracts/secret-intake.md).
#
#   … | sh access-redact.sh            stdin to stdout, line by line; a masked value reads [REDACTED]
#   … | sh access-redact.sh --check    print nothing; exit 1 when anything WOULD be masked, 0 when nothing would
#
# A browser page is where a password autofills and a freshly minted API key is shown once, and whatever a tool prints
# lands in the transcript (it did: a snapshot printed a vendor password, 2026-11-21). Three rules, each line:
#   1. a provider token shape: the floor egress guard's SECRET list, read from admission-egress.sh BESIDE this file, so
#      the guard that stops a token being written and this filter that stops one being read are one list;
#   2. the value of a form field whose label names a secret (password, token, API key, one-time code …), in the
#      Playwright snapshot form `textbox "<label>" [ref=…]: <value>`;
#   3. a URL parameter that carries one (access_token=, client_secret=, password= …).
# Fail closed: a missing guard file or a failing filter prints one withheld line and exits 3, never the raw text.
# Not a boundary: a secret with no known shape, shown as plain page text under no secret label, passes. The protocol
# (contracts/secret-intake.md) is what keeps a minted key off the page: Copy, then `harbor access … --value-clipboard`.
set -u
# Bytes, not characters: BSD sed under a UTF-8 locale fails on an invalid byte, which would withhold every such page.
LC_ALL=C; export LC_ALL
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# Stdout is the filtered text; the log is stderr, and a clean run logs nothing (every harbor chrome reply passes here).
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$HERE/library-log.sh"
log_init access-redact
EGRESS="${HARBOR_ACCESS_REDACT_EGRESS:-$HERE/admission-egress.sh}"   # test seam: a fixture guard file
MODE=filter
case "${1:-}" in
  --check) MODE=check ;;
  '') ;;
  -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) log_fail "unknown argument: $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac
# In band as well as logged: the reader of stdout is an agent, and an empty reply would read as an empty page.
withheld() { # <why> <fix>
  cat >/dev/null
  [ "$MODE" = check ] || printf '[harbor: output withheld: the credential redactor failed: %s]\n' "$1"
  log_fail "output withheld: $1"; log_fix "$2"; log_end || :; exit 3
}

SECRET="$(sed -n "s/^SECRET='\(.*\)'\$/\1/p" "$EGRESS" 2>/dev/null | head -1)"
[ -n "$SECRET" ] || withheld "no SECRET list in $EGRESS" "ls -l $EGRESS   # the floor egress guard ships beside this file"
case "$SECRET" in *'#'*) withheld "the SECRET list holds '#', this filter's sed delimiter" "pick another delimiter in $0" ;; esac

# Line-buffered, so a streamed log line is not held until exit (GNU -u, BSD -l).
SEDU=''
if sed -u q </dev/null >/dev/null 2>&1; then SEDU=-u; elif sed -l q </dev/null >/dev/null 2>&1; then SEDU=-l; fi
URLP='access_token|id_token|refresh_token|client_secret|api_?key|apikey|password|passwd|secret|token'
# Two delimiters: the SECRET list holds no '#', the URL rule's class does, and holds no '%'.
E1="s#$SECRET#[REDACTED]#g"
E2="s%([?&;#](${URLP})=)[^&#[:space:]\"'<>)]+%\\1[REDACTED]%g"
# A sed that rejects an expression prints nothing and the pipe below would pass that off as a clean, empty page.
printf 'x\n' | sed -E -e "$E1" -e "$E2" >/dev/null 2>&1 || withheld "sed rejects the expressions" "printf 'x\\n' | sed -E -e '<E1>' -e '<E2>'   # read the SECRET list in $EGRESS"

# shellcheck disable=SC2086 # SEDU is one flag or none
sed $SEDU -E -e "$E1" -e "$E2" \
| awk -v mode="$MODE" '
  BEGIN { hit = 0 }
  {
    l = $0
    if (index(l, "[REDACTED]")) hit = 1
    if (match(l, /textbox "[^"]*"[^:]*: /)) {
      lab = tolower(substr(l, RSTART, RLENGTH))
      if (lab ~ /pass|secret|token|api.?key|private.?key|client.?key|access.?key|otp|one.?time|verification|security code|digit code|sms code|authenticator|recovery code|backup code|auth(entication)? code|2fa|mfa|pin[^a-z]|cvc|cvv|card number|credential/ \
          && substr(l, RSTART + RLENGTH) != "" && substr(l, RSTART + RLENGTH) != "[REDACTED]") {
        l = substr(l, 1, RSTART + RLENGTH - 1) "[REDACTED]"; hit = 1
      }
    }
    if (mode == "filter") { print l; fflush() }
  }
  END { if (mode == "check") exit hit }' || {
  rc=$?
  [ "$MODE" = check ] && [ "$rc" = 1 ] && exit 1
  [ "$MODE" = check ] || printf '[harbor: output withheld: the credential redactor failed (exit %s)]\n' "$rc"
  log_fail "the filter failed (exit $rc)"; log_nofix "contracts/secret-intake.md"; log_end || :; exit 3
}
