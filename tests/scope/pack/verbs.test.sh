#!/usr/bin/env sh
# A pack's verb registers (harbor#1541): `harbor pack install` puts verbs/<cmd>.md at verbs.d/<repo-id>/, refuses a row for a
# command the pack does not ship, and admission-deny.sh derives allow and ask rules from them beside core's; a row a pack may
# not hold is BAD in gate-verbs.sh too, so a file dropped into verbs.d by hand grants nothing. Each refusal is driven red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
REG='| spelling | class | perm | actor | instead |\n|---|---|---|---|---|\n'
# vp <id> <row>...: a committed fixture pack whose verbs/demo-tool.md holds these rows. It ships TWO commands: the shims
# list is then two lines, which BSD awk refused as a -v value, so the shims check failed open (caught 2026-11-15).
vp() { _i="$1"; shift; mkpack "$_i"; mkdir -p "$PW/$_i/harbor-pack/verbs"
  printf '#!/bin/sh\necho two\n' > "$PW/$_i/harbor-pack/bin/demo-two"; chmod +x "$PW/$_i/harbor-pack/bin/demo-two"
  printf 'demo-two\tbin/demo-two\n' >> "$PW/$_i/harbor-pack/shims.tsv"
  { printf '# demo-tool\n\n'; printf "$REG"; for _r; do printf '%s\n' "$_r"; done; } > "$PW/$_i/harbor-pack/verbs/demo-tool.md"
  G "$PW/$_i" add -A; G "$PW/$_i" commit -q -m v; }
fresh() { mkdir -p "$1/bin" "$1/skills"; printf '{"permissions":{"allow":[],"ask":[],"deny":[]}}\n' > "$1/settings.json"; }
derive() { CLAUDE_CONFIG_DIR="$1" sh "$T_ROOT/bin/admission-deny.sh" --apply --dir "$1" > "$1/fd.log" 2>&1; }
rules() { jq -r '(.permissions.allow[] | "allow " + .), (.permissions.ask[] | "ask " + .)' "$1/settings.json"; }

t_section "a pack's register installs beside its shims, and remove takes it back"
vp vk '| `demo-tool read *` | read | allow | app | |' '| `demo-tool write *` | write | allow | app | dry run |' \
  '| `demo-tool write *--apply*` | gated | ask | app | a live change |' '| `demo-tool --live *` | gated | ask | app | |'
listed '"vk"'; TG="$T_TMP/tg-vk"; fresh "$TG"
t_exit "install --apply exits 0" 0 pk install vk --apply --dir "$TG"
t_eq "the register lands at verbs.d/<repo-id>/" "$(cat "$PW/vk/harbor-pack/verbs/demo-tool.md")" "$(cat "$TG/verbs.d/vk/demo-tool.md" 2>/dev/null)"
derive "$TG"; R="$(rules "$TG")"
t_has "admission-deny derives its read as allow" "$R" "allow Bash(demo-tool read *)"
t_has "...its dry run as allow" "$R" "allow Bash(demo-tool write *)"
t_has "...its apply as ask, which outranks the allow" "$R" "ask Bash(demo-tool write *--apply*)"
t_has "...and an ask that leads with the write flag" "$R" "ask Bash(demo-tool --live *)"
t_has "core's registers are still derived" "$R" "ask Bash(gcal-write *)"
t_eq "the planner's reader sees the pack row" app "$(HARBOR_GATE_VERBS_PACKS="$TG/verbs.d" sh "$T_ROOT/bin/gate-verbs.sh" --actor demo-tool read x)"
t_exit "remove exits 0" 0 pk remove vk --apply --dir "$TG"
t_eq "verbs.d is gone with the pack" no "$([ -e "$TG/verbs.d" ] && echo yes || echo no)"

