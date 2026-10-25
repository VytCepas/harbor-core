#!/usr/bin/env sh
# L0-5c (harbor#59) — install the Helm RUNTIME, which is not the floor (the install standard, harbor#765).
#   sh runtime-install.sh (--live | --dir PATH)           DRY RUN (the default): the plan, nothing written
#   sh runtime-install.sh --apply (--live | --dir PATH)   write, backing up first beside the run's log
#   --accept-loss   install even though this source lacks commits already installed (install-stamp)
#
# WHY A SECOND INSTALLER EXISTS. floor-install.sh installs the floor: it copies
# every guard AND wires them as PreToolUse hooks. bin/pass-score.sh exits 2 —
# the latest adversarial pass still reports criticals — so that install is
# correctly WITHHELD BY THE OPERATOR. (Withheld, not blocked: nothing enforces
# it. floor-install.sh never consults pass-score.sh — verified, zero matches —
# so the exit 2 is a verdict a human acts on, not a gate.) But three things the operator needs were sitting behind that
# block for no reason:
#
#   1. guard-lib.sh is a LIBRARY. worklog-push.sh (and the retired pull hook, #311) sourced it,
#      it ships with the floor, and so both hooks have been exiting 1 with zero
#      output at every SessionStart and Stop — the git-backed work-log has not
#      synced at all. Copying a library wires nothing and vetoes nothing.
#   2. the statusline and the SessionStart verdicts hook are L0-5 surfaces, not
#      floor surfaces. Neither can block a tool call.
#   3. statusLine.refreshInterval is one settings key.
#
# INSTALLS NO GUARD AND WIRES NO PreToolUse HOOK. That is the whole point: it is
# the part of the runtime whose blast radius is a wrong string on a status row.
# If you want the floor, that is floor-install.sh; pass-score.sh reports on it
# but does not gate it.
#
# Append-only on hooks, backup-first, and it RE-PINS at the end — because writing
# settings.json is exactly what breaks the teeth pin, and an installer that
# leaves the box in drift has handed the operator a false alarm to investigate.
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/log-lib.sh"
. "$SRC/install-lib.sh"
log_init runtime-install
# The target, --help and every flag come from install-lib (lint D7): physical paths, --live only by
# flag, CLAUDE_CONFIG_DIR never picking the dir (harbor#52, P11-01, harbor#765).
il_parse "$@"
il_target
DIR="$IL_TARGET"
# The commit column of this run's .harbor-manifest rows (install standard §3): the checkout it runs from.
il_source "$SRC/.."
REFRESH="${HARBOR_STATUSLINE_REFRESH:-10}"
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq is required, and is not on PATH"
  log_fix "$(pkg_hint jq)"
  log_end; exit 1
fi
# Same idiom as guard-lib's floor_sha: sha256sum where it exists, shasum elsewhere. Used to detect the
# content pins this install invalidates, never to write one.
_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S"
  log_nofix "SEC-0.md — a config dir Claude Code has started in once"
  log_end; exit 1
fi

