#!/usr/bin/env sh
# library-clipboard.sh (harbor#1597, contracts/secret-intake.md) — read and empty the system clipboard on macOS, Wayland, X11 and WSL2,
# for the tools that take a credential from it without showing it: memory-log-token-save.sh and harbor access
# --value-clipboard. Never run: sourced; it sets no shell option, and every function is safe under the caller's set -eu.
#
#   clip_detect   set CLIP to mac | wl | xclip | xsel | wsl; return 1 when this box has no clipboard tool
#   clip_tools    the tools clip_detect looks for, for a refusal's words
#   clip_read     the clipboard on stdout, as it is (call clip_detect first)
#   clip_clear    empty the clipboard
#
# Lifted unchanged from memory-log-token-save.sh (harbor#431), where it was the only reader, when a second one came.

clip_detect() {
  if command -v pbpaste >/dev/null 2>&1; then CLIP=mac
  elif command -v wl-paste >/dev/null 2>&1; then CLIP=wl
  elif command -v xclip >/dev/null 2>&1; then CLIP=xclip
  elif command -v xsel >/dev/null 2>&1; then CLIP=xsel
  elif command -v powershell.exe >/dev/null 2>&1; then CLIP=wsl
  else CLIP=''; return 1
  fi
}
clip_tools() { printf 'pbpaste, wl-paste, xclip, xsel and powershell.exe (WSL2)'; }
clip_read() {
  case "${CLIP:-}" in
    mac) pbpaste ;; wl) wl-paste --no-newline ;; xclip) xclip -selection clipboard -o ;;
    xsel) xsel --clipboard --output ;; wsl) powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r' ;;
    *) return 1 ;;
  esac
}
clip_clear() {
  case "${CLIP:-}" in
    mac) pbcopy < /dev/null ;; wl) wl-copy --clear ;; xclip) xclip -selection clipboard -i < /dev/null ;;
    xsel) xsel --clipboard --clear ;; wsl) clip.exe < /dev/null ;;
    *) return 1 ;;
  esac
}
