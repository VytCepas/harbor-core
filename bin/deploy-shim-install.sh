#!/usr/bin/env sh
# deploy-shim-install.sh — the ~/.local/bin commands, from contracts/shims.tsv. harbor#630.
#   sh deploy-shim-install.sh [--apply] (--live | --dir BIN)   DRY RUN unless --apply
#     --live is the operator's shim dir (HARBOR_LOCAL_BIN, default ~/.local/bin); --dir BIN any other.
#     The table is core's contracts/shims.tsv plus the shims.tsv of every installed pack (contracts/pack.md): `harbor pack
#     install` copies a pack's to <config dir>/shims.d/<repo-id>.tsv, and each row links to the pack's installed bin/ file.
#     --live reads ~/.claude/shims.d; a --dir run reads HARBOR_PACK_SHIMS_DIR, and with neither it links core's table alone.
#     A dry run exits 1 only when --apply would refuse: a regular file where a shim goes.
#
# WHY. Nineteen symlinks point into harbor and nothing created them — each
# script's help text prints the `ln -sfn` a reader is meant to type, so the set
# on any box is whatever someone typed. A symlink target is a LITERAL: no
# variable, no expansion, nothing the harbor#619 move can rewrite. So the move
# breaks all nineteen at once, and re-creating them by hand needs a list that
# did not exist until this file.
#
# READ-ONLY BY DEFAULT, and --apply is narrow on purpose:
#   - it writes only names that are IN the table;
#   - it refuses to replace a REGULAR FILE, always, even with --apply. A shim
#     name colliding with a real program is a collision to be told about, not
#     one to resolve by deleting the other thing;
#   - it reports symlinks it does not manage rather than touching or ignoring
#     them. A link into a workload repo moves with the rest, and is not
#     harbor's to install — silence about it is how it gets missed.
#
# THE TABLE IS THE ONE OWNER of every link in it (harbor#708): runtime-install no
# longer links idea, memory, gcx or gcloud. A link this run repoints is backed up,
# as a link, into backups/shim-install/<TS>/ beside the run's log.
# NO .harbor-manifest ROWS (install standard §3): it installs no file in a config dir, only links on
# PATH that point at the checkout; deploy's snapshot records that directory instead (harbor#770).
set -eu
SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init shim-install
ROOT="${HARBOR_ROOT:-$(CDPATH='' cd -- "$SRC/.." && pwd)}"
TABLE="${HARBOR_SHIMS_TABLE:-$ROOT/contracts/shims.tsv}"
# The live dir is the operator's PATH dir, from the roots table; no variable must agree with a --dir.
IL_LIVE_DIR="$(sh "$SRC/scope-roots.sh" --get HARBOR_LOCAL_BIN)"
IL_ENV=''
il_parse "$@"
# Backups and the log go to the config dir for the live PATH dir, not into a dir that is on PATH.
if [ "$IL_LIVE" -eq 1 ] && [ -d "${HOME:-}/.claude" ]; then IL_STATE="$HOME/.claude"; fi
il_target
BIN="$IL_TARGET"
if [ "$IL_APPLY" -eq 1 ] && [ -z "$IL_BK" ]; then  # a --dir that does not exist yet: made, then logged
  mkdir -p "$IL_STATE" && IL_STATE="$(CDPATH='' cd -P -- "$IL_STATE" && pwd -P)" && log_file "$IL_STATE"
  IL_BK="$LOG_DIR"; [ "$IL_LIVE" -eq 1 ] || BIN="$IL_STATE"
fi
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $BIN"; else log_head "plan for $BIN (dry run: nothing is written)"; fi
if [ ! -f "$TABLE" ]; then
  log_fail "no shim table at $TABLE"
  log_nofix "contracts/shims.tsv (HARBOR_SHIMS_TABLE overrides it)"
  log_end; exit 1
fi

BAD=0
W="${TMPDIR:-/tmp}"; W="${W%/}/harbor-shims.$$"
trap 'rm -f "$W".*' EXIT INT TERM
sed 's/#.*//' "$TABLE" | awk -F'\t' 'NF>=3 && $1!="name" && $1!=""' > "$W.rows"
: > "$W.managed"

