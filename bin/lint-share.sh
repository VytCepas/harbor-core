#!/usr/bin/env sh
# lint-share.sh (harbor#1274, harbor#1149, D-83) - the share check: a file lives in a share its kind may take.
#
#   sh lint-share.sh --list     each judged file as: path TAB share TAB kind ids TAB the share set its kinds allow
#   sh lint-share.sh --count    the number of files whose share is outside that set
#   sh lint-share.sh --check    WARN per such file, exit 0 (warn mode); --strict makes any warning exit 1
#
# A file's share comes from where it lives: the harbor checkout is core where contracts/layers.tsv marks the path core (dev
# and unlisted paths are not exported and have no share, so are not judged); the private layer (scope-roots.sh --private) is
# personal, and its hub/ folder hub; a registered workload repo's harbor-pack/ (scope-roots.sh --conf packs) is workload.
# Its kind is read from standards/naming/kinds.tsv: every kind whose folder is a prefix of the path (case-folded, a
# <placeholder> and what follows cut off); the set allowed is the union of those kinds' share cells. No kind, not judged.
# --tree DIR=SHARE adds a tree to judge (tests, and a layer outside the registry). Cannot read the registers: exit 2.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
KINDS="${SHARE_KINDS:-$ROOT/standards/naming/kinds.tsv}"
. "$SRC/library-log.sh"
log_init lint-share
LOG_FD=2
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT
MODE="${1:-}"; [ "$#" -eq 0 ] || shift
STRICT=0; : > "$T/trees"   # one per line: dir TAB share TAB label
while [ "$#" -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --tree) case "${2:-}" in ?*=?*) printf '%s\t%s\t%s\n' "${2%=*}" "${2##*=}" "tree" >> "$T/trees" ;; *) echo "lint-share: --tree wants DIR=SHARE" >&2; exit 2 ;; esac; shift ;;
    *) echo "lint-share: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done

# folder TAB the share cell, for every kind that has a repo folder
kinds() {
  [ -f "$KINDS" ] || { echo "lint-share: no ${KINDS#$ROOT/}" >&2; return 2; }
  sed 's/\r$//' "$KINDS" | grep -vE '^[[:space:]]*(#|$)' | awk -F'\t' '
    NR == 1 { for (i = 1; i <= NF; i++) { if ($i == "id") ci = i; if ($i == "folder") cf = i; if ($i == "share") cs = i }
              if (!ci || !cf || !cs) { print "lint-share: kinds.tsv has no id, folder and share column" > "/dev/stderr"; bad = 1; exit }; next }
    { n = split($cs, S, ","); if (n == 0 || $cs == "") { print "lint-share: kind " $ci " has no share" > "/dev/stderr"; bad = 1 }
      for (i = 1; i <= n; i++) if (S[i] !~ /^(core|hub|workload|personal)$/) { print "lint-share: kind " $ci ": " S[i] " is not core, hub, workload or personal" > "/dev/stderr"; bad = 1 }
      if ($cf == "-") next
      f = tolower($cf); sub(/<.*/, "", f); if (f != "") print f "\t" $cs "\t" $ci }
    END { exit bad ? 2 : 0 }'
}

# <dir> → its files, relative; a git checkout lists tracked and untracked-not-ignored, any other dir is walked
files_of() {
  if git -C "$1" rev-parse --git-dir >/dev/null 2>&1; then git -C "$1" ls-files -co --exclude-standard
  else ( cd "$1" && find . -type f -not -path './.git/*' | sed 's|^\./||' ); fi
}

gather() { # → path TAB share, every file that has a share
  files_of "$ROOT" | HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-layers.sh" --classify | awk -F'\t' '$2 == "core" { print $1 "\tcore" }'
  _pv="$(HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-roots.sh" --private 2>/dev/null)" || _pv=""
  if [ -n "$_pv" ] && [ -d "$_pv" ]; then
    files_of "$_pv" | awk '{ print ($0 ~ /^hub\// ? "private:" $0 "\thub" : "private:" $0 "\tpersonal") }'
    HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-roots.sh" --conf packs 2>/dev/null | tr ',[]"' '    ' | tr -s ' ' '\n' | grep -v '^$' | while IFS= read -r _id; do
      _rd="$(HARBOR_SCOPE_ROOT="$ROOT" sh "$SRC/scope-roots.sh" --repo "$_id" 2>/dev/null)" || continue
      [ -d "$_rd/harbor-pack" ] && files_of "$_rd/harbor-pack" | awk -v id="$_id" '{ print "pack:" id ":" $0 "\tworkload" }'
    done
  fi
  while IFS="$(printf '\t')" read -r _d _s _l; do
    [ -d "$_d" ] && files_of "$_d" | awk -v s="$_s" '{ print $0 "\t" s }'
  done < "$T/trees"
  return 0
}

# path TAB share → the judged rows: path TAB share TAB kind ids TAB allowed set TAB ok|out
judge() {
  gather | awk -F'\t' -v kf="$T/kinds" '
    BEGIN { while ((getline l < kf) > 0) { split(l, F, "\t"); n++; P[n] = F[1]; S[n] = F[2]; K[n] = F[3] } }
    { p = $1; sub(/^private:/, "", p); if (p ~ /^pack:/) sub(/^pack:[^:]*:/, "", p); sub(/^hub\//, "", p)
      q = tolower(p); ids = ""; set = ""
      for (i = 1; i <= n; i++)
        if (substr(P[i], length(P[i])) == "/" ? index(q, P[i]) == 1 : q == P[i]) {
          ids = ids (ids == "" ? "" : ",") K[i]
          m = split(S[i], A, ","); for (j = 1; j <= m; j++) if (index("," set ",", "," A[j] ",") == 0) set = set (set == "" ? "" : ",") A[j]
        }
      if (ids == "") next
      print $1 "\t" $2 "\t" ids "\t" set "\t" (index("," set ",", "," $2 ",") ? "ok" : "out") }'
}

kinds > "$T/kinds" || exit 2
case "$MODE" in
  --list)  judge | cut -f1-4 ;;
  --count) judge | awk -F'\t' '$5 == "out"' | wc -l | tr -d ' ' ;;
  --check)
    judge > "$T/judged" || { log_fail "could not judge, nothing was inspected"; log_nofix "bin/lint-share.sh"; log_end || :; exit 2; }
    awk -F'\t' '$5 == "out"' "$T/judged" > "$T/out"
    while IFS="$(printf '\t')" read -r _p _s _k _a _; do
      log_warn "[lint.share] $_p — share $_s is not in {$_a}, the set of kind $_k"
    done < "$T/out"
    _n="$(wc -l < "$T/out" | tr -d ' ')"; _t="$(wc -l < "$T/judged" | tr -d ' ')"
    if [ "$_n" -eq 0 ]; then log_ok "$_t file(s) of a known kind, each in a share its kind allows"
    else log_note "$_n of $_t judged file(s) live in a share their kind does not allow (warn: harbor#1274)"; fi
    log_end || :
    [ "$STRICT" -eq 0 ] || [ "$_n" -eq 0 ] || exit 1 ;;
  -h|--help|help|'') sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-share: unknown argument '$MODE'" >&2; exit 2 ;;
esac
