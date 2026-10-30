#!/usr/bin/env sh
# bin/lint-leaks.sh and lint.leaks: the leak gate and its ratchets (harbor#1149).
# Each case is a throwaway git checkout and a throwaway private layer; HARBOR_SCOPE_PRIVATE always points at a temp dir.
# The "secret" below is a made-up word, never a real entity. The last case alone reads the real private layer's
# patterns (copied into a temp dir) and scans this checkout; it needs that layer and says so when it is absent.
LIVE_PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"  # before t_init unsets HARBOR_* and moves HOME
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
: # nopriv is deliberately never created
LK() { HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="${PV:-$T_TMP/nopriv}" sh "$T_ROOT/bin/lint-leaks.sh" "$2" ${3:+"$3"} 2>&1; }
rc() { HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="${PV:-$T_TMP/nopriv}" sh "$T_ROOT/bin/lint-leaks.sh" "$2" >/dev/null 2>&1; echo $?; }
PATH_HDR='id	kind	pattern	note'
# Real-looking home paths are built from parts so this file holds no literal one (an export scan of the tree counts tests).
UH=/Users; HH=/home
mk() { # <name> <core baseline> → a checkout: 2 home paths in core, a private-looking word, excluded dirs
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/contracts" "$_d/tests" "$_d/fixtures" "$_d/evals"
  printf "A=$UH/jdoe/x\nB=$HH/avery/y\nC=/Users/<u>/z\n" > "$_d/bin/a.sh"
  printf 'the Zorblax client\nzorblaxion is not it\n' > "$_d/README.md"
  printf "T=$UH/jdoe/x zorblax\n" | tee "$_d/tests/t.sh" "$_d/fixtures/f.txt" "$_d/evals/e.txt" > /dev/null
  cp "$T_ROOT/bin/lint-leaks.sh" "$T_ROOT/bin/library-log.sh" "$_d/bin/"
  cp "$T_ROOT/contracts/leak-patterns.tsv" "$_d/contracts/"
  printf '%s\n' "$2" > "$_d/contracts/lint-leaks-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}
pv() { # <name> [leaks.tsv body lines...] → a private layer dir with a header and the given rows
  _p="$T_TMP/pv-$1"; mkdir -p "$_p"; shift
  { printf '%s\n' "$PATH_HDR"; [ $# -eq 0 ] || printf '%s\n' "$@"; } > "$_p/leaks.tsv"
  printf '%s' "$_p"
}

t_section "no private layer: the built-in patterns only"
unset PV; D="$(mk core 2)"
t_eq "two home paths count, the placeholder and the excluded dirs do not" "2" "$(LK "$D" --count core)"
t_eq "...and private is 0" "0" "$(LK "$D" --count private)"
t_has "--list names file:line:id" "$(LK "$D" --list)" "bin/a.sh:1:home-path"
for gone in tests/ fixtures/ evals/ "bin/a.sh:3"; do t_hasnt "...not $gone" "$(LK "$D" --list)" "$gone"; done
t_eq "an absent private layer is green" "0" "$(rc "$D" --check)"
t_has "...and says private was not checked" "$(LK "$D" --check)" "private patterns not checked"

t_section "the core ratchet: up is red, equal is green, down is green with advice"
D="$(mk coreeq 2)"; t_eq "equal is green" "0" "$(rc "$D" --check)"
D="$(mk coreup 1)"; t_eq "above is red" "1" "$(rc "$D" --check)"
t_has "...and says the count and the baseline" "$(LK "$D" --check)" "2 core leak occurrence(s) in the tree, baseline is 1"
D="$(mk coredown 9)"; t_eq "below is green" "0" "$(rc "$D" --check)"
t_has "...and tells you to lower the baseline" "$(LK "$D" --check)" "lower lint-leaks-baseline.txt to 2"
D="$(mk corenb x)"; t_eq "a non-numeric baseline is red" "1" "$(rc "$D" --check)"
D="$(mk coregrow 2)"; printf "cd $UH/jdoe/more\n" >> "$D/bin/a.sh"
t_eq "a third occurrence in a file already listed is red" "1" "$(rc "$D" --check)"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_SCOPE_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-leaks.sh" --check

t_section "each private kind matches, and its near-miss does not"
kinds() { # <kind> <pattern> <hit line> <near-miss line>
  PV="$(pv "k$1" "k1	$1	$2	n")"; D="$(mk "k$1" 2)"
  printf '%s\n' "$3" > "$D/bin/hit.txt"; printf '%s\n' "$4" > "$D/bin/near.txt"
  OUT="$(LK "$D" --list)"
  t_has "$1 matches" "$OUT" "bin/hit.txt:1:k1"
  t_hasnt "$1 near-miss is left alone" "$OUT" "bin/near.txt"
}
kinds literal "Wibble-Co" "owned by wibble-co ltd" "wibble co ltd"
kinds word "Zorb" "a Zorb client" "zorbing and zorbs"
kinds domain "wibble.test" "mail wibble.test now" "wibble-test or xwibble.test or wibbleXtest"
kinds email-domain "@wibble" "joe@wibble.test" "joe@wibbler.test or joe at wibble"
kinds regex 'ACCT-[0-9]{4}' "ref ACCT-1234" "ref acct-1234 or ACCT-12"
t_has "a domain also matches as a subdomain" "$(PV="$(pv sub 'k1	domain	wibble.test	n')"; D="$(mk sub 2)"; printf 'x.wibble.test\n' > "$D/bin/h.txt"; LK "$D" --list)" "bin/h.txt:1:k1"

t_section "terms.tsv client and system rows match as whole words, in any case"
PV="$T_TMP/pv-terms"; mkdir -p "$PV"
printf 'id\tclass\tpref\n# c\nzorblax\tclient\tz\nblipster\tsystem\tb\nsomeverb\tverb\tv\n' > "$PV/terms.tsv"
D="$(mk terms 2)"; printf 'about BLIPSTER here\nsomeverb blipsters\n' > "$D/bin/t.txt"
OUT="$(LK "$D" --list)"
t_has "a client term matches, any case" "$OUT" "README.md:1:terms.tsv:L"
t_has "a system term matches, any case" "$OUT" "bin/t.txt:1:terms.tsv:L"
t_hasnt "a verb term does not" "$OUT" "bin/t.txt:2:terms.tsv:L2"
t_hasnt "a longer word does not match a term" "$OUT" "README.md:2"
t_hasnt "...and the plural of a system term does not" "$OUT" "bin/t.txt:2"

t_section "a malformed private layer is a finding"
PV="$T_TMP/pv-bad"; mkdir -p "$PV"; D="$(mk bad 2)"
printf 'wrong\theader\n' > "$PV/leaks.tsv"
t_eq "a wrong header is red" "1" "$(rc "$D" --check)"
t_has "...and names the file" "$(LK "$D" --check)" "leaks.tsv line 1: the header is not"
printf '%s\nk1\tword\n' "$PATH_HDR" > "$PV/leaks.tsv"
t_has "a short row is named by line" "$(LK "$D" --check)" "leaks.tsv line 2: expected 4 columns, got 2"
printf '%s\nk1\tbogus\tx\tn\n' "$PATH_HDR" > "$PV/leaks.tsv"
t_has "an unknown kind is named" "$(LK "$D" --check)" "kind bogus is not"
printf '%s\nk1\tword\tx\tn\nk1\tword\ty\tn\n' "$PATH_HDR" > "$PV/leaks.tsv"
t_has "a repeated id is named" "$(LK "$D" --check)" "repeats the id of line 2"
printf '%s\nk1\tregex\t(\tn\n' "$PATH_HDR" > "$PV/leaks.tsv"
t_eq "a regex that does not compile is red" "1" "$(rc "$D" --check)"
printf 'nothing\there\n' > "$PV/terms.tsv"; rm "$PV/leaks.tsv"
t_has "a terms.tsv without id and class is named" "$(LK "$D" --check)" "terms.tsv line 1: the header has no id and class columns"
t_eq "--count is red on a malformed layer too" "1" "$(rc "$D" --count)"

t_section "the private ratchet, only when leaks-baseline.txt exists"
PV="$(pv rat 'k1	word	Zorblax	n')"; D="$(mk rat 2)"
t_has "no baseline file: noted, not red" "$(LK "$D" --check)" "private count (1) not ratcheted"
t_eq "...green" "0" "$(rc "$D" --check)"
printf '1\n' > "$PV/leaks-baseline.txt"; t_eq "equal is green" "0" "$(rc "$D" --check)"
printf '0\n' > "$PV/leaks-baseline.txt"; t_eq "above is red" "1" "$(rc "$D" --check)"
t_has "...and says private" "$(LK "$D" --check)" "1 private leak occurrence(s) in the tree, baseline is 0"
printf '5\n' > "$PV/leaks-baseline.txt"; t_eq "below is green" "0" "$(rc "$D" --check)"
t_has "...with advice" "$(LK "$D" --check)" "lower leaks-baseline.txt to 1"
printf 'x\n' > "$PV/leaks-baseline.txt"; t_eq "a non-numeric private baseline is red" "1" "$(rc "$D" --check)"

t_section "--zero is red on one match, from any source"
unset PV; D="$(mk z1 99)"; t_eq "a core match is red" "1" "$(rc "$D" --zero)"
D="$(mk z0 99)"; printf 'clean\n' > "$D/bin/a.sh"; ( cd "$D" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1
t_eq "no match anywhere is green" "0" "$(rc "$D" --zero)"
PV="$(pv z 'k1	word	Zorblax	n')"; t_eq "one private match is red" "1" "$(rc "$D" --zero)"
t_has "...and says how to list them" "$(LK "$D" --zero)" "--list names each file:line and pattern id"

t_section "privacy: no mode prints a private pattern's text"
PV="$(pv priv 'secret-id	literal	Qzxv-Hidden-Name	n' 'rx	regex	Hidd[e]n-Rx[0-9]	n')"
printf 'id\tclass\tpref\nplumbus\tclient\tp\n' > "$PV/terms.tsv"
D="$(mk priv 1)"; printf 'Qzxv-Hidden-Name and Hidden-Rx7 and plumbus\n' > "$D/bin/p.txt"
printf '1\n' > "$PV/leaks-baseline.txt"
ALL="$(for m in --count --list --check --zero; do LK "$D" "$m"; done)"
t_has "the ids are printed" "$ALL" "secret-id"
for needle in Qzxv Hidden-Name 'Hidden-Rx7' 'Hidd\[e\]n' plumbus; do t_hasnt "...never $needle" "$ALL" "$needle"; done

t_section "the allow-list forgives an exact placeholder, never a real-looking name"
unset PV; D="$(mk al 2)"
printf 'P=/Users/probe/a Q=/home/stranger/b\n' > "$D/bin/ph.sh"
t_eq "placeholder usernames add nothing to the count" "2" "$(LK "$D" --count core)"
t_hasnt "...and are not listed" "$(LK "$D" --list)" "bin/ph.sh"
t_eq "...so the ratchet stays green" "0" "$(rc "$D" --check)"
D="$(mk alreal 2)"; printf "P=$UH/mwilliams/a\n" > "$D/bin/real.sh"
t_eq "a planted real-looking username is counted" "3" "$(LK "$D" --count core)"
t_has "...and listed" "$(LK "$D" --list)" "bin/real.sh:1:home-path"
t_eq "...and the ratchet is red" "1" "$(rc "$D" --check)"
D="$(mk alnear 2)"; printf "A=$UH/probe2/a B=$UH/PROBE/b C=$HH/probe/c\n" > "$D/bin/near.sh"
t_eq "an allow row is the exact text: a longer, upper-case or other-root name still counts" "5" "$(LK "$D" --count core)"
D="$(mk aldrop 2)"; printf 'P=/Users/zed/a\n' > "$D/bin/ph.sh"
t_eq "with its row, the placeholder is free" "2" "$(LK "$D" --count core)"
grep -v 'allow-home-zed' "$D/contracts/leak-patterns.tsv" > "$D/contracts/lp.new"; mv "$D/contracts/lp.new" "$D/contracts/leak-patterns.tsv"
t_eq "removing that one allow row counts the placeholder" "3" "$(LK "$D" --count core)"
t_eq "...and turns the ratchet red" "1" "$(rc "$D" --check)"
D="$(mk albad 9)"; cp "$D/contracts/leak-patterns.tsv" "$T_TMP/lp.keep"
printf 'allow-bad\tallow\tno-equals-sign\tn\n' >> "$D/contracts/leak-patterns.tsv"
t_has "an allow pattern without <id>=<text> is named" "$(LK "$D" --check)" "an allow pattern is <pattern-id>=<exact matched text>"
PV="$(pv alpriv "p1	allow	home-path=$UH/jdoe/	n")"; cp "$T_TMP/lp.keep" "$D/contracts/leak-patterns.tsv"
t_has "an allow row in the private layer is a finding" "$(LK "$D" --check)" "kind allow is for the core file only"
t_eq "...and it forgives nothing" "2" "$(HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$PV" sh "$T_ROOT/bin/lint-leaks.sh" --count core 2>/dev/null)"
unset PV
# An allow row names one pattern: the same text under another core id still counts. The pattern file sits outside the checkout.
{ cat "$T_ROOT/contracts/leak-patterns.tsv"
  printf "alt-home\tregex\t$UH/qa-[a-z]+/\tn\nallow-qa\tallow\thome-path=$UH/qa-probe/\tn\n"; } > "$T_TMP/lp-scope.tsv"
D="$(mk alscope 2)"; printf "P=$UH/qa-probe/a\n" > "$D/bin/ph.sh"
t_eq "an allow row forgives only the pattern it names" "3" "$(HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$T_TMP/nopriv" LEAKS_CORE_PATTERNS="$T_TMP/lp-scope.tsv" sh "$T_ROOT/bin/lint-leaks.sh" --count core 2>/dev/null)"
FU=fixuser; export LEAKS_OWN_USER="$FU"
D="$(mk alown 2)"; printf "P=$UH/$FU/a\n" > "$D/bin/me.sh"
printf "allow-own\tallow\thome-path=$UH/$FU/\tn\n" >> "$D/contracts/leak-patterns.tsv"
t_has "an allow row naming the operator is a finding" "$(LK "$D" --check)" "allow row allow-own would forgive the operator's own user name"
t_eq "...it forgives nothing: the path and the row's own line both count" "4" "$(HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$T_TMP/nopriv" sh "$T_ROOT/bin/lint-leaks.sh" --count core 2>/dev/null)"
t_hasnt "...and the user name is never printed" "$(LK "$D" --check)" "$FU"
t_eq "...and the ratchet is red" "1" "$(rc "$D" --check)"
D="$(mk alownc 2)"; printf "P=$UH/FIXUSER/a\n" > "$D/bin/me.sh"
printf "allow-own\tallow\thome-path=$UH/FIXUSER/\tn\n" >> "$D/contracts/leak-patterns.tsv"
t_has "...in any case" "$(LK "$D" --check)" "would forgive the operator's own user name"
D="$(mk alpvt 2)"; PV="$(pv alpvt "p1	word	zorblax	n")"
printf "P=$UH/zorblax/a\n" > "$D/bin/me.sh"
printf "allow-pv\tallow\thome-path=$UH/zorblax/\tn\n" >> "$D/contracts/leak-patterns.tsv"
ALL="$(LK "$D" --check)"
t_has "an allow row matching a private pattern is a finding that names the pattern id" "$ALL" "allow row allow-pv would forgive private pattern p1"
t_hasnt "...and never its text" "$ALL" "zorblax"
t_eq "...and it forgives nothing" "4" "$(HARBOR_SCOPE_ROOT="$D" HARBOR_SCOPE_PRIVATE="$PV" sh "$T_ROOT/bin/lint-leaks.sh" --count core 2>/dev/null)"
unset PV LEAKS_OWN_USER

commit() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm y ) >/dev/null 2>&1; }
# planted <runner> <label> <file> <text> <id>: green before, red with the text in <file>, green once it is removed.
planted() {
  t_eq "$2: green before" "0" "$($1 "$D" --zero >/dev/null 2>&1; echo $?)"
  printf '%s\n' "$4" > "$D/$3"; git -C "$D" add -A
  t_eq "$2: red with it" "1" "$($1 "$D" --zero >/dev/null 2>&1; echo $?)"
  t_has "...listed as $5" "$($1 "$D" --list 2>&1)" "$3:1:$5"
  rm -f "$D/$3"; git -C "$D" add -A
  t_eq "...green once removed" "0" "$($1 "$D" --zero >/dev/null 2>&1; echo $?)"
}
RT() { HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="${PV:-$T_TMP/nopriv}" sh "$T_ROOT/bin/lint-leaks.sh" "$2" ${3:+"$3"}; }
EX() { LEAKS_EXPORT=1 HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="${PV:-$T_TMP/nopriv}" sh "$T_ROOT/bin/lint-leaks.sh" "$2" ${3:+"$3"}; }

