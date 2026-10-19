#!/usr/bin/env sh
# install-drift.sh, the install-vs-repo classifier (harbor#431): every verdict has a case that
# produces it, commit distance alone is never drift, and a bad ref aborts rather than reporting
# mass drift. The tool reads the tree it sits in, so it runs from a throwaway checkout.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; R="$T/repo"; CFG="$T/install"
mkdir -p "$R/bin" "$CFG/bin"; cp "$T_ROOT/bin/install-drift.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$R/bin/"
git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main
g() { git -C "$R" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
printf 'guard-a v1\n' > "$R/bin/guard-a.sh"; printf 'guard-b v1\n' > "$R/bin/guard-b.sh"; g add bin; g commit -qm v1
printf 'guard-a v2\n' > "$R/bin/guard-a.sh"; g add bin; g commit -qm v2
printf 'guard-a v3\n' > "$R/bin/guard-a.sh"; g add bin; g commit -qm v3
g branch -f ref-main HEAD
drift() { sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-main 2>&1; }
rc() { sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-main >/dev/null 2>&1; echo $?; }
reset_install() { rm -f "$CFG"/bin/*; printf 'guard-a v3\n' > "$CFG/bin/guard-a.sh"; printf 'guard-b v1\n' > "$CFG/bin/guard-b.sh"; }

t_section "current: clean and green, however many commits behind"
reset_install; out="$(drift)"
t_has "a current install is reported clean" "$out" "current=2 stale=0 modified=0 unsourced=0"
t_eq "a current install" 0 "$(rc)"
t_eq "stale count for a file unchanged since commit one" 0 "$(printf '%s' "$out" | sed -n 's/.*stale=\([0-9]*\).*/\1/p')"

t_section "stale: the live bytes are an earlier version"
reset_install; printf 'guard-a v1\n' > "$CFG/bin/guard-a.sh"; out="$(drift)"
t_has "reported stale, as a FAIL naming the file" "$out" "  FAIL: stale guard-a.sh ("
t_has "names the distance" "$out" "2 commit(s) behind ref-main"
t_eq "a stale install" 1 "$(rc)"
t_eq "...the fix under it re-runs the installers at this dir, spelled for their gate" \
  "  fix: sh $R/bin/runtime-install.sh --apply --dir '$CFG' && sh $R/bin/floor-install.sh --apply --dir '$CFG'" \
  "$(printf '%s\n' "$out" | grep -A1 '^  FAIL: stale' | sed -n 2p)"
t_eq "...and the run ends on the summary, one ok and one failure" "install-drift: 1 ok, 1 failed, 0 warnings" "$(printf '%s\n' "$out" | tail -1)"

t_section "modified: bytes match no commit for that path"
reset_install; printf 'guard-a HAND EDITED\n' > "$CFG/bin/guard-a.sh"; out="$(drift)"
t_has "reported modified" "$out" "  FAIL: modified guard-a.sh ("
t_hasnt "not misreported as stale" "$out" "FAIL: stale guard-a.sh"
t_has "...its fix says a person must capture it first" "$(printf '%s\n' "$out" | grep -A1 '^  FAIL: modified' | sed -n 2p)" "  fix: none automatic — see bin/install-drift.sh (diff "

t_section "unsourced: never in the repo, or deleted from it"
reset_install; printf 'never committed\n' > "$CFG/bin/save-log-token.sh"; out="$(drift)"
t_has "reported unsourced" "$out" "  FAIL: unsourced save-log-token.sh ("
t_has "says it is in no commit" "$out" "in no commit of this repository"
printf 'guard-c v1\n' > "$R/bin/guard-c.sh"; g add bin; g commit -qm add-c
g rm -q bin/guard-c.sh; g commit -qm rm-c; g branch -f ref-main HEAD
reset_install; printf 'guard-c v1\n' > "$CFG/bin/guard-c.sh"
t_has "a deleted file is told apart" "$(drift)" "deleted from the repo"

t_section "a ref that does not resolve aborts"
reset_install
out="$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref no/such/ref 2>&1)"; r=$?
t_eq "a bad ref" 2 "$r"
t_has "says the ref does not resolve" "$out" "ref does not resolve"
t_hasnt "reports no per-file drift" "$out" "unsourced"

t_section "every line carries the registry id, in the log shape"
reset_install; printf 'guard-a v1\n' > "$CFG/bin/guard-a.sh"
out="$(drift)"  # printf, not a pipe from drift: empty output must count as one unstamped line
t_eq "the header names the check" "── install-drift · [check:install-drift] $CFG/bin vs ref-main" "$(printf '%s\n' "$out" | head -1)"
t_eq "every result line but a fix carries [check:install-drift]" 0 \
  "$(printf '%s\n' "$out" | grep -E '^  (ok|FAIL|WARN|note|skip): ' | grep -cv '\[check:install-drift\]$')"
t_eq "...and there are result lines to check" yes "$([ "$(printf '%s\n' "$out" | grep -cE '^  (ok|FAIL|note): ')" -ge 3 ] && echo yes || echo no)"
t_eq "every line is a header, a TAG line or the summary (CONTRACTS/logging.md)" "" \
  "$(printf '%s\n' "$out" | grep -vE '^(── install-drift · |  (ok|FAIL|WARN|note|skip|fix): |install-drift: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)')"
t_eq "every FAIL is followed by its fix line" "$(printf '%s\n' "$out" | grep -c '^  FAIL: ')" \
  "$(printf '%s\n' "$out" | grep -A1 '^  FAIL: ' | grep -c '^  fix: ')"

t_section "a SUITE-installed file resolves through runtime-install's mapping at the ref (harbor#763)"
mkdir -p "$R/tests/floor" "$R/tests/lib"; g branch -f ref-before HEAD
printf 'SUITE="tests/floor/recover-test.sh:bin/recover-test.sh tests/lib/core.sh:lib/core.sh"\n' > "$R/bin/runtime-install.sh"
printf 'recover v1\n' > "$R/tests/floor/recover-test.sh"; printf 'core v1\n' > "$R/tests/lib/core.sh"; g add bin tests; g commit -qm suite-v1
printf 'recover v2\n' > "$R/tests/floor/recover-test.sh"; printf 'core v2\n' > "$R/tests/lib/core.sh"; g add tests; g commit -qm suite-v2
g branch -f ref-main HEAD
suite_install() { reset_install; [ ! -f "$R/bin/runtime-install.sh" ] || cp "$R/bin/runtime-install.sh" "$CFG/bin/"
  printf 'recover v2\n' > "$CFG/bin/recover-test.sh"; }
suite_install; out="$(drift)"
t_has "the installed suite matching tests/floor/recover-test.sh at the ref is current" "$out" "current=4 stale=0 modified=0 unsourced=0"
t_hasnt "...and is never unsourced again" "$out" "unsourced recover-test.sh"
t_has "...the control: at a ref whose runtime-install has no SUITE, the same copy reads unsourced" \
  "$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-before 2>&1)" "unsourced recover-test.sh"
t_eq "...so the install is clean" 0 "$(rc)"
suite_install; printf 'recover v1\n' > "$CFG/bin/recover-test.sh"; out="$(drift)"
t_has "an older copy of it is stale" "$out" "  FAIL: stale recover-test.sh (installed copy is 1 commit(s) behind ref-main)"
suite_install; printf 'recover EDITED\n' > "$CFG/bin/recover-test.sh"; out="$(drift)"
t_has "edited bytes are modified" "$out" "  FAIL: modified recover-test.sh ("
t_has "...and the fix names the source the mapping resolved" "$out" "(diff $R/tests/floor/recover-test.sh $CFG/bin/recover-test.sh and capture"

t_section "a DATA-installed file resolves through the same mapping: CHECKS.md into bin/ is not unsourced"
printf 'register v1\n' > "$R/CHECKS.md"; g add CHECKS.md; g commit -qm data-v0; g branch -f ref-nodata HEAD
printf 'SUITE="tests/floor/recover-test.sh:bin/recover-test.sh tests/lib/core.sh:lib/core.sh"\nDATA="CHECKS.md:bin/CHECKS.md"\n' > "$R/bin/runtime-install.sh"
g add bin; g commit -qm data-v1; g branch -f ref-main HEAD
suite_install; printf 'register v1\n' > "$CFG/bin/CHECKS.md"; out="$(drift)"
t_hasnt "the installed register matching CHECKS.md at the ref is never unsourced" "$out" "unsourced CHECKS.md"
t_has "...the control: at a ref whose runtime-install has no DATA, the same copy reads unsourced" \
  "$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-nodata 2>&1)" "unsourced CHECKS.md"
t_has "...it counts as current" "$out" "unsourced=0"
printf 'register EDITED\n' > "$CFG/bin/CHECKS.md"
t_has "...and an edited copy reads modified, naming the root source" "$(drift)" "  FAIL: modified CHECKS.md ("
rm -f "$CFG/bin/CHECKS.md"; g rm -q CHECKS.md
printf 'SUITE="tests/floor/recover-test.sh:bin/recover-test.sh tests/lib/core.sh:lib/core.sh"\n' > "$R/bin/runtime-install.sh"; g add bin; g commit -qm data-out; g branch -f ref-main HEAD

t_section "lib/ is checked too: the SUITE mapping and the install manifest name it (harbor#763, §3)"
suite_install; mkdir -p "$CFG/lib"; printf 'core v1\n' > "$CFG/lib/core.sh"; out="$(drift)"
t_has "a stale lib/core.sh is found, named by its path" "$out" "  FAIL: stale lib/core.sh (installed copy is 1 commit(s) behind ref-main)"
printf 'core v2\n' > "$CFG/lib/core.sh"
t_has "...and a current one counts" "$(drift)" "current=5 stale=0 modified=0 unsourced=0"
rm -f "$R/bin/runtime-install.sh"; g rm -q bin/runtime-install.sh; g commit -qm no-suite; g branch -f ref-main HEAD
suite_install; rm -f "$CFG/bin/runtime-install.sh" "$CFG/bin/recover-test.sh"; mkdir -p "$CFG/lib/x"
printf 'core v1\n' > "$CFG/lib/core.sh"; printf 'box\n' > "$CFG/lib/x/extra.sh"
t_hasnt "with no mapping and no manifest row, lib/ is not enumerated" "$(drift)" "lib/core.sh"
h1="$(git hash-object "$CFG/lib/core.sh")"; h2="$(git hash-object "$CFG/lib/x/extra.sh")"
printf '# header\n%s 100644 lib/core.sh runtime-install -\n%s 100644 lib/x/extra.sh skills-install -\n' "$h1" "$h2" > "$CFG/.harbor-manifest"
out="$(drift)"
t_has "a manifest row of runtime-install brings lib/core.sh into the set, resolved by its own path" "$out" "unsourced lib/core.sh"
t_hasnt "...a row of another installer does not" "$out" "lib/x/extra.sh"
t_has "...and the verdict is still git's, never the row's: with no mapping, lib/core.sh has no source" "$out" "  FAIL: unsourced lib/core.sh (in no commit of this repository)"
rm -f "$CFG/.harbor-manifest"; rm -rf "$CFG/lib"
printf 'SUITE="tests/floor/recover-test.sh:bin/recover-test.sh tests/lib/core.sh:lib/core.sh"\n' > "$R/bin/runtime-install.sh"; g add bin; g commit -qm suite-back; g branch -f ref-main HEAD

t_section "--quiet: silent when clean, the whole report when not"
reset_install
t_eq "a clean install under --quiet prints nothing" "" "$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-main --quiet 2>&1)"
t_eq "...and exits 0" 0 "$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-main --quiet >/dev/null 2>&1; echo $?)"
printf 'guard-a v1\n' > "$CFG/bin/guard-a.sh"
t_has "a stale install under --quiet still reports it" "$(sh "$R/bin/install-drift.sh" --dir "$CFG" --ref ref-main --quiet 2>&1)" "  FAIL: stale guard-a.sh"
t_done
