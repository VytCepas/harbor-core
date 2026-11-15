#!/usr/bin/env sh
# propose.test.sh (harbor#1278, control member.tools-propose) — `member-tools.sh propose <tool>` queues, and the next push opens ONE issue on the hub repo through a fake `gh`
# that records its argv and body: the exact call is asserted, nothing but `issue create` is ever run, and nothing is written to the hub. No GitHub is called.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/member-tools.sh"
H="$T_TMP/home"; CFG="$H/.claude"; BARE="$T_TMP/remote.git"; XS="$T_TMP/xdg"; CALLS="$T_TMP/gh-calls"; GHBIN="$T_TMP/ghbin"
mkdir -p "$H" "$XS" "$GHBIN"
cat > "$GHBIN/gh" <<'SH'
#!/bin/sh
# a fake gh: one line per argument into the calls file, the body file's text after it; fails when GH_FAKE_FAIL is set
{ printf 'CALL'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'
  while [ $# -gt 0 ]; do [ "$1" = --body-file ] && { sed 's/^/BODY /' "$2"; }; shift; done; } >> "$GH_FAKE_LOG"
[ -z "${GH_FAKE_FAIL:-}" ] || exit 1
echo "https://example.invalid/issues/1"
SH
chmod +x "$GHBIN/gh"
export HOME="$H" XDG_STATE_HOME="$XS" HARBOR_MEMBER_LOGIN=someone HARBOR_HUB_REPO=acme/hub HARBOR_HUB_TOOLS_REMOTE="$BARE" GH_FAKE_LOG="$CALLS" PATH="$GHBIN:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR
skill() { mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\ndescription: A scratch skill. USE WHEN a test needs one.\n---\n\n# %s\n' "$2" "$2" > "$1/skills/$2/SKILL.md"; }
tools() { _o="$(sh "$S" "$@" 2>"$T_TMP/err")" && _rc=0 || _rc=$?; OUT="$_o"; ERR="$(cat "$T_TMP/err")"; RC=$_rc; }
rm -rf "$BARE"; git init -q --bare -b main "$BARE"; : > "$CALLS"
skill "$CFG" mine; tools push >/dev/null

t_section "1 - propose queues, it does not call out"
tools propose mine
t_eq "propose exits 0" 0 "$RC"; t_has "it says it queued, under its id" "$OUT$ERR" "member.tools-propose: queued skills/mine"
t_eq "gh was not called by propose" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
t_eq "the request is a file in the personal place" yes "$([ -f "$CFG/.harbor-tools/propose/skills_mine" ] && echo yes || echo no)"

t_section "2 - the next push opens one issue with the exact call"
tools push
C="$(git -C "$BARE" rev-parse main)"
t_eq "gh ran once" 1 "$(grep -c '^CALL' "$CALLS")"
t_eq "...as exactly: issue create, the hub repo, a title naming tool and login, a body file" 1 \
  "$(grep -c '^CALL \[issue\] \[create\] \[--repo\] \[acme/hub\] \[--title\] \[tool proposal skills/mine from someone\] \[--body-file\] \[[^]]*\]$' "$CALLS")"
t_eq "the body names the personal repo" 1 "$(grep -c '^BODY Personal repo: acme/tools-someone$' "$CALLS")"
t_eq "...the tool" 1 "$(grep -c '^BODY Tool: skills/mine$' "$CALLS")"
t_eq "...and the commit that is on the remote" 1 "$(grep -c "^BODY Commit: $C\$" "$CALLS")"
t_eq "nothing but issue create was ever run" 0 "$(grep '^CALL' "$CALLS" | grep -vc '^CALL \[issue\] \[create\]')"
t_eq "the request is consumed" no "$([ -f "$CFG/.harbor-tools/propose/skills_mine" ] && echo yes || echo no)"
t_has "the person is told once, under the id" "$ERR" "member.tools-sync: opened a hub issue proposing skills/mine"
tools propose mine; tools push
t_eq "the same commit is never proposed twice" 1 "$(grep -c '^CALL' "$CALLS")"
printf 'v2\n' >> "$CFG/skills/mine/SKILL.md"; tools push; tools propose mine --note "better now"; tools push
t_eq "a new commit of the tool is a new proposal" 2 "$(grep -c '^CALL' "$CALLS")"
t_eq "...with the note" 1 "$(grep -c '^BODY Note: better now$' "$CALLS")"

t_section "3 - a failed call stays queued; refusals"
: > "$CALLS"; printf 'v3\n' >> "$CFG/skills/mine/SKILL.md"; tools propose mine
GH_FAKE_FAIL=1; export GH_FAKE_FAIL; tools push; unset GH_FAKE_FAIL
t_eq "a gh that fails: the hook still exits 0" 0 "$RC"
t_eq "...and the request stays for the next turn" yes "$([ -f "$CFG/.harbor-tools/propose/skills_mine" ] && echo yes || echo no)"
tools push; t_eq "the next push sends it" 1 "$(grep -c '^CALL .*issue.*create' "$CALLS" | awk '{print ($1 >= 1) ? 1 : 0}')"
tools propose nothere; t_eq "a tool that is not there is refused" 1 "$RC"
mkdir -p "$CFG/agents"; printf 'a\n' > "$CFG/agents/helper.md"; tools propose agents/helper; t_eq "an agent cannot go to the hub, only a skill" 1 "$RC"
mkdir -p "$CFG/.harbor-packs"; printf '# source\thub\nF\tskills/taken/SKILL.md\n' > "$CFG/.harbor-packs/hub-p.tsv"; skill "$CFG" taken
tools propose taken; t_eq "a name a hub pack holds is refused" 1 "$RC"
skill "$CFG" bad; printf -- '---\nname: bad\nhooks: x\n---\n' > "$CFG/skills/bad/SKILL.md"; tools propose bad; t_eq "a skill with a hooks: key is refused" 1 "$RC"
tools propose '../x'; t_eq "a path is refused" 1 "$RC"
t_exit "no tool named is usage" 2 sh "$S" propose
t_done
