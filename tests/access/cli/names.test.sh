#!/usr/bin/env sh
# harbor#978: credential names are enforced at birth. `harbor access add` refuses a secret ref that breaks D-36 and a
# token or app with no, or a bad, vendor-side name, printing the compliant rendering; a renamed ref is one credential
# under both names until its renames row's remove_by; `harbor access move` and `secret copy` migrate the stored value.
# A temp HOME, a temp HARBOR_SCOPE_PRIVATE and the file-backed keychain stub: no case reaches the login Keychain.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
AX() { sh "$T_ROOT/bin/access.sh" "$@"; }
SC() { sh "$T_ROOT/bin/secret" "$@"; }
PV="$T_TMP/pv"; export HARBOR_SCOPE_PRIVATE="$PV" PORT_ROOT="$T_TMP/port"
sh "$T_ROOT/bin/scope.sh" install --private-only >/dev/null 2>&1
REG="$PV/access/register.md"
REN="$T_TMP/renames.tsv"; export ACCESS_RENAMES="$REN"
printf '# fixture renames\nid\told\tnew\tsurface\twave\tremove_by\treason\n' > "$REN"
VAL="fake-names-value-0123456789"
rc() { "$@" >/dev/null 2>&1; echo $?; }
ADD() { # <id> <kind> <ref|-> [extra args...]
  _i="$1"; _k="$2"; _r="$3"; shift 3
  case "$_r" in -) set -- --no-secret "$@" ;; *) set -- --secret "$_r" "$@" ;; esac
  AX add "$_i" --kind "$_k" --what w --use-when u --reaches r --cannot c --grant g "$@"
}
entry() { printf '\n## %s\n\n    kind: token\n    what: w\n    use-when: u\n    reaches: r\n    cannot: c\n    grant: g\n    secret: %s\n' "$1" "$2" >> "$REG"; }
plant() { printf 'v1:b64:%s' "$(printf '%s' "$2" | base64 | tr -d '\n')" > "$KC_STUB/items/secret.$1@${USER:-$(id -un)}"; }
readv() { SC run "$1" V -- sh -c 'printf %s "$V"' 2>/dev/null; }

t_section "add refuses a secret ref that breaks D-36, and the fix is the compliant rendering"
BEFORE="$(cksum < "$REG")"
t_eq "a ref with no system: exit 2" 2 "$(rc ADD tt token github-tools-push --vendor-name 'EXAMPLECO API GitHub' < /dev/null)"
OUT="$(ADD tt token github-tools-push --vendor-name 'EXAMPLECO API GitHub' 2>&1 < /dev/null)"
t_has "...naming the rule" "$OUT" "[name.secret]"
t_has "...and the compliant rendering as the fix" "$OUT" "fix: use harbor-github-tools-push"
t_eq "a ref with no rendering at hand: exit 2" 2 "$(rc ADD tt token worklog-token --vendor-name 'EXAMPLECO API GitHub' < /dev/null)"
t_has "...and the fix is the grammar with its slots" "$(ADD tt token worklog-token --vendor-name 'EXAMPLECO API GitHub' 2>&1 < /dev/null)" "--render secret system=harbor service=<vendor> identity=<account> purpose=<use>"
t_eq "the register is unchanged" "$BEFORE" "$(cksum < "$REG")"
printf 'rename-1\tsecret:old-github\tharbor-github-tools-reports\tsecret\tS1\t2099-12-31\tfixture\n' >> "$REN"
t_has "a ref a renames row moves: the fix names its new name" "$(ADD tt token old-github --vendor-name 'EXAMPLECO API GitHub' 2>&1 < /dev/null)" "fix: use harbor-github-tools-reports"
t_red name.secret

