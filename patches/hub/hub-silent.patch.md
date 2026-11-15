# Operator patch — the silent-member alarm (harbor#1278, step 7)

**STATUS: NOT APPLIED.** Nothing here is enabled, and it is a recurring job: it needs the operator's own yes. An agent may not write `.github/workflows`.

## What it does

Once a day, finds the members who have not sent a valid heartbeat for `silent_days` days or more (`bin/hub-digest.sh --silent`) and opens one issue `silent <login>` for each, mentioning the admins, so a mail arrives. It opens an issue once, not every day, and closes it with a comment when the member is seen again. The daily digest lists the same people; this is the one that mails.

A member counts as silent for a reason this job cannot tell apart: a laptop that is off, a person on holiday, an expired token, or a harbor that stopped. The issue says "silent", and nothing more.

## Before you apply it

The variables of `hub-gates.patch.md` and, optionally, `HUB_MEMBERS` of `hub-digest.patch.md` are set. Without `HUB_MEMBERS` only members who have an issue `heartbeat <login>` can be silent.

## The file

Create `.github/workflows/hub-silent.yml` in the hub with exactly this content.

```yaml
# hub-silent (harbor#1278): one issue per silent member, closed when they are back.
name: hub-silent
on:
  schedule:
    - cron: '47 6 * * *'
  workflow_dispatch:
permissions:
  contents: read
  issues: write
concurrency:
  group: hub-silent
  cancel-in-progress: false
jobs:
  silent:
    runs-on: ubuntu-latest
    env:
      GH_TOKEN: ${{ github.token }}
      REPO: ${{ github.repository }}
      CORE_SHA: ${{ vars.HARBOR_HUB_CORE_SHA }}
      MEMBERS: ${{ vars.HUB_MEMBERS }}
    steps:
      - name: The variables are set
        run: |
          set -eu
          printf '%s' "$CORE_SHA" | grep -Eq '^[0-9a-f]{40}$' || { echo "HARBOR_HUB_CORE_SHA is not a 40-hex commit" >&2; exit 1; }
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          path: hub
          persist-credentials: false
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          repository: ${{ vars.HARBOR_CORE_REPO }}
          ref: ${{ vars.HARBOR_HUB_CORE_SHA }}
          path: core
          persist-credentials: false
      - name: Find the silent members
        run: |
          set -eu
          sh core/bin/hub-fetch.sh "$REPO" > "$RUNNER_TEMP/issues.json"
          printf '%s\n' $MEMBERS > "$RUNNER_TEMP/members"
          sh core/bin/hub-digest.sh --issues "$RUNNER_TEMP/issues.json" --policy hub/policy.json --members "$RUNNER_TEMP/members" --silent > "$RUNNER_TEMP/silent.txt"
          jq -r '.silent_days' hub/policy.json > "$RUNNER_TEMP/silent_days"
          jq -r '.approval.approvers | map("@" + .) | join(" ")' hub/policy.json > "$RUNNER_TEMP/cc"
      - name: Open and close the issues
        run: |
          set -eu
          days="$(cat "$RUNNER_TEMP/silent_days")"; cc="$(cat "$RUNNER_TEMP/cc")"
          open="$(gh api --paginate "repos/$REPO/issues?state=open&per_page=100" --jq '.[] | select(.title | startswith("silent ")) | "\(.number) \(.title[7:])"')"
          # a member who is silent and has no open issue gets one
          while IFS= read -r login; do
            [ -n "$login" ] || continue
            printf '%s\n' "$open" | awk -v l="$login" '$2 == l { f = 1 } END { exit !f }' && continue
            printf 'harbor-silent: 1\nmember: %s\nsilent_days: %s\ncc: %s\n' "$login" "$days" "$cc" > "$RUNNER_TEMP/body.md"
            gh issue create --repo "$REPO" --title "silent $login" --body-file "$RUNNER_TEMP/body.md"
          done < "$RUNNER_TEMP/silent.txt"
          # an open issue for a member who is no longer silent is closed
          printf '%s\n' "$open" | while read -r num login; do
            [ -n "$num" ] || continue
            grep -q -F -x -e "$login" "$RUNNER_TEMP/silent.txt" && continue
            gh issue comment "$num" --repo "$REPO" --body "seen again"
            gh issue close "$num" --repo "$REPO" --reason completed
          done
```

## After applying

1. Run it by hand. With every member current, it opens nothing.
2. To see it fire without waiting: set `silent_days` to 1 in a signed policy for one day, or run it against a hub where a member's last heartbeat is older than `silent_days`. An issue `silent <login>` opens once, with `cc:` naming the admins, and the admins get a mail.
3. Run it again: no second issue for the same member.

## Failure to watch for

- **An issue per day per member.** The open-issue lookup failed: the workflow needs `issues: read` on the repo and the title must stay `silent <login>`.
- **Nothing opens while members are plainly absent.** The members have no `heartbeat <login>` issue yet and `HUB_MEMBERS` is empty: the job cannot see people it has never heard of.
- **A silent issue for everyone after a long outage.** If GitHub or the network was down for `silent_days`, every member looks silent at once. The digest of the same morning shows the same; read both before writing to anyone.
