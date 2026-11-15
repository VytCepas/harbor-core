# make-hub.sh (harbor#1278) — sourced by the hub suites after t_init: a clean, signed hub made from templates/hub.
#   make_hub <dir>     copy the scaffold, fill the starter values, sign policy.json with a throwaway key, git init
#   resign <dir>    sign policy.json again after an edit
# The key lives in $T_TMP/hubkey and signs as namespace harbor-hub, as the hub README says.
HUBKEY="$T_TMP/hubkey"
[ -f "$HUBKEY" ] || ssh-keygen -q -t ed25519 -N '' -C hub -f "$HUBKEY"
resign() { rm -f "$1/policy.json.sig"; ssh-keygen -q -Y sign -f "$HUBKEY" -n harbor-hub "$1/policy.json"; }
make_hub() {
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$T_ROOT/templates/hub" && tar -cf - . ) | ( cd "$1" && tar -xf - )
  printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$HUBKEY.pub")" > "$1/hub-signers"
  jq '.hub = "fixture-hub" | .core.commit = "0123456789abcdef0123456789abcdef01234567" | .approval.approvers = ["fixture-admin"] | .issued = "2026-11-07T10:00:00Z"' \
    "$1/policy.json" > "$1/policy.json.new" && mv "$1/policy.json.new" "$1/policy.json"
  resign "$1"
  git -C "$1" init -q . 2>/dev/null
}
