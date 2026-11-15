#!/usr/bin/env sh
# lint-suggest-table.sh (harbor#1485) — hold every row of a suggest-tool table to the contract before it can reach a person.
#
#   sh bin/lint-suggest-table.sh <table>...     one FAIL `<table>: <row>: <reason>` per finding
#
# Exit 0 clean, 1 a finding, 2 usage. lint.suggest-table runs it over the shipped table and the test fixture.
# REFUSES a row whose only discriminator is a generic tool or a bare extension (decision 24), any WebSearch row, an unanchored Bash
# recogniser, kind=mod with safe=yes, and a person's line with backticks, a path, a command word or more than MAX_WORDS words. The
# exact token /status-pane is allowed in kind=intro lines only. English words are left out of the command-word list on purpose
# (find, sort, make, watch): a line saying "find" is plain, and a false finding is a defect.
set -u
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
. "$SRC/library-log.sh"
log_init suggest-table
MAX_WORDS=25
HEADER='id	kind	tools	word	recogniser	quiet	line	switch_to	safe	install	requires	source'
case "${1:-}" in
  -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  '') printf 'usage: sh %s <table>...\n' "$0" >&2; exit 2 ;;
esac
_G=/usr/bin/grep; [ -x "$_G" ] || _G=grep
say() { log_fail "$1"; log_fix "correct the row, then: sh bin/lint-suggest-table.sh <table>"; }

