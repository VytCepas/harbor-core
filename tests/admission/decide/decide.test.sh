#!/usr/bin/env sh
# bin/admission-decide.sh and bin/admission-replay.sh (harbor#1030): one decision function reads a fired rule's mode from its row;
# an unreadable register fails closed with its remedy; the egress guard asks it and keeps every verdict it had.
. "$(dirname "$0")/../../lib/core.sh"; t_init
D="$T_ROOT/bin/admission-decide.sh"; REG="$T_ROOT/standards/naming/controls.tsv"; RP="$T_ROOT/bin/admission-replay.sh"

t_section "the decision function"
t_has "--self-test: every row of the admission controls returns the verdict its mode declares" "$(sh "$D" --self-test 2>&1)" "0 failed"
t_eq "a block row blocks" "block	admission.key-material-read	register" "$(sh "$D" egress key-material-read --register "$REG" 2>/dev/null)"
t_eq "...and prints its stamp, from this function only" "(control:admission.key-material-read mode:block verdict:block)" "$(sh "$D" egress key-material-read --register "$REG" 2>&1 >/dev/null)"
t_eq "a shadow session shadows a block row that does not keep enforcing" "shadow" "$(sh "$D" egress key-material-read --shadow 1 --register "$REG" 2>/dev/null | cut -f1)"
t_eq "...but not one that does" "block" "$(sh "$D" egress key-material-read --shadow 1 --enforcing 1 --register "$REG" 2>/dev/null | cut -f1)"
printf 'id\tmode\ttype\nadmission.softened\twarn\tadmission\n' > "$T_TMP/warnreg"
t_eq "a warn row warns" "warn" "$(sh "$D" egress softened --register "$T_TMP/warnreg" 2>/dev/null | cut -f1)"
t_eq "...and cannot loosen a rule that keeps enforcing" "block" "$(sh "$D" egress softened --enforcing 1 --register "$T_TMP/warnreg" 2>/dev/null | cut -f1)"

t_section "the failure mode, decided: an unreadable register fails closed and names its remedy"
t_eq "a missing register: block, source unreadable" "block	admission.key-material-read	unreadable" "$(sh "$D" egress key-material-read --register "$T_TMP/none" 2>/dev/null)"
t_has "...and the remedy is printed" "$(sh "$D" egress key-material-read --register "$T_TMP/none" 2>&1 >/dev/null)" "Remedy: restore standards/naming/controls.tsv"
t_eq "a rule with no row: block, source norow" "block	admission.not-a-rule	norow" "$(sh "$D" egress not-a-rule --register "$REG" 2>/dev/null)"
t_has "...and the remedy names the row to add" "$(sh "$D" egress not-a-rule --register "$REG" 2>&1 >/dev/null)" "add the row"

t_section "red then green: the self-test fails when the table is broken"
cp "$D" "$T_TMP/broken.sh"; sed 's/block)  if \[ "\$_sh" = 1 \] \&\& \[ "\$_en" != 1 \]; then _v=shadow; else _v=block; fi ;;/block)  _v=block ;;/' "$D" > "$T_TMP/broken.sh"
t_eq "the mutation changed the file" 1 "$(cmp -s "$D" "$T_TMP/broken.sh" && echo 0 || echo 1)"
t_has "a decision function that ignores the shadow session fails its own self-test" "$(sh "$T_TMP/broken.sh" --self-test 2>&1 || :)" "mismatch"

t_section "no stamp lives in a guard: the decision function prints it"
t_eq "no guard prints a control stamp" 0 "$(grep -l '(control:' "$T_ROOT"/bin/admission-*.sh "$T_ROOT/bin/library-admission.sh" | grep -vc 'admission-decide.sh' || :)"

t_section "the replay diff"
printf 's1\tr1\tallow\ns1\tr2\tblock\n' > "$T_TMP/a.tsv"; cp "$T_TMP/a.tsv" "$T_TMP/b.tsv"
t_eq "equal runs: empty diff, exit 0" 0 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"
printf 's1\tr1\tallow\ns1\tr2\tallow\n' > "$T_TMP/b.tsv"
t_eq "a moved verdict: exit 1" 1 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"
t_has "...named with both verdicts" "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" 2>&1 || :)" "DIFF	s1	r2	block	allow"
printf 's1\tr1\tallow\n' > "$T_TMP/b.tsv"
t_has "a row missing from the second run is a difference, not a pass" "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" 2>&1 || :)" "MISSING	s1	r2"
: > "$T_TMP/b.tsv"
t_eq "an empty run compares nothing: exit 2" 2 "$(sh "$RP" diff "$T_TMP/a.tsv" "$T_TMP/b.tsv" >/dev/null 2>&1; echo $?)"

