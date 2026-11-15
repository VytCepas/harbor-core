# bin/lint-locale-ranges.awk — find locale-dependent bracket ranges in sh `case` patterns (harbor#1149).
#
#   LC_ALL=C awk -f bin/lint-locale-ranges.awk <file>...      prints  file TAB line TAB col TAB endcol TAB [bracket]
#
# WHY. In a shell `case` pattern a bracket range follows the locale's collation, not ASCII. On this Mac
# (en_NZ.UTF-8, /bin/sh is bash) letters interleave aAbB..., so `[!a-z0-9-]` lets capitals through, `[A-Z]` matches
# most lowercase letters and `[!!-~]` rejects ordinary ASCII; dash in the C locale on the CI runner does not. The
# same file is then right in one place and wrong in the other.
#
# WHAT IS FLAGGED: a bracket expression, in a case-pattern word (an unquoted word closed by `)` or `|`), holding
# a range that is not digit-to-digit and not a letter range with its other-case twin in the same bracket.
# `[!A-Za-z0-9_-]` is clean (a-z and A-Z together cover every letter in either collation); `[!a-z]`, `[0-9a-f]`,
# `[A-Z]` and `[!-~]` are not. Quoted text, comments and heredoc bodies are skipped, so an awk, grep or sed regex in
# quotes is never judged here: those engines are not the shell's pattern matcher.
# LIMIT: a shell-aware scan in awk is not a parser. It tracks '…', "…", $(…), `#` comments and heredocs, and
# misses a case pattern built by eval or held in a variable.
# case words opened and not yet closed in out[from..]: a `)` while one is open ends a pattern, not the $( )
function opencases(t, from,   a, b) {
  t = substr(t, from + 1); a = t; b = t
  return gsub(/(^|[ \t;|&({])case[ \t]/, "&", a) - gsub(/(^|[ \t;|&])esac([ \t;)|&]|$)/, "&", b)
}
function badbr(s,   i, n, c, lo, hi, k, m, L, U, bad) {
  n = length(s); i = 1; bad = 0
  if (substr(s, 1, 1) == "!" || substr(s, 1, 1) == "^") i = 2
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") { i += 2; continue }
    if (c == "[" && substr(s, i + 1, 1) == ":") { m = index(substr(s, i + 2), ":]"); if (m) { i += m + 3; continue } }
    if (substr(s, i + 1, 1) == "-" && i + 2 <= n) {
      lo = c; hi = substr(s, i + 2, 1)
      if (lo ~ /[0-9]/ && hi ~ /[0-9]/) { }
      else if (lo ~ /[a-z]/ && hi ~ /[a-z]/) L[lo hi] = 1
      else if (lo ~ /[A-Z]/ && hi ~ /[A-Z]/) U[lo hi] = 1
      else bad = 1
      i += 3; continue
    }
    i++
  }
  for (k in L) if (!(toupper(k) in U)) bad = 1
  for (k in U) if (!(tolower(k) in L)) bad = 1
  return bad
}
FNR == 1 {
  # a file is shell if it is named *.sh or its first line is a sh-family shebang
  isSh = (FILENAME ~ /\.sh$/) || ($0 ~ /^#!.*(\/|[ ])(ba|da|z)?sh([ ]|$)/)
  st = ""; hd = ""; sp = 0
}
!isSh { next }
{
  line = $0
  if (hd != "") { t = line; if (hdd) sub(/^\t+/, "", t); if (t == hd) hd = ""; next }
  out = ""; n = length(line); i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (st == "s") { if (c == "'") st = ""; out = out "Q"; i++; continue }
    if (st == "d" && c == "$" && substr(line, i + 1, 1) == "(") { sp++; stk[sp] = "d"; pc[sp] = 1; nc[sp] = 0; op[sp] = length(out) + 2; st = ""; out = out "QQ"; i += 2; continue }
    if (st == "d") { if (c == "\\") { out = out "QQ"; i += 2; continue } if (c == "\"") st = ""; out = out "Q"; i++; continue }
    if (c == "$" && substr(line, i + 1, 1) == "(") { sp++; stk[sp] = ""; pc[sp] = 1; nc[sp] = 0; op[sp] = length(out) + 2; out = out "$("; i += 2; continue }
    if (sp > 0 && c == "(") pc[sp]++
    if (sp > 0 && c == ")" && pc[sp] == 1 && nc[sp] + opencases(out, op[sp]) > 0) { out = out c; i++; continue }
    if (sp > 0 && c == ")") { pc[sp]--; if (pc[sp] == 0) { st = stk[sp]; sp--; if (st == "d") { out = out "Q"; i++; continue } } }
    if (c == "\\") { out = out "QQ"; i += 2; continue }
    if (c == "'") { st = "s"; out = out "Q"; i++; continue }
    if (c == "\"") { st = "d"; out = out "Q"; i++; continue }
    if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;|&(]/)) break
    out = out c; i++
  }
  if (match(out, /<<-?[ \t]*\\?[A-Za-z_Q]+/)) {   # the delimiter is read from the unmasked line
    rest = substr(line, RSTART); hdd = (rest ~ /^<<-/)
    sub(/^<<-?[ \t]*/, "", rest); gsub(/^[\\'"]+/, "", rest); sub(/[^A-Za-z0-9_].*$/, "", rest)
    if (rest != "") hd = rest
  }
  for (k = 1; k <= sp; k++) { nc[k] += opencases(out, op[k]); op[k] = 0 }
  n = length(out); i = 1
  while (i <= n) {
    if (substr(out, i, 1) != "[") { i++; continue }
    j = i + 1
    if (substr(out, j, 1) == "!" || substr(out, j, 1) == "^") j++
    if (substr(out, j, 1) == "]") j++
    while (j <= n && substr(out, j, 1) != "]") {
      if (substr(out, j, 2) == "[:") { m = index(substr(out, j + 2), ":]"); if (m) { j += m + 3; continue } }
      j++
    }
    if (j > n) { i++; continue }
    body = substr(out, i + 1, j - i - 1)
    if (badbr(body)) {
      r = j + 1; while (r <= n && substr(out, r, 1) !~ /[ \t;|&()]/) r++
      if (substr(out, r, 1) == ")" || substr(out, r, 1) == "|") printf "%s\t%d\t%d\t%d\t[%s]\n", FILENAME, FNR, i, j, substr(line, i + 1, j - i - 1)
    }
    i = j + 1
  }
}
