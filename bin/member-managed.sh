#!/usr/bin/env sh
# member-managed.sh (harbor#1278) — the managed settings of a member laptop, composed as JSON. Writes nothing, needs no root.
#   sh member-managed.sh --hub <owner/name> --login <github login> [--user <name>] [--root <dir>] [--mcp-allow <file>] [--deny-host <host>] [--allow-host <host>]...
#   sh member-managed.sh --where                 the managed root, then the managed settings file, for this OS
#   sh member-managed.sh --higher-source         each policy source that would silently beat the file; exit 1 when there is one
# --mcp-allow names a JSON array of allowedMcpServers entries; with none, no MCP server a person adds may load.
# The `sandbox` block is deploy-confinement.sh's composition, strict; this adds only what a member needs on top of it.
# --deny-host names the hub's support relay; upterm's public relay is always denied too, so the agent's shell can't reach a session (contracts/hub.md).
# --allow-host adds a host from signed policy `hosts` to the sandbox's allowlist, beside contracts/confinement-hosts.txt and contracts/member-hosts.txt.
# A managed file is the lowest admin source and Claude Code warns about nothing it skips, so --higher-source runs before any write (F10).
# Server-managed policy can't be seen from the laptop before sign-in: docs/how-to/member-install.md has IT read `Setting sources` in /status for it.
# HARBOR_MEMBER_OS (Darwin, Linux, WSL) and HARBOR_MEMBER_PREFS_DIR are test seams, refused under root with HARBOR_SCOPE_MANAGED_SETTINGS.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD   # stdout is the JSON
. "$HERE/library-log.sh"
log_init member-managed

# onFailure needs 2.1.295 (bin/deploy-install-lib.sh, il_onfailure); wslInheritsWindowsSettings needs 2.1.282, so this one covers both, and bare `*` in WebFetch(domain:) at 2.1.186.
MEMBER_MIN_VERSION=2.1.295
# W2: off by decision on #1278. The docs grey out the WSL entry with Local, so this stays false, and a Local session fails closed:
# the managed hook can't run there and onFailure block refuses every tool call. True only if the Windows test shows WSL survives.
MEMBER_DISABLE_LOCAL=false
# W6: allowlist by decision on #1278 (2026-11-07, reversing open): the core and member host lists plus signed policy `hosts`, fixed at install.
# open adds a managed WebFetch(domain:*), which lets sandboxed commands reach any host: reversed because deniedDomains matches names only (member-install.md).
MEMBER_NETWORK=allowlist
# N2 (harbor#1278): every hook starts from `env -i` and these names alone, each passed only when set. macOS /bin/sh is bash 3.2, which defines an exported
# function from the environment before any line of ours runs. Data only: the floor reads the role from member.conf and the proxy and CA from the managed file.
# No bus names: the hub token on Linux and WSL is bin/secret's file store under HOME, which needs no Secret Service (W7).
MEMBER_HOOK_ENV='HOME USER LOGNAME LANG LC_ALL LC_CTYPE TMPDIR CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR'

# member_refuse_override <uid> -> 1 and a FAIL when root is handed a path or OS override: sudo -E would let it aim a root write.
member_refuse_override() {
  [ "$1" -eq 0 ] || return 0
  for _v in HARBOR_SCOPE_MANAGED_SETTINGS HARBOR_MANAGED_SETTINGS HARBOR_MEMBER_OS HARBOR_MEMBER_PREFS_DIR HARBOR_MEMBER_ROOT; do
    eval "_s=\${$_v:-}"
    [ -z "$_s" ] && continue
    log_fail "$_v is set under root: refusing a caller-chosen target"
    log_fix "sudo env -u $_v sh $0"; return 1
  done
}
# member_os -> Darwin, Linux or WSL. WSL needs the Windows policy chain, so it is told apart from Linux here and nowhere else.
member_os() {
  if [ -n "${HARBOR_MEMBER_OS:-}" ]; then printf '%s' "$HARBOR_MEMBER_OS"; return 0; fi
  case "$(uname -s)" in
    Darwin) printf Darwin ;;
    *) if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null; then printf WSL; else printf Linux; fi ;;
  esac
}
# member_settings <os> -> the managed settings file. The override moves it for tests, and the root with it.
member_settings() {
  if [ -n "${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}" ]; then printf '%s' "${HARBOR_SCOPE_MANAGED_SETTINGS:-$HARBOR_MANAGED_SETTINGS}"; return 0; fi
  case "$1" in
    Darwin) printf '%s' '/Library/Application Support/ClaudeCode/managed-settings.json' ;;
    # W4: /mnt/c is the Windows chain, writable only by a Windows admin. If scripts can't run from it, this and member_root move.
    WSL) printf '%s' '/mnt/c/Program Files/ClaudeCode/managed-settings.json' ;;
    *) printf '%s' '/etc/claude-code/managed-settings.json' ;;
  esac
}
# member_root <os> -> the managed root: always the sibling `harbor` of the settings file.
member_root() { _mr="$(member_settings "$1")"; printf '%s/harbor' "${_mr%/*}"; }

