#!/usr/bin/env sh
# memory-route.sh: does a session started in a governed repo load the one memory store?
# Everything is a fixture, $HOME included. The stand-downs matter most: a check starved of
# input must exit 3 (D-29 unchecked) and say STOOD DOWN, never exit 0 (cases 1, 10, 11); a bad argument exits 2 (case 11g).
# --status (contracts/reconcile.md, harbor#1031) is the same judgement as rows: cases 1s, 2s, 3s, 10s, 11s, 11gs.
. "$(dirname "$0")/../../lib/core.sh"; t_init
# Physical: /var is a link to /private/var, and the tool keys stores off the resolved path.
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)/box"
CFG="$T/cfg"; REPOROOT="$T/repo"; TAB="$(printf '\t')"
# The registry is the private layer's (harbor#1149): a fixture layer, named for every call below.
REG="$T/priv/inject.d/box/projects.tsv"; HARBOR_SCOPE_PRIVATE="$T/priv"; export HARBOR_SCOPE_PRIVATE
mkdir -p "$CFG/projects" "$REPOROOT" "$T/priv/inject.d/box"
key_for() { printf '%s' "$1" | sed 's|/|-|g'; }  # the tool's own derivation, not a hand-typed key
route_of() { printf '%s' "$CFG/projects/$(key_for "$1")/memory"; }
HOME_STORE="$(route_of "$T")"; mkdir -p "$HOME_STORE"
printf -- '---\nname: a\n---\nbody\n' > "$HOME_STORE/a.md"
printf -- '---\nname: b\n---\nbody\n' > "$HOME_STORE/b.md"
mkrepo() { mkdir -p "$T/$1"; printf '%s%s~/%s%sw\n' "$1" "$TAB" "$1" "$TAB" >> "$REG"; }
addrow() { printf '%s%s~/%s%sw\n' "$1" "$TAB" "$1" "$TAB" >> "$REG"; }
# PORT_ROOT is pinned: an exported value on the host would add a real directory to every case.
mr() { HOME="$T" PORT_ROOT="$T/port" HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" "$@" 2>&1; }
code() { mr "$@" >/dev/null; printf '%s' "$?"; }
# --status: stdout alone (it is data), its exit in the file named $T/status.rc
mrs() { HOME="$T" PORT_ROOT="$T/port" HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" --status "$@" 2>/dev/null; }
mrs_rc() { mrs "$@" > "$T/status.out"; printf '%s' "$?"; }
is_link() { [ -L "$1" ] && echo link || echo "not a link"; }
gitrepo() { git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  : > "$1/f"; git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm base >/dev/null 2>&1; }

t_section "1 · no registry at all is a stand-down"
t_eq "1: exit" 3 "$(code)"
t_has "1: says so" "$(mr)" 'STOOD DOWN'
t_eq "1r: its receipt says stood-down, with no subjects (harbor#896)" "stood-down 0" "$(jq -r '"\(.status) \(.subjects | length)"' "$CFG/cache/checks/memory-route.json")"
t_section "1s · --status with no registry: an unchecked record and exit 3, never a green"
t_eq "1s: exit" 3 "$(mrs_rc)"
t_eq "1s: the header, then unchecked with the reason, and no summary" "reconcile${TAB}1${TAB}memory-route unchecked" \
  "$(awk -F'\t' 'NR == 1 { printf "%s%s%s%s%s", $1, FS, $2, FS, $3 } $1 == "unchecked" { printf " unchecked" } $1 == "summary" { printf " SUMMARY" }' "$T/status.out")"
t_has "1s: the reason names the registry, the private layer's (harbor#1149)" "$(cat "$T/status.out")" "no registry at $REG"
t_eq "1s: no first-seen state is made by a run that could not judge" absent "$([ -e "$CFG/cache/reconcile/memory-route.tsv" ] && echo present || echo absent)"

printf '# comment\n' > "$REG"; mkrepo zorbcorp; mkrepo blorp
t_section "2-3 · an unrouted repo is RED and named; --apply routes it and the same check passes"
t_eq "2: exit" 1 "$(code)"
t_has "2: the repo is named BLIND" "$(mr)" 'BLIND  zorbcorp'
t_eq "2r: its receipt is red over the blind repos" "red blorp zorbcorp" "$(jq -r '"\(.status) \(.subjects | sort | join(" "))"' "$CFG/cache/checks/memory-route.json")"
t_section "2s · --status: one new row per blind repo with desired, observed, delta and age; a second run adds none"
_links="$(find "$CFG/projects" -maxdepth 2 -name memory -type l 2>/dev/null | grep -c .)"
t_eq "2s: exit, the plain run's" 1 "$(mrs_rc)"
t_eq "2s: the header" "reconcile${TAB}1${TAB}memory-route" "$(sed -n 1p "$T/status.out")"
t_eq "2s: both blind repos are new rows, keyed by their registry label" "blorp zorbcorp" "$(awk -F'\t' '$1 == "new" { print $2 }' "$T/status.out" | sort | tr '\n' ' ' | sed 's/ $//')"
t_has "2s: observed names what is wrong" "$(grep "^new${TAB}zorbcorp" "$T/status.out")" "${TAB}no store for this cwd${TAB}"
t_has "2s: desired says what a session should load" "$(grep "^new${TAB}zorbcorp" "$T/status.out")" "${TAB}a session started here loads a store with notes${TAB}"
t_has "2s: delta says what changes it" "$(grep "^new${TAB}zorbcorp" "$T/status.out")" "${TAB}add a route to the one store${TAB}0"
t_eq "2s: the summary counts two examined, two drifted, none cleared" "summary${TAB}2${TAB}2${TAB}0" "$(grep '^summary' "$T/status.out")"
t_eq "2s: every stdout line is a record of the contract" "" "$(grep -Ev "^(reconcile|new|standing|cleared|summary|unchecked)${TAB}" "$T/status.out")"
t_eq "2s: the second run, nothing changed, prints no new row" 0 "$(mrs_rc >/dev/null; grep -c "^new${TAB}" "$T/status.out")"
t_eq "2s: ...and both rows are standing with an age in seconds" 2 "$(awk -F'\t' '$1 == "standing" && $6 ~ /^[0-9]+$/ { n++ } END { print n + 0 }' "$T/status.out")"
t_eq "2s: it routed nothing (it only reports)" "$_links" "$(find "$CFG/projects" -maxdepth 2 -name memory -type l 2>/dev/null | grep -c .)"
t_eq "2s: its receipt is the plain run's, red over the same repos" "red blorp zorbcorp" "$(jq -r '"\(.status) \(.subjects | sort | join(" "))"' "$CFG/cache/checks/memory-route.json")"
mr --apply >/dev/null  # the green below comes from re-running the plain check, not from --apply's report
t_eq "3: exit after --apply" 0 "$(code)"
t_has "3: the repo is ok" "$(mr)" 'ok     zorbcorp'
t_eq "3r: and its receipt is green, with no subjects" "green 0" "$(jq -r '"\(.status) \(.subjects | length)"' "$CFG/cache/checks/memory-route.json")"
t_section "3s · --status after --apply: the converged rows are cleared, once, and the exit is 0"
t_eq "3s: exit" 0 "$(mrs_rc)"
t_eq "3s: both rows are cleared and none is listed" "blorp zorbcorp 0" "$(awk -F'\t' '$1 == "cleared" { c = c $2 " " } $1 == "new" || $1 == "standing" { n++ } END { sub(/ $/, "", c); print c " " n + 0 }' "$T/status.out")"
t_eq "3s: the summary counts the two routed repos examined, none drifted, two cleared" "summary${TAB}2${TAB}0${TAB}2" "$(grep '^summary' "$T/status.out")"
t_eq "3s: the next run reports no cleared row" 0 "$(mrs_rc >/dev/null; grep -c "^cleared${TAB}" "$T/status.out")"

t_section "4-6 · the route is a symlink into the one store, counted once"
LINK="$(route_of "$T/zorbcorp")"
t_eq "4: the route is a symlink" link "$(is_link "$LINK")"
t_eq "4: it resolves to the home store" "$(cd -P "$HOME_STORE" && pwd -P)" "$(cd -P "$LINK" 2>/dev/null && pwd -P)"
printf -- '---\nname: c\n---\nfiled from the repo\n' > "$LINK/c.md"
t_eq "5: a note written through the route lands in the home store" yes "$([ -f "$HOME_STORE/c.md" ] && echo yes || echo no)"
rm -f "$HOME_STORE/c.md"
t_eq "6: the home store's 2 notes are not double-counted through the link" 2 "$(mr | sed -n 's/.*store: .*(\([0-9]*\) notes)/\1/p')"

t_section "7-8c · an own store: never clobbered, empty is blind, only an empty one is replaced"
mkrepo ownstore; OWN="$(route_of "$T/ownstore")"  # never routed, so the store is really its own
mkdir -p "$OWN"; printf -- '---\nname: own\n---\nx\n' > "$OWN/own.md"
mr --apply >/dev/null
t_eq "7: a populated own store is not replaced by a link" "not a link" "$(is_link "$OWN")"
t_eq "7: its note survives --apply" yes "$([ -f "$OWN/own.md" ] && echo yes || echo no)"
rm -f "$OWN/own.md"
t_eq "8: an empty own store is RED" 1 "$(code)"
mr --apply >/dev/null
t_eq "8b: --apply replaces an EMPTY own directory with a route" link "$(is_link "$OWN")"
rm -f "$OWN"; mkdir -p "$OWN"; printf 'x\n' > "$OWN/notes.db"  # non-.md: 0 notes, so the branch is entered
mr --apply >/dev/null
t_eq "8c: a directory with unrecognised content is not replaced" "not a link" "$(is_link "$OWN")"
t_eq "8c: its content survives" yes "$([ -f "$OWN/notes.db" ] && echo yes || echo no)"
rm -rf "$OWN" "$T/ownstore"  # both halves, or case 9 reads the leftover row as its own failure

t_section "9-11 · a gone row is skipped; an empty store or a zero-row registry stands down"
addrow ghost
t_eq "9: a row with no directory leaves the check green" 0 "$(code)"
mv "$HOME_STORE/a.md" "$T/a.keep"; mv "$HOME_STORE/b.md" "$T/b.keep"
t_eq "10: an empty home store: exit" 3 "$(code)"
t_has "10: says so" "$(mr)" 'STOOD DOWN'
rm -f "$CFG/cache/checks/memory-route.json"; mr >/dev/null
t_eq "10r: the empty-store stand-down leaves a stood-down receipt" stood-down "$(jq -r .status "$CFG/cache/checks/memory-route.json" 2>/dev/null)"
t_eq "10s: --status on an empty store: exit" 3 "$(mrs_rc)"
t_has "10s: it is an unchecked record" "$(cat "$T/status.out")" "unchecked${TAB}the store at projects/"
mv "$T/a.keep" "$HOME_STORE/a.md"; mv "$T/b.keep" "$HOME_STORE/b.md"
cp "$REG" "$T/reg.keep"; printf 'zorbcorp ~/port/zorbcorp w\n' > "$REG"  # spaces, not tabs
t_eq "11: a registry parsing to 0 rows: exit" 3 "$(code)"
t_has "11: says so" "$(mr)" 'STOOD DOWN'
rm -f "$CFG/cache/checks/memory-route.json"; mr >/dev/null
t_eq "11r: the zero-row stand-down leaves a stood-down receipt" stood-down "$(jq -r .status "$CFG/cache/checks/memory-route.json" 2>/dev/null)"
t_eq "11s: --status on a zero-row registry: exit" 3 "$(mrs_rc)"
t_has "11s: it is an unchecked record" "$(cat "$T/status.out")" "unchecked${TAB}the registry parsed to 0 usable rows"
cp "$T/reg.keep" "$REG"

t_section "11b-c · --apply never guesses the live dir"
links() { find "$CFG/projects" -maxdepth 2 -name memory -type l 2>/dev/null | grep -c .; }
_before="$(links)"
# No CLAUDE_CONFIG_DIR and HOME at the fixture: the bare default IS this run's live dir.
_out="$(HOME="$T" HARBOR_REPO="$REPOROOT" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/memory-route.sh" --apply 2>&1)"; _c=$?
t_eq "11b: bare --apply at the live dir: exit" 2 "$_c"
t_has "11b: it names --live" "$_out" 'without an explicit --live'
t_eq "11b: it wrote nothing" "$_before" "$(links)"
_out="$(HOME="$T" HARBOR_REPO="$REPOROOT" CLAUDE_CONFIG_DIR="$CFG" sh "$T_ROOT/bin/memory-route.sh" --apply 2>&1)"; _c=$?
t_eq "11b: bare --apply with a non-live config dir: exit" 2 "$_c"
t_has "11b: it asks for a target" "$_out" 'needs a target'
mkdir -p "$T/.claude/projects"  # the trailing slash: a string compare passes it, a resolved one does not
_out="$(HOME="$T" HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$T/.claude/" --apply 2>&1)"; _c=$?
t_eq "11c: --dir at the live dir: exit" 2 "$_c"
t_has "11c: it still demands --live" "$_out" 'explicit --live'

