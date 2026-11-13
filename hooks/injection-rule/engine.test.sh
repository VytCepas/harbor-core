#!/usr/bin/env sh
# inject-hook.sh, the engine, against packs this suite writes: event and tool routing, the
# predicates and their substring traps, malformed packs, the once-ledger, run: bodies and
# decisions, and the provenance stamp (harbor#173, #180, #254). Every narrowing is asserted
# both ways: a silent arm is written after the pack whose absence it would pass without.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
. "$T_ROOT/tests/context/injection-rule/fixture.sh"

t_section "1 · event and tool routing"
pack "$CFG/context-rules/user" 10-sub.md <<'PACK'
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
pack "$REPO/context-rules/repo" 10-merge.md <<'PACK'
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
pack "$T/same/context-rules/repo" 10-once.md <<'PACK'
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
pack "$CFG/context-rules/user" 11-src.md <<'PACK'
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
rm -f "$CFG/context-rules/user/11-src.md"

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
pack "$REPO/context-rules/repo" 20-path.md <<'PACK'
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
# The prefilter drops a literal list's misses in awk (harbor#1508): whole names only, and a regex still reaches the grep.
t_eq "a literal tool list rejects a tool it does not name" "" "$(fire "$(tool_ev PreToolUse Read file_path /x/vault/a.md)")"
t_eq "a literal tool list rejects a name that only contains one" "" "$(fire "$(tool_ev PreToolUse NotebookEdit file_path /x/vault/a.md)")"
pack "$REPO/context-rules/repo" 25-rx.md <<'PACK'
---
id: rxtool
event: PreToolUse
tool: mcp__harbor_.*
when: path-contains vault/
once: never
---
RX-NOTE
PACK
t_has "a regex tool pattern still matches" "$(fire "$(tool_ev PreToolUse mcp__harbor_chrome__goto file_path /x/vault/a.md)")" RX-NOTE
t_eq "a regex tool pattern still rejects" "" "$(fire "$(tool_ev PreToolUse mcp__other__goto file_path /x/vault/a.md)")"
rm -f "$REPO/context-rules/repo/25-rx.md"
pack "$REPO/context-rules/repo" 30-multi.md <<'PACK'
---
id: multipred
event: PreToolUse
tool: Bash
when: cmd-prefix just corpus
when: repo-has context-rules/repo
once: never
---
MULTI-NOTE
PACK
pack "$REPO/context-rules/repo" 31-multi-fail.md <<'PACK'
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
pack "$REPO/context-rules/repo" 32-neg.md <<'PACK'
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
rm -f "$REPO/context-rules/repo/32-neg.md" "$REPO/context-rules/repo/31-multi-fail.md"

t_section "3 · a malformed pack is silent (skill-catalog's --chekc shape)"
pack "$REPO/context-rules/repo" 40-typo.md <<'PACK'
---
id: typo
event: PreToolUse
tool: Bash
when: cmd-prefx gh pr merge
once: never
---
TYPO-NOTE
PACK
pack "$REPO/context-rules/repo" 41-nowhen.md <<'PACK'
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
rm -f "$REPO/context-rules/repo/40-typo.md" "$REPO/context-rules/repo/41-nowhen.md"

t_section "3b · the five adversarial-pass defects, each pinned"
pack "$REPO/context-rules/repo" 42-negtypo.md <<'PACK'
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
rm -f "$REPO/context-rules/repo/42-negtypo.md"
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
pack "$REPO/context-rules/repo" 43-null.md <<'PACK'
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
rm -f "$REPO/context-rules/repo/43-null.md"
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
env -u CLAUDE_CONFIG_DIR -u CLAUDECODE sh "$T_ROOT/bin/context-injection-install.sh" --dir "$T/wired" --apply >/dev/null 2>&1
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
pack "$REPO/context-rules/repo" 50-once.md <<'PACK'
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
pack "$REPO/context-rules/repo" 51-match.md <<'PACK'
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
pack "$REPO/context-rules/repo" dyn.sh <<'PACK'
#!/bin/sh
[ -f MARKER ] && printf 'DYNAMIC-NOTE %s\n' "$(cat MARKER)"
exit 0
PACK
pack "$REPO/context-rules/repo" 60-run.md <<'PACK'
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
printf '#!/bin/sh\necho ESCAPE-RAN\n' > "$REPO/escape.sh"; cp "$REPO/escape.sh" "$REPO/context-rules/repo/inside.sh"
printf -- '---\nid: escaper\nevent: PreToolUse\ntool: Bash\nwhen: cmd-prefix make ship\nonce: never\nrun: %s\n---\n' ../../escape.sh \
  > "$REPO/context-rules/repo/61-escape.md"
