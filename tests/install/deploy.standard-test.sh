#!/usr/bin/env sh
# deploy.sh on the install standard §4 and §6 (harbor#762, #770, #736): refused up front, opt-ins read
# from the box, sec0-harden in the chain, --only, every check again after a restore, a snapshot that
# covers what the installers write plus a ~/.local/bin record, and the other repos' `just install`.
# The throwaway repo and stubs are deploy-test's (deploy-fixture.sh); one section runs the REAL
# installers into a sandbox to derive what the snapshot must cover.
. "$(dirname "$0")/../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY  # a run inside a session or a deploy must not decide a case
T_TMP="$(cd "$T_TMP" && pwd -P)"  # deploy reports the config dir physically (install-lib's il_target)
. "$(dirname "$0")/deploy-fixture.sh"
need_pty
yn() { if "$@"; then echo yes; else echo no; fi; }
floorline() { grep '^floor-install.sh' "$LOGF" | grep -- "$1" | head -1; }  # <--apply|--live$> the first such line
stopwire() { printf '{"hooks":{"Stop":[{"matcher":"","hooks":[{"type":"command","command":"/bin/sh %s/bin/guard-stop.sh"}]}]}}\n' "$C" > "$C/settings.json"; }
b6wire() {
  printf '#!/bin/sh\nexit 0\n' > "$C/bin/guard-integrity.sh" 2>/dev/null || { mkdir -p "$C/bin"; printf '#!/bin/sh\nexit 0\n' > "$C/bin/guard-integrity.sh"; }
  printf '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"/bin/sh %s/bin/guard-integrity.sh"}]}]}}\n' "$C" > "$C/settings.json"
}

t_section "refused up front, before any check or plan (install standard §4)"
fixture upcc; CC=1 run '' --apply --live; CC=''
t_eq "--apply inside a Claude session" 1 "$RC"
t_has "...says so up front" "$(out)" "  FAIL: refused up front: running inside a Claude session"
t_eq "...its fix is the exact command, for a terminal" "  fix: sh '$REPO/bin/deploy.sh' --apply --live" "$(grep -A1 'refused up front' "$T/out.txt" | sed -n 2p)"
t_hasnt "...before the preflight" "$(out)" "── deploy · preflight"
t_eq "...and before any installer's dry run (stub log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
t_has "...and the refusal is kept in the run's log" "$(dlog)" "FAIL: refused up front: running inside a Claude session"
t_has "...with the verdict" "$(dlog)" "PREFLIGHT FAILED (1) — refused up front"
t_eq "...and the screen ends naming that log" "log: $(ls "$C"/backups/deploy/*/log | head -1)" "$(tail -1 "$T/out.txt")"
fixture uponly; CC=1 run '' --apply --only floor --live; CC=''
t_eq "the fix keeps this run's own arguments" "  fix: sh '$REPO/bin/deploy.sh' --apply --only floor --live" "$(grep -A1 'refused up front' "$T/out.txt" | sed -n 2p)"
fixture upwt; MAIN="$REPO"; git -C "$REPO" worktree add -q --detach "$T/wt" 2>/dev/null; REPO="$T/wt"; run '' --live
t_eq "a dry run from a linked worktree" 1 "$RC"
t_has "...is refused, naming it" "$(out)" "running from a linked worktree ($T/wt)"
t_eq "...with the same dry run from the main checkout as its fix" "  fix: sh '$MAIN/bin/deploy.sh' --live" "$(grep -A1 'linked worktree' "$T/out.txt" | sed -n 2p)"
t_hasnt "...before the preflight" "$(out)" "── deploy · preflight"
t_eq "...and before any installer's dry run (stub log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
run '' --apply --live
t_eq "an --apply from a linked worktree is refused up front too" 1 "$RC"
t_eq "...its fix the apply, from the main checkout" "  fix: sh '$MAIN/bin/deploy.sh' --apply --live   # from a terminal window" "$(grep -A1 'linked worktree' "$T/out.txt" | sed -n 2p)"
t_eq "...and nothing ran" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
fixture upok; run '' --live
t_eq "the positive control: a dry run from the main checkout outside a session" 0 "$RC"
t_has "...runs the preflight" "$(out)" "── deploy · preflight"

