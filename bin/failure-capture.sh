#!/usr/bin/env sh
# M5 · FailureCapture (harbor#44) — JUDGE the guard-decision ledger.
#
#   sh failure-capture.sh [--live | <config-dir>] [--json] [--with-probes]
#   sh failure-capture.sh [--live | <config-dir>] --exclusion-set   (harbor#560: the digests FC-5 drops)
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md): ten independent rules over one
# parsed record set, where no rule can affect another. Splitting them would
# relocate lines without shrinking any blast radius, and would fork the reader —
# and the reader is where three of the five review defects lived, so it is the one
# part that must have exactly one implementation.
#
# Exit 0 = nothing in the ledger says the floor is failing. Exit 1 = something
# does. Exit 2 = bad usage.
#
# READ-ONLY WITH RESPECT TO THE TREE IT INSPECTS — stated precisely, because the
# first draft said "opens files and writes none" and that was false: it writes
# working files under TMPDIR on every run, and review measured five of them left
# behind at a pre-planted path. It writes NOTHING under the config dir, the repo,
# or MEMORY/, and `tests/hooks/failure-capture-test.sh` compares the inspected tree before and
# after to keep that true. Its own scratch space is a `mktemp -d` under `umask 077`
# so the name is unpredictable and the contents are owner-only; a symlink planted
# at a guessable path was the hole that made the weaker wording matter.
#
# IT EXECUTES NO CODE FROM THE DIRECTORY UNDER INSPECTION. This is the sharpest
# thing review found: the first draft sourced `<dir>/bin/guard-lib.sh` to reuse
# the digest function, and a hostile copy in an inspected tree could redefine
# `finding()` and wipe three accumulated crit findings, so the tool reported
# "nothing in the ledger says the floor is failing" and exited 0. It now sources
# the guard-lib.sh SITTING NEXT TO ITSELF: same trust domain as this script (write
# there and you can rewrite this file anyway), version-controlled, and hash-pinned
# by B6 on a live box. The header used to justify the old form by citing
# guard-lib.sh's "no side effects at source time" contract — which is a property of
# the REPO's copy, not of whatever copy the argument points at, and citing it was a
# source that existed without supporting the claim (№2.5).
#
# WHY IT EXISTS. L1 (harbor#41) made every guard decision durable and
# bin/observe-report.sh PRINTS them. Nothing JUDGES them. Those are different
# jobs: a report answers "what happened", and the question this ticket was filed
# for is "is something failing here, and is it worth healing". Upstream's
# `HookHealer` repairs one class automatically — the exec-bit class, which Harbor
# does not have, because guards are invoked as `/bin/sh <path>`. COVERAGE.md
# records it as declined and names this as the part that was actually missing:
# the thing that NOTICES.
#
# THE SCOPE IS THE LEDGER, AND THAT IS A DECISION. Two rules answering one
# question is the drift class the T rules exist for, so this reads the ledger and
# the sink's own filesystem state and nothing else. It does not check hooks
# (reference-check.sh REF-1), dependencies (doctor.sh), the config surface
# (pulse.sh), citations (lint K1/T3) or document staleness (freshness.sh). The
# ledger is the one signal source on this box that nothing was watching.
#
# THREE THINGS MEASURED ON THE LIVE BOX ON 2026-08-04, EACH OF WHICH CHANGED A
# RULE HERE. None was predicted; all three came from asking the box.
#
#   1. THE TWO SESSION CENSUSES DISAGREE — AND THE FIRST EXPLANATION WAS WRONG,
#      which is the most instructive thing in this file. floor-observe.sh writes
#      one `session armed` record per SessionStart and guard-integrity.sh writes
#      one record per run (guard-integrity.sh:221-226, :287), so the counts looked
#      like they had to match. They did not — 30 against 49 — and an earlier draft
#      of this file reported that as a crit defect in floor-observe.sh.
#
#      IT WAS `harbor verify`. floor-verify.sh:196-197 invokes guard-integrity.sh
#      directly as its B6 status check, and that path records, so every verify run
#      adds one integrity record with no session record. Reconciled per day against
#      the verify-run count: 27 runs against a gap of 19 — fully consistent with
#      nothing being dropped at all. The bad grep that hid it was run from the
#      wrong directory with stderr discarded, which is why nothing here may rest a
#      negative on a `grep` it does not control.
#
#      So FC-1 subtracts the verify-run count, will not fire at all when that count
#      is unavailable, and says "does not reconcile" at WARN rather than naming a
#      culprit — guard-integrity is also invoked by floor-install --with-b6 and by a
#      paste-line runtime-install.sh prints, and no field distinguishes any of them.
#      The gap still matters, because observe-report.sh:110-117 divides overrides by
#      `NOVR + NARM`: a short `armed` count makes the override rate read WORSE, not
#      better — measured, 33.3% became 50.0% with five armed records removed.
#
#   2. `advise` HAS NO HUMAN-VISIBLE SURFACE. observe-report's report prints
#      total/block/allow/wrapper-deny/session-gate (observe-report.sh:134-135) and
#      `armed`/`override` under overrides. `advise` appears in --json alone. So 19
#      `integrity advise` records — B6 telling the operator their instruction
#      surfaces had drifted from the pins — were invisible in every mode a human
#      runs. That is FC-4.
#
#   3. observe-report --fp's TOP ROWS ARE ITS OWN VERIFIER. `harbor verify` fires
#      known-blocked shapes through the real guards (floor-verify.sh `probe` lines),
#      and each firing appends a real block record. The live ledger's six
#      highest-recurrence digests were exactly those six shapes, at 27-28
#      occurrences each, ranked above every genuine operator block — and nothing
#      said so. pulse.sh's header refuses to fire a guard for precisely this
#      reason: a probe must not manufacture the evidence its own system learns
#      from. A detector whose loudest finding is its own tooling is one the
#      operator mutes, and №2.11 calls that a defect rather than safety. So FC-5
#      excludes the probe digests, and `--with-probes` shows what it dropped,
#      because an exclusion the operator cannot audit is one they must take on
#      faith.
#
# THE PROBE LIST IS DERIVED FROM floor-verify.sh, NEVER COPIED, and the first cut
# of this file got that wrong in a way worth recording. It embedded the six probe
# payloads as literals — and guard-egress BLOCKED THE WRITE on `secret-to-disk`,
# because one of them carries a provider-token shape. The guard was right twice
# over: the literal is a token shape going to disk in cleartext, and a copy of a
# list that lives in another file is the drift class this repo keeps paying for.
# So the payloads are read out of the sibling floor-verify.sh at runtime, the way
# floor-hook.sh resolves guard-lib.sh from its own directory. A seventh probe, if
# one is ever added, is picked up for free — there are six today — no mirror can
# rot, and nothing here needs a lint seam to stay honest.
#
# THE TWO SEVERITIES MEAN TWO DIFFERENT THINGS, and keeping them apart is what
# stops this tool crying wolf. **crit = the floor is broken or blind** — it cannot
# reach a verdict, it is dropping its own records, or it is locking the operator
# out with a recovery that does not work. **warn = the rules may be wrong** — a
# recurring block, an unread advisory, a recurrence counter that has stopped
# correlating. Only the first class is an emergency, and a detector that ranks a
# rule-tuning matter alongside a blind ledger teaches the reader to skim both.
# `unknown` is reserved for a source that could not be read, and never renders as
# ok. The vocabulary is pulse.sh's, verbatim, so a pulse check over this JSON is
# one line rather than a translation layer.
#
# IT NEVER REPAIRS ANYTHING, and that is not caution. Every finding points at a
# surface guard-selfedit.sh protects — the config dir, bin/, the pins, the sink —
# so a version of this tool that could fix its own findings would be a version
# that can disable the floor. CONSTITUTION § "Fix the system, not your notes"
# states the general rule: the system may observe continuously and propose in
# batch, and may not promote its own observations into a guard without a person
# approving the change. The narrow deterministic self-repair it exempts (a lost
# exec bit, a stale cache) is not what any rule below finds. Each finding carries
# its repair as TEXT, for a human at their own terminal.
#
# CITATIONS INTO floor-observe.sh AND guard-lib.sh NAME THE FUNCTION OR SECTION,
# not a line range, and that is deliberate rather than inconsistent: harbor#119 is
# open and rewrites both files to derive the host key from a stable name, which
# moves every line number below its edits. A citation that rots the moment a
# reviewed PR lands is a copy of a fact, and this file's whole subject is copies
# that drift while reading correctly. Line ranges are kept where the target is
# stable.
#
# WHAT IT CANNOT SEE, said plainly because a checker's silence must never be read
# as health: only what reached the ledger. A guard that was never wired records
# nothing (reference-check.sh REF-1 and pulse.sh's floor check own that); a
# session under HELM_DISABLE_FLOOR evaluates no rules at all, which is why an
# `override` is a fact about the operator and never an attribution to a rule; and
# stderr text is gone the moment the session closes.
#
# IT DOES NOT DETECT TOTAL SILENCE, and an earlier draft of this header claimed the
# opposite. FC-1 fires on an ASYMMETRY between two censuses, so a failure that
# stops BOTH writers — a wiped or unreadable `bin/`, the most severe floor failure
# there is — produces no asymmetry, and pre-existing records keep NREC above zero
# so FC-0 stays quiet too. Measured against a fixture: exit 0, "nothing in the
# ledger says the floor is failing". FC-1 catches PARTIAL blindness, which is the
# common case and was the live defect here; total blindness belongs to the tools
# that read the wiring rather than the ledger — reference-check.sh REF-1 sees hooks
# pointing at absent scripts, and pulse.sh's floor check sees guard files missing.
# A clock-based "nothing recorded lately" rule was considered and left out: an idle
# machine is indistinguishable from a dead one at this layer, and that false
# positive is how a channel gets muted (№2.11).
set -u

SELF="$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)" || SELF=""
# The human report is in CONTRACTS/logging.md's line shape (harbor#771, converted by harbor#560). The
# --json and --exclusion-set outputs are data and print no log line, so only the human mode needs it.
_LOGLIB=0
if [ -n "$SELF" ] && [ -f "$SELF/log-lib.sh" ]; then . "$SELF/log-lib.sh"; log_init failure-capture; _LOGLIB=1; fi
DIR=""
JSON=0
PROBES=0
EXCL_SET=0
for a in "$@"; do
  case "$a" in
    --live)        [ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    --json)        JSON=1 ;;
    --with-probes) PROBES=1 ;;
    --exclusion-set) EXCL_SET=1 ;;
    -h|--help)
      printf 'usage: failure-capture.sh [--live | <config-dir>] [--json] [--with-probes]\n'
      printf '  Judges the guard-decision ledger L1 writes. Exit 1 = a finding.\n'
      printf '  --with-probes  keep the verifier own probe shapes in the recurrence count\n'
      printf '  --exclusion-set  print the probe and suite digests FC-5 drops, one "<source> <digest>" per line;\n'
      printf '                   exit 1 when they cannot be derived (no ledger, no salt, no floor-verify.sh)\n'
      exit 0 ;;
    -*) printf 'failure-capture: unknown option: %s\n' "$a" >&2
        printf 'usage: failure-capture.sh [--live | <config-dir>] [--json] [--with-probes]\n' >&2
        exit 2 ;;
    *)  [ -n "$DIR" ] && { printf 'failure-capture: more than one config dir given\n' >&2; exit 2; }
        DIR="$a" ;;
  esac
done
if [ "$EXCL_SET" = 1 ] && { [ "$PROBES" = 1 ] || [ "$JSON" = 1 ]; }; then
  printf 'failure-capture: --exclusion-set prints digests only; it takes neither --with-probes nor --json\n' >&2
  exit 2
fi
[ -n "$DIR" ] || DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
while [ "${DIR%/}" != "$DIR" ] && [ "$DIR" != "/" ]; do DIR="${DIR%/}"; done

# An absent config dir is an ANSWER, not a misuse — reference-check.sh:57-63 and
# floor-verify.sh:44 make the same call. Nothing is installed, so nothing failed.
if [ ! -d "$DIR" ]; then
  if [ "$JSON" = 1 ]; then printf '{"dir":"%s","installed":false,"worst":"ok","findings":[]}\n' "$DIR"
  else printf 'failure-capture: no config dir at %s — nothing is installed here.\n' "$DIR" >&2; fi
  exit 0
fi

# B9: a missing jq must never read as a clean run. guard-bash.sh exited 0 on
# 'rm -rf /' for exactly this reason. Exit 1, not 2 — a caller filters 2 out as
# "I typed it wrong", and would filter away the one result it must not ignore.
if ! command -v jq >/dev/null 2>&1; then
  printf 'failure-capture: jq not found — the ledger cannot be read.\n' >&2
  printf '  This is NOT a clean result. Install jq, then re-run.\n' >&2
  exit 1
fi