gone "run: with .. is refused" "$(fire "$(bash_ev PreToolUse 'make ship')")" ESCAPE-RAN
sed 's|^run: ../../escape.sh$|run: inside.sh|' "$REPO/context-rules/repo/61-escape.md" > "$T/e.md" && mv "$T/e.md" "$REPO/context-rules/repo/61-escape.md"
t_has "the same script beside its pack does run (the needle can appear)" "$(fire "$(bash_ev PreToolUse 'make ship')")" ESCAPE-RAN
rm -f "$REPO/context-rules/repo/61-escape.md" "$REPO/context-rules/repo/inside.sh" "$REPO/escape.sh" "$REPO/context-rules/repo/60-run.md" "$REPO/context-rules/repo/dyn.sh" "$REPO/MARKER"

t_section "7 · provenance"
t_has "with no salt the note is unstamped and still fires" "$(fire '{"hook_event_name":"SubagentStart","session_id":"p1"}')" '[HARBOR GOVERNANCE]'
printf 'test-salt\n' > "$CFG/.helm-govern-salt"
_a="$(fire '{"hook_event_name":"SubagentStart","session_id":"p1"}')"; _b="$(fire '{"hook_event_name":"SubagentStart","session_id":"p2"}')"
t_has "with a salt the note carries a session token" "$_a" 'HARBOR GOVERNANCE '
t_eq "two sessions get different stamps" yes "$([ "$_a" != "$_b" ] && echo yes)"
rm -f "$CFG/.helm-govern-salt"

t_section "7 · every note starts [context:<id>] (harbor#957)"
pack "$CFG/context-rules/user" 12-ctx-a.md <<'PACK'
---
id: ctx-static
event: SessionStart
when: always
once: never
---
STATIC-BODY
PACK
pack "$CFG/context-rules/user" 13-ctx-b.md <<'PACK'
---
id: ctx-dynamic
event: SessionStart
when: always
once: never
run: ctx-b.sh
---
PACK
printf '#!/bin/sh\necho DYNAMIC-BODY\n' > "$CFG/context-rules/user/ctx-b.sh"
_c="$(fire '{"hook_event_name":"SessionStart","session_id":"c1"}')"
t_has "a static note leads with its own id" "$_c" '[context:ctx-static] STATIC-BODY'
t_has "a run: note leads with its own id" "$_c" '[context:ctx-dynamic] DYNAMIC-BODY'
rm -f "$CFG/context-rules/user/12-ctx-a.md" "$CFG/context-rules/user/13-ctx-b.md" "$CFG/context-rules/user/ctx-b.sh"

t_section "a run: pack can decide, and only where the harness can hear it (harbor#254)"
DEC="$T/dec"; mkdir -p "$DEC/context-rules/user"
pack "$DEC/context-rules/user" decider.sh <<'PACK'
#!/usr/bin/env sh
printf 'HARBOR-DECISION deny: the backstop refused, route via merge-check --merge\n'
PACK
pack "$DEC/context-rules/user" 90-decide.md <<'PACK'
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
sed 's/^event: PreToolUse$/event: PostToolUse/' "$DEC/context-rules/user/90-decide.md" > "$T/d.md" && mv "$T/d.md" "$DEC/context-rules/user/90-decide.md"
_d2="$(fire_cfg "$DEC" "$(bash_ev PostToolUse 'perilous thing' "d-$$")")"
t_hasnt "a deny on an event that cannot carry one is downgraded" "$_d2" 'permissionDecision'
t_has "and the text still arrives, as a note" "$_d2" 'route via merge-check --merge'
t_has "the downgraded note rides additionalContext" "$_d2" 'additionalContext'
sed 's/^event: PostToolUse$/event: PreToolUse/' "$DEC/context-rules/user/90-decide.md" > "$T/d.md" && mv "$T/d.md" "$DEC/context-rules/user/90-decide.md"
pack "$DEC/context-rules/user" 91-static.md <<'PACK'
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

t_section "2 · cmd-word: the command word, however it is spelled in front, and never an argument"
pack "$CFG/context-rules/user" 12-word.md <<'PACK'
---
id: word
event: PreToolUse
tool: Bash
when: cmd-word zzwrite
once: never
---
WORD-NOTE
PACK
for _c in 'zzwrite add x' 'cd /tmp && zzwrite add x' 'true; zzwrite add' 'echo a | zzwrite add' \
  'X=$(zzwrite add x)' 'D=/tmp E="a b" zzwrite add' '/opt/bin/zzwrite add' '~/.local/bin/zzwrite add'; do
  t_has "fires: $_c" "$(fire "$(bash_ev PreToolUse "$_c" "w-$$")")" WORD-NOTE
