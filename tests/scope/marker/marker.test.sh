#!/usr/bin/env sh
# The shared marker fixtures (H2, harbor#4; contracts/marker.md) against every implementation of the seam:
# the resolver (guard-lib's floor_in_repo) inline, project-init's allowlist and projects-orchestrator's
# descriptor through one adapter process each. Only the resolver's fixtures are COUNTED; the siblings'
# answers are reported on their own line, so docs/generated/status.md's count reads the same on every box (2026-09-06).
# A sibling that disagrees, or an adapter that answers short, still fails. A missing clone SKIPS.
#   sh marker-test.sh --unsettled   the cases the spec does not decide;  HARBOR_TEST_SKIP_CROSS=1  resolver only
# The two sibling clones through the one reader, located before t_init sandboxes HOME: an exported override wins,
# else the registry's row for the role (by kind, so a renamed yard or fleet is found), else the table (harbor#966).
_MR="$(dirname "$0")/../../../bin/scope-roots.sh"
PI_DIR="${HARBOR_SCOPE_SCAFFOLDER:-$(sh "$_MR" --get HARBOR_SCOPE_SCAFFOLDER 2>/dev/null || :)}"          # the suite never writes there
PO_DIR="${HARBOR_SCOPE_FLEET_CONTROLLER:-$(sh "$_MR" --get HARBOR_SCOPE_FLEET_CONTROLLER 2>/dev/null || :)}"
SKIP_CROSS="${HARBOR_TEST_SKIP_CROSS:-${HARBOR_SKIP_CROSS:-0}}"  # and before t_init clears the caller's HARBOR_* (harbor#773)
. "$(dirname "$0")/../../lib/core.sh"; t_init
CASES="$T_ROOT/fixtures/marker/cases.json"; M="$T_TMP/m"; mkdir -p "$M"; TAB="$(printf '\t')"
command -v jq >/dev/null 2>&1 || { echo "marker-test: jq is required" >&2; exit 1; }
[ -f "$CASES" ] || { echo "marker-test: no fixtures at $CASES" >&2; exit 1; }
if [ "${1:-}" = "--unsettled" ]; then
  jq -r '.cases[] | select(.settled == false) | "── \(.id)\n   \(.question)\n   why: \(.why)"' "$CASES"; exit 0
fi
. "$T_ROOT/bin/library-admission.sh"
UNSETTLED=0; XPASS=0; XRAN=0

# The resolver through its real entry point, the hook payload's cwd. HOME and PORT_ROOT are inputs
# (M14, M33-M37), so each case pins both; `-` unsets PORT_ROOT so the $HOME/port default is under test.
resolve() { # <dir-or-empty> <home> <port-root|->
  if [ -n "$1" ]; then _j="$(jq -cn --arg d "$1" '{tool_name:"Bash",cwd:$d,tool_input:{command:"true"}}')"
  else                 _j='{"tool_name":"Bash","tool_input":{"command":"true"}}'; fi
  ( FLOOR_IN="$_j"; unset CLAUDE_PROJECT_DIR
    HOME="$2"; export HOME
    if [ "$3" = "-" ]; then unset PORT_ROOT; else PORT_ROOT="$3"; export PORT_ROOT; fi
    cd / 2>/dev/null || true          # so a stray $PWD cannot supply the answer
    floor_in_repo && echo repo || echo ambient )
}
cj() { jq -r ".cases[$i]$1" "$CASES"; }  # <jq path> — a field of case $i

