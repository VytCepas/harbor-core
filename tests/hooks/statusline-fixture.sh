# tests/hooks/statusline-fixture.sh — what the statusline parts share (L0-5, harbor#59, harbor#667).
# Sourced after core.sh: a config dir, the ANSI stripper, the renderers' runner and the teeth pin.
# SH runs the SUBJECTS: /bin/sh, or dash with --dash, since macOS sh forgives bashisms dash will not.
SH="${STATUSLINE_TEST_SH:-/bin/sh}"
for _a in "$@"; do case "$_a" in --dash) SH="$(command -v dash || echo /bin/sh)" ;; esac; done
printf 'subjects run under: %s\n' "$SH"
SRC="$T_ROOT/bin"; TMP="$T_TMP"; CFG="$T_TMP/cfg"
mkdir -p "$CFG/bin" "$CFG/cache" "$TMP/notrepo"
# A LITERAL escape byte: `sed 's/\033\[…'` strips nothing on BSD sed, silently.
# The machine row (row 3) is off here: rows 1-2 are asserted by position, and live ioreg is not a fixture.
export HARBOR_GLYPH_MACHINE=0
ESC="$(printf '\033')"
plain() { sed "s/${ESC}\\[[0-9]*m//g"; }
WS='"workspace":{"current_dir":"'"$TMP"'/notrepo"}'
NOW=1785600000
run() { printf '%s' "$1" | CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" "$SH" "$SRC/fleet-glyph.sh" 2>/dev/null; }
runat() { printf '%s' "$1" | CLAUDE_CONFIG_DIR="$CFG" HARBOR_CACHE_DIR="$CFG/cache" HARBOR_NOW="$NOW" "$SH" "$SRC/fleet-glyph.sh" 2>/dev/null; }
row1() { run "$1" | plain | head -1; }
row2() { run "{$WS}" | plain | sed -n 2p; }
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
pin() { # <config-dir> — writes the teeth pin that matches its settings.json
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' \
    "$1/settings.json" | sha > "$1/.helm-floor-teeth"
}
yn() { if "$@"; then echo yes; else echo no; fi; }
starts() { case "$1" in "$2"*) echo yes ;; *) printf 'no: %s' "$1" ;; esac; }  # <text> <prefix>
ends() { case "$1" in *"$2") echo yes ;; *) printf 'no: %s' "$1" ;; esac; }    # <text> <suffix>
DENY1='{"permissions":{"deny":["Read(~/.ssh/**)"]}}'
printf '%s\n' "$DENY1" > "$CFG/settings.json"
# Both rows at full payload, pinned and with one clean repo, for the grammar checks of two renderers.
GRAM='{"session_id":"abc123def","model":{"display_name":"Opus 5 (1M context)"},"context_window":{"context_window_size":1000000,"used_percentage":1},"effort":{"level":"xhigh"},"cost":{"total_cost_usd":1.57},'"$WS"',"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1785615180},"seven_day":{"used_percentage":49,"resets_at":1785755400}}}'
gram() {
  pin "$CFG"; printf '%s\n' '[{"status":{"dirty":false},"drift":{"status":"clean","total":0}}]' > "$CFG/cache/fleet-snapshot.json"
  runat "$GRAM" | plain
}
