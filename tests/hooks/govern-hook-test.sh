#!/usr/bin/env sh
# govern-hook.sh is CONDITIONAL: silent on ordinary work, a real verdict on a merge, and
# its four known matcher holes pinned as misses (harbor#7, #213, #254, PR #262). The git
# hooks in hooks/ ride here too, because suite-paths selects this suite on hooks/*.
REAL_HOME="$HOME"  # the in-session gh shim mints its token from $HOME, which t_init replaces
. "$(dirname "$0")/../lib/core.sh"; t_init
SUT="$T_ROOT/bin/govern-hook.sh"; HOOKS="$T_ROOT/hooks"; T="$T_TMP"
fire() { # <event> <command> [repo] → the hook's stdout
  printf '%s' "$2" | jq -Rs --arg e "$1" '{hook_event_name:$e,tool_name:"Bash",tool_input:{command:.}}' \
    | CLAUDE_PROJECT_DIR="${3:-$REPO}" sh "$SUT" 2>/dev/null
}
gitq() { git "$@" >/dev/null 2>&1; }
id_cfg() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }

# A repo with a real origin: one --no-ff merged branch, one unmerged, one squash-merged in two commits.
ORIGIN="$T/origin.git"; REPO="$T/work"
gitq init --bare "$ORIGIN"; gitq clone "$ORIGIN" "$REPO"; id_cfg "$REPO"
( cd "$REPO" && mkdir -p bin && printf 'x\n' > bin/merge-check.sh && git add -A && git commit -qm init \
  && git branch -M main && git push -qu origin main \
  && git checkout -qb done-branch && printf 'y\n' >> bin/merge-check.sh && git commit -qam work \
  && git checkout -q main && git merge -q --no-ff -m merge done-branch && git push -q origin main \
  && git checkout -qb live-branch && printf 'z\n' >> bin/merge-check.sh && git commit -qam wip \
  && git checkout -qb squashed-branch main && printf 'sq1\n' > bin/squashed && git add -A && git commit -qm sq1 \
  && printf 'sq2\n' >> bin/squashed && git commit -qam sq2 && git checkout -q main \
  && git merge -q --squash squashed-branch && git commit -qm 'squash: squashed-branch' \
  && git push -q origin main ) >/dev/null 2>&1

t_section "1 · silence on everything that is not a merge"
t_eq "an unrelated command" "" "$(fire PreToolUse 'ls -la')"
t_eq "a quoted mention" "" "$(fire PreToolUse 'echo "gh pr merge 172"')"
t_eq "the phrase in a commit message" "" "$(fire PreToolUse 'git commit -m "gh pr merge"')"
t_eq "a sibling gh verb" "" "$(fire PreToolUse 'gh pr list')"
t_eq "gh pr view" "" "$(fire PreToolUse 'gh pr view 172 --json mergeable')"

t_section "2 · the PreToolUse route"
out="$(fire PreToolUse 'gh pr merge 172 --squash')"
t_has "a real merge routes to merge-check.sh" "$out" 'merge-check.sh'
t_has "the envelope is hookSpecificOutput" "$out" 'hookSpecificOutput'
t_has "the PreToolUse envelope is correct" "$out" '"hookEventName":"PreToolUse"'
t_eq "the emission is valid JSON" 0 "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1; echo $?)"
t_has "a merge after && is caught" "$(fire PreToolUse 'cd /tmp && gh pr merge 172')" 'merge-check.sh'
t_has "irregular whitespace is caught" "$(fire PreToolUse 'gh  pr   merge 172')" 'merge-check.sh'
t_has "a merge after ; is caught" "$(fire PreToolUse 'echo hi; gh pr merge 172')" 'merge-check.sh'
t_has "--admin adds the override-record clause" "$(fire PreToolUse 'gh pr merge 172 --admin')" 'audit log'
t_hasnt "the --admin clause stays off without it" "$out" 'audit log'
BARE="$T/bare"; mkdir -p "$BARE"; gitq -C "$BARE" init; id_cfg "$BARE"
t_eq "no merge-check.sh in the repo means no advice" "" "$(fire PreToolUse 'gh pr merge 172' "$BARE")"

