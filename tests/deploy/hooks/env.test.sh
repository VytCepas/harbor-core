#!/usr/bin/env sh
# hooks-env-test.sh (harbor#824, cf. project-init#1065) — git exports GIT_DIR (and, from a linked
# worktree, GIT_WORK_TREE/GIT_INDEX_FILE) into every hook. A suite that runs `git -C <its own tmp>`
# under this inherits the real repo instead — project-init#1065's corrupted clone. Proves, in order:
# hook_scrub_run drops exactly the git-hook vars (1); the hazard is real and it closes the hazard,
# with real git repos (2); both hooks wire every dispatch through it (3); the REAL hook scripts,
# fired end-to-end in a throwaway repo, never leak GIT_* into the suites they run (4).
. "$(dirname "$0")/../../lib/core.sh"; t_init

LIBF="$T_ROOT/hooks/lib.sh"
PP="$T_ROOT/hooks/pre-push"
PC="$T_ROOT/hooks/pre-commit"
HAVE_LIB=0
[ -f "$LIBF" ] && HAVE_LIB=1

gcommit() { git -C "$1" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m "$2" >/dev/null 2>&1; }

t_section "hook_scrub_run drops exactly the git-hook vars (hooks/lib.sh)"
t_eq "hooks/lib.sh exists" yes "$([ "$HAVE_LIB" = 1 ] && echo yes || echo no)"
if [ "$HAVE_LIB" = 1 ]; then
  o="$(env -u BENIGN GIT_DIR=/x GIT_WORK_TREE=/x GIT_INDEX_FILE=/x GIT_COMMON_DIR=/x \
       GIT_OBJECT_DIRECTORY=/x GIT_ALTERNATE_OBJECT_DIRECTORIES=/x GIT_QUARANTINE_PATH=/x \
       GIT_PREFIX=sub/ BENIGN=kept sh -c ". \"$LIBF\"; hook_scrub_run env")"
  t_hasnt "GIT_DIR does not reach the child"                         "$o" 'GIT_DIR='
  t_hasnt "GIT_WORK_TREE does not reach the child"                   "$o" 'GIT_WORK_TREE='
  t_hasnt "GIT_INDEX_FILE does not reach the child"                  "$o" 'GIT_INDEX_FILE='
  t_hasnt "GIT_COMMON_DIR does not reach the child"                  "$o" 'GIT_COMMON_DIR='
  t_hasnt "GIT_OBJECT_DIRECTORY does not reach the child"            "$o" 'GIT_OBJECT_DIRECTORY='
  t_hasnt "GIT_ALTERNATE_OBJECT_DIRECTORIES does not reach the child" "$o" 'GIT_ALTERNATE_OBJECT_DIRECTORIES='
  t_hasnt "GIT_QUARANTINE_PATH does not reach the child"             "$o" 'GIT_QUARANTINE_PATH='
  t_hasnt "GIT_PREFIX does not reach the child"                      "$o" 'GIT_PREFIX='
  t_has  "an unrelated var still reaches the child"                  "$o" 'BENIGN=kept'
else
  for _v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
            GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH GIT_PREFIX unrelated-var; do
    t_fail "hooks/lib.sh missing — cannot test hook_scrub_run ($_v)"
  done
fi

t_section "the hazard is real, and the scrub closes it (project-init#1065)"
TARGET="$T_TMP/target"; POISON="$T_TMP/poison"
mkdir -p "$TARGET" "$POISON"
git init -q -b main "$TARGET" >/dev/null 2>&1
git init -q -b main "$POISON" >/dev/null 2>&1
gcommit "$TARGET" base; gcommit "$POISON" base
t0="$(git -C "$TARGET" rev-parse main)"; p0="$(git -C "$POISON" rev-parse main)"

( export GIT_DIR="$POISON/.git"
  git -C "$TARGET" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m hijacked
) >/dev/null 2>&1
t_eq "unscrubbed: TARGET's ref did not move" "$t0" "$(git -C "$TARGET" rev-parse main)"
t_eq "unscrubbed: POISON's ref moved instead — the write landed on the wrong repo" yes \
  "$([ "$(git -C "$POISON" rev-parse main)" != "$p0" ] && echo yes || echo no)"
git -C "$POISON" update-ref refs/heads/main "$p0"  # reset for the next case

if [ "$HAVE_LIB" = 1 ]; then
  ( export GIT_DIR="$POISON/.git"
    . "$LIBF"
    hook_scrub_run git -C "$TARGET" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m scrubbed
  ) >/dev/null 2>&1
  t_eq "scrubbed: TARGET's ref moved — the commit landed where -C pointed" yes \
    "$([ "$(git -C "$TARGET" rev-parse main)" != "$t0" ] && echo yes || echo no)"
  t_eq "scrubbed: POISON's ref is untouched" "$p0" "$(git -C "$POISON" rev-parse main)"
else
  t_fail "hooks/lib.sh missing — cannot prove the scrub closes the hazard"
  t_fail "hooks/lib.sh missing — POISON would be left untouched only by accident"
fi

