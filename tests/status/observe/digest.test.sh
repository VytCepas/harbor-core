#!/usr/bin/env sh
# harbor#350: the ledger's per-command digest reaches the decision verdicts (deny/ask), not
# only block. The guards run as copies inside a fixture tree, because floor_log_decision
# resolves its sink from the guard's own path (harbor#343). Two negative controls revert
# one half of the fix each and must send the digest back to "-". Isolation is asserted on
# state this suite owns: every fire must land in the fixture sink (harbor#373, #430), and
# no fixture record may reach a sandbox ledger, or the LIVE one, ruled by content: a per-run nonce (harbor#696).
# Read before t_init, which sandboxes HOME and the config dir; the live ledger is read, never written.
REAL_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; REQ_LIVE="${HARBOR_REQUIRE_LIVE_LEDGER:-0}"
. "$(dirname "$0")/../../lib/core.sh"; t_init
NONCE="$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"; NONCE="${NONCE:-$$$(date +%s)}"
LIVE_LEDGER="$(find "$REAL_CFG/MEMORY/OBSERVABILITY" -maxdepth 2 -name guard-decisions.jsonl 2>/dev/null | head -1)"
TMP="$T_TMP/od"; H=fixturehost; CFG="$TMP/tree"
mkdir -p "$CFG/bin" "$CFG/MEMORY/OBSERVABILITY/$H"
for _f in library-admission.sh admission-normalize.awk admission-destroy.sh admission-cloud.sh; do cp "$T_ROOT/bin/$_f" "$CFG/bin/$_f"; done
SINK="$CFG/MEMORY/OBSERVABILITY/$H/guard-decisions.jsonl"
printf '%s\n' "$H" > "$CFG/.helm-obs-host"
printf '%s\n' '0123456789abcdef0123456789abcdef' > "$CFG/.helm-obs-salt"  # fixture-only salt
: > "$SINK"
chmod 555 "$CFG/MEMORY/OBSERVABILITY/$H"  # the anti-tamper gate: a writable dir makes the logger skip
# The ledgers a misrouted record could reach: both sandbox config roots, empty at the start.
ledgers() { find "$CLAUDE_CONFIG_DIR/MEMORY/OBSERVABILITY" "$HOME/.claude/MEMORY/OBSERVABILITY" -name 'guard-decisions.jsonl' 2>/dev/null; }
ledgers | while IFS= read -r _lf; do printf '%s\t%s\t%s\n' "$(wc -c < "$_lf" | tr -d ' ')" "$(ls -i "$_lf" | awk '{print $1}')" "$_lf"; done > "$TMP/ledgers-before"
LIVE="$(ledgers | head -1)"
live_inode() { [ -n "$LIVE" ] && [ -f "$LIVE" ] && ls -i "$LIVE" 2>/dev/null | awk '{print $1}' || printf 0; }
LIVE_INO_BEFORE="$(live_inode)"
# Payloads live in files, never on a command line: the ambient floor inspects argv.
pay() { printf '{"session_id":"od-%s","tool_name":"Bash","tool_input":{"command":"%s"}}\n' "$NONCE" "$1" > "$TMP/p.json"; }
FIRE_N=0; EMPTY_FIRES=''
fire() { # <guard-basename-without-.sh>; truncates the sink, so each fire's record is its own
  : > "$SINK"; FIRE_N=$((FIRE_N + 1))
  [ -f "$CFG/bin/$1.sh" ] || { t_fail "harness: no $1.sh in the fixture tree"; return 1; }
  cat "$TMP/p.json" | sh "$CFG/bin/$1.sh" >/dev/null 2>&1 || true
  [ -s "$SINK" ] || EMPTY_FIRES="$EMPTY_FIRES $FIRE_N"
  jq -r '.h // empty, .sk // empty' "$SINK" 2>/dev/null | grep -E '^[0-9a-f]{16}$' >> "$TMP/fixture-digests" 2>/dev/null || true
}
hh() { tail -1 "$SINK" 2>/dev/null | jq -r '.h // "NOREC"' 2>/dev/null || echo NOREC; }
dd() { tail -1 "$SINK" 2>/dev/null | jq -r '.d // "NOREC"' 2>/dev/null || echo NOREC; }
hex16() { printf '%s' "$1" | grep -qxE '[0-9a-f]{16}' && echo yes || echo "no ($1)"; }

t_section "the fixture works at all, or nothing below discriminates"
pay "diskutil eraseDisk JHFS+ Fixture$NONCE /dev/disk99"
fire admission-destroy
t_eq "the fixture sink received the first record" yes "$([ -s "$SINK" ] && echo yes || echo no)"
[ -s "$SINK" ] || { echo "obs-digest-test: fixture sink empty — isolation broken, refusing to report" >&2; t_done; }
t_eq "the fixture payload is a deny" deny "$(dd)"

t_section "a deny carries a stable, discriminating digest"
D1="$(hh)"
t_eq "a deny carries a 16-hex digest" yes "$(hex16 "$D1")"
fire admission-destroy
t_eq "the same command gives the same digest" "$D1" "$(hh)"
pay "diskutil eraseDisk JHFS+ Other$NONCE /dev/disk98"
fire admission-destroy; D3="$(hh)"
t_eq "a different command gives a different 16-hex digest" yes "$([ "$D3" != "$D1" ] && [ "$(hex16 "$D3")" = yes ] && echo yes || echo "no ($D3 vs $D1)")"