# guard-lib.sh first and by name: it is the dependency that was missing, and the
# reason the work-log died. The rest are the L0-5 surfaces themselves.
#
# context-resolve.sh is the SECOND HALF OF THE SAME COUPLING DEFECT, found
# 2026-07-30 after this installer had already run: it ships in floor-install.sh's
# GUARDS list, so it was trapped behind the same blocked install, and both engine
# hooks read the per-session verdict IT WRITES. Copying guard-lib.sh restored the
# dependency and not the function — `floor_engine_stand_down` then treated an absent
# `.helm-context/<session_id>` as "stand down" (it no longer reads it, harbor#954), so worklog-push
# kept exiting 0 having written nothing, which is indistinguishable from success.
# Measured on the live box: newest session record 2026-07-29, zero for 07-30.
# It belongs here and not behind the floor gate for the reason floor-install.sh
# already states at its own wiring line — it is a RECORDER, never a veto: it
# wires no PreToolUse hook, cannot block a tool call, and every path in it
# exits 0.
# THE RECOVERY SET SHIPS HERE TOO, because it was already living in ~/.claude/bin
# with NO installer that puts it there. Everything reaching the live dir by hand
# drifts, and X2 proved it: baseline-pin.sh and recover-test.sh were both behind
# the repo on 2026-08-01 while the four files an installer owns were current.
#
# They belong to this installer rather than floor-install.sh by this file's own
# criterion — they install no guard and wire no PreToolUse hook. And they must be
# in the LIVE dir at all, not only in the repo, because that is the whole premise
# of RECOVER: restore.sh reads deploy's snapshots from the config dir's backups/
# (harbor#765), and a recovery path that needs a git checkout to exist is not one
# you can lean on when the checkout is what you lost. recover-test.sh comes along for the same reason — it is how you
# verify that path on a box that has nothing else. It lives in tests/floor/ on
# tests/lib/core.sh since harbor#727, so $SUITE ships both, below.
#
# fleet-sessions.sh IS THE SAME DEFECT AS B6 BELOW, found the same day and on the
# surface that made it visible. context-resolve.sh:203 guards its peer report on
# `[ -f "$DIR/fleet-sessions.sh" ]` and stays silent when the file is absent —
# correct, since the reader needs jq and a `ps` per session and must never print
# a count it did not measure. But NO INSTALLER PUT THE FILE THERE: it is in no
# GUARDS list and was in no FILES list, so the guard was permanently false and
# the SessionStart peer report had never once fired on the live box. Measured
# 2026-08-02 with four concurrent sessions running, two of them writing
# different worktrees of THIS repo — the exact contention the report exists to
# name — and every one of those sessions opened believing it was alone.
#
# A feature that is built, wired, tested and unreachable is worse than one that
# was never written: the repo reads as though the operator is being warned.
#
# floor-deny.sh JOINS FOR THE OPPOSITE REASON — not to make a call resolve, but
# to make a PASTED COMMAND UNPLANTABLE. B6 and session-verdicts.sh both hand the
# operator a re-pin command to run in their OWN terminal, unguarded, with their
# full privileges. Named at the checkout (`~/port/harbor/bin/floor-deny.sh`) that
# instruction is a delivery mechanism: a session can append a line to the file
# and then wait for the gate to tell the operator to run it. Measured 2026-08-03,
# five write shapes each: at the checkout `>>`, `cp`, `sed -i`, `>` and the Edit
# tool are ALL ALLOWED; at $CFG/bin all five are BLOCKED by guard-bash and
# guard-selfedit. Same script, same operator, opposite integrity.
#
# It adds NO capability a session does not already have — `sh ~/port/harbor/bin/
# floor-deny.sh --live --repin` runs at rc=0 today, so the amnesty is reachable
# either way. What shipping it buys is that the copy the OPERATOR is told to run
# is one the session cannot have edited.
#
# judge-run.sh, failure-capture.sh AND floor-verify.sh JOIN AS A SET, and the
# reason is the same unplantability argument one paragraph up. launchd/
# com.harbor.judge.plist runs the judge daily as the operator; a job aimed at
# ~/port/harbor/bin would let ANY session schedule arbitrary code on this machine,
# because a session can write there and cannot write under $CFG/bin. So the
# scheduled path must be the installed one.
#
# All three, not one: judge-run.sh resolves the judge from its OWN directory
# (never from the tree under inspection — failure-capture.sh's header records why
# a hostile copy in an inspected tree could make a run report nothing and exit
# 0), and failure-capture.sh in turn reads floor-verify.sh's probe payloads to
# EXCLUDE the verifier's own traffic from its recurrence counts. Installed
# without floor-verify.sh the judge still runs and says loudly that it could not
# separate probe traffic — a degraded verdict, not a silent one.
#
# THIS REVERSES A RECORDED DECISION. CONTRACTS/cli.md states failure-capture.sh
# is "deliberately not in an installer payload either, unlike observe-report.sh".
# That decision was made when nothing scheduled it, and it is exactly what left a
# crit finding unread for eleven days. The contract row is updated in the same
# change; if this is reverted, revert the plist with it or the job is aimed at a
# file that is not there.
# floor-install.sh IS IN THE PAYLOAD BECAUSE sandbox-make.sh CALLS IT (harbor#313).
# `sandbox-make.sh <dir> --with-floor` runs `sh "$SRC/floor-install.sh"`, and
# sandbox-make.sh is installed while floor-install.sh was not — so the flag worked
# from a repo checkout and failed on a missing file from $CFG/bin, which is the copy
# a session reaches. It was not a cosmetic break: --with-floor exists BECAUSE the
# sandbox went stale once and "try it in the sandbox" then validated a build nobody
# was shipping (QA-PLAN R8), so guard testing fell back to a config dir with no
# floor at exactly the surface where that matters.
#
# floor-verify.sh — the other script sandbox-make invokes through $SRC — was
# already here, which is why only half the flag was broken and why the failure read
# as a missing file rather than a missing decision.
#
# install-stamp.sh COMES WITH IT, AND THE FLAG IS STILL BROKEN WITHOUT IT.
# floor-install.sh reaches three more scripts through its own $SRC. Two degrade by
# design and say so — pass-score.sh is existence-tested and advisory,
# runtime-install.sh is read with `|| true` and its comment records that an empty
# read fails safe toward copying. install-stamp.sh is the third and is NOT guarded on
# the --apply path: absent, `sh` exits 127, floor-install reads that as a FAILED
# regression check and refuses.
#
# MEASURED with floor-install.sh in the payload and install-stamp.sh not:
#   sandbox-make <dir> --fresh --with-floor  ->  rc=1, "REFUSING — this source is
#   missing work that is already installed", and NO floor installed.
# So shipping floor-install.sh alone would have closed the ticket on a flag that
# still did not work, one layer down.
#
# WORSE, AND THE REASON THIS IS NOT COSMETIC: the sandbox was left looking ARMED.
# `--fresh` seeds it from the live config dir, so it came out with 7 guards, 5
# PreToolUse hooks and 96 deny entries — all byte-identical to
# ~/.claude/bin, none of them this checkout's. That is QA-PLAN R8 exactly: "try it in
# the sandbox" validating a build nobody is shipping, which is the failure
# --with-floor was added to prevent.
#
# ITS OWN $SRC RESOLVES CORRECTLY ONCE INSTALLED. floor-install.sh copies $GUARDS
# out of its own directory, and on a floored box those guards are in $CFG/bin
# because floor-install.sh put them there — so an installed copy creating a sandbox
# copies the LIVE floor into it, which is what R8 asks for. lint X7 now checks this
# class instead of exempting it.
# merged-check.sh COMES WITH install-stamp.sh, and leaving it out would re-open the
# §2.11 defect install-stamp's own comment was written to close. install-stamp asks
# "would this deploy remove work" by COUNT, then asks merged-check whether the
# unreachable commits are patch-present anyway (every PR here lands as a squash, so a
# fully merged branch is never an ancestor). Without it the content question cannot be
# asked, the count refuses on its own, and the remedy printed is the loss flag (then --allow-regression, --accept-loss since harbor#765) —
# "a flag whose name asserts a rollback that is not happening ... the flag a reader
# learns to pass reflexively, after which the check protects nothing".
#
# It is a leaf and it is cheap: 191 lines, no $SRC/$DIR/$CFG dependency of its own, a
# predicate that answers on stdout. So the chain X7 walks terminates here rather than
# pulling half of bin/ into $CFG.
# harbor-clean.sh COMES WITH fleet-snapshot-refresh.sh, which runs it as
# `--record --if-due` for the statusline's 🧹 count. Installed, it is only ever called
# that way; --apply from $CFG/bin would still need an explicit --live, and the operator
# runs deletes from the repo copy through skills/housekeeping.
# ci-queue.sh COMES WITH IT TOO (harbor#657): the same job runs it every tick for the
# statusline's ⏳ tile. Read-only against GitHub; it writes only its own cache.
# main-tip-verdict.sh (harbor#586) likewise: the same job runs it for the statusline's MAIN RED.
# runner-switch.sh (harbor#865) likewise: the same job runs it, and it sets the repo variable HARBOR_RUNNER.
# ci-runners.sh (harbor#1060) likewise: its `tick` sets each fleet repo's CI_RUNS_ON and re-runs billing-refused runs.
# ci-runners-{fleet,provision,github,watch}-lib.sh COME WITH IT (harbor#1060 split): it sources all four from its own dir,
# so a copy without one dies on the first verb. ci-lost-job.sh COMES WITH IT TOO: ci-runners reads the billing phrase from it (harbor#1091), so a copy without it re-runs nothing.
# gh-plan.sh (harbor#1060) likewise: it reads the account plan and main's protection and logs when either moves.
# ci-governor.sh is run by launchd/com.harbor.ci-governor.plist from here, never from a checkout a session can edit;
# ci-governor-hook.sh is the host runners' job hook (ACTIONS_RUNNER_HOOK_JOB_STARTED and _COMPLETED point at it).
# status-obligations.sh (harbor#1050) likewise: fleet-snapshot-refresh runs its `reconcile` every tick from here. It reads its
# register from ../CONTRACTS/obligation-kinds.tsv in a checkout and from bin/obligation-kinds.tsv beside itself once installed, so DATA
# below ships that file into bin/ (a new top-level entry would be one deploy's snapshot set does not cover); without either, the
# call (`>/dev/null || true`) fails silently and the box shows no ⧗, no receipt and no ledger (harbor#1115 review).
# log-lib.sh and install-lib.sh (harbor#771, #765): the installed floor-install, floor-verify, restore,
# install-stamp and floor-deny source them from their own dir, so a copy without them cannot run.
# fs-lib.sh (harbor#618): pulse, harbor-clean and reference-check read mtimes through it, from their own dir.
# alert-lib.sh (harbor#618): pulse-notify and session-react-lib say a banner through its fallback chain, from their own dir.
# stream-lib.sh (harbor#1181): fleet-snapshot-refresh appends its history through harbor_emit, from its own dir.
# collector-check.sh (harbor#1181 lane 5): fleet-snapshot-refresh runs it each tick, from its own dir.
# gate-merge-stack.sh (harbor#1060, ship contract 5b.9) is merge-stack; it runs merge-check.sh and gate-merge-stack-resolve.py
# from its own dir (5a.6), and reads merge-stack-union.txt beside itself once installed (DATA below).
# event-dispatch.sh (harbor#1044) is what launchd/com.harbor.event.dispatch.plist runs from here; shipped inert: no
# installer loads that plist or writes a rule. event-bus.sh ships with it (floor-install copies it too): the loop
# guard needs the bus that passes HARBOR_EVENT_CAUSE on, and a dispatcher beside an older bus refuses to follow.
FILES="guard-lib.sh access-confinement.sh save-log-token.sh findings-run.sh redteam-corpus-run.sh ticket-note.sh reply-shape.sh session-subagent-check.sh context-resolve.sh floor-deny.sh floor-install.sh install-stamp.sh merged-check.sh fleet-glyph.sh subagent-glyph.sh fleet-sessions.sh fleet-snapshot-refresh.sh harbor-clean.sh ci-queue.sh main-tip-verdict.sh gh-plan.sh runner-switch.sh ci-runners.sh ci-lost-job.sh ci-governor.sh ci-governor-hook.sh session-verdicts.sh observe-report.sh restore.sh sandbox-make.sh worklog-push.sh memory-harvest.sh pulse.sh pulse-notify.sh usage-aggregate.sh judge-run.sh failure-capture.sh floor-verify.sh decider-set.sh renew-check.sh store-check.sh context-budget.sh reference-check.sh cited-paths.awk failure-observe.sh log-lib.sh install-lib.sh fs-lib.sh alert-lib.sh status-obligations.sh ci-runners-fleet-lib.sh ci-runners-provision-lib.sh ci-runners-github-lib.sh ci-runners-watch-lib.sh gate-merge-stack.sh gate-merge-stack-resolve.py merge-check.sh event-dispatch.sh event-bus.sh stream-lib.sh collector-check.sh session-state.sh session-react-lib.sh session-notify.sh session-save-now.sh session-ci-watch.sh session-cleanup-report.sh session-check.sh session-title.sh"
# The restore-path suite and the harness it sources, as <checkout path>:<config-dir path> (harbor#727).
# Same relative layout as the repo, so bin/recover-test.sh finds ../lib/core.sh with no checkout.
SUITE="tests/floor/recover-test.sh:bin/recover-test.sh tests/lib/core.sh:lib/core.sh"
# Data files an installed script reads from its own directory, as <checkout path>:<config-dir path>. They go inside bin/, an entry the
# installers already write and deploy's snapshot set already covers, so the script finds them with no checkout above it (harbor#1115).
# required-checks.tsv: harbor's rows, which merge-stack unions with a repo's own declaration (r5 #3).
# CHECKS.md and event-rules.tsv: event-dispatch.sh judges a rule against the register and the presets it was installed with, by their
# manifest blob, never a working tree whose branch would decide which presets are valid (harbor#1044 review r3 #5).
# repo-slug.txt: harbor's own owner/name, which log-lib's repo_slug reads beside an installed tool (main-tip-verdict, runner-switch,
# gh-plan, ci-governor and findings-run), where no checkout's origin can name it; nothing a session can write may (harbor#1149).
DATA="CONTRACTS/obligation-kinds.tsv:bin/obligation-kinds.tsv CONTRACTS/merge-stack-union.txt:bin/merge-stack-union.txt CONTRACTS/required-checks.tsv:bin/required-checks.tsv CHECKS.md:bin/CHECKS.md CONTRACTS/event-rules.tsv:bin/event-rules.tsv CONTRACTS/session-waiting.tsv:bin/session-waiting.tsv CONTRACTS/repo-slug.txt:bin/repo-slug.txt"

