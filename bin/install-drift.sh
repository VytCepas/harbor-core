#!/usr/bin/env sh
# install-drift.sh (harbor#431) — does the RUNNING floor still equal its source?
#
#   sh install-drift.sh [--dir <config-dir>] [--ref <git-ref>] [--quiet]
#
# Exit 0 = every installed bin/ file, and every file the runtime ships elsewhere (lib/), matches the
# ref, resolved through runtime-install's SUITE mapping (harbor#763). Exit 1 = at least one does not.
#
# WHY THIS IS NOT ALREADY COVERED. Three things on this box compare an install
# against something, and none of them asks this question:
#
#   guard-integrity.sh (B6)  pins the box to ITSELF — settings, plugins and
#                            marketplaces against `.sec0-baseline.sha256`, plus
#                            "every guard is present, non-empty, has the
#                            kill-switch". A guard that is present, non-empty
#                            and SIX WEEKS STALE passes all three.
#   install-stamp.sh (#115)  gates the WRITE: "would this deploy remove commits
#                            that are already live". It fires at deploy time and
#                            says nothing between deploys.
#   pin-instructions.sh (B8) pins INSTRUCTION surfaces (CLAUDE.md, skills,
#                            hooks, plugins). `bin/` is not among them.
#   renew-check.sh (#44)     asks "is anything BUILT here not DEPLOYED", by
#                            counting commits since the install stamp over each
#                            installer's OWN declared payload.
#   lint X2 / X2b            the closest siblings, and the ones to read first.
#                            X2 walks `$ROOT/bin/*.sh` and compares each against
#                            its twin in the live bin; X2b does the same for
#                            `~/.local/bin`. Both already handle the hard part —
#                            which SIDE is newer — and X2's header carries the
#                            incident that taught it.
#
# ALL OF THEM ENUMERATE FROM THE REPOSITORY. That is the gap, and it is the whole
# reason this exists. X2 loops over repo files and asks "is this deployed";
# renew-check loops over the installer's payload and asks "did this get out".
# Neither ever lists the live directory, so a file that exists ONLY on the box —
# in no repo tree and no installer payload — is not something they report; it is
# something they cannot reach. X2 skips it at `[ -f "$LIVEBIN/$b" ] || continue`
# before any comparison happens, because the loop never had it to begin with.
#
# This enumerates `$DIR/bin` and asks what is unaccounted for. Verified
# 2026-09-05: in the same lint run that reported X2's one advisory, and with
# `renew-check --live` printing `renew 0` — both correct — save-log-token.sh sat
# in the live floor holding a GitHub PAT, and neither could name it.
#
# So the box was pinned to itself from three directions and to the repository
# from none. Measured 2026-09-05: `save-log-token.sh` was live in the floor's
# `bin/`, handling a GitHub PAT, and existed in no branch, no commit and no
# working tree of this repository. Nothing had ever reported it, because
# nothing was asking.
#
# WHY CONTENT AND NOT A COMMIT COUNT. The obvious check is "how many commits
# has main moved since the install stamp". It was built that way first and the
# measurement killed it: on 2026-09-05 the stamp read 14 commits behind while
# all 48 installed files were byte-identical to `origin/main`. floor-install and
# runtime-install write overlapping sets, so each stamp undercounts what the
# other deployed, and a lag counter reports drift that is not there. A check
# that cries wolf gets switched off, and a disabled check protects nothing
# (CLAUDE.md No.2.11).
#
# THE FOUR VERDICTS. Content alone cannot tell a stale copy from a hand-edit, so
# git is asked instead of guessed. The live bytes are hashed with
# `git hash-object`, which yields the same blob id git itself would store, and
# that id is looked up in the path's history:
#
#   current    blob == the blob at <ref>.
#   stale      blob == the blob at some ANCESTOR commit for that path. The file
#              is a real past version, so this is an undeployed change, and the
#              number of commits since is reported.
#   modified   blob matches <ref> and no ancestor. Nobody's deploy produced
#              these bytes -- either a hand-edit or a file the repo has not seen.
#   unsourced  the path does not exist at <ref> at all. Loudest of the four: a
#              live floor file with no source of truth, which no deploy can
#              reproduce and no review has read.
#
# `stale` and `modified` are deliberately separate. Merging them would report a
# missed deploy and an unreviewed edit to a security guard as the same event,
# and only one of those is fixed by re-running the installer.
set -u

