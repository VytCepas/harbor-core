#!/usr/bin/env sh
# member-upgrade.sh (harbor#1278) — Stop hook on a member laptop, check `member.upgrade`: holds contracts/member-law.md §1 and §2.
#   <hook json> | sh member-upgrade.sh     prints {"decision":"block","reason":…} or nothing; exit 0 on every path
#
# A turn that did real work (§1) must end with an `Upgrade:` line: an answer of 25 words or more after a tool call, or any answer
# after two or more runs or edits (one lookup, a Read or a Grep alone, is not work). If its answer decides something (a recommendation,
# done or fixed, missing or found, a figure) and no Agent or Task call ran in the turn, it has no second reader (§2). Either gap sends
# Claude back once; stop_hook_active stands it down, so it can never loop. A question back after lookups, a refusal and a status note
# owe neither.
# The answer is last_assistant_message (the docs' field for the final text); the tool calls come from the transcript.
# Measured on a labelled corpus: tests/member/upgrade/measure.sh. Off: the hub policy drops this hook from the managed settings
# (bin/member-managed.sh). The member has no switch, by design.
set -u
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"
. "$HERE/library-log.sh"
log_init member-upgrade

JQ=/usr/bin/jq
[ -x "$JQ" ] || JQ="$(command -v jq 2>/dev/null || printf '')"
[ -n "$JQ" ] || exit 0
case "${1:-}" in -h|--help) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac

# What "decides something" looks like, English and Lithuanian (grep -Ei, C locale, so non-ASCII letters are matched as bytes).
DECIDES='recommend|suggest|rekomenduo|siūl|siul|pasirinkčiau|naudočiau|(you|we) should|i would (pick|go|choose|check|use|start|keep|move|stop|pause|set)|better (to|off)|reikėtų|turėtumėte|geriau|verta'
DECIDES="$DECIDES"'|root cause|that is why|which (explains|is why)|štai kodėl'
DECIDES="$DECIDES"'|\b(done|fixed|resolved|complete|completed|ready|migrated|deployed|passes|passed|fails|failed|broken|missing|lacks?|found|works|confirmed|verified|matches|unchanged|paused|disabled|wrong|twice|redundant|duplicates?)\b'
DECIDES="$DECIDES"'|(does not|doesn.t|did not|didn.t|never|no longer|not) (exist|fire|fired|work|match|load|run|send|reach|show|appear|count|track|record)|there (is|are) no|no such|not found|does not exist'
DECIDES="$DECIDES"'|\b(padaryta|sutvark|pataisy|atlikta|baigta|paruošta|parengta|veikia|neveikia|suveik|nesuveik|trūksta|truksta|nėra|nerasta|neegzistuoja|radau|rasta|sutampa|nepraeina|praėjo|praeina|dingdavo|klaida|nustatyta|neatitinka)'
DECIDES="$DECIDES"'|[^[:space:]]{4,}i?au([^a-z]|$)|kite([^a-z]|$)'
DECIDES="$DECIDES"'|[0-9]([.,][0-9]+)* ?(%|€|usd|\$|eur(os?)?([^a-z]|$))|(€|\$) ?[0-9]|(cpa|roas|ctr|cpc|cpm|aov)[^.]{0,20}[0-9]'
DECIDES="$DECIDES"'|(^|[.!?:;] +)(use|pause|remove|move|add|delete|publish|switch|change|replace|enable|disable|stop|compress|divide|rename|raise|lower|increase|decrease|cut|apply|re-?run|re-?enable|drop|fix|check)[[:space:]]'
# Phrases that carry a trigger word without deciding anything, taken out before DECIDES looks.
BENIGN='s/[Yy]ou should (see|find|notice|get)//g; s/[Hh]ow [a-z ]{1,30} works//g; s/[Ee]ither works//g; s/[Ff]ixed[- ](budget|cost|price|width|rate|fee)//g; s/[Ww]hen (you are |you.re )?done//g; s/100 ?%//g; s/([Ii]f|[Ww]hen|[Ww]henever) [a-z ]{1,25} (fails|fail|failed)//g; s/mažiau|daugiau|[Pp]a(rašykite|sakykite)|[Aa]tsiųskite//g'
# An answer that opens like this is a refusal or a status note, not a result.
STANDS_DOWN='^[[:space:]>*_-]*(I (can.t|cannot|won.t|will not|am not able to|did not follow)|Sorry|Still (running|working)|Progress:|In progress|Atsiprašau|Negaliu|Deja|Dar (vyksta|dirbu)|Pažanga:)'

