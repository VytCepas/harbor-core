#!/usr/bin/env sh
# access-environment.sh (harbor#561) — the repo-visibility lines of the auto-mode environment block, read from
# the registry of governed repos and a live `gh repo view --json visibility` per repo. A repo whose visibility
# cannot be read is printed as UNKNOWN with the reason: nothing is assumed private or public.
#
#   sh access-environment.sh [--registry FILE] [--gh PATH]            the block, on stdout
#   sh access-environment.sh --check [--settings FILE] [--registry FILE] [--gh PATH] [--controls FILE]
#                                                                      does the live block carry these lines?
#
# THE REGISTRY. By default the governed repos are read through `scope-roots.sh --repos` (harbor-private/repos.tsv, the
# one registry, harbor#966); a box with no repos.tsv falls back to the private layer's projects.tsv
# (`scope-roots.sh --projects`, harbor#1149). --registry FILE
# names a file instead: any TSV whose first two columns are name and path (projects.tsv, or the output of
# `scope-roots.sh --repos`). A row's path is resolved against $HOME (a leading ~/ is expanded) and its `origin` remote
# names the GitHub repo asked about. A row with no checkout, no origin, a non-GitHub origin, or a failed `gh`
# call is UNKNOWN and says why. The render exits 2 when the registry cannot be read; otherwise 0, whatever the
# visibility verdicts. The block is stdout; the log is stderr.
#
# --check READS settings.json (default $CLAUDE_CONFIG_DIR/settings.json, else ~/.claude/settings.json) and never
# writes it. It renders the lines afresh and holds each against the `- <repo> (<owner/name>): <VERDICT>` lines in
# autoMode.environment: a repo the live block lacks or names that the registry no longer has, and a verdict that
# differs, is a finding. A live block with no such line at all is a finding too, and it quotes what the block says
# about visibility instead (today: that every repo is assumed private). A block that has the lines AND still says
# a repo is "assumed private" in a line about visibility is a finding too: the classifier would read two answers for
# one repo (a line that says it is NOT assuming, like the render's own header, is not). A repo gh gave no answer for
# is NOT JUDGED and said so: a failed call is not drift. The control is drift.repo-visibility in
# standards/naming/controls.tsv and its mode is read there, never here. Exit (D-49): 0 green, or findings under
# warn or shadow · 1 findings under block · 2 usage · 3 unchecked: no registry, no settings.json, no jq, no row
# in controls.tsv, or every repo not judged. LINT_REDLOG=<file> appends the id when the check goes red.
# Writing the live block is the deploy's, not this tool's: nothing calls --check on a schedule yet.
set -u

case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$_SRC/.." && pwd)}"
. "$ROOT/bin/library-log.sh"
log_init access-environment
LOG_FD=2
CONTROL_ID="drift.repo-visibility"
REG=""; GH="gh"; ACTION=render; SETTINGS=""; CONTROLS=""

usage_err() { log_fail "$1"; log_fix "${2:-sh bin/access-environment.sh --help}"; log_end || :; exit 2; }
unchecked() { log_fail "$1"; log_fix "$2"; log_end || :; exit 3; }

while [ $# -gt 0 ]; do
  case "$1" in
    --registry) [ $# -ge 2 ] || usage_err "--registry takes a file" "sh bin/access-environment.sh --registry FILE"; REG="$2"; shift 2 ;;
    --gh) [ $# -ge 2 ] || usage_err "--gh takes a path" "sh bin/access-environment.sh --gh PATH"; GH="$2"; shift 2 ;;
    --settings) [ $# -ge 2 ] || usage_err "--settings takes a file" "sh bin/access-environment.sh --check --settings FILE"; SETTINGS="$2"; shift 2 ;;
    --controls) [ $# -ge 2 ] || usage_err "--controls takes a file" "sh bin/access-environment.sh --check --controls FILE"; CONTROLS="$2"; shift 2 ;;
    --check) ACTION=check; shift ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done

