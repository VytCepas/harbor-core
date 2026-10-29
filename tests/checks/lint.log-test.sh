#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: LOG1, the one log format (harbor#771, CONTRACTS/logging.md).
# Each arm plants one defect beside a clean twin and asks LOG1 alone about a root holding only what it
# reads. The ratchet arms run on a git fixture: a base, a stale-branch control, and a HARBOR_BASE override.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
R="$TMP/log1"
fresh() { rm -rf "$R"; mkdir -p "$R/bin" "$R/CONTRACTS"; cp "$SRC/log-lib.sh" "$R/bin/"; printf 'path\tkind\twhy\n' > "$R/CONTRACTS/log-exempt.tsv"; }
tool() { # <file> <line>...: a bin/ tool on log-lib; its first body line is line 6
  _tf="$1"; shift
  { printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\n. "$(dirname "$0")/log-lib.sh"\nlog_init x\n'; printf '%s\n' "$@"; } > "$R/bin/$_tf"
}
plain() { printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\necho "%s"\n' "${2:-hi}" > "$R/bin/$1"; }
row() { printf '%s\t%s\t%s\n' "$1" "${2:-ratchet}" "${3-fixture}" >> "$R/CONTRACTS/log-exempt.tsv"; }
# GNU sed -i takes no separate suffix argument and BSD sed -i demands one, so neither spelling runs on both (harbor#865).
sedi() { sed "$1" "$2" > "$2.sedi" && mv "$2.sedi" "$2"; }
L() { lint1 LOG1 "${1:-$R}"; }
green() { t_eq "silent on $1" "" "$(viol LOG1 "${2:-$R}")"; t_has "...and LOG1 ran on it" "$(L "${2:-}")" '1 rules, 0 violations'; }

t_section "(a) every shell program in bin/ is in the standard or has a row"
fresh; tool ok.sh 'log_ok done' 'log_end'
green "a tool on log-lib, and log-lib itself"
plain plain.sh
t_has 'a tool outside the standard with no row is red' "$(L)" "VIOLATION [lint.log-contract] bin/plain.sh logs outside the standard and has no row"
row bin/plain.sh; green "the same tool once it has a row"
printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\necho hi\n' > "$R/bin/cli"
t_has 'an extensionless shell program is in the domain' "$(L)" "VIOLATION [lint.log-contract] bin/cli logs outside the standard"
rm "$R/bin/cli"; printf '// fixture (harbor#771)\nconsole.log("✓ hi");\n' > "$R/bin/page.mjs"
green "a Node program, which cannot source a sh library"
printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\n# fixture (harbor#771)\ncase "$x" in *[!!-~]*) exit 2 ;; esac\nexit 0\n' > "$R/bin/guard-x.sh"
green "a floor file (channel 2) needs no row, and a bracket holding !! is not a mark"
printf '. "$(dirname "$0")/log-lib.sh"\n' >> "$R/bin/guard-x.sh"
t_has 'a floor file that sources log-lib is red' "$(L)" "VIOLATION [lint.log-contract] bin/guard-x.sh is a floor file (channel 2) and sources log-lib.sh"

t_section "(a) a log-lib user prints no status mark, TAG line or header of its own"
fresh; tool m.sh 'printf "  %s\n" "$data"' 'echo "ok then"' '# printf "  ✓ %s\n" in a comment' 'log_ok done' 'log_end'
green "plain data, a word that is not a TAG, and a mark in a comment"
tool m.sh 'printf "  ✓ %s\n" done' 'log_end'
t_has 'a check mark is red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints a ✓/✗ status mark itself"
tool m.sh 'echo "m: REFUSING — no"' 'log_end'
t_has 'a REFUSING prefix is red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints an ERROR:/REFUSING/FAILED: status prefix itself"
tool m.sh "printf '%s\\n' \"!! careful\"" 'log_end'
t_has 'a mark behind a leading %s is red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints a • or !! status mark itself"
tool m.sh "printf '  FAIL: %s\\n' x" 'log_end'
t_has 'a TAG line printed around the library is red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints a TAG line itself"
tool m.sh "printf '── %s\\n' step" 'log_end'
t_has 'a header printed around the library is red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints a header line itself"
tool m.sh 'log_ok done'
t_has 'log lines with no log_end are red' "$(L)" "VIOLATION [lint.log-contract] bin/m.sh prints log lines and never calls log_end"
fresh; tool lib-x.sh 'log_ok done'
t_has 'a lib nothing sources, with log lines and no log_end, is red' "$(L)" "VIOLATION [lint.log-contract] bin/lib-x.sh prints log lines and never calls log_end"
tool main.sh '. "$(dirname -- "$0")/lib-x.sh"' 'log_ok hi'
t_has '...and red when the script that sources it never ends the log either' "$(L)" "VIOLATION [lint.log-contract] bin/lib-x.sh prints log lines and never calls log_end"
tool main.sh '. "$(dirname -- "$0")/lib-x.sh"' 'log_end'
green "a lib whose log_end lives in the script that sources it (harbor#1060)"

t_section "(a) a retired tag (D-29, CONTRACTS/logging.md \"Retired tags\") is refused, every row of the table"
# The rows come from the contract itself: a row LOG1 does not refuse fails here, and a word LOG1 refuses with no row fails below.
RT="$TMP/retired.tags"
awk '/^## Retired tags/ { on = 1; next } /^## / { on = 0 } on && /^\| `/ { c = $0; sub(/^\| `/, "", c); sub(/` \|.*$/, "", c); print c }' "$T_ROOT/CONTRACTS/logging.md" > "$RT"
t_eq "the table is read, and holds the glyphs, the prefixes and the D-29 words" yes \
  "$([ "$(grep -c . "$RT")" -ge 15 ] && grep -qxF 'PASS:' "$RT" && grep -qxF 'UNCHECKED:' "$RT" && grep -qxF '✓' "$RT" && echo yes || echo no)"
fresh; tool ok.sh 'log_ok done' 'log_end'
while IFS= read -r _rt; do
  tool m.sh "echo \"$_rt x\"" 'log_end'
  t_has "retired $_rt is red" "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints "
  tool m.sh "printf '%s\\n' \"$_rt x\"" 'log_end'
  t_has "...behind a leading %s too ($_rt)" "$(L)" "VIOLATION [lint.log-contract] bin/m.sh:6: prints "
done < "$RT"
tool m.sh 'echo "PASS: done"' 'log_end'
t_has 'the message names the retired word and its successor' "$(L)" "bin/m.sh:6: prints the retired tag PASS: (use ok) itself, around log-lib"
tool m.sh 'echo "UNCHECKED: no node"' 'log_end'
t_has 'UNCHECKED points at the FAIL line and exit 3' "$(L)" "the retired tag UNCHECKED: (use FAIL, its fix, exit 3)"
# the other direction: every word LOG1's D-29 list refuses has its row
_lw="$(sed -n 's#.*match(s, /^\[\[:space:\]\]\*(\(PASS|[A-Z|]*\)):/).*#\1#p' "$T_ROOT/bin/lint-conventions.sh" | head -1 | tr '|' '\n')"
t_eq "LOG1's retired-word list is found in its source" yes "$([ "$(printf '%s\n' "$_lw" | grep -c .)" -ge 8 ] && echo yes || echo no)"
_missing=""; for _w in $_lw; do grep -qxF "$_w:" "$RT" || _missing="$_missing $_w"; done
t_eq "every word LOG1 refuses has a row in the table" "" "$_missing"
# valid but unusual: words that start like a tag, or sit where a tag never is, stay green
fresh; tool u.sh 'echo "PASSWORD: not a tag"' 'echo "SKIPPED_COUNT=3"' 'printf "%s: PASS\n" "$name"' 'echo "okay: fine"' 'echo "OK"' 'echo "Retired: PASS and SKIP"' \
  'printf "WARNING      : a padded report label\n"' 'printf "SKIP  %-26s %s\n" "$s" "$r"' 'echo "see PASS: inside a sentence is data"' '# echo "PASS: in a comment"' 'log_ok done' 'log_end'
green "a word that only starts like a retired tag, a padded label, a column, and a mention in a comment"

t_section "(b) every FAIL is followed by a fix on its path"
fresh; tool f.sh 'log_fail "bin/f.sh:9 could not exit or return"' 'log_fix "sh bin/f.sh --apply"' \
  "log_fail 'bin/f.sh:10 did not exit, else return'" 'log_nofix "harbor#771"' 'die() { log_fail "$1"; log_nofix "$2"; log_end; exit 1; }' 'log_fail x' '[ -n "$y" ] && log_fix "$y"' 'log_end'
green "a fix after a FAIL, a breaker word in a string, a die helper, and a conditional fix (run time's job)"
tool f.sh 'log_fail x' 'log_ok y' 'log_end'
t_has 'the next log line is not a fix' "$(L)" "VIOLATION [lint.log-contract] bin/f.sh:6: a FAIL with no fix line on its path — the next log line is log_ok on line 7"
tool f.sh 'log_fail x; exit 1' 'log_end'
t_has 'the path exits first' "$(L)" "bin/f.sh:6: a FAIL with no fix line on its path — the path leaves at exit on line 6"
tool f.sh 'if [ -n "$a" ]; then' '  log_fail x' 'else' '  log_fix y' 'fi' 'log_end'
t_has 'the fix is on the other branch' "$(L)" "bin/f.sh:7: a FAIL with no fix line on its path — the path leaves at else on line 8"
tool f.sh 'case "$a" in' '  a) log_fail x ;;' '  b) log_fix y ;;' 'esac' 'log_end'
t_has 'the fix is in another case arm' "$(L)" "bin/f.sh:7: a FAIL with no fix line on its path — the case arm ends on line 7"
tool f.sh 'f() {' '  log_fail x' '}' 'log_fix y' 'log_end'
t_has 'the function ends first' "$(L)" "bin/f.sh:7: a FAIL with no fix line on its path — the function ends on line 8"
tool f.sh 'log_end' 'log_fail x'
t_has 'the file ends first' "$(L)" "bin/f.sh:7: a FAIL with no fix line on its path — the file ends first"

t_section "(c) the ratchet: an exempt file must not change, and the list only shrinks"
G="$TMP/log1-git"; rm -rf "$G"; mkdir -p "$G/bin" "$G/CONTRACTS"; cp "$SRC/log-lib.sh" "$G/bin/"
for _n in old conv gone; do printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\necho "%s"\n' "$_n" > "$G/bin/$_n.sh"; done
printf 'path\tkind\twhy\nbin/old.sh\twave-B\tfixture\nbin/conv.sh\tratchet\tfixture\nbin/gone.sh\tratchet\tfixture\n' > "$G/CONTRACTS/log-exempt.tsv"
gx() { git -C "$G" "$@" >/dev/null 2>&1; }
gx init -q .; gx config user.email t@t; gx config user.name t; gx config commit.gpgsign false
gx add -A; gx commit -qm base; gx branch -M main; gx checkout -qb feature; gx update-ref refs/remotes/origin/main main
green "exempt files unchanged since the base" "$G"
printf 'echo edited\n' >> "$G/bin/old.sh"
t_has 'an edited exempt file is red, uncommitted' "$(L "$G")" "VIOLATION [lint.log-contract] bin/old.sh changed since the base and is exempt"
gx commit -qam edit
t_has '...and committed' "$(L "$G")" "VIOLATION [lint.log-contract] bin/old.sh changed since the base and is exempt"
gx tag later; t_has 'HARBOR_BASE names the base: at a ref holding the edit, it is no change' \
  "$(HARBOR_BASE=later lint1 LOG1 "$G")" '1 rules, 0 violations'
gx reset -q --hard main; chmod 755 "$G/bin/old.sh"
green "a mode change alone (content is compared, the bit is S6's)" "$G"
gx checkout -q main; printf 'echo main-moved\n' >> "$G/bin/old.sh"; gx commit -qam 'main edits old'
gx update-ref refs/remotes/origin/main main; gx checkout -q feature
t_eq 'the control: main edited old.sh after this branch forked' 1 "$(git -C "$G" diff --name-only origin/main -- bin/old.sh | grep -c .)"
green "a stale branch behind a main that edited an exempt file (the merge-base, not the tip)" "$G"
t_has 'no base resolves: said, never read as clean' "$(HARBOR_BASE=nope lint1 LOG1 "$G")" "ADVISORY [lint.log-contract] no base (nope)"
rm "$G/bin/gone.sh"
t_has 'a row whose file is gone is an advisory' "$(L "$G")" "ADVISORY [lint.log-contract] CONTRACTS/log-exempt.tsv lists bin/gone.sh, which is gone"
t_has '...not a violation' "$(L "$G")" '1 rules, 0 violations'
printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\necho new\n' > "$G/bin/new.sh"; printf 'bin/new.sh\tratchet\tfixture\n' >> "$G/CONTRACTS/log-exempt.tsv"
t_has 'a new file cannot be exempt' "$(L "$G")" "VIOLATION [lint.log-contract] bin/new.sh is new since the base, so it cannot be exempt"
rm "$G/bin/new.sh"; printf '. "$(dirname "$0")/log-lib.sh"\nlog_init conv; log_ok x; log_end\n' >> "$G/bin/conv.sh"
t_has 'a row for a converted file is red' "$(L "$G")" "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv lists bin/conv.sh, which already conforms (user)"

t_section "(c) every row is well formed"
fresh; plain p.sh; printf 'bin/p.sh\tlater\tfixture\n' >> "$R/CONTRACTS/log-exempt.tsv"
t_has 'an unknown kind is red' "$(L)" 'VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv: bin/p.sh has kind "later"'
fresh; plain p.sh; row bin/p.sh ratchet ''
t_has 'an empty why is red' "$(L)" "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv: bin/p.sh has an empty why"
fresh; plain p.sh; row bin/p.sh; row bin/p.sh
t_has 'a duplicate row is red' "$(L)" "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv lists it twice: bin/p.sh"
fresh; printf '// fixture (harbor#771)\n' > "$R/bin/page.mjs"; row bin/page.mjs
t_has 'a row LOG1 cannot read is red' "$(L)" "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv lists bin/page.mjs, which is not a shell program in bin/"
fresh; rm "$R/CONTRACTS/log-exempt.tsv"
t_has 'no table at all is red' "$(L)" "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv is missing"

t_section "(d) a protocol row: harness output, a named consumer, and no ratchet on its stdout"
P="$TMP/log1-proto"; rm -rf "$P"; mkdir -p "$P/bin" "$P/CONTRACTS" "$P/context-rules/p"; cp "$SRC/log-lib.sh" "$P/bin/"
sh1() { printf '#!/usr/bin/env sh\n# fixture (harbor#771)\nset -u\n%s\n' "$2" > "$P/bin/$1"; }
sh1 demo-install.sh 'NEW="$(jq --arg c "/bin/sh $DIR/bin/glyph.sh" ".statusLine = {command: \$c}" "$S")"
echo "run it by hand: /bin/sh $DIR/bin/echoed.sh"'
sh1 glyph.sh 'printf "%s\n" "✓ main"'
sh1 hook.sh 'echo "hook: said the old way" >&2
jq -n --arg m "$MSG" '"'"'{systemMessage: $m}'"'"''
sh1 packed.sh 'printf "note\n"'; printf 'exec sh "bin/packed.sh" --note\n' > "$P/context-rules/p/x.sh"
sh1 plain.sh 'echo plain'; sh1 echoed.sh 'echo x'; sh1 observer.sh ':'; sh1 dropped.sh ':'
sh1 table-install.sh "floor_hooks() { cat <<'ROWS'
# SessionStart;;dropped.sh  is a comment row, never a wiring
SessionStart;;observer.sh
PreToolUse;Bash;floor-hook.sh guard-x.sh;b6
ROWS
}"
printf 'path\tkind\twhy\n' > "$P/CONTRACTS/log-exempt.tsv"
prow() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$P/CONTRACTS/log-exempt.tsv"; }
prow bin/demo-install.sh ratchet fixture; prow bin/plain.sh ratchet fixture; prow bin/echoed.sh ratchet fixture
prow bin/glyph.sh protocol 'Claude Code statusLine: the line it prints'
prow bin/hook.sh protocol 'Claude Code Stop hook: systemMessage JSON'
prow bin/packed.sh protocol 'Claude Code PostToolUse hook, through a rule pack'
prow bin/table-install.sh ratchet fixture; prow bin/dropped.sh ratchet fixture; prow bin/observer.sh protocol 'Claude Code SessionStart hook: session context'
px() { git -C "$P" "$@" >/dev/null 2>&1; }
px init -q .; px config user.email t@t; px config user.name t; px config commit.gpgsign false
px add -A; px commit -qm base; px branch -M main; px checkout -qb feature; px update-ref refs/remotes/origin/main main
green "protocol rows whose files an installer, a rule pack and hook JSON prove are harness output" "$P"
t_eq "the old form stays evidence: bin/glyph.sh is wired only by a composed /bin/sh command" 1 \
  "$(grep -c 'glyph.sh' "$P/bin/demo-install.sh")"
sedi 's#^bin/dropped.sh	ratchet	fixture#bin/dropped.sh	protocol	Claude Code SessionStart hook#' "$P/CONTRACTS/log-exempt.tsv"
t_has 'the table form: a commented-out wiring row is not evidence' "$(L "$P")" \
  "bin/dropped.sh is a protocol row, but nothing shows the harness reads its output"
px checkout -q -- CONTRACTS/log-exempt.tsv; sedi 's/^SessionStart;;observer.sh$//; s/^}$/}\
SessionStart;;observer.sh/' "$P/bin/table-install.sh"
t_has 'the table form: a row outside the table is not evidence' "$(L "$P")" \
  "bin/observer.sh is a protocol row, but nothing shows the harness reads its output"
px checkout -q -- bin/table-install.sh
printf 'printf "%%s\\n" "✓ branch"\n' >> "$P/bin/glyph.sh"
green "a touched protocol file: its stdout is the harness's, so the ratchet does not apply" "$P"
printf 'echo edited\n' >> "$P/bin/plain.sh"
t_eq 'touched protocol and ratchet files: only the ratchet file is red' "  VIOLATION [lint.log-contract] bin/plain.sh changed since the base and is exempt" \
  "$(viol LOG1 "$P" | sed 's/ — convert.*//')"
px checkout -q -- bin/plain.sh; printf 'printf "glyph: cache is stale\\n" >&2\n' >> "$P/bin/glyph.sh"
t_has 'a touched protocol file writes stderr outside the line shape: red' "$(L "$P")" \
  "VIOLATION [lint.log-contract] bin/glyph.sh:6: a stderr diagnostic outside the line shape"
sedi 's/glyph: cache is stale/  WARN: cache is stale/' "$P/bin/glyph.sh"
green "the same diagnostic as a WARN line" "$P"
t_hasnt 'an UNtouched protocol file is not judged on its old stderr' "$(viol LOG1 "$P")x" "bin/hook.sh"
printf 'echo "hook: still the old way" >&2\n' >> "$P/bin/hook.sh"
t_has '...until it is touched' "$(L "$P")" "VIOLATION [lint.log-contract] bin/hook.sh:4: a stderr diagnostic outside the line shape"
px checkout -q -- bin/hook.sh; printf '. "$(dirname "$0")/log-lib.sh"\nlog_init glyph; log_warn x; log_end\n' >> "$P/bin/glyph.sh"
t_has 'a protocol file on log-lib without LOG_FD=2 is red' "$(L "$P")" \
  "VIOLATION [lint.log-contract] bin/glyph.sh is harness protocol output and sources log-lib.sh without LOG_FD=2"
sedi 's/^log_init glyph/LOG_FD=2; log_init glyph/' "$P/bin/glyph.sh"
green "the same file with its log on stderr" "$P"
px checkout -q -- bin/glyph.sh
sedi 's/Claude Code Stop hook: systemMessage JSON/the harness/' "$P/CONTRACTS/log-exempt.tsv"
t_has 'a protocol row that names no consumer is red' "$(L "$P")" \
  "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv: bin/hook.sh is a protocol row that names no consumer"
px checkout -q -- CONTRACTS/log-exempt.tsv; sedi 's#^bin/echoed.sh	ratchet	fixture#bin/echoed.sh	protocol	Claude Code SessionStart hook#' "$P/CONTRACTS/log-exempt.tsv"
t_has 'a protocol row whose only evidence is an echoed instruction is red' "$(L "$P")" \
  "VIOLATION [lint.log-contract] CONTRACTS/log-exempt.tsv: bin/echoed.sh is a protocol row, but nothing shows the harness reads its output"
px checkout -q -- CONTRACTS/log-exempt.tsv; rm "$P/context-rules/p/x.sh"
t_has 'the rule pack is the evidence for a pack-run file' "$(L "$P")" "bin/packed.sh is a protocol row, but nothing shows the harness reads its output"
px checkout -q -- context-rules; sh1 new-hook.sh 'printf "{\"hookSpecificOutput\":{}}\n"'; prow bin/new-hook.sh protocol 'Claude Code PreToolUse hook: permissionDecision JSON'
green "a new harness hook gets a protocol row, evidence in hand" "$P"

t_section "the real tree"
t_has 'LOG1 passes the checkout' "$(lint1 LOG1 "$T_ROOT")" '1 rules, 0 violations'

t_done
