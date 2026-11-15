#!/usr/bin/env sh
# helper.test.sh (harbor#1278) — bin/member-prereqs.sh, the one root path a member has: it installs the contract's list and refuses everything else.
# The real helper and the real member-integrity.sh, in a moved managed root. apt-get and dnf are stubs, so this proves the argv, never a package landing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SYS="$T_TMP/ClaudeCode"; MR="$SYS/harbor"; B="$MR/bin"; LOG="$T_TMP/pkg.log"
mkdir -p "$B"
for _f in member-prereqs.sh member-integrity.sh library-log.sh library-hub.sh; do cp "$T_ROOT/bin/$_f" "$B/"; done
cp "$T_ROOT/contracts/member-prereqs.txt" "$B/"
: > "$B/harbor-member-mode"; printf '{}\n' > "$SYS/managed-settings.json"
pin() { sh "$B/member-integrity.sh" hash > "$MR/floor.pin"; }
pin
# env -i reaches the stub, so its log path is written into it, and it records what it was handed and what it saw.
mkpkg() { # <name>
  printf '#!/bin/sh\nprintf "%%s %%s APT_CONFIG=%%s HOOK=%%s\\n" "%s" "$*" "${APT_CONFIG:-}" "${HOOK:-}" >> "%s"\nexit "$(cat "%s/pkg.rc" 2>/dev/null || echo 0)"\n' "$1" "$LOG" "$T_TMP" > "$T_BIN/$1"
  chmod +x "$T_BIN/$1"
}
go() { : > "$LOG"; RC=0; sh "$B/member-prereqs.sh" "$@" > "$T_TMP/out" 2>&1 || RC=$?; OUT="$(cat "$T_TMP/out")"; }
want() { awk -v c="$1" '/^[[:space:]]*#/ || !NF { next } $c != "-" { printf "%s ", $c }' "$T_ROOT/contracts/member-prereqs.txt" | sed 's/ $//'; }
mkpkg apt-get

t_section "it installs the list, and only the list"
go
t_eq "exit 0" 0 "$RC"
t_has "update ran first" "$(sed -n 1p "$LOG")" 'apt-get update'
t_eq "install got exactly the contract's packages" "apt-get install -y -q --no-install-recommends $(want 2) APT_CONFIG= HOOK=" "$(sed -n 2p "$LOG")"
t_eq "and nothing else ran" 2 "$(wc -l < "$LOG" | tr -d ' ')"
t_has "CONTROL: the list holds what the guards can't run without" "$(want 2)" 'jq'
t_has "CONTROL: and the sandbox's runtime" "$(want 2)" 'bubblewrap'
rm -f "$T_BIN/apt-get"; mkpkg dnf
# The helper takes apt-get first from the system PATH, so where a real one is installed the dnf stub is never reached.
if PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v apt-get >/dev/null 2>&1; then echo "helper-test: SKIPPED dnf column (this box has a real apt-get)"
else go; t_eq "dnf gets its own column" "dnf install -y -q $(want 3) APT_CONFIG= HOOK=" "$(cat "$LOG")"; fi
rm -f "$T_BIN/dnf"; mkpkg apt-get
printf 1 > "$T_TMP/pkg.rc"; go; t_eq "a failed install is a failed run" 1 "$RC"; rm -f "$T_TMP/pkg.rc"

t_section "an argument is refused before anything runs"
for _a in curl -y -h '../evil.deb' '-oAPT::Foo=1'; do
  go "$_a"
  t_eq "$_a: exit 2" 2 "$RC"
  t_eq "$_a: the package manager never ran" '' "$(cat "$LOG")"
done
go curl jq; t_eq "two of them too" 2 "$RC"
go --help curl; t_eq "--help is no way to pass one" 2 "$RC"; t_eq "and nothing ran" '' "$(cat "$LOG")"
go --help; t_eq "--help alone answers" 0 "$RC"; t_has "with what this is" "$OUT" 'takes none'; t_eq "and installs nothing" '' "$(cat "$LOG")"
go ''; t_eq "and an empty one" 2 "$RC"

t_section "the caller's environment adds nothing"
: > "$LOG"; APT_CONFIG=/tmp/evil HOOK=evil sh "$B/member-prereqs.sh" > /dev/null 2>&1
t_eq "CONTROL: it ran" 2 "$(wc -l < "$LOG" | tr -d ' ')"
t_hasnt "APT_CONFIG stops at the helper" "$(cat "$LOG")" 'evil'

t_section "a list that isn't the fixed list installs nothing"
cp "$B/member-prereqs.txt" "$T_TMP/list.keep"
printf 'nc netcat-traditional netcat\n' >> "$B/member-prereqs.txt"
go; t_eq "a row added after the pin: refused" 1 "$RC"
t_has "named" "$OUT" 'member-integrity.sh check'
t_eq "and the package manager never ran" '' "$(cat "$LOG")"
# Past the hash, as if the pin were rewritten too: the names are still held to plain package names.
for _bad in 'x ../evil.deb -' 'x -oDebug=1 -' 'x jq=1.5 -' 'x evil.deb/x -' 'x Jq -' 'too many columns here'; do
  { cat "$T_TMP/list.keep"; printf '%s\n' "$_bad"; } > "$B/member-prereqs.txt"; pin
  go
  t_eq "a row of '$_bad' with the pin rewritten: refused" 1 "$RC"
  t_eq "and nothing installed, not even the good rows" '' "$(cat "$LOG")"
done
cp "$T_TMP/list.keep" "$B/member-prereqs.txt"; pin

t_section "only in a managed root"
rm "$B/harbor-member-mode"; pin; go
t_eq "no marker beside it: refused" 1 "$RC"; t_eq "and nothing ran" '' "$(cat "$LOG")"
: > "$B/harbor-member-mode"; pin
go; t_eq "CONTROL: put back, it runs" 0 "$RC"
mv "$B/member-prereqs.txt" "$T_TMP/list.off"; pin; go
t_eq "no list: refused" 1 "$RC"; t_eq "and nothing ran" '' "$(cat "$LOG")"
mv "$T_TMP/list.off" "$B/member-prereqs.txt"; pin
rm -f "$T_BIN/apt-get"
# A test PATH can reach the real tools, so this only speaks where neither manager is on it.
if command -v apt-get >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then echo "helper-test: SKIPPED no-manager case (this box has one)"
else go; t_eq "no package manager: refused, not a pass" 1 "$RC"; fi

t_section "the contract"
t_eq "every row is three columns" 0 "$(awk '/^[[:space:]]*#/ || !NF { next } NF != 3 { n++ } END { print n + 0 }' "$T_ROOT/contracts/member-prereqs.txt")"
t_has "member-files.txt ships the helper" "$(cat "$T_ROOT/contracts/member-files.txt")" 'bin/member-prereqs.sh'
t_has "and its list, beside it" "$(cat "$T_ROOT/contracts/member-files.txt")" 'contracts/member-prereqs.txt member-prereqs.txt'
t_done
