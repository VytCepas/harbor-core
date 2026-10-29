#!/usr/bin/env sh
# deploy-launchd-render.sh — fill a launchd plist template from the roots table (harbor#630, #1149).
#
#   sh deploy-launchd-render.sh <plist>               the rendered plist on stdout; writes, loads and bootstraps nothing
#   sh deploy-launchd-render.sh --check [<plist>...]  every template renders: each placeholder is a root this box can resolve, nothing
#                                              is left unfilled, the file ends in a newline and parses as a plist where
#                                              plutil or xmllint exists (default: every launchd/*.plist this tool owns)
#   sh deploy-launchd-render.sh --list                each placeholder and the value it has on this box
#
# WHY A TEMPLATE. launchd does not expand $HOME or ~, so a plist has to spell the home directory it runs under, and a
# tracked plist that spells one is a tracked file that names its author's home (lint HP1, lint-leaks home-path). The
# repo carries the plist with a placeholder instead and this fills it, so the file a person installs is the file
# that was reviewed, with this machine's roots written in.
#
# PLACEHOLDERS, and the one place each comes from:
#   @HOME@        the BOX base: the home directory (scope-roots.sh --base BOX, which is $HOME with no trailing slash)
#   @<VAR>@       any variable in contracts/roots.tsv, as `scope-roots.sh --get <VAR>` answers it: HARBOR_SCOPE_LOCAL_BIN is $HOME/.local/bin
#                 unless an exported HARBOR_SCOPE_LOCAL_BIN says otherwise. HARBOR_SCOPE_ROOTS_TABLE points at another table (the suite's copy).
# Anything else is refused, not left in: a plist installed with a literal @NAME@ in it loads and then fails when it runs,
# and `launchctl list` shows it healthy. @BIN@, @SOURCES@ and @STORE@ are audit-collector-install.sh's (system daemons, filled under
# sudo by its own render); this tool names them and leaves those plists alone.
#
# A TEMPLATE-ONLY BLOCK is dropped from the output. A comment that opens with `<!-- harbor:template-only` and runs to the
# first `-->` documents the template to someone reading the repo file and is not part of what gets installed, so adding
# or rewording one never makes an installed plist "differ" from its source. An unclosed block is an error, not a silent
# truncation of everything after it.
#
# WHAT THIS DOES NOT DO, ON PURPOSE. It writes to stdout and nowhere else. A session that can stand up its own scheduled job
# can stand up anything (the floor blocks a redirect into LaunchAgents, a cp naming it, and `launchctl load|bootstrap`), so
# installing stays the operator's act, from a terminal:
#   sh ~/port/harbor/bin/deploy-launchd-render.sh ~/port/harbor/launchd/com.harbor.audit.triage.plist > ~/Library/LaunchAgents/com.harbor.audit.triage.plist
#   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.harbor.audit.triage.plist
# Lint X9 renders the tracked plist before it compares it with the installed one, so a box whose plists were installed
# this way reads as in sync.
#
# platform: macOS-only — a launchd plist is macOS's; `plutil -lint` runs behind `command -v` and xmllint parses it where plutil is absent (harbor#618).
# exit 0 ok · 1 a template does not render (named, with the fix) · 2 usage or an unreadable file
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd -P)}}"
. "$SRC/library-log.sh"
LOG_FD=2; log_init launchd-render

# Filled by audit-collector-install.sh's render(), under sudo, into /Library/LaunchDaemons. Not this tool's.
FOREIGN="BIN SOURCES STORE"