t_section "harbor deploy: the same refusals through the verb, from any directory (CLI1 amendment, 2026-09-30)"
# The REAL dispatcher, committed into the throwaway repo; status-gen.sh is how it finds its own bin/.
fixture viah; cp "$T_ROOT/bin/harbor" "$REPO/bin/harbor"; printf '#!/bin/sh\nexit 0\n' > "$REPO/bin/status-gen.sh"
git -C "$REPO" add bin/harbor bin/status-gen.sh; commit_push 'the real dispatcher'
VIA=harbor; CC=1 run '' --apply --live; CC=''
t_eq "harbor deploy --apply --live inside a Claude session" 1 "$RC"
t_has "...is refused up front, as deploy.sh is" "$(out)" "  FAIL: refused up front: running inside a Claude session"
t_eq "...with the same fix" "  fix: sh '$REPO/bin/deploy.sh' --apply --live" "$(grep -A1 'refused up front' "$T/out.txt" | sed -n 2p)"
t_eq "...and nothing ran (stub log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
run '' --live
t_eq "the positive control: harbor deploy --live, from /, outside a session" 0 "$RC"
t_has "...is deploy's dry run" "$(out)" "  note: Preflight passed; the plan is above"
MAIN="$REPO"; git -C "$REPO" worktree add -q --detach "$T/wt" 2>/dev/null; REPO="$T/wt"; : > "$LOGF"; run '' --live
t_eq "harbor deploy through a linked worktree's dispatcher" 1 "$RC"
t_has "...is refused, naming the worktree" "$(out)" "running from a linked worktree ($T/wt)"
t_eq "...with the main checkout's dry run as its fix" "  fix: sh '$MAIN/bin/deploy.sh' --live" "$(grep -A1 'linked worktree' "$T/out.txt" | sed -n 2p)"
t_eq "...and nothing ran" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
VIA=''; REPO="$MAIN"

t_section "a native Windows shell is refused before the preflight, naming WSL2 (harbor#833, CONTRACTS/platforms.md)"
UB="$T_TMP/uname-bin"; mkdir -p "$UB"
for _u in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
  printf '#!/bin/sh\necho %s\n' "$_u" > "$UB/uname"; chmod +x "$UB/uname"
  for _m in --live --apply; do
    fixture "win$_m"; set -- --live; [ "$_m" = --live ] || set -- --apply --live
    RC=0; ( cd "$REPO" && env -u CLAUDE_CONFIG_DIR PATH="$UB:$PATH" HOME="$H" STUB_LOG="$LOGF" sh bin/deploy.sh "$@" ) >"$T/out.txt" 2>&1 </dev/null || RC=$?
    t_eq "deploy.sh $* under $_u exits 1" 1 "$RC"
    t_has "...naming WSL2" "$(out)" "WSL2"
    t_hasnt "...before the preflight" "$(out)" "── deploy · preflight"
    t_eq "...no installer ran (stub log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"
    t_eq "...and nothing was written under the config dir" "" "$(ls -A "$C/backups" 2>/dev/null)"
  done
done
for _u in Linux Darwin; do
  printf '#!/bin/sh\necho %s\n' "$_u" > "$UB/uname"
  fixture "unix$_u"; RC=0
  ( cd "$REPO" && env -u CLAUDE_CONFIG_DIR PATH="$UB:$PATH" HOME="$H" STUB_LOG="$LOGF" STUB_REPO="$REPO" STUB_GI="$T/gi" STUB_SKILLS="$T/skills" STUB_CMDS="$T/cmds" STUB_B8="$T/b8" sh bin/deploy.sh --live ) >"$T/out.txt" 2>&1 </dev/null || RC=$?
  t_eq "the control: deploy.sh --live under $_u" 0 "$RC"
  t_has "...runs the preflight" "$(out)" "── deploy · preflight"
