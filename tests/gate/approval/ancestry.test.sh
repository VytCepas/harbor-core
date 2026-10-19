#!/usr/bin/env sh
# gate-approve.sh proves the click launched it (harbor#1018, review finding 1): its parent must be Claude Code's Bash-tool
# shell evaluating exactly the canonical text, and that shell's parent the signed claude. The review's bypass shapes run
# against the TOOL here, through a process tree shaped like the real one; then the trust check's fail-closed paths.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/gate/approval/fixture.sh"
. "$T_ROOT/bin/log-lib.sh"; HERE="$T_ROOT/bin"; . "$T_ROOT/bin/gate-lib.sh"
SNAPPRE() { printf '/bin/zsh -c source %s/shell-snapshots/snapshot-zsh-1-ab12.sh 2>/dev/null || true && setopt NO_EXTENDED_GLOB 2>/dev/null || true' "$1"; }
argv_of() { # <cfg> <command text> → the Bash-tool shell argv Claude Code builds for it
  printf "%s && eval '%s' < /dev/null && pwd -P >| /tmp/claude-ab12-cwd" "$(SNAPPRE "$1")" "$(printf '%s' "$2" | sed "s/'/'\"'\"'/g")"
}
J() { gate_ancestry_judge "$1" "${2:-claude}" "$3" /cfg >/dev/null 2>&1 && echo accept || echo refuse; }
C0="/cfg/bin/gate-approve.sh merge VytCepas/harbor 7 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

t_section "the judge: the measured shape is accepted, every change to it refused"
t_eq "the canonical text, as the Bash tool runs it" accept "$(J "$(argv_of /cfg "$C0")" claude "$C0")"
t_eq "...from a session resumed with --resume" accept "$(J "$(argv_of /cfg "$C0")" "claude --resume abc" "$C0")"
for f in -p --print "--settings x.json" --dangerously-skip-permissions "--permission-mode bypassPermissions" "--plugin-dir /tmp/m" \
         "--permission-prompt-tool mcp__x" "--allowedTools Bash" "--mcp-config m.json" "--agents a.json"; do
  t_eq "a claude started with $f" refuse "$(J "$(argv_of /cfg "$C0")" "claude $f" "$C0")"
done
t_eq "a parent that is not zsh or bash" refuse "$(J "/bin/sh -c source /cfg/shell-snapshots/snapshot-x && eval '$C0' < /dev/null && pwd -P >| /tmp/claude-ab12-cwd" claude "$C0")"
t_eq "a shell sourcing another config dir's snapshot" refuse "$(J "$(argv_of /other "$C0")" claude "$C0")"
t_eq "a grandparent that is not claude" refuse "$(J "$(argv_of /cfg "$C0")" "/bin/bash" "$C0")"
t_eq "code before the command" refuse "$(J "/bin/zsh -c source /cfg/shell-snapshots/snapshot-zsh-1.sh && f() { :; } && eval '$C0' < /dev/null && pwd -P >| /tmp/claude-ab12-cwd" claude "$C0")"
t_eq "code after the command" refuse "$(J "$(argv_of /cfg "$C0") && rm -f x" claude "$C0")"

