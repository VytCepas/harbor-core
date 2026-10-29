#!/usr/bin/env sh
# bin/deploy-push.sh's release gate (harbor#1274): the target's published history is scanned, and every gate row is named.
# Each case is a throwaway source checkout and a throwaway export target; nothing is pushed anywhere.
# The "secret" below is a made-up word, never a real entity.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_IN_SUITE
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t.test; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t.test
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
mkdir -p "$T_TMP/pv"; printf 'id\tkind\tpattern\tnote\nk1\tword\tZorblax\tn\n' > "$T_TMP/pv/leaks.tsv"
PV="$T_TMP/pv"
mkdir -p "$T_TMP/pv/inject.d/box"; printf '# name\tpath\twhat\nzorbcorp\t~/zorbcorp\ta made-up workload repo\n' > "$T_TMP/pv/inject.d/box/projects.tsv"

mk() { # <name> → a source checkout whose release gate rows are green
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/docs/explanation" "$_d/docs"
  for _f in deploy-push.sh scope-layers.sh lint-leaks.sh lint-domain.sh scope-roots.sh eval-pass-score.sh library-log.sh; do cp "$T_ROOT/bin/$_f" "$_d/bin/"; done
  # the redteam-corpus row, green: a stub for the check (its gate wiring is push.test.sh's, its logic its own suite's)
  printf '#!/bin/sh\necho "  ok: stub"\n' > "$_d/bin/eval-redteam-corpus.sh"
  cp "$T_ROOT/contracts/leak-patterns.tsv" "$T_ROOT/contracts/roots.tsv" "$_d/contracts/"
  printf 'id\tpattern\tnote\nquuxtool\tquuxtool\tfixture\n' > "$_d/contracts/domain-terms.tsv"
  printf 'path\tterm\treason\n' > "$_d/contracts/domain-allow.tsv"
  printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 0 |\n' > "$_d/docs/explanation/admission-baseline.md"
  printf 'path\tlayer\tnote\nbin/\tcore\tt\ncontracts/\tcore\tc\ndocs/\tcore\td\nFLOOR.md\tcore\tf\n' > "$_d/contracts/layers.tsv"
  printf 'hello\n' > "$_d/docs/a.md"
  git -C "$_d" init -q . >/dev/null 2>&1; cm "$_d" src; printf '%s' "$_d"
}
cm() { ( cd "$1" && git add -A && git commit -qm "$2" ) >/dev/null 2>&1; }
bump() { printf '%s\n' "$2" > "$1/docs/a.md"; cm "$1" "$2"; }   # a changed source, so the next push has a commit to write
tgt() { _t="$T_TMP/t-$1"; mkdir -p "$_t"; ( cd "$_t" && git init -q . ) >/dev/null 2>&1; printf '%s' "$_t"; }
push() { _s="$1"; shift; HARBOR_ROOT="$_s" HARBOR_SCOPE_PRIVATE="$PV" sh "$_s/bin/deploy-push.sh" "$@" 2>&1; }
prc() { _s="$1"; shift; HARBOR_ROOT="$_s" HARBOR_SCOPE_PRIVATE="$PV" sh "$_s/bin/deploy-push.sh" "$@" >/dev/null 2>&1; echo $?; }
head_of() { git -C "$1" rev-parse -q --verify HEAD 2>/dev/null; }
# plant <target> <file> <text> [message]: an earlier export carried <text>, a later commit took the file out again.
plant() {
  printf '%s\n' "$3" > "$1/$2"; ( cd "$1" && git add -A && git commit -qm "${4:-export: earlier}" ) >/dev/null 2>&1
  ( cd "$1" && git rm -q "$2" && git commit -qm "export: later" ) >/dev/null 2>&1
}
# A GitHub-token shape, joined at run time so this file holds none (tests/ is exported and gitleaks scans it).
SEC="$(printf '%s%s%s' ghp_ Zq8LmN2pR7tY4wXc9Vb K3jHs6DfG1aQe5UoI)"

t_section "a clean published history passes, and is counted"
S="$(mk clean)"; T="$(tgt clean)"
t_eq "the first push is green" "0" "$(prc "$S" "$T")"
bump "$S" two
t_eq "a second push over a clean history is green" "0" "$(prc "$S" "$T")"
OUT="$(push "$S" --dry-run "$T")"
t_has "...the dry run names the history row green" "$OUT" "release gate · export history: green"
t_has "...and counts the published commits" "$OUT" "2 published commit(s)"
t_eq "...and its exit is 0" "0" "$(prc "$S" --dry-run "$T")"