STAMP='[check:install-drift]'
DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REF="origin/main"
QUIET=0

usage() { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; }

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)" || REPO=""
[ -n "$REPO" ] || { printf 'install-drift: cannot locate the repo this script sits in, so it cannot load log-lib.sh\n' >&2; exit 2; }
. "$REPO/bin/log-lib.sh"
. "$REPO/bin/install-lib.sh"
log_init install-drift

# EXIT 2 NEVER COMES WITHOUT A FAIL LINE AND ITS FIX (harbor#457). It used to leave one printf on stderr, so a caller
# that relays the first FAIL (live-verify) could only say "exited 2: no FAIL line". The libs load before the arguments
# are read for that reason (a --dir or --ref with no value included: dash dies on the second shift with no FAIL line);
# the one exit 2 left outside is the line above, where the libs themselves cannot be found.
_die2() { # <what failed> <fix command | "none: <where>">
  log_fail "$1 $STAMP"
  case "${2-}" in 'none: '*) log_nofix "${2#none: }" ;; *) log_fix "${2-}" ;; esac
  log_end || :
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) [ $# -ge 2 ] && [ -n "$2" ] || _die2 "install-drift: --dir needs a config dir" "none: sh $0 --help"; DIR="$2"; shift ;;
    --ref) [ $# -ge 2 ] || _die2 "install-drift: --ref needs a git ref" "none: sh $0 --help"; REF="$2"; shift ;;
    --quiet) QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) _die2 "install-drift: unknown flag: $1" "none: sh $0 --help" ;;
  esac
  shift
done

# How the fixes below are spelled (also the stale verdicts' fix at the end): the live box is HOME/.claude.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
_qn() { case "$1" in *[!A-Za-z0-9_./:=@%+,-]*|'') _q "$1" ;; *) printf '%s' "$1" ;; esac; }
LIVE="$HOME/.claude"
_target_spelling() { if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then printf '%s' --live; else printf '%s %s' --dir "$(_q "$(_phys "$DIR")")"; fi; }
_redeploy() { # the command that puts this repo's bytes back: deploy for the live box, the installers elsewhere
  if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then printf 'sh %s/bin/deploy.sh --apply --live' "$(_qn "$REPO")"
  else printf 'sh %s/bin/runtime-install.sh --apply %s && sh %s/bin/floor-install.sh --apply %s' \
         "$(_qn "$REPO")" "$(_target_spelling)" "$(_qn "$REPO")" "$(_target_spelling)"; fi
}

# NO INSTALL TO COMPARE IS NAMED BY ITS CAUSE (harbor#457): a box with no config dir, or no settings.json, has had no
# first-run step, and one with a config dir but no bin/ has had no deploy (unless .harbor-manifest says one ran). The
# first has a command only on the live box.
if [ ! -d "$DIR/bin" ]; then
  if { [ ! -d "$DIR" ] || [ ! -f "$DIR/settings.json" ]; } && ! il_installed "$DIR"; then
    if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then _fx="$(il_first_run_cmd "$REPO")"; _why=': the first-run step has not been taken'
    else _fx="none: the path given to --dir, which is not a config dir"; _why=''; fi
    [ -d "$DIR" ] && _w="no settings.json in $DIR" || _w="no config dir at $DIR"
    _die2 "$_w, so there is no install to compare$_why" "$_fx"
  fi
  if [ -f "$DIR/.harbor-manifest" ]; then _why='.harbor-manifest records an install, so bin/ was removed after the deploy'
  else _why='no deploy has run here'; fi
  _die2 "no bin/ in $DIR, so there is no install to compare: $_why" "$(_redeploy)"