t_section "2b · the backstop's verdict, not a reminder about it (harbor#254)"
MC="$T/mc"; mkdir -p "$MC/bin"; gitq -C "$MC" init; id_cfg "$MC"
( cd "$MC" && printf 'x\n' > README && git add -A && git commit -qm init ) >/dev/null 2>&1
stub() { printf '#!/usr/bin/env sh\nprintf "%%s\\n" "%s"\nexit %s\n' "$2" "$1" > "$MC/bin/merge-check.sh"; }  # <exit> <text>
stub 1 'REFUSED  a check is not passing on #253: detect-and-defer fixtures pending'
out="$(fire PreToolUse 'sh bin/merge-check.sh 253 2>&1 | tail -2 && gh pr merge 253 --squash --delete-branch' "$MC")"
t_eq "the deny is valid JSON" 0 "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1; echo $?)"
t_has "THE INCIDENT is denied" "$out" '"permissionDecision":"deny"'
t_has "the backstop's own words reach the reason" "$out" 'detect-and-defer fixtures pending'
t_has "the deny names the one-process route" "$out" '--merge 253'
t_has "and the override that leaves a record" "$out" '--force'
stub 0 'ok  #253 — 12 check(s) pass, 2 of them required'
out="$(fire PreToolUse 'gh pr merge 253 --squash' "$MC")"
t_hasnt "a green PR is not interrupted" "$out" 'permissionDecision'
t_has "the pass is stated, not assumed" "$out" 'consulted for #253'
stub 2 'merge-check: gh is not installed'
out="$(fire PreToolUse 'gh pr merge 253' "$MC")"
t_hasnt "a tooling fault fails OPEN" "$out" 'permissionDecision'
t_has "and an unverified merge says so" "$out" 'could NOT be consulted'
stub 1 'REFUSED  nope'
t_has "the PR number comes from the command" "$(fire PreToolUse 'gh pr merge 999 --squash' "$MC")" '--merge 999'
t_eq "--help is a read and reaches no verdict" "" "$(fire PreToolUse 'gh pr merge --help' "$MC")"

t_section "2c · every invocation, its own target (PR #262)"
t_has "the FIRST invocation is judged" "$(fire PreToolUse 'gh pr merge 10 && gh pr merge 20' "$MC")" '--merge 10'
t_has "a value-taking flag does not swallow the target" "$(fire PreToolUse 'gh pr merge --subject 42 261' "$MC")" '--merge 261'
t_has "a URL target is parsed" "$(fire PreToolUse 'gh pr merge https://github.com/o/r/pull/7 --squash' "$MC")" '--merge 7'
_da="$(fire PreToolUse 'gh pr merge 253 --disable-auto' "$MC")"
t_hasnt "--disable-auto reaches no verdict" "${_da:-<empty>}" 'permissionDecision'
printf '#!/usr/bin/env sh\nprintf "REFUSED  saw repo=%%s pr=%%s\\n" "${HARBOR_REPO:-none}" "$1"\nexit 1\n' > "$MC/bin/merge-check.sh"
t_has "-R is handed to the backstop with that invocation's number" "$(fire PreToolUse 'gh pr merge -R other/repo 7' "$MC")" 'repo=other/repo pr=7'
# harbor#1153: the PR's own repo, judged by that repo's checks. The stub passes only for the repo it is handed.
printf '#!/usr/bin/env sh\ncase "${HARBOR_REPO:-none}" in second/repo) echo "ok  checks green in second/repo"; exit 0 ;; *) echo "REFUSED  checks missing in ${HARBOR_REPO:-none}"; exit 1 ;; esac\n' > "$MC/bin/merge-check.sh"
for _c in 'gh pr merge 7 -R second/repo --auto' 'gh pr merge 7 --repo second/repo' 'gh pr merge 7 --repo=second/repo' 'gh pr merge -Rsecond/repo 7'; do
  _o="$(fire PreToolUse "$_c" "$MC")"
  t_hasnt "second repo is judged by its own checks: $_c" "$_o" 'permissionDecision'
  t_has "…and the pass names it: $_c" "$_o" 'consulted for #7'
