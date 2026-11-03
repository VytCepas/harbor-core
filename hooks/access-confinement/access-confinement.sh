#!/usr/bin/env sh
# access-confinement.sh (harbor#1298, #555 decisions 7 and 8) — the PreToolUse(Bash) hook that keeps a confined
# command's credentials fresh, minted OUTSIDE the confinement: a hook runs outside it, the command it gates does not.
#   <cache>/gh-<account>            the App installation token, as mint-token.sh caches it (expiry, token)
#   <cache>/orgs.tsv                the owner->account table (not secret; the denied dir hides it from the shim)
#   <cache>/gcloud-<role>           a gcx role's access token alone, for CLOUDSDK_AUTH_ACCESS_TOKEN_FILE
#   <cache>/gcloud-<role>.exp       its refresh-by time;  <cache>/gcloud-<role>.properties  the role's config (no secret)
# The cache is readable from inside the confinement and writable only outside it (contracts/confinement-paths.txt).
# It acts only while the confinement is installed (the marker deploy-confinement.sh leaves beside managed settings).
# A credential is minted when the command names its tool (gh, git, wait-for; gcx <role>), and one minted before is
# refreshed near expiry on any call, so a script that reaches gh or gcx indirectly still finds it fresh. The named ones
# go first, and the rest refresh only within BUDGET seconds: roles minted together go stale together.
# Fail-open: it prints nothing and exits 0 on every path; a missed mint surfaces as the tool's own refusal.
# NO SEAM IS READ FROM THE ENVIRONMENT (review, #1300): a project's settings `env` reaches this hook, which runs outside
# the confinement, so an overridable mint script or gcx path would run a repo's code there. Tests drive a copy with
# these lines rewritten.
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
# Silent on every path: a redirect that fails (a missing cache file, an unwritable temp) reports on the shell's stderr
exec 2>/dev/null
C="$HOME/.cache/harbor/confinement"
APPD="$HOME/.config/harbor-app"
IDS="$HOME/.config/gcloud/identities"
GCX="$HOME/.local/bin/gcx"
# Seconds the hook spends on credentials the command does not name, a third of the 30 s hook timeout (deploy-runtime-install.sh):
# a gcloud refresh is cut off at their end, and gh's starts only inside them, so at most one gh mint runs past.
BUDGET=10
# The marker path is deploy-confinement.sh's; tests/admission/baseline/confinement.test.sh holds the copies equal.
MK='/Library/Application Support/ClaudeCode/harbor-confinement'
[ -f "$MK" ] || MK=/etc/claude-code/harbor-confinement
[ -f "$MK" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
CMD="$(jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
umask 077
mkdir -p "$C" 2>/dev/null && chmod 700 "$C" 2>/dev/null || exit 0
NOW="$(date +%s)" || exit 0
# A temp outlives its hook only when the harness killed that hook; older than any live hook, it is litter
find "$C" -name '*.[0-9]*' -mmin +1 -exec rm -f {} + 2>/dev/null
# stale <file> <margin> -> 0 when the expiry on the file's first line is within <margin> seconds, or unreadable
stale() { _x=; read -r _x < "$1" 2>/dev/null || return 0; case "$_x" in ''|*[!0-9]*) return 0 ;; esac; [ "$_x" -le $((NOW + $2)) ]; }
# put <src> <dst> -> an atomic copy into the cache, so a confined reader never sees half a token
put() { cp "$1" "$2.$$" 2>/dev/null && mv "$2.$$" "$2" 2>/dev/null || rm -f "$2.$$"; }
# over -> 0 once the hook has run BUDGET seconds
over() { [ "$(date +%s)" -ge $((NOW + BUDGET)) ]; }
# gtok <role> <budgeted> <auth args> -> 0 with gcx's output in _t; a budgeted run is killed once over. Into a file, not
# a pipe: a pipe would keep the hook waiting on whatever the killed gcx left running.
gtok() {
  _g=$1 _b=$2; shift 2
  [ -z "$_b" ] || ! over || return 1
  "$GCX" "$_g" gcloud auth "$@" > "$C/gcloud-$_g.$$" & _p=$!
  [ -z "$_b" ] || { while kill -0 "$_p"; do over && kill "$_p"; sleep 1; done; } >/dev/null 2>&1 &
  wait "$_p" && _t="$(cat "$C/gcloud-$_g.$$")" && [ -n "$_t" ]
}
# gmint <role> [budgeted] -> the role's access token into the cache when it is near its refresh-by time
gmint() {
  [ -d "$IDS/$1" ] || return 0
  # Refresh-by is set 25 minutes out (below): gcloud prints a cached token, so its life left is not known here
  stale "$C/gcloud-$1.exp" 300 || return 0
  [ -z "${2:-}" ] || ! over || return 0
  _t=; gtok "$1" "${2:-}" print-access-token || gtok "$1" "${2:-}" application-default print-access-token || _t=
  rm -f "$C/gcloud-$1.$$"
  # A failed role goes to the back of the queue below, so one that keeps failing cannot spend every call's budget
  case "$_t" in ''|*[!A-Za-z0-9._-]*) touch -c "$C/gcloud-$1.exp"; return 0 ;; esac
  printf '%s\n' "$_t" > "$C/gcloud-$1.$$" && mv "$C/gcloud-$1.$$" "$C/gcloud-$1" || { rm -f "$C/gcloud-$1.$$"; return 0; }
  printf '%s\n' $((NOW + 1500)) > "$C/gcloud-$1.exp"
  _cfg=default; read -r _cfg < "$IDS/$1/active_config" 2>/dev/null || _cfg=default
  [ ! -f "$IDS/$1/configurations/config_$_cfg" ] || put "$IDS/$1/configurations/config_$_cfg" "$C/gcloud-$1.properties"
}

