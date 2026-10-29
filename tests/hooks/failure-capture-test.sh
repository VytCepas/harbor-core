#!/usr/bin/env sh
# failure-capture.sh (M5, harbor#44), part 1: the clean fixture, read-only, and rules FC-0 to FC-4 with
# the recurrence horizon (harbor#211). Every rule goes red on its shape and stays green on a valid but
# unusual one. Parts: failure-capture.fc5-test.sh (FC-5 to FC-8), failure-capture.ledger-test.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/failure-capture-fixture.sh"

t_section "the clean fixture is clean, and exits 0"
CLEAN="$(mkfixture clean)"
unseal "$CLEAN"; census "$CLEAN" 3; seal "$CLEAN"
t_eq "no findings" "" "$(rules_of "$CLEAN")"
t_exit "exit" 0 sh "$FC" "$CLEAN"
t_eq "worst" ok "$(worst_of "$CLEAN")"

t_section "read-only: the tool changes no file's name or content in the tree it inspects"
manifest() { find "$1" -type f -exec shasum -a 256 {} + 2>/dev/null | sed "s|$1||" | sort; }
_before="$(manifest "$CLEAN")"
sh "$FC" "$CLEAN" >/dev/null 2>&1; sh "$FC" "$CLEAN" --json >/dev/null 2>&1
sh "$FC" "$CLEAN" --with-probes >/dev/null 2>&1
t_eq "the manifest covers the fixture's files" 6 "$(printf '%s\n' "$_before" | grep -c .)"
t_eq "the tree after three runs" "$_before" "$(manifest "$CLEAN")"

t_section "FC-0: the floor is wired and there is no ledger"
F0="$(mkfixture fc0)"; rm -rf "$F0/MEMORY"
t_eq "FC-0 fires" yes "$(has_rule "$F0" FC-0)"
t_exit "exit" 1 sh "$FC" "$F0"

t_section "FC-0 stays green: no floor wired means there is nothing to judge"
F0G="$(mkfixture fc0green)"; rm -rf "$F0G/MEMORY"  # sandbox-make.sh builds unwired dirs (№2.11)
jq -n '{hooks:{}}' > "$F0G/settings.json"
t_eq "no findings" "" "$(rules_of "$F0G")"
t_exit "exit" 0 sh "$FC" "$F0G"

# FC-1 subtracts `harbor verify` runs (each adds an integrity record with no session record), fires
# only when their probe digests match this ledger, and warns rather than naming a culprit.
t_section "FC-1: a surplus the verify runs do not explain"
F1="$(mkfixture fc1)"; unseal "$F1"
recn 2 "$F1" session armed floor-armed "2026-08-02T10:00:00Z"
recn 10 "$F1" integrity allow integrity-clean "2026-08-02T10:00:01Z"
recn 1 "$F1" bash block floor-surface "2026-08-02T10:00:02Z" "$D_PROBE_T"
seal "$F1"
t_eq "FC-1 fires" yes "$(has_rule "$F1" FC-1)"
t_eq "FC-1 severity: it names no culprit the ledger cannot identify" warn "$(sev_of "$F1" FC-1)"

t_section "FC-1 stays green: the surplus is exactly the verify-run count"
F1V="$(mkfixture fc1verify)"; unseal "$F1V"  # the live box's own shape
recn 3 "$F1V" session armed floor-armed "2026-08-02T10:00:00Z"
recn 8 "$F1V" integrity allow integrity-clean "2026-08-02T10:00:01Z"
recn 5 "$F1V" bash block floor-surface "2026-08-02T10:00:02Z" "$D_PROBE_T"
seal "$F1V"
t_eq "FC-1 fires" no "$(has_rule "$F1V" FC-1)"

t_section "FC-1 stays silent when the verify-run count is unavailable (№2.7)"
F1U="$(mkfixture fc1uncorrectable)"; unseal "$F1U"
recn 2 "$F1U" session armed floor-armed "2026-08-02T10:00:00Z"
recn 20 "$F1U" integrity allow integrity-clean "2026-08-02T10:00:01Z"
seal "$F1U"
t_eq "FC-1 fires" no "$(has_rule "$F1U" FC-1)"

t_section "FC-1 stays green: B6 not installed is not a dropped record"
F1G="$(mkfixture fc1green)"; unseal "$F1G"
recn 5 "$F1G" session armed floor-armed "2026-08-02T10:00:00Z"
recn 1 "$F1G" bash block floor-surface "2026-08-02T10:00:02Z" "$D_PROBE_T"
seal "$F1G"
t_eq "no findings" "" "$(rules_of "$F1G")"

