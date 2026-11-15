#!/usr/bin/env sh
# member-support-guard.sh (harbor#1278) — is this tool call starting or reaching a support session? An agent never may. contracts/hub.md, "Remote support".
#   <hook json> | sh member-support-guard.sh     one record line for member-dispatch.sh when it is; nothing when it isn't. Exit 0 either way, non-zero is a fault
#
# A named command is matched in what will actually run: quoted arguments are dropped and interpreters opened by floor_bash_targets, so
# `git commit -m "upterm"` isn't a session and `sh -c 'upterm host'` is. Reading about support stays free: a segment led by a plain reader passes.
# This reads command text, so a name built at run time gets past it. The relay's deniedDomains row and member-support.sh's own refusals sit behind it.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
. "$HERE/library-hub.sh"
log_init member-support-guard
LOG_FD=2
case "${1:-}" in
  --help|-h) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac
hub_env_clean
. "$HERE/library-admission.sh"
JQ="$FLOOR_JQ"

payload="$(cat)"
command_text="$(printf '%s' "$payload" | "$JQ" -r 'if (.tool_input.command | type) == "string" then .tool_input.command else "" end')"
[ -n "$command_text" ] || exit 0

# `up\term` and `up''term` are the same word to a shell, so they are read as it reads them. The raw text goes in too, marked: a terminal
# wrapper takes its command as a quoted argument, which the normaliser drops, and a terminal is what member-support.sh insists on.
{ floor_bash_targets "$command_text"; printf '\001%s\n' "$(printf '%s' "$command_text" | tr '\n' ' ')"; } | LC_ALL=C tr 'A-Z' 'a-z' | LC_ALL=C tr -d "\\\\'\"" | awk '
  BEGIN {
    n = split("cat,grep,egrep,fgrep,rg,head,tail,less,more,ls,wc,file,stat,which,man", r, ",")
    for (i = 1; i <= n; i++) reader[r[i]] = 1
  }
  function named(s) {
    if (s ~ /(^|[^a-z0-9_.-])(upterm|uptermd|member-support|member-support\.sh|hub-support|hub-support\.sh)([^a-z0-9_.-]|$)/) return 1
    if (s ~ /(^|[^a-z0-9_.-])(harbor|hub\.sh)[ \t]+(hub[ \t]+)?support([^a-z0-9_-]|$)/) return 1
    return 0
  }
  /^\001/ { if ($0 ~ /(^|[^a-z0-9_.-])(script|expect|unbuffer|tmux|screen|socat)[ \t]/ && named($0)) hit = 1; next }
  {
    m = split($0, seg, /[;|&()`\n]/)
    for (i = 1; i <= m; i++) {
      s = seg[i]; sub(/^[ \t]+/, "", s)
      if (!named(s)) continue
      split(s, w, /[ \t]+/); f = w[1]; sub(/.*\//, "", f)
      if (!(f in reader)) { hit = 1 }
    }
  }
  END { if (hit) printf "rule\tbash\t-\tadmission.member-support\n" }'
