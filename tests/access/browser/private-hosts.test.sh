#!/usr/bin/env sh
# `harbor chrome` reads the private layer's browser-hosts.txt beside the core allowlist (harbor#1149).
# Core names no internal or client host; the operator's own are data in the private layer. The CLI is a stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
AGENT="$T_ROOT/bin/access-browser-agent.sh"
STUB="$T_TMP/pw-stub"; printf '#!/bin/sh\necho "STUB $*"\n' > "$STUB"; chmod +x "$STUB"
PH="$T_TMP/private-hosts.txt"
rc() { "$@" >"$T_TMP/out" 2>&1 && echo "exit 0" || echo "exit $?"; }
out() { cat "$T_TMP/out"; }
ag() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_PRIVATE_HOSTS="$PH" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@"; }

t_section "with no private list only the core allowlist counts"
t_eq "a core vendor UI opens" "exit 0" "$(ag goto https://ads.reddit.com/)"
t_eq "an internal host is refused" "exit 1" "$(ag goto https://wiki.example.invalid/)"
t_has "and the refusal names the private file" "$(out)" "browser-hosts.txt"

t_section "a line in the private list admits the host and its subdomains"
printf '# An internal wiki, exact host\nwiki.example.invalid\n# A client media-plan app\nplan.example.invalid\n' > "$PH"
t_eq "a listed host opens" "exit 0" "$(ag goto https://wiki.example.invalid/page)"
t_eq "a subdomain of a listed line opens, the core rule" "exit 0" "$(ag goto https://a.plan.example.invalid/)"
t_eq "an unlisted sibling is still refused" "exit 1" "$(ag goto https://other.example.invalid/)"
t_eq "the parent of a listed host is not admitted" "exit 1" "$(ag goto https://example.invalid/)"
t_eq "a lookalike suffix is not admitted" "exit 1" "$(ag goto https://notwiki.example.invalid/)"
t_eq "http is refused whatever the list holds" "exit 1" "$(ag goto http://wiki.example.invalid/)"
t_eq "a core vendor still opens beside a private list" "exit 0" "$(ag goto https://ads.reddit.com/)"

t_section "a missing or unreadable private list leaves the core list alone"
rm -f "$PH"
t_eq "a core vendor opens" "exit 0" "$(ag goto https://ads.reddit.com/)"
t_eq "the formerly listed host is refused again" "exit 1" "$(ag goto https://wiki.example.invalid/)"

t_section "the private layer is found through the resolver when no seam is given"
PV="$T_TMP/priv"; mkdir -p "$PV"
printf '# An internal wiki\nwiki.example.invalid\n' > "$PV/browser-hosts.txt"
rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN -u HARBOR_BROWSER_PRIVATE_HOSTS HARBOR_SCOPE_PRIVATE="$PV" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" goto https://wiki.example.invalid/ >/dev/null
t_eq "HARBOR_SCOPE_PRIVATE/browser-hosts.txt admits its host" "exit 0" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN -u HARBOR_BROWSER_PRIVATE_HOSTS HARBOR_SCOPE_PRIVATE="$PV" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" goto https://wiki.example.invalid/)"
rm -f "$PV/browser-hosts.txt"
t_eq "and without the file it is refused" "exit 1" "$(rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN -u HARBOR_BROWSER_PRIVATE_HOSTS HARBOR_SCOPE_PRIVATE="$PV" HARBOR_PW_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" goto https://wiki.example.invalid/)"

t_section "the Claude-in-Chrome route hook reads the same list"
HK="$T_ROOT/context-rules/user/browser-route.sh"
HR="$T_TMP/hookroot"; mkdir -p "$HR/contracts" "$HR/bin" "$T_TMP/inj"
cp "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/library-log.sh" "$HR/bin/"; cp "$T_ROOT/contracts/roots.tsv" "$HR/contracts/"
printf '# A vendor\nads.example.net\n' > "$HR/contracts/browser-agent-hosts.txt"
cp "$HK" "$T_TMP/inj/browser-route.sh"
printf 'harbor\t%s\n' "$HR" > "$T_TMP/inj/projects.tsv"
hook() { printf '{"tool_input":{"url":"%s"}}' "$1" | env HARBOR_SCOPE_PRIVATE="$PV" sh "$T_TMP/inj/browser-route.sh" 2>/dev/null; }
t_eq "a core vendor is refused toward harbor chrome" "yes" "$(hook https://ads.example.net/x | grep -q 'harbor chrome' && echo yes || echo no)"
t_eq "an unlisted host is silent" "" "$(hook https://wiki.example.invalid/)"
printf '# An internal wiki\nwiki.example.invalid\n' > "$PV/browser-hosts.txt"
t_eq "a host only the private list holds is refused toward harbor chrome" "yes" "$(hook https://wiki.example.invalid/ | grep -q 'harbor chrome' && echo yes || echo no)"
t_done
