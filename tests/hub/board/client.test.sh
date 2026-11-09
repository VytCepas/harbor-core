#!/usr/bin/env sh
# client.test.sh (harbor#1278) — bin/hub-board.sh: the token never reaches argv or a URL, and the stub seam can't redirect a member.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/board-env.sh"
be_up
B="$BE_BIN/hub-board.sh"; O="$T_TMP/out"; mkdir -p "$O"

t_section "1 - a call returns status, body and the Date header"
printf '[]' > "$BE_ST/comments/7.json"
t_eq "a response is exit 0" 0 "$(be_rc sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/issues/7/comments)"
t_eq "the status" 200 "$(cat "$O/status")"
t_eq "the body" '[]' "$(cat "$O/body")"
t_eq "the Date header" 'Sat, 07 Nov 2026 12:00:00 GMT' "$(cat "$O/date")"
t_eq "an error status is still a response" 0 "$(be_rc sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/issues/404)"
t_eq "and carries its status" 404 "$(cat "$O/status")"
printf '2026-12-01 10:00:00 UTC' > "$BE_ST/expires"
sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/issues/7/comments
t_eq "the token expiry header" '2026-12-01 10:00:00 UTC' "$(cat "$O/expires")"
rm -f "$BE_ST/expires"
t_eq "the bearer token reached the server in the header" 1 "$(be_log_count '.path | endswith("/7/comments")' | awk '$1 >= 1 {print 1}')"
t_eq "and only as the header" "Bearer $BE_TOKEN" "$(jq -rs '.[0].auth' "$BE_ST/log.jsonl")"

t_section "2 - a bad call never reaches the network"
n0="$(jq -s length "$BE_ST/log.jsonl")"
t_eq "a path with a quote" 2 "$(be_rc sh "$B" call "$O" GET '/repos/a"b')"
t_eq "a path with a newline" 2 "$(be_rc sh "$B" call "$O" GET "/repos/a
header = x")"
t_eq "a path climbing out" 2 "$(be_rc sh "$B" call "$O" GET /repos/../x)"
t_eq "a method outside the three" 2 "$(be_rc sh "$B" call "$O" DELETE /repos/a/b)"
t_eq "nothing was sent" "$n0" "$(jq -s length "$BE_ST/log.jsonl")"

t_section "3 - no token, no call"
t_eq "an empty token is exit 4" 4 "$(BE_TOKEN_VALUE='' be_rc sh "$B" call "$O" GET /repos/a/b)"
t_eq "a token that could break the config line is refused" 4 "$(BE_TOKEN_VALUE='ab"
url = "http://evil' be_rc sh "$B" call "$O" GET /repos/a/b)"
t_eq "still nothing sent" "$n0" "$(jq -s length "$BE_ST/log.jsonl")"

t_section "4 - unreachable, refused and limited are told apart"
UP="$BE_BASE"
t_eq "no server is exit 3" 3 "$(HARBOR_HUB_API_BASE=http://127.0.0.1:9 be_rc sh "$B" call "$O" GET /repos/a/b)"
t_eq "the laptop knows" unreachable "$(cat "$BE_HS/board-state")"
printf wrong > "$BE_ST/token"
sh "$B" call "$O" GET /repos/a/b
t_eq "a refused token is a response" 401 "$(cat "$O/status")"
t_eq "and a state of its own" token-expired "$(cat "$BE_HS/board-state")"
t_eq "and one token event" '{"days_left":0,"outcome":"expired-token"}' "$(jq -c '{days_left,outcome}' "$BE_HS/outbox.jsonl")"
sh "$B" call "$O" GET /repos/a/b
t_eq "told once, on the change" 1 "$(wc -l < "$BE_HS/outbox.jsonl" | tr -d ' ')"
printf '%s' "$BE_TOKEN" > "$BE_ST/token"
printf '403 limited' > "$BE_ST/perm/fixture-admin"
sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/collaborators/fixture-admin/permission
t_eq "a rate limit is flagged" 1 "$(cat "$O/limited")"
t_eq "and has a state" rate-limited "$(cat "$BE_HS/board-state")"
printf '403' > "$BE_ST/perm/fixture-admin"
sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/collaborators/fixture-admin/permission
t_eq "a plain 403 isn't one" 0 "$(cat "$O/limited")"
touch "$BE_ST/remaining0"
sh "$B" call "$O" GET /repos/fixture-org/fixture-hub/issues/7/comments
t_eq "a 200 on the last call of the hour isn't one either" 0 "$(cat "$O/limited")"
rm -f "$BE_ST/remaining0"

