# The stub Playwright CLI and AppleScript every agent suite drives `harbor chrome` against:
# sourced after core.sh, it defines rc/out/ag/called/osa and exports no real Chrome.
rc() { "$@" > "$T_TMP/out" 2>&1; echo "exit $?"; }  # the exit, with the output left in $T_TMP/out
out() { cat "$T_TMP/out"; }
STUB="$T_TMP/pwcli"; CALLS="$T_TMP/calls"; SNAP="$T_TMP/snap.yml"
# The stub logs every call, and a `snapshot --filename=X` writes $SNAP to X — the
# real CLI's format (0.1.22, measured 2026-10-01), so the guard reads a real shape.
cat > "$STUB" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$CALLS"
if [ -n "\${STUB_GONE:-}" ]; then
  printf "The browser '%s' is not open, please run open first\n\n  playwright-cli %s open [params]\n" "\${1#-s=}" "\$1"; exit 1
fi
for a in "\$@"; do case "\$a" in --filename=*) f="\${a#--filename=}" ;; esac; done
case " \$* " in *" snapshot "*) [ -z "\${f:-}" ] || cp "$SNAP" "\$f" ;; esac
# The real CLI drains stdin; STUB_READS_STDIN makes the stub do the same.
[ -z "\${STUB_READS_STDIN:-}" ] || cat >/dev/null
# tab-list answers in the real CLI's shape, with STUB_URL as the current page.
case " \$* " in *" tab-list "*) [ -z "\${STUB_URL:-}" ] || { printf -- '- 0: (current) [Page](%s)\n' "\$STUB_URL"; exit 0; } ;; esac
# STUB_LATE_BLANK: the tab goes blank 0.3 s after a fill, as the real detach did.
case " \$* " in *" fill "*) [ -z "\${STUB_LATE_BLANK:-}" ] || ( sleep 0.3; : > "\$STUB_LATE_BLANK" ) & ;; esac
# eval answers the state probe in the real --raw shape: a JSON string, quotes escaped.
case " \$* " in *" eval "*)
  [ -z "\${STUB_EVAL_FAIL:-}" ] || { echo "Error: Execution context was destroyed"; exit 1; }
  if [ -n "\${STUB_HIDDEN:-}" ]; then printf '%s\n' '"{\"visibility\":\"hidden\",\"host\":\"business.facebook.com\",\"blank\":false}"'
  elif [ -n "\${STUB_BLANK:-}" ] || { [ -n "\${STUB_LATE_BLANK:-}" ] && [ -e "\$STUB_LATE_BLANK" ]; }; then printf '%s\n' '"{\"host\":\"\",\"blank\":true}"'
  else printf '%s\n' '"{\"host\":\"business.facebook.com\",\"blank\":false}"'; fi
  exit 0 ;;
