#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: red proofs kept (harbor#588, #625) — one planted defect per
# rule, beside a clean twin that must stay silent, each rule asked alone about a root holding only
# what it reads. D1 and F11 fixtures are built from two innocent lines, never one (harbor#667).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
RP="$TMP/redproof"
_rp()       { lint1 "$1" "${2:-$RP}" || true; }
_rp_fresh() { rm -rf "$RP"; mkdir -p "$RP/bin" "$RP/contracts" "$RP/skills"; }
_rp_green() { # <ID> <what the clean fixture holds> [root]: silent, and the rule really ran
  _rpo="$(_rp "$1" "${3:-}")"
  t_eq "$1 is silent on $2" "" "$(printf '%s\n' "$_rpo" | grep -F -e "VIOLATION [$(lid "$1")]" -e "ADVISORY [$(lid "$1")]")"
  t_has "$1 ran on $2" "$_rpo" '1 rules, 0 violations'
}
_rp_red() { t_has "$1 is red on $3" "$(_rp "$1" "${4:-}")" "$2"; }  # <ID> <its own message> <the plant> [root]
_rp_sh() { printf '#!/usr/bin/env sh\n# fixture (harbor#588)\n' > "$1"; }

t_section "C1: a contract with no README row"
_rp_fresh
printf '# contracts\n\n- `listed.md`\n' > "$RP/contracts/README.md"; : > "$RP/contracts/listed.md"
_rp_green C1 "every contract indexed"
: > "$RP/contracts/zz-probe.md"
_rp_red C1 "contract not indexed in README: zz-probe.md" "an unindexed contracts/zz-probe.md"

t_section "C3: a suite outside bin/ must be in the manifest too (harbor#695)"
_rp_fresh; _rp_sh "$RP/bin/a-test.sh"; printf 'a-test.sh\n' > "$RP/contracts/suites.txt"
_rp_green C3 "a manifest listing its one bin/ suite"
mkdir -p "$RP/skills/x/bin" "$RP/evals/e"; _rp_sh "$RP/skills/x/bin/y-test.sh"
_rp_red C3 "test suite missing from contracts/suites.txt: skills/x/bin/y-test.sh" "a skill-local suite in no manifest"
printf 'skills/x/bin/y-test.sh\n' >> "$RP/contracts/suites.txt"; _rp_sh "$RP/evals/e/z-test.sh"
_rp_green C3 "the skill suite listed by path, and an evals fixture"
printf 'skills/x/bin/gone-test.sh\n' >> "$RP/contracts/suites.txt"
_rp_red C3 "names a suite that does not exist: skills/x/bin/gone-test.sh" "a manifest path that resolves to nothing"
printf 'a-test.sh\nskills/x/bin/y-test.sh\n' > "$RP/contracts/suites.txt"; mkdir -p "$RP/.github/workflows"
printf 'jobs:\n  t:\n    steps:\n      - run: sh bin/a-test.sh\n' > "$RP/.github/workflows/governance.yml"
_rp_red C3 "not run by CI, and CI does not read the manifest: skills/x/bin/y-test.sh" "a path suite a manifest-blind workflow never names"
printf '      - run: sh skills/x/bin/y-test.sh\n' >> "$RP/.github/workflows/governance.yml"; _rp_green C3 "the same workflow once it names the path suite"
mkdir -p "$RP/hooks/x"; _rp_sh "$RP/hooks/x/x.test.sh"; _rp_red C3 "test suite missing from contracts/suites.txt: hooks/x/x.test.sh" "a dot-named engine suite (D-88) in no manifest"
printf 'hooks/x/x.test.sh\n' >> "$RP/contracts/suites.txt"; printf '      - run: sh hooks/x/x.test.sh\n' >> "$RP/.github/workflows/governance.yml"; _rp_green C3 "...once it is listed and run"

t_section "S1 / S2 / S3 / S4: a bin/ script's shebang, name, ticket and --help"
_rp_fresh; _rp_sh "$RP/bin/good-name.sh"
printf 'set -u\ncase "${1:-}" in -h|--help) echo usage ;; esac\n' >> "$RP/bin/good-name.sh"
_rp_green S1 "a script with the sh shebang and strict mode"
_rp_green S2 "a kebab-case script"
_rp_green S3 "a script whose header names its ticket"
_rp_green S4 "a script with a --help arm"
printf '#!/bin/bash\n# fixture (harbor#588)\nset -u\n' > "$RP/bin/bash-shebang.sh"
_rp_red S1 "wrong shebang: bin/bash-shebang.sh" "a #!/bin/bash script in bin/"
rm "$RP/bin/bash-shebang.sh"; _rp_sh "$RP/bin/lax.sh"
_rp_red S1 "no strict mode: bin/lax.sh" "a script with no set -u"
rm "$RP/bin/lax.sh"
cp "$RP/bin/good-name.sh" "$RP/bin/Zz_Probe.sh"
_rp_red S2 "not kebab-case: Zz_Probe.sh" "bin/Zz_Probe.sh"
rm "$RP/bin/Zz_Probe.sh"
printf '#!/usr/bin/env sh\n# a script with no ticket\n\n\ncase "${1:-}" in --help) : ;; esac\n' > "$RP/bin/no-ticket.sh"
_rp_red S3 "no ticket reference in header: bin/no-ticket.sh" "a header with no ticket in its first 4 lines"
rm "$RP/bin/no-ticket.sh"
_rp_sh "$RP/bin/no-help.sh"; printf 'echo hi\n' >> "$RP/bin/no-help.sh"
_rp_red S4 "answers no --help: bin/no-help.sh" "a script with no --help arm"
_rp_sh "$RP/bin/no-help.sh"
printf '# bin/cu spells its arms ""|-h|--help|help\necho hi   # like -h|--help) elsewhere\n' >> "$RP/bin/no-help.sh"
_rp_red S4 "answers no --help: bin/no-help.sh" "a script whose only --help arm is in a comment (harbor#579)"