t_section "a word ends at _ and a domain at -, so a joined id is a hit (harbor#1149)"
PV="$(pv widen 'k1	word	Zorb	n' 'k2	domain	wibble.test	n')"
D="$(mk widen 99)"; printf 'clean\n' > "$D/bin/a.sh"; commit "$D"
planted RT "a word inside an underscore-joined id" bin/w.txt "dataset X_Zorb_LT" k1
planted RT "a word ending a snake_case name, any case" bin/w.txt "table_ZORB" k1
planted RT "a domain followed by a hyphen" bin/d.txt "host flow.wibble.test-x-ABC" k2
printf 'zorbing_x xzorb_y zorbs_LT\nxwibble.test-y wibble.tester\n' > "$D/bin/near.txt"
t_eq "...a longer word or domain is still not a hit" "0" "$(RT "$D" --count private 2>/dev/null)"

t_section "export mode counts the running user's name where home-path does not (harbor#1149)"
unset PV; FU=fixuser; export LEAKS_OWN_USER="$FU"
D="$(mk own 99)"; printf 'clean\n' > "$D/bin/a.sh"; rm -rf "$D/tests" "$D/fixtures" "$D/evals"; commit "$D"
planted EX "~user" bin/o.txt "see ~$FU/notes" own-user
planted EX "an encoded -Users-user project dir" bin/o.txt "cd -Users-$FU-port-harbor" own-user
planted EX "an encoded -home-user project dir" bin/o.txt "cd -home-$FU-port" own-user
planted EX "a home path with no trailing slash" bin/o.txt "HOME=$HH/$FU" own-user
planted EX "a home path with a trailing slash is home-path's" bin/o.txt "cd $HH/$FU/x" home-path
printf 'cd %s/%s/x\n' "$HH" "$FU" > "$D/bin/o.txt"; git -C "$D" add -A
t_eq "...and counted once, not twice" "1" "$(EX "$D" --count core 2>/dev/null)"
printf '~%s/a\n' "$FU" > "$D/bin/o.txt"; git -C "$D" add -A
t_eq "a name given twice (id -un and HOME agree) counts once" "1" "$(LEAKS_OWN_USER="$FU $FU" EX "$D" --count core 2>/dev/null)"
printf '~%s/a -Users-%s-p\n' "$FU" "$FU" > "$D/bin/o.txt"; git -C "$D" add -A
ALL="$(EX "$D" --list 2>&1; EX "$D" --zero 2>&1)"
t_has "the hit is named by id" "$ALL" "bin/o.txt:1:own-user"
t_hasnt "...and the user name is never printed" "$ALL" "$FU"
t_eq "the ratchet does not count it: export mode only" "0" "$(RT "$D" --count core 2>/dev/null)"
printf '~%sx -Users-%ss-p %s/%sx\n' "$FU" "$FU" "$HH" "$FU" > "$D/bin/o.txt"; git -C "$D" add -A
t_eq "a longer name is not the user" "0" "$(EX "$D" --count core 2>/dev/null)"
rm -f "$D/bin/o.txt"; git -C "$D" add -A; unset LEAKS_OWN_USER
EXH() { HOME="$T_TMP/h/fixhome" LEAKS_EXPORT=1 HARBOR_SCOPE_ROOT="$1" HARBOR_SCOPE_PRIVATE="$T_TMP/nopriv" sh "$T_ROOT/bin/lint-leaks.sh" "$2" ${3:+"$3"}; }
planted EXH "without LEAKS_OWN_USER, the name from HOME" bin/h.txt "see ~fixhome/x" own-user