IN="$(cat 2>/dev/null)" || exit 0
[ -n "$IN" ] || exit 0
[ "$(printf '%s' "$IN" | "$JQ" -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0
REPLY="$(printf '%s' "$IN" | "$JQ" -r '.last_assistant_message // ""' 2>/dev/null)" || exit 0
TX="$(printf '%s' "$IN" | "$JQ" -r '.transcript_path // ""' 2>/dev/null)" || exit 0

# THE TURN is everything after the last real user prompt. Three counts: tool calls, Agent/Task calls, and lookups (Read, Grep,
# Glob and the like: not work).
TOOLS=0; AGENTS=0; LOOKUP=0
if [ -n "$TX" ] && [ -f "$TX" ] && [ -r "$TX" ]; then
  _c="$("$JQ" -rs '
    def isprompt: .type=="user" and ((.message.content|type)=="string"
      or ([.message.content[]? | select(.type=="tool_result")] | length) == 0);
    def cnt(f): [.[] | select(f)] | length;
    (. as $a | [range(0; $a|length) | select($a[.] | isprompt)] | last // -1) as $p
    | [.[($p+1):][] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name] as $n
    | [($n | length), ($n | cnt(. == "Agent" or . == "Task")), ($n | cnt(. == "Read" or . == "Grep" or . == "Glob" or . == "LS" or . == "TodoWrite" or . == "ToolSearch" or . == "WebFetch" or . == "WebSearch" or . == "AskUserQuestion"))] | join(" ")' "$TX" 2>/dev/null)" || _c=""
  case "$_c" in *[!0-9\ ]*|'') ;; *) set -- $_c; TOOLS="$1"; AGENTS="$2"; LOOKUP="$3" ;; esac
fi
[ "$TOOLS" -gt 0 ] || exit 0
WORDS="$(printf '%s' "$REPLY" | wc -w | tr -d ' ')"
case "$WORDS" in ''|*[!0-9]*) exit 0 ;; esac
WORK=$((TOOLS - LOOKUP))

# A question back to the person after lookups only, a refusal and a status note owe nothing. A turn that ran or changed something is
# not excused by a closing question, so the check cannot be dodged by asking one.
if { [ "$WORK" -eq 0 ] && printf '%s' "$REPLY" | grep -q '?'; } \
  || printf '%s\n' "$REPLY" | sed -n '1p' | LC_ALL=C grep -Eiq "$STANDS_DOWN"; then exit 0; fi

# §1: the turn was real work when the answer is 25 words or more, or follows two or more runs or edits. One lookup alone is not work.
WORKED=0
if [ "$WORDS" -ge 25 ] || [ "$WORK" -ge 2 ]; then WORKED=1; fi
[ "$TOOLS" -eq 1 ] && [ "$WORK" -eq 0 ] && WORKED=0

NEED=""
if [ "$WORKED" -eq 1 ]; then
  printf '%s\n' "$REPLY" | LC_ALL=C grep -Eiq '^[[:space:]>*_#-]*Upgrade[[:space:]]*(\*\*|__)?[[:space:]]*:' \
    || NEED="End the answer with one line starting \"Upgrade:\" that names one concrete skill, pack, harbor command, connector or better way to ask that would have made this work better, specific to this task (company rules §1)."
fi

# §2: an answer decides something when its text says so ($DECIDES).
if [ "$AGENTS" -eq 0 ] && printf '%s\n' "$REPLY" | sed -E "$BENIGN" | LC_ALL=C grep -Eiq "$DECIDES"; then
  NEED="${NEED:+$NEED }This answer decides something and no second agent checked it: spawn a fresh agent with the claims and their sources, cut what it cannot support, and say how many claims held (company rules §2)."
fi

[ -n "$NEED" ] || exit 0
"$JQ" -nc --arg r "member.upgrade: $NEED" '{decision: "block", reason: $r}'
exit 0
