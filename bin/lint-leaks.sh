#!/usr/bin/env sh
# lint-leaks.sh (harbor#1149, D-79, D-85) - the leak gate: places in the tree that name a client, company, person or account.
#
#   sh lint-leaks.sh --count [core|private]  occurrences (not files); no argument prints both
#   sh lint-leaks.sh --list                  each one as file:line:pattern-id, for local triage
#   sh lint-leaks.sh --check                 the ratchet: red if core is above contracts/lint-leaks-baseline.txt, or
#                                               private is above <private>/leaks-baseline.txt (when that file exists);
#                                               green but says to lower the baseline when below
#   sh lint-leaks.sh --zero                  red on any match from any source; the gate for `harbor deploy push`
#
# Patterns, three sources. core: contracts/leak-patterns.tsv (tracked, generic, names no real entity).
# private: $HARBOR_SCOPE_PRIVATE/leaks.tsv (id TAB kind TAB pattern TAB note; kind is literal, word, domain,
# email-domain or regex) and the client and system rows of its terms.tsv, matched as whole words, any case.
# An absent private layer is not an error; a malformed file is a finding (exit 1) and its bad rows are skipped.
# Allow-list: a core row of kind allow (id, allow, "<pattern-id>=<exact matched text>", note) forgives that exact match
# of that core pattern anywhere, so a placeholder like /Users/probe/ is not a leak. Case-sensitive, whole match, core only;
# an allow row in the private layer is a finding, and so is one whose text matches a private pattern or names the
# operator (LEAKS_OWN_USER overrides id -un and $HOME): it is skipped and forgives nothing. Remove the row and the placeholder counts again (harbor#1149).
# PRIVACY: no mode prints a private pattern's text, only its id (a terms.tsv row is named terms.tsv:L<line>).
# Scope: every tracked file plus untracked ones git does not ignore, minus tests, fixtures, evals and
# skills/test-strength/targets, as lint-siblings.sh. The ratchets count that whole tracked tree, never narrowed by
# layers.tsv, so a client name regrowing in a dev-only file is still counted (harbor#1149).
# LEAKS_EXPORT=1 is the write gate (deploy push, pack install) over a staging checkout holding exactly the files to be
# written: no exclusions, no layers.tsv narrowing, binary or .gitattributes-marked files scanned as text (harbor#1149).
# It also counts the running user's name (LEAKS_OWN_USER, else id -un and $HOME's last part) as ~<user>, -Users-<user>,
# -home-<user> or a home path with no trailing slash, as core id own-user; no name is written here (harbor#1149).
# A word or domain ends at any character that is not a letter or digit, so X_<word>_LT and <domain>-x match (harbor#1149).
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
BASE="${LEAKS_BASELINE:-$ROOT/contracts/lint-leaks-baseline.txt}"
CORE="${LEAKS_CORE_PATTERNS:-$ROOT/contracts/leak-patterns.tsv}"
PRIV="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
PRIV="${PRIV%/}"
. "$SRC/library-log.sh"
log_init lint-leaks
LOG_FD=2

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint-leaks.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT INT TERM
: > "$TMP/core.hits"; : > "$TMP/private.hits"; : > "$TMP/findings"; : > "$TMP/rows"; : > "$TMP/allow"; : > "$TMP/allow.rows"

