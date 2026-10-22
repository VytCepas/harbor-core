#!/usr/bin/env sh
# bin/deploy-push.sh, bin/layers.sh and lint-leaks.sh's core scope: the one-way core export (harbor#1149).
# Each case is a throwaway source checkout, a throwaway export target and a throwaway private layer.
# The "secret" below is a made-up word, never a real entity.
. "$(dirname "$0")/../lib/core.sh"; t_init
unset HARBOR_IN_SUITE
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t.test; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t.test
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
HDR='id	kind	pattern	note'
LHDR='path	layer	note'
mkdir -p "$T_TMP/pv"; { printf '%s\n' "$HDR"; printf 'k1\tword\tZorblax\tn\n'; } > "$T_TMP/pv/leaks.tsv"
PV="$T_TMP/pv"
mkdir -p "$T_TMP/pv/inject.d/box"; printf '# name\tpath\twhat\nzorbcorp\t~/zorbcorp\ta made-up workload repo\n' > "$T_TMP/pv/inject.d/box/projects.tsv"

mk() { # <name> → a source checkout: core bin and docs, a dev notes file, layers.tsv, the tools under test
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS" "$_d/docs" "$_d/EVALS-DATA"
  cp "$T_ROOT/bin/deploy-push.sh" "$T_ROOT/bin/layers.sh" "$T_ROOT/bin/lint-leaks.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/harbor" "$_d/bin/"
  cp "$T_ROOT/bin/lint-domain.sh" "$T_ROOT/bin/pass-score.sh" "$_d/bin/"
  : > "$_d/bin/status-gen.sh"
  # redteam-corpus's row reads --print; a stub stands in for the check (its own suite is tests/checks/redteam-corpus-test.sh)
  printf '#!/bin/sh\n[ "$RTSTUB_RED" = 1 ] && { echo "  FAIL: stub: 1 not accepted"; exit 1; }\necho "  ok: stub"\n' > "$_d/bin/redteam-corpus.sh"
  cp "$T_ROOT/CONTRACTS/leak-patterns.tsv" "$_d/CONTRACTS/"
  # The release gate's other rows (harbor#1274), green: a made-up workload term, a pass table ending at zero criticals.
  printf 'id\tpattern\tnote\nquuxtool\tquuxtool\tfixture\n' > "$_d/CONTRACTS/domain-terms.tsv"
  printf 'path\tterm\treason\n' > "$_d/CONTRACTS/domain-allow.tsv"
  printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 0 |\n' > "$_d/FLOOR.md"
  printf '# fixture\n%s\nbin/\tcore\ttools\nCONTRACTS/\tcore\tcontracts\ndocs/\tcore\tdocs\nEVALS-DATA/\tdev\tbulk\nFLOOR.md\tcore\tpasses\nNOTES.md\tdev\tnotes\nREADME.md\tcore\treadme\n' "$LHDR" > "$_d/CONTRACTS/layers.tsv"
  printf 'hello\n' > "$_d/docs/a.md"; printf 'a client Zorblax here\n' > "$_d/NOTES.md"; printf 'Zorblax data\n' > "$_d/EVALS-DATA/e.txt"
  printf 'readme\n' > "$_d/README.md"
  ( cd "$_d" && git init -q . && git add -A && git commit -qm src ) >/dev/null 2>&1
  printf '%s' "$_d"
}
tgt() { _t="$T_TMP/t-$1"; mkdir -p "$_t"; ( cd "$_t" && git init -q . ) >/dev/null 2>&1; printf '%s' "$_t"; }
push() { _s="$1"; shift; HARBOR_ROOT="$_s" HARBOR_SCOPE_PRIVATE="${PVX:-$PV}" sh "$_s/bin/deploy-push.sh" "$@" 2>&1; }
prc() { _s="$1"; shift; HARBOR_ROOT="$_s" HARBOR_SCOPE_PRIVATE="${PVX:-$PV}" sh "$_s/bin/deploy-push.sh" "$@" >/dev/null 2>&1; echo $?; }
ncommits() { git -C "$1" rev-list --count HEAD 2>/dev/null || echo 0; }
files() { git -C "$1" ls-tree -r --name-only HEAD 2>/dev/null | tr '\n' ' '; }
unset PVX