# ── REFRESH-ONLY: files this installer UPDATES but will never INSTALL ────────
# guard-integrity.sh (B6) is the one file in the floor with no reachable update
# path. floor-install.sh copies it, but only under --with-b6, and the documented
# install order holds that back until the floor is verified — so in practice the
# live B6 is frozen at whatever version was installed.
#
# NOT because "pass-score gates floor-install": THAT GATE DOES NOT EXIST.
# `grep -n pass-score bin/floor-install.sh` returns nothing, no CI job wraps the
# installer, and bin/harbor:35 only DESCRIBES the install as "gated by
# pass-score.sh" in its help table. pass-score.sh exits 2, and the operator
# treats that as a stop; nothing makes them. This file said otherwise in three
# places and so did several others — Harbor's own "a rule with no mechanism is a
# wish", sitting in the comments of the thing it judges. Stated correctly here so
# the next reader does not plan against a gate that is not there.
#
# The freeze is real either way, and that is what REFRESH_ONLY answers:
# harbor#103 fixed the
# gate's recovery message (it named floor-deny.sh --live --apply for a guard
# CONTENT drift, which floor-deny cannot clear — the gate blocked the session and
# named a command that could not unblock it). The fix is on main, tested, and
# CANNOT REACH THE BOX. A guard whose own bug-fix is undeliverable is worse than
# one that was never installed, because the operator reads the repo and believes
# the live copy matches it.
#
# WHY A SEPARATE LIST RATHER THAN A LINE IN $FILES. $FILES is an unconditional
# copy. Adding B6 there would INSTALL it on any config dir that runs this
# installer, and FLOOR.md's 2026-07-28 correction records what that does: B6
# hard-requires the four scanners present, pinned AND wired, so on a box without
# them all 14 checks fail and every SessionStart emits {"continue":false}. The
# operator's only escape is HELM_DISABLE_FLOOR=1 — a bricked session or no floor
# at all. floor-install.sh's --with-b6 gate and its "B6 installs LAST" order are
# load-bearing, and this installer does not get to route around them.
#
# So: copied if and only if it is ALREADY THERE. Present means the operator ran
# --with-b6 deliberately, on a box that passed the scanner install first. Absent
# means B6 was never opted into, and this installer leaves it that way. It still
# installs no guard and wires no hook — the header's invariant holds.
REFRESH_ONLY="guard-integrity.sh"


