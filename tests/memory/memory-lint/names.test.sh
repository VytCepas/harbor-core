#!/usr/bin/env sh
# memory-lint.sh name checks and the notes-store default (harbor#1010 PR 4; D-24 claim-style, D-34 host alias):
# a clean store is silent, each NAME-* kind goes red on its own fixture, names are report-only until --strict-names,
# and memory / memory-lint read projects/<home-key>/memory when it exists.
. "$(dirname "$0")/../../lib/core.sh"; t_init
LINT="$T_ROOT/bin/memory-lint.sh"; MEM="$T_ROOT/bin/memory.sh"
S="$T_TMP/store"
note() { mkdir -p "$(dirname "$1")"; printf -- '---\nname: %s\n---\nanswers body\n' "${2:-x}" > "$1"; }
mk() { rm -rf "$S"; mkdir -p "$S"; note "$S/stores-reject-claims-with-no-subject.md" stores-reject-claims-with-no-subject
  note "$S/sub-dir/another-claim-here.md" another-claim-here; printf '# index\n' > "$S/MEMORY.md"; }
names() { HARBOR_MEMORY_HOST_NAMES="Boxy-MacBook" sh "$LINT" --root "$S" --names "$@" 2>/dev/null; }

t_section "a clean store has no name finding"
mk; out="$(names; echo end)"; t_hasnt "no NAME line" "$out" "NAME-"
mk; t_exit "strict-names green" 0 env HARBOR_MEMORY_HOST_NAMES=Boxy-MacBook sh "$LINT" --root "$S" --strict-names

t_section "each kind goes red on its own fixture (the red proof)"
mk; note "$S/Feedback_Thing.md" Feedback_Thing
t_has "uppercase / underscore is not claim-style" "$(names)" "NAME-CLAIM Feedback_Thing.md"
mk; note "$S/singleword.md" singleword
t_has "one word has no claim" "$(names)" "one word is a subject with no claim"
mk; note "$S/Up-Dir/some-claim-here.md" some-claim-here
t_has "an uppercase subfolder" "$(names)" 'subfolder "Up-Dir" is not lowercase kebab'
mk; note "$S/some-claim-here.md" different-name
t_has "name differs from stem" "$(names)" 'front matter name "different-name" differs'
mk; note "$S/Boxy-MacBook/some-claim-here.md" some-claim-here
t_has "a raw machine name" "$(names)" 'is a raw machine name'
mk; note "$S/boxy-macbook/some-claim-here.md" some-claim-here
t_hasnt "the lowercase alias is fine for the host check" "$(names; echo end)" "raw machine name"

t_section "off without --names, report-only unless --strict-names"
mk; note "$S/Feedback_Thing.md" Feedback_Thing
t_hasnt "no flag, no name judgement" "$(HARBOR_MEMORY_HOST_NAMES=Boxy-MacBook sh "$LINT" --root "$S" 2>/dev/null; echo end)" "NAME-"
mk; note "$S/Feedback_Thing.md" Feedback_Thing
t_exit "--names exits 0" 0 env HARBOR_MEMORY_HOST_NAMES=Boxy-MacBook sh "$LINT" --root "$S" --names
t_exit "--strict-names exits 1" 1 env HARBOR_MEMORY_HOST_NAMES=Boxy-MacBook sh "$LINT" --root "$S" --strict-names
t_has "json carries the finding" "$(names --json)" '"kind":"NAME-CLAIM"'

t_section "the default store is the notes store"
H="$T_TMP/home"; K="$(CDPATH= cd -- "$H" && pwd -P | sed 's|/|-|g')"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/$K/memory" "$CLAUDE_CONFIG_DIR/MEMORY"
note "$CLAUDE_CONFIG_DIR/projects/$K/memory/notes-store-answers-first.md" notes-store-answers-first
note "$CLAUDE_CONFIG_DIR/MEMORY/old-tree-answers-second.md" old-tree-answers-second
t_has "memory reads the notes store" "$(sh "$MEM" --json answers 2>/dev/null)" "notes-store-answers-first"
t_hasnt "and not the old tree" "$(sh "$MEM" --json answers 2>/dev/null)" "old-tree-answers-second"
t_has "lint reads it too" "$(sh "$LINT" 2>&1)" "projects/$K/memory"
rm -rf "$CLAUDE_CONFIG_DIR/projects"
t_has "no notes store falls back to the old tree" "$(sh "$MEM" --json answers 2>/dev/null)" "old-tree-answers-second"
t_done
