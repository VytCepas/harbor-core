#!/usr/bin/env sh
# docs-gen d_decisions (harbor#1029): the decision table is generated from the records, one row per record, into a
# page that is built on demand and not committed (harbor#1197). Hermetic: the arms run on a copy of the tracked tree, never on this checkout.
. "$(dirname "$0")/../../lib/core.sh"; t_init
DG="$T_ROOT/bin/docs-gen.sh"
COPY="$T_TMP/copy"; mkdir -p "$COPY"
( cd "$T_ROOT" && git ls-files | tar -cf - -T - ) | ( cd "$COPY" && tar -xf - )
N="$(ls "$T_ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md | wc -l | tr -d ' ')"

t_section "one row per record, id, title, status, date and superseded-by"
PAGE="$(sh "$DG" 2>/dev/null)"
t_eq "a row for every record" "$N" "$(printf '%s\n' "$PAGE" | grep -c '<tr><td><code>D-[0-9]*</code></td>')"
t_has "D-1 carries its title, status and date" "$PAGE" "<tr><td><code>D-1</code></td><td>Uppercase policy</td><td>accepted</td><td>2026-10-04</td><td>-</td></tr>"

t_section "the page is built, not committed (harbor#1197): a copy of the tracked tree has none, --apply builds it with the table"
# The exported core has no dev layer (STATUS.md) and tracks the page deploy-push built (bin/deploy-push.sh:82).
if [ -e "$COPY/STATUS.md" ]; then _pg=absent; else _pg=present; fi
t_eq "the tracked tree carries no page (the export: the one deploy-push built)" "$_pg" "$([ -e "$COPY/docs/index.html" ] && echo present || echo absent)"
rm -f "$COPY/docs/index.html"
t_exit "--check builds in a copy with no page" 0 sh "$COPY/bin/docs-gen.sh" --check
t_exit "--apply writes it" 0 sh -c "sh '$COPY/bin/docs-gen.sh' --apply >/dev/null 2>&1"
t_eq "the built page carries a row for every record" "$N" "$(grep -c '<tr><td><code>D-[0-9]*</code></td>' "$COPY/docs/index.html")"
t_exit "--check never touches the built page" 0 sh -c "cp '$COPY/docs/index.html' '$T_TMP/p.before' && sh '$COPY/bin/docs-gen.sh' --check >/dev/null 2>&1 && cmp -s '$T_TMP/p.before' '$COPY/docs/index.html'"

t_section "a record the table would drop is a build that no longer matches the records"
mv "$COPY/docs/decisions/0001-"*.md "$T_TMP/" 2>/dev/null
t_eq "one record fewer, one row fewer" "$((N - 1))" "$(sh "$COPY/bin/docs-gen.sh" 2>/dev/null | grep -c '<tr><td><code>D-[0-9]*</code></td>')"

t_section "the real checkout builds"
t_exit "docs-gen --check is green on this checkout" 0 sh "$DG" --check
t_done
