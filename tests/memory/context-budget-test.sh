#!/usr/bin/env sh
# context-budget.sh, the always-on surface every context decision is priced off (harbor#243).
# The verdict is the box's worst case, not the cwd's: a store-less cwd once read 91% and headroom
# while $HOME read 186% and over. Stores and ceilings are fixtures; cwds are compared to each other.
. "$(dirname "$0")/../lib/core.sh"; t_init
TOOL="${CB_TOOL:-$T_ROOT/bin/context-budget.sh}"  # CB_TOOL: run this suite against another build (red proof)
B="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
CFG="$B/cfg"; RICH="$B/rich"; POOR="$B/poor"  # rich owns the big store, poor owns none
mkdir -p "$CFG/skills" "$RICH" "$POOR"
slug() { printf '%s' "$1" | tr '/' '-'; }
fill() { _n=0; : > "$1"; while [ "$_n" -lt "$2" ]; do printf '%s' "$3" >> "$1"; _n=$((_n+1)); done; }  # <file> <n> <char>
mkdir -p "$CFG/projects/$(slug "$RICH")/memory"; fill "$CFG/projects/$(slug "$RICH")/memory/MEMORY.md" 5000 x
fill "$CFG/CLAUDE.md" 1000 c  # a constitution, so the base surface is non-zero and the same for both cwds
RICH_IDX="projects/$(slug "$RICH")/memory/MEMORY.md"
run() { ( cd "$1" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING="$2" sh "$TOOL" ) > "$3" 2>&1; }  # <cwd> <ceiling> <out>
verdict() { grep -E '^(OVER by|[0-9]+% of ceiling)' "$1" | head -1; }
spent() { sed -n 's/^SPENT EVERY SESSION *\([0-9][0-9]*\) *ceiling *\([0-9][0-9]*\).*/\1 \2/p' "$1" | head -1; }

t_section "1 · the verdict does not depend on the cwd"
# Ceiling 3000: the base (1000) alone is under; the base plus the big store (6000) is over.
run "$POOR" 3000 "$B/poor.out"; RC_POOR=$?
run "$RICH" 3000 "$B/rich.out"; RC_RICH=$?
V_POOR="$(verdict "$B/poor.out")"
t_has "the store-less cwd prints a verdict line" "$V_POOR" '% of ceiling'
t_eq "the verdict line is identical from both cwds" "$V_POOR" "$(verdict "$B/rich.out")"
t_eq "the exit code is identical from both cwds" "$RC_POOR" "$RC_RICH"
t_eq "the store-less cwd is judged OVER when the box's largest store is" OVER "$(printf '%s' "$V_POOR" | cut -c1-4)"
t_has "the verdict names the store it measured" "$V_POOR" "$RICH_IDX"
t_has "the local cost is still reported" "$(cat "$B/poor.out")" 'This cwd costs'

t_section "2 · the SPENT line keeps its shape, and stays local"
t_eq "SPENT EVERY SESSION parses to spent and ceiling" "1000 3000" "$(spent "$B/poor.out")"
t_eq "SPENT from the store's own cwd is the local 6000, not the worst case" "6000 3000" "$(spent "$B/rich.out")"

t_section "3 · under the ceiling it reports headroom and exits 0, from both cwds"
run "$POOR" 9000 "$B/poor9.out"; RC_U_POOR=$?
run "$RICH" 9000 "$B/rich9.out"; RC_U_RICH=$?
V_U_POOR="$(verdict "$B/poor9.out")"
t_eq "store-less cwd: exit" 0 "$RC_U_POOR"
t_eq "store's own cwd: exit" 0 "$RC_U_RICH"
t_eq "the headroom line is identical from both cwds" "$V_U_POOR" "$(verdict "$B/rich9.out")"
t_has "it is a headroom line, not OVER" "$V_U_POOR" 'bytes of headroom'
t_has "the headroom line names the store the worst case came from" "$V_U_POOR" "$RICH_IDX"

