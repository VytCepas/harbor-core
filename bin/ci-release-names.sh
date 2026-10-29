#!/usr/bin/env sh
# ci-release-names.sh (harbor#957, harbor#986) — every published release of every governed repo, read from GitHub
# and held to the release rule: the tag is v<semver> (name.release-tag, judged by `lint-name.sh --check`), the
# release title is the tag, and a repo that has released carries a Keep a Changelog CHANGELOG.md on its default
# branch with a `## [<version>]` heading for each v<semver> release. Read only: it never edits a release or a file.
#
#   sh bin/ci-release-names.sh [--registry FILE] [--repo OWNER/NAME]... [--gh PATH] [--controls FILE]
#
# THE REPOS. --repo names one GitHub repo and may repeat; without it the governed repos are read through
# `scope-roots.sh --repos` (else the private layer's projects.tsv), or from --registry FILE (first two columns
# name and path), and each checkout's `origin` names the GitHub repo. A row with no checkout, no origin, a
# non-GitHub origin, or a gh call that fails is NOT JUDGED and says why: a repo it could not read is never green.
# A draft release is not judged: it has not been released.
#
# The control is ci.release-names in standards/naming/controls.tsv and its mode is read there, never here.
# Output is stamped [check:ci.release-names]. Exit (D-29, D-49): 0 green, or findings under warn or shadow ·
# 1 findings under block · 2 usage · 3 unchecked: no registry, no controls row, no jq, or no repo judged.
# LINT_REDLOG=<file> appends the id when the check goes red. Nothing runs it on a schedule.
set -u

case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$_SRC/.." && pwd)}"
. "$ROOT/bin/library-log.sh"
log_init ci-release-names
LOG_FD=2
CONTROL_ID="ci.release-names"
REG=""; GH="gh"; CONTROLS=""; REPOS=""

