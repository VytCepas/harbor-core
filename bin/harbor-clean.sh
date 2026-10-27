#!/usr/bin/env sh
# harbor-clean.sh (harbor#456) — the machine-decidable half of skills/housekeeping.
# Deliberately one file (DOCTRINE/modularity.md): `module-shape.sh --seam` reads it
# "real but PRIVATE — leave it one file" (2026-09-22). See OVER 300 LINES below.
#
# WHAT THIS IS FOR. A box accretes: 1,134 empty session directories, 859 MB of
# unrotated CI logs, worktree registrations a test suite left behind, branches
# whose content is already in main. Deciding which of those is dead is
# mechanical. Deciding to delete is not, so this reports by default and the
# operator says --apply.
#
# THE REFUSALS ARE THE PRODUCT, NOT THE RECLAIMS. Every class below carries a
# predicate, and a class that fails its predicate is printed as KEEP with the
# reason. Measured 2026-09-06 on this box: `security/agent-sdk-venv` is 282 MB
# untouched for 50 days AND is live plugin state that `ensure_agent_sdk.py`
# recreates; `.helm-replay` is 820 KB untouched for 31 days AND is read by
# replay.sh. Both would have looked like the two biggest wins available. A
# cleaner that cannot say why it left something is one nobody can audit, and the
# whole risk here is a confident sweep that removes a recovery path.
#
# NEVER DELETES, EVEN UNDER --apply:
#   · anything under ~/.claude that floor state depends on (.helm-*, backups/,
#     MEMORY/, the pins and salts) — guard-integrity reads them and the obs salt
#     makes the decision ledger unreadable
#   · ~/.claude/projects transcripts — cleanupPeriodDays owns those, and
#     usage-aggregate.sh reads them
#   · a git branch whose tree is not already main's
#   · a worktree with uncommitted files or unpushed commits
#   · a worktree that still exists on disk and belongs to another session
#   · runner _work while any runner reports busy
# The suite (harbor-clean-test.sh) asserts each of those refusals, because a
# refusal nothing tests is a comment.
#
# FOUR VERDICTS, AND ONLY ONE OF THEM IS EVER ACTED ON HERE:
#   RECLAIM  dead by a predicate this file can decide; --apply acts on it
#   DECIDE   a person has to choose — delete a branch whose PR merged, close an
#            issue, merge a green PR, move a loose file. --apply NEVER touches it
#   RISK     work that exists in one place only and is going stale — uncommitted
#            changes in a finished worktree, a branch on no remote and in no PR,
#            an old stash, a checkout marked bare. Never touched either
#   KEEP     looks like trash, is not; the reason is the row
# DECIDE and RISK are what skills/housekeeping turns into ONE batch for the
# operator to approve. They exist because most of what accumulates on this box is
# not machine-decidable. Measured 2026-09-22 against the version before them: 61
# landed-branch rows that were 25 branches, each repeated once per worktree
# directory of its repo; nothing under the pipeline root, whose three repos sit one level
# below the walk; and no view at all of the six worktrees whose PRs had merged,
# of branches left on GitHub, or of any PR or issue.
#
# ONE ROW PER REPOSITORY, NOT PER DIRECTORY. repos() resolves every candidate to
# its primary worktree and de-duplicates, and it adds the fleet snapshot's paths
# to the $HOME walk, so the repo set is the fleet's declared one plus anything
# the snapshot missed rather than whatever happens to sit one level down.
#
# THE GITHUB LAYER is what makes "is this branch finished?" answerable. A squash
# merge leaves a branch whose tree is NOT main's, so landed-branches — correctly —
# never claims it; the PR that merged it is the only evidence it is done. One read
# of each repo's PRs, branches, open PRs and open issues, then every class joins
# against it. A repo whose read FAILS is reported as `unread`, never as clean: a
# list that silently came back empty is the exact defect harbor#626 records, and
# a sweep that says "nothing to do" because gh was logged out is worse than none.
#
# IN CHECKS.md AS `sweep`, AND THE LINE IT DRAWS. The REPORT runs on a schedule:
# --record writes a one-line count the statusline renders as 🧹N, and SWEEP when
# it is time. The DELETE does not, and nothing scheduled ever passes --apply.
# Counting is observation; deciding what to remove stays human-gated —
# CONSTITUTION "Encoding a fix is a human-gated act", with more force for a tool
# whose verb is rm.
#
# OVER 300 LINES ON PURPOSE (G1): one class per function, each independent, and
# the classes share one repo walk and one GitHub read. Split, the walk and the
# read would be done twice or passed through a file format of their own.
#
# TWO FLAGS, NOT ONE, AND D2 IS WHY. This script deletes inside the config dir
# (empty session directories, .DS_Store), so lint D2 asks it for the accident
# gate every config-dir writer here carries — and D2's header records FIVE prior
# scripts that were exempted because their --apply arm only ever wrote inside the
# repo. This one is not that shape, so it takes the gate rather than a sixth
# exemption: --apply says act, --live says act on the REAL ~/.claude. Neither
# implies the other, and HARBOR_CLEAN_HOME is a test hook, never a safety
# boundary — a suite that pins an env var proves nothing about what happens when
# the operator forgets to.
#
# USAGE
#   sh bin/harbor-clean.sh                 report only (default)
#   sh bin/harbor-clean.sh --apply         act — refuses the live config dir
#   sh bin/harbor-clean.sh --apply --live  act, including on ~/.claude
#   sh bin/harbor-clean.sh --json          machine-readable rows
#   sh bin/harbor-clean.sh <class>...      restrict to named classes
#   sh bin/harbor-clean.sh --list          the class names
#   sh bin/harbor-clean.sh --record [--live] [--if-due]
#                                          count only: write <config>/.helm-sweep
#                                          and the rows to <config>/.helm-sweep.jsonl.
#                                          Never deletes. --if-due does nothing
#                                          unless a slot (09:00, 16:00) has passed
#                                          since the last record.
# THE KEEP LIST. <config>/.helm-sweep-keep, one `class<TAB>subject<TAB>reason`
# per line: a row it names is printed as KEEP with that reason and stops counting.
# The operator's "leave it" has to be durable, or the same row is asked about
# twice a day forever and the count becomes wallpaper.
# ENV
#   HARBOR_CLEAN_HOME     root to scan (default $HOME) — the suite pins this
#   HARBOR_CLEAN_AGE      age floor in days for log classes (default 14)
#   HARBOR_CLEAN_IDLE     days before unmerged work counts as idle (default 7)
#   HARBOR_CLEAN_GH       the gh binary; `none` switches the GitHub layer off,
#                         which reports every GitHub repo as unread
#   HARBOR_CLEAN_SCRATCH  session scratch root (default /tmp/claude-<uid>)
#   HARBOR_CLEAN_SLOTS    record hours for --if-due (default "9 16", operator
#                         decision 2026-09-22)
#   HARBOR_CLEAN_DUE      rows that make the count due (default 10)
#   HARBOR_NOW            epoch to judge ages against — the suite pins this
#   HARBOR_CLEAN_BOUND    seconds before a GitHub read is killed (default: each read's
#                         own, 90-120) — the suite shortens it (harbor#768)
set -eu
# The report's header, notes and summary are log-lib lines (CONTRACTS/logging.md); its rows are data.
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/log-lib.sh"
. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/fs-lib.sh"
log_init harbor-clean

HOME_DIR="${HARBOR_CLEAN_HOME:-$HOME}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME_DIR/.claude}"
AGE="${HARBOR_CLEAN_AGE:-14}"
IDLE="${HARBOR_CLEAN_IDLE:-7}"
GH="${HARBOR_CLEAN_GH:-gh}"
SCRATCH="${HARBOR_CLEAN_SCRATCH:-/tmp/claude-$(id -u)}"
SLOTS="${HARBOR_CLEAN_SLOTS:-9 16}"
DUE_AT="${HARBOR_CLEAN_DUE:-10}"
NOW="${HARBOR_NOW:-$(date +%s)}"
KEEPF="$CFG/.helm-sweep-keep"
APPLY=0
JSON=0
LIVE=0
RECORD=0
IFDUE=0
WANT=""

