#!/usr/bin/env sh
# doctor.sh's output follows CONTRACTS/logging.md (harbor#771): stdout is the probe table (live-verify.sh reads its
# rows) or the --json object and only that; the run log is on stderr; a missing fatal dependency is a FAIL with its
# install command, a degraded one a WARN with it; the run ends with the summary and the exit agrees.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/doctor.sh"
# The real PATH as one directory of links, minus jq and gitleaks; a case links back the one it wants present.
FARM="$T_TMP/farm"; mkdir -p "$FARM"
for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
  [ -d "$_d" ] || continue
  for _b in "$_d"/*; do
    _n="${_b##*/}"
    case "$_n" in jq|gitleaks) continue ;; esac
    [ -x "$_b" ] && [ ! -e "$FARM/$_n" ] && ln -s "$_b" "$FARM/$_n"
  done
done
real() { command -v "$1"; }  # the real binary, found on the untouched PATH
run() { env PATH="$1" sh "$TOOL" "${2:-}" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after() { awk -v p="$1" '$0 ~ p { f = 1; next } f { print; exit }' "$T_TMP/err"; }
LOGLINE='^  \(ok\|FAIL\|WARN\|note\|skip\|fix\):'
# The summary must count the lines printed; how many tools this machine lacks besides the removed one is not the test.
printed() { ERR | awk '/^  FAIL: / { f++ } /^  WARN: / { w++ } END { printf "%d failed, %d warnings", f, w }'; }
summed() { ERR | tail -1 | sed -n 's/^doctor: [0-9][0-9]* ok, \(.*\)$/\1/p'; }

t_section "a fatal dependency missing: the table row on stdout, the FAIL and its fix on stderr, exit 1"
ln -sf "$(real gitleaks)" "$FARM/gitleaks"; rm -f "$FARM/jq"
t_eq "positive control: jq is gone" no "$(env PATH="$FARM" sh -c 'command -v jq' >/dev/null 2>&1 && echo yes || echo no)"
t_eq "exit 1" "exit 1" "$(run "$FARM")"
t_eq "the table header is the first stdout line" "TOOL" "$(OUT | head -1 | awk '{print $1}')"
t_has "the row says missing fatal" "$(OUT)" "jq          missing  fatal"
t_eq "no log line is mixed into stdout" 0 "$(OUT | grep -c "$LOGLINE")"
t_has "the FAIL names the tool and what breaks" "$(ERR)" "  FAIL: jq missing — every guard parses its hook payload"
t_eq "its fix follows, in this host's package manager" "  fix: $(. "$T_ROOT/bin/log-lib.sh"; pkg_hint jq)" "$(after '^  FAIL: jq missing')"
# A PATH dir that makes this host answer as Linux with apt-get (harbor#618): uname says Linux, apt-get exists.
lx_stub() { # <dir>
  mkdir -p "$1"; printf '#!/bin/sh\necho Linux\n' > "$1/uname"; printf '#!/bin/sh\nexit 0\n' > "$1/apt-get"; chmod +x "$1/uname" "$1/apt-get"
}
FARM2="$T_TMP/farm2"; lx_stub "$FARM2"; for _b in "$FARM"/*; do [ -e "$FARM2/${_b##*/}" ] || ln -s "$(readlink "$_b")" "$FARM2/${_b##*/}"; done
rm -f "$FARM2/launchctl"   # a Linux box has none: the probe must not report it
t_eq "Linux: exit 1" "exit 1" "$(run "$FARM2")"
t_eq "Linux: the fix names apt-get, not brew" "  fix: sudo apt-get install -y jq" "$(after '^  FAIL: jq missing')"
t_hasnt "Linux: no line of the log says brew" "$(ERR)" brew
t_hasnt "Linux: no launchctl note for a job systemd runs" "$(ERR)" launchctl
t_eq "the summary counts the failure" "$(printed)" "$(summed)"
t_has "and it is one" "$(summed)" "1 failed,"
t_has "the caveat is a note" "$(ERR)" "  note: This is availability, not correctness"

t_section "--json: the object alone on stdout, the same log on stderr"
t_eq "exit 1" "exit 1" "$(run "$FARM" --json)"
t_has "stdout is the object" "$(OUT)" '"missing_fatal":1'
t_eq "stdout is one line" 1 "$(OUT | wc -l | tr -d ' ')"
t_has "the FAIL is on stderr" "$(ERR)" "  FAIL: jq missing"

t_section "a degraded dependency missing: a WARN with its fix, exit 0"
ln -sf "$(real jq)" "$FARM/jq"; rm -f "$FARM/gitleaks"
t_eq "positive control: gitleaks is gone" no "$(env PATH="$FARM" sh -c 'command -v gitleaks' >/dev/null 2>&1 && echo yes || echo no)"
t_eq "exit 0" "exit 0" "$(run "$FARM")"
t_has "the WARN" "$(ERR)" "  WARN: gitleaks missing — the work-log push gate"
t_eq "its fix" "  fix: $(. "$T_ROOT/bin/log-lib.sh"; pkg_hint gitleaks)" "$(after '^  WARN: gitleaks missing')"
t_eq "the summary counts the warning" "$(printed)" "$(summed)"
t_has "and none failed" "$(summed)" "0 failed,"
t_done
