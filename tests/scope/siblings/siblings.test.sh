#!/usr/bin/env sh
# harbor#966 / #999: bin/ names no sibling repo literally except the two scaffolder identifiers the hash-pinned floor
# cannot look up, and renaming the scaffolder in the repo registry changes no floor verdict.
. "$(dirname "$0")/../../lib/core.sh"; t_init
# The sibling repos' old names. `helm-log-token` is a credential FILE name on the box (#962), not the repo, so it is not matched.
NAMES='projects-orchestrator|project-init|helm-log([^-]|$)'

t_section "bin/ names a sibling repo only in the floor's two named constants"
HITS="$(git -C "$T_ROOT" grep -n -E "$NAMES" -- 'bin/*' 2>/dev/null || :)"
t_eq "the only file is the floor library" "bin/library-admission.sh" "$(printf '%s\n' "$HITS" | cut -d: -f1 | sort -u)"
t_eq "...and only the two constant lines" 2 "$(printf '%s\n' "$HITS" | grep -c .)"
t_has "...one is the legacy marker file" "$HITS" 'FLOOR_SCAFFOLDER_MARKER_LEGACY="project-init.md"'
t_has "...one is the lifecycle plugin id" "$HITS" 'FLOOR_SCAFFOLDER_LIFECYCLE_PLUGIN="project-init-lifecycle"'
t_eq "no other script spells either name (a call site uses the constant)" 0 \
  "$(git -C "$T_ROOT" grep -n -E 'project-init\.md|project-init-lifecycle' -- 'bin/*' | grep -v '^bin/library-admission.sh' | grep -c . || :)"

t_section "contracts/marker.md freezes both names"
t_has "the legacy marker file" "$(cat "$T_ROOT/contracts/marker.md")" '.agents/project-init.md'
t_has "the lifecycle plugin id" "$(cat "$T_ROOT/contracts/marker.md")" 'project-init-lifecycle'

t_done
