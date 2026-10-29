#!/usr/bin/env sh
# A pack's check rows (harbor#1149): the private layer's own fragment shape, composed into the ONE installed bin/docs/reference/checks.md.
# Install adds the rows, remove takes them back byte for byte, a duplicate id is refused by name, runtime-install keeps them.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
GEN="$T_ROOT/bin/check-registry-generate.sh"
export HARBOR_SCOPE_PRIVATE="$PRIV"
ids() { awk -F'|' '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `/ { id = $2; gsub(/[` ]/, "", id); print id }'; }
pids() { awk -F'|' '/^## / { p = ($0 ~ /^## Platforms/) } p && /^\| [a-z]/ && $2 != " id " { id = $2; gsub(/ /, "", id); print id }'; }
# target <name>: a config dir whose bin/docs/reference/checks.md is what runtime-install would have put there (core, no pack).
target() { _t="$T_TMP/tg-$1"; rm -rf "$_t"; mkdir -p "$_t/bin/docs/reference"; sh "$GEN" --core "$T_ROOT/docs/reference/checks.md" --private "$PRIV" > "$_t/bin/docs/reference/checks.md"; printf '%s' "$_t"; }
# frag <id> <rows>: rewrite a pack's checks.md and commit it.
frag() { printf '%s\n' "$2" > "$PW/$1/harbor-pack/checks.md"; G "$PW/$1" add -A; G "$PW/$1" commit -q -m f; }
refusal() { # <label> <pack id> <target> <needle>
  _b="$(snap "$3")"; _o="$(pk install "$2" --apply --dir "$3" 2>&1)"; _rc=$?
  t_eq "$1: exits 1" 1 "$_rc"; t_has "$1: skipped by name" "$_o" "skipped $2:"; t_has "$1: says why" "$_o" "$4"
  t_eq "$1: the target is byte-identical" "$_b" "$(snap "$3")"
}

t_section "install composes the pack's rows into bin/docs/reference/checks.md; remove takes them back byte for byte"
mkpack ck; mkpack cj; rm -rf "$PW/cj/harbor-pack/skills" "$PW/cj/harbor-pack/bin" "$PW/cj/harbor-pack/shims.tsv" "$PW/cj/harbor-pack/inject.d"; G "$PW/cj" add -A; G "$PW/cj" commit -q -m checks-only; listed '"ck", "cj"'
TG="$(target one)"; B0="$(snap "$TG")"; CORE_IDS="$(ids < "$T_ROOT/docs/reference/checks.md" | wc -l | tr -d ' ')"
pk install ck --apply --dir "$TG" >/dev/null 2>&1
t_eq "the register gains the pack's one row" "$(( CORE_IDS + 1 ))" "$(ids < "$TG/bin/docs/reference/checks.md" | wc -l | tr -d ' ')"
t_has "...its register row" "$(cat "$TG/bin/docs/reference/checks.md")" '| `demo-ck` | the demo |'
t_eq "...and its platforms row" "demo-ck" "$(pids < "$TG/bin/docs/reference/checks.md" | grep -x demo-ck)"
t_eq "the installed register is the generator's output" yes "$(sh "$GEN" --core "$T_ROOT/docs/reference/checks.md" --packs "$TG/checks.d" | cmp -s - "$TG/bin/docs/reference/checks.md" && echo yes)"
t_eq "ONE registry: no register id repeats" "" "$(ids < "$TG/bin/docs/reference/checks.md" | sort | uniq -d)"
t_eq "no insertion point survives" 0 "$(grep -cx '<!-- private:[a-z]* -->' "$TG/bin/docs/reference/checks.md")"
t_eq "the fragment and its controls are installed beside" "yes" "$([ -f "$TG/checks.d/ck.md" ] && [ -f "$TG/checks.d/ck.controls.tsv" ] && echo yes || echo no)"
pk install cj --apply --dir "$TG" >/dev/null 2>&1
t_eq "a second pack adds its row too" "$(( CORE_IDS + 2 ))" "$(ids < "$TG/bin/docs/reference/checks.md" | wc -l | tr -d ' ')"
t_eq "...packs in repo-id order (cj before ck)" "demo-cj demo-ck" "$(ids < "$TG/bin/docs/reference/checks.md" | grep '^demo-' | tr '\n' ' ' | sed 's/ $//')"
pk install ck --apply --dir "$TG" >/dev/null 2>&1; A="$(cat "$TG/bin/docs/reference/checks.md")"
t_eq "a reinstall leaves the register as it was" "$A" "$(cat "$TG/bin/docs/reference/checks.md")"
t_exit "remove ck exits 0" 0 pk remove ck --apply --dir "$TG"
t_hasnt "...its row is gone" "$(cat "$TG/bin/docs/reference/checks.md")" 'demo-ck'
t_has "...the other pack's row stays" "$(cat "$TG/bin/docs/reference/checks.md")" 'demo-cj'
pk remove cj --apply --dir "$TG" >/dev/null 2>&1
t_eq "removing every pack leaves the target byte-identical" "$B0" "$(snap "$TG")"
t_eq "...with no pack row behind in the register" 0 "$(grep -c 'demo-' "$TG/bin/docs/reference/checks.md")"