t_section "a clean fixture: exactly one commit holding the core set"
S="$(mk clean)"; T="$(tgt clean)"
t_eq "dry-run is green" "0" "$(prc "$S" --dry-run)"
t_hasnt "...and lists no dev path" "$(push "$S" --dry-run)" "EVALS-DATA"
t_eq "dry-run wrote nothing to anything" "0" "$(ncommits "$T")"
t_eq "push is green" "0" "$(prc "$S" "$T")"
t_eq "...one commit" "1" "$(ncommits "$T")"
t_eq "...exactly the core files" "CONTRACTS/domain-allow.tsv CONTRACTS/domain-terms.tsv CONTRACTS/layers.tsv CONTRACTS/leak-patterns.tsv FLOOR.md README.md bin/deploy-push.sh bin/harbor bin/layers.sh bin/lint-domain.sh bin/lint-leaks.sh bin/log-lib.sh bin/pass-score.sh bin/redteam-corpus.sh bin/status-gen.sh docs/a.md " "$(files "$T")"
t_has "...the message names the source sha" "$(git -C "$T" log -1 --format=%B)" "$(git -C "$S" rev-parse HEAD)"
t_eq "...no tags" "" "$(git -C "$T" tag)"
t_eq "...the target is clean" "" "$(git -C "$T" status --porcelain)"
t_eq "a second push of the same source adds no commit" "0" "$(prc "$S" "$T")"
t_eq "...still one commit" "1" "$(ncommits "$T")"
printf 'more\n' > "$S/docs/b.md"; ( cd "$S" && git add -A && git commit -qm two ) >/dev/null 2>&1
t_eq "a changed source pushes again" "0" "$(prc "$S" "$T")"
t_eq "...as one more commit, not the source history" "2" "$(ncommits "$T")"
t_has "...holding the new file" "$(files "$T")" "docs/b.md"

t_section "a planted leak: refused, and the target is untouched"
S="$(mk leak)"; T="$(tgt leak)"
printf 'owned by Zorblax\n' > "$S/docs/leak.md"; ( cd "$S" && git add -A && git commit -qm leak ) >/dev/null 2>&1
t_eq "push is red" "1" "$(prc "$S" "$T")"
t_has "...and says the gate" "$(push "$S" "$T")" "leak occurrence"
t_hasnt "...and never prints the pattern" "$(push "$S" "$T")" "Zorblax"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
t_eq "...no file in the target" "" "$(find "$T" -path "$T/.git" -prune -o -type f -print)"
t_eq "dry-run reports red too" "1" "$(prc "$S" --dry-run)"
T2="$(tgt leak2)"; ( cd "$T2" && echo keep > keep.txt && git add -A && git commit -qm seed ) >/dev/null 2>&1
H="$(git -C "$T2" rev-parse HEAD)"; prc "$S" "$T2" >/dev/null
t_eq "a target with history keeps its HEAD" "$H" "$(git -C "$T2" rev-parse HEAD)"
t_eq "...and its file" "keep.txt" "$(ls "$T2")"
S="$(mk core-leak)"; T="$(tgt core-leak)"
printf 'p=%s/jdoe/x\n' /Users > "$S/docs/path.md"; ( cd "$S" && git add -A && git commit -qm p ) >/dev/null 2>&1
t_eq "a core-pattern leak (a home path) is red as well" "1" "$(prc "$S" "$T")"

t_section "a planted workload term: the domain ratchet refuses the export (harbor#1274)"
S="$(mk domain)"; T="$(tgt domain)"
printf 'set up quuxtool here\n' > "$S/docs/tool.md"; ( cd "$S" && git add -A && git commit -qm tool ) >/dev/null 2>&1
t_eq "dry-run is red with one hit" "1" "$(prc "$S" --dry-run)"
t_has "...on the ratchet's own row" "$(push "$S" --dry-run)" "FAIL: release gate · domain ratchet 0: red"
t_eq "push is red" "1" "$(prc "$S" "$T")"
t_has "...and says why" "$(push "$S" "$T")" "the domain ratchet is above zero"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
printf 'path\tterm\treason\ndocs/tool.md\tquuxtool\tharbor logic must name it\n' > "$S/CONTRACTS/domain-allow.tsv"
( cd "$S" && git add -A && git commit -qm allow ) >/dev/null 2>&1
t_eq "the same hit in an allow-listed path is green" "0" "$(prc "$S" --dry-run)"

