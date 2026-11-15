#!/usr/bin/env sh
# standard-label-sync.sh (harbor#1427) — label-axes.tsv is the only label source: this plans what makes a repo's labels equal it.
#
#   sh bin/standard-label-sync.sh [--repo OWNER/NAME]...          the plan, read only (the default): the dry run
#   sh bin/standard-label-sync.sh --apply [--remove-retired]      execute the plan on GitHub (a person's step: nothing runs it)
#   sh bin/standard-label-sync.sh --check                         the scheduled check: the labels outside the register as a delta and ages
#   options: --registry DIR (default standards/naming) · --gh PATH · --config-dir DIR · --today YYYY-MM-DD
#
# THE REGISTER is `lint-name.sh --gen labels` (the families terms.tsv derives and every label row of label-axes.tsv), the
# RENAMES are label-axes.tsv's `legacy` column (a rename keeps the issues that carry the label), the RETIRED are
# label-retired.tsv. A live label is one of: registered (nothing to do) · a legacy name (rename, or merge into the
# registered label when both exist) · retired (remove, only with --apply --remove-retired) · unregistered (a finding, never
# touched: add its register row, its legacy mapping or a retired row). A registered label that is missing is created.
# Without --repo the repos are the ones scope-roots.sh --repos lists that declare a repo-kind and have a github origin.
#
# --check is check id standard.label-registered: the report is the delta and the ages, never the census; state in
# <config>/cache/standard-label-registered.tsv, receipt <config>/cache/checks/standard.label-registered.json (fresh 9
# days), one [check:...] line in checks.log when something changed. The plan is the check's remedy: the same engine without
# --check is control check.label-sync (manual, corrective).
#
# Exit 0 nothing to do (--check: nothing new) · 1 a plan line or unregistered label (--check: a new finding) · 2 usage ·
# 3 unchecked: no repo could be read. Only --apply writes to GitHub; --check writes only under <config>/cache.
set -u
LC_ALL=C; export LC_ALL

case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$_SRC/.." && pwd)}"
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init standard-label-sync
ID="standard.label-registered"
MODE=plan; REMOVE=0; GH="gh"; REG="$ROOT/standards/naming"; CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; TODAY=""; REPOS=""
TAB="$(printf '\t')"

usage_err() { log_fail "$1"; log_fix "sh bin/standard-label-sync.sh --help"; log_end || :; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || usage_err "--repo takes OWNER/NAME"; REPOS="$REPOS $2"; shift 2 ;;
    --registry) [ $# -ge 2 ] || usage_err "--registry takes a directory"; REG="$2"; shift 2 ;;
    --gh) [ $# -ge 2 ] || usage_err "--gh takes a path"; GH="$2"; shift 2 ;;
    --config-dir) [ $# -ge 2 ] || usage_err "--config-dir takes a directory"; CFG="$2"; shift 2 ;;
    --today) [ $# -ge 2 ] || usage_err "--today takes YYYY-MM-DD"; TODAY="$2"; shift 2 ;;
    --apply) MODE=apply; shift ;;
    --check) MODE=check; shift ;;
    --remove-retired) REMOVE=1; shift ;;
    -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
    *) usage_err "unknown argument: $1" ;;
  esac
