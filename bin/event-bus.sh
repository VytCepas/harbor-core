#!/usr/bin/env sh
# event-bus.sh (harbor#1043, E1) — the local append-only event bus: one JSON line per event.
#
#   event-bus.sh emit <kind> <subject> [--src S] [--repo R] [--cause ID] [--data JSON]
#   event-bus.sh wait '<grep -E pattern>' --timeout N [--since-offset F] [--consumer NAME]
#   event-bus.sh since <offset-file> [--consumer NAME]
#   event-bus.sh tail [N]
#   event-bus.sh prune
#   event-bus.sh dispatch|on|pull|subscribe ...       → bin/event-dispatch.sh (harbor#1044, E2)
#   event-bus.sh ci <owner/repo>#<n> [--timeout S]    → bin/ci-wait.sh: a PR's CI verdict, woken by ci.job.done (harbor#1367)
# Bus: ${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}/YYYY-MM-DD.jsonl, the date in UTC.
# emit always exits 0 and prints the id; wait exits 0 on a match (printing the line), 3 at the
# deadline; 2 is a usage error. Design, schema and robustness rules: docs/design/events.md.
# The security floor never depends on this file.

# Not $(dirname): a hook will run this (F15, harbor#813).
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
if [ -f "$HERE/log-lib.sh" ]; then
  . "$HERE/log-lib.sh"
else
  # emit never fails its caller, even with its library gone.
  printf 'event-bus: %s/log-lib.sh is missing — nothing was done\n' "$HERE" >&2
  [ "${1-}" = emit ] && exit 0
  exit 2
fi
set -eu
umask 077
LC_ALL=C; export LC_ALL   # bytes, not characters: the cap, ${#v} and the case patterns count bytes
LOG_FD=2   # stdout is data: an id, event lines
log_init event-bus

DIR="${HARBOR_EVENT_DIR:-$HOME/.local/state/harbor/events}"
CAP=4096          # bytes per line, newline included
KEEP_DAYS=14      # retention: a day file dated more than this many days before today goes
DAYGLOB='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].jsonl'
# HARBOR_EVENT_BUS_SKEW shifts this tool's clock by N seconds — test-only, to cross a UTC midnight.
SKEW="${HARBOR_EVENT_BUS_SKEW:-0}"
case "$SKEW" in ''|-|*[!0-9-]*|?*-*) SKEW=0 ;; esac

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

# Days since 1970-01-01 → YYYY-MM-DD (Hinnant's civil_from_days): BSD and GNU date disagree on
# formatting an arbitrary epoch, awk does not.
AWK_CIVIL='function civil(z,   era, doe, yoe, y, doy, mp, d, m) {
  z += 719468; era = int((z >= 0 ? z : z - 146096) / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153); d = doy - int((153 * mp + 2) / 5) + 1; m = mp + (mp < 10 ? 3 : -9)
  return sprintf("%04d-%02d-%02d", y + (m <= 2), m, d) }'

day_of() { DAY="$(awk -v e="$1" "$AWK_CIVIL"' BEGIN { print civil(int(e / 86400)) }')"; }
# NOW (epoch) and TODAY (its UTC date) from one clock read; the skew costs an awk only under test.
now() {
  _t="$(date -u '+%s %Y-%m-%d' 2>/dev/null)" || _t="0 1970-01-01"
  NOW="${_t%% *}"; TODAY="${_t#* }"
  [ "$SKEW" = 0 ] || { NOW=$((NOW + SKEW)); day_of "$NOW"; TODAY="$DAY"; }
}
dnum() { _dn="$1"; _dy="${_dn%%-*}"; _dn="${_dn#*-}"; DNUM="$_dy${_dn%%-*}${_dn#*-}"; }