# member_protected <managed root> <port root> -> one path per line: every file that carries a hook or an env value, and the hub state.
# `~/` is the home, `**/` any project, `/` absolute. A folder ends in `/`. One list feeds both the Edit rows and denyWrite, so they can't part (F1).
member_protected() {
  printf '%s\n' \
    '~/.claude/settings.json' '~/.claude/settings.local.json' '~/.claude.json' '~/.claude/hooks/' '~/.claude/plugins/' '~/.claude/bin/' '~/.claude/session-env/' \
    '**/.claude/settings.json' '**/.claude/settings.local.json' '**/.claude/hooks/' '**/.agents/hooks/' '**/.mcp.json' '**/.git/hooks/' '**/.git/config' '**/.envrc' \
    '~/.profile' '~/.bashrc' '~/.bash_profile' '~/.bash_login' '~/.zshrc' '~/.zshenv' '~/.zprofile' '~/.zlogin' '~/.pam_environment' '~/.config/environment.d/' \
    '~/.gitconfig' '~/.config/git/' \
    '~/.local/state/harbor/hub/' '~/.local/share/secret/' \
    "$2/harbor-private/" \
    "$1/" "${1%/*}/managed-settings.json" "${1%/*}/managed-settings.d/" "${1%/*}/harbor-confinement" "${1%/*}/CLAUDE.md"
  case "$1" in /mnt/*) printf '%s\n' /etc/claude-code/CLAUDE.md ;; esac   # WSL: the in-distro copy (bin/member-install.sh)
}
# Every row as its `Edit(...)` rule. Never Write(...): the harness accepts those and never consults them (M10, bin/admission-deny.sh).
member_edit_rows() {
  sed -e 's|^/|//|' -e 's|^\*\*/|//**/|' -e 's|/$|/**|' -e 's|^|Edit(|' -e 's|$|)|'
}
# Every row as a sandbox path: a project row stays inside the write zone, the only place a confined command can reach it.
member_sandbox_rows() { # <port root>
  sed -e "s|^\*\*/|$1/**/|" -e 's|/$||'
}
# member_kill_switches <env.tsv> -> `name<TAB>pinned value` per kill-switch row: derived, so a new one is pinned without an edit here.
# A switch is pinned to 0; a mode such as HARBOR_ADMISSION_SG3 (off, warn, block) has no 0, so it is pinned to its default.
member_kill_switches() { awk -F'\t' '$3 == "kill-switch" && $1 ~ /^HARBOR_/ { print $1 "\t" ($4 ~ /^[a-z]+$/ ? $4 : "0") }' "$1"; }

# member_denied_hosts <extra host> -> the relays closed to a sandboxed command, as a JSON array: the public one always, and the hub's own.
member_denied_hosts() {
  _dh="$(awk -F'\t' '$1 == "public-relay" { print $2; exit }' "$HERE/../contracts/support-upterm.tsv")"
  [ -n "$_dh" ] || { log_fail "contracts/support-upterm.tsv has no public-relay row to deny"; log_nofix "contracts/support-upterm.tsv"; return 1; }
  printf '%s\n%s\n' "$_dh" "$1" | jq -R . | jq -s -c 'map(select(length > 0)) | unique'
}
# member_hosts_bad -> each stdin line that isn't one host in allowedDomains shape: at most one leading `*.`, two labels or more, never a bare `*`.
member_hosts_bad() { awk 'length($0) > 253 || $0 !~ /^(\*\.)?[a-z0-9-]+(\.[a-z0-9-]+)+$/'; }
# member_allowed_hosts <policy hosts, one per line> -> contracts/member-hosts.txt's rows and the policy's, as a JSON array; 1 on a row of the wrong shape.
member_allowed_hosts() {
  _ah="$HERE/../contracts/member-hosts.txt"
  [ -f "$_ah" ] || { log_fail "$_ah is missing, and the member allowlist starts there"; log_nofix "contracts/member-hosts.txt"; return 1; }
  _ar="$({ sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$_ah"; printf '%s\n' "$1"; } | sed '/^[[:space:]]*$/d')"
  _bad="$(printf '%s\n' "$_ar" | sed '/^$/d' | member_hosts_bad)"
  [ -z "$_bad" ] || { log_fail "an allowed host that does not compose: $(printf '%s' "$_bad" | tr '\n' ' ')"; log_nofix "contracts/member-hosts.txt or policy hosts (contracts/hub.md)"; return 1; }
  printf '%s\n' "$_ar" | jq -R . | jq -s -c 'map(select(length > 0)) | unique'
}
# The events a hub pack's rules may use (harbor#1278). Which hub rules exist is the signed hub's, unknown here, so the engine stands on every event a "which
# tool when" note needs: the session's start, a prompt, a helper's start and each tool call (a rule's own `tool:` and `when:` still decide whether it speaks).
MEMBER_HUB_RULE_EVENTS='SessionStart UserPromptSubmit SubagentStart PreToolUse'

