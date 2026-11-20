#!/usr/bin/env sh
# status-network.sh (harbor#1582) — no bulk download over mobile data without the operator's yes (check status.network, operator request 2026-11-19).
#
#   sh status-network.sh [status]          metered or unmetered, and why; refreshes the state the status line and guard-ask read
#   sh status-network.sh guard             the launchd tick: on a metered network pause each loaded job in the heavy list and report any
#                                       other process over HARBOR_STATUS_NETWORK_LIMIT KB/s; on an unmetered one resume what it paused
#   sh status-network.sh allow <label>     let one paused job run on THIS metered network (resumed now; forgotten when it ends)
#   sh status-network.sh forbid <label>    withdraw that yes (paused again at the next tick)
#   sh status-network.sh force metered|unmetered|auto    override detection; auto returns to it
#   sh status-network.sh list              the heavy list, the hog allow-list and the commands guard-ask holds while metered
#   sh status-network.sh hogs              one sample, read-only: each process over the line that is not on the allow-list
#
# Measured 2026-11-19: on an Android hotspot, Colima's self-hosted CI runners pulled 32 MB per 10 s (753 MB in 33 min), each job
# downloading its toolchain again. Low-data work stays on: harbor's own jobs, the event bus, gh polls, browsers and calls.
# METERED when, first match: the force file; the gateway MAC is in <config>/metered-networks (one per line, as `arp -n` prints it);
# a DHCP lease carries the Android hotspot vendor option ANDROID_METERED; a lease from an iPhone hotspot (server 172.20.10.1).
# A probe that cannot read the route or any lease is UNKNOWN and keeps the last mode: a failed read never resumes paused jobs.
# Heavy list: the built-in rows below plus <config>/net-heavy (launchd labels, one per line; stop commands are built-in only, so no
# file feeds `sh -c`). Hog allow-list: the built-in browser and call apps plus <config>/net-hog-allow (one nettop process name or
# name prefix ending at a space or dot). Events (local, bytes): network.metered, network.unmetered, network.paused, network.resumed,
# network.allowed, network.hog. State: ${HARBOR_STATUS_DIR:-~/.local/state/harbor}/net/.
# platform: macOS-only — launchctl, nettop and ipconfig getpacket are the sources; Linux has no hotspot lease to read. Exit: status 0 unmetered, 1 metered; guard 0, or 1 when a hog is reported; 2 usage.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-fs.sh"
log_init status-network
ID='[check:status.network]'
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
NET="${HARBOR_STATUS_DIR:-$HOME/.local/state/harbor}/net"
HOG_KBPS="${HARBOR_STATUS_NETWORK_LIMIT:-200}"
case "$HOG_KBPS" in ''|*[!0-9]*) HOG_KBPS=200 ;; esac
SAMPLE_S=5
U="$(id -u)"
NOW="${HARBOR_TEST_NOW:-$(date +%s)}"
mkdir -p "$NET/allow" 2>/dev/null || { echo "status-network: cannot create $NET" >&2; exit 2; }

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; }

# label <TAB> stop step (`-` none, or a built-in name stop_step knows) <TAB> why. Only what pulls megabytes belongs here.
heavy_list() {
  cat <<'EOF'
sh.brew.colima	colima	the Docker VM and the self-hosted CI runners in it: every job downloads its toolchain again
com.google.GoogleUpdater.wake	-	Google software updates
com.google.keystone.agent	-	Google software updates
com.microsoft.update.agent	-	Microsoft AutoUpdate
com.microsoft.OneDriveStandaloneUpdater	-	OneDrive updates
EOF
  # Operator rows are labels only (security review, harbor#1582): a stop command read from a file would run as the operator outside every guard.
  [ ! -r "$CFG/net-heavy" ] || awk -F'\t' '!/^#/ && $1 ~ /^[A-Za-z0-9._-]+$/ { print $1 "\t-\toperator list" }' "$CFG/net-heavy"
}
stop_step() { # <name> — the built-in stop steps; 0 when the step succeeded
  case "$1" in
    colima) colima stop >/dev/null 2>&1 ;;
    *) return 0 ;;
  esac
}
hog_allow() {
  printf '%s\n' 'Google Chrome' 'Safari' 'com.apple.WebKit' 'firefox' 'Firefox' 'Arc' 'Brave Browser' 'Microsoft Edge' \
    'Microsoft Teams' 'MSTeams' 'com.microsoft.teams' 'zoom.us' 'FaceTime' 'Slack' 'WhatsApp' 'Signal' 'Telegram'
  [ ! -r "$CFG/net-hog-allow" ] || grep -v '^#' "$CFG/net-hog-allow" | grep -v '^$'
}
# Commands guard-ask holds for the operator while metered (`Bash(<glob>)`, the permissions.ask grammar).
ask_rules() {
  printf '%s\n' 'Bash(docker pull *)' 'Bash(docker build *)' 'Bash(docker compose pull*)' 'Bash(docker compose up*)' \
    'Bash(docker run *)' 'Bash(colima start*)' 'Bash(brew install *)' 'Bash(brew upgrade*)' 'Bash(brew update*)' \
    'Bash(brew services start *)' 'Bash(npm install*)' 'Bash(npm ci*)' 'Bash(npm i *)' 'Bash(pnpm install*)' 'Bash(yarn install*)' \
    'Bash(bun install*)' 'Bash(pip install *)' 'Bash(pip3 install *)' 'Bash(uv sync*)' 'Bash(uv pip install *)' 'Bash(git clone *)' \
    'Bash(gh run download *)' 'Bash(gh release download *)' 'Bash(softwareupdate *)' 'Bash(ollama pull *)'
}