t_section "a dev-only file that names the secret does not block"
S="$(mk devleak)"; T="$(tgt devleak)"
t_eq "the fixture holds the secret in NOTES.md and EVALS-DATA" "2" "$(git -C "$S" grep -l Zorblax | wc -l | tr -d ' ')"
t_eq "push is green" "0" "$(prc "$S" "$T")"
t_hasnt "...and NOTES.md is not exported" "$(files "$T")" "NOTES.md"

t_section "the built page rides in the snapshot: the stage builds it, a failed build refuses (harbor#1197)"
# docs/index.html is not committed, so the source has none; the export runs the stage's own builder and ships the result.
S="$(mk page)"; T="$(tgt page)"
printf '#!/bin/sh\ncd "$(dirname "$0")/.." || exit 1\ncase "${1:-}" in --apply) printf "<html>built %%s</html>\\n" "$(ls docs | tr "\\n" " ")" > docs/index.html ;; esac\n' > "$S/bin/docs-gen.sh"
( cd "$S" && git add -A && git commit -qm gen ) >/dev/null 2>&1
t_eq "the source carries no page" "" "$(git -C "$S" ls-files docs/index.html)"
t_eq "push is green" "0" "$(prc "$S" "$T")"
t_has "the target holds the built page" "$(files "$T")" "docs/index.html"
t_has "...built from the staged tree, not copied" "$(git -C "$T" show HEAD:docs/index.html)" "built a.md"
t_eq "...and the source checkout still has no page" "" "$(ls "$S/docs/index.html" 2>/dev/null)"
S="$(mk pagefail)"; T="$(tgt pagefail)"
printf '#!/bin/sh\necho "boom" >&2\nexit 3\n' > "$S/bin/docs-gen.sh"; ( cd "$S" && git add -A && git commit -qm badgen ) >/dev/null 2>&1
t_eq "a builder that fails: push is red" "1" "$(prc "$S" "$T")"
t_has "...naming docs-gen" "$(push "$S" "$T")" "docs-gen could not build docs/index.html"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
t_eq "...and dry-run is red too" "1" "$(prc "$S" --dry-run)"

t_section "targets that are refused"
S="$(mk refuse)"
for u in "https://example.test/x.git" "git@example.test:x/y.git" "ssh://example.test/x" "example.test:x/y"; do
  t_eq "$u" "1" "$(prc "$S" "$u")"
done
t_has "a URL is named a network remote" "$(push "$S" https://example.test/x.git)" "network remote"
t_eq "a missing directory" "1" "$(prc "$S" "$T_TMP/nonexistent")"
mkdir -p "$T_TMP/plain"; t_eq "a directory that is not a checkout" "1" "$(prc "$S" "$T_TMP/plain")"
T="$(tgt dirty)"; printf 'x\n' > "$T/stray"
t_eq "a dirty target" "1" "$(prc "$S" "$T")"
t_eq "...is left as it was" "stray" "$(ls "$T")"
T="$(tgt stable)"; git -C "$T" symbolic-ref HEAD refs/heads/stable
t_eq "a target on stable" "1" "$(prc "$S" "$T")"
t_eq "the source itself" "1" "$(prc "$S" "$S")"
t_eq "no private layer" "1" "$(PVX="$T_TMP/nopriv" prc "$S" "$(tgt nopriv)")"
t_eq "no target and no --dry-run is a usage error" "2" "$(prc "$S")"

t_section "every tracked path is classified exactly once"
S="$(mk cls)"
t_eq "the fixture is green" "0" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check >/dev/null 2>&1; echo $?)"
printf 'x\n' > "$S/stray.txt"; ( cd "$S" && git add -A && git commit -qm stray ) >/dev/null 2>&1
t_eq "a path matching no row is red" "1" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check >/dev/null 2>&1; echo $?)"
t_has "...and named" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check 2>&1)" "stray.txt matches no row"
T="$(tgt cls)"
t_eq "push refuses it too" "1" "$(prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
S="$(mk dbl)"; printf 'docs/a.md\tdev\tover\n' >> "$S/CONTRACTS/layers.tsv"; ( cd "$S" && git add -A && git commit -qm dbl ) >/dev/null 2>&1
t_eq "a path matching two rows is red" "1" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check >/dev/null 2>&1; echo $?)"
t_has "...and named" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check 2>&1)" "docs/a.md matches more than one row"
t_eq "push refuses it" "1" "$(prc "$S" "$(tgt dbl)")"
S="$(mk badrow)"; printf 'docs/x\tpublic\tn\n' >> "$S/CONTRACTS/layers.tsv"
t_eq "a row with an unknown layer is red" "1" "$(HARBOR_ROOT="$S" sh "$S/bin/layers.sh" --check >/dev/null 2>&1; echo $?)"
t_eq "the real tree is classified" "0" "$(sh "$T_ROOT/bin/layers.sh" --check >/dev/null 2>&1; echo $?)"