# member_rule_events <contracts dir> -> JSON {"<event>": "<matcher or ->"}: the events the engine is wired on, derived from the listed packs.
# A tool event takes the union of the packs' `tool:` values, or `*` when any pack on it names none. Empty list, empty object: nothing is wired.
member_rule_events() {
  _re_root="$(CDPATH='' cd -- "$1/.." && pwd)"
  awk -F'\t' '$1 !~ /^#/ && $1 != "id" && $1 != "" { print $1 }' "$1/member-context-rules.tsv" | while IFS= read -r _id; do
    _pk="$_re_root/contracts/member-rules/$_id.md"   # the member variant: what a member reads is plain, and the shared rule is the dev box's
    [ -f "$_pk" ] || _pk="$(find "$_re_root/context-rules" -maxdepth 2 -name "$_id.md" 2>/dev/null | head -1)"
    [ -n "$_pk" ] || { echo "MISSING $_id"; continue; }
    awk -v id="$_id" 'NR==1 { next } /^---/ { exit } /^event:/ { sub(/^event:[ \t]*/, ""); e = $0 } /^tool:/ { sub(/^tool:[ \t]*/, ""); t = $0 } /^(run|spoke):/ { r = 1 }
      END { printf "%s\t%s\t%s\t%s\n", id, e, (t == "" ? "-" : t), (r ? "script" : "") }' "$_pk"
  done | awk -F'\t' '
    $1 == "MISSING" || $0 ~ /^MISSING/ { print "ERR\t" $0; next }
    $4 == "script" { print "ERR\t" $1 " has run: or spoke:"; next }
    $2 == "" { print "ERR\t" $1 " names no event"; next }
    { if ($3 == "-") any[$2] = 1; else { m[$2] = (m[$2] == "" ? $3 : m[$2] "|" $3) } ev[$2] = 1 }
    END { for (e in ev) print "EV\t" e "\t" ((e in any) || m[e] == "" ? "-" : m[e]) }'
}
# member_compose <os> <root> <hub> <login> <user> <mcp json> [<relay host>] [<policy hosts, one per line>] -> the managed settings on stdout
member_compose() {
  _mc_relays="$(member_denied_hosts "${7:-}")" || return 1
  _mc_hosts="$(member_allowed_hosts "${8:-}")" || return 1
  case "$2" in *\'*) log_fail "the managed root $2 holds a quote, and it goes into a hook command"; log_nofix "contracts/hub.md, the managed root"; return 1 ;; esac
  _mc_args='--compose --member'
  # shellcheck disable=SC2086 # _mc_args is two fixed flags; the user name is its own quoted word
  if [ -n "$5" ]; then _mc_block="$(sh "$HERE/deploy-confinement.sh" $_mc_args --user "$5")" || return 1
  else _mc_block="$(sh "$HERE/deploy-confinement.sh" $_mc_args)" || return 1; fi
  case "$MEMBER_NETWORK" in open) _mc_open=true ;; allowlist) _mc_open=false ;; *) log_fail "MEMBER_NETWORK is $MEMBER_NETWORK, not open or allowlist"; log_nofix "bin/member-managed.sh"; return 1 ;; esac
  _mc_port="$(printf '%s' "$_mc_block" | jq -r '.filesystem.allowWrite[0]')"   # the first write row is @PORT_ROOT@ (contracts/confinement-paths.txt)
  case "$_mc_port" in /*) ;; *) log_fail "the composed sandbox names no workspace: $_mc_port"; log_nofix "contracts/confinement-paths.txt"; return 1 ;; esac
  _mc_rows="$(member_protected "$2" "$_mc_port")"
  _mc_edit="$(printf '%s\n' "$_mc_rows" | member_edit_rows | jq -R . | jq -s -c .)"
  _mc_deny="$(printf '%s\n' "$_mc_rows" | member_sandbox_rows "$_mc_port" | jq -R . | jq -s -c .)"
  _mc_kill="$(member_kill_switches "$HERE/../contracts/env.tsv" | jq -R . | jq -s -c .)"
  # No allowed row may admit a relay: deniedDomains wins by name, but an allowed wildcard over a relay is a list that says two things.
  _mc_clash="$(jq -n -r --argjson a "$_mc_hosts" --argjson d "$_mc_relays" '[$a[] as $r | $d[] as $h | select($r == $h or (($r | startswith("*.")) and ($h | endswith($r[1:])))) | $r] | unique | .[]')"
  [ -z "$_mc_clash" ] || { log_fail "an allowed host admits a support relay: $(printf '%s' "$_mc_clash" | tr '\n' ' ')"; log_nofix "contracts/member-hosts.txt or policy hosts; the relay stays denied (contracts/hub.md)"; return 1; }
  [ "$_mc_kill" != '[]' ] || { log_fail "contracts/env.tsv names no kill switch to pin"; log_nofix "contracts/env.tsv"; return 1; }
  _mc_ev="$(member_rule_events "$HERE/../contracts")"
  case "$_mc_ev" in *ERR*) log_fail "contracts/member-context-rules.tsv: $(printf '%s\n' "$_mc_ev" | awk -F'\t' '$1 == "ERR" { print $2 }' | tr '\n' ' ')"; log_nofix "contracts/member-context-rules.tsv"; return 1 ;; esac
  _mc_rules="$(printf '%s\n' "$_mc_ev" | awk -F'\t' '$1 == "EV" { print $2 "\t" $3 }' | jq -R 'split("\t") | {key: .[0], value: .[1]}' | jq -s -c 'from_entries')"
  _mc_rules="$(printf '%s' "$_mc_rules" | jq -c --arg ev "$MEMBER_HUB_RULE_EVENTS" 'reduce ($ev | split(" ")[]) as $e (.; .[$e] = "-")')"
  jq -n --argjson block "$_mc_block" --argjson edit "$_mc_edit" --argjson deny "$_mc_deny" --argjson kill "$_mc_kill" --argjson mcp "$6" --argjson relays "$_mc_relays" \
     --argjson hosts "$_mc_hosts" --argjson rules "$_mc_rules" \
     --arg q "'" --arg root "$2" --arg hub "$3" --arg login "$4" --arg min "$MEMBER_MIN_VERSION" --argjson local "$MEMBER_DISABLE_LOCAL" \
     --argjson open "$_mc_open" --arg port "$_mc_port" --arg keep "$MEMBER_HOOK_ENV" '
    # Absolute: a settings env reaches every hook, and a bare `sh` resolved from its PATH could exit 0 for a hook that never ran (#1278).
    # From an empty environment: an inherited exported function would run before the floor does (N2).
    ("/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin "
      + ($keep | split(" ") | map("${" + . + ":+\"" + . + "=$" + . + "\"}") | join(" "))
      + " /bin/sh " + $q + $root + "/bin/") as $sh |
    {type: "command", command: ($sh + "member-post.sh" + $q)} as $post |
    {type: "command", command: ($sh + "member-session.sh" + $q)} as $session |
    {type: "command", command: ($sh + "member-upgrade.sh" + $q)} as $upgrade |
    # member.tools-sync: own tools go to the private repo at Stop. Bounded inside, always exit 0, writes nothing on stdout.
    {type: "command", command: ($sh + "member-tools.sh" + $q + " push"), timeout: 20} as $tools |
    {type: "command", command: ($sh + "member-tests.sh" + $q)} as $tests |
    {type: "command", command: ($sh + "member-tests.sh" + $q + " snap")} as $testsnap |
    {type: "command", command: ($sh + "hub-approval.sh" + $q + " note UserPromptSubmit")} as $note |
    # The context rules: the engine in member mode, handed the root as an argument so no environment value can aim it at a repo.
    {type: "command", command: ($sh + "injection-rule.sh" + $q + " --member-root " + $q + $root + $q)} as $engine |
    # After the existing entries of each event, so the dispatcher stays hooks.PreToolUse[0]. A tool event takes the derived matcher.
    ($rules | to_entries | map({key: .key, value: [(if (.key | IN("PreToolUse", "PostToolUse", "PostToolUseFailure")) then {matcher: (if .value == "-" then "*" else .value end), hooks: [$engine]} else {hooks: [$engine]} end)]}) | from_entries) as $ctx |
    {wslInheritsWindowsSettings: true,
     allowManagedHooksOnly: true,
     allowManagedPermissionRulesOnly: true,
     allowManagedMcpServersOnly: true,
     allowedMcpServers: $mcp,
     requiredMinimumVersion: $min,
     disableSideloadFlags: true,
     sshHostAllowlist: [],
     # W10: a WSL session opens in the home folder and no setting moves it (docs/how-to/member-install.md), so the workspace is a working directory from anywhere.
     permissions: ({disableBypassPermissionsMode: "disable", deny: $edit, additionalDirectories: [$port]}
                   + (if $open then {allow: ["WebFetch(domain:*)"]} else {} end)),
     env: ({HARBOR_MEMBER_ROLE: "member", HARBOR_HUB_REPO: $hub, HARBOR_MEMBER_LOGIN: $login, HARBOR_MEMBER_ROOT: $root}
           + ($kill | map(split("\t") | {key: .[0], value: .[1]}) | from_entries)),
     hooks: (({
       PreToolUse: [{matcher: "*", hooks: [{type: "command", command: ($sh + "member-dispatch.sh" + $q), onFailure: "block"}]}],
       PostToolUse: [{matcher: "*", hooks: [$post]}],
       PostToolUseFailure: [{matcher: "*", hooks: [$post]}],
       Stop: [{hooks: [$post, $upgrade, $tests, $tools]}],
       UserPromptSubmit: [{hooks: [$note, $testsnap]}],
       SessionStart: [{hooks: [$session]}],
       # The default is a shared 1.5 seconds, and member-session.sh bounds its send at 8: a slow send would be cancelled and wait for the next one.
       SessionEnd: [{hooks: [$session + {timeout: 15}]}]}
       | with_entries(.value += ($ctx[.key] // []))) as $merged | $ctx + $merged),
     sandbox: ($block
       | .filesystem.denyWrite = ((.filesystem.denyWrite + $deny) | unique)
       | .network.allowedDomains = (.network.allowedDomains + ($hosts - .network.allowedDomains))
       | .network.deniedDomains = (((.network.deniedDomains // []) + $relays) | unique)
       | .credentials.files = (.credentials.files + [{path: "~/.local/share/secret", mode: "deny"}]))}
    + (if $local then {disableDesktopLocalSessions: true} else {} end)'
}

# member_higher_source <os> -> one line per source that beats, or merges over, the file this install writes. Reads only (F10).
member_higher_source() {
  _hs_file="$(member_settings "$1")"; _hs_dir="${_hs_file%/*}"
  case "$1" in
    Darwin)
      _hs_prefs="${HARBOR_MEMBER_PREFS_DIR:-/Library/Managed Preferences}"
      [ -z "$(find "$_hs_prefs" -name 'com.anthropic.claudecode.plist' 2>/dev/null | head -1)" ] \
        || printf 'an MDM profile (com.anthropic.claudecode) under %s\n' "$_hs_prefs" ;;
    WSL)
      _hs_reg="$(command -v reg.exe 2>/dev/null || printf '/mnt/c/Windows/System32/reg.exe')"
      if [ ! -x "$_hs_reg" ]; then log_note "reg.exe can't be reached, so the PowerShell's own first line is what checks HKLM"
      elif "$_hs_reg" query 'HKLM\SOFTWARE\Policies\ClaudeCode' /v Settings >/dev/null 2>&1; then
        printf 'an HKLM policy (HKLM\\SOFTWARE\\Policies\\ClaudeCode, value Settings)\n'
      fi ;;
  esac
  # Drop-ins merge after the file, so one of them can undo a key of ours with no warning.
  [ -z "$(find "$_hs_dir/managed-settings.d" -name '*.json' 2>/dev/null | head -1)" ] \
    || printf 'drop-in files in %s/managed-settings.d\n' "$_hs_dir"
  # Someone else's file: merging would keep keys nobody reviewed here. A re-run finds our own role and goes on.
  if [ -f "$_hs_file" ] && ! jq -e '.env.HARBOR_MEMBER_ROLE == "member"' "$_hs_file" >/dev/null 2>&1; then
    printf 'a managed settings file this install did not write: %s\n' "$_hs_file"
  fi
  return 0
}

[ "${MEMBER_MANAGED_LIB:-0}" = 1 ] && return 0
member_refuse_override "$(id -u)" || exit 1
MODE=compose; HUB=''; LOGIN=''; USERNAME=''; ROOT_ARG=''; MCP_FILE=''; DENY_HOST=''; ALLOW_HOSTS=''
while [ $# -gt 0 ]; do
  case "$1" in
    --where) MODE=where ;;
    --higher-source) MODE=higher ;;
    --hub|--login|--user|--root|--mcp-allow|--deny-host|--allow-host)
      [ $# -ge 2 ] || { log_fail "$1 needs a value"; log_nofix "sh $0 --help"; exit 2; }
      case "$1" in --hub) HUB="$2" ;; --login) LOGIN="$2" ;; --user) USERNAME="$2" ;; --root) ROOT_ARG="$2" ;; --mcp-allow) MCP_FILE="$2" ;; --deny-host) DENY_HOST="$2" ;;
        --allow-host) [ -n "$2" ] && [ -z "$(printf '%s\n' "$2" | member_hosts_bad)" ] || { log_fail "--allow-host wants one host, at most one leading *., never a bare *: got '$2'"; log_nofix "contracts/hub.md, hosts"; exit 2; }
                      ALLOW_HOSTS="$ALLOW_HOSTS$2
" ;; esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) log_fail "unknown argument $1"; log_nofix "sh $0 --help"; exit 2 ;;
  esac
  shift
done
OS="$(member_os)"
case "$OS" in Darwin|Linux|WSL) ;; *) log_fail "HARBOR_MEMBER_OS is $OS, not Darwin, Linux or WSL"; log_nofix "contracts/env.tsv"; exit 2 ;; esac
if [ "$MODE" = where ]; then member_root "$OS"; printf '\n'; member_settings "$OS"; printf '\n'; exit 0; fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is missing, and without it the guards fail open"; log_fix "$(pkg_hint jq)"; exit 1; }
if [ "$MODE" = higher ]; then
  _found="$(member_higher_source "$OS")"
  [ -n "$_found" ] || exit 0
  printf '%s\n' "$_found"; exit 1
fi
slug_valid "$HUB" || { log_fail "--hub wants owner/name, got '$HUB'"; log_nofix "sh $0 --help"; exit 2; }
case "$LOGIN" in ''|-*|*[!A-Za-z0-9-]*) log_fail "--login wants a GitHub login, got '$LOGIN'"; log_nofix "sh $0 --help"; exit 2 ;; esac
case "$DENY_HOST" in *[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) log_fail "--deny-host wants a host name, got '$DENY_HOST'"; log_nofix "sh $0 --help"; exit 2 ;; esac
MCP='[]'
if [ -n "$MCP_FILE" ]; then
  MCP="$(jq -c . "$MCP_FILE" 2>/dev/null)" || { log_fail "--mcp-allow: $MCP_FILE is not JSON"; log_nofix "sh $0 --help"; exit 2; }
  printf '%s' "$MCP" | jq -e 'type == "array" and all(.[]; type == "object" and (keys | length == 1) and (keys[0] | IN("serverName", "serverCommand", "serverUrl")))' >/dev/null \
    || { log_fail "--mcp-allow: each entry has exactly one of serverName, serverCommand, serverUrl"; log_nofix "code.claude.com/docs/en/settings-reference, allowedMcpServers"; exit 2; }
fi
# A test's OS reaches the composition too; under root the variable was refused above, and uname answers.
if [ -n "${HARBOR_MEMBER_OS:-}" ]; then
  HARBOR_DEPLOY_CONFINEMENT_OS=Linux; [ "$OS" != Darwin ] || HARBOR_DEPLOY_CONFINEMENT_OS=Darwin
  export HARBOR_DEPLOY_CONFINEMENT_OS
fi
member_compose "$OS" "${ROOT_ARG:-$(member_root "$OS")}" "$HUB" "$LOGIN" "$USERNAME" "$MCP" "$DENY_HOST" "$ALLOW_HOSTS"
