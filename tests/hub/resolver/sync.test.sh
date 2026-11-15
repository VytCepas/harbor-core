#!/usr/bin/env sh
# sync.test.sh (harbor#1278, F3 F20 F27 R22) — bin/hub-sync.sh: a real ssh-keygen signature passes and a one-byte change fails; a bad
# or missing hub never lowers a limit; only a verified policy naming this login means revoked.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
member_env; hub_init
hs() { sh "$HS" "$@" 2>/dev/null; }
hsrc() { sh "$HS" "$@" >/dev/null 2>&1; echo $?; }

t_section "1 - a real signature passes and a one-byte change fails"
P="$T_TMP/sig/policy.json"; mkdir -p "${P%/*}"; cp "$HUBSRC/policy.json" "$P"; sign_with "$KEY" "$P"
vf() { ssh-keygen -Y verify -f "$MR/hub-signers" -I hub -n harbor-hub -s "$P.sig" < "$1" > /dev/null 2>&1; echo $?; }
t_eq "ssh-keygen -Y sign output verifies against hub-signers" 0 "$(vf "$P")"
sed 's/fixture-hub/fixture-hux/' "$P" > "$P.bad"
t_eq "one changed byte fails" 255 "$(vf "$P.bad")"
sign_with "$OTHERKEY" "$P"
t_eq "a signature from another key fails" 255 "$(vf "$P")"

t_section "2 - fetch accepts a signed, valid, higher policy"
t_eq "before any fetch: nothing held" "" "$(hs path)"
t_eq "...and the state is none" none "$(hs state)"
t_eq "fetch exits 0" 0 "$(hsrc fetch)"
t_eq "path names the held policy" "$STATE/policy.json" "$(hs path)"
t_eq "...with its signature beside it, which hub-approval and member-update re-verify" yes "$([ -s "$(hs path).sig" ] && echo yes || echo no)"
t_eq "state is joined" joined "$(hs state)"
t_eq "a second fetch of the same policy is unchanged, exit 0" 0 "$(hsrc fetch)"
publish '.serial = 2'
t_eq "a higher serial is accepted" 0 "$(hsrc fetch)"
t_eq "...and is the one held" 2 "$(jq -r .serial "$(hs path)")"

t_section "3 - a policy that cannot be proved is refused and the last good one stays"
cp "$HUBSRC/policy.json" "$T_TMP/pol2.json"; cp "$HUBSRC/policy.json.sig" "$T_TMP/pol2.sig"
publish '.serial = 3'
sed 's/"shadow"/"enforce"/' "$HUBSRC/policy.json" > "$T_TMP/edited.json"; cp "$T_TMP/edited.json" "$HUBSRC/policy.json"; G "$HUBSRC" commit -qam "edit without signing"
t_eq "an edit after signing is refused (exit 1)" 1 "$(hsrc fetch)"
t_eq "...the held serial is still 2" 2 "$(jq -r .serial "$(hs path)")"
publish '.serial = 4' "$OTHERKEY"
t_eq "a policy signed by another key is refused" 1 "$(hsrc fetch)"
t_eq "...the held serial is still 2" 2 "$(jq -r .serial "$(hs path)")"
publish '.serial = 5 | .extra = 1'
t_eq "a signed policy that breaks the format is refused" 1 "$(hsrc fetch)"
publish 'del(.extra) | .serial = 6'
t_eq "a good signed policy after the bad ones is accepted" 0 "$(hsrc fetch)"
t_eq "...serial 6" 6 "$(jq -r .serial "$(hs path)")"

t_section "4 - a lower or equal serial is refused: an old signed file cannot be replayed"
cp "$T_TMP/pol2.json" "$HUBSRC/policy.json"; cp "$T_TMP/pol2.sig" "$HUBSRC/policy.json.sig"; G "$HUBSRC" add -A; G "$HUBSRC" commit -qm replay
t_eq "an older validly signed policy is refused" 1 "$(hsrc fetch)"
t_eq "...serial 6 is still held" 6 "$(jq -r .serial "$(hs path)")"
publish '.serial = 6 | .silent_days = 9'
t_eq "the same serial with other content is refused" 1 "$(hsrc fetch)"

t_section "5 - tampering with the files on the laptop never lowers the policy"
publish '.serial = 7 | .silent_days = 5'
hsrc fetch >/dev/null
cp "$STATE/policy.json" "$T_TMP/live7.json"
printf ' ' >> "$STATE/policy.json"
t_eq "a one-byte change to the live copy: path falls to the verified last-good copy" "$STATE/last-good/policy.json" "$(hs path)"
t_eq "...serial 7" 7 "$(jq -r .serial "$(hs path)")"
t_eq "...and its signature is beside the fallback too" yes "$([ -s "$(hs path).sig" ] && echo yes || echo no)"
t_eq "...state is still joined" joined "$(hs state)"
cp "$T_TMP/pol2.json" "$STATE/policy.json"; cp "$T_TMP/pol2.sig" "$STATE/policy.json.sig"
t_eq "an older signed pair replayed into the live place does not roll the policy back" 7 "$(jq -r .serial "$(hs path)")"
printf ' ' >> "$STATE/last-good/policy.json"
printf ' ' >> "$STATE/policy.json"
t_eq "both copies broken: path prints nothing" "" "$(hs path)"
t_eq "...check says tampered (1), not absent (2)" 1 "$(hsrc check)"
t_eq "the next fetch repairs both copies" 0 "$(hsrc fetch)"
t_eq "...serial 7 again" 7 "$(jq -r .serial "$(hs path)")"
t_eq "check is 0" 0 "$(hsrc check)"