fi

# A ref that does not resolve must ABORT, never silently classify every file as
# `unsourced` -- that failure mode reports a clean box as catastrophically
# broken, which is the same false-positive trap in the other direction.
git -C "$REPO" rev-parse --verify --quiet "$REF^{commit}" >/dev/null 2>&1 || \
  _die2 "ref does not resolve: $REF" "none: git -C $(_qn "$REPO") rev-parse --verify $(_qn "$REF") (the ref this check compares against)"

n_current=0; n_stale=0; n_modified=0; n_unsourced=0
findings=""
NL='
'
TAB='	'

# WHERE AN INSTALLED FILE COMES FROM (harbor#763). bin/<name> is bin/<name> in the repo, except for
# what runtime-install's SUITE ships from elsewhere: bin/recover-test.sh is tests/floor/recover-test.sh,
# lib/core.sh is tests/lib/core.sh. The mapping is read from the installer AT THE REF, so the question
# is always "what would that commit's installer have put here". Without it the suite read `unsourced`
# on every run, forever, and a stale or hand-edited copy of it could never be told apart.
# DATA ships the same way (CHECKS.md, CONTRACTS/*.tsv into bin/), so it is read too.
SUITE_MAP="$(git -C "$REPO" show "$REF:bin/runtime-install.sh" 2>/dev/null \
  | sed -n -e 's/^SUITE="\(.*\)"/\1/p' -e 's/^DATA="\(.*\)"/\1/p' | tr ' ' '\n' \
  | awk -F: 'NF == 2 && $1 != "" && $2 != "" { print $2 "\t" $1 }')"
_src_of() { # <relpath under the config dir> -> the repo path it is installed from
  _so="$(printf '%s\n' "$SUITE_MAP" | awk -F'\t' -v r="$1" '$1 == r { print $2; exit }')"
  # A hook engine ships from its folder (D-88): bin/<name> is gone at that ref and hooks/<stem>/<name> is there.
  case "${_so:-$1}" in bin/*)
    git -C "$REPO" cat-file -e "$REF:$1" 2>/dev/null || ! git -C "$REPO" cat-file -e "$REF:$(il_engine_path "${1#bin/}")" 2>/dev/null \
      || _so="$(il_engine_path "${1#bin/}")" ;;
  esac
  printf '%s' "${_so:-$1}"
}

# THE SET: every file in bin/ (a file only the box has is the finding this exists for), plus what the
# install manifest (install standard §3) and SUITE record elsewhere — lib/core.sh — for the two installers
# whose payload this check owns. The verdict never comes from the manifest: it is git's, below.
_set="$(for live in "$DIR"/bin/*; do [ -f "$live" ] && printf 'bin/%s\n' "${live##*/}"; done
        il_mf_rows "$DIR" | awk -F'\t' '($3 == "runtime-install" || $3 == "floor-install") && $1 !~ /^bin\/[^\/]*$/ { print $1 }'
        printf '%s\n' "$SUITE_MAP" | awk -F'\t' '$1 != "" && $1 !~ /^bin\/[^\/]*$/ { print $1 }')"
