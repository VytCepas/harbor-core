#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: the command surfaces — CLI1 keeps a verb table and
# its contract equal, and a printed violation must also FAIL the gate (PR #62); CM1/CM2/CM3 judge
# the slash commands (harbor#214, #215) and name a drift's direction (harbor#139, harbor#667).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

CLR="$TMP/cliroot"; mkdir -p "$CLR/bin" "$CLR/contracts"
printf '#!/usr/bin/env sh\n# harbor#6 — lint-test fixture.\nset -u\n' > "$CLR/bin/real.sh"
# The two runs differ in exactly one thing, the verb's TARGET; real.sh exists and is S1-clean in both.
harbor_fixture() { # <script the verb points at>
  printf '#!/usr/bin/env sh\nset -u\nVERBS="\nstatus\t%s\tyes\tthe generated counts\n"\n' "$1" > "$CLR/bin/harbor"
  printf '| `harbor status` | `%s` | yes | the generated counts |\n\ninternal: `real.sh`\n' "$1" > "$CLR/contracts/cli.md"
}

t_section "CLI1: a verb pointing at a missing script is reported, and fails the gate"
harbor_fixture real.sh
BASE_N="$(vcount "$(lint1 CLI1 "$CLR")")"
harbor_fixture ghost.sh
GHOST_OUT="$(lint1 CLI1 "$CLR")"
t_has "a verb pointing at a missing script is reported" "$GHOST_OUT" 'dispatches to bin/ghost.sh, which does not exist'
t_eq "…and the report increments the violation count (no subshell loss)" "$((${BASE_N:-0} + 1))" "$(vcount "$GHOST_OUT")"

t_section "CLI1: a verb may carry fixed words after its script (harbor#800), and both halves still bind"
# `install  deploy.sh --only floor`: the pair keeps the words, and the script half must still exist.
harbor_fixture 'real.sh --only floor'
FW_OUT="$(lint1 CLI1 "$CLR")"
t_eq "a verb with fixed words, matched row for row in the contract, is clean" "${BASE_N:-0}" "$(vcount "$FW_OUT")"
t_hasnt "...and its script is found by its first word" "$FW_OUT" 'which does not exist'
harbor_fixture 'ghost.sh --only floor'
t_has "a verb with fixed words whose script is missing is still reported" "$(lint1 CLI1 "$CLR")" 'dispatches to bin/ghost.sh, which does not exist'
printf '#!/usr/bin/env sh\nset -u\nVERBS="\nstatus\t%s\tyes\tthe generated counts\n"\n' 'real.sh --only floor' > "$CLR/bin/harbor"
printf '| `harbor status` | `%s` | yes | the generated counts |\n\ninternal: `real.sh`\n' 'real.sh --only skills' > "$CLR/contracts/cli.md"
t_has "a contract whose fixed words differ from the dispatcher's is a disagreement" "$(lint1 CLI1 "$CLR")" "bin/harbor's verb table and contracts/cli.md disagree"
harbor_fixture real.sh

