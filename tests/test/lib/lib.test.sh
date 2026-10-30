#!/usr/bin/env sh
# tests/lib: the harness must fail when a suite is wrong, not only pass when it is right.
# Each case runs a tiny child suite in a fake repo root and reads its exit code and output.
set -u
LIB="$(CDPATH= cd -- "$(dirname -- "$0")/../../lib" && pwd)"   # the harness under test (harbor#961 W2 moved this suite)
. "$LIB/core.sh"
. "$LIB/../admission/helper/lib.sh"   # tests/lib/guard.sh before harbor#961 W2
t_init

# Normalised like T_ROOT (cd/pwd), so a TMPDIR holding `//` cannot fail the root case (harbor#727).
R="$(CDPATH= cd -- "$T_TMP" && pwd)/root"; mkdir -p "$R/contracts" "$R/tests/x"; : > "$R/contracts/suites.txt"
child() { # <body> — runs it as a suite; prints "rc=<n>" then its output
  { printf '. "%s/core.sh"; . "%s/../admission/helper/lib.sh"; t_init\n' "$LIB" "$LIB"; printf '%s\n' "$1"; } > "$R/tests/x/c-test.sh"
  _o="$(sh "$R/tests/x/c-test.sh" 2>&1)"; printf 'rc=%s\n%s\n' "$?" "$_o"
}

t_section "verdicts"
o="$(child 't_section a; t_eq x 1 1; t_done')"
t_has 'a passing suite exits 0'           "$o" "rc=0"
t_has 'and prints the standard summary'   "$o" "c-test: 1 passed, 0 failed"
o="$(child 't_section a; t_eq x 1 2; t_done')"
t_has 'a failing assertion exits 1'       "$o" "rc=1"
t_has 'and names section, want and got'   "$o" "FAIL: a · x (want '1', got '2')"
o="$(child 't_section a; t_section b; t_eq x 1 1; t_done')"
t_has 'an empty section fails'            "$o" "a · section ran no assertions"
t_has '...and fails the suite'            "$o" "rc=1"
o="$(child 't_done')"
t_has 'a suite with no assertions fails'  "$o" "the suite ran no assertions"
o="$(child 't_section a; t_eq x 1 2; t_eq y 1 3; t_done')"
t_has 'a failed suite names its file once, as the fix line (contracts/logging.md)' "$o" "  fix: none automatic — see tests/x/c-test.sh"
t_eq '...once, after its FAIL lines' 1 "$(printf '%s\n' "$o" | grep -c 'fix: none automatic')"
t_eq '...and the summary is still the last line, unchanged' "c-test: 0 passed, 2 failed" "$(printf '%s\n' "$o" | tail -1)"
o="$(child 't_section a; t_eq x 1 1; t_done')"
t_hasnt 'a green suite prints no fix line' "$o" "fix: none automatic"

t_section "assertions"
o="$(child 't_section a; t_hasnt x "" needle; t_done')"
t_has 't_hasnt on empty text fails'       "$o" "x (no text to check)"
o="$(child 't_section a; t_hasnt x "hay" needle; t_has y "hay" ay; t_done')"
t_has 't_hasnt/t_has pass on real text'   "$o" "rc=0"
o="$(child 't_section a; t_exit x 1 false; t_done')"
t_has 't_exit matches an exact code'      "$o" "rc=0"
o="$(child "t_section a; t_exit x 1 sh -c 'exit 2'; t_done")"
t_has 't_exit rejects a different code'   "$o" "x (want 'exit 1', got 'exit 2')"

