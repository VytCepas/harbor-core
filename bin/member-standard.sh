#!/usr/bin/env sh
# member-standard.sh (harbor#1278) — the project standard `harbor hub project register` lays down on a member laptop: pure POSIX sh.
# Renders AGENTS.md, CLAUDE.md, a standards note and a tests/ layout; never overwrites, writes no governance marker. Usage: --help (control member.standard).
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$SRC/library-log.sh"; log_init member-standard

die() { log_fail "$1"; log_fix "${2:-sh $0 --help}"; log_end || :; exit 2; }
usage() {
  cat <<'EOF_USAGE'
member-standard.sh: the project standard `harbor hub project register` lays down on a member laptop. Pure POSIX sh.

  sh member-standard.sh <repo> --name <name> [--kind <repo-kind>] [--covers <text>] [--dry-run]

WHAT IT LAYS DOWN, rendered from yard's own templates and harbor's own kit, never typed in a second place:
  AGENTS.md, CLAUDE.md (the bare `@AGENTS.md` import): yard's templates/base files, vendored in vendor/scaffolder/ (bin/standard-vendor-scaffolder.sh,
  held fresh by doc-fresh-verify) and rendered unchanged for a member project, under a delimited member section that says what does not
  apply (the repo is not self-governed). Every kind gets both files, whether or not the kit lists template rows for it.
  docs/project-standard.md (the naming standard, the language by layer, the tests
  layout, the memory route), tests/run.sh (the runner), tests/suites.txt, tests/lib/core.sh (harbor's own harness, copied) and
  tests/example/example.test.sh (one passing suite, one suite per unit, red first). The kit (standard-kit.sh --render <kind>) says
  which items the kind inherits; the ones a member laptop cannot or must not lay down are named, one line each.

NEVER OVERWRITES. A file the person has is kept as it is and the line says so (`kept`); a CLAUDE.md of theirs without the import is
reported, never edited. A second run changes nothing. After the run, a check compares every file it may touch with what it was
before: a changed pre-existing file, or a marker it must not write, is red (exit 1).

THE MARKER: none. A project is self-governed (contracts/marker.md) when `.agents/config.yaml`, the legacy scaffolder marker in `.agents/`
or `.claude/config.yaml` exists, and the company floor stands down for it. A colleague's repo is not ours to un-govern, so this
writes none of the three and the repo resolves `ambient` by absence. A marker the person already has is left as it is.

Exit 0 done, 1 a check red or a write failed, 2 usage.
EOF_USAGE
}

T=''; NAME=''; KIND=workload; COVERS=''; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --name) [ $# -ge 2 ] || die "--name takes the project name"; NAME="$2"; shift 2 ;;
    --kind) [ $# -ge 2 ] || die "--kind takes a repo kind"; KIND="$2"; shift 2 ;;
    --covers) [ $# -ge 2 ] || die "--covers takes text"; COVERS="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [ -z "$T" ] || die "one repo, not two ('$T' and '$1')"; T="$1"; shift ;;
  esac
done
[ -n "$T" ] || die "no repo given" "sh $0 <repo> --name <name>"
[ -d "$T" ] || die "no such directory: $T"
T="$(CDPATH= cd -- "$T" && pwd -P)"
[ -n "$NAME" ] || NAME="${T##*/}"
case "$NAME" in ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) die "'$NAME' is not a project name ([A-Za-z0-9][A-Za-z0-9._-]*)" ;; esac
case "$KIND" in ''|*[!A-Za-z0-9._-]*) die "'$KIND' is not a repo kind" ;; esac
[ -n "$COVERS" ] || COVERS='A member project.'
TPL="$SRC/../templates/member-project"
VY="$SRC/../vendor/scaffolder"
[ -d "$TPL" ] || die "no templates at $TPL" "the harbor checkout this runs from lacks templates/member-project/"
[ -f "$VY/templates/base/AGENTS.md.tmpl" ] && [ -f "$VY/templates/base/CLAUDE.md.tmpl" ] || die "no vendored yard templates at $VY" "sh $SRC/standard-vendor-scaffolder.sh --write"
YARDC="$(sed -n 's/^# yard_commit: *\(.......\).*/\1/p' "$VY/MANIFEST.tsv" 2>/dev/null | head -n 1)"
CORE="$SRC/../tests/lib/core.sh"
[ -f "$CORE" ] || die "no harness to copy at $CORE" "the harbor checkout this runs from lacks tests/lib/core.sh"

