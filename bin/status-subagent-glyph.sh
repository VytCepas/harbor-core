#!/usr/bin/env sh
# L0-5b (harbor#293) — Claude Code SUBAGENT statusline: one row per live agent.
#
#   settings.json:  "subagentStatusLine": { "type": "command",
#                     "command": "/bin/sh ~/.claude/bin/status-subagent-glyph.sh" }
# Why: the default agent row says what an agent is called, not where it stands. Two measured traps are collisions in a shared working directory, diagnosed only AFTER the damage:
# workflow agents sharing one scratchpad (12 arms, 51 operations on one filename) and concurrent sessions reverting uncommitted work. `cwd` is in this payload per task, so the collision is renderable WHILE IT HAPPENS.
# Contract (docs: subagentStatusLine): stdin is one object with `columns` and `tasks`; stdout is one JSON line per row, {id, content}, to OVERRIDE (omitting a task keeps its default, an empty content hides it).
# Every field is optional, so a token is emitted only when its source is present. No forks, no files: it reads its own stdin only.
# FLAGS / ENV: --help; HARBOR_STATUS_SUBAGENT_GLYPH_DUMP=<f> appends the raw payload to <f>; HARBOR_TEST_NOW=<epoch> freezes the clock (the suite pins this).
# Removed notes: docs/explanation/code-cases/bin-status-subagent-glyph.md
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac

