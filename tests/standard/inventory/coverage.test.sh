#!/usr/bin/env sh
# bin/standard-inventory.sh coverage (harbor#978): what the standard does not reach on the box. Each of the three conditions is
# planted on a throwaway tree, config dir and PATH folder, watched red, then cleared; nothing reads the operator's box.
. "$(dirname "$0")/../../lib/core.sh"; t_init
B="$T_TMP/box"; H="$B/home"
TAB="$(printf '\t')"
SURF_HDR="id${TAB}renderer${TAB}family${TAB}checked${TAB}example${TAB}rule${TAB}view${TAB}note"
mkbox() {
  rm -rf "$B"; mkdir -p "$B/root/bin" "$B/root/standards/naming" "$B/root/contracts" "$B/cfg/context-rules/user" "$B/cfg/bin" \
    "$H/.local/bin" "$H/.local/share/uv/tools/x/bin" "$B/alpha" "$B/outer/inner" "$B/access"
  cp "$T_ROOT/bin/standard-inventory.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/standard-register.sh" "$B/root/bin/"
  cp "$T_ROOT/standards/naming/schemas.tsv" "$B/root/standards/naming/"
  { printf '# fixture\n# standard_version: 2.0.0\n%s\n' "$SURF_HDR"
    printf 'owned\tkebab\t-\tno\t-\t-\t-\tno checker yet; owner #12 by 2026-12-01\n'
    printf 'checked\tkebab\t-\tcheck\tx\t-\t-\tjudged by the lint\n'; } > "$B/root/standards/naming/surfaces.tsv"
  { printf '# fixture\n# standard_version: 2.0.0\nid\tkind\tpath\theader\tnote\n'
    printf 'rule-a\trule-data\t{cfg}/a.d/*.tsv\tnone\tpack rows land in a.d\n'
    printf 'rule-b\trule-data\t{rules}/b.tsv\trow\tcore ships b.tsv\n'
    printf 'rule-c\trule-data\t{access}/routes.tsv\tnone\tthe register maps routes\n'
    printf 'rule-off\trule-data\t{cfg}/off.tsv\tnone\tnever installed here\n'
    printf 'uv\ttool-origin\t{home}/.local/share/uv/\t-\tuv tool install\n'; } > "$B/root/contracts/standard-coverage.tsv"
  # rules a, b and c installed with data to judge; rule-off not installed
  for r in rule-a rule-b rule-c; do printf -- '---\nevent: PreToolUse\n---\n' > "$B/cfg/context-rules/user/$r.md"; done
  mkdir -p "$B/cfg/a.d"; printf '# a comment\nrow\tone\n' > "$B/cfg/a.d/p.tsv"
  printf 'id\tx\nr1\ty\n' > "$B/cfg/context-rules/user/b.tsv"
  printf 'pattern\tcard\n' > "$B/access/routes.tsv"
  # a repo that tracks one tool; a registered root that is not a repo, holding one
  printf '#!/bin/sh\necho alpha\n' > "$B/alpha/tool-a"; chmod +x "$B/alpha/tool-a"
  git -C "$B/alpha" init -q && git -C "$B/alpha" add . && git -C "$B/alpha" -c user.name=t -c user.email=t@t commit -qm x
  printf '#!/bin/sh\necho inner\n' > "$B/outer/inner/tool-i"; chmod +x "$B/outer/inner/tool-i"
  git -C "$B/outer/inner" init -q && git -C "$B/outer/inner" add . && git -C "$B/outer/inner" -c user.name=t -c user.email=t@t commit -qm x
  printf 'alpha\t%s\nouter\t%s\n' "$B/alpha" "$B/outer" > "$B/repos"
  ln -s "$B/alpha/tool-a" "$H/.local/bin/tool-a"                # a link into a repo that tracks it
  cp "$B/alpha/tool-a" "$B/cfg/bin/tool-a-copy"                 # an installed copy: the bytes are committed
  ln -s "$B/outer/inner/tool-i" "$H/.local/bin/tool-i"          # under a root that is not itself a repo
  printf '#!/bin/sh\necho uv\n' > "$H/.local/share/uv/tools/x/bin/x"; chmod +x "$H/.local/share/uv/tools/x/bin/x"
  ln -s "$H/.local/share/uv/tools/x/bin/x" "$H/.local/bin/x"    # a package manager's
  printf 'data\n' > "$B/cfg/bin/notes.tsv"                      # not executable: not a tool
}
cov() { HOME="$H" sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --config-dir "$B/cfg" \
  --local-bin "$H/.local/bin" --access "$B/access" --today 2026-11-13 coverage 2>&1; }

t_section "a clean box: every condition met, nothing new, exit 0"
mkbox
out="$(cov)"
t_has "the clean fixture has no finding" "$out" '0 finding(s)'
t_has "every planted thing was judged" "$out" 'judged 1 unchecked surface(s), 3 installed rule(s) with declared data, 3 PATH tool(s)'
t_exit "a clean run exits 0" 0 sh -c "HOME='$H' sh '$B/root/bin/standard-inventory.sh' --root '$B/root' --repos '$B/repos' --config-dir '$B/cfg' --local-bin '$H/.local/bin' --access '$B/access' --today 2026-11-13 coverage"

