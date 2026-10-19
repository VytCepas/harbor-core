#!/usr/bin/env sh
# CHECKS.md's Platforms table (harbor#617): every register row states where it runs, and every
# launchd-scheduled row either has a systemd user timer that runs the same argv on the same
# schedule, or says why it has none. The plist is the source; the unit is held to it.
. "$(dirname "$0")/../lib/core.sh"; t_init
R="${SCHED_ROOT:-$T_ROOT}"
CK="$R/CHECKS.md"
# Register ids; a row is a launchd job when its plist is tracked (lint X9 owns the converse).
reg="$(awk -F'|' '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `[a-z0-9.-]+` \|/ { id = $2; gsub(/[` ]/, "", id); print id }' "$CK" \
  | while read -r _id; do if [ -f "$R/launchd/com.harbor.$_id.plist" ]; then echo "$_id launchd"; else echo "$_id other"; fi; done)"
# Platforms rows: | id | platforms | why | disable |. The id is bare, not backticked: lint X9 reads
# every "| `id` |" row in the file as a register row.
plat="$(awk -F'|' '/^## Platforms/ { p = 1; next } /^## / { p = 0 } p && /^\| [a-z0-9.-]+ \|/ && $2 != " id " {
  id = $2; gsub(/ /, "", id); v = $3; gsub(/^ +| +$/, "", v); print id "\t" v }' "$CK")"
