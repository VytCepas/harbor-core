#!/usr/bin/env sh
# status-suggest.sh (harbor#1485) — the one writer of the suggestion state, and its reader.
#
#   sh status-suggest.sh stop|start <id> --origin panel|agent    stop or restart one suggestion
#   sh status-suggest.sh off|on --origin panel|agent             silence or restore every suggestion
#   sh status-suggest.sh shown <id>                              the rule's spoke: script records the line just spoken
#   sh status-suggest.sh tick                                    one more session (the SessionStart pack, once a session)
#   sh status-suggest.sh scan-used                               the person has used the scan; the intro ends
#   sh status-suggest.sh status --json                           what the panel draws; always exit 0
#
# STATE in ${HARBOR_STATUS_SUGGEST_DIR:-$HOME/.local/state/harbor/suggest}, outside the config dir so a confined shell can write it; ids, dates and origins only.
# stopped.tsv (id, date, origin), off, shown.tsv (id, date, the table's line), sessions.tsv (count, intro_last_count, scan_used), switch.log.
# Writes are temp file plus rename under a lock; rows come from ../context-rules/user/suggest-tool.tsv. Exit 0 done, 1 unwritable or refused, 2 usage.
#
# THE FOLDER IS HOSTILE. A confined command may write it (contracts/confinement-paths.txt), and this tool also runs outside the sandbox, so
# nothing in it is trusted. Four things hold that, and none rests on a check beating a race (a check here is only the loud half):
#   every name is resolved from inside the real folder (state_enter), and has no slash, so a folder swapped for a link later reaches nothing
#   a write never opens an existing name: one O_EXCL open makes and fills a temp (put), and a rename that follows nothing lands it
#   nothing is appended: switch.log is rewritten through put, so a link or a hard link in its place is replaced, never written through
#   a rewrite carries over only rows of the contract's shape, so a read raced onto an outside file copies none of its bytes back in
# A link, a hard link or a non-regular file where a state file or .lock belongs is refused (exit 1), as floor_log_decision refuses its sink.
set -u
LC_ALL=C; export LC_ALL
umask 077
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh; stdout is data (harbor#1485)
LOG_FD=2
. "$HERE/library-log.sh"
log_init status-suggest
STATE="${HARBOR_STATUS_SUGGEST_DIR:-$HOME/.local/state/harbor/suggest}"
while [ "${STATE%/}" != "$STATE" ]; do STATE="${STATE%/}"; done
case "$STATE" in */*) ;; *) STATE="./$STATE" ;; esac
TABLE="$HERE/../context-rules/user/suggest-tool.tsv"
INTRO_EVERY=20
# A lock this old is a killed writer's. Inside the engine's 3 s spoke bound, read in whole seconds; holders keep it for milliseconds.
LOCK_STALE=2
LOCK_GIVE_UP=6
HELD=".held.$$"
BREAKING=0
TAB='	'
NL='
'
WRITABLE="make $STATE writable (a confinement write row, contracts/confinement-paths.txt)"
# The shapes the contract allows in the state files. Only these cross from a read into a rewrite or into status --json.
SHAPES='
  function okid(s) { return s != "" && length(s) <= 27 && s !~ /^-/ && s !~ /[^a-z0-9-]/ }
  function okdate(s) { return s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ }
  function okorigin(s) { return s == "panel" || s == "agent" }'

die() { log_fail "$1"; log_fix "${3:-sh bin/status-suggest.sh --help}"; log_end || :; exit "${2:-2}"; }
refuse() { die "refused: $STATE/$1 is a link or not a plain file, so it was neither read nor written" 1 "see what put it there, then delete that one entry"; }
valid_id() {
  case "$1" in ''|-*|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) return 1 ;; esac
  [ "${#1}" -le 27 ]
}
today() { date +%Y-%m-%d; }

# state_enter — stand inside the real folder, by the physical path of its parent; 1 when the name leads anywhere else.
state_enter() {
  _par="$(CDPATH='' cd -P -- "${STATE%/*}/" 2>/dev/null && pwd -P)" || return 1
  CDPATH='' cd -P -- "$STATE" 2>/dev/null || return 1
  [ "$(pwd -P)" = "${_par%/}/${STATE##*/}" ]
}
gone() { [ ! -e "$1" ] && [ ! -L "$1" ]; }
# plain <name> — a regular file with one link; find never follows a name it is given, and never opens it.
plain() { [ -n "$(find "./$1" -prune -type f -links 1 2>/dev/null)" ]; }
# usable <name> — 0 for a plain file, 1 for none, and a refusal for anything else. A refusal in a subshell ends only that: call it in the verb.
usable() { if gone "$1"; then return 1; fi; plain "$1" || refuse "$1"; }
lock_plain() { [ -d "$1" ] && [ ! -L "$1" ]; }