T="$(mktemp -d "${TMPDIR:-/tmp}/access-environment.XXXXXX")" || usage_err "cannot make a temp dir" "ls -ld \"\${TMPDIR:-/tmp}\""
trap 'rm -rf "$T"' EXIT INT TERM HUP

# load_registry → $T/reg: one `<name> TAB <path>` row per governed repo. A bad registry is the caller's to
# name: the render says 2, the check says 3, so the failure is returned and never decided here.
REGWHY=""
load_registry() {
  if [ -n "$REG" ]; then
    [ -r "$REG" ] || { REGWHY="registry not readable: $REG"; return 1; }
    cp "$REG" "$T/reg"; REGFROM="$REG"; return 0
  fi
  _priv="$(sh "$ROOT/bin/scope-roots.sh" --private 2>/dev/null)" || _priv=""
  if [ -n "$_priv" ] && [ -f "$_priv/repos.tsv" ]; then
    # A registry that exists and is invalid refuses the whole read: falling back past it would render a
    # different set of repos than the one the box registered.
    sh "$ROOT/bin/scope-roots.sh" --repos > "$T/reg" 2> "$T/reg.err" || { REGWHY="scope-roots.sh --repos refused $_priv/repos.tsv: $(tr '\n' ' ' < "$T/reg.err")"; return 1; }
    REGFROM="scope-roots.sh --repos"; return 0
  fi
  # The fallback is the private layer's projects.tsv (harbor#1149): core ships none, and scope-roots.sh is its one resolver.
  _proj="$(sh "$ROOT/bin/scope-roots.sh" --projects 2>/dev/null)" || _proj=""
  [ -n "$_proj" ] && [ -r "$_proj" ] || { REGWHY="no repos.tsv and no projects.tsv in the private layer: no registry of governed repos"; return 1; }
  cp "$_proj" "$T/reg"; REGFROM="${_proj#"${_proj%/*/*/*}"/}"; return 0
}

# render_lines <registry> → one visibility line per registry row on stdout; comments and blank lines skipped.
# Read on fd 3 so a gh call that reads stdin cannot eat the registry.
render_lines() {
  exec 3< "$1"
  while IFS= read -r _row <&3; do
    case "$_row" in ''|'#'*) continue ;; esac
    _name="$(printf '%s\n' "$_row" | cut -f1)"
    _path="$(printf '%s\n' "$_row" | cut -f2)"
    [ -n "$_name" ] || continue
    case "$_path" in "~/"*) _path="$HOME/${_path#\~/}" ;; esac

    if [ ! -d "$_path" ]; then
      printf -- '- %s: UNKNOWN (no checkout at its registry path)\n' "$_name"; continue
    fi
    _url="$(git -C "$_path" remote get-url origin 2>/dev/null)" || _url=""
    if [ -z "$_url" ]; then
      printf -- '- %s: UNKNOWN (no origin remote; not one GitHub repo)\n' "$_name"; continue
    fi
    _slug="$(printf '%s\n' "$_url" | sed -n -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\2#p' | sed -E 's/\.git$//')"
    if [ -z "$_slug" ]; then
      printf -- '- %s: UNKNOWN (origin is not a GitHub repo)\n' "$_name"; continue
    fi
    _vis="$("$GH" repo view "$_slug" --json visibility --jq .visibility 2>/dev/null </dev/null)" || _vis=""
    case "$_vis" in
      PUBLIC|PRIVATE|INTERNAL) printf -- '- %s (%s): %s\n' "$_name" "$_slug" "$_vis" ;;
      *) printf -- '- %s (%s): UNKNOWN (gh repo view gave no visibility)\n' "$_name" "$_slug" ;;
    esac
  done
  exec 3<&-
}

