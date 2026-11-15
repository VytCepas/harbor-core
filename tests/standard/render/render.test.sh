#!/usr/bin/env sh
# bin/standard-render-check.sh (harbor#967 done-when 1 and 2): a rendered repo is green when its names carry no finding, AGENTS.md
# names only paths that exist, and README.md has the four newcomer sections; each is red on its own fault, and 3 where unasked.
. "$(dirname "$0")/../../lib/core.sh"; t_init
RC="$T_ROOT/bin/standard-render-check.sh"
R="$T_TMP/repo"
mkr() { # a rendered repo that passes: its naming gate says 0, an AGENTS.md naming real paths, a README with the four sections
  rm -rf "$R"; mkdir -p "$R/docs" "$R/bin" "$R/gates"
  sh "$T_ROOT/bin/standard-vendor.sh" "$R" >/dev/null 2>&1
  printf 'echo "naming-check: 0 finding(s) now, 0 baselined, 0 new, 0 stale"\n' > "$R/gates/naming-check.sh"
  printf '# demo\n\n## What this is\n\nx\n\n## Where the code lives\n\nx\n\n## How to run the tests\n\nx\n\n## Where decisions are\n\nx\n' > "$R/README.md"
  printf '# demo\n\nRead `docs/index.md` and run `bin/build.sh`. Branches look like `<type>/<KEY>-<n>-<slug>`; `/help` is a command.\n' > "$R/AGENTS.md"
  printf '# index\n' > "$R/docs/index.md"; printf '#!/bin/sh\n' > "$R/bin/build.sh"
  git -C "$R" init -q 2>/dev/null; git -C "$R" add -A 2>/dev/null
}
run() { sh "$RC" "$R" 2>&1; }

t_section "a repo that passes is green"
mkr; out="$(run)"; rc=$?
t_eq "exit 0" 0 "$rc"; t_has "all three questions asked" "$out" "3 ok, 0 failed"

t_section "an AGENTS.md line naming an absent path is red, and names it"
mkr; printf 'Keep notes in `docs/missing/notes.md`.\n' >> "$R/AGENTS.md"
out="$(run)"; rc=$?
t_eq "exit 1" 1 "$rc"; t_has "names the path" "$out" "docs/missing/notes.md"
mkr; printf 'Edit `docs/index.md`, then `src/`.\n' >> "$R/AGENTS.md"; out="$(run)"
t_has "a directory that is absent is red too" "$out" "names src/"

t_section "a README without one of the four sections is red"
mkr; sed 's/^## Where decisions are$/## Notes/' "$R/README.md" > "$R/r" && mv "$R/r" "$R/README.md"
out="$(run)"; rc=$?
t_eq "exit 1" 1 "$rc"; t_has "names the section" "$out" "where decisions are"

t_section "a name the standard rejects is red"
mkr; rm -r "$R/gates"; printf 'x\n' > "$R/Bad_Name.md"; git -C "$R" add -A 2>/dev/null
out="$(run)"; rc=$?
t_eq "exit 1" 1 "$rc"; t_has "says the names failed" "$out" "names: the vendored lint reports"

t_section "the repo's own naming gate decides when it has one"
mkr; printf 'echo "naming-check: 2 finding(s) now, 2 baselined, 0 new, 0 stale"\nexit 0\n' > "$R/gates/naming-check.sh"
out="$(run)"; rc=$?
t_eq "baselined findings are still advisories: exit 1" 1 "$rc"; t_has "quotes the count" "$out" "reports 2 finding(s)"
printf 'echo "naming-check: 0 finding(s) now, 0 baselined, 0 new, 0 stale"\nexit 0\n' > "$R/gates/naming-check.sh"
out="$(run)"; rc=$?
t_eq "zero is green" 0 "$rc"

t_section "a question that could not be asked is 3, never green"
mkr; rm "$R/AGENTS.md"; out="$(run)"; rc=$?
t_eq "no AGENTS.md: exit 3" 3 "$rc"
mkr; rm -r "$R/gates" "$R/vendor"; out="$(run)"; rc=$?
t_eq "no judge for the names: exit 3" 3 "$rc"
t_exit "no directory is usage (2)" 2 sh "$RC" "$T_TMP/none"
t_done
