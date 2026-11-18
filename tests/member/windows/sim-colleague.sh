#!/usr/bin/env sh
# sim-colleague.sh (harbor#1278): sourced by sim-windows.sh, which holds the stubs, the profile and the helpers it uses.
# The launcher run-setup.ps1 and the colleague guide, run twice over, when SIM_WINDOWS_COLLEAGUE names the folder that holds them.
# shellcheck shell=sh disable=SC2154,SC2016 # the variables are sim-windows.sh's
# ── 3b. the launcher the colleagues run, twice: 3010, then 4 ──────────────────────────────────────────────────────────────
LAUNCHER="$T_ROOT/colleague/send-to-colleagues/run-setup.ps1"
if [ -f "$LAUNCHER" ]; then
  # launch <profile folder> <account> -> RC, OUT, HASH, DIR: run-setup.ps1 beside the generated setup file, as the zip lays it out, under that Windows profile
  launch_dir() { DIR="$C/Users/$1/Downloads/Claude-setup-x"; rm -rf "$DIR"; mkdir -p "$DIR"; cp "$LAUNCHER" "$DIR/run-setup.ps1"; cp "$SETUP" "$DIR/setup-x.ps1"
    HASH="$(sha256sum < "$DIR/setup-x.ps1" | cut -c1-64)"; printf '%s\n' "$HASH" > "$DIR/HASH.txt"; }
  launch() { RUN=$((RUN + 1)); OUT="$T_TMP/run-$RUN.out"; RC=0; ( cd "$SIM" && pwsh -NonInteractive -File "$DIR/run-setup.ps1" -Sha256 "$HASH" ) > "$OUT" 2>&1 || RC=$?
    printf -- '--- run %s exit %s (launcher)\n' "$RUN" "$RC" >> "$LOG"; }
  RESULT() { cat "$DIR/harbor-setup.result" 2>/dev/null; }
  for _acct in 'Gintar'$(printf '\304\227')'|SIMPC\Gintar'$(printf '\304\227') 'user|SIMPC\user' 'Ona [IT]|SIMPC\Ona'; do
    _p="${_acct%%|*}"; SIM_ME="${_acct#*|}"; export SIM_ME
    t_section "launcher as $SIM_ME, in C:\\Users\\$_p: first run 3010, after a restart 4"
    win_reset; distro_reset; launch_dir "$_p"; launch
    t_eq "run 1: the launcher exits 3010 (194 here)" 194 "$RC"; t_eq "...the result file says 3010" 3010 "$(RESULT)"; t_has "...and it says restart" "$(cat "$OUT")" 'RESULT 3010: restart Windows'
    t_eq "no lock or elevation file is left" '' "$(find "$DIR" -name 'harbor-setup.running' -o -name 'harbor-setup.elevated')"
    t_eq "the log kept one restart note (the guide's count)" 1 "$(grep -c 'WSL needs a restart' "$DIR/harbor-setup.log")"
    t_eq "nothing under C:\\Program Files\\ClaudeCode" no "$([ -e "$CC" ] && echo yes || echo no)"
    reboot; echo on > "$SIM/state/feature"; [ "$(cat "$SIM/state/distro")" != pending ] || echo on > "$SIM/state/distro"
    launch; t_eq "run 2, after the restart: the launcher exits 4" 4 "$RC"; t_eq "...the result file says 4" 4 "$(RESULT)"; t_has "...and it says expected" "$(cat "$OUT")" 'RESULT 4: expected'
    t_eq "the floor landed" yes "$([ -f "$CC/managed-settings.json" ] && echo yes)"
    t_eq "the log, written as UTF-8 under that profile path, holds both runs" 1 "$(grep -c 'WSL needs a restart' "$DIR/harbor-setup.log")"
    t_has "the launcher's last lines include the log's tail" "$(cat "$OUT")" '--- last lines of harbor-setup.log ---'
  done
  unset SIM_ME
  t_section "launcher: the setup fails inside, and the guide's report has what it printed"
  win_reset; distro_reset; launch_dir user; SIM_INSTALL_RC=5; export SIM_INSTALL_RC; launch; unset SIM_INSTALL_RC
  t_eq "a failing setup: exit 1" 1 "$RC"; t_eq "...the result file says 1" 1 "$(RESULT)"; t_has "...naming the log" "$(cat "$OUT")" 'STOP 1: the setup failed'
  t_has "...and the last lines are the setup's own words" "$(cat "$OUT")" 'wsl --install stopped with exit 5'
  t_section "launcher refusals"
  win_reset; distro_reset; launch_dir user; echo x > "$DIR/setup-y.ps1"; launch
  t_eq "two setup files: 10" 10 "$RC"
  win_reset; distro_reset; launch_dir user; HASH=0000; launch; t_eq "a wrong hash: 11" 11 "$RC"; t_eq "...nothing ran" '' "$(seq_of)"
  win_reset; distro_reset; launch_dir user; SIM_NOADMIN=1; export SIM_NOADMIN; launch; unset SIM_NOADMIN; t_eq "not an administrator: 13" 13 "$RC"
  win_reset; distro_reset; echo on > "$SIM/state/feature"; echo on > "$SIM/state/distro"; launch_dir user; launch; t_eq "Ubuntu already on this account: 12" 12 "$RC"
  win_reset; distro_reset; launch_dir user; SIM_UAC=no; export SIM_UAC; launch; unset SIM_UAC; t_eq "the prompt answered No: 15" 15 "$RC"; t_eq "...and the setup never ran: only the list of distros was asked" 'wsl.exe -l -q|' "$(seq_of)"
  # The guide's own commands, as Claude Desktop runs them: in the folder the zip extracted to, in PowerShell 7 (a) directly and (b) as Git Bash would, through
  # powershell.exe -NoProfile -Command '<cmd>'. Run against each shipped zip; whoami and the folder's separators are Linux's here, so those lines are checked by shape.
  GUIDE="$T_ROOT/colleague/send-to-colleagues/INSTALL-FOR-CLAUDE.md"
  g_cmd() { grep -F -- "$1" "$GUIDE" | head -n 1; }   # the first line holding this text: a fenced block's one command
  g_sel() { grep -o '`(Select-String[^`]*`' "$GUIDE" | head -n 1 | tr -d '`'; }   # the 3010 row's inline command
  g_fill() { printf '%s' "$1" | sed -e "s|<HASH>|$GH|g"; }   # the guide's one placeholder: <FOLDER> is gone, the commands are relative
  g_run() { # <form a|b> <command with the placeholders filled> -> GOUT
    case "$2" in *\'*) t_fail "a guide command carries a single quote, which Git Bash's quoting can't carry: $2"; GOUT=''; return ;; esac
    if [ "$1" = a ]; then GOUT="$( cd "$GD" && pwsh -NoProfile -NonInteractive -Command "$2" 2>&1 )"; else GOUT="$( cd "$GD" && sh -c "powershell.exe -NoProfile -Command '$2'" 2>&1 )"; fi;
    if [ "$_n" = gintare ]; then printf '  %s> %s\n' "$1" "$2" | cut -c1-170; printf '%s\n' "$GOUT" | sed -n '1,14p' | sed 's/^/      | /' | cut -c1-170; fi; }
  PINNED="$(grep -E '^[0-9A-Fa-f]{64}$' "$GUIDE" | head -n 1)"
  for _zip in "$T_ROOT"/colleague/zips/Claude-setup-*.zip; do
    _n="${_zip##*Claude-setup-}"; _n="${_n%.zip}"
    for _form in a b; do
      if [ "$_form" = a ]; then _how='PowerShell 7 directly'; else _how="through powershell.exe -Command, as from Git Bash"; fi
      t_section "the colleague guide, $_n's zip: $_how"
      win_reset; distro_reset; _lt="$(printf 'Gintar\304\227')"; GD="$C/Users/$_lt/Downloads/Claude-setup-$_n"; rm -rf "$GD"; mkdir -p "$GD"
      pwsh -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath '$_zip' -DestinationPath '$GD'" > "$T_TMP/unzip.out" 2>&1; t_eq "the zip extracts to its five files" 'CLAUDE.md HASH.txt INSTALL-FOR-CLAUDE.md run-setup.ps1 setup-'"$_n"'.ps1' "$(ls "$GD" | tr '\n' ' ' | sed 's/ $//')"
      GF=''; GH=''
      g_run "$_form" "$(g_cmd 'whoami; (Get-Location).Path')"
      t_eq "step 1: after whoami and the folder, exactly the five files" "$(printf '%s\n' CLAUDE.md HASH.txt INSTALL-FOR-CLAUDE.md run-setup.ps1 "setup-$_n.ps1")" "$(printf '%s\n' "$GOUT" | sed '1,2d' | LC_ALL=C sort)"
      GF="$(printf '%s\n' "$GOUT" | sed -n 2p)"; t_eq "step 1: line 2 is the folder" "$GD" "$GF"; t_eq "no command in the guide still names <FOLDER>" 0 "$(grep -c '<FOLDER>' "$GUIDE")"
      t_eq "step 1: line 1 is whoami's (the sim's is Linux's: a bare name)" 1 "$(printf '%s\n' "$GOUT" | sed -n 1p | grep -c .)"
      g_run "$_form" "$(g_fill "$(g_cmd 'Get-ChildItem -LiteralPath "." -Filter')")"
      t_eq "step 2: exactly one setup file, its name alone" "setup-$_n.ps1" "$GOUT"
      g_run "$_form" "$(g_fill "$(g_cmd 'Get-FileHash -Algorithm SHA256 -LiteralPath ".\run-setup.ps1')")"
      t_eq "step 2: the launcher's hash is the one pinned in the guide (case aside)" "$(printf '%s' "$PINNED" | tr a-f A-F)" "$(printf '%s' "$GOUT" | tr a-f A-F)"
      g_run "$_form" "$(g_fill "$(g_cmd 'Get-Content -LiteralPath ".\HASH.txt"')")"
      t_eq "step 3: HASH.txt is one line of 64 hex characters" 1 "$(printf '%s\n' "$GOUT" | grep -cE '^[0-9a-fA-F]{64}$')"
      t_eq "...and it is the setup file's sha256" "$(sha256sum < "$GD/setup-$_n.ps1" | cut -c1-64)" "$GOUT"
      GH="$GOUT"
      g_run "$_form" "$(g_fill "$(g_cmd 'Get-Content -LiteralPath ".\harbor-setup.result"')")"
      t_eq "step 3: before the run, the result read prints nothing and is no error" '' "$GOUT"
      if [ "$_form" = a ] || [ "$_n" = gintare ]; then
        g_run "$_form" "$(g_fill "$(g_cmd 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File')")"
        t_has "step 3: the run ends RESULT 3010 on a laptop without WSL" "$GOUT" 'RESULT 3010: restart Windows'
        g_run "$_form" "$(g_fill "$(g_cmd 'Get-Content -LiteralPath ".\harbor-setup.result"')")"
        t_eq "step 3: the result read now prints the number" 3010 "$GOUT"
        g_run "$_form" "$(g_fill "$(g_sel)")"
        t_eq "step 4: the 3010 row's Select-String count is 1 after the first run" 1 "$GOUT"
      fi
    done
  done
else
  printf '  note: SIM_WINDOWS_COLLEAGUE not given, so the launcher and the colleague guide are unchecked\n'
fi
