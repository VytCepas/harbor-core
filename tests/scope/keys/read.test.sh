#!/usr/bin/env sh
# harbor.toml carries personal parameters core used to default to (harbor#1149): mail_account and
# github_owners are core's; reconcile_bq_project, gads_secret_project and antibot_trap_param are a pack's
# (harbor#1273), read only once its conf-keys.d file declares them. A typo is still refused, never read as unset.
. "$(dirname "$0")/../../lib/core.sh"; t_init
PV="$T_TMP/pv"; mkdir -p "$PV"; export HARBOR_SCOPE_PRIVATE="$PV"
CLAUDE_CONFIG_DIR="$T_TMP/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"; export CLAUDE_CONFIG_DIR
conf() { sh "$T_ROOT/bin/scope-roots.sh" --conf "$@" 2>"$T_TMP/err"; }
rc() { sh "$T_ROOT/bin/scope-roots.sh" --conf "$1" >/dev/null 2>&1; echo $?; }
PACK_KEYS='reconcile_bq_project antibot_trap_param gads_secret_project'

t_section "unset is exit 1 and nothing on stdout, never a default"
for k in mail_account github_owners; do
  t_eq "$k unset: exit 1" 1 "$(rc $k)"
  t_eq "$k unset: stdout empty" "" "$(conf $k)"
done

t_section "a pack's keys are not core's: with no pack installed they are refused (harbor#1273)"
for k in $PACK_KEYS; do t_eq "$k with no pack: exit 2" 2 "$(rc $k)"; done
t_hasnt "...and the key list does not offer them" "$(sh "$T_ROOT/bin/scope-roots.sh" --conf nope 2>&1 || true)" "gads_secret_project"

t_section "each key reads back, a pack's once its conf-keys.d file declares it"
mkdir -p "$CLAUDE_CONFIG_DIR/conf-keys.d"; printf '# a made-up pack\n%s\n' $PACK_KEYS > "$CLAUDE_CONFIG_DIR/conf-keys.d/zorbcorp.txt"
cat > "$PV/harbor.toml" <<'T'
mail_account = "ops@example.invalid"
github_owners = ["org-one", "org-two"]
reconcile_bq_project = "example-warehouse"
antibot_trap_param = "x_trap"
gads_secret_project = "example-secrets"
T
t_eq "mail_account" "ops@example.invalid" "$(conf mail_account)"
t_eq "antibot_trap_param" "x_trap" "$(conf antibot_trap_param)"
t_eq "github_owners prints one per line" "org-one
org-two" "$(conf github_owners)"
t_eq "reconcile_bq_project" "example-warehouse" "$(conf reconcile_bq_project)"
t_eq "gads_secret_project" "example-secrets" "$(conf gads_secret_project)"

t_section "a typo is still refused"
printf 'mail_acount = "x"\n' > "$PV/harbor.toml"
t_eq "an unknown key exits 2" 2 "$(rc mail_account)"
t_has "and names the key" "$(sh "$T_ROOT/bin/scope-roots.sh" --conf mail_account 2>&1 >/dev/null)" 'unknown key "mail_acount"'
t_exit "asking for a key that does not exist exits 2" 2 sh "$T_ROOT/bin/scope-roots.sh" --conf mail_acount
t_has "and the message lists the new keys" "$(sh "$T_ROOT/bin/scope-roots.sh" --conf nope 2>&1 || true)" "mail_account, github_owners"
t_has "a declared pack key among them" "$(sh "$T_ROOT/bin/scope-roots.sh" --conf nope 2>&1 || true)" "antibot_trap_param,"
t_done
