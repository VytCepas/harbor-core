#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: the rule-pack registry — IJ1's scope enum (harbor#599),
# IJ2..IJ5 against the repo, the box and the disk (harbor#173, #177, #181), and M2's declared
# governed-repo stand-downs (harbor#581). Each arm pairs a finding with the silence beside it (#667).
# The registry and the project pack folders are the private layer's (harbor#1149): every arm that needs
# them builds a fixture layer and names it with HARBOR_SCOPE_PRIVATE, never the box's own.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"

t_section "IJ1: scope: is a frozen enum, and box needs a tool call (harbor#599)"
_ij1s() { # <scope> <event> → the IJ1 output for a root holding that one pack
  rm -rf "$TMP/ij1s"; mkdir -p "$TMP/ij1s/bin" "$TMP/ij1s/context-rules/demo"
  printf -- '---\ndescription: a demo\nevent: %s\nwhen: always\nscope: %s\n---\nbody\n' "$2" "$1" > "$TMP/ij1s/context-rules/demo/demo.md"
  lint1 IJ1 "$TMP/ij1s" || true
}
t_hasnt "scope: box on PreToolUse is valid" "$(_ij1s box PreToolUse)" 'VIOLATION [context.pack-shape]'
t_has "scope: box on SessionStart can never reach a tree" "$(_ij1s box SessionStart)" \
  'scope: box on SessionStart, which carries no tool call'
t_has "a near-miss scope value is refused" "$(_ij1s ambient PreToolUse)" 'declares scope: ambient'
_ij1p() { # <relpath under the private inject.d> <event> → IJ1's output for a fixture layer holding that one pack
  rm -rf "$TMP/ij1p" "$TMP/ij1p-root"; mkdir -p "$TMP/ij1p-root" "$TMP/ij1p/inject.d/$(dirname "$1")"
  printf -- '---\nid: demo\nevent: %s\nwhen: always\n---\nbody\n' "$2" > "$TMP/ij1p/inject.d/$1"
  HARBOR_SCOPE_PRIVATE="$TMP/ij1p" lint1 IJ1 "$TMP/ij1p-root" || true
}
t_hasnt "a well-formed private repo pack is valid" "$(_ij1p demo/10-demo.md PreToolUse)" 'VIOLATION [context.pack-shape]'
t_has "a private pack on an event the engine never sees is refused, named as private" "$(_ij1p demo/10-demo.md Bogus)" \
  'declares an event the engine never sees (Bogus): private:inject.d/demo/10-demo.md'
t_has "a private pack one level off is a pack nothing reads" "$(_ij1p box/sub/10-demo.md PreToolUse)" \
  'nothing installs or reads it'

t_section "IJ1: a tracked pack has a description (harbor#957)"
_ij1d() { # <front-matter extra line, may be empty> → IJ1's output for a tracked pack with that line
  rm -rf "$TMP/ij1d"; mkdir -p "$TMP/ij1d/bin" "$TMP/ij1d/context-rules/demo"
  printf -- '---\n%sevent: PreToolUse\nwhen: always\n---\nbody\n' "$1" > "$TMP/ij1d/context-rules/demo/${2:-demo}.md"
  lint1 IJ1 "$TMP/ij1d" || true
}
t_has "a tracked pack with no description is refused" "$(_ij1d '')" 'pack has no description: context-rules/demo/demo.md'
t_has "an empty description is refused too" "$(_ij1d 'description:
')" 'pack has no description: context-rules/demo/demo.md'
t_hasnt "a described pack is valid" "$(_ij1d 'description: what it is for
')" 'VIOLATION [context.pack-shape]'
t_has "a private pack with none is a warning, not a violation" "$(_ij1p demo/10-demo.md PreToolUse)" \
  'ADVISORY [context.pack-shape] pack has no description: private:inject.d/demo/10-demo.md'