t_section "4 · a box with no stores at all measures this cwd and says so"
CFG2="$B/cfg-empty"; mkdir -p "$CFG2/skills"; cp "$CFG/CLAUDE.md" "$CFG2/CLAUDE.md"
( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG2" HARBOR_CONTEXT_CEILING=3000 sh "$TOOL" ) > "$B/none.out" 2>&1
V_NONE="$(verdict "$B/none.out")"
t_eq "a real percentage, not 0% and not silence" "33% of ceiling" "${V_NONE%%,*}"
t_has "the verdict says it measured this cwd" "$V_NONE" 'no memory store on this box'

t_section "5 · the baseline verdict (harbor#183)"
# Only the deliberate surface is baselined; the memory index moves with every memory written.
BL="$B/baseline.tsv"
blrun() { ( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_CONTEXT_BASELINE="$BL" sh "$TOOL" "$1" ) > "$B/bl.out" 2>&1; }
: > "$BL"; blrun --check; RC=$?
t_eq "--check with no baseline recorded: exit" 1 "$RC"
t_has "--check with no baseline refuses rather than passing" "$(cat "$B/bl.out")" 'no baseline recorded'
blrun --record; RC=$?
_rec="$(grep -v '^#' "$BL" | grep -v '^[[:space:]]*$' | tail -1)"
_want="$(wc -c < "$CFG/CLAUDE.md" | tr -d ' ')"  # derived the tool's way: constitution plus ambient descriptions
for _d in "$CFG"/skills/*/; do
  [ -f "$_d/SKILL.md" ] || continue
  grep -q '^disable-model-invocation:[[:space:]]*true' "$_d/SKILL.md" && continue
  _want=$(( _want + $(awk '/^description:/{print length($0); exit}' "$_d/SKILL.md") ))
done
t_eq "--record: exit" 0 "$RC"
t_eq "--record writes the measured deliberate surface" "$_want" "$(printf '%s' "$_rec" | cut -f2)"
t_has "the recorded reason is a placeholder, not a machine-written sentence" "$_rec" 'REPLACE THIS'
blrun --check; RC=$?
t_eq "--check against the row --record just wrote: exit" 0 "$RC"
t_has "--check says it matches" "$(cat "$B/bl.out")" 'matching the recorded baseline'
mkdir -p "$CFG/skills/newly-ambient"
printf -- '---\nname: newly-ambient\ndescription: a skill somebody added, which every session now pays for\n---\n' > "$CFG/skills/newly-ambient/SKILL.md"
blrun --check; RC=$?
t_eq "a moved surface: exit" 1 "$RC"
t_has "a moved surface is reported" "$(cat "$B/bl.out")" 'DELIBERATE SURFACE MOVED'
t_has "with its direction" "$(cat "$B/bl.out")" '(+'
rm -rf "$CFG/skills/newly-ambient"
mkdir -p "$CFG/projects/$(slug "$POOR")/memory"; fill "$CFG/projects/$(slug "$POOR")/memory/MEMORY.md" 4000 m
blrun --check; RC=$?
t_eq "writing a 4 KB memory index does not move the baselined surface" 0 "$RC"
_nl="$(wc -l < "$B/bl.out" | tr -d ' ')"
t_eq "--check stays terse: at most 2 lines" yes "$([ "$_nl" -le 2 ] && echo yes || echo "no, $_nl")"

t_section "6 · the surfaces harbor#316 added, each pinned by the way it went wrong"
# A YAML block description is priced whole: a first-line read once priced 2,348 B at 14.
mkdir -p "$CFG/skills/block-desc"
{ printf -- '---\nname: block-desc\ndescription: >\n'
  _n=0; while [ "$_n" -lt 40 ]; do printf '  padding line %s that the harness lists in every session prefix\n' "$_n"; _n=$((_n+1)); done
  printf -- '---\n\n# Block\n'; } > "$CFG/skills/block-desc/SKILL.md"
run "$POOR" 3000 "$B/blk.out"; rm -rf "$CFG/skills/block-desc"
BLK="$(sed -n 's/^ambient skill descriptions ([^)]*)[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$B/blk.out" | head -1)"
t_eq "a 40-line block description is priced whole (over 2000 B)" yes "$([ "${BLK:-0}" -gt 2000 ] && echo yes || echo "no, ${BLK:-0}")"
# Two user-scope installs plus a project-scope duplicate: the register decides, not the cache dirs.
mkdir -p "$CFG/plugins/cache/mk/p/AAA/agents" "$CFG/plugins/cache/mk/p/BBB/agents"
for _v in AAA BBB; do
  printf -- '---\nname: r\ndescription: %s\n---\n' "$(_n=0; while [ "$_n" -lt 30 ]; do printf 'word '; _n=$((_n+1)); done)" \
    > "$CFG/plugins/cache/mk/p/$_v/agents/r.md"
done
printf '{"version":2,"plugins":{"p@mk":[{"scope":"user","installPath":"%s/plugins/cache/mk/p/AAA"},{"scope":"user","installPath":"%s/plugins/cache/mk/p/BBB"},{"scope":"project","projectPath":"/x","installPath":"%s/plugins/cache/mk/p/BBB"}]}}\n' \
  "$CFG" "$CFG" "$CFG" > "$CFG/plugins/installed_plugins.json"
run "$POOR" 3000 "$B/plug.out"; rm -rf "$CFG/plugins"
t_eq "plugin agent descriptions are charged once per user-scope install" 2 \
  "$(sed -n 's/^plugin agent + command descriptions (\([0-9][0-9]*\)).*/\1/p' "$B/plug.out" | head -1)"
# CLAUDE_CONFIG_DIR does not isolate the injection, so a fixture dir must refuse to measure it.
t_has "the injection is refused, not guessed, when the config dir is not live" "$(cat "$B/poor.out")" 'NOT MEASURABLE'

t_section "7 · the baseline carries its instrument, and --check refuses across a change (harbor#585)"
# #316 widened the scope and +7,018 B of it read as regrowth. A number recorded without the ruler
# cannot tell a scope change from growth, so the row names the ruler and --check will not subtract across two.
: > "$BL"; blrun --record; RC=$?
_rec="$(grep -v '^#' "$BL" | grep -v '^[[:space:]]*$' | tail -1)"
t_has "--record writes the instrument id as a 4th column" "$(printf '%s' "$_rec" | cut -f4)" 'skills'
blrun --check; RC=$?
t_eq "same instrument, same surface: exit" 0 "$RC"
# Plant a scope change: a surface the recorded row did not count.
mkdir -p "$CFG/commands"; printf -- '---\ndescription: a slash command whose description every session now pays for\n---\n' > "$CFG/commands/planted.md"
blrun --check; RC=$?
t_eq "a new surface counted: exit" 1 "$RC"
t_has "it says the instrument changed" "$(cat "$B/bl.out")" 'INSTRUMENT CHANGED'
t_eq "it prints no delta, because there is none to print" 0 "$(grep -c '(+\|MOVED' "$B/bl.out")"
rm -rf "$CFG/commands"
# Plant a method change: same surfaces, a different way of pricing a description.
sed 's/t += length(\$0) + 1/t += length($0) + 2/' "$TOOL" > "$B/tool-m.sh"
cp "$(dirname "$TOOL")/log-lib.sh" "$B/log-lib.sh"
( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_CONTEXT_BASELINE="$BL" sh "$B/tool-m.sh" --check ) > "$B/m.out" 2>&1; RC=$?
t_eq "a changed measuring function: exit" 1 "$RC"
t_has "it says the instrument changed" "$(cat "$B/m.out")" 'INSTRUMENT CHANGED'
# A row from before instruments were recorded cannot be compared either.
printf '2026-01-01\t%s\tlegacy row, no instrument\n' "$(printf '%s' "$_rec" | cut -f2)" > "$BL"
blrun --check; RC=$?
t_eq "a 3-column legacy row is refused: exit" 1 "$RC"
t_has "and says why" "$(cat "$B/bl.out")" 'no instrument recorded'

t_section "8 · --check --kind names the verdict, which lint X3 files as the subject (harbor#585)"
# One subject for every failure filed an instrument change and regrowth as one finding.
kindof() { ( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_CONTEXT_BASELINE="$BL" sh "$TOOL" --check --kind ) 2>/dev/null | sed -n 's/^kind=//p'; }
: > "$BL"
t_eq "no baseline" no-baseline "$(kindof)"
blrun --record
t_eq "the row just recorded" match "$(kindof)"
mkdir -p "$CFG/skills/grown"; printf -- '---\nname: grown\ndescription: an ambient skill added after the row\n---\n' > "$CFG/skills/grown/SKILL.md"
t_eq "an ambient description added" grew "$(kindof)"
blrun --record; rm -rf "$CFG/skills/grown"
t_eq "the same description removed" shrank "$(kindof)"
mkdir -p "$CFG/commands"; printf -- '---\ndescription: a planted slash command\n---\n' > "$CFG/commands/planted.md"
t_eq "a surface the row did not count" instrument-changed "$(kindof)"
rm -rf "$CFG/commands"
t_eq "the kind is the last stdout line" kind=shrank "$( ( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_CONTEXT_BASELINE="$BL" sh "$TOOL" --check --kind ) 2>/dev/null | tail -1)"
blrun --check
t_eq "without --kind, --check prints no kind line" 0 "$(grep -c '^kind=' "$B/bl.out")"
# Review #971: a row whose byte count is not an integer once fell through -eq/-gt errors to `shrank`.
blrun --record; _inst="$(grep -v '^#' "$BL" | tail -1 | cut -f4)"
printf '2026-01-01\t9,9\twhy\t%s\n' "$_inst" > "$BL"
t_eq "a byte count that is not an integer is malformed, never shrank" malformed "$(kindof)"
printf '2026-01-01\t1,000\twhy\t%s\n' "$_inst" > "$BL"
t_eq "a thousands separator too" malformed "$(kindof)"
# An unreadable baseline, or a directory in its place, is not "no baseline": --record cannot fix it.
blrun --record; chmod 000 "$BL"
t_eq "a baseline that cannot be read" unreadable "$(kindof)"
blrun --check; chmod 644 "$BL"
t_hasnt "and its fix line does not send you to --record" "$(cat "$B/bl.out")" 'context-budget.sh --record'
rm -f "$BL"; mkdir "$BL"
t_eq "a directory where the baseline should be" unreadable "$(kindof)"
rmdir "$BL"
t_exit "an unknown flag after --check: exit 2" 2 env CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_BASELINE="$BL" sh "$TOOL" --check --nope
t_section "9 · the baseline lives in the state directory, never the checkout (harbor#1275)"
TR="$B/tree"; ST="$B/state"; mkdir -p "$TR/bin" "$ST"; cp "$TOOL" "$TR/bin/context-budget.sh"; cp "$(dirname "$TOOL")/log-lib.sh" "$TR/bin/"
cbrun() { ( cd "$POOR" && env -u HARBOR_CONTEXT_BASELINE CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_STATUS_DIR="$ST" sh "$TR/bin/context-budget.sh" "$1" ) > "$B/st.out" 2>&1; }
cbrun --record; RC=$?
t_eq "a core clone (no in-tree file): --record exits 0" 0 "$RC"
t_eq "...writes the state directory's file" 1 "$([ -s "$ST/context-baseline.tsv" ] && echo 1 || echo 0)"
t_eq "...and nothing into the tree" 0 "$(find "$TR" -name 'CONTEXT-BASELINE.tsv' | wc -l | tr -d ' ')"
rm -f "$ST/context-baseline.tsv"; cp "$BL.seed" "$TR/CONTEXT-BASELINE.tsv" 2>/dev/null || { ( cd "$POOR" && CLAUDE_CONFIG_DIR="$CFG" HARBOR_CONTEXT_CEILING=9000 HARBOR_CONTEXT_BASELINE="$TR/CONTEXT-BASELINE.tsv" sh "$TR/bin/context-budget.sh" --record ) >/dev/null 2>&1; }
SEED_SUM="$(cksum < "$TR/CONTEXT-BASELINE.tsv")"
cbrun --check; RC=$?
t_eq "a dev checkout's in-tree file seeds --check while the state file is absent: exit" 0 "$RC"
t_eq "...and that read created nothing in the state directory" 0 "$([ -e "$ST/context-baseline.tsv" ] && echo 1 || echo 0)"
cbrun --record; RC=$?
t_eq "--record on a seeded tree: exit" 0 "$RC"
t_eq "...copies the history, then appends: two rows in the state file" 2 "$(grep -vc '^#' "$ST/context-baseline.tsv" | tr -d ' ')"
t_eq "...and leaves the in-tree file byte for byte as it was" "$SEED_SUM" "$(cksum < "$TR/CONTEXT-BASELINE.tsv")"
cbrun --check; RC=$?
t_eq "once the state file exists it wins: --check exit" 0 "$RC"
t_done
