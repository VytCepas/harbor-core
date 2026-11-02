#!/usr/bin/env sh
# doc.refs-* rules (harbor#996 E1): bin/doc-refs.sh judges the entry docs, bin/lint-conventions.sh relays it.
# Each rule is proven on fixture trees under fixtures/doc-refs/ and on trees built here, so nothing depends on the live docs.
# The red proofs: plant a dangling `<system>:path` and the check goes red; mark it `example:` and it does not.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
TOOL="$T_ROOT/bin/doc-refs.sh"; FX="$T_ROOT/fixtures/doc-refs"; REG="$T_ROOT/standards/naming"
# mktree <name> → an empty git checkout holding bin/tool.sh, plus a sibling checkout "sysb" holding src/real.py
mktree() {
  _t="$T_TMP/$1"; mkdir -p "$_t/bin" "$T_TMP/$1-sysb/src"; printf 'x\n' > "$_t/bin/tool.sh"; : > "$T_TMP/$1-sysb/src/real.py"
  ( cd "$_t" && git init -q . && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
  printf '%s' "$_t"
}
commit() { ( cd "$1" && git add -A && git commit -qm c --allow-empty ) >/dev/null 2>&1; }
# DR <tree> [args] → the A/V/S records on stdout, with the sibling checkout wired
DR() { _t="$1"; shift; sh "$TOOL" --root "$_t" --registry "$REG" --no-registry --system "sysb=$_t-sysb" --format findings "$@" 2>/dev/null; }
rc_of() { _t="$1"; shift; sh "$TOOL" --root "$_t" --registry "$REG" --no-registry --system "sysb=$_t-sysb" "$@" >/dev/null 2>&1; echo $?; }
setmode() { # <root> <rule> <mode>
  awk -F'\t' -v OFS='\t' -v r="$2" -v m="$3" '$1 == r { $2 = m } { print }' "$1/standards/naming/controls.tsv" > "$1/c.tmp" && mv "$1/c.tmp" "$1/standards/naming/controls.tsv"; }
mkroot() { _r="$T_TMP/$1"; mkdir -p "$_r/fixtures" "$_r/standards"; cp -R "$FX" "$_r/fixtures/doc-refs"; cp -R "$REG" "$_r/standards/naming"; printf '%s' "$_r"; }

t_section "the self-test passes, and its red log names both rules"
t_exit "--self-test exits 0" 0 sh "$TOOL" --self-test
RED0="$T_TMP/red0"; : > "$RED0"; LINT_REDLOG="$RED0" sh "$TOOL" --self-test >/dev/null 2>&1
t_eq "...the log a caller's LINT_REDLOG reads" "doc.refs-resolve doc.refs-stale" "$(sort -u "$RED0" | tr '\n' ' ' | sed 's/ $//')"

t_section "RED PROOF: a planted dangling <system>:path turns the check red; an example: marker does not"
D="$(mktree plant)"; printf '# x\n\nSee `sysb:src/real.py`.\n' > "$D/README.md"; commit "$D"
t_eq "a resolving <system>:path -> no finding" "" "$(DR "$D" | grep '^A')"
t_exit "...and exit 0" 0 sh "$TOOL" --root "$D" --registry "$REG" --no-registry --system "sysb=$D-sysb"
printf '# x\n\nSee `sysb:src/planted-dead.py`.\n' > "$D/README.md"; commit "$D"
t_has "the planted dangling path is a finding" "$(DR "$D")" "A	doc.refs-resolve	README.md -> sysb:src/planted-dead.py"
RED="$T_TMP/red-plant"; : > "$RED"; LINT_REDLOG="$RED" sh "$TOOL" --root "$D" --registry "$REG" --no-registry --system "sysb=$D-sysb" >/dev/null 2>&1
t_eq "...and the rule is red in the log" "doc.refs-resolve" "$(sort -u "$RED")"
printf '# x\n\nSee `example:sysb:src/planted-dead.py`.\n' > "$D/README.md"; commit "$D"
t_eq "the same path behind an example: marker is no finding" "" "$(DR "$D" | grep '^A')"
t_has "...and is counted, so the marker cannot hide it unseen" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --system "sysb=$D-sysb" 2>&1)" "1 example-marked"
printf '# x\n\nSee `sysb:src/planted-dead.py` (for example: `bin/gone.sh`).\n' > "$D/README.md"; commit "$D"
t_has "a line-level 'example:' exempts only its own line's citations... the system path on the same line too" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --system "sysb=$D-sysb" 2>&1)" "2 example-marked"
printf '# x\n\nSee `sysb:src/planted-dead.py`.\n\nAnd for example: `bin/gone.sh`.\n' > "$D/README.md"; commit "$D"
t_has "...but not another line's" "$(DR "$D")" "A	doc.refs-resolve	README.md -> sysb:src/planted-dead.py"
t_hasnt "...while its own line's is exempt" "$(DR "$D")" "bin/gone.sh"