_set="$(printf '%s\n' "$_set" | awk 'NF && !seen[$0]++')"
# A file a pack installed (its manifest in .harbor-packs, written by pack.sh) is that pack's, not this commit's, and
# pack.sh refuses to write over a core file: so it is never `unsourced` here.
_pown="$(mktemp "${TMPDIR:-/tmp}/install-drift-own.XXXXXX")" || _die2 "cannot create a temp file in ${TMPDIR:-/tmp}" "none: the TMPDIR this check was given"
cat "$DIR"/.harbor-packs/*.tsv 2>/dev/null | awk -F'\t' '$1 == "F" { print $2 }' > "$_pown"
if [ -s "$_pown" ]; then
  _set="$(printf '%s\n' "$_set" | awk -v f="$_pown" 'BEGIN { while ((getline l < f) > 0) o[l] = 1 } !($0 in o)')"
fi
rm -f "$_pown"

# THE REGISTER IS INSTALLED COMPOSED (harbor#1149): bin/CHECKS.md is core CHECKS.md plus the private layer's rows and the
# rows of the packs installed in $DIR/checks.d, so
# the blob it is held to is the composition of the register AT THAT COMMIT, never the bare core blob. With no private
# layer the composition is core byte for byte, and the blob is the commit's own.
_ckt="$(mktemp "${TMPDIR:-/tmp}/install-drift-checks.XXXXXX")" || _die2 "cannot create a temp file in ${TMPDIR:-/tmp}" "none: the TMPDIR this check was given"
trap 'rm -f "$_ckt" "$_ckt.out" "$_ckt.rc" "$_ckt.rc.out"' EXIT
# The required-checks list is installed composed the same way (harbor#1149): bin/required-checks.tsv is core's rows plus the private
# layer's required-checks.tsv, so it is held to the composition of the list AT THAT COMMIT; with no layer that is the commit's own blob.
_blob_of() { # <commit> <repo path> -> the blob this path is held to at that commit
  if [ "$2" = CONTRACTS/required-checks.tsv ] && git -C "$REPO" show "$1:$2" > "$_ckt.rc" 2>/dev/null \
     && sh "$REPO/bin/gate-required-generate.sh" --core "$_ckt.rc" > "$_ckt.rc.out" 2>/dev/null; then
    git -C "$REPO" hash-object "$_ckt.rc.out" 2>/dev/null && return 0
  fi
  if [ "$2" = CHECKS.md ] && git -C "$REPO" show "$1:CHECKS.md" > "$_ckt" 2>/dev/null \
     && sh "$REPO/bin/check-registry-generate.sh" --core "$_ckt" --packs "$DIR/checks.d" > "$_ckt.out" 2>/dev/null; then
    git -C "$REPO" hash-object "$_ckt.out" 2>/dev/null && return 0
  fi
  git -C "$REPO" rev-parse --quiet --verify "$1:$2" 2>/dev/null
}
# An install made before the list was composed is a bare older core blob, and one made when the private layer held other rows is an
# older core with an older revision of the layer's file (the layer is a repo of its own and records them). Both are BEHIND, not edited
# in place; only bytes no commit of either explains read modified (a layer row deployed uncommitted and since dropped, or an edit).
RC_SRC=CONTRACTS/required-checks.tsv
_lrevs=""
[ ! -f "$REPO/bin/gate-required-generate.sh" ] || _lrevs="$(sh "$REPO/bin/gate-required-generate.sh" --layer-revs 2>/dev/null || :)"
_rc_older() { # <core commit> <installed blob> -> 0 when those bytes are that core, bare or with an older revision of the layer's file
  _ob="$(git -C "$REPO" rev-parse --quiet --verify "$1:$RC_SRC" 2>/dev/null)" || return 1
  [ "$_ob" != "$2" ] || return 0
  git -C "$REPO" show "$1:$RC_SRC" > "$_ckt.rc" 2>/dev/null || return 1
  for _lr in $_lrevs; do
    sh "$REPO/bin/gate-required-generate.sh" --core "$_ckt.rc" --private-rev "$_lr" > "$_ckt.rc.out" 2>/dev/null || continue
    [ "$(git -C "$REPO" hash-object "$_ckt.rc.out" 2>/dev/null)" != "$2" ] || return 0
  done
  return 1
}

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  live="$DIR/$rel"
  [ -f "$live" ] || continue
  # bin/ files keep the name they have always been reported by; the rest are named by their path.
  case "$rel" in bin/*/*) b="$rel" ;; bin/*) b="${rel#bin/}" ;; *) b="$rel" ;; esac
  src="$(_src_of "$rel")"
  live_blob="$(git -C "$REPO" hash-object -- "$live" 2>/dev/null)" || continue

  ref_blob="$(_blob_of "$REF" "$src" || true)"

  if [ -z "$ref_blob" ]; then
    # Absent at the ref. It may still be a file the repo DELETED, which is a
    # different story from one it never had, so history is asked before the
    # louder verdict is used.
    if git -C "$REPO" rev-list "$REF" -- "$src" 2>/dev/null | head -1 | grep -q .; then
      findings="${findings}unsourced$TAB$b${TAB}deleted from the repo, still installed$TAB$rel$TAB$src$NL"
    else
      findings="${findings}unsourced$TAB$b${TAB}in no commit of this repository$TAB$rel$TAB$src$NL"
    fi
    n_unsourced=$((n_unsourced + 1))
    continue
  fi

  if [ "$live_blob" = "$ref_blob" ]; then
    n_current=$((n_current + 1))
    continue
  fi

  # Differs from the ref. Walk that path's history for these exact bytes; an engine moved into
  # hooks/<engine>/ (D-88) also walks its old bin/ path, or every copy from before the move reads modified.
  behind=0; matched=0; older=0
  case "$src" in hooks/*) was="$rel" ;; *) was="$src" ;; esac
  for c in $(git -C "$REPO" rev-list "$REF" -- "$src" "$was" 2>/dev/null); do
    hb="$(_blob_of "$c" "$src" || _blob_of "$c" "$was" || true)"
    [ -n "$hb" ] || continue
    if [ "$hb" = "$live_blob" ]; then matched=1; break; fi
    if [ "$src" = "$RC_SRC" ] && _rc_older "$c" "$live_blob"; then matched=1; older=1; break; fi
    behind=$((behind + 1))
  done

  if [ "$matched" = 1 ]; then
    why="installed copy is $behind commit(s) behind $REF"
    [ "$older" = 0 ] || why="installed list was composed before core or the private layer last changed ($behind core commit(s) behind $REF); a redeploy composes both as they are now"
    findings="${findings}stale$TAB$b${TAB}$why$TAB$rel$TAB$src$NL"
    n_stale=$((n_stale + 1))
  else
    findings="${findings}modified$TAB$b${TAB}bytes match no commit -- edited in place, or never committed$TAB$rel$TAB$src$NL"
    n_modified=$((n_modified + 1))
  fi
done <<SET
$_set
SET

bad=$((n_stale + n_modified + n_unsourced))
[ "$QUIET" = 1 ] && [ "$bad" -eq 0 ] && exit 0

# Every line the check emits names it (CHECKS.md): the header, and a suffix on each result line.
log_head "$STAMP $DIR/bin vs $REF"
log_note "current=$n_current stale=$n_stale modified=$n_modified unsourced=$n_unsourced $STAMP"
[ "$n_current" -eq 0 ] || log_ok "$n_current installed file(s) match $REF $STAMP"
while IFS='	' read -r _v _b _why _rel _src; do
  [ -n "$_v" ] || continue
  log_fail "$_v $_b ($_why) $STAMP"
  case "$_v" in
    stale) log_fix "$(_redeploy)" ;;
    modified)
      if [ "$_src" = "$RC_SRC" ]; then
        log_nofix "bin/install-drift.sh (the list is core's rows plus the private layer's required-checks.tsv: diff $DIR/$_rel against the output of 'sh $REPO/bin/gate-required-generate.sh' and capture what only the box holds; a redeploy overwrites it)"
      else
        log_nofix "bin/install-drift.sh (diff $REPO/$_src $DIR/$_rel and capture what exists only on the box; a redeploy overwrites it)"
      fi ;;
    *) log_nofix "bin/install-drift.sh (nothing in $REPO reproduces $DIR/$_rel: commit it, or move it out of ${_rel%/*}/)" ;;
  esac
done <<ROWS
$findings
ROWS
log_end; exit $?
