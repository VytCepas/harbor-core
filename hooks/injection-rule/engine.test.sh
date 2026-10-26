#!/usr/bin/env sh
# inject-hook.sh, the engine, against packs this suite writes: event and tool routing, the
# predicates and their substring traps, malformed packs, the once-ledger, run: bodies and
# decisions, and the provenance stamp (harbor#173, #180, #254). Every narrowing is asserted
# both ways: a silent arm is written after the pack whose absence it would pass without.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
. "$T_ROOT/tests/hooks/inject-fixture.sh"

t_section "1 · event and tool routing"
pack "$CFG/inject.d" 10-sub.md <<'PACK'
---
id: sub
event: SubagentStart
when: always
once: never
---
SUBAGENT-NOTE
PACK
t_has "the matching event fires" "$(fire '{"hook_event_name":"SubagentStart","session_id":"a"}')" SUBAGENT-NOTE
t_eq "a different event says nothing" "" "$(fire '{"hook_event_name":"PreCompact","session_id":"a"}')"
t_eq "a payload with no event says nothing" "" "$(fire '{"session_id":"a"}')"
t_eq "malformed JSON fails open, silently" "" "$(fire 'not json at all')"
pack "$REPO/.claude/inject.d" 10-merge.md <<'PACK'
---
id: merge
event: PreToolUse
tool: Bash
when: cmd-prefix gh pr merge
once: never
---
MERGE-NOTE
PACK
t_has "a repo pack fires alongside the box packs" "$(fire "$(bash_ev PreToolUse 'gh pr merge 173 --squash')")" MERGE-NOTE
t_has "the envelope names the event it answered" "$(fire "$(bash_ev PreToolUse 'gh pr merge 173')")" '"hookEventName":"PreToolUse"'
t_eq "a tool the rule does not name says nothing" "" "$(fire "$(tool_ev PreToolUse Write file_path /tmp/x)")"

t_section "1 · a tier that is the same directory twice is loaded once"
pack "$T/same/.claude/inject.d" 10-once.md <<'PACK'
---
id: once
event: SubagentStart
when: always
once: never
---
ONCE-NOTE
PACK
_fires() { # <config-dir> <project-dir> → how many times ONCE-NOTE appears
  printf '%s' '{"hook_event_name":"SubagentStart","session_id":"dup1"}' \
    | CLAUDE_CONFIG_DIR="$1" CLAUDE_PROJECT_DIR="$2" sh "$SUT" 2>/dev/null | grep -o ONCE-NOTE | wc -l | tr -d ' '
}
t_eq "project dir = \$HOME: one directory, one delivery" 1 "$(_fires "$T/same/.claude" "$T/same")"
ln -s "$T/same" "$T/samelink"
t_eq "the same directory reached through a symlink is still one" 1 "$(_fires "$T/samelink/.claude" "$T/same")"

t_section "1 · source-is: SessionStart says why it started"
pack "$CFG/inject.d" 11-src.md <<'PACK'
---
id: src
event: SessionStart
when: source-is compact
once: never
---
SOURCE-NOTE
PACK
t_has "source-is matches the declared source" "$(fire '{"hook_event_name":"SessionStart","source":"compact","session_id":"s1"}')" SOURCE-NOTE
t_eq "silent on a different source" "" "$(fire '{"hook_event_name":"SessionStart","source":"startup","session_id":"s2"}')"
t_eq "silent when the payload carries no source" "" "$(fire '{"hook_event_name":"SessionStart","session_id":"s3"}')"
t_eq "source-is compact does not match \"compacted\"" "" "$(fire '{"hook_event_name":"SessionStart","source":"compacted","session_id":"s4"}')"
rm -f "$CFG/inject.d/11-src.md"

t_section "2 · the predicates, and the substring traps they exist to avoid"
for c in 'gh pr list --search "pr merge"' 'echo "run gh pr merge 173 later"' 'git commit -m "gh pr merge"' 'gh pr merge --help'; do
  t_eq "silent on: $c" "" "$(fire "$(bash_ev PreToolUse "$c")")"
