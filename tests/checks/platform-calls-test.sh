#!/usr/bin/env sh
# platform calls (harbor#618): a macOS-only call in bin/ is ported or declared, never bare.
# Derives over every file in bin/ (extensionless included, comments stripped): a file that calls launchctl,
# plutil, ditto, caffeinate, pbcopy, pbpaste, osascript, notifyutil, pmset, scutil, dscl, xattr or brew names a Linux
# counterpart for each in its own code (systemctl, a clipboard tool, notify-send, pkg_hint, useradd), or carries
# `# platform: macOS-only — <reason>` in its first 40 lines. Guards and the lint hold the call as a refused pattern.
# osascript has no counterpart: a notification goes through bin/alert-lib.sh, the one helper allowed to call it.
. "$(dirname "$0")/../lib/core.sh"; t_init
# The derive is bin/lint-platform.sh, run by lint.platform-calls; this suite is its red-proof (harbor#618).
uncovered() { sh "$T_ROOT/bin/lint-platform.sh" "$1" 2>/dev/null || :; }
called() { sh "$T_ROOT/bin/lint-platform.sh" --called "$1" 2>/dev/null; }

t_section "bin/ holds no bare macOS-only call"
t_eq "every launchctl, plutil, ditto, caffeinate, pbcopy, pbpaste, osascript, notifyutil, pmset, scutil, dscl, xattr and brew call is ported or declared" "" "$(uncovered "$T_ROOT/bin")"
_called="$(called "$T_ROOT/bin" | tr '\n' ' ')"
t_has "control: the derive sees a ported file (fleet-snapshot-refresh.sh)" "$_called" "fleet-snapshot-refresh.sh "
t_has "control: the derive sees a declared file (renew-check.sh)" "$_called" "renew-check.sh "
t_has "control: ...and the file declared in this suite (doctor.sh)" "$_called" "doctor.sh "
t_has "control: the derive sees an extensionless file's clipboard call is not skipped (save-log-token.sh)" "$_called" "save-log-token.sh "
for _c in alert-lib.sh:osascript:helper ci-governor.sh:notifyutil:declared deliver-drive.sh:xattr:declared log-lib.sh:brew:defines gcloud-wrapper.sh:brew:guarded collector-setup.sh:dscl:ported; do
  t_has "control: the derive sees ${_c%%:*}'s ${_c#*:} call (${_c##*:})" "$_called" "${_c%%:*} "
done
for _d in renew-check.sh session-verdicts.sh standard-rename.sh ci-governor.sh ci-governor-hook.sh deliver-drive.sh; do
  t_has "$_d declares its macOS-only call" "$(head -n 40 "$(t_src "$_d")")" "# platform: macOS-only — "
done

t_section "the rule is lint.platform-calls, run by the conventions linter"
_row="$(awk -F'\t' '$1 == "lint.platform-calls" { print $2 "|" $4 "|" $11 }' "$T_ROOT/standards/naming/controls.tsv")"
t_eq "controls.tsv carries lint.platform-calls: block, run by the linter, this suite its red-proof" "block|bin/lint-conventions.sh|tests/checks/platform-calls-test.sh" "$_row"
t_has "the linter defines the rule" "$(grep -c '^rule "lint.platform-calls ' "$T_ROOT/bin/lint-conventions.sh")" "1"
t_has "...and suite-paths.txt selects this suite on a change under bin/" "$(grep '^tests/checks/platform-calls-test.sh' "$T_ROOT/CONTRACTS/suite-paths.txt")" "bin/*"

