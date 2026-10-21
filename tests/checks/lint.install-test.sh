#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: what ships to a box — X7's install reachability (#313), X1's
# sandbox floor (#517), X2/X2b's stale side and never-deployed command (#384), X9's register
# schedule and X10's retired plugin tier. X7 runs a COPIED bin/, linted once unmutated (#531, #667).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

t_section "X7: every script an installed script invokes is in a payload"
X7R="$TMP/x7repo"; mkdir -p "$X7R/bin"
cp "$ROOT"/bin/*.sh "$X7R/bin/" 2>/dev/null; cp "$ROOT"/bin/*.awk "$X7R/bin/" 2>/dev/null
_x7lines() { sh "$X7R/bin/lint-conventions.sh" --only X7 2>&1 | grep 'ADVISORY \[drift.payload-closure\]' || true; }
_X7_PRISTINE="$(_x7lines)"
t_hasnt "silent about a call whose target IS shipped" "$_X7_PRISTINE" 'fleet-sessions.sh'
# Keyed on the FILES line and one name: fleet-sessions.sh is also in the header prose above the list.
sed -i.bak '/^FILES=/s/ fleet-sessions\.sh//' "$X7R/bin/runtime-install.sh"
t_hasnt "the fixture really dropped fleet-sessions.sh from the payload" "$(grep '^FILES=' "$X7R/bin/runtime-install.sh")" 'fleet-sessions.sh'
t_has "red when an invoked script is in no payload (the 2026-08-02 defect)" "$(_x7lines)" 'invokes $DIR/fleet-sessions.sh'
mv "$X7R/bin/runtime-install.sh.bak" "$X7R/bin/runtime-install.sh"
X7E="$TMP/x7empty"; mkdir -p "$X7E/bin"; cp "$LINT" "$X7E/bin/"
t_has "no readable payload at all is said out loud" "$(sh "$X7E/bin/lint-conventions.sh" --only X7 2>&1)" \
  'drift.payload-closure] could not read the installer payloads'

t_section "X7: \$SRC is followed where it means the config dir (harbor#313)"
t_hasnt "\$SRC/floor-install.sh is silent while runtime-install.sh ships it" "$_X7_PRISTINE" 'invokes $SRC/floor-install.sh'
sed -i.bak '/^FILES=/s/ floor-install\.sh//' "$X7R/bin/runtime-install.sh"
t_eq "the fixture really dropped floor-install.sh" no "$(hasre "$(grep '^FILES=' "$X7R/bin/runtime-install.sh")" '[^-]floor-install\.sh')"
t_has "…and then sandbox-make.sh's \$SRC/floor-install.sh call is reported" "$(_x7lines)" 'invokes $SRC/floor-install.sh'
mv "$X7R/bin/runtime-install.sh.bak" "$X7R/bin/runtime-install.sh"

t_section "X7: \$SRC_DIR is followed too, which is how status-obligations.sh stayed unshipped (harbor#1115)"
t_hasnt "\$SRC_DIR/status-obligations.sh is silent while runtime-install.sh ships it" "$_X7_PRISTINE" 'status-obligations.sh'
sed -i.bak '/^FILES=/s/ status-obligations\.sh//' "$X7R/bin/runtime-install.sh"
t_hasnt "the fixture really dropped status-obligations.sh" "$(grep '^FILES=' "$X7R/bin/runtime-install.sh")" 'status-obligations.sh'
t_has "…and then fleet-snapshot-refresh.sh's \$SRC_DIR call is reported" "$(_x7lines)" 'invokes $SRC_DIR/status-obligations.sh'
mv "$X7R/bin/runtime-install.sh.bak" "$X7R/bin/runtime-install.sh"
printf '\nsh "$SRC_DIR/x7-planted-srcdir.sh" || true\n' >> "$X7R/bin/fleet-snapshot-refresh.sh"
t_has "a planted \$SRC_DIR call to an unshipped script is reported" "$(_x7lines)" 'invokes $SRC_DIR/x7-planted-srcdir.sh'
# RED: without the widened pattern (the old rule) the same plant is invisible, so the two lines above test the change.
cp "$X7R/bin/lint-conventions.sh" "$X7R/bin/lint-conventions.sh.new"
grep -v '_x7_src_is_own_dir "\$_t" SRC_DIR' "$X7R/bin/lint-conventions.sh.new" > "$X7R/bin/lint-conventions.sh"
t_eq "the fixture really removed the \$SRC_DIR arm" 1 "$(diff "$X7R/bin/lint-conventions.sh.new" "$X7R/bin/lint-conventions.sh" | grep -c '^<')"
t_hasnt "with the arm removed the planted call goes unseen (the old rule's blind spot)" "$(_x7lines)" 'x7-planted-srcdir.sh'
mv "$X7R/bin/lint-conventions.sh.new" "$X7R/bin/lint-conventions.sh"
cp "$ROOT/bin/fleet-snapshot-refresh.sh" "$X7R/bin/fleet-snapshot-refresh.sh"

t_section "X7: the exemption is being a READ, never being guarded"
t_hasnt "floor-install.sh only READS runtime-install.sh with sed" "$_X7_PRISTINE" 'invokes $SRC/runtime-install.sh'
t_has "an EXECUTED call to an unshipped script is reported though existence-tested" "$_X7_PRISTINE" 'invokes $SRC/pass-score.sh'
sed -i.bak2 's|^_stamp_tool="$SRC/install-stamp.sh"$|_stamp_tool="$SRC/install-stamp.sh"\nsh "$SRC/x7-planted-executed.sh" --check "$DIR" x7 \|\| _stamp_rc=$?|' "$X7R/bin/floor-install.sh"
t_has "the planted executed call applied" "$(cat "$X7R/bin/floor-install.sh")" 'x7-planted-executed.sh'
t_has "the read exemption is keyed on the reference, not the file" "$(_x7lines)" 'invokes $SRC/x7-planted-executed.sh'
mv "$X7R/bin/floor-install.sh.bak2" "$X7R/bin/floor-install.sh"
sed -i.bak3 's|^_stamp_tool="$SRC/install-stamp.sh"$|_stamp_tool="$SRC/install-stamp.sh"\nsh "$DIR/core.sh" x7 \|\| _stamp_rc=$?|' "$X7R/bin/floor-install.sh"
t_has "\$DIR/core.sh is still reported: SUITE ships core.sh to lib/, never bin/ (harbor#753)" "$(_x7lines)" 'invokes $DIR/core.sh'
mv "$X7R/bin/floor-install.sh.bak3" "$X7R/bin/floor-install.sh"

t_section "X7: an installed SUITE's \$B/ calls are read too (harbor#756)"
mkdir -p "$X7R/tests/floor" "$X7R/tests/lib"
cp "$ROOT/tests/floor/recover-test.sh" "$X7R/tests/floor/"; cp "$ROOT/tests/lib/core.sh" "$X7R/tests/lib/"
t_hasnt "the shipped recover-test.sh is silent: every \$B/ script it calls is shipped" "$(_x7lines)" 'recover-test.sh'
printf '#!/usr/bin/env sh\nB="$T_ROOT/bin"\n# sh "$B/x7-commented.sh" is prose\nsh "$B/not-shipped.sh" --x\n' > "$X7R/tests/floor/x7-planted-test.sh"
sed -i.bak4 '/^SUITE=/s|"$| tests/floor/x7-planted-test.sh:bin/x7-planted-test.sh"|' "$X7R/bin/runtime-install.sh"
t_has "the planted SUITE pair applied" "$(grep '^SUITE=' "$X7R/bin/runtime-install.sh")" 'tests/floor/x7-planted-test.sh:bin/x7-planted-test.sh"'
_x7p="$(_x7lines)"
t_has "a planted SUITE file calling \$B/not-shipped.sh is reported" "$_x7p" 'invokes $B/not-shipped.sh'
t_has "…naming the SUITE file and where it is installed" "$_x7p" 'SUITE tests/floor/x7-planted-test.sh (installed as bin/x7-planted-test.sh) invokes'
t_hasnt "…and not the call that is only a comment" "$_x7p" 'x7-commented.sh'
mv "$X7R/bin/runtime-install.sh.bak4" "$X7R/bin/runtime-install.sh"
sed -i.bak '/^FILES=/s/ sandbox-make\.sh//' "$X7R/bin/runtime-install.sh"
t_hasnt "the fixture really dropped sandbox-make.sh from the payload" "$(grep '^FILES=' "$X7R/bin/runtime-install.sh")" 'sandbox-make.sh'
t_has "the real recover-test.sh's \$B/sandbox-make.sh is then reported" "$(_x7lines)" \
  'SUITE tests/floor/recover-test.sh (installed as bin/recover-test.sh) invokes $B/sandbox-make.sh'
mv "$X7R/bin/runtime-install.sh.bak" "$X7R/bin/runtime-install.sh"
rm -f "$X7R/tests/floor/recover-test.sh"
t_has "a SUITE source this checkout lacks is said out loud, never read as clean" "$(_x7lines)" \
  'SUITE tests/floor/recover-test.sh is not in this checkout'

t_section "X1: the dev sandbox's guards are byte-identical to bin/ (harbor#517)"
X1R="$TMP/x1root"; X1S="$TMP/x1sbx"; mkdir -p "$X1R/bin" "$X1R/skills" "$X1S/bin"
for _x1b in guard-alpha.sh guard-beta.sh annotate-web.sh floor-hook.sh pin-instructions.sh; do
  printf '#!/usr/bin/env sh\n# x1 fixture (harbor#517)\nprintf "%%s\\n" %s\n' "$_x1b" > "$X1R/bin/$_x1b"
  cp "$X1R/bin/$_x1b" "$X1S/bin/$_x1b"
done
printf '# x1 fixture (harbor#517)\n{ print }\n' > "$X1R/bin/floor-normalize.awk"
cp "$X1R/bin/floor-normalize.awk" "$X1S/bin/floor-normalize.awk"
x1() { HELM_SANDBOX_DIR="${1:-$X1S}" lint1 X1 "$X1R" | grep -E '\[drift.sandbox-copy\]'; }
t_eq "a complete sandbox is silent (the control first)" "" "$(x1)"
rm -f "$X1S/bin/guard-beta.sh"
t_has "a sandbox MISSING a guard is reported" "$(x1)" 'sandbox is missing guard-beta.sh'
cp "$X1R/bin/guard-beta.sh" "$X1S/bin/guard-beta.sh"
printf '#!/usr/bin/env sh\n# drifted\nprintf "%%s\\n" tampered\n' > "$X1S/bin/guard-alpha.sh"
t_has "a sandbox copy that DRIFTED from bin/ is reported" "$(x1)" 'sandbox copy is stale: guard-alpha.sh'
cp "$X1R/bin/guard-alpha.sh" "$X1S/bin/guard-alpha.sh"
printf '#!/usr/bin/env sh\n# x1 fixture (harbor#517)\nprintf "%%s\\n" gamma\n' > "$X1R/bin/guard-gamma.sh"
t_has "a guard added to bin/ is DEMANDED in the sandbox (the derivation)" "$(x1)" 'sandbox is missing guard-gamma.sh'
rm -f "$X1R/bin/guard-gamma.sh"
mkdir -p "$X1S-empty/bin"; printf '#!/usr/bin/env sh\nprintf x\n' > "$X1S-empty/bin/not-a-guard.sh"
_x1e="$(x1 "$X1S-empty")"
t_hasnt "an EXISTING but guard-less sandbox is not called absent" "$_x1e" 'no dev sandbox'
t_has "…it is a VIOLATION: it tests no floor at all" "$_x1e" 'VIOLATION [drift.sandbox-copy] sandbox is missing guard-alpha.sh'
_x1n="$(x1 "$TMP/x1-does-not-exist")"
t_hasnt "NO sandbox is never a violation" "$_x1n" 'VIOLATION [drift.sandbox-copy]'
t_has "…and says it verified nothing rather than going silent" "$_x1n" 'verified NOTHING'
t_has "the absent-sandbox advisory is the no-dev-sandbox wording" "$_x1n" 'no dev sandbox'

t_section "X2: which side is stale (harbor#384)"
X24R="$TMP/x2root"; X24L="$TMP/x2live"; X24B="$TMP/x2localbin"; X24C="$TMP/x2cfg"
mkdir -p "$X24R/bin" "$X24L/bin" "$X24B" "$X24C"
printf 'repo\n' > "$X24R/bin/shipped.sh"; printf 'live\n' > "$X24L/bin/shipped.sh"
printf 'repo\n' > "$X24R/bin/unowned.sh"; printf 'live\n' > "$X24L/bin/unowned.sh"
printf '#!/bin/sh\necho one\n' > "$X24R/bin/one.sh"
printf 'FILES="shipped.sh"\n' > "$X24R/bin/runtime-install.sh"
mkdir -p "$X24R/CONTRACTS"; printf 'name\troot\trel\none\tHARBOR_REPO\tbin/one.sh\n' > "$X24R/CONTRACTS/shims.tsv"  # harbor#708: the links' owner
printf 'FILES=""\n' > "$X24R/bin/floor-install.sh"
printf 'STAMP_NAME=".helm-install-stamp"\n' > "$X24R/bin/install-stamp.sh"
x24() { HELM_LIVE_DIR="$X24L" HARBOR_LOCAL_BIN="$X24B" CLAUDE_CONFIG_DIR="$X24C" advs "$1" "$X24R" || true; }
X2_RUN='run the installer'
touch -t 202001010000 "$X24R/bin/shipped.sh"; touch -t 202006010000 "$X24L/bin/shipped.sh"
_o="$(x24 X2)"; _o_sh="$(printf '%s\n' "$_o" | grep 'shipped\.sh')"
t_has "a drifted file an installer ships is reported" "$_o_sh" 'shipped.sh'
t_has "LIVE NEWER names the direction" "$_o_sh" 'LIVE IS NEWER'
t_hasnt "…and never says reinstall over the newer copy" "$_o_sh" "$X2_RUN"
touch -t 202006010000 "$X24R/bin/shipped.sh"; touch -t 202001010000 "$X24L/bin/shipped.sh"
t_eq "REPO NEWER is the one case that advises a reinstall" yes "$(hasre "$(x24 X2)" 'repo is newer.*shipped\.sh')"
t_has "…in the reinstall wording" "$(x24 X2)" "$X2_RUN"
touch -t 202003010000 "$X24R/bin/shipped.sh" "$X24L/bin/shipped.sh"
t_eq "equal timestamps answer UNDECIDABLE" yes "$(hasre "$(x24 X2)" 'UNDECIDABLE.*shipped\.sh')"
t_eq "a file no installer ships is UNOWNED, not stale" yes "$(hasre "$(x24 X2)" 'UNOWNED.*unowned\.sh')"

t_section "X2: each SUITE pair, checkout file against config-dir file (harbor#753)"
# The real installer's SUITE line, so a change to its form turns this red rather than emptying X2's loop.
grep '^SUITE=' "$ROOT/bin/runtime-install.sh" >> "$X24R/bin/runtime-install.sh"
t_has "the fixture carries the installer's lib/core.sh pair" "$(cat "$X24R/bin/runtime-install.sh")" 'tests/lib/core.sh:lib/core.sh'
mkdir -p "$X24R/tests/lib" "$X24L/lib"; printf 'repo\n' > "$X24R/tests/lib/core.sh"; cp "$X24R/tests/lib/core.sh" "$X24L/lib/core.sh"
t_hasnt "an identical installed copy is silent" "$(x24 X2)" '~/.claude/lib/core.sh'
printf 'live\n' > "$X24L/lib/core.sh"; touch -t 202001010000 "$X24R/tests/lib/core.sh"; touch -t 202006010000 "$X24L/lib/core.sh"
t_has "a differing \$LIVE/lib/core.sh is named, LIVE newer" "$(x24 X2)" 'LIVE IS NEWER — this checkout lags the box; capture it, do NOT reinstall over it: ~/.claude/lib/core.sh'
touch -t 202006010000 "$X24R/tests/lib/core.sh"; touch -t 202001010000 "$X24L/lib/core.sh"
t_has "…and repo newer is the reinstall advice" "$(x24 X2)" "repo is newer — the box lags; $X2_RUN that ships it: ~/.claude/lib/core.sh"
touch -t 202003010000 "$X24R/tests/lib/core.sh" "$X24L/lib/core.sh"
t_has "…and equal timestamps are UNDECIDABLE" "$(x24 X2)" 'UNDECIDABLE — read the diff before either copy: ~/.claude/lib/core.sh'

t_section "X2b: a shipped command that was never deployed (harbor#384)"
printf 'runtime-install deadbeef x x\n' > "$X24L/.helm-install-stamp"
X2B_NEVER='NEVER DEPLOYED'
t_has "a one-word command its installer ships and never installed is reported" "$(x24 X2b)" "$X2B_NEVER: ~/.local/bin/one "
rm -f "$X24L/.helm-install-stamp"
t_hasnt "with no install stamp, absence is a choice and stays silent" "[$(x24 X2b)]" "$X2B_NEVER"
ln -sfn "$TMP/gone/bin/one.sh" "$X24B/one"
t_eq "a link into a REMOVED worktree is DANGLING, not absent" yes "$(hasre "$(x24 X2b)" 'DANGLING.*one')"
ln -sfn "$X24R/bin/one.sh" "$X24B/one"
t_hasnt "a link that resolves into the repo is silent" "[$(x24 X2b)]" 'one'

t_section "X9: the register's schedule column decides who owes a plist"
X9R="$TMP/x9"; mkdir -p "$X9R/bin" "$X9R/launchd"; cp "$LINT" "$X9R/bin/"
_x9_head='| id | watches | schedule | notifies | red means |
|---|---|---|---|---|'
reg() { printf '# Register\n\n%s\n%s\n' "$_x9_head" "$1" > "$X9R/CHECKS.md"; }
_x9() { HARBOR_ROOT="$X9R" sh "$X9R/bin/lint-conventions.sh" --only X9 2>&1 | grep -E 'ADVISORY \[drift.launchd-plist\]|registered check\(s\)' || true; }
reg '| `zz-fixture-cron` | a thing | hourly | desktop | it broke |'
t_has "a launchd-scheduled check with no tracked plist is reported" "$(_x9)" 'NO COMMIT: com.harbor.zz-fixture-cron.plist'
reg '| `zz-fixture-manual` | a thing | **not scheduled — run it by hand** | stdout | it broke |'
t_hasnt "\"not scheduled\" owes no plist" "$(_x9)" 'NO COMMIT'
reg '| `zz-fixture-gate` | a seam | **every commit and push — `just lint` in `~/port/zorbcorp`** | exit 1 | it broke |'
t_hasnt "a gate that runs on every commit owes no plist" "$(_x9)" 'NO COMMIT'
reg '| `zz-fixture-inline` | the surface | SessionStart, inline — 0.31s, measured | the verdict line | it broke |'
t_hasnt "an inline SessionStart check owes no plist" "$(_x9)" 'NO COMMIT'
reg '| `zz-fixture-manual` | a thing | hourly | desktop | it broke |'
t_has "DERIVED: change only the schedule cell and the same id goes red" "$(_x9)" 'NO COMMIT: com.harbor.zz-fixture-manual.plist'
printf 'fixture\n' > "$X9R/launchd/com.harbor.zz-fixture-manual.plist"
t_hasnt "a tracked plist clears it" "$(_x9)" 'NO COMMIT'
rm -f "$X9R/launchd/com.harbor.zz-fixture-manual.plist"
reg '| `zz-fixture-broken` | a thing | not scheduled |'
t_has "a malformed row names its shape" "$(_x9)" 'zz-fixture-broken: the row has the wrong column count'
t_has "…and is checked STRICTLY, never skipped" "$(_x9)" 'NO COMMIT: com.harbor.zz-fixture-broken.plist'
reg '| `zz-fixture-cron` | a thing | hourly | desktop | it broke |
| `zz-fixture-manual` | a thing | **not scheduled** | stdout | it broke |'
t_has "the count names the skipped rows" "$(_x9)" '2 registered check(s): 1 not launchd-scheduled, 1 untracked'
printf '# Register\n\nno table here at all\n' > "$X9R/CHECKS.md"
t_has "an unreadable register says so rather than passing" "$(_x9)" 'no registry rows this rule can read'
# finding #890: data tests and CI gates run under another scheduler; a rider owes its HOST's plist
reg '| `zz-fixture-sql` | a table | **every `nightly-build` run — singular test `tests/x.sql`** | sql | it broke |'
t_hasnt "a data singular test owes no plist" "$(_x9)" 'NO COMMIT'
reg '| `zz-fixture-ci` | maps | **every push and every PR — the gate job, part of CI gate** | CI | it broke |'
t_hasnt "a CI gate owes no plist" "$(_x9)" 'NO COMMIT'
reg '| `zz-fixture-cron` | a thing | hourly; falsifier: the singular test in the CI gate job | desktop | it broke |'
t_has "a launchd row whose FALSIFIER names a singular test or CI gate still owes its plist" "$(_x9)" 'NO COMMIT: com.harbor.zz-fixture-cron.plist'
reg "| \`zz-fixture-rider\` | runners | every 300s, inside \`zz-fixture-host\`'s run rather than on a schedule of its own | glyph | it broke |"
t_has "a rider whose host has no plist is reported, never skipped" "$(_x9)" 'zz-fixture-rider runs inside zz-fixture-host, which has no tracked plist'
printf 'fixture\n' > "$X9R/launchd/com.harbor.zz-fixture-host.plist"
t_hasnt "its host's tracked plist clears it" "$(_x9)" 'zz-fixture-rider'
t_has "positive control: the rider was counted as not launchd-scheduled" "$(_x9)" '1 registered check(s): 1 not launchd-scheduled'
rm -f "$X9R/launchd/com.harbor.zz-fixture-host.plist"
# harbor#592: a phrasing X9 cannot read is reported as unreadable, never as an uncommitted plist
reg '| `zz-fixture-moon` | a thing | whenever the moon is full | desktop | it broke |'
t_has "an unrecognised schedule is called unreadable" "$(_x9)" 'its schedule names no launchd time and no non-launchd kind'
t_hasnt "…and is not claimed to owe a plist" "$(_x9)" 'NO COMMIT'
t_has "…and is counted" "$(_x9)" '1 registered check(s): 0 not launchd-scheduled, 0 untracked, 0 drifted from the installed copy, 1 unreadable'
printf 'fixture\n' > "$X9R/launchd/com.harbor.zz-fixture-moon.plist"
t_hasnt "a tracked plist is evidence it is a launchd job" "$(_x9)" 'its schedule names no launchd time and no non-launchd kind'
t_has "…and it is counted as launchd, so its installed copy is still compared (review #933)" "$(_x9)" \
  '1 registered check(s): 0 not launchd-scheduled, 0 untracked, 0 drifted from the installed copy, 0 unreadable'
rm -f "$X9R/launchd/com.harbor.zz-fixture-moon.plist"
for _x9s in 'every 900s' '08:47 daily' 'weekly, Mondays' '**09:23 daily, launchd `com.harbor.x`**' '10:15' 'via launchd'; do
  reg "| \`zz-fixture-cron\` | a thing | $_x9s | desktop | it broke |"
  t_has "a launchd time ($_x9s) still owes its plist" "$(_x9)" 'NO COMMIT: com.harbor.zz-fixture-cron.plist'
done

t_section "X9: the installed copy is compared with what the tracked template RENDERS to (harbor#630)"
mkdir -p "$X9R/CONTRACTS" "$HOME/Library/LaunchAgents"
cp "$ROOT/bin/launchd-render.sh" "$ROOT/bin/roots.sh" "$ROOT/bin/log-lib.sh" "$X9R/bin/"; cp "$ROOT/CONTRACTS/roots.tsv" "$X9R/CONTRACTS/"
reg '| `zz-fixture-cron` | a thing | hourly | desktop | it broke |'
X9T="$X9R/launchd/com.harbor.zz-fixture-cron.plist"; X9I="$HOME/Library/LaunchAgents/com.harbor.zz-fixture-cron.plist"
printf '<string>@HOME@/.claude/bin/zz.sh</string>\n<key>PATH</key><string>@HARBOR_LOCAL_BIN@</string>\n' > "$X9T"
sh "$X9R/bin/launchd-render.sh" "$X9T" > "$X9I"
t_hasnt "the install made from the template is in sync (a raw cmp would call it drift)" "$(_x9)" 'installed copy differs'
t_has "…and the count says so" "$(_x9)" '1 registered check(s): 0 not launchd-scheduled, 0 untracked, 0 drifted from the installed copy'
cp "$X9T" "$X9I"
t_has "a template cp'd in whole, its placeholders installed as text, is drift" "$(_x9)" 'installed copy differs from what the repo renders to: com.harbor.zz-fixture-cron.plist'
sh "$X9R/bin/launchd-render.sh" "$X9T" > "$X9I"; printf '<!-- edited on the box -->\n' >> "$X9I"
t_has "an installed copy edited after the render is drift" "$(_x9)" 'installed copy differs from what the repo renders to'
t_has "…and the count says 1 drifted" "$(_x9)" '0 untracked, 1 drifted from the installed copy'
printf '<string>@NOT_A_ROOT@</string>\n' > "$X9T"; cp "$X9T" "$X9I"
t_hasnt "a template that does not render is compared as it stands (identical to the installed file: no drift)" "$(_x9)" 'installed copy differs'
printf 'other\n' > "$X9I"
t_has "…and differing from it, drift" "$(_x9)" 'installed copy differs'
rm -f "$X9T" "$X9I"

t_section "X9: the REAL register is fully readable (harbor#1110)"
_x9real="$(HARBOR_ROOT="$ROOT" sh "$LINT" --only X9 2>&1 | grep -E 'ADVISORY \[drift.launchd-plist\]|registered check\(s\)' || true)"
t_hasnt "no row of CHECKS.md has a column count X9 cannot read (a literal pipe in a cell)" "$_x9real" 'wrong column count'
t_hasnt "no row of CHECKS.md names no schedule kind" "$_x9real" 'names no launchd time'
t_hasnt "no row of CHECKS.md owes a plist that is in no commit" "$_x9real" 'NO COMMIT'
t_has "…and the totals say so" "$_x9real" ', 0 untracked,'

t_section "X11: the hand-installed work-log pre-push against worklog/pre-push (harbor#511)"
X11R="$TMP/x11"; mkdir -p "$X11R/bin" "$X11R/worklog" "$X11R/cfg/MEMORY/.git/hooks"; cp "$LINT" "$X11R/bin/"
printf '#!/bin/sh\necho tracked\n' > "$X11R/worklog/pre-push"
_x11() { CLAUDE_CONFIG_DIR="$X11R/cfg" HARBOR_ROOT="$X11R" sh "$X11R/bin/lint-conventions.sh" --only X11 2>&1 | grep -E 'drift\.work-log-hook\]|work-log pre-push' || true; }
t_has "no hook installed is reported" "$(_x11)" "the work-log repository has no pre-push hook"
printf '#!/bin/sh\necho old\n' > "$X11R/cfg/MEMORY/.git/hooks/pre-push"
t_has "a differing installed copy is reported" "$(_x11)" "the installed work-log pre-push differs from worklog/pre-push"
cp "$X11R/worklog/pre-push" "$X11R/cfg/MEMORY/.git/hooks/pre-push"
t_has "the copy is silent, and says what it compared" "$(_x11)" "the installed copy matches worklog/pre-push"
t_hasnt "…with no advisory" "$(_x11)" "the installed work-log pre-push differs from worklog/pre-push"
printf ' ' >> "$X11R/worklog/pre-push"
t_has "one byte changed in the tracked file fires again" "$(_x11)" "the installed work-log pre-push differs from worklog/pre-push"
# review #942: git decides where the hook lives, so core.hooksPath and a gitdir file are honoured
rm -rf "$X11R/cfg/MEMORY"; mkdir -p "$X11R/cfg/MEMORY"; git init -q "$X11R/cfg/MEMORY"
git -C "$X11R/cfg/MEMORY" config core.hooksPath githooks; mkdir -p "$X11R/cfg/MEMORY/githooks"
cp "$X11R/worklog/pre-push" "$X11R/cfg/MEMORY/githooks/pre-push"
t_has "a hook under core.hooksPath is the one compared" "$(_x11)" "the installed copy matches worklog/pre-push"
rm -rf "$X11R/cfg/MEMORY"; mkdir -p "$X11R/cfg/real.git/hooks" "$X11R/cfg/MEMORY"; git init -q --bare "$X11R/cfg/real.git"
printf 'gitdir: %s\n' "$X11R/cfg/real.git" > "$X11R/cfg/MEMORY/.git"
cp "$X11R/worklog/pre-push" "$X11R/cfg/real.git/hooks/pre-push"
t_has "a .git FILE points at the hooks git runs" "$(_x11)" "the installed copy matches worklog/pre-push"
rm -rf "$X11R/cfg/MEMORY/.git"
t_has "a box with no work-log repository says so" "$(_x11)" "no work-log repository at"
t_hasnt "…and raises nothing" "$(_x11)" "ADVISORY [drift.work-log-hook]"

t_section "X10: the authored-plugin tier stays retired"
X10R="$TMP/x10root"; mkdir -p "$X10R/bin" "$X10R/skills"; cp "$LINT" "$X10R/bin/"
x10() { CLAUDE_CONFIG_DIR="$X10R" viol X10 "$X10R"; }
t_eq "a tree with no plugin tier is green (the control)" "" "$(x10)"
mkdir -p "$X10R/plugins/anything"
t_has "a returning plugins/ tree goes red" "$(x10)" 'plugins/ is back'
rm -rf "$X10R/plugins"
mkdir -p "$X10R/.claude-plugin"; printf '{}\n' > "$X10R/.claude-plugin/marketplace.json"
t_has "a returning marketplace.json goes red on its own" "$(x10)" 'marketplace.json is back'
rm -rf "$X10R/.claude-plugin"
mkdir -p "$X10R/skills/withmanifest/.claude-plugin"
printf '{"name":"withmanifest"}\n' > "$X10R/skills/withmanifest/.claude-plugin/plugin.json"
t_eq "a plugin manifest inside a skill directory is sanctioned" "" "$(x10)"

t_done