CLASSES="session-env empty-dirs runner-diag pycache-in-payload ds-store dead-caches loose-backups landed-branches prunable-worktrees bare-checkout loose-deliverables finished-worktrees pr-branches remote-branches stale-checkouts old-stashes stray-files waiting-prs closable-issues old-scratch old-downloads"

# The header IS the help: printed up to the first line of code, so it cannot
# stop short of the flags the way a fixed line range did once the header grew.
usage() {
  awk 'NR<3{next} /^set -eu/{exit} {sub(/^# ?/,""); print}' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --live)  LIVE=1 ;;
    --json)  JSON=1 ;;
    --record) RECORD=1 ;;
    --if-due) IFDUE=1 ;;
    --list)  printf '%s\n' $CLASSES; exit 0 ;;
    -h|--help) usage ;;
    -*) echo "harbor-clean: unknown flag $1" >&2; exit 2 ;;
    *) WANT="$WANT $1" ;;
  esac
  shift
done

# THE PHYSICAL COMPARE IS P11-01's, and guard-integrity.sh makes the same one
# for the same reason: a trailing slash, a symlink or a relative spelling must
# not decide which box gets rewritten.
# LIVE_DIR, not a bare path, and lint D1 draws exactly this line: naming the live
# dir in order to COMPARE it is the sanctioned idiom; reading or writing state
# through a hardcoded path is not. Nothing here operates on LIVE_DIR.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
CFG_IS_LIVE=0
[ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ] && CFG_IS_LIVE=1
if [ "$APPLY" -eq 1 ] && [ "$CFG_IS_LIVE" -eq 1 ] && [ "$LIVE" -eq 0 ]; then
  LOG_FD=2
  log_fail "refusing to act on the live config dir without an explicit --live ($CFG)"
  log_fix "sh bin/harbor-clean.sh --apply --live"
  log_note "or re-run without --apply for the full report, KEEP rows first: they are the ones worth reading"
  log_end; exit 1
fi
if [ "$RECORD" -eq 1 ] && [ "$APPLY" -eq 1 ]; then
  echo "harbor-clean: --record counts and never deletes; it does not combine with --apply" >&2
  exit 2
fi
if [ "$RECORD" -eq 1 ] && [ "$CFG_IS_LIVE" -eq 1 ] && [ "$LIVE" -eq 0 ]; then
  LOG_FD=2
  log_fail "refusing to record into the live config dir without an explicit --live ($CFG)"
  log_fix "sh bin/harbor-clean.sh --record --live"
  log_end; exit 1
fi

# ── --record --if-due: the two daily slots, and one sweep at a time ─────────
# RIDES THE fleet-snapshot JOB, which fires every 300s, rather than a launchd
# job of its own (operator decision 2026-09-22: that job, at 09:00 and 16:00).
# So the gate is here: the latest slot at or before NOW, and the `at=` stamp of
# the last record. A record stamped after the slot means this slot is done.
# Stamped, not mtime: the stamp is the moment the sweep STARTED, and a sweep that
# takes two minutes must not make the next tick think a later slot is covered.
REC="$CFG/.helm-sweep"
last_slot() {
  _hms="$(date -r "$NOW" '+%H %M %S' 2>/dev/null || date -d "@$NOW" '+%H %M %S')"
  set -- $_hms
  _sod=$(( ${1#0} * 3600 + ${2#0} * 60 + ${3#0} ))
  _mid=$(( NOW - _sod )); _best=""; _max=0
  for _h in $SLOTS; do
    _s=$(( _mid + _h * 3600 ))
    [ "$_h" -gt "$_max" ] && _max="$_h"
    if [ "$_s" -le "$NOW" ] && { [ -z "$_best" ] || [ "$_s" -gt "$_best" ]; }; then _best="$_s"; fi
  done
  [ -n "$_best" ] || _best=$(( _mid - 86400 + _max * 3600 ))
  printf '%s' "$_best"
}
LOCK="$CFG/.helm-sweep.lock"
if [ "$RECORD" -eq 1 ]; then
  mkdir -p "$CFG"
  if [ "$IFDUE" -eq 1 ] && [ -f "$REC" ]; then
    _at="$(sed -n 's/.* at=\([0-9][0-9]*\).*/\1/p' "$REC" | head -n 1)"
    if [ -n "$_at" ] && [ "$_at" -ge "$(last_slot)" ]; then exit 0; fi
  fi
  # A lock older than 30 minutes is a sweep that died, not one that is running:
  # the slowest measured run is minutes, and a dead lock must not stop every
  # later slot in silence.
  if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
      rmdir "$LOCK" 2>/dev/null || true
      mkdir "$LOCK" 2>/dev/null || exit 0
    else
      exit 0
    fi
  fi
fi

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/harbor-clean.XXXXXX")"
trap 'rm -rf "$TMPD"; [ "$RECORD" -eq 1 ] && rmdir "$LOCK" 2>/dev/null; true' EXIT
trap '[ -z "${_bp:-}" ] || { kill "$_bw" 2>/dev/null; _kill_tree "$_bp"; }; exit 1' INT TERM HUP
if [ "$RECORD" -eq 1 ]; then JSON=1; exec 3>&1 >"$TMPD/rows.jsonl"; fi

selected() {
  [ -z "$WANT" ] && return 0
  case " $WANT " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

N_RECLAIM=0
N_KEEP=0
N_DECIDE=0
N_RISK=0
UNREAD=0
BYTES=0

# JSON string escaping, forked only when a value needs it — a branch name or a
# stash message can carry a quote, and one bad line poisons every consumer that
# reads the file a line at a time.
_je() {
  case "$1" in
    *[\\\"]*) printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' ;;
    *) printf '%s' "$1" ;;
  esac
}

# row <verdict> <class> <bytes> <subject> <reason> [<action>]
# <action> is the command a person would run for a DECIDE or RISK row. It is
# printed, never executed here: skills/housekeeping runs it after a yes.
#
# ITS VARIABLES ARE __-PREFIXED BECAUSE sh HAS NO `local`. Named _r/_s/_b they
# overwrote the callers' repo, slug and branch mid-loop, and every later branch
# in that repo was judged against a repo path that was a sentence — reading as
# "on no remote, only copy". Caught on the first live run, 2026-09-22.
row() {
  __v="$1"; __c="$2"; __b="$3"; __s="$4"; __r="$5"; __a="${6:-}"
  if [ "$__v" != KEEP ] && [ -s "$KEEPF" ]; then
    __k="$(awk -F'\t' -v c="$__c" -v s="$__s" '$1==c && $2==s {print $3; exit}' "$KEEPF" 2>/dev/null || true)"
    if [ -n "$__k" ]; then __v=KEEP; __r="kept by the operator: $__k"; __a=""; fi
  fi
  case "$__v" in
    RECLAIM) N_RECLAIM=$((N_RECLAIM+1)); BYTES=$((BYTES+__b)) ;;
    DECIDE)  N_DECIDE=$((N_DECIDE+1)) ;;
    RISK)    N_RISK=$((N_RISK+1)) ;;
    KEEP)    N_KEEP=$((N_KEEP+1)) ;;
  esac
  if [ "$JSON" -eq 1 ]; then
    printf '{"verdict":"%s","class":"%s","bytes":%s,"subject":"%s","reason":"%s","action":"%s"}\n' \
      "$__v" "$__c" "$__b" "$(_je "$__s")" "$(_je "$__r")" "$(_je "$__a")"
  else
    printf '  %-8s %-22s %8s  %s\n' "$__v" "$__c" "$(human "$__b")" "$__s"
    [ -n "$__r" ] && printf '           %-22s %8s  %s\n' "" "" "$__r"
    [ -n "$__a" ] && printf '           %-22s %8s  → %s\n' "" "" "$__a"
  fi
  return 0
}