# CM1/CM2 fixtures: the absolute-good one points INSIDE the fixture, never at a checkout, so no
# assertion depends on where this host keeps the repo.
CMR="$TMP/cmroot"; mkdir -p "$CMR/commands" "$CMR/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$CMR/bin/real.sh"
cmd() { printf -- '---\ndescription: %s\nallowed-tools: %s\n---\n!`%s 2>&1`\n' "$2" "$3" "$4" > "$CMR/commands/$1.md"; }
cmd bad-relative 'a repo-relative path' 'Bash(sh bin/whatever.sh:*)' 'sh bin/whatever.sh'
cmd good-absolute 'an absolute path that resolves' "Bash(sh $CMR/bin/real.sh:*)" "sh $CMR/bin/real.sh"
cmd missing-absolute 'absolute, inside the linted tree, and not there' "Bash(sh $CMR/bin/ghost.sh:*)" "sh $CMR/bin/ghost.sh"
cmd variable-path 'a variable is the operator'"'"'s to resolve' 'Bash(sh $HARBOR/bin/thing.sh:*)' 'sh $HARBOR/bin/thing.sh'
cmd quoted-absolute 'a quoted absolute path is still absolute' "Bash(sh \"$CMR/bin/real.sh\":*)" "sh \"$CMR/bin/real.sh\""
cmd tilde-path 'tilde is absolute by shape' 'Bash(sh ~/nowhere-at-all/bin/x.sh:*)' 'sh ~/nowhere-at-all/bin/x.sh'
cmd cd-wrapper 'a cd before the sh makes the relative path correct' 'Bash' "(cd $CMR && sh bin/real.sh)"
cmd flagged-relative 'a flag before the path does not make it resolve' 'Bash(sh -e bin/nope.sh:*)' 'sh -e bin/nope.sh'
cmd wider-grant 'a wider prefix grant permits the narrower invocation' 'Bash(sh:*)' "sh $CMR/bin/real.sh --flag"
cmd bare-bash 'bare Bash permits everything' 'Bash' "sh $CMR/bin/real.sh"
cmd bare-plus 'bare Bash beside a narrow grant still permits everything' 'Bash, Bash(ls:*)' "sh $CMR/bin/real.sh"
cmd prompts-every-time 'body and frontmatter disagree' "Bash(sh $CMR/bin/other.sh:*)" "sh $CMR/bin/real.sh"
printf -- '---\ndescription: a block sequence with a real mismatch\nallowed-tools:\n  - Bash(sh %s/bin/other.sh:*)\n  - Bash(ls:*)\n---\n!`sh %s/bin/real.sh 2>&1`\n' \
  "$CMR" "$CMR" > "$CMR/commands/yaml-list-mismatch.md"
printf -- '---\ndescription: a block sequence that permits the body\nallowed-tools:\n  - Bash(sh %s/bin/real.sh:*)\n  - Bash(ls:*)\n---\n!`sh %s/bin/real.sh 2>&1`\n' \
  "$CMR" "$CMR" > "$CMR/commands/yaml-list-ok.md"
OUT_CM1="$(viol CM1 "$CMR")"; OUT_CM2="$(viol CM2 "$CMR")"

t_section "CM1: a slash command's script resolves from the session's cwd"
t_has "a repo-relative path in a global command is reported" "$OUT_CM1" 'bad-relative.md'
t_hasnt "an absolute path that resolves stays green" "$OUT_CM1" 'good-absolute.md'
t_has "absolute but absent is a call into nothing" "$OUT_CM1" 'missing-absolute.md'
t_hasnt "a \$VAR path is the operator's to resolve, never guessed at" "$OUT_CM1" 'variable-path.md'
t_hasnt "a QUOTED absolute path is absolute, not repo-relative" "$OUT_CM1" 'quoted-absolute.md'
t_hasnt "a TILDE path is judged by shape, not by this machine's HOME" "$OUT_CM1" 'tilde-path.md'
t_hasnt "a cd before the sh makes a relative path correct" "$OUT_CM1" 'cd-wrapper.md'
t_has "an interpreter FLAG does not hide a relative path" "$OUT_CM1" 'flagged-relative.md'

t_section "CM2: allowed-tools permits the invocation in the body"
t_has "a grant that does not name the invocation is reported" "$OUT_CM2" 'prompts-every-time.md'
t_hasnt "a grant WIDER than the invocation permits it (prefix, not substring)" "$OUT_CM2" 'wider-grant.md'
t_hasnt "a bare Bash grant permits every Bash call" "$OUT_CM2" 'bare-bash.md'
t_hasnt "…even beside a narrower grant" "$OUT_CM2" 'bare-plus.md'
t_has "a YAML block sequence is read, not silently skipped" "$OUT_CM2" 'yaml-list-mismatch.md'
t_hasnt "a correct block sequence stays green" "$OUT_CM2" 'yaml-list-ok.md'
t_hasnt "a matching pair stays green" "$OUT_CM2" 'good-absolute.md'

