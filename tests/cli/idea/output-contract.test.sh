#!/usr/bin/env sh
# idea.sh's output follows CONTRACTS/logging.md (harbor#771): stdout is `idea -l`'s pool and only that; every status
# line is log-lib's, on stderr; a FAIL is followed by its fix and the run ends with the summary. The log repo is a
# throwaway with no remote and no token, so nothing is pushed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/idea.sh"; L="$T_TMP/log"; mkdir -p "$L"
git -C "$L" init -q; git -C "$L" config user.email t@t; git -C "$L" config user.name t; git -C "$L" config commit.gpgsign false
run() { env HARBOR_LOG_DIR="$L" HARBOR_LOG_TOKEN_FILE="$T_TMP/no-token" IDEA_NO_SCAN=1 sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after_fail() { awk '/^  FAIL:/ { f = 1; next } f { print; exit }' "$T_TMP/err"; }

t_section "an empty pool: a note on the log, nothing on stdout"
t_eq "-l exits 0" "exit 0" "$(run -l)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the note" "$(ERR)" "  note: pool is empty"
t_eq "the summary ends it" "idea: 0 ok, 0 failed, 0 warnings" "$(ERR | tail -1)"

t_section "a log repo with no GitHub origin: committed locally, and no repo name is assumed (harbor#1149)"
t_eq "exit 0" "exit 0" "$(run 'no origin yet')"
t_has "the WARN says why" "$(ERR)" "  WARN: the log repo has no GitHub origin — committed locally"
t_eq "HARBOR_LOG_REPO still names one" "exit 0" "$(HARBOR_LOG_REPO=o/log run 'named')"
t_has "...so the push goes on to want the token" "$(ERR)" "  WARN: no token — committed locally"
git -C "$L" remote add origin https://github.com/o/log.git

t_section "an idea with no token: recorded (ok), committed locally (WARN), exit 0"
t_eq "exit 0" "exit 0" "$(run 'try the thing')"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the id is an ok line" "$(ERR)" "  ok: i-0003 recorded"
t_has "the missing token is a WARN" "$(ERR)" "  WARN: no token — committed locally"
t_eq "the summary" "idea: 1 ok, 0 failed, 1 warnings" "$(ERR | tail -1)"
t_eq "no legacy 'idea: ' prefix line is left" 0 "$(ERR | grep -c '^idea: [^0-9]')"
t_eq "-n stays local, as a note" "exit 0" "$(run -n 'second')"
t_has "the note" "$(ERR)" "  note: local only (-n)"

t_section "-l prints the pool on stdout and logs nothing"
t_eq "exit 0" "exit 0" "$(run -l)"
t_has "the pool is data" "$(OUT)" "i-0002"
t_eq "nothing is logged" "" "$(ERR)"

t_section "a refusal: FAIL, its fix, the summary, exit 1, nothing on stdout"
t_eq "an unknown flag exits 1" "exit 1" "$(run -x)"
t_eq "stdout is empty" "" "$(OUT)"
t_has "the FAIL names it" "$(ERR)" "  FAIL: unknown flag: -x"
t_eq "the next line is its fix" "  fix: idea -h" "$(after_fail)"
t_eq "the summary ends it" "idea: 0 ok, 1 failed, 0 warnings" "$(ERR | tail -1)"
t_eq "no idea given exits 1" "exit 1" "$(run)"
t_has "its fix shows the usage" "$(after_fail)" '  fix: idea "the idea"'
t_eq "a missing log repo exits 1" "exit 1" "$(env HARBOR_LOG_DIR="$T_TMP/none" sh "$TOOL" x >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "the FAIL names the path" "$(ERR)" "  FAIL: no log repo at $T_TMP/none"
t_has "with a none-automatic fix" "$(after_fail)" "  fix: none automatic — see"

t_section "the fail-closed secret gate: no scanner is a FAIL with its fix, and the pool is untouched"
BEFORE="$(cat "$L/IDEAS.md")"
t_eq "exit 1" "exit 1" "$(env PATH="/usr/bin:/bin" HARBOR_LOG_DIR="$L" HARBOR_LOG_TOKEN_FILE="$T_TMP/no-token" sh "$TOOL" 'third' >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "the FAIL" "$(ERR)" "  FAIL: gitleaks missing — blocked (fail-closed)"
t_has "its fix installs it, in this host's package manager" "$(after_fail)" "  fix: $(. "$T_ROOT/bin/log-lib.sh"; pkg_hint gitleaks)"
# A PATH dir that makes this host answer as Linux with apt-get (harbor#618): uname says Linux, apt-get exists.
lx_stub() { # <dir>
  mkdir -p "$1"; printf '#!/bin/sh\necho Linux\n' > "$1/uname"; printf '#!/bin/sh\nexit 0\n' > "$1/apt-get"; chmod +x "$1/uname" "$1/apt-get"
}
lx_stub "$T_TMP/lx"
t_eq "Linux: exit 1" "exit 1" "$(env PATH="$T_TMP/lx:/usr/bin:/bin" HARBOR_LOG_DIR="$L" HARBOR_LOG_TOKEN_FILE="$T_TMP/no-token" sh "$TOOL" 'fourth' >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?")"
t_has "Linux: gitleaks has no apt package, so the fix names its releases" "$(after_fail)" "  fix: see https://github.com/gitleaks/gitleaks/releases"
t_hasnt "Linux: and never says brew" "$(ERR)" brew
t_eq "the pool is byte-for-byte unchanged" "$BEFORE" "$(cat "$L/IDEAS.md")"
t_done
