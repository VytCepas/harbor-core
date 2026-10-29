# Shared by tests/event/dispatch/*.test.sh (harbor#1044), sourced after t_init: a hermetic bus pinned to noon
# UTC today, the dispatcher installed into the sandbox config dir as runtime-install would (bytes and manifest
# rows), a docs/reference/checks.md register installed beside it that the suite writes rows into, and a stub `claude` that never
# spends anything. The installed copy is what runs: `dispatch` refuses any other (review r3 #1), and the register
# is read only from {cfg}/bin with its recorded blob (r3 #5). Not a Claude session: the suite is the operator.
unset CLAUDECODE
set -- $(date -u "+%s %Y-%m-%d"); D="$2"; NOON=$(( $1 / 86400 * 86400 + 43200 - $1 ))
BUSDIR="$T_TMP/bus"; CACHE="$T_TMP/cache"   # suites read these, never the knobs
export HARBOR_EVENT_BUS_SKEW="$NOON" HARBOR_EVENT_DIR="$BUSDIR" HARBOR_CACHE_DIR="$CACHE"
CFG="$CLAUDE_CONFIG_DIR"; GT="$CFG/.helm-dispatch"
ST="$BUSDIR/dispatch"; OUT="$T_TMP/out"; LEDGER="$GT/ledger"
record() { # <name>: {cfg}/bin/<name>'s blob, as the runtime-install row of {cfg}/.harbor-manifest
  _b="$(git hash-object --no-filters -- "$CFG/bin/$1")"
  { grep -v " bin/$1 " "$CFG/.harbor-manifest" 2>/dev/null; printf '%s 100755 bin/%s runtime-install test\n' "$_b" "$1"; } > "$CFG/.harbor-manifest.new"
  mv -f "$CFG/.harbor-manifest.new" "$CFG/.harbor-manifest"
}
install_bin() { # <name> <file>: copy into {cfg}/bin and record its blob as runtime-install does
  mkdir -p "$(dirname "$CFG/bin/$1")"; cp "$2" "$CFG/bin/$1"; chmod 755 "$CFG/bin/$1"; record "$1"
}
for _f in event-dispatch.sh event-bus.sh library-log.sh; do install_bin "$_f" "$T_ROOT/bin/$_f"; done
ED="$CFG/bin/event-dispatch.sh"; EB="$CFG/bin/event-bus.sh"; CKS="$CFG/bin/docs/reference/checks.md"; mkdir -p "$CFG/bin/docs/reference"
printf '# fixture\n\n## Register\n\n| id | watches | schedule | notifies | red means |\n|---|---|---|---|---|\n' > "$CKS"; record docs/reference/checks.md
register() { # <id> <kind>... — a register row naming each kind and the disable command, re-recorded
  _rid="$1"; shift; _ks=""
  for _k in "$@"; do _ks="$_ks \`$_k\`"; done
  printf '| `%s` | a test rule | fires on%s; off: `harbor event on --off %s` | none | a test failed |\n' "$_rid" "$_ks" "$_rid" >> "$CKS"
  record docs/reference/checks.md
}
spend_file() { echo "$GT/spend/$(( ($(date -u +%s) + ${HARBOR_EVENT_BUS_SKEW:-0}) / 86400 ))"; }   # today's, as the dispatcher counts it
emit() { sh "$EB" emit "$@" 2>/dev/null; }                     # <kind> <subject> [opts] → the id
dispatch_once() { sh "$ED" dispatch --once 2>>"$T_TMP/dispatch.err"; }
outcomes() { awk -F'\t' -v r="$1" '$4 == r { print $5 }' "$LEDGER" 2>/dev/null | sort | uniq -c | awk '{ printf "%s=%s ", $2, $1 }'; }
lines() { if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi; }
until_file() { _n=0; while [ ! -s "$1" ] && [ "$_n" -lt $(( $2 * 10 )) ]; do sleep 0.1; _n=$((_n + 1)); done; [ -s "$1" ]; }
# The stub runs under the dispatcher's env -i, so it reads nothing from the environment: its dir is baked in,
# the cost is the file stub.cost (absent: 0.05; `none`: no total_cost_usd), and stub.block makes it wait.
cat > "$T_BIN/claude" <<STUB
#!/bin/sh
D='$T_TMP'
STUB
cat >> "$T_BIN/claude" <<'STUB'
for a in "$@"; do printf '%s' "$a" | tr '\n' '~'; echo; done > "$D/claude.argv"
printf 'key=%s cause=%s\n' "${ANTHROPIC_API_KEY-unset}" "${HARBOR_EVENT_CAUSE-}" > "$D/claude.env"
env > "$D/claude.envdump"
printf 'pwd=%s\nentries=%s\nship=%s\n' "$PWD" "$(ls -A | grep -c .)" "${SHIP_UNATTENDED-unset}" > "$D/claude.ctx"
echo "$$" >> "$D/claude.starts"
if [ -e "$D/stub.block" ]; then while [ -e "$D/stub.block" ]; do sleep 0.1; done; fi
# stub.hook names a hook script: run it as Claude Code runs a SessionStart command hook, with this process's env.
if [ -s "$D/stub.hook" ]; then printf '{"hook_event_name":"SessionStart","session_id":"agent-sess-%s","source":"startup"}' "$$" | /bin/sh "$(cat "$D/stub.hook")"; fi
c=0.05; [ ! -f "$D/stub.cost" ] || read -r c < "$D/stub.cost"
case "$c" in
  none) printf '{"type":"result","is_error":false,"session_id":"stub-sess-1","result":"ok"}\n' ;;
  *) printf '{"type":"result","is_error":false,"total_cost_usd":%s,"session_id":"stub-sess-1","result":"ok"}\n' "$c" ;;
esac
STUB
chmod +x "$T_BIN/claude"
stub_cost() { if [ -n "${1-}" ]; then printf '%s\n' "$1" > "$T_TMP/stub.cost"; else rm -f "$T_TMP/stub.cost"; fi; }
# A cmd rule runs only `sh {cfg}/bin/<allowlisted script>` whose bytes {cfg}/.harbor-manifest records (review r2
# #1). The suites install a stand-in alert-notify.sh there, with the row runtime-install would write, that runs
# $T_TMP/h/<rule id>.sh, else $T_TMP/h/default.sh: the real allowlist and hash check, each test's own behaviour.
HND="$CFG/bin/alert-notify.sh"
printf '#!/bin/sh\nf="%s/h/$HARBOR_EVENT_RULE.sh"; [ -f "$f" ] || f="%s/h/default.sh"\nexec /bin/sh "$f" "$@"\n' "$T_TMP" "$T_TMP" > "$T_TMP/router.sh"
install_bin alert-notify.sh "$T_TMP/router.sh"
handler() { mkdir -p "$T_TMP/h"; cp "$2" "$T_TMP/h/$1.sh"; }   # <rule id | default> <script>
