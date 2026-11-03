#!/usr/bin/env sh
# deploy-harden.sh's decided env keys (harbor#816, operator 2026-09-29): keep Remote Control on
# (usage metrics + feature flags stay unset), off is error reporting, /feedback, the feedback
# survey, and marketplace autoinstall. Forced to "1", every other env key untouched, idempotent,
# and the baseline sec0 re-pins itself covers the new top-level `env` key with no separate step.
. "$(dirname "$0")/../../lib/core.sh"; t_init
SRC="$T_ROOT/bin"; SEC0="$SRC/deploy-harden.sh"
sh0() { env -u CLAUDE_CONFIG_DIR sh "$SEC0" "$@"; }  # t_init's CLAUDE_CONFIG_DIR is not these --dir targets
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
KEYS='DISABLE_ERROR_REPORTING DISABLE_FEEDBACK_COMMAND CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL'
NOT_DECIDED='DISABLE_TELEMETRY DO_NOT_TRACK CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC'

t_section "harbor#816: a dry run lists each missing key, in the deny-entry notes' shape"
D="$T_TMP/dry"; mkdir -p "$D"; printf '{}\n' > "$D/settings.json"
OUT="$(sh0 --dir "$D" 2>&1)"
for k in $KEYS; do
  t_has "$k is listed to add" "$OUT" "  note: env to add (harbor#816: "
  t_has "...naming the key and its decided value" "$(printf '%s\n' "$OUT" | grep "env to add")" "$k=1"
done
t_eq "nothing was written on a dry run" '{}' "$(cat "$D/settings.json")"
t_eq "no baseline written on a dry run" no "$([ -f "$D/.sec0-baseline.sha256" ] && echo yes || echo no)"

t_section "harbor#816: --apply sets all four to \"1\", and never touches an undecided key"
A="$T_TMP/apply"; mkdir -p "$A"
printf '{"env":{"DISABLE_TELEMETRY":"1","DO_NOT_TRACK":"1","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","FOO":"bar"}}\n' > "$A/settings.json"
sh0 --apply --dir "$A" >/dev/null 2>&1
for k in $KEYS; do
  t_eq "$k is set to 1" '"1"' "$(jq ".env.$k" "$A/settings.json")"
done
for k in $NOT_DECIDED; do
  t_eq "$k (deliberately not decided) is untouched" '"1"' "$(jq ".env.$k" "$A/settings.json")"
done
t_eq "an unrelated operator env key survives" '"bar"' "$(jq '.env.FOO' "$A/settings.json")"
t_eq "exactly eight keys are present: four decided plus the operator's four" 8 "$(jq '.env | length' "$A/settings.json")"

t_section "harbor#816: idempotent — a second run reports nothing to change"
OUT2="$(sh0 --dir "$A" 2>&1)"
t_has "the ok line, not another note" "$OUT2" "  ok: every SEC-0 env key is present (4)"
t_hasnt "no key is listed to add" "$OUT2" "env to add"
t_has "settings.json is already hardened" "$OUT2" "ok: settings.json is already hardened: nothing would change"
_before="$(cat "$A/settings.json")"
sh0 --apply --dir "$A" >/dev/null 2>&1
t_eq "a second --apply writes byte-identical env" "$_before" "$(cat "$A/settings.json")"

t_section "harbor#816: a hand-flipped decided key is corrected back to \"1\" on the next apply"
jq '.env.DISABLE_ERROR_REPORTING = "0"' "$A/settings.json" > "$T_TMP/s.tmp" && mv "$T_TMP/s.tmp" "$A/settings.json"
OUT3="$(sh0 --dir "$A" 2>&1)"
t_has "the dry run lists it to add back" "$OUT3" "DISABLE_ERROR_REPORTING=1"
sh0 --apply --dir "$A" >/dev/null 2>&1
t_eq "corrected back to 1" '"1"' "$(jq '.env.DISABLE_ERROR_REPORTING' "$A/settings.json")"
t_eq "the operator's own key is still untouched" '"1"' "$(jq '.env.DISABLE_TELEMETRY' "$A/settings.json")"

t_section "harbor#816: adding env for the first time changes the baseline's top-level keys, and sec0 re-pins itself"
BK="$T_TMP/bk"; mkdir -p "$BK"; printf '{}\n' > "$BK/settings.json"
_keys0="$(jq -Sc '(keys) - ["hooks"]' "$BK/settings.json")"
t_hasnt "before apply, settings.json has no env key" "$_keys0" '"env"'
sh0 --apply --dir "$BK" >/dev/null 2>&1
_keys1="$(jq -Sc '(keys) - ["hooks"]' "$BK/settings.json")"
t_has "after apply, env is a top-level key" "$_keys1" '"env"'
_want="$(jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$BK/settings.json" | sha)"
t_eq "sec0's own re-pin covers the new key, with no separate step" "$_want" "$(cat "$BK/.sec0-baseline.sha256")"

t_section "harbor#1313 L6: docs/explanation/admission-baseline.md's key containers and all four id_* names are Read-denied wherever they live"
# The Read tool has no hook, so permissions.deny is the whole defence and these entries are the fix.
# id_dsa and id_ecdsa were covered only under this HOME, by Read(~/.ssh/**).
_dn="$(jq -c '.permissions.deny' "$BK/settings.json")"
for _c in 'C1-L6-ccg-146 Read(//**/*.p12)' 'C1-L6-ccg-147 Read(//**/*.pfx)' \
          'C1-L6-ccg-148 Read(//**/id_dsa)' 'C1-L6-ccg-149 Read(//**/id_ecdsa)' \
          'C1-L6-jks Read(//**/*.jks)' 'C1-L6-keystore Read(//**/*.keystore)'; do
  t_eq "${_c%% *}: ${_c#* } is written" true "$(printf '%s' "$_dn" | jq --arg e "${_c#* }" 'index($e) != null')"
done
t_eq "C1-L6-ok: public keys and certificates stay readable (no .pub, .crt or id_* wildcard entry)" 0 \
  "$(printf '%s' "$_dn" | jq '[.[] | select(test("\\.pub|\\.crt|id_\\*"))] | length')"

t_done