# Work lists for the two sibling roles: id, cwd, home, expect, and for the allowlist the PORT_ROOT too
# (project-init#1030); the orchestrator's discovery walks no markers, so its list has no such column.
PI_WORK="$M/.work-allowlist"; : > "$PI_WORK"; PO_WORK="$M/.work-descriptor"; : > "$PO_WORK"
N="$(jq '.cases | length' "$CASES")"
t_section "marker fixtures · $N cases"
i=0
while [ "$i" -lt "$N" ]; do
  ID="$(cj .id)"; EXPECT="$(cj .expect)"; SETTLED="$(cj .settled)"
  CWD="$(cj '.cwd // empty')"; ABS="$(cj '.absolute_cwd // empty')"
  ROLES="$(cj '.roles // ["resolver","allowlist","descriptor"] | join(",")')"
  CASEDIR="$M/$ID"; mkdir -p "$CASEDIR"
  cj '.tree[]?' | while IFS= read -r f; do
    [ -n "$f" ] || continue; mkdir -p "$CASEDIR/$(dirname "$f")"; : > "$CASEDIR/$f"
  done
  cj '.files // {} | keys[]' | while IFS= read -r f; do  # `files`: the verdict depends on the content
    [ -n "$f" ] || continue; mkdir -p "$CASEDIR/$(dirname "$f")"
    jq -r --arg k "$f" ".cases[$i].files[\$k]" "$CASES" > "$CASEDIR/$f"
  done
  jq -c ".cases[$i].symlinks[]?" "$CASES" | while IFS= read -r s; do
    [ -n "$s" ] || continue
    _from="$(printf '%s' "$s" | jq -r '.from')"; _to="$(printf '%s' "$s" | jq -r '.to')"
    mkdir -p "$CASEDIR/$(dirname "$_from")"; ln -sfn "$CASEDIR/$_to" "$CASEDIR/$_from"
  done
  # `cwd: "."` reaches the resolver as `<case>/.` on purpose: M30 is $HOME spelled differently.
  if [ -n "$ABS" ]; then TARGET="$ABS"
  elif [ -z "$CWD" ] || [ "$CWD" = "null" ]; then TARGET=""
  else TARGET="$CASEDIR/$CWD"; fi
  HOMEV="$(cj '.home // empty')"  # absent: a HOME that is no ancestor of the case, so M14 cannot fire
  if   [ -z "$HOMEV" ];    then CASEHOME="$M/.no-home"
  elif [ "$HOMEV" = "." ]; then CASEHOME="$CASEDIR"
  else                          CASEHOME="$CASEDIR/$HOMEV"; fi
  PORTV="$(cj '.port_root // empty')"; PORTUNSET="$(cj '.port_root_unset // false')"
  if   [ "$PORTUNSET" = "true" ]; then CASEPORT="-"
  elif [ -z "$PORTV" ];           then CASEPORT="$M/.no-port-root"
  elif [ "$PORTV" = "." ];        then CASEPORT="$CASEDIR"
  else                                 CASEPORT="$CASEDIR/$PORTV"; fi
  case ",$ROLES," in *,allowlist,*)  [ -n "$TARGET" ] && printf '%s\t%s\t%s\t%s\t%s\n' "$ID" "$TARGET" "$CASEHOME" "$EXPECT" "$CASEPORT" >> "$PI_WORK" ;; esac
  case ",$ROLES," in *,descriptor,*) [ -n "$TARGET" ] && printf '%s\t%s\t%s\t%s\n' "$ID" "$TARGET" "$CASEHOME" "$EXPECT" >> "$PO_WORK" ;; esac
  case ",$ROLES," in *,resolver,*) ;; *) i=$((i + 1)); continue ;; esac
  GOT="$(resolve "$TARGET" "$CASEHOME" "$CASEPORT")"
  if [ "$SETTLED" = "false" ]; then
    UNSETTLED=$((UNSETTLED + 1)); printf '  ? %-28s spec undecided — the resolver says: %s\n' "$ID" "$GOT"
  else t_eq "$ID" "$EXPECT" "$GOT"; fi
  i=$((i + 1))
done

# ── harbor itself (harbor#954 PR C): the checkout this suite runs from resolves `repo`. A fixture cannot
# say this — the subject is the real tree — so it is one more resolver line. HOME is a non-ancestor and
# PORT_ROOT is unset, so nothing but the harbor marker decides it.
t_eq "H01-harbor-root-resolves-repo" "repo" "$(resolve "$T_ROOT" "$M/.no-home" "-")"

# ── the sibling roles: a disagreement fails, agreement is reported and never counted (see the header)
x_complete() { # <role> <workfile> <outfile> <rc> — a dead or short adapter is a failure, not a pass
  _want="$(wc -l < "$2" | tr -d ' ')"; _have="$(wc -l < "$3" 2>/dev/null | tr -d ' ')"; _have="${_have:-0}"
  [ "$4" -eq 0 ] && [ "$_have" -eq "$_want" ] && return 0
  t_eq "INCOMPLETE [$1] the adapter answers every case" "exit 0, $_want of $_want" "exit $4, $_have of $_want"; return 1
}
x_report() { # <role> <label> <outfile>
  XRAN=$((XRAN + 1))
  while IFS="$TAB" read -r _id _want _got; do
    [ -n "$_id" ] || continue
    if [ "$_want" = "$_got" ]; then XPASS=$((XPASS + 1)); else t_eq "$_id [$1]" "$_want" "$_got"; fi
  done < "$3"
  printf '  · %-12s %s\n' "$1" "$2"
}
PYTHONDONTWRITEBYTECODE=1; export PYTHONDONTWRITEBYTECODE  # no __pycache__ in a sibling clone
echo
if [ "$SKIP_CROSS" = "1" ]; then
  echo "  · cross-repo   SKIPPED (HARBOR_TEST_SKIP_CROSS=1) — the resolver only"