t_section "sandbox"
o="$(HARBOR_ADMISSION_DISABLE=1 HELM_DISABLE_FLOOR=1 CLOUD_POSTURE=deny child 't_section a; t_eq home "$T_TMP/home" "$HOME"; t_eq cfg "$T_TMP/cfg" "$CLAUDE_CONFIG_DIR"; t_eq knob "" "${HARBOR_ADMISSION_DISABLE:-}${HELM_DISABLE_FLOOR:-}${CLOUD_POSTURE:-}"; echo "tmp=$T_TMP"; t_done')"
t_has 'HOME, config dir and knobs are the sandbox' "$o" "rc=0"
_ct="$(printf '%s\n' "$o" | sed -n 's/^tmp=//p')"
[ -n "$_ct" ] && [ ! -e "$_ct" ] && t_pass || t_fail "the child's sandbox was not removed: ${_ct:-no path printed}"
# harbor#773: CI's HARBOR_STATUS_SUITE_COUNTS reached floor.status-test through its caller.
o="$(export HARBOR_STATUS_SUITE_COUNTS=floor-test=1,normalize-test=1 HARBOR_SCOPE_ROOT=/elsewhere HARBOR_STATUS_WORKFLOW=/x.yml FAST=1 HARBOR_TEST_IN_SUITE=1
     child 't_section a; t_eq x 1 1; printf "cleared:%s|%s|%s|%s kept:%s\n" "${HARBOR_STATUS_SUITE_COUNTS-unset}" "${HARBOR_SCOPE_ROOT-unset}" "${HARBOR_STATUS_WORKFLOW-unset}" "${FAST-unset}" "${HARBOR_TEST_IN_SUITE-unset}"; t_done')"
t_has "the caller's HARBOR_* knobs and status-gen's FAST never reach a suite" "$o" 'cleared:unset|unset|unset|unset '
t_has '...but T_PASS_ENV, the re-entry marker, does' "$o" ' kept:1'
# harbor#824: git exports GIT_DIR into every hook it fires (GIT_WORK_TREE/GIT_INDEX_FILE from a
# linked worktree too) — a suite that builds its own scratch git repo and drives it with
# `git -C "$T_TMP/…"` must not inherit them (project-init#1065: it acted on the real clone instead).
o="$(export GIT_DIR=/should-not-leak GIT_WORK_TREE=/should-not-leak GIT_INDEX_FILE=/should-not-leak \
            GIT_COMMON_DIR=/x GIT_OBJECT_DIRECTORY=/x GIT_ALTERNATE_OBJECT_DIRECTORIES=/x \
            GIT_QUARANTINE_PATH=/x GIT_PREFIX=sub/
     child 't_section a; t_eq x 1 1; printf "cleared:%s|%s|%s|%s|%s|%s|%s|%s\n" "${GIT_DIR-unset}" "${GIT_WORK_TREE-unset}" "${GIT_INDEX_FILE-unset}" "${GIT_COMMON_DIR-unset}" "${GIT_OBJECT_DIRECTORY-unset}" "${GIT_ALTERNATE_OBJECT_DIRECTORIES-unset}" "${GIT_QUARANTINE_PATH-unset}" "${GIT_PREFIX-unset}"; t_done')"
t_has "a suite never inherits the caller's GIT_* (harbor#824, cf. project-init#1065)" "$o" \
  'cleared:unset|unset|unset|unset|unset|unset|unset|unset'
o="$(child 't_section a; t_eq root "'"$R"'" "$T_ROOT"; t_done')"
t_has 'the repo root is found from the suite path' "$o" "rc=0"
NR="$(CDPATH= cd -- "$T_TMP" && pwd)/norepo"; mkdir -p "$NR/bin"  # a suite the box carries: no checkout above it (harbor#727)
printf '. "%s/core.sh"; t_init\nt_section a; t_eq root "%s" "$T_ROOT"; t_done\n' "$LIB" "$NR" > "$NR/bin/n-test.sh"
o="$(sh "$NR/bin/n-test.sh" 2>&1; echo "rc=$?")"
t_has 'with no checkout, a suite exits 2' "$o" "rc=2"
t_has '...and says the repo root was not found' "$o" "repo root not found"
o="$(T_STANDALONE=1 sh "$NR/bin/n-test.sh" 2>&1; echo "rc=$?")"
t_has 'T_STANDALONE=1 with no checkout: the root is the dir above the suite' "$o" "rc=0"

