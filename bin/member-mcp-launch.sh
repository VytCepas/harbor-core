#!/usr/bin/env sh
# member-mcp-launch.sh (harbor#1278, lane I; control member.connectors) — starts one MCP server with a colleague's key in ITS environment and nowhere else.
#   /bin/sh <managed root>/bin/member-mcp-launch.sh <ref> -- <server command...>
# Only Claude Code starts this, from <managed dir>/managed-mcp.json (root-written, composed from the verified policy by member-managed.sh --mcp-servers).
# An MCP server runs outside the Bash sandbox as a child of Claude Code, so the key never enters a process the agent starts; the agent calls the server's tools.
# It refuses unless ALL hold, each re-checked here and none read from a file the member can write:
#   1 the ref is a plain name, and not hub-* (the hub token)           2 <root>/connectors.json (root-owned, from the policy) lists this ref WITH exactly this command
#   3 the server's file and every folder above it are not writable by this user (else the agent could swap the server for one that sends the key away)
#   4 the store hands the key over (bin/secret run: the access register must name the ref; a sandboxed shell cannot read the store, so a hand run fails here)
# The server gets: PATH as given (the managed entry pins it), HOME from member.conf, USER, LANG, TMPDIR, and the one variable named by the entry. Working folder /.
# Test seams, honoured only when no harbor-member-mode sits beside this file: HARBOR_MEMBER_LAUNCH_TRUST_UNDER=<dir> skips check 3 for <dir> and above; HARBOR_MEMBER_LAUNCH_KEEP_ENV="A B" keeps those names (a stub store).
set -eu
CTL=member.connectors
refuse() { log_fail "$CTL: member-mcp-launch refused: $1"; log_nofix "docs/how-to/member-install.md, A colleague's API key"; log_end || :; exit 1; }

case "${1:-}" in -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
_h0="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"; . "$_h0/library-log.sh"; log_init member-mcp-launch; LOG_FD=2   # stdout is the MCP protocol
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)" || refuse "cannot find itself"
case "$HERE" in */bin) ROOT="${HERE%/bin}" ;; *) refuse "this file is not in a managed root's bin" ;; esac
MARKER=0; [ -f "$HERE/harbor-member-mode" ] && [ ! -L "$HERE/harbor-member-mode" ] && MARKER=1
command -v jq >/dev/null 2>&1 || refuse "jq is missing, and without it nothing can be checked"

# A shell the agent runs in carries CLAUDECODE; the managed entry's env -i does not. Trivial to unset, so this stops a mistake and is not the wall: the wall is the store (check 4).
[ -z "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ] || refuse "this is started by Claude Code from the managed MCP file, never by hand inside a Claude Code session"
[ $# -ge 3 ] && [ "$2" = "--" ] || refuse "usage: member-mcp-launch.sh <ref> -- <server command...>"
REF="$1"; shift 2
case "$REF" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789._-]*|[!abcdefghijklmnopqrstuvwxyz0123456789]*) refuse "'$REF' is not a name of a key" ;; esac
case "$REF" in hub-*) refuse "'$REF' is a name the company keeps for itself" ;; esac

CONF="$ROOT/connectors.json"
[ -f "$CONF" ] && [ ! -L "$CONF" ] || refuse "$CONF is missing: no connector is declared on this laptop"
CMDJ='[]'
for _a in "$@"; do CMDJ="$(printf '%s' "$CMDJ" | jq -c --arg a "$_a" '. + [$a]')" || refuse "cannot read the command"; done   # --args would read a leading - as an option
VAR="$(jq -r --arg r "$REF" --argjson c "$CMDJ" '[.[] | select(.ref == $r and .command == $c)][0].env // empty' "$CONF" 2>/dev/null)" || VAR=''
[ -n "$VAR" ] || refuse "no connector of this laptop's policy names '$REF' with this server command"
NAME="$(jq -r --arg r "$REF" --argjson c "$CMDJ" '[.[] | select(.ref == $r and .command == $c)][0].name // empty' "$CONF" 2>/dev/null)" || NAME=''
case "$NAME" in ''|*[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-]*) refuse "the connector name '$NAME' is not [A-Za-z0-9_-]" ;; esac
case "$VAR" in [ABCDEFGHIJKLMNOPQRSTUVWXYZ]*) ;; *) refuse "the variable '$VAR' is not NAME in capitals" ;; esac
case "$VAR" in *[!ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]*|PATH|HOME|SHELL|IFS|USER|LOGNAME|PWD|TMPDIR|LANG|ENV|BASH_ENV|CDPATH|LD_*|DYLD_*|PYTHON*|NODE_*|PERL*|RUBY*|GIT_*|HARBOR_*|CLAUDE*|SSL_*|CURL_*|*PROXY*) refuse "the variable '$VAR' steers a program, so a key cannot go in it" ;; esac

