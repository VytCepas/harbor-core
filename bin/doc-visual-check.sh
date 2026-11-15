#!/usr/bin/env sh
# VISUAL CHECK (harbor#392) — renders every generated HTML surface and routes it
# to the verifiers that can judge it.
#
# Three mechanisms, none redundant: lint H1 reads CSS SOURCE (a token with no dark value); this reads PIXELS (a token on
# the wrong surface, an inherited colour, a literal); archify's visual-check reads GEOMETRY and never contrast. Each found
# defects the others passed. Which verifiers a page gets is decided per page by a marker the RENDERER declares (routing block).
# Removed notes: docs/explanation/code-cases/bin-doc-visual-check.md
#   sh bin/doc-visual-check.sh              # every discovered surface
#   sh bin/doc-visual-check.sh --generated  # ONLY what this repo can regenerate
#   sh bin/doc-visual-check.sh <file.html>  # one page
#   sh bin/doc-visual-check.sh --self-test  # prove the checker can fail
# `--generated` exists because the bare form also checks gitignored build/ scratch that no generator owns (a hand-written
# page failing AA with no source to fix); a suite red on that gets switched off (No.2.11), while skipping build/ stops
# checking real pages. `--generated` checks exactly what the repo can rebuild, which is what CI can hold anyone to.
# EXIT CODES ARE A CONTRACT (D-29): 0 pass, 1 fail, 2 usage, 3 UNCHECKED. Unchecked means the verifier was unavailable
# (no node, Playwright or Chrome): nothing was judged and it is never reported as a pass (CONSTITUTION No.2.7). Before D-49
# that was exit 2, "SKIPPED"; a reader meeting an old copy accepts 2 as well and marks the line `D-49 window`.
# NOT in contracts/suites.txt, an open decision: it needs a Chrome channel the self-hosted runner is not known to have,
# and a suite entry that silently skips is C3's vacuous-gate shape.
# The node half is bin/doc-visual-check.mjs: Playwright is Node-only and the shell owns the gate contract, a recorded
# deviation from the layer rule; the seam is at the browser boundary.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$SELF/.." && pwd)"
PROBE="$SELF/doc-visual-check.mjs"
. "$SELF/library-log.sh"
log_init visual-check
[ -f "$PROBE" ] || { log_fail "missing $PROBE"; log_nofix "the header of bin/doc-visual-check.sh"; log_end || :; exit 1; }
ARCHIFY="${HARBOR_DOC_ARCHIFY_DIR:-$ROOT/vendor/archify}"

# An unknown flag is a usage error (2, D-29), judged before anything that can be unavailable. A page named `-x` is `./-x.html`.
for _a in "$@"; do
  # shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
  case "$_a" in
    --self-test|--generated) ;;
    -*) LOG_FD=2; log_fail "unknown option: $_a"; log_fix "sh $0 --help"; exit 2 ;;   # not a run: stderr, no summary (logging.md)
  esac
done

command -v node >/dev/null 2>&1 || {
  log_fail "unchecked — no node on PATH, so nothing was judged"; log_fix "$(pkg_hint node)"; log_end || :; exit 3; }

# The node half prints tag lines (ok, FAIL, fix, skip, note); each is said through the library. Its exit code is left in
# $_PRC. A FAIL is held until its fix arrives, so log_fail and log_fix stay adjacent.
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

# archify visual-check leaves exhaust (a receipt, a contact sheet, a PNG per viewport per theme); one prefix glob in a
# function so the self-test exercises the SAME code.
_sweep_exhaust() {
  rm -f "${1%.html}".visual-check.*
}

if [ "${1:-}" = "--self-test" ]; then
  # A checker that cannot fail is worse than none (No.2.10): a legible page must pass and the same page with a colour walked toward its background must fail.
  _vt="${TMPDIR:-/tmp}/harbor-visual-selftest.$$"
  mkdir -p "$_vt"
  trap 'rm -rf "$_vt"' EXIT INT TERM HUP

  printf '<!doctype html><style>:root{--bg:#ffffff;--ink:#111111}\n' > "$_vt/good.html"
  printf 'body{background:var(--bg);color:var(--ink)}</style><p>legible text</p>\n' >> "$_vt/good.html"
  printf '<!doctype html><style>:root{--bg:#ffffff;--faint:#eeeeee}\n' > "$_vt/bad.html"
  printf 'body{background:var(--bg)}p{color:var(--faint)}</style><p>invisible text</p>\n' >> "$_vt/bad.html"

  # `|| _rc=$?`, not a bare call: under `set -e` a probe exiting 1 aborts before the case can read it.
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

  # Third arm: a control on an EXEMPTION. The gate drops `viewer/viewport-overflow` because archify v2.16.0 fires it on its
  # own example; when a re-pin makes that pass, this arm goes red and the exemption must be deleted.
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

  # Fourth arm, on the cleanup: the leak (capture PNGs piling up beside the pages) was invisible from every green result.
  # The fixture carries one of EACH shape archify writes; the page must survive and nothing else.
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

# Render fresh, but never into the repo: rendering only when absent scored a fix against stale output, and regenerating in
# place made this a mutator (lint D2) that dirtied the tree. Pages go to a temp dir through each generator's STDOUT mode.
# Both halves are derived from the generator's source (`OUT="$ROOT/..."`, and `--stdout)` for whether a flag is needed),
# so a new generator enrols with no edit here.
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

# Discovery is recursive (build/<client>/*.html is a surface). Excluded: a page just rendered fresh (its stale twin is a
# fixed defect) and archify's own `.visual-check.html` contact sheets (grading its own exhaust is a loop).
_targets="$_fresh"
for f in $([ "$GENERATED_ONLY" -eq 1 ] || find "$ROOT/docs" "$ROOT/build" -type f -name '*.html' 2>/dev/null | sort); do
  case "$f" in *.visual-check.html) continue ;; esac
  case " $_superseded " in *" $f "*) continue ;; esac
  grep -q '<style' "$f" 2>/dev/null || continue
  _targets="$_targets $f"
done

# Green over zero pages is a failure, not a skip.
[ -n "$_targets" ] || {
  _why="no HTML surface found under docs/ or build/ — nothing was checked"
  [ "$GENERATED_ONLY" -eq 0 ] || _why="no generator produced a page — nothing was checked"
  log_fail "$_why"
  log_fix "sh bin/doc-visual-check.sh <file.html>   # name a page"
  log_end || :
  exit 1; }

_probe $_targets; _rc=$_PRC

# The second verifier is not a duplicate: archify asserts layout containment and text legibility at desktop viewports and
# never contrast; ours asserts AA contrast at 720px and no geometry. Two DECLARED markers route a page to it, written by a
# renderer and never inferred from content: `data-preset` on <html>, and `<figure class="af">` for an embedded figure (a bare
# search for `data-preset=` matched every page carrying the stylesheet, which defines presets as selectors).
# An absent second verifier is announced, never silent (No.2.7).
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
  # One diagnostic class is exempt: `viewer/viewport-overflow` fires on archify's own example at this pin, and importing a guard
  # upstream cannot pass is No.2.11's false positive; the self-test keeps the exemption honest. Everything else is taken.
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