days() { printf '%s' $(( (NOW - $1) / 86400 )); }

# mtime and size through fs-lib (harbor#618); when unreadable, now and 0, so an unreadable file reads as
# fresh and empty, never as garbage in the report's arithmetic.
mtime() { _hm="$(fs_mtime "$1")"; printf '%s' "${_hm:-$NOW}"; }
fsize() { _hz="$(fs_size "$1")"; printf '%s' "${_hz:-0}"; }

human() {
  awk -v b="$1" 'BEGIN{
    if (b<1024) { printf "%dB", b; exit }
    if (b<1048576) { printf "%.0fK", b/1024; exit }
    if (b<1073741824) { printf "%.0fM", b/1048576; exit }
    printf "%.1fG", b/1073741824
  }'
}

dirbytes() { du -sk "$1" 2>/dev/null | awk '{print $1*1024}'; }

# ── the classes that are NEVER touched, printed so the reader sees them ──────
# Printed under --json too: a consumer that only sees reclaims cannot tell this
# tool apart from one that had no opinion about the 282 MB it left behind.
refusals() {
  selected sacred || return 0
  for p in "$CFG/security/agent-sdk-venv|LIVE plugin state — ensure_agent_sdk.py recreates it" \
           "$CFG/.helm-replay|LIVE corpus — replay.sh and pass-score.sh read it" \
           "$CFG/backups|the recovery store restore.sh is built on" \
           "$CFG/MEMORY|the memory store; a git repo" \
           "$CFG/projects|harness-managed by cleanupPeriodDays; usage-aggregate.sh reads it" \
           "$CFG/.helm-pins|floor pins — guard-integrity fails closed without them"; do
    _path="${p%%|*}"; _why="${p#*|}"
    [ -e "$_path" ] || continue
    row KEEP sacred "$(dirbytes "$_path")" "${_path#$HOME_DIR/}" "$_why"
  done
}

# ── A · empty per-session directories ───────────────────────────────────────
c_session_env() {
  selected session-env || return 0
  d="$CFG/session-env"
  [ -d "$d" ] || return 0
  n=0
  for s in "$d"/*/; do
    [ -d "$s" ] || continue
    # EMPTY is the predicate, and `rmdir` is the mechanism precisely because it
    # CANNOT remove a non-empty directory — a stronger guarantee than any filter
    # this script could write, and it fails safe on a race with a live session.
    if [ -z "$(ls -A "$s" 2>/dev/null)" ]; then n=$((n+1)); fi
  done
  if [ "$n" -gt 0 ]; then
    row RECLAIM session-env 0 "$n empty session dir(s) under ${d#$HOME_DIR/}" \
      "rmdir only — it refuses a non-empty dir, so a live session cannot be hit"
    [ "$APPLY" -eq 1 ] && ( cd "$d" && rmdir ./*/ 2>/dev/null || true )
  fi
  # A session dir that is NOT empty is somebody's state; say so rather than
  # leaving the count unexplained.
  k=0
  for s in "$d"/*/; do
    [ -d "$s" ] || continue
    [ -n "$(ls -A "$s" 2>/dev/null)" ] && k=$((k+1))
  done
  [ "$k" -gt 0 ] && row KEEP session-env 0 "$k non-empty session dir(s)" \
    "they hold files — that is state, not residue"
  return 0
}

# ── C · CI logs, age-bounded ────────────────────────────────────────────────
c_runner_diag() {
  selected runner-diag || return 0
  for r in "$HOME_DIR"/actions-runner*; do
    [ -d "$r/_diag" ] || continue
    b=0
    for f in $(find "$r/_diag" -type f -mtime "+$AGE" -name '*.log' 2>/dev/null); do
      b=$((b + $(fsize "$f")))
    done
    if [ "$b" -gt 0 ]; then
      row RECLAIM runner-diag "$b" "${r#$HOME_DIR/}/_diag (*.log older than ${AGE}d)" \
        "runner logs are unrotated and append-only; an in-flight job's files are newer than the cut"
      [ "$APPLY" -eq 1 ] && find "$r/_diag" -type f -mtime "+$AGE" -name '*.log' -delete 2>/dev/null || true
    fi
  done
  # _work is NEVER reclaimed here: a busy runner is mid-checkout, and even idle
  # it costs a re-clone. Named so the bytes are not silently ignored.
  for r in "$HOME_DIR"/actions-runner*; do
    [ -d "$r/_work" ] || continue
    row KEEP runner-work "$(dirbytes "$r/_work")" "${r#$HOME_DIR/}/_work" \
      "a checkout, not residue — verify every runner is idle first, then age-prune per repo"
  done
  return 0
}

# ── C · bytecode inside a hashed payload ────────────────────────────────────
c_pycache() {
  selected pycache-in-payload || return 0
  # Scoped to payload/template trees, where bytecode does not merely clutter but
  # POISONS a content hash (project-init#972). A __pycache__ beside ordinary
  # source is the interpreter's business, not this tool's.
  for root in "$HOME_DIR"/project-init/plugins "$HOME_DIR"/project-init/templates; do
    [ -d "$root" ] || continue
    b=0; n=0
    for d in $(find "$root" -type d -name '__pycache__' 2>/dev/null); do
      n=$((n+1)); b=$((b + $(dirbytes "$d")))
    done
    if [ "$n" -gt 0 ]; then
      row RECLAIM pycache-in-payload "$b" "$n __pycache__ dir(s) under ${root#$HOME_DIR/}" \
        "inside a hashed payload it reddens a lock test that is green on CI — project-init#972"
      [ "$APPLY" -eq 1 ] && find "$root" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
    fi
  done
  return 0
}

# ── E · git: landed branches, prunable worktrees, a bare working checkout ───
# One line per REPOSITORY: every candidate directory resolved to its primary
# worktree, then de-duplicated. Walking directories instead reported each branch
# once per worktree of its repo (measured 2026-09-22: 61 rows for 25 branches).
# A checkout marked bare lists its gitdir as the primary, so `/.git` is stripped
# and bare-checkout can still find it. Computed once per run.
repos() {
  if [ ! -f "$TMPD/repos" ]; then
    {
      # The port root too (harbor#619 moved every repo to ~/port/<repo> on
      # 2026-09-23). ~/*/ alone found the moved repos only THROUGH the symlinks
      # left at their old addresses, which phase C deletes. While both exist a
      # repo is seen twice; the primary-worktree resolution below dedupes it.
      for _d in "$HOME_DIR"/*/ "${PORT_ROOT:-$HOME_DIR/port}"/*/; do
        [ -e "$_d/.git" ] && printf '%s\n' "${_d%/}"
      done
      _fs="${HARBOR_CACHE_DIR:-$CFG/cache}/fleet-snapshot.json"
      if [ -f "$_fs" ] && command -v jq >/dev/null 2>&1; then
        jq -r '.[]? | .descriptor.path? // empty' "$_fs" 2>/dev/null || true
      fi
    } | while IFS= read -r _d; do
      [ -d "$_d" ] || continue
      _p="$(git -C "$_d" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
      [ -n "$_p" ] && printf '%s\n' "${_p%/.git}"
    done | sort -u > "$TMPD/repos"
  fi
  cat "$TMPD/repos"
}

# Where a repo is named in a row: relative to the scanned home, so ~/port/<container>/<repo> and
# ~/port/<repo> cannot collide the way two basenames can.
rname() { printf '%s' "${1#$HOME_DIR/}"; }

# Every branch checked out anywhere in the repo, one per line. Those belong to
# the worktree and checkout classes, and `git branch -D` refuses them anyway.
checked_out() {
  git -C "$1" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p'
}