t_section "11g · a bad argument is a usage error (2), never the 3 of a stood-down run"
t_eq "11g: an unknown flag: exit" 2 "$(code --bogus)"
t_has "11g: it says so and points at --help" "$(mr --bogus)" 'unknown argument --bogus'
t_section "11gs · --status only reports: it refuses --apply and an unknown flag with 2, and prints nothing on stdout"
t_eq "11gs: --status --apply: exit" 2 "$(mrs_rc --apply)"
t_eq "11gs: ...with nothing on stdout" "" "$(cat "$T/status.out")"
HOME="$T" PORT_ROOT="$T/port" HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" --status --apply > "$T/u.out" 2> "$T/u.err"
t_has "11gs: ...and says why on stderr" "$(cat "$T/u.err")" '--status only reports'
t_eq "11gs: ...with no summary line on either stream (contracts/logging.md: a usage error is not a run)" "" "$(cat "$T/u.out" "$T/u.err" | grep -E '^memory-route: [0-9]+ ok' || :)"
t_eq "11gs: --status --bogus: exit" 2 "$(mrs_rc --bogus)"
t_eq "11gs: ...with nothing on stdout" "" "$(cat "$T/status.out")"
t_eq "11g: and the stood-down code stays distinct from it (empty registry, valid flags)" 3 "$(mv "$REG" "$T/reg.gone"; c="$(code)"; mv "$T/reg.gone" "$REG"; printf '%s' "$c")"

