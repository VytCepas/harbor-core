#!/usr/bin/env sh
# skill.agent-architecture (harbor#1278): a skill that spawns agents names an architecture the register holds, and the register
# itself is sound. Each defect is planted in a fixture root, seen red, and its repair seen green.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
ID=skill.agent-architecture; FX="$T_TMP/aa"
TAB="$(printf '\t')"
HDR="id${TAB}case${TAB}roles${TAB}receives${TAB}returns${TAB}verified_by${TAB}stop_rule${TAB}method"
row() { printf '%s\n' "$1${TAB}c${TAB}$2${TAB}r${TAB}o${TAB}$3${TAB}s${TAB}${4:--}"; }
mk() { # <root> — a sound fixture: two roles, one architecture, one spawning skill that names it, one skill that spawns nothing
  rm -rf "$1"; mkdir -p "$1/contracts" "$1/skills/a" "$1/skills/b"
  printf 'role\tmodel\neffort\tx\nbuild\thaiku\nverify\topus\n' > "$1/contracts/agents.tsv"
  { printf '%s\n' "$HDR"; row dc 'verify*1' 'parent>verify' skills/a/SKILL.md; row fx 'build*1 verify*1@opus/high' 'build>verify'; } > "$1/contracts/agent-architectures.tsv"
  printf -- '---\nname: a\narchitecture: dc\n---\n\nSpawn one subagent per claim.\n' > "$1/skills/a/SKILL.md"
  printf -- '---\nname: b\n---\n\nReads a file and writes a summary.\n' > "$1/skills/b/SKILL.md"
}
red() { _o="$(viol "$ID" "$FX")"; t_has "red: $1" "$_o" "$2"; }
green() { t_eq "green: $1" "" "$(viol "$ID" "$FX")"; }

t_section "the shipped tree is green"
t_eq "no violation on this repo" "" "$(viol "$ID" "$T_ROOT")"
mk "$FX"; green "the sound fixture"

t_section "a skill that spawns agents"
mk "$FX"; printf -- '---\nname: a\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"
red "names no architecture" "skills/a/SKILL.md spawns agents and names no architecture"
printf -- '---\nname: a\narchitecture: dc\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"; green "naming one repairs it"
printf -- '---\nname: a\narchitecture: nope\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"
red "names an unknown architecture" "names architecture nope"
printf -- '---\nname: a\narchitecture: dc nope\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"
red "one good name does not cover a bad one" "names architecture nope"
printf -- '---\nname: a\narchitecture: all\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"
mk "$FX"; printf -- '---\nname: a\narchitecture: all\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"; green "all names every row"
printf -- '---\nname: a\narchitecture: dc\n---\n\nSpawn one subagent per claim.\n' > "$FX/skills/a/SKILL.md"
printf -- '---\nname: c\n---\n\nThe agent tools it lists are only listed here.\n' > "$FX/skills/b/SKILL.md"; green "the word agent alone is not spawning"
mkdir -p "$FX/skills/g"; printf -- '---\nname: g\n---\n<!-- generated-by: sh x -->\n\nsubagent in a generated index\n' > "$FX/skills/g/SKILL.md"; green "a generated index is skipped"
mk "$FX"; rm "$FX/contracts/agent-architectures.tsv"
red "a spawning skill with no register at all" "names architecture dc"

t_section "the register"
bad() { mk "$FX"; { printf '%s\n' "$HDR"; row dc 'verify*1' 'parent>verify' skills/a/SKILL.md; row "$1" "$2" "$3" "${4:--}"; } > "$FX/contracts/agent-architectures.tsv"; }
bad zz 'build*1 verify*1' 'build>build';                red "an agent verifying its own claims" "build>build — an agent verifying its own claims"
bad zz 'build*1 ghost*1' 'build>ghost';                 red "a role agents.tsv does not hold" "role ghost is not a role of contracts/agents.tsv"
bad zz 'build*1 verify*1' 'build>verify parent>zed';    red "a verifier outside roles" "zed in verified_by is not in roles"
bad zz 'build*1 verify*1' '';                           red "no verifier named" "verified_by is empty"
bad zz 'build*1 verify*1' 'build>verify' skills/gone.md; red "a method that is not there" "method skills/gone.md does not exist"
bad zz 'build*1 verify*1' 'build>verify' skills/b/SKILL.md; red "a method that does not name it back" "does not name zz"
bad zz 'build*x verify*1' 'build>verify';               red "a count that is not a number" "roles token build*x"
bad zz 'build*1@gpt/high verify*1' 'build>verify';      red "a tier outside the three" "roles token build*1@gpt/high"
bad zz 'build*1 verify*1 explore*1' 'build>verify';     red "a role that does nothing" "role explore neither produces nor verifies"
bad dc 'build*1 verify*1' 'build>verify';               red "a repeated id" "the id appears twice"
bad Zz 'build*1 verify*1' 'build>verify';               red "an id that is not lower-case words" "the id is not lower-case words"
mk "$FX"; printf '%s\n' "$HDR" 'dc	only	three' > "$FX/contracts/agent-architectures.tsv"; red "a short row" "3 fields, not 8"
mk "$FX"; sed 's/^id/ident/' "$FX/contracts/agent-architectures.tsv" > "$FX/x" && mv "$FX/x" "$FX/contracts/agent-architectures.tsv"; red "a changed header" "header is not the eight columns"
mk "$FX"; green "the sound fixture again"

t_section "the mode of the row"
reg() { printf 'id\tmode\ttype\tengine\tsurfaces\tmoment\tfunction\tstability\tsuccessor\towner\tred_proof\temitted\ttitle\n%s\t%s\tlint\tbin/lint-conventions.sh\t-\tci\tdetective\texperimental\t-\tskill\t-\t-\tfixture\n' "$ID" "$1" > "$FX.reg"; }
mk "$FX"; printf -- '---\nname: a\n---\n\nSpawn one subagent.\n' > "$FX/skills/a/SKILL.md"
reg warn; _o="$(HARBOR_LINT_CONTROLS="$FX.reg" HARBOR_SCOPE_ROOT="$FX" sh "$LINT" --only "$ID" 2>&1; printf 'exit=%s' "$?")"
t_has "warn: an advisory" "$_o" "ADVISORY [$ID]"; t_has "warn: exit 0" "$_o" 'exit=0'
reg block; _o="$(HARBOR_LINT_CONTROLS="$FX.reg" HARBOR_SCOPE_ROOT="$FX" sh "$LINT" --only "$ID" 2>&1; printf 'exit=%s' "$?")"
t_has "block: a violation" "$_o" "VIOLATION [$ID]"; t_has "block: exit 1" "$_o" 'exit=1'
t_red "$ID"
t_done
