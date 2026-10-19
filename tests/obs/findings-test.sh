#!/usr/bin/env sh
# bin/findings.sh (harbor#590): the lint tier of CONTRACTS/finding.md against a stub GitHub. The census
# comes in as records, the store is the stub's issues, and every case reads what was WRITTEN, not what
# was printed. The No.2.10 case is §6: accept a finding, change a subject, watch it come back.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/findings-fixture.sh"
# heal, and the check tier's heal cases, are tests/obs/findings.heal-test.sh.

t_section "the digest is the contract's, on its three worked rows"
t_eq "one path" e06264caf1fcc23e "$(sh "$F" digest bin/runtime-install.sh)"
t_eq "two paths" 9951a348aefc9079 "$(sh "$F" digest studio/.agents/hooks/prod_guard.py azimuth/.agents/hooks/prod_guard.py)"
t_eq "order does not matter" 9951a348aefc9079 "$(sh "$F" digest azimuth/.agents/hooks/prod_guard.py studio/.agents/hooks/prod_guard.py)"

t_section "lanes are read from the contract, and every other key is PROPOSE"
t_has "the skill.book-current HEAL row" "$(sh "$F" lanes)" "HEAL	lint/skill.book-current	skills/skill-book/SKILL.md	sh bin/skill-book.sh"
records "$TMP/r0" lint.long-file-reason skill.book-current -- lint.long-file-reason:bin/big.sh skill.book-current:generator-failed
t_has "a subject no HEAL row matches is PROPOSE" "$(rec "$TMP/r0")" "lint/skill.book-current (1 subject(s)) · PROPOSE"

t_section "a dry run reads the store once and writes nothing"
: > "$GH_LOG"; records "$TMP/r1" lint.long-file-reason drift.launchd-plist skill.book-current skill.not-for-target-exists -- lint.long-file-reason:bin/big.sh drift.launchd-plist:uncommitted:com.harbor.a.plist skill.book-current:skills/skill-book/SKILL.md
OUT="$(rec "$TMP/r1")"
t_has "it names what it would file" "$OUT" "lint/lint.long-file-reason (1 subject(s)) · PROPOSE · would file"
t_has "and the lane the contract gives skill.book-current" "$OUT" "lint/skill.book-current (1 subject(s)) · HEAL · would file"
t_has "the denominator" "$OUT" "examined 4 rules and 0 checks, could not classify 0"
t_has "a store nobody has written says so" "$OUT" "never — this is the first reconcile"
t_eq "one read, no write" "issue list" "$(tr '\n' '|' < "$GH_LOG" | sed 's/ -R.*//')"

t_section "--apply refuses a checkout that is not the published default branch"
: > "$GH_LOG"; echo drift > "$PUB/untracked"
t_exit "exit 1" 1 env HARBOR_ROOT="$PUB" sh "$F" reconcile --from "$TMP/r1" --apply
t_eq "and nothing was read or written" 0 "$(grep -c . "$GH_LOG" | tr -d ' ')"
rm -f "$PUB/untracked"

t_section "--apply files one issue per firing rule, keyed by the marker"
: > "$GH_LOG"; OUT="$(rec "$TMP/r1" --apply)"
t_eq "three open findings" 3 "$(open_n)"
t_has "the marker carries key, digest and seen" "$(jq -r '.issues[1].body' "$GH_STATE")" \
  "<!-- harbor:finding key=lint/lint.long-file-reason digest=$(sh "$F" digest bin/big.sh) seen=2026-10-01 schema=1 -->"
t_eq "every one is labelled finding" 3 "$(jq '[.issues[] | select(any(.labels[]; .name == "finding"))] | length' "$GH_STATE")"
t_has "the report names the filed issue" "$OUT" "filed #1"

t_section "the same census the same day writes nothing; the next day refreshes seen once"
: > "$GH_LOG"; OUT="$(rec "$TMP/r1" --apply)"
t_eq "no write on a re-run" 0 "$(writes)"
t_has "nothing new" "$OUT" "open: 3"
t_hasnt "and nothing re-filed" "$OUT" "filed #"
: > "$GH_LOG"; NOW=2026-10-02; OUT="$(rec "$TMP/r1" --apply)"
t_eq "one refresh per open finding" 3 "$(writes)"
t_has "seen moved" "$(jq -r '.issues[0].body' "$GH_STATE")" "seen=2026-10-02"
t_has "and the age is from the issue, not the marker" "$OUT" "oldest open:"

