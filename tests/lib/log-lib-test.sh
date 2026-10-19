#!/usr/bin/env sh
# bin/log-lib.sh, the one log format (harbor#771, CONTRACTS/logging.md): exact bytes, counts, exit code,
# the log file, an unwritable log dir, set -u, a terminal, and a FAIL with no fix line. Each case runs a
# tiny tool that sources the library and reads its stdout, stderr, exit code and log file.
set -u
. "$(dirname "$0")/core.sh"; t_init
LIB="$T_ROOT/bin/log-lib.sh"; W="$T_TMP/w"; mkdir -p "$W"
run() { # <set flags> <body>: a tool named demo; fills $W/out and $W/err, sets RC
  printf '#!/bin/sh\nset %s\n. "%s"\n%s\n' "$1" "$LIB" "$2" > "$W/demo.sh"
  sh "$W/demo.sh" > "$W/out" 2> "$W/err"; RC=$?
}
lines() { printf '%s\n' "$@"; printf x; }   # the expected bytes, one argument per line
got()   { cat "$1"; printf x; }             # a file's bytes, trailing newline kept
yn()    { "$@" && echo yes || echo no; }
ISO='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z'

t_section "line shape: the exact bytes of every line"
run -u 'log_init demo; log_head plan; log_ok "a"; log_fail "b in x.sh:3"; log_fix "sh x.sh --apply --live"
log_warn "c"; log_note "d"; log_skip "e"; log_fail "f"; log_nofix "harbor#1"; log_end'
t_eq 'header, every TAG, both fix forms, then the summary' \
  "$(lines '── demo · plan' '  ok: a' '  FAIL: b in x.sh:3' '  fix: sh x.sh --apply --live' '  WARN: c' \
     '  note: d' '  skip: e' '  FAIL: f' '  fix: none automatic — see harbor#1' 'demo: 1 ok, 2 failed, 1 warnings')" \
  "$(got "$W/out")"
t_eq 'nothing on stderr' "" "$(cat "$W/err")"
run -u 'log_init demo; log_ok "100% \\n done"; log_note "$(printf "one\ntwo")"; log_end'
t_eq 'a message prints as data, and a newline in it is flattened' \
  "$(lines '  ok: 100% \n done' '  note: one two' 'demo: 1 ok, 0 failed, 0 warnings')" "$(got "$W/out")"
printf '#!/bin/sh\nset -u\n. "%s"\nlog_head x; log_end\n' "$LIB" > "$W/my-tool.sh"
t_eq 'with no log_init the tool is the script name' "$(lines '── my-tool · x' 'my-tool: 0 ok, 0 failed, 0 warnings')" \
  "$(sh "$W/my-tool.sh" 2>&1; printf x)"
run -u 'LOG_FD=2; log_init demo; log_ok a; log_end'
t_eq 'LOG_FD=2 moves the log to stderr' "$(lines '  ok: a' 'demo: 1 ok, 0 failed, 0 warnings')" "$(got "$W/err")"
t_eq '...and leaves stdout to the data' "" "$(cat "$W/out")"

t_section "summary line and exit code"
run -u 'log_init demo; log_ok a; log_ok b; log_note n; log_skip s; log_head h; log_end; exit $?'
t_eq 'note, skip and header are not counted' 'demo: 2 ok, 0 failed, 0 warnings' "$(tail -1 "$W/out")"
t_eq 'no FAIL exits 0' 0 "$RC"
run -u 'log_init demo; log_warn w; log_nofix doc; log_end; exit $?'
t_eq 'a WARN is counted' 'demo: 0 ok, 0 failed, 1 warnings' "$(tail -1 "$W/out")"
t_eq 'a WARN alone exits 0' 0 "$RC"
run -u 'log_init demo; log_fail x; log_fix y; log_fail z; log_fix y; log_end; exit $?'
t_eq 'each FAIL is counted' 'demo: 0 ok, 2 failed, 0 warnings' "$(tail -1 "$W/out")"
t_eq 'a FAIL exits 1' 1 "$RC"
run -eu 'log_init demo; log_fail x; log_fix y; log_warn w; log_nofix d; log_note n; log_end; exit $?'
t_eq 'under set -e no line function stops the run before its summary' 'demo: 0 ok, 1 failed, 1 warnings' "$(tail -1 "$W/out")"
t_eq '...and the exit code still agrees' 1 "$RC"
run -u 'log_init one; log_ok a; log_fail b; log_fix c; log_init two; log_ok d; log_end; exit $?'
t_eq 'log_init resets the counters' 'two: 1 ok, 0 failed, 0 warnings' "$(tail -1 "$W/out")"
t_eq '...and so the exit code' 0 "$RC"
run -u '. "'"$LIB"'"; log_init demo; log_ok a; . "'"$LIB"'"; log_end'
t_eq 'sourcing twice keeps the count' 'demo: 1 ok, 0 failed, 0 warnings' "$(tail -1 "$W/out")"

