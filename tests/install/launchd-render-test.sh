#!/usr/bin/env sh
# launchd-render.sh (harbor#630): the plists in launchd/ name no home, and what they render to follows the roots table.
# A render that could not fail would make every plist "equal" its install, so the negative cases come first.
. "$(dirname "$0")/../lib/core.sh"; t_init
X="$T_ROOT/bin/launchd-render.sh"
# NOT `VAR=x render …`: a prefix assignment on a shell function can outlive the call, and the first version of this suite
# compared a render with itself because of it. Every override below goes through `env … sh "$X"`.
render() { sh "$X" "$@"; }

t_section "a fixture template: placeholders filled, a template-only block dropped, nothing else touched"
FX="$T_TMP/fx"; mkdir -p "$FX"
printf '%s\n' '<?xml version="1.0"?>' \
  '<!-- harbor:template-only' '     do not cp this: it is documentation for the repo file' '     @HOME@ is named here and must not be needed -->' \
  '<!-- kept: replace @HOME@ with your home -->' \
  '<string>@HOME@/.claude/bin/x.sh</string>' \
  '<key>PATH</key><string>/usr/bin:@HARBOR_LOCAL_BIN@</string>' '</plist>' > "$FX/ok.plist"
printf '%s\n' '<?xml version="1.0"?>' \
  '<!-- kept: replace '"$HOME"' with your home -->' \
  '<string>'"$HOME"'/.claude/bin/x.sh</string>' \
  '<key>PATH</key><string>/usr/bin:'"$HOME"'/.local/bin</string>' '</plist>' > "$FX/ok.want"
render "$FX/ok.plist" > "$FX/ok.got"
t_eq "the output is the filled file, byte for byte" "$(cat "$FX/ok.want")" "$(cat "$FX/ok.got")"
t_eq "…including its last newline" "$(wc -c < "$FX/ok.want" | tr -d ' ')" "$(wc -c < "$FX/ok.got" | tr -d ' ')"
t_hasnt "the template-only block is not in the output" "$(cat "$FX/ok.got")" "template-only"
printf '<plist>\n<string>/usr/bin</string>\n</plist>\n' > "$FX/plain.plist"
render "$FX/plain.plist" > "$FX/plain.got"
t_eq "a plist with no placeholder (a private layer's job) passes through unchanged" "$(cksum < "$FX/plain.plist")" "$(cksum < "$FX/plain.got")"

t_section "what it refuses, and that it prints nothing when it does"
printf '<string>@NOPE@/x</string>\n' > "$FX/unknown.plist"
t_exit "a placeholder that is no root is refused" 1 sh -c 'sh "$1" "$2" > "$3" 2>"$4"' sh "$X" "$FX/unknown.plist" "$FX/o.out" "$FX/o.err"
t_has "…naming it" "$(cat "$FX/o.err")" '@NOPE@'
t_eq "…and writing nothing to stdout" "" "$(cat "$FX/o.out")"
printf '<string>@BIN@/collector.sh</string>\n' > "$FX/foreign.plist"
t_exit "collector-setup.sh's placeholders are not this tool's" 1 sh -c 'sh "$1" "$2" > "$3" 2>"$4"' sh "$X" "$FX/foreign.plist" "$FX/o.out" "$FX/o.err"
t_has "…and it says whose they are" "$(cat "$FX/o.err")" 'collector-setup.sh'
printf '<!-- harbor:template-only\n     never closed\n<string>@HOME@</string>\n</plist>\n' > "$FX/unclosed.plist"
t_exit "an unclosed template-only block is an error, not a silent truncation" 1 sh -c 'sh "$1" "$2" > "$3" 2>"$4"' sh "$X" "$FX/unclosed.plist" "$FX/o.out" "$FX/o.err"
t_has "…saying so" "$(cat "$FX/o.err")" 'never closes'
t_eq "…with nothing on stdout" "" "$(cat "$FX/o.out")"
t_exit "a missing file is exit 2" 2 sh -c 'sh "$1" "$2" >/dev/null 2>&1' sh "$X" "$FX/absent.plist"
t_exit "no argument is a usage error" 2 sh -c 'sh "$1" >/dev/null 2>&1' sh "$X"
t_exit "two files are a usage error" 2 sh -c 'sh "$1" "$2" "$2" >/dev/null 2>&1' sh "$X" "$FX/ok.plist"
t_exit "a relative HOME is refused" 1 sh -c 'HOME=relative/dir sh "$1" "$2" >/dev/null 2>&1' sh "$X" "$FX/ok.plist"
t_exit "with HOME unset there is no home to write" 1 sh -c 'env -u HOME sh "$1" "$2" >/dev/null 2>&1' sh "$X" "$FX/ok.plist"

