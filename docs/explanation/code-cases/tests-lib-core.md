---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Notes moved out of tests/lib/core.sh

On-demand. Comment blocks moved here verbatim when the file header was cut to the 8-line budget (harbor#1392, harbor#1437). The code keeps the short form; the history is here and in git.

## tests/lib/core.sh, the header (before this edit)

```text
t_init also bounds the run by its own hand (harbor#1437): a suite run as `sh tests/x/y.test.sh` skips
bin/test-suite-run.sh, and one hung 14h40m at 0% CPU on a child that never returned. The limits are the runner's:
HARBOR_TEST_SUITE_TIMEOUT seconds with no progress (a section, a pass or a fail; default 900, 0 = none) and
HARBOR_TEST_SUITE_HARD_TIMEOUT in all (default 4x that, 0 = none). Past either the suite's descendants are
killed and it exits 124. No timeout(1): it is not on BSD.
```
