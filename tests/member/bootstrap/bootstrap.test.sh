#!/usr/bin/env sh
# member-bootstrap.sh (harbor#1278): it stands alone, takes one commit and nothing else, and hands the rest to the install (R3, R10, R25).
. "$(dirname "$0")/../../lib/core.sh"; t_init
T_TMP="$(cd "$T_TMP" && pwd -P)"
. "$T_ROOT/tests/member/fixture.sh"
ALONE="$T_TMP/alone"; mkdir -p "$ALONE"; cp "$T_ROOT/bin/member-bootstrap.sh" "$ALONE/"   # beside nothing: it may read no sibling
SRC="$T_TMP/harbor-core"; mkdir -p "$SRC/bin"
cp "$T_ROOT/bin/library-log.sh" "$SRC/bin/"
stub "$SRC/bin/member-install.sh" 'printf "install %s\n" "$*" >> "$CALLS"; printf "%s\n" "$PWD" >/dev/null'
git -C "$SRC" init -q -b main; git -C "$SRC" add -A; git -C "$SRC" -c user.name=t -c user.email=t@t commit -q -m one
OLD="$(git -C "$SRC" rev-parse HEAD)"
printf 'two\n' > "$SRC/two"; git -C "$SRC" add -A; git -C "$SRC" -c user.name=t -c user.email=t@t commit -q -m two
NEW="$(git -C "$SRC" rev-parse HEAD)"
D="$T_TMP/opt/harbor-core"; mkdir -p "${D%/*}"
boot() { RC=0; sh "$ALONE/member-bootstrap.sh" --source "$SRC" --dir "$D" "$@" >"$OUT" 2>&1 </dev/null || RC=$?; }

t_section "stands alone, at the pin"
boot --pin "$OLD" --user alice --hub o/n; t_eq "a pin older than main clones and runs" 0 "$RC"
t_eq "HEAD is the pin, not main" "$OLD" "$(git -C "$D" rev-parse HEAD)"
t_eq "detached" '' "$(git -C "$D" symbolic-ref -q HEAD)"
t_has "the rest goes to the install, pin first" "$(cat "$CALLS")" "install --pin $OLD --user alice --hub o/n"
: > "$CALLS"; boot --user alice --pin "$NEW" --hub o/n; t_eq "a re-run moves the pin" "$NEW" "$(git -C "$D" rev-parse HEAD)"
t_has "the order of the rest is kept" "$(cat "$CALLS")" "install --pin $NEW --user alice --hub o/n"
boot --pin "$OLD" --user alice; t_eq "...and back: a rollback is the same run" "$OLD" "$(git -C "$D" rev-parse HEAD)"
printf x > "$D/planted"; boot --pin "$OLD" --user alice
t_eq "an untracked file left behind is cleaned" no "$([ -e "$D/planted" ] && echo yes || echo no)"
t_has "the default source is the public export (R25)" "$(cat "$ALONE/member-bootstrap.sh")" 'harbor-core.git'

t_section "refusals"
: > "$CALLS"
boot --user alice; t_eq "no pin" 2 "$RC"
boot --pin main --user alice; t_eq "a branch name is no pin" 2 "$RC"
boot --pin "${OLD%?}" --user alice; t_eq "a short pin" 2 "$RC"
boot --pin 0000000000000000000000000000000000000000 --user alice; t_eq "a commit the source doesn't have" 1 "$RC"
t_has "...says an export comes first" "$(cat "$OUT")" 'export must reach harbor-core'
t_eq "nothing reached the install" 0 "$(wc -l < "$CALLS" | tr -d ' ')"
# A link to a working checkout: anything less fails at the clone, and the refusal would never be what decided it.
rm -rf "$D"; git clone -q "$SRC" "$T_TMP/elsewhere"; ln -s "$T_TMP/elsewhere" "$D"; boot --pin "$OLD" --user alice
t_eq "a link where the checkout goes" 1 "$RC"; t_has "...named as a link" "$(cat "$OUT")" 'symbolic link'; rm -f "$D"
mkdir -p "$D"; : > "$D/x"; boot --pin "$OLD" --user alice; t_eq "a folder that isn't a checkout" 1 "$RC"; rm -rf "$D"
git -C "$SRC" rm -q bin/member-install.sh; git -C "$SRC" -c user.name=t -c user.email=t@t commit -qm three; P3="$(git -C "$SRC" rev-parse HEAD)"
boot --pin "$P3" --user alice; t_eq "a commit with no install" 1 "$RC"; t_has "...is named" "$(cat "$OUT")" 'predates the member install'
RC=0; env -u HARBOR_SCOPE_MANAGED_SETTINGS sh "$ALONE/member-bootstrap.sh" --pin "$OLD" >"$OUT" 2>&1 || RC=$?
t_eq "not root, no test override" 1 "$RC"
t_exit "--help answers with no root" 0 env -u HARBOR_SCOPE_MANAGED_SETTINGS sh "$ALONE/member-bootstrap.sh" --help
t_done