# ── scan: the one reader ─────────────────────────────────────────────────────
# scan <offset-file> <consumer>: every COMPLETE line past the consumer's offsets, day files in date
# order, then the consumer's rows (`<consumer> <day> <bytes>`, one per day file) rewritten atomically.
# A last line with no newline yet is left for the next scan, so a torn write is never read; a day
# file with no row starts at 0. Lines go out before the offsets move: a reader killed mid-read
# re-reads (consumers dedupe on id), never skips. Returns 1, offsets untouched, when it could not.
# The lock is taken BEFORE the offsets are read or a line printed: a wait that times out prints
# nothing, so it is a retry, never a re-read (hosted CI under load: 71 reads of 60, harbor#1043).
scan() {
  _so="$1"; _sw="$2"
  _sd="${_so%/*}"; [ "$_sd" != "$_so" ] || _sd=.
  mkdir -p "$_sd" 2>/dev/null || :
  _sn="$(mktemp "$_so.XXXXXX" 2>/dev/null)" || return 1
  _ss="$_sn.sizes"; _sp="$_sn.plan"; _sr="$_sn.rows"; _sc="$_sn.count"
  offsets_lock "$_so.lock" || { rm -f "$_sn"; return 1; }
  ( cd "$DIR" 2>/dev/null && set +f && for _f in $DAYGLOB; do [ ! -f "$_f" ] || wc -c -- "$_f"; done ) > "$_ss" 2>/dev/null || :
  awk -v w="$_sw" -v of="$_so" 'BEGIN { while ((getline l < of) > 0) { split(l, a, " "); if (a[1] == w) off[a[2]] = a[3] + 0 } }
    $2 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\.jsonl$/ {
      d = substr($2, 1, 10); s = (d in off) ? off[d] : 0; if (s > $1 + 0) s = 0; print d, s, $1 + 0 }' "$_ss" > "$_sp"
  : > "$_sr"
  while read -r _d _s _z; do
    _c=0
    if [ "$_z" -gt "$_s" ]; then
      # Bytes [s, z) only: a line that crosses z, or has no newline yet, stops the read.
      tail -c +"$((_s + 1))" "$DIR/$_d.jsonl" 2>/dev/null | LC_ALL=C awk -v lim="$((_z - _s))" -v cf="$_sc" '
        { n = length($0) + 1; if (used + n > lim) exit; used += n; if ($0 ~ /^[{]"id":".*[}]$/) print }
        END { print used + 0 > cf }' || { rm -rf "$_so.lock"; rm -f "$_sn" "$_ss" "$_sp" "$_sr" "$_sc"; return 1; }
      read -r _c < "$_sc" || _c=0
    fi
    printf '%s %s %s\n' "$_sw" "$_d" "$((_s + _c))" >> "$_sr"
  done < "$_sp"
  # Other consumers' rows are re-read and the file replaced under the same lock, so two consumers
  # sharing one offsets file never write back each other's stale rows.
  { awk -v w="$_sw" '$1 != w' "$_so" 2>/dev/null || :; cat "$_sr"; } > "$_sn" && mv -f "$_sn" "$_so"
  _sx=$?
  rm -rf "$_so.lock"
  rm -f "$_sn" "$_ss" "$_sp" "$_sr" "$_sc"
  return "$_sx"
}

# offsets_lock <dir>: mkdir is atomic. A lock whose holder is gone is taken over; one still held
# after ~10s fails the scan, which then prints nothing and leaves the offsets where they were.
# HARBOR_EVENT_BUS_LOCK_TRIES (test-only) shortens the wait.
offsets_lock() {
  _ln=0; _lt="${HARBOR_EVENT_BUS_LOCK_TRIES:-200}"
  until mkdir "$1" 2>/dev/null; do
    _lp=""; [ ! -f "$1/pid" ] || read -r _lp < "$1/pid" || :
    # Re-read before taking over: a lock released and re-taken by a live process since the first
    # read is not the dead holder's to remove (two writers lost a consumer's row on hosted CI).
    if [ -n "$_lp" ] && ! kill -0 "$_lp" 2>/dev/null; then
      _lq=""; [ ! -f "$1/pid" ] || read -r _lq < "$1/pid" || :
      if [ "$_lq" = "$_lp" ]; then rm -rf "$1"; continue; fi
    fi
    _ln=$((_ln + 1)); [ "$_ln" -lt "$_lt" ] || return 1
    sleep 0.05 2>/dev/null || sleep 1
  done
  printf '%s\n' "$$" > "$1/pid" 2>/dev/null || :
}

consumer_ok() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac; }

# ── prune: retention (CHECKS.md event.retention) ─────────────────────────────
# prune <quiet>: delete every day file dated more than KEEP_DAYS days before today (UTC), so every
# event is kept at least KEEP_DAYS days. quiet=1 says only what failed. Returns 1 if one survived.
prune() {
  now; day_of "$((NOW - KEEP_DAYS * 86400))"; _cut="$DAY"; dnum "$_cut"; _cutn="$DNUM"
  _pr=0; _pk=0; _pf=0
  for _f in "$DIR"/$DAYGLOB; do
    [ -f "$_f" ] || continue
    _d="${_f##*/}"; dnum "${_d%.jsonl}"
    if [ "$DNUM" -lt "$_cutn" ]; then
      rm -f "$_f" 2>/dev/null || :
      if [ -e "$_f" ]; then
        _pf=$((_pf + 1))
        log_fail "[check:event.retention] $_f is older than $KEEP_DAYS days and could not be deleted"
        log_fix "rm -f '$_f'"
      else _pr=$((_pr + 1)); fi
    else _pk=$((_pk + 1)); fi
  done
  [ "$1" = 1 ] || log_ok "[check:event.retention] removed $_pr day file(s) dated before $_cut, kept $_pk, in $DIR"
  [ "$_pf" -eq 0 ]
}

# ── emit ─────────────────────────────────────────────────────────────────────
emit_fail() { # <what failed> <fix> — said on stderr; emit still exits 0
  log_fail "$1"
  log_fix "$2"
  log_end || :
  exit 0
}

# utf8 <string> → UTF8: invalid UTF-8 dropped (iconv -c; without iconv, every non-ASCII byte).
# Plain printable ASCII, the common case, forks nothing.
utf8() {
  # The set is spelled out, not ` -~`: a punctuation range follows the locale's collation (harbor#1149).
  case "$1" in *[!]' !"#$%&()*+,./:;<=>?@[\^_`{|}~'\'0-9abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-]*) ;; *) UTF8="$1"; return 0 ;; esac
  if command -v iconv >/dev/null 2>&1; then UTF8="$(printf '%s' "$1" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null)" || :
  else UTF8="$(printf '%s' "$1" | tr -d '\200-\377')" || :; fi
}

# data_norm: --data through jq, keeping only CONTRACT §3a.2's allowlist with its types (strings;
# `link` https only; `exit` a number). Anything that is not exactly one JSON object is
# {"invalid":true}; with no jq the data is {} — never passed through unread.
DATA_KEYS='["title","link","session_id","deadline_ts","tool","closes_on","evidence","exit"]'
data_norm() {
  _dflag=ok
  case "$_data" in '{}') return 0 ;; esac
  command -v jq >/dev/null 2>&1 || { _data='{}'; _dflag=nojq; return 0; }
  _dn="$(printf '%s' "$_data" | jq -c --argjson k "$DATA_KEYS" '
    if type != "object" then error("not an object") else . end
    | with_entries(select(.key as $x | $k | index($x))
      | select(if .key == "exit" then (.value | type) == "number"
               elif .key == "link" then (.value | type) == "string" and (.value | startswith("https://"))
               else (.value | type) == "string" end))' 2>/dev/null)" || _dn=""
  case "$_dn" in
    '{'*'}') case "$_dn" in *'
'*) _dn="" ;; esac ;;
    *) _dn="" ;;
  esac
  if [ -n "$_dn" ]; then _data="$_dn"; else _data='{"invalid":true}'; _dflag=invalid; fi
}