usage() { sed -n '2,10p' "$SRC/deploy-launchd-render.sh" | sed 's/^# \{0,1\}//'; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/launchd-render.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM

# strip <plist> > out: the file without its template-only blocks. Exit 3 when one is never closed.
strip() {
  LC_ALL=C awk '
    /^[ \t]*<!-- harbor:template-only/ { skip = 1 }
    skip { if (index($0, "-->")) skip = 0; next }
    { print }
    END { if (skip) exit 3 }' "$1"
}

# names <file>: the distinct @NAME@ tokens, one per line.
names() { LC_ALL=C grep -o '@[A-Z][A-Z0-9_]*@' "$1" 2>/dev/null | sed 's/^@//; s/@$//' | LC_ALL=C sort -u || :; }

# one name per line; the old names of renamed rows too, which --get still answers until 2026-11-15 (harbor#961 W5)
known_roots() { sh "$SRC/scope-roots.sh" --list 2>/dev/null | awk 'NR > 1 { print $1 }'; sh "$SRC/scope-roots.sh" --aliases 2>/dev/null | cut -f1; }

is_foreign() { case " $FOREIGN " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# value_of <NAME>: the value on stdout, or non-zero with the reason on stderr. Absolute, one line, printable.
value_of() {
  case "$1" in
    HOME) _v="$(sh "$SRC/scope-roots.sh" --base BOX)" || return 1 ;;
    *)    _v="$(sh "$SRC/scope-roots.sh" --get "$1")" || return 1 ;;
  esac
  case "$_v" in /*) ;; *) echo "launchd-render: @$1@ resolves to '$_v', which is not an absolute path" >&2; return 1 ;; esac
  if [ -n "$(printf '%s' "$_v" | LC_ALL=C tr -d '[:print:]')" ]; then
    echo "launchd-render: @$1@ resolves to a value with a control character (TAB, newline), which a plist string cannot carry" >&2; return 1
  fi
  printf '%s' "$_v"
}

# render <plist>: the rendered plist on stdout. Returns 1 with the reason on stderr; prints nothing then.
render() {
  [ -f "$1" ] || { echo "launchd-render: no such file: $1" >&2; return 2; }
  _rs=0; strip "$1" > "$TMP/stripped" || _rs=$?
  [ "$_rs" -ne 3 ] || { echo "launchd-render: $1 opens a harbor:template-only comment that never closes with -->" >&2; return 1; }
  [ "$_rs" -eq 0 ] || { echo "launchd-render: could not read $1" >&2; return 2; }
  : > "$TMP/map"; _bad=0; _kr=" $(known_roots | tr '\n' ' ') HOME "
  for _n in $(names "$TMP/stripped"); do
    if is_foreign "$_n"; then
      echo "launchd-render: $1 holds @$_n@, which audit-collector-install.sh fills as root when it installs the system daemons; this tool does not render it" >&2; _bad=1; continue
    fi
    case "$_kr" in
      *" $_n "*) ;;
      *) echo "launchd-render: $1 holds @$_n@, which is neither HOME nor a variable in the roots table" >&2; _bad=1; continue ;;
    esac
    _val="$(value_of "$_n")" || { _bad=1; continue; }
    printf '%s\t%s\n' "$_n" "$_val" >> "$TMP/map"
  done
  [ "$_bad" -eq 0 ] || return 1
  # Substitution in awk, by index and not by regex replacement, so a value holding & or \ or | is written as it is.
  # & < > are XML-escaped: the value lands inside a plist string.
  LC_ALL=C awk -v map="$TMP/map" '
    function xesc(s,   o, i, c) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1)
      o = o (c == "&" ? "&amp;" : c == "<" ? "&lt;" : c == ">" ? "&gt;" : c) } return o }
    BEGIN { while ((getline l < map) > 0) { t = index(l, "\t"); val[substr(l, 1, t - 1)] = xesc(substr(l, t + 1)) } }
    { line = $0; out = ""
      while (match(line, /@[A-Z][A-Z0-9_]*@/)) {
        nm = substr(line, RSTART + 1, RLENGTH - 2)
        out = out substr(line, 1, RSTART - 1) ((nm in val) ? val[nm] : substr(line, RSTART, RLENGTH))
        line = substr(line, RSTART + RLENGTH)
      }
      print out line }' "$TMP/stripped"
}

# the templates this tool owns: every launchd/*.plist whose placeholders are not audit-collector-install.sh's
owned() { # → paths on stdout
  for _p in "$ROOT"/launchd/*.plist; do
    [ -f "$_p" ] || continue
    _f=0; for _n in $(names "$_p"); do is_foreign "$_n" && _f=1; done
    [ "$_f" -eq 1 ] || printf '%s\n' "$_p"
  done
}

xml_ok() { # <file> → 0 parses, 1 does not, 2 nothing here can parse it
  if command -v plutil >/dev/null 2>&1; then plutil -lint -s "$1" >/dev/null 2>&1; return $?; fi
  if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$1" >/dev/null 2>&1; return $?; fi
  return 2
}

MODE=render; ARGS=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --list) MODE=list ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) ARGS="$ARGS
$1" ;;
  esac
  shift
done

case "$MODE" in
  render)
    _cnt="$(printf '%s' "$ARGS" | grep -c . || :)"
    [ "$_cnt" -eq 1 ] || { usage >&2; exit 2; }
    _f="$(printf '%s' "$ARGS" | sed -n '2p')"
    render "$_f" > "$TMP/out" || exit $?
    cat "$TMP/out"
    ;;
  list)
    [ -z "$ARGS" ] || { usage >&2; exit 2; }
    for _n in HOME $(known_roots); do
      printf '%s\t%s\n' "$_n" "$(value_of "$_n")" || exit 1
    done
    ;;
  check)
    if [ -z "$ARGS" ]; then ARGS="
$(owned)"; fi
    _seen=0; _xml=2
    # an IFS of newline only: a path may hold a space
    _ifs="$IFS"; IFS='
'
    for _p in $ARGS; do
      IFS="$_ifs"
      [ -n "$_p" ] || continue
      _seen=$((_seen + 1)); _b="${_p##*/}"
      if ! render "$_p" > "$TMP/chk" 2> "$TMP/chk.err"; then
        log_fail "$_b does not render: $(tr '\n' ' ' < "$TMP/chk.err")"
        log_fix "fill its placeholders from the roots table, or use a variable contracts/roots.tsv names ($(known_roots | tr '\n' ' ')and HOME)"
        continue
      fi
      if grep -q '@[A-Z][A-Z0-9_]*@' "$TMP/chk"; then
        log_fail "$_b still holds an unfilled placeholder after rendering"; log_fix "sh bin/deploy-launchd-render.sh $_p | grep -n '@[A-Z]*@'"; continue
      fi
      if [ -n "$(tail -c1 "$_p")" ]; then
        log_fail "$_b does not end with a newline, so no rendering of it can equal the file launchd was given"; log_fix "add the final newline to $_p"; continue
      fi
      _x=0; xml_ok "$TMP/chk" || _x=$?
      if [ "$_x" -eq 1 ]; then log_fail "$_b renders to text that is not a valid plist"; log_fix "plutil -lint on: sh bin/deploy-launchd-render.sh $_p"; continue; fi
      [ "$_x" -ne 2 ] || _xml=0
      log_ok "$_b renders"
    done
    IFS="$_ifs"
    [ "$_seen" -gt 0 ] || { log_fail "no plist to check under $ROOT/launchd"; log_fix "pass a plist: sh bin/deploy-launchd-render.sh --check launchd/com.harbor.alert.probe.plist"; log_end || :; exit 1; }
    [ "$_xml" -eq 0 ] && log_note "neither plutil nor xmllint is installed here: the rendered text was not parsed as a plist"
    log_end || exit 1
    ;;
esac
