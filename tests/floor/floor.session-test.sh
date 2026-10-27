#!/usr/bin/env sh
# floor suite, session part (harbor#727): the per-session context file and the ENGINE default (H2,
# harbor#4), the peer record's branch (PR #93), the constitution's surfaced deference (C2, harbor#5,
# #581), the work-log credential (§4-1, harbor#85, #554), the runtime install's engine chain (L0-5d,
# harbor#59), the working-context corpus, scored and never printed (C1a, harbor#43; M3), and no
# hook script loading a file planted in the session's cwd (B9c, harbor#813).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/floor-fixture.sh"
ere() { printf '%s\n' "$2" | grep -qE -- "$1"; }  # <ERE> <text>: exit 0 when a line matches

t_section "H2 (harbor#4): the per-session context FILE, and the ENGINE default"
H2="$TMP/h2"; mkdir -p "$H2/cfg/bin" "$H2/gov/.agents" "$H2/plain"
printf 'context: repo\n' > "$H2/gov/.agents/config.yaml"
for _f in guard-lib.sh floor-normalize.awk context-resolve.sh; do cp "$SRC/$_f" "$H2/cfg/bin/"; done
_h2res() { printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$1" "$2" \
  | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" >/dev/null 2>&1; }
_h2ctx() { printf '{"session_id":"%s"}' "$1" \
  | ( CLAUDE_CONFIG_DIR="$H2/cfg"; . "$H2/cfg/bin/guard-lib.sh"; FLOOR_IN="$(cat)"; floor_session_context ); }
_h2sd()  { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" \
  | ( CLAUDE_CONFIG_DIR="$H2/cfg"; . "$H2/cfg/bin/guard-lib.sh"; FLOOR_IN="$(cat)"
      unset CLAUDE_PROJECT_DIR; cd / 2>/dev/null || true
      floor_engine_stand_down && echo down || echo act ); }
_h2res S-amb "$H2/plain"; _h2res S-gov "$H2/gov"
t_eq "H2 an ambient session is recorded" ambient "$(_h2ctx S-amb)"
t_eq "H2 a governed session is recorded" repo "$(_h2ctx S-gov)"
t_eq "H2 a session with no file reads empty" "" "$(_h2ctx S-none)"
# harbor#954 (D-46): the engine stands down ONLY on `worklog: off` in the marker's config.yaml. A marker
# alone, or a missing or empty context file, no longer stops the work log.
_h2off() { mkdir -p "$H2/$1/.agents" "$H2/$1/sub"; printf '%s\n' "$2" > "$H2/$1/.agents/config.yaml"; }
_h2off off 'context: repo
worklog: off'
_h2off offq '"worklog" : "off"   # opted out'
_h2off offamb 'context: ambient
worklog: off'
_h2off offind 'logging:
  worklog: off'
