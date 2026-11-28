---
order: 68
description: Writing Lithuanian text names the Lithuanian sentence rules and the skill that holds them
event: PreToolUse
tool: Bash|Write|Edit|mcp__claude_ai_Claude_Docs__batch|mcp__claude_ai_Claude_Docs__update
when: always
run: lithuanian-prose.sh
once: never
---

<!--
harbor#1572, decided 2026-11-18: the operator's Lithuanian style is fundamental, not a mail-only rule. A colleague's
verdict on a correct reply was "perkrauti, krūva šnekamojoj kalboj nenaudojamų žodžių" (2026-09-04);
the rules that answer it live in skills/doc-lithuanian-prose, which is invoked-only so it costs no
listing bytes. Prose in a skill does not bind and a note at the call does (docs/reports/evals.md E6),
so this note rides every call whose input carries Lithuanian text: six or more Lithuanian-only
letters, which a name in an English sentence does not reach. It tells the agent to run the text
through bin/doc-lithuanian-rewrite.sh (Haiku or Sonnet, kept only when every protected token
survives). The operator asked 2026-11-18 for the hook to have a model rephrase what it catches;
it informs rather than rewriting the input itself, because the engine carries inform and deny
only and hub hooks drop updatedInput by design (bin/member-dispatch.sh, F14/F22). `once: never`
because the script keeps its own per-session ledger: the first note carries the rules, the rest
are one line. Silent on the call that runs the rewrite.
Disable: delete this file and its script, then `harbor inject --live --apply`.
-->