t_section "a rule that ran and did not fire is fixed; one that did not run is only not seen"
records "$TMP/r2" lint.long-file-reason drift.launchd-plist skill.not-for-target-exists -- lint.long-file-reason:bin/big.sh
: > "$GH_LOG"; NOW=2026-10-03; OUT="$(rec "$TMP/r2" --apply)"
t_eq "drift.launchd-plist closed as completed with finding:fixed" "1 CLOSED COMPLETED finding,finding:fixed" "$(issue_of lint/drift.launchd-plist)"
t_has "reported as fixed" "$OUT" "lint/drift.launchd-plist #1"
t_eq "skill.book-current did not run, so it stays open" "3 OPEN  finding" "$(issue_of lint/skill.book-current)"
t_has "and is reported as not seen" "$OUT" "not seen this run: 1 (lint/skill.book-current (#3, seen 2026-10-02) — the rule did not run)"

t_section "a disposition is a person's: no terminal, or an agent session, is refused"
t_exit "no terminal" 1 sh "$F" accept lint/lint.long-file-reason --reason "reviewed"
t_has "and it says why" "$(sh "$F" accept lint/lint.long-file-reason --reason reviewed 2>&1)" "no terminal on stdin and stdout"
t_has "inside an agent session" "$(CLAUDECODE=1 sh "$F" accept lint/lint.long-file-reason --reason reviewed 2>&1)" "this is an agent session"
t_eq "and nothing was written" "2 OPEN  finding" "$(issue_of lint/lint.long-file-reason)"

