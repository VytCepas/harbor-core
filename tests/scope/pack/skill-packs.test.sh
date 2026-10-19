#!/usr/bin/env sh
# `harbor pack`, skill-packs/ (bin/pack.sh, harbor#1149): a pack ADDS packs to a core skill without claiming the skill's name.
# <pack>/skill-packs/<core skill>/<name>.md lands at <target>/skill-packs/<core skill>/<name>.md, outside skills/, where the
# skill's checker searches for it. Same throwaway PORT_ROOT and --dir as pack.test.sh.
# No core skill reads domain packs since the topology skill, and its reader, left for the measurement pack (harbor#1149), so
# the core is a fixture here: a root that links this one's bin/, CONTRACTS/, CHECKS.md and standards/ and has a skills/ of its
# own, holding `reader` (keeps a packs/ directory, so it takes packs) and `plain` (keeps none).
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
FR="$T_TMP/fakecore"; mkdir -p "$FR/skills/reader/packs" "$FR/skills/plain"
for _l in bin CONTRACTS CHECKS.md standards; do ln -s "$T_ROOT/$_l" "$FR/$_l"; done
printf -- '---\nname: plain\n---\nA skill that reads no packs.\n' > "$FR/skills/plain/SKILL.md"
printf 'the packs directory the skill keeps\n' > "$FR/skills/reader/packs/README.md"
printf -- '---\npack: measurement\ntriggers: x\n---\nA pack the core skill ships.\n' > "$FR/skills/reader/packs/measurement.md"
pk() { env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PRIV" HARBOR_ROOT="$FR" sh "$T_ROOT/bin/pack.sh" "$@"; }

# skpack <id> [<skill> [<file>]]: a clean committed pack holding one pack file for a core skill.
skpack() {
  _d="$PW/$1"; _s="${2:-reader}"; _f="${3:-demo-pack.md}"
  rm -rf "$_d"; mkdir -p "$_d/harbor-pack/skill-packs/$_s"
  printf 'name = "sk-%s"\nversion = "1.0.0"\nharbor_version = ">=1.0"\ndescription = "a fixture"\n' "$1" > "$_d/harbor-pack/pack.toml"
  printf -- '---\npack: demo-pack\ntriggers: demoword\nlayers: origin, collection\n---\nA demo pack.\n' > "$_d/harbor-pack/skill-packs/$_s/$_f"
  G "$_d" init -q; G "$_d" add -A; G "$_d" commit -q -m fixture
}
recommit() { G "$PW/$1" add -A; G "$PW/$1" commit -q -m c; }
# refused <label> <id> <reason fragment>: skipped by name, exit 1, target byte-identical.
refused() {
  TG="$T_TMP/tg-$1"; rm -rf "$TG"; mkdir -p "$TG/bin" "$TG/skills"; printf 'core\n' > "$TG/bin/core-file"
  _b="$(snap "$TG")"; listed "\"$2\""
  _o="$(pk install "$2" --apply --dir "$TG" 2>&1)"; _rc=$?
  t_eq "$1: exits 1" 1 "$_rc"
  t_has "$1: skipped by name" "$_o" "skipped $2:"
  t_has "$1: says why" "$_o" "$3"
  t_eq "$1: the target is byte-identical" "$_b" "$(snap "$TG")"
}

t_section "a pack adds a pack to a core skill, and remove takes it back exactly"
skpack ok; listed '"ok"'
TG="$T_TMP/tg-ok"; mkdir -p "$TG/bin" "$TG/skills/reader/packs"; printf 'core\n' > "$TG/bin/core-file"; printf 'core\n' > "$TG/skills/reader/packs/README.md"
B0="$(snap "$TG")"
pk install ok --dir "$TG" >/dev/null 2>&1
t_eq "a dry run writes nothing" "$B0" "$(snap "$TG")"
t_exit "install --apply exits 0" 0 pk install ok --apply --dir "$TG"
t_has "the pack file lands in skill-packs/, outside the skill's own directory" "$(cat "$TG/skill-packs/reader/demo-pack.md")" "A demo pack."
t_eq "...and nothing lands inside skills/reader/" "core" "$(cat "$TG/skills/reader/packs/README.md")"
t_eq "...whose only file is still the one that was there" 1 "$(find "$TG/skills" -type f | wc -l | tr -d ' ')"
t_has "the manifest owns the file" "$(cat "$TG/.harbor-packs/ok.tsv")" "F	skill-packs/reader/demo-pack.md"
B1="$(snap "$TG")"
pk install ok --apply --dir "$TG" >/dev/null 2>&1
t_eq "a second install changes nothing" "$B1" "$(snap "$TG")"
t_exit "remove exits 0" 0 pk remove ok --apply --dir "$TG"
t_eq "install then remove leaves the target byte-identical" "$B0" "$(snap "$TG")"

t_section "remove keeps what the operator put beside the pack file"
pk install ok --apply --dir "$TG" >/dev/null 2>&1
printf 'mine\n' > "$TG/skill-packs/reader/mine.md"
pk remove ok --apply --dir "$TG" >/dev/null 2>&1
t_eq "the operator's own pack file survives" "mine" "$(cat "$TG/skill-packs/reader/mine.md")"
t_exit "...and so does its directory" 0 test -d "$TG/skill-packs/reader"

t_section "refused: a skill core does not have, or that reads no packs"
skpack ns nosuchskill; refused no-skill ns "core has no skill nosuchskill"
skpack nd plain; refused no-packs-dir nd "core has no skill plain with a packs/ directory"
skpack uc Reader; refused case-differs uc "core has no skill Reader"

t_section "refused: a pack file core already holds (a pack in two places)"
skpack dp reader measurement.md; refused duplicate dp "also in core skills/reader/packs/"

t_section "refused: any other shape under skill-packs/"
skpack ne; mkdir -p "$PW/ne/harbor-pack/skill-packs/reader/sub"; printf -- '---\npack: x\n---\n' > "$PW/ne/harbor-pack/skill-packs/reader/sub/x.md"; recommit ne
refused nested ne "is nested"
skpack rd reader README.md; refused readme rd "never read as a pack"
skpack tl; printf -- '---\npack: x\n---\n' > "$PW/tl/harbor-pack/skill-packs/top.md"; recommit tl
refused top-level tl "holds <skill>/<name>.md"
skpack nm; printf 'x\n' > "$PW/nm/harbor-pack/skill-packs/reader/notes.txt"; recommit nm
refused not-md nm "holds <skill>/<name>.md"

t_section "refused: front matter outside the skill-pack keys"
skpack fk; printf -- '---\nname: demo\ntriggers: x\n---\nbody\n' > "$PW/fk/harbor-pack/skill-packs/reader/demo-pack.md"; recommit fk
refused key-not-listed fk "key name is not in CONTRACTS/skill-pack-frontmatter-keys.txt"
skpack hk; printf -- '---\npack: x\nhooks: y\n---\nbody\n' > "$PW/hk/harbor-pack/skill-packs/reader/demo-pack.md"; recommit hk
refused hooks-key hk "hooks: key"
skpack ob; printf -- '---\r\npack: x\r\n---\r\nbody\r\n' > "$PW/ob/harbor-pack/skill-packs/reader/demo-pack.md"; recommit ob
TGOB="$T_TMP/tg-ob-ok"; mkdir -p "$TGOB/skills/reader/packs"; listed '"ob"'
t_exit "CRLF front matter with the right keys is accepted" 0 pk install ob --apply --dir "$TGOB"

t_section "refused: a file the pack did not write"
skpack ex; listed '"ex"'
TG="$T_TMP/tg-ex"; mkdir -p "$TG/skill-packs/reader"; printf 'the operator\n' > "$TG/skill-packs/reader/demo-pack.md"
_o="$(pk install ex --apply --dir "$TG" 2>&1)"; _rc=$?
t_eq "exits 1" 1 "$_rc"
t_has "says the path is not the pack's" "$_o" "skill-packs/reader/demo-pack.md already exists in the target and is not this pack's"
t_eq "the operator's file is untouched" "the operator" "$(cat "$TG/skill-packs/reader/demo-pack.md")"

t_section "unchanged: a pack skill named like a core skill is still refused"
mkpack sh4; mkdir -p "$PW/sh4/harbor-pack/skills/reader/packs"; printf 'x\n' > "$PW/sh4/harbor-pack/skills/reader/packs/x.md"; recommit sh4
refused skill-name sh4 "shadows a core skill"

t_done