done

t_section "opt-ins are read from the box: a wired Stop gate and an installed B6 are refreshed (harbor#762)"
fixture stopwired; stopwire; run 'y\nn\n' --apply --live
t_eq "a deploy onto a box that wires guard-stop.sh" 0 "$RC"
t_has "...refreshes the Stop gate in floor-install's apply" "$(floorline --apply)" "--with-stop-gate"
t_has "...and plans it in floor-install's own dry run" "$(grep '^floor-install.sh --live' "$LOGF" | grep -v -- --apply)" "--with-stop-gate"
t_has "...saying why" "$(out)" "Stop gate: wired on this box, so floor-install refreshes it"
fixture stopnone; run 'y\nn\n' --apply --live
t_eq "the control: a box without the Stop gate" 0 "$RC"
t_hasnt "...is not opted in" "$(floorline --apply)" "--with-stop-gate"
t_hasnt "...nor into B6" "$(floorline --apply)" "--with-b6"
fixture stopflag; run 'y\nn\n' --apply --live --with-stop-gate
t_has "--with-stop-gate opts a box in" "$(floorline --apply)" "--with-stop-gate"
fixture b6in; b6wire; run 'y\nn\n' --apply --live
t_eq "a deploy onto a box that runs B6" 0 "$RC"
t_has "...refreshes it and its pin through floor-install --with-b6" "$(floorline --apply)" "--with-b6"
t_has "...and says B6 is enabled afterwards" "$(out)" "  ok: B6 is enabled; floor-install refreshed it and its pin"
fixture b6file; mkdir -p "$C/bin"; printf '#!/bin/sh\nexit 0\n' > "$C/bin/guard-integrity.sh"; run 'y\nn\n' --apply --live
t_hasnt "a guard-integrity.sh nothing wires is not B6 installed" "$(floorline --apply)" "--with-b6"
t_has "...and the B6 next step goes through deploy" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --only floor --with-b6 --live"
fixture b6first; rm -rf "$C/.helm-pins"; run '' --live --with-b6
t_eq "--with-b6 on a box with no floor yet" 1 "$RC"
t_has "...is refused: B6 installs last" "$(out)" "B6 installs last: this box has no floor yet"
t_eq "...before any installer ran" "" "$(applied)"

t_section "sec0-harden joins the chain"
fixture sec0plan; run '' --live
t_eq "its dry run is part of the plan" 1 "$(grep -cx 'sec0-harden.sh --live' "$LOGF")"
t_has "...and reported" "$(out)" "  ok: sec0-harden.sh: its dry run passes"
fixture sec0fail; STUB_FAIL=sec0-harden.sh:dry; export STUB_FAIL; refuse "sec0-harden's own dry run refusing" "sec0-harden.sh: its own dry run FAILED"; unset STUB_FAIL
fixture sec0apply; run 'y\nn\n' --apply --live
t_eq "an apply runs it once, with --live" 1 "$(grep -cx 'sec0-harden.sh --apply --live' "$LOGF")"
t_eq "...after shim-install and before runtime-install" "shim-install.sh,sec0-harden.sh,runtime-install.sh," \
  "$(grep -e '--apply' "$LOGF" | awk '{print $1}' | grep -E '^(shim-install|sec0-harden|runtime-install)' | head -n 3 | tr '\n' ',')"

