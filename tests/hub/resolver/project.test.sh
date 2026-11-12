#!/usr/bin/env sh
# project.test.sh (harbor#1278, R28) — `harbor hub project register`: a checkout is registered, listed and routed with no yard, uv or just,
# no scaffolder and no workflow; the steps a core install cannot run are said, and only health counts come back.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
mkinst
HOME="$T_TMP/box/home"; PORT_ROOT="$HOME/port"; CLAUDE_CONFIG_DIR="$HOME/.claude"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"; export HOME PORT_ROOT CLAUDE_CONFIG_DIR
sh "$T_ROOT/bin/scope.sh" install >/dev/null 2>&1
PV="$PORT_ROOT/harbor-private"
_hk="$(printf '%s' "$(CDPATH= cd -P -- "$HOME" && pwd -P)" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$_hk/memory"; printf 'a note\n' > "$CLAUDE_CONFIG_DIR/projects/$_hk/memory/note.md"
# A scaffolder that records any call: a core install has none, so nothing may call it.
printf '#!/bin/sh\necho called >> "%s/scaffolder.called"\nexit 1\n' "$T_TMP" > "$T_BIN/project-init"; chmod +x "$T_BIN/project-init"
export HARBOR_SCOPE_SCAFFOLDER_BIN="$T_BIN/project-init"
mkdir -p "$PORT_ROOT/mywork"; git -C "$PORT_ROOT/mywork" init -q
out() { env -u CLAUDE_CONFIG_DIR CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" sh "$INST/bin/hub.sh" "$@" 2>&1; }

t_section "1 - register adds the project and says what a core install cannot do"
_o="$(out project register mywork --covers "a member project")"; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_has "R28 is said, not hidden" "$_o" "no yard, uv or just"
t_eq "the registry has the row" "mywork" "$(awk -F'\t' '$1 == "mywork" { print $1 }' "$PV/repos.tsv")"
t_eq "...as kind workload" workload "$(awk -F'\t' '$1 == "mywork" { print $3 }' "$PV/repos.tsv")"
t_eq "projects.tsv lists it" "mywork" "$(awk -F'\t' '$1 == "mywork" { print $1 }' "$PV/context-rules/user/projects.tsv")"
t_eq "memory is routed to it" yes "$([ -n "$(find "$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$(CDPATH= cd -P -- "$PORT_ROOT/mywork" && pwd -P)" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')/memory/" -name '*.md' 2>/dev/null | head -n 1)" ] && echo yes || echo no)"
t_has "only health counts come back" "$_o" "health: steps"
t_has "...and name what was not run" "$_o" "not run on a core install: steps scaffold labels versions fleet"
t_eq "the scaffolder was never called" no "$([ -e "$T_TMP/scaffolder.called" ] && echo yes || echo no)"
t_eq "no workflow was written into the checkout" 0 "$(find "$PORT_ROOT/mywork" -path '*/.github/*' -not -path '*/.git/*' | wc -l | tr -d ' ')"
t_eq "a second register is idempotent" 0 "$(out project register mywork --covers "a member project" >/dev/null; echo $?)"
t_eq "...one registry row" 1 "$(grep -c '^mywork	' "$PV/repos.tsv")"

t_section "2 - refusals"
t_eq "a project with no checkout is refused (2)" 2 "$(out project register ghost >/dev/null; echo $?)"
t_eq "a bad name is refused (2)" 2 "$(out project register '../x' >/dev/null; echo $?)"
t_has "repo new --core-only is refused: new needs the scaffolder" "$(env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/scope-repo.sh" new zz --kind workload --core-only 2>&1)" "needs the scaffolder"
t_done
