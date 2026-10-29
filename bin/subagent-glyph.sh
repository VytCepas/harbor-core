#!/usr/bin/env sh
# L0-5b (harbor#293) — Claude Code SUBAGENT statusline: one row per live agent.
#
#   settings.json:  "subagentStatusLine": { "type": "command",
#                     "command": "/bin/sh ~/.claude/bin/subagent-glyph.sh" }
#
# WHY THIS EXISTS, AND IT IS NOT SYMMETRY WITH THE MAIN ROW. The default agent row
# reads `name · description · token count`, which answers what an agent is called
# and nothing about where it is standing. Two of this box's measured traps are
# about exactly that:
#
#   • WORKFLOW AGENTS SHARE ONE SCRATCHPAD — measured at 12 arms and 51 operations
#     against a single filename, with one arm emitting rules only its siblings had
#     written. Nothing on screen said two agents were in one directory.
#   • CONCURRENT SESSIONS REVERT UNCOMMITTED WORK — three files reverted to HEAD
#     mid-suite by another writer, `git status` clean, no stash.
#
# Both are collisions in a shared working directory, and both were diagnosed AFTER
# the damage from transcripts. `cwd` is in this payload per task, so the collision
# is renderable WHILE IT HAPPENS. That is the entire justification for this file;
# the tokens, the effort and the age are context, not the point.
#
# CONTRACT (docs: subagentStatusLine). Stdin is ONE object with `columns` and a
# `tasks` array; each task carries id, name, type, status, description, label,
# startTime, model, effort, contextWindowSize, tokenCount, tokenSamples, cwd.
# Stdout is one JSON line per row to OVERRIDE — `{"id": "...", "content": "..."}`.
# Omitting a task keeps its default rendering; an empty content string HIDES it.
#
# EVERY FIELD HERE IS OPTIONAL AND THE DOCS SAY SO. contextWindowSize and model
# are omitted until the model resolves; effort is absent when the agent inherits
# the session's. So each token is emitted only when its source is present, and a
# row with nothing to add is left to the default renderer rather than replaced by
# a worse copy of it.
#
# NO FORKS AND NO FILES. This runs once per refresh tick beside the main row. It
# reads its own stdin and nothing else — no git, no ps, no cache. If that ever
# stops being true, the tick cost doubles for every visible agent.
#
# FLAGS / ENV:
#   --help                 this header
#   HARBOR_SUBGLYPH_DUMP=<f>  append the raw payload to <f> (off unless set)
#   HARBOR_NOW=<epoch>     freeze the clock (the suite pins this)
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac

