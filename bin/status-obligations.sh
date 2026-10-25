#!/usr/bin/env sh
# status-obligations.sh (harbor#1050) — the obligations ledger: a projection of the event bus.
#   sh status-obligations.sh fold       read the bus from its stored offset, append the transitions it implies,
#                                       rebuild current.json, then commit the offset. A row that goes overdue in
#                                       this run makes it reconcile too (HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off: not)
#   sh status-obligations.sh reconcile  fold, then ask the real state about every row still open (below)
#   sh status-obligations.sh show       what a person or the console reads (`harbor status obligations`), read-only:
#                                       --json   the frozen shape (CONTRACTS/cli.md), age_s and an expired row's `overdue` computed at read;
#                                                generated_ts is the fold's own clock, read_ts (added last) the read's
#                                       --print  a short view: overdue, then new, then oldest; never every row
#                                       --since <N>s|m|h|d  only rows opened or changed within that window
#   sh status-obligations.sh --help     this text
#   exit 0 = done, or another run holds the lock · exit 1 = a step failed · exit 2 = usage or a bad register
#   A source that did not answer is not a failure: it is recorded and flips nothing.
#
# STATE: $HARBOR_OBLIGATION_DIR (default ~/.local/state/harbor/obligations)
#   ledger.jsonl   append-only transitions: ts, obligation, to, event, then the fields of that transition
#   current.json   {"generated_ts", "obligations": [row …]}: every live row and every row closed within the retention
#                  window (HARBOR_STATUS_OBLIGATION_RETAIN, 15 days), derived from the ledger on every run
#   snapshot.json  the fold's own state at a ledger byte: rows, the (event, obligation, to) keys already applied, and
#                  closes that arrived before their open. A run reads the ledger from that byte on, not from the start
#   offset         <day-file><TAB><bytes consumed>, one line per bus day file
#   sources.json   what each source answered on the last reconcile: {"<source>": {"ok", "reason", "ts"}}, the
#                  `sources` map of `harbor status obligations --json`. ok:false carries the reason; ts is the attempt.
# SURFACES. Every fold or reconcile run ends by writing the two things the box reads, from current.json and sources.json:
#   $HARBOR_CACHE_DIR/status-obligations.json   {at, live, overdue, overdue_since, unread, you}: the statusline's `OVERDUE N ·age`
#                                               and its YOU row; epochs, so the age is counted at print time (default ~/.claude/cache).
#                                               `you` is up to 8 open rows the operator acts on, oldest first: the operator-owned
#                                               intents (handoffs) and approvals (PRs left 2026-10-16), as {k: kind, o: overdue, t: label}
#   $HARBOR_CACHE_DIR/checks/status.obligations.json   the check's receipt (CHECKS.md row `status.obligations`): red over the
#                                               ids of every row more than 24h past its deadline, else green; `findings.sh
#                                               reconcile` files red as `check/status.obligations`. The file is named for the id.
# INPUT: $HARBOR_EVENT_DIR/YYYY-MM-DD.jsonl (default ~/.local/state/harbor/events), one event per line.
# THE REGISTER: $HARBOR_STATUS_OBLIGATION_KINDS (default CONTRACTS/obligation-kinds.tsv beside this checkout, else bin/obligation-kinds.tsv beside the installed script).
#   An event no row names opens and closes nothing, and neither does an open event whose data fails the row's opens_when
#   (a background Bash, harbor#1049): it is counted as matching no row. HARBOR_STATUS_OBLIGATION_NOW pins the clock for a suite.
#
# THE RECONCILER. One bounded read per source, made only when a live row asks about it, each read killed after
# HARBOR_STATUS_OBLIGATION_READ_TIMEOUT seconds (10) and every read of a run after HARBOR_STATUS_OBLIGATION_BUDGET (40).
#   sessions       bin/fleet-sessions.sh --json: a session whose id is not live closes (closed_by=reconcile); the
#                  background work it owns is abandoned unless the register says it outlives the session. A session
#                  `claude agents` still lists as running is not dead, and a row under HARBOR_STATUS_OBLIGATION_GRACE
#                  seconds old (300) is not judged: the registry file lags exec.
#   claude-agents  `claude agents --json --all`: an agent the list says is done, stopped or failed closes; one it does
#                  not know whose owner session is gone is abandoned.
#   gh-pr          `gh pr view`: MERGED or CLOSED closes. A kind may name it second (approval: approval-queue,gh-pr): the PR is then
#                  the one the row's link names.   gh-run   `gh run view`: the run, or the named job, completed.
#   transcripts    not a source of its own: when a dead owner last wrote its transcript (HARBOR_STATUS_OBLIGATION_TRANSCRIPTS,
#                  default ~/.claude/projects). A row that outlives its owner's stop (Workflow) is abandoned once its deadline has
#                  passed, the owner is gone from both lists and no transcript line came after the deadline, or the owner has been silent for HARBOR_STATUS_OBLIGATION_QUIET seconds (86400).
#   sweep          the harbor-clean.sh --record rows: each RISK or DECIDE row is a `leftover` obligation owned by the
#                  operator while the record names it, closed when the next record does not. $HOME is shown as ~.
# A source that fails, times out, prints what is not a list, or is older than it may be (the sweep record, 36h)
# gives no verdict, so it flips nothing; a gh read that failed leaves that row alone. Knobs that swap a source for a
# fixture: HARBOR_STATUS_OBLIGATION_GH, _CLAUDE, _SESSIONS (an executable taking --json), _HOUSEKEEPING (the record's
# .jsonl; its summary line sits beside it). Not yet a source: launchctl and receipt age (the scheduled-check kind).
#
# WHY IT SURVIVES A KILL. The order is ledger, current.json + snapshot.json, offset, and the offset is the commit: a
# run killed before it replays the same bytes. A replay re-derives the same transitions and skips each
# one whose (event, obligation, to) key the ledger already holds, so nothing is lost and nothing doubles.
# A torn last ledger line is cut off first, since only an uncommitted run can have written it. A torn
# last line on the bus is left for the next run: the offset stops at the last newline.
# RETENTION. A closed row, and the key of every transition, is kept for 15 days: the bus keeps 14 days of day files
# (CONTRACT §1), and a day file's last event is a day younger than its name, so a replay of everything the bus still
# holds is still deduped. A row older than that is gone from current.json and the snapshot; the ledger keeps it.
# A LEDGER LINE THAT DOES NOT PARSE is skipped and counted, never fatal: it is warned on stderr and shows as a `ledger`
# source (ok:false) in `harbor status obligations --json` until the next clean run.
# ORDER OF ARRIVAL. A terminal event for an id with no row is held (a `pending` transition) and applied when the open
# event arrives, if the open is not later than it. LOCK: .fold.lock is a symlink to the holder's pid, so taking it and
# naming the owner are one step. An unreadable holder is live until its lock is HARBOR_STATUS_OBLIGATION_LOCK_GRACE
# seconds old (10); any lock older than HARBOR_STATUS_OBLIGATION_LOCK_MAX (900) is taken over, whatever its pid says
# (a reused pid must not silence every later run). A run releases the lock only if it still holds its own pid.
# PRIVACY (harbor#1050, CONSTITUTION §3). title and subject lose $HOME (shown ~), any path under .claude and shell
# metacharacters; a command-like title falls back to the subject; the title is capped at 120 characters, the subject at 200.
# HARBOR_STATUS_OBLIGATION_FAULT=mid-ledger|before-offset|after-reconcile-ledger kills the run at that point, lock-gap holds the lock one second
# once taken, slow-commit waits one second before the offset is committed, slow-read three seconds between reading the
# ledger state and appending to it; for the suites only.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
esac
LOG_FD=2
. "$HERE/log-lib.sh"
. "$HERE/fs-lib.sh"
log_init status-obligations

EVDIR="${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}"
DIR="${HARBOR_OBLIGATION_DIR:-$HOME/.local/state/harbor/obligations}"
# The register: the checkout's CONTRACTS/ when it is beside bin/, else the copy runtime-install ships next to this script
# (an installed config dir has no CONTRACTS/ entry of its own: deploy's snapshot set would not cover one, harbor#1115).
KINDS="${HARBOR_STATUS_OBLIGATION_KINDS:-}"
if [ -z "$KINDS" ]; then
  KINDS="$HERE/../CONTRACTS/obligation-kinds.tsv"; [ -f "$KINDS" ] || KINDS="$HERE/obligation-kinds.tsv"
fi
LEDGER="$DIR/ledger.jsonl"; CURRENT="$DIR/current.json"; OFFSET="$DIR/offset"; LOCK="$DIR/.fold.lock"; SOURCES="$DIR/sources.json"
SNAP="$DIR/snapshot.json"
NOW="${HARBOR_STATUS_OBLIGATION_NOW:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
LEDGER_SKIPPED=0   # ledger lines this run skipped because they did not parse

CACHE_DIR="${HARBOR_CACHE_DIR:-$HOME/.claude/cache}"
RED_AFTER_S=86400   # a row this long past its deadline turns the receipt red (harbor#1050)

command -v jq >/dev/null 2>&1 || {
  log_fail "jq is not on PATH; the fold reads and writes JSON with it"; log_fix "$(pkg_hint jq)"; log_end || :; exit 1
}