# ── the recency horizon (harbor#211) ────────────────────────────────────────
# EVERY RECURRENCE RULE HERE READ THE WHOLE RETAINED LEDGER AND CALLED THE ANSWER
# A CURRENT STATE. FC-3 escalated to crit on gates spanning two distinct days
# with no cutoff anywhere, so the live box carried a standing crit for gates on
# 2026-08-02 and 2026-08-13 — eleven days apart, each one drift, each remediated
# from the operator's own terminal. The verdict could not go green: no terminal
# action clears it, only deleting ledger history. FC-2 was the same defect in
# miniature, a single 2026-08-06 record reported as current state for ten days.
#
# session-verdicts.sh speaks on crit, so that landed on the one channel built to
# be believed, every session, for a problem that was fixed — CONSTITUTION §2.11,
# and the exact wallpaper failure session-verdicts.sh was written to prevent.
#
# THE HORIZON DECIDES SEVERITY, NOT EXISTENCE. Warns are deliberately not
# surfaced at SessionStart (session-verdicts.sh § the crit loop), so a recurrence
# that has stopped is demoted to the batch-review tier CARRYING ITS DATE rather
# than deleted. Dropping it outright would repeat the mistake FC-4 exists to fix:
# a verdict with no human-visible surface.
#
# SEVEN DAYS, and the number is measured rather than chosen. Fourteen would have
# left the live 08-02/08-13 pair inside one window and changed nothing at all,
# which is the whole reason this ticket exists. Seven matches the rule's own
# stated premise — "the drift came back after a night, so whatever cleared it did
# not hold" — and gives a fortnight-apart pair the two independent episodes it is.
#
# NOT `date` ALONE. HARBOR_FC_NOW pins today so a fixture dated 2026-08-02 does
# not age out of its own test next week, which would turn this suite into a
# clock-dependent time bomb — a test that starts failing for a reason unrelated
# to the thing it guards. BSD `date -j -v` first, GNU `date -d` second; if
# NEITHER resolves, FC_CUTOFF stays empty and every rule reverts to all-history.
# Fail LOUD: an unreadable clock must never be the thing that silences a crit.
FC_HORIZON="${HARBOR_FC_HORIZON_DAYS:-7}"
case "$FC_HORIZON" in ''|*[!0-9]*|0) FC_HORIZON=7 ;; esac
FC_TODAY="${HARBOR_FC_NOW:-$(date -u +%F 2>/dev/null || true)}"
case "$FC_TODAY" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) FC_TODAY="" ;;
esac
FC_CUTOFF=""
if [ -n "$FC_TODAY" ]; then
  FC_CUTOFF="$(date -u -j -v-"${FC_HORIZON}"d -f '%Y-%m-%d' "$FC_TODAY" +%F 2>/dev/null \
            || date -u -d "$FC_TODAY - $FC_HORIZON days" +%F 2>/dev/null \
            || true)"
  case "$FC_CUTOFF" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) FC_CUTOFF="" ;;
  esac
fi

# FC-4's "still raising it" bound: yesterday or today. Day granularity of the ledger's own dates, so ~24h; the 7d horizon above
# is how far to LOOK for recurrence, not how stale an advisory may be and still count as standing. Empty = no clock: warn loudly.
FC_RECENT=""
[ -z "$FC_TODAY" ] || FC_RECENT="$(date -u -j -v-1d -f '%Y-%m-%d' "$FC_TODAY" +%F 2>/dev/null \
                 || date -u -d "$FC_TODAY - 1 day" +%F 2>/dev/null || true)"
case "$FC_RECENT" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) FC_RECENT="" ;; esac

OBS="$DIR/MEMORY/OBSERVABILITY"
SETTINGS="$DIR/settings.json"

# ── the supersession mark: when was THE FLOOR last installed ────────────────
# THE HORIZON IS A PROXY, AND ON 2026-08-24 IT WAS THE WRONG ONE. A wrapper deny
# says "a guard file was absent or empty at time T". floor-install REPLACES every
# guard wholesale (`cp` per file, no -p), so a record predating it describes a
# floor that no longer exists — a physical fact about the artefacts, not a guess
# about elapsed days. The live box carried the 2026-08-20 record at crit for four
# days while the guards under it had been rewritten twice; §2.11 calls a false
# positive a defect, because an alarm that is not a live failure teaches the
# reader to skim the channel where the real one will appear.
#
# THE floor-install LINE, NOT THE FILE'S mtime, and the first draft had it wrong.
# install-stamp.sh rewrites the WHOLE file through `mv` for whichever installer
# called it (install-stamp.sh:177-180), so `runtime-install --apply` advances the
# mtime without replacing a single guard — and the runtime payload is disjoint
# from the floor's. Reading the mtime therefore reports a floor reinstall that
# never happened and demotes a live failure. The per-installer LINE cannot say
# that: it moves only when floor-install itself writes.
#
# ITS CLOCK IS THE COMMIT DATE, AND THAT ERRS SAFELY. The field is
# `git log -1 --format=%cI` of the installed sha, which is necessarily EARLIER
# than the install that deployed it — so the mark under-states how much has been
# superseded and the rule keeps a crit it might have demoted. Under-demoting is
# the direction to fail in. Rendered at the installing box's offset, its DATE can
# also sit up to a day ahead of the same instant in UTC; a record inside that
# window is one written in the day before the install that fixed it, which is
# the case supersession is about anyway.
#
# DATE GRANULARITY, DELIBERATELY. `.ts[0:10]` is what FC_CUTOFF already compares,
# an offset-bearing stamp and a UTC record cannot be compared lexicographically
# at full precision, and parsing either into epoch needs `date -j -f`, which is
# BSD-only — the portability trap this file avoids everywhere else.
FC_INSTALL_DATE=""
_fc_stamp="$DIR/.helm-install-stamp"
if [ -f "$_fc_stamp" ] && [ ! -L "$_fc_stamp" ]; then
  _fc_iw="$(awk '$1 == "floor-install" { print $3; exit }' "$_fc_stamp" 2>/dev/null || true)"
  case "${_fc_iw:-}" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*) FC_INSTALL_DATE="$(printf '%s' "$_fc_iw" | cut -c1-10)" ;;
  esac
  case "$FC_INSTALL_DATE" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) FC_INSTALL_DATE="" ;;
  esac
fi

# ── the sibling library, sourced ONCE ────────────────────────────────────────
# Two rules need it: FC-5 derives the verifier's probe digests with
# floor_obs_digest, and FC-9 asks floor_host_token which partition key is
# canonical (harbor#119). Sourced here rather than inside FC-5, because the old
# placement was inside a block gated on `--with-probes` being absent, so that flag
# silently took floor_host_token away from FC-9 too.
#
# THE SIBLING, NEVER THE INSPECTED DIRECTORY — see the header. Same trust domain as
# this script; a copy under the argument's tree is data, not code.
GL="$SELF/guard-lib.sh"
GL_OK=0
if [ -n "$SELF" ] && [ -f "$GL" ] && [ ! -L "$GL" ]; then
  # shellcheck source=/dev/null
  { . "$GL"; } 2>/dev/null && GL_OK=1
fi
WORST=ok
FINDINGS=""   # one `rule<TAB>severity<TAB>subject<TAB>breaks<TAB>repair` per line
# `mktemp -d` under `umask 077`, never `${TMPDIR:-/tmp}/fcap.$$`. The predictable
# form was pre-plantable: `mkdir -p` SUCCEEDS on a path that is already a symlink
# to a directory, so every working file landed in the attacker's target and the
# trap then unlinked only the symlink, leaving them behind. Measured by review with
# the PID preserved through `exec`. A PID is a small space and TMPDIR is unset
# under sudo and cron, which puts the base at world-writable /tmp. `mktemp -d`
# creates 0700 with an unguessable name and fails rather than following a link;
# the umask also covers what the SHELL writes for a here-document.
umask 077
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/fcap.XXXXXXXX" 2>/dev/null)" \
  || { printf 'failure-capture: cannot create a work dir\n' >&2; exit 1; }