# gcloud through gcx, first each role the command names: nothing below may spend the hook's timeout before them.
_named=" $(printf '%s\n' "$CMD" | grep -oE '(^|[^A-Za-z0-9_-])gcx[[:space:]]+[A-Za-z0-9_-]+' | awk '{ print $NF }' | sort -u | tr '\n' ' ')"
for _r in $_named; do gmint "$_r"; done

# GitHub: every account the table names, plus the default the mint and the shim fall back to.
if cmp -s "$APPD/orgs.tsv" "$C/orgs.tsv" 2>/dev/null; then :; elif [ -f "$APPD/orgs.tsv" ]; then put "$APPD/orgs.tsv" "$C/orgs.tsv"; fi
case " $CMD " in *[!A-Za-z0-9_-]gh[!A-Za-z0-9_-]*|*[!A-Za-z0-9_-]git[!A-Za-z0-9_-]*|*wait-for*) WANT=1 ;; *) WANT=0 ;; esac
for _a in VytCepas $(awk -F'\t' 'NF >= 2 && $2 ~ /^[A-Za-z0-9-]+$/ { print $2 }' "$APPD/orgs.tsv" 2>/dev/null | sort -u); do
  [ "$WANT" = 1 ] || [ -f "$C/gh-$_a" ] || continue
  # 11 minutes: mint-token.sh hands back its cached token until 10 are left, so this never copies a dying one twice
  stale "$C/gh-$_a" 660 || continue
  [ "$WANT" = 1 ] || ! over || break
  sh "$APPD/mint-token.sh" "$_a" >/dev/null 2>&1 && [ -f "$APPD/token-$_a" ] && put "$APPD/token-$_a" "$C/gh-$_a"
done

# Then each role minted before, near its refresh-by time, within the budget: the one tried longest ago first.
for _f in $(cd "$C" && ls -tr gcloud-*.exp); do
  _r="${_f#gcloud-}"; _r="${_r%.exp}"
  case "$_named " in *" $_r "*) ;; *) gmint "$_r" budgeted ;; esac
done
exit 0
