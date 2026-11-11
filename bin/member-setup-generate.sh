#!/usr/bin/env sh
# member-setup-generate.sh (harbor#1278) — rebuilds every person's setup script, hash and zip at a harbor-core pin.
#   sh member-setup-generate.sh --pin <40-hex> --core <harbor-core checkout> --hub <owner/name> --signers <hub-signers file>
#                               --roster <file> --kit <dir> --out <dir>
#   HARBOR_HUB_CORE_DIR stands in for --core.
# --roster is a file the admin keeps privately, one `user<TAB>login` per line (the person's Linux user, their GitHub login); blank and # lines are skipped.
# --kit is a folder holding the files every person gets unchanged: run-setup.ps1, INSTALL-FOR-CLAUDE.md and CLAUDE.md.
# For each person it runs the PIN's own bin/member-windows.sh --setup, so the script is the code the laptop will install, never today's. It writes
#   <out>/bundles/<user>/setup-<user>.ps1 (+ the kit's files), <out>/bundles/<user>-HASH.txt, <out>/zips/setup-<user>.zip
# The zip holds the kit's files, HASH.txt and the setup script at its root. Send the zip, then the hash in a second message (docs/how-to/adopt.md).
# Exit 0 all built, 1 a person failed or the pin is not in the checkout, 2 usage error or an unreadable input. Nothing is sent anywhere.
set -eu
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
LOG_FD=2; export LOG_FD
. "$HERE/library-log.sh"
log_init member-setup-generate

PIN=''; CORE="${HARBOR_HUB_CORE_DIR:-}"; HUB=''; SIGNERS=''; ROSTER=''; KIT=''; OUT=''
usage() { log_fail "$1"; log_nofix "sh $0 --help"; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pin|--core|--hub|--signers|--roster|--kit|--out)
      [ $# -ge 2 ] || usage "$1 needs a value"
      case "$1" in --pin) PIN="$2" ;; --core) CORE="$2" ;; --hub) HUB="$2" ;; --signers) SIGNERS="$2" ;; --roster) ROSTER="$2" ;; --kit) KIT="$2" ;; --out) OUT="$2" ;; esac
      shift ;;
    -h|--help) awk 'NR<2{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) usage "unknown argument $1" ;;
  esac
  shift
done
case "$PIN" in ''|*[!0123456789abcdef]*) usage "--pin wants a 40-hex harbor-core commit, got '$PIN'" ;; esac
[ "${#PIN}" -eq 40 ] || usage "--pin wants the full 40-character commit, got '$PIN'"
[ -n "$CORE" ] && git -C "$CORE" rev-parse --git-dir >/dev/null 2>&1 || usage "--core wants a harbor-core checkout"
case "$HUB" in */*) ;; *) usage "--hub wants owner/name" ;; esac
[ -f "$SIGNERS" ] || usage "--signers: no file at '$SIGNERS'"
[ -f "$ROSTER" ] || usage "--roster: no file at '$ROSTER'"
[ -n "$OUT" ] || usage "--out wants a folder"
for _f in run-setup.ps1 INSTALL-FOR-CLAUDE.md CLAUDE.md; do [ -f "$KIT/$_f" ] || usage "--kit lacks $_f"; done
command -v zip >/dev/null 2>&1 || usage "zip is not installed"
HASHER=''; for _h in "shasum -a 256" sha256sum; do command -v "${_h%% *}" >/dev/null 2>&1 && { HASHER="$_h"; break; }; done
[ -n "$HASHER" ] || usage "neither shasum nor sha256sum is installed"

git -C "$CORE" fetch -q origin 2>/dev/null || :
git -C "$CORE" cat-file -e "$PIN^{commit}" 2>/dev/null || { log_fail "commit $PIN is not in $CORE"; log_fix "git -C $CORE fetch origin"; exit 1; }
WT="$(mktemp -d "${TMPDIR:-/tmp}/core-pin.XXXXXX")"
trap 'git -C "$CORE" worktree remove --force "$WT" >/dev/null 2>&1 || :; rm -rf "$WT"' EXIT INT TERM
git -C "$CORE" worktree add -q --detach "$WT" "$PIN" || { log_fail "cannot check out $PIN"; log_fix "git -C $CORE worktree prune"; exit 1; }
[ -f "$WT/bin/member-windows.sh" ] || { log_fail "$PIN has no bin/member-windows.sh"; log_nofix "docs/how-to/adopt.md"; exit 1; }

mkdir -p "$OUT/bundles" "$OUT/zips"; BAD=0; N=0; TAB="$(printf '\t')"
while IFS="$TAB" read -r U L _rest || [ -n "${U:-}" ]; do
  case "${U:-}" in ''|'#'*) continue ;; esac
  N=$((N + 1))
  if [ -z "${L:-}" ]; then log_fail "roster line for '$U' has no login"; log_fix "add a tab and the GitHub login to that line of $ROSTER"; BAD=$((BAD + 1)); continue; fi
  D="$OUT/bundles/$U"; rm -rf "$D"; mkdir -p "$D"
  if ! sh "$WT/bin/member-windows.sh" --setup --pin "$PIN" --user "$U" --hub "$HUB" --login "$L" --signers "$SIGNERS" > "$D/setup-$U.ps1" 2>"$D/.err"; then
    log_fail "$U: the pin's member-windows.sh refused: $(tail -n 1 "$D/.err")"; log_nofix "docs/how-to/adopt.md"; rm -rf "$D"; BAD=$((BAD + 1)); continue
  fi
  rm -f "$D/.err"
  cp "$KIT/run-setup.ps1" "$KIT/INSTALL-FOR-CLAUDE.md" "$KIT/CLAUDE.md" "$D/"
  $HASHER "$D/setup-$U.ps1" | cut -d' ' -f1 > "$OUT/bundles/$U-HASH.txt"
  cp "$OUT/bundles/$U-HASH.txt" "$D/HASH.txt"
  rm -f "$OUT/zips/setup-$U.zip"
  (cd "$D" && zip -qX "$OUT/zips/setup-$U.zip" CLAUDE.md HASH.txt INSTALL-FOR-CLAUDE.md run-setup.ps1 "setup-$U.ps1")
  log_ok "$U ($L): $(wc -c < "$D/setup-$U.ps1" | tr -d ' ') bytes, hash $(cut -c1-12 "$OUT/bundles/$U-HASH.txt")"
done < "$ROSTER"
[ "$N" -gt 0 ] || usage "--roster holds no person"
[ "$BAD" -eq 0 ] || { log_fail "$BAD of $N failed"; log_nofix "docs/how-to/adopt.md"; log_end || :; exit 1; }
log_ok "$N built at $(printf %.12s "$PIN") in $OUT"
log_end
