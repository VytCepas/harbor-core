#!/usr/bin/env sh
# B1 (harbor#3) — permissions.deny hard stops for the floor, on the install standard (harbor#800).
#   sh admission-deny.sh (--live | --dir PATH)                     DRY RUN (default): what --apply would add
#   sh admission-deny.sh --apply (--live | --dir PATH)             write (backup-first), then re-pin teeth + baseline
#   sh admission-deny.sh --repin (--live | --dir PATH)             re-pin ONLY: add no entries (harbor#58); it writes
#   sh admission-deny.sh --withdraw [--apply] (--live | --dir PATH)     remove the entries WITHDRAWN records
#   sh admission-deny.sh --prune-inert [--apply] (--live | --dir PATH)  remove deny entries the harness never
#                                                              consults (Write/NotebookEdit/MultiEdit/Glob PATH rules)
#   sh admission-deny.sh --print                                   the allow and ask rules contracts/verbs/*.md imply, one
#                                                              `allow|ask<TAB>Bash(..)<TAB>register` per row; reads no settings.json
#   The target, --help and every standard flag come from bin/deploy-install-lib.sh (lint D7): no positional dir.

# Extends the SEC-0 read-deny set with EDIT coverage of the same credential stores, workflow-file protection and harness-layer protection of the live config surfaces. deny is additive, evaluated before hooks, and un-swallowable in every mode.
# Append-only: --apply never removes or rewrites an existing entry. Re-pins .sec0-baseline.sha256 with the SAME recipe as deploy-harden.sh.
# Removed notes: docs/explanation/code-cases/bin-admission-deny.md
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): every mode writes the same settings.json and re-pins with the same two hashes; splitting would put four copies of the pin recipe in four files, and divergent copies are how B6 comes to block every session on a hash computed a different way.
# Deliberate frictions (harbor#3 + REVIEW F-findings): Edit(//**/.github/workflows/**) blocks ALL in-session workflow-file edits (the gh token keeps `workflow` scope, since dropping it breaks CI pushes without stopping dispatch). Legit CI edits: lift the entry in an unguarded session, or edit outside. It binds the FILE TOOLS only (harbor#61: `git apply` on the same file succeeds), so keep it but do not call it sufficient.
# Deny is NOT bypassed by the kill-switch: that env only stands down the B2-B6 hook layer. Deny entries change only by editing settings.json.
set -eu
. "$(dirname -- "$0")/library-log.sh"
. "$(dirname -- "$0")/deploy-install-lib.sh"
log_init floor-deny

# Three modes that all write, each a different act, as words il_cmd replays in every hint.
REPIN=0; PRUNE=0; WITHDRAW=0
il_opt() {
  # shellcheck disable=SC2034 # IL_TAKE: read by deploy-install-lib.sh
  case "$1" in
    --repin) REPIN=1; IL_TAKE=1 ;;
    --withdraw) WITHDRAW=1; IL_TAKE=1 ;;
    --prune-inert) PRUNE=1; IL_TAKE=1 ;;
    *) IL_TAKE=0 ;;
  esac
}
# PHYSICAL paths and INTENT AS A FLAG (P11-01, harbor#52): a trailing slash, a symlink or a
# position cannot reach live without --live, and CLAUDE_CONFIG_DIR never picks the dir (harbor#800).
# --print (harbor#1419): the derived rules alone, so a reader sees a rule per allow/ask row without a target or a dry run.
if [ "${1:-}" = --print ]; then
  [ $# -eq 1 ] || il_usage_error '--print takes no other argument'
  [ -d "$IL_VERBS_DIR" ] || { log_warn "verbs: no registers at $IL_VERBS_DIR (an installed copy): nothing is derived"; exit 1; }
  for _gvp in allow ask; do
    il_verbs "$_gvp" | awk -F'\t' -v p="$_gvp" '$1 == "OK" { print p "\tBash(" $2 ")\t" $3 }'
  done
  exit 0
fi
il_parse "$@"
APPLY="$IL_APPLY"
# Combining two modes would make the printed preview describe one thing while the write did another.
_modes=$(( PRUNE + WITHDRAW + REPIN ))
if [ "$_modes" -gt 1 ]; then
  log_fail "--prune-inert, --withdraw and --repin are different acts; pick one"
  log_nofix "sh $IL_SELF --help"
  log_end; exit 1
fi
# --prune-inert and --withdraw USE --apply as their write flag (they are modes), but --repin writes
# no entry at all, so pairing it with --apply is a contradiction rather than a shortcut.
if [ "$APPLY" -eq 1 ] && [ "$REPIN" -eq 1 ]; then
  log_fail "--apply and --repin are different acts; pick one"
  log_nofix "sh $IL_SELF --help"
  log_end; exit 1
fi
il_target
DIR="$IL_TARGET"
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end; exit 1; }