t_section "--only: one component, the same gates and the same snapshot"
fixture onlyfloor; echo mine > "$C/inject.d/99-mine.md"; run 'y\nn\n' --apply --only floor --live
t_eq "--only floor" 0 "$RC"
t_eq "...installs the floor and nothing else" "floor-install.sh --live," "$(applied)"
t_hasnt "...and does not judge an inject.d pack it will not touch" "$(out)" "99-mine.md"
t_has "...after the same snapshot" "$(tar -tzf "$C"/backups/deploy-*/config.tgz 2>/dev/null)" "settings.json"
t_has "...and says what it leaves alone" "$(out)" "  note: only:       floor — every other component is left as it is"
fixture onlytwo; run 'y\nn\n' --apply --only runtime,skills --live
t_eq "--only runtime,skills installs exactly those, in the chain's order" \
  "runtime-install.sh --live,skills-install.sh --all,skills-install.sh commands,skill-book.sh install," \
  "$(grep -e '--apply' -e '^skill-book' "$LOGF" | awk '{print $1, $2}' | tr '\n' ',')"
fixture onlyinj; echo mine > "$C/inject.d/99-mine.md"; run '' --only inject --live
t_eq "--only inject still refuses a box-only pack it would replace" 1 "$RC"
t_has "...naming it" "$(out)" "99-mine.md"
run '' --only bogus --live; t_eq "--only an unknown component is a usage error" 2 "$RC"
t_has "...naming the components" "$(out)" "--only bogus: not a component"
run '' --only --live; t_eq "--only with no value is a usage error" 2 "$RC"
run '' --prune --only floor --live; t_eq "--prune with --only is a usage error" 2 "$RC"

t_section "after a restore, every check runs again on the restored box, and the log keeps it (§4)"
fixture recheck; STUB_FAIL=floor-install.sh:apply; export STUB_FAIL
STUB_HOOK_runtimeinstallsh="printf MODIFIED > '$C/settings.json'"; export STUB_HOOK_runtimeinstallsh
run 'y\ny\n' --apply --live; unset STUB_FAIL STUB_HOOK_runtimeinstallsh
t_eq "the failed install that was restored" 1 "$RC"
t_eq "settings.json is back" "{}" "$(cat "$C/settings.json")"
t_has "the re-check runs after the restore" "$(out)" "── deploy · re-check · every check again, on the restored box"
t_exit "...verify and floor-verify, both, after it" 0 awk '/re-check · every check again/{r=1} r && /── deploy · verify/{v=1} r && /── deploy · floor-verify/{f=1} END{exit !(v && f)}' "$T/out.txt"
t_has "...ending on its verdict" "$(out)" "  ok: re-check: the restored box passes every check"
t_has "the log holds the restore" "$(dlog)" "  ok: restored $C from "
t_has "...and the re-check after it" "$(dlog)" "re-check: the restored box passes every check"
t_eq "...one log for the whole run" 1 "$(ls "$C"/backups/deploy/*/log 2>/dev/null | grep -c .)"
fixture norestore; STUB_FAIL=floor-install.sh:apply; export STUB_FAIL; run 'y\nn\n' --apply --live; unset STUB_FAIL
t_hasnt "the control: no re-check when the restore is declined" "$(out)" "re-check ·"

t_section "the snapshot: the manifest, and a ~/.local/bin record restore.sh can use (harbor#770)"
fixture snapbin; printf 'row\n' > "$C/.harbor-manifest"; printf 'real file\n' > "$H/.local/bin/tool"
ln -s "$T/nowhere" "$H/.local/bin/gone"; run 'y\nn\n' --apply --live
SD="$(ls -d "$C"/backups/deploy-* | head -1)"
t_has "set.txt names the install manifest (§3)" "$(cat "$SD/set.txt")" ".harbor-manifest"
t_has "...and the archive holds it" "$(tar -tzf "$SD/config.tgz")" ".harbor-manifest"
t_eq "local-bin.tsv names the dir it recorded" "# dir: $(cd -P "$H/.local/bin" && pwd -P)" "$(sed -n 2p "$SD/local-bin.tsv")"
t_eq "...a link as a link, with its target" "harbor	link	$REPO/bin/harbor" "$(grep '^harbor	' "$SD/local-bin.tsv")"
t_eq "...a dangling link too" "gone	link	$T/nowhere" "$(grep '^gone	' "$SD/local-bin.tsv")"
t_eq "...a file as a file, with its git blob" "tool	file	$(git hash-object "$H/.local/bin/tool")" "$(grep '^tool	' "$SD/local-bin.tsv")"
_sh() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
t_eq "the ledger row carries its hash, after the set's" "bin=$(_sh < "$SD/local-bin.tsv")" "$(awk '{print $5}' "$C/.helm-snapshots")"
t_eq "the listing it replaced is gone" no "$(yn [ -e "$SD/local-bin.txt" ])"

