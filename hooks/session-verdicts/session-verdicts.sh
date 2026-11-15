#!/usr/bin/env sh
# L0-5b (harbor#59) — SessionStart standing verdicts, printed ONCE per session.
# platform: macOS-only — the `launchctl kickstart` restart hint is the macOS arm of a uname switch; Linux prints the `systemctl --user` form instead (harbor#618).
# Verdicts that do NOT move (dead worklog, no guard wired, floor teeth drifted) print once, loudly, at session start; a statusline row would be wallpaper by the third session.
# `systemMessage` is shown to the OPERATOR, so `additionalContext` is deliberately NOT used and no context tokens are spent. SessionStart is non-blocking even on exit 2: every path ends `exit 0`.
# Emits NOTHING when every verdict is clean. Never routed through admission-hook.sh: its line-2 kill-switch would silence the one session where the floor stands down.
# Removed notes: docs/explanation/code-cases/hooks-session-verdicts-session-verdicts.md
set -u

# Once per session: skip the SessionStart that /compact re-fires (source "compact"). Read in the background under a 1 s timer: an idle open stdin held a plain `read` for ten minutes and POSIX sh has no `read -t`.
_in=""
if [ ! -t 0 ] && _sf="$(mktemp "${TMPDIR:-/tmp}/sv-in.XXXXXX" 2>/dev/null)"; then
  exec 3<&0
  { IFS= read -r _l <&3; printf '%s' "$_l" > "$_sf"; } 2>/dev/null & _rp=$!
  { sleep 1; kill "$_rp" 2>/dev/null; } & _tp=$!
  { wait "$_rp"; kill "$_tp"; wait "$_tp"; } 2>/dev/null   # reaped here, so the shell prints no "Terminated"
  exec 3<&-
  _in="$(cat "$_sf" 2>/dev/null)"; rm -f "$_sf"
fi
case "$_in" in *'"source"'*) [ "$(printf '%s' "$_in" | jq -r '.source // empty' 2>/dev/null)" != compact ] || exit 0 ;; esac

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# The re-pin hints name a TARGET: `--live` means literally $HOME/.claude and ignores CLAUDE_CONFIG_DIR, so a verdict measured in a sandbox must not print a command aimed at live (harbor#110).
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then TGT="--live"; else TGT="$CFG"; fi
# Shell-quoted because the hint is PASTED (PR #113): a config dir with a space would word-split into a different directory.
_shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
CFGQ="$(_shq "$CFG")"
# The floor-deny re-pin takes install-lib's spelling (harbor#800): '--live' or --dir '<cfg>', never a positional dir; drift-reference-check.sh still takes its target positionally.
if [ "$TGT" = --live ]; then TGTQ="$(_shq "$TGT")"; else TGTQ="--dir $CFGQ"; fi
RCQ="$(_shq "$TGT")"
S="$CFG/settings.json"
V=""

add() { V="${V:+$V
}• $1"; }

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# -- 1 · work-log hooks --
# worklog-push.sh sources library-admission.sh, which ships with the floor; without the floor it exits 1 silently and nothing syncs. Checked by SOURCE-ABILITY, not by grepping a name.
for h in worklog-push.sh; do
  if [ -f "$CFG/bin/$h" ]; then
    dep="$(sed -n 's/^\. "\$DIR\/\([a-z-]*\.sh\)".*/\1/p' "$CFG/bin/$h" 2>/dev/null | head -1)"
    if [ -n "$dep" ] && [ ! -f "$CFG/bin/$dep" ]; then
      # Verify the checkout first: an installer cannot live in $CFG/bin (it resolves its source from its own directory), so it stays where a session can write, and this line is pasted into the operator's unguarded shell.
      # `diff --quiet HEAD -- bin/` exits 1 on any modification (`status --short` always exits 0 and gated nothing). The live box goes through deploy.sh; a sandbox through the installer with --dir (harbor#800).
      _wl="work-log DEAD: bin/$h sources bin/$dep, which is not installed — the log has not synced. Fix, after confirming the checkout is clean (a session can write to it):"
      if [ "$TGT" = --live ]; then add "$_wl git -C ~/port/harbor diff --quiet HEAD -- bin/ && sh ~/port/harbor/bin/deploy.sh --only runtime --apply --live"
      else add "$_wl git -C ~/port/harbor diff --quiet HEAD -- bin/ && sh ~/port/harbor/bin/deploy-runtime-install.sh --apply --dir $CFGQ"; fi
      break
    fi
  fi
done

if [ -d "$CFG/MEMORY/.git" ] && command -v git >/dev/null 2>&1; then
  if ! git -C "$CFG/MEMORY" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    add "work-log branch has NO UPSTREAM (origin exists) — a repaired push still needs one. Fix: git -C ~/.claude/MEMORY branch --set-upstream-to=origin/main main"
  fi
