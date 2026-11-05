#!/usr/bin/env sh
# doc-shape (harbor#1434, #1435): bin/doc-shape.sh holds docs/**/*.md to one front matter shape and a generated-by
# header equal to contracts/fresh-checks.tsv both ways. Each finding is proven red on its own fixture tree, then green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
TOOL="$T_ROOT/bin/doc-shape.sh"; REG="$T_ROOT/standards/naming"
# mk <name> → a fixture repo root holding the real registry
mk() { _r="$T_TMP/$1"; mkdir -p "$_r/docs/how-to" "$_r/docs/explanation" "$_r/contracts" "$_r/.github"; cp -R "$REG" "$_r/standards-naming"; mkdir -p "$_r/standards"; mv "$_r/standards-naming" "$_r/standards/naming"
  printf '* @someone\n' > "$_r/.github/CODEOWNERS"; printf '%s' "$_r"; }
doc() { # <root> <path> <kind> <owner> <status>
  mkdir -p "$(dirname "$1/$2")"; printf -- '---\nkind: %s\nowner: %s\nstatus: %s\n---\n\n# T\n' "$3" "$4" "$5" > "$1/$2"; }
run() { _r="$1"; shift; sh "$TOOL" --root "$_r" --strict --format findings "$@" 2>/dev/null; }
msg() { _r="$1"; shift; sh "$TOOL" --root "$_r" --strict "$@" 2>&1; }   # the message text, to tell two findings on one file apart

t_section "a conforming tree is green"
R="$(mk clean)"; doc "$R" docs/how-to/a.md how-to harbor#1 current; doc "$R" docs/explanation/b.md explanation @someone draft
t_eq "no findings" "" "$(run "$R")"
t_exit "exit 0 under --strict" 0 sh "$TOOL" --root "$R" --strict

t_section "doc.kind-folder: kind disagrees with the folder"
R="$(mk kind)"; doc "$R" docs/how-to/a.md explanation harbor#1 current
t_has "kind explanation in how-to" "$(run "$R")" "A	doc.kind-folder	docs/how-to/a.md"
t_has "...said as a folder mismatch" "$(msg "$R")" "kind is explanation but this folder holds how-to"
t_exit "--strict exits 1" 1 sh "$TOOL" --root "$R" --strict
t_exit "...warn mode exits 0 (born warn)" 0 sh "$TOOL" --root "$R"
doc "$R" docs/how-to/a.md how-to harbor#1 current
t_eq "fixed, green" "" "$(run "$R")"
R="$(mk unmapped)"; doc "$R" docs/odd/a.md how-to harbor#1 current
t_has "a folder no row names has no kind" "$(run "$R")" "A	doc.kind-folder	docs/odd/a.md"
printf 'folder\tkind\tnote\ndocs/odd/\thow-to\tx\n' > "$R/contracts/doc-folders.tsv"
t_eq "...until contracts/doc-folders.tsv names it" "" "$(run "$R")"

t_section "doc.frontmatter-fields: no front matter, no owner, a bad owner or status"
R="$(mk fields)"; printf '# T\n' > "$R/docs/how-to/bare.md"
printf -- '---\nkind: how-to\nstatus: current\n---\n' > "$R/docs/how-to/noowner.md"
doc "$R" docs/how-to/badowner.md how-to "the team" current
doc "$R" docs/how-to/badstatus.md how-to @x finished
doc "$R" docs/how-to/ok.md how-to KEY-12 current
OUT="$(run "$R")"
t_has "no front matter" "$OUT" "A	doc.frontmatter-fields	docs/how-to/bare.md"
t_has "...said as no front matter" "$(msg "$R")" "bare.md — no front matter"
t_has "no owner" "$OUT" "A	doc.frontmatter-fields	docs/how-to/noowner.md"
t_has "...said as no owner" "$(msg "$R")" "noowner.md — front matter has no owner"
t_has "owner that is neither ticket nor person" "$OUT" "A	doc.frontmatter-fields	docs/how-to/badowner.md"
t_has "status outside the set" "$OUT" "A	doc.frontmatter-fields	docs/how-to/badstatus.md"
t_hasnt "a KEY-n ticket owner is fine" "$OUT" "docs/how-to/ok.md"
R="$(mk source)"; doc "$R" docs/generated/x.md generated-doc harbor#1 generated
t_has "a generated doc needs a source and a generated-by header" "$(run "$R")" "A	doc.frontmatter-fields	docs/generated/x.md"

t_section "doc.fresh-registered: header and fresh-checks.tsv row, both ways"
R="$(mk fresh)"; printf '# generated-by: sh bin/gen.sh --write\nx\n' > "$R/out.txt"
t_has "a header with no row" "$(run "$R" --generated)" "A	doc.fresh-registered	out.txt"
t_has "...said as no row" "$(msg "$R" --generated)" "has no row for it"
printf 'out.txt\tsh bin/gen.sh --check\tsh bin/gen.sh --write\t\n' > "$R/contracts/fresh-checks.tsv"
t_eq "header and row agree: green" "" "$(run "$R" --generated)"
printf 'plain\n' > "$R/out.txt"
t_has "a row whose file lacks the header" "$(run "$R" --generated)" "A	doc.fresh-registered	out.txt"
t_has "...said as a missing header" "$(msg "$R" --generated)" "no generated-by header"
printf '<!-- generated-by: sh bin/other.sh -->\nx\n' > "$R/out.txt"
t_has "a header command that differs from the row's fix" "$(run "$R" --generated)" "A	doc.fresh-registered	out.txt"
t_has "...said as a differing command" "$(msg "$R" --generated)" "but its fresh-checks.tsv fix is"
printf 'gone.txt\tsh bin/gen.sh --check\tsh bin/gen.sh --write\t\n' > "$R/contracts/fresh-checks.tsv"; printf 'plain\n' > "$R/out.txt"
t_eq "a row whose file is absent has nothing to judge (an export tree)" "" "$(run "$R" --generated)"
printf 'a.txt\tc\tsh bin/gen.sh\t\n' > "$R/contracts/fresh-checks.tsv"; printf '// generated-by: sh bin/gen.sh\n' > "$R/a.txt"
t_eq "the // comment syntax is a header too" "" "$(run "$R" --generated)"

