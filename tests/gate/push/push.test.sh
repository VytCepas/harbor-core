#!/usr/bin/env sh
# push.test.sh (harbor#1411) — bin/gate-push.sh: the checks run before git connects, and the push skips them only
# for a pass a real verify run recorded. Real hooks/pre-push, real git, a local bare remote; the linter is a stub
# that counts its runs and fails on demand. Proves: the end-to-end skip (1); a failing run records nothing (2); a
# different sha (3), an edited check set (4), a hand-written or altered record (5) and every other mismatch (6) run
# the full checks.
. "$(dirname "$0")/../../lib/core.sh"; t_init

GP="$T_ROOT/bin/gate-push.sh"
R="$T_TMP/repo"; REM="$T_TMP/remote.git"; RUNS="$T_TMP/lint-runs"; RED="$T_TMP/lint-red"
gc() { git -C "$R" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m "$1" >/dev/null 2>&1; }
runs() { if [ -f "$RUNS" ]; then grep -c . "$RUNS"; else echo 0; fi; }

git init -q --bare "$REM" >/dev/null 2>&1
git init -q -b topic "$R" >/dev/null 2>&1
mkdir -p "$R/hooks" "$R/bin" "$R/contracts"
cp "$T_ROOT/hooks/pre-push" "$T_ROOT/hooks/lib.sh" "$R/hooks/"
cp "$GP" "$T_ROOT/bin/library-log.sh" "$R/bin/"
: > "$R/bin/test-suite-select.sh"
printf '# none\n' > "$R/contracts/suites.txt"
cat > "$R/bin/lint-conventions.sh" <<EOF
#!/usr/bin/env sh
echo run >> "$RUNS"
[ ! -f "$RED" ]
EOF
git -C "$R" config core.hooksPath hooks
git -C "$R" remote add origin "$REM"
( cd "$R" && git add -A ) && gc base
S1="$(git -C "$R" rev-parse HEAD)"

t_section "end to end: gate-push runs the checks once, before the push, and the push skips them"
_o="$(cd "$R" && sh bin/gate-push.sh origin 2>&1)"; _rc=$?
t_eq "gate-push exits 0" 0 "$_rc"
t_eq "the linter ran exactly once (the dry run), not again at the push" 1 "$(runs)"
t_has "the push says it skipped on a verified pass" "$_o" "0 check(s) run — gate-push verified"
t_eq "the remote has the sha" "$S1" "$(git -C "$REM" rev-parse refs/heads/topic 2>/dev/null)"
REC="$(git -C "$R" rev-parse --absolute-git-dir)/gate-push/$S1"
t_eq "a record exists for the sha" yes "$([ -f "$REC" ] && echo yes || echo no)"
_k="$HOME/.cache/harbor/secrets/gate-push/key"
. "$T_ROOT/bin/library-fs.sh"; t_eq "the key is mode 600" 600 "$(fs_mode "$_k")"

# The recorded push, replayed against `check` directly: the control every forge case below differs from in one thing.
LINE="$(cut -f6 "$REC")"
chk() { ( cd "$R" && printf '%s\n' "$1" | sh bin/gate-push.sh check origin "$REM" >/dev/null 2>&1 ); echo $?; }
t_eq "control: the recorded push, replayed, skips" 0 "$(chk "$LINE")"

t_section "a failing run records nothing and pushes nothing"
gc second; S2="$(git -C "$R" rev-parse HEAD)"
: > "$RED"
_o="$(cd "$R" && sh bin/gate-push.sh origin 2>&1)"; _rc=$?
t_eq "gate-push exits 1 when the checks fail" 1 "$_rc"
t_has "...and says nothing was recorded" "$_o" "nothing recorded"
t_eq "no record for the failing sha" no "$([ -f "$(dirname "$REC")/$S2" ] && echo yes || echo no)"
t_eq "the remote did not move" "$S1" "$(git -C "$REM" rev-parse refs/heads/topic)"
rm -f "$RED"

