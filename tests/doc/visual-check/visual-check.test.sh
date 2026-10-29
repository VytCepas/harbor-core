#!/usr/bin/env sh
# doc-visual-check.sh, the render half of the HTML contract (harbor#392, R5). --self-test proves the
# checker can fail; --generated reads every page the repo can rebuild. Exit 3 is UNCHECKED (D-29) only
# when its reason names a missing verifier (No.2.7); any other non-zero is a failure, and a bad argument
# is 2 (D-49: before the migration both were 2).
PROBES="${HARBOR_PROBE_DIR:-$HOME/.local/lib/browser-probes}"  # the Playwright install, found before t_init
. "$(dirname "$0")/../../lib/core.sh"; t_init
HARBOR_PROBE_DIR="$PROBES"; export HARBOR_PROBE_DIR
# Under a sandbox HOME, archify's Chrome hangs on the keychain fetching the page's https web font, so
# its control arm timed out and read as "exemption stale" (measured). Playwright passes this flag too.
CHROME="${ARCHIFY_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ -x "$CHROME" ]; then
  printf '#!/bin/sh\nexec "%s" --use-mock-keychain "$@"\n' "$CHROME" > "$T_BIN/chrome"; chmod +x "$T_BIN/chrome"
  ARCHIFY_CHROME="$T_BIN/chrome"; export ARCHIFY_CHROME
fi
CHECK="$T_ROOT/bin/doc-visual-check.sh"
# `no browser available` is visual-check's own word for a missing Chrome: a missing verifier too, and it is what a
# runner without Chrome says (harbor#865). On a Mac with Chrome the arms still run.
REASON='SKIPPED|no node on PATH|no browser available|HARBOR_PROBE_DIR|playwright'
run() { # <label> <arg> — a pass is exit 0; a 3 naming a missing verifier is skipped; anything else fails
  rc=0; sh "$CHECK" "$2" > "$T_TMP/out" 2>&1 || rc=$?
  if [ "$rc" = 3 ] && grep -qE "$REASON" "$T_TMP/out"; then
    printf '  SKIP  %s — %s\n' "$1" "$(grep -m1 -E "$REASON" "$T_TMP/out")"; return
  fi
  [ "$rc" = 0 ] || sed -n '1,12p' "$T_TMP/out" >&2
  t_eq "$1" "exit 0" "exit $rc"
}

t_section "doc-visual-check.sh"
# The unchecked contract the two runs below rely on, on any host: no Playwright is a 3 that names it.
printf '<!doctype html><style>p{color:#111}</style><p>x</p>\n' > "$T_TMP/p.html"
o="$(env HARBOR_PROBE_DIR="$T_TMP/no-probes" sh "$CHECK" "$T_TMP/p.html" 2>&1)"; rc=$?
t_eq "with no Playwright the checker is blind: exit 3 (D-29 unchecked)" "exit 3" "exit $rc"
t_eq "that names the missing verifier" yes "$(printf '%s' "$o" | grep -qE "$REASON" && echo yes || echo "no: $o")"
# Bad arguments are 2 on every host, because the flag is judged before node or Playwright is looked for.
rc=0; sh "$CHECK" --bogus > "$T_TMP/out" 2>&1 || rc=$?
t_eq "an unknown flag is a usage error: exit 2" "exit 2" "exit $rc"
t_has "...that names the flag" "$(cat "$T_TMP/out")" 'unknown option: --bogus'
# contracts/logging.md: a usage error is not a run, so its words go to stderr and it ends with no summary line.
sh "$CHECK" --bogus > "$T_TMP/u.out" 2> "$T_TMP/u.err"
t_eq "...on stderr, with stdout left empty" "" "$(cat "$T_TMP/u.out")"
t_has "...(the flag is named there)" "$(cat "$T_TMP/u.err")" 'unknown option: --bogus'
t_eq "...and no summary line on either stream, because it is not a run" "" "$(cat "$T_TMP/u.out" "$T_TMP/u.err" | grep -E '^visual-check: [0-9]+ ok' || :)"
t_has "valid: the blind run above was a run, and still ends with its summary line" "$o" 'visual-check: 0 ok, 1 failed'
rc=0; env HARBOR_PROBE_DIR="$T_TMP/no-probes" sh "$CHECK" --bogus > "$T_TMP/out" 2>&1 || rc=$?
t_eq "...even on a host with no Playwright (usage is judged before availability)" "exit 2" "exit $rc"
want=2; command -v node >/dev/null 2>&1 || want=3   # with no node nothing past the availability check can run
rc=0; env HARBOR_PROBE_DIR="$T_TMP/no-probes" sh "$CHECK" "$T_TMP/does-not-exist.html" > "$T_TMP/out" 2>&1 || rc=$?
t_eq "a named page that does not exist is a usage error: exit 2 (3 with no node)" "exit $want" "exit $rc"
mkdir -p "$T_TMP/odd dir"; cp "$T_TMP/p.html" "$T_TMP/odd dir/-odd name.html"
rc=0; (cd "$T_TMP/odd dir" && env HARBOR_PROBE_DIR="$T_TMP/no-probes" sh "$CHECK" "./-odd name.html") > "$T_TMP/out" 2>&1 || rc=$?
t_eq "valid but unusual: ./-odd name.html (a dash and a space) is a page and not a flag: it reaches the verifier check, exit 3" "exit 3" "exit $rc"
run 'the checker can fail, and archify still fails its own containment' --self-test
run 'every page this repo can regenerate is legible in both themes' --generated

t_section "the contrast floor and alpha compositing are what the verdict rests on (harbor#905)"
# --self-test's fixtures sit far below any floor, so a floor lowered to 1.5 or translucent text judged
# as opaque passed it. These pages sit between the real floor and those mutants.
page() { # <label> <file> <want exit> — the same unchecked contract as run()
  rc=0; sh "$CHECK" "$2" > "$T_TMP/out" 2>&1 || rc=$?
  if [ "$rc" = 3 ] && grep -qE "$REASON" "$T_TMP/out"; then
    # Asserted, not only printed: a host with no browser (the hosted runner) must still run an
    # assertion here, or this section fails as vacuous (core.sh _t_close).
    t_eq "$1: unchecked, and it names the missing verifier" 3 "$rc"; return
  fi
  t_eq "$1" "exit $3" "exit $rc"
}
printf '<!doctype html><style>body{background:#fff}p{color:#999;font-size:16px}</style><p>grey on white, about 2.8 to 1</p>\n' > "$T_TMP/c28.html"
printf '<!doctype html><style>body{background:#fff}p{color:rgba(0,0,0,0.25);font-size:16px}</style><p>a quarter-black, about 1.8 to 1 once composited</p>\n' > "$T_TMP/alpha.html"
printf '<!doctype html><style>body{background:#fff}p{color:#222;font-size:16px}</style><p>near-black on white, about 16 to 1</p>\n' > "$T_TMP/ok.html"
page "normal text at 2.8:1 fails the 4.5 floor" "$T_TMP/c28.html" 1
page "translucent text is judged after compositing" "$T_TMP/alpha.html" 1
page "control: 16:1 text passes" "$T_TMP/ok.html" 0
t_done