case "$TMPD" in /*) ;; *) printf 'failure-capture: refusing a relative work dir\n' >&2; exit 1 ;; esac
trap 'rm -rf "$TMPD" 2>/dev/null' EXIT INT TERM HUP

# ok < unknown < warn < crit. `unknown` outranks `ok` deliberately, the ordering
# pulse.sh:318 argues for: "I could not look" is worse news than "I looked and it
# was fine", and a run whose sources were unreadable must not render as a healthy
# zero (DEAD-ENDS DE-14, DE-18).
rank() { case "$1" in ok|info) echo 0 ;; unknown) echo 1 ;; warn) echo 2 ;; crit) echo 3 ;; *) echo 1 ;; esac; }
finding() { # <rule> <severity> <subject> <what-breaks> <repair>
  [ "$(rank "$2")" -gt "$(rank "$WORST")" ] && WORST="$2"
  FINDINGS="$FINDINGS$1	$2	$3	$4	$5
"
}
# Digits or zero, never a stray word: every count below feeds an arithmetic
# comparison, and one empty jq result aborts the run on an illegal number.
num() { case "${1:-}" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$1" ;; esac; }

# ── is the floor wired at all? ───────────────────────────────────────────────
# The predicate for FC-0. A whole-path-segment match on floor-hook.sh, the one
# string this layer cannot be installed without — never a bare `guard-` substring,
# which the ambient prod_guard shim satisfies on a box carrying none of B2-B6
# (status-gen.sh:122-131, DEAD-ENDS DE-22).
FLOOR_WIRED=no
if [ -f "$SETTINGS" ] && jq -e '[.hooks.PreToolUse[]?.hooks[]?.command]
      | map(select(test("(^|/)floor-hook[.]sh([[:space:]]|$)"))) | length > 0' \
      "$SETTINGS" >/dev/null 2>&1; then FLOOR_WIRED=yes; fi

# ── read the ledger ──────────────────────────────────────────────────────────
# Rotated generations first so the series reads oldest → newest; file order is
# authoritative because the sink is bounded by SIZE, not by date
# (floor-observe.sh § "rotation, one generation").
#
# READ PER HOST PARTITION, and carry the partition in an added `_host` field. The
# ledger is host-partitioned because two devices write disjoint subtrees
# (floor-observe.sh § "the host partition"), and THREE of the rules below are meaningless across
# that boundary: a census is a per-machine fact, and so is "the drift came back
# the next day". Measured on a two-host fixture before this was fixed: host A had
# 3 session records against 9 integrity — a 67% drop, crit — and host B, a healthy
# machine without B6, contributed 5 session records that diluted the aggregate to
# 8-against-9, reported as an 11% warn. A real failure rendered as nearly clean is
# the exact shape this tool exists to catch, so it must not commit it.
#
# `_host` is added in flight and never written anywhere: the tool writes nothing,
# and the on-disk record shape is guard-lib.sh's ten keys, which observe-report.sh
# also reads.
#
# THREE THINGS IN THIS BLOCK WERE DEFECTS FOUND BY REVIEW, all of the same family
# — a source that could not be read rendering as a healthy zero, which is the
# inversion this whole tool exists to prevent (DE-14, №2.7):
#
#   NAME MATCHING, not a prefix glob. `guard-decisions.jsonl*` also matches a
#   `.bak`, `.orig`, `~` or `.save` sibling — and every repair line here tells the
#   operator to open the sink from their own terminal, which is exactly when such a
#   file appears. Measured: one `cp` beside the sink doubled every count, and a
#   command blocked twice crossed FC-5's threshold of three and produced a finding
#   for a wall the operator hit twice. Only the two names floor-observe.sh can
#   create are read: the sink, and one numeric rotated generation.
#
#   `awk 1 -- "$file"` PER FILE, never `cat $list`. Two bugs at once. (1) The
#   unquoted list word-split, so a host directory named `host b` — or any config
#   dir path containing a space — silently contributed ZERO records with the errors
#   swallowed; reproduced twice, and in one shape a textbook FC-1 crit rendered as
#   `clean: true`, exit 0. The comment 30 lines below rejects `for _h in
#   $PARTITIONS` for this exact reason and the reader did it anyway. (2) `cat a b`
#   fuses a's newline-LESS last line onto b's first line. floor-observe.sh rotates
#   with `mv -f`, so it will rotate a file killed mid-append — the torn tail this
#   reader promises to survive — and the fused line is then dropped by `fromjson?`,
#   silently costing ONE GOOD RECORD from the live sink. Measured: a matched census
#   reported a FALSE FC-1 warn at exit 1, and the mirror case downgraded a real crit
#   to warn by pushing the gap back under the threshold. `awk 1` re-terminates every
#   record, so the boundary survives.
LEDGERS=""
if [ -d "$OBS" ]; then
  find "$OBS" -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
    2>/dev/null | sort -r > "$TMPD/ledgers" || :
  LEDGERS="$(awk 'END{print NR+0}' "$TMPD/ledgers")"
  case "$LEDGERS" in ''|0) LEDGERS="" ;; esac
fi
NREC=0
REC="$TMPD/rec.jsonl"
: > "$REC"
# read_ledgers <host-label> <file-list-path> <dest> — concatenate with the record
# boundary preserved, tag each record with its partition, drop what will not parse.
#
# The destination became a PARAMETER when the tool-failure ledger arrived
# (harbor#465). Everything above this line — the name match rather than a prefix
# glob, `awk 1 < file` rather than `cat $list`, the torn-tail survival — was paid
# for by four measured defects, and a second reader for the second ledger would
# have started by re-earning all four.
read_ledgers() {
  while IFS= read -r _f; do
    [ -n "${_f:-}" ] || continue
    # `awk 1 < file`, NOT `awk 1 -- file`: BSD awk has no `--` and treats it as a
    # FILENAME ("awk: can't open file --"), so every record silently vanished and
    # the suite went from 55 green to 35 red in one edit. Reading stdin sidesteps
    # operand parsing altogether, and also means a path beginning with `-` cannot
    # be mistaken for an option.
    awk 1 < "$_f" 2>/dev/null
  done < "$2" \
    | jq -c -R --arg h "$1" 'fromjson? // empty | . + {_host:$h}' >> "$3" 2>/dev/null || :
}
if [ -n "$LEDGERS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    find "$_hd" -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
      2>/dev/null | sort -r > "$TMPD/hostfiles" || :
    [ -s "$TMPD/hostfiles" ] || continue
    read_ledgers "$(basename "$_hd")" "$TMPD/hostfiles" "$REC"
  done
  # A ledger file sitting DIRECTLY under OBSERVABILITY belongs to no partition.
  # floor-observe.sh never creates one, so it is either hand-placed or a partition
  # that lost its directory — and dropping it silently would be the same quiet loss
  # the per-host split exists to stop. It is read, and labelled unattributed so the
  # census rules skip it rather than mixing two machines together.
  find "$OBS" -maxdepth 1 -type f \( -name 'guard-decisions.jsonl' -o -name 'guard-decisions.jsonl.[0-9]*' \) \
    2>/dev/null | sort -r > "$TMPD/loosefiles" || :
  [ -s "$TMPD/loosefiles" ] && read_ledgers "(unpartitioned)" "$TMPD/loosefiles" "$REC"
  NREC="$(num "$(awk 'END{print NR+0}' "$REC")")"
fi

# ── the SECOND ledger: tool outcomes (harbor#465) ───────────────────────────
# guard-decisions.jsonl records what the floor DECIDED about a call. It records
# nothing about what the call then DID — so a Read on a path that resolves to
# nothing, a Bash exiting non-zero, a skill invoked by a name that no longer
# exists are all invisible to every rule above. That is harbor#462's class
# exactly: ten dead constitution pointers were followed for 34 days, every follow
# a tool call that found nothing, and not one left a record anywhere.
#
# Read INDEPENDENTLY of the guard ledger, never gated on it. A box can carry one
# and not the other — failure-observe.sh needs no floor, only the sink that
# floor-observe.sh prepares — and gating would make a present ledger read empty
# because a different one was absent.
NTF=0
TFREC="$TMPD/tf.jsonl"
: > "$TFREC"
if [ -d "$OBS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    find "$_hd" -type f \( -name 'tool-failures.jsonl' -o -name 'tool-failures.jsonl.[0-9]*' \) \
      2>/dev/null | sort -r > "$TMPD/tffiles" || :
    [ -s "$TMPD/tffiles" ] || continue
    read_ledgers "$(basename "$_hd")" "$TMPD/tffiles" "$TFREC"
  done
  NTF="$(num "$(awk 'END{print NR+0}' "$TFREC")")"
fi

# Is the recorder wired? Whole-path-segment match, the same shape FLOOR_WIRED
# uses and for the same reason: a bare substring would be satisfied by any hook
# whose path merely contains the name.
TF_WIRED=no
if [ -f "$SETTINGS" ] && jq -e '[.hooks.PostToolUseFailure[]?.hooks[]?.command]
      | map(select(test("(^|/)failure-observe[.]sh([[:space:]]|\"|$)"))) | length > 0' \
      "$SETTINGS" >/dev/null 2>&1; then TF_WIRED=yes; fi

# ── FC-0 · the floor is wired and the ledger says nothing ────────────────────
# THIS TOOL'S OWN BLIND SPOT, CLOSED AT BIRTH. Every rule below reads $REC, so an
# empty ledger yields zero findings and exit 0 — a clean result indistinguishable
# from "there was nothing to check". reference-check.sh shipped with exactly that
# hole and REF-6 was added the same day it was found (reference-check.sh:263-275).
# The predicate is the WIRING, not the directory: a box with no floor correctly has
# no ledger, and calling that a failure is the false positive that gets a checker
# muted (№2.11). A config dir carrying settings.json but no ledger at all is the
# state this fires on, and it is the right one: hooks and guards are running and
# nothing is recording them. (An earlier draft cited sandbox-make.sh as the
# example of the false positive; checked, that is wrong — a sandbox copies
# settings.json AND the live MEMORY tree, ledger included, so it trips neither
# predicate. The reason for keying on the wiring stands; the example did not.)
if [ "$FLOOR_WIRED" = yes ] && [ "$NREC" -eq 0 ]; then
  if [ -z "$LEDGERS" ]; then
    finding FC-0 crit "$OBS" \
      "the floor is wired and no ledger exists — every guard decision on this box is unrecorded, and every other rule here reports clean" \
      "floor-observe.sh is the only component allowed to create the sink, at SessionStart: confirm it is wired, start a session, re-run"
  else
    finding FC-0 crit "$OBS" \
      "the floor is wired, ledger files exist, and not one record parses — the recorder is running and producing nothing readable" \
      "read the newest guard-decisions.jsonl by hand; a zero-byte or non-JSONL sink means floor_log_decision refused every write"
  fi
fi

# --exclusion-set on an empty ledger: there is nothing to match a digest against.
[ "$EXCL_SET" = 0 ] || [ "$NREC" -gt 0 ] || exit 1

if [ "$NREC" -gt 0 ]; then
  # One pass per question, each into a file. `printf | while read … finding` runs
  # the loop in a SUBSHELL where FINDINGS and WORST die with it — a defect that
  # shipped three times in this repo (lint CLI1's first cut, K1's, TS1's) and
  # printed a violation while exiting 0 (lint-conventions.sh:489-495).
  count_of() { jq -r "select($1)|1" "$REC" 2>/dev/null | awk 'END{print NR+0}'; }

  # ── FC-8 · the ledger speaks a schema this tool does not know ──────────────
  # `v` is the record's schema VERSION and it is the field a reader most easily
  # forgets, because today every record carries v:1 and ignoring it costs nothing
  # (guard-lib.sh, floor_log_decision's single printf — ten keys, of which `v` is the literal). The day the
  # writer emits v:2, every count below is computed against fields that may mean
  # something else, and the report would be confidently wrong. Severity `unknown`
  # rather than warn: this is "I could not read it", which №2.7 says to defer on
  # instead of substituting a weaker answer, and pulse.sh:318 ranks above ok for
  # exactly that reason. It is reported FIRST because it qualifies everything after.
  N_UNKNOWN_V="$(num "$(count_of '(.v|tostring) != "1"')")"
  if [ "$N_UNKNOWN_V" -gt 0 ]; then
    _vseen="$(jq -r 'select((.v|tostring) != "1")|.v|tostring' "$REC" 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
    finding FC-8 unknown "schema version(s) $_vseen ($N_UNKNOWN_V of $NREC records)" \
      "this tool reads schema v1 only, so every count below was computed over records whose fields may no longer mean what it assumes" \
      "update this reader for the new record shape before believing any finding in this run"
  fi

  N_WRAPDENY="$(num "$(count_of '.g=="wrapper" and .d=="deny"')")"
  N_BLOCK="$(num "$(count_of '.d=="block"')")"
  N_DEADDG="$(num "$(count_of '.d=="block" and .h=="-"')")"

  # ── probe-digest derivation · a prerequisite for BOTH FC-1 and FC-5 ────────
  # Hoisted above the per-host rules because FC-1 needs the verify-run count and
  # FC-5 needs the exclusion set, and both are the same six digests. It sat BELOW
  # FC-1 in an earlier draft, which under `set -u` aborted on an unbound variable
  # the moment FC-1 learned to subtract verify runs.
  #
  # WHY THE DIGESTS MATTER (the FC-5 half of the story):
  # The false-positive class with the verifier's own traffic taken out. The digest
  # is a SALTED hash of the payload, so the probe digests are computable here and
  # only here: the salt is on this box, and the payloads are read out of
  # floor-verify.sh rather than copied into this file (see the header).
  #
  # THE HASHER IS DERIVED, NEVER RE-IMPLEMENTED. floor_obs_digest owns the
  # algorithm — salt, separator, truncation length — and a second spelling of it
  # here would drift silently and stop matching, which fails toward reporting the
  # probes as findings.
  #
  # SOURCED FROM THE SIBLING, NEVER FROM THE INSPECTED DIRECTORY, and the first
  # draft had this backwards. It sourced `<dir>/bin/guard-lib.sh`, which EXECUTES a
  # file out of the tree under inspection: review replaced it with a stub
  # containing `finding() { :; }; FINDINGS=""; WORST=ok` and a box carrying three
  # crit conditions reported "nothing in the ledger says the floor is failing" and
  # exited 0. `$SELF/guard-lib.sh` is the same trust domain as this script — anyone
  # who can write there can rewrite this file anyway — and it is version-controlled
  # and B6-pinned on a live box. The SALT still comes from the inspected dir, which
  # is data, not code (floor_obs_digest takes the config dir as its argument).
  #
  # One consequence, recorded rather than hidden: if the live guard-lib.sh ever lags
  # the repo copy in the digest algorithm itself, the derived digests stop matching
  # and probe traffic is REPORTED rather than excluded. That is the safe direction —
  # over-reporting, with the count visible — and lint X2 is what notices the lag.
  # HOISTED ABOVE BOTH DERIVATIONS, and under `set -u` that is correctness rather
  # than tidiness: these were defined inside the probe block, so a box whose
  # floor-verify.sh is absent or symlinked left them unbound and the suite
  # derivation below aborted the whole run. Same class as the note at the top of
  # this block about FC-1 and the hoisted digests.
  # `&`, `|` and `\` are escaped because the value lands on a sed REPLACEMENT side,
  # where `&` means "the whole match".
  _dirsafe="$(printf '%s' "$DIR" | sed 's/[&|\\]/\\&/g')"
  _homesafe="$(printf '%s' "${HOME:-}" | sed 's/[&|\\]/\\&/g')"
  PROBE_DIGESTS=""
  PROBE_OK=0
  FV="$SELF/floor-verify.sh"
  if [ "$PROBES" = 0 ] && [ "$GL_OK" = 1 ] && [ -f "$FV" ] && [ ! -L "$FV" ]; then
    if true; then
      # Each `probe` line carries one hook payload as JSON. Take the text between
      # the first `{` and the last `}`, unescape the shell quoting, and let jq name
      # the field each guard actually digests: `.tool_input.command` for guard-bash
      # and guard-egress (guard-bash.sh:34, guard-egress.sh:21), `.tool_input.file_path`
      # for guard-selfedit — which digests the RESOLVED path, so it is normalised
      # here with the same function the guard uses (guard-selfedit.sh:36-39).
      # NEVER MATERIALISED TO DISK, and this is the same lesson a third time. The
      # payloads were written to a temp file, and one of them carries the
      # provider-token shape whose literal guard-egress blocked out of this file's
      # first draft on `secret-to-disk` — so the fix for the copy problem quietly
      # reintroduced the cleartext-to-disk problem, at mode 0644, on every run. The
      # whole extraction is now ONE PIPELINE whose only output is the digest list:
      # the subshell cannot mutate a variable, and it does not need to, because a
      # digest on stdout is all the parent wants. `$DIR` is substituted with sed,
      # so `&` and `|` in the replacement are ESCAPED first — unescaped, `&` means
      # "the whole match", which corrupted the selfedit probe's path, produced a
      # non-matching digest, and reported the verifier's own traffic as a finding
      # while still claiming the traffic had been excluded.
      # THE LEADING `(` on the case pattern inside the pipeline below is REQUIRED,
      # not decoration: within a command substitution the shell scans for the
      # matching close paren, and a bare case pattern's own paren closed the
      # substitution early — a parse error plus an unbound-variable cascade. POSIX
      # allows the optional open paren for exactly this ambiguity. Nor may this
      # explanation live INSIDE the substitution: under /bin/sh here (bash 3.2) the
      # backticks and parens in a comment there re-broke the same parse.
      _pd="$(awk '/^probe[[:space:]]/ {
                    s = $0
                    i = index(s, "{"); if (i == 0) next
                    s = substr(s, i)
                    j = 0; for (k = length(s); k > 0; k--) if (substr(s, k, 1) == "}") { j = k; break }
                    if (j == 0) next
                    print substr(s, 1, j)
                  }' "$FV" 2>/dev/null \
             | sed 's/\\"/"/g' \
             | while IFS= read -r _pj; do
                 [ -n "$_pj" ] || continue
                 _pj="$(printf '%s' "$_pj" | sed "s|\$DIR|$_dirsafe|g")"
                 _subj="$(printf '%s' "$_pj" | jq -r '.tool_input.command // empty' 2>/dev/null)"
                 if [ -z "$_subj" ]; then
                   _fp="$(printf '%s' "$_pj" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
                   [ -n "$_fp" ] && _subj="$(floor_norm_path "$_fp")"
                 fi
                 [ -n "$_subj" ] || continue
                 _d="$(FLOOR_OBS_SUBJECT="$_subj" floor_obs_digest "$DIR" 2>/dev/null || printf -- -)"
                 case "$_d" in
                   ([0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) printf '%s\n' "$_d" ;;
                 esac
               done)"
      PROBE_DIGESTS="$(printf '%s' "$_pd" | tr '\n' ' ')"
      [ -n "$PROBE_DIGESTS" ] && PROBE_OK=1
    fi
  fi

  # ── suite-digest derivation · FC-5's SECOND exclusion source ───────────────
  # THE VERIFIER IS NOT THE ONLY TOOL THAT FIRES REAL GUARDS AT THE LIVE FLOOR.
  # floor-test.sh runs the guards as themselves, so every `expect_block` case
  # appends a genuine block record with the live salt — indistinguishable, in the
  # ledger, from the operator hitting a wall. Measured 2026-09-06 on this box:
  # 222 of 555 block records (40%), 33 of 247 distinct digests, are suite payloads,
  # and FOUR of the judge's five warns were the CREDSTORE cases PR #417 added —
  # 'rm -rf ~/.config/gcloud' and its siblings, fired in three bursts on 09-03 with
  # no session live at any of the three timestamps.
  #
  # This is the exact argument the header already makes for the six verify probes
  # ("a detector whose loudest finding is its own tooling is one the operator
  # mutes"), one source further on. The derivation simply never grew the second
  # source, and the count it produced indicted the operator for harbor's own tests.
  #
  # SEPARATE FILE, NOT MERGED INTO $TMPD/probes, and that separation is
  # load-bearing rather than tidiness: FC-1 derives the VERIFY-RUN COUNT from the
  # probe digests' peak occurrence, and a verify run fires each probe exactly once.
  # Suite digests do not have that property — one `just test` fires each case once
  # too, but the two tools run at different rates — so folding them in would inflate
  # `_vruns`, over-subtract from the integrity census, and silence a real FC-1.
  # FC-5 gets the union; FC-1 keeps the probes alone.
  #
  # SOURCED FROM THE SIBLING, exactly as floor-verify.sh is, and for the reason
  # spelled out above: reading a file out of the INSPECTED tree would execute or
  # trust attacker-controlled content. $SELF is this script's own directory.
  #
  # NO PAYLOAD REACHES DISK. Same pipeline discipline as the probe half — the
  # suite carries 'rm -rf /' and provider-token shapes, and materialising them is
  # what guard-egress blocked out of this file's first draft.
  #
  # TWO PAYLOAD SHAPES, because two helpers build them (floor-test.sh:163-164):
  # `bash_j '<cmd>'` digests the RAW command, and `edit_j <Tool> "<path>"` digests
  # the RESOLVED path through floor_norm_path — the same split floor-verify's
  # extraction already makes between .tool_input.command and .tool_input.file_path.
  # Only single-quoted bash_j literals are taken: a payload built by `printf` or
  # carrying an interpolated variable cannot be reconstructed without running the
  # suite, so it is left IN the count. Under-excluding over-reports, which is the
  # safe direction and the one the probe half already chose.
  # LAZY, AND THE LAZINESS IS THE DESIGN, not an optimisation bolted on after.
  # The probe half hashes SIX payloads; this one has ~690, and floor_obs_digest
  # forks a hasher per payload. Measured on this box 2026-09-06, eagerly: a
  # `--live` run went 6.2s → 12.8s, and the suite — which invokes this tool dozens
  # of times — went from minutes to not finishing in the window I gave it.
  # judge-run.sh's header is explicit that ~7s is the number that keeps this job
  # off the session path (№2.11: a gate that makes ordinary work wait is a gate
  # that gets switched off), so doubling it silently is exactly the wrong trade.
  #
  # SO IT RUNS ONLY WHEN IT CAN CHANGE AN ANSWER: FC-5 first filters candidates
  # with the probe digests alone, and this is called only if a row SURVIVES that
  # filter. On a box with nothing recurring — the ordinary case, and every fixture
  # in the suite that is not specifically about FC-5 — the cost is zero.
  SUITE_DIGESTS=""
  SUITE_OK=0
  SUITE_TRIED=0
  FT="$SELF/../tests/floor/floor-test.sh"  # harbor#727: the floor suite is that part plus its siblings
  # TWO SOURCES FOR ONE FACT, because the suite is NOT on an installed box and
  # shipping it there is the wrong repair. Measured 2026-09-06: adding
  # floor-test.sh to runtime-install's payload took lint X7 from 1 advisory to 9,
  # and every one of the eight was TRUE — an installed suite really does invoke
  # eight scripts no installer ships, so what would ship is a 474K harness that
  # cannot run. Widening a payload to feed a detector is the same move as widening
  # a rule to silence one.
  #
  # So the installer derives the payload STRINGS at install time and writes them
  # beside the scripts; 28K against 474K, and it is data, so X7 — which scans for
  # `$VAR/<name>.sh|.awk` — does not see it at all.
  #
  # IT LIVES IN $SELF, NOT THE CONFIG ROOT, and that is a security property rather
  # than a filing choice. The salt is read from the INSPECTED dir safely because a
  # wrong salt makes every exclusion MISS — it fails toward over-reporting. This
  # file fails the other way: anyone who can append to it can name the preimage of
  # their own blocked command and delete it from the judge. $SELF is the same trust
  # domain as this script (the header's argument for sourcing guard-lib.sh from
  # here), and on a live box it is $CFG/bin, which guard-selfedit and the
  # floor-surface rules already defend.
  FM="$SELF/.helm-suite-payloads"
  # ONE EXTRACTION, TWO ORIGINS. The manifest holds exactly the kind-prefixed lines
  # the suite scan produces, so the digest loop below cannot tell them apart and
  # there is no second spelling of the parse to drift.
  _suite_lines() {
    if [ -f "$FT" ] && [ ! -L "$FT" ]; then
      for _ftf in "${FT%/*}"/floor-fixture.sh "$FT" "${FT%/*}"/floor.*-test.sh; do
        { [ -f "$_ftf" ] && [ ! -L "$_ftf" ]; } || continue
        sed -n "s/.*bash_j '\\([^']*\\)'.*/C\\1/p" "$_ftf" 2>/dev/null
        sed -n 's/.*edit_j [A-Za-z][A-Za-z]* "\([^"]*\)".*/P\1/p' "$_ftf" 2>/dev/null
      done
    elif [ -f "$FM" ] && [ ! -L "$FM" ]; then
      cat "$FM" 2>/dev/null
    fi
  }
  _derive_suite() {
    [ "$SUITE_TRIED" = 0 ] || return 0
    SUITE_TRIED=1
    [ "$PROBES" = 0 ] && [ "$GL_OK" = 1 ] || return 0
    { [ -f "$FT" ] && [ ! -L "$FT" ]; } || { [ -f "$FM" ] && [ ! -L "$FM" ]; } || return 0
    _sd="$( _suite_lines \
         | sort -u \
         | while IFS= read -r _sl; do
             [ -n "$_sl" ] || continue
             _skind="$(printf '%.1s' "$_sl")"; _sraw="${_sl#?}"
             # $DIR and $HOME appear verbatim in the suite's double-quoted paths.
             # Substituted with sed, so `&` and `|` in the replacement are escaped
             # first — unescaped, `&` means "the whole match" and corrupts the path
             # into a non-matching digest while still claiming an exclusion.
             _sraw="$(printf '%s' "$_sraw" | sed "s|\$DIR|$_dirsafe|g; s|\$HOME|$_homesafe|g")"
             # Leading `(` REQUIRED — same trap the probe half records below: inside
             # a command substitution a bare case pattern's own `)` closes the
             # substitution early. A payload still carrying an unresolved `$` after
             # the two substitutions above cannot be reconstructed, so it is left in.
             case "$_sraw" in (*'$'*) continue ;; esac
             if [ "$_skind" = P ]; then _sraw="$(floor_norm_path "$_sraw")"; fi
             [ -n "$_sraw" ] || continue
             _d="$(FLOOR_OBS_SUBJECT="$_sraw" floor_obs_digest "$DIR" 2>/dev/null || printf -- -)"
             case "$_d" in
               ([0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) printf '%s\n' "$_d" ;;
             esac
           done)"
    SUITE_DIGESTS="$(printf '%s' "$_sd" | tr '\n' ' ')"
    [ -n "$SUITE_DIGESTS" ] && SUITE_OK=1
    printf '%s\n' "$SUITE_DIGESTS" | tr ' ' '\n' | awk 'NF' | sort -u > "$TMPD/suite"
    # FC-5's exclusion set is the UNION; FC-1 keeps "$TMPD/probes" alone. ONE file,
    # so the awk below keeps the single-`pf` shape whose FILENAME==pf idiom the
    # comment there records as a defect the suite caught — a second exclusion file
    # would reintroduce exactly the two-file ambiguity that idiom exists to avoid.
    sort -u "$TMPD/probes" "$TMPD/suite" > "$TMPD/excl" 2>/dev/null || :
    return 0
  }

  printf '%s\n' "$PROBE_DIGESTS" | tr ' ' '\n' | awk 'NF' | sort -u > "$TMPD/probes"
  # The exclusion set STARTS as the probes alone and is widened by _derive_suite
  # only if FC-5 finds something the probes did not already explain.
  cp "$TMPD/probes" "$TMPD/excl" 2>/dev/null || : > "$TMPD/excl"
  : > "$TMPD/suite"
  # --exclusion-set (harbor#560): the same two derivations, handed to observe-report --fp so its
  # top rows stop being this box's own verifier and suite. One derivation, two readers.
  if [ "$EXCL_SET" = 1 ]; then
    [ "$PROBE_OK" = 1 ] || exit 1
    _derive_suite
    awk 'NF { print "probe " $1 }' "$TMPD/probes"
    awk 'NF { print "suite " $1 }' "$TMPD/suite"
    exit 0
  fi
  # HORIZONED ON LAST OCCURRENCE, COUNTED OVER ALL HISTORY (harbor#211 extended).
  # FC-2, FC-3 and FC-4 got a recency horizon because each was reading the whole
  # retained ledger and calling the answer a CURRENT state. FC-5 was left out and
  # has the identical defect: "the same command reaching the same rule again" is a
  # claim about now, and a command last walled a month ago is history.
  #
  # THE RETAINED WINDOW IS BOUNDED BY BYTES, NOT BY DAYS, which is why the rotation
  # does not already do this job. floor-observe.sh rotates at ROTATE_BYTES with ONE
  # generation, so what the ledger holds is a fixed number of RECORDS (~47k at the
  # measured ~110 bytes each) and the time they span is whatever the traffic makes
  # it. Measured on this box 2026-09-04: generation .1 spanned 5.4 days at ~9k
  # records/day; the same 5 MB on a tenth of that traffic spans nearly two months.
  # So "the ledger only keeps a week anyway" is an accident of load, not a bound,
  # and it is exactly the kind of accident that stops being true quietly.
  #
  # THE COUNT MUST STAY ALL-HISTORY. A command blocked three times over a month
  # whose third block was yesterday IS a live wall, and horizoning the count would
  # silently demote it below the threshold. Only the LAST occurrence is tested.
  #
  # An unresolvable clock reverts to all-history, matching every other rule here:
  # an unreadable clock must never be the thing that silences a finding.
  # A REFUSAL IS block, deny OR ask (harbor#319): a command the operator keeps walking into a deny,
  # or keeps approving at the same ask, is the same wall. Block-only left 67% of non-allow records
  # (2026-09-16) outside the one instrument that looks for over-blocking. A record with no digest
  # (`-`, as every prod_guard ask is) cannot be counted per command, so it stays out; FC-6 watches
  # dead digests on blocks only.
  jq -r 'select((.d=="block" or .d=="deny" or .d=="ask") and .h!="-")|"\(.h) \(.r) \(.ts[0:10])"' "$REC" 2>/dev/null \
    | awk -v c="$FC_CUTOFF" '{ k = $1 " " $2; n[k]++; if ($3 > last[k]) last[k] = $3 }
                             END { for (k in n) if (c == "" || last[k] >= c) printf "%7d %s\n", n[k], k }' \
    | sort -rn > "$TMPD/recur"

  # ── DID THE EXCLUSION ACTUALLY EXCLUDE ANYTHING? ────────────────────────────
  # The sharpest thing review found after the first fix round: a digest is salted,
  # and NOTHING IN A RECORD SAYS WHICH SALT DIGESTED IT — that is the redaction
  # working. So computing six digests successfully proves only that the salt file
  # parses NOW, never that it is the salt these records were written under. Two
  # measured paths where it is not: sandbox-make.sh copies MEMORY (ledger included)
  # and does NOT copy the salt, and floor-observe.sh then mints a FRESH random one
  # at the sandbox's first SessionStart — after which the old code reported
  # `probe_traffic_excluded: true` while every one of the six probe shapes came
  # through as an FC-5 finding. Asserting an exclusion that did not happen is worse
  # than not attempting one, because the caveat that exists for this exact doubt
  # disappears at the same moment.
  #
  # The check is decidable without knowing the salt: if not ONE derived digest
  # appears among the ledger's block digests, the exclusion demonstrably removed
  # nothing. That has two innocent readings and one alarming one, and the wording
  # carries all three rather than guessing — `harbor verify` may simply never have
  # run against this ledger, which is the common case on a fresh box.
  _pmatch=0
  if [ -s "$TMPD/probes" ]; then
    # BLOCK-ONLY ON PURPOSE, unlike the recurrence count above (harbor#319): every probe
    # floor-verify.sh fires is a block, so a deny or an ask could never match one here.
    jq -r 'select(.d=="block" and .h!="-")|.h' "$REC" 2>/dev/null | sort -u > "$TMPD/blockdg"
    _pmatch="$(num "$(awk -v pf="$TMPD/probes" \
      'FILENAME==pf{p[$1]=1;next} ($1 in p){n++} END{print n+0}' "$TMPD/probes" "$TMPD/blockdg")")"
  fi

  # UNAVAILABLE VERIFIER MEANS DEFER, NEVER SUBSTITUTE (№2.7). When the digests
  # could not be computed, or could not be shown to match anything, the candidates
  # are still reported — under-reporting a real false positive is the worse error —
  # but the finding SAYS so, and `probe_traffic_excluded` stays false.
  _caveat=""
  if [ "$PROBES" = 1 ]; then
    _caveat=" (--with-probes: the verifier's own shapes are INCLUDED in this count)"
    PROBE_OK=0
  elif [ "$PROBE_OK" = 0 ]; then
    _caveat=" (WARNING: the verifier's own shapes could NOT be separated — floor-verify.sh, the sibling guard-lib.sh or the salt was unreadable — so the top rows may be this box's own probe traffic)"
  elif [ "$_pmatch" -eq 0 ]; then
    _caveat=" (NOTE: the verifier's probe digests were computed and NONE of them appears in this ledger, so nothing was excluded — either \`harbor verify\` has never run against it, or the salt was replaced after these records were written, in which case a probe shape can still be sitting in the rows below)"
    PROBE_OK=0
  fi

  # ── the three PER-HOST rules ───────────────────────────────────────────────
  # FC-1, FC-3 and FC-4 are evaluated inside one partition at a time, for the
  # reason recorded at the reader above: a census and a "came back the next day"
  # are per-machine facts, and mixing two machines produced a measured
  # under-report. Everything else here is host-agnostic — a recurring digest
  # belongs to exactly one install because the salt is per-install, and a dead
  # digest or an unknown schema version is a defect wherever it appears.
  #
  # A `while read` fed by a HERE-DOC, never `printf | while read`: the loop body
  # calls finding(), and a pipeline puts it in a SUBSHELL where FINDINGS and WORST
  # die on exit. Word-splitting `for _h in $PARTITIONS` is also wrong — the floor
  # constrains a host token to [A-Za-z0-9_-] but a hand-made directory is not
  # bound by that, and a name with a space would split into two phantom hosts.
  count_h() { # <filter> <host>
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|1" "$REC" 2>/dev/null | awk 'END{print NR+0}'
  }
  days_h() {  # <filter> <host>
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|.ts[0:10]" "$REC" 2>/dev/null \
      | sort -u | awk 'END{print NR+0}'
  }
  # THE SAME TWO QUESTIONS, ASKED OF THE HORIZON (harbor#211). The pair above
  # reads the WHOLE retained ledger, which is right for "has this ever happened"
  # and wrong for every rule that then calls the answer a current state. An
  # `_r` variant is used wherever a severity depends on RECURRENCE, and the
  # unwindowed one stays for the message that says how far back it goes.
  #
  # $FC_CUTOFF EMPTY MEANS NO WINDOW, and the direction is deliberate: a clock
  # that cannot be read must not silence a crit, so the filter passes everything
  # and the rules fall back to the loud, all-history behaviour they had before.
  # The `$c==""` arm is belt-and-braces and MEASURED to be so — jq's `.ts >= ""`
  # is already true of every string, so deleting the arm changes no verdict. It
  # stays because the next editor may replace the string compare with a date
  # parse, where the empty case stops being free. Do not read its presence as
  # evidence that the fallback depends on it; the fallback is asserted directly,
  # by a suite row that goes red when FC_CUTOFF stops defaulting to empty.
  count_hr() { # <filter> <host> — inside the horizon
    jq -r --arg h "$2" --arg c "$FC_CUTOFF" \
      "select(._host==\$h)|select(\$c==\"\" or .ts[0:10] >= \$c)|select($1)|1" \
      "$REC" 2>/dev/null | awk 'END{print NR+0}'
  }
  days_hr() { # <filter> <host> — distinct days inside the horizon
    jq -r --arg h "$2" --arg c "$FC_CUTOFF" \
      "select(._host==\$h)|select(\$c==\"\" or .ts[0:10] >= \$c)|select($1)|.ts[0:10]" \
      "$REC" 2>/dev/null | sort -u | awk 'END{print NR+0}'
  }
  last_h() { # <filter> <host> — the most recent date, for a message that must
             # say WHEN, because a demoted finding with no date is unauditable.
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|.ts[0:10]" "$REC" 2>/dev/null \
      | sort | awk 'END{print $0}'
  }
  latest_h() { # <filter> <host> — "<ts> <decision>" of the NEWEST matching record.
               # SORTED BY ts, NOT taken from file order, for the reason days_hr
               # states: the sink is not chronological across host partitions, and
               # a "latest" read off the last line is then simply the wrong record.
               # Prints the empty string when nothing matches, which every caller
               # must treat as "no evidence", never as a verdict.
    jq -r --arg h "$2" "select(._host==\$h)|select($1)|\"\(.ts) \(.d)\"" "$REC" 2>/dev/null \
      | sort | awk 'END{print $0}'
  }
  PARTITIONS="$(jq -r '._host' "$REC" 2>/dev/null | sort -u | awk '$0 != "(unpartitioned)"')"
  NPART="$(num "$(printf '%s\n' "$PARTITIONS" | awk 'NF{n++} END{print n+0}')")"

  while IFS= read -r _h; do
    [ -n "${_h:-}" ] || continue
    # The host is named only when there is more than one, so the common
    # single-machine report does not carry a token that adds nothing.
    _tag=""; [ "$NPART" -gt 1 ] && _tag="$_h · "
    # FC-1 IS DELIBERATELY NOT HORIZONED, and this is the audit harbor#211 asked
    # for rather than an oversight. It carries the same never-clears SHAPE — these
    # are cumulative counts, so a week when floor-observe.sh dropped records leaves
    # a deficit nothing ever subtracts — but windowing it was MEASURED against the
    # live ledger and made the rule WORSE, not better:
    #
    #   all-history   475 session vs 533 integrity   → silent (a large historical
    #                                                  _vruns absorbs the gap)
    #   7-day window  164 session vs 194 integrity   → fires, warn
    #
    # The in-window gap is concentrated on 2026-08-13 (29 vs 47) and 2026-08-16
    # (5 vs 12), and both are `harbor verify` and hand runs of guard-integrity.sh
    # — exactly the confound this rule's own message already names and the reason
    # it corrects by _vruns at all. Windowing shrinks the correction faster than it
    # shrinks the gap, so the rule starts firing on ordinary operator tooling: a
    # §2.11 false positive introduced by the fix for a §2.11 false positive.
    #
    # So the shape is REPORTED and left alone. Making FC-1 clearable needs a
    # denominator that separates a SessionStart from a hand invocation, which no
    # field in the record currently carries — that is a ledger-schema change, not
    # a horizon, and it is not this ticket.
    N_SESSION="$(num "$(count_h '.g=="session"' "$_h")")"
    N_INTEGRITY="$(num "$(count_h '.g=="integrity"' "$_h")")"
    N_GATE="$(num "$(count_h '.g=="integrity" and .d=="gate"' "$_h")")"
    N_ADVISE="$(num "$(count_h '.g=="integrity" and .d=="advise"' "$_h")")"

    # ── FC-1 · the writer is dropping records ──────────────────────────────────
    # TWO INDEPENDENT CENSUSES OF THE SAME EVENT. Both hooks fire once per
    # SessionStart and each writes exactly one record, so the counts must agree. A
    # gap means records are being dropped, and floor_log_decision drops them
    # SILENTLY on purpose — property 1: a logging failure must never change a
    # verdict, so every path returns 0 (guard-lib.sh, floor_log_decision property 1).
    #
    # ONLY FIRES WHEN INTEGRITY EXCEEDS SESSION, and the asymmetry is not laziness.
    # The reverse gap is the ordinary state of a box where B6 was installed later
    # than L1 — measured here as 3 armed against 0 integrity on the ledger's first
    # day — and a rule that fired on it would be wrong on every correctly configured
    # machine that has not run the separate `--with-b6` step at all.
    # VERIFY RUNS ARE SUBTRACTED FIRST, and without that this rule is a false-
    # positive generator on the documented workflow. `harbor verify` invokes
    # guard-integrity.sh directly as its B6 status check (floor-verify.sh:196-197),
    # and that path records (guard-integrity.sh:221-226) — so EVERY verify run adds
    # one integrity record with no session record. HANDOFF.md tells every fresh
    # session to run it. Measured on this box: 30 session against 49 integrity, a
    # gap of 19, with 27 verify runs in the same window — the gap this rule was
    # built on was fully consistent with the operator's own tooling, and an earlier
    # draft reported it as a crit defect in floor-observe.sh. That is FC-5's probe
    # contamination one rule over, and it got past a grep for `guard-integrity` in
    # floor-verify.sh that was run from the wrong directory with stderr discarded.
    #
    # A verify run is countable: it fires every probe once, so the highest
    # occurrence count among the derived probe digests is the number of runs. It is
    # only countable when those digests MATCH this ledger, which is what PROBE_OK
    # means — so when they do not, this rule DOES NOT FIRE AT ALL rather than firing
    # on an uncorrectable denominator (№2.7: defer, never substitute).
    #
    # WARN, NEVER CRIT, for what survives. guard-integrity.sh is also invoked
    # directly by floor-install.sh --with-b6 and by a command runtime-install.sh:402
    # prints for the operator to paste, and NOTHING in the record distinguishes any
    # of those from a SessionStart. So a residual gap is "these two counts do not
    # reconcile", which is worth a look, and not "the floor is blind", which would be
    # a claim the ledger cannot support.
    _vruns=0
    if [ "$PROBE_OK" = 1 ] && [ -s "$TMPD/probes" ]; then
      # UNWINDOWED, with the two counts it corrects. Windowing only this half is
      # what made the horizoned FC-1 fire on a healthy box: the correction shrinks
      # faster than the gap does. See the audit note at N_SESSION above.
      jq -r --arg h "$_h" 'select(._host==$h and .d=="block" and .h!="-")|.h' "$REC" 2>/dev/null \
        | sort | uniq -c > "$TMPD/hostdg" || :
      _vruns="$(num "$(awk -v pf="$TMPD/probes" \
        'FILENAME==pf{p[$1]=1;next} ($2 in p && $1+0>m){m=$1+0} END{print m+0}' \
        "$TMPD/probes" "$TMPD/hostdg")")"
    fi
    _adj=$((N_INTEGRITY - _vruns))
    [ "$_adj" -lt 0 ] && _adj=0
    if [ "$PROBE_OK" != 1 ]; then
      : # the verify-run count is unavailable, so the census is uncorrectable here
    elif [ "$_adj" -ge 3 ] && [ "$N_SESSION" -eq 0 ]; then
      # Distinct from the reconcile case and genuinely attributable: after taking
      # the verify runs out, guard-integrity has recorded a SessionStart several
      # times and floor-observe.sh has recorded none, ever. There is no denominator
      # at all, so observe-report cannot compute an override rate.
      finding FC-1 crit "${_tag}no session census exists" \
        "$_adj session-start records from the integrity gate that verify runs do not explain, and NOT ONE from floor-observe.sh — so there is no denominator, and observe-report refuses the override rate rather than printing one" \
        "check that floor-observe.sh is wired at SessionStart and reaches its last line; it exits 0 on every failure path by design, so a broken run looks exactly like a quiet one"
    elif [ "$((_adj - N_SESSION))" -ge 3 ]; then
      _gap=$((_adj - N_SESSION))
      finding FC-1 warn "${_tag}session census does not reconcile" \
        "$N_SESSION session records against $N_INTEGRITY from the integrity gate, of which $_vruns are accounted for by \`harbor verify\` runs — leaving $_gap SessionStart(s) recorded by one hook and not the other. Either floor-observe.sh is dropping records silently (it exits 0 on every failure path by design), or guard-integrity.sh was invoked by hand — floor-install.sh --with-b6 and runtime-install.sh both do that, and no field in the record tells them apart" \
        "reconcile per day (jq over .g and .ts[0:10], counting a probe digest per verify run) before suspecting the hook; floor-observe.sh holds the host dir at 0700 between its own chmods, so a record landing inside a CONCURRENT session's window is refused by the [ ! -w ] gate"
    fi

    # ── FC-3 · the integrity gate blocked a session ────────────────────────────
    # The only control in the floor that can stop a WHOLE SESSION, and it does so
    # while exiting 0 — it denies via {"continue":false} on stdout, never via exit 2
    # (guard-integrity.sh:215-220). Recurrence is the judgment observe-report's flat
    # count cannot make: one episode is the control working, and a return on a later
    # day means the recovery command the gate handed the operator is not clearing the
    # drift. That has already happened on this box — the message named floor-deny.sh for guard
    # CONTENT drift, which it cannot clear (guard-integrity.sh:229-235). Follow that
    # citation as HISTORY: the block at :250-258 also says no installer ships
    # floor-deny.sh, and that half has stopped being true — runtime-install.sh lists it
    # in FILES and it is on the live surface. The repair line below avoids naming it
    # because re-pinning is the operator's act, not because the script is absent.
    #
    # CLUSTERED BY DAY, NOT COUNTED RAW, and this tool's first cut got it wrong in
    # the one direction that matters. Raw counting made "≥3 gates" a crit, and the
    # live ledger's four gates all fall inside a TWELVE-MINUTE window on 2026-08-02
    # (19:44:59, 19:45:15, 19:55:43, 19:56:33) — one drift, one operator fixing it,
    # four attempts to open a session while they did. Calling that "the recovery is
    # not working" is a false positive on the only real data that exists, and №2.11
    # makes that a defect rather than safety. A gate returning on a SECOND DAY is the
    # signal worth a crit: the drift survived a night, so whatever was done did not
    # hold. Days come from the `ts` field directly, so no epoch arithmetic and no
    # reliance on file order — which is not chronological across host partitions.
    #
    # AND THE DAY COUNT IS NOW TAKEN INSIDE THE HORIZON (harbor#211). Clustering
    # by day fixed the false positive one level down — four gates in twelve
    # minutes is one episode, not four — and left the same error one level up:
    # two CLUSTERS eleven days apart were read as a drift that survived a night.
    # `_gdaysr` asks the question the message actually claims to be asking.
    if [ "$N_GATE" -gt 0 ]; then
      _gdays="$(num "$(days_h  '.g=="integrity" and .d=="gate"' "$_h")")"
      _gdaysr="$(num "$(days_hr '.g=="integrity" and .d=="gate"' "$_h")")"
      _ngater="$(num "$(count_hr '.g=="integrity" and .d=="gate"' "$_h")")"
      _glast="$(last_h '.g=="integrity" and .d=="gate"' "$_h")"
      # AND THE HORIZON WAS STILL NOT THE WHOLE QUESTION (2026-08-27). Day
      # clustering fixed "four gates in twelve minutes"; the horizon fixed "two
      # clusters eleven days apart". Both are about the DISTANCE between episodes,
      # and neither one ever asks the thing the message actually claims: is the
      # gate still firing? Measured on the live box — gates on 2026-08-22 (x4,
      # cleared by 18:39Z) and 2026-08-26 (x3, cleared by 11:43Z), four days
      # apart, INSIDE the window, every integrity verdict since reading clean.
      # The rule said "the drift came back after a night, so whatever cleared it
      # did not hold" and sent the operator to run restore.sh against a floor that
      # had been clean for twenty hours. Two independent drifts, each remediated
      # in half an hour, reported as one unresolved drift.
      #
      # SO RECURRENCE IS NECESSARY AND NO LONGER SUFFICIENT. The crit now also
      # requires that the ledger's OWN most recent integrity verdict still be a
      # gate. That is not a second opinion bolted on — it is the same ledger, one
      # question further, and it is the only field here that can distinguish "this
      # is still happening" from "this happened twice and is over".
      #
      # `advise` AND `allow` BOTH COUNT AS CLEARED, and that is measured from the
      # producer rather than assumed: guard-integrity.sh reaches its advise/allow
      # branch inside `if [ -z "$DRIFT" ]`, so ANY non-gate integrity record is
      # positive evidence that B6 found no blocking drift on that run. Reading
      # only `allow` as clean would leave a box whose every session raises the
      # auto-memory advisory permanently crit — which is this same defect again.
      #
      # A LEDGER WITH NOTHING BUT GATES STAYS CRIT. `latest_h` prints empty when
      # nothing matches and a gate-only ledger returns "gate", so the fixtures
      # asserting crit on consecutive days keep asserting it; the demotion needs a
      # POSITIVE clean record, never the absence of evidence.
      _glatest="$(latest_h '.g=="integrity"' "$_h")"
      _gldec="${_glatest##* }"; _glts="${_glatest%% *}"
      if [ "$_gdaysr" -ge 2 ] && [ "$_gldec" = gate ]; then
        finding FC-3 crit "${_tag}integrity gate (x$_ngater on $_gdaysr separate days in the last ${FC_HORIZON}d, still gating)" \
          "the B6 drift gate has BLOCKED a session at start on $_gdaysr different days inside ${FC_HORIZON} days, and the most recent integrity verdict in the ledger is STILL a gate — the drift is not cleared" \
          "read the drift class in the gate's own message, then act from your OWN terminal: restore.sh to undo the change, or re-pin deliberately if it was intended"
      elif [ "$_gdaysr" -ge 2 ]; then
        # Recurrence inside the window, but the gate is demonstrably clear. Warn,
        # dated on BOTH ends — when it last fired and when it last read clean —
        # because a reader who cannot check either date cannot falsify this.
        finding FC-3 warn "${_tag}integrity gate (x$_ngater on $_gdaysr separate days in the last ${FC_HORIZON}d), last fired $_glast — clear since $_glts" \
          "the B6 drift gate blocked on $_gdaysr separate days inside the window, but the ledger's most recent integrity verdict is \`$_gldec\`, not a gate — separate drifts, each cleared, rather than one that is still returning. Recurrence is evidence the recovery is not holding only while the gate is STILL firing" \
          "no action: B6 read clean at $_glts. This returns to crit the moment a gate blocks again and stays the newest integrity verdict — which is the state that means your recovery did not hold."
      elif [ "$_gdays" -ge 2 ]; then
        # History, not state. Kept at warn so the record survives where a human
        # reviews it, and off the SessionStart channel where it was wallpaper.
        finding FC-3 warn "${_tag}integrity gate (x$N_GATE on $_gdays days, none since $_glast)" \
          "the B6 drift gate has blocked on $_gdays separate days in the retained ledger, but NOT inside the last ${FC_HORIZON} days — separate episodes, each apparently cleared, rather than one drift that is still returning" \
          "no action: this is history. It returns to crit the moment a gate blocks on two days inside the window."
      elif [ "$_gdaysr" -ge 1 ]; then
        finding FC-3 warn "${_tag}integrity gate (x$_ngater in one day)" \
          "a session was BLOCKED at start by the B6 drift gate — one episode, which is the gate working; a second day would mean the recovery it printed is not clearing the drift" \
          "no action if you resolved it; if it returns tomorrow, the recovery the gate names is not the one that clears your drift class"
      fi
      # One old episode, on one day, outside the window: cleared, and there is
      # nothing to say about it that the ledger does not already record.
    fi

    # ── FC-4 · a standing advisory nobody has cleared ──────────────────────────
    # `advise` HAD no human-visible surface until observe-report counted it and grew
    # --advise (harbor#303); this finding is still the one that says it is STANDING.
    # An advisory repeating across
    # days is drift the operator has stopped reading, which is how a pinned
    # instruction surface stays unpinned for a week.
    #
    # HORIZONED TOO (harbor#211), and here the horizon IS the predicate rather
    # than a severity split. This rule's whole subject is "a standing advisory
    # NOBODY HAS CLEARED" — an advisory that stopped days ago has been cleared,
    # so the all-history count was asserting the opposite of what it measured.
    # There is no demoted tier below warn to fall to, and a cleared advisory has
    # nothing left to tell a human, so it simply stops being a finding.
    if [ "$N_ADVISE" -gt 0 ]; then
      _days="$(num "$(days_hr '.g=="integrity" and .d=="advise"' "$_h")")"
      _nadvr="$(num "$(count_hr '.g=="integrity" and .d=="advise"' "$_h")")"
      _advlast="$(last_h '.g=="integrity" and .d=="advise"' "$_h")"
      # A cause fixed days ago leaves history that still spans two days; only a recent advisory says it is standing.
      if [ "$_days" -ge 2 ] && { [ -z "$FC_RECENT" ] || [ "$(printf '%s\n%s\n' "$_advlast" "$FC_RECENT" | sort | tail -n1)" = "$_advlast" ]; }; then
        finding FC-4 warn "${_tag}integrity advisory (x$_nadvr over ${_days}d)" \
          "the integrity gate has raised an advisory on $_days separate days inside the last ${FC_HORIZON} and is still raising it" \
          "list them with observe-report.sh --advise and read the cause with harbor verify; for pin drift, review the changed surfaces and re-pin from your own terminal"
      fi
    fi

  done <<PARTITION_LIST
