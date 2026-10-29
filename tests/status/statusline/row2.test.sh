#!/usr/bin/env sh
# L0-5 (harbor#59): the statusline's PLACE row (row 2: identity, repo, branch, PR, ships) and its YOU row
# (row 3 when present, no marker: the operator queue and every alarm, coloured by severity), the width tiers and
# the payload dump; and the CI tokens, which render on BOX (inventory) and YOU (alarms). Four-row layout
# 2026-10-16. `--dash`: under dash.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../hooks/statusline-fixture.sh"
FS="$CFG/cache/fleet-snapshot.json"
r2() { run "$1" | plain | sed -n 2p; }        # <payload> — row 2 (PLACE), stripped
r2raw() { run "$1" | sed -n 2p; }             # <payload> — PLACE with its colour codes
# The fleet tile closes BOX; with no fleet cache it reads `fleet: unknown`, which the fleet suite owns.
nofleet() { sed 's/ │ fleet: unknown$//; s/^fleet: unknown$//'; }
row2at() { runat "{$WS}" | plain | sed -n 2p; }
rowsat() { runat "{$WS}" | plain | nofleet | grep -c .; }          # rows with content, a fleet-only BOX aside
row3at() { runat "{$WS}" | plain | nofleet | grep . | sed -n 3p; }  # YOU when an alarm is live, else BOX
# YOU has no marker: with a payload and a full width, BOX always prints (the fleet tile at least), so YOU is
# row 3 exactly when four rows print.
you() { run "$1" | plain | awk '{ l[NR] = $0 } END { if (NR == 4) print l[3] }'; }  # <payload> — YOU, stripped; empty when absent
youraw() { run "$1" | awk '{ l[NR] = $0 } END { if (NR == 4) print l[3] }'; }
youw() { you "{$WS}"; }
anyrow() { run "{$WS}" | plain; }

t_section "row 2: WHICH terminal this is"
# Asserted as a PREFIX, so no alarm may be live: re-pin rather than loosen to a substring.
pin "$CFG"
t_eq "session_name leads row 2" yes "$(starts "$(r2 '{"session_id":"abc123def","session_name":"harbor-guards",'"$WS"'}')" "harbor-guards │ ")"
t_eq "an unnamed session falls back to a 6-char id stem" yes "$(starts "$(r2 '{"session_id":"9f2c1a7bdead",'"$WS"'}')" "9f2c1a │ ")"
t_eq "an --agent session identifies by agent" yes "$(starts "$(r2 '{"session_id":"9f2c1a7b","agent":{"name":"security-reviewer"},'"$WS"'}')" "@security-reviewer │ ")"
t_eq "session_name outranks agent.name" yes "$(starts "$(r2 '{"session_id":"9f2c1a7b","session_name":"chosen","agent":{"name":"derived"},'"$WS"'}')" "chosen │ ")"
t_eq "with no name, row 2 starts with the dir" yes "$(starts "$(r2 "{$WS}")" "notrepo")"
t_eq "the payload's repo name outranks the directory" yes "$(starts "$(r2 '{"workspace":{"current_dir":"'"$TMP"'/notrepo","repo":{"name":"harbor"}}}')" "harbor")"

t_section "row 2 is PLACE: alarms live on the YOU row, never here (2026-10-16)"
printf '%s\n' '{"permissions":{"deny":["Read(~/.ssh/**)","CHANGED"]}}' > "$CFG/settings.json"
printf '%s\n' 'deliberately-not-the-hash' > "$CFG/.helm-floor-teeth"
printf '%s\n' '[{"status":{"dirty":false},"drift":{"status":"clean","total":0}}]' > "$FS"
P1='{"session_id":"abc123def",'"$WS"'}'
O="$(r2 "$P1")"
t_hasnt "PLACE carries no alarm" "$O" 'PIN DRIFT'
t_eq "PLACE ends with the ships" yes "$(ends "$O" "⛵1")"
t_eq "the alarm is the YOU row" "PIN DRIFT" "$(you "$P1")"
t_eq "YOU sits between PLACE and BOX" "PIN DRIFT" "$(run "$P1" | plain | sed -n 3p)"
t_has "PIN DRIFT is red" "$(youraw "$P1")" "${ESC}[31mPIN DRIFT"
pin "$CFG"
t_eq "a clean box has no YOU row at all" "" "$(you "$P1")"
t_eq "a clean box leads row 2 with the identity" yes "$(starts "$(r2 "$P1")" "abc123 │ ")"

