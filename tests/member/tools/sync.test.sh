#!/usr/bin/env sh
# sync.test.sh (harbor#1278, control member.tools-sync) — bin/member-tools.sh on scratch repos: a local bare repo stands in for the personal repo, no GitHub is called.
# Pull lands the repo's tools, push sends the laptop's, an unreachable or missing repo changes nothing, a name a managed or hub install holds is skipped,
# a hooks: key, a symlink or the managed root as the target are refused, and the hub's token scope is not asked of this script.
. "$(dirname "$0")/../../lib/core.sh"; t_init
S="$T_ROOT/bin/member-tools.sh"
H="$T_TMP/home"; CFG="$H/.claude"; BARE="$T_TMP/remote.git"; XS="$T_TMP/xdg"
mkdir -p "$H" "$XS"
export HOME="$H" XDG_STATE_HOME="$XS" HARBOR_MEMBER_LOGIN=someone HARBOR_HUB_REPO=acme/hub HARBOR_HUB_TOOLS_REMOTE="$BARE"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR
ST="$XS/harbor/tools"
g() { git -c user.name=t -c user.email=t@t "$@"; }
skill() { # <root> <name> [extra front matter line]
  mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\ndescription: A scratch skill. USE WHEN a test needs one.\n%s---\n\n# %s\n' "$2" "${3:+$3
}" "$2" > "$1/skills/$2/SKILL.md"
}
tools() { _o="$(sh "$S" "$@" 2>"$T_TMP/err")" && _rc=0 || _rc=$?; OUT="$_o"; ERR="$(cat "$T_TMP/err")"; RC=$_rc; }
tools_at() { _r="$1"; shift; _keep="$HARBOR_HUB_TOOLS_REMOTE"; HARBOR_HUB_TOOLS_REMOTE="$_r"; tools "$@"; HARBOR_HUB_TOOLS_REMOTE="$_keep"; }
snap() { for _d in "$H" "$XS"; do ( cd "$_d" && find . -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort; find . -type d | LC_ALL=C sort ); done; }
seed() { # a remote with one skill and one command, as another laptop of the person pushed it
  rm -rf "$BARE" "$T_TMP/seed"; git init -q --bare -b main "$BARE"; git init -q -b main "$T_TMP/seed"
  skill "$T_TMP/seed" remote-skill; mkdir -p "$T_TMP/seed/commands"; printf 'do the thing\n' > "$T_TMP/seed/commands/thing.md"
  ( cd "$T_TMP/seed" && g add -A && g commit -qm seed && g push -q "$BARE" HEAD:main )
}

t_section "1 - pull lands the repo's tools in the personal place"
seed; rm -rf "$H/.claude" "$XS"; mkdir -p "$H"
tools pull
t_eq "pull exits 0" 0 "$RC"
t_eq "the skill is in <config>/skills" yes "$([ -f "$CFG/skills/remote-skill/SKILL.md" ] && echo yes || echo no)"
t_eq "the command is in <config>/commands" yes "$([ -f "$CFG/commands/thing.md" ] && echo yes || echo no)"
t_has "the note carries its control id" "$OUT" "member.tools-sync: updated from your personal repo"
tools pull; t_eq "a second pull says nothing" "" "$OUT"

t_section "2 - an unreachable or missing repo changes nothing on disk"
rm -rf "$H/.claude" "$XS"; seed; B0="$(snap)"
tools_at "$T_TMP/absent.git" pull
t_eq "missing repo: exit 0" 0 "$RC"; t_eq "...nothing on disk changed" "$B0" "$(snap)"
t_has "...and it says so, under its id" "$ERR" "member.tools-sync: the personal repo acme/tools-someone could not be reached"
skill "$CFG" mine; B0="$(snap)"
tools_at "$T_TMP/absent.git" push
t_eq "push to a missing repo exits 0" 0 "$RC"; t_eq "...and changes nothing on disk" "$B0" "$(snap)"
tools pull >/dev/null; tools push >/dev/null
B0="$(snap)"; rm -rf "$BARE.gone"; mv "$BARE" "$BARE.gone"; tools pull
t_eq "a remote that went away after a good sync: nothing changes" "$B0" "$(snap)"; mv "$BARE.gone" "$BARE"
# CONTROL: the same snapshot sees a change when there is one
printf x >> "$CFG/skills/mine/SKILL.md"; t_eq "CONTROL: the snapshot sees a real edit" 1 "$([ "$B0" != "$(snap)" ] && echo 1 || echo 0)"

