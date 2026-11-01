#!/usr/bin/env sh
# gcloud-creds: refuses an empty snapshot and a clobbering restore, and round-trips byte for byte (SEC-0, harbor#724).
# The store is the sandbox HOME's ~/.config/gcloud, and `secret` is the repo copy on
# tests/cli/keychain-stub.sh, so no case reaches the real store or the login Keychain.
# Typed as the gcloud-creds-test.sh shim (contracts/shims.tsv), $0 is a symlink: re-run from the file.
[ -L "$0" ] && exec sh "$(readlink "$0")" "$@"
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/../../cli/keychain-stub.sh"
TOOL="$T_ROOT/bin/gcloud-credentials"; ST="$HOME/.config/gcloud"
# bin/secret serves only a ref the access register names (harbor#1205): this suite's own name is registered here.
export ACCESS_DIR="$T_TMP/access"; mkdir -p "$ACCESS_DIR"
printf '\n## zz-selftest-gcloud-creds\n\n    secret: zz-selftest-gcloud-creds\n' >> "$ACCESS_DIR/register.md"
run() { GCLOUD_CREDS_ROOT="$ST" GCLOUD_CREDS_SECRET=zz-selftest-gcloud-creds \
        GCLOUD_CREDS_SECRET_BIN="$T_ROOT/bin/secret" sh "$TOOL" "$@"; }
manifest() { ( cd "$ST" && find . -type f -not -path './logs/*' -exec shasum -a 256 {} \; | sort -k2 ); }
mkstore() {
  rm -rf "$ST"
  mkdir -p "$ST/identities/alpha" "$ST/identities/tools" "$ST/oauth-clients" "$ST/logs/2026.09.03"
  printf '{"account":"analytics@example.com","refresh_token":"FAKE-ALPHA"}\n' > "$ST/identities/alpha/application_default_credentials.json"
  printf '{"account":"tools@example.com","refresh_token":"FAKE-TOOLS"}\n' > "$ST/identities/tools/application_default_credentials.json"
  printf '{"installed":{"client_id":"FAKE-DESKTOP"}}\n' > "$ST/oauth-clients/alpha-desktop.json"
  printf 'noise\n' > "$ST/logs/2026.09.03/gcloud.log"
}

t_section "T1 an empty store is refused"
rm -rf "$ST"; mkdir -p "$ST/identities/alpha"
t_exit "snapshot of an empty store exits 1" 1 run snapshot
t_has "and refuses it by name" "$(run snapshot 2>&1)" "$ST holds no credentials"

t_section "T4 restore refuses to clobber live credentials"
mkstore; T4B="$(manifest)"
t_exit "restore over live credentials exits 1" 1 run restore
t_has "and refuses it by name" "$(run restore 2>&1)" "$ST already holds 2 credential(s)"
t_eq "the live store is byte-for-byte untouched" "$T4B" "$(manifest)"

t_section "T2 T3 a populated store snapshots its credentials and not its logs"
mkstore; BEFORE="$(manifest)"
t_exit "T2 snapshot of a populated store" 0 run snapshot
LIST="$(run list 2>/dev/null)"
t_has "T3a the ADC is in the snapshot" "$LIST" identities/alpha/application_default_credentials.json
t_has "T3b the OAuth client is in the snapshot" "$LIST" oauth-clients/alpha-desktop.json
t_has "the store held a log to exclude" "$(cd "$ST" && find . -type f)" ./logs/
t_hasnt "T3c logs are excluded" "$LIST" logs/

t_section "T5 wipe, restore, byte-for-byte"
rm -rf "$ST"
t_exit "restore into a wiped store" 0 run restore
t_eq "the round-trip is byte-for-byte" "$BEFORE" "$(manifest)"

t_section "T6 check"
t_exit "check passes on a good store" 0 run check
rm -f "$ST/identities/alpha/application_default_credentials.json"
t_exit "check fails when an ADC is missing" 1 run check

t_section "T7 control: a forced restore overwrites, never no-ops"
mkstore
t_exit "setup: forced snapshot" 0 run snapshot --force
printf 'MUTATED\n' > "$ST/identities/tools/application_default_credentials.json"
t_exit "forced restore" 0 run restore --force
t_has "restore put the snapshot's bytes back over the mutation" \
  "$(cat "$ST/identities/tools/application_default_credentials.json")" FAKE-TOOLS
t_done