t_section "FC-1: no session census at all, after the verify runs are taken out, is crit"
F1N="$(mkfixture fc1none)"; unseal "$F1N"
recn 5 "$F1N" integrity allow integrity-clean "2026-08-02T10:00:00Z"
recn 1 "$F1N" bash block floor-surface "2026-08-02T10:00:02Z" "$D_PROBE_T"
seal "$F1N"
t_eq "FC-1 severity" crit "$(sev_of "$F1N" FC-1)"

t_section "FC-2: a wrapper deny, and the repair names the right cause"
F2="$(mkfixture fc2)"; unseal "$F2"; census "$F2" 2
rec "$F2" wrapper deny wrapper-no-jq "2026-08-02T11:00:00Z"; seal "$F2"
t_eq "FC-2 fires" yes "$(has_rule "$F2" FC-2)"
t_eq "a wrapper deny is" crit "$(sev_of "$F2" FC-2)"
# The token routes the repair by substring: it grew a guard name and an exit code (floor-hook.sh).
t_has "the wrapper-no-jq repair mentions jq" "$(repair_of "$F2" FC-2)" "jq"
F2B="$(mkfixture fc2b)"; unseal "$F2B"; census "$F2B" 2
rec "$F2B" wrapper deny wrapper-guard-missing "2026-08-02T11:00:00Z"; seal "$F2B"
_r2b="$(repair_of "$F2B" FC-2)"
t_has "a missing guard's repair names the installer" "$_r2b" "floor-install"
# 2026-08-23: it said re-run floor-install while --live showed every guard present; three pins.
t_has "it routes to the check that owns guard presence" "$_r2b" "harbor verify"
t_has "it states the installer conditionally" "$_r2b" "only helps if"
t_has "it says when the record was written" "$_r2b" "2026-08-02"
# "only helps if" is text unique to the guard-missing branch; "harbor verify" is in the default too.
F2D="$(mkfixture fc2d)"; unseal "$F2D"; census "$F2D" 2
rec "$F2D" wrapper deny wrapper-guard-missing-annotate-web "2026-08-02T11:00:00Z"; seal "$F2D"
t_has "an enriched guard-missing token still routes" "$(repair_of "$F2D" FC-2)" "only helps if"
t_has "the subject names the wiring that failed" "$(subj_of "$F2D" FC-2)" "annotate-web"
F2E="$(mkfixture fc2e)"; unseal "$F2E"; census "$F2E" 2  # 127 missing, 126 not executable
rec "$F2E" wrapper deny wrapper-no-verdict-guard-bash-127 "2026-08-02T11:00:00Z"; seal "$F2E"
t_has "an enriched no-verdict token still routes" "$(repair_of "$F2E" FC-2)" "outside {0,2}"
t_has "the subject keeps the guard and the exit code" "$(subj_of "$F2E" FC-2)" "guard-bash-127"

