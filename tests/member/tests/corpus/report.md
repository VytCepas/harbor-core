# member.tests calibration (harbor#1278)

Corpus: `dev.jsonl` (39 rows, written while the path classes were being decided) and `holdout.jsonl` (30 rows, written afterwards, each with a
name or shape the dev set lacks; not read for errors until the hook was done). Invented names only, no client data; a home path is written
`/home/someone/`, `/Users/someone/` or `/home/other/`. Fields: `before` (files committed), `dirty` (dirty at the prompt), `touched` (writes in
the turn, `path:lines`), `commit`, `registered`, `outside` (writes outside the project), `should_block`, `arch`, `why`.
Measure: `sh tests/member/tests/measure.sh [--set dev|holdout|all] [--errors]`. It runs the hook as a laptop does (`env -i`, PATH `/usr/bin:/bin`)
over a scratch git repo it builds per row. It needs a place where `.github/` and `.env` can be written (not the Claude sandbox) and says so.

## Labels (the law's intent, set before measuring)
- `should_block`: code in a registered project changed in the turn (by any writer, committed or not) and no test or fixture path changed.
- Not blocked: docs, notes, data, settings, lock files, build recipes, dependency and build folders, editor folders, a project that is not
  registered, a write outside the project, a code file that was dirty at the prompt and untouched since.
- `arch`: `trivial` for one code file under 20 changed lines, `full` for the rest.

## Measured (all 83 rows: dev 39, holdout 30, audit 14)
| | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|
| send back, dev (39) | 12 | 0 | 0 | 27 | 100% | 100% |
| send back, all (83) | 33 | 0 | 0 | 50 | 100% | 100% |
| architecture named, rows that block | 32 of 33 | | | | 97.0% | |

`audit.jsonl` (14 rows) was added after an independent audit and its labels were written from what a colleague's project needs, before the
classifier's output on them was read: a SQL model with and without its schema.yml, a notebook, a pure rename (also committed in the turn), a rename
with 5 lines changed, a deleted test beside new code, a deleted code file, a deleted test alone, two Apps Script files, a schema.yml alone, a README and a data file inside tests/ beside new code (neither is a test written: a test path counts only with a code extension). Row d36
was relabelled the same way (a schema file beside a changed model is its test).
The one architecture miss is n05: a rename with 5 changed lines is sized by the whole file, so it names `test-writing` where the label says trivial.
Floors in the suite: precision 95, recall 95, architecture 90, a few points under the measured numbers. Three planted defects (no test class, no
once-only guard, Python not code) each take the suite red, and the git-safety cases (suite section 7) are each red with the helper swapped for plain git.

Known limits, deliberate: a notebook's cells are not read, only its file; "trivial" is one code file under 20 changed lines, not a judgement of
interfaces; a rename that is also edited is sized by the whole file.