cmd_emit() {
  [ $# -ge 2 ] || emit_fail "emit needs <kind> <subject> — nothing was written" "sh bin/event-bus.sh --help"
  _kind="$1"; _subj="$2"; shift 2
  # Inside a rule's handler the dispatcher sets HARBOR_EVENT_CAUSE, so what it emits carries the cause
  # the E2 loop guard walks without the handler having to pass --cause (harbor#1044).
  _src=cli; _repo=""; _repo_set=0; _cause="${HARBOR_EVENT_CAUSE:-}"; _data='{}'
  while [ $# -gt 0 ]; do
    [ $# -ge 2 ] || emit_fail "emit: $1 needs a value — nothing was written" "sh bin/event-bus.sh --help"
    case "$1" in
      --src) _src="$2" ;;
      --repo) _repo="$2"; _repo_set=1 ;;
      --cause) _cause="$2" ;;
      --data) _data="$2" ;;
      *) emit_fail "emit: unknown option $1 — nothing was written" "sh bin/event-bus.sh --help" ;;
    esac
    shift 2
  done
  case "$_kind" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9.-]*|.*|*.|*..*)
    emit_fail "emit: kind '$_kind' is not dotted lower case — nothing was written" "see docs/design/events.md, kinds" ;;
  esac
  [ -n "$_subj" ] || emit_fail "emit: the subject is empty — nothing was written" "see docs/design/events.md, kinds and subjects"
  if [ "$_repo_set" = 0 ]; then
    # The repo's own name, also from a linked worktree: the common git dir's parent, else the toplevel.
    _g="$(git rev-parse --show-toplevel --git-common-dir 2>/dev/null)" || _g=""
    _top="${_g%%
