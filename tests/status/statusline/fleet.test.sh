#!/usr/bin/env sh
# L0-5 (harbor#59): the statusline's fleet glyph, its cache and the writer that publishes it, the
# floor pin, the guard-decision tile and the SessionStart verdicts hook. `--dash`: subjects under dash.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../hooks/statusline-fixture.sh"
FS="$CFG/cache/fleet-snapshot.json"
fleet() { run "{$WS}" | plain; }  # both rows, stripped
TWO='[{"status":{"dirty":false,"ahead":0,"behind":0},"drift":{"status":"clean","total":0}},{"status":{"dirty":true},"drift":{"status":"drift","modified":["a"],"total":91}}]'

t_section "fleet glyph: the counts, and drift.status is the verdict"
# drift.total is the MANIFEST SIZE (drift.py:36), so "this repo drifted" is carried by status.
printf '%s\n' "$TWO" > "$FS"
O="$(fleet | tail -1)"
t_has "the glyph count" "$O" "⚓2"
t_has "the dirty sub-count" "$O" "·1 dirty"
t_has "the drift alarm, on YOU" "$(fleet)" "DRIFT 1"
# Every icon on the row must be east_asian_width W: these three narrow ones are asserted ABSENT.
t_hasnt "no narrow-presentation pencil" "$O" '✎'
t_hasnt "no narrow-presentation arrow" "$O" '⇅'
t_hasnt "no narrow-presentation warning sign" "$O" '⚠'
printf '%s\n' '[{"status":{"dirty":false},"drift":{"status":"clean","modified":[],"missing":[],"total":126}}]' > "$FS"
O="$(fleet | tail -1)"
t_hasnt "a CLEAN repo with a 126-file manifest raises no drift alarm" "$(fleet)" "DRIFT"
t_has "the clean-repo fixture keeps its anchor count" "$O" "⚓1"
printf '%s\n' '[{"status":{"dirty":false},"drift":{"status":"drift","modified":[],"missing":["justfile"],"total":126}}]' > "$FS"
t_has "a MISSING scaffold file is drift and counts" "$(fleet)" "DRIFT 1"
# Known limit, kept known: no-manifest raises no alarm, so an unmeasured repo reads as clean.
printf '%s\n' '[{"status":{"dirty":false},"drift":{"status":"no-manifest","modified":[],"missing":[],"total":0}}]' > "$FS"
t_hasnt "no-manifest raises no alarm" "$(fleet)" "DRIFT"
rm -f "$FS"
O="$(run "{$WS}" 2>&1)"; rc=$?
t_has "an absent cache reads fleet: unknown" "$(printf '%s' "$O" | plain)" "fleet: unknown"
t_eq "an absent cache does not error" 0 "$rc"
# Aged for real with `touch -t`: a 0 threshold would pass a fresh cache off as stale.
printf '%s\n' '[{"status":{"dirty":false}}]' > "$FS"; touch -t 202001010000 "$FS"
t_has "a stale cache reads fleet: unknown" "$(fleet)" "fleet: unknown"
rm -f "$FS"

t_section "fleet glyph: an INVALID cache degrades, and never errors"
# The cache crosses a seam with no schema on the producer side (contracts/fleet-controller-json.md).
for _bad_desc in 'empty:' 'not-json:this is not json at all' 'object-not-array:{"status":"ok"}' 'null:null' 'nested:BRACKETS'; do
  _bl="${_bad_desc%%:*}"; _bc="${_bad_desc#*:}"
  [ "$_bc" = BRACKETS ] && _bc="$(awk 'BEGIN{for(i=0;i<200;i++)printf "[" ; for(i=0;i<200;i++)printf "]"}')"
  printf '%s' "$_bc" > "$FS"
  O="$(run "{$WS}" 2>&1)"; rc=$?
  t_has "an invalid cache ($_bl) reads fleet: unknown" "$(printf '%s' "$O" | plain)" "fleet: unknown"
  t_eq "an invalid cache ($_bl) does not error" 0 "$rc"
done
rm -f "$FS"

