# Operator patch — the hub loader into BigQuery (harbor#1278, release 2 logging, D1)

**STATUS: NOT APPLIED.** Nothing here is enabled. It runs only by hand (`workflow_dispatch`): the daily schedule (J1) is a recurring job and needs the operator's own yes, and then the one `schedule` block below is added. An agent may not write `.github/workflows`.

## What it does

Reads the board's heartbeat issues (`bin/hub-fetch.sh`) and every signed policy in the hub's history (`bin/bq-load.sh policies`), then `bin/bq-load.sh build` keeps only comments whose author is the issue's member and that pass `hub-format.sh board`, opens each heartbeat's `sealed` field with the loader's age identity, and so learns that laptop's random id and its activity and session counts. It drops the GitHub author before anything is staged, refuses the whole run if a login or an e-mail is left in a staged file, codes the rows through `bin/bq-format.sh`, and `bin/bq-load.sh apply` loads them into staging tables, runs the SQL checks (no STRING column outside `dim_`, every code in `dim_enum`) and merges in one transaction. An id listed in `logs/excluded-ids.txt` in the hub loads nothing, and the merge deletes every row it has (`legal/dpia.md` R12).

A laptop with no notice-receipt marker seals nothing, so it gives no row at all: the receipt gate is on the laptop (R11). The loader keeps no names.

## Identity, and what holds what

- **No key file anywhere.** GitHub's OIDC token for this job is exchanged through the Workload Identity pool for a short-lived token of `harbor-bq-loader`. The pool's condition admits only this repo, `refs/heads/main` and this workflow file (`gcp-setup.md`, step 5).
- **The age identity** that opens `sealed` is a Secret Manager secret only `harbor-bq-loader` can read. It is written to `$RUNNER_TEMP` under `umask 077` for the one step that needs it and removed after; the runner is discarded with it. Whoever can run this job with that identity and read the board can link an id to a login: this is the limit `legal/dpia.md` R3 names, and why the workflow file is protected by CODEOWNERS and the pool condition.

## Before you apply it

1. `gcp-setup.md` is done: the project, the dataset, the loader service account, the pool and provider, the age identity secret and the views.
2. The hub's signed policy carries `"logs": {"recipient": "age1…"}`, the recipient printed in `gcp-setup.md` step 6. Without it no laptop seals anything.
3. Repository variables on the hub (Settings → Secrets and variables → Actions → Variables): `HARBOR_CORE_REPO`, `HARBOR_CORE_SHA` (as `hub-gates.patch.md`), `HARBOR_LOGS_PROJECT`, `HARBOR_LOGS_DATASET` (`harbor_logs`), `HARBOR_LOGS_WIF_PROVIDER` (the full provider name from step 5), `HARBOR_LOGS_LOADER_SA` (`harbor-bq-loader@PROJECT.iam.gserviceaccount.com`), `HARBOR_LOGS_IDENTITY_SECRET` (`harbor-logs-age-identity`). None of them is a secret.
4. Optionally `logs/excluded-ids.txt` in the hub, one 32-hex id a line, changed only through a reviewed PR.

## The file

Create `.github/workflows/hub-bq-load.yml` in the hub with exactly this content.

