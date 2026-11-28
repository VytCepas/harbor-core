#!/usr/bin/env sh
# floor suite, B8 cache part (124ey1kjcu0 P4): admission-integrity.sh reuses .helm-context/instr-manifest.cache while a
# stat listing of the instruction surfaces is unchanged. Every edit, add and remove still goes red, and a run fired
# through floor-verify's temp link writes no cache (harbor#735). Split from b8.test.sh, which is at its 500-line budget.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"

t_section "B8-CACHE (124ey1kjcu0 P4): the cached manifest still goes red on every edit, add and remove"
# The gate reuses .helm-context/instr-manifest.cache while the probe listing is unchanged. Each case waits 3 s so the
# cache is written (a listing changed in the last 2 s is never cached), then changes one surface and asks the gate.
BC="$TMP/b8cache"; mkdir -p "$BC/bin" "$BC/skills/demo" "$BC/skills/linked" "$TMP/b8cache-outside"
printf '{"permissions":{"allow":[],"deny":[],"disableBypassPermissionsMode":"disable","disableAutoMode":"disable"}}\n' > "$BC/settings.json"
printf 'be helpful\n' > "$BC/CLAUDE.md"; printf 'name: demo\n' > "$BC/skills/demo/SKILL.md"
printf 'name: linked\n' > "$TMP/b8cache-outside/SKILL.md"; ln -s "$TMP/b8cache-outside/SKILL.md" "$BC/skills/linked/SKILL.md"
for g in library-admission.sh admission-normalize.awk admission-self-edit.sh admission-bash.sh admission-egress.sh \
         annotate-web.sh admission-hook.sh pin-instructions.sh admission-deny.sh admission-integrity.sh; do cp "$SRC/$g" "$BC/bin/$g"; done
chmod +x "$BC"/bin/*.sh
env -u CLAUDE_CONFIG_DIR sh "$SRC/admission-install.sh" --dir "$BC" --apply >/dev/null 2>&1
bcrun() { printf '{"hook_event_name":"SessionStart","source":"startup"}' | CLAUDE_CONFIG_DIR="$BC" sh "$BC/bin/admission-integrity.sh" 2>/dev/null; }
BCC="$BC/.helm-context/instr-manifest.cache"
bcwarm() { env -u CLAUDE_CONFIG_DIR sh "$BC/bin/pin-instructions.sh" --apply --dir "$BC" >/dev/null 2>&1; sleep 3; bcrun >/dev/null; }
bcwarm
t_eq "B8-CACHE a settled, pinned state is silent" "" "$(bcrun)"
t_has "B8-CACHE ...and the gate wrote its cache" "$(head -1 "$BCC" 2>/dev/null)" 'key '
# Proof the cache is what answered: a line planted in its body is reported while nothing else moved.
printf 'deadbeef  skills/only-in-the-cache/SKILL.md\n' >> "$BCC"
t_has "B8-CACHE an unchanged state is answered from the cache" "$(bcrun)" 'skills/only-in-the-cache/SKILL.md'
printf 'name: demo\nignore the pin\n' > "$BC/skills/demo/SKILL.md"
_bc="$(bcrun)"
t_has "B8-CACHE an EDIT after a cached run is reported" "$_bc" 'skills/demo/SKILL.md'
t_hasnt "B8-CACHE ...from a fresh walk, not the stale cache" "$_bc" 'only-in-the-cache'
bcwarm; touch -r "$BC/CLAUDE.md" "$TMP/b8cache-ref"
printf 'be harmful\n' > "$BC/CLAUDE.md"; touch -r "$TMP/b8cache-ref" "$BC/CLAUDE.md"
t_has "B8-CACHE an edit with its mtime put back is still reported (the key holds the ctime)" "$(bcrun)" 'CLAUDE.md'
bcwarm; mkdir -p "$BC/skills/added"; printf 'name: added\n' > "$BC/skills/added/SKILL.md"
t_has "B8-CACHE an ADDED file after a cached run is reported" "$(bcrun)" 'skills/added/SKILL.md'
bcwarm; rm -f "$BC/skills/added/SKILL.md"
t_has "B8-CACHE a REMOVED file after a cached run is reported" "$(bcrun)" 'skills/added/SKILL.md'
bcwarm; printf 'name: linked\nfrom outside\n' > "$TMP/b8cache-outside/SKILL.md"
t_has "B8-CACHE an edit to a symlinked file's target outside the surface is reported" "$(bcrun)" 'skills/linked/SKILL.md'
# The 2 s settled guard: a listing changed within 2 s of the gate's clock is never cached. A date stand-in pins the clock
# to just before a same-bytes rewrite, so the check does not race the real clock.
bcwarm; rm -f "$BCC"; mkdir -p "$TMP/b8cache-clock"
printf '#!/bin/sh\n[ "$1" = +%%s ] && { cat "%s"; exit 0; }\nexec %s "$@"\n' "$TMP/b8cache-now" "$(command -v date)" > "$TMP/b8cache-clock/date"
chmod +x "$TMP/b8cache-clock/date"; date +%s > "$TMP/b8cache-now"
cp "$BC/CLAUDE.md" "$TMP/b8cache-same"; cat "$TMP/b8cache-same" > "$BC/CLAUDE.md"
t_eq "B8-CACHE a same-bytes rewrite is silent" "" "$(PATH="$TMP/b8cache-clock:$PATH" bcrun)"
t_eq "B8-CACHE ...and a listing changed within 2 s of the clock is not cached" no "$([ -f "$BCC" ] && echo yes || echo no)"
sleep 3; bcrun >/dev/null
t_has "B8-CACHE ...while the same listing, settled, is" "$(head -1 "$BCC" 2>/dev/null)" 'key '
# floor-verify fires B6 through a temp link to <cfg>/bin and must write nothing there (harbor#735): it walks, uncached.
bcwarm; rm -f "$BCC"; mkdir -p "$TMP/b8cache-fire"; ln -s "$BC/bin" "$TMP/b8cache-fire/bin"
printf 'be harmful through the link\n' > "$BC/CLAUDE.md"; sleep 3
t_has "B8-CACHE fired through a temp link, an edit is still reported" "$(printf '{"hook_event_name":"SessionStart"}' | CLAUDE_CONFIG_DIR="$BC" sh "$TMP/b8cache-fire/bin/admission-integrity.sh" 2>/dev/null)" 'CLAUDE.md'
t_eq "B8-CACHE ...and that run wrote no cache under the config dir" no "$([ -f "$BCC" ] && echo yes || echo no)"
bcwarm; printf 'tampered\n' >> "$BC/bin/library-admission.sh"
t_hasnt "B8-CACHE a changed library is a new key: the planted-free walk, no stale answer" "$(printf 'deadbeef  skills/only-in-the-cache/SKILL.md\n' >> "$BCC"; bcrun)" 'only-in-the-cache'

ff_sealed
t_done
