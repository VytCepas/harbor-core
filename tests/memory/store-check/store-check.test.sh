#!/usr/bin/env sh
# memory-store-check.sh, the always-on memory index's size-and-age bound (CX1, harbor#183/#184).
# Its value is that it can say OVER, so every finding is paired with the healthy shape it must
# not fire on (§2.11). It runs from a fixture bin/ whose context-budget.sh is a stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
FB="$B/bin"; mkdir -p "$FB"; cp "$T_ROOT/bin/memory-store-check.sh" "$T_ROOT/bin/library-log.sh" "$FB/"; T="$FB/memory-store-check.sh"
stub() { # <spent> <ceiling> — one line in the shape context-budget.sh prints
  cat > "$FB/context-budget.sh" <<EOS
#!/usr/bin/env sh
printf 'SPENT EVERY SESSION %46s ceiling %s\n' '$1' '$2'
exit 1
EOS
}
stub_absent() { rm -f "$FB/context-budget.sh"; }
# The store sits at the cwd-keyed path, and --root names that same path (harbor#317).
FCFG="$B/cfg"; S="$FCFG/projects/$(printf '%s' "$PWD" | tr '/' '-')/memory"
build() { # <note…> — notes a.md b.md …, and an index pointing at each
  rm -rf "$S"; mkdir -p "$S"; : > "$S/MEMORY.md"
  for n in "$@"; do printf 'body of %s\n' "$n" > "$S/$n"; printf -- '- [%s](%s) — hook\n' "$n" "$n" >> "$S/MEMORY.md"; done
}
run() { CLAUDE_CONFIG_DIR="$FCFG" sh "$T" --root "$S" --index "$S/MEMORY.md" "$@" 2>&1; }
rc() { run "$@" >/dev/null; echo $?; }
js() { run --json | jq -c "$1" 2>/dev/null || echo PARSE_ERROR; }  # <jq filter>
field() { printf '%s\n' "$1" | sed -n "s/^  $2  *\([0-9][0-9]*\).*/\1/p"; }  # <report> <row label>
# The allowance is `always-on pointers x 150 + 600`; this pads MEMORY.md to EXACTLY <bytes>
# with one pointer-free line, since two cases sit one byte either side of it.
fatten() { # <total-bytes>
  _have="$(wc -c < "$S/MEMORY.md" | tr -d ' ')"; [ "$1" -le "$_have" ] && return 0
  _need=$(( $1 - _have )); _pad=''; _n=1
  while [ "$_n" -lt "$_need" ]; do _pad="${_pad}x"; _n=$(( _n + 1 )); done
  printf '%s\n' "$_pad" >> "$S/MEMORY.md"
}
NL='
'
OVER="${NL}OVER —"; HR='Index within allowance'; NOV='NO VERDICT on size'

t_section "1 · a healthy store reports clean, and --strict does not fire"
build a.md b.md c.md; stub 5000 24000; r="$(run)"
t_eq "1a three notes are counted" 3 "$(field "$r" notes)"
t_hasnt "1b a healthy store reports no DANGLING" "$r" 'DANGLING'
t_hasnt "1c a healthy store reports no ORPHAN" "$r" 'ORPHAN'
t_has "1d a store far under allowance says so" "$r" "$HR"
t_eq "1e --strict on a healthy store" 0 "$(rc --strict)"

t_section "2 · the index over its allowance is the finding this tool exists for"
# 3 pointers allow 1,050 B; 1,400 B of the same 3 is a pointer that grew into a paragraph.
build a.md b.md c.md; fatten 1400; r="$(run)"
t_has "2a a fat index reports OVER" "$r" "$OVER"
t_has "2b the allowance is 3 pointers x 150 + 600" "$r" 'allowance of 1050 B'
t_eq "2c --strict on an over-allowance index" 1 "$(rc --strict)"
t_eq "2d a non-strict run on OVER" 0 "$(rc)"

t_section "3 · the boundary is -gt, so exactly AT the allowance is not over (§2.11)"
build a.md b.md c.md; fatten 1050; r="$(run)"
t_hasnt "3a an index exactly at allowance is not OVER" "$r" "$OVER"
t_has "3b an index exactly at allowance has zero headroom" "$r" '— 0 B of headroom'
build a.md b.md c.md; fatten 1051
t_has "3c an index one byte over its allowance is OVER" "$(run)" "$OVER"