t_section "11d-f · worktrees and sub-repos one level down are routed, deeper is not"
mkrepo wtrepo; gitrepo "$T/wtrepo"
git -C "$T/wtrepo" worktree add -q -b side "$T/wtrepo-side" >/dev/null 2>&1
mr --apply >/dev/null
t_eq "11d: a worktree of a governed repo is routed" link "$(is_link "$(route_of "$T/wtrepo-side")")"
# harbor#1149: a tree under .worktrees/<repo>/ lives outside any registry row's children
mkdir -p "$T/.worktrees/wtrepo"
git -C "$T/wtrepo" worktree add -q -b side2 "$T/.worktrees/wtrepo/side2" >/dev/null 2>&1
mr --apply >/dev/null
t_eq "11d2: a .worktrees/<repo>/<slug> worktree is routed" link "$(is_link "$(route_of "$T/.worktrees/wtrepo/side2")")"
mkdir -p "$T/rootdir/sub"; addrow rootdir; gitrepo "$T/rootdir/sub"  # a root holding checkouts, not itself a repo
mr --apply >/dev/null
t_eq "11e: a sub-repo one level below a row is routed" link "$(is_link "$(route_of "$T/rootdir/sub")")"
git -C "$T/rootdir/sub" worktree add -q -b wt "$T/rootdir/sub-wt" >/dev/null 2>&1
t_eq "11e2: the fixture's worktree has a .git FILE" yes "$([ -f "$T/rootdir/sub-wt/.git" ] && echo yes || echo no)"
mr --apply >/dev/null
t_eq "11e2: a sub-worktree under a root is routed" link "$(is_link "$(route_of "$T/rootdir/sub-wt")")"
mkdir -p "$T/rootdir/sub/deep"; git -C "$T/rootdir/sub/deep" init -q
mr --apply >/dev/null
t_eq "11f: discovery stops at one level" absent "$([ -e "$(route_of "$T/rootdir/sub/deep")" ] && echo present || echo absent)"

