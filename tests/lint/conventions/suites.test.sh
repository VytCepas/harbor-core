#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: suites, tools and the shell they are written in — F4's
# hermetic guard spawns (#348), C5's suite declarations (#150), C6's prove targets, C8's idle tools
# (#466), D2/D5's config gates (#212, #88), F12/F13's POSIX and quoting (#517, #299, #667) and C10 (#773).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

t_section "F4: a guard spawned with no CLAUDE_CONFIG_DIR (harbor#348)"
F4R="$TMP/f4root"; mkdir -p "$F4R/bin"
# Spawn targets are derived from bin/guard-*.sh; the content does not matter, only the name.
printf '#!/usr/bin/env sh\n' > "$F4R/bin/guard-bash.sh"; printf '#!/usr/bin/env sh\n' > "$F4R/bin/floor-hook.sh"
f4() { rm -f "$F4R"/bin/*-test.sh; printf '#!/usr/bin/env sh\n# fixture (harbor#348)\nset -u\nDIR=/x\n%s\n' "$2" > "$F4R/bin/$1"
  viol F4 "$F4R" | grep -c . ; }
t_eq "the LITERAL form is seen (the control on the harness)" 1 "$(f4 a-test.sh 'sh "$DIR/guard-bash.sh" --advisory')"
t_eq "the VARIABLE form is seen (the shape that occurs)" 1 "$(f4 b-test.sh 'G="$DIR/guard-bash.sh"
sh "$G" --advisory')"
t_eq "CLAUDE_CONFIG_DIR on the line exempts the literal form" 0 "$(f4 c-test.sh 'CLAUDE_CONFIG_DIR="$T" sh "$DIR/guard-bash.sh"')"
t_eq "CLAUDE_CONFIG_DIR on the line exempts the variable form" 0 "$(f4 d-test.sh 'G="$DIR/guard-bash.sh"
CLAUDE_CONFIG_DIR="$T" sh "$G"')"
t_eq "a COMMENT quoting the shape does not fire" 0 "$(f4 e-test.sh '# sh "$DIR/guard-bash.sh" is the shape this rule catches
: no spawn here')"
t_eq "a heredoc stub named guard-*.sh is not one of the repo's guards" 0 "$(f4 f-test.sh 'STUB="$SB/guard-stub.sh"
sh "$STUB"')"
t_eq "a suite outside the old hand-written list is checked" 1 "$(f4 zzz-unlisted-test.sh 'G="$DIR/guard-bash.sh"
sh "$G"')"

t_section "C5: suite path declarations (harbor#150)"
C5R="$TMP/c5"
_c5_setup() { # suite-paths.txt arrives on stdin
  rm -rf "$C5R"; mkdir -p "$C5R/bin" "$C5R/contracts"; cp "$LINT" "$C5R/bin/"
  for _s in alpha beta; do printf '#!/usr/bin/env sh\n# harbor#150 fixture\nset -eu\n' > "$C5R/bin/$_s-test.sh"; done
  printf 'alpha-test.sh\nbeta-test.sh\n' > "$C5R/contracts/suites.txt"
  cat > "$C5R/contracts/suite-paths.txt"
}
_c5() { sh "$C5R/bin/lint-conventions.sh" --only C5 2>&1; }
_GOOD='alpha-test.sh  bin/*
beta-test.sh   always
@no-suite      *.md'
printf '%s\n' "$_GOOD" | _c5_setup
_C5_BASE="$(_c5)"
t_hasnt "declarations that agree with the manifest are silent" "$_C5_BASE" 'VIOLATION [test.suite-paths]'
printf 'alpha-test.sh  bin/*\n@no-suite  *.md\n' | _c5_setup
_o="$(_c5)"
t_has "a manifest suite with no declaration is reported" "$(printf '%s\n' "$_o" | grep 'VIOLATION \[test.suite-paths\]')" 'beta-test.sh'
t_eq "…and raises the violation count (no subshell loss)" "$(($(vcount "$_C5_BASE") + 1))" "$(vcount "$_o")"
printf '%s\nghost-test.sh  bin/*\n' "$_GOOD" | _c5_setup
t_has "a declaration for a suite the manifest lacks is reported" "$(_c5 | grep 'VIOLATION \[test.suite-paths\]')" 'ghost-test.sh'
printf 'alpha-test.sh\nbeta-test.sh always\n@no-suite *.md\n' | _c5_setup
t_has "a key with no globs is reported" "$(_c5 | grep 'VIOLATION \[test.suite-paths\]')" 'no globs'
printf '%s\nalpha-test.sh  fixtures/*\n' "$_GOOD" | _c5_setup
t_has "the same suite declared twice is reported" "$(_c5 | grep 'VIOLATION \[test.suite-paths\]')" 'declared twice'
printf 'alpha-test.sh  bin/*\nbeta-test.sh   always\n' | _c5_setup
t_has "no @no-suite line is reported" "$(_c5 | grep 'VIOLATION \[test.suite-paths\]')" '@no-suite'
printf '%s\n' "$_GOOD" | _c5_setup; rm -f "$C5R/contracts/suite-paths.txt"
t_has "a deleted suite-paths.txt is reported" "$(_c5 | grep 'VIOLATION \[test.suite-paths\]')" 'is missing'

t_section "C10: a suite never inherits a HARBOR_* knob (harbor#773)"
C10R="$TMP/c10"; H='. "$(dirname "$0")/../../lib/core.sh"; t_init'
_c10_setup() { # <suite body> — one suite; bin/prog.sh reads HARBOR_K and HARBOR_M unset by default
  rm -rf "$C10R"; mkdir -p "$C10R/bin" "$C10R/contracts" "$C10R/tests/lib" "$C10R/tests/area"
  printf '#!/usr/bin/env sh\nk="${HARBOR_K:-}"; m="${HARBOR_M-}"\n' > "$C10R/bin/prog.sh"
  printf "T_PASS_ENV='HARBOR_M'\n" > "$C10R/tests/lib/core.sh"
  printf 'tests/area/s-test.sh\n' > "$C10R/contracts/suites.txt"; printf '%s\n' "$1" > "$C10R/tests/area/s-test.sh"
}
c10() { _c10_setup "$1"; viol C10 "$C10R" | grep -c .; }
t_eq "off the harness, a suite that runs a knob-reading program and clears nothing" 2 "$(c10 'sh "$R/bin/prog.sh"')"
t_has "…is named, with the program and the knob" "$(_c10_setup 'sh "$R/bin/prog.sh"'; viol C10 "$C10R")" \
  'tests/area/s-test.sh runs prog.sh, which reads HARBOR_K unset by default'
t_eq "…and is silent once it unsets both" 0 "$(c10 'unset HARBOR_K HARBOR_M
sh "$R/bin/prog.sh"')"
t_eq "a statement that is only an assignment clears one" 1 "$(c10 'HARBOR_K=; export HARBOR_K
sh "$R/bin/prog.sh"')"
t_eq "a per-command prefix clears nothing: the calls it does not prefix still inherit" 2 \
  "$(c10 'HARBOR_K=1 HARBOR_M=2 sh "$R/bin/prog.sh"')"
t_eq "a program named only as data is not run" 0 "$(c10 'cp "$R/bin/prog.sh" "$T/x"')"
t_eq "a comment that runs it is not code" 0 "$(c10 '# sh "$R/bin/prog.sh"')"
t_eq "a program run through a variable is run" 2 "$(c10 'P="$R/bin/prog.sh"
sh "$P"')"
t_eq "on the harness t_init clears one knob, and the T_PASS_ENV one is left" 1 "$(c10 "$H"'
sh "$R/bin/prog.sh"')"
t_eq "a suite that reads a knob after t_init emptied it" 1 "$(c10 "$H"'
x="${HARBOR_Q:-}"')"
t_eq "…is silent when it reads the knob before t_init" 0 "$(c10 'x="${HARBOR_Q:-}"
'"$H")"
t_eq "…or assigns it first" 0 "$(c10 "$H"'
HARBOR_Q=1; export HARBOR_Q
y="${HARBOR_Q:-}"')"
t_eq "a single-quoted stub body is not the suite reading the knob" 0 "$(c10 "$H
printf 'x=\"\${HARBOR_Q:-}\"' > \"\$T/stub\"")"
t_eq "…nor is a quoted heredoc body" 0 "$(c10 "$H
cat > \"\$T/stub\" <<'EOF'
x=\"\${HARBOR_Q:-}\"
EOF")"
t_eq "…but an unquoted one expands in the suite, so it is" 1 "$(c10 "$H
cat > \"\$T/stub\" <<EOF
x=\"\${HARBOR_Q:-}\"
EOF")"

t_section "C6: prove targets take their kinds from the engine (skills/test-strength)"
C6R="$TMP/c6"
_c6_setup() { # <subject-kind written into the target>
  rm -rf "$C6R"; mkdir -p "$C6R/bin" "$C6R/contracts" "$C6R/skills/test-strength/bin" "$C6R/skills/test-strength/targets"
  cp "$LINT" "$C6R/bin/"; : > "$C6R/contracts/suites.txt"; : > "$C6R/contracts/suite-paths.txt"
  printf '#!/usr/bin/env sh\ncase "$1" in --mutators) printf "zzz-fixture-kind zzz-op\\n" ;; esac\n' > "$C6R/skills/test-strength/bin/prove.sh"
  printf 'target        probe\nsubject-kind  %s\nlane          fast\ncost          1\nseed          probe/seed.md\nplace         $WORK/probe.md\nchecker-cmd   true\ngreen         0\nred           1\n' \
    "$1" > "$C6R/skills/test-strength/targets/probe.target"
}
_c6() { sh "$C6R/bin/lint-conventions.sh" --only C6 2>&1; }
C6_KIND='unknown subject-kind'
_c6_setup zzz-fixture-kind
t_hasnt "a kind only the engine lists is accepted: the list is read, not restated" "$(_c6)" "$C6_KIND"
_c6_setup not-a-kind-at-all
t_has "a kind no engine lists is refused" "$(_c6)" "$C6_KIND"
printf '#!/usr/bin/env sh\nexit 0\n' > "$C6R/skills/test-strength/bin/prove.sh"
t_has "an engine that lists nothing makes C6 loud" "$(_c6)" 'printed nothing'

t_section "C8: a tool nothing runs is a declared state (harbor#466)"
C8R="$TMP/c8"
_c8_setup() { # <idle-tools.txt body after the linter's own line>
  rm -rf "$C8R"; mkdir -p "$C8R/bin" "$C8R/contracts" "$C8R/hooks"; cp "$LINT" "$C8R/bin/"
  : > "$C8R/contracts/suites.txt"; : > "$C8R/contracts/suite-paths.txt"
  printf '#!/usr/bin/env sh\nsh bin/wired.sh\n' > "$C8R/hooks/pre-commit"
  printf '#!/usr/bin/env sh\nexit 0\n' > "$C8R/bin/wired.sh"; printf '#!/usr/bin/env sh\nexit 0\n' > "$C8R/bin/lonely.sh"
  printf 'lint-conventions.sh  VERB  the linter itself\n%s' "$1" > "$C8R/contracts/idle-tools.txt"
}
_c8() { sh "$C8R/bin/lint-conventions.sh" --only C8 2>&1 | grep '\[lint.tool-has-caller\]'; }
C8_NONE='nothing calls bin/lonely.sh'
_c8_setup ''
t_has "a tool with no caller and no declaration is reported" "$(_c8)" "$C8_NONE"
_IDLE='lonely.sh  IDLE  nothing points it at the box yet
'
_c8_setup "$_IDLE"
t_hasnt "a declared idle tool is discharged" "[$(_c8)]" 'lonely.sh'
_c8_setup "$_IDLE"; printf '#!/usr/bin/env sh\nsh "$(dirname "$0")/lonely.sh"\n' > "$C8R/bin/lonely-test.sh"
t_hasnt "a TEST calling the tool is not a caller" "[$(_c8)]" 'lonely.sh'
_c8_setup "$_IDLE"; printf '#!/usr/bin/env sh\nsh bin/lonely.sh\n' > "$C8R/hooks/post-commit"
t_has "a declaration goes stale once a real caller appears" "$(_c8)" 'idle, but something invokes it'
_c8_setup ''; printf '#!/usr/bin/env sh\ncat <<U\nusage: sh bin/lonely.sh --help\nU\n' > "$C8R/bin/lonely.sh"
t_has "a script naming ITSELF in its usage text is not a caller" "$(_c8)" "$C8_NONE"
_c8_setup 'ghost.sh  IDLE  a file that is not there
'
t_has "a manifest line naming a missing tool is reported" "$(_c8)" 'does not exist: bin/ghost.sh'
_c8_setup ''; rm -f "$C8R/hooks/pre-commit"
t_has "a sweep that found nothing names itself" "$(_c8)" 'the caller sweep found no invocation anywhere'
_c8_setup ''; rm -f "$C8R/contracts/idle-tools.txt"
t_has "no manifest is reported" "$(_c8)" 'idle-tools.txt is missing'

t_section "D2: the --live gate must be CODE, not prose (harbor#212)"
D2R="$TMP/d2root"; mkdir -p "$D2R/bin"
printf '%s\n' '#!/usr/bin/env sh' '# This tool refuses the live config dir without an explicit --live.' \
  '# ...except it does not: there is no gate below, only this sentence.' \
  'case "${1:-}" in --apply) APPLY=1 ;; esac' > "$D2R/bin/comment-only.sh"
_gate='if [ "$_t" = "$HOME/.claude" ] && [ -z "${LIVE_OK:-}" ]; then'
printf '%s\n' '#!/usr/bin/env sh' 'case "${1:-}" in --apply) APPLY=1 ;; --live) LIVE_OK=1 ;; esac' \
  '_t="$(CDPATH= cd -P -- "${TARGET:-.}" && pwd -P)"' "$_gate" \
  '  echo "properly-gated: refusing the live config dir without an explicit --live" >&2' '  exit 1' 'fi' > "$D2R/bin/properly-gated.sh"
printf '%s\n' '#!/usr/bin/env sh' '# A real gate, but a raw string compare. The resolved-path idiom pwd -P appears' \
  '# only in this sentence — the code below never resolves anything.' \
  'case "${1:-}" in --apply) APPLY=1 ;; --live) LIVE_OK=1 ;; esac' \
  'if [ "${TARGET:-.}" = "$HOME/.claude" ] && [ -z "${LIVE_OK:-}" ]; then' \
  '  echo "string-compare: refusing the live config dir without an explicit --live" >&2' '  exit 1' 'fi' > "$D2R/bin/string-compare.sh"
printf '%s\n' '#!/usr/bin/env sh' '# Never write the gate as' \
  '#  if [ "$_t" = "$HOME/.claude" ] && [ "${1:-}" != --live ]; then' \
  '# because the arg loop accepts --live anywhere. This tool does it properly:' \
  'case "${1:-}" in --apply) APPLY=1 ;; --live) LIVE_OK=1 ;; esac' \
  '_t="$(CDPATH= cd -P -- "${TARGET:-.}" && pwd -P)"' "$_gate" \
  '  echo "quotes-the-bad-shape: refusing the live config dir without an explicit --live" >&2' '  exit 1' 'fi' \
  > "$D2R/bin/quotes-the-bad-shape.sh"
printf '%s\n' '#!/usr/bin/env sh' '# A suite exercising a mutator'"'"'s --apply) arm needs no --live gate of its own.' \
  'sh ./thing.sh --apply' > "$D2R/bin/thing-test.sh"
OUT_D2="$(viol D2 "$D2R")"
t_has "a gate that exists only in a COMMENT is reported" "$OUT_D2" 'mutator without a --live gate: bin/comment-only.sh'
t_hasnt "a real gate in executable code stays silent" "$OUT_D2" 'properly-gated.sh'
t_hasnt "a *-test.sh exercising an --apply arm is exempt as a class" "$OUT_D2" 'thing-test.sh'
t_has "a resolved-path idiom only in a COMMENT is reported" "$OUT_D2" 'compares strings, not resolved paths: bin/string-compare.sh'
t_hasnt "quoting the harbor#52 bad shape in prose is not a violation" "$OUT_D2" 'quotes-the-bad-shape.sh'

t_section "D5: a Read deny needs its Edit twin (harbor#88)"
d5() { mkdir -p "$1/bin"; printf '#!/usr/bin/env sh\n%s\n' "$2" > "$1/bin/floor-deny.sh"
  printf '#!/usr/bin/env sh\nDENY=%s[]%s\n' "'" "'" > "$1/bin/deploy-harden.sh"; viol D5 "$1"; }
_q="'"
t_has "a Read-denied path with no Edit twin is reported" \
  "$(d5 "$TMP/d5-red" "ADD=${_q}[ \"Read(//**/.probe-secret)\" ]${_q}")" 'Edit(//**/.probe-secret)'
