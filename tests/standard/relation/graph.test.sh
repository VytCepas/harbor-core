#!/usr/bin/env sh
# graph-gen relation edges (harbor#996 G1): implements, enforces, enforced-by, notifies, disabled-by, findings-land-in,
# owned-by, red-proof, registered-in and motivated-by, each read from a registry row, the wiring or the git history.
# Hermetic: a fixture harbor tree with two commits. Every relation has a lookalike that must stay out, because a
# shape judged over an over-collected graph passes instances that carry nothing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/doc-graph-generate.sh"
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "graph-gen is unchecked without python3" 3 sh "$TOOL"; t_done; }
HB="$T_TMP/hb"; mkdir -p "$HB/standards/naming" "$HB/bin" "$HB/tests" "$HB/launchd" "$HB/contracts" "$HB/docs/decisions" "$HB/evals" "$HB/docs/reference" "$HB/policy"
TAB="$(printf '\t')"
{ printf '# controls.tsv fixture\n'
  printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'
  printf 'lint.x\twarn\tlint\tbin/lint-x.sh\t-\tci\tdetective\texperimental\t-\tlint\ttests/x.test.sh\t-\ta rule under D-1 (harbor#12)\n'
  printf 'lint.ghost\twarn\tlint\tbin/lint-x.sh\t-\tci\tdetective\texperimental\t-\tlint\ttests/missing.test.sh\t-\ta red proof that is not tracked\n'
  printf 'check.beat\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\talert\t-\tbeat\ta wired check\n'
  printf 'check.quiet\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\talert\t-\t-\ta check with no unit, stamp or receipt\n'
  printf 'check.lint.x\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\tcheck\t-\tlint.x\ta check that prints a lint rule'"'"'s id\n'
  printf 'check.daemon\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\talert\t-\tdaemon\ta system daemon\n'
} > "$HB/standards/naming/controls.tsv"
printf '#!/bin/sh\nrule_Q1() {\nrule "lint.x a rule"\n}\n' > "$HB/bin/lint-x.sh"
printf '#!/bin/sh\necho "[check:beat] ok"\nlog_receipt "$RD" beat green\n# log_receipt "$RD" check.quiet red\n' > "$HB/bin/beat.sh"
printf '#!/bin/sh\necho "[check:check.quiet]"\nlog_receipt "$RD" check.quiet red\n' > "$HB/tests/beat-test.sh"
printf '#!/bin/sh\necho "[check:beat] up"\n' > "$HB/bin/stamp-only.sh"
printf '#!/bin/sh\nlog_receipt "$RD" beat green\n' > "$HB/bin/receipt-only.sh"
printf '#!/bin/sh\n: proof\n' > "$HB/tests/x.test.sh"
chmod +x "$HB/bin/lint-x.sh" "$HB/bin/beat.sh" "$HB/bin/stamp-only.sh" "$HB/bin/receipt-only.sh" "$HB/tests/beat-test.sh" "$HB/tests/x.test.sh"
cat > "$HB/docs/reference/checks.md" <<'EOF'
# CHECKS

## Register

| id | watches | schedule | notifies | red means |
|---|---|---|---|---|
| `beat` | a heartbeat | every 60s | a desktop banner and `checks.log` | it stopped |
| `check.quiet` | nothing, `a | b` in a cell | never | none — cache only | n/a. Disable: delete `quiet.sh` and this row |
| `lint.x` | a count that only goes down | on demand | stdout | it went up |
| `daemon` | a system daemon | every 300s | its own `status.json` | it stopped. **Disable:** `sudo sh bin/daemon-setup.sh --uninstall` |
| `unregistered` | no control row | never | desktop | n/a. Disable: `rm nothing` |

## Disable

```sh
launchctl bootout gui/$UID/com.harbor.<id>          # stop now
rm ~/Library/LaunchAgents/com.harbor.<id>.plist     # stop for good
systemctl --user disable --now harbor-<id>.timer    # stop now and for good
```

## Platforms

