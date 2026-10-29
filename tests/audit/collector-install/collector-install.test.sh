#!/usr/bin/env sh
# audit-collector-install.sh (harbor#1181 lanes 5, 5b): the dry run plans a hidden collector user, a root-owned code copy,
# READ-only access and the three jobs, and changes nothing; macOS through ACLs and launchd, Linux through
# CAP_DAC_READ_SEARCH and systemd. The templates on both platforms carry placeholders, never a real path.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$(cd "$(dirname "$0")/../../.." && pwd)"; X="$R/bin/audit-collector-install.sh"
t_eq "an unknown argument is a usage error" 2 "$(sh "$X" --bogus >/dev/null 2>&1; echo $?)"
t_eq "a platform that is neither is refused" 1 "$(HARBOR_COLLECTOR_OS=Plan9 sh "$X" --dry-run >/dev/null 2>&1; echo $?)"

t_section "the templates"
for p in com.harbor.collector com.harbor.collector-checkpoint com.harbor.otlp-receiver; do
  t_has "$p runs as the second uid" "$(cat "$R/launchd/$p.plist")" "<key>UserName</key><string>_harborlog</string>"
  t_has "$p runs the installed copy, a placeholder setup fills" "$(cat "$R/launchd/$p.plist")" "@BIN@/"
done
for u in harbor-collector.service harbor-collector-checkpoint.service harbor-otlp-receiver.service; do
  t_has "$u runs as the second uid" "$(cat "$R/systemd/$u")" "User=harborlog"
done
t_has "the Linux ingest unit reads through a capability, not an ACL a chmod would mask" "$(cat "$R/systemd/harbor-collector.service")" "AmbientCapabilities=CAP_DAC_READ_SEARCH"
t_eq "and only that unit holds it" 1 "$(grep -l CAP_DAC_READ_SEARCH "$R"/systemd/harbor-*.service | grep -c .)"
t_eq "no template names a real home or user" 0 "$(cat "$R"/launchd/com.harbor.collector*.plist "$R"/launchd/com.harbor.otlp-receiver.plist "$R"/systemd/harbor-collector* "$R"/systemd/harbor-otlp-receiver.service | grep -c -E '/Users/|/home/')"

H="$T_TMP/home"; mkdir -p "$H/.claude/MEMORY/OBSERVABILITY/h" "$H/.local/state/harbor/events" "$H/.claude/cache"; : > "$H/.claude/cache/checks.log"
SRCS="$H/.claude/MEMORY/OBSERVABILITY:$H/.local/state/harbor/events:$H/.claude/cache/checks.log:$H/absent"
plan() { HARBOR_COLLECTOR_OS="$1" HARBOR_COLLECTOR_HOME="$H" HARBOR_COLLECTOR_SRC="$SRCS" sh "$X" --dry-run 2>&1; }

t_section "the Linux plan (any host)"
O="$(plan Linux)"; rc=$?
t_eq "a Linux dry run exits 0" 0 "$rc"
t_has "a system user with no shell and no home" "$O" 'useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin'
t_has "the code goes to a root-owned dir" "$O" 'chown -R root:root /opt/harbor/collector-bin'
t_eq "and no ACL is planned: the capability reads" 0 "$(printf '%s\n' "$O" | grep -c -E 'chmod [+-]a|setfacl')"
t_has "five units are written" "$O" 'would write /etc/systemd/system/harbor-otlp-receiver.service'
t_has "and enabled" "$O" 'systemctl enable --now harbor-collector.timer harbor-collector-checkpoint.timer harbor-otlp-receiver.service'
t_has "and nothing changes" "$O" 'dry run: nothing changed'

if [ "$(uname -s)" = Darwin ]; then
  t_section "the macOS plan"
  # the user is a knob: the real directory decides whether a user exists, so _harborlog made the plan differ per box
  O="$(HARBOR_COLLECTOR_USER=_harbor-test-absent plan Darwin)"; rc=$?
  t_eq "a macOS dry run exits 0" 0 "$rc"
  t_has "the code goes to a root-owned dir" "$O" 'chown -R root:wheel /Library/Application Support/Harbor/collector-bin'
  t_has "directories get list and search, inherited" "$O" 'allow list,search,readattr,readextattr,file_inherit,directory_inherit'
  t_has "files get read" "$O" 'allow read,readattr,readextattr'
  t_eq "no grant anywhere writes, appends or deletes" "" "$(printf '%s\n' "$O" | grep 'chmod +a' | grep -E 'write|append|delete|add_file|add_subdirectory')"
  t_eq "every dir between a source and the home gets search exactly once" "1 1 1 1 1" \
    "$(for d in "$H" "$H/.claude" "$H/.local/state" "$H/.local/state/harbor" "$H/.claude/cache"; do printf '%s\n' "$O" | grep -c "allow search $d\$"; done | tr '\n' ' ' | sed 's/ $//')"
  t_eq "nothing above the home is granted" 0 "$(printf '%s\n' "$O" | grep 'allow search' | grep -vc " $H")"
  t_has "a source that does not exist is not wired" "$O" "not wired, absent today: $H/absent"
  t_has "the user has no shell" "$O" 'UserShell /usr/bin/false'
  t_has "three daemons are planned" "$O" 'would write /Library/LaunchDaemons/com.harbor.otlp-receiver.plist'
  t_has "and nothing changes" "$O" 'dry run: nothing changed'
  O="$(HARBOR_COLLECTOR_USER=root plan Darwin)"
  t_has "a collector user that already exists is kept" "$O" "user root exists"
  t_eq "and is not created again" 0 "$(printf '%s\n' "$O" | grep -c 'dscl . -create')"
fi
t_done
