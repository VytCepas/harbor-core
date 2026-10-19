#!/usr/bin/env sh
# judge-run.sh and section 5 of session-verdicts.sh (harbor#44). The judge is a stub, so
# a crit and a clean box can both be produced on demand; a garbage verdict must leave the
# previous cache intact (case 5), because absence reading as healthy is the defect.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$T_TMP/jr"; mkdir -p "$T/bin" "$T/cfg"
cp "$T_ROOT/bin/judge-run.sh" "$T_ROOT/bin/log-lib.sh" "$T/bin/"
printf '#!/bin/sh\ncat "$(dirname "$0")/fc.json"\n' > "$T/bin/failure-capture.sh"; chmod +x "$T/bin/failure-capture.sh"
fixture_crit() { cat > "$T/bin/fc.json" <<'J'
{"dir":"/x","installed":true,"records":70702,"worst":"crit","findings":[
 {"rule":"FC-2","severity":"crit","subject":"wrapper-guard-missing (x1)","breaks":"the floor could not EVALUATE a tool call","repair":"re-run floor-install.sh from your own terminal"},
 {"rule":"FC-5","severity":"warn","subject":"cd-cfg-then-find-exec (x20)","breaks":"same command walled again","repair":"fix the rule or the command"}]}
J
}
fixture_clean() { printf '%s\n' '{"dir":"/x","installed":true,"records":12,"worst":"none","findings":[]}' > "$T/bin/fc.json"; }
fixture_garbage() { printf 'Traceback: the judge died\n' > "$T/bin/fc.json"; }
run() { sh "$T/bin/judge-run.sh" "$@" 2>/dev/null; }
JV="$T/cfg/.helm-judge"
has_cache() { [ -f "$1" ] && echo yes || echo no; }
lines() { grep -c "^$1 " "$JV" 2>/dev/null || true; }
sv() { CLAUDE_CONFIG_DIR="$T/cfg" sh "$T_ROOT/bin/session-verdicts.sh" 2>&1; }

t_section "1 · a crit finding reaches the cache"
fixture_crit; rm -f "$JV"
t_exit "--apply" 0 sh "$T/bin/judge-run.sh" "$T/cfg" --apply
t_eq "the cache is written" yes "$(has_cache "$JV")"
t_has "the header carries the counts" "$(head -1 "$JV")" "worst=crit crit=1 warn=1 records=70702"
t_has "the crit line, rule|subject|repair" "$(grep '^crit ' "$JV")" "crit FC-2|wrapper-guard-missing (x1)|re-run floor-install.sh"
t_eq "the warn did not leak into the crit lines" 1 "$(lines crit)"
# Warns are itemised, not merely counted: a bare warn=17 could not be resolved on 2026-09-04.
t_has "the warn line, rule|subject|repair" "$(grep '^warn ' "$JV")" "warn FC-5|cd-cfg-then-find-exec (x20)|fix the rule or the command"
t_eq "exactly one warn line" 1 "$(lines warn)"

t_section "2 · a clean judge still writes (silence must be dated, not absent)"
fixture_clean; rm -f "$JV"
run "$T/cfg" --apply >/dev/null
t_eq "a clean run writes the cache" yes "$(has_cache "$JV")"
t_has "the clean header" "$(head -1 "$JV")" "worst=none crit=0 warn=0"
t_eq "no crit line on a clean judge" 0 "$(lines crit)"
t_eq "no warn line on a clean judge" 0 "$(lines warn)"

t_section "3 · a dry run writes nothing"
fixture_crit; rm -f "$JV"
_out="$(run "$T/cfg")"
t_eq "the dry run wrote no cache" no "$(has_cache "$JV")"
t_has "the dry run prints the verdict" "$_out" "worst=crit"

t_section "4 · no judge beside the script is exit 1, not a clean cache"
fixture_crit; rm -f "$JV"
mv "$T/bin/failure-capture.sh" "$T/bin/failure-capture.off"
t_exit "a missing judge" 1 sh "$T/bin/judge-run.sh" "$T/cfg" --apply
t_eq "no cache without a judge" no "$(has_cache "$JV")"
mv "$T/bin/failure-capture.off" "$T/bin/failure-capture.sh"

t_section "5 · a garbage verdict must not overwrite a good cache"
fixture_crit; run "$T/cfg" --apply >/dev/null
fixture_garbage
t_exit "a garbage judge" 1 sh "$T/bin/judge-run.sh" "$T/cfg" --apply
t_has "the previous crit cache survives" "$(cat "$JV")" "crit FC-2"

t_section "6 · --apply on the live dir requires having named it --live"
# The sandbox HOME's .claude must exist, or the not-a-directory refusal answers instead.
mkdir -p "$HOME/.claude"
t_exit "the live dir with --apply" 2 sh "$T/bin/judge-run.sh" "$HOME/.claude" --apply
t_has "the refusal names the gate" "$(sh "$T/bin/judge-run.sh" "$HOME/.claude" --apply 2>&1)" "refusing --apply on the live config dir"
t_eq "nothing was written to the live dir" no "$(has_cache "$HOME/.claude/.helm-judge")"
t_exit "a missing target" 2 sh "$T/bin/judge-run.sh" "$T/nope" --apply

t_section "7 · session-verdicts speaks on crit, is silent on clean"
fixture_crit; run "$T/cfg" --apply >/dev/null
_v="$(sv)"
t_has "the crit reaches session-verdicts" "$_v" "ledger judge CRIT"
t_has "the repair text survives" "$_v" "floor-install.sh"
# The cache holds a warn line for this fixture (section 1); the session channel stays blind to it.
t_hasnt "an itemised warn never reaches the session channel" "$_v" "cd-cfg-then-find-exec"
fixture_clean; run "$T/cfg" --apply >/dev/null
t_eq "a clean cache prints nothing" "" "$(sv)"

t_section "8 · a cache that stopped being written is a verdict of its own"
touch -t 202601010000 "$JV"
t_has "a dead scheduled job reads stale" "$(sv)" "ledger judge STALE"
UB="$T/uname"; mkdir -p "$UB"
for _u in Darwin:launchctl Linux:'systemctl --user start harbor-judge.service'; do
  printf '#!/bin/sh\necho %s\n' "${_u%%:*}" > "$UB/uname"; chmod +x "$UB/uname"
  t_has "${_u%%:*}: the stale verdict's check is that platform's (harbor#618)" "$(PATH="$UB:$PATH" sv)" "Check: ${_u#*:}"
done

t_section "9 · no cache at all is silence"
rm -f "$JV"
t_eq "an absent cache prints nothing" "" "$(sv)"
t_done