# ── ONE-WORD COMMANDS ARE NOT THIS INSTALLER'S (harbor#708) ─────────────────
# `idea`, `memory`, `gcx` and `gcloud` were linked here (LINK_CMDS) AND by shim-install from
# CONTRACTS/shims.tsv: two owners of one path, which is how a link gets repointed twice with nobody
# saying which won. shims.tsv is the one owner of ~/.local/bin now; this installer never touches it.


RESOLVER_HOOK="/bin/sh $DIR/bin/context-resolve.sh"
# The hook engines (hooks/<engine>/, D-88) are wired by bin/deploy-hooks.sh from their manifests, after their files
# are copied: desired state for harbor's own entries, <engine>.off, and a binding removed by hand stays removed.
# The why of each binding is in its manifest (harbor#1272).
HOOKS="$SRC/deploy-hooks.sh"
_src() { printf '%s/../%s' "$SRC" "$(il_src "$SRC/.." "$1")"; }  # FILES are installed names; an engine's bytes are in its folder

# Append-only hook merge: add the command if no entry already carries it. Compares
# the COMMAND STRING, so re-running is idempotent and an operator's own hook in
# the same event is never touched.
merge_session_hook() { # <settings-json-text> <command>
  # THE BUCKET SHAPE IS THE CONTRACT (harbor#95). This used to append
  # `{hooks: [...]}` with no `matcher` key, while floor-install.sh's merge_hook
  # writes `{matcher: "", hooks: [...]}` and dedupes by scanning the bucket whose
  # matcher EQUALS the one it was given. Two shapes, two dedupes, neither able to
  # see the other's entry — so running both installers, which the documented
  # install order requires, wired context-resolve.sh at SessionStart TWICE, every
  # time. It was invisible while the resolver was a cheap recorder; once it grew
  # an additionalContext report the notice was injected into the session twice.
  #
  # Emitting the same shape fixes it in BOTH orders: merge_hook then finds the
  # matcher-"" bucket and sees the command, and this scan sees floor-install's.
  printf '%s' "$1" | jq --arg c "$2" '
    .hooks //= {} | .hooks.SessionStart //= []
    | if ([.hooks.SessionStart[]?.hooks[]?.command // empty] | index($c)) then .
      else .hooks.SessionStart += [{matcher: "", hooks: [{type: "command", command: $c}]}] end'
}

NEW="$(cat "$S")"
NEW="$(merge_session_hook "$NEW" "$RESOLVER_HOOK")"
# BOTH GLYPH SURFACES ARE WIRED HERE, IN ONE PASS, AND THAT IS DELIBERATE.
# subagent-glyph.sh would otherwise be a file this installer copies and nothing
# ever calls — the harness only invokes it when settings.json declares
# subagentStatusLine, so shipping the script without the key is a no-op that
# reads like a feature. The operator would have to hand-edit a floor surface to
# finish an install, which is the one thing this installer exists to avoid.
#
# NO refreshInterval ON THE SUBAGENT KEY. The documented shape is type+command
# only; the panel drives its own refresh tick, and inventing a field the schema
# does not define is how a settings file starts being ignored.
#
# IT DOES NOT MOVE THE FLOOR PIN. .helm-floor-teeth hashes permissions.deny plus
# the two lock flags and nothing else, so adding a display key cannot make the
# statusline report PIN DRIFT at itself. The B8 instruction pin DOES cover
# settings.json, so a re-pin is still owed after any install — which is already
# the documented next step, not a new one.
NEW="$(printf '%s' "$NEW" | jq --arg c "/bin/sh $DIR/bin/fleet-glyph.sh" \
                               --arg sc "/bin/sh $DIR/bin/subagent-glyph.sh" --argjson r "$REFRESH" '
  .statusLine = {type: "command", command: $c, refreshInterval: $r}
  | .subagentStatusLine = {type: "command", command: $sc}')"

if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $DIR"; else log_head "plan for $DIR (dry run: nothing is written)"; fi
# A half install is worse than none: every file the payload names must be here before anything is.
_missing=0
for f in $FILES $REFRESH_ONLY; do
  [ -f "$(_src "$f")" ] && continue
  _missing=1
  log_fail "$f is missing from $SRC — refusing a half install"
  log_nofix "a checkout, or an installed copy, carrying every file runtime-install.sh names in FILES"
done
for _p in $SUITE; do
  [ -f "$SRC/../${_p%%:*}" ] && continue
  _missing=1
  log_fail "${_p%%:*} is missing from $SRC/.. — refusing a half install"
  log_nofix "a harbor checkout (the restore-path suite ships from its tests/)"
done
for _p in $DATA; do
  [ -f "$SRC/../${_p%%:*}" ] && continue
  _missing=1
  log_fail "${_p%%:*} is missing from $SRC/.. — refusing a half install"
  log_nofix "a harbor checkout (an installed script reads this data file beside bin/)"
done
[ -f "$SRC/check-registry-generate.sh" ] || {
  _missing=1
  log_fail "check-registry-generate.sh is missing from $SRC — refusing a half install"
  log_nofix "a harbor checkout (the register is installed composed with the private layer's rows)"
}
[ -f "$SRC/gate-required-generate.sh" ] || {
  _missing=1
  log_fail "gate-required-generate.sh is missing from $SRC — refusing a half install"
  log_nofix "a harbor checkout (the required-checks list is installed composed with the private layer's rows)"
}
[ "$_missing" -eq 0 ] || { log_end; exit 1; }
# THE REGISTER INSTALLS COMPOSED (harbor#1149): bin/CHECKS.md is core CHECKS.md plus the private layer's rows
# when that layer holds a checks.md, and exactly core when it does not, so a reader has ONE registry to open.
# A fragment that does not parse refuses the install; it is never dropped and the box left without its client rows.
CK_SRC="$SRC/../CHECKS.md"
CK_TMP="$(mktemp "${TMPDIR:-/tmp}/runtime-install-checks.XXXXXX")" || { log_fail "could not make a temp file for the composed register"; log_nofix "TMPDIR"; log_end; exit 1; }
RC_TMP="$(mktemp "${TMPDIR:-/tmp}/runtime-install-required.XXXXXX")" || { log_fail "could not make a temp file for the composed required-checks list"; log_nofix "TMPDIR"; log_end; exit 1; }
trap 'rm -f "$CK_TMP" "$RC_TMP" "$RC_TMP.new" "$CK_TMP.in" "$CK_TMP.hooks"' EXIT
# The packs installed here (checks.d/<repo-id>.md, written by pack.sh) are composed in too, so reinstalling the runtime never drops their rows.
if _ck_err="$(sh "$SRC/check-registry-generate.sh" --core "$SRC/../CHECKS.md" --packs "$DIR/checks.d" 2>&1 >"$CK_TMP")"; then CK_SRC="$CK_TMP"
else
  il_refuse "the private layer's checks.md or an installed pack's does not compose into the register: $(printf '%s' "$_ck_err" | sed -n 's/^.*FAIL[: ]*//p' | head -1)" \
    "sh $SRC/check-registry-generate.sh --packs '$DIR/checks.d'   # names the line; the private layer is CONTRACTS/private-layer.md, a pack's is CONTRACTS/pack.md"
fi
# THE REQUIRED-CHECKS LIST INSTALLS COMPOSED TOO (harbor#1149): bin/required-checks.tsv is harbor's own rows plus the private
# layer's required-checks.tsv (the rows whose repo cannot be named in core), and exactly core when that layer has none. An installed gate-merge-stack
# has no roots.sh to find a layer with, so it reads the sum from beside itself. A file that does not compose refuses the install.
RC_SRC="$SRC/../CONTRACTS/required-checks.tsv"
if _rc_err="$(sh "$SRC/gate-required-generate.sh" --core "$SRC/../CONTRACTS/required-checks.tsv" 2>&1 >"$RC_TMP")"; then RC_SRC="$RC_TMP"
else
  il_refuse "the private layer's required-checks.tsv does not compose with core's: $(printf '%s' "$_rc_err" | sed -n 's/^.*FAIL[: ]*//p' | head -1)" \
    "sh $SRC/gate-required-generate.sh   # names the line; the private layer is CONTRACTS/private-layer.md"
fi
data_src() { case "${1%%:*}" in CHECKS.md) printf '%s' "$CK_SRC" ;; CONTRACTS/required-checks.tsv) printf '%s' "$RC_SRC" ;; *) printf '%s' "$SRC/../${1%%:*}" ;; esac; } # <checkout path>:<config-dir path> -> the bytes to install
for f in $FILES; do
  if [ ! -f "$DIR/bin/$f" ]; then log_note "bin/$f (new)"
  elif cmp -s "$(_src "$f")" "$DIR/bin/$f"; then log_note "bin/$f (replace, identical)"
  else log_note "bin/$f (replace)"; fi
