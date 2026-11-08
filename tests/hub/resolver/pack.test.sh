#!/usr/bin/env sh
# pack.test.sh (harbor#1278, R21 #1285) — hub packs install from the hub clone at the pinned commit with no gitleaks on the laptop, a hub
# hook is delivered only against the signed hash, and bin/pack.sh still refuses hooks for every other pack.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
member_env; mkinst; hub_init
# a gitleaks that would fail loudly if anything on the hub path asked for it
printf '#!/bin/sh\necho called >> "%s/gitleaks.called"\nexit 99\n' "$T_TMP" > "$T_BIN/gitleaks"; chmod +x "$T_BIN/gitleaks"
hsync() { hubsh sync --dir "$CFGD" > "$T_TMP/sync.out" 2>&1; echo $?; }
policy_with() { publish ".serial += 1 | .packs = [{id:\"fixture-pack\",commit:\"$PACKC\"}] | .hooks = [{pack:\"fixture-pack\",path:\"hooks/guard-hub.sh\",sha256:\"$HOOKSHA\"}]"; }

t_section "1 - a hub pack installs from the pinned commit, and gitleaks is never asked for"
mkhubpack fixture-pack; policy_with
t_eq "sync exits 0" 0 "$(hsync)"
t_eq "the skill is installed" "A hub skill." "$(tail -n 1 "$CFGD/skills/hubdemo/SKILL.md" 2>/dev/null)"
t_eq "the manifest is hub-fixture-pack and says it came from the hub" "hub" "$(awk -F'\t' '$1 == "# source" { print $2 }' "$CFGD/.harbor-packs/hub-fixture-pack.tsv")"
t_eq "...at the pinned commit" "$PACKC" "$(awk -F'\t' '$1 == "# commit" { print $2 }' "$CFGD/.harbor-packs/hub-fixture-pack.tsv")"
t_eq "gitleaks was not called" no "$([ -e "$T_TMP/gitleaks.called" ] && echo yes || echo no)"
t_eq "the hook is not installed into the config dir" 0 "$(find "$CFGD" -name 'guard-hub.sh' | wc -l | tr -d ' ')"
t_eq "a second sync changes nothing" 0 "$(hsync)"

t_section "2 - the hook is delivered where the dispatcher runs it, against the signed hash"
t_eq "the delivered hook answers hub-sync hook" "$STATE/hooks/fixture-pack/hooks/guard-hub.sh" "$(sh "$HS" hook fixture-pack hooks/guard-hub.sh 2>/dev/null)"
printf '#!/bin/sh\ncurl evil\n' >> "$STATE/hooks/fixture-pack/hooks/guard-hub.sh"
t_eq "a hook edited on the laptop no longer answers" "" "$(sh "$HS" hook fixture-pack hooks/guard-hub.sh 2>/dev/null)"
hsync >/dev/null
t_eq "the next sync puts the signed bytes back" "$STATE/hooks/fixture-pack/hooks/guard-hub.sh" "$(sh "$HS" hook fixture-pack hooks/guard-hub.sh 2>/dev/null)"
publish ".serial += 1 | .hooks = [{pack:\"fixture-pack\",path:\"hooks/guard-hub.sh\",sha256:\"$(printf x | hub_sha256)\"}]"
t_eq "a policy hash that the committed hook does not match: sync exits 1" 1 "$(hsync)"
t_eq "...the hook is dropped, not run" "" "$(sh "$HS" hook fixture-pack hooks/guard-hub.sh 2>/dev/null)"
t_eq "...and the failure is recorded as a check event" 1 "$(grep -c 'check check=hub-hook outcome=failed' "$T_TMP/events.log")"
policy_with; hsync >/dev/null

t_section "3 - a pack the signed policy does not pin, or whose extension is wrong, is refused"
mkhubpack other-pack
t_eq "pack.sh --hub for an unpinned pack is refused (1)" 1 "$(env -u CLAUDE_CONFIG_DIR sh "$INST/bin/pack.sh" install other-pack --hub --apply --dir "$CFGD" >/dev/null 2>&1; echo $?)"
t_has "...and says the policy does not pin it" "$(env -u CLAUDE_CONFIG_DIR sh "$INST/bin/pack.sh" install other-pack --hub --apply --dir "$CFGD" 2>&1)" "does not pin hub pack other-pack"
mkhubpack bad-ext; jq '.harbor_version = ">=9"' "$HUBSRC/packs/bad-ext/extension.json" > "$T_TMP/e.json"; cp "$T_TMP/e.json" "$HUBSRC/packs/bad-ext/extension.json"
G "$HUBSRC" add -A; G "$HUBSRC" commit -qm ext; BADC="$(G "$HUBSRC" rev-parse HEAD)"
publish ".serial += 1 | .packs += [{id:\"bad-ext\",commit:\"$BADC\"}]"
hsync >/dev/null
t_has "an extension that needs a newer harbor is skipped by name" "$(cat "$T_TMP/sync.out")" "needs harbor >=9"
mkhubpack bad-sha; printf 'tampered\n' >> "$HUBSRC/packs/bad-sha/harbor-pack/skills/hubdemo/SKILL.md"
G "$HUBSRC" add -A; G "$HUBSRC" commit -qm sha; SHAC="$(G "$HUBSRC" rev-parse HEAD)"
publish ".serial += 1 | .packs += [{id:\"bad-sha\",commit:\"$SHAC\"}]"
hsync >/dev/null
t_has "a file that differs from extension.json is skipped by name" "$(cat "$T_TMP/sync.out")" "bytes at the pinned commit differ"
t_eq "...neither bad pack is installed" 0 "$(ls "$CFGD/.harbor-packs" | grep -c 'bad-')"

t_section "4 - a pack the policy drops is removed"
publish '.serial += 1 | .packs = [] | .hooks = []'
t_eq "sync exits 0" 0 "$(hsync)"
t_eq "the manifest is gone" no "$([ -e "$CFGD/.harbor-packs/hub-fixture-pack.tsv" ] && echo yes || echo no)"
t_eq "...the skill is gone" no "$([ -e "$CFGD/skills/hubdemo" ] && echo yes || echo no)"
t_eq "...the delivered hook is gone" 0 "$(find "$STATE/hooks" -type f 2>/dev/null | wc -l | tr -d ' ')"

t_section "5 - every other pack still may not carry a hook"
PW="$T_TMP/ws"; mkdir -p "$PW/harbor-private/x" "$PW/hk/harbor-pack/hooks" "$PW/hk/harbor-pack/skills/d"
printf 'name = "hk"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "x"\n' > "$PW/hk/harbor-pack/pack.toml"
printf 'x\n' > "$PW/hk/harbor-pack/hooks/h.sh"; printf -- '---\nname: d\n---\nx\n' > "$PW/hk/harbor-pack/skills/d/SKILL.md"
G "$PW/hk" init -q; G "$PW/hk" add -A; G "$PW/hk" commit -qm h
printf 'packs = ["hk"]\n' > "$PW/harbor-private/harbor.toml"
mkdir -p "$T_TMP/tg"
_o="$(env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PW/harbor-private" sh "$INST/bin/pack.sh" install hk --apply --dir "$T_TMP/tg" 2>&1)"; _rc=$?
t_eq "a workload pack with hooks/ is refused" 1 "$_rc"
t_has "...by the hooks rule" "$_o" "hooks/"
t_done
