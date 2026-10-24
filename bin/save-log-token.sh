#!/usr/bin/env sh
# save-log-token.sh (harbor#431) — put the helm-log token on disk without ever
# showing it, and without leaving it on the clipboard.
#
#   sh save-log-token.sh          # reads the clipboard, writes the token file
#   sh save-log-token.sh --help
#
# CAPTURED FROM THE BOX, NOT WRITTEN HERE. This existed only as an installed file
# in the live floor: no commit, no branch, no working tree of this repository held
# it, and it had been handling a GitHub PAT that way for an unknown length of time.
# install-drift.sh (harbor#431) is what named it — `unsourced save-log-token.sh
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
# WHY `umask 177` AND NOT `chmod` AFTER. chmod leaves a window in which the file
# exists at the default mode with the token already in it. The umask closes that
# window by construction: the file is created 0600 or not at all. It is set before
# the redirect for the same reason, not after.
set -eu

case "${1:-}" in
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') ;;
  *) printf 'save-log-token: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

# Its lines are log-lib's (CONTRACTS/logging.md), installed beside it in the config dir's bin/.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
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

DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.helm-log-token"

# `|| true` ON THE SUBSTITUTION, not on a later line. Under `set -e` a bare
# `T="$(clip_read)"` ABORTS on a non-zero read, so a fallback written underneath
# it is dead code that never runs — measured trap, and the reason the guard below
# is reachable at all.
T="$(clip_read 2>/dev/null || true)"

case "$T" in
  github_pat_*|ghp_*)
    umask 177
    printf %s "$T" > "$DEST"
    clip_clear 2>/dev/null || true
    # LENGTH, NEVER THE VALUE. Enough to tell a truncated paste from a whole one.
    log_ok "token saved (${#T} chars, clipboard cleared)"
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
