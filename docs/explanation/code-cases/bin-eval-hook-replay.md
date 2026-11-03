---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/eval-hook-replay.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/eval-hook-replay.sh, lines 11-31 (before this edit)

```text
THE QUESTION THIS ANSWERS, AND WHY IT IS THE ONE THAT DECIDES ADOPTION.
CONSTITUTION §2.11: a false positive is a defect, not safety — a guard that
fires on ordinary work gets switched off, and a disabled guard protects
nothing. Every argument for injecting a rule at the moment it applies is void
if "the moment it applies" turns out to be most moments. That is not
answerable from a unit test, because a unit test contains exactly the cases
its author thought of. It is answerable from history, and harbor has history.

THREE REPLAYS, EACH AGAINST ITS OWN REAL TRAFFIC. A hook is judged by the
stream it actually sits in, and the three hooks sit in three different ones:
  commit-msg   every commit message on the base branch
  pre-push     every commit's changeset, through the selector the hook uses
  govern-hook  every Bash command in the transcript store
Replaying commits through the merge hook would be a category error — it fires
on a command, not on a commit — and getting that wrong would produce a
confident number about nothing.

READ-ONLY. It writes no file and mutates no repo. It reads the transcript
store, which is private: only counts are reported in full, and a command is
printed only when it FIRES, truncated, because a fire is the thing a human has
to adjudicate and the other 10,000 are not.
```

## bin/eval-hook-replay.sh, lines 34-40 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/eval-hook-replay.sh, lines 50-50 (before this edit)

```text
die <what failed> <fix> <exit> — FAIL, its fix, the summary, the exit code the tool always had.
```

## bin/eval-hook-replay.sh, lines 66-68 (before this edit)

```text
════════════════════════════════════════════════════════════════════════════
SELF-TEST — a measurement tool that cannot be wrong is a tool nobody checked.
════════════════════════════════════════════════════════════════════════════
```

## bin/eval-hook-replay.sh, lines 71-75 (before this edit)

```text
The pre-filter below excludes any command with no 'merge' substring, on the
grounds that govern-hook's matcher requires the literal phrase 'pr merge'.
That is the one claim in this file that could silently drop real fires, so
it is asserted rather than argued: a command the filter excludes must also
be one the hook does not fire on.
```

## bin/eval-hook-replay.sh, lines 95-97 (before this edit)

```text
════════════════════════════════════════════════════════════════════════════
T0a · commit-msg against every real commit message
════════════════════════════════════════════════════════════════════════════
```

## bin/eval-hook-replay.sh, lines 112-115 (before this edit)

```text
EVERY FIRE HERE IS FOR A HUMAN TO ADJUDICATE, and this tool deliberately does
not adjudicate for them. The hook's pattern IS the definition of a violation,
so a second regex asking "but was it REALLY a trailer?" would be the same
judgement wearing a machine's clothes.
```

## bin/eval-hook-replay.sh, lines 119-121 (before this edit)

```text
════════════════════════════════════════════════════════════════════════════
T0b · the pre-push gate against every real changeset
════════════════════════════════════════════════════════════════════════════
```

## bin/eval-hook-replay.sh, lines 148-150 (before this edit)

```text
════════════════════════════════════════════════════════════════════════════
T0c · the govern-hook matcher against every real Bash command
════════════════════════════════════════════════════════════════════════════
```

## bin/eval-hook-replay.sh, lines 156-169 (before this edit)

```text
ONE COMMAND PER LINE, AS A READY-MADE HOOK PAYLOAD. jq emits the compact
envelope directly, so a command containing newlines stays ONE record — its
newlines are escaped inside the JSON string. Extracting raw command text
and counting lines would have inflated the denominator with every heredoc
and every multi-line script in the store, which makes the fire RATE look
better than it is: the flattering direction, and therefore the one to be
suspicious of.

THE PRE-FILTER IS PROVABLY EQUIVALENT, NOT A SAMPLE. The hook's matcher
requires a segment whose first word is `gh` and which contains the literal
`pr merge`, so a command with no `merge` substring anywhere cannot fire.
`--self-test` asserts that rather than asking to be believed, and both
sides of the split are printed — a cap that is not reported reads as full
coverage.
```