$PARTITIONS
PARTITION_LIST

  # ── FC-2 · the floor could not reach a verdict ─────────────────────────────
  # The wrapper's own denies: "the floor is broken", as distinct from "a rule
  # fired". Without them a jq outage reads as a quiet drop in block counts and
  # looks like the rules getting better (floor-hook.sh:34-39). On the --advisory
  # path it does not even deny, so an annotate-web wrapper failure is invisible by
  # construction unless it is written down (floor-hook.sh:62-64).
  #
  # THE WORDING BELOW MUST NOT SAY "N CALLS WERE BLOCKED", and the first draft did.
  # The record is identical in both modes: fail-closed wiring denies and exits 2,
  # advisory wiring records the same `d:"deny"` and exits 0, and no field tells them
  # apart. The record also carries `t:"none"` always — the wrapper never parses the
  # payload, so `FLOOR_TOOL` is unset and the ledger cannot say which tool call the
  # floor failed to judge — and floor-hook.sh:92-95 collapses every rc outside {0,2}
  # into one token, so 126, 127, 1 and 137 are indistinguishable here. Enough to
  # alarm, not enough to diagnose, and the repair lines say so.
  #
  # HORIZONED (harbor#211), and this rule is why the ticket calls FC-3's defect a
  # class rather than a bug: one wrapper deny on 2026-08-06 was still being
  # reported as current state, at crit, ten days later, under a repair line
  # ("re-run floor-install.sh") that could not change it because every wired guard
  # was already present. A single record can be reported forever by a rule that
  # never asks when it happened.
  #
  # SPLIT BY DATE, NOT FILTERED BY IT. Inside the horizon the verdict is unchanged
  # — crit, with the repair. Outside it the same row is a warn that NAMES THE DATE,
  # so it leaves the SessionStart channel without leaving the record. Both halves
  # run the identical awk; only the severity, the two suffixes and the two dates
  # handed in differ.
  #
  # THE REPAIR SAYS WHEN, AND IT ROUTES BEFORE IT PRESCRIBES (harbor#211 follow-up).
  # The horizon fixed how LONG a spent record shouts; it did not fix what the row
  # tells you to do about it. Measured on the live box 2026-08-23: the single
  # 2026-08-20 wrapper deny printed "a wired guard is absent or empty: re-run
  # floor-install.sh" while floor-verify --live reported all sixteen guards
  # present, wired and blocking — an instruction that could not change the verdict,
  # on the one channel session-verdicts.sh speaks on. A crit whose remedy is inert
  # teaches the reader that crits are advisory, which is the wallpaper failure
  # №2.11 calls a defect rather than safety.
  #
  # SO THE ROW NAMES THE CHECK, NOT THE CURE. It cannot ask whether a guard is
  # present — see THE SCOPE IS THE LEDGER in the header: guard presence is
  # floor-verify's question and reference-check.sh REF-1's, and answering it here
  # a second time is exactly the drift class the T rules exist for. Routing the
  # operator to that tool is not the same as running it, and the default repair
  # already did precisely this. What is new is that the installer is now stated as
  # CONDITIONAL on what the check says, and the date the row goes quiet is printed
  # so the claim can be falsified by waiting.
  if [ "$N_WRAPDENY" -gt 0 ]; then
    _fc2_rows() { # <jq-date-predicate> <severity> <suffix> <repair-suffix> [as-of-date] [demote-date]
      jq -r --arg c "$FC_CUTOFF" --arg i "$FC_INSTALL_DATE" "select(.g==\"wrapper\" and .d==\"deny\")|select($1)|.r" "$REC" 2>/dev/null \
        | sort | uniq -c | sort -rn \
        | awk -v sev="$2" -v sfx="$3" -v rsfx="$4" -v when="${5:-}" -v clears="${6:-}" '{ n=$1; r=$2
                 repair = "run `harbor verify` and read which guard fails to reach a verdict"
                 if (r ~ /no-jq/)         repair = "install jq — without it every floor_field returns empty and a guard sees an empty command"
                 if (r ~ /guard-missing/) repair = "run `harbor verify` first — floor-install.sh only helps if that reports a guard absent or unwired, and a green floor means this record is spent"
                 if (r ~ /no-grep/)       repair = "grep is unresolvable from the hook environment: check PATH and /usr/bin/grep"
                 if (r ~ /no-verdict/)    repair = "the guard exited outside {0,2}: run it by hand against a payload and read stderr"
                 if (when != "") {
                   repair = "recorded " when ", not now: " repair
                   if (clears != "") repair = repair "; clears " clears " if nothing new lands"
                 }
                 printf "FC-2\t%s\t%s (x%d)%s\tthe floor could not EVALUATE a tool call: on fail-closed wiring it denied one with no rule behind it, and on the advisory wiring it recorded this and let the call through — the record is identical either way, and carries neither the tool nor the exit code\t%s%s\n", sev, r, n, sfx, repair, rsfx }'
    }
    _fc2_last="$(jq -r 'select(.g=="wrapper" and .d=="deny")|.ts[0:10]' "$REC" 2>/dev/null | sort | awk 'END{print $0}')"
    # THE DAY THE ROW GOES QUIET, COMPUTED RATHER THAN DESCRIBED. "in about a week"
    # is a claim the reader cannot check; a date is one they can. A record dated D
    # stays in the crit half while D >= cutoff and cutoff is today-minus-horizon, so
    # the first day it falls out is D + horizon + 1. Same two-dialect idiom as
    # FC_CUTOFF — BSD `-v` first, GNU `-d` second — and empty when neither resolves,
    # in which case the clause is simply not printed rather than guessed.
    _fc2_clears=""
    case "$_fc2_last" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
        _fc2_clears="$(date -u -j -v+"$((FC_HORIZON + 1))"d -f '%Y-%m-%d' "$_fc2_last" +%F 2>/dev/null \
                    || date -u -d "$_fc2_last + $((FC_HORIZON + 1)) days" +%F 2>/dev/null \
                    || true)"
        case "$_fc2_clears" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
          *) _fc2_clears="" ;;
        esac ;;
    esac
    # The crit half carries both dates. The warn half carries NEITHER, and that is
    # not an oversight: its subject suffix already names the date and its repair
    # suffix already says the recurrence stopped, so handing them in again would
    # print the same date three times in one row, and a demote date already in the
    # past would read as a promise about nothing.
    # THREE BUCKETS, DISJOINT AND EXHAUSTIVE. A record is crit only while it is
    # BOTH inside the horizon AND not superseded by an install; supersession wins
    # over the horizon because it is the stronger statement — "the file this names
    # was replaced" beats "this happened a while ago". The predicates are exact
    # complements of one another, so no record can be emitted twice or dropped,
    # including when either mark is empty: with both empty the crit arm takes
    # everything, which is the fail-toward-crit direction both marks require.
    # ONLY THE CLASSES WHOSE ARTEFACT AN INSTALL ACTUALLY REPLACES. The first
    # draft superseded every wrapper deny, and a reinstall cannot restore a
    # missing `jq` or `grep`: the row would have told the operator that the file
    # the record names was replaced, which is false for the interpreter canaries.
    # Worse, SessionStart surfaces only crit, so an interpreter outage on a
    # rarely-exercised wiring — annotate-web fires on web calls alone, and in
    # advisory mode it has no other witness — would go quiet after an unrelated
    # install. That is the false NEGATIVE this rule was meant to close, reopened
    # one class to the left. guard-missing and no-verdict are both statements
    # about the guard FILE (absent, empty, or exiting 126/127/1), and that file is
    # exactly what floor-install overwrites; everything else keeps its severity.
    _fc2_replaced='(.r|startswith("wrapper-guard-missing") or startswith("wrapper-no-verdict"))'
    { _fc2_rows "(\$c==\"\" or .ts[0:10] >= \$c) and (\$i==\"\" or .ts[0:10] >= \$i or ($_fc2_replaced|not))" crit '' '' "$_fc2_last" "$_fc2_clears"
      # SUPERSEDED — the informative demotion, and it names the install rather
      # than the calendar, because that is what the reader can act on.
      _fc2_rows "\$i!=\"\" and .ts[0:10] < \$i and $_fc2_replaced" info \
        ", last on $_fc2_last — before the floor was reinstalled" \
        " — and the guard file this names was REPLACED by the floor-install of ${FC_INSTALL_DATE}, so it no longer exists in the state this record describes: history unless it recurs"
      # The old half only exists when a horizon was resolvable; with $FC_CUTOFF
      # empty the first call already took every record and this one must take none,
      # or every row would be emitted twice. It also excludes anything the
      # supersession arm already took.
      [ -n "$FC_CUTOFF" ] && _fc2_rows ".ts[0:10] < \$c and (\$i==\"\" or .ts[0:10] >= \$i or ($_fc2_replaced|not))" warn \
        ", last on $_fc2_last — outside the ${FC_HORIZON}d window" \
        " — but nothing has been recorded since $_fc2_last, so verify before acting: this is history unless it recurs"
    } > "$TMPD/fc2" 2>/dev/null || :
    while IFS='	' read -r r s j w p; do [ -n "${r:-}" ] && finding "$r" "$s" "$j" "$w" "$p"; done < "$TMPD/fc2"
  fi

  # ── FC-6 · the recurrence counter is dead ──────────────────────────────────
  # Ordered before FC-5 because it decides whether FC-5 can be believed. A block
  # record carries `h="-"` when the salt is absent or malformed, or no hasher
  # resolved (guard-lib.sh, floor_obs_digest). Blocks are still counted; they are no longer
  # CORRELATED, which is the one question the digest exists to answer — so the
  # false-positive detector goes blind while every total still looks right.
  if [ "$N_BLOCK" -gt 0 ] && [ "$N_DEADDG" -gt 0 ]; then
    _sev=warn; [ "$N_DEADDG" -eq "$N_BLOCK" ] && _sev=crit
    finding FC-6 "$_sev" "dead digests ($N_DEADDG of $N_BLOCK blocks)" \
      "these blocks carry no digest, so FC-5 and observe-report --fp cannot tell them apart and both under-report recurrence without saying so" \
      "check that the per-install salt holds 32 hex characters and that a sha256 binary resolves at one of the absolute paths floor_obs_digest pins"
  fi

  # awk, not grep: a negative ("this digest is not a probe") must never rest on a
  # grep whose flags this script does not control. On this Mac `grep` is a ugrep
  # wrapper carrying -I --ignore-files, and a silently skipped line here DROPS a
  # real finding (reference-check.sh:94-98).
  #
  # GROUPED BY RULE, ONE FINDING PER RULE, and that is this tool's own first
  # measured false positive. Ungrouped, its first run on the live ledger printed
  # eight FC-5 rows, six of them the same rule at the same count with different
  # digests — eleven findings in total where the operator had four things to look at. A detector that
  # emits a row per item on a class that is ordinarily populated is one that gets
  # skimmed, which is the failure mode №2.11 names and pulse.sh:246-249 designs
  # around when it refuses to raise a verdict on ordinary drift. The per-rule count
  # is also the more useful number: six different commands walled by ONE rule is
  # evidence about the rule, and six separate rows hide it.
  # `FILENAME==pf`, NEVER the `NR==FNR` idiom — and this is a defect the suite
  # caught rather than a style choice. When no probe digests could be computed the
  # first file is EMPTY, and `NR==FNR` is then true for the first record of the
  # SECOND file, so the highest-count recurring block was silently consumed as if
  # it were a probe entry. The failure mode is the one this tool exists to prevent:
  # the loudest finding disappears and the report still looks complete.
  # TWO PASSES, AND THE FIRST ONE IS WHAT MAKES THE SUITE DERIVATION AFFORDABLE.
  # Pass one filters with the probe digests alone. If nothing survives, there is no
  # finding to make and no reason to hash ~690 suite payloads — see _derive_suite's
  # header for the measured cost. If something does survive, the suite digests are
  # derived once and the filter is re-run over the WIDENED set. The candidate rows
  # themselves are recomputed rather than subtracted, so there is exactly one
  # spelling of the filter and the two passes cannot disagree.
  _fc5_filter() { # <exclusion-file>
    awk -v pf="$1" 'FILENAME==pf{p[$1]=1;next} { n=$1; d=$2; r=$3; if (!(d in p) && n+0>=3) printf "%s\t%d\t%s\n", r, n, d }' \
        "$1" "$TMPD/recur"
  }
  _fc5_filter "$TMPD/excl" > "$TMPD/fc5cand" 2>/dev/null || :
  if [ -s "$TMPD/fc5cand" ]; then
    _derive_suite
    _fc5_filter "$TMPD/excl" > "$TMPD/fc5cand" 2>/dev/null || :
  fi
  # The suite half gets its own caveat sentence rather than a branch in the block
  # above, because whether it ran is only known HERE — the derivation is lazy, so
  # at caveat-building time SUITE_OK is still 0 on a perfectly healthy box and a
  # branch there would have fired on every run. Only said when there is a finding
  # to attach it to, which is the only time it could mislead.
  if [ "$PROBES" = 0 ] && [ "$SUITE_TRIED" = 1 ] && [ "$SUITE_OK" = 0 ]; then
    _caveat="$_caveat (NOTE: the floor suite (tests/floor/) could not be read beside this script, so the SUITE's own payloads — which fire the real guards and land in this ledger exactly as an operator's commands do — are still counted in the rows below)"
  fi
  cat "$TMPD/fc5cand" \
    | sort -k1,1 -k2,2nr \
    | awk -F'\t' '{ c[$1]++; if ($2+0 > worst[$1]) worst[$1]=$2+0
                    if (c[$1] <= 3) top[$1] = (top[$1] == "" ? $3 "(x" $2 ")" : top[$1] " " $3 "(x" $2 ")") }
                  END { for (r in c) printf "%s\t%d\t%d\t%s\n", r, c[r], worst[r], top[r] }' \
    | sort -t'	' -k3,3nr > "$TMPD/fc5"
  while IFS='	' read -r r ndist wmax tops; do
    [ -n "${r:-}" ] || continue
    _plural=""; _about=""
    # The count spans the whole retained ledger; the RULE for emitting it is that
    # the most recent block is inside the window. Say so, or a reader takes the
    # count for an all-time total that is still climbing.
    _recent=""
    [ -n "$FC_CUTOFF" ] && _recent=" — still recurring inside the ${FC_HORIZON}d window (the count itself spans the whole retained ledger)"
    if [ "$ndist" -gt 1 ]; then
      _plural="s"
      # The distinct-command count is the part that indicts the RULE rather than a
      # command: one command blocked four times can be one stubborn operator, and
      # six different commands walled by the same rule is a precision problem.
      _about=" — and $ndist DIFFERENT commands walled by one rule is evidence about the rule, not about any of them"
    fi
    finding FC-5 warn "$r · $ndist distinct command$_plural refused >=3x (worst x$wmax)" \
      "the same command reaching the same rule again is either the operator re-hitting a wall, which №2.11 makes a defect rather than safety, or a script retrying into the floor$_about$_recent$_caveat" \
      "reproduce from the digests [$tops] by re-running what you were doing, then fix the rule or the command — never widen a rule to silence a count"
  done < "$TMPD/fc5"
