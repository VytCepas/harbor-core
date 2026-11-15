#!/usr/bin/env sh
# bin/secret refuses a ref the access register does not name (harbor#1205).
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
SC="$T_ROOT/bin/secret"
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
VAL="fake-gate-value-0123456789"
W="$T_TMP/work"; mkdir -p "$W"; printf '%s' "$VAL" > "$W/file.txt"
rc() { "$@" >/dev/null 2>&1; echo $?; }
reads() { grep -c 'find-generic-password' "$KC_STUB/argv.log" | sed 's/^[1-9][0-9]*$/some/'; }  # 0 or some
adds() { grep -c 'add-generic-password' "$KC_STUB/argv.log" | sed 's/^[1-9][0-9]*$/some/'; }
entry() { printf '\n## %s\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: %s\n' "$1" "$2" >> "$REG"; }

# Every verb that names a ref, against a register that names none.
verbs() { # <label>
  t_exit "$1: put is refused" 1 sh -c "printf %s x | '$SC' put never-registered"
  t_exit "$1: putfile is refused" 1 "$SC" putfile never-registered "$W/file.txt"
  t_exit "$1: run is refused" 1 "$SC" run never-registered V -- true
  t_exit "$1: withfile is refused" 1 "$SC" withfile never-registered -- true
  t_exit "$1: adopt is refused" 1 "$SC" adopt "$W/file.txt" never-registered
  t_exit "$1: import onto it is refused" 1 "$SC" import some-old-service never-registered
  t_has "$1: and the message says why" "$("$SC" run never-registered V -- true 2>&1)" "'never-registered' is not in the access register"
  t_has "$1: and names the fix" "$("$SC" run never-registered V -- true 2>&1)" "harbor access add"
  t_eq "$1: stdout stayed empty" "" "$("$SC" run never-registered V -- true 2>/dev/null)"
}

t_section "an empty register (header only): every ref is refused, and the store is never touched"
verbs "empty register"
t_eq "no item was written" 0 "$(adds)"
t_eq "no item was read" 0 "$(reads)"
t_eq "the plaintext file survived adopt" present "$([ -f "$W/file.txt" ] && echo present || echo gone)"

t_section "no private layer at all: the register is empty and every ref is refused"
HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer"
verbs "no layer"
t_eq "no item was written" 0 "$(adds)"
t_eq "no item was read" 0 "$(reads)"
HARBOR_SCOPE_PRIVATE="$PV"

t_section "a registered ref works, every verb"
entry gate-token gate-ref
printf '%s' "$VAL" | "$SC" put gate-ref >/dev/null 2>&1; _rc=$?
t_eq "put of a registered ref" 0 "$_rc"
t_eq "run hands the value to the child" "$VAL" "$("$SC" run gate-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"
t_eq "withfile materialises it" "$VAL" "$("$SC" withfile gate-ref -- cat '{}' 2>/dev/null)"
entry gate-file gate-file-ref
t_eq "putfile of a registered ref" 0 "$(rc "$SC" putfile gate-file-ref "$W/file.txt")"
entry gate-adopt gate-adopt-ref
t_eq "adopt of a registered ref" 0 "$(rc "$SC" adopt "$W/file.txt" gate-adopt-ref)"
printf '%s' "$VAL" > "$W/file.txt"
entry gate-import gate-import-ref
printf 'old' > "$KC_STUB/items/some-old-service@${USER:-$(id -un)}"
t_eq "import onto a registered ref" 0 "$(rc "$SC" import some-old-service gate-import-ref)"
t_eq "a ref the register names is not a ref it does not: a neighbour is still refused" 1 "$(rc "$SC" run gate-ref-other V -- true)"
t_eq "a prefix of a registered ref is refused" 1 "$(rc "$SC" run gate V -- true)"
t_eq "a ref with none as its value is not registered" 1 "$(rc "$SC" run none V -- true)"

