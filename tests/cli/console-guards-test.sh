#!/usr/bin/env sh
# harbor ui's guards (harbor#738): loopback bind, token, Origin and Host, the allowlist, the idle stop, the verb.
# Every guard is also deleted from a copy of the server, and the same probe must then fail: the red proofs.
# HARBOR_REQUIRE_BUN=1 turns a missing bun into a failure; the runner image carries bun once rebuilt.
REAL_HOME="$HOME"; UI_BUN="${HARBOR_STATUS_CONSOLE_BUN:-}"; REQ_BUN="${HARBOR_REQUIRE_BUN:-0}"  # before t_init clears them
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"; . "$T_ROOT/tests/cli/console-fixture.sh"
[ -n "$UI_BUN" ] || UI_BUN="$(command -v bun 2>/dev/null || true)"
[ -n "$UI_BUN" ] || { [ ! -x "$REAL_HOME/.bun/bin/bun" ] || UI_BUN="$REAL_HOME/.bun/bin/bun"; }
UI="$T_ROOT/bin/status-console.sh"
alive() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in ''|Z*) echo no ;; *) echo yes ;; esac; }  # a zombie is gone
wait_exit() { _w=0; while [ $_w -lt 150 ] && [ "$(alive "$1")" = yes ]; do sleep 0.1; _w=$((_w + 1)); done; }

t_section "the verb, with no bun needed"
t_exit "harbor ui --help answers" 0 sh "$T_ROOT/bin/harbor" ui --help
t_has "and names the idle stop" "$(sh "$T_ROOT/bin/harbor" ui --help 2>&1)" "--idle"
t_has "harbor help lists the verb" "$(sh "$T_ROOT/bin/harbor" help 2>&1)" "  ui  "
t_exit "ui has no --json, so the dispatcher refuses it" 2 sh "$T_ROOT/bin/harbor" ui --json
linux_path "$T_TMP/nobun" bun
NB="$(env PATH="$T_TMP/nobun" /bin/sh "$UI" 2>&1; echo "RC=$?")"
t_has "no bun is exit 2" "$NB" "RC=2"
t_has "and says what is missing and the fix" "$NB" "bun is not installed"

if [ -z "$UI_BUN" ]; then
  echo "  SKIP the server arms: no bun on PATH (the runner image carries it once rebuilt)"
  t_section "bun is absent: only an image that does not promise it may skip"
  t_eq "HARBOR_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
  t_done
fi
ui_require_listen "the server arms"

t_section "the runner image carries bun, pinned and checksummed; until it is rebuilt both suites skip, loudly (harbor#738)"
DF="$T_ROOT/runners/linux/Dockerfile"
t_has "bun comes from the release page" "$(cat "$DF")" "oven-sh/bun/releases"
t_eq "bun is checksummed for both architectures" 2 "$(grep -c 'bun_sha=[0-9a-f]\{64\}' "$DF")"
mkdir -p "$T_TMP/nobunhome"
for _s in console-guards-test console-panels-test; do
  NB="$(env HOME="$T_TMP/nobunhome" PATH="$T_TMP/nobun" /bin/sh "$T_ROOT/tests/cli/$_s.sh" 2>&1; echo "RC=$?")"
  t_has "$_s passes where there is no bun" "$NB" "RC=0"
  t_has "and its skip says so" "$NB" "SKIP the"
done

ui_tree 0
t_section "an unknown flag is refused before anything listens"
t_has "exit 2 and the flag named" "$(HARBOR_STATUS_CONSOLE_BUN="$UI_BUN" sh "$UI" --nope 2>&1; echo "RC=$?")" "RC=2"
t_has "it names the argument" "$(HARBOR_STATUS_CONSOLE_BUN="$UI_BUN" sh "$UI" --nope 2>&1)" "unknown argument --nope"