# A record the floor has outlived is history (§2.11). The stamp is a written floor-install LINE,
# never an mtime, so a rule that read the mtime could not pass F2J below.
_fc_stamp() { printf '%s 0000000000000000000000000000000000000000 %s deadbee\n' "$2" "$3" >> "$1/.helm-install-stamp"; }
t_section "FC-2: a record older than the last floor-install is history, not a crit"
F2F="$(mkfixture fc2f)"; unseal "$F2F"; census "$F2F" 2
rec "$F2F" wrapper deny wrapper-guard-missing-annotate-web "2026-07-28T11:00:00Z"; seal "$F2F"
_fc_stamp "$F2F" floor-install "2026-08-01T00:00:00+03:00"
t_eq "a deny the floor was reinstalled over is info" info "$(sev_of "$F2F" FC-2)"
t_eq "and is not counted as a warn" 0 "$(q '[.findings[]|select(.severity=="warn")]|length' "$F2F")"
t_eq "nor does it raise worst" ok "$(worst_of "$F2F")"
t_exit "nor the exit status" 0 sh "$FC" "$F2F"
JR="$T_TMP/jr-info"; mkdir -p "$JR/bin" "$JR/cfg"; cp "$T_ROOT/bin/judge-run.sh" "$T_ROOT/bin/log-lib.sh" "$JR/bin/"
printf '#!/bin/sh\nsh %s %s --json\n' "$FC" "$F2F" > "$JR/bin/failure-capture.sh"
sh "$JR/bin/judge-run.sh" "$JR/cfg" --apply >/dev/null 2>&1
t_has "the judge header counts warn=0" "$(head -1 "$JR/cfg/.helm-judge")" "warn=0"
t_has "the demoted row says the guard file was replaced" "$(repair_of "$F2F" FC-2)" "REPLACED by the floor-install"
F2G="$(mkfixture fc2g)"; unseal "$F2G"; census "$F2G" 2
rec "$F2G" wrapper deny wrapper-guard-missing-annotate-web "2026-08-02T11:00:00Z"; seal "$F2G"
_fc_stamp "$F2G" floor-install "2026-07-20T00:00:00+03:00"
t_eq "a deny recorded AFTER the last install stays" crit "$(sev_of "$F2G" FC-2)"
F2H="$(mkfixture fc2h)"; unseal "$F2H"; census "$F2H" 2
rec "$F2H" wrapper deny wrapper-guard-missing-annotate-web "2026-08-02T11:00:00Z"; seal "$F2H"
t_eq "fixture fc2h has no stamp" no "$([ -e "$F2H/.helm-install-stamp" ] && echo yes || echo no)"
t_eq "a missing stamp never silences a crit" crit "$(sev_of "$F2H" FC-2)"
# An install replaces guard files, not interpreters: it cannot restore jq (review of harbor#340).
F2I="$(mkfixture fc2i)"; unseal "$F2I"; census "$F2I" 2
rec "$F2I" wrapper deny wrapper-no-jq "2026-07-28T11:00:00Z"; seal "$F2I"
_fc_stamp "$F2I" floor-install "2026-08-01T00:00:00+03:00"
t_eq "an interpreter outage is not demoted by a floor-install" crit "$(sev_of "$F2I" FC-2)"
F2J="$(mkfixture fc2j)"; unseal "$F2J"; census "$F2J" 2  # runtime-install rewrites the stamp file too
rec "$F2J" wrapper deny wrapper-guard-missing-annotate-web "2026-07-28T11:00:00Z"; seal "$F2J"
_fc_stamp "$F2J" runtime-install "2026-08-01T00:00:00+03:00"
t_eq "a runtime-install is not a floor reinstall" crit "$(sev_of "$F2J" FC-2)"
# A record dated D leaves the crit half on D + horizon + 1: 2026-08-02 + 8 with the pinned clock.
t_has "the crit repair names the day the row demotes" "$_r2b" "2026-08-10"

t_section "FC-3: four gates in one day is one episode (warn, not crit)"
F3="$(mkfixture fc3)"; unseal "$F3"; census "$F3" 4; sessions "$F3" 4
for _t in 19:44:59 19:45:15 19:55:43 19:56:33; do rec "$F3" integrity gate integrity-drift "2026-08-02T${_t}Z"; done
seal "$F3"
t_eq "four gates in one window" warn "$(sev_of "$F3" FC-3)"
F3B="$(mkfixture fc3b)"; unseal "$F3B"; census "$F3B" 4; sessions "$F3B" 2
rec "$F3B" integrity gate integrity-drift "2026-08-02T19:44:59Z"
rec "$F3B" integrity gate integrity-drift "2026-08-03T09:10:00Z"; seal "$F3B"
t_eq "a gate returning on a second day" crit "$(sev_of "$F3B" FC-3)"

t_section "FC-4: an advisory on two days fires; on one day it does not"
F4="$(mkfixture fc4)"; unseal "$F4"; census "$F4" 2; sessions "$F4" 2
rec "$F4" integrity advise integrity-advisory "2026-08-02T10:00:00Z"
rec "$F4" integrity advise integrity-advisory "2026-08-03T10:00:00Z"; seal "$F4"
t_eq "FC-4 fires across two days" yes "$(has_rule "$F4" FC-4)"
F4G="$(mkfixture fc4green)"; unseal "$F4G"; census "$F4G" 2; sessions "$F4G" 2
rec "$F4G" integrity advise integrity-advisory "2026-08-02T10:00:00Z"
rec "$F4G" integrity advise integrity-advisory "2026-08-02T11:00:00Z"; seal "$F4G"
t_eq "twice in one day: no findings" "" "$(rules_of "$F4G")"