t_section "log file: the same lines, timestamped, under <target>/backups/<tool>/<TS>/log"
TG="$T_TMP/tgt"; mkdir -p "$TG"; LP="$TG/backups/demo/20260927-120000/log"
run -u 'LOG_TS=20260927-120000; log_init demo; log_file "'"$TG"'"; log_head apply; log_ok a; log_fail "b"; log_fix "c"
log_end; rc=$?; printf "dir=%s\n" "$LOG_DIR" >&2; exit $rc'
t_eq 'the last screen line names the file' "log: $LP" "$(tail -1 "$W/out")"
t_eq 'the file exists at the contract path' yes "$(yn [ -f "$LP" ])"
t_eq 'every file line is the screen line behind an ISO-8601 UTC time' "$(got "$W/out")" "$(sed "s/^$ISO //" "$LP"; printf x)"
t_eq 'every file line carries the time' "$(wc -l < "$LP" | tr -d ' ')" "$(grep -c "^$ISO " "$LP")"
t_eq 'a failed run keeps its FAIL in the file' 1 "$(grep -c '^'"$ISO"'   FAIL: b$' "$LP")"
t_eq '...and exits 1' 1 "$RC"
t_eq 'LOG_DIR is the run dir, for backups beside the log' "dir=$TG/backups/demo/20260927-120000" "$(cat "$W/err")"
OLD="$(cat "$LP")"
run -u 'LOG_TS=20260927-120000; log_init demo; log_file "'"$TG"'"; log_ok second; log_end'
NP="$(tail -1 "$W/out" | sed 's/^log: //')"
t_eq 'a second run in the same second leaves the first log alone' "$OLD" "$(cat "$LP")"
t_has '...and writes its own beside it' "$NP" "$TG/backups/demo/20260927-120000-"
t_has '...which holds its lines' "$(cat "$NP" 2>/dev/null)" "  ok: second"
run -u 'log_init demo; log_file "'"$TG"'"; log_ok a; log_end'
t_eq 'the default TS is the backups one, %Y%m%d-%H%M%S' yes \
  "$(yn grep -qE '^log: .*/backups/demo/[0-9]{8}-[0-9]{6}/log$' "$W/out")"
run -u 'log_init demo; log_ok a; log_end'
t_hasnt 'no log_file, no log line' "$(cat "$W/out")" "log: "
t_has 'the positive control: the same run with a file names it' "$(run -u 'log_init demo; log_file "'"$TG"'"; log_end'; cat "$W/out")" "log: "

t_section "an unwritable log dir: said on stderr, the screen keeps logging, the caller is not failed"
BAD="$T_TMP/bad"; mkdir -p "$BAD"; : > "$BAD/backups"
run -eu 'log_init demo; log_file "'"$BAD"'"; log_ok a; log_warn w; log_nofix d; log_end; exit $?'
t_has 'stderr says the dir could not be made' "$(cat "$W/err")" "log-lib: could not create $BAD/backups/demo/"
t_has '...and that the screen still has the log' "$(cat "$W/err")" "logging to the screen only"
t_has 'the screen lines are all there' "$(cat "$W/out")" "demo: 1 ok, 0 failed, 1 warnings"
t_has 'the last line says there is no file, and why' "$(tail -1 "$W/out")" "log: none — could not create $BAD/backups/demo/"
t_eq 'set -e does not stop at log_file, and the exit code agrees with the summary' 0 "$RC"
run -u 'log_init demo; log_file "'"$BAD"'"; log_fail x; log_fix y; log_end; exit $?'
t_eq 'a failed run with no file still exits 1' 1 "$RC"
run -u 'LOG_TS=20260927-130000; log_init demo; log_file "'"$TG"'"; log_ok a; rm "$LOG_PATH"; mkdir "$LOG_PATH"; log_ok b; log_ok c; log_end'
t_eq 'a log that stops accepting writes is said once on stderr' 1 "$(grep -c 'stopped accepting writes' "$W/err")"
t_eq '...and nothing else is' 1 "$(wc -l < "$W/err" | tr -d ' ')"
t_has '...the screen keeps every line' "$(cat "$W/out")" "demo: 3 ok, 0 failed, 0 warnings"
t_eq '...and the last line says the file is incomplete' \
  "log: $TG/backups/demo/20260927-130000/log (incomplete — a write failed)" "$(tail -1 "$W/out")"