# ── show · the read side: `harbor status obligations` ─────────────────────────────────────────────
# Read-only: no lock, no register, nothing written. The projection below is the one shape the console reads, so every key
# is named here and defaulted to "" rather than passed through: a row the fold wrote with a key missing still has it.
# TWO CLOCKS, AND NEITHER MAY STAND IN FOR THE OTHER (harbor#1115). generated_ts is when the FOLD last wrote current.json, so a
# reader can see how stale it is; read_ts is this read's clock. And a row stored `open` whose deadline has passed is shown
# `overdue`, so a stale file cannot show an expired row as healthy: age_s is already counted at read, and so is this.
SHOW_JQ='
  def ts($t): try ($t | fromdateiso8601) catch 0;
  def clean: gsub("[[:cntrl:]]"; " ");
  def ago($s): if $s < 90 then "\($s)s" elif $s < 5400 then "\($s / 60 | floor)m" elif $s < 172800 then "\($s / 3600 | floor)h" else "\($s / 86400 | floor)d" end;
  def rowline($r; $tail): "  \($r.id | clean)  \($tail)  \($r.title | clean | .[0:70])";
  [(.obligations // [])[] | {
      id: (.id // ""), kind: (.kind // ""), subject: (.subject // ""), repo: (.repo // ""), owner: (.owner // ""),
      title: (.title // ""), link: (.link // ""), opened_ts: (.opened_ts // ""), deadline_ts: (.deadline_ts // ""),
      state: (.state // ""), closed_by: (.closed_by // ""), closed_ts: (.closed_ts // "")}
    | . + {age_s: ([0, ($now - ts(.opened_ts))] | max)}
    | . + {state: (if .state == "open" and ts(.deadline_ts) > 0 and ts(.deadline_ts) < $now then "overdue" else .state end)}
    | select($since < 0 or ([ts(.opened_ts), ts(.closed_ts), ts($changed[.id] // "")] | max) >= ($now - $since))] as $rows
  | if $fmt == "json" then
      {generated_ts: (.generated_ts // $nowiso), sources: $src, obligations: $rows, proposals: [], read_ts: $nowiso}
    else
      ($rows | map(select(.state == "overdue")) | sort_by(.deadline_ts)) as $od
      | ($rows | map(select(.state == "open" or .state == "overdue"))) as $live
      | (if $since < 0 then 86400 else $since end) as $win
      | ($rows | map(select(.state == "open" and ts(.opened_ts) >= ($now - $win))) | sort_by(.opened_ts) | reverse) as $new
      | ($new | map(.id)) as $newids
      | ($rows | map(select(.state == "open" and (.id | IN($newids[]) | not))) | sort_by(.opened_ts)) as $old
      | ([$rows[] | select(.state == "closed")] | length) as $closed
      | ([$rows[] | select(.state == "abandoned")] | length) as $gone
      | ([$src | to_entries[] | select(.value.ok == false)] ) as $dark
      | ( "obligations as of \($nowiso)\(if $since >= 0 then " (changed in the last \(ago($since)))" else "" end): "
          + "\($od | length) overdue · \($new | length) new · \($closed) closed · \($gone) abandoned · \($live | length) live" ),
        (if ($od | length) > 0 then "OVERDUE", ($od[0:8][] | rowline(.; "\(ago([0, $now - ts(.deadline_ts)] | max)) over · \(.owner | clean)")),
           (if ($od | length) > 8 then "  … and \(($od | length) - 8) more overdue" else empty end) else empty end),
        (if ($new | length) > 0 then "NEW (opened in the last \(ago($win)))", ($new[0:8][] | rowline(.; "\(.state) \(ago(.age_s)) ago")),
           (if ($new | length) > 8 then "  … and \(($new | length) - 8) more new" else empty end) else empty end),
        (if ($old | length) > 0 then "OLDEST OPEN", ($old[0:5][] | rowline(.; "\(ago(.age_s)) old")),
           (if ($old | length) > 5 then "  … and \(($old | length) - 5) more open" else empty end) else empty end),
        (if ($dark | length) > 0 then "NO ANSWER FROM: " + ($dark | map("\(.key) (\(.value.reason | clean | .[0:80]))") | join("; ")) else empty end),
        (if ($live | length) == 0 and ($new | length) == 0 and ($closed + $gone) == 0 then "nothing live, nothing new" else empty end)
    end'

show_usage() {
  log_fail "usage: harbor status obligations [--json | --print] [--since <N>s|m|h|d]"
  log_fix "harbor status obligations --print"; log_end || :; exit 2
}

show_main() {
  _fmt=print; _since=-1
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
      --json) _fmt=json ;;
      --print) _fmt=print ;;
      --since)
        [ $# -ge 2 ] || show_usage
        case "$2" in
          [0-9]*[smhd]) _n="${2%?}"
            case "$_n" in *[!0-9]*) show_usage ;; esac
            case "${2#"$_n"}" in s) _since="$_n" ;; m) _since=$((_n * 60)) ;; h) _since=$((_n * 3600)) ;; d) _since=$((_n * 86400)) ;; esac ;;
          *) show_usage ;;
        esac
        shift ;;
      *) show_usage ;;
    esac
    shift
  done
  _now="$(jq -n -r --arg t "$NOW" '$t | fromdateiso8601' 2>/dev/null)" \
    || { log_fail "the clock $NOW is not YYYY-MM-DDTHH:MM:SSZ"; log_fix "unset HARBOR_STATUS_OBLIGATION_NOW"; log_end || :; exit 1; }
  if [ -f "$CURRENT" ]; then
    _cur="$CURRENT"
  elif [ "$_fmt" = print ]; then
    printf 'no obligations ledger at %s yet: nothing has folded the event bus (fleet-snapshot runs it every 5 minutes)\n' "$DIR"; exit 0
  else _cur=/dev/null
  fi
  _src='{}'; [ ! -f "$SOURCES" ] || _src="$(jq -c 'if type == "object" then . else {} end' "$SOURCES" 2>/dev/null)" || _src='{}'
  _chg='{}'
  if [ "$_since" -ge 0 ] && [ -f "$LEDGER" ]; then   # the last transition of each row: a row changes when it closes or goes overdue, not only when it opens
    _chg="$(jq -R -c 'fromjson? | select(type == "object" and (.obligation | type) == "string" and (.ts | type) == "string")' "$LEDGER" \
      | jq -s -c 'group_by(.obligation) | map({key: .[0].obligation, value: (map(.ts) | max)}) | from_entries')" \
      || { log_fail "could not read $LEDGER"; log_nofix "tests/status/obligations/surface.test.sh"; log_end || :; exit 1; }
  fi
  _rc=0
  { if [ "$_cur" = /dev/null ]; then printf '{"obligations":[]}\n'; else cat "$_cur"; fi; } \
    | jq -r --argjson now "$_now" --arg nowiso "$NOW" --argjson since "$_since" --arg fmt "$_fmt" --argjson src "$_src" --argjson changed "$_chg" "$SHOW_JQ" \
    || _rc=$?
  [ "$_rc" -eq 0 ] || { log_fail "could not read $CURRENT"; log_fix "sh $0 fold"; log_end || :; exit 1; }
}

case "${1:-}" in show) shift; show_main "$@"; exit 0 ;; esac

