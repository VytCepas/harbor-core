#!/usr/bin/env sh
# issue-connector (harbor#512) — label an issue from the one taxonomy, and tell it
# which existing issues are its family.
#
#   sh bin/issue-connector.sh --check <n>       exit 1 when a type or theme is missing
#   sh bin/issue-connector.sh --suggest <n>     a theme DERIVED from the paths it names
#   sh bin/issue-connector.sh --siblings <n>    the open issues sharing its theme
#   sh bin/issue-connector.sh --apply <n> <label>...   apply labels that exist in the taxonomy
#   sh bin/issue-connector.sh --audit           every open issue missing an axis, and
#                                               every theme whose members cite no sibling
#   sh bin/issue-connector.sh --falsifiers      open issues that state no falsifier
#   sh bin/issue-connector.sh --labels          the taxonomy, as the connector reads it
#
#   HARBOR_ISSUE_REPO   owner/name; defaults to this checkout's origin
#   HARBOR_TAXONOMY     path to the taxonomy; defaults to CONTRACTS/issue-taxonomy.tsv
#
# IT SUGGESTS A THEME AND NEVER A TYPE, and the asymmetry is the design. A theme is
# a claim about which part of the tree an issue is about, so it can be derived from
# the paths the issue names against the globs CONTRACTS/issue-taxonomy.tsv declares.
# A type is a claim about the system's STATE — whether something is wrong now (bug)
# or right and unenforced (tech-debt) — and no content predicate can settle that.
# Guessing it would produce a plausible label nobody chose, which is the failure this
# repo files tickets about. So --check reports a missing type and stops.
#
# IT NEVER APPLIES WHAT IT SUGGESTS. --suggest prints; --apply takes labels from the
# caller and refuses any the taxonomy does not carry. Two verbs, because a connector
# that labels on its own authority is an unreviewed classifier writing into the
# backlog at machine speed — CONSTITUTION's "encoding a fix is a human-gated act".
#
# A PROVENANCE EPIC IS THEME-EXEMPT, and that is a rule rather than a tolerance. An
# `epic:provenance` is the origin record of an audit pass: its children span several
# themes by nature, so forcing one on it would file a true finding under a false
# heading. Every other kind must carry both axes. Without this the audit's "none" line
# could never appear, and a checker that can never come back clean is one nobody reads.
#
# A FALSIFIER IS THE CHEAPEST TRIAGE STEP THERE IS, and it is reported rather than
# required. On 2026-09-16 FOUR tickets closed on nothing but a re-read of their own
# stated refutation condition — it had already fired, weeks earlier, and nobody had
# looked. That is the highest-yield paragraph in a ticket and it costs one read.
#
# It is not part of --check, deliberately: most of the backlog predates the
# convention, so making it fatal would redden 122 issues and teach the reader to
# ignore the checker (§2.11). `--falsifiers` names them, and the count is the thing
# to watch trend down.
#
# THE SIBLING HALF IS WHY THIS EXISTS AT ALL. Twelve themes carry 122 open issues, and
# before this, finding an issue's family meant knowing the backlog by heart. On
# 2026-09-16 three sibling epics from ONE audit pass were found referencing each other
# nowhere, across three repos, six weeks after they were filed.
set -eu

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
TAX="${HARBOR_TAXONOMY:-$ROOT/CONTRACTS/issue-taxonomy.tsv}"

# The one log format (CONTRACTS/logging.md). Diagnostics go to stderr, so stdout stays data for every
# mode except --audit and --falsifiers, which set LOG_FD=1 because their stdout is the report.
. "$ROOT/bin/log-lib.sh"
LOG_FD=2

case "${1:-}" in
  -h|--help)
    awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
    exit 0 ;;
esac

[ -f "$TAX" ] || { printf 'issue-connector: no taxonomy at %s\n' "${TAX#"$ROOT"/}" >&2; exit 2; }

# THE REPO IS DERIVED, NOT TYPED. A constant here would be a second copy of a fact
# `git remote` already holds, and this script runs from worktrees whose origin is
# the same repo.
repo() {
  if [ -n "${HARBOR_ISSUE_REPO:-}" ]; then printf '%s\n' "$HARBOR_ISSUE_REPO"; return 0; fi
  git -C "$ROOT" remote get-url origin 2>/dev/null \
    | sed -e 's|^git@[^:]*:||' -e 's|^https://[^/]*/||' -e 's|\.git$||'
}

