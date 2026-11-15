#!/usr/bin/env sh
# reconcile.test.sh (harbor#1437) — event-dispatch.sh reconcile and health: refused presets replaced, default-on presets installed.
# Measured 2026-11-02 on the operator's box: two installed presets (event.fleet-snapshot, event.pulse) kept handler names an old release had and were refused on every load, and nothing said
# so. A deploy now reconciles the installed rules with contracts/event-rules.tsv without a session ever running `on`, and a
# rule refused twice running is a standing refusal the pulse can file as a finding. The register and presets are the repo's own.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
HARBOR_EVENT_HEALTH_SECS=0; export HARBOR_EVENT_HEALTH_SECS
for _h in status-fleet-snapshot-refresh.sh alert-notify.sh session-notify.sh session-save-now.sh session-ci-watch.sh session-cleanup-report.sh session-check.sh; do
  install_bin "$_h" "$(t_src "$_h")"
done
install_bin docs/reference/checks.md "$T_ROOT/docs/reference/checks.md"
install_bin event-rules.tsv "$T_ROOT/contracts/event-rules.tsv"
RULES="$GT/rules"
list() { sh "$ED" on --list 2>/dev/null; }
refused() { list | grep -c 'REFUSED'; }
# the rule files exactly as the box holds them: a handler name from before the renames
old_rule() { # <id> <handler> <pattern>
  mkdir -p "$RULES"
  printf 'id=%s\npattern=%s\ndebounce=60\nrate=12\nbackstop=3600\ncreated=1761393600\nkind=cmd\nargv=sh\nargv=%s/bin/%s\n' "$1" "$3" "$CFG" "$2" > "$RULES/$1.rule"
}

t_section "the box as measured: two presets refused on every load"
old_rule event.fleet-snapshot fleet-snapshot-refresh.sh '"kind":"(session\.start|session\.stop|pr\.opened|pr\.merged|git\.merge|ci\.job\.done)"'
old_rule event.pulse pulse-notify.sh '"kind":"(ci\.job\.done|obligation\.open|obligation\.close|git\.merge)"'
t_eq "both are REFUSED (the defect, before any fix)" 2 "$(refused)"
t_has "the old handler is not on the allowlist" "$(list)" "fleet-snapshot-refresh.sh is not on the handler allowlist"
t_has "the old id's window is closed" "$(list)" "event.pulse was renamed event.alerting"

t_section "reconcile --dry-run says what it would do and changes nothing"
sh "$ED" reconcile --dry-run > "$T_TMP/dry.out" 2>&1; t_eq "exit 0" 0 "$?"
t_has "it would reinstall fleet-snapshot" "$(cat "$T_TMP/dry.out")" "[check:event.fleet-snapshot] would reinstall the preset"
t_has "...and replace event.pulse by event.alerting" "$(cat "$T_TMP/dry.out")" "[check:event.alerting] would reinstall the preset: event.pulse is refused"
t_has "...and install the default-on session presets" "$(cat "$T_TMP/dry.out")" "[check:event.session-check] would install the default-on preset"
t_eq "no rule file was written" "event.fleet-snapshot.rule event.pulse.rule " "$(ls "$RULES" | tr '\n' ' ')"

t_section "reconcile: refused presets are replaced, default-on presets installed, no session involved"
PULSE_BEFORE="$(cat "$RULES/event.pulse.rule")"
sh "$ED" reconcile > "$T_TMP/rec.out" 2>&1; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_eq "nothing is refused any more" 0 "$(refused)"
t_eq "the seven presets are the seven rules (event.pulse is gone, event.alerting is its successor)" \
  "event.alerting.rule event.fleet-snapshot.rule event.session-check.rule event.session-ci-watch.rule event.session-cleanup-report.rule event.session-notify.rule event.session-save-now.rule " \
  "$(ls "$RULES" | tr '\n' ' ')"
t_has "fleet-snapshot runs the renamed handler" "$(cat "$RULES/event.fleet-snapshot.rule")" "argv=$CFG/bin/status-fleet-snapshot-refresh.sh"
t_has "alerting runs alert-notify.sh" "$(cat "$RULES/event.alerting.rule")" "argv=$CFG/bin/alert-notify.sh"
t_eq "the spawner stays off: no spawn.on, no prompt file" "" "$([ -e "$GT/spawn.on" ] && echo spawn.on; ls "$RULES" | grep '\.prompt$')"
t_eq "the follower still starts with them (every rule re-checks)" 0 "$(dispatch_once; echo $?)"
: "$PULSE_BEFORE"

