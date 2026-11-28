#!/usr/bin/env sh
# fleet-snapshot-refresh writes the snapshot only when it changed (155 KB a tick, 288 ticks a day). An unchanged tick leaves the
# file's bytes and inode alone and touches its mtime, because the glyph's staleness reads the mtime; a changed one replaces it.
# The refresher runs alone in a temp bin/ with a stub orchestrator, so no sibling job runs.
. "$(dirname "$0")/../../lib/core.sh"; t_init
W="$T_TMP/w"; mkdir -p "$W/bin" "$W/cfg" "$W/cache"
cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/status-fleet-snapshot-refresh.sh" "$W/bin/"
printf '#!/bin/sh\ncat "%s/orch.out"\n' "$W" > "$W/orch"; chmod +x "$W/orch"
CACHE="$W/cache/fleet-snapshot.json"
run() { # <script> — one refresh as launchd starts it
  env CLAUDE_CONFIG_DIR="$W/cfg" HARBOR_SCOPE_CACHE_DIR="$W/cache" HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$W/orch" \
    HARBOR_SCOPE_FLEET_FILE="$W/fleet.yaml" HARBOR_CI_GOVERNOR_ADMITTED=1 sh "$1" >/dev/null 2>&1
}
inode() { ls -i "$1" | awk '{ print $1 }'; }
recent() { [ -n "$(find "$1" -newer "$W/ref" 2>/dev/null)" ] && echo yes || echo no; }

# the case, against a given copy of the script: prints ok or what was wrong
case_unchanged() { # <script>
  _bad=""; rm -f "$CACHE"; printf '[{"id":1},{"id":2}]' > "$W/orch.out"
  run "$1"; _i1="$(inode "$CACHE")"
  touch -t 200001010000 "$CACHE"; : > "$W/ref"; sleep 1; touch "$W/ref"
  run "$1"
  [ "$(cat "$CACHE")" = '[{"id":1},{"id":2}]' ] || _bad="$_bad [content changed]"
  [ "$(inode "$CACHE")" = "$_i1" ] || _bad="$_bad [an unchanged snapshot was rewritten: its inode changed]"
  [ "$(recent "$CACHE")" = yes ] || _bad="$_bad [the unchanged snapshot's mtime was not refreshed: the glyph would call it stale]"
  printf '[{"id":1},{"id":3}]' > "$W/orch.out"
  run "$1"
  [ "$(cat "$CACHE")" = '[{"id":1},{"id":3}]' ] || _bad="$_bad [a changed snapshot was not written]"
  printf '%s' "${_bad:-ok}"
}

t_section "an unchanged tick writes nothing; a changed one still writes"
t_eq "the real script" ok "$(case_unchanged "$W/bin/status-fleet-snapshot-refresh.sh")"

t_section "red-proof: with the comparison taken out the same case fails"
mkdir -p "$W/bin2"; cp "$W/bin/library-log.sh" "$W/bin2/"
awk '{ i = index($0, "cmp -s \"$TMP\" \"$CACHE\""); if (i) { $0 = substr($0, 1, i - 1) "false" substr($0, i + length("cmp -s \"$TMP\" \"$CACHE\"")); n++ } print } END { exit n == 1 ? 0 : 3 }' \
  "$W/bin/status-fleet-snapshot-refresh.sh" > "$W/bin2/status-fleet-snapshot-refresh.sh" && t_pass || t_fail "the mutation did not apply"
_v="$(case_unchanged "$W/bin2/status-fleet-snapshot-refresh.sh")"
_caught=no; case "$_v" in *rewritten*) _caught=yes ;; esac
t_eq "the broken copy is caught on the rewrite" yes "$_caught"
t_done