# tty_run <typed> <cmd…> — the person at a terminal: a pseudo-terminal from script(1), BSD or util-linux.
_q() { printf "'%s' " "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
tty_run() {
  _ty="$1"; shift
  if script --version 2>/dev/null | grep -q util-linux; then
    _c=""; for _w in "$@"; do _c="$_c$(_q "$_w")"; done
    { sleep 1; printf '%s\n' "$_ty"; sleep 1; } | script -qec "$_c" /dev/null 2>&1
  else
    { sleep 1; printf '%s\n' "$_ty"; sleep 1; } | script -q /dev/null "$@" 2>&1
  fi
}
t_section "a person at a terminal accepts; a wrong key typed back changes nothing"
OUT="$(tty_run lint/drift.launchd-plist env HARBOR_ROOT="$PUB" sh "$F" accept lint/lint.long-file-reason --reason "reviewed")"
t_has "the mismatch is refused" "$OUT" "not lint/lint.long-file-reason — nothing changed"
t_eq "still open" "2 OPEN  finding" "$(issue_of lint/lint.long-file-reason)"
OUT="$(tty_run lint/lint.long-file-reason env HARBOR_ROOT="$PUB" sh "$F" accept lint/lint.long-file-reason --reason "the header says why (#578)")"
t_has "accepted" "$OUT" "is accepted"
t_eq "closed not planned, labelled" "2 CLOSED NOT_PLANNED finding,finding:accepted" "$(issue_of lint/lint.long-file-reason)"

t_section "an accepted finding stays closed while its digest holds"
: > "$GH_LOG"; NOW=2026-10-04; OUT="$(rec "$TMP/r2" --apply)"
t_eq "no new issue" 1 "$(jq '[.issues[] | select(.body | contains("key=lint/lint.long-file-reason "))] | length' "$GH_STATE")"
t_has "counted as accepted" "$OUT" "accepted: 1"

t_section "No.2.10 · an accepted finding whose subject changes re-opens as new"
records "$TMP/r3" lint.long-file-reason drift.launchd-plist skill.not-for-target-exists -- lint.long-file-reason:bin/big.sh lint.long-file-reason:bin/bigger.sh
NOW=2026-10-05; OUT="$(rec "$TMP/r3" --apply)"
t_eq "a second lint.long-file-reason issue, open" "4 OPEN  finding" "$(issue_of lint/lint.long-file-reason)"
t_has "it links the accepted one" "$(jq -r '.issues[3].body' "$GH_STATE")" "This finding follows #2: accepted, digest changed"
t_has "and the report says so" "$OUT" "accepted, digest changed (was #2)"

t_section "an issue closed without a disposition is filed again, once"
jq '(.issues[] | select(.number == 4)) |= (.state = "CLOSED" | .stateReason = "NOT_PLANNED")' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
NOW=2026-10-06; OUT="$(rec "$TMP/r3" --apply)"
t_has "re-filed" "$OUT" "closed without a disposition, filed again (was #4)"
NOW=2026-10-07; OUT="$(rec "$TMP/r3" --apply)"
t_eq "and only once" 1 "$(jq '[.issues[] | select(.state == "OPEN" and (.body | contains("key=lint/lint.long-file-reason ")))] | length' "$GH_STATE")"

t_section "a store that cannot be read is a FAIL, never an empty store"
: > "$GH_LOG"
t_exit "exit 1" 1 env GH_FAIL=list HARBOR_ROOT="$PUB" sh "$F" reconcile --from "$TMP/r3" --apply
t_has "it names the store" "$(GH_FAIL=list HARBOR_ROOT="$PUB" sh "$F" reconcile --from "$TMP/r3" 2>&1)" "could not read the finding store at o/r"
t_eq "and wrote nothing" 0 "$(writes)"

t_section "report is the ages and the last write, never the census"
OUT="$(HARBOR_ROOT="$PUB" HARBOR_FINDINGS_NOW=2026-10-07 sh "$F" report 2>&1)"
t_has "when the store was last written" "$OUT" "last reconcile:  2026-10-07"
t_has "the oldest open" "$OUT" "oldest open:"
t_has "the age buckets" "$OUT" "under a week"
t_hasnt "and no per-finding census" "$OUT" "bin/big.sh"

t_section "harbor#893 · a list that lags a just-filed finding does not file it twice"
GH_STATE="$TMP/gh-lag.json"; export GH_STATE
records "$TMP/l1" lint.long-file-reason drift.launchd-plist -- lint.long-file-reason:bin/big.sh drift.launchd-plist:bin/other.sh
NOW=2026-10-20; rec "$TMP/l1" --apply > /dev/null
_newest="$(jq '[.issues[].number] | max' "$GH_STATE")"
: > "$GH_LOG"; OUT="$(GH_LAG_HIDE="$_newest" rec "$TMP/l1" --apply)"
t_eq "no issue created while the list hid #$_newest" 0 "$(grep -c '^issue create' "$GH_LOG" | tr -d ' ')"
t_eq "still two findings" 2 "$(jq '.issues | length' "$GH_STATE")"
t_has "and the report says what the list missed" "$OUT" "missed by the list, read:"
t_has "naming the issue" "$OUT" "#$_newest — GitHub's issue list lagged"
OUT="$(rec "$TMP/l1")"
t_hasnt "a list that does not lag reports nothing missed" "$OUT" "missed by the list"
t_has "positive control for that line's absence: the run printed its header" "$OUT" "findings: reconciled"

t_section "harbor#957 · a finding filed under a deprecated letter id joins its successor, and is re-keyed"
GH_STATE="$TMP/gh-rekey.json"; export GH_STATE
_g1="$(sh "$F" digest bin/big.sh)"
jq -n --arg b "<!-- harbor:finding key=lint/G1 digest=$_g1 seen=2026-10-01 schema=1 -->" \
      --arg b2 '<!-- harbor:finding key=lint/X9 digest=0000000000000000 seen=2026-10-01 schema=1 -->' \
  '{issues: [{number: 1, state: "OPEN", stateReason: "", labels: [{name: "finding"}], createdAt: "2026-10-01T09:00:00Z", title: "finding lint/G1: x", body: $b},
             {number: 2, state: "OPEN", stateReason: "", labels: [{name: "finding"}], createdAt: "2026-10-01T09:00:00Z", title: "finding lint/X9: x", body: $b2}],
    labels: ["finding", "finding:accepted", "finding:superseded", "finding:fixed"]}' > "$GH_STATE"
