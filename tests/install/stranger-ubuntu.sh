#!/usr/bin/env sh
# stranger-ubuntu.sh (harbor#1149, #831): a person who is not the operator installs Harbor on a clean
# Ubuntu box (WSL2 stand-in): the CORE EXPORT of HEAD (the path set `deploy-push.sh --dry-run` stages, what a public
# repo carries), fresh non-root user, no git identity, no ~/.claude.
# Needs a docker daemon; without one it FAILS (exit 2), never skips. STRANGER_KEEP_GOING=1 runs every step.
# Not *-test.sh on purpose: the suite pool's runner has no docker; .github/workflows/stranger-install.yml (manual dispatch) runs it.
# The default is the stranger who has NOT started Claude Code: no ~/.claude at all, and `harbor scope install` is what makes
# settings.json (harbor#457). STRANGER_CLAUDE_FIRST_RUN=1 adds step 03b, the machine where `claude` already ran once and wrote it.
# A step that fails on a missing settings.json names it as the precondition; with STRANGER_KEEP_GOING=1 every later step reports that precondition instead of its own downstream error.
REAL_HOME="$HOME"
. "$(dirname "$0")/../lib/core.sh"; t_init
# t_init sandboxes HOME; docker still needs the real context (colima socket).
export DOCKER_CONFIG="${DOCKER_CONFIG:-$REAL_HOME/.docker}"
DOCKER="${DOCKER:-docker}"; command -v "$DOCKER" >/dev/null 2>&1 || DOCKER=/opt/homebrew/bin/docker
IMAGE="${STRANGER_IMAGE:-ubuntu:24.04}"
CT="harbor-stranger-$$"
"$DOCKER" info >/dev/null 2>&1 || { echo "stranger-ubuntu: no docker daemon (colima start); refusing to substitute a weaker check" >&2; exit 2; }
trap '"$DOCKER" rm -f "$CT" >/dev/null 2>&1; chmod -R u+w "$T_TMP" 2>/dev/null; rm -rf "$T_TMP"' EXIT

# The core export only: the path set deploy-push stages (its stdout), taken from HEAD, committed under a throwaway
# identity into a repo the stranger clones. The leak gate is deploy-push's own verdict, not this test's: the dry run
# lists the set whether or not it is green, and a refusal (no list, no "dry run:" note) stops here.
mkdir -p "$T_TMP/raw" "$T_TMP/export" "$T_TMP/private-empty"
git -C "$T_ROOT" archive HEAD | tar -x -C "$T_TMP/raw" || { echo "git archive HEAD failed" >&2; exit 2; }
HARBOR_SCOPE_PRIVATE="$T_TMP/private-empty" sh "$T_ROOT/bin/deploy-push.sh" --dry-run >"$T_TMP/core.files" 2>"$T_TMP/dry-run.err" || :
_n="$(wc -l <"$T_TMP/core.files" | tr -d ' ')"
{ [ "$_n" -gt 0 ] && grep -q "dry run: $_n core file" "$T_TMP/dry-run.err"; } ||
  { cat "$T_TMP/dry-run.err" >&2; echo "stranger-ubuntu: deploy-push --dry-run gave no core set; refusing to fall back to the whole tree" >&2; exit 2; }
tar -cf - -C "$T_TMP/raw" -T "$T_TMP/core.files" | tar -xf - -C "$T_TMP/export"
echo "stranger-ubuntu: installing from the core export ($_n files)" >&2
git -C "$T_TMP/export" init -q -b main
git -C "$T_TMP/export" add -A
git -C "$T_TMP/export" -c user.name=x -c user.email=x@x commit -qm export
git clone -q --bare "$T_TMP/export" "$T_TMP/core.git"
tar -C "$T_TMP" -cf "$T_TMP/core.tar" core.git

"$DOCKER" run -d --name "$CT" "$IMAGE" sleep 3600 >/dev/null || { echo "docker run $IMAGE failed" >&2; exit 2; }
"$DOCKER" cp "$T_TMP/core.tar" "$CT:/tmp/core.tar"

PRECOND=''  # name of the first step that failed on the missing first-run settings.json (harbor#457)
step() { # <name> <user> <script> - runs in the container; the name is what a failure reports
  _n="$1"; _u="$2"; _h=/home/$_u; [ "$_u" != root ] || _h=/root
  t_section "$_n"
  if [ -n "$PRECOND" ]; then
    t_fail "step '$_n' not run: precondition failed at step '$PRECOND' (no ~/.claude/settings.json: harbor scope install makes it, harbor#457)"; return 0
  fi
  # $4 = answers typed at the prompt: deploy reads /dev/tty on purpose, so `script` gives it a real pty.
  if [ -n "${4:-}" ]; then _cmd="script -qec '$3' /dev/null"; else _cmd="$3"; fi
  if printf '%s' "${4:-}" | "$DOCKER" exec -i -u "$_u" -e HOME="$_h" -w "$_h" "$CT" sh -c "$_cmd" >"$T_TMP/$_n.log" 2>&1; then
    t_pass
  else
    _rc=$?; t_fail "step '$_n' failed (exit $_rc)"; tail -15 "$T_TMP/$_n.log" >&2
    if grep -q 'no settings.json in' "$T_TMP/$_n.log"; then PRECOND="$_n"; fi
    [ "${STRANGER_KEEP_GOING:-0}" = 1 ] || { echo "stranger-ubuntu: FAILED at step: $_n" >&2; exit 1; }
  fi
}

