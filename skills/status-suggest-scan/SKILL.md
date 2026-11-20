---
name: status-suggest-scan
description: "Runs the repeated-work scan and says in plain words what a person keeps doing by hand. USE WHEN a person asks what they repeat or what Harbor could take over. NOT FOR building what it finds."
---

# status-suggest-scan — what do I keep doing by hand

**Done looks like:** the scan ran once, and the reply is at most three plain-word findings, or the sentence "no repeated job found", or the reason the scan could not run. Nothing was built, installed or stopped unless the person then asked for it.

The scan is `bin/status-suggest-scan.sh` (harbor#1485, decision 28 on #1485). It reads no model and no mod: it needs only the sessions already on this machine and writes nothing. A person with the Harbor pane loaded has a button for the same scan; this skill is the way when no mod is loaded, as on a company laptop.

## Run it

The script sits in one of these folders, and `deploy-install-lib.sh` and `library-log.sh` sit beside it. Take the first that has it:

```sh
d=""; for c in "${HARBOR_SCOPE_BIN:-}" "${HARBOR_MEMBER_ROOT:+$HARBOR_MEMBER_ROOT/bin}" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin" "${PORT_ROOT:-$HOME/port}/harbor/bin"; do
  [ -n "$c" ] && [ -f "$c/status-suggest-scan.sh" ] && { d="$c"; break; }
done
if [ -n "$d" ]; then sh "$d/status-suggest-scan.sh" --json --live; else echo "status-suggest-scan.sh is not installed here" >&2; false; fi
```

It can take up to a minute on a large history. Run it once; do not repeat it to see if the answer moves.

## Read the answer

One JSON object: `{"schema":1,"days":14,"sessions":N,"candidates":[{"id","kind","shape","sessions","count"}]}`.

- **No output and exit 1:** the scan could not read the history. Say so. That is not "nothing repeated".
- **`candidates` empty:** say "no repeated job found in the last `days` days (`sessions` sessions)".
- **A candidate:** `shape` is the steps in order, in fixed words ("connector report, then write document"); `sessions` is in how many separate sessions it appeared. Say what it is in a sentence, then the kind in plain words:

| `kind` | Say |
|---|---|
| `skill` | a saved recipe the agent follows when asked |
| `hook` | something that runs by itself after a step, such as a check after an edit |
| `job` | a task that could run on a schedule |
| `mod` | something to keep in view, not a task to run: only lookups |

Use only the fields above. Do not guess at what a step touched: the scan keeps no names, paths or text, so there is nothing to quote.

## After

To stop one from being offered again, `sh <that folder>/status-suggest.sh stop <id> --origin agent`. To build one, the person asks, and the work goes through `default-way-route`'s homes. Offer; do not start.