t_section "the mode is controls.tsv's, and a red is logged"
R="$(mk block)"; doc "$R" docs/how-to/a.md explanation harbor#1 current
awk -F'\t' -v OFS='\t' '$1 == "doc.kind-folder" { $2 = "block" } { print }' "$R/standards/naming/controls.tsv" > "$R/c.tmp" && mv "$R/c.tmp" "$R/standards/naming/controls.tsv"
t_exit "block exits 1 without --strict" 1 sh "$TOOL" --root "$R"
awk -F'\t' -v OFS='\t' '$1 == "doc.kind-folder" { $2 = "shadow" } { print }' "$R/standards/naming/controls.tsv" > "$R/c.tmp" && mv "$R/c.tmp" "$R/standards/naming/controls.tsv"
t_eq "shadow prints no record" "" "$(sh "$TOOL" --root "$R" --format findings 2>/dev/null)"
RED="$T_TMP/redlog"; : > "$RED"; LINT_REDLOG="$RED" sh "$TOOL" --root "$R" >/dev/null 2>&1
t_eq "...but the log names the control" "doc.kind-folder" "$(sort -u "$RED")"

t_section "--write is idempotent and never invents an owner"
R="$(mk apply)"; printf '# A page (harbor#77)\n\nbody\n' > "$R/docs/how-to/titled.md"; printf '# Plain\n' > "$R/docs/explanation/plain.md"
printf -- '---\nkind: how-to\nowner_issue: 9\n---\n\n# Old\n' > "$R/docs/how-to/oi.md"
( cd "$R" && git init -q . && git add -A && git -c user.name=A -c user.email='1+someone@users.noreply.github.com' commit -q -m init )
OUT="$(sh "$TOOL" --root "$R" --write --repo harbor 2>/dev/null)"
t_has "a ticket in the title is the owner" "$(cat "$R/docs/how-to/titled.md")" "owner: harbor#77"
t_has "owner_issue becomes a ticket" "$(cat "$R/docs/how-to/oi.md")" "owner: harbor#9"
t_has "the git history's author is a person" "$(cat "$R/docs/explanation/plain.md")" "owner: @someone"
t_has "kind comes from the folder" "$(cat "$R/docs/explanation/plain.md")" "kind: explanation"
t_has "status is unreviewed, not current" "$(cat "$R/docs/explanation/plain.md")" "status: unreviewed"
t_eq "the judge is green after" "" "$(run "$R" --docs)"
SUM="$(cat "$R"/docs/*/*.md | cksum)"; sh "$TOOL" --root "$R" --write --repo harbor >/dev/null 2>&1
t_eq "a second --write changes nothing" "$SUM" "$(cat "$R"/docs/*/*.md | cksum)"
R="$(mk default)"; printf '# Plain\n' > "$R/docs/how-to/plain.md"
OUT="$(sh "$TOOL" --root "$R" --write 2>/dev/null)"
t_has "no ticket and no history: the CODEOWNERS default, listed" "$OUT" "default-owner	docs/how-to/plain.md"
t_has "...written as the default" "$(cat "$R/docs/how-to/plain.md")" "owner: @someone"

t_section "doc.shape-conform: bin/lint-conventions.sh relays doc-shape's findings, warn as advisory, block as violation"
RL="$(mk relay)"; mkdir -p "$RL/bin"; cp "$T_ROOT/bin/doc-shape.sh" "$T_ROOT/bin/library-log.sh" "$RL/bin/"; printf '# T\n' > "$RL/docs/how-to/bare.md"
( cd "$RL" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
OUT="$(lint1 doc.shape-conform "$RL")"
t_has "a doc with no front matter is an advisory under the relay id" "$OUT" "ADVISORY [doc.shape-conform] [doc.frontmatter-fields] docs/how-to/bare.md"
t_eq "...and not a violation: the rules are born warn" "0" "$(vcount "$OUT")"
awk -F'\t' -v OFS='\t' '$1 == "doc.frontmatter-fields" { $2 = "block" } { print }' "$RL/standards/naming/controls.tsv" > "$RL/c.tmp" && mv "$RL/c.tmp" "$RL/standards/naming/controls.tsv"
t_has "a block row makes the same finding a violation" "$(lint1 doc.shape-conform "$RL")" "VIOLATION [doc.shape-conform] [doc.frontmatter-fields] docs/how-to/bare.md"
printf 'exit 3\n' > "$RL/bin/doc-shape.sh"
t_has "an engine that exits above 1 judged nothing, which is a violation, not a pass" "$(lint1 doc.shape-conform "$RL")" "VIOLATION [doc.shape-conform] bin/doc-shape.sh exited"

t_section "this repo conforms"
t_exit "bin/doc-shape.sh --strict is green on the tree" 0 sh "$TOOL" --root "$T_ROOT" --strict
t_done