done
t_has "a merge with no -R is still judged by this repo" "$(fire PreToolUse 'gh pr merge 7' "$MC")" 'checks missing in none'
# The flag list copies gh's interface, so it is checked against gh.
if command -v gh >/dev/null 2>&1; then
  # A value-taking flag is `--flag <type>  Description`; the old pattern missed --body-file and --match-head-commit.
  _flags="$(HOME="$REAL_HOME" gh pr merge --help 2>/dev/null \
    | sed -n 's/^[[:space:]]*\(-[a-zA-Z], \)\{0,1\}\(--[a-z-]*\) [^ ][^ ]*  .*$/\2/p')"
  t_eq "gh's help yields value-taking flags to check" yes "${_flags:+yes}"
  _missing=''; for _f in $_flags; do grep -q -- "$_f" "$SUT" || _missing="$_missing $_f"; done
  t_eq "every value-taking gh pr merge flag is known to the parser" "" "$_missing"
else
  echo "  skip: gh is not installed here — the flag-list check did not run"
fi

t_section "2d · --box: the box-wired gate finds the repo from the call (harbor#516)"
# A registered checkout under a fake port root whose origin is Own/Gov, and a session standing elsewhere.
PORTB="$T/portb"; GOV="$PORTB/gov"; CFGB="$T/cfgb"; ELSE="$T/elsewhere"
mkdir -p "$GOV/bin" "$CFGB/inject.d" "$ELSE"; gitq -C "$GOV" init; id_cfg "$GOV"
gitq -C "$GOV" remote add origin https://github.com/Own/Gov.git
( cd "$GOV" && printf 'x\n' > README && git add -A && git commit -qm init ) >/dev/null 2>&1
GOVP="$(cd "$GOV" && pwd -P)"
printf 'gov\t%s\tfixture\n' "$GOV" > "$CFGB/inject.d/projects.tsv"
bstub() { printf '#!/usr/bin/env sh\nprintf "%%s\\n" "%s"\nexit %s\n' "$2" "$1" > "$GOV/bin/merge-check.sh"; }  # <exit> <text>
fireb() { # <event> <command> <call cwd> [project dir] → the --box hook's stdout
  printf '%s' "$2" | jq -Rs --arg e "$1" --arg c "$3" '{hook_event_name:$e,tool_name:"Bash",cwd:$c,tool_input:{command:.}}' \
    | CLAUDE_PROJECT_DIR="${4:-$ELSE}" CLAUDE_CONFIG_DIR="$CFGB" PORT_ROOT="$PORTB" sh "$SUT" --box 2>/dev/null
}
bstub 1 'REFUSED  a check is not passing on #7'
out="$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov --squash' "$ELSE")"
t_has "a -R slug from outside the repo is denied on a refusal" "$out" '"permissionDecision":"deny"'
t_eq "the box deny is valid JSON" 0 "$(printf '%s' "$out" | jq -e . >/dev/null 2>&1; echo $?)"
t_has "the deny names the repo the route runs in" "$out" "(in $GOVP)"
# the decision log (harbor#957 item 4): the box deny is recorded under g=govern; the --note route is inject's
mkledger() { # <dir> <script>… → a config dir whose bin/ holds the scripts and guard-lib.sh, with a sink; prints the sink
  mkdir -p "$1/bin" "$1/MEMORY/OBSERVABILITY/probehost"; _lt="$1"; shift
  cp "$@" "$T_ROOT/bin/guard-lib.sh" "$_lt/bin/"; printf 'probehost\n' > "$_lt/.helm-obs-host"
  : > "$_lt/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; chmod 0500 "$_lt/MEMORY/OBSERVABILITY/probehost"
  printf '%s' "$_lt/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"
}
GLS="$(mkledger "$T/gledger" "$SUT")"; _sut="$SUT"; SUT="$T/gledger/bin/govern-hook.sh"
t_has "the deny still comes through the ledger copy (control)" "$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov --squash' "$ELSE")" '"permissionDecision":"deny"'
t_has "...and is recorded under g=govern" "$(cat "$GLS")" '"g":"govern"'
t_has "...as deny" "$(cat "$GLS")" '"d":"deny"'
t_eq "...with nothing in the catch-all" 0 "$(grep -c '"g":"other"' "$GLS")"
_n="$(grep -c . "$GLS")"
printf '%s' 'gh pr merge 7 -R Own/Gov' | jq -Rs --arg c "$ELSE" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$c,tool_input:{command:.}}' \
  | CLAUDE_PROJECT_DIR="$ELSE" CLAUDE_CONFIG_DIR="$CFGB" PORT_ROOT="$PORTB" sh "$SUT" --note >/dev/null 2>&1