# Exact whole-line membership. awk, not `grep -x`: grep on this box is ugrep,
# whose defaults differ, and a membership test must not depend on which grep.
inlist() { awk -v n="$1" '$0 == n {f = 1} END {exit !f}' "$2" 2>/dev/null; }

c_landed_branches() {
  selected landed-branches || return 0
  : > "$TMPD/landed"
  for d in $(repos); do
    git -C "$d" rev-parse --verify origin/main >/dev/null 2>&1 || continue
    mt="$(git -C "$d" rev-parse 'origin/main^{tree}' 2>/dev/null)" || continue
    checked_out "$d" > "$TMPD/co"
    for b in $(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null); do
      [ "$b" = "main" ] && continue
      inlist "$b" "$TMPD/co" && continue
      # THE PREDICATE IS merge-tree, NEVER `git cherry` — which misclassifies a
      # cherry-pick. A branch is landed only when merging it produces main's
      # tree exactly; "no unique commits" is a weaker and wronger question.
      t="$(git -C "$d" merge-tree --write-tree origin/main "$b" 2>/dev/null)" || continue
      if [ "$t" = "$mt" ]; then
        row RECLAIM landed-branches 0 "$(rname "$d") $b" \
          "merge-tree == origin/main^{tree}: merging it would change nothing"
        printf '%s\t%s\n' "$d" "$b" >> "$TMPD/landed"
        [ "$APPLY" -eq 1 ] && git -C "$d" branch -D "$b" >/dev/null 2>&1 || true
      fi
    done
  done
  return 0
}

c_prunable_worktrees() {
  selected prunable-worktrees || return 0
  for d in $(repos); do
    n="$(git -C "$d" worktree list 2>/dev/null | grep -c 'prunable' || true)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$n" -gt 0 ]; then
      row RECLAIM prunable-worktrees 0 "$(rname "$d"): $n prunable registration(s)" \
        "gitdir is gone — commonly a test suite that ran worktree add against the real repo"
      [ "$APPLY" -eq 1 ] && git -C "$d" worktree prune >/dev/null 2>&1 || true
    fi
  done
  return 0
}

c_bare_checkout() {
  selected bare-checkout || return 0
  # NOT trash — DAMAGE, and it is reported because nothing else on the box
  # notices. projects-orchestrator's pytest suite set this on the operator's real
  # checkout on 2026-09-06; `git status` there read clean throughout. RISK, not
  # KEEP: it is the operator's to fix, so it has to count on the statusline.
  for d in $(repos); do
    [ -d "$d/.git" ] || continue
    if [ "$(git -C "$d" config --get core.bare 2>/dev/null || true)" = "true" ]; then
      row RISK bare-checkout 0 "$(rname "$d") has core.bare=true" \
        "DAMAGE, not residue — a working checkout marked bare" \
        "git -C $d config --unset core.bare"
    fi
  done
  return 0
}

# ── G · documents outside the deliverable tree ──────────────────────────────
# Every visible file sitting directly in $HOME or on the Desktop, not only the
# four document extensions this began with: measured 2026-09-22, the loose set
# included a 600 KB `.js` capture the extension list walked past. DECIDE, not
# KEEP — each one wants a person to move it, so each one counts.
c_loose_deliverables() {
  selected loose-deliverables || return 0
  for f in "$HOME_DIR"/* "$HOME_DIR"/Desktop/*; do
    [ -f "$f" ] || continue
    case "${f##*/}" in '~$'*) continue ;; esac   # Office locks: old-downloads
    row DECIDE loose-deliverables "$(fsize "$f")" "${f#$HOME_DIR/}" \
      "MOVE, never delete — it belongs in ~/Deliverables/<date>-<slug>/ with a MANIFEST.md row" \
      "mv '$f' ~/Deliverables/<date>-<slug>/"
  done
  return 0
}

# THE FOLDERS macOS GUARDS ARE NEVER ENTERED (harbor#658). A process with no
# privacy grant does not reliably get EPERM in ~/Music and its siblings: measured
# 2026-09-24, this walk sat 4h17m at 0% CPU behind a consent prompt, along with
# every other reader of that folder. The .DS_Store files inside them are left for
# Finder — they cost bytes, and a sweep that hangs costs the whole fleet-snapshot
# job. NOT `find -delete`: it implies -depth, and -depth makes -prune a no-op, so
# the delete would walk straight back into the folders this list exists to avoid.
ds_store_list() {
  find "$HOME_DIR" -maxdepth 3 \( -path "$HOME_DIR/Library" -o -path "$HOME_DIR/Music" \
    -o -path "$HOME_DIR/Pictures" -o -path "$HOME_DIR/Movies" -o -path "$HOME_DIR/Desktop" \
    -o -path "$HOME_DIR/Documents" -o -path "$HOME_DIR/Downloads" -o -path "$HOME_DIR/.Trash" \) \
    -prune -o -name '.DS_Store' -type f -print 2>/dev/null || true
}

c_ds_store() {
  selected ds-store || return 0
  b=0; n=0
  _dsl="$(ds_store_list)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    n=$((n+1)); b=$((b + $(fsize "$f")))
  done <<DSEOF
$_dsl
DSEOF
  if [ "$n" -gt 0 ]; then
    row RECLAIM ds-store "$b" "$n .DS_Store file(s) within 3 levels of $HOME_DIR" \
      "Finder rewrites them on demand"
    if [ "$APPLY" -eq 1 ]; then
      while IFS= read -r f; do
        [ -n "$f" ] && rm -f "$f" 2>/dev/null || :
      done <<DSEOF
$_dsl
DSEOF
    fi
  fi
  return 0
}

c_loose_backups() {
  selected loose-backups || return 0
  # CONSOLIDATE, never delete. 132 KB of loose settings backups included the only
  # copy of a July state; the store is ~/.claude/backups and that is where they go.
  for f in "$CFG"/settings.json.bak* "$CFG"/CLAUDE.md.bak*; do
    [ -f "$f" ] || continue
    row DECIDE loose-backups "$(fsize "$f")" "${f#$HOME_DIR/}" \
      "MOVE into $CFG/backups/ — a deleted backup is a deleted recovery path" \
      "mv '$f' '$CFG/backups/'"
  done
  return 0
}

# ── H · live sessions: whose tree is this, and whose scratch ────────────────
# The session registry (<config>/sessions/<pid>.json) names every running
# session's id and cwd; a record whose pid is dead is not a session. The
# statusline's peer records (.helm-peers/*) add the trees sessions have WRITTEN
# in, which the registry's launch cwd does not show.
TAB="$(printf '\t')"
live_sessions() {
  [ -f "$TMPD/live" ] && return 0
  : > "$TMPD/live"
  for __j in "$CFG"/sessions/*.json; do
    [ -f "$__j" ] || continue
    __l="$(jq -r '[((.pid // 0) | tostring), (.sessionId // "-"), (.cwd // "-")] | @tsv' "$__j" 2>/dev/null || true)"
    __pid="${__l%%"$TAB"*}"
    case "$__pid" in ''|*[!0-9]*|0) continue ;; esac
    kill -0 "$__pid" 2>/dev/null || continue
    printf '%s\n' "${__l#*"$TAB"}" >> "$TMPD/live"
  done
  for __p in "$CFG"/.helm-peers/*; do
    [ -f "$__p" ] || continue
    __t="$(sed -n 's/^tree=//p' "$__p" | head -n 1)"; __pid="$(sed -n 's/^pid=//p' "$__p" | head -n 1)"
    case "$__pid" in ''|*[!0-9]*) continue ;; esac
    if [ -n "$__t" ] && kill -0 "$__pid" 2>/dev/null; then printf -- '-\t%s\n' "$__t" >> "$TMPD/live"; fi
  done
  return 0
}
live_in()  { live_sessions; awk -F'\t' -v w="$1" '$2 == w || index($2, w "/") == 1 {f = 1} END {exit !f}' "$TMPD/live"; }
live_sid() { live_sessions; awk -F'\t' -v s="$1" '$1 == s {f = 1} END {exit !f}' "$TMPD/live"; }

# <link> → the physical path it finally names, through chains, relative hops and /private (harbor#922).
link_phys() {
  __p="$1"; __i=0
  while [ -L "$__p" ] && [ "$__i" -lt 16 ]; do
    __p="$(_phys "${__p%/*}")/${__p##*/}"
    __t="$(readlink "$__p" 2>/dev/null)" || return 1
    case "$__t" in /*) __p="$__t" ;; *) __p="${__p%/*}/$__t" ;; esac
    __i=$((__i + 1))
  done
  if [ -d "$__p" ]; then _phys "$__p"; else printf '%s/%s' "$(_phys "${__p%/*}")" "${__p##*/}"; fi
}

