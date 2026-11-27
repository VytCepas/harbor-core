#!/usr/bin/env sh
# secret-scan.test.sh (harbor#25) — worklog/pre-push scans only what a push sends, bin/memory-secret-scan.sh the whole history (P3).
# A secret in the pushed range blocks; one already on the remote passes the push only while the nightly job is loaded; a missing scanner blocks both.
REQ_GITLEAKS="${HARBOR_TEST_REQUIRE_GITLEAKS:-0}"
. "$(dirname "$0")/../../lib/core.sh"; t_init
PP="$T_ROOT/worklog/pre-push"; NS="$T_ROOT/bin/memory-secret-scan.sh"
if ! command -v gitleaks >/dev/null 2>&1; then
  t_eq "gitleaks is absent, so HARBOR_TEST_REQUIRE_GITLEAKS must be off" 0 "$REQ_GITLEAKS"
  echo "secret-scan-test: SKIPPED (no gitleaks on PATH)"; t_done; exit $?
fi
# Assembled, not written: a token-shaped literal here trips secret-to-disk and the repo's own scan.
TOK="ghp_$(printf '%s' 'a1B2c3D4e5F6g7H8i9J0kLmNoPqRsTuVwXyZ')"
R="$T_TMP/log"; O="$T_TMP/origin.git"; Z=0000000000000000000000000000000000000000
git init -q --bare "$O"; git init -q "$R"
git -C "$R" config user.email t@t; git -C "$R" config user.name t; git -C "$R" remote add origin "$O"
commit() { printf '%s\n' "$2" > "$R/$1"; git -C "$R" add -A; git -C "$R" commit -q -m "$1"; git -C "$R" rev-parse HEAD; }
# The backstop is the nightly job as launchctl sees it; a stand-in on PATH says loaded (exit 0) or not (113, launchctl's "not found").
BS="$T_TMP/bs"; mkdir -p "$BS/on" "$BS/off"
printf '#!/bin/sh\n[ "$1 $2" = "print gui/%s/com.harbor.memory.secret-scan" ] || exit 64\nexit 0\n' "$(id -u)" > "$BS/on/launchctl"
printf '#!/bin/sh\nexit 113\n' > "$BS/off/launchctl"; chmod +x "$BS/on/launchctl" "$BS/off/launchctl"
pp() { ( cd "$R" && printf '%s\n' "$1" | PATH="$BS/${2:-on}:$PATH" sh "$PP" origin "$O" ) >/dev/null 2>&1; }  # <stdin line> [on|off] → exit code

t_section "the fixture is live"
printf 'tok %s\n' "$TOK" > "$T_TMP/bare.md"
t_exit "gitleaks detects the fixture token out of band (else every row below is inert)" 1 gitleaks dir --no-banner --exit-code 1 "$T_TMP/bare.md"

t_section "pre-push: the pushed range"
C1="$(commit a.md clean)"
t_exit "a new ref with a clean history goes through" 0 pp "refs/heads/main $C1 refs/heads/main $Z"
C2="$(commit leak.md "exported $TOK")"
t_exit "a secret in the pushed range blocks an update" 1 pp "refs/heads/main $C2 refs/heads/main $C1"
t_exit "...and blocks a new ref that carries it" 1 pp "refs/heads/main $C2 refs/heads/main $Z"
git -C "$R" push -q --no-verify origin HEAD:refs/heads/main 2>/dev/null
C3="$(commit b.md 'clean again')"
t_exit "a secret already on the remote is outside the range: the push goes through" 0 pp "refs/heads/main $C3 refs/heads/main $C2"
t_exit "a new ref scans the whole history, so it blocks" 1 pp "refs/heads/topic $C3 refs/heads/topic $Z"
t_exit "a deletion sends no commit and goes through" 0 pp "(delete) $Z refs/heads/old $C1"
t_exit "a remote sha this repo lacks scans the whole history, so it blocks" 1 pp "refs/heads/main $C3 refs/heads/main 1111111111111111111111111111111111111111"
t_exit "a malformed line scans the whole history, so it blocks" 1 pp "refs/heads/main not-a-sha refs/heads/main $C2"
t_exit "no lines on stdin scans the whole history, so it blocks" 1 pp ""
t_section "pre-push: a stale remote-tracking ref hides nothing"
# origin/stale names a secret commit the remote never received: a new ref on top of it must still be scanned through it.
R2="$T_TMP/log2"; O2="$T_TMP/origin2.git"; git init -q --bare "$O2"; git init -q "$R2"
git -C "$R2" config user.email t@t; git -C "$R2" config user.name t; git -C "$R2" remote add origin "$O2"
printf 'clean\n' > "$R2/a.md"; git -C "$R2" add -A; git -C "$R2" commit -q -m a; git -C "$R2" push -q --no-verify origin HEAD:refs/heads/main 2>/dev/null
git -C "$R2" checkout -q -b topic; printf 'exported %s\n' "$TOK" > "$R2/leak.md"; git -C "$R2" add -A; git -C "$R2" commit -q -m leak
git -C "$R2" update-ref refs/remotes/origin/stale HEAD
printf 'more\n' > "$R2/b.md"; git -C "$R2" add -A; git -C "$R2" commit -q -m b; S3="$(git -C "$R2" rev-parse HEAD)"
t_exit "a new ref over a secret only a stale origin/* has blocks" 1 sh -c 'cd "$1" && printf "%s\n" "$2" | PATH="$3:$PATH" sh "$4" origin "$5"' _ "$R2" "refs/heads/topic $S3 refs/heads/topic $Z" "$BS/on" "$PP" "$O2"