t_section "red-proof: the checker reads a plant the way the rule says"
P="$T_TMP/plant"; mkdir -p "$P"
printf '#!/usr/bin/env sh\nlaunchctl list\n' > "$P/bare"                                    # extensionless, bare
printf '#!/usr/bin/env sh\n# launchctl is only prose here\necho hi\n' > "$P/prose.sh"
printf '#!/usr/bin/env sh\n# platform: macOS-only — a launchd probe\nlaunchctl list\n' > "$P/declared.sh"
printf '#!/usr/bin/env sh\nlaunchctl list || systemctl --user list-timers\n' > "$P/ported.sh"
printf '#!/usr/bin/env sh\npbpaste | xclip -selection clipboard -o\n' > "$P/clip-ported.sh"
printf '#!/usr/bin/env sh\npbpaste\n' > "$P/clip-bare.sh"
printf '#!/usr/bin/env sh\nprintf x | pbcopy\n' > "$P/copy-bare.sh"
printf '#!/usr/bin/env sh\nprintf x | pbcopy || wl-copy\n' > "$P/copy-ported.sh"
printf '#!/usr/bin/env sh\nplutil -p x; xclip -o; systemctl status\n' > "$P/plutil-bare.sh"  # another tool's counterpart does not cover it
printf '#!/usr/bin/env sh\ncaffeinate -d\n' > "$P/caff.sh"
printf '#!/usr/bin/env sh\nditto a b # ported?\n' > "$P/ditto.sh"
{ printf '#!/usr/bin/env sh\n'; i=0; while [ $i -lt 45 ]; do echo ":"; i=$((i+1)); done
  printf '# platform: macOS-only — too deep to be a header\nlaunchctl list\n'; } > "$P/deep.sh"
printf '#!/usr/bin/env sh\nx=$(echo launchctl-mutate); y=pbpaste-hint; z=ditto2\n' > "$P/near-miss.sh"
printf '#!/usr/bin/env sh\nlaunchctl list\n' > "$P/guard-new.sh"                            # a guard holds it as a pattern
printf '#!/usr/bin/env sh\nosascript -e x\n' > "$P/notify-bare.sh"
printf '#!/usr/bin/env sh\nosascript -e x || notify-send y\n' > "$P/notify-ported.sh"
printf '#!/usr/bin/env sh\nlog_fix "brew install jq"\n' > "$P/brew-bare.sh"
printf '#!/usr/bin/env sh\nlog_fix "$(pkg_hint jq)"\n[ "$(uname -s)" = Darwin ] && brew install x\n' > "$P/brew-ported.sh"
printf '#!/usr/bin/env sh\nxattr -p k f\n' > "$P/xattr-bare.sh"
printf '#!/usr/bin/env sh\n# platform: macOS-only — Drive for Desktop\nxattr -p k f\n' > "$P/xattr-declared.sh"
printf '#!/usr/bin/env sh\nnotifyutil -p k; pmset -g; scutil --dns\n' > "$P/mac-trio.sh"
printf '#!/usr/bin/env sh\ndscl . -list /Users; useradd x\n' > "$P/dscl-ported.sh"
want="bare: launchctl
brew-bare.sh: brew
caff.sh: caffeinate
clip-bare.sh: pbpaste
copy-bare.sh: pbcopy
deep.sh: launchctl
ditto.sh: ditto
mac-trio.sh: notifyutil
mac-trio.sh: pmset
mac-trio.sh: scutil
notify-bare.sh: osascript
notify-ported.sh: osascript
plutil-bare.sh: plutil
xattr-bare.sh: xattr"
t_eq "bare, caffeinate, clipboard-without-counterpart (pbpaste and pbcopy), too-deep header, ditto, another tool's counterpart, a bare notifier, brew, xattr and the macOS trio are red; prose, declared, ported (including a Darwin-guarded brew), near-miss names and a guard are not" "$want" "$(uncovered "$P")"