t_section "refused: a row for a command the pack does not ship, a bad class, a nested file, no row at all"
TG="$T_TMP/tg-vr"
vp vg '| `git push *` | write | allow | app | |'; listed '"vg"'; fresh "$TG"; _b="$(snap "$TG")"
_o="$(pk install vg --apply --dir "$TG" 2>&1)"; t_eq "git push in a pack is refused" 1 "$?"
t_has "...naming the command" "$_o" "names git, which is not a command this pack ships"
t_eq "...and nothing is written" "$_b" "$(snap "$TG")"
vp vc '| `demo-tool read *` | sometimes | allow | app | |'; listed '"vc"'
t_has "a class outside read, write, gated is refused" "$(pk install vc --apply --dir "$TG" 2>&1)" "has class sometimes"
mkpack vn; mkdir -p "$PW/vn/harbor-pack/verbs/x"; printf 'x\n' > "$PW/vn/harbor-pack/verbs/x/demo-tool.md"; G "$PW/vn" add -A; G "$PW/vn" commit -q -m n; listed '"vn"'
t_has "a nested register is refused" "$(pk install vn --apply --dir "$TG" 2>&1)" "verbs/ is flat"
mkpack ve; mkdir -p "$PW/ve/harbor-pack/verbs"; printf '# nothing here\n' > "$PW/ve/harbor-pack/verbs/demo-tool.md"; G "$PW/ve" add -A; G "$PW/ve" commit -q -m e; listed '"ve"'
t_has "a register with no row is refused" "$(pk install ve --apply --dir "$TG" 2>&1)" "no row parses"
# RED-PROOF: the shims check removed, the git row installs.
M="$T_TMP/pm"; mkdir -p "$M"; cp -R "$T_ROOT/bin" "$M/bin"; cp -R "$T_ROOT/contracts" "$M/contracts"; cp -R "$T_ROOT/standards" "$M/standards"; cp -R "$T_ROOT/skills" "$M/skills"; mkdir -p "$M/docs"; cp -R "$T_ROOT/docs/reference" "$M/docs/"
sed 's/^          if (!(c in own)) { print .*$/          if (0) { }/' "$T_ROOT/bin/pack.sh" > "$M/bin/pack.sh"
t_eq "CONTROL: the pack.sh mutant differs" yes "$(cmp -s "$T_ROOT/bin/pack.sh" "$M/bin/pack.sh" || echo yes)"
listed '"vg"'
_o="$(env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$M/bin/pack.sh" install vg --apply --dir "$TG" 2>&1)"
t_eq "without the shims check the git row installs" "0 yes" "$? $([ -f "$TG/verbs.d/vg/demo-tool.md" ] && echo yes || echo "no: $_o")"

t_section "a register dropped into verbs.d by hand grants nothing outside its pack's shims"
# The mutant install above left vg's git row in $TG/verbs.d: the reader is the second wall.
derive "$TG"; R="$(rules "$TG")"
t_hasnt "git push is never derived from a pack" "$R" "Bash(git push *)"
t_has "admission-deny warns and skips it" "$(cat "$TG/fd.log")" "git push *"
mkdir -p "$TG/verbs.d/stray"; printf "$REG"'| `demo-tool read *` | read | allow | app | |\n' > "$TG/verbs.d/stray/demo-tool.md"
derive "$TG"
t_hasnt "a pack dir with no shims file grants nothing" "$(rules "$TG")" "Bash(demo-tool read *)"
sed 's/^        if (pk != "" \&\& !(c in own)) ok = 0$/        ok = ok/' "$T_ROOT/bin/gate-verbs.sh" > "$M/bin/gate-verbs.sh"
t_eq "CONTROL: the gate-verbs mutant differs" yes "$(cmp -s "$T_ROOT/bin/gate-verbs.sh" "$M/bin/gate-verbs.sh" || echo yes)"
t_has "without the own-shims line the git row comes back OK" "$(HARBOR_GATE_VERBS_DIR="$T_ROOT/contracts/verbs" HARBOR_GATE_VERBS_PACKS="$TG/verbs.d" sh "$M/bin/gate-verbs.sh" rules allow)" "OK	git push *"
t_done