t_section "the snapshot covers every top-level entry the REAL installers write (derived, §4)"
SB="$T_TMP/snapset/cfg"; PI_FAKE="$T_TMP/snapset/pi"; mkdir -p "$SB" "$PI_FAKE/templates/base/dot_agents/hooks"
printf '{}\n' > "$SB/settings.json"
# prod-guard-install verifies the pair it installed asks on a destructive gcloud call (tests/hooks/prod-guard-test's stub).
cat > "$PI_FAKE/templates/base/dot_agents/hooks/prod_guard.py" <<'PY'
import json, sys  # a stub: the PI-903 refusal marker the installer greps for is is_symlink
p = json.load(sys.stdin)
if "gcloud" in p.get("tool_input", {}).get("command", ""):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask", "permissionDecisionReason": "STUB"}}))
PY
SNAPSET="$(sed -n "s/^SNAP_SET='\(.*\)'$/\1/p" "$T_ROOT/bin/deploy.sh")"
t_has "deploy.sh's SNAP_SET is read" "$SNAPSET" "settings.json"
ri() { printf "=== %s\n" "$*" >>"$T_TMP/snapset/out"; env -u CLAUDE_CONFIG_DIR HARBOR_DEPLOY=1 PROJECT_INIT_SRC="$PI_FAKE" sh "$T_ROOT/bin/$@" >>"$T_TMP/snapset/out" 2>&1; echo $?; }
for _i in "sec0-harden.sh --apply --dir $SB" "runtime-install.sh --apply --dir $SB" \
          "floor-install.sh --apply --dir $SB --with-b6 --with-stop-gate" "constitution-install.sh --apply --dir $SB --from-branch" \
          "prod-guard-install.sh --apply --dir $SB" "skills-install.sh --all --apply --dir $SB" \
          "skills-install.sh commands --all --apply --dir $SB" "inject-install.sh --apply --dir $SB" "pin-instructions.sh --apply --dir $SB"; do
  # shellcheck disable=SC2086
  t_eq "the real ${_i%% *} applies to the sandbox" 0 "$(ri $_i)"
done
# Never snapshot state its reader must keep: MEMORY and backups/ restore never touches, and the two
# floor-observe files (written by that SessionStart hook; floor-install runs it once) key the ledger in
# MEMORY, so restoring an older salt would un-link every recorded digest (CONTRACTS/helm-state.md).
_uncovered=''
for _e in $(ls -A "$SB"); do
  case "$_e" in backups|MEMORY|.helm-obs-host|.helm-obs-salt) continue ;; esac
  _hit=0
  set -f
  for _g in $SNAPSET; do
    # shellcheck disable=SC2254
    case "$_e" in $_g) _hit=1 ;; esac
  done
  set +f
  [ "$_hit" -eq 1 ] || _uncovered="$_uncovered $_e"
done
t_eq "every top-level entry they wrote is in SNAP_SET, so a restore puts it back" "" "$_uncovered"
t_has "...and they wrote a manifest to check" "$(ls -A "$SB")" ".harbor-manifest"