# lock_old <name> — it has stood LOCK_STALE seconds, by its own mtime, not following a link. A date ahead of the clock is no live writer's.
lock_old() {
  _lm="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  case "$_lm" in ''|*[!0-9]*) return 1 ;; esac
  _la=$(( $(date +%s) - _lm ))
  [ "$_la" -ge "$LOCK_STALE" ] || [ "$_la" -lt 0 ]
}
# lock_break — clear a stale .lock. One breaker at a time, and it rereads the age, so a second waiter cannot take the first one's fresh lock.
lock_break() {
  lock_old .lock || return 0
  if ! mkdir .lock.break 2>/dev/null; then
    if gone .lock.break; then die "cannot write $STATE" 1 "$WRITABLE"; fi
    lock_plain .lock.break || refuse .lock.break
    if lock_old .lock.break; then rm -rf .lock.break 2>/dev/null; fi
    return 0
  fi
  BREAKING=1
  if lock_old .lock; then rm -rf .held.* .lock 2>/dev/null; fi
  rmdir .lock.break 2>/dev/null; BREAKING=0
}
# lock_drop — only a holder whose mark still stands frees the lock: a broken lock is someone else's by now.
lock_drop() {
  [ "$BREAKING" = 0 ] || rmdir .lock.break 2>/dev/null
  if rmdir "$HELD" 2>/dev/null; then rmdir .lock 2>/dev/null; fi
}
# lock_take — mkdir is atomic. The holder's mark sits beside .lock, never in it: a path through a swapped .lock would reach outside.
lock_take() {
  mkdir -p "$STATE" 2>/dev/null || die "cannot create $STATE" 1 "$WRITABLE"
  state_enter || die "refused: $STATE does not lead to the plain folder of that name, so nothing was written" 1 "see what put it there, then delete the link"
  trap lock_drop EXIT
  trap 'exit 130' INT HUP TERM
  _t0="$(date +%s)"
  until mkdir .lock 2>/dev/null; do
    if gone .lock; then
      # the holder released between the failed mkdir and this test: try once more before calling the folder unwritable
      mkdir .lock 2>/dev/null && break
      if gone .lock; then die "cannot write $STATE" 1 "$WRITABLE"; fi
    fi
    lock_plain .lock || refuse .lock
    lock_break
    [ $(( $(date +%s) - _t0 )) -lt "$LOCK_GIVE_UP" ] || die "the lock in $STATE stayed held for ${LOCK_GIVE_UP}s" 1 "run it again; if it repeats, see what keeps making $STATE/.lock"
    sleep 0.05 2>/dev/null || sleep 1
  done
  mkdir "$HELD" 2>/dev/null || die "cannot mark the lock in $STATE" 1 "$WRITABLE"
}

# put <name> — stdin becomes <name> in the state folder, whole or not at all. `set -C` makes the temp with O_EXCL and cat writes through that
# same open; mktemp alone would create it and leave the shell to reopen it by name, which a watcher can swap. Plain mv moves INTO a linked
# directory, so only the forms that follow nothing are tried: -T (GNU), -h (BSD). A holder whose lock was broken commits nothing.
put() {
  gone "$1" || plain "$1" || refuse "$1"
  _tmp="$(mktemp -u .tmp.XXXXXXXXXX)" || die "cannot name a temp file in $STATE" 1 "$WRITABLE"
  if ( set -C; cat > "$_tmp" ) 2>/dev/null && [ -d "$HELD" ] && { mv -Tf "$_tmp" "$1" 2>/dev/null || mv -hf "$_tmp" "$1" 2>/dev/null; }; then return 0; fi
  rm -f "$_tmp" 2>/dev/null
  die "cannot write $STATE/$1" 1 "$WRITABLE"
}

# trail <verb> <id> <origin> — one line per switch; trimmed to the last 200 lines past 400. A failed log write never fails the verb.
trail() {
  (
    _log=0; if usable switch.log; then _log=1; fi
    { [ "$_log" = 0 ] || tail -n 400 switch.log; printf '%s\t%s\t%s\t%s\n' "$(today)" "$1" "$2" "$3"; } \
      | awk -F'\t' "$SHAPES"'
          NF == 4 && okdate($1) && $2 ~ /^(stop|start|off|on|scan-used)$/ && ($3 == "-" || okid($3)) && ($4 == "-" || okorigin($4)) { l[++n] = $0 }
          END { for (i = (n > 400 ? n - 199 : 1); i <= n; i++) print l[i] }' \
      | put switch.log
  ) 2>/dev/null || :
}