done
t_eq "the phrase inside a heredoc body says nothing" "" "$(fire "$(bash_ev PreToolUse 'cat <<NOTE
gh pr merge 173 --squash is what we ran yesterday
NOTE')")"
t_has "a real command after a heredoc still fires" "$(fire "$(bash_ev PreToolUse 'cat <<NOTE
context
NOTE
gh pr merge 173')")" MERGE-NOTE
pack "$REPO/.claude/inject.d" 20-path.md <<'PACK'
---
id: pathrule
event: PreToolUse
tool: Write|Edit
when: path-contains vault/
once: never
---
PATH-NOTE
PACK
t_has "path-contains fires, and the alternation accepts Edit" "$(fire "$(tool_ev PreToolUse Edit file_path /x/vault/report.md)")" PATH-NOTE
t_has "the alternation accepts Write too" "$(fire "$(tool_ev PreToolUse Write file_path /x/vault/a.md)")" PATH-NOTE
t_eq "path-contains says nothing off the path" "" "$(fire "$(tool_ev PreToolUse Edit file_path /x/src/report.md)")"
pack "$REPO/.claude/inject.d" 30-multi.md <<'PACK'
---
id: multipred
event: PreToolUse
tool: Bash
when: cmd-prefix just corpus
when: repo-has .claude/inject.d
once: never
---
MULTI-NOTE
PACK
pack "$REPO/.claude/inject.d" 31-multi-fail.md <<'PACK'
---
id: multifail
event: PreToolUse
tool: Bash
when: cmd-prefix just corpus
when: repo-has NOTHING-IS-HERE
once: never
---
MULTIFAIL-NOTE
PACK
_jc="$(fire "$(bash_ev PreToolUse 'just corpus')")"
t_has "two predicates both satisfied fire" "$_jc" MULTI-NOTE
t_hasnt "predicates are ANDed: one false is silent" "$_jc" MULTIFAIL-NOTE
pack "$REPO/.claude/inject.d" 32-neg.md <<'PACK'
---
id: negated
event: PreToolUse
tool: Bash
when: not repo-has NOTHING-IS-HERE
once: never
---
NEG-NOTE
PACK
t_has "not <predicate> inverts" "$(fire "$(bash_ev PreToolUse 'ls')")" NEG-NOTE
rm -f "$REPO/.claude/inject.d/32-neg.md" "$REPO/.claude/inject.d/31-multi-fail.md"

t_section "3 · a malformed pack is silent (skill-book's --chekc shape)"
pack "$REPO/.claude/inject.d" 40-typo.md <<'PACK'
---
id: typo
event: PreToolUse
tool: Bash
when: cmd-prefx gh pr merge
once: never
---
TYPO-NOTE
PACK
pack "$REPO/.claude/inject.d" 41-nowhen.md <<'PACK'
---
id: nowhen
event: PreToolUse
tool: Bash
once: never
---
NOWHEN-NOTE
PACK
gone "a misspelled predicate never fires" "$(fire "$(bash_ev PreToolUse 'gh pr merge 1')")" TYPO-NOTE
gone "a pack with no when: refuses to fire" "$(fire "$(bash_ev PreToolUse 'ls')")" NOWHEN-NOTE
rm -f "$REPO/.claude/inject.d/40-typo.md" "$REPO/.claude/inject.d/41-nowhen.md"

t_section "3b · the five adversarial-pass defects, each pinned"
pack "$REPO/.claude/inject.d" 42-negtypo.md <<'PACK'
---
id: negtypo
event: PreToolUse
tool: Bash
when: not cmd-prefx git push
once: never
---
NEGTYPO-NOTE
PACK
gone "(1) not <unknown predicate> stays silent" "$(fire "$(bash_ev PreToolUse 'ls -la')")" NEGTYPO-NOTE
rm -f "$REPO/.claude/inject.d/42-negtypo.md"
gone "(1b) a parenthesised aside in a commit message" \
  "$(fire "$(bash_ev PreToolUse 'git commit -m "docs: record the gate (gh pr merge needs the backstop first)"')")" MERGE-NOTE
gone "(1b) a multi-line quoted commit body" "$(fire "$(bash_ev PreToolUse 'git commit -m "line one
gh pr merge is what we did yesterday"')")" MERGE-NOTE
gone "(1b) a semicolon inside a quoted body" \
  "$(fire "$(bash_ev PreToolUse 'gh issue comment 12 --body "then; gh pr merge 3 --squash"')")" MERGE-NOTE
fire "$(bash_ev PreToolUse 'git commit -m "note: (gh pr merge) later"' quote-budget)" >/dev/null
t_has "(1b) the real command still fires after a benign quoted mention" \
  "$(fire "$(bash_ev PreToolUse 'gh pr merge 3 --squash' quote-budget)")" MERGE-NOTE
t_has "(1b) an unquoted second command still fires" "$(fire "$(bash_ev PreToolUse 'git status && gh pr merge 3')")" MERGE-NOTE
t_has "(2) -h inside a quoted argument does not silence a real merge" \
  "$(fire "$(bash_ev PreToolUse "gh pr merge 12 --body 'pass -h to see the flags'")")" MERGE-NOTE
gone "(2) --help still silences" "$(fire "$(bash_ev PreToolUse 'gh pr merge --help')")" MERGE-NOTE
pack "$REPO/.claude/inject.d" 43-null.md <<'PACK'
---
id: nullprobe
event: PreToolUse
tool: Bash
when: content-contains null
once: never
---
NULL-NOTE
PACK
gone "(3) an absent tool_response is empty content, not \"null\"" "$(fire "$(bash_ev PreToolUse 'ls')")" NULL-NOTE
rm -f "$REPO/.claude/inject.d/43-null.md"
# (4) one fork per segment blew the 10 s hook timeout. harbor#789: bound the hook's CPU (every child it
# reaped), never the host's wall clock, as #755 did. Measured 2026-09-28: 0.5-0.8 s of CPU, 0.8 s beside
# 80 busy loops that took the wall to 6 s, 17.6 s with a tr per segment. A hang is killed at 60 s.
_cost() { # <stdin> <cmd...> -> "<done|killed> <cpu s> <wall s>" for cmd and every child it reaped
  perl -MTime::HiRes=time -e '
    my ($in, @cmd) = @ARGV; my $t0 = time; my $p = fork // die;
    if (!$p) { setpgrp; open STDIN, "<", $in; open STDOUT, ">", "/dev/null"; open STDERR, ">&", \*STDOUT; exec @cmd; exit 127 }
    $SIG{ALRM} = sub { kill "-KILL", $p }; alarm 60;
    1 while waitpid($p, 0) == -1 && $!{EINTR}; alarm 0;
    printf "%s %.2f %.2f\n", ($? == 0 ? "done" : "killed"), (times)[2] + (times)[3], time - $t0' "$@"
}
_big="$(awk 'BEGIN { for (i = 0; i < 3000; i++) printf "echo seg%d && ", i; print "true" }')"
bash_ev PreToolUse "$_big" > "$T/big.json"
# (4b) CPU cannot see a hook that sleeps or blocks, and one past its timeout fails OPEN. So its wall, less
# the queueing the host's load explains (its CPU times the wall/CPU of a CPU-bound baseline run either side
# of it, the larger), stays under the old 5 s bound, capped by the timeout inject-install really wires.
mkdir -p "$T/wired"; printf '{}\n' > "$T/wired/settings.json"
env -u CLAUDE_CONFIG_DIR -u CLAUDECODE sh "$T_ROOT/bin/inject-install.sh" --dir "$T/wired" --apply >/dev/null 2>&1
_to="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | select(.command | test("injection-rule")) | .timeout // 600] | min // empty' \
  "$T/wired/settings.json" 2>/dev/null)"
_base() { _cost /dev/null awk 'BEGIN { for (i = 0; i < 10000000; i++) s += i }'; }
_b1="$(_base)"
_cost="$(_cost "$T/big.json" env CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$REPO" sh "$SUT")"
_b2="$(_base)"
t_eq "(4) a 3,000-segment command costs the hook at most 3s of CPU (${_cost:-no measurement}: exit, cpu s, wall s)" yes \
  "$(printf '%s\n' "$_cost" | awk '$1 == "done" && $2 <= 3 { print "yes" }')"
_est="$(printf '%s %s %s\n' "$_cost" "$_b1" "$_b2" | awk '$1 == "done" && $5 > 0 && $8 > 0 {
  f = $6 / $5; if ($9 / $8 > f) f = $9 / $8; if (f < 1) f = 1; printf "%.2f", $3 - $2 * (f - 1) }')"
