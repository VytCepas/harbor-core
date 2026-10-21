#!/usr/bin/env sh
# memory-route.sh (GOVERNANCE) — does a session started IN a governed repo load
# the memory store, or does it start blind?
#
#   sh memory-route.sh [--dir <config-dir> | --live] [--apply] [--quiet]
#   sh memory-route.sh [--dir <config-dir> | --live] --status
#
# Exit 0 = every governed repo resolves to a non-empty store. Exit 1 = at least
# one starts blind. Exit 3 = it could not look (D-29 unchecked: nothing was
# judged), which is never a green. Exit 2 = a usage error. Until the D-49 window
# closes a reader also accepts 2 as "could not look" (the code it used to exit).
#
# `--status` is the reconcile form (CONTRACTS/reconcile.md, harbor#1031): the same
# judgement, printed as desired / observed / delta / age for each repo that starts
# blind, and nothing for the ones that do not. It reports only, so it refuses
# `--apply` (exit 2), and its exit code is the plain run's.
#
# `--apply` REFUSES TO GUESS ITS TARGET. Writing needs `--live` or an explicit
# `--dir`, because the read path defaults to the live config dir and a mutator
# that inherits a convenience default writes to the operator's real box on a
# bare `--apply`. Same shape as D2's settings.json rule, for the same reason.
#
# WHY. The auto-memory store is keyed by the session's working directory:
# ~/.claude/projects/<cwd-key>/memory/. A session started at $HOME gets the
# store; a session started in the measurement repo (resolved through the repo registry) gets a DIFFERENT key, which has no store
# behind it, so it loads nothing. Measured 2026-09-16: 291 notes under
# `-Users-someone`, and 0 under `-Users-someone-harbor`. Every other governed
# repo had no project directory at all.
#
# That is the whole defect, and it is worse than it sounds because it is silent
# and it inverts. The notes most worth having in the measurement repo (resolved through the repo registry) are the ones written
# WHILE WORKING IN the measurement repo (resolved through the repo registry) — the ugrep negative, the zsh word-split, the
# `cd ~` prompt — and every one of them was filed from a $HOME session and is
# therefore invisible in the repo it describes. `memory-store-topology.md` has
# recorded this since 2026-08-02 and nothing acted on it, because a note about a
# routing defect is itself subject to the routing defect.
#
# THE FIX IS ONE STORE WITH MANY DOORS, not a store per repo. Each governed
# repo's key gets its `memory` directory symlinked at the $HOME silo, so there
# is exactly one set of notes, one MEMORY.md index, and a note written from any
# repo is visible from all of them. A store per repo would re-create the same
# invisibility one level down and multiply the index nobody reads.
#
# WHAT IT COSTS, said plainly because `context-budget.sh` will now charge it
# everywhere: the $HOME store's index is ~40 KB, so every governed repo's
# sessions begin paying what only $HOME sessions paid before. That is the
# intended trade — an index that is loaded and slightly over budget beats an
# index that is under budget because nothing reads it — but it makes trimming
# MEMORY.md a real task rather than a tidy one.
#
# IT WRITES ONLY SYMLINKS, AND ONLY UNDER --apply. It never creates, moves,
# copies or deletes a note. A pre-existing real directory is reported and left
# alone: that is somebody's store, and silently replacing it with a link to a
# different store would lose notes.
set -u

# Its errors go through log-lib on stderr: stdout is the report, which lint IJ6 parses (harbor#896).
# shellcheck disable=SC2034 # read by log-lib.sh
LOG_FD=2; . "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)/log-lib.sh"; log_init memory-route

_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

REPO="${HARBOR_REPO:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)}"
LIVE_DIR="$HOME/.claude"
CFG="${CLAUDE_CONFIG_DIR:-$LIVE_DIR}"
APPLY=0
QUIET=0
STATUS=0
TARGETED=0
EXPLICIT_LIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --live)  CFG="$LIVE_DIR"; TARGETED=1; EXPLICIT_LIVE=1 ;;
    --dir)   shift; CFG="${1:-}"; TARGETED=1 ;;
    --apply) APPLY=1 ;;
    --quiet) QUIET=1 ;;
    --status) STATUS=1 ;;
    -h|--help)
      awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
      exit 0 ;;
    *) log_fail "unknown argument $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
  esac
  shift
