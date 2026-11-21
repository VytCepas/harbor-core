#!/usr/bin/env sh
# bin/access-redact.sh and the two harbor chrome routes that pass every reply through it (contracts/secret-intake.md):
# what is masked, what is left alone, that it fails closed, that its token shapes ARE the egress guard's list, and that
# a screenshot or pdf of a page showing a credential is refused. Each protection has a mutant that removes it.
REQ_BUN="${HARBOR_TEST_REQUIRE_BUN:-0}"  # before t_init clears it
. "$(dirname "$0")/../../lib/core.sh"; t_init
RED="$T_ROOT/bin/access-redact.sh"
# Token-shaped strings are built here, never written whole, so no file or command line carries one. Synthetic bodies.
AZ=ABCDEFGHIJKLMNOPQRSTUVWXYZ
K_OAI="sk-svc""acct-$AZ"; K_GH="gh""p_$AZ"; K_AWS="AK""IA""ABCDEFGHIJKLMNOP"; TOK="SEKRET""VALUE""123"
red() { sh "$RED" "$@" < "$T_TMP/in" > "$T_TMP/out" 2> "$T_TMP/err"; echo "exit $?"; }
o() { cat "$T_TMP/out"; }

t_section "provider token shapes, secret-labelled fields and secret URL parameters are masked"
{
  printf '      - generic [ref=e9]: %s\n' "$K_OAI"
  printf '      - paragraph: your token %s and key %s\n' "$K_GH" "$K_AWS"
  printf '        - textbox "Password" [ref=e33]: hunter2-not-real\n'
  printf '        - textbox "Client secret" [ref=e34]: cs-%s\n' "$TOK"
  printf '        - textbox "API key" [active] [ref=e35]: k-%s\n' "$TOK"
  printf '      - textbox "Verification code" [ref=e36]: 123456\n'
  printf -- '- Page URL: https://app.example.com/cb?state=xyz&access_%s=%s&ok=1\n' token "$TOK"
  printf -- '- Page URL: https://app.example.com/cb?client_%s=%s\n' secret "$TOK"
} > "$T_TMP/in"
t_eq "the filter passes" "exit 0" "$(red)"
t_eq "no OpenAI key is left" 0 "$(o | grep -c "$K_OAI")"
t_eq "no GitHub or AWS key is left" 0 "$(o | grep -cE "$K_GH|$K_AWS")"
t_eq "no field value is left" 0 "$(o | grep -cE 'hunter2|cs-|k-SEKRET|123456')"
t_eq "no URL secret is left" 0 "$(o | grep -c "$TOK")"
t_eq "each of the eight lines says [REDACTED]" 8 "$(o | grep -c '\[REDACTED\]')"
t_has "the field keeps its label and ref" "$(o)" 'textbox "Password" [ref=e33]: [REDACTED]'
t_has "the URL keeps its other parameters" "$(o)" '?state=xyz&access_token=[REDACTED]&ok=1'
t_eq "and the clean run logs nothing" "" "$(cat "$T_TMP/err")"

t_section "what is not a secret passes byte for byte"
{
  printf '      - textbox "Login" [active] [ref=e26]: someone@example.com\n'
  printf '      - textbox "Search" [ref=e9]: tokens per day\n'
  printf '      - textbox "Postal code" [ref=e8]: LT-01100\n'
  printf '        - textbox "Password" [ref=e34]\n'
  printf -- '- Page URL: https://ads.openai.com/manage/campaigns?act=adacct_6a9fcfd444e4819c8e0bce02032e76fb\n'
  printf '      - button "Continue as Mediabrands, tools@example.com" [ref=f3e3]\n'
  printf 'caf\351 menu, a byte that is not UTF-8\n'
} > "$T_TMP/in"
t_eq "the filter passes" "exit 0" "$(red)"
t_eq "the output is the input" "same" "$(cmp -s "$T_TMP/in" "$T_TMP/out" && echo same)"
t_eq "--check on it is 0" "exit 0" "$(red --check)"
t_eq "and prints nothing" "" "$(o)"
printf '        - textbox "Password" [ref=e33]: hunter2\n' > "$T_TMP/in"
t_eq "--check on a secret field is 1" "exit 1" "$(red --check)"
t_eq "and prints nothing" "" "$(o)"

t_section "fail closed: no list, no text"
printf 'line one %s\n' "$K_OAI" > "$T_TMP/in"
t_eq "with no egress guard the filter withholds, exit 3" "exit 3" "$(HARBOR_ACCESS_REDACT_EGRESS="$T_TMP/none" red)"
t_eq "stdout is the one withheld line" 1 "$(o | grep -c .)"
t_has "saying why" "$(o)" "output withheld: the credential redactor failed: no SECRET list"
t_eq "and none of the input" 0 "$(o | grep -c 'line one')"
t_has "logged as a FAIL with its fix" "$(cat "$T_TMP/err")" "fix: ls -l"
t_eq "--check withholds too, exit 3, nothing printed" "exit 3" "$(HARBOR_ACCESS_REDACT_EGRESS="$T_TMP/none" red --check)"
t_eq "and stdout is empty" "" "$(o)"