t_section "a different sha does not skip"
_l2="$(printf '%s' "$LINE" | awk -v s="$S2" '{ $2 = s; print }')"
t_eq "the recorded push line with another sha runs the checks" 1 "$(chk "$_l2")"
cp "$REC" "$(dirname "$REC")/$S2"
t_eq "...even with the pass copied to that sha's record" 1 "$(chk "$_l2")"
rm -f "$(dirname "$REC")/$S2"
_o="$( cd "$R" && printf 'refs/heads/topic %s refs/heads/topic %s\n' "$S2" "$S1" | git push origin topic 2>&1 )"
t_has "a plain push of a new sha runs the full checks" "$_o" "no recorded pass for"

t_section "an edited check set does not skip"
cp "$R/hooks/lib.sh" "$T_TMP/lib.bak"; printf '\n# edited\n' >> "$R/hooks/lib.sh"
t_eq "a file the hook declares (lib.sh) changed" 1 "$(chk "$LINE")"
cp "$T_TMP/lib.bak" "$R/hooks/lib.sh"
cp "$R/hooks/pre-push" "$T_TMP/pp.bak"; printf '\n# edited\n' >> "$R/hooks/pre-push"
t_eq "the hook itself changed" 1 "$(chk "$LINE")"
cp "$T_TMP/pp.bak" "$R/hooks/pre-push"
t_eq "a declared env var changes the check set (FULL mode)" 1 \
  "$( ( cd "$R" && printf '%s\n' "$LINE" | HARBOR_GATE_PREPUSH_FULL=1 sh bin/gate-push.sh check origin "$REM" >/dev/null 2>&1 ); echo $?)"
t_eq "control after the restores: it skips again" 0 "$(chk "$LINE")"

t_section "a hand-written record does not skip: the tag needs the key"
cp "$REC" "$T_TMP/rec.bak"
_f="$(cut -f5 "$REC")"; _fp="$(cut -f4 "$REC")"; _at="$(cut -f2 "$REC")"
printf 'v1\t%s\t%s\t%s\t%s\t%s\n' "$_at" "$(printf 'x' | shasum -a 256 | cut -c1-64)" "$_fp" "$_f" "$LINE" > "$REC"
t_eq "every field right but a tag computed without the key" 1 "$(chk "$LINE")"
_wk="$( { printf 'not-the-key-not-the-key-not-the-key\n'; printf 'harbor gate-push v1\nat %s\nremote %s\npush %s\nfingerprint %s\n' "$_at" "$_f" "$LINE" "$_fp"; } | shasum -a 256 | cut -c1-64)"
printf 'v1\t%s\t%s\t%s\t%s\t%s\n' "$_at" "$_wk" "$_fp" "$_f" "$LINE" > "$REC"
t_eq "the right message tagged under another key" 1 "$(chk "$LINE")"
awk -F'\t' -v OFS='\t' '{ $2 = $2 + 1; print }' "$T_TMP/rec.bak" > "$REC"
t_eq "a real record with its time edited" 1 "$(chk "$LINE")"
cp "$T_TMP/rec.bak" "$REC"
mv "$_k" "$T_TMP/key.bak"
t_eq "the key unreadable (a sandboxed push)" 1 "$(chk "$LINE")"
mv "$T_TMP/key.bak" "$_k"
mkdir -p "$T_TMP/plain/gate-push" "$T_TMP/elsewhere/harbor"; cp "$_k" "$T_TMP/plain/gate-push/key"
ln -s "$T_TMP/plain" "$T_TMP/elsewhere/harbor/secrets"
t_eq "a key reached through a symlinked secrets/ that resolves elsewhere is refused" 1 \
  "$( ( cd "$R" && printf '%s\n' "$LINE" | XDG_CACHE_HOME="$T_TMP/elsewhere" sh bin/gate-push.sh check origin "$REM" >/dev/null 2>&1 ); echo $?)"
