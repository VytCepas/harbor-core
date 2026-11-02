#!/usr/bin/env sh
# The session.* reaction handlers (harbor#1043, #1044): notify, save-now, ci-watch, cleanup-report and check each act on
# their own event and state and on nothing else; cleanup-report kills and removes nothing; ci-watch validates the PR link
# before it reaches a command. The handlers run as the dispatcher runs them: `sh <script>` with HARBOR_EVENT in the env.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$T_ROOT/bin"; T="$T_TMP"; ST="$T/state"; REPO="$T/repo"
export HARBOR_STATUS_DIR="$ST"
mkdir -p "$ST/sessions" "$REPO"
cat > "$T_BIN/osascript" <<'STUB'
#!/bin/sh
shift; printf '%s|%s\n' "$1" "$2" >> "$HARBOR_STATUS_DIR/banners"
STUB
chmod +x "$T_BIN/osascript"
ev() { # <kind> <subject> <title> [link] — a bus line as the dispatcher hands it over
  jq -nc --arg k "$1" --arg s "$2" --arg t "$3" --arg l "${4:-}" '{id:"20261010T000000Z-1-abcd",kind:$k,subject:$s,data:({session_id:$s,title:$t}+(if $l == "" then {} else {link:$l} end))}'; }
fire() { HARBOR_EVENT="$1" sh "$B/$2" > "$T/out" 2>&1; RC=$?; }  # <event-line> <handler>
banners() { cat "$ST/banners" 2>/dev/null; }
reset() { rm -f "$ST/banners" "$ST/reactions.log"; }
wait_banner() { n=0; while [ ! -s "$ST/banners" ] && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done; }

t_section "session-notify: a banner for waiting-operator and done, none for anything else"
reset; fire "$(ev session.state abcdef123 waiting-operator)" session-notify.sh
t_eq "exit 0" 0 "$RC"; t_has "waiting-operator: the banner names the state" "$(banners)" "waiting for you"
t_has "...and six characters of the session id" "$(banners)" "session abcdef"
t_hasnt "...and no path" "$(banners)" "/"
t_has "...and a reactions.log line carrying the rule id" "$(cat "$ST/reactions.log")" "[check:event.session-notify]"
reset; fire "$(ev session.state abcdef123 done)" session-notify.sh; t_has "done: a banner" "$(banners)" "done|session abcdef"
for st in idle blocked waiting-agents; do reset; fire "$(ev session.state abcdef123 $st)" session-notify.sh; t_eq "$st: no banner" "" "$(banners)"; done
reset; fire "$(ev pr.opened abcdef123 done)" session-notify.sh; t_eq "another event kind with the same title: no banner" "" "$(banners)"
reset; fire '{"kind":"session.state","subject":"../x","data":{"title":"done"}}' session-notify.sh; t_eq "an unsafe session id: no banner" "" "$(banners)"
reset; fire 'not json' session-notify.sh; t_eq "garbage event: exit 0, no banner" "0:" "$RC:$(banners)"

t_section "session-save-now: records the nudge, acts on session.save-now only"
reset; fire "$(ev session.save-now abcdef123 'ctx 95%')" session-save-now.sh
t_has "a session.save-now event is logged under its rule id" "$(cat "$ST/reactions.log")" "[check:event.session-save-now] abcdef: asked to write the handoff (ctx 95%)"
reset; fire "$(ev session.state abcdef123 done)" session-save-now.sh; t_eq "a session.state event: nothing logged" no "$([ -e "$ST/reactions.log" ] && echo yes || echo no)"
t_eq "it sends no banner" "" "$(banners)"

t_section "session-ci-watch: a detached ci-wait on a validated PR link, then one verdict (harbor#1367)"
cat > "$T/ci-wait.sh" <<'STUB'
printf '%s\n' "$*" > "$HARBOR_STATUS_DIR/ci-wait.args"
echo "acme/widgets#9: stub"; exit "${CW_RC:-0}"
STUB
export HARBOR_SESSION_CI_WAIT="$T/ci-wait.sh"
LINK=https://github.com/acme/widgets/pull/9
reset; rm -f "$ST/ci-wait.args"; fire "$(ev pr.opened abcdef123 '' "$LINK")" session-ci-watch.sh; wait_banner
t_eq "the handler returns at once, exit 0" 0 "$RC"
t_eq "ci-wait was given the PR and the deadline" "acme/widgets#9 --timeout 1800" "$(cat "$ST/ci-wait.args")"
t_has "green (exit 0): the banner says so" "$(banners)" "checks green|PR #9"
t_has "...and the log carries ci-wait's own line" "$(cat "$ST/reactions.log")" "acme/widgets#9: stub"
for c in "1 checks red" "3 still running" "4 checks unreadable"; do
  reset; CW_RC="${c%% *}" fire "$(ev pr.opened abcdef123 '' "$LINK")" session-ci-watch.sh; wait_banner
  t_has "ci-wait exit ${c%% *}: '${c#* }'" "$(banners)" "${c#* }"