t_eq "the same path WITH its Edit twin goes green" "" \
  "$(d5 "$TMP/d5-green" "ADD=${_q}[ \"Read(//**/.probe-secret)\", \"Edit(//**/.probe-secret)\" ]${_q}")"
t_has "a twin that exists only in a COMMENT does not count" "$(d5 "$TMP/d5-comment" "# \"Edit(//**/.probe-secret)\" is what we should add
ADD=${_q}[ \"Read(//**/.probe-secret)\" ]${_q}")" 'Edit(//**/.probe-secret)'
t_eq "Edit-without-Read is a posture, not a violation" "" "$(d5 "$TMP/d5-editonly" "ADD=${_q}[ \"Edit(~/.claude/settings.json)\" ]${_q}")"
# Aimed at what D5 reads (#531): byte copies of the writers on its _d5src line, read from that line.
D5REAL="$TMP/d5-real"; mkdir -p "$D5REAL/bin"; _d5n=0
for _d5f in $(sed -n 's/^_d5src="\(.*\)"$/\1/p' "$LINT" | sed 's|\$ROOT/||g'); do
  cp "$ROOT/$_d5f" "$D5REAL/$_d5f" && _d5n=$((_d5n + 1))
done
t_eq "the real-writers fixture copied what _d5src names" yes "$([ "$_d5n" -gt 0 ] && echo yes || echo no)"
t_eq "D5 is clean on harbor's own writers" "" "$(viol D5 "$D5REAL")"

