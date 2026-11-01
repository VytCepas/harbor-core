#!/usr/bin/env sh
# bin/doc-fresh-verify.sh (harbor#1287): one verdict per generated file, the fix for a stale one, non-zero on any stale file,
# and hooks/pre-push refusing before the linter. The harness arms use stub rows; the real arms break a copy of this tree.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset HARBOR_TEST_IN_SUITE HARBOR_IN_SUITE  # t_init passes it through (T_PASS_ENV); the real-tree arms run status-gen --check-fast (harbor#773)
FC="$T_ROOT/bin/doc-fresh-verify.sh"
TAB="$(printf '\t')"

# ── the harness, on stub checks ────────────────────────────────────────────
S="$T_TMP/stub"; mkdir -p "$S"; for _f in a b c; do : > "$S/$_f.md"; done
row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-}"; }
{ row a.md 'exit 0' 'gen a'; row b.md 'echo drifted; exit 1' 'gen b --apply'; row c.md 'exit 3' 'gen c'
  row d.md 'exit 1' 'gen d' nowhere/at/all; printf -- '-\tskipme.sh\tnot a freshness check\n'; } > "$S/mixed.tsv"
{ row a.md 'exit 0' 'gen a'; row b.md 'exit 3' 'gen b'; } > "$S/clean.tsv"
t_section "verdicts"
out="$(HARBOR_SCOPE_ROOT="$S" sh "$FC" --table "$S/mixed.tsv" 2>&1)"; rc=$?
t_eq "any stale file fails the run" 1 "$rc"
t_has "a fresh file is named" "$out" "ok: a.md is current"
t_has "a stale file is named" "$out" "FAIL: b.md is STALE"
t_has "the stale file carries its exact fix" "$out" "fix: gen b --apply"
t_has "a check that cannot judge is UNCHECKED, not stale" "$out" "WARN: c.md UNCHECKED"
t_has "a row whose subject is absent is skipped" "$out" "skip: d.md: nothing to judge"
t_eq "only b.md is stale: the skipped row's check never ran" 1 "$(printf '%s\n' "$out" | grep -c 'is STALE')"
t_eq "one verdict per table row, and a - row is not a row" 4 "$(printf '%s\n' "$out" | grep -cE '^  (ok|FAIL|WARN|skip):')"
out="$(HARBOR_SCOPE_ROOT="$S" sh "$FC" --table "$S/clean.tsv" 2>&1)"; rc=$?
t_eq "fresh and unchecked only: exit 0" 0 "$rc"
t_has "the clean run counts one ok and the unchecked one as a warning" "$out" "1 ok, 0 failed, 1 warnings"
{ for _n in p1 p2 p3; do : > "$S/$_n.md"; row $_n.md 'sleep 2' "gen $_n"; done; } > "$S/par.tsv"
p0="$(date +%s)"; HARBOR_SCOPE_ROOT="$S" sh "$FC" --table "$S/par.tsv" >/dev/null 2>&1; pe=$(( $(date +%s) - p0 ))
[ "$pe" -lt 5 ] && t_eq "three 2 s checks run in parallel (took ${pe}s, not 6)" ok ok || t_eq "three 2 s checks run in parallel (took ${pe}s, not 6)" ok serial
t_exit "an unknown flag is usage, exit 2" 2 sh "$FC" --bogus
t_exit "a missing table is exit 2" 2 sh "$FC" --table "$S/none.tsv"

# ── the registry enumerates the repo's generators ──────────────────────────
t_section "every generator is decided"
T="$T_ROOT/contracts/fresh-checks.tsv"
decided="$(awk -F'\t' '!/^#/ && NF>=2 { if ($1=="-") print $2; else { n=split($2,w," "); for(i=1;i<=n;i++) if (w[i] ~ /\.sh$/) { sub(/.*\//,"",w[i]); print w[i] } } }' "$T")"
cands=""
for f in "$T_ROOT"/bin/*.sh $(sh "$T_ROOT/bin/deploy-hooks.sh" --engines --root "$T_ROOT" 2>/dev/null); do
  [ -L "$f" ] && continue   # a W3 rename shim is its target's old name (harbor#961)
  h="$(sed -n '1,40p' "$f" | grep '^#')"
  case "$h" in *--check*) ;; *) continue ;; esac
  printf '%s\n' "$h" | grep -qiE 'stale|current|fresh|equals|differs' && cands="$cands ${f##*/}"
done
missing=""; for c in $cands; do printf '%s\n' "$decided" | grep -qx "$c" || missing="$missing $c"; done
t_eq "every bin/ script with a staleness --check is a row or a - row" "" "${missing# }"
lintgens="$(awk '/^rule "doc\.[a-z-]*generated/ {on=1; next} on && /^}/ {on=0} on' "$T_ROOT/bin/lint-conventions.sh" | grep -o 'bin/[a-z-]*\.sh' | sed 's|bin/||' | sort -u)"
miss=""; for g in $lintgens; do printf '%s\n' "$decided" | grep -qx "$g" || miss="$miss $g"; done
t_eq "every generator a doc.*-generated lint rule calls is in the table" "" "${miss# }"
t_has "the rule scan found the status generator (the scan is not empty)" "$lintgens" "status-generate.sh"

