#!/usr/bin/env sh
# harbor chrome and the route cards (harbor#1617): attach --blank, the sign-in account from the card that lists the host,
# `session: show-only`, `verify <card>`, and signin over several cards with the cookie report. The shell agent against a stub
# CLI and a fixture register; every host is invented (example.com), so no client or vendor name is here.
. "$(dirname "$0")/../../lib/core.sh"; t_init
AGENT="$T_ROOT/bin/access-browser-agent.sh"; unset HARBOR_ACCESS_CHROME
HARBOR_ACCESS_BROWSER_SETTLE=0; export HARBOR_ACCESS_BROWSER_SETTLE
. "$(dirname "$0")/../../cli/browser/agent-stub.sh"
printf 'example.com\n' > "$PH"
AP="$T_TMP/agentprof"; W="$T_TMP/harbor-browser/claude-abc123def456"
aag() { HARBOR_ACCESS_AGENT_PROFILE="$AP"; export HARBOR_ACCESS_AGENT_PROFILE; ag "$@"; }
mkdir -p "$AP/Default"; : > "$AP/Default/Cookies"
# a card: identity, the host it lists, a primary account, and the check lines the cases below vary
card() { # <name> <ui-hosts> <account> <session line or ''> <check url> <role url>
  { printf '    identity: fixture via a test\n    ui-hosts: %s\n    account:  %s | primary | Admin | the app\n    via:      cli > browser\n' "$2" "$3"
    [ -z "$4" ] || printf '    session:  %s\n' "$4"
    printf '    use:      the first move\n    check:    harbor chrome goto %s\n    expect:   `Example Admin` and `Reports`\n' "$5"
    [ -z "$6" ] || printf '    role-check: harbor chrome goto %s\n    role-expect: `Owner`\n' "$6"; } > "$ACC/$1.md"
}

t_section "attach --blank is the profile-less Chrome; --headless is its old name and says so (harbor#1617)"
: > "$CALLS"
t_eq "attach --blank passes" "exit 0" "$(HARBOR_ACCESS_BROWSER_LANE=web aag attach --blank)"
t_eq "...starting a Chrome with no profile" 1 "$(called 'open --browser=chrome --idle-timeout=')"
t_eq "...marked as the blank lane" yes "$([ -e "$W-web/.headless" ] && echo yes)"
t_hasnt "...with no deprecation line" "$(out)" "renamed"
HARBOR_ACCESS_BROWSER_LANE=web aag detach >/dev/null
t_eq "attach --headless still works" "exit 0" "$(HARBOR_ACCESS_BROWSER_LANE=web aag attach --headless)"
t_has "...and says it is renamed" "$(out)" "attach --headless is renamed"
t_has "...pointing to plain attach for the signed-in profile" "$(out)" "plain 'attach' is the signed-in agent profile"
t_has "...and --blank for a throwaway" "$(out)" "'--blank' is a throwaway Chrome with no profile, never signed in"
t_eq "...still a profile-less Chrome" yes "$([ -e "$W-web/.headless" ] && echo yes)"
HARBOR_ACCESS_BROWSER_LANE=web aag detach >/dev/null
t_eq "an unknown attach flag is refused" "exit 1" "$(aag attach --bogus)"
t_has "...naming --blank, not --headless" "$(out)" "[--blank] (no profile, never signed in)"
t_hasnt "...and never --headless" "$(out)" "[--headless]"
t_eq "wait-signin in a blank session is refused" "exit 1" "$(HARBOR_ACCESS_BROWSER_LANE=web; export HARBOR_ACCESS_BROWSER_LANE; mkdir -p "$W-web"; : > "$W-web/.headless"; ag wait-signin; rm -f "$W-web/.headless")"
t_has "...saying it is a --blank browser" "$(out)" "a --blank browser, never signed in"
t_hasnt "...with no 'headless' in the text" "$(out)" "headless"

