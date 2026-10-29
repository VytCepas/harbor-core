#!/usr/bin/env sh
# Which tree a note belongs to, through inject-hook.sh and its shipped scripts: a linked
# worktree is its project, an access failure names its route card, a `scope: box` pack
# follows the call into a REGISTERED repo only, and repo-tier reports what stayed home
# (harbor#599, #619, 2026-08-28, 2026-09-24).
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/inject-fixture.sh"

t_section "project-pointer: a linked worktree is the same project"
PP="$T_ROOT/context-rules/user/project-pointer.sh"; W="$T/wtcase"
mkdir -p "$W/home/proj" "$W/home/decoy" "$W/pack" "$W/elsewhere"
( cd "$W/home/proj" && git init -q . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
  && git worktree add -q -b wtbranch "$W/home/projwt" ) >/dev/null 2>&1
cp "$PP" "$W/pack/project-pointer.sh"
# The decoy is required: the pack is silent when the only registered project is the current one.
printf 'proj\t~/proj\tthe project under test\ndecoy\t~/decoy\tsomething else entirely\n' > "$W/pack/projects.tsv"
_pp() { ( cd "$1" && HOME="$W/home" sh "$W/pack/project-pointer.sh" 2>/dev/null ); }
t_eq "git worktree add produced a tree" yes "$([ -d "$W/home/projwt" ] && echo yes)"
_o="$(_pp "$W/home/projwt")"
t_has "a linked worktree is recognised as its project" "$_o" 'YOU ARE IN: proj'
t_has "the worktree is named as a worktree" "$_o" 'linked worktree'
t_hasnt "the current project is omitted from the elsewhere list" "$_o" '- proj (~/proj)'
_o="$(_pp "$W/home/proj")"
t_has "the main checkout still resolves to its project" "$_o" 'YOU ARE IN: proj'
t_hasnt "the main checkout is not labelled a worktree" "$_o" 'linked worktree'
t_has "the decoy is listed from the main checkout" "$_o" '- decoy (~/decoy)'
t_has "a directory outside every project is still unmatched" "$(_pp "$W/elsewhere")" 'NOT IN A REGISTERED PROJECT'
mkdir -p "$W/home/proj"/sub
printf 'subproj\t~/proj/sub\ta subdirectory, not a repo root\ndecoy\t~/decoy\tsomething else\n' > "$W/pack/projects.tsv"
t_hasnt "a registered subdirectory does not claim the whole repository" "$(_pp "$W/home/proj")" 'YOU ARE IN: subproj'

t_section "8c · an access failure names its route card and account (2026-09-24)"
ACCCFG="$T/acccfg"; mkdir -p "$ACCCFG/inject.d" "$T/access"
cp "$T_ROOT/context-rules/user/access-route-pointer.md" "$T_ROOT/context-rules/user/access-route.sh" "$ACCCFG/inject.d/"
# The command-to-card table is the register's own (<register>/routes.tsv, harbor#1149); core ships none, so the fixture writes one.
printf 'example-project|api\\.example\\.test\texample\n@B@gcloud \tgcloud\n' > "$T/access/routes.tsv"
cat > "$T/access/example.md" <<'CARD'
# example — fixture

    account:  owner@example.com | primary | owner; UI admin | gcx me
    account:  tools@example.com | fallback | owner; UI viewer | gcx tools
    account:  analytics@example.com | never | fixture | -
CARD
acc() { # <command> <stderr> <session> → the engine's stdout
  jq -cn --arg c "$1" --arg e "$2" --arg s "$3" \
    '{hook_event_name:"PostToolUse",tool_name:"Bash",session_id:$s,tool_input:{command:$c},tool_response:{stdout:"",stderr:$e,interrupted:false}}' \
    | HARBOR_REPO="$T_ROOT" ACCESS_DIR="${ACC_DIR:-$T/access}" CLAUDE_CONFIG_DIR="$ACCCFG" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null
}
_acc="$(acc 'gcx me bq ls example-project:core_marts' 'ERROR: (bq) Reauthentication failed.' a1)"
t_has "an expired login on a routed command names its card" "$_acc" 'Access failure on **example**'
t_has "the card's primary account" "$_acc" 'use `owner@example.com` (gcx me)'
t_has "the card's fallback account" "$_acc" 'fall back to `tools@example.com`'
t_has "the card's never account" "$_acc" 'never `analytics@example.com`'
t_has "on a model-visible channel" "$_acc" 'additionalContext'
t_eq "reading ABOUT access is silent" "" "$(acc 'grep -rn PERMISSION_DENIED harbor-private/access/' 'gcloud.md: PERMISSION_DENIED' a2)"
t_eq "a mapped call that names the private layer is reading about access, so silent" "" "$(acc 'gcx me bq ls example-project:x harbor-private/access/example.md' 'Reauthentication failed.' a2b)"
t_eq "reading source behind a leading cd is silent" "" "$(acc 'cd /r && sed -n 1,40p deploy-example-project.sh' 'die "PERMISSION_DENIED means"' a7)"
t_eq "a call that worked is silent" "" "$(acc 'gcx me bq ls example-project:core_marts' '' a3)"
t_eq "a 403 from a system with no card is silent" "" "$(acc 'curl -sS https://example.com/x' '403 Forbidden' a4)"
t_eq "a mapped system whose card is absent is silent" "" "$(acc 'gcloud projects list' 'PERMISSION_DENIED' a5)"
t_eq "no access register at all (core ships no cards) is silent, not an error" "" "$(ACC_DIR="$T/no-register" acc 'gcx me bq ls example-project:core_marts' 'ERROR: (bq) Reauthentication failed.' a8)"
acc 'gcx me bq ls example-project:x' 'Reauthentication failed.' a6 >/dev/null
t_eq "the same failure retried is told once" "" "$(acc 'gcx me bq ls example-project:x' 'Reauthentication failed.' a6)"
t_has "a different failure in the same session is told again" "$(acc 'curl https://api.example.test/users' 'HTTP/2 403' a6)" 'Access failure on **example**'

