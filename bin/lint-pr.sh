#!/usr/bin/env sh
# lint-pr.sh (harbor#978, D-21): a PR's title, body and branch against the git naming standard.
#
#   sh lint-pr.sh --title <t> --body-file <f|-> --branch <b>     any one, or all three
#
# The title is judged as a commit subject and the branch as a branch, both by `lint-name.sh --check`
# (surfaces commit and branch). The body must carry the six labelled lines, a #<n> issue reference and
# no AI attribution (the pattern is hooks/commit-msg's, the one lint C2 reads too).
# Each finding prints WARN with its rule id. A rule whose controls.tsv mode is warn never fails the run:
# exit 1 only for a block rule, 2 on a usage error, 0 otherwise.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/library-log.sh"
log_init lint-pr
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT
CONTROLS="$ROOT/standards/naming/controls.tsv"

usage() { awk 'NR < 2 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "$0"; }
die() { echo "lint-pr: $1" >&2; exit 2; }

TITLE=''; HAVE_T=0; BODY=''; HAVE_B=0; BRANCH=''; HAVE_R=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --title) [ "$#" -ge 2 ] || die "--title wants a value"; TITLE="$2"; HAVE_T=1; shift ;;
    --body-file) [ "$#" -ge 2 ] || die "--body-file wants a file or -"; BODY="$2"; HAVE_B=1; shift ;;
    --branch) [ "$#" -ge 2 ] || die "--branch wants a value"; BRANCH="$2"; HAVE_R=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
  shift
done
[ $((HAVE_T + HAVE_B + HAVE_R)) -gt 0 ] || die "nothing to judge: give --title, --body-file or --branch"
if [ "$HAVE_B" -eq 1 ]; then
  if [ "$BODY" = - ]; then cat > "$T/body"; else [ -f "$BODY" ] || die "no body file at $BODY"; cp "$BODY" "$T/body"; fi
fi
[ -f "$CONTROLS" ] || die "no standards/naming/controls.tsv under $ROOT"

# A rule's mode is controls.tsv's, never written here: block fails the run, shadow is silent, anything else warns.
mode_of() { awk -F'\t' -v id="$1" '$1 == id { print $2; found = 1; exit } END { if (!found) print "warn" }' "$CONTROLS"; }
BLOCKED=0
finding() { # <rule> <message>
  case "$(mode_of "$1")" in
    block) log_fail "[$1] $2"; log_fix "correct the PR title, body or branch: $1 is a block rule (standards/naming/controls.tsv)"; BLOCKED=1 ;;
    shadow) : ;;
    *) log_warn "[$1] $2" ;;
  esac
}
# lint-name's WARN and FAIL lines carry "[rule] subject — message"; re-emit each under this tool's own mode lookup.
surface() { # <surface> <name>
  sh "$ROOT/bin/lint-name.sh" --check "$1" "$2" < /dev/null > "$T/ln" 2>&1 || :
  awk '/^  (WARN|FAIL): \[[a-z0-9.-]+\] / { l = $0; sub(/^  (WARN|FAIL): \[/, "", l); r = l; sub(/\].*$/, "", r); sub(/^[^]]*\] /, "", l); print r " " l }' "$T/ln" > "$T/found"
  while IFS= read -r _l; do finding "${_l%% *}" "${_l#* }"; done < "$T/found"
}

log_head "pr"
[ "$HAVE_T" -eq 0 ] || surface commit "$TITLE"
[ "$HAVE_R" -eq 0 ] || surface branch "$BRANCH"
if [ "$HAVE_B" -eq 1 ]; then
  for _lab in What Touches Breaks Tested BPN Merge; do
    grep -qE "^\*\*$_lab:\*\* ." "$T/body" || finding lint.pr-body-shape "the body has no \`**$_lab:** …\` line (six labelled lines: What, Touches, Breaks, Tested, BPN, Merge)"
  done
  grep -qE '#[0-9]+' "$T/body" || finding lint.pr-issue-link "the body references no issue: add #<n> or <repo>#<n>"
  # The pattern is read out of hooks/commit-msg, as lint C2 does; no second copy lives here.
  _ere="$(sed -n "s/^HARBOR_ATTRIBUTION_ERE='\(.*\)'$/\1/p" "$ROOT/hooks/commit-msg" 2>/dev/null | head -1)"
  if [ -z "$_ere" ]; then die "hooks/commit-msg defines no HARBOR_ATTRIBUTION_ERE: the attribution rule has no pattern"
  elif grep -vE '^[[:space:]]*#' "$T/body" | grep -qiE "$_ere"; then
    finding lint.pr-no-ai-attribution "the body carries an AI attribution line (hooks/commit-msg HARBOR_ATTRIBUTION_ERE)"
  fi
fi
log_end || :
[ "$BLOCKED" -eq 0 ]
