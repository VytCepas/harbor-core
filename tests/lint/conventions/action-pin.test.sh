#!/usr/bin/env sh
# ci.action-sha-pinned (harbor#1426): a workflow whose uses: is a mutable tag is red; a full SHA with its version comment is green.
# The fixture workflows are built in a throwaway tree at run time, so this file writes nothing into the repo's own workflow folder.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
R=ci.action-sha-pinned
SHA=0123456789abcdef0123456789abcdef01234567
WF=".github/workflows"
mk() { # <name> <uses line…> → a tree with one workflow holding those steps
  _d="$T_TMP/$1"; mkdir -p "$_d/$WF"; shift
  { printf 'name: x\non: push\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n'; for _u in "$@"; do printf '      - %s\n' "$_u"; done; } > "$_d/$WF/x.yml"
  printf '%s' "$_d"
}
n() { printf '%s\n' "$1" | grep -c "ADVISORY \[$R\]"; }

t_section "a mutable tag is red, and names the file, the line and the action"
OUT="$(lint1 $R "$(mk tag "uses: actions/checkout@v5")")"
t_eq "one finding" "1" "$(n "$OUT")"
t_has "names the workflow and line" "$OUT" "$WF/x.yml:7 actions/checkout@v5 is a mutable tag"

t_section "a branch ref is red too"
t_eq "@main" "1" "$(n "$(lint1 $R "$(mk br "uses: actions/checkout@main")")")"

t_section "a full SHA with a version comment is green"
t_eq "none" "0" "$(n "$(lint1 $R "$(mk ok "uses: actions/checkout@$SHA # v6.0.3")")")"

t_section "a full SHA with no version comment is red"
OUT="$(lint1 $R "$(mk nocm "uses: actions/checkout@$SHA")")"
t_eq "one" "1" "$(n "$OUT")"; t_has "says why" "$OUT" "carries no # version comment"

t_section "a local action and a docker image are not tags"
t_eq "none" "0" "$(n "$(lint1 $R "$(mk loc "uses: ./local-action" "uses: docker://alpine:3")")")"

t_section "a short SHA is red"
t_eq "one" "1" "$(n "$(lint1 $R "$(mk short "uses: actions/checkout@0123456 # v6")")")"

t_section "a tree with no workflows is silent"
mkdir -p "$T_TMP/none"; t_eq "none" "0" "$(n "$(lint1 $R "$T_TMP/none")")"
t_done