# stopped_rows — the rows of stopped.tsv in the contract's shape, the only ones a rewrite carries over.
stopped_rows() { awk -F'\t' "$SHAPES"' NF == 3 && okid($1) && okdate($2) && okorigin($3)' stopped.tsv 2>/dev/null; }

# counters — sets C_COUNT, C_INTRO, C_SCAN from sessions.tsv, each 0 when absent or not a number.
counters() {
  C_COUNT=0; C_INTRO=0; C_SCAN=0
  usable sessions.tsv || return 0
  _row="$(awk -F'\t' 'NR==1{print $1 " " $2 " " $3; exit}' sessions.tsv 2>/dev/null)"
  # shellcheck disable=SC2086
  set -- $_row
  case "${1:-}" in ''|*[!0-9]*) ;; *) C_COUNT="$1" ;; esac
  case "${2:-}" in ''|*[!0-9]*) ;; *) C_INTRO="$2" ;; esac
  case "${3:-}" in 1) C_SCAN=1 ;; esac
}
counters_put() { printf '%s\t%s\t%s\n' "$C_COUNT" "$C_INTRO" "$C_SCAN" | put sessions.tsv; }

# row_field <id> <column> — the table's cell for one row; empty when the table or the row is absent.
row_field() {
  [ -f "$TABLE" ] || return 0
  awk -F'\t' -v id="$1" -v col="$2" '/^#/ || $1 == "id" {next} $1 == id {print $col; exit}' "$TABLE" 2>/dev/null
}

# parse <verb> <wants-id> <args...> — sets ID and ORIGIN; bad shapes exit 2.
parse() {
  _verb="$1"; _wid="$2"; shift 2
  ID=''; ORIGIN=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --origin) [ $# -ge 2 ] || die "$_verb: --origin takes panel or agent"; ORIGIN="$2"; shift 2 ;;
      -*) die "$_verb: unknown option $1" ;;
      *) [ "$_wid" = 1 ] && [ -z "$ID" ] || die "$_verb: unexpected argument"; ID="$1"; shift ;;
    esac
  done
  if [ "$_wid" = 1 ]; then valid_id "$ID" || die "$_verb: wants one id of a-z, 0-9 and -, at most 27 characters"; fi
}
need_origin() { case "$ORIGIN" in panel|agent) ;; *) die "$1: --origin must be panel or agent" ;; esac; }

cmd_stop() {
  parse stop 1 "$@"; need_origin stop
  lock_take
  _rows=''; if usable stopped.tsv; then _rows="$(stopped_rows)"; fi
  case "$NL$_rows" in
    *"$NL$ID$TAB"*) ;;
    *) { [ -z "$_rows" ] || printf '%s\n' "$_rows"; printf '%s\t%s\t%s\n' "$ID" "$(today)" "$ORIGIN"; } | put stopped.tsv || exit 1 ;;
  esac
  trail stop "$ID" "$ORIGIN"
}
cmd_start() {
  parse start 1 "$@"; need_origin start
  lock_take
  if usable stopped.tsv; then
    stopped_rows | awk -F'\t' -v id="$ID" '$1 != id' | put stopped.tsv || exit 1
  fi
  trail start "$ID" "$ORIGIN"
}
cmd_off() {
  parse off 0 "$@"; need_origin off
  lock_take
  printf '%s\t%s\n' "$(today)" "$ORIGIN" | put off || exit 1
  trail off - "$ORIGIN"
}
cmd_on() {
  parse on 0 "$@"; need_origin on
  lock_take
  rm -f off 2>/dev/null || die "cannot remove $STATE/off" 1 "$WRITABLE"
  trail on - "$ORIGIN"
}
cmd_shown() {
  parse shown 1 "$@"
  [ -z "$ORIGIN" ] || die "shown: takes only an id"
  _line="$(row_field "$ID" 7)"; _line="$(printf '%s' "$_line" | tr '\t\r' '  ')"; _kind="$(row_field "$ID" 2)"
  lock_take
  printf '%s\t%s\t%s\n' "$ID" "$(today)" "${_line:--}" | put shown.tsv || exit 1
  if [ "$_kind" = intro ]; then counters; C_INTRO="$C_COUNT"; counters_put || exit 1; fi
}
cmd_tick() {
  parse tick 0 "$@"; [ -z "$ORIGIN" ] || die "tick: takes no arguments"
  lock_take
  counters; C_COUNT=$((C_COUNT + 1)); counters_put || exit 1
}
cmd_scan_used() {
  parse scan-used 0 "$@"; [ -z "$ORIGIN" ] || die "scan-used: takes no arguments"
  lock_take
  counters; C_SCAN=1; counters_put || exit 1
  trail scan-used - -
}