# Backups follow the one scheme (the install standard, harbor#765): the run's own dir,
# backups/floor-deny/<TS>/, beside its log. --apply opened it in il_target; --repin writes without
# --apply, so it opens one here, only when it is about to write.
_bkdir() {
  if [ -n "$IL_BK" ]; then BK="$IL_BK"; return 0; fi
  log_file "$DIR"
  BK="${LOG_DIR:-$DIR/backups/floor-deny/$(date +%Y%m%d-%H%M%S)-$$}"
  mkdir -p "$BK"
}

# Atomic write, VERIFIED: a bare `jq . >tmp && mv` cannot fail loudly under set -eu (a failing left side short-circuits the &&), so it once printed "APPLIED." with settings.json untouched and a tmp file orphaned (red-team pass 8).
write_settings() {  # <json-text> <target>
  _tmp="$2.tmp.$$"
  if ! printf '%s\n' "$1" | jq . >"$_tmp" 2>/dev/null || ! jq -e . "$_tmp" >/dev/null 2>&1; then
    rm -f "$_tmp"
    log_fail "refusing to write invalid JSON to $2 — nothing changed"
    log_nofix "bin/admission-deny.sh write_settings; the JSON came from its own jq"
    log_end; exit 1
  fi
  if ! mv "$_tmp" "$2"; then
    rm -f "$_tmp"
    log_fail "could not replace $2 — nothing changed"
    log_nofix "the mv error above"
    log_end; exit 1
  fi
}
S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S"
  log_nofix "floor-deny extends an existing settings.json; SEC-0 (deploy-harden.sh) is applied first"
  log_end; exit 1
fi