else
  PI_HOOK="$PI_DIR/templates/base/dot_agents/hooks/prod_guard.py"
  if [ -f "$PI_HOOK" ] && command -v python3 >/dev/null 2>&1; then
    # The program is a FILE: `python3 -` reads its source from stdin, where the work list goes.
    cat > "$M/.adapter-allowlist.py" <<'PYEOF'
import importlib.util, os, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("_pg", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)          # __name__ is "_pg", so main() does not run
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    case_id, cwd, home, want, port = line.split("\t")
    os.environ["HOME"] = home         # Path.home() reads this at call time
    if port == "-":                   # M37: the $HOME/port DEFAULT is under test
        os.environ.pop("PORT_ROOT", None)
    else:                             # read per call too (_port_root)
        os.environ["PORT_ROOT"] = port
    verdict = "repo" if mod._find_config(Path(cwd)) is not None else "ambient"
    print(f"{case_id}\t{want}\t{verdict}")
PYEOF
    python3 "$M/.adapter-allowlist.py" "$PI_HOOK" < "$PI_WORK" > "$M/.out-allowlist" 2>"$M/.err-allowlist"; _rc=$?
    [ -s "$M/.err-allowlist" ] && printf '    %s\n' "$(head -1 "$M/.err-allowlist")" >&2
    x_complete allowlist "$PI_WORK" "$M/.out-allowlist" "$_rc" \
      && x_report allowlist "project-init prod_guard._find_config · $(wc -l < "$PI_WORK" | tr -d ' ') cases" "$M/.out-allowlist"
  else
    printf '  · %-12s SKIPPED — no clone at %s\n' "allowlist" "$PI_DIR"
  fi
  PO_PY="$PO_DIR/.venv/bin/python"
  if [ -x "$PO_PY" ] && [ -d "$PO_DIR/src" ]; then
    cat > "$M/.adapter-descriptor.py" <<'PYEOF'
import sys
from pathlib import Path

sys.path.insert(0, sys.argv[1])
from projects_orchestrator.descriptor import load_descriptor, resolve_config

for line in sys.stdin:
    line = line.rstrip("\n")
    if not line:
        continue
    case_id, cwd, home, want = line.split("\t")
    target = Path(cwd)
    if resolve_config(target) is None:
        verdict = "ambient"
    else:
        descriptor = load_descriptor(target)
        verdict = "ambient" if descriptor is None or descriptor.context == "ambient" else "repo"
    print(f"{case_id}\t{want}\t{verdict}")
PYEOF
    "$PO_PY" "$M/.adapter-descriptor.py" "$PO_DIR/src" < "$PO_WORK" > "$M/.out-descriptor" 2>"$M/.err-descriptor"; _rc=$?
    [ -s "$M/.err-descriptor" ] && printf '    %s\n' "$(head -1 "$M/.err-descriptor")" >&2
    x_complete descriptor "$PO_WORK" "$M/.out-descriptor" "$_rc" \
      && x_report descriptor "orchestrator resolve_config · $(wc -l < "$PO_WORK" | tr -d ' ') cases" "$M/.out-descriptor"
  else
    printf '  · %-12s SKIPPED — no venv at %s\n' "descriptor" "$PO_PY"
  fi
fi
echo
if [ "$XRAN" -gt 0 ]; then
  printf '  cross-repo: %d passed from %d sibling repo(s) — not counted here, and not in docs/generated/status.md\n' "$XPASS" "$XRAN"
else
  printf '  cross-repo: not run on this box — the fixtures above are the resolver half only\n'
fi
printf '  awaiting an owner decision: %d%s\n' "$UNSETTLED" "$([ "$UNSETTLED" -gt 0 ] && echo " (sh $0 --unsettled)")"
t_done