| id | platforms | why | disable |
|---|---|---|---|
| beat | macOS, Linux | a user agent | macOS: `launchctl bootout gui/$(id -u)/com.harbor.beat`. Linux: `systemctl --user disable --now harbor-beat.timer` |
| check.quiet | inherits: `beat` | no schedule of its own | the register row's own |
| lint.x | inherits: a terminal | no schedule of its own | the register row's own |
| daemon | macOS | a system daemon, as its own user | macOS: `sudo launchctl bootout system/com.harbor.daemon` |
EOF
printf '<plist><string>com.harbor.beat</string></plist>\n' > "$HB/launchd/com.harbor.beat.plist"
printf '<plist><string>com.harbor.daemon</string></plist>\n' > "$HB/launchd/com.harbor.daemon.plist"
cat > "$HB/contracts/finding.md" <<'EOF'
| lane | key | subject | repair | ticket |
|---|---|---|---|---|
| HEAL | `lint/lint.ghost` | `*` | `sh bin/outside.sh` | #1 |
<!-- lanes:begin -->
| lane | key | subject | repair | ticket |
|---|---|---|---|---|
| HEAL | `check/check.quiet` | `*` | `sh bin/quiet.sh --fix` | #2 |
| DECIDE | `lint/lint.x` | `*` | - | #3 |
<!-- lanes:end -->
EOF
printf -- '- **No AI trailers.** Enforced by lint rule **Q1**.\n- **The critique rule.** **Nothing enforces this rule**, by judgment.\n- GitHub enforces no required check here, and this sentence then names `lint.ghost` far away.\n- What is enforced; `lint.y` sits past the break.\n' > "$HB/policy/constitution.md"
printf 'a report on another repo: enforced by **Q1**\n' > "$HB/evals/notes.md"
printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-1\n---\n\n# One\n\nMotivated by harbor#7.\n' > "$HB/docs/decisions/0001-one.md"
git -C "$HB" init -q && git -C "$HB" add -A
git -C "$HB" -c user.email=t@t -c user.name=t commit -qm "feat(standard): the registry (harbor#19)" -m "Refs: #18"
printf '# lint.y joins\nlint.y\twarn\tlint\tbin/lint-x.sh\t-\tci\tdetective\texperimental\t-\tlint\t-\t-\ta rule added later\n' >> "$HB/standards/naming/controls.tsv"
git -C "$HB" -c user.email=t@t -c user.name=t commit -qam "feat(standard): the fixture (harbor#20)" -m "Refs: #21"
sed "s/a red proof that is not tracked/a red proof, still untracked/" "$HB/standards/naming/controls.tsv" > "$T_TMP/c" && cp "$T_TMP/c" "$HB/standards/naming/controls.tsv"
git -C "$HB" -c user.email=t@t -c user.name=t commit -qam "fix(standard): retitle one row" -m "Refs: harbor#22"
G="$HB/build/graph.tsv"
gen() { sh "$TOOL" --root "$HB" "$@"; }
row() { awk -F'\t' -v e="$1" -v f="$2" -v t="$3" '$1 == e && $2 == f && $3 == t { n = 1 } END { print n + 0 }' "$G"; }  # <edge> <from> <to>: 1 if the edge exists, at any number of sites
cnt() { awk -F'\t' -v e="$1" -v f="$2" '$1 == e && $2 == f { n++ } END { print n + 0 }' "$G"; }                    # <edge> <from>
t_exit "a build exits 0" 0 gen
GRAPH="$(cat "$G")"

t_section "each derived relation says where it is read from"
for r in implements enforces enforced-by notifies disabled-by findings-land-in owned-by red-proof registered-in motivated-by; do
  t_has "# relation $r" "$GRAPH" "# relation${TAB}$r${TAB}"
done