t_section "fleet glyph: a cache with TWO documents is invalid, not two answers"
# `jq -r PROGRAM file` runs once per document, and streams: the row count is asserted with the text.
for _md in twodocs trailing; do
  case "$_md" in
    twodocs)  printf '%s\n%s\n' '[{"status":{"dirty":false}}]' '[{"status":{"dirty":false}},{"status":{"dirty":false}}]' > "$FS" ;;
    trailing) printf '%s\n' '[{"status":{"dirty":false}}] garbage' > "$FS" ;;
  esac
  O="$(run "{$WS}" 2>&1)"; rc=$?
  t_has "a multi-document cache ($_md) degrades" "$(printf '%s' "$O" | plain)" "fleet: unknown"
  t_eq "a multi-document cache ($_md) adds no row: SESSION, PLACE, YOU (unpinned), BOX" 4 "$(printf '%s\n' "$O" | grep -c .)"
  t_eq "a multi-document cache ($_md) does not error" 0 "$rc"
done
rm -f "$FS"

t_section "fleet glyph: a VALID cache still renders (the false-positive control)"
for _gd in 'one:[{"status":{"dirty":true},"drift":{"total":5}}]:⚓1' 'three:[{"status":{"dirty":false}},{"status":{"dirty":false}},{"status":{"dirty":true}}]:⚓3' 'emptyfleet:[]:⚓0'; do
  _gl="${_gd%%:*}"; _rest="${_gd#*:}"; _gc="${_rest%:*}"; _gw="${_rest##*:}"
  printf '%s\n' "$_gc" > "$FS"
  t_has "a valid cache ($_gl) renders $_gw" "$(fleet)" "$_gw"
done
rm -f "$FS"

t_section "fleet snapshot: the writer's own gate rejects a two-document emission"
# The predicate is READ OUT OF THE SOURCE, one definition, rather than copied here.
GATE="$(sed -n 's/.*&& jq -e -s \(.*\) "\$TMP".*/\1/p' "$SRC/status-fleet-snapshot-refresh.sh" | head -1)"
t_eq "the gate predicate was read out of status-fleet-snapshot-refresh.sh" yes "$(yn [ -n "$GATE" ])"
printf '%s\n' '[{"a":1},{}]' > "$TMP/gate-one.json"
printf '%s\n%s\n' '[{}]' '[{},{}]' > "$TMP/gate-two.json"
eval "jq -e -s $GATE \"\$TMP/gate-one.json\"" >/dev/null 2>&1
t_eq "the gate accepts a single valid array" 0 "$?"
eval "jq -e -s $GATE \"\$TMP/gate-two.json\"" >/dev/null 2>&1
t_eq "the gate refuses two concatenated arrays" 1 "$?"

t_section "fleet snapshot: the writer refuses a non-object element and keeps the prior cache"
# projects-orchestrator#218: `[…, null]` was published and counted as a project. The real
# refresher against a fake producer; its sweep's home, scratch and gh are pinned to nothing.
WR="$TMP/writer"; mkdir -p "$WR/cache"
printf '%s\n' '[{"status":{"dirty":false}}]' > "$WR/prior.json"
printf '#!/bin/sh\ncat "%s"\n' "$WR/emit.json" > "$WR/orch"; chmod +x "$WR/orch"
wrun() {
  printf '%s\n' "$1" > "$WR/emit.json"
  cp "$WR/prior.json" "$WR/cache/fleet-snapshot.json"
  mkdir -p "$WR/home" "$WR/scratch"
  CLAUDE_CONFIG_DIR="$WR" HARBOR_SCOPE_CACHE_DIR="$WR/cache" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$WR/orch" \
    HARBOR_HOUSEKEEPING_CLEAN_HOME="$WR/home" HARBOR_HOUSEKEEPING_CLEAN_SCRATCH="$WR/scratch" HARBOR_HOUSEKEEPING_CLEAN_GH=none \
    HARBOR_SCOPE_FLEET_FILE="$WR/fleet.yaml" "$SH" "$SRC/status-fleet-snapshot-refresh.sh" >/dev/null 2>&1
}
for _wd in 'null-padded:[{"status":{"dirty":false}},null]' 'all-null:[null]' \
           'scalar:[{"status":{}},1]' 'nested-array:[[]]'; do
  _wl="${_wd%%:*}"; _wc="${_wd#*:}"
  wrun "$_wc"
  t_eq "the writer refuses a $_wl emission" 1 "$?"
  t_eq "a refused $_wl emission leaves the prior cache in place" yes "$(yn cmp -s "$WR/prior.json" "$WR/cache/fleet-snapshot.json")"