t_eq "the --note route writes nothing here: inject-hook records it" "$_n" "$(grep -c . "$GLS")"
SUT="$_sut"
t_has "the slug is matched case-insensitively" "$(fireb PreToolUse 'gh pr merge 7 --repo own/gov' "$ELSE")" '"permissionDecision":"deny"'
t_has "a HOST/OWNER/REPO slug is matched" "$(fireb PreToolUse 'gh pr merge 7 -R github.com/Own/Gov' "$ELSE")" '"permissionDecision":"deny"'
t_has "with no -R, the call's working folder names the repo" "$(fireb PreToolUse 'gh pr merge 7' "$GOV")" '"permissionDecision":"deny"'
t_eq "a slug with no checkout is silent" "" "$(fireb PreToolUse 'gh pr merge 7 -R Own/Other' "$ELSE")"
t_eq "outside any repo with no -R is silent" "" "$(fireb PreToolUse 'gh pr merge 7' "$ELSE")"
t_eq "a non-merge command is silent" "" "$(fireb PreToolUse 'gh pr view 7 -R Own/Gov' "$ELSE")"
t_eq "PostToolUse is not the box gate's event" "" "$(fireb PostToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")"
mkdir -p "$GOV/.claude/inject.d"; printf 'x\n' > "$GOV/.claude/inject.d/merge-note.sh"
t_eq "standing in the repo with its merge pack, the pack checks it and --box stays silent" "" \
  "$(fireb PreToolUse 'gh pr merge 7' "$GOV" "$GOV")"
t_has "the same repo reached from outside is still checked" "$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")" '"permissionDecision":"deny"'
rm -rf "$GOV/.claude"
: > "$CFGB/inject.d/projects.tsv"
t_eq "an unregistered checkout never runs its merge-check.sh" "" "$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")"
printf 'gov\t%s\tfixture\n' "$GOV" > "$CFGB/inject.d/projects.tsv"
bstub 0 'ok  #7 — 3 check(s) pass'
out="$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")"
t_hasnt "a green PR from outside is not interrupted" "$out" 'permissionDecision'
t_has "and its pass is stated" "$out" 'consulted for #7'
bstub 127 'x: command not found'
out="$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")"
t_hasnt "a broken backstop fails OPEN in --box too" "$out" 'permissionDecision'
t_has "and says nothing was verified" "$out" 'could NOT be consulted'
bstub 1 'REFUSED  owner says no'
t_has "the deny carries its CHECKS.md id" "$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$ELSE")" '[check:merge-backstop]'
# A worktree of the registered repo: its own copy of merge-check.sh would pass, the owner's refuses.
WT="$T/gov-wt"; gitq -C "$GOV" worktree add -q "$WT" -b wt-branch
printf '#!/usr/bin/env sh\necho "ok  stale copy"\nexit 0\n' > "$WT/bin/merge-check.sh"
t_has "from a worktree, the OWNER's backstop decides, not the worktree's copy" \
  "$(fireb PreToolUse 'gh pr merge 7' "$WT")" 'owner says no'
