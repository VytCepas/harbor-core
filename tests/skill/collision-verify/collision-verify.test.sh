#!/usr/bin/env sh
# skill-collision-verify.sh refuses to install over a live skill holding work only the box has, and stays
# silent on the ordinary update (harbor#117 I3). It judges by CONTENT, never mtime (harbor#476, #641):
# a live file is safe to overwrite when its bytes are an older commit of the skill or an install
# record in .harbor-manifest. Runs on a fake git repo and config dir.
. "$(dirname "$0")/../../lib/core.sh"; t_init
FAKE="$T_TMP/repo"; CFG="$T_TMP/cfg"
mkdir -p "$FAKE/bin" "$FAKE/skills" "$FAKE/vendor/skills" "$CFG/skills"
cp "$T_ROOT/bin/skill-collision-verify.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$FAKE/bin/"
git init -q "$FAKE"
g() { git -C "$FAKE" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
mk() { mkdir -p "$1/$2"; printf -- '---\nname: %s\n---\n\n%s\n' "$2" "$3" > "$1/$2/SKILL.md"; }  # <where> <name> <body>
commit() { g add -A; g commit -qm "$1"; }
run() { CLAUDE_CONFIG_DIR="$CFG" sh "$FAKE/bin/skill-collision-verify.sh" "$@" > "$T_TMP/out" 2>&1; echo $?; }
out() { cat "$T_TMP/out"; }
fixfollows() { awk '/^  FAIL: / { f = 1; next } f && !/^  fix: / { bad = 1 } { f = 0 } END { exit bad }' "$T_TMP/out"; }

t_section "absent or identical destinations are not collisions"
mk "$FAKE/skills" alpha "repo copy"; commit alpha-v1
t_eq "absent destination" 0 "$(run alpha)"
cp -R "$FAKE/skills/alpha" "$CFG/skills/alpha"
t_eq "byte-identical destination" 0 "$(run alpha)"

t_section "repo newer than box is the ordinary update and stays silent"
printf -- '---\nname: alpha\n---\n\nrepo copy, edited later\n' > "$FAKE/skills/alpha/SKILL.md"; commit alpha-v2
touch -t 203001010000 "$FAKE/skills/alpha/SKILL.md"
t_eq "ordinary update" 0 "$(run alpha)"
touch -t 203101010000 "$CFG/skills/alpha/SKILL.md"
t_eq "a live copy whose mtime is newer, but whose bytes are an older commit, is not refused (harbor#476)" 0 "$(run alpha)"

t_section "work only the box has is refused, whatever the mtimes say"
printf -- '---\nname: alpha\n---\n\nbox edited it\n' > "$CFG/skills/alpha/SKILL.md"
touch -t 200101010000 "$CFG/skills/alpha/SKILL.md"
t_eq "a live edit in no commit, with an OLDER mtime than the source" 1 "$(run alpha)"
t_has "names the skill and the file" "$(out)" "  FAIL: alpha: the installed copy holds bytes in no commit and no install record: SKILL.md"
t_has "says what to do instead" "$(out)" "Capture them first"
t_exit "every FAIL is followed by its fix line" 0 fixfollows
t_has "it ends on its summary line" "$(tail -1 "$T_TMP/out")" "skills-collide: 0 ok, 1 failed, 0 warnings"
git -C "$FAKE" show HEAD~1:skills/alpha/SKILL.md > "$CFG/skills/alpha/SKILL.md"; printf 'mine\n' > "$CFG/skills/alpha/NOTES.md"
t_eq "a file only the box has, in no commit, is refused too" 1 "$(run alpha)"
t_has "...naming it" "$(out)" "no install record: NOTES.md"
rm -f "$CFG/skills/alpha/NOTES.md"

t_section "#476 (a): an older commit plus a change to a sibling of SKILL.md installs with no flag"
mk "$FAKE/skills" atlas "atlas"; printf 'readme v1\n' > "$FAKE/skills/atlas/README.md"; commit atlas-v1
cp -R "$FAKE/skills/atlas" "$CFG/skills/atlas"
touch -t 202001010000 "$FAKE/skills/atlas/SKILL.md"  # cp -R stamped the live copy with install time
printf 'readme v2\n' > "$FAKE/skills/atlas/README.md"; commit atlas-v2
t_eq "a repo-side README-only change over a fresh install" 0 "$(run atlas)"
printf 'readme v1\nplus a line in no commit\n' > "$CFG/skills/atlas/README.md"
t_eq "#476 (b): a line in no commit, in a sibling, is still refused" 1 "$(run atlas)"
t_has "...naming the sibling" "$(out)" "no install record: README.md"

t_section "#641: a non-SKILL.md file identical to an older commit, and a repo-side path rename"
mk "$FAKE/skills" tstr "test-strength"; mkdir -p "$FAKE/skills/tstr/targets" "$FAKE/skills/tstr/old"
printf 'one\n' > "$FAKE/skills/tstr/targets/a.target"; printf 'doc\n' > "$FAKE/skills/tstr/old/p.md"; commit tstr-v1
cp -R "$FAKE/skills/tstr" "$CFG/skills/tstr"
printf 'two\n' > "$FAKE/skills/tstr/targets/a.target"; mkdir -p "$FAKE/skills/tstr/new"
g mv skills/tstr/old/p.md skills/tstr/new/p.md; commit tstr-v2
t_eq "a stale target line and a file the repo moved are both older commits" 0 "$(run tstr)"
t_has "...said as ok" "$(out)" "  ok: tstr: "

t_section "the install manifest is the second witness: a recorded install is not a box-only edit (§3)"
NG="$T_TMP/nogit"; mkdir -p "$NG/bin" "$NG/skills"; cp "$FAKE/bin/"* "$NG/bin/"; mk "$NG/skills" rho "rho v2"
mkdir -p "$CFG/skills/rho"; printf 'installed bytes\n' > "$CFG/skills/rho/SKILL.md"
ngrun() { CLAUDE_CONFIG_DIR="$CFG" sh "$NG/bin/skill-collision-verify.sh" "$@" > "$T_TMP/out" 2>&1; echo $?; }
t_eq "no git checkout and no install record: no verdict, and no verdict does not block (§2.11)" 0 "$(ngrun rho)"
t_has "...said as a note" "$(out)" "  note: rho: no verdict for SKILL.md"
printf '# m\n%s 100644 skills/rho/SKILL.md skills-install -\n' "$(git hash-object "$CFG/skills/rho/SKILL.md")" > "$CFG/.harbor-manifest"
t_eq "the manifest recording those bytes for that path" 0 "$(ngrun rho)"
printf 'edited after the install\n' > "$CFG/skills/rho/SKILL.md"
t_eq "bytes that differ from the recorded install are refused, git or not" 1 "$(ngrun rho)"
rm -f "$CFG/.harbor-manifest"

t_section "a skill without a SKILL.md is judged the same way: its bytes decide"
mkdir -p "$FAKE/skills/beta" "$CFG/skills/beta"
printf 'not a skill file\n' > "$FAKE/skills/beta/README.md"; commit beta-v1
printf 'not a skill file\n' > "$CFG/skills/beta/README.md"
printf 'newer in the repo\n' > "$FAKE/skills/beta/README.md"; commit beta-v2
t_eq "an older commit of a skill with no SKILL.md" 0 "$(run beta)"
printf 'different\n' > "$CFG/skills/beta/README.md"
t_eq "box-only bytes in a skill with no SKILL.md" 1 "$(run beta)"
t_eq "an untracked name" 1 "$(run nosuchskill)"
t_has "says it is not tracked" "$(out)" "not tracked here"

t_section "--all reaches the vendored tier, and no argument refuses"
rm -rf "$CFG/skills/beta" "$CFG/skills/alpha" "$CFG/skills/atlas"
mk "$FAKE/vendor/skills" gamma "vendored"; commit gamma
cp -R "$FAKE/vendor/skills/gamma" "$CFG/skills/gamma"
printf -- '---\nname: gamma\n---\n\nbox edited it\n' > "$CFG/skills/gamma/SKILL.md"
t_eq "--all with a vendored collision" 1 "$(run --all)"
t_has "names the vendored refusal" "$(out)" "  FAIL: gamma: "
t_eq "bare invocation" 2 "$(run)"
t_done
