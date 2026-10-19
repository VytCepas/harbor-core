#!/usr/bin/env sh
# UNINSTALL (harbor#3 follow-on, #766) — remove the Helm floor from a config dir (the install standard, harbor#765).
#   sh floor-uninstall.sh (--live | --dir PATH)           DRY RUN: what would change, nothing written
#   sh floor-uninstall.sh --apply (--live | --dir PATH)   write; every removed file is MOVED into the run's backup
#   --accept-loss   accepted, and changes nothing: nothing here is lost, since every removed file is kept
#
# WHY THIS EXISTS: the QA review (QA-PLAN.md, R7) found there was no way out.
# An operator who wanted the floor gone had to hand-edit settings.json — which
# B1's own Edit(~/.claude/settings.json) deny and B2's self-edit guard both
# forbid. A control you cannot remove is not a control the operator owns.
#
# WHAT IT REMOVES IS READ FROM floor-install.sh, never listed here (harbor#766):
# its GUARDS payload, the scripts in its wiring table (floor_hooks), and every
# hook that names one of them or matches a table row. This file kept its own
# copies and they drifted: four hooks stayed wired to a deleted guard-lib.sh.
#
# Kept: what runtime-install also ships and wires, while it is on this box; the
# recovery tooling; the SEC-0 read-deny set and the B1 deny entries; mode locks,
# plugins, skills, MEMORY, and every foreign hook.
#
# NOTE the ordering: B6 is unwired FIRST. It is fail-closed, so removing the
# guards it checks while it is still armed would block the next session.
set -eu
SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/log-lib.sh"
. "$SRC/install-lib.sh"
log_init floor-uninstall
# THE INSTALL STANDARD'S INTERFACE (harbor#766, #765), from install-lib (lint D7): no positional
# target — the old loop let the LAST bare word win, so `<sandbox> --live --apply` stripped live —
# physical paths (P11-01: `floor-uninstall.sh "$LIVE/" --apply` once stripped every hook), and a
# CLAUDE_CONFIG_DIR that disagrees with the target is a usage error, never a redirect.
il_parse "$@"
il_target
DIR="$IL_TARGET"
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq is required, and is not on PATH"
  log_fix "$(pkg_hint jq)"
  log_end; exit 1
fi
S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S, so there is no floor wiring here to remove"
  log_nofix "the --dir or --live target given"
  log_end; exit 1
fi

# ── what the floor owns, read from its installer ─────────────────────────────
FI="$SRC/floor-install.sh"
GUARDS="$(sed -n "s/^GUARDS='\(.*\)'/\1/p" "$FI" 2>/dev/null | head -1)"
RECOVERY="$(sed -n "s/^RECOVERY='\(.*\)'/\1/p" "$FI" 2>/dev/null | head -1)"
EVENTS="$(sed -n "s/^EVENTS='\(.*\)'/\1/p" "$FI" 2>/dev/null | head -1)"  # harbor#1043: the producers and their bus
GATES="$(sed -n "s/^GATES='\(.*\)'/\1/p" "$FI" 2>/dev/null | head -1)"  # harbor#1018: the approval gate's tools
ROWS="$(awk '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit } f && !/^#/ && /;/' "$FI" 2>/dev/null)"
RT_FILES="$(sed -n 's/^FILES="\(.*\)"/\1/p' "$SRC/runtime-install.sh" 2>/dev/null | head -1)"
# An empty list strips nothing and reports success, so an unreadable one refuses.
if [ -z "$GUARDS" ] || [ -z "$ROWS" ] || [ -z "$RT_FILES" ]; then
  il_refuse "could not read the floor's payload and wiring from $FI (or runtime-install's payload beside it), so nothing would be removed" \
    "sh ~/port/harbor/bin/floor-uninstall.sh$( [ "$IL_APPLY" -eq 1 ] && printf ' --apply' ) $(il_spell)"
  log_end; exit 1
fi
PAYLOAD=""  # every file floor-install copies that a hook can run: GUARDS plus the table's scripts
for _f in $GUARDS $EVENTS $GATES $(printf '%s\n' "$ROWS" | cut -d';' -f3); do
  case "$_f" in -*) continue ;; esac
  case " $PAYLOAD " in *" $_f "*) ;; *) PAYLOAD="${PAYLOAD:+$PAYLOAD }$_f" ;; esac
done
# SHARED OWNERSHIP. runtime-install ships guard-lib.sh and context-resolve.sh too,
# and its own hooks (memory-harvest, context-resolve at SessionStart) load them, so
# removing them wherever the runtime is installed breaks hooks this tool never
# wired. Present = its stamp, or a file only it ships.
RT_HERE=""
if [ -f "$DIR/.helm-install-stamp" ] && grep -q '^runtime-install ' "$DIR/.helm-install-stamp"; then
  RT_HERE="its install stamp"
else
  for _f in $RT_FILES; do
    case " $PAYLOAD $RECOVERY " in *" $_f "*) continue ;; esac
    if [ -f "$DIR/bin/$_f" ]; then RT_HERE="bin/$_f"; break; fi
  done
