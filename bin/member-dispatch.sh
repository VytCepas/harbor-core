#!/usr/bin/env sh
# member-dispatch.sh (harbor#1278) — the one managed PreToolUse entry on a member laptop: runs the guards, then decides the call once.
#   <hook json> | sh member-dispatch.sh                  the hook: a decision on stdout, or nothing when the call may go on
#   sh member-dispatch.sh --guard-table <install-file>   the guard table from floor_hooks in admission-install.sh, on stdout
#
# The table is bin/member-guards.tsv beside this script, kept in contracts/member-guards.tsv from --guard-table: one row per always-on PreToolUse row of
# floor_hooks in order, `matcher<TAB>argv` (a bare name is a file beside this script), then the member-only Read row and its read-deny rows. None is added at run time.
# Order of the verdict: integrity denies with no route, in shadow too; in shadow a fixed row still takes the very-high path, and default
# and hub rows and hub hooks are only recorded; a hub hook's deny stands; very-high is denied until hub-approval.sh says approved; high and medium ask, or deny where no
# person can answer; low runs. An approved call gets silence, never `allow`, so permission rules still apply (contracts/hub.md).
# FAIL CLOSED: anything that stops this script before it decides is a refusal, and no guard's text reaches the reader (M1, F9).
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -- "$HERE" && pwd)"

MSG_FAULT='The safety checks on this laptop could not finish, so this step was stopped. If it keeps happening, tell your admin.'
MSG_POLICY='The company safety settings on this laptop could not be read, so this step was stopped. Your admin needs to look at this laptop.'