t_eq "control after the restores: it skips again" 0 "$(chk "$LINE")"

t_section "every other mismatch runs the full checks"
_l3="$(printf '%s' "$LINE" | awk -v s="$S2" '{ $4 = s; print }')"
t_eq "the remote moved since the pass" 1 "$(chk "$_l3")"
t_eq "another remote" 1 "$( ( cd "$R" && printf '%s\n' "$LINE" | sh bin/gate-push.sh check fork "$REM" >/dev/null 2>&1 ); echo $?)"
t_eq "two refs in one push" 1 "$(chk "$(printf '%s\n%s' "$LINE" "$_l2")")"
t_eq "past the TTL" 1 "$( ( cd "$R" && printf '%s\n' "$LINE" | HARBOR_GATE_PUSH_TTL=0 sh -c 'sleep 1; sh bin/gate-push.sh check origin x' >/dev/null 2>&1 ); echo $?)"
t_eq "a verify run (capture set) never skips" 1 \
  "$( ( cd "$R" && printf '%s\n' "$LINE" | HARBOR_GATE_PUSH_CAPTURE="$T_TMP/cap" sh bin/gate-push.sh check origin "$REM" >/dev/null 2>&1 ); echo $?)"

t_section "gate-push refuses what it cannot bind to a sha"
printf 'dirty\n' >> "$R/contracts/suites.txt"
_n="$(runs)"
t_exit "uncommitted tracked changes are refused" 1 sh -c "cd '$R' && sh bin/gate-push.sh origin"
t_eq "...before any check ran" "$_n" "$(runs)"
git -C "$R" checkout -q -- contracts/suites.txt

t_section "any repo: a bash hook reaches gate-push through the PATH shim, and a declared cmd is in the check set"
F="$T_TMP/foreign"; FREM="$T_TMP/foreign.git"; FRUNS="$T_TMP/foreign-runs"
git init -q --bare "$FREM" >/dev/null 2>&1; git init -q -b topic "$F" >/dev/null 2>&1
git -C "$F" remote add origin "$FREM"
ln -s "$GP" "$T_BIN/gate-push"
printf 'lint test\n' > "$F/recipe.txt"
cat > "$F/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
# gate-push: cmd cat recipe.txt
if command -v gate-push >/dev/null 2>&1; then
  _gp_in="\$(mktemp)"; cat > "\$_gp_in"
  if gate-push check "\$@" < "\$_gp_in"; then rm -f "\$_gp_in"; exit 0; fi
  exec < "\$_gp_in"; rm -f "\$_gp_in"
fi
while read -r _ _ _ _; do :; done
echo run >> "$FRUNS"
EOF
chmod +x "$F/.git/hooks/pre-push"
( cd "$F" && git add -A ) && git -C "$F" -c user.email=t@t.invalid -c user.name=t commit -q -m base >/dev/null 2>&1
_o="$(cd "$F" && gate-push origin 2>&1)"; _rc=$?
t_eq "gate-push through the symlink exits 0" 0 "$_rc"
t_eq "the foreign hook's checks ran once" 1 "$(grep -c . "$FRUNS" 2>/dev/null || echo 0)"
t_has "...and its push skipped them" "$_o" "0 check(s) run — gate-push verified"
_fs="$(git -C "$F" rev-parse HEAD)"
_fl="$(cut -f6 "$(git -C "$F" rev-parse --absolute-git-dir)/gate-push/$_fs")"
fchk() { ( cd "$F" && printf '%s\n' "$_fl" | gate-push check origin "$FREM" >/dev/null 2>&1 ); echo $?; }
t_eq "control: the recorded foreign push skips" 0 "$(fchk)"
printf 'lint\n' > "$F/recipe.txt"
t_eq "the declared cmd's output changed (a recipe edit)" 1 "$(fchk)"

t_done