fi

if [ -f "$S" ] && command -v jq >/dev/null 2>&1; then
  if [ -f "$CFG/.helm-floor-teeth" ]; then
    _pin="$(cat "$CFG/.helm-floor-teeth" 2>/dev/null)"
    _live="$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" 2>/dev/null | sha)"
    [ "$_pin" = "$_live" ] || \
      add "floor teeth DRIFT: settings.json no longer matches the pin. If you changed deny deliberately: sh $CFGQ/bin/admission-deny.sh $TGTQ --repin (adds nothing). If you did not, investigate before re-pinning."
  else
    add "floor teeth UNPINNED: nothing detects a change to permissions.deny. Fix: sh $CFGQ/bin/admission-deny.sh $TGTQ --repin"
  fi
fi

if [ -f "$S" ] && command -v jq >/dev/null 2>&1; then
  _g="$(jq '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | map(select(test("(guard|admission)-"))) | length' "$S" 2>/dev/null || echo 0)"
  [ "${_g:-0}" -eq 0 ] && \
    add "no guard is wired: B1 deny is live, B2-B6 are not. bin/eval-pass-score.sh exits 2 — the latest adversarial pass still reports criticals, so this is the CURRENT CORRECT STATE, not a todo."
fi

# -- 5 · the judge --
# audit-triage-run.sh writes this cache from a scheduled job (judging takes 7 s; not on the session's path). Age is from mtime (`find -mtime`); the stamp is displayed.
# Silent when the cache is absent (an operator who did not install the job must not be nagged, 2.11); speaks only on `crit` or a cache that STOPPED being written.
JV="$CFG/.helm-judge"
if [ -f "$JV" ]; then
  _jhead="$(head -1 "$JV" 2>/dev/null)"
  _jstamp="$(printf '%s' "$_jhead" | awk '{print $2}')"
  if [ -n "$(find "$JV" -mtime +2 -print 2>/dev/null)" ]; then
    case "$(uname -s 2>/dev/null)" in
      Darwin) _jcheck="launchctl kickstart -k gui/\$(id -u)/com.harbor.audit.triage" ;;
      *) _jcheck="systemctl --user start harbor-audit-triage.service; journalctl --user -u harbor-audit-triage.service -n 20" ;;
    esac
    add "ledger judge STALE: last verdict $_jstamp and the daily job has not written since. The judge is not reporting clean — it is not reporting. Check: $_jcheck"
  else
    while IFS= read -r _jl; do
      case "$_jl" in
        crit\ *) add "ledger judge CRIT: $(printf '%s' "${_jl#crit }" | awk -F'|' '{print $1": "$2" — fix: "$3}')" ;;
      esac
    done < "$JV"
  fi
fi

# -- 6 · installed-surface references (harbor#462) --
# drift-reference-check.sh asks whether the copy that RUNS holds together; nothing else ran it. Inline, not a cache: ~0.2 s, and a cache needs the staleness rule of 5.
# One line per rule, not per finding: ten dead citations from one cause must not be ten lines at every session start.
# Stamped `[check:drift.reference-check]` (docs/reference/checks.md) so an alert resolves to its registry row.
# Reads $CFG/bin, NEVER the repo: a session can write the repo copy but not $CFG/bin, so running it would let a session inject code into later sessions. Silent when not installed (2.11).
RCHK="$CFG/bin/drift-reference-check.sh"
if [ -f "$RCHK" ] && command -v jq >/dev/null 2>&1; then
  _rj="$(sh "$RCHK" "$CFG" --json 2>/dev/null)"
  # An unparseable payload is NOT silence: "could not look" must never render as "nothing to see".
  if printf '%s' "$_rj" | jq -e 'has("findings")' >/dev/null 2>&1; then
    _rn="$(printf '%s' "$_rj" | jq -r '.findings | length')"
    if [ "${_rn:-0}" -gt 0 ] 2>/dev/null; then
      _rr="$(printf '%s' "$_rj" | jq -r '[.findings[].rule] | group_by(.) | map("\(.[0])x\(length)") | join(" ")')"
      add "[check:drift.reference-check] INSTALLED SURFACE: $_rn reference(s) do not resolve ($_rr). This is the copy every session loads. Detail: sh $CFGQ/bin/drift-reference-check.sh $RCQ"
    fi
  else
    add "[check:drift.reference-check] could not run the installed-surface check — that is not a clean result. Try: sh $CFGQ/bin/drift-reference-check.sh $RCQ"
  fi
fi

[ -z "$V" ] && exit 0

MSG="HARBOR — standing verdicts (once per session; the statusline carries what moves)
$V"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$MSG" '{systemMessage: $m}'
else
  # No jq: say it on stderr; malformed JSON would be a hook error and silence would hide a dead worklog.
  printf '%s\n' "$MSG" >&2
fi
exit 0
