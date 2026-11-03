#!/usr/bin/env sh
# proposal (harbor#44 follow-through) — self-improvement packets a human ingests.
#
#   sh proposal.sh new <slug> --falsifier <text> [--from <range>] [--evidence -|<file>]
#   sh proposal.sh list
#   sh proposal.sh show <slug>
#   sh proposal.sh review <slug> --as <name> [--refuted --reason <text>]
#   sh proposal.sh apply <slug> [--apply] [--floor]
#
# Exit 0 = the verb did its job. 1 = a gate refused. 2 = bad usage.
#
# A reviewer may veto, never approve. An LLM reviewer is a rule, and rules do not bound an agent that can act
# (an `ask` verdict auto-approves off the main loop; pass 9's confident fixes caused ~24 defects pass 10 found,
# with a green suite throughout). So a review can only REMOVE a packet from the queue: there is no `--approve`
# and no "approved" state. A packet is `pending` until a human runs `apply --apply`; an unrefuted packet is
# UNREFUTED. A captured reviewer costs a missed improvement, never a self-granted permission.
# A review is a signature over the patch bytes: each verdict records the sha256 of `patch.diff`, and `apply`
# ignores verdicts for a different digest, so a reviewed directory cannot be swapped afterwards.
# The tier is computed from the patch, never declared; floor-adjacent paths need `--floor` on top of `--apply`.
# This file and its suite are unpatchable from a packet, at `new` and at `apply`, with no override.
# It is wired to nothing (no hook, no launchd job): generating and reviewing may be automated, ingesting is the human act.
# Removed notes: docs/explanation/code-cases/bin-proposal.md
set -u

# --help before any work (S4, harbor#140): the text is this header, read at runtime.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="${HARBOR_SCOPE_REPO:-$(CDPATH= cd -- "$DIR/.." && pwd -P)}"
STORE="$ROOT/proposals"

# Status lines are log-lib's, on stderr: stdout is the verb's data (list, count, show, a dry run's files).
. "$DIR/library-log.sh"; . "$DIR/library-fs.sh"
log_init proposal
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
# die <what failed> [exit code, default 2] [fix command]: FAIL, its fix, the summary, exit.
die() {
  log_fail "$1"
  if [ -n "${3:-}" ]; then log_fix "$3"; else log_nofix "the header of bin/proposal.sh"; fi
  log_end || :
  exit "${2:-2}"
}
_H="sh bin/proposal.sh --help"
meta() { sed -n "s/^$2=//p" "$STORE/$1/meta" 2>/dev/null | tail -1; }