mkdir -p "$WT/.claude/inject.d"; printf 'x\n' > "$WT/.claude/inject.d/merge-note.sh"
t_eq "a session launched in a worktree with the merge pack is left to the pack, even via -R" "" \
  "$(fireb PreToolUse 'gh pr merge 7 -R Own/Gov' "$WT" "$WT")"
# A folder whose .git FILE names the registered repo must not get its own script run.
FAKE="$T/fake"; mkdir -p "$FAKE/bin"; printf 'gitdir: %s/.git\n' "$GOV" > "$FAKE/.git"
printf '#!/usr/bin/env sh\ntouch "%s/ran"\nexit 0\n' "$FAKE" > "$FAKE/bin/merge-check.sh"
fireb PreToolUse 'gh pr merge 7' "$FAKE" >/dev/null
t_eq "a .git file naming a registered repo never runs the folder's own script" absent \
  "$([ -f "$FAKE/ran" ] && echo ran || echo absent)"
t_eq "the floor kill-switch silences --box" "" \
  "$(printf '%s' 'gh pr merge 7 -R Own/Gov' | jq -Rs --arg c "$ELSE" '{hook_event_name:"PreToolUse",tool_name:"Bash",cwd:$c,tool_input:{command:.}}' \
     | HELM_DISABLE_FLOOR=1 CLAUDE_PROJECT_DIR="$ELSE" CLAUDE_CONFIG_DIR="$CFGB" PORT_ROOT="$PORTB" sh "$SUT" --box 2>/dev/null)"
t_has "...but not the repo pack's --note, which is repo payload" \
  "$(printf '%s' 'gh pr merge 7' | jq -Rs '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:.}}' \
     | HELM_DISABLE_FLOOR=1 CLAUDE_PROJECT_DIR="$GOV" sh "$SUT" --note 2>/dev/null)" 'HARBOR-DECISION deny'

t_section "3 · the PostToolUse route: merge-consequent state only"
out="$(fire PostToolUse 'gh pr merge 172 --squash')"
t_has "a merged local branch is named" "$out" 'done-branch'
t_hasnt "an unmerged branch is left alone" "$out" 'live-branch'
t_has "a SQUASH-merged branch is named (harbor#213)" "$out" 'squashed-branch'
t_exit "the squash fixture is genuinely not an ancestor of origin/main" 1 \
  git -C "$REPO" merge-base --is-ancestor squashed-branch origin/main
t_has "the PostToolUse envelope is correct" "$out" '"hookEventName":"PostToolUse"'

t_section "4 · the false-positive gate: a clean repo after a merge says nothing"
CLEAN_O="$T/clean.git"; CLEAN="$T/clean"
gitq init --bare "$CLEAN_O"; gitq clone "$CLEAN_O" "$CLEAN"; id_cfg "$CLEAN"
( cd "$CLEAN" && mkdir -p bin && printf 'x\n' > bin/merge-check.sh && git add -A && git commit -qm init \
  && git branch -M main && git push -qu origin main ) >/dev/null 2>&1
t_eq "a clean repo after a merge says nothing" "" "$(fire PostToolUse 'gh pr merge 9 --squash' "$CLEAN")"
printf 'dirty\n' >> "$CLEAN/bin/merge-check.sh"
t_eq "uncommitted changes alone do not trigger it" "" "$(fire PostToolUse 'gh pr merge 9' "$CLEAN")"

t_section "5 · the pinned holes, asserted as MISSES (update CONTRACTS/hooks.md if one changes)"
t_eq "a shell alias is not caught" "" "$(fire PreToolUse 'ghm 172')"
t_eq "the program in a variable is not caught" "" "$(fire PreToolUse 'GH=gh; $GH pr merge 172')"
t_eq "a merge reached through xargs is not caught" "" "$(fire PreToolUse 'xargs -I{} gh pr merge {} < prs.txt')"
t_eq "a backslash-continued phrase is not caught" "" "$(fire PreToolUse 'gh pr \
  merge 172')"

