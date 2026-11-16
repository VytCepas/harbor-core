---
kind: decision-record
status: accepted
alias: D-94
date: 2026-11-15
supersedes: -
superseded_by: -
source: harbor#1541
owner: harbor#1541
---

# A change to a live system asks the operator on the API path and in the browser alike

Settles which calls ask the operator in Claude Code's dialog, so the same act is not free on one path and refused or
silent on the other.

## Context

- Measured 2026-11-15 (harbor#1541): `harbor chrome` asked only for clicks labelled delete, remove, pause, publish, pay and
  similar; Save, Apply and Turn on, `press Enter` and `fill --submit` committed with no dialog. On the API side the
  measurement pack's apply and write flags matched no rule, so the auto-mode classifier refused them and the session
  handed the operator a command instead.
- Operator decision, 2026-11-15, chosen over "ask only on risky changes" and "API asks, browser as now".

## Decision

1. **Reads and drafts are free on both paths.** A read verb or a dry run is an `allow` rule; a browser read verb is allowed.
2. **A change that reaches a live system asks, on both paths.** In the browser: a click, Enter or Space on a control whose
   label carries a word of `contracts/live-change-words.txt`, run only through `confirm_click` (a `permissions.ask` rule).
   On the API: the apply or write flag of a CLI, an `ask` row in that CLI's verb register.
3. **One list per path, each in one place.** The browser's words are `contracts/live-change-words.txt`, read by both
   browser routes. The API's are the verb registers: core's `contracts/verbs/`, and a pack's own `verbs/` for the
   commands it ships (contracts/pack.md).
4. **Where a CLI cannot tell an edit from a delete, its apply asks.** Finer classes need the CLI to classify its own
   request; until it does, the stricter class holds.

## Consequences

- More dialogs for routine commits (a tag manager's workspace Save). Reversible by editing the word list.
- The browser cannot see an Enter handler that is script on a field outside any form, nor focus inside an iframe: that
  residual is named in contracts/browser-routing.md, not hidden.
- Hand-added allow rules for pack commands become redundant once the pack's registers land; removing them from
  `settings.json` is the operator's.
