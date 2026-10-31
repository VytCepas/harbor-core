#!/usr/bin/env sh
# access-confinement.sh (harbor#1298, #555 decisions 7 and 8): the hook mints a confined command's credentials outside
# the confinement, into a cache it can read. Against stubs only: a mint that logs each call, a gcx that prints a token.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
M="$T_TMP/managed/managed-settings.json"; mkdir -p "$T_TMP/managed"
APPD="$T_TMP/app"; C="$T_TMP/cache"; IDS="$T_TMP/ids"; LOG="$T_TMP/calls.log"; mkdir -p "$APPD" "$IDS"; : > "$LOG"
# The hook reads no seam from the environment, so the suite drives a copy with its pinned paths rewritten.
HOOK="$T_TMP/access-confinement.sh"
sed -e "s|^C=.*|C=\"$C\"|" -e "s|^APPD=.*|APPD=\"$APPD\"|" -e "s|^IDS=.*|IDS=\"$IDS\"|" -e "s|^GCX=.*|GCX=\"$T_BIN/gcx\"|" \
    -e "s|^MK=.*|MK=\"$T_TMP/managed/harbor-confinement\"|" -e '/^\[ -f "\$MK" \] || MK=/d' "$T_ROOT/hooks/access-confinement/access-confinement.sh" > "$HOOK"
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
OUT="$(run 'gh issue list -R VytCepas/harbor' 2>&1)"
t_eq "gh: the default account and the table's are minted" 2 "$(calls mint)"
t_eq "...copied into the cache" tok-VytCepas "$(sed -n 2p "$C/gh-VytCepas")"
t_eq "...for the org too" tok-Acme-Org "$(sed -n 2p "$C/gh-Acme-Org")"
. "$T_ROOT/bin/library-fs.sh"; t_eq "...mode 600" 600 "$(fs_mode "$C/gh-VytCepas")"
t_eq "the hook printed nothing, on stderr either, though no cache file existed yet" "" "$OUT"
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

t_section "the named role first, the rest within the budget, inside the harness's timeout"
# Six roles minted together go stale together; refreshed in sort order by a slow gcx, they ran the hook into its
# timeout before the named one, last of them. A copy with a 2 s budget against a 2 s gcx, killed at 6 s.
HOOK2="$T_TMP/access-confinement-budget.sh"; sed 's|^BUDGET=.*|BUDGET=2|' "$HOOK" > "$HOOK2"
t_eq "CONTROL: the copy's budget is the fixture's" 1 "$(grep -c '^BUDGET=2$' "$HOOK2")"
cat > "$T_BIN/gcx" <<'EOF'
#!/bin/sh
echo "gcx $*" >> "$CALLS"; sleep 2; echo "ya29.new-$1"
EOF
for _r in alpha beta beta-write gamma me tools; do
  mkdir -p "$IDS/$_r"; printf 'old-%s\n' "$_r" > "$C/gcloud-$_r"; printf '%s\n' $(($(date +%s) - 1)) > "$C/gcloud-$_r.exp"
done
printf '%s\nold\n' $(($(date +%s) + 100)) > "$C/gh-VytCepas"; _m="$(calls mint)"
# killed <secs> <command> -> the hook's exit, SIGKILLed at <secs> as the harness ends a hook at its timeout
killed() {
  printf '{"session_id":"s","tool_name":"Bash","tool_input":{"command":"%s"}}' "$2" > "$T_TMP/in.json"
  sh "$HOOK2" < "$T_TMP/in.json" > "$T_TMP/hook.out" 2>&1 & _hp=$!
  { sleep "$1"; kill -9 "$_hp"; } >/dev/null 2>&1 & _kp=$!
  wait "$_hp"; _hrc=$?; kill "$_kp" 2>/dev/null; return "$_hrc"
}
killed 6 'gcx tools gcloud projects list'; RC=$?
t_eq "the named role is minted, though it sorts last of six gone stale together" ya29.new-tools "$(cat "$C/gcloud-tools")"
t_eq "...the hook ends by itself, before the kill" 0 "$RC"
t_eq "...printing nothing" "" "$(cat "$T_TMP/hook.out")"
t_eq "...and with the budget spent, the other roles wait for a later call" old-alpha "$(cat "$C/gcloud-alpha")"
t_eq "...so does a cached gh token's refresh" "old $_m" "$(sed -n 2p "$C/gh-VytCepas") $(calls mint)"
t_eq "...and no temp file is left in the cache" "" "$(find "$C" -name '*.[0-9]*')"