# member_guard_table <install-file>: the rows of floor_hooks this entry stands in for. Opt-in rows (b6, stop) are not PreToolUse vetoes.
member_guard_table() {
  sed -n "/^floor_hooks() { cat <<'ROWS'/,/^ROWS\$/p" "$1" | awk -F';' '$1 == "PreToolUse" && $4 == "" { print $2 "\t" $3 }'
}
# member_read_rows <install-file>: a standalone install's Read(...) deny rows, which allowManagedPermissionRulesOnly drops here, read as lint D5 reads them, plus
# MEMBER_READ_ROWS, the hub token's store (bin/secret's ciphertext and, on Linux and WSL, its keys; libsecret's keyrings) that no standalone writer denies (harbor#1278).
# shellcheck disable=SC2088 # rows, not paths: admission-egress.sh reads the ~ as the home anchor
MEMBER_READ_ROWS='~/.local/share/secret/**
~/.local/share/keyrings/**'
member_read_rows() {
  # awk, not grep: this file sources library-admission.sh, whose rules want $FLOOR_GREP, and the generator runs before it is sourced.
  _mrr="$(awk '/^[[:space:]]*#/ { next } { while (match($0, /"Read\([^"]+\)"/)) { print substr($0, RSTART + 6, RLENGTH - 8); $0 = substr($0, RSTART + RLENGTH) } }' \
    "${1%/*}/deploy-harden.sh" "${1%/*}/admission-deny.sh")" || return 1
  [ -n "$_mrr" ] || return 1   # no standalone rows to carry is a broken generator, whatever this file adds
  printf '%s\n%s\n' "$_mrr" "$MEMBER_READ_ROWS" | LC_ALL=C sort -u
}

case "${1:-}" in
  --help|-h) sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --guard-table)
    . "$HERE/library-log.sh"
    log_init member-dispatch
    LOG_FD=2
    if [ ! -f "${2:-}" ]; then log_fail "--guard-table wants the path of admission-install.sh"; log_nofix "sh $0 --help"; log_end || :; exit 2; fi
    _rows="$(member_guard_table "$2")"
    if [ -z "$_rows" ]; then log_fail "no PreToolUse rows in floor_hooks of $2"; log_nofix "bin/admission-install.sh, floor_hooks"; log_end || :; exit 1; fi
    _reads="$(member_read_rows "$2" 2>/dev/null)" || _reads=""
    if [ -z "$_reads" ]; then log_fail "no Read deny rows beside $2"; log_nofix "bin/deploy-harden.sh and bin/admission-deny.sh"; log_end || :; exit 1; fi
    printf '%s\nRead\tadmission-hook.sh admission-egress.sh\n' "$_rows"
    printf '%s\n' "$_reads" | awk '{ print "read-deny\t" $0 }'
    exit 0 ;;
esac

# set -e under bash 3.2 hands an EXIT trap $?=0, so the trap reads this flag, not the exit status (harbor#810).
WORK=""; DECIDED=0
_finish() {
  [ -z "$WORK" ] || rm -rf "$WORK"
  if [ "$DECIDED" != 1 ]; then printf '%s\n' "$MSG_FAULT" >&2; trap - EXIT; exit 2; fi
}
trap _finish EXIT
trap 'exit 1' HUP INT TERM

. "$HERE/library-hub.sh"
hub_env_clean
[ -f "$HERE/harbor-member-mode" ]
. "$HERE/library-admission.sh"

TAB="$(printf '\t')"
JQ="$FLOOR_JQ"
TABLE="$HERE/member-guards.tsv"
STATE="$(hub_state_dir)"
# W3: if a hook's `ask` doesn't render in a WSL session, set this to deny and below very-high becomes deny-and-retry.
ASK_VERDICT=ask

floor_read_stdin
printf '%s' "$FLOOR_IN" | "$JQ" -e 'type == "object" and (.tool_name | type == "string" and length > 0)' >/dev/null
TOOL="$(floor_field '.tool_name')"
SESSION="$(floor_field '.session_id')"
CALL_ID="$(floor_field '.tool_use_id')"
case "$CALL_ID" in ''|*[!A-Za-z0-9_-]*) CALL_ID="" ;; esac
[ "${#CALL_ID}" -le 128 ] || CALL_ID=""

WORK="$(mktemp -d "${TMPDIR:-/tmp}/member-dispatch.XXXXXX")"
PAYLOAD="$WORK/payload.json"; RECORDS="$WORK/records"; FIRED="$WORK/fired"
printf '%s' "$FLOOR_IN" > "$PAYLOAD"
: > "$RECORDS"; : > "$FIRED"

event() { sh "$HERE/hub-events.sh" record "$@" </dev/null >/dev/null 2>&1 || :; }

# activity <verdict> (D9): one count per call by tool, verb class and this script's verdict, folded per day by the sender (D4).
# The tool is mapped onto the vocabulary (an mcp__ name to mcp) and the class is floor_obs_class's literal: no byte of the call leaves.
VOCAB="$HERE/hub-vocabulary.tsv"; [ -f "$VOCAB" ] || VOCAB="$HERE/../contracts/hub-vocabulary.tsv"
activity() {
  _at="$TOOL"
  case "$_at" in ''|*[!A-Za-z0-9_]*) _at=other ;; esac
  if ! awk -F'\t' -v t="$_at" '$1 == "tool" && $2 == t { f = 1 } END { exit !f }' "$VOCAB" 2>/dev/null; then
    case "$_at" in mcp__*) _at=mcp ;; *) _at=other ;; esac
  fi
  _ac=na
  if [ "$TOOL" = Bash ]; then _xo=other; floor_obs_class "$(floor_field '.tool_input.command')" 2>/dev/null || :; _ac="$_xo"; fi
  event activity tool="$_at" verb_class="$_ac" verdict="$1" count=1
}

decide() { # <decision> <reason>: the only output of this script
  activity "$1" || :
  "$JQ" -cn --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}'
  DECIDED=1; exit 0
}
stay_silent() { activity "${1:-allow}" || :; DECIDED=1; exit 0; }   # [verdict]: allow, or shadow when a rule fired and was only recorded

# guard_target <guard>: the closed word a board request shows for a core rule (contracts/hub-vocabulary.tsv).
guard_target() {
  case "$1" in
    bash) printf command ;; egress) printf credential ;; cloud) printf cloud ;;
    destroy|selfedit|deliverables) printf file ;; govern) printf repo ;; *) printf other ;;
  esac
}

# unreadable <file>: 0 iff stdout opens as JSON and isn't one JSON value. Claude Code counts that a failure under onFailure block, so this can't be weaker (harbor#1278).
unreadable() {
  [ "$(sed -n '/[^[:space:]]/{s/^[[:space:]]*//;p;q;}' "$1" | cut -c1)" = '{' ] || return 1
  ! "$JQ" -es 'length == 1' "$1" >/dev/null 2>&1
}

