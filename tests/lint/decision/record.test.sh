#!/usr/bin/env sh
# standard.decision-fields (harbor#1429): every decision record opens with the one front matter all repos share.
# Each arm is a throwaway git checkout; a record is built by rec() so the fields can be taken away one at a time.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
Q() { printf '%s/D-%s' "$1" "$2"; }   # a qualified id built at run time, so this file cites nothing itself
rec() { # <alias> <status> [extra front matter line…] → a complete record
  _a="$1"; _s="$2"; shift 2
  printf -- '---\nkind: decision-record\nstatus: %s\nalias: %s\ndate: 2026-10-04\nsupersedes: -\nsuperseded_by: -\n' "$_s" "$_a"
  for _x in "$@"; do printf '%s\n' "$_x"; done
  printf -- '---\n\n# %s\n' "$_a"
}
mk() { # <name> → a checkout with one complete record
  _d="$T_TMP/$1"; mkdir -p "$_d/docs/decisions"
  rec D-1 accepted > "$_d/docs/decisions/0001-one.md"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
commit() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1; }
R=standard.decision-fields
acount() { printf '%s\n' "$1" | grep "ADVISORY \[$R\]" | grep -vc unchecked; }   # advisories a warn control prints; "could not look" is not one

t_section "a complete record is green"
D="$(mk ok)"
t_eq "no violation" "0" "$(acount "$(lint1 $R "$D")")"

t_section "a record without supersedes and superseded_by is red, and names the file and the fields"
D="$(mk nosup)"
printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-2\ndate: 2026-10-04\n---\n\n# Two\n' > "$D/docs/decisions/0002-two.md"; commit "$D"
OUT="$(lint1 $R "$D")"
t_eq "one violation" "1" "$(acount "$OUT")"
t_has "...naming the file" "$OUT" "docs/decisions/0002-two.md"
t_has "...and the missing fields" "$OUT" "supersedes"
t_has "...both of them" "$OUT" "superseded_by"

t_section "a record with no front matter at all is red"
D="$(mk nofm)"; printf '# ADR-2: Two\n\n**Status:** Accepted\n' > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the record" "$(lint1 $R "$D")" "docs/decisions/0002-two.md"

t_section "a status outside the MADR words is red"
D="$(mk badstatus)"; rec D-2 maybe > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the status" "$(lint1 $R "$D")" "maybe"

t_section "two records with one alias are red"
D="$(mk dup)"; rec D-1 accepted > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the alias" "$(lint1 $R "$D")" "D-1"

t_section "a reference that is not [system/]D-n is red"
D="$(mk badref)"; rec D-2 accepted "revised_by: soon" > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the value" "$(lint1 $R "$D")" "soon"

t_section "a qualified and a listed reference are well formed"
D="$(mk goodref)"; rec D-2 accepted "revised_by: $(Q yard 3), D-1" > "$D/docs/decisions/0002-two.md"; commit "$D"
t_eq "no violation" "0" "$(acount "$(lint1 $R "$D")")"

t_section "the real tree"
t_eq "every record in this checkout carries the shape" "0" "$(acount "$(lint1 $R "$T_ROOT")")"
t_done
