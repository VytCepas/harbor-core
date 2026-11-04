#!/usr/bin/env sh
# scope-repo.sh (harbor#1430, #1423 T18.7; `harbor repo`) - one command creates or adopts a repo, and audits it.
#
#   harbor repo new <name> --kind <repo-kind> [options]     scaffold a new repo, register it everywhere, audit it
#   harbor repo adopt <path> [--kind <repo-kind>] [options] the same for a checkout that exists (its directory name is the id)
#   harbor repo list                                        where each repo is known: registry, projects.tsv, yard marker, fleet
#   harbor repo audit <name>                                re-run the checks a new repo passes
#   options: --path <rel to PORT_ROOT> --covers <text> --domain <term> --owner <name> --topology <t> --interaction <i>
#            --remote <url> --slug <owner/name> --github --dry-run
#
# THE STEPS, in order (STEPS below; each prints `step <id>: ok|warn|FAIL`, and tests/scope/repo/repo.test.sh holds one assertion per step,
# so a step removed from this list turns that suite red):
#   scaffold   yard's scaffolder (`harbor yard new`), never reimplemented; git init when the checkout has no .git
#   registry   the row in the private layer's repos.tsv (#966); an id already there with another path is refused
#   projects   the box tier's projects.tsv, written from the registry when it is generated, else the one row appended
#   route      the memory route (memory-route.sh, applied): sessions in the repo load the store
#   rules      context-rules/<name>/ in the private layer, for a repo the project registry names
#   labels     the label sync (#1427), as a plan; --github applies it, the one step that writes to GitHub
#   versions   the repo's own vendored naming lint (the versions and seams checks of #1425, #1426)
#   fleet      register with fleet (`harbor fleet register`) and audit it (`harbor fleet audit <name>`)
# Then the audit: lint IJ2, IJ3, IJ6, the four sources agreeing, the kit carried, labels, versions, fleet's audit.
# Exit 0 every step and check green, 1 a step failed or a check is red, 2 usage, 3 a check could not look.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$SRC/library-log.sh"; log_init scope-repo
TAB="$(printf '\t')"

STEPS="scaffold registry projects route rules labels versions fleet"
CHECKS="ij2 ij3 ij6 sources kit labels versions fleet"

die() { log_fail "$1"; log_fix "${2:-sh $SRC/scope-repo.sh --help}"; log_end || :; exit 2; }
usage() { awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SRC/scope-repo.sh"; }
SR() { sh "$SRC/scope-roots.sh" "$@"; }

SUB="${1:-}"; [ $# -eq 0 ] || shift
case "$SUB" in
  -h|--help|help|'') usage; [ -n "$SUB" ] && exit 0; exit 2 ;;
  new|adopt|list|audit) ;;
  *) die "unknown verb '$SUB' (new, adopt, list, audit)" ;;
esac

ARG=''; KIND=''; RELPATH=''; COVERS='-'; DOMAIN='-'; OWNER='-'; TOPO='-'; INTER='-'; REMOTE='-'; SLUG=''; GITHUB=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --kind) [ $# -ge 2 ] || die "--kind takes a repo kind"; KIND="$2"; shift 2 ;;
    --path) [ $# -ge 2 ] || die "--path takes a path relative to PORT_ROOT"; RELPATH="$2"; shift 2 ;;
    --covers) [ $# -ge 2 ] || die "--covers takes a sentence"; COVERS="$2"; shift 2 ;;
    --domain) [ $# -ge 2 ] || die "--domain takes a domain term"; DOMAIN="$2"; shift 2 ;;
    --owner) [ $# -ge 2 ] || die "--owner takes a name"; OWNER="$2"; shift 2 ;;
    --topology) [ $# -ge 2 ] || die "--topology takes a value"; TOPO="$2"; shift 2 ;;
    --interaction) [ $# -ge 2 ] || die "--interaction takes a value"; INTER="$2"; shift 2 ;;
    --remote) [ $# -ge 2 ] || die "--remote takes a URL"; REMOTE="$2"; shift 2 ;;
    --slug) [ $# -ge 2 ] || die "--slug takes owner/name"; SLUG="$2"; shift 2 ;;
    --github) GITHUB=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$ARG" ] || die "one name or path, not two ('$ARG' and '$1')"; ARG="$1"; shift ;;
  esac
