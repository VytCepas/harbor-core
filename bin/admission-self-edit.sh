#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# B2 (harbor#3) — PreToolUse(Write|Edit|MultiEdit) system-file guard.
# Blocks an agent from editing the floor's OWN control surfaces in the active config dir: settings.json, bin guards and library, hooks, integrity
# pins, deploy snapshots under backups/. The rest of ~/.claude stays editable. FAIL-OPEN on any parse error: the permissions.deny layer (B1) is the backstop. Ports containment-zones.ts and system-file-guard-core.ts @ a4e8e74 (v7.1.1), narrowed.
# Removed notes: docs/explanation/code-cases/bin-admission-self-edit.md
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin
TOOL="$(floor_field '.tool_name')"
# shellcheck disable=SC2034 # FLOOR_TOOL: read by library-admission.sh
FLOOR_TOOL="$TOOL"
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

CFG="$(floor_config_dir)"
P="$(floor_field '.tool_input.file_path')"
[ -n "$P" ] || exit 0

# Resolve to the physical target first: ./, // and bin/../ reached the real settings.json while string matching said "not protected" (red-team 2026-07-24).
# The digest subject is that RESOLVED path, so recurrence counts see one target, not three.
ABS="$(floor_norm_path "$P")"
# shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
FLOOR_OBS_SUBJECT="$ABS"

# Both the ACTIVE and the LIVE config dir are protected (a sandbox session must not rewrite the live floor), with the roots resolved physically too:
# a resolved target against an unresolved root misses everything under a symlink (macOS /var -> /private/var).
LIVE="$HOME/.claude"
# harbor#787: each root in BOTH spellings, since floor_norm_path resolves only an existing parent.
CFGR="$CFG"; LIVER="$LIVE"
case "$CFGR" in *//*|*/./*|*/../*|*/.|*/..) CFGR="$(floor_collapse_dots "$CFGR")" ;; esac
case "$LIVER" in *//*|*/./*|*/../*|*/.|*/..) LIVER="$(floor_collapse_dots "$LIVER")" ;; esac
[ -d "$CFG" ]  && CFG="$(CDPATH= cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"
[ -d "$LIVE" ] && LIVE="$(CDPATH= cd -P -- "$LIVE" 2>/dev/null && pwd -P || printf '%s' "$LIVE")"
# Case-folded: APFS is case-insensitive, so `Settings.json` reached the same inode while a case glob said "not protected" (red-team pass 2).
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
{ IFS= read -r LCFG; IFS= read -r LLIVE; IFS= read -r LCFGR; IFS= read -r LLIVER; } <<ROOTS
$(printf '%s\n%s\n%s\n%s\n' "$CFG" "$LIVE" "$CFGR" "$LIVER" | tr '[:upper:]' '[:lower:]')
ROOTS
is_protected() {
  set -- "$(lower "$1")"
  for root in "$LCFG" "$LLIVE" "$LCFGR" "$LLIVER"; do
    case "$1" in
      "$root/settings.json"|"$root/settings.local.json") return 0 ;;
      "$root/.sec0-baseline.sha256"|"$root/.helm-baseline"|"$root/.helm-floor-teeth") return 0 ;;
      # deploy's snapshot hash ledger (harbor#769). Writable, a session could bless a snapshot it forged.
      "$root/.helm-snapshots") return 0 ;;
      # The instruction-surface pin (B8) and guard-apiroute's allow list and accepted copies: writable, a session could bless its own change and re-pin over it.
      "$root/.helm-instructions.sha256") return 0 ;;
      "$root/.helm-apiroute-allow") return 0 ;;
      "$root"/.helm-apiroute/*) return 0 ;;
      # CONST-1 (harbor#44): the constitution itself, the subject of the pin above. Anchored on $CFG/$LIVE only, so a governed repo's own CLAUDE.md stays
      # writable (recover/floor-test assert it).
      "$root/claude.md"|"$root/claude.local.md") return 0 ;;
      "$root/.helm-pins"|"$root"/.helm-pins/*) return 0 ;;
      "$root/.helm-log-token") return 0 ;;
      # harbor#779: the integrity rows of contracts/control-plane-state.md (lint F14); a directory is refused by its own name too.
      "$root/.helm-obs-salt") return 0 ;;
      "$root/.helm-obs-host"|"$root/.helm-govern-salt") return 0 ;;
      "$root/.helm-install-stamp"|"$root/.helm-judge") return 0 ;;
      "$root/.helm-peers"|"$root"/.helm-peers/*) return 0 ;;
      "$root/.helm-context"|"$root"/.helm-context/*) return 0 ;;
      "$root/.helm-stop-gate"|"$root"/.helm-stop-gate/*) return 0 ;;
      "$root/.helm-dispatch"|"$root"/.helm-dispatch/*) return 0 ;;
      "$root/.helm-approvals"|"$root"/.helm-approvals/*) return 0 ;;
      "$root/.helm-ship"|"$root"/.helm-ship/*) return 0 ;;
      "$root/.helm-apiroute") return 0 ;;
      # harbor#787 — deploy snapshots, which guard-bash refuses since harbor#772. Top level only.
      "$root/backups"|"$root"/backups/*) return 0 ;;
      "$root"/hooks/*) return 0 ;;
      "$root"/bin/*) return 0 ;;   # incl. deploy-restore.sh / baseline-pin.sh — the recovery path
    esac
  done
  return 1
}

if is_protected "$ABS"; then
  # The message interpolates a payload-derived path, so the record carries the rule id passed here, never the message text.
  floor_block selfedit \
    "edit of a Helm floor control surface ($ABS) is denied — a guard must not be able to disable itself in-session" \
    floor-surface.path
fi
# A FLOOR SWITCH WRITTEN INTO ANY SETTINGS FILE (harbor#482): a settings `env` block reaches every hook and a project's settings are writable by design.
case "$(lower "$ABS")" in
  */.claude/settings.json|*/.claude/settings.local.json)
    _sw="$(floor_field '[.tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string)] | map(select(type == "string")) | join("\n")')"
    case "$_sw" in
      *HARBOR_ADMISSION_DISABLE*|*HARBOR_ADMISSION_SHADOW*)
        floor_block selfedit \
          "a floor switch (HARBOR_ADMISSION_DISABLE or HARBOR_ADMISSION_SHADOW, or an old name of one) written into a settings file reaches every later session's hooks — the operator sets it at launch" \
          switch-in-settings.content
        ;;
    esac ;;
esac
floor_log_decision selfedit allow selfedit-clean.meta
exit 0
