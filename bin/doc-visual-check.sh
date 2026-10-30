#!/usr/bin/env sh
# VISUAL CHECK (harbor#392) — renders every generated HTML surface and routes it
# to the verifiers that can judge it.
#
# THREE MECHANISMS, NONE OF THEM REDUNDANT. Lint H1 reads CSS SOURCE and catches
# a colour token with no dark value. This reads PIXELS and catches what source
# arithmetic cannot — a token used on a surface it was not chosen for, an
# inherited colour, a hand-written literal. archify's own visual-check reads
# GEOMETRY — containment and projected text size at desktop widths — and greps
# zero times for contrast. Measured on 2026-08-31/09-01: H1 found 1 defect, this
# found 12 more that H1 passes cleanly, and archify found 12 more that BOTH pass.
#
# Which verifiers a page gets is decided per page, by a marker the RENDERER
# declares — see the routing block at the foot of this file.
#
#   sh bin/doc-visual-check.sh              # every discovered surface
#   sh bin/doc-visual-check.sh --generated  # ONLY what this repo can regenerate
#   sh bin/doc-visual-check.sh <file.html>  # one page
#   sh bin/doc-visual-check.sh --self-test  # prove the checker can fail
#
# WHY `--generated` EXISTS, and it is not a quieter default. The bare form checks
# everything under docs/ and build/, which is right for a person: a page that
# ships is a page that must be legible, whoever made it. But build/ is gitignored
# scratch, so it accumulates artifacts no generator owns — on 2026-09-01 an audit
# page written by hand on 08-13, failing AA at 4.09:1, with no source to fix. A
# SUITE that goes red on that is a suite the operator switches off (No.2.11), and
# one that skips build/ entirely stops checking real pages. `--generated` is the
# third answer: check exactly what the repo can rebuild from source, which is
# what CI can hold anyone to.
#
# EXIT CODES ARE A CONTRACT (D-29): 0 pass, 1 fail, 2 usage, 3 UNCHECKED. Unchecked
# means the verifier was unavailable (no node, no Playwright, no Chrome): nothing was
# judged, and it is never reported as a pass — an unavailable verifier defers, it does
# not get substituted with weaker evidence (CONSTITUTION No.2.7). Before D-49 that was
# exit 2, "SKIPPED"; a reader that must still meet an old copy accepts 2 as well and
# marks the line `D-49 window`.
#
# NOT IN contracts/suites.txt, deliberately, and this is the open decision:
# the check needs a Chrome channel, which the self-hosted runner is not known to
# have. A suite entry that silently skips on the runner is the vacuous-gate
# shape C3 exists to prevent, so wiring it in is gated on either proving Chrome
# on the runner or accepting exit 3 as a distinct CI state.
#
# THE NODE HALF IS bin/doc-visual-check.mjs. Two runtimes for one gate is a
# deviation from the layer rule, recorded rather than hidden: Playwright is
# Node-only and the shell owns the gate contract, so the seam is at the browser
# boundary and nowhere else.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$SELF/.." && pwd)"
PROBE="$SELF/visual-check.mjs"
. "$SELF/library-log.sh"
log_init visual-check
[ -f "$PROBE" ] || { log_fail "missing $PROBE"; log_nofix "the header of bin/doc-visual-check.sh"; log_end || :; exit 1; }
ARCHIFY="${HARBOR_DOC_ARCHIFY_DIR:-${HARBOR_ARCHIFY:-$ROOT/vendor/archify}}"

# A flag this script does not know is a usage error (2, D-29), judged before anything that can be unavailable, so a
# typo is never read as a missing verifier. A page whose name starts with `-` is written `./-name.html`.
for _a in "$@"; do
  case "$_a" in
    --self-test|--generated) ;;
    -*) LOG_FD=2; log_fail "unknown option: $_a"; log_fix "sh $0 --help"; exit 2 ;;   # not a run: stderr, no summary (logging.md)
  esac
done

command -v node >/dev/null 2>&1 || {
  log_fail "unchecked — no node on PATH, so nothing was judged"; log_fix "$(pkg_hint node)"; log_end || :; exit 3; }