t_section "guard channels fold into one token"
g() { printf '#!/bin/sh\ncat >/dev/null\n%s\n' "$1" > "$T_TMP/g.sh"; t_decide "$T_TMP/g.sh" '{}'; }
t_eq 'exit 0, no output'   allow    "$(g 'exit 0')"
t_eq 'permissionDecision'  ask      "$(g "printf '{\"hookSpecificOutput\":{\"permissionDecision\":\"ask\"}}'")"
t_eq 'exit 2'              block    "$(g 'exit 2')"
t_eq 'any other exit'      exit-1   "$(g 'exit 1')"
t_eq 'output that is not a decision' PARSE_ERR "$(g 'echo hello')"
t_eq 'two decisions are not one'   PARSE_ERR "$(g "printf '{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}\n%.0s' 1 2")"
t_eq 't_pad is exact'      33000    "$(t_pad 33000 | wc -c | tr -d ' ')"

t_section "table runner"
ln -s "$LIB" "$R/tests/lib"
FG="$T_TMP/fg"; mkdir -p "$FG"; : > "$FG/floor-normalize.awk"
cat > "$FG/guard-fake.sh" <<'EOF'
p="$(cat)"; c="$(printf '%s' "$p" | jq -r '.tool_input.command // .tool_input.file_path // .tool_input.url')"
case "$c" in
  ok*) exit 0 ;;
  ask*) printf '{"hookSpecificOutput":{"permissionDecision":"ask","permissionDecisionReason":"knob=%s"}}' "${KNOB:-}" ;;
  blk*) exit 2 ;;
  crash*) exit 3 ;;
  long*) [ "${#c}" -gt 30000 ] && exit 2; exit 0 ;;
  ctx*) [ "$(printf '%s' "$p" | jq -r '.agent_type // ""')" = sub ] && exit 2; exit 0 ;;
  fx*) [ -f "$(dirname "$0")/floor-normalize.awk" ] || exit 2; exit 0 ;;
  home:*) [ "$c" = "home:$HOME/x" ] && exit 0; exit 2 ;;
  loop*) sh -c 'while :; do :; done # loopmark' ;;
  pid:*) sleep 7769 & printf '%s\n' "$!" >> "${c#pid:}"; wait ;;
  cfg:*) [ "$c" = "cfg:$CLAUDE_CONFIG_DIR/x" ] && exit 0; exit 2 ;;
  web:*) [ "$c" = "web:$WANT" ] && exit 0; exit 2 ;;
  root:*) [ "$c" = "root:$ROOTWANT/x" ] && exit 0; exit 2 ;;
  noisy*) echo "HELM FLOOR [x:noisy]: BLOCKED" >&2; exit 2 ;;
  *) printf '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"no"}}' ;;
esac
EOF
rows() { printf '%s\n' "$@" > "$T_TMP/rows.jsonl"; }
tchild() { child "T_JOBS=3; . \"$LIB/table.sh\"; $1; t_done"; }  # <runner call>
rows '{"id":"r-allow","want":"allow","cmd":"ok"}' '{"id":"r-ask","want":"ask","cmd":"ask"}' \
     '{"id":"r-deny","want":"deny","cmd":"zap"}' '{"id":"r-block","want":"block","cmd":"blk"}' \
     '{"id":"r-pad","want":"block","cmd":"long","pad":30001}' '{"id":"r-ctx","want":"block","cmd":"ctx","ctx":{"agent_type":"sub"}}' \
     '{"id":"r-nonorm","want":"block","cmd":"fx","fixture":"nonorm"}' '{"id":"r-copy","want":"allow","cmd":"fx","fixture":"copy"}' \
     '{"id":"r-home","want":"allow","tool":"Write","path":"home:{home}/x"}' '{"id":"r-todo","want":"deny","todo":"allow","cmd":"zap"}'
