#!/usr/bin/env sh
# standard.decision-orphan (harbor#1029): a decision record that nothing outside docs/decisions/ cites is
# red, unless CONTRACTS/decision-orphans.tsv names it. The allow-list is checked both ways: a row for a
# cited record, or for an id with no record, is itself red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
rec() { printf -- '---\nkind: decision-record\nstatus: accepted\nalias: %s\ndate: 2026-10-04\nsource: x\n---\n\n# %s\n' "$2" "$3"; }
mk() { # <name> → records D-1 (cited by standards/a.md) and D-2 (cited by nothing)
  _d="$T_TMP/$1"; mkdir -p "$_d/docs/decisions" "$_d/standards" "$_d/CONTRACTS"
  rec x D-1 One > "$_d/docs/decisions/0001-one.md"; rec x D-2 Two > "$_d/docs/decisions/0002-two.md"
  printf 'the rule is D-1 here\n' > "$_d/standards/a.md"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
commit() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1; }

t_section "a record nobody cites is red, and named"
D="$(mk uncited)"
OUT="$(lint1 standard.decision-orphan "$D")"
t_eq "one violation" "1" "$(vcount "$OUT")"
t_has "...naming the orphan's record" "$OUT" "docs/decisions/0002-two.md"

t_section "a citation from inside docs/decisions does not make a record cited"
D="$(mk inner)"; rec x D-3 Three > "$D/docs/decisions/0003-three.md"; printf -- 'revised_by: D-2\n' >> "$D/docs/decisions/0003-three.md"; commit "$D"
t_has "D-2 is still an orphan" "$(lint1 standard.decision-orphan "$D")" "docs/decisions/0002-two.md"

t_section "the allow-list exempts a deliberate orphan"
D="$(mk allowed)"; printf '# id\treason\nD-2\tdeliberately uncited\n' > "$D/CONTRACTS/decision-orphans.tsv"; commit "$D"
t_eq "allow-listed orphan is green" "0" "$(vcount "$(lint1 standard.decision-orphan "$D")")"

t_section "a stale allow-list row is red both ways"
D="$(mk stale)"; printf 'D-2\tx\nD-1\tcited, so this row is stale\n' > "$D/CONTRACTS/decision-orphans.tsv"; commit "$D"
t_has "a row for a cited record is red" "$(lint1 standard.decision-orphan "$D")" "D-1"
D="$(mk ghost)"; printf 'D-2\tx\nD-7\tno such record\n' > "$D/CONTRACTS/decision-orphans.tsv"; commit "$D"
t_has "a row for a missing record is red" "$(lint1 standard.decision-orphan "$D")" "D-7"

t_section "the real tree"
t_eq "every record is cited or allow-listed" "0" "$(vcount "$(lint1 standard.decision-orphan "$T_ROOT")")"
t_done