# state_lines <tag> <name> — a state file's lines for the status reader, tagged; a file that is not plain reads as absent, and says so.
state_lines() {
  if gone "$2"; then return 0; fi
  if plain "$2"; then sed "s/^/$1	/" "$2" 2>/dev/null; else log_warn "refused: $STATE/$2 is a link or not a plain file, so it reads as empty"; fi
}

# cmd_status — the whole picture as JSON, built in one awk over tagged lines (T table, S stopped, L shown, N sessions). The state files hold
# what any confined command wrote: an id, a date and an origin pass only in their shape, and a line comes from the table by id, never from a file.
cmd_status() {
  [ "$#" -eq 1 ] && [ "$1" = --json ] || die "status: wants --json"
  _in=0
  if [ -d "$STATE" ]; then
    if state_enter; then _in=1; else log_warn "refused: $STATE does not lead to the plain folder of that name, so the state reads as empty"; fi
  fi
  _en=true
  if [ "$_in" = 1 ] && ! gone off; then _en=false; fi
  {
    printf 'E\t%s\n' "$_en"
    [ ! -f "$TABLE" ] || sed 's/^/T\t/' "$TABLE" 2>/dev/null
    if [ "$_in" = 1 ]; then state_lines S stopped.tsv; state_lines L shown.tsv; state_lines N sessions.tsv; fi
  } | awk -F'\t' -v every="$INTRO_EVERY" "$SHAPES"'
    function esc(s,   i, c, o) {
      o = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") o = o "\\\\"
        else if (c == "\"") o = o "\\\""
        else if (c < " ") o = o " "
        else o = o c
      }
      return o
    }
    function num(s) { return (s ~ /^[0-9]+$/) ? s + 0 : 0 }
    $1 == "E" { enabled = $2; next }
    $1 == "T" {
      if ($2 ~ /^#/ || $2 == "id" || !okid($2) || ($2 in kind)) next
      kind[$2] = $3; line[$2] = $8; order[++nrows] = $2; next
    }
    $1 == "S" { if (okid($2) && !($2 in since)) { since[$2] = (okdate($3) ? $3 : ""); origin[$2] = (okorigin($4) ? $4 : ""); sorder[++nstop] = $2 } next }
    $1 == "L" { if (okid($2) && !havelast) { havelast = 1; lid = $2; lat = (okdate($3) ? $3 : "") } next }
    $1 == "N" { if (!havesess) { havesess = 1; count = num($2); introlast = num($3); scan = ($4 == "1") } next }
    END {
      printf "{\"schema\":1,\"enabled\":%s,\"stopped\":[", (enabled == "false" ? "false" : "true")
      for (i = 1; i <= nstop; i++) {
        id = sorder[i]; lab = (id in line && line[id] != "") ? line[id] : id
        printf "%s{\"id\":\"%s\",\"since\":\"%s\",\"origin\":\"%s\",\"label\":\"%s\"}", (i > 1 ? "," : ""), esc(id), since[id], origin[id], esc(lab)
      }
      printf "],\"last\":"
      if (havelast) printf "{\"id\":\"%s\",\"line\":\"%s\",\"at\":\"%s\"}", esc(lid), esc(line[lid]), lat
      else printf "null"
      printf ",\"rows\":["
      for (i = 1; i <= nrows; i++) {
        id = order[i]
        printf "%s{\"id\":\"%s\",\"kind\":\"%s\",\"line\":\"%s\",\"stopped\":%s}", (i > 1 ? "," : ""), esc(id), esc(kind[id]), esc(line[id]), ((id in since) ? "true" : "false")
        if (kind[id] == "intro" && !(id in since)) introlive = 1
      }
      due = (introlive && !scan && count - introlast >= every) ? "true" : "false"
      printf "],\"intro_due\":%s}\n", due
    }'
  return 0
}

[ $# -ge 1 ] || die "usage: status-suggest.sh stop|start|off|on|shown|tick|scan-used|status ..."
_v="$1"; shift
case "$_v" in
  stop) cmd_stop "$@" ;;
  start) cmd_start "$@" ;;
  off) cmd_off "$@" ;;
  on) cmd_on "$@" ;;
  shown) cmd_shown "$@" ;;
  tick) cmd_tick "$@" ;;
  scan-used) cmd_scan_used "$@" ;;
  status) cmd_status "$@" ;;
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0" ;;
  *) die "unknown verb: $_v" ;;
esac