# 3: no part of the server's path may be one this user can change. Symlinks are followed first, so a link cannot hide a writable target.
resolve() { # <abs path> -> its target with no link in it, or nothing
  _p="$1"; _n=0
  while [ -L "$_p" ] && [ "$_n" -lt 10 ]; do
    _l="$(readlink "$_p")" || return 1
    case "$_l" in /*) _p="$_l" ;; *) _p="${_p%/*}/$_l" ;; esac; _n=$((_n + 1))
  done
  [ "$_n" -lt 10 ] || return 1
  _d="$(CDPATH='' cd -P -- "${_p%/*}" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s' "${_d%/}" "${_p##*/}"
}
TRUST=''; KEEP=''; BWSEAM=''; TREES='/usr /etc'
[ "$MARKER" = 0 ] && { TRUST="${HARBOR_MEMBER_LAUNCH_TRUST_UNDER:-}"; KEEP="${HARBOR_MEMBER_LAUNCH_KEEP_ENV:-}"; BWSEAM="${HARBOR_MEMBER_LAUNCH_BWRAP:-}"; TREES="${HARBOR_MEMBER_LAUNCH_TREES:-$TREES}"; }
walkp() { # <abs path, as it is written>: 0 when it and every folder from / down to it are not writable here
  [ -e "$1" ] || [ -L "$1" ] || return 1
  _q=''; _rest="${1#/}"
  [ ! -w / ] || return 1
  while [ -n "$_rest" ]; do
    _seg="${_rest%%/*}"; case "$_rest" in */*) _rest="${_rest#*/}" ;; *) _rest='' ;; esac
    _q="$_q/$_seg"
    if [ -n "$TRUST" ] && { [ "$_q" = "$TRUST" ] || case "$TRUST" in "$_q"/*) true ;; *) false ;; esac; }; then continue; fi
    [ ! -w "$_q" ] || return 1
  done
  return 0
}
fixed() { # <abs path>: 0 when neither its target nor a folder above the target is writable here
  _r="$(resolve "$1")" || return 1
  [ -e "$_r" ] || return 1
  walkp "$_r"
}
fixedchain() { # <abs path>: fixed as written (every folder from / down), at EVERY link hop, and resolved. A link in a writable folder is refused though its target is root's: it can be swapped
  _cp="$1"; _ch=0
  while :; do
    walkp "$_cp" || return 1
    [ -L "$_cp" ] || break
    _cl="$(readlink "$_cp")" || return 1
    case "$_cl" in /*) _cp="$_cl" ;; *) _cp="${_cp%/*}/$_cl" ;; esac
    _ch=$((_ch + 1)); [ "$_ch" -lt 10 ] || return 1
  done
  fixed "$1"
}
nodots() { case "/$1/" in */../*|*/./*) return 1 ;; esac; return 0; }
# The command is a CLOSED GRAMMAR, the same one hub-format.sh and the composer apply to the signed policy. Each connector has a root-owned folder <base>/<name>
# (base /opt/company-mcp). command[0] is a file inside it, or bun, node or python3 (wherever it sits), and then:
#   bun   first --no-install, then an ENTRY FILE inside the folder     node, python3   the ENTRY FILE inside the folder
# Every later word is (a) an absolute path that, links followed, is inside the folder, (b) a plain token: no "/", not starting with "." or "-", or (c) a flag
# --name or --name=value whose value has no "/" and does not start with ".". The interpreter flags (-e -m -c -r -p --require --import --preload --eval --print),
# a shell, bunx and deno, and the bun subcommands x run install add pm create are refused. A relative word is resolved against / (the launcher's cwd), and one that
# names something that exists there is refused. The interpreter rules key on the resolved name as well as the written one, so a link named "server" that leads to bun
# is still bun. Anything else is refused: it could load code from a place the agent can write (~/.cache/uv, ~/.bun, node_modules, a file under its home).
for _a in "$@"; do
  case "$_a" in -e|-m|-c|-r|-p|--require|--import|--preload|--eval|--print|--eval=*|--require=*|--import=*|--preload=*|--print=*) refuse "the interpreter flag $_a is not allowed in a connector command" ;; esac
  case "$_a" in *'${'*) refuse "a connector command may not hold a \${ expansion: $_a" ;; esac
done
BASE=/opt/company-mcp; [ "$MARKER" = 0 ] && [ -n "${HARBOR_MEMBER_LAUNCH_ROOT:-}" ] && BASE="$HARBOR_MEMBER_LAUNCH_ROOT"
FDIR="$BASE/$NAME"
fixedchain "$FDIR" || refuse "$FDIR is missing, or it or a folder above it is writable by this user: a connector's files live in a root-owned folder of their own"
FR="$(resolve "$FDIR")" || refuse "$FDIR does not resolve"
inside() { _ir="$(resolve "$1")" || return 1; case "$_ir" in "$FR"/*) return 0 ;; esac; return 1; }
case "$1" in /*) ;; *) refuse "$1 is not an absolute path: command[0] is a file in $FDIR or bun, node or python3" ;; esac
nodots "$1" || refuse "$1 holds a . or .. segment"
SYSDIRS="/usr/bin /usr/local/bin /bin"; [ "$MARKER" = 0 ] && [ -n "${HARBOR_MEMBER_LAUNCH_SYSDIRS:-}" ] && SYSDIRS="$HARBOR_MEMBER_LAUNCH_SYSDIRS"
_r0="$(resolve "$1")" || refuse "$1 does not resolve to a file"
_kind=''; _ni=0
for _nm in "${1##*/}" "${_r0##*/}"; do
  case "$_nm" in
    sh|bash|dash|zsh|ksh|ash|fish|csh|tcsh|bunx|deno) refuse "$_nm starts programs of the caller's choosing: no shell, bunx or deno may start a connector server" ;;
    bun) _kind=bun; _ni=$((_ni + 1)) ;;
    node|nodejs|python|python3|python3.[0-9]*) [ "$_kind" = bun ] || _kind=other; _ni=$((_ni + 1)) ;;
  esac
