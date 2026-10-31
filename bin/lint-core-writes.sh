#!/usr/bin/env sh
# lint-core-writes.sh (harbor#1275, harbor#1149) - the ratchet on core scripts that write into the checkout at runtime.
# The core tree is read-only at runtime: what a run produces belongs in the user's state directory or private layer, because
# an untracked file at the root of a harbor-core clone is one `git add -A` away from a PR.
#
#   sh lint-core-writes.sh --count    the number of hits: (file, target) pairs, not occurrences
#   sh lint-core-writes.sh --list     each hit as file TAB target (the path under the tree, "<root>" when it is the tree itself)
#   sh lint-core-writes.sh --check    red if the count is above contracts/lint-core-writes-baseline.txt;
#                                       green but says to lower the baseline when it is below
#
# A WRITE is, on a non-comment line of a core shell script, a redirect (> >>), tee, touch, mkdir, or the last argument of
# mv, cp, install or ln, whose target is $ROOT or $HARBOR_SCOPE_ROOT, or a variable the same file assigns from a path under one
# of them (NAME="$ROOT/x", NAME="${V:-$ROOT/x}"). Not a hit: a target .gitignore covers (it cannot be staged), a file the core
# export tracks (a diff, reviewed like any edit), a mkdir of a directory the tree tracks. Not followed: a path built through a
# variable that copies $ROOT (B=$ROOT; "$B/x").
# Scope: tracked and untracked-not-ignored files of layer core (bin/scope-layers.sh --core), outside tests/, fixtures/, vendor/,
# docs/ (they act on fixture trees or are text); .sh files and files with an sh shebang. Writers in Python or TypeScript are
# not seen. Allowed: contracts/core-writes-allow.tsv (path TAB target or * TAB reason), the reason required.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
ALLOW="${CORE_WRITES_ALLOW:-$ROOT/contracts/core-writes-allow.tsv}"
BASE="${CORE_WRITES_BASELINE:-$ROOT/contracts/lint-core-writes-baseline.txt}"
. "$SRC/library-log.sh"
log_init lint-core-writes
LOG_FD=2
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT

rows() { # <file> → its data rows: CR stripped, comments and blanks dropped, header dropped
  [ -f "$1" ] || return 0
  sed 's/\r$//' "$1" | grep -vE '^[[:space:]]*(#|$)' | sed 1d
}

# A register that does not parse refuses the run (exit 2): a skipped row would read as "nothing to find".
valid() {
  rows "$ALLOW" | awk -F'\t' -v f="${ALLOW#$ROOT/}" '
    NF < 3 || $1 == "" || $2 == "" || $3 == "" { print "lint-core-writes: " f ": a row needs a path, a target and a reason: " $0 > "/dev/stderr"; bad = 1 }
    END { exit bad ? 2 : 0 }' || return 2
}

