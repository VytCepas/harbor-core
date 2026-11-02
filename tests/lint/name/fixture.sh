#!/usr/bin/env sh
# Shared fixture for the lint-name suites (harbor#950): mini <dir> builds the copy of what bin/lint-name.sh reads.
# Sourced after tests/checks/lint-fixture.sh, with LN (the lint) and REG (the registry) set.
# A copy of what the lint reads, outside git: the lint, its log library, the registry, the standard
# and the fixtures. Its legacy rows are its OWN first scan (--gen exemptions), the move harbor#950 made
# on harbor's tree, so a finding on it is a finding about what the arm put there afterwards.
mini() { # <dir>
  mkdir -p "$1/bin" "$1/standards" "$1/fixtures"
  cp "$LN" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-register.sh" "$1/bin/"
  cp -R "$REG" "$1/standards/"; cp "$T_ROOT/standards/naming.md" "$1/standards/"
  cp -R "$T_ROOT/fixtures/naming" "$1/fixtures/"
  # the sources the census reads, real, so a copy is a tree whose every control id is carried (an empty census is red)
  mkdir -p "$1/contracts" "$1/context-rules" "$1/docs/reference"
  cp "$T_ROOT"/bin/admission-*.sh "$T_ROOT"/bin/library-admission.sh "$T_ROOT/bin/lint-conventions.sh" "$1/bin/"; cp "$T_ROOT/docs/reference/checks.md" "$1/docs/reference/"
  cp "$T_ROOT/contracts/required-checks.tsv" "$1/contracts/"; cp -R "$T_ROOT"/context-rules/. "$1/context-rules/"
  # a stub for every file a control names as its engine or its proof, so the copy is a tree controls.tsv can be judged in
  awk -F'\t' '/^#/ || $1 == "id" { next } { print $4; print $11 }' "$REG/controls.tsv" | sort -u | awk '$0 != "-"' | while IFS= read -r _p; do
    mkdir -p "$1/$(dirname "$_p")"; [ -e "$1/$_p" ] || : > "$1/$_p"
  done
  # ...and for every reader schemas.tsv names, since read_by is a path the tree must hold (standard.reference-resolves, harbor#1424)
  awk -F'\t' '/^#/ || $1 == "id" { next } $7 ~ /\// { print $7 }' "$REG/schemas.tsv" | sort -u | while IFS= read -r _p; do
    mkdir -p "$1/$(dirname "$_p")"; [ -e "$1/$_p" ] || : > "$1/$_p"
  done
  # the copy's schema table declares only the registers the copy holds: a row with no file is red (standard.register-declared)
  awk -F'\t' -v r="$1" '/^#/ || $1 == "id" || ($1 !~ /\*/ && system("test -e \"" r "/" $1 "\"") == 0) { print }' "$REG/schemas.tsv" > "$1/standards/naming/schemas.tsv"
  grep -v '^legacy-' "$REG/exemptions.tsv" > "$1/standards/naming/exemptions.tsv"
  sh "$1/bin/lint-name.sh" --root "$1" --gen exemptions > /dev/null 2>&1
  cat "$1/build/naming/exemptions.legacy.tsv" >> "$1/standards/naming/exemptions.tsv"
}
# the repo-kind trees (name.test.sh, repo-verb.test.sh): RKD holds them, mkrk builds one, rk judges one
RKD="$TMP/rkdirs"; mkdir -p "$RKD"
vrecipes() { # <kind> -> a justfile with one empty recipe per verb verbs.tsv requires of the kind (harbor#1428)
  awk -F'\t' -v k="$1" '/^#/ || !H[FILENAME]++ { next } $4 != "-" && k != "" && index(" " $4 " ", " " k " ") { print $1 ":" }' "$REG/verbs.tsv"
}
mkrk() { # <dir> <kind> <entry>... : a repo tree; a trailing / is a directory, .agents/config.yaml carries the kind
  _d="$RKD/$1"; _k="$2"; shift 2; rm -rf "$_d"; mkdir -p "$_d/.agents"; [ -z "$_k" ] || printf 'repo-kind: %s\n' "$_k" > "$_d/.agents/config.yaml"
  for _e in "$@"; do case "$_e" in */) mkdir -p "$_d/$_e" ;; justfile) vrecipes "$_k" > "$_d/justfile" ;; *) mkdir -p "$_d/$(dirname "$_e")"; : > "$_d/$_e" ;; esac; done
  printf '%s' "$_d"
}
rk() { sh "$LN" --check repo-kind "$1" 2>&1; }