# The install root is roots.tsv's HARBOR_LOCAL_BIN (ROOT1 checks this default), based at the scanned home.
# A worktree one of its symlinks resolves into is an installed runtime, not finished work (harbor#922).
install_links() {
  [ -f "$TMPD/installs" ] && return 0
  __ib="$(HOME="$HOME_DIR"; printf '%s' "${HARBOR_LOCAL_BIN:-$HOME/.local/bin}")"
  find "$__ib" -maxdepth 1 -type l 2>/dev/null | sort | while IFS= read -r __l; do
    if __t="$(link_phys "$__l")"; then printf '%s\t%s\n' "$__t" "${__l#"$HOME_DIR"/}"; fi
  done > "$TMPD/installs"
  return 0
}
install_link() { install_links; awk -F'\t' -v w="$(_phys "$1")" '$1 == w || index($1, w "/") == 1 {print $2; f = 1; exit} END {exit !f}' "$TMPD/installs"; }

days() {
  case "${1:-}" in ''|*[!0-9]*) printf '0'; return 0 ;; esac
  printf '%s' $(( (NOW - $1) / 86400 ))
}

# `sh bin/harbor-clean.sh old-scratch` — one class and nothing else — lists every
# member of an aggregated class. A full run keeps each to one row, because thirty
# dead scratch dirs are one decision, not thirty.
detail() { [ "$WANT" = " $1" ]; }

# ── I · the GitHub layer: one bounded read per repo, every class joins it ───
# owner/name from origin, or nothing. A repo with no GitHub remote has no PRs to
# join against — a fact about the repo, not a failed read, so it is not unread.
slug_of() {
  _u="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  case "$_u" in
    https://github.com/*)   _u="${_u#https://github.com/}" ;;
    git@github.com:*)       _u="${_u#git@github.com:}" ;;
    ssh://git@github.com/*) _u="${_u#ssh://git@github.com/}" ;;
    *) return 1 ;;
  esac
  _u="${_u%.git}"; _u="${_u%/}"
  case "$_u" in ?*/?*) printf '%s' "$_u" ;; *) return 1 ;; esac
}

# The tree under <pid>, each generation stopped before its children are listed, then killed. A TERM
# to the top process alone left a wrapper's children running (harbor#768).
_kill_tree() {
  _kt_all=" $1 "; _kt_new="$1"
  while [ -n "$_kt_new" ]; do
    kill -STOP $_kt_new 2>/dev/null || :
    _kt_new=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v all="$_kt_all" \
      'index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }')
    _kt_all="$_kt_all$_kt_new"
  done
  kill -9 $_kt_all 2>/dev/null || :
}

# A call that hangs must not hold the fleet refresher this rides. POSIX has no
# timeout(1), and neither does this box. The watchdog kills its own sleep when it
# is stopped, so a finished call leaves nothing behind.
bounded() {
  _t="${HARBOR_CLEAN_BOUND:-$1}"; shift
  "$@" & _bp=$!
  ( trap 'kill "$_bs" 2>/dev/null; exit 0' TERM
    sleep "$_t" & _bs=$!; wait "$_bs"; _kill_tree "$_bp" ) & _bw=$!
  _brc=0; wait "$_bp" || _brc=$?
  kill "$_bw" 2>/dev/null || true; wait "$_bw" 2>/dev/null || true
  _bp=""; _bw=""
  return "$_brc"
}

# A list that FILLED its limit is a list that was cut off — the `cu find` lesson.
# Overridable only so the suite can prove the cut is caught without 2,000 PRs.
PR_LIMIT="${HARBOR_CLEAN_PR_LIMIT:-2000}"
GHQ='query($owner:String!,$name:String!,$endCursor:String){repository(owner:$owner,name:$name){issues(states:OPEN,first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{number updatedAt body subIssuesSummary{total completed} closedByPullRequestsReferences(first:10,includeClosedPrs:true){nodes{state}}}}}}'

# gh_try <out> <cmd…> — bounded, retried up to 3 times on a 5xx or gateway timeout, never on a 4xx.
# gh's stderr is kept only to classify the failure. HARBOR_CLEAN_RETRY_WAIT is the backoff seed (suite sets 0).
gh_try() {
  _go="$1"; shift; _gn=0
  while :; do
    bounded "$GHT" "$@" > "$_go" 2> "$_go.err" && { rm -f "$_go.err"; return 0; }
    _gn=$((_gn + 1))
    grep -Eqi 'HTTP 5[0-9][0-9]|Gateway Time-?out|Bad Gateway|Service Unavailable' "$_go.err" 2>/dev/null || return 1
    [ "$_gn" -lt 3 ] || return 1
    sleep $((_gn * ${HARBOR_CLEAN_RETRY_WAIT:-2}))
  done
}