done
for bad in 'https://github.com/acme/widgets/pull/9;touch x' 'https://github.com/a;b/c/pull/1' 'https://evil.example/acme/widgets/pull/9' 'https://github.com/acme/widgets/issues/9' 'https://github.com/acme/widgets/pull/'; do
  reset; rm -f "$ST/ci-wait.args"; fire "$(ev pr.opened abcdef123 '' "$bad")" session-ci-watch.sh; sleep 0.3
  t_eq "link '$bad' never reaches ci-wait" no "$([ -e "$ST/ci-wait.args" ] && echo yes || echo no)"
done
reset; rm -f "$ST/ci-wait.args"; fire "$(ev session.state abcdef123 done "$LINK")" session-ci-watch.sh; sleep 0.3
t_eq "a non-pr.opened event is ignored" no "$([ -e "$ST/ci-wait.args" ] && echo yes || echo no)"
HARBOR_SESSION_CI_WAIT="$T/missing" fire "$(ev pr.opened abcdef123 '' "$LINK")" session-ci-watch.sh
t_has "no ci-wait installed: said in the log, exit 0" "$(cat "$ST/reactions.log"):$RC" "not watched"

t_section "session-cleanup-report: lists, and kills and removes nothing"
git -C "$REPO" init -q && git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
git -C "$REPO" checkout -q -b main && printf a > "$REPO/f" && git -C "$REPO" add f && git -C "$REPO" commit -q -m init
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
REPO="$(CDPATH= cd -P -- "$REPO" && pwd -P)"
git -C "$REPO" worktree add -q -b merged-work "$T/wt-merged" && git -C "$REPO" worktree add -q -b live-work "$T/wt-live"
printf b > "$T/wt-live/g" && git -C "$T/wt-live" add g && git -C "$T/wt-live" commit -q -m live
WT="$(CDPATH= cd -P -- "$T/wt-merged" && pwd -P)"
( sh -c 'sleep 300; true' _ "$REPO" >/dev/null 2>&1 & )
sleep 0.5; PIDS="$(ps -axo pid=,ppid=,command= | awk -v d="$REPO" '$2 == 1 && index($0, d) { print $1 }')"
jq -nc --arg c "$REPO" '{state:"done",cwd:$c}' > "$ST/sessions/abcdef123.json"
fire "$(ev session.state abcdef123 done)" session-cleanup-report.sh
R="$(cat "$ST/sessions/abcdef123.cleanup.txt" 2>/dev/null)"
t_has "the report says it is report only" "$R" "report only"
t_has "an orphan (parent init, command names the directory) is listed with its pid" "$R" "pid $(printf '%s' "$PIDS" | head -n 1)"
t_has "a merged, clean linked worktree is listed as stale" "$R" "$WT"
t_hasnt "an unmerged worktree is not" "$R" "wt-live"
t_eq "the orphan is still running" yes "$(for p in $PIDS; do kill -0 "$p" 2>/dev/null && echo yes && break; done)"
t_eq "the stale worktree is still there" yes "$([ -d "$WT" ] && echo yes || echo no)"
for p in $PIDS; do kill "$p" 2>/dev/null; done
rm -f "$ST/sessions/abcdef123.cleanup.txt"; fire "$(ev session.state abcdef123 idle)" session-cleanup-report.sh
t_eq "a non-done state writes no report" no "$([ -e "$ST/sessions/abcdef123.cleanup.txt" ] && echo yes || echo no)"

t_section "session-check: lint verdict for a finished session's changes"
mkdir -p "$REPO/bin"; printf '#!/bin/sh\necho "  VIOLATION [x.y] one"; exit 1\n' > "$REPO/bin/lint-conventions.sh"
git -C "$REPO" add bin && git -C "$REPO" commit -q -m lint
fire "$(ev session.state abcdef123 done)" session-check.sh
t_eq "changes against origin/main and a failing lint: red 1" "red 1" "$(cat "$ST/sessions/abcdef123.check" 2>/dev/null)"
printf '#!/bin/sh\nexit 0\n' > "$REPO/bin/lint-conventions.sh"; fire "$(ev session.state abcdef123 done)" session-check.sh
t_eq "a passing lint: ok" ok "$(cat "$ST/sessions/abcdef123.check" 2>/dev/null)"
rm -f "$ST/sessions/abcdef123.check"; git -C "$REPO" update-ref refs/remotes/origin/main HEAD; fire "$(ev session.state abcdef123 done)" session-check.sh
t_eq "no changed files against origin/main: no verdict" no "$([ -e "$ST/sessions/abcdef123.check" ] && echo yes || echo no)"
git -C "$REPO" reset -q --hard HEAD~1; fire "$(ev session.state abcdef123 waiting-operator)" session-check.sh
t_eq "a state other than done: no verdict" no "$([ -e "$ST/sessions/abcdef123.check" ] && echo yes || echo no)"
t_done
