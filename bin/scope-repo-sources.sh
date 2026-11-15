#!/usr/bin/env sh
# scope-repo-sources.sh (harbor#1430; check id `context.repo-sources-agree`) - the four places a repo is known, held against each other.
#
#   sh scope-repo-sources.sh            the repos present in one source and missing from another, one line each:
#                                       <repo> TAB present: <sources> TAB missing: <sources>   (exit 1 on any, 0 on none)
#   sh scope-repo-sources.sh --matrix   every repo and where it is known: id TAB path TAB kind TAB governed TAB registry TAB projects TAB marker TAB fleet
#   sh scope-repo-sources.sh --not-adopted   each git checkout at depth 1 of PORT_ROOT that `harbor repo adopt` would bring in, one line each:
#                                       <path> TAB <kind, - when unregistered> TAB unregistered|ungoverned   (exit 0; harbor#1278)
#                                       It never runs the fleet CLI (seconds a call, too slow for a session start), so a nested repo only
#                                       fleet.yaml names is not in it; the private layer is never a registry row (contracts/pack.md), so never in it.
#
# THE FOUR: the private layer's repos.tsv (the registry, the one source), the box tier's projects.tsv (generated from it by
# scope-repos-generate.sh), yard markers (the scaffolder's legacy marker file under <repo>/.claude/, named once by the floor library) and fleet discovery (the fleet CLI's `projects`).
# A governed registry row is expected in all four (projects.tsv only when it carries `covers`); an ungoverned row, and anything the
# registry lacks, is expected in the registry alone. Exit 3, never a green, when there is no registry or no governed row.
# The fleet CLI is HARBOR_SCOPE_FLEET_CONTROLLER_BIN; absent or failing, the fleet column is unchecked and says so.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$SRC/library-log.sh"; log_init scope-repo-sources
SR() { sh "$SRC/scope-roots.sh" "$@"; }

MODE='delta'
case "${1:-}" in
  '') ;;
  --matrix) MODE=matrix ;;
  --not-adopted) MODE=not-adopted ;;
  -h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SRC/scope-repo-sources.sh"; exit 0 ;;
  *) log_fail "unknown argument: $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac

W="${TMPDIR:-/tmp}/scope-repo-sources.$$"; mkdir -p "$W" || exit 2
trap 'rm -rf "$W"' EXIT
standdown() { log_note "$1"; log_note "this is not a pass: nothing was compared"; log_end || :; exit 3; }

SR --rows > "$W/rows" 2> "$W/err" || { _rc=$?; [ "$_rc" -eq 1 ] && standdown "no repo registry on this box"; log_fail "the registry was refused: $(cat "$W/err")"; log_fix "sh $SRC/scope-roots.sh --registry-check"; log_end || :; exit 2; }
# --not-adopted lists what the disk holds that the registry lacks, so an empty registry is its plainest answer (a member's fresh box), not a stand-down
[ -s "$W/rows" ] || [ "$MODE" = not-adopted ] || standdown "the registry has no row"
PR="$(SR --port-root)"; PR="${PR%/}"
PRP="$(CDPATH= cd -P -- "$PR" 2>/dev/null && pwd -P)" || PRP="$PR"   # fleet prints resolved paths, so both spellings are stripped

# registry: id path kind remote topology interaction note domain governed owner covers
awk -F'\t' '$9 == "yes" { n++ } END { exit !n }' "$W/rows" || [ "$MODE" = not-adopted ] || standdown "the registry has no governed row yet"

# projects.tsv: the names (column 1) of the box tier's registry
: > "$W/proj"
_pf="$(SR --projects 2>/dev/null)" && [ -f "$_pf" ] && awk -F'\t' '!/^#/ && NF >= 2 { print $1 }' "$_pf" | sort -u > "$W/proj"
PROJ_OK=0; [ -n "${_pf:-}" ] && [ -f "${_pf:-/nonexistent}" ] && PROJ_OK=1

# markers: every registered checkout, and every top-level directory of the workspace root
_mk="$(sed -n 's/^FLOOR_SCAFFOLDER_MARKER_LEGACY="\(.*\)"$/\1/p' "$SRC/library-admission.sh" 2>/dev/null | head -1)"
{ awk -F'\t' '{ print $2 }' "$W/rows"
  for _d in "$PR"/*/; do [ -d "$_d" ] && { _b="${_d%/}"; printf '%s\n' "${_b##*/}"; }; done
} | sort -u | while IFS= read -r _p; do [ -f "$PR/$_p/.claude/$_mk" ] && printf '%s\n' "$_p"; done > "$W/marker"

# the disk: every git checkout at depth 1 of the workspace root (--not-adopted only, where it stands in for fleet's root scan)
: > "$W/disk"
# A harbor core checkout (a member's copy of the pinned core, bin/harbor beside contracts/roots.tsv) is the tool, not a project to adopt.
[ "$MODE" != not-adopted ] || for _d in "$PR"/*/; do
  [ -e "$_d.git" ] && { [ -f "$_d""bin/harbor" ] && [ -f "$_d""contracts/roots.tsv" ] || { _b="${_d%/}"; printf '%s\n' "${_b##*/}"; }; }