# The awk finds candidate writes; the ignore test needs git, so it runs after, on the literal path under the tree.
CAND='
function isname(c) { return c ~ /[A-Za-z0-9_]/ }
function lit(s,   i, c, r) { # the literal prefix of a path word: up to a quote, space, paren, semicolon or $
  r = ""
  for (i = 1; i <= length(s); i++) { c = substr(s, i, 1); if (c ~ /["\x27 \t);|&$`}]/) break; r = r c }
  return r
}
function try(s, n,   re, rest, p) { # s starts at a word: is it $n or ${n} followed by "/path", an end, or a quote?
  re = "^[\"\x27]?\\$\\{?" n "\\}?"
  if (s !~ re) return "\001"
  rest = s; sub(re, "", rest)
  if (rest != "" && rest !~ /^[\/"\x27 \t);|&]/) return "\001"
  if (rest ~ /^\//) { sub(/^\//, "", rest); return lit(rest) }
  return ""
}
function resolve(s,   n, r) { # a word naming a tree path: the literal path under the tree, or "\001" when it names none
  for (n in N) { r = try(s, n); if (r != "\001") return (N[n] == "" ? r : N[n] r) }
  return "\001"
}
FNR == 1 { delete N; N["ROOT"] = ""; N["HARBOR_SCOPE_ROOT"] = ""; N["HARBOR_ROOT"] = "" }
/^[ \t]*#/ { next }
{
  line = $0
  # harbor#961 W5: the dual read ${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-}} names the tree as either name does, until 2026-11-15
  gsub(/\$\{HARBOR_SCOPE_ROOT:-\$\{HARBOR_ROOT(:-)?\}\}/, "$HARBOR_SCOPE_ROOT", line)
  # A variable assigned from a path under the tree. The right-hand side may nest it: NAME="${V:-$ROOT/x}".
  ns = split(line, SEG, ";")
  for (k = 1; k <= ns; k++) {
    seg = SEG[k]
    if (match(seg, /^[ \t]*(export +|local +|readonly +)?[A-Za-z_][A-Za-z0-9_]*=/)) {
      lhs = substr(seg, 1, RLENGTH - 1); sub(/^[ \t]*(export +|local +|readonly +)?/, "", lhs)
      rhs = substr(seg, RLENGTH + 1); sub(/;.*/, "", rhs)
      # A ROOT that is not derived from the own place of the script (gcloud-creds: ~/.config/gcloud) is not the tree.
      if (lhs == "ROOT") { if (rhs ~ /(\.\.|pwd|HARBOR_SCOPE_ROOT|HARBOR_ROOT|rev-parse|HERE|SRC|\$0)/) N["ROOT"] = ""; else if (rhs !~ /^["\x27]*$/) delete N["ROOT"] }
      if (lhs != "ROOT" && lhs != "HARBOR_SCOPE_ROOT" && lhs != "HARBOR_ROOT" && match(rhs, /^["\x27]?(\$\{[A-Za-z_0-9]+:-)?\$\{?(ROOT|HARBOR_SCOPE_ROOT|HARBOR_ROOT)\}?\//)) {
        w = rhs; sub(/^["\x27]?(\$\{[A-Za-z_0-9]+:-)?/, "", w); r = resolve(w)
        if (r != "\001" && r != "") N[lhs] = r
      }
    }
  }
  # redirects: > or >> (not >& and not a comparison inside [[ ]]: those do not occur in sh)
  s = line
  while (match(s, /[^>&]>>?[ \t]*["\x27]?\$/)) {
    w = substr(s, RSTART + 1); sub(/^>>?[ \t]*/, "", w); r = resolve(w)
    if (r != "\001") print FILENAME "\t" (r == "" ? "<root>" : r)
    s = substr(s, RSTART + RLENGTH)
  }
  # words after a writing verb: tee, touch and mkdir write to every argument, mv cp install ln to the last
  sub(/^[ \t]+/, "", line); nw = split(line, W, /[ \t]+/)
  for (i = 1; i <= nw; i++) {
    v = W[i]; sub(/^.*[;|&(`]/, "", v)
    # only at command position: the first word, after a separator, or after then/do/else/!/{
    if (i > 1 && W[i] == v && W[i-1] !~ /([;|&(`]|^then|^do|^else|^!|^\{)$/) continue
    if (v != "tee" && v != "touch" && v != "mkdir" && v != "mv" && v != "cp" && v != "install" && v != "ln") continue
    last = ""
    for (j = i + 1; j <= nw; j++) {
      t = W[j]
      if (j > i + 1 && W[j-1] ~ /(\$\(|`)/) continue   # an argument of a command substitution (dirname "$OUT"), not of the verb
      if (t ~ /^(;|\|\||&&|&|\||>|>>)$/ || t ~ /^[0-9]?>/) break
      end = (t ~ /[;|&]$/); sub(/[;|&)]+$/, "", t)
      if (t !~ /^-/ && t != "") {
        if (v == "tee" || v == "touch" || v == "mkdir") { r = resolve(t); if (r != "\001") print FILENAME "\t" (r == "" ? "<root>" : r) (v == "mkdir" && r != "" ? "/" : "") }
        else last = t
      }
      if (end) break
    }
    if (last != "") { r = resolve(last); if (r != "\001") print FILENAME "\t" (r == "" ? "<root>" : r) }
  }
}'

hits() { # file TAB target, one line per pair, sorted
  ( cd "$ROOT" && git ls-files --cached --others --exclude-standard ) | sort -u |
    HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-layers.sh" --core |
    grep -vE '^(tests|fixtures|vendor|docs)/' | grep -vE '\.(md|html|tsv|txt|json|jsonl|csv|py|ts|js|mjs)$' > "$T/files" || :
  : > "$T/code"
  while IFS= read -r f; do
    case "$f" in *.sh) ;; *) head -1 "$ROOT/$f" 2>/dev/null | grep -qE '^#!.*(sh|bash|zsh)( |$)' || continue ;; esac
    printf '%s\n' "$f"
  done < "$T/files" > "$T/code"
  ( cd "$ROOT" && [ ! -s "$T/code" ] || xargs awk "$CAND" < "$T/code" ) | sort -u > "$T/cand"
  ( cd "$ROOT" && git ls-files ) | HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-layers.sh" --core > "$T/tcore" || :
  while IFS="$(printf '\t')" read -r f p; do
    # A file the core export tracks is rewritten as a diff, reviewed like any edit: never a stray untracked file.
    if grep -qxF -- "$p" "$T/tcore"; then continue; fi
    # Not a hit if the tree's .gitignore covers the path (the literal part of it, checked as written).
    if [ "$p" != "<root>" ] && git -C "$ROOT" check-ignore -q -- "$p" 2>/dev/null; then continue; fi
    # A mkdir (path ends in /) of a directory the tree already tracks changes nothing.
    case "$p" in */) [ -z "$(git -C "$ROOT" ls-files -- "$p" | head -1)" ] || continue ;; esac
    printf '%s\t%s\n' "$f" "$p"
  done < "$T/cand" > "$T/raw"
  rows "$ALLOW" > "$T/allow"
  awk -F'\t' -v allow="$T/allow" '
    BEGIN { while ((getline l < allow) > 0) { n++; split(l, F, "\t"); AP[n] = F[1]; AT[n] = F[2] } }
    { for (i = 1; i <= n; i++)
        if ((AT[i] == "*" || AT[i] == $2) && (substr(AP[i], length(AP[i])) == "/" ? index($1, AP[i]) == 1 : $1 == AP[i])) next
      print }' "$T/raw" | sort -u
}

need_git() { git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }

case "${1:-}" in
  --count) need_git || { echo "lint-core-writes: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits | wc -l | tr -d ' ' ;;
  --list)  need_git || { echo "lint-core-writes: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits ;;
  --check)
    need_git || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-core-writes.sh"; log_end || :; exit 2; }
    valid || { log_fail "a register does not parse, nothing was counted"; log_fix "correct the rows named above"; log_end || :; exit 2; }
    WANT="$(grep -vE '^[[:space:]]*(#|$)' "$BASE" 2>/dev/null | head -1 | tr -d ' ')" || WANT=""
    case "$WANT" in ''|*[!0-9]*) log_fail "no numeric baseline in ${BASE#$ROOT/}"; log_fix "write the current count (sh bin/lint-core-writes.sh --count) into it"; log_end || :; exit 1 ;; esac
    hits > "$T/hits"; GOT="$(wc -l < "$T/hits" | tr -d ' ')"
    if [ "$GOT" -gt "$WANT" ]; then
      log_fail "$GOT core file(s)-and-target pair(s) write into the tree, baseline is $WANT"
      log_fix "write to the state directory (sh bin/scope-roots.sh, \${HARBOR_STATUS_DIR:-\$HOME/.local/state/harbor}) or a gitignored path, or allow-list it in ${ALLOW#$ROOT/} with a reason (harbor#1275)"
      # The delta, not the census: files this branch touched that hold a hit.
      __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
      cut -f1 "$T/hits" | sort -u | while IFS= read -r f; do
        case "
$__chg
" in *"
$f
"*) log_note "changed and writes into the tree: $f ($(awk -F'\t' -v f="$f" '$1 == f { printf "%s%s", s, $2; s = "," }' "$T/hits"))" ;; esac
      done
    elif [ "$GOT" -lt "$WANT" ]; then
      log_ok "$GOT pair(s), under the baseline of $WANT"
      log_note "lower ${BASE#$ROOT/} to $GOT so the gain is kept"
    else
      log_ok "$GOT pair(s) of core script writing into the tree, equal to the baseline"
    fi
    log_end ;;
  -h|--help|help|'') sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-core-writes: unknown argument '$1'" >&2; exit 2 ;;
esac
