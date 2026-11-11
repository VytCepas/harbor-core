#!/usr/bin/env sh
# library-hub.sh (harbor#1278) — shared helpers for the hub and member formats. Sourced, never run, so it sets no shell option. Format: contracts/hub.md.
# POSIX sh and jq. Nothing here decides a tier or an approval: it only names paths and builds the canonical call.

hub_role() { printf '%s' "${HARBOR_MEMBER_ROLE:-standalone}"; }
hub_is_member() { [ "${HARBOR_MEMBER_ROLE:-standalone}" = member ]; }

hub_state_dir() { printf '%s/harbor/hub' "${XDG_STATE_HOME:-$HOME/.local/state}"; }

# hub_marker: 0 iff this script runs from a managed root. floor_member_mode's test: a file only an admin can write, never env. HUB_HERE is the script's
# folder, as every floor script finds its own: `.` when $0 has no slash, so `sh member-support.sh` from inside the root reads member.conf too (N9).
hub_marker() {
  case "$0" in */*) HUB_HERE="${0%/*}" ;; *) HUB_HERE=. ;; esac
  [ -f "$HUB_HERE/harbor-member-mode" ] && [ ! -L "$HUB_HERE/harbor-member-mode" ]
}

# hub_facts (harbor#1278): on a marker box role, hub, login and home come from <managed root>/member.conf, because a launch environment can beat settings `env`.
# Short of three valid lines it is a fault: role `fault`, exit 1, so set -e stops a hook and hub_is_member says no. So is a key given twice, which readers
# taking the first or the last line would read apart. Off the marker it does nothing.
hub_facts() {
  hub_marker || return 0
  _hfc="$HUB_HERE/../member.conf"; _hfr=''; _hfl=''; _hfd=''
  unset XDG_STATE_HOME HARBOR_HUB_REPO HARBOR_MEMBER_LOGIN
  HARBOR_MEMBER_ROLE=fault; export HARBOR_MEMBER_ROLE
  { [ -f "$_hfc" ] && [ ! -L "$_hfc" ] && [ -r "$_hfc" ]; } || return 1
  _hfn=''
  while IFS= read -r _hfline || [ -n "$_hfline" ]; do
    case "$_hfline" in
      hub=*) _hfn="${_hfn}h"; _hfr="${_hfline#hub=}" ;;
      login=*) _hfn="${_hfn}l"; _hfl="${_hfline#login=}" ;;
      home=*) _hfn="${_hfn}d"; _hfd="${_hfline#home=}" ;;
    esac
  done < "$_hfc"
  case "$_hfn" in *h*h*|*l*l*|*d*d*) return 1 ;; esac
  case "$_hfr" in ''|/*|*/|*/*/*|*..*|*[!A-Za-z0-9._/-]*) return 1 ;; */*) ;; *) return 1 ;; esac
  case "$_hfl" in ''|-*|*[!A-Za-z0-9-]*) return 1 ;; esac
  case "$_hfd" in */) return 1 ;; /*) ;; *) return 1 ;; esac
  HARBOR_MEMBER_ROLE=member; HARBOR_HUB_REPO="$_hfr"; HARBOR_MEMBER_LOGIN="$_hfl"; HOME="$_hfd"
  export HARBOR_HUB_REPO HARBOR_MEMBER_LOGIN HOME
}

# hub_net_env (harbor#1278): on a marker box, before any network call. Every variable that steers git, curl or TLS goes, then the proxy and CA names come back
# from the root-owned managed settings `env` alone: env can be beaten by a launch environment, the file can't. A CA file the member can write is dropped.
HUB_NET_KEEP='HTTPS_PROXY HTTP_PROXY ALL_PROXY NO_PROXY https_proxy http_proxy all_proxy no_proxy SSL_CERT_FILE SSL_CERT_DIR CURL_CA_BUNDLE GIT_SSL_CAINFO'
hub_net_env() {
  hub_marker || return 0
  # Pinned here too: at source time PATH is still whoever started the script.
  for _hnv in $(PATH=/usr/bin:/bin env | PATH=/usr/bin:/bin sed -n -e 's/^\(GIT_[A-Za-z0-9_]*\)=.*/\1/p' -e 's/^\([A-Za-z0-9_]*_[Pp][Rr][Oo][Xx][Yy]\)=.*/\1/p'); do unset "$_hnv"; done
  # shellcheck disable=SC2086 # a fixed list of names
  unset $HUB_NET_KEEP CURL_HOME CURL_SSL_BACKEND SSLKEYLOGFILE REQUESTS_CA_BUNDLE NODE_EXTRA_CA_CERTS OPENSSL_CONF OPENSSL_ENGINES NETRC SSH_ASKPASS \
    XDG_CONFIG_HOME XDG_DATA_HOME 2>/dev/null || :
  _hns="$HUB_HERE/../../managed-settings.json"   # W4: one above the root, as member-integrity.sh reads it
  { [ -f "$_hns" ] && [ ! -L "$_hns" ] && [ -r "$_hns" ]; } || return 0
  for _hnk in $HUB_NET_KEEP; do
    _hnx="$(PATH=/usr/bin:/bin jq -r --arg k "$_hnk" '.env[$k] // empty | strings' "$_hns" 2>/dev/null)" || _hnx=''
    case "$_hnx" in ''|*[[:cntrl:]]*) continue ;; esac
    case "$_hnk" in SSL_CERT_FILE|SSL_CERT_DIR|CURL_CA_BUNDLE|GIT_SSL_CAINFO) case "$_hnx" in /*) ;; *) continue ;; esac; [ -e "$_hnx" ] && [ ! -w "$_hnx" ] || continue ;; esac
    eval "$_hnk=\$_hnx"; export "${_hnk?}"
  done
}

# hub_bounded <seconds> <command...>: runs it, and past the bound ends it and what it started; 124 then. No timeout(1) on BSD. A hung credential store or hub
# must not hold a hook: curl's own --max-time never sees a hang that is not curl's (harbor#1278).
hub_kill_tree() { for _hk in $(pgrep -P "$1" 2>/dev/null); do hub_kill_tree "$_hk"; done; kill "$1" 2>/dev/null || :; }
hub_bounded() {
  _hbs="$1"; shift
  "$@" & _hbp=$!
  ( sleep "$_hbs"; hub_kill_tree "$_hbp" ) > /dev/null 2>&1 < /dev/null & _hbw=$!
  _hbrc=0; wait "$_hbp" 2>/dev/null || _hbrc=$?
  kill "$_hbw" 2>/dev/null || :
  wait "$_hbw" 2>/dev/null || :
  [ "$_hbrc" -lt 128 ] || return 124   # ended by the bound: no hub command exits above 4
  return "$_hbrc"
}

# hub_sha256: stdin to lowercase hex. sha256sum on Linux, shasum on macOS.
hub_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# hub_salt: this laptop's salt, made once. Mode 600: the id must not be guessable from a short command.
hub_salt() {
  _hs="$(hub_state_dir)/salt"
  if [ ! -s "$_hs" ]; then
    mkdir -p "${_hs%/*}" || return 1
    (umask 077; od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$_hs") || return 1
  fi
  cat "$_hs"
}

# hub_canon <payload-json> <member>: the fields that matter for this tool. description and timeout vary between identical
# retries, so they stay out, or a re-emitted call would miss its approval.
hub_canon() {
  printf '%s' "$1" | jq -cS --arg m "$2" '
    .tool_name as $t | (.tool_input // {}) as $i |
    {t: $t, c: (.cwd // ""), m: $m, i: (
      if   $t == "Bash" or $t == "Monitor" then {command: $i.command}
      elif $t == "Write" then {file_path: $i.file_path, content: $i.content}
      elif $t == "Edit" then {file_path: $i.file_path, old_string: $i.old_string, new_string: $i.new_string, replace_all: ($i.replace_all // false)}
      elif $t == "MultiEdit" then {file_path: $i.file_path, edits: $i.edits}
      elif $t == "NotebookEdit" then {notebook_path: $i.notebook_path, cell_id: $i.cell_id, edit_mode: $i.edit_mode, new_source: $i.new_source}
      elif $t == "WebFetch" then {url: $i.url}
      elif $t == "WebSearch" then {query: $i.query}
      elif $t == "Task" or $t == "Agent" then {subagent_type: $i.subagent_type, prompt: $i.prompt}
      else $i end)}'
}

# hub_request_id <canonical> <salt>: r- and 16 hex (contracts/hub.md, "The request id").
hub_request_id() {
  _hd="$(printf '%s%s' "$2" "$1" | hub_sha256)" || return 1
  [ -n "$_hd" ] || return 1
  printf 'r-%s' "$(printf '%s' "$_hd" | cut -c1-16)"
}

# hub_env_clean (harbor#1278, F9): the first act of every managed hook entry, because a settings `env` block reaches them all: a member script keeps only the four
# managed names and a pinned PATH, then hub_facts overwrites three of them on a marker box. Exit 1 is hub_facts' fault, with the env already clean.
# Only system directories: /opt/homebrew is the user's own on most Macs, so a planted jq there would read every payload.
hub_env_clean() {
  PATH=/usr/bin:/bin:/usr/sbin:/sbin; export PATH
  for _hv in $(env | sed -n -e 's/^\(HARBOR_[A-Za-z0-9_]*\)=.*/\1/p' -e 's/^\(FLOOR_[A-Za-z0-9_]*\)=.*/\1/p'); do
    case "$_hv" in HARBOR_MEMBER_ROLE|HARBOR_HUB_REPO|HARBOR_MEMBER_LOGIN|HARBOR_MEMBER_ROOT) ;; *) unset "$_hv" ;; esac
  done
  unset BASH_ENV ENV CDPATH LD_PRELOAD LD_LIBRARY_PATH DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH JQ_LIBRARY_PATH 2>/dev/null || :
  hub_net_env
  hub_facts
}

# At source time too, so hub-sync.sh, hub-events.sh, hub-board.sh and hub.sh read the file's facts and network env whoever started them.
hub_net_env
hub_facts || :