t_section "one list: the shapes are the egress guard's SECRET, read from the file beside it"
printf "SECRET='(ZZQ[0-9]{6})'\n" > "$T_TMP/egress.sh"
printf 'a ZZQ123456 b %s\n' "$K_OAI" > "$T_TMP/in"
t_eq "a fixture guard's list is the one used" "exit 0" "$(HARBOR_ACCESS_REDACT_EGRESS="$T_TMP/egress.sh" red)"
t_eq "its shape is masked" 0 "$(o | grep -c ZZQ123456)"
t_eq "and a shape it does not list passes, so the filter holds no list of its own" 1 "$(o | grep -c "$K_OAI")"
t_eq "CONTROL: the real guard's SECRET line is one the filter can read" 1 "$(grep -c "^SECRET='" "$T_ROOT/bin/admission-egress.sh")"

t_section "mutants: each rule removed, its secret comes back"
M="$T_TMP/m"; mkdir -p "$M"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/admission-egress.sh" "$M/"
printf '        - textbox "Password" [ref=e33]: hunter2-not-real\n      - generic: %s\n' "$K_OAI" > "$T_TMP/in"
sed '/l = substr(l, 1, RSTART + RLENGTH - 1) "\[REDACTED\]"; hit = 1/d' "$RED" > "$M/access-redact.sh"
t_eq "the field mutant differs" yes "$(cmp -s "$RED" "$M/access-redact.sh" || echo yes)"
sh "$M/access-redact.sh" < "$T_TMP/in" > "$T_TMP/out" 2>/dev/null
t_eq "without the field rule the password passes" 1 "$(o | grep -c hunter2-not-real)"
sed 's/^sed $SEDU -E -e "$E1" -e "$E2"/sed $SEDU -E -e "$E2"/' "$RED" > "$M/access-redact.sh"
t_eq "the shape mutant differs" yes "$(cmp -s "$RED" "$M/access-redact.sh" || echo yes)"
sh "$M/access-redact.sh" < "$T_TMP/in" > "$T_TMP/out" 2>/dev/null
t_eq "without the shape rule the key passes" 1 "$(o | grep -c "$K_OAI")"

