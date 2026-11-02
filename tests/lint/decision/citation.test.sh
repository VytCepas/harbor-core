#!/usr/bin/env sh
# standard.decision-dangling (harbor#1029): every D-n cited in the tree resolves to a decision record.
# Each arm is a throwaway git checkout. The planted id is built at run time, so this file cites nothing.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
Q() { printf '%s/D-%s' "$1" "$2"; }   # a qualified id built at run time, so this file cites nothing itself
DANG="D-$((900 + 1))"   # no record carries it
mk() { # <name> → a checkout: record D-1 and one clean citation of it
  _d="$T_TMP/$1"; mkdir -p "$_d/docs/decisions" "$_d/standards" "$_d/vendor/skills"
  printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-1\ndate: 2026-10-04\nsource: research/x.md\n---\n\n# One\n' > "$_d/docs/decisions/0001-one.md"
  printf 'the rule is D-1 here\n' > "$_d/standards/a.md"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
commit() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1; }

t_section "a citation that resolves is green"
D="$(mk clean)"
t_eq "no dangling citation, no violation" "0" "$(vcount "$(lint1 standard.decision-dangling "$D")")"

t_section "a citation with no record is red, and names the file and the id"
D="$(mk dang)"; printf 'and %s here\n' "$DANG" >> "$D/standards/a.md"; commit "$D"
OUT="$(lint1 standard.decision-dangling "$D")"
t_eq "one violation" "1" "$(vcount "$OUT")"
t_has "...under the rule's id" "$OUT" "VIOLATION [standard.decision-dangling]"
t_has "...naming the file" "$OUT" "standards/a.md"
t_has "...and the id" "$OUT" "$DANG"

t_section "a dangling revised_by inside a record is a citation too"
D="$(mk revby)"
printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-2\ndate: 2026-10-04\nsource: x\nrevised_by: %s\n---\n\n# Two\n' "$DANG" > "$D/docs/decisions/0002-two.md"; commit "$D"
t_has "red, naming the record" "$(lint1 standard.decision-dangling "$D")" "docs/decisions/0002-two.md"

t_section "vendored text is third-party and is not judged"
D="$(mk vend)"; printf 'vendored %s text\n' "$DANG" > "$D/vendor/skills/x.md"; commit "$D"
t_eq "still no violation" "0" "$(vcount "$(lint1 standard.decision-dangling "$D")")"
D="$(mk nestedvend)"; mkdir -p "$D/templates/base/vendor/naming"; printf 'vendored %s text\n' "$DANG" > "$D/templates/base/vendor/naming/x.md"; commit "$D"
t_eq "a vendored copy under a template is third-party too (harbor#1429)" "0" "$(vcount "$(lint1 standard.decision-dangling "$D")")"

t_section "a qualified citation of this repo's own system resolves, or is red, like a bare one (harbor#1429)"
D="$(mk own)"; mkdir -p "$D/.agents"; printf 'scope: project\nrepo-kind: control-plane\n' > "$D/.agents/config.yaml"
printf 'the rule is harbor/D-1 here\n' > "$D/standards/b.md"; commit "$D"
t_eq "harbor/D-1 resolves to this repo's D-1" "0" "$(vcount "$(lint1 standard.decision-dangling "$D")")"
printf 'and harbor/%s here\n' "$DANG" >> "$D/standards/b.md"; commit "$D"
OUT="$(lint1 standard.decision-dangling "$D")"
t_eq "harbor/<no record> is one violation" "1" "$(vcount "$OUT")"
t_has "...naming the id" "$OUT" "$DANG"

t_section "another system's citation is read from its checkout"
Y="$T_TMP/yardrepo"; mkdir -p "$Y/docs/decisions"
printf -- '---\nkind: decision-record\nstatus: accepted\nalias: D-1\ndate: 2026-10-04\n---\n\n# Y\n' > "$Y/docs/decisions/0001-y.md"
D="$(mk far)"; mkdir -p "$D/.agents"; printf 'scope: project\nrepo-kind: control-plane\n' > "$D/.agents/config.yaml"
printf 'see %s here\n' "$(Q yard 1)" > "$D/standards/b.md"; commit "$D"
t_eq "$(Q yard 1) resolves in yard" "0" "$(vcount "$(HARBOR_SCOPE_SCAFFOLDER="$Y" lint1 standard.decision-dangling "$D")")"
printf 'and yard/%s here\n' "$DANG" >> "$D/standards/b.md"; commit "$D"
OUT="$(HARBOR_SCOPE_SCAFFOLDER="$Y" lint1 standard.decision-dangling "$D")"
t_eq "yard/<no record> is one violation" "1" "$(vcount "$OUT")"
t_has "...naming yard's id" "$OUT" "yard/$DANG"
OUT="$(HARBOR_SCOPE_SCAFFOLDER="$T_TMP/nowhere" lint1 standard.decision-dangling "$D")"
t_eq "no yard checkout on the box: not red" "0" "$(vcount "$OUT")"
t_has "...and said to be unchecked" "$OUT" "unchecked"

t_section "a bare D-n in a surface read outside the repo is red; the qualified one is not"
D="$(mk reach)"; mkdir -p "$D/.agents" "$D/contracts"; printf 'scope: project\nrepo-kind: control-plane\n' > "$D/.agents/config.yaml"
printf '# why\ncontracts/\tsiblings read it\n' > "$D/contracts/decision-reach.tsv"
printf 'the rule is harbor/D-1 here\n' > "$D/contracts/x.md"; commit "$D"
t_eq "harbor/D-1 in a reached surface is green" "0" "$(vcount "$(lint1 standard.decision-dangling "$D")")"
printf 'and D-1 bare here\n' >> "$D/contracts/x.md"; commit "$D"
OUT="$(lint1 standard.decision-dangling "$D")"
t_eq "bare D-1 in a reached surface is one violation" "1" "$(vcount "$OUT")"
t_has "...naming the file" "$OUT" "contracts/x.md"
t_has "...and the qualified spelling to write" "$OUT" "harbor/D-1"
t_eq "the same bare D-1 in standards/, which is not listed, stays green" "0" "$(vcount "$(lint1 standard.decision-dangling "$(mk plain)")")"

t_section "the real tree"
t_eq "no dangling citation in this checkout" "0" "$(vcount "$(lint1 standard.decision-dangling "$T_ROOT")")"
t_done