t_section "the ratchet counts the whole tree, dev paths included"
S="$(mk scope)"
t_eq "--zero sees a dev path despite layers.tsv" "1" "$(HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/lint-leaks.sh" --zero >/dev/null 2>&1; echo $?)"
t_has "--list names the dev notes file" "$(HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/lint-leaks.sh" --list 2>&1; echo end)" "NOTES.md"

t_section "the export scans tests and fixtures too"
S="$(mk tfx)"; T="$(tgt tfx)"
mkdir -p "$S/tests" "$S/fixtures"; printf 'tests/\tcore\tsuites\nfixtures/\tcore\tfixtures\n' >> "$S/CONTRACTS/layers.tsv"
printf 'ok\n' > "$S/tests/a.sh"; ( cd "$S" && git add -A && git commit -qm tests ) >/dev/null 2>&1
t_eq "clean tests and fixtures export" "0" "$(prc "$S" --dry-run)"
printf 'a client Zorblax fixture\n' > "$S/tests/planted.sh"; ( cd "$S" && git add -A && git commit -qm planted ) >/dev/null 2>&1
t_eq "a client term only in a staged tests/ file refuses the push" "1" "$(prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
t_hasnt "...while the ratchet scope still excludes tests/" "$(HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/lint-leaks.sh" --list 2>&1; echo end)" "tests/planted.sh"
S="$(mk fxf)"; T="$(tgt fxf)"; mkdir -p "$S/fixtures"; printf 'fixtures/\tcore\tfixtures\n' >> "$S/CONTRACTS/layers.tsv"
printf 'Zorblax\n' > "$S/fixtures/f.txt"; ( cd "$S" && git add -A && git commit -qm f ) >/dev/null 2>&1
t_eq "the same in fixtures/" "1" "$(prc "$S" "$T")"

t_section "the export gate reads binary and attribute-marked files as text (harbor#1149)"
S="$(mk nul)"; T="$(tgt nul)"
printf 'a client Zorblax here\n\0\n' > "$S/docs/nul.md"; ( cd "$S" && git add -A && git commit -qm nul ) >/dev/null 2>&1
t_eq "a leak in a file holding a NUL byte refuses the push" "1" "$(prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
S="$(mk attr)"; T="$(tgt attr)"; printf '.gitattributes\tcore\tattr\n' >> "$S/CONTRACTS/layers.tsv"
printf '*.md binary\n' > "$S/.gitattributes"; printf 'a client Zorblax here\n' > "$S/docs/attr.md"; ( cd "$S" && git add -A && git commit -qm attr ) >/dev/null 2>&1
t_eq "a leak under a .gitattributes binary marking refuses the push" "1" "$(prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
S="$(mk ign)"; T="$(tgt ign)"
printf 'leak.md\n' > "$S/docs/.gitignore"; printf 'a client Zorblax here\n' > "$S/docs/leak.md"; ( cd "$S" && git add -f -A && git commit -qm ign ) >/dev/null 2>&1
t_eq "a leak in a tracked file a .gitignore lists refuses the push" "1" "$(prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
S="$(mk own)"; printf 'Zorblax\n' > "$S/docs/own.md"
sed 's|^docs/.*|docs/\tdev\tn|' "$S/CONTRACTS/layers.tsv" > "$S/CONTRACTS/l.new"; mv "$S/CONTRACTS/l.new" "$S/CONTRACTS/layers.tsv"
( cd "$S" && git add -A && git commit -qm own ) >/dev/null 2>&1
t_eq "export mode ignores the scanned repo's own layers.tsv" "1" "$(LEAKS_EXPORT=1 HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/lint-leaks.sh" --zero >/dev/null 2>&1; echo $?)"