# Event data through jq, never by string concatenation: a process name is data a local process chooses.
emit() { # <kind> <subject> [title] [evidence]
  [ -r "$HERE/event-bus.sh" ] || return 0
  _ed='{}'
  if [ -n "${3:-}" ] && command -v jq >/dev/null 2>&1; then
    _ed="$(jq -cn --arg t "$3" --arg e "${4:-}" '{title: $t} + (if $e == "" then {} else {evidence: $e} end)' 2>/dev/null)" || _ed='{}'
  fi
  sh "$HERE/event-bus.sh" emit "$1" "$2" --src status-network --data "$_ed" >/dev/null 2>&1 || :
}

# ── detection ────────────────────────────────────────────────────────────────
detect() { # prints "metered <why>", "unmetered <why>" or "unknown <why>"
  _f=""; [ ! -r "$NET/force" ] || read -r _f < "$NET/force" 2>/dev/null || :
  case "$_f" in metered) echo "metered forced"; return ;; unmetered) echo "unmetered forced"; return ;; esac
  _rt="$(route -n get 1.1.1.1 2>/dev/null | awk '$1 == "interface:" { i = $2 } $1 == "gateway:" { g = $2 } END { if (i != "") print i, g }')" || :
  [ -n "$_rt" ] || { echo "unknown no-route"; return; }
  _if="${_rt%% *}"; _gw="${_rt#* }"; [ "$_gw" != "$_rt" ] || _gw=""
  if [ -n "$_gw" ] && [ -r "$CFG/metered-networks" ]; then
    # The arp line is passed as a variable, not as a first input file: an empty arp output must not shift the file roles.
    _al="$(arp -n "$_gw" 2>/dev/null)" || _al=""
    _m="$(AL="$_al" awk '
      function norm(m,  p, n, i, o) { n = split(tolower(m), p, ":"); if (n != 6) return ""
        for (i = 1; i <= n; i++) o = o (i > 1 ? ":" : "") (length(p[i]) == 1 ? "0" : "") p[i]; return o }
      BEGIN { k = split(ENVIRON["AL"], w, /[ \t]+/); for (i = 1; i < k; i++) if (w[i] == "at") mac = norm(w[i + 1]) }
      { sub(/#.*/, "") } mac != "" && norm($1) == mac { print "yes"; exit }' "$CFG/metered-networks")" || :
    [ "$_m" != yes ] || { echo "metered listed-gateway"; return; }
  fi
  # Behind a VPN the default route is the tunnel: read every Wi-Fi/Ethernet lease instead of the route's interface.
  case "$_if" in en*) _ifs="$_if" ;; *) _ifs="en0 en1 en2 en3 en4 en5 en6 en7 en8" ;; esac
  _read=0
  for _i in $_ifs; do
    _p="$(ipconfig getpacket "$_i" 2>/dev/null)" || continue
    _read=1
    case "$_p" in *ANDROID_METERED*) echo "metered android-hotspot:$_i"; return ;; esac
    case "$_p" in *"server_identifier (ip): 172.20.10.1"*) echo "metered iphone-hotspot:$_i"; return ;; esac
  done
  [ "$_read" = 1 ] || { echo "unknown no-lease:$_if"; return; }
  echo "unmetered $_if"
}

