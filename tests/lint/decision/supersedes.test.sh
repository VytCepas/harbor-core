#!/usr/bin/env sh
# standard.decision-supersession (harbor#1429): supersedes and superseded_by name each other, in one repo and across two.
# A repo is a throwaway checkout whose .agents/config.yaml names its kind, so it knows its own system (harbor or yard).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
Q() { printf '%s/D-%s' "$1" "$2"; }   # a qualified id built at run time, so this file cites nothing itself
rec() { # <alias> <status> <supersedes> <superseded_by> → a record
  printf -- '---\nkind: decision-record\nstatus: %s\nalias: %s\ndate: 2026-10-04\nsupersedes: %s\nsuperseded_by: %s\n---\n\n# %s\n' "$2" "$1" "$3" "$4" "$1"
}
repo() { # <name> <repo-kind> → an empty checkout of that kind
  _d="$T_TMP/$1"; mkdir -p "$_d/docs/decisions" "$_d/.agents"
  printf 'scope: project\nrepo-kind: %s\n' "$2" > "$_d/.agents/config.yaml"
  printf '%s' "$_d"
}
commit() { ( cd "$1" && git init -q . 2>/dev/null; git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1; }
R=standard.decision-supersession
acount() { printf '%s\n' "$1" | grep "ADVISORY \[$R\]" | grep -vc unchecked; }   # advisories a warn control prints; "could not look" is not one

t_section "a pair that names each other is green"
D="$(repo pair control-plane)"
rec D-1 superseded - D-2 > "$D/docs/decisions/0001-one.md"; rec D-2 accepted D-1 - > "$D/docs/decisions/0002-two.md"; commit "$D"
t_eq "no violation" "0" "$(acount "$(lint1 $R "$D")")"

t_section "superseded_by with no supersedes back is red, and names the record that is one-way"
D="$(repo oneway control-plane)"
rec D-1 superseded - D-2 > "$D/docs/decisions/0001-one.md"; rec D-2 accepted - - > "$D/docs/decisions/0002-two.md"; commit "$D"
OUT="$(lint1 $R "$D")"
t_eq "one violation" "1" "$(acount "$OUT")"
t_has "...naming the superseded record" "$OUT" "docs/decisions/0001-one.md"
t_has "...and the successor that does not name it back" "$OUT" "D-2"

t_section "supersedes with no superseded_by back is red the other way round"
D="$(repo reverse control-plane)"
rec D-1 accepted - - > "$D/docs/decisions/0001-one.md"; rec D-2 accepted D-1 - > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the successor" "$(lint1 $R "$D")" "docs/decisions/0002-two.md"

t_section "a target that no record defines is red"
D="$(repo gone control-plane)"
rec D-1 superseded - D-9 > "$D/docs/decisions/0001-one.md"; commit "$D"
t_has "red, naming the missing target" "$(lint1 $R "$D")" "D-9"

t_section "a named successor with a status that is not superseded is red, and so is the reverse"
D="$(repo status control-plane)"
rec D-1 accepted - D-2 > "$D/docs/decisions/0001-one.md"; rec D-2 superseded D-1 - > "$D/docs/decisions/0002-two.md"; commit "$D"
OUT="$(lint1 $R "$D")"
t_has "D-1 names a successor but is accepted" "$OUT" "docs/decisions/0001-one.md"
t_has "D-2 is superseded and names none" "$OUT" "docs/decisions/0002-two.md"

t_section "a record cannot supersede itself"
D="$(repo self control-plane)"
rec D-1 superseded D-1 D-1 > "$D/docs/decisions/0001-one.md"; commit "$D"
t_has "red" "$(lint1 $R "$D")" "docs/decisions/0001-one.md"

t_section "across two repos: a pair that names each other, qualified, is green"
H="$(repo xh control-plane)"; Y="$(repo xy scaffolder)"
rec D-1 superseded - $(Q yard 1) > "$H/docs/decisions/0001-one.md"; rec D-1 accepted harbor/D-1 - > "$Y/docs/decisions/0001-one.md"; commit "$H"; commit "$Y"
t_eq "harbor side green" "0" "$(acount "$(HARBOR_SCOPE_SCAFFOLDER="$Y" lint1 $R "$H")")"
t_eq "yard side green" "0" "$(acount "$(HARBOR_SCOPE_REPO="$H" lint1 $R "$Y")")"

t_section "across two repos: the far side not naming back is red on the near side"
Y2="$(repo xy2 scaffolder)"
rec D-1 accepted - - > "$Y2/docs/decisions/0001-one.md"; commit "$Y2"
OUT="$(HARBOR_SCOPE_SCAFFOLDER="$Y2" lint1 $R "$H")"
t_eq "one violation" "1" "$(acount "$OUT")"
t_has "...naming the record and the foreign target" "$OUT" "$(Q yard 1)"

t_section "across two repos: a checkout that cannot be found is unchecked, never red"
OUT="$(HARBOR_SCOPE_SCAFFOLDER="$T_TMP/none" lint1 $R "$H")"
t_eq "no violation" "0" "$(acount "$OUT")"
t_has "...and says it could not look" "$OUT" "unchecked"

t_section "the real tree"
t_eq "supersession in this checkout is consistent" "0" "$(acount "$(lint1 $R "$T_ROOT")")"
t_done
