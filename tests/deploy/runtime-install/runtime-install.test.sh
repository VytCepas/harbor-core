#!/usr/bin/env sh
# deploy-runtime-install.sh (harbor#59): the restore-path suite ships with its harness, the suite payload
# manifest reads tests/admission/baseline/, and — harbor#708 — the four one-word commands have exactly one owner,
# contracts/shims.tsv through shim-install, so runtime-install writes nothing in ~/.local/bin.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY  # a run inside a session or a deploy must not decide a case
TOOL="$T_ROOT/bin/deploy-runtime-install.sh"; SRCB="$T_ROOT/bin"; T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
ri() { env -u CLAUDE_CONFIG_DIR sh "$TOOL" "$@"; }  # t_init's CLAUDE_CONFIG_DIR is not these targets

t_section "the re-pin after writing settings.json reaches floor-deny through --dir (harbor#800)"
# Asserted by the pin's CONTENT, as prod-guard-test does: a printed "re-pinned" over a stale pin is the bug.
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
RPD="$T/repin"; mkdir -p "$RPD"; printf '{"permissions":{"deny":[]}}\n' > "$RPD/settings.json"; printf 'stale-teeth\n' > "$RPD/.helm-floor-teeth"
_rpo="$(ri --dir "$RPD" --apply 2>&1)"
t_eq "the teeth pin matches the settings.json it wrote" \
  "$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$RPD/settings.json" | sha)" \
  "$(cat "$RPD/.helm-floor-teeth" 2>/dev/null || echo MISSING)"
t_has "...and says so" "$_rpo" "  ok: re-pinned: teeth + sec0 baseline now match the settings.json just written"

t_section "harbor#708: contracts/shims.tsv alone owns idea, memory, gcx and gcloud"
H="$T/home"; mkdir -p "$H/.claude"; printf '{}' > "$H/.claude/settings.json"
env -u CLAUDE_CONFIG_DIR HOME="$H" sh "$TOOL" --live --apply >/dev/null 2>&1
t_eq "a LIVE runtime-install --apply (sandbox HOME) ran" yes "$([ -f "$H/.claude/bin/library-admission.sh" ] && echo yes || echo no)"
t_eq "...and created no ~/.local/bin" no "$([ -e "$H/.local/bin" ] && echo yes || echo no)"
env -u CLAUDE_CONFIG_DIR HOME="$H" HARBOR_SCOPE_LOCAL_BIN="$H/lbin" sh "$TOOL" --live --apply >/dev/null 2>&1
t_eq "...not even with HARBOR_SCOPE_LOCAL_BIN pointing somewhere" no "$([ -e "$H/lbin" ] && echo yes || echo no)"
t_has "the plan says who owns them instead" "$(env -u CLAUDE_CONFIG_DIR HOME="$H" sh "$TOOL" --live 2>&1)" \
  'one-word commands (idea, memory, gcx, gcloud): contracts/shims.tsv owns them'