done

PR="$(SR --port-root)" || die "scope-roots.sh could not resolve the workspace root" "sh $SRC/scope-roots.sh --port-root"; PR="${PR%/}"
PV="$(SR --private 2>/dev/null)" || PV="$PR/harbor-private"
REGF="$PV/repos.tsv"
LIVE_DIR="$HOME/.claude"
CFG="${CLAUDE_CONFIG_DIR:-$LIVE_DIR}"
W="${TMPDIR:-/tmp}/scope-repo.$$"; mkdir -p "$W" || exit 2
trap 'rm -rf "$W"' EXIT

if [ "$SUB" = list ]; then
  printf 'id\tpath\tkind\tgoverned\tregistry\tprojects\tmarker\tfleet\n'
  sh "$SRC/scope-repo-sources.sh" --matrix 2>/dev/null; exit 0
fi

[ -n "$ARG" ] || die "$SUB takes a ${SUB%audit}name" "sh $SRC/scope-repo.sh --help"
case "$SUB" in
  adopt)
    case "$ARG" in /*) T="$ARG" ;; *) T="$PR/$ARG" ;; esac
    [ -d "$T" ] || die "no such directory: $T" "harbor repo new <name> --kind <repo-kind>"
    T="$(CDPATH= cd -- "$T" && pwd -P)"; PRP="$(CDPATH= cd -- "$PR" && pwd -P)"
    case "$T" in "$PRP"/*) RELPATH="${RELPATH:-${T#"$PRP"/}}" ;; *) die "$T is outside PORT_ROOT ($PRP): a registered repo lives inside it" ;; esac
    NAME="${RELPATH##*/}" ;;
  new|audit) NAME="$ARG"; RELPATH="${RELPATH:-$NAME}" ;;