_h2off on 'context: repo
worklog: on'
_h2off offhash 'worklog: off#typo'
t_eq "H2 an ambient session lets the engine act" act "$(_h2sd S-amb "$H2/plain")"
t_eq "H2 a governed session with no opt-out lets the engine act (harbor#954)" act "$(_h2sd S-gov "$H2/gov")"
t_eq "H2 NO context file lets the engine act (harbor#954)" act "$(_h2sd S-none "$H2/plain")"
printf '' > "$H2/cfg/.helm-context/S-empty"
t_eq "H2 an EMPTY context file lets the engine act (harbor#954)" act "$(_h2sd S-empty "$H2/plain")"
t_eq "H2 worklog: off stands the engine down" down "$(_h2sd S-gov "$H2/off")"
t_eq "H2 worklog: off stands it down from a subdirectory" down "$(_h2sd S-gov "$H2/off/sub")"
t_eq "H2 worklog: off overrides a recorded ambient verdict" down "$(_h2sd S-amb "$H2/off")"
t_eq "H2 a quoted, commented worklog: off counts" down "$(_h2sd S-none "$H2/offq")"
t_eq "H2 worklog: off still counts beside context: ambient" down "$(_h2sd S-none "$H2/offamb")"
t_eq "H2 an indented worklog: off is another block's key" act "$(_h2sd S-none "$H2/offind")"
t_eq "H2 worklog: on lets the engine act" act "$(_h2sd S-none "$H2/on")"
t_eq "H2 off#typo is not off (a comment needs whitespace)" act "$(_h2sd S-none "$H2/offhash")"
# `./../escape` is the id that lands at cfg/escape once the id check is gone; the legacy's
# `../../escape` could not escape even then, because `.$SID` makes its temp path need a `...` dir.
_h2res "./../escape" "$H2/plain"
t_eq "H2 a traversing session id escapes nothing out of the context dir" "" "$(find "$H2" -name 'escape*')"
_h2blk() { printf '{"hook_event_name":"SessionStart"}' | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" >/dev/null 2>&1; }
t_exit "H2 the resolver never blocks a session" 0 _h2blk

t_section "PEER-BRANCH (PR #93 review): the record follows a checkout"
_pb="$H2/branchrepo"; mkdir -p "$_pb"
( cd "$_pb" && git init -q && git config user.email t@t && git config user.name t \
  && printf 'x\n' > f.txt && git add f.txt && git commit -qm init \
  && git branch -M first ) >/dev/null 2>&1
_pbwrite() { printf '{"hook_event_name":"PostToolUse","tool_name":"Write","session_id":"S-branch","cwd":"%s","tool_input":{"file_path":"%s/f.txt"}}' "$_pb" "$_pb" \
  | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" >/dev/null 2>&1; }
_pbrec() { sed -n 's/^branch=//p' "$H2/cfg/.helm-peers/S-branch" 2>/dev/null | head -1; }
_pbwrite
t_eq "PEER-BRANCH the first record carries the branch" first "$(_pbrec)"
( cd "$_pb" && git checkout -q -b second ) >/dev/null 2>&1
_pbwrite
t_eq "PEER-BRANCH the record follows a checkout" second "$(_pbrec)"

t_section "PEER-READ (harbor#610): a Read is not a write"
_prd() { printf '{"hook_event_name":"PostToolUse","tool_name":"%s","session_id":"S-read","cwd":"%s","tool_input":{"file_path":"%s/f.txt"}}' "$1" "$_pb" "$_pb" \
  | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" >/dev/null 2>&1; }
_prdsrc() { sed -n 's/^src=//p' "$H2/cfg/.helm-peers/S-read" 2>/dev/null | head -1; }
mkdir -p "$H2/cfg/.helm-peers"
printf 'tree=%s\nsrc=launch\npid=1\nbranch=\n' "$H2" > "$H2/cfg/.helm-peers/S-read"
_prd Read
t_eq "PEER-READ a Read leaves src=launch alone" launch "$(_prdsrc)"
_prd Edit
t_eq "PEER-READ an Edit still upgrades to src=write (positive control)" write "$(_prdsrc)"

t_section "PEER-BASH (harbor#610): a Bash command that writes into a tree is a write"
_pbs() { # <command> <cwd> -> src after one Bash PostToolUse, from a fresh src=launch record
  printf 'tree=%s\nsrc=launch\npid=1\nbranch=\n' "$H2" > "$H2/cfg/.helm-peers/S-bash"
  jq -n --arg c "$1" --arg d "$2" '{hook_event_name:"PostToolUse",tool_name:"Bash",session_id:"S-bash",cwd:$d,tool_input:{command:$c}}' \
    | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" >/dev/null 2>&1
  sed -n 's/^src=//p' "$H2/cfg/.helm-peers/S-bash" 2>/dev/null | head -1; }
t_eq "PEER-BASH > redirect, absolute" write "$(_pbs "echo hi > $_pb/f.txt" "$H2")"
t_eq "PEER-BASH >> redirect, relative to cwd" write "$(_pbs "echo hi >> f.txt" "$_pb")"
t_eq "PEER-BASH tee -a" write "$(_pbs "echo hi | tee -a $_pb/f.txt" "$H2")"
t_eq "PEER-BASH cp destination" write "$(_pbs "cp /etc/hosts $_pb/f.txt" "$H2")"
t_eq "PEER-BASH mv destination, relative" write "$(_pbs "mv a.txt f.txt" "$_pb")"
t_eq "PEER-BASH install destination" write "$(_pbs "install -m 644 a.txt $_pb/f.txt" "$H2")"
t_eq "PEER-BASH git -C <dir> commit" write "$(_pbs "git -C $_pb commit -m x" "$H2")"
t_eq "PEER-BASH negative: cat is read-only" launch "$(_pbs "cat $_pb/f.txt" "$_pb")"
t_eq "PEER-BASH negative: grep is read-only" launch "$(_pbs "grep -r x $_pb" "$_pb")"
t_eq "PEER-BASH negative: git -C status is read-only" launch "$(_pbs "git -C $_pb status" "$H2")"
t_eq "PEER-BASH negative: a quoted > in a string" launch "$(_pbs "echo 'a > f.txt' \"b >> f.txt\"" "$_pb")"
t_eq "PEER-BASH negative: an unparseable target (variable) is ignored" launch "$(_pbs 'echo x > "$OUT"' "$_pb")"
t_eq "PEER-BASH negative: > /dev/null is not a tree write" launch "$(_pbs "ls $_pb > /dev/null 2>&1" "$_pb")"

t_section "C2 (harbor#5): the constitution's deference is SURFACED, not assumed"
_c2out() { printf '{"hook_event_name":"SessionStart","session_id":"%s","cwd":"%s"}' "$1" "$2" \
  | CLAUDE_CONFIG_DIR="$H2/cfg" sh "$H2/cfg/bin/context-resolve.sh" 2>/dev/null; }
_c2g="$(_c2out C-gov "$H2/gov")"
_c2ctx="$(printf '%s' "$_c2g" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null)"
t_eq "C2 a governed session emits a valid SessionStart payload" SessionStart \
  "$(printf '%s' "$_c2g" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
t_has "C2 the deference notice names the repo as authoritative" "$_c2ctx" 'AUTHORITATIVE'
t_has "C2 the notice says the five constitutional rules never yield (harbor#581)" "$_c2ctx" 'never yield'
# The negative's positive control (lint F9): the pre-#581 sentence did carry the phrase.
_c2_standdown='constitution stands down'
t_has "C2 the stand-down phrase matches the pre-#581 wording it was written against" \
  "$(printf '%s' "Harbor's ambient constitution stands down here (CONTRACTS/marker.md)." | tr '[:upper:]' '[:lower:]')" "$_c2_standdown"
t_hasnt "C2 the notice never says the constitution stands down (harbor#581)" \
  "$(printf '%s' "$_c2ctx" | tr '[:upper:]' '[:lower:]')" "$_c2_standdown"
t_eq "C2 an ambient session emits no deference noise" "" "$(_c2out C-amb "$H2/plain")"
# It POINTS, never injects: the constitution's own marker word must not reach the notice.
t_has "C2 the constitution carries the CONSTITUTIONAL marker an injection would carry" \
  "$(cat "$HROOT/CONSTITUTION.md")" 'CONSTITUTIONAL'
t_hasnt "C2 the notice does not inject constitutional text" "$_c2ctx" 'CONSTITUTIONAL'

t_section "§4-1 (harbor#85): the work-log credential never reaches a URL"
# Source assertions on non-comment lines: a real push needs a network and a live credential.
_wpush="$(grep -v '^[[:space:]]*#' "$T_ROOT/hooks/worklog-push/worklog-push.sh" 2>/dev/null)"
t_exit "§4-1 worklog-push.sh embeds no credential in a URL" 1 ere 'https://[^"]*:\$|@github\.com' "$_wpush"
t_exit "§4-1 worklog-push.sh pushes to the origin remote" 0 ere 'push .*origin main' "$_wpush"
t_has "§4-1 worklog-push.sh reports a push failure" "$_wpush" 'push FAILED'

t_section "L0-5d (harbor#59): the RUNTIME install revives the engine chain, end to end"
L5="$TMP/l05"; mkdir -p "$L5/cfg" "$L5/log" "$L5/plain"
printf '{"model":"opus"}\n' > "$L5/cfg/settings.json"
git -C "$L5/log" init -q 2>/dev/null
t_exit "L0-5d runtime-install.sh --apply succeeds on a throwaway config dir" 0 env -u CLAUDE_CONFIG_DIR sh "$SRC/runtime-install.sh" --dir "$L5/cfg" --apply
t_eq "L0-5d runtime-install copies context-resolve.sh" yes "$([ -f "$L5/cfg/bin/context-resolve.sh" ] && echo yes || echo no)"
t_eq "L0-5d runtime-install copies fleet-sessions.sh (the peer report's reader)" yes \
  "$([ -f "$L5/cfg/bin/fleet-sessions.sh" ] && echo yes || echo no)"
t_has "L0-5d context-resolve.sh is wired to SessionStart" \
  "$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command // empty] | .[]' "$L5/cfg/settings.json" 2>/dev/null)" 'context-resolve.sh'
cp "$T_ROOT/hooks/worklog-push/worklog-push.sh" "$L5/cfg/bin/"
_l5push() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$L5/plain" \
  | CLAUDE_CONFIG_DIR="$L5/cfg" HARBOR_LOG_DIR="$L5/log" sh "$L5/cfg/bin/worklog-push.sh" >/dev/null 2>&1; }
_l5n() { find "$L5/log/WORK" -type f 2>/dev/null | wc -l | tr -d ' '; }
printf '{"hook_event_name":"SessionStart","session_id":"L5-a","cwd":"%s"}' "$L5/plain" \
  | CLAUDE_CONFIG_DIR="$L5/cfg" sh "$L5/cfg/bin/context-resolve.sh" >/dev/null 2>&1
_l5push L5-a
t_eq "L0-5d a resolved session's Stop hook writes its record" 1 "$(_l5n)"
_l5push L5-never-resolved
t_eq "L0-5d an unresolved session still writes its record (harbor#954)" 2 "$(_l5n)"
# A marked repo with and without `worklog: off`: tests/floor/floor.worklog-test.sh (harbor#954).
env -u CLAUDE_CONFIG_DIR sh "$SRC/runtime-install.sh" --dir "$L5/cfg" --apply >/dev/null 2>&1
t_eq "L0-5d a second runtime-install does not duplicate the resolver hook" 1 \
  "$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command // empty] | map(select(test("context-resolve"))) | length' "$L5/cfg/settings.json" 2>/dev/null)"

t_section "C1a (harbor#43): the working-context corpus is SCORED, never PRINTED"
C1A="$TMP/c1a"; mkdir -p "$C1A/TELOS"
printf 'what this system is for\n'  > "$C1A/TELOS/TELOS.md"
printf 'what is believed and why\n' > "$C1A/TELOS/BELIEFS.md"
printf 'role, expertise, constraints\n' > "$C1A/IDENTITY.md"
{ printf -- '- `G1` · %s · active · CANARY-fresh\n' "$(date +%Y-%m-%d)"
  printf -- '- `G2` · 2020-01-02 · active · CANARY-stale\n'
  printf -- '- `G3` · active · CANARY-undated\n'; } > "$C1A/TELOS/GOALS.md"
_fresh() { HARBOR_TELOS_DIR="$1" sh "$SRC/freshness.sh" 2>&1; }
_c1a="$(_fresh "$C1A")"
t_hasnt "C1a the report prints ids and ages, never goal TEXT (§3)" "$_c1a" 'CANARY'
t_exit "C1a a goal reviewed today scores fresh per entry" 0 ere '^  G1 +[0-9]+d +90d +fresh' "$_c1a"
t_exit "C1a a goal reviewed TODAY scores exactly 0d (no local/UTC skew)" 0 ere '^  G1 +0d +90d +fresh' "$_c1a"
printf -- '- `G9` · 2099-01-01 · active · CANARY-future\n' >> "$C1A/TELOS/GOALS.md"
t_exit "C1a a future review date is reported FUTURE" 0 ere 'G9 .*FUTURE' "$(_fresh "$C1A")"
printf '\n    - `GX` · YYYY-MM-DD · active · the format example, indented\n' >> "$C1A/TELOS/GOALS.md"
t_hasnt "C1a an indented format example is not scored as a goal" "$(_fresh "$C1A")" 'GX'
# M3: the ceiling counts what is SPENT; the un-injected corpus is a separate projected line.
M3="$TMP/m3"; mkdir -p "$M3/MEMORY/TELOS" "$M3/skills"
printf 'a constitution of some length\n' > "$M3/CLAUDE.md"
for _f in TELOS/TELOS.md TELOS/GOALS.md TELOS/BELIEFS.md; do
  awk 'BEGIN{for(i=0;i<200;i++) print "padding line for a measurable file size"}' > "$M3/MEMORY/$_f"
done
cp "$M3/MEMORY/TELOS/TELOS.md" "$M3/MEMORY/IDENTITY.md"
# From an empty cwd: context-budget also counts $PWD's repo CLAUDE.md, which harbor now has (#954).
mkdir -p "$TMP/m3-cwd"
_m3="$(cd "$TMP/m3-cwd" && CLAUDE_CONFIG_DIR="$M3" sh "$SRC/context-budget.sh" 2>&1 || true)"
_spent="$(printf '%s\n' "$_m3" | sed -n 's/^SPENT[^0-9]*\([0-9][0-9]*\).*/\1/p')"
_projd="$(printf '%s\n' "$_m3" | sed -n 's/^PROJECTED[^0-9]*\([0-9][0-9]*\).*/\1/p')"
t_eq "M3 context-budget prints a spent/projected pair" yes \
  "$([ -n "$_spent" ] && [ -n "$_projd" ] && echo yes || echo "spent=${_spent:-none} proj=${_projd:-none}")"
t_eq "M3 the projection exceeds what is spent when the corpus exists" ok \
  "$([ "${_projd:-0}" -gt "${_spent:-0}" ] 2>/dev/null && echo ok || echo "proj=${_projd:-none} spent=${_spent:-none}")"
t_eq "M3 SPENT is exactly the one live surface (the corpus did not leak into the ceiling)" \
  "$(wc -c < "$M3/CLAUDE.md" | tr -d ' ')" "${_spent:-none}"
t_has "M3 the corpus rows are labelled as projected" "$_m3" 'projected — nothing injects it today'
t_exit "C1a a goal reviewed years ago scores STALE per entry" 0 ere '^  G2 +[0-9]+d +90d +STALE' "$_c1a"
t_exit "C1a an undated goal is surfaced" 0 ere 'G3 .*UNDATED' "$_c1a"
t_exit "C1a the stale summary counts the stale entries (no subshell loss)" 0 ere '^  WARN: [0-9]+ document\(s\) past threshold' "$_c1a"
printf -- '- `G1` · %s · active · CANARY-fresh\n' "$(date +%Y-%m-%d)" > "$C1A/TELOS/GOALS.md"
t_has "C1a an all-fresh corpus reports nothing past threshold" "$(_fresh "$C1A")" '  ok: nothing past its threshold'
t_has "C1a an absent corpus reports the finding, not an empty table" "$(_fresh "$TMP/c1a-nothing-here")" 'ABSENT'
# The control is the real hook's allowlist, driven against a fixture log repo with no remote.
C1G="$TMP/c1a-log"; mkdir -p "$C1G/TELOS" "$C1G/KNOWLEDGE"
git -C "$C1G" init -q 2>/dev/null
git -C "$C1G" config user.email harbor-test@localhost
git -C "$C1G" config user.name  harbor-test
printf -- '- `G1` · 2026-07-30 · active · CANARY-goal\n' > "$C1G/TELOS/GOALS.md"
printf 'CANARY-identity\n' > "$C1G/IDENTITY.md"
printf '# a durable note\n'  > "$C1G/KNOWLEDGE/note.md"
printf '{"hook_event_name":"SessionStart","session_id":"C1A-log","cwd":"%s"}' "$TMP/plainish" \
  | CLAUDE_CONFIG_DIR="$L5/cfg" sh "$L5/cfg/bin/context-resolve.sh" >/dev/null 2>&1
printf '{"session_id":"C1A-log","cwd":"%s"}' "$TMP/plainish" \
  | CLAUDE_CONFIG_DIR="$L5/cfg" HARBOR_LOG_DIR="$C1G" sh "$L5/cfg/bin/worklog-push.sh" >/dev/null 2>&1
_tracked="$(git -C "$C1G" ls-files)"
t_exit "C1a the allowlist committed something (the two exclusions below can fail)" 0 ere '^KNOWLEDGE/note\.md$' "$_tracked"
t_exit "C1a worklog-push commits no TELOS file" 1 ere '^TELOS/' "$_tracked"
t_exit "C1a worklog-push does not commit IDENTITY.md" 1 ere '^IDENTITY\.md$' "$_tracked"

t_section "B9c (harbor#813): no script a hook runs loads a file planted in the session's cwd"
# B9b pins the guards; this runs EVERY command the installers wire, exactly as wired, from a cwd
# holding a marker under every installed file's name, with no dirname on PATH. Lint F15 pins the
# same set in the source; this pins what the install actually does.
B9C="$TMP/b9c"; B9CC="$B9C/cfg"; B9CP="$B9C/plant"; B9CN="$B9C/nodn"
mkdir -p "$B9CC/sessions" "$B9CP" "$B9CN" "$B9C/pi/templates/base/dot_agents/hooks"
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$B9CC/settings.json"
# One citation, so session-verdicts' reference-check.sh reaches its extractor, cited-paths.awk.
printf '# b9c\n\nRead `bin/restore.sh` first.\n' > "$B9CC/CLAUDE.md"
# Each installer is told its target twice, or it refuses a differing CLAUDE_CONFIG_DIR. prod-guard-install
# requires a prod_guard.py carrying the symlink refusal, and one that answers ask.
printf '%s\n' '# is_symlink (harbor#813 stub)' 'import json' \
  'print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "ask"}}))' \
  > "$B9C/pi/templates/base/dot_agents/hooks/prod_guard.py"
CLAUDE_CONFIG_DIR="$B9CC" sh "$SRC/floor-install.sh" --apply --dir "$B9CC" --with-b6 --with-stop-gate > "$B9C/install.log" 2>&1
CLAUDE_CONFIG_DIR="$B9CC" sh "$SRC/runtime-install.sh" --apply --dir "$B9CC" >> "$B9C/install.log" 2>&1
CLAUDE_CONFIG_DIR="$B9CC" sh "$SRC/inject-install.sh" --apply --dir "$B9CC" >> "$B9C/install.log" 2>&1
CLAUDE_CONFIG_DIR="$B9CC" PROJECT_INIT_SRC="$B9C/pi" sh "$SRC/prod-guard-install.sh" --apply --dir "$B9CC" >> "$B9C/install.log" 2>&1
# <event> TAB <command>, one per wiring: the hooks, both status lines, each box pack's run: script, and
# each hook the box wires by hand, declared in CONTRACTS/hooks-external.tsv, wired the way the box does.
{ jq -r '(.hooks // {} | to_entries[] | .key as $e | .value[]? | .hooks[]? | [$e, .command] | @tsv),
         (.statusLine.command // empty | ["statusLine", .] | @tsv),
         (.subagentStatusLine.command // empty | ["subagentStatusLine", .] | @tsv)' "$B9CC/settings.json"
  for _b9k in "$B9CC"/inject.d/*.md; do
    _b9r="$(sed -n 's/^run:[[:space:]]*//p' "$_b9k" | head -n 1)"
    [ -z "$_b9r" ] || printf 'inject.d\t/bin/sh "%s"\n' "$B9CC/inject.d/$_b9r"
  done
  grep -vE '^[[:space:]]*(#|$)' "$HROOT/CONTRACTS/hooks-external.tsv" | while IFS='	' read -r _b9s _b9e _b9y; do
    printf '%s\t/bin/sh %s\n' "$_b9e" "$B9CC/$_b9s"; done; } | awk '!s[$0]++' > "$B9C/wired"
t_eq "B9c the sandbox install wires every installer's hooks (floor, runtime, inject, prod-guard, box packs)" 5 \
  "$(for _b9w in floor-hook.sh session-verdicts.sh injection-rule.sh prod-guard-ambient.sh project-pointer.sh; do
       grep -F "/$_b9w" "$B9C/wired" | head -n 1; done | grep -c .)"
t_eq "B9c worklog-push is installed and wired here (from its manifest since harbor#1272; it was wired by hand)" 1 \
  "$(for _b9w in worklog-push.sh; do grep -F "/bin/$_b9w" "$B9C/wired" | head -n 1 | cut -f2 \
       | sed 's#^/bin/sh ##' | while IFS= read -r _b9f; do [ -f "$_b9f" ] && echo y; done; done | grep -c y)"
# The plant: a marker under every installed .sh and .awk name, and a registry row project-pointer would name.
for _b9f in "$B9CC"/bin/* "$B9CC"/inject.d/*; do
  _b9b="${_b9f##*/}"
  case "$_b9b" in
    *.sh)  printf 'echo %s >> "%s/ran"\nexit 0\n' "$_b9b" "$B9C" > "$B9CP/$_b9b" ;;
    *.awk) printf 'BEGIN { print "%s" >> "%s/ran"; exit }\n' "$_b9b" "$B9C" > "$B9CP/$_b9b" ;;
  esac
