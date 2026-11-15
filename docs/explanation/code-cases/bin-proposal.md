---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/proposal.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/proposal.sh, lines 12-49 (before this edit)

```text
THE INVERSION THIS FILE IS BUILT ON: A REVIEWER MAY VETO, NEVER APPROVE. The
request that produced it was the opposite — let an independent subagent bless a
change so the human gate can be skipped — and that direction cannot be made
safe here. An LLM reviewer is a RULE, and this estate has already measured that
rules do not bound an agent that can act: an `ask` verdict auto-approves off the
main loop, and the standing conclusion was "the mitigation is identity, never a
rule". A reviewer that can widen `permissions.deny` is an agent granting itself
permission by convincing another instance of itself. Harbor also carries the
receipt: pass 9's confidently-applied fixes caused ~24 defects that pass 10
found, WITH A GREEN SUITE THROUGHOUT — a reviewing agent would have read that
same green suite.

So a review can only ever REMOVE a packet from the queue. There is deliberately
no `--approve` flag and no "approved" state: a packet is `pending` until a
human runs `apply --apply`, and an unrefuted packet is UNREFUTED, never
approved. The failure mode of a broken or captured reviewer is therefore a
missed improvement, never a self-granted permission.

A REVIEW IS A SIGNATURE OVER THE PATCH BYTES, not over the packet name. Each
verdict records the sha256 of `patch.diff` as reviewed; `apply` recomputes it
and ignores every verdict for a different digest. Without that, "reviewed" is a
label on a directory whose contents can be swapped afterwards — which is the
whole attack this design would otherwise invite.

THE TIER IS COMPUTED FROM THE PATCH, NEVER DECLARED. A packet that names its
own risk level is a claim written by the thing being judged. `apply` classifies
the touched paths itself, every time, and floor-adjacent paths need `--floor`
typed by the operator on top of `--apply`.

THE PACKET MACHINERY IS UNPATCHABLE FROM A PACKET. A diff touching this file or
its suite is refused outright, at `new` and again at `apply`, with no flag that
overrides it. Everything else here is a gate a human chooses to pass; that one
is the hinge they all hang on.

IT IS NOT WIRED TO ANYTHING. No hook, no launchd job, and nothing in this repo
calls `apply`. Generating and reviewing are safe to automate; ingesting is the
human act, and automating the last step would delete the property the first two
exist to protect.
```

## bin/proposal.sh, lines 52-58 (before this edit)

```text
--help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
so it is the first executable line: a --help that reaches an argument parser is
a --help that a script with no parser ignores, and this file had none. Measured
2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
one script treated the flag as a request to do work, and five of the scripts
with no --help at all are mutators. The text is the header, read out of THIS
file at runtime, so a help message cannot drift from what the script says it is.
```

## bin/proposal.sh, lines 90-93 (before this edit)

```text
Floor-adjacent: allowed, but only when the operator types --floor as well. The
linter is in this list on purpose — a packet that exempts itself from a lint
rule is the same self-granting shape as one that edits its own reviewer, one
indirection further out.
```

## bin/proposal.sh, lines 101-115 (before this edit)

```text
EVERY SIDE OF EVERY CHANGE SHAPE, and this is not defensive padding — the
first version read `+++ b/` alone and TWO ATTACKS WALKED THROUGH IT, both
reproduced 2026-08-13 against a fixture repo:

  · a patch that DELETES bin/proposal.sh has `+++ /dev/null` and its only
    mention of the file is on the `---` side, so the machinery gate saw a
    0-file "ordinary" packet. Deleting the reviewer is at least as powerful as
    editing it, and that is the one gate with no override.
  · a pure RENAME (`bin/guard-x.sh` -> `bin/harmless.sh`) carries NO `+++` line
    at all — only `rename from`/`rename to` — so a floor file could be moved
    out of the floor tier with no --floor typed.

So both sides are read, plus the rename pair, `/dev/null` is dropped, and git's
quoted form (`--- "a/x y"`) is unquoted — an unquoted parse would make a path
with a space invisible to both classifiers.
```

## bin/proposal.sh, lines 146-152 (before this edit)

```text
UNTRACKED FILES ARE REFUSED, NOT SILENTLY DROPPED. `git diff HEAD` sees only
tracked content, so a change that ADDS a file produces a patch missing that
file entirely — and the packet then reads as "the change" while carrying part
of it. Measured the first time this ran against a real working tree: a packet
was created from a 7-file diff whose two new scripts were not in it, including
the one the machinery gate exists to catch. Refusing is side-effect-free;
`git add -N` is one command and makes the intent explicit in the index.
```

## bin/proposal.sh, lines 168-177 (before this edit)

```text
EVIDENCE IS EXPLICIT, AND STDIN IS NEVER READ UNLESS ASKED FOR. The first
version read stdin whenever it was not a tty, and that BLOCKS FOREVER on an
open-but-silent pipe — measured 2026-08-13: the same command took 4 seconds
under `(sleep 4) | …` and would hang indefinitely under a scheduled or
piped caller. `[ -t 0 ]` answers "is this a terminal", never "does data
follow", and no read can tell an empty pipe from a slow one.

ABSENCE IS RECORDED, not defaulted to something reassuring: an empty
evidence file reads as "none was offered", which is what a reviewer and the
operator both need to see stated.
```

## bin/proposal.sh, lines 303-308 (before this edit)

```text
A dirty tree makes `git apply` unrevertable by inspection: the operator can
no longer tell what the packet did from what they were already doing.
EXCLUDING THE PACKET STORE, which is the one thing that is always modified
here: `new` and `review` write into proposals/ by design, so counting it as
dirt would make every packet unappliable the moment it was reviewed — a gate
that blocks the ordinary path, which §2.11 calls a defect rather than safety.
```
