#!/usr/bin/env sh
# bin/docs-gen.sh (harbor#173) on the one log format (harbor#771): the page and the token table are data
# on stdout, the tool's own lines are log-lib's on stderr, and each exit code agrees with its summary.
# It runs a copy of the generator in a fixture tree, so a case never depends on the repo's own prose.
. "$(dirname "$0")/../lib/core.sh"; t_init
FX="$T_TMP/fx"; mkdir -p "$FX/bin" "$FX/docs/src"
cp "$T_ROOT/bin/docs-gen.sh" "$T_ROOT/bin/log-lib.sh" "$FX/bin/"
DG="$FX/bin/docs-gen.sh"; IDX="$FX/docs/index.html"
printf '<section><h2 id="a">A</h2>\n<p>prose</p></section>\n' > "$FX/docs/src/10-a.html"
dg() { sh "$DG" "$@" > "$T_TMP/o" 2> "$T_TMP/e"; RC=$?; }  # fills $T_TMP/o (stdout), $T_TMP/e (stderr), $RC
lines() { printf '%s\n' "$@"; printf x; }
got() { cat "$1"; printf x; }

t_section "print: the page, and only the page, on stdout"
dg
t_eq 'exit 0' 0 "$RC"
t_eq 'the first line opens the document' '<!doctype html>' "$(head -1 "$T_TMP/o")"
t_eq 'the last line closes it' '</html>' "$(tail -1 "$T_TMP/o")"
t_eq 'nothing on stderr' '' "$(cat "$T_TMP/e")"
cp "$T_TMP/o" "$T_TMP/page"

t_section "--check builds to a temp file: green with no page on disk, and it writes none (harbor#1197)"
dg --check
t_eq 'exit 0' 0 "$RC"
t_eq 'the log: one ok line naming the build, then the summary' \
  "$(lines '── docs-gen · check' "  ok: the page builds from docs/src ($(wc -c < "$T_TMP/page" | tr -d ' ') bytes, no unknown hole)" \
     'docs-gen: 1 ok, 0 failed, 0 warnings')" "$(got "$T_TMP/e")"
t_eq 'stdout stays empty' '' "$(cat "$T_TMP/o")"
t_eq 'it wrote no docs/index.html and left no temp file' 'src' "$(ls "$FX/docs" | tr '\n' ' ' | sed 's/ $//')"

t_section "--apply: writes the page it prints, and says so in one ok line"
dg --apply
t_eq 'exit 0' 0 "$RC"
t_eq 'the log, exactly' \
  "$(lines '── docs-gen · apply' "  ok: wrote docs/index.html ($(wc -c < "$T_TMP/page" | tr -d ' ') bytes)" \
     'docs-gen: 1 ok, 0 failed, 0 warnings')" "$(got "$T_TMP/e")"
t_eq 'stdout stays empty' '' "$(cat "$T_TMP/o")"
t_eq 'the file is the printed page, byte for byte' same "$(cmp -s "$T_TMP/page" "$IDX" && echo same || echo differs)"
t_eq 'no temp file is left' 'index.html src' "$(ls "$FX/docs" | tr '\n' ' ' | sed 's/ $//')"

t_section "--check after --apply: the built page is left exactly as it was, whatever the prose says"
cp "$IDX" "$T_TMP/idx.applied"
printf '<p>an edit to the prose</p>\n' >> "$FX/docs/src/10-a.html"
dg --check
t_eq 'a changed prose is not "stale": exit 0' 0 "$RC"
t_eq '...and --check did not rebuild or touch the page' same "$(cmp -s "$T_TMP/idx.applied" "$IDX" && echo same || echo changed)"
t_eq '...nor leave a temp file' 'index.html src' "$(ls "$FX/docs" | tr '\n' ' ' | sed 's/ $//')"
dg --apply
t_has 'the page after --apply carries the edit' "$(cat "$IDX")" '<p>an edit to the prose</p>'

t_section "an unknown token is a build failure: FAIL, fix, summary on stderr — never inside the page"
cp "$IDX" "$T_TMP/idx.before"
printf '<section><h2 id="b">B</h2>\n<!--gen:nope-->\n</section>\n' > "$FX/docs/src/20-b.html"
dg
t_eq 'print: exit 3, as before' 3 "$RC"
t_has 'a FAIL names the token' "$(cat "$T_TMP/e")" '  FAIL: unknown token <!--gen:nope--> in the prose'
t_has '...then its fix line' "$(cat "$T_TMP/e")" '  fix: none automatic — see bin/docs-gen.sh'
t_eq '...then the summary' 'docs-gen: 0 ok, 1 failed, 0 warnings' "$(tail -1 "$T_TMP/e")"
t_hasnt 'the page on stdout carries no log line' "$(cat "$T_TMP/o")" 'FAIL'
dg --check
t_eq 'check: exit 3, the same FAIL on stderr' 3 "$RC"
t_has 'check: it names the token' "$(cat "$T_TMP/e")" '  FAIL: unknown token <!--gen:nope--> in the prose'
t_eq 'check: no temp file is left in the tree' 'index.html src' "$(ls "$FX/docs" | tr '\n' ' ' | sed 's/ $//')"
t_eq 'check: nor in TMPDIR (the exit trap removes it)' 0 "$(find "$TMPDIR" -name 'docs-gen.check.*' 2>/dev/null | grep -c . || :)"
dg --apply
t_eq 'apply: exit 3' 3 "$RC"
t_eq 'apply: docs/index.html is untouched' same "$(cmp -s "$T_TMP/idx.before" "$IDX" && echo same || echo changed)"
t_eq 'apply: no temp file is left' 'index.html src' "$(ls "$FX/docs" | tr '\n' ' ' | sed 's/ $//')"

t_section "--tokens stays a data table; an unknown flag is a usage error, not a run"
dg --tokens
t_eq 'exit 0' 0 "$RC"
t_eq 'one row per token, its state and its file' 'nope MISSING docs/src/20-b.html' "$(tr -s ' ' < "$T_TMP/o")"
t_eq 'nothing on stderr' '' "$(cat "$T_TMP/e")"
dg --frobnicate
t_eq 'an unknown flag exits 2' 2 "$RC"
t_has '...and names it' "$(cat "$T_TMP/e")" 'docs-gen: unknown flag --frobnicate'
t_hasnt '...with no summary line, since no run started' "$(cat "$T_TMP/e")" 'docs-gen: 0 ok'
t_has 'the positive control: a run that did start has one' "$(sh "$DG" --check 2>&1 >/dev/null)" 'docs-gen: 0 ok'
t_done