_cap="$(awk -v t="${_to:-0}" 'BEGIN { print (t > 0 && t < 5) ? t : 5 }')"
t_eq "(4b) and is not blocked: wall less host load = ${_est:-unmeasured} s, bound ${_cap} s (hook timeout ${_to:-unread}s; $_cost; baselines $_b1 / $_b2)" yes \
  "$(awk -v e="$_est" -v c="$_cap" -v t="${_to:-}" 'BEGIN { if (e != "" && t != "" && e + 0 <= c + 0) print "yes" }')"

t_section "4 · the once-ledger"
pack "$REPO/.claude/inject.d" 50-once.md <<'PACK'
---
id: oncerule
event: PreToolUse
tool: Bash
when: cmd-prefix make deploy
once: session
---
ONCE-NOTE
PACK
t_has "once: session delivers the first time" "$(fire "$(bash_ev PreToolUse 'make deploy' sess-once)")" ONCE-NOTE
gone "once: session stays quiet the second time" "$(fire "$(bash_ev PreToolUse 'make deploy' sess-once)")" ONCE-NOTE
t_has "a different session gets its own first delivery" "$(fire "$(bash_ev PreToolUse 'make deploy' sess-other)")" ONCE-NOTE
t_has "once: never repeats without limit" "$(fire "$(bash_ev PreToolUse 'gh pr merge 1' sess-once)")" MERGE-NOTE
# harbor#180: a Bash rule at PreToolUse has no path or content, so `match` fell back to `session`.
pack "$REPO/.claude/inject.d" 51-match.md <<'PACK'
---
id: matchrule
event: PreToolUse
tool: Bash
when: cmd-prefix deploy
once: match
---
MATCH-NOTE
PACK
t_has "once: match delivers the first command" "$(fire "$(bash_ev PreToolUse 'deploy alpha' sess-m)")" MATCH-NOTE
gone "once: match is quiet on the same command twice" "$(fire "$(bash_ev PreToolUse 'deploy alpha' sess-m)")" MATCH-NOTE
t_has "once: match still speaks for a DIFFERENT command" "$(fire "$(bash_ev PreToolUse 'deploy beta' sess-m)")" MATCH-NOTE
fire "$(jq -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",session_id:"../../escape",tool_input:{command:"make deploy"}}')" >/dev/null
t_eq "a traversing session id is refused, not used as a path" no \
  "$([ -e "$CFG/state/inject/../../escape.seen" ] && echo yes || echo no)"

