#!/usr/bin/env sh
# hub-fetch.sh (harbor#1278) — the heartbeat issues of a hub repo and their comments, flattened for hub-digest.sh --issues. Reads GitHub, writes only stdout.
#   sh hub-fetch.sh <owner/name> [--since-days N]
# Needs gh on PATH with GH_TOKEN in the environment (a workflow's github.token reads issues; the token never goes in an argument or a URL).
# Prints a JSON array: [{"title","author","comments":[{"author","created_at","body"}]}], one entry per issue titled `heartbeat <login>`,
# closed ones included, comments from N days back (default 95: past the longest silent_days of 90). Nothing is printed if any read fails.
# Exit 0 printed, 2 usage, 3 GitHub unreachable or refused.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init hub-fetch
usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

REPO=""; DAYS=95
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --since-days) [ "$#" -ge 2 ] || usage; DAYS="$2"; shift ;;
    -*) usage ;;
    *) [ -z "$REPO" ] || usage; REPO="$1" ;;
  esac
  shift
done
[ -n "$REPO" ] || usage
printf '%s' "$REPO" | grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || { log_fail "'$REPO' is not owner/name"; log_nofix "name the hub repo as owner/name"; log_end || :; exit 2; }
case "$DAYS" in ''|*[!0-9]*|0) log_fail "--since-days wants a whole number of days"; log_nofix "the header of bin/hub-fetch.sh"; log_end || :; exit 2 ;; esac
for _t in gh jq; do command -v "$_t" >/dev/null 2>&1 || { log_fail "$_t is missing"; log_fix "$(pkg_hint "$_t")"; log_end || :; exit 3; }; done

T="$(mktemp -d "${TMPDIR:-/tmp}/hub-fetch.XXXXXX")" || exit 2
trap 'rm -rf "$T"' EXIT INT TERM
unreachable() { log_fail "GitHub did not answer for $1: $(tail -n 1 "$T/err" 2>/dev/null)"; log_nofix "the next run reads again; nothing was printed"; log_end || :; exit 3; }

SINCE="$(jq -n -r --argjson d "$DAYS" 'now - ($d * 86400) | todate')"
# gh writes to a file first: in a pipe its failure would be hidden by jq's exit, and an empty list reads as "no members"
gh api --paginate "repos/$REPO/issues?state=all&per_page=100" > "$T/raw" 2> "$T/err" || unreachable "the issue list"
jq -s 'add // []' "$T/raw" > "$T/all.json" 2> "$T/err" || unreachable "the issue list"
jq -c '.[] | select((.pull_request | not) and ((.title // "") | startswith("heartbeat "))) | {number, title, author: (.user.login // "")}' "$T/all.json" > "$T/heartbeats"

: > "$T/out"
while IFS= read -r _i; do
  _n="$(printf '%s' "$_i" | jq -r '.number')"
  gh api --paginate "repos/$REPO/issues/$_n/comments?per_page=100&since=$SINCE" > "$T/raw" 2> "$T/err" || unreachable "issue $_n"
  jq -s 'add // []' "$T/raw" > "$T/c.json" 2> "$T/err" || unreachable "issue $_n"
  printf '%s' "$_i" | jq -c --slurpfile c "$T/c.json" '{title, author, comments: ($c[0] | map({author: (.user.login // ""), created_at, body: (.body // "")}))}' >> "$T/out"
done < "$T/heartbeats"
jq -s '.' "$T/out"