t_section "it binds 127.0.0.1 and prints one URL with a single-use launch code"
ui_start main --idle 300
t_eq "the listener is on 127.0.0.1, not the wildcard" 127.0.0.1 "$(ui_listen "$UI_PID" "$UI_PORT")"
t_eq "the launch code is 64 hex characters" 64 "${#UI_CODE}"
t_eq "the session cookie is another value" different "$([ -n "$UI_TOKEN" ] && [ "$UI_TOKEN" != "$UI_CODE" ] && echo different)"
C1="$UI_CODE"; P1="$UI_PORT"; PID1="$UI_PID"; K1="$UI_COOKIE"; ui_start second --idle 300; C2="$UI_CODE"; ui_stop; UI_PID="$PID1"
t_eq "a second launch has another code" different "$([ "$C1" != "$C2" ] && echo different)"
UI_CODE="$C1"; UI_PORT="$P1"; UI_URL="http://127.0.0.1:$P1"; UI_COOKIE="$K1"

t_section "no session, a bad session, a foreign Origin, Host or Sec-Fetch-Site is 403"
t_eq "no cookie" 403 "$(ui_code "$UI_URL/")"
t_eq "a wrong cookie" 403 "$(ui_code -H "Cookie: harbor_ui_$UI_PORT=nope" "$UI_URL/")"
t_eq "the launch code as a cookie" 403 "$(ui_code -H "Cookie: harbor_ui_$UI_PORT=$UI_CODE" "$UI_URL/")"
t_eq "the launch code as a bearer token" 403 "$(ui_code -H "Authorization: Bearer $UI_CODE" "$UI_URL/")"
t_eq "the session as a bearer token (the cookie is the only door)" 403 "$(ui_code -H "Authorization: Bearer $UI_TOKEN" "$UI_URL/")"
t_eq "the session's first half" 403 "$(ui_code -H "Cookie: harbor_ui_$UI_PORT=$(printf '%s' "$UI_TOKEN" | cut -c1-32)" "$UI_URL/")"
t_eq "the cookie of another port's name" 403 "$(ui_code -H "Cookie: harbor_ui_1=$UI_TOKEN" "$UI_URL/")"
t_eq "a foreign Origin with the session" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Origin: http://evil.example' "$UI_URL/")"
t_eq "Origin: null with the session" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Origin: null' "$UI_URL/")"
t_eq "an Origin that merely starts with ours (a longer host name)" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Origin: http://127.0.0.1.evil.example' "$UI_URL/")"
t_eq "the same host on another port" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H "Origin: http://127.0.0.1:$((UI_PORT + 1))" "$UI_URL/")"
t_eq "a foreign Host with the session (DNS rebinding)" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Host: evil.example' "$UI_URL/")"
t_eq "our Origin, ours" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H "Origin: $UI_URL" "$UI_URL/")"
t_eq "a page on another localhost port (cross-site fetch)" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: cross-site' "$UI_URL/")"
t_eq "a page on another port of this host (same-site)" 403 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: same-site' "$UI_URL/")"
t_eq "the console's own script (same-origin)" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: same-origin' "$UI_URL/")"
t_eq "a typed URL (none)" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: none' "$UI_URL/")"
t_eq "the event stream is refused cross-site too" 403 "$(ui_code -m 2 -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: cross-site' "$UI_URL/events")"
t_eq "the cookie authorises the event stream" 200 "$(ui_code -m 1 -H "Cookie: $UI_COOKIE" "$UI_URL/events")"
t_eq "the launch code in the query of any path but the page" 403 "$(ui_code "$UI_URL/events?token=$UI_CODE")"
t_eq "a malformed Host is 403, not a crash" 403 "$(ui_code -H "Host: 127.0.0.1:$UI_PORT." "$UI_URL/")"
BAD="$(curl -s -m 20 -H "Host: 127.0.0.1:$UI_PORT." -H "Cookie: $UI_COOKIE" "$UI_URL/")"
t_eq "and answers plain text" "forbidden" "$(printf '%s' "$BAD" | tr -d '\n')"
t_hasnt "with no path or source in it" "$BAD" "server.ts"
ui_stop