t_section "5 · run: — a dynamic body"
pack "$REPO/.claude/inject.d" dyn.sh <<'PACK'
#!/bin/sh
[ -f MARKER ] && printf 'DYNAMIC-NOTE %s\n' "$(cat MARKER)"
exit 0
PACK
pack "$REPO/.claude/inject.d" 60-run.md <<'PACK'
---
id: dynrule
event: PreToolUse
tool: Bash
when: cmd-prefix make ship
once: never
run: dyn.sh
---
PACK
gone "run: producing no output produces no note" "$(fire "$(bash_ev PreToolUse 'make ship')")" DYNAMIC-NOTE
printf 'from-the-repo\n' > "$REPO/MARKER"
t_has "run: stdout becomes the note, with cwd = the session repo" "$(fire "$(bash_ev PreToolUse 'make ship')")" 'DYNAMIC-NOTE from-the-repo'
# A real script outside the pack dir: the legacy `../../../../bin/sh` target did not exist, so it proved nothing.
printf '#!/bin/sh\necho ESCAPE-RAN\n' > "$REPO/escape.sh"; cp "$REPO/escape.sh" "$REPO/.claude/inject.d/inside.sh"
printf -- '---\nid: escaper\nevent: PreToolUse\ntool: Bash\nwhen: cmd-prefix make ship\nonce: never\nrun: %s\n---\n' ../../escape.sh \
  > "$REPO/.claude/inject.d/61-escape.md"
gone "run: with .. is refused" "$(fire "$(bash_ev PreToolUse 'make ship')")" ESCAPE-RAN
sed 's|^run: ../../escape.sh$|run: inside.sh|' "$REPO/.claude/inject.d/61-escape.md" > "$T/e.md" && mv "$T/e.md" "$REPO/.claude/inject.d/61-escape.md"
t_has "the same script beside its pack does run (the needle can appear)" "$(fire "$(bash_ev PreToolUse 'make ship')")" ESCAPE-RAN
rm -f "$REPO/.claude/inject.d/61-escape.md" "$REPO/.claude/inject.d/inside.sh" "$REPO/escape.sh" "$REPO/.claude/inject.d/60-run.md" "$REPO/.claude/inject.d/dyn.sh" "$REPO/MARKER"