case "${1:-}" in fold|reconcile) [ $# -eq 1 ] && MODE="$1" || MODE="" ;; *) MODE="" ;; esac
[ -n "$MODE" ] || {
  log_fail "usage: status-obligations.sh fold|reconcile|show"; log_fix "sh $0 --help"; log_end || :; exit 2
}

# The register is checked before it is trusted: a row the fold would have to guess at is refused.
check_kinds() {
  [ -f "$KINDS" ] || { log_fail "no register at $KINDS"; log_fix "git checkout origin/main -- CONTRACTS/obligation-kinds.tsv"; return 1; }
  _bad="$(awk -F'\t' '
    /^[[:space:]]*(#|$)/ { next }
    $1 == "kind" { next }
    { n++ }
    NF != 9                                   { print NR ": " NF " columns, want 9"; next }
    $1 == "" || $1 ~ /:/                      { print NR ": kind is empty or holds a colon"; next }
    seen[$1]++                                { print NR ": kind " $1 " appears twice"; next }
    $2 == "" || $3 == ""                      { print NR ": open or close pattern is empty"; next }
    $4 !~ /^(-|[0-9]+[smhd])$/                { print NR ": deadline is " $4 ", want - or <N>s|m|h|d"; next }
    $5 !~ /^(self|subject-session|data-session|operator)$/ { print NR ": owner is " $5; next }
    $6 !~ /^(-|abandon)$/                     { print NR ": on_stop is " $6 ", want - or abandon"; next }
    $7 != "-" && $7 !~ /^[a-z_]+=./           { print NR ": outlives is " $7 ", want - or key=ERE"; next }
    $8 == ""                                  { print NR ": reconcile is empty"; next }
    $9 != "-" && $9 !~ /^[a-z_]+=./           { print NR ": opens_when is " $9 ", want - or key=ERE"; next }
    END { if (n == 0) print "no kind rows" }' "$KINDS")"
  [ -z "$_bad" ] || {
    printf '%s\n' "$_bad" | while IFS= read -r _l; do log_fail "$KINDS line $_l"; done
    log_fix "edit $KINDS to the columns its header describes"; return 1
  }
}

# The lock is a symlink named for its owner: `ln -s` creates it and records the pid in one atomic step, so there is no
# moment at which a lock exists without an owner. A directory lock (an older run's) is still read, never created.
lock_pid() { readlink "$LOCK" 2>/dev/null || cat "$LOCK/pid" 2>/dev/null || :; }
lock_age() { # seconds since the lock was made; non-zero when it is gone. GNU stat -c first, then perl's lstat: neither follows the link
  # No `stat -f` here: GNU reads it as --file-system and prints text (lint posix.stat-fallback, harbor#618), and perl is already a dependency of bounded().
  _lm="$(stat -c %Y "$LOCK" 2>/dev/null || true)"
  case "$_lm" in ''|*[!0-9]*) _lm="$(perl -e 'print +(lstat $ARGV[0])[9]' "$LOCK" 2>/dev/null || true)" ;; esac
  case "$_lm" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s' $(($(date +%s) - _lm))
}
release_lock() { [ "$(lock_pid)" != "$$" ] || rm -f "$LOCK"; }   # only our own: a lock taken over from us is not ours to drop

# Move a lock aside only while it is still the one judged stale; if another run took it in between, put it back. Two runs
# that both judge one lock stale and a third that takes the gap can still end with two holders: the window is the length of
# two syscalls, and it opens only for a lock already dead or past its age limit.
steal_lock() { # <the pid judged stale>
  _aside="$LOCK.stale.$$"
  mv "$LOCK" "$_aside" 2>/dev/null || return 0
  _got="$(readlink "$_aside" 2>/dev/null || cat "$_aside/pid" 2>/dev/null || :)"
  rm -rf "$_aside"
  [ "$_got" = "$1" ] || { [ -z "$_got" ] || ln -s "$_got" "$LOCK" 2>/dev/null || :; }
}

acquire() {
  mkdir -p "$DIR"
  _try=0
  while :; do
    if [ -d "$LOCK" ] && [ ! -L "$LOCK" ]; then :   # ln -s onto a directory would link inside it
    elif ln -s "$$" "$LOCK" 2>/dev/null; then
      [ "${HARBOR_STATUS_OBLIGATION_FAULT:-}" != lock-gap ] || sleep 1   # a suite's way to hold the lock open
      return 0
    fi
    _pid="$(lock_pid)"; _age="$(lock_age)" || { _try=$((_try + 1)); [ "$_try" -le 5 ] || { log_fail "cannot take $LOCK"; log_fix "rm -rf $LOCK"; return 2; }; continue; }
    _why=""
    if [ "$_age" -gt "$LOCK_MAX" ]; then _why="is $_age s old (over $LOCK_MAX s), whatever pid ${_pid:-?} says"
    elif [ -z "$_pid" ]; then [ "$_age" -lt "$LOCK_GRACE" ] || _why="names no owner and is $_age s old"
    elif ! kill -0 "$_pid" 2>/dev/null; then _why="was held by pid $_pid, which is gone"
    fi
    [ -n "$_why" ] || { log_note "another fold (pid ${_pid:-unknown}) holds $LOCK; nothing read this run"; return 1; }
    _try=$((_try + 1))
    [ "$_try" -le 5 ] || { log_fail "cannot take $LOCK"; log_fix "rm -rf $LOCK"; return 2; }
    if [ "$_age" -gt "$LOCK_MAX" ]; then log_warn "taking over $LOCK: it $_why"; else log_note "taking over $LOCK: it $_why"; fi
    steal_lock "$_pid"
  done
}

# Only a run killed before it committed its offset can have left half a line on the ledger.
heal_ledger() {
  [ -s "$LEDGER" ] || return 0
  [ "$(tail -c 1 "$LEDGER" | od -An -tx1 | tr -d ' \n')" != 0a ] || return 0
  _torn="$(tail -n 1 "$LEDGER" | wc -c | tr -d ' ')"; _size="$(wc -c < "$LEDGER" | tr -d ' ')"
  head -c $((_size - _torn)) "$LEDGER" > "$T/ledger.healed" && mv -f "$T/ledger.healed" "$LEDGER"
  log_note "cut $_torn bytes of a torn ledger tail left by an interrupted run"
}

cleanup() { [ -z "$T" ] || rm -rf "$T"; release_lock; }

fault() { # <point> — a suite's way to kill this run exactly there
  [ "${HARBOR_STATUS_OBLIGATION_FAULT:-}" != "$1" ] || kill -9 "$$"
}

# The complete lines of every day file past its stored offset, in file order, into $T/raw; the
# offsets to commit into $T/offset.new. A line without its newline is not read.
collect() {
  : > "$T/raw"; : > "$T/offset.new"
  [ -d "$EVDIR" ] || { log_note "no bus directory at $EVDIR; nothing to read"; return 0; }
  find "$EVDIR" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl' | sort > "$T/days"
  while IFS= read -r _f; do
    _b="$(basename "$_f")"
    _off="$(awk -F'\t' -v f="$_b" '$1 == f { print $2; exit }' "$OFFSET" 2>/dev/null || :)"
    case "$_off" in ''|*[!0-9]*) _off=0 ;; esac
    _size="$(wc -c < "$_f" | tr -d ' ')"
    # A day file smaller than its offset was replaced: read it whole; the ledger's keys stop doubles.
    [ "$_off" -le "$_size" ] || { log_warn "$_b is shorter than its offset ($_size < $_off); reading it from 0"; _off=0; }
    _take=0
    if [ "$_size" -gt "$_off" ]; then
      tail -c +$((_off + 1)) "$_f" > "$T/chunk"
      _csize=$((_size - _off))
      if [ "$(tail -c 1 "$T/chunk" | od -An -tx1 | tr -d ' \n')" = 0a ]; then _take="$_csize"
      else _take=$((_csize - $(tail -n 1 "$T/chunk" | wc -c | tr -d ' '))); fi
      [ "$_take" -le 0 ] || head -c "$_take" "$T/chunk" >> "$T/raw"
    fi
    printf '%s\t%s\n' "$_b" $((_off + _take)) >> "$T/offset.new"
  done < "$T/days"
}

# The definitions the fold and the reconciler share: ts_re … finish. $reg is the register, $now the clock, $home the
# operator's home, $retain the seconds a closed row is kept. The state they thread is {rows, seen, pending, live, out}:
# rows by id; seen the (event, obligation, to) keys applied, by the epoch of their ts; pending a terminal event held for
# an open that has not arrived; live the ids of the open and overdue rows, so a pass never walks the closed ones.
# SPEED. jq mutates the state in place only while nothing else holds it, and an unfinished generator holds it: `//`, `try`,
# `?`, `first(f)`, and any `reduce` or `as` whose source is still producing. Evaluated before an update, each makes that
# update copy the whole state (harbor#1050: 40k events took minutes). So nothing below puts one of them on the path to an
# update: a value is collected with [ … ][0], and a pass collects its ids into an array before it reduces over them.
# shellcheck disable=SC2016
DEFS='
def ts_re: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$";
def ts_e($t): [$t | try fromdateiso8601 catch 0][0];   # collected: a live `try` fork pins the state and makes every later update copy it
def live: . == "open" or . == "overdue";
def is_live($id): .rows[$id] != null and (.rows[$id].state | live);
# What may leave the fold as text (harbor#1050, CONSTITUTION §3): $HOME and any /Users/<n> or /home/<n> shown as ~, a path
# under .claude gone, control characters blanked. A subject also loses shell metacharacters and is capped at 200; it is
# an identifier, and a terminal event repeats it, so the same cleaning on both sides keeps them equal.
def scrub:
  (if $home != "" then split($home) | join("~") else . end)
  | gsub("/(Users|home)/[^/\\s]+"; "~")
  | gsub("[^\\s\"\u0027]*\\.claude(/[^\\s\"\u0027]*)?"; "[path]")
  | gsub("[[:cntrl:]]"; " ");
