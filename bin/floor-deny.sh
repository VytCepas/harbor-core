#!/usr/bin/env sh
# B1 (harbor#3) — permissions.deny hard stops for the floor, on the install standard (harbor#800).
#   sh floor-deny.sh (--live | --dir PATH)                     DRY RUN (default): what --apply would add
#   sh floor-deny.sh --apply (--live | --dir PATH)             write (backup-first), then re-pin teeth + baseline
#   sh floor-deny.sh --repin (--live | --dir PATH)             re-pin ONLY: add no entries (harbor#58); it writes
#   sh floor-deny.sh --withdraw [--apply] (--live | --dir PATH)     remove the entries WITHDRAWN records
#   sh floor-deny.sh --prune-inert [--apply] (--live | --dir PATH)  remove deny entries the harness never
#                                                              consults (Write/NotebookEdit/MultiEdit/Glob PATH rules)
#   The target, --help and every standard flag come from bin/install-lib.sh (lint D7): no positional dir.

# Extends the SEC-0 read-deny set with EDIT coverage of the same
# credential stores, workflow-file protection, and harness-layer protection of
# the live config surfaces (defense-in-depth above the B2 hook — deny is
# additive, evaluated before hooks, and un-swallowable in every mode).
# Append-only by default: --apply never removes or rewrites an existing entry.
# Recomputes the .sec0-baseline.sha256 pin with the SAME recipe as sec0-harden.sh:82.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md), and G1 asked, so: every mode here
# writes the same settings.json and re-pins with the same two hashes. Splitting
# --apply, --repin, --withdraw and --prune-inert into separate scripts would put
# four copies of the pin recipe in four files, and the failure that recipe exists to
# prevent — B6 blocking every session on a hash computed a different way — is
# exactly what divergent copies produce. The blast radius is the deny list either
# way; keeping it in one file keeps the write path in one place.
#
# NOTE the deliberate frictions (plan of record, harbor#3 + REVIEW F-findings):
# • Edit(//**/.github/workflows/**) blocks ALL in-session workflow-file
#   edits — the gh token keeps `workflow` scope (F-finding: dropping it breaks
#   CI pushes without stopping dispatch), so the file surface is the control.
#   Legit CI edits: lift the entry in an unguarded session, or edit outside.
#   MEASURED 2026-07-30 (harbor#61): this entry binds the FILE TOOLS only. `Edit`
#   on a workflow file is refused and `git apply` on the same file succeeds, and
#   guard-bash.sh — which would close the shell path — is not installed. Keep the
#   entry; stop calling it sufficient.
# • deny is NOT bypassed by HELM_DISABLE_FLOOR — that env only stands down the
#   B2-B6 hook layer. Deny entries change only by editing settings.json.
set -eu
. "$(dirname -- "$0")/log-lib.sh"
. "$(dirname -- "$0")/install-lib.sh"
log_init floor-deny
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# Three modes that all write, each a different act, as words il_cmd replays in every hint.
REPIN=0; PRUNE=0; WITHDRAW=0
il_opt() {
  case "$1" in
    --repin) REPIN=1; IL_TAKE=1 ;;
    --withdraw) WITHDRAW=1; IL_TAKE=1 ;;
    --prune-inert) PRUNE=1; IL_TAKE=1 ;;
    *) IL_TAKE=0 ;;
  esac
}
# PHYSICAL paths and INTENT AS A FLAG (P11-01, harbor#52): a trailing slash, a symlink or a
# position cannot reach live without --live, and CLAUDE_CONFIG_DIR never picks the dir (harbor#800).
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

