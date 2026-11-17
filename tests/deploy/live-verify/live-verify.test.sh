#!/usr/bin/env sh
# deploy-live-verify.sh (harbor#735): the read-only live tier. One line per check, each with its id; red
# when a check is; nothing written, by stamp and find -newer; never in CI. The box is a sandbox HOME
# with the floor installed and its ledger armed, and a scratch HARBOR_SCOPE_LOCAL_BIN holding the shims.
. "$(dirname "$0")/../../lib/core.sh"; t_init
LV="$T_ROOT/bin/deploy-live-verify.sh"; SRC="$T_ROOT/bin"; C="$HOME/.claude"; LB="$T_TMP/localbin"
HARBOR_SCOPE_MANAGED_SETTINGS="$T_TMP/no-managed/managed-settings.json"; export HARBOR_SCOPE_MANAGED_SETTINGS   # the wall step reads it: never the real one
unset CLAUDE_CONFIG_DIR CI GITHUB_ACTIONS HARBOR_ACCESS_BROWSER_LIVE_URL
HARBOR_DRIFT_REF=HEAD; HARBOR_SCOPE_LOCAL_BIN="$LB"; export HARBOR_DRIFT_REF HARBOR_SCOPE_LOCAL_BIN
rc() { "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }  # the exit; output in $T_TMP/out
out() { cat "$T_TMP/out"; }
line() { grep "\[check:deploy.live-verify\] $1 " "$T_TMP/out"; }  # <check id>

mkdir -p "$C/bin" "$LB"
for f in admission-hook.sh library-admission.sh admission-self-edit.sh admission-bash.sh admission-egress.sh annotate-web.sh admission-deny.sh \
         admission-normalize.awk admission-observe.sh admission-install.sh admission-integrity.sh library-log.sh pin-instructions.sh; do
  cp "$SRC/$f" "$C/bin/$f"
done
printf '{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}\n' > "$C/settings.json"
printf '# the sandbox constitution\n' > "$C/CLAUDE.md"
sh "$SRC/deploy-harden.sh" --apply --live > "$T_TMP/setup" 2>&1
sh "$SRC/admission-install.sh" --apply --live >> "$T_TMP/setup" 2>&1
sh "$SRC/pin-instructions.sh" --apply --live >> "$T_TMP/setup" 2>&1
CLAUDE_CONFIG_DIR="$C" sh "$C/bin/admission-observe.sh" < /dev/null >> "$T_TMP/setup" 2>&1
sh "$SRC/deploy-shim-install.sh" --apply --live >> "$T_TMP/setup" 2>&1
LEDGER="$(find "$C/MEMORY/OBSERVABILITY" -name guard-decisions.jsonl 2>/dev/null | head -1)"

t_section "the sandbox box is armed like a real one"
t_eq "the floor installed" yes "$([ -s "$C/bin/admission-bash.sh" ] && [ -f "$C/.helm-instructions.sha256" ] && echo yes)"
t_eq "the ledger is armed, so a probe that files in it would show" yes "$([ -f "$LEDGER" ] && echo yes)"
t_eq "the shims are linked in the scratch bin" yes "$([ -L "$LB/harbor" ] && echo yes)"

t_section "a green box: every check, one line each with its id"
_n0="$(wc -l < "$LEDGER")"; sleep 1; touch "$T_TMP/stamp"; sleep 1
t_eq "every check green exits 0" "exit 0" "$(rc sh "$LV" --live)"
for id in floor doctor install-drift shims roots sec0-env launchd manifest; do
  t_has "the $id check has its line, and it is green" "$(line "$id")" "ok: [check:deploy.live-verify] $id "
done
t_has "the wall has its line: a WARN here, since the fixture box has no managed install (born warn)" "$(line wall)" "WARN: [check:deploy.live-verify] wall — does not hold: confined Bash"
t_has "...stamped with its own check id as well" "$(line wall)" "[check:drift.wall]"
t_has "the probes are named even when not run" "$(out)" "skip: [check:deploy.live-verify] probe:secret "
t_has "and say how to opt in" "$(line probe:secret)" '--probes'
t_eq "the run ends with its summary" "live-verify: 8 ok, 0 failed, 1 warnings" "$(tail -1 "$T_TMP/out")"
t_eq "every result line carries the check id" "$(grep -cE '^  (ok|FAIL|WARN|skip): ' "$T_TMP/out")" \
  "$(grep -cE '^  (ok|FAIL|WARN|skip): \[check:deploy.live-verify\] ' "$T_TMP/out")"
t_has "docs/reference/checks.md registers the id, unscheduled" "$(grep '^| `deploy.live-verify` |' "$T_ROOT/docs/reference/checks.md")" 'not scheduled'
t_has "and says how to retire it" "$(cat "$T_ROOT/docs/reference/checks.md")" 'To retire `deploy.live-verify`'

t_section "it writes nothing: nothing under the box or the shim dir is newer than the stamp"
t_eq "the config dir, ledger included, and the shim dir" "" "$(find "$C" "$LB" -newer "$T_TMP/stamp" 2>/dev/null)"
t_eq "the ledger took no probe record" "$_n0" "$(wc -l < "$LEDGER")"
t_eq "the stamp would catch a write (control)" "$LEDGER" "$(printf '{}\n' >> "$LEDGER"; find "$C" -newer "$T_TMP/stamp" -name guard-decisions.jsonl)"

t_section "a mispointed shim turns it red, and the line names the shim and the fix"
ln -sfn "$T_TMP/nowhere" "$LB/harbor"
t_eq "one red check exits 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the shims line is the FAIL" "$(line shims)" "FAIL: [check:deploy.live-verify] shims "
t_has "it names the shim" "$(line shims)" 'harbor'
t_has "the fix is the installer's apply" "$(out)" "fix: sh $SRC/deploy-shim-install.sh --apply --live"
t_has "the other checks stay green" "$(line roots)" "ok: [check:deploy.live-verify] roots "
t_eq "the summary counts it" "live-verify: 7 ok, 1 failed, 1 warnings" "$(tail -1 "$T_TMP/out")"
rm -f "$LB/harbor"
t_eq "a missing shim is red too" "exit 1" "$(rc sh "$LV" --live)"
sh "$SRC/deploy-shim-install.sh" --apply --live > /dev/null 2>&1

t_section "a broken floor turns it red"
cp "$C/bin/admission-bash.sh" "$T_TMP/admission-bash.sh.keep"; chmod u+w "$C/bin" "$C/bin/admission-bash.sh" 2>/dev/null
printf 'exit 0\n' > "$C/bin/admission-bash.sh"
t_eq "a gutted guard exits 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the floor line is the FAIL" "$(line floor)" "FAIL: [check:deploy.live-verify] floor "
cp "$T_TMP/admission-bash.sh.keep" "$C/bin/admission-bash.sh"
t_eq "restored, it is green again" "exit 0" "$(rc sh "$LV" --live)"

t_section "a missing harbor#816 env key turns sec0-env red, and the fix is deploy's sec0 apply"
_env0="$(jq -S '.env' "$C/settings.json")"
jq '.env.DISABLE_ERROR_REPORTING = "0"' "$C/settings.json" > "$T_TMP/s.tmp" && mv "$T_TMP/s.tmp" "$C/settings.json"
t_eq "one flipped key exits 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the sec0-env line is the FAIL" "$(line sec0-env)" "FAIL: [check:deploy.live-verify] sec0-env "
t_has "it names the missing key" "$(line sec0-env)" 'DISABLE_ERROR_REPORTING'
t_has "the fix is deploy's sec0 apply, never sec0-harden run bare (deploy is the only live entry)" "$(out)" \
  "fix: sh $SRC/deploy.sh --only sec0 --apply --live"
t_has "the other checks stay green" "$(line roots)" "ok: [check:deploy.live-verify] roots "
t_eq "the summary counts it" "live-verify: 7 ok, 1 failed, 1 warnings" "$(tail -1 "$T_TMP/out")"
sh "$SRC/deploy-harden.sh" --apply --live > /dev/null 2>&1
t_eq "sec0-harden's own apply repairs it (no drift left for the next deploy)" "$_env0" "$(jq -S '.env' "$C/settings.json")"
t_eq "green again" "exit 0" "$(rc sh "$LV" --live)"

t_section "a manifest row with no file turns manifest red (harbor#1437)"
# bin/CHECKS.md moved to bin/docs/reference/checks.md; its row stayed in the live manifest and nothing said so.
cp "$C/.harbor-manifest" "$T_TMP/manifest.keep"
t_has "control: the manifest exists and the check is green" "$(rc sh "$LV" --live >/dev/null; line manifest)" "ok: [check:deploy.live-verify] manifest "
printf '%s 100644 bin/CHECKS.md runtime-install abc123\n' "$(printf x | git hash-object --stdin)" >> "$C/.harbor-manifest"
t_eq "a row whose file is gone exits 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the manifest line is the FAIL" "$(line manifest)" "FAIL: [check:deploy.live-verify] manifest "
t_has "...naming the dangling path" "$(line manifest)" "bin/CHECKS.md"
t_has "...fixed by a deploy" "$(out)" "fix: sh $SRC/deploy.sh --apply --live"
cp "$T_TMP/manifest.keep" "$C/.harbor-manifest"
t_eq "restored, green again" "exit 0" "$(rc sh "$LV" --live)"

t_section "the name-create rule with no row is OFF, and the line says so (harbor#978, check context.name-create)"
t_has "control: the rule not installed, the line is a skip" "$(rc sh "$LV" --live >/dev/null; line name-create)" "skip: [check:deploy.live-verify] name-create "
mkdir -p "$C/context-rules/user"; cp "$T_ROOT/context-rules/user/name-note-create.md" "$C/context-rules/user/"
t_eq "the rule installed and name-create.d missing: exit 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the line is the FAIL, saying the rule is off" "$(line name-create)" "FAIL: [check:deploy.live-verify] name-create — OFF: "; t_has "...naming what is missing" "$(line name-create)" "/name-create.d is missing"
t_has "...stamped with its own check id" "$(line name-create)" "[check:context.name-create]"
t_has "...and the fix installs core's rows" "$(out)" "fix: sh $SRC/context-injection-install.sh --apply --live"
mkdir -p "$C/name-create.d"; printf '# only a comment\n\n' > "$C/name-create.d/harbor.tsv"
t_eq "a row file that holds no row: exit 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "...and says it holds no row" "$(line name-create)" "holds no row"
cp "$T_ROOT/contracts/name-create.tsv" "$C/name-create.d/harbor.tsv"
t_eq "core's rows in place: green" "exit 0" "$(rc sh "$LV" --live)"
t_has "...counting them" "$(line name-create)" "ok: [check:deploy.live-verify] name-create — 4 command row(s) in 1 file(s)"
t_red check.context.name-create
rm -rf "$C/name-create.d" "$C/context-rules/user/name-note-create.md"

t_section "a job running a script older than its installed copy turns launchd red (harbor#1437)"
# launchctl is a stub reporting a real sleep as the job's pid; the job's script is then newer than that process.
mkdir -p "$HOME/Library/LaunchAgents" "$T_TMP/jobstub"
printf '#!/bin/sh\necho v1\n' > "$C/lv-job.sh"
cat > "$HOME/Library/LaunchAgents/com.harbor.lvjob.plist" <<PL
<plist version="1.0"><dict>
  <key>Label</key><string>com.harbor.lvjob</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>$C/lv-job.sh</string>
  </array>
</dict></plist>
PL
sleep 300 >/dev/null 2>&1 & echo $! > "$T_TMP/jobstub/pid"
cat > "$T_BIN/launchctl" <<STUB
#!/bin/sh
case "\$1" in print) printf 'pid = %s\n' "\$(cat "$T_TMP/jobstub/pid")" ;; esac
exit 0
STUB
chmod +x "$T_BIN/launchctl"
t_eq "control: a job on the bytes it started with is green" "exit 0" "$(rc sh "$LV" --live)"
printf '#!/bin/sh\necho v2\n' > "$C/lv-job.sh"; touch -t "$(date -v+2M +%Y%m%d%H%M.%S 2>/dev/null || date -d '+2 min' +%Y%m%d%H%M.%S)" "$C/lv-job.sh"
t_eq "a replaced script under an older process exits 1" "exit 1" "$(rc sh "$LV" --live)"
t_has "the launchd line is the FAIL" "$(line launchd)" "FAIL: [check:deploy.live-verify] launchd "
t_has "...naming the job" "$(out)" "com.harbor.lvjob"
kill "$(cat "$T_TMP/jobstub/pid")" 2>/dev/null; rm -f "$T_BIN/launchctl" "$HOME/Library/LaunchAgents/com.harbor.lvjob.plist" "$C/lv-job.sh"
t_eq "with the job gone it is green again" "exit 0" "$(rc sh "$LV" --live)"