t_section "an example: link target is a marker too"
D="$(mktree link-marker)"; printf 'A produced page: [report](example:out/report.html) and [dead](out/report.html).\n' > "$D/README.md"; commit "$D"
OUT="$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry 2>&1)"
t_has "an example: link target is counted as example-marked" "$OUT" "1 example-marked"
t_has "...while the same path without it is a finding" "$OUT" "README.md:1 cites out/report.html"

t_section "what is cited, and what is not"
D="$(mktree shape)"; mkdir -p "$D/docs" "$D/contracts"; : > "$D/docs/context-map.md"; : > "$D/contracts/note.md"
cat > "$D/README.md" <<'DOC'
Link [ok](contracts/note.md), [dead](contracts/gone.md), [site](https://x.org/a/gone.md), [anchor](#top), [mail](mailto:a@b.c).
Span `bin/tool.sh:3`, `bin/tool.sh#frag`, dead `bin/gone-span.sh`, a word `sh bin/gone-word.sh -v`, a dir `bin/`, a bare `GONE.md`.
Not paths: `/abs/gone.md`, `~/gone.md`, `bin/*.sh`, `bin/{a,b}.sh`, `a/b`, `and/or`, `$HOME/x.md`, `<x>/y.md`.
DOC
commit "$D"
OUT="$(DR "$D")"
t_has "a dead link" "$OUT" "README.md -> contracts/gone.md"
t_has "a dead span with a slash" "$OUT" "README.md -> bin/gone-span.sh"
t_has "a dead word inside a longer span" "$OUT" "README.md -> bin/gone-word.sh"
t_eq "...and nothing else: 3 findings" "3" "$(printf '%s\n' "$OUT" | grep -c '^A')"
t_hasnt "a bare name with no slash is prose" "$OUT" "GONE.md"
t_hasnt "a URL, an anchor and a mailto are not paths" "$OUT" "x.org"
printf '# map\n\nUp one: [bin](../bin/tool.sh), here: `./note.md` and dead `../bin/gone.sh`.\n' > "$D/docs/context-map.md"; : > "$D/docs/note.md"; commit "$D"
OUT="$(DR "$D" --doc docs/context-map.md)"
t_has "a ../ path resolves against the doc's directory, so only the dead one is found" "$OUT" "docs/context-map.md -> ../bin/gone.sh"
t_eq "...one finding" "1" "$(printf '%s\n' "$OUT" | grep -c '^A')"
t_has "the default docs include docs/context-map*.md" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry 2>&1)" "2 doc(s)"
printf '# x\n\n```sh\nsh bin/gone-in-fence.sh\n```\n' > "$D/README.md"; commit "$D"
t_eq "a fenced block is not read" "" "$(DR "$D" --doc README.md | grep '^A')"
t_has "...and its lines are counted" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --doc README.md 2>&1)" "3 fenced line(s) not read"

t_section "a system whose checkout is absent is NOT JUDGED, never resolved"
D="$(mktree absent)"; printf 'See `sysc:docs/x.md`.\n' > "$D/README.md"; commit "$D"
OUT="$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --system "sysc=$D/nowhere" 2>&1)"
t_has "the summary names the system" "$OUT" "system checkout absent: sysc"
t_hasnt "...and is not an ok line, which would read as a clean pass" "$OUT" "ok: no finding"
t_has "...it says no finding in the PART judged" "$OUT" "no finding in the part judged"
t_has "a system that IS this root resolves in the root (--self)" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --self me --system "me=$T_TMP/elsewhere" 2>&1)" "0 dangling"