t_section "the launch code opens the console once, and the URL it leaves behind is clean"
UI_NOEX=1; ui_start once --idle 300; UI_NOEX=
t_eq "a wrong code" 403 "$(ui_code "$UI_URL/?token=nope")"
HDR="$(curl -s -D - -o /dev/null "$UI_URL/?token=$UI_CODE" | tr -d '\r')"
t_has "the first use is a 303" "$HDR" " 303 "
t_has "to the page without the code" "$HDR" "Location: /"
t_has "and sets a cookie JavaScript cannot read" "$HDR" "HttpOnly"
t_has "that is not sent cross-site" "$HDR" "SameSite=Strict"
t_hasnt "the cookie is not the code" "$HDR" "=$UI_CODE;"
t_eq "the second use of the same code is 403" 403 "$(ui_code "$UI_URL/?token=$UI_CODE")"
t_eq "and a third" 403 "$(ui_code "$UI_URL/?token=$UI_CODE")"
UI_TOKEN="$(printf '%s\n' "$HDR" | sed -n 's/^[Ss]et-[Cc]ookie: harbor_ui_[0-9]*=\([0-9a-f]*\);.*/\1/p')"; UI_COOKIE="harbor_ui_$UI_PORT=$UI_TOKEN"
PAGEH="$(curl -s -D - -m 60 -H "Cookie: $UI_COOKIE" "$UI_URL/" | tr -d '\r')"
t_has "the code is in the server's own output, where its owner reads it" "$(cat "$T_TMP/once.out")" "$UI_CODE"
t_has "and the session is in the cookie it set" "$HDR" "$UI_TOKEN"
t_eq "the cookie it set opens the page" 200 "$(ui_code -H "Cookie: $UI_COOKIE" "$UI_URL/")"
t_has "the page is not cached" "$PAGEH" "no-store"
t_has "and sends no Referer" "$PAGEH" "Referrer-Policy: no-referrer"
CSP="$(printf '%s\n' "$PAGEH" | sed -n "s/^[Cc]ontent-[Ss]ecurity-[Pp]olicy: //p" | sed "s/'nonce-[^']*'/'nonce-N'/g")"
t_eq "the CSP is exactly the one written, nothing added" "default-src 'none'; script-src 'nonce-N'; style-src 'nonce-N'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'" "$CSP"
t_has "the page strips anything left in the address bar" "$(ui_get /)" "history.replaceState"
t_hasnt "no page echoes the code back" "$(ui_get /)" "$UI_CODE"
t_hasnt "or the session" "$(ui_get /)" "$UI_TOKEN"
ui_stop

t_section "a command outside the allowlist cannot be run through the server"
ui_start allow --idle 300
before="$(ui_calls floor-verify)"
t_has "a listed panel id runs" "$(ui_post '{"id":"floor"}')" " 200"
t_eq "and that ran its one source" $((before + 1)) "$(ui_calls floor-verify)"
before="$(ui_calls floor-verify)"
for body in '{"id":"rm -rf /"}' '{"id":"sh"}' '{"id":"__proto__"}' '{"id":"constructor"}' '{"id":"*"}' '{"id":7}' '{"cmd":["touch","'"$T_TMP"'/pwned"]}' '{"argv":["touch","'"$T_TMP"'/pwned"],"id":"floor-verify"}' '{}'; do
  R="$(ui_post "$body")"
  t_has "refused with 403: $body" "$R" " 403"
  t_has "and says why: $body" "$R" "not in the allowlist"
done
t_eq "no source ran for any of them" "$before" "$(ui_calls floor-verify)"
t_eq "and nothing the request named was run" no "$([ -e "$T_TMP/pwned" ] && echo yes || echo no)"
# The Obligations tab (harbor#1053) is one allowlisted argv array: the id picks it, and nothing in the request can add to it.
# It is the console's own script, run from its own ROOT (harbor#1113); a PATH-resolved `harbor` is never started.
ob_logger() { printf '#!/bin/sh\nprintf "%%s|" "$@" >> "%s/ob.args"\necho >> "%s/ob.args"\ncat "%s/out.status-obligations"\n' "$T_TMP" "$T_TMP" "$T_TMP" > "$UI_ROOT/bin/status-obligations.sh"; rm -f "$T_TMP/ob.args"; }
ob_logger
R="$(ui_post '{"id":"obligations","argv":["touch","'"$T_TMP"'/pwned"],"cmd":"touch '"$T_TMP"'/pwned"}')"
t_has "the obligations panel runs by its id" "$R" " 200"
t_eq "and ran exactly the script's show --json, the request's argv ignored" "show|--json|" "$(sed -n 1p "$T_TMP/ob.args")"
t_eq "once" 1 "$(wc -l < "$T_TMP/ob.args" | tr -d ' ')"
t_eq "the PATH harbor was never started" 0 "$(ui_calls harbor)"
t_eq "nothing the request named was run" no "$([ -e "$T_TMP/pwned" ] && echo yes || echo no)"
t_has "a body that is not JSON is 400" "$(ui_post 'id=floor')" " 400"
t_has "a form post is 415, never parsed" "$(curl -s -m 20 -w ' %{http_code}' -H "Cookie: $UI_COOKIE" -d 'id=floor' "$UI_URL/run")" " 415"
t_eq "a listed id from a foreign Origin is 403" 403 "$(ui_code -X POST -H "Cookie: $UI_COOKIE" -H 'Origin: http://evil.example' -H 'Content-Type: application/json' -d '{"id":"floor"}' "$UI_URL/run")"
t_eq "GET /run is not a route" 404 "$(ui_code -H "Cookie: $UI_COOKIE" "$UI_URL/run")"
ui_stop