t_section "a token or app names itself as the vendor shows it"
t_eq "a token with no --vendor-name: exit 2" 2 "$(rc ADD tt token harbor-github-tools-push < /dev/null)"
t_has "...and the fix renders <ORG> API <Platform> from the ref's service" "$(ADD tt token harbor-github-tools-push 2>&1 < /dev/null)" 'rename it on the vendor to "EXAMPLECO API GitHub"'
t_eq "an app with no --vendor-name: exit 2" 2 "$(rc ADD tt app harbor-github-tools-oauth-client < /dev/null)"
t_eq "the vendor's default name (Some Connector): exit 2" 2 "$(rc ADD tt app harbor-github-tools-oauth-client --vendor-name 'Some Connector' < /dev/null)"
OUT="$(ADD tt app harbor-github-tools-oauth-client --vendor-name 'Some Connector' 2>&1 < /dev/null)"
t_has "...naming the rule" "$OUT" "[name.vendor-credential]"
t_has "...and the fix is the rendering" "$OUT" 'rename it on the vendor to "EXAMPLECO API GitHub"'
t_eq "a brand spelled wrong (Github): exit 2" 2 "$(rc ADD tt app harbor-github-tools-oauth-client --vendor-name 'EXAMPLECO API Github' < /dev/null)"
t_eq "an account needs none: exit 0" 0 "$(rc ADD a-mailbox account - < /dev/null)"
t_red name.vendor-credential

t_section "a compliant entry is written with both names"
printf '%s' "$VAL" | ADD github-push token harbor-github-tools-push --vendor-name 'EXAMPLECO API GitHub Northwind' --value-stdin > "$T_TMP/ok.out" 2>&1; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_has "the ref" "$(cat "$REG")" "    secret: harbor-github-tools-push"
t_has "the vendor-name" "$(cat "$REG")" "    vendor-name: EXAMPLECO API GitHub Northwind"
t_eq "check is green" 0 "$(rc AX check)"
t_hasnt "no value left the process" "$(cat "$T_TMP/ok.out" "$REG")" "$VAL"

t_section "check holds a hand-edited vendor-name to the same rule"
printf '    vendor-name: Some Connector\n' > "$T_TMP/vn"
entry hand-app harbor-gcloud-tools-oauth-client; cat "$T_TMP/vn" >> "$REG"
t_eq "check: exit 1" 1 "$(rc AX check)"
t_has "...naming the entry and the rule" "$(AX check 2>&1)" "hand-app: vendor-name [name.vendor-credential]"
sed -i.bak 's/^    vendor-name: Some Connector$/    vendor-name: EXAMPLECO API Google Cloud/' "$REG"; rm -f "$REG.bak"
t_eq "renamed on the vendor, check is green" 0 "$(rc AX check)"

