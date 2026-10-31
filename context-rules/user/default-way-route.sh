#!/usr/bin/env sh
# default-way-route.sh (harbor#1397) — a Write, Edit or Bash call that builds a harbor-shaped thing the way Claude Code
# allows by default (a skill into ~/.claude/skills, a hook into settings.json, a job into LaunchAgents) draws a note
# naming harbor's home for it and its install route. The kinds are rows of default-way-route.tsv beside this file.
# A note, never a decision: the HARBOR-DECISION sentinel appears nowhere below.
#
# FAIL-OPEN: no jq, no registry, a payload with no path or command, or no matching row prints nothing and exits 0.
set -u
command -v jq >/dev/null 2>&1 || exit 0
HERE="${0%/*}"; [ "$HERE" != "$0" ] || HERE=.
REGF="$HERE/default-way-route.tsv"
[ -f "$REGF" ] || exit 0
P="$(cat)"
[ -n "$P" ] || exit 0
TOOL="$(printf '%s' "$P" | jq -r '.tool_name // empty | strings' 2>/dev/null)" || exit 0
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
CFGP="$(CDPATH= cd -- "$CFG" 2>/dev/null && pwd -P)" || CFGP="$CFG"
HOMEP="$(CDPATH= cd -- "$HOME" 2>/dev/null && pwd -P)" || HOMEP="$HOME"

case "$TOOL" in
  Write|Edit)
    TARGET="$(printf '%s' "$P" | jq -r '.tool_input.file_path // empty | strings' 2>/dev/null)" || exit 0
    [ -n "$TARGET" ] || exit 0
    case "$TARGET" in /*) ;; *) TARGET="${CLAUDE_PROJECT_DIR:-$PWD}/$TARGET" ;; esac
    BODY="$(printf '%s' "$P" | jq -r '(.tool_input.content // .tool_input.new_string // "") | strings' 2>/dev/null | head -c 262144)"
    CMD='' ;;
  Bash)
    BODY="$(printf '%s' "$P" | jq -r '.tool_input.command // empty | strings' 2>/dev/null | head -c 262144)"
    [ -n "$BODY" ] || exit 0
    # A heredoc body is data, not a command (the strip name-note-create.sh does); BODY keeps it for `content`.
    # The first 16 KB is judged: the quote mask walks it a character at a time, and a hook must stay cheap.
    CMD="$(printf '%s\n' "$BODY" | awk '
      /<<-?[ ]*['\''"]?[A-Za-z_][A-Za-z0-9_]*['\''"]?/ && !skip {
        t = $0; sub(/^.*<<-?[ ]*/, "", t); gsub(/['\''"]/, "", t); sub(/[^A-Za-z0-9_].*$/, "", t)
        if (t != "") { term = t; skip = 1; print; next }
      }
      skip { s = $0; gsub(/^[ \t]+|[ \t]+$/, "", s); if (s == term) skip = 0; next }
      { print }' | head -c 16384)"
    TARGET='' ;;
  *) exit 0 ;;
esac