t_section "controls.tsv rows: owned-by, red-proof, implements"
t_eq "owned-by its owner family" 1 "$(row owned-by control:lint.x family:lint)"
t_eq "red-proof names its tracked suite" 1 "$(row red-proof control:lint.x harbor:tests/x.test.sh)"
t_eq "a red proof that is not tracked is no edge" 0 "$(cnt red-proof control:lint.ghost)"
t_eq "the engine implements the control" 1 "$(row implements harbor:bin/lint-x.sh control:lint.x)"
t_eq "a markdown register is no implementation" 0 "$(awk -F'\t' '$1 == "implements" && $2 == "harbor:docs/reference/checks.md"' "$G" | wc -l | tr -d ' ')"
t_eq "the code that stamps and receipts a check implements it" 1 "$(row implements harbor:bin/beat.sh control:check.beat)"
t_eq "...code that only stamps [check:<id>] implements it" 1 "$(row implements harbor:bin/stamp-only.sh control:check.beat)"
t_eq "...and code that only writes its receipt" 1 "$(row implements harbor:bin/receipt-only.sh control:check.beat)"
t_eq "a test that stamps a check id implements nothing" 0 "$(row implements harbor:tests/beat-test.sh control:check.quiet)"

t_section "enforces and enforced-by"
t_eq "a D-n in the row: enforces" 1 "$(row enforces control:lint.x decision:D-1)"
t_eq "...and enforced-by, read backward" 1 "$(row enforced-by decision:D-1 control:lint.x)"
t_eq "a retired letter beside 'Enforced by' reaches the control" 1 "$(row enforces control:lint.x harbor:policy/constitution.md)"
t_eq "...and the clause file is enforced-by it" 1 "$(row enforced-by harbor:policy/constitution.md control:lint.x)"
t_eq "'Nothing enforces this rule' is a declared judgment" 1 "$(row enforced-by harbor:policy/constitution.md judgment:unenforced)"
t_eq "a control named far from the word enforces nothing" 0 "$(cnt enforces control:lint.ghost)"
t_eq "a control past a sentence break from the word enforces nothing" 0 "$(cnt enforces control:lint.y)"
t_eq "recorded prose (evals) states no clause" 0 "$(awk -F'\t' '$3 ~ /evals/ || $2 ~ /evals/' "$G" | grep -c '^enforce' || :)"

t_section "docs/reference/checks.md: registered-in, notifies, disabled-by"
t_eq "a check is registered in docs/reference/checks.md by the id it prints" 1 "$(row registered-in control:check.beat harbor:docs/reference/checks.md)"
t_eq "...once: the Platforms table is not the register" 1 "$(cnt registered-in control:check.beat)"
t_eq "a lint control is no check, though a check prints its id" 0 "$(row registered-in control:lint.x harbor:docs/reference/checks.md)"
t_eq "...the check that prints it is registered" 1 "$(row registered-in control:check.lint.x harbor:docs/reference/checks.md)"
t_eq "...or by its own id when it prints no other" 1 "$(row registered-in control:check.quiet harbor:docs/reference/checks.md)"
t_eq "a register row with no control is no edge" 0 "$(grep -c 'unregistered' "$G" || :)"
t_eq "notifies: desktop" 1 "$(row notifies control:check.beat channel:desktop)"
t_eq "notifies: checks.log, from the same cell" 1 "$(row notifies control:check.beat channel:checks-log)"
t_eq "...and no channel read from another table" "channel:checks-log channel:desktop" "$(awk -F'\t' '$1 == "notifies" && $2 == "control:check.beat" { print $3 }' "$G" | sort -u | tr '\n' ' ' | sed 's/ $//')"
t_eq "a declared none is the channel none, and nothing else" "channel:none" "$(awk -F'\t' '$1 == "notifies" && $2 == "control:check.quiet" { print $3 }' "$G")"
t_eq "a Platforms disable cell: each command in it is an edge" 1 "$(row disabled-by control:check.beat 'command:launchctl bootout gui/$(id -u)/com.harbor.beat')"
t_eq "...the Linux one too, from the same cell" 1 "$(row disabled-by control:check.beat 'command:systemctl --user disable --now harbor-beat.timer')"
t_eq "...and nothing else: two commands, two edges" 2 "$(cnt disabled-by control:check.beat)"
t_eq "a system daemon is disabled by its own system/ command" 1 "$(row disabled-by control:check.daemon 'command:sudo launchctl bootout system/com.harbor.daemon')"
t_eq "...never the user-agent template, though its launchd unit is tracked" 0 "$(awk -F'\t' '$1 == "disabled-by" && $3 ~ /gui\/\$UID/' "$G" | wc -l | tr -d ' ')"
t_eq "...and its register clause is not read when the Platforms cell names commands" 1 "$(cnt disabled-by control:check.daemon)"
t_eq "a cell that defers reads the register row's Disable clause, whole" 1 "$(row disabled-by control:check.quiet 'command:delete `quiet.sh` and this row')"
t_eq "a check whose row names no way to disable it has no disabled-by" 0 "$(cnt disabled-by control:check.lint.x)"