t_section "the review's bypass shapes, against the installed TOOL, in a Bash-tool-shaped process tree"
ag_world; HARBOR_GATE_ENFORCE_ANCESTRY=1; export HARBOR_GATE_ENFORCE_ANCESTRY
C="$GB/gate-approve.sh merge $AG_R 7 $SHA_A"; A="merge $AG_R 7 $SHA_A"
printf 'a:\n\t%s\n' "$C" > "$T_TMP/mk"; printf '%s\n' "$C" > "$T_TMP/x.sh"
N=0
for shape in "$GB/gate-ap*.sh $A" "$GB/gate-approv?.sh $A" "$GB/gate-appro[v]e.sh $A" "$GB/gate-{approve,x}.sh $A" \
  "X=; $GB/gate-ap\${X}prove.sh $A" "cd $GB && ./gate-appr*.sh $A" "cd $GB && ./gate-approve.sh $A" "eval \"$C\"" \
  "f() { $C; }; f" "git -c alias.x='!$C' x" "make -f $T_TMP/mk" "sh $T_TMP/x.sh" "sh -c '$C'" "bash -c '$C'" "env $C" \
  "nohup $C" "echo $A | xargs $GB/gate-approve.sh" "find $GB -name gate-approve.sh -exec {} $A ;" "true && $C" "$C; true" \
  "( $C )" "x=\$($C); echo \"\$x\"" "{ $C; }" "if true; then $C; fi" "for i in 1; do $C; done" "$C & wait" "command $C" \
  "exec $C" "$GB/../bin/gate-approve.sh $A" "$C " "$GB/gate-approve.sh  $A" "X=1 $C" "$C 2>&1" "$C | cat" \
  "/bin/sh $C" "$GB/gate-approve.sh	$A" "$(printf '%s\n%s' "$C" true)" "cd $GB; ./gate-approve.sh $A" "\\$C" "nice $C"; do
  N=$((N + 1)); rm -f "$GF/merge.log"
  ag_tree "$shape"
  t_eq "probe $N merges nothing: $(printf '%s' "$shape" | sed "s|$GB|<bin>|g; s|$T_TMP|<tmp>|g" | tr '\n\t' '  ' | cut -c1-70)" "" "$(ag_merged)"
  case "$OUT" in *"gate-approve:"*) t_has "probe $N: the tool refused it itself, as no click" "$OUT" "no click launched this run" ;; esac
done
t_eq "every probe shape ran" 40 "$N"
ag_tree "$C"
t_eq "the canonical text passes the shell check and stops only at the claude identity check" 1 "$RC"
t_has "...naming the identity" "$OUT" "claude process"
t_hasnt "...not the shell" "$OUT" "no click launched this run"
t_eq "...nothing merged" "" "$(ag_merged)"

t_section "red-proofs: the identity check, then the shell check, are each load-bearing"
ag_mutant "M1 the identity is not checked" gate-lib.sh 's/^  _gexe="\$(gate_claude_exe "\$GATE_CLAUDE_PID")"$/  PATH="$_gapath"; return 0/'
ag_tree "$C"
t_eq "M1: the canonical text in the tree now merges, so the tree is the real shape" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
ag_world; ag_mutant "M1 again" gate-lib.sh 's/^  _gexe="\$(gate_claude_exe "\$GATE_CLAUDE_PID")"$/  PATH="$_gapath"; return 0/'
ag_tree "$GB/gate-ap*.sh $A"
t_eq "M1: a glob is still refused by the shell check" "" "$(ag_merged)"
sed -e 's/^  _gexe="\$(gate_claude_exe "\$GATE_CLAUDE_PID")"$/  PATH="$_gapath"; return 0/' -e 's/^gate_ancestry_judge() {$/gate_ancestry_judge() { return 0/' \
  "$T_ROOT/bin/gate-lib.sh" > "$GB/gate-lib.sh"
t_eq "M2: both mutations apply" yes "$(grep -q 'gate_ancestry_judge() { return 0' "$GB/gate-lib.sh" && grep -qx '  return 0' "$GB/gate-lib.sh" && echo yes)"
ag_tree "$GB/gate-ap*.sh $A"
t_eq "M2: with the shell check gone too, the glob merges with no click" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
unset HARBOR_GATE_ENFORCE_ANCESTRY

