#!/usr/bin/env sh
# suggest-subject.sh (harbor#1485): the reading of a suggest-tool table, and the one string a row's recogniser and quiet run on.
# Sourced, never run, by suggest-tool.sh and bin/eval-suggest-replay.sh, so the replay proves what the live rule does.
# The caller sets SUGGEST_HERE to the directory of this file.
#
# THE SUBJECT
#   Bash    <basename of SEGC> <SEGA...>, one line per executed segment, from the floor's parser
#   others  <tool> <lowercase ext or -> <place>; place is config, deliverables, project or scratch, and is never shown
# A heredoc body and a `command -v` lookup run nothing, so they make no subject (skill-first-use.sh does the same).

SUGGEST_GREP=/usr/bin/grep; [ -x "$SUGGEST_GREP" ] || SUGGEST_GREP=grep
SUGGEST_OVERLAP='ci-wait-on-the-bus.sh suite-run-through-runner.sh unbounded-wait-loop.sh long-wait-process-exists.sh default-way-route.sh'

# <tool, empty for every row> <core table> <table>... -> each good row of the tables, in order. One awk, and the cost on every tool
# call, so a bad row is dropped here and never silences the rest. Trust is read from the file: a row outside the core table, and any
# mod row, leaves here as safe=no whatever its cells say. An intro row always passes, because it answers to no tool.
suggest_rows() {
  _sr_t="$1"; _sr_c="$2"; shift 2
  [ "$#" -gt 0 ] || return 0
  LC_ALL=C SUGGEST_T="$_sr_t" SUGGEST_CORE="$_sr_c" awk -F'\t' '
    BEGIN { OFS = "\t"; t = ENVIRON["SUGGEST_T"]; core = ENVIRON["SUGGEST_CORE"] }
    /^#/ || $1 == "id" || NF != 12 { next }
    { for (i = 1; i <= 12; i++) if ($i == "") next }
    length($1) > 27 || $1 !~ /^[a-z0-9][a-z0-9-]*$/ { next }
    $2 !~ /^(verb|tool|skill|mod|intro)$/ || $9 !~ /^(yes|no)$/ { next }
    $7 == "-" || $7 ~ /[`$]/ || $7 ~ /^HARBOR-/ { next }
    $8 != "-" && $8 ~ /[^A-Za-z0-9._:\/@ -]/ { next }
    $2 == "intro" { if ($3 == "-" && $5 == "-") { $9 = "no"; print } next }
    $3 == "-" || $5 == "-" { next }
    t != "" && index("|" $3 "|", "|" t "|") == 0 { next }
    $3 == "Bash" { if ($4 == "-" || $4 ~ /[^A-Za-z0-9._\/:@+ -]/ || $5 !~ /^\^/) next }
    $3 != "Bash" { if ($4 != "-" || index("|" $3 "|", "|Bash|")) next }
    { if (FILENAME != core || $2 == "mod") $9 = "no"; print }' "$@" 2>/dev/null
}

# Load the floor's parser. ~70 ms, so the rule reaches this only after a row's word was found in the command; the replay calls it once.
suggest_parser_load() {
  [ -z "${SUGGEST_PARSER:-}" ] || return 0
  for _sp in "$SUGGEST_HERE/../bin/library-admission.sh" "$SUGGEST_HERE/../../bin/library-admission.sh"; do
    if [ -f "$_sp" ]; then
      # shellcheck disable=SC2034 # DIR: read by library-admission.sh
      DIR="${_sp%/*}"; . "$_sp" >/dev/null 2>&1
      SUGGEST_PARSER=1; return 0
    fi
  done
  return 1
}

suggest_place() { # <path> -> config | deliverables | project | scratch
  _sp_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _sp_cfg="${_sp_cfg%/}"
  case "$1" in
    "$_sp_cfg"/*) echo config; return ;;
    "$HOME"/Deliverables/*) echo deliverables; return ;;
    "${CLAUDE_PROJECT_DIR:-/nonexistent}"/*|"$HOME"/*) echo project; return ;;
    "${TMPDIR:-/nonexistent}"/*|/tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) echo scratch; return ;;
  esac
  echo project
}

suggest_subject() { # <tool> <command, or the path a file tool names> -> the subjects, one per line
  if [ "$1" != Bash ]; then
    _ss_b="${2##*/}"; _ss_e=-
    case "$_ss_b" in ?*.?*) _ss_e="$(printf '%s' "${_ss_b##*.}" | tr '[:upper:]' '[:lower:]')" ;; esac
    case "$_ss_e" in *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) _ss_e=- ;; esac
    printf '%s %s %s\n' "$1" "$_ss_e" "$(suggest_place "$2")"
    return 0
  fi
  suggest_parser_load || return 0
  floor_seg_load "$2"
  _ss_l=0; printf '%s' "$2" | "$SUGGEST_GREP" -qE 'command[[:space:]]+(-[pvV]+[[:space:]]+)*-[pvV]*[vV]' && _ss_l=1
  printf '%s\n' "$FLOOR_SEGS" | awk -v lookup="$_ss_l" '
    function sid(s) { return substr(s, 1, index(s, ":") - 1) + 0 }
    function val(s) { return substr(s, index(s, ":") + 1) }
    /^SEGW:/ { s = substr($0, 6); W[sid(s)] = val(s) }
    /^SEGC:/ { s = substr($0, 6); i = sid(s); C[i] = val(s); if (i > M) M = i }
    /^SEGA:/ { s = substr($0, 6); i = sid(s); A[i] = A[i] " " val(s) }
    /^SEGR:/ { s = substr($0, 6); i = sid(s); r = val(s)
               if (substr(r, 1, 3) == "<<:") { d = substr(r, 4); sub(/^-/, "", d); H[i] = d } }
    END { delim = ""
          for (i = 1; i <= M; i++) { if (!(i in C)) continue
            if (delim != "") { if (C[i] == delim) delim = ""; continue }
            if (i in H) delim = H[i]
            if (lookup && W[i] == "command") continue
            w = C[i]; sub(/.*\//, "", w); print w A[i] } }'
}

# <tool> <recogniser> <quiet> <subjects>: 0 when a subject matches and is not quiet. Each ERE runs alone, so a bad one loses only its
# row. A Bash recogniser is anchored here whatever it says: `^a|b` must not let `b` match inside an argument.
suggest_row_hits() {
  _sh_r="$2"
  [ "$1" != Bash ] || _sh_r="^(${_sh_r#^})"
  if [ "$3" = - ]; then
    printf '%s\n' "$4" | "$SUGGEST_GREP" -qE -- "$_sh_r" 2>/dev/null
  else
    printf '%s\n' "$4" | "$SUGGEST_GREP" -E -- "$_sh_r" 2>/dev/null | "$SUGGEST_GREP" -qvE -- "$3" 2>/dev/null
  fi
}

# <tool> <command> <path>: 0 when another pack would speak on this call, whether or not its own once-key has been spent. The scripts
# named in SUGGEST_OVERLAP read only. Run only after a row matched.
suggest_overlap() {
  _so_p="$(jq -cn --arg t "$1" --arg c "$2" --arg f "$3" \
    '{hook_event_name:"PreToolUse",tool_name:$t,tool_input:(if $t == "Bash" then {command:$c} else {file_path:$f} end)}' 2>/dev/null)" || return 1
  for _so_s in $SUGGEST_OVERLAP; do
    [ -f "$SUGGEST_HERE/$_so_s" ] || continue
    if [ -n "$(printf '%s' "$_so_p" | sh "$SUGGEST_HERE/$_so_s" 2>/dev/null)" ]; then return 0; fi
  done
  return 1
}

suggest_stop_tool() { # -> the stop tool's path beside the installed packs, or nothing
  _st_d="$(CDPATH='' cd -- "$SUGGEST_HERE/../../bin" 2>/dev/null && pwd)" || return 0
  [ ! -f "$_st_d/status-suggest.sh" ] || printf '%s/status-suggest.sh' "$_st_d"
}