t_section "F12: every script is POSIX under sh (harbor#517)"
if command -v shellcheck >/dev/null 2>&1; then
  F12R="$TMP/f12"; mkdir -p "$F12R/bin" "$F12R/skills" "$F12R/tests/x"
  printf '#!/usr/bin/env sh\n# f12 (harbor#517)\nset -eu\narr=(a b)\nprintf "%%s\\n" "${arr[0]}"\n' > "$F12R/bin/bashism.sh"
  cp "$F12R/bin/bashism.sh" "$F12R/tests/x/bashism-test.sh"
  printf '#!/usr/bin/env sh\n# f12 (harbor#517)\nset -eu\nprintf "%%s\\n" ok\n' > "$F12R/bin/clean.sh"
  chmod +x "$F12R/bin/bashism.sh" "$F12R/bin/clean.sh"
  _o="$(lint1 F12 "$F12R" | grep -E '\[posix.shellcheck\]')"
  t_has "a bash array is reported" "$_o" 'bin/bashism.sh'
  t_has "a bash array in a tests/ suite is reported" "$_o" 'tests/x/bashism-test.sh'
  t_hasnt "a clean POSIX script is not reported" "$_o" 'clean.sh'
  A12R="$TMP/f12abort"; mkdir -p "$A12R/bin" "$A12R/skills"
  # The array sits after a comment that opens with the tool's name, so a blinded parse sees neither.
  { printf '#!/usr/bin/env sh\n# f12 abort (harbor#517)\nset -eu\n'
    printf '# %s is mentioned first here, which makes this a directive\n' "$(printf 'shell''check')"
    printf 'arr=(a b)\nprintf "%%s\\n" "${arr[0]}"\n'; } > "$A12R/bin/aborts.sh"
  chmod +x "$A12R/bin/aborts.sh"
  t_has "a directive-shaped prose comment is reported as an ABORT" "$(lint1 F12 "$A12R")" 'ABORTED here'
  sed 's|^# shellcheck is mentioned first here.*|# The tool is named later in this sentence, so it is prose.|' "$A12R/bin/aborts.sh" \
    > "$A12R/bin/aborts.sh.new" && mv "$A12R/bin/aborts.sh.new" "$A12R/bin/aborts.sh"
  t_eq "…and the abort was HIDING a real bashism" yes "$(hasre "$(lint1 F12 "$A12R")" 'not POSIX under sh.*aborts\.sh')"
  # harbor#811: test's mtime operators, which shellcheck 0.11 stopped reporting. Spliced in with
  # printf, so this suite's own text never carries one (F12 reads tests/ too).
  T12R="$TMP/f12test"; mkdir -p "$T12R/bin" "$T12R/skills"
  _t12() { printf '#!/usr/bin/env sh\n# f12 (harbor#811)\nset -eu\n%s\n' "$2" > "$T12R/bin/$1"; }
  _t12 nt.sh "$(printf 'if [ "$1" -%s "$2" ]; then echo y; fi' nt)"
  _t12 ot.sh "$(printf 'test "$1" -%s "$2" && echo y' ot)"
  _t12 ef.sh "$(printf '[ -f "$1" ] || [ "$1" -%s "$2" ] || echo y' ef)"
  _t12 prose.sh "$(printf '# [ "$1" -%s "$2" ] in a comment is prose\nps -%s | head -1\n[ -n "$1" ] && ps -%s' nt ef ef)"
  _o="$(lint1 F12 "$T12R" | grep -E '\[posix.shellcheck\]')"
  t_has "a -nt comparison is reported, with its line" "$_o" 'bin/nt.sh:4'
  t_has "a -ot comparison in test(1) form is reported" "$_o" 'bin/ot.sh:4'
  t_has "an -ef comparison after another test is reported" "$_o" 'bin/ef.sh:4'
  t_hasnt "a comment, and ps -ef outside a test, are not" "$_o" 'prose.sh'