t_section "lint.leaks runs the same check"
unset PV; D="$(mk lintok 2)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.leaks "$D")")"
D="$(mk lintbad 1)"
t_has "above the baseline the rule reports" "$(lint1 lint.leaks "$D")" "VIOLATION [lint.leaks]"

t_section "the live tree: no core-layer file matches a private pattern (harbor#967)"
# A core skill named a client and reached the public mirror: the ratchet counts private hits over dev and core alike,
# and only deploy push asks for zero in core. This asks it here, in export mode as deploy push does. Prints ids only.
if [ -f "$LIVE_PRIV/leaks.tsv" ] || [ -f "$LIVE_PRIV/terms.tsv" ]; then
  unset PV; LP="$T_TMP/pv-live"; mkdir -p "$LP"
  for f in leaks.tsv terms.tsv; do [ ! -f "$LIVE_PRIV/$f" ] || cp "$LIVE_PRIV/$f" "$LP/"; done
  IDS="|$(awk -F'\t' '!/^[ \t]*#/ && NF == 4 && $1 != "id" { printf "%s|", $1 }' "$LP/leaks.tsv" 2>/dev/null)"
  LEAKS_EXPORT=1 LEAKS_OWN_USER='' HARBOR_SCOPE_ROOT="$T_ROOT" HARBOR_SCOPE_PRIVATE="$LP" \
    sh "$T_ROOT/bin/lint-leaks.sh" --list 2>/dev/null > "$T_TMP/live.list"; LRC=$?
  t_eq "the gate read the live tree and the private patterns cleanly" "0" "$LRC"
  awk -v ids="$IDS" '{ id = $0; sub(/^[^:]*:[^:]*:/, "", id)
    if (index(ids, "|" id "|") || id ~ /^terms\.tsv:L[0-9]+$/) print }' "$T_TMP/live.list" > "$T_TMP/live.priv"
  cut -d: -f1 "$T_TMP/live.priv" | sort -u |
    HARBOR_SCOPE_ROOT="$T_ROOT" sh "$T_ROOT/bin/scope-layers.sh" --core > "$T_TMP/live.core" 2>/dev/null
  CORE_HITS="$(awk 'NR == FNR { c[$0] = 1; next } { split($0, F, ":") } F[1] in c' "$T_TMP/live.core" "$T_TMP/live.priv" | tr '\n' ' ')"
  t_eq "no core-layer file holds a private-layer match (fix: reword it; sh bin/lint-leaks.sh --list)" "" "$CORE_HITS"
else
  printf '  note: no private layer at %s: the live-tree case did not run\n' "$LIVE_PRIV" >&2
fi
t_done