t_section "the other repos' just install, after Harbor's (harbor#736)"
fixture xr; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" 'install lint'; xrepo "$STUB_PO" 'install test'
run '' --live
t_eq "a dry run with both repos" 0 "$RC"
t_has "...plans project-init's own dry run" "$(out)" "  ok: project-init: its dry run (just install) passes"
t_has "...and projects-orchestrator's" "$(out)" "  ok: projects-orchestrator: its dry run (just install) passes"
t_eq "...as each repo's own recipe, with no flag" "just $STUB_PI install,just $STUB_PO install," "$(grep '^just ' "$LOGF" | tr '\n' ',')"
t_eq "...and writes nothing" "" "$(applied)"
: > "$LOGF"; run 'y\nn\n' --apply --live
t_eq "an apply with both repos" 0 "$RC"
t_eq "...runs them after Harbor's installers, project-init first" "inject-install.sh,just $STUB_PI install --apply,just $STUB_PO install --apply," \
  "$(grep -e '--apply' "$LOGF" | grep -e '^inject-install' -e '^just ' | sed 's/ --live --apply$//' | awk '{ if ($1 == "just") print; else print $1 }' | tr '\n' ',')"
t_eq "...and its verify runs each one's --check" "just $STUB_PI install --check,just $STUB_PO install --check," "$(grep -- '--check' "$LOGF" | tr '\n' ',')"
t_has "...reporting the match" "$(out)" "  ok: project-init: the installed build matches its tree (just install --check)"
fixture xrfail; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
echo 3 > "$STUB_PI/.rc.apply"; run 'y\nn\n' --apply --live
t_eq "a sub-installer exiting 3 fails the deploy" 1 "$RC"
t_has "...naming it and its exit code" "$(out)" "stopped at: project-init: just install --apply (rc=3)"
t_eq "...and the rest of the chain does not run" 0 "$(grep -c "^just $STUB_PO install --apply" "$LOGF")"
t_has "...the snapshot is offered back" "$(out)" "Restore the snapshot now?"
fixture xrdry; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
echo 1 > "$STUB_PO/.rc.dry"; refuse "projects-orchestrator's dry run refusing" "projects-orchestrator: its own dry run (just install, in $STUB_PO) refuses (rc=1)"
fixture xrunreach; unset STUB_PO; xrepo "$STUB_PI" 'lint test'; run '' --live
t_eq "a repo with no install recipe, and one unresolved: the dry run fails" 1 "$RC"
t_has "...in preflight, before any write" "$(out)" "PREFLIGHT FAILED (1) — nothing was installed"
t_has "...naming the repo with no install recipe" "$(out)" "  note: project-init: $STUB_PI has no \`install\` recipe"
t_has "...and the unresolved one" "$(out)" "  note: projects-orchestrator: no justfile at <unresolved>"
t_eq "...and its recipe is never run" 0 "$(grep -c '^just ' "$LOGF")"
XFIX="$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)"
t_eq "...its fix: this run with --only every other component" \
  "  fix: sh '$REPO/bin/deploy.sh' --only constitution,shim,sec0,runtime,floor,prod-guard,skills,inject,packs --live" "$XFIX"
