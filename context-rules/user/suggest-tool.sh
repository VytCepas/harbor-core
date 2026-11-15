#!/usr/bin/env sh
# suggest-tool.sh (harbor#1485): a call doing by hand a job Harbor has a better way for prints the person's line, as the engine's
# HARBOR-USER-LINE sentinel, then a fixed note for the agent. The rows are suggest-tool.tsv beside this file. A note, never a decision.
#
# THE ORDER IS THE COST (lane contract): this runs on nearly every tool call until it speaks. Off file or empty table leaves before
# stdin or jq; one jq; a subagent leaves; one awk on the tools cell; for Bash one `case` on each row's literal word, so the floor's
# parser loads only on a hit. Everything else runs only after a row was a candidate.
#
# SILENT WHEN any of these holds: suggestions are off, the row is stopped, its required file is absent, the skill it names is already
# in use, the surface cannot load the mod, another pack speaks on the command. FAIL-OPEN: any error prints nothing and exits 0.
# The state folder is a confinement write row, so this hook, which runs outside the sandbox, believes none of it: a link or a non-regular
# file reads as "cannot tell", which is silent. What it reads is compared and never copied, so a raced read carries no byte anywhere.
set -u
TAB='	'
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
STATE="${HARBOR_STATUS_SUGGEST_DIR:-$HOME/.local/state/harbor/suggest}"
[ ! -L "$STATE" ] || exit 0
[ ! -e "$STATE/off" ] && [ ! -L "$STATE/off" ] || exit 0
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
TBL="$HERE/suggest-tool.tsv"

has_rows() { # <table>: builtins only, this is the path every session pays for an empty table
  while IFS= read -r _l || [ -n "$_l" ]; do
    case "$_l" in ''|'#'*|"id$TAB"*) continue ;; esac
    return 0
  done < "$1"
  return 1
}
# One table: a company's rows have no delivery until harbor#1278, and that lane decides how they are checked before they can reach a person.
[ -f "$TBL" ] && has_rows "$TBL" || exit 0
command -v jq >/dev/null 2>&1 || exit 0

F="$(jq -r '[(.agent_id // ""), (.tool_name // ""), (.transcript_path // ""),
             (.tool_input.file_path // .tool_input.notebook_path // "" | tostring | gsub("\t"; " ")),
             (.tool_input.command // "" | tostring)] | join("\t")' 2>/dev/null)" || exit 0
AID="${F%%"$TAB"*}"; F="${F#*"$TAB"}"
[ -z "$AID" ] || exit 0
TOOL="${F%%"$TAB"*}"; F="${F#*"$TAB"}"
TP="${F%%"$TAB"*}"; F="${F#*"$TAB"}"
FP="${F%%"$TAB"*}"; CMD="${F#*"$TAB"}"
[ -n "$TOOL" ] || exit 0

SUGGEST_HERE="$HERE"
. "$HERE/suggest-subject.sh"
ROWS="$(suggest_rows "$TOOL" "$TBL" "$TBL")"
[ -n "$ROWS" ] || exit 0

CAND=''; INTRO=''
NL='
'
while IFS= read -r _r; do
  _c="${_r#*"$TAB"}"; _k="${_c%%"$TAB"*}"
  if [ "$_k" = intro ]; then [ -n "$INTRO" ] || INTRO="$_r"; continue; fi
  if [ "$TOOL" = Bash ]; then
    _c="${_c#*"$TAB"}"; _c="${_c#*"$TAB"}"; _w="${_c%%"$TAB"*}"
    case "$CMD" in *"$_w"*) ;; *) continue ;; esac
  fi
  CAND="$CAND$_r$NL"
done <<ROWS
$ROWS
ROWS
[ -n "$CAND" ] || [ -n "$INTRO" ] || exit 0