# run_guard <argv>: one table row. A guard reports through the record file; one that can't speaks JSON, and its deny or ask is
# filed under its control here. Its stderr is dropped: on this box it would teach the reader the way round (M1).
run_guard() { # <argv> <row number>
  _gout="$WORK/out.$2"; _grec="$WORK/rec.$2"; _gname=""; _gn=0
  set -f; # shellcheck disable=SC2086 # the row is words from a table only an admin can write
  set -- $1; set +f
  _gc=$#
  while [ "$_gn" -lt "$_gc" ]; do
    _gw="$1"; shift; _gn=$((_gn + 1))
    case "$_gw" in
      -*) set -- "$@" "$_gw" ;;
      */*) return 1 ;;
      *) set -- "$@" "$HERE/$_gw"; _gname="$_gw" ;;
    esac
  done
  [ -f "$1" ] && [ -f "${_gname:+$HERE/$_gname}" ] || return 1
  HARBOR_ADMISSION_MEMBER_RECORDS="$_grec" sh "$@" < "$PAYLOAD" > "$_gout" 2>/dev/null || return 1
  [ -s "$_gout" ] || return 0
  if unreadable "$_gout"; then return 1; fi
  case "$("$JQ" -r '.hookSpecificOutput.permissionDecision // empty' "$_gout" 2>/dev/null || :)" in
    deny|ask)
      case "$_gname" in
        govern-hook.sh) _gc=admission.merge-backstop-box; _gg=govern ;;
        *) _gc="admission.${_gname%.sh}"; _gg=other ;;
      esac
      printf 'rule\t%s\t-\t%s\n' "$_gg" "$_gc" >> "$_grec" ;;
  esac
}

run_guards() {
  [ -s "$TABLE" ]
  TOOL="$TOOL" awk -F'\t' 'BEGIN { t = ENVIRON["TOOL"] } /^#/ { next } t ~ ("^(" $1 ")$") { print $2 }' "$TABLE" > "$WORK/rows"
  # At once: in series a clean call waited for each guard in turn, a third longer (harbor#1278). The records join in table order, so top_row doesn't hang on which guard finished first.
  # A row counts only with its ok mark: a guard that died is a fault, not a pass.
  _rn=0
  while IFS= read -r _row; do
    _rn=$((_rn + 1)); : > "$WORK/rec.$_rn"
    ( run_guard "$_row" "$_rn" && : > "$WORK/ok.$_rn" ) &
  done < "$WORK/rows"
  wait
  _ri=0
  while [ "$_ri" -lt "$_rn" ]; do
    _ri=$((_ri + 1))
    [ -e "$WORK/ok.$_ri" ] || decide deny "$MSG_FAULT"
    cat "$WORK/rec.$_ri" >> "$RECORDS"
  done
}

# fired rows: id TAB tier TAB set TAB target TAB label. A lookup that gives no usable line is integrity: nothing was decided, so nothing may pass.
add_core_rows() {
  awk -F'\t' '$1 == "rule" && !seen[$4]++ { print $2 "\t" $4 }' "$RECORDS" > "$WORK/controls"
  while IFS="$TAB" read -r _cg _cc; do
    _line="$(sh "$HERE/hub-tier.sh" lookup "$_cc" 2>/dev/null)" || _line=""
    _ct=""; _cs=""; _cl=""
    IFS="$TAB" read -r _ct _cs _cl <<EOF
$_line
EOF
    case "$_ct:$_cs" in
      very-high:fixed|very-high:integrity|very-high:default|high:default|medium:default|low:default) ;;
      *) _ct=very-high; _cs=integrity; _cl="" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$_cc" "$_ct" "$_cs" "$(guard_target "$_cg")" "${_cl:-A safety check}" >> "$FIRED"
  done < "$WORK/controls"
}

add_hub_rows() {
  sh "$HERE/hub-tier.sh" rules "$PAYLOAD" > "$WORK/hub" 2>/dev/null
  while IFS="$TAB" read -r _hi _ht _hg _hl; do
    case "$_ht" in very-high|high|medium|low) ;; *) decide deny "$MSG_POLICY" ;; esac
    printf '%s\t%s\thub\t%s\t%s\n' "$_hi" "$_ht" "$_hg" "$_hl" >> "$FIRED"
  done < "$WORK/hub"
}

# Hub hooks run last and can only add: deny or ask. Allow and updatedInput are logged and dropped (F14, F22). A hook that doesn't match
# its signed digest, or dies, is a deny: the hub wanted it to judge this call and it didn't.
HOOK_VERDICT=""
run_hub_hooks() {
  sh "$HERE/hub-tier.sh" hooks > "$WORK/hooks" 2>/dev/null
  while IFS="$TAB" read -r _pk _pp _ps; do
    _hf="$(sh "$HERE/hub-sync.sh" hook "$_pk" "$_pp" 2>/dev/null)" || _hf=""
    if [ -z "$_hf" ]; then
      event check check=hub-hook-digest outcome=failed
      HOOK_VERDICT=deny; continue
    fi
    _hrc=0; sh "$_hf" < "$PAYLOAD" > "$WORK/hook.out" 2>/dev/null || _hrc=$?
    case "$_hrc" in
      0) ;;
      2) HOOK_VERDICT=deny; continue ;;
      *) event check check=hub-hook-run outcome=failed; HOOK_VERDICT=deny; continue ;;
    esac
    [ -s "$WORK/hook.out" ] || continue
    if unreadable "$WORK/hook.out"; then event check check=hub-hook-run outcome=failed; HOOK_VERDICT=deny; continue; fi
    _hv="$("$JQ" -r '(.hookSpecificOutput.permissionDecision // .decision // "") + "\t" + (if (.hookSpecificOutput.updatedInput // .updatedInput) != null then "rewrite" else "-" end)' "$WORK/hook.out" 2>/dev/null || :)"
    case "$_hv" in *"${TAB}rewrite") event check check=hub-hook-rewrite outcome=failed ;; esac
    case "${_hv%%"$TAB"*}" in
      deny|block) HOOK_VERDICT=deny ;;
      ask) [ "$HOOK_VERDICT" = deny ] || HOOK_VERDICT=ask ;;
      allow|approve) event check check=hub-hook-allow outcome=failed ;;
    esac
  done < "$WORK/hooks"
}

in_set() { awk -F'\t' -v s="$1" '$3 == s { f = 1 } END { exit !f }' "$FIRED"; }
# top_row: the first row of the highest tier fired, so a later very-high is never hidden by an earlier high.
top_row() {
  awk -F'\t' 'BEGIN { r["low"] = 1; r["medium"] = 2; r["high"] = 3; r["very-high"] = 4 }
    r[$2] > best { best = r[$2]; row = $0 } END { if (row != "") print row }' "$FIRED"
}

# open_record <asked 0|1> <request-id|->: what member-post.sh closes, keyed on tool_use_id (F21). Best effort: a call is never stopped for it.
open_record() {
  [ -n "$CALL_ID" ] || return 0
  mkdir -p "$STATE/open" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$SESSION" "$1" "$ID" "$TIER" "$TARGET" "$2" > "$STATE/open/$CALL_ID" 2>/dev/null || :
}

ask_or_deny() { # <label>
  if floor_no_human || [ "$ASK_VERDICT" != ask ]; then
    event refusal rule="$ID" tier="$TIER" target="$TARGET" count=1
    decide deny "This step needs a person to say yes, and nobody can answer here, so it was stopped: $1. Try it from the main conversation, where you can be asked."
  fi
  open_record 1 "${RID:--}"
  decide ask "$1. Do you want this to go ahead?"
}

# approval_or_deny: the one consultation. Status is read-only; the approval is spent at PostToolUse, once the call has really run (F8).
RID=""
approval_or_deny() { # <label>
  # Each part on its own line: a failed inner substitution would pass set -e and give every call the same id.
  [ -n "${HARBOR_MEMBER_LOGIN:-}" ]
  _canon="$(hub_canon "$FLOOR_IN" "$HARBOR_MEMBER_LOGIN")"; _salt="$(hub_salt)"
  [ -n "$_canon" ] && [ -n "$_salt" ]
  RID="$(hub_request_id "$_canon" "$_salt")"
  _arc=0; sh "$HERE/hub-approval.sh" status "$RID" </dev/null >/dev/null 2>&1 || _arc=$?
  if [ "$_arc" = 0 ]; then
    event request id="$RID" rule="$ID" tier="$TIER" target="$TARGET" outcome=approved
    [ "$HOOK_VERDICT" != ask ] || ask_or_deny "$1"
    open_record 0 "$RID"
    stay_silent
  fi
  event refusal rule="$ID" tier="$TIER" target="$TARGET" count=1
  _frc=0; sh "$HERE/hub-approval.sh" file "$RID" "$ID" "$TIER" "$TARGET" "$1" </dev/null >/dev/null 2>&1 || _frc=$?
  if [ "$_frc" = 0 ]; then
    if [ ! -e "$STATE/opened/$RID" ]; then
      mkdir -p "$STATE/opened" 2>/dev/null && : > "$STATE/opened/$RID" 2>/dev/null || :
      event request id="$RID" rule="$ID" tier="$TIER" target="$TARGET" outcome=opened
    fi
    decide deny "Waiting for an admin to approve this exact action: $1. Your admin has been told (request $RID). You'll be told here when it arrives. Don't change the command: a changed call needs a new approval."
  fi
  decide deny "This action needs an admin's approval, and your admin could not be told just now: $1 (request $RID). Try again later. Don't change the command: a changed call needs a new approval."
}

MODE="$(sh "$HERE/hub-tier.sh" mode 2>/dev/null)" || MODE=bad
case "$MODE" in
  shadow|enforce) ;;
  *) event check check=hub-policy outcome=failed; decide deny "$MSG_POLICY" ;;
esac

run_guards
# A support session is a person's act, so this row is integrity: no approval reaches it (contracts/hub.md, Remote support).
sh "$HERE/member-support-guard.sh" < "$PAYLOAD" >> "$RECORDS" 2>/dev/null || decide deny "$MSG_FAULT"
add_core_rows

if in_set integrity; then
  IFS="$TAB" read -r ID TIER _set TARGET LABEL <<EOF
$(awk -F'\t' '$3 == "integrity" { print; exit }' "$FIRED")
EOF
  event refusal rule="$ID" tier="$TIER" target="$TARGET" count=1
  decide deny "This step was stopped: $LABEL. That is never allowed, and no approval can change it."
fi

add_hub_rows
run_hub_hooks

ID=""; TIER=""; TARGET=""; LABEL=""
if [ -s "$FIRED" ]; then
  IFS="$TAB" read -r ID TIER _set TARGET LABEL <<EOF
$(top_row)
EOF
fi

# Shadow records default and hub rows only: a fixed row takes the very-high path in both modes (operator, 2026-11-08: "Always enforce credentials").
if [ "$MODE" = shadow ]; then
  [ -z "$HOOK_VERDICT" ] || event refusal rule=hub-hook tier=high target=other count=1
  HOOK_VERDICT=""
  if in_set fixed; then
    IFS="$TAB" read -r ID TIER _set TARGET LABEL <<EOF
$(awk -F'\t' '$3 == "fixed" { print; exit }' "$FIRED")
EOF
    approval_or_deny "$LABEL"
  fi
  [ -z "$ID" ] || { event refusal rule="$ID" tier="$TIER" target="$TARGET" count=1; stay_silent shadow; }
  stay_silent
fi

if [ "$HOOK_VERDICT" = deny ]; then
  event refusal rule=hub-hook tier="${TIER:-high}" target="${TARGET:-other}" count=1
  decide deny "Your company's own check stopped this step. If you need it, ask your admin."
fi

case "$TIER" in
  very-high) approval_or_deny "$LABEL" ;;
  high|medium) ask_or_deny "$LABEL" ;;
esac
if [ "$HOOK_VERDICT" = ask ]; then
  ID=hub-hook; TIER=high; TARGET=other
  ask_or_deny "Your company's own check wants you to confirm this step"
fi
[ -z "$ID" ] || event check check="$ID" outcome=passed
stay_silent
exit 0