# Atomic write, VERIFIED. A bare `jq . >tmp && mv` cannot fail loudly under
# set -eu: a failing left side short-circuits the && and execution continues, so
# the script printed "APPLIED." while settings.json was untouched and a
# settings.json.tmp.NNNN was orphaned (red-team pass 8).
write_settings() {  # <json-text> <target>
  _tmp="$2.tmp.$$"
  if ! printf '%s\n' "$1" | jq . >"$_tmp" 2>/dev/null || ! jq -e . "$_tmp" >/dev/null 2>&1; then
    rm -f "$_tmp"
    log_fail "refusing to write invalid JSON to $2 — nothing changed"
    log_nofix "bin/floor-deny.sh write_settings; the JSON came from its own jq"
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
  log_nofix "floor-deny extends an existing settings.json; SEC-0 (sec0-harden.sh) is applied first"
  log_end; exit 1
fi

# The B1 additions. Edit mirrors SEC-0's Read stores 1:1; the ~/.claude
# entries protect the LIVE surfaces from any session (sandbox included) at the
# harness layer — B2 protects the running session's own CLAUDE_CONFIG_DIR at
# the hook layer. Read(~/.claude/.helm-log-token) closes a SEC-0 gap: the G1
# token file was minted after the read-deny set was pinned.
#
# "1:1" WAS A CLAIM, NOT A FACT, FOR SEVEN OF NINETEEN PATHS (harbor#88). This
# comment has said "mirrors SEC-0's Read stores 1:1" since the file was written,
# and lint rule D5 now makes it true instead of aspirational. It was not: the
# twelve `~/`-anchored stores had Edit twins and the six `//**/` PROJECT
# credential globs — .env, .env.*, secrets/**, *.pem, id_rsa, id_ed25519 — plus
# gcalcli had none. What that cost, measured by FIRING it rather than reading:
#
#   Write  at <path>/.github/workflows/probe.yml  → REFUSED   (an Edit deny)
#   Write  at <path>/.env                         → CREATED   (a Read deny)
#   Edit   at <path>/.env                         → REFUSED   (a Read deny)
#
# So an agent could not READ a project's .env or a stray private key, and could
# OVERWRITE either one. The permissions reference states both halves: a Read deny
# also blocks the Edit tool "including creating a new file there", but "Write and
# NotebookEdit aren't covered, so add an `Edit` deny rule for paths no tool may
# change" (code.claude.com/docs/en/permissions, read 2026-08-02, v2.1.208+).
#
# THE TWINS COST NOTHING IN FRICTION, which is why they are safe to add wholesale:
# the Edit TOOL is already refused on every one of these paths by the Read deny —
# fired above — so the only behaviour that changes is Write and NotebookEdit,
# which had no legitimate use on a file the same session is forbidden to read.
#
# This is harbor#88's finding, in the half of the list the ticket did not look at.
# The ticket's own example — `.github/workflows/**` being denied for Edit and "not
# Write" — is not a gap at all: `Edit(path)` covers every file-editing tool, and
# adding `Write(path)` beside it would emit an entry the harness accepts and never
# consults, which is the inert class lint D4 forbids and `--prune-inert` removes.
#
# ANCHORING IS LOAD-BEARING (harbor#53). Read/Edit/Write patterns are gitignore
# syntax against an ANCHOR, and these live in USER settings:
#   //path   filesystem root      — the only form that matches every project
#   ~/path   home directory
#   /path    the SETTINGS SOURCE — in user settings that is ~/.claude, NOT /
#   path     the current directory — whatever dir the session happens to be in
# `Edit(**/.github/workflows/**)` shipped here bare-relative, so it was anchored
# at the SESSION WORKING DIRECTORY: it protected workflow files in whatever repo
# the session happened to be anchored to and no other, while sec0-harden.sh:150
# reasoned about it as an unconditional control compensating for the gh token's
# `workflow` scope. Both halves were proven by FIRING it, not by reading: an Edit
# outside the anchor went through, an Edit on this repo's own governance.yml was
# blocked. cwd is not a boundary anyone chose, which is the whole argument for
# `//`. `Edit(/mnt/c/Users/**)` was worse and simpler — a single leading slash
# anchors at the settings source, so it resolved to ~/.claude/mnt/c/Users/** and
# could never fire anywhere. A new cross-project entry uses `//` or `~/`;
# floor-test.sh asserts it (see harbor#54).
# NO `Write(<path>)` ENTRIES — they are accepted and never consulted (2026-07-30).
# Every one of these paths shipped as an Edit/Write PAIR, on the reasonable-looking
# assumption that the two tools need separate rules. The harness says otherwise, in
# its own words, at every session start:
#
#   "Permission deny rule: Write(~/.ssh/**) is not matched by file permission
#    checks — only Edit(path) rules are. Use Edit(~/.ssh/**) instead (Edit rules
#    cover all file-editing tools)."
#
# and the permissions reference (code.claude.com/docs/en/permissions, read
# 2026-07-30, v2.1.210+) states the rule directly: "Claude Code checks file
# permissions against `Edit(path)` and `Read(path)` rules only. If you write a
# path rule for `Write`, `NotebookEdit`, `Glob`, or the legacy `MultiEdit` tool
# instead, Claude Code accepts the rule but never consults it".
#
# WHAT WAS AND WAS NOT LOST. Nothing: every removed `Write(p)` had an `Edit(p)`
# twin, and the Edit rule covers every file-editing tool — verified by firing it,
# not by reading, when a `Write` tool call at an absolute path was refused by
# `Edit(//**/.github/workflows/**)`. So this removes 24 inert entries and no
# protection. A bare `Write` with NO path is a different thing and IS consulted at
# the tool level; the docs say so and this list has none.
#
# The pairing is what made it invisible: a half-inert list where the live half
# does the work reads as a working list. The live config still carries these
# entries because floor-deny.sh is append-only — `--prune-inert` removes them.
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
# ── WITHDRAWN (harbor#58) ────────────────────────────────────────────────────
# Entries the operator has DECIDED against. This is data, not a comment, and that
# is the whole fix: from 2026-07-29 until 2026-07-30 the fork-bomb withdrawal below
# lived as prose saying "do not re-add this", which is a wish. Nothing stopped a
# future edit — or a future session reading the corpus and being helpful — from
# putting the entry back in ADD, and nothing removed it from a config that still
# carried it.
#
# Now: --apply SUBTRACTS this list from ADD, so re-adding an entry to ADD cannot
# resurrect it; `--withdraw` REMOVES these entries from the target settings.json
# and re-pins; and floor-test asserts the two lists never intersect.
#
# ADDING TO THIS LIST IS A SOURCE EDIT ON PURPOSE. CONSTITUTION says encoding a
# fix is a human-gated act, so there is deliberately no `--withdraw <entry>` that
# takes an argument: the record has to exist in the tree, reviewable, before the
# tool will act on it. A withdrawal you can perform from the command line is a
# withdrawal with no memory, which is the defect this closes.
#
# "Bash(:(){ :|:& };:)" — the fork-bomb glob — was in ADD, was applied live, and
# the operator removed it from settings.json by hand. Append-only meant the next
# --apply would put it back, silently overruling a decision already made.
WITHDRAWN='[
  "Bash(:(){ :|:& };:)"
]'
# CANDIDATES, NOT WITHDRAWN — the operator has not decided, so the tool must not
# act. Six bare-relative Read entries in the live config (`Read(**/.env)` and its
# five siblings) are now redundant subsets of the `//`-anchored versions
# sec0-harden.sh writes. They are WORKING rules — a deny rule with a single
# directory segment matches at any depth under the cwd — so --prune-inert refuses
# them by design, and removing a working rule is exactly the act that needs a
# person. Move a line up into WITHDRAWN to decide it.
# BASH DENIES AT THE HARNESS LAYER (coverage sweep, 2026-07-26). Until now
# permissions.deny held Read/Edit/Write entries ONLY — verified: zero `Bash(`
# entries live or in this list — so the floor's entire answer to 'rm -rf /' was
# guard-bash.sh, which is a text scanner with acknowledged residuals AND is not
# installed. These cost nothing, are evaluated by the harness BEFORE any hook
# runs, cannot be swallowed by a broken guard, and are independent of the install
# decision that twelve adversarial passes have not settled.
#
# They are GLOB matches on the command string, not a parser, so they catch the
# literal spellings and nothing cleverer — 'rm -rf $(echo /)' walks past them.
# That is fine and is the point: this layer is the un-swallowable floor under the
# scanner, not a replacement for it. FLOOR.md's layering already says B1 is the
# only layer the model cannot argue with; it simply had no Bash entries in it.
#
# EXTENDED 2026-07-26 by diffing upstream's own permissions.deny
# (Upstream/install/settings.system.json @ a4e8e74, 42 entries) against this list.
# That diff had never been run: the first twelve globs here were written from
# scratch while a curated list sat in the tree the whole build harvests from.
# Eight classes were missing outright, one of them badly:
#
#   curl|wget PIPED TO A SHELL — the most common real-world compromise shape
#   there is, and APPROACH.md:33 has said "never `curl | bash`" since day one
#   with NOTHING enforcing it. CONSTITUTION.md § "a rule with no mechanism is a
#   wish", found in Harbor's own approach document.
#
# EXTENDED 2026-08-25 (harbor#306) — `diskutil` erase/reformat/zero/random/
# partition/apfs-delete. mkfs and 'dd of=/dev/*' were here and diskutil was not:
# the same irreversible physical wipe, one spelling missing, and QA-PLAN's R9 row
# signed the guards' jq fail-open off as acceptable *because B1 is the backstop*.
# For this tier B1 was empty, so the documented backstop did not exist — the whole
# of harbor#306. guard-destroy.sh's own header already noted the gap one layer up
# ("guard-bash blocks mkfs and dd but not diskutil — same class, one spelling
# missing") and closing it there left this layer still open.
#
# THIS IS THE LAYER THAT MATTERS FOR THE MODES A GUARD CANNOT COVER. The
# floor_seg_degraded backstop added to guard-destroy.sh/guard-cloud.sh handles an
# unparseable call, but two failure modes never reach a guard at all: with jq
# absent the guard exits before any rule (CMD reads empty), and a DELETED guard
# file exits 127, which is not a deny. Both were measured as allows. permissions
# .deny is evaluated by the harness before any hook runs and cannot be swallowed
# by a broken guard, which is exactly the property those two modes need.
#
# GLOBS, NOT A PARSER, and deliberately so — 'sudo diskutil eraseDisk' walks past
# these just as 'rm -rf $(echo /)' walks past the entries above. That is the stated
# division of labour for this layer: the un-swallowable floor under the scanner,
# catching the literal spellings, with guard-destroy.sh covering the clever ones.
#
# Also added: raw disk writes via REDIRECT (`* > /dev/disk*`) — the dd form was
# covered and the redirect form was not; 'rm -rf ~/.claude' and `~/.claude/*`,
# i.e. deleting the floor's own home, which nothing denied; 'rm -rf .git';
# chmod 777 on $HOME/~ (only `/` and `/*` were covered); and the `master`
# spellings of the force-push guard.
[ -d /mnt/c/Users ] && ADD="$(printf '%s' "$ADD" | jq '. + ["Edit(//mnt/c/Users/**)"]')"

# ── THE `~<user>` SPELLING OF $HOME (pass 13) ───────────────────────────────
# Measured on the live config before this: 80 deny entries, ZERO matching
# `~[a-z]`. 'rm -rf ~' and 'rm -rf $HOME' were both denied and 'rm -rf ~someone'
# was not — the same directory, a third spelling, and the gap sat in the one
# floor layer that is actually installed on this machine (FLOOR.md: B2's hooks
# are built, not wired; B1 is evaluated by the harness before any hook runs).
#
# WHAT THIS LAYER CAN EXPRESS. Bash deny entries are GLOB matches over the
# command string — a wildcard and nothing else. The general shape has exactly one
# glob spelling, `Bash(rm -rf ~*)`, and it is unusable: `~*` also matches
# 'rm -rf ~/proj/node_modules', so it would refuse ordinary work in every project
# on the machine. A guard that blocks ordinary work gets switched off, and a
# disabled guard protects nothing (CONSTITUTION No.2.11) — so the general shape
# does NOT belong here.
#
# WHAT IT CANNOT, said plainly rather than papered over: this layer cannot deny
# 'rm -rf ~someoneelse', because it cannot enumerate accounts it has never seen,
# and it cannot express "a tilde, then a name, then the end of the word" at all.
# Both are covered one layer up, in guard-bash.sh, where TILDE_USER is a regex
# that can require exactly that — and only there.
#
# So B1 carries the names it can RESOLVE, computed at apply time. A hardcoded
# "someone" would be correct on this machine and quietly wrong on the next,
# which is the failure mode this file already documents for anchoring: a rule
# that reads fine and matches nothing. `id -un` and the basename of $HOME are
# both consulted because they can differ, and `unique` folds them when they do
# not. A name carrying anything glob- or shell-significant is skipped rather than
# quoted into an entry nobody could reason about.
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

# ADD MINUS WITHDRAWN, and the subtraction happens HERE rather than being trusted
# to whoever edits ADD. Belt and braces on purpose: the lists are far apart in this
# file, and "someone will notice the comment" is what failed for a day.
ADD="$(jq -n --argjson a "$ADD" --argjson w "$WITHDRAWN" '$a - $w')"

NEW="$(jq --argjson ADD "$ADD" \
  '.permissions //= {} | .permissions.deny = (((.permissions.deny // []) + $ADD) | unique)' "$S")"

# THE APPROVAL GATE'S RULES (harbor#1018, docs/design/approval-gate.md). `ask` makes every gate-approve.sh call show
# Claude Code's own dialog, in auto mode too, and no allow rule or PreToolUse allow can override it; the allow rules
# let the unattended merge and the queue run without the classifier. Each names the INSTALLED copy under this
# config dir, which the floor guards, never a checkout or ~/.local/bin link a session can edit; guard-bash refuses
# every other spelling of these tools. Added like the deny entries: append-only, never rewritten.
GATE_ASK="$(jq -n --arg d "$DIR" '["Bash(\($d)/bin/gate-approve.sh *)"]')"
# The ship runner (harbor#1060) is allowed for `night` only: its `deploy` is gate-approve.sh's child, never a rule's.
GATE_ALLOW="$(jq -n --arg d "$DIR" '["Bash(\($d)/bin/gate-merge.sh *)", "Bash(\($d)/bin/gate-queue.sh *)", "Bash(\($d)/bin/deploy-fleet.sh night*)"]')"
NEW="$(printf '%s' "$NEW" | jq --argjson a "$GATE_ASK" --argjson l "$GATE_ALLOW" '
  .permissions.ask = (((.permissions.ask // []) + $a) | unique)
  | .permissions.allow = (((.permissions.allow // []) + $l) | unique)')"

# THE GIT VERBS (harbor#1291). CONTRACTS/git-verbs.md is the one list of git shapes, and these rules are
# DERIVED from its `allow` and `ask` rows rather than copied here, so the register cannot say one thing while
# settings.json does another; tests/floor/git-verbs-test.sh holds the register, these rules and guard-bash's
# read-only git list to one another. Append-only like everything above. A row whose spelling does not start
# `git <subcommand>` is skipped, never trusted: a leading flag or wildcard (`git -C * log *`) lets the `*`
# absorb `-c core.pager=<cmd>`, which is how a read becomes arbitrary execution. Run from an installed copy
# with no CONTRACTS/ beside it, nothing is derived and nothing is removed. The reader is install-lib's
# il_git_verbs, because floor-uninstall takes the same rules back out.
GIT_ALLOW='[]'; GIT_ASK='[]'
if [ -f "$IL_GIT_VERBS" ]; then
  for _gvp in allow ask; do
    _gvr="$(il_git_verbs "$_gvp")"
    printf '%s\n' "$_gvr" | sed -n 's/^BAD	//p' | while IFS= read -r _e; do
      log_warn "git-verbs: an $_gvp row must start 'git <subcommand>' and carry no <>|;&\$, so it is skipped: $_e"
    done
    _gvj="$(printf '%s\n' "$_gvr" | sed -n 's/^OK	//p' | jq -Rsc 'split("\n") | map(select(length > 0) | "Bash(\(.))")')"
    if [ "$_gvp" = allow ]; then GIT_ALLOW="$_gvj"; else GIT_ASK="$_gvj"; fi
  done
else
  log_note "git-verbs: no register at $IL_GIT_VERBS (an installed copy), so no git allow or ask rule is derived"
fi
NEW="$(printf '%s' "$NEW" | jq --argjson a "$GIT_ASK" --argjson l "$GIT_ALLOW" '
  .permissions.ask = (((.permissions.ask // []) + $a) | unique)
  | .permissions.allow = (((.permissions.allow // []) + $l) | unique)')"

# ── --repin (harbor#58) ──────────────────────────────────────────────────────
# The act that had no tool. B1 is append-only, so the ONLY way to re-pin after
# the operator deliberately edits settings.json was --apply, which also puts
# back whatever they removed. That made a deliberate withdrawal unrepinnable:
# leave the pin broken (and B6 would then block every session) or run a command
# that silently reverses your own decision. Neither is a choice.
#
# A re-pin BLESSES whatever is in settings.json right now, so it must never be
# blind: it prints the entries B1 would add and does not add them, which is the
# operator seeing exactly what they are signing. Writes two hashes, nothing else.
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
  # SAME recipe as the --apply arm and as sec0-harden.sh:82. If these two ever
  # diverge, B6 blocks every session on a hash that was never wrong.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | sha >"$DIR/.helm-floor-teeth"
  log_ok "re-pinned teeth: $(cat "$DIR/.helm-floor-teeth")"
  log_ok "re-pinned baseline: $(cat "$DIR/.sec0-baseline.sha256")"
  log_note "no deny entry was added or removed"
  log_end; exit $?
fi

# ── --withdraw (harbor#58) ──────────────────────────────────────────────────
# Removes every WITHDRAWN entry that is present in the target settings.json, then
# re-pins. This is the act --prune-inert deliberately refuses: pruning deletes
# syntax that cannot protect anything, while this deletes a rule that WORKS
# because a person decided it should not.
#
# THE SAFETY IS THAT IT TAKES NO ARGUMENT. It can only remove what the tree already
# records, so the reviewable edit comes first and the command second. An operator
# who wants a different entry gone edits WITHDRAWN and re-runs — which leaves a
# diff, survives the next --apply, and cannot be done by accident at 2am.
if [ "$WITHDRAW" -eq 1 ]; then
  log_head "B1 · withdraw · $S"
  _live_w="$(jq -r --argjson w "$WITHDRAWN" '(.permissions.deny // []) - ((.permissions.deny // []) - $w) | .[]' "$S" 2>/dev/null || true)"
  printf '%s' "$WITHDRAWN" | jq -r '.[]' | while IFS= read -r _e; do log_note "recorded as withdrawn (bin/floor-deny.sh, WITHDRAWN): $_e"; done
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
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | sha >"$DIR/.helm-floor-teeth"
  log_ok "withdrawn; deny entries now: $(jq '.permissions.deny | length' "$S")"
  log_ok "re-pinned: teeth + sec0 baseline"
  log_note "backup: $BK/settings.json"
  log_end; exit $?
fi

# ── --prune-inert (harbor#58, second half) ──────────────────────────────────
# REMOVES deny entries the harness accepts and never consults: a PATH rule for
# Write, NotebookEdit, MultiEdit or Glob. This is the only removal this tool will
# ever do, and it is safe for one narrow reason — such an entry cannot be
# protecting anything, by the harness's own statement, so removing it changes no
# verdict. It is not a general withdrawal tool: --repin blesses an operator's
# manual removal, this prunes provably-dead syntax, and neither can delete a rule
# that works.
#
# PROTECTION-PRESERVING BY CONSTRUCTION: a `Write(p)` whose `Edit(p)` twin is
# missing gets the twin ADDED before the Write is dropped, so a config that
# depended on the dead entry ends up better protected, not worse. A bare tool name
# with no path (`Write`) IS consulted at tool level — never touched.
if [ "$PRUNE" -eq 1 ]; then
  log_head "B1 · prune inert deny entries · $S"
  _dead="$(jq -r '(.permissions.deny // [])[] | select(test("^(Write|NotebookEdit|MultiEdit|Glob)\\(.+\\)$"))' "$S" 2>/dev/null || true)"
  if [ -z "$_dead" ]; then
    log_ok "nothing to prune: no path-scoped rule for an unconsulted tool"
    log_end; exit $?
  fi
  printf '%s\n' "$_dead" | while IFS= read -r _e; do log_note "never consulted by the harness (only Edit(path)/Read(path) are), to prune: $_e"; done
  # Twins to add. EVERY unconsulted class has a documented replacement, and the
  # first cut of this only converted Write — so a `NotebookEdit(p)` or `Glob(p)`
  # would have been deleted with nothing put in its place, silently discarding
  # protection someone had asked for. That is the defect this whole mode exists to
  # repair, committed by the repair. From the permissions reference: "Use
  # `Edit(docs/**)` in place of `Write(docs/**)`, `NotebookEdit(docs/**)`, or
  # `MultiEdit(docs/**)`, and `Read(docs/**)` in place of `Glob(docs/**)`."
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
  # A prune changes the deny list, so both pins are stale by our own hand — same
  # recipe as the --apply and --repin arms, or B6 blocks every session on a hash
  # that was never wrong.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | sha >"$DIR/.sec0-baseline.sha256"
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | sha >"$DIR/.helm-floor-teeth"
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
printf '%s' "$GIT_ASK" | jq -r '.[]' | while IFS= read -r _e; do log_note "ask rule (git-verbs): $_e"; done
printf '%s' "$GIT_ALLOW" | jq -r '.[]' | while IFS= read -r _e; do log_note "allow rule (git-verbs): $_e"; done
_new_e="$(jq -n --argjson old "$(jq '.permissions.deny // []' "$S")" --argjson add "$ADD" '$add - $old | .[]' -r)"
if [ -n "$_new_e" ]; then
  printf '%s\n' "$_new_e" | while IFS= read -r _e; do log_note "new here (not already present): → $_e"; done
else
  log_ok "none new — already applied"
fi

if [ "$APPLY" -eq 0 ]; then
  log_note "dry run: nothing written"
  # Print a command the accident gate ACCEPTS (harbor#51). The hint used to echo
  # "$DIR --apply" unconditionally, which for the live dir is the one shape the
  # gate refuses — so the tool taught the operator to run a refused command, and
  # the shortest way to make it work is to delete the gate.
  il_next "$(il_cmd --apply)"
else
  _bkdir
  cp "$S" "$BK/settings.json"
  write_settings "$NEW" "$S"
  # Same recipe as sec0-harden.sh:82 — B6 asserts against this pin.
  jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" | sha >"$DIR/.sec0-baseline.sha256"
  # The floor's TEETH alone (deny + mode locks). B6 blocks a session only on
  # this; plugin/marketplace drift is reported, never blocking, because those
  # are ordinary user state and a fail-closed gate over them locks the operator
  # out with no in-session escape (red-team pass 3).
  jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" | sha >"$DIR/.helm-floor-teeth"
  log_ok "applied; deny entries now: $(jq '.permissions.deny | length' "$S")"
  log_ok "re-pinned: teeth + sec0 baseline ($DIR/.sec0-baseline.sha256)"
  log_note "backup: $BK/settings.json"
fi
log_end; exit $?