t_section "exit codes: 3 when nothing was judged, 2 on usage"
mkdir -p "$T_TMP/nodoc"
t_exit "no entry doc is unchecked (3), never a pass" 3 sh "$TOOL" --root "$T_TMP/nodoc" --registry "$REG" --no-registry
t_exit "an unknown option" 2 sh "$TOOL" --nope
t_exit "a stray argument" 2 sh "$TOOL" extra
t_exit "--format with anything else" 2 sh "$TOOL" --format json
t_exit "--stale-after 0" 2 sh "$TOOL" --stale-after 0
t_exit "--system without =" 2 sh "$TOOL" --system sysb
t_exit "a missing controls.tsv is unchecked (3)" 3 sh "$TOOL" --root "$D" --registry "$T_TMP/no-registry" --no-registry
t_exit "--help exits 0" 0 sh "$TOOL" --help
t_has "--list reads the modes from controls.tsv" "$(sh "$TOOL" --list)" "doc.refs-resolve   warn"

t_section "the modes are controls.tsv's: warn prints, shadow records only, block fails"
for _id in doc.refs-resolve doc.refs-stale doc.refs-conform; do
  t_eq "$_id is warn in the registry" "warn" "$(awk -F'\t' -v i="$_id" '$1 == i { print $2 }' "$REG/controls.tsv")"
done
D="$(mktree modes)"; printf 'See `bin/gone.sh`.\n' > "$D/README.md"; commit "$D"
R="$(mkroot modes-root)"; setmode "$R" doc.refs-resolve shadow
OUT="$(sh "$TOOL" --root "$D" --registry "$R/standards/naming" --no-registry 2>&1)"
t_hasnt "shadow prints no finding" "$OUT
x" "[doc.refs-resolve]"
RED="$T_TMP/red-shadow"; : > "$RED"; LINT_REDLOG="$RED" sh "$TOOL" --root "$D" --registry "$R/standards/naming" --no-registry >/dev/null 2>&1
t_eq "...but the rule is red in the log" "doc.refs-resolve" "$(sort -u "$RED")"
t_eq "...and still exits 0" "0" "$(sh "$TOOL" --root "$D" --registry "$R/standards/naming" --no-registry >/dev/null 2>&1; echo $?)"
R="$(mkroot block-root)"; setmode "$R" doc.refs-resolve block
t_eq "block exits 1" "1" "$(sh "$TOOL" --root "$D" --registry "$R/standards/naming" --no-registry >/dev/null 2>&1; echo $?)"
t_has "...and a V record" "$(sh "$TOOL" --root "$D" --registry "$R/standards/naming" --no-registry --format findings 2>/dev/null)" "V	doc.refs-resolve"

t_section "staleness counts commits that touched a cited FILE since the doc changed"
D="$(mktree age)"; printf 'It describes `bin/tool.sh` and the dir `bin/`.\n' > "$D/README.md"; commit "$D"
for _i in 1 2 3; do printf '%s\n' "$_i" >> "$D/bin/tool.sh"; commit "$D"; done
t_has "3 commits behind at threshold 3 is a finding" "$(DR "$D" --stale-after 3)" "A	doc.refs-stale	README.md"
t_eq "...and at threshold 4 it is not" "" "$(DR "$D" --stale-after 4 | grep '^A')"
printf 'y\n' > "$D/unrelated.txt"; commit "$D"
t_eq "a commit touching a path the doc does not cite does not count" "" "$(DR "$D" --stale-after 5 | grep '^A')"
printf 'It describes the dir `bin/` only.\n' > "$D/README.md"; commit "$D"
for _i in 1 2 3; do printf '%s\n' "$_i" >> "$D/bin/tool.sh"; commit "$D"; done
t_eq "a cited directory is a claim it exists, not about its contents: not counted" "" "$(DR "$D" --stale-after 1 | grep '^A')"
D="$(mktree spelling)"; mkdir -p "$D/docs"; printf 'See [t](../bin/tool.sh) and `./bin/tool.sh`.\n' > "$D/docs/context-map.md"; commit "$D"
for _i in 1 2; do printf '%s\n' "$_i" >> "$D/bin/tool.sh"; commit "$D"; done
t_has "two spellings of one file are one cited path" "$(sh "$TOOL" --root "$D" --registry "$REG" --no-registry --stale-after 2 2>&1)" "2 commits behind the 1 path(s) it cites"
S="$T_TMP/age-shallow"; git clone -q --depth 1 "file://$D" "$S" >/dev/null 2>&1
t_has "a shallow clone cannot count: said, not zero" "$(sh "$TOOL" --root "$S" --registry "$REG" --no-registry 2>&1)" "staleness not judged (shallow clone)"