done | sort -u > "$W/disk"
_pv="$(SR --private 2>/dev/null || :)"; _pv="${_pv%/}"; PRIV=''; case "$_pv" in "$PR"/*) PRIV="${_pv#"$PR"/}" ;; esac

# fleet discovery
fleet_ok=0; : > "$W/fleet"
_fb="${HARBOR_SCOPE_FLEET_CONTROLLER_BIN:-$(SR --get HARBOR_SCOPE_FLEET_CONTROLLER_BIN 2>/dev/null || :)}"
_ff="$(SR --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)"
if [ "$MODE" != not-adopted ] && [ -n "$_fb" ] && [ -x "$_fb" ]; then
  if [ -n "$_ff" ] && [ -f "$_ff" ]; then set -- --fleet "$_ff"; else set -- --root "$PR"; fi
  if "$_fb" projects "$@" > "$W/fleet.raw" 2>/dev/null; then
    fleet_ok=1
    sed -n 's/^.*, \(.*\))$/\1/p' "$W/fleet.raw" | while IFS= read -r _p; do
      case "$_p" in "$PR"/*) printf '%s\n' "${_p#"$PR"/}" ;; "$PRP"/*) printf '%s\n' "${_p#"$PRP"/}" ;; esac
    done | sort -u > "$W/fleet"
  fi
fi
[ "$fleet_ok" -eq 1 ] || [ "$MODE" = not-adopted ] || log_note "fleet discovery is unchecked: ${_fb:+$_fb failed}${_fb:-no fleet CLI (HARBOR_SCOPE_FLEET_CONTROLLER_BIN)}"
[ "$PROJ_OK" -eq 1 ] || log_note "projects.tsv is unchecked: the box tier has none"

awk -F'\t' -v projok="$PROJ_OK" -v fleetok="$fleet_ok" -v mode="$MODE" -v dir="$W" -v priv="$PRIV" '
  function load(f, set,   l) { while ((getline l < f) > 0) set[l] = 1; close(f) }
  function add(s, w) { return s == "" ? w : s "," w }
  BEGIN { load(dir "/proj", P); load(dir "/marker", M); load(dir "/fleet", F); load(dir "/disk", D) }
  { id = $1; path = $2; kind = $3; gov = $9; cov = $11
    R[path] = 1; ID[path] = id; byid[id] = path; KIND[path] = kind; GOV[path] = gov; COV[path] = cov; order[++n] = path }
  END {
    # a projects.tsv name is an id; the repo it names is that id'"'"'s path, or itself when the registry lacks it
    for (nm in P) { p = (nm in byid) ? byid[nm] : nm; PP[p] = 1; if (!(p in R)) { U[p] = 1; order[++n] = p } }
    for (p in M) if (!(p in R) && !(p in U)) { U[p] = 1; order[++n] = p }
    for (p in F) if (!(p in R) && !(p in U)) { U[p] = 1; order[++n] = p }
    for (p in D) if (!(p in R) && !(p in U)) { U[p] = 1; order[++n] = p }
    for (i = 1; i <= n; i++) { p = order[i]; if (seen[p]++) continue
      pres = ""; miss = ""
      inreg = (p in R); gov = inreg ? GOV[p] : "-"
      if (mode == "not-adopted") { if ((p in D) && p != priv && (!inreg || gov != "yes")) printf "%s\t%s\t%s\n", p, (inreg ? KIND[p] : "-"), (inreg ? "ungoverned" : "unregistered"); continue }
      if (inreg) pres = add(pres, "registry")
      if (p in PP) pres = add(pres, "projects.tsv")
      if (p in M) pres = add(pres, "marker")
      if (p in F) pres = add(pres, "fleet")
      if (mode == "matrix") { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", (inreg ? ID[p] : "-"), p, (inreg ? KIND[p] : "-"), gov,
          (inreg ? "yes" : "no"), (p in PP ? "yes" : "no"), (p in M ? "yes" : "no"), (fleetok ? ((p in F) ? "yes" : "no") : "?"); continue }
      if (!inreg) miss = add(miss, "registry")
      if (inreg && gov == "yes") {
        if (projok && COV[p] != "-" && COV[p] != "" && !(p in PP)) miss = add(miss, "projects.tsv")
        if (!(p in M)) miss = add(miss, "marker")
        if (fleetok && !(p in F)) miss = add(miss, "fleet")
      }
      if (miss != "") printf "%s\tpresent: %s\tmissing: %s\n", p, (pres == "" ? "-" : pres), miss
    } }' "$W/rows" > "$W/out"

if [ "$MODE" = matrix ] || [ "$MODE" = not-adopted ]; then cat "$W/out"; log_end || :; exit 0; fi
if [ -s "$W/out" ]; then
  cat "$W/out"
  log_fail "$(grep -c . "$W/out") repo(s) are known in one source and missing from another"
  log_fix "register the repo (sh $SRC/scope-repo.sh adopt <path>), then regenerate the lists (sh $SRC/scope-repos-generate.sh --check)"
  log_end || :; exit 1
fi
log_ok "the registry, projects.tsv, yard markers and fleet discovery name the same repos"
log_end || :; exit 0