W="${TMPDIR:-/tmp}/member-standard.$$"; mkdir -p "$W" || exit 2
# a time bound like the other member tools: 60 s in all, then TERM; every way out removes the temp dir
( sleep 60; kill -TERM $$ 2>/dev/null ) > /dev/null 2>&1 & WD=$!
trap 'kill "$WD" 2>/dev/null; rm -rf "$W"' EXIT
trap 'exit 143' TERM INT HUP

# Every path this may touch, and the markers it must not create.
TOUCH="AGENTS.md CLAUDE.md docs/project-standard.md tests/run.sh tests/suites.txt tests/lib/core.sh tests/example/example.test.sh"
# The scaffolder's legacy marker and repo name are read from the floor's one named constant (tests/scope/siblings).
LEGACY="$(sed -n 's/^FLOOR_SCAFFOLDER_MARKER_LEGACY="\(.*\)"$/\1/p' "$SRC/library-admission.sh" 2>/dev/null)"
[ -n "$LEGACY" ] || die "no scaffolder marker constant in $SRC/library-admission.sh" "reinstall the member floor"
MARKERS=".agents/config.yaml .agents/$LEGACY .claude/config.yaml"
snap() { for _p in $TOUCH $MARKERS; do if [ -f "$T/$_p" ]; then cksum < "$T/$_p" | sed "s|\$| $_p|"; elif [ -e "$T/$_p" ]; then echo "other $_p"; else echo "absent $_p"; fi; done; }
snap > "$W/before"

# ── rendering: @@TOKEN@@ placeholders, replaced from the environment so no character of the text is ever read as syntax ─────
NAMING=''
case "$SRC" in */bin) _h="${SRC%/bin}" ;; *) _h='' ;; esac
if [ -n "$_h" ] && [ -f "$_h/standards/naming.md" ]; then
  _hn="${_h##*/}"; _pn="$(CDPATH= cd -- "$T/.." && pwd -P)"
  [ "${_h%/*}" != "$_pn" ] || NAMING=" (here: \`../$_hn/standards/naming.md\`; judge a name with \`sh ../$_hn/bin/lint-name.sh --check <surface> <name>\`)"
fi
KITOUT="$W/kit.out"
sh "$SRC/standard-kit.sh" --render "$KIND" > "$KITOUT" 2> "$W/kit.err"; KITRC=$?
case "$KITRC" in
  0) KIT="$(awk -F'\t' '{ printf "- `%s` (%s: %s)\n", $1, $2, $3 }' "$KITOUT")" ;;
  *) KIT="- the kit could not be read on this install (standard-kit.sh exit $KITRC), so no item is listed"; : > "$KITOUT" ;;
esac
render() { # <template> -> stdout
  M_YARD="$YARDC" M_NAME="$NAME" M_COVERS="$COVERS" M_KIND="$KIND" M_NAMING="$NAMING" M_KIT="$KIT" awk '{
    gsub(/@@NAME@@/, ENVIRON["M_NAME"]); gsub(/@@YARD@@/, ENVIRON["M_YARD"]); gsub(/@@KIND@@/, ENVIRON["M_KIND"])
    n = split($0, a, "@@COVERS@@"); if (n > 1) { l = a[1]; for (i = 2; i <= n; i++) l = l ENVIRON["M_COVERS"] a[i]; $0 = l }
    n = split($0, a, "@@NAMING@@"); if (n > 1) { l = a[1]; for (i = 2; i <= n; i++) l = l ENVIRON["M_NAMING"] a[i]; $0 = l }
    n = split($0, a, "@@KIT@@"); if (n > 1) { l = a[1]; for (i = 2; i <= n; i++) l = l ENVIRON["M_KIT"] a[i]; $0 = l }
    print }' "$1"
}