t_section "6 - unreachable is not revoked"
mkdir -p "$T_TMP/failbin"
for code in 401 403 dead; do
  printf '#!/bin/sh\necho "fatal: HTTP %s" >&2\nexit 128\n' "$code" > "$T_BIN/git"; chmod +x "$T_BIN/git"
  t_eq "a failing fetch ($code) exits 3" 3 "$(hsrc fetch)"
  t_eq "...the policy and the state are untouched ($code)" "7 joined" "$(jq -r .serial "$(hs path)") $(hs state)"
done
rm -f "$T_BIN/git"
HARBOR_HUB_REMOTE="$T_TMP/no-such-hub" sh "$HS" fetch >/dev/null 2>&1; t_eq "a hub that does not exist is unreachable (3)" 3 "$?"
printf 'revoked\n' > "$STATE/state"; : > "$STATE/revoked"
t_eq "a file named revoked on the laptop means nothing" joined "$(hs state)"

t_section "7 - only a verified policy naming this login is a revocation"
publish '.serial = 8 | .revoked = ["alice"]'
t_eq "the revoking policy is accepted" 0 "$(hsrc fetch)"
t_eq "state is revoked" revoked "$(hs state)"
publish '.serial = 9 | .revoked = ["bob"]'
hsrc fetch >/dev/null
t_eq "a policy naming someone else leaves alice joined" joined "$(hs state)"
publish '.serial = 10 | .revoked = ["alice"]' "$OTHERKEY"
t_eq "a revocation signed by another key is refused" 1 "$(hsrc fetch)"
t_eq "...alice stays joined" joined "$(hs state)"

t_section "8 - what a standalone or unconfigured box sees"
t_eq "standalone: path prints nothing" "" "$(HARBOR_MEMBER_ROLE= sh "$HS" path 2>/dev/null)"
t_eq "standalone: state is none" none "$(HARBOR_MEMBER_ROLE= sh "$HS" state 2>/dev/null)"
t_eq "standalone: fetch exits 0 and touches nothing" 0 "$(HARBOR_MEMBER_ROLE= sh "$HS" fetch >/dev/null 2>&1; echo $?)"
mv "$MR/hub-signers" "$MR/hub-signers.off"
t_eq "no hub-signers: path prints nothing" "" "$(hs path)"
t_eq "no hub-signers: fetch is refused (1), never unreachable" 1 "$(hsrc fetch)"
mv "$MR/hub-signers.off" "$MR/hub-signers"

t_section "9 - the token is read through secret and goes in the child's environment, never argv"
SECRET="$T_TMP/secret-stub"
printf '#!/bin/sh\n[ "$1" = run ] && [ "$2" = hub-token ] || exit 1\nv="$3"; shift 4; export "$v=tok-ABC123"; exec "$@"\n' > "$SECRET"; chmod +x "$SECRET"
cat > "$T_BIN/git" <<'EOF'
#!/bin/sh
{ printf 'ARGS:%s\n' "$*"; env | grep '^GIT_CONFIG_VALUE_[0-9]*=Authorization' ; } > "$FAKEGIT_OUT"
exit 128
EOF
chmod +x "$T_BIN/git"
t_eq "no secret store: token says so (1)" 1 "$(hsrc token)"
FAKEGIT_OUT="$T_TMP/fakegit0.out" sh "$HS" fetch >/dev/null 2>&1
t_eq "...and the fetch carries no Authorization header" 0 "$(grep -c 'Authorization' "$T_TMP/fakegit0.out")"
export HARBOR_ACCESS_SECRET_BIN="$SECRET"
t_eq "with the store: token says so (0)" 0 "$(hsrc token)"
t_eq "...and prints nothing" "" "$(sh "$HS" token 2>/dev/null)"
FAKEGIT_OUT="$T_TMP/fakegit.out" sh "$HS" fetch >/dev/null 2>&1
t_has "the header carries the token (base64) in the environment" "$(cat "$T_TMP/fakegit.out")" "=Authorization: Basic $(printf 'x-access-token:tok-ABC123' | base64)"
t_eq "...and the token is nowhere in argv" 0 "$(grep '^ARGS:' "$T_TMP/fakegit.out" | grep -c 'tok-ABC123\|Authorization')"
rm -f "$T_BIN/git"; unset HARBOR_ACCESS_SECRET_BIN

t_section "10 - a delivered hook runs only if it matches the signed hash"
mkdir -p "$STATE/hooks/fixture-pack/hooks"; printf '#!/bin/sh\nexit 0\n' > "$STATE/hooks/fixture-pack/hooks/h.sh"
H1="$(shasum -a 256 "$STATE/hooks/fixture-pack/hooks/h.sh" | cut -d' ' -f1)"
publish ".serial = 11 | .revoked = [] | .hooks = [{pack:\"fixture-pack\",path:\"hooks/h.sh\",sha256:\"$H1\"}]"
hsrc fetch >/dev/null
t_eq "a hook whose bytes match prints its path" "$STATE/hooks/fixture-pack/hooks/h.sh" "$(hs hook fixture-pack hooks/h.sh)"
printf '#!/bin/sh\ncurl evil\n' > "$STATE/hooks/fixture-pack/hooks/h.sh"
t_eq "a changed hook prints nothing and exits 1" "|1" "$(hs hook fixture-pack hooks/h.sh)|$(hsrc hook fixture-pack hooks/h.sh)"
t_eq "a hook the policy does not list prints nothing" 1 "$(hsrc hook fixture-pack hooks/other.sh)"
t_eq "a path out of the pack is refused" 1 "$(hsrc hook fixture-pack ../../x)"
t_done
