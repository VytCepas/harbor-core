#!/usr/bin/env sh
# 99-skill-on-first-use: a call a skill owns, in a session that has not read that skill, names the skill and
# its SKILL.md (harbor#1591). The first note carries the USE WHEN triggers and the inline section; while the skill
# stays unread, a one-line reminder follows on the next owned call and every 10th after, at most 5 per session:
# uncapped, a 14-day replay counted 871 agent-routing reminders in 38 sessions.
#
# A CALL IS OWNED when a command-position segment (heredoc bodies and quoted arguments are data, by the
# floor's own parser) runs an `owns-commands` CLI, the tool is an `owns-tools` tool, or the call's input
# (Bash's description excluded) matches the skill's `owns-content` regex (jq's flavour, Unicode-aware).
# `grep <cli>` and `git commit -m "<cli>"` run grep and git, so they never fire on a command (CONSTITUTION §2.11).
# Read means a Read or a cat/sed/head of its SKILL.md, or a Skill call, in the transcript.
#
# THE GATE: a `gate-commands` entry, `<cli>` or `<cli>:<subcommand>`, run in command position, while the skill owns the call or was already named
# this session and is still unread, prints `HARBOR-DECISION deny:` first. Every gated call is held; the cap is the
# reminder's only. The engine honours it only when this pack's controls.tsv row is block; under warn it arrives as a
# note. A mention of the CLI never gates.
#
# FAIL-OPEN: no jq, no payload, no transcript, no guard-lib or no skills dir prints nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
US="$(printf '\037')"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SK="$CFG/skills"
[ -d "$SK" ] || exit 0
_G=/usr/bin/grep; [ -x "$_G" ] || _G=grep

# The index is derived from the skills' own frontmatter and cached: a scan per call measured ~25 ms, over
# the budget of a hook on every Bash call, and a find over every skill cost as much as the scan. Fresh while
# the skills dir and every owner's SKILL.md are older than the cache and the cache is under 5 minutes old, so
# a skill that newly gains an owns- key is noticed within 5 minutes. Row: name, commands, tools, section,
# USE-WHEN text, content regex, gate CLIs, joined on the unit separator (tab would collapse an empty field).
CACHE="$CFG/state/skill-first-use/index.v2"
INDEX=''
fresh=0
if [ -f "$CACHE" ] && [ ! "$SK" -nt "$CACHE" ] && [ -z "$(find "$CACHE" -mmin +5 2>/dev/null)" ]; then
  fresh=1
  while IFS="$US" read -r _n _rest; do
    if [ -n "$_n" ] && [ "$SK/$_n/SKILL.md" -nt "$CACHE" ]; then fresh=0; fi
  done < "$CACHE"
fi
if [ "$fresh" = 1 ]; then
  INDEX="$(cat "$CACHE" 2>/dev/null || true)"
else
  OWNERS="$("$_G" -l '^owns-' "$SK"/*/SKILL.md 2>/dev/null || true)"
  INDEX="$([ -z "$OWNERS" ] || printf '%s\n' "$OWNERS" | while IFS= read -r _f; do
    _n="${_f%/SKILL.md}"; _n="${_n##*/}"
    awk -v n="$_n" '
      function val(s) { sub(/^[^:]*:[[:space:]]*/, "", s); gsub(/^["'\'']|["'\'']$/, "", s); return s }
      NR == 1 && !/^---/ { exit }
      NR > 1 && /^---/ { exit }
      /^owns-commands:/ { c = val($0) }
      /^owns-tools:/    { t = val($0) }
      /^inline-section:/ { s = val($0) }
      /^owns-content:/  { e = val($0) }
      /^gate-commands:/ { g = val($0) }
      /^description:/   { d = val($0); i = index(d, "USE WHEN "); d = i ? substr(d, i + 9) : ""
                          i = index(d, " NOT FOR"); if (i) d = substr(d, 1, i - 1); sub(/[.[:space:]]+$/, "", d) }
      END { if (c != "" || t != "" || e != "") printf "%s\037%s\037%s\037%s\037%s\037%s\037%s\n", n, c, t, s, d, e, g }' "$_f" 2>/dev/null
  done)"
  # An empty index is cached too, so a box with no owners pays one find per call, not a scan.
  if mkdir -p "${CACHE%/*}" 2>/dev/null; then
    printf '%s\n' "$INDEX" > "$CACHE.$$" 2>/dev/null && mv -f "$CACHE.$$" "$CACHE" 2>/dev/null || true
  fi
fi
[ -n "$INDEX" ] || exit 0

