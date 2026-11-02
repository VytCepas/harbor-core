#!/usr/bin/env sh
# access-browser-flow.sh (harbor#1445): record a flow once, replay it from its file, on a signed-out
# disposable profile; and `harbor chrome` still refuses recording. Offline arms drive a stub CLI; the live
# arm runs the real pinned CLI in headless Chromium when HARBOR_ACCESS_BROWSER_FLOW_LIVE=1.
LIVE="${HARBOR_ACCESS_BROWSER_FLOW_LIVE:-}"   # before t_init clears HARBOR_*
. "$(dirname "$0")/../../lib/core.sh"; t_init
FLOW="$T_ROOT/bin/access-browser-flow.sh"; AGENT="$T_ROOT/bin/access-browser-agent.sh"
FIX="$T_ROOT/tests/access/browser-flow"
unset HARBOR_ACCESS_CHROME HARBOR_CHROME
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"

HAVE_SQLITE=0; ! command -v sqlite3 >/dev/null 2>&1 || HAVE_SQLITE=1
[ "$HAVE_SQLITE" = 1 ] || echo "  SKIP the profile arms: no sqlite3 on PATH"

# The stub CLI: logs every call; `open` makes a Chromium-shaped profile (empty Cookies and Login Data, as
# the real browser does) under its TMPDIR; STUB_SIGNED_IN puts a cookie row in it; STUB_LEAK keeps it after close.
FSTUB="$T_TMP/flowcli"; FCALLS="$T_TMP/flowcalls"; CODE="$T_TMP/code.js"
cat > "$CODE" <<'EOF'
await page.getByRole('textbox', { name: 'Name' }).fill('Ada');
await page.getByRole('button', { name: 'Greet' }).click();
await page.getByRole('checkbox', { name: 'I agree' }).check();
EOF
cat > "$FSTUB" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$FCALLS"
case " \$* " in
  *" open "*|*" open") p="\$TMPDIR/playwright_chromiumdev_profile-stub/Default"; mkdir -p "\$p"
    sqlite3 "\$p/Cookies" 'create table cookies(name text)'
    sqlite3 "\$p/Login Data" 'create table logins(origin text)'
    [ -z "\${STUB_SIGNED_IN:-}" ] || sqlite3 "\$p/Cookies" "insert into cookies values ('sid')" ;;
  *" close "*|*" close") [ -n "\${STUB_LEAK:-}" ] || rm -rf "\$TMPDIR/playwright_chromiumdev_profile-stub" ;;
  *" recording-stop "*|*" recording-stop")
    if [ -n "\${STUB_NOREC:-}" ]; then printf '### Result\nRecording stopped. No actions were recorded.\n'
    else printf '### Result\nRecording stopped. Recorded actions:\n\n%s\n' '\`\`\`js'; cat "\${STUB_CODE_FILE:-$CODE}"; printf '%s\n\n### Page\n' '\`\`\`'; fi ;;
  *" run-code "*) [ -z "\${STUB_RUN_FAIL:-}" ] || { printf '### Error\nTimeoutError: locator.fill: Timeout 5000ms exceeded.\n'; exit 1; } ;;
  *" eval "*) printf '"Hello, Ada"\n' ;;
  *" screenshot "*) for a in "\$@"; do case "\$a" in --filename=*) printf png > "\${a#--filename=}" ;; esac; done ;;
esac
exit 0
EOF
chmod +x "$FSTUB"
OUT="$T_TMP/flowout"; mkdir -p "$OUT"
HARBOR_ACCESS_BROWSER_FLOW_WORKROOT="$T_TMP"; HARBOR_ACCESS_PLAYWRIGHT_CLI="$FSTUB"; export HARBOR_ACCESS_BROWSER_FLOW_WORKROOT HARBOR_ACCESS_PLAYWRIGHT_CLI
STEPS="$FIX/steps.tsv"; URL='http://127.0.0.1:9/fixture.html'
fcalls() { grep -c -- "$1" "$FCALLS" 2>/dev/null || :; }
fr() { : > "$FCALLS"; rc "$@"; }
leftovers() { find "$T_TMP" -maxdepth 1 -name 'hbf.*' | wc -l | tr -d ' '; }

t_section "the refusals reach no browser"
t_eq "--help answers" "exit 0" "$(fr sh "$FLOW" --help)"
t_has "  and shows the verbs" "$(out)" "record <flow.js> <url>"
t_eq "an unknown verb is refused" "exit 1" "$(fr sh "$FLOW" open)"
for u in 'file:///etc/passwd' 'javascript:alert(1)' "http://x/'y" 'https://u:p@host/' 'http://h/a b'; do
  t_eq "record refuses the URL $u" "exit 1" "$(fr sh "$FLOW" record "$OUT/f.js" "$u" "$STEPS")"
done
for v in eval run-code goto cookie-list state-save open; do
  printf '%s\t#x\n' "$v" > "$T_TMP/bad.tsv"
  t_eq "record refuses the step verb $v" "exit 1" "$(fr sh "$FLOW" record "$OUT/f.js" "$URL" "$T_TMP/bad.tsv")"