if [ "$ACTION" = render ]; then
  load_registry || { log_fail "$REGWHY"; log_fix "sh bin/access-environment.sh --registry FILE"; log_end || :; exit 2; }
  log_note "registry: $REGFROM"
  printf '%s\n' 'Repository visibility, from gh repo view --json visibility at generation. A repo marked UNKNOWN is not assumed private or public:'
  render_lines "$T/reg"
  exit 0
fi

# ── --check ───────────────────────────────────────────────────────────────────────────────────────
[ -n "$CONTROLS" ] || CONTROLS="$ROOT/standards/naming/controls.tsv"
[ -n "$SETTINGS" ] || SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

[ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the mode of $CONTROL_ID is unknown" "ls $ROOT/standards/naming"
MODE="$(awk -F'\t' -v id="$CONTROL_ID" '/^#/ { next } $1 == id { m = $2; if (m == "advisory" || m == "inform") m = "warn"; print m; exit }' "$CONTROLS")"
[ -n "$MODE" ] || unchecked "no controls.tsv row for $CONTROL_ID, so its mode is unknown" "add the row to $CONTROLS"
command -v jq >/dev/null 2>&1 || unchecked "jq is absent, so settings.json cannot be read" "$(pkg_hint jq)"
[ -r "$SETTINGS" ] || unchecked "no settings.json at $SETTINGS: there is no live block to hold the lines against" "sh bin/access-environment.sh --check --settings FILE"
load_registry || unchecked "$REGWHY" "sh bin/access-environment.sh --check --registry FILE"
NREG="$(awk -F'\t' '/^#/ || NF == 0 || $1 == "" { next } { n++ } END { print n + 0 }' "$T/reg")"
[ "$NREG" -gt 0 ] || unchecked "the registry ($REGFROM) names no governed repo, so there is nothing to render" "sh bin/access-environment.sh --registry FILE"

# The live block, one text line per line (an element may hold several), read-only.
jq -r '(.autoMode.environment // []) | if type == "array" then .[] elif type == "string" then . else empty end | tostring' "$SETTINGS" > "$T/live.raw" 2> "$T/jq.err" \
  || unchecked "settings.json is not readable as JSON ($(head -n 1 "$T/jq.err")): $SETTINGS" "jq . $SETTINGS"

# The visibility lines the generator writes, wherever the block carries them: `- <name>[ (<owner/repo>)]: <VERDICT>…`.
# Brackets, not backslashes, for the literal parentheses: awk reads an escape in a -v value differently per awk.
VISRE='^[[:space:]]*- [A-Za-z0-9._-]+( [(][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+[)])?: (PUBLIC|PRIVATE|INTERNAL|UNKNOWN)( .*)?$'
awk -v re="$VISRE" '$0 ~ re' "$T/live.raw" \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' > "$T/live"
NLIVE="$(wc -l < "$T/live" | tr -d ' ')"
: > "$T/findings"; : > "$T/notjudged"; JUDGED=0; SKIPPED=0

if [ "$NLIVE" = 0 ]; then
  # The block carries none of the generated lines, so there is nothing for a render to be held against: say what
  # it carries about visibility instead, and spend no gh call to say it.
  _says="$(grep -i 'repository visibility' "$T/live.raw" | head -n 1 | cut -c1-200)"
  printf 'absent\tthe live block in %s carries no repo-visibility line, so %s governed repos are undescribed to the classifier%s\n' "$SETTINGS" "$NREG" \
    "${_says:+; it says: $_says}" > "$T/findings"
else
  render_lines "$T/reg" > "$T/fresh"
  # judge: `<kind> TAB <message>` per finding or non-judgement, then `J TAB <judged> TAB <not judged>`.
  awk -v fresh="$T/fresh" -v live="$T/live" '
    function nm(l,   t) { t = substr(l, 3); sub(/[ :].*$/, "", t); return t }
    BEGIN {
      while ((getline l < fresh) > 0) { n = nm(l); F[n] = l; order[++no] = n }
      while ((getline l < live) > 0) { n = nm(l); if (n in L) twice[n] = 1; L[n] = l; lorder[++nl] = n }
      for (i = 1; i <= no; i++) {
        n = order[i]
        if (!(n in L)) { printf "missing\tthe live block has no line for %s; a fresh render says: %s\n", n, F[n]; continue }
        if (n in twice) printf "duplicate\tthe live block names %s more than once\n", n
        if (F[n] ~ /UNKNOWN [(]gh repo view gave no visibility[)]$/) { skipped++; printf "notjudged\t%s: gh gave no answer now, so the live line (%s) is not judged\n", n, L[n]; continue }
        judged++
        if (F[n] != L[n]) printf "differs\t%s: the live block says \"%s\" but a fresh render says \"%s\"\n", n, L[n], F[n]
      }
      for (i = 1; i <= nl; i++) { n = lorder[i]; if (!(n in F)) printf "stale\tthe live block names %s (\"%s\"), which the registry no longer has\n", n, L[n] }
      printf "J\t%d\t%d\n", judged + 0, skipped + 0
    }' > "$T/judge"
  awk -F'\t' '$1 != "J" && $1 != "notjudged"' "$T/judge" > "$T/findings"
  # A line about visibility that still assumes private. The generated lines are skipped, and a negated "assum…"
  # (the render's own header says UNKNOWN is "not assumed private or public") is dropped before the test.
  awk -v re="$VISRE" '
    $0 ~ re { next }
    { l = tolower($0); gsub(/(not|never|n[^a-z ]t) +assum[a-z]*/, "", l) }
    l ~ /visibility/ && l ~ /assum[a-z]* .*private/ { print }' "$T/live.raw" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' | cut -c1-200 > "$T/contra"
  while IFS= read -r _c; do
    printf 'contradiction\tthe live block still says "%s" beside its %s generated visibility lines, so the classifier reads two answers for the same repos\n' "$_c" "$NLIVE" >> "$T/findings"
  done < "$T/contra"
  awk -F'\t' '$1 == "notjudged" { print $2 }' "$T/judge" > "$T/notjudged"
  JUDGED="$(awk -F'\t' '$1 == "J" { print $2 }' "$T/judge")"; SKIPPED="$(awk -F'\t' '$1 == "J" { print $3 }' "$T/judge")"
  # Every repo gh failed on and nothing else wrong is a check that looked at nothing, never a green one.
  if [ "$JUDGED" = 0 ] && [ ! -s "$T/findings" ]; then
    unchecked "gh gave no answer for any of the $NREG repos, so no live line could be judged" "gh auth status"
  fi
fi

if [ -s "$T/findings" ]; then
  [ -z "${LINT_REDLOG:-}" ] || printf '%s\n' "$CONTROL_ID" >> "$LINT_REDLOG" 2>/dev/null || :
  # shadow records and prints nothing (D-29); warn prints; block fails the run.
  [ "$MODE" != shadow ] || exit 0
  log_head "check $CONTROL_ID ($MODE)"
  while IFS= read -r _l; do log_note "not judged: $_l"; done < "$T/notjudged"
  _fix="sh bin/access-environment.sh prints the lines the block should carry; this check only reads settings.json (harbor#561)"
  if [ "$MODE" = block ]; then
    while IFS="$(printf '\t')" read -r _k _m; do log_fail "$CONTROL_ID: $_m"; log_fix "$_fix"; done < "$T/findings"
    log_end || :; exit 1
  fi
  while IFS="$(printf '\t')" read -r _k _m; do log_warn "$CONTROL_ID: $_m"; done < "$T/findings"
  log_fix "$_fix"
  log_end || :; exit 0
fi

log_head "check $CONTROL_ID ($MODE)"
while IFS= read -r _l; do log_note "not judged: $_l"; done < "$T/notjudged"
log_ok "the live block's $NLIVE visibility lines match a fresh render of $NREG repos ($SKIPPED not judged), from $REGFROM"
log_end || :
exit 0
