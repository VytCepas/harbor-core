#!/usr/bin/env sh
# access-confinement.sh (harbor#1298, #555 decisions 7 and 8) — the PreToolUse(Bash) hook that keeps a confined
# command's credentials fresh, minted OUTSIDE the confinement: a hook runs outside it, the command it gates does not.
#   <cache>/gh-<account>            the App installation token, as mint-token.sh caches it (expiry, token)
#   <cache>/orgs.tsv                the owner->account table (not secret; the denied dir hides it from the shim)
#   <cache>/gcloud-<role>           a gcx role's access token alone, for CLOUDSDK_AUTH_ACCESS_TOKEN_FILE
#   <cache>/gcloud-<role>.exp       its refresh-by time;  <cache>/gcloud-<role>.properties  the role's config (no secret)
# The cache is readable from inside the confinement and writable only outside it (CONTRACTS/confinement-paths.txt).
# It acts only while the confinement is installed (the marker deploy-confinement.sh leaves beside managed settings).
# A credential is minted when the command names its tool (gh, git, wait-for; gcx <role>), and one minted before is
# refreshed near expiry on any call, so a script that reaches gh or gcx indirectly still finds it fresh.
# Fail-open: it prints nothing and exits 0 on every path; a missed mint surfaces as the tool's own refusal.
# NO SEAM IS READ FROM THE ENVIRONMENT (review, #1300): a project's settings `env` reaches this hook, which runs outside
# the confinement, so an overridable mint script or gcx path would run a repo's code there. Tests drive a copy with
# these lines rewritten.
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
C="$HOME/.cache/harbor/confinement"
APPD="$HOME/.config/harbor-app"
IDS="$HOME/.config/gcloud/identities"
GCX="$HOME/.local/bin/gcx"
# The marker path is deploy-confinement.sh's; tests/floor/floor.confinement-test.sh holds the copies equal.
MK='/Library/Application Support/ClaudeCode/harbor-confinement'
[ -f "$MK" ] || MK=/etc/claude-code/harbor-confinement
[ -f "$MK" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
umask 077
mkdir -p "$C" 2>/dev/null && chmod 700 "$C" 2>/dev/null || exit 0
NOW="$(date +%s)" || exit 0
# stale <file> <margin> -> 0 when the expiry on the file's first line is within <margin> seconds, or unreadable
stale() { _x=; read -r _x < "$1" 2>/dev/null || return 0; case "$_x" in ''|*[!0-9]*) return 0 ;; esac; [ "$_x" -le $((NOW + $2)) ]; }
# put <src> <dst> -> an atomic copy into the cache, so a confined reader never sees half a token
put() { cp "$1" "$2.$$" 2>/dev/null && mv "$2.$$" "$2" 2>/dev/null || rm -f "$2.$$"; }

# GitHub: every account the table names, plus the default the mint and the shim fall back to.
if cmp -s "$APPD/orgs.tsv" "$C/orgs.tsv" 2>/dev/null; then :; elif [ -f "$APPD/orgs.tsv" ]; then put "$APPD/orgs.tsv" "$C/orgs.tsv"; fi
case " $CMD " in *[!A-Za-z0-9_-]gh[!A-Za-z0-9_-]*|*[!A-Za-z0-9_-]git[!A-Za-z0-9_-]*|*wait-for*) WANT=1 ;; *) WANT=0 ;; esac
for _a in VytCepas $(awk -F'\t' 'NF >= 2 && $2 ~ /^[A-Za-z0-9-]+$/ { print $2 }' "$APPD/orgs.tsv" 2>/dev/null | sort -u); do
  [ "$WANT" = 1 ] || [ -f "$C/gh-$_a" ] || continue
  # 11 minutes: mint-token.sh hands back its cached token until 10 are left, so this never copies a dying one twice
  stale "$C/gh-$_a" 660 || continue
  sh "$APPD/mint-token.sh" "$_a" >/dev/null 2>&1 && [ -f "$APPD/token-$_a" ] && put "$APPD/token-$_a" "$C/gh-$_a"
done

# gcloud through gcx: each role the command names, plus each role minted before.
_roles="$(printf '%s\n' "$CMD" | grep -oE '(^|[^A-Za-z0-9_-])gcx[[:space:]]+[A-Za-z0-9_-]+' | awk '{ print $NF }')"
for _f in "$C"/gcloud-*.exp; do [ -f "$_f" ] && { _r="${_f##*/gcloud-}"; _roles="$_roles ${_r%.exp}"; }; done
for _r in $(printf '%s\n' $_roles | sort -u); do
  [ -d "$IDS/$_r" ] || continue
  # Refresh-by is set 25 minutes out (below): gcloud prints a cached token, so its life left is not known here
  stale "$C/gcloud-$_r.exp" 300 || continue
  _t="$("$GCX" "$_r" gcloud auth print-access-token 2>/dev/null)" || _t=
  [ -n "$_t" ] || _t="$("$GCX" "$_r" gcloud auth application-default print-access-token 2>/dev/null)" || _t=
  case "$_t" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
  printf '%s\n' "$_t" > "$C/gcloud-$_r.$$" && mv "$C/gcloud-$_r.$$" "$C/gcloud-$_r" || { rm -f "$C/gcloud-$_r.$$"; continue; }
  printf '%s\n' $((NOW + 1500)) > "$C/gcloud-$_r.exp"
  _cfg=default; read -r _cfg < "$IDS/$_r/active_config" 2>/dev/null || _cfg=default
  [ ! -f "$IDS/$_r/configurations/config_$_cfg" ] || put "$IDS/$_r/configurations/config_$_cfg" "$C/gcloud-$_r.properties"
done
exit 0