# The installed packs' shims (harbor#1149). A pack row is name TAB bin/<file>, linked to <config dir>/<file>, where the config dir
# is the one that holds shims.d. Written into the same row shape as core's, with the root column `=` (the third is already the
# absolute target). A name core owns, or another pack listed first, is a finding and its row is skipped.
PSD="${HARBOR_PACK_SHIMS_DIR:-}"
if [ -z "$PSD" ] && [ "$IL_LIVE" -eq 1 ]; then PSD="${HOME:-}/.claude/shims.d"; fi
PCFG=''
if [ -n "$PSD" ] && [ -d "$PSD" ]; then
  PCFG="$(CDPATH='' cd -- "$PSD/.." && pwd -P)"
  for _pf in "$PSD"/*.tsv; do
    [ -f "$_pf" ] || continue
    _pid="${_pf##*/}"; _pid="${_pid%.tsv}"
    sed 's/#.*//' "$_pf" | tr -d '\r' | awk -F'\t' -v cfg="$PCFG" -v id="$_pid" -v rows="$W.rows" '
      BEGIN { while ((getline l < rows) > 0) { split(l, c, "\t"); seen[c[1]] = (c[2] == "=" ? "another pack" : "core") } }
      NF == 2 && $1 != "name" && $1 != "" && $2 ~ /^bin\/[A-Za-z0-9._-]+$/ {
        if ($1 in seen) { printf "%s\t%s\t%s\n", id, $1, seen[$1] > "/dev/stderr"; next }
        seen[$1] = id; printf "%s\t=\t%s/%s\n", $1, cfg, $2 }' >> "$W.rows" 2> "$W.clash" || :
    while IFS="$(printf '\t')" read -r _a _b _c; do
      [ -z "$_a" ] || { BAD=1; log_fail "pack $_a: $_b is already in the table ($_c), so its row is skipped"; log_nofix "one of the two shims.tsv files names it: drop the row from the pack's, or the pack"; }
    done < "$W.clash"
  done
fi

# One line per row; a redirect, never a pipe, so the counts reach the summary.
while IFS="$(printf '\t')" read -r NAME VAR REL; do
  printf '%s\n' "$NAME" >> "$W.managed"
  if [ "$VAR" = = ]; then WANT="$REL"; else WANT="$(sh "$SRC/scope-roots.sh" --get "$VAR")/$REL"; fi
  LINK="$BIN/$NAME"
  if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
    BAD=1
    log_fail "$NAME: $LINK is a regular file, not a shim — not touched"
    log_fix "mv '$LINK' '$LINK.not-a-shim' && $(il_cmd --apply)"
    continue
  fi
  HAVE="$(readlink "$LINK" 2>/dev/null || true)"
  if [ "$HAVE" = "$WANT" ]; then
    log_ok "$NAME -> $WANT"
    continue
  fi
  if [ "$IL_APPLY" -eq 0 ]; then
    if [ -z "$HAVE" ]; then log_note "$NAME: would link -> $WANT"; else log_note "$NAME: would repoint $HAVE -> $WANT"; fi
    continue
  fi
  # The TARGET is not required to exist yet. During the move the shims are
  # rewritten before every repo has landed, and refusing a dangling link here
  # would mean running this twice and remembering to.
  il_backup "$LINK" || continue
  mkdir -p "$BIN"
  if ! ln -sfn "$WANT" "$LINK"; then
    log_fail "$NAME: could not link $LINK -> $WANT"
    log_nofix "the ln error above"
    continue
  fi
  if [ -z "$HAVE" ]; then log_ok "$NAME: linked -> $WANT"; else log_ok "$NAME: repointed $HAVE -> $WANT (the old link is in $IL_BK)"; fi
done < "$W.rows"

# Symlinks into a repo the move relocates that this table does not manage. The repo ids are the registry's
# (scope-roots.sh --repos, harbor#1273); with none it is the roots table's, and an unreadable registry skips the scan.
if _ids="$(sh "$SRC/scope-roots.sh" --repos 2>/dev/null)"; then printf '%s\n' "$_ids" | cut -f1 > "$W.repos"; else
  log_warn "the repo registry did not read (sh bin/scope-roots.sh --repos), so links into a repo were not scanned"; : > "$W.repos"
fi
find "$BIN" -maxdepth 1 -type l 2>/dev/null | sort > "$W.links"
while IFS= read -r L; do
  N="$(basename "$L")"
  grep -qx "$N" "$W.managed" 2>/dev/null && continue
  T="$(readlink "$L" 2>/dev/null || true)"
  # A link into the config dir's bin/ that no installed pack lists: the pack was removed, or its row was. Nothing else puts one there.
  if [ -n "$PCFG" ]; then
    case "$T" in
      "$PCFG"/bin/*) log_warn "$N -> $T is a pack's command and no installed pack's shims.tsv lists it"; log_nofix "reinstall the pack (harbor pack install), or remove the link"; continue ;;
    esac
  fi
  case "$T" in
    "$HOME"/*) ;;
    *) continue ;;
  esac
  _rel="${T#"$HOME"/}"; grep -qxF -- "${_rel%%/*}" "$W.repos" || continue
  log_warn "$N -> $T is unmanaged: it moves with harbor#619, and nothing installs it"
  log_nofix "harbor#619: give it a row in contracts/shims.tsv, or remove the link"
done < "$W.links"

[ "$IL_APPLY" -eq 1 ] || [ "$BAD" -eq 1 ] || il_apply_next shim
log_end; exit $?