# The B1 additions. Edit mirrors SEC-0's Read stores 1:1 (lint D5 enforces it, harbor#88); the ~/.claude entries protect the LIVE surfaces from any session at the harness layer (B2 protects the running session's own config dir at the hook layer). Read(~/.claude/.helm-log-token) closes a SEC-0 gap: the token file was minted after the read-deny set was pinned.
# The Edit twins of the Read stores cost nothing in friction (harbor#88, measured by firing): a Read deny already refuses the Edit TOOL, so only Write and NotebookEdit change, and those had no legitimate use on a file the session may not read. Before them an agent could not READ a project's .env or stray key but could OVERWRITE it.
# ANCHORING IS LOAD-BEARING (harbor#53). Read/Edit patterns are gitignore syntax against an ANCHOR, and these live in USER settings: `//path` filesystem root (the only form matching every project), `~/path` home, `/path` the SETTINGS SOURCE (~/.claude in user settings, NOT /), `path` the session's cwd. A bare `Edit(**/.github/workflows/**)` protected only whichever repo the session was anchored to; `Edit(/mnt/c/Users/**)` resolved to ~/.claude/mnt/c/Users/** and could never fire. A new cross-project entry uses `//` or `~/` (floor-test.sh asserts it, harbor#54).
# NO `Write(<path>)` ENTRIES (2026-07-30): the harness accepts them and never consults them; only Edit(path)/Read(path) rules count, and an Edit rule covers every file-editing tool (code.claude.com/docs/en/permissions; verified by firing: a Write call was refused by an Edit deny). A bare `Write` with no path IS consulted. Lint D4 forbids the inert class and `--prune-inert` removes it from a live config, since this tool is append-only.
ADD='[
  "Edit(~/.ssh/**)",
  "Edit(~/.config/gh/**)",
  "Edit(~/.aws/**)",
  "Edit(~/.config/gcloud/**)",
  "Edit(~/.config/fly/**)",
  "Edit(~/.gnupg/**)",
  "Edit(~/.password-store/**)",
  "Edit(~/.kube/**)",
  "Edit(~/.docker/config.json)",
  "Edit(~/.netrc)",
  "Edit(~/.npmrc)",
  "Edit(~/.pypirc)",
  "Edit(//**/.env)",
  "Edit(//**/.env.*)",
  "Edit(//**/secrets/**)",
  "Edit(//**/*.pem)",
  "Edit(//**/id_rsa)",
  "Edit(//**/id_ed25519)",
  "Edit(//**/id_dsa)",
  "Edit(//**/id_ecdsa)",
  "Edit(//**/*.p12)",
  "Edit(//**/*.pfx)",
  "Edit(//**/*.jks)",
  "Edit(//**/*.keystore)",
  "Edit(~/.local/share/gcalcli/**)",
  "Edit(//**/.github/workflows/**)",
  "Edit(~/.claude/settings.json)",
  "Edit(~/.claude/settings.local.json)",
  "Edit(~/.claude/bin/**)",
  "Edit(~/.claude/.helm-baseline)",
  "Edit(~/.claude/.helm-snapshots)",
  "Edit(~/.claude/.sec0-baseline.sha256)",
  "Edit(~/.claude/.helm-floor-teeth)",
  "Edit(~/.claude/.helm-pins/**)",
  "Edit(~/.claude/.helm-peers/**)",
  "Edit(~/.claude/.helm-instructions.sha256)",
  "Edit(~/.claude/CLAUDE.md)",
  "Edit(~/.claude/CLAUDE.local.md)",
  "Edit(~/.claude/MEMORY/OBSERVABILITY/**)",
  "Edit(~/.claude/.helm-obs-salt)",
  "Read(~/.claude/.helm-obs-salt)",
  "Edit(~/.claude/.helm-log-token)",
  "Read(~/.claude/.helm-log-token)",
  "Edit(~/.claude/.helm-obs-host)",
  "Edit(~/.claude/.helm-govern-salt)",
  "Edit(~/.claude/.helm-install-stamp)",
  "Edit(~/.claude/.helm-judge)",
  "Edit(~/.claude/.helm-context/**)",
  "Edit(~/.claude/.helm-stop-gate/**)",
  "Edit(~/.claude/.helm-dispatch/**)",
  "Edit(~/.claude/.helm-approvals/**)",
  "Edit(~/.claude/.helm-ship/**)",
  "Edit(~/.claude/.helm-apiroute/**)",
  "Edit(~/.claude/.helm-apiroute-allow)",
  "Bash(rm -rf /)","Bash(rm -rf /*)","Bash(rm -rf ~)","Bash(rm -rf ~/*)","Bash(rm -rf $HOME)",
  "Bash(mkfs*)","Bash(dd if=* of=/dev/*)","Bash(chmod -R 777 /*)","Bash(chown -R * /)",
  "Bash(diskutil erase*)","Bash(diskutil secureErase*)","Bash(diskutil reformat*)",
  "Bash(diskutil zeroDisk*)","Bash(diskutil randomDisk*)","Bash(diskutil partitionDisk*)",
  "Bash(diskutil apfs delete*)","Bash(diskutil apfs erase*)",
  "Bash(git push --force*main*)","Bash(git push -f*main*)",
  "Bash(curl * | bash)","Bash(curl * | sh)","Bash(curl * | zsh)",
  "Bash(wget * | bash)","Bash(wget * | sh)","Bash(wget * | zsh)",
  "Bash(* > /dev/disk*)","Bash(* > /dev/sd*)",
  "Bash(rm -rf ~/.claude)","Bash(rm -rf ~/.claude/*)","Bash(rm -rf .git)",
  "Bash(chmod -R 777 ~)","Bash(chmod -R 777 $HOME)","Bash(chmod -R 777 /)",
  "Bash(git push --force*master*)","Bash(git push -f*master*)",
  "Bash(gh auth token*)"
]'
# `gh auth token` prints the keyring credential to stdout; the operator's box denied it, a fresh install did not (harbor#1149).
# WITHDRAWN (harbor#58): entries the operator has DECIDED against. This is data, not prose: a fork-bomb withdrawal that lived as "do not re-add this" was a wish, and a later edit or helpful session could put it back. --apply SUBTRACTS this list from ADD; `--withdraw` REMOVES these entries from the target and re-pins; floor-test asserts the two lists never intersect.
# ADDING TO THIS LIST IS A SOURCE EDIT ON PURPOSE (encoding a fix is human-gated): there is no `--withdraw <entry>` taking an argument, because the record must exist in the tree, reviewable, before the tool acts. The fork-bomb glob was applied live and removed by the operator by hand; append-only meant the next --apply would silently have put it back.
WITHDRAWN='[
  "Bash(:(){ :|:& };:)"
]'
# CANDIDATES, NOT WITHDRAWN (operator undecided, so the tool must not act): six bare-relative Read entries in the live config (`Read(**/.env)` and siblings) are redundant subsets of the `//`-anchored versions deploy-harden.sh writes. They are WORKING rules, so --prune-inert refuses them by design; move a line up into WITHDRAWN to decide it.
# BASH DENIES AT THE HARNESS LAYER (2026-07-26). They cost nothing, are evaluated before any hook, cannot be swallowed by a broken guard, and do not depend on the guards' install decision. They are GLOB matches on the command string, not a parser: they catch literal spellings only (rm -rf $(echo /) walks past), which is the point: the un-swallowable floor under the scanner (admission-baseline.md layering).
# EXTENDED 2026-07-26 by diffing upstream's permissions.deny: curl|wget piped to a shell (docs/explanation/approach.md said "never `curl | bash`" with nothing enforcing it).
# EXTENDED 2026-08-25 (harbor#306): `diskutil` erase/reformat/zero/random/partition/apfs-delete. mkfs and dd of=/dev/* were here and diskutil was not, and QA-PLAN R9 signed the guards' jq fail-open off *because B1 is the backstop*, so for this tier the documented backstop did not exist.
# THIS IS THE LAYER FOR THE MODES A GUARD CANNOT COVER: with jq absent a guard exits before any rule, and a DELETED guard file exits 127, which is not a deny. permissions.deny is evaluated by the harness and cannot be swallowed by a broken guard.
# GLOBS, NOT A PARSER: sudo diskutil eraseDisk walks past, with admission-destroy.sh covering the clever spellings. Also added: raw disk writes via redirect (`* > /dev/disk*`), rm -rf ~/.claude and `~/.claude/*`, rm -rf .git, chmod 777 on $HOME/~, and the `master` spellings of the force-push guard.
[ -d /mnt/c/Users ] && ADD="$(printf '%s' "$ADD" | jq '. + ["Edit(//mnt/c/Users/**)"]')"

# THE `~<user>` SPELLING OF $HOME (pass 13): rm -rf ~ and rm -rf $HOME were denied and rm -rf ~someone was not, in the one floor layer actually installed here (B1 is evaluated by the harness before any hook).
# This layer's Bash denies are globs and cannot say "a tilde, a name, then end of word"; the general `Bash(rm -rf ~*)` would also refuse rm -rf ~/proj/node_modules, and a guard that blocks ordinary work gets switched off (No.2.11). The general shape is covered one layer up in admission-bash.sh (TILDE_USER).
# So B1 carries the names it can RESOLVE at apply time (a hardcoded name is right here and wrong on the next box): `id -un` and the basename of $HOME, which can differ; `unique` folds them. A name with anything glob- or shell-significant is skipped rather than quoted into an entry nobody could reason about.
for _b1u in "$(id -un 2>/dev/null || true)" "$(basename "${HOME:-/}" 2>/dev/null || true)"; do
  case "$_b1u" in
    ''|*[!A-Za-z0-9_.-]*) continue ;;
  esac
  ADD="$(printf '%s' "$ADD" | jq --arg u "$_b1u" '. + [
      "Bash(rm -rf ~\($u))",
      "Bash(rm -rf ~\($u)/)",
      "Bash(rm -rf ~\($u)/*)",
      "Bash(rm -rf ~\($u)/.claude)",
      "Bash(rm -rf ~\($u)/.claude/*)",
      "Bash(chmod -R 777 ~\($u))"
    ] | unique')"