t_section "S6: a script that loses its executable bit (harbor#574)"
S6R="$TMP/rp-s6"; mkdir -p "$S6R/bin"
( cd "$S6R" && git init -q . && git config user.email t@t && git config user.name t && git config commit.gpgsign false ) >/dev/null 2>&1
printf '#!/usr/bin/env sh\necho run\n' > "$S6R/bin/tool.sh";   chmod 755 "$S6R/bin/tool.sh"
printf 'lib_fn() { :; }\n'               > "$S6R/bin/lib.sh";    chmod 755 "$S6R/bin/lib.sh"
printf '#!/usr/bin/env sh\necho late\n'  > "$S6R/bin/late.sh";   chmod 644 "$S6R/bin/late.sh"
printf '#!/usr/bin/env sh\necho moved\n' > "$S6R/bin/ren.sh";    chmod 755 "$S6R/bin/ren.sh"
( cd "$S6R" && git add -A && git commit -qm base && git branch -M main && git checkout -qb feature \
    && git checkout -q main && chmod 755 bin/late.sh && git commit -qam 'late gains its bit' \
    && git update-ref refs/remotes/origin/main HEAD && git checkout -q feature ) >/dev/null 2>&1
t_eq "the fixture is on the stale branch (the merge-base control)" 100644 "$(git -C "$S6R" ls-files -s bin/late.sh | cut -c1-6)"
_rp_green S6 "a stale branch behind a main that GAINED a bit" "$S6R"
chmod 644 "$S6R/bin/lib.sh"
_rp_green S6 "a sourced file with no shebang that dropped its bit" "$S6R"
chmod 644 "$S6R/bin/tool.sh"
_rp_red S6 "(100755 -> 100644): bin/tool.sh" "an uncommitted 755 -> 644 on a script" "$S6R"
( cd "$S6R" && git commit -qam 'the #572 shape: a mode lost through mv' ) >/dev/null 2>&1
_rp_red S6 "(100755 -> 100644): bin/tool.sh" "a committed 755 -> 644 on a script" "$S6R"
( cd "$S6R" && git mv bin/ren.sh bin/renamed.sh && chmod 644 bin/renamed.sh && git commit -qam 'moved, and lost its bit' ) >/dev/null 2>&1
_rp_red S6 "(100755 -> 100644): bin/renamed.sh" "a git mv that also dropped the bit" "$S6R"

t_section "S5: the justfile names a path that does not exist"
_rp_fresh; _rp_sh "$RP/bin/real.sh"; printf 'real:\n\tsh bin/real.sh\n' > "$RP/justfile"
_rp_green S5 "a justfile naming a script that exists"
printf 'gone:\n\tsh bin/zz-does-not-exist.sh\n' >> "$RP/justfile"
_rp_red S5 "names a path that does not exist: bin/zz-does-not-exist.sh" "a recipe naming bin/zz-does-not-exist.sh"

t_section "C8: a tool named only by the justfile or the dispatcher is called (harbor#474)"
_rp_fresh; _rp_sh "$RP/bin/recipe-tool.sh"; _rp_sh "$RP/bin/row-tool.sh"; : > "$RP/contracts/idle-tools.txt"
mkdir -p "$RP/hooks"; _rp_sh "$RP/bin/wired-tool.sh"; printf '#!/usr/bin/env sh\nsh bin/wired-tool.sh\n' > "$RP/hooks/pre-commit"
printf 'recipe:\n\tsh bin/recipe-tool.sh --live\n' > "$RP/justfile"
printf '#!/usr/bin/env sh\n# fixture (harbor#474)\nVERBS="\nrow\trow-tool.sh\tno\tfixture row\n"\n' > "$RP/bin/harbor"
_rp_green C8 "a tool named only by a justfile recipe, and one named only by a dispatcher row"
_rp_sh "$RP/bin/lonely-tool.sh"
_rp_red C8 "nothing calls bin/lonely-tool.sh" "a tool called from nowhere, the control that must stay red"

t_section "D1: a bare live config dir"
_rp_fresh; _rp_h='$HOME'; _rp_sh "$RP/bin/cfg.sh"
printf 'D="${CLAUDE_CONFIG_DIR:-%s/.claude}"\n' "$_rp_h" >> "$RP/bin/cfg.sh"
_rp_green D1 "the config dir resolved through CLAUDE_CONFIG_DIR"
printf 'cat "%s/.claude/settings.json"\n' "$_rp_h" >> "$RP/bin/cfg.sh"
_rp_red D1 "hardcoded live config dir: bin/cfg.sh" "a bare \$HOME config path"