# ── the real thing, on a copy of this tree ─────────────────────────────────
t_section "a stale generated file fails in seconds; a fresh tree passes"
if [ ! -f "$T_ROOT/docs/generated/status.md" ]; then t_eq "the export carries no docs/generated/status.md, so there is no real-tree arm to run" ok ok; else
C="$T_TMP/copy"; mkdir -p "$C"
( cd "$T_ROOT" && git ls-files -co --exclude-standard -z | tar --null -T - -cf - ) | tar -xf - -C "$C"
# committed: docs/context-map.md counts tracked files, so the copy must track what the tree has
( cd "$C" && git init -q && git add -Af >/dev/null 2>&1 && git -c user.email=t@t -c user.name=t commit -qm copy )
out="$(cd "$C" && env -u HARBOR_TEST_IN_SUITE -u HARBOR_IN_SUITE sh bin/doc-fresh-verify.sh 2>&1)"; rc=$?
t_eq "control: the tree as it is passes" 0 "$rc"
t_hasnt "and nothing is stale" "$out" "is STALE"
cp "$C/docs/generated/status.md" "$T_TMP/STATUS.good"; cp "$C/docs/context-map.md" "$T_TMP/map.good"
printf '\nhand edit\n' >> "$C/docs/generated/status.md"; printf '\nhand edit\n' >> "$C/docs/context-map.md"
s0="$(date +%s)"
out="$(cd "$C" && env -u HARBOR_TEST_IN_SUITE -u HARBOR_IN_SUITE sh bin/doc-fresh-verify.sh 2>&1)"; rc=$?
el=$(( $(date +%s) - s0 ))
t_eq "a stale docs/generated/status.md and context map fail the run" 1 "$rc"
t_has "docs/generated/status.md is named" "$out" "FAIL: docs/generated/status.md is STALE"
t_has "docs/generated/status.md's fix is the generator" "$out" "fix: sh bin/status-generate.sh --apply"
t_has "the context map is named" "$out" "FAIL: docs/context-map.md is STALE"
t_has "the untouched CODEOWNERS is still fresh" "$out" "ok: .github/CODEOWNERS is current"
# ~13 s on an idle box (the slowest check, docs-gen). The bound is loose on purpose: a loaded runner must not turn this red;
# the parallelism itself is asserted on the stubs above.
[ "$el" -lt 90 ] && t_eq "it finished in under 90 s (took ${el}s)" ok ok || t_eq "it finished in under 90 s (took ${el}s)" ok slow
cp "$T_TMP/STATUS.good" "$C/docs/generated/status.md"; cp "$T_TMP/map.good" "$C/docs/context-map.md"
t_exit "restored, the tree passes again" 0 sh -c "cd '$C' && env -u HARBOR_TEST_IN_SUITE -u HARBOR_IN_SUITE sh bin/doc-fresh-verify.sh >/dev/null 2>&1"
fi

# ── pre-push refuses a stale push before anything else ────────────────────
t_section "pre-push"
P="$T_TMP/push"; mkdir -p "$P/bin" "$P/hooks" "$P/contracts"
cp "$T_ROOT/hooks/pre-push" "$T_ROOT/hooks/lib.sh" "$P/hooks/"; cp "$FC" "$T_ROOT/bin/library-log.sh" "$P/bin/"
printf '#!/bin/sh\nexit 0\n' > "$P/bin/test-suite-select.sh"; printf 'x.sh\n' > "$P/contracts/suites.txt"
printf 'echo LINTER-RAN >> "%s/ran"\n' "$T_TMP" > "$P/bin/lint-conventions.sh"
( cd "$P" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm init )
A0="$(git -C "$P" rev-parse HEAD)"
push() { ( cd "$P" && env -u GIT_DIR sh hooks/pre-push origin url ) < /dev/null 2>&1; }
row g.md 'exit 0' 'gen g' > "$P/contracts/fresh-checks.tsv"; : > "$P/g.md"
out="$(push)"; rc=$?
t_eq "a fresh tree: the hook passes" 0 "$rc"
t_has "and says fresh-check ran" "$out" "doc-fresh-verify.sh  ok"
rm -f "$T_TMP/ran"
row g.md 'echo stale; exit 1' 'sh bin/gen-g.sh --apply' > "$P/contracts/fresh-checks.tsv"
out="$(push)"; rc=$?
t_eq "a stale file: the hook refuses" 1 "$rc"
t_has "it names the file" "$out" "FAIL: g.md is STALE"
t_has "it names the fix" "$out" "fix: sh bin/gen-g.sh --apply"
t_exit "the linter never ran" 1 test -f "$T_TMP/ran"
t_done
