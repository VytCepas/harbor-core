# Operator patch — make CI read `contracts/suites.txt` (harbor#61)

**STATUS: OBSOLETE (2026-10-14).** The one-pool workflow (harbor#679) runs every line of `contracts/suites.txt` through `bin/test-suite-run.sh`, and the per-suite jobs this file proposed to sit beside no longer exist. `grep -c suite-manifest .github/workflows/governance.yml` prints 0. Kept for its measurements; nothing in it applies to the current workflow.

**Why this is a file and not a commit.** `permissions.deny` covers
`.github/workflows/**`, deliberately: that deny exists so an agent cannot rewrite
the gate that judges it. This is the one edit in the C3 change that an agent must
not make, so it is prepared here for you to apply by hand. That round-trip,
performed **once**, is what removes it for every future suite.

## What is already landed

- `contracts/suites.txt` — the tracked, agent-editable suite list.
- Rule **C3** now checks the manifest in both directions: every `bin/*-test.sh`
  appears in it, and every line in it names a file that exists.
- C3 also refuses to accept the manifest as decoration. Until `governance.yml`
  reads it, C3 still requires every suite to be named in `governance.yml` — so
  the guarantee is never weaker than before this change, only differently
  sourced.

## The patch

Append one job. Do **not** remove the existing per-suite jobs — they give named
checks and parallelism, and this job deliberately skips anything they already
cover, so nothing runs twice.

```yaml
  suite-manifest:
    name: manifest suites (not already wired to a job)
    runs-on: ${{ fromJSON((inputs.runner || vars.HARBOR_RUNNER) == 'github-hosted' && '["ubuntu-latest"]' || '["self-hosted","macOS","ARM64"]') }}
    steps:
      - uses: actions/checkout@v5

      # Runs every suite in contracts/suites.txt that does NOT already have a job
      # of its own in this file. Adding a suite becomes one line in the manifest,
      # with no workflow edit — which is the entire point of harbor#61.
      #
      # The skip is what keeps CI time flat: the runner is the operator's own
      # Mac, so running eleven suites twice is a real cost, not a rounding error.
      - name: run manifest suites with no dedicated job
        run: |
          set -eu
          ran=0
          while IFS= read -r s; do
            case "$s" in ''|\#*) continue ;; esac
            if grep -q "bin/$s" .github/workflows/governance.yml; then
              printf 'skip %s (has its own job)\n' "$s"
              continue
            fi
            printf '== %s\n' "$s"
            sh "bin/$s"
            ran=$((ran + 1))
          done < contracts/suites.txt
          printf '\nmanifest suites run: %d\n' "$ran"
```

## After applying

C3's `grep -q 'contracts/suites.txt'` on `governance.yml` starts matching, and
the fallback branch stops running. From then on, an agent adding
`bin/foo-test.sh` writes one line in `contracts/suites.txt` and CI runs it.

Verify with:

```sh
sh bin/lint-conventions.sh | grep C3     # must stay silent
```

Then confirm the new job actually executed something on the next run — a job
that skips everything and reports success is the failure mode this whole change
is about. On the first run after the patch it should print
`manifest suites run: 0`, because every current suite has its own job; that is
correct, and the number moves the first time a suite is added by manifest alone.