records "$TMP/k1" lint.long-file-reason drift.launchd-plist -- lint.long-file-reason:bin/big.sh
: > "$GH_LOG"; NOW=2026-10-21; OUT="$(rec "$TMP/k1")"
t_has "a dry run names the re-key" "$OUT" "would re-key (D-19):"
t_has "…from the letter to its successor, on the same issue" "$OUT" "lint/G1 → lint/lint.long-file-reason (#1)"
t_hasnt "nothing is filed new" "$OUT" "would file"
t_has "nothing is orphaned: every open finding classifies" "$OUT" "could not classify 0"
t_has "a letter-keyed finding whose rule ran and did not fire is fixed under its successor" "$OUT" "lint/drift.launchd-plist #2"
t_eq "a dry run writes nothing" 0 "$(writes)"
: > "$GH_LOG"; OUT="$(rec "$TMP/k1" --apply)"
t_has "--apply rewrites the marker on the same issue" "$(jq -r '.issues[0].body' "$GH_STATE")" "key=lint/lint.long-file-reason digest=$_g1 "
t_eq "…files nothing new" 2 "$(jq '.issues | length' "$GH_STATE")"
t_has "…and retitles it under the id" "$(cat "$GH_LOG")" "--title finding lint/lint.long-file-reason:"
records "$TMP/k2" G1 X9 -- G1:bin/big.sh; _k2="$(rec "$TMP/k2")"
t_hasnt "a capture still spelling letters is read under the ids: nothing to file" "$_k2" "would file"
t_has "…and its one finding stands" "$_k2" "open: 1"
: > "$GH_LOG"; OUT="$(rec "$TMP/k1" --apply)"
t_hasnt "a re-keyed marker is not re-keyed again" "$OUT" "re-key"
t_eq "…and the same day writes nothing" 0 "$(writes)"

