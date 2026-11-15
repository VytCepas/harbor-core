#!/usr/bin/env sh
# roots.test.sh (harbor#1278, F3 M5) — scope-roots.sh --hub: a member box's hub clone, from member.conf beside the marker, else managed env; exit 1, empty, anywhere else;
# and a box with no hub prints what it printed before.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SR="$T_ROOT/bin/scope-roots.sh"
XDG_STATE_HOME="$T_TMP/state"; export XDG_STATE_HOME
CLONE="$XDG_STATE_HOME/harbor/hub/repo"
sr() { sh "$SR" "$@" 2>/dev/null; }
rc() { sh "$SR" "$@" >/dev/null 2>&1; echo $?; }

t_section "1 - exit 1 and nothing on stdout unless the box is a member with a clone"
t_eq "standalone, no clone: exit 1" 1 "$(rc --hub)"
t_eq "...and empty" "" "$(sr --hub)"
mkdir -p "$CLONE"
t_eq "standalone, a clone on disk: still exit 1" 1 "$(HARBOR_HUB_REPO=o/h rc --hub)"
t_eq "a member with no HARBOR_HUB_REPO: exit 1" 1 "$(HARBOR_MEMBER_ROLE=member rc --hub)"
t_eq "a member naming a hub, with the clone: the clone's path" "$CLONE" "$(HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=o/h sr --hub)"
rm -rf "$CLONE"
t_eq "a member before the first clone: exit 1" 1 "$(HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=o/h rc --hub)"

t_section "2 - only managed env decides: harbor.toml and HARBOR_SCOPE_HUB do not"
mkdir -p "$CLONE"; PV="$T_TMP/pv"; mkdir -p "$PV"; export HARBOR_SCOPE_PRIVATE="$PV"
printf 'hub_repo = "o/h"\n' > "$PV/harbor.toml"
t_eq "a hub_repo key in harbor.toml is an unknown key (exit 2)" 2 "$(rc --conf hub_repo)"
t_eq "...and does not make --hub answer" 1 "$(rc --hub)"
printf '[hub]\nrepo = "o/h"\n' > "$PV/harbor.toml"
t_eq "a [hub] table is still refused (no tables)" 2 "$(rc --conf channel)"
rm -f "$PV/harbor.toml"
t_eq "HARBOR_SCOPE_HUB pointing at a directory changes nothing" 1 "$(HARBOR_SCOPE_HUB="$CLONE" rc --hub)"

t_section "3 - a box with no hub prints what it printed before"
H="$T_TMP/home2"; mkdir -p "$H"
base() { HOME="$H" PORT_ROOT="$H/port" sh "$SR" "$@" 2>&1; }
A="$(base --list; base --repos; base --port-root; base --private; base --conf-keys; base --aliases)"
B="$(HARBOR_MEMBER_ROLE=standalone HARBOR_HUB_REPO=o/h base --list; HARBOR_HUB_REPO=o/h base --repos; base --port-root; base --private; base --conf-keys; base --aliases)"
t_eq "--list --repos --port-root --private --conf-keys --aliases are byte-identical with a hub named but not joined" "$A" "$B"
t_eq "the usage text a stranger sees (first 17 lines) does not mention the hub" 0 "$(sh "$SR" --help 2>&1 | sed -n '1,17p' | grep -c -- '--hub')"
t_section "4 - run directly on a marker box, member.conf decides, never env"
MR="$T_TMP/managed/harbor"; mkdir -p "$MR/bin"
for _f in scope-roots.sh library-log.sh library-hub.sh; do cp "$T_ROOT/bin/$_f" "$MR/bin/"; done; cp "$T_ROOT/contracts/roots.tsv" "$MR/bin/"   # as member-files.txt lands them
: > "$MR/bin/harbor-member-mode"
MH="$T_TMP/member-home"; mkdir -p "$MH/.local/state/harbor/hub/repo"
printf 'hub=o/h\nlogin=alice\nhome=%s\n' "$MH" > "$MR/member.conf"
mr() { (cd "$T_TMP" && env -u HARBOR_MEMBER_ROLE -u HARBOR_HUB_REPO "$@" sh "$MR/bin/scope-roots.sh" --hub 2>/dev/null); }
t_eq "role and repo unset in env: the file's member, the file's home" "$MH/.local/state/harbor/hub/repo" "$(mr)"
t_eq "env saying standalone changes nothing" "$MH/.local/state/harbor/hub/repo" "$(mr HARBOR_MEMBER_ROLE=standalone)"
mkdir -p "$T_TMP/moved/harbor/hub/repo"
t_eq "a state folder or HOME in env is not where the clone is read" "$MH/.local/state/harbor/hub/repo" "$(mr XDG_STATE_HOME="$T_TMP/moved" HOME="$T_TMP/home2")"
mv "$MR/member.conf" "$T_TMP/conf.keep"
t_eq "no member.conf: nothing, whatever env says" '' "$(mr HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=o/h XDG_STATE_HOME="$T_TMP/moved")"
t_eq "...and exit 1" 1 "$(cd "$T_TMP" && HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=o/h XDG_STATE_HOME="$T_TMP/moved" sh "$MR/bin/scope-roots.sh" --hub >/dev/null 2>&1; echo $?)"
mv "$T_TMP/conf.keep" "$MR/member.conf"
t_eq "run by a bare name from inside the root, it can't find the file, so nothing" '' "$(cd "$MR/bin" && HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=o/h XDG_STATE_HOME="$T_TMP/moved" sh scope-roots.sh --hub 2>/dev/null)"
t_done
