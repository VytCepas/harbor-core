#!/usr/bin/env sh
# harbor desktop (D-95, harbor#1440): the MCP server's tools and confirm rule, the CLI's relay (a caller cannot smuggle
# the confirm flag or the verb), and — on a Mac with swiftc — the helper's own policy self-test, with mutants.
# Nothing here needs a macOS grant or touches a real app.
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"
. "$(dirname "$0")/../../lib/core.sh"; t_init
command -v python3 >/dev/null 2>&1 || { t_fail "python3 is required (the CLI's JSON step)"; t_done; }

t_section "the CLI relays one JSON line; the verb and confirm are its own"
X="$T_TMP/x"; mkdir -p "$X/bin" "$X/contracts" "$T_TMP/fakebin" "$T_TMP/state"
cp "$T_ROOT/bin/access-desktop.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$X/bin/"
cp "$T_ROOT/contracts/roots.tsv" "$X/contracts/" 2>/dev/null || :
# A stand-in nc: records the request line and answers ok, so no helper and no grant is needed.
cat > "$T_TMP/fakebin/nc" <<EOF
#!/bin/sh
cat >> "$T_TMP/sent"; printf '{"ok":true}\n'
EOF
chmod +x "$T_TMP/fakebin/nc"
cli() { : > "$T_TMP/sent"; PATH="$T_TMP/fakebin:$PATH" HARBOR_ACCESS_DESKTOP_STATE="$T_TMP/state" HARBOR_SCOPE_PRIVATE=/nonexistent \
  sh "$X/bin/access-desktop.sh" "$@" >/dev/null 2>&1; tail -1 "$T_TMP/sent"; }
S="$(cli tree '{"bundle":"com.apple.TextEdit","confirmed":true,"verb":"script"}')"
t_has "the verb is the CLI's argument" "$S" '"verb": "tree"'
t_hasnt "a smuggled confirmed is dropped" "$S" 'confirmed'
S="$(cli key '{"bundle":"com.apple.TextEdit","combo":"return"}' --confirm)"
t_has "--confirm sets confirmed" "$S" '"confirmed": true'
t_exit "an unknown verb is refused before anything is sent" 64 env PATH="$T_TMP/fakebin:$PATH" HARBOR_ACCESS_DESKTOP_STATE="$T_TMP/state" sh "$X/bin/access-desktop.sh" eval '{}'
t_exit "args that are not an object are refused" 1 env PATH="$T_TMP/fakebin:$PATH" HARBOR_ACCESS_DESKTOP_STATE="$T_TMP/state" HARBOR_SCOPE_PRIVATE=/nonexistent sh "$X/bin/access-desktop.sh" tree '[1]'

t_section "the MCP server: one tool per verb; a confirm tool needs the operator's ask rule"
if ! command -v bun >/dev/null 2>&1; then
  echo "  SKIP mcp: bun is not installed (the server's interpreter)"
  t_eq "HARBOR_TEST_REQUIRE_BUN is off where bun is absent" 0 "$REQ_BUN"
else
  cp "$T_ROOT/bin/access-desktop-mcp.ts" "$X/bin/"
  cat > "$X/bin/access-desktop.sh" <<'EOF'