t_section "hooks/pre-push and hooks/pre-commit route every suite/lint dispatch through hook_scrub_run"
t_has "pre-push sources hooks/lib.sh" "$(cat "$PP")" 'hooks/lib.sh'
t_has "pre-commit sources hooks/lib.sh" "$(cat "$PC")" 'hooks/lib.sh'

t_has "pre-push wraps the FULL-mode selection decision" "$(cat "$PP")" \
  'hook_scrub_run sh "$ROOT/bin/test-suite-select.sh" "$_s"'
# Checks go through _quiet (one CPU slot each from bin/ci-governor.sh); both of its arms scrub.
t_has "_quiet's governed arm scrubs" "$(cat "$PP")" \
  'hook_scrub_run sh "$ROOT/bin/ci-governor.sh" run --out /dev/null -- "$@"'
t_has "_quiet's plain arm scrubs" "$(cat "$PP")" \
  'else hook_scrub_run "$@" >/dev/null 2>&1; fi'
t_has "pre-push wraps the FULL-mode direct suite run" "$(cat "$PP")" \
  '_quiet sh "$_sp"'
t_has "pre-push wraps the linter" "$(cat "$PP")" \
  '_quiet sh "$ROOT/bin/lint-conventions.sh"'
t_has "pre-push wraps the floor smoke" "$(cat "$PP")" \
  '_quiet env T_SMOKE=1 sh "$ROOT/tests/admission/baseline/baseline.test.sh"'
t_eq "…and lint-conventions.sh is dispatched exactly once (no second, unguarded copy)" 1 \
  "$(grep -c 'sh "$ROOT/bin/lint-conventions.sh"' "$PP")"
t_eq "…and tests/admission/baseline/baseline.test.sh is dispatched exactly once" 1 \
  "$(grep -c 'sh "$ROOT/tests/admission/baseline/baseline.test.sh"' "$PP")"

t_has "pre-commit wraps the floor smoke" "$(cat "$PC")" \
  'hook_scrub_run T_SMOKE=1 sh "$_idx/tests/admission/baseline/baseline.test.sh"'
t_has "pre-commit wraps the staged guard suites" "$(cat "$PC")" \
  'hook_scrub_run T_SMOKE=1 T_JOBS=8 sh "$_t"'
t_eq "…and \$_idx/tests/admission/baseline/baseline.test.sh is dispatched exactly once" 1 \
  "$(grep -c 'sh "$_idx/tests/admission/baseline/baseline.test.sh"' "$PC")"
t_eq "…and \$_t is dispatched exactly once" 1 "$(grep -c 'sh "$_t"' "$PC")"

t_section "end-to-end: hooks/pre-commit's floor smoke never sees GIT_* (real script, real repo)"
FR="$T_TMP/frC"
mkdir -p "$FR/bin" "$FR/hooks" "$FR/tests/admission/baseline" "$FR/tests/guards"
git init -q -b main "$FR" >/dev/null 2>&1
cp "$PC" "$FR/hooks/pre-commit"
[ "$HAVE_LIB" = 1 ] && cp "$LIBF" "$FR/hooks/lib.sh"
MARK_C="$T_TMP/leak-marker-c"; RAN_C="$T_TMP/ran-marker-c"; rm -f "$MARK_C" "$RAN_C"
cat > "$FR/tests/admission/baseline/baseline.test.sh" <<EOF
#!/usr/bin/env sh
: > "$RAN_C"
if [ -n "\${GIT_DIR:-}" ] || [ -n "\${GIT_WORK_TREE:-}" ] || [ -n "\${GIT_INDEX_FILE:-}" ]; then
  : > "$MARK_C"
fi
exit 0
EOF
chmod +x "$FR/tests/admission/baseline/baseline.test.sh"
: > "$FR/bin/guard-something.sh"
( cd "$FR" && git add bin/guard-something.sh tests/admission/baseline/baseline.test.sh hooks/pre-commit )
[ "$HAVE_LIB" = 1 ] && ( cd "$FR" && git add hooks/lib.sh )
( cd "$FR" && git -c user.email=t@t.invalid -c user.name=t commit -q -m base ) >/dev/null 2>&1
echo x >> "$FR/bin/guard-something.sh"  # stage a floor-surface change, as an in-flight commit would
( cd "$FR" && git add bin/guard-something.sh )
( cd "$FR" && GIT_DIR="$FR/.git" sh hooks/pre-commit ) >"$T_TMP/pc.out" 2>&1
_pc_rc=$?
t_has "the fixture triggers the floor branch (sanity)" "$(cat "$T_TMP/pc.out")" "running the guard smoke suite"
t_eq "hooks/pre-commit itself exits 0 (the floor-test.sh child ran and passed)" 0 "$_pc_rc"
t_eq "the floor-test.sh child actually ran (a broken dispatch is not a pass)" yes "$([ -f "$RAN_C" ] && echo yes || echo no)"
t_eq "the floor-test.sh child never saw a git-hook var" no "$([ -f "$MARK_C" ] && echo yes || echo no)"

