#!/usr/bin/env sh
# deploy.sh, part: harbor uninstall (deploy --only floor --uninstall, harbor#808) and the runtime-without-floor pin refusal
# (harbor#916). Split from tests/deploy/deploy/deploy.test.sh at the 500-line budget (tests/README.md T2); the throwaway repo
# and its stub installers are tests/install/deploy-fixture.sh's, as there.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE  # a run inside a session or a deploy must not decide a case
T_TMP="$(cd "$T_TMP" && pwd -P)"  # deploy reports the config dir physically (install-lib's il_target)
. "$(dirname "$0")/../../install/deploy-fixture.sh"
need_pty
t_section "harbor uninstall is deploy --only floor --uninstall: flags (harbor#808)"
fixture unflags
run '' --uninstall --live; t_eq "--uninstall without --only floor" 2 "$RC"
t_has "...names the one component it takes" "$(out)" "--uninstall takes --only floor"
run '' --only skills --uninstall --live; t_eq "--uninstall of a component with no uninstaller" 2 "$RC"
run '' --only floor,skills --uninstall --live; t_eq "--uninstall of the floor and another component" 2 "$RC"
run '' --only floor --uninstall --with-b6 --live; t_eq "--uninstall with an opt-in" 2 "$RC"
t_eq "no usage error ran anything (log bytes)" 0 "$(wc -c < "$LOGF" | tr -d ' ')"

# The REAL floor-uninstall, reading the real floor-install and runtime-install beside it, on a floor it
# recognises: floor-hook + guard-bash wired and present, a pin, the teeth; and a foreign hook it keeps.
unfloor() {
  cp "$T_ROOT/bin/admission-remove.sh" "$T_ROOT/bin/admission-install.sh" "$T_ROOT/bin/deploy-runtime-install.sh" "$REPO/bin/"
  git -C "$REPO" add bin/admission-remove.sh; commit_push realfloor
  mkdir -p "$C/bin"; printf '#!/bin/sh\nexit 0\n' > "$C/bin/admission-hook.sh"; cp "$C/bin/admission-hook.sh" "$C/bin/admission-bash.sh"
  printf 'x  bin/admission-bash.sh\n' > "$C/.helm-pins/admission-bash.sh.sha256"; printf 'teeth\n' > "$C/.helm-floor-teeth"
  jq -n --arg g "/bin/sh $C/bin/admission-hook.sh $C/bin/admission-bash.sh" --arg m "/bin/sh $H/mine.sh" \
    '{hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $g}, {type: "command", command: $m}]}]}}' > "$C/settings.json"
  cp "$C/settings.json" "$T/settings.before"
}
unmanifest() { # the two floor files' rows, and one row for a file the uninstall keeps (harbor#815)
  { printf '# .harbor-manifest (install standard §3, bin/deploy-install-lib.sh): <git-blob> <mode> <relpath> <installer> <commit>\n'
    for _f in admission-hook.sh admission-bash.sh; do printf '%s 100755 bin/%s floor-install -\n' "$(git hash-object "$C/bin/$_f")" "$_f"; done
    printf '%s 100644 lib/core.sh runtime-install -\n' "$(git hash-object "$C/bin/admission-hook.sh")"
  } > "$C/.harbor-manifest"
  cp "$C/.harbor-manifest" "$T/manifest.before"
}
t_section "harbor uninstall: a dry run plans through floor-uninstall's own dry run and removes nothing"
fixture undry; unfloor; run '' --only floor --uninstall --live
t_eq "the uninstall dry run" 0 "$RC"
t_has "it relays what floor-uninstall would remove" "$(out)" "  note: floor file to remove: bin/admission-bash.sh"
t_eq "...and removes nothing" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_has "its next step is the apply, which its own gate takes" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --only floor --uninstall --live"
t_eq "no installer ran" "" "$(applied)"
CC=1 run 'y\n' --only floor --uninstall --apply --live; CC=''
t_eq "inside a Claude session its --apply is refused up front" 1 "$RC"
t_has "...before any plan" "$(out)" "refused up front: running inside a Claude session"
t_eq "...and nothing is removed" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"