t_section "set -u, and nothing leaks into the caller"
run -u 'log_head h; log_ok; log_fail; log_fix; log_warn; log_nofix; log_note; log_skip; log_end; exit $?'
t_eq 'every function, no arguments, no log_init: stderr stays empty' "" "$(cat "$W/err")"
t_eq '...and the run still summarises' "demo: 1 ok, 1 failed, 1 warnings" "$(tail -1 "$W/out")"
t_eq '...with the exit code it states' 1 "$RC"
run -u 'printf "%s\n" "$nope"'
t_has 'the control: this set -u tool does die on an unset variable' "$(cat "$W/err")" "nope"
run +eu 'case $- in *u*|*e*) echo LEAK ;; *) echo clean ;; esac'
t_eq 'sourcing sets no shell option in its caller' clean "$(cat "$W/out")"

t_section "not a TTY: the same bytes to a pipe, a file and a terminal"
t_eq 'no terminal probe or escape code in the library' "" "$(grep -nE 'tput|\[ -t |\\033|\\e\[|\\x1b' "$LIB")"
printf '#!/bin/sh\nset -u\n. "%s"\nlog_init demo; log_head h; log_ok a; log_fail b; log_fix c; log_end\n' "$LIB" > "$W/tty.sh"
t_eq 'a pipe gets what a file gets' "$(sh "$W/tty.sh" > "$W/f"; got "$W/f")" "$(sh "$W/tty.sh" | cat; printf x)"
if script -q /dev/null true </dev/null >/dev/null 2>&1; then PTY="$(script -q /dev/null sh "$W/tty.sh" </dev/null 2>&1)"
else PTY="$(script -qec "sh $W/tty.sh" /dev/null </dev/null 2>&1)"; fi
t_has 'a pty gets the same lines (CR from the terminal aside)' "$(printf '%s' "$PTY" | tr -d '\r')" "$(cat "$W/f")"

t_section "a FAIL with no fix line is caught at run time"
run -u 'log_init demo; log_fail x; log_ok y; log_end; exit $?'
t_eq 'the library says so right after that FAIL, and counts it' "$(lines '  FAIL: x' \
  '  WARN: no fix line followed the FAIL above — demo breaks CONTRACTS/logging.md' \
  '  fix: none automatic — see CONTRACTS/logging.md' '  ok: y' 'demo: 1 ok, 1 failed, 1 warnings')" "$(got "$W/out")"
run -u 'log_init demo; log_fail x; log_end'
t_has 'a FAIL that ends the run with no fix is caught too' "$(cat "$W/out")" "no fix line followed the FAIL above"
run -u 'log_init demo; log_fail x; log_nofix y; log_fail z; log_fix w; log_end'
t_hasnt 'a FAIL followed by its fix is not flagged' "$(cat "$W/out")" "no fix line followed the FAIL above"

t_section "a FAIL with no fix line is caught statically, by lint LOG1"
FX="$T_TMP/fx"; mkdir -p "$FX/bin" "$FX/CONTRACTS"; cp "$LIB" "$FX/bin/log-lib.sh"
printf 'path\tkind\twhy\n' > "$FX/CONTRACTS/log-exempt.tsv"
printf '#!/usr/bin/env sh\n# fx (harbor#771)\nset -u\n. "$(dirname "$0")/log-lib.sh"\nlog_init fx\nlog_fail "x"\nlog_ok "y"\nlog_end\n' > "$FX/bin/fx.sh"
t_has 'LOG1 names the file and line of the FAIL' "$(HARBOR_ROOT="$FX" sh "$T_ROOT/bin/lint-conventions.sh" --only LOG1 2>&1)" \
  "VIOLATION [lint.log-contract] bin/fx.sh:6"
