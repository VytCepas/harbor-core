#!/usr/bin/env sh
# renew-check.sh and the statusline token fleet-glyph.sh renders from its cache (harbor#44,
# #557). The checkout is a fixture with a controllable origin/main, so the behind-count is
# testable. Case 4 matters most: with no checkout the tool must say so, never report zero.
. "$(dirname "$0")/../lib/core.sh"; t_init
T="$T_TMP/rc"; CFG="$T/cfg"; REPO="$T/repo"; AG="$HOME/Library/LaunchAgents"
mkdir -p "$CFG" "$REPO/bin" "$REPO/launchd" "$AG"
g() { git -C "$REPO" "$@"; }
g init -q; g config user.email t@t; g config user.name t; g config commit.gpgsign false
printf 'v1\n' > "$REPO/bin/thing.sh"
# The live payload shapes: single quotes in floor-install, double in runtime-install, shared.sh in both.
printf "GUARDS='thing.sh'\nRECOVERY='shared.sh'\n" > "$REPO/bin/floor-install.sh"
printf 'FILES="rt.sh shared.sh"\nREFRESH_ONLY="ro.sh"\nSUITE="tests/x/s-test.sh:bin/s-test.sh tests/lib/core.sh:lib/core.sh"\n' > "$REPO/bin/runtime-install.sh"
for _f in shared.sh rt.sh ro.sh unowned.sh; do printf 'v1\n' > "$REPO/bin/$_f"; done
mkdir -p "$REPO/tests/x" "$REPO/tests/lib" "$REPO/lib"
for _f in tests/x/s-test.sh tests/x/other-test.sh tests/lib/core.sh lib/core.sh; do printf 'v1\n' > "$REPO/$_f"; done
printf 'C v1\n' > "$REPO/CONSTITUTION.md"
g add -A >/dev/null; g commit -qm base
BASE="$(g rev-parse HEAD)"; g update-ref refs/remotes/origin/main "$BASE"
: > "$REPO/launchd/com.harbor.one.plist"
publish() { g update-ref refs/remotes/origin/main "$(g rev-parse HEAD)"; }  # origin/main := HEAD
stamp() { printf 'floor-install %s x %s\nruntime-install %s x %s\n' "$1" "$1" "$1" "$1" > "$CFG/.helm-install-stamp"; }
provision() { # a fully deployed box; the constitution comes from origin/main, never the tree
  stamp "$BASE"; : > "$CFG/.helm-instructions.sha256"; : > "$CFG/.helm-judge"
  cp "$REPO/launchd/com.harbor.one.plist" "$AG/"
  g show origin/main:CONSTITUTION.md > "$CFG/CLAUDE.md.t" 2>/dev/null && mv "$CFG/CLAUDE.md.t" "$CFG/CLAUDE.md" || rm -f "$CFG/CLAUDE.md.t"
}
# The launchd cases run as macOS whatever the host is; 2b runs the same checks as Linux (harbor#618).
UD="$T/uname-darwin"; mkdir -p "$UD"; printf '#!/bin/sh\necho Darwin\n' > "$UD/uname"; chmod +x "$UD/uname"
run() { PATH="$UD:$PATH" HARBOR_RENEW_DAEMONS="$T/daemons" HARBOR_REPO="$REPO" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG" "$@" 2>/dev/null; }
head1() { run "$@" | head -1; }

t_section "1 · a fully deployed box reports renew 0"
provision
t_eq "a deployed box" "renew 0" "$(head1)"

t_section "2 · a job built here and on no schedule"
provision; rm -f "$AG/com.harbor.one.plist"
t_has "a missing LaunchAgent" "$(head1)" "jobs1"

t_section "2a · a private layer's jobs/ is a second source of built plists (harbor#1149)"
PJ="$T/pv/jobs"; mkdir -p "$PJ"; : > "$PJ/com.harbor.acme.plist"
provision
t_eq "a private plist built and not installed counts" "renew 1 jobs1" "$(HARBOR_SCOPE_PRIVATE="$T/pv" head1)"
t_eq "...and with no layer named it does not" "renew 0" "$(HARBOR_SCOPE_PRIVATE="$T/nowhere" head1)"
cp "$PJ/com.harbor.acme.plist" "$AG/"
t_eq "...installed, it counts for nothing" "renew 0" "$(HARBOR_SCOPE_PRIVATE="$T/pv" head1)"
rm -f "$AG/com.harbor.acme.plist"; rm -f "$REPO/launchd/com.harbor.one.plist" "$AG/com.harbor.one.plist"
t_eq "...and with core's plist gone, the private one still counts, once" "renew 1 jobs1" "$(HARBOR_SCOPE_PRIVATE="$T/pv" head1)"
: > "$REPO/launchd/com.harbor.one.plist"

t_section "2b · Linux: the footprint is systemd/ against ~/.config/systemd/user, never LaunchAgents (harbor#618)"
UX="$T/uname-linux"; mkdir -p "$UX"; printf '#!/bin/sh\necho Linux\n' > "$UX/uname"; chmod +x "$UX/uname"
SU="$HOME/.config/systemd/user"; mkdir -p "$REPO/systemd" "$SU"
: > "$REPO/systemd/harbor-one.service"; : > "$REPO/systemd/harbor-one.timer"
lrun() { PATH="$UX:$PATH" HARBOR_REPO="$REPO" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG" "$@" 2>/dev/null; }
provision; rm -f "$AG/com.harbor.one.plist"; cp "$REPO/systemd/harbor-one.timer" "$SU/"
t_eq "a Linux box with its timer installed and no LaunchAgents" "renew 0" "$(lrun | head -1)"
rm -f "$SU/harbor-one.timer"
t_has "a Linux box missing a timer built here" "$(lrun | head -1)" "jobs1"
t_has "...whose listing names systemd/, not launchd/" "$(lrun)" "systemd/*.timer"
provision; rm -f "$CFG/.helm-judge"
t_has "Linux: the never-written judge's remedy is the systemd timer" "$(lrun)" "systemctl --user enable --now harbor-judge.timer"
rm -rf "$REPO/systemd" "$SU"

t_section "2c · a system daemon is installed, and a plist that declares itself inert is not a missed job (false alarm: STALE jobs4)"
DM="$T/daemons"; mkdir -p "$DM"
provision; rm -f "$AG/com.harbor.one.plist"
: > "$REPO/launchd/com.harbor.daemon.plist"; printf '<!-- harbor:shipped-inert -->\n' > "$REPO/launchd/com.harbor.inert.plist"
t_eq "built here, in no agent dir, no daemon dir, no marker: two missed, the inert one not" "renew 1 jobs2" "$(head1)"
cp "$REPO/launchd/com.harbor.one.plist" "$AG/"
t_eq "the agent plist installed leaves only the daemon one" "renew 1 jobs1" "$(head1)"
cp "$REPO/launchd/com.harbor.daemon.plist" "$DM/"
t_eq "the daemon plist found in the system daemon dir is installed, the inert one is skipped" "renew 0" "$(head1)"
: > "$REPO/launchd/com.harbor.forgotten.plist"
t_eq "a genuinely uninstalled agent plist is still reported" "renew 1 jobs1" "$(head1)"
t_has "...and the listing a human runs skips the daemon and the inert one" "$(run)" "grep -q harbor:shipped-inert"
rm -f "$REPO/launchd/com.harbor.forgotten.plist" "$REPO/launchd/com.harbor.daemon.plist" "$REPO/launchd/com.harbor.inert.plist" "$DM/com.harbor.daemon.plist"

t_section "3 · an installed floor behind the checkout counts commits, not files"
provision
printf 'v2\n' > "$REPO/bin/thing.sh"; g commit -qam next >/dev/null; publish
_l="$(head1)"
t_has "the behind-count" "$_l" "floor1"
t_hasnt "a floor-only payload commit raises no runtime token" "$_l" "runtime"
printf 'x\n' > "$REPO/README.md"; g add -A >/dev/null; g commit -qm docs >/dev/null; publish
t_has "a docs commit does not move the count" "$(head1)" "floor1"

t_section "3b · a bin/ commit in no installer payload must not move the number"
# The pathspec was `bin/ hooks/` and read STALE floor5 off runtime-only commits (2026-08-24).
provision; stamp "$(g rev-parse HEAD)"
printf 'v2\n' > "$REPO/bin/unowned.sh"; mkdir -p "$REPO/hooks"; printf 'v2\n' > "$REPO/hooks/pre-commit"
g add -A >/dev/null; g commit -qm unowned >/dev/null; publish
t_eq "a commit to no installer's payload" "renew 0" "$(head1)"

t_section "3c · an installer whose payload cannot be read stands down"
provision
cp "$REPO/bin/floor-install.sh" "$T/floor-install.sh.bak"
printf '# no payload declared here\n' > "$REPO/bin/floor-install.sh"
_l="$(head1)"
t_has "an unreadable payload stands down" "$_l" "floor?"
t_hasnt "and is not a clean box" "$_l" "renew 0"
cp "$T/floor-install.sh.bak" "$REPO/bin/floor-install.sh"

t_section "3d · the running constitution: behind, redeployed, hand-edited, unreadable (harbor#557)"
provision
t_hasnt "a deployed constitution raises no token" "$(head1)" "const"
printf 'C v2\n' > "$REPO/CONSTITUTION.md"; g commit -qam const2 >/dev/null; publish
t_has "one undeployed commit" "$(head1)" "const1"
printf 'C v3\n' > "$REPO/CONSTITUTION.md"; g commit -qam const3 >/dev/null; publish
t_has "the distance advances to 2" "$(head1)" "const2"
# A capped walk must not fall through to const+, whose remedy is a back-port, not a deploy.
_l="$(HARBOR_REPO="$REPO" HARBOR_CONST_WALK_MAX=1 env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG" 2>/dev/null | head -1)"
t_has "a truncated walk stands down" "$_l" "const?"
t_hasnt "a truncated walk is not unsourced live text" "$_l" "const+"
g show origin/main:CONSTITUTION.md > "$CFG/CLAUDE.md"
t_hasnt "green again after deploying the merged text" "$(head1)" "const"
printf 'y\n' >> "$REPO/README.md"; g add -A >/dev/null; g commit -qm unrelated >/dev/null; publish
t_hasnt "an unrelated commit raises no constitution token" "$(head1)" "const"

t_section "3e · a live file matching no commit asks for a back-port, never a deploy"
printf 'hand-written doctrine in no commit\n' >> "$CFG/CLAUDE.md"
_l="$(head1)"
t_has "unsourced live text" "$_l" "const+"
t_eq "it is not a behind-count, whose remedy would destroy it" 0 "$(printf '%s\n' "$_l" | grep -cE 'const[0-9]')"
_bp="$(run | grep 'matches NO commit')"
t_has "the back-port detail line is printed" "$_bp" "matches NO commit"
t_has "another finding's remedy does offer --apply" "$(run)" "--apply"
t_hasnt "the back-port line offers no deploy" "$_bp" "--apply"

t_section "3f · a config dir that has never been deployed to"
provision; rm -f "$CFG/CLAUDE.md"
t_has "never deployed" "$(head1)" "const!"

t_section "3g · no CONSTITUTION.md on origin/main: say so, never identical"
provision
g rm -q CONSTITUTION.md >/dev/null; g commit -qm drop >/dev/null; publish
_l="$(head1)"
t_has "an absent CONSTITUTION.md stands down" "$_l" "const?"
t_hasnt "and is not a clean box" "$_l" "renew 0"
printf 'C v3\n' > "$REPO/CONSTITUTION.md"; g add -A >/dev/null; g commit -qm restore >/dev/null; publish
provision
t_hasnt "the fixture comes back clean" "$(head1)" "const"

t_section "3h · runtime-install's SUITE pairs count by their checkout path (harbor#727)"
provision; stamp "$(g rev-parse HEAD)"
printf 'v2\n' > "$REPO/tests/lib/core.sh"; g commit -qam suite-harness >/dev/null; publish
_l="$(head1)"
t_has "a commit to a SUITE file is a runtime payload commit" "$_l" "runtime1"
printf 'v2\n' > "$REPO/tests/x/other-test.sh"; printf 'v2\n' > "$REPO/lib/core.sh"
g commit -qam not-suite >/dev/null; publish
_l="$(head1)"
t_has "a tests/ file outside SUITE, or the config-dir name, does not move it" "$_l" "runtime1"
t_hasnt "...so it is still one commit" "$_l" "runtime2"

t_section "4 · no checkout: say so, never up to date"
provision
_l="$(HARBOR_REPO="$T/nope" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG" 2>/dev/null | head -1)"
t_has "an absent checkout stands down loudly" "$_l" "repo?"
t_hasnt "and is not a clean box" "$_l" "renew 0"