t_section "12 · every line is stamped with the registry id"
t_has "12: the stamp" "$(mr)" '[check:memory-route]'

t_section "13 · the workspace root is checked though no row names it (harbor#619)"
mkrepo port/inner  # a governed repo inside the root, as on the real box
mr --apply >/dev/null; rm -f "$(route_of "$T/port")"
t_eq "13: an unrouted PORT_ROOT: exit" 1 "$(code)"
t_has "13: it is named BLIND port-root" "$(mr)" 'BLIND  port-root'
HOME="$T" HARBOR_REPO="$REPOROOT" env -u PORT_ROOT sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" --apply >/dev/null 2>&1
t_eq "13b: PORT_ROOT unset routes \$HOME/port" link "$(is_link "$(route_of "$T/port")")"
rm -f "$(route_of "$T/port")"
HOME="$T" PORT_ROOT= HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" --apply >/dev/null 2>&1
t_eq "13c: an EMPTY PORT_ROOT routes \$HOME/port" link "$(is_link "$(route_of "$T/port")")"
mkdir -p "$T/ws"
HOME="$T" PORT_ROOT="$T/ws/" HARBOR_REPO="$REPOROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CFG" --apply >/dev/null 2>&1
t_eq "13d: an exported PORT_ROOT, trailing slash and all, is the root routed" link "$(is_link "$(route_of "$T/ws")")"
t_done