t_section "6 · fail-open on every degraded input"
printf 'not json at all' > "$T/bad.json"
t_exit "malformed JSON exits 0" 0 env CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" < "$T/bad.json"
t_exit "empty stdin exits 0" 0 env CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" < /dev/null
t_eq "a non-Bash tool says nothing" "" "$(printf '{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"/x"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null)"
printf '%s' 'gh pr merge 1' | jq -Rs '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:.}}' > "$T/m1.json"
t_exit "a non-repo project dir exits 0" 0 env CLAUDE_PROJECT_DIR=/nonexistent-path-xyz sh "$SUT" < "$T/m1.json"
t_eq "a non-repo project dir says nothing" "" "$(CLAUDE_PROJECT_DIR=/nonexistent-path-xyz sh "$SUT" < "$T/m1.json" 2>/dev/null)"
# No jq: a PATH of real tools with jq left out, and a real merge payload on stdin.
NOJQ="$T/nojq"; mkdir -p "$NOJQ"
for _b in cat sed awk grep tr cut head tail wc git dirname basename mktemp rm; do
  _p="$(command -v "$_b")" && ln -s "$_p" "$NOJQ/$_b"
done
t_exit "no jq on PATH exits 0" 0 env PATH="$NOJQ" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$SUT" < "$T/m1.json"
t_eq "no jq on PATH says nothing" "" "$(PATH="$NOJQ" CLAUDE_PROJECT_DIR="$REPO" /bin/sh "$SUT" < "$T/m1.json" 2>/dev/null)"

t_section "6b · events that moved to inject.d/box, the stamp, and --note"
for _ev in PreCompact SubagentStart Stop; do
  t_eq "$_ev says nothing here" "" "$(printf '{"hook_event_name":"%s","session_id":"s"}' "$_ev" \
    | CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null)"
done
_merge='{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"%s","tool_input":{"command":"gh pr merge 172 --squash"}}'
NOSALT="$T/nosalt"; mkdir -p "$NOSALT/.claude"
_ns="$(printf "$_merge" sid-1 | HOME="$NOSALT" CLAUDE_CONFIG_DIR="$NOSALT/.claude" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null)"
t_has "with no salt the note is unstamped and still fires" "$_ns" '[HARBOR GOVERNANCE]'
SALT="$T/salted"; mkdir -p "$SALT"; printf 'test-salt-value\n' > "$SALT/.helm-govern-salt"
_st="$(printf "$_merge" sid-1 | CLAUDE_CONFIG_DIR="$SALT" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null)"
_s2="$(printf "$_merge" sid-2 | CLAUDE_CONFIG_DIR="$SALT" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" 2>/dev/null)"
t_has "with a salt the note carries a session token" "$_st" 'HARBOR GOVERNANCE '
t_eq "two sessions get different stamps" yes "$([ "$_st" != "$_s2" ] && echo yes)"
_n="$(printf "$_merge" sid-1 | CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" --note 2>/dev/null)"
t_has "--note carries the same advice" "$_n" 'merge-check.sh'
t_hasnt "--note emits no JSON envelope" "$_n" 'hookSpecificOutput'
t_hasnt "--note emits no stamp; its caller adds it" "$_n" '[HARBOR GOVERNANCE'
t_eq "--note is silent on ordinary work" "" "$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"s","tool_input":{"command":"ls -la"}}' \
  | CLAUDE_PROJECT_DIR="$REPO" sh "$SUT" --note 2>/dev/null)"
t_eq "no systemMessage when nothing is operator-facing" false \
  "$(fire PreToolUse 'gh pr merge 172 --squash' | jq 'has("systemMessage")' 2>/dev/null)"