t_section "CM3: installed-command drift names its direction (harbor#139)"
CM3L="$TMP/cm3live"; mkdir -p "$CM3L/commands"
printf 'the repo copy\n' > "$CMR/commands/drifted.md"
printf 'the live copy\n' > "$CM3L/commands/drifted.md"
cp "$CMR/commands/good-absolute.md" "$CM3L/commands/good-absolute.md"
cm3() { HARBOR_DEPLOY_LIVE_DIR="$CM3L" advs CM3 "$CMR"; }
OUT_CM3="$(cm3)"
t_has "a drifted installed command is reported" "$OUT_CM3" 'drifted.md'
t_hasnt "an identical pair stays green" "$OUT_CM3" 'good-absolute.md'
# Explicit stamps six months apart: a bare touch lands in the same second on a fast run (#139).
touch -t 202001010000 "$CMR/commands/drifted.md"; touch -t 202006010000 "$CM3L/commands/drifted.md"
t_eq "LIVE-NEWER says capture, never reinstall" yes "$(hasre "$(cm3)" 'LIVE IS NEWER.*do NOT reinstall')"
touch -t 202001010000 "$CM3L/commands/drifted.md"; touch -t 202006010000 "$CMR/commands/drifted.md"
t_has "REPO-NEWER says reinstall" "$(cm3)" 'repo is newer'
touch -t 202003150000 "$CMR/commands/drifted.md" "$CM3L/commands/drifted.md"
t_has "EQUAL mtimes say UNDECIDABLE, never a guess" "$(cm3)" 'UNDECIDABLE'

# harbor#957 item 3: no id has two meanings. A fixture linter is planted beside the real registry, the
# way C9 is tested, so each defect is one edit away from the clean twin.
t_section "lint.id-one-meaning: one id per rule, one rule per id (harbor#957)"
IMR="$TMP/idroot"; mkdir -p "$IMR/bin" "$IMR/standards/naming"
cp "$ROOT/standards/naming/terms.tsv" "$ROOT/standards/naming/controls.tsv" "$IMR/standards/naming/"
IMMSG='VIOLATION [lint.id-one-meaning]'
imfx() { # <rule lines…>: one `rule_<fn>() {` / `rule "<id> …"` pair per argument, `fn id`
  : > "$IMR/bin/lint-conventions.sh"
  for _p in "$@"; do printf 'rule_%s() {\nrule "%s a fixture rule"\n}\n' "${_p%% *}" "${_p#* }" >> "$IMR/bin/lint-conventions.sh"; done
}
im() { lint1 lint.id-one-meaning "$IMR" | grep -F "$IMMSG"; }
imfx 'K1 policy.constitution-paths' 'F1 admission.kill-switch-first' 'lint_new_rule lint.new-rule'
t_eq "distinct ids, distinct letters, registered families: silent" "" "$(im)"
t_eq "…and the real linter is silent too" "" "$(lint1 lint.id-one-meaning "$ROOT" | grep -F "$IMMSG")"
imfx 'K1 policy.constitution-paths' 'F1 policy.constitution-paths'
t_has "two rules under one id is a violation" "$(im)" 'the id policy.constitution-paths names two rules: rule_K1 and rule_F1'
imfx 'K1 policy.constitution-paths' 'K1 admission.kill-switch-first'
t_has "one deprecated letter for two rules is a violation" "$(im)" 'the deprecated id K1 names two rules'
imfx 'K1 K1'
t_has "a letter-shaped id is no <family>.<slug>" "$(im)" 'rule_K1 has the id K1: an id is <family>.<slug>'
imfx 'K1 widget.constitution-paths'
t_has "an id whose first word is not a family is a violation" "$(im)" 'widget is not a family or lint subject'
imfx 'K1 name.case'
t_has "an id bin/lint-name.sh already owns is a violation" "$(im)" 'name.case is also a bin/lint-name.sh rule'
imfx 'K1 policy.constitution-paths'; printf 'rule_F1() {\n: no rule line\n}\n' >> "$IMR/bin/lint-conventions.sh"
t_has "a rule function with no id never runs, and is a violation" "$(im)" '2 rule functions and 1 ids'
rm -f "$IMR/standards/naming/terms.tsv"
t_has "no registry to judge against is a violation, never a clean pass" "$(im)" 'no id was judged'

t_section "duplicate meanings outside the lint (harbor#957)"
t_eq "docs/explanation/admission-baseline.md cites the kill-switch rule by its id, not K1 (which is the constitution-path rule)" "" \
  "$(grep -n 'K1 asserts' "$ROOT/docs/explanation/admission-baseline.md")"
t_has "…and names admission.kill-switch-first" "$(cat "$ROOT/docs/explanation/admission-baseline.md")" 'lint admission.kill-switch-first (was F1)'
t_hasnt "contracts/roots.tsv names no lint rule that does not exist" "$(cat "$ROOT/contracts/roots.tsv")" 'X-prodguard'

t_done