cell() { awk -F'|' -v id="$1" -v c="$2" '/^## Platforms/ { p = 1; next } /^## / { p = 0 }
  p && $2 == " " id " " { print $c; exit }' "$CK"; }

t_section "every register row has exactly one Platforms row, and no Platforms row is orphaned"
t_eq "the register parsed" yes "$([ "$(printf '%s\n' "$reg" | grep -c .)" -ge 20 ] && echo yes || echo no)"
t_eq "the register ids equal the Platforms ids" \
  "$(printf '%s\n' "$reg" | awk '{print $1}' | sort)" "$(printf '%s\n' "$plat" | cut -f1 | sort)"
t_eq "no id is listed twice" "" "$(printf '%s\n' "$plat" | cut -f1 | sort | uniq -d)"
t_eq "every platforms cell is one of the four declared values" "" \
  "$(printf '%s\n' "$plat" | awk -F'\t' '$2 !~ /^(macOS, Linux|macOS only|macOS; Linux undecided|inherits: .+)$/ { print $1 ": " $2 }')"

# plist → "argv<TAB>schedule<TAB>runatload", with the template's @HOME@ (harbor#630) replaced by systemd's %h.
# Flattened and comment-stripped first: a plist may split a <key> and its value across lines.
plist_facts() {
  tr -d '\n\t' < "$1" | awk '
    function val(s, key,   i) { i = index(s, "<key>" key "</key>"); if (!i) return ""; s = substr(s, i + length(key) + 11)
      sub(/^ */, "", s); return s }
    function first(s, tag,   i, j) { i = index(s, "<" tag ">"); if (!i) return ""; s = substr(s, i + length(tag) + 2)
      j = index(s, "</" tag ">"); return substr(s, 1, j - 1) }
    { s = $0
      while ((i = index(s, "<!--")) > 0) { j = index(substr(s, i), "-->"); s = substr(s, 1, i - 1) substr(s, i + j + 2) }
      a = val(s, "ProgramArguments"); a = substr(a, 1, index(a, "</array>") - 1); argv = ""
      while ((i = index(a, "<string>")) > 0) { a = substr(a, i + 8); j = index(a, "</string>")
        argv = argv (argv == "" ? "" : " ") substr(a, 1, j - 1); a = substr(a, j + 9) }
      sched = ""
      iv = val(s, "StartInterval"); if (iv != "") sched = "every " first(iv, "integer") "s"
      ci = val(s, "StartCalendarInterval")
      if (ci != "") { ci = substr(ci, 1, index(ci, "</dict>")); sched = sprintf("daily %02d:%02d", first(val(ci, "Hour"), "integer"), first(val(ci, "Minute"), "integer")) }
      r = val(s, "RunAtLoad"); r = (r ~ /^<true\/>/) ? "yes" : "no"
      gsub(/@HOME@/, "%h", argv); print argv "\t" sched "\t" r }'
}
# unit pair → the same three facts, read from ExecStart, OnUnitActiveSec/OnCalendar and OnActiveSec.
unit_facts() { # <service> <timer>
  _argv="$(sed -n 's/^ExecStart=//p' "$1")"
  _sched="$(awk -F= '/^OnUnitActiveSec=/ { print "every " $2 } /^OnCalendar=/ { split($2, t, " "); sub(/:00$/, "", t[2]); print "daily " t[2] }' "$2")"
  _ral="$(grep -q '^OnActiveSec=' "$2" && echo yes || echo no)"
  printf '%s\t%s\t%s\n' "$_argv" "$_sched" "$_ral"
}

t_section "a launchd row that runs on Linux has a systemd user timer equal to its plist"
_n=0
for id in $(printf '%s\n' "$reg" | awk '$2 == "launchd" { print $1 }'); do
  v="$(printf '%s\n' "$plat" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')"
  svc="$R/systemd/harbor-$id.service"; tmr="$R/systemd/harbor-$id.timer"; pl="$R/launchd/com.harbor.$id.plist"
  case "$v" in
    'macOS, Linux')
      _n=$((_n + 1))
      # harbor#1181: a plist with UserName is a SYSTEM job, its twin a system unit with User=, both stopped with sudo;
      # a KeepAlive plist is a daemon, its twin a service with Restart=always and no timer.
      _sys=no; grep -q '<key>UserName</key>' "$pl" 2>/dev/null && _sys=yes
      _ka=no; tr -d '\n\t ' < "$pl" 2>/dev/null | grep -q '<key>KeepAlive</key><true/>' && _ka=yes
      if [ "$_ka" = yes ]; then
        t_eq "$id: the daemon's service is tracked" yes "$([ -f "$svc" ] && echo yes || echo no)"
        [ -f "$svc" ] || continue
        t_eq "$id: argv equals the plist's" "$(plist_facts "$pl" | cut -f1)" "$(sed -n 's/^ExecStart=//p' "$svc")"
        t_eq "$id: it is restarted like KeepAlive" Restart=always "$(grep '^Restart=' "$svc")"
        t_eq "$id: no timer claims a daemon" no "$([ -f "$tmr" ] && echo yes || echo no)"
        t_has "$id: the disable cell stops the service" "$(cell "$id" 5)" "sudo systemctl disable --now harbor-$id.service"
        t_has "$id: ...and the launchd job" "$(cell "$id" 5)" "launchctl bootout system/com.harbor.$id"
        continue
      fi
      t_eq "$id: both units are tracked" "yes yes" "$([ -f "$svc" ] && echo yes || echo no) $([ -f "$tmr" ] && echo yes || echo no)"
      [ -f "$svc" ] && [ -f "$tmr" ] || continue
      t_eq "$id: argv, schedule and run-at-start equal the plist's" "$(plist_facts "$pl")" "$(unit_facts "$svc" "$tmr")"
      t_eq "$id: the timer starts its own service" "Unit=harbor-$id.service" "$(grep '^Unit=' "$tmr")"
      t_eq "$id: the timer is enabled into timers.target" "WantedBy=timers.target" "$(grep '^WantedBy=' "$tmr")"
      _stop="systemctl --user disable --now harbor-$id.timer"; [ "$_sys" = no ] || _stop="sudo systemctl disable --now harbor-$id.timer"
      [ "$_sys" = no ] || t_has "$id: a system unit runs as its own user" "$(grep '^User=' "$svc")" User=
      t_has "$id: the disable cell stops the systemd timer" "$(cell "$id" 5)" "$_stop"
      _dom="gui/\$(id -u)"; [ "$_sys" = no ] || _dom=system
      t_has "$id: ...and the launchd job" "$(cell "$id" 5)" "launchctl bootout $_dom/com.harbor.$id" ;;
    'macOS only'|'macOS; Linux undecided')
      t_eq "$id ($v): no systemd unit claims it" "no no" "$([ -f "$svc" ] && echo yes || echo no) $([ -f "$tmr" ] && echo yes || echo no)"
      t_eq "$id ($v): the row gives its reason" yes "$([ "$(cell "$id" 4 | tr -d ' ')" != "" ] && echo yes || echo no)"
      # a plist that names a UserName is a SYSTEM daemon (/Library/LaunchDaemons), stopped in the system domain (harbor#1181)
      _dom="gui/\$(id -u)"; grep -q "<key>UserName</key>" "$pl" 2>/dev/null && _dom=system
      t_has "$id ($v): the disable cell stops the launchd job" "$(cell "$id" 5)" "launchctl bootout $_dom/com.harbor.$id" ;;
    *) t_fail "$id is a launchd job, so it must be 'macOS, Linux', 'macOS only' or 'macOS; Linux undecided' (got '$v')" ;;
  esac