_code() { sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$1"; }
t_eq "runtime-install has no link-making code left" 0 "$(_code "$TOOL" | grep -c 'ln -s')"
_owners=""
for f in "$T_ROOT"/bin/*install*.sh; do [ -L "$f" ] && continue; _code "$f" | grep -q 'ln -s' && _owners="$_owners ${f#"$T_ROOT"/}"; done
t_eq "exactly one installer makes links in bin/: shim-install" " bin/deploy-shim-install.sh" "$_owners"
# gcx left core for the measurement pack, which links it through shims.d (harbor#1149)
for n in idea memory gcloud; do
  t_eq "shims.tsv has exactly one row for $n" 1 "$(sed 's/#.*//' "$T_ROOT/contracts/shims.tsv" | awk -F'\t' -v n="$n" '$1 == n' | wc -l | tr -d ' ')"
done
LB="$T/lb"; mkdir -p "$LB"
HARBOR_SCOPE_REPO="$T_ROOT" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-shim-install.sh" --apply --dir "$LB" >/dev/null 2>&1
for n in idea memory gcloud; do
  _rel="$(sed 's/#.*//' "$T_ROOT/contracts/shims.tsv" | awk -F'\t' -v n="$n" '$1 == n { print $3 }')"
  t_eq "the $n link points into the checkout, at shims.tsv's path" "$T_ROOT/$_rel" "$(readlink "$LB/$n" 2>/dev/null)"
  t_eq "...and resolves to a file" yes "$([ -f "$LB/$n" ] && echo yes || echo no)"
done

t_section "the restore-path suite ships with its harness and runs with no checkout (harbor#727)"
RC="$T/rcfg"; mkdir -p "$RC/bin"; printf '{}' > "$RC/settings.json"; printf 'stale\n' > "$RC/bin/recover-test.sh"
t_has "the dry run names the stale copy as replaced" "$(ri --dir "$RC" 2>&1)" "  note: bin/recover-test.sh (replace)"
ri --apply --dir "$RC" >/dev/null 2>&1
t_exit "apply replaces bin/recover-test.sh with tests/deploy/restore/recover.test.sh" 0 cmp -s "$T_ROOT/tests/deploy/restore/recover.test.sh" "$RC/bin/recover-test.sh"
t_exit "the harness it sources lands at lib/core.sh" 0 cmp -s "$T_ROOT/tests/lib/core.sh" "$RC/lib/core.sh"
t_eq "the installed suite is executable" yes "$([ -x "$RC/bin/recover-test.sh" ] && echo yes)"
t_eq "the libraries every installed tool sources ship too (harbor#771, #765)" "yes yes" \
  "$(for l in library-log.sh deploy-install-lib.sh; do cmp -s "$T_ROOT/bin/$l" "$RC/bin/$l" && printf 'yes ' || printf 'no '; done | sed 's/ $//')"
t_eq "the stale copy it replaced is in this run's backup" stale "$(cat "$RC"/backups/runtime-install/*/bin/recover-test.sh 2>/dev/null)"
out="$(cd / && sh "$RC/bin/recover-test.sh" 2>&1)"; rc=$?
t_eq "the installed suite runs green from / with no checkout above it" 0 "$rc"
t_eq "...and prints a whole run's summary" 1 "$(printf '%s\n' "$out" | grep -c '^recover-test: [0-9]* passed, 0 failed$')"
printf '#!/bin/sh\nexit 0\n' > "$RC/bin/deploy-restore.sh"  # it must test the INSTALLED scripts, not a checkout's
t_exit "a broken installed deploy-restore.sh turns the installed suite red" 1 sh "$RC/bin/recover-test.sh"

t_section "the suite payload manifest reads the floor suite in tests/admission/baseline/ (harbor#727)"
MAN="$(cat "$RC/bin/.helm-suite-payloads" 2>/dev/null)"
first_payload() { sed -n "s/.*bash_j '\([^']*\)'.*/\1/p" "$1" | head -1; }  # <suite file>
t_has "it carries the fixture's payloads" "${MAN:-none}" "C$(first_payload "$T_ROOT/tests/admission/baseline/fixture.sh")"
t_has "…and a part's, not only the main part's" "${MAN:-none}" "C$(first_payload "$T_ROOT/tests/admission/baseline/ledger.test.sh")"

t_section "the install standard's interface (harbor#765): target, dry-run rule, log, backups"
IF="$T/iface"; mkdir -p "$IF"; printf '{"a":1}\n' > "$IF/settings.json"
t_exit "a positional target is a usage error" 2 ri "$IF"
t_exit "an unknown flag is a usage error" 2 ri --dir "$IF" --bogus
t_exit "the retired --allow-regression is an unknown flag now (--accept-loss replaced it)" 2 ri --dir "$IF" --allow-regression
t_exit "CLAUDE_CONFIG_DIR that is not the target exits 2" 2 env CLAUDE_CONFIG_DIR="$T/elsewhere" sh "$TOOL" --dir "$IF"
t_exit "--dir onto the live dir is refused without --live" 1 env -u CLAUDE_CONFIG_DIR HOME="$H" sh "$TOOL" --apply --dir "$H/.claude/"
t_eq "a dry run writes nothing" '{"a":1}' "$(jq -c . "$IF/settings.json")"
t_eq "...and leaves no backups dir" no "$([ -e "$IF/backups" ] && echo yes || echo no)"
_io="$(ri --apply --dir "$IF" 2>&1)"
t_eq "an apply writes its log at backups/runtime-install/<TS>/log, and names it last" yes \
  "$(_lp="$(printf '%s\n' "$_io" | tail -1 | sed -n 's/^log: //p')"; [ -n "$_lp" ] && [ -f "$_lp" ] && case "$_lp" in ("$IF"/backups/runtime-install/*/log) echo yes ;; (*) echo "no: $_lp" ;; esac)"
t_eq "...the pre-run settings.json beside it" '{"a":1}' "$(jq -c . "$IF"/backups/runtime-install/*/settings.json 2>/dev/null)"
t_eq "...and no old-style backups/settings.json.runtime-install-* file" 0 "$(find "$IF/backups" -maxdepth 1 -name 'settings.json.*' | wc -l | tr -d ' ')"
t_has "the summary line agrees with the exit code" "$(printf '%s\n' "$_io" | tail -2 | head -1)" 'runtime-install: '
t_hasnt "...and no line uses a status glyph the log format bans" "$_io" '•'
# The dry-run exit rule: a regression refuses the apply, so the dry run exits 1 and says why.
RG="$T/regress"; mkdir -p "$RG"; printf '{}\n' > "$RG/settings.json"
printf 'runtime-install ffffffffffffffffffffffffffffffffffffffff 2026-01-01T00:00:00Z x\n' > "$RG/.helm-install-stamp"
_rgo="$(ri --dir "$RG" 2>&1)"; _rgc=$?
t_eq "a stamp this checkout cannot place is not a regression verdict (install-stamp warns, proceeds)" 0 "$_rgc"

t_section "harbor#285: a pin floor-install re-pins is a note; any other keeps the banner"
# copy_data <copy root>: every DATA source deploy-runtime-install.sh names, so a copied checkout is not a half install
# (harbor#1115; harbor#1044 added docs/reference/checks.md and event-rules.tsv). Derived from the line, never a second list.
copy_data() {
  for _dp in $(sed -n 's/^DATA="\(.*\)"$/\1/p' "$T_ROOT/bin/deploy-runtime-install.sh"); do
    mkdir -p "$1/$(dirname "${_dp%%:*}")"; cp "$T_ROOT/${_dp%%:*}" "$1/${_dp%%:*}"
  done
}
# The hook engines' folders (D-88): their bytes and manifests are payload too, so a copied checkout carries them.
copy_hooks() { cp -R "$T_ROOT/hooks" "$1/"; }
P2="$T/p285"; mkdir -p "$P2/.helm-pins"; printf '{}\n' > "$P2/settings.json"
printf 'stale\n' > "$P2/.helm-pins/library-admission.sh.sha256"
_o285="$(ri --apply --dir "$P2" 2>&1)"
t_hasnt "a pin in floor-install's payload claims no lockout" "$_o285" 'will be BLOCKED'
t_has "...and names floor-install as the remedy" "$_o285" "floor-install re-pins them: sh $SRCB/admission-install.sh"
printf 'stale\n' > "$P2/.helm-pins/library-admission.sh.sha256"
_o285d="$(env -u CLAUDE_CONFIG_DIR HARBOR_DEPLOY_ACTIVE=1 sh "$TOOL" --apply --dir "$P2" 2>&1)"
t_hasnt "under deploy it does not: floor-install re-pins a step later" "$_o285d" 'B6 CONTENT PINS ARE NOW STALE'
t_has "...and it says what happens instead" "$_o285d" 'floor-install re-pins them next in this deploy'
P3="$T/p285b"; mkdir -p "$P3/.helm-pins"; printf '{}\n' > "$P3/settings.json"
printf 'stale\n' > "$P3/.helm-pins/alert-probe.sh.sha256"
t_has "a pin floor-install does NOT carry keeps the banner" "$(ri --apply --dir "$P3" 2>&1)" 'B6 CONTENT PINS ARE NOW STALE — the next SessionStart will be BLOCKED'
printf 'stale\n' > "$P3/.helm-pins/alert-probe.sh.sha256"
t_has "...under deploy too: nothing later re-pins it" "$(env -u CLAUDE_CONFIG_DIR HARBOR_DEPLOY_ACTIVE=1 sh "$TOOL" --apply --dir "$P3" 2>&1)" 'will be BLOCKED: this install replaced content-pinned file(s): alert-probe.sh'
# The covered set is read from admission-install.sh: empty its GUARDS and library-admission.sh is banner-worthy again.
CG="$T/cg"; mkdir -p "$CG/bin" "$CG/tests/deploy/restore" "$CG/tests/lib" "$CG/contracts"
# the whole payload (merge-stack's .py too, harbor#1060; DATA via copy_data), or the copy is a refused half install
cp "$T_ROOT"/bin/*.sh "$T_ROOT"/bin/*.awk "$T_ROOT"/bin/*.py "$CG/bin/"; cp "$T_ROOT/tests/deploy/restore/recover.test.sh" "$CG/tests/deploy/restore/"
cp "$T_ROOT/tests/lib/core.sh" "$CG/tests/lib/"; copy_data "$CG"; copy_hooks "$CG"
sed "s/^GUARDS='.*'\$/GUARDS=''/" "$T_ROOT/bin/admission-install.sh" > "$CG/bin/admission-install.sh"
P4="$T/p285c"; mkdir -p "$P4/.helm-pins"; printf '{}\n' > "$P4/settings.json"; printf 'stale\n' > "$P4/.helm-pins/library-admission.sh.sha256"
t_has "mutation: floor-install with no GUARDS brings the banner back" "$(env -u CLAUDE_CONFIG_DIR sh "$CG/bin/deploy-runtime-install.sh" --apply --dir "$P4" 2>&1)" 'will be BLOCKED: this install replaced content-pinned file(s): library-admission.sh'

t_section "the dry-run exit rule over a regression: runtime-install and floor-install refuse in both modes"
# A copied bin/ whose deploy-install-stamp.sh reports a regression, so the installers' own handling is what runs.
CB="$T/copy"; mkdir -p "$CB/bin" "$CB/tests/deploy/restore" "$CB/tests/lib"
cp "$T_ROOT"/bin/*.sh "$T_ROOT"/bin/*.awk "$T_ROOT"/bin/*.py "$CB/bin/"
cp "$T_ROOT/tests/deploy/restore/recover.test.sh" "$CB/tests/deploy/restore/"; cp "$T_ROOT/tests/lib/core.sh" "$CB/tests/lib/"
copy_data "$CB"; copy_hooks "$CB"
printf '#!/bin/sh\n[ "$1" = --check ] || exit 0\nprintf "  FAIL: %%s would remove 2 installed commit(s) from %%s\\n  fix: x\\n  note: abc1234 a commit only the box has\\n" "$3" "$2"\nexit 1\n' > "$CB/bin/deploy-install-stamp.sh"
for tool in runtime-install floor-install; do
  RD="$T/rg-$tool"; mkdir -p "$RD"; printf '{"permissions":{"deny":[]}}\n' > "$RD/settings.json"
  cp "$RD/settings.json" "$T/rg-$tool.before"
  _o="$(env -u CLAUDE_CONFIG_DIR sh "$CB/bin/$tool.sh" --dir "$RD" 2>&1)"; _c=$?
  t_eq "$tool: its dry run over a regression exits 1" 1 "$_c"
  t_has "...saying what --apply would refuse" "$_o" '  FAIL: --apply would refuse: '
  t_has "...naming the loss from install-stamp" "$_o" 'would remove 2 installed commit(s)'
  t_has "...then the fix with --accept-loss" "$_o" "  fix: sh $CB/bin/$tool.sh --apply --dir '$RD' --accept-loss"
  t_has "...relaying the commits it would remove" "$_o" '  note: abc1234 a commit only the box has'
  _o="$(env -u CLAUDE_CONFIG_DIR sh "$CB/bin/$tool.sh" --apply --dir "$RD" 2>&1)"; _c=$?
  t_eq "$tool: its apply refuses, exit 1" 1 "$_c"
  t_eq "...and writes nothing" same "$(cmp -s "$RD/settings.json" "$T/rg-$tool.before" && echo same || echo changed)"
  _o="$(env -u CLAUDE_CONFIG_DIR sh "$CB/bin/$tool.sh" --apply --dir "$RD" --accept-loss 2>&1)"; _c=$?
  t_eq "$tool: --accept-loss proceeds" 0 "$_c"
  t_has "...with a WARN naming exactly what is lost" "$_o" '  WARN: --accept-loss: '
  t_has "...and the loss in it" "$_o" 'would remove 2 installed commit(s)'
done
t_section "a script's data file ships beside bin/, and a checkout without it is refused (harbor#1115)"
DR="$T/data"; mkdir -p "$DR"; printf '{}' > "$DR/settings.json"
# No private layer here: the installed rows are core's alone (the composed case is tests/ci/required-checks/compose.test.sh, harbor#1149)
env -u CLAUDE_CONFIG_DIR HARBOR_SCOPE_PRIVATE="$T/no-layer" sh "$TOOL" --apply --dir "$DR" >/dev/null 2>&1
t_exit "status-obligations.sh reads bin/obligation-kinds.tsv once installed, and the installer puts it there" 0 cmp -s "$T_ROOT/contracts/obligation-kinds.tsv" "$DR/bin/obligation-kinds.tsv"
t_eq "...inside bin/: no new top-level entry for deploy's snapshot set to miss" no "$([ -e "$DR/contracts" ] && echo yes || echo no)"
t_exit "...and the script itself ships" 0 cmp -s "$T_ROOT/bin/status-obligations.sh" "$DR/bin/status-obligations.sh"
t_has "...and the manifest has a row for the data file" "$(cat "$DR/.harbor-manifest" 2>/dev/null)" "bin/obligation-kinds.tsv"
t_eq "merge-stack ships with what it runs from its own dir, and its union list beside it (ship contract 5b.9, harbor#1060)" "yes yes yes yes" \
  "$(for f in gate-merge-stack.sh gate-merge-stack-resolve.py gate-merge-check.sh; do cmp -s "$T_ROOT/bin/$f" "$DR/bin/$f" && printf 'yes ' || printf 'no '; done
     cmp -s "$T_ROOT/contracts/merge-stack-union.txt" "$DR/bin/merge-stack-union.txt" && echo yes || echo no)"
t_exit "...and harbor's required-checks rows, which it unions with a repo's own (r5 #3)" 0 cmp -s "$T_ROOT/contracts/required-checks.tsv" "$DR/bin/required-checks.tsv"
rm -f "$CB/contracts/obligation-kinds.tsv"; DN="$T/nodata"; mkdir -p "$DN"; printf '{}' > "$DN/settings.json"
_o="$(env -u CLAUDE_CONFIG_DIR sh "$CB/bin/deploy-runtime-install.sh" --apply --dir "$DN" 2>&1)"; _c=$?
t_eq "a checkout that lacks the data file is a refused half install" 1 "$_c"
t_has "...naming it" "$_o" "contracts/obligation-kinds.tsv is missing"
t_eq "...and nothing is installed" no "$([ -e "$DN/bin" ] && echo yes || echo no)"
cp "$T_ROOT/contracts/obligation-kinds.tsv" "$CB/contracts/"
rm -f "$CB/bin/gate-required-generate.sh"; DM="$T/nocomposer"; mkdir -p "$DM"; printf '{}' > "$DM/settings.json"
_o="$(env -u CLAUDE_CONFIG_DIR sh "$CB/bin/deploy-runtime-install.sh" --apply --dir "$DM" 2>&1)"; _c=$?
t_eq "a checkout that lacks the required-checks composer is a refused half install (harbor#1149)" 1 "$_c"
t_has "...naming it" "$_o" "gate-required-generate.sh is missing"
t_eq "...and nothing is installed" no "$([ -e "$DM/bin" ] && echo yes || echo no)"
cp "$T_ROOT/bin/gate-required-generate.sh" "$CB/bin/"

t_section "the install manifest (install standard §3): a row per file it wrote, SUITE paths included"
MI="$T/mf"; mkdir -p "$MI/bin"; printf '{}\n' > "$MI/settings.json"
ri --dir "$MI" >/dev/null 2>&1
t_eq "a dry run writes no manifest" no "$([ -e "$MI/.harbor-manifest" ] && echo yes || echo no)"
printf '#!/bin/sh\n# an opted-in B6\n' > "$MI/bin/admission-integrity.sh"
ri --apply --dir "$MI" >/dev/null 2>&1
_h="$(git -C "$T_ROOT" rev-parse HEAD)"
mrow() { grep " $1 " "$MI/.harbor-manifest" 2>/dev/null | awk '{print $1, $2, $4, $5}'; }
t_eq "every FILES entry is a row" "$(sed -n 's/^FILES="\(.*\)"/\1/p' "$TOOL" | wc -w | tr -d ' ')" \
  "$(for f in $(sed -n 's/^FILES="\(.*\)"/\1/p' "$TOOL"); do grep -c " bin/$f runtime-install " "$MI/.harbor-manifest"; done | awk '{ s += $1 } END { print s }')"
t_eq "the suite is recorded where it was installed, bin/recover-test.sh" "$(git hash-object "$MI/bin/recover-test.sh") 100755 runtime-install $_h" "$(mrow bin/recover-test.sh)"
t_eq "...and its harness at lib/core.sh, 100644" "$(git hash-object "$MI/lib/core.sh") 100644 runtime-install $_h" "$(mrow lib/core.sh)"
t_eq "an installed B6 it refreshed is a row" runtime-install "$(mrow bin/admission-integrity.sh | awk '{print $3}')"
t_eq "the generated suite payload file is not a row: no repo file is its source" "" "$(mrow bin/.helm-suite-payloads)"
MN="$T/mf-nob6"; mkdir -p "$MN"; printf '{}\n' > "$MN/settings.json"; ri --apply --dir "$MN" >/dev/null 2>&1
t_eq "a B6 it did not install has no row" 0 "$(grep -c ' bin/admission-integrity.sh ' "$MN/.harbor-manifest")"

t_section "the installed dispatcher follows with the installed bus: the loop guard's cause reaches it (harbor#1044 r2 #3)"
# runtime-install alone must ship a bus that passes HARBOR_EVENT_CAUSE on; the dispatcher refuses (4) beside one that does not.
t_eq "event-bus.sh is installed beside event-dispatch.sh, the repo's bytes" yes \
  "$(cmp -s "$T_ROOT/bin/event-bus.sh" "$MI/bin/event-bus.sh" && echo yes || echo no)"
# env -u CLAUDECODE: the dispatcher refuses to follow inside a Claude session (r3 #1), and this suite may run in one.
_rc=0; env -u CLAUDECODE HARBOR_EVENT_DIR="$T/mf-bus" HARBOR_SCOPE_CACHE_DIR="$T/mf-cache" CLAUDE_CONFIG_DIR="$MI" sh "$MI/bin/event-dispatch.sh" dispatch --once >/dev/null 2>&1 || _rc=$?
t_eq "the installed dispatcher's dispatch --once exits 0 beside it" 0 "$_rc"
t_section "the installed dispatcher judges its presets by the register and presets installed with it (harbor#1044 r3 #5)"
for _f in docs/reference/checks.md event-rules.tsv; do
  t_eq "bin/$_f is installed with a manifest row" 1 "$(grep -c " bin/$_f runtime-install " "$MI/.harbor-manifest")"
done
for _p in event.alerting event.fleet-snapshot; do
  _rc=0; env -u CLAUDECODE HARBOR_EVENT_DIR="$T/mf-bus" HARBOR_SCOPE_CACHE_DIR="$T/mf-cache" CLAUDE_CONFIG_DIR="$MI" HOME="$T/mf-home" \
    sh "$MI/bin/event-dispatch.sh" on --preset "$_p" >/dev/null 2>&1 || _rc=$?
  t_eq "$_p: on --preset exits 0 with no checkout in reach (HOME has no ~/port/harbor)" 0 "$_rc"
done
t_hasnt "...and neither is refused on load" "$(env -u CLAUDECODE HARBOR_EVENT_DIR="$T/mf-bus" CLAUDE_CONFIG_DIR="$MI" HOME="$T/mf-home" sh "$MI/bin/event-dispatch.sh" on --list 2>/dev/null)" "REFUSED"

t_section "the installed ci-runners.sh reads the billing phrase from its installed sibling (harbor#1091)"
# #1091 moved the phrase into ci-lost-job.sh and did not install it: the live tick warned and re-ran nothing.
t_eq "installed ci-lost-job.sh prints the billing pattern" yes \
  "$([ -n "$(sh "$MI/bin/ci-lost-job.sh" --billing-pattern 2>/dev/null)" ] && echo yes || echo no)"
t_section "the installed ci-runners.sh runs from its installed dir: it sources its four sibling libs (harbor#1060 split)"
# a sibling left out of FILES is the #1091 bug again: sourcing fails and every verb dies. list reads the fleet lib, tick the other three.
RX="$T/rx"; mkdir -p "$RX/cache" "$RX/cfg"; printf '[]\n' > "$RX/cache/fleet-snapshot.json"
printf '#!/bin/sh\nexit 1\n' > "$RX/gh"; printf '#!/bin/sh\nexit 0\n' > "$RX/docker"; chmod +x "$RX/gh" "$RX/docker"   # gh answers nothing, docker an empty list
rxrun() { HARBOR_TEST_GH="$RX/gh" HARBOR_CI_DOCKER="$RX/docker" HARBOR_SCOPE_CACHE_DIR="$RX/cache" CLAUDE_CONFIG_DIR="$RX/cfg" HARBOR_CI_EVENTS_DIR="$RX/ev" \
            sh "$MI/bin/ci-runners.sh" "$@" 2>&1; }
t_eq "installed ci-runners list --json answers (fleet lib)" harbor "$(rxrun list --json | jq -r '.[0].repo')"
t_eq "installed ci-runners tick runs to the end (provision, github and watch libs)" 0 "$(rxrun tick >/dev/null; echo $?)"
t_eq "...and wrote its drift cache" yes "$([ -s "$RX/cache/ci-runners.json" ] && echo yes || echo no)"

t_section "harbor#1043: session-state.sh is wired at Stop, once, and its sentinel stops the wiring"
_ssn() { jq -r '[.hooks.Stop[]?.hooks[]?.command // empty | select(contains("session-state.sh"))] | length' "$1/settings.json"; }
SS="$T/ss-on"; mkdir -p "$SS"; printf '{}' > "$SS/settings.json"; ri --apply --dir "$SS" >/dev/null 2>&1; ri --apply --dir "$SS" >/dev/null 2>&1
t_eq "two installs wire exactly one Stop entry" 1 "$(_ssn "$SS")"
t_eq "...and ship the hook, its library and the pattern table" yes "$([ -f "$SS/bin/session-state.sh" ] && [ -f "$SS/bin/session-react-lib.sh" ] && [ -f "$SS/bin/session-waiting.tsv" ] && echo yes || echo no)"
t_eq "...and the banner helper the library and pulse-notify source beside them (harbor#618)" yes "$([ -f "$SS/bin/library-alert.sh" ] && [ -f "$SS/bin/alert-notify.sh" ] && echo yes || echo no)"
SO="$T/ss-off"; mkdir -p "$SO"; printf '{}' > "$SO/settings.json"; : > "$SO/session-state.off"; ri --apply --dir "$SO" >/dev/null 2>&1
t_eq "session-state.off in the config dir: not wired" 0 "$(_ssn "$SO")"

t_section "harbor#1257: session-title.sh is wired at UserPromptSubmit and SessionStart, once, and its sentinel stops the wiring"
_stn() { jq -r --arg e "$2" '[.hooks[$e][]?.hooks[]?.command // empty | select(contains("session-title.sh"))] | length' "$1/settings.json"; }
ST="$T/st-on"; mkdir -p "$ST"; printf '{}' > "$ST/settings.json"; ri --apply --dir "$ST" >/dev/null 2>&1; ri --apply --dir "$ST" >/dev/null 2>&1
t_eq "two installs wire exactly one UserPromptSubmit entry" 1 "$(_stn "$ST" UserPromptSubmit)"
t_eq "...and exactly one SessionStart entry" 1 "$(_stn "$ST" SessionStart)"
t_eq "...and ship the hook" yes "$([ -f "$ST/bin/session-title.sh" ] && echo yes || echo no)"
STO="$T/st-off"; mkdir -p "$STO"; printf '{}' > "$STO/settings.json"; : > "$STO/session-title.off"; ri --apply --dir "$STO" >/dev/null 2>&1
t_eq "session-title.off in the config dir: not wired at UserPromptSubmit" 0 "$(_stn "$STO" UserPromptSubmit)"
t_eq "...nor at SessionStart" 0 "$(_stn "$STO" SessionStart)"

t_section "harbor#1298: access-confinement.sh is wired at PreToolUse(Bash), once, and its sentinel stops the wiring"
_acn() { jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command // empty | select(contains("access-confinement.sh"))] | length' "$1/settings.json"; }
AC="$T/ac-on"; mkdir -p "$AC"; printf '{}' > "$AC/settings.json"; ri --apply --dir "$AC" >/dev/null 2>&1; ri --apply --dir "$AC" >/dev/null 2>&1
t_eq "two installs wire exactly one PreToolUse(Bash) entry" 1 "$(_acn "$AC")"
t_eq "...and ship the hook" yes "$([ -f "$AC/bin/access-confinement.sh" ] && echo yes || echo no)"
ACO="$T/ac-off"; mkdir -p "$ACO"; printf '{}' > "$ACO/settings.json"; : > "$ACO/access-confinement.off"; ri --apply --dir "$ACO" >/dev/null 2>&1
t_eq "access-confinement.off in the config dir: not wired" 0 "$(_acn "$ACO")"

t_section "harbor#1272: the engines' wiring is rendered by deploy-hooks.sh from their manifests"
_tnn() { jq -r '[.hooks.Stop[]?.hooks[]?.command // empty | select(contains("ticket-note.sh"))] | length' "$1/settings.json"; }
_nbind="$(grep -l '^installer	runtime-install$' "$T_ROOT"/hooks/*/manifest.tsv | xargs cat | grep -c '^wire	')"  # this installer's only
HK="$T/hk"; mkdir -p "$HK"; printf '{}' > "$HK/settings.json"; ri --apply --dir "$HK" >/dev/null 2>&1
t_eq "an install records every binding it wired" "$_nbind" "$(wc -l < "$HK/.harbor-hooks-wired" 2>/dev/null | tr -d ' ')"
( jq '.hooks.Stop |= map(select([.hooks[]?.command] | any(contains("ticket-note.sh")) | not))' "$HK/settings.json" > "$HK/s" && mv "$HK/s" "$HK/settings.json" )  # a subshell: jq hashed here would answer the no-jq control below
t_eq "CONTROL: ticket-note's entry was taken out by hand" 0 "$(_tnn "$HK")"
t_has "the dry run says it stays out, and how to bring it back" "$(ri --dir "$HK" 2>&1)" "ticket-note.sh NOT wired: it was removed from settings.json by hand"
ri --apply --dir "$HK" >/dev/null 2>&1
t_eq "...and the next install leaves it out (harbor#362, for every engine)" 0 "$(_tnn "$HK")"
HD="$T/hk-dup"; mkdir -p "$HD"; printf '{}' > "$HD/settings.json"; ri --apply --dir "$HD" >/dev/null 2>&1
( jq --arg c "/bin/sh $HOME/.local/bin/ticket-note.sh" '.hooks.Stop += [{matcher: "", hooks: [{type: "command", command: $c}]}]' "$HD/settings.json" > "$HD/s" && mv "$HD/s" "$HD/settings.json" )
t_eq "CONTROL: a second ticket-note entry, at another path" 2 "$(_tnn "$HD")"
ri --apply --dir "$HD" >/dev/null 2>&1
t_eq "an install re-renders it to the one entry the manifest wants" 1 "$(_tnn "$HD")"
t_eq "...which runs the copy in this config dir" "/bin/sh $HD/bin/ticket-note.sh" "$(jq -r '[.hooks.Stop[]?.hooks[]?.command | select(contains("ticket-note.sh"))][0]' "$HD/settings.json")"
CM="$T/hk-bad-src"; mkdir -p "$CM/bin" "$CM/tests/deploy/restore" "$CM/tests/lib"
cp "$T_ROOT"/bin/*.sh "$T_ROOT"/bin/*.awk "$T_ROOT"/bin/*.py "$CM/bin/"; cp "$T_ROOT/tests/deploy/restore/recover.test.sh" "$CM/tests/deploy/restore/"
cp "$T_ROOT/tests/lib/core.sh" "$CM/tests/lib/"; copy_data "$CM"; copy_hooks "$CM"
printf 'bogus\tkey\n' >> "$CM/hooks/ticket-note/manifest.tsv"
HB="$T/hk-bad"; mkdir -p "$HB"; printf '{}' > "$HB/settings.json"
_hbo="$(env -u CLAUDE_CONFIG_DIR sh "$CM/bin/deploy-runtime-install.sh" --dir "$HB" 2>&1)"; _hbr=$?
t_eq "a manifest that does not render refuses the dry run" 1 "$_hbr"
t_has "...naming the manifest's defect" "$_hbo" "do not render: hooks/ticket-note/manifest.tsv"
env -u CLAUDE_CONFIG_DIR sh "$CM/bin/deploy-runtime-install.sh" --apply --dir "$HB" >/dev/null 2>&1
t_eq "...and --apply writes nothing to settings.json" '{}' "$(cat "$HB/settings.json")"

t_section "a missing jq names the package manager of THIS OS (harbor#618)"
. "$T_ROOT/tests/lib/linux-sim.sh"; NJ="$T/nojq-path"; linux_path "$NJ" jq uname apt-get brew
NJD="$T/nojq-dir"; mkdir -p "$NJD/.claude"; printf '{}' > "$NJD/.claude/settings.json"
nj_run() { # <uname answer> <manager stub|-> -> the run's combined output with no jq on PATH
  _p="$T/nj-$1-$2"; rm -rf "$_p"; mkdir -p "$_p"
  printf '#!/bin/sh\necho %s\n' "$1" > "$_p/uname"; chmod +x "$_p/uname"
  [ "$2" = - ] || { printf '#!/bin/sh\nexit 0\n' > "$_p/$2"; chmod +x "$_p/$2"; }
  env -u CLAUDE_CONFIG_DIR PATH="$_p:$NJ" sh "$TOOL" --dir "$NJD/.claude" 2>&1
}
t_eq "control: the stripped PATH has no jq" "" "$(PATH="$NJ" command -v jq)"
t_has "Linux with apt-get: the FAIL says jq is missing" "$(nj_run Linux apt-get)" "  FAIL: jq is required, and is not on PATH"
t_has "Linux with apt-get: the fix is apt-get" "$(nj_run Linux apt-get)" "  fix: sudo apt-get install -y jq"
t_has "Linux with dnf: the fix is dnf" "$(nj_run Linux dnf)" "  fix: sudo dnf install -y jq"
t_hasnt "Linux: the fix never says brew" "$(nj_run Linux apt-get)" "brew"
t_has "macOS: the fix is brew" "$(nj_run Darwin -)" "  fix: brew install jq"
t_done
