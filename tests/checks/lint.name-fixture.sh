#!/usr/bin/env sh
# Shared fixture for the lint-name suites (harbor#950): mini <dir> builds the copy of what bin/lint-name.sh reads.
# Sourced after tests/checks/lint-fixture.sh, with LN (the lint) and REG (the registry) set.
# A copy of what the lint reads, outside git: the lint, its log library, the registry, the standard
# and the fixtures. Its legacy rows are its OWN first scan (--gen exemptions), the move harbor#950 made
# on harbor's tree, so a finding on it is a finding about what the arm put there afterwards.
mini() { # <dir>
  mkdir -p "$1/bin" "$1/standards" "$1/fixtures"
  cp "$LN" "$T_ROOT/bin/log-lib.sh" "$1/bin/"
  cp -R "$REG" "$1/standards/"; cp "$T_ROOT/standards/naming.md" "$1/standards/"
  cp -R "$T_ROOT/fixtures/naming" "$1/fixtures/"
  # the sources the census reads, real, so a copy is a tree whose every control id is carried (an empty census is red)
  mkdir -p "$1/CONTRACTS" "$1/inject.d/box" "$1/.claude/inject.d"
  cp "$T_ROOT"/bin/guard-*.sh "$T_ROOT/bin/lint-conventions.sh" "$1/bin/"; cp "$T_ROOT/CHECKS.md" "$1/"
  cp "$T_ROOT/CONTRACTS/required-checks.tsv" "$1/CONTRACTS/"; cp "$T_ROOT"/inject.d/box/*.md "$1/inject.d/box/"; cp "$T_ROOT"/.claude/inject.d/*.md "$1/.claude/inject.d/"
  # a stub for every file a control names as its engine or its proof, so the copy is a tree controls.tsv can be judged in
  awk -F'\t' '/^#/ || $1 == "id" { next } { print $4; print $11 }' "$REG/controls.tsv" | sort -u | grep -vx -- '-' | while IFS= read -r _p; do
    mkdir -p "$1/$(dirname "$_p")"; [ -e "$1/$_p" ] || : > "$1/$_p"
  done
  grep -v '^legacy-' "$REG/exemptions.tsv" > "$1/standards/naming/exemptions.tsv"
  sh "$1/bin/lint-name.sh" --root "$1" --gen exemptions > /dev/null 2>&1
  cat "$1/build/naming/exemptions.legacy.tsv" >> "$1/standards/naming/exemptions.tsv"
}
