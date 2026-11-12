# tests/hub/fixtures/resolver.sh (harbor#1278) — a member box, an admin key and a hub repo on disk, shared by the resolver suites.
# Sourced after core.sh's t_init. Every key, repo and state dir lives under the suite's temp dir; the real ssh agent and ~/.ssh are never named.
MR="$T_TMP/managed"; HUBSRC="$T_TMP/hubsrc"; KEY="$T_TMP/admin"; OTHERKEY="$T_TMP/other"; FX="$T_ROOT/tests/hub/fixtures"
STATE="$T_TMP/state/harbor/hub"
HS="$T_ROOT/bin/hub-sync.sh"; HUB="$T_ROOT/bin/hub.sh"
mkdir -p "$MR"
ssh-keygen -q -t ed25519 -N '' -C fixture-admin -f "$KEY"
ssh-keygen -q -t ed25519 -N '' -C someone-else -f "$OTHERKEY"
printf 'hub %s\n' "$(cat "$KEY.pub")" > "$MR/hub-signers"

member_env() {
  export HARBOR_MEMBER_ROLE=member HARBOR_HUB_REPO=fixture-org/fixture-hub HARBOR_MEMBER_LOGIN=alice
  export HARBOR_MEMBER_ROOT="$MR" HARBOR_HUB_REMOTE="$HUBSRC" XDG_STATE_HOME="$T_TMP/state"
}
G() { _g="$1"; shift; git -C "$_g" -c user.name=t -c user.email=t@example.test "$@"; }

# sign_with <key> <file>: a real ssh-keygen -Y sign, the signature beside the file.
sign_with() { rm -f "$2.sig"; ssh-keygen -q -Y sign -f "$1" -n harbor-hub "$2" > /dev/null 2>&1; }

# hub_init: the hub repo with the fixture policy (serial 1, no packs) signed by the admin key.
hub_init() {
  rm -rf "$HUBSRC"; mkdir -p "$HUBSRC"; G "$HUBSRC" init -q
  jq '.packs = [] | .hooks = []' "$FX/policy.json" > "$HUBSRC/policy.json"
  sign_with "$KEY" "$HUBSRC/policy.json"
  G "$HUBSRC" add -A; G "$HUBSRC" commit -q -m policy
}
# publish <jq edit> [key]: edit the hub's policy, sign it, commit it.
publish() {
  jq "$1" "$HUBSRC/policy.json" > "$HUBSRC/policy.new" && mv "$HUBSRC/policy.new" "$HUBSRC/policy.json"
  sign_with "${2:-$KEY}" "$HUBSRC/policy.json"
  G "$HUBSRC" add -A; G "$HUBSRC" commit -q -m "policy $(jq -r .serial "$HUBSRC/policy.json")"
}
serial_held() { jq -r .serial "$("$@" 2>/dev/null)" 2>/dev/null || echo none; }

. "$T_ROOT/bin/library-hub.sh"
# mkinst: an installed-layout bin/ of symlinks to the real files, with stubs for the scripts other lanes own, so a script finds its
# siblings by its own directory the way it will on a member laptop. The stubs are real files and win over any real sibling.
INST="$T_TMP/inst"; CFGD="$T_TMP/cfgd"
mkinst() {
  mkdir -p "$INST/bin" "$CFGD"
  for _f in "$T_ROOT"/bin/*; do ln -sf "$_f" "$INST/bin/${_f##*/}"; done
  for _d in contracts standards docs skills; do [ -e "$INST/$_d" ] || ln -s "$T_ROOT/$_d" "$INST/$_d"; done
  rm -f "$INST/bin/member-integrity.sh" "$INST/bin/hub-events.sh"
  printf '#!/bin/sh\ncase "$1" in hash) echo 0123456789abcdef ;; check) exit "$(cat "%s/integrity.rc" 2>/dev/null || echo 0)" ;; esac\n' "$T_TMP" > "$INST/bin/member-integrity.sh"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/events.log"\n' "$T_TMP" > "$INST/bin/hub-events.sh"
  # hub-approval.sh note answers with hook JSON only when a test left a note for it
  rm -f "$INST/bin/hub-approval.sh"
  printf '#!/bin/sh\n[ "$1" = note ] && [ -s "%s/approval.note" ] && jq -n --arg m "$(cat "%s/approval.note")" '"'"'{systemMessage: $m}'"'"'\nexit 0\n' "$T_TMP" "$T_TMP" > "$INST/bin/hub-approval.sh"
  : > "$T_TMP/events.log"
  HS="$INST/bin/hub-sync.sh"; HUB="$INST/bin/hub.sh"
}
hubsh() { env -u CLAUDE_CONFIG_DIR sh "$HUB" "$@"; }

# mkhubpack <id> [harbor_version]: commit a hub pack (a skill and a hook) with its extension.json; sets PACKC, HOOKSHA.
mkhubpack() {
  _id="$1"; _p="$HUBSRC/packs/$_id"; rm -rf "$_p"; mkdir -p "$_p/harbor-pack/skills/hubdemo" "$_p/harbor-pack/hooks"
  printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "a hub fixture"\n' "$_id" > "$_p/harbor-pack/pack.toml"
  printf -- '---\nname: hubdemo\n---\nA hub skill.\n' > "$_p/harbor-pack/skills/hubdemo/SKILL.md"
  printf '#!/bin/sh\nexit 0\n' > "$_p/harbor-pack/hooks/guard-hub.sh"
  _s1="$(hub_sha256 < "$_p/harbor-pack/skills/hubdemo/SKILL.md")"; HOOKSHA="$(hub_sha256 < "$_p/harbor-pack/hooks/guard-hub.sh")"
  jq -n --arg id "$_id" --arg hv "${2:->=1}" --arg s1 "$_s1" --arg s2 "$HOOKSHA" \
    '{schema:1,id:$id,version:"1.0.0",harbor_version:$hv,provides:["skill","hook"],files:[{path:"skills/hubdemo/SKILL.md",sha256:$s1},{path:"hooks/guard-hub.sh",sha256:$s2}]}' > "$_p/extension.json"
  G "$HUBSRC" add -A; G "$HUBSRC" commit -q -m "pack $_id" >/dev/null 2>&1 || :; PACKC="$(G "$HUBSRC" rev-parse HEAD)"
}