# The routes table is data now (harbor#1149), so its semantics are asserted here, not inherited from a heredoc.
ACC2="$T/access2"; mkdir -p "$ACC2"; cp "$T/access/example.md" "$ACC2/example.md"; cp "$T/access/example.md" "$ACC2/github.md"
printf '# first match wins; @B@ is a word boundary\nexample-project\texample\n@B@gh \tgithub\n' > "$ACC2/routes.tsv"
_r1="$(ACC_DIR="$ACC2" acc 'gh pr view 1 --repo example-project/x' '403 Forbidden' r1)"
t_has "the first matching row wins: a gh call naming the project is the project's" "$_r1" 'Access failure on **example**'
t_hasnt "...and not the later gh row's" "$_r1" '**github**'
t_has "a later row still routes when no earlier one matches" "$(ACC_DIR="$ACC2" acc 'gh pr view 1' '403 Forbidden' r2)" 'Access failure on **github**'
t_eq "@B@ is a boundary: gh inside a longer word is not gh" "" "$(ACC_DIR="$ACC2" acc 'high pr view 1' '403 Forbidden' r3)"
t_has "@B@ admits the start of a compound: a pipe directly before gh" "$(ACC_DIR="$ACC2" acc 'true|gh pr view 1' '403 Forbidden' r3b)" 'Access failure on **github**'
ACC3="$T/access3"; mkdir -p "$ACC3"; cp "$T/access/example.md" "$ACC3/example.md"
t_eq "a register with cards and no routes table is silent, not an error" "" "$(ACC_DIR="$ACC3" acc 'gcx me bq ls example-project:x' 'Reauthentication failed.' r4)"
ACC4="$T/access4"; mkdir -p "$ACC4"; cp "$T/access/example.md" "$T/outside.md"
printf 'walks-out\t../outside\n' > "$ACC4/routes.tsv"
t_eq "a row cannot name a card outside the register" "" "$(ACC_DIR="$ACC4" acc 'walks-out now' '403 Forbidden' r5)"

t_section "scope: box · a repo rule that follows the call (harbor#599)"
# The session stands in no repository. alpha is REGISTERED, with one pack that did not
# consent; beta consents but is NOT registered, which is the trust boundary under test.
SB="$T/sb"; SBC="$SB/cfg"; WS="$SB/ws"; A="$WS/alpha"; B="$WS/beta"
mkdir -p "$SBC/inject.d" "$A/.claude/inject.d" "$B/.claude/inject.d"
scoped() { # <dir> <file> <id> <when> <scope> <body>
  printf -- '---\nid: %s\nevent: PreToolUse\nwhen: %s\n%s---\n%s\n' "$3" "$4" "${5:+scope: $5
}" "$6" > "$1/$2"
}
scoped "$A/.claude/inject.d" 10-consents.md alpha-consents always box ALPHA-CONSENTS
scoped "$A/.claude/inject.d" 20-private.md alpha-private always '' ALPHA-PRIVATE
scoped "$A/.claude/inject.d" 30-marker.md alpha-marker 'repo-has MARKER.txt' box ALPHA-HAS-MARKER
printf -- '---\nid: alpha-run\nevent: PreToolUse\nwhen: always\nscope: box\nrun: where.sh\n---\n' > "$A/.claude/inject.d/40-run.md"
printf '#!/usr/bin/env sh\nprintf "RAN-IN %%s\\n" "$(pwd -P)"\n' > "$A/.claude/inject.d/where.sh"
printf 'x\n' > "$A/MARKER.txt"
scoped "$B/.claude/inject.d" 10-consents.md beta-consents always box BETA-CONSENTS
for _r in "$A" "$B"; do
  ( cd "$_r" && git init -q . && git config user.email t@t && git config user.name t \
    && git config commit.gpgsign false && printf 'x\n' > README.md && git add -A && git commit -qm init ) >/dev/null 2>&1
