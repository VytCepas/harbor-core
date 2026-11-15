---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of bin/ci-lost-job.sh

On-demand. Comment blocks that told the story of a fix, moved here verbatim when the file's comment ratio was cut (harbor#1392). The code keeps 1-3 lines of why; the history is here and in git.


## bin/ci-lost-job.sh, lines 24-35 (before this edit)

```text
WHY. GitHub cancels a queued job it could not dispatch and annotates the check
run "The job was not acquired by Runner of type self-hosted even after multiple
attempts". The job has no runner, no steps and no log, so `gh pr checks` scores
it like any other red check. Measured 2026-09-17..24: 8 such jobs in 1,257,
spread over every kind of job, each read as a failing suite until somebody
opened the annotation. Re-running it is a repair with no judgment in it; the
read that tells the two apart is this one, and it lives in one place so
gate-pr-wait.sh and gate-merge-check.sh cannot drift apart on the phrase.

EVERY ANNOTATION, NOT ANY. A job that ran, failed and was ALSO annotated is a
failure first; calling it lost would send someone to re-run a real red. Zero
annotations is not lost either — that is the ordinary shape of a failed step.
```

## bin/ci-lost-job.sh, lines 72-76 (before this edit)

```text
`--job`, NOT `--failed` (Codex on #692): gh defines --failed as "only failed
jobs", and a lost job is CANCELLED — so --failed could leave it untouched and
re-run an unrelated real failure instead. The link's /job/<id> is the job's
databaseId, which is what --job takes; gh's warning is about the /jobs/<n>
step URL, which the parser above never accepts.
```