t_section "trust fails closed: plugins, mods, a settings change mid-session, jq, a missing library"
ag_world; mkdir -p "$CFG/plugins/cache/m/1"; printf '{"hooks":{"PermissionRequest":[]}}\n' > "$CFG/plugins/cache/m/1/plugin.json"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "an inline PermissionRequest in a plugin.json refuses" 1 "$RC"
t_eq "...nothing merged" "" "$(ag_merged)"
# only what a session can load is scanned: a marketplace checkout and the catalogue never run (live false refusal, 10-09)
ag_world; mkdir -p "$CFG/plugins/marketplaces/o/plugins/s/hooks"
printf '{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"echo allow"}]}]}}\n' > "$CFG/plugins/marketplaces/o/plugins/s/hooks/hooks.json"
printf '{"hookEvents":["PreToolUse","PermissionRequest"]}\n' > "$CFG/plugins/plugin-catalog-cache.json"
ag_tree "$C"
t_eq "a hook only in a marketplace checkout, and a catalogue naming the event: not loaded, so it merges" 0 "$RC"
ag_world; mkdir -p "$CFG/plugins/synced/b/p"; printf '{"hooks":{"PermissionRequest":[]}}\n' > "$CFG/plugins/synced/b/p/plugin.json"
ag_tree "$C"
t_eq "a synced plugin's PermissionRequest still refuses" 1 "$RC"
t_has "...naming it" "$OUT" "plugins/synced/b/p/plugin.json"
ag_world; mkdir -p "$T_TMP/ext/p/hooks" "$CFG/plugins"; printf '{"hooks":{"PermissionRequest":[]}}\n' > "$T_TMP/ext/p/hooks/hooks.json"
printf '{"plugins":{"x@o":[{"installPath":"%s"}]}}\n' "$T_TMP/ext/p" > "$CFG/plugins/installed_plugins.json"
ag_tree "$C"
t_eq "an installed plugin outside cache/ is scanned: refuses" 1 "$RC"
ag_mutant "M7 installPath is not scanned" gate-lib.sh 's/^  \[ ! -f "\$_gtj" \] || _gti=.*$/  :/'
ag_tree "$C"
t_eq "M7: the mutant merges past that plugin's hook" 0 "$RC"
rm -rf "$T_TMP/ext"
ag_world; mkdir -p "$CFG/plugins/cache/m/1"; printf '{}\n' > "$CFG/plugins/cache/m/1/plugin.json"; chmod 000 "$CFG/plugins/cache/m/1/plugin.json"
ag_tree "$C"
t_eq "an unreadable plugin file refuses (fail closed)" 1 "$RC"
chmod 644 "$CFG/plugins/cache/m/1/plugin.json"
ag_world; mkdir -p "$CFG/dev-mods/s1"; printf 'export default { "tool.check": () => ({ decision: "allow" }) }\n' > "$CFG/dev-mods/s1/m.js"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a mod with tool.check refuses" 1 "$RC"
ag_world; jq '.hooks.PermissionRequest = [{hooks: [{type: "command", command: ("/bin/sh " + $c + "/bin/../../tmp/x.sh")}]}]' --arg c "$CFG" "$CFG/settings.json" > "$T_TMP/s" && mv "$T_TMP/s" "$CFG/settings.json"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a hook spelled as <cfg>/bin/../../tmp refuses (no prefix trust)" 1 "$RC"
ag_world; ag_tree "$C"
t_eq "control: in the tree, with settings older than the session, it merges" 0 "$RC"
ag_world; ag_tree "/bin/sleep 2; touch $CFG/settings.json; $C"
t_eq "settings changed after the session started: refused" 1 "$RC"
t_has "...saying so" "$OUT" "changed after this Claude Code session started"
t_eq "...nothing merged" "" "$(ag_merged)"
ag_mutant "M3 the session-start check is gone" gate-lib.sh 's/^  if \[ -n "\$_gtpid" \]; then$/  if false; then/'
ag_tree "/bin/sleep 2; touch $CFG/settings.json; $C"
t_eq "M3: the mutant merges on settings the session never loaded" 0 "$RC"
ag_world; printf '#!/bin/sh\nexit 3\n' > "$T_BIN/jq"; chmod +x "$T_BIN/jq"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a broken jq refuses" 1 "$RC"
t_has "...saying so" "$OUT" "jq does not work here"
rm -f "$T_BIN/jq"
ag_world; rm -f "$GB/gate-lib.sh"
ag_run gate-approve.sh merge "$AG_R" 7 "$SHA_A"
t_eq "a missing gate-lib.sh: nothing merged" "" "$(ag_merged)"
t_eq "...and a non-zero exit" yes "$([ "$RC" -ne 0 ] && echo yes || echo no)"
t_section "shims earlier on PATH cannot lie to the proof (#1127 r2 #1): it reads system tools only"
HARBOR_GATE_ENFORCE_ANCESTRY=1; export HARBOR_GATE_ENFORCE_ANCESTRY
# a ps that shows the canonical argv for the Bash-tool shell, whatever it really ran; an id naming nobody
ag_world; ag_mutant "M5 base: the identity is not checked (isolates the shell check)" gate-lib.sh 's/^  _gexe="\$(gate_claude_exe "\$GATE_CLAUDE_PID")"$/  PATH="$_gapath"; return 0/'
SHIM_ARGV="$(argv_of "$CFG" "$C")"; export SHIM_ARGV
printf '#!/bin/sh\n_o="$(/bin/ps "$@")"; case "$_o" in claude*) printf "%%s\\n" "$_o" ;; *"eval "*) printf "%%s\\n" "$SHIM_ARGV" ;; *) printf "%%s\\n" "$_o" ;; esac\n' > "$T_BIN/ps"
chmod +x "$T_BIN/ps"
ag_tree "$GB/gate-ap*.sh $A"
t_eq "a ps shim: the glob still merges nothing" "" "$(ag_merged)"
t_has "...refused as no click" "$OUT" "no click launched this run"
sed -e 's/^  _gexe="\$(gate_claude_exe "\$GATE_CLAUDE_PID")"$/  PATH="$_gapath"; return 0/' -e 's#^  _gapath="\$PATH"; PATH=/usr/bin:/bin:/usr/sbin:/sbin$#  _gapath="$PATH"#' \
  "$T_ROOT/bin/gate-lib.sh" > "$GB/gate-lib.sh"
