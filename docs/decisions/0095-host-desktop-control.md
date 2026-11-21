---
kind: decision-record
status: proposed
alias: D-95
date: 2026-11-21
supersedes: -
superseded_by: -
source: harbor#1440
owner: harbor#1440
---

# Mac apps get general controllers on the host, through one helper with its own identity

Amends harbor#1440's routing order and DE-40's "do instead": a Mac app with no broker no longer waits for a guest.

## Context

- harbor#1440 (2026-11-01) ruled screen control of the operator's desktop out and sent apps with no broker to a macOS
  guest (#1444, not built). DE-40 rejected `allowAppleEvents` in the sandbox.
- Operator decision, 2026-11-21: build general, app-agnostic controllers on the host (API and CLI brokers, the browser,
  Apple Events, Shortcuts, the Accessibility API), with no screen takeover; chosen over the guest-only route after
  the guest's cost on this box was measured (5.4 GiB free memory, 43 GiB free disk).

## Decision

1. **One helper, its own identity.** All host app control runs in one signed helper app launched through
   LaunchServices, so macOS attributes Accessibility, Screen Recording and Automation to it and never to the terminal.
   The Claude sandbox stays as it is: `allowAppleEvents` stays off (DE-40 holds for the sandbox).
2. **General verbs, apps as data.** The verbs are app-agnostic (list apps, read a window's element tree, press, set a
   value, capture a window, run a script, run a Shortcut). Which apps they may touch is an allow-list file, not code.
3. **Background only by default.** A verb that would raise an app, move the pointer or take focus is refused unless
   the call names the foreground explicitly.
4. **Changes ask.** A press, menu item or value set on an element whose label carries a word of
   `contracts/live-change-words.txt`, Enter or Space, a script and a Shortcut run go through the operator's dialog, as
   D-94 does for the browser; a typed line break is refused. A plain field's value is set without a dialog, as
   harbor chrome's `fill` is.
5. **The guest stays** for apps that must not see host state (#1444); this record removes it as the only route.

## Consequences

- One Accessibility grant reaches every app the helper can see; the allow-list and the ask rule are the boundary the
  operator relies on, so both are tested with mutants.
- Rebuilding an ad-hoc signed helper changes its code hash, and macOS may ask for the grants again.