o="$(tchild "t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has 'every verdict, pad, ctx, fixture and {home} row passes' "$o" "c-test: 10 passed, 0 failed"
t_has 'a todo row is reported, not failed' "$o" "todo: r-todo — today deny, should be allow"
rows '{"id":"f-first","want":"allow","cmd":"crash"}' '{"id":"ok-mid","want":"allow","cmd":"ok"}' '{"id":"f-last","want":"allow","cmd":"zap"}'
o="$(tchild "t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has 'a crash is never read as allow' "$o" "f-first (want 'allow', got 'exit-3')"
t_eq 'failures print in row order' "f-first f-last" "$(printf '%s\n' "$o" | sed -n 's/.*· \(f-[a-z]*\) .*/\1/p' | tr '\n' ' ' | sed 's/ $//')"
rows '{"id":"t-loop","want":"allow","cmd":"loop"}' '{"id":"t-ok","want":"allow","cmd":"ok"}'
o="$(tchild "export T_ROW_SECS=1; t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has 'a guard that never answers reads timeout' "$o" "t-loop (want 'allow', got 'timeout')"
# harbor#768: under dash `set -m` made no group, so only the guard died. Each child records its pid.
settle() { _sa=x; _si=0; while [ -n "$_sa" ] && [ "$_si" -lt 20 ]; do  # <pidfile>: alive after up to 2s
  _sa="$(for _p in $(cat "$1"); do kill -0 "$_p" 2>/dev/null && printf '%s ' "$_p"; done)"; [ -z "$_sa" ] || sleep 0.1
  _si=$((_si + 1)); done; printf '%s' "$_sa"; }
mkdir -p "$T_TMP/dash"; ln -s /bin/dash "$T_TMP/dash/sh"; KID="$T_TMP/kid.pid"
t_eq 'the dash case resolves sh to dash' dash "$(PATH="$T_TMP/dash:$PATH"; sh -c 'echo ${BASH_VERSION:+bash}${BASH_VERSION:-dash}')"
for _sh in sh dash; do
  : > "$KID"; rows '{"id":"t-kid","want":"allow","cmd":"pid:'"$KID"'"}'
  o="$([ "$_sh" = sh ] || PATH="$T_TMP/dash:$PATH"; tchild "export T_ROW_SECS=1; t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
  t_has "under $_sh a guard whose child never exits reads timeout" "$o" "t-kid (want 'allow', got 'timeout')"
  t_eq "under $_sh the guard recorded its child, or the next row is vacuous" 1 "$(grep -c . "$KID")"
  t_eq "under $_sh that child is dead after T_ROW_SECS" '' "$(settle "$KID")"
  for _p in $(cat "$KID"); do kill -9 "$_p" 2>/dev/null; done  # a red run leaks nothing
done
rows '{"id":"p-cfg","want":"allow","cmd":"cfg:{cfg}/x"}' '{"id":"p-root","want":"allow","cmd":"root:{root}/x"}' \
     '{"id":"p-input","want":"allow","tool":"Web","input":{"url":"web:{tmp}/u"},"env":{"WANT":"{tmp}/u"}}'
o="$(tchild "export ROOTWANT=\"\$T_ROOT\"; t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has '{cfg}, {root}, {tmp}, input payloads and env placeholders resolve' "$o" "c-test: 3 passed, 0 failed"
rows '{"id":"m-block","cmd":"noisy","has":"HELM FLOOR [x:noisy]"}'
o="$(tchild "t_msgs $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has "a block's message is its stderr" "$o" "c-test: 1 passed, 0 failed"
rows '{"id":"s1","rule":"a","want":"allow","cmd":"ok"}' '{"id":"s2","rule":"a","want":"allow","cmd":"zap"}' \
     '{"id":"s3","rule":"a","want":"deny","cmd":"zap"}' '{"id":"s4","rule":"b","want":"allow","cmd":"ok"}'
o="$(tchild "export T_SMOKE=1; t_table $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has 'smoke runs the first row per rule and verdict' "$o" "c-test smoke: 3 passed, 0 failed (NOT a full run)"
rows '{"id":"m-env","cmd":"ask","env":{"KNOB":"on"},"has":"knob=on"}' '{"id":"m-noenv","cmd":"ask","hasnt":"knob=on"}'
o="$(tchild "t_msgs $FG/guard-fake.sh $T_TMP/rows.jsonl")"
t_has 'message rows read env and reason text' "$o" "c-test: 2 passed, 0 failed"