done
[ "$REMOVE" = 0 ] || [ "$MODE" = apply ] || usage_err "--remove-retired only goes with --apply"
for _s in $REPOS; do case "$_s" in */*) ;; *) usage_err "--repo takes OWNER/NAME, not: $_s" ;; esac; done
[ -n "$TODAY" ] || TODAY="$(date -u +%Y-%m-%d)"
case "$TODAY" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) usage_err "--today takes YYYY-MM-DD, not: $TODAY" ;; esac
[ -r "$REG/label-axes.tsv" ] || usage_err "no label-axes.tsv under $REG"

T="$(mktemp -d "${TMPDIR:-/tmp}/standard-label-sync.XXXXXX")" || usage_err "cannot make a temp dir"
trap 'rm -rf "$T"' EXIT INT TERM HUP

# ── the register ─────────────────────────────────────────────────────────────
mkdir -p "$T/root"
if ! sh "$ROOT/bin/lint-name.sh" --gen labels --root "$T/root" --registry "$REG" > "$T/gen.out" 2> "$T/gen.err" || [ ! -s "$T/root/build/naming/labels.tsv" ]; then
  log_fail "[check:$ID] the register could not be generated (unchecked)"; log_fix "sh bin/lint-name.sh --gen labels"; log_end || :; exit 3
fi
grep -v -e '^#' -e '^name	' "$T/root/build/naming/labels.tsv" > "$T/register"
# legacy -> label, from the rows that are labels and whose legacy name differs from the label
awk -F'\t' '/^#/ || !H[FILENAME]++ { next } $3 != "-" && $4 != "-" && $4 != $1 { print $4 "\t" $1 }' "$REG/label-axes.tsv" > "$T/map"
if [ -r "$REG/label-retired.tsv" ]; then grep -v -e '^#' -e '^id	' "$REG/label-retired.tsv" | cut -f1 > "$T/retired"; else : > "$T/retired"; fi

# ── the repos ────────────────────────────────────────────────────────────────
if [ -z "$REPOS" ]; then
  sh "$ROOT/bin/scope-roots.sh" --repos 2>/dev/null | grep -v '^#' | while IFS="$TAB" read -r _n _p; do
    case "$_p" in "~/"*) _p="$HOME/${_p#\~/}" ;; esac
    [ -d "$_p/.git" ] || continue
    grep -q '^repo-kind:' "$_p/.agents/config.yaml" 2>/dev/null || continue
    git -C "$_p" remote get-url origin 2>/dev/null | sed -n -e 's#^.*github\.com[:/]##' -e 's#\.git$##p'
  done > "$T/repos"
else
  for _s in $REPOS; do printf '%s\n' "$_s"; done > "$T/repos"
fi
sort -u "$T/repos" -o "$T/repos"
if [ ! -s "$T/repos" ]; then
  log_fail "[check:$ID] no repo to read: pass --repo OWNER/NAME, or declare a repo-kind in a repo's .agents/config.yaml (unchecked)"; log_fix "sh bin/standard-label-sync.sh --repo OWNER/NAME"; log_end || :; exit 3
fi

# ── the plan, per repo ───────────────────────────────────────────────────────
# $T/plan: repo TAB action TAB arg1 TAB arg2 ; $T/unread: repos that could not be read
: > "$T/plan"; : > "$T/unread"; NREAD=0
while IFS= read -r _repo; do
  if ! "$GH" label list --repo "$_repo" --limit 1000 --json name,description --jq '.[] | [.name, (.description // "")] | @tsv' > "$T/live" 2> "$T/gh.err" < /dev/null; then
    printf '%s\n' "$_repo" >> "$T/unread"; log_warn "$_repo: gh label list failed: $(head -n 1 "$T/gh.err")"; continue
  fi
  NREAD=$((NREAD + 1))
  awk -F'\t' -v repo="$_repo" -v OFS='\t' '
    FILENAME == ARGV[1] { DESC[$1] = $2; ORD[++nr] = $1; next }
    FILENAME == ARGV[2] { MAP[$1] = $2; next }
    FILENAME == ARGV[3] { RET[++nt] = $1; next }
    { LIVE[$1] = 1; LORD[++nl] = $1 }
    function retired(l,   i, p) { for (i = 1; i <= nt; i++) { p = RET[i]
      if (p == l) return 1
      if (substr(p, length(p)) == "*" && index(l, substr(p, 1, length(p) - 1)) == 1) return 1 } return 0 }
    END {
      for (i = 1; i <= nl; i++) { l = LORD[i]
        if (l in DESC) continue
        if (l in MAP) { n = MAP[l]; if ((n in LIVE) || (n in MOVED)) print repo, "merge", l, n; else { print repo, "rename", l, n; MOVED[n] = 1 } }
        else if (retired(l)) print repo, "remove", l, "-"
        else print repo, "unregistered", l, "-" }
      for (i = 1; i <= nr; i++) { n = ORD[i]; if (!(n in LIVE) && !(n in MOVED)) print repo, "create", n, DESC[n] }
    }' "$T/register" "$T/map" "$T/retired" "$T/live" >> "$T/plan"
done < "$T/repos"

if [ "$NREAD" -eq 0 ]; then
  log_fail "[check:$ID] none of the $(grep -c . "$T/repos" | tr -d ' ') repo(s) could be read, so no result is claimed"; log_fix "gh auth status"; log_end || :; exit 3
fi

# ── plan / apply ─────────────────────────────────────────────────────────────
_count() { awk -F'\t' -v r="$1" -v a="$2" '$1 == r && $2 == a { n++ } END { print n + 0 }' "$T/plan"; }
_fixtext() { # <action> <label> <target> -> what to do about a label outside the register
  case "$1" in
    rename) printf 'apply the rename to %s (label-axes.tsv legacy column)' "$3" ;;
    merge) printf 'both it and %s exist: relabel its issues to %s, then delete it (--apply does)' "$3" "$3" ;;
    remove) printf 'retired (label-retired.tsv): remove it (--apply --remove-retired)' ;;
    *) printf 'add its row to standards/naming/label-axes.tsv, map it in the legacy column, or retire it in label-retired.tsv' ;;
  esac
}

if [ "$MODE" = plan ] || [ "$MODE" = apply ]; then
  while IFS= read -r _repo; do
    if grep -qx "$_repo" "$T/unread"; then printf '%s: not read\n' "$_repo"; continue; fi
    printf '%s: %s rename, %s merge, %s create, %s remove (retired), %s unregistered\n' "$_repo" \
      "$(_count "$_repo" rename)" "$(_count "$_repo" merge)" "$(_count "$_repo" create)" "$(_count "$_repo" remove)" "$(_count "$_repo" unregistered)"
    awk -F'\t' -v r="$_repo" '$1 == r { printf "  %-12s %s%s\n", $2, $3, ($4 == "-" ? "" : ($2 == "create" ? "" : "  ->  " $4)) }' "$T/plan"
  done < "$T/repos"
  _total="$(grep -c . "$T/plan" | tr -d ' ')"
  if [ "$MODE" = plan ]; then
    printf 'dry run: nothing was changed. --apply executes create, rename and merge; --apply --remove-retired also removes.\n'
    log_end || :; [ "$_total" -eq 0 ] && [ ! -s "$T/unread" ] || exit 1; exit 0
  fi
  # apply: a person's step. Every call is one gh argument vector, never a shell string.
  _rc=0
  while IFS="$TAB" read -r _repo _act _a _b; do
    case "$_act" in
      create) "$GH" label create "$_a" --repo "$_repo" --description "$_b" > /dev/null < /dev/null || _rc=1 ;;
      rename) "$GH" label edit "$_a" --repo "$_repo" --name "$_b" > /dev/null < /dev/null || _rc=1 ;;
      merge)
        "$GH" issue list --repo "$_repo" --label "$_a" --state all --limit 1000 --json number --jq '.[].number' < /dev/null | while IFS= read -r _n; do
          "$GH" issue edit "$_n" --repo "$_repo" --add-label "$_b" --remove-label "$_a" > /dev/null < /dev/null || exit 1; done || _rc=1
        "$GH" pr list --repo "$_repo" --label "$_a" --state all --limit 1000 --json number --jq '.[].number' < /dev/null | while IFS= read -r _n; do
          "$GH" pr edit "$_n" --repo "$_repo" --add-label "$_b" --remove-label "$_a" > /dev/null < /dev/null || exit 1; done || _rc=1
        [ "$_rc" -ne 0 ] || "$GH" label delete "$_a" --repo "$_repo" --yes > /dev/null < /dev/null || _rc=1 ;;
      remove)
        if [ "$REMOVE" = 1 ]; then "$GH" label delete "$_a" --repo "$_repo" --yes > /dev/null < /dev/null || _rc=1
        else printf '  skipped (needs --remove-retired): remove %s on %s\n' "$_a" "$_repo"; fi ;;
    esac
  done < "$T/plan"
  log_end || :; exit "$_rc"
fi

# ── --check: the delta against the last run ──────────────────────────────────
CACHE="$CFG/cache"; STATE="$CACHE/standard-label-registered.tsv"; CHECKS_LOG="$CACHE/checks.log"
# a live label outside the register is one plan line that is not a create
awk -F'\t' -v OFS='\t' '$2 != "create" { print $1, "label-outside-register " $1 ": " $3 }' "$T/plan" > "$T/cur"
mkdir -p "$CACHE" 2>/dev/null || :
[ -f "$STATE" ] || : > "$STATE"
if [ -s "$T/unread" ]; then   # not seen is never fixed: an unread repo keeps its earlier rows, standing
  awk -F'\t' 'FILENAME == ARGV[1] { u[$1] = 1; next } ($2 in u) { print $2 "\t" $3 }' "$T/unread" "$STATE" >> "$T/cur"
fi
LC_ALL=C sort -u "$T/cur" -o "$T/cur"
awk -F'\t' -v today="$TODAY" -v OFS='\t' 'FILENAME == ARGV[1] { old[$3] = $1; next } { print (($2 in old) ? old[$2] : today), $1, $2 }' "$STATE" "$T/cur" > "$T/next"
awk -F'\t' 'FILENAME == ARGV[1] { cur[$2] = 1; next } !($3 in cur) { print $3 }' "$T/cur" "$STATE" | LC_ALL=C sort > "$T/fixed"
awk -F'\t' 'FILENAME == ARGV[1] { s[$3] = 1; next } !($3 in s) { print $3 }' "$STATE" "$T/next" | LC_ALL=C sort > "$T/new"
NNEW="$(grep -c . "$T/new" | tr -d ' ')"; NFIX="$(grep -c . "$T/fixed" | tr -d ' ')"; NCUR="$(grep -c . "$T/next" | tr -d ' ')"; NSTAND=$((NCUR - NNEW))
_days() { awk -v a="$1" -v b="$2" 'function jd(s,  y, m, d) { y = substr(s,1,4)+0; m = substr(s,6,2)+0; d = substr(s,9,2)+0
    if (m <= 2) { y--; m += 12 } return int(365.25*y) + int(30.6001*(m+1)) + d } BEGIN { print jd(b) - jd(a) }'; }
_tmp="$(mktemp "$CACHE/.standard-label-registered.XXXXXX" 2>/dev/null)" || _tmp=""
if [ -n "$_tmp" ] && cp "$T/next" "$_tmp" && mv -f "$_tmp" "$STATE"; then :; else
  [ -z "$_tmp" ] || rm -f "$_tmp"; log_warn "the state could not be written at $STATE, so the next run will report this one's findings as new again"
fi
if [ "$NCUR" -eq 0 ]; then _st=green; else _st=red; fi
set --; while IFS="$TAB" read -r _fs _u _s; do set -- "$@" "$_s"; done < "$T/next"
LOG_RECEIPT_FRESH_DAYS=9 log_receipt "$(receipt_dir "$CFG")" "$ID" "$_st" "$@" \
  || log_warn "no receipt could be written under $(receipt_dir "$CFG"), so the findings channel does not see this run"

printf '[check:%s] %s: %s repo(s) read, %s label(s) outside the register: %s new, %s fixed, %s standing\n' "$ID" "$TODAY" "$NREAD" "$NCUR" "$NNEW" "$NFIX" "$NSTAND"
CAP=20
_show() { # <label> <file> <with fix text>
  [ -s "$2" ] || return 0
  _h="$1"; _i=0
  while IFS= read -r _x; do
    _i=$((_i + 1)); [ "$_i" -le "$CAP" ] || break
    if [ "$3" = fix ]; then
      _r="${_x#label-outside-register }"; _rp="${_r%%: *}"; _lb="${_r#*: }"
      _p="$(awk -F'\t' -v r="$_rp" -v l="$_lb" '$1 == r && $3 == l { print $2 "\t" $4; exit }' "$T/plan")"
      printf '  %-8s %s: %s\n' "$_h" "$_x" "$(_fixtext "${_p%%"$TAB"*}" "$_lb" "${_p#*"$TAB"}")"
    else printf '  %-8s %s\n' "$_h" "$_x"; fi
    _h=""
  done < "$2"
  _more=$(($(grep -c . "$2" | tr -d ' ') - CAP)); [ "$_more" -le 0 ] || printf '  %-8s ... and %s more\n' "" "$_more"
}
if [ "$NNEW" -eq 0 ] && [ "$NFIX" -eq 0 ]; then printf '  nothing new\n'; fi
_show new "$T/new" fix
_show fixed "$T/fixed" nofix
if [ "$NSTAND" -gt 0 ]; then
  awk -F'\t' 'FILENAME == ARGV[1] { n[$1] = 1; next } !($3 in n) { print $1 "\t" $3 }' "$T/new" "$T/next" | LC_ALL=C sort | head -n 1 > "$T/oldest"
  printf '  standing %s finding(s) already known, oldest %s day(s): %s\n' "$NSTAND" "$(_days "$(cut -f1 "$T/oldest")" "$TODAY")" "$(cut -f2 "$T/oldest" | cut -c1-120)"
fi
[ ! -s "$T/unread" ] || printf '  not read this run (their earlier findings stand): %s\n' "$(tr '\n' ' ' < "$T/unread")"
printf '  the plan that clears them: sh bin/standard-label-sync.sh (check.label-sync, dry run)\n'
if [ "$NNEW" -gt 0 ] || [ "$NFIX" -gt 0 ]; then
  if [ ! -e "$CHECKS_LOG" ] || { [ -f "$CHECKS_LOG" ] && [ ! -L "$CHECKS_LOG" ]; }; then
    printf '[check:%s] %s %s new, %s fixed, %s standing\n' "$ID" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$NNEW" "$NFIX" "$NSTAND" >> "$CHECKS_LOG" 2>/dev/null || :
  fi
fi
log_end || :
[ "$NNEW" -eq 0 ] || exit 1
exit 0