done

# ADD minus WITHDRAWN, subtracted HERE and not trusted to whoever edits ADD: the lists are far apart in this file.
ADD="$(jq -n --argjson a "$ADD" --argjson w "$WITHDRAWN" '$a - $w')"

NEW="$(jq --argjson ADD "$ADD" \
  '.permissions //= {} | .permissions.deny = (((.permissions.deny // []) + $ADD) | unique)' "$S")"

# THE APPROVAL GATE'S RULES (harbor#1018, docs/design/approval-gate.md). `ask` makes every gate-approve.sh call show Claude Code's own dialog, in auto mode too; the allow rules let the unattended merge and queue run without the classifier. Each names the INSTALLED copy under this config dir, which the floor guards; guard-bash refuses every other spelling. Append-only like the deny entries.
GATE_ASK="$(jq -n --arg d "$DIR" '["Bash(\($d)/bin/gate-approve.sh *)"]')"
# The ship runner (harbor#1060) is allowed for `night` only: its `deploy` is gate-approve.sh's child, never a rule's.
GATE_ALLOW="$(jq -n --arg d "$DIR" '["Bash(\($d)/bin/gate-merge.sh *)", "Bash(\($d)/bin/gate-queue.sh *)", "Bash(\($d)/bin/deploy-fleet.sh night*)"]')"
NEW="$(printf '%s' "$NEW" | jq --argjson a "$GATE_ASK" --argjson l "$GATE_ALLOW" '
  .permissions.ask = (((.permissions.ask // []) + $a) | unique)
  | .permissions.allow = (((.permissions.allow // []) + $l) | unique)')"

# THE VERB REGISTERS (harbor#1291, #1419). contracts/verbs/*.md hold the command shapes per CLI; these rules are DERIVED from their `allow` and `ask` rows (tests/admission/git/verbs.test.sh and tests/admission/verbs/registers.test.sh hold register and rules together) via install-lib's il_verbs, which floor-uninstall also uses.
# A row not starting `<cli> <subcommand>` is skipped: a leading flag or wildcard (`git -C * log *`) lets `*` absorb `-c core.pager=<cmd>`, a read becoming execution. With no contracts/ beside an installed copy, nothing is derived or removed.
VERB_ALLOW='[]'; VERB_ASK='[]'
if [ -d "$IL_VERBS_DIR" ]; then
  for _gvp in allow ask; do
    _gvr="$(il_verbs "$_gvp")"
    printf '%s\n' "$_gvr" | awk -F'\t' '$1 == "BAD" { print $3 "\t" $2 }' | while IFS='	' read -r _f _e; do
      log_warn "verbs/$_f: an $_gvp row must start '<cli> <subcommand>' and carry no <>|;&\$, so it is skipped: $_e"
    done
    _gvj="$(printf '%s\n' "$_gvr" | awk -F'\t' '$1 == "OK" { print $2 }' | jq -Rsc 'split("\n") | map(select(length > 0) | "Bash(\(.))")')"
    if [ "$_gvp" = allow ]; then VERB_ALLOW="$_gvj"; else VERB_ASK="$_gvj"; fi
  done
else
  log_note "verbs: no registers at $IL_VERBS_DIR (an installed copy), so no allow or ask rule is derived from them"
fi
NEW="$(printf '%s' "$NEW" | jq --argjson a "$VERB_ASK" --argjson l "$VERB_ALLOW" '
  .permissions.ask = (((.permissions.ask // []) + $a) | unique)
  | .permissions.allow = (((.permissions.allow // []) + $l) | unique)')"

# --repin (harbor#58): the act that had no tool. B1 is append-only, so after a deliberate edit of settings.json the only re-pin was --apply, which also put back what the operator removed (leave B6 blocking every session, or reverse your own decision). A re-pin BLESSES settings.json as it is, so it prints the entries B1 would add, adds nothing, and writes two hashes only.
if [ "$REPIN" -eq 1 ]; then
  log_head "B1 · re-pin only · $S"
  _absent="$(jq -n --argjson old "$(jq '.permissions.deny // []' "$S")" \
                   --argjson add "$ADD" -r '$add - $old | .[]' 2>/dev/null || true)"
  if [ -n "$_absent" ]; then
    log_warn "$(printf '%s\n' "$_absent" | grep -c .) B1 entries are NOT present in this settings.json — the re-pin blesses their absence"
    log_fix "sh $IL_SELF --apply $(il_spell)"
    printf '%s\n' "$_absent" | while IFS= read -r _e; do log_note "absent: $_e"; done
  else
    log_ok "every B1 entry is present"
  fi
  log_note "deny entries: $(jq '.permissions.deny | length' "$S")"
  _bkdir
  for _p in .sec0-baseline.sha256 .helm-floor-teeth; do
    [ -f "$DIR/$_p" ] && cp "$DIR/$_p" "$BK/$_p"
  done
  # SAME recipe as the --apply arm and as deploy-harden.sh:82. If these two ever
  # diverge, B6 blocks every session on a hash that was never wrong.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | il_sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | il_sha >"$DIR/.helm-floor-teeth"
  log_ok "re-pinned teeth: $(cat "$DIR/.helm-floor-teeth")"
  log_ok "re-pinned baseline: $(cat "$DIR/.sec0-baseline.sha256")"
  log_note "no deny entry was added or removed"
  log_end; exit $?
fi

# --withdraw (harbor#58): removes every WITHDRAWN entry present in the target, then re-pins. --prune-inert refuses this act: pruning deletes syntax that cannot protect anything, this deletes a rule that WORKS because a person decided so. It takes NO ARGUMENT, so the reviewable edit to WITHDRAWN comes first and leaves a diff.
if [ "$WITHDRAW" -eq 1 ]; then
  log_head "B1 · withdraw · $S"
  _live_w="$(jq -r --argjson w "$WITHDRAWN" '(.permissions.deny // []) - ((.permissions.deny // []) - $w) | .[]' "$S" 2>/dev/null || true)"
  printf '%s' "$WITHDRAWN" | jq -r '.[]' | while IFS= read -r _e; do log_note "recorded as withdrawn (bin/admission-deny.sh, WITHDRAWN): $_e"; done
  if [ -z "$_live_w" ]; then
    log_ok "none of them is present in this settings.json — nothing to remove (--apply subtracts WITHDRAWN from ADD, so they cannot come back)"
    log_end; exit $?
  fi
  # The removal IS the diff of the deny array, so it is listed rather than a raw diff printed.
  printf '%s\n' "$_live_w" | while IFS= read -r _e; do log_note "present here, and therefore to be REMOVED: $_e"; done
  WD="$(jq --argjson w "$WITHDRAWN" \
    '.permissions.deny = ((.permissions.deny // []) - $w)' "$S")"
  if [ "$APPLY" -eq 0 ]; then
    log_note "dry run: nothing written"
    il_next "$(il_cmd --apply)"
    log_end; exit $?
  fi
  _bkdir
  cp "$S" "$BK/settings.json"
  write_settings "$WD" "$S"
  # Re-pin, same recipe as every other write arm. A withdrawal that leaves the pin
  # stale hands the operator the exact lockout harbor#58 was filed about.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | il_sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | il_sha >"$DIR/.helm-floor-teeth"
  log_ok "withdrawn; deny entries now: $(jq '.permissions.deny | length' "$S")"
  log_ok "re-pinned: teeth + sec0 baseline"
  log_note "backup: $BK/settings.json"
  log_end; exit $?
fi

# --prune-inert (harbor#58): REMOVES deny entries the harness accepts and never consults (a PATH rule for Write, NotebookEdit, MultiEdit or Glob). Safe because such an entry cannot protect anything, so removing it changes no verdict; it is not a general withdrawal tool (--repin blesses a manual removal, neither deletes a working rule).
# PROTECTION-PRESERVING: a `Write(p)` whose `Edit(p)` twin is missing gets the twin ADDED first. A bare tool name (`Write`) IS consulted and never touched.
if [ "$PRUNE" -eq 1 ]; then
  log_head "B1 · prune inert deny entries · $S"
  _dead="$(jq -r '(.permissions.deny // [])[] | select(test("^(Write|NotebookEdit|MultiEdit|Glob)\\(.+\\)$"))' "$S" 2>/dev/null || true)"
  if [ -z "$_dead" ]; then
    log_ok "nothing to prune: no path-scoped rule for an unconsulted tool"
    log_end; exit $?
  fi
  printf '%s\n' "$_dead" | while IFS= read -r _e; do log_note "never consulted by the harness (only Edit(path)/Read(path) are), to prune: $_e"; done
  # Twins to add: EVERY unconsulted class has a documented replacement (permissions reference: `Edit(docs/**)` replaces Write/NotebookEdit/MultiEdit, `Read(docs/**)` replaces Glob); converting only Write would have silently discarded protection asked for under the others.
  TWIN_MAP='
    def twin:
      if   test("^(Write|NotebookEdit|MultiEdit)\\(.+\\)$")
      then sub("^(Write|NotebookEdit|MultiEdit)\\("; "Edit(")
      elif test("^Glob\\(.+\\)$")
      then sub("^Glob\\("; "Read(")
      else . end;
    def inert: test("^(Write|NotebookEdit|MultiEdit|Glob)\\(.+\\)$");
  '
  _twins="$(jq -r "$TWIN_MAP"'
    (.permissions.deny // []) as $d
    | [ $d[] | select(inert) | twin ]
    | map(select(. as $e | ($d | index($e)) | not)) | unique | .[]' "$S" 2>/dev/null || true)"
  if [ -n "$_twins" ]; then
    printf '%s\n' "$_twins" | while IFS= read -r _e; do log_note "consulted twin MISSING for a pruned entry, added so protection only increases: $_e"; done
  else
    log_ok "every pruned entry already has its consulted twin; nothing to add"
  fi
  PRUNED="$(jq "$TWIN_MAP"'
    .permissions.deny = (
      ((.permissions.deny // []) + [ (.permissions.deny // [])[] | select(inert) | twin ])
      | map(select(inert | not))
      | unique)' "$S")"
  if [ "$APPLY" -eq 0 ]; then
    log_note "dry run: nothing written"
    il_next "$(il_cmd --apply)"
    log_end; exit $?
  fi
  _bkdir
  cp "$S" "$BK/settings.json"
  write_settings "$PRUNED" "$S"
  # A prune changes the deny list, so both pins are stale by our own hand: same recipe as the other arms.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | il_sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | il_sha >"$DIR/.helm-floor-teeth"
  log_ok "pruned; deny entries now: $(jq '.permissions.deny | length' "$S")"
  log_ok "re-pinned: teeth + sec0 baseline"
  log_note "backup: $BK/settings.json"
  log_end; exit $?
fi

log_head "B1 · proposed deny hard stops for $S"
# One `+ <entry>` note per entry: the floor suites read the proposed set from these lines.
printf '%s' "$ADD" | jq -r '.[]' | while IFS= read -r _e; do log_note "+ $_e"; done
printf '%s' "$GATE_ASK" | jq -r '.[]' | while IFS= read -r _e; do log_note "ask rule (approval gate): $_e"; done
printf '%s' "$GATE_ALLOW" | jq -r '.[]' | while IFS= read -r _e; do log_note "allow rule (approval gate): $_e"; done
printf '%s' "$VERB_ASK" | jq -r '.[]' | while IFS= read -r _e; do log_note "ask rule (verbs): $_e"; done
printf '%s' "$VERB_ALLOW" | jq -r '.[]' | while IFS= read -r _e; do log_note "allow rule (verbs): $_e"; done
_new_e="$(jq -n --argjson old "$(jq '.permissions.deny // []' "$S")" --argjson add "$ADD" '$add - $old | .[]' -r)"
if [ -n "$_new_e" ]; then
  printf '%s\n' "$_new_e" | while IFS= read -r _e; do log_note "new here (not already present): → $_e"; done
else
  log_ok "none new — already applied"
fi

if [ "$APPLY" -eq 0 ]; then
  log_note "dry run: nothing written"
  # Print a command the accident gate ACCEPTS (harbor#51): echoing `$DIR --apply` for the live dir is the one shape the gate refuses.
  il_next "$(il_cmd --apply)"
else
  _bkdir
  cp "$S" "$BK/settings.json"
  write_settings "$NEW" "$S"
  # Same recipe as deploy-harden.sh:82 — B6 asserts against this pin.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | il_sha >"$DIR/.sec0-baseline.sha256"
  # The floor's TEETH alone (deny + mode locks): B6 blocks a session only on this; plugin/marketplace drift is reported, never blocking (red-team pass 3).
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | il_sha >"$DIR/.helm-floor-teeth"
  log_ok "applied; deny entries now: $(jq '.permissions.deny | length' "$S")"
  log_ok "re-pinned: teeth + sec0 baseline ($DIR/.sec0-baseline.sha256)"
  log_note "backup: $BK/settings.json"
fi
log_end; exit $?