usage_err() { log_fail "$1"; log_fix "${2:-sh bin/ci-release-names.sh --help}"; log_end || :; exit 2; }
unchecked() { log_fail "$1"; log_fix "$2"; log_end || :; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --registry) [ $# -ge 2 ] || usage_err "--registry takes a file" "sh bin/ci-release-names.sh --registry FILE"; REG="$2"; shift 2 ;;
    --repo) [ $# -ge 2 ] || usage_err "--repo takes OWNER/NAME" "sh bin/ci-release-names.sh --repo VytCepas/harbor"
            case "$2" in */*) ;; *) usage_err "--repo takes OWNER/NAME, not: $2" "sh bin/ci-release-names.sh --repo VytCepas/harbor" ;; esac
            REPOS="$REPOS$2
"; shift 2 ;;
    --gh) [ $# -ge 2 ] || usage_err "--gh takes a path" "sh bin/ci-release-names.sh --gh PATH"; GH="$2"; shift 2 ;;
    --controls) [ $# -ge 2 ] || usage_err "--controls takes a file" "sh bin/ci-release-names.sh --controls FILE"; CONTROLS="$2"; shift 2 ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-release-names.XXXXXX")" || usage_err "cannot make a temp dir" "ls -ld \"\${TMPDIR:-/tmp}\""
trap 'rm -rf "$T"' EXIT INT TERM HUP

[ -n "$CONTROLS" ] || CONTROLS="$ROOT/standards/naming/controls.tsv"
[ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the mode of $CONTROL_ID is unknown" "ls $ROOT/standards/naming"
MODE="$(awk -F'\t' -v id="$CONTROL_ID" '/^#/ { next } $1 == id { m = $2; if (m == "advisory" || m == "inform") m = "warn"; print m; exit }' "$CONTROLS")"
[ -n "$MODE" ] || unchecked "no controls.tsv row for $CONTROL_ID, so its mode is unknown" "add the row to $CONTROLS"
command -v jq >/dev/null 2>&1 || unchecked "jq is absent, so gh's answers cannot be read" "$(pkg_hint jq)"

# → $T/targets: `<name> TAB <slug or -> TAB <why not judged>` per repo.
if [ -n "$REPOS" ]; then
  printf '%s' "$REPOS" | awk 'NF { print $1 "\t" $1 "\t" }' > "$T/targets"; FROM="--repo"
else
  if [ -n "$REG" ]; then
    [ -r "$REG" ] || unchecked "registry not readable: $REG" "sh bin/ci-release-names.sh --registry FILE"
    cp "$REG" "$T/reg"; FROM="$REG"
  elif sh "$ROOT/bin/scope-roots.sh" --repos > "$T/reg" 2>/dev/null && [ -s "$T/reg" ]; then FROM="scope-roots.sh --repos"
  else
    _proj="$(sh "$ROOT/bin/scope-roots.sh" --projects 2>/dev/null)" || _proj=""
    [ -n "$_proj" ] && [ -r "$_proj" ] || unchecked "no repos.tsv and no projects.tsv in the private layer: no registry of governed repos" "sh bin/ci-release-names.sh --repo OWNER/NAME"
    cp "$_proj" "$T/reg"; FROM="projects.tsv"
  fi
  exec 3< "$T/reg"
  while IFS= read -r _row <&3; do
    case "$_row" in ''|'#'*) continue ;; esac
    _name="$(printf '%s\n' "$_row" | cut -f1)"; _path="$(printf '%s\n' "$_row" | cut -f2)"
    [ -n "$_name" ] || continue
    case "$_path" in "~/"*) _path="$HOME/${_path#\~/}" ;; esac
    if [ ! -d "$_path" ]; then printf '%s\t-\tno checkout at its registry path\n' "$_name"; continue; fi
    _url="$(git -C "$_path" remote get-url origin 2>/dev/null)" || _url=""
    _slug="$(printf '%s\n' "$_url" | sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\2#p' | sed -E 's/\.git$//')"
    if [ -z "$_slug" ]; then printf '%s\t-\tno GitHub origin\n' "$_name"; continue; fi
    printf '%s\t%s\t\n' "$_name" "$_slug"
  done > "$T/targets"
  exec 3<&-
fi
NREPO="$(grep -c . "$T/targets" | tr -d ' ')"
[ "$NREPO" -gt 0 ] || unchecked "the registry ($FROM) names no repo, so there is nothing to read" "sh bin/ci-release-names.sh --repo OWNER/NAME"

: > "$T/findings"; : > "$T/notjudged"; JUDGED=0; NREL=0
exec 4< "$T/targets"
while IFS="$(printf '\t')" read -r _name _slug _why <&4; do
  if [ "$_slug" = - ]; then printf '%s: %s\n' "$_name" "$_why" >> "$T/notjudged"; continue; fi
  # `tag TAB title` per published release; a failed call is not judged, never an empty list.
  if ! "$GH" release list -R "$_slug" --limit 1000 --json tagName,name,isDraft > "$T/rel.json" 2> "$T/rel.err" </dev/null \
     || ! jq -r '.[] | select(.isDraft | not) | [.tagName, (.name // "")] | @tsv' "$T/rel.json" > "$T/rel" 2>/dev/null; then
    printf '%s (%s): gh release list failed: %s\n' "$_name" "$_slug" "$(head -n 1 "$T/rel.err" | cut -c1-160)" >> "$T/notjudged"; continue
  fi
  JUDGED=$((JUDGED + 1))
  [ -s "$T/rel" ] || continue
  : > "$T/versions"
  while IFS="$(printf '\t')" read -r _tag _title; do
    NREL=$((NREL + 1))
    if sh "$ROOT/bin/lint-name.sh" --check release-tag "$_tag" >/dev/null 2>&1; then
      printf '%s\n' "${_tag#v}" >> "$T/versions"
    else
      printf '%s (%s): release tag %s is not v<major>.<minor>.<patch> (name.release-tag)\n' "$_name" "$_slug" "$_tag" >> "$T/findings"
    fi
    # An empty title is rendered as the tag by GitHub, so it is the tag.
    [ -z "$_title" ] || [ "$_title" = "$_tag" ] \
      || printf '%s (%s): release %s is titled "%s"; a release title is its tag\n' "$_name" "$_slug" "$_tag" "$_title" >> "$T/findings"
  done < "$T/rel"
  # Keep a Changelog: the default branch's CHANGELOG.md, one `## [<version>]` heading per v<semver> release.
  if "$GH" api -H 'Accept: application/vnd.github.raw' "repos/$_slug/contents/CHANGELOG.md" > "$T/cl" 2> "$T/cl.err" </dev/null; then
    while IFS= read -r _v; do
      awk -v v="$_v" 'index($0, "## [" v "]") == 1 { f = 1; exit } END { exit !f }' "$T/cl" \
        || printf '%s (%s): CHANGELOG.md has no "## [%s]" heading for release v%s (Keep a Changelog)\n' "$_name" "$_slug" "$_v" "$_v" >> "$T/findings"
    done < "$T/versions"
  elif grep -q 'HTTP 404' "$T/cl.err"; then
    printf '%s (%s): %s release(s) and no CHANGELOG.md on the default branch (Keep a Changelog)\n' "$_name" "$_slug" "$(grep -c . "$T/rel" | tr -d ' ')" >> "$T/findings"
  else
    printf '%s (%s): CHANGELOG.md could not be read: %s\n' "$_name" "$_slug" "$(head -n 1 "$T/cl.err" | cut -c1-160)" >> "$T/notjudged"
  fi
done
exec 4<&-

if [ "$JUDGED" = 0 ] && [ ! -s "$T/findings" ]; then
  while IFS= read -r _l; do log_note "not judged: $_l"; done < "$T/notjudged"
  unchecked "[check:$CONTROL_ID] no release list could be read for any of the $NREPO repos, so nothing was judged" "gh auth status"
fi

if [ -s "$T/findings" ]; then
  [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$CONTROL_ID" >> "$LINT_REDLOG" 2>/dev/null || :
  # shadow records and prints nothing (D-29); warn prints; block fails the run.
  [ "$MODE" != shadow ] || exit 0
  log_head "[check:$CONTROL_ID] ($MODE)"
  while IFS= read -r _l; do log_note "not judged: $_l"; done < "$T/notjudged"
  _fix="the repo's release is edited by a person: gh release edit <tag> -R <repo> --title <tag>, and a CHANGELOG.md in https://keepachangelog.com/en/1.1.0/ form (harbor#986)"
  if [ "$MODE" = block ]; then
    while IFS= read -r _m; do log_fail "$_m"; log_fix "$_fix"; done < "$T/findings"
    log_end || :; exit 1
  fi
  while IFS= read -r _m; do log_warn "$_m"; done < "$T/findings"
  log_fix "$_fix"
  log_end || :; exit 0
fi

log_head "[check:$CONTROL_ID] ($MODE)"
while IFS= read -r _l; do log_note "not judged: $_l"; done < "$T/notjudged"
log_ok "$NREL release(s) across $JUDGED of $NREPO repos follow the release rule, from $FROM"
log_end || :
exit 0