done
# The control: the nine keys snapshot.v1 requires, with the type looseness relied on below.
_real='[{"descriptor":{"name":"a"},"status":{"dirty":"yes"},"checks":{},"memory":{},"drift":{},"hooks":"ok","run_state":null,"trend":{},"agent_run":null}]'
for _wd in "snapshot-shaped:$_real" 'emptyfleet:[]'; do
  _wl="${_wd%%:*}"; _wc="${_wd#*:}"
  wrun "$_wc"
  t_eq "the writer publishes a valid $_wl emission" 0 "$?"
  t_eq "a valid $_wl emission is written to the cache" yes "$(yn cmp -s "$WR/emit.json" "$WR/cache/fleet-snapshot.json")"
done
# harbor#1181: each published refresh appends one counts-only history line; a refused one appends nothing.
_hist="$(cat "$WR"/MEMORY/OBSERVABILITY/*/streams/fleet.snapshots/*/*.jsonl 2>/dev/null)"
t_eq "two published refreshes, two history lines (the four refused ones wrote none)" 2 "$(printf '%s\n' "$_hist" | grep -c '"stream":"fleet.snapshots"')"
t_eq "a history line carries counts" '{"repos":1,"dirty":0,"ahead":0,"behind":0}' "$(printf '%s\n' "$_hist" | head -n 1 | jq -c .attrs)"
t_eq "and never a project name" 0 "$(printf '%s\n' "$_hist" | grep -c '"name"')"
case "$(head -1 "$WR/.helm-sweep" 2>/dev/null)" in "sweep items="*" unread="*" due="*" at="*) _sw=yes ;; *) _sw=no ;; esac
t_eq "the refresher records a sweep into its config dir" yes "$_sw"
t_eq "the refresher's sweep leaves no lock behind" no "$(yn [ -e "$WR/.helm-sweep.lock" ])"
# The limit of the promise: a well-formed array with wrong TYPES renders glyphs, by design.
printf '%s' '[{"status":{"dirty":"yes","ahead":"many"},"drift":{"total":"lots"}}]' > "$FS"
t_hasnt "a well-formed array with wrong TYPES does not blank the tile" "$(fleet)" 'fleet: unknown'
rm -f "$FS"

