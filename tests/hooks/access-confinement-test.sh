#!/usr/bin/env sh
# access-confinement.sh (harbor#1298, #555 decisions 7 and 8): the hook mints a confined command's credentials outside
# the confinement, into a cache it can read. Against stubs only: a mint that logs each call, a gcx that prints a token.
. "$(dirname "$0")/../lib/core.sh"; t_init
M="$T_TMP/managed/managed-settings.json"; mkdir -p "$T_TMP/managed"
APPD="$T_TMP/app"; C="$T_TMP/cache"; IDS="$T_TMP/ids"; LOG="$T_TMP/calls.log"; mkdir -p "$APPD" "$IDS"; : > "$LOG"
# The hook reads no seam from the environment, so the suite drives a copy with its pinned paths rewritten.
HOOK="$T_TMP/access-confinement.sh"
sed -e "s|^C=.*|C=\"$C\"|" -e "s|^APPD=.*|APPD=\"$APPD\"|" -e "s|^IDS=.*|IDS=\"$IDS\"|" -e "s|^GCX=.*|GCX=\"$T_BIN/gcx\"|" \
    -e "s|^MK=.*|MK=\"$T_TMP/managed/harbor-confinement\"|" -e '/^\[ -f "\$MK" \] || MK=/d' "$T_ROOT/bin/access-confinement.sh" > "$HOOK"
t_eq "CONTROL: the copy's pins point at the fixture" 5 "$(grep -cE "^(C|APPD|IDS|GCX|MK)=\"$T_TMP" "$HOOK")"
cat > "$APPD/mint-token.sh" <<'EOF'
#!/bin/sh
a="${1:-VytCepas}"; echo "mint $a" >> "$CALLS"
printf '%s\ntok-%s\n' $(($(date +%s) + 3600)) "$a" > "$(dirname "$0")/token-$a"; echo "tok-$a"
EOF
cat > "$T_BIN/gcx" <<'EOF'
#!/bin/sh
echo "gcx $*" >> "$CALLS"
case "$*" in *application-default*) echo "ya29.adc-$1" ;; *) [ -n "${GCX_CLI_FAILS:-}" ] && exit 1; echo "ya29.cli-$1" ;; esac
EOF
chmod +x "$T_BIN/gcx"; export CALLS="$LOG"
printf 'acme-org\tAcme-Org\n' > "$APPD/orgs.tsv"
mkdir -p "$IDS/tools/configurations"; printf 'default\n' > "$IDS/tools/active_config"
printf '[core]\naccount = tools@example.com\nproject = example-project\n' > "$IDS/tools/configurations/config_default"
run() { printf '{"session_id":"s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | sh "$HOOK"; }
calls() { grep -c "$1" "$LOG" || :; }

t_section "inert until the confinement is installed"
OUT="$(run 'gh issue list')"; RC=$?
t_eq "no marker: exit 0" 0 "$RC"
t_eq "...prints nothing" "" "$OUT"
t_eq "...mints nothing" 0 "$(calls mint)"
t_eq "...and makes no cache" absent "$([ -e "$C" ] && echo present || echo absent)"
: > "$T_TMP/managed/harbor-confinement"

t_section "GitHub: minted when the command names gh, git or wait-for"
OUT="$(run 'ls -la')"
t_eq "a command that names none mints nothing" 0 "$(calls mint)"
t_eq "...but the owner table is copied for the shim" acme-org "$(cut -f1 "$C/orgs.tsv")"
OUT="$(run 'gh issue list -R VytCepas/harbor')"
t_eq "gh: the default account and the table's are minted" 2 "$(calls mint)"
t_eq "...copied into the cache" tok-VytCepas "$(sed -n 2p "$C/gh-VytCepas")"
t_eq "...for the org too" tok-Acme-Org "$(sed -n 2p "$C/gh-Acme-Org")"
. "$T_ROOT/bin/fs-lib.sh"; t_eq "...mode 600" 600 "$(fs_mode "$C/gh-VytCepas")"
t_eq "the hook printed nothing" "" "$OUT"
run 'git push' >/dev/null
t_eq "a fresh cache is not re-minted" 2 "$(calls mint)"
printf '%s\nold\n' $(($(date +%s) + 100)) > "$C/gh-VytCepas"
run 'ls' >/dev/null
t_eq "a token minted before is refreshed near expiry on any call" 3 "$(calls mint)"
t_eq "...with the new one" tok-VytCepas "$(sed -n 2p "$C/gh-VytCepas")"
run 'echo legit; agh-tool run' >/dev/null
t_eq "a word that only contains gh is not gh" 3 "$(calls mint)"

t_section "gcloud: the role the command names, CLI first, then ADC"
run 'gcx tools gcloud projects list' >/dev/null
t_eq "the named role is minted" ya29.cli-tools "$(cat "$C/gcloud-tools")"
_left=$(($(cat "$C/gcloud-tools.exp") - $(date +%s))); t_eq "...refreshed by 25 minutes out" ok "$([ "$_left" -ge 1400 ] && [ "$_left" -le 1500 ] && echo ok || echo "$_left")"
t_has "...and the role's config, so gcloud keeps its project" "$(cat "$C/gcloud-tools.properties")" "project = example-project"
run 'gcx nosuchrole gcloud config list' >/dev/null
t_eq "a role with no identity dir is never asked for" 0 "$(calls 'gcx nosuchrole')"
printf '%s\n' $(($(date +%s) - 1)) > "$C/gcloud-tools.exp"
GCX_CLI_FAILS=1 run 'ls' >/dev/null
t_eq "an expired role refreshes on any call, and a failed CLI login falls to ADC" ya29.adc-tools "$(cat "$C/gcloud-tools")"
cat > "$T_BIN/gcx" <<'EOF'
#!/bin/sh
echo 'not a token; rm -rf /'
EOF
printf '%s\n' $(($(date +%s) - 1)) > "$C/gcloud-tools.exp"
run 'gcx tools gcloud projects list' >/dev/null
t_eq "output that is not a token is never written" ya29.adc-tools "$(cat "$C/gcloud-tools")"

t_section "fail-open, always"
OUT="$(printf 'not json' | sh "$HOOK" 2>&1)"; RC=$?
t_eq "unparseable stdin: exit 0" 0 "$RC"
t_eq "...and silent" "" "$OUT"
t_eq "the marker path is the installer's, on both platforms" 2 "$(grep -cE "'/Library/Application Support/ClaudeCode/harbor-confinement'|/etc/claude-code/harbor-confinement" "$T_ROOT/bin/access-confinement.sh")"
t_has "...and the installer writes that name beside managed settings" "$(cat "$T_ROOT/bin/deploy-confinement.sh")" '"$BASE/harbor-confinement"'
t_eq "the shipped hook reads no seam from the environment" "" \
  "$(grep -nE 'HARBOR_(CONFINEMENT_CACHE|APP_DIR|GCX|GCLOUD_IDENTITIES|MANAGED_SETTINGS)' "$T_ROOT/bin/access-confinement.sh" | grep -v '^[0-9]*:#' || :)"
t_eq "CONTROL: the pattern finds a seam where one is read" 1 \
  "$(printf 'GCX="${HARBOR_GCX:-gcx}"\n' | grep -cE 'HARBOR_(CONFINEMENT_CACHE|APP_DIR|GCX|GCLOUD_IDENTITIES|MANAGED_SETTINGS)')"
t_done
