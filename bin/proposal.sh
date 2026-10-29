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
# THE INVERSION THIS FILE IS BUILT ON: A REVIEWER MAY VETO, NEVER APPROVE. The
# request that produced it was the opposite — let an independent subagent bless a
# change so the human gate can be skipped — and that direction cannot be made
# safe here. An LLM reviewer is a RULE, and this estate has already measured that
# rules do not bound an agent that can act: an `ask` verdict auto-approves off the
# main loop, and the standing conclusion was "the mitigation is identity, never a
# rule". A reviewer that can widen `permissions.deny` is an agent granting itself
# permission by convincing another instance of itself. Harbor also carries the
# receipt: pass 9's confidently-applied fixes caused ~24 defects that pass 10
# found, WITH A GREEN SUITE THROUGHOUT — a reviewing agent would have read that
# same green suite.
#
# So a review can only ever REMOVE a packet from the queue. There is deliberately
# no `--approve` flag and no "approved" state: a packet is `pending` until a
# human runs `apply --apply`, and an unrefuted packet is UNREFUTED, never
# approved. The failure mode of a broken or captured reviewer is therefore a
# missed improvement, never a self-granted permission.
#
# A REVIEW IS A SIGNATURE OVER THE PATCH BYTES, not over the packet name. Each
# verdict records the sha256 of `patch.diff` as reviewed; `apply` recomputes it
# and ignores every verdict for a different digest. Without that, "reviewed" is a
# label on a directory whose contents can be swapped afterwards — which is the
# whole attack this design would otherwise invite.
#
# THE TIER IS COMPUTED FROM THE PATCH, NEVER DECLARED. A packet that names its
# own risk level is a claim written by the thing being judged. `apply` classifies
# the touched paths itself, every time, and floor-adjacent paths need `--floor`
# typed by the operator on top of `--apply`.
#
# THE PACKET MACHINERY IS UNPATCHABLE FROM A PACKET. A diff touching this file or
# its suite is refused outright, at `new` and again at `apply`, with no flag that
# overrides it. Everything else here is a gate a human chooses to pass; that one
# is the hinge they all hang on.
#
# IT IS NOT WIRED TO ANYTHING. No hook, no launchd job, and nothing in this repo
# calls `apply`. Generating and reviewing are safe to automate; ingesting is the
# human act, and automating the last step would delete the property the first two
# exist to protect.
set -u

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="${HARBOR_SCOPE_REPO:-${HARBOR_REPO:-$(CDPATH= cd -- "$DIR/.." && pwd -P)}}"
STORE="$ROOT/proposals"

_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
# Status lines are log-lib's, on stderr: stdout is the verb's data (list, count, show, a dry run's files).
. "$DIR/library-log.sh"
log_init proposal; LOG_FD=2
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
# Floor-adjacent: allowed, but only when the operator types --floor as well. The
# linter is in this list on purpose — a packet that exempts itself from a lint
# rule is the same self-granting shape as one that edits its own reviewer, one
# indirection further out.
touches_floor() { # <patch-file>
  _files_in "$1" | while IFS= read -r f; do
    case "$f" in
      bin/guard-*|bin/floor-*|bin/sec0-*|hooks/*|*settings.json|bin/lint-conventions.sh) printf '%s\n' "$f" ;;
    esac
  done
}
# EVERY SIDE OF EVERY CHANGE SHAPE, and this is not defensive padding — the
# first version read `+++ b/` alone and TWO ATTACKS WALKED THROUGH IT, both
# reproduced 2026-08-13 against a fixture repo:
#
#   · a patch that DELETES bin/proposal.sh has `+++ /dev/null` and its only
#     mention of the file is on the `---` side, so the machinery gate saw a
#     0-file "ordinary" packet. Deleting the reviewer is at least as powerful as
#     editing it, and that is the one gate with no override.
#   · a pure RENAME (`bin/guard-x.sh` -> `bin/harmless.sh`) carries NO `+++` line
#     at all — only `rename from`/`rename to` — so a floor file could be moved
#     out of the floor tier with no --floor typed.
#
# So both sides are read, plus the rename pair, `/dev/null` is dropped, and git's
# quoted form (`--- "a/x y"`) is unquoted — an unquoted parse would make a path
# with a space invisible to both classifiers.
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
  # UNTRACKED FILES ARE REFUSED, NOT SILENTLY DROPPED. `git diff HEAD` sees only
  # tracked content, so a change that ADDS a file produces a patch missing that
  # file entirely — and the packet then reads as "the change" while carrying part
  # of it. Measured the first time this ran against a real working tree: a packet
  # was created from a 7-file diff whose two new scripts were not in it, including
  # the one the machinery gate exists to catch. Refusing is side-effect-free;
  # `git add -N` is one command and makes the intent explicit in the index.
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
  # EVIDENCE IS EXPLICIT, AND STDIN IS NEVER READ UNLESS ASKED FOR. The first
  # version read stdin whenever it was not a tty, and that BLOCKS FOREVER on an
  # open-but-silent pipe — measured 2026-08-13: the same command took 4 seconds
  # under `(sleep 4) | …` and would hang indefinitely under a scheduled or
  # piped caller. `[ -t 0 ]` answers "is this a terminal", never "does data
  # follow", and no read can tell an empty pipe from a slow one.
  #
  # ABSENCE IS RECORDED, not defaulted to something reassuring: an empty
  # evidence file reads as "none was offered", which is what a reviewer and the
  # operator both need to see stated.
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
    _sh="$(_sha < "$p/patch.diff" 2>/dev/null)"
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
  printf 'patch_sha=%s\n' "$(_sha < "$P/patch.diff")"
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
  _sh="$(_sha < "$P/patch.diff")"
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
  _sh="$(_sha < "$P/patch.diff")"
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
  # A dirty tree makes `git apply` unrevertable by inspection: the operator can
  # no longer tell what the packet did from what they were already doing.
  # EXCLUDING THE PACKET STORE, which is the one thing that is always modified
  # here: `new` and `review` write into proposals/ by design, so counting it as
  # dirt would make every packet unappliable the moment it was reviewed — a gate
  # that blocks the ordinary path, which §2.11 calls a defect rather than safety.
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