t_section "findings-land-in: a receipt is the finding store, a HEAL row is a repair"
t_eq "log_receipt lands the check's findings in finding:check/<id>" 1 "$(row findings-land-in control:check.beat finding:check/beat)"
t_eq "a HEAL row inside the lanes block is a repair" 1 "$(row findings-land-in control:check.quiet 'command:sh bin/quiet.sh --fix')"
t_eq "a commented or a test's log_receipt lands nothing" 0 "$(row findings-land-in control:check.quiet finding:check/check.quiet)"
t_eq "a HEAL row outside the block is not read" 0 "$(cnt findings-land-in control:lint.ghost)"
t_eq "a DECIDE row is no repair" 0 "$(cnt findings-land-in control:lint.x)"

t_section "motivated-by: the row, the record, and the commits that changed the row"
t_eq "an issue cited in the row" 1 "$(row motivated-by control:lint.x issue:harbor#12)"
t_eq "the commit that created controls.tsv is a census: it motivates no row" 0 "$(awk -F'\t' '$1 == "motivated-by" && ($3 == "issue:harbor#18" || $3 == "issue:harbor#19")' "$G" | wc -l | tr -d ' ')"
t_eq "the subject of the commit that added the row" 1 "$(row motivated-by control:lint.y issue:harbor#20)"
t_eq "...and its Refs trailer, a bare #n being harbor's" 1 "$(row motivated-by control:lint.y issue:harbor#21)"
t_eq "...and no row it did not add" 0 "$(row motivated-by control:lint.x issue:harbor#20)"
t_eq "a comment line the commit added is no control" 0 "$(awk -F'\t' '$1 == "motivated-by" && $2 ~ /^control:/ && $2 !~ /^control:(lint\.[xy]|lint\.ghost|check\.(beat|quiet|lint\.x|daemon))$/' "$G" | wc -l | tr -d ' ')"
t_eq "a later commit that changed only another row does not motivate this one" 0 "$(row motivated-by control:lint.x issue:harbor#22)"
t_eq "...and does motivate the row it changed" 1 "$(row motivated-by control:lint.ghost issue:harbor#22)"
t_eq "a decision record's own citation" 1 "$(row motivated-by decision:D-1 issue:harbor#7)"
t_has "the relation row counts the commits read, and the census left out" "$GRAPH" "the 2 commits that changed controls.tsv, not the 1 that created it"

t_section "refs answers by a control id, bare or prefixed"
t_has "refs control:lint.x" "$(gen --refs control:lint.x 2>/dev/null)" "owned-by${TAB}control:lint.x${TAB}family:lint"
t_has "refs lint.x" "$(gen --refs lint.x 2>/dev/null)" "red-proof${TAB}control:lint.x"

t_section "a source that is absent derives nothing, and says so by its missing # relation row"
git -C "$HB" rm -q docs/reference/checks.md
gen >/dev/null 2>&1
t_eq "no docs/reference/checks.md: no registered-in row" 0 "$(grep -c "^# relation${TAB}registered-in" "$G" || :)"
t_eq "...and no registered-in edge" 0 "$(grep -c '^registered-in' "$G" || :)"

t_section "same input, same bytes"
gen --stdout 2>/dev/null > "$T_TMP/g1"; gen --stdout 2>/dev/null > "$T_TMP/g2"
t_eq "two builds are byte-identical" same "$(cmp -s "$T_TMP/g1" "$T_TMP/g2" && echo same || echo differ)"
t_done