t_section "red-proof: a copy of bin/ with one call planted, or one header removed, goes red"
M="$T_TMP/mut"; mkdir -p "$M"; cp "$T_ROOT"/bin/* "$M"/ 2>/dev/null
t_eq "control: the copy is clean before the mutation" "" "$(uncovered "$M")"
printf 'launchctl list >/dev/null 2>&1\n' >> "$M/freshness.sh"
t_eq "a new bare launchctl call in a clean script" "freshness.sh: launchctl" "$(uncovered "$M")"
cp "$T_ROOT/bin/freshness.sh" "$M/freshness.sh"
grep -v '^# platform: macOS-only — ' "$T_ROOT/bin/standard-rename.sh" > "$M/standard-rename.sh"
t_eq "standard-rename.sh without its header line" "standard-rename.sh: launchctl" "$(uncovered "$M")"
cp "$T_ROOT/bin/standard-rename.sh" "$M/standard-rename.sh"
grep -v 'systemctl' "$T_ROOT/bin/fleet-snapshot-refresh.sh" > "$M/fleet-snapshot-refresh.sh"
t_eq "fleet-snapshot-refresh.sh without its Linux branch" "fleet-snapshot-refresh.sh: launchctl" "$(uncovered "$M")"
cp "$T_ROOT/bin/fleet-snapshot-refresh.sh" "$M/fleet-snapshot-refresh.sh"
grep -vE 'wl-paste|xclip|xsel|powershell|wl-copy|clip\.exe' "$T_ROOT/bin/save-log-token.sh" > "$M/save-log-token.sh"
t_has "save-log-token.sh without its Linux clipboard branches" "$(uncovered "$M")" "save-log-token.sh: pbpaste"
cp "$T_ROOT/bin/save-log-token.sh" "$M/save-log-token.sh"
printf 'printf x | pbcopy\n' >> "$M/freshness.sh"
t_eq "a bare pbcopy planted in a clean bin script" "freshness.sh: pbcopy" "$(uncovered "$M")"
cp "$T_ROOT/bin/freshness.sh" "$M/freshness.sh"
sed 's/pkg_hint jq/brew install jq/' "$T_ROOT/bin/runtime-install.sh" > "$M/runtime-install.sh"
t_eq "runtime-install.sh back on a bare brew hint (harbor#618)" "runtime-install.sh: brew" "$(uncovered "$M")"
cp "$T_ROOT/bin/runtime-install.sh" "$M/runtime-install.sh"
printf 'osascript -e x || notify-send y\n' >> "$M/pulse-notify.sh"
t_eq "pulse-notify.sh calling osascript itself, notify-send beside it or not" "pulse-notify.sh: osascript" "$(uncovered "$M")"
cp "$T_ROOT/bin/pulse-notify.sh" "$M/pulse-notify.sh"
cp "$T_ROOT/bin/alert-lib.sh" "$M/alert-copy.sh"
t_eq "the helper's code under any other name is red: the exemption is the helper, not the code" "alert-copy.sh: osascript" "$(uncovered "$M")"
rm -f "$M/alert-copy.sh"
grep -v '^# platform: macOS-only — ' "$T_ROOT/bin/deliver-drive.sh" > "$M/deliver-drive.sh"
t_eq "deliver-drive.sh without its header line" "deliver-drive.sh: xattr" "$(uncovered "$M")"
t_section "the rule itself: a planted bare call fails the linter (lint.platform-calls)"
LR="$T_TMP/lroot"; mkdir -p "$LR/bin"; cp "$T_ROOT/bin/lint-platform.sh" "$T_ROOT/bin/alert-lib.sh" "$T_ROOT/bin/log-lib.sh" "$LR/bin/"
printf '#!/usr/bin/env sh\necho ok\n' > "$LR/bin/clean.sh"
_lo="$(HARBOR_ROOT="$LR" sh "$T_ROOT/bin/lint-conventions.sh" --only lint.platform-calls 2>&1)"
t_hasnt "control: a clean bin/ with the helper in it raises nothing" "$_lo" "VIOLATION [lint.platform-calls]"
printf 'osascript -e x\n' >> "$LR/bin/clean.sh"
_lo="$(HARBOR_ROOT="$LR" sh "$T_ROOT/bin/lint-conventions.sh" --only lint.platform-calls 2>&1)"
t_has "a planted osascript call is a violation naming the file" "$_lo" "VIOLATION [lint.platform-calls] bin/clean.sh: osascript"
t_has "...and the linter exits red" "$_lo" "1 violation(s)"
t_done