t_section "a target with no bin/docs/reference/checks.md gets none from a pack; runtime-install composes it later"
TG="$T_TMP/tg-nort"; mkdir -p "$TG"
pk install ck --apply --dir "$TG" >/dev/null 2>&1
t_eq "no register is invented" no "$([ -e "$TG/bin/docs/reference/checks.md" ] && echo yes || echo no)"
t_eq "...the fragment is installed" yes "$([ -f "$TG/checks.d/ck.md" ] && echo yes || echo no)"
printf '{}' > "$TG/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-runtime-install.sh" --apply --dir "$TG" >/dev/null 2>&1
t_has "runtime-install composes the installed pack's row in" "$(cat "$TG/bin/docs/reference/checks.md")" '| `demo-ck` |'
t_eq "...and the register is still the generator's output" yes "$(sh "$GEN" --core "$T_ROOT/docs/reference/checks.md" --packs "$TG/checks.d" | cmp -s - "$TG/bin/docs/reference/checks.md" && echo yes)"
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-runtime-install.sh" --apply --dir "$TG" >/dev/null 2>&1
t_has "a second runtime-install keeps it" "$(cat "$TG/bin/docs/reference/checks.md")" '| `demo-ck` |'
pk remove ck --apply --dir "$TG" >/dev/null 2>&1
t_hasnt "remove then drops it from the installed register" "$(cat "$TG/bin/docs/reference/checks.md")" 'demo-ck'

t_section "a duplicate id is refused by name: across packs, and against core"
TG="$(target dup)"; pk install ck --apply --dir "$TG" >/dev/null 2>&1
mkpack dp; frag dp "$(sed 's/demo-dp/demo-ck/g' "$PW/dp/harbor-pack/checks.md")"; listed '"ck", "dp"'
B1="$(snap "$TG")"; O="$(pk install dp --apply --dir "$TG" 2>&1)"; RC=$?
t_eq "the same id in another pack: exit 1" 1 "$RC"
t_has "...skipped by name" "$O" "skipped dp:"
t_has "...naming the id and both sources" "$O" "the id demo-ck is in"
t_eq "...and the target is untouched" "$B1" "$(snap "$TG")"
CORE1="$(ids < "$T_ROOT/docs/reference/checks.md" | head -n 1)"
mkpack dc; frag dc "$(printf '## Register\n\n| `%s` | x | hourly | desktop | y |\n\n## Platforms\n\n| %s | macOS only | w | d |\n' "$CORE1" "$CORE1")"; listed '"dc"'
refusal "an id already in core" dc "$(target dupcore)" "is in core docs/reference/checks.md"
t_eq "the generator refuses the same pair with exit 2" 2 "$(mkdir -p "$T_TMP/pk2"; cp "$PW/dc/harbor-pack/checks.md" "$T_TMP/pk2/dc.md"; sh "$GEN" --core "$T_ROOT/docs/reference/checks.md" --packs "$T_TMP/pk2" >/dev/null 2>&1; echo $?)"
P1="$T_TMP/pk3"; mkdir -p "$P1"; cp "$PW/ck/harbor-pack/checks.md" "$P1/aa.md"; cp "$PW/ck/harbor-pack/checks.md" "$P1/bb.md"
t_eq "two fragments with one id: the generator exits 2 and prints nothing" "2:" "$(_o="$(sh "$GEN" --core "$T_ROOT/docs/reference/checks.md" --packs "$P1" 2>/dev/null)"; echo "$?:$_o")"

t_section "a fragment with a byte-order mark and CRLF installs, as the private layer's does"
mkpack bm; { printf '\357\273\277'; sed 's/$/\r/' "$PW/bm/harbor-pack/checks.md"; } > "$T_TMP/bm.md"; cp "$T_TMP/bm.md" "$PW/bm/harbor-pack/checks.md"
G "$PW/bm" add -A; G "$PW/bm" commit -q -m bom; listed '"bm"'; TG="$(target bm)"
t_exit "a BOM'd CRLF checks.md installs" 0 pk install bm --apply --dir "$TG"
t_has "...and its row is in the register" "$(cat "$TG/bin/docs/reference/checks.md")" '| `demo-bm` |'

