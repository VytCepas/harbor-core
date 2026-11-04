#!/usr/bin/env sh
# drift.wall (harbor#1442): drift-wall.sh prints one row per agent surface, holds / does not hold / not probed. The
# installed state is built by the writers' own output (deploy-confinement.sh, scope-managed-folders.sh) into a fixture
# managed file, so every red here is a real break of a real install and every green is its restore.
. "$(dirname "$0")/../../lib/core.sh"; t_init
DW="$T_ROOT/bin/drift-wall.sh"; INST="$T_ROOT/bin/deploy-confinement.sh"; FOL="$T_ROOT/bin/scope-managed-folders.sh"
HOME="$T_TMP/home"; export HOME
mkdir -p "$HOME/Desktop" "$HOME/Documents" "$HOME/Downloads" "$HOME/Movies" "$HOME/Music" "$HOME/Pictures" "$HOME/Library/LaunchAgents" "$HOME/.claude/bin"
PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT/harbor-private" "$PORT_ROOT/work"; PORT_ROOT="$(cd -P "$PORT_ROOT" && pwd)"; export PORT_ROOT
PRIV="$PORT_ROOT/harbor-private"
M="$T_TMP/managed/managed-settings.json"; mkdir -p "$T_TMP/managed"
US="$T_TMP/user-settings.json"; CJ="$T_TMP/claude.json"; LA="$T_TMP/LaunchAgents"; mkdir -p "$LA"
export HARBOR_MANAGED_SETTINGS="$M" HARBOR_CONFINEMENT_OS=Darwin HARBOR_CHECK_RECEIPTS="$T_TMP/receipts" \
  HARBOR_DRIFT_WALL_USER_SETTINGS="$US" HARBOR_DRIFT_WALL_CLAUDE_JSON="$CJ" HARBOR_DRIFT_LAUNCHD_DIR="$LA"
dw() { sh "$DW" "$@" 2>&1; }
rc() { sh "$DW" >/dev/null 2>&1; echo $?; }
state() { sh "$DW" --state 2>/dev/null; }
receipt() { jq -r .status "$HARBOR_CHECK_RECEIPTS/drift.wall.json" 2>/dev/null; }
row() { dw | grep -F "[check:drift.wall] $1:"; }   # one surface's row(s), named by $1
verdict() { row "$1" | sed -nE "s/.*\[check:drift.wall\] [^:]*: (holds|does not hold|not probed).*/\1/p" | head -1; }
printf '{}\n' > "$US"; printf '{"mcpServers":{"harbor_chrome":{"command":"python3","args":["-I","x.py"]}}}\n' > "$CJ"

t_section "nothing installed: the wall does not hold anywhere it can be judged"
printf '{}\n' > "$M"
t_eq "an empty managed file: exit 1" 1 "$(rc)"
t_eq "confined Bash does not hold" "does not hold" "$(verdict 'confined Bash')"
t_eq "retried Bash does not hold" "does not hold" "$(verdict 'retried Bash')"
t_eq "Edit/Write does not hold" "does not hold" "$(verdict 'Edit/Write')"
t_eq "...state does-not-hold" does-not-hold "$(state)"
t_eq "...the receipt is red" red "$(receipt)"

t_section "the confinement installed: Bash confined, the retry still open (the ticket's red row)"
sh "$INST" >/dev/null 2>&1
t_eq "CONTROL: the install wrote a sandbox block" true "$(jq 'has("sandbox")' "$M")"
t_eq "confined Bash holds" holds "$(verdict 'confined Bash')"
t_eq "retried Bash reads does not hold while allowUnsandboxedCommands is true" "does not hold" "$(verdict 'retried Bash')"
t_has "...naming the key and the ticket that closes it" "$(row 'retried Bash')" "allowUnsandboxedCommands is true"
t_eq "...so the whole check is red" 1 "$(rc)"
printf 'confinement_strict = "true"\n' > "$PRIV/harbor.toml"
sh "$INST" >/dev/null 2>&1
t_eq "after confinement_strict and a reinstall, retried Bash holds" holds "$(verdict 'retried Bash')"
t_eq "...and confined Bash still does" holds "$(verdict 'confined Bash')"