t_section "4 · index parity, both directions"
build a.md b.md c.md; stub 5000 24000; rm "$S/b.md"; r="$(run)"
t_has "4a a pointer to a deleted note is reported" "$r" 'DANGLING'
t_has "4b DANGLING names b.md" "$r" "${NL}    b.md"
t_eq "4c --strict on a dangling pointer" 1 "$(rc --strict)"
build a.md b.md c.md; printf 'a note nothing points at\n' > "$S/orphan.md"; r="$(run)"
t_has "4d an unindexed note is reported" "$r" 'ORPHAN'
t_has "4e ORPHAN names orphan.md" "$r" "${NL}    orphan.md"
t_eq "4f --strict on an orphan note" 1 "$(rc --strict)"

t_section "5 · an index that links OUT is not a dangling pointer"
build a.md b.md
printf -- '- [upstream](https://example.invalid/x) — external\n- [section](#how-i-work) — an anchor\n' >> "$S/MEMORY.md"
t_hasnt "5a an external link or anchor is not dangling" "$(run)" 'DANGLING'
t_eq "5b --strict on an index carrying an external link" 0 "$(rc --strict)"

t_section "6 · an index with bytes and NO parsed pointer gets no verdict"
# An extractor returning nothing from a document that plainly has bytes is a finding, never a pass (REF-10).
build; printf 'this index is prose and carries no pointer at all\n' > "$S/MEMORY.md"; fatten 3000; r="$(run)"
t_has "6a bytes with no pointer say NOT DERIVED" "$r" 'NOT DERIVED'
t_has "6b the no-verdict branch prints" "$r" "$NOV"
t_hasnt "6c a 3,000 B index with no parsed pointer is not declared OVER" "$r" "$OVER"
t_eq "6d --strict where the allowance is not derivable" 0 "$(rc --strict)"
# harbor#316 cut the coupling: with no context-budget.sh at all, a full verdict still comes out.
stub_absent; build a.md b.md c.md; r="$(run)"
t_has "6e an allowance is derived without context-budget.sh" "$r" 'index allowance (derived)'
t_has "6f ...and a verdict with it" "$r" "$HR"
t_eq "6g an absent context-budget.sh: exit" 0 "$(rc)"

t_section "7 · a store that does not exist is not an error"
stub 5000 24000
t_exit "7a a missing store" 0 sh "$T" --root "$B/nope"
t_has "7b a missing store says why it is silent" "$(sh "$T" --root "$B/nope" 2>&1)" 'nothing always-on to bound'
t_has "7c --json on a missing store reports present:false" "$(sh "$T" --root "$B/nope" --json 2>&1)" '"present":false'

t_section "8 · --json carries every number the text report does"
build a.md b.md c.md; fatten 1400; j="$(run --json)"
t_has "8a json note count" "$j" '"notes":3'
t_has "8b json over:true" "$j" '"over":true'
t_has "8c json allowance" "$j" '"allowance":1050'
t_has "8d json allowance_derived:true" "$j" '"allowance_derived":true'
t_has "8f json carries the per-pointer factor" "$j" '"bytes_per_pointer":150'
t_has "8g json carries the structure term" "$j" '"structure_bytes":600'
t_has "8h the schema change is versioned" "$j" '"schema_version":2'
build; printf 'prose and no pointer\n' > "$S/MEMORY.md"; fatten 3000
t_has "8e json reports an underivable allowance" "$(run --json)" '"allowance_derived":false'

t_section "9 · usage errors are distinguishable from findings"
t_exit "9a --root with no operand" 2 sh "$T" --root
t_exit "9b --top with a non-number" 2 sh "$T" --top x
t_exit "9c --stale-days -1" 2 sh "$T" --stale-days -1
t_exit "9d an unknown flag" 2 sh "$T" --nonsense
t_exit "9e --help" 0 sh "$T" --help
t_has "9f --help points at the tool that covers link rot" "$(sh "$T" --help 2>&1)" 'memory-lint'

t_section "10 · the largest-note list, and --top 0 suppressing it"
build a.md b.md c.md; stub 5000 24000
printf '%s\n' "$(dd if=/dev/zero bs=1 count=900 2>/dev/null | tr '\0' 'x')" > "$S/big.md"
printf -- '- [big](big.md) — hook\n' >> "$S/MEMORY.md"; r="$(run --top 1)"
t_has "10a --top 1 prints its header" "$r" 'largest 1 note'
t_has "10b the largest note is listed" "$r" 'big.md'
t_hasnt "10c --top 0 prints no list" "$(run --top 0)" 'largest'

