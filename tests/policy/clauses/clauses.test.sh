#!/usr/bin/env sh
# bin/policy-check.sh (harbor#1026): the constitution as a register of clauses, both ways, traced down, with the competency questions.
. "$(dirname "$0")/../../lib/core.sh"; t_init
PC="$T_ROOT/bin/policy-check.sh"; FX="$T_ROOT/fixtures/policy"
pc() { sh "$PC" "$@" 2>&1; }
prc() { sh "$PC" "$@" >/dev/null 2>&1; echo $?; }

t_section "the real register agrees with the real prose"
t_eq "--census is green" 0 "$(prc --census)"
t_has "...and says how many clauses it matched" "$(pc --census)" "0 finding(s)"
t_eq "--check (census, shape, trace) is green" 0 "$(prc --check)"
n_prose="$(grep -cE '^(- |[0-9]+\. )?\*\*' "$T_ROOT/policy/constitution.md")"
n_rows="$(awk -F'\t' '!/^#/ && $1 != "id"' "$T_ROOT/policy/clauses.tsv" | wc -l | tr -d ' ')"
t_has "the census count is the register's row count" "$(pc --census)" "$n_rows row(s) in the register"
t_eq "every strength in the register is a term of class strength" "" "$(awk -F'\t' '!/^#/ && $1 != "id" { print $2 }' "$T_ROOT/policy/clauses.tsv" | sort -u | while read -r s; do awk -F'\t' -v s="$s" '$1 == s && $2 ~ /strength/ { f = 1 } END { if (!f) print s }' "$T_ROOT/standards/naming/terms.tsv"; done)"
t_eq "controls are never a strength" 0 "$(awk -F'\t' '!/^#/ { print $2 }' "$T_ROOT/policy/clauses.tsv" | grep -c '^\(lint\|check\|admission\|injection\)$' || :)"

t_section "an anchor without a row, and a row without an anchor, are red"
R="$T_TMP/real"; mkdir -p "$R/policy" "$R/standards/naming"
cp "$T_ROOT/policy/constitution.md" "$T_ROOT/policy/clauses.tsv" "$R/policy/"; cp "$T_ROOT/standards/naming/terms.tsv" "$T_ROOT/standards/naming/controls.tsv" "$R/standards/naming/"
t_eq "the copy is green" 0 "$(prc --root "$R" --census)"
grep -v '^n1.2	' "$T_ROOT/policy/clauses.tsv" > "$R/policy/clauses.tsv"
t_eq "a deleted row: red" 1 "$(prc --root "$R" --census)"
t_has "...naming the prose clause that lost its row" "$(pc --root "$R" --census)" "[policy.clause-no-row]"
cp "$T_ROOT/policy/clauses.tsv" "$R/policy/clauses.tsv"; sed 's/^\*\*Lead with the answer\.\*\*/**Lead with the reply.**/' "$T_ROOT/policy/constitution.md" > "$R/policy/constitution.md"
t_eq "an edited bold lead: red" 1 "$(prc --root "$R" --census)"
t_has "...the row now anchors text the prose lacks" "$(pc --root "$R" --census)" "[policy.row-no-clause]"
cp "$T_ROOT/policy/constitution.md" "$R/policy/constitution.md"

t_section "each arm goes red on its fixture, and the pass fixture stays green"
t_has "--self-test judges every fixture" "$(pc --self-test)" "0 failed"
for d in "$FX"/*/; do
  n="${d%/}"; n="${n##*/}"; IFS='	' read -r a w < "${d}case"
  if [ "$w" = none ]; then t_eq "$n: green" 0 "$(cd "$d" && sh "$PC" --root "$d" $a >/dev/null 2>&1; echo $?)"
  else t_has "$n: raises policy.$w" "$(cd "$d" && sh "$PC" --root "$d" $a 2>&1)" "[policy.$w]"; fi
done

t_section "the deployed constitution is judged by the same anchors"
t_eq "the real deployed anchors need no row more than the source has" 0 "$(prc --deployed "$T_ROOT/policy/constitution.md")"
t_eq "a deployed file with an extra bold-led block is red" 1 "$(printf '\n**A deployed-only rule.** text\n' | cat "$T_ROOT/policy/constitution.md" - > "$T_TMP/dep.md"; prc --deployed "$T_TMP/dep.md")"

t_section "the competency questions are queries (harbor#1026 item 8), each with a pass and a fail fixture"
t_has "Q2 lists a clause with no mechanism" "$(cd "$FX/red-trace-down" && sh "$PC" --root . --ask 2)" "t.1"
t_eq "Q2 lists none on the pass fixture" "Q2 clauses with no control and no judgment declaration:" "$(cd "$FX/pass" && sh "$PC" --root . --ask 2)"
t_has "Q3 counts a control that enforces no clause" "$(cd "$FX/red-trace-up" && sh "$PC" --root . --ask 3)" "enforce no clause"
t_has "Q9 gives the judgment share per strength" "$(pc --ask 9)" "constitutional"
t_has "Q8 counts controls that never went red" "$(pc --ask 8)" "lint"
t_has "Q6 finds the inbound references of a control" "$(pc --ask 6 admission.merge-raw)" "policy/clauses.tsv"
t_has "Q5 is harbor why" "$(pc --ask 5 bin/lint-conventions.sh)" "implements"
for q in 1 4 7 10; do t_has "Q$q says what it lacks rather than answering nothing" "$(pc --ask $q)" "unanswerable"; done
t_eq "a question out of range is a usage error" 2 "$(prc --ask 11)"

t_section "harbor why: file -> control -> clause -> issue, from rows and commit refs only"
t_has "a file that implements a clause's control names the clause" "$(pc --why bin/lint-conventions.sh)" "enforces  pre.1"
t_eq "a file no control names is explained as such, exit 1" 1 "$(prc --why README.md)"

t_section "motivated_by is derived, and a clause with no edge is a warn finding"
t_has "the motivation report counts clauses with an edge" "$(pc --motivation)" "clause(s) have an edge"
t_has "a fixture clause no commit touched has no edge" "$(cd "$FX/red-edge" && sh "$PC" --root . --motivation 2>&1)" "[policy.clause-no-motive]"

t_section "feedback notes with neither a clause nor a control link are listed, never promoted"
t_has "a note without enforced_by: is listed" "$(cd "$FX/red-notes" && sh "$PC" --root . --notes notes 2>&1)" "b.md"
t_has "a linked note is absent" "$(cd "$FX/red-notes" && sh "$PC" --root . --notes notes 2>&1 | grep -c 'a.md' || :)" "0"
t_done