t_section "6c · slash commands, and their install path"
CMDS="$T_ROOT/commands"; _n=0; _nodesc=''
for _c in "$CMDS"/*.md; do
  [ -f "$_c" ] || continue; _n=$((_n + 1))
  grep -q '^description:' "$_c" || _nodesc="$_nodesc $(basename "$_c")"
done
t_eq "slash commands are tracked ($_n)" yes "$([ "$_n" -gt 0 ] && echo yes)"
t_eq "every slash command has a description" "" "$_nodesc"
FH2="$T/fh2"; mkdir -p "$FH2/.claude"
t_exit "the commands path refuses the live dir without --live" 1 \
  env HOME="$FH2" CLAUDE_CONFIG_DIR="$FH2/.claude" sh "$T_ROOT/bin/skills-install.sh" commands --apply --dir "$FH2/.claude"
t_exit "commands install with --live" 0 \
  env HOME="$FH2" CLAUDE_CONFIG_DIR="$FH2/.claude" sh "$T_ROOT/bin/skills-install.sh" commands --apply --live
t_exit "an installed command is byte-identical" 0 cmp -s "$CMDS/harbor-merge.md" "$FH2/.claude/commands/harbor-merge.md"

t_section "7 · hooks/commit-msg"
cm() { printf '%s\n' "$1" > "$T/msg"; sh "$HOOKS/commit-msg" "$T/msg" >/dev/null 2>&1; echo $?; }
t_eq "passes an ordinary message" 0 "$(cm 'feat: an ordinary subject line')"
t_eq "blocks a Co-Authored-By trailer" 1 "$(cm 'Co-Authored-By: Claude <noreply@anthropic.com>')"
t_eq "blocks the generated-with banner" 1 "$(cm '🤖 Generated with Claude Code')"
t_eq "blocks a Claude-Session trailer (harbor#584)" 1 "$(cm "$(printf 'fix: a subject\n\nClaude-Session: https://claude.ai/code/session_x')")"
t_eq "allows the Claude-Session trailer to be named mid-line" 0 "$(cm 'docs: why the Claude-Session: trailer is attribution')"
t_eq "ignores a git comment line" 0 "$(cm '# Co-Authored-By: Claude')"
t_eq "allows the rule to be discussed mid-line" 0 "$(cm 'docs: explain why Co-Authored-By trailers are banned')"
_ere="$(sed -n "s/^HARBOR_ATTRIBUTION_ERE='\(.*\)'$/\1/p" "$HOOKS/commit-msg" | head -1)"
t_eq "lint C2 can still extract the pattern from the hook" yes "${_ere:+yes}"
t_has "lint C2 consumes the hook definition rather than a copy" "$(cat "$T_ROOT/bin/lint-conventions.sh")" 'HARBOR_ATTRIBUTION_ERE'
# Through real `git commit`: the unit cases passed while a 644 mode bit made git skip the hook.
E2E="$T/e2e"; mkdir -p "$E2E/hooks"; gitq -C "$E2E" init; id_cfg "$E2E"
cp -p "$HOOKS/commit-msg" "$E2E/hooks/commit-msg"; ln -sf ../../hooks/commit-msg "$E2E/.git/hooks/commit-msg"
printf 'x\n' > "$E2E/f"; gitq -C "$E2E" add -A
t_exit "REAL git commit rejects a trailer" 1 git -C "$E2E" commit -q -m "feat: x

Co-Authored-By: Claude <noreply@anthropic.com>"
t_exit "REAL git commit accepts a clean message" 0 git -C "$E2E" commit -q -m "feat: x"
for _h in pre-commit commit-msg pre-push; do
  t_eq "hooks/$_h is executable (git skips it otherwise)" yes "$([ -x "$HOOKS/$_h" ] && echo yes)"
done

t_section "7 · hooks/pre-push"
t_eq "stands down where no selector exists" 0 "$(cd "$BARE" && sh "$HOOKS/pre-push" </dev/null >/dev/null 2>&1; echo $?)"
# A repo WITH a selector (a stub that stands down), so the deletion path is what runs.
DELR="$T/delrepo"; mkdir -p "$DELR/bin" "$DELR/CONTRACTS"; gitq -C "$DELR" init; id_cfg "$DELR"
printf '#!/usr/bin/env sh\nexit 1\n' > "$DELR/bin/suite-select.sh"; printf 'nothing-test.sh\n' > "$DELR/CONTRACTS/suites.txt"
printf 'x\n' > "$DELR/f"; ( cd "$DELR" && git add -A && git commit -qm i ) >/dev/null 2>&1
_del="$( cd "$DELR" && printf 'refs/heads/x 0000000000000000000000000000000000000000 refs/heads/x %s\n' \
  '1111111111111111111111111111111111111111' | sh "$HOOKS/pre-push" 2>&1; echo "rc=$?" )"
t_has "ignores a ref deletion" "$_del" 'rc=0'
t_has "reaches its summary on a deletion (the guard is live)" "$_del" 'check(s) run'
t_has "prints what it did NOT run (no silent cap)" "$(cat "$HOOKS/pre-push")" 'suite(s) NOT run here'
_pp="$( cd "$DELR" && HARBOR_CHANGED='README.md' sh "$HOOKS/pre-push" </dev/null 2>&1 )"
t_hasnt "the default is not the full selection" "$_pp" 'FULL mode'
t_has "the default is the cheap lane" "$_pp" 'check(s) run'
t_has "the expensive mode is still an opt-in" "$( cd "$DELR" && HARBOR_PREPUSH_FULL=1 HARBOR_CHANGED='README.md' sh "$HOOKS/pre-push" </dev/null 2>&1 )" 'FULL mode'
t_has "the opt-in is still named in the hook" "$(cat "$HOOKS/pre-push")" 'HARBOR_PREPUSH_FULL'
# Through real `git push` (harbor#575); the linter stub leaves a marker, so "did it run" is a file.
PPR="$T/pp-repo"; PPREM="$T/pp-remote.git"; PPMARK="$T/pp-lint-ran"
mkdir -p "$PPR/bin" "$PPR/CONTRACTS" "$PPR/.hooks"; gitq init --bare "$PPREM"; gitq -C "$PPR" init; id_cfg "$PPR"
git -C "$PPR" config core.hooksPath .hooks; git -C "$PPR" remote add origin "$PPREM"
printf '#!/usr/bin/env sh\nexit 1\n' > "$PPR/bin/suite-select.sh"
printf '#!/usr/bin/env sh\necho ran >> "%s"\n' "$PPMARK" > "$PPR/bin/lint-conventions.sh"
printf 'nothing-test.sh\n' > "$PPR/CONTRACTS/suites.txt"; cp -p "$HOOKS/pre-push" "$PPR/.hooks/pre-push"
printf 'x\n' > "$PPR/f"
( cd "$PPR" && git add -A && git commit -qm i && git branch -M main && git push -q --no-verify origin main main:old ) >/dev/null 2>&1
rm -f "$PPMARK"
_ppd="$( cd "$PPR" && git push origin --delete old 2>&1; echo "rc=$?" )"
t_exit "a pure-deletion push deleted the branch (it reached the hook)" 1 \
  git --git-dir="$PPREM" rev-parse --verify --quiet refs/heads/old
t_has "a pure-deletion push is not refused" "$_ppd" 'rc=0'
t_eq "a push of only deletions runs no linter" no "$([ -f "$PPMARK" ] && echo yes || echo no)"
t_has "a push of only deletions says so" "$_ppd" 'pre-push: 0 check(s) run'
( cd "$PPR" && git push -q --no-verify origin main:old ) >/dev/null 2>&1
printf 'y\n' >> "$PPR/f"; ( cd "$PPR" && git commit -qam j ) >/dev/null 2>&1; rm -f "$PPMARK"
t_exit "the mixed push :old main is not refused" 0 git -C "$PPR" push -q origin :old main
t_eq "a mixed push (:old main) still runs the linter" yes "$([ -f "$PPMARK" ] && echo yes || echo no)"
t_done
