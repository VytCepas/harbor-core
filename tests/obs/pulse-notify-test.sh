#!/usr/bin/env sh
# pulse-notify.sh (harbor#9, E1), driven by a fake probe: a copy of the notifier beside a
# stub pulse.sh lets every edge (first warn, unchanged, recovery, persisting crit, unknown)
# be produced on demand. osascript is a stub that records its argv, so nothing is sent.
# A silent run must say notifications: 0; the first notifier counted the carried-forward map.
. "$(dirname "$0")/../lib/core.sh"; t_init
TMP="$T_TMP/pn"; mkdir -p "$TMP/stub" "$TMP/nbin"
# The sink stub consumes stdin, as the real osascript is handed its script there.
cat > "$TMP/stub/osascript" <<STUB
#!/bin/sh
cat >/dev/null 2>&1
printf 'SENT\t%s\n' "\$*" >> "$TMP/sent.log"
exit 0
STUB
chmod +x "$TMP/stub/osascript"; : > "$TMP/sent.log"
sent() { grep -c '^SENT' "$TMP/sent.log" 2>/dev/null | tr -d ' '; }
sent_with() { grep -c "$1" "$TMP/sent.log" 2>/dev/null | tr -d ' '; }
cp "$T_ROOT/bin/pulse-notify.sh" "$T_ROOT/bin/log-lib.sh" "$TMP/nbin/"  # log-lib: installed beside it
fake() { printf '%s' "$1" > "$TMP/probe.json"; }
probe_reads_fixture() { printf '#!/bin/sh\ncat "%s"\n' "$TMP/probe.json" > "$TMP/nbin/pulse.sh"; chmod +x "$TMP/nbin/pulse.sh"; }
probe_reads_fixture
mkjson() { # <verdict> <detail>
  jq -n --arg v "$1" --arg d "$2" '{ran_at: 1700000000, generated:"x", inputs_seen:1, checks_run:1, worst:$v, checks:{demo:{verdict:$v, detail:$d}}}'
}
nrun() { PATH="$TMP/stub:$PATH" HARBOR_CACHE_DIR="$TMP/ncache" HARBOR_PULSE_STATE="$TMP/ncache/state.json" sh "$TMP/nbin/pulse-notify.sh" "$@" 2>&1; }
nstate() { jq -r "$1" "$TMP/ncache/state.json" 2>/dev/null; }
has_state() { [ -f "$1" ] && echo yes || echo no; }
fresh() { rm -f "$TMP/ncache/state.json"; : > "$TMP/sent.log"; }

t_section "--dry-run says what it would do, and writes nothing"
fake "$(mkjson warn 'the fixture is unhappy')"
t_has "--dry-run prints its intent" "$(nrun --dry-run)" "would notify"
t_eq "--dry-run wrote no state" no "$(has_state "$TMP/ncache/state.json")"
t_eq "--dry-run did not reach the sink" 0 "$(sent)"

t_section "edges speak once, and a silent run says so"
nrun >/dev/null
t_eq "a new warn sends one" 1 "$(sent)"
t_eq "the state records the one it sent" 1 "$(nstate '.notifications')"
nrun >/dev/null
t_eq "the same warn again sends nothing" 1 "$(sent)"
t_eq "a silent run reports notifications 0" 0 "$(nstate '.notifications')"
fake "$(mkjson ok 'the fixture is fine')"; nrun >/dev/null
t_eq "a recovery is news" 2 "$(sent)"
t_eq "the recovery is worded as one" 1 "$(sent_with RECOVERED)"
nrun >/dev/null
t_eq "a steady ok stays quiet" 2 "$(sent)"
fake "$(mkjson unknown 'the source went away')"; nrun >/dev/null
t_eq "unknown never speaks" 2 "$(sent)"

t_section "a persisting crit repeats only after the reminder window"
fake "$(mkjson crit 'the fixture is on fire')"; nrun >/dev/null
t_eq "a new crit speaks" 3 "$(sent)"
nrun >/dev/null
t_eq "inside the window it does not repeat" 3 "$(sent)"
PATH="$TMP/stub:$PATH" HARBOR_CACHE_DIR="$TMP/ncache" HARBOR_PULSE_STATE="$TMP/ncache/state.json" HARBOR_PULSE_REMIND=0 \
  sh "$TMP/nbin/pulse-notify.sh" >/dev/null 2>&1
t_eq "past the window it repeats" 4 "$(sent)"
t_eq "the reminder is worded as one" 1 "$(sent_with 'STILL CRIT')"

