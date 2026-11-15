# Operator patch — the hub's gates (harbor#1278, step 7)

**STATUS: NOT APPLIED.** Nothing here is enabled. An agent may not write `.github/workflows`, so this file carries the whole workflow for a person to create in the **hub** repo (not in harbor).

## What it does

On every pull request and every push to `main`, runs `bin/hub-gate.sh` from a pinned harbor-core commit over the hub checkout: the leak gate in export mode, gitleaks, the share check, the policy format, the signature, a serial that rises, and the packs (with `bin/pack.sh`'s own install refusals, so a pack every laptop would skip is red). Red on any finding (R14, R23, R29).

**On GitHub Free a private repo has no protected branches (R14).** The check then reports red but cannot stop a merge or a push to `main`, so a bad policy still reaches every laptop. The signature is what keeps an unsigned policy out: a laptop refuses it whatever the board says. On Team, require the check `hub gates` in branch protection (`docs/how-to/hub-admin.md`).

## Before you apply it

Set three repository variables in the hub (Settings, Secrets and variables, Variables), and one optional secret:

| Name | Value |
|---|---|
| `HARBOR_CORE_REPO` | `owner/name` of the harbor-core repo that holds `bin/hub-gate.sh` |
| `HARBOR_HUB_CORE_SHA` | the 40-hex commit you tested, usually the same as `core.commit` in `policy.json`; raise it by hand, never from a pull request |
| `GITLEAKS_SHA256` | the sha256 of the pinned `gitleaks_8.18.4_linux_x64.tar.gz`, from that release's checksums file |
| secret `HUB_LEAKS_TSV` (optional) | the company's own names as a `leaks.tsv` (`id`, `kind`, `pattern`, `note`; `contracts/private-layer.md`). Without it only the generic patterns run |

## The file

Create `.github/workflows/hub-gates.yml` in the hub with exactly this content.

```yaml
# hub-gates (harbor#1278): bin/hub-gate.sh over the hub, from a pinned harbor-core commit.
name: hub-gates
on:
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: hub-gates-${{ github.ref }}
  cancel-in-progress: true
jobs:
  gates:
    name: hub gates
    runs-on: ubuntu-latest
    env:
      CORE_SHA: ${{ vars.HARBOR_HUB_CORE_SHA }}
      GL_SHA256: ${{ vars.GITLEAKS_SHA256 }}
      LEAKS_TSV: ${{ secrets.HUB_LEAKS_TSV }}
      BASE_REF: ${{ github.base_ref }}
      BEFORE_SHA: ${{ github.event.before }}
    steps:
      - name: The variables are set
        run: |
          set -eu
          printf '%s' "$CORE_SHA" | grep -Eq '^[0-9a-f]{40}$' || { echo "HARBOR_HUB_CORE_SHA is not a 40-hex commit" >&2; exit 1; }
          [ -n "$GL_SHA256" ] || { echo "GITLEAKS_SHA256 are not set" >&2; exit 1; }
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          path: hub
          fetch-depth: 0
          persist-credentials: false
      - uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5.1.0
        with:
          repository: ${{ vars.HARBOR_CORE_REPO }}
          ref: ${{ vars.HARBOR_HUB_CORE_SHA }}
          path: core
          persist-credentials: false
      - name: Install gitleaks at the pinned release
        run: |
          set -eu
          curl -fsSL https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz -o "$RUNNER_TEMP/gitleaks.tgz"
          echo "${GL_SHA256}  $RUNNER_TEMP/gitleaks.tgz" | sha256sum -c -
          sudo tar -xz -C /usr/local/bin -f "$RUNNER_TEMP/gitleaks.tgz" gitleaks
      - name: Run the gate
        run: |
          set -eu
          # the company's own names stay outside the hub tree
          if [ -n "$LEAKS_TSV" ]; then
            mkdir -p "$RUNNER_TEMP/priv" && printf '%s\n' "$LEAKS_TSV" > "$RUNNER_TEMP/priv/leaks.tsv"
            export HARBOR_HUB_GATE_PRIVATE="$RUNNER_TEMP/priv"
          else
            echo "no HUB_LEAKS_TSV secret: only the generic leak patterns ran" >&2
          fi
          # the policy this change is made against: a changed policy must carry a higher serial
          base=""
          if [ -n "$BASE_REF" ]; then base="origin/$BASE_REF"
          elif printf '%s' "$BEFORE_SHA" | grep -Eq '^[0-9a-f]{40}$' && [ "$BEFORE_SHA" != 0000000000000000000000000000000000000000 ]; then base="$BEFORE_SHA"; fi
          if [ -n "$base" ] && git -C hub show "$base:policy.json" > "$RUNNER_TEMP/base-policy.json" 2>/dev/null; then
            sh core/bin/hub-gate.sh hub --core core --base "$RUNNER_TEMP/base-policy.json"
          else
            sh core/bin/hub-gate.sh hub --core core
          fi
```

## After applying

1. Open a pull request that only changes `README.md`. The `hub gates` check must run and pass once the policy is signed. A hub with no `policy.json.sig` fails it with `[signature]`, which is the proof the gate runs.
2. Prove it goes red: on a branch, add a line naming a path under a person's home folder (the form `/home/<name>/x`, with a real name) to `README.md`. The check must fail with `[leaks]` and name the pattern id, not the text. Delete the branch.
3. If you are on Team, add `hub gates` to the branch protection rule for `main`, with admins included.

## Failure to watch for

- **Green with nothing judged.** The last line of a passing run is `N file(s) judged, no finding`. If `N` is 0 or the line is absent, the gate did not look at the hub: check the `path: hub` checkout.
- **`gitleaks: sha256 mismatch`.** The release was re-uploaded or the checksum was copied from another file. Do not skip the check; copy the checksum again.
- **A pull request raising `HARBOR_HUB_CORE_SHA`.** The variable is not in the repo, so a pull request cannot change which gate judges it. Keep it that way.
- **The workflow file itself.** A pull request can edit `.github/workflows/hub-gates.yml` and weaken its own gate. `CODEOWNERS` covers it, and only branch protection (Team) enforces the owner's review.
