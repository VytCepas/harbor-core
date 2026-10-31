#!/usr/bin/env sh
# audit-triage.sh (M5, harbor#44), part 2: FC-5 (a command blocked again and again) with its horizon
# and the exclusion of the verifier's and the suite's own traffic, then FC-6 to FC-8. The exclusions are
# proven against the independent digest oracle in failure-capture-fixture.sh.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/audit/triage/fixture.sh"

t_section "FC-5: a non-probe command blocked three times"
F5="$(mkfixture fc5)"; unseal "$F5"; census "$F5" 2
recn 3 "$F5" bash block mutate-aimed-surface "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5"
t_eq "FC-5 fires" yes "$(has_rule "$F5" FC-5)"

t_section "FC-5 stays green below the threshold"
F5T="$(mkfixture fc5thresh)"; unseal "$F5T"; census "$F5T" 2
recn 2 "$F5T" bash block mutate-aimed-surface "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5T"
t_eq "two occurrences: no findings" "" "$(rules_of "$F5T")"

t_section "FC-5: a deny or an ask is a refusal too (harbor#319)"
F5A="$(mkfixture fc5ask)"; unseal "$F5A"; census "$F5A" 2
recn 3 "$F5A" destroy ask git-worktree-remove-force "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5A"
t_eq "three asks on one command fire" yes "$(has_rule "$F5A" FC-5)"
t_has "named as refused, by its rule" "$(subj_of "$F5A" FC-5)" "git-worktree-remove-force · 1 distinct command refused >=3x"
F5D="$(mkfixture fc5deny)"; unseal "$F5D"; census "$F5D" 2
recn 3 "$F5D" deliverables deny home-loose "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5D"
t_eq "three denies on one command fire" yes "$(has_rule "$F5D" FC-5)"
F5V="$(mkfixture fc5advise)"; unseal "$F5V"; census "$F5V" 2
recn 3 "$F5V" bash advise some-advice "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5V"
t_eq "an advise refuses nothing, so three of them stay green" "" "$(rules_of "$F5V")"

t_section "FC-5 horizon: the count spans all history, only the last block is horizoned"
F5OLD="$(mkfixture fc5stale)"; unseal "$F5OLD"; census "$F5OLD" 2  # the 7d cutoff is 2026-07-27
recn 3 "$F5OLD" bash block mutate-aimed-surface "2026-07-01T12:00:00Z" "$D_REAL"; seal "$F5OLD"
t_eq "a month-cold recurrence is history" no "$(has_rule "$F5OLD" FC-5)"
F5MIX="$(mkfixture fc5mixed)"; unseal "$F5MIX"; census "$F5MIX" 2
recn 2 "$F5MIX" bash block mutate-aimed-surface "2026-07-01T12:00:00Z" "$D_REAL"
recn 1 "$F5MIX" bash block mutate-aimed-surface "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5MIX"
t_eq "two old blocks and one yesterday still fire" yes "$(has_rule "$F5MIX" FC-5)"
t_has "with the all-history count" "$(subj_of "$F5MIX" FC-5)" "worst x3"
HARBOR_AUDIT_TRIAGE_NOW=not-a-date  # fail loud: an unreadable clock never makes a finding disappear
t_eq "an unresolvable clock reports the stale recurrence" yes "$(has_rule "$F5OLD" FC-5)"
HARBOR_AUDIT_TRIAGE_NOW=2026-08-03

t_section "FC-5 stays green on the verifier's own probe traffic"
t_eq "a probe subject is derived from admission-verify.sh" yes "$([ -n "$PROBE_SUBJ" ] && echo yes || echo no)"
F5P="$(mkfixture fc5probe)"; unseal "$F5P"; census "$F5P" 2
recn 30 "$F5P" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$(digest_of "$PROBE_SUBJ")"; seal "$F5P"
t_eq "30 probe blocks: no findings" "" "$(rules_of "$F5P")"
t_eq "probe_traffic_excluded" true "$(q '.probe_traffic_excluded' "$F5P")"
t_eq "--with-probes shows them again" yes "$(has_rule "$F5P" FC-5 --with-probes)"