t_section "Edit/Write: red without the deny rows, green with them, red again with one removed"
t_eq "CONTROL: red before the rows" "does not hold" "$(verdict 'Edit/Write')"
sh "$FOL" >/dev/null 2>&1
t_eq "after scope-managed-folders.sh: holds" holds "$(verdict 'Edit/Write')"
cp "$M" "$T_TMP/good.json"
jq '.permissions.deny -= ["Edit(~/Documents/**)"]' "$T_TMP/good.json" > "$M"
t_eq "one folder's row removed: does not hold" "does not hold" "$(verdict 'Edit/Write')"
t_has "...naming the folder" "$(row 'Edit/Write')" "lacks: Edit(~/Documents/**)"
cp "$T_TMP/good.json" "$M"
t_eq "restored: holds" holds "$(verdict 'Edit/Write')"
printf 'not json' > "$M"
t_eq "an unreadable managed file is not probed, never a hold" "not probed" "$(verdict 'Edit/Write')"
cp "$T_TMP/good.json" "$M"

t_section "confined Bash: a write-list row that reaches a main folder breaks it"
printf 'write ~/Documents/scratch\n' > "$PRIV/confinement-paths.txt"
sh "$INST" >/dev/null 2>&1
t_eq "a write row inside Documents: does not hold" "does not hold" "$(verdict 'confined Bash')"
t_has "...naming the pair" "$(row 'confined Bash')" "$HOME/Documents/scratch~$HOME/Documents"
rm -f "$PRIV/confinement-paths.txt"; sh "$INST" >/dev/null 2>&1
t_eq "row removed and reinstalled: holds" holds "$(verdict 'confined Bash')"
jq '.sandbox.enabled = false' "$M" > "$T_TMP/off.json"; cp "$M" "$T_TMP/good.json"; cp "$T_TMP/off.json" "$M"
t_eq "the sandbox switched off: does not hold" "does not hold" "$(verdict 'confined Bash')"
cp "$T_TMP/good.json" "$M"

t_section "MCP servers: srt-wrapped, exempt by a row, or red"
t_eq "harbor_chrome carries core's exempt row: does not hold, exempt" "does not hold" "$(verdict 'MCP harbor_chrome')"
t_has "...stating the exemption and its reason" "$(row 'MCP harbor_chrome')" "exempt: drives the operator's own logged-in Chrome"
t_eq "CONTROL: an exempt server alone does not make the check red" "0 holds" "$(rc) $(state)"
printf '{"mcpServers":{"harbor_chrome":{"command":"python3","args":["-I","x.py"]},"srv":{"command":"npx","args":["-y","pkg"]},"remote":{"type":"http","url":"https://x.example"}}}\n' > "$CJ"
t_eq "an unwrapped server with no row: does not hold" "does not hold" "$(verdict 'MCP srv')"
t_has "...saying it has no srt wrapper and no row" "$(row 'MCP srv')" "no srt wrapper and no row in contracts/confinement-mcp.tsv"
t_eq "...and the check is red" "1 does-not-hold" "$(rc) $(state)"
t_eq "a remote (http) server is not local and has no row" "" "$(verdict 'MCP remote')"
printf 'srv\texempt\tcannot run under srt: needs the host keychain; bounded by its own read-only token\n' > "$PRIV/confinement-mcp.tsv"
t_has "a private exempt row covers it" "$(row 'MCP srv')" "exempt: cannot run under srt"
t_eq "...green again" "0 holds" "$(rc) $(state)"
printf 'srv\twrap\tmust start under srt\n' > "$PRIV/confinement-mcp.tsv"
t_has "a wrap row on an unwrapped server is red and says what the contract wants" "$(row 'MCP srv')" "says wrap, but the registered command is npx, not srt"
printf '{"mcpServers":{"harbor_chrome":{"command":"python3","args":["-I","x.py"]},"srv":{"command":"srt","args":["--settings","/p/srv.json","npx","-y","pkg"]}}}\n' > "$CJ"
t_eq "wrapped in srt: holds" holds "$(verdict 'MCP srv')"
t_eq "...green" "0 holds" "$(rc) $(state)"
rm -f "$PRIV/confinement-mcp.tsv"
printf '{"projects":{"/some/project":{"mcpServers":{"inproj":{"command":"node","args":["s.js"]}}}}}\n' > "$CJ"
t_eq "a server in a project entry of the user config is inventoried" "does not hold" "$(verdict 'MCP inproj')"
mkdir -p "$PORT_ROOT/harbor"; printf '{"mcpServers":{"inrepo":{"command":"bunx","args":["pkg"]}}}\n' > "$PORT_ROOT/harbor/.mcp.json"
t_has "...and one in a governed repo's .mcp.json" "$(sh "$DW" --mcp 2>/dev/null)" "inrepo	repo harbor	bunx	pkg"
rm -rf "$PORT_ROOT/harbor"; printf '{"mcpServers":{"harbor_chrome":{"command":"python3","args":["-I","x.py"]}}}\n' > "$CJ"
t_eq "CONTROL: back to green" "0 holds" "$(rc) $(state)"