# rows <file> <src> <mode>: print "R<TAB>id<TAB>kind<TAB>pattern" per good row and "E<TAB>message" per bad one.
# mode pat reads id,kind,pattern,note; mode terms reads a terms.tsv and keeps the client and system rows.
rows() {
  awk -F'\t' -v mode="$3" -v src="$2" '
    function bad(m) { printf "E\t%s line %d: %s\n", src, FNR, m }
    FNR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, length("\357\273\277") + 1) }  # 1 char to gawk in UTF-8
    { sub(/\r$/, "") }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    !hdr {
      hdr = 1
      if (mode == "pat") { if ($0 != "id\tkind\tpattern\tnote") { printf "E\t%s line %d: the header is not id, kind, pattern, note\n", src, FNR; stop = 1 } }
      else { for (i = 1; i <= NF; i++) { if ($i == "id") ci = i; if ($i == "class") cc = i }
             if (!ci || !cc) { printf "E\t%s line %d: the header has no id and class columns\n", src, FNR; stop = 1 }; nf = NF }
      next
    }
    stop { next }
    mode == "pat" {
      if (NF != 4) { bad("expected 4 columns, got " NF); next }
      if ($1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) { bad("the id is not [A-Za-z0-9][A-Za-z0-9._-]*"); next }
      if ($1 in seen) { bad("repeats the id of line " seen[$1]); next }
      seen[$1] = FNR
      if ($2 == "allow" && src != "leak-patterns.tsv") { bad("kind allow is for the core file only"); next }
      if ($2 !~ /^(literal|word|domain|email-domain|regex|allow)$/) { bad("kind " $2 " is not literal, word, domain, email-domain, regex or allow"); next }
      if ($2 == "allow" && $3 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*=./) { bad("an allow pattern is <pattern-id>=<exact matched text>"); next }
      if ($3 == "") { bad("the pattern is empty"); next }
      printf "R\t%s\t%s\t%s\n", $1, $2, $3; next
    }
    {
      if (NF != nf) { bad("expected " nf " columns, got " NF); next }
      n = split($cc, C, ","); keep = 0
      for (i = 1; i <= n; i++) if (C[i] == "client" || C[i] == "system") keep = 1
      if (!keep) next
      if ($ci == "") { bad("the id is empty"); next }
      printf "R\tterms.tsv:L%d\tword\t%s\n", FNR, $ci
    }' "$1"
}

# esc: an ERE-safe copy of a literal, read from stdin.
esc() { sed 's/[.[\*^$(){}?+|]/\\&/g'; }

# gg <git grep flags>: the scan. LEAKS_EXPORT=1 scans every tracked file as text (-a: a NUL or a binary attribute hides nothing); no --untracked there, which would skip a tracked file a .gitignore matches (harbor#1149).
gg() {
  if [ "${LEAKS_EXPORT:-0}" = 1 ]; then git -C "$ROOT" grep -a -n -o "$@" -- . 2>/dev/null; return 0; fi
  git -C "$ROOT" grep -I --untracked -n -o "$@" -- . \
      ':!tests/**' ':!fixtures/**' ':!evals/**' ':!**/tests/**' ':!**/fixtures/**' ':!**/evals/**' ':!skills/test-strength/targets/**' 2>/dev/null || return 0
}

# mkre <kind> <pattern>: sets _hf (grep flags) and _hp (the ERE or fixed string) for one pattern row.
# `_` ends a word and `-` ends a domain: X_<client>_LT and <domain>-x-<CODE> are hits (harbor#1149). own is internal, never a file kind.
mkre() {
  case "$1" in
    literal) _hf="-F -i"; _hp="$2" ;;
    word) _hf="-E -i"; _hp="(^|[^A-Za-z0-9])$(printf '%s' "$2" | esc)(\$|[^A-Za-z0-9])" ;;
    domain) _hf="-E -i"; _hp="(^|[^A-Za-z0-9-])$(printf '%s' "$2" | esc)(\$|[^A-Za-z0-9])" ;;
    email-domain) _hf="-E -i"; _hp="$(printf '%s' "$2" | esc)(\$|[^A-Za-z0-9_-])" ;;
    regex) _hf="-E"; _hp="$2" ;;
    own) _hf="-E -i"; _hp="$2" ;;
  esac
}

# own_names: sets _own to the operator's user names, LEAKS_OWN_USER or else id -un and the last part of $HOME.
own_names() { _h="${HOME:-}"; _own="${LEAKS_OWN_USER-$(id -un 2>/dev/null || :) ${_h##*/}}"; }

# own_rows: export mode only. One core row per user name for the forms home-path misses: ~<user>, the -Users-<user> and
# -home-<user> of an encoded project dir, and /Users/<user> or /home/<user> with no trailing slash (that one is home-path's).
own_rows() {
  own_names; _done=' '
  for _n in $_own; do
    case "$_n" in home|Users|root|tmp|var) continue ;; esac  # a directory name, not a person
    case "$_done" in *" $_n "*) continue ;; esac; _done="$_done$_n "  # id -un and $HOME usually agree: count once
    _e="$(printf '%s' "$_n" | esc)"; _c="$(printf '%s' "$_n" | tr -c 'A-Za-z0-9' '-' | esc)"
    printf 'core\town-user\town\t~%s($|[^A-Za-z0-9._-])|-(Users|home)-%s($|[^A-Za-z0-9])|/(Users|home)/%s($|[^A-Za-z0-9._/-])\n' "$_e" "$_c" "$_e" >> "$TMP/rows"
  done
}