done
printf 'b9cplanted\t%s\tthe planted registry row\n' "$B9C" > "$B9CP/projects.tsv"
# A live peer, so context-resolve reaches fleet-sessions.sh, which sources guard-lib.sh per session.
_b9l="$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')"
_b9e="$(date -j -f '%a %b %d %T %Y' "$_b9l" +%s 2>/dev/null || date -d "$_b9l" +%s)"
_b9u="$(date -u -r "$_b9e" '+%a %b %e %T %Y' 2>/dev/null || date -u -d "@$_b9e" '+%a %b %e %T %Y')"
printf '{"pid":%s,"sessionId":"b9c-peer","cwd":"%s","procStart":"%s","status":"busy","name":"b9c","kind":"interactive"}\n' \
  $$ "$B9CP" "$_b9u" > "$B9CC/sessions/b9c.json"
# PATH with no dirname: every directory that has one is replaced by links to all of it but dirname.
_b9path=""; _b9dn=0; _b9ifs="$IFS"; IFS=:
for _b9d in $PATH; do
  { [ -n "$_b9d" ] && [ -d "$_b9d" ]; } || continue
  if [ -e "$_b9d/dirname" ]; then
    ln -s "$_b9d"/* "$B9CN"/ 2>/dev/null
    [ "$_b9dn" = 1 ] || _b9path="${_b9path:+$_b9path:}$B9CN"; _b9dn=1
  else _b9path="${_b9path:+$_b9path:}$_b9d"; fi
done
IFS="$_b9ifs"; rm -f "$B9CN/dirname"
t_eq "B9c the sandbox PATH holds no dirname" "" "$(PATH="$_b9path" command -v dirname 2>/dev/null)"
_b9n=0
b9c_run() { # <event> <command> -> "clean", or "ran:<planted names>"
  _b9n=$((_b9n + 1)); rm -f "$B9C/ran"
  jq -cn --arg e "$1" --arg c "$B9CP" --arg s "b9c-$_b9n" '{session_id: $s, cwd: $c, hook_event_name: $e,
    tool_name: "Bash", tool_input: {command: "git status"}, tool_response: {stdout: "x"}, workspace: {current_dir: $c}}' \
    > "$B9C/in.json"
  ( cd "$B9CP" && ff_bound 30 env PATH="$_b9path" CLAUDE_CONFIG_DIR="$B9CC" sh -c "$2" < "$B9C/in.json" ) > "$B9C/out" 2>&1
  grep -q b9cplanted "$B9C/out" && echo projects.tsv >> "$B9C/ran"
  if [ -s "$B9C/ran" ]; then printf 'ran:%s' "$(sort -u "$B9C/ran" | paste -sd, -)"; else echo clean; fi
}
# The positive control: the pre-harbor#813 line, run the same way, does load the plant.
printf '%s\n' 'DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"' '. "$DIR/guard-lib.sh"' > "$B9C/probe.sh"
t_eq "B9c control: the old resolution loads the planted guard-lib.sh" ran:guard-lib.sh "$(b9c_run Probe "/bin/sh $B9C/probe.sh")"
# ONE assertion, not one per wired line (harbor#851): the wired list is built from the install and the
# box's hook declarations, so its length differs by runner and a per-line assert made floor-test's count
# (pinned in STATUS.md) runner-dependent. Every line is still run; each offender is named in the result.
_b9bad=""; _b9ran=0
while IFS='	' read -r _b9ev _b9cmd; do
  _b9lab="$(printf '%s\n' "$_b9cmd" | tr ' "' '\n\n' | sed -n 's#^.*/\([^/]*\.sh\)$#\1#p' | paste -sd+ -)"
  _b9want=clean   # every wired line, session-verdicts.sh included since reference-check.sh left $(dirname) (#880)
  _b9got="$(b9c_run "$_b9ev" "$_b9cmd")"; _b9ran=$((_b9ran + 1))
  [ "$_b9got" = "$_b9want" ] || _b9bad="${_b9bad:+$_b9bad; }$_b9lab ($_b9ev): want $_b9want, got $_b9got"
