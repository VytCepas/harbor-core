#!/usr/bin/env sh
# hub-pin-upgrade.sh (harbor#1278) — raises the hub policy's core pin on a branch of the hub checkout, and stops before signing.
#   sh hub-pin-upgrade.sh --pin <40-hex harbor-core commit> --hub <hub checkout> --core <harbor-core checkout> [--key <signing key>]
#   HARBOR_HUB_DIR and HARBOR_HUB_CORE_DIR stand in for --hub and --core.
# It edits policy.json only: serial + 1, issued = now (UTC), core.commit = the pin, on a new branch pin/<12 hex>. Then it checks the file
# with the pin's own hub-format.sh and prints the signing and push lines. Signing is the hub admin's alone: this script never signs.
# Refused (exit 1, nothing changed): a pin not on the core checkout's origin/main, a dirty hub checkout, a pin the policy already holds,
# a CONTRACT_VERSION change (edit core.contract by hand, check every pack's harbor_version), an edited policy that fails the hub format.
# Exit 0 branch ready to sign, 1 refused, 2 usage error or an unreadable input.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init hub-pin-upgrade

PIN=''; HUB="${HARBOR_HUB_DIR:-}"; CORE="${HARBOR_HUB_CORE_DIR:-}"; KEY='<your-signing-key>'
usage() { log_fail "$1"; log_nofix "sh $0 --help"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pin|--hub|--core|--key)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in --pin) PIN="$2" ;; --hub) HUB="$2" ;; --core) CORE="$2" ;; --key) KEY="$2" ;; esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) usage "unknown argument $1" ;;
  esac
  shift
done
case "$PIN" in ''|*[!0123456789abcdef]*) usage "--pin wants a 40-hex harbor-core commit, got '$PIN'" ;; esac
[ "${#PIN}" -eq 40 ] || usage "--pin wants the full 40-character commit, got '$PIN'"
[ -n "$HUB" ] && [ -f "$HUB/policy.json" ] || usage "--hub wants a hub checkout holding policy.json"
[ -n "$CORE" ] && git -C "$CORE" rev-parse --git-dir >/dev/null 2>&1 || usage "--core wants a harbor-core checkout"
command -v jq >/dev/null 2>&1 || usage "jq is not installed"
refuse() {
  log_fail "$1"
  if [ -n "${2:-}" ]; then log_fix "$2"; else log_nofix "contracts/hub.md"; fi
  exit 1
}

git -C "$CORE" fetch -q origin || usage "cannot fetch origin in $CORE"
git -C "$CORE" merge-base --is-ancestor "$PIN" origin/main 2>/dev/null \
  || refuse "$PIN is not on harbor-core main" "merge the export pull request first, then pass the commit it created"
[ -z "$(git -C "$HUB" status --porcelain)" ] || refuse "$HUB has uncommitted changes" "commit or discard them in the hub checkout"
git -C "$HUB" fetch -q origin && git -C "$HUB" switch -q main && git -C "$HUB" merge -q --ff-only origin/main \
  || refuse "the hub checkout cannot move to an up-to-date main" "git -C $HUB switch main && git -C $HUB pull --ff-only"
CV="$(git -C "$CORE" show "$PIN:bin/harbor" | sed -n 's/^CONTRACT_VERSION=\([0-9][0-9]*\)$/\1/p' | head -n 1)"
[ -n "$CV" ] || refuse "$PIN carries no CONTRACT_VERSION in bin/harbor" "is it a harbor-core commit?"
OLD="$(jq -r .core.commit "$HUB/policy.json")"; SERIAL="$(jq -r .serial "$HUB/policy.json")"
[ "$OLD" != "$PIN" ] || refuse "the policy already pins $PIN" ""
[ "$(jq -r .core.contract "$HUB/policy.json")" = "$CV" ] \
  || refuse "contract changes (policy $(jq -r .core.contract "$HUB/policy.json"), core $CV)" "edit core.contract by hand and check every pack's harbor_version"

B="pin/$(printf %.12s "$PIN")"
git -C "$HUB" switch -q -c "$B" || refuse "cannot create branch $B in $HUB" "does it exist already?"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq --arg c "$PIN" --arg t "$NOW" '.serial += 1 | .issued = $t | .core.commit = $c' "$HUB/policy.json" > "$HUB/policy.json.new"
mv "$HUB/policy.json.new" "$HUB/policy.json"
# The pin's own checker, with the files it reads beside it: the format the laptops will hold the policy to.
FMT="$(mktemp -d "${TMPDIR:-/tmp}/hub-format.XXXXXX")"; trap 'rm -rf "$FMT"' EXIT INT TERM
git -C "$CORE" archive "$PIN" bin contracts | tar -x -C "$FMT"
if ! sh "$FMT/bin/hub-format.sh" policy "$HUB/policy.json" 2>/dev/null; then
  git -C "$HUB" checkout -q -- policy.json; git -C "$HUB" switch -q main; git -C "$HUB" branch -q -D "$B"
  refuse "the edited policy fails contracts/hub.md: nothing to sign" ""
fi
log_ok "branch $B: serial $SERIAL -> $((SERIAL + 1)), core.commit $(printf %.12s "$OLD") -> $(printf %.12s "$PIN"), issued $NOW"
git -C "$HUB" diff --stat >&2
cat <<MSG

Now, the hub admin alone (the signing asks for the key's passphrase):
  cd "$HUB" && rm -f policy.json.sig && ssh-keygen -Y sign -f "$KEY" -n harbor-hub policy.json
  ssh-keygen -Y verify -f hub-signers -I hub -n harbor-hub -s policy.json.sig < policy.json
Then:
  git -C "$HUB" commit -am "hub: core pin $(printf %.12s "$PIN"), serial $((SERIAL + 1))" && git -C "$HUB" push -u origin "$B"
  gh pr create -R <org>/<hub-repo> --head "$B" --title "hub: core pin $(printf %.12s "$PIN")" --body "Raises core.commit to $PIN (serial $((SERIAL + 1)))."
  gh variable set HARBOR_HUB_CORE_SHA -R <org>/<hub-repo> --body "$PIN"
Merge it once the hub gate is green.
MSG
log_end