t_exit "...every FAIL followed by its fix line" 0 fixfollows
: > "$LOGF"
# shellcheck disable=SC2046
run '' $(printf '%s' "$XFIX" | sed "s|^  fix: sh '$REPO/bin/deploy.sh' ||")
t_eq "that fix, run as printed, passes" 0 "$RC"
t_eq "...and runs neither repo's recipe" 0 "$(grep -c '^just ' "$LOGF")"
run 'y\nn\n' --apply --only constitution,shim,sec0,runtime,floor,prod-guard,skills,inject,packs --live
t_eq "...and its --apply installs Harbor's components" 0 "$RC"
t_has "...ending verified" "$(out)" "installed and verified"
run '' --live --with-stop-gate
t_has "the fix keeps this run's opt-ins" "$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)" "--only constitution,shim,sec0,runtime,floor,prod-guard,skills,inject,packs --with-stop-gate --live"
run '' --only floor,project-init --live
t_eq "--only a subset holding an unreachable repo fails too" 1 "$RC"
t_eq "...its fix keeps the rest of that subset" "  fix: sh '$REPO/bin/deploy.sh' --only floor --live" "$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)"
run '' --only projects-orchestrator --live
t_eq "--only an unreachable repo alone fails" 1 "$RC"
t_has "...with no --only left to offer, so its fix is to make it reachable" "$(grep -A1 '^  FAIL: cannot install ' "$T/out.txt" | sed -n 2p)" "  fix: none automatic — see "
unset STUB_PI; run '' --only floor --live
t_eq "the control: a box with neither repo, deploying only what it can reach" 0 "$RC"
t_hasnt "...names neither repo" "$(out)" "project-init"
fixture xrcheck; xrepo "$STUB_PI" install; echo 1 > "$STUB_PI/.rc.check"
run 'y\nn\n' --apply --live
t_eq "an installed build that differs from its tree fails verify" 1 "$RC"
t_has "...saying so" "$(out)" "  FAIL: project-init: the installed build differs from its tree (just install --check, rc=1)"
t_has "...with the one-component deploy as its fix" "$(out)" "  fix: sh '$REPO/bin/deploy.sh' --apply --only project-init --live"
fixture xronly; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
run 'y\nn\n' --apply --only projects-orchestrator --live
t_eq "--only projects-orchestrator runs that repo alone" "just $STUB_PO install,just $STUB_PO install --apply,just $STUB_PO install --check," "$(grep '^just ' "$LOGF" | tr '\n' ',')"
t_eq "...and no Harbor installer" "" "$(grep -v '^just ' "$LOGF" | grep -e '--apply' || true)"
t_section "a cross-repo clone behind its origin fails preflight, judged against a fresh fetch (harbor#736)"
fixture xrsync; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
xgit "$STUB_PI"; xgit "$STUB_PO"; rm -f "$STUB_PI/.git/FETCH_HEAD" "$STUB_PO/.git/FETCH_HEAD"
run '' --live
t_eq "the control: both clones in sync" 0 "$RC"
t_has "...says so, per repo" "$(out)" "  ok: project-init: $STUB_PI is in sync with origin/main (fetched just now)"
t_eq "...and the dry run left no FETCH_HEAD in either clone (a dry run writes nothing to an up-to-date box)" "" "$(ls "$STUB_PI/.git/FETCH_HEAD" "$STUB_PO/.git/FETCH_HEAD" 2>/dev/null)"
xadvance "$STUB_PO"
t_eq "origin moved on, the clone's last-fetched ref still says in sync" "" "$(git -C "$STUB_PO" rev-list HEAD..origin/main)"
: > "$LOGF"
run '' --apply --live
t_eq "a clone behind: the deploy fails" 1 "$RC"
t_has "...in preflight" "$(out)" "PREFLIGHT FAILED (1) — nothing was installed"
t_has "...naming the repo, its path and how far behind" "$(out)" "  FAIL: projects-orchestrator: $STUB_PO is not in sync with origin/main (ahead 0, behind 1)"
t_eq "...with the pull as its fix" "  fix: git -C '$STUB_PO' pull --ff-only origin main" "$(grep -A1 '^  FAIL: projects-orchestrator: .* not in sync' "$T/out.txt" | sed -n 2p)"
t_eq "...before anything was written" "" "$(applied)"
t_exit "...every FAIL followed by its fix line" 0 fixfollows
sh -c "$(grep -A1 '^  FAIL: projects-orchestrator: .* not in sync' "$T/out.txt" | sed -n 2p | sed 's/^  fix: //')" >/dev/null 2>&1
run '' --live
t_eq "that fix, run as printed, clears it" 0 "$RC"
fixture xrfetch; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
xgit "$STUB_PI"; xgit "$STUB_PO"; git -C "$STUB_PI" remote set-url origin "$T/unreachable.git"
refuse "a clone whose origin cannot be fetched" "  FAIL: project-init: cannot fetch origin/main in $STUB_PI, so whether the clone is current cannot be confirmed"
t_eq "...with the fetch as its fix" "  fix: git -C '$STUB_PI' fetch origin main" "$(grep -A1 '^  FAIL: project-init: cannot fetch' "$T/out.txt" | sed -n 2p)"
fixture xrahead; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install
xgit "$STUB_PI"; xgit "$STUB_PO"; printf 'local\n' > "$STUB_PI/local.txt"
git -C "$STUB_PI" add -A && git -C "$STUB_PI" -c user.name=t -c user.email=t@t commit -qm local
refuse "a clone ahead of its origin" "project-init: $STUB_PI is not in sync with origin/main (ahead 1, behind 0)"
fixture xrnotgit; STUB_PI="$T/pi"; export STUB_PI; xrepo "$STUB_PI" install
run '' --live
t_has "a clone that is not a git checkout is said so, not passed silently" "$(out)" "  note: project-init: $STUB_PI is not a git checkout, so its sync with origin/main was not checked"