sed 's/^log_ok "y"$/log_fix "sh bin\/fx.sh --apply"/' "$FX/bin/fx.sh" > "$FX/bin/fx.tmp" && mv "$FX/bin/fx.tmp" "$FX/bin/fx.sh"
t_has '...and is silent once a fix follows it' "$(HARBOR_ROOT="$FX" sh "$T_ROOT/bin/lint-conventions.sh" --only LOG1 2>&1)" \
  "1 rules, 0 violations"

t_section "the reconcile interface: rows, the first-seen state, ages, cleared, could-not-judge (harbor#1031)"
# A tool that sources the library, with $S as its config dir; the body starts with status_init. A row is
# new on the run that first sees it and standing after, with its age; the state is kept by a run that judged only.
TB="$(printf '\t')"; S="$W/st"; rm -rf "$S"; mkdir -p "$S"
stt() { # <config dir> <body>: stdout in $W/out, stderr in $W/err, the tool's exit in RC
  printf '#!/bin/sh\nset -u\nLOG_FD=2\n. "%s"\nS="%s"\n%s\n' "$LIB" "$1" "$2" > "$W/st.sh"
  sh "$W/st.sh" > "$W/out" 2> "$W/err"; RC=$?
}
BODY='status_init demo-check "$S"; status_ok 3; status_drift r1 want1 have1 "do 1"; status_drift r2 want2 have2; status_end; exit $?'
stt "$S" "$BODY"
t_eq "a first run: the header, a new row per drift with age 0, the summary" \
  "$(lines "reconcile${TB}1${TB}demo-check" "new${TB}r1${TB}want1${TB}have1${TB}do 1${TB}0" "new${TB}r2${TB}want2${TB}have2${TB}-${TB}0" "summary${TB}5${TB}2${TB}0")" "$(got "$W/out")"
t_eq "...and it exits 1, drift being red" 1 "$RC"
t_eq "...and prints nothing else on stderr" "" "$(cat "$W/err")"
t_eq "the state is one key and one epoch per drifted row" "2 2" "$(wc -l < "$S/cache/reconcile/demo-check.tsv" | tr -d ' ') $(awk -F'\t' 'NF == 2 && $2 ~ /^[0-9]+$/ { n++ } END { print n }' "$S/cache/reconcile/demo-check.tsv")"
stt "$S" "$BODY"
t_eq "a second run with nothing changed prints no new row" 0 "$(grep -c "^new${TB}" "$W/out")"
t_eq "...both rows standing, each with an age in seconds" 2 "$(awk -F'\t' '$1 == "standing" && $6 ~ /^[0-9]+$/ { n++ } END { print n + 0 }' "$W/out")"
t_eq "...and nothing cleared" 0 "$(grep -c "^cleared${TB}" "$W/out")"
_then=$(( $(date +%s) - 5000 )); awk -F'\t' -v t="$_then" 'BEGIN { OFS = "\t" } { print $1, t }' "$S/cache/reconcile/demo-check.tsv" > "$S/t" && mv "$S/t" "$S/cache/reconcile/demo-check.tsv"
stt "$S" "$BODY"
t_eq "a row first seen 5000 s ago shows 5000 s, counted from the first sighting and not the last run" 2 \
  "$(awk -F'\t' '$1 == "standing" && $6 >= 5000 && $6 < 5060 { n++ } END { print n + 0 }' "$W/out")"
stt "$S" 'status_init demo-check "$S"; status_drift r1 want1 have1 "do 1"; status_end; exit $?'
t_eq "a row that converged is cleared, once, and the one that did not stays standing" \
  "r1 r2" "$(awk -F'\t' '$1 == "standing" { s = $2 } $1 == "cleared" { c = $2 } END { print s " " c }' "$W/out")"
t_eq "...with the summary counting it" "summary${TB}1${TB}1${TB}1" "$(grep "^summary" "$W/out")"
stt "$S" 'status_init demo-check "$S"; status_drift r1 want1 have1 "do 1"; status_end; exit $?'
t_eq "...and the next run does not report it again" 0 "$(grep -c "^cleared${TB}" "$W/out")"
stt "$S" 'status_init demo-check "$S"; status_ok 6; status_end; exit $?'
t_eq "everything converged: the last row is cleared, the summary is 6 examined, 0 drifted, and the exit is 0" \
  "cleared${TB}r1 summary${TB}6${TB}0${TB}1 0" "$(awk -F'\t' '$1 == "cleared" { c = "cleared" FS $2 } $1 == "summary" { s = "summary" FS $2 FS $3 FS $4 } END { print c " " s }' "$W/out") $RC"