*}"; _com="${_g#*
}"
    case "$_com" in /*/.git) _repo="${_com%/.git}"; _repo="${_repo##*/}" ;; *) _repo="${_top##*/}" ;; esac
  fi
  # The escaper below is quadratic, so a field set already over the cap never reaches it.
  [ $(( ${#_src} + ${#_kind} + ${#_subj} + ${#_repo} + ${#_cause} )) -lt "$CAP" ] \
    || emit_fail "emit: the $_kind event's subject, repo, cause and src exceed $CAP bytes — nothing was written" \
      "shorten the subject, repo or cause (docs/design/events.md, the line cap)"
  utf8 "$_src"; _src="$UTF8"; utf8 "$_subj"; _subj="$UTF8"; utf8 "$_repo"; _repo="$UTF8"; utf8 "$_cause"; _cause="$UTF8"
  data_norm
  now
  _hex="$(od -An -N2 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')" || _hex=""
  case "$_hex" in [0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) ;; *) _hex="$(printf '%04x' "$(( ($$ * 7919 + NOW) % 65536 ))")" ;; esac
  mkdir -p "$DIR" 2>/dev/null || emit_fail "emit: cannot create $DIR — nothing was written" "mkdir -p '$DIR'"
  # A day file that ends mid-line (a write cut short, say by a full disk) gets its newline first, so
  # this line is never glued onto the fragment; readers step over the fragment.
  _pre=""
  [ ! -s "$DIR/$TODAY.jsonl" ] || [ -z "$(tail -c 1 "$DIR/$TODAY.jsonl" 2>/dev/null)" ] || _pre=1
  # One awk builds the line and appends it with ONE printf: fields arrive through ENVIRON, so no
  # backslash in them is interpreted, and a line under the cap fits one stdio buffer, so it leaves
  # in one write() on an O_APPEND file. The shell's printf did not: bash 3.2 tore 1 line in 320.
  _rc=0
  _out="$(E_NOW="$NOW" E_PID="$$" E_HEX="$_hex" E_SRC="$_src" E_KIND="$_kind" E_SUBJ="$_subj" \
    E_REPO="$_repo" E_CAUSE="$_cause" E_DATA="$_data" E_DIR="$DIR" E_DAY="$TODAY" E_PRE="$_pre" awk -v cap="$CAP" "$AWK_CIVIL"'
    function esc(s,   o, i, c) { o = ""
      for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"; else if (c == "\"") o = o "\\\""; else if (c == "\t") o = o "\\t"
        else if (c == "\n") o = o "\\n"; else if (c == "\r") o = o "\\r"; else if (c >= " ") o = o c }
      return o }
    BEGIN { e = ENVIRON["E_NOW"] + 0; d = int(e / 86400); s = e - d * 86400; day = ENVIRON["E_DAY"]
      ts = sprintf("%sT%02d:%02d:%02dZ", day, int(s / 3600), int((s % 3600) / 60), s % 60)
      c = ts; gsub(/[-:]/, "", c); id = c "-" ENVIRON["E_PID"] "-" ENVIRON["E_HEX"]
      data = ENVIRON["E_DATA"]; flag = "ok"; if (ENVIRON["E_PRE"] != "") cap--
      head = "{\"id\":\"" id "\",\"ts\":\"" ts "\",\"src\":\"" esc(ENVIRON["E_SRC"]) "\",\"kind\":\"" esc(ENVIRON["E_KIND"]) \
        "\",\"subject\":\"" esc(ENVIRON["E_SUBJ"]) "\",\"repo\":\"" esc(ENVIRON["E_REPO"]) "\",\"cause\":\"" esc(ENVIRON["E_CAUSE"]) "\",\"data\":"
      line = head data "}"
      if (length(line) + 1 > cap) { line = head "{\"truncated\":true}}"; if (flag == "ok") flag = "truncated" }
      if (length(line) + 1 > cap) { print day; print id; print "overcap"; exit }
      f = ENVIRON["E_DIR"] "/" day ".jsonl"
      printf "%s%s\n", (ENVIRON["E_PRE"] == "" ? "" : "\n"), line >> f
      if (close(f) != 0) flag = "unwritten"
      print day; print id; print flag }' 2>/dev/null)" || _rc=$?
  _day=""; _id=""; _flag=""
  { read -r _day; read -r _id; read -r _flag; } <<EOF || :
$_out
EOF
  case "$_flag" in
    ok|invalid|truncated) ;;
    overcap) emit_fail "emit: the $_kind event for '$_subj' would exceed $CAP bytes even with empty data — nothing was written" \
      "shorten the subject, repo or cause (docs/design/events.md, the line cap)" ;;
    *) emit_fail "emit: could not append the $_kind event to a day file in $DIR (awk exit $_rc) — nothing was written" "chmod u+w '$DIR'" ;;
  esac
  _warned=0
  if [ "$_dflag" = invalid ]; then
    log_warn "emit: --data is not one JSON object; the $_kind event carries {\"invalid\":true} instead"
    _warned=1
  fi
  printf '%s\n' "$_id" 2>/dev/null || :
  # The retention sweep rides the first emit of each UTC day; prune.off in the bus dir turns it off.
  _last=""; [ ! -f "$DIR/prune.day" ] || read -r _last < "$DIR/prune.day" || :
  if [ "$_last" != "$_day" ] && [ ! -e "$DIR/prune.off" ]; then
    printf '%s\n' "$_day" 2>/dev/null > "$DIR/prune.day" || :
    prune 1 || _warned=1
  fi
  [ "$_warned" = 0 ] || log_end || :
  exit 0
}