t_section "the register decides, not the store: an item that exists under an unregistered name is unreachable"
printf 'v1:b64:%s' "$(printf '%s' "$VAL" | base64 | tr -d '\n')" > "$KC_STUB/items/secret.planted@${USER:-$(id -un)}"
t_eq "the item is there" present "$([ -f "$KC_STUB/items/secret.planted@${USER:-$(id -un)}" ] && echo present || echo gone)"
t_eq "...and run refuses it" 1 "$(rc "$SC" run planted V -- true)"
entry planted-entry planted
t_eq "once registered it opens" "$VAL" "$("$SC" run planted V -- sh -c 'printf %s "$V"' 2>/dev/null)"

t_section "a legacy ref (contracts/secret-legacy-refs.txt) is served with no entry"
LEGREF="$(awk '/^[[:space:]]*(#|$)/ { next } { print $1; exit }' "$T_ROOT/contracts/secret-legacy-refs.txt")"
t_eq "the list names the live-verify probe's absent name, and it comes first" zz-harbor-live-probe-absent "$LEGREF"
printf '%s' "$VAL" | "$SC" put "$LEGREF" >/dev/null 2>&1; _rc=$?
t_eq "put of a legacy ref, no entry" 0 "$_rc"
t_eq "run of a legacy ref" "$VAL" "$("$SC" run "$LEGREF" V -- sh -c 'printf %s "$V"' 2>/dev/null)"

t_section "the credential refs that predated the register left the list: with no entry each is refused (harbor#1205)"
for _r in stape-api meta-system-user-read meta-system-user-write hostinger-api rtbhouse-api gcloud-store; do
  t_eq "$_r is not grandfathered" 0 "$(awk -v r="$_r" '$1 == r' "$T_ROOT/contracts/secret-legacy-refs.txt" | wc -l | tr -d ' ')"
  # An item is stored under the name, so only the gate can refuse it.
  printf 'v1:b64:%s' "$(printf '%s' "$VAL" | base64 | tr -d '\n')" > "$KC_STUB/items/secret.$_r@${USER:-$(id -un)}"
  t_has "...so with no entry the gate refuses it, though the store holds it" "$("$SC" run "$_r" V -- sh -c 'printf %s "$V"' 2>&1)" "'$_r' is not in the access register"
done

t_section "rm and list are not gated"
sed -i.bak '/^## planted-entry$/,$d' "$REG"; rm -f "$REG.bak"
t_eq "the ref is unregistered again" 1 "$(rc "$SC" run planted V -- true)"
t_eq "list still lists names" 0 "$(rc "$SC" list)"
t_eq "rm of an unregistered ref still removes it" 0 "$(rc "$SC" rm planted)"

t_section "it fails closed: no reader beside the seam is a refusal"
D="$T_TMP/nogate"; mkdir -p "$D"; cp "$SC" "$T_ROOT/bin/library-log.sh" "$D/"
t_exit "a copy with no access.sh refuses even a registered ref" 1 "$D/secret" run gate-ref V -- true
t_has "...and says why" "$("$D/secret" run gate-ref V -- true 2>&1)" "is not in the access register"
printf '#!/bin/sh\nexit 2\n' > "$D/access.sh"
t_exit "a reader that errors (exit 2) is a refusal" 1 "$D/secret" run gate-ref V -- true
printf '#!/bin/sh\nexit 0\n' > "$D/access.sh"
t_eq "control: a reader that says yes admits it" "$VAL" "$("$D/secret" run gate-ref V -- sh -c 'printf %s "$V"' 2>/dev/null)"

t_section "red-proof: without the gate an unregistered ref is stored"
mkdir -p "$T_TMP/mut"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/access.sh" "$T_ROOT/bin/scope-roots.sh" "$T_TMP/mut/" 2>/dev/null
sed 's/^  registered "\$1" \&\& return 0$/  return 0/' "$SC" > "$T_TMP/mut/secret"
t_eq "control: the real seam has the gate line" 1 "$(grep -c '^  registered "\$1" && return 0$' "$SC")"
t_eq "the mutant was built: the gate line is gone" 0 "$(grep -c 'registered "\$1" && return 0' "$T_TMP/mut/secret")"
t_eq "the mutant stores a ref nothing registered" 0 "$(printf x | sh "$T_TMP/mut/secret" put zz-unregistered >/dev/null 2>&1; echo $?)"
t_eq "...where the real seam refused it" 1 "$(printf x | sh "$SC" put zz-unregistered >/dev/null 2>&1; echo $?)"
t_done
