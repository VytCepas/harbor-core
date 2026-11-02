#!/usr/bin/env sh
# module.* rules (harbor#996 C1): a graph that is missing, stale or not a graph is UNCHECKED (exit 3), never a pass.
# Each case is a throwaway git checkout whose graph doc-graph-generate.sh builds, so "stale" means what graph-gen --check says.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/lint-module.sh"; REG="$T_ROOT/standards/naming"
LM() { _r="$1"; shift; sh "$TOOL" --root "$_r" "$@" 2>&1; }
mk() { # <name> → a checkout with the registry, one source file and one generated file
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/standards"
  cp -R "$REG" "$_d/standards/naming"
  printf '#!/bin/sh\n: reads nothing\n' > "$_d/bin/alpha-run.sh"
  printf 'build/\n' > "$_d/.gitignore"   # as in the real tree: a tracked graph would scan itself and never converge
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
rc() { sh "$TOOL" --root "$@" >/dev/null 2>&1; echo $?; }

t_section "a missing graph is unchecked, and says how to build it"
D="$(mk missing)"
t_eq "no build/graph.tsv -> exit 3" "3" "$(rc "$D")"
t_has "...naming the fix" "$(LM "$D")" "sh bin/doc-graph-generate.sh"
t_hasnt "...and never a 'no finding' pass line" "$(LM "$D")" "no finding"

t_section "an explicit graph that is absent or is not a graph is unchecked"
t_eq "--graph to a missing file -> exit 3" "3" "$(rc "$D" --graph "$T_TMP/nope.tsv")"
printf 'just some text\n' > "$T_TMP/junk.tsv"
t_eq "--graph to a file that is not a graph -> exit 3" "3" "$(rc "$D" --graph "$T_TMP/junk.tsv")"
printf '# graph.tsv (harbor#996) - x\nno header here\n' > "$T_TMP/nohdr.tsv"
t_eq "--graph without the edge header -> exit 3" "3" "$(rc "$D" --graph "$T_TMP/nohdr.tsv")"

t_section "usage errors are 2"
t_eq "an unknown option" "2" "$(rc "$D" --nope)"
t_eq "a stray argument" "2" "$(rc "$D" extra)"
t_eq "--format with anything else" "2" "$(rc "$D" --format json)"

if command -v python3 >/dev/null 2>&1; then
  t_section "a current graph is judged; a stale one is unchecked"
  D="$(mk stale)"; sh "$T_ROOT/bin/doc-graph-generate.sh" --root "$D" >/dev/null 2>&1
  t_eq "a graph just built -> exit 0" "0" "$(rc "$D")"
  t_has "...and judged it" "$(LM "$D")" "no finding"
  printf '#!/bin/sh\n: calls bin/alpha-run.sh\n' > "$D/bin/beta-run.sh"
  ( cd "$D" && git add -A ) >/dev/null 2>&1
  t_eq "a tracked file added since -> stale -> exit 3" "3" "$(rc "$D")"
  t_has "...said stale, with the fix" "$(LM "$D")" "is stale"
  t_hasnt "...and not judged" "$(LM "$D")" "no finding"
  sh "$T_ROOT/bin/doc-graph-generate.sh" --root "$D" >/dev/null 2>&1
  t_eq "rebuilt -> exit 0 again" "0" "$(rc "$D")"
  printf '# now calls bin/beta-run.sh\n' >> "$D/bin/alpha-run.sh"; ( cd "$D" && git add -A ) >/dev/null 2>&1
  t_eq "a tracked file edited to add an edge since -> exit 3" "3" "$(rc "$D")"
  t_eq "--graph vouches for itself: the same stale file, judged" "0" "$(rc "$D" --graph "$D/build/graph.tsv")"
else
  t_section "without python3 the graph cannot be shown current"
  D="$(mk nopy)"; mkdir -p "$D/build"; printf '# graph.tsv (harbor#996) - x\nedge\tfrom\tto\tsite\n' > "$D/build/graph.tsv"
  t_eq "a graph on disk but no python3 -> exit 3" "3" "$(rc "$D")"
fi

t_done