t_section "a path in a detail never reaches the lock screen"
fake "$(mkjson warn "the file /Users/someone/.claude/settings.json drifted")"; nrun >/dev/null
t_hasnt "no absolute path reaches the sink" "$(cat "$TMP/sent.log")" "/Users/someone"
t_has "the scrubber ran on the body" "$(cat "$TMP/sent.log")" "[path]"

t_section "it refuses to write through something that is not a regular file"
rm -rf "$TMP/fifo"; mkdir -p "$TMP/fifo"; mkfifo "$TMP/fifo/state.json"
t_exit "a fifo at the state path" 1 env PATH="$TMP/stub:$PATH" HARBOR_CACHE_DIR="$TMP/fifo" HARBOR_PULSE_STATE="$TMP/fifo/state.json" sh "$TMP/nbin/pulse-notify.sh"
t_has "the refusal says why" "$(PATH="$TMP/stub:$PATH" HARBOR_CACHE_DIR="$TMP/fifo" HARBOR_PULSE_STATE="$TMP/fifo/state.json" sh "$TMP/nbin/pulse-notify.sh" 2>&1)" "not a regular file"
rm -f "$TMP/fifo/state.json"

t_section "an unknown in between neither swallows nor repeats an edge (REVIEW #106)"
fresh
fake "$(mkjson warn 'unhappy')"; nrun >/dev/null
fake "$(mkjson unknown 'gone')"; nrun >/dev/null
fake "$(mkjson ok 'fine')"; nrun >/dev/null
t_eq "warn, unknown, ok still reports the recovery" 1 "$(sent_with RECOVERED)"
fresh
fake "$(mkjson warn 'unhappy')"; nrun >/dev/null
fake "$(mkjson unknown 'gone')"; nrun >/dev/null
fake "$(mkjson warn 'unhappy')"; nrun >/dev/null
t_eq "one standing warn across an unknown is announced once" 1 "$(sent)"

t_section "a sink that refuses does not mark the edge delivered (REVIEW #106)"
fresh; mkdir -p "$TMP/deadstub"
printf '#!/bin/sh\nexit 1\n' > "$TMP/deadstub/osascript"; chmod +x "$TMP/deadstub/osascript"
fake "$(mkjson warn 'unhappy')"
PATH="$TMP/deadstub:$PATH" HARBOR_CACHE_DIR="$TMP/ncache" HARBOR_PULSE_STATE="$TMP/ncache/state.json" sh "$TMP/nbin/pulse-notify.sh" >/dev/null 2>&1
t_eq "a refused send is not recorded as delivered" none "$(nstate '.notified.demo.verdict // "none"')"
nrun >/dev/null
t_eq "the edge is retried once the sink comes back" 1 "$(sent)"

t_section "--selftest speaks unconditionally, and changes nothing"
_before="$(sent)"; rm -f "$TMP/ncache/state.json"
fake "$(mkjson ok 'nothing to report')"; nrun --selftest >/dev/null
t_eq "--selftest sends exactly one banner" "$((_before + 1))" "$(sent)"
t_eq "--selftest wrote no state" no "$(has_state "$TMP/ncache/state.json")"

t_section "Linux: with no osascript, notify-send is the sink (harbor#618)"
# A PATH with every tool this host has except osascript, and a notify-send that records.
. "$T_ROOT/tests/lib/linux-sim.sh"; LX="$TMP/linux"; linux_path "$LX" osascript notify-send
printf '#!/bin/sh\nprintf "SENT\\tnotify-send %%s\\n" "$*" >> "%s"\nexit 0\n' "$TMP/sent.log" > "$LX/notify-send"; chmod +x "$LX/notify-send"
lrun() { PATH="$LX" HARBOR_CACHE_DIR="$TMP/ncache" HARBOR_PULSE_STATE="$TMP/ncache/state.json" sh "$TMP/nbin/pulse-notify.sh" "$@" 2>&1; }
t_eq "control: the Linux PATH has no osascript" "" "$(PATH="$LX" command -v osascript)"
fresh; fake "$(mkjson warn 'unhappy on linux')"; lrun >/dev/null
t_eq "a new warn reaches notify-send" 1 "$(sent_with 'notify-send')"
t_has "...naming the check" "$(cat "$TMP/sent.log")" "demo"
t_eq "...and the edge is recorded as delivered" warn "$(nstate '.notified.demo.verdict // "none"')"
_before="$(sent)"; lrun --selftest >/dev/null
t_eq "--selftest speaks through notify-send too" "$((_before + 1))" "$(sent)"
printf '#!/bin/sh\nexit 1\n' > "$LX/notify-send"; fresh; _held="$(lrun)"
t_eq "WSL2 shape: a notify-send with no daemon behind it leaves the edge unrecorded" none "$(nstate '.notified.demo.verdict // "none"')"
t_has "...and says so in one note, naming the sink (harbor#618)" "$_held" "  note: 1 banner(s) held: sink=notify-send did not take them"
t_eq "...exactly once" 1 "$(printf '%s\n' "$_held" | grep -c 'banner(s) held')"
rm -f "$LX/notify-send"; fresh; _held="$(lrun)"
t_eq "with neither sink the edge stays unrecorded, to be said later" none "$(nstate '.notified.demo.verdict // "none"')"
t_has "...with the same one note, sink=absent" "$_held" "  note: 1 banner(s) held: sink=absent did not take them"
t_eq "a run with nothing to say makes no note" 0 "$(fake "$(mkjson ok 'nothing to report')"; fresh; lrun | grep -c 'banner(s) held')"
t_exit "...and --selftest says there is no sink" 1 lrun --selftest

