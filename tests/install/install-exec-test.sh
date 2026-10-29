#!/usr/bin/env sh
# il_install_exec: a script is installed by rename, so a shell already running it keeps reading the old
# bytes. With an in-place cp, bash resumes at its old offset in the NEW bytes — on 2026-10-15 that ran
# an example command quoted in a guard's comment. The probe payload here is `touch`, never destructive.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; mkdir -p "$T/bin" "$T/dst"
cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/install-lib.sh" "$T/bin/"
printf '%s\n' '. "$(dirname -- "$0")/install-lib.sh"' 'il_install_exec "$1" "$2"' > "$T/bin/drive.sh"

# old: sleeps, then writes OUT. new: same first line, then touches MARK — reached only by a resume in the new bytes.
old() { printf 'sleep 1\necho old > %s/out-%s\n' "$T" "$1"; }
new() { printf 'sleep 1\ntouch %s/mark-%s\n' "$T" "$1"; }
race() { # <arm> <installer…> → run old under bash, swap in new mid-sleep
  _a="$1"; shift; old "$_a" > "$T/dst/g-$_a.sh"; new "$_a" > "$T/new-$_a.sh"
  bash "$T/dst/g-$_a.sh" & _p=$!
  sleep 0.3; "$@" "$T/new-$_a.sh" "$T/dst/g-$_a.sh"; wait "$_p"
}
inplace() { cp "$1" "$2"; }

t_section "the hazard: an in-place copy runs the new bytes in the running shell"
race cp inplace
t_exit "bash resumed in the new bytes (the probe that il_install_exec must defeat)" 0 test -e "$T/mark-cp"

t_section "il_install_exec: the running shell finishes the old script"
race il sh "$T/bin/drive.sh"
t_exit "the old script's second line ran" 0 test -e "$T/out-il"
t_exit "the new bytes were not executed by the running shell" 0 test ! -e "$T/mark-il"
t_exit "the destination now holds the new bytes" 0 cmp -s "$T/new-il.sh" "$T/dst/g-il.sh"
t_exit "the destination is executable" 0 test -x "$T/dst/g-il.sh"
t_exit "no temp file is left beside it" 0 test -z "$(find "$T/dst" -name '*.tmp.*')"

t_section "a failed install leaves the destination unchanged"
printf 'keep\n' > "$T/dst/k.sh"
t_exit "a missing source returns 1" 1 sh "$T/bin/drive.sh" "$T/absent" "$T/dst/k.sh"
t_exit "the destination keeps its bytes" 0 grep -qx keep "$T/dst/k.sh"
t_exit "no temp file is left" 0 test -z "$(find "$T/dst" -name '*.tmp.*')"
t_done
