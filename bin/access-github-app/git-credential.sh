#!/bin/sh
# git credential helper (harbor#1018): inside a Claude Code session (CLAUDECODE=1) github.com pushes and fetches
# authenticate as the harbor-claude GitHub App. Elsewhere it answers nothing, so git falls through to osxkeychain.
# In a session a failed mint answers quit=1: git stops rather than falling through to the operator's login.
# Installed as git-credential-harbor on PATH (helper value `harbor`) as well as in ~/.config/harbor-app: under the
# confinement that directory is OS-denied, so git could not run the old copy and fell through to the operator's
# Keychain credential (harbor#1297 round 1). The token then comes from the access-confinement hook's cache.
[ "${1:-}" = get ] || exit 0
[ "${CLAUDECODE:-}" = 1 ] || exit 0
_C="${HARBOR_ACCESS_CONFINEMENT_CACHE:-$HOME/.cache/harbor/confinement}"
# The installation follows the repo owner: path= when git sends it (useHttpPath), else the cwd's origin.
_p=; while IFS= read -r _l && [ -n "$_l" ]; do case "$_l" in path=*) _p="${_l#path=}" ;; esac; done
_o="${_p%%/*}"
if [ -z "$_o" ]; then
  _u="$(git config --get remote.origin.url 2>/dev/null)"
  case "$_u" in *github.com[:/]*) _u="${_u#*github.com[:/]}"; _o="${_u%%/*}" ;; esac
fi
# An owner listed in orgs.tsv (owner<TAB>account) gets that account's installation: the operator's table, else the
# hook's copy. awk's own open decides, since under Seatbelt `[ -r ]` can say readable for a file open(2) refuses.
_acct=
for _tf in "$HOME/.config/harbor-app/orgs.tsv" "$_C/orgs.tsv"; do
  _a="$(awk -F'\t' -v o="$_o" 'tolower($1) == tolower(o) { print $2; exit }' "$_tf" 2>/dev/null)" && { _acct="$_a"; break; }
done
# git asks once, before the pre-push hook, and uploads after it, so the token must outlive the hook (azimuth's gate
# ran up to ~40 min and then took HTTP 401). A token with 50 min left, else a fresh mint where the key opens; a
# confined session cannot mint, so there the hook's token while it has a minute left.
_t= _s= _now=$(date +%s)
if { read -r _e && read -r _k; } < "$_C/gh-${_acct:-VytCepas}" 2>/dev/null; then
  case "$_e" in ''|*[!0-9]*) ;; *) [ "$_e" -le $((_now + 3000)) ] || _t="$_k"; [ "$_e" -le $((_now + 60)) ] || _s="$_k" ;; esac
fi
# A subshell: a failed redirect on `:` (a special builtin) exits the whole script under dash, not only the test.
if [ -z "$_t" ] && ( : < "$HOME/.config/harbor-app/app.pem" ) 2>/dev/null; then
  _t="$(sh "$HOME/.config/harbor-app/mint-token.sh" "$_acct" 3000)" || _t=
fi
[ -n "$_t" ] || _t="$_s"
[ -n "$_t" ] || _t="$(sh "$HOME/.config/harbor-app/mint-token.sh" $_acct)" || _t=
if [ -n "$_t" ]; then
  printf 'username=x-access-token\npassword=%s\n' "$_t"
else
  printf 'quit=1\n'
fi