# ── wait ─────────────────────────────────────────────────────────────────────
# Scan, then sleep on `tail -F` of today's file from the byte the scan stopped at (so nothing that
# lands in between is missed), with one timer for min(deadline, next UTC midnight + 1s). Any wake
# rescans by offsets across every day file; the midnight wake re-arms the follower on the new
# day's file. No polling loop: between wakes the process is blocked on a fifo.
W_TMP=""; W_TAIL=""; W_TIMER=""
wait_cleanup() {
  [ -z "$W_TAIL" ] || kill "$W_TAIL" 2>/dev/null || :
  [ -z "$W_TIMER" ] || kill "$W_TIMER" 2>/dev/null || :
  [ -z "$W_TMP" ] || rm -rf "$W_TMP"
}

cmd_wait() {
  _pat=""; _to=""; _from=""; _who=default
  while [ $# -gt 0 ]; do
    case "$1" in
      --timeout|--since-offset|--consumer)
        [ $# -ge 2 ] || { printf 'event-bus: %s needs a value\n' "$1" >&2; exit 2; }
        case "$1" in --timeout) _to="$2" ;; --since-offset) _from="$2" ;; *) _who="$2" ;; esac
        shift 2 ;;
      -*) printf 'event-bus: wait: unknown option %s\n' "$1" >&2; exit 2 ;;
      *) [ -z "$_pat" ] || { printf 'event-bus: wait takes one pattern\n' >&2; exit 2; }; _pat="$1"; shift ;;
    esac
  done
  [ -n "$_pat" ] || { printf 'event-bus: wait needs a pattern\n' >&2; usage >&2; exit 2; }
  case "$_to" in ''|*[!0-9]*|0) printf 'event-bus: wait needs --timeout N, N > 0 seconds — every wait has a deadline\n' >&2; exit 2 ;; esac
  consumer_ok "$_who" || { printf 'event-bus: consumer %s is not [A-Za-z0-9._-]+\n' "$_who" >&2; exit 2; }
  _gr=0; printf '' | grep -E -e "$_pat" >/dev/null 2>&1 || _gr=$?
  [ "$_gr" -le 1 ] || { printf 'event-bus: %s is not a grep -E pattern\n' "$_pat" >&2; exit 2; }
  now; _dl=$((NOW + _to))
  W_TMP="$(mktemp -d "${TMPDIR:-/tmp}/event-wait.XXXXXX")" || { printf 'event-bus: cannot make a temp dir\n' >&2; exit 2; }
  trap wait_cleanup EXIT
  trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
  _off="$W_TMP/offsets"
  if [ -n "$_from" ]; then
    awk -v w="$_who" '$1 == w' "$_from" > "$_off" 2>/dev/null || : > "$_off"
  else
    # From now: every older day file at its end, and today's at its last COMPLETE line (a scan from
    # 0, output dropped), so a line half-written as the wait starts is still seen once it is whole.
    now; day_of "$NOW"
    ( cd "$DIR" 2>/dev/null && set +f && for _f in $DAYGLOB; do [ ! -f "$_f" ] || wc -c -- "$_f"; done ) 2>/dev/null \
      | awk -v w="$_who" -v t="$DAY" 'substr($2, 1, 10) != t { print w, substr($2, 1, 10), $1 + 0 }' > "$_off" || :
    scan "$_off" "$_who" > /dev/null || { printf 'event-bus: cannot read the bus at %s\n' "$DIR" >&2; exit 2; }
  fi
  mkdir -p "$DIR" 2>/dev/null || :
  _i=0
  while :; do
    scan "$_off" "$_who" > "$W_TMP/new" || { printf 'event-bus: cannot read the bus at %s\n' "$DIR" >&2; exit 2; }
    _hit="$(grep -E -e "$_pat" "$W_TMP/new" 2>/dev/null | head -n 1)" || _hit=""
    if [ -n "$_hit" ]; then printf '%s\n' "$_hit"; exit 0; fi
    now
    if [ "$NOW" -ge "$_dl" ]; then
      log_fail "wait: no event matched '$_pat' within ${_to}s in $DIR — a deadline is a report, not a hang"
      log_nofix "docs/design/events.md, rule 1: check the real state the event stood for"
      log_end || :
      exit 3
    fi
    day_of "$NOW"; _today="$DAY"
    _until=$(( (NOW / 86400 + 1) * 86400 + 1 )); [ "$_until" -le "$_dl" ] || _until="$_dl"
    _secs=$((_until - NOW)); [ "$_secs" -ge 1 ] || _secs=1
    _at="$(awk -v d="$_today" '$2 == d { print $3; exit }' "$_off")"
    _i=$((_i + 1)); _fifo="$W_TMP/wake.$_i"
    mkfifo "$_fifo" || { printf 'event-bus: cannot make a fifo in %s\n' "$W_TMP" >&2; exit 2; }
    tail -c +"$((${_at:-0} + 1))" -F "$DIR/$_today.jsonl" 2>/dev/null > "$_fifo" &
    W_TAIL=$!
    ( trap 'kill "$_s" 2>/dev/null; exit 0' TERM; sleep "$_secs" & _s=$!; wait "$_s"; echo T ) > "$_fifo" &
    W_TIMER=$!
    IFS= read -r _w < "$_fifo" || :
    kill "$W_TAIL" "$W_TIMER" 2>/dev/null || :
    wait "$W_TAIL" "$W_TIMER" 2>/dev/null || :
    W_TAIL=""; W_TIMER=""; rm -f "$_fifo"
  done
}