t_section "a rule is found by what its guard emits, so a renamed slug still has its row"
t_eq "bash:cd-cfg-then-fetch is the row admission.cd-config-then-fetch" "admission.cd-config-then-fetch" "$(sh "$D" bash cd-cfg-then-fetch --register "$REG" 2>/dev/null | cut -f2)"
t_eq "selfedit:floor-surface is the row admission.baseline-surface" "admission.baseline-surface" "$(sh "$D" selfedit floor-surface --register "$REG" 2>/dev/null | cut -f2)"
t_eq "the same slug under another guard is no row" "norow" "$(sh "$D" cloud cd-cfg-then-fetch --register "$REG" 2>/dev/null | cut -f3)"

t_section "every rule a guard raises through floor_block is a row (the bash, egress and self-edit guards)"
# the rule slugs are literals at the call sites: floor_block bash|egress|selfedit <message> <slug>.<shape>
for _g in bash egress self-edit; do
  grep -ho 'floor_block \(bash\|egress\|selfedit\) .*' "$T_ROOT/bin/admission-$_g.sh"
done | sed -E 's/^floor_block ([a-z]+) .* ([a-z0-9-]+)\.(flat|argv|path|glob|[a-z]+)[ ;)]*.*$/\1:\2/' | grep -E '^(bash|egress|selfedit):[a-z0-9-]+$' | sort -u > "$T_TMP/rules"
awk -F'\t' '/^#/ { next } $3 == "admission" && $12 != "-" { print $12 }' "$REG" | sort -u > "$T_TMP/rows"
t_eq "the call sites were found" 1 "$([ "$(grep -c . "$T_TMP/rules")" -gt 100 ] && echo 1 || echo 0)"
t_eq "no rule is without a row" "" "$(comm -23 "$T_TMP/rules" "$T_TMP/rows" | tr '\n' ' ')"

t_section "the bash guard asks the function: flipping one row changes its verdict, nothing else does"
_probe() { # <command>: the bash guard's exit status for one Bash call
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"s1","cwd":"/tmp"}' "$1" | sh "$T_ROOT/bin/admission-bash.sh" >/dev/null 2>"$T_TMP/probe.err"; echo $?
}
t_eq "crontab -e: blocked by the live register" 2 "$(_probe 'crontab -e')"
t_has "...and the stamp names the control, printed by the function" "$(cat "$T_TMP/probe.err")" "(control:admission.crontab-install mode:block verdict:block)"
awk -F'\t' -v OFS='\t' '$1 == "admission.crontab-install" { $2 = "warn" } { print }' "$REG" > "$T_TMP/warn-crontab.tsv"
t_eq "with that one row on warn: allowed" 0 "$(FLOOR_CONTROLS="$T_TMP/warn-crontab.tsv" _probe 'crontab -e')"
t_has "...and said so" "$(cat "$T_TMP/probe.err")" "WARN"
t_eq "another rule still blocks under that register" 2 "$(FLOOR_CONTROLS="$T_TMP/warn-crontab.tsv" _probe 'at now')"
awk -F'\t' -v OFS='\t' '$1 == "admission.crontab-install" { $2 = "bogus" } { print }' "$REG" > "$T_TMP/bogus.tsv"
t_eq "a row that is not one of the four modes decides as block" 2 "$(FLOOR_CONTROLS="$T_TMP/bogus.tsv" _probe 'crontab -e')"
t_eq "an unreadable register: still blocked (fails closed)" 2 "$(FLOOR_CONTROLS="$T_TMP/none" _probe 'crontab -e')"
t_has "...with the remedy" "$(cat "$T_TMP/probe.err")" "Remedy: restore standards/naming/controls.tsv"

t_section "every rule the other guards decide is a row (destroy, cloud, deliverables)"
{ grep -o 'RULE="[a-z-]*"' "$T_ROOT/bin/admission-destroy.sh" | sed -E 's/RULE="([a-z-]+)"/destroy:\1/' | grep -E '^destroy:[a-z]'
  grep -o '_crule=[a-z-]*' "$T_ROOT/bin/admission-cloud.sh" | sed -E 's/_crule=/cloud:/' | grep -v 'cloud-unclassified'   # the * arm: an unclassified tier, which asks
  grep -o '_kind="[a-z-]*"' "$T_ROOT/bin/admission-deliverables.sh" | sed -E 's/_kind="([a-z-]+)"/deliverables:\1/' | grep -E '^deliverables:[a-z]'
} | sort -u > "$T_TMP/rules2"
t_eq "the rules were found" 1 "$([ "$(grep -c . "$T_TMP/rules2")" -gt 15 ] && echo 1 || echo 0)"
t_eq "no rule is without a row" "" "$(comm -23 "$T_TMP/rules2" "$T_TMP/rows" | tr '\n' ' ')"