# THE NODE HALF PRINTS TAG LINES (ok, FAIL, fix, skip, note) and this says each one through the library, so a
# FAIL is counted, followed by its fix, and written to the log. Its exit code (0 pass, 1 fail, 2 usage,
# 3 unchecked) is left in $_PRC. A FAIL is held until its fix arrives, so log_fail and log_fix stay adjacent.
_pf=""
_flush() { [ -z "$_pf" ] || { log_fail "$_pf"; log_nofix "bin/doc-visual-check.mjs"; }; _pf=""; }
_probe() { # <targets...>
  _po="$(mktemp "${TMPDIR:-/tmp}/harbor-visual-probe.XXXXXX")"
  _PRC=0; node "$PROBE" "$@" > "$_po" 2>&1 || _PRC=$?
  while IFS= read -r _pl; do
    case "$_pl" in "  fix: "*) ;; *) _flush ;; esac
    case "$_pl" in
      "  ok: "*)   log_ok "${_pl#  ok: }" ;;
      "  FAIL: "*) _pf="${_pl#  FAIL: }" ;;
      "  fix: "*)  if [ -n "$_pf" ]; then log_fail "$_pf"; log_fix "${_pl#  fix: }"; _pf=""; else log_note "${_pl#  fix: }"; fi ;;
      "  skip: "*) log_skip "${_pl#  skip: }" ;;
      "  note: "*) log_note "${_pl#  note: }" ;;
      *)           log_note "$_pl" ;;
    esac
  done < "$_po"
  _flush
  rm -f "$_po"
  return 0
}

# THE SECOND VERIFIER LEAVES EXHAUST, and naming two of its files by hand left
# the rest on disk: `archify visual-check` writes a receipt, a contact sheet AND
# one PNG capture per viewport per theme — measured 2026-09-02, sixteen files and
# 2.0 MB per sweep, growing with every run. A checker that litters the directory
# it is judging is a checker whose next run reads its own droppings, and build/
# being gitignored only hides it. One prefix, one glob, and `_sweep_exhaust` is a
# function rather than a line so the self-test can exercise the SAME code.
_sweep_exhaust() {
  rm -f "${1%.html}".visual-check.*
}

if [ "${1:-}" = "--self-test" ]; then
  # A CHECKER THAT CANNOT FAIL IS WORSE THAN NO CHECKER (No.2.10). Two fixtures,
  # one each way: a page that is legible must pass, and the same page with one
  # colour walked toward its background must fail. The control is the half that
  # matters — without it a checker that returns "fail" unconditionally scores
  # perfectly on the red arm.
  _vt="${TMPDIR:-/tmp}/harbor-visual-selftest.$$"
  mkdir -p "$_vt"
  trap 'rm -rf "$_vt"' EXIT INT TERM HUP

  printf '<!doctype html><style>:root{--bg:#ffffff;--ink:#111111}\n' > "$_vt/good.html"
  printf 'body{background:var(--bg);color:var(--ink)}</style><p>legible text</p>\n' >> "$_vt/good.html"
  printf '<!doctype html><style>:root{--bg:#ffffff;--faint:#eeeeee}\n' > "$_vt/bad.html"
  printf 'body{background:var(--bg)}p{color:var(--faint)}</style><p>invisible text</p>\n' >> "$_vt/bad.html"

  # `|| _rc=$?` AND NOT A BARE CALL: under `set -e` a probe that exits 1 aborts
  # this script before the case can read it, so the red arm never runs and the
  # self-test reports one pass and a silent exit 1 — which is what it did.
  _rc=0; node "$PROBE" "$_vt/good.html" >/dev/null 2>&1 || _rc=$?
  case $_rc in
    0) log_ok "a legible page passes" ;;
    3) log_fail "unchecked — no browser available, so the self-test judged nothing"; log_fix "sh $0 --self-test   # once Chrome and Playwright are installed"; log_end || :; exit 3 ;;
    *) log_fail "the checker rejected a legible page"; log_nofix "the header of bin/doc-visual-check.sh" ;;
  esac

  _rc=0; node "$PROBE" "$_vt/bad.html" >/dev/null 2>&1 || _rc=$?
  case $_rc in
    1) log_ok "#eeeeee text on #ffffff is rejected" ;;
    3) log_fail "unchecked — no browser available, so the self-test judged nothing"; log_fix "sh $0 --self-test   # once Chrome and Playwright are installed"; log_end || :; exit 3 ;;
    *) log_fail "the checker passed text at 1.1:1"; log_nofix "the header of bin/doc-visual-check.sh" ;;
  esac

  # THE THIRD ARM IS A CONTROL ON AN EXEMPTION, not on this checker. The gate
  # below drops archify's `viewer/viewport-overflow` because at v2.16.0 it fires
  # on archify's OWN bundled example — so the exemption is only defensible while
  # that stays true. This renders that example and asserts it still fails. When a
  # re-pin makes it pass, this arm goes red and the exemption must be deleted:
  # the mechanism that stops a measured workaround becoming folklore.
  _ex="$ARCHIFY/examples/event-stream.dataflow.json"
  if [ -f "$ARCHIFY/bin/archify.mjs" ] && [ -f "$_ex" ]; then
    _rc=0
    node "$ARCHIFY/bin/archify.mjs" render dataflow "$_ex" "$_vt/ctl.html" >/dev/null 2>&1 || _rc=$?
    if [ "$_rc" -ne 0 ]; then
      log_fail "archify could not render its own example"; log_nofix "the header of bin/doc-visual-check.sh"
    else
      _ov="$(node "$ARCHIFY/bin/archify.mjs" visual-check "$_vt/ctl.html" --json 2>/dev/null \
             | grep -c 'viewer/viewport-overflow' || true)"
      if [ "${_ov:-0}" -gt 0 ]; then
        log_ok "upstream still fails its own containment check — exemption stands"
      else
        log_fail "archify example now passes containment: the viewer/viewport-overflow exemption is stale"
        log_nofix "the exemption comment in bin/doc-visual-check.sh (delete the exemption)"
      fi
    fi
  fi

  # A FOURTH ARM, ON THE CLEANUP ITSELF, because the leak it closes was invisible
  # from every green result: the gate passed, the report was correct, and 2.0 MB
  # of capture PNGs accumulated beside the pages under test on every run. The
  # fixture carries one of EACH shape archify actually writes — receipt, contact
  # sheet, and a capture per viewport per theme — and the arm asserts the page
  # survives and nothing else does. Naming two of them by hand is exactly what
  # shipped, so the fixture is what stops that returning.
  printf '<!doctype html><p>page</p>\n' > "$_vt/leak.html"
  for _e in visual-check.json visual-check.html \
            visual-check.1440x900.dark.png visual-check.1440x900.light.png \
            visual-check.2048x1320.dark.png visual-check.2048x1320.light.png; do
    printf 'x\n' > "$_vt/leak.$_e"
  done
  _sweep_exhaust "$_vt/leak.html"
  _left=$(ls "$_vt"/leak.* 2>/dev/null | LC_ALL=C wc -l | tr -d ' ')
  if [ "${_left:-0}" -eq 1 ] && [ -f "$_vt/leak.html" ]; then
    log_ok "every shape of archify exhaust is swept, the page is not"
  else
    log_note "left beside the page: $(ls "$_vt"/leak.* 2>/dev/null)"
    log_fail "${_left:-0} file(s) left beside the page — expected only the page itself"
    log_nofix "_sweep_exhaust in bin/doc-visual-check.sh"
  fi

  log_end || exit 1
  exit 0