t_section "a failing probe writes no state at all"
rm -f "$TMP/ncache/state.json"
printf '#!/bin/sh\nexit 1\n' > "$TMP/nbin/pulse.sh"; chmod +x "$TMP/nbin/pulse.sh"
nrun >/dev/null 2>&1
t_eq "a failed probe wrote no state" no "$(has_state "$TMP/ncache/state.json")"
probe_reads_fixture

t_section "it will not speak if it cannot record that it spoke (REVIEW #106)"
fresh; mkdir -p "$TMP/rocache"; chmod 500 "$TMP/rocache"
if [ "$(id -u)" = 0 ]; then echo "  (skipped: running as root, so discretionary permissions do not apply)"
else
  fake "$(mkjson warn 'unhappy')"
  O="$(PATH="$TMP/stub:$PATH" HARBOR_CACHE_DIR="$TMP/rocache" HARBOR_PULSE_STATE="$TMP/rocache/state.json" sh "$TMP/nbin/pulse-notify.sh" 2>&1)"; _rc=$?
  t_eq "an unwritable state path stops the run" 1 "$_rc"
  t_eq "it spoke nothing it could not record" 0 "$(sent)"
  t_has "the refusal explains itself" "$O" "repeats forever"
fi
chmod 700 "$TMP/rocache"

t_section "every run leaves a receipt on stdout (REVIEW #106)"
rm -f "$TMP/ncache/state.json"
fake "$(mkjson ok 'fine')"; O="$(nrun)"
t_has "the receipt names the worst verdict" "$O" "pulse: worst=ok"
t_has "the receipt carries the answered count" "$O" "answered=1/1"

t_section "the dashboard reads the cache dir the writer resolved (REVIEW #106)"
mkdir -p "$TMP/dash" "$TMP/dashcfg"
jq -n '{ran_at: 1700000000, generated:"x", inputs_seen:2, checks_run:2, worst:"warn", sink:"osascript",
        notifications:0, checks:{demo:{verdict:"warn", detail:"a fixture verdict"}}}' > "$TMP/dash/pulse-state.json"
echo '[]' > "$TMP/dash/fleet-snapshot.json"
dash() { CLAUDE_CONFIG_DIR="$TMP/dashcfg" HARBOR_CACHE_DIR="$1" sh "$T_ROOT/bin/dashboard-gen.sh" --stdout 2>/dev/null; }
PAGE="$(dash "$TMP/dash")"
t_has "the fixture verdict reaches the Pulse tile" "$PAGE" ">demo<"
t_hasnt "the Pulse tile honours HARBOR_CACHE_DIR" "$PAGE" "No probe has run"
t_has "an empty fleet array is worded as one" "$PAGE" "lists no repos"
t_hasnt "an empty fleet is not a broken cache" "$PAGE" "not the array"
# The positive twins: both needles are real wording, reached from a cache without the files.
mkdir -p "$TMP/dash2"; echo '{"repos":[]}' > "$TMP/dash2/fleet-snapshot.json"
PAGE2="$(dash "$TMP/dash2")"
t_has "a cache with no pulse state says so" "$PAGE2" "No probe has run"
t_has "a snapshot that is not an array says so" "$PAGE2" "not the array"
t_done
