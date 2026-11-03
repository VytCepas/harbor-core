#!/usr/bin/env sh
# 96-agent-brief (harbor#953): inform when an Agent call's brief lacks a done/outcome statement,
# constraints or an output location, or sets no model. It prints a note, never a decision:
# the HARBOR-DECISION sentinel appears nowhere below, so this cannot block a call.
#
# THE WORD LISTS ARE GENEROUS ON PURPOSE. A false positive on a good brief is a defect (the
# constitution's No.2.11) and trains the operator to skip the note, so each section passes on any
# of several ordinary phrasings. Falsifier: a complete brief draws a note, or a bare "Find X" draws none.
#
# FAIL-OPEN, like every run: script. No jq, an empty or malformed payload, or a tool_input that is
# not an object prints nothing and exits 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
US="$(printf '\037')"
F="$(printf '%s' "$P" | jq -r --arg us "$US" \
  '(.tool_input | if type == "object" then . else error("not an object") end) as $i
   | [($i.subagent_type // "" | tostring), ($i.model // "" | tostring), ($i.effort // "" | tostring),
      ($i.prompt // "" | tostring | gsub("[\n\r\t]"; " "))] | join($us)' \
  2>/dev/null)" || exit 0
TYPE="${F%%"$US"*}"; F="${F#*"$US"}"
MODEL="${F%%"$US"*}"; F="${F#*"$US"}"
EFFORT="${F%%"$US"*}"
PROMPT="${F#*"$US"}"
[ "$TYPE" != fork ] || exit 0

has() { printf '%s' "$PROMPT" | LC_ALL=C /usr/bin/grep -Eiq "$1"; }
MISSING=""
add() { MISSING="${MISSING:+$MISSING; }$1"; }

has '(done|outcome|success|goal|objective|ideal state|acceptance|end state|so that|looks like|testable)' \
  || add 'a done/outcome statement (what a finished result looks like, testably)'
has '(constraint|must not|must never|never|do not|don'"'"'t|only|without|read-only|at most|no more than|avoid|stay within|out of scope|limit)' \
  || add 'constraints (what it must not touch or do)'
has '(write (it |them |the |your )?[a-z ]{0,30}(to|into|in) |save (it |them |the |your )?[a-z ]{0,30}(to|as|in) |output|return(s|ed)? |reply with|report back|respond with|deliver|[~./][A-Za-z0-9._-]+/[A-Za-z0-9._/-]+|\.(md|json|tsv|csv|txt|html)\b)' \
  || add 'an output location (a file path, or the shape of the reply)'

# Reuse agent-model.sh for the model check, so its exemptions are not copied here.
# A leading deny sentinel means "no tier chosen"; its text is not forwarded.
_am="$(printf '%s' "$P" | sh "${0%/*}/agent-model.sh" 2>/dev/null || true)"
case "$_am" in 'HARBOR-DECISION deny: '*) add 'a model (set haiku, sonnet or opus; unset inherits the parent tier)' ;; esac
# harbor#818: Haiku defaults to medium effort, and the 2026-10-08 trial measured its code changes at
# high. A brief that asks Haiku to change code with no effort set gets one line naming it.
if [ "$MODEL" = haiku ] && [ -z "$EFFORT" ] \
  && has '((^|[^a-z])fix|implement|refactor|(^|[^a-z])edit |modify|patch|write (a |the )?(regression )?tests?|add (a |an |the )?(regression )?(test|flag|verb|option|function|feature))'; then
  add 'an effort (haiku defaults to medium; set effort: high when the agent changes code)'
fi

[ -n "$MISSING" ] || exit 0
printf '%s\n' "Agent brief check (harbor#953, advisory, the call was not blocked). This brief does not state: $MISSING. A brief that names the testable outcome, the constraints and where the result goes lets the agent work without guessing. Checked by keywords, so a brief can pass and still be thin."