step 01-prereqs root 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git ca-certificates sudo jq >/dev/null'
step 02-user root 'useradd -m -s /bin/sh stranger
  [ -z "$(su stranger -c "git config --global user.name" 2>/dev/null)" ] && [ ! -e /home/stranger/.claude ]'
step 03-clone stranger 'mkdir -p ~/port && tar -C /tmp -xf /tmp/core.tar && git clone -q /tmp/core.git ~/port/harbor'
# Precondition (harbor#457): settings.json. By default the stranger has none and scope install makes it (04c); with
# STRANGER_CLAUDE_FIRST_RUN=1 a first `claude` run wrote it and scope install must leave it be.
if [ "${STRANGER_CLAUDE_FIRST_RUN:-0}" = 1 ]; then step 03b-claude-first-run stranger 'mkdir -p ~/.claude && echo "{}" > ~/.claude/settings.json'
else echo "stranger-ubuntu: no Claude Code first run (STRANGER_CLAUDE_FIRST_RUN=1 adds it): scope install makes settings.json" >&2; fi
step 04-scope-install stranger 'sh ~/port/harbor/bin/harbor scope install && test -f ~/port/harbor-private/harbor.toml'
step 04c-settings-json stranger 'test "$(cat ~/.claude/settings.json)" = "{}" && sh ~/port/harbor/bin/harbor scope install | grep -q "kept .*settings.json"'
step 04b-seeded-core stranger 'test "$(sh ~/port/harbor/bin/roots.sh --conf components)" = core'
# scope install seeds components = ["core"], so a bare deploy plans core only, no private repos (harbor#1149).
# bootstrap (harbor#966) reads that layer: core names nothing to clone, so it ends on deploy's dry run having cloned no
# repository, installed no uv or just and used no gh. The image has no gh and no curl, so a bootstrap that wanted either fails here.
step 04c-bootstrap stranger 'sh ~/port/harbor/bin/bootstrap.sh >/tmp/boot.txt 2>&1; rc=$?; cat /tmp/boot.txt
  [ "$rc" -eq 0 ] && grep -q "nothing is cloned" /tmp/boot.txt && grep -q "^deploy: [0-9]* ok, 0 failed" /tmp/boot.txt &&
  ! command -v gh >/dev/null && ! command -v curl >/dev/null && [ ! -e ~/.local/bin/uv ] && [ ! -e ~/.local/bin/just ] &&
  [ "$(find ~/port -maxdepth 2 -name .git | wc -l | tr -d " ")" = 1 ]'
step 05-deploy-plan stranger 'sh ~/port/harbor/bin/deploy.sh --live >/tmp/plan.txt 2>&1; rc=$?; cat /tmp/plan.txt; [ "$rc" -eq 0 ] && grep -q "components: core" /tmp/plan.txt && ! grep -q project-init /tmp/plan.txt'
step 06-deploy-apply stranger "sh ~/port/harbor/bin/deploy.sh --apply --live" 'y
'
# Exit 0 proves nothing: the lockdown file and its marketplace must exist with the keys it claims (a vacuous green otherwise).
step 07-managed-mods root 'sh /home/stranger/port/harbor/bin/managed-mods.sh &&
  jq -e ".pluginConfigs[\"cc-plugin-sec-default@builtin\"].options.allowManagedModsOnly == true and .disableSideloadFlags == true" /etc/claude-code/managed-settings.json >/dev/null &&
  test -f /etc/claude-code/harbor-mods/.claude-plugin/marketplace.json'
# Confinement (harbor#1298): composed as the stranger, no Darwin-only key on Linux. In an unprivileged container
# bubblewrap cannot start, so the install must REFUSE, naming the fix, and leave the managed file without a sandbox
# block: with failIfUnavailable, installing here would refuse every session (#1297 round 5).
step 07c-confinement root 'su stranger -c "sh /home/stranger/port/harbor/bin/deploy-confinement.sh --compose" > /tmp/block.json &&
  jq -e ".enabled == true and .network.allowManagedDomainsOnly == true and .filesystem.allowWrite[0] == \"/home/stranger/port\" and (has(\"enableWeakerNetworkIsolation\") | not)" /tmp/block.json >/dev/null &&
  ! SUDO_USER=stranger sh /home/stranger/port/harbor/bin/deploy-confinement.sh > /tmp/confine.log 2>&1 &&
  grep -qE "missing: bwrap|bubblewrap cannot start" /tmp/confine.log &&
  jq -e "(has(\"sandbox\") | not) and .disableSideloadFlags == true" /etc/claude-code/managed-settings.json >/dev/null'
# B8 pin is the owner's own act by design (floor-install.sh:458); it is part of a first install. Run from the checkout, as
# deploy spells it: it needs only the config dir, and a missing one is then named, not "cannot open".
step 07b-pin-instructions stranger 'sh ~/port/harbor/bin/pin-instructions.sh --apply --live'
step 08-check stranger 'sh ~/port/harbor/bin/harbor check --live'
step 09-verify stranger 'sh ~/port/harbor/bin/harbor verify'
t_done