t_section "hooks: a command running a file in the write list does not hold"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"/bin/sh $HOME/.claude/bin/admission-hook.sh"}]}]}}\n' > "$US"
t_eq "an installed hook (under ~/.claude/bin): holds" holds "$(verdict hooks)"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"sh \\"%s/work/hook.sh\\" --x"}]}]}}\n' "$PORT_ROOT" > "$US"
t_eq "a hook script inside PORT_ROOT: does not hold" "does not hold" "$(verdict hooks)"
t_has "...naming the path" "$(row hooks)" "$PORT_ROOT/work/hook.sh"
printf '{}\n' > "$US"
t_eq "CONTROL: removed, holds" holds "$(verdict hooks)"

t_section "launchd jobs: the row follows drift-launchd-wall.sh"
if command -v plutil >/dev/null 2>&1; then
  printf '<plist version="1.0"><dict><key>Label</key><string>com.harbor.t</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>%s/work/j.sh</string></array></dict></plist>\n' "$PORT_ROOT" > "$LA/com.harbor.t.plist"
  t_eq "a job running from the write list: does not hold" "does not hold" "$(verdict 'launchd jobs')"
  t_eq "...and the check is red" 1 "$(rc)"
  printf '<plist version="1.0"><dict><key>Label</key><string>com.harbor.t</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>%s/.claude/bin/j.sh</string></array></dict></plist>\n' "$HOME" > "$LA/com.harbor.t.plist"
  t_eq "pointed at an installed copy: holds" holds "$(verdict 'launchd jobs')"
  rm -f "$LA/com.harbor.t.plist"
else
  t_eq "no plutil: the launchd row is skipped, not faked" "" "$(verdict 'launchd jobs')"
fi

t_section "--probe: a landed canary is the only thing that lowers a hold, and it is removed"
rm -f "$PRIV/harbor.toml"; sh "$INST" >/dev/null 2>&1   # the retry open again, so a refused canary has a config red to not close
RUN="$T_TMP/runner.sh"
printf '#!/bin/sh\n# lands the canary through the edit-write surface only\n[ "$1" = edit-write ] && : > "$2"\nexit 0\n' > "$RUN"; chmod +x "$RUN"
OUT="$(HARBOR_DRIFT_WALL_RUNNER="$RUN" dw --probe)"
t_has "a canary that lands through Edit/Write: does not hold, by probe" "$OUT" "Edit/Write: does not hold (probe) — a canary landed in"
t_has "...in the main folders" "$OUT" "$HOME/Desktop"
t_eq "...every canary is removed" "" "$(find "$HOME" -name '.harbor-wall-canary-*' | head -1)"
t_has "a refused canary through confined Bash: holds, by probe" "$OUT" "confined Bash: holds (probe)"
t_has "a refused canary cannot close the open retry" "$OUT" "retried Bash: does not hold (config)"
printf '#!/bin/sh\nexit 2\n' > "$RUN"
t_has "a runner that cannot drive a surface: the config verdict stands, and says no canary ran" "$(HARBOR_DRIFT_WALL_RUNNER="$RUN" dw --probe)" "canary not run: the runner exited 2 for bash-confined"
t_has "--probe with no runner says so" "$(dw --probe)" "canary not run: HARBOR_DRIFT_WALL_RUNNER names no runner"
t_hasnt "without --probe nothing is written and nothing is claimed as probed" "$(dw)" "(probe)"
t_eq "...no canary left behind by any of it" "" "$(find "$HOME" -name '.harbor-wall-canary-*' | head -1)"

t_section "reads and arguments"
t_eq "--state writes no receipt" absent "$(rm -f "$HARBOR_CHECK_RECEIPTS/drift.wall.json"; state >/dev/null; [ -e "$HARBOR_CHECK_RECEIPTS/drift.wall.json" ] && echo present || echo absent)"
t_exit "an unknown argument is a usage error" 2 sh "$DW" --nope
t_done