t_section "a leak in an earlier export commit refuses the next push"
S="$(mk leak)"; T="$(tgt leak)"
prc "$S" "$T" >/dev/null; plant "$T" docs/old.md "owned by Zorblax"
t_eq "positive control: the target's tree no longer holds it" "" "$(git -C "$T" grep -l Zorblax HEAD 2>/dev/null)"
C="$(git -C "$T" rev-parse --short=12 HEAD~1)"; H="$(head_of "$T")"
bump "$S" next
OUT="$(push "$S" "$T")"
t_eq "push is red" "1" "$(prc "$S" "$T")"
t_has "...naming the commit and path" "$OUT" "commit $C docs/old.md:1"
t_has "...and the pattern id" "$OUT" "pattern k1"
t_hasnt "...never the matched text" "$OUT" "Zorblax"
t_eq "...nothing written to the target" "$H" "$(head_of "$T")"
t_eq "the dry run with the target is red" "1" "$(prc "$S" --dry-run "$T")"
t_has "...on the history row" "$(push "$S" --dry-run "$T")" "release gate · export history: red"
t_eq "the dry run without a target is green: the stage is clean" "0" "$(prc "$S" --dry-run)"

t_section "the core patterns read history too (a home path)"
S="$(mk core)"; T="$(tgt core)"
prc "$S" "$T" >/dev/null; plant "$T" docs/p.md "$(printf 'p=%s/jdoe/x' /Users)"; bump "$S" next
t_eq "push is red" "1" "$(prc "$S" "$T")"
t_has "...named by the core id" "$(push "$S" "$T")" "pattern home-path"

t_section "a commit message is published history"
S="$(mk msg)"; T="$(tgt msg)"
prc "$S" "$T" >/dev/null
( cd "$T" && git commit -q --allow-empty -m "export: for Zorblax" ) >/dev/null 2>&1; bump "$S" next
OUT="$(push "$S" "$T")"
t_eq "a leak in a message refuses the push" "1" "$(prc "$S" "$T")"
t_has "...named as the commit's message" "$OUT" "commit $(git -C "$T" rev-parse --short=12 HEAD) msg:1"
t_hasnt "...never the matched text" "$OUT" "Zorblax"

t_section "tags and remote branches are published too"
S="$(mk tag)"; T="$(tgt tag)"
prc "$S" "$T" >/dev/null
( cd "$T" && git checkout -q -b side && printf 'Zorblax\n' > docs/t.md && git add -A && git commit -qm side && git tag v0 && git checkout -q - && git branch -D side ) >/dev/null 2>&1
t_eq "positive control: the leak is reachable from the tag alone" "" "$(git -C "$T" log --format=%H HEAD -- docs/t.md)"
bump "$S" next
t_eq "a leak reachable only from a tag refuses the push" "1" "$(prc "$S" "$T")"
git -C "$T" tag -d v0 >/dev/null 2>&1
t_eq "...and the tag deleted, nothing reaches it" "0" "$(prc "$S" "$T")"
S="$(mk rem)"; T="$(tgt rem)"; R="$(tgt rem-origin)"
prc "$S" "$T" >/dev/null
( cd "$R" && printf 'Zorblax\n' > r.md && git add -A && git commit -qm r ) >/dev/null 2>&1
( cd "$T" && git remote add origin "$R" && git fetch -q origin ) >/dev/null 2>&1
bump "$S" next
t_eq "a leak on a remote-tracking branch refuses the push" "1" "$(prc "$S" "$T")"

S="$(mk remsec)"; T="$(tgt remsec)"; R="$(tgt remsec-origin)"
prc "$S" "$T" >/dev/null
( cd "$R" && printf 'pat %s\n' "$SEC" > r.md && git add -A && git commit -qm r ) >/dev/null 2>&1
( cd "$T" && git remote add origin "$R" && git fetch -q origin ) >/dev/null 2>&1
bump "$S" next
t_has "gitleaks reads the remote-tracking branches too" "$(push "$S" "$T")" ":r.md:github-pat:1"

# The leak sits in the path checked out first, so a shared directory would let the clean one overwrite it.
t_section "two paths differing only in case are both read (a case-insensitive disk keeps one file)"
S="$(mk case)"; T="$(tgt case)"
prc "$S" "$T" >/dev/null
( cd "$T" && b1="$(printf 'clean\n' | git hash-object -w --stdin)" && b2="$(printf 'owned by Zorblax\n' | git hash-object -w --stdin)" &&
  git update-index --add --cacheinfo "100644,$b1,docs/case.md" && git update-index --add --cacheinfo "100644,$b2,docs/CASE.md" &&
  git commit -qm "export: case" && git rm -q --cached docs/case.md docs/CASE.md && git commit -qm "export: uncase" && rm -f docs/case.md docs/CASE.md ) >/dev/null 2>&1