done
for _c in 'gh pr create --body "uses zzwrite add"' 'grep -rn zzwrite .' "sed 's/zzwrite/x/' SKILL.md" \
  'echo zzwrite' 'zzwrite-helper add' 'zzwrite --help' "git commit -m 'zzwrite; zzwrite add'" \
  "$(printf 'cat <<EOF\nzzwrite add\nEOF')"; do
  gone "silent: $_c" "$(fire "$(bash_ev PreToolUse "$_c" "w-$$")")" WORD-NOTE
done

t_section "the mode is the register's: shadow records and is silent, warn speaks, block decides (harbor#1422)"
# An installed layout, so the decision log has a sink: <cfg>/bin holds the engine, the library and the register copy.
ML="$T/modecfg"; mkdir -p "$ML/bin" "$ML/context-rules/user" "$ML/MEMORY/OBSERVABILITY/probehost"
cp "$SUT" "$T_ROOT/bin/library-admission.sh" "$ML/bin/"; printf 'probehost\n' > "$ML/.helm-obs-host"
: > "$ML/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; chmod 0500 "$ML/MEMORY/OBSERVABILITY/probehost"
MS="$ML/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"
printf '#!/bin/sh\nprintf "HARBOR-DECISION deny: the register said block\\n"\n' > "$ML/context-rules/user/modedeny.sh"
pack "$ML/context-rules/user" modenote.md <<'PACK'
---
id: mode-note
event: PreToolUse
tool: Bash
when: cmd-prefix modeprobe
once: never
---
MODE-NOTE-BODY
PACK
pack "$ML/context-rules/user" modedeny.md <<'PACK'
---
id: mode-deny
event: PreToolUse
tool: Bash
when: cmd-prefix modeprobe
run: modedeny.sh
once: never
---
PACK
modefire() { # <mode of mode-note> <mode of mode-deny> -> the engine's stdout, with the register copy rewritten first
  { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n'
    printf 'context.mode-note\t%s\tinjection\thooks/injection-rule/injection-rule.sh\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tmode-note\tx\n' "$1"
    printf 'context.mode-deny\t%s\tinjection\thooks/injection-rule/injection-rule.sh\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tmode-deny\tx\n' "$2"; } > "$ML/bin/controls.tsv"
  printf '%s' "$(bash_ev PreToolUse 'modeprobe now' "m-$$-$1-$2")" \
    | CLAUDE_CONFIG_DIR="$ML" CLAUDE_PROJECT_DIR="$REPO" sh "$ML/bin/injection-rule.sh" 2>/dev/null
}
: > "$MS"
_m="$(modefire warn warn)"
t_has "warn: the note is spoken" "$_m" MODE-NOTE-BODY
t_hasnt "warn: a run: pack's deny is a note, not a decision" "$_m" '"permissionDecision"'
t_has "warn: the downgraded deny still arrives as text" "$_m" 'the register said block'
t_eq "warn: nothing is logged as shadow" 0 "$(grep -c '"d":"shadow"' "$MS")"
: > "$MS"
_m="$(modefire shadow shadow)"
t_eq "shadow: the engine prints nothing" "" "$_m"
t_has "shadow: the note was recorded, as d=shadow" "$(cat "$MS")" '"d":"shadow"'
t_eq "shadow: one record per rule that would have spoken" 2 "$(grep -c '"d":"shadow"' "$MS")"
_m="$(modefire warn block)"
t_has "block: the deny is a real PreToolUse decision" "$_m" '"permissionDecision":"deny"'
rm -f "$ML/bin/controls.tsv"
_m="$(printf '%s' "$(bash_ev PreToolUse 'modeprobe now' "m-nore-$$")" | CLAUDE_CONFIG_DIR="$ML" CLAUDE_PROJECT_DIR="$REPO" sh "$ML/bin/injection-rule.sh" 2>/dev/null)"
t_has "no register at all: a deny is still honoured, as before" "$_m" '"permissionDecision":"deny"'