t_section "guard-cloud too"
pay "gcloud projects delete fixture-$NONCE --quiet"
fire admission-cloud
t_eq "the cloud fixture is a decision" yes "$(case "$(dd)" in (deny|ask) echo yes ;; (*) echo "no ($(dd))" ;; esac)"
t_eq "the cloud decision carries a digest" yes "$(hex16 "$(hh)")"

t_section "negative controls: each half of the fix, reverted, sends the digest to -"
cp "$CFG/bin/admission-destroy.sh" "$TMP/gd.bak"
grep -v '^FLOOR_OBS_SUBJECT="\$CMD"$' "$TMP/gd.bak" > "$CFG/bin/admission-destroy.sh"
pay "diskutil eraseDisk JHFS+ Fixture$NONCE /dev/disk99"
fire admission-destroy
t_eq "no published subject, no digest" - "$(hh)"
cp "$TMP/gd.bak" "$CFG/bin/admission-destroy.sh"
cp "$CFG/bin/library-admission.sh" "$TMP/gl.bak"
sed 's/^  case "\$_ov" in block|deny|ask|shadow|covered)$/  case "$_ov" in block)/' "$TMP/gl.bak" > "$CFG/bin/library-admission.sh"
fire admission-destroy
t_eq "a block-only verdict gate, no digest" - "$(hh)"
cp "$TMP/gl.bak" "$CFG/bin/library-admission.sh"
fire admission-destroy
t_eq "the sources are restored after the controls" yes "$(hex16 "$(hh)")"

t_section "an allow never gains a digest (the hot-path cost rationale)"
pay 'echo fixture allow path'
fire admission-destroy
ALLOW_FIRE="$FIRE_N"  # the one fire allowed to leave the sink empty: allow is not a logged verdict
t_eq "an allow carries no digest" - "$(if [ -s "$SINK" ]; then hh; else echo -; fi)"

t_section "the isolation ruling keeps all three outcomes reachable"
isolation_verdict() { # <empty-fire-list> <allow-fire-n> <inode-moved 0|1> -> ok|inconclusive|leak
  _iv_unexpected=''
  for _iv_f in $1; do [ "$_iv_f" = "$2" ] || _iv_unexpected="$_iv_unexpected $_iv_f"; done
  [ -z "$_iv_unexpected" ] || { printf 'leak'; return; }
  [ "$3" = 1 ] && { printf 'inconclusive'; return; }
  printf 'ok'
}
t_eq "the allow fire alone" ok "$(isolation_verdict ' 7' 7 0)"
t_eq "no empty fire at all" ok "$(isolation_verdict '' 7 0)"
t_eq "a fire with no fixture record is a leak" leak "$(isolation_verdict ' 3' 7 0)"
t_eq "an unexpected empty fire beside the expected one" leak "$(isolation_verdict ' 3 7' 7 0)"
t_eq "a rotated ledger is inconclusive" inconclusive "$(isolation_verdict ' 7' 7 1)"
t_eq "a real leak outranks the rotation confounder" leak "$(isolation_verdict ' 3' 7 1)"

t_section "isolation: every fixture record landed, and none reached a sandbox ledger"
_ino_moved=0; [ "$LIVE_INO_BEFORE" = "$(live_inode)" ] || _ino_moved=1
# Nothing else writes the sandbox's ledgers, so inconclusive (a rotation) can only be a leak here.
t_eq "every fire but the allow landed in the fixture sink (empty fires:${EMPTY_FIRES:- none})" ok "$(isolation_verdict "$EMPTY_FIRES" "$ALLOW_FIRE" "$_ino_moved")"
marker_in() { # <ledger> — any fixture digest or session key in it, by content; "none" or the hits
  _hits=''
  for _dg in $(sort -u "$TMP/fixture-digests"); do
    grep -qE "\"(h|sk)\":\"$_dg\"" "$1" 2>/dev/null && _hits="$_hits $_dg"
  done
  echo "${_hits:-none}"
}
leaked() {
  [ -s "$TMP/fixture-digests" ] || { echo "no fixture digest collected"; return; }
  _leaked=''
  for _lf in $(ledgers); do
    _m="$(marker_in "$_lf")"; [ "$_m" = none ] || _leaked="$_leaked$_m@$_lf"
  done
  echo "${_leaked:-none}"
}
t_eq "no fixture digest reached a ledger outside the fixture (by content)" none "$(leaked)"
# The detector is live: a ledger holding one of this run's rows must be reported (else "none" is inert).
{ printf '{"v":1,"ts":"x","g":"destroy","d":"deny","r":"r","s":"argv","t":"Bash","h":"-","sk":"%s"}\n' "$(head -1 "$TMP/fixture-digests")"; } > "$TMP/planted.jsonl"
t_eq "positive control: a planted fixture session key is found by content" "$(head -1 "$TMP/fixture-digests")" "$(marker_in "$TMP/planted.jsonl" | tr -d ' ')"
if [ -n "$LIVE_LEDGER" ]; then
  t_eq "the test's records reached the LIVE ledger zero times (by content, unique per-run marker)" none "$(marker_in "$LIVE_LEDGER")"
else
  t_eq "no live ledger under $REAL_CFG on this host, so HARBOR_REQUIRE_LIVE_LEDGER must be off" 0 "$REQ_LIVE"
  echo "obs-digest-test: SKIPPED the live-ledger content check (no guard-decisions.jsonl under $REAL_CFG/MEMORY/OBSERVABILITY)"
fi
t_done