t_section "colour: only yellow and red, and only for what needs attention (2026-10-16)"
printf 'renew 2 runtime1·floor1\n' > "$CFG/.helm-renew"
printf 'judged 2026-08-23T02:23:31Z worst=crit crit=3 warn=9 records=10\n' > "$CFG/.helm-judge"
printf 'props 2\n' > "$CFG/.helm-props"
YRAW="$(youraw "$P1")"
t_has "STALE (built, not running) is red" "$YRAW" "${ESC}[31mSTALE runtime1·floor1"
t_has "JUDGE at crit is red, with no level word" "$YRAW" "${ESC}[31mJUDGE 3"
t_has "a queued proposal is yellow" "$YRAW" "${ESC}[33mprops 2"
case "$(printf '%s' "$YRAW" | plain)" in "STALE"*"props 2") _z=yes ;; *) _z="no: $YRAW" ;; esac
t_eq "a loud YOU row runs from STALE to props" yes "$_z"
PRAW="$(r2raw "$P1")"
t_hasnt "PLACE carries no RED with every alarm live" "$PRAW" "${ESC}[31m"
t_hasnt "PLACE carries no YELLOW with every alarm live" "$PRAW" "${ESC}[33m"
t_has "the ships are grey, like every informational token" "$PRAW" "${ESC}[90m⛵1"
# An approved PR, the branch and a dirty tree are information: plain or dim, never yellow.
t_has "an approved PR renders" "$(r2 '{"pr":{"number":292,"review_state":"approved"},'"$WS"'}')" "#292 approved"
t_eq "and carries no green" 0 "$(r2raw '{"pr":{"number":292,"review_state":"approved"},'"$WS"'}' | grep -c "${ESC}\[32m")"
git init -q "$TMP/repo"
( export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git -C "$TMP/repo" update-ref HEAD "$(git -C "$TMP/repo" commit-tree -m x "$(git -C "$TMP/repo" write-tree)")" )
: > "$TMP/repo/untracked"
t_has "a dirty tree is a dim ~N" "$(r2raw '{"workspace":{"current_dir":"'"$TMP"'/repo"}}')" "${ESC}[2m~1"
t_eq "the branch carries no colour" 0 "$(r2raw '{"workspace":{"current_dir":"'"$TMP"'/repo"}}' | grep -c "${ESC}\[3[2-6]m")"
# session_name is an AI-written title with no bound: capped at 80 (operator, 2026-10-16), whole inside it.
O="$(r2 '{"session_name":"investigating the statusline separator grammar and the FC-2 repair wording across both renderers",'"$WS"'}')"
_lead="${O%% │ *}"
t_eq "the leading name is capped (${#_lead} bytes)" yes "$(yn [ "${#_lead}" -le 82 ])"
t_eq "a truncated name says so with an ellipsis" yes "$(ends "$_lead" "…")"
O="$(r2 '{"session_name":"harbor: incident fix, guard perf, fleet cleanup + statusline",'"$WS"'}')"
t_eq "a 60-character name survives whole" yes "$(starts "$O" "harbor: incident fix, guard perf, fleet cleanup + statusline │ ")"
t_hasnt "a name inside the cap is not truncated" "$O" '…'
O="$(r2 '{"session_name":"harbor-guards",'"$WS"'}')"
t_eq "a SHORT name survives the cap untouched" yes "$(starts "$O" "harbor-guards │ ")"
t_hasnt "a short name gains no ellipsis" "$O" '…'
printf '%s\n' "$DENY1" > "$CFG/settings.json"; rm -f "$CFG/.helm-renew" "$CFG/.helm-judge" "$CFG/.helm-props"; pin "$CFG"

t_section "row 2: the open PR and its review state"
t_has "an approved PR renders" "$(r2 '{"pr":{"number":292,"review_state":"approved"},'"$WS"'}')" "#292 approved"
t_has "changes_requested renders" "$(r2 '{"pr":{"number":292,"review_state":"changes_requested"},'"$WS"'}')" "#292 changes"
t_has "changes_requested is RED" "$(run '{"pr":{"number":292,"review_state":"changes_requested"},'"$WS"'}')" "${ESC}[31m#292 changes"
t_has "pending is dim: information, not an alarm" "$(run '{"pr":{"number":292,"review_state":"pending"},'"$WS"'}')" "${ESC}[2m#292 pending"
t_has "a PR with no review state still renders its number" "$(r2 '{"pr":{"number":292},'"$WS"'}')" "#292"
O="$(r2 '{"pr":{"number":77,"kind":"mr","review_state":"pending"},'"$WS"'}')"
t_has "an MR renders with the ! sigil" "$O" "!77 pending"
t_hasnt "an MR does not render as a GitHub PR" "$O" '#77'
t_hasnt "no PR renders no token" "$(row2)" '#'

t_section "YOU: the JUDGE verdict, WITH AN AGE"
printf '%s\n' 'judged 2026-08-23T02:23:31Z worst=crit crit=1 warn=62 records=96662' > "$CFG/.helm-judge"
O="$(youw)"
t_has "a crit verdict renders with its count" "$O" "JUDGE 1"
t_has "the verdict carries an age" "$O" "JUDGE 1 ·"
# harbor#300: a file newer than the clock must show the verdict with NO age, never a negative one.
touch -t 203601010000 "$CFG/.helm-judge"; O="$(youw)"
t_has "a future-dated judge file still shows the verdict" "$O" "JUDGE 1"
t_hasnt "a future-dated judge file shows no age at all" "$O" "JUDGE 1 ·"
touch "$CFG/.helm-judge"
t_has "a restored (current) judge file gets its age back" "$(youw)" "JUDGE 1 ·"
printf '%s\n' 'judged 2026-08-23T02:23:31Z worst=warn crit=0 warn=62 records=96662' > "$CFG/.helm-judge"
t_has "a warn verdict renders its count, no level word" "$(youw)" "JUDGE 62"
t_hasnt "the word warn is nowhere on the line" "$(anyrow)" "warn"
t_has "a warn verdict is yellow" "$(youraw "{$WS}")" "${ESC}[33mJUDGE 62"
t_hasnt "and never on PLACE" "$(row2)" 'JUDGE'
printf '%s\n' 'judged 2026-08-23T02:23:31Z worst=ok crit=0 warn=0 records=96662' > "$CFG/.helm-judge"
t_hasnt "a clean verdict renders nothing" "$(anyrow)" 'JUDGE'
rm -f "$CFG/.helm-judge"
t_hasnt "an absent judge file renders nothing" "$(anyrow)" 'JUDGE'

t_section "YOU: WATCH, the schedulers this whole board depends on"
printf '%s\n' 'watch 5 5' > "$CFG/.helm-watch"
t_hasnt "all-loaded renders nothing: the steady state is no tile (2026-10-16)" "$(anyrow)" '📡'
t_hasnt "all-loaded raises no alarm" "$(anyrow)" 'WATCH'
printf '%s\n' 'watch 4 5' > "$CFG/.helm-watch"
t_has "a job not loaded raises WATCH n/m on YOU" "$(youw)" "WATCH 4/5"
t_has "WATCH is red: every number on the board may be frozen" "$(youraw "{$WS}")" "${ESC}[31mWATCH 4/5"
t_hasnt "and no tile beside it" "$(anyrow)" '📡'
rm -f "$CFG/.helm-watch"
t_hasnt "an absent watch file renders nothing" "$(anyrow)" 'WATCH'
printf '%s\n' 'watch banana 5' > "$CFG/.helm-watch"
t_hasnt "a malformed watch file renders nothing" "$(anyrow)" 'WATCH'
rm -f "$CFG/.helm-watch"

t_section "YOU: SWEEP when it is due (the 🧹 count left the line 2026-10-16)"
# housekeeping-clean.sh --record writes it; `due` is the writer's policy and is rendered, never re-derived.
_now="$(date +%s)"
sw() { printf 'sweep items=%s risk=%s decide=0 reclaim=0 bytes=0 keep=0 unread=%s due=%s at=%s\n' "$1" "$2" "$3" "$4" "$5" > "$CFG/.helm-sweep"; }
nosweep() { t_hasnt "$1 (no 🧹)" "$2" '🧹'; t_hasnt "$1 (no SWEEP)" "$2" 'SWEEP'; }  # <label> <rows>
sw 0 0 0 0 "$((_now - 3600))"; nosweep "a clean sweep renders nothing" "$(anyrow)"
sw 4 0 0 0 "$((_now - 3600))"; nosweep "a count that is not due renders nothing" "$(anyrow)"
sw 12 1 0 1 "$((_now - 7200))"
t_eq "a due sweep is SWEEP 12 ·2h on YOU" yes "$(ends "$(youw)" "SWEEP 12 ·2h")"
t_has "SWEEP is yellow: waiting, not broken" "$(youraw "{$WS}")" "${ESC}[33mSWEEP 12"
t_hasnt "no 🧹 tile beside the alarm" "$(anyrow)" '🧹'
sw 12 1 2 1 "$((_now - 7200))"
t_eq "unread repos mark the count a lower bound: SWEEP 12? ·2h" yes "$(ends "$(youw)" "SWEEP 12? ·2h")"
sw 4 0 2 0 "$((_now - 3600))"; nosweep "an unread repo with nothing due renders nothing" "$(anyrow)"
printf 'sweep items=banana due=1 at=%s\n' "$_now" > "$CFG/.helm-sweep"; nosweep "a malformed sweep file renders nothing" "$(anyrow)"
printf 'sweep items=3 due=1\n' > "$CFG/.helm-sweep"; nosweep "a sweep line without unread/at renders nothing" "$(anyrow)"
rm -f "$CFG/.helm-sweep"; nosweep "an absent sweep file renders nothing" "$(anyrow)"

t_section "YOU: OVERDUE when a ledger row is past its deadline (harbor#1050; the ⧗ count left the line 2026-10-16)"
# status-obligations.sh writes the cache with epochs; the age is counted here, at print time. surface.test.sh holds the red-proofs.
ob() { printf '{"at":%s,"live":%s,"overdue":%s,"overdue_since":%s,"unread":%s}\n' "$1" "$2" "$3" "$4" "$5" > "$CFG/cache/status-obligations.json"; }
noob() { t_hasnt "$1 (no ⧗)" "$2" '⧗'; t_hasnt "$1 (no OVERDUE)" "$2" 'OVERDUE'; }  # <label> <rows>
rm -f "$CFG/cache/status-obligations.json"; noob "an absent cache renders nothing" "$(anyrow)"
ob "$_now" 0 0 0 false; noob "nothing open renders nothing" "$(anyrow)"
ob "$_now" 3 0 0 false; noob "three open rows, none overdue, render nothing" "$(anyrow)"
ob "$_now" 5 2 "$((_now - 3 * 86400))" false
t_eq "an overdue row is OVERDUE 2 ·3d on YOU" "OVERDUE 2 ·3d" "$(youw)"
t_has "OVERDUE is yellow" "$(youraw "{$WS}")" "${ESC}[33mOVERDUE 2"
ob "$((_now - 901))" 5 2 "$((_now - 86400))" false; noob "a cache over 900s old claims nothing" "$(anyrow)"
ob "$_now" 5 0 0 true; noob "a failed source with nothing overdue renders nothing" "$(anyrow)"
printf 'not json\n' > "$CFG/cache/status-obligations.json"; noob "a malformed cache renders nothing" "$(anyrow)"

t_section "YOU: the operator queue — handoffs and approvals from the ledger, never PRs (2026-10-16)"
oq() { printf '{"at":%s,"live":3,"overdue":0,"overdue_since":0,"unread":false,"you":%s}\n' "$1" "$2" > "$CFG/cache/status-obligations.json"; }
oq "$_now" '[{"k":"pr","o":false,"t":"harbor#1263"},{"k":"pr","o":false,"t":"zorbcorp#113"},{"k":"intent","o":false,"t":"run cleanup.sh --apply"},{"k":"approval","o":false,"t":"deploy harbor main"}]'
t_eq "handoffs, then approvals; the PRs in the cache are not shown" "run cleanup.sh --apply │ approve deploy harbor main" "$(youw)"
t_has "a waiting handoff is yellow" "$(youraw "{$WS}")" "${ESC}[33mrun cleanup.sh"
oq "$_now" '[{"k":"intent","o":true,"t":"late one"}]'
t_has "an overdue item is red" "$(youraw "{$WS}")" "${ESC}[31mlate one"
oq "$_now" '[{"k":"pr","o":false,"t":"a#1"},{"k":"pr","o":false,"t":"b#2"},{"k":"pr","o":false,"t":"c#3"},{"k":"pr","o":false,"t":"d#4"},{"k":"pr","o":false,"t":"e#5"}]'
t_eq "PRs alone raise no YOU row: several agents, several PRs (2026-10-16)" "" "$(youw)"
oq "$_now" '[{"k":"intent","o":false,"t":"x\u001b[31mPAINTED\u0007"}]'
O="$(youraw "{$WS}")"
t_has "control: the cache title does carry the escape sequence" "$(jq -r '.you[0].t' "$CFG/cache/status-obligations.json")" "${ESC}[31mPAINTED"
t_hasnt "a control character in a title never reaches the terminal" "$O" "${ESC}[31mPAINTED"
t_has "the text around it survives" "$(youw)" "x[31mPAINTED"
oq "$_now" '[{"k":"intent","o":false,"t":"Ask Claude Primary Owner: Team or Enterprise? + one single-day spend export"},{"k":"intent","o":false,"t":"exactly forty columns of handoff title k"}]'
t_eq "a title over 40 columns is cut to 39 and an ellipsis; one of exactly 40 is whole" \
  "Ask Claude Primary Owner: Team or Enter… │ exactly forty columns of handoff title k" "$(youw)"
oq "$((_now - 901))" '[{"k":"pr","o":false,"t":"harbor#1263"}]'
t_eq "a stale cache claims no queue" "" "$(youw)"
oq "$_now" '"not a list"'
t_eq "a malformed queue renders nothing" "" "$(youw)"
oq "$_now" '[{"k":"intent","o":false,"t":"set the feed"}]'
printf 'judged 2026-08-23T02:23:31Z worst=crit crit=1 warn=0 records=1\n' > "$CFG/.helm-judge"
case "$(youw)" in "set the feed │ JUDGE 1"*) _z=yes ;; *) _z="no: $(youw)" ;; esac
t_eq "the queue leads, alarms follow" yes "$_z"
rm -f "$CFG/.helm-judge" "$CFG/cache/status-obligations.json" "$FS"

t_section "row 3: the ⏳ CI tile: jobs left, and time left computed at PRINT time"
# ci-queue.sh stores each repo's expected finish as an EPOCH (harbor#657); the clock is frozen here.
ciq() { printf '%s\n' "$1" > "$CFG/cache/ci-queue.json"; }
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/r","runners":4,"left":0,"eta":null}]}'
t_eq "idle runners render nothing: no row 3" 2 "$(rowsat)"
ciq '{"at":'"$((NOW - 60))"',"repos":[{"repo":"o/r","runners":4,"left":3,"eta":'"$((NOW + 800))"'}]}'
t_has "800s left rounds UP to 14m" "$(row3at)" "⏳3 ·~14m"
O="$(printf '%s' "{$WS}" | CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$((NOW + 240))" \
  "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | sed -n 3p)"
t_has "the same cache 240s later counts down" "$O" "⏳3 ·~10m"
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/a","runners":4,"left":2,"eta":'"$((NOW + 300))"'},{"repo":"o/b","runners":1,"left":1,"eta":'"$((NOW + 3900))"'}]}'
t_has "two repos add up and the later finish wins" "$(row3at)" "⏳3 ·~1h5m"
ciq '{"at":'"$((NOW - 200))"',"repos":[{"repo":"o/r","runners":4,"left":1,"eta":'"$((NOW - 30))"'}]}'
t_has "a job past its finish is due, never negative" "$(row3at)" "⏳1 ·due"
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/a","runners":4,"left":2,"eta":'"$((NOW + 120))"'},{"repo":"o/b","runners":1,"unread":true}]}'
t_has "an unread repo marks the tile a lower bound" "$(row3at)" "⏳2 ·~2m?"
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/b","runners":1,"unread":true}]}'
t_has "nothing read renders ⏳0?, not nothing" "$(row3at)" "⏳0?"
ciq '{"at":'"$((NOW - 1000))"',"repos":[{"repo":"o/r","runners":4,"left":3,"eta":'"$((NOW + 800))"'}]}'
O="$(row3at)"
t_has "a cache older than 900s keeps the count, marked" "$O" "⏳3?"
t_hasnt "a stale cache prints no time at all" "$O" '⏳3 ·'
ciq 'banana'
t_eq "a malformed CI cache renders nothing: no row 3" 2 "$(rowsat)"
rm -f "$CFG/cache/ci-queue.json"
t_eq "an absent CI cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "row 3: CI STALL is an alarm, and only from a fresh cache (harbor#152)"
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/r","runners":4,"left":1,"eta":'"$((NOW + 600))"',"stall":true}]}'
t_has "a stalled repo in a fresh cache raises CI STALL" "$(row3at)" "CI STALL"
O="$(printf '%s' "{$WS}" | HARBOR_GLYPH_COLS=60 CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" \
  "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | sed -n 3p)"
t_has "CI STALL survives the narrow tier, which drops the CI ambient" "$O" "CI STALL"
ciq '{"at":'"$((NOW - 1000))"',"repos":[{"repo":"o/r","runners":4,"left":1,"eta":'"$((NOW + 600))"',"stall":true}]}'
t_hasnt "a stall read from a cache over 900s old is not claimed" "$(row3at)" 'CI STALL'
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/r","runners":4,"left":1,"eta":'"$((NOW + 600))"',"stall":false,"suspect_since":'"$NOW"'}]}'
t_hasnt "a SUSPECT is not a stall" "$(row3at)" 'CI STALL'
rm -f "$CFG/cache/ci-queue.json"

t_section "row 3: MAIN RED is an alarm from a fresh cache, and a stale one says main? (harbor#586)"
mtv() { printf '%s\n' "$1" > "$CFG/cache/main-tip-verdict.json"; }
mtv '{"at":'"$NOW"',"tip":{"sha":"abc","verdict":"failed","at":'"$((NOW - 10800))"',"red":true}}'
t_has "a red tip in a fresh cache raises MAIN RED with its age" "$(row3at)" "MAIN RED 3h"
mtv '{"at":'"$NOW"',"tip":{"sha":"abc","verdict":"green","at":'"$((NOW - 10800))"',"red":false}}'
t_eq "a green tip raises nothing: no row 3" 2 "$(rowsat)"
mtv '{"at":'"$((NOW - 1000))"',"tip":{"sha":"abc","verdict":"failed","at":'"$((NOW - 10800))"',"red":true}}'
O="$(row3at)"
t_hasnt "a red tip read from a cache over 900s old is not claimed" "$O" 'MAIN RED'
t_has "…it says main? instead" "$O" 'main?'
mtv '{"at":'"$NOW"',"unread":true,"tip":{"sha":"abc","verdict":"green","at":'"$((NOW - 60))"',"red":false}}'
t_has "a cache whose last read failed says main?, never green" "$(row3at)" 'main?'
mtv '{"at":'"$NOW"',"unread":false,"repos":[{"repo":"o/blorp","tip":{"red":true,"at":'"$((NOW - 10800))"'}},{"repo":"o/ok","tip":{"red":false,"at":'"$NOW"'}}]}'
t_has "fleet cache: one red repo is named with its age" "$(row3at)" "MAIN RED blorp 3h"
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/blorp","tip":{"red":true,"at":'"$((NOW - 10800))"'}},{"repo":"o/labkit","tip":{"red":true,"at":'"$((NOW - 86400))"'}}]}'
t_has "two red repos are listed oldest first" "$(row3at)" "MAIN RED labkit 24h, blorp 3h"
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/a","tip":{"red":true,"at":'"$((NOW - 600))"'}},{"repo":"o/b","tip":{"red":true,"at":'"$((NOW - 7200))"'}},{"repo":"o/c","tip":{"red":true,"at":'"$((NOW - 400000))"'}}]}'
t_has "more than two are counted, with the oldest age" "$(row3at)" "MAIN RED 3 repos, oldest 4d"
mtv '{"at":'"$NOW"',"unread":true,"repos":[{"repo":"o/blorp","tip":{"red":true,"at":'"$((NOW - 10800))"'}},{"repo":"o/gone","unread":true,"state":"unread"}]}'
t_has "a red repo that was read is still said when another repo is unread" "$(row3at)" "MAIN RED blorp 3h"
mtv '{"at":'"$NOW"',"unread":true,"repos":[{"repo":"o/ok","tip":{"red":false,"at":'"$NOW"'}},{"repo":"o/gone","unread":true,"state":"unread"}]}'
t_has "an unread repo and nothing red says main?" "$(row3at)" "main?"
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/tagscope","tip":{"red":true,"single":true,"at":'"$((NOW - 86400))"',"red_at":'"$((NOW - 600))"'}}]}'
t_has "a red tip's age counts from the failing run (red_at), not the commit" "$(row3at)" "MAIN RED tagscope 10m ·1 run"
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/blorp","tip":{"red":true,"single":false,"at":'"$((NOW - 10800))"'}}]}'
t_hasnt "a red tip that is not a single run carries no ·1 run" "$(row3at)" '·1 run'
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/idea-to-live","tip":{"red":false,"verdict":"green","at":'"$NOW"',"sched":["Scheduled readings"]}}]}'
O="$(row3at)"
t_has "a failing scheduled workflow beside a green tip is SCHED, named by repo" "$O" "SCHED idea-to-live"
t_hasnt "…and is not MAIN RED" "$O" 'MAIN RED'
mtv '{"at":'"$NOW"',"repos":[{"repo":"o/off","state":"disabled","tip":{"red":false,"at":'"$NOW"'}}]}'
t_eq "a disabled repo raises nothing: no row 3" 2 "$(rowsat)"
rm -f "$CFG/cache/main-tip-verdict.json"
t_eq "an absent cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "row 3: CI→local shows the fallback, and only the fallback (harbor#865)"
rsw() { printf '%s\n' "$1" > "$CFG/cache/runner-switch.json"; }
rsw '{"at":'"$NOW"',"runner":"self-hosted","fallback":true,"percent":93,"unread":false}'
t_has "a fresh fallback cache shows CI→local with the percentage" "$(row3at)" "CI→local 93%"
rsw '{"at":'"$NOW"',"runner":"github-hosted","fallback":false,"percent":12,"unread":false}'
t_eq "control: github-hosted, the normal state, renders nothing: no row 3" 2 "$(rowsat)"
rsw '{"at":'"$((NOW - 1000))"',"runner":"self-hosted","fallback":true,"percent":93,"unread":false}'
O="$(row3at)"
t_hasnt "a fallback read from a cache over 900s old is not claimed" "$O" 'CI→local'
t_has "...it says CI? instead" "$O" 'CI?'
rsw '{"at":'"$NOW"',"runner":"github-hosted","fallback":false,"percent":12,"unread":true}'
t_has "a cache whose last read failed says CI?, never a calm state" "$(row3at)" 'CI?'
rm -f "$CFG/cache/runner-switch.json"
t_eq "an absent cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "row 3: CI⇣ shows a CI core budget held under its target (bin/ci-governor.sh)"
gvc() { printf '%s\n' "$1" > "$CFG/cache/ci-governor.json"; }
sh -c 'exit 0' & GONE=$!; wait "$GONE"
gvc '{"at":'"$((NOW - 86400))"',"listener_pid":'"$$"',"budget":2,"target":8,"held":true}'
t_has "a live listener's cache held under its target shows CI⇣ budget/target, however old" "$(row3at)" "CI⇣2/8"
gvc '{"at":'"$NOW"',"listener_pid":'"$$"',"budget":4,"target":4,"held":false}'
t_eq "control: at its target it renders nothing: no row 3" 2 "$(rowsat)"
gvc '{"at":'"$NOW"',"listener_pid":'"$GONE"',"budget":2,"target":8,"held":true}'
O="$(row3at)"
t_hasnt "a listener whose pid is gone is not claimed" "$O" 'CI⇣'
t_has "...it says gov? instead" "$O" 'gov?'
gvc '{"at":'"$NOW"',"budget":2,"target":8,"held":true}'
t_has "no listener recorded at all is gov? too" "$(row3at)" 'gov?'
gvc '{"at":'"$NOW"',"listener_pid":'"$$"',"budget":2,"target":4,"held":true,"emergency":true}'
O="$(row3at)"
t_eq "an emergency is an ALARM, rightmost on row 3" yes "$(ends "$O" "CI EMERG")"
t_hasnt "...in place of the CI⇣ inventory token" "$O" 'CI⇣'
rm -f "$CFG/cache/ci-governor.json"
t_eq "an absent cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "row 3: PLAN and GATE alarm until a person acknowledges the new state (bin/ci-github-plan.sh, harbor#1060)"
ghp() { printf '%s\n' "$1" > "$CFG/cache/gh-plan.json"; }
ghp '{"at":'"$NOW"',"plan":"free","gate":"local","ack":{"plan":"pro","gate":"github"},"alarm":true,"unread":false}'
O="$(row3at)"
t_eq "Pro -> Free is an ALARM, rightmost on row 3" yes "$(ends "$O" "GATE local")"
t_has "...naming the move" "$O" "PLAN pro→free"
t_hasnt "...and never on row 2" "$(row2at)" "PLAN pro"
ghp '{"at":'"$NOW"',"plan":"free","gate":"local","ack":{"plan":"free","gate":"local"},"alarm":false,"unread":false}'
t_eq "control: acknowledged, it renders nothing: no row 3" 2 "$(rowsat)"
ghp '{"at":'"$((NOW - 1000))"',"plan":"free","gate":"local","ack":{"plan":"pro","gate":"github"},"alarm":true,"unread":false}'
O="$(row3at)"
t_hasnt "a cache over 900s old is not claimed" "$O" "PLAN"
t_has "...it says plan? instead" "$O" "plan?"
ghp '{"at":'"$NOW"',"plan":"pro","gate":"github","ack":{"plan":"pro","gate":"github"},"alarm":false,"unread":true}'
t_has "a failed read says plan?, never a calm state" "$(row3at)" "plan?"
rm -f "$CFG/cache/gh-plan.json"
t_eq "an absent cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "row 3: DOCKER DOWN, RUNNER DOWN and CI NO RUNNER (bin/ci-runners.sh tick, harbor#1060)"
cra() { printf '%s\n' "$1" > "$CFG/cache/ci-runner-alarm.json"; }
cra '{"at":'"$NOW"',"unread":false,"docker_down":true,"offline":["a-linux","harbor-linux"],"stuck":{"jobs":3,"oldest":'"$((NOW - 1500))"',"repos":["a"]}}'
O="$(row3at)"
t_has "a dead docker is an alarm" "$O" "DOCKER DOWN"
t_has "...offline runners are counted" "$O" "RUNNER DOWN 2"
t_eq "...and jobs no runner can take, with their wait counted from the oldest, are rightmost" yes "$(ends "$O" "CI NO RUNNER 3 ·25m")"
t_hasnt "...and none of it is on row 2" "$(row2at)" "DOWN"
cra '{"at":'"$NOW"',"unread":false,"docker_down":false,"offline":[],"wedged":["exampleorg-linux"],"stuck":{"jobs":0,"oldest":null,"repos":[]}}'
O="$(row3at)"
t_has "a runner busy on a dead job is an alarm, counted (harbor#1060, 2026-10-13)" "$O" "RUNNER WEDGED 1"
t_hasnt "...and is not called down" "$O" "RUNNER DOWN"
cra '{"at":'"$NOW"',"unread":false,"docker_down":false,"offline":[],"stuck":{"jobs":0,"oldest":null,"repos":[]}}'
t_eq "control: a clean cache renders nothing: no row 3" 2 "$(rowsat)"
cra '{"at":'"$((NOW - 1000))"',"unread":false,"docker_down":true,"offline":[],"stuck":{"jobs":0}}'
O="$(row3at)"
t_hasnt "an outage read from a cache over 900s old is not claimed" "$O" "DOCKER DOWN"
t_has "...it says runners? instead" "$O" "runners?"
cra '{"at":'"$NOW"',"unread":true,"docker_down":false,"offline":[],"stuck":{"jobs":0}}'
t_has "GitHub not answering says runners?" "$(row3at)" "runners?"
rm -f "$CFG/cache/ci-runner-alarm.json"
t_eq "an absent cache renders nothing: no row 3" 2 "$(rowsat)"

t_section "CI: inventory on BOX in grey, alarms on YOU by severity, none on PLACE"
# All four caches at once (harbor#1032, operator request 2026-10-05); the machine row is off in this suite.
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/r","runners":4,"left":3,"eta":'"$((NOW + 800))"'}]}'
mtv '{"at":'"$((NOW - 1000))"',"tip":{"sha":"abc","verdict":"green","at":'"$((NOW - 60))"',"red":false}}'
rsw '{"at":'"$NOW"',"runner":"self-hosted","fallback":true,"percent":100,"unread":false}'
gvc '{"at":'"$NOW"',"listener_pid":'"$$"',"budget":2,"target":8,"held":true}'
r3narrow() { printf '%s' "{$WS}" | HARBOR_GLYPH_COLS=60 CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" \
  "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain; }
t_eq "ambient CI, golden BOX" "⏳3 ·~14m │ main? │ CI→local 100% │ CI⇣2/8" "$(row3at)"
O="$(row2at)"
t_eq "PLACE carries no ambient CI token" 0 "$(printf '%s\n' "$O" | grep -cE '⏳|main\?|CI→|CI⇣|CI\?|gov\?')"
t_hasnt "the old CI→mac spelling is gone everywhere" "$(runat "{$WS}" | plain)" 'CI→mac'
RAW="$(runat "{$WS}" | sed -n 3p)"
t_has "BOX CI is dark grey" "$RAW" "${ESC}[90m⏳3"
t_hasnt "BOX CI carries no red" "$RAW" "${ESC}[31m"
t_hasnt "BOX CI carries no yellow" "$RAW" "${ESC}[33m"
t_eq "the narrow tier drops ambient CI: BOX is gone, two rows remain" 2 "$(r3narrow | wc -l | tr -d ' ')"
ciq '{"at":'"$NOW"',"repos":[{"repo":"o/r","runners":4,"left":1,"eta":'"$((NOW + 600))"',"stall":true}]}'
mtv '{"at":'"$NOW"',"tip":{"sha":"abc","verdict":"failed","at":'"$((NOW - 10800))"',"red":true}}'
gvc '{"at":'"$NOW"',"listener_pid":'"$$"',"budget":2,"target":4,"held":true,"emergency":true}'
t_eq "the alarms are the YOU row, golden" "CI STALL │ MAIN RED 3h │ CI EMERG" "$(row3at)"
t_eq "and the inventory stays on BOX" "⏳1 ·~10m │ CI→local 100%" "$(runat "{$WS}" | plain | tail -1 | nofleet)"
O="$(row2at)"
t_eq "PLACE carries no CI alarm" 0 "$(printf '%s\n' "$O" | grep -cE 'CI STALL|MAIN RED|CI EMERG')"
t_has "MAIN RED is red" "$(runat "{$WS}" | sed -n 3p)" "${ESC}[31mMAIN RED 3h"
t_has "CI STALL is red" "$(runat "{$WS}" | sed -n 3p)" "${ESC}[31mCI STALL"
t_eq "the narrow tier keeps the YOU row whole" "CI STALL │ MAIN RED 3h │ CI EMERG" "$(r3narrow | sed -n 3p)"
rm -f "$CFG/cache/ci-queue.json" "$CFG/cache/main-tip-verdict.json" "$CFG/cache/runner-switch.json" "$CFG/cache/ci-governor.json"
t_eq "no CI token and no machine: two rows with content" 2 "$(rowsat)"
t_eq "and no blank line anywhere" "$(runat "{$WS}" | wc -l | tr -d " ")" "$(runat "{$WS}" | grep -c .)"

t_section "YOU: SHARED TREE is an alarm, not inventory"
# here > 1 is the condition under which uncommitted work has been lost on this box.
mkdir -p "$CFG/.helm-peers"
printf 'tree=%s\nsrc=launch\npid=%s\n' "$TMP/notrepo" "$$" > "$CFG/.helm-peers/peer-a"
t_hasnt "a plain folder is not a shared tree: each session works in its own worktree" "$(run '{"session_id":"mine",'"$WS"'}')" 'SHARED TREE'
git init -q "$TMP/arepo"; RT="$(git -C "$TMP/arepo" rev-parse --show-toplevel)"
printf 'tree=%s\nsrc=launch\npid=%s\n' "$RT" "$$" > "$CFG/.helm-peers/peer-a"
WS='"workspace":{"current_dir":"'"$TMP"'/arepo"}'
t_has "a peer in this tree raises an alarm" "$(you '{"session_id":"mine",'"$WS"'}')" "SHARED TREE 2"
t_has "SHARED TREE is red" "$(youraw '{"session_id":"mine",'"$WS"'}')" "${ESC}[31mSHARED TREE 2"
O="$(printf '%s' '{"session_id":"mine",'"$WS"'}' | HARBOR_GLYPH_COLS=60 CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" \
  "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain | sed -n 3p)"
t_has "SHARED TREE survives the narrow tier, which drops inventory" "$O" "SHARED TREE 2"
printf 'tree=%s\nsrc=launch\npid=%s\n' "/somewhere/else" "$$" > "$CFG/.helm-peers/peer-a"
t_hasnt "a peer in another tree raises no alarm" "$(run '{"session_id":"mine",'"$WS"'}')" 'SHARED TREE'
printf 'tree=%s\nsrc=write\npid=%s\n' "$RT" "2147483646" > "$CFG/.helm-peers/peer-a"
t_hasnt "a dead pid is not a peer" "$(run '{"session_id":"mine",'"$WS"'}')" 'SHARED TREE'
rm -rf "$CFG/.helm-peers"; WS='"workspace":{"current_dir":"'"$TMP"'/notrepo"}'  # the fixture's own value again

t_section "the ships count comes from the REGISTRY, which sees idle sessions"
# Two pids this suite owns: `kill -0` on another user's process is EPERM and reads as dead.
mkdir -p "$CFG/sessions"
printf '%s\n' '{"pid":'"$$"',"status":"busy"}' > "$CFG/sessions/$$.json"
printf '%s\n' '{"pid":'"$PPID"',"status":"idle"}' > "$CFG/sessions/$PPID.json"
O="$(row2)"
t_has "two live registry entries count 2 ships" "$O" "⛵2"
t_has "the busy split renders" "$O" "·1 busy"
# Registry status is PEER-SUPPLIED, so it is counted, never echoed.
printf '%s\n' '{"pid":'"$PPID"',"status":"idle\u001b[31mINJECTED"}' > "$CFG/sessions/$PPID.json"
O="$(row2)"
t_hasnt "a peer-supplied status never reaches the row" "$O" 'INJECTED'
t_has "a hostile status still counts as one ship" "$O" "⛵2"
printf '%s\n' '{"pid":'"$PPID"',"status":"idle"}' > "$CFG/sessions/$PPID.json"
printf '%s\n' '{"pid":2147483646,"status":"busy"}' > "$CFG/sessions/2147483646.json"
t_has "a dead registry entry is not counted" "$(row2)" "⛵2"
rm -rf "$CFG/sessions"; O="$(row2)"
t_has "an absent registry degrades to 1" "$O" "⛵1"
t_hasnt "a session never reports zero sessions" "$O" '⛵0'

t_section "width tiers: COLUMNS is the only readable width, and 0 means unknown"
printf '%s\n' '[{"status":{"dirty":true},"drift":{"status":"clean","total":0}}]' > "$FS"
printf '%s\n' 'watch 5 5' > "$CFG/.helm-watch"
tier() { printf '%s' "$2" | CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_GLYPH_COLS="$1" "$SH" "$SRC/status-fleet-glyph.sh" 2>/dev/null | plain; }
PL='{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":30,"current_usage":{"input_tokens":10,"cache_read_input_tokens":90,"cache_creation_input_tokens":0}},"rate_limits":{"five_hour":{"used_percentage":5},"seven_day":{"used_percentage":9}},'"$WS"'}'
t_has "an UNKNOWN width takes the full render" "$(tier 0 "$PL")" "cache 90%"
O="$(tier 200 "$PL")"
t_has "a wide terminal takes the full render" "$O" "cache 90%"
t_has "the full tier keeps the sub-counts" "$O" "·1 dirty"
t_hasnt "no tier renders a healthy watch tile" "$O" "📡"
O="$(tier 110 "$PL")"
t_hasnt "the wide tier drops the cache share" "$O" 'cache'
t_has "the wide tier keeps the ships" "$O" "⛵1"
t_has "the wide tier keeps the sub-counts" "$O" "·1 dirty"
O="$(tier 90 "$PL")"
t_hasnt "the mid tier drops the sub-counts" "$O" '·1 dirty'
t_has "the mid tier keeps the anchor count" "$O" "⚓1"
t_has "the mid tier keeps the weekly window" "$O" "7d 9%"
O="$(tier 60 "$PL")"
t_hasnt "the narrow tier drops the anchor" "$O" '⚓'
t_hasnt "the narrow tier drops the ships" "$O" '⛵'
t_hasnt "the narrow tier drops the weekly window" "$O" '7d'
t_has "the narrow tier keeps the 5h window" "$O" "5h 5%"
t_has "the narrow tier keeps the context" "$O" "ctx 30%"
t_has "a garbage COLUMNS degrades to the full render" "$(tier banana "$PL")" "cache 90%"
rm -f "$CFG/.helm-watch"

t_section "the payload dump hook (the only way to verify a field really arrives)"
DUMP="$TMP/dump.jsonl"
printf '%s' '{"model":{"display_name":"Opus 5"},'"$WS"'}' \
  | CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_GLYPH_DUMP="$DUMP" "$SH" "$SRC/status-fleet-glyph.sh" >/dev/null 2>&1
t_eq "HARBOR_GLYPH_DUMP captures the raw payload" yes "$(yn [ -s "$DUMP" ])"
t_has "the dump is the payload VERBATIM" "$(cat "$DUMP" 2>/dev/null)" '"display_name":"Opus 5"'
rm -f "$DUMP"; run '{"model":{"display_name":"Opus 5"},'"$WS"'}' >/dev/null
t_eq "the dump hook is off by default" no "$(yn [ -f "$DUMP" ])"

t_done