t_section "a run: pack may supply the person's line, at most one a session (harbor#1485)"
# An installed layout, so the ledger has a sink, the salt gives a session key and the claim is real.
UL="$T/linecfg"; UB="$UL/context-rules/user"; mkdir -p "$UL/bin" "$UB" "$UL/MEMORY/OBSERVABILITY/probehost"
cp "$SUT" "$T_ROOT/bin/library-admission.sh" "$UL/bin/"; printf 'probehost\n' > "$UL/.helm-obs-host"
UK=0123456789abcdef0123456789abcdef; printf '%s\n' "$UK" > "$UL/.helm-obs-salt"
US="$UL/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; : > "$US"; chmod 0500 "${US%/*}"
UI="$UL/state/inject"
# run: prints the file `out`; with `bar` present it first waits for a second caller, so two calls reach the claim together.
pack "$UB" line.sh <<EOS
#!/bin/sh
printf x >> "$UL/ran"
if [ -d "$UL/bar" ]; then
  : > "$UL/bar/\$\$"; i=0
  while [ "\$(ls "$UL/bar" | wc -l)" -lt 2 ] && [ "\$i" -lt 400 ]; do sleep 0.05; i=\$((i + 1)); done
fi
cat "$UL/out"
EOS
pack "$UB" line-spoke.sh <<EOS
#!/bin/sh
printf '%s|%s\n' "\$#" "\$*" >> "$UL/spoken"
echo SPOKE-NOISE
echo SPOKE-ERR >&2
exit 3
EOS
pack "$UB" 20-suggest-tool.md <<'PACK'
---
id: suggest-tool
event: PreToolUse
tool: Bash
when: cmd-prefix lineprobe
mode: notify
summary: THE-SUMMARY
run: line.sh
spoke: line-spoke.sh
---
PACK
ufire() { # <session> [command] -> the engine's stdout
  printf '%s' "$(bash_ev PreToolUse "${2:-lineprobe now}" "$1")" \
    | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" 2>/dev/null
}
uout() { printf '%s\n' "$@" > "$UL/out"; }            # what run: prints, one line per argument
umsg() { printf '%s' "$1" | jq -r '.systemMessage // empty'; }
unote() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
urec() { jq -c --arg r "$1" 'select(.r == $r)' "$US" | wc -l | tr -d ' '; }  # <ledger rule> -> how many records
uclaim() { [ -d "$UI/$1.seen.line" ] && echo claimed || echo free; }
uspoken() { cat "$UL/spoken" 2>/dev/null || true; }
ukey() { grep -qs suggest-tool "$UI/$1.seen" && echo spent || echo kept; }
ureset() { : > "$US"; rm -f "$UL/spoken" "$UL/ran"; }
uset() { sed "s|^$1:.*|$1: $2|" "$UB/20-suggest-tool.md" > "$T/u.md" && mv "$T/u.md" "$UB/20-suggest-tool.md"; }  # <key> <value>
usk() { if command -v sha256sum >/dev/null 2>&1; then printf '%s:sid:%s' "$UK" "$1" | sha256sum; else printf '%s:sid:%s' "$UK" "$1" | shasum -a 256; fi | cut -c1-16; }

ureset; uout 'HARBOR-USER-LINE row-a: The plain line.' 'The agent note,' 'on two lines.'
_u="$(ufire l1)"
t_eq "the sentinel's text is the person's line, and summary: gives way" 'harbor: The plain line.' "$(umsg "$_u")"
t_eq "the rest is the note, one paragraph, led by the pack id, the sentinel gone" \
  '[HARBOR GOVERNANCE] [context:suggest-tool] The agent note, on two lines.' "$(unote "$_u")"
t_eq "spoke: ran once with the row id as its one argument" '1|row-a' "$(uspoken)"
t_eq "the spoken line left one record under its row token" 1 "$(jq -c 'select(.r == "suggest-tool-row-a" and .d == "advise" and .g == "inject")' "$US" | wc -l | tr -d ' ')"
t_eq "the record carries the salted session key" "$(usk l1)" "$(jq -r 'select(.r == "suggest-tool-row-a") | .sk' "$US")"
t_eq "the claim is taken" claimed "$(uclaim l1)"
_u="$(ufire l1)"
t_eq "once: session: the second call is silent" "" "$_u"
t_eq "and the rule did not run again" x "$(cat "$UL/ran")"
t_eq "and spoke: did not run again" '1|row-a' "$(uspoken)"

# A session with the claim already gone: the state a parallel call leaves.
ureset; mkdir -p "$UI/l2.seen.line"
t_eq "a loser says nothing at all: the line is dropped and the note with it" "" "$(ufire l2)"
t_eq "a loser leaves no record" 0 "$(urec suggest-tool-row-a)"
t_eq "a loser does not run spoke:" "" "$(uspoken)"
t_eq "a loser spends its key, since no line can follow" spent "$(ukey l2)"

# Two calls past the once-ledger at the same moment, held there by the barrier in line.sh.
ureset; mkdir "$UL/bar"
ufire lrace > "$T/race1" & _p1=$!
ufire lrace > "$T/race2" & _p2=$!
wait "$_p1"; wait "$_p2"; rm -rf "$UL/bar"
t_eq "both parallel calls reached the rule" xx "$(cat "$UL/ran")"
t_eq "two parallel calls: one line" 1 "$(cat "$T/race1" "$T/race2" | grep -c systemMessage)"
t_eq "two parallel calls: one note" 1 "$(cat "$T/race1" "$T/race2" | grep -c additionalContext)"
t_eq "two parallel calls: one spoke:" 1 "$(uspoken | wc -l | tr -d ' ')"
t_eq "two parallel calls: one record" 1 "$(urec suggest-tool-row-a)"

t_section "the row id is held to the ledger's token rules, and a bad row is dropped whole (harbor#1485)"
_r27=abcdefghijklmnopqrstuvwxyz0; _r28=abcdefghijklmnopqrstuvwxyz01
ureset; uout "HARBOR-USER-LINE $_r27: The longest id." 'note'
t_eq "a 27-character id is a row" 'harbor: The longest id.' "$(umsg "$(ufire lmax)")"
t_eq "and its 40-character token reaches the ledger whole" 1 "$(urec "suggest-tool-$_r27")"
_n=0
for _bad in "HARBOR-USER-LINE $_r28: text" 'HARBOR-USER-LINE Upper: text' 'HARBOR-USER-LINE -lead: text' 'HARBOR-USER-LINE a_b: text' \
  'HARBOR-USER-LINE ../x: text' 'HARBOR-USER-LINE : text' 'HARBOR-USER-LINE nocolon text' 'HARBOR-USER-LINE nocolon' 'HARBOR-USER-LINE row-a: ' 'HARBOR-USER-LINE row-a:    '; do
  _n=$((_n + 1)); ureset; uout "$_bad" 'BADROW-NOTE'
  t_eq "bad row $_n, the whole output is dropped: $_bad" "" "$(ufire "lbad$_n")"
  t_eq "bad row $_n leaves no claim" free "$(uclaim "lbad$_n")"
  t_eq "bad row $_n runs no spoke:" "" "$(uspoken)"
  t_eq "bad row $_n is logged as a bad row, shadow, not spoken" 1 "$(jq -c 'select(.r == "suggest-tool--bad-row" and .d == "shadow")' "$US" | wc -l | tr -d ' ')"
done
ufire "lbad$_n" >/dev/null
t_eq "a bad row logs once a session, not on every tool call" 1 "$(urec suggest-tool--bad-row)"
t_eq "and it spends no pack key: the rule still runs" xx "$(cat "$UL/ran")"
ureset; printf 'HARBOR-USER-LINE row-a: A line with no note.\n' > "$UL/out"
t_eq "a sentinel with no note: nothing is shown" "" "$(ufire lnone)"
t_eq "and it is logged as a defect" 1 "$(urec suggest-tool--no-note)"
t_eq "and it leaves no claim, so the row can still speak" free "$(uclaim lnone)"
t_eq "and it runs no spoke:" "" "$(uspoken)"
ureset; uout 'HARBOR-USER-LINE row-a: A line.' "$(printf '\t \t')"
t_eq "a note of tabs is no note: nothing is shown" "" "$(ufire ltab)"
t_eq "and it is logged as a defect" 1 "$(urec suggest-tool--no-note)"
t_eq "and it leaves no claim, so the row can still speak" free "$(uclaim ltab)"
t_eq "and it runs no spoke:" "" "$(uspoken)"
ureset; uout 'note first' 'HARBOR-USER-LINE row-a: Second line.'
_u="$(ufire lsecond)"
t_eq "the sentinel counts only on the first line: summary: stands" 'harbor: THE-SUMMARY' "$(umsg "$_u")"
t_has "and that output is an ordinary note" "$(unote "$_u")" 'note first'
t_eq "and no spoke: runs for it" "" "$(uspoken)"
ureset; uout 'HARBOR-USER-LINE row-a: A line.' 'HARBOR-DECISION deny: not a verdict down here'
_u="$(ufire lnodeny)"
t_hasnt "a deny after the sentinel is not a decision" "$_u" permissionDecision
t_has "it stays note text" "$(unote "$_u")" 'not a verdict down here'

t_section "the line is honoured only from a box-tier mode: notify pack (harbor#1485)"
pack "$REPO/context-rules/repo" repo-line.sh <<'PACK'
#!/bin/sh
printf 'HARBOR-USER-LINE rowx: COMPUTED-TEXT\nREPO-NOTE\n'
PACK
pack "$REPO/context-rules/repo" repo-spoke.sh <<EOS
#!/bin/sh
: > "$UL/repo-spoke-ran"
EOS
pack "$REPO/context-rules/repo" 97-repo-line.md <<'PACK'
---
id: repo-line
event: PreToolUse
tool: Bash
when: cmd-prefix repolineprobe
mode: notify
summary: REPO-SUMMARY
run: repo-line.sh
spoke: repo-spoke.sh
---
PACK
ureset; _u="$(ufire lrepo repolineprobe)"
t_eq "a repo pack's sentinel falls back to summary:" 'harbor: REPO-SUMMARY' "$(umsg "$_u")"
t_hasnt "a repo pack's computed text reaches neither channel" "$_u" COMPUTED-TEXT
t_eq "the rest of its output is its note" '[HARBOR GOVERNANCE] [context:repo-line] REPO-NOTE' "$(unote "$_u")"
t_eq "a repo pack's stdout never names a ledger token" "0 1" "$(urec repo-line-rowx) $(urec repo-line)"
t_eq "a repo pack takes no claim" free "$(uclaim lrepo)"
t_eq "a repo pack's spoke: never runs" no "$([ -e "$UL/repo-spoke-ran" ] && echo yes || echo no)"
rm -f "$REPO/context-rules/repo/97-repo-line.md" "$REPO/context-rules/repo/repo-line.sh" "$REPO/context-rules/repo/repo-spoke.sh"
ureset; uout 'HARBOR-USER-LINE row-a: Unsaid.' 'INFORM-NOTE'; uset mode inform
_u="$(ufire linform)"
t_eq "a box pack without mode: notify shows no line" "" "$(umsg "$_u")"
t_eq "and is still a note, the sentinel gone" '[HARBOR GOVERNANCE] [context:suggest-tool] INFORM-NOTE' "$(unote "$_u")"
t_eq "and takes no claim" free "$(uclaim linform)"
t_eq "and runs no spoke:" "" "$(uspoken)"
uset mode notify
printf '#!/bin/sh\n: > "%s/idle-spoke-ran"\n' "$UL" > "$UB/idle-spoke.sh"
pack "$UB" 21-static-line.md <<'PACK'
---
id: static-line
event: PreToolUse
tool: Bash
when: cmd-prefix staticlineprobe
mode: notify
summary: STATIC-SUMMARY
spoke: idle-spoke.sh
---
HARBOR-USER-LINE row-a: prose about the mechanism, not a line.
PACK
_u="$(ufire lstatic staticlineprobe)"
t_eq "only run: output is inspected: a static body is prose" 'harbor: STATIC-SUMMARY' "$(umsg "$_u")"
t_has "and is delivered whole" "$(unote "$_u")" 'HARBOR-USER-LINE row-a: prose about the mechanism'
t_eq "spoke: on a pack with no run: is inert" no "$([ -e "$UL/idle-spoke-ran" ] && echo yes || echo no)"
rm -f "$UB/21-static-line.md" "$UB/idle-spoke.sh"

t_section "a later deny spends nothing, and shadow speaks nothing (harbor#1485)"
pack "$REPO/context-rules/repo" 98-line-deny.md <<'PACK'
---
id: line-deny
event: PreToolUse
tool: Bash
when: cmd-prefix lineprobe deny
run: line-deny.sh
once: never
---
PACK
printf '#!/bin/sh\nprintf "HARBOR-DECISION deny: refused later in the sweep\\n"\n' > "$REPO/context-rules/repo/line-deny.sh"
ureset; uout 'HARBOR-USER-LINE row-a: The plain line.' 'The agent note.'
_u="$(ufire ldeny 'lineprobe deny')"
t_has "the deny stands" "$_u" '"permissionDecision":"deny"'
t_hasnt "the line does not ride a deny" "$_u" systemMessage
t_eq "a deny spends no claim" free "$(uclaim ldeny)"
t_eq "a deny spends no once key" kept "$(ukey ldeny)"
t_eq "a deny writes no record of a line" 0 "$(urec suggest-tool-row-a)"
t_eq "a deny runs no spoke:" "" "$(uspoken)"
t_eq "so the next call in the session still speaks" 'harbor: The plain line.' "$(umsg "$(ufire ldeny)")"
printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\ncontext.suggest-tool\tshadow\tinjection\thooks/injection-rule/injection-rule.sh\t-\truntime\tpreventive\texperimental\t-\tcontext\t-\tsuggest-tool\tx\n' > "$UL/bin/controls.tsv"
ureset
t_eq "shadow: nothing is spoken" "" "$(ufire lshadow)"
t_eq "shadow: recorded under the row token" 1 "$(jq -c 'select(.r == "suggest-tool-row-a" and .d == "shadow")' "$US" | wc -l | tr -d ' ')"
t_eq "shadow: no claim" free "$(uclaim lshadow)"
t_eq "shadow: no spoke:" "" "$(uspoken)"
t_eq "shadow: the once key is spent, one record a session" spent "$(ukey lshadow)"
ureset; ufire lshadowdeny 'lineprobe deny' >/dev/null
t_eq "shadow: a later deny means it would not have spoken, so no record" 0 "$(urec suggest-tool-row-a)"
t_eq "shadow: and no key is spent" kept "$(ukey lshadowdeny)"
sed 's/\tshadow\t/\twarn\t/' "$UL/bin/controls.tsv" > "$T/c.tsv" && mv "$T/c.tsv" "$UL/bin/controls.tsv"
ureset; uout 'HARBOR-DECISION deny: HARBOR-USER-LINE row-a: smuggled' 'rest'
_u="$(ufire lwarn)"
t_eq "a deny downgraded to a note is not then read as a line" 'harbor: THE-SUMMARY' "$(umsg "$_u")"
t_eq "and runs no spoke:" "" "$(uspoken)"
rm -f "$UL/bin/controls.tsv" "$REPO/context-rules/repo/98-line-deny.md" "$REPO/context-rules/repo/line-deny.sh"

t_section "spoke: fails silent, and runs only after a line really left (harbor#1485)"
ureset; uout 'HARBOR-USER-LINE row-a: The plain line.' 'The agent note.'
_base="$(ufire lsp0)"
t_hasnt "a spoke: script's stdout never reaches the hook's answer" "$_base" SPOKE-NOISE
t_eq "and it ran, and exited 3, without changing the answer" '1|row-a' "$(uspoken)"
ureset; uset spoke ../outside-spoke.sh; printf '#!/bin/sh\n: > "%s/outside-ran"\n' "$UL" > "$UL/context-rules/outside-spoke.sh"
t_eq "spoke: with .. is refused, and the line still speaks" "$_base" "$(ufire lsp1)"
t_eq "the script past .. never ran" no "$([ -e "$UL/outside-ran" ] && echo yes || echo no)"
uset spoke "$UL/context-rules/outside-spoke.sh"
t_eq "spoke: with an absolute path is refused too" "$_base" "$(ufire lsp2)"
t_eq "the absolute script never ran" no "$([ -e "$UL/outside-ran" ] && echo yes || echo no)"
uset spoke no-such-spoke.sh
t_eq "a missing spoke: script changes nothing" "$_base" "$(ufire lsp3)"
t_has "and --explain names it" "$(printf '%s' "$(bash_ev PreToolUse 'lineprobe now' lsp3x)" | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" --explain 2>&1)" \
  'skip spoke suggest-tool: no-such-spoke.sh not found'
# The hook has 10 s (hooks/injection-rule/manifest.tsv). A hung spoke: is cut off, and the answer already made still leaves.
for _h in "plain|sleep 20" "ignores-term|trap '' TERM; i=0; while [ \"\$i\" -lt 25 ]; do sleep 1; i=\$((i + 1)); done"; do
  ureset; rm -f "$UL/hang-ran"
  printf '#!/bin/sh\n: > "%s/hang-ran"\n%s\n' "$UL" "${_h#*|}" > "$UB/hang-spoke.sh"
  uset spoke hang-spoke.sh
  _t0="$(date +%s)"; _ho="$(ufire "lhang-${_h%%|*}")"; _t1="$(date +%s)"
  t_eq "a hung spoke: (${_h%%|*}) did run" yes "$([ -e "$UL/hang-ran" ] && echo yes || echo no)"
  t_eq "...and the hook is back inside its 10 s" yes "$([ $((_t1 - _t0)) -lt 10 ] && echo yes || echo no)"
  t_eq "...with the line in its answer" 'harbor: The plain line.' "$(umsg "$_ho")"
done
uset spoke line-spoke.sh
mkdir -p "$T/jqstub"; printf '#!/bin/sh\ncase "$1" in -cn) exit 1 ;; esac\nexec "%s" "$@"\n' "$(command -v jq)" > "$T/jqstub/jq"; chmod +x "$T/jqstub/jq"
ureset
_u="$(printf '%s' "$(bash_ev PreToolUse 'lineprobe now' lsp4)" | PATH="$T/jqstub:$PATH" CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" 2>/dev/null)"
t_eq "an emit that failed leaves nothing on stdout" "" "$_u"
t_eq "an emit that failed runs no spoke:, since nothing was spoken" "" "$(uspoken)"
pack "$UB" 22-compact-line.md <<'PACK'
---
id: compact-line
event: PreCompact
when: always
mode: notify
run: line.sh
spoke: line-spoke.sh
---
PACK
ureset
_u="$(printf '%s' '{"hook_event_name":"PreCompact","session_id":"lsp5"}' | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" 2>/dev/null)"
t_eq "on an event with no model channel the line still leaves, alone" '{"systemMessage":"harbor: The plain line."}' "$_u"
t_eq "and spoke: runs for it" '1|row-a' "$(uspoken)"
rm -f "$UB/22-compact-line.md"

t_section "one line a sweep, beside whatever else speaks (harbor#1485)"
printf '#!/bin/sh\nprintf "HARBOR-USER-LINE row-b: The other line.\\nOTHER-NOTE\\n"\n' > "$UB/line-two.sh"
pack "$UB" 23-suggest-two.md <<'PACK'
---
id: suggest-two
event: PreToolUse
tool: Bash
when: cmd-prefix lineprobe
mode: notify
run: line-two.sh
spoke: line-spoke.sh
---
PACK
pack "$UB" 24-static-notify.md <<'PACK'
---
id: static-notify
event: PreToolUse
tool: Bash
when: cmd-prefix lineprobe
mode: notify
summary: A-STATIC-SUMMARY
---
STATIC-NOTIFY-NOTE
PACK
ureset; uout 'HARBOR-USER-LINE row-a: The plain line.' 'The agent note.'
_u="$(ufire lsweep)"
t_eq "two sentinel packs in one sweep: one line, and a plain notify pack keeps its summary" 'harbor: A-STATIC-SUMMARY; The plain line.' "$(umsg "$_u")"
t_hasnt "the second sentinel pack's note goes with its line" "$_u" OTHER-NOTE
t_has "a plain pack's note is untouched by the held line" "$(unote "$_u")" '[context:static-notify] STATIC-NOTIFY-NOTE'
t_eq "one spoke:, for the row that spoke" '1|row-a' "$(uspoken)"
rm -f "$UB/23-suggest-two.md" "$UB/24-static-notify.md" "$UB/line-two.sh"

t_section "no ledger, no line; --explain spends nothing; the claim is pruned (harbor#1485)"
ureset
_u="$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"lineprobe now"}}' | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" 2>/dev/null)"
t_eq "a call with no session id cannot claim, so it stays silent" "" "$_u"
t_eq "and it runs no spoke:" "" "$(uspoken)"
ureset
_u="$(printf '%s' "$(bash_ev PreToolUse 'lineprobe now' lexp)" | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" --explain 2>&1)"
t_has "--explain reports the fire" "$_u" 'FIRE suggest-tool'
t_has "--explain shows what would be said" "$_u" '"systemMessage":"harbor: The plain line."'
t_eq "--explain takes no claim" free "$(uclaim lexp)"
t_eq "--explain runs no spoke:" "" "$(uspoken)"
t_eq "--explain writes no record" 0 "$(urec suggest-tool-row-a)"
uout 'HARBOR-USER-LINE Bad: text' 'note'
printf '%s' "$(bash_ev PreToolUse 'lineprobe now' lexp2)" | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" --explain >/dev/null 2>&1
t_eq "--explain writes no defect record either" 0 "$(urec suggest-tool--bad-row)"
uout 'HARBOR-USER-LINE row-a: The plain line.' 'The agent note.'
mkdir -p "$UI/old.seen.line"; : > "$UI/old.seen"; mkdir -p "$UI/fresh.seen.line"
touch -t 202001010000 "$UI/old.seen.line" "$UI/old.seen"
ufire lprune >/dev/null
t_eq "a week-old claim is pruned with its ledger" "no no" "$([ -e "$UI/old.seen.line" ] && echo yes || echo no) $([ -e "$UI/old.seen" ] && echo yes || echo no)"
t_eq "a recent claim stays" yes "$([ -d "$UI/fresh.seen.line" ] && echo yes || echo no)"

t_section "every inject record carries the session key, and only that (harbor#1485)"
pack "$UB" 25-plain.md <<'PACK'
---
id: plain-rule
event: PreToolUse
tool: Bash
when: cmd-prefix skprobe
once: never
---
PLAIN-NOTE
PACK
: > "$US"
ufire lsk1 skprobe >/dev/null
t_eq "a plain pack's record has the session key" "$(usk lsk1)" "$(jq -r 'select(.r == "plain-rule") | .sk' "$US")"
: > "$US"
printf '%s' '{"session_id":"lsk2","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"skprobe"}}' \
  | CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" >/dev/null 2>&1
t_eq "whatever the payload's key order" "$(usk lsk2)" "$(jq -r 'select(.r == "plain-rule") | .sk' "$US")"
: > "$US"; mkdir -p "$T/mg"; : > "$T/mg/harbor-confinement"
printf '%s' '{"session_id":"lsk3","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"skprobe","dangerouslyDisableSandbox":true}}' \
  | HARBOR_SCOPE_MANAGED_SETTINGS="$T/mg/managed-settings.json" CLAUDE_CONFIG_DIR="$UL" CLAUDE_PROJECT_DIR="$REPO" sh "$UL/bin/injection-rule.sh" >/dev/null 2>&1
t_eq "the writer still reads no payload text: c stays what the marker says" confined "$(jq -r 'select(.r == "plain-rule") | .c' "$US")"
t_done
