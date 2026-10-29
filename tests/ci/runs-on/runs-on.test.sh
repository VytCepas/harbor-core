#!/usr/bin/env sh
# ci-runs-on.sh against fixture workflow copies (harbor#1060). One job per case; the control is the plain
# hosted job that MUST be rewritten, every other case must come back untouched with its reason.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/ci-runs-on.sh"
R="$T_TMP/repo"; W="$R/.github/workflows"; mkdir -p "$W"
git -C "$R" init -q

cat > "$W/ci.yml" <<'EOF'
name: ci
on: [push]
jobs:
  lint:
    runs-on: ubuntu-latest # keep this note
    steps:
      - run: echo lint
  test:
    runs-on: "ubuntu-22.04"
    steps:
      - run: |
          echo runs-on: ubuntu-latest in a script is not a label
  old:
    runs-on: ubuntu-24.04
    env:
      TOKEN: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - run: echo token only
  adopted:
    runs-on: ${{ vars.CI_RUNS_ON || 'ubuntu-24.04' }}
    steps:
      - run: echo done
  expr:
    runs-on: ${{ vars.HARBOR_RUNNER || 'ubuntu-latest' }}
    steps:
      - run: echo x
  matrixed:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - run: echo x
  arr:
    runs-on: [self-hosted, linux]
    steps:
      - run: echo x
  grp:
    runs-on:
      group: big
      labels: linux
    steps:
      - run: echo x
  mac:
    runs-on: macos-14
    steps:
      - run: echo x
  win:
    runs-on: windows-latest
    steps:
      - run: echo x
  reuse:
    uses: ./.github/workflows/other.yml
EOF
cat > "$W/ship.yml" <<'EOF'
name: ship
on: [push]
jobs:
  deploy-site:
    runs-on: ubuntu-latest
    steps:
      - run: echo go
  build:
    runs-on: ubuntu-latest
    environment: production
    steps:
      - run: echo go
  cloud:
    runs-on: ubuntu-latest
    steps:
      - uses: google-github-actions/auth@v2
  secret:
    runs-on: ubuntu-latest
    steps:
      - run: echo ${{ secrets.NPM_TOKEN }}
  oidc:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
    steps:
      - run: echo go
  fb:
    runs-on: ubuntu-latest
    steps:
      - run: firebase deploy
  publish:
    runs-on: ubuntu-latest
    steps:
      - run: echo go
EOF
# job indent of four spaces, and a file with no jobs at all
cat > "$W/wide.yaml" <<'EOF'
name: wide
jobs:
    only:
        runs-on: ubuntu-latest
        steps:
            - run: echo x
EOF
git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t commit -qm fx
run() { sh "$TOOL" "$R" "$@" 2>&1; }

t_section "dry run reports and diffs, and writes nothing"
OUT="$(run)"
t_eq "the tree is untouched" "" "$(git -C "$R" status --porcelain)"
t_has "lint is rewritten" "$OUT" "+    runs-on: \${{ vars.CI_RUNS_ON || 'ubuntu-latest' }} # keep this note"
t_has "a quoted label keeps its value" "$OUT" "+    runs-on: \${{ vars.CI_RUNS_ON || 'ubuntu-22.04' }}"
t_has "a GITHUB_TOKEN-only job is rewritten" "$OUT" "'ubuntu-24.04' }}"
t_has "four-space indent is rewritten" "$OUT" "+        runs-on: \${{ vars.CI_RUNS_ON || 'ubuntu-latest' }}"
t_has "a unified diff header" "$OUT" "+++ b/.github/workflows/ci.yml"
t_has "tells how to apply" "$OUT" "--apply"
t_hasnt "a script line mentioning runs-on is left alone" "$OUT" "+          echo runs-on"
t_eq "three jobs in ci.yml + one in wide.yaml are rewritten" "4" "$(printf '%s\n' "$OUT" | grep -c 'rewrite ')"
t_eq "ship.yml has no rewrite" "0" "$(printf '%s\n' "$OUT" | grep 'rewrite ' | grep -c 'ship.yml')"

t_section "each skip carries its reason"
for pair in 'adopted:already adopted' 'expr:already an expression' 'matrixed:already an expression' \
  'arr:array or group form' 'grp:array, matrix or group form' 'mac:macOS runner' 'win:Windows runner' \
  'reuse:no runs-on' 'deploy-site:deploy/release/publish' 'build:environment' 'cloud:cloud credentials' \
  'secret:secrets beyond GITHUB_TOKEN' 'oidc:OIDC' 'fb:cloud credentials' 'publish:deploy/release/publish'; do
  j="${pair%%:*}"; why="${pair#*:}"
  line="$(printf '%s\n' "$OUT" | grep ":: $j " || :)"
  t_has "$j is not rewritten" "$line" "$why"
  t_hasnt "$j is not a rewrite" "$line" "rewrite"
done

t_section "--apply writes, then a second --apply changes nothing"
run --apply >/dev/null
t_eq "the rewrite landed in ci.yml (3 new + the adopted one)" "4" "$(grep -c 'runs-on: \${{ vars.CI_RUNS_ON' "$W/ci.yml")"
t_eq "ship.yml is byte-identical" "" "$(git -C "$R" diff --stat -- .github/workflows/ship.yml)"
t_has "wide.yaml is rewritten" "$(cat "$W/wide.yaml")" "vars.CI_RUNS_ON || 'ubuntu-latest'"
SUM1="$(cat "$W"/* | cksum)"
OUT2="$(run --apply)"
t_eq "second apply leaves every file the same" "$SUM1" "$(cat "$W"/* | cksum)"
t_has "second apply says nothing to rewrite" "$OUT2" "nothing to rewrite"
t_eq "nothing was committed" "fx" "$(git -C "$R" log --format=%s)"
t_has "the original label is the fallback" "$(cat "$W/ci.yml")" "vars.CI_RUNS_ON || 'ubuntu-22.04' }}"

t_section "apply prints the commands to run by hand"
R2="$T_TMP/repo2"; mkdir -p "$R2/.github/workflows"
printf 'jobs:\n  a:\n    runs-on: ubuntu-latest\n' > "$R2/.github/workflows/a.yml"
OUT3="$(sh "$TOOL" "$R2" --apply 2>&1)"
t_has "a branch is created by the operator" "$OUT3" "switch -c ci/runs-on-adopt"
t_has "a push is printed, not run" "$OUT3" "push -u origin ci/runs-on-adopt"
t_has "a PR command is printed" "$OUT3" "gh pr create"

t_section "usage errors"
t_exit "no argument" 2 sh "$TOOL"
t_exit "a directory with no workflows" 2 sh "$TOOL" "$T_TMP/home"
t_exit "an unknown option" 2 sh "$TOOL" "$R" --force
t_done