done
for _p in $SUITE; do
  if [ -f "$DIR/${_p#*:}" ]; then log_note "${_p#*:} (replace)"; else log_note "${_p#*:} (new)"; fi
done
for _p in $DATA; do
  if [ -f "$DIR/${_p#*:}" ]; then log_note "${_p#*:} (replace)"; else log_note "${_p#*:} (new)"; fi
done
if [ "$RC_SRC" = "$RC_TMP" ] && ! cmp -s "$RC_TMP" "$SRC/../CONTRACTS/required-checks.tsv"; then
  log_note "bin/required-checks.tsv is composed: core plus $(( $(grep -c '^[^#[:space:]]' "$RC_TMP") - $(grep -c '^[^#[:space:]]' "$SRC/../CONTRACTS/required-checks.tsv") )) row(s) from the private layer"
fi
# A merge gate that gets smaller is the one change of this install the operator must see at the approval, and the private layer's
# file (not a protected path) is how it can: a row of the installed list that the new list lacks is named, not just counted.
if [ -f "$DIR/bin/required-checks.tsv" ]; then
  grep '^[^#[:space:]]' "$RC_SRC" 2>/dev/null | sort -u > "$RC_TMP.new" || :
  _rcdrop="$(grep '^[^#[:space:]]' "$DIR/bin/required-checks.tsv" 2>/dev/null | sort -u | comm -23 - "$RC_TMP.new" | tr '\t' ' ')" || _rcdrop=""
  if [ -n "$_rcdrop" ]; then
    log_warn "bin/required-checks.tsv DROPS $(printf '%s\n' "$_rcdrop" | wc -l | tr -d ' ') required-check row(s) the installed copy has, so those repos' local merge gate gets smaller: $(printf '%s\n' "$_rcdrop" | paste -sd';' - | sed 's/;/; /g') (a row left core or the private layer's required-checks.tsv, or the layer is not found)"
  fi