IN="$(cat 2>/dev/null || true)"
[ -n "$IN" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

if [ -n "${HARBOR_SUBGLYPH_DUMP:-}" ]; then
  ( umask 077; printf '%s\n' "$IN" >> "$HARBOR_SUBGLYPH_DUMP" ) 2>/dev/null || true
fi

E="$(printf '\033')"
NOW_EPOCH="${HARBOR_NOW:-$(date +%s)}"

# ONE jq PASS, AND ALL ARITHMETIC INSIDE IT — the same rule fleet-glyph.sh states
# and for the same measured reason: `[ 41.7 -ge 85 ]` is not false in POSIX sh, it
# is an ERROR that `2>/dev/null` swallows into a ramp that never fires.
#
# EXIT 0 EVEN ON A MALFORMED PAYLOAD. Writing nothing leaves every row at its
# default rendering, which is a worse row but a correct one. A non-zero exit or a
# half-written line would degrade the agent panel itself, and a display helper must
# never be able to damage the thing it decorates.
printf '%s' "$IN" | jq -r -c \
  --arg dim "$E[2m" --arg rst "$E[0m" --arg red "$E[31m" --arg yel "$E[33m" --arg grey "$E[90m" \
  --argjson now "$NOW_EPOCH" '
  def esc: $dim; # placeholder to keep the def block uniform if extended

  # startTime IS NOT DOCUMENTED AS A UNIT, so all three plausible encodings are
  # accepted and an unparseable one yields NOTHING rather than a wrong age. A
  # fabricated "0m" on a long-running agent is worse than a missing age: it reads
  # as "just started" at the moment you are trying to work out what is stuck.
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

  # THE TAIL OF THE PATH, NOT THE PATH. A full cwd is 40+ columns of mostly shared
  # prefix in a row the docs warn is width-limited; the last segment is the part
  # that differs between agents, which is the only part this row exists to show.
  def tail(p): if (p // "") == "" then "" else (p | split("/") | last) end;

  # A READING IS A NUMBER OR AN OBJECT CARRYING ONE; the docs name tokenSamples
  # ("up to the last 16 readings") without a shape, so both are accepted and anything
  # else reads as absent.
  def reading: if type == "number" then . elif type == "object"
               then (.tokenCount // .tokens // .count // .value // null) else null end;
  # ACTIVITY, NOT LEVEL. tokenCount only grows, so a sparkline of raw readings is a
  # ramp on every agent. The deltas between readings show work as it happens, and a
  # flat tail is an agent that has stopped growing (operator decision 2026-10-16).
  # Block elements are East-Asian-width A: one column unless a terminal is set to
  # draw ambiguous characters wide, which is off by default.
  def deltas: [ .[] | reading | select(. != null) ] as $r
              | [ range(1; $r | length) as $i | ($r[$i] - $r[$i - 1]) | if . < 0 then 0 else . end ];
  def spark: (. | max // 0) as $m
             | if $m <= 0 then "" else map(("▁▂▃▄▅▆▇█" | split(""))[(. * 7 / $m | floor)]) | join("") end;
  # agentType names the agent definition; plugin prefixes and the long built-in names
  # are shortened, everything else shows as given.
  def short: tostring | split(":") | last
             | if . == "general-purpose" then "general" elif . == "claude-code-guide" then "guide" else . end;

  (.tasks // []) as $t
  # THE COLLISION SET. Any cwd claimed by more than one RUNNING agent — computed
  # across the whole array, which is why this cannot be a per-row transform. A
  # finished agent writes nothing more, so counting it made SHARED fire on every
  # agent that ever ran in the session directory (a false positive, 2026-10-16).
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
      # MODEL AND EFFORT ON EVERY ROW (operator ask, 2026-10-09). The model is
      # omitted until it resolves, so an unresolved one renders nothing. Only the
      # family renders (claude-sonnet-5-5, "Sonnet 5.5" → sonnet): the operator
      # always runs the latest of each, so the version is noise.
      ((($x.model // null) | if type == "object" then (.display_name // .id // null) else . end) as $m
       | if $m == null or ($m | tostring) == "" then empty
         else ($m | tostring | ascii_downcase) as $l
              | $dim + (($l | capture("(?<f>opus|sonnet|haiku|fable)") | .f)
                        // ($l | sub("^claude-"; "") | split("-")[0] | split(" ")[0])) + $rst end),
      # EFFORT IS ABSENT WHEN INHERITED, and an absent one now renders nothing: the
      # word `inherit` sat on almost every row and said only "same as the session"
      # (operator decision 2026-10-16).
      (if ($x.effort // null) == null then empty
       else ($x.effort | tostring) as $e
            | (if $e == "max" or $e == "xhigh" then $yel + ($e | ascii_upcase) + $rst
               else $dim + $e + $rst end) end),
      # A PERCENTAGE NEEDS BOTH FIELDS. contextWindowSize is documented omitted
      # until the model resolves, and tokenCount over an assumed 200k would be a
      # confident wrong number on a 1M model — off by 5x, in the direction that
      # reads as trouble when there is none.
      (if ($x.tokenCount // null) == null or ($x.contextWindowSize // null) == null
          or ($x.contextWindowSize <= 0) then empty
       else (($x.tokenCount * 100) / $x.contextWindowSize | round) as $p
            | (if $p >= 90 then $red elif $p >= 70 then $yel else $dim end)
              + "\($p)%" + $rst end),
      # THE ACTIVITY TRACE, and IDLE once the last three readings did not grow on a
      # running agent: the "is it stuck?" answer. Needs four readings to say either.
      (if ($dl | length) < 3 then empty
       else [ ($dl | spark | if . == "" then empty else $grey + . + $rst end),
              (if $live and ($dl[-3:] | all(. == 0)) then $yel + "idle" + $rst else empty end) ]
            | if length == 0 then empty else join(" ") end
       end),
      (age($x.startTime) as $a | if $a == "" then empty else $dim + $a + $rst end),
      # THE POINT OF THE FILE. A directory two agents share is rendered YELLOW and
      # marked; one agent alone in its directory is dim and unmarked. The mark is a
      # word, not a glyph: the operator reported that narrow text-presentation
      # symbols do not render at all in this terminal, which is how the main row
      # lost its pencil and its warning sign.
      (if $dir == "" then empty
       elif $live and ([$shared[]] | index($x.cwd)) != null then $yel + $dir + " SHARED" + $rst
       else $dim + $dir + $rst end)
    ]
  # THE SAME BOUNDARY MARK AS THE MAIN ROW, and the reason is that they are read
  # in the same glance. fleet-glyph.sh defines the grammar: ` | ` separates
  # DIFFERENT facts, ` ·` means MORE ABOUT the fact on its left. Every field joined
  # here is a different fact — name, status, model, effort, context share, age,
  # directory — so this is the boundary case, and it was spelled with a SPACED
  # middot until 2026-08-24. That is the one form the main row removed, because
  # there the identical character also meant sub-fact two tokens away.
  #
  # A DUPLICATED CONSTANT, GUARDED BY A TEST RATHER THAN A COMMENT. This file
  # cannot source fleet-glyph.sh — it is a sibling renderer, not a library, and it
  # redefines the colours for the same reason. So the suite asserts BOTH renderers
  # emit the same mark and that NEITHER emits a spaced middot; that assertion is
  # what makes the copy safe, and deleting it puts the two rows back on separate
  # grammars with nothing to notice.
  | join($dim + " │ " + $rst) as $content
  | { id: ($x.id // ""), content: $content }
  | select(.id != "")
' 2>/dev/null || exit 0