done < "$B9C/wired"
t_eq "B9c no wired hook command loads a file planted in the cwd" "" "$_b9bad"
t_eq "B9c the loop ran the wired list (not vacuous)" y "$([ "$_b9ran" -ge 7 ] && echo y || echo n)"

t_section "SW (harbor#954 PR B, #977): a settings env block that sets either switch is reported at SessionStart"
# The write-time guards miss five ways of putting a switch in a project's settings (FLOOR.md residuals). The
# check reads the FILE at SessionStart, so each shape is built the way its name says and only the end state is
# read: one fixture per shape, for both switches. floor-observe.sh carries it because it runs when the switch is set.
SW="$TMP/sw"; SWC="$SW/cfg"; mkdir -p "$SWC/bin" "$SW/real"
for _f in guard-lib.sh floor-normalize.awk floor-observe.sh; do cp "$SRC/$_f" "$SWC/bin/$_f"; done
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$SWC/settings.json"
sw_run() { # <project dir> [<observe script>] -> what the SessionStart hook printed
  printf '{"hook_event_name":"SessionStart","session_id":"S-sw","cwd":"%s"}' "$1" \
    | env -u CLAUDE_PROJECT_DIR -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW CLAUDE_CONFIG_DIR="$SWC" sh "${2:-$SWC/bin/floor-observe.sh}" 2>/dev/null
}
sw_proj() { rm -rf "$SW/$1"; mkdir -p "$SW/$1/.claude"; printf '%s' "$SW/$1"; }
# the control: the same hook, no switch in any settings file, says nothing
_p="$(sw_proj clean)"; printf '{"env":{"FOO":"1"}}\n' > "$_p/.claude/settings.json"
t_eq "SW a settings file with no switch in it is silent" "" "$(sw_run "$_p")"
for _n in HELM_DISABLE_FLOOR HELM_FLOOR_SHADOW; do
  _last="${_n#"${_n%?}"}"; _head="${_n%?}"
  _hex="$(printf '%s' "$_last" | od -An -tx1 | tr -d ' \n')"
  # 1. a JSON \u escape in the key
  _p="$(sw_proj "u-$_n")"; printf '{"env":{"%s\\u00%s":"1"}}\n' "$_head" "$_hex" > "$_p/.claude/settings.json"
  t_has "SW $_n: a JSON \\u-escaped key is reported" "$(sw_run "$_p")" "$_n"
  # 2. a split Edit: an existing near-miss key, edited to the real name
  _p="$(sw_proj "split-$_n")"; printf '{"env":{"%sX":"1"}}\n' "$_head" > "$_p/.claude/settings.json"
  t_eq "SW $_n: the near-miss key before the edit is silent" "" "$(sw_run "$_p")"
  sed "s/${_head}X/$_n/" "$_p/.claude/settings.json" > "$_p/.claude/s.tmp" && mv "$_p/.claude/s.tmp" "$_p/.claude/settings.json"
  t_has "SW $_n: a split Edit is reported" "$(sw_run "$_p")" "$_n"
  # 3. a project .claude reached through a symlink
  _p="$SW/link-$_n"; rm -rf "$_p" "$SW/real-$_n"; mkdir -p "$_p" "$SW/real-$_n"
  printf '{"env":{"%s":"1"}}\n' "$_n" > "$SW/real-$_n/settings.json"; ln -s "$SW/real-$_n" "$_p/.claude"
  t_has "SW $_n: a symlinked .claude is reported" "$(sw_run "$_p")" "$_n"
  # 4. a writer after a pipe
  _p="$(sw_proj "pipe-$_n")"; printf '{"env":{"%s":"1"}}\n' "$_n" | tee "$_p/.claude/settings.json" >/dev/null
  t_has "SW $_n: a writer after a pipe is reported" "$(sw_run "$_p")" "$_n"
  # 5. two steps: prepared elsewhere, then copied in
  _p="$(sw_proj "copy-$_n")"; printf '{"env":{"%s":"1"}}\n' "$_n" > "$SW/prep-$_n.json"; cp "$SW/prep-$_n.json" "$_p/.claude/settings.json"
  t_has "SW $_n: a two-step copy is reported" "$(sw_run "$_p")" "$_n"
  # the report names the file, and never the value
  t_has "SW $_n: the report names the settings file" "$(sw_run "$_p")" "$_p/.claude/settings.json"
  # the user tier, and a value that does not open the switch
  _p="$(sw_proj "user-$_n")"; printf '{"env":{"%s":"1"}}\n' "$_n" > "$SWC/settings.json"
  t_has "SW $_n: the user-tier settings.json is reported" "$(sw_run "$_p")" "$SWC/settings.json"
  printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$SWC/settings.json"
  printf '{"env":{"%s":"0"}}\n' "$_n" > "$_p/.claude/settings.json"
  t_eq "SW $_n: a value of 0 opens nothing and is silent" "" "$(sw_run "$_p")"
done
# the check can fail: the same fixtures against a floor-observe with the check cut out report nothing
awk '/^# ── a settings `env` block that sets either switch/ {skip=1} /^# A SHADOW session \(harbor#482\)/ {skip=0} !skip' \
  "$SRC/floor-observe.sh" > "$SWC/bin/observe-nocheck.sh"
t_eq "SW the cut-out copy differs from floor-observe.sh (the cut found the check)" yes \
  "$(cmp -s "$SWC/bin/observe-nocheck.sh" "$SRC/floor-observe.sh" && echo no || echo yes)"
_p="$(sw_proj mut)"; printf '{"env":{"HELM_DISABLE_FLOOR":"1"}}\n' > "$_p/.claude/settings.json"
t_has "SW the real hook reports the switch (mutation control)" "$(sw_run "$_p")" "HELM_DISABLE_FLOOR"
t_eq "SW with the check removed the report is empty (the fixtures above go red)" "" "$(sw_run "$_p" "$SWC/bin/observe-nocheck.sh")"

ff_sealed
t_done