load() { IFS="$TAB" read -r ID KIND TOOLS WORD REC QUIET LINE SW SAFE INSTALL REQ SRC <<ROW
$1
ROW
}
stopped() { # <id>: a stop list that is not a plain file cannot say a row is free
  [ -e "$STATE/stopped.tsv" ] || [ -L "$STATE/stopped.tsv" ] || return 1
  [ -f "$STATE/stopped.tsv" ] && [ ! -L "$STATE/stopped.tsv" ] || return 0
  while IFS="$TAB" read -r _i _rest; do
    if [ "$_i" = "$1" ]; then return 0; fi
  done < "$STATE/stopped.tsv"
  return 1
}
present() { # <requires cell>: by file, never PATH (a hook's PATH is not the person's)
  case "$1" in
    -) return 0 ;;
    *..*) return 1 ;;
    @CFG@/*) [ -e "$CFG/${1#@CFG@/}" ] ;;
    @HOME@/*) [ -e "$HOME/${1#@HOME@/}" ] ;;
    *) return 1 ;;
  esac
}
# The surface is a stub until the Desktop probe settles the signal: only the Desktop entry point counts as able to load a mod.
surface_can_load() {
  [ -z "${WSL_DISTRO_NAME:-}${WSL_INTEROP:-}" ] || return 1
  [ "${CLAUDE_CODE_ENTRYPOINT:-}" = claude-desktop ]
}
mod_loaded() { # <mod>: the first file that names it decides, the managed files before the person's own. Runs only after a mod row matched.
  for _s in "${HARBOR_SCOPE_MANAGED_SETTINGS:-/Library/Application Support/ClaudeCode/managed-settings.json}" \
            "${HARBOR_SCOPE_MANAGED_SETTINGS:-/etc/claude-code/managed-settings.json}" "$CFG/settings.json"; do
    [ -f "$_s" ] || continue
    case "$(jq -r --arg m "$1@" '[.enabledPlugins | to_entries[] | select(.key | startswith($m)) | .value == true] | if length == 0 then "none" else (any | tostring) end' "$_s" 2>/dev/null)" in
      true) return 0 ;;
      false) return 1 ;;
    esac
  done
  return 1
}
# skill-first-use.sh's `unread`, the other way up. No transcript means the rule cannot tell, so it stays silent.
skill_in_use() { # <skill>
  case "$1" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  [ -n "$TP" ] && [ -r "$TP" ] || return 0
  "$SUGGEST_GREP" -qE "\"file_path\": ?\"[^\"]*/skills/$1/SKILL\.md\"|\"skill\": ?\"([^\"]*:)?$1\"|\"command\": ?\"[^\"]*(cat|sed|head|tail|less|more) [^\"]*skills/$1/SKILL\.md" "$TP" 2>/dev/null
}
speak() { # the sentinel, then a note that is never empty: the sentence is composed here, the table supplies only the tool's name
  printf 'HARBOR-USER-LINE %s: %s\n' "$ID" "$LINE"
  if [ "$SAFE" = yes ] && [ "$SW" != - ]; then
    printf 'Suggestion %s. The person was told: "%s". Switch to %s for this job from here on; the call in hand still runs.' "$ID" "$LINE" "$SW"
  else
    printf 'Suggestion %s. The person was told: "%s". Carry on with what you are doing; the choice is theirs.' "$ID" "$LINE"
  fi
  _t="$(suggest_stop_tool)"
  [ -z "$_t" ] || printf ' If they say no: sh %s stop %s --origin agent.' "$_t" "$ID"
  printf '\n'
}

if [ -n "$CAND" ]; then
  if [ "$TOOL" = Bash ]; then SUBJ="$(suggest_subject Bash "$CMD")"; else SUBJ="$(suggest_subject "$TOOL" "$FP")"; fi
  OVER=''
  while IFS= read -r _r; do
    [ -n "$_r" ] || continue
    load "$_r"
    suggest_row_hits "$TOOL" "$REC" "$QUIET" "$SUBJ" || continue
    if stopped "$ID"; then continue; fi
    present "$REQ" || continue
    case "$KIND" in
      mod) surface_can_load || continue; if mod_loaded "$SW"; then continue; fi ;;
      skill) if skill_in_use "$SW"; then continue; fi ;;
    esac
    if [ -z "$OVER" ]; then
      if suggest_overlap "$TOOL" "$CMD" "$FP"; then OVER=yes; else OVER=no; fi
    fi
    [ "$OVER" = no ] || exit 0
    speak
    exit 0
  done <<CANDS
$CAND
CANDS
fi

# THE INTRO (decision 22). A real row outranks it, and it stays due until spoken. Builtins first: on most calls it is not due.
[ -n "$INTRO" ] || exit 0
surface_can_load || exit 0
[ -f "$STATE/sessions.tsv" ] && [ ! -L "$STATE/sessions.tsv" ] || exit 0
_n=''; _at=''
while IFS="$TAB" read -r _a _b _rest; do
  case "$_a" in ''|*[!0-9]*) continue ;; esac
  case "$_b" in ''|*[!0-9]*) continue ;; esac
  _n="$_a"; _at="$_b"
done < "$STATE/sessions.tsv"
[ -n "$_n" ] && [ "$((_n - _at))" -ge 20 ] || exit 0
# Shadow never spends it: `spoke:` does not run there, so it would stay due and take every session's slot. No readable row reads as shadow.
CTL="${HARBOR_CONTEXT_CONTROLS:-}"
if [ -z "$CTL" ]; then
  for _c in "$HERE/../../bin/controls.tsv" "$HERE/../../standards/naming/controls.tsv"; do
    if [ -f "$_c" ]; then CTL="$_c"; break; fi
  done
fi
[ -n "$CTL" ] && [ -f "$CTL" ] || exit 0
[ "$(awk -F'\t' '$3 == "injection" && $12 == "suggest-tool" { print $2; exit }' "$CTL" 2>/dev/null)" = warn ] || exit 0
load "$INTRO"
if stopped "$ID"; then exit 0; fi
present "$REQ" || exit 0
_t="$(suggest_stop_tool)"
[ -n "$_t" ] || exit 0
[ "$(sh "$_t" status --json 2>/dev/null | jq -r '.intro_due // false' 2>/dev/null)" = true ] || exit 0
speak
exit 0