t_section "it stops after the idle timeout"
ui_start idle --idle 1
ui_get / > /dev/null
wait_exit "$UI_PID"
t_eq "the process is gone" no "$(alive "$UI_PID")"
wait "$UI_PID"; t_eq "and left with exit 0" 0 "$?"
t_has "it says so" "$(cat "$T_TMP/idle.out")" "stopped after"
ui_start busy --idle 3
for _i in 1 2 3 4; do sleep 1; ui_code -H "Cookie: $UI_COOKIE" "$UI_URL/healthz" > /dev/null; done
t_eq "an authorised request every second keeps it up past the timeout" yes "$(alive "$UI_PID")"
ui_stop
ui_start refused --idle 2
for _i in 1 2 3 4; do sleep 1; ui_code "$UI_URL/" > /dev/null; done
wait_exit "$UI_PID"
t_eq "a request refused with 403 does not keep it up" no "$(alive "$UI_PID")"

t_section "red proofs: delete each guard from a copy of the server, and the same probe fails"
ui_mutant bind 's/hostname: "127.0.0.1"/hostname: "0.0.0.0"/'
t_eq "the bind mutant differs from the server" changed "$UI_MUT"
ui_start mbind --idle 60
t_eq "bound to the wildcard, the listener probe sees it" yes "$([ "$(ui_listen "$UI_PID" "$UI_PORT")" != 127.0.0.1 ] && echo yes)"; ui_stop
ui_mutant token '/guard:token/d'
t_eq "the token mutant differs" changed "$UI_MUT"
ui_start mtoken --idle 60
t_eq "without the session check a bare request is served" 200 "$(ui_code "$UI_URL/")"; ui_stop
ui_mutant origin '/guard:origin/d'
t_eq "the origin mutant differs" changed "$UI_MUT"
ui_start morigin --idle 60
t_eq "without the Origin check a foreign Origin is served" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Origin: http://evil.example' "$UI_URL/")"; ui_stop
ui_mutant prefix 's|^    if (origin !== null .*guard:origin$|    if (origin !== null \&\& !origin.startsWith("http://127.0.0.1")) return FORBIDDEN(); // guard:origin|'
t_eq "the prefix-match mutant differs" changed "$UI_MUT"
ui_start mprefix --idle 60
t_eq "an Origin that only starts with ours is served by a prefix match" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Origin: http://127.0.0.1.evil.example' "$UI_URL/")"
t_eq "and so is another port" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H "Origin: http://127.0.0.1:$((UI_PORT + 1))" "$UI_URL/")"; ui_stop
ui_mutant host '/guard:host/d'
t_eq "the host mutant differs" changed "$UI_MUT"
ui_start mhost --idle 60
t_eq "without the Host check a foreign Host is served" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Host: evil.example' "$UI_URL/")"; ui_stop
ui_mutant fetchsite '/guard:fetchsite/d'
t_eq "the Sec-Fetch-Site mutant differs" changed "$UI_MUT"
ui_start mfetch --idle 60
t_eq "without it a cross-site fetch is served" 200 "$(ui_code -H "Cookie: $UI_COOKIE" -H 'Sec-Fetch-Site: cross-site' "$UI_URL/")"; ui_stop
ui_mutant once '/guard:once/d'
t_eq "the single-use mutant differs" changed "$UI_MUT"
UI_NOEX=1; ui_start monce --idle 60; UI_NOEX=
ui_code "$UI_URL/?token=$UI_CODE" > /dev/null
t_eq "without the used flag the same code opens the console again" 303 "$(ui_code "$UI_URL/?token=$UI_CODE")"; ui_stop
ui_mutant referrer 's/"referrer-policy": "no-referrer", //'
t_eq "the referrer mutant differs" changed "$UI_MUT"
ui_start mref --idle 60
t_hasnt "without the header the page names no Referrer-Policy" "$(curl -s -D - -o /dev/null -H "Cookie: $UI_COOKIE" "$UI_URL/" | tr -d '\r')" "Referrer-Policy: no-referrer"; ui_stop
ui_mutant csp "s/default-src 'none';/default-src 'none' 'unsafe-inline' *;/"
t_eq "the CSP mutant differs" changed "$UI_MUT"
ui_start mcsp --idle 60
t_has "a loosened CSP is visible to the same probe" "$(curl -s -D - -o /dev/null -H "Cookie: $UI_COOKIE" "$UI_URL/" | tr -d '\r')" "'unsafe-inline' *"; ui_stop
ui_mutant replace '/history.replaceState/d' render.ts
t_eq "the replaceState mutant differs" changed "$UI_MUT"
ui_start mrepl --idle 60
t_hasnt "without it the page leaves the code in the address bar" "$(ui_get /)" "history.replaceState"; ui_stop
ui_mutant dev '/guard:dev/d;/guard:error/d;/guard:host/d;s/try { url = new URL(req.url); } catch { return FORBIDDEN(); }/url = new URL(req.url);/'
t_eq "the error-page mutant differs" changed "$UI_MUT"
ui_start mdev --idle 60
t_has "with the original order and Bun's dev page, a malformed Host leaks the file name" "$(curl -s -m 20 -H "Host: 127.0.0.1:$UI_PORT." -H "Cookie: $UI_COOKIE" "$UI_URL/")" "server.ts"; ui_stop
ui_mutant allow 's/^      const panel = .*guard:allowlist.*$/      const panel = BY_ID.get(String(id)) ?? PANELS[0];/'
t_eq "the allowlist mutant differs" changed "$UI_MUT"
ui_start mallow --idle 60
before="$(ui_calls floor-verify)"; R="$(ui_post '{"id":"rm -rf /"}')"
t_has "without the allowlist check an unlisted id is not refused" "$R" " 200"
t_eq "and a source ran for it" $((before + 1)) "$(ui_calls floor-verify)"; ui_stop
ui_mutant idle 's/if (Date.now() - lastActive < IDLE_MS) return;/if (true) return;/'
t_eq "the idle mutant differs" changed "$UI_MUT"
ui_start midle --idle 1
ui_get / > /dev/null; sleep 4
t_eq "without the idle check it is still up after the timeout" yes "$(alive "$UI_PID")"; ui_stop
ui_mutant argv 's/argv: sh("status-obligations.sh", "show", "--json")/argv: sh("status-obligations.sh", "show")/' sources.ts
t_eq "the obligations argv mutant differs" changed "$UI_MUT"
ui_start margv --idle 60; ob_logger
ui_post '{"id":"obligations"}' > /dev/null
t_eq "with the argv changed, the same probe sees another command" "show|" "$(sed -n 1p "$T_TMP/ob.args")"; ui_stop
ui_mutant pathharbor 's/argv: sh("status-obligations.sh", "show", "--json")/argv: ["harbor", "status", "obligations", "--json"]/' sources.ts
t_eq "the PATH-harbor mutant differs" changed "$UI_MUT"
ui_start mpharbor --idle 60; rm -f "$T_TMP/calls.harbor"
ui_post '{"id":"obligations"}' > /dev/null
t_eq "with the source resolved through PATH the same probe starts harbor" 1 "$(ui_calls harbor)"; ui_stop
UI_SCRIPT=""
t_done