t_section "a value is written as it is: & < > | and a backslash survive, and the XML stays well-formed"
ODD="$T_TMP/o&d|h<o>m\\e"
printf '<string>@HOME@/x</string>\n' > "$FX/odd.plist"
t_eq "XML-escaped, nothing eaten as a sed or awk metacharacter" '<string>'"$T_TMP"'/o&amp;d|h&lt;o&gt;m\e/x</string>' "$(env HOME="$ODD" sh "$X" "$FX/odd.plist")"

t_section "the real templates: no operator home in any of them, and every one renders"
t_eq "no tracked plist spells a home directory" "" "$(grep -n -E '/Users/[A-Za-z]|/home/[A-Za-z]' "$T_ROOT"/launchd/*.plist || true)"
t_eq "…nor spells ~/.local/bin in a value: that root comes from the table (@HARBOR_LOCAL_BIN@), or moving it would miss the plist" "" "$(grep -n -E '<string>[^<]*/\.local/bin' "$T_ROOT"/launchd/*.plist || true)"
_owned=0; for _p in "$T_ROOT"/launchd/*.plist; do grep -q '@\(BIN\|SOURCES\|STORE\)@' "$_p" || _owned=$((_owned + 1)); done
# Not a census: plists leave core for packs (harbor#1273), so any found is the control, and --check below counts them.
t_eq "positive control: the templates this tool owns were found" yes "$([ "$_owned" -ge 1 ] && echo yes || echo no)"
_chk="$(sh "$X" --check 2>&1)"; _rc=$?
t_eq "--check is green on the tree" 0 "$_rc"
t_has "…and says how many it rendered" "$_chk" "launchd-render: $_owned ok, 0 failed"
t_eq "the collector's system-daemon plists are left to collector-setup.sh" 0 "$(printf '%s\n' "$_chk" | grep -c 'collector\|otlp')"
t_has "--list names HOME and a root of the table" "$(sh "$X" --list)" "HARBOR_LOCAL_BIN	$HOME/.local/bin"

t_section "--check can fail: an unknown placeholder, a missing newline, an unclosed block"
t_exit "an unknown placeholder fails the check" 1 sh -c 'sh "$1" --check "$2" >/dev/null 2>&1' sh "$X" "$FX/unknown.plist"
t_has "…saying which file and what" "$(sh "$X" --check "$FX/unknown.plist" 2>&1)" 'unknown.plist does not render'
printf '<string>@HOME@</string>' > "$FX/nonl.plist"
t_exit "a template with no final newline fails the check" 1 sh -c 'sh "$1" --check "$2" >/dev/null 2>&1' sh "$X" "$FX/nonl.plist"
t_exit "an unclosed block fails the check" 1 sh -c 'sh "$1" --check "$2" >/dev/null 2>&1' sh "$X" "$FX/unclosed.plist"
printf '<?xml version="1.0"?><plist><dict></plist>\n' > "$FX/broken.plist"
if command -v plutil >/dev/null 2>&1 || command -v xmllint >/dev/null 2>&1; then
  t_exit "text that renders but is not a plist fails the check" 1 sh -c 'sh "$1" --check "$2" >/dev/null 2>&1' sh "$X" "$FX/broken.plist"
else
  printf 'SKIP: neither plutil nor xmllint here, so the parse arm of --check is NOT exercised\n'
fi

t_section "the table decides: change one root in a copy of it and every plist that names it changes (harbor#630)"
sed 's|^\(HARBOR_LOCAL_BIN[[:space:]]*BOX[[:space:]]*\)\.local/bin|\1.local/moved-bin|' "$T_ROOT/CONTRACTS/roots.tsv" > "$T_TMP/roots-moved.tsv"
t_eq "positive control: the copy really differs from the table" 1 "$(diff "$T_ROOT/CONTRACTS/roots.tsv" "$T_TMP/roots-moved.tsv" | grep -c '^>')"
MV="$T_TMP/moved"; ST="$T_TMP/same"; mkdir -p "$MV" "$ST"
_hit=0; _miss=0; _wrong=""
for _p in "$T_ROOT"/launchd/*.plist; do
  grep -q '@\(BIN\|SOURCES\|STORE\)@' "$_p" && continue
  _b="${_p##*/}"
  render "$_p" > "$ST/$_b"
  env HARBOR_ROOTS_TABLE="$T_TMP/roots-moved.tsv" sh "$X" "$_p" > "$MV/$_b"
  if grep -q '@HARBOR_LOCAL_BIN@' "$_p"; then
    _hit=$((_hit + 1))
    cmp -s "$ST/$_b" "$MV/$_b" && _wrong="$_wrong $_b(did-not-move)"
    t_has "$_b: the moved root is in its PATH" "$(cat "$MV/$_b")" "$HOME/.local/moved-bin"
    t_hasnt "$_b: …and the old one is gone" "$(cat "$MV/$_b")" "$HOME/.local/bin"
  else
    _miss=$((_miss + 1))
    cmp -s "$ST/$_b" "$MV/$_b" || _wrong="$_wrong $_b(moved-without-naming-it)"
  fi