```yaml
# hub-bq-load (harbor#1278): the board's heartbeat comments into harbor's BigQuery logs, keyed by each laptop's random id.
name: hub-bq-load
on:
  workflow_dispatch:
permissions:
  contents: read
  issues: read
  id-token: write
concurrency:
  group: hub-bq-load
  cancel-in-progress: false
jobs:
  load:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ github.token }}
      REPO: ${{ github.repository }}
      CORE_SHA: ${{ vars.HARBOR_CORE_SHA }}
      PROJECT: ${{ vars.HARBOR_LOGS_PROJECT }}
      DATASET: ${{ vars.HARBOR_LOGS_DATASET }}
      SECRET: ${{ vars.HARBOR_LOGS_IDENTITY_SECRET }}
    steps:
      - name: The variables are set
        run: |
          set -eu
          printf '%s' "$CORE_SHA" | grep -Eq '^[0-9a-f]{40}$' || { echo "HARBOR_CORE_SHA is not a 40-hex commit" >&2; exit 1; }
          printf '%s' "$PROJECT" | grep -Eq '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' || { echo "HARBOR_LOGS_PROJECT is not a project id" >&2; exit 1; }
          printf '%s' "$DATASET" | grep -Eq '^[a-z_][a-z0-9_]{0,63}$' || { echo "HARBOR_LOGS_DATASET is not a dataset name" >&2; exit 1; }
          printf '%s' "$SECRET" | grep -Eq '^[A-Za-z0-9_-]{1,255}$' || { echo "HARBOR_LOGS_IDENTITY_SECRET is not a secret name" >&2; exit 1; }
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          path: hub
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          repository: ${{ vars.HARBOR_CORE_REPO }}
          ref: ${{ vars.HARBOR_CORE_SHA }}
          path: core
          persist-credentials: false
      - uses: google-github-actions/auth@7c6bc770dae815cd3e89ee6cdf493a5fab2cc093 # v3.0.0
        with:
          workload_identity_provider: ${{ vars.HARBOR_LOGS_WIF_PROVIDER }}
          service_account: ${{ vars.HARBOR_LOGS_LOADER_SA }}
      - uses: google-github-actions/setup-gcloud@aa5489c8933f4cc7a4f7d45035b3b1440c9c10db # v3.0.1
      - name: The tools
        run: |
          set -eu
          sudo apt-get update -q
          sudo apt-get install -y -q age jq
      - name: Read the board and the policies
        run: |
          set -eu
          sh core/bin/hub-fetch.sh "$REPO" > "$RUNNER_TEMP/issues.json"
          sh core/bin/bq-load.sh policies hub "$RUNNER_TEMP/policies"
      - name: Build the rows
        run: |
          set -eu
          umask 077
          if [ -f hub/logs/excluded-ids.txt ]; then cp hub/logs/excluded-ids.txt "$RUNNER_TEMP/excluded"; else : > "$RUNNER_TEMP/excluded"; fi
          gcloud secrets versions access latest --secret="$SECRET" --project="$PROJECT" > "$RUNNER_TEMP/identity"
          rc=0
          sh core/bin/bq-load.sh build --issues "$RUNNER_TEMP/issues.json" --policies "$RUNNER_TEMP/policies" \
            --identity "$RUNNER_TEMP/identity" --excluded "$RUNNER_TEMP/excluded" --out "$RUNNER_TEMP/out" || rc=$?
          rm -f "$RUNNER_TEMP/identity"
          exit "$rc"
      - name: Load and merge
        run: |
          set -eu
          sh core/bin/bq-load.sh apply --dir "$RUNNER_TEMP/out" --project "$PROJECT" --dataset "$DATASET"
          jq -c . "$RUNNER_TEMP/out/summary.json"
```

## When J1 gets its yes

Add, under `on:`, exactly:

```
  schedule:
    - cron: '23 7 * * *'
```

07:23 UTC, after `hub-digest` (06:17) and `hub-silent` (06:47).

## After applying

1. Run it by hand (Actions → hub-bq-load → Run workflow). The last line prints the summary: comments read, kept, rows staged and refused by reason. A pilot with no laptop holding a notice marker stages no fact row, and that is right.
2. In BigQuery, `SELECT * FROM harbor_logs.v_pipeline` shows the run, and `SELECT COUNT(*) FROM harbor_logs.heartbeat` the ids seen.
3. Run it again: the counts do not double, because each (source, id, day) is replaced whole.

## Failure to watch for

- **`no-id` for every comment.** The policy has no `logs.recipient`, the laptops lack `age`, or none has the notice marker. `harbor hub id` on a laptop says which.
- **`google-github-actions/auth` refuses.** The pool condition does not match: it admits `main` and this file only, so a run from a branch or a renamed file is refused, as intended.
- **The merge stops on an ASSERT.** Nothing reached the fact tables. A code a laptop sent that `dim_enum` lacks means the laptop runs a newer core than this job's `HARBOR_CORE_SHA`: raise the pin.
- **Minutes run out.** The job stops and nothing says so but `v_pipeline`'s age: J2 (a freshness alert) is the remedy, and it is a recurring job of its own.
