#!/usr/bin/env sh
# fleet-snapshot-refresh's watch (harbor#618): the same `.helm-watch` facts from launchd and from systemd.
# The refresher runs alone in a temp bin/ with a stub orchestrator, so no sibling job runs. macOS is a stub
# `launchctl list`, Linux a stub `systemctl --user is-active` on a PATH with neither real tool.
# Three installed jobs, two loaded, one whose label is a prefix of a loaded one: both forms must say `watch 2 3`.
# Each branch is then mutated (unanchored match, ignored listing, no is-active, wrong glob) and must go red.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/lib/linux-sim.sh"
W="$T_TMP/w"; mkdir -p "$W/bin" "$W/cfg" "$W/cache"
cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/fleet-snapshot-refresh.sh" "$W/bin/"
printf '#!/bin/sh\nprintf "[{\\"id\\":1}]"\n' > "$W/orch"; chmod +x "$W/orch"
AG="$HOME/Library/LaunchAgents"; SU="$HOME/.config/systemd/user"; mkdir -p "$AG" "$SU"
for _j in usage usage-sessions judge; do : > "$AG/com.harbor.$_j.plist"; : > "$SU/harbor-$_j.timer"; done
: > "$AG/com.example.other.plist"; : > "$SU/other-thing.timer"   # not ours: never counted
TAB="$(printf '\t')"

# macOS: launchctl lists `pid status label`; "-" is a loaded job that is between runs, which is normal.
# A harbor job is listed LAST: $(...) strips the final newline, which once hid it from the anchored match.
MAC="$T_TMP/mac"; mkdir -p "$MAC"
printf '#!/bin/sh\nprintf "PID\\tStatus\\tLabel\\n-\\t0\\tcom.apple.Finder\\n-\\t0\\tcom.harbor.usage-sessions\\n4242\\t0\\tcom.harbor.judge\\n"\n' > "$MAC/launchctl"
chmod +x "$MAC/launchctl"
# Linux: neither real tool on PATH; systemctl answers `--user is-active --quiet <unit>`.
LX="$T_TMP/lx"; linux_path "$LX" launchctl systemctl
printf '#!/bin/sh\ncase "$4" in harbor-usage-sessions.timer|harbor-judge.timer) exit 0 ;; esac\nexit 3\n' > "$LX/systemctl"
chmod +x "$LX/systemctl"
BARE="$T_TMP/bare"; linux_path "$BARE" launchctl systemctl   # a box with no scheduler at all

# run <bindir> <PATH> -> the cache line the statusline reads, or "absent"
run() {
  rm -f "$W/cfg/.helm-watch"
  PATH="$2" CLAUDE_CONFIG_DIR="$W/cfg" HARBOR_CACHE_DIR="$W/cache" HARBOR_ORCH_BIN="$W/orch" HARBOR_FLEET_FILE="$W/fleet.yaml" \
    sh "$1/fleet-snapshot-refresh.sh" >/dev/null 2>&1
  cat "$W/cfg/.helm-watch" 2>/dev/null || echo absent
}
t_eq "control: the Linux PATH has neither launchctl nor systemctl but the stub" "$LX/systemctl" "$(PATH="$LX" command -v systemctl)"
t_eq "control: ...and no launchctl" "" "$(PATH="$LX" command -v launchctl)"
t_eq "control: the bare PATH has no scheduler" "" "$(PATH="$BARE" command -v launchctl systemctl)"

t_section "the watch reads the same on launchd and on systemd"
t_eq "macOS: loaded over installed, a prefix label not counted loaded" "watch 2 3" "$(run "$W/bin" "$MAC:$PATH")"
t_eq "Linux: loaded over installed" "watch 2 3" "$(run "$W/bin" "$LX")"
t_eq "the snapshot itself is still written beside it" "[{\"id\":1}]" "$(cat "$W/cache/fleet-snapshot.json")"