t_section "IJ1: the id is the file name and order is a key (D-43, harbor#1010)"
_ijv() { printf '%s\n' "$1" | grep 'VIOLATION \[context.pack-shape\]' || true; }
t_eq "a described rule with a derived id and an order is valid" "" "$(_ijv "$(_ij1d 'description: d
order: 20
')")"
_ijdesc='description: d
'
t_has "an NN- file name is refused" "$(_ij1d "$_ijdesc" 10-demo)" 'carries an NN- prefix'
t_has "an id: that repeats the file name is refused" "$(_ij1d 'description: d
id: demo
')" 'repeats its file name in id:'
t_eq "an id: that differs from the file name is kept" "" "$(_ijv "$(_ij1d 'description: d
id: other
')")"
t_has "an order: that is not a whole number is refused" "$(_ij1d 'description: d
order: soon
')" 'order: is not a whole number (soon)'
mkdir -p "$TMP/ij1d/inject.d/box"; printf -- '---\ndescription: d\nevent: PreToolUse\nwhen: always\n---\nb\n' > "$TMP/ij1d/inject.d/box/old.md"
t_has "a tracked rule in the retired inject.d/ is refused" "$(lint1 IJ1 "$TMP/ij1d" || true)" 'retired inject.d/ layout'
t_hasnt "...and the private layer's old layout is not judged by name" "$(_ij1p demo/10-demo.md PreToolUse)" 'carries an NN- prefix'

t_section "IJ2: the registry's second direction (harbor#177)"
IJR="$TMP/ij-root"; IJP="$TMP/ij-priv"; IJH="$TMP/ij-home"
mkdir -p "$IJR/inject.d/box" "$IJP/inject.d/box" "$IJP/inject.d/seeded" "$IJH/selfseeded/.claude/inject.d" "$IJH/barren" "$IJH/seeded" "$IJH/selfnew/context-rules/selfnew"
printf -- '---\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJH/selfnew/context-rules/selfnew/self.md"
printf -- '---\nid: seeded-pack\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJP/inject.d/seeded/10-seeded.md"
printf -- '---\nid: self-pack\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJH/selfseeded/.claude/inject.d/10-self.md"
printf '# name\tpath\tcovers\nseeded\t~/seeded\tpacks seeded from this repo\nselfseeded\t~/selfseeded\tpacks live in the project own tree\nbarren\t~/barren\tno packs anywhere\nselfnew\t~/selfnew\tits rules in context-rules/ (harbor#1010)\nabsent\t~/absent\tthe repo is not on this box\n' \
  > "$IJP/inject.d/box/projects.tsv"
OUT_IJ2="$(HOME="$IJH" HARBOR_SCOPE_PRIVATE="$IJP" lint1 IJ2 "$IJR" | grep -E '(VIOLATION|ADVISORY) \[context.registry-dirs\]')"
IJ2_ROW='projects.tsv row'
t_has "a row with no packs in EITHER home is reported" "$OUT_IJ2" "$IJ2_ROW 'barren' has no packs"
t_hasnt "a row whose packs live in the project's OWN tree stays silent" "$OUT_IJ2" 'selfseeded'
t_hasnt "a row seeded from this repo stays silent" "$OUT_IJ2" "$IJ2_ROW 'seeded'"
t_hasnt "a repo absent from this box is never a violation" "$OUT_IJ2" "VIOLATION [context.registry-dirs] projects.tsv row 'absent'"
t_has "…it is UNDECIDABLE, and says so" "$OUT_IJ2" 'ADVISORY [context.registry-dirs] ~/absent is not on this box'
t_hasnt "a row whose rules live in its own context-rules/<repo>/ stays silent (harbor#1010)" "$OUT_IJ2" 'selfnew'
IJPN="$TMP/ij-privnew"; mkdir -p "$IJPN/context-rules/user" "$IJPN/context-rules/orphan2"
printf '# name\tpath\tcovers\n' > "$IJPN/context-rules/user/projects.tsv"
printf -- '---\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJPN/context-rules/orphan2/orphan2.md"
t_has "a new-layout private layer's registry and folders are compared (harbor#1010)" \
  "$(HOME="$IJH" HARBOR_SCOPE_PRIVATE="$IJPN" lint1 IJ2 "$IJR")" 'context-rules/orphan2/ has no row in projects.tsv'
mkdir -p "$IJP/inject.d/orphan"; printf -- '---\nid: orphan-pack\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJP/inject.d/orphan/10-orphan.md"
t_has "a private pack folder with no registry row is never seeded, and is reported" \
  "$(HOME="$IJH" HARBOR_SCOPE_PRIVATE="$IJP" lint1 IJ2 "$IJR")" 'inject.d/orphan/ has no row in projects.tsv'
rm -r "$IJP/inject.d/orphan"
IJN="$TMP/ij-noreg"; mkdir -p "$IJN/inject.d/box"
_ij2n="$(HOME="$IJH" HARBOR_SCOPE_PRIVATE="$IJN" lint1 IJ2 "$IJR")"
t_has "a private layer with no registry is a finding" "$_ij2n" "VIOLATION [context.registry-dirs] the private layer's inject.d/box/projects.tsv is missing"
_ij2x="$(HOME="$IJH" HARBOR_SCOPE_PRIVATE="$TMP/ij-no-layer-at-all" lint1 IJ2 "$IJR")"
t_hasnt "no private layer at all is not a violation" "$_ij2x" 'VIOLATION [context.registry-dirs]'
t_has "...and says it did not look, so the silence is not read as a pass" "$_ij2x" 'there is no registry to compare against the pack folders — not checked'

t_section "IJ4: a tracked pack is installed where the engine reads it (harbor#173)"
IJ4R="$TMP/ij4-root"; IJ4H="$TMP/ij4-home"; IJ4P="$TMP/ij4-priv"
mkdir -p "$IJ4R/context-rules/user" "$IJ4P/inject.d/box" "$IJ4P/inject.d/never" "$IJ4P/inject.d/good" "$IJ4P/inject.d/drifted" \
         "$IJ4H/never" "$IJ4H/good/.claude/inject.d" "$IJ4H/drifted/.claude/inject.d" "$IJ4H/cfg" "$IJ4H/cfg2/context-rules/user"
for _n in never good drifted; do
  printf -- '---\nid: %s-pack\nevent: SessionStart\nwhen: always\n---\n\nbody\n' "$_n" > "$IJ4P/inject.d/$_n/10-$_n.md"
done
cp "$IJ4P/inject.d/good/10-good.md" "$IJ4H/good/.claude/inject.d/"
cp "$IJ4P/inject.d/drifted/10-drifted.md" "$IJ4H/drifted/.claude/inject.d/"
printf 'tampered\n' >> "$IJ4H/drifted/.claude/inject.d/10-drifted.md"
printf '# name\tpath\tcovers\nnever\t~/never\ttracked but never seeded\ngood\t~/good\tseeded and current\ndrifted\t~/drifted\tseeded then edited in place\nabsent\t~/absent\tthe repo is not on this box\n' \
  > "$IJ4P/inject.d/box/projects.tsv"
ij4() { HOME="$IJ4H" HARBOR_ESTATE_ROOT="$IJ4H" HARBOR_SCOPE_PRIVATE="$IJ4P" CLAUDE_CONFIG_DIR="$IJ4H/$1" lint1 IJ4 "$IJ4R"; }
RAW_IJ4="$(ij4 cfg)"
OUT_IJ4="$(printf '%s\n' "$RAW_IJ4" | grep 'ADVISORY \[drift.pack-installed\]' || true)"
t_has "a tracked pack that was NEVER SEEDED is reported" "$OUT_IJ4" 'never pack is tracked but NEVER SEEDED'
t_has "a pack edited in place after seeding is DRIFT" "$OUT_IJ4" 'drifted pack has drifted'
t_hasnt "a correctly seeded pack stays silent" "$OUT_IJ4" 'good'
t_hasnt "a project absent from this box stays silent (IJ2 owns that)" "$OUT_IJ4" 'absent'
t_has "BOX packs tracked but never installed are reported" "$OUT_IJ4" 'BOX packs are tracked but NEVER INSTALLED'
printf -- '---\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJ4R/context-rules/user/core-box.md"
printf -- '---\nid: private-box\nevent: SessionStart\nwhen: always\n---\n\nbody\n' > "$IJ4P/inject.d/box/20-private-box.md"
cp -R "$IJ4R/context-rules/user/." "$IJ4H/cfg2/context-rules/user/"
t_has "a private box file missing from the install is DRIFT in the box tier" "$(ij4 cfg2 | grep 'ADVISORY \[drift.pack-installed\]')" 'the BOX packs have drifted'
cp "$IJ4P/inject.d/box/projects.tsv" "$IJ4P/inject.d/box/20-private-box.md" "$IJ4H/cfg2/context-rules/user/"
t_eq "BOX packs installed and current (core's and the private layer's) stay silent" "" "$(ij4 cfg2 | grep 'ADVISORY \[drift.pack-installed\].*BOX')"
printf 'edited\n' >> "$IJ4H/cfg2/context-rules/user/20-private-box.md"
t_has "a private box pack edited in place after install is DRIFT" "$(ij4 cfg2 | grep 'ADVISORY \[drift.pack-installed\]')" 'the BOX packs have drifted'
t_hasnt "IJ4 is advisory: it never emits a VIOLATION" "$RAW_IJ4" 'VIOLATION [drift.pack-installed]'

t_section "IJ3: every governed repo on this box has a registry row (harbor#181)"
IJ3H="$TMP/ij3-home"; IJ3R="$TMP/ij3-root"; IJ3P="$TMP/ij3-priv"
mkdir -p "$IJ3P/inject.d/box" "$IJ3R" "$IJ3H/registered/.git" "$IJ3H/registered/.claude" \
         "$IJ3H/unregistered/.git" "$IJ3H/unregistered/.agents" "$IJ3H/with-skills/.git" \
         "$IJ3H/with-skills/.claude/skills" "$IJ3H/plain-checkout/.git" "$IJ3H/not-a-repo/.claude"
printf '# name\tpath\tcovers\nregistered\t~/registered\ta project somebody registered\n' > "$IJ3P/inject.d/box/projects.tsv"
OUT_IJ3="$(HARBOR_ESTATE_ROOT="$IJ3H" HARBOR_SCOPE_PRIVATE="$IJ3P" lint1 IJ3 "$IJ3R" \
          | grep -E 'ADVISORY \[context.repo-registered\]|governed repo\(s\)')"
IJ3_UN='governed but unregistered:'
t_has "a governed repo with no registry row is reported" "$OUT_IJ3" "$IJ3_UN unregistered"
t_hasnt "a registered repo stays silent" "$OUT_IJ3" "$IJ3_UN registered"
t_hasnt "a PLAIN git checkout is not governed (the discriminator)" "$OUT_IJ3" 'plain-checkout'
t_hasnt "a .claude directory that is NOT a git repo is not reported" "$OUT_IJ3" 'not-a-repo'
t_has "the skills clause appears where skills exist" "$(printf '%s\n' "$OUT_IJ3" | grep "$IJ3_UN with-skills")" \
  'with-skills — and it carries .claude/skills'
t_hasnt "…and only there" "$(printf '%s\n' "$OUT_IJ3" | grep "$IJ3_UN unregistered")" 'carries'
t_has "the count names how many of how many" "$OUT_IJ3" '2 of 3 governed repo(s) are unregistered'

t_section "IJ5: every registry row still resolves to a directory"
IJ5H="$TMP/ij5-home"; IJ5R="$TMP/ij5-root"; IJ5P="$TMP/ij5-priv"; mkdir -p "$IJ5R" "$IJ5P/inject.d/box" "$IJ5H/alive"
ij5_reg() { printf '# name\tpath\tcovers\n%s' "$1" > "$IJ5P/inject.d/box/projects.tsv"; }
ij5() { HARBOR_ESTATE_ROOT="$IJ5H" HARBOR_SCOPE_PRIVATE="$IJ5P" lint1 IJ5 "$IJ5R" \
          | grep -E 'ADVISORY \[context.registry-resolves\]|registry row'; }
IJ5_DEAD='registry row points at nothing:'
ij5_reg 'alive	~/alive	a project that is here
ghost	~/ghost	a project that was renamed out from under this row
'
OUT_IJ5="$(ij5)"
t_has "a row pointing at nothing is reported when other rows resolve" "$OUT_IJ5" "$IJ5_DEAD ghost (~/ghost)"
t_hasnt "the row that DOES resolve is not reported" "$OUT_IJ5" "$IJ5_DEAD alive"
ij5_reg 'ghost	~/ghost	absent here
other	~/other	also absent here
'
_o="$(ij5)"
t_hasnt "with NO row resolving the rule stands down (a bare CI checkout)" "$_o" 'ADVISORY [context.registry-resolves]'
t_has "…and declines explicitly" "$_o" 'cannot tell a stale row from an absent checkout'
ij5_reg 'alive	~/alive	the only project
'
t_has "all rows resolving reports the count, not silence" "$(ij5)" 'all 1 registry row(s) resolve'

t_section "M2: governed-repo stand-downs are declared, and the five never yield (harbor#581)"
M2R="$TMP/m2"
m2_doc() { mkdir -p "$M2R/CONTRACTS"
  printf '# marker\n\n## What stands down inside a governed repo\n\n| site | via | tier | what | ticket |\n|---|---|---|---|---|\n%s\n## next\n\n| `bin/ignored.sh` | `floor_in_repo` | bogus | outside the section | — |\n' "$1" > "$M2R/CONTRACTS/marker.md"; }
m2_bin() { mkdir -p "$M2R/bin"; printf '#!/usr/bin/env sh\n%s\n' "$2" > "$M2R/bin/$1"; }
M2_OK='| `bin/guard-x.sh` | `floor_in_repo` | project | a policy | — |
| `bin/hook-y.sh` | `floor_engine_stand_down` | constitutional | a gate | harbor#1 |'
rm -rf "$M2R"; mkdir -p "$M2R/bin"
m2_bin guard-x.sh 'if ! floor_in_repo; then echo armed; fi'
m2_bin hook-y.sh 'floor_engine_stand_down && exit 0'
m2_doc "$M2_OK"
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_hasnt "every call declared is green" "$_m2o" 'VIOLATION [scope.stand-down-declared]'
t_eq "…and exits 0" "exit 0" "exit $_m2rc"
t_has "…and says what it counted" "$_m2o" '2 stand-down site(s) declared, 1 of them'
m2_bin new-z.sh 'floor_in_repo && exit 0'
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "an undeclared stand-down is reported" "$_m2o" 'VIOLATION [scope.stand-down-declared] bin/new-z.sh stands down via floor_in_repo'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"
rm -f "$M2R/bin/new-z.sh"
m2_bin wired-v.sh 'floor_repo_wires some_guard some-plugin || echo armed'
t_has "an undeclared floor_repo_wires stand-down is reported (harbor#954)" "$(lint1 M2 "$M2R")" \
  'VIOLATION [scope.stand-down-declared] bin/wired-v.sh stands down via floor_repo_wires'
rm -f "$M2R/bin/wired-v.sh"
m2_bin doc-only.sh '# we used to call floor_in_repo here'
t_hasnt "a call named only in a COMMENT is not a stand-down" "$(lint1 M2 "$M2R")" 'doc-only.sh'
rm -f "$M2R/bin/doc-only.sh"
m2_doc '| `bin/guard-x.sh` | `floor_in_repo` | project | a policy | — |
| `bin/hook-y.sh` | `floor_engine_stand_down` | constitutional | a gate | — |'
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "a constitutional stand-down with no ticket is reported" "$_m2o" \
  'VIOLATION [scope.stand-down-declared] bin/hook-y.sh is a CONSTITUTIONAL stand-down with no ticket'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"
m2_doc '| `bin/guard-x.sh` | `floor_in_repo` | policy | a policy | — |
| `bin/hook-y.sh` | `floor_engine_stand_down` | constitutional | a gate | harbor#1 |'
_m2o="$(lint1 M2 "$M2R")"
M2_TIER='declares tier'
t_has "a tier outside the four is reported" "$_m2o" "$M2_TIER 'policy'"
t_hasnt "a row outside the section is not read (its site)" "$_m2o" 'ignored.sh'
t_hasnt "a row outside the section is not read (its tier)" "$_m2o" "$M2_TIER 'bogus'"
m2_doc "$M2_OK
| \`bin/gone.sh\` | \`floor_in_repo\` | engine | removed | — |"
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "a row whose call is gone is reported as stale" "$_m2o" \
  'declares bin/gone.sh standing down via floor_in_repo, and no such call exists'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"
m2_doc "$M2_OK"
mkdir -p "$M2R/inject.d/box"
printf '#!/usr/bin/env sh\n. "$(dirname "$0")/../../bin/guard-lib.sh"\nfloor_in_repo || exit 0\n' > "$M2R/inject.d/box/pack.sh"
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "a script outside bin/ that sources guard-lib is reported" "$_m2o" 'inject.d/box/pack.sh sources guard-lib.sh from outside bin/'
t_eq "…and fails the run (no subshell count loss)" "exit 1" "exit $_m2rc"
rm -rf "$M2R/inject.d"

t_section "M2: a row covers a file and a function, and a script need not end in .sh (PR #678)"
m2_bin guard-x.sh 'if ! floor_in_repo; then echo armed; fi
floor_in_repo && exit 0'
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "a SECOND call in a declared file cannot hide behind the first row" "$_m2o" 'bin/guard-x.sh calls floor_in_repo 2 times'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"
m2_bin guard-x.sh 'if ! floor_in_repo; then echo armed; fi'
m2_bin tool-w '#!/bin/sh
floor_in_repo && exit 0'
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "an EXTENSIONLESS script in bin/ is scanned by its shebang" "$_m2o" 'VIOLATION [scope.stand-down-declared] bin/tool-w stands down via floor_in_repo'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"
rm -f "$M2R/bin/tool-w"
printf 'notes: floor_in_repo && exit 0 is how the guards stand down\n' > "$M2R/bin/NOTES"
t_hasnt "a file with no shell shebang is not a script" "$(lint1 M2 "$M2R")" 'bin/NOTES'
rm -f "$M2R/bin/NOTES"
mkdir -p "$M2R/hooks"
printf '#!/usr/bin/env sh\n. "$(dirname "$0")/../bin/guard-lib.sh"\nfloor_in_repo || exit 0\n' > "$M2R/hooks/pre-commit"
_m2o="$(lint1 M2 "$M2R")"; _m2rc=$?
t_has "an EXTENSIONLESS hook outside bin/ that sources guard-lib is reported" "$_m2o" 'hooks/pre-commit sources guard-lib.sh from outside bin/'
t_eq "…and fails the run" "exit 1" "exit $_m2rc"

t_done
