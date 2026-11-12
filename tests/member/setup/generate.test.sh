#!/usr/bin/env sh
# member-setup-generate.sh (harbor#1278): a scratch harbor-core whose member-windows.sh is a stub that echoes its arguments, so each person's
# script shows what the pin was asked for. No network, no real hub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
G="$T_ROOT/bin/member-setup-generate.sh"
GIT="git -c user.name=t -c user.email=t@t"
command -v zip >/dev/null 2>&1 && command -v unzip >/dev/null 2>&1 || { echo "member-setup-generate: skipped (zip/unzip missing)"; t_done; exit 0; }

CORE="$T_TMP/core"; mkdir -p "$CORE/bin"; git init -q -b main "$CORE"
cp "$T_ROOT/bin/library-log.sh" "$CORE/bin/"
cat > "$CORE/bin/member-windows.sh" <<'STUB'
#!/bin/sh
printf 'setup for %s (generator lines %s)\n' "$*" "$(wc -l < "$0" | tr -d ' ')"
[ "$5" != bad ] || { echo "refused: bad user" >&2; exit 1; }
STUB
$GIT -C "$CORE" add -A; $GIT -C "$CORE" commit -q -m one; PIN="$(git -C "$CORE" rev-parse HEAD)"
printf '# newer\n' >> "$CORE/bin/member-windows.sh"; $GIT -C "$CORE" commit -qam two; PIN2="$(git -C "$CORE" rev-parse HEAD)"

KIT="$T_TMP/kit"; mkdir -p "$KIT"; for f in run-setup.ps1 INSTALL-FOR-CLAUDE.md CLAUDE.md; do printf 'kit %s\n' "$f" > "$KIT/$f"; done
SIG="$T_TMP/signers"; printf 'hub namespaces="harbor-hub" ssh-ed25519 AAAA\n' > "$SIG"
printf '# who gets a setup\nuser1\tlogin-one\n\nuser2\tlogin-two\n' > "$T_TMP/roster"
run() { # <out> <args...>
  _o="$1"; shift; sh "$G" --core "$CORE" --hub org/hub --signers "$SIG" --kit "$KIT" --out "$_o" "$@" > "$T_TMP/out" 2>&1; RC=$?
}

t_section "every person, at the pin"
run "$T_TMP/o1" --pin "$PIN" --roster "$T_TMP/roster"
t_eq "exit 0" 0 "$RC"
for u in user1 user2; do
  t_has "$u script asked the pin's generator" "$(cat "$T_TMP/o1/bundles/$u/setup-$u.ps1")" "--setup --pin $PIN --user $u --hub org/hub --login login-"
  t_eq "$u hash file is the script's hash" "$( (shasum -a 256 "$T_TMP/o1/bundles/$u/setup-$u.ps1" 2>/dev/null || sha256sum "$T_TMP/o1/bundles/$u/setup-$u.ps1") | cut -d' ' -f1)" "$(cat "$T_TMP/o1/bundles/$u-HASH.txt")"
  t_eq "$u zip holds the five files" "CLAUDE.md HASH.txt INSTALL-FOR-CLAUDE.md run-setup.ps1 setup-$u.ps1" "$(unzip -Z1 "$T_TMP/o1/zips/setup-$u.zip" | sort | tr '\n' ' ' | sed 's/ $//')"
done
t_has "the login rides to the right person" "$(cat "$T_TMP/o1/bundles/user2/setup-user2.ps1")" "--login login-two"
t_eq "kit files unchanged" "kit run-setup.ps1" "$(cat "$T_TMP/o1/bundles/user1/run-setup.ps1")"
t_eq "the comment line is no person" 2 "$(ls "$T_TMP/o1/zips" | wc -l | tr -d ' ')"

t_section "the pin's own generator, not the checkout's tip"
run "$T_TMP/o2" --pin "$PIN2" --roster "$T_TMP/roster"
t_has "the first pin's file ran for the first pin" "$(cat "$T_TMP/o1/bundles/user1/setup-user1.ps1")" "generator lines 3"
t_has "the second pin's file ran for the second" "$(cat "$T_TMP/o2/bundles/user1/setup-user1.ps1")" "generator lines 4"
t_eq "a different pin, a different hash" "yes" "$([ "$(cat "$T_TMP/o1/bundles/user1-HASH.txt")" != "$(cat "$T_TMP/o2/bundles/user1-HASH.txt")" ] && echo yes)"
t_eq "the scratch worktree is gone" "" "$(git -C "$CORE" worktree list | grep -v "$CORE" | head -n 1)"

t_section "one failure does not hide the rest"
printf 'user1\tlogin-one\nbad\tlogin-bad\nuser2\tlogin-two\n' > "$T_TMP/roster-bad"
run "$T_TMP/o3" --pin "$PIN" --roster "$T_TMP/roster-bad"
t_eq "exit 1" 1 "$RC"
t_has "names the person" "$(cat "$T_TMP/out")" "bad: the pin's member-windows.sh refused"
t_eq "the others were still built" 2 "$(ls "$T_TMP/o3/zips" | wc -l | tr -d ' ')"
printf 'user1\n' > "$T_TMP/roster-nologin"
run "$T_TMP/o4" --pin "$PIN" --roster "$T_TMP/roster-nologin"; t_eq "a line without a login: exit 1" 1 "$RC"

t_section "refusals"
run "$T_TMP/o5" --pin "$(printf 'a%.0s' $(seq 40))" --roster "$T_TMP/roster"; t_eq "a pin not in the checkout: exit 1" 1 "$RC"
t_has "...says so" "$(cat "$T_TMP/out")" "is not in"
t_eq "no pin" 2 "$(run "$T_TMP/o6" --roster "$T_TMP/roster"; echo $RC)"
t_eq "short pin" 2 "$(run "$T_TMP/o6" --pin abc --roster "$T_TMP/roster"; echo $RC)"
t_eq "no roster file" 2 "$(run "$T_TMP/o6" --pin "$PIN" --roster "$T_TMP/none"; echo $RC)"
: > "$T_TMP/empty"; t_eq "an empty roster" 2 "$(run "$T_TMP/o6" --pin "$PIN" --roster "$T_TMP/empty"; echo $RC)"
rm "$KIT/CLAUDE.md"; t_eq "a kit missing a file" 2 "$(run "$T_TMP/o6" --pin "$PIN" --roster "$T_TMP/roster"; echo $RC)"
t_eq "unknown flag" 2 "$(run "$T_TMP/o6" --pin "$PIN" --roster "$T_TMP/roster" --zap; echo $RC)"
sh "$G" --help >/dev/null 2>&1; t_eq "--help exits 0" 0 "$?"
t_done