t_section "D3 / F1 / F2: a guard's exit code, kill switch and caret"
_rp_fresh
_KS='[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0'
guard() { printf '#!/usr/bin/env sh\n# guard (harbor#588)\n%s\n' "$1" > "$RP/bin/guard-zz.sh"; }
# F1 derives its set from bin/decider-set.sh (harbor#954): the fixture's decider set is its one guard, no drift
printf '#!/usr/bin/env sh\n# decider-set stub (harbor#954)\ncase "${1:-}" in --switch) echo guard-zz.sh ;; --check|--exempt|--records) : ;; esac\n' > "$RP/bin/decider-set.sh"
guard "$_KS
echo judged
exit 0"
_rp_green D3 "a guard ending in exit 0"
_rp_green F1 "a guard whose first live line is the kill switch"
_rp_green F2 "a guard with no mid-pattern caret"
guard "$_KS
[ -n \"\${X:-}\" ] && exit 2
exit 0"
_rp_red D3 "open-codes 'exit 2' instead of floor_block(): bin/guard-zz.sh" "an exit 2 in a guard"
guard "$_KS
echo judged"
_rp_red D3 "does not end with 'exit 0': bin/guard-zz.sh" "a guard whose last line is not exit 0"
guard "set -u
$_KS
exit 0"
_rp_red F1 "kill-switch is not the first live line: bin/guard-zz.sh" "a guard that runs a line before its kill switch"
guard "$_KS
grep -qE '.*(^|foo)' x
exit 0"
_rp_red F2 "mid-pattern caret: bin/guard-zz.sh" "a .*(^| pattern in a guard"
guard "$_KS
grep -qE '[a-z]+(^|foo)' x
exit 0"
_rp_red F2 "mid-pattern caret: bin/guard-zz.sh" "a [a-z]+(^| pattern (harbor#588)"
guard "$_KS
grep -qE 'a((^|b))' x
exit 0"
_rp_red F2 "mid-pattern caret: bin/guard-zz.sh" "a((^|b)), the caret behind a nested paren"
guard "$_KS
# prose: \`(^| is not an option
awk '\$3 ~ /(^|\\/)bin\\// { print }' x
exit 0"
_rp_green F2 "an awk /(^|…/ literal and a comment quoting (^|"

t_section "F3: a bare grep in a guard-lib consumer"
_rp_fresh; _rp_sh "$RP/bin/consumer.sh"
printf '. "$DIR/library-admission.sh"\n"$FLOOR_GREP" -q x "$f"\n' >> "$RP/bin/consumer.sh"
_rp_green F3 "a consumer matching through \$FLOOR_GREP"
printf 'grep -q x "$f"\n' >> "$RP/bin/consumer.sh"
_rp_red F3 "bare grep in a guard-lib consumer (use \$FLOOR_GREP): bin/consumer.sh" "a bare grep after sourcing guard-lib"

t_section "F5: a floor_block with no rule id"
_rp_fresh; _rp_sh "$RP/bin/admission-egress.sh"
printf 'floor_block egress "a probe shape" zz-probe.argv\n' >> "$RP/bin/admission-egress.sh"
_rp_green F5 "every call site carries a rule id"
printf 'floor_block egress "a probe shape with no id"\n' >> "$RP/bin/admission-egress.sh"
_rp_red F5 "1 of 2 floor_block call site(s) carry no rule id" "a floor_block call with no <rule>.<shape>"
_rp_fresh; _rp_sh "$RP/bin/guard-zz.sh"
printf '# payload text that never enters floor_block cannot leak\n' >> "$RP/bin/guard-zz.sh"
_rp_green F5 "a guard whose only floor_block is in a comment"
printf 'floor_block zz "a probe with no id"\n' >> "$RP/bin/guard-zz.sh"
_rp_red F5 "1 of 1 floor_block call site(s) carry no rule id" "a call with no id in a guard outside the old three"

t_section "F16: a floor guard printing the kill-switch as its remedy (harbor#482)"
_rp_fresh
printf "#!/usr/bin/env sh\nGUARDS='guard-zz.sh admission-hook.sh pin-zz.sh'\n" > "$RP/bin/floor-install.sh"
_rp_sh "$RP/bin/guard-zz.sh"; printf "printf 'run it once as a ! command\\\\n' >&2\n# the old hatch was HARBOR_ADMISSION_DISABLE=1 claude\n" >> "$RP/bin/guard-zz.sh"
_rp_sh "$RP/bin/admission-hook.sh"; printf "printf 'Fix the guard, or open an unguarded session: HELM_DISABLE_FLOOR=1 claude\\\\n' >&2\n" >> "$RP/bin/admission-hook.sh"
_rp_sh "$RP/bin/pin-zz.sh"
_rp_green F16 "a narrow remedy, the hatch in a comment, and the wrapper where it is the true one"
printf "printf '(operator escape hatch: HELM_DISABLE_FLOOR=1 claude)\\\\n' >&2\n" >> "$RP/bin/pin-zz.sh"
_rp_red F16 "bin/pin-zz.sh prints the kill-switch as a remedy on 1 code line(s)" "the hatch in a file only the GUARDS line names"
printf '#!/usr/bin/env sh\n' > "$RP/bin/floor-install.sh"
_rp_red F16 "has no GUARDS=" "an installer whose floor file set cannot be derived"

t_section "F14: a .helm-* name with no row, a stale row, and a layer that disagrees (harbor#779)"
_F14_FILES='FILES="(settings\\.json|\\.helm-zz-pin\\.sha256|\\.helm-zz-trust(/[^;]*)?)"'
_F14_SELF='    "$root/.helm-zz-trust"|"$root"/.helm-zz-trust/*) return 0 ;;'
_F14_DENY='  "Edit(~/.claude/.helm-zz-trust/**)",'
_f14_fx() { # [extra-row] [FILES-line] [selfedit-arm] [deny-entry] — clean unless an argument says otherwise
  _rp_fresh
  printf '%s\n' '## The table' '' '| name | where | class | reader | writer | why |' '|---|---|---|---|---|---|' \
    '| `.helm-zz-trust` | `<cfg>/.helm-zz-trust/` | integrity | r | w | y |' \
    '| `.helm-zz-pin.sha256` | `<cfg>/.helm-zz-pin.sha256` | integrity | r | w | y |' \
    '| `.helm-zz-cache` | `<cfg>/.helm-zz-cache` | cache | r | w | y |' \
    '| `.helm-zz-tmp` | `$TMPDIR/.helm-zz-tmp.<pid>` | scratch | r | w | y |' "${1:-}" '' '## After' \
    > "$RP/contracts/control-plane-state.md"
  _rp_sh "$RP/bin/reader.sh"; printf 'a="$CFG/.helm-zz-cache"; t="$TMPDIR/.helm-zz-tmp.$$"\n' >> "$RP/bin/reader.sh"
  _rp_sh "$RP/bin/admission-bash.sh"; printf '%s\n' "${2-$_F14_FILES}" >> "$RP/bin/admission-bash.sh"
  _rp_sh "$RP/bin/admission-self-edit.sh"
  printf '%s\n' 'is_protected() {' '  case "$1" in' '    # the trust dir is .helm-zz-trust' "${3-$_F14_SELF}" \
    '    "$root/.helm-zz-pin.sha256") return 0 ;;   # the pin' '  esac' '}' >> "$RP/bin/admission-self-edit.sh"
  _rp_sh "$RP/bin/floor-deny.sh"
  printf '%s\n' "ADD='[" "${4-$_F14_DENY}" '  "Edit(~/.claude/.helm-zz-pin.sha256)"' "]'" >> "$RP/bin/floor-deny.sh"
}
_f14_fx
_rp_green F14 "a row per name, and three layers naming exactly the integrity rows (one only as a regex)"
_rp_sh "$RP/bin/new.sh"; printf 'x="$CFG/.helm-zz-new"\n' >> "$RP/bin/new.sh"
_rp_red F14 "bin/new.sh names .helm-zz-new, which has no row in contracts/control-plane-state.md" "a new name in bin/ with no row"
_f14_fx; _rp_sh "$RP/bin/zz-entry"; printf 'x="$CFG/.helm-zz-bare"\n' >> "$RP/bin/zz-entry"
_rp_red F14 "bin/zz-entry names .helm-zz-bare, which has no row" "a new name in an extensionless bin/ entrypoint"
_f14_fx; printf '# a comment naming .helm-zz-note\n' >> "$RP/bin/reader.sh"
_rp_red F14 "bin/reader.sh names .helm-zz-note, which has no row" "a new name that appears only in a comment"
_f14_fx '| `.helm-zz-gone` | `<cfg>/.helm-zz-gone` | cache | r | w | y |'
_rp_red F14 "has a row for .helm-zz-gone and no file in bin/ names it" "a row that no file in bin/ names"
_f14_fx '| `.helm-zz-cache` | `<cfg>/.helm-zz-cache` | cache | r | w | y |'
_rp_red F14 "has two rows for .helm-zz-cache" "the same name in two rows"
_f14_fx '| `.helm-zz-odd` | `<cfg>/.helm-zz-odd` | kinda | r | w | y |'; printf 'o=.helm-zz-odd\n' >> "$RP/bin/reader.sh"
_rp_red F14 "classes .helm-zz-odd as 'kinda'" "a class that is none of the three"
_f14_fx '' 'FILES="(settings\\.json|\\.helm-zz-pin\\.sha256)"'
_rp_red F14 ".helm-zz-trust is an integrity row and guard-bash does not protect it" "an integrity row cut from FILES"
_f14_fx '' "$_F14_FILES" '    "$root/other") return 0 ;;'
_rp_red F14 ".helm-zz-trust is an integrity row and guard-selfedit does not protect it" "an integrity row cut from is_protected, its comment kept"
_f14_fx '' "$_F14_FILES" "$_F14_SELF" '  "Edit(~/.claude/other)",'
_rp_red F14 ".helm-zz-trust is an integrity row and floor-deny does not protect it" "an integrity row cut from the deny list"
_f14_fx '' 'FILES="(settings\\.json|\\.helm-zz-cache|\\.helm-zz-pin\\.sha256|\\.helm-zz-trust(/[^;]*)?)"'
_rp_red F14 "guard-bash protects .helm-zz-cache, which contracts/control-plane-state.md classes as 'cache'" "a cache row protected by a layer"
_f14_fx; rm "$RP/contracts/control-plane-state.md"
_rp_red F14 "contracts/control-plane-state.md is missing" "no table at all"

t_section "F15: a script a hook runs resolves its own directory through \$(dirname) (harbor#813)"
_F15_DIRTY='DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"'
_F15_CLEAN='case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac'
_f15_sh() { _rp_sh "$RP/$1"; _f15_f="$RP/$1"; shift; printf '%s\n' "$@" >> "$_f15_f"; }  # <rel> <line>…
_f15_fx() { # a clean box: a table row, a composed hook, one named through a variable, a box pack, their libraries
  _rp_fresh; mkdir -p "$RP/context-rules/user"
  printf '%s\n' '#!/usr/bin/env sh' '# fixture (harbor#813)' 'PACKS="$SRC/../context-rules/user"' \
    "floor_hooks() { cat <<'ROWS'" 'PreToolUse;Bash;zz-wrap.sh zz-guard.sh' '# PreToolUse;Bash;zz-commented.sh' 'ROWS' '}' \
    'ZZ_HOOK="/bin/sh $DIR/bin/zz-stop.sh"' 'Z_DST="$DIR/bin/zz-shim.sh"' 'CMD="/bin/sh $Z_DST $DIR/hooks/x.py"' \
    'log_note "verify: /bin/sh $DIR/bin/zz-hint.sh < p"' > "$RP/bin/zz-install.sh"
  for _f15n in zz-wrap zz-stop zz-lib zz-vlib zz-hint zz-commented zz-cli zz-tool; do _f15_sh "bin/$_f15n.sh" "$_F15_CLEAN"; done
  _f15_sh bin/zz-guard.sh "$_F15_CLEAN" '. "$DIR/zz-lib.sh"' 'L="$DIR/zz-vlib.sh"' '[ -f "$L" ] && . "$L"' \
    'echo "to reinstall: sh $DIR/zz-cli.sh --apply"'
  _f15_sh bin/zz-shim.sh '_L="${0%/*}/zz-lib.sh"' '( . "$_L" )'
  printf '%s\n' '---' 'event: SessionStart' 'run: zz-pack.sh' '---' 'body' > "$RP/context-rules/user/zz.md"
  _f15_sh context-rules/user/zz-pack.sh "$_F15_CLEAN"
}
_f15_dirty() { # <rel> [line] — the clean resolution becomes the dirty one, or [line]
  awk -v r="${2:-$_F15_DIRTY}" 'index($0, "case \"$0\" in */*) DIR=") == 1 { print r; next } { print }' "$RP/$1" > "$RP/$1.t" \
    && mv "$RP/$1.t" "$RP/$1"
}
_f15_fx
_rp_green F15 "a table row, a composed hook, a variable-named shim, a box pack and the libraries they source, all on \${0%/*}"
t_has "F15 derives the set from the wiring and what it sources, not from a list" "$(_rp F15)" \
  'zz-guard.sh zz-lib.sh zz-pack.sh zz-shim.sh zz-stop.sh zz-vlib.sh zz-wrap.sh '
for _f15n in zz-hint zz-commented zz-cli zz-tool; do _f15_dirty "bin/$_f15n.sh"; done
t_has "F15 the controls carry the dirty line" "$(cat "$RP/bin/zz-cli.sh")" 'dirname -- "$0"'
_rp_green F15 "the dirty line in a hint's script, a commented row's, one only named in a string, and an unwired tool"
_f15_fx; _f15_dirty bin/zz-guard.sh
_rp_red F15 "bin/zz-guard.sh:3 resolves its own directory through \$(dirname) and a hook runs it (bin/zz-install.sh)" "a table-wired guard"
_f15_fx; _f15_dirty bin/zz-lib.sh
_rp_red F15 "bin/zz-lib.sh:3 resolves its own directory through \$(dirname) and a hook runs it (run by bin/" "a library a hook sources"
_f15_fx; _f15_dirty bin/zz-vlib.sh
_rp_red F15 "bin/zz-vlib.sh:3 resolves" "a library sourced through a variable"
_f15_fx; _f15_dirty bin/zz-stop.sh
_rp_red F15 "bin/zz-stop.sh:3 resolves" "a composed /bin/sh \$DIR/bin/X hook"
_f15_fx; printf '%s\n' "$_F15_DIRTY" >> "$RP/bin/zz-shim.sh"
_rp_red F15 "bin/zz-shim.sh:5 resolves" "a hook named through V=\"\$DIR/bin/X\""
_f15_fx; _f15_dirty context-rules/user/zz-pack.sh
_rp_red F15 "context-rules/user/zz-pack.sh:3 resolves" "a box pack's run: script"
_f15_fx; _f15_dirty bin/zz-lib.sh 'FLOOR_AWK="${DIR:-$(dirname -- "${0:-.}")}/floor-normalize.awk"'
_rp_red F15 "bin/zz-lib.sh:3 resolves" "guard-lib's \${0:-.} fallback spelling"
_f15_fx; _f15_dirty bin/zz-lib.sh 'D=`dirname $0`'
_rp_red F15 "bin/zz-lib.sh:3 resolves" "the backtick spelling"
_f15_fx; printf '# was: %s\n' "$_F15_DIRTY" >> "$RP/bin/zz-guard.sh"
_rp_green F15 "the dirty line in a wired script's comment"
_f15_fx; rm "$RP/bin/zz-wrap.sh"
_rp_red F15 "bin/zz-wrap.sh is wired by bin/zz-install.sh and does not exist" "a wired script that is gone"
_f15_fx; _f15_sh bin/zz-hand.sh "$_F15_DIRTY" '. "$DIR/zz-hlib.sh"'; _f15_sh bin/zz-hlib.sh "$_F15_CLEAN"
_rp_green F15 "a dirty script no installer wires and no row declares"
printf '# script\tevent\twhy\nbin/zz-hand.sh\tStop\twired by hand\n' > "$RP/contracts/hooks-external.tsv"
_rp_red F15 "bin/zz-hand.sh:3 resolves its own directory through \$(dirname) and a hook runs it (contracts/hooks-external.tsv, Stop)" "a hook declared in contracts/hooks-external.tsv (harbor#813)"
_f15_sh bin/zz-hand.sh "$_F15_CLEAN" '. "$DIR/zz-hlib.sh"'; _f15_sh bin/zz-hlib.sh "$_F15_DIRTY"
_rp_red F15 "bin/zz-hlib.sh:3 resolves" "a library a declared hook sources"
_f15_sh bin/zz-hlib.sh "$_F15_CLEAN"; printf 'bin/zz-gone.sh\tStop\tx\nbin/zz-hlib.sh\n' >> "$RP/contracts/hooks-external.tsv"
_f15o="$(_rp F15)"
t_has "F15 a declared hook that is gone is red" "$_f15o" 'VIOLATION [admission.no-dirname] bin/zz-gone.sh is wired by contracts/hooks-external.tsv, Stop and does not exist'
t_has "F15 a declared row with no event is red" "$_f15o" 'VIOLATION [admission.no-dirname] contracts/hooks-external.tsv: bin/zz-hlib.sh names no event'
t_has "F15 a row's violation fails the run" "$_f15o" '1 rules, 2 violation(s)'
_f15_fx; printf 'X_HOOK="/bin/sh $DIR/bin/drift-reference-check.sh"\n' >> "$RP/bin/zz-install.sh"
_f15_sh bin/drift-reference-check.sh "$_F15_DIRTY"
_f15o="$(_rp F15)"
# harbor#880: drift-reference-check.sh's exemption (harbor#809) retired with its defect: a hook-run one on $(dirname) is red.
t_has "F15 the once-pending drift-reference-check.sh is a violation now" "$_f15o" 'VIOLATION [admission.no-dirname] bin/drift-reference-check.sh:3 resolves its own directory'

t_section "F11: a BSD-first stat fallback in one capture"
_rp_fresh; _rp_c='stat -c'; _rp_sh "$RP/bin/mtime.sh"
printf 'm="$(stat -f %%m "$f" 2>/dev/null)" || m="$(%s %%Y "$f")"\n' "$_rp_c" >> "$RP/bin/mtime.sh"
_rp_green F11 "two separate captures"
printf 'm="$(stat -f %%m "$f" 2>/dev/null || %s %%Y "$f")"\n' "$_rp_c" >> "$RP/bin/mtime.sh"
_rp_red F11 "a BSD-first stat fallback captured in one expression" "both spellings inside one \$(…)"
_rp_fresh; mkdir -p "$RP/tests/x"
printf 'm="$(stat -f %%m "$f" 2>/dev/null || %s %%Y "$f")"\n' "$_rp_c" > "$RP/tests/x/y-test.sh"
_rp_red F11 "tests/x/y-test.sh" "a one-capture fallback in a tests/ suite (harbor#667)"

t_section "N1 / T10 / T11: a skill's name, README row and triggers"
_rp_fresh; mkdir -p "$RP/skills/good-skill"
printf -- '---\nname: good-skill\ndescription: Does a thing. USE WHEN a thing.\n---\n' > "$RP/skills/good-skill/SKILL.md"
printf '# skills\n\n| `good-skill` | why it exists |\n' > "$RP/skills/README.md"
_rp_green N1 "a kebab-case skill named like its dir"
_rp_green T10 "a skill with a README row"
_rp_green T11 "a description with USE WHEN"
mkdir -p "$RP/skills/Zz_Probe"; printf -- '---\nname: Zz_Probe\ndescription: USE WHEN probing.\n---\n' > "$RP/skills/Zz_Probe/SKILL.md"
_rp_red N1 "skill dir not kebab-case: Zz_Probe" "skills/Zz_Probe/"
_rp_red T10 "skills/Zz_Probe has no row in skills/README.md" "a skill with no README row"
rm -rf "$RP/skills/Zz_Probe"
printf -- '---\nname: good-skill\ndescription: Does a thing, and says nothing about when.\n---\n' > "$RP/skills/good-skill/SKILL.md"
_rp_red T11 "skills/good-skill description carries no USE WHEN triggers" "a description with no USE WHEN"


t_section "G1 (advisory): a long script whose header does not say why"
_rp_fresh
code310() { awk 'BEGIN { for (i = 0; i < 310; i++) print "x=" i }'; }
{ printf '#!/usr/bin/env sh\n# fixture (harbor#588)\n'; code310; } > "$RP/bin/big.sh"
_rp_red G1 "ADVISORY [lint.long-file-reason] bin/big.sh is 310 lines of code" "310 lines of code under a header with no reason"
{ printf '#!/usr/bin/env sh\n# big (harbor#588) — DELIBERATELY ONE FILE (docs/explanation/modularity.md)\n'; code310; } > "$RP/bin/big.sh"
_rp_green G1 "the same length under a header that names its exemption"
{ printf '#!/usr/bin/env sh\n'; awk 'BEGIN { for (i = 0; i < 58; i++) print "# why this file is long, line " i }'
  printf '# DELIBERATELY ONE FILE (docs/explanation/modularity.md)\n'; code310; } > "$RP/bin/big.sh"
_rp_green G1 "an exemption at the end of a 60-line header (harbor#578)"
{ printf '#!/usr/bin/env sh\n[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0\n# DELIBERATELY ONE FILE (docs/explanation/modularity.md)\n'
  code310; } > "$RP/bin/big.sh"
_rp_green G1 "an exemption after the kill-switch preamble F1 requires"
{ printf '#!/usr/bin/env sh\n# big (harbor#578)\nset -eu\n# DELIBERATELY ONE FILE (docs/explanation/modularity.md)\n'; code310; } > "$RP/bin/big.sh"
_rp_red G1 "ADVISORY [lint.long-file-reason] bin/big.sh is 311 lines of code" "an exemption written after the first line of code"

t_section "C7: a guard token and the ledger's enum disagree"
_rp_fresh
printf "FLOOR_OBS_GUARDS=' bash egress '\n" > "$RP/bin/library-admission.sh"
_rp_sh "$RP/bin/guard-zz.sh"
printf 'floor_log_decision bash allow a.meta\nfloor_log_decision egress allow b.meta\n' >> "$RP/bin/guard-zz.sh"
_rp_green C7 "every logged token in the enum and every enum token logged"
printf 'floor_log_decision zzprobe allow c.meta\n' >> "$RP/bin/guard-zz.sh"
_rp_red C7 "guard token 'zzprobe' is passed to floor_log_decision but is NOT in FLOOR_OBS_GUARDS" "a token missing from the enum"
printf "FLOOR_OBS_GUARDS=' bash egress zzprobe ghost '\n" > "$RP/bin/library-admission.sh"
_rp_red C7 "FLOOR_OBS_GUARDS lists 'ghost' but no guard passes it" "an enum token no guard logs"
printf '# no enum line at all\n' > "$RP/bin/library-admission.sh"
_rp_red C7 "has no readable FLOOR_OBS_GUARDS line" "a library-admission.sh with no enum"

t_section "IJ1: a pack with no predicate, or where nothing reads it"
_rp_fresh; mkdir -p "$RP/context-rules/demo"
printf -- '---\ndescription: a demo pack\nevent: PreToolUse\nwhen: always\n---\nbody\n' > "$RP/context-rules/demo/demo.md"
_rp_green IJ1 "a pack with an event, a predicate and a body"
printf -- '---\ndescription: a demo pack\nevent: PreToolUse\n---\nbody\n' > "$RP/context-rules/demo/demo.md"
_rp_red IJ1 "pack has no when: predicate, so it can never fire" "a pack with no when:"
_rp_fresh; mkdir -p "$RP/context-rules/demo/sub" "$RP/context-rules/user"
printf -- '---\ndescription: a demo pack\nevent: PreToolUse\nwhen: always\n---\nbody\n' > "$RP/context-rules/demo/demo.md"
cp "$RP/context-rules/demo/demo.md" "$RP/context-rules/user/demo.md"; : > "$RP/context-rules/README.md"
_rp_green IJ1 "packs in two scopes, and a README beside them"
cp "$RP/context-rules/demo/demo.md" "$RP/context-rules/demo/a rule.md"
_rp_green IJ1 "a valid pack whose file name contains a space"
printf -- '---\ndescription: a demo pack\nevent: PreToolUse\n---\nbody\n' > "$RP/context-rules/demo/a rule.md"
_rp_red IJ1 "pack has no when: predicate, so it can never fire: context-rules/demo/a rule.md" "an invalid pack whose name has a space"
rm "$RP/context-rules/demo/a rule.md"
IJ1_WHERE='nothing installs or reads it (contracts/injection-rule.md names context-rules/<scope>/):'
cp "$RP/context-rules/demo/demo.md" "$RP/context-rules/top.md"
_rp_red IJ1 "pack sits where $IJ1_WHERE context-rules/top.md" "a pack at context-rules/top.md"
rm "$RP/context-rules/top.md"; cp "$RP/context-rules/demo/demo.md" "$RP/context-rules/demo/sub/deep.md"
_rp_red IJ1 "$IJ1_WHERE context-rules/demo/sub/deep.md" "a pack two levels deep"
rm "$RP/context-rules/demo/sub/deep.md"; mkdir -p "$RP/.claude/inject.d"; cp "$RP/context-rules/demo/demo.md" "$RP/.claude/inject.d/10-demo.md"
_rp_red IJ1 "retired inject.d/ layout, which nothing installs; move it to context-rules/<scope>/<id>.md: .claude/inject.d/10-demo.md" "a rule left in the old layout (harbor#1010)"

t_section "T8: an upstream hook with no docs/reference/coverage.md row"
_rp_fresh; mkdir -p "$TMP/rp-up/Mirror/install/hooks"; : > "$TMP/rp-up/Mirror/install/hooks/zzprobe.hook.ts"
mkdir -p "$RP/docs/reference"; printf '# coverage\n\n| `zzprobe` | taken |\n' > "$RP/docs/reference/coverage.md"
_rp_t8() { HARBOR_UPSTREAM_MIRROR="$1" _rp T8; }
t_has "no upstream mirror is said, never a quiet pass" "$(_rp_t8 "$TMP/rp-none")" 'skipped: no upstream mirror'
_o="$(_rp_t8 "$TMP/rp-up")"
t_hasnt "an upstream hook with its docs/reference/coverage.md row is silent" "$_o" 'VIOLATION [doc.coverage-row-per-hook]'
t_has "…and T8 ran against the supplied mirror" "$_o" '1 rules, 0 violations'
printf '# coverage\n' > "$RP/docs/reference/coverage.md"
t_has "an upstream hook with no row is red" "$(_rp_t8 "$TMP/rp-up")" 'upstream hook with no disposition in docs/reference/coverage.md: zzprobe'

t_section "T9 / X3: advisories that relay a generator's verdict"
_rp_fresh
printf '#!/usr/bin/env sh\nexit 0\n' > "$RP/bin/skill-catalog.sh"
_rp_green T9 "a skill catalog its generator calls current"
printf '#!/usr/bin/env sh\nexit 1\n' > "$RP/bin/skill-catalog.sh"
_rp_red T9 "ADVISORY [skill.book-current] skills/skill-catalog/SKILL.md is STALE" "a generator whose --check says stale"
printf '#!/usr/bin/env sh\necho boom >&2\nexit 3\n' > "$RP/bin/skill-catalog.sh"
_rp_red T9 "the generator FAILED (rc=3)" "a generator that crashes"
# The tracked book reads nothing outside the checkout (harbor#1149): a machine with no skills dir (CI, a stranger) gets the same verdict.
rm -rf "$CLAUDE_CONFIG_DIR/skills"; printf '#!/usr/bin/env sh\nexit 1\n' > "$RP/bin/skill-catalog.sh"
_rp_red T9 "ADVISORY [skill.book-current] skills/skill-catalog/SKILL.md is STALE" "a checkout on a machine with no skills dir"
mkdir -p "$CLAUDE_CONFIG_DIR/skills"
# The REAL generator: a router row it cannot read exits 3, and T9 reports a failed generator with the row's line (it exited 1, harbor#1149).
_rp_fresh; cp "$T_ROOT/bin/skill-catalog.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$RP/bin/"
mkdir -p "$RP/skills/alpha" "$RP/skills/skill-catalog"; printf -- '---\nname: alpha\ndescription: "Alpha. USE WHEN alpha work."\n---\n' > "$RP/skills/alpha/SKILL.md"
cp "$T_ROOT/skills/skill-catalog/SKILL.md" "$RP/skills/skill-catalog/SKILL.md"; printf 'skill\tsituation\nalpha\tAlpha work\n' > "$RP/contracts/skill-book-router.tsv"
(cd "$RP" && sh bin/skill-catalog.sh >/dev/null 2>&1); _rp_green T9 "the real generator over a book it just wrote"
printf 'stale\n' >> "$RP/skills/skill-catalog/SKILL.md"; _rp_red T9 "ADVISORY [skill.book-current] skills/skill-catalog/SKILL.md is STALE" "the real generator over a book that differs"
t_has "...the control for the assertion below: a book that differs is STALE" "$(_rp T9)" "is STALE"
(cd "$RP" && sh bin/skill-catalog.sh >/dev/null 2>&1); printf 'alpha\n' >> "$RP/contracts/skill-book-router.tsv"; _o="$(_rp T9)"
t_has "T9 calls a router row the generator cannot read a failed generator" "$_o" "the generator FAILED (rc=3)"
t_has "...with the line that names the row" "$_o" "expected 2 columns, got 1"
t_hasnt "...and never stale" "$_o" "is STALE"
_rp_fresh
printf '#!/usr/bin/env sh\ncase "${1:-}" in --check) exit 0 ;; esac\necho "42%% of ceiling"\n' > "$RP/bin/context-budget.sh"
_rp_green X3 "a surface at 42% of its ceiling"
t_has "X3 prints the surface's level" "$(_rp X3)" '42% of ceiling'
printf '#!/usr/bin/env sh\necho "OVER by 7 bytes"\ncase "${1:-}" in --check) exit 1 ;; esac\n' > "$RP/bin/context-budget.sh"
_rp_red X3 "ADVISORY [context.budget-ceiling] OVER by 7 bytes" "a surface over its ceiling"
t_has "X3 names what to run to trim it" "$(_rp X3)" 'ADVISORY [context.budget-ceiling] the breakdown, and what to trim: sh bin/memory-store-check.sh'
printf '#!/usr/bin/env sh\ncase "${1:-}" in --check) echo "SURFACE MOVED: 9 B"; exit 1 ;; esac\necho "42%% of ceiling"\n' > "$RP/bin/context-budget.sh"
_rp_red X3 "ADVISORY [context.budget-ceiling] SURFACE MOVED: 9 B" "a failing --check under the ceiling"

t_section "T1 / T1b / T1c: a hand edit to a regenerated file (T1b: an unknown hole in the page it builds)"
_RPA="$TMP/rp-archive"; mkdir -p "$_RPA"
if git -C "$ROOT" archive HEAD 2>/dev/null | tar -x -C "$_RPA" 2>/dev/null && [ -n "$(find "$_RPA/docs/src" -name '*.html' 2>/dev/null | head -1)" ]; then
  # T1b (harbor#1197): the page is not committed; the rule builds it to a temp path, green, then red on an unknown hole.
  _pg=absent; [ -e "$_RPA/docs/generated/status.md" ] || _pg=present; t_eq "T1b: the archive of HEAD carries no docs/index.html (an export, no dev layer: the page deploy-push.sh:82 built)" "$_pg" "$([ -e "$_RPA/docs/index.html" ] && echo present || echo absent)"; rm -f "$_RPA/docs/index.html"
  _rp_green T1b "a tree that carries the sources and no page" "$_RPA"
  _rpf="$(find "$_RPA/docs/src" -name '*.html' | sort | head -1)"; cp "$_rpf" "$TMP/rp-src.keep"; printf '<!--gen:no_such_table-->\n' >> "$_rpf"
  _rp_red T1b "docs/index.html cannot be built: unknown token <!--gen:no_such_table-->" "an unknown hole in docs/src" "$_RPA"
  cp "$TMP/rp-src.keep" "$_rpf"; _rp_green T1b "the same tree with the hole removed" "$_RPA"
  # docs/generated/status.md and docs/generated/plan.md are dev-layer: where the tree has neither, the rule says it skipped (tests/deploy/push/selfcontained.test.sh)
  for _t1 in "T1 docs/generated/status.md docs/generated/status.md is dev-layer" "T1c docs/generated/plan.md docs/generated/plan.md is generated from docs/reports/platform-build-tickets.md"; do set -- $_t1
    if [ -f "$_RPA/$2" ]; then _rp_green "$1" "$2 as committed" "$_RPA"; printf '\na hand edit\n' >> "$_RPA/$2"; _rp_red "$1" "$2 is stale" "a hand edit to $2" "$_RPA"
    else _rp_green "$1" "a tree with no $2" "$_RPA"; t_has "$1 says it skipped" "$(_rp "$1" "$_RPA")" "(skipped: ${_t1#* * }"; fi
  done
else t_fail "could not archive HEAD into a scratch tree, so T1, T1b and T1c were not red-proved"
fi

t_section "F9: a tests/ suite asserting a phrase absent with no positive control"
_rp_fresh; mkdir -p "$RP/tests/x"; _f9p="'no such wording'"
printf 't_hasnt "l" "$o" %s\nt_has "l" "$o" %s\n' "$_f9p" "$_f9p" > "$RP/tests/x/y-test.sh"
_rp_green F9 "a tests/ t_hasnt with its t_has twin"
printf 't_hasnt "l" "$o" %s\n' "$_f9p" > "$RP/tests/x/y-test.sh"
_rp_red F9 "asserts a phrase is ABSENT" "a tests/ t_hasnt with no t_has on the same phrase"

t_section "S4 / D6 / D7: the install standard's one parser (harbor#765)"
_rp_fresh
_rp_inst() { # <name> <body lines…>: an installer fixture on install-lib
  _rpf="$RP/bin/$1"; shift; _rp_sh "$_rpf"; printf 'set -eu\n' >> "$_rpf"; printf '%s\n' "$@" >> "$_rpf"
}
_IL_SRC='. "$(dirname "$0")/library-log.sh"; . "$(dirname "$0")/deploy-install-lib.sh"'
_rp_inst fix-install.sh "$_IL_SRC" 'il_parse "$@"; il_target' \
  'il_next "sh $0 --apply $(il_spell) --with-b6"' 'log_fix "$(il_cmd --apply --accept-loss)"'
_rp_green S4 "an installer that answers --help through il_parse"
_rp_green D6 "a hint spelled by il_spell and il_cmd"
_rp_inst run-install.sh "$_IL_SRC" 'il_parse "$@"; il_target' 'il_run sh "$DIR/bin/pin-instructions.sh" --apply'
_rp_green D6 "a child call run through il_run"
rm "$RP/bin/run-install.sh"
_rp_green D7 "an installer on install-lib: il_parse, il_target, no own flag arms"
_rp_inst nosrc-install.sh 'il_parse "$@"; il_target'
_rp_red D7 "bin/nosrc-install.sh does not source bin/deploy-install-lib.sh" "an installer calling il_parse with no source line"
_rp_red S4 "answers no --help: bin/nosrc-install.sh" "il_parse with no install-lib source: nothing answers --help"
rm "$RP/bin/nosrc-install.sh"
_rp_inst notgt-install.sh "$_IL_SRC" 'il_parse "$@"'
_rp_red D7 "bin/notgt-install.sh never calls il_target" "an installer that parses and never resolves a target"
rm "$RP/bin/notgt-install.sh"
_rp_inst noparse-install.sh "$_IL_SRC" 'il_target'
_rp_red D7 "bin/noparse-install.sh never calls il_parse" "an installer that never parses its argv"
rm "$RP/bin/noparse-install.sh"
_rp_inst arm-install.sh "$_IL_SRC" 'for a in "$@"; do case "$a" in --live) L=1 ;; esac; done' 'il_parse "$@"; il_target'
_rp_red D7 "bin/arm-install.sh parses a standard flag itself" "a second parser's --live arm, inline after in"
_rp_inst arm-install.sh "$_IL_SRC" 'while [ $# -gt 0 ]; do case "$1" in' '  --apply|--dry) A=1 ;;' 'esac; shift; done' 'il_parse "$@"; il_target'
_rp_red D7 "bin/arm-install.sh parses a standard flag itself" "a second parser's --apply arm, at a line start"
rm "$RP/bin/arm-install.sh"
_rp_inst env-install.sh "$_IL_SRC" 'CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"' 'il_parse "$@"; il_target'
_rp_red D7 "bin/env-install.sh reads CLAUDE_CONFIG_DIR as a default target" "an installer defaulting its target to CLAUDE_CONFIG_DIR"
rm "$RP/bin/env-install.sh"
_rp_inst deploy-harden.sh 'il_parse "$@"'
_rp_red D7 "bin/deploy-harden.sh does not source bin/deploy-install-lib.sh" "a named box tool (sec0-harden) off the library"
rm "$RP/bin/deploy-harden.sh"
# harbor#800: the three tools that still parsed a positional dir are named in D7's scope.
_rp_inst floor-deny.sh 'for a in "$@"; do case "$a" in --live) DIR="$HOME/.claude" ;; *) DIR="$a" ;; esac; done'
_rp_red D7 "bin/floor-deny.sh does not source bin/deploy-install-lib.sh" "floor-deny's positional parser, off the library (harbor#800)"
rm "$RP/bin/floor-deny.sh"
_rp_inst floor-verify.sh 'case "${1:-}" in' "  ''|--live) DIR=\"\${CLAUDE_CONFIG_DIR:-\$HOME/.claude}\" ;;" '  *) DIR="$1" ;;' 'esac'
_rp_red D7 "bin/floor-verify.sh does not source bin/deploy-install-lib.sh" "floor-verify's \$1 parser, off the library (harbor#800)"
_rp_inst floor-verify.sh "$_IL_SRC" 'DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"' 'il_parse "$@"; il_target'
_rp_red D7 "bin/floor-verify.sh reads CLAUDE_CONFIG_DIR as a default target" "floor-verify on the library that still lets the env pick the box"
rm "$RP/bin/floor-verify.sh"
_rp_inst drift-renew-check.sh "$_IL_SRC" 'while [ $# -gt 0 ]; do case "$1" in' '  --live) T="$HOME/.claude" ;;' 'esac; shift; done' 'il_parse "$@"; il_target'
_rp_red D7 "bin/drift-renew-check.sh parses a standard flag itself" "renew-check with its own --live arm beside il_parse (harbor#800)"
rm "$RP/bin/drift-renew-check.sh"
_rp_inst raw-install.sh "$_IL_SRC" 'il_parse "$@"; il_target' 'echo "  sh floor-install.sh $DIR --apply"'
_rp_red D6 "printed command its own gate refuses" "a hint that spells a raw \$DIR, beside il_parse"
rm "$RP/bin/raw-install.sh"
_rp_inst hint-install.sh "$_IL_SRC" 'il_parse "$@"; il_target' 'x="$(il_cmd --apply)"'
t_has "the D2 fixture carries the trigger shape the defer exists for" "$(cat "$RP/bin/hint-install.sh")" '--apply)'
_rp_green D2 "an installer on install-lib whose only --apply) is a \$(il_cmd --apply) hint"
rm "$RP/bin/hint-install.sh"
_rp_inst hint-only.sh 'x="$(il_cmd --apply)"'
_rp_red D2 "mutator without a --live gate: bin/hint-only.sh" "the same hint in a file with no il_target and no gate"
rm "$RP/bin/hint-only.sh"

t_done
