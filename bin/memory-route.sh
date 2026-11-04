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
# `--status` is the reconcile form (contracts/reconcile.md, harbor#1031): the same
# judgement, printed as desired / observed / delta / age for each repo that starts
# blind, and nothing for the ones that do not. It reports only, so it refuses
# `--apply` (exit 2), and its exit code is the plain run's.
#
# --apply refuses to guess its target: writing needs --live or an explicit --dir, since the read path defaults to the live dir and a mutator inheriting that default would write to the real box on a bare --apply (D2's rule).
# Why: the auto-memory store is keyed by the session cwd (~/.claude/projects/<cwd-key>/memory/). A session at $HOME gets the store; one started in the measurement repo gets a different key with no store behind it, so it loads nothing (2026-09-16: 291 notes under the $HOME key, 0 under the repo's). Silent and inverted: the notes most worth having there are written WHILE WORKING IN it, and each was filed from a $HOME session, invisible in the repo it describes (memory-store-topology.md has recorded this since 2026-08-02).
# The fix is one store with many doors, not a store per repo: each governed repo's key gets its `memory` directory symlinked at the $HOME silo, so there is one set of notes and one MEMORY.md index. A store per repo re-creates the invisibility one level down.
# Cost: context-budget.sh now charges the $HOME index (~40 KB) in every governed repo's sessions. An index that is loaded and slightly over budget beats one under budget because nothing reads it, but it makes trimming MEMORY.md a real task.
# It writes only symlinks, only under --apply, and never creates, moves, copies or deletes a note. A pre-existing real directory is reported and left alone: replacing it with a link to a different store would lose notes.
# Removed notes: docs/explanation/code-cases/bin-memory-route.md
set -u

# Its errors go through log-lib on stderr: stdout is the report, which lint IJ6 parses (harbor#896).
# shellcheck disable=SC2034 # read by library-log.sh
LOG_FD=2; . "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)/library-log.sh"; log_init memory-route

_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }

REPO="${HARBOR_SCOPE_REPO:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)}"
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
'; set -f; log_receipt "$RECEIPTS" memory.route "$1" $BLINDS || { log_warn "no receipt written to $RECEIPTS"; log_end || :; }
  set +f; IFS=$_oifs; }

# The write needs an explicit --live for the live dir (lint D2): reading defaults to the live config dir, writing must not inherit that. Resolved paths, not strings: `--dir ~/.claude/` or a symlinked route is the live dir by another spelling (D2's header records a pass that stripped every hook that way).
if [ "$APPLY" = 1 ] && [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ] && [ "$EXPLICIT_LIVE" = 0 ]; then
  log_fail "refusing to write $LIVE_DIR without an explicit --live"; log_fix "sh $0 --live --apply"; log_end || :
  exit 2
fi
if [ "$STATUS" = 1 ] && [ "$APPLY" = 1 ]; then
  # not a run (contracts/logging.md): said on stderr, no summary line
  log_fail "--status only reports, and --apply writes"; log_fix "run one: sh $0 --live --status (report) or sh $0 --live --apply (route)"
  exit 2
fi
# A non-live target must still be named, so a bare --apply cannot fall through on a box whose CLAUDE_CONFIG_DIR points elsewhere.
if [ "$APPLY" = 1 ] && [ "$TARGETED" = 0 ]; then
  log_fail "--apply needs a target — pass --live, or --dir <config-dir>"; log_fix "sh $0 --live --apply"; log_end || :
  exit 2
fi

# ── the key derivation, which is the one thing here that can be wrong ────────
# Claude Code names a project directory after the session cwd with every `/` replaced by `-` (/Users/x/<repo> -> -Users-x-<repo>). Derived, never parsed back: only the forward map is needed.
key_for() { printf '%s' "$1" | sed 's|/|-|g'; }

