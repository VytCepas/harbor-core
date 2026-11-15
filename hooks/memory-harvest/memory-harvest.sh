#!/usr/bin/env sh
# memory-harvest (harbor#6 — workstream D, D1) — the work-log reconciler.
# The work-log reconciler: a session that crashes or is killed never reaches Stop, so worklog-push.sh writes no record; this re-harvests it on the next start (D1).
# It NEVER OPENS A TRANSCRIPT: the session id is the filename, the project the directory, the clock the mtime. DEAD-ENDS DE-16 rejected a durable corpus of transcript content (it outlives the 30-day GC and scrubbers let secrets through), so there is nothing to scrub.
# Wired at SessionStart (harbor#1390); the starting session is skipped, its record is Stop's to write. hooks/memory-harvest/manifest.tsv carries the history.
# Bounded (DEAD-ENDS DE-09: a hook over its timeout is SKIPPED, silently): a day window and a per-run cap, and what the cap drops is REPORTED. Every path exits 0.
# Removed notes: docs/explanation/code-cases/hooks-memory-harvest-memory-harvest.md
set -u

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
WORKLOG_DIR="${HARBOR_MEMORY_LOG_DIR:-$CFG/MEMORY}"
PROJECTS="${HARBOR_MEMORY_TRANSCRIPT_DIR:-$CFG/projects}"
DAYS="${HARBOR_MEMORY_HARVEST_DAYS:-7}"
CAP="${HARBOR_MEMORY_HARVEST_CAP:-25}"

# harbor#813: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh from it.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
[ ! -f "$DIR/manifest.tsv" ] || DIR="$DIR/../../bin"  # D-88: in the repo an engine sits beside its manifest in hooks/<engine>/; deployed, flat beside its libraries
. "$DIR/library-admission.sh"
# Its one line goes to stderr: a hook's stdout is the harness's (contracts/logging.md).
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$DIR/library-log.sh"

# Stdin FIRST: the resolver reads .cwd from the payload (same order as worklog-push.sh).
floor_read_stdin
# Stands down only on the repo's `worklog: off` — identical to worklog-push.sh (harbor#954).
floor_engine_stand_down && exit 0
# The session that is starting: its record is worklog-push's to write at Stop (harbor#1390).
SELF="$(floor_field '.session_id')"

[ -d "$WORKLOG_DIR/.git" ] || exit 0
[ -d "$PROJECTS" ] || exit 0

HOST="$(floor_host_token)"

# Session ids already recorded under ANY host partition (PR #119): an id belongs to one machine, and scoping to $HOST made records written under a previous host token read as unharvested and written twice. Writes still go to $HOST.
SEEN="$(find "$WORKLOG_DIR/WORK/sessions" -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null \
  | sed -e 's|.*/||' -e 's/\.md$//' -e 's/^[0-9][0-9-]*-//' | LC_ALL=C sort -u)"

# A project dir name is the cwd with separators dashed, which is lossy: the decode is checked against a real directory, else the encoded name is kept verbatim.
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
  [ "$SID" != "$SELF" ] || continue

  printf '%s\n' "$SEEN" | LC_ALL=C "$FLOOR_GREP" -qxF -- "$SID" && continue

  PROJ="$(basename "$(dirname "$f")")"
  # Harness scratch dirs (test runs, probes under the system temp dir) are not work.
  case "$PROJ" in
    -private-tmp*|-tmp*|-var-folders*) continue ;;
  esac

  if [ "$WROTE" -ge "$CAP" ]; then
    SKIPPED_CAP=$((SKIPPED_CAP + 1))
    continue
  fi

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

# No silent caps: say so when the backlog exceeds one run; the next session start takes the next batch.
if [ "$SKIPPED_CAP" -gt 0 ]; then
  log_note "wrote $WROTE record(s); $SKIPPED_CAP more still unrecorded (cap $CAP, the next session start continues)"
  log_end || :
fi

exit 0