# ── the check tier (harbor#896) ──────────────────────────────────────────────
t_section "log_receipt writes one atomic, valid receipt, and refuses a bad status or id"
RD="$TMP/rl"; ( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD" memory-route red 'har"bor/wt' studio )
t_eq "valid JSON with its subjects" 'red ["har\"bor/wt","studio"]' "$(jq -c -r '"\(.status) \(.subjects | tojson)"' "$RD/memory-route.json")"
t_has "stamped" "$(jq -r .ran_at "$RD/memory-route.json")" "T"
t_eq "a bad status returns 1" 1 "$( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD" memory-route amber x; echo $?)"
( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD" 'Bad Id' red x || : )
t_eq "a bad status leaves the receipt as it was" red "$(jq -r .status "$RD/memory-route.json")"
t_eq "a bad id writes nothing" 1 "$(find "$RD" -name '*.json' | grep -c .)"
t_eq "no temp file is left" 0 "$(find "$RD" -name '.*' -type f | grep -c .)"

GH_STATE="$TMP/gh-check.json"; export GH_STATE
records "$TMP/c0" lint.long-file-reason -- lint.long-file-reason:bin/big.sh

t_section "check tier · a red receipt files check/<id> over its subjects, with the receipt as evidence"
rcpt memory-route red 2026-10-21 harbor/wt-a studio
NOW=2026-10-21; OUT="$(rec "$TMP/c0" --apply)"
t_has "filed, in the HEAL lane" "$OUT" "check/memory-route (2 subject(s)) · HEAL · filed"
_cb="$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))][0].body' "$GH_STATE")"
t_has "digested over the subjects" "$_cb" "digest=$(sh "$F" digest harbor/wt-a studio)"
t_has "the rule line names the receipt" "$_cb" '`~/.claude/cache/checks/memory-route.json`'
t_has "the evidence is the receipt" "$_cb" '"status":"red"'

t_section "check tier · a stale receipt is not seen, never fixed"
rcpt memory-route green 2026-10-21
NOW=2026-10-25; OUT="$(rec "$TMP/c0" --apply)"
t_has "not seen" "$OUT" "check/memory-route (#"
t_has "and said so" "$OUT" "the rule did not run)"
t_eq "still open" OPEN "$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))][0].state' "$GH_STATE")"

t_section "check tier · a fresh green receipt closes it as fixed"
rcpt memory-route green 2026-10-25
NOW=2026-10-25; OUT="$(rec "$TMP/c0" --apply)"
t_has "fixed" "$OUT" "check/memory-route #"
t_eq "closed completed, labelled" "CLOSED COMPLETED" "$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))][0] | "\(.state) \(.stateReason)"' "$GH_STATE")"
t_has "the close says the receipt was green, not that a commit ran" "$(grep '^issue close' "$GH_LOG" | tail -1)" "its receipt was fresh and green on 2026-10-25"

t_section "check tier · a stood-down run is a finding of its own"
rcpt memory-route stood-down 2026-10-26
NOW=2026-10-26; OUT="$(rec "$TMP/c0" --apply)"
t_has "filed again over stood-down" "$OUT" "check/memory-route → filed"
t_has "with stood-down as its subject" "$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))] | max_by(.number) | .body' "$GH_STATE")" '- `stood-down`'

t_section "check tier · a receipt whose id is not a CHECKS.md row is refused, not filed"
rcpt not-a-check red 2026-10-26 x
: > "$GH_LOG"; OUT="$(NOW=2026-10-26 rec "$TMP/c0" --apply)"
t_has "could not classify it" "$OUT" "check/not-a-check (receipt with no CHECKS.md row)"
t_eq "and filed nothing for it" 0 "$(jq '[.issues[] | select(.body | contains("key=check/not-a-check "))] | length' "$GH_STATE")"
rm -f "$RCD/not-a-check.json"

t_section "check tier · a private check's receipt joins the composed register (harbor#1149)"
PVR="$TMP/pv-rcpt"; mkdir -p "$PVR"
printf '## Register\n\n| `acme-feed` | the Acme feed | hourly | desktop | the feed stopped |\n\n## Platforms\n\n| acme-feed | macOS only | w | d |\n' > "$PVR/checks.md"
rcpt acme-feed red 2026-10-26 x
: > "$GH_LOG"; OUT="$(HARBOR_SCOPE_PRIVATE="$TMP/no-layer" NOW=2026-10-26 rec "$TMP/c0" --apply)"
t_has "with no layer the receipt has no row and is refused" "$OUT" "check/acme-feed (receipt with no CHECKS.md row)"
: > "$GH_LOG"; OUT="$(HARBOR_SCOPE_PRIVATE="$PVR" NOW=2026-10-26 rec "$TMP/c0" --apply)"
t_hasnt "with the layer it is a row, and is not refused" "$OUT" "check/acme-feed (receipt with no CHECKS.md row)"
t_eq "...and a filing for it exists" 1 "$(jq '[.issues[] | select(.body | contains("key=check/acme-feed "))] | length' "$GH_STATE")"
rm -f "$RCD/acme-feed.json"

t_section "check tier · review #898: a receipt with an unknown status is refused, never read as a run"
rcpt memory-route red 2026-10-26 harbor/wt-z
NOW=2026-10-26; rec "$TMP/c0" --apply > /dev/null
rcpt memory-route amber 2026-10-26
OUT="$(NOW=2026-10-26 rec "$TMP/c0" --apply)"
t_has "refused, naming the status" "$OUT" "receipt status amber is not green, red or stood-down"
t_eq "the open finding is not closed as fixed" OPEN "$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))] | max_by(.number) | .state' "$GH_STATE")"

t_section "check tier · review #898: a receipt dated in the future is refused, never fresh"
rcpt memory-route green 2026-11-30
OUT="$(NOW=2026-10-26 rec "$TMP/c0" --apply)"
t_has "refused, naming the date" "$OUT" "check/memory-route (receipt dated after 2026-10-26)"
t_eq "the open finding is not closed as fixed" OPEN "$(jq -r '[.issues[] | select(.body | contains("key=check/memory-route "))] | max_by(.number) | .state' "$GH_STATE")"

t_section "check tier · review: the freshness window is two days, exactly"
rcpt memory-route red 2026-10-24 harbor/wt-w
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "two days old is a run" "$OUT" "check/memory-route"
t_hasnt "and not 'not seen'" "$OUT" "seen 2026-10-24) — the rule did not run"
rcpt memory-route red 2026-10-23 harbor/wt-w
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "three days old is not seen" "$OUT" "the rule did not run"

t_section "check tier · review: a receipt whose file name is not its id is refused; the id is a literal"
rcpt memory-route red 2026-10-26 x; mv "$RCD/memory-route.json" "$RCD/main-tip-verdict.json"
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "refused" "$OUT" "receipt main-tip-verdict.json names another id"
rm -f "$RCD/main-tip-verdict.json"
jq -n '{id: "memory.route", ran_at: "2026-10-26T09:00:00Z", status: "red", subjects: ["x"]}' > "$RCD/memory.route.json"
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "a regex-shaped id matches no row" "$OUT" "check/memory.route (receipt with no CHECKS.md row)"
rm -f "$RCD/memory.route.json"

t_section "check tier · harbor#904: a writer and the reconcile resolve one receipt dir, CLAUDE_CONFIG_DIR set elsewhere"
_cfg="$TMP/cfg904"; rm -rf "$_cfg"; mkdir -p "$_cfg"
( unset HARBOR_RECEIPTS HARBOR_CACHE_DIR; CLAUDE_CONFIG_DIR="$_cfg" HOME="$TMP/home904" HARBOR_GH=false \
    sh "$T_ROOT/bin/main-tip-verdict.sh" >/dev/null 2>&1 || : )
t_eq "main-tip-verdict wrote its receipt under CLAUDE_CONFIG_DIR" stood-down "$(jq -r .status "$_cfg/cache/checks/main-tip-verdict.json" 2>/dev/null)"
OUT="$( unset HARBOR_RECEIPTS; CLAUDE_CONFIG_DIR="$_cfg" NOW="$(date -u +%Y-%m-%d)" rec "$TMP/c0" )"
t_has "the reconcile read it" "$OUT" "check/main-tip-verdict"

t_section "check tier · harbor#904: the report counts rules and checks apart"
rm -f "$RCD"/*.json; rcpt memory-route red 2026-10-26 x
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "one rule, one check" "$OUT" "examined 1 rules and 1 checks"

t_section "check tier · review: log_receipt escapes a backslash, and refuses too few arguments"
( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD" memory-route red 'a\b' )
t_eq "the backslash survives the round trip" 'a\b' "$(jq -r '.subjects[0]' "$RD/memory-route.json")"
t_eq "two arguments is a failure" 1 "$( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD" memory-route; echo $?)"

t_section "check tier · log_receipt never writes through a planted symlink"
RD2="$TMP/rl2"; mkdir -p "$RD2"; printf 'protected\n' > "$TMP/prot"
ln -s "$TMP/prot" "$RD2/.memory-route.json.$$"; ln -s "$TMP/prot" "$RD2/.memory-route.json.planted"
( . "$T_ROOT/bin/log-lib.sh"; log_receipt "$RD2" memory-route green )
t_eq "the protected file is untouched" protected "$(cat "$TMP/prot")"
t_eq "and the receipt is a plain file" "file green" "$([ -L "$RD2/memory-route.json" ] && echo link || echo file) $(jq -r .status "$RD2/memory-route.json")"

t_section "check tier · a receipt's own fresh_days widens its window (a weekly check, harbor#577)"
GH_STATE="$TMP/gh-check.json"; export GH_STATE
jq -n '{id: "memory-route", ran_at: "2026-10-21T09:00:00Z", status: "red", subjects: ["harbor/wt-weekly"], fresh_days: 8}' > "$RCD/memory-route.json"
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_hasnt "five days old with fresh_days 8 is a run, not 'not seen'" "$OUT" "the rule did not run"
t_has "positive control: the finding is judged" "$OUT" "check/memory-route"
jq -n '{id: "memory-route", ran_at: "2026-10-21T09:00:00Z", status: "red", subjects: ["harbor/wt-weekly"]}' > "$RCD/memory-route.json"
OUT="$(NOW=2026-10-26 rec "$TMP/c0")"
t_has "without it, five days old is not seen" "$OUT" "the rule did not run"

t_section "context.budget-ceiling end to end (harbor#585, No.2.10): a planted regrowth reaches the store, its restore closes it"
# The real linter and the real context-budget.sh against a fixture box, read by the real reconcile.
GH_STATE="$TMP/gh-x3.json"; export GH_STATE; rm -f "$RCD"/*.json
XR="$TMP/x3root"; XC="$TMP/x3cfg"; XW="$TMP/x3cwd"; XB="$TMP/x3-baseline.tsv"
mkdir -p "$XR/bin" "$XC/skills" "$XW"; cp "$T_ROOT/bin/context-budget.sh" "$T_ROOT/bin/log-lib.sh" "$XR/bin/"
printf 'a constitution\n' > "$XC/CLAUDE.md"
x3() { # <dir> — one context.budget-ceiling run over the fixture box, captured the way the reconcile reads a lint run
  mkdir -p "$1"; : > "$1/records.tsv"
  ( cd "$XW" && CLAUDE_CONFIG_DIR="$XC" HARBOR_CONTEXT_CEILING=99999999 HARBOR_CONTEXT_BASELINE="$XB" \
      HARBOR_ROOT="$XR" HARBOR_FINDINGS_OUT="$1/records.tsv" sh "$T_ROOT/bin/lint-conventions.sh" --only context.budget-ceiling ) > "$1/lint.log" 2>&1
}
x3body() { jq -r '[.issues[] | select(.body | contains("key=lint/context.budget-ceiling "))] | max_by(.number) | .body' "$GH_STATE"; }
( cd "$XW" && CLAUDE_CONFIG_DIR="$XC" HARBOR_CONTEXT_BASELINE="$XB" sh "$XR/bin/context-budget.sh" --record ) >/dev/null 2>&1
x3 "$TMP/x3a"
t_eq "the surface as recorded: context.budget-ceiling ran and named no subject" "R context.budget-ceiling|" "$(tr '\t\n' ' |' < "$TMP/x3a/records.tsv")"
mkdir -p "$XC/skills/grown"
printf -- '---\nname: grown\ndescription: an ambient skill every session now pays for\n---\n' > "$XC/skills/grown/SKILL.md"
x3 "$TMP/x3b"
t_eq "a planted regrowth: the subject is the verdict's kind" "R context.budget-ceiling|A context.budget-ceiling grew:CONTEXT-BASELINE.tsv|" "$(tr '\t\n' ' |' < "$TMP/x3b/records.tsv")"
NOW=2026-11-01; OUT="$(rec "$TMP/x3b" --apply)"
t_has "the reconcile files it" "$OUT" "filed #"
t_has "keyed lint/context.budget-ceiling, over the kind" "$(x3body)" '- `grew:CONTEXT-BASELINE.tsv`'
t_has "with the tool's own line as evidence" "$(x3body)" 'DELIBERATE SURFACE MOVED'
rm -rf "$XC/skills/grown"; x3 "$TMP/x3c"
NOW=2026-11-02; rec "$TMP/x3c" --apply > /dev/null
t_eq "restored: context.budget-ceiling ran and did not fire, so it closes as fixed" "CLOSED COMPLETED finding,finding:fixed" "$(issue_of lint/context.budget-ceiling | cut -d' ' -f2-)"
mkdir -p "$XC/commands"; printf -- '---\ndescription: a planted slash command\n---\n' > "$XC/commands/planted.md"
x3 "$TMP/x3d"
t_eq "a surface the row did not count is an instrument change, never regrowth" "R context.budget-ceiling|A context.budget-ceiling instrument-changed:CONTEXT-BASELINE.tsv|" "$(tr '\t\n' ' |' < "$TMP/x3d/records.tsv")"
NOW=2026-11-03; rec "$TMP/x3d" --apply > /dev/null
t_eq "it reaches the store as an open finding" OPEN "$(issue_of lint/context.budget-ceiling | cut -d' ' -f2)"
t_has "over its own subject" "$(x3body)" '- `instrument-changed:CONTEXT-BASELINE.tsv`'
rm -rf "$XC/commands"
# Review #971: a --check that fails and names no kind (a crash) is its own subject, never a verdict.
XS="$TMP/x3stub"; mkdir -p "$XS/bin"
printf '#!/usr/bin/env sh\ncase "${1:-}" in --check) echo "boom: measuring failed" >&2; exit 3 ;; esac\n' > "$XS/bin/context-budget.sh"
mkdir -p "$TMP/x3e"; : > "$TMP/x3e/records.tsv"
HARBOR_ROOT="$XS" HARBOR_FINDINGS_OUT="$TMP/x3e/records.tsv" sh "$T_ROOT/bin/lint-conventions.sh" --only context.budget-ceiling > "$TMP/x3e/lint.log" 2>&1
t_eq "a --check that prints no kind files verdict-unreadable" "R context.budget-ceiling|A context.budget-ceiling verdict-unreadable:CONTEXT-BASELINE.tsv|" "$(tr '\t\n' ' |' < "$TMP/x3e/records.tsv")"
t_has "with the tool's own line as the message" "$(cat "$TMP/x3e/lint.log")" 'ADVISORY [context.budget-ceiling] boom: measuring failed'

t_done
