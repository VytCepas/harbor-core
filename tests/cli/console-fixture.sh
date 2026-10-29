# tests/cli/console-fixture.sh — what the console's suites share (harbor#738). Source after t_init; it asserts nothing.
# A fixture tree stands in for the checkout (HARBOR_STATUS_CONSOLE_ROOT), so no panel reads the operator's box.
PANEL_IDS="floor findings register checks guards context memory backlog fleet sessions worktrees prs obligations"
UI_BUN="${UI_BUN:-}"

ui_stub() { # <name> <exit> [stdout-text] — a fixture bin script: counts its calls, prints, exits
  mkdir -p "$UI_ROOT/bin"; printf '%s\n' "${3:-}" > "$T_TMP/out.$1"
  { printf '#!/bin/sh\necho x >> "%s/calls.%s"\n' "$T_TMP" "$1"
    [ -z "${UI_STUB_SLEEP:-}" ] || printf 'sleep %s\n' "$UI_STUB_SLEEP"
    printf 'cat "%s/out.%s"\n' "$T_TMP" "$1"
    [ "$2" = 0 ] || printf 'echo "stub %s: boom" >&2\n' "$1"
    printf 'exit %s\n' "$2"; } > "$UI_ROOT/bin/$1.sh"
}
ui_cmd() { # <name> <exit> [stdout-text] — a PATH command (gh, projects-orchestrator), same shape
  mkdir -p "$T_BIN"; printf '%s' "${3:-}" > "$T_TMP/out.$1"
  { printf '#!/bin/sh\necho x >> "%s/calls.%s"\ncat "%s/out.%s"\n' "$T_TMP" "$1" "$T_TMP" "$1"
    [ "$2" = 0 ] || printf 'echo "stub %s: boom" >&2\n' "$1"
    printf 'exit %s\n' "$2"; } > "$T_BIN/$1"; chmod +x "$T_BIN/$1"
}
ui_calls() { if [ -f "$T_TMP/calls.$1" ]; then wc -l < "$T_TMP/calls.$1" | tr -d ' '; else echo 0; fi; }

# ob_json — `harbor status obligations --json` as contracts/cli.md freezes it (harbor#1053): one new-looking row, one overdue, one old.
# The tab runs `sh $UI_ROOT/bin/status-obligations.sh show --json` (ob_set stands it in), never a PATH `harbor` (harbor#1113): ui_tree plants one as a tripwire.
# Overrides: OB_SOURCES (the sources object), OB_ROWS (the obligations array), OB_PROPOSALS, OB_GEN (generated_ts).
OB_SRC_OK='{"events":{"ok":true,"reason":"","ts":"2026-10-06T01:30:00Z"},"gh":{"ok":true,"reason":"","ts":"2026-10-06T01:30:00Z"}}'
OB_ROWS_3='[{"id":"pr:acme/widgets#7","kind":"pr","subject":"acme/widgets#7","repo":"widgets","owner":"session:s-1","title":"fixture open pr","link":"https://github.com/acme/widgets/pull/7","opened_ts":"2026-10-06T00:30:00Z","deadline_ts":"2026-10-09T00:30:00Z","state":"open","closed_by":"","closed_ts":"","age_s":3600},{"id":"agent:a-2","kind":"agent","subject":"a-2","repo":"gadgets","owner":"agent:a-2","title":"fixture overdue agent","link":"","opened_ts":"2026-10-05T00:30:00Z","deadline_ts":"2026-10-05T04:30:00Z","state":"overdue","closed_by":"","closed_ts":"","age_s":90000},{"id":"intent:old1","kind":"intent","subject":"old1","repo":"widgets","owner":"operator","title":"fixture oldest intent","link":"","opened_ts":"2026-10-01T00:30:00Z","deadline_ts":"","state":"open","closed_by":"","closed_ts":"","age_s":432000}]'
ob_row() { # <id> <title> <link> [subject repo owner kind] — one open row; values are JSON-escaped by the caller
  printf '{"id":"%s","kind":"%s","subject":"%s","repo":"%s","owner":"%s","title":"%s","link":"%s","opened_ts":"2026-10-06T00:30:00Z","deadline_ts":"","state":"open","closed_by":"","closed_ts":"","age_s":100}' "$1" "${7:-pr}" "${4:-s}" "${5:-r}" "${6:-o}" "$2" "$3"
}
ob_set() { ui_stub status-obligations 0 "$(ob_json)"; chmod +x "$UI_ROOT/bin/status-obligations.sh"; }  # the script now prints ob_json with the OB_* variables as they stand
ob_stub_raw() { ui_stub status-obligations "$1" "$2"; chmod +x "$UI_ROOT/bin/status-obligations.sh"; }  # <exit> <stdout-text> — the script, answering with exactly this
ob_stub_file() { ui_stub status-obligations 0 ""; cp "$1" "$T_TMP/out.status-obligations"; chmod +x "$UI_ROOT/bin/status-obligations.sh"; }  # <file> — a big answer, kept out of argv
ob_json() {
  printf '{"generated_ts":"%s","sources":%s,"obligations":%s,"proposals":%s}' "${OB_GEN:-2026-10-06T01:30:00Z}" "${OB_SOURCES:-$OB_SRC_OK}" "${OB_ROWS:-$OB_ROWS_3}" "${OB_PROPOSALS:-[]}"
}