fi
if [ "$CK_SRC" = "$CK_TMP" ] && ! cmp -s "$CK_TMP" "$SRC/../CHECKS.md"; then
  _nreg() { awk '/^## / { p = ($0 ~ /^## Register/) } p && /^\| `/ { n++ } END { print n + 0 }' "$1"; }
  log_note "bin/CHECKS.md is composed: core plus $(( $(_nreg "$CK_TMP") - $(_nreg "$SRC/../CHECKS.md") )) register row(s) from the private layer and installed packs"
fi
# Named in the dry run whether or not it will be touched. "skip" is the answer to
# a question the operator would otherwise have to go read the source to settle —
# whether this installer is about to put a session-blocking gate on a box that
# never asked for one. Silence would read as "not considered".
for f in $REFRESH_ONLY; do
  if [ -f "$DIR/bin/$f" ]; then log_note "bin/$f (refresh — already installed)"
  else log_skip "bin/$f — not installed here; B6 installs only via floor-install.sh --with-b6"; fi
done
log_note "statusLine → command + refreshInterval ${REFRESH}s"
# ANNOUNCED FOR THE SAME REASON THE PINS ARE (harbor#275): a settings.json key the
# dry run never mentions is a key the operator did not know this installer owns.
log_note "subagentStatusLine → command (one row per live subagent)"
log_note "SessionStart += context-resolve.sh (append-only, idempotent)"
log_note "Stop, PostToolUseFailure and the rest: the hook engines, as bin/deploy-hooks.sh plans them below"
log_skip "one-word commands (idea, memory, gcx, gcloud): CONTRACTS/shims.tsv owns them, through shim-install (harbor#708)"
# The engines' wiring, asked of the renderer here as in --apply, so a bad manifest refuses the dry run too.
if _hk_plan="$(sh "$HOOKS" --plan "$DIR" --root "$SRC/.." 2>"$CK_TMP.hooks")"; then
  while IFS="$(printf '\t')" read -r _hv _he _hev _hm _ht; do
    [ -n "$_hv" ] || continue
    case "$_hv" in
      off) log_skip "$_hev: $_he.sh NOT wired: $DIR/$_he.off is present; to re-enable: rm it, then re-run" ;;
      removed) log_skip "$_hev: $_he.sh NOT wired: it was removed from settings.json by hand; to re-enable: add it back to $DIR/settings.json, and the next run keeps it" ;;
      *) log_note "$_hev ($_hm): $_he.sh — $_hv" ;;
    esac
  done <<EOF
$_hk_plan
EOF
else
  il_refuse "the hook engines' manifests do not render: $(sed -n 's/^.*FAIL[: ]*//p' "$CK_TMP.hooks" | head -1)" "sh $HOOKS --check"
fi
_hk_moves="$(printf '%s\n' "${_hk_plan:-}" | grep -cE '^(wire|prune)' || :)"
if [ "$(jq -S '{statusLine, subagentStatusLine, hooks}' "$S")" = "$(printf '%s' "$NEW" | jq -S '{statusLine, subagentStatusLine, hooks}')" ] && [ "$_hk_moves" = 0 ]
then log_ok "settings.json already carries every key and hook above"
else log_note "settings.json: the keys and hooks above would be merged in"; fi

# ── would this deploy REMOVE work that is already installed? (harbor#115) ────
# Asked in BOTH modes, and now a refusal in both (the install standard's dry-run rule): a dry
# run that exits 0 over a regression is how deploy's plan phase missed the apply that failed.
# "The check said no" and "the check could not run" stay two answers (harbor#313).
if [ ! -f "$SRC/install-stamp.sh" ]; then
  il_refuse "the regression check could not run: install-stamp.sh is not beside this script ($SRC)" \
    "sh ~/port/harbor/bin/runtime-install.sh --apply $(il_spell)"
elif _st="$(sh "$SRC/install-stamp.sh" --check "$DIR" runtime-install 2>&1)"; then
  log_ok "no regression against what is installed (install-stamp)"
else
  il_loss "this source lacks work already installed in $DIR ($(printf '%s\n' "$_st" | sed -n 's/^  FAIL: //p' | head -1))" \
    "$(il_cmd --apply --accept-loss)"
  while IFS= read -r _l; do [ -z "$_l" ] || log_note "$_l"; done <<EOF
$(printf '%s\n' "$_st" | sed -n 's/^  note: //p')
EOF
fi
il_stop
if [ "$IL_APPLY" -eq 0 ]; then
  [ "$IL_REFUSED" -eq 1 ] || il_apply_next runtime
  log_end; exit $?
fi

mkdir -p "$DIR/bin"
il_backup "$S" || { log_end; exit 1; }
# The pre-run bytes of every file this run REPLACES with different content; identical bytes lose nothing.
for f in $FILES $REFRESH_ONLY; do
  if [ -f "$DIR/bin/$f" ] && ! cmp -s "$(_src "$f")" "$DIR/bin/$f"; then il_backup "$DIR/bin/$f" || { log_end; exit 1; }; fi
done
for _p in $SUITE $DATA; do
  if [ -f "$DIR/${_p#*:}" ] && ! cmp -s "$(data_src "$_p")" "$DIR/${_p#*:}"; then il_backup "$DIR/${_p#*:}" || { log_end; exit 1; }; fi