t_section "gitleaks scans the same stage: a secret refuses, and so does a missing scanner (harbor#1149)"
cm() { ( cd "$1" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1; }
S="$(mk gl)"; T="$(tgt gl)"
t_has "the clean fixture's dry run names the scan" "$(push "$S" --dry-run)" "gitleaks: no secret in the"
# A GitHub-token shape, joined at run time so this file holds none: tests/ is exported and gitleaks scans it too.
SEC="$(printf '%s%s%s' ghp_ Zq8LmN2pR7tY4wXc9Vb K3jHs6DfG1aQe5UoI)"
printf 'pat %s\n' "$SEC" > "$S/docs/tok.md"; cm "$S" tok
t_eq "a token-shaped literal refuses the push" "1" "$(prc "$S" "$T")"
OUT="$(push "$S" "$T")"
t_has "...named as file:rule:line" "$OUT" "docs/tok.md:github-pat:1"
t_hasnt "...never by its text" "$OUT" "Zq8LmN2pR7tY4wXc9Vb"
t_eq "...the leak gate alone was green" "0" "$(LEAKS_EXPORT=1 HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/lint-leaks.sh" --count core 2>/dev/null)"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
t_eq "...and the dry run is red" "1" "$(prc "$S" --dry-run)"
printf '[extend]\nuseDefault = true\n[allowlist]\npaths = [%s]\n' "'''docs/tok[.]md'''" > "$T_TMP/loose.toml"
t_eq "an inherited GITLEAKS_CONFIG does not loosen it" "1" "$(GITLEAKS_CONFIG="$T_TMP/loose.toml" prc "$S" --dry-run)"
cp "$T_TMP/loose.toml" "$S/.gitleaks.toml"; printf '.gitleaks.toml\tcore\tscan config\n' >> "$S/CONTRACTS/layers.tsv"; cm "$S" cfg
t_eq "the staged .gitleaks.toml is honoured" "0" "$(prc "$S" --dry-run)"
git -C "$S" rm -q .gitleaks.toml docs/tok.md; sed '/^\.gitleaks\.toml/d' "$S/CONTRACTS/layers.tsv" > "$S/l.new"; mv "$S/l.new" "$S/CONTRACTS/layers.tsv"; cm "$S" untok
t_eq "the secret removed, the push is green" "0" "$(prc "$S" "$T")"
t_eq "...one commit" "1" "$(ncommits "$T")"
# gitleaks reads the stage, never the checkout or all of HEAD: each mis-scope fails one case below.
S="$(mk glwt)"; T="$(tgt glwt)"
printf 'pat %s\n' "$SEC" > "$S/docs/tok.md"; cm "$S" tok; rm "$S/docs/tok.md"
t_eq "a secret in HEAD but deleted from the working tree still refuses the push" "1" "$(prc "$S" "$T")"
t_has "...named from the stage" "$(push "$S" "$T")" "docs/tok.md:github-pat:1"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
S="$(mk gldev)"; T="$(tgt gldev)"
printf 'pat %s\n' "$SEC" > "$S/EVALS-DATA/tok.txt"; cm "$S" devtok
t_eq "a secret only in a dev path, never staged, does not block" "0" "$(prc "$S" "$T")"
t_hasnt "...and is not exported" "$(files "$T")" "EVALS-DATA"
# The real PATH as one directory of links minus gitleaks, as tests/install/doctor does.
FARM="$T_TMP/farm"; mkdir -p "$FARM"
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
  [ -d "$_d" ] || continue
  for _b in "$_d"/*; do
    _n="${_b##*/}"; [ "$_n" != gitleaks ] || continue
    [ -x "$_b" ] && [ ! -e "$FARM/$_n" ] && ln -s "$_b" "$FARM/$_n"
  done
