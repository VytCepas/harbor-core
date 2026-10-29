#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-${HELM_DISABLE_FLOOR:-0}}" = "1" ] && exit 0
# B2 (harbor#3) — PreToolUse(Write|Edit|MultiEdit) system-file guard.
# Blocks an agent from editing the Helm floor's OWN control surfaces inside the
# active config dir: settings.json, the guard scripts (bin/guard-*.sh,
# bin/floor-*.sh, bin/guard-lib.sh), the hooks tree, the integrity pins
# (.sec0-baseline.sha256 and the integrity rows of contracts/control-plane-state.md)
# and deploy's snapshots under backups/. Everything else — user files, and
# notably the rest of ~/.claude — is ALLOWED (matches upstream's "you may edit
# ~/.claude freely" stance; we protect only the floor's teeth, not the whole
# dir). Pure POSIX, zero Bun/node. FAIL-OPEN on any parse error: the
# un-swallowable permissions.deny layer (B1) is the backstop.
#
# Provenance: ports the SYSTEM/USER classification of upstream
# containment-zones.ts / system-file-guard-core.ts @ a4e8e74 (v7.1.1), narrowed
# to the floor's self-protection concern (the upstream content-egress scanner
# is B4's job, not this guard's).
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/guard-lib.sh"

floor_read_stdin
TOOL="$(floor_field '.tool_name')"
FLOOR_TOOL="$TOOL"
case "$TOOL" in Write|Edit|MultiEdit) ;; *) exit 0 ;; esac

CFG="$(floor_config_dir)"
# Every path this edit would touch (Write.file_path, Edit.file_path,
# MultiEdit uses file_path too). Empty ⇒ nothing to judge ⇒ allow.
P="$(floor_field '.tool_input.file_path')"
[ -n "$P" ] || exit 0

# Resolve to the physical target before classifying: ./ , // and bin/../ all
# reached the real settings.json (verified same inode) while string-matching
# the protected globs reported "not protected" (red-team 2026-07-24).
ABS="$(floor_norm_path "$P")"
# The digest subject is the RESOLVED path, not the raw one: ./x, //x and
# bin/../x are the same target, and a recurrence count that treats them as three
# different things cannot answer "is this the same block again?".
FLOOR_OBS_SUBJECT="$ABS"

