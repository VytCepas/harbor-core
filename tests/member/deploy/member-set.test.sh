#!/usr/bin/env sh
# deploy.sh --member --pin (harbor#1278, R8, R9, R10): the REAL deploy in the deploy suites' throwaway repo, its installers stubbed. No prompt is
# reached, because the run is unattended; these are the very flags member-install.sh passes.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
T_TMP="$(cd "$T_TMP" && pwd -P)"
. "$T_ROOT/tests/install/deploy-fixture.sh"
member_fixture() { # <case>: a member box: no floor yet, the checkout detached at a pin behind main
  fixture "$1"; rm -rf "$C/.helm-pins" "$C/.helm-instructions.sha256"
  OLD="$(git -C "$REPO" rev-parse HEAD~1)"; TIP="$(git -C "$REPO" rev-parse HEAD)"
  git -C "$REPO" checkout -q --detach "$OLD"
  SNAPF="$T/snap"; : > "$SNAPF"
}
mrun() { HARBOR_DEPLOY_UNATTENDED=1 HARBOR_DEPLOY_SNAPSHOT="$SNAPF"; export HARBOR_DEPLOY_UNATTENDED HARBOR_DEPLOY_SNAPSHOT; run '' --apply --live --member --pin "$OLD" --unattended "$@"; }

t_section "the flags"
member_fixture flags
run '' --live --member; t_eq "--member alone" 2 "$RC"
run '' --live --pin "$OLD"; t_eq "--pin alone" 2 "$RC"; t_has "...says they go together" "$(out)" 'go together'
run '' --live --member --pin abc; t_eq "a short pin" 2 "$RC"
run '' --live --member --pin main; t_eq "a branch name" 2 "$RC"
run '' --live --member --pin "$OLD" --only floor; t_eq "--only can't put the floor back" 2 "$RC"
run '' --live --member --pin "$OLD" --with-b6; t_eq "--with-b6 either" 2 "$RC"
run '' --live --member --pin "$OLD"; t_eq "a dry run at the pin passes" 0 "$RC"
t_has "...naming the set" "$(out)" 'the member set'

t_section "the member set: no user-tier floor (R9)"
member_fixture apply; mrun; t_eq "an unattended apply at a pin behind main exits 0 (R8, R10)" 0 "$RC"
t_has "it says it is at the pin" "$(out)" "at the pinned commit $OLD"
A="$(applied)"
for s in policy-constitution-install.sh deploy-shim-install.sh deploy-runtime-install.sh skill-install.sh context-injection-install.sh; do t_has "$s runs" "$A" "$s"; done
for s in admission-install.sh deploy-harden.sh prod-guard-install.sh; do t_hasnt "$s never runs" "$A" "$s"; done
t_has "the constitution's branch gate is handed the pin, which stands in for main on a member box" "$(grep '^policy-constitution-install.sh' "$LOGF" | tail -1)" "--pin $OLD"
t_eq "no user-tier floor file is planned either" 0 "$(grep -c '^admission-install.sh\|^deploy-harden.sh\|^prod-guard-install.sh' "$LOGF")"
t_eq "no scheduled job is touched: each needs its own yes" 0 "$(grep -c '^deploy-launchd-sync.sh' "$LOGF")"
t_eq "no B8 pin: nothing here reads it" 0 "$(pins)"
t_hasnt "floor-verify doesn't run, or it would fail on purpose" "$(out)" 'floor-verify'
t_has "verify reads what a member box should have" "$(out)" 'no user-tier floor'
t_has "the snapshot id reached the caller" "$(cat "$SNAPF")" backups/deploy-

t_section "what stays refused at a pin"
member_fixture wrong; git -C "$REPO" checkout -q --detach "$TIP"; mrun
t_eq "HEAD isn't the pin" 1 "$RC"; t_has "...named" "$(out)" 'not the pinned commit'
t_eq "...nothing installed" '' "$(applied)"
member_fixture dirty; printf x >> "$REPO/bin/harbor"; mrun
t_eq "a dirty checkout" 1 "$RC"; t_has "...named" "$(out)" 'uncommitted changes'
member_fixture floor; mkdir -p "$C/.helm-pins"; mrun
t_eq "a box with B6 pins has a user-tier floor" 1 "$RC"; t_has "...named, with its way out" "$(out)" '--only floor --uninstall'
member_fixture wired; printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh ~/.claude/bin/admission-hook.sh ~/.claude/bin/admission-bash.sh"}]}]}}' > "$C/settings.json"; mrun
t_eq "a wired guard is one too" 1 "$RC"

t_section "the write zone can't widen the set (R11)"
PV="$T_TMP/pv"; mkdir -p "$PV"; HARBOR_SCOPE_PRIVATE="$PV"; export HARBOR_SCOPE_PRIVATE
printf 'components = ["prod-guard"]\n' > "$PV/harbor.toml"
member_fixture toml; mrun; t_eq "harbor.toml naming a component" 0 "$RC"
t_hasnt "...is not read" "$(applied)" 'prod-guard'
unset HARBOR_SCOPE_PRIVATE

t_section "rollback (R10)"
STUB_STAMP_RC=1; export STUB_STAMP_RC
fixture stand; run '' --live; t_eq "CONTROL: standalone refuses a move back" 1 "$RC"
t_has "...as lost work" "$(out)" 'would REMOVE installed work'
member_fixture back; mrun; t_eq "the member path takes an older pin" 0 "$RC"
t_has "...warning what it removes, not hiding it" "$(out)" 'would REMOVE installed work'
t_has "...and tells the installers so" "$(grep '^deploy-runtime-install.sh' "$LOGF" | tail -1)" '--accept-loss'
unset STUB_STAMP_RC
unset HARBOR_DEPLOY_UNATTENDED HARBOR_DEPLOY_SNAPSHOT; fixture stand2; run '' --live; t_hasnt "CONTROL: an operator's deploy never hands the constitution a pin" "$(grep '^policy-constitution-install.sh' "$LOGF")" '--pin'
t_done