t_eq "positive control: the target is clean" "" "$(git -C "$T" status --porcelain)"
t_eq "positive control: one commit holds both paths" "2" "$(git -C "$T" ls-tree --name-only HEAD~1 docs/ | grep -ci 'docs/case.md')"
bump "$S" next
t_eq "a leak in one of them refuses the push" "1" "$(prc "$S" "$T")"

t_section "gitleaks reads the published commits"
S="$(mk sec)"; T="$(tgt sec)"
prc "$S" "$T" >/dev/null; plant "$T" docs/tok.md "pat $SEC"; C="$(git -C "$T" rev-parse HEAD~1)"; bump "$S" next
OUT="$(push "$S" "$T")"
t_eq "a token in an earlier commit refuses the push" "1" "$(prc "$S" "$T")"
t_has "...named as commit:file:rule:line" "$OUT" "$C:docs/tok.md:github-pat:1"
t_hasnt "...never by its text" "$OUT" "Zq8LmN2pR7tY4wXc9Vb"
t_eq "...and the leak gate alone found nothing" "" "$(printf '%s' "$OUT" | grep 'history leak')"

t_section "a history that cannot all be read refuses"
S="$(mk shallow)"; T="$(tgt shallow-src)"
prc "$S" "$T" >/dev/null; bump "$S" two; prc "$S" "$T" >/dev/null
git clone -q --depth 1 "file://$T" "$T_TMP/t-shallow" >/dev/null 2>&1
t_eq "positive control: the clone is shallow" "true" "$(git -C "$T_TMP/t-shallow" rev-parse --is-shallow-repository)"
bump "$S" three
t_eq "a shallow target refuses the push" "1" "$(prc "$S" "$T_TMP/t-shallow")"
t_has "...and says why" "$(push "$S" "$T_TMP/t-shallow")" "shallow clone"

t_section "every release gate row is named; the ones not run say so"
S="$(mk rows)"
OUT="$(push "$S" --dry-run)"
for r in "leak gate 0: green" "secrets 0: green" "domain ratchet 0: green" "pass-score: green" \
         "export history: not run" "stranger install: not run" "export suite: not run"; do
  t_has "the row: $r" "$OUT" "release gate · $r"
done
t_hasnt "the dry run's stdout is the file list alone (stranger-ubuntu reads it)" "$(HARBOR_ROOT="$S" HARBOR_SCOPE_PRIVATE="$PV" sh "$S/bin/deploy-push.sh" --dry-run 2>/dev/null)" "release gate"
T="$(tgt dom)"
printf 'uses quuxtool\n' > "$S/docs/d.md"; cm "$S" dom
t_eq "a workload term in core refuses the push" "1" "$(prc "$S" "$T")"
t_has "...on the domain row" "$(push "$S" "$T")" "release gate · domain ratchet 0: red"
t_eq "...writing nothing" "" "$(head_of "$T")"
# a workload repo's name, its id read from the private registry (harbor#1273)
printf 'cd ~/zorbcorp\n' > "$S/docs/d.md"; cm "$S" repo
t_eq "a workload repo named in core refuses the push" "1" "$(prc "$S" "$T")"
t_has "...on the domain row" "$(push "$S" "$T")" "release gate · domain ratchet 0: red"
printf 'hello\n' > "$S/docs/d.md"; cm "$S" norepo
PV0="$PV"; PV="$T_TMP/pv-noreg"; mkdir -p "$PV"; cp "$PV0/leaks.tsv" "$PV/"
t_eq "with no project registry the push is refused, not passed unjudged" "1" "$(prc "$S" "$T")"
t_has "...on the domain row" "$(push "$S" "$T")" "release gate · domain ratchet 0: red"
PV="$PV0"
t_eq "...and with it back, the same tree pushes" "0" "$(prc "$S" "$T")"
S="$(mk pass)"; T="$(tgt pass)"
printf '| | pass 1 | pass 2 | pass 3 |\n|---|---|---|---|\n| criticals | 0 | 0 | 2 |\n' > "$S/docs/explanation/admission-baseline.md"; cm "$S" crit
t_eq "pass-score red refuses the push" "1" "$(prc "$S" "$T")"
t_has "...on the pass-score row, with its verdict" "$(push "$S" "$T")" "release gate · pass-score: red - VERDICT"
t_eq "...writing nothing" "" "$(head_of "$T")"

t_done