# hits <id> <kind> <pattern> <bucket> → file:line:id per occurrence on stdout. The pattern text goes to git only.
# A core hit whose exact match is in $TMP/allow as "<id>=<text>" is dropped (the allow-list, harbor#1149).
hits() {
  mkre "$2" "$3"
  # git grep, not grep: grep here is ugrep and skips gitignored files. -o prints the match; only file:line is kept.
  # shellcheck disable=SC2086
  gg $_hf -e "$_hp" |
    awk -F: -v id="$1" -v bucket="$4" -v allow="$TMP/allow" '
      BEGIN { if (bucket == "core") while ((getline a < allow) > 0) ok[a] = 1 }
      { m = $0; sub(/^[^:]*:[^:]*:/, "", m); if ((id "=" m) in ok) next
        printf "%s:%s:%s\n", $1, $2, id }' |
    cat || :
}

# load <file> <src> <mode> <bucket>: rows into $TMP/rows as bucket TAB id TAB kind TAB pattern; findings to $TMP/findings.
load() {
  [ -f "$1" ] || return 0
  rows "$1" "$2" "$3" > "$TMP/r.out"
  while IFS='	' read -r tag a b c; do
    case "$tag" in
      E) printf '%s\n' "$a" >> "$TMP/findings" ;;
      R) if [ "$b" = allow ]; then printf '%s\t%s\n' "$a" "$c" >> "$TMP/allow.rows"
         elif [ "$b" = regex ] && { printf '' | grep -E -e "$c" >/dev/null 2>&1; [ $? -eq 2 ]; }; then
           printf '%s: the regex of %s does not compile\n' "$2" "$a" >> "$TMP/findings"
         else printf '%s\t%s\t%s\t%s\n' "$4" "$a" "$b" "$c" >> "$TMP/rows"; fi ;;
    esac
  done < "$TMP/r.out"
}

# check_allow: an allow row may forgive a placeholder only. One whose text matches a private-layer pattern, or names
# the operator (LEAKS_OWN_USER, default: id -un and the last part of $HOME), is a finding and forgives nothing, and its
# own line then counts as a hit. Findings name the allow row and the private pattern id, never a pattern's text.
check_allow() {
  : > "$TMP/allow"
  [ -s "$TMP/allow.rows" ] || return 0
  own_names
  while IFS='	' read -r _aid _ent; do
    _txt="${_ent#*=}"; _why=""
    for _n in $_own; do
      case "$_n" in home|Users|root|tmp|var) continue ;; esac  # a directory name, not a person
      if printf '%s\n' "$_txt" | grep -i -E -e "(^|[^A-Za-z0-9_.-])$(printf '%s' "$_n" | esc)([^A-Za-z0-9_.-]|\$)" >/dev/null 2>&1; then _why="the operator's own user name"; break; fi
    done
    if [ -z "$_why" ]; then
      while IFS='	' read -r _b _pid _k _pat; do
        [ "$_b" = private ] || continue
        mkre "$_k" "$_pat"
        # shellcheck disable=SC2086
        if printf '%s\n' "$_txt" | grep $_hf -e "$_hp" >/dev/null 2>&1; then _why="private pattern $_pid"; break; fi
      done < "$TMP/rows"
    fi
    if [ -n "$_why" ]; then printf 'leak-patterns.tsv: allow row %s would forgive %s, so it forgives nothing\n' "$_aid" "$_why" >> "$TMP/findings"
    else printf '%s\n' "$_ent" >> "$TMP/allow"; fi
  done < "$TMP/allow.rows"
}