ui_tree() { # <exit> — every source present and exiting <exit>; a good tree passes 0
  UI_ROOT="$T_TMP/root"; rm -rf "$UI_ROOT" "$T_TMP"/calls.* "$T_BIN/gh" "$T_BIN/projects-orchestrator" "$T_BIN/harbor"
  mkdir -p "$UI_ROOT/bin" "$T_BIN" "$CLAUDE_CONFIG_DIR/cache"; rm -f "$CLAUDE_CONFIG_DIR/cache/checks.log"
  for s in floor-verify lint-findings context-budget memory-route admission-observe-report standard-issue-label context-peers worktree status-obligations; do
    ui_stub "$s" "$1" "fixture $s output"; done
  if [ "$1" = 0 ]; then
    ui_stub floor-verify 0 '  ok: a
  ok: b
  WARN: c
floor-verify: 2 ok, 0 failed, 1 warnings'
    ui_stub context-peers 0 '[{"name":"s1","status":"idle","kind":"interactive","tree":"/x","branch":"main"}]'
    mkdir -p "$UI_ROOT/docs/reference"; printf '| `alpha-check` | w | hourly | desktop | r |\n' > "$UI_ROOT/docs/reference/checks.md"
    printf '[check:alpha-check] 2026-10-06T00:00:00Z fixture line\n' > "$CLAUDE_CONFIG_DIR/cache/checks.log"
    ui_cmd gh 0 '[{"number":7,"title":"fixture pr","headRefName":"b","isDraft":false,"updatedAt":"t"}]'
    ui_cmd projects-orchestrator 0 '[{"descriptor":{"name":"proj"},"status":{"branch":"main","dirty":false,"ahead":0,"behind":0,"last_commit":"t"}}]'
    ob_set
    ui_cmd harbor 0 "$(ob_json)"   # the tripwire: the tab must never reach it
  else
    ui_cmd gh "$1" "x"; ui_cmd projects-orchestrator "$1" "x"; ui_cmd harbor "$1" "x"
  fi
  chmod +x "$UI_ROOT"/bin/*.sh
  export HARBOR_STATUS_CONSOLE_ROOT="$UI_ROOT"
}

# ui_start <name> [status-console.sh args…] [— env assignments before the script via UI_ENV] — sets UI_PID UI_PORT UI_TOKEN
ui_start() {
  _n="$1"; shift; _script="${UI_SCRIPT:-$T_ROOT/bin/status-console.sh}"
  # A reused name's last .out still holds a dead server's token= until the background child truncates it; on a loaded
  # runner the wait below read that first and every check got an empty page (#1322's console-panels reds).
  rm -f "$T_TMP/$_n.out" "$T_TMP/$_n.err"
  HARBOR_STATUS_CONSOLE_BUN="$UI_BUN" sh "$_script" --wait 20 "$@" > "$T_TMP/$_n.out" 2> "$T_TMP/$_n.err" &
  UI_PID=$!
  # 60 s, not 10: Bun on a loaded CI runner (P=24) started past 10 s and every check after read an empty page (harbor#738)
  _i=0
  # A server that exited (a refused listen, a crash) ends the wait at once: 60 s per start was 54 min in the sandbox.
  while [ $_i -lt 600 ] && ! grep -q 'token=' "$T_TMP/$_n.out" 2>/dev/null && kill -0 "$UI_PID" 2>/dev/null; do sleep 0.1; _i=$((_i + 1)); done
  _url="$(sed -n 's/^harbor ui: \(http[^ ]*\)$/\1/p' "$T_TMP/$_n.out" | head -1)"
  [ -n "$_url" ] || printf 'console-fixture: ui_start %s printed no URL in 60 s; stderr: %s\n' "$_n" "$(head -c 300 "$T_TMP/$_n.err" 2>/dev/null)" >&2
  UI_CODE="${_url##*token=}"; UI_PORT="$(printf '%s' "$_url" | sed -n 's#^http://127.0.0.1:\([0-9]*\)/.*#\1#p')"
  UI_URL="http://127.0.0.1:$UI_PORT"; UI_TOKEN=""
  # The launch code is good once: swap it for the session cookie, unless the caller wants to spend it itself (UI_NOEX=1).
  [ -n "${UI_NOEX:-}" ] || UI_TOKEN="$(curl -s -D - -o /dev/null "$UI_URL/?token=$UI_CODE" | tr -d '\r' | sed -n "s/^[Ss]et-[Cc]ookie: harbor_ui_[0-9]*=\([0-9a-f]*\);.*/\1/p")"
  UI_COOKIE="harbor_ui_$UI_PORT=$UI_TOKEN"
}
# ui_can_listen — can bun listen on 127.0.0.1 here? The Claude sandbox refuses it (allowLocalBinding off), and then
# every ui_start would only time out. 0 = listens, 1 = refused or no answer in 10 s.
ui_can_listen() {
  printf 'Bun.serve({port:0,hostname:"127.0.0.1",fetch(){return new Response("")}});console.log("up")\n' > "$T_TMP/listen.ts"
  "$UI_BUN" "$T_TMP/listen.ts" > "$T_TMP/listen.out" 2>&1 & _lp=$!
  _i=0; while [ $_i -lt 100 ] && ! grep -q '^up' "$T_TMP/listen.out" 2>/dev/null && kill -0 "$_lp" 2>/dev/null; do sleep 0.1; _i=$((_i + 1)); done
  _lr=1; grep -q '^up' "$T_TMP/listen.out" 2>/dev/null && _lr=0
  kill "$_lp" 2>/dev/null; wait "$_lp" 2>/dev/null; return $_lr
}
# ui_require_listen <what> — skip the suite loudly where loopback is refused; HARBOR_TEST_REQUIRE_BUN=1 (CI) makes that a failure.
ui_require_listen() {
  ui_can_listen && return 0
  if [ "${REQ_BUN:-0}" = 1 ]; then t_fail "bun cannot listen on 127.0.0.1 ($(head -c 200 "$T_TMP/listen.out" 2>/dev/null))"; t_done; fi
  echo "  SKIP $1: bun cannot listen on 127.0.0.1 here (the Claude sandbox refuses it; rerun outside it)"
  t_section "loopback listen refused: the server arms stand down"
  t_eq "HARBOR_TEST_REQUIRE_BUN is off where listening is refused" 0 "${REQ_BUN:-0}"
  t_done
}
ui_stop() { kill "$UI_PID" 2>/dev/null; wait "$UI_PID" 2>/dev/null; return 0; }