# gh_load <slug> <dir> — 0 only when EVERY read came back whole. Raw JSON from gh
# and every projection here in jq, so the suite's stub serves recorded JSON and
# the projections are what it tests.
gh_load() {
  _s="$1"; _g="$2"; mkdir -p "$_g"
  [ "$GH" = none ] && return 1
  command -v "$GH" >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  GHT=90 gh_try "$_g/repo.json" "$GH" repo view "$_s" --json defaultBranchRef || return 1
  jq -r '.defaultBranchRef.name // empty' "$_g/repo.json" > "$_g/default" 2>/dev/null || return 1
  [ -s "$_g/default" ] || return 1
  GHT=90 gh_try "$_g/branches.json" "$GH" api "repos/$_s/branches?per_page=100" --paginate || return 1
  jq -r '.[] | [.name, .commit.sha] | @tsv' "$_g/branches.json" > "$_g/branches.tsv" 2>/dev/null || return 1
  GHT=120 gh_try "$_g/prs.json" "$GH" pr list -R "$_s" --state all --limit "$PR_LIMIT" \
    --json number,state,headRefName,headRefOid,updatedAt || return 1
  jq -r '.[] | [.headRefName, .state, (.number | tostring), .headRefOid, (.updatedAt | fromdateiso8601 | tostring)] | @tsv' \
    "$_g/prs.json" > "$_g/prs.tsv" 2>/dev/null || return 1
  [ "$(wc -l < "$_g/prs.tsv")" -lt "$PR_LIMIT" ] || return 1
  GHT=90 gh_try "$_g/open.json" "$GH" pr list -R "$_s" --state open --limit 200 \
    --json number,headRefName,updatedAt,isDraft,mergeable,statusCheckRollup || return 1
  jq -r '.[] | [(.number | tostring), .headRefName, (.updatedAt | fromdateiso8601 | tostring),
      (if .isDraft then "draft" else "ready" end), (.mergeable // "UNKNOWN"),
      ([.statusCheckRollup[]? | (.conclusion // .state // "")] as $c
       | if ($c | length) == 0 then "none"
         elif any($c[]; . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE") then "red"
         elif all($c[]; . == "SUCCESS" or . == "SKIPPED" or . == "NEUTRAL") then "green"
         else "pending" end)] | @tsv' "$_g/open.json" > "$_g/open.tsv" 2>/dev/null || return 1
  GHT=120 gh_try "$_g/issues.json" "$GH" api graphql --paginate -f owner="${_s%%/*}" -f name="${_s#*/}" -f query="$GHQ" || return 1
  jq -r '.data.repository.issues.nodes[] | [(.number | tostring), (.updatedAt | fromdateiso8601 | tostring),
      ([(.body // "") | scan("(?m)^[ \t]*[-*] \\[ \\]")] | length | tostring),
      ([(.body // "") | scan("(?m)^[ \t]*[-*] \\[[xX]\\]")] | length | tostring),
      ((.subIssuesSummary.total // 0) | tostring), ((.subIssuesSummary.completed // 0) | tostring),
      ([.closedByPullRequestsReferences.nodes[]? | select(.state == "MERGED")] | length | tostring)] | @tsv' \
    "$_g/issues.json" > "$_g/issues.tsv" 2>/dev/null || return 1
  return 0
}

# The newest PR whose head is <branch>: "STATE NUMBER OID", or nothing. gh lists
# newest first, so a branch name reused for a later PR answers with the later one.
pr_of() { awk -F'\t' -v b="$1" '$1 == b {print $2, $3, $4; exit}' "$G/prs.tsv"; }

# contained <repo> <tip> <oid>: 0 when every commit on <tip> is in <oid>, 1 when
# <tip> has commits <oid> lacks, 2 when <oid> is not in this clone and nobody can
# tell. "The PR merged" proves nothing about commits made after it did.
contained() {
  [ "$2" = "$3" ] && return 0
  git -C "$1" cat-file -e "$3^{commit}" 2>/dev/null || return 2
  git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null && return 0
  return 1
}

# on_remote <repo> <sha> <branch>: some remote-tracking ref contains <sha>, or
# GitHub's <branch> sits at exactly it. RISK means "the only copy", so every rule
# that says RISK about commits asks this first. The first live sweep did not, and
# kept four branches at RISK after they had been pushed (2026-09-22).
on_remote() {
  [ -n "$(git -C "$1" for-each-ref --contains "$2" --count=1 --format=x refs/remotes 2>/dev/null)" ] && return 0
  inlist "$3$TAB$2" "$G/branches.tsv"
}

# Worktrees other than the main checkout, whose PR is merged or closed, or which
# have had no PR and no commit for IDLE days. Uncommitted changes, or commits made
# after the PR that no remote holds, make it RISK: that is work in one place only.
gh_worktrees() {
  selected finished-worktrees || return 0
  _r="$1"
  git -C "$_r" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { if (p != "") print p "\t" h "\t" b "\t" f; p = substr($0, 10); h = ""; b = "-"; f = ""; next }
    /^HEAD /     { h = $2; next }
    /^branch /   { b = $2; sub("^refs/heads/", "", b); next }
    /^prunable/  { f = f "prunable,"; next }
    /^locked/    { f = f "locked,"; next }
    /^bare/      { f = f "bare,"; next }
    END          { if (p != "") print p "\t" h "\t" b "\t" f }' | sed 1d > "$G/wt"
  while IFS="$TAB" read -r _w _h _b _f; do
    case "$_f" in *prunable*|*locked*|*bare*) continue ;; esac
    [ -d "$_w" ] || continue
    _sub="${_w#$HOME_DIR/}"
    _dirty=0
    [ -n "$(git -C "$_w" status --porcelain 2>/dev/null | head -n 1)" ] && _dirty=1
    _age="$(days "$(git -C "$_w" log -1 --format=%ct 2>/dev/null || true)")"
    _rm="git -C $_r worktree remove $_w"
    [ "$_b" = "-" ] || _rm="$_rm && git -C $_r branch -D $_b"
    _pr=""
    [ "$_b" = "-" ] || _pr="$(pr_of "$_b")"
    # harbor#922: a finished-looking worktree an install root links into is KEEP, whatever else holds.
    if [ "${_pr%% *}" != OPEN ] && { [ -n "$_pr" ] || [ "$_age" -ge "$IDLE" ]; } && _lnk="$(install_link "$_w")"; then
      row KEEP finished-worktrees 0 "$_sub" "install target: $_lnk resolves into it"; continue
    fi
    if [ -n "$_pr" ]; then
      set -- $_pr
      case "$1" in OPEN) continue ;; MERGED) _did=merged ;; *) _did="closed without merging" ;; esac
      _n="$2"; _rc=0; contained "$_r" "$_h" "$3" || _rc=$?
      if [ "$_rc" -eq 1 ] && ! on_remote "$_r" "$_h" "$_b"; then
        row RISK finished-worktrees 0 "$_sub" "commits made after PR #$_n was $_did — on no remote and in no PR" "git -C $_w log $3..HEAD"
      elif [ "$_rc" -eq 1 ]; then
        row DECIDE finished-worktrees 0 "$_sub" "commits made after PR #$_n was $_did are pushed but in no PR — open one, or let them go" "git -C $_w log $3..HEAD"
      elif [ "$_dirty" -eq 1 ]; then
        row RISK finished-worktrees 0 "$_sub" "uncommitted changes in a worktree whose PR #$_n was $_did" "git -C $_w status"
      elif live_in "$_w"; then
        row KEEP finished-worktrees 0 "$_sub" "PR #$_n was $_did, but a live session is working in it"
      elif [ "$_rc" -eq 2 ]; then
        row DECIDE finished-worktrees 0 "$_sub" "PR #$_n was $_did; its head is not in this clone, so containment is unproven" "$_rm"
      else
        row DECIDE finished-worktrees 0 "$_sub" "PR #$_n was $_did and carried every commit on it" "$_rm"
      fi
    elif [ "$_age" -ge "$IDLE" ]; then
      if [ "$_dirty" -eq 1 ]; then
        row RISK finished-worktrees 0 "$_sub" "no PR, no commit for ${_age}d, and uncommitted changes" "git -C $_w status"
      elif live_in "$_w"; then
        row KEEP finished-worktrees 0 "$_sub" "no PR for ${_age}d, but a live session is working in it"
      else
        row DECIDE finished-worktrees 0 "$_sub" "no PR and no commit for ${_age}d" "$_rm"
      fi
    fi
  done < "$G/wt"
  return 0
}

# Local branches no worktree holds and landed-branches did not already claim. A
# squash-merged branch lands here: its tree is not main's, and the PR is the only
# evidence it is finished. DECIDE, never RECLAIM — deleting a branch whose tree is
# not main's is exactly the delete the header says --apply never makes.
gh_branches() {
  selected pr-branches || return 0
  _r="$1"
  git -C "$_r" for-each-ref --format='%(refname:short)%09%(objectname)%09%(committerdate:unix)' refs/heads \
    > "$G/heads" 2>/dev/null || return 0
  while IFS="$TAB" read -r _b _h _ct; do
    [ "$_b" = "$DEF" ] && continue
    inlist "$_b" "$G/co" && continue
    inlist "$_r$TAB$_b" "$TMPD/landed" && continue
    _sub="$(rname "$_r") $_b"
    _age="$(days "$_ct")"
    _del="git -C $_r branch -D $_b"
    _pr="$(pr_of "$_b")"
    if [ -n "$_pr" ]; then
      set -- $_pr
      case "$1" in OPEN) continue ;; MERGED) _did=merged ;; *) _did="closed without merging" ;; esac
      _n="$2"; _rc=0; contained "$_r" "$_h" "$3" || _rc=$?
      case "$_rc" in
        0) row DECIDE pr-branches 0 "$_sub" "PR #$_n was $_did and carried every commit on it" "$_del" ;;
        1) if on_remote "$_r" "$_h" "$_b"; then
             row DECIDE pr-branches 0 "$_sub" "commits made after PR #$_n was $_did are pushed but in no PR — open one, or let them go" "git -C $_r log $3..$_b"
           else
             row RISK pr-branches 0 "$_sub" "commits made after PR #$_n was $_did — on no remote and in no PR" "git -C $_r log $3..$_b"
           fi ;;
        *) row DECIDE pr-branches 0 "$_sub" "PR #$_n was $_did; its head is not in this clone, so containment is unproven" "$_del" ;;
      esac
    else
      _on=0
      on_remote "$_r" "$_h" "$_b" && _on=1
      if [ "$_on" -eq 0 ] && [ "$_age" -ge "$IDLE" ]; then
        row RISK pr-branches 0 "$_sub" "on no remote and in no PR for ${_age}d — this clone holds the only copy" "git -C $_r push -u origin $_b"
      elif [ "$_on" -eq 1 ] && [ "$_age" -ge $((IDLE * 2)) ]; then
        row DECIDE pr-branches 0 "$_sub" "pushed, but no PR and no commit for ${_age}d" "$_del"
      fi
    fi
  done < "$G/heads"
  return 0
}