fi

GENERATED_ONLY=0
if [ "${1:-}" = "--generated" ]; then GENERATED_ONLY=1; shift; fi

if [ "$#" -gt 0 ]; then
  _probe "$@"
  log_end || :
  exit "$_PRC"
fi

# RENDER FRESH, BUT NEVER INTO THE REPO. This gate ran `status-dashboard-generate.sh` only
# when build/dashboard.html was ABSENT, so on 2026-09-01 it scored a palette fix
# against output written before the fix and reported twelve failures that no
# longer existed. Regenerating in place fixed that and broke something worse:
# lint D2 immediately flagged this file as a mutator, and it was right — a
# checker that rewrites two generated pages turns a clean tree dirty and would
# leave CI with a non-empty `git status`. So the pages are rendered to a temp
# directory through each generator's STDOUT mode and checked there. Nothing under
# the repo is written.
#
# BOTH HALVES ARE DERIVED FROM THE GENERATOR'S OWN SOURCE, never listed here: it
# declares its destination as `OUT="$ROOT/..."`, and it declares whether stdout
# needs a flag — `status-dashboard-generate.sh` writes by default and prints with `--stdout`,
# `doc-index-generate.sh` prints by default and writes with `--apply`. Adding a generator
# that follows either convention enrols it with no edit to this file.
_tmp="${TMPDIR:-/tmp}/harbor-visual.$$"
mkdir -p "$_tmp"
trap 'rm -rf "$_tmp"' EXIT INT TERM HUP
_fresh=""; _superseded=""
for _g in "$ROOT"/bin/*-generate.sh; do   # harbor#961 W3: the generators are <family>-<object>-generate.sh
  [ -f "$_g" ] && [ ! -L "$_g" ] || continue   # a rename shim is the same generator under its old name
  _out="$(sed -n 's|^OUT="$ROOT/\(.*\)"$|\1|p' "$_g" | head -1)"
  [ -n "$_out" ] || continue
  _sflag=""
  grep -q -- '--stdout)' "$_g" 2>/dev/null && _sflag="--stdout"
  if sh "$_g" $_sflag > "$_tmp/$(basename "$_out")" 2>/dev/null; then
    _fresh="$_fresh $_tmp/$(basename "$_out")"
    _superseded="$_superseded $ROOT/$_out"
  else
    log_warn "${_g#$ROOT/} could not render — checking the copy on disk"
    log_fix "sh ${_g#$ROOT/} >/dev/null   # run it alone and read its error"
  fi
done

# DISCOVERY IS RECURSIVE, because build/pandora/*.html is a surface too and a
# top-level glob never saw it. Three exclusions: a page just rendered fresh above
# (checking the stale twin as well would report a defect already fixed), and
# archify's own `<name>.visual-check.html` contact sheets — a checker that grades
# its own exhaust is a loop.
_targets="$_fresh"
for f in $([ "$GENERATED_ONLY" -eq 1 ] || find "$ROOT/docs" "$ROOT/build" -type f -name '*.html' 2>/dev/null | sort); do
  case "$f" in *.visual-check.html) continue ;; esac
  case " $_superseded " in *" $f "*) continue ;; esac
  grep -q '<style' "$f" 2>/dev/null || continue
  _targets="$_targets $f"
done

# GREEN OVER ZERO PAGES IS A FAILURE, not a skip. A gate that renders nothing
# and prints a pass teaches the reader that it was checked.
[ -n "$_targets" ] || {
  _why="no HTML surface found under docs/ or build/ — nothing was checked"
  [ "$GENERATED_ONLY" -eq 0 ] || _why="no generator produced a page — nothing was checked"
  log_fail "$_why"
  log_fix "sh bin/doc-visual-check.sh <file.html>   # name a page"
  log_end || :
  exit 1; }

_probe $_targets; _rc=$_PRC

# THE SECOND VERIFIER, AND IT IS NOT A DUPLICATE. archify ships its own
# visual-check; measured at v2.16.0 it runs four DESKTOP viewports up to
# 2048x1320 and asserts layout containment and projected text legibility, and it
# greps zero times for contrast, luminance or WCAG. Ours asserts AA contrast at a
# 720px narrow viewport and nothing about geometry. Neither subsumes the other,
# so an archify-rendered page gets both. TWO DECLARED MARKERS, because a diagram
# reaches a reader two ways: archify's own page stamps `data-preset` on <html>,
# and a report that embeds the figure carries `<figure class="af">`. Both are
# written by a renderer, never inferred from content. A bare search for
# `data-preset=` was the first attempt and it was wrong for a reason worth
# recording: the embedded stylesheet defines each preset AS A SELECTOR, so every
# page carrying the fragment matched — right answer, wrong question, and the next
# page to mention the string in prose would have been routed too.
# AN ABSENT SECOND VERIFIER IS ANNOUNCED, NEVER SILENT (No.2.7). Without this the
# gate would print a clean pass over pages whose geometry nobody checked, which is
# substituting weaker evidence and calling it the same result.
if [ ! -f "$ARCHIFY/bin/archify.mjs" ]; then
  for f in $_targets; do
    grep -qE '<html[^>]*data-preset=|<figure class="af"' "$f" 2>/dev/null || continue
    log_skip "SKIPPED archify geometry pass on ${f#$ROOT/} — no archify at $ARCHIFY"
  done
  log_end || :
  exit "$_rc"
fi
for f in $_targets; do
  grep -qE '<html[^>]*data-preset=|<figure class="af"' "$f" 2>/dev/null || continue
  # ONE DIAGNOSTIC CLASS IS EXEMPT AND THE SELF-TEST IS WHAT KEEPS IT HONEST.
  # `viewer/viewport-overflow` fires 6/6 on archify's OWN bundled example at this
  # pin, so gating on it would import a guard that upstream cannot pass — the
  # false positive of No.2.11, which ends with the guard switched off. Everything
  # else archify reports is taken: `viewer/projected-text-readability` caught a
  # real defect here that our probe cannot see, and `archify validate` passes.
  _codes="$(node "$ARCHIFY/bin/archify.mjs" visual-check "$f" --json 2>/dev/null \
            | grep -o '"code"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | sed 's/.*"\([^"]*\)"$/\1/' \
            | grep -v '^viewer/viewport-overflow$' | sort -u)"
  _sweep_exhaust "$f"
  [ -n "$_codes" ] || { log_ok "${f#$ROOT/} (archify)"; continue; }
  printf '%s\n' "$_codes" > "$_tmp/codes"
  while IFS= read -r _c; do
    log_fail "${f#$ROOT/} (archify): $_c"
    log_fix "node $ARCHIFY/bin/archify.mjs visual-check $f   # lists where the diagnostic fires"
  done < "$_tmp/codes"
  _rc=1
done

log_end || :
exit "$_rc"