# ── since, tail ──────────────────────────────────────────────────────────────
cmd_since() {
  _of=""; _who=default
  while [ $# -gt 0 ]; do
    case "$1" in
      --consumer) [ $# -ge 2 ] || { printf 'event-bus: --consumer needs a value\n' >&2; exit 2; }; _who="$2"; shift 2 ;;
      -*) printf 'event-bus: since: unknown option %s\n' "$1" >&2; exit 2 ;;
      *) [ -z "$_of" ] || { printf 'event-bus: since takes one offset file\n' >&2; exit 2; }; _of="$1"; shift ;;
    esac
  done
  [ -n "$_of" ] || { printf 'event-bus: since needs <offset-file>\n' >&2; usage >&2; exit 2; }
  consumer_ok "$_who" || { printf 'event-bus: consumer %s is not [A-Za-z0-9._-]+\n' "$_who" >&2; exit 2; }
  if ! scan "$_of" "$_who"; then
    log_fail "since: could not read $DIR or rewrite $_of — the offsets did not move"
    log_fix "ls -ld '$DIR' '$_of'"
    log_end || :
    exit 1
  fi
}

cmd_tail() {
  _n="${1:-10}"
  case "$_n" in ''|*[!0-9]*) printf 'event-bus: tail takes a line count\n' >&2; exit 2 ;; esac
  _t="$(mktemp -d "${TMPDIR:-/tmp}/event-tail.XXXXXX")" || exit 1
  scan "$_t/offsets" tail > "$_t/all" || { rm -rf "$_t"; exit 1; }
  tail -n "$_n" "$_t/all"
  rm -rf "$_t"
}

VERB="${1:-}"
[ $# -eq 0 ] || shift
case "$VERB" in
  emit) trap 'exit 0' EXIT; trap '' PIPE; cmd_emit "$@" ;;  # a closed stdout is not a failure either
  wait) cmd_wait "$@" ;;
  since) cmd_since "$@" ;;
  tail) cmd_tail "$@" ;;
  prune)
    prune 0 || :
    log_end; exit $? ;;
  dispatch|on|pull|subscribe) exec sh "$HERE/event-dispatch.sh" "$VERB" "$@" ;;
  ci) exec sh "$HERE/ci-wait.sh" "$@" ;;
  -h|--help|help) usage ;;
  '') usage >&2; exit 2 ;;
  *) printf 'event-bus: unknown verb %s (emit, wait, since, tail, prune; dispatch, on, pull, subscribe; ci)\n' "$VERB" >&2; exit 2 ;;
esac
