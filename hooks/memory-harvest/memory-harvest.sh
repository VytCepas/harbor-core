#!/usr/bin/env sh
# memory-harvest (harbor#6 — workstream D, D1) — the work-log reconciler.
#
# THE GAP IT CLOSES. worklog-push.sh writes a session record on Stop. A session
# that crashes, is killed, or ends with the machine asleep never reaches Stop, so
# it leaves a transcript and no record. Measured on this machine before this hook
# existed: 87 transcripts in 30 days, 61 of them with no work-log record. D1's
# done-when is "a crashed session re-harvests on next start"; this is that.
#
# IT NEVER OPENS A TRANSCRIPT. Everything it needs is in the index: the session
# id is the filename, the project is the directory name, and the clock is the
# file's mtime. That is not a shortcut — DEAD-ENDS DE-16 rejected building a
# durable corpus out of transcript CONTENT, because it outlives the 30-day GC
# that deletes the transcripts and because a shape-preserving scrubber still let
# live-secret-shaped payloads through. Reading only the index makes the whole
# class unreachable rather than mitigated. There is no scrubber here because
# there is nothing to scrub.
#
# WIRED AT STOP, NOT SessionStart, and the ticket says SessionStart. Every hook
# here reads the session's resolved context, and the thing that WRITES it is
# context-resolve.sh — itself a SessionStart hook. Nothing orders the two, so on
# a fresh session the context may not exist yet when this runs, and the
# fail-toward-repo default then correctly makes it a no-op. At Stop the context
# is reliably present (observed: the live store carries records written by
# worklog-push.sh, which reads it there). A crashed session is still reconciled
# with no operator action — at the end of the next session rather than the start.
# Buying the ticket's literal wording by weakening the stand-down default would
# trade a safety property for a schedule. contracts/cli.md records this.
# (Since harbor#954 the stand-down reads only the repo's `worklog: off`.)
#
# BOUNDED, because a Stop hook is still on a path the operator waits for.
# DEAD-ENDS DE-09: a hook that exceeds its timeout is SKIPPED, so a slow
# reconciler does not fail loudly — it silently stops running, and a fail-open
# bypass wearing a performance regression's clothes is the worst shape
# available. Two bounds: a day window, and a per-run cap. What the cap drops is
# REPORTED, never silent: a run that quietly covered half the backlog reads
# exactly like one that covered all of it.
#
# NEVER BLOCKS THE SESSION: every path exits 0.
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WORKLOG_DIR="${HARBOR_LOG_DIR:-$CFG/MEMORY}"
PROJECTS="${HARBOR_TRANSCRIPT_DIR:-$CFG/projects}"
DAYS="${HARBOR_HARVEST_DAYS:-7}"
CAP="${HARBOR_HARVEST_CAP:-25}"

# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
[ ! -f "$DIR/manifest.tsv" ] || DIR="$DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
. "$DIR/guard-lib.sh"
# Its one line goes to stderr: a Stop hook's stdout is the harness's (contracts/logging.md).
LOG_FD=2; . "$DIR/library-log.sh"

# Stdin FIRST: the shared resolver reads .cwd from the payload, and the
# stand-down decision depends on it. Same order as worklog-push.sh.
floor_read_stdin
# Stands down only on the repo's `worklog: off` — identical to worklog-push.sh (harbor#954).
floor_engine_stand_down && exit 0

[ -d "$WORKLOG_DIR/.git" ] || exit 0
[ -d "$PROJECTS" ] || exit 0

HOST="$(floor_host_token)"

# Every session id already recorded under ANY host partition, from the FILENAMES —
# the record's name is <date>-<session-id>.md and the date is not known in advance,
# so matching on the id means stripping the date rather than guessing it.
#
# ALL partitions, not just this host's (PR #119 review). A session id belongs to
# exactly one machine, so "recorded anywhere" is the correct predicate, while
# scoping the check to $HOST makes every record written under a PREVIOUS host token
# invisible: the session reads as unharvested and gets written a second time.
#
# Not hypothetical, and not a risk this change introduces — it is a duplication this
# change STOPS. The 2026-08-04 token flip did exactly this, and every one of the 38
# session records it wrote under `Mac` was a duplicate of one that already existed
# under the real host name: 38 ids in both directories, 0 unique to `Mac`. Writes
# still go to $HOST; only the reconciliation predicate is host-agnostic.
SEEN="$(find "$WORKLOG_DIR/WORK/sessions" -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null \
  | sed -e 's|.*/||' -e 's/\.md$//' -e 's/^[0-9][0-9-]*-//' | LC_ALL=C sort -u)"

# A project directory name is the cwd with every separator replaced by a dash,
# which is LOSSY: a path that itself contains a dash is indistinguishable from a
# separator. So the decode is checked rather than trusted — if the reconstructed
# path is a real directory, use it; otherwise record the encoded name verbatim
# and let the reader see that it is encoded. Guessing a plausible path that was
# never the cwd would be worse than showing the raw one.
decode_cwd() { # <project-dir-name>
  _dc_raw="$1"
  _dc_try="$(printf '%s' "$_dc_raw" | sed 's|-|/|g')"
  if [ -d "$_dc_try" ]; then printf '%s' "$_dc_try"; else printf '%s' "$_dc_raw"; fi
}

WROTE=0
SKIPPED_CAP=0
set -f   # a project dir name is data; nothing here may be glob-expanded

for f in $(find "$PROJECTS" -maxdepth 2 -type f -name '*.jsonl' -mtime "-$DAYS" 2>/dev/null | LC_ALL=C sort); do
  [ -f "$f" ] || continue
  SID="$(basename "$f" .jsonl)"
  [ -n "$SID" ] || continue

  # Already recorded — by id, whatever date the record carries.
  printf '%s\n' "$SEEN" | LC_ALL=C "$FLOOR_GREP" -qxF -- "$SID" && continue

  PROJ="$(basename "$(dirname "$f")")"
  # Harness scratch directories are not work. They are created by test runs and
  # e2e probes under the system temp dir, and backfilling them would fill the
  # cross-device work-log with sessions that never belonged to anyone.
  case "$PROJ" in
    -private-tmp*|-tmp*|-var-folders*) continue ;;
  esac

  if [ "$WROTE" -ge "$CAP" ]; then
    SKIPPED_CAP=$((SKIPPED_CAP + 1))
    continue
  fi

  # The transcript's mtime is the closest available stamp for when the session
  # ended. `date -r` reads a file's mtime on both BSD and GNU date.
  STAMP="$(date -r "$f" +'%Y-%m-%d %H:%M' 2>/dev/null)" || continue
  [ -n "$STAMP" ] || continue
  D_DATE="${STAMP%% *}"
  D_TIME="${STAMP##* }"

  floor_worklog_record "$WORKLOG_DIR" "$HOST" "$SID" "$D_DATE" "$D_TIME" \
    "$(decode_cwd "$PROJ")" "reconciled" || continue
  WROTE=$((WROTE + 1))
  SEEN="$SEEN
$SID"
done

# NO SILENT CAPS. If the backlog is bigger than one run may write, say so — the
# next Stop takes the next batch, and the operator can see it happening instead
# of wondering why the log is still short.
if [ "$SKIPPED_CAP" -gt 0 ]; then
  log_note "wrote $WROTE record(s); $SKIPPED_CAP more still unrecorded (cap $CAP, next Stop continues)"
  log_end || :
fi

exit 0