t_section "red proof: a fixture that stops yielding its id, or yields one it did not expect, fails the self-test"
R="$(mkroot red-expect)"; : > "$R/fixtures/doc-refs/dangling/expect.tsv"
t_exit "an expected id removed -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-doc)"; printf '# fixed\n' > "$R/fixtures/doc-refs/dangling/doc.md"
t_exit "the dead citation removed from the doc -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-extra)"; printf 'And `bin/gone-extra.sh`.\n' >> "$R/fixtures/doc-refs/clean/doc.md"
t_exit "a pass fixture that goes red -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-marker)"; printf '# marker gone\n\nSee `out/report.html` and `bin/gone.sh`.\n' > "$R/fixtures/doc-refs/example-marked/doc.md"
t_exit "the example: marker removed from its fixture -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
R="$(mkroot red-rule)"; rm -r "$R/fixtures/doc-refs/stale"
t_exit "a rule no fixture turns red -> exit 1" 1 sh "$TOOL" --self-test --root "$R" --registry "$R/standards/naming"
t_exit "no fixtures at all is unchecked, not a pass" 3 sh "$TOOL" --self-test --root "$T_TMP/home" --registry "$REG"

t_section "--fleet: one count row per registry checkout, and an absent checkout is a row, not silence"
P="$T_TMP/port"; mkdir -p "$P/alpha" "$P/beta" "$P/harbor-private"
printf '# a\n\nSee `bin/gone.sh`.\n' > "$P/alpha/README.md"; mkdir -p "$P/beta"; : > "$P/beta/AGENTS.md"
for _r in alpha beta; do ( cd "$P/$_r" && git init -q . && git config user.email t@t && git config user.name t && git add -A && git commit -qm c ) >/dev/null 2>&1; done
printf 'id\tpath\tkind\tremote\nalpha\talpha\tworkload\t-\nbeta\tbeta\tworkload\t-\ngamma\tgamma\tworkload\t-\n' > "$P/harbor-private/repos.tsv"
OUT="$(PORT_ROOT="$P" sh "$TOOL" --fleet --registry "$REG" 2>/dev/null)"
t_has "alpha: 1 doc, 1 citation, 1 dangling" "$OUT" "alpha	1	1	1	0	"
t_has "beta: a doc with no citation" "$OUT" "beta	1	0	0	0	"
t_has "gamma: no checkout, said" "$OUT" "gamma	-	-	-	-	checkout absent"

t_section "bin/lint-conventions.sh relays the findings as advisories and exits clean"
D="$T_TMP/relay"; mkdir -p "$D/bin" "$D/standards"
cp "$T_ROOT/bin/doc-refs.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$D/bin/"; mkdir -p "$D/contracts"; cp "$T_ROOT/contracts/roots.tsv" "$D/contracts/"
cp -R "$REG" "$D/standards/naming"
printf '# r\n\nSee `bin/gone-relay.sh`.\n' > "$D/README.md"
( cd "$D" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
OUT="$(lint1 doc.refs-conform "$D")"
t_has "the advisory carries the relayed id and the citation" "$OUT" "ADVISORY [doc.refs-conform] [doc.refs-resolve] README.md -> bin/gone-relay.sh"
t_eq "no violation: a warn rule never fails the run" "0" "$(vcount "$OUT")"
RED="$T_TMP/red2"; : > "$RED"; LINT_REDLOG="$RED" lint1 doc.refs-conform "$D" >/dev/null
t_has "the red log names the doc rule, not the relay" "$(cat "$RED")" "doc.refs-resolve"
t_hasnt "...and never the relay id for a warn finding" "$(cat "$RED"; echo x)" "doc.refs-conform"
printf '# r\n\nSee `bin/doc-refs.sh`.\n' > "$D/README.md"
t_has "a clean tree says what it judged" "$(lint1 doc.refs-conform "$D")" "no finding in 1 doc(s)"
t_hasnt "...with the tool's ok: prefix stripped, as BSD sed strips it too" "$(lint1 doc.refs-conform "$D")" "ok: no finding"
D="$T_TMP/bare"; mkdir -p "$D/bin"
t_has "a tree without the tool is skipped, said so" "$(lint1 doc.refs-conform "$D")" "skip: no bin/doc-refs.sh"
t_eq "...with no violation" "0" "$(vcount "$(lint1 doc.refs-conform "$D")")"

t_done