# One jq pass reads the payload and answers every owns-content regex at once: the fields, then the names of the skills
# whose regex matches the call's input (Bash's description excluded), space-joined. A second jq per call measured
# +16 ms on every Bash call. A regex jq cannot compile matches nothing, so one bad skill never silences the rest.
CROWS="$(printf '%s\n' "$INDEX" | awk -F"$US" '$6 != "" { print $1 FS $6 }')"
F="$(printf '%s' "$P" | jq -r --arg us "$US" --arg rows "$CROWS" '
  ([(.tool_input // {}) | del(.description) | .. | strings] | join(" ")) as $t
  | [ $rows | split("\n")[] | select(length > 0) | split($us) as $r
      | select(try ($t | test($r[1])) catch false) | $r[0] ] as $hit
  | [(.tool_name // ""), (.session_id // ""), (.transcript_path // ""), ($hit | join(" ")),
     (.tool_input.command // "" | tostring | gsub("\u001f"; " "))] | join($us)' 2>/dev/null)" || exit 0
TOOL="${F%%"$US"*}"; F="${F#*"$US"}"
SID="${F%%"$US"*}"; F="${F#*"$US"}"
TP="${F%%"$US"*}"; F="${F#*"$US"}"
CHIT="${F%%"$US"*}"
CMD="${F#*"$US"}"
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
[ -n "$TP" ] && [ -r "$TP" ] || exit 0

# Command names this call runs, one per line, from the floor's segment table. Sourcing the floor's
# library costs ~70 ms, so a command that does not even contain an owned name never reaches it.
RAN=''
_any=0
if [ "$TOOL" = Bash ]; then
  while IFS="$US" read -r _n _cmds _tools _sec _use _con _gate; do
    for _w in $_cmds $_gate; do case "$CMD" in *"${_w%%:*}"*) _any=1 ;; esac; done
  done <<EOF
$INDEX
EOF
  [ "$_any" = 1 ] || [ -n "$CHIT" ] || exit 0
fi
if [ "$TOOL" = Bash ] && [ "$_any" = 1 ]; then
  case "$0" in */*) _H="${0%/*}" ;; *) _H=. ;; esac
  _L=''
  for _c in "$_H/../bin/library-admission.sh" "$_H/../../bin/library-admission.sh"; do
    if [ -f "$_c" ]; then _L="$_c"; break; fi
  done
  [ -n "$_L" ] || exit 0
  RAN="$( DIR="${_L%/*}"; . "$_L" >/dev/null 2>&1
    floor_seg_load "$CMD"
    # `command -v <cli>` looks a CLI up and runs nothing, but the table resolves `command` away; skip it.
    _lookup=0; printf '%s' "$CMD" | "$_G" -qE 'command[[:space:]]+(-[pvV]+[[:space:]]+)*-[pvV]*[vV]' && _lookup=1
    printf '%s\n' "$FLOOR_SEGS" | awk -v lookup="$_lookup" '
      function sid(s) { return substr(s, 1, index(s, ":") - 1) + 0 }
      function val(s) { return substr(s, index(s, ":") + 1) }
      /^SEGW:/ { s = substr($0, 6); W[sid(s)] = val(s) }
      /^SEGC:/ { s = substr($0, 6); i = sid(s); C[i] = val(s); if (i > M) M = i }
      /^SEGA:/ { s = substr($0, 6); i = sid(s); if (!(i in A)) A[i] = val(s) }
      /^SEGR:/ { s = substr($0, 6); i = sid(s); r = val(s)
                 if (substr(r, 1, 3) == "<<:") { d = substr(r, 4); sub(/^-/, "", d); H[i] = d } }
      END { delim = ""
            for (i = 1; i <= M; i++) { if (!(i in C)) continue
              if (delim != "") { if (C[i] == delim) delim = ""; continue }
              if (i in H) delim = H[i]
              if (lookup && W[i] == "command") continue
              w = C[i]; sub(/.*\//, "", w); print w
              # `<cli>:<first argument>` too, so a gate can hold one subcommand and pass the rest.
              if (i in A) print w ":" A[i] } }' )" || exit 0
  [ -n "$RAN" ] || [ -n "$CHIT" ] || exit 0
fi

SEEN="$CFG/state/skill-first-use/$SID.seen"
mkdir -p "${SEEN%/*}" 2>/dev/null || exit 0
find "${SEEN%/*}" -name '*.seen' -mtime +7 -exec rm -f {} + 2>/dev/null || true
told() { [ -f "$SEEN" ] && "$_G" -qxF -- "$1" "$SEEN"; }
unread() { # <skill>: no Read/cat of its SKILL.md and no Skill call in the transcript. A read is remembered in the ledger,
  # and so is how far the transcript was searched: a repeat check reads only what was appended since, less a 64 KiB
  # overlap for a line cut at the mark. A full search of a long transcript measured ~250 ms; the tail costs a few.
  ! { [ -f "$SEEN" ] && "$_G" -qxF -- "read:$1" "$SEEN"; } || return 1
  _sz="$(wc -c < "$TP" 2>/dev/null | tr -d ' ')"; case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
  _off="$( [ -f "$SEEN" ] && sed -n "s/^off:$1:\([0-9][0-9]*\)$/\1/p" "$SEEN" | tail -1)"; _off="${_off:-0}"
  _from=$((_off - 65536)); [ "$_from" -gt 0 ] || _from=0
  if tail -c +"$((_from + 1))" "$TP" 2>/dev/null | "$_G" -qE "\"file_path\": ?\"[^\"]*/skills/$1/SKILL\.md\"|\"skill\": ?\"([^\"]*:)?$1\"|\"command\": ?\"[^\"]*(cat|sed|head|tail|less|more) [^\"]*skills/$1/SKILL\.md"; then
    printf 'read:%s\n' "$1" >> "$SEEN" 2>/dev/null || true
    return 1
  fi
  printf 'off:%s:%s\n' "$1" "$_sz" >> "$SEEN" 2>/dev/null || true
  return 0
}
# Membership by `case`, not grep: a fork per owned word per skill measured ~100 ms once 26 skills owned something.
NL='
'
ran() { case "$NL$RAN$NL" in *"$NL$1$NL"*) return 0 ;; esac; return 1; }

OUT=''; DENY=''; GATED=''
while IFS="$US" read -r _n _cmds _tools _sec _use _con _gate; do
  case "$_n" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
  hit=0
  if [ "$TOOL" = Bash ]; then
    for _w in $_cmds; do
      if ran "$_w"; then hit=1; break; fi
    done
  else
    for _w in $_tools; do
      if [ "$_w" = "$TOOL" ] || { [ "$TOOL" = Task ] && [ "$_w" = Agent ]; }; then hit=1; fi
    done
  fi
  if [ "$hit" = 0 ]; then case " $CHIT " in *" $_n "*) hit=1 ;; esac; fi
  gate=''
  for _w in $_gate; do
    if ran "$_w"; then gate="$_w"; break; fi
  done
  # A gate CLI holds a skill this call owns, or one named earlier this session; anything else is not this skill's call.
  if [ "$hit" = 0 ] && { [ -z "$gate" ] || ! told "$_n"; }; then continue; fi
  unread "$_n" || continue
  if [ -n "$gate" ]; then
    DENY="${DENY:+$DENY; }$SK/$_n/SKILL.md"; GATED="${gate%%:*}"; case "$gate" in *:*) GATED="$GATED ${gate#*:}" ;; esac
    told "$_n" || printf '%s\n' "$_n" >> "$SEEN" 2>/dev/null || true
    continue
  fi
  if told "$_n"; then
    _k="$("$_G" -cxF -- "own:$_n" "$SEEN" 2>/dev/null || true)"; case "$_k" in ''|*[!0-9]*) _k=0 ;; esac
    printf 'own:%s\n' "$_n" >> "$SEEN" 2>/dev/null || true
    case "$((_k + 1))" in 1|10|20|30|40) OUT="${OUT}Skill \`$_n\` owns this call and is still unread: read $SK/$_n/SKILL.md.
" ;; esac
    continue
  fi
  printf '%s\n' "$_n" >> "$SEEN" 2>/dev/null || true
  OUT="${OUT}Skill \`$_n\` owns this call and was not read this session: read $SK/$_n/SKILL.md before going on."
  [ -z "$_use" ] || OUT="$OUT USE WHEN: $_use."
  if [ -n "$_sec" ] && [ -f "$SK/$_n/SKILL.md" ]; then
    _body="$(awk -v h="## $_sec" '$0 == h { f = 1; next } f && /^## / { exit } f && NF' "$SK/$_n/SKILL.md" | head -c 3000)"
    [ -z "$_body" ] || OUT="$OUT Its section \"$_sec\", read live: $_body"
  fi
  OUT="$OUT
"
done <<EOF
$INDEX
EOF
# The decision line first: the engine reads the sentinel on the first line only.
if [ -n "$DENY" ]; then
  printf 'HARBOR-DECISION deny: %s waits until the skill that governs it is read: read %s, then run it again.\n' "$GATED" "$DENY"
fi
printf '%s' "$OUT"