fi
SHARED=""; DEL=""
for _f in $PAYLOAD; do
  case " $RT_FILES " in
    *" $_f "*) if [ -n "$RT_HERE" ]; then SHARED="${SHARED:+$SHARED }$_f"; continue; fi ;;
  esac
  DEL="${DEL:+$DEL }$_f"
done
STATE='.helm-pins .helm-floor-teeth .helm-instructions.sha256'

# ── ONE predicate decides both the listing and the strip ─────────────────────
# A hook is the floor's when its command names a file this run deletes, or when
# it matches a table row (by event and argv basenames) that is not co-owned by an
# installer still on the box.
_rows_json() {
  printf '%s\n' "$ROWS" | while IFS=';' read -r _ev _m _argv _opt _co; do
    if [ -n "$_co" ] && [ -n "$RT_HERE" ]; then continue; fi
    printf '%s\n' "$_argv" | jq -Rc --arg ev "$_ev" '{ev: $ev, argv: (["sh"] + [splits(" +")])}'
  done | jq -sc .
}
ROWS_JSON="$(_rows_json)"
DEL_JSON="$(printf '%s\n' $DEL | jq -Rsc 'split("\n") | map(select(length > 0))')"
JQ_DEFS='
  def names: (. // "") | gsub("[\"'"'"']"; "") | [splits("[[:space:]]+")]
             | map(select(length > 0) | sub("^.*/"; ""));
  def floor_hook($ev): (.command | names) as $n
    | any($n[]; IN($del[])) or any($rows[]; .ev == $ev and .argv == $n);
  def arr: if type == "array" then . else [] end;
  def gate_rule: type == "string" and ((startswith("Bash(" + $gdir + "/bin/gate-") or startswith("Bash(" + $gdir + "/bin/deploy-fleet.sh ")) or IN($gv[]));'
# The git-verbs rules floor-deny derived (harbor#1291), read from the same register by the same reader. An identical
# rule the operator added by hand cannot be told apart, so it goes too; the dry run lists every one first.
GV_JSON="$( { il_git_verbs allow; il_git_verbs ask; } | sed -n 's/^OK	//p' | jq -Rsc 'split("\n") | map(select(length > 0) | "Bash(\(.))")')"
_floor_jq() { jq -r --argjson del "$DEL_JSON" --argjson rows "$ROWS_JSON" --argjson gv "$GV_JSON" --arg gdir "$DIR" "$JQ_DEFS $1" "$2"; }
# The approval gate's ask and allow rules (harbor#1018) name files this removes, so they go with them, and so do the
# git-verbs rules floor-deny added; an ask list left empty goes too, because the install created it.
GATE_RULES_JQ='[(.permissions.ask // [] | arr | .[]), (.permissions.allow // [] | arr | .[]) | select(gate_rule)] | .[]'
GATE_STRIP_JQ='if (.permissions | type) == "object" then
    (if (.permissions.ask | type) == "array" then .permissions.ask |= map(select(gate_rule | not)) else . end)
    | (if (.permissions.allow | type) == "array" then .permissions.allow |= map(select(gate_rule | not)) else . end)
    | (if .permissions.ask == [] then del(.permissions.ask) else . end)
  else . end'
LIST_JQ='.hooks | if type == "object" then to_entries[] else empty end
  | .key as $ev | .value | arr | .[] | .hooks | arr | .[]
  | select(floor_hook($ev)) | "\($ev): \(.command)"'
STRIP_JQ='if (.hooks | type) == "object" then .hooks |= with_entries(.key as $ev
    | if (.value | type) == "array" and (.value | length) > 0
      then .value |= map(if (.hooks | type) == "array" and (.hooks | length) > 0
             then (.hooks |= map(select(floor_hook($ev) | not))) | select((.hooks | length) > 0)
             else . end)
           | select((.value | length) > 0)
      else . end)
  else . end'
if ! REMOVE="$(_floor_jq "$LIST_JQ" "$S")"; then
  log_fail "could not parse $S as settings JSON"
  log_nofix "jq . $S shows where it breaks"
  log_end; exit 1
fi

if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $DIR"; else log_head "plan for $DIR (dry run: nothing is written)"; fi
if [ -n "$REMOVE" ]; then
  while IFS= read -r _l; do log_note "hook to remove: $_l"; done <<EOF