# ── the shell route: bin/access-browser-agent.sh (also the CLI and the python server's) ─────────────────────────────
AGENT="$T_ROOT/bin/access-browser-agent.sh"; unset HARBOR_ACCESS_CHROME HARBOR_ACCESS_REDACTED
HARBOR_ACCESS_BROWSER_SETTLE=0; export HARBOR_ACCESS_BROWSER_SETTLE
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"
t_section "the shell route: every byte it prints is filtered, and its exit is kept"
SURL="https://business.facebook.com/cb?access_token=$TOK"
t_eq "a goto that lands on a token URL passes" "exit 0" "$(STUB_PAGE_URL="$SURL" ag goto https://business.facebook.com/)"
t_eq "the token is not in what it printed" 0 "$(out | grep -c "$TOK")"
t_has "the URL is, masked" "$(out)" "access_token=[REDACTED]"
t_eq "a refusal keeps its exit through the filter" "exit 1" "$(ag no-such-verb)"
t_has "and its words" "$(out)" "verb refused: no-such-verb"
W="$T_TMP/wm"; mkdir -p "$W/bin" "$W/contracts"; cp "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/admission-egress.sh" "$W/bin/"
cp "$T_ROOT/contracts/browser-agent-hosts.txt" "$T_ROOT/contracts/browser-script.tsv" "$T_ROOT/contracts/live-change-words.txt" "$W/contracts/"
cp "$AGENT" "$W/bin/access-browser-agent.sh"
t_eq "with the filter missing the agent withholds, exit 3" "exit 3" "$(AGENT="$W/bin/access-browser-agent.sh" ag state)"
t_has "naming the missing file, not a silent SIGPIPE" "$(out)" "access-redact.sh is missing"
cp "$RED" "$W/bin/"
sed '/^if \[ "${HARBOR_ACCESS_REDACTED:-}" != 1 \]; then$/,/^fi$/d' "$AGENT" > "$W/bin/access-browser-agent.sh"
t_eq "the wrapper mutant differs" yes "$(cmp -s "$AGENT" "$W/bin/access-browser-agent.sh" || echo yes)"
( STUB_PAGE_URL="$SURL" AGENT="$W/bin/access-browser-agent.sh" ag goto https://business.facebook.com/ >/dev/null )   # a prefix on a function persists in sh
t_eq "without the wrapper the token comes back" 1 "$(out | grep -c "$TOK")"

t_section "the shell route: a screenshot or pdf of a page that shows a credential is refused"
_s0="$(called ' screenshot')"
t_eq "a plain page: screenshot passes" "exit 0" "$(ag screenshot)"
t_eq "and reaches the CLI" "$((_s0 + 1))" "$(called ' screenshot')"
t_eq "a page showing a key: screenshot is refused" "exit 1" "$(STUB_SHOWN="here is $K_OAI" ag screenshot)"
t_has "saying an image cannot be redacted" "$(out)" "an image cannot be redacted"
t_has "and the way on" "$(out)" "--value-clipboard"
t_eq "the CLI never took it" "$((_s0 + 1))" "$(called ' screenshot')"
t_eq "pdf the same" "exit 1" "$(STUB_SHOWN="here is $K_OAI" ag pdf)"
t_eq "a page that cannot be read is refused, not shot" "exit 1" "$(STUB_EVAL_FAIL=1 ag screenshot)"
sed '/^    case "$VERB" in screenshot|pdf)$/,/^    esac$/d' "$AGENT" > "$W/bin/access-browser-agent.sh"
t_eq "the guard mutant differs" yes "$(cmp -s "$AGENT" "$W/bin/access-browser-agent.sh" || echo yes)"
t_eq "without the guard the screenshot goes through" "exit 0" "$(STUB_SHOWN="here is $K_OAI" AGENT="$W/bin/access-browser-agent.sh" ag screenshot)"

# ── the MCP route: bin/access-chrome-mcp.ts, against the fake daemon ──────────────────────────────────────────────────
. "$(dirname "$0")/server-env.sh"
t_section "the MCP route: every reply is filtered"
# The fake daemon's snapshot carries no page body; its goto reply carries the landing URL, so the secret rides in that.
printf 'https://business.facebook.com/x/%s?state=1&api_key=%s' "$K_OAI" "$TOK" > "$CTL/page_url"
t_eq "a goto passes" "exit 0" "$(mcp goto https://business.facebook.com/)"
t_eq "the key in the path is not in the reply" 0 "$(txt | grep -c "$K_OAI")"
t_eq "nor the api_key value" 0 "$(txt | grep -c "$TOK")"
t_has "the parameter is masked in place" "$(txt)" "?state=1&api_key=[REDACTED]"
sed 's/text: redacted(r.text)/text: r.text/' "$T_ROOT/bin/access-chrome-mcp.ts" > "$X/bin/access-chrome-mcp.ts"
t_eq "the reply mutant differs" yes "$(cmp -s "$T_ROOT/bin/access-chrome-mcp.ts" "$X/bin/access-chrome-mcp.ts" || echo yes)"
mcp goto https://business.facebook.com/ >/dev/null
t_eq "without the filter the key comes back" 1 "$(txt | grep -c "$K_OAI")"
cp "$T_ROOT/bin/access-chrome-mcp.ts" "$X/bin/"
mv "$X/bin/access-redact.sh" "$X/bin/access-redact.keep"
t_eq "with the filter missing the reply is withheld" "exit 0" "$(mcp goto https://business.facebook.com/)"
t_has "saying so" "$(txt)" "output withheld, the credential redactor failed"
t_eq "and none of the page" 0 "$(txt | grep -c business.facebook.com)"
mv "$X/bin/access-redact.keep" "$X/bin/access-redact.sh"; rm -f "$CTL/page_url"

t_section "the MCP route: a screenshot or pdf of a page that shows a credential is refused"
clean; : > "$CALLS"
t_eq "a plain page: screenshot passes" "exit 0" "$(mcp screenshot)"
t_eq "and the daemon took it" 1 "$(n '^screenshot')"
printf 'here is %s' "$K_OAI" > "$CTL/shown"; : > "$CALLS"
t_eq "a page showing a key: screenshot is refused" "exit 1" "$(mcp screenshot)"
t_has "saying an image cannot be redacted" "$(txt)" "an image cannot be redacted"
t_eq "the daemon never took it" 0 "$(n '^screenshot')"
t_eq "pdf the same" "exit 1" "$(mcp pdf)"
sed "s/if (verb === 'screenshot' || verb === 'pdf') await shownSecretGuard(c, S, wd, verb);//" "$T_ROOT/bin/access-chrome-mcp.ts" > "$X/bin/access-chrome-mcp.ts"
t_eq "the guard mutant differs" yes "$(cmp -s "$T_ROOT/bin/access-chrome-mcp.ts" "$X/bin/access-chrome-mcp.ts" || echo yes)"
t_eq "without the guard the screenshot goes through" "exit 0" "$(mcp screenshot)"
cp "$T_ROOT/bin/access-chrome-mcp.ts" "$X/bin/"; rm -f "$CTL/shown"
t_done