# labels_all -> EVERY declared label, whatever its kind (harbor#609). The apply
# gate is where this contract is enforced, so it has to read all of it: the gate
# used to test `type` and `theme` alone, which meant `--apply P1-high` was refused
# as "not in the taxonomy" while P1-high sat on 58 open issues. A validation
# narrower than the contract it cites teaches the caller to set labels by hand
# instead, which is exactly how 23 labels came to be applied against no list.
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
# A THEME IS SUGGESTED FROM THE INTERSECTION, not from a keyword. Every tracked path
# a theme's globs cover is compared against the paths the issue body names, and the
# theme with the most hits wins. A tie prints both rather than picking, because a
# coin-flip label reads exactly like a considered one.
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
    [ -n "$ty" ] || { log_fail "#$n has no TYPE from the taxonomy"; log_nofix "CONTRACTS/issue-taxonomy.tsv — pick a type, then --apply"; rc=1; }
    if [ "$ty" = "epic:provenance" ]; then
      th="${th:-(theme-exempt: provenance epics span themes)}"
    fi
    [ -n "$th" ] || { log_fail "#$n has no THEME from the taxonomy"; log_nofix "CONTRACTS/issue-taxonomy.tsv — pick a theme, then --apply"; rc=1; }
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
      log_fail "#$n names no path any theme covers — choose by hand"; log_nofix "CONTRACTS/issue-taxonomy.tsv — choose the theme by hand"
      log_end || :
      exit 1
    fi
    ;;

  --siblings)
    n="${1:?issue number}"
    L="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; labels_of "$n" > "$L"
    th="$(first_match theme "$L")"; rm -f "$L"
    [ -n "$th" ] || { log_fail "#$n has no theme — nothing to compare"; log_nofix "CONTRACTS/issue-taxonomy.tsv — give it a theme label"; log_end || :; exit 1; }
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
        log_fail "$l is not in the taxonomy — refusing"; log_nofix "CONTRACTS/issue-taxonomy.tsv — use a declared label"
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
      # AN EPIC IS EXEMPT, and for the same reason a provenance epic is theme-exempt:
      # an epic's falsifier is its children's. Requiring one of the container would
      # file a true finding under a false heading.
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
    LOG_FD=1
    R="$(repo)"
    STRICT=no; [ "${1:-}" = "--strict" ] && STRICT=yes
    FAIL=0

    A="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; ALLOPEN="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; GRAPH="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    # THE READ'S STATUS IS THE GATE. Before this, a failed `gh` either aborted the run silently
    # under `set -e` (exit 1, no line printed) or, when it succeeded with no rows, produced an
    # empty $ALLOPEN that every section below read as "nothing open": cardinality said "none",
    # and the closed-parent join swallowed the whole graph (harbor#626, DE-15). Nothing audited
    # is not a clean audit, so the run stops here and says so.
    OPENREAD=yes
    gh issue list -R "$R" --state open --limit 400 --json number,labels \
      -q '.[] | "\(.number)\t\([.labels[].name]|join(","))"' 2>/dev/null > "$A" || OPENREAD=no
    [ -s "$A" ] || OPENREAD=no
    if [ "$OPENREAD" = no ]; then
      log_fail "could not read open issues — nothing was audited"
      log_fix "gh auth status, then re-run: sh bin/issue-connector.sh --audit"
      rm -f "$A" "$ALLOPEN" "$GRAPH"
      log_end || :
      exit 1
    fi
    cut -f1 "$A" > "$ALLOPEN"

    # ── 1 · CARDINALITY, read from the #AXIS rows rather than hard-coded ────────
    # The seven-axis table this replaced was PROSE. A human read "layer exactly
    # one" and no checker did, so 32 issues violated it while every gate stayed
    # green (harbor#612). Parsing the declaration is the only thing that keeps
    # the rule and the mechanism from drifting apart.
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
          # A PROVENANCE EPIC IS THEME-EXEMPT and that is a rule, not a tolerance:
          # its children span themes by nature, so requiring one files a true
          # finding under a false heading.
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
    # harbor#609 declared `theme:security` and `theme:testing`; NEITHER EXISTED on
    # the tracker, while bare `security` and `testing` sat on 20 issues the apply
    # gate then refused. A contract checked in one direction only is how that
    # shipped green.
    printf '\n'; log_head "taxonomy against the tracker"
    LIVE="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"; DECL="$(mktemp "${TMPDIR:-/tmp}/harbor.XXXXXX")"
    gh label list -R "$R" --limit 300 --json name -q '.[].name' 2>/dev/null | LC_ALL=C sort > "$LIVE"
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
    rm -f "$LIVE" "$DECL"

    # ── 4 · P0 IS ONLY MEANINGFUL WHILE IT IS RARE ─────────────────────────────
    p0="$(awk -F'\t' '{ if ($2 ~ /(^|,)P0-critical(,|$)/) n++ } END{print n+0}' "$A")"
    printf '\n'; log_head "P0-critical"; printf '  %s issue(s), cap 3\n' "$p0"
    [ "$p0" -gt 3 ] && { printf '  OVER CAP — a flag that stops being rare has stopped meaning anything\n'; FAIL=1; }

    # ── 5 · THE OWNERSHIP GRAPH ────────────────────────────────────────────────
    # Native sub-issues are authoritative (#612 Q2). Everything here is a question
    # about the EDGE, never about a label that claims to restate it.
    printf '\n'; log_head "ownership graph"
    # PAGINATED, because the first cut asked for `first:100` against 135 open
    # issues and silently reported 24 orphans instead of 34 — a truncated page
    # reads exactly like a smaller problem.
    _cur=''; _pages=0
    while [ "$_pages" -lt 20 ]; do
      _pages=$((_pages + 1))
      if [ -z "$_cur" ]; then _after='null'; else _after="\"$_cur\""; fi
      _q='{repository(owner:"'"${R%%/*}"'",name:"'"${R#*/}"'"){issues(states:OPEN,first:100,after:'"$_after"'){pageInfo{hasNextPage endCursor} nodes{number parent{number} subIssues(first:50){totalCount}}}}}'
      _out="$(gh api graphql -f query="$_q" 2>/dev/null)" || break
      printf '%s' "$_out" | jq -r '.data.repository.issues.nodes[] | "\(.number)\t\(.parent.number // "-")\t\(.subIssues.totalCount)"' >> "$GRAPH" 2>/dev/null || break
      [ "$(printf '%s' "$_out" | jq -r '.data.repository.issues.pageInfo.hasNextPage')" = true ] || break
      _cur="$(printf '%s' "$_out" | jq -r '.data.repository.issues.pageInfo.endCursor')"
    done
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
      while IFS='	' read -r num par kids; do
        labs="$(awk -F'\t' -v k="$num" '$1==k{print $2}' "$A")"
        case ",$labs," in *",epic:"*) is_epic=yes ;; *) is_epic=no ;; esac
        [ "$is_epic" = yes ] && [ "$kids" -eq 0 ] && epicnokid="$epicnokid #$num"
        [ "$is_epic" = no ]  && [ "$kids" -gt 0 ] && kidnoepic="$kidnoepic #$num"
      done < "$GRAPH"
      [ -n "$epicnokid" ] && { printf '  epic:* that parents nothing:%s\n' "$epicnokid"; FAIL=1; }
      [ -n "$kidnoepic" ] && { printf '  parents carrying no epic:*:%s\n' "$kidnoepic"; FAIL=1; }
      orph="$(awk -F'\t' '$2=="-" && $3==0 {n++} END{print n+0}' "$GRAPH")"
      printf '  %s issue(s) with no parent and no children\n' "$orph"
      [ -z "$closedpar$epicnokid$kidnoepic" ] && printf '  edges consistent\n'
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
    # `|| true` IS LOAD-BEARING AND IS NOT COSMETIC. This pipeline is the last
    # command in the --audit arm, and `set -e` is on (line 50). Its status is the
    # loop body's final `[ -n "$lonely" ] && printf`, which is FALSE whenever the
    # LAST theme happens to have no lonely issue. The script then died HERE with
    # status 1, and everything below — including the whole --strict gate — never
    # ran. Measured 2026-09-21 on live harbor: `--audit` and `--audit --strict`
    # both exited 1, the second one not because it was strict. An AND-OR list
    # exempts every command but the last from `set -e`, which is the whole fix.
    done || true

    rm -f "$A" "$ALLOPEN" "$GRAPH" "$AX" "$MAP"
    # REPORTING IS THE DEFAULT AND FAILING IS OPT-IN. Turning 67 standing
    # violations into a red exit on day one is the false positive CONSTITUTION
    # No.2 clause 11 names: a checker that blocks ordinary work gets switched off.
    # --strict is what CI uses once the count is zero.
    if [ "$STRICT" = yes ] && [ "$FAIL" -ne 0 ]; then
      printf '\naudit: violations above, and --strict was given\n' >&2
      exit 1
    fi
    ;;
  *)
    printf 'issue-connector: unknown mode %s — see --help\n' "${mode:-<none>}" >&2
    exit 2 ;;
esac