t_section "horizon (harbor#211): recurrence is a question about the last N days"
FH1="$(mkfixture h1)"; unseal "$FH1"; census "$FH1" 2; sessions "$FH1" 2  # the shape #211 was filed on
rec "$FH1" integrity gate integrity-drift "2026-07-23T19:44:59Z"
rec "$FH1" integrity gate integrity-drift "2026-08-03T14:51:44Z"; seal "$FH1"
t_eq "two gate episodes 11d apart" warn "$(sev_of "$FH1" FC-3)"
t_has "the demoted FC-3 names the date it last fired" "$(subj_of "$FH1" FC-3)" "none since 2026-08-03"
t_eq "and the run's worst" warn "$(worst_of "$FH1")"
FH2="$(mkfixture h2)"; unseal "$FH2"; census "$FH2" 2; sessions "$FH2" 2
rec "$FH2" integrity gate integrity-drift "2026-08-02T19:44:59Z"
rec "$FH2" integrity gate integrity-drift "2026-08-03T09:10:00Z"; seal "$FH2"
t_eq "consecutive-day gates inside the window" crit "$(sev_of "$FH2" FC-3)"
FH3="$(mkfixture h3)"; unseal "$FH3"; census "$FH3" 2; sessions "$FH3" 2
rec "$FH3" integrity gate integrity-drift "2026-07-27T10:00:00Z"
rec "$FH3" integrity gate integrity-drift "2026-08-03T10:00:00Z"; seal "$FH3"
t_eq "a pair exactly 7d apart is inside the 7d window" crit "$(sev_of "$FH3" FC-3)"

t_section "FC-3: recurrence inside the window, but the gate has gone clean (2026-08-27)"
G5CLEAN="$(mkfixture h5clean)"; unseal "$G5CLEAN"; census "$G5CLEAN" 2; sessions "$G5CLEAN" 3
rec "$G5CLEAN" integrity gate  integrity-drift "2026-07-30T10:00:00Z"
rec "$G5CLEAN" integrity gate  integrity-drift "2026-08-01T09:00:00Z"
rec "$G5CLEAN" integrity allow integrity-clean "2026-08-02T13:00:00Z"; seal "$G5CLEAN"
t_eq "two gate days then a clean verdict" warn "$(sev_of "$G5CLEAN" FC-3)"
t_eq "and the run's worst" warn "$(worst_of "$G5CLEAN")"
_h5s="$(subj_of "$G5CLEAN" FC-3)"  # dated on both ends, or the reader cannot falsify it
t_has "it names when it last fired" "$_h5s" "last fired 2026-08-01"
t_has "it names when B6 last read clean" "$_h5s" "clear since 2026-08-02T13:00:00Z"
t_hasnt "its repair does not send anyone to restore.sh" "$(repair_of "$G5CLEAN" FC-3)" "restore.sh"
# guard-integrity.sh reaches its advise branch only when B6 found no blocking drift.
G6ADV="$(mkfixture h6advise)"; unseal "$G6ADV"; census "$G6ADV" 2; sessions "$G6ADV" 3
rec "$G6ADV" integrity gate   integrity-drift    "2026-07-30T10:00:00Z"
rec "$G6ADV" integrity gate   integrity-drift    "2026-08-01T09:00:00Z"
rec "$G6ADV" integrity advise integrity-advisory "2026-08-02T13:00:00Z"; seal "$G6ADV"
t_eq "two gate days then an advisory" warn "$(sev_of "$G6ADV" FC-3)"
G7BETWEEN="$(mkfixture h7between)"; unseal "$G7BETWEEN"; census "$G7BETWEEN" 2; sessions "$G7BETWEEN" 3
rec "$G7BETWEEN" integrity gate  integrity-drift "2026-07-30T10:00:00Z"
rec "$G7BETWEEN" integrity allow integrity-clean "2026-07-30T11:00:00Z"
rec "$G7BETWEEN" integrity gate  integrity-drift "2026-08-02T20:00:00Z"; seal "$G7BETWEEN"
t_eq "a clean BETWEEN two episodes: the latest verdict decides" crit "$(sev_of "$G7BETWEEN" FC-3)"

