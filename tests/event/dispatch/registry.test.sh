#!/usr/bin/env sh
# What harbor#1044 ships, against the repo's own docs/reference/checks.md: every preset in contracts/event-rules.tsv installs
# only through its register row; nothing is on as shipped; the launchd plist is the KeepAlive follower; subscribe
# is refused as unverified; `harbor event` routes the E2 verbs.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
PRESETS="$T_ROOT/contracts/event-rules.tsv"
# The register and the presets, installed as runtime-install's DATA installs them: the repo's bytes in {cfg}/bin.
install_bin docs/reference/checks.md "$T_ROOT/docs/reference/checks.md"; install_bin event-rules.tsv "$PRESETS"
ids="$(awk -F'\t' '!/^#/ && NF == 6 { print $1 }' "$PRESETS")"

t_section "a fresh dispatcher is inert: no rule, no spawner"
dispatch_once; rc=$?
t_eq "dispatch --once on an empty bus exits 0" 0 "$rc"
t_eq "no rule exists until someone adds one" "" "$(ls "$GT/rules")"
t_eq "no spawn.on exists until the operator makes it" no "$([ -e "$GT/spawn.on" ] && echo yes || echo no)"

t_section "the handler allowlist is the presets' handlers, and none of them approves or runs claude (review r2 #1, #2)"
allow="$(sed -n "s/^HANDLERS='\(.*\)'$/\1/p" "$ED" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"
t_eq "event-dispatch.sh's HANDLERS is exactly contracts/event-rules.tsv's handler scripts" \
  "$(awk -F'\t' '!/^#/ && NF == 6 { print $6 }' "$PRESETS" | sed 's#^sh {cfg}/bin/##' | sort -u | tr '\n' ' ' | sed 's/ $//')" "$allow"
t_eq "every preset's handler is the one form a rule may run: sh {cfg}/bin/<script>" "" \
  "$(awk -F'\t' '!/^#/ && NF == 6 && $6 !~ /^sh \{cfg\}\/bin\/[A-Za-z0-9._-]+$/ { print $1 }' "$PRESETS")"
for h in $allow; do
  t_eq "$h is a file runtime-install ships" yes "$(sed -n 's/^FILES="\(.*\)"/ \1 /p' "$T_ROOT/bin/deploy-runtime-install.sh" | grep -q " $h " && echo yes || echo no)"
  t_hasnt "$h does not name gate-approve.sh" "$(cat "$T_ROOT/bin/$h")" "gate-approve"
  t_eq "$h does not run claude" "" "$(grep -n -E '(^|[;&|(` ])claude( |$)|claude-code|"\$_?claude"' "$T_ROOT/bin/$h")"
done

t_section "every preset installs through its docs/reference/checks.md row, and only that way"
t_eq "the presets file has the rows #1044 and the session reactions ship" \
  "event.fleet-snapshot event.pulse event.session-check event.session-ci-watch event.session-cleanup-report event.session-notify event.session-save-now" \
  "$(printf '%s\n' "$ids" | sort | tr '\n' ' ' | sed 's/ $//')"
# The presets' scripts, installed as runtime-install would: the bytes and the manifest row the load checks.
for h in $allow; do install_bin "$h" "$T_ROOT/bin/$h"; done
for id in $ids; do
  sh "$ED" on --preset "$id" 2>"$T_TMP/p.err"; rc=$?
  t_eq "$id: on --preset exits 0 against the repo's docs/reference/checks.md" 0 "$rc"
  t_has "$id: its handler is the installed copy, {cfg} expanded" "$(grep '^argv=' "$GT/rules/$id.rule" | tr '\n' ' ')" "argv=$CLAUDE_CONFIG_DIR/bin/"
  case "$id" in event.fleet-snapshot|event.pulse) _bs=3600 ;; *) _bs=0 ;; esac   # fixed values, not read back from the row under test
  t_eq "$id: its backstop ($_bs)" "backstop=$_bs" "$(grep '^backstop=' "$GT/rules/$id.rule")"
done
sed 's/`harbor event on --off event.pulse`/(no disable)/g' "$T_ROOT/docs/reference/checks.md" > "$T_TMP/nodisable.md"
install_bin docs/reference/checks.md "$T_TMP/nodisable.md"
t_exit "a register row that loses its disable command refuses the preset" 1 sh "$ED" on --preset event.pulse
sed 's/`obligation.open`/obligation-open/' "$T_ROOT/docs/reference/checks.md" > "$T_TMP/notrigger.md"
install_bin docs/reference/checks.md "$T_TMP/notrigger.md"
t_exit "a register row that stops naming a trigger refuses the preset" 1 sh "$ED" on --preset event.pulse
install_bin docs/reference/checks.md "$T_ROOT/docs/reference/checks.md"
t_exit "an unknown preset is refused" 1 sh "$ED" on --preset event.nope
t_exit "a #stub preset (session-peer) is refused with exit 4" 4 sh "$ED" on --preset event.session-peer
t_has "...and says why: the messaging socket is unverified" "$(sh "$ED" on --preset event.session-peer 2>&1)" "not built"
t_eq "...and installed no rule" no "$([ -e "$GT/rules/event.session-peer.rule" ] && echo yes || echo no)"
printf '# drifted\n' >> "$CFG/bin/alert-notify.sh"
t_exit "a preset whose installed script is not the bytes runtime-install recorded is refused (4)" 4 sh "$ED" on --preset event.pulse
install_bin alert-notify.sh "$T_ROOT/bin/alert-notify.sh"