t_section "reconcile is idempotent and leaves a healthy rule alone"
sed -i.bak 's/^rate=12$/rate=5/' "$RULES/event.session-check.rule"; rm -f "$RULES/event.session-check.rule.bak"
SUM="$(cat "$RULES"/*.rule | cksum)"
sh "$ED" reconcile > "$T_TMP/rec2.out" 2>&1; t_eq "second run exits 0" 0 "$?"
t_eq "no rule file changed (the operator's rate=5 survives)" "$SUM" "$(cat "$RULES"/*.rule | cksum)"
t_has "and it says there was nothing to do" "$(cat "$T_TMP/rec2.out")" "every installed rule passes its re-check and every default-on preset is installed"

t_section "a rule removed by hand comes back; a preset with no #default line does not"
rm -f "$RULES/event.session-notify.rule"
sh "$ED" reconcile > /dev/null 2>&1
t_eq "event.session-notify is installed again" yes "$([ -f "$RULES/event.session-notify.rule" ] && echo yes)"
grep -v '^#default	event.session-check$' "$CFG/bin/event-rules.tsv" > "$T_TMP/rules.nodefault"; cp "$T_TMP/rules.nodefault" "$CFG/bin/event-rules.tsv"; record event-rules.tsv
rm -f "$RULES/event.session-check.rule"
sh "$ED" reconcile > /dev/null 2>&1
t_eq "a preset the register does not mark #default stays off" no "$([ -f "$RULES/event.session-check.rule" ] && echo yes || echo no)"
install_bin event-rules.tsv "$T_ROOT/contracts/event-rules.tsv"

t_section "a refused rule that is no preset is reported, not touched"
mkdir -p "$RULES"; printf 'id=event.custom\npattern="kind":"pr\\.opened"\ndebounce=60\nrate=6\nbackstop=0\ncreated=1\nkind=cmd\nargv=sh\nargv=%s/bin/rm-rf.sh\n' "$CFG" > "$RULES/event.custom.rule"
BEFORE="$(cat "$RULES/event.custom.rule")"
sh "$ED" reconcile > "$T_TMP/rec3.out" 2>&1; t_eq "exit 3: something is still refused" 3 "$?"
t_has "the report names it and why" "$(cat "$T_TMP/rec3.out")" "rule event.custom is refused and is not a preset, so deploy leaves it"
t_eq "its file is untouched" "$BEFORE" "$(cat "$RULES/event.custom.rule")"
rm -f "$RULES/event.custom.rule"

t_section "reconcile is the operator's: a Claude session is refused (exit 4), a dry run is not"
rm -f "$RULES/event.session-notify.rule"
CLAUDECODE=1 sh "$ED" reconcile > "$T_TMP/cc.out" 2>&1; t_eq "reconcile under CLAUDECODE exits 4" 4 "$?"
t_eq "...and wrote nothing" no "$([ -f "$RULES/event.session-notify.rule" ] && echo yes || echo no)"
CLAUDECODE=1 sh "$ED" reconcile --dry-run > /dev/null 2>&1; t_eq "a dry run is read-only and allowed" 0 "$?"

t_section "health: a rule refused on two passes running is a standing refusal the pulse can file"
REF="$CACHE/event-dispatch-refused.tsv"
t_eq "control: with every rule sound health exits 0" 0 "$(sh "$ED" health >/dev/null 2>&1; echo $?)"
old_rule event.session-check old-handler.sh '"kind":"session\.state"'
sh "$ED" health > "$T_TMP/h1.out" 2>&1; t_eq "a refused rule: health exits 1" 1 "$?"
t_has "it names the rule and the reason" "$(cat "$T_TMP/h1.out")" "REFUSED	event.session-check	old-handler.sh is not on the handler allowlist"
t_eq "one pass is not yet standing: no refused file" no "$([ -f "$REF" ] && echo yes || echo no)"
sh "$ED" health > /dev/null 2>&1
t_eq "the second pass makes it standing: the refused file names it" "event.session-check" "$(cut -f1 "$REF" 2>/dev/null)"
t_has "...with its reason" "$(cat "$REF")" "not on the handler allowlist"
sh "$ED" reconcile > /dev/null 2>&1; sh "$ED" health > /dev/null 2>&1
t_eq "reconcile repaired it, the next pass is clean and the file is gone" no "$([ -f "$REF" ] && echo yes || echo no)"

t_section "the follower runs the same pass (the loop calls health_pass, not only a verb)"
old_rule event.session-check old-handler.sh '"kind":"session\.state"'
rm -f "$ST/refused.prev"
dispatch_once; dispatch_once
t_eq "two --once starts make the refusal standing" "event.session-check" "$(cut -f1 "$REF" 2>/dev/null)"
t_done