# Branches left on GitHub after their PR was merged or closed. A branch with NO
# PR is not counted: the branch list carries no date, and an undated row would be
# a guess about whether anyone is still working on it.
gh_remote() {
  selected remote-branches || return 0
  _r="$1"; _s="$2"
  while IFS="$TAB" read -r _b _h; do
    [ "$_b" = "$DEF" ] && continue
    _pr="$(pr_of "$_b")"
    [ -n "$_pr" ] || continue
    set -- $_pr
    case "$1" in OPEN) continue ;; MERGED) _did=merged ;; *) _did="closed without merging" ;; esac
    if [ "$_h" = "$3" ]; then
      row DECIDE remote-branches 0 "$_s $_b" "PR #$2 was $_did, and the branch still sits at its head on GitHub" \
        "git -C $_r push origin --delete $_b"
    else
      row DECIDE remote-branches 0 "$_s $_b" "PR #$2 was $_did, but the branch moved after it — look before deleting" \
        "git -C $_r fetch origin $_b && git -C $_r log $3..FETCH_HEAD"
    fi
  done < "$G/branches.tsv"
  return 0
}

# The main checkout: its default branch behind (or ahead of) GitHub's, or the
# checkout parked on a branch whose PR is finished. Pulling moves files under any
# session working there, so even the plain fast-forward is DECIDE.
gh_checkout() {
  selected stale-checkouts || return 0
  _r="$1"
  _cur="$(git -C "$_r" branch --show-current 2>/dev/null || true)"
  _dirty=0
  [ -n "$(git -C "$_r" status --porcelain -uno 2>/dev/null | head -n 1)" ] && _dirty=1
  _loc="$(git -C "$_r" rev-parse -q --verify "refs/heads/$DEF" 2>/dev/null || true)"
  _hub="$(awk -F'\t' -v b="$DEF" '$1 == b {print $2; exit}' "$G/branches.tsv")"
  if [ -n "$_loc" ] && [ -n "$_hub" ] && [ "$_loc" != "$_hub" ]; then
    if [ "$_cur" = "$DEF" ]; then _up="git -C $_r pull --ff-only"; else _up="git -C $_r fetch origin $DEF:$DEF"; fi
    if ! git -C "$_r" cat-file -e "$_hub^{commit}" 2>/dev/null; then
      row DECIDE stale-checkouts 0 "$(rname "$_r") $DEF" "GitHub's $DEF has commits this clone has not fetched" "$_up"
    elif git -C "$_r" merge-base --is-ancestor "$_loc" "$_hub" 2>/dev/null; then
      row DECIDE stale-checkouts 0 "$(rname "$_r") $DEF" \
        "$(git -C "$_r" rev-list --count "$_loc..$_hub" 2>/dev/null) commit(s) behind GitHub" "$_up"
    else
      row RISK stale-checkouts 0 "$(rname "$_r") $DEF" "local $DEF carries commits GitHub's does not" \
        "git -C $_r log $_hub..$DEF"
    fi
  fi
  if [ -n "$_cur" ] && [ "$_cur" != "$DEF" ]; then
    _pr="$(pr_of "$_cur")"
    if [ -n "$_pr" ]; then
      set -- $_pr
      if [ "$1" != OPEN ]; then
        if [ "$_dirty" -eq 1 ]; then
          row RISK stale-checkouts 0 "$(rname "$_r") on $_cur" \
            "the main checkout sits on a finished branch (PR #$2) with uncommitted changes" "git -C $_r status"
        else
          row DECIDE stale-checkouts 0 "$(rname "$_r") on $_cur" \
            "the main checkout sits on a finished branch (PR #$2)" "git -C $_r switch $DEF"
        fi
      fi
    fi
  fi
  return 0
}

# Open PRs that are waiting on a person: green and mergeable for a day, red for
# two, or silent for twice IDLE. Harbor's own merge goes through its gate.
gh_prs() {
  selected waiting-prs || return 0
  _r="$1"; _s="$2"
  if [ -f "$_r/bin/merge-check.sh" ]; then _mc="(cd $_r && sh bin/merge-check.sh --merge %s --squash --delete-branch)"
  else _mc="gh pr merge %s -R $_s"; fi
  while IFS="$TAB" read -r _n _b _up _dr _mg _ci; do
    _age="$(days "$_up")"
    if [ "$_dr" = ready ] && [ "$_ci" = green ] && [ "$_mg" = MERGEABLE ] && [ "$_age" -ge 1 ]; then
      # shellcheck disable=SC2059 # the format is this file's own, holding one %s
      row DECIDE waiting-prs 0 "$_s #$_n" "green and mergeable, waiting on you for ${_age}d" "$(printf "$_mc" "$_n")"
    elif [ "$_ci" = red ] && [ "$_age" -ge 2 ]; then
      row DECIDE waiting-prs 0 "$_s #$_n" "CI red, untouched for ${_age}d" "gh pr checks $_n -R $_s"
    elif [ "$_age" -ge $((IDLE * 2)) ]; then
      row DECIDE waiting-prs 0 "$_s #$_n" "no activity for ${_age}d" "gh pr view $_n -R $_s"
    fi
  done < "$G/open.tsv"
  return 0
}

# Open issues that say they are done: every done-when box ticked, every
# sub-issue closed, or a merged PR that claims to close them.
gh_issues() {
  selected closable-issues || return 0
  _s="$2"
  while IFS="$TAB" read -r _n _up _open _done _st _sd _mp; do
    _why=""
    # AN UNTICKED BOX VETOES EVERY OTHER SIGNAL. Closed sub-issues or a merged PR
    # say part of the work is done; an open done-when box is the issue saying it
    # is not. The first live sweep offered harbor#603 (5 open acceptance boxes,
    # its one child closed) and a workload repo's #1 for closing (2026-09-22).
    if [ "$_open" -gt 0 ]; then :
    elif [ "$_done" -gt 0 ]; then _why="every done-when box is ticked ($_done)"
    elif [ "$_st" -gt 0 ] && [ "$_sd" -eq "$_st" ]; then _why="all $_st sub-issues are closed"
    elif [ "$_mp" -gt 0 ]; then _why="a merged PR says it closes this"
    fi
    if [ -n "$_why" ]; then
      row DECIDE closable-issues 0 "$_s #$_n" "$_why" "gh issue close $_n -R $_s"
    fi
  done < "$G/issues.tsv"
  return 0
}

c_github() {
  _any=0
  for _c in finished-worktrees pr-branches remote-branches stale-checkouts waiting-prs closable-issues; do
    selected "$_c" && _any=1
  done
  [ "$_any" -eq 1 ] || return 0
  _i=0
  for d in $(repos); do
    s="$(slug_of "$d")" || continue
    _i=$((_i + 1)); G="$TMPD/gh.$_i"
    if ! gh_load "$s" "$G"; then
      UNREAD=$((UNREAD + 1))
      row KEEP unread 0 "$(rname "$d") ($s)" \
        "could not read GitHub — this repo's PR, branch, checkout and issue rows are MISSING from this report, not clean"
      continue
    fi
    DEF="$(cat "$G/default")"
    checked_out "$d" > "$G/co"
    gh_worktrees "$d" "$s"
    gh_branches "$d" "$s"
    gh_remote "$d" "$s"
    gh_checkout "$d" "$s"
    gh_prs "$d" "$s"
    gh_issues "$d" "$s"
  done
  return 0
}