t_eq "...and the state is empty, so a row that comes back is new again" "0" "$(wc -c < "$S/cache/reconcile/demo-check.tsv" | tr -d ' ')"

t_section "a key is unique within a report: reported twice, it is one row, counted once (CONTRACTS/reconcile.md)"
rm -rf "$S"; mkdir -p "$S"
DUP='status_init demo-check "$S"; status_ok 2; status_drift k want have; status_drift k want have; status_drift other w h; status_drift k want2 have2; status_end; exit $?'
stt "$S" "$DUP"
t_eq "the same key three times lists one row, the first" "new${TB}k${TB}want${TB}have${TB}-${TB}0 1" \
  "$(awk -F'\t' '$1 == "new" && $2 == "k" { print $1 FS $2 FS $3 FS $4 FS $5 FS $6 }' "$W/out") $(grep -c "^new${TB}k${TB}" "$W/out")"
t_eq "...the summary counts it once: 4 examined (2 ok, 2 drifted), 2 drifted" "summary${TB}4${TB}2${TB}0" "$(grep '^summary' "$W/out")"
t_eq "...and the state holds each key once" "2" "$(wc -l < "$S/cache/reconcile/demo-check.tsv" | tr -d ' ')"
stt "$S" "$DUP"
t_eq "...the second run lists it once, standing, and no row is new" "1 0" "$(grep -c "^standing${TB}k${TB}" "$W/out") $(grep -c "^new${TB}" "$W/out")"
rm -rf "$S"; mkdir -p "$S"
stt "$S" 'status_init demo-check "$S"; status_drift "a*" w h; status_drift ab w h; status_drift k w h; status_drift kk w h; status_drift "[k]" w h; status_drift K w h; status_drift "k k" w h; status_end; exit $?'
t_eq "valid but unusual: keys that only look alike (a glob, a prefix, a case, a bracket, a space) are seven rows, not folded" "7" "$(grep -c "^new${TB}" "$W/out")"
t_eq "...and the summary agrees" "summary${TB}7${TB}7${TB}0" "$(grep '^summary' "$W/out")"

t_section "a run that could not judge says so, exits 3 and leaves the ages alone"
stt "$S" "$BODY"; cp "$S/cache/reconcile/demo-check.tsv" "$W/st.keep"
stt "$S" 'status_init demo-check "$S"; status_unjudged "no registry, so nothing was judged"; exit $?'
t_eq "the header, then one unchecked record with the reason, and nothing else" \
  "$(lines "reconcile${TB}1${TB}demo-check" "unchecked${TB}no registry, so nothing was judged")" "$(got "$W/out")"
t_eq "...and the exit is 3" 3 "$RC"
t_eq "...and the first-seen state is byte for byte what it was" yes "$(cmp -s "$S/cache/reconcile/demo-check.tsv" "$W/st.keep" && echo yes || echo no)"
t_eq "...so the run after it still finds the rows standing" 0 "$(stt "$S" "$BODY"; grep -c "^new${TB}" "$W/out")"
t_eq "a blind run leaves no temp file behind" "demo-check.tsv" "$(ls -A "$S/cache/reconcile" | tr '\n' ' ' | sed 's/ $//')"

t_section "valid input that looks like a defect"
rm -rf "$S"; mkdir -p "$S"
stt "$S" 'status_init demo-check "$S"; status_drift "rule\n a\"q\" x" "w" "h"; status_end; exit $?'
stt "$S" 'status_init demo-check "$S"; status_drift "rule\n a\"q\" x" "w" "h"; status_end; exit $?'
t_eq "a key holding a backslash, a quote and spaces matches itself on the next run (it is standing, not new)" "standing" \
  "$(awk -F'\t' '$1 == "new" || $1 == "standing" { print $1 }' "$W/out")"
stt "$S" 'status_init demo-check "$S"; status_drift "k" "a	b" "c
d" "e"; status_end; exit $?'
t_eq "a tab or a line break inside a field becomes a space, so the row keeps its six fields" "6 a b c d" \
  "$(awk -F'\t' '$1 == "new" || $1 == "standing" { print NF " " $3 " " $4 }' "$W/out" | head -1)"
