#!/usr/bin/env sh
# drift-wall.sh (harbor#1442, #1440) — the check drift.wall: does each agent surface hold the main-files invariant (no
# change to the folders in contracts/main-folders.txt)? One row per surface: confined Bash, retried Bash, Edit/Write, each
# local MCP server, hooks, launchd jobs. Each row reads `holds`, `does not hold` or `not probed`, with how it was judged.
#   sh drift-wall.sh              exit 0 every surface holds (an exempt one is a recorded decision), 1 one does not, 3 not judged
#   sh drift-wall.sh --state      the same, plus one word on stdout: holds | does-not-hold | unchecked, and no receipt
#   sh drift-wall.sh --mcp        print the local MCP server inventory (name, source, command), judge nothing
#   sh drift-wall.sh --probe      also write one canary per main folder through the surfaces HARBOR_DRIFT_WALL_RUNNER can drive
# By default it is read-only and judges from the installed config (how=config): the managed sandbox block and permissions.deny,
# the user settings' hook commands, the MCP configs, and drift-launchd-wall.sh. A config verdict is not a probe, and the row says so.
# --probe is the probe: HARBOR_DRIFT_WALL_RUNNER names a program that is run as `<runner> <surface> <canary path>` once per
# main folder, with surface bash-confined, bash-retried or edit-write. It must try to create that file THROUGH the surface
# (a headless Claude session with that tool) and exit 0 or 1; exit 2 means the surface cannot be driven, and the row says not
# probed. The verdict reads the file, not the exit code: a canary on disk is `does not hold`, and it is removed. Adversarial
# probing is operator-run on this box, so no runner ships; a refusal here is a refusal to relay, not to route around.
# A refused canary cannot raise a config verdict (a refusal may be a prompt, not the wall); a landed one always lowers it.
# An unwrapped MCP server with a row in contracts/confinement-mcp.tsv reads `does not hold (exempt: <reason>)` and is not red.
# Every finding line carries [check:drift.wall]; the receipt goes to log_receipt's dir (docs/reference/checks.md).
# HARBOR_MANAGED_SETTINGS, HARBOR_DRIFT_WALL_USER_SETTINGS and HARBOR_DRIFT_WALL_CLAUDE_JSON move the three files read (tests).
set -u
case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;; esac
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
. "$HERE/library-log.sh"
log_init drift-wall
STATE=0; MODE=judge; PROBE=0
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
case "${1:-}" in
  --state) STATE=1; LOG_FD=2 ;;
  --mcp) MODE=mcp; LOG_FD=2 ;;
  --probe) PROBE=1 ;;
  '') ;;
  *) log_fail "unknown argument $1"; log_fix "sh $0 --help"; exit 2 ;;
esac
[ "$#" -le 1 ] || { log_fail "one argument at most"; log_fix "sh $0 --help"; exit 2; }
ID=drift.wall; P="[check:$ID]"
CORE="$HERE/../contracts"
if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then MF="$HARBOR_MANAGED_SETTINGS"
elif [ "$(uname -s)" = Darwin ]; then MF='/Library/Application Support/ClaudeCode/managed-settings.json'
else MF=/etc/claude-code/managed-settings.json; fi
US="${HARBOR_DRIFT_WALL_USER_SETTINGS:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json}"
CJ="${HARBOR_DRIFT_WALL_CLAUDE_JSON:-$HOME/.claude.json}"

finish() { # <receipt status> <state word> <exit> [subject...]
  _fs="$1"; _fw="$2"; _fx="$3"; shift 3
  [ "$STATE" = 1 ] || log_receipt "$(receipt_dir)" "$ID" "$_fs" "$@" || log_warn "$P no receipt written to $(receipt_dir)"
  [ "$STATE" = 0 ] || printf '%s\n' "$_fw"
  log_end || :
  exit "$_fx"
}
command -v jq >/dev/null 2>&1 || { log_warn "$P unchecked: jq is required"; log_fix "$(pkg_hint jq)"; finish stood-down unchecked 3; }