t_section "the ask-tier guards: the row says ask or deny, and a guard holds no tier of its own"
_pd() { # <guard> <command>: the permissionDecision the guard prints, or allow
  _o="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"session_id":"s1","cwd":"/tmp"}' "$2" | sh "$T_ROOT/bin/admission-$1.sh" 2>/dev/null)"
  case "$_o" in *'"permissionDecision":"ask"'*) echo ask ;; *'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}
t_eq "git reset --hard asks (a warn row)" ask "$(_pd destroy 'git reset --hard HEAD~1')"
awk -F'\t' -v OFS='\t' '$1 == "admission.git-reset-hard" { $2 = "block" } { print }' "$REG" > "$T_TMP/block-reset.tsv"
t_eq "...with that one row on block it denies" deny "$(FLOOR_CONTROLS="$T_TMP/block-reset.tsv" _pd destroy 'git reset --hard HEAD~1')"
t_eq "...and git clean -f still asks" ask "$(FLOOR_CONTROLS="$T_TMP/block-reset.tsv" _pd destroy 'git clean -fd')"
t_eq "...and with no register it asks as it did before rows" ask "$(FLOOR_CONTROLS="$T_TMP/none" _pd destroy 'git reset --hard HEAD~1')"
t_eq "a diskutil wipe denies (a block row)" deny "$(_pd destroy 'diskutil eraseDisk JHFS+ X disk9')"
t_eq "...and with no register it still denies" deny "$(FLOOR_CONTROLS="$T_TMP/none" _pd destroy 'diskutil eraseDisk JHFS+ X disk9')"
t_eq "a generic gcloud delete asks (the soft tier, a warn row)" ask "$(_pd cloud 'gcloud compute instances delete vm1')"
awk -F'\t' -v OFS='\t' '$1 == "admission.cloud-soft" { $2 = "block" } { print }' "$REG" > "$T_TMP/block-soft.tsv"
t_eq "...with that row on block it denies" deny "$(FLOOR_CONTROLS="$T_TMP/block-soft.tsv" _pd cloud 'gcloud compute instances delete vm1')"
t_eq "...with no register it asks as it did before rows" ask "$(FLOOR_CONTROLS="$T_TMP/none" _pd cloud 'gcloud compute instances delete vm1')"
t_eq "a project delete denies (the catastrophic tier, a block row)" deny "$(_pd cloud 'gcloud projects delete p1')"
t_eq "...and with no register it still denies" deny "$(FLOOR_CONTROLS="$T_TMP/none" _pd cloud 'gcloud projects delete p1')"
t_eq "a posture of deny turns an ask into a deny" deny "$(CLOUD_POSTURE=deny _pd cloud 'gcloud compute instances delete vm1')"
awk -F'\t' -v OFS='\t' '$1 == "admission.cloud-soft" { $2 = "shadow" } { print }' "$REG" > "$T_TMP/shadow-soft.tsv"
t_eq "a shadow row records and allows" allow "$(FLOOR_CONTROLS="$T_TMP/shadow-soft.tsv" _pd cloud 'gcloud compute instances delete vm1')"

t_section "the deliverables guard: its row decides, shadow and warn allow"
_dl() { # <register>: the verdict for a loose document written into the sandbox HOME
  _o="$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/loose.md"},"session_id":"s1","cwd":"/tmp"}' "$HOME" | FLOOR_CONTROLS="$1" sh "$T_ROOT/bin/admission-deliverables.sh" 2>/dev/null)"
  case "$_o" in *'"permissionDecision":"deny"'*) echo deny ;; *) echo allow ;; esac
}
t_eq "a loose document in HOME is refused" deny "$(_dl "$REG")"
awk -F'\t' -v OFS='\t' '$1 == "admission.deliverable-home-loose" { $2 = "warn" } { print }' "$REG" > "$T_TMP/warn-dl.tsv"
t_eq "...with its row on warn it is allowed" allow "$(_dl "$T_TMP/warn-dl.tsv")"
t_eq "...and with no register it is still refused" deny "$(_dl "$T_TMP/none")"
t_done