done
for f in $FILES; do il_install_exec "$(_src "$f")" "$DIR/bin/$f"; il_manifest "bin/$f"; done
log_ok "copied $(printf '%s\n' $FILES | wc -l | tr -d ' ') files into $DIR/bin"
for _p in $SUITE; do
  mkdir -p "$DIR/$(dirname "${_p#*:}")"
  case "${_p#*:}" in
    bin/*) il_install_exec "$SRC/../${_p%%:*}" "$DIR/${_p#*:}" ;;
    *) cp "$SRC/../${_p%%:*}" "$DIR/${_p#*:}"; chmod 0644 "$DIR/${_p#*:}" ;;
  esac
  il_manifest "${_p#*:}"
done
for _p in $DATA; do
  mkdir -p "$DIR/$(dirname "${_p#*:}")"; cp "$(data_src "$_p")" "$DIR/${_p#*:}"; chmod 0644 "$DIR/${_p#*:}"
  il_manifest "${_p#*:}"
done
log_ok "data files read beside bin/: $(for _p in $DATA; do printf '%s ' "${_p#*:}"; done | sed 's/ $//')"
log_ok "the restore-path suite and its harness: $(for _p in $SUITE; do printf '%s ' "${_p#*:}"; done | sed 's/ $//')"
# ── the suite payload manifest · DATA, derived here, read by failure-capture ──
# FC-5 subtracts the test suite's own traffic from the recurrence count, because
# floor-test.sh fires the REAL guards and every expect_block case lands a genuine
# block record in the live ledger — measured 2026-09-06, 222 of 555 (40%), and
# four of the daily judge's five warns were the suite's CREDSTORE cases.
#
# THE SUITE ITSELF MUST NOT SHIP, and that was measured rather than assumed:
# putting floor-test.sh in FILES took lint X7 from 1 advisory to 9, all eight of
# them TRUE — an installed suite invokes eight scripts no installer ships, so what
# would arrive is a 474K harness that cannot run. Its PAYLOADS are the only part
# the judge needs, and they are 28K.
#
# NOT +x, and it is not a script: it is one payload per line, kind-prefixed `C`
# for a command and `P` for a path, which is exactly the shape failure-capture's
# own scan of the suite produces. One parse, two origins, no second spelling.
#
# BESIDE THE SCRIPTS, NEVER IN THE CONFIG ROOT. The salt lives in the root safely
# because a wrong salt makes every exclusion MISS; this file fails the other way —
# an appended line deletes a real block from the judge — so it belongs in the
# directory guard-selfedit and the floor-surface rules already defend, in the same
# trust domain as the script that reads it.
#
# REGENERATED ON EVERY INSTALL, so it cannot drift the way a hand-kept copy would,
# and it lags the repo only as far as the install does — which is renew-check's
# existing question, not a new one.
# harbor#727: the floor suite is tests/floor/floor-test.sh, its parts and their fixture.
_ftd="$SRC/../tests/floor"
if [ -f "$_ftd/floor-test.sh" ]; then
  for _ftf in "$_ftd"/floor-fixture.sh "$_ftd"/floor-test.sh "$_ftd"/floor.*-test.sh; do
    [ -f "$_ftf" ] || continue
    sed -n "s/.*bash_j '\([^']*\)'.*/C\1/p" "$_ftf"
    sed -n 's/.*edit_j [A-Za-z][A-Za-z]* "\([^"]*\)".*/P\1/p' "$_ftf"
  done | sort -u > "$DIR/bin/.helm-suite-payloads"
  chmod 0644 "$DIR/bin/.helm-suite-payloads"
fi
# The refresh-only copy, guarded by presence. Note the test is on $DIR/bin/$f and
# not on a flag: the box itself is the record of whether B6 was opted into, and
# it cannot go stale the way a flag can.
_b6_refreshed=""
for f in $REFRESH_ONLY; do
  [ -f "$DIR/bin/$f" ] || continue
  il_install_exec "$(_src "$f")" "$DIR/bin/$f"; il_manifest "bin/$f"
  _b6_refreshed="${_b6_refreshed}${_b6_refreshed:+ }$f"
done
if [ -n "$_b6_refreshed" ]; then log_ok "b6: $_b6_refreshed refreshed (already installed here)"
else log_skip "b6: not installed here — guard-integrity.sh left alone"; fi
# The engines' entries, rendered now that their files are in $DIR/bin: the renderer refuses to wire a script not there.
printf '%s' "$NEW" > "$CK_TMP.in"
NEW="$(sh "$HOOKS" --settings "$DIR" --in "$CK_TMP.in" --root "$SRC/.." 2>"$CK_TMP.hooks")" \
  || { log_fail "the hook engines' wiring did not render: $(sed -n 's/^.*FAIL[: ]*//p' "$CK_TMP.hooks" | head -1)"; log_nofix "sh $HOOKS --check"; log_end; exit 1; }
il_write_json "$NEW" "$S" || { log_end; exit 1; }
sh "$HOOKS" --record "$DIR" --root "$SRC/.." >/dev/null 2>"$CK_TMP.hooks" \
  || log_warn "settings.json is written, but what is wired was not recorded, so a binding removed by hand may come back on the next run: $(sed -n 's/^.*FAIL[: ]*//p' "$CK_TMP.hooks" | head -1)"
log_ok "settings.json: statusLine, subagentStatusLine and the hooks merged; the old bytes are in $IL_BK"

# THE PINS THIS INSTALLER JUST INVALIDATED. Two files in FILES — guard-lib.sh
# and context-resolve.sh — are CONTENT-PINNED in .helm-pins/ and checked by B6 at
# every SessionStart. Replacing them without saying so left the box in exactly
# the state this installer's header claims to avoid: "an installer that leaves
# the box in drift has handed the operator a false alarm to investigate". It was
# worse than a false alarm — B6 returns continue:false, so the NEXT SESSION WAS
# BLOCKED, by a tool the operator had just been told to run.
#
# It reports rather than re-pins, and that is the point. Refreshing the pin on
# the guard library is re-baselining the thing that judges the agent, which
# CONSTITUTION § "Encoding a fix is a human-gated act" reserves for a person. An
# installer that did it silently would make B6 blind to an installer-shaped
# change — the one shape it is most worth catching.
#
# ONLY THE FILES B6 ACTUALLY CHECKS, asked rather than restated: B6 checks every pin it finds except
# its own (guard-integrity.sh, 2026-08-14), so a pin that exists and disagrees is one it will block on.
_pin_drift=""
if [ -d "$DIR/.helm-pins" ]; then
  for f in $FILES; do
    _p="$DIR/.helm-pins/$f.sha256"
    [ -f "$_p" ] || continue
    _want="$(cat "$_p" 2>/dev/null)"
    _have="$(_sha < "$DIR/bin/$f" 2>/dev/null || true)"
    [ "$_want" = "$_have" ] || _pin_drift="${_pin_drift}${_pin_drift:+ }$f"
  done
fi
# B6's OWN pin, tracked apart from $_pin_drift because the CONSEQUENCE differs: nothing reads it back
# (B6 does not check B6), so its staleness never blocks a session and must not borrow the banner.
_b6_pin_stale=""
for f in $_b6_refreshed; do
  _p="$DIR/.helm-pins/$f.sha256"
  [ -f "$_p" ] || continue
  [ "$(cat "$_p" 2>/dev/null)" = "$(_sha < "$DIR/bin/$f" 2>/dev/null || true)" ] \
    || _b6_pin_stale="${_b6_pin_stale}${_b6_pin_stale:+ }$f"
done

# RE-PIN. This installer just wrote settings.json, so the teeth pin is now stale
# by our own hand. Leaving that would hand the operator a drift alarm caused by
# the tool that told them to run it — and would make B6, once installed, block
# every session. --repin adds no deny entry, so a withdrawn entry stays withdrawn.
if [ -f "$DIR/.helm-floor-teeth" ] || [ -f "$DIR/.sec0-baseline.sha256" ]; then
  _fd_rc=0; _fd="$(il_run sh "$SRC/floor-deny.sh" --repin 2>&1)" || _fd_rc=$?
  if [ "$_fd_rc" -eq 0 ]; then
    log_ok "re-pinned: teeth + sec0 baseline now match the settings.json just written"
  else
    log_fail "floor-deny --repin exited $_fd_rc, so the teeth pin is behind settings.json: $(printf '%s\n' "$_fd" | tail -1)"
    log_fix "sh $SRC/floor-deny.sh --repin $(il_spell)"
  fi
fi

log_note "verify the work-log is alive, asserting the record and not the exit code: P=\$(mktemp -d); git -C \"\$P\" init -q; printf '{\"session_id\":\"probe-1\",\"cwd\":\"'\"\$HOME\"'\"}' > \"\$P/payload.json\"; /bin/sh $DIR/bin/context-resolve.sh < \"\$P/payload.json\"; HARBOR_LOG_DIR=\"\$P\" /bin/sh $DIR/bin/worklog-push.sh < \"\$P/payload.json\"; find \"\$P/WORK\" -type f   # expect ONE session record"

# NOT A FALSE ALARM (harbor#285): floor-install copies then re-pins its own payload, so a stale pin on
# a file it carries is a note naming it; only a pin it does not carry keeps the banner. Read from
# floor-install.sh, never copied here: an unreadable list makes every file banner-worthy.
_fi_pay=" $(sed -n -e "s/^GUARDS='\(.*\)'\$/\1/p" -e "s/^RECOVERY='\(.*\)'\$/\1/p" "$SRC/floor-install.sh" 2>/dev/null | tr '\n' ' ') "
_pin_cov=""; _pin_hard=""
for f in $_pin_drift; do
  case "$_fi_pay" in *" $f "*) _pin_cov="${_pin_cov}${_pin_cov:+ }$f" ;; *) _pin_hard="${_pin_hard}${_pin_hard:+ }$f" ;; esac
