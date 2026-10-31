#!/usr/bin/env sh
# regen.sh (harbor#996 D) — rewrites expected/ from repo/ with the current tool. The expected files ARE the specification
# the catalog suites hold the tool to, so read the diff before committing it; never regenerate to make a red suite green.
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TOOL="$HERE/../../bin/standard-catalog.sh"
W="$(mktemp -d "${TMPDIR:-/tmp}/catalog-regen.XXXXXX")"; trap 'rm -rf "$W"' EXIT
cp -R "$HERE/repo" "$W/r"; git -C "$W/r" init -q; git -C "$W/r" add -A
sh "$TOOL" --map --root "$W/r" >/dev/null
cp "$W/r/docs/context-map.md" "$HERE/expected/context-map.txt"
git -C "$W/r" add -A
sh "$TOOL" --census --root "$W/r" >/dev/null
cp "$W/r/build/catalog.tsv" "$HERE/expected/catalog.txt"
cp "$W/r/build/catalog-findings.tsv" "$HERE/expected/findings.txt"
sh "$TOOL" --find drift --root "$W/r" > "$HERE/expected/find-drift.txt"
sh "$TOOL" --tree --root "$W/r" > "$HERE/expected/tree.txt"
sh "$TOOL" --tree --files drift --root "$W/r" > "$HERE/expected/tree-drift-files.txt"