esac
case "$NAME" in ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) die "'$NAME' is not a repo name ([A-Za-z0-9][A-Za-z0-9._-]*)" ;; esac
case "$RELPATH" in /*|*..*|~*|\$*) die "--path must be relative to PORT_ROOT and stay inside it" ;; esac

if [ "$SUB" = audit ]; then
  # the audited repo is the registry's, not what the arguments guess
  _row="$(SR --rows 2>/dev/null | awk -F'\t' -v n="$NAME" '$1 == n { print; exit }')"
  [ -n "$_row" ] || die "$NAME is not in the registry ($REGF)" "harbor repo adopt <path>"
  RELPATH="$(printf '%s' "$_row" | cut -f2)"; KIND="$(printf '%s' "$_row" | cut -f3)"; COVERS="$(printf '%s' "$_row" | cut -f11)"
fi
T="$PR/$RELPATH"
if [ "$SUB" = new ] || [ "$SUB" = adopt ]; then
  [ -n "$KIND" ] || die "$SUB needs --kind (one of: $(awk -F'\t' '!/^#/ && NR > 1 { printf "%s ", $1 }' "$SRC/../standards/naming/repo-kinds.tsv" 2>/dev/null))" "harbor repo $SUB $ARG --kind workload"
fi
[ "$SUB" != new ] || [ ! -e "$T" ] || [ -z "$(ls -A "$T" 2>/dev/null)" ] || die "$T exists and is not empty" "harbor repo adopt $T --kind ${KIND:-<kind>}"

# The GitHub slug: given, else the registry remote, else the owner of harbor's own origin.
slug_of() {
  [ -z "$SLUG" ] || { printf '%s' "$SLUG"; return; }
  case "$REMOTE" in *github.com[:/]*) _s="${REMOTE#*github.com[:/]}"; printf '%s' "${_s%.git}"; return ;; esac
  _o="$(git -C "$SRC/.." remote get-url origin 2>/dev/null || :)"
  case "$_o" in *github.com[:/]*) _o="${_o#*github.com[:/]}"; printf '%s/%s' "${_o%%/*}" "$ID" ;; esac
}
ID="$NAME"

FAILS=0; WARNS=0
ok()   { printf '  step %s: ok%s\n' "$1" "${2:+ - $2}"; }
warn() { WARNS=$((WARNS + 1)); printf '  step %s: warn - %s\n' "$1" "$2"; }
fail() { FAILS=$((FAILS + 1)); printf '  step %s: FAIL - %s\n' "$1" "$2"; }
# the scaffolder is a root of roots.tsv; a box without it is named here, not left to a bare exit 127 (harbor#1436)
yard_new() {
  _yb="${HARBOR_SCOPE_SCAFFOLDER_BIN:-$(SR --get HARBOR_SCOPE_SCAFFOLDER_BIN 2>/dev/null || :)}"
  [ -n "$_yb" ] && [ -x "$_yb" ] || { echo "no scaffolder: HARBOR_SCOPE_SCAFFOLDER_BIN is not set and roots.tsv names none that is installed" >&2; return 127; }
  sh "$SRC/scope-system.sh" run yard new "$@"
}
GH_ARG=''; [ -z "${HARBOR_SCOPE_GH:-}" ] || GH_ARG="--gh $HARBOR_SCOPE_GH"
fleet_args() { _ff="$(SR --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)"; if [ -n "$_ff" ] && [ -f "$_ff" ]; then printf -- '--fleet\n%s\n' "$_ff"; else printf -- '--root\n%s\n' "$PR"; fi; }

# ── the checks (shared by the steps that are checks, and by `audit`) ────────────────────────────────────
chk_labels() { # 0 the register's labels, 1 a plan line, 3 no slug
  _sl="$(slug_of)"; [ -n "$_sl" ] || { echo "no GitHub slug (give --slug owner/name)"; return 3; }
  # shellcheck disable=SC2086
  sh "$SRC/standard-label-sync.sh" --repo "$_sl" $GH_ARG --config-dir "$CFG" > "$W/labels.out" 2>&1; _r=$?
  [ "$_r" -eq 0 ] || echo "$(grep -c -E '^  (create|rename|merge|remove|unregistered)' "$W/labels.out" || :) label change(s) planned for $_sl (harbor repo new --github applies them)"
  return "$_r"
}
chk_versions() {
  [ -f "$T/vendor/naming/lint-name.sh" ] || { echo "$RELPATH vendors no naming package (vendor/naming/lint-name.sh)"; return 1; }
  (cd "$T" && sh vendor/naming/lint-name.sh > "$W/versions.out" 2>&1) || { echo "the repo's own naming lint is red: $(grep -m1 -E 'FAIL|\[' "$W/versions.out" | cut -c1-160)"; return 1; }
  return 0
}
chk_fleet() {
  # fleet's audit exits 1 on any warn, and a newborn repo always has some (git hooks not installed, no memory directory, never
  # checked, the scaffolder's own naming baseline drift), so the verdict is by finding: a fail, or the kit category not ok, is red;
  # the warns are counted in the message of an ok.
  # shellcheck disable=SC2046
  sh "$SRC/scope-system.sh" run fleet audit "$NAME" $(fleet_args | tr '\n' ' ') --json > "$W/fleet.out" 2> "$W/fleet.err"; _r=$?
  [ "$_r" -le 1 ] || { echo "fleet audit exited $_r: $(head -n 1 "$W/fleet.err" | cut -c1-160)"; return 1; }
  if ! command -v jq >/dev/null 2>&1; then
    [ "$_r" -eq 0 ] || { echo "fleet audit exited $_r (jq is absent, so its findings could not be told apart)"; return 1; }
    return 0
  fi
  _red="$(jq -r '.[]?.findings[]? | select(.severity == "fail" or (.category == "kit" and .severity != "ok")) | .category + ": " + .message' "$W/fleet.out" 2>/dev/null | head -n 3 | tr '\n' ';')"
  [ -z "$_red" ] || { echo "fleet audit: $_red"; return 1; }
  return 0
}
chk_kit() {
  sh "$SRC/standard-kit.sh" --carries "$T" > "$W/kit.out" 2>&1; _r=$?
  [ "$_r" -eq 0 ] || echo "$(grep -m1 'kit:' "$W/kit.out" || grep -m1 FAIL "$W/kit.out")"
  return "$_r"
}
chk_sources() {
  sh "$SRC/scope-repo-sources.sh" > "$W/sources.out" 2>/dev/null; _r=$?
  [ "$_r" -ne 3 ] || { echo "no governed row to compare"; return 3; }
  _l="$(awk -F'\t' -v p="$RELPATH" '$1 == p' "$W/sources.out")"
  [ -z "$_l" ] || { echo "$_l" | tr '\t' ' '; return 1; }
  return 0
}
chk_ij2() { # lint context.registry-dirs, for the lines that name this repo
  sh "$SRC/lint-conventions.sh" --only IJ2 > "$W/ij2.out" 2>&1
  _l="$(grep -F "/$ID/" "$W/ij2.out" | grep VIOLATION | head -n 1)"; [ -z "$_l" ] || { echo "$_l"; return 1; }
  # the other direction: a repo the project registry names has its context-rules/<name>/ folder
  if awk -F'\t' -v k="$ID" '!/^#/ && $1 == k { f = 1 } END { exit !f }' "$PV/context-rules/user/projects.tsv" 2>/dev/null; then
    [ -d "$PV/context-rules/$ID" ] || { echo "projects.tsv names $ID and $PV/context-rules/$ID/ does not exist"; return 1; }
  fi
  return 0
}
chk_ij3() { # lint context.repo-registered
  HARBOR_LINT_ESTATE_ROOT="$PR" sh "$SRC/lint-conventions.sh" --only IJ3 > "$W/ij3.out" 2>&1
  _l="$(grep 'governed but unregistered' "$W/ij3.out" | grep -F "$ID" | head -n 1)"; [ -z "$_l" ] || { echo "$_l"; return 1; }
  return 0
}
chk_ij6() { # lint memory.repo-reachable
  _mo="$(HARBOR_SCOPE_REPO="$SRC/.." sh "$SRC/memory-route.sh" --dir "$CFG" 2>/dev/null)"; _r=$?
  [ "$_r" -ne 3 ] || { echo "memory route could not look (no store to route to)"; return 3; }
  printf '%s\n' "$_mo" | grep -E "^  BLIND[[:space:]]+$ID( |\$)" >/dev/null && { echo "$ID starts with no memory (sh $SRC/memory-route.sh --dir $CFG, applied)"; return 1; }
  return 0
}
run_audit() { # runs every check, prints one line each; sets AFAIL / AUNLOOKED
  AFAIL=0; AUNLOOKED=0
  for _c in $CHECKS; do
    _m="$(chk_"$_c")"; _r=$?
    case "$_r" in 0) printf '  check %s: ok\n' "$_c" ;; 3) AUNLOOKED=$((AUNLOOKED + 1)); printf '  check %s: unchecked - %s\n' "$_c" "$_m" ;;
      *) AFAIL=$((AFAIL + 1)); printf '  check %s: RED - %s\n' "$_c" "$_m" ;; esac
  done
}

if [ "$SUB" = audit ]; then
  printf 'audit %s (%s, kind %s)\n' "$NAME" "$T" "$KIND"
  run_audit
  if [ "$AFAIL" -gt 0 ]; then log_fail "$AFAIL check(s) red for $NAME"; log_fix "sh $0 audit $NAME   # names each red check"; log_end || :; exit 1; fi
  if [ "$AUNLOOKED" -gt 0 ]; then log_note "$AUNLOOKED check(s) could not look: this is not a pass for them"; log_end || :; exit 3; fi
  log_ok "$NAME passes every check"; log_end || :; exit 0
fi

# ── the steps ────────────────────────────────────────────────────────────────────────────────────────────
step_scaffold() {
  if [ "$SUB" = new ]; then set -- "$T" --kind "$KIND" --name "$NAME"; else set -- "$T" --kind "$KIND" --name "$NAME" --adopt; fi
  if [ "$DRY" = 1 ]; then yard_new "$@" --non-interactive --dry-run; _r=$?; [ "$_r" -eq 0 ] && ok scaffold "dry run of the scaffolder" || fail scaffold "the scaffolder's dry run exited $_r"; return; fi
  yard_new "$@" --non-interactive --json > "$W/scaffold.json" 2> "$W/scaffold.err"; _r=$?
  [ "$_r" -eq 0 ] || { fail scaffold "the scaffolder exited $_r: $(head -n 1 "$W/scaffold.err" | cut -c1-160)"; return; }
  [ -d "$T/.git" ] || git -C "$T" init -q 2>/dev/null || { fail scaffold "git init failed in $T"; return; }
  case "$REMOTE" in -|'') ;; *) git -C "$T" remote get-url origin >/dev/null 2>&1 || git -C "$T" remote add origin "$REMOTE" ;; esac
  ok scaffold "$T"
}
step_registry() {
  _row="$ID$TAB$RELPATH$TAB$KIND$TAB$REMOTE$TAB$TOPO$TAB$INTER$TAB-$TAB$DOMAIN${TAB}yes$TAB$OWNER$TAB$COVERS"
  _hit="$(awk -F'\t' -v n="$ID" -v p="$RELPATH" '!/^#/ && ($1 == n || tolower($2) == tolower(p)) { print $1 "\t" $2; exit }' "$REGF" 2>/dev/null)"
  if [ -n "$_hit" ]; then
    [ "$_hit" = "$ID$TAB$RELPATH" ] && ok registry "already registered" || fail registry "the registry has '$(printf '%s' "$_hit" | tr '\t' ' ')' and this repo is '$ID $RELPATH'"
    return
  fi
  [ "$DRY" = 0 ] || { ok registry "would append: $_row"; return; }
  [ -f "$REGF" ] || { fail registry "no registry at $REGF (harbor scope install)"; return; }
  { cat "$REGF"; [ -z "$(tail -c1 "$REGF")" ] || echo; printf '%s\n' "$_row"; } > "$W/repos.new"
  sh "$SRC/scope-roots.sh" --registry-check "$W/repos.new" > "$W/regcheck.out" 2>&1 || { fail registry "the row does not validate: $(grep -m1 -E 'FAIL|roots:' "$W/regcheck.out" | cut -c1-160)"; return; }
  cp "$W/repos.new" "$REGF" && ok registry "$REGF" || fail registry "could not write $REGF"
}
projects_file() { SR --projects 2>/dev/null || printf '%s' "$PV/context-rules/user/projects.tsv"; }
step_projects() {
  [ "$COVERS" != '-' ] || { warn projects "no --covers: the repo is registered and left out of projects.tsv until it has one"; return; }
  _pf="$PV/context-rules/user/projects.tsv"
  [ "$DRY" = 0 ] || { ok projects "would list $ID in $_pf"; return; }
  mkdir -p "${_pf%/*}"
  _disp="$PR"; case "$PR" in "$HOME"/*) _disp="~/${PR#"$HOME"/}" ;; esac
  if [ ! -f "$_pf" ] || grep -q 'GENERATED by bin/scope-repo' "$_pf"; then
    sh "$SRC/scope-repos-generate.sh" --projects > "$W/projects.new" 2> "$W/projects.err"; _r=$?
    [ "$_r" -eq 0 ] || { fail projects "the generator exited $_r: $(grep -m1 -E 'FAIL|note' "$W/projects.err" | cut -c1-160)"; return; }
    cp "$W/projects.new" "$_pf" && ok projects "generated $_pf" || fail projects "could not write $_pf"
  else
    awk -F'\t' -v k="$ID" '!/^#/ && $1 == k { f = 1 } END { exit !f }' "$_pf" && { ok projects "already listed in the hand-kept $_pf"; return; }
    { [ -z "$(tail -c1 "$_pf")" ] || echo; printf '%s\t%s/%s\t%s\n' "$ID" "$_disp" "$RELPATH" "$COVERS"; } >> "$_pf" && ok projects "appended to the hand-kept $_pf" || fail projects "could not write $_pf"
  fi
}
step_route() {
  [ "$DRY" = 0 ] || { ok route "would run memory-route.sh --apply"; return; }
  if [ "$CFG" = "$LIVE_DIR" ]; then set -- --live; else set -- --dir "$CFG"; fi
  HARBOR_SCOPE_REPO="$SRC/.." sh "$SRC/memory-route.sh" "$@" --apply --quiet > "$W/route.out" 2>&1; _r=$?
  case "$_r" in 0) ok route "sessions in $ID load the memory store" ;; 3) warn route "memory-route could not look (no store to route to): $(grep -m1 -E 'STOOD|stood|no store' "$W/route.out" | cut -c1-120)" ;;
    *) fail route "memory-route exited $_r" ;; esac
}
step_rules() {
  grep -q "^$ID$TAB" "$(projects_file)" 2>/dev/null || { warn rules "$ID is not in projects.tsv, so no context-rules/$ID/ (the registry-dirs lint would call it unseeded)"; return; }
  [ "$DRY" = 0 ] || { ok rules "would make $PV/context-rules/$ID/"; return; }
  mkdir -p "$PV/context-rules/$ID" && : > "$PV/context-rules/$ID/.gitkeep" && ok rules "$PV/context-rules/$ID/" || fail rules "could not make $PV/context-rules/$ID/"
}
step_labels() {
  _sl="$(slug_of)"
  [ -n "$_sl" ] || { warn labels "no GitHub slug (--slug owner/name): the label sync was not run"; return; }
  if [ "$GITHUB" = 1 ] && [ "$DRY" = 0 ]; then
    # shellcheck disable=SC2086
    sh "$SRC/standard-label-sync.sh" --repo "$_sl" $GH_ARG --config-dir "$CFG" --apply > "$W/labels.apply" 2>&1 || { fail labels "label sync --apply failed for $_sl"; return; }
  fi
  _m="$(chk_labels)"; _r=$?
  case "$_r" in 0) ok labels "$_sl carries the register's labels" ;; *) warn labels "$_m" ;; esac
}
step_versions() {
  [ "$DRY" = 0 ] || { ok versions "would run the repo's vendored naming lint"; return; }
  _m="$(chk_versions)" && ok versions "the repo's naming lint (versions, seams) is green" || fail versions "$_m"
}
step_fleet() {
  [ "$DRY" = 0 ] || { ok fleet "would register with fleet and audit"; return; }
  if [ -s "$W/scaffold.json" ]; then
    # shellcheck disable=SC2046
    sh "$SRC/scope-system.sh" run fleet register $(fleet_args | tr '\n' ' ') "$W/scaffold.json" > "$W/fleet.reg" 2>&1 || { fail fleet "fleet register failed: $(head -n 1 "$W/fleet.reg" | cut -c1-160)"; return; }
  fi
  _m="$(chk_fleet)" && ok fleet "registered; fleet audit is green" || fail fleet "$_m"
}

printf '%s %s (kind %s) in %s%s\n' "$SUB" "$ID" "$KIND" "$PR" "$([ "$DRY" = 1 ] && echo ' [dry run: nothing is written]')"
for _s in $STEPS; do "step_$_s"; done
if [ "$DRY" = 1 ]; then
  [ "$FAILS" -eq 0 ] || { log_fail "dry run: $FAILS step(s) would fail"; log_fix "read the FAIL lines above, then run without --dry-run"; log_end || :; exit 1; }
  log_ok "dry run: every step would run"; log_end || :; exit 0
fi
printf 'audit\n'
run_audit
[ "$FAILS" -eq 0 ] && [ "$AFAIL" -eq 0 ] || { log_fail "$FAILS step(s) failed, $AFAIL check(s) red"; log_fix "harbor repo audit $ID"; log_end || :; exit 1; }
[ "$AUNLOOKED" -eq 0 ] || { log_note "$AUNLOOKED check(s) could not look: this is not a pass for them"; log_end || :; exit 3; }
log_ok "$ID is created and green on every check"; log_end || :; exit 0