t_section "FC-2 and FC-4 under the horizon"
FH4="$(mkfixture h4)"; unseal "$FH4"; census "$FH4" 2; sessions "$FH4" 2
rec "$FH4" wrapper deny wrapper-guard-missing "2026-07-20T09:36:07Z"; seal "$FH4"
t_eq "a 14-day-old wrapper deny" warn "$(sev_of "$FH4" FC-2)"
t_has "the demoted FC-2 carries the record's date" "$(subj_of "$FH4" FC-2)" "2026-07-20"
t_hasnt "and promises no future demotion" "$(repair_of "$FH4" FC-2)" "demotes"
FH5="$(mkfixture h5)"; unseal "$FH5"; census "$FH5" 2; sessions "$FH5" 2
rec "$FH5" wrapper deny wrapper-guard-missing "2026-08-03T09:36:07Z"; seal "$FH5"
t_eq "a same-day wrapper deny" crit "$(sev_of "$FH5" FC-2)"
t_has "keeps its installer repair" "$(repair_of "$FH5" FC-2)" "floor-install"
t_eq "one FC-2 row per reason, not two halves" 1 "$(count_of "$FH5" FC-2)"
FH6="$(mkfixture h6)"; unseal "$FH6"; census "$FH6" 2; sessions "$FH6" 2
rec "$FH6" integrity advise integrity-advisory "2026-07-20T10:00:00Z"
rec "$FH6" integrity advise integrity-advisory "2026-07-21T10:00:00Z"; seal "$FH6"
t_eq "FC-4 on an advisory that stopped a fortnight ago" no "$(has_rule "$FH6" FC-4)"
FH7="$(mkfixture h7)"; unseal "$FH7"; census "$FH7" 2; sessions "$FH7" 2
rec "$FH7" integrity advise integrity-advisory "2026-07-28T10:00:00Z"
rec "$FH7" integrity advise integrity-advisory "2026-07-29T10:00:00Z"; seal "$FH7"
t_eq "FC-4 on a cause last seen 5 days ago (inside the 7d window)" no "$(has_rule "$FH7" FC-4)"
FH8="$(mkfixture h8)"; unseal "$FH8"; census "$FH8" 2; sessions "$FH8" 2
rec "$FH8" integrity advise integrity-advisory "2026-07-30T10:00:00Z"
rec "$FH8" integrity advise integrity-advisory "2026-08-03T10:00:00Z"; seal "$FH8"
t_eq "FC-4 on an advisory today" yes "$(has_rule "$FH8" FC-4)"
HARBOR_FC_NOW=not-a-date  # no resolvable today: every rule reverts to loud all-history
t_eq "an unreadable clock does not silence FC-3" crit "$(sev_of "$FH1" FC-3)"
HARBOR_FC_NOW=2026-08-03

t_section "mutation: FC-1's verify-run subtraction is load-bearing"
MUT="$TMP/mut-fc1.sh"
sed 's/^    _adj=\$((N_INTEGRITY - _vruns))$/    _adj=$((N_INTEGRITY))/' "$FC" > "$MUT"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT" && echo yes || echo no)"
FCT="$MUT"; t_eq "the verify-explained fixture fires FC-1" yes "$(has_rule "$F1V" FC-1)"; FCT="$FC"

t_section "mutation: FC-3's day clustering is load-bearing"
# Targets the crit arm by its `&& [ "$_gldec" = gate ]` half, which no other arm carries: a shorter
# pattern drifted onto a neighbouring elif twice (#211, 2026-08-27).
MUT3="$TMP/mut-fc3.sh"
sed 's/if \[ "\$_gdaysr" -ge 2 \] \&\& \[ "\$_gldec" = gate \]; then/if [ "$_ngater" -ge 2 ] \&\& [ "$_gldec" = gate ]; then/' "$FC" > "$MUT3"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT3" && echo yes || echo no)"
FCT="$MUT3"; t_eq "counting gates raw escalates the one-episode fixture" crit "$(sev_of "$F3" FC-3)"; FCT="$FC"

t_section "mutation: FC-3's clean-since guard is load-bearing"
MUT3B="$TMP/mut-fc3-clean.sh"
sed 's/ \&\& \[ "\$_gldec" = gate \]; then/; then/' "$FC" > "$MUT3B"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT3B" && echo yes || echo no)"
FCT="$MUT3B"; t_eq "without it the cleared fixture is crit again" crit "$(sev_of "$G5CLEAN" FC-3)"; FCT="$FC"

t_section "mutation: the exit code follows the finding counter"
MUT4="$TMP/mut-exit.sh"
sed 's/^\[ "\$NACT" -eq 0 \] || exit 1$/[ "$NACT" -eq 0 ] || exit 0/' "$FC" > "$MUT4"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT4" && echo yes || echo no)"
t_exit "the mutant exits 0 on a fixture with findings" 0 sh "$MUT4" "$F1"
t_done