t_section "nothing to watch is not a zero"
t_eq "no scheduler on PATH: no file, never 'watch 0 3'" absent "$(run "$W/bin" "$BARE")"
mv "$AG" "$AG.off"; mv "$SU" "$SU.off"
t_eq "macOS with nothing installed: no file" absent "$(run "$W/bin" "$MAC:$PATH")"
t_eq "Linux with nothing installed: no file" absent "$(run "$W/bin" "$LX")"
mv "$AG.off" "$AG"; mv "$SU.off" "$SU"
printf 'watch 9 9\n' > "$W/cfg/.helm-watch"
PATH="$BARE" CLAUDE_CONFIG_DIR="$W/cfg" HARBOR_CACHE_DIR="$W/cache" HARBOR_ORCH_BIN="$W/orch" sh "$W/bin/fleet-snapshot-refresh.sh" >/dev/null 2>&1
t_eq "no scheduler leaves an earlier cache alone (it did not look)" "watch 9 9" "$(cat "$W/cfg/.helm-watch")"
rm -f "$W/cfg/.helm-watch"
printf '#!/bin/sh\nexit 3\n' > "$LX/systemctl"
t_eq "Linux with no timer active: a real zero" "watch 0 3" "$(run "$W/bin" "$LX")"
printf '#!/bin/sh\nprintf "PID\\tStatus\\tLabel\\n"\n' > "$MAC/launchctl"
t_eq "macOS with nothing loaded: a real zero" "watch 0 3" "$(run "$W/bin" "$MAC:$PATH")"

t_section "red-proof: each branch's mutant answers a different fact"
printf '#!/bin/sh\nprintf "PID\\tStatus\\tLabel\\n-\\t0\\tcom.apple.Finder\\n-\\t0\\tcom.harbor.usage-sessions\\n4242\\t0\\tcom.harbor.judge\\n"\n' > "$MAC/launchctl"
printf '#!/bin/sh\ncase "$4" in harbor-usage-sessions.timer|harbor-judge.timer) exit 0 ;; esac\nexit 3\n' > "$LX/systemctl"
# mutate <name> <awk program>: the refresher with one line changed, alone in its own bin/
mutate() {
  _d="$T_TMP/mut-$1"; rm -rf "$_d"; mkdir -p "$_d"; cp "$W/bin/log-lib.sh" "$_d/"
  awk "$2" "$W/bin/fleet-snapshot-refresh.sh" > "$_d/fleet-snapshot-refresh.sh"
  cmp -s "$W/bin/fleet-snapshot-refresh.sh" "$_d/fleet-snapshot-refresh.sh" && { echo NOT-APPLIED; return; }
  echo "$_d"
}
M="$(mutate substring '$0 == "      *\"\t$_lbl" { print "      *\"$_lbl\"*) _load=$((_load + 1)) ;;"; getline; next } { print }')"
t_eq "mutant: unanchored label match counts usage as loaded" "watch 3 3" "$(run "$M" "$MAC:$PATH")"
M="$(mutate trailing '$0 == "$_listing" { print "$_listing\" in"; getline; next } { print }')"
t_eq "mutant: the listing's last line unwrapped hides a harbor job listed last" "watch 1 3" "$(run "$M" "$MAC:$PATH")"
M="$(mutate nolisting '/_listing="\$\(launchctl/ { print "  _listing=\"\""; next } { print }')"
t_eq "mutant: the launchctl listing ignored loads nothing" "watch 0 3" "$(run "$M" "$MAC:$PATH")"
M="$(mutate noactive '/is-active --quiet/ { print "    _load=$((_load + 1))"; next } { print }')"
t_eq "mutant: no is-active asks, every installed timer counted loaded" "watch 3 3" "$(run "$M" "$LX")"
M="$(mutate glob '{ sub(/harbor-\*\.timer/, "harbor-*.service") } { print }')"
t_eq "mutant: the wrong unit glob finds nothing installed" absent "$(run "$M" "$LX")"
t_eq "unmutated, the same probes are green" "watch 2 3 watch 2 3" "$(run "$W/bin" "$MAC:$PATH" | tr '\n' ' ')$(run "$W/bin" "$LX")"
t_done