rm -rf "$S"; mkdir -p "$S"
stt "$S" 'status_init demo-check "$S"; status_end; exit $?'
t_eq "a run that examined nothing prints the header and a summary of zeros, and exits 0" "reconcile${TB}1${TB}demo-check summary${TB}0${TB}0${TB}0 0" \
  "$(awk '{ printf "%s ", $0 }' "$W/out" | sed 's/ $//') $RC"
rm -rf "$W/nodir"
stt "$W/nodir" 'status_init demo-check "$S"; status_drift k w h; status_end; exit $?'
t_eq "a config dir that does not exist is not made for the state: the row is standing with age -, and the exit is the verdict's" \
  "standing${TB}k${TB}w${TB}h${TB}-${TB}- 1 absent" "$(grep '^standing' "$W/out") $RC $([ -e "$W/nodir" ] && echo present || echo absent)"
t_eq "...without a warning, because nothing was lost" "" "$(cat "$W/err")"
rm -rf "$W/rodir"; mkdir -p "$W/rodir"; : > "$W/rodir/cache"
stt "$W/rodir" 'status_init demo-check "$S"; status_drift k w h; status_end; exit $?'
t_eq "a state dir that cannot be made is said on stderr, and the rows still print, standing with age -" \
  "standing${TB}k${TB}w${TB}h${TB}-${TB}- 1" "$(grep '^standing' "$W/out") $RC"
t_has "...and stderr says why" "$(cat "$W/err")" "first-seen state cannot be kept"
stt "$S" 'status_init "bad/id" "$S"; echo "rc=$?"'
t_eq "an id that is not a file name is refused and prints nothing" "rc=1" "$(cat "$W/out")"

t_section "pkg_hint names the install command for this OS (harbor#618)"
# A PATH holding only a uname that answers as asked and the one package manager under test, so the
# answer is the stub's and not whatever this host happens to have installed.
hint() { # <uname> <manager|-> <tool> -> pkg_hint's line
  _pb="$W/pk-$1-$2"; rm -rf "$_pb"; mkdir -p "$_pb"
  printf '#!/bin/sh\necho %s\n' "$1" > "$_pb/uname"; chmod +x "$_pb/uname"
  [ "$2" = - ] || { printf '#!/bin/sh\nexit 0\n' > "$_pb/$2"; chmod +x "$_pb/$2"; }
  PATH="$_pb" /bin/sh -c '. "$1"; pkg_hint "$2"' _ "$LIB" "$3"
}
t_eq "macOS: jq is a brew formula" "brew install jq" "$(hint Darwin - jq)"
t_eq "macOS: bun lives in a tap" "brew install oven-sh/bun/bun" "$(hint Darwin - bun)"
t_eq "macOS: python3 is the python formula" "brew install python" "$(hint Darwin - python3)"
t_eq "macOS: awk is gawk" "brew install gawk" "$(hint Darwin - awk)"
t_eq "Debian family: apt-get" "sudo apt-get install -y jq" "$(hint Linux apt-get jq)"
t_eq "Fedora family: dnf" "sudo dnf install -y jq" "$(hint Linux dnf jq)"
t_eq "Arch: pacman" "sudo pacman -S jq" "$(hint Linux pacman jq)"
t_eq "Alpine: apk" "sudo apk add jq" "$(hint Linux apk jq)"
t_eq "openSUSE: zypper" "sudo zypper install jq" "$(hint Linux zypper jq)"
t_eq "Arch names python3 python" "sudo pacman -S python" "$(hint Linux pacman python3)"
t_eq "Fedora names shellcheck ShellCheck" "sudo dnf install -y ShellCheck" "$(hint Linux dnf shellcheck)"
t_eq "Debian names awk gawk" "sudo apt-get install -y gawk" "$(hint Linux apt-get awk)"
t_has "bun has no distro package: it names its install page" "$(hint Linux apt-get bun)" "https://bun.sh/docs/installation"
t_has "gitleaks has no apt package: it names its releases" "$(hint Linux apt-get gitleaks)" "gitleaks/releases"
t_eq "gitleaks is a package on Arch" "sudo pacman -S gitleaks" "$(hint Linux pacman gitleaks)"
t_eq "no known manager still names the package" "install jq with your distro package manager" "$(hint Linux - jq)"
t_hasnt "a Linux answer never says brew" "$(for _m in apt-get dnf pacman apk zypper -; do hint Linux "$_m" jq; hint Linux "$_m" python3; done)" brew
t_exit "pkg_hint exits 0 under set -eu for an unknown tool" 0 env PATH="$W/pk-Linux--" /bin/sh -eu -c '. "$1"; pkg_hint nosuchtool >/dev/null' _ "$LIB"

