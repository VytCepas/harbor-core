# `harbor chrome` playbook — rules, recovery, dead ends, recipes

The working half of row 4. `SKILL.md` says when to reach for `harbor chrome`; the
contract (`contracts/browser-routing.md`, row 4) says what each verb may do. This page
is what was learned driving the operator's Chrome: how to keep control of a tab, what
each failure means, what has already been tried and failed, and step-by-step tasks.

## Rules

1. **One window, one tab, closed after.** `attach` opens a window on `about:blank`
   and the extension connects to that tab; it is the session's tab. Work in it with
   `goto`. Never leave a tab or window behind: `detach` closes exactly the tabs this
   session opened (attach's, `tab-new`'s) and nothing of the operator's.
2. **Parallel work is a lane, not a tab.** Two agents in one session each set their own
   `HARBOR_BROWSER_LANE` and `attach`: a window each. Two tabs in one window cannot both
   show, so one goes `hidden` and its clicks time out. `tab-new` is for a second page
   in the same lane that only gets read.
3. **Never take the operator's focus.** `attach` hands focus straight back to the app
   they were in; `front` shows the tab without raising its window or activating Chrome.
   A covered window still paints; a **minimised** one does not, so a harbor window is
   covered, never minimised.
4. **The operator is in the same browser.** A tab that switched, a banner that went,
   an input that emptied is, most of the time, the operator. Before blaming a bug or
   a session, ask whether the operator did it, and prefer evidence the operator
   cannot produce: the relay log, Chrome's own error, a repeat.
5. **`state` before and after anything that matters.** It prints visibility, focus,
   host, `blank` and `online`. `hidden` means nothing will paint; `blank: true` means the
   tab is gone; `online: false` stalls react-query apps on a blank page.
6. **Every input verb is checked.** A lost tab or a hidden tab is a refusal, never a
   silent success. Read the refusal's `fix:` line; it names the next command.
7. **Writes are the operator's to name.** Saving a data source, a setting, an
   invite: ask in chat first, unless the operator named that write this turn.
8. **One field, one call when timing matters.** `fill <ref> <text> --submit` sends
   Enter in the same call; a second call comes too late after a detach.

## Signing in — the operator's click, never harbor's

Harbor never fills a password and never picks an entry in a password manager (LastPass,
NordPass, any of them). That is signing in with credentials, and it stays the operator's
act. It is also out of reach: a password manager's dropdown is that extension's own frame,
which Chrome lets no other extension drive, and its arrival drops the tab.

1. A `goto`, `tab-new`, `reload` or `click` that lands on a sign-in page is refused:
   `signed out: <app> sent this session to a sign-in page … sign in as <account> (<card>)`.
   The account is the `primary` line of the access register's route card naming the
   app's host or its parent domain. No card means no account is named; never guess one.
2. Tell the operator in one line: the app, and the account to pick in their password
   manager.
3. `harbor chrome wait-signin` (default 300 s, at most 900). It watches the tab through
   Chrome itself, so it still works while the password manager's frame has dropped the
   connection. Signed in, it carries on in the same tab, or, if the connection dropped,
   closes that tab, attaches afresh and opens the page the sign-in reached.
4. **Then check the account inside the app** before any work: the business, ad account or
   advertiser switcher shows which one is active. Switching it is a navigation click and
   is harbor's to do. The route card's `reaches:` line names the right one.

An account picker (Google's chooser, LinkedIn's) is a sign-in page too: the operator picks.

**The operator signs in inside harbor's tab, not their own.** Some apps keep the session per
tab: one data-pipeline app sent harbor's fresh tab to `/login` minutes after the operator
signed in elsewhere (2026-10-17). When `goto` reports `the tab was lost on load: another
extension put a frame in the page`, the password manager injected on the sign-in form before
the operator acted. The fix is the operator's, once per host, and then the loop works:

1. Operator: `chrome://extensions` → the password manager → **Details** → **Site access:
   On click** (or on-click for that host). The operator then fills from the toolbar icon.