done

# --status prints the reconcile records and nothing else on stdout.
[ "$STATUS" = 0 ] || QUIET=1
say() { [ "$QUIET" = 1 ] || printf '%s\n' "$1"; }
# The check tier's receipt (harbor#896, log-lib's log_receipt): every run that examined, or stood down, leaves one.
RECEIPTS="$(receipt_dir "$CFG")"
BLINDS=""
DESIRED="a session started here loads a store with notes"
blind() { BAD=$((BAD + 1)); BLINDS="$BLINDS
$name"; [ "$STATUS" = 0 ] || status_drift "$name" "$DESIRED" "${1:-no store}" "${2:--}"; }
# Could not look: the receipt says so, --status says so, and neither is a green.
stood_down() { # <reason>
  receipt stood-down
  [ "$STATUS" = 0 ] || status_unjudged "$1" || :
  exit 3
}
receipt() { _oifs=$IFS; IFS='
'; set -f; log_receipt "$RECEIPTS" memory-route "$1" $BLINDS || { log_warn "no receipt written to $RECEIPTS"; log_end || :; }
  set +f; IFS=$_oifs; }

# THE WRITE NEEDS AN EXPLICIT --live FOR THE LIVE DIR (lint D2). Reading
# defaults to the live config dir because that is the question anyone asking
# has; writing must not inherit that convenience, or `--apply` typed while
# thinking about a sandbox lands on the operator's real store.
#
# RESOLVED PATHS, NOT STRINGS, and that is not ceremony: `--dir ~/.claude/`
# with a trailing slash, or any symlinked route to the same directory, is the
# live dir by another spelling and a string compare waves it through. D2's own
# header records a pass that stripped every hook from a live config exactly that
# way. The comparison is of physical paths, so only `--live` opens the live dir.
if [ "$APPLY" = 1 ] && [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ] && [ "$EXPLICIT_LIVE" = 0 ]; then
  log_fail "refusing to write $LIVE_DIR without an explicit --live"; log_fix "sh $0 --live --apply"; log_end || :
  exit 2
fi
if [ "$STATUS" = 1 ] && [ "$APPLY" = 1 ]; then
  # not a run (CONTRACTS/logging.md): said on stderr, no summary line
  log_fail "--status only reports, and --apply writes"; log_fix "run one: sh $0 --live --status (report) or sh $0 --live --apply (route)"
  exit 2
fi
# A target that is NOT the live dir still has to be named, so a bare --apply
# with no target at all cannot fall through this gate on a box where
# CLAUDE_CONFIG_DIR happens to point elsewhere.
if [ "$APPLY" = 1 ] && [ "$TARGETED" = 0 ]; then
  log_fail "--apply needs a target — pass --live, or --dir <config-dir>"; log_fix "sh $0 --live --apply"; log_end || :
  exit 2
fi

# ── the key derivation, which is the one thing here that can be wrong ────────
# Claude Code names a project directory after the session's cwd with every `/`
# replaced by `-`, leading slash included: /Users/x/azimuth -> -Users-x-azimuth.
# Derived, never parsed back: two different paths can in principle collide once
# a directory name contains a dash, and this only ever needs the forward map.
key_for() { printf '%s' "$1" | sed 's|/|-|g'; }

# THE REGISTRY IS THE PRIVATE LAYER'S (harbor#1149): <private>/inject.d/box/projects.tsv, through the one resolver beside this
# script. None is the stand-down below, which names where it looked.
_SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
REGISTRY="$(env -u HARBOR_ROOT sh "$_SELF/roots.sh" --projects 2>/dev/null || :)"
[ -n "$REGISTRY" ] || REGISTRY="$(env -u HARBOR_ROOT sh "$_SELF/roots.sh" --private 2>/dev/null || :)/inject.d/box/projects.tsv"
STORE_ROOT="$CFG/projects"
# PHYSICAL, on both sides of the comparison. Claude Code keys the directory off
# the resolved path, which this box's own store proves: the scratchpad silos are
# named `-private-tmp-claude-501-...` and not `-tmp-...`, because /tmp is a
# symlink to /private/tmp. Taking $HOME raw while resolving the repo paths works
# only for as long as no path above either one is a link — true for
# this box's $HOME today and false the moment this runs anywhere else.
[ "$STATUS" = 0 ] || status_init memory-route "$CFG" || exit 3
HOME_KEY="$(key_for "$(_phys "$HOME")")"
HOME_STORE="$STORE_ROOT/$HOME_KEY/memory"

# ── stand down loudly, never quietly green ──────────────────────────────────
# renew-check.sh's case 4 is the precedent: "nothing to compare against" and
# "nothing wrong" must not render the same. A green here would certify routing
# that was never examined.
if [ ! -f "$REGISTRY" ]; then
  say "[check:memory-route] STOOD DOWN — no registry at $REGISTRY, so the governed repos are unknown."
  say "  This is not a pass. Nothing was examined."
  stood_down "no registry at ${REGISTRY#"$REPO"/}, so the governed repos are unknown"
fi
if [ ! -d "$HOME_STORE" ]; then
  say "[check:memory-route] STOOD DOWN — no store at $HOME_STORE to route to."
  say "  This is not a pass. Nothing was examined."
  stood_down "no store at projects/$HOME_KEY/memory to route to"
fi

# A store that exists and holds nothing is the same blindness as no store, so
# the count is the subject, not the directory's existence.
#
# RESOLVE FIRST, THEN WALK. `find -P <symlink>` does not descend — it reports on
# the link itself — so counting a correctly routed repo returned 0 and this tool
# called its own successful --apply a failure. Resolving to the real directory
# keeps -P's guarantee (nothing below is ever followed) while letting the one
# link that matters be followed exactly once. A dangling link resolves to
# itself, finds nothing, and is reported BLIND, which is right.
count_notes() {
  _d="$(_phys "$1")"
  find -P "$_d" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c .
}

HOME_N="$(count_notes "$HOME_STORE")"
if [ "$HOME_N" -eq 0 ]; then
  say "[check:memory-route] STOOD DOWN — the store at $HOME_STORE is empty."
  say "  This is not a pass. Routing a repo at an empty store buys nothing."
  stood_down "the store at projects/$HOME_KEY/memory is empty, so routing a repo at it buys nothing"
fi

say "[check:memory-route] $CFG"
say "  store: $HOME_STORE ($HOME_N notes)"

BAD=0; OK=0; MADE=0; EXAMINED=0

# ── every place a session can actually START ────────────────────────────────
# A REGISTRY ROW IS NOT A DIRECTORY, IT IS A TREE. The first version routed the
# ten registry paths and called the job done; measured immediately afterwards,
# eight more directories a session can legitimately open were still blind —
# three harbor worktrees (INCLUDING THE ONE THIS TOOL WAS BEING WRITTEN IN),
# the pipeline repo's sub-checkouts (resolved through the repo registry), a project-init worktree, and mailcal's
# installed copy under ~/.local/lib.
#
# Two shapes, both ordinary on this box:
#   worktrees   `worktree.sh` creates one per branch, so they are the NORMAL way
#               work happens here. Each gets its own cwd key and its own
#               blindness.
#   sub-repos   the pipeline repo (resolved through the repo registry) is a ROOT and not a repo — its sub-checkouts are several
#               separate checkouts one level below it. A session runs in those,
#               never in the root, so routing only the root routes nobody.
#
# Discovered, never listed: a hardcoded set of worktrees is stale the next time
# anyone branches, which is exactly the copy-drift "derive it, don't state it"
# exists for.
route_targets() { # <repo-or-root path> -> one absolute path per line
  printf '%s\n' "$1"
  # `worktree list` prints the main checkout first; every later line is an extra
  # tree. Silent when the path is not a git repo, which is how a root like
  # the pipeline repo (resolved through the repo registry) falls through to the sub-repo branch below.
  git -C "$1" worktree list 2>/dev/null | awk 'NR>1 {print $1}'
  # Immediate children that are themselves checkouts. One level only: deeper is
  # vendored dependencies, not somewhere anyone opens a session.
  #
  # `-e`, NOT `-d`, AND THAT IS THE WHOLE CASE. A normal clone has `.git` as a
  # DIRECTORY; a git worktree has `.git` as a FILE containing a gitdir pointer.
  # Testing for a directory therefore found the pipeline repo's checkout (resolved through the repo registry) and silently missed all
  # five of its `<sub>-wt-*` worktrees — the branch checkouts, which
  # is where the work in that tree actually happens. Measured 2026-09-16: the
  # first --apply reported a confident "18 of 18 routed" with those five still
  # blind, which is why the suite now pins both spellings.
  for _c in "$1"/*/; do
    [ -e "$_c.git" ] || continue
    printf '%s\n' "${_c%/}"
  done
}

# THE TARGET LIST IS BUILT FIRST, THEN WALKED ONCE — deliberately, and not for
# tidiness. `route_targets ... | while read` puts the loop in a PIPELINE, and a
# pipeline runs its stages in subshells, so every BAD/OK/MADE increment would be
# discarded at the closing `done` and this tool would report 0 of 0 whatever it
# found. That is a silent wrong-green, which is the one outcome the whole file
# is built to prevent.
TARGETS="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")" || { log_fail "cannot create a temp file"; log_fix "df -h \"\${TMPDIR:-/tmp}\""; log_end || :
  [ "$STATUS" = 0 ] || status_unjudged "cannot create a temp file" || :; exit 3; }
trap 'rm -f "$TARGETS"' EXIT INT TERM

while IFS="$(printf '\t')" read -r name path _rest; do
  case "$name" in ''|\#*) continue ;; esac
  [ -n "${path:-}" ] || continue
  abs="$(printf '%s' "$path" | sed "s|^~|$HOME|")"
  # A ROW WHOSE DIRECTORY IS GONE IS SKIPPED, matching project-pointer.sh's own
  # rule. Lint IJ5 is what catches a stale row; duplicating that judgement here
  # would make this check fail for a reason it does not own.
  [ -d "$abs" ] || continue
  route_targets "$abs" | while IFS= read -r tgt; do
    [ -d "$tgt" ] || continue
    # The label names the row for the row itself, and row/dir for anything
    # discovered under it, so a BLIND line says which tree it means without
    # printing an absolute home (CONSTITUTION §3).
    if [ "$(_phys "$tgt")" = "$(_phys "$abs")" ]; then _l="$name"
    else _l="$name/$(basename "$tgt")"; fi
    printf '%s\t%s\n' "$_l" "$(_phys "$tgt")"
  done
done < "$REGISTRY" | sort -u -t"$(printf '\t')" -k2,2 > "$TARGETS"

# THE WORKSPACE ROOT IS A DOOR TOO (harbor#619). The repos live under
# ${PORT_ROOT:-$HOME/port} and that is where sessions are launched from, but it
# is not a repo, so no registry row names it and nothing above routes it.
# Measured 2026-09-23 after the move: its store was an EMPTY directory the
# harness had made on the first session there, so every session started in
# ~/port loaded no memory, and this check was green throughout. Same rule as
# floor_port_root (CONTRACTS/port-root.md): empty is unset. A root that does not
# exist is skipped, as a registry row's missing directory is.
_pr="${PORT_ROOT:-$HOME/port}"
if [ -d "$_pr" ]; then
  _pr="$(_phys "$_pr")"
  # The WHOLE field, never a prefix: every repo lives under this root, so a
  # substring test finds the root "already listed" on every real box.
  awk -F'\t' -v p="$_pr" '$2 == p { f = 1 } END { exit !f }' "$TARGETS" ||
    printf 'port-root\t%s\n' "$_pr" >> "$TARGETS"
fi

# WORKTREES UNDER <PORT_ROOT>/.worktrees/<repo>/<slug> ARE DOORS TOO (harbor#1149). A registry row finds its
# own trees through `git worktree list`, but projects.tsv is not repos.tsv: a repo registered only in the
# private layer has no row here, so a tree of it would start blind. Read off the directory, as the port root
# is. `.git` is a FILE in a linked worktree. The WHOLE path is compared, never a prefix.
_wd="${PORT_ROOT:-$HOME/port}/.worktrees"
if [ -d "$_wd" ]; then
  for _w in "$_wd"/*/*/; do
    [ -f "${_w}.git" ] || continue
    _wp="$(_phys "${_w%/}")"
    awk -F'\t' -v p="$_wp" '$2 == p { f = 1 } END { exit !f }' "$TARGETS" ||
      printf 'worktrees/%s\t%s\n' "$(basename -- "$(dirname -- "$_wp")")/$(basename -- "$_wp")" "$_wp" >> "$TARGETS"
  done
fi

while IFS="$(printf '\t')" read -r name target; do
  [ -n "$target" ] || continue
  EXAMINED=$((EXAMINED + 1))

  k="$(key_for "$target")"
  link="$STORE_ROOT/$k/memory"

  if [ -L "$link" ]; then
    n="$(count_notes "$link")"
    if [ "$n" -eq 0 ]; then
      say "  BLIND  $name — route exists but resolves to nothing ($link)"
      blind "a route that resolves to no notes" "point the route at the one store"
    else
      say "  ok     $name — $n notes"
      OK=$((OK + 1)); [ "$STATUS" = 0 ] || status_ok
    fi
    continue
  fi

  if [ -d "$link" ]; then
    n="$(count_notes "$link")"
    # A REAL DIRECTORY WITH NOTES IS NEVER REPLACED. It holds notes this tool
    # did not write and cannot merge; clobbering it would lose them silently.
    if [ "$n" -gt 0 ]; then
      say "  own    $name — has its OWN store ($n notes), left untouched"
      OK=$((OK + 1)); [ "$STATUS" = 0 ] || status_ok
      continue
    fi
    # AN EMPTY ONE IS A DIRECTORY, NOT A STORE, and leaving it is a permanent
    # red the operator can do nothing about: the harness creates it the first
    # time a session runs there, so on this box `harbor` had one and would have
    # stayed blind forever.
    #
    # `rmdir`, NEVER 'rm -rf' — the safety property, not a style choice. rmdir
    # refuses a non-empty directory, so if anything at all is in there the
    # replacement cannot proceed and the store survives. The guard is the
    # syscall, not this comment.
    if [ "$APPLY" = 1 ] && rmdir "$link" 2>/dev/null && ln -s "$HOME_STORE" "$link" 2>/dev/null; then
      say "  ROUTED $name — replaced an empty directory with a route"
      MADE=$((MADE + 1)); OK=$((OK + 1))
    else
      say "  BLIND  $name — has an EMPTY own store, so a session here loads nothing"
      blind "an empty own store" "replace the empty directory with a route to the one store"
    fi
    continue
  fi

  if [ "$APPLY" = 1 ]; then
    mkdir -p "$STORE_ROOT/$k" 2>/dev/null || true
    if ln -s "$HOME_STORE" "$link" 2>/dev/null; then
      say "  ROUTED $name"
      MADE=$((MADE + 1)); OK=$((OK + 1))
    else
      say "  BLIND  $name — could not create $link"
      blind "no route, and creating one failed" "create the route to the one store"
    fi
  else
    say "  BLIND  $name — no store for this cwd, so a session here loads nothing"
    blind "no store for this cwd" "add a route to the one store"
  fi
done < "$TARGETS"

# EXAMINED IS ASSERTED, not assumed. A registry that parses to zero rows — a
# changed separator, a CRLF checkout — would otherwise print a clean green
# having checked nothing at all, which is the failure this file's own stand-down
# block exists to prevent one level up.
if [ "$EXAMINED" -eq 0 ]; then
  say "[check:memory-route] STOOD DOWN — the registry parsed to 0 usable rows."
  say "  This is not a pass. Check the tab separators in $REGISTRY."
  stood_down "the registry parsed to 0 usable rows, so nothing was examined"
fi

[ "$STATUS" = 0 ] || status_end || :
say ""
if [ "$BAD" -eq 0 ]; then
  say "[check:memory-route] green — $OK of $EXAMINED governed repo(s) routed${MADE:+, $MADE created this run}"
  receipt green
  exit 0
fi
say "[check:memory-route] RED — $BAD of $EXAMINED governed repo(s) start blind"
receipt red
[ "$APPLY" = 1 ] || say "  Fix: sh $REPO/bin/memory-route.sh --live --apply"
exit 1
