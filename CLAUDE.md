# harbor — Claude Code entry point

@AGENTS.md

That bare line is an IMPORT and has to stay bare. Claude Code expands `@path`
and nothing else, so a markdown link to the same file loads nothing. Backticks
or a code fence disable the import the same way.

`AGENTS.md` is the source of truth. Claude-only details go in its
`## Claude Code specifics` section, not here.

## Compact Instructions

When compacting this conversation, preserve:
- The GitHub issue number being worked on (e.g. `#954`)
- Files modified in this session (list by path)
- Test results: pass/fail count and any failing test names
- Unresolved errors or lint failures
- Any decisions made that are not yet committed to `docs/` or `CONTRACTS/`