t_section "FC-5 stays green on the floor suite's own payloads (tests/floor/, harbor#727)"
# Chosen ABSENT from admission-verify.sh: the first bash_j payload is also a probe, and against it this
# section stayed green with the suite derivation stubbed out (№2.10). awk, since grep is ugrep here.
SUITE_SUBJ=""
while IFS= read -r _cand; do
  [ -n "$_cand" ] || continue
  case "$_cand" in (*'$'*) continue ;; esac
  awk -v needle="$_cand" 'index($0, needle) { found = 1 } END { exit(found ? 0 : 1) }' \
     "$SRC/admission-verify.sh" 2>/dev/null && continue
  SUITE_SUBJ="$_cand"; break
done <<SUITE_CANDIDATES
$(for _ff in "$T_ROOT"/tests/admission/baseline/fixture.sh "$T_ROOT"/tests/admission/baseline/*.test.sh; do
  sed -n "s/.*bash_j '\\([^']*\\)'.*/\\1/p" "$_ff" 2>/dev/null; done)
SUITE_CANDIDATES
t_eq "a bash_j payload is derived from the floor suite" yes "$([ -n "$SUITE_SUBJ" ] && echo yes || echo no)"
t_eq "and admission-verify.sh does not carry it" absent "$(awk -v needle="$SUITE_SUBJ" \
  'index($0, needle) { found = 1 } END { print (found ? "present" : "absent") }' "$SRC/admission-verify.sh")"
F5S="$(mkfixture fc5suite)"; unseal "$F5S"; census "$F5S" 2
recn 30 "$F5S" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$(digest_of "$SUITE_SUBJ")"; seal "$F5S"
t_eq "30 suite-payload blocks: no findings" "" "$(rules_of "$F5S")"
# The discrimination control: an exclusion that swallowed everything would pass the line above.
F5TD="$(mkfixture fc5suitediscrim)"; unseal "$F5TD"; census "$F5TD" 2
recn 30 "$F5TD" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$(digest_of "$SUITE_SUBJ")"
recn  4 "$F5TD" bash block rm-rf-root    "2026-08-02T12:00:00Z" "$(digest_of 'an operator command that is in neither tool')"
seal "$F5TD"
t_eq "an operator block in the same ledger still fires" yes "$(has_rule "$F5TD" FC-5)"
t_has "the surviving row is the operator's rule" "$(subj_of "$F5TD" FC-5)" "rm-rf-root"
t_hasnt "and not the suite payload's" "$(subj_of "$F5TD" FC-5)" "pipe-to-shell"
t_eq "--with-probes shows the suite traffic again" yes "$(has_rule "$F5S" FC-5 --with-probes)"

t_section "FC-5 suite exclusion, installed shape: manifest present, suite absent"
# The floor suite does not ship (X7), so an installed judge reads $SELF/.helm-suite-payloads. Before
# this arm the fix was green here and inert once installed.
F5M="$TMP/selfdir"; mkdir -p "$F5M"
cp "$SRC/audit-triage.sh" "$SRC/library-admission.sh" "$SRC/admission-verify.sh" "$F5M/"
[ -f "$SRC/admission-normalize.awk" ] && cp "$SRC/admission-normalize.awk" "$F5M/"
t_eq "the installed copy has no floor suite beside it" no "$([ -f "$F5M/../tests/admission/baseline/baseline.test.sh" ] && echo yes || echo no)"
printf 'C%s\n' "$SUITE_SUBJ" > "$F5M/.helm-suite-payloads"
FCT="$F5M/audit-triage.sh"
t_eq "the manifest excludes the suite payload" "" "$(rules_of "$F5S")"
t_eq "suite_traffic_excluded with the manifest" true "$(q '.suite_traffic_excluded' "$F5S")"
rm -f "$F5M/.helm-suite-payloads"  # the negative that proves the manifest is load-bearing
t_eq "with no manifest the finding returns" yes "$(has_rule "$F5S" FC-5)"
t_eq "suite_traffic_excluded with neither" false "$(q '.suite_traffic_excluded' "$F5S")"
ln -s /dev/null "$F5M/.helm-suite-payloads"  # this file can delete a finding: a link is refused
t_eq "a symlinked manifest is not read" false "$(q '.suite_traffic_excluded' "$F5S")"
rm -f "$F5M/.helm-suite-payloads"; FCT="$FC"

t_section "FC-5: a replaced salt is not reported as a successful exclusion"
# No record says which salt digested it, so six probe digests computing cleanly proves only that
# the salt parses now. test-sandbox-make.sh copies the ledger and not the salt.
F5W="$(mkfixture fc5saltswap)"; unseal "$F5W"; census "$F5W" 2
recn 30 "$F5W" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$(digest_of "$PROBE_SUBJ")"; seal "$F5W"
printf 'fedcba9876543210fedcba9876543210\n' > "$F5W/.helm-obs-salt"
t_eq "probe_traffic_excluded" false "$(q '.probe_traffic_excluded' "$F5W")"
t_has "it warns that nothing was excluded" "$(breaks_of "$F5W" FC-5)" "NONE of them appears"

t_section "FC-5: an unreadable salt defers loudly, it does not quietly include (№2.7)"
F5N="$(mkfixture fc5nosalt)"; rm -f "$F5N/.helm-obs-salt"; unseal "$F5N"; census "$F5N" 2
recn 4 "$F5N" bash block pipe-to-shell "2026-08-02T12:00:00Z" "$D_REAL"; seal "$F5N"
t_eq "probe_traffic_excluded" false "$(q '.probe_traffic_excluded' "$F5N")"
t_has "the finding says probe traffic is still in the count" "$(breaks_of "$F5N" FC-5)" "could NOT be separated"

t_section "FC-6: a block carrying no digest"
F6="$(mkfixture fc6)"; unseal "$F6"; census "$F6" 2
rec "$F6" bash block rm-rf-root "2026-08-02T12:00:00Z" -; seal "$F6"
t_eq "FC-6 fires" yes "$(has_rule "$F6" FC-6)"
F6G="$(mkfixture fc6green)"; unseal "$F6G"; census "$F6G" 2  # h is "-" by design off the block path
rec "$F6G" egress allow egress-clean "2026-08-02T12:00:00Z" -
rec "$F6G" web advise web-annotated "2026-08-02T12:00:01Z" -; seal "$F6G"
t_eq "the dash on allow and advise: no findings" "" "$(rules_of "$F6G")"

t_section "FC-7: a writable host directory, or a sink that is not a regular file"
F7="$(mkfixture fc7)"; unseal "$F7"; census "$F7" 2  # left unsealed on purpose
t_eq "FC-7 fires on a writable host dir" yes "$(has_rule "$F7" FC-7)"
t_eq "which is" crit "$(sev_of "$F7" FC-7)"
F7B="$(mkfixture fc7b)"; unseal "$F7B"; census "$F7B" 2
mv "$(SINK_OF "$F7B")" "$F7B/elsewhere.jsonl"; ln -s "$F7B/elsewhere.jsonl" "$(SINK_OF "$F7B")"; seal "$F7B"
t_eq "FC-7 fires on a symlinked sink" yes "$(has_rule "$F7B" FC-7)"

t_section "FC-8: a schema version this reader does not know"
F8="$(mkfixture fc8)"; unseal "$F8"; census "$F8" 2
printf '{"v":2,"ts":"2026-08-02T12:00:00Z","g":"bash","d":"block","r":"x","s":"meta","t":"Bash","h":"-"}\n' \
  >> "$(SINK_OF "$F8")"; seal "$F8"
t_eq "FC-8 fires on a v:2 record" yes "$(has_rule "$F8" FC-8)"
t_eq "with severity" unknown "$(sev_of "$F8" FC-8)"

t_section "mutation: FC-5's probe exclusion is load-bearing"
MUT2="$TMP/mut-fc5.sh"
sed 's/if (!(d in p) \&\& n+0>=3)/if (n+0>=3)/' "$FC" > "$MUT2"
t_eq "the mutation applies" no "$(cmp -s "$FC" "$MUT2" && echo yes || echo no)"
FCT="$MUT2"; t_eq "the probe fixture fires FC-5" yes "$(has_rule "$F5P" FC-5)"; FCT="$FC"
t_done
