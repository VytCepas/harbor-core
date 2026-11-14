#!/usr/bin/env sh
# issue-connector (harbor#512) — label an issue from the one taxonomy, and tell it
# which existing issues are its family.
#
#   sh bin/standard-issue-label.sh --check <n>       exit 1 when a type or theme is missing
#   sh bin/standard-issue-label.sh --suggest <n>     a theme DERIVED from the paths it names
#   sh bin/standard-issue-label.sh --siblings <n>    the open issues sharing its theme
#   sh bin/standard-issue-label.sh --apply <n> <label>...   apply labels that exist in the taxonomy
#   sh bin/standard-issue-label.sh --audit           every open issue missing an axis, and
#                                               every theme whose members cite no sibling
#   sh bin/standard-issue-label.sh --falsifiers      open issues that state no falsifier
#   sh bin/standard-issue-label.sh --labels          the taxonomy, as the connector reads it
#
#   HARBOR_STANDARD_ISSUE_REPO   owner/name; defaults to this checkout's origin
#   HARBOR_STANDARD_TAXONOMY     path to the taxonomy; defaults to contracts/issue-taxonomy.tsv
#
# It suggests a theme and never a type: a theme is a claim about which part of the tree an issue is about, derivable
# from the paths it names against contracts/issue-taxonomy.tsv; a type is a claim about the system's STATE, which no
# content predicate settles, so --check reports a missing type and stops.
# It never applies what it suggests: --apply takes labels from the caller and refuses any the taxonomy lacks (a
# connector labelling on its own authority is an unreviewed classifier; encoding a fix is a human-gated act).
# A provenance epic is theme-exempt, a rule not a tolerance: its children span themes by nature, and without the
# exemption the audit's "none" line could never appear.
# A falsifier is reported, not required (2026-09-16: four tickets closed on re-reading a refutation condition that had
# already fired). It is not part of --check: most of the backlog predates it and a fatal check would redden 122 issues (§2.11).
# The sibling half is why this exists: finding an issue's family meant knowing the backlog by heart (three sibling epics
# from one audit pass referenced each other nowhere for six weeks).
# Removed notes: docs/explanation/code-cases/bin-standard-issue-label.md
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TAX="${HARBOR_STANDARD_TAXONOMY:-$ROOT/contracts/issue-taxonomy.tsv}"

# The one log format (contracts/logging.md). Diagnostics go to stderr, so stdout stays data for every
# mode except --audit and --falsifiers, which set LOG_FD=1 because their stdout is the report.
. "$ROOT/bin/library-log.sh"
LOG_FD=2

case "${1:-}" in
  -h|--help)
    awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
    exit 0 ;;
esac

[ -f "$TAX" ] || { printf 'issue-connector: no taxonomy at %s\n' "${TAX#"$ROOT"/}" >&2; exit 2; }

# The repo is derived from `git remote`, not typed: worktrees share the origin.
repo() {
  if [ -n "${HARBOR_STANDARD_ISSUE_REPO:-}" ]; then printf '%s\n' "${HARBOR_STANDARD_ISSUE_REPO:-}"; return 0; fi
  git -C "$ROOT" remote get-url origin 2>/dev/null \
    | sed -e 's|^git@[^:]*:||' -e 's|^https://[^/]*/||' -e 's|\.git$||'
}

# labels_all is EVERY declared label (harbor#609): the apply gate tested `type` and `theme` alone and refused
# `--apply P1-high` as "not in the taxonomy" while it sat on 58 issues, teaching callers to label by hand.
labels_all() { awk -F'\t' '/^#/ || NF < 4 { next } { print $2 }' "$TAX"; }

# tax <kind> -> label<TAB>glob<TAB>meaning, comments and blanks dropped
tax() {
  awk -F'\t' -v k="$1" '/^#/ || NF < 4 { next } $1 == k { print $2 "\t" $3 "\t" $4 }' "$TAX"
}

labels_of() { # <n> -> one label per line
  gh issue view "$1" -R "$(repo)" --json labels -q '.labels[].name' 2>/dev/null || true
}

body_of() { gh issue view "$1" -R "$(repo)" --json body -q '.body' 2>/dev/null || true; }

# first_match <kind> <labels-file> -> the first taxonomy label present, or nothing
first_match() {
  tax "$1" | cut -f1 | while IFS= read -r l; do
    [ -n "$l" ] || continue
    if grep -Fxq -- "$l" "$2" 2>/dev/null; then printf '%s\n' "$l"; break; fi
  done
}