else
  printf '  SKIP: shellcheck is not installed, so F12 and F13 have nothing to prove here\n'
  t_has "F12 says it verified nothing" "$(lint1 F12 "$TMP")" 'this rule verified NOTHING'
fi

t_section "F13: an apostrophe inside a single-quoted program (harbor#299)"
if command -v shellcheck >/dev/null 2>&1; then
  F13R="$TMP/f13"; mkdir -p "$F13R/bin" "$F13R/skills"
  _f13_write() { # <file> <comment inside the awk program>; built with printf, so this file quotes cleanly
    { printf '#!/usr/bin/env sh\n# f13 fixture (harbor#299)\n'; printf 'printf %s | awk %s\n' "'a b\\n'" "'"
      printf '  # %s\n' "$2"; printf '  { print "field1=" $1 }\n'; printf "'\n"; } > "$1"; }
  _f13_write "$F13R/bin/odd.sh" "the row s own grammar has one apostrophe here: it's"
  t_has "ONE apostrophe in a comment inside an awk program is reported" "$(lint1 F13 "$F13R")" 'odd.sh'
  rm -f "$F13R/bin/odd.sh"
  _f13_write "$F13R/bin/even.sh" "the row's own grammar and the window's LENGTH"
  t_has "TWO apostrophes are reported, the case sh -n misses" "$(lint1 F13 "$F13R")" 'even.sh'
  t_exit "…and sh -n really does pass that file (the premise)" 0 sh -n "$F13R/bin/even.sh"
  rm -f "$F13R/bin/even.sh"
  _f13_write "$F13R/bin/clean.sh" "the row own grammar, no apostrophes at all"
  t_hasnt "a program with no apostrophe is not reported" "$(lint1 F13 "$F13R")" 'clean.sh'
  rm -f "$F13R/bin/clean.sh"
  { printf '#!/usr/bin/env sh\n# f13 fixture (harbor#299)\n'
    printf '# This comment has the operator%ss apostrophe and a contraction: it%ss fine.\n' "'" "'"
    printf 'printf %s\n' "'ok\\n'"; printf "printf '%%s\\\\n' '\$HOME stays literal'\n"; } > "$F13R/bin/prose.sh"
  t_hasnt "an apostrophe in an ORDINARY shell comment does not fire" "$(lint1 F13 "$F13R")" 'prose.sh'
  t_has "…though the same file carries another finding (SC2016), which F13 must not report" \
    "$(shellcheck -s sh -f gcc "$F13R/bin/prose.sh" 2>&1)" 'SC2016'
else
  t_has "F13 says it verified nothing" "$(lint1 F13 "$TMP")" 'this rule verified NOTHING'
fi

t_done