done
t_eq "every plist that names the root moved, none that does not" "" "$_wrong"
t_eq "positive control: some plists name HARBOR_LOCAL_BIN" yes "$([ "$_hit" -ge 5 ] && echo yes || echo no)"
t_eq "positive control: some do not (the check is not vacuous)" yes "$([ "$_miss" -ge 1 ] && echo yes || echo no)"
t_eq "the only lines that moved are the ones holding the root" "" "$(diff -r "$ST" "$MV" | grep '^[<>]' | grep -v 'moved-bin\|\.local/bin' || true)"

t_section "the home decides: another HOME changes every plist, and none keeps the old one"
H2="$T_TMP/elsewhere/h2"; mkdir -p "$H2"; SAME2="$T_TMP/h2"; mkdir -p "$SAME2"; _unmoved=""; _kept=""
for _p in "$T_ROOT"/launchd/*.plist; do
  grep -q '@\(BIN\|SOURCES\|STORE\)@' "$_p" && continue
  _b="${_p##*/}"
  env HOME="$H2" sh "$X" "$_p" > "$SAME2/$_b"
  cmp -s "$ST/$_b" "$SAME2/$_b" && _unmoved="$_unmoved $_b"
  grep -q -F "$T_TMP/home" "$SAME2/$_b" && _kept="$_kept $_b"
done
t_eq "every plist changed with HOME" "" "$_unmoved"
t_eq "none keeps the first HOME" "" "$_kept"

t_section "no template tells the reader to cp it unless it carries the block that says not to"
_bare=""
for _p in "$T_ROOT"/launchd/*.plist; do
  grep -q '@\(BIN\|SOURCES\|STORE\)@' "$_p" && continue
  if grep -q -E '(^|[[:space:]])cp (bin|launchd)/' "$_p" && ! grep -q 'harbor:template-only' "$_p"; then _bare="$_bare ${_p##*/}"; fi
done
t_eq "a cp line sits only in a file with its template-only warning" "" "$_bare"
t_done