done
printf 'fill\t#who\n' > "$T_TMP/bad.tsv"
t_eq "a fill with no value is refused" "exit 1" "$(fr sh "$FLOW" record "$OUT/f.js" "$URL" "$T_TMP/bad.tsv")"
t_eq "a missing steps file is refused" "exit 1" "$(fr sh "$FLOW" record "$OUT/f.js" "$URL" "$T_TMP/none.tsv")"
t_eq "an unknown replay option is refused" "exit 1" "$(fr sh "$FLOW" replay "$OUT/f.js" --headed)"
t_eq "no refusal called the CLI" "0" "$(wc -l < "$FCALLS" | tr -d ' ')"
t_eq "and no refusal wrote a flow file" "0" "$(find "$OUT" -type f | wc -l | tr -d ' ')"

if [ "$HAVE_SQLITE" = 1 ]; then
t_section "record, on a profile that holds no cookie and no login"
t_eq "record exits 0" "exit 0" "$(fr sh "$FLOW" record "$OUT/flow.js" "$URL" "$STEPS")"
RECLOG="$(cat "$T_TMP/out")"; RECCALLS="$(cat "$FCALLS")"
t_has "the log says the profile was empty before, and signed out during" "$RECLOG" "no row in any"
t_eq "the CLI was told to record once" "1" "$(printf '%s\n' "$RECCALLS" | grep -c recording-start)"
t_eq "the browser is never headed" "0" "$(printf '%s\n' "$RECCALLS" | grep -c -e '--headed' -e '--persistent' -e '--profile' -e '--extension')"
t_eq "the session is this tool's own, not a harbor chrome one" "yes" "$(printf '%s\n' "$RECCALLS" | grep -q -- '-s=hbflow-' && ! printf '%s\n' "$RECCALLS" | grep -q -- '-s=claude-' && echo yes)"
t_eq "the browser is closed" "yes" "$(printf '%s\n' "$RECCALLS" | grep -q ' close' && echo yes)"
t_eq "stdout is the flow path alone" "$OUT/flow2.js" "$(sh "$FLOW" record "$OUT/flow2.js" "$URL" "$STEPS" 2>/dev/null)"
t_eq "the file opens with the version header" "// access-browser-flow v1" "$(sed -n 1p "$OUT/flow.js")"
t_has "  goes to the recorded URL first" "$(cat "$OUT/flow.js")" "await page.goto('$URL');"
t_has "  carries the recorded locator code" "$(cat "$OUT/flow.js")" "getByRole('textbox', { name: 'Name' }).fill('Ada')"
t_eq "check accepts what record wrote" "exit 0" "$(fr sh "$FLOW" check "$OUT/flow.js")"
t_eq "no work dir is left behind" "0" "$(leftovers)"

t_section "the profile check fails when the profile is not signed out"
rm -f "$OUT/red.js"
t_eq "a cookie row in the profile refuses the record" "exit 1" "$(STUB_SIGNED_IN=1; export STUB_SIGNED_IN; fr sh "$FLOW" record "$OUT/red.js" "$URL" "$STEPS")"
t_has "  naming the row" "$(out)" "Cookies holds 1 rows"
t_eq "  and writes no flow file" "no" "$([ -e "$OUT/red.js" ] && echo yes || echo no)"
t_eq "  and leaves no .tmp beside it" "0" "$(find "$OUT" -name 'red.js*' | wc -l | tr -d ' ')"
t_eq "a profile still on disk after close refuses the record" "exit 1" "$(STUB_LEAK=1; export STUB_LEAK; fr sh "$FLOW" record "$OUT/red.js" "$URL" "$STEPS")"
t_has "  naming the leftover" "$(out)" "after the run"
t_eq "a failed run still removes its work dir" "0" "$(leftovers)"
t_eq "the CLI recording nothing is refused" "exit 1" "$(STUB_NOREC=1; export STUB_NOREC; fr sh "$FLOW" record "$OUT/red.js" "$URL" "$STEPS")"
t_eq "CLI code that is not a locator action is refused" "exit 1" "$(printf "%s\\n" "await page.evaluate(() => fetch('http://x'));" > "$T_TMP/evil.js"; STUB_CODE_FILE="$T_TMP/evil.js"; export STUB_CODE_FILE; fr sh "$FLOW" record "$OUT/red.js" "$URL" "$STEPS")"
t_eq "  and no file is written for it" "no" "$([ -e "$OUT/red.js" ] && echo yes || echo no)"

t_section "replay runs only the file it was given, in a fresh signed-out browser"
t_eq "replay exits 0" "exit 0" "$(fr sh "$FLOW" replay "$OUT/flow.js" --text '#out' --shot "$OUT/end.png")"
t_has "  prints the end-state text on stdout" "$(out)" "Hello, Ada"
t_eq "  saves the screenshot" "png" "$(cat "$OUT/end.png")"
t_eq "  through run-code --filename" "1" "$(fcalls 'run-code --filename=')"
t_eq "  with the profile checked again" "yes" "$(grep -q 'no row in any' "$T_TMP/out" && echo yes)"
t_eq "a failing replay exits 1" "exit 1" "$(STUB_RUN_FAIL=1; export STUB_RUN_FAIL; fr sh "$FLOW" replay "$OUT/flow.js")"
t_has "  and says which locator no longer matches" "$(out)" "TimeoutError: locator.fill"
t_eq "a cookie row in the replay profile refuses it" "exit 1" "$(STUB_SIGNED_IN=1; export STUB_SIGNED_IN; fr sh "$FLOW" replay "$OUT/flow.js")"
fi