# THE REGISTRY IS THE PRIVATE LAYER'S (harbor#1149): <private>/context-rules/user/projects.tsv (harbor#1010), through the one resolver beside this
# script. None is the stand-down below, which names where it looked.
_SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)"
REGISTRY="$(env -u HARBOR_SCOPE_ROOT sh "$_SELF/scope-roots.sh" --projects 2>/dev/null || :)"
if [ -z "$REGISTRY" ]; then  # named where the layer's own layout would hold it (harbor#1010)
  _pv="$(env -u HARBOR_SCOPE_ROOT sh "$_SELF/scope-roots.sh" --private 2>/dev/null || :)"
  REGISTRY="$_pv/context-rules/user/projects.tsv"
fi
STORE_ROOT="$CFG/projects"
# Physical on both sides: Claude Code keys off the resolved path (scratchpad silos are `-private-tmp-...` because /tmp is a symlink), so taking $HOME raw works only while no path above it is a link.
[ "$STATUS" = 0 ] || status_init memory.route "$CFG" || exit 3
HOME_KEY="$(key_for "$(_phys "$HOME")")"
HOME_STORE="$STORE_ROOT/$HOME_KEY/memory"

# ── stand down loudly, never quietly green ──────────────────────────────────
# drift-renew-check.sh's case 4 is the precedent: "nothing to compare against" and "nothing wrong" must not render the same.
if [ ! -f "$REGISTRY" ]; then
  say "[check:memory.route] STOOD DOWN — no registry at $REGISTRY, so the governed repos are unknown."
  say "  This is not a pass. Nothing was examined."
  stood_down "no registry at ${REGISTRY#"$REPO"/}, so the governed repos are unknown"
fi
if [ ! -d "$HOME_STORE" ]; then
  say "[check:memory.route] STOOD DOWN — no store at $HOME_STORE to route to."
  say "  This is not a pass. Nothing was examined."
  stood_down "no store at projects/$HOME_KEY/memory to route to"
fi

# A store that exists and holds nothing is the same blindness as no store, so the count is the subject. Resolve first, then walk: `find -P <symlink>` does not descend, so a correctly routed repo counted 0 and the tool called its own --apply a failure. A dangling link resolves to itself, finds nothing, and is BLIND, which is right.
count_notes() {
  _d="$(_phys "$1")"
  find -P "$_d" -maxdepth 1 -name '*.md' 2>/dev/null | grep -c .
}

HOME_N="$(count_notes "$HOME_STORE")"
if [ "$HOME_N" -eq 0 ]; then
  say "[check:memory.route] STOOD DOWN — the store at $HOME_STORE is empty."
  say "  This is not a pass. Routing a repo at an empty store buys nothing."
  stood_down "the store at projects/$HOME_KEY/memory is empty, so routing a repo at it buys nothing"
fi

say "[check:memory.route] $CFG"
say "  store: $HOME_STORE ($HOME_N notes)"

BAD=0; OK=0; MADE=0; EXAMINED=0