for T in "$@"; do
  [ -f "$T" ] || { say "$T: -: no such table"; continue; }
  OUT="$(LC_ALL=C MAXW="$MAX_WORDS" HDR="$HEADER" awk -F'\t' '
    function bad(id, why) { printf "%s\t%s\n", id, why }
    # Every branch outside a group or a bracket has to start with ^, or `^a|b` matches inside an argument.
    function anchored(re,   i, c, d, br) {
      if (substr(re, 1, 1) != "^") return 0
      d = 0; br = 0
      for (i = 1; i <= length(re); i++) { c = substr(re, i, 1)
        if (c == "\\") { i++; continue }
        if (br) { if (c == "]" && substr(re, i - 1, 1) != "[") br = 0; continue }
        if (c == "[") { br = 1; continue }
        if (c == "(") d++
        else if (c == ")") d--
        else if (c == "|" && d == 0 && substr(re, i + 1, 1) != "^") return 0 }
      return 1 }
    function ere_portable(re) { return re !~ /\\[A-Za-z0-9]/ }
    function line_check(id, kind, line, word, sw,   n, w, i, t, m, x) {
      if (line == "-") { bad(id, "the person line is empty"); return }
      if (line ~ /^HARBOR-/) bad(id, "the person line starts like a sentinel")
      if (index(line, "`")) bad(id, "the person line holds a backtick")
      n = split(line, w, " ")
      if (n > ENVIRON["MAXW"] + 0) bad(id, "the person line is " n " words, the limit is " ENVIRON["MAXW"])
      for (i = 1; i <= n; i++) { t = w[i]
        gsub(/^[("\047]+|[).,;:!?"\047]+$/, "", t)
        if (index(t, "/")) {
          if (!(t == "/status-pane" && kind == "intro")) bad(id, "the person line holds a path: " t)
          continue }
        if (t ~ /^[~$]/ || t ~ /^--?[a-z]/ || index(t, "\\") || t ~ /[a-z0-9]\.[a-z0-9]/) bad(id, "the person line holds a path or a flag: " t)
        if (index(" " CMDS " ", " " t " ") || t == word) bad(id, "the person line holds a command word: " t)
        m = split(sw, x, " ")
        while (m > 0) { if (t == x[m] && sw != "-") bad(id, "the person line holds a command word: " t); m-- } } }
    BEGIN { CMDS = "sh bash zsh sudo git gh curl wget jq awk sed grep ls cd rm cp mv chmod chown mkdir npm npx node python python3 pip docker kubectl harbor" }
    /^#/ || NF == 0 { next }
    !hdr { hdr = 1; if ($0 != ENVIRON["HDR"]) bad("-", "the header is not the contract header"); next }
    { id = ($1 == "" ? "-" : $1) }
    NF != 12 { bad(id, "the row has " NF " cells, not 12"); next }
    { e = 0; for (i = 1; i <= 12; i++) if ($i == "") e = 1 }
    e { bad(id, "a cell is empty: write - for none"); next }
    length($1) > 27 || $1 !~ /^[a-z0-9][a-z0-9-]*$/ { bad(id, "the id is not ^[a-z0-9][a-z0-9-]{0,26}$") }
    seen[$1]++ { bad(id, "the id is repeated") }
    $2 !~ /^(verb|tool|skill|mod|intro)$/ { bad(id, "the kind is not verb, tool, skill, mod or intro"); next }
    $9 !~ /^(yes|no)$/ { bad(id, "safe is not yes or no") }
    $8 != "-" && $8 ~ /[^A-Za-z0-9._:\/@ -]/ { bad(id, "switch_to holds a character a tool name cannot") }
    $8 != "-" && split($8, _w, " ") > 4 { bad(id, "switch_to is a sentence, not a tool name") }
    $9 == "yes" && $8 == "-" { bad(id, "safe=yes needs a switch_to") }
    $9 == "yes" && $12 != "core" { bad(id, "only a core row can be safe") }
    $11 != "-" && ($11 !~ /^@(CFG|HOME)@\// || index($11, "..")) { bad(id, "requires is not @CFG@/... or @HOME@/...") }
    $12 !~ /^[a-z0-9][a-z0-9-]*$/ { bad(id, "the source is not core or a pack id") }
    $2 == "mod" && $9 == "yes" { bad(id, "a mod row cannot be safe") }
    $2 == "mod" && ($10 == "-" || $8 == "-") { bad(id, "a mod row needs install and the mod name in switch_to") }
    $2 != "mod" && $10 != "-" { bad(id, "only a mod row has install") }
    $2 == "skill" && ($8 == "-" || $8 !~ /^[A-Za-z0-9._-]+$/) { bad(id, "a skill row needs the skill name in switch_to") }
    { line_check(id, $2, $7, $4, $8) }
    $2 == "intro" {
      if ($3 != "-" || $4 != "-" || $5 != "-" || $6 != "-") bad(id, "an intro row has - in tools, word, recogniser and quiet")
      if ($9 != "no" || $8 != "-") bad(id, "an intro row is safe=no with no switch_to")
      next }
    $3 == "-" || $5 == "-" { bad(id, "tools and recogniser are - only for kind=intro"); next }
    { if (!ere_portable($5) || ($6 != "-" && !ere_portable($6))) bad(id, "an ERE uses a backslash class no grep agrees on") }
    index("|" $3 "|", "|WebSearch|") { bad(id, "a WebSearch row has no distinctive call to match"); next }
    index("|" $3 "|", "|Bash|") {
      if ($3 != "Bash") { bad(id, "a Bash row names Bash alone, its subject is not the others subject"); next }
      if ($4 == "-" || length($4) < 2 || $4 ~ /[^A-Za-z0-9._\/:@+ -]/) { bad(id, "a Bash row needs a literal word"); next }
      if (!anchored($5)) { bad(id, "the Bash recogniser is not anchored with ^ on every branch"); next }
      if ($5 !~ /^\^[A-Za-z0-9_(]/) bad(id, "the Bash recogniser does not name a command")
      if (!index($5, $4)) bad(id, "the word is not in the recogniser, so the row could never be reached the way it reads")
      next }
    $4 != "-" { bad(id, "only a Bash row has a word") }
    { n = split($3, tl, "|")
      for (i = 1; i <= n; i++) {
        if (tl[i] ~ /[^A-Za-z0-9_-]/) { bad(id, "the tool " tl[i] " is not a plain tool name"); continue }
        if (tl[i] ~ /^mcp__/) continue
        if (tl[i] !~ /^(Write|Edit|MultiEdit|NotebookEdit)$/) { bad(id, "the tool " tl[i] " is generic and has nothing distinctive to match"); continue }
        if ($5 !~ /(scratch|config|project|deliverables)/) bad(id, "a file tool with no place word matches a generic tool or a bare extension") } }
  ' "$T" 2>&1)"
  while IFS="$(printf '\t')" read -r _i _why; do
    [ -n "$_i" ] || continue
    say "$T: $_i: $_why"
  done <<FINDINGS
$OUT
FINDINGS
  # Every ERE compiles under the grep the rule runs it with: a row that cannot compile is a row that is silently never heard.
  _E="$(awk -F'\t' '/^#/ || NF != 12 || $1 == "id" { next } $5 != "-" { print $1 "\t" $5 } $6 != "-" { print $1 "\t" $6 }' "$T")"
  while IFS="$(printf '\t')" read -r _i _re; do
    [ -n "$_i" ] || continue
    printf 'x\n' | "$_G" -E -- "$_re" >/dev/null 2>&1
    if [ "$?" -gt 1 ]; then say "$T: $_i: an ERE does not compile"; fi
  done <<ERES
$_E
ERES
done
log_end; exit $?