collect() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-leaks.sh"; log_end || :; exit 2; }
  if [ ! -f "$CORE" ]; then log_fail "no core patterns at ${CORE#$ROOT/}"; log_fix "restore contracts/leak-patterns.tsv"; log_end || :; exit 1; fi
  load "$CORE" "leak-patterns.tsv" pat core
  if [ -d "$PRIV" ]; then
    load "$PRIV/leaks.tsv" "leaks.tsv" pat private
    load "$PRIV/terms.tsv" "terms.tsv" terms private
  fi
  check_allow
  [ "${LEAKS_EXPORT:-0}" != 1 ] || own_rows
  while IFS='	' read -r bucket id kind pat; do
    hits "$id" "$kind" "$pat" "$bucket" >> "$TMP/$bucket.hits"
  done < "$TMP/rows"
  sort -o "$TMP/core.hits" "$TMP/core.hits"; sort -o "$TMP/private.hits" "$TMP/private.hits"
  NCORE="$(wc -l < "$TMP/core.hits" | tr -d ' ')"; NPRIV="$(wc -l < "$TMP/private.hits" | tr -d ' ')"
  NFIND="$(wc -l < "$TMP/findings" | tr -d ' ')"
}

# findings: a malformed pattern file is a finding, never silence.
report_findings() {
  [ "$NFIND" -gt 0 ] || return 0
  while IFS= read -r _f; do log_fail "$_f"; done < "$TMP/findings"
  log_fix "correct the file; its bad rows were skipped, so the count is a lower bound (contracts/private-layer.md)"
}

base_of() { grep -vE '^[[:space:]]*(#|$)' "$1" 2>/dev/null | head -1 | tr -d ' ' || :; }

# ratchet <label> <got> <baseline file> <fix>
ratchet() {
  _w="$(base_of "$3")"
  case "$_w" in ''|*[!0-9]*) log_fail "no numeric $1 baseline in $(basename "$3")"; log_fix "write the current count (sh bin/lint-leaks.sh --count $1) into it"; return 1 ;; esac
  if [ "$2" -gt "$_w" ]; then
    log_fail "$2 $1 leak occurrence(s) in the tree, baseline is $_w"; log_fix "$4"
    __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
    cut -d: -f1 "$TMP/$1.hits" | sort -u | while IFS= read -r f; do
      case "
$__chg
" in *"
$f
"*) log_note "changed and holds a $1 leak: $f" ;; esac
    done
    return 1
  elif [ "$2" -lt "$_w" ]; then
    log_ok "$2 $1 occurrence(s), under the baseline of $_w"; log_note "lower $(basename "$3") to $2 so the gain is kept"
  else
    log_ok "$2 $1 leak occurrence(s), equal to the baseline"
  fi
}

case "${1:-}" in
  --count) collect >&2
           case "${2:-}" in
             core) echo "$NCORE" ;; private) echo "$NPRIV" ;;
             '') printf 'core\t%s\nprivate\t%s\n' "$NCORE" "$NPRIV" ;;
             *) echo "lint-leaks: --count takes core or private" >&2; exit 2 ;;
           esac
           [ "$NFIND" -eq 0 ] || { report_findings; log_end || :; exit 1; } ;;
  --list)  collect >&2; cat "$TMP/core.hits" "$TMP/private.hits" | sort
           [ "$NFIND" -eq 0 ] || { report_findings; log_end || :; exit 1; } ;;
  --check)
    collect; RC=0
    report_findings; [ "$NFIND" -eq 0 ] || RC=1
    ratchet core "$NCORE" "$BASE" "name no real entity in the tree; real names live in the private layer (contracts/private-layer.md)" || RC=1
    if [ ! -d "$PRIV" ]; then log_note "no private layer at the private path: private patterns not checked"
    elif [ -f "$PRIV/leaks-baseline.txt" ]; then ratchet private "$NPRIV" "$PRIV/leaks-baseline.txt" "move the named client, company or account out of the tracked file into the private layer" || RC=1
    else log_note "no leaks-baseline.txt in the private layer: private count ($NPRIV) not ratcheted"; fi
    log_end || :; exit $RC ;;
  --zero)
    collect; RC=0
    report_findings; [ "$NFIND" -eq 0 ] || RC=1
    [ -d "$PRIV" ] || log_note "no private layer: only the core patterns were checked"
    if [ $((NCORE + NPRIV)) -gt 0 ]; then
      log_fail "$NCORE core and $NPRIV private leak occurrence(s); the export gate needs zero"
      log_fix "sh bin/lint-leaks.sh --list names each file:line and pattern id"; RC=1
    else log_ok "zero leak occurrences"; fi
    log_end || :; exit $RC ;;
  -h|--help|help|'') sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-leaks: unknown argument '$1'" >&2; exit 2 ;;
esac