T="$(mktemp -d "${TMPDIR:-/tmp}/drift-wall.XXXXXX")" || { log_warn "$P unchecked: mktemp failed"; log_fix "set TMPDIR to a writable dir"; exit 3; }
trap 'rm -rf "$T"' EXIT INT TERM

# ── the local MCP inventory: user config, every project entry in it, each governed repo's .mcp.json ──
# name TAB source TAB command TAB first argument; stdio servers only (a remote server runs elsewhere)
JQ_SERVERS='(.mcpServers // .) | if type == "object" then to_entries[] else empty end
  | select(.value | type == "object") | select((.value.type // "stdio") == "stdio") | select(.value.command != null)
  | [.key, $src, .value.command, ((.value.args // [])[0] // "" | tostring)] | @tsv'
mcp_inventory() {
  : > "$T/inv"; INV_BAD=""
  if [ -f "$CJ" ]; then
    jq -r --arg src "user config" '{mcpServers: (.mcpServers // {})} | '"$JQ_SERVERS" "$CJ" >> "$T/inv" 2>/dev/null || INV_BAD="$CJ is not readable JSON"
    jq -r '(.projects // {}) | to_entries[] | .key as $p | .value | {mcpServers: (.mcpServers // {})} | [., $p] | @json' "$CJ" 2>/dev/null \
      | while IFS= read -r _l; do
          printf '%s' "$_l" | jq -r --arg src "project entry" '.[0] | '"$JQ_SERVERS" 2>/dev/null
        done >> "$T/inv"
  fi
  sh "$HERE/scope-roots.sh" --repos 2>/dev/null | while IFS="$(printf '\t')" read -r _id _path _rest; do
    [ -f "$_path/.mcp.json" ] || continue
    jq -r --arg src "repo $_id" "$JQ_SERVERS" "$_path/.mcp.json" 2>/dev/null
  done >> "$T/inv"
  sort -u "$T/inv" > "$T/inv.s"
}
if [ "$MODE" = mcp ]; then
  mcp_inventory
  [ -z "$INV_BAD" ] || { log_warn "$P $INV_BAD"; log_fix "inspect $CJ"; }
  cat "$T/inv.s"
  log_end || :; exit 0
fi

# ── rows ──
NH=0; NP=0; NX=0; SUBJ=""
holds() { log_ok "$P $1: holds ($2) — $3"; }
nothold() { # <surface> <how> <detail>
  NH=$((NH + 1)); SUBJ="$SUBJ
$1"
  log_fail "$P $1: does not hold ($2) — $3"; log_fix "${4:-$FIXHINT}"
}
exempted() { NX=$((NX + 1)); log_note "$P $1: does not hold ($2) — $3; exempt: $4"; }
notprobed() { NP=$((NP + 1)); log_warn "$P $1: not probed — $2"; log_fix "${3:-$FIXHINT}"; }
FIXHINT="sh $HERE/drift-wall.sh --help"

# ── the installed managed file ──
MJ="$T/managed.json"; MOK=0; MNOTE=""
if [ ! -f "$MF" ]; then MNOTE="no managed settings file at $MF"
elif jq -e 'type == "object"' "$MF" >/dev/null 2>&1; then cp "$MF" "$MJ"; MOK=1
else MNOTE="$MF is not a JSON object"; fi
[ "$MOK" = 1 ] || echo '{}' > "$MJ"
# ~ expanded, one path per line
ZONE="$(jq -r '.sandbox.filesystem.allowWrite // [] | .[]' "$MJ" 2>/dev/null | sed "s|^~/|$HOME/|")"
FOLDERS="$(sh "$HERE/scope-managed-folders.sh" --rows 2>/dev/null | sed -n 's|^Edit(\(.*\)/\*\*)$|\1|p' | sed "s|^~/|$HOME/|")"
[ -n "$FOLDERS" ] || { log_warn "$P unchecked: contracts/main-folders.txt rendered no folder"; log_fix "sh $HERE/scope-managed-folders.sh --rows"; finish stood-down unchecked 3; }

# overlap <path> <path> -> 0 when one is the other or lies under it
overlap() { case "$1" in "$2"|"$2"/*) return 0 ;; esac; case "$2" in "$1"/*) return 0 ;; esac; return 1; }
# in_zone <path> -> 0 and the row when the path is a write-list row or below one
in_zone() {
  while IFS= read -r _z; do
    [ -n "$_z" ] || continue
    case "$1" in "$_z"|"$_z"/*) printf '%s\n' "$_z"; return 0 ;; esac
  done <<EOF
$ZONE
EOF
  return 1
}

# ── the live canary: one file per main folder through a surface, read back from disk, removed ──
# canary <surface> -> prints one of: landed:<folder>... | refused | unprobed:<why> | none
canary() {
  [ "$PROBE" = 1 ] || { echo none; return; }
  [ -n "${HARBOR_DRIFT_WALL_RUNNER:-}" ] || { echo "unprobed:HARBOR_DRIFT_WALL_RUNNER names no runner"; return; }
  [ -x "$HARBOR_DRIFT_WALL_RUNNER" ] || { echo "unprobed:$HARBOR_DRIFT_WALL_RUNNER is not executable"; return; }
  _land=""; _ran=0
  while IFS= read -r _f; do
    [ -d "$_f" ] || continue
    _c="$_f/.harbor-wall-canary-$$"; rm -f "$_c"
    "$HARBOR_DRIFT_WALL_RUNNER" "$1" "$_c" < /dev/null > /dev/null 2>&1; _r=$?
    if [ -e "$_c" ]; then _land="$_land $_f"; rm -f "$_c"; _ran=1
    elif [ "$_r" -le 1 ]; then _ran=1
    else echo "unprobed:the runner exited $_r for $1 (cannot drive this surface)"; return; fi
  done <<EOF
$FOLDERS
EOF
  [ "$_ran" = 1 ] || { echo "unprobed:no main folder exists to hold a canary"; return; }
  if [ -n "$_land" ]; then echo "landed:${_land# }"; else echo refused; fi
}
# probed <surface> <config verdict: holds|nothold> <config detail> <fix>: combine a config verdict with the canary
surface() {
  _s="$1"; _cv="$2"; _cd="$3"; _fx="$4"; _key="$5"
  _cr="$(canary "$_key")"
  case "$_cr" in
    landed:*) nothold "$_s" probe "a canary landed in ${_cr#landed:}; config said: $_cd" "$_fx" ;;
    refused)
      if [ "$_cv" = holds ]; then holds "$_s" probe "a canary in each main folder was refused; $_cd"
      else nothold "$_s" config "$_cd (a canary was refused this run, which does not close it: a refusal may be a prompt)" "$_fx"; fi ;;
    unprobed:*)
      if [ "$_cv" = holds ]; then holds "$_s" config "$_cd; canary not run: ${_cr#unprobed:}"
      else nothold "$_s" config "$_cd; canary not run: ${_cr#unprobed:}" "$_fx"; fi ;;
    *)
      if [ "$_cv" = holds ]; then holds "$_s" config "$_cd; no canary written (--probe)"
      else nothold "$_s" config "$_cd" "$_fx"; fi ;;
  esac
}

# 1 · confined Bash: the sandbox is on and no write-list row reaches a main folder
if [ "$MOK" = 0 ]; then
  surface "confined Bash" nothold "$MNOTE, so Bash runs with no confinement" "sudo sh $HERE/deploy-confinement.sh" bash-confined
else
  _en="$(jq -r '(.sandbox.enabled == true) and (.sandbox.failIfUnavailable == true)' "$MJ")"
  _hit=""
  while IFS= read -r _z; do
    [ -n "$_z" ] || continue
    while IFS= read -r _f; do [ -n "$_f" ] && overlap "$_z" "$_f" && _hit="$_hit $_z~$_f"; done <<EOF
$FOLDERS
EOF
  done <<EOF
$ZONE
EOF
  if [ "$_en" != true ]; then
    surface "confined Bash" nothold "the managed sandbox block is missing, or not enabled with failIfUnavailable" "sudo sh $HERE/deploy-confinement.sh" bash-confined
  elif [ -n "$_hit" ]; then
    surface "confined Bash" nothold "a write-list row reaches a main folder (write row ~ folder:${_hit})" "edit contracts/confinement-paths.txt or the private layer's, then sudo sh $HERE/deploy-confinement.sh" bash-confined
  else
    surface "confined Bash" holds "the sandbox is on and no write-list row reaches a main folder" "" bash-confined
  fi
fi

# 2 · retried Bash: a command the sandbox refuses may be run again without it unless the managed block closes the retry
_ru="$(jq -r '(.sandbox // {}) | if has("allowUnsandboxedCommands") then (.allowUnsandboxedCommands | tostring) else "absent" end' "$MJ")"
if [ "$MOK" = 1 ] && [ "$_ru" = false ]; then
  surface "retried Bash" holds "allowUnsandboxedCommands is false" "" bash-retried
else
  surface "retried Bash" nothold "allowUnsandboxedCommands is ${_ru} (${MNOTE:-the retry runs the command outside the confinement}); #555 P4 closes it with confinement_strict" "set confinement_strict = \"true\" in harbor.toml after #555 decision 10, then sudo sh $HERE/deploy-confinement.sh" bash-retried
fi

# 3 · Edit/Write: the managed permissions.deny holds an Edit row per main folder
_m="$(HARBOR_MANAGED_SETTINGS="$MF" sh "$HERE/scope-managed-folders.sh" --missing 2>/dev/null)"; _mrc=$?
if [ "$_mrc" -ne 0 ]; then
  notprobed "Edit/Write" "the managed file could not be read for deny rows ($MF)" "sh $HERE/scope-managed-folders.sh --missing"
elif [ -z "$_m" ]; then
  surface "Edit/Write" holds "the managed permissions.deny holds an Edit row for every main folder" "" edit-write
else
  _mn="$(printf '%s\n' "$_m" | tr '\n' ' ')"
  surface "Edit/Write" nothold "the managed permissions.deny lacks: ${_mn% }${MNOTE:+ ($MNOTE)}" "sudo sh $HERE/scope-managed-folders.sh" edit-write
fi

# 4 · each local MCP server: wrapped in srt, or exempt by a recorded row
mcp_inventory
[ -z "$INV_BAD" ] || notprobed "MCP servers" "$INV_BAD" "inspect $CJ"
{ [ -f "$CORE/confinement-mcp.tsv" ] && sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$CORE/confinement-mcp.tsv"
  _priv="$(sh "$HERE/scope-roots.sh" --private 2>/dev/null || :)"
  [ -z "$_priv" ] || [ ! -f "$_priv/confinement-mcp.tsv" ] || sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$_priv/confinement-mcp.tsv"; } > "$T/mcprows" 2>/dev/null
_badm="$(awk -F'\t' '$1 == "" || ($2 != "wrap" && $2 != "exempt") || $3 == "" { print NR ": " $0 }' "$T/mcprows" | head -1)"
if [ -n "$_badm" ]; then
  notprobed "MCP servers" "a row of confinement-mcp.tsv is not <server> TAB wrap|exempt TAB <reason> ($_badm)" "edit contracts/confinement-mcp.tsv"
elif [ ! -s "$T/inv.s" ]; then
  log_note "$P MCP servers: no local (stdio) server in $CJ or any governed repo's .mcp.json"
else
  _names="$(cut -f1 "$T/inv.s" | sort -u)"
  for _n in $_names; do
    _cmd="$(awk -F'\t' -v n="$_n" '$1 == n { print $3; exit }' "$T/inv.s")"
    _src="$(awk -F'\t' -v n="$_n" '$1 == n { s = s (s ? ", " : "") $2 } END { print s }' "$T/inv.s")"
    _wrapped=no; [ "$(basename -- "$_cmd")" = srt ] && _wrapped=yes
    _verdict="$(awk -F'\t' -v n="$_n" '$1 == n { print $2; exit }' "$T/mcprows")"
    _why="$(awk -F'\t' -v n="$_n" '$1 == n { print $3; exit }' "$T/mcprows")"
    if [ "$_wrapped" = yes ]; then
      holds "MCP $_n" config "starts under srt ($_src); a canary-writing tool call was not made"
    elif [ "$_verdict" = exempt ]; then
      exempted "MCP $_n" config "runs unwrapped ($_src)" "$_why"
    elif [ "$_verdict" = wrap ]; then
      nothold "MCP $_n" config "contracts/confinement-mcp.tsv says wrap, but the registered command is $(basename -- "$_cmd"), not srt ($_src)" "claude mcp get $_n shows the command; operator-steps lists the srt form"
    else
      nothold "MCP $_n" config "starts as $(basename -- "$_cmd") with no srt wrapper and no row in contracts/confinement-mcp.tsv ($_src)" "wrap it in srt, or add a <server> TAB exempt TAB <reason> row (the private layer's confinement-mcp.tsv for a workload server)"
    fi
  done
fi

# 5 · hooks: a hook command that runs a file in the write list runs what an agent can edit, outside the sandbox
: > "$T/hookcmds"
for _sf in "$US" "$MJ"; do
  [ -f "$_sf" ] && jq -r '[.. | objects | select(has("command")) | .command | strings] | .[]' "$_sf" 2>/dev/null >> "$T/hookcmds"
done
if [ -z "$ZONE" ]; then
  notprobed "hooks" "no installed write list to judge a hook command's path against (${MNOTE:-the managed sandbox block has none})" "sudo sh $HERE/deploy-confinement.sh"
else
  _hh=""
  tr -s ' \t"'"'"'' '\n\n\n\n' < "$T/hookcmds" | sed -e "s|^\$HOME/|$HOME/|" -e "s|^\${HOME}/|$HOME/|" -e "s|^~/|$HOME/|" | grep '^/' | sort -u > "$T/hooktoks"
  while IFS= read -r _tok; do
    in_zone "$_tok" >/dev/null && _hh="$_hh $_tok"
  done < "$T/hooktoks"
  if [ -z "$_hh" ]; then
    holds "hooks" config "no hook command in $US or the managed file names a path inside the write list"
  else
    nothold "hooks" config "a hook command runs a path inside the write list:${_hh}" "install the hook script under ~/.claude/bin (write-denied) and point the hook at it"
  fi
fi

# 6 · launchd jobs: drift-launchd-wall.sh judges ProgramArguments against the same write list
_ls="$(sh "$HERE/drift-launchd-wall.sh" --state 2>/dev/null)"
case "$_ls" in
  match) holds "launchd jobs" config "no com.harbor.* job runs code from the write list (drift-launchd-wall.sh)" ;;
  drift) nothold "launchd jobs" config "a com.harbor.* job runs code from the write list (the paths: sh $HERE/drift-launchd-wall.sh)" "sh $HERE/drift-launchd-wall.sh" ;;
  not-applicable) log_skip "$P launchd jobs: not applicable — no launchd plists on this host" ;;
  *) notprobed "launchd jobs" "drift-launchd-wall.sh could not judge" "sh $HERE/drift-launchd-wall.sh" ;;
esac
[ "$PROBE" = 1 ] || log_note "$P no canary was written: config verdicts only. --probe with HARBOR_DRIFT_WALL_RUNNER writes one per main folder through Bash and Edit/Write; a local MCP server's canary-writing tool call has no runner yet"

if [ "$NH" -gt 0 ]; then
  log_fail "$P $NH surface(s) do not hold, listed above ($NX more exempt by a recorded row)"
  log_fix "$FIXHINT"
  set -f; IFS='
'
  # shellcheck disable=SC2086
  finish red does-not-hold 1 $SUBJ
fi
if [ "$NP" -gt 0 ]; then finish stood-down unchecked 3; fi
log_ok "$P every judged surface holds ($NX exempt by a recorded row)"
finish green holds 0