# The first matching row, as kind<TAB>home<TAB>install<TAB>reason<TAB>shown path<TAB>name; nothing when none matches.
HIT="$(TOOL="$TOOL" TARGET="$TARGET" CMD="$CMD" BODY="$BODY" CFG="$CFG" CFGP="$CFGP" H="$HOME" HP="$HOMEP" awk -F'\t' '
  function esc(s,   o, c, i) { o = ""; for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (index("\\^$.[]|()*+?{}", c)) o = o "\\" c; else o = o c }; return o }
  # A glob as an anchored ERE: `*` is part of one segment, and anything below the match counts.
  function globre(g,   o, c, i) { o = ""; for (i = 1; i <= length(g); i++) { c = substr(g, i, 1); if (c == "*") o = o "[^/]*"; else o = o esc(c) }; return o }
  function under(p, base, g,   pre) { pre = base "/"; if (index(p, pre) != 1) return ""; p = substr(p, length(pre) + 1)
    if (p ~ ("^" globre(g) "(/.*)?$")) return p
    # A Bash target may be the directory the last `*` segment sits in (`cp -R x ~/.claude/skills/`).
    if (BASHMODE && g ~ /\/\*[^\/]*$/) { d = g; sub(/\/[^\/]*$/, "", d); sub(/\/$/, "", p); if (p ~ ("^" globre(d) "$")) return p "/" }
    return "" }
  function judge(p, rec,   g, r) {
    if (rec ~ /^cfg:/)  { g = substr(rec, 5); r = under(p, ENVIRON["CFG"], g);  if (r == "" && ENVIRON["CFGP"] != ENVIRON["CFG"]) r = under(p, ENVIRON["CFGP"], g); if (r != "") { SHOWN = p; NAMEOF = r; return 1 } }
    if (rec ~ /^home:/) { g = substr(rec, 6); r = under(p, ENVIRON["H"], g);    if (r == "" && ENVIRON["HP"] != ENVIRON["H"]) r = under(p, ENVIRON["HP"], g);    if (r != "") { SHOWN = p; NAMEOF = r; return 1 } }
    return 0 }
  # A shell word as an absolute path: quotes dropped, ~ $HOME ${HOME} $CLAUDE_CONFIG_DIR spelled out.
  function expand(w) { gsub(/["\047]/, "", w)
    if (w ~ /^~\//) w = ENVIRON["H"] substr(w, 2)
    else if (w ~ /^\$HOME\//) w = ENVIRON["H"] substr(w, 6)
    else if (w ~ /^\$\{HOME\}\//) w = ENVIRON["H"] substr(w, 8)
    else if (w ~ /^\$CLAUDE_CONFIG_DIR\//) w = ENVIRON["CFG"] substr(w, 19)
    else if (w ~ /^\$\{CLAUDE_CONFIG_DIR\}\//) w = ENVIRON["CFG"] substr(w, 21)
    else if (w == "~") w = ENVIRON["H"]
    return w }
  # Every path a command WRITES, one per element of TG[1..NT]: redirect and tee targets, mkdir touch and sed -i
  # operands, and the last operand of a copy or of sed -i. Segments split on ; && || | and newlines.
  # Quoted text is literal: its operators, blanks and newlines become _ so a quoted > or ; neither redirects nor splits.
  function mask(c,   o, ch, i, q) { o = ""; q = ""
    for (i = 1; i <= length(c); i++) { ch = substr(c, i, 1)
      if (q == "" && ch == "\\") { o = o ch substr(c, i + 1, 1); i++; continue }
      if (q == "\"" && ch == "\\") { o = o "__"; i++; continue }
      if (q == "" && (ch == "\047" || ch == "\"")) q = ch
      else if (ch == q) q = ""
      else if (q != "" && index("><|;&( )\t\n", ch)) ch = "_"
      o = o ch }
    return o }
  # A relative target is resolved against the last absolute `cd` or `pushd` of the command, and dropped without one,
  # as is a word that is not a plain path (`&1`, `$S/x`).
  function at(w,   x) { x = expand(w); if (x ~ /^\//) return x
    if (CWD == "" || x !~ /^[A-Za-z0-9_.@%+-][A-Za-z0-9_.\/@%+-]*$/) return ""; return CWD "/" x }
  function targets(cmd,   segs, ns, s, seg, w, nw, i, v, j, last) { NT = 0; CWD = ""; cmd = mask(cmd)
    gsub(/&&|\|\||;|\|/, "\n", cmd); ns = split(cmd, segs, "\n")
    for (s = 1; s <= ns; s++) { seg = segs[s]; gsub(/[0-9&]?>>?/, " & ", seg); nw = split(seg, w, /[ \t]+/)
      v = ""; j = 0
      for (i = 1; i <= nw; i++) { if (w[i] == "") continue
        if (w[i] ~ /^[0-9&]?>>?$/) { if (i < nw) TG[++NT] = at(w[i + 1]); i++; continue }
        if (v == "") { if (w[i] ~ /^(sudo|env|command|nohup|time|\(|[A-Za-z_][A-Za-z0-9_]*=.*)$/) continue; v = w[i]; sub(/^.*\//, "", v); continue }
        if (w[i] ~ /^-/) continue
        if (v ~ /^(cd|pushd)$/) { CWD = at(w[i]); v = "cd-done"; continue }
        if (v ~ /^(tee|mkdir|touch)$/) TG[++NT] = at(w[i])
        else if (v ~ /^(cp|mv|ln|rsync|install|ditto|sed|perl)$/) last = w[i] }
      # sed -i and perl -i write their last operand; the words before it are the script, which may quote any path.
      if (v ~ /^(sed|perl)$/ && seg !~ /[ \t](-[A-Za-z]*i|--in-place)/) last = ""
      if (v ~ /^(cp|mv|ln|rsync|install|ditto|sed|perl)$/ && last != "") TG[++NT] = at(last)
      last = "" } }
  NR == 1 { next }
  /^#/ || NF < 8 { next }
  { if (("|" $2 "|") !~ ("\\|" ENVIRON["TOOL"] "\\|")) next
    if ($5 != "-" && ENVIRON["TOOL"] == "Bash" && ENVIRON["CMD"] ~ $5) next
    if ($4 != "-" && ENVIRON["BODY"] !~ $4) next
    hit = 0; SHOWN = ""; NAMEOF = ""; BASHMODE = (ENVIRON["TOOL"] == "Bash")
    if ($3 ~ /^cmd:/) { if (BASHMODE) { c = mask(ENVIRON["CMD"]); gsub(/&&|\|\||;|\|/, "\n", c); n = split(c, cs, "\n")
        for (k = 1; k <= n && !hit; k++) if (cs[k] ~ substr($3, 5)) { hit = 1; SHOWN = cs[k]; gsub(/^[ \t(]+|[ \t)]+$/, "", SHOWN) } } }
    else if (!BASHMODE) hit = judge(ENVIRON["TARGET"], $3)
    else { if (!DONE) { targets(ENVIRON["CMD"]); DONE = 1 }; for (k = 1; k <= NT && !hit; k++) hit = judge(TG[k], $3) }
    if (!hit) next
    # {name}: the segment the first `*` matched (`skills/*` and `skills/foo/SKILL.md` give foo).
    g = $3; sub(/^[a-z]+:/, "", g); ng = split(g, gs, "/"); ix = 0; for (k = 1; k <= ng && !ix; k++) if (index(gs[k], "*")) ix = k
    split(NAMEOF, parts, "/"); nm = (ix ? parts[ix] : ""); if (nm == "") nm = "<name>"
    sh = SHOWN; if (index(sh, ENVIRON["H"] "/") == 1) sh = "~" substr(sh, length(ENVIRON["H"]) + 1)
    printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $6, $7, $8, sh, nm; exit }
' "$REGF" 2>/dev/null)" || exit 0
[ -n "$HIT" ] || exit 0

TAB="$(printf '\t')"
IFS="$TAB" read -r KIND HOMEDIR INSTALL REASON SHOWN NAME <<EOF
$HIT
EOF
# The checkout the home is relative to: the registry's harbor row beside this pack when the box has one.
ROOT="$(awk -F'\t' '$1 == "harbor" { print $2; exit }' "$HERE/projects.tsv" 2>/dev/null)"
[ -n "$ROOT" ] || ROOT='your harbor checkout'
sub_name() { printf '%s' "$1" | awk -v n="$NAME" '{ while ((i = index($0, "{name}")) > 0) $0 = substr($0, 1, i - 1) n substr($0, i + 6); print }'; }
printf '%s\n' "Default-way check (harbor#1397, advisory, the call was not blocked). \`$SHOWN\` is where Claude Code puts a $KIND by default, and harbor builds it in $ROOT instead: $(sub_name "$HOMEDIR"). It reaches the box by: $(sub_name "$INSTALL"). Why: $REASON. If this is a deliberate box-only change, say so in your answer and carry on."
exit 0