t_section "11 · the findings discriminate"
build a.md b.md c.md; fatten 1400
t_hasnt "M1 an index 350 B over its allowance reports no headroom" "$(run)" 'headroom'
build a.md b.md; rm "$S/b.md"
t_hasnt "M2 a dangling pointer is not also an ORPHAN" "$(run)" 'ORPHAN'
# The same 1,400 B is OVER at 3 pointers (1,050) and fine at 12 (2,400): the bound is per pointer.
build a.md b.md c.md; fatten 1400
t_eq "M3 1,400 B at 3 pointers is OVER" 1 "$(run | grep -c '^OVER —')"
build a.md b.md c.md d.md e.md f.md g.md h.md i.md j.md k.md l.md; fatten 1400
t_eq "M3 the same 1,400 B at 12 pointers is not" 0 "$(run | grep -c '^OVER —')"
build a.md b.md; rm "$S/b.md"; stub 5000 24000
t_eq "M4 a finding without --strict exits 0" 0 "$(rc)"
t_eq "M4 the same finding under --strict exits 1" 1 "$(rc --strict)"

t_section "12 · a TIERED index: parity is the union, bytes are the always-on file"
# MEMORY.md is partial by design; a note only the overflow index names is not an orphan.
build a.md b.md c.md
printf -- '- [a.md](a.md) — hook\n' > "$S/MEMORY.md"
printf -- '- [b.md](b.md) — hook\n- [c.md](c.md) — hook\n' > "$S/INDEX-FULL.md"
stub 5000 24000
t_hasnt "12a a note the overflow index names is no orphan" "$(run | tr 'A-Z' 'a-z')" 'orphan'
t_eq "12b --strict on a healthy tiered store" 0 "$(rc --strict)"
t_eq "12c union parity is 3 pointers" 3 "$(js .index.pointers)"
t_eq "12d the always-on count is 1" 1 "$(js .index.pointers_always_on)"
t_eq "12e a split index reports tiered" true "$(js .full_index.tiered)"
b1="$(js .index.bytes)"  # the overflow is never loaded, so growing it must not move the charge
printf -- '- [pad](a.md) — %s\n' "$(head -c 400 /dev/zero | tr '\0' 'x')" >> "$S/INDEX-FULL.md"
t_eq "12f growing the overflow index leaves the charged bytes alone" "$b1" "$(js .index.bytes)"
printf 'body of d\n' > "$S/d.md"
t_has "12g a note in neither index is still an orphan" "$(js .orphans)" 'd.md'
build a.md; printf -- '- [a.md](a.md) — hook\n' > "$S/MEMORY.md"; printf -- '- [gone](gone.md) — hook\n' > "$S/INDEX-FULL.md"
t_has "12h a dangling pointer in the overflow index is still dangling" "$(js .dangling)" 'gone.md'

t_section "13 · absent --full-index means untiered"
build a.md b.md; stub 5000 24000
t_eq "13a a store with no overflow index is not tiered" false "$(js .full_index.tiered)"
t_eq "13b full_index.present is false with no overflow file" false "$(js .full_index.present)"

t_section "14 · the two tiers cross-link, and an index is not a note"
build a.md b.md
printf -- '- [a.md](a.md) — hook\n- [the rest](INDEX-FULL.md)\n' > "$S/MEMORY.md"
printf -- '- [back](MEMORY.md)\n- [b.md](b.md) — hook\n' > "$S/INDEX-FULL.md"
_d="$(js .dangling)"
t_hasnt "14a the cross-link to the overflow index is not dangling" "$_d" 'INDEX-FULL.md'
t_hasnt "14b the back-link to the always-on index is not dangling" "$_d" 'MEMORY.md'
t_eq "14c --strict on a healthy cross-linked tiered store" 0 "$(rc --strict)"
printf -- '- [nope](INDEX-MISSING.md)\n' >> "$S/MEMORY.md"
t_has "14d a real dangling pointer that looks index-ish still fires" "$(js .dangling)" 'INDEX-MISSING.md'

