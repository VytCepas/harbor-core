#!/usr/bin/env sh
# The first-run precondition (harbor#457): a box where Claude Code never ran has no config dir and no settings.json.
# Every tool that meets that says so FIRST, as a FAIL line, with the command that removes it, instead of failing on its
# own downstream error. A sandbox HOME with nothing in it is the stranger's box; nothing outside it is read or written.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDE_CONFIG_DIR CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY CI GITHUB_ACTIONS
B="$T_ROOT/bin"; C="$HOME/.claude"; CP="$(cd "$HOME" && pwd -P)/.claude"  # a dir that exists is reported physically (il_target)
HARBOR_SCOPE_REPO="$T_ROOT"; export HARBOR_SCOPE_REPO
FIX="sh '$T_ROOT/bin/harbor' scope install"   # the one spelling, il_first_run_cmd's
run() { "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }  # the exit; the output is in $T_TMP/out
out() { cat "$T_TMP/out"; }
fails() { grep -c '^  FAIL: ' "$T_TMP/out" || :; }
first() { grep -m1 '^  FAIL: ' "$T_TMP/out"; }   # the first FAIL line
fixof() { awk '/^  FAIL: /{f=1; next} f && /^  fix: /{print; exit}' "$T_TMP/out"; }  # the fix under the first FAIL

t_section "il_first_run_cmd: the one spelling"
# A copy of the two libs with no scope-roots.sh beside them, so the helper's own fallbacks are what answers.
mkdir -p "$T_TMP/bare"; cp "$B/library-log.sh" "$B/deploy-install-lib.sh" "$T_TMP/bare/"
printf '#!/bin/sh\nset -eu\n. "%s/bare/library-log.sh"\n. "%s/bare/deploy-install-lib.sh"\nil_first_run_cmd "$@"\n' "$T_TMP" "$T_TMP" > "$T_TMP/bare/spell.sh"
spell() { env -u PORT_ROOT "$@" sh "$T_TMP/bare/spell.sh" "$SPELL_ARG"; }
SPELL_ARG="/x y/harbor"
t_eq "a given checkout is spelled as the harbor verb, single-quoted" "sh '/x y/harbor/bin/harbor' scope install" "$(spell -u HARBOR_SCOPE_REPO -u HARBOR_REPO)"
SPELL_ARG=""
t_eq "with none given and no scope-roots.sh beside it, HARBOR_SCOPE_REPO" "sh '/from/env/bin/harbor' scope install" "$(spell HARBOR_SCOPE_REPO=/from/env)"
t_eq "...and with that unset, the conventional path under HOME" "sh '$HOME/port/harbor/bin/harbor' scope install" "$(spell -u HARBOR_SCOPE_REPO -u HARBOR_REPO)"
# A tool run from a checkout names THAT checkout's verb: a clone anywhere, with HARBOR_SCOPE_REPO unset, got the conventional path.
mkdir -p "$T_TMP/clone/bin"; cp "$B/library-log.sh" "$B/deploy-install-lib.sh" "$T_TMP/clone/bin/"; : > "$T_TMP/clone/bin/harbor"
cp "$T_TMP/bare/spell.sh" "$T_TMP/clone/bin/spell.sh"; sed -i.bak "s#$T_TMP/bare/#$T_TMP/clone/bin/#g" "$T_TMP/clone/bin/spell.sh"
SPELL_ARG=""
t_eq "with none given, a bin/harbor beside the script is the checkout, wherever it was cloned" "sh '$T_TMP/clone/bin/harbor' scope install" \
  "$(env -u PORT_ROOT -u HARBOR_SCOPE_REPO -u HARBOR_REPO sh "$T_TMP/clone/bin/spell.sh" "")"
t_eq "...and that beats HARBOR_SCOPE_REPO" "sh '$T_TMP/clone/bin/harbor' scope install" "$(env -u PORT_ROOT HARBOR_SCOPE_REPO=/from/env sh "$T_TMP/clone/bin/spell.sh" "")"

t_section "floor-verify --live on a box with no config dir"
t_eq "it answers, it does not misuse: exit 1" "exit 1" "$(run sh "$B/admission-verify.sh" --live)"
t_eq "one FAIL" 1 "$(fails)"
t_has "the FAIL names the missing config dir" "$(first)" "no config dir at $C"
t_eq "the fix is the first-run command, not 'see docs/explanation/admission-baseline.md'" "  fix: $FIX" "$(fixof)"
t_eq "a --dir that names no directory has no automatic fix, and says why" "  fix: none automatic — see the path given to --dir" \
  "$(run sh "$B/admission-verify.sh" --dir "$T_TMP/nowhere" >/dev/null; fixof | sed 's/, which names no directory.*//')"

t_section "floor-verify --live on a config dir with no settings.json"
mkdir -p "$C"
run sh "$B/admission-verify.sh" --live >/dev/null
t_has "the wiring check names the missing file" "$(out)" "  FAIL: no settings.json in $CP — the floor has nothing to be wired into"
t_has "...and with nothing installed, says the first-run step was not taken" "$(grep 'no settings.json in' "$T_TMP/out")" "the first-run step has not been taken"
t_has "...fixed by the first-run command" "$(grep -A1 'no settings.json in' "$T_TMP/out")" "  fix: $FIX"
mkdir -p "$C/bin"
run sh "$B/admission-verify.sh" --live >/dev/null
t_has "a box with a bin/ lost the file after the first run, and says so" "$(grep 'no settings.json in' "$T_TMP/out")" "this box has an install (bin/ or .harbor-manifest), so the file was lost after the first run"
t_eq "...without claiming the first-run step was not taken" 0 "$(grep -c 'first-run step has not been taken' "$T_TMP/out")"
t_has "...and with no snapshot the fix is still the first-run command" "$(grep -A1 'no settings.json in' "$T_TMP/out")" "  fix: $FIX"
mkdir -p "$C/backups/deploy-20260101-000000"
run sh "$B/admission-verify.sh" --live >/dev/null
t_has "...with a deploy snapshot it is restore's dry run, which holds the operator's own settings" "$(grep -A1 'no settings.json in' "$T_TMP/out")" "  fix: sh '$B/deploy-restore.sh' --live"
rm -rf "$C"
mkdir -p "$C"; : > "$C/.harbor-manifest"
run sh "$B/admission-verify.sh" --live >/dev/null
t_has "a manifest with no bin/ is an install too" "$(grep 'no settings.json in' "$T_TMP/out")" "so the file was lost after the first run"
rm -rf "$C"

t_section "install-drift: an exit 2 always carries a FAIL line and its fix"
d() { run sh "$B/drift-install.sh" "$@"; }
t_eq "no config dir: exit 2" "exit 2" "$(d --dir "$C" --ref HEAD)"
t_eq "...one FAIL line" 1 "$(fails)"
t_has "...naming the config dir" "$(first)" "no config dir at $C"
t_eq "...fixed by the first-run command" "  fix: $FIX" "$(fixof)"
mkdir -p "$C"
t_eq "a config dir with no settings.json: exit 2" "exit 2" "$(d --dir "$C" --ref HEAD)"
t_has "...names the missing settings.json" "$(first)" "no settings.json in $C"
printf '{}\n' > "$C/settings.json"
t_eq "settings.json but no bin/: exit 2" "exit 2" "$(d --dir "$C" --ref HEAD)"
t_has "...says no deploy has run" "$(first)" "no deploy has run here"
t_eq "...fixed by deploy" "  fix: sh $T_ROOT/bin/deploy.sh --apply --live" "$(fixof)"
mkdir -p "$C/bin"
t_eq "a ref that does not resolve: exit 2" "exit 2" "$(d --dir "$C" --ref no/such/ref)"
t_has "...a FAIL naming the ref" "$(first)" "ref does not resolve: no/such/ref"
t_has "...and a fix line under it" "$(fixof)" "  fix: none automatic"
t_eq "an unknown flag: exit 2" "exit 2" "$(d --bogus)"
t_has "...a FAIL naming the flag" "$(first)" "unknown flag: --bogus"
t_has "...and a fix line under it" "$(fixof)" "--help"
t_eq "--ref with no value: exit 2" "exit 2" "$(d --ref)"
t_has "...a FAIL naming the flag, not the shell's own shift error" "$(first)" "--ref needs a git ref"
t_eq "--dir with no value: exit 2" "exit 2" "$(d --dir)"
t_has "...a FAIL naming the flag" "$(first)" "--dir needs a config dir"
t_eq "--dir with an empty value is the same, not a comparison of /bin" "exit 2" "$(d --dir '' --ref HEAD)"
t_has "...a FAIL naming the flag" "$(first)" "--dir needs a config dir"
if command -v dash >/dev/null 2>&1; then  # the stranger's /bin/sh: its shift dies on a missing operand
  t_eq "under dash, --ref as the last word: exit 2 with a FAIL line" "exit 2" "$(run dash "$B/drift-install.sh" --ref)"
  t_eq "...one FAIL" 1 "$(fails)"
  t_eq "under dash, --dir as the last word: exit 2 with a FAIL line" "exit 2" "$(run dash "$B/drift-install.sh" --dir)"
  t_eq "...one FAIL" 1 "$(fails)"
fi
rm -rf "$C"; mkdir -p "$C"; : > "$C/.harbor-manifest"
t_eq "a manifest and no bin/ (no settings.json): exit 2" "exit 2" "$(d --dir "$C" --ref HEAD)"
t_has "...is an install whose bin/ was removed, not a first run" "$(first)" ".harbor-manifest records an install, so bin/ was removed after the deploy"
t_eq "a dir outside the live one has no automatic fix" "exit 2" "$(d --dir "$T_TMP/other" --ref HEAD)"
t_has "...and says so" "$(fixof)" "none automatic — see the path given to --dir"
rm -rf "$C"

t_section "pin-instructions --live on a box with no config dir"
t_eq "exit 1" "exit 1" "$(run sh "$B/pin-instructions.sh" --live)"
t_has "the FAIL names the missing config dir and the missing first-run step" "$(first)" "no config dir at $C, so there is nothing to pin: the first-run step has not been taken"
t_eq "the fix is the first-run command" "  fix: $FIX" "$(fixof)"
t_eq "--apply says the same" "exit 1" "$(run sh "$B/pin-instructions.sh" --apply --live)"
t_eq "...with the same fix" "  fix: $FIX" "$(fixof)"
t_eq "a --dir that does not exist keeps its own message" "  FAIL: no such config dir: $T_TMP/other" "$(run sh "$B/pin-instructions.sh" --dir "$T_TMP/other" >/dev/null; first)"
t_has "...and the checkout copy of the script runs before any deploy, which is the order's point" "$(sed -n '/^# ORDER/,/^# NO /p' "$B/pin-instructions.sh")" "sh <checkout>/bin/pin-instructions.sh --apply --live"
t_section "a checkout cloned anywhere names itself, with HARBOR_SCOPE_REPO unset"
cp -R "$B" "$T_TMP/clone/binall"; CFIX="sh '$T_TMP/clone/binall/harbor' scope install"
t_eq "pin-instructions --live" "  fix: $CFIX" "$(run env -u HARBOR_SCOPE_REPO -u HARBOR_REPO sh "$T_TMP/clone/binall/pin-instructions.sh" --live >/dev/null; fixof)"
t_eq "floor-verify --live" "  fix: $CFIX" "$(run env -u HARBOR_SCOPE_REPO -u HARBOR_REPO sh "$T_TMP/clone/binall/admission-verify.sh" --live >/dev/null; fixof)"
t_done
