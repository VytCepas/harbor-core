#!/usr/bin/env sh
# The rule layout (harbor#1010, D-43, D-65): context-rules/<scope>/<id>.md with the id derived and the order
# from `order:`; the old inject.d/ is retired and not read. engine.test.sh drives the layout end to end.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
. "$T_ROOT/tests/context/injection-rule/fixture.sh"
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

t_section "the old inject.d tree is retired: it is not read"
note OLD-BOX 'id: from-old-box
' | pack "$CFG/inject.d" 10-from-old-box.md
note OLD-REPO 'id: from-old-repo
' | pack "$REPO/.claude/inject.d" 10-from-old-repo.md
note NEW-BOX-CONTROL | pack "$NEWBOX" control.md
t_has "control: a rule in the new tree fires in the same run" "$(sub)" NEW-BOX-CONTROL
gone "an old box rule does not fire" "$(sub)" OLD-BOX
gone "an old repo rule does not fire" "$(sub)" OLD-REPO
rm -f "$NEWBOX"/*.md "$CFG"/inject.d/*.md "$REPO"/.claude/inject.d/*.md

t_section "order: sorts a tier; an old NN- name sorts by its number; no order sorts last"
note C 'order: 30
' | pack "$NEWBOX" c-first-by-name.md
note A 'order: 10
' | pack "$NEWBOX" zz-last-by-name.md
note Z | pack "$NEWBOX" aa-unordered.md
note B 'id: b-old
' | pack "$NEWBOX" 20-b-old.md
t_eq "order 10, old 20-, order 30, then the unordered rule" \
  '[context:zz-last-by-name] [context:b-old] [context:c-first-by-name] [context:aa-unordered] ' "$(ctx)"
t_eq "--list prints the tier in the same order" 'zz-last-by-name.md 20-b-old.md c-first-by-name.md aa-unordered.md ' \
  "$(CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" --list | awk 'index($0, ".md ") { n = $1; sub(/.*\//, "", n); printf "%s ", n }')"
rm -f "$NEWBOX"/*.md

t_section "the registry lives with the box tier"
OT="$T/other"; mkdir -p "$OT/context-rules/other"; ( cd "$OT" && git init -q . )
printf -- '---\nevent: PreToolUse\nscope: box\nwhen: always\nonce: never\n---\nTRAVELS\n' > "$OT/context-rules/other/travel.md"
reach() { fire "$(tool_ev PreToolUse Read file_path "$OT/README.md" r1)"; }
gone "an unregistered tree's rules stay home" "$(reach)" TRAVELS
mkdir -p "$CFG/inject.d"; printf 'other\t%s\tfixture\n' "$OT" > "$CFG/inject.d/projects.tsv"
gone "the old registry is not read" "$(reach)" TRAVELS
printf 'other\t%s\tfixture\n' "$OT" > "$NEWBOX/projects.tsv"
t_has "a tree the registry names is reached through context-rules/<scope>" "$(reach)" TRAVELS
t_done
