#!/usr/bin/env sh
# bin/lint-pr.sh (harbor#978): a PR's title, body and branch against the git naming standard.
# Every rule is born warn (D-64): a finding prints WARN with its rule id and the exit stays 0.
. "$(dirname "$0")/../../lib/core.sh"; t_init
GC="$T_ROOT/bin/lint-pr.sh"
LN="$T_ROOT/bin/lint-name.sh"
GOODBODY="$T_TMP/good.md"
{ printf '%s\n' '**What:** stop exit-127 in admission (#949).' '**Touches:** bin/admission-bash.sh.' \
    '**Breaks:** Nothing.' '**Tested:** suite green.' '**BPN:** not needed.' '**Merge:** ready once CI is green.'; } > "$GOODBODY"
run() { sh "$GC" "$@" 2>&1; }
good() { run --title 'fix(admission): stop exit-127' --body-file "$GOODBODY" --branch 'fix/949-admission-missing-hook' "$@"; }

t_section "the commit and branch surfaces are checkable"
t_has "a person id is not a family" "$(sh "$LN" --check commit 'feat(PI-42): x' 2>&1)" "[name.commit]"
t_has "a family-scoped subject is clean" "$(sh "$LN" --check commit 'fix(admission): stop exit-127' 2>&1)" "0 failed, 0 warnings"
t_has "an unregistered type warns" "$(sh "$LN" --check commit 'wip(admission): x' 2>&1)" "[name.commit]"
t_has "a branch of <type>/<issue>-<slug> is clean" "$(sh "$LN" --check branch 'fix/949-admission-missing-hook' 2>&1)" "0 failed, 0 warnings"
t_eq "perf is a registered commit type" "0 failed, 0 warnings" "$(sh "$LN" --check commit 'perf(admission): x' 2>&1 | sed -n 's/^lint-name: [0-9]* ok, //p')"
t_has "a domain is a valid scope" "$(sh "$LN" --check commit 'feat(tracking): x' 2>&1)" "0 failed, 0 warnings"
t_has "an unregistered scope warns" "$(sh "$LN" --check commit 'fix(nosuchscope): x' 2>&1)" "not a registered domain"
t_has "a capitalised branch warns" "$(sh "$LN" --check branch 'Feature/foo' 2>&1)" "[name.branch]"

t_section "a PR that follows the standard is clean"
out="$(good)"; rc=$?
t_eq "exit 0" 0 "$rc"
t_has "no warning" "$out" "0 failed, 0 warnings"

t_section "a title that breaks it warns and names the rule"
out="$(run --title 'feat(PI-42): x' --body-file "$GOODBODY" --branch 'fix/949-admission-missing-hook')"; rc=$?
t_has "the rule id is named" "$out" "[name.commit]"
W="$T_TMP/warnroot"; mkdir -p "$W/standards" "$W/hooks"; cp -R "$T_ROOT/bin" "$W/bin"; cp -R "$T_ROOT/standards/naming" "$W/standards/naming"; cp "$T_ROOT/hooks/commit-msg" "$W/hooks/"
sed 's/^name.commit\t[a-z]*/name.commit\twarn/' "$T_ROOT/standards/naming/controls.tsv" > "$W/standards/naming/controls.tsv"
t_eq "warn mode exits 0" 0 "$(HARBOR_SCOPE_ROOT="$W" sh "$GC" --title 'feat(PI-42): x' >/dev/null 2>&1; echo $?)"
t_eq "a block-mode rule (controls.tsv today) exits 1" 1 "$rc"

t_section "a body that breaks it warns"
printf '%s\n' '**What:** x (#949).' 'Co-Authored-By: Claude <noreply@anthropic.com>' > "$T_TMP/ai.md"
t_has "an AI trailer names its rule" "$(run --title 'fix(admission): x' --body-file "$T_TMP/ai.md" --branch 'fix/949-x')" "[lint.pr-no-ai-attribution]"
sed '/Tested/d' "$GOODBODY" > "$T_TMP/short.md"
out="$(run --title 'fix(admission): x' --body-file "$T_TMP/short.md" --branch 'fix/949-x')"
t_has "a missing labelled line names its rule" "$out" "[lint.pr-body-shape]"
t_has "and says which line" "$out" "Tested"
sed 's/#949//' "$GOODBODY" > "$T_TMP/noref.md"
t_has "a body with no #<n> warns" "$(run --title 'fix(admission): x' --body-file "$T_TMP/noref.md" --branch 'fix/949-x')" "[lint.pr-issue-link]"

t_section "a branch that breaks it warns"
t_has "a bad branch names its rule" "$(run --title 'fix(admission): x' --body-file "$GOODBODY" --branch 'Feature/foo')" "[name.branch]"

t_section "only a block rule fails the run"
B="$T_TMP/blockroot"; mkdir -p "$B/standards" "$B/hooks"; cp -R "$T_ROOT/bin" "$B/bin"; cp -R "$T_ROOT/standards/naming" "$B/standards/naming"; cp "$T_ROOT/hooks/commit-msg" "$B/hooks/"
sed 's/^name.commit\t[a-z]*/name.commit\tblock/' "$T_ROOT/standards/naming/controls.tsv" > "$B/standards/naming/controls.tsv"
out="$(HARBOR_SCOPE_ROOT="$B" sh "$GC" --title 'feat(PI-42): x' 2>&1)"; rc=$?
t_eq "a block rule exits 1" 1 "$rc"
t_has "and prints FAIL with its id" "$out" "FAIL: [name.commit]"

t_section "usage"
t_exit "no arguments" 2 sh "$GC"
t_exit "an unknown flag" 2 sh "$GC" --nope
t_exit "a body file that is not there" 2 sh "$GC" --title t --body-file "$T_TMP/none.md" --branch b
t_exit "--help" 0 sh "$GC" --help
t_done
