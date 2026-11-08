# Operator patch — the daily digest (harbor#1278, step 7)

**STATUS: NOT APPLIED.** Nothing here is enabled, and it is a recurring job: it needs the operator's own yes before anyone creates the file. An agent may not write `.github/workflows`.

## What it does

Once a day, reads the hub's heartbeat issues (`bin/hub-fetch.sh`), builds one digest (`bin/hub-digest.sh`) and posts it as an issue titled `digest YYYY-MM-DD`, mentioning the admins in the policy. The digest is posted **every day, empty or not**, so a morning with no mail is itself the signal (R19). `hub-watchdog` (its own patch) notices when it stops.

The digest holds a login, a time, a version, a floor hash and counts, nothing else: `hub-digest.sh` prints only fields that passed `hub-format.sh event`.

## Before you apply it

The variables of `hub-gates.patch.md` (`HARBOR_CORE_REPO`, `HARBOR_CORE_SHA`) are already set. Optional: the variable `HUB_MEMBERS`, the logins you expect, separated by spaces. Without it a member who has never sent a heartbeat does not appear, because the hub holds no member list (R13).

**Minutes.** Two short jobs a day are far under the included Actions minutes on Free and Team. With no payment method on the org, usage is blocked once the included minutes run out, and then every scheduled job stops silently. The watchdog is the answer to that, and so is the digest mail not arriving.

## The file

Create `.github/workflows/hub-digest.yml` in the hub with exactly this content.

```yaml
# hub-digest (harbor#1278): one digest issue a day, empty or not. Its absence is the alarm.
name: hub-digest
on:
  schedule:
    - cron: '17 6 * * *'
  workflow_dispatch:
permissions:
  contents: read
  issues: write
concurrency:
  group: hub-digest
  cancel-in-progress: false
jobs:
  digest:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ github.token }}
      REPO: ${{ github.repository }}
      CORE_SHA: ${{ vars.HARBOR_CORE_SHA }}
      MEMBERS: ${{ vars.HUB_MEMBERS }}
    steps:
      - name: The variables are set
        run: |
          set -eu
          printf '%s' "$CORE_SHA" | grep -Eq '^[0-9a-f]{40}$' || { echo "HARBOR_CORE_SHA is not a 40-hex commit" >&2; exit 1; }
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          path: hub
          persist-credentials: false
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          repository: ${{ vars.HARBOR_CORE_REPO }}
          ref: ${{ vars.HARBOR_CORE_SHA }}
          path: core
          persist-credentials: false
      - name: Build the digest
        id: build
        run: |
          set -eu
          sh core/bin/hub-fetch.sh "$REPO" > "$RUNNER_TEMP/issues.json"
          printf '%s\n' $MEMBERS > "$RUNNER_TEMP/members"
          sh core/bin/hub-digest.sh --issues "$RUNNER_TEMP/issues.json" --policy hub/policy.json --members "$RUNNER_TEMP/members" > "$RUNNER_TEMP/digest.md"
      - name: Post it once for the day
        run: |
          set -eu
          title="digest $(date -u +%F)"
          have="$(gh api --paginate "repos/$REPO/issues?state=all&per_page=100&sort=created&direction=desc" --jq ".[] | select(.title == \"$title\") | .number" | head -n 1)"
          if [ -n "$have" ]; then echo "$title already exists (#$have)"; exit 0; fi
          url="$(gh issue create --repo "$REPO" --title "$title" --body-file "$RUNNER_TEMP/digest.md")"
          gh issue close "$url" --repo "$REPO" --reason completed
          echo "posted $url"
```

## After applying

1. Run it once by hand: Actions, `hub-digest`, Run workflow. An issue `digest <today>` appears, closed, with the header `harbor-digest: 1`, and each admin in the policy gets a mail from the mention.
2. Run it again the same day: it says `already exists` and posts nothing.
3. Confirm the mail lands in the inbox of each admin. If it does not, see "Admins' notification setup" in `docs/how-to/hub-admin.md` before relying on this.

## Failure to watch for

- **No digest on a day is not a quiet day.** An empty hub still posts `no member has sent a heartbeat`. No issue means the job did not run or failed: open the Actions tab.
- **`hub-digest: ... fails hub-format.sh policy`.** The digest refuses a policy it cannot trust and prints nothing, so no issue is posted and the watchdog opens `digest missing`. Fix the policy.
- **A digest that lists nobody while members work.** Check that `HUB_MEMBERS` is a list of logins separated by spaces, and that heartbeat issues are titled `heartbeat <login>`.
- **Times are UTC.** The cron fires at 06:17 UTC, a rough guess at morning. GitHub may delay it by many minutes at busy hours.