t_section "the register and the presets are read only as installed, hash-checked data (review r3 #5)"
# A working tree where ~/port/harbor would be, holding a register with neither row: it is never read.
mkdir -p "$HOME/port/harbor/contracts"; printf '# a checkout on another branch\n' > "$HOME/port/harbor/docs/reference/checks.md"
: > "$HOME/port/harbor/contracts/event-rules.tsv"
t_exit "a checkout on another branch at ~/port/harbor changes nothing: on --preset still installs" 0 sh "$ED" on --preset event.pulse
t_hasnt "...and --list does not refuse it" "$(sh "$ED" on --list 2>/dev/null)" "REFUSED"
printf '\n' >> "$CKS"
t_exit "the installed docs/reference/checks.md, its bytes not the manifest's blob: refused" 1 sh "$ED" on --preset event.pulse
t_has "...and --list refuses the rules it registers, naming why" "$(sh "$ED" on --list 2>/dev/null)" "docs/reference/checks.md is not the bytes runtime-install recorded"
install_bin docs/reference/checks.md "$T_ROOT/docs/reference/checks.md"
mv "$CFG/bin/event-rules.tsv" "$T_TMP/rules.keep"
t_exit "no installed event-rules.tsv: on --preset is refused, the checkout's is not used" 1 sh "$ED" on --preset event.pulse
mv "$T_TMP/rules.keep" "$CFG/bin/event-rules.tsv"
rm -f "$GT/rules/event.pulse.rule"
t_exit "on --preset with CLAUDE_CONFIG_DIR spelled with a trailing slash: accepted" 0 env CLAUDE_CONFIG_DIR="$CFG/" sh "$ED" on --preset event.pulse
t_hasnt "...its handler path is the one spelling, no //" "$(grep '^argv=' "$GT/rules/event.pulse.rule")" "//"
t_hasnt "...and it loads under the plist's environment (no CLAUDE_CONFIG_DIR)" "$(env -u CLAUDE_CONFIG_DIR sh "$ED" on --list 2>/dev/null)" "REFUSED"
t_hasnt "...and under CLAUDE_CONFIG_DIR without the slash" "$(sh "$ED" on --list 2>/dev/null)" "REFUSED"
rm -f "$GT/rules/event.pulse.rule"
t_exit "from a checkout's copy (harbor event in ~/port/harbor) with the trailing slash: accepted" 0 env CLAUDE_CONFIG_DIR="$CFG/" sh "$T_ROOT/bin/event-dispatch.sh" on --preset event.pulse
t_hasnt "...its handler path is the one spelling, no //" "$(grep '^argv=' "$GT/rules/event.pulse.rule")" "//"
t_hasnt "...and it loads under the plist's environment" "$(env -u CLAUDE_CONFIG_DIR sh "$ED" on --list 2>/dev/null)" "REFUSED"
t_exit "the installed copy refuses a CLAUDE_CONFIG_DIR that is not its own (4)" 4 env CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" sh "$ED" on --list
rm -rf "$HOME/port"

t_section "the launchd job is the KeepAlive follower, shipped and not installed"
PL="$T_ROOT/launchd/com.harbor.event.dispatch.plist"
flat="$(tr -d ' \n\t' < "$PL")"
t_has "it runs the installed dispatcher's dispatch verb" "$flat" "/.claude/bin/event-dispatch.sh</string><string>dispatch</string></array>"
t_has "...under /bin/sh" "$flat" "<key>ProgramArguments</key><array><string>/bin/sh</string>"
t_has "restarted on a crash, left down after exit 0" "$flat" "<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>"
t_has "in the operator's GUI session, for the keychain" "$flat" "<key>LimitLoadToSessionType</key><string>Aqua</string>"
t_has "docs/reference/checks.md registers it as not installed" "$(grep '^| `event.dispatch` |' "$T_ROOT/docs/reference/checks.md")" "NOT installed"
t_eq "no installer copies or loads it" "" "$(grep -h 'LaunchAgents\|launchctl' "$T_ROOT"/bin/*install*.sh "$T_ROOT"/bin/deploy.sh 2>/dev/null | grep 'event\.dispatch')"

t_section "subscribe is refused until the messaging socket is verified"
sh "$ED" subscribe '"kind":"git\.merge"' 2>"$T_TMP/sub.err"; rc=$?
t_eq "exit 4" 4 "$rc"
t_has "it says UNVERIFIED and why" "$(cat "$T_TMP/sub.err")" "UNVERIFIED"
t_has "...and where the finding is" "$(cat "$T_TMP/sub.err")" "docs/design/events.md"

t_section "harbor event routes the E2 verbs"
t_exit "harbor event subscribe → 4" 4 sh "$T_ROOT/bin/harbor" event subscribe x
t_has "harbor event on --list shows the presets added above" "$(sh "$T_ROOT/bin/harbor" event on --list 2>/dev/null)" "event.pulse"
t_exit "harbor event dispatch --bogus is a usage error" 2 sh "$T_ROOT/bin/harbor" event dispatch --bogus
t_done
