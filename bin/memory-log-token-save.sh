#!/usr/bin/env sh
# memory-log-token-save.sh (harbor#431, #1205) — put the work-log token in the store as worklog-token
# without ever showing it, and without leaving it on the clipboard.
#
#   sh memory-log-token-save.sh          # reads the clipboard, stores worklog-token, removes the old plaintext file
#   sh memory-log-token-save.sh --help
#
# Captured from the box, not written here: this existed only as an installed file in the live floor, handling a GitHub PAT
# with no commit holding it, until drift-install.sh (harbor#431) named it as unsourced. The behaviour is the box's, preserved.
# It never prints the token: success prints a LENGTH and a confirmation, since stderr, stdout and scrollback are where a
# pasted credential outlives the paste (constitution §3).
# The value goes into the store (harbor#1205, decided 2026-10-23) on stdin to `secret put`, never on disk or in argv; a
# leftover plaintext file moves with `secret adopt <file> worklog-token`.
# Removed notes: docs/explanation/code-cases/bin-memory-log-token-save.md
set -eu

case "${1:-}" in
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) printf 'save-log-token: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

# Its lines are log-lib's (contracts/logging.md), installed beside it in the config dir's bin/.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init save-log-token

if command -v pbpaste >/dev/null 2>&1; then CLIP=mac
elif command -v wl-paste >/dev/null 2>&1; then CLIP=wl
elif command -v xclip >/dev/null 2>&1; then CLIP=xclip
elif command -v xsel >/dev/null 2>&1; then CLIP=xsel
elif command -v powershell.exe >/dev/null 2>&1; then CLIP=wsl
else
  log_fail "no clipboard tool — looked for pbpaste, wl-paste, xclip, xsel and powershell.exe (WSL2)"
  log_fix "install wl-clipboard (Wayland), xclip or xsel (X11), then run this again"
  log_end || :; exit 2
fi
clip_read() {
  case "$CLIP" in
    mac) pbpaste ;; wl) wl-paste --no-newline ;; xclip) xclip -selection clipboard -o ;;
    xsel) xsel --clipboard --output ;; wsl) powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r' ;;
  esac
}
clip_clear() {
  case "$CLIP" in
    mac) pbcopy < /dev/null ;; wl) wl-copy --clear ;; xclip) xclip -selection clipboard -i < /dev/null ;;
    xsel) xsel --clipboard --clear ;; wsl) clip.exe < /dev/null ;;
  esac
}

DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-log-token"   # legacy plaintext, removed once the store holds it
SECRET="${HARBOR_ACCESS_SECRET_BIN:-${HARBOR_SECRET_BIN:-$(command -v secret 2>/dev/null || true)}}"; [ -n "$SECRET" ] || SECRET="$HOME/.local/bin/secret"

# `|| true` on the substitution: under `set -e` a bare `T="$(clip_read)"` aborts, so a fallback written beneath it is dead code.
T="$(clip_read 2>/dev/null || true)"

case "$T" in
  github_pat_*|ghp_*)
    # Piped to the store so the value never reaches argv. A refused store is a FAIL, never a quiet fall back to plaintext; its stderr goes to a FILE (a `2>&1 >/dev/null` capture would tee it) and then to the operator.
    ERRF="$(mktemp "${TMPDIR:-/tmp}/save-log-token.XXXXXX")" || ERRF=/dev/null
    if ! printf %s "$T" | sh "$SECRET" put worklog-token >/dev/null 2>"$ERRF"; then
      T=""; clip_clear 2>/dev/null || true
      log_fail "NOT SAVED: the credential store refused worklog-token (clipboard cleared)"
      log_fix "sh $SECRET list; harbor access check   # the register must name worklog-token"
      [ ! -s "$ERRF" ] || while IFS= read -r _l; do log_note "store: $_l"; done < "$ERRF"
      [ "$ERRF" = /dev/null ] || rm -f "$ERRF"
      log_end || :; exit 1
    fi
    [ "$ERRF" = /dev/null ] || rm -f "$ERRF"
    T_LEN=${#T}; T=""
    clip_clear 2>/dev/null || true
    rm -f "$DEST"
    log_ok "token stored as worklog-token ($T_LEN chars, clipboard cleared, plaintext file removed)"
    log_end
    ;;
  *)
    # Four characters of prefix tell "copied the wrong thing" from "copied nothing" and are too short to carry a secret.
    log_fail "NOT SAVED: clipboard does not look like a GitHub token (starts: $(printf %.4s "$T")...)"
    log_fix "copy the token on GitHub (github_pat_...) as the LAST thing, then: sh $0"
    log_end || :; exit 1
    ;;
esac