IN="$(cat 2>/dev/null || true)"
[ -n "$IN" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

if [ -n "${HARBOR_STATUS_SUBAGENT_GLYPH_DUMP:-}" ]; then
  ( umask 077; printf '%s\n' "$IN" >> "${HARBOR_STATUS_SUBAGENT_GLYPH_DUMP:-}" ) 2>/dev/null || true
fi

E="$(printf '\033')"
NOW_EPOCH="${HARBOR_TEST_NOW:-$(date +%s)}"

# ONE jq PASS, ALL ARITHMETIC INSIDE IT (as status-fleet-glyph.sh): `[ 41.7 -ge 85 ]` is an ERROR that `2>/dev/null` swallows into a ramp that never fires.
# EXIT 0 EVEN ON A MALFORMED PAYLOAD: writing nothing leaves every row at its default rendering, and a display helper must never damage the thing it decorates.
printf '%s' "$IN" | jq -r -c \
  --arg dim "$E[2m" --arg rst "$E[0m" --arg red "$E[31m" --arg yel "$E[33m" --arg grey "$E[90m" \
  --argjson now "$NOW_EPOCH" '
  def esc: $dim; # placeholder to keep the def block uniform if extended

  # startTime has no documented unit, so all three plausible encodings are accepted and an unparseable one yields NOTHING, never a wrong age (a fabricated 0m reads as just started).
  def secs(t):
    if   (t|type) == "number" then (if t > 100000000000 then (t / 1000) else t end)
    elif (t|type) == "string" then (t | try (fromdateiso8601) catch (try (tonumber
           | if . > 100000000000 then (. / 1000) else . end) catch null))
    else null end;
  def age(t):
    secs(t) as $s
    | if $s == null then "" else (($now - $s) | floor) as $d
      | if   $d < 0    then ""
        elif $d < 60   then "\($d)s"
        elif $d < 3600 then "\(($d / 60) | floor)m"
        else                "\(($d / 3600) | floor)h\((($d % 3600) / 60) | floor)m"
        end
      end;

  def tail(p): if (p // "") == "" then "" else (p | split("/") | last) end;

  def reading: if type == "number" then . elif type == "object"
               then (.tokenCount // .tokens // .count // .value // null) else null end;
  # ACTIVITY, NOT LEVEL: tokenCount only grows, so deltas between readings show work as it happens and a flat tail is an agent that stopped growing (operator, 2026-10-16). Block elements are East-Asian-width A: one column by default.
  def deltas: [ .[] | reading | select(. != null) ] as $r
              | [ range(1; $r | length) as $i | ($r[$i] - $r[$i - 1]) | if . < 0 then 0 else . end ];
  def spark: (. | max // 0) as $m
             | if $m <= 0 then "" else map(("▁▂▃▄▅▆▇█" | split(""))[(. * 7 / $m | floor)]) | join("") end;
  # agentType names the agent definition; plugin prefixes and the long built-in names
  # are shortened, everything else shows as given.
  def short: tostring | split(":") | last
             | if . == "general-purpose" then "general" elif . == "claude-code-guide" then "guide" else . end;

  (.tasks // []) as $t
  # THE COLLISION SET: any cwd claimed by more than one RUNNING agent, computed across the whole array (a finished agent writes nothing, and counting it made SHARED a false positive, 2026-10-16).
  | ([ $t[] | select((.status // "running") == "running") | .cwd // "" | select(. != "") ]
     | group_by(.) | map(select(length > 1) | .[0])) as $shared
  | $t[]
  | . as $x
  | (tail($x.cwd)) as $dir
  | (($x.status // "running") == "running") as $live
  | (if ($x.tokenSamples | type) == "array" then ($x.tokenSamples[-12:] | deltas) else [] end) as $dl
  | [ # STATUS FIRST AND ONLY WHEN IT IS NOT THE ORDINARY ONE. A row that says
      # "running" on every running agent is a column spent to say nothing.
      (if $live then ""
       elif $x.status == "failed" or $x.status == "killed" then $red + $x.status + $rst + " "
       else $dim + ($x.status | tostring) + $rst + " " end)
      + ($x.name // $x.label // $x.type // "agent" | tostring)
        + (if ($x.agentType // "") == "" then "" else " " + $grey + ($x.agentType | short) + $rst end),
      ((($x.model // null) | if type == "object" then (.display_name // .id // null) else . end) as $m
       | if $m == null or ($m | tostring) == "" then empty
         else ($m | tostring | ascii_downcase) as $l
              | $dim + (($l | capture("(?<f>opus|sonnet|haiku|fable)") | .f)
                        // ($l | sub("^claude-"; "") | split("-")[0] | split(" ")[0])) + $rst end),
      (if ($x.effort // null) == null then empty
       else ($x.effort | tostring) as $e
            | (if $e == "max" or $e == "xhigh" then $yel + ($e | ascii_upcase) + $rst
               else $dim + $e + $rst end) end),
      # A PERCENTAGE NEEDS BOTH FIELDS: tokenCount over an assumed 200k would be a confident wrong number on a 1M model.
      (if ($x.tokenCount // null) == null or ($x.contextWindowSize // null) == null
          or ($x.contextWindowSize <= 0) then empty
       else (($x.tokenCount * 100) / $x.contextWindowSize | round) as $p
            | (if $p >= 90 then $red elif $p >= 70 then $yel else $dim end)
              + "\($p)%" + $rst end),
      # THE ACTIVITY TRACE, and IDLE once the last three readings did not grow on a running agent (needs four readings to say either).
      (if ($dl | length) < 3 then empty
       else [ ($dl | spark | if . == "" then empty else $grey + . + $rst end),
              (if $live and ($dl[-3:] | all(. == 0)) then $yel + "idle" + $rst else empty end) ]
            | if length == 0 then empty else join(" ") end
       end),
      (age($x.startTime) as $a | if $a == "" then empty else $dim + $a + $rst end),
      # THE POINT OF THE FILE: a directory two agents share renders YELLOW and marked with a WORD, not a glyph (narrow text-presentation symbols do not render in this terminal).
      (if $dir == "" then empty
       elif $live and ([$shared[]] | index($x.cwd)) != null then $yel + $dir + " SHARED" + $rst
       else $dim + $dir + $rst end)
    ]
  # Same boundary mark as the main row (status-fleet-glyph.sh defines the grammar: a bar separates different facts, a tight middot means more about the fact on its left); a spaced middot is the form the main row removed.
  # The constant is duplicated because this sibling renderer cannot source status-fleet-glyph.sh; the suite asserts both emit the same mark and neither a spaced middot, and that assertion is what keeps the copy safe.
  | join($dim + " │ " + $rst) as $content
  | { id: ($x.id // ""), content: $content }
  | select(.id != "")
' 2>/dev/null || exit 0