done
t_eq "positive control: gitleaks is gone from the farm" no "$(env PATH="$FARM" sh -c 'command -v gitleaks' >/dev/null 2>&1 && echo yes || echo no)"
S="$(mk nogl)"; T="$(tgt nogl)"
nogl() { HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" env PATH="$FARM" sh "$S/bin/deploy-push.sh" "$@" 2>&1; }
t_eq "no gitleaks refuses the push rather than skipping the scan" "1" "$(nogl "$T" >/dev/null; echo $?)"
t_has "...and says so" "$(nogl "$T")" "gitleaks is missing, so the stage was not scanned"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
t_eq "...and the dry run is red" "1" "$(nogl --dry-run >/dev/null; echo $?)"

t_section "the export names itself in repo-slug.txt, never the source repo (harbor#1149)"
slugd() { # <name> → a source whose core carries repo-slug.txt and whose origin is o/dev
  _d="$(mk "$1")"; printf '# header\n#\no/dev\n' > "$_d/CONTRACTS/repo-slug.txt"
  ( cd "$_d" && git remote add origin https://github.com/o/dev.git && git add -A && git commit -qm slug ) >/dev/null 2>&1; printf '%s' "$_d"
}
pinned() { git -C "$1" show HEAD:CONTRACTS/repo-slug.txt 2>/dev/null | grep -v '^#' | grep -v '^$'; }
S="$(slugd slug)"; T="$(tgt slug)"; git -C "$T" remote add origin git@github.com:o/core.git
t_eq "a target with a GitHub origin pushes" "0" "$(prc "$S" "$T")"
t_eq "...and the exported slug is the target's" "o/core" "$(pinned "$T")"
t_has "...the header comment is kept" "$(git -C "$T" show HEAD:CONTRACTS/repo-slug.txt)" "# header"
t_has "the dry run names the slug it would write" "$(push "$S" --dry-run "$T")" "exports as o/core"
T="$(tgt slug-none)"
t_eq "a target with no GitHub origin refuses (it would ship o/dev)" "1" "$(prc "$S" "$T")"
t_has "...and says which repo it would have named" "$(push "$S" "$T")" "name o/dev as its own repo"
t_eq "...no commit in the target" "0" "$(ncommits "$T")"
T="$(tgt slug-same)"; git -C "$T" remote add origin https://github.com/o/dev.git
t_eq "a target whose origin is the source repo refuses" "1" "$(prc "$S" "$T")"
t_has "...and says so" "$(push "$S" "$T")" "is the source repo o/dev"
S="$(mk noslug)"; T="$(tgt noslug)"
t_eq "a core with no repo-slug.txt needs no origin" "0" "$(prc "$S" "$T")"


t_section "the redteam-corpus row (decision 23 on harbor#1149): red refuses the push, and so does a missing check"
S="$(mk redteam)"; T="$(tgt redteam)"
t_eq "a red --print: dry-run is red" "1" "$(RTSTUB_RED=1 prc "$S" --dry-run)"
t_has "...naming the row" "$(RTSTUB_RED=1 push "$S" --dry-run)" "release gate · redteam-corpus: red"
t_eq "...and the push refuses" "1" "$(RTSTUB_RED=1 prc "$S" "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"
t_eq "green: the push proceeds" "0" "$(prc "$S" "$T")"
( cd "$S" && git rm -q bin/redteam-corpus.sh && git commit -qm gone ) >/dev/null 2>&1
t_has "no check at HEAD: red, never a silent pass" "$(push "$S" --dry-run)" "no bin/redteam-corpus.sh at HEAD"

t_section "harbor deploy push reaches the script"
S="$(mk disp)"; T="$(tgt disp)"
t_eq "the dispatcher routes deploy push" "0" "$(HARBOR_BIN="$S/bin" HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/harbor" deploy push "$T" >/dev/null 2>&1; echo $?)"
t_eq "...and it wrote the snapshot" "1" "$(ncommits "$T")"

t_section "--ci-base: a CI mirror's comparison base skips the two release rows, never the leak rows (harbor#1149)"
S="$(mk cibase)"; T="$(tgt cibase)"
printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 2 |\n' > "$S/FLOOR.md"; ( cd "$S" && git add -A && git commit -qm crit ) >/dev/null 2>&1
t_eq "a red pass table and a red redteam refuse a release" "1" "$(RTSTUB_RED=1 prc "$S" "$T")"
t_eq "...and --ci-base writes the base anyway" "0" "$(RTSTUB_RED=1 prc "$S" --ci-base "$T")"
t_has "...saying both rows were not run" "$(RTSTUB_RED=1 push "$S" --ci-base "$(tgt cibase2)")" "skip: release gate · redteam-corpus: not run: a CI comparison base"
S="$(mk cibaseleak)"; T="$(tgt cibaseleak)"
printf 'a Zorblax line\n' > "$S/docs/leak.md"; ( cd "$S" && git add -A && git commit -qm leak ) >/dev/null 2>&1
t_eq "a leak still refuses a --ci-base" "1" "$(prc "$S" --ci-base "$T")"
t_eq "...writing nothing" "0" "$(ncommits "$T")"

t_done