# ── every place a session can actually START ────────────────────────────────
# A registry row is a TREE, not a directory: the first version routed the registry paths and eight more directories a session can open were still blind. Two shapes: worktrees (`worktree.sh` makes one per branch, each with its own cwd key) and sub-repos (a pipeline ROOT holds separate checkouts one level down; a session runs in those, never the root). Discovered, never listed: a hardcoded set is stale the next time anyone branches.
route_targets() { # <repo-or-root path> -> one absolute path per line
  printf '%s\n' "$1"
  # `worktree list` prints the main checkout first; every later line is an extra tree. Silent when the path is not a git repo, so a root falls through to the sub-repo branch.
  git -C "$1" worktree list 2>/dev/null | awk 'NR>1 {print $1}'
  # Immediate children that are themselves checkouts, one level only (deeper is vendored dependencies). `-e`, not `-d`: a worktree's `.git` is a FILE, so `-d` missed all five `<sub>-wt-*` worktrees and the first --apply reported "18 of 18 routed" with them still blind (the suite pins both spellings).
  for _c in "$1"/*/; do
    [ -e "$_c.git" ] || continue
    printf '%s\n' "${_c%/}"
  done
}

# The target list is built first, then walked once: `route_targets | while read` runs the loop in a pipeline subshell, so every BAD/OK/MADE increment would be discarded and the tool would report 0 of 0, a silent wrong-green.
TARGETS="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")" || { log_fail "cannot create a temp file"; log_fix "df -h \"\${TMPDIR:-/tmp}\""; log_end || :
  [ "$STATUS" = 0 ] || status_unjudged "cannot create a temp file" || :; exit 3; }
trap 'rm -f "$TARGETS"' EXIT INT TERM

while IFS="$(printf '\t')" read -r name path _rest; do
  case "$name" in ''|\#*) continue ;; esac
  [ -n "${path:-}" ] || continue
  abs="$(printf '%s' "$path" | sed "s|^~|$HOME|")"
  # A row whose directory is gone is skipped, as project-pointer.sh does: lint IJ5 catches a stale row, and judging it here would fail this check for a reason it does not own.
  [ -d "$abs" ] || continue
  route_targets "$abs" | while IFS= read -r tgt; do
    [ -d "$tgt" ] || continue
    # The label names the row, and row/dir for anything discovered under it, without printing an absolute home (§3).
    if [ "$(_phys "$tgt")" = "$(_phys "$abs")" ]; then _l="$name"
    else _l="$name/$(basename "$tgt")"; fi
    printf '%s\t%s\n' "$_l" "$(_phys "$tgt")"
  done
done < "$REGISTRY" | sort -u -t"$(printf '\t')" -k2,2 > "$TARGETS"

# The workspace root is a door too (harbor#619): sessions launch from ${PORT_ROOT:-$HOME/port}, which is not a repo, so no registry row names it; its store was an empty directory the harness made, every session there loaded no memory, and this check was green. Empty PORT_ROOT is unset (contracts/port-root.md); a missing root is skipped.
_pr="${PORT_ROOT:-$HOME/port}"
if [ -d "$_pr" ]; then
  _pr="$(_phys "$_pr")"
  # The WHOLE field, never a prefix: every repo lives under this root.
  awk -F'\t' -v p="$_pr" '$2 == p { f = 1 } END { exit !f }' "$TARGETS" ||
    printf 'port-root\t%s\n' "$_pr" >> "$TARGETS"
fi

# Worktrees under <PORT_ROOT>/.worktrees/<repo>/<slug> are doors too (harbor#1149): a repo registered only in the private layer has no row in projects.tsv, so its trees would start blind. Read off the directory; `.git` is a FILE in a linked worktree; the WHOLE path is compared.
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
    # A real directory with notes is never replaced: it holds notes this tool did not write and cannot merge.
    if [ "$n" -gt 0 ]; then
      say "  own    $name — has its OWN store ($n notes), left untouched"
      OK=$((OK + 1)); [ "$STATUS" = 0 ] || status_ok
      continue
    fi
    # An empty one is a directory, not a store, and leaving it is a permanent red the operator cannot fix: the harness creates it on the first session there. `rmdir`, never rm -rf: rmdir refuses a non-empty directory, so the guard is the syscall, not this comment.
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

# Examined is asserted: a registry that parses to zero rows (changed separator, CRLF) would otherwise print a clean green having checked nothing.
if [ "$EXAMINED" -eq 0 ]; then
  say "[check:memory.route] STOOD DOWN — the registry parsed to 0 usable rows."
  say "  This is not a pass. Check the tab separators in $REGISTRY."
  stood_down "the registry parsed to 0 usable rows, so nothing was examined"
fi

[ "$STATUS" = 0 ] || status_end || :
say ""
if [ "$BAD" -eq 0 ]; then
  say "[check:memory.route] green — $OK of $EXAMINED governed repo(s) routed${MADE:+, $MADE created this run}"
  receipt green
  exit 0
fi
say "[check:memory.route] RED — $BAD of $EXAMINED governed repo(s) start blind"
receipt red
[ "$APPLY" = 1 ] || say "  Fix: sh $REPO/bin/memory-route.sh --live --apply"
# The cause, not just the repair (harbor#966): a raw worktree of a repo without harbor's hooks is born blind.
git config --global --get hook.harbor-memory-route.command >/dev/null 2>&1 ||
  say "  Cause: hooks/post-checkout is not wired box-wide, so a raw worktree outside harbor is born blind (its header has the two git config lines)"
exit 1
