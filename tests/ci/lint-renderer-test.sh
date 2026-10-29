#!/usr/bin/env sh
# bin/lint-renderer.sh (harbor#978 item 8, rule name.renderer-used) on a fixture tree: a registered writer that
# calls the renderer is clean, one that does not warns, a creating script outside the census warns, and only a
# block rule fails the run. Born warn (D-64).
. "$(dirname "$0")/../lib/core.sh"; t_init
LR="$T_ROOT/bin/lint-renderer.sh"
F="$T_TMP/fx"
mk() { rm -rf "$F"; mkdir -p "$F/bin" "$F/hooks" "$F/standards/naming"; cp "$T_ROOT/bin/log-lib.sh" "$F/bin/"
  cp "$T_ROOT/standards/naming/writers.tsv" "$F/standards/naming/"
  printf 'name.renderer-used\twarn\tcheck\tbin/lint-renderer.sh\n' > "$F/standards/naming/controls.tsv"
  printf '%s\n' '#!/bin/sh' 'N="$(sh bin/lint-name.sh --render branch type=fix issue=1 slug=x)"' 'git switch -c "$N"' > "$F/bin/worktree.sh"
  printf '%s\n' '#!/bin/sh' 'N="$(sh bin/lint-name.sh --render issue-title family=a)"' 'gh issue create --title "$N"' > "$F/bin/findings.sh"
  printf '%s\n' '#!/bin/sh' 'N="$(sh bin/lint-name.sh --render branch type=ci issue=1 slug=x)"' 'git switch -c "$N"' > "$F/bin/ci-runs-on.sh"; }
run() { HARBOR_ROOT="$F" sh "$LR" "$@" 2>&1; }

t_section "writers that call the renderer are clean"
mk; out="$(run)"; rc=$?
t_has "no warning" "$out" "0 failed, 0 warnings"
t_eq "exit 0" 0 "$rc"

t_section "a writer that builds the name by hand warns"
mk; printf '%s\n' '#!/bin/sh' 'git switch -c "fix/$1"' > "$F/bin/worktree.sh"
out="$(run)"; rc=$?
t_has "names the rule" "$out" "[name.renderer-used] bin/worktree.sh"
t_eq "warn mode exits 0" 0 "$rc"

t_section "a creating script outside the census is a finding"
mk; printf '%s\n' '#!/bin/sh' 'gh pr create --title t' > "$F/bin/newwriter.sh"
t_has "names the unregistered script" "$(run)" "bin/newwriter.sh creates a named thing but is in no writer row"
mk; printf '%s\n' '#!/bin/sh' '# gh pr create --title t, in a comment only' > "$F/bin/talker.sh"
t_has "a comment is not a command" "$(run)" "0 failed, 0 warnings"
mk; printf '%s\n' '#!/bin/sh' 'git worktree add --detach /x HEAD' > "$F/bin/detached.sh"
t_has "a detached worktree names nothing" "$(run)" "0 failed, 0 warnings"

t_section "a registered writer that is gone warns; only block fails"
mk; rm "$F/bin/findings.sh"
t_has "missing writer" "$(run)" "bin/findings.sh is a registered writer but is not there"
mk; printf '%s\n' '#!/bin/sh' 'git switch -c x' > "$F/bin/worktree.sh"
sed 's/\twarn\t/\tblock\t/' "$F/standards/naming/controls.tsv" > "$F/c" && mv "$F/c" "$F/standards/naming/controls.tsv"
out="$(run)"; rc=$?
t_eq "a block rule exits 1" 1 "$rc"
t_has "and prints FAIL with its id" "$out" "FAIL: [name.renderer-used]"

t_section "usage"
t_exit "an unknown flag" 2 sh "$LR" --nope
t_exit "--help" 0 sh "$LR" --help
t_done