t_section "4b · a git worktree is a checkout too (.git is a file there)"
provision
g worktree add -q "$T/wt" -b wtbranch 2>/dev/null
t_hasnt "a worktree is not 'no checkout'" "$(HARBOR_REPO="$T/wt" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG" 2>/dev/null | head -1)" "repo?"

t_section "5 · the judge's cache: absent vs stopped"
provision; rm -f "$CFG/.helm-judge"
t_has "a never-written judge cache" "$(head1)" "judge!"
provision; touch -t 202601010000 "$CFG/.helm-judge"
t_has "a stopped judge cache" "$(head1)" "judge?"
provision; rm -f "$CFG/.helm-judge"
t_has "macOS: the never-written judge's remedy renders the plist template (harbor#630)" "$(run)" "sh $REPO/bin/launchd-render.sh $REPO/launchd/com.harbor.judge.plist > ~/Library/LaunchAgents/com.harbor.judge.plist"
t_hasnt "…and no longer cp's it, which would install the placeholders" "$(run)" "cp $REPO/launchd/com.harbor.judge.plist"

t_section "6 · unpinned instruction surfaces"
provision; rm -f "$CFG/.helm-instructions.sha256"
t_has "unpinned surfaces" "$(head1)" "pin!"

t_section "7 · --apply writes the cache, a dry run does not"
provision; rm -f "$CFG/.helm-renew"
run >/dev/null
t_eq "a dry run wrote no cache" no "$([ -f "$CFG/.helm-renew" ] && echo yes || echo no)"
run --apply >/dev/null
t_eq "--apply wrote the cache" yes "$([ -f "$CFG/.helm-renew" ] && echo yes || echo no)"
t_eq "...and keeps no run log: its --apply runs every scheduled tick (IL_LOG=0)" no "$([ -e "$CFG/backups" ] && echo yes || echo no)"
# The sandbox HOME's .claude must exist, or the not-a-directory refusal answers instead.
mkdir -p "$HOME/.claude"
rclive() { env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" "$@"; }
t_exit "the live dir named by --dir, with --apply and no --live, is refused (install-lib's il_target)" 1 rclive --dir "$HOME/.claude" --apply
t_has "the refusal names the gate" "$(rclive --dir "$HOME/.claude" --apply 2>&1)" "refusing the live dir without an explicit --live"
t_eq "nothing was written to the live dir" no "$([ -f "$HOME/.claude/.helm-renew" ] && echo yes || echo no)"
t_exit "a positional target is a usage error: there is none (harbor#800)" 2 rclive "$CFG"
# Its scheduled caller, fleet-snapshot-refresh.sh, names a sandbox by --dir (harbor#800). The orchestrator
# is absent here, so the job ends in its one FAIL; renew-check ran before it.
provision; rm -f "$CFG/.helm-renew"
_fs="$(CLAUDE_CONFIG_DIR="$CFG" HARBOR_REPO="$REPO" HARBOR_ORCH_BIN="$T/no-orchestrator" HARBOR_CACHE_DIR="$T/cache" \
  sh "$T_ROOT/bin/fleet-snapshot-refresh.sh" 2>&1)"
t_eq "the refresher writes a sandbox's renew cache through renew-check --dir" yes "$([ -f "$CFG/.helm-renew" ] && echo yes || echo no)"
t_has "...and its own failure is a FAIL line with its fix (CONTRACTS/logging.md)" "$(printf '%s\n' "$_fs" | grep -A1 '^  FAIL: ')" "  fix: none automatic — see fleet"
t_exit "a CLAUDE_CONFIG_DIR naming another dir is a usage error: it never picks the target" 2 \
  env CLAUDE_CONFIG_DIR="$T" sh "$T_ROOT/bin/renew-check.sh" --dir "$CFG"
# Linux (harbor#618): no launchctl, so the watch counts harbor-*.timer units and asks systemctl which run.
. "$T_ROOT/tests/lib/linux-sim.sh"; LX="$T/lxpath"; linux_path "$LX" launchctl systemctl uname
cp "$UX/uname" "$LX/uname"
printf '#!/bin/sh\n[ "$4" = harbor-one.timer ]\n' > "$LX/systemctl"; chmod +x "$LX/systemctl"
SU="$HOME/.config/systemd/user"; mkdir -p "$SU"; : > "$SU/harbor-one.timer"; : > "$SU/harbor-two.timer"
rm -f "$CFG/.helm-watch"
( PATH="$LX"; export PATH; CLAUDE_CONFIG_DIR="$CFG" HARBOR_REPO="$REPO" HARBOR_ORCH_BIN="$T/no-orchestrator" \
  HARBOR_CACHE_DIR="$T/cache" sh "$T_ROOT/bin/fleet-snapshot-refresh.sh" >/dev/null 2>&1 )
t_eq "Linux: the refresher's watch is active timers over installed ones" "watch 1 2" "$(cat "$CFG/.helm-watch" 2>/dev/null)"
rm -rf "$SU"

t_section "8 · the statusline renders it as STALE, and renders nothing at zero (harbor#293)"
glyph() { printf '{}' | HARBOR_GLYPH_MACHINE=0 CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$T/nocache" sh "$T_ROOT/bin/fleet-glyph.sh" 2>/dev/null; }
printf 'renew 3 floor11·jobs1\n' > "$CFG/.helm-renew"
_s="$(glyph)"
t_has "the token is rendered verbatim" "$_s" "STALE floor11·jobs1"
t_hasnt "the redundant count stays off the row" "$_s" "renew 3"
# Token shapes, not bare words: a branch named fix/renew-check-... must not decide the verdict.
printf 'renew 0\n' > "$CFG/.helm-renew"; _s="$(glyph)"
t_eq "zero prints no STALE token" 0 "$(printf '%s\n' "$_s" | grep -cE 'STALE [a-z]|renew [0-9]')"
rm -f "$CFG/.helm-renew"; _s="$(glyph)"
t_eq "an absent cache invents no number" 0 "$(printf '%s\n' "$_s" | grep -cE 'STALE [a-z]|renew [0-9]')"

t_section "9 · the props token: rendered above zero, silent at zero"
printf 'props 2\n' > "$CFG/.helm-props"
t_has "props 2 is rendered" "$(glyph)" "props 2"
printf 'props 0\n' > "$CFG/.helm-props"
t_hasnt "props 0 is not" "$(glyph)" "props"

t_section "10 · the two install remedies print in the order that does not lock you out"
# floor-install writes the pins and runtime-install replaces pinned files, so floor goes last.
provision
printf 'v3\n' > "$REPO/bin/shared.sh"; g commit -qam third >/dev/null; publish
stamp "$BASE"
_ord="$(run | grep -oE '(floor|runtime)-install is [0-9]+ payload' | sed -E 's/ is .*//')"
t_eq "both installers are reported behind" 2 "$(printf '%s\n' "$_ord" | grep -c .)"
t_eq "runtime-install is printed first" runtime-install "$(printf '%s\n' "$_ord" | head -1)"
t_section "11 · every fix is aimed at the box it measured (harbor#800)"
CFGP="$(cd -P "$CFG" && pwd -P)"
live() { HARBOR_REPO="$REPO" env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/renew-check.sh" --live 2>/dev/null; }
mirror() { rm -rf "$HOME/.claude"; mkdir -p "$HOME/.claude"; cp -R "$CFG/." "$HOME/.claude/"; }  # the sandbox HOME's live dir := $CFG
provision; rm -f "$CFG/.helm-instructions.sha256"
_o="$(run)"
t_has "a sandbox's re-pin fix names the sandbox, --dir spelled" "$_o" "  fix: sh $REPO/bin/pin-instructions.sh --apply --dir '$CFGP'"
t_hasnt "...and no fix line names the live box" "$(printf '%s\n' "$_o" | grep '^  fix: ')" "--live"
mirror
t_has "the live box's re-pin fix is --live" "$(live)" "  fix: sh $REPO/bin/pin-instructions.sh --apply --live"
provision; printf 'v9\n' > "$REPO/bin/thing.sh"; g commit -qam eleven >/dev/null; publish; mirror
t_has "a sandbox behind is fixed by its installer at that dir" "$(run)" "  fix: sh $REPO/bin/floor-install.sh --apply --dir '$CFGP'"
t_has "the live box behind is fixed by deploy, the one live entry (the install standard §4)" "$(live)" \
  "  fix: sh '$REPO/bin/deploy.sh' --only floor --apply --live"
_o="$(run)"
t_eq "the token line stays first: the statusline reads it" renew "$(printf '%s\n' "$_o" | head -1 | cut -d' ' -f1)"
t_eq "every finding is a WARN followed by its fix line (CONTRACTS/logging.md)" "$(printf '%s\n' "$_o" | grep -c '^  WARN: ')" \
  "$(printf '%s\n' "$_o" | grep -A1 '^  WARN: ' | grep -c '^  fix: ')"
t_eq "...and the run ends on the summary, exit 0 as the header promises" "0 yes" \
  "$(run >/dev/null; echo $?) $(printf '%s\n' "$_o" | tail -1 | grep -qE '^renew-check: [0-9]+ ok, 0 failed, [0-9]+ warnings$' && echo yes || echo no)"
t_eq "...and after the data line every line is a header, a TAG line or the summary" "" \
  "$(printf '%s\n' "$_o" | sed 1d | grep -vE '^(── renew-check · |  (ok|FAIL|WARN|note|skip|fix): |renew-check: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$)')"
t_done
