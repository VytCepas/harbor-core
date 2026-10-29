#!/usr/bin/env sh
# The rule layout (harbor#1010, D-43, D-65): context-rules/<scope>/<id>.md with the id derived and the order
# from `order:`, and the old inject.d/ still read for one release, the new tree winning an id clash.
# engine.test.sh drives the old layout end to end; this suite is the new one and the two side by side.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/inject-fixture.sh"
NEWBOX="$CFG/context-rules/user"; NEWREPO="$REPO/context-rules/repo"
note() { printf -- '---\nevent: SubagentStart\nwhen: always\nonce: never\n%s---\n%s\n' "${2:-}" "$1"; }
sub() { fire '{"hook_event_name":"SubagentStart","session_id":"l"}'; }
ctx() { sub | jq -r '.hookSpecificOutput.additionalContext // empty' | grep -o '\[context:[^]]*\]' | tr '\n' ' '; }

t_section "the new tree fires, and the id is the file name"
note NEW-BOX | pack "$NEWBOX" from-new-box.md
t_has "a user rule in context-rules/user fires" "$(sub)" NEW-BOX
t_has "its id is derived from the file name" "$(sub)" '[context:from-new-box]'
note NEW-REPO | pack "$NEWREPO" from-new-repo.md
t_has "a repo rule in context-rules/<repo> fires" "$(sub)" NEW-REPO
note REPO-USER-SCOPE | pack "$REPO/context-rules/user" stray.md
gone "a repo's context-rules/user is the box tier's source and is never read in the repo" "$(sub)" REPO-USER-SCOPE
rm -rf "$REPO/context-rules/user" "$NEWBOX"/*.md "$NEWREPO"/*.md

t_section "the old tree still fires for one release"
note OLD-BOX 'id: from-old-box
' | pack "$CFG/inject.d" 10-from-old-box.md
note OLD-REPO 'id: from-old-repo
' | pack "$REPO/.claude/inject.d" 10-from-old-repo.md
t_has "an old box rule fires" "$(sub)" OLD-BOX
t_has "an old repo rule fires" "$(sub)" OLD-REPO

t_section "on an id clash the new tree wins, once"
note NEW-WINS | pack "$NEWBOX" from-old-box.md
note NEW-REPO-WINS | pack "$NEWREPO" from-old-repo.md
t_has "the new box rule fires" "$(sub)" NEW-WINS
gone "the old box rule with the same id does not" "$(sub)" OLD-BOX
t_has "the new repo rule fires" "$(sub)" NEW-REPO-WINS
gone "the old repo rule with the same id does not" "$(sub)" OLD-REPO
t_eq "each id is delivered once" 1 "$(sub | grep -o '\[context:from-old-box\]' | wc -l | tr -d ' ')"
rm -f "$NEWBOX"/*.md "$NEWREPO"/*.md "$CFG"/inject.d/*.md "$REPO"/.claude/inject.d/*.md

t_section "order: sorts a tier; an old NN- name sorts by its number; no order sorts last"
note C 'order: 30
' | pack "$NEWBOX" c-first-by-name.md
note A 'order: 10
' | pack "$NEWBOX" zz-last-by-name.md
note Z | pack "$NEWBOX" aa-unordered.md
note B 'id: b-old
' | pack "$CFG/inject.d" 20-b-old.md
t_eq "order 10, old 20-, order 30, then the unordered rule" \
  '[context:zz-last-by-name] [context:b-old] [context:c-first-by-name] [context:aa-unordered] ' "$(ctx)"
t_eq "--list prints the tier in the same order" 'zz-last-by-name.md 20-b-old.md c-first-by-name.md aa-unordered.md ' \
  "$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" --list | awk 'index($0, ".md ") { n = $1; sub(/.*\//, "", n); printf "%s ", n }')"
rm -f "$NEWBOX"/*.md "$CFG"/inject.d/*.md

t_section "the registry moves with the box tier"
OT="$T/other"; mkdir -p "$OT/context-rules/other"; ( cd "$OT" && git init -q . )
printf -- '---\nevent: PreToolUse\nscope: box\nwhen: always\nonce: never\n---\nTRAVELS\n' > "$OT/context-rules/other/travel.md"
reach() { fire "$(tool_ev PreToolUse Read file_path "$OT/README.md" r1)"; }
gone "an unregistered tree's rules stay home" "$(reach)" TRAVELS
printf 'other\t%s\tfixture\n' "$OT" > "$CFG/inject.d/projects.tsv"
t_has "the old registry is read while no new one is installed" "$(reach)" TRAVELS
: > "$NEWBOX/projects.tsv"
gone "a new registry wins over the old one" "$(reach)" TRAVELS
printf 'other\t%s\tfixture\n' "$OT" > "$NEWBOX/projects.tsv"
t_has "a tree the new registry names is reached through context-rules/<scope>" "$(reach)" TRAVELS
t_done
