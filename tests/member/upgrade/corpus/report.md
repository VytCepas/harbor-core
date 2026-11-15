# member.upgrade calibration (harbor#1278)

Corpus: `dev.jsonl` (80 rows, the set the hook was tuned on) and `holdout.jsonl` (61, written before any tuning and not read for errors until the
hook was done; one rule, the 25-word floor, was simplified after its errors showed). 141 rows, 82 English and 59 Lithuanian, invented
names, no client data. Fields: `reply`, `tools`, `lang`, `should_upgrade`, `decides`, `why`, plus `id` and `ambiguous`.
Measure: `sh tests/member/upgrade/measure.sh [--set dev|holdout|all] [--clean] [--errors]`. It runs the hook as a laptop does (`env -i`, PATH `/usr/bin:/bin`).

## Labels (the law's intent, set before measuring)
- `should_upgrade`: the turn used a tool and the answer reports real work (analysis, change, diagnosis, report) and has no `Upgrade:` line. A
  question back after lookups, a refusal, a progress note, a how-to or explanation after one Read, and an answer that already carries the line are false.
- `decides`: a recommendation, a verdict (done, fixed, passes, fails), an exists or missing claim, a figure given as a finding, or a draft that leaves the
  session. False: how-to steps, explanations, quoted figures or dates, questions, refusals, progress notes.
- Clause 2 is expected when `decides` is true and no Agent or Task ran. `ambiguous` marks the rows a person should judge (33 of 141).

## Before and after (all 141 rows)
| | TP | FP | FN | TN | precision | recall |
|---|---|---|---|---|---|---|
| clause 1, before | 29 | 16 | 40 | 56 | 64.4% | 42.0% |
| clause 1, after | 69 | 7 | 0 | 65 | 90.8% | 100% |
| clause 2, before | 10 | 5 | 65 | 61 | 66.7% | 13.3% |
| clause 2, after | 65 | 12 | 10 | 54 | 84.4% | 86.7% |
| decides regex alone, before | 40 | 14 | 42 | 45 | 74.1% | 48.8% |
| decides regex alone, after | 74 | 26 | 8 | 33 | 74.0% | 90.2% |

Held-out 61 rows, before then after: clause 1 71.4/34.5 to 87.9/100, clause 2 66.7/6.1 to 81.8/81.8, regex alone 77.3/45.9 to 72.1/83.8 (precision/recall, %).
Without the 33 ambiguous rows (108 left): clause 1 70.3/41.9 to 95.4/100, clause 2 71.4/15.9 to 96.6/90.5, regex alone 81.4/50.0 to 83.1/91.4.

"Regex alone" pads the answer past the length gate with one non-writing tool and no agent, so it judges the pattern with none of the exemptions.
It trades 12 more false alarms for 34 more catches; the exemptions (question back, refusal, status, single lookup) are what keep clause 2 at 84% precision.

## What changed
- Length gate: 40 words became 25 (or any answer after two or more runs or edits, so "Done." after four edits is caught). Most real answers in the corpus are 24 to 39 words; the old gate missed 40 of 69.
- A single Read, Grep, Glob or web lookup is not work. A question back after lookups only, a refusal opener and a status opener ("Still running", "Progress:") owe nothing; a question after a run or edit does not excuse it.
- Upgrade line: `**Upgrade**:`, `upgrade:`, a heading or bullet marker now count.
- "Decides": many more triggers (Lithuanian first-person past and imperative endings, "nėra", "siūlau", figures with euro or dollar signs, metric names with a figure, sentence-start imperatives like Pause, Remove, Use) and a short list of benign phrases removed first ("how it works", "you should see", "fixed budget", "when done", "if it fails").
- Regexes run under `LC_ALL=C` so behaviour does not depend on the member's locale (`eur\b` matched "eurų" only in C).
- Floors in the suite (a few points under measured): clause 1 precision 85 and recall 95; clause 2 precision 80 and recall 82; regex alone 70 and 85. Proven red with the old regex (recall 42 and 48) and with `[a-z]` (precision 73 and 58).

## Ambiguous, where a person should decide
- Progress or status told as a result ("The first batch is done and the second is running"; "waiting for your approval"): the regex sees `done`.
- Figures quoted or summarised with no decision (a campaign's budget, a document's deadline, an inbox summary): the euro or percent figure fires clause 2.
- Diagnoses and fixes in plain words ("the tag is paused", "same table as before", "63 of 63 pass"): no trigger, so clause 2 misses them. Only a reader can tell a finding from a description.
- A question that also reports ("No campaign was found. Which one?") after a run: the run stops the question exemption; arguably it should not.
- Answers with no tool call that recommend (chat advice): the hook never checks them, by the old design; the law's §2 says every deciding answer. Operator's call.
- Real but short single-query answers ("Yesterday there were 4,210 sessions"): treated as a lookup, no Upgrade line.
- Labels were written by one person (the agent that tuned the hook); the same hand wrote the corpus and the rules, so expect lower real-world numbers than these.
