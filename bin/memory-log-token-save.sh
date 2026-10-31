#!/usr/bin/env sh
# memory-log-token-save.sh (harbor#431, #1205) — put the work-log token in the store as worklog-token
# without ever showing it, and without leaving it on the clipboard.
#
#   sh memory-log-token-save.sh          # reads the clipboard, stores worklog-token, removes the old plaintext file
#   sh memory-log-token-save.sh --help
#
# CAPTURED FROM THE BOX, NOT WRITTEN HERE. This existed only as an installed file
# in the live floor: no commit, no branch, no working tree of this repository held
# it, and it had been handling a GitHub PAT that way for an unknown length of time.
# drift-install.sh (harbor#431) is what named it — `unsourced memory-log-token-save.sh
# (in no commit of this repository)` — because it is the one check that enumerates
# the LIVE directory instead of the repo, so it can see a file nothing here ships.
# Everything else compared repo-to-box and could only ever miss it.
#
# The behaviour is the box's, preserved deliberately; what this adds is the
# repository conventions it now has to meet (S1 shebang + strict mode, S3 ticket,
# S4 --help) and the two properties below stated where a reader will find them.
#
# WHY IT NEVER PRINTS THE TOKEN. The only output on success is a LENGTH and a
# confirmation. A guard's stderr, a hook's stdout and a terminal scrollback are
# all places a pasted credential outlives the paste, and the operator running this
# already has the value — echoing it back buys nothing and costs a copy in the
# session transcript, which is exactly what CONSTITUTION §3 is about.
#
# WHY THE STORE AND NOT A FILE (harbor#1205, decided 2026-10-23). The value goes in on stdin to `secret put`, so it
# is never on disk or in argv. A plaintext file from before is never read by anything any more; `secret adopt <file>
# worklog-token` moves one that is still there without a new token.
set -eu

case "${1:-}" in
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) printf 'save-log-token: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

# Its lines are log-lib's (contracts/logging.md), installed beside it in the config dir's bin/.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init save-log-token

# The clipboard: pbpaste/pbcopy on macOS; wl-clipboard, xclip or xsel on Linux; under WSL2 the
# Windows clipboard, through powershell.exe and clip.exe (harbor#618).
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
SECRET="${HARBOR_SECRET_BIN:-$(command -v secret 2>/dev/null || true)}"; [ -n "$SECRET" ] || SECRET="$HOME/.local/bin/secret"

# `|| true` ON THE SUBSTITUTION, not on a later line. Under `set -e` a bare
# `T="$(clip_read)"` ABORTS on a non-zero read, so a fallback written underneath
# it is dead code that never runs — measured trap, and the reason the guard below
# is reachable at all.
T="$(clip_read 2>/dev/null || true)"

case "$T" in
  github_pat_*|ghp_*)
    # The store, not a file (harbor#1205): piped, so the value never reaches argv or a prompt's echo.
    # A refused store is a FAIL, never a quiet fall back to the plaintext file.
    # The store's stderr goes to a FILE, then to the operator: its own words say why (a register entry that
    # does not name the ref), and a file leaks nothing a `2>&1 >/dev/null` capture would tee. The token goes in
    # on stdin only, so it is not in anything `secret` says about its arguments.
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
    # LENGTH, NEVER THE VALUE. Enough to tell a truncated paste from a whole one.
    log_ok "token stored as worklog-token ($T_LEN chars, clipboard cleared, plaintext file removed)"
    log_end
    ;;
  *)
    # FOUR CHARACTERS OF THE PREFIX, which is what distinguishes "I copied the
    # wrong thing" from "I copied nothing" — and is short enough to carry no
    # secret even when the clipboard did hold one.
    log_fail "NOT SAVED: clipboard does not look like a GitHub token (starts: $(printf %.4s "$T")...)"
    log_fix "copy the token on GitHub (github_pat_...) as the LAST thing, then: sh $0"
    log_end || :; exit 1
    ;;
esac