t_section "pre-push: no backstop, the whole history"
t_exit "with the nightly job not loaded, a secret already on the remote blocks again" 1 pp "refs/heads/main $C3 refs/heads/main $C2" off
NOLC="$T_TMP/nolc"; mkdir -p "$NOLC"; for _b in sh git gitleaks cat sed id tr; do ln -s "$(command -v "$_b")" "$NOLC/$_b"; done
nolc() { sh -c 'cd "$1" && printf "%s\n" "$2" | PATH="$3" sh "$4" origin' _ "$1" "$2" "$NOLC" "$PP"; }
t_exit "...and with no launchctl at all (Linux), it blocks too" 1 nolc "$R" "refs/heads/main $C3 refs/heads/main $C2"
K0="$T_TMP/clean0"; git init -q "$K0"; git -C "$K0" config user.email t@t; git -C "$K0" config user.name t
printf 'clean\n' > "$K0/a.md"; git -C "$K0" add -A; git -C "$K0" commit -q -m a; K1="$(git -C "$K0" rev-parse HEAD)"
t_exit "...while a clean history still goes through" 0 nolc "$K0" "refs/heads/main $K1 refs/heads/main $Z"

SAFE="$T_TMP/nogl"; mkdir -p "$SAFE"; for _b in sh git cat sed date mktemp mkdir mv rm tr awk cut head dirname uname id chmod ls; do ln -s "$(command -v "$_b")" "$SAFE/$_b"; done
t_exit "gitleaks missing blocks the push (fail-closed)" 1 sh -c 'cd "$1" && printf "%s\n" "$2" | PATH="$3" sh "$4" origin' _ "$R" "refs/heads/main $C3 refs/heads/main $C2" "$SAFE" "$PP"

t_section "nightly: the whole history"
CFG="$T_TMP/cfg"; mkdir -p "$CFG/cache"
ns() { CLAUDE_CONFIG_DIR="$CFG" sh "$NS" --repo "$1" >/dev/null 2>&1; }
t_exit "the secret left on the remote's history is found" 1 ns "$R"
t_has "...its receipt is red" "$(cat "$CFG/cache/checks/memory.secret-scan.json" 2>/dev/null)" '"red"'
t_hasnt "...and carries no secret text" "$(cat "$CFG/cache/checks/memory.secret-scan.json" "$CFG/cache/checks.log" 2>/dev/null)" "$TOK"
K="$T_TMP/clean"; git init -q "$K"; git -C "$K" config user.email t@t; git -C "$K" config user.name t
printf 'clean\n' > "$K/a.md"; git -C "$K" add -A; git -C "$K" commit -q -m a
t_exit "a clean history is green" 0 ns "$K"
t_has "...and says so in its receipt" "$(cat "$CFG/cache/checks/memory.secret-scan.json" 2>/dev/null)" '"green"'
t_exit "no repository stands down" 3 ns "$T_TMP/nowhere"
t_exit "gitleaks missing is red, not silent" 1 env PATH="$SAFE" CLAUDE_CONFIG_DIR="$CFG" sh "$NS" --repo "$K"
t_has "the check log names the check" "$(cat "$CFG/cache/checks.log" 2>/dev/null)" '[check:memory.secret-scan]'
t_done