printf '{"ok":true,"argv":"%s"}\n' "$*"
EOF
  H="$T_TMP/home"; mkdir -p "$H/.claude"
  rpc() { printf '%s\n' "$@" | HOME="$H" bun "$X/bin/access-desktop-mcp.ts" 2>&1; }
  callj() { printf '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"%s","arguments":%s}}' "$1" "$2"; }
  OUT="$(rpc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}')"
  t_eq "initialize names the server harbor_desktop" harbor_desktop "$(printf '%s' "$OUT" | jq -r .result.serverInfo.name)"
  TL="$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[].name' | sort | tr '\n' ' ')"
  t_eq "the tools" "action apps confirm_key confirm_menu confirm_press doctor key menu press script set_value shortcut_run shortcuts_list shot tree type windows " "$TL"
  _bad=""; for _n in $TL; do sh "$T_ROOT/bin/lint-name.sh" --check mcp-tool "mcp__harbor_desktop__$_n" 2>&1 | grep -q 'no finding' || _bad="$_bad $_n"; done
  t_eq "every tool name passes the mcp-tool surface" "" "$_bad"
  printf '{"permissions":{"ask":[]}}\n' > "$H/.claude/settings.json"
  R="$(rpc "$(callj script '{"source":"beep"}')")"
  t_has "script without an ask rule is refused" "$(printf '%s' "$R" | jq -r '.result.content[0].text')" "no permissions.ask rule"
  t_eq "...as an error" true "$(printf '%s' "$R" | jq -r .result.isError)"
  printf '{"permissions":{"ask":["mcp__harbor_desktop__script","mcp__harbor_desktop__confirm_press"]}}\n' > "$H/.claude/settings.json"
  t_has "with the ask rule, script passes --confirm" "$(rpc "$(callj script '{"source":"beep"}')" | jq -r '.result.content[0].text')" "--confirm"
  T="$(rpc "$(callj press '{"bundle":"b","ref":"0.1","confirmed":true}')" | jq -r '.result.content[0].text')"
  t_hasnt "press never passes --confirm, whatever its arguments say" "$T" "--confirm"
  t_hasnt "...and drops a smuggled confirmed" "$T" "confirmed"
  t_has "press is AXPress" "$T" "AXPress"
  t_has "confirm_press passes --confirm" "$(rpc "$(callj confirm_press '{"bundle":"b","ref":"0.1","expect":"Send"}')" | jq -r '.result.content[0].text')" "--confirm"
fi

t_section "the helper's policy (a Mac with swiftc only)"
if [ "$(uname)" != Darwin ] || ! command -v swiftc >/dev/null 2>&1; then
  echo "  SKIP helper: not a Mac with swiftc"
  t_pass
else
  B="$T_TMP/build"; mkdir -p "$B/mc"
  build() { swiftc -O -swift-version 5 -module-cache-path "$B/mc" -o "$B/$2" "$1" >/dev/null 2>&1; }
  W="words=$T_ROOT/contracts/live-change-words.txt"
  if build "$T_ROOT/bin/access-desktop-helper.swift" h; then
    O="$("$B/h" selftest "$W" 2>&1)"; r=$?
    t_eq "the self-test passes" "0" "$r"
    t_has "...and ran every check" "$O" "an empty word list refuses every guarded call"
    # Mutants: each planted defect must turn the self-test red.
    sed 's/if hardDeny.contains(bundle) { throw/if false { throw/' "$T_ROOT/bin/access-desktop-helper.swift" > "$B/m1.swift"
    build "$B/m1.swift" m1 && { "$B/m1" selftest "$W" >/dev/null 2>&1; t_eq "MUTANT: no hard deny → red" 1 "$?"; } || t_fail "mutant 1 did not compile"
    sed 's/if let w = liveWord(text), (r\["confirmed"\]/if let w = liveWord(text), false \&\& (r["confirmed"]/' "$T_ROOT/bin/access-desktop-helper.swift" > "$B/m2.swift"
    build "$B/m2.swift" m2 && { "$B/m2" selftest "$W" >/dev/null 2>&1; t_eq "MUTANT: gate never refuses → red" 1 "$?"; } || t_fail "mutant 2 did not compile"
    sed 's/if !lab.contains(want) { throw/if false { throw/' "$T_ROOT/bin/access-desktop-helper.swift" > "$B/m3.swift"
    build "$B/m3.swift" m3 && { "$B/m3" selftest "$W" >/dev/null 2>&1; t_eq "MUTANT: a moved ref acts on its neighbour → red" 1 "$?"; } || t_fail "mutant 3 did not compile"
  else t_fail "the helper did not compile"; fi
fi
t_done