t_section "3 - push sends what the laptop has, and only when something changed"
seed; rm -rf "$H/.claude" "$XS"; tools pull >/dev/null
skill "$CFG" mine
tools push; t_eq "push exits 0" 0 "$RC"; t_has "it says it saved, on stderr" "$ERR" "member.tools-sync: saved your tools to acme/tools-someone"
t_eq "the bare repo has the new skill" yes "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "and still has the old one" yes "$(git -C "$BARE" cat-file -e main:skills/remote-skill/SKILL.md 2>/dev/null && echo yes || echo no)"
N0="$(git -C "$BARE" rev-list --count main)"; tools push
t_eq "a push with no change makes no commit" "$N0" "$(git -C "$BARE" rev-list --count main)"
t_eq "...and says nothing" "" "$OUT$ERR"
tools_at "$T_TMP/absent.git" push; t_eq "an unchanged push never reaches for the network: an absent remote is not even noticed" "" "$OUT$ERR"
printf 'more\n' >> "$CFG/skills/mine/SKILL.md"; tools push
t_eq "an edit makes one commit" "$((N0 + 1))" "$(git -C "$BARE" rev-list --count main)"
rm -rf "$CFG/skills/mine"; tools push
t_eq "a tool the laptop removed leaves the repo" no "$(git -C "$BARE" cat-file -e main:skills/mine/SKILL.md 2>/dev/null && echo yes || echo no)"
t_eq "...while one it never held stays" yes "$(git -C "$BARE" cat-file -e main:skills/remote-skill/SKILL.md 2>/dev/null && echo yes || echo no)"
# a second laptop pulls it
rm -rf "$H/.claude" "$XS"; tools pull >/dev/null; t_eq "a fresh laptop gets the remote skill" yes "$([ -f "$CFG/skills/remote-skill/SKILL.md" ] && echo yes || echo no)"
# an empty remote: the first push creates main
rm -rf "$H/.claude" "$XS" "$BARE"; git init -q --bare -b main "$BARE"; skill "$CFG" first; tools push
t_eq "an empty personal repo takes the first push" yes "$(git -C "$BARE" cat-file -e main:skills/first/SKILL.md 2>/dev/null && echo yes || echo no)"

t_section "4 - local wins where both sides changed"
seed; rm -rf "$H/.claude" "$XS"; tools pull >/dev/null
printf 'local edit\n' >> "$CFG/skills/remote-skill/SKILL.md"
( cd "$T_TMP/seed" && printf 'remote edit\n' >> skills/remote-skill/SKILL.md && g commit -qam r && g push -q "$BARE" HEAD:main )
tools pull; t_has "the laptop's edit survives the pull" "$(cat "$CFG/skills/remote-skill/SKILL.md")" "local edit"
tools push; t_has "and the push sends it" "$(git -C "$BARE" show main:skills/remote-skill/SKILL.md)" "local edit"

t_section "5 - a name a managed, hub or core skill holds is skipped and said"
seed; rm -rf "$H/.claude" "$XS"
mkdir -p "$CFG/.harbor-packs"; printf '# source\thub\nF\tskills/hubheld/SKILL.md\n' > "$CFG/.harbor-packs/hub-x.tsv"
( cd "$T_TMP/seed" && skill . hubheld && skill . audit-claims && g add -A && g commit -qm clash && g push -q "$BARE" HEAD:main )
mkdir -p "$CFG/skills/hubheld"; printf 'the hub pack own file\n' > "$CFG/skills/hubheld/SKILL.md"
tools pull
t_has "the hub pack's skill is named in the note" "$OUT" "hubheld"
t_has "...as skipped by name" "$OUT" "skipped, a managed or hub tool has the name"
t_eq "the hub pack's file is untouched" "the hub pack own file" "$(cat "$CFG/skills/hubheld/SKILL.md")"
t_eq "a core skill's name is skipped too" no "$([ -e "$CFG/skills/audit-claims" ] && echo yes || echo no)"
tools push
t_eq "a clash is never pushed from the laptop" no "$(git -C "$BARE" log --format=%s -1 main -- skills/hubheld | grep -c . | awk '{print ($1 > 1)? "yes":"no"}')"
# CONTROL: the same repo with no hub manifest installs the name
rm -rf "$CFG/.harbor-packs" "$CFG/skills/hubheld" "$XS"; tools pull >/dev/null
t_eq "CONTROL: with no hub pack holding it, the name lands" yes "$([ -f "$CFG/skills/hubheld/SKILL.md" ] && echo yes || echo no)"