t_section "end-to-end: hooks/pre-push's lint and floor smoke never see GIT_* (real script, real repo)"
FR2="$T_TMP/frP"
mkdir -p "$FR2/bin" "$FR2/hooks" "$FR2/tests/admission/baseline" "$FR2/contracts"
git init -q -b main "$FR2" >/dev/null 2>&1
cp "$PP" "$FR2/hooks/pre-push"
[ "$HAVE_LIB" = 1 ] && cp "$LIBF" "$FR2/hooks/lib.sh"
: > "$FR2/bin/test-suite-select.sh"  # pre-push exits 0 up front without this file; content unused (narrow mode)
printf '# no suites needed for this fixture\n' > "$FR2/contracts/suites.txt"
MARK_L="$T_TMP/leak-marker-lint"; MARK_F="$T_TMP/leak-marker-floor"; rm -f "$MARK_L" "$MARK_F"
cat > "$FR2/bin/lint-conventions.sh" <<EOF
#!/usr/bin/env sh
if [ -n "\${GIT_DIR:-}" ] || [ -n "\${GIT_WORK_TREE:-}" ] || [ -n "\${GIT_INDEX_FILE:-}" ]; then
  : > "$MARK_L"
fi
exit 0
EOF
cat > "$FR2/tests/admission/baseline/baseline.test.sh" <<EOF
#!/usr/bin/env sh
if [ -n "\${GIT_DIR:-}" ] || [ -n "\${GIT_WORK_TREE:-}" ] || [ -n "\${GIT_INDEX_FILE:-}" ]; then
  : > "$MARK_F"
fi
printf 'floor-test smoke: 1 passed, 0 failed\n'
exit 0
EOF
chmod +x "$FR2/bin/lint-conventions.sh" "$FR2/tests/admission/baseline/baseline.test.sh" "$FR2/bin/test-suite-select.sh"
( cd "$FR2" && git add -A && git -c user.email=t@t.invalid -c user.name=t commit -q -m base ) >/dev/null 2>&1
BASE_SHA="$(git -C "$FR2" rev-parse HEAD)"
printf '#!/usr/bin/env sh\n' > "$FR2/bin/floor-fake.sh"  # a floor-surface path, so the smoke branch fires
( cd "$FR2" && git add bin/floor-fake.sh && git -c user.email=t@t.invalid -c user.name=t commit -q -m "add floor surface" ) >/dev/null 2>&1
LOCAL_SHA="$(git -C "$FR2" rev-parse HEAD)"
( cd "$FR2" && printf 'refs/heads/main %s refs/heads/main %s\n' "$LOCAL_SHA" "$BASE_SHA" \
    | GIT_DIR="$FR2/.git" sh hooks/pre-push ) >"$T_TMP/pp.out" 2>&1
_pp_rc=$?
t_has "the fixture runs the linter (sanity)"      "$(cat "$T_TMP/pp.out")" 'run   lint-conventions.sh'
t_has "the fixture runs the floor smoke (sanity)" "$(cat "$T_TMP/pp.out")" 'run   floor-test.sh smoke'
t_eq "hooks/pre-push itself exits 0 (both children ran and passed)" 0 "$_pp_rc"
t_hasnt "the dispatch never reports FAILED (a broken dispatch is not a pass)" "$(cat "$T_TMP/pp.out")" 'FAILED'
t_eq "the linter child never saw a git-hook var"      no "$([ -f "$MARK_L" ] && echo yes || echo no)"
t_eq "the floor-test.sh child never saw a git-hook var" no "$([ -f "$MARK_F" ] && echo yes || echo no)"

t_section "end-to-end: the same push through bin/ci-governor.sh still never leaks GIT_*"
cp "$T_ROOT/bin/ci-governor.sh" "$T_ROOT/bin/library-log.sh" "$FR2/bin/"
printf '#!/bin/sh\nexit 0\n' > "$T_BIN/notifyutil"; chmod +x "$T_BIN/notifyutil"   # the governor's post stays off the real notifyd
mkdir -p "$T_TMP/gov-cache/ci-governor/slots"
printf 'at=%s\nslots=4\n' "$(date +%s)" > "$T_TMP/gov-cache/ci-governor/state"
rm -f "$MARK_L" "$MARK_F"
( cd "$FR2" && printf 'refs/heads/main %s refs/heads/main %s\n' "$LOCAL_SHA" "$BASE_SHA" \
    | GIT_DIR="$FR2/.git" HARBOR_CACHE_DIR="$T_TMP/gov-cache" sh hooks/pre-push ) >"$T_TMP/pp2.out" 2>&1
_pp_rc=$?
t_eq "hooks/pre-push exits 0 with the governor in the path" 0 "$_pp_rc"
t_has "...and still runs the floor smoke" "$(cat "$T_TMP/pp2.out")" 'run   floor-test.sh smoke'
t_hasnt "...without a FAILED" "$(cat "$T_TMP/pp2.out")" 'FAILED'
t_eq "the linter child never saw a git-hook var"      no "$([ -f "$MARK_L" ] && echo yes || echo no)"
t_eq "the floor-test.sh child never saw a git-hook var" no "$([ -f "$MARK_F" ] && echo yes || echo no)"

t_done