t_section "a fragment that does not parse refuses the pack"
mkpack bad1; frag bad1 '## Register

| `demo-bad1` | only | three |'
listed '"bad1"'; refusal "a short register row" bad1 "$(target bad1)" "does not compose into the register"
mkpack bad2; frag bad2 '## Register

| `demo-bad2` | the demo | hourly | desktop | broken |'
listed '"bad2"'; refusal "a register row with no platforms row" bad2 "$(target bad2)" "not both"
mkpack bad3; printf 'id\tcmd\ndemo.check\techo ok\n' > "$PW/bad3/harbor-pack/checks.tsv"; G "$PW/bad3" add -A; G "$PW/bad3" commit -q -m t
listed '"bad3"'; refusal "the retired checks.tsv" bad3 "$(target bad3)" "checks.tsv is retired"

t_section "controls.tsv: the core columns, a row per check of this pack"
ctl() { # <id> <printf-format of the controls.tsv body>
  mkpack "$1"; printf "$2" "$1" "$1" > "$PW/$1/harbor-pack/controls.tsv"; G "$PW/$1" add -A; G "$PW/$1" commit -q -m c; listed "\"$1\""
}
ctl cb 'not\ta\theader\ncheck.demo-%s\tx\n'
refusal "a header that is not core's" cb "$(target cb)" "its header is not the core controls.tsv header"
HDR="$(grep -v '^#' "$T_ROOT/standards/naming/controls.tsv" | awk 'NF { print; exit }')"
ctl cc "$HDR"'\ncheck.other-%s\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\tcheck\t-\tx\tt\n'
refusal "a control row of a check the pack does not carry" cc "$(target cc)" "is not check.<id> of a row in checks.md"
ctl cd "$HDR"'\ncheck.demo-%s\twarn\tcheck\n'
refusal "a control row with the wrong column count" cd "$(target cd)" "columns"
mkpack ce; rm "$PW/ce/harbor-pack/checks.md"; G "$PW/ce" add -A; G "$PW/ce" commit -q -m n; listed '"ce"'
refusal "controls.tsv without checks.md" ce "$(target ce)" "controls.tsv without checks.md"

t_section "install-drift: a pack's file is the pack's, and the register is held to the composition with its rows"
D="$T_TMP/drift"; DR="$D/repo"; DC="$D/install"; mkdir -p "$DR/bin" "$DC/bin" "$DR/docs/reference" "$DC/bin/docs/reference"
cp "$T_ROOT/bin/drift-install.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$GEN" "$DR/bin/"
printf 'DATA="docs/reference/checks.md:bin/docs/reference/checks.md"\n' > "$DR/bin/deploy-runtime-install.sh"; cp "$T_ROOT/docs/reference/checks.md" "$DR/docs/reference/checks.md"
git init -q "$DR"; git -C "$DR" symbolic-ref HEAD refs/heads/main; git -C "$DR" add -A
git -C "$DR" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -qm v1
cp "$DR/docs/reference/checks.md" "$DC/bin/docs/reference/checks.md"
drift() { sh "$DR/bin/drift-install.sh" --dir "$DC" --ref main 2>&1; }
t_has "a core-only install is current" "$(drift)" "unsourced=0"
printf '#!/bin/sh\n' > "$DC/bin/demo-tool"; chmod +x "$DC/bin/demo-tool"
t_has "a file no commit holds reads unsourced" "$(drift)" "FAIL: unsourced demo-tool"
mkdir -p "$DC/.harbor-packs" "$DC/checks.d"; printf '# repo\tck\nF\tbin/demo-tool\nF\tchecks.d/ck.md\n' > "$DC/.harbor-packs/ck.tsv"
t_hasnt "...and not once a pack's manifest owns it" "$(drift)" "unsourced demo-tool"
cp "$PW/ck/harbor-pack/checks.md" "$DC/checks.d/ck.md"
t_has "the bare register reads modified once a pack's rows are installed" "$(drift)" "FAIL: modified docs/reference/checks.md ("
sh "$GEN" --core "$DR/docs/reference/checks.md" --packs "$DC/checks.d" > "$DC/bin/docs/reference/checks.md"
t_has "...and current when it is the composition with them" "$(drift)" "current=1 stale=0 modified=0 unsourced=0"
t_done
