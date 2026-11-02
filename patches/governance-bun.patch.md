# Operator patch — CI must stop skipping 56 assertions on a box that has bun (harbor#165)

**STATUS: APPLIED by the operator on 2026-08-07**, in `095812e` (merged as
`04a5661`, PR #168). An agent cannot write into `.github/workflows/**` at all —
`permissions.deny` covers it deliberately, because that deny is what stops an
agent rewriting the gate that judges it. That held under test: `Edit`, and then
`git add`/`git commit` of this path, were both refused.

**The 56 assertions now run in CI.** First run after applying, `manifest suites`
job:

```
Run echo "$HOME/.bun/bin" >> "$GITHUB_PATH"
  HARBOR_REQUIRE_BUN: 1
── the Bun engine assertions, folded into one ──
    memory-engine.test: 56 passed, 0 failed
memory-test: 50 passed, 0 failed
```

No `SKIPPED the engine assertions` line, and the suite total stayed at 50 — the
host-count-stability claim in `bin/memory-test.sh:15-19` held rather than being
assumed. Their first green in CI is new information, not a formality: they had
never executed there.

## The defect

Run `31128495190` on `main` at `d172a2f`, all 11 jobs green, job
`manifest suites`:

```
2026-08-06T21:51:11Z ── the Bun engine assertions, folded into one ──
2026-08-06T21:51:11Z memory-test: SKIPPED the engine assertions (no bun on PATH; set HARBOR_REQUIRE_BUN=1 to make this fatal)
```

The runner is the operator's own Mac and bun is installed on it:

```
$ command -v bun
$HOME/.bun/bin/bun
```

The runner **service** resolves a different `PATH` than a login shell, and
`~/.bun/bin` is not in it. So the ladder in `bin/memory-test.sh:15-19` behaved
exactly as designed — and the box description it acted on was wrong.

What is lost is **56 assertions**. Measured locally on the same tree:

```
$ sh bin/memory-test.sh                       # bun on PATH
    memory-engine.test: 56 passed, 0 failed
memory-test: 50 passed, 0 failed

$ env PATH="/usr/bin:/bin:/usr/sbin:/sbin" sh bin/memory-test.sh    # the runner's condition
memory-test: SKIPPED the engine assertions (no bun on PATH; …)
memory-test: 50 passed, 0 failed
```

Note both report **50**. That is the host-count-stability the file's header
claims, working — and it is also why the skip was invisible: no count moves, no
job turns red, nothing in the summary changes.

`HARBOR_REQUIRE_BUN=1` exists precisely to catch this, per the same header:

> the skip is printed loudly rather than swallowed, and `HARBOR_REQUIRE_BUN=1`
> converts it into a failure — which is how CI on a box that IS supposed to have
> bun finds out that it does not, instead of quietly testing less.

`git grep -n HARBOR_REQUIRE_BUN` returns four hits, **all inside
`bin/memory-test.sh` itself**. Nothing sets it. The mechanism has no caller.

## The fix

Two additions to the `suite-manifest` job. Nothing else in the file changes.

First, a step before `run manifest suites with no dedicated job`:

```yaml
      # THE RUNNER SERVICE'S PATH IS NOT A LOGIN SHELL'S. bun installs itself to
      # ~/.bun/bin, which the launchd environment does not carry, so every suite
      # that degrades without bun degraded silently on a box that has it —
      # bin/memory-test.sh skipped 56 engine assertions and still reported green
      # (harbor#165). $GITHUB_PATH is the documented way to extend PATH for the
      # steps that follow, and it fixes this for every suite rather than for one.
      - name: Put bun on PATH (self-hosted only; the hosted image has none)
        if: runner.os == 'macOS'
        run: echo "$HOME/.bun/bin" >> "$GITHUB_PATH"
```

Second, on the `run manifest suites with no dedicated job` step:

```yaml
      - name: run manifest suites with no dedicated job
        env:
          # A SKIP MUST NOT BE SILENT ON A BOX THAT IS SUPPOSED TO HAVE BUN. Set
          # only for macOS: ubuntu-latest carries no bun, and the
          # `runner: github-hosted` dispatch option must stay usable, so making
          # this unconditional would turn a working leg red for a dependency it
          # was never expected to have.
          HARBOR_REQUIRE_BUN: ${{ runner.os == 'macOS' && '1' || '' }}
        run: |
```

An empty value is not `1`, and `memory-test.sh` reads
`${HARBOR_REQUIRE_BUN:-0}`, so the hosted leg is unaffected.

## Do them in that order, in one commit

`HARBOR_REQUIRE_BUN=1` without the `PATH` step turns the run **red** rather than
quiet — the correct direction, and a bad thing to discover during an incident.
Verified:

```
$ env PATH="/usr/bin:/bin:/usr/sbin:/sbin" HOME=<a home with no .bun> \
      HARBOR_REQUIRE_BUN=1 sh bin/memory-test.sh
  FAIL: HARBOR_REQUIRE_BUN=1 but no bun on PATH — the engine assertions did not run
memory-test: 49 passed, 1 failed        (exit 1)
```

And with both halves in place, which is what the patch produces:

```
$ env PATH="/usr/bin:/bin:/usr/sbin:/sbin" HARBOR_MEMORY_BUN="$HOME/.bun/bin/bun" \
      sh bin/memory-test.sh
    memory-engine.test: 56 passed, 0 failed
memory-test: 50 passed, 0 failed
```

`HARBOR_MEMORY_BUN` is the equivalent single-variable form — `bin/memory.sh:142`
and `bin/memory-test.sh:70` both honour it, so tool and suite cannot disagree.
Either shape works; the `$GITHUB_PATH` one is preferred because it also serves
any future suite that looks for bun by name.

## Why NOT preflight, and why NOT a code fallback

**Not preflight.** Adding `bun` to the `for t in …` loop at `governance.yml:119`
would fail the `github-hosted` leg, which has no bun and is not supposed to.
Rule **C4** would stay satisfied — `bin/deploy-doctor.sh:59` already probes bun — but
the loop is a hard failure for every runner, and bun is `optional` by design:
the security floor is deliberately zero-Bun.

**Not a `~/.bun/bin` fallback in the code.** Tried and reverted while filing
this. Adding the fallback to `bin/memory-test.sh` alone made the **suite** believe
the host had bun while `bin/memory.sh`, the tool under test, still resolved it
from `PATH` and answered on the grep rung:

```
  FAIL: top rung reports its tier: want [bm25] got [grep]
  FAIL: top rung best hit: want [bm25-rare-term] got [null]
```

That is the suite correctly reporting that its host model and the tool's had
diverged — a worse defect than the skip, and a louder one. A refusal comment now
sits at that line so the next reader does not repeat it. If a code-level fallback
is ever wanted it has to go in **both** halves, or in neither.

## After applying

| Check | Expect |
|---|---|
| the `manifest suites` job log | `memory-engine.test: 56 passed, 0 failed`, and **no** `SKIPPED the engine assertions` line |
| `memory-test`'s own total | still `50 passed` — the folded assertion is what makes the count host-stable, and that claim should be re-verified rather than assumed |
| a `runner: github-hosted` dispatch | still green, still skipping, no `HARBOR_REQUIRE_BUN` failure |

**The failure to watch for** is the engine assertions running and *failing* — they
have never executed in CI, so their first green there is new information, not a
formality.
