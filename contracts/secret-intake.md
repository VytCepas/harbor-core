# Secret intake — a credential reaches the store without an agent reading it

**The rule:** no credential value enters an agent's context: not a tool reply, not a transcript line, not argv, not a
file. An agent may cause a credential to be *stored*; it never *sees* one. Why: a value an agent reads is written to the
session transcript on disk and replayed into every later turn (constitution §3), and on 2026-11-21 a browser snapshot
printed a vendor password into one.

## The three ways a credential arrives

| It is… | The route | Who acts |
|---|---|---|
| **shown once on a vendor page** (a new API key, a client secret) | open the create dialog in the headless agent Chrome → `harbor chrome intake <ref of the page's Copy> add\|rotate <id> [the add flags]` (MCP: `intake`), which clicks the Copy, reads **that Chrome's own clipboard** (a ref that is the key's own field: its value) and pipes it into `harbor access … --value-stdin` → close the dialog. Never a plain click on Copy then `--value-clipboard`: on 2026-11-23 RTB House's Copy & Close ran headless, `--value-clipboard` read and emptied the operator's unrelated macOS clipboard, and the key, shown once, was lost; both click routes now refuse a Copy click with no window | the agent, end to end |
| **held by the operator** (password manager, an email, a file) | the operator copies it, then the agent runs `harbor access add\|rotate <id> --value-clipboard`; or the operator runs `! harbor access rotate <id>` and types at bin/secret's no-echo prompt | operator copies or types; never pastes into chat |
| **a token from an OAuth consent** (a refresh token from a vendor's authorization-code grant) | `harbor access add\|rotate <id> --value-oauth --oauth-authorize … --oauth-token … --oauth-client-id … --oauth-client-ref <app ref>` → open the printed authorize URL in harbor chrome → click the vendor's consent | the agent, end to end, once an operator has signed in to the vendor |
| **a sign-in password** | never stored by harbor: the operator signs in, `harbor chrome wait-signin` carries on (contracts/browser-routing.md) | operator |

Never: `snapshot`, `text`, `find` or `screenshot` of a page while it shows a key; `pbpaste` (or any clipboard read)
in an agent's shell; a value pasted into chat; a value as an argument.

## What holds it, and where

| Mechanism | Where | What it does |
|---|---|---|
| **The reply redactor** | `bin/access-redact.sh`, run on every reply of `bin/access-chrome-mcp.ts` and on all stdout and stderr of `bin/access-browser-agent.sh` (so the CLI and the python server too) | masks a provider token shape (the egress guard's `SECRET` list, read from `bin/admission-egress.sh`: one list, not a copy), the value of a field whose label names a secret (password, token, API key, one-time code…) and a secret URL parameter (`access_token=`, `client_secret=`…). Fails closed: no list, no text |
| **The image check** | the `shown-secret` probe of `contracts/browser-script.tsv`, run by both routes before `screenshot` and `pdf` | an image cannot be redacted, so a page that shows a credential is refused, with this route as the fix |
| **Browser intake** | `harbor chrome intake` (`bin/access-browser-agent.sh`; the MCP `intake` tool delegates to it), the `intake-read` row of `contracts/browser-script.tsv` | headless only (agent Chrome without a window, or the headless lane); the click takes the guard's ref and live-change checks; the CLI's `run-code` first empties that Chrome's clipboard (the `intake-clear` row; no answer or a clipboard still full refuses before the click), so a Copy that copies nothing stores nothing rather than the last intake's key, then runs the one fixed read row (clipboard-read granted to the page's origin, `navigator.clipboard.readText()`, the field's value), its answer piped through `jq` into `access.sh … --value-stdin`: never printed, argv or a file; a failed read is reported as one (its exit, or the read's error name), never as an empty Copy; and the guard's snapshot of the open dialog is deleted at once. Refused with a window or in the operator's Chrome, where the macOS clipboard is the route |
| **The copy-click net** | `_guard` of `bin/access-browser-agent.sh`, `guardSnapshot` of `bin/access-chrome-mcp.ts` | with no window, a click or dblclick on a Copy label (Copy … clipboard or … to clipboard, a bare Copy or Copy & Close, or Copy … key/token/secret; never Copy campaign or Paste from clipboard) is refused, naming `intake`; past a confirm too; so is Enter or Space on a focused Copy (`_submit_guard`, `submitGuard`) |
| **Clipboard intake** | `harbor access add\|rotate … --value-clipboard` (`bin/access.sh`, `bin/library-clipboard.sh`) | the clipboard piped into `--value-stdin` inside its own process: never shown, trimmed and checked as a piped value is, the clipboard emptied after whatever the outcome; `rotate` keeps the value only if the entry's check passes |
| **OAuth intake** | `harbor access add\|rotate … --value-oauth` (`bin/access-oauth.sh`) | a one-shot listener on 127.0.0.1 takes the redirect, checks `state`, keeps the code in a 0600 file and answers 303 to `/done`, so the page the agent sees carries no code; curl exchanges it with the client secret and the code in a config on stdin (never argv), and the token field is piped into `--value-stdin`. A failed exchange names the response's keys, never its values. The redactor masks a stray `code=` too |
| **The floor** | `bin/admission-egress.sh` rules `clipboard-read`, `browser-raw-cli`, `key-material-read`, `keychain-dump`, `provider-secret-egress` | an agent's own clipboard read, a hand-run Playwright CLI (outside the redactor), a key file or keychain read, a live token in a command — each blocked |
| **The store** | `bin/secret` | no verb prints a value; `secret run` / `withfile` hand it to one process |

## Known limits — said, not hidden

- **A secret with no known shape, shown as plain page text under no secret label, passes the redactor.** A client secret
  with no prefix is one. The route above never puts it in a reply (`harbor chrome intake`; never a plain Copy click then
  `--value-clipboard` headless, which lost a key on 2026-11-23); the redactor is the net for a mistake, not the reason
  the route is safe.
- **A snapshot of the open dialog is a file holding the key.** The CLI writes one for `snapshot` and for every non-raw
  verb (`.playwright-cli/page-*.yml`, `--filename=`), and the guard's own is on disk until intake deletes it. They live
  in the session workdir under `$TMPDIR` and go at detach; measured live by `tests/access/chrome/intake-live.sh`.
- **The live read is proved on one page.** `tests/access/chrome/intake-live.sh` (a local page, the headless lane, the
  pinned CLI) stored a Copy & Close key through `navigator.clipboard.readText()` on 2026-11-23. A vendor whose Copy
  needs more than the CLI's trusted click, or reads `document.hasFocus()`, is not covered by that run.
- **A script file that runs the Playwright CLI** is not seen by `browser-raw-cli`, which judges the command line. The
  anonymous routes (`bin/access-browser-cdp.mjs`, `bin/access-browser-flow.sh`) are not filtered: they run a throwaway,
  signed-out profile, so no vendor session can show one of our credentials there.
- **An agent cannot load a Meta token from the clipboard** (`pbpaste | meta set-token` is a clipboard read); the
  operator runs that line as `! …`.
- **Two shape lists exist:** the egress guard's `SECRET` (runtime, read by the redactor) and
  `contracts/credential-patterns.tsv` (`bin/lint-secrets.sh`, `harbor access check`). They overlap and drift
  (Meta: `EAA{100,}` against `EAA{40,}`).
- **The guard's JWT and `mongodb+srv` shapes never match** (`\\.` and `\\+` in a single-quoted ERE are a literal
  backslash). Fixing it widens what the floor blocks in every session, so it is its own change.

## Proof

`tests/access/chrome/redact.test.sh` (both routes, the image check, fail-closed, one list; a mutant per protection),
`tests/access/cli/clipboard.test.sh` (stored, unseen, emptied; a mutant), `tests/access/browser/intake.test.sh` (stored,
unseen in output, call log and workdir, the field fallback, refused with a window and in the operator's Chrome; mutants
that print the value, skip the pipe or keep the guard snapshot), the copy-click net in `tests/access/browser/chrome.test.sh`
and `tests/access/chrome/live-change.test.sh` (both routes; a mutant each), `tests/access/chrome/intake-live.sh` (live, not a suite), `tests/access/cli/oauth.test.sh` (stored, unseen,
state checked, both client-auth styles, the vendor's refusal; a mutant without the state check), `tests/guards/egress.jsonl` rows `clip-*`
and `pw-*` (each block row red with its rule removed).