2. `harbor chrome attach`, `goto <app>/login`: the `signed out` refusal now keeps the tab.
3. `harbor chrome wait-signin` in the background; the operator fills from the icon in harbor's
   window. Verified end to end 2026-10-17 (the app's route card has the host): signed in, the
   session drove the tab.

**Any page with a password field loses the tab, not only sign-in.** A connector's settings form
(an `API Token` field) dropped harbor's tab on load even with On click set (2026-10-17). Inputs
sent after that land on the fallback blank tab and report success, so `harbor chrome tabs`
after every navigation to a settings form. Such an edit goes to the operator, with the exact
field and value.

## Recovery — symptom, cause, command

| the verb says | what happened | do |
|---|---|---|
| `the tab is hidden … timed out` | Chrome is showing another tab in that window, or the window is minimised | `harbor chrome front`, then the verb again |
| `front: … still hidden` | the window is minimised again or on another Space | the operator brings it up; never minimise a harbor window |
| `signed out: … sign in as …` | the app sent the tab to sign-in | the operator signs in as named, then `harbor chrome wait-signin` |
| `the tab was lost on load: another extension put a frame in the page` (from `goto`) | a sign-in page whose password field a password manager fills: Outbrain, Eskimi, every pass | the operator signs in to that host in Chrome, then `attach` and `goto` again |
| `the tab was lost: another extension put a frame in the page` (after an input verb) | another extension (usually a password manager's autofill, on a password field the page just revealed) put its frame in the page; Chrome lets no extension debug another's, and the re-attach fails | the operator sets that extension's **Site access** to *On click* for the host (`chrome://extensions` → Details). Then `harbor chrome goto <url>` |
| `the tab was lost: Chrome detached …` (no extension named) | a frame on an unknown scheme, or the page navigated to sign-in | `harbor chrome goto <url>`; signed out → the operator signs in first |
| `snapshot` is two lines (`status`, `alert`) | not proof of anything: a lost tab gives it, and so does an app fully rendered whose UI exposes no accessibility tree (2026-10-17) | `screenshot` decides. Lost: `harbor chrome tabs`, `state`. Rendered: work from the screenshot with `mousemove <x> <y>`, `mousedown`, `mouseup`, `type` |
| `no Chrome is connected … All controlled tabs detached` | the relay closed with its last tab | `harbor chrome attach` |
| every verb: `does not handle the modal state` / `[File chooser]` | a click opened a file chooser and it is still pending | `harbor chrome upload <file>`; there is no cancel, so otherwise `detach` then `attach` |
| `upload refused by Chrome: … no access to file URLs` | Chrome lets an extension fill a file input only with *Allow access to file URLs* | the operator's switch, on the Playwright Extension's Details page |
| `front` says `0 Chrome tabs show this session's URL` | the page rewrote its URL since the CLI looked | `front` marks the tab with `#harbor-<session>` and finds the mark; if it still fails, `harbor chrome tabs` |

To see the whole browser: `harbor chrome tabs` (`=` marks this session's tab; anyone
else's tab shows its host only, since a path can be a message thread).
To see why the relay dropped: `harbor chrome status` (its `relay` line), then the
`.err` beside it, where `pw:mcp:error` lines carry Chrome's own reason.

## Dead ends — measured, do not retry

| tried | result | date |
|---|---|---|
| a Commerce Manager feed URL typed into its field: whole, char by char, after `Home`, without the scheme | with the scheme the tab is lost 0.3–1.5 s later; without it Meta refuses the value and Next stays disabled | 2026-10-14 |
| the same URL into a plain search box | no loss: the trigger is the password field the feed form reveals, not the URL | 2026-10-14 |
| `fill --submit` on the feed URL | Enter goes out 36 ms after the text; the tab is still lost 1.5 s later, and the wizard is one URL, so whether it advanced is unreadable | 2026-10-14 |
| Claude in Chrome on `business.facebook.com` | refused by the router hook, by design: row 4 covers it | 2026-10-14 |
| `upload` with the extension lacking file-URL access | Chrome: `DOM.setFileInputFiles … Not allowed` | 2026-10-14 |
| `upload` with no file, to cancel a chooser | the CLI requires a file | 2026-10-14 |
| moving the controlled tab to another window (AppleScript `move`) | the extension detaches; open the window before `attach` instead | 2026-10-14 |
| attaching to a new window's New Tab page | it is another extension's page when one replaces New Tab; the first `goto` lost the tab 3 of 3. `attach` opens `about:blank` now | 2026-10-14 |
| many lanes attaching at once | every lane's tab landed in one window and all but one went `hidden`; attaches now take turns on a lock | 2026-10-14 |
| `timeout` around a verb | not on this Mac (exit 127); a hung verb is waited out or the next `goto` recovers it | 2026-10-14 |
| blaming the CLI version, a covered window, or the extension's host access | ruled out: 0.1.22 is the newest; a covered window stays `visible`; YouTube and Facebook help pages, full of cross-site frames, keep the tab | 2026-10-14 |
| harbor driving a password manager to sign in | refused by rule: signing in with credentials is the operator's; and Chrome lets no extension drive another's frame | 2026-10-14 |
| a catalog write through the Graph API on `fb-system-user-token` | not attempted: its scopes carry no `catalog_management` | 2026-10-14 |
| reading the Chrome profile (`Secure Preferences`, `Extensions/`) from a session | macOS refuses (`Operation not permitted`); the extension list is not readable from here | 2026-10-14 |

## Recipes

### Meta Commerce Manager — add a scheduled data feed (Update mode)

Pre-flight, once: the operator's password manager does not inject on
`business.facebook.com` (its Site access set to *On click*), or this recipe loses the
tab at step 4.

1. `harbor chrome attach`, then
   `harbor chrome goto 'https://business.facebook.com/commerce/catalogs/<catalog_id>/feeds/new/?catalogItemType=EntProductItem&business_id=<business_id>'`.
2. `harbor chrome state`: `visible`, host `business.facebook.com`. Hidden → `harbor chrome front`.
3. `harbor chrome snapshot`. The form sits in an iframe, so refs read `f<n>e<m>`. The
   field is `textbox "Enter a URL from your server, hosting website or a Google spreadsheet"`.
4. `harbor chrome fill <ref> '<https feed url>'`, then a new snapshot; `Next` must be
   enabled.
5. Next. On the settings step: name, currency, schedule, and **Update, never
   Replace**. Replace deletes every item not in the file, including another
   source's. If only Replace is offered, stop and tell the operator.
6. Save is a write: the operator names it, or ask.
7. Verify on the data source page, not the wizard's confirmation: the item count
   arrived, and every other data source's count is unchanged.
8. `harbor chrome detach`: the window closes.

An upload instead of a URL (`Upload from your computer` → `choose file on your
device` → `harbor chrome upload <abs path>`) needs the extension's file-URL access,
and gives a one-off upload with no schedule.