t_section "a role that keeps failing goes to the back, and a slow one is cut off at the budget's end"
# A failing role sorting first spent every call's budget ahead of the rest; a slow one ran the hook into the kill.
cat > "$T_BIN/gcx" <<'EOF'
#!/bin/sh
echo "gcx $*" >> "$CALLS"
case "$1" in bad) sleep 1; exit 1 ;; slow) exec sleep 20 ;; esac
echo "ya29.new-$1"
EOF
rm -f "$C"/gcloud-*; for _a in VytCepas Acme-Org; do printf '%s\nfresh\n' $(($(date +%s) + 3600)) > "$C/gh-$_a"; done
for _r in bad beta gamma; do
  mkdir -p "$IDS/$_r"; printf 'old-%s\n' "$_r" > "$C/gcloud-$_r"; printf '%s\n' $(($(date +%s) - 1)) > "$C/gcloud-$_r.exp"
done
touch -t 202001010000 "$C/gcloud-bad.exp"; touch -t 202001010001 "$C/gcloud-beta.exp" "$C/gcloud-gamma.exp"
killed 6 'ls'
t_eq "CONTROL: the failing role, tried longest ago, spends the first call's budget" old-beta "$(cat "$C/gcloud-beta")"
killed 6 'ls'
t_eq "the next call refreshes the others first" "ya29.new-beta ya29.new-gamma" "$(cat "$C/gcloud-beta") $(cat "$C/gcloud-gamma")"
rm -f "$C"/gcloud-bad*; mkdir -p "$IDS/slow"; printf 'old-slow\n' > "$C/gcloud-slow"; printf '%s\n' $(($(date +%s) - 1)) > "$C/gcloud-slow.exp"
: > "$C/gh-VytCepas.4243"; : > "$C/gcloud-alpha.4242"; touch -t 202001010000 "$C/gcloud-alpha.4242"
killed 6 'ls'; RC=$?
t_eq "a refresh slower than the budget is cut off, and the hook ends by itself" 0 "$RC"
t_eq "...printing nothing" "" "$(cat "$T_TMP/hook.out")"
t_eq "...the role keeping its old token for a later call" old-slow "$(cat "$C/gcloud-slow")"
t_eq "...its temp file gone, a killed hook's old one swept, a live hook's kept" gh-VytCepas.4243 "$(find "$C" -name '*.[0-9]*' | sed 's|.*/||')"
rm -f "$C/gh-VytCepas.4243"

t_section "fail-open, always"
OUT="$(printf 'not json' | sh "$HOOK" 2>&1)"; RC=$?
t_eq "unparseable stdin: exit 0" 0 "$RC"
t_eq "...and silent" "" "$OUT"
t_eq "the marker path is the installer's, on both platforms" 2 "$(grep -cE "'/Library/Application Support/ClaudeCode/harbor-confinement'|/etc/claude-code/harbor-confinement" "$T_ROOT/hooks/access-confinement/access-confinement.sh")"
t_has "...and the installer writes that name beside managed settings" "$(cat "$T_ROOT/bin/deploy-confinement.sh")" '"$BASE/harbor-confinement"'
t_eq "the shipped hook reads no seam from the environment" "" \
  "$(grep -nE 'HARBOR_(CONFINEMENT_CACHE|APP_DIR|GCX|GCLOUD_IDENTITIES|MANAGED_SETTINGS)' "$T_ROOT/hooks/access-confinement/access-confinement.sh" | grep -v '^[0-9]*:#' || :)"
t_eq "CONTROL: the pattern finds a seam where one is read" 1 \
  "$(printf 'GCX="${HARBOR_GCX:-gcx}"\n' | grep -cE 'HARBOR_(CONFINEMENT_CACHE|APP_DIR|GCX|GCLOUD_IDENTITIES|MANAGED_SETTINGS)')"
t_done