# ── suggest ─────────────────────────────────────────────────────────────────────
# A theme is suggested from the INTERSECTION of the paths its globs cover and the paths the issue names; a tie prints both.
suggest_theme() {
  _sb="$1"                      # file holding the issue body
  _best=0; _win=''
  tax theme | while IFS='	' read -r _lbl _globs _mean; do
    [ "$_globs" = "-" ] && continue
    _hits=0
    for _g in $_globs; do
      # git ls-files expands the glob against the real tree; a glob matching nothing
      # is a defect the suite catches, not something to silently skip here.
      git -C "$ROOT" ls-files -- "$_g" 2>/dev/null | while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        if grep -Fq -- "$_p" "$_sb" 2>/dev/null; then printf 'x'; fi
      done
    done | { _n=$(wc -c | tr -d ' '); printf '%s\t%s\n' "${_n:-0}" "$_lbl"; }
  done | sort -rn | awk -F'\t' 'NR==1{top=$1} $1==top && top>0 {print $2}'
  unset _sb _best _win 2>/dev/null || true
}

# ── modes ───────────────────────────────────────────────────────────────────────
mode="${1:-}"; shift 2>/dev/null || true

case "$mode" in
  --labels)
    printf 'types:\n';  tax type  | awk -F'\t' '{printf "  %-18s %s\n", $1, $3}'
    printf 'themes:\n'; tax theme | awk -F'\t' '{printf "  %-20s %s\n", $1, $3}'
    ;;

  --check)
    n="${1:?issue number}"
    L="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; labels_of "$n" > "$L"
    ty="$(first_match type  "$L")"
    th="$(first_match theme "$L")"
    rc=0
    [ -n "$ty" ] || { log_fail "#$n has no TYPE from the taxonomy"; log_nofix "contracts/issue-taxonomy.tsv — pick a type, then --apply"; rc=1; }
    if [ "$ty" = "epic:provenance" ]; then
      th="${th:-(theme-exempt: provenance epics span themes)}"
    fi
    [ -n "$th" ] || { log_fail "#$n has no THEME from the taxonomy"; log_nofix "contracts/issue-taxonomy.tsv — pick a theme, then --apply"; rc=1; }
    if [ "$rc" -eq 0 ]; then printf 'ok  #%s  %s  %s\n' "$n" "$ty" "$th"; else log_end || :; fi
    rm -f "$L"
    exit "$rc"
    ;;

  --suggest)
    n="${1:?issue number}"
    B="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; body_of "$n" > "$B"
    s="$(suggest_theme "$B")"
    rm -f "$B"
    if [ -n "$s" ]; then
      printf '%s\n' "$s"
    else
      log_fail "#$n names no path any theme covers — choose by hand"; log_nofix "contracts/issue-taxonomy.tsv — choose the theme by hand"
      log_end || :
      exit 1
    fi
    ;;

  --siblings)
    n="${1:?issue number}"
    L="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; labels_of "$n" > "$L"
    th="$(first_match theme "$L")"; rm -f "$L"
    [ -n "$th" ] || { log_fail "#$n has no theme — nothing to compare"; log_nofix "contracts/issue-taxonomy.tsv — give it a theme label"; log_end || :; exit 1; }
    printf '%s siblings:\n' "$th"
    gh issue list -R "$(repo)" --state open --limit 400 --label "$th" \
      --json number,title -q '.[] | "  #\(.number)  \(.title[0:72])"' 2>/dev/null \
      | grep -v "^  #$n  " || true
    ;;

  --apply)
    n="${1:?issue number}"; shift
    [ "$#" -gt 0 ] || { printf 'issue-connector: --apply needs at least one label\n' >&2; exit 2; }
    ok=''
    for l in "$@"; do
      if labels_all | grep -Fxq -- "$l"; then
        ok="$ok --add-label $l"
      else
        log_fail "$l is not in the taxonomy — refusing"; log_nofix "contracts/issue-taxonomy.tsv — use a declared label"
        log_end || :
        exit 1
      fi
    done
    # shellcheck disable=SC2086 # $ok is a built flag list, each element validated above
    gh issue edit "$n" -R "$(repo)" $ok >/dev/null
    printf 'applied to #%s:%s\n' "$n" "$(printf '%s' "$ok" | sed 's/--add-label//g')"
    ;;

  --falsifiers)
    LOG_FD=1
    R="$(repo)"
    F="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    gh issue list -R "$R" --state open --limit 400 --json number,body,labels \
      -q '.[] | "\(.number)\t\(([.labels[].name]|join(",")))\t\((.body//"")|gsub("\n";" "))"' \
      2>/dev/null > "$F"
    tot=0; miss=0
    log_head "open issues stating no falsifier"
    while IFS='	' read -r num labs body; do
      [ -n "$num" ] || continue
      # An epic is exempt, like a provenance epic: its falsifier is its children's.
      case ",$labs," in *",epic:"*) continue ;; esac
      tot=$(( tot + 1 ))
      case "$body" in
        *[Ff]alsifier*|*[Rr]efuted\ if*|*"would falsify"*) ;;
        *) miss=$(( miss + 1 )); printf '  #%s\n' "$num" ;;
      esac
    done < "$F"
    rm -f "$F"
    [ "$miss" -eq 0 ] && printf '  none\n'
    printf '\n%s of %s non-epic open issues state no falsifier\n' "$miss" "$tot"
    ;;

  --audit)
    # shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
    LOG_FD=1
    R="$(repo)"
    STRICT=no; [ "${1:-}" = "--strict" ] && STRICT=yes
    FAIL=0

    A="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; ALLOPEN="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; GRAPH="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    # The read's status is the gate (harbor#626, DE-15): a failed `gh` aborted silently under `set -e`, or returned no rows
    # so every section read "nothing open". Nothing audited is not a clean audit, so the run stops and says so.
    OPENREAD=yes
    gh issue list -R "$R" --state open --limit 400 --json number,labels \
      -q '.[] | "\(.number)\t\([.labels[].name]|join(","))"' 2>/dev/null > "$A" || OPENREAD=no
    [ -s "$A" ] || OPENREAD=no
    if [ "$OPENREAD" = no ]; then
      log_fail "could not read open issues — nothing was audited"
      log_fix "gh auth status, then re-run: sh bin/standard-issue-label.sh --audit"
      rm -f "$A" "$ALLOPEN" "$GRAPH"
      log_end || :
      exit 1
    fi
    cut -f1 "$A" > "$ALLOPEN"

    # Cardinality is read from the #AXIS rows, not hard-coded: the prose table let 32 issues violate "layer exactly one" (harbor#612).
    log_head "cardinality"
    card="$(awk -F'\t' '/^#AXIS/{print $2"\t"$3"\t"$4}' "$TAX")"
    [ -n "$card" ] || { printf 'issue-connector: taxonomy declares no #AXIS rows\n' >&2; exit 2; }
    AX="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; printf '%s\n' "$card" > "$AX"
    MAP="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    awk -F'\t' '/^#/ || NF < 4 { next } { print $2 "\t" $1 }' "$TAX" > "$MAP"

    CV="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    awk -F'\t' -v axf="$AX" -v mapf="$MAP" '
      BEGIN{ while ((getline l < axf) > 0) { split(l,a,"\t"); mn[a[1]]=a[2]; mx[a[1]]=a[3] }
             while ((getline m < mapf) > 0) { split(m,b,"\t"); kind[b[1]]=b[2] } }
      { n=$1; split($2,L,","); delete c; prov=0
        for (i in L) { l=L[i]; if (l=="epic:provenance") prov=1
          k=(l in kind)?kind[l]:"UNDECLARED"; c[k]++ }
        msg=""
        for (ax in mn) {
          got=c[ax]+0
          # Provenance epic is theme-exempt (see the header).
          if (ax=="theme" && prov) continue
          if (got < mn[ax]) msg = msg sprintf(" %s=%d(min %d)", ax, got, mn[ax])
          if (got > mx[ax]) msg = msg sprintf(" %s=%d(max %d)", ax, got, mx[ax])
        }
        if (msg != "") printf "  #%-5s%s\n", n, msg
      }' "$A" | LC_ALL=C sort > "$CV"
    nbad="$(awk 'END{print NR+0}' "$CV")"
    [ "$nbad" -eq 0 ] && printf '  none\n' || cat "$CV"
    rm -f "$CV"
    [ "$nbad" -gt 0 ] && FAIL=1

    # ── 2 · UNDECLARED LABELS IN USE ───────────────────────────────────────────
    printf '\n'; log_head "labels applied but not declared"
    und="$(awk -F'\t' -v mapf="$MAP" '
      BEGIN{ while ((getline m < mapf) > 0) { split(m,b,"\t"); kind[b[1]]=1 } }
      { split($2,L,","); for (i in L) if (L[i] != "" && !(L[i] in kind)) print L[i] }' "$A" \
      | sort | uniq -c | sort -rn)"
    if [ -n "$und" ]; then printf '%s\n' "$und" | sed 's/^/  /'; FAIL=1; else printf '  none\n'; fi

    # ── 3 · THE CONTRACT AGAINST THE TRACKER, BOTH DIRECTIONS ──────────────────
    # Check the contract against the tracker in both directions: harbor#609 declared `theme:security`/`theme:testing` that never existed on the tracker.
    printf '\n'; log_head "taxonomy against the tracker"
    LIVE="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; DECL="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    # An unread list is not an empty tracker: piped straight into sort, a failed read listed every declared label ABSENT.
    if gh label list -R "$R" --limit 300 --json name -q '.[].name' 2>/dev/null > "$LIVE.raw"; then
      LC_ALL=C sort "$LIVE.raw" > "$LIVE"
      cut -f1 "$MAP" | LC_ALL=C sort -u > "$DECL"
      miss_live="$(LC_ALL=C comm -23 "$DECL" "$LIVE" | tr '\n' ' ')"
      miss_decl="$(LC_ALL=C comm -13 "$DECL" "$LIVE" | tr '\n' ' ')"
      if [ -n "$(printf '%s' "$miss_live" | tr -d ' ')" ]; then
        printf '  declared here, ABSENT on the tracker: %s\n' "$miss_live"; FAIL=1
      fi
      if [ -n "$(printf '%s' "$miss_decl" | tr -d ' ')" ]; then
        printf '  on the tracker, NOT declared here:    %s\n' "$miss_decl"; FAIL=1
      fi
      [ -z "$(printf '%s%s' "$miss_live" "$miss_decl" | tr -d ' ')" ] && printf '  reconciled\n'
    else
      printf "  could not read the tracker's labels: the taxonomy was not compared\n"; FAIL=1
    fi
    rm -f "$LIVE.raw"
    rm -f "$LIVE" "$DECL"

    # ── 4 · P0 IS ONLY MEANINGFUL WHILE IT IS RARE ─────────────────────────────
    p0="$(awk -F'\t' '{ if ($2 ~ /(^|,)P0-critical(,|$)/) n++ } END{print n+0}' "$A")"
    printf '\n'; log_head "P0-critical"; printf '  %s issue(s), cap 3\n' "$p0"
    [ "$p0" -gt 3 ] && { printf '  OVER CAP — a flag that stops being rare has stopped meaning anything\n'; FAIL=1; }

    # ── 5 · THE OWNERSHIP GRAPH ────────────────────────────────────────────────
    # Native sub-issues are authoritative (#612 Q2). Everything here is a question
    # about the EDGE, never about a label that claims to restate it.
    printf '\n'; log_head "ownership graph"
    # Paginated: `first:100` against 135 open issues reported 24 orphans instead of 34.
    # A failed page, or the cap with pages left, is a PARTIAL graph: it once printed "edges consistent" over part of it.
    _cur=''; _pages=0; _trunc=''
    while [ "$_pages" -lt 20 ]; do
      _pages=$((_pages + 1))
      if [ -z "$_cur" ]; then _after='null'; else _after="\"$_cur\""; fi
      _q='{repository(owner:"'"${R%%/*}"'",name:"'"${R#*/}"'"){issues(states:OPEN,first:100,after:'"$_after"'){pageInfo{hasNextPage endCursor} nodes{number parent{number} subIssues(first:50){totalCount}}}}}'
      _out="$(gh api graphql -f query="$_q" 2>/dev/null)" || { _trunc="page $_pages could not be read"; break; }
      printf '%s' "$_out" | jq -r '.data.repository.issues.nodes[] | "\(.number)\t\(.parent.number // "-")\t\(.subIssues.totalCount)"' >> "$GRAPH" 2>/dev/null \
        || { _trunc="page $_pages did not parse"; break; }
      [ "$(printf '%s' "$_out" | jq -r '.data.repository.issues.pageInfo.hasNextPage')" = true ] || break
      _cur="$(printf '%s' "$_out" | jq -r '.data.repository.issues.pageInfo.endCursor')"
      if [ "$_pages" -ge 20 ]; then _trunc="the 20-page cap ended it with pages left"; fi
    done
    if [ -n "$_trunc" ] && [ -s "$GRAPH" ]; then
      printf '  graph INCOMPLETE (%s): the verdicts below cover only what was read\n' "$_trunc"; FAIL=1
    fi
    if [ ! -s "$GRAPH" ]; then
      log_warn "graph unavailable — sub-issue query returned nothing"
    else
      # An open child under a CLOSED parent is invisible in every open-issue view.
      # FILENAME, not NR==FNR: an empty first file would make NR==FNR true for every row of the
      # second, swallowing the graph into the open set (harbor#626, DE-15).
      closedpar="$(awk -F'\t' 'FILENAME==ARGV[1]{open[$1]=1;next} $2!="-" && !($2 in open){printf " #%s->#%s",$1,$2}' "$ALLOPEN" "$GRAPH")"
      [ -n "$closedpar" ] && { printf '  open issue under a CLOSED parent:%s\n' "$closedpar"; FAIL=1; }
      # `epic:*` says what KIND of parent; the EDGE says whether it is one.
      epicnokid=''; kidnoepic=''
      while IFS='	' read -r num _par kids; do
        labs="$(awk -F'\t' -v k="$num" '$1==k{print $2}' "$A")"
        case ",$labs," in *",epic:"*) is_epic=yes ;; *) is_epic=no ;; esac
        [ "$is_epic" = yes ] && [ "$kids" -eq 0 ] && epicnokid="$epicnokid #$num"
        [ "$is_epic" = no ]  && [ "$kids" -gt 0 ] && kidnoepic="$kidnoepic #$num"
      done < "$GRAPH"
      [ -n "$epicnokid" ] && { printf '  epic:* that parents nothing:%s\n' "$epicnokid"; FAIL=1; }
      [ -n "$kidnoepic" ] && { printf '  parents carrying no epic:*:%s\n' "$kidnoepic"; FAIL=1; }
      orph="$(awk -F'\t' '$2=="-" && $3==0 {n++} END{print n+0}' "$GRAPH")"
      printf '  %s issue(s) with no parent and no children\n' "$orph"
      [ -z "$closedpar$epicnokid$kidnoepic$_trunc" ] && printf '  edges consistent\n'
      # PROSE-ONLY PARENTAGE (harbor#978): a body that says `Part of #N` (or the italic `_Part of_ #N`) while the native
      # sub-issue edge is absent is a parent the board cannot see. The edge is authoritative; the prose is the finding.
      BODIES="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
      gh issue list -R "$R" --state open --limit 400 --json number,body \
        -q '.[] | "\(.number)\t\((.body//"")|gsub("\n";" "))"' 2>/dev/null > "$BODIES" || :
      proseonly="$(awk -F'\t' 'FILENAME==ARGV[1]{par[$1]=$2;next} ($1 in par) && par[$1]=="-" && match($0,/(^|[^[:alnum:]])_?[Pp]art of_?:? *[A-Za-z0-9._\/-]*#[0-9]+/){printf " #%s",$1}' "$GRAPH" "$BODIES")"
      rm -f "$BODIES"
      [ -n "$proseonly" ] && { printf '  prose-only parent (body says Part of #N, no sub-issue edge):%s\n' "$proseonly"; FAIL=1; }
    fi

    # ── 6 · SIBLING CITATION, unchanged in intent ──────────────────────────────
    printf '\n'; log_head "open issues citing no other open issue, grouped by theme"
    tax theme | cut -f1 | while IFS= read -r th; do
      [ -n "$th" ] || continue
      N="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
      gh issue list -R "$R" --state open --limit 400 --label "$th" --json number,body,comments \
        -q '.[] | "\(.number)\t\(((.body//"") + " " + ([.comments[]?.body]|join(" ")))|gsub("\n";" "))"' 2>/dev/null > "$N"
      cnt="$(awk 'END{print NR+0}' "$N")"
      [ "$cnt" -lt 2 ] && { rm -f "$N"; continue; }
      ids="$(tr '\n' ' ' < "$ALLOPEN")"
      lonely=''
      while IFS='	' read -r num body; do
        [ -n "$num" ] || continue
        cited=no
        for other in $ids; do
          [ "$other" = "$num" ] && continue
          case "$body" in *"#$other"*) cited=yes; break ;; esac
        done
        [ "$cited" = no ] && lonely="$lonely #$num"
      done < "$N"
      rm -f "$N"
      [ -n "$lonely" ] && printf '  %-22s %s of %s cite no sibling:%s\n' \
        "$th" "$(printf '%s' "$lonely" | tr -s ' ' '\n' | grep -c '#' || true)" "$cnt" "$lonely"
    # `|| true` is load-bearing: this is the last command in the --audit arm under `set -e`, and its status is false when the
    # last theme has no lonely issue, which killed the run before the --strict gate (measured 2026-09-21).
    done || true

    rm -f "$A" "$ALLOPEN" "$GRAPH" "$AX" "$MAP"
    # Reporting is the default and failing is opt-in: a red exit on 67 standing violations is a false positive (No.2.11). CI uses --strict once the count is zero.
    if [ "$STRICT" = yes ] && [ "$FAIL" -ne 0 ]; then
      printf '\naudit: violations above, and --strict was given\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'issue-connector: unknown mode %s — see --help\n' "${mode:-<none>}" >&2
    exit 2 ;;
esac