t_section "7 · provenance"
t_has "with no salt the note is unstamped and still fires" "$(fire '{"hook_event_name":"SubagentStart","session_id":"p1"}')" '[HARBOR GOVERNANCE]'
printf 'test-salt\n' > "$CFG/.helm-govern-salt"
_a="$(fire '{"hook_event_name":"SubagentStart","session_id":"p1"}')"; _b="$(fire '{"hook_event_name":"SubagentStart","session_id":"p2"}')"
t_has "with a salt the note carries a session token" "$_a" 'HARBOR GOVERNANCE '
t_eq "two sessions get different stamps" yes "$([ "$_a" != "$_b" ] && echo yes)"
rm -f "$CFG/.helm-govern-salt"

t_section "7 · every note starts [context:<id>] (harbor#957)"
pack "$CFG/inject.d" 12-ctx-a.md <<'PACK'
---
id: ctx-static
event: SessionStart
when: always
once: never
---
STATIC-BODY
PACK
pack "$CFG/inject.d" 13-ctx-b.md <<'PACK'
---
id: ctx-dynamic
event: SessionStart
when: always
once: never
run: ctx-b.sh
---
PACK
printf '#!/bin/sh\necho DYNAMIC-BODY\n' > "$CFG/inject.d/ctx-b.sh"
_c="$(fire '{"hook_event_name":"SessionStart","session_id":"c1"}')"
t_has "a static note leads with its own id" "$_c" '[context:ctx-static] STATIC-BODY'
t_has "a run: note leads with its own id" "$_c" '[context:ctx-dynamic] DYNAMIC-BODY'
rm -f "$CFG/inject.d/12-ctx-a.md" "$CFG/inject.d/13-ctx-b.md" "$CFG/inject.d/ctx-b.sh"

t_section "a run: pack can decide, and only where the harness can hear it (harbor#254)"
DEC="$T/dec"; mkdir -p "$DEC/inject.d"
pack "$DEC/inject.d" decider.sh <<'PACK'
#!/usr/bin/env sh
printf 'HARBOR-DECISION deny: the backstop refused, route via merge-check --merge\n'
PACK
pack "$DEC/inject.d" 90-decide.md <<'PACK'
---
id: decide-test
event: PreToolUse
tool: Bash
when: cmd-prefix perilous
run: decider.sh
once: never
---
PACK
_d="$(fire_cfg "$DEC" "$(bash_ev PreToolUse 'perilous thing' "d-$$")")"
t_has "a run: pack sentinel becomes a real PreToolUse deny" "$_d" '"permissionDecision":"deny"'
t_has "the reason travels with the decision" "$_d" 'route via merge-check --merge'
t_hasnt "a decision does not double as a note" "$_d" 'additionalContext'
sed 's/^event: PreToolUse$/event: PostToolUse/' "$DEC/inject.d/90-decide.md" > "$T/d.md" && mv "$T/d.md" "$DEC/inject.d/90-decide.md"
_d2="$(fire_cfg "$DEC" "$(bash_ev PostToolUse 'perilous thing' "d-$$")")"
t_hasnt "a deny on an event that cannot carry one is downgraded" "$_d2" 'permissionDecision'
t_has "and the text still arrives, as a note" "$_d2" 'route via merge-check --merge'
t_has "the downgraded note rides additionalContext" "$_d2" 'additionalContext'
sed 's/^event: PostToolUse$/event: PreToolUse/' "$DEC/inject.d/90-decide.md" > "$T/d.md" && mv "$T/d.md" "$DEC/inject.d/90-decide.md"
pack "$DEC/inject.d" 91-static.md <<'PACK'
---
id: static-test
event: PreToolUse
tool: Bash
when: cmd-prefix staticcase
once: never
---
HARBOR-DECISION deny: this is prose about the mechanism, not a decision.
PACK
_d3="$(fire_cfg "$DEC" "$(bash_ev PreToolUse 'staticcase here' "d-$$")")"
t_has "a static body quoting the sentinel is delivered" "$_d3" 'prose about the mechanism'
t_hasnt "only run: output can decide; the static body is prose" "$_d3" 'permissionDecision'
t_done
