#!/usr/bin/env sh
# GOVERNANCE (harbor#3 follow-on) — enforce the conventions in standards/naming.md
# and the house style the floor scripts already follow.
#
# WHY THIS EXISTS: an audit on 2026-07-25 found harbor had NO CI, NO active git
# hooks, and exactly ONE continuously-enforced rule (the work-log gitleaks
# pre-push gate). Everything else — including CONTRACTS/README.md's claim that
# "a CI freshness check fails if a consumer's vendored copy drifts" — was prose.
# A convention nobody checks is a suggestion; this file is what makes them real.
#
#   sh lint-conventions.sh            # check, exit 1 on any violation
#   sh lint-conventions.sh --list     # show the rules and their status
#   sh lint-conventions.sh --ids      # each rule's id and the deprecated letter id it succeeds
#
# RULE IDS ARE <family>.<slug> (D-10, harbor#957): the first word of each `rule "…"` line, and
# permanent (D-19). The letter ids they replaced (F1, X5, …) are deprecated, never reused: a
# rule's letter is its function's suffix, `rule_F1() {`, so `--only F1` still runs
# admission.kill-switch-first. A rule born after harbor#957 has no letter: its function is
# named after its id (`rule_lint_id_one_meaning`). Output, LINT_REDLOG and the finding records
# carry the id; lint.id-one-meaning holds the map to one meaning per id.
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md): a flat list of independent
# rules. Same argument as floor-test.sh — no rule can affect another, so a
# split relocates lines without shrinking any blast radius.
#
# Every rule states a CHECKABLE assertion and prints the offending path. Adding
# a rule here is how a convention becomes binding.
set -u
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
FAIL=0
RULES=0
say()  { printf '%s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  VIOLATION [%s] %s\n' "$1" "$2" >&2  # <ID> <message> [subject…]
         [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$1" >> "$LINT_REDLOG" 2>/dev/null || :
         [ -z "${HARBOR_FINDINGS_OUT:-}" ] || { _fid="$1"; shift 2; _fsub V "$_fid" "$@"; }; }
rule() { RULES=$((RULES+1)); printf '── %s\n' "$1"
         [ -z "${HARBOR_FINDINGS_OUT:-}" ] || printf 'R\t%s\n' "${1%% *}" >> "$HARBOR_FINDINGS_OUT"; }

# ── the finding record (harbor#590, CONTRACTS/finding.md) ────────────────────
# Every ADVISORY line is printed beside `_adv <ID> <subject>…`, and lint FL2 fails a line that is
# not. The SUBJECT IS SUPPLIED HERE, NEVER PARSED FROM THE MESSAGE: a repo-relative path, a skill or
# repo name, a `kind:name` — never a count, a size or a date, which stay in the message as evidence.
# `bin/lint-test.sh is 1983 lines` changes on every commit, so G1's subject is the path alone and an
# accepted G1 re-opens only when the set of files changes. `-` marks a line that continues the one
# above it and adds no subject.
#
# COST: with HARBOR_FINDINGS_OUT unset — every push, every CI run — it is one `[ -z ]` per line and
# writes nothing. bin/findings.sh sets it, once a day at most, to reconcile the census into issues.
# LINT_REDLOG (harbor#577): bad and _adv append the rule id to it, so a run of the lint suites names
# every rule that went red at least once. bin/rule-health.sh reads it; unset, it costs one [ -z ].
# NOT A HARBOR_* KNOB, deliberately: it can never change a verdict (a failed append is swallowed),
# so it must reach every suite's linter, and t_init clears inherited HARBOR_* to keep knobs out (C10).
_adv() { [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$1" >> "$LINT_REDLOG" 2>/dev/null || :
         [ -z "${HARBOR_FINDINGS_OUT:-}" ] || _fsub A "$@"; return 0; }  # <ID> <subject>…
_fsub() { # <A|V> <ID> <subject>… — one `<kind> TAB <ID> TAB <subject>` line per subject
  _fk="$1"; _fr="$2"; shift 2
  [ "$#" -gt 0 ] || set -- "$_fr"   # a violation that names no subject is about its rule
  for _fs in "$@"; do
    [ -n "$_fs" ] && [ "$_fs" != - ] || continue
    case "$_fs" in "$ROOT"/*) _fs="${_fs#"$ROOT"/}" ;; esac
    case "$_fs" in *"$HOME"/*) _fs="${_fs%%"$HOME"/*}~/${_fs#*"$HOME"/}" ;; esac
    printf '%s\t%s\t%s\n' "$_fk" "$_fr" "$_fs" >> "$HARBOR_FINDINGS_OUT"
  done
  return 0
}

# _rule_map [file] → `fn TAB id TAB letter` per rule, in file order: fn is what follows `rule_` in the
# function name, id the first word of the `rule "…"` line under it, letter the deprecated id or `-`.
_rule_map() {
  awk '/^rule_[A-Za-z0-9_]+\(\) \{$/ { fn = substr($0, 6); sub(/\(\) \{$/, "", fn); next }
       fn != "" && /^rule "/ { id = substr($2, 2); sub(/"$/, "", id)
                              printf "%s\t%s\t%s\n", fn, id, (fn ~ /^[A-Z]+[0-9]+[a-z]?$/ ? fn : "-"); fn = "" }' "${1:-$0}"
}
[ "${1:-}" = "--list" ] && { grep -n '^rule ' "$0" | sed 's/^[0-9]*:rule /  /' | tr -d '"'; exit 0; }
[ "${1:-}" = "--ids" ] && { printf 'id\tdeprecated\n'; _rule_map | cut -f2,3; exit 0; }

# ── --only <ID> · run exactly one rule (harbor#537) ──────────────────────────
# WHY THIS EXISTS: every rule ran on every invocation, and the lint suite (then bin/lint-test.sh) calls
# this file ~39 times. Re-measured 2026-09-17 for harbor#531: the suite took
# 1,371 s and 78% of it was three arms asking a WHOLE-TREE lint a question about
# one rule — X7 alone paid 7 whole-repo runs for 679 s. It also made §2.10
# unreachable in practice: watching ONE rule go red meant running all 78.
#
# AN UNKNOWN ID IS A HARD ERROR, never a quiet run of nothing. `--only X7x`
# selecting zero rules and exiting 0 would report "0 violations" about a rule
# that never ran, which is the same false green the `renew-check` tokens exist
# to keep apart: "I could not look" must not render as "nothing is wrong".
#
# AND `--help` IS ANSWERED FOR REAL, WHICH IT WAS NOT BEFORE. Rule S4 requires
# every hand-invocable bin/*.sh to answer the flag, and it matches a `case`
# PATTERN rather than the word, precisely so a script that only TALKS about the
# flag cannot pass. This file passed anyway, and measured 2026-09-20 on 8ea3d70
# the pass came from ONE line — a comment inside rule CU1 quoting a DIFFERENT
# script's arms, `help` is spelled `""|-h|--help|help`. Strip comments and the
# file matched S4's pattern zero times, while `sh lint-conventions.sh --help`
# printed `78 rules, 14 violation(s)`: it ran the whole linter. S4's own regex
# does not self-match — `--help\)` is not `--help)` — so this is the comment
# case from the guard-satisfied-by-its-own-comment class, not self-reference.
# Until now it cost a silently ignored flag; with unknown options refused it
# would cost `exit 2` on `--help`, so the flag is handled here rather than
# grandfathered. S4's blind spot is a separate defect and is NOT fixed here.
case "${1:-}" in
  -h|--help)
    printf '%s\n' \
      'lint-conventions.sh — enforce standards/naming.md and the house style (harbor#3)' \
      '' \
      '  sh lint-conventions.sh                 check every rule, exit 1 on any violation' \
      '  sh lint-conventions.sh --list          list the rules and their ids' \
      '  sh lint-conventions.sh --ids           each id and the deprecated letter id it succeeds (D-19)' \
      '  sh lint-conventions.sh --only <ID>     run exactly one rule, by id or deprecated letter (unknown: exit 2)' \
      '  sh lint-conventions.sh --help' \
      '' \
      'HARBOR_ROOT points the rules at a tree other than this checkout.' \
      'Writes nothing. Exit 0 clean, 1 on a violation, 2 on bad usage.'
    exit 0 ;;
esac

ONLY=""
case "${1:-}" in
  --only)   ONLY="${2:-}"
            [ -n "$ONLY" ] || { printf 'lint-conventions: --only needs a rule ID (see --list)\n' >&2; exit 2; } ;;
  --only=*) ONLY="${1#--only=}"
            [ -n "$ONLY" ] || { printf 'lint-conventions: --only needs a rule ID (see --list)\n' >&2; exit 2; } ;;
  "")       ;;
  *)        printf 'lint-conventions: unknown option: %s\n' "${1:-}" >&2; exit 2 ;;
esac

# BOTH SKILL HOMES (2026-07-30). `vendor/skills/` holds vendored upstream skills;
# `skills/` holds the ones Harbor authors, and it was created outside every rule
# in this file — N1, N2, V1 and T6 all globbed `vendor/skills/` alone, so the
# first Harbor-authored skill could have had any directory name, any frontmatter
# key, and no SKILL.md at all, and this linter would have reported 0 violations.
# A new tracked home is not governed because it looks like the governed one.
#
# V1 is deliberately NOT extended: it asserts every skill has a PROVENANCE row,
# and a Harbor-authored skill has no upstream to cite. skills/README.md makes
# that argument, and forcing a row would make vendor/skills/PROVENANCE.md lie
# about its own contents — which K1 exists to prevent.
SKILL_HOMES="$ROOT/vendor/skills $ROOT/skills"

# THERE WAS A THIRD HOME AND IT IS GONE, 2026-09-06. `plugins/<name>/skills/<skill>/`
# was added here on 09-05 because a plugin skill was invisible to N1, N2 and N3 —
# measured on a fixture: moved to `skills/atlas/`, T10 fired immediately; left under
# `plugins/`, nothing did. That patch treated the symptom. The tier itself was the
# defect: SEVEN of eight gates could not see it (context-budget, skill-catalog,
# freshness, doctor, status-gen, skills-install, skills-collide all grep `plugins/`
# zero times), so teaching one linter about it left six holes open. atlas moved to
# `skills/atlas/` and the tier is retired — see DOCTRINE/no-authored-plugins.md and
# lint rule X6, which fails if it comes back.

# ── N1 · skill directories are kebab-case and match their name: field ────────

# ── shared across rules ──────────────────────────────────────────────────────
# HOISTED BY harbor#537, AND ONLY WHAT IS GENUINELY SHARED. Each definition
# below was measured to be used by a rule other than the one it sat in, so with
# one function per rule `--only X7` would have run against an undefined helper.
# Twelve of them; everything else stayed in the single block that reads it. The
# prose explaining each one stays with the rule that owns the question — the
# pointer is the symbol name, which greps to both places.
ALLOWED='name|description|when_to_use|user-invocable|argument-hint|allowed-tools|disable-model-invocation|version|effort|context|model|license|metadata|owns-commands|owns-tools|inline-section'
PROV="$ROOT/vendor/skills/PROVENANCE.md"
CI="$ROOT/.github/workflows/governance.yml"
_MAN="$ROOT/CONTRACTS/suites.txt"
_man_list() { grep -vE '^[[:space:]]*(#|$)' "$_MAN" 2>/dev/null; }
# _export_tree <dev-path>...: this tree does not carry the dev layer, as far as <dev-path>... can tell (harbor#1149).
# True when CONTRACTS/layers.tsv lists every argument as a dev row and none of them is on disk or in the index; no layers.tsv,
# or an argument it does not list as dev, is never an export. The arguments are WITNESSES, not "any dev path", and the choice
# is load-bearing: core tells an adopter to write HANDOFF.md (hooks/session-state/session-state.sh) and DEAD-ENDS.md (CONTRACTS/memory-format.md),
# so a tree holding either is still the export and must not turn the two rules below red with a fix the export cannot run
# (plan-status.sh needs harbor-build-tickets.md). The index counts as well as the disk, so a witness deleted from a dev
# checkout and not yet committed stays red there. Used by the two rules whose subject is a generated dev-layer file
# (doc.status-generated, doc.plan-generated).
_export_tree() (
  [ -f "$ROOT/CONTRACTS/layers.tsv" ] && [ "$#" -gt 0 ] || exit 1
  for _et_p in "$@"; do
    awk -F'\t' -v p="$_et_p" '$1 == p && $2 == "dev" { f = 1 } END { exit !f }' "$ROOT/CONTRACTS/layers.tsv" || exit 1
    [ ! -e "$ROOT/$_et_p" ] || exit 1
    [ -z "$(git -C "$ROOT" ls-files -- "$_et_p" 2>/dev/null)" ] || exit 1
  done
)
_fx='evil\.com|example\.(com|org)|localhost|domain\.tld|interactsh|https://x[\\]?$|abc\.com|target\.com|https?://[^ ]*\*|https?://[^ ]*<|https?://[^ ]*\$[0-9]|https://www\.googleapis\.com/auth/'
_x8_mtime() { # <file> -> epoch seconds, or empty
  _v="$(stat -f %m "$1" 2>/dev/null || true)"
  case "$_v" in ''|*[!0-9]*) _v="$(stat -c %Y "$1" 2>/dev/null || true)" ;; esac
  case "$_v" in ''|*[!0-9]*) _v="" ;; esac
  printf '%s' "$_v"
}
_x8_repo_time() { # <file in $ROOT> -> epoch seconds, or empty
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
     && git -C "$ROOT" diff --quiet HEAD -- "$1" 2>/dev/null \
     && [ -z "$(git -C "$ROOT" ls-files --others --exclude-standard -- "$1" 2>/dev/null)" ]; then
    _rv="$(git -C "$ROOT" log -1 --format=%ct -- "$1" 2>/dev/null || true)"
    case "$_rv" in ''|*[!0-9]*) _rv="" ;; esac
    if [ -n "$_rv" ]; then printf '%s' "$_rv"; return 0; fi
  fi
  _x8_mtime "$1"
}
_installer_payload() {
  sed -n 's/^FILES="\(.*\)"/\1/p'        "$ROOT"/bin/*-install.sh 2>/dev/null
  sed -n 's/^REFRESH_ONLY="\(.*\)"/\1/p' "$ROOT"/bin/*-install.sh 2>/dev/null
  sed -n "s/^GUARDS='\(.*\)'/\1/p"       "$ROOT"/bin/*-install.sh 2>/dev/null
  sed -n "s/^PAYLOAD='\(.*\)'/\1/p"      "$ROOT"/bin/*-install.sh 2>/dev/null
  # Copied by name rather than through a list, so it cannot be derived above.
  grep -ohE 'cp "\$SRC/[a-z0-9-]+\.sh"'   "$ROOT"/bin/*-install.sh 2>/dev/null \
    | sed -E 's#.*/##; s/"$//'
}
LIVEBIN="${HELM_LIVE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/bin"
# The repo file an installed name ships from: bin/<name>, else its hook engine folder (D-88; il_src in bin/install-lib.sh).
_payload_src() { if [ -f "$ROOT/bin/$1" ] || [ ! -f "$ROOT/hooks/${1%.*}/$1" ]; then printf '%s' "$ROOT/bin/$1"; else printf '%s' "$ROOT/hooks/${1%.*}/$1"; fi; }
_x7_src_is_own_dir() { # <bin-relative script> [variable, default SRC]
  grep -qE '^'"${2:-SRC}"'="\$\(CDPATH= cd -- "\$\(dirname -- "\$0"\)" && pwd\)"' "$(_payload_src "$1")" 2>/dev/null
}
_x7_read_only() { # <bin-relative script> <referenced script>
  _x7ro="$(grep -v '^[[:space:]]*#' "$(_payload_src "$1")" 2>/dev/null \
           | grep -E '\$(SRC_DIR|SRC|DIR|CFG)(/bin)?/'"$2" || true)"
  [ -n "$_x7ro" ] || return 1
  # Any line that is not a read-tool invocation disqualifies the exemption.
  printf '%s\n' "$_x7ro" \
    | grep -qvE '(sed|grep|egrep|fgrep|cat|head|tail|wc|cut|sort|comm|cmp|diff)[[:space:]]' \
    && return 1
  return 0
}
# _justfile_bin_paths — every bin/ path the justfile names, one per line, sorted and unique. THE ONE
# PARSER for the justfile: S5 asks whether each path resolves, C8 asks which tools a recipe runs
# (harbor#474). Two parsers would disagree about the same file.
# AWK, NOT grep -o AND NOT sed: this box's grep is a ugrep wrapper, so a negative rested on it is not
# evidence (F3's note), and BSD sed has no ERE alternation to express the leading boundary this needs.
# THE BOUNDARY IS LOAD-BEARING AND ITS ABSENCE WAS S5's FIRST FINDING. Without it `#!/usr/bin/env sh`
# inside a recipe body matched, and S5 reported `bin/env` as a missing path — a §2.11 false positive
# on its first run. `bin/` must start a word.
_justfile_bin_paths() {
  [ -f "$ROOT/justfile" ] || return 0
  awk '{ l = $0
         while (match(l, /(^|[^\/A-Za-z0-9_.-])bin\/[A-Za-z0-9_-][A-Za-z0-9._-]*/)) {
           t = substr(l, RSTART, RLENGTH); sub(/^[^b]/, "", t); print t
           l = substr(l, RSTART + RLENGTH)
         } }' "$ROOT/justfile" | sort -u
}


# ── the shellcheck pass · shared by F12 and F13, computed at most once ───────
# HOISTED BY harbor#537, AND THE ORDERING BUG IT FIXED IS THE REASON IT MOVED.
# F13 read F12's `$_F12RAW` directly, on purpose: re-running the tool over ~180
# files for one more pattern would roughly double the slowest rule in this file
# (~50 s of a ~115 s whole-repo lint). That worked only while every rule ran, in
# order, on every invocation. Once each rule became a function, `--only F13`
# died on `_F12RAW: unbound variable` — found by diffing 78 isolated runs
# against the whole-tree run, NOT by the suite, which had never run one rule on
# its own. The coupling is now a CALL rather than a position: whoever asks first
# pays, everyone after reads the memo, and a full run still invokes the tool
# exactly once.
#
# THE MEMO IS A GLOBAL, NOT A `$( )`. A command substitution runs in a subshell,
# so a cache written inside one is thrown away on return and every caller would
# quietly pay again — with the right answer, which is what makes it invisible.
_SC_RAW=''
# _sc_scope — the scripts F12 and F13 judge, into $_sc_files. F12's -nt/-ot arm
# (harbor#811) reads the same list, so the two halves cannot disagree on scope.
# The hook engines (D-88, harbor#1272): hooks/<e>/<e>.sh, never the .test.sh beside them, as the renderer defines them. A rule over
# bin/*.sh that would lose a moved engine reads these too, so the move narrows no rule.
_engines() {
  sh "$ROOT/bin/deploy-hooks.sh" --engines --root "$ROOT" 2>/dev/null || :
}
_sc_scope() {
  _sc_files=''
  # tests/*/*.sh: suites and the harness left bin/ for tests/ (harbor#667) and must stay POSIX.
  for f in "$ROOT"/bin/*.sh "$ROOT"/bin/harbor "$ROOT"/bin/gcx "$ROOT"/hooks/* "$ROOT"/hooks/*/*.sh \
           "$ROOT"/worklog/* "$ROOT"/skills/*/bin/*.sh "$ROOT"/tests/*/*.sh; do
    [ -f "$f" ] || continue; case "$f" in *.md) continue ;; esac
    _sc_files="$_sc_files $f"
  done
}
_shellcheck_raw() {
  [ -n "${_SC_DONE:-}" ] && return 0
  _SC_DONE=1
  command -v shellcheck >/dev/null 2>&1 || return 0
  _sc_scope
  # The tool's own exit status is non-zero whenever it reports ANYTHING, and this
  # rule cares about one family, so the verdict is the filtered output.
  #
  # NEITHER COMMENT ABOVE MAY BEGIN WITH THE TOOL'S NAME, and that is not style.
  # A comment whose first word is that name is parsed as a DIRECTIVE; a prose
  # sentence after it is a parse error, and the parse error ABORTS THE FILE. Two
  # such sentences sat at lines 556 and 596 of this very file, and the second was
  # invisible until the first was fixed, because the abort is serial. Measured
  # 2026-09-16: a bash array planted at line 600 of this file drew ZERO findings
  # with them in place and SC3030 + SC3054 with them reworded. So F12 -- the rule
  # that greps for exactly SC3xxx -- read clean over 61 of this linter's 76 rules
  # because its instrument had stopped, not because the code was POSIX. The arm
  # below is what makes a re-break loud instead of silent.
  _SC_RAW="$(_sc_run)"
}
# _sc_run — shellcheck over $_sc_files in ordered chunks, one per CPU slot (harbor#1085): the
# serial pass was 38 s of a 56 s lint on idle CPUs. Chunks are concatenated in list order, so the
# output is byte-for-byte the single call's; a chunk that fails to start is an empty one, as before.
_sc_cpus() { # the container's CPU quota (cgroup v2) when it has one, else the online CPUs
  _q="$(cat /sys/fs/cgroup/cpu.max 2>/dev/null || :)"
  case "$_q" in [0-9]*' '[0-9]*) printf '%s\n' "$_q" | awk '{ c = int(($1 + $2 - 1) / $2); print (c < 1 ? 1 : c) }'; return ;; esac
  getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1
}
_sc_run() {
  _scd="$(mktemp -d "${TMPDIR:-/tmp}/lint-sc.XXXXXX")" || { shellcheck -s sh -f gcc $_sc_files 2>/dev/null || :; return 0; }
  for f in $_sc_files; do printf '%s\n' "$f"; done | split -l 6 - "$_scd/c."
  printf '%s\n' "$_scd"/c.?? | xargs -P "$(_sc_cpus)" -n 1 sh -c 'shellcheck -s sh -f gcc $(cat "$0") > "$0.out" 2>/dev/null || :' || :
  for f in "$_scd"/c.??.out; do [ ! -f "$f" ] || cat "$f"; done
  rm -rf "$_scd"
}

rule_N1() {
rule "skill.dir-matches-name skill dirs are kebab-case and equal their name: field (standards/naming.md)"
for _h in $SKILL_HOMES; do
  [ -d "$_h" ] || continue
  for d in "$_h"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    # letters spelled out: under en_NZ, macOS sh lets [a-z] match capitals (harbor#1149)
    case "$n" in
      *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) bad skill.dir-matches-name "skill dir not kebab-case: $n" ;;
    esac
    [ -f "$d/SKILL.md" ] || { bad skill.dir-matches-name "skill has no SKILL.md: $n"; continue; }
    v="$(grep -m1 '^name:' "$d/SKILL.md" 2>/dev/null | sed 's/^name:[[:space:]]*//')"
    [ "$v" = "$n" ] || bad skill.dir-matches-name "dir/name mismatch: $n has name: $v"
  done
done
}


# ── N3 · a NOT FOR handoff names a skill that exists (harbor#273) ───────────
# THE DEFECT, AND IT WAS SHIPPED BY A DEPLOY. On 2026-08-22 twelve skills were
# renamed PascalCase -> kebab-case, which is what N1 above requires. Two
# `description:` lines still handed off to the old names — `(use RedTeam)` and
# `(ExtractWisdom)` — and N1 cannot see that: it checks a skill against its own
# directory, never against the names it POINTS AT.
#
# Why the description and not the body. `skill-catalog` renders the description, and
# most skills on this box are hidden from the model's listing, so a `NOT FOR`
# clause is the routing an operator actually follows. A name in the body is prose
# the reader meets after opening the file; a name in the description is a
# signpost, and a signpost to nothing is worse than none.
#
# WHY THIS IS A RULE AND NOT A ONE-OFF EDIT. The two references were fixed in the
# same commit as this rule, and without the rule the next rename re-opens the
# class silently — the reference lives in a different file from the thing renamed,
# so nothing about the rename looks wrong. That asymmetry is the whole argument.
#
# NARROWLY SCOPED, BECAUSE THE WIDE VERSION WAS MEASURED AND REJECTED. Rewriting
# every PascalCase skill name anywhere in the sources touched 209 lines across 29
# files and mangled prose — `# Fabric` became `# fabric`, "When to Use Fabric CLI
# Directly" lost its capital — because those strings are also ordinary English and
# product names. So this reads ONLY the parenthesised names inside a `NOT FOR`
# clause of a `description:`, and only flags one that looks like a skill
# reference: PascalCase or kebab-case with no spaces. A parenthetical like
# `(Research)` names a skill this box never took, and PROVENANCE records that
# under "what was NOT taken" — so an unresolvable name is reported as ADVISORY
# rather than failing the build, and the advisory names the file.
rule_N3() {
rule "skill.not-for-target-exists a NOT FOR handoff in a description names a skill that exists (advisory) (harbor#273)"
_n3_known=""
for _h in $SKILL_HOMES; do
  [ -d "$_h" ] || continue
  for d in "$_h"/*/; do
    [ -d "$d" ] && _n3_known="$_n3_known $(basename "$d")"
  done
done
# A tracked slash command is invoked like a skill, so it is a handoff target too (harbor#1010: review-fanout -> harbor-merge).
for _c in "$ROOT"/commands/*.md; do [ -f "$_c" ] && _n3_known="$_n3_known $(basename "$_c" .md)"; done
_n3_hits=0
for _h in $SKILL_HOMES; do
  [ -d "$_h" ] || continue
  for d in "$_h"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    _me="$(basename "$d")"
    _desc="$(awk 'NR==1 && $0 !~ /^---/ {exit} /^---[[:space:]]*$/ {n++; if (n>=2) exit; next} /^description:/ {print; exit}' "$d/SKILL.md")"
    case "$_desc" in *"NOT FOR"*) ;; *) continue ;; esac
    _tail="${_desc#*NOT FOR}"
    # Each parenthesised group in the NOT FOR clause, one per line.
    printf '%s\n' "$_tail" | tr '(' '\n' | sed -n 's/^\([^)]*\)).*/\1/p' | while IFS= read -r _ref; do
      _ref="${_ref#use }"
      _ref="$(printf '%s' "$_ref" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      # A skill reference is one word, PascalCase or kebab. Anything with a space
      # is a description, not a name.
      case "$_ref" in
        ''|*[[:space:]]*|*,*) continue ;;
        *[!A-Za-z0-9-]*) continue ;;
      esac
      case " $_n3_known " in
        *" $_ref "*) continue ;;
      esac
      _adv skill.not-for-target-exists "$_me->$_ref"; printf '  ADVISORY [skill.not-for-target-exists] %s hands off to "%s", which no tracked skill provides\n' "$_me" "$_ref"
    done
  done
done
}
# ── N2 · no NEW bespoke frontmatter keys ────────────────────────────────────
# The harness reads a fixed key set; anything else is dead weight that invites
# per-repo divergence. version:/effort: are upstream legacy — recorded as known,
# so the rule catches NEW inventions rather than re-flagging the backlog.
rule_N2() {
rule "skill.frontmatter-keys frontmatter uses harness-defined keys only (known legacy allowed)"
# ALLOWED is defined in the shared section at the top (harbor#537) — another rule reads it.
for _h in $SKILL_HOMES; do
  [ -d "$_h" ] || continue
  for f in "$_h"/*/SKILL.md; do
    [ -f "$f" ] || continue
    awk '/^---$/{c++; next} c==1' "$f" 2>/dev/null \
      | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*:' | tr -d ':' \
      | grep -vE "^($ALLOWED)$" \
      | while IFS= read -r k; do [ -n "$k" ] && printf '  VIOLATION [skill.frontmatter-keys] bespoke frontmatter key "%s" in %s\n' "$k" "${f#$ROOT/}" >&2; done
  done
  c="$(for f in "$_h"/*/SKILL.md; do awk '/^---$/{c++; next} c==1' "$f" 2>/dev/null; done \
       | grep -oE '^[A-Za-z_][A-Za-z0-9_-]*:' | tr -d ':' | grep -vcE "^($ALLOWED)$")"
  [ "${c:-0}" -gt 0 ] && FAIL=$((FAIL+1))
done
}

# ── N4 · every name passes the naming registry's own lint (warn, harbor#950) ──
# standards/naming.md is the standard and standards/naming/*.tsv its registry; bin/lint-name.sh judges
# every tracked name against them. This rule only RUNS it and relays its findings: a second spelling
# of the grammar here would be the copy the registry exists to remove. Warn like every naming rule
# (§10.3): the legacy names are exemptions that only shrink, so what prints is what a branch added.
# A lint that could not judge (missing, or exit above 1) is a VIOLATION: "I could not look" must not
# read as "nothing is wrong".
# THE RED LOG CARRIES name.* IDS, NEVER N4, FOR A NAMING FINDING (harbor#950). Each rule is promoted to
# block on its own 4-week record (§10.3), so lint-name.sh writes its own rule ids to LINT_REDLOG and
# the relay below writes none: under one N4 id the record would say nothing per rule. N4 is red in the
# log only when it could not judge, through bad().
rule_N4() {
rule "standard.names-conform every name passes bin/lint-name.sh against standards/naming/ (warn) (harbor#950)"
_n4="$ROOT/bin/lint-name.sh"
if [ ! -f "$_n4" ]; then bad standard.names-conform "no bin/lint-name.sh in this tree, so no name was judged"; return 0; fi
_n4o="${TMPDIR:-/tmp}/n4.$$"; _n4rc=0; _n4red="${LINT_REDLOG:-}"
LINT_REDLOG="$_n4red" sh "$_n4" --root "$ROOT" > /dev/null 2> "$_n4o" || _n4rc=$?
if [ "$_n4rc" -gt 1 ]; then
  bad standard.names-conform "bin/lint-name.sh exited $_n4rc and judged nothing: $(grep -m1 'FAIL:' "$_n4o" | sed 's/^ *FAIL: //')"
else
  _n4n=0; LINT_REDLOG=""   # the relay records findings, not reds: lint-name.sh already logged its ids
  while IFS= read -r _n4l; do
    case "$_n4l" in
      '  WARN: ['*) _n4n=$((_n4n + 1)); _n4s="${_n4l#*] }"; _n4s="${_n4s%% — *}"
                    _adv standard.names-conform "$_n4s"; printf '  ADVISORY [standard.names-conform] %s\n' "${_n4l#  WARN: }" >&2 ;;
      '  FAIL: ['*) _n4s="${_n4l#*] }"; LINT_REDLOG="$_n4red"; bad standard.names-conform "${_n4l#  FAIL: }" "${_n4s%% — *}"; LINT_REDLOG="" ;;
    esac
  done < "$_n4o"
  LINT_REDLOG="$_n4red"
  [ "$_n4n" -gt 0 ] || say "  $(tail -1 "$_n4o")"
fi
rm -f "$_n4o"
}

# ── standard.names-added · every path the branch adds passes bin/lint-name.sh (warn, harbor#968) ──
# N4 judges the whole tree, so what it prints mixes what a branch added with what the legacy list never covered.
# This asks the narrower question on its own record: of the paths THIS branch adds against its base, which break
# the grammar? It RUNS `bin/lint-name.sh --added` and relays its findings, as N4 does, so the grammar stays in
# the registry and one spelling of it exists. It exists so the backlog of legacy names stops growing while the
# rename waves wait. Warn; promoting it to block is a person's PR (standards/naming.md §10.3, D-64), and nothing
# here moves it.
# THE RED LOG CARRIES standard.names-added FOR AN ADDED PATH THAT BROKE THE GRAMMAR, through _adv: that is the
# rule's own record (lint-name.sh also writes the name.* rule ids it went red on). N4 records none of its own
# because its findings are not one rule's; this rule's are, and its 4 weeks are counted from this id.
# A lint that exits above 1 could not judge and is a VIOLATION, as in N4: an unreadable registry or private overlay
# exits 3 too, and must not be taken for a missing base. A lint that is not in the tree is skipped by name, because
# N4 on the same tree already makes that a VIOLATION and a second one would count it twice. A tree that is not git
# has no branch to ask about, and one with no base to compare against (a shallow clone, no origin/main) could not
# look: that is said as an advisory, never silence, so a missing base never reads as "no path was added". THE
# MISSING BASE IS TOLD FROM THE OTHER EXIT-3 CAUSES BY lint-name.sh's `no base to compare against` FAIL line; if that
# wording moves, a missing base turns into a VIOLATION, which is loud, never a silent pass.
rule_standard_names_added() {
rule "standard.names-added every path the branch adds passes bin/lint-name.sh (warn) (harbor#968)"
_na="$ROOT/bin/lint-name.sh"
if [ ! -f "$_na" ]; then say "  skip: no bin/lint-name.sh in this tree, so no added path was judged"; return 0; fi
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then say "  skip: not a git tree, so there is no branch to ask what it added"; return 0; fi
_nao="${TMPDIR:-/tmp}/na.$$"; _narc=0
sh "$_na" --root "$ROOT" --added > /dev/null 2> "$_nao" || _narc=$?
if [ "$_narc" -eq 3 ] && grep -q 'FAIL: no base to compare against' "$_nao"; then
  _nar="${LINT_REDLOG:-}"; LINT_REDLOG=""   # "could not look" is not the rule going red: its record stays honest
  _adv standard.names-added bin/lint-name.sh; printf '  ADVISORY [standard.names-added] unchecked: no base to compare against (HARBOR_BASE, else origin/main), so no added path was judged\n' >&2
  LINT_REDLOG="$_nar"
elif [ "$_narc" -gt 1 ]; then
  bad standard.names-added "bin/lint-name.sh exited $_narc and judged nothing: $(grep -m1 'FAIL:' "$_nao" | sed 's/^ *FAIL: //')"
else
  _nan=0
  while IFS= read -r _nal; do
    case "$_nal" in
      '  WARN: ['*) _nan=$((_nan + 1)); _nas="${_nal#*] }"; _nas="${_nas%% — *}"
                    _adv standard.names-added "$_nas"; printf '  ADVISORY [standard.names-added] %s\n' "${_nal#  WARN: }" >&2 ;;
      '  FAIL: ['*) _nas="${_nal#*] }"; bad standard.names-added "${_nal#  FAIL: }" "${_nas%% — *}" ;;
    esac
  done < "$_nao"
  [ "$_nan" -gt 0 ] || say "  $(tail -1 "$_nao")"
fi
rm -f "$_nao"
}

# ── module.graph-conform · the reference graph passes bin/lint-module.sh (warn, harbor#996) ──
# Builds the graph into a temp file (never build/graph.tsv: a stale one is exactly what this must not judge)
# and RUNS bin/lint-module.sh on it, relaying its findings as advisories like N4 does: the rules, their modes
# and their ids are lint-module.sh's and controls.tsv's, so a second spelling here would be the copy the
# registry exists to remove. Cost: one graph-gen.sh build, about 9 s on the box. Without python3 the graph
# cannot be built, and that is said as an advisory, never silence: "could not look" must not read as clean.
# A tree that carries neither tool is not a harbor checkout and is skipped, as the fixture trees are.
rule_module_graph_conform() {
rule "module.graph-conform the reference graph passes bin/lint-module.sh: system, family and layer edges (warn) (harbor#996)"
_mg="$ROOT/bin/lint-module.sh"; _mgg="$ROOT/bin/graph-gen.sh"
if [ ! -f "$_mg" ] || [ ! -f "$_mgg" ]; then say "  skip: no bin/lint-module.sh and bin/graph-gen.sh in this tree, so no graph was judged"; return 0; fi
_mgd="${TMPDIR:-/tmp}/mg.$$"; mkdir -p "$_mgd"; _mgrc=0
sh "$_mgg" --root "$ROOT" --out "$_mgd/graph.tsv" > /dev/null 2> "$_mgd/gen.err" || _mgrc=$?
if [ "$_mgrc" -eq 3 ]; then
  _adv module.graph-conform build/graph.tsv; printf '  ADVISORY [module.graph-conform] unchecked: python3 is absent, so no module edge was judged (install python3)\n' >&2
elif [ "$_mgrc" -ne 0 ]; then
  bad module.graph-conform "bin/graph-gen.sh exited $_mgrc and built no graph: $(grep -m1 'FAIL:' "$_mgd/gen.err" | sed 's/^ *FAIL: //')"
else
  _mgred="${LINT_REDLOG:-}"; _mgrc=0
  LINT_REDLOG="$_mgred" sh "$_mg" --root "$ROOT" --graph "$_mgd/graph.tsv" > /dev/null 2> "$_mgd/out" || _mgrc=$?
  if [ "$_mgrc" -gt 1 ]; then
    bad module.graph-conform "bin/lint-module.sh exited $_mgrc and judged nothing: $(grep -m1 'FAIL:' "$_mgd/out" | sed 's/^ *FAIL: //')"
  else
    _mgn=0; LINT_REDLOG=""   # the relay records findings, not reds: lint-module.sh already logged its ids
    while IFS= read -r _mgl; do
      case "$_mgl" in
        '  WARN: ['*) _mgn=$((_mgn + 1)); _mgs="${_mgl#*] }"; _mgs="${_mgs%% — *}"
                      _adv module.graph-conform "$_mgs"; printf '  ADVISORY [module.graph-conform] %s\n' "${_mgl#  WARN: }" >&2 ;;
        '  FAIL: ['*) _mgs="${_mgl#*] }"; LINT_REDLOG="$_mgred"; bad module.graph-conform "${_mgl#  FAIL: }" "${_mgs%% — *}"; LINT_REDLOG="" ;;
      esac
    done < "$_mgd/out"
    LINT_REDLOG="$_mgred"
    [ "$_mgn" -gt 0 ] || say "  $(tail -1 "$_mgd/out")"
  fi
fi
rm -rf "$_mgd"
}

# ── doc.refs-conform · the entry docs pass bin/doc-refs.sh (warn, harbor#996 E1) ──
# RUNS bin/doc-refs.sh on this tree and relays its findings as advisories, as N4 and module.graph-conform do: the
# rules, their modes and their ids are doc-refs.sh's and controls.tsv's, so a second spelling here would be the copy
# the registry exists to remove. A citation it could not look at (a sibling checkout absent in CI, a shallow clone)
# is counted NOT JUDGED in its summary line, which is printed when there is no finding. A tree without the tool is skipped.
rule_doc_refs_conform() {
rule "doc.refs-conform the entry docs pass bin/doc-refs.sh: cited paths resolve, docs are not left behind (warn) (harbor#996)"
_dr="$ROOT/bin/doc-refs.sh"
if [ ! -f "$_dr" ]; then say "  skip: no bin/doc-refs.sh in this tree, so no entry doc was judged"; return 0; fi
_drd="${TMPDIR:-/tmp}/dr.$$"; _drrc=0; _drred="${LINT_REDLOG:-}"
LINT_REDLOG="$_drred" sh "$_dr" --root "$ROOT" > /dev/null 2> "$_drd" || _drrc=$?
if [ "$_drrc" -gt 1 ]; then
  bad doc.refs-conform "bin/doc-refs.sh exited $_drrc and judged nothing: $(grep -m1 'FAIL:' "$_drd" | sed 's/^ *FAIL: //')"
else
  _drn=0; LINT_REDLOG=""   # the relay records findings, not reds: doc-refs.sh already logged its ids
  while IFS= read -r _drl; do
    case "$_drl" in
      '  WARN: ['*) _drn=$((_drn + 1)); _drs="${_drl#*] }"; _drs="${_drs%% — *}"
                    _adv doc.refs-conform "$_drs"; printf '  ADVISORY [doc.refs-conform] %s\n' "${_drl#  WARN: }" >&2 ;;
      '  FAIL: ['*) _drs="${_drl#*] }"; LINT_REDLOG="$_drred"; bad doc.refs-conform "${_drl#  FAIL: }" "${_drs%% — *}"; LINT_REDLOG="" ;;
    esac
  done < "$_drd"
  LINT_REDLOG="$_drred"
  [ "$_drn" -gt 0 ] || say "  $(grep -m1 'no finding in' "$_drd" | sed -E 's/^ *(ok|note): //')"
fi
rm -f "$_drd"
}

# ── standard.shape-conform · every instance carries its kinds.tsv shapes (warn, harbor#996 G2) ──
# Builds the graph into a temp file (never build/graph.tsv: a stale one is what this must not judge) and RUNS
# bin/standard-shape.sh on it, relaying its findings as advisories as module.graph-conform does: the rule, its mode
# and its id are standard-shape.sh's and controls.tsv's. Cost: a second graph-gen.sh build (about 9 s of CPU on the
# box) and one catalog listing (under 1 s). Without python3 no graph is built, and that is an advisory, never silence.
# A tree that carries neither tool is not a harbor checkout and is skipped, as the fixture trees are.
rule_standard_shape_conform() {
rule "standard.shape-conform every instance of a kind carries its kinds.tsv shapes, judged by bin/standard-shape.sh (warn) (harbor#996)"
_ss="$ROOT/bin/standard-shape.sh"; _ssg="$ROOT/bin/graph-gen.sh"
if [ ! -f "$_ss" ] || [ ! -f "$_ssg" ]; then say "  skip: no bin/standard-shape.sh and bin/graph-gen.sh in this tree, so no shape was judged"; return 0; fi
_ssd="${TMPDIR:-/tmp}/ss.$$"; mkdir -p "$_ssd"; _ssrc=0
sh "$_ssg" --root "$ROOT" --out "$_ssd/graph.tsv" > /dev/null 2> "$_ssd/gen.err" || _ssrc=$?
if [ "$_ssrc" -eq 3 ]; then
  _adv standard.shape-conform build/graph.tsv; printf '  ADVISORY [standard.shape-conform] unchecked: python3 is absent, so no shape was judged (install python3)\n' >&2
elif [ "$_ssrc" -ne 0 ]; then
  bad standard.shape-conform "bin/graph-gen.sh exited $_ssrc and built no graph: $(grep -m1 'FAIL:' "$_ssd/gen.err" | sed 's/^ *FAIL: //')"
else
  _ssred="${LINT_REDLOG:-}"; _ssrc=0
  LINT_REDLOG="$_ssred" sh "$_ss" --root "$ROOT" --graph "$_ssd/graph.tsv" > /dev/null 2> "$_ssd/out" || _ssrc=$?
  if [ "$_ssrc" -gt 1 ]; then
    bad standard.shape-conform "bin/standard-shape.sh exited $_ssrc and judged nothing: $(grep -m1 'FAIL:' "$_ssd/out" | sed 's/^ *FAIL: //')"
  else
    _ssn=0; LINT_REDLOG=""   # the relay records findings, not reds: standard-shape.sh already logged its id
    while IFS= read -r _ssl; do
      case "$_ssl" in
        '  WARN: ['*) _ssn=$((_ssn + 1)); _sss="${_ssl#*] }"; _sss="${_sss%% — *}"
                      _adv standard.shape-conform "$_sss"; printf '  ADVISORY [standard.shape-conform] %s\n' "${_ssl#  WARN: }" >&2 ;;
        '  FAIL: ['*) _sss="${_ssl#*] }"; LINT_REDLOG="$_ssred"; bad standard.shape-conform "${_ssl#  FAIL: }" "${_sss%% — *}"; LINT_REDLOG="" ;;
      esac
    done < "$_ssd/out"
    LINT_REDLOG="$_ssred"
    [ "$_ssn" -gt 0 ] || say "  $(grep -m1 'instances carry' "$_ssd/out" | sed -E 's/^ *(ok|note): //')"
  fi
fi
rm -rf "$_ssd"
}

# ── lint.comment-conform · the lines a branch adds pass bin/lint-comment.sh (warn, harbor#978) ──
# RUNS bin/lint-comment.sh and relays its findings as advisories, as N4 does (ids and modes are its and controls.tsv's).
# Exit 3, no base (a shallow clone), is an advisory, never silence or a failure; exit 2 or above 3 judged nothing.
rule_lint_comment_conform() {
rule "lint.comment-conform the lines a branch adds pass bin/lint-comment.sh: header line 2, comment runs (warn) (harbor#978)"
_lc="$ROOT/bin/lint-comment.sh"
if [ ! -f "$_lc" ]; then say "  skip: no bin/lint-comment.sh in this tree, so no added line was judged"; return 0; fi
_lco="${TMPDIR:-/tmp}/lc.$$"; _lcrc=0; _lcred="${LINT_REDLOG:-}"
LINT_REDLOG="$_lcred" sh "$_lc" --root "$ROOT" > /dev/null 2> "$_lco" || _lcrc=$?
if [ "$_lcrc" -eq 3 ]; then
  LINT_REDLOG=""   # "could not look" is not the rule going red
  _adv lint.comment-conform bin/lint-comment.sh; printf '  ADVISORY [lint.comment-conform] unchecked: no base to compare against (HARBOR_BASE, else origin/main), so no added line was judged\n' >&2
  LINT_REDLOG="$_lcred"
elif [ "$_lcrc" -gt 1 ]; then
  bad lint.comment-conform "bin/lint-comment.sh exited $_lcrc and judged nothing: $(grep -m1 'FAIL:' "$_lco" | sed 's/^ *FAIL: //')"
else
  _lcn=0; _lcf=0; LINT_REDLOG=""   # the relay records findings, not reds: lint-comment.sh already logged its ids
  while IFS= read -r _lcl; do
    case "$_lcl" in
      '  WARN: ['*) _lcn=$((_lcn + 1)); _lcs="${_lcl#*] }"; _lcs="${_lcs%% — *}"
                    _adv lint.comment-conform "$_lcs"; printf '  ADVISORY [lint.comment-conform] %s\n' "${_lcl#  WARN: }" >&2 ;;
      '  FAIL: ['*) _lcf=$((_lcf + 1)); _lcs="${_lcl#*] }"; LINT_REDLOG="$_lcred"; bad lint.comment-conform "${_lcl#  FAIL: }" "${_lcs%% — *}"; LINT_REDLOG="" ;;
    esac
  done < "$_lco"
  LINT_REDLOG="$_lcred"
  # exit 1 with no [rule] FAIL line is the engine dying (a missing lib exits 1), not a finding: never a pass
  if [ "$_lcrc" -eq 1 ] && [ "$_lcf" -eq 0 ]; then bad lint.comment-conform "bin/lint-comment.sh exited 1 with no finding and judged nothing: $(head -1 "$_lco")"; fi
  [ "$_lcn" -gt 0 ] || say "  $(grep -m1 'no added header' "$_lco" | sed -E 's/^ *(ok|note): //')"
fi
rm -f "$_lco"
}

# ── S1 · shell scripts: shebang, strict mode ────────────────────────────────
rule_S1() {
rule "posix.shebang-strict bin/*.sh use #!/usr/bin/env sh + strict mode (documented exceptions only)"
# EXEMPT, with reasons — encoded so the rule does not flag correct design:
#   guard-lib.sh   — SOURCED, so `set -eu` would leak into every caller
#   log-lib.sh     — SOURCED, the same reason (harbor#771)
#   install-lib.sh — SOURCED, the same reason (the install standard, harbor#765)
#   fs-lib.sh      — SOURCED, the same reason (harbor#618)
#   ci-runners-*-lib.sh — SOURCED by ci-runners.sh, which holds the strict mode (harbor#1060 split)
#   gate-lib.sh    — SOURCED, the same reason (harbor#1018)
#   stream-lib.sh  — SOURCED, the same reason (harbor#1181)
#   alert-lib.sh   — SOURCED, the same reason (harbor#618)
#   worklog-*.sh   — contractually fail-open ("every path exits 0"); -e would abort
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  head -1 "$f" | grep -q '^#!/usr/bin/env sh$' || bad posix.shebang-strict "wrong shebang: ${f#$ROOT/}"
  case "$b" in guard-lib.sh|log-lib.sh|install-lib.sh|fs-lib.sh|gate-lib.sh|stream-lib.sh|alert-lib.sh|worklog-push.sh|ci-runners-fleet-lib.sh|ci-runners-provision-lib.sh|ci-runners-github-lib.sh|ci-runners-watch-lib.sh) continue ;; esac
  grep -qE '^set -(eu|u|euo)' "$f" || bad posix.shebang-strict "no strict mode: ${f#$ROOT/}"
done
# EXTENSIONLESS EXECUTABLES ARE SCRIPTS TOO (2026-07-30). Every rule in this file
# globbed `bin/*.sh`, so `bin/gcx` and a second extensionless tool — a gcloud identity selector and
# a credentialed API client, the two most security-relevant tools added since the
# floor — were governed by nothing. S2 saw them (it globs bin/*) and passed them
# on the filename alone. Coverage that depends on a filename extension is coverage
# nobody chose.
#
# A NON-sh INTERPRETER IS ALLOWED, WITH A REASON IN THE HEADER. This is S1's own
# "documented exceptions only" applied where the exception is legitimate rather
# than grandfathered: a zsh tool needs `emulate -L zsh`, `setopt` and process
# substitution for its leak-free token path, and rewriting that in POSIX sh to
# satisfy a linter would trade a verified control for a green check.
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  case "$b" in *.sh|*.awk|*.md) continue ;; esac
  head -1 "$f" | grep -q '^#!' || continue          # data file, not a script
  if head -1 "$f" | grep -q '^#!/usr/bin/env sh$'; then
    grep -qE '^set -(eu|u|euo)' "$f" || bad posix.shebang-strict "no strict mode: ${f#$ROOT/}"
  else
    head -12 "$f" | grep -q 'INTERPRETER EXCEPTION:' \
      || bad posix.shebang-strict "non-sh shebang with no 'INTERPRETER EXCEPTION:' reason in the header: ${f#$ROOT/}"
  fi
done
}

# ── S2 · script filenames are kebab-case ────────────────────────────────────
rule_S2() {
rule "name.script-kebab-case bin/ filenames are kebab-case (standards/naming.md)"
for f in "$ROOT"/bin/*; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  # letters spelled out: under en_NZ, macOS sh lets [a-z] match capitals (harbor#1149)
  case "${b%.*}" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) bad name.script-kebab-case "not kebab-case: $b" ;;
  esac
done
}

# ── S3 · every script carries a ticket-traceable header ─────────────────────
rule_S3() {
rule "lint.script-ticket-header bin/ scripts name their ticket in the first 4 lines (B1/K1a/SEC-0/harbor#N)"
# Same extension blind spot as S1: a script is a script whether or not its name
# ends in .sh, and "which ticket asked for this" is the question a reader of an
# undocumented credentialed tool most needs answered.
for f in "$ROOT"/bin/*.sh "$ROOT"/bin/* $(_engines); do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in *.awk|*.md) continue ;; esac
  head -1 "$f" | grep -q '^#!' || continue
  head -4 "$f" | grep -qE '(harbor#[0-9]+|\b(B[1-6]|K1[ab]?|K2|G[12]|I1|J1|SEC-0|FLEET-0|SANDBOX|RECOVER|BOX-1|INSTALL|GOVERNANCE|CU-[1-9]|VIZ-1)\b)' \
    || bad lint.script-ticket-header "no ticket reference in header: ${f#$ROOT/}"
done
}

# ── S4 · every hand-invocable bin/ script answers --help (harbor#140) ───────
# THE DEFECT. Harbor had no way to learn what a script does except opening it:
# 27 of 55 non-exempt scripts answered nothing, and the failure is not aesthetic.
# A caller that cannot ask a tool what it does reads the tool's SOURCE, which is
# how a caller ends up depending on an internal that was never a contract — and
# a --help is a paragraph where a script can be 600 lines.
#
# IT IS ALSO A HAZARD, NOT ONLY A GAP, and that is what made it urgent. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past FIVE MINUTES before it was
# killed, because a script with no argument parser does not ignore --help — it
# does its work. Five of the twenty-seven were mutators. harbor#140 records the
# sibling shape: a script that READS STDIN on --help, which is a hang in CI or in
# a hook rather than a missing message.
#
# So the convention S4 enforces is not "has a usage() somewhere". It is a --help
# case, and the fix shipped with this rule puts it immediately after strict mode
# in every one of the 27, ahead of any work.
#
# ── THE EXEMPTIONS, WRITTEN DOWN RATHER THAN IMPLIED ───────────────────────
# harbor#140 asks for exactly this: an exemption is a decision, and a silent one
# is indistinguishable from an oversight.
#
#   *-test.sh      a suite is invoked by CI through CONTRACTS/suites.txt and by
#                  `harbor lint`, never typed at a prompt. Its name IS its
#                  surface, and 53 of them would make this rule noise.
#   the hook list  invoked by the HARNESS with a JSON payload on stdin, never by
#                  a person. A --help case on one is dead code at best; on a
#                  guard it is a branch in the security floor's hot path, which
#                  is ~790 invocations per suite run.
#   guard-lib.sh   sourced, not executed. It has no argv at all. log-lib.sh too
#                  (harbor#771): a --help arm there would answer the CALLER's $1.
#   replay-worker  spawned by replay.sh as a background pipeline, same argument.
#
# NOT EXEMPT, DELIBERATELY: the installers and the pinners. They are the scripts
# an operator runs by hand least often and therefore remembers least, and they
# are the ones where guessing at an invocation is expensive.
rule_S4() {
rule "lint.help-flag every hand-invocable bin/*.sh answers --help (harbor#140)"
_S4_HOOKS="floor-hook floor-observe context-resolve annotate-web prod-guard-ambient
worklog-push memory-harvest injection-rule replay-worker guard-bash
guard-egress guard-selfedit guard-integrity guard-cloud guard-destroy guard-lib
guard-deliverables guard-apiroute
guard-stop session-verdicts failure-capture failure-observe statusline ticket-note reply-shape log-lib install-lib fs-lib alert-lib ci-runners-fleet-lib ci-runners-provision-lib ci-runners-github-lib ci-runners-watch-lib gate-lib stream-lib session-react-lib"
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  _s4b="$(basename "$f" .sh)"
  case "$_s4b" in *-test) continue ;; esac
  case " $(printf '%s' "$_S4_HOOKS" | tr '\n' ' ') " in *" $_s4b "*) continue ;; esac
  # A `case` PATTERN, not a mention. `--help` appears in prose, in a printed
  # remedy and inside a usage() body all over this repo, so grepping for the word
  # would pass a script that only ever TALKS about the flag — the same
  # false-negative shape F9 exists for one layer up.
  #
  # COMMENTS ARE STRIPPED FIRST (harbor#579). The pattern alone still passed
  # bin/lint-conventions.sh, which did not answer the flag: its one match was a
  # comment inside rule CU1 quoting how bin/cu's dispatcher spells ITS help arms.
  # Whole-line comments go, and so does a trailing ` #…` — a `case` arm puts
  # `--help)` before any comment on its line, so cutting at a space-hash cannot
  # remove the arm, while `${#v}` and `$#` carry no space and survive.
  #
  # A MATCHER OVER SOURCE CANNOT CLOSE "DOES IT ANSWER THE FLAG". Only running
  # the script can, and running all of them is not free: #140 measured a sweep
  # past five minutes because a script without a parser does its work on
  # --help, and #144 owns the mutators among them. So this rule proves the arm
  # exists, and the running proof lives where it is cheap — tests/checks/lint-test.sh
  # runs this linter with --help and fails if it prints a report.
  # A tool on the install standard answers it through il_parse (bin/install-lib.sh), whose own arm is
  # held to this rule by the install-lib suite: the call AND the source line, or il_parse is undefined.
  _s4c="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$f")"
  if printf '%s\n' "$_s4c" | grep -qE '(^|[;&|[:space:]])il_parse[[:space:]]+"\$@"' \
     && printf '%s\n' "$_s4c" | grep -qE '(^|[;&|[:space:]])\.[[:space:]]+[^;]*install-lib\.sh'; then continue; fi
  printf '%s\n' "$_s4c" \
    | grep -qE '(^|[^a-zA-Z-])(-h\||-h\)|--help\)|--help\|)' \
    || bad lint.help-flag "answers no --help: ${f#"$ROOT"/}"
done
}

# ── S5 · the justfile names scripts that exist (harbor#140) ─────────────────
# S4 makes each script self-describing; this keeps the INDEX of them honest.
# harbor#140's own words: "without it the justfile rots the first time someone
# adds a script and does not add a recipe" — the rot that actually bites first is
# the other direction, a recipe still naming a script that was renamed or
# deleted, because `just --list` keeps printing it and reads as a working
# surface. One deterministic check, no judgement: every bin/ path a recipe names
# must resolve.
#
# NOT A COMPLETENESS CHECK. Requiring a recipe per script would make the justfile
# a second copy of bin/, which is the copy T2 exists to prevent, and it would
# make adding an internal helper a two-file change for no gain. The justfile is
# curated on purpose — what an operator TYPES, not what exists.
rule_S5() {
rule "lint.justfile-paths-resolve every bin/ path the justfile names resolves (harbor#140)"
_S5_JF="$ROOT/justfile"
if [ -f "$_S5_JF" ]; then
  # The parse is _justfile_bin_paths (shared with C8, harbor#474); S5 keeps only the verdict.
  _justfile_bin_paths > "${TMPDIR:-/tmp}/s5.$$"
  while IFS= read -r _s5p; do
    [ -n "$_s5p" ] || continue
    # `bin/{{ NAME }}-test.sh` is a parameterised recipe, not a path. It cannot
    # be resolved here and asserting on it would fail permanently, which is the
    # false positive that gets a rule deleted (§2.11).
    case "$_s5p" in *'{{'*|*'}}'*) continue ;; esac
    [ -e "$ROOT/$_s5p" ] || bad lint.justfile-paths-resolve "justfile names a path that does not exist: $_s5p"
  done < "${TMPDIR:-/tmp}/s5.$$"
  rm -f "${TMPDIR:-/tmp}/s5.$$"
fi
}

# ── S6 · a script that was executable stays executable (harbor#574) ───────
# NOTHING IN THIS REPO READ A FILE MODE. A one-line comment edit to
# bin/install-drift.sh went through a temp file, `mv` did not carry the mode,
# and 100755 -> 100644 rode 8/8 CI checks, 78 lint rules and four suites. Every
# caller ran it as `sh <path>`, so nothing exercised the bit, and the only place
# the change was ever visible was a `git diff` the operator happened to read.
#
# THE EXPECTATION IS DERIVED FROM HISTORY, NOT A LIST. bin/*.sh splits 95/71
# between the two modes, so "every script is 755" would go red on 71 files and
# be switched off in a day (§2.11), and a list of the 95 is a copy that drifts.
# What a branch must not do is LOSE a bit its base had: the base's own mode is
# the expectation, per file. A file that still opens with `#!` declares that it
# is run, so a lost bit on one is a defect; a file with no shebang is sourced,
# and dropping its bit is a deliberate change this rule leaves alone.
#
# THE BASE IS THE MERGE-BASE, NOT origin/main. Diffing against main's tip would
# read a bit main GAINED after this branch forked as a bit this branch LOST —
# a false positive on every stale branch. The diff runs to the WORKING TREE, so
# `just lint` sees an uncommitted `mv` too; in CI the tree is the commit.
rule_S6() {
rule "lint.exec-bit-kept a script that was executable on the base stays executable (harbor#574)"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  _s6r=""
  for _s6c in origin/main main; do
    git -C "$ROOT" rev-parse --verify -q "$_s6c" >/dev/null 2>&1 && { _s6r="$_s6c"; break; }
  done
  _s6mb=""
  [ -z "$_s6r" ] || _s6mb="$(git -C "$ROOT" merge-base "$_s6r" HEAD 2>/dev/null || true)"
  if [ -n "$_s6mb" ]; then
    _s6out="${TMPDIR:-/tmp}/s6.$$"
    # RENAMES ARE FOLLOWED (Codex on #693). With --no-renames a `git mv` that
    # also dropped the bit is a deletion plus an addition, and neither record
    # carries the 100755 -> 100644 pair, so the loss was invisible. -M pairs
    # them into one R record whose LAST field is the new path. An unstaged
    # plain `mv` is still invisible here — its destination is untracked until
    # it is added — and is seen the moment it is committed, which is the tree
    # CI and pre-push judge.
    git -C "$ROOT" diff --raw -M "$_s6mb" -- 2>/dev/null \
      | awk -F'\t' '$1 ~ /^:100755 100644 / { print $NF }' > "$_s6out" || true
    while IFS= read -r _s6p; do
      [ -n "$_s6p" ] && [ -f "$ROOT/$_s6p" ] || continue
      case "$(head -n 1 "$ROOT/$_s6p" 2>/dev/null)" in '#!'*) ;; *) continue ;; esac
      bad lint.exec-bit-kept "lost its executable bit since the merge-base with $_s6r (100755 -> 100644): $_s6p" "$_s6p"
    done < "$_s6out"
    rm -f "$_s6out"
  else
    # NO BASE IS NOT A CLEAN RESULT — C2's reason 1, one rule over.
    _adv lint.exec-bit-kept no-base; printf '  ADVISORY [lint.exec-bit-kept] no origin/main or main to compare against — NO file mode was inspected\n' >&2
  fi
fi
}

# ── F1 · the floor's kill-switch convention (FLOOR.md) ──────────────────────
rule_F1() {
rule "admission.kill-switch-first every wired decider's first live line is the HELM_DISABLE_FLOOR check, or it is listed exempt with a reason (harbor#954)"
# THE SET IS bin/decider-set.sh's, derived from the wiring floor-install writes (harbor#1003). It used to be
# `bin/guard-*.sh` + annotate-web.sh: 10 files that missed inject-hook.sh and prod-guard-ambient.sh, two
# wired deciders that read no switch. floor-test, floor-verify and B6's list are diffed against it.
_f1set="$ROOT/bin/decider-set.sh"
[ -f "$_f1set" ] || { bad admission.kill-switch-first "bin/decider-set.sh is missing, so the decider set cannot be derived"; return 0; }
_f1out="$(sh "$_f1set" --check 2>&1 || :)"
while IFS= read -r _l; do
  case "$_l" in *"FAIL: "*) bad admission.kill-switch-first "${_l#*FAIL: }" ;; esac
done <<F1EOF
$_f1out
F1EOF
for _s in $(sh "$_f1set" --switch); do
  f="$ROOT/bin/$_s"
  [ -f "$f" ] || { bad admission.kill-switch-first "wired decider is not in bin/: $_s"; continue; }
  line="$(grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | grep -vE '^#!' | head -1)"
  case "$line" in
    *HELM_DISABLE_FLOOR*) ;;
    *) bad admission.kill-switch-first "kill-switch is not the first live line: bin/$_s" ;;
  esac
done
# the second switch: a decider declared to record under shadow must reach floor_block or read the switch
for _s in $(sh "$_f1set" --records); do
  grep -qE 'floor_block|HELM_FLOOR_SHADOW' "$ROOT/bin/$_s" 2>/dev/null \
    || bad admission.kill-switch-first "bin/$_s is declared to record under HELM_FLOOR_SHADOW and reaches neither floor_block nor the switch"
done
}

# ── admission.wired-registered · every wired hook script is a control's engine (harbor#1272) ──
# A hook that runs in every session and has no controls.tsv row has no mode, owner or off switch a person can
# read, and the census never sees a guard that answers in JSON instead of floor_block. The set is F1's.
rule_admission_wired_registered() {
rule "admission.wired-registered every wired hook script (bin/decider-set.sh) is the engine of a standards/naming/controls.tsv row (harbor#1272) (advisory)"
_wrset="$ROOT/bin/decider-set.sh"; _wrc="$ROOT/standards/naming/controls.tsv"
[ -f "$_wrset" ] && [ -f "$_wrc" ] || { bad admission.wired-registered "bin/decider-set.sh or standards/naming/controls.tsv is missing, so the wired set cannot be checked"; return 0; }
_wrl="$(sh "$_wrset" 2>/dev/null | cut -f1)"
[ -n "$_wrl" ] || { bad admission.wired-registered "bin/decider-set.sh listed no wired script, so nothing was checked"; return 0; }
for _s in $_wrl; do
  _wre="$(_payload_src "$_s")"; _wre="${_wre#"$ROOT"/}"  # a hook engine's row names its folder's file (D-88)
  awk -F'\t' -v e="$_wre" '/^#/ { next } $4 == e { f = 1; exit } END { exit !f }' "$_wrc" \
    || { _adv admission.wired-registered "$_wre"; printf '  ADVISORY [admission.wired-registered] %s is wired as a hook and no standards/naming/controls.tsv row names it as its engine\n' "$_wre" >&2; }
done
}

# ── F5 · every floor_block call site carries a <rule>.<shape> id ───────────
# Without one the record logs `unclassified` and the block is invisible to
# `observe-report.sh` — a rule that fires and cannot be counted, which is the
# exact condition harbor#41 exists to end. Silent, so it needs a mechanism.
rule_F5() {
rule "admission.block-id every floor_block passes a <rule>.<shape> id (harbor#41)"
_f5bad=0; _f5tot=0
# THE SCOPE IS EVERY GUARD, NOT THREE NAMED ONES (harbor#588). The title says
# "every floor_block", and a hand list of three files is a copy of a fact the
# tree already holds: a fourth guard that called floor_block with no id would
# have passed. The set is now bin/guard-*.sh — guard-lib.sh defines the
# function and guard-cloud.sh / guard-destroy.sh decide through
# permissionDecision, so today they contribute zero call sites, not a gap.
#
# WHOLE-LINE COMMENTS ARE DROPPED FIRST, because widening the scope brought in
# prose: guard-cloud.sh:66, guard-destroy.sh:48 and three lines of guard-lib.sh
# say "floor_block" in a comment, and #588 first counted those five as
# unchecked CALL SITES. They are sentences. Counted as calls they would have
# made this rule fire on documentation — the false positive §2.11 names.
for f in "$ROOT"/bin/guard-*.sh; do
  [ -f "$f" ] || continue
  # JOIN backslash continuations first, then test. Counting quotes line-by-line
  # was the first cut and it undercounted by exactly the 3 calls whose message
  # wraps — i.e. it passed the sites most likely to be edited carelessly.
  _j="$(sed '/^[[:space:]]*#/d' "$f" | awk '{ line=$0
               while (line ~ /\\$/) { sub(/\\$/,"",line); if ((getline nxt) <= 0) break; sub(/^[[:space:]]+/,"",nxt); line = line " " nxt }
               print line }')"
  _n="$(printf '%s\n' "$_j" | grep -cE '(^|[^a-z_])floor_block[[:space:]]' || true)"
  _g="$(printf '%s\n' "$_j" | grep -E '(^|[^a-z_])floor_block[[:space:]]' \
        | grep -cE '"[[:space:]]+[a-z0-9-]+\.[a-z]+[[:space:]]*;?[[:space:]]*\}?[[:space:]]*$' || true)"
  _f5tot=$((_f5tot + _n)); _f5bad=$((_f5bad + _n - _g))
done
[ "$_f5bad" -eq 0 ] || bad admission.block-id "$_f5bad of $_f5tot floor_block call site(s) carry no rule id"
}

# ── F16 · a refusal prints its narrowest true remedy, not the kill-switch ──
# floor_block printed `HELM_DISABLE_FLOOR=1 claude` under every one of ~110
# rules: turn all of them off to get past one (harbor#482). The narrow remedy
# for one refused call is a `!` command, which is not a tool call. The blanket
# hatch is the TRUE remedy in exactly two places, named here with why:
#   guard-integrity.sh  the SessionStart gate refuses the SESSION; relaunching is the only door in
#   floor-hook.sh       fail-closed: no guard can evaluate ANY call, so a per-call remedy is none
# THE SCOPE IS DERIVED: every bin/guard-*.sh plus every file floor-install.sh's
# GUARDS line installs, so a new floor file is in scope the day it is pinned.
rule_F16() {
rule "admission.kill-switch-remedy no floor guard prints the kill-switch as its remedy, except where it is the true one (harbor#482)"
_f16g="$(sed -n "s/^GUARDS='\(.*\)'\$/\1/p" "$ROOT/bin/floor-install.sh" 2>/dev/null | head -1)"
[ -n "$_f16g" ] || { bad admission.kill-switch-remedy "bin/floor-install.sh has no GUARDS='…' line, so the floor's file set could not be derived"; return 0; }
_f16seen=" "
for f in "$ROOT"/bin/guard-*.sh $(for _f16b in $_f16g; do printf '%s ' "$ROOT/bin/$_f16b"; done); do
  [ -f "$f" ] || continue
  _f16b="${f##*/}"
  case "$_f16seen" in *" $_f16b "*) continue ;; esac
  _f16seen="$_f16seen$_f16b "
  case "$_f16b" in guard-integrity.sh|floor-hook.sh) continue ;; esac
  _f16n="$(grep -vE '^[[:space:]]*#' "$f" 2>/dev/null | grep -c 'HELM_DISABLE_FLOOR=1' || true)"
  [ "${_f16n:-0}" -eq 0 ] || bad admission.kill-switch-remedy "bin/$_f16b prints the kill-switch as a remedy on $_f16n code line(s); print the narrowest true one (a \`!\` command for one call)"
done
}

# ── G1 · large files carry their reason, and new ones stay small ───────────
# See DOCTRINE/modularity.md. The point is NOT to forbid large files — the floor
# guards are deliberately monolithic (F1 needs the kill-switch as the first live
# line; B6 hash-pins each file; per-rule files would add a fork per rule, and
# DE-09 records that a fork regression turned SessionStart into a fail-OPEN
# bypass). The point is that the permission must be ARGUED in the file's own
# header, so it cannot spread by imitation.
# 300 lines: above p75 (176) and below p90 (425) of bin/*.sh, so it flags the
# outliers and nothing routine. ADVISORY — a size threshold is a smell, and
# promoting a smell to a build failure is how a linter gets routed around.
rule_G1() {
rule "lint.long-file-reason files over 300 lines name their exemption reason in the header (advisory)"
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  _tot="$(wc -l < "$f" | tr -d ' ')"
  # NON-COMMENT LINES, because the rule was penalising the header it exists to
  # require. It counted every line, so a file that answered G1 properly — a long
  # WHY block above the code, which DOCTRINE/modularity.md and this whole repo
  # ask for — crossed the threshold BECAUSE it was well documented. replay.sh and
  # replay-corpus.sh were advised on for months while carrying exactly the
  # explanation the rule wanted; measured 2026-08-01, they are 375 and 328 total
  # lines but 207 and 183 lines of actual code.
  #
  # A rule whose easiest fix is "delete the comments" is teaching the wrong
  # lesson. The exemption header still works and is still the answer for a file
  # that is genuinely long; this just stops the counter mistaking prose for size.
  _n="$(grep -cvE '^[[:space:]]*(#|$)' "$f" 2>/dev/null || echo 0)"
  [ "$_n" -gt 300 ] || continue
  # The reason must appear in the header block, not anywhere in the file: a
  # justification buried at line 800 is not one the next reader will find.
  #
  # THE HEADER IS THE LEADING COMMENT BLOCK, NOT A FIXED 40 LINES (harbor#578).
  # `head -40` repeated the defect the counter above already paid for, one line
  # down: bin/lint-test.sh (now tests/checks/) named its exemption at line 54 of a long WHY block, so
  # G1 advised on it BECAUSE its header was thorough. The window is now derived
  # from the file's own shape — every line from the top until the first line
  # that is neither a comment nor blank — so a long header is read whole and a
  # reason written after the first line of code still does not count.
  #
  # ONE LINE OF CODE BELONGS TO THE PREAMBLE, AND ANOTHER RULE PUT IT THERE. F1
  # requires a guard's kill switch to be its FIRST live line, so bin/guard-bash.sh
  # opens with it at line 2 and argues its size at line 16. The first cut of this
  # window stopped at line 2 and advised on guard-bash.sh — a rule obeying F1 was
  # penalised by G1. So the kill-switch line is skipped when it sits in the first
  # three lines, which is exactly where F1 puts it, and nowhere else.
  if awk 'NR <= 3 && /HELM_DISABLE_FLOOR/ { next }
          /^[[:space:]]*(#|$)/ { print; next } { exit }' "$f" \
       | grep -qiE 'deliberately (one file|monolithic)|single file by design|DOCTRINE/modularity'; then
    :
  else
    # ADVISORY, printed like X2/X3 — NOT `bad`. DOCTRINE/modularity.md says in
    # so many words that "promoting a smell to a build failure is how a linter
    # becomes something people route around", and the first version of this rule
    # contradicted the doctrine it was written to enforce. It caught that by
    # firing on bin/replay.sh at 311 lines, which is the rule working: a file
    # crossed the line as it grew, and the right response is a note to carry into
    # the next PLANNING session, not a mid-task split under a full context window.
    _adv lint.long-file-reason "${f#$ROOT/}"; printf "  ADVISORY [lint.long-file-reason] %s is %s lines of code (%s total) and its header does not say why (DOCTRINE/modularity.md)\n" "${f#$ROOT/}" "$_n" "$_tot"
  fi
done
}

# ── F4 · a test must never point a guard at the operator's LIVE config ─────
# A guard invoked without CLAUDE_CONFIG_DIR resolves its config dir to
# $HOME/.claude. Three invocations in floor-test.sh had done exactly that since
# they were written; it stayed harmless only because nothing in the floor wrote
# anything, and OBSERVE-1's mutation pass turned it into a real escape into the
# operator's MEMORY tree within minutes (DEAD-ENDS DE-13).
rule_F4() {
rule "test.config-dir-isolated no test spawns a guard without CLAUDE_CONFIG_DIR (its verdict would depend on the operator's live config)"
# THE RULE'S OWN JUSTIFICATION MOVED, and the message moved with it. It used to
# say "would hit live ~/.claude", which harbor#343 made false: the ledger sink now
# follows the WRITER's location, not the caller's environment. Measured after
# rebasing onto it — both offending suites, no CLAUDE_CONFIG_DIR, ZERO new records
# in the live ledger. A matcher fixed while its stated purpose is stale is how a
# rule turns into documentation, so the purpose is restated rather than inherited.
#
# What is still true: floor_config_dir() reads CLAUDE_CONFIG_DIR, and guard-bash
# and guard-selfedit build CFG_RE from it. A suite spawning a guard without it has
# its SURFACE rules evaluated against the operator's real ~/.claude, so the
# verdict depends on the machine rather than on the fixture. Hermeticity, not
# contamination — a weaker consequence than the old one, and a real one.
#
# harbor#348. This rule was LIVE but blind to the one shape that actually occurs,
# and it checked 4 of 42 suites. Four defects, and fixing any one alone leaves the
# escape hidden:
#
#   1 · THE FILE LIST WAS HAND-WRITTEN — floor-test, normalize-test, marker-test,
#       stop-guard-test. The destroy and cloud guard suites were not on
#       it, and both fire a guard with no CLAUDE_CONFIG_DIR. Now derived from
#       bin/*-test.sh, so a new suite there is covered BY DEFAULT. Suites under tests/
#       spawn guards through tests/lib/guard.sh, whose t_init exports a sandbox config dir.
#
#   2 · STAGE 2 REQUIRED THE GUARD FILENAME ON THE SPAWN LINE, and every suite
#       assigns the path once (`GUARD="$DIR/guard-destroy.sh"`) then spawns through
#       the variable. The filename line has no `sh "$`, the spawn line has no
#       filename, so the two conditions never co-occurred. Measured: with the
#       original matcher, a PLANTED literal-path escape fires and a planted
#       variable-form escape does not. Variables assigned a guard path are now
#       collected and their spawns matched too.
#
#   3 · COMMENTS WERE MATCHED. The awk printed comment lines unjoined to close a
#       continuation exploit (a `#` line ending in `\` widened the exemption over a
#       whole block) but never EXCLUDED them, so prose quoting the shape tripped the
#       rule. They are now dropped outright — which closes the exploit too, since a
#       dropped line cannot join anything.
#
#   4 · THE SPAWN TARGETS ARE DERIVED FROM THE GUARDS THAT EXIST, not from a
#       `guard-[a-z]+\.sh` pattern. recover-test.sh spawns `sh "$STUB"` where
#       STUB="$SB/guard-stub.sh" — a heredoc-written fake whose whole body is
#       `exit 2`, which sources no guard-lib and cannot write a record. A pattern
#       match calls that an escape; asking "is this one of OUR guards" does not,
#       with no allowlist and no stub-detection heuristic to rot. A guard added to
#       bin/ later is picked up automatically.
# NO NAMED EXEMPTION LEFT. lint-test.sh held F4's own planted escapes as strings and
# was exempt by name; it moved to tests/checks/ (harbor#667), outside this scan.
_f4_names=""
for _g in "$ROOT"/bin/guard-*.sh; do
  [ -f "$_g" ] || continue
  _f4_names="$_f4_names $(basename "$_g")"
done
for _g in floor-hook.sh floor-observe.sh annotate-web.sh context-resolve.sh; do
  [ -f "$ROOT/bin/$_g" ] && _f4_names="$_f4_names $_g"
done
# One alternation, built from the names above. Dots escaped so `guard-bash.sh`
# cannot match `guard-bashXsh`.
_f4_alt=""
for _n in $_f4_names; do
  _e="$(printf '%s' "$_n" | sed 's/\./\\./g')"
  if [ -z "$_f4_alt" ]; then _f4_alt="$_e"; else _f4_alt="$_f4_alt|$_e"; fi
done
if [ -n "$_f4_alt" ]; then
  for f in "$ROOT"/bin/*-test.sh; do
    [ -f "$f" ] || continue
    # Comment lines are DROPPED, not printed — see defect 3.
    _j="$(awk '{ line=$0; n=NR
                 if (line ~ /^[[:space:]]*#/) { next }
                 while (line ~ /\\$/) { sub(/\\$/,"",line); if ((getline nxt) <= 0) break; sub(/^[[:space:]]+/,"",nxt); line = line " " nxt }
                 print n ":" line }' "$f")"
    # (a) the literal form — a guard filename on the spawn line. This half always
    #     worked; a planted literal escape fires against it today.
    _bad="$(printf '%s\n' "$_j" \
            | grep -E '(^|[^[:alnum:]_.-])sh[[:space:]]+"\$' \
            | grep -E "($_f4_alt)" \
            | grep -v 'CLAUDE_CONFIG_DIR' | cut -d: -f1 | tr '\n' ' ')"
    # (b) the variable form — collect NAMEs assigned one of OUR guard paths, then
    #     match `sh "$NAME"`. Two greps rather than one dynamic alternation, so a
    #     name containing a regex metacharacter cannot alter the pattern.
    _vars="$(printf '%s\n' "$_j" \
             | grep -E "^[0-9]+:[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*($_f4_alt)" \
             | sed -n 's/^[0-9]*:[[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' | sort -u)"
    for _v in $_vars; do
      _vb="$(printf '%s\n' "$_j" \
             | grep -E "(^|[^[:alnum:]_.-])sh[[:space:]]+\"\\\$$_v\"" \
             | grep -v 'CLAUDE_CONFIG_DIR' | cut -d: -f1 | tr '\n' ' ')"
      [ -z "$_vb" ] || _bad="$_bad$_vb"
    done
    [ -z "$_bad" ] || bad test.config-dir-isolated "${f#$ROOT/}: guard spawned with no CLAUDE_CONFIG_DIR — surface rules resolve against the live config — at line(s) $_bad"
  done
fi
}

# ── F2 · no mid-pattern ^ inside an alternation (BSD grep ignores it) ───────
# This silently disabled live rules while they passed under GNU grep by hand.
rule_F2() {
rule "posix.grep-alternation no mid-pattern (^| alternation — BSD grep never matches that branch"
# ANY TOKEN BEFORE THE GROUP, NOT ONLY `.*` (harbor#588). The pattern used to be
# `\.\*\(\^\|`, so `[a-z]+(^|foo)` — the same caret in the same place — passed.
# The group is mid-pattern whenever the character before its `(` is part of the
# pattern: anything but a quote or blank (the pattern's own start), `/` (an awk
# regex literal's start — guard-stop.sh:187 opens `/(^|\/)bin\/…/`), `|` (the
# start of an alternative) or `(` (the start of an enclosing group). A RUN of
# opening parens is skipped to the character before it (Codex on #693), so
# `a((^|b))` is still mid-pattern. NOT HANDLED: `a(b|(^|c))`, where the `|` is
# inside a group a token already consumed — telling that apart needs a parser,
# not a character class. Comment
# lines are dropped first: guard-bash.sh:2225 quotes `(^|` in prose, and the
# first run of the widened pattern flagged both of those — neither is a defect.
#
# THE BSD HALF DID NOT REPRODUCE ON 2026-09-24. /usr/bin/grep here is
# `2.6.0-FreeBSD` on macOS 26.6.2, and `.*(^|q)a` matches `ab` under it, with
# and without -i. The rule still earns its line: after a token that CONSUMES
# a character, as in `[a-z]+(^|`, the caret can never match in any grep, so the
# branch is dead code wherever it runs, whichever grep runs it.
for f in "$ROOT"/bin/guard-*.sh "$ROOT"/bin/floor-*.sh; do
  [ -f "$f" ] || continue
  sed '/^[[:space:]]*#/d' "$f" 2>/dev/null | grep -qE "[^'\"[:space:]/|(]\\(+\\^\\|" \
    && bad posix.grep-alternation "mid-pattern caret: ${f#$ROOT/}"
done
}

# ── F11 · `stat -f` is a DIALECT, and its failing branch is NOT silent ──────
rule_F11() {
rule "posix.stat-fallback no stat -f/-c fallback captured in one expression (GNU prints, then fails)"
# THE MECHANISM BEHIND A FIX THAT DID NOT PROPAGATE. `stat -f` means "format" to
# BSD stat and "file system status" to GNU stat, so on Linux the first call PRINTS
# a block of filesystem fields to stdout and THEN fails — and `a || b` evaluated
# in ONE expression appends b's answer to that garbage. bin/pulse.sh:93 states the
# rule ("VALIDATE THE OUTPUT, NEVER THE EXIT CODE") after a review reported it
# there, and bin/skills-collide.sh followed it. FOUR other live call sites never
# did, and were found on 2026-09-06 only because a Linux box happened to run the
# suites: `harbor fresh` aborted part-way through its own report, skills-install
# could not install ANY skill, wf-progress lost the liveness verdict it exists to
# give, and save-log-token-test went red for the box rather than the code.
#
# Three hand-propagations and a miss is the argument for this rule existing. A
# rule with no mechanism is a wish (DOCTRINE/doc-truth.md), and until now this one
# was a comment in one file hoping to be read by the author of the next.
#
# THE DISCRIMINATOR IS THE INTERVENING ASSIGNMENT, NOT THE PRESENCE OF `||`.
# bin/fleet-glyph.sh:588 and :757 are CORRECT and must stay green:
# `if mt="$(stat -f …)" || mt="$(stat -c …)"` runs two SEPARATE captures and the
# second overwrites the first, so the garbage never survives the line. The broken
# shape has no `="$(` between the two calls, which is precisely what lets one
# capture hold both answers. Checked in that order, so a whole-line grep — which
# matches `_m="$(stat -f …` at the START of the broken line too — cannot be used.
#
# tests/checks/reference-check-test.sh IS EXEMPT BY PATH, WITH THE REASON. It carries the
# broken idiom as harbor#226's own probe FIXTURE, and a suite proving the trap is
# detected must be able to write the trap down. Named rather than globbed to
# `*-test.sh`, because bin/save-log-token-test.sh:74 (now tests/hooks/) held a REAL instance of this
# defect and a blanket suite exclusion would have gone on missing it. If a second
# file ever needs the fixture, add it here with its own reason — do not widen this
# to a glob.
_F11P="${TMPDIR:-/tmp}/.helm-f11.$$"
cat > "$_F11P" <<'F11AWK'
{
  if ($0 ~ /^[[:space:]]*#/) next
  i = index($0, "stat -f"); if (i == 0) next
  rest = substr($0, i + 7)
  j = index(rest, "stat -c"); if (j == 0) next
  if (index(substr(rest, 1, j - 1), "=\"$(") > 0) next
  print FILENAME ":" FNR
}
F11AWK
_f11=''
# tests/*/*.sh: a suite moved out of bin/ stays scanned, so the exemption stays one file (harbor#667).
for f in "$ROOT"/bin/*.sh "$ROOT"/hooks/* "$ROOT"/hooks/*/*.sh "$ROOT"/worklog/* "$ROOT"/skills/*/bin/*.sh "$ROOT"/tests/*/*.sh; do
  [ -f "$f" ] || continue
  case "${f#"$ROOT"/}" in tests/checks/reference-check-test.sh) continue ;; esac
  _f11hit="$(awk -f "$_F11P" "$f" 2>/dev/null || true)"
  [ -z "$_f11hit" ] || _f11="$_f11 ${_f11hit#$ROOT/}"
done
rm -f "$_F11P"
# THE PROBE MUST NOT BECOME THE FINDING (harbor#226, and it happened here on the
# first run). This message named BOTH spellings in one line, so the rule reported
# its own text at bin/lint-conventions.sh:554. It now names the first only; the
# comment block above carries the full explanation and is skipped as comment.
[ -z "$_f11" ] || bad posix.stat-fallback "a BSD-first stat fallback captured in one expression — on GNU the first spelling PRINTS filesystem fields and THEN fails, so the captured value is garbage plus the answer. Call bin/fs-lib.sh (fs_mtime, fs_size, fs_mode, fs_uid), or validate the output and never the exit code, at:$_f11"
}

# ── F12 · no POSIX-compatibility violations under `sh` (shellcheck SC3xxx) ──
rule_F12() {
rule "posix.shellcheck every script is POSIX under sh — no shellcheck SC3xxx (advisory when shellcheck is absent)"
# WHY ONLY SC3xxx, AND NOT THE WHOLE TOOL. Measured 2026-09-06 over 166 scripts:
# at its defaults it reports 3,132 findings here, and ~97% of them are this
# repo's house style rather than defects — 1,969 SC2015 (`test && ok || bad`, the
# idiom every suite is written in), 467 SC2016 (single-quoted awk and ERE
# programs), 169 SC1007 (`CDPATH= cd`), and SC1087 on `"$E[2m"` and `"$GH_ALIAS_SET[^;&|]*"`,
# where a POSIX `$VAR` followed by a literal `[` is read as a bash array. Gating
# on all of that would be a rule nobody could keep green, i.e. a rule that gets
# switched off (§2.11). Gating on nothing was the status quo, and it cost a suite.
#
# SC3xxx IS THE SUBSET THAT PAYS. It is exactly "this construct is not in POSIX
# sh", which is the class the GNU/BSD runner split exists to catch and the class
# a `#!/bin/zsh` tool is grandfathered out of by being honestly `#!/bin/zsh`. Measured on
# the same 166 files: SC3xxx findings = ONE (`test '>'` in floor-install.sh,
# removed in the same pass), so this rule starts from a baseline of ZERO. A
# ratchet at zero is enforceable; one at "1, with an exemption" is the shape that
# grows.
#
# IT WOULD HAVE CAUGHT A REAL DEFECT, which is the only argument that matters.
# bin/normalize-test.sh (now tests/floor/) carried one `$'…'`; dash could not parse the file, the
# suite reported ZERO assertions on every dash box while STATUS.md claimed 173,
# and status-gen wrote that zero into the file. shellcheck flags it as SC3003 at
# exactly that line. Nothing in shellcheck's output catches the `stat -f` dialect
# (F11's class) — checked, not assumed — so these two rules are complements and
# neither subsumes the other.
#
# ADVISORY WHEN THE TOOL IS ABSENT, and LOUD about it, in the idiom X7 already
# uses: a rule that silently passes because its instrument is missing is worse
# than no rule. bin/doctor.sh probes shellcheck as `degraded` for the same reason.
# This becomes a real gate on the runner the moment governance.yml's preflight
# installs it, which is a workflow change and the operator's to make.
if command -v shellcheck >/dev/null 2>&1; then
  _shellcheck_raw
  _F12RAW="$_SC_RAW"
  _F12="$(printf '%s\n' "$_F12RAW" | grep -E 'SC3[0-9]{3}' || true)"
  # A PARSE ABORT IS A SKIPPED FILE, AND SKIPPED READS AS CLEAN. SC1072/SC1073 mean
  # the tool gave up partway, so the SC3xxx grep above returns empty for every line
  # after that point and F12 passes on a file it never finished reading. That is the
  # false-negative shape from No.2.10 one layer down: the instrument, not the guard.
  # Baseline on 2026-09-16 over all 180 files in scope: ONE, in this file, fixed in
  # the same commit -- so this arm starts from zero and any hit is a regression.
  _F12A="$(printf '%s\n' "$_F12RAW" | grep -E 'SC(1072|1073)' || true)"
  if [ -n "$_F12A" ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      bad posix.shellcheck "shellcheck ABORTED here, so every check after this line was SKIPPED and F12 cannot speak for the rest of the file (a comment beginning with the tool's name is read as a directive): ${_l#"$ROOT"/}"
    done <<F12AEOF
$_F12A
F12AEOF
  fi
  # HEREDOC, NOT A PIPE, and this is the same trap F10 two rules down is written
  # around: `printf | while read` puts the loop in a SUBSHELL, so every `bad` call
  # inside it increments a FAIL that dies with that subshell, and the linter exits
  # 0 while printing violations. Caught while writing this rule — the third time
  # in this pass that running a thing beat reasoning about it.
  if [ -n "$_F12" ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      bad posix.shellcheck "not POSIX under sh: ${_l#"$ROOT"/}"
    done <<F12EOF
$_F12
F12EOF
  fi
  # SC3013 LEFT THE TOOL IN 0.11, SO ITS CLASS IS READ HERE (harbor#811). POSIX.1-2024
  # adopted test's -nt/-ot/-ef and 0.11 stopped reporting them; an older runner still
  # does, so F12 was green on the Mac and red on ubuntu-latest for the same line.
  _sc_scope
  _F12T="$(awk '/^[ \t]*#/ { next }
    /(^|[^A-Za-z0-9_-])(\[|test)[ \t][^];|&]*[ \t]-(nt|ot|ef)([ \t]|$)/ { print FILENAME ":" FNR }' $_sc_files 2>/dev/null || true)"
  if [ -n "$_F12T" ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      bad posix.shellcheck "not POSIX under sh: test's mtime/identity operator (pre-2024 POSIX; use find -newer): ${_l#"$ROOT"/}"
    done <<F12TEOF
$_F12T
F12TEOF
  fi
else
  _adv posix.shellcheck shellcheck-absent; printf '  ADVISORY [posix.shellcheck] shellcheck is not installed — this rule verified NOTHING.\n' >&2
  printf '           brew install shellcheck (or apt install shellcheck) to arm it.\n' >&2
fi
}

# ── F13 · an apostrophe inside a single-quoted program (harbor#299) ─────────
# ONE APOSTROPHE IN A COMMENT INSIDE A SINGLE-QUOTED awk OR jq PROGRAM CLOSES THE
# QUOTE, and the shell then parses the rest of the program as shell code. harbor#299
# measured it twice in bin/fleet-glyph.sh on 2026-08-24 — the second time inside a
# comment WARNING about the first — and it happened again in THIS file on 2026-09-16,
# from the word "item's" in the comment above T12's awk program.
#
# harbor#299 SAYS `sh -n` CATCHES IT SO IT CANNOT REACH MAIN. That holds for an ODD
# number of apostrophes and fails for an EVEN number, which is the case worth
# gating. Measured 2026-09-16 on a two-apostrophe fixture:
#
#   sh -n                   rc=0   passes
#   the linter at -S error  rc=0   passes — SC1011 is a WARNING, not an error
#   running it              prints NOTHING where it should print field1=a
#
# The quoting re-balances, every gate in this repo stays green, and the program
# silently receives different text. THAT one reaches main.
#
# SHELLCHECK ALREADY HAS THE PARSER, WHICH IS WHY THIS IS NOT A NEW ONE. harbor#299
# proposes a rule that finds the blocks itself. Three attempts at that here measured
# 81% false positives, then 462 hits, then 12 — each an artefact of an incomplete
# shell model: inline closers, then unquoted `#` comments, then heredoc bodies, whose
# contents are not shell at all. A rule built on a model that wrong is the false
# positive §2.11 forbids. SC1011 comes from a real parser, it points at the
# APOSTROPHE with a line and column rather than at an EOF 150 lines later — which is
# harbor#299's actual complaint — and its baseline across all 180 files in scope on
# 2026-09-16 is ZERO. A ratchet at zero is enforceable.
#
# IT SHARES F12's SHELLCHECK RUN ON PURPOSE. Re-running the tool over ~180 files for
# one more pattern would roughly double the slowest rule in this file. It shares it
# through `_shellcheck_raw` at the top, which computes once and memoises — NOT, as
# it did until harbor#537, by reading a variable F12 happened to have set earlier in
# the same pass. That version was correct only because every rule always ran, in
# order: `--only F13` met an unset `$_F12RAW` the first time one rule ran alone.
#
# DECLARED AT COLUMN 0, AND THAT IS NOT COSMETIC. bin/status-gen.sh counts rules with
# `grep -c '^rule "'` — anchored, no leading space — because harbor#117 made it the
# single answer to "how many lint rules are there". The first cut of this rule sat
# INSIDE F12's if/else and was declared in both branches, so the repo briefly held
# three answers: 77 in STATUS.md, which cannot see an indented declaration at all,
# 78 at runtime, and 79 to a static scan allowing indent. T1 stayed GREEN throughout,
# because status-gen's number never moved. An indented rule is an invisible rule.
rule_F13() {
rule "posix.awk-apostrophe no apostrophe inside a single-quoted awk/jq program — it closes the quote (harbor#299)"
if command -v shellcheck >/dev/null 2>&1; then
  _shellcheck_raw
  _F13="$(printf '%s\n' "$_SC_RAW" | grep -E 'SC1011' || true)"
  if [ -n "$_F13" ]; then
    while IFS= read -r _l; do
      [ -n "$_l" ] || continue
      bad posix.awk-apostrophe "an apostrophe closes the single-quoted program here — the shell parses what follows as shell, and with an EVEN number of them every other gate stays green while the program is silently wrong: ${_l#"$ROOT"/}"
    done <<F13EOF
$_F13
F13EOF
  fi
else
  # It rides F12's run, so it verified nothing either, and says so rather than let a
  # silent skip read as green — the X1 defect found earlier the same day.
  _adv posix.awk-apostrophe shellcheck-absent; printf '  ADVISORY [posix.awk-apostrophe] shellcheck is not installed — this rule verified NOTHING.\n' >&2
fi
}

# ── F10 · the settings.json baseline projection is ONE shape ────────────────
rule_F10() {
rule "deploy.baseline-projection every writer and reader of .sec0-baseline uses the SAME jq projection (harbor#221)"
# THE MECHANISM BEHIND harbor#221's FIX. The projection that decides what B6
# watches in settings.json is written out by sec0-harden.sh and floor-deny.sh
# and read back by guard-integrity.sh — seven literal copies of one jq program
# across three files. A fact copied seven times drifts silently, and here the
# drift is not cosmetic: if a WRITER pins one shape and the GUARD computes
# another, the hashes never match, B6 reports drift at every SessionStart
# forever, and the operator learns to scroll past the one gate that would have
# told them their deny list had been emptied. §2.11, with the whole file behind
# it. A rule with no mechanism is a wish (DOCTRINE/doc-truth.md), so this is the
# mechanism: they are compared as strings, and any disagreement is a violation.
_f10n=0; _f10ref=""
for f in "$ROOT"/bin/sec0-harden.sh "$ROOT"/bin/floor-deny.sh "$ROOT"/bin/guard-integrity.sh; do
  [ -f "$f" ] || continue
  # Only the FULL baseline projection, which is the one keyed on `perms:`. The
  # narrower `{deny, locks}` teeth projection is a different question with a
  # different sidecar file and is deliberately not folded in here.
  while IFS= read -r _f10p; do
    _f10n=$((_f10n + 1))
    if [ -z "$_f10ref" ]; then _f10ref="$_f10p"
    elif [ "$_f10p" != "$_f10ref" ]; then
      bad deploy.baseline-projection "baseline projection differs from the first copy: ${f#$ROOT/}"
    fi
  done <<EOF
$(sed -n "s/.*\(-S '{perms:[^']*}'\).*/\1/p" "$f")
EOF
done
[ "$_f10n" -ge 3 ] || bad deploy.baseline-projection "expected the baseline projection in all three of sec0-harden.sh, floor-deny.sh and guard-integrity.sh; found $_f10n copy/copies"
}

# ── F3 · guards pin the interpreter they match with ────────────────────────
rule_F3() {
rule "admission.grep-wrapper guards use \$FLOOR_GREP, never a bare grep, for rule matching"
# Any file that SOURCES guard-lib has $FLOOR_GREP in scope and must use it —
# a bare grep there resolves to whatever is first in PATH. The audit found
# guard-integrity.sh doing this inside the kill-switch presence check, where a
# grep-resolution difference decides whether the gate blocks the session.
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  # TEST HARNESSES ARE EXEMPT, and not merely for convenience. A test asserting
  # on what a guard produced must use the plain `grep` in its own PATH: if it
  # used $FLOOR_GREP it would inherit whatever the guard inherited, and a
  # FLOOR_GREP misconfiguration would make the guard and its test agree by
  # construction instead of being caught. The rule protects RULE MATCHING inside
  # guards, where grep resolution decides a security verdict.
  case "$(basename "$f")" in lint-conventions.sh|*-test.sh) continue ;; esac
  # SOURCES it, not merely mentions it. doctor.sh READS guard-lib.sh to report
  # which grep the floor pins; floor-install.sh names it in a copy list. Neither
  # has $FLOOR_GREP in scope, so flagging them was the rule mis-scoping itself.
  grep -qE '^[[:space:]]*\.[[:space:]]+"[^"]*guard-lib\.sh"' "$f" 2>/dev/null || continue
  grep -nE '(^|[|(;&[:space:]])grep[[:space:]]' "$f" 2>/dev/null | grep -vE '^[0-9]+: *#' | grep -q . \
    && bad admission.grep-wrapper "bare grep in a guard-lib consumer (use \$FLOOR_GREP): ${f#$ROOT/}"
done
}

# ── D1 · the config dir is resolved, never hardcoded ───────────────────────
# baseline-pin.sh WRITES the pointer into ${CLAUDE_CONFIG_DIR:-…}; restore.sh
# read it from $HOME/.claude unconditionally, so the two halves of RECOVER
# disagreed about which dir they meant.
rule_D1() {
rule "deploy.config-dir scripts resolve \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}, never a bare \$HOME/.claude"
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  # guard-selfedit deliberately protects the LIVE dir as well as the active one.
  # The suites that compare the sandbox against live left bin/ for tests/ (harbor#727).
  case "$(basename "$f")" in guard-selfedit.sh|lint-conventions.sh) continue ;; esac
  # A word boundary after .claude — otherwise .claude-sandbox and
  # .claude-recover-test match. And `LIVE=`/`LIVE_DIR=` is the legitimate idiom
  # for NAMING the live dir in order to refuse it; what is forbidden is READING
  # or WRITING state through a hardcoded path.
  grep -nE '(\$\{HOME\}|\$HOME)/\.claude([^-a-zA-Z0-9]|$)' "$f" 2>/dev/null \
    | grep -v 'CLAUDE_CONFIG_DIR' | grep -v ':-' | grep -vE '^[0-9]+: *#' \
    | grep -vE '^[0-9]+:[[:space:]]*(LIVE|LIVE_DIR)=' | grep -q . \
    && bad deploy.config-dir "hardcoded live config dir: ${f#$ROOT/}"
done
}

# ── D2 · settings.json mutators gate the live dir ──────────────────────────
rule_D2() {
rule "deploy.live-flag every settings.json mutator requires an explicit --live for the live dir"
# `APPLY=1` was the only trigger, so pin-instructions.sh — which uses a MODE
# variable — was never checked, and it defaults its target to the LIVE dir. That
# is the file pass 10 walked through four different ways. Any script that writes
# a pin or a settings file counts, however it spells its apply flag.
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  # status-gen.sh has an --apply arm but writes STATUS.md IN THE REPO — it never
  # touches a config dir, so a --live gate would be meaningless ceremony. The
  # rule is about scripts that can rewrite the LIVE config.
  # marker-backfill.sh (H3) writes ONE line into OTHER repositories' descriptors
  # and never a config surface — it REFUSES any target that resolves inside the
  # config dir, so a --live gate would name a directory it is forbidden to
  # reach. The refusal is the control, not this exemption, and floor-test's H3
  # block fires the script at a config-dir target to keep that true.
  # worktree.sh (CI-4) is the THIRD exemption of the same shape, and three is the
  # finding. This rule triggers on `--apply)` / `APPLY=1` — an APPLY FLAG — and
  # then demands a control that only makes sense for a config-dir writer. It
  # removes git worktrees and never reads or writes a config surface at all, so a
  # `--live` gate would name a directory it has no business touching. Its
  # equivalent control is stronger and is asserted in tests/ci/worktree-test.sh: `gc`
  # is a dry run unless `--apply`, and dirty / session-held / main-worktree are
  # refusals no flag overrides.
  #
  # docs-gen.sh (harbor#173) is the FOURTH exemption and is status-gen.sh's exact
  # shape: an --apply arm that writes a GENERATED FILE IN THE REPO (docs/index.html)
  # and never reads or writes a config surface. Four of these now, which is no
  # longer a run of special cases — it is the trigger being wrong. Recorded on
  # harbor#144, which already argues for keying this rule on the write.
  #
  # THE REAL FIX IS TO TRIGGER ON THE WRITE, NOT THE FLAG — key D2 on a script
  # that names a config dir or settings.json, so a new mutator is caught even if
  # it spells its apply flag some fourth way, and a non-mutator is never asked
  # for ceremony. That is a change to a floor-adjacent rule and does not belong
  # in the commit that tripped over it; filed rather than done here.
  # proposal.sh (harbor#44 follow-through) is the FIFTH of this exact shape: an
  # --apply arm that writes inside the REPO (proposals/ and, at apply, the tree
  # via `git apply`) and never reads or writes a config surface. It has its own
  # stronger controls, asserted in tests/obs/proposal-test.sh: a dry run unless
  # --apply, a refusal on any refuted review, a refusal on a patch whose bytes
  # changed since review, and an unoverridable refusal on a patch touching the
  # packet machinery. Five exemptions is the same finding harbor#144 already
  # carries — the trigger is the flag when it should be the write.
  # A SUITE IS NOT A MUTATOR, as a class. `proposal-test.sh` was exempted here by
  # NAME, which is the sixth exemption of the flag-trigger's own shape: a suite
  # matches `--apply)` because it EXERCISES a mutator's apply arm, and then gets
  # asked for a gate protecting a dir it never writes. Keying on the class instead
  # of the name means the next suite that tests an --apply arm does not have to be
  # added here. A suite's control is its own assertions, and its config dir is a
  # sandbox by construction (guard-lib.sh: a writer that cannot mkdir cannot
  # pollute what it cannot find).
  #
  # issue-connector.sh (harbor#512) is the SIXTH named exemption of one shape, and
  # six is past the point where the list is the finding. Its --apply arm writes
  # LABELS TO THE GITHUB TRACKER through `gh issue edit` — not a config dir, not a
  # settings file, nothing on this disk — so a --live gate would name a directory it
  # is not reaching. Its controls are stronger than a flag and are asserted in
  # tests/cli/issue-connector-test.sh: every label is checked against
  # CONTRACTS/issue-taxonomy.tsv and one outside it is refused, the refusal writes
  # NOTHING (asserted against an edit log, not inferred), --apply with no labels is
  # refused, and --suggest never applies what it prints.
  #
  # Six exemptions with one shape is harbor#144's argument finished: the trigger is
  # the flag when it should be the write. Recorded there rather than fixed here,
  # because keying D2 on a config-surface write is a change to a floor-adjacent rule
  # and does not belong in the commit that tripped over it.
  case "$(basename "$f")" in
    *-test.sh) continue ;;
    status-gen.sh|docs-gen.sh|marker-backfill.sh|worktree.sh|proposal.sh) continue ;;
    frozen-gen.sh) continue ;;  # --apply writes standards/naming/frozen.tsv in the repo, never the live box (harbor#1276)
    issue-connector.sh) continue ;;
    # findings.sh (harbor#590) writes GitHub issues and never a config dir; its --apply is gated
    # on the checkout being origin/main instead, asserted in tests/obs/findings-test.sh. The
    # seventh of harbor#144's shape: the trigger is the flag when it should be the write.
    findings.sh) continue ;;
    # ci-runners.sh (harbor#1060) writes docker containers and GitHub runner variables, never a config dir;
    # its gate is a dry run unless --apply, asserted in tests/ci/ci-runners-test.sh (the same finding, harbor#144).
    ci-runners.sh) continue ;;
    # ci-runners-watch-lib.sh is `tick`, sourced by ci-runners.sh and run only through it: the same gate, the same suite.
    ci-runners-watch-lib.sh) continue ;;
    # ci-runs-on.sh (harbor#1060) rewrites the workflow files of a checkout it is handed, never a config dir;
    # dry run unless --apply, asserted in tests/ci/ci-runs-on-test.sh (harbor#144's shape again).
    ci-runs-on.sh) continue ;;
    # browser-hosts-add.sh (harbor#900) writes one repo file, CONTRACTS/browser-agent-hosts.txt,
    # and never a config dir; the live box reads the deployed copy, so deploy.sh is its gate.
    browser-hosts-add.sh) continue ;;
  esac
  grep -qE 'APPLY=1|MODE="--apply"|\-\-apply\)' "$f" 2>/dev/null || continue
  # ON THE INSTALL STANDARD, the gate is install-lib's il_target and D7 holds the file to it; its
  # `"$(il_cmd --apply)"` hints match the trigger above and are not a second parser.
  _d2il="$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null)"
  if printf '%s\n' "$_d2il" | grep -qE '(^|[;&|[:space:]])\.[[:space:]]+[^;]*install-lib\.sh' \
     && printf '%s\n' "$_d2il" | grep -qE '(^|[;&|[:space:]])il_target([;&|[:space:]]|$)'; then continue; fi
  # COMMENTS STRIPPED FIRST (harbor#212). This was a bare grep over the whole file,
  # so a mutator with no gate whatsoever passed if it merely MENTIONED the phrase in
  # prose — and the phrase appears in prose all over this tree, including in this
  # rule's own rationale. The house idiom is an executable refusal
  # (`echo "<tool>: refusing … without an explicit --live" >&2`), so the check has
  # to see code. Stripping comments is the narrowest thing that restores the
  # discrimination without guessing at the message's exact wording.
  _d2code="$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null)"
  printf '%s\n' "$_d2code" | grep -q 'explicit --live' \
    || bad deploy.live-flag "mutator without a --live gate: ${f#$ROOT/}"
  # …and the gate must compare RESOLVED paths. A plain string compare is
  # defeated by a trailing slash, which pass 11 used to strip every hook from a
  # live config with no --live (P11-01). pin-instructions.sh had the right shape
  # and its own comment claimed the other four matched it; they did not, and
  # this rule was a string-presence check that could never notice.
  printf '%s\n' "$_d2code" | grep -q 'explicit --live' || continue
  # THIS CHECK READS $_d2code TOO (harbor#212, second half). The comment strip
  # was applied to the presence check above and not to this one, so the SAME
  # spoof survived one line lower: a mutator whose gate is real but compares raw
  # strings passes if `pwd -P` appears anywhere in its prose — and the phrase is
  # in this file's own rationale three lines up. No shipped mutator relies on it
  # today (all fourteen have the idiom in code), so this is latent, not a live
  # finding; it is fixed because "the rule reads code" was never true of half
  # the rule. The third check below needs no strip: its `^\s*if` anchor cannot
  # match a commented line, which is asserted rather than assumed in lint-test.
  printf '%s\n' "$_d2code" | grep -qE 'cd -P|pwd -P' \
    || bad deploy.live-flag "--live gate compares strings, not resolved paths: ${f#$ROOT/}"
  # …and it must read INTENT, not an argument's INDEX (harbor#52). All four gates
  # tested `${1:-}` while their own arg loops accepted --live anywhere, so
  # `<dir> --live --apply` was refused: explicit intent, correct dir, blocked.
  # That is a false positive on the one gate the operator has to pass, and
  # CONSTITUTION §2.11 calls that a defect — a gate that blocks ordinary work is
  # a gate that gets deleted. The previous two checks in this rule could not see
  # it: the gate existed and did compare resolved paths.
  grep -nE '^\s*if .*_phys .*(&&|\]).*\$\{?1' "$f" \
    | grep -q '\-\-live' \
    && bad deploy.live-flag "--live gate reads \$1 instead of a flag set by the arg loop: ${f#$ROOT/}"
done
}

# ── D6 · a printed command is one its own gate accepts ─────────────────────
# THE HALF D2 CANNOT SEE (harbor#142). D2 checks the code that DECIDES: that a
# mutator has a --live gate, that the gate compares resolved paths, that it reads
# a flag and not $1. Nothing checked the strings a tool PRINTS — and on 2026-08-06
# three refused commands were live in the deployed tooling, each found by hand
# while doing something else:
#
#   floor-install.sh:220  post-apply hint printed `<live path> --apply --with-b6`
#   floor-install.sh:197  invoked  pin-instructions.sh --apply "$DIR"  on live
#   floor-verify.sh:164   printed  pin-instructions.sh --apply         (defaults live)
#
# harbor#51 → harbor#95 → these. Every time it was fixed at the one site somebody
# noticed, and harbor#95's own Done-when asked for this rule and never got it.
# The cost is not the wasted paste: a tool that teaches a command its own gate
# refuses trains the operator to delete the gate, and these are the gates between
# "I meant the sandbox" and a rewritten live config.
#
# WHAT COUNTS AS A VIOLATION. A FULL INVOCATION of a live-gated mutator with
# --apply — printed to the operator OR executed by the script — whose target is
# neither an explicit --live nor a computed spelling (`_target_spelling`, `$_hint`,
# `$_vt`, …). Both halves, because floor-install.sh:197 was the executed kind and
# it failed silently on every live install, which is worse than a wrong hint.
# `Re-run with --apply.` is deliberately NOT a violation — it respells no target,
# so it cannot teach a wrong one (prod-guard-install.sh:137 is correct for exactly
# that reason).
#
# THE GUARDED FORMS ARE CORRECT AND MUST NOT BE FLAGGED. Harbor's idiom is a
# two-branch choice: `--live --apply` when the target resolves to live, `$DIR
# --apply` otherwise. A false positive here would be a defect under CONSTITUTION
# §2.11 — the gate that blocks ordinary work is the gate that gets deleted — so a
# `$DIR`-target line is accepted when, within TWO lines, there is either a sibling
# --live form or a `_phys`-against-$LIVE_DIR comparison that licenses it.
#
# TWO LINES, AND THE NUMBER IS LOAD-BEARING. The defect at floor-install.sh:197
# had a `_phys "$DIR" = _phys "$LIVE_DIR"` comparison three lines below it — for a
# different decision entirely (which floor-deny spelling to run). A ±3 window
# accepted the defect it was written to catch. So the window is tight and the
# convention is that a guarded call sits adjacent to its guard; where that reads
# badly, spell --live and the window stops mattering.
rule_D6() {
rule "deploy.printed-command-valid every command a mutator PRINTS is one its own gate would accept"
_D6_MUT='floor-install|floor-uninstall|floor-deny|sec0-harden|pin-instructions|runtime-install|prod-guard-install|restore'
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  # The suites EXECUTE these tools and quote them in assertion labels; neither is
  # a hint to an operator. Their own coverage of the printed hints is floor-test's
  # WIRE-2 section, which runs the tools and reads what they actually print.
  case "$(basename "$f")" in *-test.sh) continue ;; esac
  # A SCRIPT WHOSE TARGET CAN NEVER BE LIVE needs no --live spelling. sandbox-make.sh
  # refuses the live dir unconditionally — there is no `--live)` in its arg loop to
  # open it — so `floor-install.sh "$DIR" --apply` is the ONLY correct form there,
  # and demanding --live would be a §2.11 false positive on a script forbidden to
  # reach live at all. Keyed on the shape (a _phys compare against $LIVE plus no
  # --live escape), not on a message string.
  if ! grep -q -- '--live)' "$f" && grep -qE '_phys[^#]*"\$LIVE' "$f"; then continue; fi
  # Candidate lines: an echo/printf that names a gated mutator AND --apply.
  # NOT `printf … | while read`. bad() increments FAIL in the CURRENT shell, and a
  # pipeline puts the loop in a subshell where that increment is discarded — the
  # rule would print VIOLATION and the script would still exit 0. That is the
  # "green test that cannot fail" shape CONSTITUTION §2.10 exists for, in a rule
  # written to close a green-suite blind spot. Redirect from a file instead.
  _d6t="${TMPDIR:-/tmp}/lint-d6.$$"
  grep -nE '('"$_D6_MUT"')\.sh[^#]*--apply' "$f" \
    | grep -vE '^[0-9]+:[[:space:]]*#' > "$_d6t" 2>/dev/null || true
  [ -s "$_d6t" ] || { rm -f "$_d6t"; continue; }
  while IFS=: read -r _ln _txt; do
    case "$_txt" in
      *--live*|*_target_spelling*|*'$_hint'*|*'$_vt'*|*'$_pin_tgt'*) continue ;;
      # install-lib's spelling of the run's own target (the install standard): --live or --dir '<t>',
      # printed (il_spell, il_cmd) or executed (il_run).
      *il_spell*|*il_cmd*|*il_run\ *) continue ;;
      # A usage line teaches the flag NAMES, not a target — `<dir>|--live` is the
      # whole point of it, and it carries no path to get wrong.
      *usage:*) continue ;;
    esac
    _lo=$((_ln - 2)); [ "$_lo" -lt 1 ] && _lo=1
    if sed -n "${_lo},$((_ln + 2))p" "$f" \
         | grep -qE '('"$_D6_MUT"')\.sh[^#]*--live|--live[^#]*--apply|_phys[^#]*LIVE_DIR'; then
      continue
    fi
    bad deploy.printed-command-valid "printed command its own gate refuses (no --live, no computed target): ${f#$ROOT/}:$_ln"
  done < "$_d6t"
  rm -f "$_d6t"
done
}

# ── D7 · one interface, parsed once (the install standard, harbor#765) ────────
# `[--apply] (--live | --dir PATH) [--accept-loss] [-h]` is parsed in bin/install-lib.sh and nowhere
# else. A second parser is how `<sandbox> --live --apply` wrote live (the last word won), how a typo
# became a target, and how CLAUDE_CONFIG_DIR chose the dir a restore overwrote (review 2026-09-27 §2).
rule_D7() {
rule "deploy.target-from-lib every installer takes its target from install-lib.sh: il_parse, il_target, no second parser, no env target"
# floor-deny, floor-verify and renew-check name a config dir too (harbor#800): the same one parser.
for f in "$ROOT"/bin/*-install.sh "$ROOT"/bin/floor-uninstall.sh "$ROOT"/bin/restore.sh \
         "$ROOT"/bin/pin-instructions.sh "$ROOT"/bin/sec0-harden.sh \
         "$ROOT"/bin/floor-deny.sh "$ROOT"/bin/floor-verify.sh "$ROOT"/bin/renew-check.sh; do
  [ -f "$f" ] || continue
  _d7="${f#"$ROOT"/}"
  _d7c="$(sed -e '/^[[:space:]]*#/d' -e 's/[[:space:]]#.*$//' "$f")"
  if ! printf '%s\n' "$_d7c" | grep -qE '(^|[;&|[:space:]])\.[[:space:]]+[^;]*install-lib\.sh'; then
    bad deploy.target-from-lib "$_d7 does not source bin/install-lib.sh"; continue
  fi
  printf '%s\n' "$_d7c" | grep -qE '(^|[;&|[:space:]])il_parse[[:space:]]+"\$@"' \
    || bad deploy.target-from-lib "$_d7 never calls il_parse \"\$@\""
  printf '%s\n' "$_d7c" | grep -qE '(^|[;&|[:space:]])il_target([;&|[:space:]]|$)' \
    || bad deploy.target-from-lib "$_d7 never calls il_target"
  # A case arm, at a line's start or after `in`: never `"$(il_cmd --apply)"`, which is a hint.
  printf '%s\n' "$_d7c" \
    | grep -qE '(^[[:space:]]*|[[:space:]]in[[:space:]]+)\(?([^)]*\|)?(--apply|--live|--dir|--accept-loss)(\|[^)]*)?\)' \
    && bad deploy.target-from-lib "$_d7 parses a standard flag itself — il_parse owns --apply, --live, --dir and --accept-loss"
  printf '%s\n' "$_d7c" | grep -qE '\$\{CLAUDE_CONFIG_DIR:-' \
    && bad deploy.target-from-lib "$_d7 reads CLAUDE_CONFIG_DIR as a default target — it never picks the target"
done
}

# ── D3 · exit-code polarity ────────────────────────────────────────────────
# `exit 2` (deny) belongs in exactly one place: floor_block(). An open-coded
# exit 2 in a PostToolUse or SessionStart hook is a silent no-op — the guard
# would look like it denies and would not.
# ── D4 · no deny entry the harness never consults ──────────────────────────
# Harbor shipped 24 `Write(<path>)` deny entries — every credential store, every
# live config surface — for five days. The harness accepts them, never consults
# them, and warns at startup; the permissions reference is explicit: "Claude Code
# checks file permissions against `Edit(path)` and `Read(path)` rules only" for
# path rules, and `Edit` covers every file-editing tool. They were invisible
# because each was PAIRED with a working `Edit(p)` twin, so the list did its job
# while half of it was decoration — and a half-inert control reads exactly like a
# whole one. floor-test asserts the same property over the derived entry set; this
# rule catches it at the source, in any writer, before it can be applied.
#
# A BARE tool name with no path (`"Write"`) is a different rule and IS consulted
# at the tool level, so the pattern below requires a `(`.
rule_D4() {
rule "deploy.deny-consulted no writer emits a deny entry the harness never consults (Write/NotebookEdit/MultiEdit/Glob path rules)"
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  # The mode that REMOVES these has to name them to match them. Skip comments;
  # scan code only. floor-test, which builds fixtures from them, left bin/ (harbor#727).
  case "$(basename "$f")" in floor-deny.sh|floor-uninstall.sh) continue ;; esac
  grep -v '^[[:space:]]*#' "$f" 2>/dev/null \
    | grep -qE '"(Write|NotebookEdit|MultiEdit|Glob)\([^"]+\)"' \
    && bad deploy.deny-consulted "deny entry for a tool whose path rules are never consulted — use Edit(path)/Read(path): ${f#$ROOT/}" \
    || true
done
}

# ── D5 · a Read deny does not cover every writer ────────────────────────────
# THE INVERSE OF D4, and the gap D4 is structurally unable to see. D4 asks "does
# every entry a writer emits get consulted?"; it never asks "is every path worth
# denying denied for every tool that can change it?". harbor#88 was filed about
# that inverse and looked at the wrong half of the list.
#
# The harness's rule, quoted from code.claude.com/docs/en/permissions (read
# 2026-08-02): file permissions are checked against `Edit(path)` and `Read(path)`
# only; an `Edit` deny "covers all file-editing tools"; and a `Read` deny "also
# blocks the Edit tool on the same path, including creating a new file there.
# Write and NotebookEdit aren't covered, so add an `Edit` deny rule for paths no
# tool may change."
#
# So Read-without-Edit is a WRITABLE secret. Fired on this machine before the
# rule was written: `Write` created a file at a path carrying `Read(//**/.env)`,
# while `Edit` on the same path was refused. Seven paths were in that state.
#
# ONE DIRECTION ONLY, deliberately. Edit-without-Read is a posture, not a defect:
# settings.json, ~/.claude/bin/** and the pins are meant to be readable and not
# writable, and floor-verify.sh reads them by design. Requiring the reverse twin
# would make this rule demand that Harbor blind itself to its own controls.
rule_D5() {
rule "deploy.deny-read-edit-pair every path a writer denies for Read also has an Edit twin (Read does not cover Write/NotebookEdit)"
_d5src="$ROOT/bin/floor-deny.sh $ROOT/bin/sec0-harden.sh"
# Comments are stripped first: both files QUOTE deny entries while explaining
# them, and a rule that reads its own documentation as data is the substring
# defect DE-22 records.
_d5body="$(grep -vh '^[[:space:]]*#' $_d5src 2>/dev/null || true)"
_d5reads="$(printf '%s\n' "$_d5body" | grep -oE '"Read\([^"]+\)"' | sed 's/^"Read(//; s/)"$//' | sort -u)"
_d5edits="$(printf '%s\n' "$_d5body" | grep -oE '"Edit\([^"]+\)"' | sed 's/^"Edit(//; s/)"$//' | sort -u)"
# A `while read` loop, never `for p in $list`: these paths are globs, and an
# unquoted expansion PATHNAME-EXPANDS them against the linter's own cwd — the
# same zsh/sh word-splitting trap this repo has already been bitten by.
_d5miss="$(printf '%s\n' "$_d5reads" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    printf '%s\n' "$_d5edits" | grep -qxF -- "$_p" || printf '%s\n' "$_p"
  done)"
if [ -n "$_d5miss" ]; then
  printf '%s\n' "$_d5miss" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    printf '  VIOLATION [deploy.deny-read-edit-pair] Read-denied but WRITABLE by Write/NotebookEdit — add "Edit(%s)": bin/floor-deny.sh\n' "$_p" >&2
  done
  FAIL=$((FAIL + $(printf '%s\n' "$_d5miss" | grep -c . || true)))
fi
}

# ── TS1 · the TypeScript tool tree stays zero-setup and writes nothing ──────
# D1 (harbor#6) adds the repo's FIRST first-party TypeScript. It sits in the Bun
# skill-tool layer, not the floor layer (CONSTITUTION.md § Operational rules —
# "language by layer, not by decree"), and two properties are what make it safe
# to keep in a governance repo. Neither is self-evident from reading the code,
# and both are one line away from being false:
#
# (a) NO INSTALL STEP. There is no package.json, no tsconfig, no lockfile and no
#     node_modules — `bun tools/memory/memory-engine.ts` is the whole build. A
#     single off-disk import ends that, and it ends it silently: the code still
#     runs on the machine that has the package cached. The import allowlist is
#     the mechanism; without it, "zero-setup" is a claim in a README.
#
# (b) THE INDEX IS NEVER PERSISTED. CONTRACTS/memory-format.md fixes the derived
#     graph/BM25 layer as "rebuilt in-memory at query time. No DB is the source
#     of truth." A cache is the obvious optimisation and it is exactly what the
#     contract forbids, so the ban is checked here rather than trusted — a rule
#     with no mechanism is a wish. A tool that genuinely must write belongs in
#     bin/ (POSIX sh, where the write rules already are), or this rule gets
#     amended deliberately with the reason in its header.
rule_TS1() {
rule "lint.typescript-tool-shape tools/*.ts are kebab-case + ticketed, import nothing off-disk, and write nothing (harbor#6)"
for f in "$ROOT"/tools/*/*.ts; do
  [ -f "$f" ] || continue
  # letters spelled out: under en_NZ, macOS sh lets [a-z] match capitals (harbor#1149)
  case "$(basename "$f")" in
    *[!abcdefghijklmnopqrstuvwxyz0123456789.-]*) bad lint.typescript-tool-shape "tools/ filename not kebab-case: ${f#$ROOT/}" ;;
  esac
  head -4 "$f" | grep -qE 'harbor#[0-9]+|B[0-9]+|K1a|SEC-0' \
    || bad lint.typescript-tool-shape "no ticket reference in the first 4 lines: ${f#$ROOT/}"
  # Captured into a variable, NOT piped into `while ... bad`: `bad` increments
  # FAIL, and a pipeline runs its right-hand side in a SUBSHELL, so the counter
  # increment is discarded and the rule prints a violation while exiting 0.
  _ts_imp="$(grep -nE '^[[:space:]]*(import|export)[^;]*[[:space:]]from[[:space:]]*['"'"'"]' "$f" 2>/dev/null \
             | grep -vE '['"'"'"](\./|\.\./|bun:|node:)' || true)"
  [ -z "$_ts_imp" ] || bad lint.typescript-tool-shape "off-disk import (would need npm) in ${f#$ROOT/}: $(printf '%s' "$_ts_imp" | head -1 | cut -c1-80)"
  # process.stdout/stderr.write is OUTPUT, not a filesystem write, and a CLI that
  # streams results is the normal case. Excluded explicitly: a rule that fires on
  # the ordinary way to print gets switched off, and a disabled rule protects
  # nothing (CONSTITUTION.md §2.11).
  _ts_wr="$(grep -nE '(writeFileSync|appendFileSync|mkdirSync|createWriteStream|Bun\.write|\.write\(|rmSync|unlinkSync)' "$f" 2>/dev/null \
            | grep -vE '^[0-9]+:[[:space:]]*(\*|//)' \
            | grep -vE 'process\.(stdout|stderr)\.write' || true)"
  [ -z "$_ts_wr" ] || bad lint.typescript-tool-shape "filesystem write in ${f#$ROOT/} — the derived index is in-memory by contract: $(printf '%s' "$_ts_wr" | head -1 | cut -c1-80)"
done
}

# ── CLI1 · the harbor verb surface matches its contract ─────────────────────
# harbor#42: four documents called Helm "the environment + the `harbor` command"
# while no ticket defined a subcommand. Now that the verbs exist, the failure mode
# moves: a renamed script, a verb added to the dispatcher and not the contract, or
# a new bin/*.sh nobody classified. All three are silent.
#
# THREE CHECKS, and the second is why bin/harbor may embed its own table at all:
# CONTRACTS/cli.md argues that a recovery command must not parse a markdown file
# out of a repo checkout to print --help. The equality assertion here is what makes
# the embedded copy safe — remove it and the contract becomes decoration.
rule_CLI1() {
rule "lint.cli-contract harbor's verbs, its contract, and bin/ agree (CONTRACTS/cli.md)"
_cli="$ROOT/CONTRACTS/cli.md"
_disp="$ROOT/bin/harbor"
if [ -f "$_cli" ] && [ -f "$_disp" ]; then
  # (1) + (2): the dispatcher's verb<TAB>script pairs vs the contract's table rows.
  _d_pairs="$(awk '/^VERBS="/{f=1;next} /^"$/{f=0} f && NF' "$_disp" \
              | awk -F'\t' 'NF>=2 {print $1"="$2}' | sort)"
  # A script may carry fixed words after it (`deploy.sh --only floor`, harbor#800): the pair keeps them.
  _c_pairs="$(grep -E '^\| `harbor [a-z-]+` \| `[a-z0-9.-]+\.sh( [a-z0-9-]+)*` \|' "$_cli" \
              | sed -E 's/^\| `harbor ([a-z-]+)` \| `([a-z0-9.-]+\.sh( [a-z0-9-]+)*)` \|.*/\1=\2/' | sort)"
  if [ "$_d_pairs" != "$_c_pairs" ]; then
    bad lint.cli-contract "bin/harbor's verb table and CONTRACTS/cli.md disagree:"
    printf '%s\n' "$_d_pairs" > "${TMPDIR:-/tmp}/cli-d.$$"
    printf '%s\n' "$_c_pairs" > "${TMPDIR:-/tmp}/cli-c.$$"
    diff "${TMPDIR:-/tmp}/cli-d.$$" "${TMPDIR:-/tmp}/cli-c.$$" | sed 's/^/      /' >&2 || true
    rm -f "${TMPDIR:-/tmp}/cli-d.$$" "${TMPDIR:-/tmp}/cli-c.$$"
  fi
  # NOT `printf | while read … bad`. This was reported by the review bot on PR #62
  # and left unfixed: a pipeline runs its right-hand side in a SUBSHELL, so `bad`
  # incremented a FAIL that died with the subshell — the linter printed a CLI1
  # violation for a verb pointing at a deleted script and still exited 0. That is
  # the third shape of the same defect in this file (K1's first cut, and the trap
  # TS1's header names), which is why it is now fixed everywhere it appears rather
  # than only where it was noticed.
  # A here-doc, not `for _pair in $_d_pairs`: a pair holds a space once a verb carries fixed words.
  _cli_missing=""
  while IFS= read -r _pair; do
    _v="${_pair%%=*}"
    _s="${_pair#*=}"; _s="${_s%% *}"
    [ -n "${_s:-}" ] || continue
    [ -f "$ROOT/bin/$_s" ] || _cli_missing="$_cli_missing $_v=$_s"
  done <<CLIEOF
$_d_pairs
CLIEOF
  for _m in $_cli_missing; do
    bad lint.cli-contract "verb '${_m%%=*}' dispatches to bin/${_m#*=}, which does not exist"
  done
  # (2b) THE `--json` COLUMN, which this rule did not compare (2026-08-14).
  # (1)+(2) above assert verb=script and stop there, so column 3 of the two tables
  # could disagree indefinitely — and the disagreement is not cosmetic: bin/harbor
  # REFUSES `--json` with exit 2 for any verb whose column says `no`, so the column
  # IS the behaviour. A table saying `yes` where the dispatcher says `no` documents
  # a machine-readable output that cannot be obtained through the front door; the
  # reverse promises a passthrough that then produces nothing parseable.
  #
  # This is CLI1's own argument applied one column over: the document is a second
  # copy of a list that lives in code, and the equality assertion is the only thing
  # that makes a copy safe. The verb=script half had it; this half did not.
  _d_json="$(awk '/^VERBS="/{f=1;next} /^"$/{f=0} f && NF' "$_disp" \
             | awk -F'\t' 'NF>=3 {print $1"="$3}' | sort)"
  _c_json="$(grep -E '^\| `harbor [a-z-]+` \| `[a-z0-9.-]+\.sh( [a-z0-9-]+)*` \|' "$_cli" \
             | sed -E 's/^\| `harbor ([a-z-]+)` \| `[a-z0-9.-]+\.sh( [a-z0-9-]+)*` \| *([a-z]+) *\|.*/\1=\3/' | sort)"
  if [ "$_d_json" != "$_c_json" ]; then
    bad lint.cli-contract "bin/harbor and CONTRACTS/cli.md disagree about which verbs take --json:"
    printf '%s\n' "$_d_json" > "${TMPDIR:-/tmp}/cli-dj.$$"
    printf '%s\n' "$_c_json" > "${TMPDIR:-/tmp}/cli-cj.$$"
    diff "${TMPDIR:-/tmp}/cli-dj.$$" "${TMPDIR:-/tmp}/cli-cj.$$" | sed 's/^/      /' >&2 || true
    rm -f "${TMPDIR:-/tmp}/cli-dj.$$" "${TMPDIR:-/tmp}/cli-cj.$$"
  fi
  # AND THE COLUMN MUST PARSE AT ALL. `[ "$a" != "$b" ]` is vacuously satisfied when
  # both sides come back EMPTY, which is exactly what a changed row format would do
  # to those two seds — the same way a variable rename silently emptied floor-test's
  # recovery-path scan on this branch. An assertion that cannot fail is worse than
  # none, so the count is asserted too (№2.10).
  _n_json="$(printf '%s\n' "$_d_json" | grep -c '=' || true)"
  [ "${_n_json:-0}" -ge 10 ] \
    || bad lint.cli-contract "could only parse ${_n_json:-0} --json column value(s) out of bin/harbor's VERBS table — the row format changed and the comparison above verified NOTHING"

  # (3) every bin/*.sh is classified — a verb, or internal WITH A REASON. A script
  # that is in neither table is an orphan nobody decided about, which is how a
  # front door quietly stops being the front door.
  for f in "$ROOT"/bin/*.sh $(_engines); do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    grep -qF "\`$b\`" "$_cli" || bad lint.cli-contract "${f#"$ROOT"/} appears in no CONTRACTS/cli.md table — verb or internal?"
  done
fi
}

rule_D3() {
rule "admission.exit-codes exit 2 appears only in floor_block(); every hook ends with exit 0"
# Scope: HOOK scripts only. exit 2 is the ordinary usage-error code for a CLI
# tool (restore.sh, sandbox-make.sh), which is not what this rule is about.
# memory-harvest.sh (harbor#6) is a SessionStart hook, so it is in scope for
# both loops. A hook whose FILENAME escapes this glob is a fail-open contract
# nothing checks: it may exit non-zero on a bad day and the harness treats that
# as a blocked event, in a script whose entire job is to be invisible.
for f in "$ROOT"/bin/guard-*.sh "$ROOT"/bin/annotate-web.sh "$ROOT"/hooks/memory-harvest/memory-harvest.sh; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in guard-lib.sh) continue ;; esac
  grep -nE '(^|[[:space:];&|])exit 2([[:space:]]|$)' "$f" 2>/dev/null | grep -vE '^[0-9]+: *#' | grep -q . \
    && bad admission.exit-codes "hook open-codes 'exit 2' instead of floor_block(): ${f#$ROOT/}"
done
for f in "$ROOT"/bin/guard-*.sh "$ROOT"/bin/annotate-web.sh "$ROOT"/hooks/worklog-push/worklog-push.sh "$ROOT"/hooks/memory-harvest/memory-harvest.sh; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in guard-lib.sh) continue ;; esac
  [ "$(tail -1 "$f")" = "exit 0" ] || bad admission.exit-codes "hook does not end with 'exit 0': ${f#$ROOT/}"
done
}

# ── P1 · ported corpora carry provenance ───────────────────────────────────
rule_P1() {
rule "admission.upstream-sha-cited guards that port upstream corpora cite the pinned SHA (A2 provenance)"
for f in "$ROOT"/bin/guard-bash.sh "$ROOT"/bin/guard-egress.sh "$ROOT"/bin/guard-selfedit.sh "$ROOT"/bin/annotate-web.sh; do
  [ -f "$f" ] || continue
  grep -q 'a4e8e74' "$f" || bad admission.upstream-sha-cited "no upstream SHA cited: ${f#$ROOT/}"
done
}

# ── V1 · vendored-copy freshness (the check CONTRACTS/README long claimed) ──
# HONEST SCOPE, stated so this claim does not outrun the code a third time:
# this is a MANIFEST check, not a content diff against the upstream remote. It
# proves the vendored set and its provenance agree — a skill added or removed
# without updating PROVENANCE.md fails. A true content diff needs the pinned
# upstream clone, which CI does not have; PROVENANCE.md documents that manual
# re-sync, and V2 below asserts the pin is at least declared.
rule_V1() {
rule "skill.vendor-provenance every vendored skill is listed in PROVENANCE.md (and vice versa)"
# PROV is defined in the shared section at the top (harbor#537) — another rule reads it.
if [ -f "$PROV" ]; then
  for d in "$ROOT"/vendor/skills/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    # A ROW, NOT A SUBSTRING ANYWHERE IN THE FILE (harbor#447). This was a bare
    # grep over the whole of PROVENANCE.md, and the file carries narrative on
    # purpose — so a skill named in a prose paragraph satisfied a rule that claims
    # to check it is LISTED. Measured 2026-09-16: with every table row deleted, V1
    # still passed for 18 of 28 vendored skills, because the surrounding prose
    # mentions the name. Same shape as the memory note `guard-satisfied-by-its-own-
    # comment`, and the same fix: read the structure, not the bytes.
    #
    # It is a FALSE NEGATIVE, which is why nothing ever went red and nobody looked.
    # Restricting to `^|` is strictly stronger and costs nothing today: all 28
    # tracked skills carry a row, verified before the change, so no legitimate work
    # is blocked (§2.11).
    grep '^|' "$PROV" 2>/dev/null \
      | grep -qiE "(^|[^a-z0-9-])$n([^a-z0-9-]|$)" \
      || bad skill.vendor-provenance "vendored skill has no PROVENANCE.md table ROW: $n (a prose mention is not a listing)"
  done
  # ── THE REVERSE WALK — a row whose directory is gone (harbor#7) ───────────
  # The rule's title has said "and vice versa" since it was written and only
  # ever checked one direction, which made the missing half invisible in the
  # exact way this repo keeps re-finding: the name promises the guarantee, so
  # nobody re-reads the body. What it leaves undetectable is a DELETION — and
  # deletion is precisely what the skills unification does 25 times over. A
  # vendored skill removed without its PROVENANCE row leaves the document
  # asserting an upstream lineage for a directory that no longer exists, and
  # PROVENANCE.md's re-sync clause is the only written route back to upstream
  # fixes, so a lying row is worse than a missing one.
  #
  # THE FIRST COLUMN OF THE PER-SKILL TABLE, NOT EVERY BACKTICKED WORD. This
  # document also discusses skills in prose and names upstream ones Harbor never
  # took; matching those would fire on correct text. The table rows are
  # `| <name> | <verdict> | ...`, so the walk is anchored to that shape and the
  # header and separator rows are dropped by the same predicate that requires a
  # lowercase kebab first field.
  sed -n 's/^|[[:space:]]*\([a-z][a-z0-9-]*\)[[:space:]]*|.*|.*|.*/\1/p' "$PROV" \
  | sort -u > "${TMPDIR:-/tmp}/v1-rows.$$"
  while IFS= read -r _row; do
    [ -n "$_row" ] || continue
    [ -d "$ROOT/vendor/skills/$_row" ] && continue
    bad skill.vendor-provenance "PROVENANCE.md has a row for '$_row' but vendor/skills/$_row is gone — delete the row in the same commit as the directory"
  done < "${TMPDIR:-/tmp}/v1-rows.$$"
  rm -f "${TMPDIR:-/tmp}/v1-rows.$$"
elif _export_tree vendor/skills/; then
  printf '  (skipped: vendor/skills/ is dev-layer and this tree carries none of it, so there is no vendored copy to need provenance)\n'
else
  bad skill.vendor-provenance "vendor/skills/PROVENANCE.md missing — vendored copies have no provenance"
fi
}

rule_V2() {
rule "admission.upstream-sha-pinned PROVENANCE.md pins an upstream SHA, and the guards cite the same one"
if [ -f "$PROV" ]; then
  psha="$(grep -oE '\b[0-9a-f]{7,40}\b' "$PROV" | head -1)"
  [ -n "$psha" ] || bad admission.upstream-sha-pinned "PROVENANCE.md declares no upstream SHA"
  if [ -n "$psha" ]; then
    short="$(printf '%s' "$psha" | cut -c1-7)"
    for f in "$ROOT"/bin/guard-bash.sh "$ROOT"/bin/guard-egress.sh; do
      [ -f "$f" ] || continue
      grep -q "$short" "$f" || bad admission.upstream-sha-pinned "guard cites a different upstream SHA than PROVENANCE.md ($short): ${f#$ROOT/}"
    done
  fi
fi
}

# ── C1 · every contract declares its status and owner ──────────────────────
rule_C1() {
rule "doc.contract-index CONTRACTS/*.md are listed in CONTRACTS/README.md"
if [ -d "$ROOT/CONTRACTS" ]; then
  for f in "$ROOT"/CONTRACTS/*.md; do
    b="$(basename "$f")"
    [ "$b" = "README.md" ] && continue
    grep -q "$b" "$ROOT/CONTRACTS/README.md" || bad doc.contract-index "contract not indexed in README: $b"
  done
fi
}

# ── M1 · ONE marker implementation, never a private re-walk ────────────────
# CONTRACTS/marker.md freezes one detect-and-defer spec across three REPOS, and
# harbor was already violating it inside a single repo: the two work-log hooks
# each walked the tree themselves with `[ -e "$d/.agents" ]` — the forgeable
# predicate floor_in_repo was hardened away from after the 2026-07-24
# marker-forgery finding — while the guards used the hardened one. A planted
# zero-byte `.agents` file silently stopped work-log sync.
rule_M1() {
rule "scope.marker-walk-once the marker walk lives ONLY in floor_in_repo (CONTRACTS/marker.md)"
for f in "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  # guard-lib DEFINES it; the linter names it to forbid it. marker-test left bin/ (harbor#727).
  case "$b" in guard-lib.sh|lint-conventions.sh) continue ;; esac
  # COMMENT LINES ARE NOT CODE. First run of this rule flagged both files it had
  # just fixed, because their comments quote the old predicate verbatim to
  # explain what was wrong with it. A rule that fires on its own documentation
  # is the cry-wolf failure this repo keeps working to avoid.
  grep -nE '\[[[:space:]]+-[edfL][[:space:]]+"?\$[a-zA-Z_]+/\.agents' "$f" 2>/dev/null \
    | grep -qvE '^[0-9]+:[[:space:]]*#' \
    && bad scope.marker-walk-once "private marker walk (call floor_in_repo instead): ${f#$ROOT/}"
done
}

# ── M2 · every governed-repo stand-down is declared, and the five never yield ─
# harbor#581, decided 2026-09-22 (A): inside a governed repo the repo wins on
# workflow, conventions and tooling, and the constitution's five rules never
# yield. The deferral is only as scoped as the code that performs it, so the
# code's stand-down sites are what is checked, not the prose.
#
# WHAT IT READS. Every non-comment call to floor_in_repo, floor_repo_wires or
# floor_engine_stand_down in bin/'s shell scripts, against the table under "What
# stands down inside a governed repo" in CONTRACTS/marker.md. Both directions: a
# call with no row is an undeclared stand-down, and a row with no call is a stale
# claim that reads as coverage. A `constitutional` row is an exception to (A) and
# must name the ticket that owns it.
#
# ONE STAND-DOWN PER FILE AND FUNCTION. A row names a file and a function, not a
# line, so a second call in a declared file would inherit the first one's tier
# and pass — a new constitutional stand-down hiding behind a `report` row. So a
# file that calls any of them twice fails, and the table stays exact.
#
# A SHELL SCRIPT IS `*.sh` OR A SHELL SHEBANG. bin/ carries extensionless
# entrypoints (bin/harbor, bin/gcx) and so do hooks/ and worklog/; a scan keyed on
# the suffix read past all of them. Both scans below use _m2_shells.
#
# WHY bin/ AND NOTHING WIDER. All three live in bin/guard-lib.sh, and a
# script can only call them by sourcing it. That premise is checked below rather
# than assumed: a shell script outside bin/ that sources guard-lib.sh fails this
# rule until the scan is widened.
#
# WHAT IT CANNOT DO. Whether a row's tier is TRUE is judgement — a №3 guard
# declared `project` passes. The rule makes the declaration explicit and
# reviewable, not correct. A stand-down that bypasses all three is invisible
# here; M1 is what keeps marker-based stand-downs on floor_in_repo.
rule_M2() {
rule "scope.stand-down-declared every governed-repo stand-down in bin/ and the hook engines is declared in CONTRACTS/marker.md, and a constitutional one names its ticket (harbor#581)"
_m2_doc="$ROOT/CONTRACTS/marker.md"
if [ ! -f "$_m2_doc" ]; then
  bad scope.stand-down-declared "CONTRACTS/marker.md is missing — no stand-down can be checked"; return 0
fi
_m2_rows="${TMPDIR:-/tmp}/harbor-m2-rows.$$"; _m2_code="${TMPDIR:-/tmp}/harbor-m2-code.$$"
# The table, one row per line: file|fn|tier|ticket. `|` and not a tab, because a
# tab is IFS whitespace and an empty cell would collapse into its neighbour.
awk '/^## What stands down inside a governed repo/ { s = 1; next }
     s && /^## / { s = 0 }
     s && /^\| `(bin|hooks)\// { print }' "$_m2_doc" \
  | awk -F'|' '{ for (i = 2; i <= 6; i++) { gsub(/^[ \t]+|[ \t]+$/, "", $i); gsub(/`/, "", $i) }
                 print $2 "|" $3 "|" $4 "|" $6 }' > "$_m2_rows"
[ -s "$_m2_rows" ] \
  || bad scope.stand-down-declared "CONTRACTS/marker.md has no rows under \"What stands down inside a governed repo\""
# The shell scripts among the files given: a `.sh` name, or a first line that is
# a sh-family shebang. One awk reads only line 1 of each file. Regular files only: mawk stops at the first
# directory operand (bin/harbor-app), so every later script went unread and two live rows read stale (harbor#1149).
_m2_shells() {
  for _m2_a in "$@"; do shift; [ ! -f "$_m2_a" ] || set -- "$@" "$_m2_a"; done
  [ "$#" -gt 0 ] || return 0
  awk 'FNR == 1 { if (FILENAME ~ /\.sh$/ || $0 ~ /^#!.*[\/ ](ba|z|da|k)?sh([ \t]|$)/) print FILENAME; nextfile }' "$@" 2>/dev/null
}
# The code: file|fn for every call on a line that is not a comment.
: > "$_m2_code"
_m2_list="${TMPDIR:-/tmp}/harbor-m2-list.$$"
_m2_eng="$(_engines)"  # the hook engines are scanned as bin/ is (D-88, harbor#1272)
_m2_nl='
'
_m2_shells "$ROOT"/bin/* $_m2_eng > "$_m2_list"
while IFS= read -r f; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  # guard-lib DEFINES them; the linter names them to check them; a suite drives them.
  case "$b" in guard-lib.sh|lint-conventions.sh|*-test.sh) continue ;; esac
  for _m2_fn in floor_in_repo floor_repo_wires floor_engine_stand_down; do
    _m2_n="$(grep -E "(^|[^A-Za-z0-9_])${_m2_fn}([^A-Za-z0-9_]|\$)" "$f" 2>/dev/null \
      | grep -cvE '^[[:space:]]*#' || :)"
    [ "${_m2_n:-0}" -gt 0 ] || continue
    printf '%s|%s\n' "${f#"$ROOT"/}" "$_m2_fn" >> "$_m2_code"
    [ "$_m2_n" -eq 1 ] \
      || bad scope.stand-down-declared "${f#"$ROOT"/} calls $_m2_fn $_m2_n times — a row covers one stand-down, so a second call would inherit the first one's tier; keep one call per file and function"
  done
done < "$_m2_list"
while IFS='|' read -r _m2_f _m2_fn; do
  awk -F'|' -v f="$_m2_f" -v fn="$_m2_fn" '$1 == f && $2 == fn { hit = 1 } END { exit !hit }' "$_m2_rows" \
    || bad scope.stand-down-declared "$_m2_f stands down via $_m2_fn inside a governed repo, and CONTRACTS/marker.md does not declare it — add a row with its tier"
done < "$_m2_code"
while IFS='|' read -r _m2_f _m2_fn _m2_tier _m2_tk; do
  case "$_m2_tier" in
    project|engine|report) ;;
    constitutional)
      printf '%s' "$_m2_tk" | grep -qE 'harbor#[0-9]+' \
        || bad scope.stand-down-declared "$_m2_f is a CONSTITUTIONAL stand-down with no ticket — the five never yield (harbor#581), so name the ticket that owns this exception" ;;
    *) bad scope.stand-down-declared "$_m2_f declares tier '$_m2_tier' — it must be project, engine, report or constitutional" ;;
  esac
  awk -F'|' -v f="$_m2_f" -v fn="$_m2_fn" '$1 == f && $2 == fn { hit = 1 } END { exit !hit }' "$_m2_code" \
    || bad scope.stand-down-declared "CONTRACTS/marker.md declares $_m2_f standing down via $_m2_fn, and no such call exists — a stale row reads as coverage"
done < "$_m2_rows"
# The scope premise: nothing outside bin/ can reach any of them. Read from a
# file, not a pipe: `bad` inside `find | while` runs in a subshell, prints its
# line, and loses the FAIL it counted — a violation that cannot fail the run.
find "$ROOT" -type f -not -path "$ROOT/bin/*" -not -path '*/.git/*' -print0 2>/dev/null \
  | xargs -0 awk 'FNR == 1 { if (FILENAME ~ /\.sh$/ || $0 ~ /^#!.*[\/ ](ba|z|da|k)?sh([ \t]|$)/) print FILENAME; nextfile }' 2>/dev/null \
  > "$_m2_list"
while IFS= read -r f; do
  # The suite that drives floor_in_repo, exempt here as it was in bin/ (harbor#727).
  case "${f#$ROOT/}" in tests/floor/marker-test.sh) continue ;; esac
  case "$_m2_nl$_m2_eng$_m2_nl" in *"$_m2_nl$f$_m2_nl"*) continue ;; esac  # an engine, scanned above
  grep -qE '^[[:space:]]*(\.|source)[[:space:]].*guard-lib\.sh' "$f" 2>/dev/null \
    && bad scope.stand-down-declared "${f#$ROOT/} sources guard-lib.sh from outside bin/ and the hook engines — M2 scans only those, so widen it"
done < "$_m2_list"
say "  $(wc -l < "$_m2_rows" | tr -d ' ') stand-down site(s) declared, $(grep -c '|constitutional|' "$_m2_rows" || :) of them a constitutional exception."
rm -f "$_m2_rows" "$_m2_code" "$_m2_list"
}

# ── F14 · every .helm-* name in bin/ is classified, and the layers agree ─────
# harbor#779: 13 of the box's 20 .helm-* state files were session-writable,
# the salts, the Stop-gate state and the install stamp among them, because
# nothing said which of them the floor trusts. CONTRACTS/helm-state.md says it
# now, one row per name, and this rule holds that table to the code.
#
# BOTH DIRECTIONS, as M2 does: a name in bin/ with no row is unclassified, and
# a row no file in bin/ names reads as coverage it does not have.
#
# THE THREE LAYERS NAME EXACTLY THE INTEGRITY ROWS. guard-bash's FILES line,
# guard-selfedit's is_protected() and floor-deny's ADD list are each a copy of
# the integrity set. A row missing from one of them is the #779 defect again,
# and a name a layer protects that the table calls cache is a table that lies.
# A row that lives under <cfg>/bin/ is covered by each layer's bin/ arm instead.
#
# WHAT IT CANNOT DO. Whether a row's class is right is judgement. Text in a
# layer is not behaviour either: tests/guards/bash.state and selfedit.jsonl fire
# the real guards per row, and floor.install-test the applied deny list.
rule_F14() {
rule "admission.state-file-registered every .helm-* name in bin/ has a row in CONTRACTS/helm-state.md, and the three layers protect exactly its integrity rows (harbor#779)"
_f14_doc="$ROOT/CONTRACTS/helm-state.md"
if [ ! -f "$_f14_doc" ]; then
  bad admission.state-file-registered "CONTRACTS/helm-state.md is missing, so no .helm-* name can be classified"; return 0
fi
_f14_rows="${TMPDIR:-/tmp}/harbor-f14-rows.$$"; _f14_code="${TMPDIR:-/tmp}/harbor-f14-code.$$"
_f14_lay="${TMPDIR:-/tmp}/harbor-f14-lay.$$"
# name<TAB>where<TAB>class, one per row under "## The table".
awk '/^## The table/ { s = 1; next } s && /^## / { s = 0 }
     s && /^\| `\.helm-/ { split($0, c, "|"); for (i = 2; i <= 4; i++) gsub(/^[ \t]+|[ \t]+$|`/, "", c[i])
                           print c[2] "\t" c[3] "\t" c[4] }' "$_f14_doc" > "$_f14_rows"
[ -s "$_f14_rows" ] || bad admission.state-file-registered "CONTRACTS/helm-state.md has no rows under \"The table\""
awk -F'\t' '{ n[$1]++ } n[$1] == 2 { print $1 }' "$_f14_rows" > "$_f14_lay"
while IFS= read -r _f14_n; do bad admission.state-file-registered "CONTRACTS/helm-state.md has two rows for $_f14_n"; done < "$_f14_lay"
while IFS='	' read -r _f14_n _f14_w _f14_c; do
  case "$_f14_c" in integrity|cache|scratch) ;;
    *) bad admission.state-file-registered "CONTRACTS/helm-state.md classes $_f14_n as '$_f14_c': it must be integrity, cache or scratch" ;;
  esac
done < "$_f14_rows"
# _f14_names: every .helm-* token on stdin, one per line. A regex spells a dot
# as `\\.`, so backslashes before a dot go first: FILES names
# `\\.helm-instructions\\.sha256`, which is .helm-instructions.sha256.
_f14_names() {
  LC_ALL=C awk '{ gsub(/\\+\./, "."); s = $0
    while (match(s, /\.helm-[A-Za-z0-9_.-]*[A-Za-z0-9_]/)) { print substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }'
}
# The code: file<TAB>name for every name in any file under bin/, comments included.
: > "$_f14_code"
find "$ROOT/bin" -type f 2>/dev/null | LC_ALL=C sort > "$_f14_lay"
while IFS= read -r f; do
  _f14_names < "$f" | LC_ALL=C sort -u | while IFS= read -r _f14_n; do
    printf '%s\t%s\n' "${f#"$ROOT"/}" "$_f14_n"; done >> "$_f14_code"
done < "$_f14_lay"
while IFS='	' read -r _f14_f _f14_n; do
  awk -F'\t' -v n="$_f14_n" '$1 == n { hit = 1 } END { exit !hit }' "$_f14_rows" \
    || bad admission.state-file-registered "$_f14_f names $_f14_n, which has no row in CONTRACTS/helm-state.md; classify it integrity, cache or scratch"
done < "$_f14_code"
while IFS='	' read -r _f14_n _f14_w _f14_c; do
  awk -F'\t' -v n="$_f14_n" '$2 == n { hit = 1 } END { exit !hit }' "$_f14_code" \
    || bad admission.state-file-registered "CONTRACTS/helm-state.md has a row for $_f14_n and no file in bin/ names it; a stale row reads as coverage"
done < "$_f14_rows"
# The layers: layer<TAB>name for every .helm-* name each one protects.
: > "$_f14_lay"
_f14_layer() { # <layer> <file> <awk program printing the protecting lines>
  if [ ! -f "$2" ]; then bad admission.state-file-registered "${2#"$ROOT"/} is missing, so the $1 layer cannot be checked"; return 0; fi
  awk "$3" "$2" | _f14_names | LC_ALL=C sort -u | while IFS= read -r _f14_n; do
    printf '%s\t%s\n' "$1" "$_f14_n"; done >> "$_f14_lay"
}
_f14_layer guard-bash "$ROOT/bin/guard-bash.sh" '/^FILES="/ { print }'
_f14_layer guard-selfedit "$ROOT/bin/guard-selfedit.sh" '/^is_protected\(\) *\{/ { s = 1; next } s && /^\}/ { s = 0 } s && !/^[ \t]*#/ { sub(/[ \t]#.*$/, ""); print }'
_f14_layer floor-deny "$ROOT/bin/floor-deny.sh" "/^ADD='\\[/ { s = 1; next } s && /^\\]'/ { s = 0 } s { print }"
while IFS='	' read -r _f14_n _f14_w _f14_c; do
  [ "$_f14_c" = integrity ] || continue
  case "$_f14_w" in "<cfg>/bin/"*) continue ;; esac
  for _f14_l in guard-bash guard-selfedit floor-deny; do
    awk -F'\t' -v l="$_f14_l" -v n="$_f14_n" '$1 == l && $2 == n { hit = 1 } END { exit !hit }' "$_f14_lay" \
      || bad admission.state-file-registered "$_f14_n is an integrity row and $_f14_l does not protect it"
  done
done < "$_f14_rows"
while IFS='	' read -r _f14_l _f14_n; do
  _f14_c="$(awk -F'\t' -v n="$_f14_n" '$1 == n { print $3; exit }' "$_f14_rows")"
  [ "$_f14_c" = integrity ] \
    || bad admission.state-file-registered "$_f14_l protects $_f14_n, which CONTRACTS/helm-state.md classes as '${_f14_c:-no row}'; protect only integrity rows"
done < "$_f14_lay"
say "  $(wc -l < "$_f14_rows" | tr -d ' ') .helm-* name(s) classified, $(awk -F'\t' '$3 == "integrity"' "$_f14_rows" | wc -l | tr -d ' ') of them integrity."
rm -f "$_f14_rows" "$_f14_code" "$_f14_lay"
}

# ── F15 · no script a hook runs resolves its own directory through $(dirname) ─
# harbor#813: `DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"` is the SESSION's cwd when the
# inner $(dirname) yields nothing (a failed fork under process pressure, or dirname off PATH), and
# the script then sources ./guard-lib.sh from whatever repo the session stands in. harbor#810 moved
# the guards to `${0%/*}`, which forks nothing; this holds every script a hook runs to the same.
#
# THE SET IS DERIVED, NEVER LISTED, from what the installers wire:
#   wired   every argv word of a floor_hooks table row, every "/bin/sh $DIR/bin/X" (or "/bin/sh $V"
#           with V="$DIR/bin/X") an installer composes as a harness command, and the run: script of
#           every box pack an installer that names inject.d/box installs;
#   closed  what those execute or source (`.`, sh, bash, exec) through a path ending in a file
#           beside them or in bin/, outside a quoted string: a hint that only NAMES a command runs nothing.
#   declared a hook the box runs that no installer wires (worklog-push) is a row in
#           CONTRACTS/hooks-external.tsv, read here as one more wiring.
# A repo pack's scripts (.claude/inject.d) are out: they run the session repo's own code, so a file
# planted beside them has the same author. The behaviour is pinned by floor-test B9c.
rule_F15() {
rule "admission.no-dirname no script a hook runs resolves its own directory through \$(dirname) (harbor#813)"
_f15t="${TMPDIR:-/tmp}"; _f15t="${_f15t%/}/harbor-f15.$$"; rm -rf "$_f15t"; mkdir -p "$_f15t"
_f15_code() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1"; }  # comments blanked, lines kept
: > "$_f15t/wired"
for _f15i in "$ROOT"/bin/*install*.sh; do
  [ -f "$_f15i" ] || continue
  _f15_code "$_f15i" | awk -v src="${_f15i#"$ROOT"/}" '
    /\(\) *\{ *cat <<.?ROWS.?$/ { t = 1; next }
    t && /^ROWS$/ { t = 0; next }
    t { if ($0 ~ /^[A-Z][A-Za-z]+;/ && split($0, f, ";") >= 3) { m = split(f[3], a, " ")
          for (i = 1; i <= m; i++) if (a[i] !~ /^-/) print "bin/" a[i] "\t" src }
        next }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*="?[$][{]?DIR[}]?\/bin\/[A-Za-z0-9_.-]+"?[[:space:]]*$/ {
      k = $0; sub(/^[[:space:]]*/, "", k); v = k; sub(/=.*/, "", k); sub(/^[^=]*=["]?[$][{]?DIR[}]?\/bin\//, "", v)
      sub(/["]?[[:space:]]*$/, "", v); PV[k] = v }
    { l = $0
      while (match(l, /(=|--arg[[:space:]]+[A-Za-z_]+[[:space:]]+)"\/bin\/sh[[:space:]]+(\\")?[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?(\/bin\/[A-Za-z0-9_.-]+)?/)) {
        s = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
        sub(/^.*"\/bin\/sh[[:space:]]+(\\")?[$][{]?/, "", s)
        if (index(s, "/bin/")) { sub(/^[^\/]*\/bin\//, "", s); print "bin/" s "\t" src }
        else { sub(/[}]$/, "", s); U[s] = 1 } } }
    END { for (k in U) if (k in PV) print "bin/" PV[k] "\t" src }' >> "$_f15t/wired"
  if _f15_code "$_f15i" | grep -q 'inject\.d/box'; then
    for _f15p in "$ROOT"/inject.d/box/*.md; do
      [ -f "$_f15p" ] || continue
      _f15r="$(awk 'NR == 1 && !/^---/ { exit } NR > 1 && /^---/ { exit } /^run:[[:space:]]*/ { sub(/^run:[[:space:]]*/, ""); print; exit }' "$_f15p")"
      [ -z "$_f15r" ] || printf 'inject.d/box/%s\t%s\n' "$_f15r" "${_f15i#"$ROOT"/} (box pack ${_f15p##*/})" >> "$_f15t/wired"
    done
  fi
done
# A hook engine's manifest is its wiring (D-88): bin/deploy-hooks.sh renders a command for each wire row.
for _f15m in "$ROOT"/hooks/*/manifest.tsv; do
  [ -f "$_f15m" ] && grep -q '^wire	' "$_f15m" || continue
  _f15d="${_f15m%/manifest.tsv}"; printf '%s\t%s\n' "${_f15d#"$ROOT"/}/${_f15d##*/}.sh" "${_f15m#"$ROOT"/}" >> "$_f15t/wired"
done
_f15_x="$ROOT/CONTRACTS/hooks-external.tsv"
if [ -f "$_f15_x" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$_f15_x" > "$_f15t/ext"
  while IFS='	' read -r _f15s _f15e _f15y; do  # not in a pipe: bad() counts in this shell
    [ -n "$_f15e" ] || bad admission.no-dirname "CONTRACTS/hooks-external.tsv: $_f15s names no event"
    printf '%s\t%s\n' "$_f15s" "CONTRACTS/hooks-external.tsv, $_f15e" >> "$_f15t/wired"
  done < "$_f15t/ext"
fi
# The closure: <rel> of each file a member runs or sources, judged on code outside quotes.
_f15_runs() { # <rel>
  _f15_code "$ROOT/$1" | awk -v me="$1" '
    function outside(l, p,   i, c, sp) { sp = 0; ST[0] = "n"
      for (i = 1; i < p; i++) { c = substr(l, i, 1)
        if (ST[sp] == "s") { if (c == "\047") sp--; continue }
        if (c == "\\") { i++; continue }
        if (ST[sp] == "d") { if (c == "\"") sp--; else if (c == "$" && substr(l, i + 1, 1) == "(") { ST[++sp] = "n"; i++ }; continue }
        if (c == "\"") ST[++sp] = "d"; else if (c == "\047") ST[++sp] = "s"
        else if (c == "(") ST[++sp] = "n"; else if (c == ")" && sp > 0) sp-- }
      return ST[sp] == "n" }
    function tail(v) { sub(/["]?[[:space:]]*$/, "", v); return v }
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=.*\/[A-Za-z0-9_.-]+\.sh"?[[:space:]]*$/ {
      k = $0; sub(/^[[:space:]]*/, "", k); v = k; sub(/=.*/, "", k); V[k] = tail(v) }
    { l = $0; o = 0
      while (match(substr(l, o + 1), /(^|[;&|({`[:space:]])(\.|sh|bash|exec)[[:space:]]+"?[$][{]?[A-Za-z_][A-Za-z0-9_]*[}]?[^;&|)[:space:]"]*"?/)) {
        p = o + RSTART; s = substr(l, p, RLENGTH); o = p + RLENGTH - 1
        if (substr(s, 1, 1) !~ /[.a-z]/) { p++; s = substr(s, 2) }
        if (!outside(l, p)) continue
        sub(/^(\.|sh|bash|exec)[[:space:]]+"?/, "", s); s = tail(s)
        if (s ~ /\//) f = s; else { sub(/^[$][{]?/, "", s); sub(/[}]$/, "", s); if (!(s in V)) continue; f = V[s] }
        b = f; sub(/.*\//, "", b); if (b !~ /^[A-Za-z0-9_.-]+\.sh$/) continue
        print (f ~ /\/bin\/[^\/]*$/ ? "bin" : "here") "\t" b } }' | while IFS='	' read -r _f15w _f15b; do
    _f15d="${1%/*}"
    if [ "$_f15w" = here ] && [ -f "$ROOT/$_f15d/$_f15b" ]; then printf '%s/%s\n' "$_f15d" "$_f15b"
    elif [ -f "$ROOT/bin/$_f15b" ]; then printf 'bin/%s\n' "$_f15b"; fi
  done
}
awk -F'\t' '!s[$1]++' "$_f15t/wired" > "$_f15t/set"
cp "$_f15t/set" "$_f15t/todo"
while [ -s "$_f15t/todo" ]; do
  : > "$_f15t/next"
  while IFS='	' read -r _f15m _f15why; do
    [ -f "$ROOT/$_f15m" ] || { bad admission.no-dirname "$_f15m is wired by $_f15why and does not exist"; continue; }
    _f15_runs "$_f15m" | while IFS= read -r _f15c; do
      awk -F'\t' -v c="$_f15c" '$1 == c { f = 1 } END { exit !f }' "$_f15t/set" "$_f15t/next" 2>/dev/null \
        || printf '%s\t%s\n' "$_f15c" "run by $_f15m" >> "$_f15t/next"
    done
  done < "$_f15t/todo"
  cat "$_f15t/next" >> "$_f15t/set"; mv "$_f15t/next" "$_f15t/todo"
done
while IFS='	' read -r _f15m _f15why; do
  [ -f "$ROOT/$_f15m" ] || continue
  case "$_f15m" in *.sh) ;; *) continue ;; esac
  _f15_hit="$(_f15_code "$ROOT/$_f15m" | awk '/(\$\(|`)[[:space:]]*dirname[[:space:]]+(--[[:space:]]+)?["]?[$][{]?0([^0-9A-Za-z_]|$)/ { printf "%s%d", (n++ ? "," : ""), NR }')"
  [ -z "$_f15_hit" ] || bad admission.no-dirname "$_f15m:$_f15_hit resolves its own directory through \$(dirname) and a hook runs it ($_f15why): a failed fork or a dirname off PATH makes it the session's cwd — use \${0%/*} (harbor#810)"
done < "$_f15t/set"
say "  $(grep -c . "$_f15t/set" | tr -d ' ') script(s) a hook runs, $(grep -c . "$_f15t/wired" | tr -d ' ') wiring(s): $(cut -f1 "$_f15t/set" | sed 's#.*/##' | LC_ALL=C sort | tr '\n' ' ')"
rm -rf "$_f15t"
}

# ── C3 · every test suite is actually wired into CI ────────────────────────
# CONTRACTS/README.md claimed `bin/marker-test.sh` runs in "CI + on demand"
# within ten minutes of the file being written, and it did not — the same
# claim-without-mechanism that made this whole linter necessary. A suite nobody
# runs is a suite that is already broken; this makes the claim checkable.
rule_C3() {
rule "test.suite-in-manifest every tracked *-test.sh is in the suite manifest, and the manifest is consumed"
# THE GUARANTEE IS UNCHANGED — no suite sits silently outside CI. What changed is
# where the list lives. Requiring each suite to be NAMED in governance.yml made
# adding one a human round-trip forever, because permissions.deny covers
# .github/workflows/** and that deny exists to stop an agent rewriting the gate
# that judges it (harbor#61). CONTRACTS/suites.txt is tracked, agent-editable and
# not a workflow file.
#
# BOTH DIRECTIONS, or the list rots: a new suite missing from the manifest is the
# original defect, and a manifest line naming a deleted file is a suite CI thinks
# it is running and is not.
# CI is defined in the shared section at the top (harbor#537) — another rule reads it.
# _MAN is defined in the shared section at the top (harbor#537) — another rule reads it.
# _man_list is defined in the shared section at the top (harbor#537) — another rule reads it.
# AND EVERY *.test.sh: a D-88 engine's suite and 157 others are dot-named, and a new unlisted one sat outside
# CI with this rule green (harbor#1272, measured adding a probe engine).
# EVERY *-test.sh IN THE TREE, NOT ONLY bin/ (harbor#695). The loop was
# `"$ROOT"/bin/*-test.sh`, so a skill's own suite was invisible to the rule that
# promises no suite sits outside CI: a skill's bin/*-preflight-test.sh plants
# broken fixtures and no job ever ran it, with this rule green. A suite in bin/
# is listed by NAME; anywhere else, by its path from the repo root, which
# bin/suite-select.sh --run resolves the same way.
#
# ONE PREFIX IS EXEMPT, AND IT IS DATA: EVALS-DATA/ holds eval corpora and the
# fixtures an eval shipped with (e5trap's gate-test.sh writes a hooktest dir
# beside itself). They are evidence for EVALS.md, run by the eval that owns
# them, never a gate on this repo's code.
if [ -f "$_MAN" ]; then
  _c3l="${TMPDIR:-/tmp}/c3.$$"
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$ROOT" ls-files -- '*-test.sh' '*.test.sh' > "$_c3l" 2>/dev/null || :
  else
    ( cd "$ROOT" && find . \( -name '*-test.sh' -o -name '*.test.sh' \) -not -path './.git/*' | sed 's#^\./##' ) > "$_c3l"
  fi
  while IFS= read -r _c3p; do
    case "$_c3p" in ''|EVALS-DATA/*) continue ;; esac
    [ -f "$ROOT/$_c3p" ] || continue
    case "$_c3p" in bin/*/*) _c3k="$_c3p" ;; bin/*) _c3k="${_c3p#bin/}" ;; *) _c3k="$_c3p" ;; esac
    _man_list | grep -Fxq "$_c3k" || bad test.suite-in-manifest "test suite missing from CONTRACTS/suites.txt: $_c3p"
  done < "$_c3l"
  rm -f "$_c3l"
  while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    case "$_b" in */*) _bp="$_b" ;; *) _bp="bin/$_b" ;; esac
    [ -f "$ROOT/$_bp" ] || bad test.suite-in-manifest "CONTRACTS/suites.txt names a suite that does not exist: $_bp"
  done <<C3MAN
$(_man_list)
C3MAN
else
  bad test.suite-in-manifest "CONTRACTS/suites.txt is missing — the suite manifest is the source of truth"
fi
# A MANIFEST NOBODY READS IS DECORATION. Until the operator lands the workflow
# patch that iterates it, the old per-suite wiring is still what actually runs,
# so accept EITHER shape and never less than one of them. Dropping this half
# early would let a suite fall out of CI while the linter stayed green — exactly
# the silence C3 exists to prevent.
if [ -f "$CI" ]; then
  if grep -q 'CONTRACTS/suites.txt' "$CI"; then
    :
  else
    # EVERY MANIFEST ENTRY, PATH ENTRIES INCLUDED (Codex on #701): walking only
    # bin/*-test.sh here let a skill-local suite sit in the manifest, unnamed by
    # a workflow that does not read the manifest, with this rule green.
    while IFS= read -r _b; do
      [ -n "$_b" ] || continue
      case "$_b" in */*) _bp="$_b" ;; *) _bp="bin/$_b" ;; esac
      grep -qF -- "$_b" "$CI" \
        || bad test.suite-in-manifest "suite in the manifest but not run by CI, and CI does not read the manifest: $_bp"
    done <<C3CI
$(_man_list)
C3CI
  fi
fi
}

rule_C4() {
rule "test.ci-tools-probed every tool CI preflights is probed by doctor.sh (one dependency list, not two)"
# Since governance.yml moved to a self-hosted runner, "is this binary present"
# is answered in two places: preflight fails the run, doctor.sh tells you what
# breaks without it. Two hand-maintained lists of the same fact drift silently
# and read correctly the whole time — the T-rule failure mode, in shell. This
# does not merge them; it makes the divergence a build failure.
DOC="$ROOT/bin/doctor.sh"
if [ -f "$CI" ] && [ -f "$DOC" ]; then
  # the `for t in ... ; do` list inside preflight's existence check
  _tools="$(sed -n 's/.*for t in \(.*\); do.*/\1/p' "$CI" | head -1)"
  if [ -z "$_tools" ]; then
    bad test.ci-tools-probed "could not find preflight's tool list in governance.yml — the rule is now blind, which is worse than absent"
  else
    for t in $_tools; do
      grep -qE "^probe $t([[:space:]]|$)" "$DOC" \
        || bad test.ci-tools-probed "CI preflights '$t' but bin/doctor.sh does not probe it — a fresh box passes doctor and fails CI"
    done
  fi
fi
}

# ── C5 · every suite declares which changes select it (CI-2, harbor#150) ────
# The declarations decide which suites DO NOT RUN, and a defect there is silent
# in the one direction that matters: the run comes back green and shorter, which
# reads as an improvement rather than as coverage going away. So the list is
# checked the same way C3 checks the manifest — BOTH DIRECTIONS, because a suite
# with no declaration is one nobody decided about, and a declaration naming a
# suite that no longer exists is a narrowing nobody can see is dead.
rule_C5() {
rule "test.suite-paths every manifest suite declares its selecting paths (CONTRACTS/suite-paths.txt)"
_DECL="$ROOT/CONTRACTS/suite-paths.txt"
_decl_keys() { awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$_DECL" 2>/dev/null; }
if [ ! -f "$_DECL" ]; then
  bad test.suite-paths "CONTRACTS/suite-paths.txt is missing — the change-class table is the source of truth for what CI may skip"
elif [ -f "$_MAN" ]; then
  # HEREDOCS, NOT PIPES, throughout: `bad` increments FAIL, and a `| while` loop
  # runs in a subshell where that increment is discarded — the rule would report
  # every violation on stderr and still exit 0. C3 above is shaped this way for
  # the same reason.
  while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    awk -v k="$_b" '$1 == k { f = 1 } END { exit !f }' "$_DECL" \
      || bad test.suite-paths "suite declares no paths in CONTRACTS/suite-paths.txt: $_b"
  done <<C5MAN
$(_man_list)
C5MAN
  while IFS= read -r _k; do
    [ -n "$_k" ] || continue
    case "$_k" in '@no-suite') continue ;; esac
    _man_list | grep -Fxq "$_k" \
      || bad test.suite-paths "CONTRACTS/suite-paths.txt declares a suite the manifest does not list: $_k"
  done <<C5DECL
$(_decl_keys)
C5DECL
  # A key with nothing after it reads as a declaration and behaves as an absent
  # one — the selector treats it as undeclared and runs the suite always, so the
  # file would claim a narrowing that is not happening.
  while IFS= read -r _k; do
    [ -n "$_k" ] || continue
    bad test.suite-paths "declares a key with no globs (write 'always' if that is what you mean): $_k"
  done <<C5EMPTY
$(awk '!/^[[:space:]]*(#|$)/ && NF < 2 { print $1 }' "$_DECL" 2>/dev/null)
C5EMPTY
  while IFS= read -r _k; do
    [ -n "$_k" ] || continue
    bad test.suite-paths "declared twice — the first line wins silently: $_k"
  done <<C5DUP
$(_decl_keys | sort | uniq -d)
C5DUP
  # Without it every changed path is unclassified, so every suite runs. That is
  # the SAFE failure, which is exactly why it needs saying out loud: the table
  # would be inert and CI would look unchanged.
  _decl_keys | grep -Fxq '@no-suite' \
    || bad test.suite-paths "no @no-suite line — every path is then unclassified and nothing is ever narrowed"
fi
# NOT A VIOLATION, because the workflow edit is an operator round-trip by design
# (permissions.deny covers .github/workflows/**). But an inert table that reads
# as a working one is how a repo ends up believing it has a control it does not,
# so it is reported every run until the patch lands.
if [ -f "$CI" ] && [ -f "$_DECL" ] && ! grep -q 'suite-select' "$CI"; then
  _adv test.suite-paths governance.yml; printf '  ADVISORY [test.suite-paths] governance.yml does not call bin/suite-select.sh yet — the declarations are inert until patches/governance-change-class.patch.md is applied\n'
fi
}

# ── C6 · every prove target is gate-shaped ─────────────────────────────────
# WHAT GOES WRONG WITHOUT IT. `skills/test-strength/bin/prove.sh` refuses a
# declaration that is not gate-shaped — no control, a control copied from the
# seed, a mutator name that does not exist — but it only refuses it WHEN SOMEONE
# RUNS IT. The real sweep is operator-invoked or scheduled, not per-PR, so a
# declaration that loses its control in an edit would sit green in the tree
# until the next full run, and the run before it would still be quoted.
# C6 is the same set of rules paid for at lint speed, on every change.
#
# THE MUTATOR LIST IS READ, NEVER RESTATED. `prove.sh --mutators` is the only
# listing of the library; a copy of it here would be a second source of truth
# for a fact that changes when the engine changes, which is the T-rule failure
# mode this whole file exists to prevent.
#
# WHAT IT DELIBERATELY DOES NOT ASSERT. That every checker in the repo has a
# target — that is unmeetable today and a guard that blocks ordinary work gets
# switched off. The census lives in `prove.sh --coverage`, which reports and
# does not fail. And it cannot assert that a control is a GOOD control: it
# checks that `varies:` and `why:` exist, never that they are true. A reviewer
# reads those; no lint can.
rule_C6() {
rule "test.prove-target-shape every prove target is gate-shaped (skills/test-strength/targets/)"
_PT="$ROOT/skills/test-strength/targets"
_PROVE="$ROOT/skills/test-strength/bin/prove.sh"
if [ -d "$_PT" ]; then
  if [ ! -x "$_PROVE" ] && [ ! -f "$_PROVE" ]; then
    bad test.prove-target-shape "targets are declared but skills/test-strength/bin/prove.sh is missing — the declarations are inert"
  else
    # HEREDOCS, NOT PIPES. `bad` increments FAIL, and a `| while` loop runs in a
    # subshell where that increment is discarded — every violation on stderr and
    # exit 0. C3 and C5 above are shaped this way for the same reason.
    _c6_lib="$(sh "$_PROVE" --mutators 2>/dev/null)"
    [ -n "$_c6_lib" ] || bad test.prove-target-shape "prove.sh --mutators printed nothing — C6 cannot resolve a mutator name and is now blind, which is worse than absent"
    _c6_names=""
    while IFS= read -r _t; do
      [ -n "$_t" ] || continue
      _b="$(basename "$_t" .target)"

      _c6_get() { awk -v k="$1" '$1 == k { sub(/^[^[:space:]]*[[:space:]]*/, ""); print; exit }' "$_t"; }
      _c6_cnt() { awk -v k="$1" '$1 == k { n++ } END { print n + 0 }' "$_t"; }

      for _k in target subject-kind lane cost seed place checker-cmd green red; do
        _n="$(_c6_cnt "$_k")"
        [ "$_n" -eq 1 ] || bad test.prove-target-shape "$_b: directive '$_k' appears $_n time(s), want exactly 1"
      done

      [ "$(_c6_get target)" = "$_b" ] \
        || bad test.prove-target-shape "$_b: target name '$(_c6_get target)' does not equal the file basename"
      # THE KIND LIST IS READ, NEVER RESTATED — the same rule this file already
      # states for the mutator library, and it was missed here once: the engine
      # grew `trigger-routing`, this line still named two kinds, and a lawful
      # target became a lint violation while the engine ran it happily. Two
      # spellings of one predicate drift in silence, and the copy always reads
      # correct. `tests/checks/lint.suites-test.sh` pins the pair against the engine so a third
      # kind cannot reintroduce the divergence.
      _c6_kind="$(_c6_get subject-kind)"
      printf '%s\n' "$_c6_lib" | awk '{ print $1 }' | /usr/bin/grep -qx -- "$_c6_kind" \
        || bad test.prove-target-shape "$_b: unknown subject-kind '$_c6_kind' — prove.sh --mutators knows: $(printf '%s\n' "$_c6_lib" | awk '{ print $1 }' | sort -u | tr '\n' ' ')"
      case "$(_c6_get lane)" in fast|deep) ;;
        *) bad test.prove-target-shape "$_b: lane must be fast or deep, got '$(_c6_get lane)'" ;; esac
      case "$(_c6_get cost)" in ''|*[!0-9]*) bad test.prove-target-shape "$_b: cost must be an integer" ;; esac

      # No duplicate target NAME across files, and no duplicate id within one.
      case " $_c6_names " in *" $_b "*) bad test.prove-target-shape "$_b: two files declare the same target name" ;; esac
      _c6_names="$_c6_names $_b"
      _dupid="$(awk '$1 == "plant" || $1 == "manual" || $1 == "control" || $1 == "mutate" { print $2 }' "$_t" \
                | sort | uniq -d | tr '\n' ' ')"
      [ -z "$(printf '%s' "$_dupid" | tr -d '[:space:]')" ] \
        || bad test.prove-target-shape "$_b: duplicate id(s) within the target: $_dupid"

      # Every seed and control file resolves. `repo:` is the repo root, absolute
      # is itself, anything else is relative to the .target file — one rule,
      # stated once in CONTRACTS/prove-targets.md and applied here.
      _tdir="$(dirname "$_t")"
      _c6_path() {
        case "$1" in
          repo:*) printf '%s' "$ROOT/${1#repo:}" ;;
          /*)     printf '%s' "$1" ;;
          *)      printf '%s' "$_tdir/$1" ;;
        esac
      }
      _sd="$(_c6_get seed)"
      [ -f "$(_c6_path "$_sd")" ] || bad test.prove-target-shape "$_b: seed does not exist: $_sd"

      # AT LEAST ONE CONTROL, AND EVERY CONTROL CARRIES ITS TWO REASONS. An
      # over-broad rule that refuses everything kills every mutant and scores a
      # flawless recall; only a valid-but-unusual legitimate input can see it,
      # and a mutant sweep can never generate one.
      _nc="$(_c6_cnt control)"
      [ "$_nc" -ge 1 ] || bad test.prove-target-shape "$_b: no control declared — a target without a control is not a target"

      while IFS= read -r _cf; do
        [ -n "$_cf" ] || continue
        [ -f "$(_c6_path "$_cf")" ] || bad test.prove-target-shape "$_b: control names a file that does not exist: $_cf"
      done <<C6CF
$(awk '$1 == "control" && $3 == "file" { print $4 }' "$_t")
C6CF

      # `varies:` and `why:` are continuations, so they are counted against the
      # directive they follow rather than globally — a file with three controls
      # and one shared why: would otherwise pass.
      _miss="$(awk '
        function flush(  ) {
          if (last == "control" && (!v || !w)) print "control " id " is missing " (!v ? "varies:" : "") (!v && !w ? " and " : "") (!w ? "why:" : "")
          if (last == "plant" && !w) print "plant " id " is missing why:"
          last = ""; v = 0; w = 0
        }
        /^[[:space:]]/ {
          if ($0 ~ /^[[:space:]]+varies:[[:space:]]*[^[:space:]]/) v = 1
          if ($0 ~ /^[[:space:]]+why:[[:space:]]*[^[:space:]]/)    w = 1
          next
        }
        { flush(); if ($1 == "control" || $1 == "plant") { last = $1; id = $2 } }
        END { flush() }
      ' "$_t")"
      while IFS= read -r _m; do
        [ -n "$_m" ] || continue
        bad test.prove-target-shape "$_b: $_m"
      done <<C6WHY
$_miss
C6WHY

      # A manual with no description is an UNPROVEN line that says nothing.
      while IFS= read -r _m; do
        [ -n "$_m" ] || continue
        bad test.prove-target-shape "$_b: manual $_m has no description"
      done <<C6MAN
$(awk '$1 == "manual" && NF < 3 { print $2 }' "$_t")
C6MAN

      # Every mutate names a mutator the ENGINE has, for the target's own kind.
      _kind="$(_c6_get subject-kind)"
      while IFS= read -r _mn; do
        [ -n "$_mn" ] || continue
        printf '%s\n' "$_c6_lib" | awk -v k="$_kind" -v n="$_mn" '$1 == k && $2 == n { f = 1 } END { exit !f }' \
          || bad test.prove-target-shape "$_b: mutate names '$_mn', which prove.sh --mutators does not list for $_kind"
      done <<C6MUT
$(awk '$1 == "mutate" { print $3 }' "$_t")
C6MUT

      # A checker-cmd naming a script that has moved is a gate pointed at
      # nothing, and it reads exactly like a working one until someone runs it.
      while IFS= read -r _tok; do
        [ -n "$_tok" ] || continue
        case "$_tok" in \$WORK*|\$\{WORK\}*|\$TDIR*|\$\{TDIR\}*) continue ;; esac
        [ -f "$ROOT/$_tok" ] || [ -f "$_tok" ] \
          || bad test.prove-target-shape "$_b: checker-cmd names a script that does not resolve: $_tok"
      done <<C6CC
$(awk '$1 == "checker-cmd" { for (i = 2; i <= NF; i++) if ($i ~ /\.sh$/) print $i }' "$_t")
C6CC
    done <<C6T
$(find "$_PT" -maxdepth 1 -name '*.target' -type f | sort)
C6T
  fi
fi
}

# ── C7 · the ledger's guard enum equals the guards that write to it ────────
rule_C7() {
rule "audit.decision-token-listed every guard token logged is in FLOOR_OBS_GUARDS, and vice versa (harbor#320)"
# THE RULE ALREADY EXISTED IN PROSE AND FAILED TWICE ANYWAY. guard-lib.sh's own
# comment says "EVERY GUARD THAT LOGS MUST BE NAMED HERE" and records guard-cloud
# and guard-destroy filing 745 decisions as g=other before anyone noticed. It then
# happened again to guard-deliverables, whose 1,805 records were the ENTIRE `other`
# bucket on this box when this rule was written -- so the catch-all that exists to
# reveal an unknown writer contained no unknown writer at all, and could not have
# revealed one. Two instances of one defect against a written rule is the
# definition of a rule with no mechanism, so here is the mechanism.
#
# BOTH DIRECTIONS, for C3's reason exactly. A token passed but not listed is the
# original defect: silent coercion to `other`, and a guard the census cannot see.
# A token listed but never passed is the dead dispatch arm the census exists to
# find -- an enum entry that outlived its guard reads, to every consumer, as a
# guard that is installed and has simply never fired.
#
# LITERAL CALL SITES ONLY, and *-test.sh is excluded on purpose. A suite proving
# the coercion path works MUST pass a token that is not in the enum, so scanning
# them would make this rule fire on the one file whose job is to falsify it --
# a guard that blocks correct work gets switched off (§2.11). A `$VAR` token is
# skipped for the same reason in the other direction: it is not knowable here,
# and guessing would be a finding the author cannot act on.
_GL="$ROOT/bin/guard-lib.sh"
if [ -f "$_GL" ]; then
  _enum="$(sed -n "s/^FLOOR_OBS_GUARDS='\(.*\)'.*/\1/p" "$_GL" | head -1)"
  if [ -z "$_enum" ]; then
    bad audit.decision-token-listed "bin/guard-lib.sh has no readable FLOOR_OBS_GUARDS line — the ledger's guard enum is the source of truth and could not be parsed"
  else
    # COMMAND POSITION, NOT MERE PRESENCE, and the first draft of this rule proves
    # why. Matching the bare name anywhere on a non-comment line reported three
    # violations on its first run -- `refused` and `refuses` from failure-capture.sh
    # PROSE ("...means floor_log_decision refused every write"), and `but` from THIS
    # RULE'S OWN MESSAGE STRING, which the linter scans along with everything else.
    # Every one of them was a token nobody could act on, in a file nobody had
    # broken. So the name must open a command: at line start, or straight after a
    # `;`, `{`, `&&`, `||`, `(` or `!`. Prose is preceded by a word or a quote and
    # is excluded by construction rather than by a list of exceptions.
    _sites() {
      grep -rhE --exclude='*-test.sh' \
           '(^|[;{}&|()!])[[:space:]]*floor_log_decision +[a-z0-9-]+' \
           "$ROOT/bin" "$ROOT/hooks" 2>/dev/null \
        | grep -vE '^[[:space:]]*#' \
        | sed -E 's/.*floor_log_decision +([a-z0-9-]+).*/\1/'
    }
    # → direction 1: passed but not listed.
    for _tok in $(_sites | sort -u); do
      case " $_enum " in
        *" $_tok "*) ;;
        *) bad audit.decision-token-listed "guard token '$_tok' is passed to floor_log_decision but is NOT in FLOOR_OBS_GUARDS — every record it writes is silently filed as g=other" ;;
      esac
    done
    # → direction 2: listed but never passed.
    _seen="$(_sites | sort -u)"
    for _tok in $_enum; do
      case "
$_seen
" in
        *"
$_tok
"*) ;;
        *) bad audit.decision-token-listed "FLOOR_OBS_GUARDS lists '$_tok' but no guard passes it to floor_log_decision — a dead dispatch arm reads as a guard that never fires" ;;
      esac
    done
  fi
fi
}

# ── C8 · a tool nothing runs is a DECLARED state, never a silent one ────────
# harbor#466, generalised from #462. `bin/reference-check.sh` was built for a
# real defect on 2026-08-03, was correct about what it watched, and NOTHING EVER
# RAN IT — no hook, no plist, no CI job, only a line in HANDOFF.md naming a
# command a human types. Nobody typed it. Sixteen scripts were in that state and
# none of them was visible as being in it.
#
# CHECKS.md registers what is SCHEDULED. This registers the opposite: what is
# built, asserts something, and is wired to nothing. Both directions, like C3 —
# a tool that quietly loses its last caller must show up here, and a line for a
# tool that has since GAINED one is a stale entry nobody can see is dead.
#
# THE PREDICATE, AND WHAT IT DELIBERATELY IS NOT. "Called" means: some file that
# is not a test names this script in COMMAND POSITION — after `sh`/`bash`/`exec`,
# or as the tail of a path. A mention is not a call (module-shape.sh encodes the
# same distinction, for the same reason), and a TEST calling a tool is not a
# caller at all — CI proving the instrument works while nothing points it at the
# real subject IS the #466 defect, so counting a suite as a caller would make
# the rule endorse exactly what it exists to catch.
#
# The surface is what runs ITSELF: CI, launchd, hooks, inject packs, and other
# non-test scripts. It also reads the two places an operator's typing becomes a
# call to a bin/ tool: the dispatcher `bin/harbor` (its VERBS rows are wirings,
# and it has no extension, so it is named by path) and the `justfile` (its
# recipes, through S5's parser, _justfile_bin_paths; harbor#474). `commands/` and
# `plugins/` are deliberately NOT on it.
#
# ONE PREDICATE ANSWERS BOTH DIRECTIONS, which is what makes the rule fixable.
# If the two halves asked the question differently, a script could be "idle" to
# one and "called" to the other, and then BOTH a manifest line and its absence
# would be violations — a false positive with no edit that clears it, which is
# the shape No.2.11 says gets a gate switched off. Here the manifest is exactly
# the complement of the predicate, so every violation names one line to add or
# one to delete.
rule_C8() {
rule "lint.tool-has-caller every bin/ tool has a caller or a declared reason it has none (harbor#466)"
_C8_MAN="$ROOT/CONTRACTS/idle-tools.txt"
_C8_N="${TMPDIR:-/tmp}/c8-names.$$"
_C8_C="${TMPDIR:-/tmp}/c8-called.$$"
_C8_D="${TMPDIR:-/tmp}/c8-declared.$$"
if [ -f "$_C8_MAN" ]; then
  for _f in "$ROOT"/bin/*.sh; do
    [ -f "$_f" ] || continue
    case "${_f##*/}" in *-test.sh) continue ;; esac
    printf '%s\n' "${_f##*/}"
  done > "$_C8_N"
  awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$_C8_MAN" | sort -u > "$_C8_D"
  # ONE awk over the whole surface, driven from the TOKENS on each line rather
  # than from the 92 names: the name-driven shape is 92 × every line of every
  # file, on a linter that runs at every commit. `-print0`/`xargs -0` because a
  # path is not a word.
  # hooks/ prose is not a call: its READMEs quote commands for a reader (D-88, harbor#1272). inject.d keeps its .md,
  # whose run: lines are real calls.
  find "$ROOT/.github/workflows" "$ROOT/launchd" "$ROOT/inject.d" \
       -type f -print0 2>/dev/null > "${TMPDIR:-/tmp}/c8-surf.$$"
  find "$ROOT/hooks" -type f ! -name '*.md' -print0 2>/dev/null >> "${TMPDIR:-/tmp}/c8-surf.$$"
  find "$ROOT/bin" -type f -name '*.sh' ! -name '*-test.sh' -print0 2>/dev/null \
       >> "${TMPDIR:-/tmp}/c8-surf.$$"
  # bin/harbor is named BY PATH: the glob above cannot see it (no extension), and it is the
  # dispatcher, the largest caller of bin/ there is (harbor#474). A path that is not a file prints nothing.
  find "$ROOT/bin/harbor" -type f -print0 2>/dev/null >> "${TMPDIR:-/tmp}/c8-surf.$$"
  { xargs -0 awk -v NAMES="$(tr '\n' ',' < "$_C8_N")" '
    BEGIN { k = split(NAMES, a, ","); for (i = 1; i <= k; i++) if (a[i] != "") names[a[i]] = 1 }
    /^[[:space:]]*#/ { next }                    # a comment is not a call
    {
      line = $0
      gsub(/<[^>]*>/, " ", line)                 # a plist wraps its argv in tags
      m = split(line, F, /[[:space:]]+/)
      for (i = 1; i <= m; i++) {
        t = F[i]
        gsub(/^[^A-Za-z0-9_.$\/~-]+/, "", t)     # quoting is not part of a path
        gsub(/[^A-Za-z0-9_.\/~-]+$/, "", t)
        if (t !~ /\.sh$/) continue
        b = t; sub(/.*\//, "", b)
        if (!(b in names)) continue
        # A SCRIPT NAMING ITSELF IS NOT A CALLER, and this was measured wrong on
        # the first run: every tool with a `usage()` heredoc quoting its own
        # invocation came back CALLED, including the five #466 names by name.
        # "One caller is the file talking to itself through a longer path" —
        # module-shape.sh says it about symbols; it is truer about whole files.
        if (index(FILENAME, "/" b) == length(FILENAME) - length(b)) continue
        if (t ~ /\//) { print b; continue }      # a PATH is command position
        p = (i > 1) ? F[i-1] : ""
        if (p == "sh" || p == "bash" || p == "exec") { print b; continue }
        # A BARE NAME INSIDE ANOTHER SCRIPT IS ALSO A WIRING, and requiring
        # command position there was measured wrong on the first run: it called
        # `worklog-push.sh` idle while it runs at Stop on every box,
        # because runtime-install.sh carries it in a PAYLOAD list (`FILES="…"`)
        # and session-verdicts.sh checks it in a `for h in …` — neither of which
        # is an invocation and both of which are wirings. The relaxation is
        # confined to bin/ scripts and the dispatcher, whose VERBS rows are the
        # same wiring (harbor#474): a plist or a workflow naming a script it does
        # not run is noise, a script doing so is not.
        if (FILENAME ~ /\/bin\/([^\/]*\.sh|harbor)$/) print b
      }
    }' < "${TMPDIR:-/tmp}/c8-surf.$$" 2>/dev/null
    # THE JUSTFILE is the operator's surface and the recipes are its calls. Its parser is S5's,
    # shared, so the two rules cannot disagree about which bin/ paths the justfile names (harbor#474).
    _justfile_bin_paths | sed 's#.*/##'
  } | sort -u > "$_C8_C"
  rm -f "${TMPDIR:-/tmp}/c8-surf.$$"
  # A sweep that found NOTHING did not run. Every tool would then read as idle —
  # a hundred violations that say nothing about the repo and everything about a
  # broken surface list. B9's rule: "I could not look" must never render as an
  # answer, and here the wrong answer is loud rather than quiet, which is worse.
  if [ ! -s "$_C8_C" ]; then
    bad lint.tool-has-caller "the caller sweep found no invocation anywhere — the surface list is broken, and every tool would falsely read as idle"
  else
    # awk, not grep, for the membership tests: two of the four are NEGATIVES,
    # and on this box grep is a ugrep wrapper carrying flags this file does not
    # control. A missed line here silently clears a violation.
    awk -v D="$_C8_D" '
         NR == FNR     { called[$0] = 1; next }
         FILENAME == D { decl[$0] = 1; next }
         { if ($0 in called) { if ($0 in decl) print "X\t" $0 }
           else             { if (!($0 in decl)) print "M\t" $0 } }' \
        "$_C8_C" "$_C8_D" "$_C8_N" > "${TMPDIR:-/tmp}/c8-verdict.$$"
    while IFS='	' read -r _k _b; do
      [ -n "${_b:-}" ] || continue
      case "$_k" in
        M) bad lint.tool-has-caller "nothing calls bin/$_b and it is not declared in CONTRACTS/idle-tools.txt — a tool nobody runs must say so out loud" ;;
        X) bad lint.tool-has-caller "CONTRACTS/idle-tools.txt calls bin/$_b idle, but something invokes it — delete the line, the declaration has gone stale" ;;
      esac
    done < "${TMPDIR:-/tmp}/c8-verdict.$$"
    rm -f "${TMPDIR:-/tmp}/c8-verdict.$$"
    while IFS= read -r _b; do
      [ -n "$_b" ] || continue
      [ -f "$ROOT/bin/$_b" ] || bad lint.tool-has-caller "CONTRACTS/idle-tools.txt names a tool that does not exist: bin/$_b"
    done < "$_C8_D"
  fi
  rm -f "$_C8_N" "$_C8_C" "$_C8_D"
else
  bad lint.tool-has-caller "CONTRACTS/idle-tools.txt is missing — 'nothing runs this' becomes a state a tool can be in silently"
fi
}

# ── C9 · every rule in this file has been watched go red ───────────────────
# §2.10 ONE LEVEL UP. "A test that cannot fail is worse than no test" is usually
# said about a suite; it is equally true of a lint rule. Measured 2026-09-16, before
# this pass: 32 of the 54 ids that could then fire were never mentioned anywhere in
# bin/lint-test.sh — and that count uses the most generous predicate available (any
# word-mention of the id), so it is a LOWER bound on what has never been watched
# fail. Both halves of that pair MOVE, so do not read them here: the live pair is
# printed by `sh bin/lint-conventions.sh` and tracked on harbor#517. It stood at
# 30 of 55 once this pass armed V1, C9 and F12.
#
# EVERY RULE THE DISPATCHER RUNS, NOT EVERY RULE THAT CALLS `bad` (harbor#625).
# This first counted ids appearing as `bad <ID>`, on the argument that an
# advisory-only rule has no red state to watch. It has one: its advisory, which is
# its whole output. G1 was the cost. #578 measured one of its advisories in seven
# to be false, and C9, the rule that exists to surface an untested rule, could not
# see G1 at all. The universe is now the `rule_<ID>() {` definitions, the same list
# `--only` dispatches from, so the denominator matches a whole run's tally line.
#
# THE TWO DEFECT CLASSES SEPARATE CLEANLY, which is why this is worth a rule rather
# than a note. V1 (0 mentions) was measured 64% INERT — it passes for 18 of 28
# vendored skills with every table row deleted, because its predicate is a substring
# search the file's own prose satisfies. C8 (10 mentions) and D2 (16 mentions) also
# had defects that day, and both were SCOPE errors: C8 cannot see `bin/harbor` or the
# justfile, D2 keys on the apply flag rather than the write. Tested rules fail by
# being wrong; untested rules fail by being inert. The first kind gets found because
# somebody hits it. The second never goes red, so nobody looks.
#
# A VIOLATION SINCE harbor#577, AT ZERO. It was advisory while most of the set failed it
# (§2.11: a rule that reddens CI wholesale on arrival gets reverted wholesale). harbor#588
# red-proved the last 11, so the baseline is zero and the ratchet is "no rule lands without
# an arm". No exemption list: one would be the hand-kept copy this rule exists to refuse.
# A rule that genuinely cannot be red-proved would need its reason written next to an arm.
# THE PREDICATE IS STILL A MENTION, not an assertion: a comment naming the id satisfies it
# (harbor#517 records this as a lower bound), so it forces the author to open the redproof
# suite, and does not prove the arm can fail.
#
# DERIVED ON BOTH SIDES, NEVER A LIST. An exemption list here would be the eighth
# instance of the pattern this estate measured seven times on 2026-09-16 — a
# hand-kept copy of a derivable fact, every one of which had diverged or gone inert.
# The ids come from the `rule_<ID>() {` definitions in this file; the ids exercised come
# from the suite. Both sides move when the code moves.
#
# IT COUNTS ITSELF, and the first cut of this comment claimed otherwise — it said
# `bad lint.rule-has-test` never appears below, and it does, in the else-branch where the linter
# cannot read itself or its suite. That branch is right: a C9 that cannot compare is
# a hard failure, not an advisory. So the comment was wrong about the code five lines
# under it, which is the defect this whole sweep is about, committed by the person
# writing the rule against it. C9 therefore appears in its own list until it has an
# arm, like everything else, and tests/checks/lint.c9-test.sh gives it one.
rule_C9() {
rule "lint.rule-has-test every rule in this file has a mention in the lint suite, tests/checks/lint*-test.sh or an assertion in tests/lint/**/*.test.sh — a rule added without an arm fails the build (the #577 ratchet)"
_C9_L="$ROOT/bin/lint-conventions.sh"
_C9_T="$ROOT/tests/checks"
_C9_D="$ROOT/tests/lint"
# The suite is lint-test.sh and its lint.<part>-test.sh parts (harbor#667): a mention in any part counts.
_c9_all="${TMPDIR:-/tmp}/c9-suite.$$"
find "$_C9_T" -maxdepth 1 -type f \( -name 'lint-test.sh' -o -name 'lint.*-test.sh' \) \
  -exec cat {} + > "$_c9_all" 2>/dev/null
# D-14 puts a rule's own suite at tests/lint/<subject>/<aspect>.test.sh. There a mention counts only as an
# assertion: comment lines and anything under fixtures/ are not read, so a note cannot arm a rule.
[ -d "$_C9_D" ] && find "$_C9_D" -type f -name '*.test.sh' -not -path '*/fixtures/*' \
  -exec grep -hv '^[[:space:]]*#' {} + >> "$_c9_all" 2>/dev/null
if [ -f "$_C9_L" ] && [ -s "$_c9_all" ]; then
  _c9_un=''
  _c9_tot=0
  # A mention is the rule's id or its deprecated letter (harbor#957), as a whole token: the suites
  # still say `lint1 F1`, and `grep -w` would let `drift.skill-tier` match inside `drift.skill-tier-x`.
  for _c9_p in $(_rule_map "$_C9_L" | awk -F'\t' '{ print $2 ":" $3 }' | sort -u); do
    _c9_id="${_c9_p%%:*}"; _c9_lt="${_c9_p#*:}"
    _c9_tot=$(( _c9_tot + 1 ))
    { [ "$_c9_lt" != - ] && grep -qw -- "$_c9_lt" "$_c9_all" 2>/dev/null; } \
      || awk -v s="$_c9_id" 'function tok(   r, p, i, c, d, e, n) { n = length(s); r = $0; p = 0
             while ((i = index(r, s)) > 0) { p += i; c = (p > 1) ? substr($0, p - 1, 1) : ""
               d = substr($0, p + n, 1); e = substr($0, p + n + 1, 1)
               if (c !~ /[A-Za-z0-9_.-]/ && d !~ /[A-Za-z0-9_]/ && !((d == "." || d == "-") && e ~ /[A-Za-z0-9]/)) return 1
               r = substr($0, p + 1) }
             return 0 }
           tok() { f = 1; exit } END { exit !f }' "$_c9_all" 2>/dev/null \
      || _c9_un="$_c9_un $_c9_id"
  done
  if [ -n "$_c9_un" ]; then
    _c9_n=$(printf '%s' "$_c9_un" | wc -w | tr -d ' ')
    bad lint.rule-has-test "$_c9_n of $_c9_tot rules are never mentioned in tests/checks/lint*-test.sh or tests/lint/**/*.test.sh — never watched fail (harbor#577): add a red-proof arm in tests/checks/lint.redproof*-test.sh for$_c9_un" $_c9_un
  fi
else
  bad lint.rule-has-test "cannot read the linter or its suite — C9 has nothing to compare"
fi
rm -f "$_c9_all"
}

# ── lint.id-one-meaning · one id per rule, one rule per id (harbor#957) ─────────
# WHY THIS EXISTS: 23 of the 93 letter ids meant something else as well. K1 was this file's
# constitution-path rule, PLAN.md's security-floor workstream, and in FLOOR.md the kill-switch check
# that is F1's; T1-T7 are also tests/lib/check.sh ids. A grep-first reader landed on the wrong
# meaning in 1 of 3 sampled ids (research 11b §2.3). The ids are now <family>.<slug> (D-10), and
# this rule holds what makes one id one meaning, on the linter it is pointed at (the C9 trick, so a
# fixture can plant a bad one):
#   - every `rule_<fn>() {` has a `rule "<id> …"` line under it — the dispatcher runs the map, so a
#     function the map misses would silently never run;
#   - no two rules share an id, or a deprecated letter, and no letter is also a current id;
#   - an id is lowercase kebab segments joined by `.`, the first a family or lint subject registered
#     in standards/naming/terms.tsv;
#   - no id is also one of bin/lint-name.sh's (the controls.tsv rows whose engine it is): `sh
#     bin/lint-name.sh --list` lists both, and one list may not hold one id twice.
# What the words in an id may be (aliases, abbreviations) is bin/lint-name.sh's to judge, under N4.
rule_lint_id_one_meaning() {
rule "lint.id-one-meaning every rule has one <family>.<slug> id, no id or deprecated letter names two rules, and none is also a bin/lint-name.sh id (harbor#957)"
_im_l="$ROOT/bin/lint-conventions.sh"; _im_t="$ROOT/standards/naming/terms.tsv"; _im_r="$ROOT/standards/naming/controls.tsv"
if [ ! -f "$_im_l" ] || [ ! -f "$_im_t" ]; then
  bad lint.id-one-meaning "cannot read bin/lint-conventions.sh or standards/naming/terms.tsv — no id was judged"
  return 0
fi
_im_fn="$(grep -c '^rule_[A-Za-z0-9_]*() {$' "$_im_l" | tr -d ' ')"
_im_out="$(_rule_map "$_im_l" | awk -F'\t' -v T="$_im_t" -v R="$_im_r" -v nfn="$_im_fn" '
  BEGIN { while ((getline l < T) > 0) { if (l ~ /^#/) continue; split(l, c, "\t")
            if (c[2] ~ /(^|,)(family|subject)(,|$)/) fam[c[1]] = 1 }
          while ((getline l < R) > 0) { if (l ~ /^#/) continue; split(l, c, "\t"); if (c[1] != "id" && c[4] == "bin/lint-name.sh") nm[c[1]] = 1 } }
  { n++
    if ($2 in by) print $2 "\tthe id " $2 " names two rules: rule_" by[$2] " and rule_" $1
    else by[$2] = $1
    if ($3 != "-") { if ($3 in lt) print $3 "\tthe deprecated id " $3 " names two rules: rule_" lt[$3] " and rule_" $1
                     else lt[$3] = $1 }
    if ($2 !~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*(\.[a-z][a-z0-9]*(-[a-z0-9]+)*)+$/)
      print $2 "\trule_" $1 " has the id " $2 ": an id is <family>.<slug>, lowercase kebab segments joined by . (D-10)"
    else { split($2, sg, "."); if (!(sg[1] in fam))
      print $2 "\trule_" $1 " has the id " $2 ": " sg[1] " is not a family or lint subject in standards/naming/terms.tsv (D-10)" }
    if ($2 in nm) print $2 "\tthe id " $2 " is also a bin/lint-name.sh rule in standards/naming/controls.tsv"
  }
  END { for (x in lt) if (x in by) print x "\tthe deprecated id " x " is also the id of rule_" by[x]
        if (n != nfn) print "-\t" nfn " rule functions and " n " ids: a rule_<fn>() { with no rule \"<id> …\" line under it never runs" }')"
while IFS='	' read -r _im_s _im_m; do
  [ -n "$_im_m" ] || continue
  bad lint.id-one-meaning "$_im_m" "$_im_s"
done <<IMOUT
$_im_out
IMOUT
}

# ── C10 · a suite never inherits a HARBOR_* knob (harbor#773) ───────────────
# CI's HARBOR_SUITE_COUNTS cost floor.status-test 4 passes. t_init now clears every HARBOR_* but
# T_PASS_ENV; this finds what that misses: a knob a suite runs through T_PASS_ENV or off the harness
# (a), and a knob a suite reads after t_init emptied it (b). Static: a program reached through another is not seen.
rule_C10() {
rule "test.knobs-cleared a suite never inherits a HARBOR_* knob: t_init clears them, and a suite clears what it runs unset (harbor#773)"
_c10t="${TMPDIR:-/tmp}/c10.$$"; rm -rf "$_c10t"; mkdir -p "$_c10t"
# lineno<TAB>code: comments dropped, single-quoted text and escaped $ blanked, a quoted heredoc's body
# dropped; quotes nest inside $( ), so a fixture quoted inside a command substitution stays text.
_c10_lex() {
  awk '
    BEGIN { sp = 0; st[0] = "U"; hd = "" }
    {
      line = $0
      if (hd != "") {
        t = line; if (hdt) sub(/^\t+/, "", t)
        if (t == hd) { hd = ""; next }
        if (!hdq) { gsub(/\\\$/, "", line); print NR "\t" line }
        next
      }
      out = ""; n = length(line); nh = ""
      for (i = 1; i <= n; i++) {
        c = substr(line, i, 1); top = st[sp]
        if (top == "S") { if (c == "\047") { sp--; out = out c } else out = out " "; continue }
        if (c == "\\") { out = out (substr(line, i + 1, 1) == "$" ? "  " : substr(line, i, 2)); i++; continue }
        if (c == "$" && substr(line, i + 1, 1) == "(") { st[++sp] = "C"; dep[sp] = 1; out = out "$("; i++; continue }
        if (top == "D") { if (c == "\"") sp--; out = out c; continue }
        if (c == "\047") { st[++sp] = "S"; out = out c; continue }
        if (c == "\"") { st[++sp] = "D"; out = out c; continue }
        if (top == "C" && c == "(") dep[sp]++
        if (top == "C" && c == ")" && --dep[sp] == 0) sp--
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[[:space:];&|()]/)) break
        if (nh == "" && c == "<" && match(substr(line, i), /^<<-?[[:space:]]*[\\\047"]?[A-Za-z_][A-Za-z0-9_]*/)) {
          nh = substr(line, i, RLENGTH)
        }
        out = out c
      }
      if (nh != "") {
        hdt = (nh ~ /^<<-/); hdq = (nh ~ /[\\\047"]/); sub(/^<<-?[[:space:]]*[\\\047"]?/, "", nh); hd = nh
      }
      print NR "\t" out
    }' "$1" 2>/dev/null
}
# A lexer that cannot run reads every suite as empty, and a rule that sees nothing is green.
printf 'a=${HARBOR_Z:-} # c\n' > "$_c10t/canary"
[ "$(_c10_lex "$_c10t/canary" | cut -f2-)" = 'a=${HARBOR_Z:-} ' ] \
  || bad test.knobs-cleared "its lexer cannot read a one-line script, so every suite would read as empty"
_c10_pass="$(sed -n "s/^T_PASS_ENV='\\([^']*\\)'.*/\\1/p" "$ROOT/tests/lib/core.sh" 2>/dev/null)"
# The knobs: every `${HARBOR_X` + a default operator in a shell program the repo ships.
for _c10p in "$ROOT"/bin/* "$ROOT"/hooks/* $(_engines) "$ROOT"/skills/*/bin/*; do
  [ -f "$_c10p" ] || continue
  case "${_c10p##*/}" in *-test.sh|*-fixture.sh) continue ;; *.sh) ;; *.*) continue ;;
    *) case "$(head -1 "$_c10p")" in '#!'*sh*) ;; *) continue ;; esac ;; esac
  _c10_lex "$_c10p" | cut -f2- | grep -oE '[$][{]HARBOR_[A-Z0-9_]+:?[-+=?]' \
    | sed -e 's/^..//' -e 's/:*[-+=?]$//' | sort -u | sed "s#^#${_c10p##*/}	#"
done > "$_c10t/knobs"
_c10_src() { # <file> — the fixtures it sources under tests/, one path per line (not the harness)
  _c10_lex "$1" | cut -f2- | grep -E '(^|[;&|[:space:]])[.][[:space:]]' | grep -oE '[A-Za-z0-9_.-]+[.]sh' \
    | while IFS= read -r _c10b; do
      case "$_c10b" in core.sh) continue ;; esac
      for _c10c in "${1%/*}/$_c10b" "$ROOT/tests/lib/$_c10b" "$ROOT"/tests/*/"$_c10b"; do
        [ -f "$_c10c" ] && { printf '%s\n' "$_c10c"; break; }
      done
    done
}
grep -vE '^[[:space:]]*(#|$)' "$ROOT/CONTRACTS/suites.txt" 2>/dev/null > "$_c10t/suites"
while IFS= read -r _c10s; do
  case "$_c10s" in */*) _c10f="$ROOT/$_c10s" ;; *) _c10f="$ROOT/bin/$_c10s" ;; esac
  [ -f "$_c10f" ] || continue
  # The suite, then the fixtures it sources, two levels deep, each tagged with its file.
  { _c10_src "$_c10f"; _c10_src "$_c10f" | while IFS= read -r _c10x; do _c10_src "$_c10x"; done; } \
    | awk '!seen[$0]++' > "$_c10t/fx"
  { _c10_lex "$_c10f" | sed "s#^#${_c10f#"$ROOT"/}	#"
    while IFS= read -r _c10x; do _c10_lex "$_c10x" | sed "s#^#${_c10x#"$ROOT"/}	#"; done < "$_c10t/fx"
  } > "$_c10t/code"
  _c10h=no
  _c10_lex "$_c10f" | cut -f2- | grep -E '(^|[;&|[:space:]])[.][[:space:]]' | grep -qE '(^|[/"[:space:]])core[.]sh' \
    && cut -f3- "$_c10t/code" | grep -qE '(^|[;&|[:space:]])t_init([;&|[:space:]]|$)' && _c10h=yes
  awk -F'\t' -v suite="${_c10f#"$ROOT"/}" -v harness="$_c10h" -v pass=" $_c10_pass " '
    function word(s, v,   p, r) {  # 1 when v occurs in s as a whole name
      r = s
      while ((p = index(r, v)) > 0) {
        if ((p == 1 || substr(r, p - 1, 1) !~ /[A-Za-z0-9_]/) && substr(r, p + length(v), 1) !~ /[A-Za-z0-9_]/) return 1
        r = substr(r, p + length(v))
      }
      return 0
    }
    function assigns(s, v,   i, n, c, dq, dp, k, rest) {  # 1 when a statement in s is only assignments, one to v
      n = split(s, st, /;|&&|[|][|]|[|]|[(]|[)]|[{]|[}]|(^|[[:space:]])(then|do|else)[[:space:]]/)
      for (k = 1; k <= n; k++) {
        rest = st[k]; sub(/^[[:space:]]+/, "", rest); sub(/^export[[:space:]]+/, "", rest)
        hit = 0
        while (match(rest, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
          if (substr(rest, 1, RLENGTH - 1) == v) hit = 1
          rest = substr(rest, RLENGTH + 1); dq = 0; dp = 0
          for (i = 1; i <= length(rest); i++) {
            c = substr(rest, i, 1)
            if (c == "\\") { i++; continue }
            if (c == "\"") { dq = !dq; continue }
            if (c == "$" && substr(rest, i + 1, 1) == "(") { dp++; i++; continue }
            if (c == ")" && dp > 0) { dp--; continue }
            if (!dq && !dp && c ~ /[[:space:]]/) break
          }
          rest = substr(rest, i); sub(/^[[:space:]]+/, "", rest)
        }
        if (hit && rest == "") return 1
      }
      return 0
    }
    function runs(p,   i, r, k, e, v, pre, w) {  # 1 when the code runs the program p (directly or through a variable)
      for (i = 1; i <= last; i++) {
        r = code[i]
        while ((k = index(r, "/" p)) > 0) {
          e = substr(r, k + length(p) + 1, 1)
          if (e !~ /[A-Za-z0-9_.-]/) {
            pre = substr(r, 1, k - 1)
            if (pre ~ /(^|[^A-Za-z0-9_])(sh|bash|dash|exec)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*"?[^[:space:]"]*$/ \
                || pre ~ /(^|[;&|(!]|then[[:space:]]|do[[:space:]])[[:space:]]*"?[^[:space:]"=]*$/) return 1
            if (match(pre, /[A-Za-z_][A-Za-z0-9_]*="?[^[:space:]"]*$/)) {
              v = substr(pre, RSTART); sub(/=.*/, "", v); via[v] = 1
            }
          }
          r = substr(r, k + 1)
        }
      }
      for (v in via) for (i = 1; i <= last; i++) {
        w = code[i]
        if (w ~ ("(^|[^A-Za-z0-9_])(sh|bash|dash|exec)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*\"?[$][{]?" v "([^A-Za-z0-9_]|$)") \
            || w ~ ("(^|[;&|(!]|then[[:space:]]|do[[:space:]])[[:space:]]*\"?[$][{]?" v "[}]?\"?([[:space:]]|$)")) { delete via; return 1 }
      }
      delete via
      return 0
    }
    FILENAME == ARGV[1] { knob[$1] = knob[$1] " " $2; next }
    { f[NR] = $1; ln[NR] = $2; code[NR] = substr($0, length($1) + length($2) + 3); last = NR }
    END {
      for (i = 1; i <= last; i++) {
        if (f[i] == suite && tinit == 0 && code[i] ~ /(^|[;&|[:space:]])t_init([;&|[:space:]]|$)/) tinit = ln[i]
        if (code[i] ~ /(^|[;&|[:space:](])unset[[:space:]]/) { s = code[i]; sub(/.*unset[[:space:]]/, "", s); nu = split(s, U, /[^A-Za-z0-9_]+/); for (u = 1; u <= nu; u++) cleared[U[u]] = 1 }
      }
      for (p in knob) {
        if (!runs(p)) continue
        nk = split(knob[p], K, " ")
        for (j = 1; j <= nk; j++) {
          v = K[j]; if (v == "" || done[v]) continue
          if (harness == "yes" && index(pass, " " v " ") == 0) continue
          if (cleared[v]) continue
          set = 0; for (i = 1; i <= last && !set; i++) if (assigns(code[i], v)) set = 1
          if (set) continue
          done[v] = 1
          printf "%s runs %s, which reads %s unset by default, and %s — unset it at the top (harbor#773)\n", suite, p, v, \
            (harness == "yes" ? "t_init passes it through (T_PASS_ENV) and the suite never clears it" : "the suite is off the harness and never clears it")
        }
      }
      if (harness != "yes") exit
      for (i = 1; i <= last; i++) {
        if (f[i] == suite && ln[i] <= tinit) continue
        r = code[i]
        while (match(r, /[$][{]?HARBOR_[A-Z0-9_]+/)) {
          v = substr(r, RSTART, RLENGTH); sub(/^[$][{]?/, "", v); r = substr(r, RSTART + RLENGTH)
          if (index(pass, " " v " ") || seen[f[i] SUBSEP v]) continue
          set = 0
          for (a = 1; a <= i && !set; a++) if (f[a] == f[i] && ln[a] <= ln[i] && (assigns(code[a], v) || (a < i && code[a] ~ ("(^|[^A-Za-z0-9_])" v "=")))) set = 1
          if (set) continue
          seen[f[i] SUBSEP v] = 1
          printf "%s:%s reads %s after t_init cleared it — read it before t_init (harbor#773)\n", f[i], ln[i], v
        }
      }
    }' "$_c10t/knobs" "$_c10t/code" >> "$_c10t/msgs"
done < "$_c10t/suites"
: >> "$_c10t/msgs"; while IFS= read -r _c10m; do bad test.knobs-cleared "$_c10m"; done < "$_c10t/msgs"
say "  $(grep -c . "$_c10t/suites") suites, $(cut -f2 "$_c10t/knobs" | sort -u | grep -c .) HARBOR_* knobs read with a default, T_PASS_ENV: ${_c10_pass:-none}."
rm -rf "$_c10t"
}

# ── T1 · STATUS.md is generated and current ────────────────────────────────
# The T rules exist because of one measured failure: on 2026-07-26 a sweep found
# CONTRACTS/README.md claiming "18 rules" and "492 assertions" (actual 21, 573),
# PROVENANCE.md claiming "19 skills" (actual 28), and QA-PLAN.md §6 listing risks
# as OPEN that §7 of the SAME FILE said had shipped. None was a lie when written.
# They rotted because a count in prose is a COPY of a fact that lives in the
# code, and copies drift silently while reading correct.
rule_T1() {
rule "doc.status-generated STATUS.md is regenerated, not hand-edited (the single source for counts)"
# --check-fast: the linter runs on every commit, and the full check RUNS all
# three suites (minutes). CI runs the full one, so a suite that silently stops
# reporting is still caught — at push time rather than at commit time.
if _export_tree STATUS.md harbor-build-tickets.md; then
  printf '  (skipped: STATUS.md is dev-layer and this tree carries none of the dev layer, so there is no STATUS.md to judge)\n'
else
  sh "$ROOT/bin/status-gen.sh" --check-fast >/dev/null 2>&1 \
    || bad doc.status-generated "STATUS.md is stale — run: sh bin/status-gen.sh --apply"
fi
}

rule_F9() {
rule "test.negative-has-control a NEGATIVE assertion on a tool's prose needs a positive control (harbor#145)"
# THE HALF THAT FAILS SILENTLY. An assertion keyed on an English phrase from a
# tool's output has two directions and only one is safe:
#   grep -q 'phrase' && ok || bad   → a reword makes it go RED. Loud, visible, fine.
#   grep -q 'phrase' && bad || ok   → a reword makes it PASS. The property stops
#                                     being checked and the suite still prints green.
# harbor#95's WIRE-2 is how this is known: it grepped for `To apply`, a phrase that
# existed only on the dry-run path, so the post-apply hint went unread for months
# while the assertion stayed true and the property was false (harbor#142).
#
# WHAT MAKES A NEGATIVE ONE SAFE is a POSITIVE assertion on the SAME phrase in the
# same file: if the wording changes, the positive goes red first and the negative
# can never be silently keying on a phrase nothing produces. That is the "prove the
# red state is reachable" idiom the suites already claim — this rule is what makes
# the claim true rather than a habit. floor-test's B8-ABSENT block was safe only by
# PROXIMITY (its positive twin sat 17 lines above); it now names the phrase once in
# a variable, and token equality below covers both spellings.
#
# ONLY PIPELINE-FED GREPS. A grep whose target is a FILE is reading source, not
# prose — `grep -v '^#' worklog-push.sh | grep -qE 'git add (-A|--all|\.)' && bad`
# is a legitimate negative assertion on CODE SHAPE, and a reword of any message
# cannot affect it. harbor#145's own list included it by mistake, which is the
# discrimination this rule has to get right or it becomes noise.
# tests/ suites (harbor#667) spell the pair `t_hasnt … 'phrase'` / `t_has … 'phrase'`.
for f in "$ROOT"/bin/*-test.sh "$ROOT"/tests/*/*-test.sh "$ROOT"/hooks/*/*.test.sh; do
  [ -f "$f" ] || continue
  # Phrase (literal or "$VAR") from every pipeline-fed `grep -q` whose assertion
  # reaches `&& bad` within two lines — the negative direction.
  # SAME-LINE FIRST, AND `--` IS PART OF THE INVOCATION. Both gaps were found by
  # review on PR #237, and each one hid a real instance of exactly what F9 exists to
  # catch. The first pass stored the phrase and ran `next`, so a `grep -q 'x' && bad
  # || ok` written on ONE line — the canonical form in replay-test.sh:259 — lost the
  # only evidence that the assertion was negative and was never considered. And the
  # extractor required the pattern to follow `grep -q` directly, so the equally
  # ordinary `grep -q -- '── floor-verify · --live'` (floor-test.sh:4012) did not
  # parse as an assertion at all. A rule blind to two of the three spellings its
  # subject is written in is worse than no rule: it reports the property as checked.
  # LINE CONTINUATIONS ARE JOINED FIRST, or the rule is a false-positive machine.
  # The house style splits an assertion over two lines — `… | grep -q 'x' \` then
  # `  && ok || bad "…"` — so the phrase and its verdict never share a line. Scanned
  # raw, that made the POSITIVE control invisible and F9 reported four suites that
  # were already correct (`LIVE IS NEWER`, `B6 installs LAST`). A rule that fires on
  # the sanctioned shape is the §2.11 defect it is written to prevent: it gets
  # switched off, and then it protects nothing. Both halves — the negative scan and
  # the positive check — read the joined text, so the rule sees the assertion the way
  # the shell does rather than the way the file is wrapped.
  _f9_j="${TMPDIR:-/tmp}/f9j.$$"
  awk '{ l=$0; while (l ~ /\\$/ && (getline n) > 0) { sub(/\\$/, "", l); sub(/^[ \t]+/, "", n); l = l " " n } print l }' "$f" > "$_f9_j"
  _f9_neg="$(awk '
    /(^|[;[:space:]])t_hasnt / {
      q = "(\"[^\"]*\"|\x27[^\x27]*\x27)"
      if (match($0, "t_hasnt +" q " +" q " +" q)) {
        s = substr($0, RSTART, RLENGTH)
        if (match(s, q "$")) { ph = substr(s, RSTART + 1, RLENGTH - 2); if (ph != "") print ph }
      }
      next
    }
    /\| *grep -q/ && !/grep -q[^\x27"]*[a-z]\.sh/ {
      line=$0; ph=""
      if (match(line, /grep -q[EFqi]*( +--)? *\x27[^\x27]+\x27/)) { ph=substr(line, RSTART, RLENGTH); sub(/grep -q[EFqi]*( +--)? *\x27/, "", ph); sub(/\x27$/, "", ph) }
      else if (match(line, /grep -q[EFqi]*( +--)? *"[^"]+"/)) { ph=substr(line, RSTART, RLENGTH); sub(/grep -q[EFqi]*( +--)? *"/, "", ph); sub(/"$/, "", ph) }
      if (ph != "") {
        if (line ~ /&& *bad|&& *no /) { print ph; pend=""; next }
        if (line ~ /&& *ok/)          { pend=""; next }
        pend=ph; nl=NR+2; next
      }
    }
    pend != "" && NR <= nl { if ($0 ~ /&& *bad|&& *no /) { print pend; pend="" } else if ($0 ~ /&& *ok/) { pend="" } }
    pend != "" && NR > nl { pend="" }
  ' "$_f9_j" | sort -u)"
  [ -n "$_f9_neg" ] || { rm -f "$_f9_j"; continue; }
  printf '%s\n' "$_f9_neg" | while IFS= read -r _ph; do
    [ -n "$_ph" ] || continue
    # PROSE ONLY, AND THE FILTER IS THE RULE. Without it this fired on eight
    # negative assertions keyed on REGEXES and single tokens — `(src|href)="https?:`,
    # `^IDENTITY.md$`, `CANARY`, `GX` — none of which is a wording anybody could
    # reword. That is the false-positive class §2.11 calls a defect, produced by the
    # rule written to catch it, so the discriminator is harbor#145's own: two or more
    # words. A regex metacharacter disqualifies it — a pattern is a contract, a
    # sentence is not. A "$VAR" reference stays IN scope: naming the phrase once is
    # the sanctioned fix, and token equality still proves the positive control.
    #
    # CASE AND PUNCTUATION ARE NOT THE TEST — also from PR #237's review, and it cost
    # two more misses. Keying on a lowercase-to-lowercase word boundary excluded
    # `REFUSING TO REPORT` (replay-test.sh) because it SHOUTS, and
    # `── floor-verify · --live` (floor-test.sh) because its words are separated by a
    # rule character and a flag. Both are wordings a message rewrite invalidates,
    # which is the only property that matters here. So the count is over WORDS: a
    # token with two or more letters in it, after punctuation is stripped. Two such
    # tokens is prose; one is a token, and `CANARY`, `GX` and `--check` stay out.
    case "$_ph" in
      '$'*) ;;                                    # a variable — the good shape, still checked
      *[\\\(\)\[\]\|\^\$\*\+\?]*) continue ;;     # a regex, not a wording
      *) _f9_words=0
         for _f9_w in $_ph; do
           _f9_w="$(printf '%s' "$_f9_w" | tr -cd 'A-Za-z')"
           [ "${#_f9_w}" -ge 2 ] && _f9_words=$((_f9_words + 1))
         done
         [ "$_f9_words" -ge 2 ] || continue ;;
    esac
    # THE KEY IS THE VARIABLE, WHEN THERE IS ONE. A phrase like "$_FV_HDR--live"
    # is a named wording plus a literal argument, and no positive assertion can
    # ever say `--live` IS present — that is the bug being guarded. What must not
    # rot is the wording, and the wording is the variable: reword floor-verify's
    # header and $_FV_HDR's definition changes, so every positive assertion using
    # it goes red first and the negative cannot drift onto a dead phrase. So when
    # the phrase carries a $VAR, the positive control is required on that token,
    # not on the whole string. A phrase with no variable is checked whole, as before.
    _f9_key="$_ph"
    case "$_ph" in
      *'$'*) _f9_key="$(printf '%s' "$_ph" | sed -n 's/.*\(\$[A-Za-z_][A-Za-z0-9_]*\).*/\1/p')"
             [ -n "$_f9_key" ] || _f9_key="$_ph" ;;
    esac
    # A positive assertion on the same token, anywhere in the file.
    if ! grep -F -- "$_f9_key" "$_f9_j" | grep -qE '&& *ok|(^|[;[:space:]])t_has '; then
      printf 'F9-MISS\t%s\t%s\n' "${f#"$ROOT"/}" "$_ph"
    fi
  done > "${TMPDIR:-/tmp}/f9.$$"
  while IFS="$(printf '\t')" read -r _tag _file _phrase; do
    [ "${_tag:-}" = "F9-MISS" ] || continue
    bad test.negative-has-control "$_file asserts a phrase is ABSENT with no positive control on it: '$_phrase' — reword the message and this assertion passes forever while nothing is checked"
  done < "${TMPDIR:-/tmp}/f9.$$"
  rm -f "${TMPDIR:-/tmp}/f9.$$" "$_f9_j"
done
}

rule_T1b() {
rule "doc.site-generated docs/index.html builds from docs/src with no unknown hole (harbor#1197)"
# THE SAME ARGUMENT AS T1, FOR THE OTHER GENERATED DOCUMENT, and it was unguarded.
# docs-gen.sh --check has existed since harbor#173 and NOTHING ran it: not a CI
# job, not a rule here, not a suite. A staleness gate nobody invokes is a gate.
#
# MEASURED 2026-08-14, and the demonstration is this very commit: adding two suites
# and one hook wiring made docs/index.html stale in three derived tables, `--check`
# exited 1, and no gate anywhere noticed. The page's tables are DERIVED from the
# repo at build time — lint rules, CLI verbs, rule packs, suites, CI jobs,
# contracts, skills — so every change to any of those rots it silently while it
# keeps reading perfectly. That is T1's lesson exactly, one document over.
#
# WHY HERE AND NOT IN CI. patches/governance-docs-gen-check.patch.md proposes a
# step in .github/workflows/governance.yml, which is agent-denied by design — so
# that patch has waited for an operator keystroke while the page kept drifting. The
# linter is the surface that already owns "a generated document is current" (T1),
# runs on every commit through hooks/pre-commit, and needs no keystroke. When the
# operator applies the patch, CI gains a second, independent check; this one is not
# made redundant by that, because pre-commit catches it a push earlier.
#
# FULL --check, NOT A FAST VARIANT, because there is no equivalent: docs-gen has no
# --check-fast, and the reason T1 needs one does not apply. Measured at 2.15s on
# this box, against status-gen's full check, which ran three suites and took minutes
# until harbor#117 cached their counts on content (0.33s warm, 4:48 cold). A
# rule that costs two seconds on every commit is affordable; if it ever stops being
# so, the fix is a --check-fast in docs-gen.sh, not dropping the gate.
# SINCE harbor#1197 THE PAGE IS NOT COMMITTED, so the rule above no longer asks "is it fresh": --check builds it to a temp
# path and fails on a build error or an unknown <!--gen:NAME--> hole, which is what a committed copy could not show anyway.
_ds="$(sh "$ROOT/bin/docs-gen.sh" --check 2>&1)" \
  || bad doc.site-generated "docs/index.html cannot be built: $(printf '%s\n' "$_ds" | grep -m1 'FAIL' | sed 's/^ *FAIL: //') — run: sh bin/docs-gen.sh --check"
}

# ── H1 · a colour token defined for light is redefined in every dark branch ──
# MEASURED 2026-08-31. bin/dashboard-gen.sh defines `--unk:#6b6b68` in `:root`
# and its dark block redefines every OTHER token. So the "unknown"/"unavailable"
# status text rendered a light-ground grey on a #151514 dark ground — 3.42:1,
# under the 4.5:1 AA floor — while its light-mode twin `--dim` gets #9a9a96 for
# 6.47:1. Same generator, one name absent from one block.
#
# WHY ONLY A MECHANISM CATCHES THIS CLASS. In LIGHT mode `--unk` and `--dim`
# hold the same hex, so the omission renders identically and emits no signal at
# all. Reading the source does not show it either: the dark block is a wall of
# correct-looking redefinitions with one name missing from the middle of it.
# Set arithmetic finds it; eyes do not. That is the whole argument for the rule
# over a note telling someone to be careful.
#
# VALUE-TYPED, NOT "every token" (No.2.11 — a false positive is a defect, and a
# guard that blocks ordinary work gets switched off). docs/index.html defines
# `--serif` and `--mono` as font stacks in the same `:root`; redefining those for
# dark would be wrong, not right. The rule keys on the value BEING a colour,
# which is decidable from the text.
#
# A FILE WITH NO DARK BRANCH IS NOT A VIOLATION. A page may commit to one visual
# world deliberately. This rule judges parity between branches that exist; it
# never rules on whether a page ought to have a dark mode.
#
# WHY A BRACE-DEPTH STACK AND NOT A PROXIMITY GREP. "prefers-color-scheme within
# N characters before a :root" reads correctly on all three of our surfaces
# today and is wrong in principle — a dark media block that CLOSES before a
# light `:root` would be mis-attributed. Enclosure is what the rule means, and
# brace depth is what decides enclosure.
rule_H1() {
rule "doc.dark-tokens every colour token has a value in each dark branch its file declares"
for f in "$ROOT"/docs/*.html "$ROOT"/bin/*.sh $(_engines) "$ROOT"/skills/*/bin/*.sh "$ROOT"/build/*.html; do
  [ -f "$f" ] || continue
  # vendor/ is not ours to lint (the V1 argument, one rule over).
  case "$f" in "$ROOT"/vendor/*) continue ;; esac
  # A *-test.sh IS EXEMPT AS A CLASS, the way D2 exempts one. A suite proving
  # this rule can fail must contain CSS that fails it, so H1 read its own
  # fixtures as defects and turned the linter permanently red the moment the
  # arms landed — six violations against deliberately broken paint. Fixture data
  # is not a surface anyone renders.
  case "$(basename "$f")" in *-test.sh) continue ;; esac
  # A FILE THAT EMITS A STYLESHEET, not one that merely mentions :root. Without
  # the <style> half this rule scanned its own source — this file quotes both
  # `:root` and a `--token:#hex` pair in the rationale above — and awk then
  # brace-counted shell code and choked on the box-drawing rule separators.
  grep -q '<style' "$f" 2>/dev/null || continue
  grep -qE ':root[[:space:]]*\{' "$f" 2>/dev/null || continue
  # ONE parse, captured. The first cut of this rule ran the same awk twice —
  # once to print and once to count — which is two copies of a parser that drift
  # apart silently and make the report disagree with the verdict. It is also the
  # exact shape T2 exists to stop, three hundred lines up in this same file.
  _h1out="$(LC_ALL=C awk '
    function iscolour(v) {
      return (v ~ /#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]/ || v ~ /rgba?\(/ ||
              v ~ /hsla?\(/ || v ~ /oklch\(/ || v ~ /oklab\(/ || v ~ /color\(/)
    }
    { buf = buf $0 "\n" }
    END {
      n = length(buf); depth = 0; sel = ""; nblk = 0
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (c == "{") {
          depth++
          dark[depth] = (sel ~ /prefers-color-scheme/ && sel ~ /dark/) ||
                        (sel ~ /data-theme=.?dark/)
          if (depth > 1 && dark[depth-1]) dark[depth] = 1
          root[depth] = (sel ~ /:root/); body[depth] = ""; sel = ""
          continue
        }
        if (c == "}") {
          if (depth > 0) {
            if (root[depth]) {
              if (dark[depth]) nblk++
              b = body[depth]
              while (match(b, /--[A-Za-z0-9_-]+[[:space:]]*:[^;}]*/)) {
                decl = substr(b, RSTART, RLENGTH); b = substr(b, RSTART + RLENGTH)
                name = substr(decl, 1, index(decl, ":") - 1)
                sub(/[[:space:]]+$/, "", name)
                val = substr(decl, index(decl, ":") + 1)
                if (!iscolour(val)) continue
                if (dark[depth]) seen[nblk "|" name] = 1; else light[name] = 1
              }
            }
            depth--
          }
          sel = ""; continue
        }
        sel = sel c
        if (length(sel) > 400) sel = substr(sel, length(sel) - 300)
        for (d = 1; d <= depth; d++) if (root[d]) body[d] = body[d] c
      }
      if (nblk == 0) exit 0
      for (name in light)
        for (k = 1; k <= nblk; k++)
          if (!((k "|" name) in seen)) printf "%s in dark branch %d of %d\n", name, k, nblk
    }
  ' "$f")"
  [ -n "$_h1out" ] || continue
  # Report and tally both read the SAME capture, and the tally is taken outside
  # any pipeline: a `while read` on the right of a pipe runs in a subshell, so a
  # FAIL incremented in there is discarded and the gate prints violations while
  # reporting green.
  printf '%s\n' "$_h1out" | sed "s|^|  VIOLATION [doc.dark-tokens] ${f#$ROOT/}: |;s|\$| has no value|" >&2
  FAIL=$((FAIL+1))
done
}

# ── T2 · no other document restates a countable fact ───────────────────────
# The structural half, and the one that actually prevents recurrence. Checking
# copies harder does not help; the fix is that there is only ever one copy.
# A document that wants to cite a count links to STATUS.md instead.
#
# Scoped to the counts STATUS.md owns, and only in the numeral form that rots —
# "21 lint rules". Prose like "every lint rule" or "the rule count" is fine, and
# so is a historical statement inside a dated record: FLOOR.md's pass tables and
# the git log are ACCOUNTS OF THE PAST and must keep their numbers, or the
# project loses the evidence its own conclusions rest on.
rule_T2() {
rule "doc.counts-in-status-only only STATUS.md states a countable fact in numerals (link to it instead)"
# `[[:space:]]+`, not a literal space (edge pass 2026-08-29): `7  floor guards`
# with two spaces walked past the rule while `7 floor guards` was caught, and a
# reflowed paragraph or a markdown table cell produces exactly that. A rule whose
# coverage depends on whitespace count is a rule that reports clean for the wrong
# reason. A newline is deliberately NOT included — grep is line-oriented here, so
# a count split across two lines is out of reach of this shape either way, and
# pretending otherwise in the pattern would be the more misleading of the two.
COUNTABLE='[0-9]+[[:space:]]+(lint rules|vendored skills|frozen contracts|floor guards|marker fixtures)'
for f in "$ROOT"/*.md "$ROOT"/CONTRACTS/*.md "$ROOT"/DOCTRINE/*.md; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  # STATUS.md is the source. FLOOR.md and QA-PLAN.md are dated records of what
  # was true at each pass — their numbers are evidence, not claims about now.
  case "$b" in STATUS.md|FLOOR.md|QA-PLAN.md) continue ;; esac
  grep -nEi "$COUNTABLE" "$f" 2>/dev/null | grep -v 'STATUS.md' | head -3 \
    | while IFS= read -r hit; do
        [ -n "$hit" ] && printf '  VIOLATION [doc.counts-in-status-only] %s restates a STATUS.md count: %s\n' "${f#$ROOT/}" "$(printf '%s' "$hit" | cut -c1-90)" >&2
      done
  if grep -qEi "$COUNTABLE" "$f" 2>/dev/null; then FAIL=$((FAIL+1)); fi
done
}

# ── T4 · no document names a GitHub repo that does not exist ───────────────
# The doc-truth sweep's single most common high-severity class. Line 3 of the
# ticket file named `VytCepas/helm` — a repo that was never created and never
# will be after the 2026-07-25 no-fork decision — while §A of the SAME FILE
# said so thirty lines below. A reader who stops at the summary gets the
# opposite of the plan of record.
#
# Checked against a static allowlist of repos known to exist rather than by
# calling `gh`: the linter runs offline, in CI, and on a pre-commit hook, and a
# network round-trip in any of those is a flake waiting to happen. Adding a repo
# here is a deliberate act, which is the point.
rule_T4() {
rule "doc.repos-exist documents name only repos that exist (VytCepas/*)"
# FIXED 2026-08-02 (harbor#86). This was a hand-maintained COPY of a fact that
# lives on GitHub: the rule is named for existence and was implemented as
# membership of a string typed into this line. So a real repo read as
# nonexistent until a human edited it — which is what happened to a workload repo on
# the day it was created, in the same lint run where cite-verify had already
# fetched it and got 200. It failed the other way too, and more quietly: a
# deleted or renamed repo stayed on the list forever, and T4 kept certifying
# every document that named it.
#
# The existence proof now comes from CITATIONS.md, which is the file whose job
# is to hold verified external facts — each row records the URL, the HTTP
# status, the fetcher, and the date. Only rows with a 2xx/3xx status count.
# A lint rule must work offline and in CI, and this keeps it offline: the
# network round-trip already happened, in bin/cite-verify.sh, and was written
# down. NOTE the asymmetry that column exists for — these repos are PRIVATE, so
# they answer 200 to an authenticated `gh` and 404 to a bare `curl`; an
# existence check that ignored the VIA column would call every one of them
# missing.
_t4_cited="$(grep -E '^\| `https://github\.com/VytCepas/[^`]+` \| *[23][0-9][0-9] ' "$ROOT/CITATIONS.md" 2>/dev/null \
             | sed -E 's|.*github\.com/VytCepas/([A-Za-z0-9_.-]+).*|\1|' | sort -u | tr '\n' '|' | sed 's/|$//')"
# The residual: repos that exist and that no document cites by URL, so there is
# nothing for CITATIONS.md to hold. Adding a row for one of these would be
# inventing a citation to satisfy a lint rule, which is the failure the file
# exists to prevent. Each name here should disappear the day a document cites it.
#   helm-log              the private work-log remote; named in prose, never linked
#   projects-orchestrator Fleet; named constantly, its URL cited nowhere yet
#
# A workload repo id WAS ON THIS LIST FOR ONE HOUR on 2026-09-15 and is deliberately not any
# more. The tree was renamed ~/oldname -> ~/<newname> and the GitHub repo was not, so for
# that hour `VytCepas/oldname` was the live remote for a directory called <newname> and a
# document naming it honestly had to say `oldname`. The repo has since been renamed too
# and every live pointer repointed, so the entry would now be certifying a name
# nothing uses — which is the second failure mode this rule's own header describes:
# a deleted or renamed repo that stays on the list forever.
_t4_uncited='helm-log|projects-orchestrator'  # two workload ids left when no core doc named them (harbor#1273)
KNOWN_REPOS="${_t4_cited:+$_t4_cited|}$_t4_uncited"
for f in "$ROOT"/*.md "$ROOT"/CONTRACTS/*.md "$ROOT"/DOCTRINE/*.md; do
  [ -f "$f" ] || continue
  # Trailing sentence punctuation is stripped: `.` is in the name character
  # class (repos like `foo.bar` exist), so a repo named at the END OF A SENTENCE
  # captured its full stop and read as a different, nonexistent repo. Found by
  # the first red-green fixture this rule ever had, 2026-08-02 — the real tree
  # happened to contain no such sentence, so the rule had been passing on luck.
  for r in $(grep -oE 'VytCepas/[A-Za-z0-9_.-]+' "$f" 2>/dev/null | sed 's|VytCepas/||' \
             | sed 's/[.,;:!?]*$//' | sort -u); do
    printf '%s' "$r" | grep -qE "^($KNOWN_REPOS)$" && continue
    # A line that NEGATES the repo ("there is no VytCepas/helm") is the fix, not
    # the defect — so only flag when no negation is present on that line.
    # A TRAILING BOUNDARY, or `<owner>/helm` matches `<owner>/helm-log` and the
    # Log's perfectly good lines trip a rule aimed at a repo that does not exist.
    # Same substring-matching class this linter exists to catch elsewhere, and it
    # took ten minutes to reintroduce here.
    # `\.?` before the boundary: the SECOND half of the end-of-sentence bug. The
    # extraction above strips a trailing full stop, but this confirmation grep
    # still required a non-name character after the repo, and `.` is a name
    # character — so `VytCepas/<repo>.` extracted cleanly and then matched
    # nothing, and the rule reported no violation for a repo it had just
    # decided did not exist. A dot is a boundary only when what follows it is
    # not part of a name, which keeps a genuinely dotted repo name intact.
    grep -nE "VytCepas/$r\.?([^A-Za-z0-9_.-]|\$)" "$f" | grep -qviE 'no |never|not a fork|does not exist|~~' \
      && bad doc.repos-exist "${f#$ROOT/} names a repo that does not exist: VytCepas/$r"
  done
done
}

# ── T5 · the CLI is `harbor`; nothing describes a `helm` command ───────────
# Decided 2026-07-26 (standards/naming.md §6.4). Helm stays the LAYER name — a helm
# is where you steer from, which is exactly what L0 is — but the BINARY is
# `harbor`, because `helm` collides and not theoretically: project-init's
# prod_guard.py:50 already classes `helm uninstall|delete` as a destructive
# operation, and that guard ships in templates/base/ to every scaffolded repo.
# A `helm` CLI with an uninstall subcommand would be blocked by Harbor's own
# guard, everywhere.
#
# This rule exists because the binary DOES NOT EXIST YET. The decision is free
# today and expensive later, so it needs something holding it in place for the
# months before anyone writes the CLI.
rule_T5() {
rule "doc.no-legacy-cli the CLI is \`harbor\` — no document describes a \`helm\` command"
# NARROWED 2026-08-02 (harbor#83). The rule flagged any backticked `helm <verb>`,
# which it cannot distinguish from THE KUBERNETES PACKAGE MANAGER — a real
# third-party binary Harbor's own corpus guards (`prod_guard`'s deny table
# carries a helm-uninstall rule, and that command is one of the four used to
# verify the B10 install behaviourally). So the true, load-bearing sentence
# "…and `helm uninstall` returns ask" was unwritable, and the workaround was to
# describe the command in prose instead. §2.11: a false positive that pushes a
# writer toward VAGUER text, in the documents where precision is the point, is a
# defect — not safety.
#
# The subject is Harbor's own verb surface, and that list is already frozen in
# CONTRACTS/cli.md under CLI1. Derive it rather than restating it.
#
# BUT DERIVING IT IS NOT ENOUGH, and the ticket (#83) was wrong about this: it
# proposed keying on Harbor's verbs and named `install`/`uninstall`/`upgrade`/
# `list` as "a different program". Five of Harbor's eleven verbs — install,
# uninstall, status, verify, lint — are ALSO Kubernetes helm verbs, so that
# predicate re-flags the exact sentence the ticket was filed about. Measured
# before believing it.
#
# So subtract the other program's verb set. What survives is the set that can
# only mean Harbor: doctor, fresh, cite, observe, dash, restore. `helm observe`
# is the confusion this rule exists to catch; `helm status` is genuinely
# ambiguous from the token alone and is deliberately NOT flagged — §2.11, a rule
# that cannot tell must not guess in the direction that costs the writer
# precision. "the `helm` command" still fires regardless of verb, which is the
# phrasing the naming decision was actually about.
_t5_k8s='completion|create|dependency|docs|env|get|help|history|install|lint|list|package|plugin|pull|push|registry|repo|rollback|search|show|status|template|test|uninstall|upgrade|verify|version'
_t5_verbs="$(grep -E '^\| `harbor [a-z-]+` \|' "$ROOT/CONTRACTS/cli.md" 2>/dev/null \
             | sed -E 's/^\| `harbor ([a-z-]+)`.*/\1/' | grep -vxE "$_t5_k8s" \
             | sort -u | tr '\n' '|' | sed 's/|$//')"
if [ -z "$_t5_verbs" ]; then
  # No contract to derive from ⇒ fall back to the OLD broad pattern. Fail toward
  # noise, never toward silence: a rule that quietly stops checking because its
  # input moved is worse than one that over-reports, and the fallback is visible.
  _t5_verbs='[a-z]+'
  printf '  (T5: no verb table in CONTRACTS/cli.md — falling back to the broad pattern)\n'
fi
for f in "$ROOT"/*.md "$ROOT"/CONTRACTS/*.md "$ROOT"/DOCTRINE/*.md; do
  [ -f "$f" ] || continue
  # naming.md records the decision; DEAD-ENDS.md records the REJECTED alternative
  case "$(basename "$f")" in naming.md|DEAD-ENDS.md) continue ;; esac
  # A backticked `helm` followed by one of HARBOR'S verbs, or "the `helm` command".
  grep -nE "\`helm ($_t5_verbs)([^a-z]|\$)|the \`helm\` command" "$f" 2>/dev/null \
    | grep -qviE 'not |never|~~|instead of' \
    && bad doc.no-legacy-cli "${f#$ROOT/} describes a \`helm\` CLI — the binary is \`harbor\` (standards/naming.md §6.4)"
done
}

# ── T8 · every upstream hook has a disposition ─────────────────────────────
# The 2026-07-26 coverage sweep found 73 capabilities neither built, ticketed
# nor declined, and wrote that finding into a COMMIT MESSAGE. Two days later the
# answer to "is the backlog recorded?" was no. COVERAGE.md is the file version;
# this rule keeps it complete. The point is that a gap must be VISIBLE, not that
# it must be closed — an OPEN row passes, a missing row does not.
rule_T8() {
rule "doc.coverage-row-per-hook every upstream hook has a row in COVERAGE.md (gaps must be visible)"
_mir="${HARBOR_UPSTREAM_MIRROR:-$HOME/.harbor-upstream}"
_up="$_mir"
for _d in "$_mir"/*/install/hooks; do [ -d "$_d" ] && { _up="$_d"; break; }; done
if [ -d "$_up" ] && [ -f "$ROOT/COVERAGE.md" ]; then
  for h in "$_up"/*.hook.*; do
    [ -f "$h" ] || continue
    n="$(basename "$h")"; n="${n%%.hook.*}"
    grep -qF "\`$n\`" "$ROOT/COVERAGE.md" \
      || bad doc.coverage-row-per-hook "upstream hook with no disposition in COVERAGE.md: $n"
  done
elif [ ! -d "$_up" ]; then
  printf '  (skipped: no upstream mirror at %s)\n' "$_up"
fi
}

# ── T7 · every external citation is on the verified list ───────────────────
# Offline half of the UrlVerificationProtocol taken from upstream Research
# (PROVENANCE.md). bin/cite-verify.sh does the network half by hand; this asks
# only "was this URL ever verified at all", which is the question that catches a
# hallucinated citation. Fixtures (attack payloads, template placeholders) are
# not citations and are skipped by pattern. `_fx` below is the ONE definition of
# that list: bin/cite-verify.sh reads this very line out of this file rather than
# keeping its own copy, because it kept one and the copy drifted the moment #255
# widened this rule alone. Edit it here; nothing else defines it.
rule_T7() {
rule "doc.urls-cited every external URL a doc cites is listed in CITATIONS.md"
# A URL CONTAINING A GLOB IS A PATTERN, NOT A SOURCE (harbor#255). Capturing
# `skills/reporting-apis` forced a CITATIONS.md row for
# `https://mcp.facebook.com/*` — the value inside a `deniedMcpServers` config
# example. cite-verify.sh then fetched it and got a 404, because a wildcard path
# cannot resolve by construction, and the only way to clear the gate was to record
# a non-fact in a table whose entire value is that its last column is a human
# judgement about whether content supports a claim.
#
# `*` IS THE DISCRIMINATOR, AND IT IS THE ONLY ONE THAT IS MECHANICAL. The ticket
# proposed skipping code spans instead; that was measured and rejected — the glob
# sits in INLINE backticks in prose, exactly like every real citation in this tree
# and every row in CITATIONS.md itself, so a rule that skipped inline code would
# ignore the glob and silently stop watching most of the corpus. That is
# harbor#212's shape: a check satisfied by markup. A `*` in the path says
# "pattern" with no semantics required.
#
# WHAT IS DELIBERATELY NOT FIXED: bare hostnames in prose (`Windsor.ai`,
# `claude.ai`) are product names as often as sources, and nothing mechanical
# separates them. The existing table already answers that by ANNOTATION — several
# rows read "an endpoint, not a source" — and three rows added for #251 say the
# same. Left as a judgement in the column built for judgements, not guessed at
# here. The fenced-block half is also left alone: the hostname pass skips fences
# and the URL pass does not, which is a real inconsistency and fixes nothing
# observable today, so it is recorded on #255 rather than changed under it.
# `<NAME>` AND `$1` ARE PLACEHOLDERS, THE SAME CLASS AS THE GLOB ABOVE and added
# for the same reason (2026-09-15). Consolidating the ACCESS cards into this repo
# brought documents whose `use:`/`check:` lines are RUNNABLE COMMANDS, so the URL
# pass — which does not skip code the way the hostname pass does — extracted
# command operands as citations. Three could never verify by construction:
# `admin.shopify.com/store/<handle`, `api.example.com/api$1`, and a URL carrying a
# shell quote. Recording a non-fact in CITATIONS.md to clear a gate is the failure
# that table exists to prevent, which is exactly what harbor#255 said about the
# glob. The fence inconsistency itself is still the deferred fix, not this.
# AN OAUTH SCOPE IS A URN THAT LOOKS LIKE A URL, and it is the same class as the
# glob and the placeholder above (2026-09-15). `https://www.googleapis.com/auth/
# cloud-platform` is an IDENTIFIER in a consent request — it is never fetched,
# there is nothing at the other end to read, and a row in CITATIONS.md claiming
# it was verified as a source would be exactly the non-fact that table exists to
# keep out. Anchored on the `/auth/` path so it cannot swallow a real
# googleapis.com endpoint, which is a genuine citation and must stay checked.
# _fx is defined in the shared section at the top (harbor#537) — another rule reads it.
_t7_tmp="${TMPDIR:-/tmp}/harbor-t7.$$"
# Tracked .md when this is a checkout; a plain walk otherwise, so the rule can be
# pointed at a fixture tree via HARBOR_ROOT the way X6 uses HARBOR_FLEET_FILE.
_t7_files() {
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    (cd "$ROOT" && git ls-files '*.md' ':!vendor/*' ':!CITATIONS.md' 2>/dev/null | sed "s|^|$ROOT/|")
  else
    find "$ROOT" -name '*.md' -not -path '*/vendor/*' -not -name 'CITATIONS.md' 2>/dev/null
  fi
  # The access cards are private data (harbor#1149), so where the register exists they are judged
  # in place, as they were when they sat in the tree; where it does not, the rule says it skipped them.
  [ -z "$_t7_acc" ] || find "$_t7_acc" -maxdepth 1 -name '*.md' 2>/dev/null
}
_t7_acc=''
# The resolver beside this script, not $ROOT/bin: a HARBOR_ROOT fixture holds no roots.sh, and the
# resolver would then read the fixture's table instead of its own.
_t7_acc="$(env -u HARBOR_ROOT sh "$(dirname -- "$0")/roots.sh" --access 2>/dev/null || :)"
[ -n "$_t7_acc" ] || printf '  (skipped: no private layer, so the access cards were not scanned)\n'
# An empty register would make the case patterns below read /*.md, which is every file.
_t7_accp="${_t7_acc:-/no-access-register}"
# The ledger is CITATIONS.md plus the private layer's citations.md: the rows for hosts core does not name (harbor#1149).
# Read beside the core file, never instead of it; absent is the core ledger alone.
_t7_pcit="$(env -u HARBOR_ROOT sh "$(dirname -- "$0")/roots.sh" --private 2>/dev/null || :)"
[ -z "$_t7_pcit" ] || _t7_pcit="$_t7_pcit/citations.md"
if [ -f "$ROOT/CITATIONS.md" ]; then
  cat "$ROOT/CITATIONS.md" > "$_t7_tmp.cit"
  [ -z "$_t7_pcit" ] || [ ! -f "$_t7_pcit" ] || cat "$_t7_pcit" >> "$_t7_tmp.cit"
  _t7_files > "$_t7_tmp.files" 2>/dev/null || : > "$_t7_tmp.files"
  : > "$_t7_tmp.url"; : > "$_t7_tmp.host"
  # BARE HOSTNAMES TOO (harbor#82). The extractor was `https?://`, so a source
  # written as `help.example.com` or `s.pinimg.com/ct/core.js` was invisible —
  # the doc cited a source and nothing ever asked whether it was read. That
  # trains exactly the wrong habit: the sloppier the citation, the less scrutiny.
  #
  # THE FALSE-POSITIVE SURFACE WAS MEASURED BEFORE THIS LANDED, and the first cut
  # was unusable: 37 hits, 25 of them phantoms. `permissions.deny` matched as the
  # host `permissions.de`, `storage.buckets.delete` as `storage.buckets.de`,
  # `edit.container` as `edit.co` — because the pattern had no RIGHT-HAND
  # boundary and stopped happily in the middle of a dotted identifier. With the
  # boundary and an email exclusion the same corpus yields 12 hits, all of them
  # real hostnames. §2.11: a T7 that fires on `permissions.deny` gets the rule
  # switched off, and a disabled rule protects nothing.
  #
  # Deliberately narrow TLD list. It omits every extension this repo uses as a
  # FILE suffix even where that is a real TLD — `.sh` (guard-lib.sh) and `.md`
  # (README.md) are both country TLDs and both would fire on half the tree.
  # A ROUTE IS AN ADDRESS, NOT A CITATION, AND IT ALREADY HAS ITS OWN VERIFIER.
  # Consolidating the ACCESS cards into this repo put 65 findings into a rule that
  # asks "was this URL read as a SOURCE?" — the wrong question for an address
  # book. A card's `use:`/`check:`/`upgrade:` line names where a system LIVES, and
  # `skills/access-ledger/bin/check-routes.sh` is the instrument that verifies
  # exactly those fields, including an opt-in mode that RUNS them. Coverage moves;
  # it does not vanish. Card PROSE is still scanned, which is the half that can
  # hold a real source — stape's helpdesk article and price page are in
  # CITATIONS.md precisely because this carve-out leaves them visible.
  #
  # THE FIELD LIST IS READ OUT OF THE CHECKER, NEVER COPIED. check-routes.sh owns
  # the card schema; a second copy here would drift the first time a field is
  # added — the same reason cite-verify.sh reads `_fx` out of this file instead of
  # keeping its own. An unreadable list yields an EMPTY pattern and therefore NO
  # carve-out: the failure direction is stricter, never looser.
  _t7_routes=''
  if [ -f "$ROOT/skills/access-ledger/bin/check-routes.sh" ]; then
    _t7_routes="$(awk "/^REQUIRED_FIELDS='/,/'[[:space:]]*\$/" \
        "$ROOT/skills/access-ledger/bin/check-routes.sh" 2>/dev/null \
      | tr -d "'" | sed 's/^REQUIRED_FIELDS=//' \
      | awk 'NF { printf "%s%s", sep, $1; sep = "|" }')"
  fi
  while IFS= read -r _f; do
    [ -f "$_f" ] || continue
    # The file the extractors actually read. For a card it is a filtered copy;
    # for everything else it is the file itself, so the default corpus is
    # untouched by this block.
    _t7_src="$_f"
    case "$_f" in
      "$_t7_accp"/DISPATCH.md|"$_t7_accp"/ACCOUNTS.md)
        # DISPATCH.md's first line reads "generated by check-routes.sh --dispatch
        # — do not edit; edit the route cards", and ACCOUNTS.md's the same for
        # --accounts. Their table rows are the cards' own route and `account:`
        # fields rendered into columns, so every URL in them is already covered
        # above; the prose around the tables is NOT skipped.
        _t7_src="$_t7_tmp.card"
        grep -v '^[[:blank:]]*|' "$_f" > "$_t7_src" 2>/dev/null || : > "$_t7_src" ;;
      "$_t7_accp"/*.md)
        if [ -n "$_t7_routes" ]; then
          _t7_src="$_t7_tmp.card"
          grep -vE "^[[:blank:]]*($_t7_routes):" "$_f" > "$_t7_src" 2>/dev/null \
            || : > "$_t7_src"
        fi ;;
    esac
    grep -ohE 'https?://[^ )>"`]+' "$_t7_src" 2>/dev/null >> "$_t7_tmp.url"
    awk '
      /^[[:space:]]*```/ { infence = !infence; next }
      infence { next }
      {
        line = $0
        gsub(/https?:\/\/[^ )>"`]+/, " ", line)          # the URL half already has these
        gsub(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+/, " ", line)  # an email is not a citation
        while (match(line, /[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)*\.(com|org|net|io|dev|ai|app|cloud|edu|gov|co|uk|de|lt|eu|info|tech)([^A-Za-z0-9.-]|$)/)) {
          tok = substr(line, RSTART, RLENGTH)
          sub(/[^A-Za-z0-9]$/, "", tok)
          print tok
          line = substr(line, RSTART + RLENGTH)
        }
      }' "$_t7_src" 2>/dev/null >> "$_t7_tmp.host"
  done < "$_t7_tmp.files"
  rm -f "$_t7_tmp.card"
  for u in $(sed 's/[.,;]*$//' "$_t7_tmp.url" | grep -vE "$_fx" | sort -u); do
    grep -qF "$u" "$_t7_tmp.cit" \
      || bad doc.urls-cited "cited but never verified: $u (add it via sh bin/cite-verify.sh)"
  done
  # A host already appearing anywhere in the ledger — including inside a listed
  # URL — counts as listed. Otherwise every doc naming `github.com` would owe a
  # row for a host the file already carries thirty times.
  for h in $(grep -vE "$_fx" "$_t7_tmp.host" 2>/dev/null | sort -u); do
    grep -qF "$h" "$_t7_tmp.cit" \
      || bad doc.urls-cited "cited as a bare hostname and never verified: $h (add it via sh bin/cite-verify.sh)"
  done
  rm -f "$_t7_tmp.files" "$_t7_tmp.url" "$_t7_tmp.host" "$_t7_tmp.cit"
fi
}

# ── T6 · a "not taken" list must not name something we took ────────────────
# PROVENANCE.md's not-taken list was copied from harbor-epic.md §6 TRIM and then
# I1-ext vendored seven of the names on it. Nobody noticed for two days, because
# a not-taken list is only ever read to STOP looking at something.
#
# Same class as T2: prose restating a fact that lives on disk. The fact here is
# `vendor/skills/<slug>` existing, so check the prose against the disk.
rule_T6() {
rule "skill.not-taken-consistent no document lists a skill as not-taken while vendor/skills/ holds it"
for f in "$ROOT"/*.md "$ROOT"/CONTRACTS/*.md "$ROOT"/DOCTRINE/*.md; do
  [ -f "$f" ] || continue
  # The section runs from the NOT-taken heading to the next heading.
  sec="$(sed -n '/^## What was NOT taken/,/^## [^W]/p' "$f" 2>/dev/null)"
  [ -n "$sec" ] || continue
  # Only BACKTICKED names count as claims. The section also discusses names in
  # prose ("it previously named PrivateInvestigator, which is vendored"), and a
  # rule that fired on those would fire on its own correction note. So the
  # convention is: a not-taken claim is a backticked name, and nothing else.
  # PascalCase → the kebab-case directory convention (standards/naming.md).
  for n in $(printf '%s' "$sec" | grep -oE '`[A-Z][a-zA-Z]{3,}`' | tr -d '`' | sort -u); do
    slug="$(printf '%s' "$n" | sed 's/\([a-z0-9]\)\([A-Z]\)/\1-\2/g' | tr 'A-Z' 'a-z')"
    [ -d "$ROOT/vendor/skills/$slug" ] \
      && bad skill.not-taken-consistent "${f#$ROOT/} lists $n as not taken, but vendor/skills/$slug exists"
  done
done
}

# ── T6b · every vendored asset has an intake row (A4) ──────────────────────
# T6 catches a not-taken list naming something we took. This is the same claim
# from the other side: an asset TAKEN and not recorded. Both leave the reader
# with a wrong picture of what upstream owes us, and neither is visible by
# reading — a 29th vendored skill with no row looks exactly like 28 with rows.
#
# The check lives in bin/adoption-check.sh because A4's own falsifier calls it
# too. One mechanism, two callers; a second copy here would be the drift T2 is
# about, in the file that enforces T2.
#
# SCOPED TO A ROOT THAT ACTUALLY VENDORS. lint-test points the linter at fixture
# HARBOR_ROOTs that have no vendor/skills at all, and an unguarded call reported
# "no vendor/skills" as a violation on every one of them — a false positive on
# ~39 invocations, which §2.11 counts as a defect rather than as safety. The
# guard is the subject's existence, not a fixture opt-out: this repo has the
# directory, so the rule is live exactly where the claim can be wrong.
rule_T6b() {
rule "skill.vendor-provenance-row every vendor/skills/ directory has a row in its PROVENANCE, and vice versa"
if [ -d "$ROOT/vendor/skills" ] && [ -x "$ROOT/bin/adoption-check.sh" ]; then
  _ac="$(sh "$ROOT/bin/adoption-check.sh" 2>&1)" || {
    printf '%s\n' "$_ac" | while IFS= read -r _l; do
      case "$_l" in "  FAIL: "*) bad skill.vendor-provenance-row "${_l#  FAIL: }" ;; esac
    done
  }
fi
}

# ── T3 · every repo path a document cites resolves ─────────────────────────
# K1 does this for CONSTITUTION.md alone. The same sweep found ~/.claude/CLAUDE.md
# named as "the sole root constitution" by TWO documents, for a file that has
# never existed — so the class is not constitution-specific.
rule_T3() {
rule "doc.paths-resolve every ./path cited by a tracked doc resolves (generalises K1)"
# TWO WIDENINGS, 2026-08-02 (harbor#6). Both were fail-open, and both were found
# by needing the rule to cover a link this workstream actually writes:
#   1. `../path` was never extracted at all — only `./path` was. Every contract
#      in CONTRACTS/ points UP at the repo root (`](../DEAD-ENDS.md)`), so the
#      directory whose links are most load-bearing was the one directory whose
#      links this rule did not read.
#   2. The extractor was `sed -n 's/.*](...)/\1/p'`, and `.*` is greedy: on a
#      line carrying two links it captured only the LAST one. A dangling first
#      link on a two-link line was invisible. grep -o returns every match.
# THE SWEEP IS EVERY TRACKED MARKDOWN FILE (harbor#1149), because that is what this rule's title says. It was a list of
# globs, and the list was the defect twice: docs/README.md linked ../STATUS.md, a dev-layer file the export does not
# carry, and docs/ was not on it; then the glob list still left ~500 exported files unread (vendor/skills, skills/,
# commands/, inject.d/, patches/), so a dev link planted in a skill or an injected session note stayed green. The link
# resolves in the dev checkout and dangles in the export, which is why tests/export/selfcontained.test.sh runs this rule
# over the staged export and a core document NAMES a dev-layer file (CONTRACTS/layers.tsv) in code font, never links it.
# The set comes from git when ROOT is a checkout, so untracked output (build/, a scratch note) is not judged; a root with
# no git (a throwaway fixture) falls back to every *.md under it. _t3_deliberate is the one file that cites a dead path ON
# PURPOSE, as the input of a memory-tool test; a new deliberate dead citer is added here, by name, on purpose.
_t3_deliberate='fixtures/memory/corpus/KNOWLEDGE/Research/dead-path-citer.md'
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  _t3_docs="$(git -C "$ROOT" -c core.quotePath=false ls-files -- '*.md' 2>/dev/null)"
else
  _t3_docs="$(cd "$ROOT" && find . -name .git -prune -o -type f -name '*.md' -print 2>/dev/null | sed 's#^\./##')"
fi
while IFS= read -r _t3_rel; do
  [ -n "$_t3_rel" ] && [ "$_t3_rel" != "$_t3_deliberate" ] || continue
  f="$ROOT/$_t3_rel"
  [ -f "$f" ] || continue
  d="$(dirname "$f")"
  # `set -f` around the loop ONLY, never file-wide: this linter's other rules
  # iterate `"$ROOT"/bin/*.sh`, which IS pathname expansion and must keep working.
  # Scoped here because a markdown link target containing a glob character would
  # otherwise be expanded against the working directory — the same defect fixed
  # in bin/memory.sh, surviving in a third file.
  set -f
  for p in $(grep -oE '\]\(\.\.?/[^)#]*' "$f" 2>/dev/null | sed 's/^](//' | sort -u); do
    [ -n "$p" ] || continue
    # RELATIVE TO THE CITING FILE, not to the repo root. `./marker.md` inside
    # CONTRACTS/README.md means CONTRACTS/marker.md — resolving it against $ROOT
    # made this rule fire on six correct links the first time it ran.
    [ -e "$d/$p" ] || bad doc.paths-resolve "${f#$ROOT/} cites a path that does not exist: $p"
  done
  set +f
done <<EOF_T3
$_t3_docs
EOF_T3
}

# ── X2 · the LIVE install must not drift from the repo ─────────────────────
# X1 guards the dev SANDBOX against staleness. Nothing guarded the live config,
# and the coverage sweep found five of nine scripts in ~/.claude/bin already
# behind harbor/bin — including BOTH halves of the documented recovery path.
#
# That one is not cosmetic, and this block twice stated it larger than the
# evidence — corrected 2026-08-04 by reading the live copy rather than recalling
# it. What is measured: the live restore.sh DOES carry .helm-floor-teeth and
# .helm-pins in its slot list; what it lacks is .helm-instructions.sha256, the
# per-pin granularity check, and the floor-loss pre-flight, so a baseline that
# predates the floor restores over a floored box without refusing.
#
# The second claim was worse, because it was load-bearing: this block asserted
# the drift was "inert today only because the floor is not installed", inside
# the file that gates every commit. The floor IS installed — ask the box, not
# this comment: `sh bin/status-gen.sh --observed`. The live-vs-repo lag is
# machine state and is deliberately not written here (harbor#91); that is the
# whole reason this rule reports instead of asserting a number.
# Drift has to fail the build, not wait to be noticed at the worst moment.
#
# Advisory, not fatal, and skipped when the live dir has no copy: a developer
# machine may legitimately be mid-deploy, and this rule must not block a commit
# on the state of someone's home directory. It exists to make the drift VISIBLE.
# ── X4 · the INSTALLED skill surface vs the governed one (advisory) ─────────
# Found 2026-07-31 while measuring the ambient budget: 28 skills are vendored in
# kebab-case, 26 are installed in CamelCase, three vendored ones were never
# installed, and NOTHING detected any of it. V1 checks vendor↔PROVENANCE, X2 covers
# bin/, and skills/README.md's drift note was scoped to the Harbor-authored home.
# So the surface that costs money in every session and drives which skill fires was
# the one surface under no rule at all.
#
# ADVISORY, deliberately, exactly like X2: the live box's state is not the commit's
# fault, and a hard failure here would block every commit on a machine that has not
# reinstalled. It reports; the operator decides when to reconcile.
#
# TIER AGREEMENT IS THE PART THAT MATTERS. A skill demoted to invoked-only in the
# tree and still ambient live keeps costing bytes and keeps being selectable, so the
# repo would claim a saving that the machine never made.
rule_X4() {
rule "drift.skill-tier every installed skill has a governed counterpart, and their tiers agree (advisory)"
_sk_live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
if [ -d "$_sk_live" ]; then
  _x4_missing=0; _x4_tier=0; _x4_uninst=0; _x4_noskill=0; _x4_synced=0
  tier_of() { grep -q '^disable-model-invocation:[[:space:]]*true' "$1" 2>/dev/null && echo invoked || echo ambient; }
  for d in "$_sk_live"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    # A DIRECTORY WITH NO TOP-LEVEL SKILL.md WAS SKIPPED WITHOUT A WORD, which
    # made "installed and governed surfaces agree" a claim about the directories
    # this loop happened to recognise. Measured 2026-09-17: `synced/` held 45
    # markdown files and 26 SKILL.md below its buckets, and X4 had never mentioned
    # it. REF-9 read the same tree as Harbor's that day (harbor#528).
    #
    # Two outcomes, never a silent third. `synced/` is the harness's account-sync
    # tree, rewritten on every sync, so it has no governed counterpart by
    # construction. Its skills are COUNTED in the summary line and never compared,
    # the same exact-path ownership line REF-9 draws. Any other such directory is
    # an advisory, because X4 cannot say what it is. harbor#527 is the spike on
    # reading owners from an inventory instead of naming a path.
    if [ ! -f "$d/SKILL.md" ]; then
      _x4_below="$(find "$d" -name SKILL.md 2>/dev/null | awk 'END { print NR+0 }')"
      if [ "$n" = synced ]; then
        _x4_synced="$_x4_below"
      else
        _adv drift.skill-tier "no-skill-md:$n"; echo "  ADVISORY [drift.skill-tier] installed directory with no top-level SKILL.md, so it is not a skill X4 can compare: $n ($_x4_below SKILL.md below it)" >&2
        _x4_noskill=$(( _x4_noskill + 1 ))
      fi
      continue
    fi
    # CamelCase → kebab, then the squashed form too: `ArXiv` vendors as `arxiv`,
    # not `ar-xiv`, so a single mapping would report a false divergence.
    k="$(printf '%s' "$n" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
    ks="$(printf '%s' "$k" | tr -d '-')"
    src=""
    for cand in "$ROOT/vendor/skills/$k" "$ROOT/vendor/skills/$ks" "$ROOT/skills/$n" "$ROOT/skills/$k"; do
      [ -f "$cand/SKILL.md" ] && { src="$cand"; break; }
    done
    if [ -z "$src" ]; then
      _adv drift.skill-tier "ungoverned:$n"; echo "  ADVISORY [drift.skill-tier] installed skill under no governed copy: $n" >&2
      _x4_missing=$(( _x4_missing + 1 )); continue
    fi
    _lt="$(tier_of "$d/SKILL.md")"; _st="$(tier_of "$src/SKILL.md")"
    if [ "$_lt" != "$_st" ]; then
      _adv drift.skill-tier "tier:$n"; echo "  ADVISORY [drift.skill-tier] tier mismatch: $n is $_lt live but $_st in ${src#$ROOT/}" >&2
      _x4_tier=$(( _x4_tier + 1 ))
    fi
  done
  # The other direction: governed but never installed. Not a defect on its own —
  # a vendored skill may be deliberately unshipped — but silence about it is how
  # three of them sat unnoticed.
  for d in "$ROOT"/vendor/skills/*/; do
    [ -d "$d" ] || continue
    v="$(basename "$d")"; [ -f "$d/SKILL.md" ] || continue
    c="$(printf '%s' "$v" | awk -F- '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')"
    cs="$(printf '%s' "$v" | tr -d '-')"
    _found=0
    for cand in "$_sk_live/$c" "$_sk_live/$v" "$_sk_live/$cs"; do
      [ -f "$cand/SKILL.md" ] && { _found=1; break; }
    done
    # Case-insensitive last resort: the live names differ from the vendored ones by
    # more than hyphens on this box (ArXiv/arxiv, ISA/isa).
    [ "$_found" -eq 0 ] && [ -n "$(find "$_sk_live" -maxdepth 1 -iname "$cs" -o -maxdepth 1 -iname "$c" 2>/dev/null)" ] && _found=1
    # A SKILL MARKED DORMANT IS NOT A GAP, IT IS A DECISION. `knowledge` carries
    # a `harbor: DORMANT` marker in its header — it drives Bun memory tools that
    # workstream D has not built, so installing it would ship a skill pointing at
    # machinery that does not exist. Advising on it every run made one of the
    # three X4 lines PERMANENT NOISE: nothing an operator could do would clear
    # it, and an advisory that can never be actioned is how a reader learns to
    # skim past the two that can (No.2.11).
    if [ "$_found" -eq 0 ] && grep -q 'harbor:[[:space:]]*DORMANT' "$d/SKILL.md" 2>/dev/null; then
      _found=2   # not installed, deliberately — say so once, do not count it
      echo "  (X4) vendored and deliberately DORMANT, not a gap: $v"
    fi
    [ "$_found" -eq 0 ] && { _adv drift.skill-tier "uninstalled:$v"; echo "  ADVISORY [drift.skill-tier] vendored but not installed: $v" >&2; _x4_uninst=$(( _x4_uninst + 1 )); }
  done
  [ "$(( _x4_missing + _x4_tier + _x4_uninst + _x4_noskill ))" -eq 0 ] \
    && echo "  installed and governed surfaces agree." \
    || echo "  $_x4_missing ungoverned, $_x4_tier tier mismatch(es), $_x4_uninst not installed, $_x4_noskill directory(ies) with no SKILL.md."
  [ -d "$_sk_live/synced" ] && echo "  $_x4_synced harness-synced skill(s) under synced/ counted, not compared — the harness rewrites them on sync."
fi

# ── shared: how old is each side? (used by X2, X8 and CM3) ─────────────────
# A SECOND COPY OF pulse.sh's mtime(), deliberately: this file is a standalone
# linter and sourcing another bin script into it would make every rule depend on
# that script existing. The gotcha it encodes is not cosmetic and is why the copy
# is verbatim rather than rewritten — `stat -f` means "file system" to GNU stat
# and "format" to BSD, so on Linux the first call PRINTS filesystem fields and
# then fails, and an `||` chain appends the second call's answer to that garbage.
# Digits or nothing. See bin/pulse.sh:93 for the incident.
# _x8_mtime is defined in the shared section at the top (harbor#537) — another rule reads it.
# THE REPO SIDE'S AGE COMES FROM GIT, AND THE FILESYSTEM IS THE FALLBACK — never
# the other way round. `git worktree add` stamps every checked-out file with the
# moment of checkout, so inside a session worktree the tracked copy is ALWAYS the
# newer one and the direction verdict inverts.
#
# THIS IS harbor#139's OWN INCIDENT, REPRODUCED BY THE FIX FOR IT. Measured
# 2026-08-24 on skills/dev-tracking/SKILL.md, whose live copy carried 43 lines the
# operator had written that afternoon:
#
#   ~/harbor   copy      2026-08-21 20:21   (the real authorship)
#   live       copy      2026-08-24 14:13   (43 newer lines, the thing to keep)
#   worktree   checkout  2026-08-24 16:10   (a checkout stamp, no authorship)
#
# Run from ~/harbor the rule said "LIVE IS NEWER — do NOT reinstall". Run from
# the worktree it said "repo is newer — reinstalling is the right direction", one
# `cp -R` from deleting the newer work. `just worktree` is the house workflow
# (CI-4, harbor#150), so the inverted answer is the one most sessions see.
#
# A DIRTY OR UNTRACKED FILE KEEPS ITS MTIME, because then the working tree really
# does hold the newest authorship and git has nothing later to offer. Both probes
# are needed: `diff --quiet HEAD` says nothing about a file git has never seen.
#
# NO GIT, NO CHANGE. Outside a checkout this is _x8_mtime exactly, which is what
# keeps the rule working against a fixture directory that was never a repo.
# _x8_repo_time is defined in the shared section at the top (harbor#537) — another rule reads it.

# ── THE INSTALLER PAYLOADS, ENUMERATED ONCE ────────────────────────────────
# TWO RULES ASKED "does an installer ship this?" AND BOTH ANSWERED FROM THEIR OWN
# LIST OF INSTALLERS. Both lists said runtime-install.sh and floor-install.sh, and
# this box has a THIRD — bin/inject-install.sh, whose `PAYLOAD=` ships
# inject-hook.sh and govern-token.sh into the live bin. So X2 reported the live
# engine as UNOWNED ("no installer ships it there, so no install can refresh it")
# about a file an installer ships and refreshes on every run, and X7 could not see
# either script as a legitimate call target. Measured 2026-09-02, and it is the
# copy-drifts-silently shape DOCTRINE/doc-truth.md is about: neither list was
# wrong when written, and nothing failed when a third installer arrived.
#
# DERIVED FROM bin/*-install.sh RATHER THAN NAMED, so a fourth installer is
# covered by existing. The three payload spellings differ because the installers
# do — a shell list, a quoted list, and by-name `cp` calls — and each is read
# where it lives rather than normalised into a fourth copy somewhere.
# _installer_payload is defined in the shared section at the top (harbor#537) — another rule reads it.
}

rule_X2() {
rule "drift.config-bin the live ~/.claude/bin does not lag the repo (advisory)"
# THE CONFIG DIR IS WHEREVER CLAUDE_CONFIG_DIR SAYS, and this rule did not ask.
# bin/skills-install.sh:43 writes to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`; these
# advisories read `${HELM_LIVE_DIR:-$HOME/.claude}`. With CLAUDE_CONFIG_DIR set —
# which is exactly how every hermetic suite on this box isolates itself — the
# installer writes one place and the drift check reads another, so it compares the
# repo against a directory nothing installed into. The worse half is silent: if
# that directory has no commands/, CM3's "not installed is a choice" arm skips
# every file and the advisory reports nothing at all. Latent rather than firing
# here (the variable is unset in an ordinary session), which is precisely why it
# would have survived. HELM_LIVE_DIR stays FIRST so the existing override still
# wins for a caller that sets it deliberately.
# LIVEBIN is defined in the shared section at the top (harbor#537) — another rule reads it.
# <checkout file> <live file> <path under ~/.claude>: the direction verdict bin/ and SUITE share (harbor#753).
_x2_side() {
  _x2_rm="$(_x8_repo_time "$1")"; _x2_lm="$(_x8_mtime "$2")"
  if [ -n "$_x2_rm" ] && [ -n "$_x2_lm" ] && [ "$_x2_lm" -gt "$_x2_rm" ]; then
    _adv drift.config-bin "live-newer:~/.claude/$3"; printf "  ADVISORY [drift.config-bin] LIVE IS NEWER — this checkout lags the box; capture it, do NOT reinstall over it: ~/.claude/%s\\n" "$3"
  elif [ -n "$_x2_rm" ] && [ -n "$_x2_lm" ] && [ "$_x2_rm" -gt "$_x2_lm" ]; then
    _adv drift.config-bin "repo-newer:~/.claude/$3"; printf "  ADVISORY [drift.config-bin] repo is newer — the box lags; run the installer that ships it: ~/.claude/%s\\n" "$3"
  else
    _adv drift.config-bin "undecidable:~/.claude/$3"; printf "  ADVISORY [drift.config-bin] differs, direction UNDECIDABLE — read the diff before either copy: ~/.claude/%s\\n" "$3"
  fi
}
if [ -d "$LIVEBIN" ]; then
  for f in "$ROOT"/bin/*.sh $(_engines); do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    [ -f "$LIVEBIN/$b" ] || continue          # not deployed is a choice, not drift
    # THE TWO STALENESSES ARE DIFFERENT DEFECTS WITH DIFFERENT FIXES, and calling
    # both "lags the repo" gave one of them a remedy that can never work. bin/idea.sh
    # sat in the live bin from 2026-07-29, reported by this line on every run, while
    # NO INSTALLER SHIPS IT THERE — so "run the installer" would have refreshed
    # nothing, forever. An advisory whose fix does not exist is one the reader learns
    # to skip, and it sits in the same list as the ones that matter (No.2 clause 11).
    #
    # UNOWNED, NOT ORPHANED, AND THE FIRST WORDING SAID "REMOVE IT". THAT WAS WRONG,
    # measured 2026-08-31: this rule reads the two installer payloads and NOTHING
    # ELSE, so what it can prove is that no install will refresh the file — never
    # that nothing uses it. bin/idea.sh is the target of a live alias in the
    # operator shell rc, and acting on the advice as first written would have
    # deleted a working command. A check states what it measured; the remedy belongs
    # to the reader, who can see the shell config, the crontab and the aliases this
    # rule cannot. harbor#384 carries the underlying gap.
    #
    # AND THE DIRECTION IS NOT ASSERTABLE FROM `cmp`. Until 2026-08-31 this arm
    # said "lags the repo — run the installer" on ANY difference, which is the
    # exact destructive remedy CM3 was given three arms to avoid. Measured that
    # morning: run from a checkout 13 commits behind main, it reported four files
    # as stale when all four live copies were byte-identical to origin/main and it
    # was the WORKING TREE that was old. Following the advice would have installed
    # four older guards over four newer ones — harbor#115's incident, re-run by
    # the rule meant to warn about it. X2b's own header already refused to assert
    # direction for this reason; X2 is the copy that never got the fix. harbor#384.
    if ! cmp -s "$f" "$LIVEBIN/$b"; then
      if _installer_payload | tr ' ' '\n' | grep -Fxq "$b"; then
        _x2_side "$f" "$LIVEBIN/$b" "bin/$b"
      else
        _adv drift.config-bin "unowned:~/.claude/bin/$b"; printf "  ADVISORY [drift.config-bin] UNOWNED: ~/.claude/bin/%s — no installer ships it there, so no install can refresh it and it is frozen at whatever version it was born with. Find what references it BEFORE removing it: this rule reads the two installer payloads and NOTHING else\\n" "$b"
      fi
    fi
  done
fi
# SUITE pairs (<checkout path>:<config-dir path>) do not keep bin/'s same-name layout, so the loop
# above never saw them. An installer ships every pair, so no UNOWNED arm. Parsed here, not in
# _installer_payload: its bare names would let X7 accept $DIR/core.sh for lib/core.sh (harbor#753).
_x2_cfg="${LIVEBIN%/bin}"
for _x2p in $(sed -n 's/^SUITE="\(.*\)"$/\1/p' "$ROOT"/bin/*-install.sh 2>/dev/null); do
  case "$_x2p" in ?*:?*) ;; *) continue ;; esac
  _x2s="$ROOT/${_x2p%%:*}"; _x2d="${_x2p#*:}"
  [ -f "$_x2s" ] && [ -f "$_x2_cfg/$_x2d" ] || continue   # not deployed is a choice, not drift
  cmp -s "$_x2s" "$_x2_cfg/$_x2d" || _x2_side "$_x2s" "$_x2_cfg/$_x2d" "$_x2d"
done
}

# ── X2b · the OTHER install prefix, which nothing watched ───────────────────
# X2 checks ~/.claude/bin only, and `idea.sh` and `memory.sh` install
# to **~/.local/bin** under their own one-word names (CONTRACTS/cli.md's internal
# table says so, and says why). So the tools an operator types most often had no
# drift check at all.
#
# NOT HYPOTHETICAL. Measured 2026-08-06: ~/.local/bin/cu had been ahead of
# bin/cu.sh by the entire `dm` command, `need_arg`, and the EXIT-trap
# exit-status fix — three separate pieces of work that were done in the live
# copy and never landed here, while bin/cu.sh's own header went on calling
# itself the source of truth. Nothing in 44 rules said a word.
#
# The direction is deliberately NOT asserted. X2 says "lags"; this says
# "differs", because the failure here ran the other way — the install was the
# newer file — and a check that only looks for a stale install would have
# stayed green through the whole episode.
#
# Advisory, for X2's reason: the subject is outside the repo, so a hard failure
# would fire on a box where the tool is simply installed from somewhere else.
rule_X2b() {
rule "drift.local-bin the ~/.local/bin installs do not differ from the repo (advisory)"
# HARBOR_LOCAL_BIN, the same name runtime-install.sh takes, so the rule and the
# installer can be pointed at one fixture together. Without it this rule could
# only ever be tested against the operator's real ~/.local/bin — which is to say
# not tested, which is how its never-deployed arm stayed missing (harbor#384).
_localbin="${HARBOR_LOCAL_BIN:-$HOME/.local/bin}"
if [ -d "$_localbin" ]; then
  # THE LIST IS READ OUT OF THE INSTALLER, NOT TYPED HERE. Whichever commands
  # runtime-install.sh ships are the ones this rule must watch, and a second copy
  # of that list would drift silently while reading correctly (DOCTRINE/doc-truth).
  #
  # BOTH PAYLOAD LISTS, and reading only one of them was this rule's blind spot.
  # LINK_CMDS ships symlinks precisely because "a link cannot go stale"
  # (CONTRACTS/cli.md) — so the list this rule derived from was, by construction,
  # the list of commands that CANNOT drift, while the one command that must be a
  # COPY was invisible. `harbor` copies so that `harbor restore` survives the
  # checkout disappearing, which means it can never join LINK_CMDS; the list it
  # was missing from was the one list it could never be in.
  #
  # MEASURED 2026-09-07: ~/.local/bin/harbor was byte-identical to commit
  # 86411f3 of 2026-07-30 and missing FOUR verbs — `skills`, `inject`,
  # `constitution` and `browser`. Three had been unreachable for over a month.
  # Every `harbor <verb>` typed outside the checkout answered `unknown verb` and
  # exit 2. Nothing in the repo could see it: CLI1 compares bin/harbor against
  # CONTRACTS/cli.md and both were correct — the defect was one directory over.
  #
  # Still DERIVED from the installer, never typed here, so adding a payload
  # extends the watch automatically (DOCTRINE/doc-truth.md).
  # harbor#708: the one-word links' single owner is CONTRACTS/shims.tsv (runtime-install's LINK_CMDS is
  # gone), so the pairs are read from there: every bin/ row, as <file>:<name>.
  _x2b_owned="$(sed 's/#.*//' "$ROOT/CONTRACTS/shims.tsv" 2>/dev/null \
    | awk -F'\t' 'NF >= 3 && $1 != "name" && $3 ~ /^bin\// { sub(/^bin\//, "", $3); printf "%s:%s ", $3, $1 }')"
  _x2b_stamp="${HELM_LIVE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/$(awk -F\" '/^STAMP_NAME=/{print $2; exit}' "$ROOT/bin/install-stamp.sh" 2>/dev/null || printf '.helm-install-stamp')"
  # source .sh -> installed one-word name
  for _pair in $_x2b_owned; do
    _src="$ROOT/bin/${_pair%%:*}"
    _dst="$_localbin/${_pair#*:}"
    [ -f "$_src" ] || continue
    # A DANGLING LINK IS THE WORST OF THE THREE STATES AND USED TO BE INVISIBLE.
    # `-f` follows the symlink, so a link into a REMOVED WORKTREE failed the old
    # test exactly like an absent file and this rule said nothing — while the
    # command it names answers "No such file or directory" every time it is typed.
    if [ -L "$_dst" ] && [ ! -e "$_dst" ]; then
      _adv drift.local-bin "dangling:~/.local/bin/${_pair#*:}"; printf "  ADVISORY [drift.local-bin] DANGLING: ~/.local/bin/%s points at %s, which does not exist — re-run the installer\\n" \
        "${_pair#*:}" "$(readlink "$_dst" 2>/dev/null || printf '?')"
      continue
    fi
    # NEVER DEPLOYED IS NOT THE SAME AS DELIBERATELY NOT DEPLOYED, and folding
    # them together is how a missing `idea` stayed invisible for a month while a
    # merely-stale `cu` would have been reported (harbor#384). The discriminator
    # is the stamp: if the installer that OWNS this command has run on this box,
    # the command should be here, and its absence is a defect rather than a
    # preference. No stamp, or a command no installer ships, and this stays quiet
    # — a rule that fires on a box which never asked for the tool is one that
    # gets switched off (CONSTITUTION No.2 clause 11).
    if [ ! -e "$_dst" ]; then
      case " $_x2b_owned " in
        *" $_pair "*)
          if [ -f "$_x2b_stamp" ] && grep -q '^runtime-install ' "$_x2b_stamp" 2>/dev/null; then
            _adv drift.local-bin "never-deployed:~/.local/bin/${_pair#*:}"; printf "  ADVISORY [drift.local-bin] NEVER DEPLOYED: ~/.local/bin/%s is absent, though runtime-install.sh ships it and has run on this box — re-run it\\n" "${_pair#*:}"
          fi ;;
      esac
      continue
    fi
    # A LINK INTO THE REPO CANNOT DRIFT, which is why it is the shipped form.
    [ -L "$_dst" ] && continue
    cmp -s "$_src" "$_dst" \
      || { _adv drift.local-bin "differs:~/.local/bin/${_pair#*:}"; printf "  ADVISORY [drift.local-bin] installed copy DIFFERS (either direction): ~/.local/bin/%s vs bin/%s\\n" \
           "${_pair#*:}" "${_pair%%:*}"; }
  done
fi
}

# ── X11 · the work-log's §3 pre-push gate, installed by hand, against its source ─
# worklog/pre-push is tracked here and installed by a person copying it into the work-log repo's
# .git/hooks (its own fourth line). It is standalone on purpose, so it can never be a link, and
# nothing compared the two. MEASURED 2026-10-03 (harbor#511): installed 440 B from 2026-07-23,
# tracked 1524 B, missing 9cadc2f's fix for gitleaks 8.18.4, the version CI pins. On that version
# the old hook blocks every push and reports a secret. DIFFERS, not lags, for X2b's reason: either
# side can be the newer. Advisory for X2's reason, and it never copies: installing a hook in another
# repository is the operator's act.
rule_X11() {
rule "drift.work-log-hook the installed work-log pre-push hook does not differ from worklog/pre-push (advisory)"
_x11s="$ROOT/worklog/pre-push"
_x11r="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/MEMORY"
case "$_x11r" in "$HOME"/*) _x11v="~/${_x11r#"$HOME"/}" ;; *) _x11v="$_x11r" ;; esac
[ -f "$_x11s" ] || { say "  no worklog/pre-push in this tree"; return 0; }
# Where GIT runs the hook, which core.hooksPath or a gitdir file can move (review #942).
_x11h="$(git -C "$_x11r" rev-parse --git-path hooks/pre-push 2>/dev/null)" || _x11h=""
case "$_x11h" in /*) ;; "") _x11h="$_x11r/.git/hooks/pre-push" ;; *) _x11h="$_x11r/$_x11h" ;; esac
case "$_x11h" in "$HOME"/*) _x11hv="~/${_x11h#"$HOME"/}" ;; *) _x11hv="$_x11h" ;; esac
if [ ! -e "$_x11r/.git" ]; then
  say "  work-log pre-push: no work-log repository at $_x11v, nothing to compare"
elif [ ! -f "$_x11h" ]; then
  _adv drift.work-log-hook absent:worklog-pre-push; printf '  ADVISORY [drift.work-log-hook] the work-log repository has no pre-push hook, so its gitleaks gate is not installed — review worklog/pre-push, then copy it to %s\n' "$_x11hv"
elif cmp -s "$_x11s" "$_x11h"; then
  say "  work-log pre-push: the installed copy matches worklog/pre-push"
else
  _adv drift.work-log-hook differs:worklog-pre-push; printf '  ADVISORY [drift.work-log-hook] the installed work-log pre-push differs from worklog/pre-push — review both, then copy the right one to %s\n' "$_x11hv"
fi
}

# ── X8 · an installed Harbor-authored skill matches its tracked source ──────
# skills/README.md documents the install as `cp -R skills/<name>
# ~/.claude/skills/<name>` and admits the two copies "can drift, and nothing
# currently detects that", owing a sync check "when this directory has more than
# one inhabitant". It has several now, and the drift is not hypothetical: that
# documented command is WRONG for an already-installed skill — `cp -R src dest`
# with dest existing nests src INSIDE it, so the update silently does not land
# and a stale `<name>/<name>/` copy appears beside it. Measured 2026-08-04: the
# installed command kept its old routing table while the source carried the new
# one, and only a recursive compare showed why.
#
# Recursive, not SKILL.md-only, for that exact reason — the bulk of a skill lives
# in references/*.md, and the nested-copy failure presents as an extra PATH
# rather than a changed byte, which a single-file `cmp` cannot see.
#
# vendor/skills/ USED TO BE out of scope, and the stated reason conflated two
# different comparisons (found by the 2026-08-13 audit). "Those carry PROVENANCE.md
# and a documented re-sync diff procedure, so divergence there is a workflow rather
# than drift" is true of repo↔UPSTREAM divergence and says nothing about
# repo↔INSTALLED divergence, which is drift in exactly the sense this rule means.
# The cost of that conflation, measured: the de-persona intake fix landed in the
# repo on 2026-07-26 and `DOCTRINE/absent-by-decision.md` recorded it "closed the
# same day", while the INSTALLED copies still rendered `{{PRINCIPAL_NAME}}`
# literally in three Fabric READMEs and still said "the principal" in four more —
# for seventeen days, loadable in every session, and unfalsifiable from inside the
# repo because X8 walked only `skills/` and X4 compares tiers rather than bytes.
# Not-installed remains out of scope — that is X4's call, and duplicating it here
# would turn one advisory into two for the same fact.
rule_X8() {
rule "drift.skill-bytes an installed skill (authored or vendored) is byte-identical to its tracked source, and drift names its DIRECTION (advisory)"
# THE INSTALL RENAMES `name:`, AND THAT IS NOT DRIFT. The installer writes the
# frontmatter `name:` in the installed spelling (kebab in the repo, often
# PascalCase on the box) — the same documented rename this loop already resolves
# for DIRECTORY names via _x8_c. A raw byte compare therefore reports every
# PascalCase-installed vendored skill as drifted: measured 2026-08-13, 28 of 28
# vendored skills differed and exactly one of them had a real difference. An
# advisory that is 96% noise is one nobody reads, and CONSTITUTION §2.11 calls a
# false positive a defect rather than safety — so the `name:` line is ignored for
# the vendored tier.
#
# `description:` is ignored for the same reason and it is the same transformation
# one level in: the installer rewrites SKILL CROSS-REFERENCES inside the
# description to their installed spelling (`use red-team` -> `use RedTeam`), so
# every vendored skill that names a sibling differed too. Calibration, measured on
# 27 installed vendored skills: strict compare flagged 28, ignoring `name:` flagged
# 20, ignoring both flagged 3 — and those 3 (`fabric`, `isa`, `telos`) are exactly
# the three carrying the de-persona residue this extension was written to catch.
# Frontmatter is TRANSFORMED BY THE INSTALLER BY DESIGN, so it is not evidence
# either way; the body is, and the body is where the intake rules apply.
#
# A FUNCTION and not a `$OPTS` variable: under `sh` an empty
# variable would still expand to an argument on some shells and this file has
# already been bitten by expansion assumptions. Authored skills keep the strict
# compare — their two copies are peers and a renamed skill IS worth a line.
# GENERATED CACHES ARE NOT PAYLOAD (harbor#1109): skills-install's _diff_r skips these three, and X8
# must too, or a box-only __pycache__ reads as drift the installer itself would not see.
_x8_phys() { # <dir> -> its physical path, or nothing when it is not there
  ( CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P )
}
_x8_differs() { # <repo-dir> <live-dir> <tier> -> 0 when they differ
  if [ "$3" = vendored ]; then
    ! diff -r -x __pycache__ -x '*.pyc' -x .DS_Store -I '^name:' -I '^description:' "$1" "$2" >/dev/null 2>&1
  else
    ! diff -r -x __pycache__ -x '*.pyc' -x .DS_Store "$1" "$2" >/dev/null 2>&1
  fi
}
_x8_detail() { # <repo-dir> <live-dir> <tier>
  if [ "$3" = vendored ]; then
    diff -rq -x __pycache__ -x '*.pyc' -x .DS_Store -I '^name:' -I '^description:' "$1" "$2" 2>&1
  else
    diff -rq -x __pycache__ -x '*.pyc' -x .DS_Store "$1" "$2" 2>&1
  fi
}
# THE DIRECTION IS A PROPERTY OF THE FILES THAT DIFFER, NOT OF SKILL.md (review
# of harbor#333). _x8_differs compares with `diff -r`, so a skill drifts when ANY
# file under it differs — but the verdict below read the two SKILL.md timestamps
# and nothing else. A skill whose references/ carried the newest repo-side edit
# while its SKILL.md was older than the live copy was told LIVE IS NEWER, and the
# documented `cp -R` then overwrites that newer tracked file: the same inversion
# this rule exists to prevent, one file to the left. The cleanliness probes had
# the same blind spot, since they also only ever looked at SKILL.md.
#
# THE FILES THAT DIFFER, NOT THE WHOLE DIRECTORY, and the distinction is load
# bearing rather than an optimisation. Take the newest file on each side over ALL
# files and a skill with an identical-but-recent references/a.md on both sides
# reports the repo as newer while the only real difference is a live SKILL.md
# written later — inverting the verdict in a second way while appearing to fix
# the first. A file that is byte-identical on both sides is evidence about
# nothing: whichever way it is copied, it lands unchanged.
#
# THE PER-FILE RULES ARE UNCHANGED. The repo side still prefers the commit date
# and falls back to the mtime when the file is dirty or untracked (_x8_repo_time),
# which is what stops a worktree checkout stamp from reading as authorship and an
# uncommitted edit from being aged by a stale commit. Only the SET of files those
# rules run over has changed.
#
# `-I` IS HONOURED PER FILE for the vendored tier, for the reason _x8_differs
# honours it: the installer rewrites `name:`/`description:`, so treating that as a
# difference would let a rename the rule deliberately ignores pick the direction.
# BRANCH SKEW IS NOT INSTALL DRIFT (measured 2026-09-05). Everything below
# compares the live copy to the WORKING TREE, so a branch switch makes every
# skill that differs between branches look like drift — and it did. Run from
# ~/harbor on fix/obs-digest-isolation-by-conservation, X8 called the installed
# `tracking-standards` "INSTALLED BUT TRACKED NOWHERE" while it was committed
# AND pushed on topology-arm-measurement-pack, and called `topology` "LIVE IS
# NEWER" while the live bytes matched that branch's blob EXACTLY. Two of three
# findings wrong, in the advisory a reader would most want to promote to a gate.
#
# This does not change any verdict — it adds the line that makes the verdict
# actionable, because "which ref does the live copy come from" is the question
# the reader actually has and the working tree cannot answer.
_x8_live_manifest() { # <live-dir> <out> -> "<blob> <path>" per file, sorted; 1 when there is none
  [ -d "$1" ] || return 1
  _x8m_tmp="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
  ( cd "$1" && find . -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name .DS_Store -print | sed 's|^\./||' | LC_ALL=C sort ) > "$_x8m_tmp"
  [ -s "$_x8m_tmp" ] || { rm -f "$_x8m_tmp"; return 1; }
  while IFS= read -r _x8m_f; do
    [ -n "$_x8m_f" ] || continue
    printf '%s %s\n' "$(git -C "$ROOT" hash-object "$1/$_x8m_f" 2>/dev/null)" "$_x8m_f"
  done < "$_x8m_tmp" | LC_ALL=C sort > "$2"
  rm -f "$_x8m_tmp"
}
_x8_ref_match() { # <live-dir> <repo-rel> -> first ref whose tree equals the live copy, or nothing
  _x8r_live=$1; _x8r_rel=$2
  _x8r_want="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
  _x8_live_manifest "$_x8r_live" "$_x8r_want" || { rm -f "$_x8r_want"; return 0; }
  _x8r_got="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; _x8r_hit=''
  for _x8r_ref in $(git -C "$ROOT" for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null); do
    git -C "$ROOT" ls-tree -r --format='%(objectname) %(path)' "$_x8r_ref" -- "$_x8r_rel" 2>/dev/null \
      | sed "s| $_x8r_rel/| |" | LC_ALL=C sort > "$_x8r_got"
    if cmp -s "$_x8r_want" "$_x8r_got"; then _x8r_hit="${_x8r_ref#refs/}"; break; fi
  done
  rm -f "$_x8r_want" "$_x8r_got"
  [ -n "$_x8r_hit" ] && printf '%s\n' "$_x8r_hit"
  return 0
}
# A leftover squash-merged branch still holds the old bytes, so a ref match alone called a lagging
# box BRANCH SKEW (harbor#647). 0 when the live copy is an origin/main version older than its tip.
_x8_main_superseded() { # <live-dir> <repo-rel>
  _x8s_base="${HARBOR_BASE:-origin/main}"
  git -C "$ROOT" rev-parse --verify -q "$_x8s_base^{commit}" >/dev/null 2>&1 || return 1
  _x8s_want="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
  _x8_live_manifest "$1" "$_x8s_want" || { rm -f "$_x8s_want"; return 1; }
  _x8s_got="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; _x8s_rc=1; _x8s_tip=1
  for _x8s_c in $(git -C "$ROOT" rev-list "$_x8s_base" -- "$2" 2>/dev/null); do
    git -C "$ROOT" ls-tree -r --format='%(objectname) %(path)' "$_x8s_c" -- "$2" 2>/dev/null \
      | sed "s| $2/| |" | LC_ALL=C sort > "$_x8s_got"
    if cmp -s "$_x8s_want" "$_x8s_got"; then [ "$_x8s_tip" = 1 ] || _x8s_rc=0; break; fi
    _x8s_tip=0
  done
  rm -f "$_x8s_want" "$_x8s_got"
  return "$_x8s_rc"
}

_x8_same_file() { # <repo-file> <live-file> <tier> -> 0 when equal for X8's purposes
  if [ "$3" = vendored ]; then
    diff -q -I '^name:' -I '^description:' "$1" "$2" >/dev/null 2>&1
  else
    cmp -s "$1" "$2"
  fi
}
_x8_dir_times() { # <repo-dir> <live-dir> <tier> -> "<repo-newest> <live-newest>"
  _x8t_r=""; _x8t_l=""
  while IFS= read -r _x8t_rel; do
    [ -n "$_x8t_rel" ] || continue
    _x8t_rf="$1/$_x8t_rel"; _x8t_lf="$2/$_x8t_rel"
    if [ -f "$_x8t_rf" ] && [ -f "$_x8t_lf" ]; then
      if _x8_same_file "$_x8t_rf" "$_x8t_lf" "$3"; then continue; fi
    fi
    if [ -f "$_x8t_rf" ]; then
      _x8t_v="$(_x8_repo_time "$_x8t_rf")"
      case "$_x8t_v" in ''|*[!0-9]*) ;; *)
        if [ -z "$_x8t_r" ] || [ "$_x8t_v" -gt "$_x8t_r" ]; then _x8t_r="$_x8t_v"; fi ;;
      esac
    fi
    if [ -f "$_x8t_lf" ]; then
      _x8t_v="$(_x8_mtime "$_x8t_lf")"
      case "$_x8t_v" in ''|*[!0-9]*) ;; *)
        if [ -z "$_x8t_l" ] || [ "$_x8t_v" -gt "$_x8t_l" ]; then _x8t_l="$_x8t_v"; fi ;;
      esac
    fi
  done <<X8_RELPATHS
$( { ( cd "$1" 2>/dev/null && find . -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name .DS_Store -print 2>/dev/null ); ( cd "$2" 2>/dev/null && find . -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name .DS_Store -print 2>/dev/null ); } | sed 's|^\./||' | sort -u )
X8_RELPATHS
  printf '%s %s' "$_x8t_r" "$_x8t_l"
}
_x8_live="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"
if [ -d "$_x8_live" ]; then
  _x8_drift=0; _x8_checked=0; _x8_seen=''; _x8_orphan=0
  for d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ -f "$d/SKILL.md" ] || continue
    # WHICH TIER, because the safe repair differs. For an authored skill the repo
    # and the box are peers and mtime decides. For a VENDORED skill the repo copy
    # is the de-persona'd, intake-corrected artefact — so "live is newer" must not
    # be read as "capture it", which would import upstream persona text straight
    # back into the tree the intake rules exist to keep clean.
    case "$d" in "$ROOT"/vendor/skills/*) _x8_tier=vendored ;; *) _x8_tier=authored ;; esac
    # Resolve the INSTALLED name the same way X4 does. The tracked home is
    # kebab-case (naming.md) but a skill can be installed CamelCase — `mail-cal`
    # shipped CamelCase until 2026-08-05, when the install was renamed kebab to
    # match its source. Matching only the exact name exempted precisely the one
    # skill whose names disagreed, which is where a hand-install is likeliest and
    # so where drift is likeliest. Caught while falsifying this rule. No skill
    # currently needs the fallback; it stays because the next hand-install is
    # where the divergence returns, and an exemption that silent is worth keeping
    # a dead branch to prevent.
    _x8_c="$(printf '%s' "$n" | awk -F- '{for(i=1;i<=NF;i++) printf "%s%s", toupper(substr($i,1,1)), substr($i,2)}')"
    _x8_s="$(printf '%s' "$n" | tr -d '-')"
    _x8_dst=""
    for cand in "$_x8_live/$n" "$_x8_live/$_x8_c" "$_x8_live/$_x8_s"; do
      [ -f "$cand/SKILL.md" ] && { _x8_dst="$cand"; break; }
    done
    # ── TRACKED BUT NOT INSTALLED (harbor#252), A SILENT `continue` UNTIL NOW ──
    # X8 compares PAIRS, so both unpaired directions were invisible: a tracked
    # skill on no box, and — the expensive one, below — an installed skill with
    # no tracked source anywhere. Measured 2026-08-21: one of each.
    #
    # Reported, never `bad`, and the wording does not assume a repair. A tracked
    # skill deliberately absent from THIS box is legitimate — the repo is not a
    # manifest of one machine — so this says what is true and leaves the decision
    # alone. §2.11: an advisory that demands an install nobody wants is one the
    # reader learns to skip.
    _x8_norm="$(printf '%s' "$n" | tr 'A-Z' 'a-z' | sed 's/[_-]//g')"
    _x8_seen="$_x8_seen $_x8_norm"
    if [ -z "$_x8_dst" ]; then
      _adv drift.skill-bytes "uninstalled:${d#$ROOT/}"; echo "  ADVISORY [drift.skill-bytes] tracked here, installed on no box: ${d#$ROOT/} — intended, or a deploy nobody ran?" >&2
      continue
    fi
    _x8_checked=$(( _x8_checked + 1 ))
    # ── A GENERATED SKILL HAS NO AUTHORITATIVE COPY — ONLY A GENERATOR ──────
    # Both branches below advise moving BYTES between two directories, and for
    # a generated skill both are wrong in the destructive direction. skill-catalog
    # is produced by bin/skill-catalog.sh from whatever is in ~/.claude/skills, so
    # "capture the live copy into the repo" writes an output into a source
    # position, where the next generator run silently reverts it and any
    # hand-written line in between is gone; and "reinstall, the box lags"
    # deploys a book generated against a different skill set. The drift itself
    # is also not drift in the sense the rest of this rule means: the installed
    # book differs because the SKILLS changed, and the repair is to regenerate,
    # after which the difference is gone without either copy being touched.
    #
    # Detected from the marker the generator itself writes into its output, so
    # this cannot go stale against a renamed script — the advice names whatever
    # command the file says produced it.
    _x8_gen="$(sed -n 's/^Generated by `\([^`]*\)`.*/\1/p' "$d/SKILL.md" 2>/dev/null | head -1)"
    if [ -n "$_x8_gen" ]; then
      # THE INSTALLED COPY OF A GENERATED SKILL IS COMPOSED FROM THE CONFIG DIR IT SITS IN (harbor#1149): the skill catalog
      # lists every skill installed there, the box's and the packs' beside the repo's, so it differs from the tracked copy
      # by design on any box with a skill the repo does not ship, and a byte diff would call every such box drifted for
      # ever, with a repair that cannot clear it. The question is whether it is what the generator writes for THIS dir, and
      # the generator answers that (`install --check`). A generator that cannot be asked falls back to the byte diff.
      if [ -f "$ROOT/$_x8_gen" ]; then
        _x8_cfg="${_x8_live%/skills}"
        if [ "$(_x8_phys "$_x8_cfg")" = "$(_x8_phys "$HOME/.claude")" ]; then
          sh "$ROOT/$_x8_gen" install --check --live >/dev/null 2>&1; _x8_grc=$?
        else
          sh "$ROOT/$_x8_gen" install --check --dir "$_x8_cfg" >/dev/null 2>&1; _x8_grc=$?
        fi
        case "$_x8_grc" in
          0) ;;
          1) _adv drift.skill-bytes "generated:$n"; echo "  ADVISORY [drift.skill-bytes] GENERATED — the installed copy is not what the generator writes for this config dir; do not copy either way, regenerate: $n -> sh $_x8_gen install --apply" >&2
             _x8_drift=$(( _x8_drift + 1 )) ;;
          *) _adv drift.skill-bytes "generator-failed:$n"; echo "  ADVISORY [drift.skill-bytes] GENERATED — the generator FAILED (rc=$_x8_grc), so $n was not judged: sh $_x8_gen install --check --live" >&2 ;;
        esac
      elif _x8_differs "$d" "$_x8_dst" "$_x8_tier"; then
        _adv drift.skill-bytes "generated:$n"; echo "  ADVISORY [drift.skill-bytes] GENERATED — do not copy either way, regenerate: $n -> sh $_x8_gen" >&2
        _x8_drift=$(( _x8_drift + 1 ))
      fi
      continue
    fi
    if _x8_differs "$d" "$_x8_dst" "$_x8_tier"; then
      # DIRECTION, NOT JUST DIFFERENCE (harbor#139). "Installed copy differs from
      # tracked source" is true and points at the wrong repair: the natural
      # reading of a drift advisory is "reinstall to fix it", the documented
      # install is a `cp -R`, and on 2026-08-06 that was one keystroke away from
      # deleting 38 lines of newer work in `measurement-debug`. The rule already
      # holds both files; it can hold their mtimes too.
      _x8_times="$(_x8_dir_times "$d" "$_x8_dst" "$_x8_tier")"
      _x8_rm="${_x8_times% *}"
      _x8_lm="${_x8_times#* }"
      if _x8_main_superseded "$_x8_dst" "skills/$n"; then
        _adv drift.skill-bytes "repo-newer:$n"; echo "  ADVISORY [drift.skill-bytes] repo is newer — the box lags; reinstalling is the right direction: $n -> ${_x8_dst##*/}" >&2
        echo "             the live bytes are an older ${HARBOR_BASE:-origin/main} version of this skill, whatever branch also holds them" >&2
      elif [ -n "$_x8_rm" ] && [ -n "$_x8_lm" ] && [ "$_x8_lm" -gt "$_x8_rm" ] \
         && [ "$_x8_tier" = vendored ]; then
        _adv drift.skill-bytes "vendored-live-newer:$n"; echo "  ADVISORY [drift.skill-bytes] VENDORED and live is newer — INSPECT, do not capture blind: $n -> ${_x8_dst##*/}" >&2
        echo "             the repo copy is the de-persona'd intake artefact; a blind capture reimports upstream persona text" >&2
      elif [ -n "$_x8_rm" ] && [ -n "$_x8_lm" ] && [ "$_x8_lm" -gt "$_x8_rm" ]; then
        # THE MARKER GOES ON THE ADVISORY LINE, not a continuation. Measured
        # 2026-09-05: it was a continuation, and lint-test's own reader
        # (`grep 'ADVISORY \[X8\]'`) filtered it out — the assertion below could
        # never see the string it asserts. A qualifier that reverses the action
        # belongs where the action is read, and every reader here greps.
        _x8_ref="$(_x8_ref_match "$_x8_dst" "skills/$n")"
        if [ -n "$_x8_ref" ]; then
          _adv drift.skill-bytes "branch-skew:$n"; echo "  ADVISORY [drift.skill-bytes] BRANCH SKEW — the live bytes are committed verbatim on $_x8_ref, so this is NOT newer work: $n -> ${_x8_dst##*/}" >&2
          echo "             this tree is older than $_x8_ref; capturing would re-import that ref, not rescue anything" >&2
        else
          _adv drift.skill-bytes "live-newer:$n"; echo "  ADVISORY [drift.skill-bytes] LIVE IS NEWER — capture it into the repo, do NOT reinstall: $n -> ${_x8_dst##*/}" >&2
        fi
      elif [ -n "$_x8_rm" ] && [ -n "$_x8_lm" ] && [ "$_x8_rm" -gt "$_x8_lm" ]; then
        _x8_ref="$(_x8_ref_match "$_x8_dst" "skills/$n")"
        if [ -n "$_x8_ref" ]; then
          _adv drift.skill-bytes "branch-skew:$n"; echo "  ADVISORY [drift.skill-bytes] BRANCH SKEW — the live bytes are committed verbatim on $_x8_ref, so the box is NOT lagging: $n -> ${_x8_dst##*/}" >&2
          echo "             this tree is newer than $_x8_ref; installing from here is a branch decision, not a repair" >&2
        else
          _adv drift.skill-bytes "repo-newer:$n"; echo "  ADVISORY [drift.skill-bytes] repo is newer — the box lags; reinstalling is the right direction: $n -> ${_x8_dst##*/}" >&2
        fi
      else
        # SAME MTIME, OR UNREADABLE. Two same-day edits and a `cp` that preserved
        # nothing both land here, and neither side can be called authoritative
        # from outside. Saying so is the honest answer; guessing is how the wrong
        # copy gets destroyed.
        _adv drift.skill-bytes "undecidable:$n"; echo "  ADVISORY [drift.skill-bytes] differs, direction UNDECIDABLE — read the diff before either copy: $n -> ${_x8_dst##*/}" >&2
      fi
      _x8_detail "$d" "$_x8_dst" "$_x8_tier" | sed "s|$HOME|~|g;s|^|      |" >&2
      _x8_drift=$(( _x8_drift + 1 ))
    fi
  done
  # ── THE OTHER UNPAIRED DIRECTION, AND THE COSTLY ONE (harbor#252) ────────
  # An installed skill with NO tracked source is invisible to a pair-wise rule:
  # the loop above walks the REPO, so a live-only skill is never even visited.
  # It has no review path, no history, and — the part that bites — NO SECOND
  # COPY, because ~/.claude is never pushed anywhere (§3). A disk failure or a
  # careless reinstall is the whole backup story.
  #
  # Measured 2026-08-21: `dev-tracking`, 819 B of ambient description, the
  # largest single ambient skill on the box, tracked in no repository at all —
  # not harbor, not any governed project. It had been invisible for as long as
  # it existed, and it stayed invisible through an audit that was specifically
  # counting ambient skills, because the instrument could not see an orphan.
  #
  # NAME MATCHING IS NORMALISED, not exact: the installer renames kebab to
  # PascalCase by design (`root-cause-analysis` -> `RootCauseAnalysis`), so an
  # exact compare would report twelve orphans that are nothing of the kind. Case
  # folded and separators dropped — `tr -d '[_-]'` is deliberately spelled with
  # the hyphen LAST, because BSD tr reads a leading `-` as a flag and this
  # estate's userland is BSD.
  for _x8_l in "$_x8_live"/*/; do
    [ -f "$_x8_l/SKILL.md" ] || continue
    _x8_ln="$(basename "$_x8_l")"
    _x8_lnorm="$(printf '%s' "$_x8_ln" | tr 'A-Z' 'a-z' | sed 's/[_-]//g')"
    case " $_x8_seen " in *" $_x8_lnorm "*) continue ;; esac
    _x8_ref="$(_x8_ref_match "$_x8_l" "skills/$_x8_ln")"
    if [ -n "$_x8_ref" ]; then
      _adv drift.skill-bytes "branch-skew:$_x8_ln"; echo "  ADVISORY [drift.skill-bytes] not in THIS working tree, but committed on $_x8_ref — branch skew, not drift: $_x8_ln" >&2
    else
      _adv drift.skill-bytes "untracked:$_x8_ln"; echo "  ADVISORY [drift.skill-bytes] INSTALLED BUT TRACKED NOWHERE — no review path and no second copy, on any ref: $_x8_ln" >&2
    fi
    _x8_orphan=$(( _x8_orphan + 1 ))
  done
  if [ "$_x8_checked" -eq 0 ]; then
    echo "  no Harbor-authored skill is installed here — nothing to compare."
  elif [ "$_x8_drift" -eq 0 ]; then
    echo "  $_x8_checked installed skill(s) match their tracked source."
  else
    echo "  $_x8_drift of $_x8_checked installed skill(s) have drifted."
  fi
  [ "$_x8_orphan" -gt 0 ] && \
    echo "  $_x8_orphan installed skill(s) are tracked nowhere — capture, or accept they exist on one disk."
fi

# ── X7 · every script an INSTALLED script calls is itself installed ─────────
# X2's `[ -f "$LIVEBIN/$b" ] || continue  # not deployed is a choice, not drift`
# is the blind spot this closes, and it hid two live defects at once. Not
# deployed is a choice — until an installed script INVOKES the thing, at which
# point absence is not a choice, it is a call into nothing.
#
# Both were found on 2026-08-02, in one session, on this box:
#   · context-resolve.sh:203 guards its SessionStart peer report on
#     `[ -f "$DIR/fleet-sessions.sh" ]` and prints nothing when absent — correct,
#     since the reader must never print a count it could not measure. No
#     installer shipped fleet-sessions.sh, so that guard was permanently false
#     and the report had NEVER FIRED, on a box that routinely runs four
#     concurrent sessions across two worktrees of one repo.
#   · guard-integrity.sh had no update path at all outside floor-install
#     --with-b6, which the install order holds back (pass-score.sh reports on
#     the floor; it does not gate the installer — floor-install.sh never calls it).
# Neither was invisible for want of a test. Both were invisible because nothing
# asked the one question that spans the two lists: does the payload contain
# everything the payload calls?
#
# ADVISORY, in the X2/X4/X5 family — same class, fourth surface: the artifact
# under governance is not the artifact doing the work. Hard-failing would turn
# the build red on a condition whose repair is a judgement call about blast
# radius (floor-deny.sh is a settings MUTATOR; putting it in a config dir is a
# decision about what a session can reach, and CONSTITUTION § "Encoding a fix is
# a human-gated act" makes that the operator's, not this linter's).
#
# $DIR and $CFG are the tell, and the reason this is cheap to get right: every
# installer resolves the CONFIG dir into one of those two, and the repo checkout
# into $SRC or $ROOT. Comments are stripped — a comment naming a script is prose.
#
# $SRC IS NOT ALWAYS THE REPO, AND THAT EXEMPTION HID harbor#313 FOR AS LONG AS IT
# STOOD. This comment used to end "a reference through $SRC is a repo-local call and
# correctly invisible here". That is true only of a script which is never installed.
# `sandbox-make.sh` sets SRC to `dirname "$0"` — its OWN directory — and is itself in
# runtime-install's FILES, so on a real box its $SRC is $CFG/bin. Its
# `sh "$SRC/floor-install.sh"` therefore resolved to nothing, `--with-floor` worked
# from a checkout and failed from the install, and this rule — the one rule whose
# entire job is "does the payload contain everything the payload calls" — read the
# call and exempted it. A blind spot in the check for blind spots.
#
# SO $SRC IS FOLLOWED, BUT ONLY WHERE IT MEANS THE CONFIG DIR: the script defines
# SRC as its own directory AND is in the payload. Both halves are load-bearing. Drop
# the first and every repo-only tool that resolves SRC to $ROOT gets reported for
# calls that are genuinely repo-local. Drop the second and a script nobody installs
# is judged by where an installed copy would look, which is the exemption's original
# and correct point.
#
# MEASURED BEFORE AND AFTER on this tree: two payload scripts resolve SRC to their
# own directory (pulse-notify.sh, sandbox-make.sh), and the widened scan reports
# EXACTLY ONE finding — the harbor#313 call. So this does not trade a blind spot for
# noise, which would get the advisory skimmed and cost more than it bought.
# _x7_src_is_own_dir is defined in the shared section at the top (harbor#537) — another rule reads it.
# A READ IS NOT A CALL INTO NOTHING, and that is the only exemption this rule can
# safely carry. "Is the call guarded?" is NOT the axis — the first attempt at this
# used it and lint-test's own arm 2 went red within a minute, correctly: X7's
# FOUNDING case is context-resolve.sh guarding `[ -f "$DIR/fleet-sessions.sh" ]`,
# where the existence test is precisely what HID the loss for months. Exempting
# guarded calls would have retired the rule's reason for existing while leaving it
# in the file, which is worse than deleting it.
#
# So the axis is EXECUTED vs READ. floor-install.sh reads runtime-install's FILES
# line with `sed -n … "$SRC/runtime-install.sh"`, and the comment above it records
# that an empty read fails SAFE, toward copying — an absent file there degrades a
# derivation, it does not call into nothing. Every other reference in this tree is
# `sh "$SRC/x"`, the same shape as the founding case.
#
# IT FAILS TOWARD REPORTING. A reference is exempt only when EVERY non-comment
# occurrence is a read tool; an assignment (`_mc="$SRC/merged-check.sh"`, executed
# later through the variable) matches no read pattern and is therefore reported,
# which is the direction a rule about missing files has to lean.
# _x7_read_only is defined in the shared section at the top (harbor#537) — another rule reads it.
}
rule_X7() {
rule "drift.payload-closure every script that an installed script invokes is itself in an installer payload (advisory)"
# ONE ENUMERATOR, SHARED WITH X2 — see its header for the third installer both
# rules were blind to. The alias is kept so this rule's later references read as
# they always did.
_x7_payload() { _installer_payload; }
# `grep -c .` PRINTS 0 and EXITS 1 on empty input, so `$(… || echo 0)` yields the
# TWO-LINE string "0\n0" — and `[ "0\n0" -lt 10 ]` is a test ERROR, not false, so
# the guard fell through to its else branch and checked nothing. The guard
# against vacuity was itself vacuous (CONSTITUTION №2.10). Caught by running the
# linter from a bin/-only copy, where the payload genuinely cannot be read.
_X7P="$(_x7_payload | tr ' ' '\n' | grep -c . 2>/dev/null || true)"
_X7P="$(printf '%s' "${_X7P:-0}" | tr -dc '0-9')"
if [ "${_X7P:-0}" -lt 10 ]; then
  # A payload that came back empty would make every check below vacuously pass —
  # the shape CONSTITUTION №2.10 calls worse than no test. Say so instead.
  _adv drift.payload-closure payloads-unreadable; printf '  ADVISORY [drift.payload-closure] could not read the installer payloads (got %s entries) — this rule verified NOTHING\n' "${_X7P:-0}" >&2
else
  # OUT OF $ROOT: a scratch file in the repo is picked up by the tracked-file
  # rules further down and by anything reading `git status`.
  _X7F="${TMPDIR:-/tmp}/.helm-x7-payload.$$"
  _x7_payload | tr ' ' '\n' | grep . | sort -u > "$_X7F"
  # sort -u on the SCAN list too. guard-integrity.sh reaches the payload twice —
  # once via REFRESH_ONLY, once via floor-install's by-name cp — and an undeduped
  # loop reported its one finding twice, which reads as two defects.
  for _t in $(_x7_payload | tr ' ' '\n' | grep . | sort -u); do
    [ -f "$(_payload_src "$_t")" ] || continue
    # NOTE the single-quoted ERE. Written in double quotes, `\$` reaches grep as a
    # bare `$` — an end-of-line anchor — and the pattern silently matches nothing.
    # That false negative is how this rule first reported a clean repo it had not
    # looked at (CONSTITUTION №2.10, caught by testing the probe against a target
    # known to be absent).
    # The variable set scanned depends on the script: $SRC joins it only where
    # $SRC provably means the config dir (see _x7_src_is_own_dir above). The
    # message names the variable actually found, so a reader can go straight to
    # the line rather than guessing which of three spellings was matched.
    _x7vars='(DIR|CFG)'
    _x7_src_is_own_dir "$_t" && _x7vars='(DIR|CFG|SRC)'
    # $SRC_DIR is the same variable under the name fleet-snapshot-refresh.sh (and the scripts launchd runs) use. The pattern above
    # read `$DIR` and `$SRC` only, so a call through `$SRC_DIR/` was never scanned: status-obligations.sh sat out of every payload
    # while its sibling callees were in it (harbor#1115). Same proviso as $SRC: only where it provably is the script's own dir.
    _x7_src_is_own_dir "$_t" SRC_DIR && _x7vars="${_x7vars%)}|SRC_DIR)"
    grep -v '^[[:space:]]*#' "$(_payload_src "$_t")" 2>/dev/null \
      | grep -oE '\$'"$_x7vars"'(/bin)?/[a-z0-9-]+\.(sh|awk)' \
      | sed -E 's#^\$([A-Z_]+).*/#\1 #' | sort -u | while read -r _v _r; do
          [ "$_r" = "$_t" ] && continue
          grep -Fxq "$_r" "$_X7F" 2>/dev/null && continue
          _x7_read_only "$_t" "$_r" && continue
          _adv drift.payload-closure "bin/$_t->$_r"; printf '  ADVISORY [drift.payload-closure] bin/%s invokes $%s/%s, which no installer ships — the call resolves to nothing on a real box\n' "$_t" "$_v" "$_r" >&2
        done
  done
  # A SUITE pair ships a suite that runs on the box and calls its subjects through $B/, the installed
  # bin/ (recover-test's B="$T_ROOT/bin"), which the loop above never read (harbor#756).
  for _x7p in $(sed -n 's/^SUITE="\(.*\)"$/\1/p' "$ROOT"/bin/*-install.sh 2>/dev/null | tr ' ' '\n' | grep ':' | sort -u); do
    _x7s="${_x7p%%:*}"
    if [ ! -f "$ROOT/$_x7s" ]; then
      _adv drift.payload-closure "suite-missing:$_x7s"; printf '  ADVISORY [drift.payload-closure] SUITE %s is not in this checkout — its calls were NOT checked\n' "$_x7s" >&2; continue
    fi
    grep -v '^[[:space:]]*#' "$ROOT/$_x7s" 2>/dev/null | grep -oE '\$B/[a-z0-9-]+\.(sh|awk)' | sed 's#^\$B/##' | sort -u \
      | while read -r _r; do
          grep -Fxq -- "$_r" "$_X7F" 2>/dev/null && continue
          _adv drift.payload-closure "$_x7s->$_r"; printf '  ADVISORY [drift.payload-closure] SUITE %s (installed as %s) invokes $B/%s, which no installer ships — the call resolves to nothing on a real box\n' "$_x7s" "${_x7p#*:}" "$_r" >&2
        done
  done
  rm -f "$_X7F"
fi
}

# ── the folders macOS guards are never walked (harbor#658) ─────────────────
# macOS privacy (TCC) guards these home folders, and a process with no grant does
# not reliably get EPERM there. Measured 2026-09-24: eleven finds sat 4h26m at 0%
# CPU with their working directory in ~/Music, behind a consent prompt that a
# newly registered runner's first job had raised — and every later reader of the
# folder queued behind it: this linter, the pre-push hook, two CI jobs. b784e11
# (2026-08-25) pruned ~/Library alone; this is the set. Coverage: a walk from
# $HOME no longer finds a checkout INSIDE one of these folders; a fleet root that
# is itself inside one is still walked, because only these exact paths are pruned.
guarded_find() { # guarded_find <root> <maxdepth> <find expression...>
  _gf_r="$1"; _gf_d="$2"; shift 2
  find "$_gf_r" -maxdepth "$_gf_d" \( -path "$HOME/Library" -o -path "$HOME/Music" \
    -o -path "$HOME/Pictures" -o -path "$HOME/Movies" -o -path "$HOME/Desktop" \
    -o -path "$HOME/Documents" -o -path "$HOME/Downloads" -o -path "$HOME/.Trash" \) \
    -prune -o "$@"
}

# ── X5 · no deployed prod_guard.py diverges from the plugin it came from ───
# THE GAP THIS CLOSES. projects-orchestrator#199 existed because a scaffolded
# prod_guard.py sat a week behind the plugin it was copied from, with the
# symlink refusal (PI-903) missing, and NOTHING compared the two. X2 covers live
# bin/ vs repo and X4 covers installed skills vs vendored; neither looks at a
# copied hook. Same class, third surface: the artifact under governance is not
# the artifact doing the work.
#
# Advisory, for X2's reason: it reads paths OUTSIDE this repo, so a hard failure
# would depend on the machine the build runs on. On a hosted runner there is no
# plugin tree and every branch below simply says nothing — which is the correct
# behaviour for a check whose subject is absent, and the reason this lives here
# and not in prod-guard-test.sh, where it made a hermetic suite depend on the
# operator's home directory. Since harbor#696 that suite blocks on the ambient
# install vs the mirror where both exist (loud SKIP elsewhere); this stays the
# advisory second signal, and the only one that walks scaffolded copies.
rule_X5() {
rule "drift.prod-policy-copy every deployed prod_guard.py matches the AUTHORITATIVE copy (advisory)"
# THE BASELINE IS THE POINT OF THIS RULE, and the first version got it wrong.
# It compared deployed copies against the marketplace mirror under
# ~/.claude/plugins — which is itself STALE: HEAD c2b81b1 (2026-07-13) against an
# upstream fix in ac85947 (2026-07-26, project-init#904, the PI-903 symlink
# refusal). All three installed plugin copies are 266 lines with zero
# `is_symlink`. So the rule would have called the VULNERABLE copy "matching" and
# projects-orchestrator's CORRECT one "diverged" — precisely inverted.
#
# Fourth instance of one class in this ticket: the artifact under governance is
# not the artifact doing the work. Here the artifact was the BASELINE.
_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
_SRC="${PROJECT_INIT_SRC:-${PORT_ROOT:-$HOME/port}/project-init}/templates/base/dot_agents/hooks/prod_guard.py"
_MIRROR="$_CFG/plugins/marketplaces/project-init/plugins/project-init-workflow/hooks/prod_guard.py"
if [ -f "$_SRC" ]; then _BASE="$_SRC"; _BKIND="source repo"
else _BASE="$_MIRROR"; _BKIND="marketplace mirror"; fi
if [ -f "$_BASE" ]; then
  # The channel first: a stale mirror means every NEW scaffold is born wrong, which
  # no per-copy comparison can show.
  if [ -f "$_SRC" ] && [ -f "$_MIRROR" ] && ! cmp -s "$_SRC" "$_MIRROR"; then
    _adv drift.prod-policy-copy mirror-stale; printf '  ADVISORY [drift.prod-policy-copy] the marketplace mirror is STALE against the source repo — new scaffolds inherit it\n'
  fi
  _n=0
  # Depth-bounded: this runs in every lint, and an unbounded $HOME walk is how a
  # gate becomes too slow to keep. Measured at 0.1s locally.
  #
  # DEPTH IS NOT THE ONLY WAY THIS WALK GOES UNBOUNDED, and the line above was
  # measured true and still let CI hang for hours. `-maxdepth 4` bounds how far
  # find DESCENDS; it does nothing about a directory that never answers, and
  # ~/Library/Group Containers sits at depth 2. macOS TCC protects it, so a
  # process without Full Disk Access — which is every launchd-started CI runner —
  # BLOCKS there rather than getting EPERM and moving on.
  #
  # MEASURED 2026-08-25: the conventions-linter job for PR #356 ran 80 minutes
  # having consumed 0.16 SECONDS of CPU. Not slow — blocked. Every one of the 20
  # Group Containers probed individually blocked the same way, which is what
  # identifies it as the privacy layer rather than one broken app. It stalled the
  # whole merge queue on the single self-hosted runner, and it would have stalled
  # every future lint on this box, because nothing about it is transient.
  #
  # Pruning ~/Library costs NO coverage: the subject of this rule is a scaffolded
  # repo's .agents/hooks/prod_guard.py, and a project checkout never lives inside
  # ~/Library. The falsifier is a deployed prod_guard.py under ~/Library that this
  # rule stops reporting — if one is ever found there, the bug is the scaffold's
  # location, not this prune.
  # The port root is walked as well as $HOME (harbor#619). After the 2026-09-23
  # move every checkout sits at ~/port/<repo>, which puts its prod_guard.py at
  # depth 5 from $HOME, and find does not follow the compatibility symlinks left
  # at ~/<repo>. Measured that day: the $HOME walk found 0 deployed copies,
  # silently — an advisory that reports on nothing reads exactly like one that
  # found everything current. From the port root the copies are back at depth
  # 4: 8 found, the same 8 a depth-5 walk of $HOME finds.
  for _c in "$_CFG/hooks/prod_guard.py" \
            $(for _gr in "$HOME" "${PORT_ROOT:-$HOME/port}"; do
                guarded_find "$_gr" 4 -path '*/.agents/hooks/prod_guard.py' \
                  -not -path '*/plugins/*' -print 2>/dev/null
              done); do
    [ -f "$_c" ] || continue
    _n=$((_n+1))
    cmp -s "$_BASE" "$_c" && continue
    # Direction matters: a copy missing the refusal is a live weakness, a copy that
    # merely differs may be ahead of the baseline.
    if ! grep -q 'is_symlink' "$_c"; then
      _adv drift.prod-policy-copy "missing-refusal:${_c#$HOME/}"; printf '  ADVISORY [drift.prod-policy-copy] MISSING the PI-903 symlink refusal: %s\n' "${_c#$HOME/}"
    else
      _adv drift.prod-policy-copy "differs:${_c#$HOME/}"; printf '  ADVISORY [drift.prod-policy-copy] differs from the %s (has the refusal): %s\n' "$_BKIND" "${_c#$HOME/}"
    fi
  done
  printf '  %s deployed copy/copies checked against the %s.\n' "$_n" "$_BKIND"
else
  printf '  no authoritative prod_guard.py on this machine — nothing to compare.\n'
fi
}

# ── X9 · every registered check has a plist in a commit, and it matches ─────
# FIFTH SURFACE OF ONE CLASS, and X2/X4/X5's own headers name the first four:
# the artifact under governance is not the artifact doing the work. Here the
# artifact is the SCHEDULE. CHECKS.md is the registry, `launchd/` is the tracked
# definition, and ~/Library/LaunchAgents is what launchd actually loaded —
# nothing related the three, so both failure directions ran unnoticed:
#
#   MEASURED 2026-09-06. A client monitor's job had been firing hourly since
#   2026-09-04 with a registry row, a tracked monitor script in a workload repo, and NO
#   PLIST IN ANY COMMIT — the same defect harbor#436 closed for save-log-token.sh,
#   one layer up. And `com.harbor.pulse.plist` installed was 14 comment-lines
#   BEHIND the repo copy, so the tree documented a delivery observation the box
#   had never been given.
#
# WHY THAT MATTERS RATHER THAN BEING TIDINESS. CHECKS.md's own 2026-09-04
# incident is the argument: launchd keeps the job it LOADED, so a plist that is
# missing, truncated or stale looks perfectly healthy in `launchctl list` and the
# loss first shows at reboot, as a check that silently stopped existing. Recovery
# there was a single `cp` only because the repo carried the canonical plists. A
# check whose plist is in no commit has no such recovery.
#
# ADVISORY, and for X2's reason exactly: the second half reads the operator's
# home directory, so a hard failure would gate every commit on the state of one
# machine. The FIRST half — a registry row with no tracked plist — is a fact
# about this repo alone and would be fatal-able; it is kept advisory so the rule
# has one severity and reads as one thing.
#
# THE REGISTRY IS THE LIST, never a glob of launchd/. Globbing would make an
# untracked check invisible to the very rule that exists to find it, which is
# the shape of a detector that cannot see its own subject.
# THE REGISTER AND THE PLISTS ARE EACH TWO SOURCES (harbor#1149): core CHECKS.md and launchd/, plus, where a private layer
# exists, its checks.md rows and its jobs/ plists. _registry prints the composed register (rc 2: the private rows refuse);
# _plist_of <id> prints the tracked plist for a check id, from launchd/ first. No layer: core alone, as CI sees it.
_registry() {
  if [ -f "$ROOT/bin/check-registry-generate.sh" ]; then sh "$ROOT/bin/check-registry-generate.sh" --core "$ROOT/CHECKS.md"
  else cat "$ROOT/CHECKS.md" 2>/dev/null; fi
}
_plist_of() { # <id> -> the plist path, or nothing
  for _po_d in "$ROOT/launchd" "${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}/jobs"; do
    [ -f "$_po_d/com.harbor.$1.plist" ] && { printf '%s' "$_po_d/com.harbor.$1.plist"; return 0; }
  done
  return 0
}
rule_X9() {
rule "drift.launchd-plist every launchd-scheduled CHECKS.md check has a tracked plist, and the installed copy matches (advisory)"
# THE SCHEDULE COLUMN IS PART OF THE REGISTER, AND THIS RULE USED TO IGNORE IT.
# X9 demanded `launchd/com.harbor.<id>.plist` for EVERY row, while the register's
# own third column says of eight of the fifteen that they are not launchd jobs at
# all: `reference-check` runs inline at SessionStart, four run on every `just
# lint` in the measurement repo, and three say "not scheduled" in as many words. So the rule
# emitted eight permanent advisories that were wrong by the register's own text —
# a majority — and on 2026-09-15 they buried the one that was right, which was
# a client monitor's installed copy having been left on its old path by a rename.
# That is CONSTITUTION 2.11 arriving from the other side: a rule wrong more often
# than right is one the reader learns to skip, and then it protects nothing.
#
# THE DISCRIMINATOR IS A NEGATIVE LIST, DELIBERATELY. The tempting shape is a
# positive one — match `hourly`, `every <n>s`, `HH:MM daily` — and it fails in
# the SILENT direction: a real launchd job whose schedule is phrased in a way the
# pattern does not know would simply stop being checked, which is the one outcome
# this rule exists to prevent. A negative list fails the other way: an
# unrecognised phrasing still demands a plist, so a new kind of non-launchd check
# produces a WRONG ADVISORY rather than a silent gap. Noise is recoverable by
# reading; silence is not.
#
# BUT THE LOUD LINE MUST SAY WHAT IT KNOWS (harbor#592). An unrecognised phrasing used to be
# reported as "registered but in NO COMMIT", a claim about a plist the row may never have owed.
# Both lists now run: a row that is neither a known non-launchd kind nor a launchd time (`hourly`,
# `every <n>s`, `HH:MM`, `daily`, `weekly`, `launchd`), and has no tracked plist, is UNREADABLE.
# Still loud, never silent, and no longer wrong about why.
#
# TWO MORE KINDS, AND ONE IS NOT A SKIP (finding #890, 2026-10-02). Eleven rows were reported as
# owing a plist they never could: five SQL singular tests and one CI gate run under someone else's
# scheduler (skipped, like a SessionStart check), and five run INSIDE another job's run, e.g.
# "inside `fleet-snapshot`'s run". A rider is not let off: its HOST must have a tracked plist, or the
# rider has no schedule either, so the negative list still errs loud, never silent.
#
# A MALFORMED ROW IS NOT A SKIP EITHER. If the table shape moves, the schedule
# cell cannot be trusted, so the row keeps the old strict behaviour and the shape
# is reported — never quietly dropped from the count.
_x9_la="$HOME/Library/LaunchAgents"
_x9_reg="$(_registry 2>/dev/null)" || { _adv drift.launchd-plist registry-refused; printf '  ADVISORY [drift.launchd-plist] the private layer'"'"'s checks.md does not compose into the register (sh bin/check-registry-generate.sh names the line), so core CHECKS.md alone was read\n'; _x9_reg="$(cat "$ROOT/CHECKS.md" 2>/dev/null)"; }
_x9_rows="$(printf '%s\n' "$_x9_reg" | awk -F'|' '
  /^\| `[a-z0-9.-]+` \|/ {
    id = $2; gsub(/[` ]/, "", id)
    if (NF != 7) { print id " shape"; next }
    sched = $4
    # The schedule only, never its falsifier: a launchd row whose falsifier mentions a SQL
    # "singular test" or a "CI gate" must still owe its plist (review #929).
    sub(/falsifier.*/, "", sched)
    if (sched ~ /not scheduled/ || sched ~ /every commit and push/ || sched ~ /SessionStart/ \
        || sched ~ /singular test/ || sched ~ /CI gate/)
      print id " other"
    else if (match(sched, /inside `[a-z0-9-]+`\047s run/)) {
      h = substr(sched, RSTART + 8); sub(/`.*/, "", h); print id " rides:" h
    } else if (sched ~ /hourly|every [0-9]+ ?s([^a-z]|$)|[0-9][0-9]:[0-9][0-9]|daily|weekly|launchd/)
      print id " launchd"
    else
      print id " unread"
  }' 2>/dev/null)"
if [ -z "$_x9_rows" ]; then
  _adv drift.launchd-plist no-rows; printf '  ADVISORY [drift.launchd-plist] CHECKS.md has no registry rows this rule can read — the register or its table shape moved\n'
else
  _x9_n=0; _x9_other=0; _x9_untracked=0; _x9_drift=0; _x9_unread=0
  _x9_tmp="${TMPDIR:-/tmp}/harbor-x9.$$"
  printf '%s\n' "$_x9_rows" | { while read -r _x9_id _x9_kind; do
    [ -n "$_x9_id" ] || continue
    _x9_n=$(( _x9_n + 1 ))
    if [ "$_x9_kind" = shape ]; then
      _adv drift.launchd-plist "shape:$_x9_id"; printf '  ADVISORY [drift.launchd-plist] %s: the row has the wrong column count, so its schedule cannot be read — checked strictly\n' "$_x9_id"
    elif [ "${_x9_kind#rides:}" != "$_x9_kind" ]; then
      _x9_host="${_x9_kind#rides:}"
      if [ -n "$(_plist_of "$_x9_host")" ]; then _x9_other=$(( _x9_other + 1 )); continue; fi
      _adv drift.launchd-plist "rides-unscheduled:$_x9_id"; printf '  ADVISORY [drift.launchd-plist] %s runs inside %s, which has no tracked plist — so neither has a schedule in any commit\n' "$_x9_id" "$_x9_host"
      _x9_untracked=$(( _x9_untracked + 1 )); continue
    elif [ "$_x9_kind" = other ]; then
      # Registered, governed, and not a launchd job. Counted so the register's
      # own arithmetic stays visible: silence about these would make the total
      # disagree with CHECKS.md for no stated reason.
      _x9_other=$(( _x9_other + 1 )); continue
    elif [ "$_x9_kind" = unread ] && [ -z "$(_plist_of "$_x9_id")" ]; then
      # a tracked plist is evidence enough that it is a launchd job; without one, say what is unknown
      _adv drift.launchd-plist "unreadable:$_x9_id"; printf '  ADVISORY [drift.launchd-plist] %s: its schedule names no launchd time and no non-launchd kind, so whether it owes a plist cannot be read — say "not scheduled", the host it runs inside, or its time\n' "$_x9_id"
      _x9_unread=$(( _x9_unread + 1 )); continue
    fi
    _x9_repo="$(_plist_of "$_x9_id")"
    if [ -z "$_x9_repo" ]; then
      _adv drift.launchd-plist "uncommitted:com.harbor.$_x9_id.plist"; printf '  ADVISORY [drift.launchd-plist] registered but in NO COMMIT: %s — launchd keeps what it loaded, so this shows at reboot\n' "com.harbor.$_x9_id.plist"
      _x9_untracked=$(( _x9_untracked + 1 )); continue
    fi
    # Absent installed copy is NOT drift: a check may legitimately be registered
    # and not loaded on this particular box. `launchctl list` answers whether the
    # SCHEDULE is healthy; this rule answers whether the DEFINITION is governed.
    [ -f "$_x9_la/com.harbor.$_x9_id.plist" ] || continue
    # The tracked plist is a TEMPLATE (launchd/ names no home, harbor#630); what was installed is what it renders to on this
    # box, so that is what is compared. One that does not render is compared as it stands, which reads as drift.
    if sh "$ROOT/bin/launchd-render.sh" "$_x9_repo" > "$_x9_tmp" 2>/dev/null; then
      cmp -s "$_x9_tmp" "$_x9_la/com.harbor.$_x9_id.plist" && continue
    else
      cmp -s "$_x9_repo" "$_x9_la/com.harbor.$_x9_id.plist" && continue
    fi
    _adv drift.launchd-plist "differs:com.harbor.$_x9_id.plist"; printf '  ADVISORY [drift.launchd-plist] installed copy differs from what the repo renders to: %s — render it again (sh bin/launchd-render.sh), or commit what the box is running\n' "com.harbor.$_x9_id.plist"
    _x9_drift=$(( _x9_drift + 1 ))
  done
  rm -f "$_x9_tmp"
  printf '  %s registered check(s): %s not launchd-scheduled, %s untracked, %s drifted from the installed copy, %s unreadable.\n' \
    "$_x9_n" "$_x9_other" "$_x9_untracked" "$_x9_drift" "$_x9_unread"; }
fi
}
# ── X3 · the always-on context surface stays under its ceiling ─────────────
# bin/context-budget.sh existed and NOTHING RAN IT — which is exactly the shape
# CONSTITUTION.md calls a wish. Advisory rather than fatal, like X2: the ceiling
# is a round arguable number, and a hard failure on an arguable threshold is how
# a check gets commented out. Advisory means it is SEEN every build.
# ── T9 · the skill catalog matches the skills on disk ──────────────────────────
# An index of this many skills maintained by hand drifts the moment one is added,
# renamed or hidden — and an index that lies is WORSE than no index, because
# the whole reason it exists is to be trusted by a session that cannot see the
# skills it lists. Same reasoning as T1's "STATUS.md is generated, not
# ── T10 · every authored skill is answered for in skills/README.md ──────────
# skills/README.md carries an Inhabitants table whose column is "Why it exists",
# and it is the only place a reader learns whether a skill earns its always-on
# cost. Nothing checked it, and 4 of 10 skills had no row — `access-ledger`,
# a ticketing skill, `skill-catalog`, `topology` — three of them ambient, so the box was
# paying for them every session with no recorded reason.
#
# HARD, not advisory: unlike T9 the subject is entirely inside the repo, the
# resolution is unambiguous (write the row), and the row is the cheapest artefact
# in the whole tree. An advisory here would be a wish about documentation.
#
# It matches on the skill NAME in backticks, not on the link, because the table
# is markdown and a reader may reasonably reshape it. What must not be possible
# is a skill nobody wrote a sentence about.
rule_T10() {
rule "skill.readme-row every skills/ entry has a row in skills/README.md (why it exists)"
if [ -d "$ROOT/skills" ] && [ -f "$ROOT/skills/README.md" ]; then
  for d in "$ROOT"/skills/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    grep -qF "\`$n\`" "$ROOT/skills/README.md" \
      || bad skill.readme-row "skills/$n has no row in skills/README.md — no recorded reason to exist"
  done
fi
}

# hand-edited"; this is that rule applied to the one other derived document.
#
# Advisory, and deliberately so: the subject is ~/.claude/skills, outside the
# repo, so a hard failure would fire on a box where the skills are installed
# differently or not at all. A false positive gets a check deleted rather than
# fixed (CONSTITUTION.md §2.11).
# ── T11 · a skill the router cannot match is a skill nobody reaches ─────────
# `inject.d/box/repo-skills.sh` makes a hidden skill reachable by emitting its
# TRIGGER PHRASES, not its prose: it extracts `USE WHEN...` from the description
# and falls back to the prose half only when a skill has none. Its own header
# records what happens when that half is missing — until 2026-08-28 the emitter
# STRIPPED `USE WHEN` and shipped only abstract description, and the measurement
# was 0 occurrences of the phrase across 11,412 B of injection with 25 of 27
# vendored skills never opened by any tool call in 600 sessions. `red-team`
# arrived as "adversarial analysis deploying parallel expert agents" with
# "critique, stress test, devil's advocate, break this, poke holes" cut off.
#
# So the triggers are load-bearing for routing, and nothing asserted they exist.
# All 50 installed skills carried them on 2026-09-16, which is the argument FOR
# adding this now rather than against it: the rule starts green, costs nothing
# today, and catches the next skill written without them — the one that would
# otherwise be installed, invisible and unreachable, with no symptom to notice.
#
# HARD, not advisory, for T10's reason: the subject is entirely inside the repo,
# and the remedy is unambiguous — write the trigger phrases into the
# description. It reads the FRONTMATTER only. Scanning the body would let a
# skill satisfy the rule by discussing `USE WHEN` in prose, which is the
# self-satisfying-comment defect this estate has already measured once.
rule_T11() {
rule "skill.use-when every tracked skill's description carries USE WHEN trigger phrases"
for _t11d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
  [ -d "$_t11d" ] || continue
  _t11f="$_t11d/SKILL.md"
  [ -f "$_t11f" ] || continue
  _t11n="$(basename "$_t11d")"
  _t11desc="$(awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
                   NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
                   NR>1' "$_t11f" \
             | awk '/^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); print; exit }')"
  [ -n "$_t11desc" ] || { bad skill.use-when "skills/$_t11n has no description: the router has nothing to match on"; continue; }
  case "$_t11desc" in
    *"USE WHEN"*) : ;;
    *) bad skill.use-when "skills/$_t11n description carries no USE WHEN triggers — repo-skills.sh can only emit its prose, which is what left 25 of 27 skills unopened in 600 sessions" ;;
  esac
done
}

rule_T9() {
rule "skill.book-current the tracked skill catalog is current against the skills this checkout tracks (advisory)"
# The tracked book reads nothing outside the checkout (harbor#1149), so this needs no config dir and gives one verdict on every machine.
if [ -f "$ROOT/bin/skill-catalog.sh" ]; then
  # Distinguish "stale" (exit 1, the diff branch) from "the generator broke"
  # (anything else). Collapsing both into STALE printed a remedy — `run:
  # skill-catalog.sh` — that runs the generator in WRITE mode, so a crashing
  # generator got its own broken output committed on the strength of this
  # advice. The reason went to /dev/null with stderr. The generator logs its FAIL line to stdout and its diff to
  # stderr, so both are kept: a router row it cannot read exits 3 (harbor#1149) and the line naming it is the reason.
  _t9_err="${TMPDIR:-/tmp}/t9.$$"
  sh "$ROOT/bin/skill-catalog.sh" --check >"$_t9_err" 2>&1; _t9_rc=$?
  case "$_t9_rc" in
    0) ;;
    1) _adv skill.book-current skills/skill-catalog/SKILL.md; printf '  ADVISORY [skill.book-current] skills/skill-catalog/SKILL.md is STALE — run: sh bin/skill-catalog.sh\n' ;;
    *) _adv skill.book-current generator-failed; printf '  ADVISORY [skill.book-current] the generator FAILED (rc=%s) — do NOT run it to "fix" this:\n' "$_t9_rc"
       sed 's/^/      /' "$_t9_err" | head -5 ;;
  esac
  rm -f "$_t9_err"
fi
}

# ── T12 · a magnitude quoted from a tool carries the date it was measured ───
# §2.12 AS A MECHANISM. "Your own team's documents are claims too" names the
# direction of the drift: nobody edits a note to say the thing got worse, so a
# stale doc reads flattering. A number copied out of a tool's output is the purest
# case — it reads as a claim about NOW and was a claim about THEN, and nothing in
# the sentence says which.
#
# Measured 2026-09-16 over CONTRACTS/ + DOCTRINE/ (26 files, 4,294 lines): 101
# magnitude claims in prose, 68 already dated, SIX undated and sitting beside one
# of this repo's own tools. Four of those six are checkable by running the tool
# they name, and THREE WERE WRONG: `lint-conventions` "73 rules" against 76,
# `doctor` "18 of 18" against an output shape that no longer exists, and "1 of 9
# installed skill(s) have drifted" against 1 of 49. The worst was the newest —
# two of them were written that same day and were already wrong on arrival. A copy
# is not stale because it is old; it is stale because it is a copy.
#
# WHY NOT THE OBVIOUS RULE. "Every magnitude in these directories carries a date"
# fires on 33 of 101, and about a quarter of those are not measurements at all:
# spec constants (inject.md's "first 4 KB" truncation limit), thresholds
# (modularity.md's "300 lines is the advisory line"), hypotheticals
# (prove-targets.md's "scores 100 %"), literal labels (reports.md's diagram
# captioned "1 of 3") and worked examples (cu.md's "page 5 of 8"). A quarter false
# positives is the shape that gets muted (§2.11), and X9 is the receipt for what a
# permanent advisory buys. So the general rule is the goal, not the mechanism: this
# ships as the slice where a number is unambiguously a snapshot of tool output.
# Six hits, zero false positives, all six fixed in the commit that added the rule —
# a ratchet at ZERO, which is enforceable, not one at "some, with exemptions".
#
# THE TOOL VOCABULARY IS DERIVED FROM bin/, NEVER LISTED, and that is what makes it
# a ratchet instead of a hand-kept set that drifts smaller than the truth. It also
# killed this rule's only false positive independently of the regex fix that also
# killed it: the first draft matched `check-seams.sh` in
# DOCTRINE/wiring-new-capability.md, and that script DOES NOT EXIST here, so a
# derived vocabulary cannot name it. (The dangling citation is a real defect and
# belongs to K1 / reference-check, not to this rule.)
rule_T12() {
rule "doc.magnitude-dated a magnitude quoted beside one of this repo's tools names the date it was measured (harbor#520)"
_T12_CMDS="$(find "$ROOT/bin" -maxdepth 1 -name '*.sh' 2>/dev/null \
  | sed 's|.*/||; s|[.]sh$||' | sort -u | tr '\n' '|' | sed 's/|$//')"
if [ -n "$_T12_CMDS" ]; then
  # Single quotes around the backticks so no escaping is needed, and [.] rather
  # than \. because awk's -v processes escape sequences and \. is not one of them.
  _T12_CRE='`('"$_T12_CMDS"')([.]sh)?( --?[a-z-]+)*`'
  _T12_MRE='(^|[^0-9A-Za-z.:#-])([0-9]+ of [0-9]+|[0-9]+([.][0-9]+)?[ ]?%|[0-9][0-9]?[0-9]?(,[0-9][0-9][0-9])+|[0-9]+ (B|KB|MB|GB)|[0-9]+ (rules?|files?|lines?|skills?|checks?|violations?|copies|repos?|scripts?|assertions?))'
  _T12="$(
    find "$ROOT/CONTRACTS" "$ROOT/DOCTRINE" -maxdepth 1 -name '*.md' 2>/dev/null | sort |
    while IFS= read -r _t12f; do
      # A DATE ANYWHERE IN THE PARAGRAPH SATISFIES IT, and for a markdown table
      # that means one stamp in the header covers every row — which is the right
      # granularity, because a table of measurements was taken in one sitting.
      awk -v cmdre="$_T12_CRE" -v magre="$_T12_MRE" -v file="${_t12f#"$ROOT"/}" '
        # A LIST ITEM IS SCOPED TO ITSELF, NOT TO THE PARAGRAPH. One date in a
        # table header covering every row is right -- a table of measurements was
        # taken in one sitting -- but a bullet list is independent claims added at
        # different times, and there a dated bullet SHELTERS an undated one. Probed
        # 2026-09-16: two bullets in one block, the first dated, the second an
        # undated `doctor` -- 4 of 4, went unreported. Tightening costs nothing
        # today (measured: zero new hits across CONTRACTS/ + DOCTRINE/), which is
        # why it ships now rather than as a known hole.
        function dated(lo, hi,   i, s) {
          s = ""
          for (i = lo; i <= hi; i++) s = s "\n" txt[i]
          return (s ~ /20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)
        }
        function itemlo(i,   j) {
          for (j = i; j >= 1; j--) if (txt[j] ~ /^[ \t]*([-*+]|[0-9]+[.])[ \t]/) return j
          return 0
        }
        function itemhi(i,   j) {
          for (j = i + 1; j <= n; j++) if (txt[j] ~ /^[ \t]*([-*+]|[0-9]+[.])[ \t]/) return j - 1
          return n
        }
        function flush(   i, lo) {
          for (i = 1; i <= n; i++) {
            if (txt[i] !~ cmdre || txt[i] !~ magre) continue
            lo = itemlo(i)
            # Inside a list item, only the lines of THAT item count as its date.
            # (No apostrophes in here: this awk program lives inside a single-quoted
            # shell string, so one contraction closes it and the parse error surfaces
            # 1,100 lines later as a bogus unexpected-EOF. It did, while writing this.)
            if (lo > 0) { if (!dated(lo, itemhi(i))) printf "%s:%d\n", file, lno[i] }
            else if (!dated(1, n))                   printf "%s:%d\n", file, lno[i]
          }
          n = 0; para = ""
        }
        BEGIN { fence = 0; n = 0; para = "" }
        {
          if ($0 ~ /^[ \t]*```/) { fence = 1 - fence; next }
          if (fence) next
          if ($0 ~ /^[ \t]*$/) { flush(); next }
          para = para "\n" $0
          n++; lno[n] = FNR; txt[n] = $0
        }
        END { flush() }
      ' "$_t12f"
    done
  )"
  # HEREDOC, NOT A PIPE — the F10/F12 trap: a `bad` inside a piped `while` runs in
  # a SUBSHELL, so FAIL dies with it and the linter exits 0 while printing.
  if [ -n "$_T12" ]; then
    while IFS= read -r _t12l; do
      [ -n "$_t12l" ] || continue
      bad doc.magnitude-dated "a magnitude quoted beside one of this repo's own tools with no date in its paragraph — it reads as current and was current then: $_t12l"
    done <<T12EOF
$_T12
T12EOF
  fi
else
  bad doc.magnitude-dated "cannot derive the tool vocabulary from bin/ — T12 has nothing to match against"
fi
}

rule_X3() {
rule "context.budget-ceiling the always-on context surface stays under its ceiling (advisory)"
# ── THE BASELINE VERDICT COMES FIRST (harbor#183) ───────────────────────────
# The percentage below is measured against `HARBOR_CONTEXT_CEILING`, and #183
# established that the number has no referent: capacity, cost and dilution were
# each measured and each came back dead. What the instrument was built for is
# REGROWTH, so the primary verdict is now a recorded prior measurement — T1's
# mechanism applied to a surface. The deliberate surface (constitution + ambient
# skill descriptions + repo-scoped) is the half a baseline can bind; the memory
# index changes whenever a memory is written and is store-check.sh's to bound.
# The subject is the verdict's KIND, which the tool prints (harbor#585): an instrument change and
# regrowth are different findings, and a flip between grew and shrank re-opens an accepted one.
if [ -f "$ROOT/bin/context-budget.sh" ]; then
  _x3b="$(sh "$ROOT/bin/context-budget.sh" --check --kind 2>&1)" || {
    _x3k="$(printf '%s\n' "$_x3b" | sed -n 's/^kind=\([a-z-]*\)$/\1/p' | tail -1)"
    _x3m="$(printf '%s\n' "$_x3b" | grep -v '^kind=' | head -1)"
    _adv context.budget-ceiling "${_x3k:-verdict-unreadable}:CONTEXT-BASELINE.tsv"; printf '  ADVISORY [context.budget-ceiling] %s\n' "$_x3m"; }
fi
if [ -x "$ROOT/bin/context-budget.sh" ] || [ -f "$ROOT/bin/context-budget.sh" ]; then
  # Match the verdict LINE, not a position: the OVER branch prints a blank line
  # first, so `tail -3 | head -1` returned "" and the rule silently never fired
  # on the one case it exists for.
  _cb="$(sh "$ROOT/bin/context-budget.sh" 2>/dev/null | grep -E '^(OVER by|[0-9]+% of ceiling)' | head -1)"
  case "$_cb" in
    OVER*) _adv context.budget-ceiling context-ceiling; printf '  ADVISORY [context.budget-ceiling] %s\n' "$_cb"
           # THE OLD REMEDY WAS CIRCULAR: it named the tool that had just printed
           # this line, so the operator ran it and got the same total again. What
           # is actionable is WHICH surface to trim, and on this box that is the
           # cwd-keyed memory index — 22,467 B of a 44,311 B total on 2026-08-20,
           # larger than CLAUDE.md and bounded by nothing until CX1.
           _adv context.budget-ceiling -; printf '  ADVISORY [context.budget-ceiling] the breakdown, and what to trim: sh bin/store-check.sh\n' ;;
    *%*)   printf '  %s\n' "$_cb" ;;
  esac
fi
}

# ── X10 · the authored-plugin tier stays retired ────────────────────────────
# WHY THIS RULE EXISTS, and it is not a style preference. Harbor authored one
# plugin (`atlas`, 2026-09-02) on a premise its own README stated: "a plugin is
# loaded when its repo is entered; ~/.claude/skills is loaded always." Measured
# 2026-09-06, both halves are false. `claude plugin list` reported atlas at
# **Scope: user** — active in every session on the machine — and `claude plugin
# details atlas` put it at ~398 tokens ALWAYS-ON, in sessions not building an
# atlas. Meanwhile a `~/.claude/skills` skill carrying `disable-model-invocation:
# true` costs ZERO: verified with three arms and a control, the plugin skill in
# the session listing as YES / NO / NO.
#
# The cost premise was backwards, and the governance cost was real: SEVEN of
# eight gates greped `plugins/` zero times, so atlas was invisible to
# context-budget.sh (which therefore reported a headroom number that could not
# see the thing being justified by it), absent from the generated skill-catalog
# (0 hits), and its build/check.mjs was registered in no suite while its own
# manifest advertised "Ships its own browser acceptance suite" and
# CONTRACTS/suite-paths.txt recorded "atlas ships no suite and has no prove
# target". Two documents, one tree, opposite claims.
#
# AND THE TIER BOUGHT NOTHING. Verified 2026-09-06: a `.claude-plugin/plugin.json`
# placed inside `~/.claude/skills/<name>/` loads as a full plugin — `plugin list`
# reported `expdir@skills-dir · Status: loaded`, with the same component inventory
# (skills, agents, hooks, MCP, LSP) and the same cost accounting. Every plugin
# power is reachable from the tier Harbor already governs and already installs
# into. The marketplace buys exactly one thing `skills/` cannot: installing on a
# box that does not have this repo. Nothing here is doing that.
#
# SO THE RULE IS NARROW, AND SO IS ITS EXIT. This fails on a Harbor-AUTHORED
# plugin tier only. The security floor watching the BOX's third-party plugin
# surface (guard-lib.sh, sec0-harden.sh, guard-integrity.sh, and the
# `plugins/marketplaces/...` paths elsewhere in this file) is a defence against
# somebody else's plugin and is untouched — weakening it to satisfy this rule
# would be the exact move the constitution forbids while degraded.
#
# IF DISTRIBUTION EVER BECOMES REAL, this rule is what you delete, deliberately,
# with the reasoning in DOCTRINE/no-authored-plugins.md updated to say why.
rule_X10() {
rule "policy.no-authored-plugins no Harbor-authored plugin tier (DOCTRINE/no-authored-plugins.md)"
if [ -d "$ROOT/plugins" ]; then
  bad policy.no-authored-plugins "plugins/ is back — capability belongs in skills/ + bin/; see DOCTRINE/no-authored-plugins.md"
fi
if [ -f "$ROOT/.claude-plugin/marketplace.json" ]; then
  bad policy.no-authored-plugins "marketplace.json is back — it buys only off-repo install; see DOCTRINE/no-authored-plugins.md"
fi
for _pm in "$ROOT"/skills/*/.claude-plugin/plugin.json "$ROOT"/vendor/skills/*/.claude-plugin/plugin.json; do
  # A manifest INSIDE a skill dir is the sanctioned escape hatch (it loads as
  # <name>@skills-dir and stays under every gate), so this is a note, not a
  # failure — but an unannounced one is a tier growing back by accident.
  [ -f "$_pm" ] && printf '  NOTE  [policy.no-authored-plugins] skills-dir plugin manifest: %s (sanctioned — stays under skills/ governance)\n' "${_pm#$ROOT/}"
done
unset _pm
}

# ── X6 · a governed repo the fleet scan cannot reach ────────────────────────
# THE GAP THIS CLOSES. The layout convention — "this Mac keeps repos flat under
# $HOME" — lived in exactly two pieces of prose: a comment inside the GITIGNORED
# fleet.yaml, and one line of harbor-build-tickets.md. Nothing checked it. So a
# governed repo cloned into ~/Documents sat outside the fleet while every command
# reported success, because projects-orchestrator scans `roots:` one level deep
# and drops `exclude:` trees — and a project it never enumerates cannot be
# reported as missing. Found 2026-07-31 with a workload repo and a since-retired project both under
# ~/Documents/projects, the fleet reporting 2 projects and nothing reporting a
# problem. This is the fleet's blind spot, not its error.
#
# Advisory, for X2/X5's reason: the subject is the operator's home directory, so
# a hard failure would depend on the machine the build runs on. With no fleet
# file the rule says nothing — correct for a check whose subject is absent, and
# the reason it is not in a *-test.sh, where it would make a hermetic suite
# depend on $HOME (X5's header makes the same argument at length).
#
# THE REJECTED SHAPE, because it looked obviously right and was wrong. The first
# cut keyed on DEPTH alone — the scan walks one level, so treat any `.agents`
# deeper than that as unreachable. Measured against this box it reported six
# repos, of which ONE was drift: the others were a CI runner's `_work` checkout,
# uv's installed package data, a plugin marketplace mirror, and two codex temp
# bundles. Five false positives out of six, on a rule whose whole purpose is to
# be believed — and per the constitution a guard that fires on ordinary work gets
# switched off, after which it protects nothing. Depth cannot tell a project from
# a copy of one. The operator's own `exclude:` list can: it is a declaration that
# these trees hold no projects, so a governed repo inside one is drift BY THE
# OPERATOR'S OWN DEFINITION. That predicate reports exactly the one real hit.
#
# BOUNDED WALK: excluded trees are searched to depth 4 and hidden ancestors are
# pruned, so the clean message names the bound rather than claiming the tree is
# empty. A silent cap reads as "covered everything" when it did not.
rule_X6() {
rule "scope.repo-discoverable every governed repo is reachable by fleet.yaml's own discovery (advisory)"
# ASK THE QUESTION THE FLEET ASKS. The previous predicate built a roots x exclude
# CROSS PRODUCT and walked each branch to depth 4, which is not how discovery
# works: registry.py's _scan_root lists entries ONE LEVEL under each root and
# drops them by directory NAME (fnmatch against exclude:). Nothing walks deeper,
# and no path is ever assembled from a root and an exclude entry.
#
# The two disagreed in both directions, and the rule's own remedy line was one of
# the broken fixes: adding ~/Documents/projects to roots: makes the fleet reach
# that repo — one level down, name not excluded — while the old predicate kept firing,
# because ~/Documents is still a root x exclude branch containing a .agents. An
# operator following the advice would have fixed the problem and been told they
# had not (measured 2026-08-01).
#
# It also never parsed `projects:`, so a repo registered there explicitly — the
# supported way to include something outside every root — was reported as
# unreachable while the fleet was reading it fine.
_FLEET="${HARBOR_FLEET_FILE:-${PORT_ROOT:-$HOME/port}/projects-orchestrator/fleet.yaml}"
if [ -f "$_FLEET" ]; then
  # One awk pass, TAB-tagged by key, so the shell can tell the three lists apart
  # without word-splitting a path. awk and not a YAML library: this layer is
  # POSIX sh with no Bun and no Python.
  _x6_cfg="$(awk '
    /^roots:/    { m="R"; next }
    /^exclude:/  { m="E"; next }
    /^projects:/ { m="P"; next }
    m!="" && /^[[:space:]]*-[[:space:]]/ {
      gsub(/^[[:space:]]*-[[:space:]]*|["\047]/,""); print m "\t" $0; next }
    /^[^[:space:]#]/ { m="" }
  ' "$_FLEET")"
  _x6_roots="$(printf '%s\n' "$_x6_cfg" | sed -n 's/^R\t//p')"
  _x6_excl="$(printf '%s\n' "$_x6_cfg"  | sed -n 's/^E\t//p')"
  _x6_projs="$(printf '%s\n' "$_x6_cfg" | sed -n 's/^P\t//p')"

  # Reachable iff the fleet's own rule says so: the repo sits exactly one level
  # under a root and its NAME survives the exclude patterns, or it is listed in
  # projects:. Exclude entries are fnmatch patterns upstream, so they are matched
  # with `case`, not string equality.
  _x6_reachable() { # <repo-dir>
    _rp="$1"; _rparent="$(dirname "$_rp")"; _rname="$(basename "$_rp")"
    printf '%s\n' "$_x6_projs" | grep -Fxq "$_rp" && return 0
    printf '%s\n' "$_x6_roots" | grep -Fxq "$_rparent" || return 1
    # READ LOOP, NOT `for _e in $_x6_excl`. An exclude entry may contain a space
    # ("My Docs"), and word-splitting it silently turns one pattern into two that
    # match nothing — the exact regression lint-test pins.
    _x6_ok=0
    while IFS= read -r _e; do
      [ -n "$_e" ] || continue
      case "$_rname" in $_e) _x6_ok=1; break ;; esac
    done <<X6EXCL
$_x6_excl
X6EXCL
    [ "$_x6_ok" -eq 0 ]
  }

  _x6=0
  # Search every root SUBTREE for governed repos — including the parts discovery
  # cannot see, which is the whole point: a repo the fleet misses is exactly what
  # this rule is looking for. Bounded to depth 4 with hidden ancestors pruned, and
  # the clean message names the bound rather than claiming the tree is empty.
  # Same reason: a ROOT may contain a space, so this reads line by line and
  # accumulates rather than word-splitting the list.
  _x6_hits=""
  while IFS= read -r _r; do
    [ -n "$_r" ] || continue
    [ -d "$_r" ] || continue
    # ~/Library IS PRUNED FOR THE SAME REASON AS X5, and it is not covered by the
    # hidden-ancestor prune above because Library is not hidden. macOS TCC blocks
    # a process without Full Disk Access inside ~/Library/Group Containers instead
    # of returning EPERM, so this find hangs there indefinitely when a ROOT is
    # $HOME. Fixing X5 alone would only have moved the hang one rule down — both
    # walks were blocked simultaneously on 2026-08-25. No coverage is lost: a
    # governed repo is a git checkout and never lives under ~/Library.
    # Every guarded folder, not only ~/Library, since harbor#658: guarded_find.
    _x6_found="$(guarded_find "$_r" 4 \
      -type d -name .agents \
      -not -path "*/.*/*" -not -path "*/node_modules/*" -print 2>/dev/null)"
    [ -n "$_x6_found" ] && _x6_hits="${_x6_hits}${_x6_found}
"
  done <<X6ROOTS
$_x6_roots
X6ROOTS
  while IFS= read -r _m; do
    [ -n "$_m" ] || continue
    _repo="$(dirname "$_m")"
    _x6_reachable "$_repo" && continue
    _adv scope.repo-discoverable "$_repo"; printf '  ADVISORY [scope.repo-discoverable] governed repo the fleet cannot reach: %s\n' "$_repo" >&2
    _x6=$((_x6+1))
  done <<X6HITS
$_x6_hits
X6HITS
  if [ "$_x6" -eq 0 ]; then
    echo "  every governed repo under a fleet root is reachable (walked to depth 4, hidden pruned)."
  else
    _adv scope.repo-discoverable -; printf '  ADVISORY [scope.repo-discoverable] %d unreachable — add the PARENT dir to roots:, or list the repo under projects:, in %s\n' \
      "$_x6" "$_FLEET" >&2
  fi
fi
}

# ── K1 · the constitution may not cite a path that does not exist ──────────
# CONSTITUTION.md's own opening promise is "every mechanism named below exists in
# this repo and is cited by path". That promise is the whole reason the file is
# trustworthy: a constitution that references machinery it does not have is a
# constitution that LIES, and a reader who catches one dead citation has no way
# to tell which other rules are also fiction.
#
# It is also the specific failure the C1 curation existed to avoid — the upstream
# source it was curated from named 20+ files, hooks and daemons that do not exist
# here, and the upstream MIRROR is readable at ~/.harbor-upstream, so a relative
# pointer would not even fail loudly: it would resolve, into the engine the
# no-fork decision excluded.
rule_K1() {
rule "policy.constitution-paths every repo path cited by CONSTITUTION.md resolves"
CON="$ROOT/CONSTITUTION.md"
if [ -f "$CON" ]; then
  # Markdown links of the form (./path) or (./path#anchor) — the only citation
  # form the file uses, deliberately, so this rule can be exhaustive rather than
  # heuristic.
  #
  # GREEDY-SED, THE SAME DEFECT T3 CARRIED (2026-08-02). T3 is named "generalises
  # K1" and the two were born with one extractor; fixing it in T3 and leaving it
  # here would be the "finding not generalised" failure this repo has already
  # recorded once. `sed 's/.*](…)/\1/'` anchors on `.*`, which is greedy, so on a
  # line carrying two links only the LAST was ever checked. CONSTITUTION.md has
  # no two-link line today — measured, both extractors return the same 16 paths —
  # so this changes no verdict now and closes the hole before it opens.
  #
  # `./` ONLY, deliberately, and NOT widened to `../` the way T3 was: K1 resolves
  # against $ROOT rather than the citing file's directory, so accepting `../`
  # here would resolve a path that escapes the repo and report it as fine.
  #
  # A `for` over a captured list, NOT `… | while read`. A while-read pipeline
  # runs its body in a SUBSHELL, so `bad` increments a counter that dies with
  # it: the first cut of this rule printed the violation and still reported
  # "0 violations" — a rule that reports but cannot fail, which is the exact
  # class CONSTITUTION.md §2 forbids and which this repo has now hit three
  # times in three different shapes.
  # TWO CITATION FORMS, ONE RULE (2026-08-03). CONSTITUTION.md is the only repo
  # document that is also DEPLOYED — it is copied to ~/.claude/CLAUDE.md, where
  # `./DOCTRINE/…` resolves against a directory tree that is not there. Twelve
  # markdown links were dead on the surface that is actually read, while this
  # rule stayed green against the checkout: the file's own instruction to report
  # an unresolvable citation was unfollowable in the place it was being read.
  #
  # So the file now cites a repo-only document as a BACKTICKED `./path` — plain
  # text, which cannot dangle anywhere — and keeps markdown links exclusively for
  # paths that resolve on BOTH sides (the deployed bin/ scripts). Both forms are
  # extracted here, so the dialect change costs no coverage: the count this rule
  # checks went 16 → 16.
  #
  # `./` STAYS MANDATORY IN BOTH FORMS, which is what keeps this exhaustive
  # rather than heuristic. A bare `FLOOR.md` in backticks would be indistinguish-
  # able from prose, and widening to "any backticked token containing a dot"
  # would have to decide whether `permissions.deny`, `absent  CLAUDE.md` and
  # `harbor#44` are paths. They are not, and a rule that guesses is a rule that
  # gets muted (№2.11).
  #
  # awk, NOT grep, for the same reason reference-check.sh uses it: `grep` here is
  # a ugrep wrapper carrying -I --ignore-files, and a citation it silently skips
  # produces FEWER violations — a false green in the rule that guards the
  # constitution's own honesty.
  # THE EXTRACTOR MOVED OUT OF THIS RULE (harbor#462) and that is the whole fix,
  # not a tidy-up. This rule and reference-check.sh REF-5 ask the same question of
  # the same document against two different roots, and each carried its own copy
  # of the parsing. When commit 8b50867 migrated this file's citation dialect to
  # backticks, the copy HERE was taught the new form and the copy THERE was not —
  # so REF-5 went from 12 findings to 0 and read like a repair, while ten dead
  # pointers sat on the surface that every session actually loads, undetected
  # until 2026-09-06. Two copies of a parser is what made a dialect change able to
  # blind one reader and not the other, so now there is one: bin/cited-paths.awk.
  #
  # THE ROOTS STAY DIFFERENT ON PURPOSE, and that is not the duplication being
  # reintroduced. K1 asks "does this resolve IN THE REPO" and must resolve against
  # $ROOT — the rule's original comment argues this, and it is why `../` is
  # refused here: a path that escapes the checkout would be reported as fine.
  # REF-5 asks "does this resolve WHERE IT IS READ" and honours the document's
  # declared `**Path root:**`. Same citations, two questions, two answers, one
  # parser. In CI the checkout is not at ~/port/harbor, which is the second reason this
  # rule must not follow the declaration.
  #
  # A MISSING EXTRACTOR IS NOT A CLEAN SWEEP. Without this guard the awk below
  # emits nothing, the `for` body never runs, and the rule guarding the
  # constitution's honesty reports zero violations because it could not read.
  set -f
  # FROM THE LINTER'S OWN DIRECTORY, NOT $ROOT. The extractor is part of this
  # tool, not of the tree under inspection, and $ROOT is overridable with
  # HARBOR_ROOT — lint-test.sh points it at a fixture that has no bin/ until 50
  # lines after the K1 cases run, so resolving there made the rule report "the
  # extractor is missing" instead of checking citations. It is also the same
  # trust rule reference-check.sh and failure-capture.sh both carry: a tool taken
  # from the inspected tree lets that tree choose what the checker can see.
  _K1_AWK="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)/cited-paths.awk"
  if [ ! -f "$_K1_AWK" ]; then
    bad policy.constitution-paths "bin/cited-paths.awk is missing — NO citation in CONSTITUTION.md was checked, and this is not a pass"
  fi
  _k1_cited() {
    [ -f "$_K1_AWK" ] || return 0
    # ./ ONLY, and the prefix stripped for resolution against $ROOT. The shared
    # extractor emits markdown targets verbatim (URLs and anchors included) and
    # backticked paths only when ./-prefixed; this filter is what makes the set
    # K1's, and it lives at the caller so the extractor holds no policy.
    awk -f "$_K1_AWK" "$CON" | sed -n 's|^\./||p' | sed 's/#.*//' | sort -u
  }
  for p in $(_k1_cited); do
    [ -n "$p" ] || continue
    [ -e "$ROOT/$p" ] || bad policy.constitution-paths "CONSTITUTION.md cites a path that does not exist: $p"
  done
  set +f
fi
}

# ── MAG1 · a magnitude in the constitution carries the command that derives it ─
# CONSTITUTION.md says it itself — "a magnitude that decides something carries the
# command that derives it" — and was caught breaking it three times (harbor#583):
# "two thirds" (really 39 of 50), "52 files / NOT ONE earns a split" (one did, two
# weeks later), "10 of 10 repos blind" (fixed the day it was measured, still read
# live). K1 checks that a cited PATH exists; nothing checked that a cited NUMBER
# could be re-derived, which is the half No.2.5 calls insufficient, inverted.
#
# SCOPE, AND WHAT IT CANNOT SEE. A magnitude here is a DIGIT token in prose. Dates,
# `#N` refs, №N, No.x.y, "Rule N", list markers, "(1)" enumerators, `2×2` and
# anything in backticks or a code fence are not magnitudes (an incident's date is a
# record, not a claim about now). Spelled-out numbers ("ten of them") are NOT
# examined: a rule that guessed which words are quantities would fire on "one
# adapter" and get muted (No.2.11). A fence next to the number is taken as the
# derive command — this rule proves one is DECLARED, not that it is correct.
#
# PASS = the paragraph holding the number, or the next one, contains a fenced block.
# A list item and a blockquote line each start their own paragraph, so a number in
# one bullet cannot borrow the fence under another. The denominator is printed:
# "0 violations" over 0 examined would read as clean and mean nothing.
rule_MAG1() {
rule "policy.magnitude-derived a magnitude in CONSTITUTION.md carries the command that derives it (harbor#583)"
CON="$ROOT/CONSTITUTION.md"
if [ -f "$CON" ]; then
  _cm1="$(awk '
    function strip(t) {
      gsub(/`[^`]*`/, " ", t); gsub(/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/, " ", t)
      gsub(/[A-Za-z_#\/.№-][A-Za-z_#\/.№-]*[0-9][0-9.]*/, " ", t)
      gsub(/[Rr]ule [0-9]+/, " ", t); gsub(/[0-9]+×[0-9]+/, " ", t); gsub(/\([0-9]+\)/, " ", t); sub(/^ *[0-9]+\. /, " ", t)
      return t
    }
    /^```/ { if (!fence) { has[para] = 1 } fence = !fence; next }
    fence { next }
    /^[ \t]*$/ { para++; next }
    /^[ \t]*([-*] |[0-9]+\. |>)/ { if (!/^>/ || prevq == 0) para++ }
    { prevq = /^>/ ? 1 : 0 }
    { t = strip($0); if (match(t, /[0-9]+/)) { n++; at[n] = NR; tok[n] = substr(t, RSTART, RLENGTH); pp[n] = para } }
    END {
      for (i = 1; i <= n; i++) if (!(pp[i] in has) && !((pp[i] + 1) in has)) print "BAD " at[i] " " tok[i]
      print "EXAMINED " n+0
    }' "$CON")"
  for _l in $(printf '%s\n' "$_cm1" | sed -n 's/^BAD \([0-9]*\) .*/\1/p'); do
    _t="$(printf '%s\n' "$_cm1" | sed -n "s/^BAD $_l //p")"
    bad policy.magnitude-derived "CONSTITUTION.md:$_l states the magnitude '$_t' with no fenced derive command beside it — add the command, or remove the number and keep the sentence (harbor#583)"
  done
  say "  $(printf '%s\n' "$_cm1" | sed -n 's/^EXAMINED //p') digit magnitude(s) examined in CONSTITUTION.md; spelled-out numbers are not read."
else
  bad policy.magnitude-derived "CONSTITUTION.md is missing — NO magnitude was checked, and this is not a pass"
fi
}

# ── X1 · the dev sandbox must not drift from the repo ──────────────────────
# QA-PLAN R8: the sandbox was built once and never rebuilt, so "try it in the
# sandbox" validated a nine-passes-old floor — it was missing floor-normalize.awk
# entirely, which means the whole quoting model was absent from the thing being
# tested. Staleness has to be a VIOLATION, not a surprise.
# Skipped entirely when no sandbox exists (CI, a fresh clone) — this checks a
# local artefact, and its absence is not a defect.
rule_X1() {
rule "drift.sandbox-copy the dev sandbox's guards are byte-identical to bin/ (QA-PLAN R8)"
# TWO DEFECTS, BOTH FOUND BY C9 LISTING THIS RULE AS NEVER WATCHED FAIL (harbor#517).
#
# ONE · IT VERIFIED NOTHING, SILENTLY. The whole rule used to be one `if [ -d
# "$SBX/bin" ] && ls ...` with NO else branch, so on a box with no dev sandbox it
# examined zero items and reported green without saying so. Measured 2026-09-16:
# there is no sandbox on this box, so that is exactly what it had been doing. The
# advisory below is F12's idiom, and CHECKS.md already states the principle about a
# sibling repo's seam — "it also fails when it examines ZERO files, because a seam
# whose glob stopped matching must not report green". It is ADVISORY and not `bad`
# because a box without a sandbox is a legitimate state, and failing on it would be
# the false positive §2.11 forbids.
#
# TWO · THE PRESENCE LIST WAS A HAND-KEPT COPY, and the comment above it claimed
# "every guard the repo ships" while naming FOUR of the NINE in bin/ — so
# guard-cloud, guard-deliverables, guard-destroy, guard-integrity and guard-stop
# could all be absent from the sandbox and X1 would pass. A comment that is false
# about the code under it is the same defect this sweep keeps finding, and it is now
# true instead: the list is derived from bin/ and both loops read it.
#
# REQUIRING ALL THIRTEEN IS ZERO-FALSE-POSITIVE, MEASURED, NOT ASSUMED. The rebuild
# this rule names does `cp -R "$LIVE/bin"` — the whole directory — and on
# 2026-09-16 the live config dir carried all 9 guards and all 4 non-guard floor
# files. So a correctly built sandbox cannot fail the wider check (§2.11).
SBX="${HELM_SANDBOX_DIR:-$HOME/.claude-sandbox}"
# DERIVED, NOT LISTED, for the guards. The four non-guard floor components are
# named because no glob selects exactly those four — but they are named ONCE now,
# and the presence check and the byte check read the same list instead of two.
_X1_WANT="$(
  find "$ROOT/bin" -maxdepth 1 -name 'guard-*.sh' 2>/dev/null | sed 's|.*/||' | sort
  printf '%s\n' annotate-web.sh floor-normalize.awk floor-hook.sh pin-instructions.sh
)"
# KEYED ON THE DIRECTORY ALONE, NOT ON "does it contain any guard". The first cut
# of this fix wrote `[ -d "$SBX/bin" ] && ls "$SBX"/bin/guard-*.sh`, which conflates
# two different states: a box with NO sandbox (legitimate) and a sandbox that exists
# but carries NO guards (broken — it tests no floor at all, which is R8's failure
# exactly). Under that condition the second state printed "no dev sandbox at <path>"
# about a path that existed, and printed it as an ADVISORY. Caught by probing the
# edge case rather than by review. Now: absent is advisory, present-but-empty walks
# the list below and reports every missing file as the violation it is.
if [ -d "$SBX/bin" ]; then
  # HEREDOC, NOT A PIPE — the F10/F12 trap: a `bad` inside a piped `while` runs in a
  # SUBSHELL, so FAIL dies with it and the linter exits 0 while printing violations.
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    # Every file the repo ships into the floor must be PRESENT in the sandbox, or
    # the sandbox tests a smaller floor than the one being shipped — R8 exactly.
    if [ ! -f "$SBX/bin/$b" ]; then
      bad drift.sandbox-copy "sandbox is missing $b (rebuild: sh bin/sandbox-make.sh --fresh --with-floor)"
      continue
    fi
    [ -f "$ROOT/bin/$b" ] || continue
    cmp -s "$SBX/bin/$b" "$ROOT/bin/$b" || bad drift.sandbox-copy "sandbox copy is stale: $b (rebuild: sh bin/sandbox-make.sh --fresh --with-floor)"
  done <<X1EOF
$_X1_WANT
X1EOF
  # …and wired THROUGH the fail-closed wrapper, not called directly (B9).
  if command -v jq >/dev/null 2>&1 && [ -f "$SBX/settings.json" ]; then
    jq -e '[.hooks.PreToolUse[]?.hooks[]?.command] | map(select(test("guard-(bash|egress|selfedit)\\.sh")))
           | map(select(test("floor-hook\\.sh") | not)) | length == 0' "$SBX/settings.json" >/dev/null 2>&1 \
      || bad drift.sandbox-copy "sandbox wires a guard directly instead of through floor-hook.sh (rebuild the sandbox)"
  fi
else
  _adv drift.sandbox-copy no-dev-sandbox; printf '  ADVISORY [drift.sandbox-copy] no dev sandbox at %s — this rule verified NOTHING.\n' "$SBX" >&2
  printf '           build one: sh bin/sandbox-make.sh --fresh --with-floor\n' >&2
fi
}

# ── IJ1 · every rule pack is well-formed ───────────────────────────────────
# THE FAILURE THIS CATCHES IS SILENT BY CONSTRUCTION. hooks/injection-rule/injection-rule.sh refuses
# to fire a pack it cannot parse — an unknown predicate never matches, a pack with
# no `when:` never fires — and both refusals are correct: the most likely typo
# must not produce the loudest possible rule. But the consequence is that a
# broken pack and a pack that decided not to fire are indistinguishable from
# outside, which is the quietest possible way for governance to stop existing.
# The engine's job is to fail safe; this rule's job is to say so.
#
# TRACKED PACKS ONLY. The installed copies under the config dir are checked by
# their own drift rules; what belongs here is the source, at commit time.
#
# AND THE PRIVATE LAYER'S (harbor#1149). The packs that name a repo or a client, and the project
# registry, live in <private>/inject.d, in the shape of this tree's inject.d/. They are not tracked
# here, but they are installed and seeded from there, so a malformed one is the same silent
# never-fired defect and IJ1..IJ5 read that tree too. `_inj_load` asks the one resolver beside this
# script (a HARBOR_ROOT fixture holds no roots.sh): _INJ_DIR is the private inject.d, empty when
# there is none, and _INJ_REG the registry inside it, empty when there is none.
_inj_load() {
  [ -z "${_INJ_LOADED:-}" ] || return 0
  _INJ_LOADED=1
  _INJ_DIR="$(env -u HARBOR_ROOT sh "$(dirname -- "$0")/roots.sh" --inject 2>/dev/null || :)"
  _INJ_REG=''
  if [ -n "$_INJ_DIR" ] && [ -f "$_INJ_DIR/box/projects.tsv" ]; then _INJ_REG="$_INJ_DIR/box/projects.tsv"; fi
}
rule_IJ1() {
rule "context.pack-shape every tracked rule pack declares an event, a predicate and a body (CONTRACTS/inject.md)"
_inj_load
_ij_fm() { awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
                NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
                NR>1' "$1"; }
for f in "$ROOT"/inject.d/*/*.md "$ROOT"/.claude/inject.d/*.md "${_INJ_DIR:-/nonexistent}"/*/*.md; do
  [ -f "$f" ] || continue
  case "$f" in "$ROOT"/*) _rel="${f#$ROOT/}" ;; *) _rel="private:${f#"${_INJ_DIR%/inject.d}"/}" ;; esac
  _ev="$(_ij_fm "$f" | awk -F': *' '$1=="event"{print $2;exit}')"
  case "$_ev" in
    PreToolUse|PostToolUse|PostToolUseFailure|SessionStart|SubagentStart|PreCompact|SessionEnd) ;;
    '') bad context.pack-shape "pack declares no event: $_rel" ; continue ;;
    *)  bad context.pack-shape "pack declares an event the engine never sees ($_ev): $_rel" ; continue ;;
  esac
  # A PACK ON AN EVENT THAT CANNOT REACH THE MODEL IS A RULE THAT NEVER RAN.
  # `hookSpecificOutput.additionalContext` is accepted on some events and rejected
  # on others, and rejection discards the whole object — so the pack emits, the
  # engine exits 0, and the only trace is a validation error in the operator's
  # terminal. `20-precompact-carry.md` shipped this way and every compaction on
  # this box threw its note away. A rule whose audience is the operator says so
  # with `mode: notify`; anything else on such an event is a defect.
  # These events are RECOGNISED above rather than rejected, because the engine
  # really does serve them — it drops to a `systemMessage` the operator reads.
  # What it cannot do is reach the model, so the audience must be declared.
  case "$_ev" in
    PreCompact|SessionEnd)
      [ "$(_ij_fm "$f" | awk -F': *' '$1=="mode"{print $2;exit}')" = notify ] \
        || bad context.pack-shape "pack targets $_ev, which carries no model-visible channel, without mode: notify: $_rel" ;;
  esac
  # `description` says what the rule is for, one line, so an operator can retire it without reading its
  # body (harbor#957). A tracked pack is refused; a private one is only reported, because it is not in this
  # tree to fix.
  if [ -z "$(_ij_fm "$f" | awk -F': *' '$1=="description"{print $2;exit}')" ]; then
    case "$_rel" in
      private:*) _adv context.pack-shape "$_rel"; printf '  ADVISORY [context.pack-shape] pack has no description: %s\n' "$_rel" >&2 ;;
      *) bad context.pack-shape "pack has no description: $_rel" ;;
    esac
  fi
  _n="$(_ij_fm "$f" | grep -c '^when:' || true)"
  [ "${_n:-0}" -ge 1 ] || { bad context.pack-shape "pack has no when: predicate, so it can never fire: $_rel"; continue; }
  # THE PREDICATE VOCABULARY IS FIXED, and an unrecognised one is silent at run
  # time. Checking it here is the difference between a typo caught at commit and
  # a rule that has quietly never fired since the day it was written.
  _ij_fm "$f" | sed -n 's/^when:[[:space:]]*//p' | while IFS= read -r _w; do
    _w="${_w#not }"
    case "${_w%% *}" in
      always|cmd-prefix|cmd-contains|path-contains|content-contains|repo-has|tool-is|source-is|injected-instruction) ;;
      *) printf '  VIOLATION [context.pack-shape] unknown predicate "%s": %s\n' "${_w%% *}" "$_rel" >&2
         printf 'x' >> "${TMPDIR:-/tmp}/ij1.$$" ;;
    esac
  done
  _r="$(_ij_fm "$f" | awk -F': *' '$1=="run"{print $2;exit}')"
  if [ -n "$_r" ]; then
    [ -f "$(dirname "$f")/$_r" ] \
      || bad context.pack-shape "pack names a run: script that is not beside it: $_rel -> $_r"
  else
    _b="$(awk 'BEGIN{n=0} /^---[[:space:]]*$/ {n++; next} n>=2' "$f" | tr -d '[:space:]')"
    [ -n "$_b" ] || bad context.pack-shape "pack has neither a body nor a run: — it would emit nothing: $_rel"
  fi
  # `scope:` IS A FROZEN ENUM, AND `box` ONLY MEANS SOMETHING ON A TOOL CALL
  # (harbor#599). The engine reaches a tree because a tool call touched it; an
  # event with no tool call touches nothing, so a `scope: box` pack there is a
  # consent that can never be acted on — the same silent never-ran defect as a
  # context-less event above. And a near-miss value (`Box`, `global`, `ambient`)
  # reads as consent to a human while the engine, comparing exactly, keeps the
  # pack home: caught here, not discovered by the session it failed to reach.
  _sc="$(_ij_fm "$f" | awk -F': *' '$1=="scope"{print $2;exit}')"
  case "$_sc" in
    ''|repo) ;;
    box)
      case "$_ev" in
        PreToolUse|PostToolUse|PostToolUseFailure) ;;
        *) bad context.pack-shape "pack declares scope: box on $_ev, which carries no tool call to reach a tree with: $_rel" ;;
      esac ;;
    *) bad context.pack-shape "pack declares scope: $_sc — the values are repo and box: $_rel" ;;
  esac
done
# A PACK OUTSIDE THE TWO DECLARED LOCATIONS IS A PACK NOTHING READS (harbor#588).
# The glob above is `inject.d/*/*.md` and `.claude/inject.d/*.md`, which is
# exactly where CONTRACTS/inject.md says packs live — and so a pack one level
# off, at `inject.d/x.md` or `inject.d/box/sub/x.md`, was not validated and not
# reported either. The installer copies `inject.d/<name>/` and the engine reads
# one directory deep, so such a pack is committed, reviewed and never fires.
# The set is every `.md` under both trees, derived with find; the contract's two
# shapes are the only accepted depths. A README is documentation, not a pack.
# READ LINE BY LINE, NEVER WORD-SPLIT (Codex on #693): `for f in $(find …)`
# broke `inject.d/demo/a rule.md` into two paths and flagged the fragment. The
# list goes through a file so `bad` still counts in this shell, not a pipe's.
_ijl="${TMPDIR:-/tmp}/ij1loc.$$"
for _ijd in "$ROOT/inject.d" "$ROOT/.claude/inject.d" ${_INJ_DIR:+"$_INJ_DIR"}; do
  [ -d "$_ijd" ] || continue
  find "$_ijd" -type f -name '*.md' 2>/dev/null
done | sort > "$_ijl"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in "$ROOT"/*) _rel="${f#$ROOT/}"; _lbl="$_rel" ;; *) _rel="${f#"${_INJ_DIR%/inject.d}"/}"; _lbl="private:$_rel" ;; esac
  case "${_rel##*/}" in README.md) continue ;; esac
  [ "$(printf '%s' "$_rel" | awk -F/ '{ print NF }')" -eq 3 ] \
    || bad context.pack-shape "pack sits where nothing installs or reads it (CONTRACTS/inject.md names inject.d/<name>/ and .claude/inject.d/): $_lbl"
done < "$_ijl"
rm -f "$_ijl"
# The subshell above cannot increment FAIL — the same defect CLI1's header
# records three times over — so its violations are counted through a file.
if [ -f "${TMPDIR:-/tmp}/ij1.$$" ]; then
  FAIL=$(( FAIL + $(wc -c < "${TMPDIR:-/tmp}/ij1.$$" | tr -d ' ') ))
  rm -f "${TMPDIR:-/tmp}/ij1.$$"
fi
}

# ── IJ2 · the project registry and the pack directories agree ──────────────
# BOTH DIRECTIONS, or the registry rots the way every second copy of a list does.
# A pack directory with no registry row is never seeded by `harbor inject
# --projects` and never reaches the repo it was written for. A registry row with
# no directory is a project the pointer advertises to every session on the box —
# which is the more expensive half, because it is paid in every session and the
# thing it points at may not be there.
rule_IJ2() {
rule "context.registry-dirs inject.d/<project>/ and inject.d/box/projects.tsv name the same projects"
# The registry and the project pack folders are the private layer's (harbor#1149): <private>/inject.d/box/projects.tsv
# and <private>/inject.d/<project>/. Core ships neither, so with no private layer there is nothing to compare, and
# the rule says it did not look rather than passing.
_inj_load
_reg="$_INJ_REG"
if [ -n "$_reg" ]; then
  for d in "$ROOT"/inject.d/*/ "$_INJ_DIR"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"; [ "$n" = box ] && continue
    awk -F'\t' -v k="$n" '$1 == k { found = 1 } END { exit !found }' "$_reg" \
      || bad context.registry-dirs "inject.d/$n/ has no row in projects.tsv, so nothing ever seeds it"
  done
  while IFS='	' read -r _n _p _rest; do
    case "$_n" in ''|'#'*) continue ;; esac
    [ -n "$_p" ] || { bad context.registry-dirs "projects.tsv row '$_n' has no path"; continue; }
    case "$_p" in '~/'*) ;; *) bad context.registry-dirs "projects.tsv path is not ~-relative ('$_p') — CONSTITUTION §3" ;; esac
    # THE SECOND DIRECTION, DERIVED RATHER THAN DECLARED (harbor#177). A naive
    # `[ -d inject.d/$_n ]` was tried and reverted because it flags a CORRECT row:
    # `harbor` is the repo rather than a project seeded into, so its packs live in
    # this tree's own `.claude/inject.d/` and there is no `inject.d/harbor/` for
    # there to be. §2.11 makes that false positive a defect, not safety.
    #
    # The filed remedy was a format change — a fourth column, a sentinel path, a
    # self-row convention — on a tracked contract that three things read. It is not
    # needed: DOCTRINE/doc-truth.md's rule is to DERIVE a fact rather than write a
    # copy of it, and "does anything govern this project" is derivable from the two
    # places a pack can live. A declared column would be a third copy that drifts
    # while reading perfectly, and it would make every existing row wrong until
    # edited.
    #
    # So a row is covered when EITHER home holds packs for it, and the finding is
    # the case where neither does: the pointer advertises the project in every
    # session on the box and no rule of its own can ever fire.
    #
    # A REPO THAT IS NOT ON THIS BOX IS UNDECIDABLE, NEVER GREEN. The registry is
    # tracked and the linter runs on hosts that carry some of these repos and not
    # others, so an absent path proves nothing either way. CM3 already answers this
    # shape — "EQUAL mtimes say UNDECIDABLE, never a guess" — and saying so out
    # loud is what keeps the silence from reading as a pass.
    _abs="$HOME/${_p#\~/}"
    if [ -d "$ROOT/inject.d/$_n" ] || [ -d "$_INJ_DIR/$_n" ]; then
      :   # seeded from this repo or from the private layer
    elif [ ! -d "$_abs" ]; then
      _adv context.registry-dirs "$_p"; printf '  ADVISORY [context.registry-dirs] %s is not on this box — cannot tell whether anything governs %s\n' "$_p" "$_n"
    elif [ -n "$(ls "$_abs"/.claude/inject.d/*.md 2>/dev/null)" ]; then
      :   # self-seeded: the packs live in the project's own tree
    else
      bad context.registry-dirs "projects.tsv row '$_n' has no packs — none in the private inject.d/$_n/ and none in $_p/.claude/inject.d/ — so the pointer advertises it in every session and no rule of its own can fire"
    fi
  done < "$_reg"
elif [ -n "$_INJ_DIR" ]; then
  bad context.registry-dirs "the private layer's inject.d/box/projects.tsv is missing — the pointer has no registry"
else
  printf '  no private layer with an inject.d/ on this box, so there is no registry to compare against the pack folders — not checked.\n'
fi
}

# ── T1c · the plan's completion state is generated, not stated ─────────────
# T1 does this for counts and T1b for the architecture page. The gap it leaves
# was measured on 2026-08-21: asked which plan tickets were built, parsing the
# prose for "DONE" said B1-B6, L3, M5, M8 and M9 were open, and probing for the
# artifacts said every one of them exists. Three methods, three answers, and the
# prose lost — harbor#117's "stale checkboxes", on the one document that says
# what Harbor still owes.
#
# PLAN.md is derived from each ticket's own `- Evidence:` line and this rule
# fails when it is stale, exactly as T1 does for STATUS.md. The advisory beside
# it counts UNDECLARED tickets — the ones naming no falsifier at all — because
# that number, not the open count, is how much of the plan is still prose.
rule_T1c() {
rule "doc.plan-generated PLAN.md is regenerated, not hand-edited (harbor#117)"
if _export_tree harbor-build-tickets.md; then
  printf '  (skipped: PLAN.md is generated from harbor-build-tickets.md, which is dev-layer and not in this tree, so there is nothing to regenerate it from)\n'
elif [ -f "$ROOT/bin/plan-status.sh" ]; then
  if ! sh "$ROOT/bin/plan-status.sh" --check >/dev/null 2>&1; then
    bad doc.plan-generated "PLAN.md is stale — run: sh bin/plan-status.sh"
  fi
  _t1c="$(sh "$ROOT/bin/plan-status.sh" --summary 2>/dev/null || true)"
  case "$_t1c" in
    *' 0 UNDECLARED'*) printf '  every plan ticket names a falsifier.\n' ;;
    *UNDECLARED*)      _adv doc.plan-generated undeclared-falsifiers; printf '  ADVISORY [doc.plan-generated] %s — an UNDECLARED ticket cannot be proven finished\n' "$_t1c" ;;
  esac
fi
}

# ── IJ3 · the registry against the ESTATE, not against itself ──────────────
# IJ2 checks the registry against the pack directories — two lists that live in
# this repo. Neither is the box. So a governed repository that nobody registered
# is invisible to both, and `project-pointer.sh` announces a count of the REGISTRY
# in every session while presenting it as a count of the estate.
#
# Measured 2026-08-21: ELEVEN governed repositories on the box, FOUR registered.
# Six of the seven missing ones carry `.claude/skills` — capability a session
# outside the tree cannot see and, being unregistered, is never even named. That
# is the exact failure the pointer exists to prevent, produced by the pointer.
#
# ADVISORY, AND THE WORDING ASSERTS NO REPAIR. Whether a workload repo or `zarija`
# should be governed at the repo tier changes what every session on this box is
# told, so it is the operator's call and not a lint rule's. This says what is
# there and what is named; it does not say one should follow the other. §2.11:
# an advisory that demands an edit nobody wants is one the reader learns to skip.
#
# GOVERNED MEANS A GIT REPO CARRYING `.agents/` OR `.claude/` — the same two
# markers X5 and X6 already treat as the signal, rather than a third definition
# that would drift against them. Depth 1 under $HOME, which is this box's stated
# layout convention and the one X6 also assumes.
rule_IJ3() {
rule "context.repo-registered every governed repo on this box has a registry row (advisory)"
_inj_load
_ij3_reg="$_INJ_REG"
_ij3_home="${HARBOR_ESTATE_ROOT:-$HOME}"
if [ -f "$_ij3_reg" ] && [ -d "$_ij3_home" ]; then
  _ij3_missing=0; _ij3_total=0
  for _r in "$_ij3_home"/*/; do
    [ -d "$_r/.git" ] || continue
    { [ -d "$_r/.agents" ] || [ -d "$_r/.claude" ]; } || continue
    _rn="$(basename "$_r")"
    _ij3_total=$(( _ij3_total + 1 ))
    # Match on the NAME column, the same key IJ2 uses, so the two rules cannot
    # disagree about what "registered" means.
    awk -F'\t' -v k="$_rn" '$1 == k { found = 1 } END { exit !found }' "$_ij3_reg" && continue
    _ij3_extra=''
    [ -d "$_r/.claude/skills" ] && _ij3_extra=' — and it carries .claude/skills nothing outside can see'
    _adv context.repo-registered "$_rn"; printf '  ADVISORY [context.repo-registered] governed but unregistered: %s%s\n' "$_rn" "$_ij3_extra"
    _ij3_missing=$(( _ij3_missing + 1 ))
  done
  if [ "$_ij3_missing" -eq 0 ]; then
    printf '  all %s governed repo(s) on this box have a registry row.\n' "$_ij3_total"
  else
    printf '  %s of %s governed repo(s) are unregistered — the pointer names the rest.\n' \
      "$_ij3_missing" "$_ij3_total"
  fi
fi
}

# ── IJ4 · a tracked project pack must actually be seeded to its project ────
# IJ2 asserts inject.d/<project>/ and projects.tsv agree; IJ3 asserts every
# governed repo has a row. NEITHER asks the question that decides whether a rule
# is delivered: is the pack in the project's own tree, where the engine reads it?
#
# THE INCIDENT, 2026-08-29. inject.d/<repo>/ was committed 2026-08-25. Seeding
# is opt-in (`inject-install.sh --projects`) and the last seeding run was
# 2026-08-23, so ~/<repo>/.claude/inject.d never existed and the note warning
# that `<tool> --full-refresh` destroys 2.5 years of history had never been
# delivered once. inject-install.sh's own status line said `absent or drifted`
# the whole time — the detector was right and nothing consulted it. That is the
# gap this rule closes: not a missing check, a check nobody ran.
#
# ADVISORY, for IJ3's reason. It reads $HOME for sibling repos, and a CI runner
# has none — a hard rule would fail every build on a machine that is behaving
# correctly, which is CONSTITUTION §2.11's false positive exactly.
rule_IJ4() {
rule "drift.pack-installed every tracked pack is installed where the engine reads it — box and project (advisory)"
_inj_load
_ij4_reg="$_INJ_REG"
_ij4_home="${HARBOR_ESTATE_ROOT:-$HOME}"
_ij4_bad=0; _ij4_seen=0
# THE PROJECT PACKS ARE THE PRIVATE LAYER'S (harbor#1149): <private>/inject.d/<name>/ seeded by `inject-install.sh
# --projects`. With no registry there is nothing to seed them by, and the box tier below is still judged.
if [ -n "$_ij4_reg" ]; then
  for _d in "$_INJ_DIR"/*/; do
    [ -d "$_d" ] || continue
    _n="$(basename "$_d")"; [ "$_n" = box ] && continue
    _t="$(awk -F'\t' -v k="$_n" '$1 == k { print $2; exit }' "$_ij4_reg" 2>/dev/null || true)"
    case "$_t" in '~/'*) _t="$_ij4_home/${_t#'~/'}" ;; esac
    # No row, or no such directory on this box, is IJ2's business and IJ3's.
    { [ -n "$_t" ] && [ -d "$_t" ]; } || continue
    _ij4_seen=$(( _ij4_seen + 1 ))
    if [ ! -d "$_t/.claude/inject.d" ]; then
      _adv drift.pack-installed "never-seeded:$_n"; printf '  ADVISORY [drift.pack-installed] %s pack is tracked but NEVER SEEDED: %s/.claude/inject.d does not exist\n' \
        "$_n" "${_t#"$_ij4_home"/}"
      _ij4_bad=$(( _ij4_bad + 1 ))
    elif ! diff -r "$_d" "$_t/.claude/inject.d" >/dev/null 2>&1; then
      _adv drift.pack-installed "drifted:$_n"; printf '  ADVISORY [drift.pack-installed] %s pack has drifted from the repo copy: %s/.claude/inject.d\n' \
        "$_n" "${_t#"$_ij4_home"/}"
      _ij4_bad=$(( _ij4_bad + 1 ))
    fi
  done
fi
# THE BOX TIER IS THE SAME QUESTION ONE LEVEL UP, and leaving it out would make
# this half a rule — box packs load in EVERY session on the machine, where a
# project pack loads in one repo. It was in sync when this landed (2026-08-29),
# which is exactly why it needs a check: a latent gap with nothing watching it
# is how the workload pack sat undelivered for four days.
#
# THE TIER IS CORE'S inject.d/box PLUS THE PRIVATE LAYER'S box files (harbor#1149): the
# installer puts both in one directory, so the comparison is against both, and a private pack
# that was never installed is a gap in this tier like any other. Only what the installer takes
# crosses — a .md pack and projects.tsv — so a stray file in the private box dir is not drift.
_ij4_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -d "$ROOT/inject.d/box" ] && [ -d "$_ij4_cfg" ]; then
  _ij4_u="${TMPDIR:-/tmp}/ij4u.$$"; mkdir -p "$_ij4_u"; cp -R "$ROOT/inject.d/box/." "$_ij4_u/" 2>/dev/null || :
  if [ -n "$_INJ_DIR" ]; then
    for _pf in "$_INJ_DIR"/box/*.md "$_INJ_DIR"/box/projects.tsv; do [ -f "$_pf" ] && cp "$_pf" "$_ij4_u/"; done
  fi
  _ij4_seen=$(( _ij4_seen + 1 ))
  if [ ! -d "$_ij4_cfg/inject.d" ]; then
    _adv drift.pack-installed box-never-installed; printf '  ADVISORY [drift.pack-installed] the BOX packs are tracked but NEVER INSTALLED: %s/inject.d does not exist\n' \
      "${_ij4_cfg#"$HOME"/}"
    _ij4_bad=$(( _ij4_bad + 1 ))
  elif ! diff -r "$_ij4_u" "$_ij4_cfg/inject.d" >/dev/null 2>&1; then
    _adv drift.pack-installed box-drifted; printf '  ADVISORY [drift.pack-installed] the BOX packs have drifted from the repo copy: %s/inject.d\n' \
      "${_ij4_cfg#"$HOME"/}"
    _ij4_bad=$(( _ij4_bad + 1 ))
  fi
  rm -rf "$_ij4_u"
fi
if [ "$_ij4_seen" -gt 0 ]; then
  if [ "$_ij4_bad" -eq 0 ]; then
    printf '  all %s tracked pack set(s) present on this box are installed and current.\n' "$_ij4_seen"
  else
    printf '  %s of %s need: sh bin/inject-install.sh --live --apply --projects\n' "$_ij4_bad" "$_ij4_seen"
  fi
fi
}

# ── CM1 · a slash command's script must resolve from the session's cwd ─────
# X7's principle on a fifth surface, and X7 cannot see it. X7 says: "Not deployed
# is a choice — until an installed script INVOKES the thing, at which point
# absence is not a choice, it is a call into nothing." A slash command IS an
# installed artefact that invokes; the only difference is that it is markdown, so
# X7's scan for `$DIR/x.sh` inside installed SCRIPTS never looks at it.
#
# ALL THREE OF harbor's COMMANDS WERE BROKEN, measured 2026-08-13. Every one
# invoked `sh bin/<script>.sh` — a repo-relative path — while `skills-install.sh`
# installs them to `$CFG/commands/`, where they are GLOBAL and run in whatever cwd
# the session has. There is no in-repo `.claude/commands/`, so global is the only
# ── IJ5 · the registry against the DISK, in the direction nothing else walks ─
# IJ2 compares two lists that both live in this repo. IJ3 walks the box for a
# governed repo with no row. IJ4 asks whether a pack reached the tree. All three
# travel REPO -> ROW. None of them asks the reverse, and that is the direction the
# defect actually took.
#
# Measured 2026-09-15. ~/oldname was renamed ~/<newname>. The registry row kept the old
# path, and project-pointer.sh drops a row whose directory is gone --
# `[ -d "$path" ] || continue` -- so nothing broke and nothing said anything. Every
# session outside the repo was told "4 REGISTERED project(s)" while the measurement repo, the
# tree most of this estate's work happens in, went unmentioned. A silent drop is
# worse than a broken row: a broken row gets fixed the first time someone reads it.
#
# THE DISCRIMINATOR IS "DOES ANY ROW RESOLVE", and it is the whole rule. A bare CI
# checkout has no sibling repos, so EVERY row is missing there and a rule that
# reported them all would fire hardest on the machine behaving most correctly --
# CONSTITUTION No.2.11, and the reason IJ3 and IJ4 are advisory too. So this stays
# silent unless the box is one where the registry is demonstrably live: at least
# one row resolves. On such a box a row that does not resolve is not an absent
# checkout, it is a stale registry.
#
# ADVISORY, for IJ3's reason: whether a path should be repaired or the row retired
# is the operator's call, and this rule states what it found rather than demanding
# an edit nobody wants.
rule_IJ5() {
rule "context.registry-resolves every registry row still resolves to a directory (advisory)"
_inj_load
_ij5_reg="$_INJ_REG"
_ij5_home="${HARBOR_ESTATE_ROOT:-$HOME}"
if [ -f "$_ij5_reg" ]; then
  _ij5_live=0; _ij5_dead=0; _ij5_names=''
  while IFS='	' read -r _n _p _rest; do
    case "$_n" in ''|'#'*) continue ;; esac
    [ -n "$_p" ] || continue
    case "$_p" in '~/'*) _pa="$_ij5_home/${_p#'~/'}" ;; *) _pa="$_p" ;; esac
    if [ -d "$_pa" ]; then
      _ij5_live=$(( _ij5_live + 1 ))
    else
      _ij5_dead=$(( _ij5_dead + 1 ))
      _ij5_names="$_ij5_names$_n ($_p)
"
    fi
  done < "$_ij5_reg"
  if [ "$_ij5_live" -eq 0 ]; then
    printf '  no registry row resolves here, so this box cannot tell a stale row from an absent checkout — not checked.\n'
  elif [ "$_ij5_dead" -eq 0 ]; then
    printf '  all %s registry row(s) resolve to a directory on this box.\n' "$_ij5_live"
  else
    printf '%s' "$_ij5_names" | while IFS= read -r _row; do
      [ -n "$_row" ] || continue
      _adv context.registry-resolves "$_row"; printf '  ADVISORY [context.registry-resolves] registry row points at nothing: %s — the pointer DROPS it in silence, so every session is told a count that excludes it\n' "$_row"
    done
  fi
fi
}

# tier they have. Reproduced from the operator's usual cwd:
#
#   $ cd ~ && sh bin/context-budget.sh
#   sh: bin/context-budget.sh: No such file or directory
#
# and none of the four scripts they call is in an installer payload either, so
# there was no cwd on the box from which `/harbor-context` worked except the repo
# root itself.
#
# WHY THIS RULE DOES NOT SCAN inject.d/, which has the same shape and is CORRECT.
# `.claude/inject.d/merge-note.sh` runs `exec sh "bin/govern-hook.sh" --note`,
# also relative — and it works, because hooks/injection-rule/injection-rule.sh wraps every `run:`
# call in `(cd "$REPO" 2>/dev/null && sh "$_dir/$_run")`. CITED BY SHAPE, NOT BY
# LINE: this comment said `:587` until 2026-09-16, by which time the wrapper had
# moved to 623 and the number pointed at unrelated code — a line number in prose
# is a copy of a fact that lives in the file, and copies drift while reading
# perfectly. Verified both ways from $HOME: rc=0 through the wrapper,
# rc=127 without it. Nothing cds for a slash command, which is the whole
# difference. A rule that flagged inject.d would be a false positive on working
# behaviour, and §2.11 makes that a defect rather than safety.
# ── IJ6 · a governed repo whose sessions load NO memory (advisory) ──────────
# The auto-memory store is keyed by the session's working directory, so a repo
# whose key has no store behind it starts every session with none of the notes.
# Measured 2026-09-16, before bin/memory-route.sh existed: 10 of 10 governed
# repos were in that state, including the measurement repo, where most of this estate's
# client work happens. The notes most worth having in a repo are the ones
# written while working in it, and every one of them was filed from a $HOME
# session and was therefore invisible exactly where it applied.
#
# THIS IS THE C8 CALLER, deliberately and not incidentally. memory-route.sh
# asserts something real and nothing else runs it; a tool in that state is
# harbor#466's defect, and declaring it idle would hide a check whose whole
# value is catching the NEXT repo somebody registers. Lint runs on every commit
# and push, which is when a new row in projects.tsv first appears.
#
# SILENT UNLESS THE BOX IS DEMONSTRABLY LIVE, for IJ5's reason: a bare CI
# checkout has no config dir and no sibling repos, so an unconditional rule
# would fire hardest on the machine behaving most correctly. Exit 3 from the
# tool (D-29 unchecked) means it STOOD DOWN — no registry, no store, nothing
# parsed — and that is treated here as "not a live box", never as a finding.
# Exit 2 meant the same before D-49 and is read the same for the window.
#
# ADVISORY, for IJ3's reason: the remedy writes symlinks into the operator's
# config dir, which is theirs to run, not lint's to demand.
rule_IJ6() {
rule "memory.repo-reachable every governed repo's sessions can load the memory store (advisory)"
_ij6_tool="$ROOT/bin/memory-route.sh"
_ij6_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -x "$_ij6_tool" ] || [ -f "$_ij6_tool" ]; then
  if [ -d "$_ij6_cfg/projects" ]; then
    _ij6_out="$(HARBOR_REPO="$ROOT" sh "$_ij6_tool" --dir "$_ij6_cfg" --quiet 2>/dev/null)"; _ij6_rc=$?
    case "$_ij6_rc" in
      0) printf '  every governed repo on this box loads the memory store.\n' ;;
      1) _ij6_blind="$(HARBOR_REPO="$ROOT" sh "$_ij6_tool" --dir "$_ij6_cfg" 2>/dev/null | sed -n 's/^  BLIND[[:space:]]*\([^[:space:]]*\).*/\1/p')"
         _ij6_n="$(printf '%s\n' "$_ij6_blind" | grep -c .)"
         # The ledger records this once, as check/memory-route, from the receipt the run above just
         # wrote (harbor#896); a lint/IJ6 finding over the same repos would file it twice.
         _adv memory.repo-reachable -; printf '  ADVISORY [memory.repo-reachable] %s governed repo(s) start with NO memory — sh bin/memory-route.sh --live --apply\n' "$_ij6_n" ;;
      3) : ;;   # stood down (D-29 unchecked): not a live box, and never a finding
      2) : ;;   # D-49 window: the code a stood-down run exited before D-49 (and a usage error today): read the same
      *) : ;;   # anything else is no verdict either
    esac
  fi
fi
}

rule_CM1() {
rule "skill.command-script-resolves every script a slash command invokes resolves from the session's cwd, not just the repo root"
# SHAPE ONLY — NEVER EXISTENCE ON THE AMBIENT FILESYSTEM. The first cut resolved
# `~/` against $HOME and then ran `[ -f ]`, which made this rule answer about a
# tree it was not pointed at. Three consequences, all reproduced 2026-08-14 with
# $ROOT held constant and only $HOME changed:
#   · GREEN on this box, RED on a github-hosted runner — and governance.yml:170
#     makes that a one-word flip, so the conventions job passes today by accident.
#   · a linted tree containing nothing but commands/ passed, because the check
#     stat'ed the OPERATOR's ~/harbor instead. A PR that renames a script is then
#     graded against a working copy that is not the PR.
#   · not testable: no HARBOR_ROOT fixture can control the answer.
# A path's shape is decidable from the text; its existence on someone else's
# machine is not this linter's business. Existence is still checked when the path
# lands inside $ROOT, because there the tree under test IS the subject.
_cm_scripts="${TMPDIR:-/tmp}/.helm-cm1.$$"
for f in "$ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  _cmb="${f#"$ROOT"/}"
  # `sh`, an optional flag, then the path. Prose counts on purpose: a command file
  # that TELLS the operator to run `sh bin/x.sh` hands them a line that fails from
  # where they are standing.
  grep -oE 'sh +(-[a-z]+ +)?[^ `|)]+\.sh' "$f" 2>/dev/null \
    | sed -E 's/^sh +(-[a-z]+ +)?//' | sort -u > "$_cm_scripts" || :
  while IFS= read -r _cmp; do
    [ -n "$_cmp" ] || continue
    # A LEADING QUOTE IS NOT PART OF THE PATH. `sh "$HOME/x.sh"` and
    # `sh '~/harbor/bin/x.sh'` both arrived with the quote attached, missed every
    # arm below, and were reported as repo-relative — a violation whose text was
    # factually false about a line that runs fine from `/`.
    _cmp="${_cmp#\"}"; _cmp="${_cmp#\'}"
    _cmp="${_cmp%\"}"; _cmp="${_cmp%\'}"
    [ -n "$_cmp" ] || continue
    case "$_cmp" in
      /*)    _cma="$_cmp" ;;
      '~/'*) _cma="" ;;    # absolute by shape; whose $HOME is not this rule's business
      '$'*)  continue ;;   # a variable is the operator's to resolve; not decidable here
      *)
        # A `cd` EARLIER IN THE SAME COMMAND MAKES A RELATIVE PATH CORRECT, and
        # this rule's own header blesses exactly that construct for inject.d
        # (`(cd "$REPO" && sh bin/x.sh)`, verified rc=0 from $HOME). Flagging it
        # inside commands/ while exempting it next door is the rule contradicting
        # its own reasoning.
        if grep -qE '(cd [^&|;]+(&&|;) *)?sh +(-[a-z]+ +)?["'"'"']?'"$(printf '%s' "$_cmp" | sed 's/[.[\*^$/]/\\&/g')" "$f" 2>/dev/null \
           && grep -qE 'cd [^&|;]+(&&|;) *sh +(-[a-z]+ +)?["'"'"']?'"$(printf '%s' "$_cmp" | sed 's/[.[\*^$/]/\\&/g')" "$f" 2>/dev/null; then
          continue
        fi
        bad skill.command-script-resolves "$_cmb invokes \`sh $_cmp\` — repo-relative with no preceding cd, and a slash command runs in the session's cwd"
        continue ;;
    esac
    # Only a path that lands inside the tree under test can be checked for
    # existence here. Anything else is a claim about another machine.
    case "$_cma" in
      "$ROOT"/*) [ -f "$_cma" ] || bad skill.command-script-resolves "$_cmb invokes \`sh $_cmp\`, which does not exist in this tree" ;;
    esac
  done < "$_cm_scripts"
done
rm -f "$_cm_scripts"
}

# ── CM2 · a command's allowed-tools must PERMIT the command it runs ─────────
# THE FIRST VERSION'S PREMISE WAS WRONG, and it is worth writing down because the
# wrong premise produced a rule that fired on correct work. It tested
# `case "$allowed_tools" in *"sh $path"*)` — a literal substring — and reported
# "every use prompts" whenever the declared grant was not that exact string. But
# `allowed-tools` matches by PREFIX, with `:*` as an argument wildcard, so a grant
# STRICTLY WIDER than the invocation permits it and can never prompt. Measured on
# this box rather than assumed: the operator's own settings distinguish
# `Bash(cu note:*)` from `Bash(cu notes)`, which is meaningless unless `:*` is an
# argument wildcard, and harbor's own commands depend on it —
# commands/harbor-merge.md declares `Bash(gh pr view:*)` and runs `gh pr view $1`,
# commands/harbor-context.md declares `Bash(wc:*)` and `Bash(ls:*)`. Under the old
# predicate all three of those were violations.
#
# So the question is not "does the frontmatter contain this string" but "does any
# grant PERMIT this invocation". A bare `Bash` permits everything and is silent
# here, which is correct: it is over-broad, not broken, and over-broad grants are a
# different rule's subject if they are anyone's.
#
# AND THE WHOLE FRONTMATTER BLOCK IS READ, not one physical line. The first cut was
# `sed -n 's/^allowed-tools:...//p' | head -1`, which saw only the first line: a
# wrapped scalar was a false positive, and a YAML block sequence (`allowed-tools:`
# followed by `  - Bash(...)`) made the value empty, which the next line turned
# into `continue` — silently disabling the rule for that whole file. Every
# `Bash(...)` in the frontmatter is collected instead, whatever the spelling.
rule_CM2() {
rule "skill.command-tools-allowed a slash command's allowed-tools permits the invocation in its body"
for f in "$ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  _cmb="${f#"$ROOT"/}"
  # The frontmatter block only: line 1 `---` up to the closing `---`.
  _cm_fm="${TMPDIR:-/tmp}/.helm-cm2fm.$$"
  awk 'NR==1 && $0=="---" {inx=1; next} inx && $0=="---" {exit} inx {print}' "$f" > "$_cm_fm" 2>/dev/null || :
  # A bare `Bash` (no parentheses) permits every Bash call — nothing to check.
  if grep -qE '(^|[[:space:],-])Bash([[:space:],]|$)' "$_cm_fm" 2>/dev/null; then
    rm -f "$_cm_fm"; continue
  fi
  _cm_grants="${TMPDIR:-/tmp}/.helm-cm2g.$$"
  grep -oE 'Bash\([^)]*\)' "$_cm_fm" 2>/dev/null \
    | sed -E 's/^Bash\(//; s/\)$//; s/:\*$//' | sort -u > "$_cm_grants" || :
  rm -f "$_cm_fm"
  # No allowed-tools at all is not this rule's business — the harness prompts, and
  # a command file may legitimately declare none.
  if [ ! -s "$_cm_grants" ]; then rm -f "$_cm_grants"; continue; fi
  _cm_inv="${TMPDIR:-/tmp}/.helm-cm2i.$$"
  # The whole invocation, not just its path: prefix matching needs the real string.
  sed -n 's/^!`\(.*\)`.*/\1/p' "$f" 2>/dev/null | sort -u > "$_cm_inv" || :
  while IFS= read -r _cmi; do
    [ -n "$_cmi" ] || continue
    _cm_ok=0
    while IFS= read -r _cmg; do
      [ -n "$_cmg" ] || continue
      case "$_cmi" in "$_cmg"*) _cm_ok=1; break ;; esac
    done < "$_cm_grants"
    [ "$_cm_ok" -eq 1 ] || bad skill.command-tools-allowed "$_cmb runs \`$_cmi\` and no allowed-tools grant is a prefix of it — every use prompts"
  done < "$_cm_inv"
  rm -f "$_cm_grants" "$_cm_inv"
done
}

# ── CM3 · the installed slash commands must not drift from the repo ────────
# THE SAME BLIND SPOT, A THIRD TIME. X2 covers $CFG/bin, X8 covers installed
# skills (authored, and vendored since harbor#214) — and `commands/` was in
# neither, on a box where `skills-install.sh` installs it as a third payload kind
# and already computes `current`/`DRIFTED`/`absent` in its dry run. The capability
# existed; nothing in the lint sweep asked for it, so the answer only appeared if
# somebody happened to run that command. X2's own scope note describes exactly
# this shape: "the tools an operator types most often had no drift check at all."
#
# The cost of this class is measured, not hypothetical: de-persona was recorded
# "closed the same day" on 2026-07-26 while the installed copies carried
# {{PRINCIPAL_NAME}} for seventeen more days, because the only rule that could
# have seen it did not walk that directory (harbor#214).
#
# ADVISORY, in the X2/X4/X5/X8 family, and for their reason: the repair is a
# judgement about direction, and a re-install changes what every future session
# loads. Direction by mtime, and UNDECIDABLE said out loud rather than guessed —
# on 2026-08-06 a reinstall was one keystroke from destroying 38 lines that
# existed only on the box.
rule_CM3() {
rule "drift.slash-commands the installed slash commands do not drift from the repo (advisory)"
_cm3_live="${HELM_LIVE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}/commands"
_cm3_n=0
for f in "$ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  _cm3_b="$(basename "$f")"
  _cm3_d="$_cm3_live/$_cm3_b"
  # NOT INSTALLED IS A CHOICE, the same call X2 makes — a command can be tracked
  # and deliberately not deployed. Drift is a comparison, and there is nothing to
  # compare against.
  [ -f "$_cm3_d" ] || continue
  cmp -s "$f" "$_cm3_d" && continue
  # _x8_repo_time / _x8_mtime, not a third copy: they already encode the BSD/GNU
  # `stat -f` trap (lint-conventions.sh:1409) and return digits or nothing.
  #
  # THE SAME WORKTREE INVERSION, and CM3 prints the same destructive remedy — so
  # the repo side is dated from git here too. See _x8_repo_time's header for the
  # measurement; this rule had it for exactly the same reason and would have been
  # the second place to say "reinstall" over newer live work.
  _cm3_rm="$(_x8_repo_time "$f")"; _cm3_lm="$(_x8_mtime "$_cm3_d")"
  if [ -n "$_cm3_rm" ] && [ -n "$_cm3_lm" ] && [ "$_cm3_lm" -gt "$_cm3_rm" ]; then
    _adv drift.slash-commands "live-newer:$_cm3_b"; echo "  ADVISORY [drift.slash-commands] LIVE IS NEWER — capture it into the repo, do NOT reinstall: $_cm3_b" >&2
  elif [ -n "$_cm3_rm" ] && [ -n "$_cm3_lm" ] && [ "$_cm3_rm" -gt "$_cm3_lm" ]; then
    _adv drift.slash-commands "repo-newer:$_cm3_b"; echo "  ADVISORY [drift.slash-commands] repo is newer — the box lags; reinstall is the right direction: $_cm3_b" >&2
  else
    _adv drift.slash-commands "undecidable:$_cm3_b"; echo "  ADVISORY [drift.slash-commands] differs, direction UNDECIDABLE — read the diff before either copy: $_cm3_b" >&2
  fi
  _cm3_n=$(( _cm3_n + 1 ))
done
[ "$_cm3_n" -eq 0 ] || echo "  $_cm3_n installed command(s) have drifted — sh bin/skills-install.sh commands --all --live" >&2
}

# ── C2 · no Claude attribution in commit messages ──────────────────────────
rule_C2() {
rule "git.no-ai-attribution no AI attribution in commits on THIS branch (main history is advisory)"
# THE PATTERN IS NOT DEFINED HERE. It is read out of hooks/commit-msg, which is
# the one place it exists, because the two checks are the same rule at two
# moments and a second grep for the same shape is a copy that drifts silently
# while reading correctly. The hook is the owner rather than this file for a
# reason: the hook is the only one that can PREVENT the trailer, and C2 can only
# count it afterwards — on `main` not even that, since the repair there is a
# force-push and the rule downgrades itself to an advisory.
#
# The hook missing is itself the violation. A repo that dropped the mechanism
# and kept the linter has a rule again instead of a gate, and that must be
# loud rather than quietly falling back to an inline literal that then becomes
# the copy this comment exists to prevent.
_c2_hook="$ROOT/hooks/commit-msg"
_c2_ere=''
if [ -f "$_c2_hook" ]; then
  _c2_ere="$(sed -n "s/^HARBOR_ATTRIBUTION_ERE='\(.*\)'$/\1/p" "$_c2_hook" | head -1)"
  [ -n "$_c2_ere" ] || bad git.no-ai-attribution "hooks/commit-msg no longer defines HARBOR_ATTRIBUTION_ERE — C2 has no pattern to enforce"
else
  bad git.no-ai-attribution "hooks/commit-msg is missing — the attribution rule has a linter but no mechanism"
fi
# ── THREE REASONS THIS RULE INSPECTED NOTHING (harbor#307) ───────────────────
#
# CONSTITUTION says "No AI-attribution trailers in commits or PRs. Enforced by
# lint rule C2." Measured 2026-08-25, C2 enforced it almost nowhere:
#
#  1. `[ -d "$ROOT/.git" ]` — IN A WORKTREE .git IS A FILE, not a directory, so
#     the entire block below was skipped. Harbor standardised on session
#     worktrees (CI-4, bin/worktree.sh, and `git worktree list` shows nineteen),
#     so the rule was disabled in exactly the mode the repo works in. Verified on
#     this checkout: `[ -d <worktree>/.git ]` is false, `[ -d ~/harbor/.git ]` is
#     true. `rev-parse --git-dir` asks git instead of guessing at a layout.
#
#  2. `main..HEAD` IS EMPTY WHEN HEAD IS MAIN, so on main the blocking arm read
#     zero commits — not "too late", nothing at all. The range is now anchored on
#     the PUSHED tip, preferring the remote-tracking ref: on a feature branch it
#     is the branch's own commits, and on main it is whatever is not yet pushed,
#     which is precisely the set still rewritable without a force-push. That is
#     the "point the blocking arm at the pushed range" the ticket asks for.
#     `origin/main` is also the ref that exists in CI, where actions/checkout
#     creates remote-tracking refs and no local `main`.
#
#  3. THE ADVISORY'S `-40` WINDOW HID EVERY REAL HIT. Measured on this history:
#     8 of 337 commits on main carry a trailer under C2's own pattern, and the
#     last 40 carry NONE — so the advisory printed nothing while the condition it
#     reports was true eight times. Reading the full history costs one git log.
#
# THE TICKET'S COUNT IS CORRECTED HERE TOO. It reports "26 of 308", from an
# UNANCHORED grep for the trailer text. C2's pattern is anchored at line start,
# and the difference is not pedantry: this repo writes ABOUT the trailer
# constantly, so an unanchored count scores every prose mention as a violation.
# The real number is 8. A rule that over-counts its own subject teaches the
# reader to discount it, which is the same failure as under-counting.
if [ -n "$_c2_ere" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  base=""
  for _c2b in origin/main main; do
    git -C "$ROOT" rev-parse --verify -q "$_c2b" >/dev/null 2>&1 && { base="$_c2b"; break; }
  done
  if [ -n "$base" ]; then
    n="$(git -C "$ROOT" log --format='%B' "$base..HEAD" 2>/dev/null | grep -ciE "$_c2_ere" || true)"
    [ "${n:-0}" -gt 0 ] && bad git.no-ai-attribution "$n commit(s) not yet on $base carry AI attribution (rewritable — they are unpushed)"
    # Pushed history is reported, never blocking: fixing it needs a force-push to
    # a shared branch, which is the operator's decision. FULL history, not a
    # window — see reason 3 above.
    m="$(git -C "$ROOT" log --format='%B' "$base" 2>/dev/null | grep -ciE "$_c2_ere" || true)"
    [ "${m:-0}" -gt 0 ] && { _adv git.no-ai-attribution "attributed-commits:$base"; printf '  ADVISORY [git.no-ai-attribution] %s pre-existing commit(s) on %s carry attribution (needs a force-push to fix)\n' "$m" "$base"; }
  else
    # A REPO WITH NO BASE REF IS NOT A CLEAN REPO. Silence here is what reason 1
    # looked like from the outside for as long as it stood.
    _adv git.no-ai-attribution no-base; printf '  ADVISORY [git.no-ai-attribution] no origin/main or main ref in this checkout — NO commit was inspected\n' >&2
  fi
  # ── THE COUNTER IS NOT THE MECHANISM ────────────────────────────────────────
  # C2 can only count a trailer after it exists; hooks/commit-msg is the only
  # thing that can PREVENT one, so whether it is installed is read below on
  # every run, never stated here (harbor#490). When this block was written,
  # core.hooksPath was unset and commit-msg was inert while the hook itself
  # discriminated correctly; "a rule with no mechanism is a wish" was the
  # constitution's own example. A comment that says what the box holds today
  # is the copy that drifted: hooksPath has since been set, as `hooks` or its
  # absolute path, which is what the case below accepts (harbor#490).
  #
  # ADVISORY, AND INSTALLING IT IS NOT THIS LINTER'S ACT. Encoding a fix is
  # human-gated; a linter that configured the repo it is judging would be the
  # self-approval loop. So it names the state and the one command. Suppressed
  # under GITHUB_ACTIONS: a disposable CI checkout never has local hooks and
  # never should, so printing it there would be noise on every run.
  if [ -z "${GITHUB_ACTIONS:-}" ] && [ -f "$_c2_hook" ]; then
    _c2_hp="$(git -C "$ROOT" config --get core.hooksPath 2>/dev/null || true)"
    # RESOLVED AGAINST $ROOT, because --git-common-dir ANSWERS RELATIVE. Asked
    # from a repo root it returns the bare `.git`, so joining a path onto it
    # resolved against the CALLER's cwd — and this rule is reached with
    # HARBOR_ROOT pointing somewhere else all through lint-test. MEASURED on a
    # fixture with commit-msg symlinked in: silent from $ROOT, and
    # "NOT installed" from /tmp. An advisory that misreports is the defect
    # harbor#307 is about, one rule over.
    _c2_gd="$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null || echo .git)"
    case "$_c2_gd" in /*) ;; *) _c2_gd="$ROOT/$_c2_gd" ;; esac
    case "$_c2_hp" in
      hooks|"$ROOT/hooks") ;;
      *) # ALL THREE TRACKED HOOKS, not just commit-msg. The state first measured
         # here was "commit-msg and pre-push are both inert" (the comment above),
         # and then the check looked at ONE of them, so a box with commit-msg
         # symlinked by hand and the other two missing stayed silent. That gap
         # became load-bearing on 2026-09-05, when the conventions linter moved
         # out of pre-commit and into pre-push: pre-push is now the ONLY local
         # run of it, so an uninstalled pre-push means no local linting at all,
         # silently. Derived from hooks/ by listing it, so a fourth hook is
         # covered by existing rather than by someone remembering this line.
         #
         # THE PROSE NAMES NO HOOK, deliberately. It read "commit-msg is what
         # prevents one, and pre-push is the only local run of this linter"
         # until its own suite caught that: an arm asserting the advisory
         # NAMES an uninstalled pre-push was satisfied by that sentence, so it
         # passed whatever the list contained. Every hook name in this message
         # now comes from the filesystem, which is what makes it assertable.
         _c2_missing=''
         for _c2_h in "$ROOT"/hooks/*; do
           [ -f "$_c2_h" ] || continue
           _c2_hn="${_c2_h##*/}"
           [ -e "$_c2_gd/hooks/$_c2_hn" ] || _c2_missing="$_c2_missing $_c2_hn"
         done
         [ -z "$_c2_missing" ] \
           || { _adv git.no-ai-attribution $_c2_missing; printf '  ADVISORY [git.no-ai-attribution] tracked hook(s) NOT installed (core.hooksPath=%s):%s — the counter is not the mechanism; these are. Install them: git -C %s config core.hooksPath hooks\n' \
                "${_c2_hp:-unset}" "$_c2_missing" "$ROOT"; } ;;
    esac
  fi
fi
}

# ── HP1 · no tracked file names this machine's home directory (harbor#602) ──
rule_HP1() {
rule "lint.no-home-path no tracked file names the running user's home directory by absolute path"
# WHY THIS EXISTS. harbor#602: one operator's home was compiled into the floor
# and its own tests, so Harbor could not be installed elsewhere unedited. A test
# that names its author's home does not fail on a second machine — it passes
# vacuously, or errors in a way that reads as environmental. Measured 2026-09-22
# on the guard corpus: eight config-dir rows blocked ONLY when the path was the
# runner's own home, and on a synthetic second home floor-equiv's coverage fell
# from 62 to 61 of 75 — bash:redirect-into-cfg exercised by nothing, silently.
#
# THE PATTERN IS DERIVED FROM $HOME, NEVER WRITTEN HERE. The ticket asked for
# "no literal /Users/", and that was measured first: it flags every deliberate
# test home in the floor's red-team cases (`/Users/probe/.aws/credentials`,
# `/Users/me/proj`), whose verdicts do not depend on whose machine runs them.
# Refusing those is a false positive on the floor's own corpus (§2.11). Re-derive:
#   git grep -n -E '/Users/[A-Za-z0-9_]' -- bin fixtures
# The defect is an author's OWN home leaking in, and the one place that string
# is known is the author's $HOME when they lint before pushing. Write `$HOME` or
# `~`; in a corpus fixture write `@HOME@`, which bin/floor-equiv.sh renders.
#
# EXCLUDED, EACH FOR A STATED REASON:
#   EVALS-DATA/            captured run data: it records what actually happened,
#   skills/*/EVALS/RUN-*/  and a rewritten path would record a run nobody ran.
#   FLOOR.md               measured bypass payloads: the guard's verdict depends
#                          on the literal spelling, so a rewrite would record a
#                          payload nobody measured.
# launchd/ WAS EXCLUDED UNTIL harbor#630: launchd does not expand $HOME, so a plist
# had to spell it. The plists are templates now (@HOME@, rendered at install by
# bin/launchd-render.sh from CONTRACTS/roots.tsv), so they are scanned like any file.
_hp1_home="${HOME:-}"
case "$_hp1_home" in
  ''|/) _adv lint.no-home-path home-unset; printf '  ADVISORY [lint.no-home-path] $HOME is "%s" — NO file was inspected\n' "$_hp1_home" >&2 ;;
  *)
    if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
      # To a file, not a pipe: `bad` inside `| while` runs in a subshell, and
      # its FAIL increment would vanish with it.
      # And git grep's exit is read, not swallowed: 1 is "no match", but 128 (a
      # malformed pathspec) inspected nothing and must not read as clean.
      _hp1_tmp="${TMPDIR:-/tmp}/harbor-hp1.$$"
      _hp1_rc=0
      git -C "$ROOT" grep -n -I -F -e "$_hp1_home" -- . \
        ':(exclude)EVALS-DATA' ':(exclude,glob)skills/*/EVALS/RUN-*/**' \
        ':(exclude)FLOOR.md' > "$_hp1_tmp" 2>/dev/null || _hp1_rc=$?
      [ "$_hp1_rc" -le 1 ] || bad lint.no-home-path "git grep exited $_hp1_rc — NO file was inspected, and this is not a pass"
      # The path and line only: the matched text carries the home it is about.
      while IFS=: read -r _hp1_f _hp1_n _hp1_rest; do
        bad lint.no-home-path "$_hp1_f:$_hp1_n names this machine's home — write \$HOME or ~ (in a corpus fixture, @HOME@)"
      done < "$_hp1_tmp"
      rm -f "$_hp1_tmp"
    else
      _adv lint.no-home-path not-a-checkout; printf '  ADVISORY [lint.no-home-path] %s is not a git checkout — NO file was inspected\n' "$ROOT" >&2
    fi ;;
esac
}

# ── ROOT1 · every root default agrees with CONTRACTS/roots.tsv (harbor#630) ──
rule_ROOT1() {
rule "scope.root-defaults every repo-root default matches CONTRACTS/roots.tsv"
# WHY THIS EXISTS. Measured 2026-09-23: 91 non-comment, non-markdown lines here
# name a governed repo and 13 go through an override variable. Those 13 were
# written one at a time and had already diverged — PROJECT_INIT_SRC and
# HARBOR_PROJECT_INIT are two names for one repo with one default, and nothing
# compared them, so both read correctly at every site.
#
# THE TABLE IS NOT THE RULE. A table with no check is one more copy, and a copy
# is what this removes. bin/roots.sh --check is the check; this rule is how it
# runs on every commit. Its own suite (tests/install/roots-test.sh) holds four negative
# cases, because a --check that cannot go red would make this rule decorative.
#
# NOT A SECOND IMPLEMENTATION. The comparison lives in roots.sh alone; this
# calls it and reports. A lint rule that re-derived the answer would be the
# third spelling of a rule that exists to stop there being two.
_root1_out="${TMPDIR:-/tmp}/harbor-root1.$$"
if sh "$ROOT/bin/roots.sh" --check > "$_root1_out" 2>&1; then
  say "  $(tail -1 "$_root1_out")"
else
  # roots.sh --check logs its disagreements through bin/log-lib.sh (harbor#771): each is a
  # "  FAIL: <what>" line, not the pre-LOG1 "ROOTS  <what>" this used to key on.
  while IFS= read -r _root1_l; do
    case "$_root1_l" in
      '  FAIL: '*) bad scope.root-defaults "${_root1_l#  FAIL: }" ;;
    esac
  done < "$_root1_out"
fi
rm -f "$_root1_out"
}

# ── SHIM1 · the operator's PATH shims still point at a file (advisory) ───────
rule_SHIM1() {
rule "drift.shim-targets every shim in CONTRACTS/shims.tsv points where the table says (advisory)"
# ADVISORY, and that is the honest level. Nineteen symlinks in ~/.local/bin point
# into this repo and NOTHING created them — the set on any box is whatever its
# operator typed, so a fresh clone legitimately has none of them and a hard
# failure would be red on every machine that has not opted in. A rule that is red
# everywhere protects nothing (CONSTITUTION No.2.11).
#
# IT IS STILL WORTH RUNNING, for the reason IJ6 runs memory-route.sh: the value
# is catching the NEXT one — a shim added to the table and never installed, or,
# after harbor#619, nineteen shims pointing at a directory that no longer exists.
# `gcx`, `gcloud`, `secret`, `memory`, `harbor` and `wait-for` are in that set,
# so the failure mode is every credentialed command on the box saying "not found"
# at once.
#
# A COUNT, NOT A LIST. Printing nineteen advisory lines on a fresh clone trains
# the reader to skip the block, which is how the one real row gets missed.
# The install standard (harbor#765): shim-install needs a target, and its dry run of the live dir
# reads, never writes. A shim to link or repoint is a note there, a collision a FAIL.
_shim1_out="${TMPDIR:-/tmp}/harbor-shim1.$$"
sh "$ROOT/bin/shim-install.sh" --live > "$_shim1_out" 2>&1 || :
_shim1_n="$(grep -cE '^  (note: [^ ]+: would (link|repoint) |FAIL: )' "$_shim1_out" || true)"
if [ "${_shim1_n:-0}" -eq 0 ] && grep -q '^  ok: ' "$_shim1_out"; then
  say "  all $(grep -c '^  ok: ' "$_shim1_out") shim(s) point where the table says."
else
  _adv drift.shim-targets shims; printf '  ADVISORY [drift.shim-targets] %s shim(s) missing, mispointed or blocked — sh bin/shim-install.sh --live, then --apply --live\n' \
    "${_shim1_n:-0}" >&2
fi
grep -E '^  WARN: .* is unmanaged' "$_shim1_out" 2>/dev/null | while IFS= read -r _shim1_u; do
  _adv drift.shim-targets "unmanaged:${_shim1_u%% is unmanaged*}"; printf '  ADVISORY [drift.shim-targets] %s\n' "${_shim1_u#  WARN: }" >&2
done
rm -f "$_shim1_out"
}

# ── LOG1 · one log format: log-lib, FAIL-then-fix, and a ratchet (harbor#771) ─
# CONTRACTS/logging.md is the rule; this makes it binding over every shell program in bin/. A floor
# file (channel 2), a protocol row (channel 3) and the two named files below are in it by other means.
rule_LOG1() {
rule "lint.log-contract bin/ logs through log-lib.sh, every FAIL has a fix, and CONTRACTS/log-exempt.tsv only shrinks (CONTRACTS/logging.md)"
_l1t="${TMPDIR:-/tmp}/log1.$$"; rm -rf "$_l1t"; mkdir -p "$_l1t"; : > "$_l1t/msgs"; : > "$_l1t/rows"
_l1_tsv="$ROOT/CONTRACTS/log-exempt.tsv"
[ ! -f "$_l1_tsv" ] || grep -vE '^[[:space:]]*(#|$)' "$_l1_tsv" | awk -F'\t' 'NR > 1 || $1 != "path"' > "$_l1t/rows"
# The library itself, and this linter: its VIOLATION lines and summary are parsed by the lint suites
# and guard-stop, a protocol like the test harness's summary rather than a run log. fs-lib.sh prints a
# value and logs nothing: a library, like log-lib.
# alert-lib.sh is a library too: its one stderr line IS the notification, said when no desktop channel takes it.
_l1_named='bin/log-lib.sh bin/lint-conventions.sh bin/fs-lib.sh bin/alert-lib.sh'
_l1_code() { sed -e 's/^[[:space:]]*#.*$//' -e 's/[[:space:]]#.*$//' "$1"; }  # comments blanked, lines kept
_l1_uses() { _l1_code "$1" | grep -qE '(^|[;&|[:space:]])\.[[:space:]]+[^;]*log-lib\.sh'; }
_l1_floor() { # channel 2: guard-lib.sh, or F1's mark of an installed floor file
  [ "${1##*/}" = guard-lib.sh ] && return 0
  grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null | head -1 | grep -q HELM_DISABLE_FLOOR
}
# Channel 3 evidence that the harness reads a file's stdout (harbor#771): an installer composes it as a
# harness command (not in an echoed instruction), a rule pack runs it, or it builds Claude Code hook JSON.
_l1_harness() { # <rel>
  _l1h="${1##*/}"
  # A hook engine is harness-run when its manifest binds it: bin/deploy-hooks.sh renders that wiring (D-88).
  case "$1" in hooks/*/*.sh) grep -q '^wire	' "$ROOT/${1%/*}/manifest.tsv" 2>/dev/null && return 0 ;; esac
  for _l1i in "$ROOT"/bin/*install*.sh; do
    [ -f "$_l1i" ] || continue
    _l1_code "$_l1i" | grep -vE '^[[:space:]]*(echo|printf)[[:space:]]' \
      | grep -qF -e "/bin/sh \$DIR/bin/$_l1h" -e "/bin/sh \\\"\$DIR/bin/$_l1h" -e "/bin/sh \"\$DIR/bin/$_l1h" && return 0
    # The table form (harbor#766): <event>;<matcher>;<argv>;... rows in a `cat <<'ROWS'` heredoc, where
    # a bare argv word is a file in bin/. A comment row, or a row outside the table, is not a wiring.
    awk -F';' -v b="$_l1h" '/\(\) *\{ *cat <<.?ROWS.?$/ { t = 1; next } t && /^ROWS$/ { t = 0; next }
      t && $1 ~ /^[A-Z][A-Za-z]+$/ && NF >= 3 { m = split($3, a, " "); for (i = 1; i <= m; i++) if (a[i] == b) h = 1 }
      END { exit !h }' "$_l1i" && return 0
  done
  find "$ROOT/inject.d" "$ROOT/.claude/inject.d" -type f 2>/dev/null | while IFS= read -r _l1q; do
    _l1_code "$_l1q" | grep -qF -e "sh \"bin/$_l1h\"" -e "sh bin/$_l1h" && { echo y; break; }
  done | grep -q y && return 0
  _l1_code "$ROOT/$1" | grep -qE '\{[[:space:]]*\\?"?(hookSpecificOutput|systemMessage|additionalContext)\\?"?[[:space:]]*:'
}
_l1_consumer='Claude Code (statusLine|subagentStatusLine|(SessionStart|UserPromptSubmit|PreToolUse|PostToolUse|PostToolUseFailure|Stop|SubagentStart|SubagentStop|PreCompact|Notification|SessionEnd) hook)'
for _l1f in "$ROOT"/bin/* $(_engines); do
  [ -f "$_l1f" ] || continue
  case "${_l1f##*/}" in
    *.sh) ;;
    *.*) continue ;;  # .awk .mjs .py cannot source a sh library
    *) case "$(head -1 "$_l1f")" in '#!'*/sh|'#!'*' sh'|'#!'*/bash|'#!'*' bash'|'#!'*/zsh|'#!'*' zsh') ;; *) continue ;; esac ;;
  esac
  _l1p="${_l1f#"$ROOT"/}"   # the real path: a hook engine lives in hooks/<e>/ (D-88), and its log-exempt row says so
  case " $_l1_named " in *" $_l1p "*) printf '%s\tnamed\n' "$_l1p" ;; *)
    if _l1_floor "$_l1f"; then printf '%s\tfloor\n' "$_l1p"
    elif awk -F'\t' -v p="$_l1p" '$1 == p && $2 == "protocol" { f = 1 } END { exit !f }' "$_l1t/rows"; then printf '%s\tprotocol\n' "$_l1p"
    elif _l1_uses "$_l1f"; then printf '%s\tuser\n' "$_l1p"
    else printf '%s\tout\n' "$_l1p"; fi ;;
  esac
done > "$_l1t/class"

# (a) the first literal a printf or echo prints (or the argument a leading %s stands for), and a
# check mark anywhere after one. Alternation, not a bracket: a byte-wise awk reads [✓✗] as bytes.
_l1_markers() { # <file> <rel>
  _l1_code "$1" | awk -v rel="$2" '
    function judge(s) {
      if (s ~ /^[[:space:]]*(•|!!)/) return "a • or !! status mark"
      if (s ~ /^[[:space:]]*([A-Za-z0-9._-]+:[[:space:]]+)?(ERROR:|REFUSING|FAILED:)/) return "an ERROR:/REFUSING/FAILED: status prefix"
      # The words D-29 retired from a log line (CONTRACTS/logging.md, "Retired tags"), as a tag: the word, then a colon.
      # PASSWORD: and SKIPPED_COUNT= are not tags, and neither is a padded report label (`WARNING      :`) or a
      # the SKIP column of a suite listing, so the colon must follow the word directly.
      if (match(s, /^[[:space:]]*(PASS|PASSED|OK|SKIP|SKIPPED|UNCHECKED|WARNING|ERR|FATAL):/)) {
        t = substr(s, RSTART, RLENGTH); gsub(/[[:space:]:]/, "", t)
        u = (t ~ /^(PASS|PASSED|OK)$/) ? "ok" : (t ~ /^SKIP(PED)?$/) ? "skip" : (t == "UNCHECKED") ? "FAIL, its fix, exit 3" : (t == "WARNING") ? "WARN" : "FAIL"
        return "the retired tag " t ": (use " u ")"
      }
      if (s ~ /^[[:space:]]*(ok|FAIL|WARN|note|skip|fix):/) return "a TAG line"
      if (s ~ /^──/) return "a header line"
      return ""
    }
    function lit(r,   q, s, i) {
      q = substr(r, 1, 1)
      if (q == "\"" || q == "\047") { s = substr(r, 2); i = index(s, q); return i ? substr(s, 1, i - 1) : s }
      s = r; sub(/[;&|>].*$/, "", s); return s
    }
    { l = $0
      while (match(l, /(^|[^A-Za-z0-9_])(printf|echo)[[:space:]]+/)) {
        r = substr(l, RSTART + RLENGTH); l = r
        sub(/^(-[A-Za-z-]*[[:space:]]+)*/, "", r)
        why = (r ~ /(✓|✗)/) ? "a ✓/✗ status mark" : judge(lit(r))
        if (why == "" && lit(r) ~ /^[[:space:]]*%s/) { a = substr(r, length(lit(r)) + 3); sub(/^[[:space:]]+/, "", a); why = judge(lit(a)) }
        if (why != "") { printf "%s:%d: prints %s itself, around log-lib (CONTRACTS/logging.md)\n", rel, NR, why; break }
      } }'
}

# (b) after a log_fail the next log-lib call on its straight-line path is log_fix or log_nofix. A path
# that leaves first (exit, return, else, elif, a case arm, a function end) cannot print one.
_l1_fixes() { # <file> <rel>
  _l1_code "$1" | awk -v rel="$2" '
    function miss(why) { if (pend) printf "%s:%d: a FAIL with no fix line on its path — %s (log_fix <command>, or log_nofix <issue>)\n", rel, pl, why; pend = 0 }
    { l = $0; gsub(/\\./, "", l); gsub(/"[^"]*"/, "\"\"", l); gsub(/\047[^\047]*\047/, "\047\047", l)
      if (l ~ /^}/) miss("the function ends on line " NR)
      gsub(/;;/, " L1ARM ", l)
      n = split(l, T, /[[:space:];&|()]+/)
      for (i = 1; i <= n; i++) { t = T[i]
        if (t == "log_fix" || t == "log_nofix") { pend = 0; continue }
        if (t ~ /^log_(fail|ok|warn|note|skip|head|end)$/) { miss("the next log line is " t " on line " NR); if (t == "log_fail") { pend = 1; pl = NR }; continue }
        if (t == "exit" || t == "return" || t == "else" || t == "elif") miss("the path leaves at " t " on line " NR)
        if (t == "L1ARM") miss("the case arm ends on line " NR)
      } }
    END { miss("the file ends first") }'
}

# (d) a touched protocol file's stderr keeps the line shape: the first literal a printf or echo sends
# to >&2 is a header, a TAG line or the guard channel. A %s- or $var-led one cannot be judged.
_l1_stderr() { # <file> <rel>
  _l1_code "$1" | awk -v rel="$2" '
    function lit(r,   q, s, i) {
      q = substr(r, 1, 1)
      if (q == "\"" || q == "\047") { s = substr(r, 2); i = index(s, q); return i ? substr(s, 1, i - 1) : s }
      s = r; sub(/[;&|>].*$/, "", s); return s
    }
    />&2/ && match($0, /(^|[^A-Za-z0-9_])(printf|echo)[[:space:]]+/) {
      r = substr($0, RSTART + RLENGTH); sub(/^(-[A-Za-z-]*[[:space:]]+)*/, "", r); s = lit(r)
      if (r ~ /(✓|✗)/ || (s !~ /^(── |  (ok|FAIL|WARN|note|skip|fix): |HELM FLOOR \[)/ && s !~ /^[%$]/ && s != ""))
        printf "%s:%d: a stderr diagnostic outside the line shape, in a touched protocol file (CONTRACTS/logging.md)\n", rel, NR
    }'
}

# A lib sourced by a sibling that calls log_end has its summary line there (harbor#1060: ci-runners-*-lib.sh); derived from
# the source lines, never listed, so a lib nothing sources, or whose caller never ends the log, still fails.
_l1_sourced_by_ender() { # <file>
  _l1sb="${1##*/}"
  for _l1c in "$ROOT"/bin/*.sh $(_engines); do
    [ "$_l1c" != "$1" ] || continue
    _l1_code "$_l1c" | grep -qE "(^|[;&|[:space:]])\\.[[:space:]]+[^;]*/$_l1sb\"?([[:space:];]|\$)" || continue
    _l1_code "$_l1c" | grep -qE '(^|[^A-Za-z0-9_])log_end([^A-Za-z0-9_]|$)' && return 0
  done
  return 1
}

while IFS='	' read -r _l1p _l1k; do
  _l1f="$ROOT/$_l1p"
  case "$_l1k" in
    protocol)  # its stdout is the harness's, so only a log on stderr is allowed, and it keeps FAIL-then-fix
      if _l1_uses "$_l1f"; then
        _l1_code "$_l1f" | grep -q 'LOG_FD=2' || printf '%s is harness protocol output and sources log-lib.sh without LOG_FD=2 — its log would land in the protocol\n' "$_l1p" >> "$_l1t/msgs"
        _l1_fixes "$_l1f" "$_l1p" >> "$_l1t/msgs"
      fi ;;
    floor)
      _l1_uses "$_l1f" && printf '%s is a floor file (channel 2) and sources log-lib.sh — its stdout and stderr are the harness'"'"'s\n' "$_l1p" >> "$_l1t/msgs"
      _l1_markers "$_l1f" "$_l1p" >> "$_l1t/msgs" ;;
    user)
      _l1_markers "$_l1f" "$_l1p" >> "$_l1t/msgs"
      _l1_fixes "$_l1f" "$_l1p" >> "$_l1t/msgs"
      if _l1_code "$_l1f" | grep -qE '(^|[^A-Za-z0-9_])log_(ok|fail|warn|note|skip|head)([^A-Za-z0-9_]|$)' \
         && ! _l1_code "$_l1f" | grep -qE '(^|[^A-Za-z0-9_])log_end([^A-Za-z0-9_]|$)' \
         && ! _l1_sourced_by_ender "$_l1f"; then
        printf '%s prints log lines and never calls log_end — no summary line, and no exit code agreeing with one\n' "$_l1p" >> "$_l1t/msgs"
      fi ;;
  esac
done < "$_l1t/class"

# (c) the ratchet: a row may only name an unconverted shell program unchanged since the base, which is
# suite-select's (HARBOR_BASE, default origin/main, from the merge-base), compared by content.
if [ ! -f "$_l1_tsv" ]; then
  printf 'CONTRACTS/log-exempt.tsv is missing — every bin/ file outside the standard is unaccounted for\n' >> "$_l1t/msgs"
else
  _l1_mb=""
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    _l1_base="${HARBOR_BASE:-origin/main}"
    git -C "$ROOT" rev-parse --verify -q "$_l1_base^{commit}" >/dev/null 2>&1 \
      && _l1_mb="$(git -C "$ROOT" merge-base "$_l1_base" HEAD 2>/dev/null || true)"
  fi
  if [ -n "$_l1_mb" ]; then
    git -C "$ROOT" ls-tree -r "$_l1_mb" -- bin/ 2>/dev/null | awk -F'\t' '{ split($1, a, " "); print $2 "\t" a[3] }' > "$_l1t/base"
  else
    _adv lint.log-contract no-base; printf '  ADVISORY [lint.log-contract] no base (%s) to compare against — NO exempt file was checked for change\n' "${HARBOR_BASE:-origin/main}" >&2
  fi
  cut -f1 "$_l1t/rows" | sort | uniq -d | sed 's#^#CONTRACTS/log-exempt.tsv lists it twice: #' >> "$_l1t/msgs"
  while IFS='	' read -r _l1p _l1k _l1w; do
    [ -n "$_l1p" ] || continue
    case "$_l1k" in wave-B|ratchet|protocol) ;; *) printf 'CONTRACTS/log-exempt.tsv: %s has kind "%s" — wave-B, ratchet or protocol\n' "$_l1p" "$_l1k" >> "$_l1t/msgs"; continue ;; esac
    [ -n "${_l1w:-}" ] || printf 'CONTRACTS/log-exempt.tsv: %s has an empty why\n' "$_l1p" >> "$_l1t/msgs"
    if [ ! -e "$ROOT/$_l1p" ]; then  # it can exempt nothing: a file re-created here is new since the base
      _adv lint.log-contract "gone:$_l1p"; printf '  ADVISORY [lint.log-contract] CONTRACTS/log-exempt.tsv lists %s, which is gone — drop the row\n' "$_l1p" >&2; continue
    fi
    if [ "$_l1k" = protocol ]; then
      printf '%s\n' "${_l1w:-}" | grep -qE "$_l1_consumer" \
        || printf 'CONTRACTS/log-exempt.tsv: %s is a protocol row that names no consumer — say "Claude Code statusLine", or "Claude Code <Event> hook"\n' "$_l1p" >> "$_l1t/msgs"
      _l1_harness "$_l1p" \
        || printf 'CONTRACTS/log-exempt.tsv: %s is a protocol row, but nothing shows the harness reads its output — no installer runs it as a harness command, no rule pack runs it, and it builds no hook JSON\n' "$_l1p" >> "$_l1t/msgs"
    fi
    _l1c="$(awk -F'\t' -v p="$_l1p" '$1 == p { print $2 }' "$_l1t/class")"
    case "$_l1c" in
      out|protocol) ;;
      '') printf 'CONTRACTS/log-exempt.tsv lists %s, which is not a shell program in bin/ — LOG1 cannot read it\n' "$_l1p" >> "$_l1t/msgs"; continue ;;
      *) printf 'CONTRACTS/log-exempt.tsv lists %s, which already conforms (%s) — drop the row\n' "$_l1p" "$_l1c" >> "$_l1t/msgs"; continue ;;
    esac
    [ -n "$_l1_mb" ] || continue
    _l1b="$(awk -F'\t' -v p="$_l1p" '$1 == p { print $2 }' "$_l1t/base")"
    if [ "$_l1k" = protocol ]; then  # permanent: touching it never trips the ratchet, but its stderr is judged
      [ -n "$_l1b" ] && [ "$_l1b" = "$(git -C "$ROOT" hash-object -- "$_l1p" 2>/dev/null)" ] \
        || _l1_stderr "$ROOT/$_l1p" "$_l1p" >> "$_l1t/msgs"
    elif [ -z "$_l1b" ]; then
      printf '%s is new since the base, so it cannot be exempt — source bin/log-lib.sh and drop its row\n' "$_l1p" >> "$_l1t/msgs"
    elif [ "$_l1b" != "$(git -C "$ROOT" hash-object -- "$_l1p" 2>/dev/null)" ]; then
      printf '%s changed since the base and is exempt — convert it onto bin/log-lib.sh, then drop its row\n' "$_l1p" >> "$_l1t/msgs"
    fi
  done < "$_l1t/rows"
fi
awk -F'\t' 'FILENAME == ARGV[1] { row[$1] = 1; next } $2 == "out" && !($1 in row) { print $1 }' "$_l1t/rows" "$_l1t/class" \
  | sed 's#$# logs outside the standard and has no row in CONTRACTS/log-exempt.tsv — source bin/log-lib.sh#' >> "$_l1t/msgs"
while IFS= read -r _l1m; do bad lint.log-contract "$_l1m"; done < "$_l1t/msgs"
say "  $(grep -c '	user$' "$_l1t/class") on log-lib, $(grep -c '	floor$' "$_l1t/class") on the guard channel, $(grep -c '	protocol$' "$_l1t/class") harness protocol, $(grep -c . "$_l1t/rows") row(s)."
rm -rf "$_l1t"
}

# ── FL1 · a finding's lane is declared by a person, in one table, and joins (harbor#590) ──
# CONTRACTS/finding.md § Lanes holds the ONLY lane declaration. A lane is a property of the key,
# written by a person: the system never infers one at run time, because a model deciding at run
# time that a finding is safe to auto-fix is the promotion CONSTITUTION forbids. So this rule checks
# the table and nothing else can add a lane: one block, a known lane, a well-formed key that joins
# to where its rule is registered (never restated), and a HEAL row whose repair names a script that
# exists. Adding a HEAL row is the human-gated act; this rule is what makes it the only one.
rule_FL1() {
rule "audit.finding-lanes finding lanes are declared once, in CONTRACTS/finding.md, and every row joins (harbor#590)"
_fl1c="$ROOT/CONTRACTS/finding.md"
if [ ! -f "$_fl1c" ]; then
  [ ! -f "$ROOT/bin/findings.sh" ] || bad audit.finding-lanes "bin/findings.sh exists and CONTRACTS/finding.md does not — the lanes it reads are gone"
  return 0
fi
_fl1n="$(grep -c '^<!-- lanes:begin -->$' "$_fl1c" 2>/dev/null | tr -d ' ')"
[ "${_fl1n:-0}" = 1 ] || { bad audit.finding-lanes "CONTRACTS/finding.md has ${_fl1n:-0} lanes blocks — exactly one <!-- lanes:begin --> … <!-- lanes:end -->"; return 0; }
for _fl1o in "$ROOT"/CONTRACTS/*.md "$ROOT"/bin/*.sh $(_engines); do
  [ -f "$_fl1o" ] && [ "$_fl1o" != "$_fl1c" ] && [ "$_fl1o" != "$ROOT/bin/lint-conventions.sh" ] || continue
  grep -q '^<!-- lanes:begin -->$' "$_fl1o" 2>/dev/null && bad audit.finding-lanes "${_fl1o#$ROOT/} declares lanes — CONTRACTS/finding.md is the only place a lane is written"
done
_fl1ids=" $(_rule_map | cut -f2 | tr '\n' ' ') "
_fl1regf="$(mktemp "${TMPDIR:-/tmp}/fl1-register.XXXXXX")" || return 0
_registry > "$_fl1regf" 2>/dev/null || { bad audit.finding-lanes "the private layer's checks.md does not compose into the register (sh bin/check-registry-generate.sh names the line)"; cat "$ROOT/CHECKS.md" > "$_fl1regf" 2>/dev/null; }
_fl1chk=" $(sed -n 's/^| `\([a-z0-9.-]*\)` |.*/\1/p' "$_fl1regf" 2>/dev/null | tr '\n' ' ') "
rm -f "$_fl1regf"
_fl1rows="$(awk '/^<!-- lanes:begin -->$/ { t = 1; next } /^<!-- lanes:end -->$/ { t = 0 } t && /^\|/' "$_fl1c" \
  | awk -F'|' '{ for (i = 2; i < NF; i++) { f = $i; gsub(/`/, "", f); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f); $i = f }
                 if ($2 == "lane" || $2 ~ /^-+$/) next
                 printf "%s\t%s\t%s\t%s\t%s\t%d\n", $2, $3, $4, $5, $6, NF }')"
_fl1keys=""; _fl1heal=0
while IFS='	' read -r _fl1l _fl1k _fl1s _fl1r _fl1t _fl1nf; do
  [ -n "$_fl1l$_fl1k" ] || continue
  [ "$_fl1nf" = 7 ] || { bad audit.finding-lanes "lanes row for '$_fl1k' has $((_fl1nf - 2)) columns — lane | key | subject | repair | ticket"; continue; }
  case "$_fl1l" in HEAL|PROPOSE|DECIDE) ;; *) bad audit.finding-lanes "lanes row '$_fl1k' has lane '$_fl1l' — HEAL, PROPOSE or DECIDE"; continue ;; esac
  printf '%s\n' "$_fl1k" | grep -qE '^[a-z]+/[A-Za-z0-9._:-]+$' || { bad audit.finding-lanes "lanes key '$_fl1k' is malformed — <tier>/<rule>"; continue; }
  case "$_fl1keys" in *" $_fl1k "*) bad audit.finding-lanes "lanes key '$_fl1k' is declared twice"; continue ;; esac
  _fl1keys="$_fl1keys $_fl1k "
  case "$_fl1k" in
    lint/*)  case "$_fl1ids" in *" ${_fl1k#lint/} "*) ;; *)
               _fl1s2="$(_rule_map | awk -F'\t' -v l="${_fl1k#lint/}" '$3 == l { print $2 }')"
               if [ -n "$_fl1s2" ]; then bad audit.finding-lanes "lanes key '$_fl1k' names a deprecated id — its successor is lint/$_fl1s2 (D-19)"
               else bad audit.finding-lanes "lanes key '$_fl1k' names no lint rule — see sh bin/lint-conventions.sh --list"; fi ;; esac ;;
    check/*) case "$_fl1chk" in *" ${_fl1k#check/} "*) ;; *) bad audit.finding-lanes "lanes key '$_fl1k' names no CHECKS.md row" ;; esac ;;
    *)       bad audit.finding-lanes "lanes key '$_fl1k' is in a tier FL1 cannot join yet — lint/ and check/ only" ;;
  esac
  printf '%s\n' "$_fl1t" | grep -qE '^#[0-9]+$' || bad audit.finding-lanes "lanes row '$_fl1k' cites no ticket (#<n>) — '$_fl1t'"
  [ -n "$_fl1s" ] || bad audit.finding-lanes "lanes row '$_fl1k' has an empty subject — a subject, or * for every subject"
  if [ "$_fl1l" = HEAL ]; then
    _fl1heal=$((_fl1heal + 1))
    case "$_fl1r" in ''|-) bad audit.finding-lanes "HEAL row '$_fl1k' names no repair — a HEAL row is a deterministic command"; continue ;; esac
    for _fl1w in $_fl1r; do
      case "$_fl1w" in bin/*) [ -f "$ROOT/$_fl1w" ] || bad audit.finding-lanes "HEAL row '$_fl1k' repairs with $_fl1w, which does not exist" ;; esac
    done
  fi
done <<FL1ROWS
$_fl1rows
FL1ROWS
say "  $(printf '%s' "$_fl1keys" | wc -w | tr -d ' ') declared key(s), $_fl1heal in HEAL; every other key is PROPOSE."
}

# ── FL2 · every ADVISORY line carries its finding subject (harbor#590) ────────
# A line printed without `_adv` is a finding the ledger never sees: it prints in the census and the
# report says nothing about it, which is the unread block #514 measured, one layer down. Same line,
# same ID, so a reader can check the pairing without running anything.
rule_FL2() {
rule "lint.advisory-recorded every ADVISORY line in bin/lint-conventions.sh records its subject with _adv (harbor#590)"
_fl2f="$ROOT/bin/lint-conventions.sh"
[ -f "$_fl2f" ] || { say "  no bin/lint-conventions.sh under $ROOT — nothing to pair"; return 0; }
_fl2m="$(awk '/^[[:space:]]*#/ { next }
     { i = index($0, "ADVISORY [")
       if (i == 0) next
       pre = substr($0, 1, i - 1)
       if (pre !~ /(printf|echo)[[:space:]]+["\047][[:space:]]*$/) next
       id = substr($0, i + 10); id = substr(id, 1, index(id, "]") - 1)
       if (index(pre, "_adv " id " ") == 0) printf "bin/lint-conventions.sh:%d prints ADVISORY [%s] with no `_adv %s <subject>` before it on the line\n", NR, id, id
     }' "$_fl2f")"
while IFS= read -r _fl2l; do [ -z "$_fl2l" ] || bad lint.advisory-recorded "$_fl2l"; done <<FL2MSGS
$_fl2m
FL2MSGS
}

# ── lint.sibling-literals · core names no more sibling repos by path than the baseline (harbor#966) ─
# Core reaches a sibling through `roots.sh --repo <id>` (the registry), not a literal path. The count
# is derived by bin/lint-siblings.sh and may only fall; a rise is red, a fall asks for the baseline.
rule_lint_sibling_literals() {
rule "lint.sibling-literals occurrences of another repo's path in core only go down (CONTRACTS/lint-siblings-baseline.txt, harbor#966)"
if [ -f "$ROOT/bin/lint-siblings.sh" ] && [ -f "$ROOT/CONTRACTS/lint-siblings-baseline.txt" ]; then
  _sl_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-siblings.sh" --check 2>&1)" \
    || bad lint.sibling-literals "$(printf '%s' "$_sl_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.domain · core files name no more workload tools than the baseline (harbor#1274) ─
# Core holds only harbor's own logic (harbor#1149). bin/lint-domain.sh counts (core file, term) pairs over
# CONTRACTS/domain-terms.tsv minus CONTRACTS/domain-allow.tsv; the count may only fall.
rule_lint_platform_calls() {
rule "lint.platform-calls a bin/ script calls no bare macOS-only tool: ported, declared or in a helper (harbor#618)"
# The derive is bin/lint-platform.sh; tests/checks/platform-calls-test.sh is its red-proof. Approved by the operator 2026-10-20.
if [ -f "$ROOT/bin/lint-platform.sh" ]; then
  _pc_out="$(sh "$ROOT/bin/lint-platform.sh" "$ROOT/bin" 2>/dev/null)" || :
  while IFS= read -r _pcl; do
    [ -n "$_pcl" ] || continue
    bad lint.platform-calls "bin/$_pcl is a bare macOS-only call: port it beside its Linux counterpart, go through bin/alert-lib.sh for a notification, or declare \`# platform: macOS-only — <reason>\` in its first 40 lines" "bin/${_pcl%%:*}"
  done <<PLATFORM
$_pc_out
PLATFORM
fi
}

rule_lint_domain() {
rule "lint.domain core files naming a workload tool only go down (CONTRACTS/lint-domain-baseline.txt, harbor#1274)"
if [ -f "$ROOT/bin/lint-domain.sh" ] && [ -f "$ROOT/CONTRACTS/lint-domain-baseline.txt" ]; then
  _dm_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-domain.sh" --check 2>&1)" \
    || bad lint.domain "$(printf '%s' "$_dm_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
# Workload repo names too (harbor#1273), from the private registry: their own baseline, judged only where it exists.
if [ -f "$ROOT/bin/lint-domain.sh" ] && [ -f "$ROOT/CONTRACTS/lint-domain-repos-baseline.txt" ]; then
  _dr_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-domain.sh" --repos --check 2>&1)" \
    || bad lint.domain "$(printf '%s' "$_dr_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── doc.constitution-abstract · the constitution states rules, never their cases (harbor#1273) ─
# No date, ticket, absolute home path or workload repo name outside a fence; the cases are DOCTRINE/case-law.md.
rule_doc_constitution_abstract() {
rule "doc.constitution-abstract CONSTITUTION.md names no date, ticket, absolute path or workload repo (harbor#1273)"
if [ -f "$ROOT/bin/lint-constitution.sh" ] && [ -f "$ROOT/CONSTITUTION.md" ]; then
  # Green needs the summary line too: a script that died early must not read as a clean constitution.
  if ! _ca_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-constitution.sh" --check 2>&1)" \
     || ! printf '%s\n' "$_ca_out" | grep -q '^lint-constitution: [0-9]* ok, 0 failed'; then
    bad doc.constitution-abstract "$(printf '%s' "$_ca_out" | grep -E 'FAIL:|error|unexpected' | sed 's/^ *//' | tr '\n' ' ')"
  fi
fi
}

# ── lint.dev-paths · core code names no more dev-layer paths than the baseline (harbor#1275) ─
# harbor-core has no dev layer, so a core script or test that reads or writes one fails or litters the export.
# bin/lint-dev-paths.sh counts (core code file, dev path) pairs from CONTRACTS/layers.tsv; the count may only fall.
rule_lint_dev_paths() {
rule "lint.dev-paths core code naming a dev-layer path only goes down (CONTRACTS/lint-dev-paths-baseline.txt, harbor#1275)"
if [ -f "$ROOT/bin/lint-dev-paths.sh" ] && [ -f "$ROOT/CONTRACTS/lint-dev-paths-baseline.txt" ]; then
  _dp_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-dev-paths.sh" --check 2>&1)" \
    || bad lint.dev-paths "$(printf '%s' "$_dp_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.core-writes · core scripts write no more paths into the checkout than the baseline (harbor#1275) ─
# The core tree is read-only at runtime: a run's output belongs in the state directory, and an untracked file at the root of
# a harbor-core clone is one `git add -A` from a PR. bin/lint-core-writes.sh counts (script, target) pairs; the count may only fall.
rule_lint_core_writes() {
rule "lint.core-writes core scripts writing into the checkout only goes down (CONTRACTS/lint-core-writes-baseline.txt, harbor#1275)"
if [ -f "$ROOT/bin/lint-core-writes.sh" ] && [ -f "$ROOT/CONTRACTS/lint-core-writes-baseline.txt" ]; then
  _cw_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-core-writes.sh" --check 2>&1)" \
    || bad lint.core-writes "$(printf '%s' "$_cw_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.share · every file of a known kind lives in a share its kind allows (block, harbor#1274) ─
# D-83: a file's share comes from where it lives and must be in its kind's set in kinds.tsv. bin/lint-share.sh judges it;
# each finding is a violation since the tree reached zero. CI has no private layer, so only the checkout is judged there.
rule_lint_share() {
rule "lint.share every file of a known kind lives in a share its kind allows (harbor#1274)"
if [ -f "$ROOT/bin/lint-share.sh" ]; then
  _sh_o="${TMPDIR:-/tmp}/lsh.$$"; _sh_rc=0
  HARBOR_ROOT="$ROOT" HARBOR_SCOPE_PRIVATE="${TMPDIR:-/tmp}/lint-share-no-private" sh "$ROOT/bin/lint-share.sh" --check > "$_sh_o" 2>&1 || _sh_rc=$?
  if [ "$_sh_rc" -ne 0 ]; then
    bad lint.share "bin/lint-share.sh exited $_sh_rc and judged nothing: $(grep -m1 'FAIL:\|lint-share:' "$_sh_o" | sed 's/^ *//')"
  else
    _sh_n=0
    while IFS= read -r _sh_l; do
      case "$_sh_l" in
        '  WARN: [lint.share] '*) _sh_n=$((_sh_n + 1)); bad lint.share "${_sh_l#*] }" ;;
      esac
    done < "$_sh_o"
    [ "$_sh_n" -gt 0 ] || say "  $(grep -m1 ' ok: ' "$_sh_o" | sed -E 's/^ *ok: //')"
  fi
  rm -f "$_sh_o"
fi
}

# ── lint.layout-map · every tracked top-level entry has a kind and a layer in the map (harbor#1272) ─
# bin/lint-layout-map.sh is red on an entry with no row in CONTRACTS/layout-map.tsv and on a row naming no entry.
rule_lint_layout_map() {
rule "lint.layout-map every tracked top-level entry is in CONTRACTS/layout-map.tsv with a kind and a layer (harbor#1272)"
if [ -f "$ROOT/bin/lint-layout-map.sh" ] && [ -f "$ROOT/CONTRACTS/layout-map.tsv" ]; then
  _lm_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-layout-map.sh" --check 2>&1)" \
    || bad lint.layout-map "$(printf '%s' "$_lm_out" | grep -E 'FAIL:|fix:' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.frozen-names · a name a stranger types never vanishes without an alias (harbor#1276) ─
# bin/frozen-gen.sh is red on a name not yet in standards/naming/frozen.tsv and on a frozen one gone from its source
# with no renames.tsv row carrying its alias.
rule_lint_frozen_names() {
rule "lint.frozen-names every CLI family, toml key, env root, core skill and guard rule id is frozen, and a rename keeps an alias (harbor#1276)"
if [ -f "$ROOT/bin/frozen-gen.sh" ] && [ -f "$ROOT/standards/naming/frozen.tsv" ]; then
  _fz_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/frozen-gen.sh" --check 2>&1)" \
    || bad lint.frozen-names "$(printf '%s' "$_fz_out" | grep -E 'FAIL:|fix:' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.leaks · the tree names no more clients, companies or accounts than the baseline (harbor#1149) ─
# bin/lint-leaks.sh counts the generic patterns of CONTRACTS/leak-patterns.tsv. CI has no private layer, so
# only the core count is judged here (HARBOR_SCOPE_PRIVATE is emptied); the private count is a local --check.
rule_lint_leaks() {
rule "lint.leaks occurrences of a leak-gate core pattern in the tree only go down (CONTRACTS/lint-leaks-baseline.txt, harbor#1149)"
if [ -f "$ROOT/bin/lint-leaks.sh" ] && [ -f "$ROOT/CONTRACTS/lint-leaks-baseline.txt" ]; then
  _lk_out="$(HARBOR_ROOT="$ROOT" HARBOR_SCOPE_PRIVATE="${TMPDIR:-/tmp}/lint-leaks-no-private" sh "$ROOT/bin/lint-leaks.sh" --check 2>&1)" \
    || bad lint.leaks "$(printf '%s' "$_lk_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.credential-reads · no more credential reads outside bin/secret than the baseline (harbor#1205) ─
# A credential reaches code through bin/secret and a register entry (CONTRACTS/access-register.md). The count is
# derived by bin/lint-secrets.sh (a literal value, a direct keychain call, an env token read) and may only fall.
rule_lint_credential_reads() {
rule "lint.credential-reads credential reads outside bin/secret only go down (CONTRACTS/lint-secrets-baseline.txt, harbor#1205)"
if [ -f "$ROOT/bin/lint-secrets.sh" ] && [ -f "$ROOT/CONTRACTS/lint-secrets-baseline.txt" ]; then
  _cr_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-secrets.sh" --check 2>&1)" \
    || bad lint.credential-reads "$(printf '%s' "$_cr_out" | grep -E 'FAIL:|fix:|changed and' | sed 's/^ *//' | tr '\n' ' ')"
fi
}

# ── lint.locale-ranges · no sh case pattern holds a range that follows the locale (harbor#1149) ─
# A bracket range in a shell `case` pattern follows the locale's collation: on the operator's Mac (en_NZ.UTF-8,
# /bin/sh is bash) `[!a-z0-9-]` lets capitals through, `[A-Z]` matches most lowercase letters and `[!!-~]` rejects
# ordinary ASCII, while dash on the CI runner (C locale) reads them as ASCII. Proven three times on 2026-10-12.
# bin/lint-locale-ranges.awk finds them; a bracket holding a letter range and its other-case twin (`[!A-Za-z0-9_-]`)
# is clean. awk, grep, sed, tr and jq regexes are other engines and are not judged here.
rule_lint_locale_ranges() {
rule "lint.locale-ranges no sh case pattern holds a single-case letter range or a punctuation range (harbor#1149)"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  _adv lint.locale-ranges not-a-checkout; printf '  ADVISORY [lint.locale-ranges] %s is not a git checkout — NO file was inspected\n' "$ROOT" >&2
elif [ ! -f "$ROOT/bin/lint-locale-ranges.awk" ]; then
  bad lint.locale-ranges "bin/lint-locale-ranges.awk is missing, so no case pattern was inspected"
else
  _lr_list="${TMPDIR:-/tmp}/harbor-lr.$$"
  # sh candidates: *.sh, or a name with no extension (the awk keeps those whose shebang is a sh); to files, not pipes (bad in a subshell is lost)
  git -C "$ROOT" ls-files | while IFS= read -r _lr_f; do
    case "${_lr_f##*/}" in *.sh) printf '%s\n' "$_lr_f" ;; *.*) ;; *) printf '%s\n' "$_lr_f" ;; esac
  done > "$_lr_list.files"
  ( cd "$ROOT" && tr '\n' '\0' < "$_lr_list.files" | xargs -0 env LC_ALL=C awk -f bin/lint-locale-ranges.awk ) > "$_lr_list" 2>/dev/null \
    || bad lint.locale-ranges "the scan exited non-zero — NO file was fully inspected, and this is not a pass"
  _lr_prev=
  while IFS="$(printf '\t')" read -r _lr_f _lr_n _lr_i _lr_j _lr_b; do
    [ "$_lr_f:$_lr_n" != "$_lr_prev" ] || continue
    _lr_prev="$_lr_f:$_lr_n"
    bad lint.locale-ranges "$_lr_f:$_lr_n case pattern $_lr_b ranges follow the locale, not ASCII (en_NZ: [!a-z] passes capitals) — fix: spell the letters out ([!abcdefghijklmnopqrstuvwxyz0-9]), or use LC_ALL=C tr -d for a punctuation range" "$_lr_f"
  done < "$_lr_list"
  rm -f "$_lr_list" "$_lr_list.files"
fi
}

# ── lint.comment-commands · no destructive command in backticks in a shell comment ─
# sh reads a script as it runs. A script rewritten in place under a running shell resumes mid-line, and from
# anywhere before a backtick span the span is a command substitution: on 2026-10-15 two quoted examples in
# guard-bash.sh comments ran that way (a recursive chmod 000 from the root). Quote examples with ' instead —
# a resume must then land exactly on the verb. Installs rename (il_install_exec); this covers the dev tree.
rule_lint_comment_commands() {
rule "lint.comment-commands no shell comment quotes a destructive command in backticks"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  _adv lint.comment-commands not-a-checkout; printf '  ADVISORY [lint.comment-commands] %s is not a git checkout — NO file was inspected\n' "$ROOT" >&2
elif [ ! -f "$ROOT/bin/lint-comment-commands.awk" ]; then
  bad lint.comment-commands "bin/lint-comment-commands.awk is missing, so no comment was inspected"
else
  _cc_list="${TMPDIR:-/tmp}/harbor-cc.$$"
  git -C "$ROOT" ls-files | while IFS= read -r _cc_f; do
    case "${_cc_f##*/}" in *.sh) printf '%s\n' "$_cc_f" ;; *.*) ;; *) printf '%s\n' "$_cc_f" ;; esac
  done > "$_cc_list.files"
  ( cd "$ROOT" && tr '\n' '\0' < "$_cc_list.files" | xargs -0 env LC_ALL=C awk -f bin/lint-comment-commands.awk ) > "$_cc_list" 2>/dev/null \
    || bad lint.comment-commands "the scan exited non-zero — NO file was fully inspected, and this is not a pass"
  while IFS="$(printf '\t')" read -r _cc_f _cc_n _cc_s; do
    bad lint.comment-commands "$_cc_f:$_cc_n comment quotes $_cc_s in backticks, which a shell resuming mid-line runs — fix: quote it with ' instead (with \" inside a single-quoted program, such as an awk body)" "$_cc_f"
  done < "$_cc_list"
  rm -f "$_cc_list" "$_cc_list.files"
fi
}

# ── standard.decision-dangling / standard.decision-orphan · the decision citations (harbor#1029) ─
# A decision is cited as D-<n>; its record is docs/decisions/NNNN-*.md, whose `alias:` line is D-<n>.
# A citation with no record is an authority nobody can read; a record nothing cites is a decision the
# tree does not act on. Citations are judged over tracked text, vendor/ excluded (third-party, not ours).
# A record's own text does not cite, so its `alias:` and `revised_by:` lines count only for dangling, and
# docs/index.html, whose decision table quotes every record, is excluded: built, untracked here since harbor#1197,
# but tracked in the exported core (bin/deploy-push.sh:82), where it would make every record cited.
# CONTRACTS/decision-orphans.tsv is the deliberate-orphan allow-list: one id per row, and a row that is
# cited or names no record is itself red. Output: `path TAB line TAB D-n`, one row per citation.
_decision_cites() {
  git -C "$ROOT" grep -InE '(^|[^A-Za-z0-9_-])D-[0-9]+([^0-9A-Za-z]|$)' -- . ':(exclude)vendor' ':(exclude)CONTRACTS/decision-orphans.tsv' ':(exclude)docs/index.html' 2>/dev/null \
    | LC_ALL=C awk '{
        p = $0; i = index(p, ":"); path = substr(p, 1, i - 1); rest = substr(p, i + 1)
        j = index(rest, ":"); ln = substr(rest, 1, j - 1); txt = substr(rest, j + 1)
        while (match(txt, /(^|[^A-Za-z0-9_-])D-[0-9]+([^0-9A-Za-z]|$)/)) {
          s = substr(txt, RSTART, RLENGTH)
          if (match(s, /D-[0-9]+/)) printf "%s\t%s\t%s\n", path, ln, substr(s, RSTART, RLENGTH)
          txt = substr(txt, RSTART + RLENGTH) } }'
}
# `alias TAB path` for each record: the first `alias: D-<n>` line of a docs/decisions/NNNN-*.md.
_decision_records() {
  for _dr_f in "$ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$_dr_f" ] || continue
    _dr_a="$(awk 'NR > 12 { exit } /^alias: *D-[0-9]+ *$/ { sub(/^alias: */, ""); sub(/ *$/, ""); print; exit }' "$_dr_f")"
    printf '%s\t%s\n' "$_dr_a" "${_dr_f#"$ROOT"/}"
  done
}

rule_standard_decision_dangling() {
rule "standard.decision-dangling every D-n cited in the tree resolves to a decision record (docs/decisions/, harbor#1029)"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  bad standard.decision-dangling "$ROOT is not a git checkout, so no citation was judged"; return 0
fi
_dd="${TMPDIR:-/tmp}/dd.$$"
_decision_records > "$_dd.recs"; _decision_cites > "$_dd.cites"
LC_ALL=C awk -F'\t' 'NR == FNR { known[$1] = 1; next }
  !($3 in known) { printf "%s\t%s\n", $1, $3 }' "$_dd.recs" "$_dd.cites" > "$_dd.out"
while IFS="$(printf '\t')" read -r _ddp _ddi; do
  [ -n "$_ddp" ] || continue
  bad standard.decision-dangling "$_ddp cites $_ddi, which no record in docs/decisions/ defines" "$_ddp"
done < "$_dd.out"
rm -f "$_dd.recs" "$_dd.cites" "$_dd.out"
}

rule_standard_decision_orphan() {
rule "standard.decision-orphan every decision record is cited outside docs/decisions/, or allow-listed in CONTRACTS/decision-orphans.tsv (harbor#1029)"
if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  bad standard.decision-orphan "$ROOT is not a git checkout, so no record was judged"; return 0
fi
_do="${TMPDIR:-/tmp}/do.$$"
_decision_records > "$_do.recs"; _decision_cites > "$_do.cites"
LC_ALL=C awk -F'\t' '$1 !~ /^docs\/decisions\// { print $3 }' "$_do.cites" | LC_ALL=C sort -u > "$_do.cited"
if [ -f "$ROOT/CONTRACTS/decision-orphans.tsv" ]; then
  awk -F'\t' '!/^#/ && NF { print $1 }' "$ROOT/CONTRACTS/decision-orphans.tsv" | LC_ALL=C sort -u > "$_do.allow"
  _do_al="CONTRACTS/decision-orphans.tsv"
else
  : > "$_do.allow"; _do_al="CONTRACTS/decision-orphans.tsv (absent)"
fi
LC_ALL=C awk -F'\t' -v al="$_do_al" '
  FILENAME == ARGV[1] { cited[$1] = 1; next }
  FILENAME == ARGV[2] { allow[$1] = 1; next }
  { rec[$1] = $2 }
  END {
    for (a in rec) {
      if (!(a in cited) && !(a in allow)) printf "%s\t%s\tuncited: %s is cited nowhere outside docs/decisions/, and %s does not allow it\n", rec[a], a, a, al
      if ((a in cited) && (a in allow)) printf "%s\t%s\tstale allow-list row: %s is cited, so %s should not list it\n", al, a, a, al
    }
    for (a in allow) if (!(a in rec)) printf "%s\t%s\tallow-list row for %s, which no record defines\n", al, a, a
  }' "$_do.cited" "$_do.allow" "$_do.recs" | LC_ALL=C sort > "$_do.out"
while IFS="$(printf '\t')" read -r _dop _doi _dom; do
  [ -n "$_dop" ] || continue
  bad standard.decision-orphan "$_dop: $_dom" "$_dop"
done < "$_do.out"
rm -f "$_do.recs" "$_do.cites" "$_do.cited" "$_do.allow" "$_do.out"
}

# ── event.kind-registered · the event bus has one register of kinds, and nothing waits on silence ──
# The presets event.pulse and event.fleet-snapshot listened for ci.job.done while nothing emitted it, and pr.merged had
# no producer either: the kinds were a prose table, and no rule could say a listener waits on a kind nobody emits
# (harbor#1367). CONTRACTS/event-kinds.tsv is the register; this holds it to the code in both directions.
rule_event_kind_registered() {
rule "event.kind-registered every event kind is a row of CONTRACTS/event-kinds.tsv, its emitter names it, and no preset waits on a kind nothing emits (harbor#1367)"
_ekf="$ROOT/CONTRACTS/event-kinds.tsv"
[ -f "$_ekf" ] || { bad event.kind-registered "CONTRACTS/event-kinds.tsv is missing: the register of event kinds"; return 0; }
_ek="${TMPDIR:-/tmp}/ek.$$"
awk -F'\t' '!/^#/ && NF && $1 != "kind" { print $1 "\t" $4 }' "$_ekf" > "$_ek.reg"
cut -f1 "$_ek.reg" | LC_ALL=C sort -u > "$_ek.kinds"
# The row names a file that emits it, and that file names the kind: a register row with no producer is the defect.
while IFS="$(printf '\t')" read -r _ekk _eke; do
  [ -n "$_ekk" ] && [ "$_eke" != - ] || continue
  for _ekp in $_eke; do
    if [ ! -f "$ROOT/$_ekp" ]; then bad event.kind-registered "$_ekk: its emitter $_ekp does not exist" "CONTRACTS/event-kinds.tsv"
    elif ! grep -Fq -- "$_ekk" "$ROOT/$_ekp"; then bad event.kind-registered "$_ekk: its emitter $_ekp never names it" "$_ekp"; fi
  done
done < "$_ek.reg"
# Every kind the code emits by name is registered.
{ find "$ROOT/bin" "$ROOT/hooks" -type f \( -name '*.sh' -o ! -name '*.*' \) 2>/dev/null || :; } | while IFS= read -r _ekf2; do
  # A word of its own: harbor_emit (stream-lib.sh) writes a telemetry stream, not a bus event.
  grep -oE '(^|[^A-Za-z0-9_])(emit|emit_event|hook_event) "?[a-z][a-z0-9_-]*(\.[a-z0-9_-]+)+' "$_ekf2" 2>/dev/null \
    | sed -E 's/^[^a-z]*//; s/^[a-z_]+ "?//' | while IFS= read -r _ekk; do
        grep -Fxq -- "$_ekk" "$_ek.kinds" || printf '%s\t%s\n' "${_ekf2#"$ROOT"/}" "$_ekk"
      done
done | LC_ALL=C sort -u > "$_ek.emitted"
while IFS="$(printf '\t')" read -r _ekp _ekk; do
  [ -n "$_ekk" ] && bad event.kind-registered "$_ekp emits $_ekk, which CONTRACTS/event-kinds.tsv does not register" "$_ekp"
done < "$_ek.emitted"
# Every kind a preset or an obligation names is registered, and a preset never listens for a kind nothing emits.
_ek_kinds_of() { # <pattern> → one kind per line: `"kind":"(a\.b|c\.d)"` or `a\.b|c\.d`
  printf '%s\n' "$1" | sed -e 's/.*"kind":"//' -e 's/".*//' -e 's/[()]//g' -e 's/\\//g' | tr '|' '\n' | grep -E '^[a-z][a-z0-9_.-]*$' || :
}
# The pipes below run in subshells, so findings go to a file and bad() runs in this shell.
for _ekt in event-rules obligation-kinds; do
  [ -f "$ROOT/CONTRACTS/$_ekt.tsv" ] || continue
  awk -F'\t' -v t="$_ekt" '!/^#/ && NF && $1 != "kind" { if (t == "event-rules") print $1 "\t" $2; else { print $1 "\t" $2; print $1 "\t" $3 } }' \
    "$ROOT/CONTRACTS/$_ekt.tsv" | while IFS="$(printf '\t')" read -r _ekid _ekpat; do
      [ "$_ekpat" != - ] || continue
      _ek_kinds_of "$_ekpat" | while IFS= read -r _ekk; do
        if ! grep -Fxq -- "$_ekk" "$_ek.kinds"; then
          printf 'CONTRACTS/%s.tsv\tCONTRACTS/%s.tsv %s names %s, which CONTRACTS/event-kinds.tsv does not register\n' "$_ekt" "$_ekt" "$_ekid" "$_ekk"
        elif [ "$_ekt" = event-rules ] && [ "$(awk -F'\t' -v k="$_ekk" '$1 == k { print $2; exit }' "$_ek.reg")" = - ]; then
          printf 'CONTRACTS/event-rules.tsv\tCONTRACTS/event-rules.tsv %s listens for %s, which nothing on this box emits\n' "$_ekid" "$_ekk"
        fi
      done
    done
done | LC_ALL=C sort -u > "$_ek.refs"
while IFS="$(printf '\t')" read -r _ekp _ekm; do
  [ -n "$_ekm" ] && bad event.kind-registered "$_ekm" "$_ekp"
done < "$_ek.refs"
rm -f "$_ek.reg" "$_ek.kinds" "$_ek.emitted" "$_ek.refs"
}

# ── skill.description-shape · an authored skill's description has one shape (harbor#1010, warn) ──
# The catalog (bin/skill-catalog.sh) renders `USE WHEN` as the trigger index and `NOT FOR` as the sibling disambiguator, and
# for a hidden skill that clause is the only place a reader sees it. So a skill under skills/ carries both, `USE WHEN` first,
# and declares its visibility with ONE key: `disable-model-invocation` and `user-invocable` together say two things about one
# fact, and a repeated key is read by whichever parser comes last. Vendored skills keep their upstream shape (vendor/skills/).
# Advisory (warn): a person promotes it in controls.tsv after the 4-week record (standards/naming.md 10.3).
rule_skill_description_shape() {
rule "skill.description-shape an authored skill's description carries USE WHEN then NOT FOR, and its frontmatter has at most one visibility key (warn, harbor#1010)"
for _ds_d in "$ROOT"/skills/*/; do
  [ -f "$_ds_d/SKILL.md" ] || continue
  _ds_n="$(basename "$_ds_d")"
  _ds_fm="$(awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit } NR>1 && $0 ~ /^---[[:space:]]*$/ { exit } NR>1' "$_ds_d/SKILL.md")"
  _ds_desc="$(printf '%s\n' "$_ds_fm" | awk '/^description:[[:space:]]*/ { sub(/^description:[[:space:]]*/, ""); print; exit }')"
  case "$_ds_desc" in
    '') _adv skill.description-shape "skills/$_ds_n"; printf '  ADVISORY [skill.description-shape] skills/%s has no one-line description (a folded block or none)\n' "$_ds_n" >&2 ;;
    *"USE WHEN"*"NOT FOR"*) : ;;
    *"NOT FOR"*"USE WHEN"*) _adv skill.description-shape "skills/$_ds_n"; printf '  ADVISORY [skill.description-shape] skills/%s puts NOT FOR before USE WHEN\n' "$_ds_n" >&2 ;;
    *) _adv skill.description-shape "skills/$_ds_n"; printf '  ADVISORY [skill.description-shape] skills/%s description lacks a USE WHEN or a NOT FOR clause\n' "$_ds_n" >&2 ;;
  esac
  _ds_v="$(printf '%s\n' "$_ds_fm" | grep -cE '^(disable-model-invocation|user-invocable):' || :)"
  if [ "${_ds_v:-0}" -gt 1 ]; then
    _adv skill.description-shape "skills/$_ds_n"; printf '  ADVISORY [skill.description-shape] skills/%s declares %s visibility keys; keep one (disable-model-invocation)\n' "$_ds_n" "$_ds_v" >&2
  fi
done
}

# ── skill.cited-path-exists · a repo path a description cites resolves (harbor#1010, warn) ──
# A description is what a session reads when it cannot open the skill, so a `bin/x.sh` that no longer exists sends it to a
# dead end with confidence. Only a backticked token that is a plain repo-relative path is judged: `~/...`, absolute paths,
# globs, URLs and `<placeholders>` name the box or a pattern, which a CI checkout cannot resolve. Skills under skills/ only.
rule_skill_cited_path_exists() {
rule "skill.cited-path-exists a backticked repo path in an authored skill's description exists in the tree (warn, harbor#1010)"
for _cp_d in "$ROOT"/skills/*/; do
  [ -f "$_cp_d/SKILL.md" ] || continue
  _cp_n="$(basename "$_cp_d")"
  awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit } NR>1 && $0 ~ /^---[[:space:]]*$/ { exit } NR>1' "$_cp_d/SKILL.md" \
    | awk '/^description:[[:space:]]*/ { print; exit }' | grep -oE '`[^`[:space:]]+/[^`[:space:]]*`' | tr -d '`' \
    | while IFS= read -r _cp_t; do
        case "$_cp_t" in '~'*|/*|*'*'*|*'<'*|*'$'*|*://*|*'{'*) continue ;; esac
        [ -e "$ROOT/${_cp_t%/}" ] && continue
        _adv skill.cited-path-exists "skills/$_cp_n"; printf '  ADVISORY [skill.cited-path-exists] skills/%s cites %s, which is not in the tree\n' "$_cp_n" "$_cp_t" >&2
      done
done
}

# ── drift.skill-manifest · every installed skill has a manifest row (harbor#1010, warn) ──
# bin/skill-catalog.sh install --manifest answers it for one config dir: an installed skill no manifest records (hand-installed,
# or an installer that did not write its row), or a row whose skill is gone. Advisory, and silent where it cannot judge: a CI
# checkout has no installed skills dir or no manifest, and "could not look" is the generator's exit 3, never an advisory.
rule_drift_skill_manifest() {
rule "drift.skill-manifest every skill installed in the config dir has a row in .harbor-manifest or a pack's manifest, and every skill row an installed skill (advisory, harbor#1010)"
_sm_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
if [ -f "$ROOT/bin/skill-catalog.sh" ] && [ -d "$_sm_cfg/skills" ] && [ -f "$_sm_cfg/.harbor-manifest" ]; then
  if [ "$(CDPATH='' cd -P -- "$_sm_cfg" 2>/dev/null && pwd -P)" = "$(CDPATH='' cd -P -- "$HOME/.claude" 2>/dev/null && pwd -P)" ]; then _sm_sp="--live"; else _sm_sp="--dir $_sm_cfg"; fi
  # shellcheck disable=SC2086  # the target spelling is two words or one
  _sm_out="$(HARBOR_ROOT="$ROOT" sh "$ROOT/bin/skill-catalog.sh" install --manifest $_sm_sp 2>&1)"; _sm_rc=$?
  case "$_sm_rc" in
    0|3) ;;
    *) printf '%s\n' "$_sm_out" | sed -n 's/^ *FAIL: //p' | while IFS= read -r _sm_l; do
         _adv drift.skill-manifest "$_sm_l"; printf '  ADVISORY [drift.skill-manifest] %s\n' "$_sm_l" >&2
       done ;;
  esac
fi
}

# ── the dispatcher ───────────────────────────────────────────────────────────
# THE ORDER IS DERIVED, NOT DECLARED (harbor#537, DOCTRINE/doc-truth.md). A
# hand-written registry of 78 ids is a copy, and a copy that drops one entry
# silently stops running that rule while the summary still says "78 rules". The
# source is the only thing that cannot disagree with itself, so the list comes
# out of $0 — which is the same trick --list has used since harbor#117.
# `--only` takes the id or its deprecated letter (harbor#957), and resolves to ONE function: an
# argument two rules answer to is refused, never run twice — lint.id-one-meaning names the pair.
_rule_fns="$(_rule_map | awk -F'\t' '{ print $1 ":" $2 }')"
if [ -n "$ONLY" ]; then
  _only_fn="$(_rule_map | awk -F'\t' -v o="$ONLY" '$2 == o || $3 == o { print $1 }')"
  case "$_only_fn" in
    '') printf 'lint-conventions: no such rule: %s (see --list, --ids)\n' "$ONLY" >&2; exit 2 ;;
    *'
'*) printf 'lint-conventions: %s names more than one rule: %s\n' "$ONLY" "$(printf '%s' "$_only_fn" | tr '\n' ' ')" >&2; exit 2 ;;
  esac
fi
for _rp in $_rule_fns; do
  _rfn="${_rp%%:*}"; _rid="${_rp#*:}"
  if [ -n "$ONLY" ] && [ "$_only_fn" != "$_rfn" ]; then continue; fi
  _rf0=$FAIL
  "rule_$_rfn"
  # A rule that counts its own failures without bad() (T2, D5, H1, N2) still went red: the red log
  # reads the FAIL count, not only the bad() calls (harbor#577). It records the id, never the letter.
  [ -z "${LINT_REDLOG:-}" ] || [ "$FAIL" -eq "$_rf0" ] || printf '%s\n' "$_rid" >> "$LINT_REDLOG" 2>/dev/null || :
done

say ""
say "════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
  printf 'lint-conventions: %d rules, 0 violations\n' "$RULES"
  exit 0
fi
printf 'lint-conventions: %d rules, %d violation(s)\n' "$RULES" "$FAIL"
exit 1
