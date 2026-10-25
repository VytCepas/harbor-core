#!/usr/bin/env sh
# repo-skills.sh (harbor#173 · A5) — name the repo-scoped skills a session
# CANNOT see. Run by hooks/injection-rule/injection-rule.sh at SessionStart with cwd = the session's
# repo and the hook payload on stdin, which it ignores.
#
# WHY ONLY THE HIDDEN ONES. A repo-scoped skill without the flag is already in
# the model's listing when its repo is the cwd — repeating it would be pure cost
# for a capability the session already has. `disable-model-invocation: true`
# removes a skill from that listing ENTIRELY, so the model cannot invoke it and
# will never learn it exists. That is the whole gap, and it is why the line below
# carries PATHS: a SKILL.md is a markdown file, so a path makes it readable even
# when it is unreachable.
#
# SILENT WHEN THERE IS NOTHING HIDDEN, which is the common case. An empty
# "here are your skills:" line is a false positive with extra steps.
set -eu

D=".claude/skills"
[ -d "$D" ] || exit 0

# The frontmatter ONLY. Scanning the body misfiles any skill whose prose mentions
# the key at column 0 — skill-book.sh records that exact defect.
fm() { awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
            NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
            NR>1' "$1"; }

out=''
n=0
for d in "$D"/*/; do
  f="$d/SKILL.md"
  [ -f "$f" ] || continue
  fm "$f" | grep -q '^disable-model-invocation:[[:space:]]*true' || continue
  name="$(basename "$d")"
  # THE TRIGGERS ARE THE PAYLOAD; THE PROSE IS NOT. Until 2026-08-28 this line
  # stripped `USE WHEN.*` and kept the "what it is" half — so the one mechanism
  # whose job is to make a hidden skill reachable deleted every trigger phrase
  # and shipped only abstract description. Measured that day: 0 occurrences of
  # `USE WHEN` across 11,412 B of injection, and 25 of the 27 vendored skills had
  # never been opened by any tool call in 600 sessions. `red-team` arrived as
  # "adversarial analysis deploying parallel expert agents" with "critique,
  # stress test, devil's advocate, break this, poke holes" cut off.
  # So: keep USE WHEN, drop the prose, fall back to the prose when a skill has no
  # triggers at all. Smaller AND matchable — the prose half is 9,483 B across the
  # roster and the trigger half is 7,556 B.
  _full="$(fm "$f" | awk '/^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); print; exit }' \
           | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//" -e 's/[[:space:]]*NOT FOR.*//')"
  desc="$(printf '%s' "$_full" | sed -n 's/.*\(USE WHEN.*\)/\1/p')"
  [ -n "$desc" ] || desc="$_full"
  out="$out $name (.claude/skills/$name/SKILL.md) — $desc;"
  n=$(( n + 1 ))
done

[ "$n" -gt 0 ] || exit 0

# THE ROOT IS DECLARED ONCE, AND THAT IS harbor#315 RE-DERIVED (harbor#462).
# #315 measured "24 paths of which 10 do not resolve" and read it as a broken
# affordance. The paths were never missing — this loop only emits a path it has
# just confirmed with `[ -f "$f" ]`, so it is structurally incapable of naming an
# absent file. They were UNROOTED: emitted relative to the directory the hook ran
# in, and resolved by a reader standing somewhere else. Re-measured 2026-09-06
# from cwd=$HOME, 36 of 36 resolve; from cwd=~/harbor, 0 of 36 do. Same paths,
# same box, same second.
#
# ONE DECLARATION, NOT 36 ABSOLUTE PATHS, and the arithmetic is the argument:
# absolutising every entry costs ~20 B x 36 on the single largest item in the
# SessionStart budget, which is the cost half of #315 and would make it worse to
# fix the correctness half. Naming the root once costs about 60 B total. It is
# also the same shape the constitution and the skills now use — `**Path root:**`
# — so there is one convention on this box rather than one per surface.
#
# ABSOLUTE, because the Read tool refuses a relative path outright: a pointer the
# reader cannot pass to the tool that reads it is not a pointer. This is session
# context, not public-destined output, so CONSTITUTION §3's rule against quoting
# absolute ~/.claude paths outward is not in play.
printf 'This repo carries %d skill(s) you cannot see and cannot invoke — they are hidden from your listing by design, and only the operator can run them by name. You CAN read them, and the path is the point — every path below is relative to %s, so resolve it there and not against your own cwd:%s Read one when its subject is the task in front of you.\n' \
  "$n" "$(pwd -P)" "${out% }"
