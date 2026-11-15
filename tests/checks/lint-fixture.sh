# tests/checks/lint-fixture.sh — what the lint-conventions suites share (harbor#3, harbor#667).
# Source after t_init. Each arm asks ONE rule (--only) about a root holding what it reads (#531),
# and t_init's sandbox config dir keeps X8/T9/X4 off the live skills dir (F4's hermeticity).
LINT="$T_ROOT/bin/lint-conventions.sh"; SRC="$T_ROOT/bin"; ROOT="$T_ROOT"; TMP="$T_TMP/lint"
mkdir -p "$TMP" "$CLAUDE_CONFIG_DIR/skills" "$CLAUDE_CONFIG_DIR/bin" "$CLAUDE_CONFIG_DIR/commands"
lint1() { HARBOR_SCOPE_ROOT="$2" sh "$LINT" --only "$1" 2>&1; }  # <ID> <root> → the rule's whole output
# The lint prints a rule's <family>.<slug> id; an arm may still ask by its deprecated letter (harbor#957).
LINT_IDS="$TMP/lint-ids.tsv"; sh "$LINT" --ids > "$LINT_IDS"
lid() { awk -F'\t' -v k="$1" 'NR > 1 && ($1 == k || $2 == k) { print $1; f = 1; exit } END { if (!f) print k }' "$LINT_IDS"; }
viol() { lint1 "$1" "$2" | grep -F "VIOLATION [$(lid "$1")]"; }   # <ID> <root> → its VIOLATION lines
advs() { lint1 "$1" "$2" | grep -F "ADVISORY [$(lid "$1")]"; }    # <ID> <root> → its ADVISORY lines
vcount() { printf '%s\n' "$1" | sed -n 's/^lint-conventions: [0-9]* rules, \([0-9]*\) violation.*/\1/p'; }
hasre() { printf '%s\n' "$1" | grep -q -- "$2" && echo yes || echo no; }  # <text> <BRE>: ordered needles
nonempty() { [ -n "$1" ] && echo yes || echo no; }
DEAD='cites a path that does not exist:'  # T3 and K1 name a dead citation with this wording