# The one list with no override. Kept as a function rather than a variable so the
# match is anchored per path and cannot be widened by a stray glob.
touches_machinery() { # <patch-file>
  _files_in "$1" | while IFS= read -r f; do
    case "$f" in bin/proposal.sh|tests/proposal/proposal/proposal.test.sh) printf '%s\n' "$f" ;; esac
  done
}
# Floor-adjacent: allowed with --floor. The linter is listed on purpose: a packet exempting itself from a lint
# rule is the same self-granting shape as one editing its reviewer.
touches_floor() { # <patch-file>
  _files_in "$1" | while IFS= read -r f; do
    case "$f" in
      bin/admission-*|bin/library-admission.sh|bin/guard-*|bin/floor-*|bin/sec0-*|hooks/*|*settings.json|bin/lint-conventions.sh) printf '%s\n' "$f" ;;
    esac
  done
}
# Read EVERY side of every change shape: `+++ b/` alone let two attacks through (2026-08-13). A patch DELETING
# bin/proposal.sh has `+++ /dev/null`, so the machinery gate saw 0 files; a pure RENAME has no `+++` line, so a
# floor file could leave the floor tier. Both sides and the rename pair are read, `/dev/null` is dropped, and
# git's quoted form (`--- "a/x y"`) is unquoted so a path with a space is not invisible.
_files_in() {
  sed -n -e 's|^--- ||p' -e 's|^+++ ||p' "$1" 2>/dev/null \
    | sed -e 's|^"||' -e 's|"$||' -e 's|^[ab]/||' | grep -v '^/dev/null$'
  sed -n -e 's|^rename from ||p' -e 's|^rename to ||p' "$1" 2>/dev/null \
    | sed -e 's|^"||' -e 's|"$||'
}

usage() { sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -ge 1 ] || usage
VERB="$1"; shift

case "$VERB" in
new)
  [ $# -ge 1 ] || usage
  SLUG="$1"; shift
  case "$SLUG" in *[!abcdefghijklmnopqrstuvwxyz0-9-]*|"") die "slug must be kebab-case: $SLUG" 2 "$_H" ;; esac
  FALS=""; FROM=""; EV=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --falsifier) shift; FALS="${1:-}" ;;
      --from)      shift; FROM="${1:-}" ;;
      --evidence)  shift; EV="${1:-}" ;;
      *) die "unknown flag for new: $1" 2 "$_H" ;;
    esac
    shift
  done
  [ -n "$FALS" ] || die "--falsifier is required: name what would show this change is wrong" 2 "sh bin/proposal.sh new $SLUG --falsifier \"<what would show this change is wrong>\""
  [ -d "$STORE/$SLUG" ] && die "packet exists: $SLUG" 1 "sh bin/proposal.sh show $SLUG"
  P="$STORE/$SLUG"
  mkdir -p "$P/reviews" || die "cannot create $P" 1
  # Untracked files are REFUSED, not silently dropped: `git diff HEAD` omits added files, so a packet read as
  # "the change" while missing part of it. `git add -N` makes the intent explicit.
  if [ -z "$FROM" ]; then
    _unt="$(git -C "$ROOT" ls-files --others --exclude-standard -- ':!proposals' 2>/dev/null)"
    if [ -n "$_unt" ]; then
      rm -rf "$P"
      log_note "untracked, and therefore NOT in \`git diff HEAD\`: $(printf '%s' "$_unt" | tr '\n' ' ')"
      die "the patch would omit these untracked files" 1 "git add -N <files>   # or pass --from <range>"
    fi
  fi
  if [ -n "$FROM" ]; then git -C "$ROOT" diff "$FROM" > "$P/patch.diff" 2>/dev/null
  else                    git -C "$ROOT" diff HEAD  > "$P/patch.diff" 2>/dev/null; fi
  [ -s "$P/patch.diff" ] || { rm -rf "$P"; die "empty diff — a packet with no change is a claim with nothing to check" 1 "make the change, then sh bin/proposal.sh new $SLUG --falsifier <text>"; }
  if [ -n "$(touches_machinery "$P/patch.diff")" ]; then
    rm -rf "$P"
    die "the patch touches the packet machinery itself — refused with no override" 1
  fi
  # Evidence is explicit and stdin is never read unless asked: reading whenever it was not a tty blocked forever on
  # an open-but-silent pipe. Absence is recorded ("none was offered"), not defaulted to something reassuring.
  case "$EV" in
    "")  : > "$P/evidence.md" ;;
    -)   cat > "$P/evidence.md" ;;
    *)   [ -f "$EV" ] || { rm -rf "$P"; die "no such evidence file: $EV" 1 "sh bin/proposal.sh new $SLUG --falsifier <text> --evidence <an existing file>"; }
         cat "$EV" > "$P/evidence.md" ;;
  esac
  [ -s "$P/evidence.md" ] || printf 'NO EVIDENCE SUPPLIED.\n' > "$P/evidence.md"
  { printf 'slug=%s\n' "$SLUG"
    printf 'created=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'status=pending\n'
    printf 'falsifier=%s\n' "$FALS"
  } > "$P/meta"
  log_ok "$(printf 'packet %s created (%s file(s), %s)' "$SLUG" \
    "$(_files_in "$P/patch.diff" | wc -l | tr -d ' ')" \
    "$( [ -n "$(touches_floor "$P/patch.diff")" ] && echo 'floor-adjacent — apply needs --floor' || echo 'ordinary' )")"
  log_end; exit $?
  ;;

list)
  [ -d "$STORE" ] || { printf 'no packets\n'; exit 0; }
  _n=0
  for p in "$STORE"/*/; do
    [ -f "$p/meta" ] || continue
    _s="$(basename "$p")"; _n=$((_n+1))
    _sh="$(fs_sha256 < "$p/patch.diff" 2>/dev/null)"
    _ref=0; _ok=0
    for r in "$p/reviews"/*.json; do
      [ -f "$r" ] || continue
      grep -q "\"patch_sha\": *\"$_sh\"" "$r" 2>/dev/null || continue
      if grep -q '"refuted": *true' "$r"; then _ref=$((_ref+1)); else _ok=$((_ok+1)); fi
    done
    # "unrefuted", never "approved" — the word is the contract.
    printf '%-24s %-9s refuted=%s unrefuted=%s %s\n' "$_s" "$(meta "$_s" status)" "$_ref" "$_ok" \
      "$( [ -n "$(touches_floor "$p/patch.diff")" ] && echo '[floor]' || echo '' )"
  done
  [ "$_n" = 0 ] && printf 'no packets\n'
  exit 0
  ;;

count)
  # For the statusline: packets a human still has to look at. A vetoed or applied
  # packet is not pending work.
  _n=0
  for p in "$STORE"/*/; do
    [ -f "$p/meta" ] || continue
    [ "$(meta "$(basename "$p")" status)" = "pending" ] && _n=$((_n+1))
  done
  printf '%s\n' "$_n"
  exit 0
  ;;

show)
  [ $# -ge 1 ] || usage
  P="$STORE/$1"; [ -f "$P/meta" ] || die "no such packet: $1" 1 "sh bin/proposal.sh list"
  printf '== %s ==\n' "$1"; cat "$P/meta"
  printf 'patch_sha=%s\n' "$(fs_sha256 < "$P/patch.diff")"
  printf '\n== files ==\n'; _files_in "$P/patch.diff"
  printf '\n== evidence ==\n'; cat "$P/evidence.md"
  printf '\n== reviews ==\n'
  _any=0
  for r in "$P/reviews"/*.json; do [ -f "$r" ] || continue; _any=1; cat "$r"; done
  [ "$_any" = 0 ] && printf 'none — an unreviewed packet is not a rejected one, it is an unlooked-at one\n'
  exit 0
  ;;

review)
  [ $# -ge 1 ] || usage
  SLUG="$1"; shift
  P="$STORE/$SLUG"; [ -f "$P/meta" ] || die "no such packet: $SLUG" 1 "sh bin/proposal.sh list"
  AS=""; REF=false; REASON=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --as)      shift; AS="${1:-}" ;;
      --refuted) REF=true ;;
      --reason)  shift; REASON="${1:-}" ;;
      --approve|--approved|--ok)
        die "there is no approve verb — a review can only refute; a human applying is the approval" 2 "sh bin/proposal.sh review $SLUG --as <name> --refuted --reason <text>" ;;
      *) die "unknown flag for review: $1" 2 "$_H" ;;
    esac
    shift
  done
  [ -n "$AS" ] || die "--as <name> is required: an anonymous verdict cannot be argued with" 2 "sh bin/proposal.sh review $SLUG --as <name>"
  [ "$REF" = true ] && [ -z "$REASON" ] && die "a refusal needs --reason: a veto with no reason cannot be answered" 2 "sh bin/proposal.sh review $SLUG --as $AS --refuted --reason <text>"
  case "$AS" in *[!a-zA-Z0-9_-]*) die "reviewer name must be [a-zA-Z0-9_-]: $AS" 2 "sh bin/proposal.sh review $SLUG --as <name>" ;; esac
  _sh="$(fs_sha256 < "$P/patch.diff")"
  printf '{"reviewer": "%s", "refuted": %s, "reason": "%s", "patch_sha": "%s", "at": "%s"}\n' \
    "$AS" "$REF" "$(printf '%s' "$REASON" | sed 's/"/\\"/g')" "$_sh" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "$P/reviews/$AS.json"
  [ "$REF" = true ] && { sed -i.bak 's/^status=.*/status=vetoed/' "$P/meta"; rm -f "$P/meta.bak"; }
  log_ok "recorded $AS verdict for $SLUG (refuted=$REF)"
  log_end; exit $?
  ;;

apply)
  [ $# -ge 1 ] || usage
  SLUG="$1"; shift
  DO=0; FLOOR=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) DO=1 ;;
      --floor) FLOOR=1 ;;
      *) die "unknown flag for apply: $1" 2 "$_H" ;;
    esac
    shift
  done
  P="$STORE/$SLUG"; [ -f "$P/meta" ] || die "no such packet: $SLUG" 1 "sh bin/proposal.sh list"
  [ "$(meta "$SLUG" status)" = "pending" ] || die "packet is $(meta "$SLUG" status), not pending" 1 "sh bin/proposal.sh list"

  # Re-run every classification against the CURRENT bytes. The packet's own
  # metadata is not consulted for any of this: it was written by the proposer.
  [ -n "$(touches_machinery "$P/patch.diff")" ] && \
    die "the patch touches the packet machinery itself — refused with no override" 1
  _sh="$(fs_sha256 < "$P/patch.diff")"
  _ref=0; _ok=0
  for r in "$P/reviews"/*.json; do
    [ -f "$r" ] || continue
    grep -q "\"patch_sha\": *\"$_sh\"" "$r" 2>/dev/null || continue
    if grep -q '"refuted": *true' "$r"; then _ref=$((_ref+1)); else _ok=$((_ok+1)); fi
  done
  [ "$_ref" -gt 0 ] && die "$_ref reviewer(s) refuted this patch — read them" 1 "sh bin/proposal.sh show $SLUG"
  [ "$_ok" -gt 0 ] || die "no unrefuted review of THESE patch bytes ($_sh) — review it, or re-review after the edit" 1 "sh bin/proposal.sh review $SLUG --as <name>"
  if [ -n "$(touches_floor "$P/patch.diff")" ] && [ "$FLOOR" = 0 ]; then
    log_note "floor-adjacent paths in this patch: $(touches_floor "$P/patch.diff" | tr '\n' ' ')"
    die "refusing without --floor" 1 "sh bin/proposal.sh apply $SLUG --floor   # typed by the operator, on top of --apply"
  fi
  # A dirty tree makes `git apply` unrevertable by inspection. The packet store is excluded: `new` and `review`
  # write into proposals/ by design, so counting it would make every reviewed packet unappliable.
  [ -n "$(git -C "$ROOT" status --porcelain -- ':!proposals' 2>/dev/null)" ] && \
    die "working tree is dirty — commit or stash first, so this patch is the only change in it" 1 "git stash   # or commit, then re-run apply"
  git -C "$ROOT" apply --check "$P/patch.diff" 2>/dev/null || \
    die "the patch no longer applies cleanly to this tree" 1 "git -C $ROOT apply --check $P/patch.diff   # see why, then re-create the packet"

  if [ "$DO" = 0 ]; then
    _files_in "$P/patch.diff"
    log_ok "every gate passed (dry run, nothing written)"
    log_note "to write it: sh bin/proposal.sh apply $SLUG --apply"
    log_end; exit $?
  fi
  git -C "$ROOT" apply "$P/patch.diff" || die "git apply failed" 1 "git -C $ROOT apply --check $P/patch.diff"
  sed -i.bak 's/^status=.*/status=applied/' "$P/meta"; rm -f "$P/meta.bak"
  log_ok "applied $SLUG — the tree now carries it, uncommitted"
  log_note "falsifier to run: $(meta "$SLUG" falsifier)"
  log_end; exit $?
  ;;
*) usage ;;
esac