ui_code() { # <curl args…> — the HTTP status only
  curl -s -o /dev/null -w '%{http_code}' -m 60 "$@"; }
ui_get() { # <path> <curl args…> — the body, with the session cookie
  _p="$1"; shift; curl -s -m 60 -H "Cookie: $UI_COOKIE" "$@" "$UI_URL$_p"; }
ui_post() { # <json> — POST /run with the session; prints "<body> <status>"
  curl -s -m 60 -w ' %{http_code}' -H "Cookie: $UI_COOKIE" -H 'Content-Type: application/json' -d "$1" "$UI_URL/run"; }
ui_panel() { # <page> <id> — exactly that panel's section. The page is mostly ONE line, so a line range returned every panel (harbor#1113);
  # a text panel's <pre> holds newlines, so they are folded to \001 while the sections are split, then restored.
  printf '%s' "$1" | tr '\n' '\001' | sed 's/<section/\n<section/g; s/<\/section>/<\/section>\n/g' | grep "id=\"p-$2\"" | tr '\001' '\n'; }

ui_listen() { # <pid> <port> — the address the server listens on: 127.0.0.1, or the wildcard it must never be
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -a -p "$1" -iTCP -sTCP:LISTEN 2>/dev/null | awk -v p=":$2" '$0 ~ p { n = $9; sub(p "$", "", n); print n; exit }'
  elif [ -r /proc/net/tcp ]; then
    _hex="$(printf '%04X' "$2")"
    cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk -v h=":$_hex" '$4 == "0A" && index($2, h) { a = $2; sub(h "$", "", a); print (a == "0100007F" ? "127.0.0.1" : a == "00000000" ? "*" : a); exit }'
  fi
}

ui_mutant() { # <name> <sed-script> [file] — a copy of the console with one guard changed; sets UI_SCRIPT, UI_MUT=changed|same
  _m="$T_TMP/mut-$1"; rm -rf "$_m"; mkdir -p "$_m/bin" "$_m/tools"
  cp "$T_ROOT/bin/status-console.sh" "$T_ROOT/bin/library-log.sh" "$_m/bin/"; cp -R "$T_ROOT/tools/ui" "$_m/tools/ui"
  _f="$_m/tools/ui/${3:-server.ts}"
  sed "$2" "$_f" > "$_f.new" && mv "$_f.new" "$_f"
  if diff -rq "$T_ROOT/tools/ui" "$_m/tools/ui" >/dev/null 2>&1; then UI_MUT=same; else UI_MUT=changed; fi
  UI_SCRIPT="$_m/bin/status-console.sh"
}
