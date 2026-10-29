#!/usr/bin/env sh
# doc-isa-index.sh, the ISA pointer table (harbor#117, F1). No ISA run exists on the box, so its
# real output is an empty table: the fixtures manufacture the runs the tool has never seen.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/doc-isa-index.sh"; STORE="$T_TMP/WORK"; OUT="$T_TMP/isa-index.md"
mkdir -p "$STORE"
run() { HARBOR_ISA_STORE="$STORE" HARBOR_ISA_OUT="$OUT" CLAUDE_CONFIG_DIR="$T_TMP" sh "$TOOL" "$@" > "$T_TMP/out" 2>&1; }

t_section "an empty or absent store is a result, not a crash"
run; t_eq "an empty store: exit" 0 "$?"
t_has "an empty store gives an honest empty index" "$(cat "$OUT")" 'Empty is a result'
t_exit "an absent store reports zero" 0 env HARBOR_ISA_STORE="$T_TMP/nope" HARBOR_ISA_OUT="$OUT" sh "$TOOL"

t_section "a run is indexed by reference, from its own frontmatter and body"
ISA="$STORE/20260201-090000_beanline-v1/ISA.md"; mkdir -p "$(dirname "$ISA")"
cat > "$ISA" <<'EOF'
---
task: "Build BeanLine"
slug: 20260201-090000_beanline-v1
project: BeanLine
phase: execute
progress: 22/38
---

## Decisions

Settled in harbor#117 and recorded as adr-004-warmup-discard-after-model-load.
Superseded a note in VytCepas/harbor#94.
EOF
run
t_has "the run's frontmatter reaches the table" "$(cat "$OUT")" '| `20260201-090000_beanline-v1` | BeanLine | execute | 22/38 |'
# Presence, not order: order is the tool's business, and two earlier cuts pinned a guessed one.
_row="$(grep beanline "$OUT")"
t_has "a repo-local issue ref is extracted from the body" "$_row" 'harbor#117'
t_has "a cross-repo issue ref is extracted from the body" "$_row" 'VytCepas/harbor#94'
t_has "an ADR ref is extracted from the body" "$_row" 'adr-004-warmup-discard-after-model-load'
t_has "the fixture carries the task text" "$(cat "$ISA")" 'Build BeanLine'
t_has "the fixture carries body prose" "$(cat "$ISA")" 'Settled in'
t_hasnt "the index does not copy the task text" "$(cat "$OUT")" 'Build BeanLine'
t_hasnt "the index does not copy the body prose" "$(cat "$OUT")" 'Settled in'

t_section "only a directory holding ISA.md is a run"
# The G2 work-log shares MEMORY/WORK; indexed, every session would be an ISA run.
mkdir -p "$STORE/sessions/Mac"
printf -- '---\nslug: not-an-isa\n---\n\nwork log\n' > "$STORE/sessions/Mac/2026-08-22-abc.md"
run --summary
t_has "the work-log sessions tree is not counted" "$(cat "$T_TMP/out")" '1 ISA run(s)'
mkdir -p "$STORE/20260301-120000_no-isa-here"; printf 'notes\n' > "$STORE/20260301-120000_no-isa-here/NOTES.md"
run --summary
t_has "a directory without ISA.md is skipped" "$(cat "$T_TMP/out")" '1 ISA run(s)'

t_section "a slugless run, the source store, an unknown flag"
mkdir -p "$STORE/20260401-080000_bare"; printf '# no frontmatter at all\n' > "$STORE/20260401-080000_bare/ISA.md"
run
t_has "a run with no frontmatter slug is keyed by its directory" "$(cat "$OUT")" '`20260401-080000_bare`'
t_has "the index names the store it read" "$(cat "$OUT")" "$(basename "$STORE")"
t_exit "an unknown flag refuses" 2 env HARBOR_ISA_STORE="$STORE" HARBOR_ISA_OUT="$OUT" sh "$TOOL" --wat
t_done
