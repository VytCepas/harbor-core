#!/usr/bin/env sh
# 99-skill-on-first-use: the first time a session runs a CLI (or tool) that a skill owns, and has not
# read that skill, name the skill, its SKILL.md and its USE WHEN triggers. Inform only, never a deny.
#
# SILENT UNLESS ALL HOLD: a command-position segment (heredoc bodies and quoted arguments are data,
# by the floor's own parser) runs an owned CLI, or the tool is an owned tool; this session has not
# been told about that skill; and the transcript shows no Read of its SKILL.md and no Skill call.
# `grep <cli>` and `git commit -m "<cli>"` run grep and git, so they never fire (CONSTITUTION §2.11).
#
# FAIL-OPEN: no jq, no payload, no transcript, no guard-lib or no skills dir prints nothing, exit 0.
set -eu
command -v jq >/dev/null 2>&1 || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
US="$(printf '\037')"
F="$(printf '%s' "$P" | jq -r --arg us "$US" \
  '[(.tool_name // ""), (.session_id // ""), (.transcript_path // ""), (.tool_input.command // "" | tostring | gsub("\u001f"; " "))] | join($us)' 2>/dev/null)" || exit 0
TOOL="${F%%"$US"*}"; F="${F#*"$US"}"
SID="${F%%"$US"*}"; F="${F#*"$US"}"
TP="${F%%"$US"*}"
CMD="${F#*"$US"}"
case "$SID" in ''|*[!A-Za-z0-9._-]*) exit 0 ;; esac
[ -n "$TP" ] && [ -r "$TP" ] || exit 0

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SK="$CFG/skills"
[ -d "$SK" ] || exit 0
_G=/usr/bin/grep; [ -x "$_G" ] || _G=grep

# The index is derived from the skills' own frontmatter and cached: a scan per call measured ~25 ms, over
# the budget of a hook on every Bash call, and a find over every skill cost as much as the scan. Fresh while
# the skills dir and every owner's SKILL.md are older than the cache and the cache is under 5 minutes old, so
# a skill that newly gains an owns- key is noticed within 5 minutes. Row: name, commands, tools, section,
# USE-WHEN text, joined on the unit separator (tab would collapse an empty field).
CACHE="$CFG/state/skill-first-use/index"
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
      /^description:/   { d = val($0); i = index(d, "USE WHEN "); d = i ? substr(d, i + 9) : ""
                          i = index(d, " NOT FOR"); if (i) d = substr(d, 1, i - 1); sub(/[.[:space:]]+$/, "", d) }
      END { if (c != "" || t != "") printf "%s\037%s\037%s\037%s\037%s\n", n, c, t, s, d }' "$_f" 2>/dev/null
  done)"
  # An empty index is cached too, so a box with no owners pays one find per call, not a scan.
  if mkdir -p "${CACHE%/*}" 2>/dev/null; then
    printf '%s\n' "$INDEX" > "$CACHE.$$" 2>/dev/null && mv -f "$CACHE.$$" "$CACHE" 2>/dev/null || true
  fi
fi
[ -n "$INDEX" ] || exit 0

# Command names this call runs, one per line, from the floor's segment table. Sourcing the floor's
# library costs ~70 ms, so a command that does not even contain an owned name never reaches it.
RAN=''
if [ "$TOOL" = Bash ]; then
  _any=0
  while IFS="$US" read -r _n _cmds _rest; do
    for _w in $_cmds; do case "$CMD" in *"$_w"*) _any=1 ;; esac; done
  done <<EOF
$INDEX
EOF
  [ "$_any" = 1 ] || exit 0
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
      /^SEGR:/ { s = substr($0, 6); i = sid(s); r = val(s)
                 if (substr(r, 1, 3) == "<<:") { d = substr(r, 4); sub(/^-/, "", d); H[i] = d } }
      END { delim = ""
            for (i = 1; i <= M; i++) { if (!(i in C)) continue
              if (delim != "") { if (C[i] == delim) delim = ""; continue }
              if (i in H) delim = H[i]
              if (lookup && W[i] == "command") continue
              w = C[i]; sub(/.*\//, "", w); print w } }' )" || exit 0
  [ -n "$RAN" ] || exit 0
fi

SEEN="$CFG/state/skill-first-use/$SID.seen"
mkdir -p "${SEEN%/*}" 2>/dev/null || exit 0
find "${SEEN%/*}" -name '*.seen' -mtime +7 -exec rm -f {} + 2>/dev/null || true
told() { [ -f "$SEEN" ] && "$_G" -qxF -- "$1" "$SEEN"; }
unread() { # <skill>: no Read/cat of its SKILL.md and no Skill call in the transcript
  ! "$_G" -qE "\"file_path\": ?\"[^\"]*/skills/$1/SKILL\.md\"|\"skill\": ?\"([^\"]*:)?$1\"|\"command\": ?\"[^\"]*(cat|sed|head|tail|less|more) [^\"]*skills/$1/SKILL\.md" "$TP" 2>/dev/null
}

OUT=''
while IFS="$US" read -r _n _cmds _tools _sec _use; do
  case "$_n" in ''|*[!A-Za-z0-9._-]*) continue ;; esac
  hit=0
  if [ "$TOOL" = Bash ]; then
    for _w in $_cmds; do
      if printf '%s\n' "$RAN" | "$_G" -qxF -- "$_w"; then hit=1; break; fi
    done
  else
    for _w in $_tools; do
      if [ "$_w" = "$TOOL" ] || { [ "$TOOL" = Task ] && [ "$_w" = Agent ]; }; then hit=1; fi
    done
  fi
  [ "$hit" = 1 ] || continue
  if told "$_n"; then continue; fi
  printf '%s\n' "$_n" >> "$SEEN" 2>/dev/null || true
  if ! unread "$_n"; then continue; fi
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
printf '%s' "$OUT"