t_section "a member laptop: the flat floor carries the lint, so the ref gate runs; hub-token is the floor's exemption"
MB="$T_TMP/Program Files/member"; mkdir -p "$MB"   # a space, as the macOS managed root has
cp "$T_ROOT/bin/access.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/secret" "$T_ROOT/bin/lint-name.sh" "$MB/"
cp "$T_ROOT"/standards/naming/*.tsv "$MB/"   # flat, as contracts/member-files.txt lands them
: > "$MB/harbor-member-mode"
MADD() { env -u ACCESS_LINT_NAME HARBOR_SCOPE_ROOT="$T_ROOT" sh "$MB/access.sh" add "$1" --kind token --what w --use-when u --reaches r --cannot c --grant g --secret "$2" < /dev/null; }
OUT="$(MADD hub-token hub-token 2>&1)"; _rc=$?
t_eq "the install's hub-token entry: exit 0" 0 "$_rc"
t_has "...the vendor-name gate says why it stands down" "$OUT" "member laptop: the vendor-name gate does not run here"
t_eq "a member's own pre-D-36 ref: exit 2" 2 "$(rc MADD gcloud-key worklog-token)"
t_has "...judged by the lint beside it, on its flat registry" "$(MADD gcloud-key worklog-token 2>&1)" "[name.secret]"
t_eq "a member's D-36 ref: exit 0" 0 "$(rc MADD gcloud-key harbor-gcloud-tools-member)"
t_eq "off a member laptop hub-token passes the ref gate (exempt) and is refused for its missing vendor-name" 2 "$(rc ADD hub-two token hub-token < /dev/null)"
t_has "...and it is the vendor-name that is missing" "$(ADD hub-two token hub-token 2>&1 < /dev/null)" "--vendor-name is missing"

t_section "a renamed ref is one credential under both names until remove_by"
entry old-entry old-github
plant old-github "$VAL"
t_eq "has the new name while the entry names the old: 0" 0 "$(rc AX has harbor-github-tools-reports)"
t_eq "renamed: the registered name first, then the other, then the date" "old-github	harbor-github-tools-reports	2099-12-31" "$(AX renamed harbor-github-tools-reports)"
t_eq "a reader asking for the new name gets the old item's value" "$VAL" "$(readv harbor-github-tools-reports)"
t_has "...and is told it read the other name" "$(SC run harbor-github-tools-reports V -- true 2>&1)" "reading old-github"
t_eq "an unrenamed unregistered ref is still refused: 1" 1 "$(rc AX has no-such-ref)"
t_eq "a ref no row names: renamed exits 1" 1 "$(rc AX renamed no-such-ref)"
printf 'rename-2\tsecret:gone-ref\tharbor-gcloud-tools-account\tsecret\tS1\t2000-01-01\tfixture, closed\n' >> "$REN"
entry gone-entry gone-ref
t_eq "past remove_by the twin is not admitted: 1" 1 "$(rc AX has harbor-gcloud-tools-account)"

t_section "move: the entry names the new ref, the value is copied inside bin/secret, the old item stays"
OUT="$(AX move old-github 2>&1)"; _rc=$?
t_eq "move exits 0" 0 "$_rc"
t_has "the entry names the new ref" "$(cat "$REG")" "    secret: harbor-github-tools-reports"
t_hasnt "...and not the old one" "$(cat "$REG")" "    secret: old-github"
t_has "the copy is proved by hash" "$OUT" "verified by sha256"
t_hasnt "no value in the output" "$OUT" "$VAL"
t_hasnt "no value in any store call's argv" "$(cat "$KC_STUB/argv.log")" "$VAL"
t_eq "the new name holds the value" "$VAL" "$(readv harbor-github-tools-reports)"
t_eq "a reader still asking for the old name gets it" "$VAL" "$(readv old-github)"
t_eq "the old item is kept" present "$([ -f "$KC_STUB/items/secret.old-github@${USER:-$(id -un)}" ] && echo present || echo gone)"
t_eq "stored: the old twin is not an orphan" "renamed	old-github" "$(AX stored 2>/dev/null | grep old-github)"
t_eq "a rerun is safe: exit 0" 0 "$(rc AX move old-github)"
t_eq "move of a ref no row names: exit 2" 2 "$(rc AX move no-such-ref)"
t_eq "move takes the old name, not the new: exit 2" 2 "$(rc AX move harbor-github-tools-reports)"
printf 'other-value-for-the-new' | SC put old-github >/dev/null 2>&1
t_eq "a write to the old name lands on the registered name" "other-value-for-the-new" "$(readv harbor-github-tools-reports)"

t_section "secret copy refuses to overwrite and never shows a value"
plant cp-src "$VAL"; entry cp-a cp-src; entry cp-b cp-dst; plant cp-dst "already-here"
t_eq "a target that holds a value: exit 1" 1 "$(rc SC copy cp-src cp-dst)"
t_eq "...and it is untouched" "already-here" "$(readv cp-dst)"
t_eq "an unregistered target: exit 1" 1 "$(rc SC copy cp-src nobody-names-this)"

t_section "a client-bearing rename lives in the private <access>/renames.tsv"
printf 'id\told\tnew\tsurface\twave\tremove_by\treason\nrename-p1\tsecret:priv-old\tharbor-gcloud-analytics-northwind\tsecret\tS1\t2099-12-31\tprivate fixture\n' > "$PV/access/renames.tsv"
entry priv-entry priv-old
t_eq "has the new name through the private row: 0" 0 "$(rc AX has harbor-gcloud-analytics-northwind)"

t_section "a piped value is trimmed, and one with whitespace inside is refused, saying only its length"
SEC="AbCdEf0123456789secret"
printf '  %s\n\n' "$SEC" | ADD trim-ok token harbor-github-tools-trim --vendor-name 'EXAMPLECO API GitHub' --value-stdin > "$T_TMP/trim.out" 2>&1; _rc=$?
t_eq "surrounding spaces and newlines: exit 0" 0 "$_rc"
t_eq "...the stored value is the credential alone" "$SEC" "$(readv harbor-github-tools-trim)"
t_has "...and the trim is said, by count" "$(cat "$T_TMP/trim.out")" "trimmed 4 whitespace character(s)"
BEFORE="$(cksum < "$REG")"
printf 'Abcd %s\n' "$SEC" | ADD paste-bad token harbor-github-tools-paste --vendor-name 'EXAMPLECO API GitHub' --value-stdin > "$T_TMP/paste.out" 2>&1; _rc=$?
t_eq "a prefix and a space in front (the 2026-11-13 paste): exit 2" 2 "$_rc"
t_has "...saying the length" "$(cat "$T_TMP/paste.out")" "holds whitespace inside it (27 characters after trimming)"
t_hasnt "...and never the value" "$(cat "$T_TMP/paste.out")" "$SEC"
t_eq "...and nothing was written" "$BEFORE" "$(cksum < "$REG")"
t_eq "...nor stored" 1 "$(rc SC run harbor-github-tools-paste V -- true)"
t_eq "whitespace only: exit 2" 2 "$(printf ' \n ' | rc ADD blank token harbor-github-tools-blank --vendor-name 'EXAMPLECO API GitHub' --value-stdin)"
KEYF="$(printf '{\n  "type": "service_account"\n}\n')"
printf '%s\n' "$KEYF" | ADD key-file token harbor-gcloud-tools-key --vendor-name 'EXAMPLECO API Google Cloud' --value-stdin --verbatim > /dev/null 2>&1; _rc=$?
t_eq "a key file with --verbatim: exit 0" 0 "$_rc"
t_has "...the entry says so" "$(cat "$REG")" "    value-shape: verbatim"
t_eq "...and it is stored byte for byte" "$(printf '%s\n' "$KEYF" | cksum)" "$(SC withfile harbor-gcloud-tools-key -- cat {} | cksum)"
t_eq "--verbatim with no ref: exit 2" 2 "$(rc ADD v-none token - --vendor-name 'EXAMPLECO API GitHub' --verbatim < /dev/null)"

t_section "red-proof: with the gates cut out, add takes what the real code refuses"
mkdir -p "$T_TMP/mut"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/secret" "$T_TMP/mut/"; export ACCESS_LINT_NAME="$T_ROOT/bin/lint-name.sh"
sed 's/^ *\[ "\$REFNAME" = none \] || name_gate secret .*$/    :/' "$T_ROOT/bin/access.sh" > "$T_TMP/mut/access.sh"
t_eq "mutant built: the secret gate is gone" 0 "$(grep -c 'name_gate secret "\$REFNAME"' "$T_TMP/mut/access.sh")"
t_eq "the mutant registers github-tools-push" 0 "$(HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$T_TMP/mut/access.sh" add mut-a --kind token --what w --use-when u --reaches r --cannot c --grant g --secret github-tools-push --vendor-name 'EXAMPLECO API GitHub' < /dev/null)"
sed 's/^    \[ -z "\$VNAME" \] || name_gate vendor-credential .*$/    :/' "$T_ROOT/bin/access.sh" > "$T_TMP/mut/access.sh"
t_eq "the mutant registers Some Connector" 0 "$(HARBOR_SCOPE_ROOT="$T_ROOT" rc sh "$T_TMP/mut/access.sh" add mut-b --kind app --what w --use-when u --reaches r --cannot c --grant g --secret harbor-gcloud-tools-mut --vendor-name 'Some Connector' < /dev/null)"
t_done