# Writes the mode, refreshes or removes the ask rules guard-ask reads, and emits on a change. Sets MODE and WHY.
# An UNKNOWN reading keeps the last mode (unmetered when there is none) and says so in WHY.
refresh() {
  _d="$(detect)"; _mode="${_d%% *}"; _why="${_d#* }"
  _old=""; [ ! -r "$NET/mode" ] || read -r _ot _old _ow < "$NET/mode" 2>/dev/null || :
  if [ "$_mode" = unknown ]; then
    case "$_old" in metered|unmetered) _mode="$_old" ;; *) _mode=unmetered ;; esac
    _why="kept, probe failed: $_why"
  fi
  printf '%s %s %s\n' "$NOW" "$_mode" "$_why" > "$NET/mode.$$" && mv -f "$NET/mode.$$" "$NET/mode"
  if [ "$_mode" = metered ]; then ask_rules > "$NET/ask-rules.$$" && mv -f "$NET/ask-rules.$$" "$NET/ask-rules"
  else rm -f "$NET/ask-rules"; fi
  # One subject for the pair, so a terminal repeats its start verbatim (docs/design/events.md); the reason rides in evidence.
  if [ "$_old" != "$_mode" ]; then
    if [ "$_mode" = metered ]; then emit network.metered network "metered network: heavy jobs paused, bulk downloads ask first" "$_why"
    else emit network.unmetered network "unmetered network: paused jobs resume" "$_why"; fi
  fi
  MODE="$_mode"; WHY="$_why"
}

# ── pause / resume ───────────────────────────────────────────────────────────
loaded() { launchctl print "gui/$U/$1" >/dev/null 2>&1; }
plist_of() {
  for _pf in "$HOME/Library/LaunchAgents/$1.plist" "/Library/LaunchAgents/$1.plist"; do [ ! -f "$_pf" ] || { echo "$_pf"; return 0; }; done
  return 1
}
is_paused() { [ -r "$NET/paused" ] && grep -qxF "$1" "$NET/paused"; }
unpause() { # <label> — drop it from the paused list
  if [ -r "$NET/paused" ]; then grep -vxF "$1" "$NET/paused" > "$NET/paused.$$" 2>/dev/null; mv -f "$NET/paused.$$" "$NET/paused"; fi
}
# A stop step that fails leaves the job loaded and unpaused, so the next metered tick tries again and says so each time.
pause_one() { # <label> <stop-step>
  if ! stop_step "$2"; then
    log_warn "$ID could not stop $1 ($2 stop failed): left running, retried next tick"
    return 0
  fi
  launchctl disable "gui/$U/$1" 2>/dev/null || :
  launchctl bootout "gui/$U/$1" 2>/dev/null || :
  is_paused "$1" || printf '%s\n' "$1" >> "$NET/paused"
  emit network.paused "$1" "paused on a metered network" "$WHY"
  log_note "$ID paused $1 (metered: $WHY)"
}
# A resume counts only when the job is loaded afterwards; else it stays paused and is retried, or dropped when its plist is gone.
resume_one() { # <label>
  launchctl enable "gui/$U/$1" 2>/dev/null || :
  if ! loaded "$1"; then
    if _pf="$(plist_of "$1")"; then launchctl bootstrap "gui/$U" "$_pf" 2>/dev/null || :
    else
      unpause "$1"
      log_warn "$ID cannot resume $1: no plist in ~/Library/LaunchAgents or /Library/LaunchAgents; dropped from the paused list"
      return 0
    fi
  fi
  if ! loaded "$1"; then
    log_warn "$ID resume of $1 failed (launchctl bootstrap): still paused, retried next tick"
    return 0
  fi
  unpause "$1"
  emit network.resumed "$1"
  log_note "$ID resumed $1"
}

# ── hogs: one nettop delta sample; any process over the line that is not a browser or a call ─────────
# Exit 0 sampled (the hogs on stdout), 2 when nettop failed: a failed sample is not a clean one.
hogs() {
  _allow="$(hog_allow)"
  _raw="$(nettop -P -x -d -L 2 -s "$SAMPLE_S" -J bytes_in,bytes_out 2>/dev/null)" || return 2
  case "$_raw" in *,bytes_in*) ;; *) return 2 ;; esac
  printf '%s\n' "$_raw" | ALLOW="$_allow" awk -F, -v s="$SAMPLE_S" -v lim="$HOG_KBPS" '
    BEGIN { n = split(ENVIRON["ALLOW"], a, "\n") }
    # An entry matches the whole name or a prefix ending at a space or dot (`Slack Helper`, not `Slack-miner`); nettop truncates a
    # name to 15 bytes (`com.microsoft.t`), so a full-length name also matches an entry it is a prefix of.
    function allowed(nm,  i, c) {
      for (i = 1; i <= n; i++) {
        if (a[i] == "") continue
        if (nm == a[i]) return 1
        c = substr(nm, length(a[i]) + 1, 1)
        if (index(nm, a[i]) == 1 && (c == " " || c == ".")) return 1
        if (length(nm) >= 15 && index(a[i], nm) == 1) return 1
      }
      return 0 }
    /^,bytes_in/ { blk++; next }
    blk == 2 && $1 != "" {
      kb = ($2 + $3) / 1024 / s; if (kb < lim) next
      name = $1; sub(/\.[0-9]+$/, "", name)
      if (allowed(name)) next
      printf "%s\t%d\n", name, kb }' | sort -t'	' -k2,2nr
}