done
git -C "$A" remote add origin https://github.com/fixture/alpha.git
git -C "$A" worktree add -q "$WS/feature" -b feature >/dev/null 2>&1  # a name that gives no hint of its owner
printf 'alpha\t%s\tthe fixture repo\n' "$A" > "$SBC/inject.d/projects.tsv"
PA="$(CDPATH='' cd -P -- "$A" && pwd -P)"
reach() { # <payload> [project dir]
  printf '%s' "$1" | CLAUDE_CONFIG_DIR="$SBC" CLAUDE_PROJECT_DIR="${2:-$WS}" PORT_ROOT="$WS" sh "$SUT" 2>/dev/null
}
rd() { jq -cn --arg p "$1" --arg c "$2" '{hook_event_name:"PreToolUse",tool_name:"Read",tool_input:{file_path:$p},cwd:$c}'; }
sh_ev() { jq -cn --arg x "$1" --arg c "$2" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$x},cwd:$c}'; }
_r="$(reach "$(rd "$A/README.md" "$WS")")"
t_has "a Read into a registered repo delivers its consenting pack" "$_r" 'ALPHA-CONSENTS'
t_hasnt "a pack that did not declare scope: box stays home" "$_r" 'ALPHA-PRIVATE'
t_has "repo-has is judged in the reached tree, not the workspace" "$_r" 'ALPHA-HAS-MARKER'
t_has "a run: pack runs from its own tree" "$_r" "RAN-IN $PA"
gone "the registry is the trust boundary: an unregistered repo is not reached" "$(reach "$(rd "$B/README.md" "$WS")")" 'BETA-CONSENTS'
t_has "a worktree of a registered repo counts as its owner" "$(reach "$(rd "$WS/feature/README.md" "$WS")")" 'ALPHA-CONSENTS'
t_has "git -C reaches the tree it names" "$(reach "$(sh_ev "git -C $A status" "$WS")")" 'ALPHA-CONSENTS'
t_has "gh -R reaches the checkout its slug names" "$(reach "$(sh_ev 'gh pr create -R Fixture/Alpha --fill' "$WS")")" 'ALPHA-CONSENTS'
t_has "a shell call standing in the tree reaches it" "$(reach "$(sh_ev 'ls' "$A")")" 'ALPHA-CONSENTS'
gone "a call that names no tree reaches none" "$(reach "$(sh_ev 'ls' "$WS")")" 'ALPHA-'
gone "a quoted mention of -C is data" "$(reach "$(sh_ev "git commit -m \"run git -C $A first\"" "$WS")")" 'ALPHA-'
gone "a heredoc body is data" "$(reach "$(sh_ev "cat <<'EOF'
git -C $A status
EOF" "$WS")")" 'ALPHA-'
gone "cd X && … is not followed (the #599 decision)" "$(reach "$(sh_ev "cd $A && ls" "$WS")")" 'ALPHA-'
gone "only a tool call reaches a tree" "$(reach "$(jq -cn --arg c "$A" '{hook_event_name:"SessionStart",source:"startup",cwd:$c}')")" 'ALPHA-'
_r="$(reach "$(rd "$A/README.md" "$A")" "$A")"
t_eq "inside its own repo the pack is delivered once, not twice" 1 "$(printf '%s' "$_r" | grep -o 'ALPHA-CONSENTS' | wc -l | tr -d ' ')"
t_has "inside its own repo a home-only pack still loads" "$_r" 'ALPHA-PRIVATE'

t_section "repo-tier: the report reads the same answer the sweep acted on"
cp "$T_ROOT/context-rules/user/repo-tier-not-loaded.md" "$T_ROOT/context-rules/user/repo-tier.sh" "$SBC/inject.d/"
t_has "names what crossed and what stayed home" "$(reach "$(rd "$A/README.md" "$WS")")" \
  'NOT govern this session: alpha-private (delivered anyway, because they declare scope: box: alpha-consents alpha-marker alpha-run)'
_rb="$(reach "$(rd "$B/README.md" "$WS")")"
t_has "an unregistered tree loses even its consenting rule, and says so" "$_rb" 'NOT govern this session: beta-consents.'
t_has "the loss is reported under its heading" "$_rb" 'REPO RULES NOT LOADED'
rm -f "$A/.claude/inject.d/20-private.md"
gone "a tree whose every rule crossed is not reported" "$(reach "$(rd "$A/README.md" "$WS")")" 'REPO RULES NOT LOADED'
t_done