# Protected surfaces, relative to the config dir. Match on the un-resolved ABS
# against the config dir prefix (both live and sandbox: $CFG is whichever is
# active; the B1 deny array independently pins the LIVE ~/.claude surfaces).
# Both the ACTIVE config dir and the LIVE one: a sandbox session must not be
# able to reach out and rewrite the live floor. The ROOTS are resolved
# physically too — comparing a resolved target against an unresolved root
# silently misses everything whenever the root sits under a symlink (macOS
# /var → /private/var is the everyday case).
LIVE="$HOME/.claude"
# harbor#787 — each root in BOTH spellings, as guard-deliverables does for HOME: floor_norm_path
# resolves only an existing parent, so a Write into a new backups/<snapshot>/ keeps the raw prefix.
CFGR="$CFG"; LIVER="$LIVE"
case "$CFGR" in *//*|*/./*|*/../*|*/.|*/..) CFGR="$(floor_collapse_dots "$CFGR")" ;; esac
case "$LIVER" in *//*|*/./*|*/../*|*/.|*/..) LIVER="$(floor_collapse_dots "$LIVER")" ;; esac
[ -d "$CFG" ]  && CFG="$(CDPATH= cd -P -- "$CFG" 2>/dev/null && pwd -P || printf '%s' "$CFG")"
[ -d "$LIVE" ] && LIVE="$(CDPATH= cd -P -- "$LIVE" 2>/dev/null && pwd -P || printf '%s' "$LIVE")"
# Case-folded comparison: APFS is case-INSENSITIVE by default, so
# `Settings.json` reaches the very same inode while a POSIX `case` glob (which
# is case-SENSITIVE) reports "not protected" — a one-character bypass, verified
# end-to-end (red-team pass 2).
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# The four roots are folded in one fork, not four (harbor#787 doubled them).
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
      # The instruction-surface pin (B8). Leaving it writable would let a
      # session inject into CLAUDE.md and then re-pin over its own tracks.
      "$root/.helm-instructions.sha256") return 0 ;;
      # guard-apiroute's allow list. Writable, it would let a session allow
      # the API reroute it was about to make.
      "$root/.helm-apiroute-allow") return 0 ;;
      # guard-apiroute's accepted copies: the baseline a reroute is judged
      # against. Writable, a session could bless its own reroute.
      "$root"/.helm-apiroute/*) return 0 ;;
      # CONST-1 (harbor#44) — the constitution itself, the thing the pin above
      # records. Protecting the record while leaving the record's SUBJECT
      # writable was the gap: the comment above reasoned about "a session
      # inject into CLAUDE.md" and then did not stop one. guard-bash.sh's FILES
      # arm closed the shell-redirect channel; this closes the cheaper one,
      # because Write/Edit/MultiEdit needs no shell at all.
      # Anchored on $CFG/$LIVE only, and floor_config_dir() resolves solely to
      # CLAUDE_CONFIG_DIR or ~/.claude — so a GOVERNED REPO's own CLAUDE.md,
      # which every Harbor-managed project has, stays writable. That is the
      # discriminating case, and recover/floor-test assert it green.
      "$root/claude.md"|"$root/claude.local.md") return 0 ;;
      "$root/.helm-pins"|"$root"/.helm-pins/*) return 0 ;;
      "$root/.helm-log-token") return 0 ;;
      # harbor#779 — the rest of contracts/control-plane-state.md's integrity rows; lint F14 holds this list to it.
      # A directory is refused by its own name too, so a file there cannot stop its writer's mkdir.
      "$root/.helm-obs-salt") return 0 ;;
      "$root/.helm-obs-host"|"$root/.helm-govern-salt") return 0 ;;
      "$root/.helm-install-stamp"|"$root/.helm-judge") return 0 ;;
      "$root/.helm-peers"|"$root"/.helm-peers/*) return 0 ;;
      "$root/.helm-context"|"$root"/.helm-context/*) return 0 ;;
      "$root/.helm-stop-gate"|"$root"/.helm-stop-gate/*) return 0 ;;
      # harbor#1044 review r3 #1 — the event dispatcher's gates: rules, ledger, spend record, spawn.on.
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
  # The MESSAGE interpolates $ABS — a payload-derived path. That is exactly why
  # the record carries the rule id passed here and never the message text.
  floor_block selfedit \
    "edit of a Helm floor control surface ($ABS) is denied — a guard must not be able to disable itself in-session" \
    floor-surface.path
fi
# A FLOOR SWITCH WRITTEN INTO ANY SETTINGS FILE (harbor#482). A settings.json `env`
# block reaches every hook (guard-lib.sh, FO-03), and a project's own
# .claude/settings*.json is deliberately writable, so either switch planted there
# would open every later session in that project. Only the two names are refused.
case "$(lower "$ABS")" in
  */.claude/settings.json|*/.claude/settings.local.json)
    _sw="$(floor_field '[.tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string)] | map(select(type == "string")) | join("\n")')"
    case "$_sw" in
      *HARBOR_ADMISSION_DISABLE*|*HARBOR_ADMISSION_SHADOW*|*HELM_DISABLE_FLOOR*|*HELM_FLOOR_SHADOW*)
        floor_block selfedit \
          "a floor switch (HARBOR_ADMISSION_DISABLE or HARBOR_ADMISSION_SHADOW, or an old name of one) written into a settings file reaches every later session's hooks — the operator sets it at launch" \
          switch-in-settings.content
        ;;
    esac ;;
esac
floor_log_decision selfedit allow selfedit-clean.meta
exit 0