esac
# STUB_UPLOAD_DENIED: Chrome refuses the file input, as it does without file-URL access.
case " \$* " in *" upload "*) [ -z "\${STUB_UPLOAD_DENIED:-}" ] || { echo 'fileChooser.setFiles: Protocol error (DOM.setFileInputFiles): {"code":-32000,"message":"Not allowed"}'; exit 1; } ;; esac
# STUB_PAGE_URL: where the page landed, in the CLI's own "- Page URL:" line.
[ -z "\${STUB_PAGE_URL:-}" ] || case " \$* " in *" goto "*|*" click "*|*" tab-new "*|*" reload "*) printf -- '- Page URL: %s\n' "\$STUB_PAGE_URL" ;; esac
# STUB_TOKEN_URL: the CLI prints the extension's connect page, token and all, as it does after attach.
[ -z "\${STUB_TOKEN_URL:-}" ] || printf -- '- 0: (current) [Welcome](chrome-extension://mmlmfjhmonkocbjadbfplnigmagldckm/connect.html?mcpRelayUrl=ws&token=SEKRET99)\n'
# STUB_XERR: a goto loses the tab to another extension's frame, logged where the relay logs it.
case " \$* " in *" goto "*) [ -z "\${STUB_XERR:-}" ] || { echo 'pw:mcp:error Error: Cannot access a chrome-extension:// URL of different extension' >> "\$STUB_XERR"; echo 'Error: Target page, context or browser has been closed'; exit 1; } ;; esac
# STUB_FAIL: every verb but snapshot fails as a wait on an unpainted page does.
case " \$* " in *" snapshot "*) ;; *) [ -z "\${STUB_FAIL:-}" ] || { echo "TimeoutError: Timeout 5000ms exceeded."; exit 1; } ;; esac
printf "STUB profile=%s pwd=%s args=%s debug=%s\n" "\${PLAYWRIGHT_MCP_PROFILE_DIR_NAME:-}" "\$PWD" "\$*" "\${DEBUG:-}"
EOF
chmod +x "$STUB"
cat > "$SNAP" <<'EOF'
- generic [active] [ref=e1] [box=8,16,1264,55]:
  - paragraph [ref=e2] [box=8,16,1264,18]: nothing clicked
  - button "Spoof [ref=e4] [box=1,1,1,1]" [ref=e17] [box=400,50,20,20]: "[ref=e4]"
  - paragraph [ref=e18]: text [ref=e4] here, and [ref=e9] [box=1,1,1,1]
  - button "Create" [ref=e3] [cursor=pointer] [box=8,50,56,21]
  - button "Delete campaign" [ref=e4] [box=68,50,116,21]
  - button "Remove" [ref=e5] [box=188,50,23,21]: x
  - button "Ištrinti" [ref=e6] [box=215,50,52,21]
  - generic [ref=e7] [box=862,0,420,720]:
    - heading "Set up conversion tracking" [level=2] [ref=e8] [box=862,20,420,28]
    - button "Create data source" [ref=e9] [cursor=pointer] [box=862,68,129,21]
  - button [ref=e10] [box=300,50,20,20]:
    - img "Delete" [ref=e11]
  - cell "Campaign A Paused Removed" [ref=e12] [box=8,80,400,20]
  - button "Payments" [ref=e13] [box=8,110,80,20]
  - button "APMOKĖTI" [ref=e14] [box=100,110,80,20]
  - button "Hidden" [ref=e15] [box=0,0,0,0]
  - button "Save" [ref=e19] [box=600,600,100,30]
  - dialog "Confirm" [ref=e20] [box=590,590,200,60]:
    - button "Delete" [ref=e21] [box=600,600,100,30]
  - button "[delete]" [ref=e22] [box=8,140,80,20]
  - button "Unlink" [ref=e23] [box=8,170,80,20]
  - iframe [ref=e16] [box=52,8,904,304]:
    - generic [ref=f2e1] [box=8,16,884,55]:
      - button "Create" [ref=f2e3] [box=8,50,56,21]
EOF
called() { grep -c -- "$1" "$CALLS" 2>/dev/null || :; }  # how many CLI calls carried $1
# AppleScript stub, exported for every case: no test may open a window in the real Chrome.
# It logs which script ran and answers from $OSA_TABS (window, tab, active, url per line).
OSA="$T_TMP/osascript"; OSACALLS="$T_TMP/osacalls"; OSA_TABS="$T_TMP/osatabs"
TAB="$(printf '\t')"
cat > "$OSA" <<EOF
#!/bin/sh
sc="\$(cat)"
case "\$sc" in
  *'make new window'*) echo window >> "$OSACALLS"; printf '9\t%s\t%s\t7' "\${STUB_NEW_TAB:-501}" "\${STUB_PREV_APP:-com.apple.Terminal}" ;;
  *'set index of'*) echo "raise \$2" >> "$OSACALLS" ;;
  *'whose id is'*) shift; echo "close \$*" >> "$OSACALLS"
    [ -z "\${STUB_OSA_FAIL:-}" ] || exit 1
    echo "\$#" ;;
  *'set active tab index'*) echo "front \$2" >> "$OSACALLS"
    [ -z "\${STUB_OSA_FAIL:-}" ] || exit 1
    awk -F '\t' -v u="\$2" 'substr(\$4, length(\$4) - length(u) + 1) == u { print "window " \$1 " tab " \$2; exit }' "$OSA_TABS" ;;
  *) echo tabs >> "$OSACALLS"; cat "$OSA_TABS"
    # \$OSA_TABS.next is the list after this one: Chrome before and after a verb
    [ ! -f "$OSA_TABS.next" ] || mv "$OSA_TABS.next" "$OSA_TABS" ;;
esac
EOF
chmod +x "$OSA"; : > "$OSA_TABS"
HARBOR_OSASCRIPT="$OSA"; export HARBOR_OSASCRIPT
# The access register's route cards: a fixture, so no case reads the box's own.
ACC="$T_TMP/access"; mkdir -p "$ACC"; HARBOR_ACCESS_DIR="$ACC"; export HARBOR_ACCESS_DIR
osa() { grep -c -- "$1" "$OSACALLS" 2>/dev/null || :; }
# PH is the private layer's extra hosts: none unless a case writes it, so the box's own layer never decides a result.
PH="$T_TMP/private-browser-hosts.txt"
ag() { rc env -u PLAYWRIGHT_MCP_EXTENSION_TOKEN HARBOR_BROWSER_PRIVATE_HOSTS="$PH" HARBOR_ACCESS_PLAYWRIGHT_CLI="$STUB" CLAUDE_CODE_SESSION_ID=abc-123-def-456-789 TMPDIR="$T_TMP" sh "$AGENT" "$@"; }