t_section "a child's apply-time refusal becomes deploy's own FAIL and fix lines (harbor#736)"
xrfail2() { fixture "$1"; STUB_PI="$T/pi"; STUB_PO="$T/po"; export STUB_PI STUB_PO; xrepo "$STUB_PI" install; xrepo "$STUB_PO" install; echo 1 > "$STUB_PO/.rc.apply"; }
fixture xrctl; STUB_FAIL=floor-install.sh:apply; export STUB_FAIL; run 'y\nn\n' --apply --live; unset STUB_FAIL
t_has "the control: a Harbor installer that failed DID print FAIL and fix lines, so deploy still points at them" "$(out)" "see its FAIL and fix lines above"
xrfail2 xrline
printf '  FAIL: not in sync with origin/main (ahead 0, behind 5)\n  fix: git -C /x/po pull --ff-only origin main\n' > "$STUB_PO/.out.apply"
run 'y\nn\n' --apply --live
t_eq "a child refusing at apply fails the deploy" 1 "$RC"
t_eq "...deploy's FAIL carries the child's reason" "  FAIL: stopped at: projects-orchestrator: just install --apply (rc=1) — not in sync with origin/main (ahead 0, behind 5) (later steps did not run)" \
  "$(grep '^  FAIL: stopped at' "$T/out.txt")"
t_eq "...and its fix is the child's" "  fix: git -C /x/po pull --ff-only origin main" "$(grep -A1 '^  FAIL: stopped at' "$T/out.txt" | sed -n 2p)"
t_hasnt "...no pointer to lines that are not there" "$(out)" "see its FAIL and fix lines above"
t_has "...and the same two lines are in deploy's log file" "$(dlog)" "FAIL: stopped at: projects-orchestrator: just install --apply (rc=1) — not in sync with origin/main (ahead 0, behind 5)"
t_exit "...every FAIL followed by its fix line" 0 fixfollows
xrfail2 xrlegacy
printf 'refusing --apply:\n    - not in sync with origin/main (ahead 0, behind 5)\n    - on '"'"'feat/x'"'"', not main\n' > "$STUB_PO/.out.apply"
run 'y\nn\n' --apply --live
t_has "an older child's report: its first reason, in deploy's FAIL" "$(out)" "  FAIL: stopped at: projects-orchestrator: just install --apply (rc=1) — not in sync with origin/main (ahead 0, behind 5) (later steps did not run)"
t_has "...its second as a FAIL of its own" "$(out)" "  FAIL: projects-orchestrator: on 'feat/x', not main"
t_has "...a fix that says the child gave none, and where its dry run is" "$(out)" "  fix: none automatic — see the output above, where projects-orchestrator gave no fix; \`just install\` in $STUB_PO is its dry run"
t_exit "...every FAIL followed by its fix line" 0 fixfollows
xrfail2 xrsilent
run 'y\nn\n' --apply --live
t_has "a child that printed neither says so, not 'see its lines above'" "$(out)" "  FAIL: stopped at: projects-orchestrator: just install --apply (rc=1) — later steps did not run, and it printed no FAIL or fix line"
t_hasnt "...and does not point at lines that are not there" "$(out)" "see its FAIL and fix lines above"
t_exit "...every FAIL followed by its fix line" 0 fixfollows
unset STUB_PI STUB_PO
t_done
