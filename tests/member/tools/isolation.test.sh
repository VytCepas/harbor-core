#!/usr/bin/env sh
# isolation.test.sh (harbor#1278, control member.tools-sync) — nothing the agent can write decides what git runs or where the token goes.
# The agent owns ~/.gitconfig and ~/.local/state/harbor/tools, so each attack plants there, with a marker file the planted code writes if it ever runs:
#   1 core.fsmonitor   2 core.hooksPath with a pre-push hook   3 url.<evil>.insteadOf redirecting the remote   4 a hook that reads the token header
#   5 a planted installed.tsv whose rel climbs out of the config dir into an rm -rf
# Then the two paths a managed hook takes: the url-scoped header, and `propose` under the pinned PATH, where gh is not found and hub-board.sh sends.
# No GitHub: a local bare repo is the remote, a fake `secret` hands over a fake token, a stub hub-board.sh records its argv.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/member-tools.sh"
H="$T_TMP/home"; CFG="$H/.claude"; BARE="$T_TMP/remote.git"; EVIL="$T_TMP/evil.git"; XS="$H/.local/state"; ST="$XS/harbor/tools"; MARK="$T_TMP/mark"
mkdir -p "$H" "$MARK"
export HOME="$H" XDG_STATE_HOME="$XS" HARBOR_MEMBER_LOGIN=someone HARBOR_HUB_REPO=acme/hub HARBOR_HUB_TOOLS_REMOTE="$BARE"
unset CLAUDE_CONFIG_DIR GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM   # the script must set these itself: that is what is tested
tg() { GIT_CONFIG_GLOBAL=/dev/null git -c user.name=t -c user.email=t@t "$@"; }   # the test's own git never reads the planted config
skill() { mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\ndescription: A scratch skill. USE WHEN a test needs one.\n---\n\n# %s\n' "$2" "$2" > "$1/skills/$2/SKILL.md"; }
tools() { _o="$(sh "$S" "$@" 2>"$T_TMP/err")" && _rc=0 || _rc=$?; OUT="$_o"; ERR="$(cat "$T_TMP/err")"; RC=$_rc; }
fresh() { rm -rf "$H/.claude" "$H/.local" "$H/.gitconfig" "$MARK" "$BARE" "$EVIL"; mkdir -p "$H" "$MARK"; git init -q --bare -b main "$BARE"; git init -q --bare -b main "$EVIL"; }
# plant <what>: writes the attack into ~/.gitconfig and into a legacy persistent clone of the state dir, where the agent could also write
plant_legacy() { mkdir -p "$ST/repo"; git init -q "$ST/repo" 2>/dev/null; }
mkhook() { mkdir -p "$T_TMP/hooks"; printf '#!/bin/sh\n{ echo ran "$0" "$@"; env; } > "%s/%s"\nexit 0\n' "$MARK" "$1" > "$T_TMP/hooks/$2"; chmod +x "$T_TMP/hooks/$2"; }
ran() { [ -e "$MARK/$1" ] && echo ran || echo clean; }
work() { skill "$CFG" mine; tools push; }   # a new skill: the push clones, adds, diffs, commits and pushes

t_section "1 - core.fsmonitor in ~/.gitconfig or the legacy state clone never runs"
fresh; printf '#!/bin/sh\necho fsmonitor > "%s/fsmonitor"\nexit 0\n' "$MARK" > "$T_TMP/fsm.sh"; chmod +x "$T_TMP/fsm.sh"
printf '[core]\n\tfsmonitor = %s\n' "$T_TMP/fsm.sh" > "$H/.gitconfig"
plant_legacy; git -C "$ST/repo" config core.fsmonitor "$T_TMP/fsm.sh"
work
t_eq "the push worked" yes "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "the planted fsmonitor never ran" clean "$(ran fsmonitor)"
# CONTROL: the marker can be written by the same config when git is not isolated
rm -rf "$MARK"; mkdir -p "$MARK"; rm -rf "$T_TMP/ctl"; git init -q "$T_TMP/ctl"; ( cd "$T_TMP/ctl" && printf x > f && git add f ) 2>/dev/null
HOME="$H" git -C "$T_TMP/ctl" status >/dev/null 2>&1
t_eq "CONTROL: an unisolated git with that config runs the planted fsmonitor" ran "$(ran fsmonitor)"

t_section "2 - core.hooksPath with a pre-push hook never runs"
fresh; mkhook prepush pre-push; printf '[core]\n\thooksPath = %s\n' "$T_TMP/hooks" > "$H/.gitconfig"
plant_legacy; mkdir -p "$ST/repo/.git/hooks"; cp "$T_TMP/hooks/pre-push" "$ST/repo/.git/hooks/pre-push"; git -C "$ST/repo" config core.hooksPath "$T_TMP/hooks"
work
t_eq "the push worked" yes "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "the planted pre-push hook never ran" clean "$(ran prepush)"
rm -rf "$T_TMP/ctl2"; git init -q "$T_TMP/ctl2"; ( cd "$T_TMP/ctl2" && printf x > f && git add f && git -c user.name=t -c user.email=t@t commit -qm c && git push -q "$BARE" HEAD:refs/heads/ctl ) >/dev/null 2>&1
t_eq "CONTROL: an unisolated push with that config runs the hook" ran "$(ran prepush)"

t_section "3 - url.<evil>.insteadOf cannot redirect the remote"
fresh; printf '[url "%s"]\n\tinsteadOf = %s\n' "$EVIL" "$BARE" > "$H/.gitconfig"
plant_legacy; git -C "$ST/repo" config "url.$EVIL.insteadOf" "$BARE"
work
t_eq "the personal repo got the push" yes "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "the evil repo got nothing" 0 "$(git -C "$EVIL" for-each-ref | wc -l | tr -d ' ')"
rm -rf "$T_TMP/ctl3"; git init -q "$T_TMP/ctl3"; ( cd "$T_TMP/ctl3" && printf x > f && git add f && git -c user.name=t -c user.email=t@t commit -qm c && git push -q "$BARE" HEAD:refs/heads/ctl ) >/dev/null 2>&1
t_eq "CONTROL: an unisolated push with that config lands in the evil repo" 1 "$(git -C "$EVIL" for-each-ref | wc -l | tr -d ' ')"

t_section "4 - a hook cannot read the token"
fresh; mkdir -p "$T_TMP/fsec"; SECLOG="$T_TMP/secret-calls"; : > "$SECLOG"
cat > "$T_TMP/fsec/secret" <<SH
#!/bin/sh
# a fake bin/secret: run <ref> <VAR> -- <cmd...> hands the child a fake token in VAR
[ "\$1" = run ] || exit 1
echo "run \$2 \$3" >> "$SECLOG"; _v="\$3"; shift 4
exec env "\$_v=faketoken-0123456789" "\$@"
SH
mkhook tokenhook pre-push; printf '[core]\n\thooksPath = %s\n' "$T_TMP/hooks" > "$H/.gitconfig"
plant_legacy; git -C "$ST/repo" config core.hooksPath "$T_TMP/hooks"
HARBOR_ACCESS_SECRET_BIN="$T_TMP/fsec/secret"; export HARBOR_ACCESS_SECRET_BIN
work
t_eq "the push worked with the token path in use" yes "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "CONTROL: the token store was asked for the token (so the path under test ran)" 1 "$([ "$(grep -c '^run hub-token TOOLS_CREDENTIAL' "$SECLOG")" -ge 1 ] && echo 1 || echo 0)"
t_eq "the planted hook never ran" clean "$(ran tokenhook)"
t_eq "...so the token header is in no file it could have written" 0 "$(grep -rl 'Authorization: Basic\|faketoken' "$MARK" 2>/dev/null | wc -l | tr -d ' ')"
unset HARBOR_ACCESS_SECRET_BIN

t_section "5 - the header is scoped to the exact remote url, and is not in the environment otherwise"
U=https://github.com/acme/tools-someone.git
_env="$(TOOLS_CREDENTIAL=abc123 sh "$S" --child "$U" -c 'alias.zz=!env' zz 2>&1)"
t_has "the key is http.<url>.extraHeader" "$_env" "GIT_CONFIG_KEY_0=http.$U.extraHeader"
t_hasnt "never the unscoped http.extraHeader" "$_env" "GIT_CONFIG_KEY_0=http.extraHeader"
t_has "the value is the Basic header" "$_env" "GIT_CONFIG_VALUE_0=Authorization: Basic $(printf 'x-access-token:abc123' | base64)"
t_hasnt "the raw variable is gone before git starts" "$_env" "TOOLS_CREDENTIAL="
t_has "and git ignores user and system config" "$_env" "GIT_CONFIG_GLOBAL=/dev/null"
t_exit "a child call with no url is refused" 2 sh "$S" --child

t_section "6 - a planted installed.tsv cannot make the sync delete outside the personal place"
fresh; printf 'victim data\n' > "$H/victim"; printf 'other\n' > "$H/.claude-keep"; mkdir -p "$CFG/skills"
VH="$(. "$T_ROOT/bin/library-hub.sh"; hub_sha256 < "$H/victim")"
mkdir -p "$ST"; printf 'skills/../../victim\t%s\nskills/../skills\t%s\n' "$VH" "$VH" > "$ST/installed.tsv"
skill "$CFG" mine; tg -C "$T_TMP" init -q seedx 2>/dev/null
# the remote has a skill so a pull reaches the "dropped from the repo" loop
rm -rf "$T_TMP/seedx"; git init -q -b main "$T_TMP/seedx"; skill "$T_TMP/seedx" there; ( cd "$T_TMP/seedx" && tg add -A && tg commit -qm s && tg push -q "$BARE" HEAD:refs/heads/main )
tools pull; tools push
t_eq "the file outside the config dir is still there" yes "$([ -f "$H/victim" ] && echo yes || echo no)"
t_eq "the config dir's skills folder is still there" yes "$([ -d "$CFG/skills" ] && echo yes || echo no)"
t_eq "a good row still works: the remote skill landed" yes "$([ -f "$CFG/skills/there/SKILL.md" ] && echo yes || echo no)"
t_eq "the planted rows are not carried into the new record" 0 "$(grep -c '\.\.' "$ST/installed.tsv")"
printf 'agents/ok.md\tnothex\nskills/there\t%s extra\tx\n' "$VH" > "$ST/installed.tsv"; tools push
t_eq "a row with a bad hash is dropped, not trusted" 0 "$(grep -c 'nothex' "$ST/installed.tsv")"

t_section "7 - propose under a managed hook: PATH pinned, no gh, hub-board.sh sends"
fresh; : > "$T_TMP/gh-calls"; mkdir -p "$T_TMP/ghbin"
printf '#!/bin/sh\necho "gh $*" >> "%s/gh-calls"\n' "$T_TMP" > "$T_TMP/ghbin/gh"; chmod +x "$T_TMP/ghbin/gh"
skill "$CFG" mine; tools push; tools propose mine     # state: the tool is synced, a request is queued (no hub issue yet: gh is not on this PATH)
C="$(git -C "$BARE" rev-parse main)"
MM="$T_TMP/mm/harbor"; rm -rf "$T_TMP/mm"; mkdir -p "$MM/bin"; cp "$S" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/library-hub.sh" "$MM/bin/"; : > "$MM/bin/harbor-member-mode"
printf 'hub=acme/hub\nlogin=someone\nhome=%s\n' "$H" > "$MM/member.conf"
BL="$T_TMP/board-calls"; : > "$BL"
printf '#!/bin/sh\n{ printf "BOARD"; for a in "$@"; do printf " [%%s]" "$a"; done; printf "\\n"; sed "s/^/BODY /" "$5"; } >> "%s"\nprintf 201 > "$2/status"\n' "$BL" > "$MM/bin/hub-board.sh"
_o="$(env -i PATH="$T_TMP/ghbin:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T_TMP" HOME="$H" HARBOR_MEMBER_ROLE=member sh "$MM/bin/member-tools.sh" push 2>&1)"; _rc=$?
t_eq "the managed push exits 0" 0 "$_rc"
t_eq "hub-board.sh was called once, as: call <dir> POST /repos/<hub>/issues <body file>" 1 "$(grep -c '^BOARD \[call\] \[[^]]*\] \[POST\] \[/repos/acme/hub/issues\] \[[^]]*\]$' "$BL")"
t_eq "the body is JSON with the title" 1 "$(grep '^BODY ' "$BL" | sed 's/^BODY //' | jq -r '.title' | grep -c '^tool proposal skills/mine from someone$')"
t_eq "...naming the personal repo and the pushed commit" 1 "$(grep '^BODY ' "$BL" | sed 's/^BODY //' | jq -r '.body' | grep -c "^Commit: $C\$")"
t_eq "gh was never called, though one sat on the PATH given" 0 "$(wc -l < "$T_TMP/gh-calls" | tr -d ' ')"
t_has "the person is told once, under the id" "$_o" "member.tools-sync: opened a hub issue proposing skills/mine"
t_eq "the request is consumed" no "$([ -f "$CFG/.harbor-tools/propose/skills_mine" ] && echo yes || echo no)"
t_done