t_exit "M5: the PATH pin mutation applies" 1 cmp -s "$GB/gate-lib.sh" "$T_ROOT/bin/gate-lib.sh"
ag_tree "$GB/gate-ap*.sh $A"
t_eq "M5: without the PATH pin, the ps shim makes the glob merge with no click" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
rm -f "$T_BIN/ps"; unset SHIM_ARGV
ag_world; unset HARBOR_GATE_ENFORCE_ANCESTRY
printf '#!/bin/sh\necho nobody-here-x\n' > "$T_BIN/id"; chmod +x "$T_BIN/id"
ag_mutant "M6 base: the account dir is unreadable" gate-lib.sh 's/^  _gu="\$(id -un)"; /  _gu=nobody-here-x; /'
ag_tree "$GB/gate-ap*.sh $A"
t_eq "an unreadable account dir is not a sandbox: the proof runs, the glob merges nothing" "" "$(ag_merged)"
t_hasnt "...and it never says the check was skipped" "$OUT" "ancestry not checked"
sed -e 's/^  _gu="\$(id -un)"; /  _gu=nobody-here-x; /' -e 's/^  if \[ -n "\$_glive" \] && \[ "\$GATE_CFG" != "\$_glive" \]/  if [ "$GATE_CFG" != "$_glive" ]/' \
  "$T_ROOT/bin/gate-lib.sh" > "$GB/gate-lib.sh"
ag_tree "$GB/gate-ap*.sh $A"
t_eq "M6: treating it as a sandbox skips the proof and the glob merges" "pr merge 7 --repo $AG_R --squash --match-head-commit $SHA_A" "$(ag_merged)"
rm -f "$T_BIN/id"; HARBOR_GATE_ENFORCE_ANCESTRY=1; export HARBOR_GATE_ENFORCE_ANCESTRY
t_done