t_section "slug_of_url and slug_valid: the three spellings a clone is given, and the shape one must have (harbor#1149)"
slug() { /bin/sh -c '. "$1"; slug_of_url "$2"' _ "$LIB" "$1"; }
valid() { /bin/sh -c '. "$1"; if slug_valid "$2"; then echo yes; else echo no; fi' _ "$LIB" "$1"; }
t_eq "https, with .git" "o/r" "$(slug https://github.com/o/r.git)"
t_eq "https, without it" "o/r" "$(slug https://github.com/o/r)"
t_eq "scp-like ssh" "o/r" "$(slug git@github.com:o/r.git)"
t_eq "ssh://, with a trailing slash" "o/r" "$(slug ssh://git@github.com/o/r/)"
t_eq "a user:token part is no spelling: nothing is printed, so a credential never is" "" "$(slug https://x:tok@github.com/o/r.git)"
t_eq "another host" "" "$(slug https://gitlab.com/o/r)"
t_eq "a local path" "" "$(slug /tmp/o/r)"
t_eq "a host that only contains github.com" "" "$(slug https://github.com.example/o/r)"
t_eq "a path that only contains github.com" "" "$(slug https://example.com/github.com/o/r)"
t_eq "no argument" "" "$(/bin/sh -eu -c '. "$1"; slug_of_url' _ "$LIB")"
t_eq "owner/name is valid" yes "$(valid o/r)"
t_eq "a name may hold . _ and -" yes "$(valid o-x/r_x.y-z)"
t_eq "one segment is not" no "$(valid o)"
t_eq "three are not" no "$(valid a/b/c)"
t_eq "an empty owner is not" no "$(valid /r)"
t_eq "an empty name is not" no "$(valid o/)"
t_eq "empty is not" no "$(valid '')"
t_eq "a leading dash is not, on either side" "no no" "$(valid -o/r) $(valid o/-r)"
t_eq "a leading dot in the name is not" no "$(valid o/.r)"
t_eq "a space is not" no "$(valid 'o/r s')"
t_eq "a shell metacharacter is not" no "$(valid 'o/r;x')"
t_eq "an underscore in the owner is not (github's own alphabet)" no "$(valid o_x/r)"

t_section "repo_slug: a checkout's origin, an install's pin, and nothing else (harbor#1149)"
RS="$W/rs"; rm -rf "$RS"; mkdir -p "$RS"
mktree() { # <dir> <pin line|-> <origin|-> -> a checkout shape: bin/, CONTRACTS/repo-slug.txt and a git origin
  mkdir -p "$1/bin" "$1/CONTRACTS"; git -C "$1" init -q
  [ "$2" = - ] || printf '# comment\n\n%s\n' "$2" > "$1/CONTRACTS/repo-slug.txt"
  [ -f "$1/CONTRACTS/repo-slug.txt" ] || : > "$1/CONTRACTS/repo-slug.txt"
  [ "$3" = - ] || git -C "$1" remote add origin "$3"
}
rslug() { /bin/sh -eu -c '. "$1"; repo_slug "$2"' _ "$LIB" "$1"; }
mktree "$RS/fork" pin/pinned https://github.com/other/fork.git
t_eq "in a checkout: that checkout's origin, not the pin" "other/fork" "$(rslug "$RS/fork/bin")"
mktree "$RS/ssh" pin/pinned git@github.com:ssh/owner.git
t_eq "an ssh origin names it too" "ssh/owner" "$(rslug "$RS/ssh/bin")"
mktree "$RS/local" pin/pinned "$RS/fork"
t_eq "an origin that is a local path is no name: the pin answers" "pin/pinned" "$(rslug "$RS/local/bin")"
mktree "$RS/noorigin" pin/pinned -
t_eq "no origin at all: the pin answers" "pin/pinned" "$(rslug "$RS/noorigin/bin")"
mktree "$RS/nopin" - https://github.com/other/nopin.git
t_eq "an origin needs no pin" "other/nopin" "$(rslug "$RS/nopin/bin")"
mktree "$RS/neither" - -
t_eq "no origin and an empty pin: nothing is printed" "" "$(rslug "$RS/neither/bin")"
t_exit "...and it is not a failure under set -eu" 0 /bin/sh -eu -c '. "$1"; repo_slug "$2" >/dev/null' _ "$LIB" "$RS/neither/bin"
t_eq "a worktree of the checkout answers with the origin it shares" "other/fork" \
  "$(git -C "$RS/fork" -c user.email=t@t -c user.name=t commit -q --allow-empty -m x; git -C "$RS/fork" worktree add -q "$RS/fork-wt" -b wt >/dev/null 2>&1; mkdir -p "$RS/fork-wt/bin" "$RS/fork-wt/CONTRACTS"; : > "$RS/fork-wt/CONTRACTS/repo-slug.txt"; rslug "$RS/fork-wt/bin")"