done
if [ -n "$_pin_cov" ]; then
  if [ "${HARBOR_DEPLOY:-0}" = 1 ]; then
    log_note "content pins behind for: $_pin_cov — floor-install re-pins them next in this deploy"
  else
    log_note "content pins behind for: $_pin_cov — floor-install re-pins them: sh $SRC/floor-install.sh $(il_spell) --apply, next in the documented order (B6 blocks a new session until it runs)"
  fi
fi
if [ -n "$_pin_hard" ]; then
  log_warn "B6 CONTENT PINS ARE NOW STALE — the next SessionStart will be BLOCKED: this install replaced content-pinned file(s): $_pin_hard (both copies came from this checkout, so only the pin is behind; re-pinning is YOURS to do, not an installer's)"
  log_fix "for g in $_pin_hard; do $( command -v sha256sum >/dev/null 2>&1 && echo sha256sum || echo 'shasum -a 256' ) < $DIR/bin/\$g | awk '{print \$1}' > $DIR/.helm-pins/\$g.sha256; done; /bin/sh $DIR/bin/guard-integrity.sh < /dev/null"
  log_note "or go back to before the last deploy: sh $DIR/bin/restore.sh $(il_spell)   (the plan; add --apply)"
fi

# RECORD WHAT WAS DEPLOYED (harbor#115), only after the apply ran; --live is install-stamp's own gate.
_stw_rc=0
if [ "$IL_LIVE" -eq 1 ]; then _stw="$(sh "$SRC/install-stamp.sh" --write "$DIR" runtime-install --live 2>&1)" || _stw_rc=$?
else _stw="$(sh "$SRC/install-stamp.sh" --write "$DIR" runtime-install 2>&1)" || _stw_rc=$?; fi
if [ "$_stw_rc" -eq 0 ]; then
  log_ok "install-stamp: recorded runtime-install in $DIR/.helm-install-stamp"
else
  log_warn "install-stamp could not record this deploy, so the next run cannot detect a rollback: $(printf '%s\n' "$_stw" | tail -1)"
  log_fix "sh $SRC/install-stamp.sh --write '$DIR' runtime-install$( [ "$IL_LIVE" -eq 1 ] && echo ' --live' )"
fi

# What this run installed, one row per file (install standard §3); B6 never reads it.
il_manifest_write || { log_end; exit 1; }
if [ -n "$_b6_pin_stale" ]; then
  log_note "$_b6_pin_stale was refreshed, so its pin in .helm-pins/ is behind; nothing reads that pin back (B6 does not check itself), so the next session is unaffected, and floor-install.sh --with-b6 rewrites it"
fi
log_end; exit $?
