#!/usr/bin/env sh
# access-github-app-install.sh — the in-session GitHub App scripts, COPIED from bin/access-github-app/. harbor#1225.
#   sh access-github-app-install.sh [--apply] (--live | --dir HOME)   DRY RUN unless --apply
#     --live is this account's $HOME; --dir HOME any other root laid out the same way.
#     The dry run is the drift report: one line per script, same / differs / missing / a symlink.
#     --apply refuses inside a Claude session: only the operator's terminal installs these.
#
# WHAT IT INSTALLS (harbor#1018): the gh shim at <bin>/gh, and git-credential.sh and mint-token.sh in
# <home>/.config/harbor-app/. Nothing else in that directory is touched: app.pem, app-id and the token
# caches are the operator's and never live in this repo. The owner->account table (orgs.tsv) names real
# organisations, so core carries none: it is copied from the private layer's harbor-app/orgs.tsv when that exists.
#
# COPIES, NEVER LINKS. A session can edit this checkout, and a shim that drops GH_TOKEN falls through to
# the operator's own gh login — the escalation the denied directories exist to stop. A symlink at a
# destination is therefore replaced by a regular file, never written through.
# NO .harbor-manifest ROWS, like shim-install: nothing lands in a config dir this standard owns.
set -eu
SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init harbor-app-install
IL_LIVE_DIR="${HOME:-}"
IL_ENV=''
il_parse "$@"
if [ "$IL_LIVE" -eq 1 ] && [ -d "${HOME:-}/.claude" ]; then IL_STATE="$HOME/.claude"; fi
il_target
if [ "$IL_LIVE" -eq 1 ]; then BIN="$(sh "$SRC/scope-roots.sh" --get HARBOR_LOCAL_BIN)"; else BIN="$IL_TARGET/.local/bin"; fi
CFG="$IL_TARGET/.config/harbor-app"
il_session "$(il_cmd --apply)"
il_stop
if [ "$IL_APPLY" -eq 1 ] && [ -z "$IL_BK" ]; then
  mkdir -p "$IL_STATE" && log_file "$IL_STATE"; IL_BK="$LOG_DIR"
fi
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $IL_TARGET"; else log_head "plan for $IL_TARGET (dry run: nothing is written)"; fi

CHANGE=0
put() { putf "$SRC/access-github-app/$1" "$2" "$3" "$1"; } # <source name> <destination> <mode>
putf() { # <source file> <destination> <mode> [label]
  _s="$1"; _d="$2"; _m="$3"; _n="${4:-orgs.tsv}"
  if [ ! -f "$_s" ]; then log_fail "$_n: no source at $_s"; log_nofix "deploy from a harbor checkout"; return 0; fi
  if [ -L "$_d" ]; then _was="a symlink to $(readlink "$_d")"
  elif [ ! -e "$_d" ]; then _was=missing
  elif cmp -s "$_s" "$_d"; then log_ok "$_n: same ($_d)"; return 0
  else _was=differs; fi
  CHANGE=1
  if [ "$IL_APPLY" -eq 0 ]; then
    log_note "$_n: $_was ($_d) — would copy"
    [ "$_was" != differs ] || diff -u "$_d" "$_s" | sed 's/^/    /' >&2 || :
    return 0
  fi
  [ ! -e "$_d" ] && [ ! -L "$_d" ] || il_backup "$_d" || return 0
  mkdir -p "$(dirname "$_d")"
  rm -f "$_d"
  if cp "$_s" "$_d" && chmod "$_m" "$_d"; then log_ok "$_n: installed ($_was before) at $_d"
  else log_fail "$_n: could not copy to $_d"; log_nofix "the cp error above"; fi
}
[ -d "$CFG" ] || [ "$IL_APPLY" -eq 0 ] || { mkdir -p "$CFG" && chmod 700 "$CFG"; }
put gh "$BIN/gh" 755
put git-credential.sh "$CFG/git-credential.sh" 700
put mint-token.sh "$CFG/mint-token.sh" 700
# The helper's PATH copy (harbor#1298): git runs git-credential-harbor for the helper value `harbor`. Under the
# confinement ~/.config/harbor-app is OS-denied, so a helper entry pointing in there cannot even start, and git
# falls through to the operator's Keychain login (harbor#1297 round 1). Repoint it; every other entry stays put.
put git-credential.sh "$BIN/git-credential-harbor" 755
GC="$IL_TARGET/.gitconfig"; GK='credential.https://github.com.helper'; GOLD='/\.config/harbor-app/git-credential\.sh$'
if git config --file "$GC" --get-all "$GK" 2>/dev/null | grep -qE "$GOLD"; then
  CHANGE=1
  if [ "$IL_APPLY" -eq 0 ]; then log_note "gitconfig: the github.com helper runs ~/.config/harbor-app/git-credential.sh — would repoint it to harbor"
  elif il_backup "$GC" && git config --file "$GC" --replace-all "$GK" harbor "$GOLD"; then log_ok "gitconfig: the github.com helper now runs git-credential-harbor"
  else log_fail "gitconfig: could not repoint the github.com helper in $GC"; log_fix "git config --global --replace-all $GK harbor '$GOLD'"; fi
fi
PRIV="$(sh "$SRC/scope-roots.sh" --private 2>/dev/null)" || PRIV=
if [ -n "$PRIV" ] && [ -f "$PRIV/harbor-app/orgs.tsv" ]; then putf "$PRIV/harbor-app/orgs.tsv" "$CFG/orgs.tsv" 600; fi

[ "$IL_APPLY" -eq 1 ] || [ "$CHANGE" -eq 0 ] || il_next "$(il_cmd --apply)"
log_end; exit $?
