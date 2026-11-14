#!/usr/bin/env sh
# hub.test.sh (harbor#1278, F26 F27 R4 R22) — `harbor hub`: init, status and the pin, pin-check, sign, check, and leave with a
# verified revocation told apart from every other failure.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
member_env; mkinst; hub_init
out() { hubsh "$@" 2>&1; }
rcof() { hubsh "$@" >/dev/null 2>&1; echo $?; }

t_section "1 - init says what is missing and who fixes it, then syncs"
_o="$(HARBOR_MEMBER_ROOT="$T_TMP/emptyroot" out init --dir "$CFGD")"
t_has "no hub-signers is named, with IT as the one who fixes it" "$_o" "hub-signers"
t_eq "...and init exits 1" 1 "$(HARBOR_MEMBER_ROOT="$T_TMP/emptyroot" rcof init --dir "$CFGD")"
t_eq "a standalone box: init exits 1 and says why" 1 "$(HARBOR_MEMBER_ROLE= rcof init --dir "$CFGD")"
t_eq "a complete box: init exits 0" 0 "$(rcof init --dir "$CFGD")"
t_eq "...and the policy is held" joined "$(sh "$HS" state 2>/dev/null)"
t_eq "the state dir is private (mode 700)" "drwx------" "$(ls -ld "$STATE" | cut -c1-10)"
t_eq "sync with no target is refused, never defaulted to the live dir (2)" 2 "$(rcof sync)"

t_section "2 - status reports the pin against the installed core, and does not act on it"
_s="$(out status --dir "$CFGD")"
t_has "status names the serial and mode" "$_s" "serial 1, mode shadow"
t_has "with no install stamp the pin line says the installed commit is unknown" "$_s" "installed commit unknown"
printf 'floor-install 1111111111111111111111111111111111111111 2026-11-07T10:00:00+02:00 11111111\n' > "$CFGD/.helm-install-stamp"
_s="$(out status --dir "$CFGD")"
t_has "an installed commit that is not the pinned one is a MISMATCH" "$_s" "pin: MISMATCH - core 111111111111 is installed, the policy pins 0123456789ab"
t_has "...and acting on it is IT's" "$_s" "stays with IT until the updater exists"
t_eq "status still exits 0 on a mismatch" 0 "$(rcof status --dir "$CFGD")"
printf 'floor-install 0123456789abcdef0123456789abcdef01234567 2026-11-07T10:00:00+02:00 01234567\n' > "$CFGD/.helm-install-stamp"
t_has "the pinned commit installed: ok" "$(out status --dir "$CFGD")" "pin: ok - core 0123456789ab, contract 1"
publish '.serial = 2 | .core.contract = 2'; sh "$HS" fetch >/dev/null 2>&1
t_has "a pinned contract the installed core does not have is a MISMATCH" "$(out status --dir "$CFGD")" "contract 1 is installed, the policy pins 2"
t_has "sync prints the same pin line" "$(out sync --dir "$CFGD")" "pin: MISMATCH"
t_eq "status on a standalone box says there is no hub" "no hub on this box" "$(HARBOR_MEMBER_ROLE= hubsh status --dir "$CFGD" 2>&1 | tail -n 1)"

t_section "3 - pin-check refuses a pin an extension rejects, reusing the pack grammar"
PD="$T_TMP/pin"; mkdir -p "$PD/packs/a" "$PD/packs/b"
printf '{"id":"a","harbor_version":">=1"}\n' > "$PD/packs/a/extension.json"; printf '{"id":"b","harbor_version":"<2"}\n' > "$PD/packs/b/extension.json"
t_eq "contract 1 satisfies both" 0 "$(rcof pin-check 1 "$PD")"
t_eq "contract 2 is refused" 1 "$(rcof pin-check 2 "$PD")"
t_has "...naming the extension and its constraint" "$(out pin-check 2 "$PD")" "extension b needs harbor <2"
t_eq "contract 0 is refused by >=1" 1 "$(rcof pin-check 0 "$PD")"
printf '{"id":"b","harbor_version":"~1"}\n' > "$PD/packs/b/extension.json"
t_eq "a constraint the pack grammar cannot read is refused, not passed" 1 "$(rcof pin-check 1 "$PD")"
t_eq "a contract that is not a number is a usage error" 2 "$(rcof pin-check one "$PD")"