t_section "shared rows"
S="$T_TMP/sh"; mkdir -p "$S"
echo '{"guard":"x","posture":"XP","reps":{"deny":"zap it","ask":"poke it","allow":{"cmd":"ls","want":"block"}}}' > "$S/reg"
printf '%s\n' '{"shape":"up","form":"{BIN} {args}","reps":["deny"],"expect":"same"}' \
  '{"shape":"sub","reps":["ask"],"expect":"no-human"}' '{"shape":"up2","reps":["allow"],"expect":"same"}' '{"shape":"pd","posture":"deny","reps":["ask"],"expect":"no-human"}' > "$S/shapes"
echo '{"id":"b1","cmd":"true","pad":5}' > "$S/benign"
echo '{"guard":"x","id":"shape:sub/ask","want":"ask","todo":"deny","why":"w"}' > "$S/ex"
gen() { jq -c -n --arg g x -f "$LIB/shared.jq" --slurpfile reg "$S/reg" --slurpfile shapes "$S/shapes" \
  --slurpfile benign "$S/benign" --slurpfile ex "$S/ex" | jq -r "$1"; }
t_eq 'a form rewrites the representative' "ZAP it"  "$(gen 'select(.id == "shape:up/deny") | .cmd')"
t_eq 'no-human escalates ask'             "deny"    "$(gen 'select(.id == "shape:pd/ask") | .want')"
t_eq 'posture sets the guard knob'        "deny"    "$(gen 'select(.id == "shape:pd/ask") | .env.XP')"
t_eq 'an exemption replaces the verdict'  "ask/deny" "$(gen 'select(.id == "shape:sub/ask") | "\(.want)/\(.todo)"')"
t_eq 'benign rows keep their fields'      "allow/5" "$(gen 'select(.id == "benign:b1") | "\(.want)/\(.pad)"')"
t_eq 'a rep can carry its own verdict'    "ls/block" "$(gen 'select(.id == "shape:up2/allow") | "\(.cmd)/\(.want)"')"

t_section "a suite that writes the repo's shared git config fails (harbor#1152)"
git init -q "$R" 2>/dev/null
o="$(child 't_section a; t_eq x 1 1; git -C "$T_ROOT" config user.email t@t; t_done')"
t_has 'a leaking suite exits 1'          "$o" "rc=1"
t_has 'and names the key it added'       "$o" "wrote the shared git config of $R (added: user.email)"
t_has '...and the suite'                 "$o" "c-test: 1 passed, 1 failed"
o="$(child 't_section a; t_eq x 1 1; git -C "$T_ROOT" config core.sparsecheckout true; t_done')"
t_has 'any key counts, not only user.*'  "$o" "added: core.sparsecheckout"
git -C "$R" config --local --unset user.email; git -C "$R" config --local --unset core.sparsecheckout
o="$(child 't_section a; t_eq x 1 1; git init -q "$T_TMP/r"; git -C "$T_TMP/r" config user.email t@t; t_done')"
t_has 'a temp repo of its own is fine'   "$o" "rc=0"
t_eq 'and left the root config clean'    "" "$(git -C "$R" config --local --get user.email)"
# Another worktree's `git push -u` writes branch.* into the shared config mid-suite: not the suite's leak.
o="$(child 't_section a; t_eq x 1 1; git -C "$T_ROOT" config branch.other.remote origin; t_done')"
t_has 'a branch.* key from a concurrent push -u is not a leak' "$o" "rc=0"
git -C "$R" config --local --unset branch.other.remote
o="$(child 't_section a; t_eq x 1 1; git -C "$T_ROOT" config branch.other.remote origin; git -C "$T_ROOT" config user.email t@t; t_done')"
t_has '...but a real key beside it still fails, named' "$o" "(added: user.email)"
git -C "$R" config --local --unset branch.other.remote; git -C "$R" config --local --unset user.email

t_done