# ── J · local-only classes: no forge needed ────────────────────────────────
# A stash exists in this clone and nowhere else.
c_old_stashes() {
  selected old-stashes || return 0
  for d in $(repos); do
    git -C "$d" stash list --format='%gd%x09%ct%x09%s' > "$TMPD/stash" 2>/dev/null || continue
    while IFS="$TAB" read -r _g _ct _m; do
      _age="$(days "$_ct")"
      [ "$_age" -ge "$IDLE" ] || continue
      row RISK old-stashes 0 "$(rname "$d") $_g" "${_age}d old, and a stash exists in this clone only: $_m" \
        "git -C $d stash show -p $_g"
    done < "$TMPD/stash"
  done
  return 0
}

# Untracked, un-ignored entries at the top of a main checkout, a day old or more.
c_stray_files() {
  selected stray-files || return 0
  for d in $(repos); do
    git -C "$d" ls-files -o --exclude-standard --directory --no-empty-directory 2>/dev/null \
      | sed 's#/.*##' | sort -u > "$TMPD/stray"
    while IFS= read -r _f; do
      [ -n "$_f" ] && [ -e "$d/$_f" ] || continue
      _age="$(days "$(mtime "$d/$_f")")"
      [ "$_age" -ge 1 ] || continue
      row DECIDE stray-files 0 "$(rname "$d") $_f" \
        "untracked in the main checkout for ${_age}d — commit it, ignore it, or move it out" \
        "git -C $d status --short -- $_f"
    done < "$TMPD/stray"
  done
  return 0
}

# Per-session scratch (<scratch>/<project>/<session-id>/) whose session is not
# running and inside which nothing changed for three days. Measured 2026-09-22:
# 23 such dirs holding 385 MiB. Scratch is per-session by definition; the session
# registry is what says the session is gone.
c_old_scratch() {
  selected old-scratch || return 0
  [ -d "$SCRATCH" ] || return 0
  _n=0; _b=0
  for _d in "$SCRATCH"/*/*/; do
    [ -d "$_d" ] || continue
    _d="${_d%/}"
    live_sid "${_d##*/}" && continue
    # -mindepth 1: what is INSIDE changed, not the directory entry itself.
    [ -n "$(find "$_d" -mindepth 1 -mtime -3 -print 2>/dev/null | head -n 1)" ] && continue
    _db="$(dirbytes "$_d")"; _db="${_db:-0}"
    if detail old-scratch; then
      row DECIDE old-scratch "$_db" "$_d" "session not running, nothing changed inside for 3 days" "rm -rf '$_d'"
    fi
    _n=$((_n + 1)); _b=$((_b + _db))
  done
  if [ "$_n" -gt 0 ] && ! detail old-scratch; then
    row DECIDE old-scratch "$_b" "$_n session scratch dir(s) under $SCRATCH" \
      "each session is not running, and nothing inside changed for 3 days" \
      "sh bin/harbor-clean.sh old-scratch   # lists each one"
  fi
  return 0
}

# ~/Downloads entries 30 days old, and Office lock files (~$name) a day old in
# the four places a document is opened from. Aggregated, like old-scratch.
c_old_downloads() {
  selected old-downloads || return 0
  _n=0; _b=0
  for _f in "$HOME_DIR"/Downloads/* "$HOME_DIR"/'~$'* "$HOME_DIR"/Desktop/'~$'* "$HOME_DIR"/Documents/'~$'*; do
    [ -e "$_f" ] || continue
    _age="$(days "$(mtime "$_f")")"
    case "${_f##*/}" in
      '~$'*) [ "$_age" -ge 1 ] || continue; _why="an Office lock file left by a closed document, ${_age}d old" ;;
      *)     [ "$_age" -ge 30 ] || continue; _why="in Downloads for ${_age}d" ;;
    esac
    _fb="$(dirbytes "$_f")"; _fb="${_fb:-0}"
    detail old-downloads && row DECIDE old-downloads "$_fb" "${_f#$HOME_DIR/}" "$_why" "rm -rf '$_f'"
    _n=$((_n + 1)); _b=$((_b + _fb))
  done
  if [ "$_n" -gt 0 ] && ! detail old-downloads; then
    row DECIDE old-downloads "$_b" "$_n old download(s) or lock file(s)" \
      "Downloads entries 30 days old, and Office lock files a day old" \
      "sh bin/harbor-clean.sh old-downloads   # lists each one"
  fi
  return 0
}

# ── report ──────────────────────────────────────────────────────────────────
if [ "$JSON" -eq 0 ]; then
  log_head "$HOME_DIR · age floor ${AGE}d"
  if [ "$APPLY" -eq 1 ]; then log_note "APPLY: acting on RECLAIM rows"
  else log_note "DRY RUN — nothing is touched. Pass --apply to act."; fi
  printf '\n'
fi

refusals
c_session_env
c_runner_diag
c_pycache
c_ds_store
c_loose_backups
c_landed_branches
c_prunable_worktrees
c_bare_checkout
c_loose_deliverables
c_github
c_old_stashes
c_stray_files
c_old_scratch
c_old_downloads

# ── the count, and when it is due ───────────────────────────────────────────
# ITEMS is what needs a PERSON: DECIDE plus RISK. RECLAIM is left out on
# purpose — .DS_Store and empty session dirs regenerate every day, so a count
# that included them would never reach zero, and a count that never reaches zero
# is wallpaper by the third session. RISK alone makes it due: a single piece of
# work that exists in one place is worth interrupting for.
ITEMS=$((N_DECIDE + N_RISK))
DUE=0
if [ "$N_RISK" -gt 0 ] || [ "$ITEMS" -ge "$DUE_AT" ]; then DUE=1; fi
SUMMARY="sweep items=$ITEMS risk=$N_RISK decide=$N_DECIDE reclaim=$N_RECLAIM bytes=$BYTES keep=$N_KEEP unread=$UNREAD due=$DUE at=$NOW"

if [ "$RECORD" -eq 1 ]; then
  exec 1>&3 3>&-
  ( umask 077; printf '%s\n' "$SUMMARY" > "$REC.tmp" ) && mv -f "$REC.tmp" "$REC"
  ( umask 077; cat "$TMPD/rows.jsonl" > "$REC.jsonl.tmp" ) && mv -f "$REC.jsonl.tmp" "$REC.jsonl"
  printf '%s  [check:sweep]\n' "$SUMMARY"
  exit 0
fi

if [ "$JSON" -eq 0 ]; then
  printf '\n'
  log_note "$N_RECLAIM reclaimable row(s), about $(human "$BYTES") · $N_DECIDE to decide · $N_RISK at risk · $N_KEEP KEPT on a stated predicate"
  if [ "$UNREAD" -gt 0 ]; then
    log_warn "$UNREAD GitHub repo(s) could not be read: their rows are MISSING, not clean."
    log_fix "gh auth status"
  fi
  log_note "The KEEP rows are the point: read them before widening anything."
  # NO GRAND TOTAL of "space on the box". A headline number invites the sweep
  # this tool exists to prevent, and the class size is not the cut size — the
  # runner-log class was 859 MB where the >14d cut returned 210 MB.
  if [ "$APPLY" -eq 0 ] && [ "$N_RECLAIM" -gt 0 ]; then
    log_note "Before --apply, bundle every ref you can still lose:"
    log_note "  git -C <repo> bundle create ~/Deliverables/\$(date +%F)-cleanup/<repo>.bundle --all"
    log_note "  git bundle verify ~/Deliverables/\$(date +%F)-cleanup/<repo>.bundle"
  fi
  log_end; exit $?
fi
exit 0