t_section "check refuses a file this tool did not write"
G="$OUT/good.js"
cat > "$G" <<EOF
// access-browser-flow v1
async (page) => {
  page.setDefaultTimeout(5000);
  await page.goto('$URL');
  await page.getByRole('button', { name: 'Greet' }).click();
}
EOF
t_eq "the good file passes" "exit 0" "$(fr sh "$FLOW" check "$G")"
bad() { # <label> <sed script over the good file>
  sed "$2" "$G" > "$OUT/bad.js"
  t_eq "$1" "exit 1" "$(fr sh "$FLOW" check "$OUT/bad.js")"
  t_eq "  and replay of it calls no CLI" "0" "$(fr sh "$FLOW" replay "$OUT/bad.js" >/dev/null; wc -l < "$FCALLS" | tr -d ' ')"
}
bad "no header" '1d'
bad "a require" "s|await page.getByRole('button', { name: 'Greet' }).click();|await page.locator(require('fs')).click();|"
bad "a fetch chained on" "s|click();|click(); fetch('http://x');|"
bad "a second goto" "/goto/p"
bad "a goto off http(s)" "s|http://127.0.0.1:9/fixture.html|file:///etc/passwd|"
bad "a bare statement" "s|  await page.getByRole.*|  process.exit(1);|"
bad "code after the closing brace" '$a\
await page.getByRole("button").click();'
bad "no default timeout" '/setDefaultTimeout/d'

t_section "harbor chrome still refuses recording, and the other verbs this tool owns"
for v in recording-start recording-stop tracing-start tracing-stop video-start run-code; do
  t_eq "harbor chrome $v is refused" "exit 1" "$(ag "$v")"
done
t_eq "none of them reached the CLI" "0" "$({ cat "$CALLS" 2>/dev/null || :; } | grep -c -e recording -e tracing -e video -e run-code || :)"
mkdir -p "$T_TMP/pinbin"; printf '#!/bin/sh\nprintf "%%s\\n" "$1" > "%s/pin"\nexit 0\n' "$T_TMP" > "$T_TMP/pinbin/bunx"; chmod +x "$T_TMP/pinbin/bunx"
env -u HARBOR_ACCESS_PLAYWRIGHT_CLI PATH="$T_TMP/pinbin:$PATH" sh "$FLOW" replay "$G" >/dev/null 2>&1 || :
want="$(sed -n "s/^PW_CLI_PIN='\\([^']*\\)'.*/\\1/p" "$AGENT")"
t_eq "the pin this tool runs is the attended channel's" "@playwright/cli@$want" "$(cat "$T_TMP/pin" 2>/dev/null)"

# The live arm: the real pinned CLI, headless Chromium, a local static page. Off by default (it needs bunx, a
# browser and a free port); the lane that built this tool ran it by hand and recorded the evidence on #1445.
if [ "$LIVE" = 1 ]; then
t_section "live: record, replay, red, green on a real headless browser"
unset HARBOR_ACCESS_BROWSER_FLOW_WORKROOT HARBOR_ACCESS_PLAYWRIGHT_CLI
SRVLOG="$T_TMP/srv.log"
python3 -u -m http.server 0 --bind 127.0.0.1 --directory "$FIX" > "$SRVLOG" 2>&1 &
SRV=$!
_i=0; PORT=''
while [ -z "$PORT" ] && [ "$_i" -lt 50 ]; do PORT="$(sed -n 's/.*port \([0-9][0-9]*\).*/\1/p' "$SRVLOG" | head -n 1)"; _i=$((_i + 1)); [ -n "$PORT" ] || sleep 0.1; done
LF="$T_TMP/live-flow.js"
t_eq "a three-step flow records" "exit 0" "$(rc sh "$FLOW" record "$LF" "http://127.0.0.1:$PORT/fixture.html" "$STEPS")"
t_eq "it replays to the same end state" "Hello, Ada" "$(sh "$FLOW" replay "$LF" --text '#out' --shot "$T_TMP/live-end.png" 2>/dev/null)"
t_eq "  and the screenshot is a PNG" "PNG" "$(head -c 4 "$T_TMP/live-end.png" | tail -c 3)"
sed "s/name: 'Name'/name: 'Nombre'/" "$LF" > "$T_TMP/live-red.js"
t_eq "one edited selector fails the replay (red)" "exit 1" "$(rc sh "$FLOW" replay "$T_TMP/live-red.js")"
t_has "  on the locator" "$(out)" "TimeoutError"
t_eq "the original passes again (green)" "exit 0" "$(rc sh "$FLOW" replay "$LF")"
kill "$SRV" 2>/dev/null || :
fi

t_done
