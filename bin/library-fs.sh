#!/usr/bin/env sh
# library-fs.sh (harbor#618) — a file's mtime, size, mode and owner on BSD and GNU stat, one spelling.
# Sourced, never run: it sets no shell option, and every function is safe under the caller's set -eu.
#
#   . "$HERE/library-fs.sh"
#   fs_mtime <file>   epoch seconds        fs_size <file>   bytes
#   fs_mode <file>    permission bits, octal (644)           fs_uid <file>    numeric owner
#   fs_sha256 < <file>   stdin's sha256 as bare hex, sha256sum else shasum (harbor#1392: one copy outside
#                        the floor library and the installers' deploy-install-lib.sh)
#   fs_session_key <path>   the harness's session-store key, <config>/projects/<key>/ (harbor#966)
#   fs_session_keys         the same for each path on stdin, one key per line
#
# fs_mode keeps the low three octal digits: GNU `%a` prints 4755 for a setuid file where BSD `%Lp` prints 755.
#
# Digits on stdout and exit 0, or NOTHING on stdout and exit 0 (missing, unreadable, no known stat), so
# `x="$(fs_mtime f)"` never aborts a set -e caller; the caller picks its own default for "empty".
#
# GNU first, in two separate captures. BSD rejects `stat -c` outright and prints nothing; GNU reads
# `stat -f` as --file-system and prints filesystem text, so BSD-first would let that text reach the
# caller's arithmetic. Each answer is kept only if it is all digits (lint posix.stat-fallback).
_fs_q() { # <gnu-format> <bsd-format> <file> <bad-char-class: 9 or 7>
  _fs_v="$(stat -c "$1" "$3" 2>/dev/null || true)"
  case "$_fs_v" in ''|*[!0-9]*) _fs_v="$(stat -f "$2" "$3" 2>/dev/null || true)" ;; esac
  case "$_fs_v" in ''|*[!0-9]*) return 0 ;; esac
  case "$4:$_fs_v" in 7:*[89]*) return 0 ;; esac
  case "$4:$_fs_v" in 7:????*) _fs_v="${_fs_v#"${_fs_v%???}"}" ;; esac
  printf '%s' "$_fs_v"
}
fs_mtime() { _fs_q %Y %m "$1" 9; }
fs_size()  { _fs_q %s %z "$1" 9; }
fs_mode()  { _fs_q %a %Lp "$1" 7; }
fs_uid()   { _fs_q %u %u "$1" 9; }
fs_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# The harness's own key (claude 2.1.317's bundle: k(e) = e.replace(/[^a-zA-Z0-9]/g, "-")), the one derivation every reader of
# <config>/projects/ uses (harbor#966): a `/`-only copy put every .worktrees/ tree under a key no session reads. Over 200
# characters the harness hashes the key; a caller that can meet such a path judges the length itself.
fs_session_keys() { LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }
fs_session_key() { printf '%s\n' "$1" | fs_session_keys; }