$REMOVE
EOF
else log_ok "no floor hook is wired"; fi
_floor_jq "$GATE_RULES_JQ" "$S" 2>/dev/null | while IFS= read -r _l; do log_note "approval-gate or git-verbs rule to remove: $_l"; done
_n=0
for _f in $DEL; do if [ -e "$DIR/bin/$_f" ]; then log_note "floor file to remove: bin/$_f"; _n=$((_n+1)); fi; done
for _f in $STATE; do if [ -e "$DIR/$_f" ]; then log_note "floor file to remove: $_f"; _n=$((_n+1)); fi; done
[ "$_n" -gt 0 ] || log_ok "no floor file is present"
# A moved file's .harbor-manifest rows go with it (harbor#815, install standard §3). Only a path that
# has rows is dropped, so a box installed before the manifest is never handed one.
_mf_rows_of() { # <relpath> → "<relpath> (<installer>)" per row il_manifest_drop removes for it
  il_mf_rows "$DIR" | awk -F'\t' -v p="$1" '$1 == p || index($1, p "/") == 1 { print $1 " (" $3 ")" }'
}
_nl='
'; _mfl=""
for _f in $DEL; do if [ -e "$DIR/bin/$_f" ]; then _mfl="$_mfl$(_mf_rows_of "bin/$_f")$_nl"; fi; done
for _f in $STATE; do if [ -e "$DIR/$_f" ]; then _mfl="$_mfl$(_mf_rows_of "$_f")$_nl"; fi; done
while IFS= read -r _l; do [ -z "$_l" ] || log_note ".harbor-manifest row to drop: $_l"; done <<EOF
$_mfl
EOF
if [ -n "$SHARED" ]; then
  log_skip "kept, because runtime-install ships them too and is on this box ($RT_HERE): $SHARED — and the hooks it wires to them"
fi
log_skip "kept: recovery tooling ($(echo $RECOVERY | sed 's/ /, /g')) — no hook runs it, and it is the way back"
log_skip "kept: the SEC-0 read-deny set and the B1 deny entries, mode locks, plugins, skills, MEMORY, and every foreign hook"

if [ "$IL_APPLY" -eq 0 ]; then
  # harbor#95 — a hint its own gate refuses is a hint that teaches the operator to remove the gate.
  # A live removal goes through deploy, the one live entry (install standard §4, harbor#808).
  if [ "$IL_LIVE" -eq 1 ] && [ -f "$SRC/deploy.sh" ]; then il_next --deploy-does "sh '$SRC/deploy.sh' --apply --only floor --uninstall --live"
  else il_next "$(il_cmd --apply)"; fi
  log_end; exit $?
fi

# ── apply: back up, strip, verify, then move the files out ───────────────────
il_backup "$S" || { log_end; exit 1; }
BK="$IL_BK"
mkdir -p "$BK/bin"
_tmp="$S.tmp.$$"
if ! _floor_jq "$STRIP_JQ | $GATE_STRIP_JQ" "$S" >"$_tmp" 2>/dev/null || ! jq -e . "$_tmp" >/dev/null 2>&1; then
  rm -f "$_tmp"
  log_fail "the strip produced invalid JSON for $S — it is unchanged"
  log_nofix "harbor#766 (floor-uninstall's STRIP_JQ)"
  log_end; exit 1
fi
if [ -n "$(_floor_jq "$LIST_JQ" "$_tmp")" ]; then
  rm -f "$_tmp"
  log_fail "the strip left floor hooks wired in $S — it is unchanged"
  log_nofix "harbor#766 (floor-uninstall's STRIP_JQ and LIST_JQ disagree)"
  log_end; exit 1
fi
il_write_json "$(cat "$_tmp")" "$S" || { rm -f "$_tmp"; log_end; exit 1; }
rm -f "$_tmp"
log_ok "floor hooks unwired from $S"
_failed=""; _moved=""
for _f in $DEL; do
  if [ -e "$DIR/bin/$_f" ]; then
    if mv "$DIR/bin/$_f" "$BK/bin/$_f"; then _moved="$_moved bin/$_f"; else _failed="$_failed bin/$_f"; fi
  fi
done
for _f in $STATE; do
  if [ -e "$DIR/$_f" ]; then
    if mv "$DIR/$_f" "$BK/$_f"; then _moved="$_moved $_f"; else _failed="$_failed $_f"; fi
  fi
done
# The rows of exactly what moved, written before any failure exits (harbor#815): a partial run's
# manifest still names only files that are there. il_manifest_write backs it up into $BK first.
_nd=0; _mf_ok=1
for _p in $_moved; do
  _r="$(_mf_rows_of "$_p")"
  if [ -n "$_r" ]; then il_manifest_drop "$_p"; _nd=$((_nd + $(printf '%s\n' "$_r" | grep -c .))); fi
done
il_manifest_write || _mf_ok=0
if [ "$_mf_ok" -eq 1 ] && [ "$_nd" -gt 0 ]; then log_ok "dropped $_nd .harbor-manifest row(s) of the files moved out; the manifest as it was is in $BK"; fi
if [ -n "$_failed" ]; then
  log_fail "could not move:$_failed — the hooks are already unwired"
  log_fix "$(il_cmd --apply)"
  log_end; exit 1
fi
[ "$_mf_ok" -eq 1 ] || { log_end; exit 1; }
log_ok "floor files moved into $BK (with settings.json as it was)"
log_note "the B1 deny entries are still present: inert without the guards and the un-swallowable layer, so removing them is a separate, deliberate step — edit permissions.deny by hand, or restore an older snapshot with restore.sh"
log_end; exit $?