# yrender <vendored template> -> stdout: yard's own template language ({{var}}, {{#if var}}...{{/if [var]}}, nesting, a variable is true when
# non-empty), the semantics of yard's scaffold._render. Values come from V_* in the environment. A marker left unrendered is red.
yrender() { # a bound on output (1 MB) and on steps; unknown, unclosed or stray markup in the TEMPLATE is an error (exit 3); values are literal
  V_project_name="$NAME" V_project_description="$COVERS" V_created_date="$(date +%Y-%m-%d)" \
  V_project_init_url="https://github.com/VytCepas/${LEGACY%.md}" V_no_just=true awk -v max=1048576 -v steps=100000 'BEGIN { RS = "\001" }
    function val(n) { return ENVIRON["V_" n] }
    function fail(m) { printf "member-standard: unrendered markup or bound hit: %s\n", m > "/dev/stderr"; exit 3 }
    function out(t) { outn += length(t); if (outn > max) fail("output is larger than " max " bytes"); printf "%s", t }
    function emit(chunk,   o, n) {
      if (!act[d]) return
      o = ""
      while (match(chunk, /\{\{[a-z_]+\}\}/)) {
        if (++nsteps > steps) fail("more than " steps " steps")
        n = substr(chunk, RSTART + 2, RLENGTH - 4)
        if (!(("V_" n) in ENVIRON)) fail("unknown variable {{" n "}}")
        o = o substr(chunk, 1, RSTART - 1) val(n)
        chunk = substr(chunk, RSTART + RLENGTH)
      }
      if (chunk ~ /(^|[^$])\{\{/) fail("a {{ that is not a variable or a block tag")
      out(o chunk)
    }
    { rest = $0; d = 0; act[0] = 1
      while (match(rest, /\{\{(#if [a-z_]+|\/if( [a-z_]+)?)\}\}/)) {
        if (++nsteps > steps) fail("more than " steps " steps")
        _s = RSTART; _l = RLENGTH
        emit(substr(rest, 1, _s - 1))
        tag = substr(rest, _s + 2, _l - 4); rest = substr(rest, _s + _l)
        if (substr(tag, 1, 3) == "#if") { n = substr(tag, 5); d++; act[d] = act[d - 1] && (val(n) != "") }
        else if (d > 0) d--
        else fail("a {{/if}} with no opener")
      }
      emit(rest)
      if (d > 0) fail("a {{#if}} block that is never closed") }' "$1"
}
yard_file() { # <AGENTS.md|CLAUDE.md> <member section template> -> the file's whole text
  cat "$TPL/$2" && yrender "$VY/templates/base/$1.tmpl"
}

WROTE=0; KEPT=0; FAILS=0
say() { printf '  %s\n' "$*"; }
put() { # <relative path> <source file>: write when absent, never otherwise (noclobber: a file that appears meanwhile is kept too)
  _rel="$1"; _src="$2"
  if [ -e "$T/$_rel" ] || [ -L "$T/$_rel" ]; then
    if grep -q 'harbor member project standard' "$T/$_rel" 2>/dev/null; then say "kept $_rel (already laid down)"; else say "kept $_rel (yours, not modified)"; fi
    KEPT=$((KEPT + 1)); return
  fi
  if [ "$DRY" = 1 ]; then say "would write $_rel"; return; fi
  case "$_rel" in */*) mkdir -p "$T/${_rel%/*}" 2>/dev/null || { say "FAILED $_rel (cannot make its folder)"; FAILS=$((FAILS + 1)); return; } ;; esac
  if ( set -C; cat "$_src" > "$T/$_rel" ) 2>/dev/null; then say "wrote $_rel"; WROTE=$((WROTE + 1))
  else say "kept $_rel (appeared while writing; not modified)"; KEPT=$((KEPT + 1)); fi
}

# ── render everything first: a failure here writes nothing to the project and the temp dir goes with the trap ─────────────
renderfail() { log_fail "member.standard: $1"; log_fix "the vendored template or a value is not renderable: sh $SRC/standard-vendor-scaffolder.sh --check"; log_end || :; exit 1; }
for _g in AGENTS.md CLAUDE.md; do
  case "$_g" in AGENTS.md) _m=member-agents.md.tmpl ;; *) _m=member-claude.md.tmpl ;; esac
  yard_file "$_g" "$_m" > "$W/$_g" 2> "$W/$_g.err" || renderfail "$_g: $(head -n 1 "$W/$_g.err" | cut -c1-200)"
done
render "$TPL/project-standard.md.tmpl" > "$W/standard.md"; render "$TPL/run.sh.tmpl" > "$W/run.sh"; render "$TPL/suites.txt.tmpl" > "$W/suites.txt"
render "$TPL/example.test.sh.tmpl" > "$W/example.test.sh"
{ cat "$CORE"; printf '# harbor member project standard: copied from harbor tests/lib/core.sh\n'; } > "$W/core.sh"
for _f in AGENTS.md CLAUDE.md standard.md run.sh suites.txt example.test.sh core.sh; do
  [ "$(wc -c < "$W/$_f" | tr -d ' ')" -le 1048576 ] || renderfail "$_f is larger than 1048576 bytes"
done

printf 'member standard for %s (kind %s) in %s%s\n' "$NAME" "$KIND" "$T" "$([ "$DRY" = 1 ] && echo ' [dry run: nothing is written]')"

# Every kind gets AGENTS.md and CLAUDE.md; the kit says which other template items the kind carries, and the ones this does not lay down are named.
CARRIES="$(awk -F'\t' '$2 == "template" { print $3 }' "$KITOUT" | tr '\n' ' ')"
[ -n "$CARRIES" ] || say "note: the kit lists no template items for kind $KIND; AGENTS.md and CLAUDE.md are written for every member project"
for _g in AGENTS.md CLAUDE.md; do put "$_g" "$W/$_g"; done
for _c in $CARRIES; do
  case "$_c" in
    AGENTS.md|CLAUDE.md) ;;
    .agents/config.yaml) say "not written: $_c (the self-governed marker: this repo stays under the company layer)" ;;
    *) say "not written: $_c (needs yard, uv or just, or is not the standard's to put in a colleague's repo)" ;;
  esac
done
# the import: a CLAUDE.md of theirs without the bare line is reported, never edited
if [ -f "$T/CLAUDE.md" ] && ! grep -qx '@AGENTS.md' "$T/CLAUDE.md"; then
  say "note: CLAUDE.md does not import AGENTS.md; add the line @AGENTS.md on its own line (not edited)"
fi
put docs/project-standard.md "$W/standard.md"
# The tests layout is one unit: a runner or manifest of the person's own keeps the whole layout out, so two runners never share a folder.
_foreign=0
for _f in tests/run.sh tests/suites.txt; do
  [ -e "$T/$_f" ] && ! grep -q 'harbor member project standard' "$T/$_f" 2>/dev/null && _foreign=1
done
if [ "$_foreign" = 1 ]; then
  say "kept tests/ (you have your own runner or suite list; the example suite and harness were not laid down)"; KEPT=$((KEPT + 1))
else
  put tests/run.sh "$W/run.sh"
  put tests/suites.txt "$W/suites.txt"
  put tests/lib/core.sh "$W/core.sh"
  put tests/example/example.test.sh "$W/example.test.sh"
fi
say "memory: routed by the register step above (nothing is stored in this repo)"

# ── the check: nothing of the person's changed, and no marker was made ───────────────────────────────────
snap > "$W/after"
CHANGED="$(awk 'NR == FNR { b[FNR] = $0; next } b[FNR] != $0 && b[FNR] !~ /^absent / { print $NF }' "$W/before" "$W/after" | tr '\n' ' ')"
MADE="$(awk 'NR == FNR { b[FNR] = $0; next } b[FNR] ~ /^absent / && $0 !~ /^absent / { print $NF }' "$W/before" "$W/after" | grep -E '^\.(agents|claude)/' | tr '\n' ' ')"
[ -z "$CHANGED" ] || { log_fail "member.standard: a file the person had was changed: ${CHANGED% }"; log_fix "git -C $T diff   # restore it, then report the run"; FAILS=$((FAILS + 1)); }
[ -z "$MADE" ] || { log_fail "member.standard: a governance marker was written: ${MADE% }"; log_fix "git -C $T status   # remove the marker, then report the run"; FAILS=$((FAILS + 1)); }
_mk=''; [ -n "$MADE" ] || _mk='; marker: none (the repo stays under the company layer)'
printf 'standard: %d written, %d kept%s; left uncommitted for you to review\n' "$WROTE" "$KEPT" "$_mk"
if [ "$FAILS" -gt 0 ]; then log_end || :; exit 1; fi
log_ok "$NAME carries the member project standard"; log_end || :; exit 0