done
if [ -n "$_kind" ]; then
  [ "$_ni" = 2 ] || refuse "${1##*/} resolves to ${_r0##*/}: an interpreter's written name and its resolved name must both name an interpreter"
  # An interpreter is judged AS WRITTEN: in /usr/bin, /usr/local/bin or /bin, or inside the connector's folder. A link elsewhere (~/venv/bin/python3) is refused though its target is root's.
  _okd=0
  for _sd in $SYSDIRS; do [ "${1%/*}" = "$_sd" ] && _okd=1; done
  case "$1" in "$FDIR"/*) _okd=1 ;; esac
  [ "$_okd" = 1 ] || refuse "$1 is not written as a file in /usr/bin, /usr/local/bin, /bin or $FDIR: an interpreter sits only in the root's own places"
  fixedchain "$1" || refuse "$1, a folder above it or a link on the way is writable by this user or missing: the interpreter must be the root's own"
  # A python that finds a pyvenv.cfg beside it (or one folder up) loads that venv's site-packages, and a .pth file there runs code: only an admin venv inside the connector's folder is allowed.
  case "${1##*/}${_r0##*/}" in
    *python*) for _pv in "${1%/*}/pyvenv.cfg" "${1%/*}/../pyvenv.cfg" "${_r0%/*}/pyvenv.cfg" "${_r0%/*}/../pyvenv.cfg"; do
        if [ -e "$_pv" ]; then
          case "$1" in "$FDIR"/*) ;; *) refuse "a pyvenv.cfg sits beside the interpreter ($_pv): a venv is allowed only inside $FDIR" ;; esac
          # the venv's base python is where python loads its standard library from: a member's own python (uv, pyenv) there would run code
          _hm="$(sed -n 's/^home[[:space:]]*=[[:space:]]*//p' "$_pv" | head -n 1)"; _hmok=0
          for _sd in $SYSDIRS; do [ "$_hm" = "$_sd" ] && _hmok=1; done
          [ "$_hmok" = 1 ] || refuse "$_pv names home = '$_hm': a venv's base python is in /usr/bin, /usr/local/bin or /bin"
          fixedchain "$_hm" || refuse "$_pv names home = $_hm, which or a folder above it is writable by this user"
        fi
      done ;;
  esac
  _entry="${2:-}"
  if [ "$_kind" = bun ]; then
    [ "${2:-}" = --no-install ] || refuse "bun must be given --no-install before the entry file, or it fetches a missing package into a cache the agent can write"
    _entry="${3:-}"
  fi
  case "$_entry" in /*) inside "$_entry" || refuse "the entry file $_entry is not inside $FDIR" ;; *) refuse "name the entry file, an absolute path inside $FDIR, right after the interpreter" ;; esac
else
  inside "$1" || refuse "$1 is not a file inside $FDIR, and not bun, node or python3: nothing else may start a connector server"
fi
exists_at_root() { [ -e "/$1" ] || [ -L "/$1" ]; }
_n=0
for _w in "$@"; do
  _n=$((_n + 1))
  [ "$_n" -gt 1 ] || [ -z "$_kind" ] || continue   # the interpreter itself was judged above
  case "$_w" in
    /*) nodots "$_w" || refuse "$_w holds a . or .. segment"
        inside "$_w" || refuse "$_w is an absolute path outside $FDIR: a connector command may name only files of its own folder"
        fixedchain "$_w" || refuse "$_w, or a folder above it, is writable by this user or missing: an agent could swap it" ;;
    --*=*) _fn="${_w%%=*}"; _fv="${_w#*=}"
        case "${_fn#--}" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9_-]*) refuse "the flag $_fn is not of the form --name" ;; esac
        case "$_fv" in */*|.*) refuse "the value of $_fn names a path: a flag value may not hold a slash or start with a dot" ;; esac
        ! exists_at_root "$_fv" || refuse "the value of $_fn names /$_fv, which exists: a relative word resolves against /" ;;
    --*) case "${_w#--}" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9_-]*) refuse "the flag $_w is not of the form --name" ;; esac ;;
    -*) refuse "the flag $_w is not allowed: a flag is --name or --name=value" ;;
    */*|.*) refuse "$_w is a relative path: a word is an absolute path in $FDIR, a plain token, or a --flag" ;;
    *) ! exists_at_root "$_w" || refuse "$_w names /$_w, which exists: a relative word resolves against /, which the launcher runs in"
        if [ "$_kind" = bun ]; then
          case "$_w" in x|run|install|add|pm|create) refuse "bun $_w is a package command: refused" ;; esac
        fi ;;
  esac
done

# The server's environment: nothing inherited but these. Names are unset here, so no value rides in an argument list.
for _v in $(env | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort -u); do
  case "$_v" in PATH|LANG|LC_ALL|LC_CTYPE|TMPDIR) ;; *) case " $KEEP " in *" $_v "*) continue ;; esac; unset "$_v" 2>/dev/null || : ;; esac
done
HOME_CONF="$(sed -n 's/^home=//p' "$ROOT/member.conf" 2>/dev/null | head -n 1)"
case "$HOME_CONF" in /*) ;; *) refuse "$ROOT/member.conf names no absolute home" ;; esac
export HOME="$HOME_CONF" USER="$(id -un)"
export PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"
cd /
# THE JAIL. Everything above judges paths; this makes the class of path leaks impossible: the server runs in a filesystem view that holds nothing this user can write,
# so a planted stdlib (a venv home=), NODE_PATH, sys.path, a plugin folder, ~/.cache or /tmp are not there to be read (ENOENT), whatever the command names. The view is an
# ALLOWLIST of the root's own trees: /usr, /bin /sbin /lib* (links into /usr or the real folders), /etc, the connector's folder (read-only), a private /proc (own pid
# namespace, so /proc/<pid>/environ of anything else is gone), /dev, and an empty tmpfs /tmp. Nothing else exists: no /home, /root, /mnt, /run/user, /var, /dev/shm.
# The network is shared (the server needs it). If the jail cannot start the server does not start: refuse, never run bare.
case "$(uname -s)" in
  Linux) JK=bwrap ;;
  Darwin) JK=seatbelt ;;
  *) JK=none ;;
esac
BW=''
if [ -n "$BWSEAM" ]; then JK=bwrap; BW="$BWSEAM"; fi
case "$JK" in
  bwrap)
    if [ -z "$BW" ]; then for _b in /usr/bin/bwrap /bin/bwrap; do [ -x "$_b" ] && { BW="$_b"; break; }; done; fi
    [ -n "$BW" ] && [ -x "$BW" ] || refuse "bubblewrap (bwrap) is not installed: a connector server runs only inside its jail, and without one it does not start"
    fixed "$BW" || refuse "$BW, or a folder above it, is writable by this user: the jail program must be the root's own"
    # Nothing in or UNDER a bound tree may be writable by this user: a /usr/local handed to the user (npm -g, Homebrew, pip) would put their code inside the view. GNU find tests real access
    # (-writable; find exits non-zero on a folder it may not read, which set -e must not turn into a silent exit); where find has no such test (the suites on macOS) owner or other write bits stand in. /etc/claude-code is masked below, so it is not looked at.
    _wf=''; ! find / -maxdepth 0 -writable > /dev/null 2>&1 || _wf=writable
    for _t in $TREES "$FR"; do
      if [ -n "$_wf" ]; then _bad="$(find "$_t" -xdev -path /etc/claude-code -prune -o -writable ! -type l -print -quit 2> /dev/null)" || :
      else _bad="$(find "$_t" -xdev -path /etc/claude-code -prune -o ! -type l \( -perm -0002 -o \( -user "$(id -u)" -perm -0200 \) \) -print -quit 2> /dev/null)" || :; fi
      [ -z "$_bad" ] || refuse "$_bad is writable by this user and lies under $_t, which the jail's view binds in: code there would run with the key"
    done
    # the arguments are built last-first: the server's command, then the jail's flags in front of it
    set -- /usr/bin/env HOME=/ XDG_CONFIG_HOME=/ XDG_CACHE_HOME=/ XDG_DATA_HOME=/ XDG_STATE_HOME=/ "$@"
    set -- --ro-bind "$FR" "$FDIR" --chdir / -- "$@"
    for _d in bin sbin lib lib32 lib64 libx32; do
      if [ -L "/$_d" ]; then set -- --symlink "$(readlink "/$_d")" "/$_d" "$@"
      elif [ -d "/$_d" ] && [ ! -w "/$_d" ]; then set -- --ro-bind "/$_d" "/$_d" "$@"; fi
    done
    # /etc/claude-code holds the member's own writable log (the dispatcher writes it as the member) and the managed floor, which a server has no use for: masked, so nothing member-writable is in the view
    [ ! -d /etc/claude-code ] || set -- --tmpfs /etc/claude-code "$@"
    set -- --unshare-pid --unshare-ipc --die-with-parent --new-session --cap-drop ALL --proc /proc --dev /dev --tmpfs /tmp --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind-try /run/systemd/resolve /run/systemd/resolve "$@"
    set -- "$BW" "$@" ;;
  seatbelt)
    # macOS: Seatbelt (sandbox-exec). A deny-list of the places a member can write, weaker than the Linux view and not exercised by the suites.
    SBX=/usr/bin/sandbox-exec
    [ -x "$SBX" ] || refuse "sandbox-exec is missing: a connector server runs only inside its jail"
    _prof="(version 1)(allow default)(deny file-read* file-write* (subpath \"/Users\") (subpath \"/Volumes\") (subpath \"/private/tmp\") (subpath \"/private/var/tmp\") (subpath \"/private/var/folders\") (subpath \"$HOME_CONF\"))(allow file-read* (subpath \"$FR\"))"
    set -- "$SBX" -p "$_prof" /usr/bin/env HOME=/ XDG_CONFIG_HOME=/ XDG_CACHE_HOME=/ XDG_DATA_HOME=/ XDG_STATE_HOME=/ "$@" ;;
  *) refuse "no jail is known for this system ($(uname -s)): a connector server does not start without one" ;;
esac
exec sh "$HERE/secret" run "$REF" "$VAR" -- "$@"
