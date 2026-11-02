#!/usr/bin/env sh
# standard-rename.sh on a real guard in a TEMPORARY HOME (harbor#996 item 3): a clone of this tree, the floor installed into a box
# under the sandbox HOME (never ~/.claude), bin/annotate-web.sh renamed to bin/admission-annotate-web.sh, the renamed tree redeployed,
# the box half run. (Its first subject, guard-bash.sh, took its name in W6a; annotate-web is a wired, pinned floor file the waves left.) Settings, pins and tests stay consistent, a known-blocked command still blocks, and the residual list is printed.
# The clone skips .github/ (the Claude sandbox refuses to create it; nothing here reads a workflow).
. "$(dirname "$0")/../../lib/core.sh"; t_init
command -v python3 >/dev/null 2>&1 || { t_section "python3 is absent"; t_exit "the codemod is unchecked without python3" 3 sh "$T_ROOT/bin/standard-rename.sh" --plan --id rename-0001; t_done; }
unset CLAUDE_CONFIG_DIR
CL="$HOME/port/harbor"; CFG="$HOME/box/.claude"
mkdir -p "$CFG/bin"; printf '%s\n' '{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}' > "$CFG/settings.json"
git clone -q -n "$T_ROOT" "$CL" && git -C "$CL" sparse-checkout set --no-cone '/*' '!/.github' && git -C "$CL" checkout -q HEAD \
  && git -C "$CL" config user.email t@t && git -C "$CL" config user.name t || t_fail "could not clone $T_ROOT into $CL"
# The clone is HEAD; carry the working tree's codemod, so an uncommitted run tests itself.
cp "$T_ROOT/bin/standard-rename.sh" "$CL/bin/standard-rename.sh"
R() { ( cd "$CL" && sh bin/standard-rename.sh "$@" ); }
FV() { sh "$CL/bin/admission-verify.sh" --dir "$CFG" 2>&1; }

t_section "the floor is installed in the sandbox box and blocks before the rename"
sh "$CL/bin/admission-install.sh" --apply --dir "$CFG" --with-b6 >/dev/null 2>&1; sh "$CL/bin/pin-instructions.sh" --apply --dir "$CFG" >/dev/null 2>&1
out="$(FV)"; rc=$?
t_eq "floor-verify before: exit 0" 0 "$rc"; t_has "...the floor is on" "$out" "FLOOR IS ON"
t_eq "the floor file is deployed under its old name" present "$([ -f "$CFG/bin/annotate-web.sh" ] && echo present || echo absent)"

t_section "the repo half: the row moves the file and rewrites its references"
printf 'rename-9001\tbin/annotate-web.sh\tbin/admission-annotate-web.sh\tbin\tT3\t-\tsandbox proof of the codemod (harbor#996 item 3)\n' >> "$CL/standards/naming/renames.tsv"
git -C "$CL" commit -qam row
t_eq "the row names a valid new name" 0 "$(sh "$CL/bin/lint-name.sh" --check bin admission-annotate-web.sh --root "$CL" >/dev/null 2>&1; echo $?)"
R --apply --id rename-9001 > "$T_TMP/apply.out" 2>"$T_TMP/apply.err"; t_eq "apply exits 0" 0 "$?"
t_eq "residual 0" "residual 0" "$(head -1 "$T_TMP/apply.out")"
t_eq "the file moved" present "$([ -f "$CL/bin/admission-annotate-web.sh" ] && [ ! -e "$CL/bin/annotate-web.sh" ] && echo present || echo absent)"
t_eq "no true reference to the old path is left outside the register" 0 "$(git -C "$CL" grep -E -c '(^|[^A-Za-z0-9_-])annotate-web[.]sh' -- . ':!standards/naming/renames.tsv' | wc -l | tr -d ' ')"
git -C "$CL" add -A; git -C "$CL" commit -qm applied

t_section "the box half waits for the deploy, then rewires settings and pins"
R --apply --id rename-9001 --dir "$CFG" >/dev/null 2>&1; t_eq "before the deploy it refuses" 1 "$?"
sh "$CL/bin/admission-install.sh" --apply --dir "$CFG" --with-b6 >/dev/null 2>&1
R --apply --id rename-9001 --dir "$CFG" > "$T_TMP/box.out" 2>"$T_TMP/box.err"; t_eq "after it, exit 0" 0 "$?"
t_eq "box residual 0" "residual 0" "$(head -1 "$T_TMP/box.out")"
sh "$CL/bin/pin-instructions.sh" --apply --dir "$CFG" >/dev/null 2>&1
t_eq "settings.json names the new file" yes "$(grep -q 'admission-annotate-web.sh' "$CFG/settings.json" && echo yes || echo no)"
t_eq "...and no longer the old one" 0 "$(grep -c '[^-]annotate-web.sh' "$CFG/settings.json")"
t_eq "the old deployed copy and its pin are gone" "absent absent" "$([ -e "$CFG/bin/annotate-web.sh" ] && echo present || echo absent) $([ -e "$CFG/.helm-pins/annotate-web.sh.sha256" ] && echo present || echo absent)"
t_eq "the new pin is there" present "$([ -f "$CFG/.helm-pins/admission-annotate-web.sh.sha256" ] && echo present || echo absent)"

t_section "a known-blocked command still blocks, and the verify can fail (the red proof)"
out="$(FV)"; rc=$?
t_eq "floor-verify after: exit 0" 0 "$rc"; t_has "...the floor is on" "$out" "FLOOR IS ON"
cp "$CFG/bin/admission-bash.sh" "$T_TMP/ab.keep"; printf '#!/bin/sh\nexit 0\n' > "$CFG/bin/admission-bash.sh"
out="$(FV)"; rc=$?
t_eq "a guard that no longer blocks makes floor-verify exit 1" 1 "$rc"
cp "$T_TMP/ab.keep" "$CFG/bin/admission-bash.sh"

t_section "the tests that guard the floor pass in the renamed tree"
( cd "$CL" && sh tests/admission/baseline/b6.test.sh >"$T_TMP/b6.out" 2>&1 ); t_eq "b6.test exits 0" 0 "$?"
t_has "...with no failure" "$(tail -1 "$T_TMP/b6.out")" " 0 failed"

t_section "the residual list the operator reads"
REP="$CL/build/rename-report.tsv"
echo "# residual list for rename-9001 (annotate-web.sh to admission-annotate-web.sh): what no rewrite decides" >&2
echo "# pattern rows (a glob, regex or built name reaches the file through family guard): $(grep -c '^pattern	' "$REP")" >&2
echo "# stem rows (annotate-web in a log or check id, or prose): $(grep -c '^stem	' "$REP")" >&2
grep '^pattern	' "$REP" | cut -f3 | sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn | head -12 | sed 's/^/#   /' >&2
t_has "the report names the row it judged" "$(cat "$REP")" "row	rename-9001	bin/annotate-web.sh	bin/admission-annotate-web.sh"
t_done
