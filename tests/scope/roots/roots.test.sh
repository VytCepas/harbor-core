#!/usr/bin/env sh
# scope-roots.sh --check must be able to fail: four arms that fire, three correct shapes that
# must not, and a non-checkout that is not a pass (harbor#630, #619). Every case is a throwaway checkout.
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_SCOPE_PRIVATE="$T_TMP/no-private"; export HARBOR_SCOPE_PRIVATE   # the box's real registry must not answer
# @V@ becomes '$': spelled literally, these fixtures are live ${VAR:-$HOME/<repo>} tokens
# and --check on this repo reports the test's own data as defects.
build() { # <name> <table-body> <site-content> → the checkout's path
  _d="$T_TMP/$1"; mkdir -p "$_d/contracts" "$_d/bin"
  printf 'var\tbase\trel\tbreaks\n%s\n' "$2" > "$_d/contracts/roots.tsv"
  printf '%s\n' "$3" | sed 's/@V@/$/g' > "$_d/bin/site.sh"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
# Assign the dir before calling: inline, a brace-comma fixture brace-expands the whole word.
rc_is() { # <label> <dir> <want-rc> [<stderr-substring>]
  _rc="$(HARBOR_SCOPE_ROOT="$2" sh "$T_ROOT/bin/scope-roots.sh" --check >/dev/null 2>"$T_TMP/err"; echo $?)"
  t_eq "$1: exit" "$3" "$_rc"
  [ -z "${4:-}" ] || t_has "$1: reason" "$(cat "$T_TMP/err")" "$4"
}

t_section "the four arms fire"
D="$(build ok1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"')"
rc_is "a matching default is green" "$D" 0
D="$(build bad1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp-old}"')"
rc_is "a drifted default" "$D" 1 'table says'
D="$(build bad2 'BLORP_DIR	REPOS	blorp	x
NEWTHING_DIR	REPOS	nothing	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
E="@V@{NEWTHING_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/nothing}"
F="@V@{SURPRISE_DIR:-@V@HOME/port/blorp}"')"
rc_is "an unregistered root variable" "$D" 1 'not in'
D="$(build bad3 'BLORP_DIR	REPOS	blorp	x
GHOST_DIR	REPOS	labkit	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"')"
rc_is "a dead table row" "$D" 1 'used nowhere'

t_section "the ~/port move: both arms see old and new addresses (harbor#619)"
D="$(build move1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@HOME/blorp}"')"
rc_is "a registered default at the pre-move address" "$D" 1 'table says'
D="$(build move2 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
F="@V@{SURPRISE_DIR:-@V@HOME/port/blorp}"')"
rc_is "an unregistered root at the new address" "$D" 1 'not in'
D="$(build move3 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
F="@V@{SURPRISE_DIR:-@V@HOME/blorp}"')"
rc_is "an unregistered root at the old address" "$D" 1 'not in'

t_section "three correct shapes are not flagged"
D="$(build ok2 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
if [ -n "@V@{BLORP_DIR:-}" ]; then :; fi')"
rc_is "an empty default" "$D" 0
D="$(build ok3 'HARBOR_SCOPE_REPO	REPOS	harbor	x' 'R="@V@{HARBOR_SCOPE_REPO:-@V@{PORT_ROOT:-@V@HOME/port}/harbor}"
S="@V@{HARBOR_SCOPE_REPO:-@V@(CDPATH= cd -- "@V@(dirname -- "@V@0")/.." && pwd -P)}"')"
rc_is "a derived default" "$D" 0
D="$(build ok4 'HARBOR_SCOPE_REPO	REPOS	harbor	x' 'R="@V@{HARBOR_SCOPE_REPO:-@V@{PORT_ROOT:-@V@HOME/port}/harbor}"
printf "looked in: %s" "@V@{HARBOR_SCOPE_REPO:-none}"
printf "looked in: %s" "@V@{BIN:-@V@_self_dir, @V@HOME/port/harbor/bin}"')"
rc_is "a non-path default" "$D" 0

t_section "--repos: each governed checkout once, BOX rows left out (harbor#829)"
D="$(build repos 'HARBOR_SCOPE_REPO	REPOS	harbor	x
ACCESS_DIR	REPOS	harbor/ACCESS	x
BLORP_DIR	REPOS	blorp	x
HARBOR_SCOPE_LOCAL_BIN	BOX	.local/bin	x' 'x=1')"
t_eq "one row per repo, resolved under HOME" "harbor	$HOME/port/harbor
blorp	$HOME/port/blorp" "$(HARBOR_SCOPE_ROOT="$D" env -u PORT_ROOT sh "$T_ROOT/bin/scope-roots.sh" --repos)"
D="$(build repos2 'EVIL_DIR	REPOS	..	x' 'x=1')"
t_exit "a segment that is not a repo name is refused" 2 env HARBOR_SCOPE_ROOT="$D" sh "$T_ROOT/bin/scope-roots.sh" --repos
t_has "...saying why" "$(HARBOR_SCOPE_ROOT="$D" sh "$T_ROOT/bin/scope-roots.sh" --repos 2>&1)" "is not a repo name"

t_section "the spelling decides whether PORT_ROOT is honoured (harbor#630)"
D="$(build flat1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@HOME/port/blorp}"')"
rc_is "a flat REPOS default ignores PORT_ROOT and is refused" "$D" 1 'ignores PORT_ROOT'
D="$(build flat2 'HARBOR_SCOPE_LOCAL_BIN	BOX	.local/bin	x' 'B="@V@{HARBOR_SCOPE_LOCAL_BIN:-@V@HOME/.local/bin}"')"
rc_is "a BOX default has no PORT_ROOT to honour, so flat is right" "$D" 0
D="$(build nest1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
F="@V@{SURPRISE_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"')"
rc_is "an unregistered root spelled with PORT_ROOT is still found" "$D" 1 'SURPRISE_DIR names a governed repo'
D="$(build nest2 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp-old}"')"
rc_is "a nested default that drifted" "$D" 1 'table says'
D="$(build nest3 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
P="@V@{HARBOR_SCOPE_PRIVATE:-@V@{PORT_ROOT:-@V@HOME/port}/harbor-private}/jobs"')"
rc_is "the private layer is not a spelling of the harbor repo" "$D" 0

t_section "two names for one path need a stated reason (harbor#630)"
D="$(build pair1 'PROJECT_INIT_SRC	REPOS	project-init	x
HARBOR_PROJECT_INIT	REPOS	project-init	x' 'A="@V@{PROJECT_INIT_SRC:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"
B="@V@{HARBOR_PROJECT_INIT:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"')"
rc_is "an unexplained pair" "$D" 1 'no reason on'
D="$(build pair2 'PROJECT_INIT_SRC	REPOS	project-init	x	suites export this name
HARBOR_PROJECT_INIT	REPOS	project-init	x' 'A="@V@{PROJECT_INIT_SRC:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"
B="@V@{HARBOR_PROJECT_INIT:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"')"
rc_is "a pair where only one row explains itself" "$D" 1 'no reason on: HARBOR_PROJECT_INIT'
D="$(build pair3 'PROJECT_INIT_SRC	REPOS	project-init	x	suites export this name
HARBOR_PROJECT_INIT	REPOS	project-init	x	prod-guard-install reads the other' 'A="@V@{PROJECT_INIT_SRC:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"
B="@V@{HARBOR_PROJECT_INIT:-@V@{PORT_ROOT:-@V@HOME/port}/project-init}"')"
rc_is "a pair where every row explains itself" "$D" 0

t_section "a PORT_ROOT other than the default resolves every table row (harbor#630)"
WS="$T_TMP/elsewhere/ws"; mkdir -p "$WS"
D="$(build res1 'HARBOR_SCOPE_REPO	REPOS	harbor	x
BLORP_DIR	REPOS	blorp	x
HARBOR_SCOPE_FLEET_FILE	REPOS	projects-orchestrator/fleet.yaml	x
HARBOR_SCOPE_LOCAL_BIN	BOX	.local/bin	x' 'x=1')"
r() { HARBOR_SCOPE_ROOT="$D" PORT_ROOT="$WS" sh "$T_ROOT/bin/scope-roots.sh" "$@"; }
t_eq "--get under PORT_ROOT" "$WS/blorp" "$(r --get BLORP_DIR)"
t_eq "--get of a file under a repo" "$WS/projects-orchestrator/fleet.yaml" "$(r --get HARBOR_SCOPE_FLEET_FILE)"
t_eq "--get of a BOX row stays under HOME" "$HOME/.local/bin" "$(r --get HARBOR_SCOPE_LOCAL_BIN)"
t_eq "an exported variable still beats the default" "/own/blorp" "$(BLORP_DIR=/own/blorp r --get BLORP_DIR)"
t_has "--list resolves under PORT_ROOT" "$(r --list)" "$WS/projects-orchestrator/fleet.yaml"
t_eq "--repos resolves under PORT_ROOT" "harbor	$WS/harbor
blorp	$WS/blorp
projects-orchestrator	$WS/projects-orchestrator" "$(r --repos)"
t_eq "PORT_ROOT unset falls back to the home default" "$HOME/port/blorp" "$(HARBOR_SCOPE_ROOT="$D" env -u PORT_ROOT sh "$T_ROOT/bin/scope-roots.sh" --get BLORP_DIR)"
t_eq "a trailing slash on PORT_ROOT does not double" "$WS/blorp" "$(HARBOR_SCOPE_ROOT="$D" PORT_ROOT="$WS/" sh "$T_ROOT/bin/scope-roots.sh" --get BLORP_DIR)"

t_section "--base: what a base is on this box, the text a launchd template's @HOME@ fills (harbor#630)"
t_eq "BOX is the home directory" "$HOME" "$(r --base BOX)"
t_eq "REPOS is the workspace root, PORT_ROOT honoured" "$WS" "$(r --base REPOS)"
t_eq "a trailing slash on HOME is dropped" "$HOME" "$(HOME="$HOME/" HARBOR_SCOPE_ROOT="$D" sh "$T_ROOT/bin/scope-roots.sh" --base BOX)"
t_exit "a base that is not one is refused" 2 r --base NOWHERE
t_exit "no base named is a usage error" 2 r --base
t_exit "with HOME unset the BOX base has no path, and says so" 2 env -u HOME HARBOR_SCOPE_ROOT="$D" sh "$T_ROOT/bin/scope-roots.sh" --base BOX

t_section "the real table: every REPOS row resolves under another root and no site spells it flat"
t_eq "the tree's own --check is green" "0" "$(sh "$T_ROOT/bin/scope-roots.sh" --check >/dev/null 2>&1; echo $?)"
_bad=""
for _v in $(awk -F'\t' '!/^#/ && $2=="REPOS" {print $1}' "$T_ROOT/contracts/roots.tsv"); do
  _g="$(PORT_ROOT="$WS" sh "$T_ROOT/bin/scope-roots.sh" --get "$_v")"
  case "$_g" in "$WS"/*) ;; *) _bad="$_bad $_v=$_g" ;; esac
done
t_eq "every REPOS row of contracts/roots.tsv lands under PORT_ROOT" "" "$_bad"

t_section "arm 2 reads its repo ids from the registry, and with none says it sees fewer (harbor#1273)"
REG="$T_TMP/reg"; mkdir -p "$REG"; printf 'id\tpath\tkind\tremote\nwidget\twidget\tworkload\t-\n' > "$REG/repos.tsv"
D="$(build reg1 'BLORP_DIR	REPOS	blorp	x' 'D="@V@{BLORP_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/blorp}"
F="@V@{SURPRISE_DIR:-@V@{PORT_ROOT:-@V@HOME/port}/widget}"')"
_rc="$(HARBOR_SCOPE_PRIVATE="$REG" HARBOR_SCOPE_ROOT="$D" sh "$T_ROOT/bin/scope-roots.sh" --check >/dev/null 2>"$T_TMP/err"; echo $?)"
t_eq "a repo only the registry names is found" 1 "$_rc"
t_has "...as an unregistered root" "$(cat "$T_TMP/err")" 'SURPRISE_DIR names a governed repo'
rc_is "no registry: that repo is unknown, so the site is not flagged" "$D" 0 'no repo registry: arm 2 checks'

t_section "a check that inspected nothing is not a pass"
mkdir -p "$T_TMP/nogit/contracts"
printf 'var\tbase\trel\tbreaks\nBLORP_DIR\tREPOS\tblorp\tx\n' > "$T_TMP/nogit/contracts/roots.tsv"
rc_is "a non-checkout" "$T_TMP/nogit" 2
t_done