fi

# ── FC-9 · the ledger is sharded under more than one host key ────────────────
# ONE CONFIG DIR IS ONE INSTALL, so more than one host partition means the host
# key MOVED and the history is now in fragments. Not hypothetical: harbor#119
# measured `hostname -s` on macOS answering the literal `Mac` once no network has
# supplied a name, which forked this box's ledger at 21917 records against 54 —
# and its own summary names the consequence in this tool's exact terms, "a reader
# of either directory silently under-reports, which is the one failure mode an
# audit trail cannot have".
#
# THIS TOOL UNIONS THE PARTITIONS, so its own totals are right — which is exactly
# why the fork has to be SAID. Every other reader of that tree opens one directory:
# observe-report.sh globs them all but attributes nothing, and any hand-written jq
# over `OBSERVABILITY/<host>/` sees one fragment and reports it as the history. A
# tool that quietly compensates for a defect while every neighbour still trips over
# it has hidden the defect rather than found it.
#
# WARN, not crit: nothing is lost, and the wording carries the innocent reading
# too. A ledger copied in from another machine looks identical from here, and the
# repair differs — so the finding names both and picks neither.
if [ -d "$OBS" ]; then
  _nhost=0
  for _hd in "$OBS"/*; do [ -d "$_hd" ] && _nhost=$((_nhost + 1)); done
  if [ "$_nhost" -gt 1 ]; then
    _hlist=""
    for _hd in "$OBS"/*; do
      [ -d "$_hd" ] || continue
      _hn="$(basename "$_hd")"
      _hc="$(num "$(jq -r --arg h "$_hn" 'select(._host==$h)|1' "$REC" 2>/dev/null | awk 'END{print NR+0}')")"
      _hlist="$_hlist $_hn($_hc)"
    done
    # WHICH KEY IS CANONICAL, ASKED OF THE FUNCTION THAT OWNS THE ANSWER.
    # harbor#119 made floor_host_token the one definition of the partition key,
    # with a structural assertion that no consumer derives it again — so this rule
    # CALLS it rather than re-deriving, and the two changes become one mechanism
    # instead of two adjacent ones. It also separates the only two states an
    # operator can act on differently, which a bare partition count cannot:
    #
    #   ONGOING  the newest record is in a NON-canonical partition, so the code
    #            still running writes under the old key. Every reader is losing
    #            data right now, and the act is to deploy the fix. crit.
    #   HISTORICAL  the newest record is canonical, so writes have resumed under
    #            the right key and the other partitions are orphaned history. The
    #            act is to fold them, at leisure. warn.
    #
    # Without that split the finding is permanent and unactionable the moment the
    # fix lands — a standing warn nobody can clear is how a channel gets muted
    # (№2.11), which is the same argument harbor#119 makes for not weakening O-19.
    _canon=""
    [ "$GL_OK" = 1 ] && _canon="$(floor_host_token 2>/dev/null || printf '')"
    _newest_host="$(jq -rs 'max_by(.ts)._host // empty' "$REC" 2>/dev/null || printf '')"
    if [ -n "$_canon" ] && [ -n "$_newest_host" ] && [ "$_newest_host" != "$_canon" ]; then
      finding FC-9 crit "$_nhost host partitions, still writing under \`$_newest_host\` (canonical is \`$_canon\`):$_hlist" \
        "the newest record is NOT in the canonical partition, so the code writing this ledger still derives the old key — the fork is growing, and every reader that opens one directory is losing data now" \
        "deploy the stable-key fix (harbor#119) so writes resume under \`$_canon\`, then fold the orphaned partition(s); an installer is the operator's act, and until it runs the split widens every session"
    elif [ -n "$_canon" ]; then
      finding FC-9 warn "$_nhost host partitions, canonical is \`$_canon\`:$_hlist" \
        "writes are landing under the canonical key, so this is orphaned HISTORY rather than a growing fork — but the record is still in fragments, and every other reader of that tree opens ONE directory and reports a fragment as the whole record" \
        "fold the orphaned partition(s) under \`$_canon\`, or move them out of OBSERVABILITY/ — note the guard ledger's records are per-event and unique, unlike the work-log's, where harbor#119 measured all 38 as duplicates"
    else
      # floor_host_token unavailable: the count is still true, the attribution is not.
      finding FC-9 warn "$_nhost host partitions (canonical key UNKNOWN):$_hlist" \
        "one config dir is one install, so the host key moved and the history is in fragments — and the sibling guard-lib.sh could not be read, so this cannot say which partition is the canonical one" \
        "run this from the repo so floor_host_token is reachable; the fix for the key itself is harbor#119, and a ledger copied in from another machine looks identical from here — the sink is machine-local by design"
    fi
  fi
fi

# ── FC-7 · the sink's own state ──────────────────────────────────────────────
# The gates that make the writer safe are the same gates that make it BLIND when
# they drift, and it fails blind by design: floor_log_decision refuses to write
# unless the host directory is NON-writable (property 2 — that gate, not the file
# type check, is what makes a FIFO plant unwinnable) and returns 0 when it
# refuses. So the failure state of the ledger is silence, and silence is what
# every reader renders as a healthy history.
if [ -d "$OBS" ]; then
  for _hd in "$OBS"/*; do
    [ -d "$_hd" ] || continue
    _host="$(basename "$_hd")"
    if [ -w "$_hd" ]; then
      finding FC-7 crit "$_host/ is writable" \
        "floor_log_decision refuses to write while the host directory is writable, so every guard decision from now on is dropped and no reader can tell that from a quiet day" \
        "restore the mode from your own terminal (0500 on the host directory); floor-observe.sh re-applies it at the next SessionStart"
    fi
    _sink="$_hd/guard-decisions.jsonl"
    if [ -e "$_sink" ] && { [ ! -f "$_sink" ] || [ -L "$_sink" ]; }; then
      finding FC-7 crit "$_host/guard-decisions.jsonl is not a regular file" \
        "the hot path type-checks the sink and refuses a symlink or a FIFO, so the ledger is permanently empty — and floor-observe.sh refuses to reuse it rather than overwrite whatever it points at" \
        "inspect what the path IS before removing anything: a FIFO or symlink here was planted, and its target may be a file you care about"
    fi
    if [ -f "$_sink" ] && [ ! -L "$_sink" ]; then
      _sz="$(num "$(wc -c < "$_sink" 2>/dev/null | tr -d ' ')")"
      # floor-observe.sh, ROTATE_BYTES rotates above 5 MiB and is the ONLY rotator. A sink
      # meaningfully past that has not been rotated, which means the SessionStart
      # hook that rotates it is not reaching that line — the same silence FC-1
      # counts, seen a second way. The headroom keeps a sink that merely grew past
      # the mark mid-session out of the report.
      if [ "$_sz" -gt 6291456 ]; then
        finding FC-7 warn "$_host/guard-decisions.jsonl is $((_sz / 1048576)) MiB" \
          "it is past the rotation threshold, and floor-observe.sh is the only thing that rotates it, so that hook is not reaching its rotation line" \
          "confirm floor-observe.sh runs to completion at SessionStart; do not rotate by hand from a session — the sink is a surface guard-selfedit protects"
      fi
    fi
  done
fi

# ── FC-10 · a tool failure that keeps coming back (harbor#465) ──────────────
# THE THRESHOLD IS THE WHOLE RULE, and both halves of it are in the ticket's own
# falsifier: the same failure in three separate sessions must surface as ONE
# finding naming the tool and the input, and a tool that fails ONCE must raise
# nothing. A ledger that reports every transient is one the operator mutes, after
# which it carries nothing (No.2.11) — so this needs a floor, and the floor needs
# a reason rather than a round number.
#
#   >= 3 RECORDS  — the ticket's own worked example, and the first count at which
#                   "it happened again" is a pattern rather than a coincidence.
#   >= 2 SESSIONS — this is the half that does the work. Three failures INSIDE one
#                   session is a retry loop: the operator was there, saw it, and
#                   is already dealing with it. The same failure in a SECOND
#                   session means the first session's fix did not happen or did
#                   not hold, and nothing in the box would otherwise say so —
#                   which is exactly how harbor#462 survived 34 days of sessions
#                   each independently discovering the same dead pointer.
#
# `blocked` IS EXCLUDED, and not for tidiness. A floor block reaches this event as
# a tool failure AND is already one record in guard-decisions.jsonl, judged by the
# rules above. Counting it here would double-report the floor doing its job, and
# the loudest finding in this ledger would be the control that works.
# `handoff` likewise: browser-agent refusing by its own rules and naming the operator's next step.
if [ "$NTF" -gt 0 ]; then
  # HORIZONED ON LAST OCCURRENCE, like FC-2 to FC-5: the ledger is bounded by bytes, not days, so a failure last seen weeks
  # ago was still reported as current. Measured 2026-10-26: one of three live FC-10 findings had last failed on 2026-09-28.
  jq -s -r --arg c "$FC_CUTOFF" '
      map(select(.e != "blocked" and .e != "handoff" and (.h // "-") != "-"))
    | group_by(.h)
    # Label from the NEWEST record: the oldest one of a long-lived group can predate a recorder fix (bare `mcp` before #1381).
    | map((sort_by(.ts // "") | .[-1]) as $n | { t: $n.t, k: $n.k, e: $n.e,
            n: length, s: (map(.s) | unique | length), last: (map(.ts // "" | .[0:10]) | max) })
    | map(select(.n >= 3 and .s >= 2))
    | map(select($c == "" or .last >= $c))
    | sort_by(-.n)[]
    | [.t, .k, .e, (.n|tostring), (.s|tostring)] | @tsv' \
    "$TFREC" 2>/dev/null > "$TMPD/fc10" || : > "$TMPD/fc10"
  while IFS='	' read -r _ft _fk _fe _fn _fs; do
    [ -n "${_ft:-}" ] || continue
    # A DEAD POINTER THAT NOW RESOLVES IS REPAIRED, NOT STILL DEAD. The finding's own remedy is "resolve the pointer", and nothing
    # ever read whether someone had: ~/port/harbor/CLAUDE.md stayed crit for days after harbor#954 created it, because the records
    # that said "not found" are history and the ledger keeps them for its whole retention. Only a key that is a path (~/ or /) can be
    # probed; anything else is a command or a relative name and stays reported. If the path vanishes again the finding returns.
    if [ "$_fe" = "not-found" ]; then
      case "$_fk" in "~/"*) _fp="$HOME/${_fk#"~/"}" ;; /*) _fp="$_fk" ;; *) _fp="" ;; esac
      [ -z "$_fp" ] || [ ! -e "$_fp" ] || continue
    fi
    # `not-found` across three or more sessions IS harbor#462's shape — a pointer
    # that is dead and keeps being followed — and it is the one class where the
    # repair is a one-line edit rather than an investigation. Everything else is a
    # warn: a command exiting non-zero repeatedly may be a defect or may be how
    # the operator works, and this tool does not get to decide which.
    _sev=warn
    [ "$_fe" = "not-found" ] && [ "$_fs" -ge 3 ] && _sev=crit
    _fr="if the subject is a path, resolve or delete the pointer to it; the ledger is at MEMORY/OBSERVABILITY/<host>/tool-failures.jsonl and this tool repairs nothing"
    _fsub="$_ft → $_fk"
    case "$_ft" in
      mcp__*) # an MCP server: no path to resolve, and the ledger keeps no tool name, so the remedy is to look at the server
        _fsub="MCP server ${_ft#mcp__}"; [ "$_fk" = - ] || _fsub="$_fsub → $_fk"
        _fr="check that MCP server's own state (is it attached and healthy?) and the first error of the failing call; the ledger keeps the server only, not the tool, and this tool repairs nothing" ;;
    esac
    finding FC-10 "$_sev" "$_fsub" \
      "failed $_fn time(s) across $_fs session(s) with the same input, error class '$_fe' — each session found it independently and none of them left a record the next one could read" \
      "$_fr"
  done < "$TMPD/fc10"
fi

# ── FC-11 · the recorder is wired and has nowhere to write ──────────────────
# FC-0's shape, aimed at the second ledger. The predicate is NOT "the ledger is
# empty": a box with no failed tool calls is a healthy box, and firing on that
# would be the false positive that gets this muted. It is "the hook is wired and
# the SINK DOES NOT EXIST" — which means floor-observe.sh never prepared it, and
# every failure since is being dropped by the two gates in failure-observe.sh
# rather than recorded.
#
# WARN, NOT CRIT, and the reason is a real window rather than a hedge: a box
# installed but not yet restarted legitimately has no sink until the next
# SessionStart. A crit that clears itself by waiting teaches the reader to wait.
if [ "$TF_WIRED" = yes ] && [ -d "$OBS" ]; then
  _tf_sinks="$(find "$OBS" -type f -name 'tool-failures.jsonl' 2>/dev/null | awk 'END{print NR+0}')"
  _tf_hosts="$(find "$OBS" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | awk 'END{print NR+0}')"
  if [ "$_tf_hosts" -gt 0 ] && [ "$_tf_sinks" -eq 0 ]; then
    finding FC-11 warn "$OBS/tool-failures.jsonl" \
      "failure-observe.sh is wired at PostToolUseFailure and no sink exists in any host partition, so every failed tool call is being dropped — and this ledger's other rules would report clean, because a ledger that was never written looks exactly like a box that never failed" \
      "floor-observe.sh is the only component allowed to create it, at SessionStart: confirm it is wired, start a session, re-run. If it was only just installed, one restart is the whole fix — and if the floor was UNINSTALLED here on purpose, floor-observe.sh went with it, so unwire failure-observe.sh from PostToolUseFailure rather than leaving a recorder that can never record"
  fi
fi

# ── report ───────────────────────────────────────────────────────────────────
NFIND="$(printf '%s' "$FINDINGS" | awk 'NF{n++} END{print n+0}')"
# info rows are history: reported, never counted toward the exit status or the clean verdict.
NACT="$(printf '%s' "$FINDINGS" | awk -F'\t' 'NF && $2!="info"{n++} END{print n+0}')"
: "${PROBE_OK:=0}"
# Same reason as the line above: the per-host loop is where both are set, and a
# box with no host partition never enters it.
: "${SUITE_OK:=0}"

if [ "$JSON" = 1 ]; then
  # One dataset, two renderers. A reporter that builds its JSON from a second pass
  # is a reporter whose two outputs can disagree (reference-check.sh:78-80).
  # `worst` uses pulse.sh's exact vocabulary, so a pulse check over this is one
  # line rather than a translation layer.
  printf '%s' "$FINDINGS" | jq -R -s \
    --arg dir "$DIR" --arg worst "$WORST" --argjson records "$NREC" \
    --argjson toolfails "$NTF" \
    --argjson probes "$PROBE_OK" --argjson suite "$SUITE_OK" '
    { dir: $dir, installed: true, records: $records, tool_failures: $toolfails,
      worst: $worst,
      probe_traffic_excluded: ($probes == 1),
      suite_traffic_excluded: ($suite == 1),
      findings: [ split("\n")[] | select(length > 0) | split("\t")
                  | {rule: .[0], severity: .[1], subject: .[2], breaks: .[3], repair: .[4]} ] }
    | . + {clean: (([.findings[] | select(.severity != "info")] | length) == 0)}'
elif [ "$_LOGLIB" = 0 ]; then
  # A copy with no log-lib.sh beside it says so rather than printing half a report. --json needs none.
  printf 'failure-capture: log-lib.sh is missing beside %s, so this copy cannot print its report; --json still works\n' "${SELF:-?}" >&2
else
  log_head "$OBS"
  # BOTH DENOMINATORS, ALWAYS (harbor#467). Two ledgers now feed this, and one of
  # them reading zero is a different fact from the other reading zero — a report
  # that summed them, or named only the first, would let a dead recorder hide
  # behind a healthy one.
  log_note "$NREC guard decision(s) · $NTF tool failure(s) read · worst: $WORST"
  if [ "$NFIND" -eq 0 ]; then
    # BOTH LEDGERS, OR THE SENTENCE IS FALSE. This read `$NREC -eq 0` alone and
    # printed "there is no ledger to judge" over five tool-failure records —
    # caught by the fixture that first exercised the second ledger, and it is
    # harbor#467's defect reappearing one file over: a clean line that describes a
    # state the tool is not in.
    if [ "$NREC" -eq 0 ] && [ "$NTF" -eq 0 ] && [ "$FLOOR_WIRED" = no ]; then
      log_skip "no floor is wired here and no tool failure is recorded, so there is nothing to judge"
    else
      log_ok "nothing in either ledger says the floor or a tool is failing"
      [ "$PROBE_OK" = 1 ] || log_note "the verifier's own probe shapes were NOT separated from the recurrence count"
    fi
  else
    # One line per finding: crit is a FAIL, warn and unknown a WARN, and the repair is its fix line.
    # Read from a file, not a pipe, so the counters log_end reports survive the loop.
    printf '%s' "$FINDINGS" > "$TMPD/report"
    while IFS='	' read -r r s j w p; do
      [ -n "${r:-}" ] || continue
      case "$s" in
        crit) log_fail "$r $j — $w"; log_fix "$p" ;;
        warn) log_warn "$r $j — $w"; log_fix "$p" ;;
        info) log_note "$r [info] $j — $w" ;;
        *)    log_warn "$r [$s] $j — $w"; log_fix "$p" ;;
      esac
    done < "$TMPD/report"
    log_note "$NFIND finding(s). NOTHING here is repaired by this tool: every surface it names is one guard-selfedit.sh protects, so a version that could fix them would be a version that can disable the floor. Each fix line is for a human at their own terminal."
  fi
  log_end || :
fi

[ "$NACT" -eq 0 ] || exit 1
exit 0