done
t_eq "at least one row is ported, so the parity checks above ran" yes "$([ "$_n" -ge 1 ] && echo yes || echo no)"

t_section "every tracked unit belongs to a ported row"
_orph=''
for u in "$R"/systemd/harbor-*.service "$R"/systemd/harbor-*.timer; do
  [ -f "$u" ] || continue
  id="${u##*/harbor-}"; id="${id%.*}"
  [ "$(printf '%s\n' "$plat" | awk -F'\t' -v id="$id" '$1 == id { print $2 }')" = 'macOS, Linux' ] || _orph="$_orph ${u##*/}"
done
t_eq "no unit without a 'macOS, Linux' row" "" "$_orph"

t_section "the plist reader is not blind (a parser that returns nothing would make every unit 'equal')"
t_eq "pulse's plist reads as the argv, interval and run-at-load it holds" \
  "$(printf '/bin/sh %%h/.claude/bin/pulse-notify.sh\tevery 900s\tyes')" "$(plist_facts "$R/launchd/com.harbor.pulse.plist")"
t_eq "judge's reads its calendar time" "daily 05:23" "$(plist_facts "$R/launchd/com.harbor.judge.plist" | cut -f2)"

t_section "every event rule's schedule names its trigger events and its disable command (harbor#1044)"
_nr=0
for id in $(awk -F'\t' '!/^#/ && NF == 6 { print $1 }' "$R/CONTRACTS/event-rules.tsv"); do
  _nr=$((_nr + 1)); _sc="$(awk -F'|' -v id="$id" '$2 == " `" id "` " { print $4; exit }' "$CK")"
  for k in $(awk -F'\t' -v id="$id" '$1 == id { s = $2; gsub(/\\/, "", s); while (match(s, /[a-z0-9-]+(\.[a-z0-9-]+)+/)) { print substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }' "$R/CONTRACTS/event-rules.tsv"); do
    t_has "$id names its trigger $k" "$_sc" "\`$k\`"
  done
  t_has "$id names its disable command" "$_sc" "\`harbor event on --off $id\`"
done
t_eq "the rules file was read" yes "$([ "$_nr" -ge 2 ] && echo yes || echo no)"

t_section "systemd itself accepts the units (Linux only)"
# `--user verify` needs a running systemd: in a container it fails "Failed to initialize manager".
# /run/systemd/system is sd_booted()'s own test, so that is what decides "running".
_booted="$([ -d /run/systemd/system ] && echo yes || echo no)"
if command -v systemd-analyze >/dev/null 2>&1 && [ "$_booted" = no ]; then
  printf 'SKIP: systemd is not PID 1 here (a container?) — systemd-analyze --user verify NOT run\n'
  t_eq "systemd-analyze is present but systemd is not running, so this section only records that" no "$_booted"
elif command -v systemd-analyze >/dev/null 2>&1; then
  # A unit systemd half-understands exits 0 with a warning ("Failed to parse …, ignoring"), so silence is the pass.
  _sv="$(systemd-analyze --user verify "$R"/systemd/harbor-*.timer "$R"/systemd/harbor-*.service 2>&1; echo "rc=$?")"
  t_eq "systemd-analyze verify accepts every unit, with nothing to say" "rc=0" "$_sv"
else
  t_eq "no systemd-analyze here, so this section only records that (runs on ubuntu CI)" no "$(command -v systemd-analyze >/dev/null 2>&1 && echo yes || echo no)"
fi
t_done