def subj_clean: scrub | gsub("[;&|`<>\\\\]|\\$[({]"; "") | .[0:200];
def cmdlike: test("(^|\\s)(&&|\\|\\||[|;`]|[0-9]?>>?)(\\s|$)|[;`]\\s|`|\\$[({]|^\\s*(sudo|sh|bash|zsh|dash|rm|curl|wget|chmod|chown|ssh|scp|docker|npx|python3?|eval|exec)\\s+\\S");
def secs($d): if $d == "-" then null else ($d[0:-1] | tonumber) * ({"s":1,"m":60,"h":3600,"d":86400}[$d[-1:]]) end;
def oid($k; $subj): $k + ":" + ($subj | ltrimstr($k + ":"));
def owner($o; $e; $subj):
  if $o.owner == "self" then $o.kind + ":" + $subj
  elif $o.owner == "subject-session" then "session:" + ($subj | split(":")[0])
  elif $o.owner == "data-session" then
    (($e.data.session_id // "") | if type == "string" and length > 0 then "session:" + subj_clean else "operator" end)
  else "operator" end;
def title($e; $subj):
  (($e.data.title // "") | if type == "string" then scrub else "" end) as $t
  | if ($t | length) == 0 or ($t | cmdlike) then $subj else $t[0:120] end;
def link($e; $subj):
  (($e.data.link // "") | if type == "string" and startswith("https://") then . else "" end) as $dl
  | ([$subj | capture("^(?<r>[^/ ]+/[^/ #]+)#(?<n>[0-9]+)$")] | first) as $m
  | if $dl != "" then $dl elif $m != null then "https://github.com/\($m.r)/pull/\($m.n)" else "" end;
def deadline($o; $e):
  ($e.data.deadline_ts // "") as $dd
  | if ($dd | type) == "string" and ($dd | test(ts_re)) then $dd
    else secs($o.deadline) as $s | if $s == null then "" else (($e.ts | fromdateiso8601) + $s | todate) end end;
def outlives($o; $e):
  if $o.outlives == "-" then false
  else ($o.outlives | split("=")) as $p
    | (($e.data[$p[0]] // "") | if type == "string" then test("^(" + ($p[1:] | join("=")) + ")$") else false end) end;

# opens_when (harbor#1049): an open event whose data does not match is no open event at all, so it counts as unmatched.
def opens($o; $e):
  if $o.opens_when == "-" then true
  else ($o.opens_when | split("=")) as $p
    | (($e.data[$p[0]] // "") | if type == "string" then test("^(" + ($p[1:] | join("=")) + ")$") else false end) end;

def key($t): $t.event + "|" + $t.obligation + "|" + $t.to;
def apply($t):
  (if $t.event != "" then .seen[key($t)] = ts_e($t.ts) else . end)
  | if $t.to == "pending" then .pending[$t.obligation] = {ts: $t.ts, event: $t.event, closed_by: (if $t.closed_by == null then $t.event else $t.closed_by end)}
    elif $t.to == "open" then
      .rows[$t.obligation] = {id: $t.obligation, kind: $t.kind, subject: $t.subject, repo: $t.repo, owner: $t.owner,
        title: $t.title, link: $t.link, opened_ts: $t.ts, deadline_ts: $t.deadline_ts, state: "open",
        closed_by: "", closed_ts: "", outlives: $t.outlives}
      | .live[$t.obligation] = true | del(.pending[$t.obligation])
    elif .rows[$t.obligation] == null then .
    elif $t.to == "overdue" then .rows[$t.obligation].state = "overdue"
    else .rows[$t.obligation] |= (.state = $t.to | .closed_by = $t.closed_by | .closed_ts = $t.ts) | del(.live[$t.obligation]) end;
# A transition whose (event, obligation, to) key is already in the ledger is the replay of a killed run.
def emit($t):
  if $t.event != "" and .seen[key($t)] != null then .
  else (1000000000 + .n | tostring) as $k | .out[$k] = $t | .n += 1 | apply($t) end;   # an object, not an array: jq copies an array on every append

def stop_abandon($e):
  [(.live | keys_unsorted[]) as $id | .rows[$id]
      | select(.owner == "session:" + $e.subject and (.outlives | not)
          and (.kind as $k | [$reg[] | select(.kind == $k and .on_stop == "abandon")] | length > 0)) | .id] as $ids
  | reduce $ids[] as $id (.; emit({ts: $e.ts, obligation: $id, to: "abandoned", event: $e.id, closed_by: $e.id}));

def step($raw):
  ($raw | .subject |= subj_clean) as $e
  | ([$reg[] | select(.open != "-" and (. as $r | $e.kind | test("^(" + $r.open + ")$")) and opens(.; $e))] | first) as $o
  | if $o != null then
      oid($o.kind; $e.subject) as $id
      | ($id | ltrimstr($o.kind + ":")) as $subj
      | if is_live($id) then .
        else .pending[$id] as $p
          | [{ts: $e.ts, obligation: $id, to: "open", event: $e.id, kind: $o.kind, subject: $subj, repo: $e.repo,
              owner: owner($o; $e; $subj), title: title($e; $subj), link: link($e; $subj),
              deadline_ts: deadline($o; $e), outlives: outlives($o; $e)}][0] as $t
          | emit($t)
          # a close that came first applies if the open is not later than it: otherwise it was meant for an earlier life
          | if $p != null and $p.ts >= $e.ts then emit({ts: $p.ts, obligation: $id, to: "closed", event: $p.event, closed_by: $p.closed_by}) else . end
        end
    else
      ([$reg[] | select(.close != "-" and (. as $r | $e.kind | test("^(" + $r.close + ")$")))] | first) as $c
      | if $c == null then .unmatched += 1
        else oid($c.kind; $e.subject) as $id
          | (if is_live($id) then emit({ts: $e.ts, obligation: $id, to: "closed", event: $e.id, closed_by: $e.id})
             elif .rows[$id] == null then emit({ts: $e.ts, obligation: $id, to: "pending", event: $e.id, closed_by: $e.id})
             else . end)
          | if $c.kind == "session" then stop_abandon($e) else . end
        end
    end;

def overdue_pass:
  [(.live | keys_unsorted[]) as $id | .rows[$id] | select(.state == "open" and .deadline_ts != ""
      and (.deadline_ts | fromdateiso8601) < $now) | .id] as $ids
  | reduce $ids[] as $id (.; emit({ts: $nowiso, obligation: $id, to: "overdue", event: ""}));

# What a run hands back, one JSON document per line so that nothing after it has to parse the big ones: the current.json
# document, the state the snapshot keeps, a summary, then each transition to append. A closed row, a seen key and a
# pending close older than the retention window are dropped here, once, at the end.
def finish:
  ($now - $retain) as $cut
  | .rows |= del(.[] | select(((.state | live) or ts_e(.closed_ts) >= $cut) | not))
  | .seen |= del(.[] | select(. < $cut))
  | .pending |= del(.[] | select(ts_e(.ts) < $cut))
  | {generated_ts: $nowiso, obligations: ([.rows[] | del(.outlives)] | sort_by(.opened_ts, .id))},
    {rows: .rows, seen: .seen, pending: .pending},
    {unmatched: .unmatched},
    (.out[]);
'
# The fold: reads $led (ledger), $ev (valid new events), the register and the clock.
# shellcheck disable=SC2016
FOLD="$DEFS"'
$snap[0].state | (.live = (.rows | with_entries(select(.value.state | live) | .value = true)) | .out = {} | .n = 0 | .unmatched = 0)
| reduce $led[] as $t (.; apply($t))
| reduce $ev[] as $e (.; step($e))
| overdue_pass
| finish'

# The register as JSON, from the TSV that check_kinds has passed.
# shellcheck disable=SC2016
REGJSON='$regraw | split("\n") | map(select((startswith("#") | not) and length > 0) | split("\t")) | map(select(.[0] != "kind"))
  | map({kind: .[0], open: .[1], close: .[2], deadline: .[3], owner: .[4], on_stop: .[5], outlives: .[6], reconcile: .[7], opens_when: .[8]})'

# Valid events only: a complete line that is not an event object, or has no id, is counted and skipped, never fatal. An
# event with no id could not be told from its own replay (the ledger's key would be empty), so it opens nothing.
# shellcheck disable=SC2016
VALID='
def ts_re: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$";
fromjson? | select(type == "object" and (.id | type) == "string" and (.id | length) > 0 and (.kind | type) == "string"
    and (.subject | type) == "string" and (.subject | length) > 0 and (.ts | type) == "string" and (.ts | test(ts_re)))
| .data = (if (.data | type) == "object" then .data else {} end)
| .repo = (if (.repo | type) == "string" then .repo else "" end)'


# The reconciler's decisions: $src is what the sources answered, $lo the register's `leftover` row or null,
# $grace the age a row needs before a dead session may close it. A row flips only on an answer: a source
# with ok:false, or one that was not asked, gives no verdict. Every transition carries event "" and
# closed_by "reconcile", and the source that said so.
# shellcheck disable=SC2016
# The pull request a row stands for: a pr rows own subject, else the one its link names (an approval to merge it).
# shellcheck disable=SC2016
PRKEY='def pr_key: if (.subject | test("^[^/ ]+/[^/ #]+#[0-9]+$")) then .subject
  else ([(.link // "") | capture("^https://github.com/(?<r>[A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/(?<n>[0-9]+)$")][0]
        | if . == null then "" else "\(.r)#\(.n)" end) end;'
# shellcheck disable=SC2016
RECON="$DEFS$PRKEY"'
def terminal: . as $s | ["done", "stopped", "failed", "error", "completed", "cancelled"] | any(.[]; . == $s);
def age($r): $now - ($r.opened_ts | fromdateiso8601);
def sid_of($owner): if ($owner | startswith("session:")) then $owner[8:] else "" end;
def alive($sid):
  (($src.sessions.live // []) | any(.[]; . == $sid))
  or (($src["claude-agents"].agents // []) | any(.[]; .sessionId == $sid and ((.state // "") | terminal | not)));
# Dead needs BOTH answers: a background session has no registry file, only a line in `claude agents`.
def dead($sid): $sid != "" and ($src.sessions.ok // false) and ($src["claude-agents"].ok // false) and (alive($sid) | not);
# A row that outlives its owners stop (a Workflow) is judged only once its deadline has passed AND the dead owners transcript has not
# been written since: nothing then says it still runs, and the stop that spared it was long ago. A missing transcript counts as quiet.
def lapsed($r):
  $r.deadline_ts != "" and ($r.deadline_ts | fromdateiso8601) < $now
  and ((($src.sessions.transcripts // {})[sid_of($r.owner)] // 0) as $w
       | $w <= ($r.deadline_ts | fromdateiso8601) or $now - $w >= $quiet);
def sources_of($k): $k.reconcile | split(",");
def agent_for($subj): (($src["claude-agents"].agents // []) | map(select(.id == $subj or .sessionId == $subj)) | first);
def verdict($r; $k):
  if $k.reconcile == "sessions" then
    (if age($r) >= $grace and dead($r.subject) then {to: "closed", source: "sessions"} else null end)
  elif $k.reconcile == "claude-agents" then
    agent_for($r.subject) as $a
    | if ($src["claude-agents"].ok // false) | not then null
      elif $a != null then (if ($a.state // "") | terminal then {to: "closed", source: "claude-agents"} else null end)
      elif age($r) >= $grace and dead(sid_of($r.owner)) then {to: "abandoned", source: "owner-session"}
      else null end
  elif $k.reconcile == "owner-session" then
    (if $k.on_stop == "abandon" and (($r.outlives | not) or lapsed($r)) and age($r) >= $grace and dead(sid_of($r.owner))
     then {to: "abandoned", source: "owner-session"} else null end)
  elif $k.reconcile == "gh-pr" then
    (if ($src["gh-pr"].answers[$r.subject] // "") | IN("MERGED", "CLOSED") then {to: "closed", source: "gh-pr"} else null end)
  elif $k.reconcile == "gh-run" then
    (if ($src["gh-run"].answers[$r.subject] // "") == "completed" then {to: "closed", source: "gh-run"} else null end)
  elif sources_of($k) | any(.[]; . == "approval-queue") then
    (if ($src["approval-queue"].closed // []) | any(.[]; . == $r.subject) then {to: "closed", source: "approval-queue"}
     elif (sources_of($k) | any(.[]; . == "gh-pr")) and (($src["gh-pr"].answers[$r | pr_key] // "") | IN("MERGED", "CLOSED")) then {to: "closed", source: "gh-pr"}
     else null end)
  else null end;

# Leftovers are opened and closed only by this pass: a RISK/DECIDE row in the sweep record opens one, and the
# row being gone from the next record closes it.
def leftover:
  if $lo == null or (($src.sweep.ok // false) | not) then .
  else
    ($src.sweep.rows) as $want
    | ($want | map(.subject)) as $names
    | (secs($lo.deadline) | if . == null then "" else ($now + .) | todate end) as $dl
    | reduce $want[] as $w (.;
        if is_live(oid("leftover"; $w.subject)) then .
        else emit({ts: $nowiso, obligation: oid("leftover"; $w.subject), to: "open", event: "", kind: "leftover", subject: $w.subject,
                   repo: "", owner: "operator", title: $w.title, link: "", deadline_ts: $dl, outlives: false}) end)
    | [(.live | keys_unsorted[]) as $id | {key: $id, value: .rows[$id]} | select(.value.kind == "leftover"
          and (.value.subject as $s | ($names | any(.[]; . == $s)) | not))] as $gone
    | reduce $gone[] as $r
        (.; emit({ts: $nowiso, obligation: $r.key, to: "closed", event: "", closed_by: "reconcile", source: "sweep"}))
  end;

$snap[0].state | (.live = (.rows | with_entries(select(.value.state | live) | .value = true)) | .out = {} | .n = 0 | .unmatched = 0)
| reduce $led[] as $t (.; apply($t))
| [(.live | keys_unsorted[]) as $id | {key: $id, value: .rows[$id]}] as $livers
| reduce $livers[] as $e (.;
    ([$reg[] | select(.kind == $e.value.kind)] | first) as $k
    | if $k == null then .
      else [verdict($e.value; $k)][0] as $v
        | if $v == null then .
          else emit({ts: $nowiso, obligation: $e.key, to: $v.to, event: "", closed_by: "reconcile", source: $v.source}) end
      end)
| leftover
| finish'

# ── the reconciler's sources ────────────────────────────────────────────────────────────────────────
# One bounded read per source, and only of what a live row asks about. Each stub knob swaps the binary,
# never the logic: a suite points them at fixtures and never at the real gh, claude or registry.
GH="${HARBOR_STATUS_OBLIGATION_GH:-gh}"
CLAUDE="${HARBOR_STATUS_OBLIGATION_CLAUDE:-claude}"
SESSIONS_BIN="${HARBOR_STATUS_OBLIGATION_SESSIONS:-}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SWEEP="${HARBOR_STATUS_OBLIGATION_HOUSEKEEPING:-$CFG/.helm-sweep.jsonl}"
TRANSCRIPTS="${HARBOR_STATUS_OBLIGATION_TRANSCRIPTS:-$CFG/projects}"   # <project>/<session id>.jsonl: when a dead session last wrote
READ_TO="${HARBOR_STATUS_OBLIGATION_READ_TIMEOUT:-10}"   # seconds one read may take
BUDGET="${HARBOR_STATUS_OBLIGATION_BUDGET:-40}"          # seconds every read of one run may take together
GRACE="${HARBOR_STATUS_OBLIGATION_GRACE:-300}"           # a registry file lags exec: a younger row is not judged dead
QUIET="${HARBOR_STATUS_OBLIGATION_QUIET:-86400}"         # seconds a dead owner may be silent before its outliving row lapses even though it wrote after the deadline
RETAIN="${HARBOR_STATUS_OBLIGATION_RETAIN:-1296000}"       # seconds a closed row, and the keys of its transitions, are kept: bus retention (14d) + 1d
LOCK_GRACE="${HARBOR_STATUS_OBLIGATION_LOCK_GRACE:-10}"  # a lock whose owner cannot be read is live until it is this old
LOCK_MAX="${HARBOR_STATUS_OBLIGATION_LOCK_MAX:-900}"     # a lock older than this is taken over, whatever its pid says
GH_MAX=25                                                # gh reads per source per run, oldest row first
RECORD_MAX_AGE=129600                                    # a sweep record older than 36h answers nothing
for _v in READ_TO BUDGET GRACE QUIET RETAIN LOCK_GRACE LOCK_MAX; do
  eval "_x=\$$_v"; case "$_x" in ''|*[!0-9]*) log_fail "HARBOR_STATUS_OBLIGATION_$_v is '$_x', want whole seconds"; log_fix "unset HARBOR_STATUS_OBLIGATION_$_v"; log_end || :; exit 2 ;; esac
done

bounded() { # <seconds> <command> [args…] — its stdout; non-zero when it failed or ran over
  # THE READ GOES TO A FILE, NEVER A PIPE. `$(…)` waits for every holder of the pipe's write end, so a command whose grandchild
  # outlives the kill (`sh -c 'sleep 25'`: the alarm kills the sh, the sleep keeps stdout) held the caller for the sleep's whole
  # life and was then recorded as "timed out after 2s" (measured 27s on this box, no timeout(1), harbor#1115). A file has no
  # reader to wait for. The perl arm also kills the whole process group, so nothing is left running behind a timed-out read.
  _bs="$1"; shift; _bo="$T/bounded.out"; _brc=0
  if command -v timeout >/dev/null 2>&1; then timeout "$_bs" "$@" > "$_bo" || _brc=$?
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$_bs" "$@" > "$_bo" || _brc=$?
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'my $t = shift; my $p = fork; defined $p or exit 127;
      if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
      $SIG{ALRM} = sub { kill "KILL", -$p; waitpid($p, 0); exit 142 };
      alarm $t; waitpid($p, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$_bs" "$@" > "$_bo" || _brc=$?
  else return 125; fi
  cat "$_bo"; rm -f "$_bo"; return "$_brc"
}
slot() { # seconds the next read may take: the per-read cap, or what is left of the budget, or 0
  _left=$((BUDGET - ($(date +%s) - T_START)))
  [ "$_left" -gt 0 ] || { printf 0; return 0; }
  [ "$_left" -lt "$READ_TO" ] && printf '%s' "$_left" || printf '%s' "$READ_TO"
}
why() { # <exit code> <seconds> — the reason a read gives, never the tool's own words (they can carry paths)
  case "$1" in 124|137|142) printf 'timed out after %ss' "$2" ;; 125) printf 'no timeout(1), gtimeout or perl to bound the read' ;; *) printf 'exited %s' "$1" ;; esac
}
src_set() { # <source> <true|false> <reason> [extra-json] — what one source answered, into $T/src/<source>.json
  _x="${4:-}"; [ -n "$_x" ] || _x='{}'
  jq -n -c --argjson ok "$2" --arg reason "$3" --argjson extra "$_x" '{ok: $ok, reason: $reason} + $extra' > "$T/src/$1.json"
}
live_rows() { # <source> — the subjects of live rows whose kind the register reconciles by <source>, oldest first; gh-pr: the PR each stands for
  jq -r --arg s "$1" --slurpfile reg "$T/reg.json" "$PRKEY"'
    ($reg[0] | map(select(.reconcile | split(",") | any(.[]; . == $s)) | .kind)) as $kinds
    | [.obligations[] | select((.state | IN("open", "overdue")) and (.kind as $k | $kinds | any(.[]; . == $k)))]
    | sort_by(.opened_ts) | .[] | (if $s == "gh-pr" then pr_key else .subject end) | select(length > 0)' "$CURRENT"
}

read_sessions() {
  _to="$(slot)"; [ "$_to" -gt 0 ] || { src_set sessions false "read budget spent"; return 0; }
  if [ -n "$SESSIONS_BIN" ]; then _rc=0; _out="$(bounded "$_to" "$SESSIONS_BIN" --json </dev/null 2>/dev/null)" || _rc=$?
  elif [ ! -d "${HARBOR_SESSIONS_DIR:-$CFG/sessions}" ]; then src_set sessions false "no session registry on this box"; return 0
  else _rc=0; _out="$(bounded "$_to" sh "$HERE/fleet-sessions.sh" --json </dev/null 2>/dev/null)" || _rc=$?; fi
  [ "$_rc" -eq 0 ] || { src_set sessions false "$(why "$_rc" "$_to")"; return 0; }
  printf '%s' "$_out" | jq -e 'type == "array"' >/dev/null 2>&1 || { src_set sessions false "the registry read was not a list"; return 0; }
  src_set sessions true "" "$(printf '%s' "$_out" | jq -c '{live: [.[] | .sessionId | select(type == "string")]}')"
}

# When each candidate session last wrote its transcript (epoch), into the sessions answer: the one other fact that says a dead
# owner left nothing running (see lapsed). Only ids the registry no longer lists are looked up; an id that is not a plain token, or
# has no transcript under $TRANSCRIPTS/<project>/, is simply absent, which the verdict reads as quiet.
read_transcripts() {
  jq -e '.ok == true' "$T/src/sessions.json" >/dev/null 2>&1 || return 0
  : > "$T/tr.tsv"
  for _tid in $(jq -r --slurpfile live "$T/src/sessions.json" '.[] | select(. as $c | ($live[0].live | any(.[]; . == $c)) | not)' "$T/candidates.json"); do
    case "$_tid" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
    _tf="$(find "$TRANSCRIPTS" -maxdepth 2 -name "$_tid.jsonl" -type f 2>/dev/null | head -n 1)"
    [ -n "$_tf" ] || continue
    _tm="$(fs_mtime "$_tf")"; [ -z "$_tm" ] || printf '%s\t%s\n' "$_tid" "$_tm" >> "$T/tr.tsv"
  done
  jq -R -s -c --slurpfile cur "$T/src/sessions.json" 'split("\n") | map(select(length > 0) | split("\t") | {key: .[0], value: (.[1] | tonumber)})
    | $cur[0] + {transcripts: from_entries}' "$T/tr.tsv" > "$T/src/sessions.new" && mv -f "$T/src/sessions.new" "$T/src/sessions.json"
}

read_agents() {
  _to="$(slot)"; [ "$_to" -gt 0 ] || { src_set claude-agents false "read budget spent"; return 0; }
  _rc=0; _out="$(bounded "$_to" "$CLAUDE" agents --json --all </dev/null 2>/dev/null)" || _rc=$?
  [ "$_rc" -eq 0 ] || { src_set claude-agents false "$(why "$_rc" "$_to")"; return 0; }
  printf '%s' "$_out" | jq -e 'type == "array"' >/dev/null 2>&1 || { src_set claude-agents false "claude agents did not print a list"; return 0; }
  src_set claude-agents true "" "$(printf '%s' "$_out" | jq -c '{agents: [.[] | select(type == "object")
    | {id: (.id // "" | tostring), sessionId: (.sessionId // "" | tostring), state: (.state // "" | tostring)}]}')"
}

# The approvals queue (harbor#1018, ship contract §5a.3): an id closed there (approved, or refused by the operator) is
# closed here. One local file, so no budget slot; a queue that is not JSON lines answers ok:false and closes nothing.
read_queue() {
  _q="$HOME/.local/state/harbor/approvals/queue.jsonl"
  [ -f "$_q" ] || { src_set approval-queue true "no approvals queue on this box" '{"closed": []}'; return 0; }
  _c="$(jq -c -n '[inputs | select(type == "object" and .closed == true and (.id | type) == "string") | .id] | unique | {closed: .}' "$_q" 2>/dev/null)" \
    || { src_set approval-queue false "$_q is not JSON lines"; return 0; }
  src_set approval-queue true "" "$_c"
}

# A PR merged or closed on GitHub runs no local hook, so the read that saw it is the producer of pr.merged and pr.closed
# (harbor#1367, CONTRACTS/event-kinds.tsv): one event per pr row this run closed by gh-pr. Emit never fails the run, and
# the fold reading the event back closes nothing twice.
publish_pr_closes() {
  [ -f "$HERE/event-bus.sh" ] || return 0
  jq -r 'select(.source == "gh-pr" and .to == "closed" and (.obligation | startswith("pr:"))) | .obligation | ltrimstr("pr:")' "$T/batch" 2>/dev/null \
  | while IFS= read -r _s; do
      case "$(awk -F'\t' -v s="$_s" '$1 == s { print $2; exit }' "$T/ans.gh-pr" 2>/dev/null)" in
        MERGED) _kind=pr.merged ;; CLOSED) _kind=pr.closed ;; *) continue ;;
      esac
      _r="${_s%#*}"
      sh "$HERE/event-bus.sh" emit "$_kind" "$_s" --src status-obligations --repo "${_r##*/}" </dev/null >/dev/null 2>&1 || :
    done
}

# One `gh` read per live row, capped. A row whose read failed gets no answer, so it flips nothing; the source is
# ok:false when any read failed, and says how many.
read_gh() { # <gh-pr|gh-run>
  _src="$1"; live_rows "$_src" | head -n "$GH_MAX" > "$T/list.$_src"
  : > "$T/ans.$_src"; _n=0; _bad=0; _last=""
  while IFS= read -r _s; do
    [ -n "$_s" ] || continue
    case "$_src" in
      gh-pr)  printf '%s' "$_s" | jq -R -e 'test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+#[0-9]+$")' >/dev/null 2>&1 || continue ;;
      gh-run) printf '%s' "$_s" | jq -R -e 'test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+:[0-9]+:.+$")' >/dev/null 2>&1 || continue ;;
    esac
    _n=$((_n + 1)); _to="$(slot)"
    [ "$_to" -gt 0 ] || { _bad=$((_bad + 1)); _last="read budget spent"; continue; }
    _rc=0
    if [ "$_src" = gh-pr ]; then
      _a="$(bounded "$_to" "$GH" pr view "${_s##*#}" -R "${_s%#*}" --json state --jq .state </dev/null 2>/dev/null)" || _rc=$?
      case "$_a" in MERGED|CLOSED|OPEN) ;; *) [ "$_rc" -ne 0 ] || _rc=1 ;; esac
    else
      _rest="${_s#*:}"; _json="$(bounded "$_to" "$GH" run view "${_rest%%:*}" -R "${_s%%:*}" --json status,jobs </dev/null 2>/dev/null)" || _rc=$?
      _a=""
      [ "$_rc" -ne 0 ] || _a="$(printf '%s' "$_json" | jq -r -e --arg job "${_rest#*:}" '
        if (.status | type) != "string" then error("no status")
        elif .status == "completed" or ([.jobs[]? | select(.name == $job and .status == "completed")] | length > 0) then "completed"
        else "running" end' 2>/dev/null)" || _rc=1
    fi
    if [ "$_rc" -eq 0 ]; then printf '%s\t%s\n' "$_s" "$_a" >> "$T/ans.$_src"
    else _bad=$((_bad + 1)); _last="$(why "$_rc" "$_to")"; fi
  done < "$T/list.$_src"
  _ans="$(jq -R -s -c 'split("\n") | map(select(length > 0) | split("\t")) | map({key: .[0], value: .[1]}) | {answers: from_entries}' "$T/ans.$_src")"
  if [ "$_n" -eq 0 ]; then src_set "$_src" true "no live rows to check" "$_ans"
  elif [ "$_bad" -eq 0 ]; then src_set "$_src" true "" "$_ans"
  else src_set "$_src" false "$_bad of $_n reads failed (last: $_last)" "$_ans"; fi
}

# The sweep record: harbor-clean.sh --record writes the rows (.jsonl) and, beside them, a summary line carrying the
# epoch it started at. Only RISK and DECIDE rows are leftovers; $HOME becomes ~ so no row carries an absolute path.
read_sweep() {
  EMPTYROWS='{"rows": []}'
  _sum="${SWEEP%.jsonl}"
  [ -f "$SWEEP" ] && [ -f "$_sum" ] || { src_set sweep false "no sweep record" "$EMPTYROWS"; return 0; }
  _at="$(sed -n 's/.* at=\([0-9][0-9]*\).*/\1/p' "$_sum" | head -n 1)"
  [ -n "$_at" ] || { src_set sweep false "the sweep record has no stamp" "$EMPTYROWS"; return 0; }
  [ $((NOW_E - _at)) -le "$RECORD_MAX_AGE" ] || { src_set sweep false "the sweep record is $(((NOW_E - _at) / 3600))h old" "$EMPTYROWS"; return 0; }
  _rows="$(jq -R -c --arg home "$HOME" '
    def clean: (if $home != "" then split($home) | join("~") else . end) | gsub("[[:cntrl:]]"; " ") | .[0:160];
    fromjson? | select(type == "object" and (.verdict | IN("RISK", "DECIDE")) and (.class | type) == "string" and (.subject | type) == "string")
    | {subject: (.class + ":" + (.subject | clean)), title: ((.class + ": " + (.subject | clean)) | .[0:120])}' "$SWEEP")" \
    || { src_set sweep false "the sweep record could not be read" "$EMPTYROWS"; return 0; }
  src_set sweep true "" "$(printf '%s\n' "$_rows" | jq -s -c '{rows: map(select(. != null))}')"
}

# ── the passes ────────────────────────────────────────────────────────────────────────────────────
prepare() {
  check_kinds || return 2
  mkdir -p "$DIR" || { log_fail "cannot create $DIR"; log_fix "mkdir -p $DIR"; return 1; }
  T=""
  trap 'cleanup' EXIT
  trap 'cleanup; trap - EXIT; exit 130' INT TERM HUP
  _ac=0; acquire || _ac=$?
  [ "$_ac" -ne 1 ] || return 10
  [ "$_ac" -eq 0 ] || return 1
  T="$(mktemp -d "$DIR/.fold.XXXXXX")" || { log_fail "cannot create a scratch dir in $DIR"; log_fix "ls -ld $DIR"; return 1; }
  mkdir "$T/src"
  heal_ledger
  [ -e "$LEDGER" ] || : > "$LEDGER"
  jq -n -c --rawfile regraw "$KINDS" "$REGJSON" > "$T/reg.json" || { log_fail "could not read $KINDS"; log_nofix "tests/status/obligations/fold.test.sh"; return 1; }
  NOW_E="$(jq -n -r --arg t "$NOW" '$t | fromdateiso8601' 2>/dev/null)" || { log_fail "the clock $NOW is not YYYY-MM-DDTHH:MM:SSZ"; log_fix "unset HARBOR_STATUS_OBLIGATION_NOW"; return 1; }
}

# A run's result is one document per line (see finish): split, never parsed again. $T is inside $DIR, so the moves are renames.
split_result() { # <file> → $T/current.doc, $T/state.doc, $T/summary, $T/batch
  sed -n -e "1w $T/current.doc" -e "2w $T/state.doc" -e "3w $T/summary" -e "4,\$w $T/batch" "$1"
}

# The state to fold onto: the snapshot, and the ledger lines written after the byte it was taken at, into $T/snap.json
# and $T/led.tail. No snapshot, an unreadable one, or one that does not sit on a line of this ledger (the ledger was
# replaced) means the whole ledger is read. A ledger line that does not parse is skipped and counted into LEDGER_BAD.
load_state() {
  _from=0
  if [ -s "$SNAP" ]; then
    _lb="$(jq -r 'if .v == 1 and (.ledger_bytes | type) == "number" and (.state.rows | type) == "object" and (.state.seen | type) == "object"
      and (.state.pending | type) == "object" then .ledger_bytes else empty end' "$SNAP" 2>/dev/null || :)"
    case "$_lb" in ''|*[!0-9]*) log_warn "$SNAP is unreadable; rebuilding it from the whole ledger" ;; *)
      _size="$(wc -c < "$LEDGER" | tr -d ' ')"
      if [ "$_lb" -le "$_size" ] && { [ "$_lb" -eq 0 ] || [ "$(head -c "$_lb" "$LEDGER" | tail -c 1 | od -An -tx1 | tr -d ' \n')" = 0a ]; }; then _from="$_lb"
      else log_warn "$SNAP does not match $LEDGER (taken at byte $_lb of $_size); rebuilding it from the whole ledger"; fi ;;
    esac
  fi
  if [ "$_from" -gt 0 ]; then SNAPFILE="$SNAP"
  else SNAPFILE="$T/snap.json"; printf '{"state":{"rows":{},"seen":{},"pending":{}}}\n' > "$SNAPFILE"; fi
  tail -c +$((_from + 1)) "$LEDGER" > "$T/led.raw"
  jq -R -c 'fromjson? | select(type == "object" and (.obligation | type) == "string" and (.to | type) == "string"
      and (.event | type) == "string" and (.ts | type) == "string")' "$T/led.raw" > "$T/led.tail" \
    || { log_fail "could not read $LEDGER"; log_nofix "tests/status/obligations/fold.test.sh"; return 1; }
  _bad=$(( $(awk 'NF { n++ } END { print n + 0 }' "$T/led.raw") - $(wc -l < "$T/led.tail" | tr -d ' ') ))
  [ "$_bad" -le 0 ] || { LEDGER_SKIPPED=$((LEDGER_SKIPPED + _bad))
    log_warn "skipped $_bad ledger line(s) that do not parse; the rest of the ledger was folded (a bad line stays in $LEDGER, inert)"; }
}

# The ledger's own answer, beside the sources': ok:false for the run that skipped lines, gone again on the next clean one.
ledger_source() {
  if [ "$LEDGER_SKIPPED" -gt 0 ]; then
    _sj='{}'; [ ! -f "$SOURCES" ] || _sj="$(jq -c 'if type == "object" then . else {} end' "$SOURCES" 2>/dev/null)" || _sj='{}'
    printf '%s' "$_sj" | jq -c --arg r "$LEDGER_SKIPPED ledger line(s) did not parse and were skipped" --arg ts "$NOW" '. + {ledger: {ok: false, reason: $r, ts: $ts}}' \
      > "$DIR/.sources.tmp" && mv -f "$DIR/.sources.tmp" "$SOURCES" || log_warn "cannot write $SOURCES"
  elif [ -f "$SOURCES" ] && jq -e 'type == "object" and has("ledger")' "$SOURCES" >/dev/null 2>&1; then
    jq -c 'del(.ledger)' "$SOURCES" > "$DIR/.sources.tmp" && mv -f "$DIR/.sources.tmp" "$SOURCES" || log_warn "cannot write $SOURCES"
  fi
}

# A reconcile that failed leaves the PREVIOUS run's sources.json in place, and surface_pass would publish it as if it were this
# run's answer (harbor#1115). Say so beside the sources: ok:false makes `unread` true, so the statusline shows `⧗?` and the console
# lists it, until the next reconcile that completes rewrites the whole map. Written through $T, so it works when $DIR/.sources.tmp
# is the thing that could not be written.
stale_source() {
  _sj='{}'; [ ! -f "$SOURCES" ] || _sj="$(jq -c 'if type == "object" then . else {} end' "$SOURCES" 2>/dev/null)" || _sj='{}'
  printf '%s' "$_sj" | jq -c --arg r "the reconcile failed; the other entries are from an earlier run" --arg ts "$NOW" '. + {reconcile: {ok: false, reason: $r, ts: $ts}}' \
    > "$T/sources.stale" && mv -f "$T/sources.stale" "$SOURCES" || log_warn "cannot write $SOURCES"
}

fold_pass() {
  collect
  jq -R -c "$VALID" "$T/raw" > "$T/events" || { log_fail "could not read the new bus lines"; log_nofix "tests/status/obligations/fold.test.sh"; return 1; }
  load_state || return 1
  [ "${HARBOR_STATUS_OBLIGATION_FAULT:-}" != slow-read ] || sleep 3   # a suite's way to hold what a run read while another reads too
  jq -n -c --slurpfile snap "$SNAPFILE" --slurpfile led "$T/led.tail" --slurpfile ev "$T/events" --argjson reg "$(cat "$T/reg.json")" \
    --argjson now "$NOW_E" --arg nowiso "$NOW" --arg home "$HOME" --argjson retain "$RETAIN" "$FOLD" > "$T/result" \
    || { log_fail "the fold failed on $LEDGER or the new events; nothing was written"; log_nofix "tests/status/obligations/fold.test.sh"; return 1; }
  split_result "$T/result"
  if [ -s "$T/batch" ]; then
    if [ "${HARBOR_STATUS_OBLIGATION_FAULT:-}" = mid-ledger ]; then
      head -c $(($(wc -c < "$T/batch") - 5)) "$T/batch" >> "$LEDGER"; kill -9 "$$"
    fi
    cat "$T/batch" >> "$LEDGER" || { log_fail "cannot append to $LEDGER; the offset is not advanced"; log_fix "ls -l $LEDGER"; return 1; }
  fi
  write_current || return 1
  fault before-offset
  [ "${HARBOR_STATUS_OBLIGATION_FAULT:-}" != slow-commit ] || sleep 1   # a suite's way to keep a run uncommitted while another starts
  { cp "$T/offset.new" "$DIR/.offset.tmp" && mv -f "$DIR/.offset.tmp" "$OFFSET"; } \
    || { log_fail "cannot write $OFFSET; the next run replays these lines, which the ledger absorbs"; log_fix "ls -ld $DIR"; return 1; }
  NEW_OVERDUE="$(jq -s '[.[] | select(.to == "overdue")] | length' "$T/batch")"
  _read="$(wc -l < "$T/raw" | tr -d ' ')"; _valid="$(wc -l < "$T/events" | tr -d ' ')"
  _moves="$(jq -s -r 'map(.to) | group_by(.) | map("\(length) \(.[0])") | join(", ")' "$T/batch")"
  log_ok "read $_read lines ($_valid events), $(jq '.unmatched' "$T/summary") matched no register row; transitions: ${_moves:-none}"
}

write_current() { # $T/current.doc as current.json, then $T/state.doc as the snapshot, taken at the ledger's end
  mv -f "$T/current.doc" "$CURRENT" || { log_fail "cannot write $CURRENT; the offset is not advanced"; log_fix "ls -ld $DIR"; return 1; }
  { printf '{"v":1,"ledger_bytes":%s,"state":' "$(wc -c < "$LEDGER" | tr -d ' ')"; cat "$T/state.doc"; printf '}\n'; } > "$T/snapshot.new" \
    && mv -f "$T/snapshot.new" "$SNAP" || { log_fail "cannot write $SNAP; the offset is not advanced"; log_fix "ls -ld $DIR"; return 1; }
}

reconcile_pass() {
  T_START="$(date +%s)"
  _lo="$(jq -c 'map(select(.kind == "leftover")) | first' "$T/reg.json")"
  # Session ids a verdict would hang on: a session row's own id, and the owner of a row the register abandons with its owner.
  jq -c --slurpfile reg "$T/reg.json" '
    [.obligations[] | select(.state | IN("open", "overdue")) | . as $r
      | ($reg[0][] | select(.kind == $r.kind)) as $k
      | if $k.reconcile == "sessions" then $r.subject
        elif ($k.reconcile | IN("owner-session", "claude-agents")) and ($r.owner | startswith("session:")) then $r.owner[8:]
        else empty end] | unique' "$CURRENT" > "$T/candidates.json"
  _cand="$(jq 'length' "$T/candidates.json")"
  if [ "$_cand" -gt 0 ]; then read_sessions; read_transcripts; else src_set sessions true "no live rows to check"; fi
  _need=0
  [ -z "$(live_rows claude-agents)" ] || _need=1
  if [ "$_need" -eq 0 ] && [ "$_cand" -gt 0 ] && jq -e '.ok == true' "$T/src/sessions.json" >/dev/null 2>&1 \
     && jq -e --slurpfile live "$T/src/sessions.json" '[.[] | select(. as $c | ($live[0].live | any(.[]; . == $c)) | not)] | length > 0' "$T/candidates.json" >/dev/null 2>&1; then
    _need=1
  fi
  if [ "$_need" -eq 1 ]; then read_agents; else src_set claude-agents true "no live rows to check" '{"agents": []}'; fi
  read_gh gh-pr
  read_gh gh-run
  if [ -n "$(live_rows approval-queue)" ]; then read_queue; else src_set approval-queue true "no live rows to check" '{"closed": []}'; fi
  if [ -n "$_lo" ] && [ "$_lo" != null ]; then read_sweep; else src_set sweep true "no leftover kind in the register"; fi
  for _f in "$T"/src/*.json; do jq -c --arg n "$(basename "$_f" .json)" '{($n): .}' "$_f"; done | jq -s -c 'add // {}' > "$T/src.json"
  load_state || return 1
  jq -n -c --slurpfile snap "$SNAPFILE" --slurpfile led "$T/led.tail" --argjson reg "$(cat "$T/reg.json")" --slurpfile src "$T/src.json" --argjson lo "$_lo" \
    --argjson now "$NOW_E" --argjson grace "$GRACE" --argjson quiet "$QUIET" --arg nowiso "$NOW" --arg home "$HOME" --argjson retain "$RETAIN" '$src[0] as $src | '"$RECON" > "$T/rresult" \
    || { log_fail "the reconcile failed on $LEDGER or a source answer; nothing was written"; log_nofix "tests/status/obligations/reconcile.test.sh"; return 1; }
  split_result "$T/rresult"
  if [ -s "$T/batch" ]; then
    cat "$T/batch" >> "$LEDGER" || { log_fail "cannot append to $LEDGER"; log_fix "ls -l $LEDGER"; return 1; }
    publish_pr_closes
  fi
  fault after-reconcile-ledger
  write_current || return 1
  # What each source answered, for `harbor status obligations --json` (§3 `sources`): the attempt, not the last success.
  jq --arg ts "$NOW" 'to_entries | map({key, value: {ok: .value.ok, reason: .value.reason, ts: $ts}}) | from_entries' "$T/src.json" > "$DIR/.sources.tmp" \
    && mv -f "$DIR/.sources.tmp" "$SOURCES" || { log_fail "cannot write $SOURCES"; log_fix "ls -ld $DIR"; return 1; }
  _moves="$(jq -s -r 'map("\(.to) by \(.source)") | group_by(.) | map("\(length) \(.[0])") | join(", ")' "$T/batch")"
  _dark="$(jq -r 'to_entries | map(select(.value.ok | not) | .key) | join(", ")' "$T/src.json")"
  log_ok "reconciled: ${_moves:-nothing to flip}${_dark:+; no answer from $_dark}"
}

# What the box reads between runs, from the state this run just wrote (see SURFACES above). A run that cannot write either one
# says so and fails nothing: the statusline then ages the old cache to `⧗?`, which is the honest state.
surface_pass() {
  _src='{}'; [ ! -f "$SOURCES" ] || _src="$(jq -c 'if type == "object" then . else {} end' "$SOURCES" 2>/dev/null)" || _src='{}'
  jq -c --argjson now "$NOW_E" --argjson red "$RED_AFTER_S" --argjson src "$_src" '
    def ts($t): try ($t | fromdateiso8601) catch 0;
    [.obligations[] | select(.state == "overdue")] as $od
    | {at: $now, live: ([.obligations[] | select(.state == "open" or .state == "overdue")] | length), overdue: ($od | length),
       overdue_since: ([$od[] | ts(.deadline_ts)] | min // 0), unread: ($src | any(.[]; .ok == false)),
       you: ([.obligations[] | select((.state == "open" or .state == "overdue")
                and .owner == "operator" and (.kind == "intent" or .kind == "approval"))]
             | sort_by(.opened_ts) | .[0:8]
             | map({k: .kind, o: (.state == "overdue"),
                    t: (.title | .[0:90])})),
       red: [$od[] | select(($now - ts(.deadline_ts)) > $red) | .id] | sort}' "$CURRENT" > "$T/surface.json" \
    || { log_warn "could not read $CURRENT; no statusline cache or receipt written"; return 0; }
  mkdir -p "$CACHE_DIR/checks" 2>/dev/null || { log_warn "cannot create $CACHE_DIR/checks; no statusline cache or receipt written"; return 0; }
  jq -c 'del(.red)' "$T/surface.json" > "$CACHE_DIR/.status-obligations.tmp.$$" && mv -f "$CACHE_DIR/.status-obligations.tmp.$$" "$CACHE_DIR/status-obligations.json" \
    || { rm -f "$CACHE_DIR/.status-obligations.tmp.$$"; log_warn "cannot write $CACHE_DIR/status-obligations.json"; }
  jq -r '.red[]' "$T/surface.json" > "$T/red.ids"
  if [ -s "$T/red.ids" ]; then
    # one id per argument, never word-split: an obligation id holds `#`, `:` and `/`
    set --; while IFS= read -r _id; do set -- "$@" "$_id"; done < "$T/red.ids"
    log_receipt "$CACHE_DIR/checks" status.obligations red "$@" || log_warn "no receipt written to $CACHE_DIR/checks"
    log_warn "[check:status.obligations] $# row(s) are more than 24h past their deadline: harbor status obligations --print"
  else
    log_receipt "$CACHE_DIR/checks" status.obligations green || log_warn "no receipt written to $CACHE_DIR/checks"
  fi
}

run() {
  log_head "$MODE"
  _pc=0; prepare || _pc=$?
  [ "$_pc" -ne 10 ] || return 0
  [ "$_pc" -eq 0 ] || return "$_pc"
  NEW_OVERDUE=0; _rr=0
  fold_pass || return 1
  case "$MODE" in
    reconcile) reconcile_pass || _rr=1 ;;
    # A row going overdue is the moment to ask the real state; HARBOR_STATUS_OBLIGATION_ON_OVERDUE=off keeps a fold-only run offline.
    fold) if [ "$NEW_OVERDUE" -gt 0 ] && [ "${HARBOR_STATUS_OBLIGATION_ON_OVERDUE:-on}" != off ]; then
            log_note "$NEW_OVERDUE row(s) went overdue; asking the sources"; reconcile_pass || _rr=1
          fi ;;
  esac
  [ "$_rr" -eq 0 ] || stale_source
  ledger_source
  surface_pass
  return "$_rr"
}

EXIT_RC=0; run || EXIT_RC=$?
log_end || :
exit "$EXIT_RC"
