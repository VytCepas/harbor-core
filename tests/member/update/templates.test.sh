#!/bin/sh
# templates.test.sh (harbor#1278, step 12) — templates/member/: the updater's launchd plist and systemd unit are inert files. Each says in
# its header that nothing installs it and that the schedule needs the operator's yes; none sits where deploy renders schedules; and the
# paths they run match the managed root the updater defaults to.
. "$(dirname "$0")/../../lib/core.sh"; t_init
M="$T_ROOT/templates/member"
for f in com.harbor.member.update.plist member-update.service member-update.timer; do
  h="$(head -n 14 "$M/$f")"
  t_has "$f says it is a template and not installed" "$h" "TEMPLATE, NOT INSTALLED"
  t_has "$f says the schedule needs the operator's yes" "$h" "operator"
  t_eq "$f is not also under launchd/ or systemd/, where deploy renders schedules" "no" "$([ -e "$T_ROOT/launchd/$f" ] || [ -e "$T_ROOT/systemd/$f" ] && echo yes || echo no)"
  t_has "$f is about the updater" "$(cat "$M/$f")" "member-update"
done
t_has "the plist runs the macOS managed root the updater defaults to" "$(cat "$M/com.harbor.member.update.plist")" "/Library/Application Support/ClaudeCode/harbor/bin/member-update.sh"
t_has "the unit runs the Linux managed root the updater defaults to" "$(cat "$M/member-update.service")" "/etc/claude-code/harbor/bin/member-update.sh"
t_has "the updater's default for macOS is the same path" "$(cat "$T_ROOT/bin/member-update.sh")" "/Library/Application Support/ClaudeCode/harbor"
t_has "and for Linux" "$(cat "$T_ROOT/bin/member-update.sh")" "/etc/claude-code/harbor"
t_has "the unit only runs on a member box" "$(cat "$M/member-update.service")" "ConditionPathExists=/etc/claude-code/harbor/bin/harbor-member-mode"
for f in com.harbor.member.update.plist member-update.service; do
  t_hasnt "$f names no member: member.conf does" "$(cat "$M/$f")" '@MEMBER_HOME@'
  t_hasnt "$f sets no state folder either" "$(cat "$M/$f")" 'XDG_STATE_HOME'
done
t_has "the timer asks for no run at load" "$(cat "$M/com.harbor.member.update.plist")" "<key>RunAtLoad</key><false/>"
if command -v plutil >/dev/null 2>&1; then
  if plutil -lint "$M/com.harbor.member.update.plist" >/dev/null 2>&1; then t_pass; else t_fail "the plist does not lint"; fi
else echo "templates-test: SKIPPED plutil (not macOS); the text checks above ran"; fi
t_done
