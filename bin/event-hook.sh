#!/usr/bin/env sh
# event-hook.sh (harbor#1043 PR 2, harbor#1051 PR 1) — a Claude Code hook that puts one event on the local bus.
#
#   SessionStart  → session.start  subject = session_id        (not on source=compact: same session)
#   SessionEnd    → session.stop   subject = session_id        (Stop is end-of-TURN, measured 2.1.291)
#   SubagentStart → agent.spawn    subject = agent_id          data = {"session_id": <owner>}
#   SubagentStop  → agent.done     subject = agent_id          data = {"session_id": <owner>}
#   PostToolUse   → tool.background.start  subject = <session_id>:<tool_use_id>  data = {session_id, tool}
#                     for Monitor, CronCreate, Workflow, ScheduleWakeup (not stop:true) and
#                     Bash with run_in_background:true
#                   → pr.opened    subject = <owner>/<repo>#<n>, one per PR; only when the command holds a `gh pr create`
#                     (in a loop or a ; && chain too, harbor#1437), nothing but quiet commands follows the last
#                     one, and the PR comes from a whole github.com pull URL line of the result's stdout
#                     (never from the command text); data = {session_id, link}
#                 → skill.call   subject = the skill name; data = {session_id}            (harbor#1181 lane 7)
#                 → memory.read  subject = the memory note's BASENAME, for a Read of */memory/*.md, MEMORY.md or
#                     INDEX-FULL.md, never its path or content; data = {session_id}.  Every other Read exits at once.
#
# Hook-invoked, the payload on stdin; nothing to run by hand. Wired by admission-install.sh, standalone
# and fail-OPEN like guard-apiroute: it exits 0 on EVERY path, prints nothing, and takes only ids
# from the payload, each checked against a short charset. A prompt, a command, a transcript path or
# tool output never reaches an event (docs/design/events.md, the record). Claude Code has no hook
# for a background tool's completion, so there is no tool.background.done producer.
# BOUNDED: reading the payload and the bus emit each get HARBOR_EVENT_BUS_TIMEOUT seconds (default
# 2, 1..60); a hung bus or a stdin that never closes costs the session at most twice that, then exit 0.
# Off: `touch <bus dir>/producers.off`. The security floor never depends on this file.
#
# A new producer is one `case` arm below plus one row in admission-install.sh's wiring table; the
# payload fields it needs go in the KEYS list (or the awk's derived flags).

# Not $(dirname): a hook runs this (F15, harbor#813). No `set -e`: this exits 0 on every path.
set -u
trap 'exit 0' EXIT   # the contract: exit 0 on EVERY path, even a shell-fatal error
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
case "${1-}" in -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
exec 2>/dev/null   # a killed child must not print "Terminated"; this hook's stderr is never useful

BUS_DIR="${HARBOR_EVENT_DIR:-${HOME:-/nonexistent}/.local/state/harbor/events}"
[ ! -e "$BUS_DIR/producers.off" ] || exit 0
# A closed stdin makes `exec 3<&0` fatal to the shell (dash and bash both exit on it, non-zero); the
# EXIT trap above turns that exit into the 0 this hook promises. `( : <&0 )` cannot probe it: the
# probe's own redirect opens /dev/null as fd 0 and reads as open.
exec 3<&0
BOUND="${HARBOR_EVENT_BUS_TIMEOUT:-2}"
case "$BOUND" in ''|*[!0-9]*) BOUND=2 ;; esac
[ "$BOUND" -ge 1 ] && [ "$BOUND" -le 60 ] || BOUND=2

# run_bounded <cmd…> — the command in the background, killed with its children after $BOUND seconds.
# Its stdin is fd 3, because an async command otherwise gets /dev/null. Returns its status (143 if killed).
# With _grp=1 and perl on the box the command runs as its own process-group leader and the kill takes
# the whole group, so a child that double-forks (reparented to init, no longer anyone's child) dies too;
# without perl only the direct children are killed (docs/design/events.md, "Bounded").
_perl=""; command -v perl >/dev/null 2>&1 && _perl=1
_grp=0
run_bounded() {
  if [ "$_grp" = 1 ] && [ -n "$_perl" ]; then
    perl -e 'setpgrp(0, 0); exec @ARGV or exit 127' -- "$@" <&3 & _p=$!
  else
    _grp=0; "$@" <&3 & _p=$!
  fi
  # The watchdog traps TERM so that disarming it also ends its sleep: no pkill on the normal path.
  ( trap 'kill "$_s"; exit 0' TERM; sleep "$BOUND" & _s=$!
    wait "$_s" && { if [ "$_grp" = 1 ]; then kill -s TERM -- "-$_p"; else pkill -P "$_p"; fi; kill "$_p"; } ) >/dev/null 2>&1 </dev/null & _g=$!
  wait "$_p"; _rc=$?
  kill "$_g"; wait "$_g"
  return "$_rc"
}

