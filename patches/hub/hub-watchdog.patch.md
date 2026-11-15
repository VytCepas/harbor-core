# Operator patch — the watchdog for a dropped schedule (harbor#1278, step 7, R19)

**STATUS: NOT APPLIED.** Nothing here is enabled, and it is a recurring job: it needs the operator's own yes. An agent may not write `.github/workflows`.

## What it does

GitHub may delay or drop a scheduled run ("some queued jobs may be dropped"), and a dropped digest looks exactly like a quiet day. The watchdog checks that a `digest YYYY-MM-DD` issue was posted within the last 26 hours. If not, it opens one issue `digest missing`, mentioning the admins. When a digest is back it closes that issue.

It does not depend only on a schedule, which is the point. It runs on its own cron four times a day **and on every comment created on a `heartbeat <login>` issue**. Members' laptops post those comments when they work, so a schedule GitHub stops running is still noticed the next time anyone works. If nobody works and the schedules are all dropped, the signal left is the morning mail that did not arrive, and `docs/how-to/hub-admin.md` tells the admins to treat that as an outage.

## Before you apply it

The variables of `hub-gates.patch.md` are set, and `hub-digest` is applied: with no digest ever posted, the watchdog counts from the age of the repo, so a new hub gets one day of grace and then `digest missing`.

## The file

Create `.github/workflows/hub-watchdog.yml` in the hub with exactly this content.

```yaml
# hub-watchdog (harbor#1278): notices when the daily digest stops, on a schedule and on member activity.
name: hub-watchdog
on:
  schedule:
    - cron: '41 0,6,12,18 * * *'
  issue_comment:
    types: [created]
  workflow_dispatch:
permissions:
  contents: read
  issues: write
concurrency:
  group: hub-watchdog
  cancel-in-progress: true
jobs:
  watchdog:
    if: ${{ github.event_name != 'issue_comment' || startsWith(github.event.issue.title, 'heartbeat ') }}
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ github.token }}
      REPO: ${{ github.repository }}
      STALE_HOURS: '26'
    steps:
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          persist-credentials: false
      - name: Is there a digest from the last day
        run: |
          set -eu
          # the newest digest issue, else the repo's own age (a new hub gets its grace)
          newest="$(gh api "repos/$REPO/issues?state=all&per_page=100&sort=created&direction=desc" --jq '[.[] | select(.title | startswith("digest 20")) | .created_at] | first // empty')"
          [ -n "$newest" ] || newest="$(gh api "repos/$REPO" --jq '.created_at')"
          age_h="$(jq -n -r --arg t "$newest" '((now - ($t | fromdateiso8601)) / 3600) | floor')"
          open="$(gh api "repos/$REPO/issues?state=open&per_page=100" --jq '[.[] | select(.title == "digest missing") | .number] | first // empty')"
          echo "newest digest or repo creation: $newest ($age_h h ago)"
          if [ "$age_h" -ge "$STALE_HOURS" ]; then
            if [ -z "$open" ]; then
              cc="$(jq -r '.approval.approvers | map("@" + .) | join(" ")' policy.json)"
              printf 'harbor-watchdog: 1\nmissing: digest\nhours_since: %s\ncc: %s\n' "$age_h" "$cc" > "$RUNNER_TEMP/body.md"
              gh issue create --repo "$REPO" --title "digest missing" --body-file "$RUNNER_TEMP/body.md"
            else
              echo "digest missing is already open (#$open)"
            fi
          elif [ -n "$open" ]; then
            gh issue comment "$open" --repo "$REPO" --body "a digest is back"
            gh issue close "$open" --repo "$REPO" --reason completed
          fi
```

## After applying

1. Run it by hand with a fresh digest in place: it prints `... h ago`, opens nothing.
2. Prove it fires: run it in a hub whose newest digest is older than 26 hours (a new hub with no digest, a day after creation, will do). An issue `digest missing` opens with `cc:` naming the admins, and a mail arrives.
3. Run it again: it says the issue is already open and does not make a second one.
4. Post a digest (run `hub-digest` by hand) and run the watchdog: it comments and closes the issue.

## Failure to watch for

- **The watchdog has the same weakness as what it watches.** A dropped watchdog schedule is covered by the comment trigger only while members work, and by the admins noticing a missing mail. Neither is a guarantee; this lowers the odds, and the doc says what the residue is.
- **`digest missing` opens every morning for a week after you apply it.** The digest workflow is not applied, or fails: open the Actions tab and read its last run.
- **A new hub opens `digest missing` on day two.** Correct: it has had a day and posted no digest.