t_section "15 · the design falsifier: an off-index note is still findable"
build a.md; printf 'a note about kingfishers and their nesting habits\n' > "$S/offindex.md"
printf -- '- [a.md](a.md) — hook\n- [the rest](INDEX-FULL.md)\n' > "$S/MEMORY.md"
printf -- '- [offindex](offindex.md) — hook\n' > "$S/INDEX-FULL.md"
t_hasnt "15a an off-index note is not an orphan" "$(js .orphans)" 'offindex.md'
t_hasnt "15b the fixture keeps the note out of the always-on index" "$(cat "$S/MEMORY.md")" 'offindex'
t_has "15c the off-index note is findable by searching the store" "$(grep -ril 'kingfisher' "$S" 2>/dev/null)" 'offindex.md'

t_section "16 · a verdict needs a basis and an index (harbor#317, #316)"
# This cwd's store is thin, --root's is fat: judged on the wrong basis, a fat store reads as headroom.
build a.md b.md c.md
OTHER="$B/not-the-cwd-store"; mkdir -p "$OTHER"
printf -- '- [a.md](a.md) — hook\n' > "$OTHER/MEMORY.md"; printf 'body of a\n' > "$OTHER/a.md"
_pad=''; _n=0; while [ "$_n" -lt 2000 ]; do _pad="${_pad}x"; _n=$(( _n + 1 )); done
printf '%s\n' "$_pad" >> "$OTHER/MEMORY.md"  # 1 pointer allows 750 B; this is ~2 KB
_o="$(CLAUDE_CONFIG_DIR="$FCFG" sh "$T" --root "$OTHER" --index "$OTHER/MEMORY.md" 2>&1)"
t_has "16a --root at another store judges that store" "$_o" "$OVER"
t_has "16b the allowance comes from --root's own pointer count" "$_o" 'allowance of 750 B'
t_hasnt "16c a fat --root store has no headroom" "$_o" 'headroom'
t_has "16d the --root path still reports the size facts" "$_o" 'index bytes (ALWAYS ON)'
rm -rf "$S"; mkdir -p "$S"; stub 5000 24000; _n="$(run)"  # a store directory with no index
t_has "16d a store with no index gets no verdict" "$_n" "$NOV"
t_hasnt "16e an absent index is not within allowance" "$_n" 'headroom'
t_eq "16f --strict on an absent index" 0 "$(rc --strict)"
t_has "16g json carries verdict:false for an absent index" "$(run --json)" '"verdict":false'
t_hasnt "16h json carries no over verdict for an absent index" "$(run --json)" '"over":'
build a.md b.md c.md; stub 5000 24000
t_has "16i the healthy path keeps its verdict" "$(run)" 'headroom'

t_section "17 · a symlinked store is the one memory-route creates (harbor#608)"
# find without -L walked nothing behind the link while bytes() read the index through it.
linked_store() { # <cfg-dir> <real-store> — prints the symlinked cwd-keyed path
  _lp="$1/projects/$(printf '%s' "$PWD" | tr '/' '-')/memory"; mkdir -p "$(dirname "$_lp")"; ln -s "$2" "$_lp"; printf '%s' "$_lp"
}
REAL="$B/real-store"; mkdir -p "$REAL"; : > "$REAL/MEMORY.md"
for n in a.md b.md c.md; do printf 'body of %s\n' "$n" > "$REAL/$n"; printf -- '- [%s](%s) — hook\n' "$n" "$n" >> "$REAL/MEMORY.md"; done
FCFG17="$B/cfg17"; S17="$(linked_store "$FCFG17" "$REAL")"; stub 5000 24000
run17() { CLAUDE_CONFIG_DIR="$FCFG17" sh "$T" --root "$S17" --index "$S17/MEMORY.md" "$@" 2>&1; }
r="$(run17)"
t_eq "17a a symlinked store counts its notes" 3 "$(field "$r" notes)"
t_hasnt "17b a symlinked store does not report its index as dangling" "$r" 'DANGLING'
t_eq "17c a symlinked store reports its real corpus bytes" 39 "$(field "$r" 'store bytes (recall corpus)')"
t_exit "17d --strict on a healthy symlinked store" 0 run17 --strict
t_has "17e --json carries the real note count" "$(run17 --json)" '"notes":3'
EMPTY="$B/empty-store"; mkdir -p "$EMPTY"; printf -- '- [gone.md](gone.md) — hook\n' > "$EMPTY/MEMORY.md"
S17B="$(linked_store "$B/cfg17b" "$EMPTY")"
t_has "17f a link to a store genuinely missing its notes still reports DANGLING" \
  "$(CLAUDE_CONFIG_DIR="$B/cfg17b" sh "$T" --root "$S17B" --index "$S17B/MEMORY.md" 2>&1)" 'DANGLING'
t_done