t_section "floor integrity: a WORD, and only when it can be computed"
t_has "no pin file reads PIN UNPINNED" "$(fleet)" "PIN UNPINNED"
pin "$CFG"
O="$(fleet)"; RAW="$(run "{$WS}")"
t_hasnt "the pushpin is cut" "$O" '📌'
t_eq "row 2 carries no green" 0 "$(printf "%s" "$RAW" | grep -c "${ESC}\[32m")"
t_hasnt "row 2 carries no red" "$RAW" "${ESC}[31m"
t_has "control: the renderer does emit colour codes, so their absence is measured" "$(run '{"pr":{"number":7,"review_state":"changes_requested"},'"$WS"'}' | sed -n 2p)" "${ESC}[3"
t_has "row 2 can carry red: changes requested (control)" "$(run '{"pr":{"number":7,"review_state":"changes_requested"},'"$WS"'}' | sed -n 2p)" "${ESC}[31m#7 changes"
t_hasnt "a matching pin raises no PIN DRIFT" "$O" 'PIN DRIFT'
t_hasnt "a matching pin raises no PIN UNPINNED" "$O" 'PIN UNPINNED'
printf '%s\n' '{"permissions":{"deny":["Read(~/.ssh/**)","Read(~/.aws/**)"]}}' > "$CFG/settings.json"
O="$(fleet)"; RAW="$(run "{$WS}")"
t_has "a changed deny reads PIN DRIFT" "$O" "PIN DRIFT"
t_hasnt "a drifted pin does not bring the pushpin back" "$RAW" '📌'
t_has "the drift is carried by the WORD" "$RAW" "PIN DRIFT"
t_has "the alarm is a word, not a glyph" "$O" "DRIFT"

t_section "guard decisions: absent, never 'blocks 0'"
t_hasnt "no ledger cache renders nothing" "$(fleet)" 'blocks'
printf '%s\n' '{"blocks":0,"overrides":0}' > "$CFG/cache/guard-decisions.json"
t_hasnt "zero blocks render nothing" "$(fleet)" 'blocks'
# `blocks` is gone by decision (2026-08-23); the fixture keeps the real number so a restore fails.
printf '%s\n' '{"blocks":4719,"overrides":1}' > "$CFG/cache/guard-decisions.json"
O="$(fleet)"
t_hasnt "the removed blocks count does not render" "$O" 'blocks'
t_hasnt "the removed blocks number does not render" "$O" '4719'
t_has "an override count renders" "$O" "ovr 1"
printf '%s\n' '{"blocks":4719,"overrides":0}' > "$CFG/cache/guard-decisions.json"
t_hasnt "zero overrides render nothing" "$(fleet)" 'ovr'

t_section "the statusline NEVER invokes the orchestrator (REVIEW F6)"
# Code lines only: a comment naming drift.py as the schema's source is not an invocation. The needle is the fleet
# CLI's name from its roots row (contracts/roots.tsv), so a renamed fleet is still the thing looked for (harbor#999).
_cli="$(sh "$T_ROOT/bin/scope-roots.sh" --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN)"; _cli="${_cli##*/}"
_strip() { sed 's/^[[:space:]]*#.*$//'; }
t_has "the needle's control: a code line invoking the fleet CLI survives the strip" "$(printf '"%s" snapshot --json\n' "$_cli" | _strip)" "$_cli"
t_eq "...and a comment naming it does not" "" "$(printf '  # %s states it\n' "$_cli" | _strip | tr -d '[:space:]')"
_code="$(_strip < "$SRC/status-fleet-glyph.sh")"
t_hasnt "no code line names the fleet CLI" "$_code" "$_cli"
t_hasnt "no code line names ORCH" "$_code" 'ORCH'
t_hasnt "no code line asks for the fleet CLI's path" "$_code" 'FLEET_CONTROLLER_BIN'

t_section "session-verdicts: silent when clean, and never blocking"
V="$TMP/vcfg"; mkdir -p "$V/bin"
printf '%s\n' '{"permissions":{"deny":[]},"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/bin/sh x/admission-bash.sh"}]}]}}' > "$V/settings.json"
pin "$V"
O="$(CLAUDE_CONFIG_DIR="$V" "$SH" "$T_ROOT/hooks/session-verdicts/session-verdicts.sh" </dev/null 2>/dev/null)"; rc=$?
t_eq "a clean box prints NOTHING" "" "$O"
t_eq "the verdicts hook exits 0 when clean" 0 "$rc"
verdict() { CLAUDE_CONFIG_DIR="$V" "$SH" "$T_ROOT/hooks/session-verdicts/session-verdicts.sh" </dev/null 2>/dev/null | jq -r '.systemMessage' 2>/dev/null; }
# A guard named in a DENY ENTRY is text, not a wired guard (floor pass-4).
printf '%s\n' '{"permissions":{"deny":["Edit(~/.claude/bin/admission-bash.sh)"]},"hooks":{}}' > "$V/settings.json"
pin "$V"
t_has "a guard named in deny does not count as wired" "$(verdict)" "no guard is wired"
cp "$T_ROOT/hooks/worklog-push/worklog-push.sh" "$V/bin/worklog-push.sh"
t_has "a missing library-admission.sh is a dead worklog" "$(verdict)" "work-log DEAD"
# The reinstall it names is aimed at the dir it measured (harbor#800): a sandbox's installer by --dir,
# the live box through deploy, the one live entry (the install standard §4).
t_has "...its fix re-runs the runtime installer at THIS sandbox, --dir spelled" "$(verdict)" "deploy-runtime-install.sh --apply --dir '$V'"
t_eq "...and no fix in it is aimed at the live box" 0 "$(verdict | grep -c -- '--live')"
LV="$TMP/lvhome"; mkdir -p "$LV/.claude/bin"; cp "$V/settings.json" "$LV/.claude/"; cp "$T_ROOT/hooks/worklog-push/worklog-push.sh" "$LV/.claude/bin/"
t_has "the live box's fix is deploy's runtime component" \
  "$(HOME="$LV" CLAUDE_CONFIG_DIR="$LV/.claude" "$SH" "$T_ROOT/hooks/session-verdicts/session-verdicts.sh" </dev/null 2>/dev/null | jq -r '.systemMessage' 2>/dev/null)" \
  "deploy.sh --only runtime --apply --live"
cp "$SRC/library-admission.sh" "$V/bin/library-admission.sh"
t_hasnt "installing library-admission.sh clears the verdict" "$(verdict)" 'work-log DEAD'
# systemMessage (operator-facing), never additionalContext (context spend). Comments stripped first.
t_has "the source names additionalContext in a comment (the needle's control)" "$(cat "$T_ROOT/hooks/session-verdicts/session-verdicts.sh")" 'additionalContext'
t_hasnt "no code line spends context tokens" "$(sed 's/#.*//' "$T_ROOT/hooks/session-verdicts/session-verdicts.sh")" 'additionalContext'

t_done