guard() {
  refresh
  if [ "$MODE" != metered ]; then
    if [ -s "$NET/paused" ]; then
      cp "$NET/paused" "$NET/paused.todo" 2>/dev/null || :
      while IFS= read -r _l; do [ -z "$_l" ] || resume_one "$_l"; done < "$NET/paused.todo"
      rm -f "$NET/paused.todo"
    fi
    rm -f "$NET/hogs" "$NET/allow/"* 2>/dev/null || :
    return 0
  fi
  heavy_list | while IFS='	' read -r _l _stop _w; do
    [ -n "$_l" ] || continue
    [ ! -e "$NET/allow/$_l" ] || continue
    if loaded "$_l"; then pause_one "$_l" "$_stop"; fi
  done
  _h="$(hogs)"; _hr=$?
  if [ "$_hr" = 2 ]; then
    log_warn "$ID the nettop sample failed: hogs unknown this tick, the last report is kept"
    return 0
  fi
  _prev=""; [ ! -r "$NET/hogs" ] || _prev="$(cut -f1 "$NET/hogs")"
  if [ -n "$_h" ]; then
    printf '%s\n' "$_h" > "$NET/hogs.$$" && mv -f "$NET/hogs.$$" "$NET/hogs"
    printf '%s\n' "$_h" | while IFS='	' read -r _n _kb; do
      log_warn "$ID hog $_n ${_kb} KB/s on mobile data (not stopped: the operator decides; \`status-network.sh hogs\` to look again)"
      printf '%s\n' "$_prev" | grep -qxF "$_n" || emit network.hog "$_n" "$_n ${_kb} KB/s on mobile data" "nettop ${SAMPLE_S} s sample"
    done
    return 1
  fi
  rm -f "$NET/hogs"
  return 0
}

case "${1:-status}" in
  -h|--help) usage; exit 0 ;;
  status)
    refresh
    echo "$MODE ($WHY)"
    [ ! -s "$NET/paused" ] || echo "paused: $(tr '\n' ' ' < "$NET/paused")"
    [ ! -s "$NET/hogs" ] || { echo "hogs:"; awk -F'\t' '{ print "  " $1, $2, "KB/s" }' "$NET/hogs"; }
    [ "$MODE" = metered ] && exit 1; exit 0 ;;
  guard)
    # One tick at a time: WatchPaths can fire while StartInterval's run still samples.
    if ! mkdir "$NET/lock" 2>/dev/null; then
      _lt="$(fs_mtime "$NET/lock" 2>/dev/null)" || _lt=0; case "$_lt" in ''|*[!0-9]*) _lt=0 ;; esac
      [ $((NOW - _lt)) -gt 120 ] || exit 0
      rm -rf "$NET/lock"; mkdir "$NET/lock" 2>/dev/null || exit 0
    fi
    trap 'rm -rf "$NET/lock"' EXIT INT TERM HUP
    guard; _g=$?; log_end || :; exit "$_g" ;;
  allow|forbid)
    _l="${2:-}"; case "$_l" in ''|*[!A-Za-z0-9._-]*) echo "status-network: $1 <launchd-label>" >&2; exit 2 ;; esac
    refresh
    if [ "$1" = allow ]; then
      : > "$NET/allow/$_l"; emit network.allowed "$_l"
      if is_paused "$_l"; then resume_one "$_l"; else log_ok "$ID $_l allowed on this metered network"; fi
    else rm -f "$NET/allow/$_l"; log_ok "$ID $_l no longer allowed; paused at the next tick if metered"; fi
    log_end || :; exit 0 ;;
  force)
    case "${2:-}" in
      metered|unmetered) printf '%s\n' "$2" > "$NET/force" ;;
      auto) rm -f "$NET/force" ;;
      *) echo "status-network: force metered|unmetered|auto" >&2; exit 2 ;;
    esac
    refresh; echo "$MODE ($WHY)"; exit 0 ;;
  hogs) _o="$(hogs)" || { echo "status-network: the nettop sample failed" >&2; exit 2; }
        [ -z "$_o" ] || printf '%s\n' "$_o" | awk -F'\t' '{ print $1, $2, "KB/s" }'; exit 0 ;;
  list)
    echo "heavy (paused when metered):"; heavy_list | cut -f1 | sed 's/^/  /'
    echo "hog allow-list (never reported):"; hog_allow | sed 's/^/  /'
    echo "held for the operator while metered (guard-ask):"; ask_rules | sed 's/^/  /'
    exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