t_section "the sign-in account is the card that lists the host, not a grep of card prose (harbor#1617)"
rm -f "$ACC"/*.md
# aaa sorts first and names the host in its prose with another account; bbb lists the host in ui-hosts
printf '    identity: prose via a test\n    ui-hosts: other.example.com\n    account:  wrong@example.com | primary | Admin | also uses app.example.com in the browser\n' > "$ACC/aaa.md"
card bbb app.example.com right@example.com '' https://app.example.com/home ''
LOGIN='https://login.example.com/'
t_eq "a goto that lands on sign-in is refused" "exit 1" "$(STUB_PAGE_URL="$LOGIN"; export STUB_PAGE_URL; ag goto https://app.example.com/home)"
t_has "naming the account of the card whose ui-hosts lists the host" "$(out)" "sign in as right@example.com (bbb.md)"
t_hasnt "...never the card that only mentions it" "$(out)" "wrong@example.com"
t_eq "a subdomain of a listed host takes that card too" "exit 1" "$(STUB_PAGE_URL="$LOGIN"; export STUB_PAGE_URL; ag goto https://eu.app.example.com/x)"
t_has "...its account" "$(out)" "sign in as right@example.com (bbb.md)"
rm -f "$ACC/bbb.md"
t_eq "with no card listing the host, the prose reading stays" "exit 1" "$(STUB_PAGE_URL="$LOGIN"; export STUB_PAGE_URL; ag goto https://app.example.com/home)"
t_has "...naming the card that mentions it" "$(out)" "sign in as wrong@example.com (aaa.md)"
printf '    identity: a card with no primary\n    ui-hosts: app.example.com\n    account:  spare@example.com | fallback | Admin | x\n' > "$ACC/ccc.md"
t_eq "a card that lists the host but holds no primary names no account" "exit 1" "$(STUB_PAGE_URL="$LOGIN"; export STUB_PAGE_URL; ag goto https://app.example.com/home)"
t_hasnt "...and does not fall back to a prose match" "$(out)" "wrong@example.com"
rm -f "$ACC"/*.md

t_section "session: show-only refuses a headless profile copy and names the window that fixes it (harbor#1617)"
card app app.example.com owner@example.com 'show-only - the login is a session cookie' https://app.example.com/home ''
card plain plain.example.com owner@example.com 'persistent' https://plain.example.com/home ''
card bare bare.example.com owner@example.com '' https://bare.example.com/home ''
: > "$CALLS"
t_eq "attach passes (the headless copy of the agent profile)" "exit 0" "$(aag attach)"
t_eq "goto a show-only host is refused" "exit 1" "$(aag goto https://app.example.com/home)"
t_has "...saying the login does not survive the copy" "$(out)" "app.md says the login does not survive a headless profile copy (session: show-only - the login is a session cookie)"
t_has "...with the one-line fix" "$(out)" "fix: harbor chrome attach --show --ui='<why>'"
t_eq "tab-new to it is refused too" "exit 1" "$(aag tab-new https://app.example.com/home)"
t_eq "neither reached the CLI" 0 "$(called 'app.example.com')"
t_eq "session: persistent opens" "exit 0" "$(aag goto https://plain.example.com/home)"
t_eq "a card with no session line opens" "exit 0" "$(aag goto https://bare.example.com/home)"
aag detach >/dev/null
t_eq "attach --show passes" "exit 0" "$(aag attach --show)"
t_eq "...and in that window the show-only host opens" "exit 0" "$(aag goto https://app.example.com/home)"
t_eq "...with no rule left for tab-new" "exit 0" "$(aag tab-new https://app.example.com/home)"
aag detach >/dev/null
t_eq "after detach the marker is gone (a plain attach is refused again)" "exit 1" "$(aag attach >/dev/null; aag goto https://app.example.com/home)"
aag detach >/dev/null
t_eq "a --blank session has no profile to lose: not refused" "exit 0" "$(HARBOR_ACCESS_BROWSER_LANE=web; export HARBOR_ACCESS_BROWSER_LANE; aag attach --blank >/dev/null; aag goto https://app.example.com/home)"
HARBOR_ACCESS_BROWSER_LANE=web aag detach >/dev/null

t_section "verify <card>: the card's browser checks, read-only (harbor#1617)"
rm -f "$ACC"/*.md
card ok app.example.com owner@example.com '' https://app.example.com/home https://app.example.com/roles
card nowall app.example.com owner@example.com '' https://app.example.com/home ''
: > "$CALLS"; aag attach >/dev/null
STUB_TEXT='Welcome Example Admin. Reports Owner'; export STUB_TEXT
t_eq "a card whose literals are all on the pages passes" "exit 0" "$(aag verify ok)"
t_has "...check: pass" "$(out)" "check: pass"
t_has "...role-check: pass" "$(out)" "role-check: pass"
t_eq "it went to each url" 1 "$(called 'goto https://app.example.com/roles')"
STUB_TEXT='Welcome Example Admin. Reports'
t_eq "a literal missing from the page fails" "exit 1" "$(aag verify ok)"
t_has "...naming it" "$(out)" "role-check: FAIL missing Owner"
t_has "...while the check that matched passes" "$(out)" "check: pass"
STUB_TEXT='Welcome'
t_eq "every missing literal is its own line" 2 "$(aag verify nowall >/dev/null; grep -c 'FAIL missing' "$T_TMP/out")"
STUB_TEXT=''; STUB_SNAPSHOT='- heading "Example Admin" - link "Reports" - cell "Owner"'; export STUB_SNAPSHOT
_sn0="$(called ' snapshot')"
t_eq "an empty page text falls back to the accessibility snapshot" "exit 0" "$(aag verify ok)"
t_eq "...which it read" "$((_sn0 + 2))" "$(called ' snapshot')"
unset STUB_SNAPSHOT; STUB_TEXT='Example Admin Reports Owner'
t_eq "a page that sends the tab to sign-in is login-wall" "exit 1" "$(STUB_PAGE_URL="$LOGIN"; export STUB_PAGE_URL; aag verify ok)"
t_has "...check: login-wall" "$(out)" "check: login-wall"
t_has "...role-check: login-wall" "$(out)" "role-check: login-wall"
t_hasnt "...and not a FAIL" "$(out)" "check: FAIL"
card offlist other.invalid owner@example.com '' https://not-allowed.invalid/home ''
t_eq "a url off the host allow-list fails, the allow-list deciding" "exit 1" "$(aag verify offlist)"
t_has "...as the host refusal" "$(out)" "check: FAIL hand-off: host refused"
printf '    identity: x\n    check:    fixture-cli accounts list\n    expect:   `ok`\n    role-check: harbor chrome goto https://app.example.com/roles\n    role-expect: `Owner`\n' > "$ACC/mixed.md"
t_eq "a check that is not a goto line is skipped, the other still runs" "exit 0" "$(aag verify mixed)"
t_has "...say so" "$(out)" "check: skip (not a \`harbor chrome goto <https url>\` line)"
printf '    identity: x\n    check:    fixture-cli accounts list\n    expect:   `ok`\n' > "$ACC/nogoto.md"
t_eq "a card with nothing to navigate to is refused, not passed" "exit 1" "$(aag verify nogoto)"
t_eq "an unknown card is refused" "exit 1" "$(aag verify nope)"
t_eq "a path is not a card name" "exit 1" "$(aag verify ../ok)"
t_eq "verify takes exactly one card" "exit 1" "$(aag verify ok nowall)"
t_eq "it never clicks, fills, types or presses" 0 "$(grep -c ' click \| fill \| type \| press \| select \| check e\| upload ' "$CALLS")"
card shown shown.example.com owner@example.com 'show-only - session cookie' https://shown.example.com/home ''
t_eq "a show-only card on a headless copy fails with the window fix" "exit 1" "$(aag verify shown)"
t_has "...check: FAIL" "$(out)" "check: FAIL shown.example.com: shown.md says the login does not survive"
t_has "...and the fix" "$(out)" "fix: harbor chrome attach --show --ui='<why>'"
t_eq "an agent's verify needs no --ui of its own: api first reads the verify reason" "exit 0" "$(ACCESS_DIR="$ACC"; HARBOR_ACCESS_ENFORCE=1; export ACCESS_DIR HARBOR_ACCESS_ENFORCE; aag verify ok)"
t_eq "...while the same goto without a reason is held" "exit 1" "$(ACCESS_DIR="$ACC"; HARBOR_ACCESS_ENFORCE=1; export ACCESS_DIR HARBOR_ACCESS_ENFORCE; aag goto https://app.example.com/home)"
t_has "...by api first" "$(out)" "api first"
t_eq "with no Chrome connected verify says so" "exit 1" "$(STUB_GONE=1; export STUB_GONE; aag verify ok)"
t_has "...naming the attach" "$(out)" "harbor chrome attach"
t_has "...from the CLI's stderr answer, not an empty reason" "$(out)" "no Chrome is connected"
STUB_TEXT='Welcome Example Admin. Reports Owner'
t_eq "a page that renders after load is read again until its literals show" "exit 0" "$(: > "$T_TMP/late"; STUB_TEXT_LATE="$T_TMP/late"; export STUB_TEXT_LATE; aag verify ok)"
t_has "...and passes" "$(out)" "role-check: pass"
t_eq "...within its tries: one try sees only the loading page" "exit 1" "$(: > "$T_TMP/late"; STUB_TEXT_LATE="$T_TMP/late"; HARBOR_ACCESS_VERIFY_TRIES=1; export STUB_TEXT_LATE HARBOR_ACCESS_VERIFY_TRIES; aag verify ok)"
t_has "...naming what was missing" "$(out)" "check: FAIL missing Example Admin"
rm -f "$T_TMP/late"
aag detach >/dev/null; unset STUB_TEXT

t_section "signin over several cards, and the cookie names each sign-in left (harbor#1617)"
rm -f "$ACC"/*.md; : > "$CALLS"
card one one.example.com owner@example.com '' https://one.example.com/home ''
card two two.example.com owner@example.com '' https://two.example.com/home ''
printf '    identity: x\n    check:    fixture-cli accounts list\n    expect:   `ok`\n' > "$ACC/nourl.md"
# the profile's cookie database: names and lifetimes; a value column that must never be printed
NOW="$(date +%s)"; CH=$(( (NOW + 11644473600) * 1000000 )); OLD=13300000000000000
DB="$AP/Default/Cookies"; rm -f "$DB"
sqlite3 "$DB" 'create table cookies (creation_utc integer, host_key text, name text, value text, encrypted_value blob, is_persistent integer, last_update_utc integer)'
sqlite3 "$DB" "insert into cookies values ($OLD, '.two.example.com', 'older', 'secret-old', x'00', 1, $OLD), ($OLD, 'other.example.org', 'foreign', 'secret-foreign', x'00', 1, $OLD)"
t_eq "--cards takes card names only" "exit 1" "$(aag signin --cards 'one,../two')"
t_eq "an unknown card is refused" "exit 1" "$(aag signin --cards one,missing)"
t_eq "a card with no goto check has no url to open" "exit 1" "$(aag signin --cards nourl)"
t_eq "--next with no walk is refused" "exit 1" "$(aag signin --next)"
t_eq "--cards passes" "exit 0" "$(aag signin --cards one,two)"
t_eq "...opening the first card's url" 1 "$(called "-s=harbor-agent-signin open --browser=chrome --profile=$AP --headed https://one.example.com/home")"
t_eq "...and not the second's yet" 0 "$(called 'https://two.example.com/home')"
t_has "...saying where it is and what comes next" "$(out)" 'signin 1/2: a window of the AGENT Chrome is open on one.example.com: sign in as owner@example.com (one.md)'
sqlite3 "$DB" "insert into cookies values ($((CH + 60000000)), '.one.example.com', 'sid', 'secret-sid-value', x'5345435245', 1, $((CH + 60000000))), ($((CH + 60000000)), 'one.example.com', 'tmp', 'secret-tmp-value', x'00', 0, $((CH + 60000000)))"
t_eq "--next passes" "exit 0" "$(aag signin --next)"
t_eq "...closed that window" 1 "$(called '-s=harbor-agent-signin close')"
t_eq "...and opened the next card's" 1 "$(called "--headed https://two.example.com/home")"
t_has "...naming the host just signed in" "$(out)" "signin 1/2 one (one.example.com)"
t_has "...a persistent cookie by name" "$(out)" "sid  persistent"
t_has "...a session-only one by name" "$(out)" "tmp  session-only"
t_hasnt "...never a cookie value" "$(out)" "secret"
t_hasnt "...never another host's cookie" "$(out)" "foreign"
t_hasnt "...and, with cookies written, no 'no new cookies'" "$(out)" "no new cookies"
t_has "...pointing at the next step" "$(out)" "signin 2/2"
t_eq "--done after the last card passes" "exit 0" "$(aag signin --done)"
t_has "...reporting the host it signed in" "$(out)" "signin 2/2 two (two.example.com)"
t_has "...with the cookie that was already there" "$(out)" "older  persistent"
t_has "...and saying nothing new was written since the window opened" "$(out)" "no new cookies for two.example.com — was the sign-in done in this window?"
t_hasnt "...never a value" "$(out)" "secret"
t_eq "--next after the walk is refused" "exit 1" "$(aag signin --next)"
aag signin --cards one,two >/dev/null
aag signin --next >/dev/null
t_eq "--next on the last card ends the walk" "exit 0" "$(aag signin --next)"
t_has "...saying it was the last" "$(out)" "that was the last card"
t_eq "a single url signin is unchanged: it opens that url" "exit 0" "$(aag signin https://one.example.com/home)"
t_eq "...and --done closes it with no cookie report" "exit 0" "$(aag signin --done)"
t_hasnt "...no report" "$(out)" "cookies for"
t_eq "signin to a host off the allow-list stays refused" "exit 1" "$(aag signin https://evil.example/)"
ln -s nowhere "$AP/SingletonLock"
t_eq "an open sign-in window still holds the profile: --cards refuses" "exit 1" "$(aag signin --cards one)"
rm -f "$AP/SingletonLock"

t_done