t_section "the opt-in probes run only when asked, and touch no real item"
. "$T_ROOT/tests/cli/keychain-stub.sh"  # a hermetic suite never reaches the real Keychain (rule 1)
t_eq "--probes on the sandbox box" "exit 0" "$(rc sh "$LV" --live --probes)"
t_has "the live-dir refusal is probed" "$(line probe:live-dir)" "ok: [check:deploy.live-verify] probe:live-dir "
t_has "the Keychain probe is green" "$(line probe:secret)" "ok: [check:deploy.live-verify] probe:secret "
t_has "it looked up its own absent name" "$(cat "$KC_STUB/argv.log")" 'find-generic-password|-s|secret.zz-harbor-live-probe-absent|'
t_eq "and only looked up: no add, no delete, no dump" "" "$(grep -v '^find-generic-password|' "$KC_STUB/argv.log")"
t_eq "and no other name" "" "$(grep -v 'secret.zz-harbor-live-probe-absent' "$KC_STUB/argv.log")"
t_eq "the stub's store is untouched" "" "$(ls "$KC_STUB/items")"
t_has "the browser probe skips without a URL the operator owns" "$(line probe:browser)" 'HARBOR_ACCESS_BROWSER_LIVE_URL'
printf 'x' > "$KC_STUB/items/secret.zz-harbor-live-probe-absent@${USER:-$(id -un)}"
t_eq "a probe item that exists turns the probe red" "exit 1" "$(rc sh "$LV" --live --probes)"
t_has "and says so" "$(line probe:secret)" "FAIL: [check:deploy.live-verify] probe:secret "
t_has "naming the item, not a changed exit contract" "$(line probe:secret)" 'exists; the probe needs that name absent'
t_eq "and leaves the item alone" yes "$([ -f "$KC_STUB/items/secret.zz-harbor-live-probe-absent@${USER:-$(id -un)}" ] && echo yes)"
rm -f "$KC_STUB/items"/*
t_eq "without --probes, no probe touches the Keychain" "" "$(: > "$KC_STUB/argv.log"; sh "$LV" --live > /dev/null 2>&1; cat "$KC_STUB/argv.log")"

t_section "no config dir: one FAIL naming the precondition, and the checks that read the install are not run (harbor#457)"
NH="$T_TMP/nobox"; mkdir -p "$NH"
rcx() { env HOME="$NH" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
t_eq "a box that Claude Code never ran on exits 1" "exit 1" "$(rcx sh "$LV" --live)"
t_eq "...with exactly one FAIL, not four" 1 "$(grep -c '^  FAIL: ' "$T_TMP/out")"
t_has "...and it is the precondition, naming the missing dir" "$(grep -m1 '^  FAIL: ' "$T_TMP/out")" "[check:deploy.live-verify] precondition — no config dir at $NH/.claude"
t_has "...fixed by the first-run command, spelled from this checkout" "$(grep -A1 'precondition' "$T_TMP/out")" "  fix: sh '$T_ROOT/bin/harbor' scope install"
for id in floor install-drift shims sec0-env; do
  t_has "$id is skipped, with the cause" "$(line "$id")" "skip: [check:deploy.live-verify] $id — not run: no config dir at $NH/.claude"
done
t_has "doctor reads the tools, not the install, and still runs" "$(line doctor)" "ok: [check:deploy.live-verify] doctor "
t_has "roots reads the checkout, and still runs" "$(line roots)" "ok: [check:deploy.live-verify] roots "
t_eq "the summary counts the one failure" "live-verify: 3 ok, 1 failed, 1 warnings" "$(tail -1 "$T_TMP/out")"
mkdir -p "$NH/.claude"; NHP="$(cd "$NH/.claude" && pwd -P)"
t_eq "a config dir with no settings.json is the same precondition" "exit 1" "$(rcx sh "$LV" --live)"
t_has "...naming the file" "$(grep -m1 '^  FAIL: ' "$T_TMP/out")" "precondition — no settings.json in $NHP"
printf '{}\n' > "$NH/.claude/settings.json"
t_eq "CONTROL: with a settings.json the checks run again" "exit 1" "$(rcx sh "$LV" --live)"
t_eq "...and no precondition line is raised" 0 "$(grep -c 'precondition' "$T_TMP/out")"
t_has "...the floor check ran and failed on its own terms" "$(line floor)" "FAIL: [check:deploy.live-verify] floor "

t_section "an installed box that lost its settings.json: its own cause and fix, and only what reads the file is skipped (harbor#457)"
LH="$T_TMP/lostbox"; mkdir -p "$LH/.claude"; cp -R "$C/bin" "$LH/.claude/bin"; LHP="$(cd "$LH/.claude" && pwd -P)"  # the install, minus settings.json
rcl() { env HOME="$LH" "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }
t_eq "a box with bin/ and no settings.json exits 1" "exit 1" "$(rcl sh "$LV" --live)"
t_has "...the precondition says the file was lost after an install" "$(grep -m1 '^  FAIL: ' "$T_TMP/out")" "precondition — no settings.json in $LHP: this box has an install (bin/ or .harbor-manifest), so the file was lost after the first run"
t_eq "...and never claims nothing is installed" 0 "$(grep -c 'nothing is installed here' "$T_TMP/out")"
t_has "...with no snapshot, the fix is still the first-run command" "$(grep -A1 'precondition' "$T_TMP/out")" "  fix: sh '$T_ROOT/bin/harbor' scope install"
for id in floor sec0-env; do
  t_has "$id reads settings.json, so it is skipped with the cause" "$(line "$id")" "skip: [check:deploy.live-verify] $id — not run: no settings.json in $LHP"
done
for id in install-drift shims; do
  t_eq "$id does not read settings.json, so it still runs" 0 "$(line "$id" | grep -c 'skip:')"
done
mkdir -p "$LH/.claude/backups/deploy-20260101-000000"
t_eq "with a deploy snapshot, still exit 1" "exit 1" "$(rcl sh "$LV" --live)"
t_has "...the fix is restore's dry run, which holds the operator's own settings" "$(grep -A1 'precondition' "$T_TMP/out")" "  fix: sh '$SRC/deploy-restore.sh' --live"
rm -rf "$LH"

t_section "the gates: read-only, the live box only, never in CI"
t_exit "--apply is refused as usage" 2 sh "$LV" --live --apply
t_exit "--dir is refused as usage: a sandbox is a HOME" 2 sh "$LV" --dir "$C"
t_exit "no target is usage" 2 sh "$LV"
t_exit "CI set: it never runs" 2 env CI=true sh "$LV" --live
t_exit "GITHUB_ACTIONS set: it never runs" 2 env GITHUB_ACTIONS=true sh "$LV" --live
t_exit "a CLAUDE_CONFIG_DIR naming another dir is refused" 2 env CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" sh "$LV" --live
t_exit "--help answers" 0 sh "$LV" --help
t_eq "harbor check dispatches to it" "exit 0" "$(rc sh "$SRC/harbor" check --live)"
t_has "through the dispatcher, the same lines" "$(out)" "ok: [check:deploy.live-verify] roots "
t_red check.live-verify   # the falsifier this suite names for them (harbor#1422)
t_done