t_section "6 - personal hooks and unsafe items are refused"
seed; rm -rf "$H/.claude" "$XS"
( cd "$T_TMP/seed" && skill . hooked 'hooks: x' && skill . linked && ln -s /etc/hosts skills/linked/alias.md && mkdir -p hooks && printf 'x\n' > hooks/h.sh && printf '{}\n' > settings.json && g add -A && g commit -qm bad && g push -q "$BARE" HEAD:main )
tools pull
t_eq "a skill with a hooks: key is not installed" no "$([ -e "$CFG/skills/hooked" ] && echo yes || echo no)"
t_has "...and the reason is said" "$OUT" "hooked (its front matter has a hooks: key)"
t_eq "a skill holding a symlink is not installed" no "$([ -e "$CFG/skills/linked" ] && echo yes || echo no)"
t_eq "a hooks/ folder or settings.json in the repo lands nowhere" 0 "$(find "$H" -name h.sh -o -name settings.json | wc -l | tr -d ' ')"
skill "$CFG" localhook 'hooks: y'; tools push
t_eq "a local skill with a hooks: key is not pushed" no "$(git -C "$BARE" cat-file -e main:skills/localhook/SKILL.md 2>/dev/null && echo yes || echo no)"

t_section "7 - it never writes into the managed root"
seed; rm -rf "$H/.claude" "$XS"
MR="$T_TMP/managed"; mkdir -p "$MR/harbor/bin"; cp "$S" "$MR/harbor/bin/"; for f in library-log.sh library-hub.sh; do cp "$T_ROOT/bin/$f" "$MR/harbor/bin/"; done
: > "$MR/harbor/bin/harbor-member-mode"; printf 'hub=acme/hub\nlogin=someone\nhome=%s\n' "$H" > "$MR/harbor/member.conf"
_o="$(env -i PATH="$PATH" TMPDIR="$T_TMP" HOME="$H" CLAUDE_CONFIG_DIR="$MR/harbor/skills-home" sh "$MR/harbor/bin/member-tools.sh" pull 2>&1)"; _rc=$?
t_eq "a config dir inside the managed root is refused" 0 "$_rc"
t_has "...and said ($_o)" "$_o" "inside the managed root"
t_eq "nothing was written there" 0 "$(find "$MR/harbor" -newer "$MR/harbor/member.conf" -type f ! -name harbor-member-mode | wc -l | tr -d ' ')"
# the same refusal with a remote that works, so that dropping the refusal writes a file into the managed root (red on the file, not only on the words)
seed; rm -rf "$H/.claude" "$XS" "$T_TMP/m2"; M2="$T_TMP/m2/harbor"; mkdir -p "$M2/bin"; cp "$S" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/library-hub.sh" "$M2/bin/"
CLAUDE_CONFIG_DIR="$M2/cfg" sh "$M2/bin/member-tools.sh" pull > "$T_TMP/o2" 2> "$T_TMP/e2"; _rc=$?
t_eq "a config dir inside the managed root: the hook exits 0" 0 "$_rc"
t_eq "the remote skill was NOT written into the managed root" 0 "$(find "$M2" -name SKILL.md | wc -l | tr -d ' ')"
t_eq "nothing at all was created under the managed root but the copied scripts" 0 "$(find "$M2" -type f ! -path "$M2/bin/*" | wc -l | tr -d ' ')"
t_has "...and it says why" "$(cat "$T_TMP/e2")" "inside the managed root"
CLAUDE_CONFIG_DIR="$T_TMP/m2cfg" sh "$M2/bin/member-tools.sh" pull > /dev/null 2>&1
t_eq "CONTROL: the same copy and remote with a config dir outside the root installs the skill" yes "$([ -f "$T_TMP/m2cfg/skills/remote-skill/SKILL.md" ] && echo yes || echo no)"
t_eq "the script writes no hook and no settings file anywhere" 0 "$(find "$H" \( -name 'settings*.json' -o -path '*/hooks/*' \) | wc -l | tr -d ' ')"

t_section "8 - bounded and fail-open"
rm -rf "$H/.claude" "$XS"
cat > "$T_TMP/slowgit" <<'SH'
#!/bin/sh
sleep 30
SH
chmod +x "$T_TMP/slowgit"; mkdir -p "$T_TMP/slowbin"; cp "$T_TMP/slowgit" "$T_TMP/slowbin/git"
_t0="$(date +%s)"; PATH="$T_TMP/slowbin:$PATH" HARBOR_HUB_TIMEOUT=2 sh "$S" pull > /dev/null 2>&1; _rc=$?; _t1="$(date +%s)"
t_eq "a hung git does not fail the hook" 0 "$_rc"
t_eq "...and ends inside the bound plus a margin" 1 "$([ $((_t1 - _t0)) -le 8 ] && echo 1 || echo 0)"
tools status; t_has "status names the repo" "$OUT" "acme/tools-someone"
t_exit "an unknown verb is usage" 2 sh "$S" frobnicate
t_done
