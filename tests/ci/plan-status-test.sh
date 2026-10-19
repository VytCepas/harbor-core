#!/usr/bin/env sh
# plan-status.sh derives each ticket's state from its own falsifier (harbor#117). The load-bearing
# arms are the negatives: "DONE" in the words, or a cmd: that prints success and exits 1, never counts.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/plan-status.sh"; P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
# Not plan.md and PLAN.md: on a case-insensitive volume those are one file (the harbor#239 trap).
PLAN="$P/tickets.md"; OUT="$P/derived.md"
run() { HARBOR_PLAN_SRC="$PLAN" HARBOR_PLAN_OUT="$OUT" sh "$TOOL" "$@" > "$P/out" 2>&1; echo $?; }
state() { grep -F "| \`$1\` |" "$OUT" | awk -F'|' '{ gsub(/ /, "", $3); print $3 }'; }  # <ticket id>
: > "$P/present.txt"
cat > "$PLAN" <<EOF
## X · fixture

**Z1 · a ticket whose artifact exists** — effort S
- Done when: it exists.
- Evidence: $P/present.txt

**Z2 · a ticket whose artifact does not** — effort S
- Done when: it exists.
- Evidence: $P/absent.txt

**Z3 · a ticket that merely SAYS it is done** — effort S · **DONE — shipped, honest**
- Done when: somebody wrote DONE above.

**Z4 · a command that exits zero** — effort S
- Evidence: cmd: true

**Z5 · a command that PRINTS success and exits nonzero** — effort S
- Evidence: cmd: echo BUILT SUCCESS DONE; exit 1

**Z7 · a ticket whose proof is outside this repo** — effort S
- Evidence: host: something only the box can answer

**Z8 · a cancelled ticket whose evidence path EXISTS** — effort S · **VOID by owner decision**
- Evidence: $P/present.txt

**Z9 · a live ticket whose BODY discusses voiding** — effort S
- Note: M6 is VOID by owner decision and this ticket explains why at length.
- Evidence: $P/present.txt
EOF
run --summary >/dev/null; SUM="$(cat "$P/out")"
run >/dev/null

t_section "each ticket's state comes from its evidence"
t_eq "an artifact that exists is DONE" DONE "$(state Z1)"
t_eq "an artifact that does not exist is OPEN" OPEN "$(state Z2)"
t_has "…and says it is not present" "$(grep -F '| `Z2` |' "$OUT")" 'not present'
t_eq "a ticket that only SAYS done is UNDECLARED (the harbor#117 defect)" UNDECLARED "$(state Z3)"
t_eq "a cmd: that exits zero is DONE" DONE "$(state Z4)"
t_eq "a cmd: that prints success and exits 1 is OPEN" OPEN "$(state Z5)"
t_eq "host: evidence is named, never evaluated" HOST-DEPENDENT "$(state Z7)"
t_eq "a VOID heading beats evidence that exists" VOID "$(state Z8)"
t_eq "VOID in a live ticket's body cancels nothing" DONE "$(state Z9)"

t_section "the summary counts every state"
t_has "the summary line" "$SUM" '3 done, 2 open, 1 UNDECLARED, 1 host-dependent, 1 void, of 8 ticket(s)'
t_has "host-dependent and void tickets leak into neither done nor open" "$SUM" '3 done, 2 open'

t_section "--check"
t_eq "--check passes on a freshly written file" 0 "$(run --check)"
printf '\n**Z6 · added later** — effort S\n- Evidence: %s\n' "$P/present.txt" >> "$PLAN"
t_eq "--check fails when the plan moved and the file did not" 1 "$(run --check)"
t_has "…and says the file is stale" "$(cat "$P/out")" 'stale'
t_eq "an absent plan refuses" 1 "$(HARBOR_PLAN_SRC="$P/nope.md" HARBOR_PLAN_OUT="$OUT" sh "$TOOL" --summary > "$P/out" 2>&1; echo $?)"
t_has "…and says there is no plan" "$(cat "$P/out")" 'no plan at'

t_section "host: is named, never evaluated, so the derivation is HOME-independent"
# Teeth first: a cmd: reaching into $HOME must differ across two HOMEs, or the host: arm is
# vacuous. $HOME stays literal in the fixture; plan-status.sh expands it in its own eval.
HA="$P/homeA"; HB="$P/homeB"; mkdir -p "$HA" "$HB"; : > "$HA/on-this-box-only"; HP="$P/hostdep.md"
derive() { HOME="$2" HARBOR_PLAN_SRC="$HP" HARBOR_PLAN_OUT="$P/$1.md" sh "$TOOL" >/dev/null 2>&1; }  # <out> <home>
printf '## H · fixture\n\n**H1 · a falsifier that reaches into $HOME** — effort S\n- Evidence: cmd: test -f "$HOME/on-this-box-only"\n' > "$HP"
derive h-a "$HA"; derive h-b "$HB"
t_exit "a HOME-dependent cmd: differs across two HOMEs" 1 cmp -s "$P/h-a.md" "$P/h-b.md"
printf '## H · fixture\n\n**H1 · the same claim, declared host:** — effort S\n- Evidence: host: a file that exists on one box only\n' > "$HP"
derive h-c "$HA"; derive h-d "$HB"
t_exit "the same claim as host: is identical across two HOMEs" 0 cmp -s "$P/h-c.md" "$P/h-d.md"
t_done
