#!/usr/bin/env sh
# standard-decision-migrate.sh (harbor#1429): records move onto the shared shape without a change of meaning, and twice is once.
. "$(dirname "$0")/../../lib/core.sh"; t_init
M="$T_ROOT/bin/standard-decision-migrate.sh"
mk() { _d="$T_TMP/$1"; mkdir -p "$_d/docs/decisions"; printf '%s' "$_d"; }
fm() { awk 'NR > 1 && $0 == "---" { exit } NR > 1' "$1" | tr '\n' ' '; }   # a record's front matter on one line
body() { awk 'f { print } NR > 1 && $0 == "---" { f = 1 }' "$1" | sed '1{/^$/d;}'; }

t_section "a legacy header becomes front matter and the text under it is untouched"
D="$(mk legacy)"
printf '# ADR-003: Three\n\n**Date:** 2026-04-27\n**Status:** Accepted — superseded in part by [ADR-006](0006-x.md) (the title format)\n\n## Context\n\nbody\n' > "$D/docs/decisions/0003-three.md"
cp "$D/docs/decisions/0003-three.md" "$T_TMP/three.orig"
sh "$M" --root "$D" records >/dev/null 2>&1
t_eq "status, alias, date and the partial revision" "kind: decision-record status: accepted alias: D-3 date: 2026-04-27 supersedes: - superseded_by: - revised_by: D-6 " "$(fm "$D/docs/decisions/0003-three.md")"
t_eq "the original text follows, byte for byte" "$(cat "$T_TMP/three.orig")" "$(body "$D/docs/decisions/0003-three.md")"

t_section "a full supersession writes the pair; a bullet header reads the same"
D="$(mk pair)"
printf '# ADR-014: Old\n\n- Status: **Superseded** by epic #316\n- Date: 2026-06-19 (superseded 2026-06-19)\n- Superseded-by: ADR-015 (the new model)\n' > "$D/docs/decisions/0014-old.md"
printf '# ADR-015: New\n\n- Status: Accepted\n- Date: 2026-06-19\n- Supersedes: ADR-014 (branch-per-env)\n' > "$D/docs/decisions/0015-new.md"
printf '# ADR-016: Partial\n\n- Status: Accepted\n- Date: 2026-06-20\n- Supersedes: title-format portions of ADR-003\n' > "$D/docs/decisions/0016-part.md"
sh "$M" --root "$D" records >/dev/null 2>&1
t_eq "the old one is superseded and names its successor" "kind: decision-record status: superseded alias: D-14 date: 2026-06-19 supersedes: - superseded_by: D-15 " "$(fm "$D/docs/decisions/0014-old.md")"
t_eq "the new one names what it replaces" "kind: decision-record status: accepted alias: D-15 date: 2026-06-19 supersedes: D-14 superseded_by: - " "$(fm "$D/docs/decisions/0015-new.md")"
t_eq "a partial supersession is not a supersedes" "kind: decision-record status: accepted alias: D-16 date: 2026-06-20 supersedes: - superseded_by: - " "$(fm "$D/docs/decisions/0016-part.md")"

t_section "a record that has front matter gains only the two fields"
D="$(mk shaped)"
printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-5\ndate: 2026-10-04\nsource: x\nrevised_by: D-9\n---\n\n# Five\n' > "$D/docs/decisions/0005-five.md"
sh "$M" --root "$D" records >/dev/null 2>&1
t_eq "after date, the rest in place" "kind: decision-record status: accepted alias: D-5 date: 2026-10-04 supersedes: - superseded_by: - source: x revised_by: D-9 " "$(fm "$D/docs/decisions/0005-five.md")"

t_section "twice is once, and --check says when there is work"
sh "$M" --root "$D" records >/dev/null 2>&1; sh "$M" --root "$D" --check records >/dev/null 2>&1
t_eq "nothing left to change" "0" "$?"
D2="$(mk fresh)"; printf '# ADR-001: One\n\n**Date:** 2026-04-23\n**Status:** Accepted\n' > "$D2/docs/decisions/0001-one.md"
sh "$M" --root "$D2" --check records >/dev/null 2>&1
t_eq "--check exits 1 while a record lacks the shape" "1" "$?"
t_eq "...and writes nothing" "# ADR-001: One" "$(head -1 "$D2/docs/decisions/0001-one.md")"

t_section "a header it cannot read is refused, not guessed"
D3="$(mk nodate)"; printf '# ADR-001: One\n\nno header here\n' > "$D3/docs/decisions/0001-one.md"
sh "$M" --root "$D3" records >/dev/null 2>&1
t_eq "exit 2" "2" "$?"
t_eq "...and the file is as it was" "# ADR-001: One" "$(head -1 "$D3/docs/decisions/0001-one.md")"

t_section "qualify writes the system in front of a bare id, once"
printf 'see D-29, D-49 and D-3.\nalready harbor/D-1 and x-D-9 stay.\n' > "$T_TMP/q.md"
sh "$M" --system harbor qualify "$T_TMP/q.md" >/dev/null 2>&1
t_eq "bare ids qualified, adjacent ones too" "see harbor/D-29, harbor/D-49 and harbor/D-3." "$(sed -n 1p "$T_TMP/q.md")"
t_eq "a qualified id and a hyphenated word are left" "already harbor/D-1 and x-D-9 stay." "$(sed -n 2p "$T_TMP/q.md")"
cp "$T_TMP/q.md" "$T_TMP/q.once"; sh "$M" --system harbor qualify "$T_TMP/q.md" >/dev/null 2>&1
t_eq "a second run changes nothing" "$(cat "$T_TMP/q.once")" "$(cat "$T_TMP/q.md")"
t_done