t_section "condition 1: a surface with checked = no needs an owner issue and a date that has not passed"
printf 'bare\tkebab\t-\tno\t-\t-\t-\treview only\n' >> "$B/root/standards/naming/surfaces.tsv"
printf 'noowner\tkebab\t-\tno\t-\t-\t-\towner none, #996 by 2026-12-01\n' >> "$B/root/standards/naming/surfaces.tsv"
printf 'late\tkebab\t-\tno\t-\t-\t-\towner harbor#7 by 2026-10-01\n' >> "$B/root/standards/naming/surfaces.tsv"
out="$(cov)"
t_has "no owner and no date is red" "$out" 'surface:bare  surfaces.tsv row bare is checked = no and its note names no owner issue and no date'
t_has "owner none is no owner" "$out" 'surface:noowner  surfaces.tsv row noowner is checked = no and its note names no owner issue:'
t_has "a passed date is red" "$out" 'its date 2026-10-01 has passed'
t_hasnt "an owned, dated row is not" "$out" 'surface:owned'
t_hasnt "a checked surface is not judged" "$out" 'surface:checked'
t_exit "a new finding exits 1" 1 sh -c "HOME='$H' sh '$B/root/bin/standard-inventory.sh' --root '$B/root' --repos '$B/repos' --config-dir '$B/cfg-1' --local-bin '$H/.local/bin' --access '$B/access' --today 2026-11-13 coverage"

t_section "condition 2: an installed rule whose data is missing or holds no row"
mkbox
rm -f "$B/cfg/a.d/p.tsv"
printf 'id\tx\n' > "$B/cfg/context-rules/user/b.tsv"
out="$(cov)"
t_has "missing data is red" "$out" 'rule:rule-a  context rule rule-a is installed and {cfg}/a.d/*.tsv does not exist'
t_has "a header row alone is no row" "$out" 'rule:rule-b  context rule rule-b is installed and {rules}/b.tsv holds no row'
t_hasnt "a rule that is not installed is not judged" "$out" 'rule:rule-off'
: > "$B/access/routes.tsv"
t_has "an empty access table is red too" "$(cov)" 'rule:rule-c'
mkbox
out="$(HOME="$H" sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --config-dir "$B/cfg" --local-bin "$H/.local/bin" --access "$B/none" --today 2026-11-13 coverage 2>&1)"
t_has "an access folder that does not exist leaves the rule nothing to read" "$out" 'rule:rule-c'

t_section "condition 3: a PATH tool whose bytes no registered repo holds"
mkbox
printf '#!/bin/sh\necho mine\n' > "$H/.local/bin/stray"; chmod +x "$H/.local/bin/stray"
printf '#!/bin/sh\necho changed\n' >> "$B/alpha/tool-a"
out="$(cov)"
t_has "an untracked tool is red" "$out" 'tool:~/.local/bin/stray  no registered repo holds the bytes of ~/.local/bin/stray:'
t_has "a tracked tool changed since its commit is red, named with where it resolves" "$out" "tool:~/.local/bin/tool-a  no registered repo holds the bytes of ~/.local/bin/tool-a (it resolves to $(cd "$B/alpha" && pwd -P)/tool-a)"
t_hasnt "the installed copy of the committed bytes is home" "$out" 'tool-a-copy'
t_hasnt "a tool in a repo one level under a registered root is home" "$out" 'tool:~/.local/bin/tool-i'
t_hasnt "a package manager's tool is not ours" "$out" 'tool:~/.local/bin/x'
t_hasnt "a data file in the config bin is not a tool" "$out" 'notes.tsv'
printf 'ghost\t%s\n' "$B/missing" > "$B/repos"
t_exit "no registered repo can be read: unchecked, exit 3" 3 sh -c "HOME='$H' sh '$B/root/bin/standard-inventory.sh' --root '$B/root' --repos '$B/repos' --config-dir '$B/cfg' --local-bin '$H/.local/bin' --access '$B/access' --today 2026-11-13 coverage"

t_section "the report is the delta and the ages, and the receipt is what the findings channel files"
mkbox
printf '#!/bin/sh\necho mine\n' > "$H/.local/bin/stray"; chmod +x "$H/.local/bin/stray"
cov > /dev/null
t_has "the receipt is red and names the subject" "$(cat "$B/cfg/cache/checks/standard.coverage.json")" '"tool:~/.local/bin/stray"'
out="$(HOME="$H" sh "$B/root/bin/standard-inventory.sh" --root "$B/root" --repos "$B/repos" --config-dir "$B/cfg" --local-bin "$H/.local/bin" --access "$B/access" --today 2026-11-20 coverage 2>&1)"
t_has "a second run files nothing new and gives the age" "$out" 'standing 1 finding(s) already filed, oldest 7 day(s): tool:~/.local/bin/stray'
rm -f "$H/.local/bin/stray"
t_has "a cleared finding is reported fixed" "$(cov)" 'fixed    tool:~/.local/bin/stray'
t_red check.standard.coverage   # the falsifier its controls.tsv row names (harbor#1422)

t_done