t_section "4 - sign validates, then makes a real ssh-keygen signature"
SD="$T_TMP/signdir"; rm -rf "$SD"; mkdir -p "$SD"; G "$SD" init -q; jq '.packs = [] | .hooks = []' "$FX/policy.json" > "$SD/policy.json"
t_eq "sign exits 0" 0 "$(rcof sign "$SD/policy.json" --key "$KEY")"
t_eq "...and the signature verifies with ssh-keygen against hub-signers" 0 "$(ssh-keygen -Y verify -f "$MR/hub-signers" -I hub -n harbor-hub -s "$SD/policy.json.sig" < "$SD/policy.json" >/dev/null 2>&1; echo $?)"
t_eq "check on the signed directory is green" 0 "$(rcof check "$SD" --signers "$MR/hub-signers")"
G "$SD" add -A; G "$SD" commit -qm one
jq '.silent_days = 9' "$SD/policy.json" > "$SD/p.new"; mv "$SD/p.new" "$SD/policy.json"
t_eq "an edit after signing makes check red" 1 "$(rcof check "$SD" --signers "$MR/hub-signers")"
t_has "...saying the signature does not verify" "$(out check "$SD" --signers "$MR/hub-signers")" "does not verify"
t_eq "sign refuses the same serial with other content" 1 "$(rcof sign "$SD/policy.json" --key "$KEY")"
t_has "...and says why" "$(out sign "$SD/policy.json" --key "$KEY")" "is not above the committed serial 1"
jq '.serial = 2 | .extra = 1' "$SD/policy.json" > "$SD/p.new"; mv "$SD/p.new" "$SD/policy.json"
t_eq "sign refuses a policy that breaks the format" 1 "$(rcof sign "$SD/policy.json" --key "$KEY")"
t_eq "...and leaves no signature behind" no "$([ -e "$SD/policy.json.sig" ] && echo yes || echo no)"
jq 'del(.extra) | .tiers = {"admission.key-material-egress":"low"}' "$SD/policy.json" > "$SD/p.new"; mv "$SD/p.new" "$SD/policy.json"
t_has "a tiers entry on a fixed row is refused before signing" "$(out sign "$SD/policy.json" --key "$KEY")" "a fixed row cannot be re-tiered"
jq 'del(.tiers)' "$SD/policy.json" > "$SD/p.new"; mv "$SD/p.new" "$SD/policy.json"
t_eq "a higher serial signs" 0 "$(rcof sign "$SD/policy.json" --key "$KEY")"
t_eq "a signature by a key hub-signers does not hold fails check" 1 "$(sign_with "$OTHERKEY" "$SD/policy.json"; rcof check "$SD" --signers "$MR/hub-signers")"

t_section "5 - check covers packs, hooks and the pin of a whole hub repo"
hub_init; mkhubpack fixture-pack
publish ".packs = [{id:\"fixture-pack\",commit:\"$PACKC\"}] | .hooks = [{pack:\"fixture-pack\",path:\"hooks/guard-hub.sh\",sha256:\"$HOOKSHA\"}]"
t_eq "a consistent hub repo is green" 0 "$(rcof check "$HUBSRC" --signers "$MR/hub-signers")"
publish ".hooks = [{pack:\"fixture-pack\",path:\"hooks/guard-hub.sh\",sha256:\"$(printf x | hub_sha256)\"}]"
t_has "a hook hash that the committed file does not match is a finding" "$(out check "$HUBSRC" --signers "$MR/hub-signers")" "does not match sha256 in the policy"
publish ".hooks = [] | .packs = [{id:\"fixture-pack\",commit:\"0000000000000000000000000000000000000000\"}]"
t_has "a pack pinned to a commit that is not there is a finding" "$(out check "$HUBSRC" --signers "$MR/hub-signers")" "is not in this repository"
mkhubpack fixture-pack; jq '.harbor_version = "<2"' "$HUBSRC/packs/fixture-pack/extension.json" > "$T_TMP/e.json"; cp "$T_TMP/e.json" "$HUBSRC/packs/fixture-pack/extension.json"; G "$HUBSRC" add -A; G "$HUBSRC" commit -qm lt2
publish ".serial += 1 | .core.contract = 2 | .packs = [{id:\"fixture-pack\",commit:\"$(G "$HUBSRC" rev-parse HEAD)\"}]"
t_has "raising the pin past an extension's harbor_version is a finding" "$(out check "$HUBSRC" --signers "$MR/hub-signers")" "contract 2 is refused: extension fixture-pack needs harbor <2"