# Top-level string fields of the payload: the FIRST `"key":"value"`, value quoted plainly (an escaped
# quote inside a string never matches, so a forged field inside a prompt is not the field). Special
# cases: tool_use_id is the LAST one (it follows tool_response, which can carry nested objects), and
# the awk derives bg= (run_in_background true) and stop= (stop true) from the tool_input region only.
# pr= and ghpr= come from two reads that must BOTH hold (harbor#1114, #1437): (1) the tool_input `command`
# string only (never `description` or any other key), decoded, split into simple commands at an unquoted
# ; & && || | or newline; at least one is `gh pr create` (a loop body or a chain member counts) and every command
# after the last one is quiet (done, cd, an echo naming no URL), so `gh pr create && cat notes.txt` still does not
# count: its output is not gh's; (2) the tool_response `stdout`, decoded, whose last non-empty line must be a whole
# github.com pull URL; its whole-line URLs are the PRs (outside a loop at most as many as there are creates, the last
# ones), an "already exists" line dropping the URL under it. Nothing but those flags and ids comes out. One awk, no jq.
KEYS="hook_event_name session_id agent_id source tool_name"
FIELDS="$(run_bounded env LC_ALL=C awk -v keys="$KEYS" '
  # jstr(r): the JSON string that starts r, decoded (\n and \r become newlines, \t a space); "" when
  # it never closes or is over 60000 bytes. The escape handling is what keeps a quoted quote quoted.
  function jstr(r,   out, c, e) {
    out = ""
    while (match(r, /["\\]/)) {
      out = out substr(r, 1, RSTART - 1); c = substr(r, RSTART, 1)
      if (c == "\"") return out
      e = substr(r, RSTART + 1, 1); r = substr(r, RSTART + 2)
      if (e == "n" || e == "r") out = out "\n"
      else if (e == "t") out = out " "
      else if (e == "u") { out = out "?"; r = substr(r, 5) }
      else out = out e
      if (length(out) > 60000) return ""
    }
    return ""
  }
  # splitsegs(c): every simple command of a shell command line, in order, in SEG[1..SEGN]; quote-aware (single,
  # double, backslash), split at an unquoted ; & && || | or newline.
  function splitsegs(c,   seg, st, ch, pv, m) {
    seg = ""; st = 0; SEGN = 0
    while (c != "") {
      if (st == 1) {
        if (!(m = index(c, SQ))) { seg = seg c; break }
        seg = seg substr(c, 1, m); c = substr(c, m + 1); st = 0; continue
      }
      if (st == 2) {
        if (!match(c, /["\\]/)) { seg = seg c; break }
        if (substr(c, RSTART, 1) == "\"") { seg = seg substr(c, 1, RSTART); c = substr(c, RSTART + 1); st = 0 }
        else { seg = seg substr(c, 1, RSTART + 1); c = substr(c, RSTART + 2) }
        continue
      }
      if (!match(c, SPECIAL)) { seg = seg c; break }
      ch = substr(c, RSTART, 1); seg = seg substr(c, 1, RSTART - 1); c = substr(c, RSTART + 1)
      if (ch == SQ) { seg = seg ch; st = 1 }
      else if (ch == "\"") { seg = seg ch; st = 2 }
      else if (ch == "\\") { seg = seg " " substr(c, 1, 1); c = substr(c, 2) }
      else {
        pv = substr(seg, length(seg), 1)
        if (ch == "&" && (pv == ">" || pv == "<" || substr(c, 1, 1) == ">")) { seg = seg ch; continue }
        if (seg ~ /[^ \t]/) SEG[++SEGN] = seg
        seg = ""
      }
    }
    if (seg ~ /[^ \t]/) SEG[++SEGN] = seg
  }
  # head(x): a simple command without the shell keywords and assignment that may lead it (`do gh ...`, `u=$(gh ...`).
  function head(x) {
    while (x ~ /^[ \t]*(do|then|else|elif|if|while|until|time|!|\{|\()([ \t]|$)/) sub(/^[ \t]*(do|then|else|elif|if|while|until|time|!|\{|\()/, "", x)
    sub(/^[ \t]*[A-Za-z_][A-Za-z0-9_]*="?\$\(/, "", x)
    return x
  }
  function isgh(x) { return head(x) ~ /^[ \t]*([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)*gh[ \t]+(-R[ \t]+[^ \t]+[ \t]+|--repo[ \t]+[^ \t]+[ \t]+)?pr[ \t]+create([ \t]|$)/ }
  # quiet(x): a command that may follow the last gh pr create without putting anything of its own on stdout
  # that could be taken for the PR line of gh (a loop closer, a cd); an echo only when it names no github.com URL.
  function quiet(x) {
    x = head(x)
    if (x ~ /^[ \t]*(done|fi|esac|\}|\)|true|:|cd|sleep|wait|exit|return)([ \t]|$)/) return 1
    if (x ~ /^[ \t]*(echo|printf)([ \t]|$)/ && x !~ /github\.com/) return 1
    return 0
  }
  BEGIN { SQ = sprintf("%c", 39); SPECIAL = "[" SQ "\"\\\;&|\n]" }
  { s = s $0 "\n" }
  END { n = split(keys, K, " ")
    for (i = 1; i <= n; i++) if (match(s, "\"" K[i] "\" *: *\"")) {
      r = substr(s, RSTART + RLENGTH); q = index(r, "\""); if (q) print K[i] "=" substr(r, 1, q - 1) }
    r = s
    while (match(r, /"tool_use_id" *: *"/)) { r = substr(r, RSTART + RLENGTH); q = index(r, "\""); if (q) u = substr(r, 1, q - 1) }
    if (u != "") print "tool_use_id=" u
    ti = match(s, /"tool_input" *: */) ? RSTART : 0
    tr = match(s, /"tool_response" *: */) ? RSTART : 0
    ghpr = 0
    if (ti) {
      ri = (tr > ti) ? substr(s, ti, tr - ti) : substr(s, ti)
      if (ri ~ /"run_in_background" *: *true/) print "bg=1"
      if (ri ~ /"stop" *: *true/) print "stop=1"
      # harbor#1181 lane 7: a skill call names its skill; a Read of a memory note names its BASENAME only, never a path
      if (match(ri, /"skill" *: *"/)) print "skill=" jstr(substr(ri, RSTART + RLENGTH))
      if (match(ri, /"file_path" *: *"/)) { fp = jstr(substr(ri, RSTART + RLENGTH))
        if (fp ~ /\/memory\/[^\/]+\.md$/ || fp ~ /\/(MEMORY|INDEX-FULL)\.md$/) { n2 = split(fp, FP, "/"); print "memfile=" FP[n2] } }
      # harbor#1437: every gh pr create of a compound command counts (a loop, ; or && chain), not only the last simple
      # command. What still must hold: nothing but quiet commands after the last one, and a URL is taken from the
      # result stdout, a whole line, never from the command text.
      if (ri ~ /gh/ && ri ~ /pr/ && ri ~ /create/ && match(ri, /"command" *: *"/)) {
        splitsegs(jstr(substr(ri, RSTART + RLENGTH)))
        nc = 0; lastc = 0; loop = 0
        for (i = 1; i <= SEGN; i++) {
          if (isgh(SEG[i])) { nc++; lastc = i }
          if (head(SEG[i]) ~ /^[ \t]*(for|while|until|done)([ \t]|$)/ || SEG[i] ~ /^[ \t]*do([ \t]|$)/) loop = 1
        }
        if (nc > 0) { ghpr = 1; for (i = lastc + 1; i <= SEGN; i++) if (!quiet(SEG[i])) ghpr = 0 }
      }
    }
    if (ghpr && tr) {
      r = substr(s, tr)
      if (match(r, /"stdout" *: *"/)) {
        so = jstr(substr(r, RSTART + RLENGTH)); m = split(so, L, "\n")
        # An "already exists" outside stdout cannot be tied to one URL: nothing is emitted. Inside stdout it is
        # the line before the URL it names, and only that URL is dropped.
        if (r ~ /already exists/ && so !~ /already exists/) m = 0
        while (m > 0 && L[m] !~ /[^ \t]/) m--
        # gh prints its URL last: a result that ends in anything else is not a gh pr create result (harbor#1114).
        if (m > 0 && L[m] !~ /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pull\/[0-9]+$/) m = 0
        k = 0; prev = ""
        for (i = 1; i <= m; i++) {
          if (L[i] ~ /^https:\/\/github\.com\/[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\/pull\/[0-9]+$/ && prev !~ /already exists/ && !(L[i] in seen)) {
            seen[L[i]] = 1; U[++k] = L[i] }
          if (L[i] ~ /[^ \t]/) prev = L[i]
        }
        # One gh pr create can print one URL; outside a loop, only the last nc URLs can come from gh itself.
        first = 1; if (!loop && k > nc) first = k - nc + 1
        if (k - first + 1 > 20) first = k - 19
        for (i = first; i <= k; i++) { split(substr(U[i], 20), P, "/"); print "ghpr=1"; print "pr=" P[1] "/" P[2] "#" P[4] }
      }
    } }' 2>/dev/null)" || exit 0

EV=""; SID=""; AID=""; SRC=""; TOOL=""; TUID=""; BG=""; STOP=""; GHPR=""; PR=""; SKILL=""; MEMF=""
while IFS= read -r _l; do
  _v="${_l#*=}"
  if [ "${_l%%=*}" = pr ]; then   # owner/repo#n, the one value with a `#` and a `/`; one per PR a compound command opened
    case "$_v" in */*#*) ;; *) continue ;; esac
    case "$_v" in *[!A-Za-z0-9._#/-]*) continue ;; esac
    [ "${#_v}" -le 128 ] && PR="$PR $_v"
    continue
  fi
  # An id is [A-Za-z0-9._:-], at most 128 bytes; anything else is not an id and is dropped.
  case "$_v" in ''|*[!A-Za-z0-9._:-]*) continue ;; esac
  [ "${#_v}" -le 128 ] || continue
  case "$_l" in
    hook_event_name=*) EV="$_v" ;;
    session_id=*) SID="$_v" ;;
    agent_id=*) AID="$_v" ;;
    source=*) SRC="$_v" ;;
    tool_name=*) TOOL="$_v" ;;
    tool_use_id=*) TUID="$_v" ;;
    bg=*) BG="$_v" ;;
    stop=*) STOP="$_v" ;;
    ghpr=*) GHPR="$_v" ;;
    skill=*) SKILL="$_v" ;;
    memfile=*) MEMF="$_v" ;;
  esac
done <<EOF
$FIELDS
EOF

emit_event() { # <kind> <subject> <src> [data-json] [repo] — every failure is swallowed; bounded
  [ -n "$2" ] || return 0
  _d="${4-}"; [ -n "$_d" ] || _d='{}'
  if [ -n "${5-}" ]; then
    _grp=1; run_bounded sh "$HERE/event-bus.sh" emit "$1" "$2" --src "$3" --data "$_d" --repo "$5" 3</dev/null >/dev/null 2>&1 || :
  else
    _grp=1; run_bounded sh "$HERE/event-bus.sh" emit "$1" "$2" --src "$3" --data "$_d" 3</dev/null >/dev/null 2>&1 || :
  fi
  _grp=0
}
owner_data() { [ -z "$SID" ] || printf '{"session_id":"%s"}' "$SID"; }
bg_start() { # $TOOL is one of the fixed names matched below, never free payload text
  emit_event tool.background.start "$SID:$TUID" hook.post-tool-use "$(printf '{"session_id":"%s","tool":"%s"}' "$SID" "$TOOL")"
}

case "$EV" in
  SessionStart) [ "$SRC" = compact ] || emit_event session.start "$SID" hook.session-start ;;
  SessionEnd) emit_event session.stop "$SID" hook.stop ;;
  SubagentStart)
    # The agent_id pairs with SubagentStop's agent.done; without one, the spawning call's own id.
    _sub="$AID"; [ -n "$_sub" ] || { [ -z "$SID" ] || [ -z "$TUID" ] || _sub="$SID:$TUID"; }
    emit_event agent.spawn "$_sub" hook.subagent-start "$(owner_data)" ;;
  SubagentStop) emit_event agent.done "$AID" hook.subagent-stop "$(owner_data)" ;;
  PostToolUse)
    # No session or call id, no subject: a row nothing can pair or abandon is not worth writing.
    if [ -n "$SID" ] && [ -n "$TUID" ]; then
      case "$TOOL" in
        Monitor|CronCreate|Workflow) bg_start ;;
        Skill) [ -z "$SKILL" ] || emit_event skill.call "$SKILL" hook.post-tool-use "$(owner_data)" ;;
        Read) [ -z "$MEMF" ] || emit_event memory.read "$MEMF" hook.post-tool-use "$(owner_data)" ;;
        ScheduleWakeup) [ "$STOP" = 1 ] || bg_start ;;
        Bash)
          [ "$BG" != 1 ] || bg_start
          if [ "$GHPR" = 1 ] && [ -n "$PR" ]; then
            for _pr in $PR; do
              _repo="${_pr#*/}"; _repo="${_repo%#*}"
              emit_event pr.opened "$_pr" hook.post-tool-use \
                "$(printf '{"session_id":"%s","link":"https://github.com/%s/pull/%s"}' "$SID" "${_pr%#*}" "${_pr#*#}")" "$_repo"
            done
          fi ;;
      esac
    fi ;;
esac
exit 0