t_section "harbor uninstall --apply: snapshot first, remove, verify the floor is GONE, offer the snapshot back"
fixture unapply; unfloor; unmanifest; run 'y\n' --only floor --uninstall --apply --live
SNAPD="$(ls -d "$C"/backups/deploy-* 2>/dev/null | head -1)"
t_eq "the uninstall" 0 "$RC"
t_has "a snapshot was taken before the removal" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null)" "bin/admission-bash.sh"
t_eq "...recorded in the ledger deploy-restore.sh demands" 1 "$(grep -c "backups/${SNAPD##*/}/config.tgz" "$C/.helm-snapshots" 2>/dev/null || echo 0)"
t_eq "the floor's hook is unwired and the foreign one kept" "/bin/sh $H/mine.sh" "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command] | join(",")' "$C/settings.json")"
t_eq "the floor's files are gone from bin/" no "$([ -e "$C/bin/admission-bash.sh" ] && echo yes || echo no)"
t_has "the snapshot holds .harbor-manifest as it was" "$(tar -tzf "$SNAPD/config.tgz" 2>/dev/null)" ".harbor-manifest"
t_eq ".harbor-manifest drops the moved files' rows and keeps the rest (harbor#815)" \
  "$(grep ' lib/core.sh ' "$T/manifest.before")" "$(grep -v '^#' "$C/.harbor-manifest")"
t_has "verify reads the floor as absent, by floor-uninstall's own dry run" "$(out)" "  ok: the floor is gone: floor-uninstall's own dry run finds no hook and no file left to remove"
t_hasnt "...and floor-verify is not run on the floor it just removed" "$(out)" "floor-verify:"
t_has "the snapshot is offered back as the command that restores it" "$(out)" \
  "  note: next: sh '$REPO/bin/deploy-restore.sh' --apply --live --from '$SNAPD' --accept-loss"
t_has "the run keeps its log" "$(dlog)" "  ok: the floor is gone: "
_rcmd="$(sed -n "s|^  note: next: \(sh '$REPO/bin/deploy-restore.sh' .*\)$|\1|p" "$T/out.txt" | head -1)"
t_has "the restore command was printed, to run as printed" "$_rcmd" "/bin/deploy-restore.sh' --apply --live --from '$SNAPD' --accept-loss"
env -u CLAUDE_CONFIG_DIR HOME="$H" sh -c "$_rcmd" </dev/null >"$T/restore.out" 2>&1; _rrc=$?
t_eq "the printed restore command runs as printed" 0 "$_rrc"
t_eq "...and puts the floor's wiring back, byte for byte" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_eq "...and the floor's files" yes "$([ -f "$C/bin/admission-bash.sh" ] && [ -f "$C/.helm-pins/admission-bash.sh.sha256" ] && echo yes || echo no)"
t_eq "...and their .harbor-manifest rows, byte for byte (harbor#815)" "$(cat "$T/manifest.before")" "$(cat "$C/.harbor-manifest")"

t_section "harbor uninstall: a floor still present after the removal fails verify and offers the snapshot back"
fixture unfail; unfloor
printf '#!/bin/sh\ncase " $* " in *" --apply "*) printf MODIFIED > "$HOME/.claude/settings.json"; echo "  ok: stub removed nothing"; exit 0 ;; esac\necho "  note: hook to remove: PreToolUse: /bin/sh x/admission-bash.sh"\n' > "$REPO/bin/admission-remove.sh"
commit_push stubun; run 'y\ny\n' --only floor --uninstall --apply --live
t_eq "an uninstall that left the floor" 1 "$RC"
t_has "verify names it" "$(out)" "  FAIL: the floor is still present after floor-uninstall"
t_has "...relaying what is left" "$(out)" "  note: hook to remove: PreToolUse: /bin/sh x/admission-bash.sh"
t_has "the restore plan is deploy-restore.sh's, on this run's snapshot" "$(out)" "── restore · plan for $C (dry run: nothing is written)"
t_eq "accepting the restore puts settings.json back" "$(cat "$T/settings.before")" "$(cat "$C/settings.json")"
t_has "...and every check runs again on the restored box" "$(out)" "── deploy · re-check · every check again, on the restored box"
t_section "harbor#916 · runtime without floor refuses a pinned file it would replace, before any write"
fixture pin916
printf 'stale-pin\n' > "$C/.helm-pins/library-log.sh.sha256"
commit_push pin916; run '' --only runtime --apply --live
t_eq "--only runtime fails the preflight" 1 "$RC"
t_has "naming the pinned file" "$(out)" "would replace B6-pinned library-log.sh"
t_has "with the run that re-pins it" "$(out)" "--only runtime,floor"
t_has "refused in the preflight" "$(out)" "PREFLIGHT FAILED"
t_eq "so no installer applied anything" "" "$(applied)"
run '' --only runtime,floor --live
t_hasnt "with floor selected it is not refused" "$(out)" "would replace B6-pinned"
_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
_sha256 < "$REPO/bin/library-log.sh" > "$C/.helm-pins/library-log.sh.sha256"
run '' --only runtime --live
t_has "and a pin that already matches lets runtime go alone" "$(out)" "runtime replaces no B6-pinned file"
printf '#!/bin/sh\necho stub\n' > "$REPO/bin/deploy-runtime-install.sh"; commit_push nofiles916
run '' --only runtime --live
t_has "a runtime-install with no FILES line is a FAIL, never a pass" "$(out)" "cannot read runtime-install's FILES"

fixture unpre; unfloor
printf '#!/bin/sh\necho "  FAIL: stub: cannot read the floor payload"; echo "  fix: none automatic — see the stub"; exit 1\n' > "$REPO/bin/admission-remove.sh"
commit_push stubpre; run '' --only floor --uninstall --live
t_eq "a floor-uninstall dry run that refuses fails the preflight" 1 "$RC"
t_has "...saying so" "$(out)" "PREFLIGHT FAILED"
t_has "...relaying its FAIL line" "$(out)" "  FAIL: stub: cannot read the floor payload"
t_done
t_done
