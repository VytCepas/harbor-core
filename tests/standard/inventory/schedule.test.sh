#!/usr/bin/env sh
# bin/standard-inventory.sh schedule (harbor#1433): every scheduled job on the box is a row of the composed check register. The red
# proofs run on throwaway repos, never on a sibling checkout: a scheduled workflow with no row, a launchd label that is the prefix of a
# covered one, a repo fragment that covers a workflow through check-registry-generate.sh --repos, an exemption and its lapse.
. "$(dirname "$0")/../../lib/core.sh"; t_init
INV="$T_ROOT/bin/standard-inventory.sh"
B="$T_TMP/box"
mkbox() {
  rm -rf "$B"; mkdir -p "$B/root/docs/reference" "$B/root/bin" "$B/alpha/.github/workflows" "$B/beta/.github/workflows" "$B/launchd" "$B/cfg"
  cp "$T_ROOT/bin/check-registry-generate.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-register.sh" "$INV" "$B/root/bin/"
  printf '## Register\n\n| id | watches | schedule | notifies | red means |\n|---|---|---|---|---|\n<!-- private:register -->\n\n## Platforms\n\n| id | platforms | why | disable |\n|---|---|---|---|\n<!-- private:platforms -->\n' > "$B/root/docs/reference/checks.md"
  printf 'on:\n  push:\n    branches: [main]\n  schedule:\n    - cron: "0 3 * * *"\njobs: {}\n' > "$B/alpha/.github/workflows/nightly.yml"
  printf 'on:\n  push:\n    branches: [main]\n  workflow_dispatch: {}\n# schedule:\n#   - cron: "0 1 * * *"\njobs: {}\n' > "$B/beta/.github/workflows/ci.yml"
  printf '<plist><dict><key>Label</key><string>com.harbor.fixture.job</string></dict></plist>\n' > "$B/launchd/com.harbor.fixture.job.plist"
  printf 'alpha\t%s\nbeta\t%s\nroot\t%s\n' "$B/alpha" "$B/beta" "$B/root" > "$B/repos"
}
sched() { [ -n "${KEEP:-}" ] || rm -rf "$B/cfg"; sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg" \
  --launchd-dir "$B/launchd" --exempt "$B/exempt" --today 2026-11-02 schedule 2>&1; }

t_section "a scheduled workflow with no row is red; a push-only workflow and a commented schedule are not jobs"
mkbox
out="$(sched)"
t_has "the scheduled workflow is a finding" "$out" 'alpha/.github/workflows/nightly.yml'
t_hasnt "a workflow with no schedule trigger is not" "$out" 'beta/.github/workflows/ci.yml'
t_has "the launchd label with no row is a finding" "$out" 'com.harbor.fixture.job'
t_exit "a new finding exits 1" 1 sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg-a" --launchd-dir "$B/launchd" --exempt "$B/exempt" schedule

t_section "a row that cites the job as a whole word clears it; a prefix of a longer name does not"
printf '| `ci.fixture-nightly` | w | daily, `alpha/.github/workflows/nightly.yml` | none | red |\n' > "$B/rows"
awk -v f="$B/rows" '$0 == "<!-- private:register -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
printf '| ci.fixture-nightly | inherits: GitHub Actions | x | y |\n' > "$B/prows"
awk -v f="$B/prows" '$0 == "<!-- private:platforms -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
out="$(sched)"
t_hasnt "the workflow path is no longer a finding" "$out" 'new      alpha/.github'
printf '| `check.longer` | w | `com.harbor.fixture.job-extra` | none | red |\n' > "$B/rows"
awk -v f="$B/rows" '$0 == "<!-- private:register -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
printf '| check.longer | macOS only | y | z |\n' > "$B/prows"
awk -v f="$B/prows" '$0 == "<!-- private:platforms -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
t_has "com.harbor.fixture.job-extra does not cover com.harbor.fixture.job" "$(sched)" 'new      com.harbor.fixture.job'
printf '| `check.exact` | w | launchd `com.harbor.fixture.job`. | none | red |\n' > "$B/rows"
awk -v f="$B/rows" '$0 == "<!-- private:register -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
printf '| check.exact | macOS only | y | z |\n' > "$B/prows"
awk -v f="$B/prows" '$0 == "<!-- private:platforms -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
out="$(sched)"
t_hasnt "the label is covered by its own row" "$out" 'new      com.harbor.fixture.job'
t_has "and nothing is left" "$out" '0 finding(s)'
t_exit "a clean run exits 0" 0 sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg-b" --launchd-dir "$B/launchd" --exempt "$B/exempt" schedule

t_section "a repo's own harbor-pack/checks.md is composed, so the repo registers its workflow where it keeps it"
mkbox
printf '## Register\n\n| `ci.alpha-nightly` | w | `alpha/.github/workflows/nightly.yml` | none | red |\n\n## Platforms\n\n| ci.alpha-nightly | inherits: GitHub Actions | x | y |\n' > "$B/frag"
mkdir -p "$B/alpha/harbor-pack"; cp "$B/frag" "$B/alpha/harbor-pack/checks.md"
printf '| `check.exact` | w | `com.harbor.fixture.job` | none | red |\n' > "$B/rows"
awk -v f="$B/rows" '$0 == "<!-- private:register -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
printf '| check.exact | macOS only | y | z |\n' > "$B/prows"
awk -v f="$B/prows" '$0 == "<!-- private:platforms -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
t_has "check-registry-generate --repos puts the fragment row in the register" "$(sh "$B/root/bin/check-registry-generate.sh" --core "$B/root/docs/reference/checks.md" --private "$B/none" --repos "$B/repos")" '`ci.alpha-nightly`'
t_has "…and the fixture is clean through it" "$(sched)" '0 finding(s)'
cp "$B/frag" "$B/root/docs/reference/dup.md"
printf '| `ci.alpha-nightly` | w | `alpha/.github/workflows/nightly.yml` | none | red |\n' > "$B/rows"
awk -v f="$B/rows" '$0 == "<!-- private:register -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
printf '| ci.alpha-nightly | inherits: GitHub Actions | x | y |\n' > "$B/prows"
awk -v f="$B/prows" '$0 == "<!-- private:platforms -->" { while ((getline l < f) > 0) print l } { print }' "$B/root/docs/reference/checks.md" > "$B/c" && mv "$B/c" "$B/root/docs/reference/checks.md"
t_exit "an id in core and in a repo fragment refuses the register: unchecked, exit 3" 3 sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg-c" --launchd-dir "$B/launchd" schedule
t_exit "no --repos fragment changes nothing: the register is byte for byte core" 0 sh -c "sh '$B/root/bin/check-registry-generate.sh' --core '$B/root/docs/reference/checks.md' --private '$B/none' | cmp -s - '$B/root/docs/reference/checks.md'"

t_section "an exempt repo is not scanned until its date; a lapsed exemption judges it again"
mkbox
printf 'repo\treason\tremove_by\nalpha\ta separate project\t2026-12-01\n' > "$B/exempt"
out="$(sched)"
t_hasnt "alpha's workflow is not a finding" "$out" 'new      alpha/.github'
t_has "the run says how many repos it left out" "$out" '1 exempt repo(s)'
printf 'repo\treason\tremove_by\nalpha\ta separate project\t2026-10-01\n' > "$B/exempt"
out="$(sched)"
t_has "past its date the repo is judged again" "$out" 'new      alpha/.github/workflows/nightly.yml'
t_has "and the lapse is a finding of its own" "$out" 'exemption:alpha'

t_section "a repo that cannot be read keeps the run honest"
mkbox; printf 'ghost\t%s\n' "$B/missing" >> "$B/repos"
t_has "an unreadable checkout is a finding, not silence" "$(sched)" 'unread:ghost'
printf '' > "$B/repos"
t_exit "no repo registry at all is unchecked (3), never green" 3 sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg-d" --launchd-dir "$B/launchd" schedule

t_section "the delta and the ages: a standing finding is a count, not a relist, and the receipt is filed"
mkbox
KEEP=1; sched >/dev/null
out="$(sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --private "$B/none" --config-dir "$B/cfg" --launchd-dir "$B/launchd" --exempt "$B/exempt" --today 2026-11-09 schedule 2>&1)"
t_has "a week later the finding stands with its age" "$out" 'standing 2 finding(s) already filed, oldest 7 day(s)'
t_hasnt "and is not listed as new" "$out" 'new      alpha'
t_has "the receipt is red for the findings channel" "$(cat "$B/cfg/cache/checks/standard.schedule-registered.json")" 'red'

t_section "the real register names the scheduled workflows of yard and fleet (harbor#1433 condition 1)"
reg_real="$(sh "$T_ROOT/bin/check-registry-generate.sh" --core "$T_ROOT/docs/reference/checks.md" --private "$T_TMP/none")"
for _w in yard/.github/workflows/nightly.yml yard/.github/workflows/third-party-updates.yml fleet/.github/workflows/contract-freshness.yml fleet/.github/workflows/ci.yml; do
  t_has "the composed register cites $_w" "$reg_real" "$_w"
done
printf '%s\n' "$reg_real" > "$T_TMP/reg_real"
missing=""
for _p in "$T_ROOT"/launchd/com.harbor.*.plist; do
  _l="${_p##*/}"; _l="${_l%.plist}"
  grep -qF "$_l" "$T_TMP/reg_real" || missing="$missing $_l"
done
t_eq "every tracked launchd label of this checkout is in the register" "" "${missing# }"
t_done