t_section "6 - leave: only a verified revocation removes anything"
hub_init; mkhubpack fixture-pack; publish ".serial = 10 | .packs = [{id:\"fixture-pack\",commit:\"$PACKC\"}] | .hooks = [{pack:\"fixture-pack\",path:\"hooks/guard-hub.sh\",sha256:\"$HOOKSHA\"}]"
rm -rf "$STATE" "$CFGD/.harbor-packs" "$CFGD/skills"
hubsh sync --dir "$CFGD" >/dev/null 2>&1
t_eq "the hub pack is installed" yes "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no)"
t_eq "joined: leave --apply is refused (1)" 1 "$(rcof leave --apply --dir "$CFGD")"
t_has "...and says only a verified revocation removes anything" "$(out leave --apply --dir "$CFGD")" "only a verified policy"
printf '#!/bin/sh\necho "fatal: HTTP 403" >&2\nexit 128\n' > "$T_BIN/git"; chmod +x "$T_BIN/git"
hubsh sync --dir "$CFGD" >/dev/null 2>&1; t_eq "a 403 on sync exits 3" 3 "$(rcof sync --dir "$CFGD")"
rm -f "$T_BIN/git"
t_eq "...and the pack and policy are still there" "yes yes" "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no) $([ -f "$STATE/policy.json" ] && echo yes || echo no)"
t_eq "...and leave is still refused" 1 "$(rcof leave --apply --dir "$CFGD")"
publish '.serial = 11 | .revoked = ["alice"]'; sh "$HS" fetch >/dev/null 2>&1
_o="$(out leave --dir "$CFGD")"
t_has "revoked: the dry run names the pack it would remove" "$_o" "would remove hub pack fixture-pack"
t_eq "...and removes nothing" "yes yes" "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no) $([ -f "$STATE/policy.json" ] && echo yes || echo no)"
_o="$(out leave --apply --dir "$CFGD")"
t_eq "--apply drops the hub pack" no "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no)"
t_eq "...the skill with it" no "$([ -e "$CFGD/skills/hubdemo" ] && echo yes || echo no)"
t_eq "...and the policy, the clone and the hooks" no "$([ -e "$STATE" ] && echo yes || echo no)"
t_has "the root half is named as IT's step" "$_o" "The root half is IT's step"
t_has "...with what to remove" "$_o" "hub-signers"
t_eq "a second leave has nothing to do and exits 0" 0 "$(rcof leave --apply --dir "$CFGD")"

t_section "7 - sync with a revocation leaves by itself"
rm -rf "$STATE" "$CFGD/.harbor-packs" "$CFGD/skills"; hub_init; mkhubpack fixture-pack
publish ".serial = 20 | .packs = [{id:\"fixture-pack\",commit:\"$PACKC\"}]"; hubsh sync --dir "$CFGD" >/dev/null 2>&1
publish '.serial = 21 | .revoked = ["alice"]'
hubsh sync --dir "$CFGD" >/dev/null 2>&1
t_eq "one sync after the revocation: pack gone" no "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no)"
t_eq "...policy gone" none "$(sh "$HS" state 2>/dev/null)"
t_done
