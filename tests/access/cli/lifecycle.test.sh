#!/usr/bin/env sh
# `harbor access status|rotate|revoke` and the lifecycle fields (harbor#1205): one controller for a credential's life.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
# NOT COVERED here: bin/secret rotate's exit 4 (the put-back itself failing) needs a store that fails on the
# second write only; and the interactive value prompt of rotate, which needs a human at the keyboard.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
SC() { sh "$T_ROOT/bin/secret" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port" ACCESS_STATE="$T_TMP/state.tsv"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
rc() { "$@" >/dev/null 2>&1; echo $?; }
TODAY="$(date -u +%Y-%m-%d)"
entry() { # <id> <ref> [extra field lines...]
  _i="$1"; _r="$2"; shift 2
  printf '\n## %s\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: %s\n' "$_i" "$_r" >> "$REG"
  for _l in "$@"; do printf '    %s\n' "$_l" >> "$REG"; done
}
put() { printf '%s' "$2" | SC put "$1" >/dev/null 2>&1; }  # <ref> <value>
# A check that is alive only while the stored value starts good-, and never prints the value itself.
alive() { printf 'check: sh %s run %s V -- sh -c '"'"'case "$V" in good-*) echo alive ;; esac'"'"'' "$T_ROOT/bin/secret" "$1"; }
EXPECT='expect: prints `alive`'
days_from_today() { awk -v n="$1" -v t="$TODAY" 'BEGIN { split(t, a, "-"); y = a[1]; m = a[2]; d = a[3] + n
  while (1) { ml = (m == 2) ? (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
    if (d > ml) { d -= ml; m++; if (m > 12) { m = 1; y++ } } else if (d < 1) { m--; if (m < 1) { m = 12; y-- }
      d += (m == 2) ? (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31) } else break }
  printf "%04d-%02d-%02d\n", y, m, d }'; }

t_section "status on a header-only register"
t_eq "exit 0" 0 "$(rc AX status)"
t_has "...and the tally says 0 entries" "$(AX status 2>&1)" "0 entries"

t_section "status: ok, unprobed, unmanaged and n/a are not red, and are counted"
entry live-one live-ref "$(alive live-ref)" "$EXPECT" "renew: mint it" "revoke: kill it"; put live-ref good-1
entry quiet-one quiet-ref; put quiet-ref good-2
entry outside-one none
printf '\n## a-login\n\n    kind: account\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: none\n' >> "$REG"
OUT="$(AX status 2>&1)"; RC=$(rc AX status)
t_eq "exit 0" 0 "$RC"
t_has "the tally counts each state" "$OUT" "4 entries: 1 ok, 1 unprobed, 1 unmanaged, 1 n/a, 0 red"
t_hasnt "a healthy entry prints no line by default" "$OUT" "live-one"
t_has "-v prints every entry" "$(AX status -v 2>&1)" "live-one"
t_has "...a stored ref with no recipe says so" "$(AX status -v 2>&1)" "no renew:/revoke: recipe"

t_section "status: the reds"
entry dead-one dead-ref "$(alive dead-ref)" "$EXPECT"; put dead-ref bad-1
entry gone-one gone-ref
entry late-one late-ref "expires: $(days_from_today -1)"; put late-ref good-3
entry soon-one soon-ref "expires: $(days_from_today 5)"; put soon-ref good-4
entry slow-one slow-ref 'check: sleep 5; echo alive' "$EXPECT"; put slow-ref good-5
entry write-one write-ref "check: rm -rf $T_TMP/keepme" "$EXPECT"; put write-ref good-6; mkdir "$T_TMP/keepme"
OUT="$(PROBE_TIMEOUT=1 AX status 2>&1)"; RC=$(PROBE_TIMEOUT=1 rc AX status)
t_eq "exit 1" 1 "$RC"
t_has "a failing check is FAIL" "$OUT" "FAIL            dead-one"
t_has "a ref not in the store is MISSING" "$OUT" "MISSING         gone-one"
t_has "a past expires: is EXPIRED" "$OUT" "EXPIRED         late-one"
t_has "an expiry within 14 days is a warning line" "$OUT" "expiring        soon-one"
t_has "a hung check is TIMEOUT" "$OUT" "TIMEOUT         slow-one"
t_has "a check that writes is REFUSED" "$OUT" "REFUSED         write-one"
t_eq "...and was never run" present "$([ -d "$T_TMP/keepme" ] && echo present || echo gone)"
t_has "each red says since when" "$OUT" "new today"
t_hasnt "no stored value reached the output" "$OUT" "bad-1"

t_section "status: the age of a standing red comes from the state file, outside the register"
REGSUM="$(cksum < "$REG")"
awk -F'\t' -v OFS='\t' '$1 == "dead-one" { $3 = "2026-01-01" } { print }' "$ACCESS_STATE" > "$T_TMP/s" && mv "$T_TMP/s" "$ACCESS_STATE"
t_has "an unchanged state keeps its first day" "$(PROBE_TIMEOUT=1 AX status dead-one 2>&1)" "since 2026-01-01"
t_eq "status never wrote the register" "$REGSUM" "$(cksum < "$REG")"
put dead-ref good-7
t_has "a changed state starts again today" "$(AX status -v dead-one 2>&1)" "new today"
t_eq "a named id that does not exist: exit 2" 2 "$(rc AX status no-such-id)"

t_section "status: an interrupt stops it"
entry hang-one hang-ref 'check: sleep 4; echo alive' "$EXPECT"; put hang-ref good-h
sh "$T_ROOT/bin/access.sh" status hang-one >/dev/null 2>&1 & _sp=$!
sleep 1; kill -INT "$_sp" 2>/dev/null; kill -TERM "$_sp" 2>/dev/null; wait "$_sp"; _rc=$?
t_eq "exit 130" 130 "$_rc"

t_section "status: a check that prints a credential and fails never shows it"
entry leak-one leak-ref 'check: echo leaked-0123456789; exit 1' "$EXPECT"; put leak-ref good-8
t_hasnt "the probe's output is not printed" "$(AX status leak-one 2>&1)" "leaked-0123456789"

t_section "status and stored: a store that cannot be listed is not a pass"
mkdir -p "$T_TMP/nolist"; printf '#!/bin/sh\ncase "$1" in dump-keychain) exit 1 ;; esac\nexec "%s/security" "$@"\n' "$T_BIN" > "$T_TMP/nolist/security"; chmod +x "$T_TMP/nolist/security"
t_eq "secret list exits 1" 1 "$(PATH="$T_TMP/nolist:$PATH" rc SC list)"
t_eq "status exits 2" 2 "$(PATH="$T_TMP/nolist:$PATH" rc AX status)"
t_eq "stored exits 2" 2 "$(PATH="$T_TMP/nolist:$PATH" rc AX stored)"

t_section "rotate: a good new value is kept and dated; a bad one is refused and the old one is back"
entry rot-one rot-ref "$(alive rot-ref)" "$EXPECT" "renew: mint it at the vendor" "revoke: delete the old key at the vendor"; put rot-ref good-old
OUT="$(printf 'good-new' | AX rotate rot-one --value-stdin 2>&1)"; RC=$?
t_eq "a good value: exit 0" 0 "$(printf 'good-new2' | rc AX rotate rot-one --value-stdin)"
t_has "...and says rotated" "$OUT" "rotated 'rot-one'"
t_has "...and names the operator's last step, the revoke recipe" "$OUT" "delete the old key at the vendor"
t_eq "the store holds the new value" good-new2 "$(SC run rot-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_has "rotated: is today" "$(cat "$REG")" "    rotated: $TODAY"
t_eq "the register is still well formed" 0 "$(rc AX check)"
OUT="$(printf 'bad-new' | AX rotate rot-one --value-stdin 2>&1)"; RC=$?
t_eq "a bad value: exit 1" 1 "$RC"
t_has "...says it was not rotated" "$OUT" "was NOT rotated"
t_eq "...and the old value is back, byte for byte" good-new2 "$(SC run rot-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_hasnt "no value in the output" "$OUT" "bad-new"
t_hasnt "no value in any store call's argv" "$(cat "$KC_STUB/argv.log")" "bad-new"
entry fresh-one fresh-ref "$(alive fresh-ref)" "$EXPECT"
t_eq "nothing before and a bad value: exit 1" 1 "$(printf 'bad-x' | rc AX rotate fresh-one --value-stdin)"
t_eq "...and nothing is left stored" 1 "$(rc SC run fresh-ref V -- true)"
t_eq "an entry with no check: refused, exit 1" 1 "$(printf 'good-x' | rc AX rotate quiet-one --value-stdin)"
t_eq "...and the value was not touched" good-2 "$(SC run quiet-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
entry man-one man-ref 'check: ssh somewhere true' "$EXPECT"; put man-ref good-man
ARGV_BEFORE="$(wc -l < "$KC_STUB/argv.log")"
t_eq "a check that is not a runnable read: refused, exit 1" 1 "$(printf 'good-y' | rc AX rotate man-one --value-stdin)"
t_has "...naming the kind of check" "$(printf 'good-y' | AX rotate man-one --value-stdin 2>&1)" "has a manual check"
t_eq "...and the store was never written" "$ARGV_BEFORE" "$(wc -l < "$KC_STUB/argv.log")"
t_eq "an entry with no ref: exit 2" 2 "$(printf 'x' | rc AX rotate outside-one --value-stdin)"
t_eq "no value and no terminal: exit 2" 2 "$(rc AX rotate rot-one </dev/null)"

t_section "rotate: a store that fails mid-write, and an interrupt, still roll back"
mkdir -p "$T_TMP/trunc"; FLAG="$T_TMP/trunc/once"; export FLAG
# The 128-character truncation incident, once: the first write after the flag is cut short, later ones are not.
cat > "$T_TMP/trunc/security" <<EOF
#!/bin/sh
if [ "\$1" = add-generic-password ] && [ -f "\$FLAG" ]; then
  rm -f "\$FLAG"; n=0
  for a in "\$@"; do n=\$((n + 1)); [ "\$p" = -w ] && set -- "\$@" short || set -- "\$@" "\$a"; p="\$a"; done
  shift "\$n"
fi
exec "$T_BIN/security" "\$@"
EOF
chmod +x "$T_TMP/trunc/security"
entry trunc-one trunc-ref "$(alive trunc-ref)" "$EXPECT"; put trunc-ref good-keep
touch "$FLAG"
OUT="$(printf 'good-new' | PATH="$T_TMP/trunc:$PATH" AX rotate trunc-one --value-stdin 2>&1)"; RC=$?
t_eq "a failed write: exit 1" 1 "$RC"
t_has "...says the new value could not be stored" "$OUT" "could not be stored"
t_eq "...and the old value still loads, byte for byte" good-keep "$(SC run trunc-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
entry intr-one intr-ref 'check: sleep 3; echo alive' "$EXPECT"
printf 'good-i' > "$T_TMP/ival"   # a file, not a pipe: $! must be bin/secret itself, not a wrapper subshell
sh "$T_ROOT/bin/secret" rotate intr-ref -- sleep 3 < "$T_TMP/ival" >/dev/null 2>&1 & _rp=$!
sleep 1; kill -TERM "$_rp" 2>/dev/null; wait "$_rp"; _rc=$?
t_eq "an interrupted rotate exits 130" 130 "$_rc"
t_eq "...and a value that was never proved is not left behind" 0 "$(SC list | grep -c 'secret.intr-ref$')"

t_section "a date is never spliced into awk's program"
t_eq "add: --expires carrying awk code is refused" 2 "$(rc AX add inj1 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --expires '2026-01-01") + system("touch '"$T_TMP"'/pwned1") + okdate("2026-01-01')"
t_eq "...and ran nothing" gone "$([ -e "$T_TMP/pwned1" ] && echo present || echo gone)"
cp "$REG" "$T_TMP/pre-inj"; entry inj2 none "expires: 2026-01-01\") + system(\"touch $T_TMP/pwned2\") + okdate(\"x"
AX status inj2 >/dev/null 2>&1
t_eq "status on a register line carrying awk code ran nothing" gone "$([ -e "$T_TMP/pwned2" ] && echo present || echo gone)"
t_eq "...and check names the line" 1 "$(rc AX check)"
cp "$T_TMP/pre-inj" "$REG"

t_section "revoke: the ref is refused first, then the value goes; the legacy list cannot bring it back"
LEG="$T_TMP/legacy.txt"; printf 'rot-ref bin/old-consumer\n' > "$LEG"
OUT="$(ACCESS_LEGACY_REFS="$LEG" AX revoke rot-one 2>&1)"
t_has "revoke says it is revoked" "$OUT" "'rot-one' is revoked"
t_has "...and names the source-side step" "$OUT" "delete the old key at the vendor"
t_has "revoked: is today" "$(cat "$REG")" "    revoked: $TODAY"
t_eq "has says 4, revoked, even with the ref on the legacy list" 4 "$(ACCESS_LEGACY_REFS="$LEG" rc AX has rot-ref)"
t_eq "the store no longer holds it" 0 "$(SC list | grep -c 'secret.rot-ref$')"
t_eq "bin/secret refuses to store under it" 1 "$(printf 'good-z' | ACCESS_LEGACY_REFS="$LEG" rc SC put rot-ref)"
t_eq "rotate refuses a revoked entry" 1 "$(printf 'good-z' | rc AX rotate rot-one --value-stdin)"
printf 'v1:b64:%s' "$(printf 'x' | base64)" > "$KC_STUB/items/secret.rot-ref@${USER:-$(id -un)}"
t_eq "an item still stored under a revoked ref: stored is red" 1 "$(rc AX stored)"
t_has "...as REVOKED, with secret rm as the fix" "$(AX stored 2>&1)" "secret rm rot-ref"
t_has "...and status says REVOKED-STORED" "$(AX status rot-one 2>&1)" "REVOKED-STORED"
t_eq "a second revoke removes it and is not an error" 0 "$(rc AX revoke rot-one)"

t_section "revoke and rotate refuse a register the grammar rejects"
cp "$REG" "$T_TMP/pre-dup"
entry dup-one dup-ref-1; entry dup-one dup-ref-2; put dup-ref-1 good-d
t_eq "revoke on a repeated id: exit 1" 1 "$(rc AX revoke dup-one)"
t_eq "...the ref is still admitted, so nothing pretended otherwise" 0 "$(rc AX has dup-ref-1)"
t_eq "...and the value was not removed" good-d "$(SC run dup-ref-1 V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_eq "rotate on it: exit 1" 1 "$(printf 'good-e' | rc AX rotate dup-one --value-stdin)"
cp "$T_TMP/pre-dup" "$REG"

t_section "probe: an interrupt ends the probe even when pkill finds no child"
mkdir -p "$T_TMP/nopk"; printf '#!/bin/sh\nexit 1\n' > "$T_TMP/nopk/pkill"; chmod +x "$T_TMP/nopk/pkill"
PATH="$T_TMP/nopk:$PATH" sh "$T_ROOT/skills/access-ledger/bin/check-routes.sh" --probe "sleep 6; echo alive" 'prints `alive`' >/dev/null 2>&1 & _pp=$!
sleep 1; kill -TERM "$_pp" 2>/dev/null; wait "$_pp"; _rc=$?
t_eq "exit 130, not set -e's 1" 130 "$_rc"

t_section "check: the lifecycle fields' grammar"
good="$T_TMP/good.md"; cp "$REG" "$good"
field_is_red() { # <label> <expected> <field lines...>
  _l="$1"; _e="$2"; shift 2; cp "$good" "$REG"; entry hand-edit none "$@"
  t_eq "$_l: check is red" 1 "$(rc AX check)"; t_has "$_l: and says why" "$(AX check 2>&1)" "$_e"; cp "$good" "$REG"
}
field_is_red "an impossible date" "expires 2026-02-30 is not a calendar date" "expires: 2026-02-30"
field_is_red "month 13" "rotated 2026-13-01 is not a calendar date" "rotated: 2026-13-01"
field_is_red "a check with no expect" "check and expect go together" "check: true"
field_is_red "an expect with no literal" "expect carries no backticked literal" "check: true" "expect: something"
t_eq "the good register is green" 0 "$(rc AX check)"

t_section "add: the lifecycle flags are written, checked and scanned"
FAKECRED="ghp_$(printf 'a%.0s' $(seq 1 36))"
printf 'good-a' | AX add add-one --kind token --what w --use-when u --reaches r --cannot c --grant g --secret add-ref \
  --check "$(alive add-ref | sed 's/^check: //')" --expect 'prints `alive`' --expires 2030-01-31 --renew "mint it" --revoke "kill it" --value-stdin >/dev/null 2>&1
t_has "check: is written" "$(cat "$REG")" "    expect: prints \`alive\`"
t_has "expires: is written" "$(cat "$REG")" "    expires: 2030-01-31"
t_has "a stored value dates rotated:" "$(cat "$REG")" "    rotated: $TODAY"
t_eq "and status passes it" 0 "$(rc AX status add-one)"
BEFORE="$(cksum < "$REG")"
t_eq "--expires not a date: exit 2" 2 "$(rc AX add x1 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --expires 2030-02-31)"
t_eq "--check without --expect: exit 2" 2 "$(rc AX add x2 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --check true)"
t_eq "a credential in --renew: exit 2" 2 "$(rc AX add x3 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --renew "$FAKECRED")"
t_eq "a credential in --probe: exit 2" 2 "$(rc AX add x4 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --probe "curl -H 'Authorization: token $FAKECRED' x")"
t_hasnt "...and the probe command is never echoed" "$(AX add x5 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret --probe 'echo probe-text-xyz' 2>&1)" "probe-text-xyz"
cp "$REG" "$T_TMP/after-x5"; BEFORE="$(cksum < "$REG")"

t_section "one writer at a time: a held lock refuses, and leaves the register as it was"
mkdir "$REG.lock"
t_eq "add while locked: exit 1" 1 "$(ACCESS_LOCK_WAIT=1 rc AX add x6 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret)"
t_has "...naming the lock" "$(ACCESS_LOCK_WAIT=1 AX add x6 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret 2>&1)" "rmdir $REG.lock"
t_eq "revoke while locked: exit 1" 1 "$(ACCESS_LOCK_WAIT=1 rc AX revoke add-one)"
t_eq "the register is untouched" "$BEFORE" "$(cksum < "$REG")"
rmdir "$REG.lock"
t_eq "a finished write leaves no lock behind" 0 "$(rc AX add x7 --kind token --what w --use-when u --reaches r --cannot c --grant g --no-secret)"
t_eq "...the lock directory is gone" gone "$([ -d "$REG.lock" ] && echo present || echo gone)"

t_section "held: a credential outside the seam by design is told apart from a migration debt"
cp "$REG" "$T_TMP/before-held"
entry held-one none "held: an Actions secret of the repository, never on the box"
t_eq "check is green on it" 0 "$(rc AX check)"
OUT="$(AX status -v held-one outside-one 2>&1)"
t_eq "status is not red" 0 "$(rc AX status held-one outside-one)"
t_has "a held entry is its own state, with its why" "$OUT" "outside the seam by design: an Actions secret"
t_has "...and one with no held: is a migration debt" "$OUT" "no held: says why: a migration debt"
t_has "the tally counts held apart from unmanaged" "$OUT" "2 entries: 1 held, 1 unmanaged, 0 red"
cp "$T_TMP/before-held" "$REG"; good="$T_TMP/before-held"
field_is_red "an empty held" "held is empty" "held:"
cp "$good" "$REG"; entry held-ref some-ref "held: somewhere"
t_eq "held beside a ref: check is red" 1 "$(rc AX check)"
t_has "...and says why" "$(AX check 2>&1)" "goes with secret: none, not some-ref"; cp "$good" "$REG"
t_eq "add --held with --no-secret: exit 0" 0 "$(rc AX add held-add --kind app --what w --use-when u --reaches r --cannot c --grant g --no-secret --held 'a 0600 key the hook reads')"
t_has "...and held: is written" "$(cat "$REG")" "    held: a 0600 key the hook reads"
t_eq "add --held with --secret: exit 2" 2 "$(rc AX add held-x1 --kind app --what w --use-when u --reaches r --cannot c --grant g --secret hx-ref --held h)"
t_eq "a credential in --held: exit 2" 2 "$(rc AX add held-x2 --kind app --what w --use-when u --reaches r --cannot c --grant g --no-secret --held "$FAKECRED")"
cp "$good" "$REG"

t_section "red-proof: mutants of the two gates go green where the real code is red"
mkdir -p "$T_TMP/mut"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/secret" "$T_TMP/mut/"
sed 's/case "\$__hs" in 0) return 0 ;; 4) return 4 ;; esac/case "$__hs" in 0) return 0 ;; esac/' "$T_ROOT/bin/access.sh" > "$T_TMP/mut/access.sh"
t_eq "mutant 1 built: revoked no longer short-circuits" 0 "$(grep -c '4) return 4' "$T_TMP/mut/access.sh")"
t_eq "mutant 1 admits the revoked ref through the legacy list" 3 "$(ACCESS_LEGACY_REFS="$LEG" HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$T_TMP/mut/access.sh" has rot-ref)"
sed 's/^    if "\$@" < \/dev\/null > \/dev\/null 2>&1; then$/    if true; then/' "$T_ROOT/bin/secret" > "$T_TMP/mut/secret"
t_eq "mutant 2 built: the rotate probe is skipped" 1 "$(grep -c '^    if true; then$' "$T_TMP/mut/secret")"
cp "$T_ROOT/bin/access.sh" "$T_TMP/mut/access.sh"
entry mut-one mut-ref "$(alive mut-ref)" "$EXPECT"; put mut-ref good-m
t_eq "mutant 2 keeps a bad value the real code refuses" 0 "$(printf 'bad-m' | HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$T_TMP/mut/access.sh" rotate mut-one --value-stdin)"
t_done