t_section "5 - what curl is handed"
# A logging curl first on PATH. Exit 7 is curl's own could-not-connect.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$BE_CURL_ARGV"\ncat > "$BE_CURL_STDIN"\nenv > "$BE_CURL_ENV"\nexit 7\n' > "$T_BIN/curl"
chmod +x "$T_BIN/curl"
BE_CURL_ARGV="$T_TMP/argv"; BE_CURL_STDIN="$T_TMP/stdin"; BE_CURL_ENV="$T_TMP/env"; export BE_CURL_ARGV BE_CURL_STDIN BE_CURL_ENV
planted() { CURL_CA_BUNDLE=/x SSL_CERT_FILE=/x CURL_HOME=/x "$@"; }
t_eq "no network is exit 3" 3 "$(planted be_rc sh "$B" call "$O" GET /repos/a/b)"
t_hasnt "argv never holds the token" "$(cat "$T_TMP/argv")" "$BE_TOKEN"
t_has "stdin config does" "$(cat "$T_TMP/stdin")" "Authorization: Bearer $BE_TOKEN"
t_hasnt "and the URL line doesn't" "$(grep '^url' "$T_TMP/stdin")" "$BE_TOKEN"
t_eq "-q comes first, so ~/.curlrc can't add a proxy" -q "$(sed -n 1p "$T_TMP/argv")"
t_has "a connect timeout" "$(cat "$T_TMP/argv")" --connect-timeout
t_has "a total timeout" "$(cat "$T_TMP/argv")" --max-time
t_hasnt "never follows a redirect" "$(cat "$T_TMP/argv")" --location
t_hasnt "a planted CA bundle stays out" "$(cat "$T_TMP/env")" CURL_CA_BUNDLE
t_hasnt "a planted cert file stays out" "$(cat "$T_TMP/env")" SSL_CERT_FILE

t_section "the last header block is GitHub's"
# A proxy's CONNECT reply comes first and carries its own Date, which must never pass for GitHub's.
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do case "$1" in --dump-header) h="$2" ;; --output) o="$2" ;; esac; shift; done\ncat >/dev/null\nprintf "HTTP/1.1 200 Connection established\\r\\nDate: Mon, 01 Jan 2024 00:00:00 GMT\\r\\n\\r\\nHTTP/2 200\\r\\nserver: x\\r\\n\\r\\n" > "$h"\nprintf "{}" > "$o"\nprintf 200\n' > "$T_BIN/curl"
sh "$B" call "$O" GET /repos/a/b
t_eq "the last header block decides, so a proxy's Date isn't taken" "" "$(cat "$O/date")"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "$BE_CURL_ARGV"\ncat > "$BE_CURL_STDIN"\nexit 7\n' > "$T_BIN/curl"

t_section "6 - the seam stops at the member marker"
t_has "with no marker the stub base is used" "$(sed -n 1p "$T_TMP/stdin")" "$UP"
HARBOR_HUB_API_BASE=http://example.test:1 sh "$B" call "$O" GET /repos/a/b 2>/dev/null || :
t_has "a non-loopback base is ignored even then" "$(sed -n 1p "$T_TMP/stdin")" 'url = "https://api.github.com/'
HARBOR_HUB_API_BASE=http://127.0.0.1:1@example.test sh "$B" call "$O" GET /repos/a/b 2>/dev/null || :
t_has "and so is a loopback prefix hiding another host" "$(sed -n 1p "$T_TMP/stdin")" 'url = "https://api.github.com/'
: > "$BE_BIN/harbor-member-mode"
printf '#!/bin/sh\n[ "$1" = run ] || exit 1; export "$3=sidecar_token"; shift 4; exec "$@"\n' > "$BE_BIN/secret"; chmod +x "$BE_BIN/secret"
sh "$B" call "$O" GET /repos/a/b 2>/dev/null || :
t_has "with the marker the env base is ignored" "$(sed -n 1p "$T_TMP/stdin")" 'url = "https://api.github.com/'
t_has "and only https is allowed" "$(cat "$T_TMP/argv")" '=https'
t_has "and the env secret tool is ignored for the one beside the file" "$(cat "$T_TMP/stdin")" sidecar_token
# W4: files PowerShell lays under C:\ carry whatever mode the drvfs mount gives them, so the floor never needs an execute bit.
chmod 644 "$BE_BIN/secret"; : > "$T_TMP/stdin"
sh "$B" call "$O" GET /repos/a/b 2>/dev/null || :
t_has "a secret beside the file with no execute bit is still used" "$(cat "$T_TMP/stdin")" sidecar_token
rm -f "$BE_BIN/harbor-member-mode" "$BE_BIN/secret"

t_section "7 - each tool answers --help"
for s in hub-board hub-approval hub-events; do
  t_has "$s --help" "$(sh "$BE_BIN/$s.sh" --help)" "$s.sh"
done

be_down
t_done