t_eq "a GIT_DIR a hook exported does not answer for the checkout" "other/fork" \
  "$(GIT_DIR="$RS/ssh/.git" GIT_WORK_TREE="$RS/ssh" rslug "$RS/fork/bin")"
t_eq "an inherited GIT_TRACE neither answers nor writes a file" "other/fork no" \
  "$(GIT_TRACE="$RS/trace" rslug "$RS/fork/bin") $([ -e "$RS/trace" ] && echo yes || echo no)"
t_eq "a global config's remote.origin.url is not the checkout's origin" "pin/pinned" \
  "$(H="$RS/home"; mkdir -p "$H"; printf '[remote "origin"]\n\turl = https://github.com/glob/al.git\n' > "$H/.gitconfig"; HOME="$H" rslug "$RS/noorigin/bin")"
mkdir -p "$RS/inst/bin"; printf '# the pin\n\r\n  \nacme/installed\r\nignored/second\n' > "$RS/inst/bin/repo-slug.txt"
t_eq "an install: the first line that is not blank or a comment, CRLF and all" "acme/installed" "$(rslug "$RS/inst/bin")"
t_eq "...and the pin alone: no git is run for an install" "acme/installed" \
  "$(mkdir -p "$RS/nogit"; printf '#!/bin/sh\necho git-was-run >&2; exit 1\n' > "$RS/nogit/git"; chmod +x "$RS/nogit/git"; PATH="$RS/nogit:$PATH" rslug "$RS/inst/bin" 2>&1)"
mkdir -p "$RS/inst2/bin"
t_eq "an install with no pin: nothing" "" "$(rslug "$RS/inst2/bin")"
printf 'not a slug\n' > "$RS/inst2/bin/repo-slug.txt"
t_eq "a pin that is not a slug: nothing, never the text" "" "$(rslug "$RS/inst2/bin")"
printf '# only a comment\n' > "$RS/inst2/bin/repo-slug.txt"
t_eq "a pin that is only comments: nothing" "" "$(rslug "$RS/inst2/bin")"
t_eq "a directory that does not exist: nothing" "" "$(rslug "$RS/nowhere/bin")"
mktree "$RS/registered" evil/pin https://github.com/evil/harbor.git
t_eq "an install never reads the registered checkout, PORT_ROOT, the environment or the private layer" "acme/installed" \
  "$(HARBOR_REPO="$RS/registered" PORT_ROOT="$RS" HARBOR_SCOPE_PRIVATE="$RS/registered" GITHUB_REPOSITORY=evil/env HARBOR_SLUG=evil/slug rslug "$RS/inst/bin")"
t_eq "...nor does a checkout read the environment" "other/fork" \
  "$(GITHUB_REPOSITORY=evil/env HARBOR_SLUG=evil/slug rslug "$RS/fork/bin")"
printf '#!/bin/sh\n. "%s"\nrepo_slug\n' "$LIB" > "$RS/fork/bin/ask.sh"
t_eq "with no argument it asks about the script that sourced it" "other/fork" "$(sh "$RS/fork/bin/ask.sh")"
t_eq "...also when the script is run by a bare name" "other/fork" "$(cd "$RS/fork/bin" && sh ask.sh)"

t_done
