#!/usr/bin/env sh
# findings.sh (harbor#590) — the lint tier of CONTRACTS/finding.md: the census in, the delta out.
#
#   sh bin/findings.sh reconcile [--apply] [--from <dir>]   run lint, diff it against the store, print the delta
#   sh bin/findings.sh report                              the store alone: the ages, and when it was last written
#   sh bin/findings.sh accept <key> --reason "<why>"       a person, at their own terminal
#   sh bin/findings.sh supersede <key> --by "<what>"       a person, at their own terminal
#   sh bin/findings.sh heal [--apply] [--from <dir>]        run the repairs the contract's HEAL rows declare (#856)
#   sh bin/findings.sh lanes                               the lanes table, as the contract declares it
#   sh bin/findings.sh digest <subject>...                 the contract's digest of a subject set
#
# reconcile WRITES NOTHING WITHOUT --apply, and --apply refuses unless this checkout is the published
# default branch (HEAD is origin/main and the tree is clean): a result from a branch describes the
# operator's own work, and filing it would publish a failure main may not have. --from <dir> reads
# a lint run already captured there (records.tsv, lint.log) instead of running lint again.
#
# THE STORE IS THE DESTINATION: GitHub issues labelled `finding`, keyed by a hidden marker. There is
# no state file, so there is nothing here to lose track and nothing to go quiet on its own.
#
# A DISPOSITION IS A PERSON'S. accept and supersede refuse without a terminal on stdin and stdout and
# inside an agent session, and ask for the key back. Nothing here accepts, and only `heal` repairs:
# what a HEAL row in the contract names, on the subjects it matches, as a draft PR when a tracked
# file changes. `heal` without --apply prints the plan and runs nothing.
#
#   HARBOR_FINDINGS_REPO   owner/name of the store; defaults to this checkout's origin
#   HARBOR_ROOT            the checkout to reconcile; defaults to the one this script is in
#
# Deliberately one file (DOCTRINE/modularity.md): its parts share one census, one store and one temp
# dir, and nothing outside calls them. Re-ask with `sh bin/module-shape.sh --seam bin/findings.sh`.
set -eu
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
esac
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HARBOR_ROOT:-$(CDPATH='' cd -- "$HERE/.." && pwd)}"
. "$HERE/log-lib.sh"
log_init findings
LINT="$HERE/lint-conventions.sh"
CONTRACT="$ROOT/CONTRACTS/finding.md"
TODAY="${HARBOR_FINDINGS_NOW:-$(date -u +%Y-%m-%d)}"
case "$TODAY" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) TODAY="$(date -u +%Y-%m-%d)" ;; esac
umask 077
T="$(mktemp -d "${TMPDIR:-/tmp}/findings.XXXXXX")"
# heal registers worktrees and branches under $T: a signal must unregister them, not just delete the directory
HEAL_BR=""
cleanup() {
  rm -rf "$T"
  [ -z "$HEAL_BR" ] || { git -C "$ROOT" worktree prune 2>/dev/null; git -C "$ROOT" branch -D "$HEAL_BR" >/dev/null 2>&1; } || :
}
trap cleanup EXIT
trap 'cleanup; trap - EXIT; exit 130' INT TERM HUP

usage() { log_fail "$1"; log_fix "sh $HERE/findings.sh --help"; log_end || :; exit 2; }
stop()  { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }

_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
# The contract's digest: the subjects one per line, LC_ALL=C sort -u, newline-terminated, 16 hex.
digest_of_file() { LC_ALL=C sort -u "$1" | _sha | cut -c1-16; }

repo() {
  [ -z "${HARBOR_FINDINGS_REPO:-}" ] || { printf '%s' "$HARBOR_FINDINGS_REPO"; return 0; }
  git -C "$ROOT" remote get-url origin 2>/dev/null \
    | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##'
}

# The lanes block, as `lane TAB key TAB subject TAB repair` rows. Lint FL1 holds its shape.
lanes() {
  awk '/^<!-- lanes:begin -->$/ { t = 1; next } /^<!-- lanes:end -->$/ { t = 0 } t && /^\|/' "$CONTRACT" 2>/dev/null \
    | awk -F'|' '{ for (i = 2; i < NF; i++) { f = $i; gsub(/`/, "", f); gsub(/^[[:space:]]+|[[:space:]]+$/, "", f); $i = f }
                   if ($2 == "lane" || $2 ~ /^-+$/) next
                   printf "%s\t%s\t%s\t%s\n", $2, $3, $4, $5 }'
}
# lane_of <key> <subjects-file> → the lane, and for a split key `HEAL for n of m`
lane_of() {
  _lk="$1"; _lm=0; _ln=0; _ll=PROPOSE
  [ -f "$T/lanes" ] || lanes > "$T/lanes"
  while IFS= read -r _ls; do
    _ln=$((_ln + 1))
    [ "$_ls" != stood-down ] || continue   # a check that could not look is a person's to read (harbor#896)
    while IFS='	' read -r _rl _rk _rs _rr; do
      [ "$_rk" = "$_lk" ] || continue
      # shellcheck disable=SC2254
      case "$_ls" in $_rs) _lm=$((_lm + 1)); _ll="$_rl"; break ;; esac
    done < "$T/lanes"
  done < "$2"
  if [ "$_lm" -eq 0 ]; then printf 'PROPOSE'
  elif [ "$_lm" -eq "$_ln" ]; then printf '%s' "$_ll"
  else printf '%s for %s of %s subjects' "$_ll" "$_lm" "$_ln"; fi
}

# ── the store ────────────────────────────────────────────────────────────────
# EVERY FIELD IS NON-EMPTY ("-" for none): tab is IFS whitespace, so `read` collapses an empty field
# and shifts every column after it.
# One read. A store that cannot be read is a FAIL, never an empty store: an empty one would file
# every finding again, and "nothing is open" and "I could not look" must not render the same.
# The label-filtered list lagged a just-created issue by seconds (harbor#893), and an --apply in that
# window files the finding twice. A lookup by number reads the issue itself, so the newest numbers are
# read that way, in one GraphQL call, and any finding the list missed is merged in. Lag is a tail
# effect, so the window is the newest numbers only: RECENT below the repo's head, and a few past it.
RECENT=50
recent_findings() {
  : > "$T/recovered"
  _head="$(gh api "repos/$REPO/issues?state=all&sort=created&direction=desc&per_page=1" --jq '.[0].number // 0' 2>"$T/gh.err")" \
    || stop "could not read the newest issue number at $REPO: $(head -1 "$T/gh.err")" "gh auth status"
  _top="$(jq '[.[].number] | max // 0' "$T/store.json")"
  [ "$_top" -gt "$_head" ] 2>/dev/null && _head="$_top"
  _lo=$((_head - RECENT)); [ "$_lo" -ge 1 ] || _lo=1
  _q=""; _n="$_lo"
  while [ "$_n" -le $((_head + 10)) ]; do
    _q="$_q n$_n: issueOrPullRequest(number: $_n) { ... on Issue { number state stateReason createdAt body labels(first: 20) { nodes { name } } } }"
    _n=$((_n + 1))
  done
  # A number that does not exist is null in .data and an error on stderr, so the call is judged by .data.
  gh api graphql -f query="{ repository(owner: \"${REPO%%/*}\", name: \"${REPO#*/}\") {$_q } }" > "$T/recent.json" 2>"$T/gh.err" || :
  jq -e '.data.repository' "$T/recent.json" >/dev/null 2>&1 \
    || stop "could not read the newest issues at $REPO by number: $(head -1 "$T/gh.err")" "gh auth status"
  jq --slurpfile have "$T/store.json" '[.data.repository[] | select(. != null and .number != null)
      | select(any(.labels.nodes[]; .name == "finding"))
      | select(.number as $n | ($have[0] | map(.number) | index($n)) == null)
      | {number, state, stateReason, createdAt, body, labels: .labels.nodes}]' "$T/recent.json" > "$T/missed.json"
  jq -r '.[].number' "$T/missed.json" > "$T/recovered"
  [ -s "$T/recovered" ] || return 0
  jq -s '.[0] + .[1]' "$T/store.json" "$T/missed.json" > "$T/store.u" && mv "$T/store.u" "$T/store.json"
}
# A lint key filed under a deprecated letter id (lint/X5) is the same finding as its successor's
# (lint/drift.prod-policy-copy, D-19, harbor#957). The store is read through the linter's own map, so
# a rename orphans nothing: the row joins under the successor, and column 10 keeps the key its marker
# still spells, which reconcile --apply rewrites. `--ids` from a linter without it is an empty map.
successors() { # → $T/succ: `letter TAB id`
  [ -f "$T/succ" ] || { sh "$LINT" --ids 2>/dev/null | awk -F'\t' 'NR > 1 && $2 != "-" { print $2 "\t" $1 }' > "$T/succ" || :; }
}
canon_key() { # <key> → the key under its current id
  successors
  awk -F'\t' -v k="$1" 'BEGIN { split(k, p, "/") } p[1] == "lint" && $1 == substr(k, 6) { print "lint/" $2; f = 1; exit }
                         END { if (!f) print k }' "$T/succ"
}
read_store() { # → $T/store.tsv: number state reason dispositions created key digest seen schema marker-key
  gh issue list -R "$REPO" --label finding --state all --limit 1000 \
     --json number,state,stateReason,labels,createdAt,body > "$T/store.json" 2>"$T/gh.err" \
    || stop "could not read the finding store at $REPO: $(head -1 "$T/gh.err")" "gh auth status"
  recent_findings
  jq -r '.[] | . as $i
    | ((($i.body // "") | capture("<!-- harbor:finding key=(?<k>[^ ]+) digest=(?<d>[^ ]+) seen=(?<s>[^ ]+) schema=(?<v>[0-9]+) -->")?) // {}) as $m
    | [ $i.number, ($i.state | ascii_downcase), (($i.stateReason // "") | ascii_downcase),
        ([$i.labels[]?.name | select(startswith("finding:")) | ltrimstr("finding:")] | join(",")),
        (($i.createdAt // "") | .[0:10]), ($m.k // "-"), ($m.d // "-"), ($m.s // "-"), ($m.v // "-") ]
    | map(tostring | if . == "" then "-" else . end) | @tsv' \
    "$T/store.json" | sort -t'	' -k1,1nr > "$T/store.raw" \
    || stop "the finding store at $REPO did not parse" "gh issue list -R $REPO --label finding --state all --json number,body"
  successors
  # The map is read in BEGIN, never as a first file: an empty map would make NR == FNR hold for the
  # store itself and swallow every row, and an empty store files every finding again.
  awk -F'\t' -v OFS='\t' -v S="$T/succ" 'BEGIN { while ((getline l < S) > 0) { split(l, p, "\t"); s["lint/" p[1]] = "lint/" p[2] } }
       { m = "-"; if ($6 in s) { m = $6; $6 = s[$6] } print $0, m }' "$T/store.raw" > "$T/store.tsv"
}
# latest <key> → the newest issue's row for that key, or nothing
latest() { awk -F'\t' -v k="$1" '$6 == k { print; exit }' "$T/store.tsv"; }
age_days() { [ -n "$1" ] && [ "$1" != - ] || { printf '?'; return 0; }; jq -rn --arg a "$1" --arg b "$TODAY" '((($b|strptime("%Y-%m-%d")|mktime) - ($a|strptime("%Y-%m-%d")|mktime)) / 86400) | floor'; }
unreadable() { # rows that are not a finding this reader can classify
  awk -F'\t' '$6 == "-" || $9 == "-" || $9 > 1 || $6 !~ /^[a-z]+\/[A-Za-z0-9._:-]+$/' "$T/store.tsv"
}
last_written() { awk -F'\t' '$2 == "open" && $8 != "-" { print $8 }' "$T/store.tsv" | sort | tail -1; }

# ── report ───────────────────────────────────────────────────────────────────
cmd_report() {
  REPO="$(repo)"; [ -n "$REPO" ] || stop "no store: this checkout has no origin" "HARBOR_FINDINGS_REPO=<owner/name> sh $HERE/findings.sh report"
  read_store
  _n="$(grep -c . "$T/store.tsv" | tr -d ' ')"; _bad="$(unreadable | grep -c . | tr -d ' ')"
  _last="$(last_written)"
  printf 'findings: the store at %s, read %s — %s finding issue(s), %s it could not classify\n' "$REPO" "$TODAY" "$_n" "$_bad"
  if [ -n "$_last" ]; then printf '  last reconcile:  %s (%s day(s) ago)\n' "$_last" "$(age_days "$_last")"
  else printf '  last reconcile:  none — no reconcile has written this store, so nothing below is current\n'; fi
  awk -F'\t' '$2 == "open" && $6 != "-"' "$T/store.tsv" > "$T/open.tsv"
  _open="$(grep -c . "$T/open.tsv" | tr -d ' ')"
  if [ "$_open" -gt 0 ]; then
    _old="$(sort -t'	' -k5,5 "$T/open.tsv" | head -1)"
    printf '  oldest open:     %s, %s day(s) (#%s)\n' "$(printf '%s' "$_old" | cut -f6)" \
      "$(age_days "$(printf '%s' "$_old" | cut -f5)")" "$(printf '%s' "$_old" | cut -f1)"
    _b1=0; _b2=0; _b3=0
    while IFS='	' read -r _ _ _ _ _c _ _ _ _; do
      _a="$(age_days "$_c")"
      if [ "$_a" -lt 7 ]; then _b1=$((_b1 + 1)); elif [ "$_a" -lt 28 ]; then _b2=$((_b2 + 1)); else _b3=$((_b3 + 1)); fi
    done < "$T/open.tsv"
    printf '  ages:            %s under a week · %s one to four weeks · %s older\n' "$_b1" "$_b2" "$_b3"
    if [ -n "$_last" ]; then
      awk -F'\t' -v l="$_last" '$8 < l { printf "%s (seen %s) ", $6, $8 }' "$T/open.tsv" > "$T/stale"
      [ ! -s "$T/stale" ] || printf '  not seen by the last reconcile: %s\n' "$(cat "$T/stale")"
    fi
  fi
  printf '  open: %s · accepted: %s · superseded: %s · fixed: %s\n' "$_open" \
    "$(awk -F'\t' '$4 ~ /accepted/' "$T/store.tsv" | grep -c . | tr -d ' ')" \
    "$(awk -F'\t' '$4 ~ /superseded/' "$T/store.tsv" | grep -c . | tr -d ' ')" \
    "$(awk -F'\t' '$4 ~ /fixed/' "$T/store.tsv" | grep -c . | tr -d ' ')"
  log_end || :
}

# ── reconcile ────────────────────────────────────────────────────────────────
body_of() { # <key> <digest> <subjects-file> <evidence-file> <lane> → the issue body on stdout
  _bid="${1#*/}"
  printf '<!-- harbor:finding key=%s digest=%s seen=%s schema=1 -->\n' "$1" "$2" "$TODAY"
  printf '**`%s`** — %s\n\n' "$1" "$(title_of "$1")"
  case "$1" in
    check/*) _brule="the receipt \`~/.claude/cache/checks/$_bid.json\`, \`CHECKS.md\` row \`$_bid\`" ;;
    *)       _brule="\`sh bin/lint-conventions.sh --only $_bid\`" ;;
  esac
  printf 'Lane: **%s** · rule: %s · reconciled %s on `origin/main` %s\n\n' "$5" "$_brule" "$TODAY" "$SHA7"
  printf 'Subjects (%s):\n\n' "$(grep -c . "$3" | tr -d ' ')"
  head -50 "$3" | sed 's/^/- `/; s/$/`/'
  printf '\nEvidence, the rule'"'"'s own lines (replaced on every reconcile; evidence, not identity):\n\n```text\n'
  cut -c1-4000 "$4" | head -c 4000
  printf '\n```\n\nA person dispositions this, never the reconcile: `sh bin/findings.sh accept %s --reason "…"` or\n' "$1"
  printf '`supersede %s --by "…"` from their own terminal, or close it as *not planned* with the\n' "$1"
  printf '`finding:accepted` or `finding:superseded` label. Contract: `CONTRACTS/finding.md`.\n'
}
ensure_labels() {
  [ "$LABELS_OK" = 0 ] || return 0
  gh label list -R "$REPO" --search finding --limit 50 --json name --jq '.[].name' > "$T/labels" 2>/dev/null || : > "$T/labels"
  for _l in finding finding:accepted finding:superseded finding:fixed; do
    grep -qx "$_l" "$T/labels" && continue
    gh label create "$_l" -R "$REPO" --color 5319e7 --description "CONTRACTS/finding.md (harbor#590)" >/dev/null \
      || stop "could not create the $_l label on $REPO" "gh label create $_l -R $REPO"
  done
  LABELS_OK=1
}

# The census, with its subjects → $T/records.tsv lint.log ran titles registered pairs firing
census() {
  if [ -n "$FROM" ]; then
    { [ -f "$FROM/records.tsv" ] && [ -f "$FROM/lint.log" ]; } \
      || stop "--from $FROM holds no records.tsv and lint.log" "HARBOR_FINDINGS_OUT=$FROM/records.tsv sh $LINT > $FROM/lint.log 2>&1"
    cp "$FROM/records.tsv" "$T/records.tsv"; cp "$FROM/lint.log" "$T/lint.log"
  else
    : > "$T/records.tsv"
    HARBOR_ROOT="$ROOT" HARBOR_FINDINGS_OUT="$T/records.tsv" sh "$LINT" > "$T/lint.log" 2>&1 || :
  fi
  # A capture from a linter that still spoke letter ids (--from) is read under the current ids.
  successors
  awk -F'\t' -v OFS='\t' -v S="$T/succ" 'BEGIN { while ((getline l < S) > 0) { split(l, p, "\t"); s[p[1]] = p[2] } }
       ($1 == "R" || $1 == "A" || $1 == "V") && ($2 in s) { $2 = s[$2] } { print }' "$T/records.tsv" > "$T/records.c" \
    && mv "$T/records.c" "$T/records.tsv"
  awk -F'\t' '$1 == "R" { print "lint/" $2 }' "$T/records.tsv" | sort -u > "$T/ran"
  [ -s "$T/ran" ] || stop "lint recorded no rule running — the emitter is not wired, so there is nothing to reconcile" "HARBOR_FINDINGS_OUT=/dev/stdout sh $LINT --only T9"
  sh "$LINT" --list 2>/dev/null | sed 's/^  //; s#^#lint/#' > "$T/titles"
  awk -F'\t' '($1 == "A" || $1 == "V") && $3 != "" { print "lint/" $2 "\t" $3 }' "$T/records.tsv" > "$T/pairs"
  receipts
  awk '{ print $1 }' "$T/titles" | sort -u > "$T/registered"
  LC_ALL=C sort -u "$T/pairs" -o "$T/pairs"
  cut -f1 "$T/pairs" | sort -u > "$T/firing"
}
# The check tier (harbor#896): each check's own receipt, never a re-run. A receipt is fresh when it is
# at most RECEIPT_DAYS old: fresh means the check ran, so green closes its finding; stale or missing
# means not seen, which is never fixed. A receipt whose id is not a CHECKS.md row is refused.
RECEIPT_DAYS=2
receipts() {
  : > "$T/check.ev"; : > "$T/receipt.refused"
  _rdir="$(receipt_dir)"
  # The register is core CHECKS.md plus the private layer's rows (harbor#1149): a receipt from a client check has a row too.
  { sh "$HERE/check-registry-generate.sh" --core "$ROOT/CHECKS.md" 2>/dev/null \
      || { log_warn "the private layer's checks.md does not compose into the register, so receipts are judged against core CHECKS.md alone"; log_fix "sh $HERE/check-registry-generate.sh   # names the line"; cat "$ROOT/CHECKS.md" 2>/dev/null; }; } \
    | awk -F'|' '/^\| `[a-z0-9.-]+` \|/ { id = $2; gsub(/[` ]/, "", id); print id }' \
    | sort -u > "$T/checks.ids"
  sed 's#^\(.*\)$#check/\1 the `\1` check (CHECKS.md)#' "$T/checks.ids" >> "$T/titles"
  [ -d "$_rdir" ] || return 0
  for _rf in "$_rdir"/*.json; do
    [ -f "$_rf" ] || continue
    jq -r --arg now "$TODAY" --argjson max "$RECEIPT_DAYS" '
      select(type == "object" and (.id | type) == "string" and (.status | type) == "string") |
((($now | strptime("%Y-%m-%d") | mktime) - ((.ran_at // "1970-01-01")[0:10] | strptime("%Y-%m-%d") | mktime)) / 86400) as $age |
      (if (.fresh_days | type) == "number" and .fresh_days >= 1 and .fresh_days <= 31 then .fresh_days else $max end) as $win |
      [.id, .status, (if $age < 0 then "future" elif $age <= $win then "fresh" else "stale" end)] + ((.subjects // []) | map(tostring)) | @tsv' \
      "$_rf" 2>/dev/null > "$T/r1" || continue
    [ -s "$T/r1" ] || continue
    IFS='	' read -r _ri _rs _rfr _ < "$T/r1"
    [ "${_rf##*/}" = "$_ri.json" ] || { printf 'check/%s (receipt %s names another id)\n' "$_ri" "${_rf##*/}" >> "$T/receipt.refused"; continue; }
    if ! grep -qxF "$_ri" "$T/checks.ids"; then printf 'check/%s (receipt with no CHECKS.md row)\n' "$_ri" >> "$T/receipt.refused"; continue; fi
    # An unknown status is refused, never read as a run: a run that fires nothing would close the finding.
    case "$_rs" in green|red|stood-down) ;; *) printf 'check/%s (receipt status %s is not green, red or stood-down)\n' "$_ri" "$_rs" >> "$T/receipt.refused"; continue ;; esac
    # A receipt dated after today is refused: it would read as fresh until its date arrived (review #898).
    [ "$_rfr" != future ] || { printf 'check/%s (receipt dated after %s)\n' "$_ri" "$TODAY" >> "$T/receipt.refused"; continue; }
    [ "$_rfr" = fresh ] || continue
    printf 'check/%s\n' "$_ri" >> "$T/ran"
    printf 'check/%s\t%s\n' "$_ri" "$(jq -c . "$_rf")" >> "$T/check.ev"
    case "$_rs" in
      red)        tr '\t' '\n' < "$T/r1" | tail -n +4 | grep . > "$T/r2" || printf '%s\n' "$_ri" > "$T/r2"
                  sed "s#^#check/$_ri	#" "$T/r2" >> "$T/pairs" ;;
      stood-down) printf 'check/%s\tstood-down\n' "$_ri" >> "$T/pairs" ;;
    esac
  done
  sort -u "$T/ran" -o "$T/ran"
}
title_of() { awk -v k="$1" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$T/titles"; }
evidence_of() { # <key> → the rule's own lines on stdout
  case "$1" in
    lint/*) grep -F -e "ADVISORY [${1#lint/}]" -e "VIOLATION [${1#lint/}]" "$T/lint.log" 2>/dev/null | sed "s#$HOME/#~/#g" || : ;;
    check/*) awk -F'\t' -v k="$1" '$1 == k { print $2 }' "$T/check.ev" | sed "s#$HOME/#~/#g" ;;
  esac
}
# published <verb> — sets SHA SHA7 PUB ON_MAIN; with APPLY=1, refuses anything but the published default branch
published() {
  SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"; SHA7="$(printf '%.7s' "$SHA")"
  PUB="$(git -C "$ROOT" rev-parse -q --verify refs/remotes/origin/main 2>/dev/null || :)"
  if [ "$SHA" = "$PUB" ] && [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then ON_MAIN=1; else ON_MAIN=0; fi
  if [ "$APPLY" = 1 ] && [ "$ON_MAIN" = 0 ]; then
    stop "--apply ${1}s only the published default branch, and $ROOT is at $SHA7 with origin/main at $(printf '%.7s' "${PUB:-none}")$( [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || printf ', with local changes')" \
      "git -C $ROOT fetch origin && git -C $ROOT worktree add --detach $ROOT.findings origin/main && HARBOR_ROOT=$ROOT.findings sh $HERE/findings.sh $1 --apply"
  fi
}

cmd_reconcile() {
  APPLY=0; FROM=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) APPLY=1 ;;
      --from)  FROM="${2:-}"; [ -n "$FROM" ] || usage "--from needs a directory"; shift ;;
      *) usage "reconcile: unknown option $1" ;;
    esac
    shift
  done
  REPO="$(repo)"; [ -n "$REPO" ] || stop "no store: this checkout has no origin" "HARBOR_FINDINGS_REPO=<owner/name> sh $HERE/findings.sh reconcile"
  [ -f "$CONTRACT" ] || stop "no contract at $CONTRACT — nothing says what a finding is" "git -C $ROOT checkout origin/main -- CONTRACTS/finding.md"
  published reconcile

  # 1 · the census, with its subjects
  census

  # 2 · the store
  read_store
  LAST="$(last_written)"
  unreadable | awk -F'\t' '{ printf "#%s (no readable marker)\n", $1 }' > "$T/unclassified"
  LABELS_OK=0
  for _f in new changed fixed reopened again notseen accepted superseded standing rekeyed; do : > "$T/r.$_f"; done
  _wrote=0

  # 3 · every rule that fired
  cat "$T/receipt.refused" >> "$T/unclassified"
  while IFS= read -r _k; do
    awk -F'\t' -v k="$_k" '$1 == k { print $2 }' "$T/pairs" > "$T/subj"
    _d="$(digest_of_file "$T/subj")"; _ns="$(grep -c . "$T/subj" | tr -d ' ')"
    evidence_of "$_k" > "$T/ev"
    _lane="$(lane_of "$_k" "$T/subj")"
    body_of "$_k" "$_d" "$T/subj" "$T/ev" "$_lane" > "$T/body"
    _row="$(latest "$_k")"
    _num="$(printf '%s' "$_row" | cut -f1)"; _st="$(printf '%s' "$_row" | cut -f2)"
    _disp="$(printf '%s' "$_row" | cut -f4)"; _od="$(printf '%s' "$_row" | cut -f7)"; _os="$(printf '%s' "$_row" | cut -f8)"
    _mk="$(printf '%s' "$_row" | cut -f10)"
    _why=""
    if [ -z "$_row" ]; then _why=new
    elif [ "$_st" = open ]; then
      # A marker still spelling a deprecated id is rewritten with the body, title and all (harbor#957).
      _rk=0; [ -z "$_mk" ] || [ "$_mk" = - ] || {
        _rk=1; printf '%s → %s (#%s)\n' "$_mk" "$_k" "$_num" >> "$T/r.rekeyed"; }
      if [ "$_od" != "$_d" ]; then
        printf '%s (#%s, now %s subject(s))\n' "$_k" "$_num" "$_ns" >> "$T/r.changed"
        [ "$APPLY" = 0 ] || { gh issue edit "$_num" -R "$REPO" --body-file "$T/body" >/dev/null || stop "could not update #$_num" "gh issue view $_num -R $REPO"; _wrote=$((_wrote + 1)); }
      else
        printf '%s\n' "$_k" >> "$T/r.standing"
        [ "$APPLY" = 0 ] || { [ "$_os" = "$TODAY" ] && [ "$_rk" = 0 ]; } || { gh issue edit "$_num" -R "$REPO" --body-file "$T/body" >/dev/null || stop "could not update #$_num" "gh issue view $_num -R $REPO"; _wrote=$((_wrote + 1)); }
      fi
      [ "$APPLY" = 0 ] || [ "$_rk" = 0 ] || gh issue edit "$_num" -R "$REPO" --title "finding $_k: $(title_of "$_k" | cut -c1-90)" >/dev/null \
        || stop "could not retitle #$_num under $_k" "gh issue view $_num -R $REPO"
    else
      case ",$_disp," in
        *,accepted,*|*,superseded,*)
          _dn="accepted"; case ",$_disp," in *,superseded,*) _dn=superseded ;; esac
          if [ "$_od" = "$_d" ]; then printf '%s\n' "$_k" >> "$T/r.$_dn"
          else _why="$_dn, digest changed (was #$_num)"; fi ;;
        *,fixed,*) _why="recurred (was #$_num, fixed)" ;;
        *)         _why="closed without a disposition, filed again (was #$_num)" ;;
      esac
    fi
    [ -n "$_why" ] || continue
    if [ "$APPLY" = 1 ]; then
      ensure_labels
      [ "$_why" = new ] || printf '\nThis finding follows #%s: %s.\n' "$_num" "$_why" >> "$T/body"
      _url="$(gh issue create -R "$REPO" --title "finding $_k: $(title_of "$_k" | cut -c1-90)" \
                --label finding --body-file "$T/body")" || stop "could not file $_k" "gh auth status"
      _wrote=$((_wrote + 1)); _ref="filed #${_url##*/}"
    else _ref="would file"; fi
    if [ "$_why" = new ]; then printf '%s (%s subject(s)) · %s · %s\n' "$_k" "$_ns" "$_lane" "$_ref" >> "$T/r.new"
    else printf '%s → %s · %s\n' "$_k" "$_ref" "$_why" >> "$T/r.reopened"; fi
  done < "$T/firing"

  # 4 · every open finding whose rule did not fire
  awk -F'\t' '$2 == "open" && $6 ~ /^(lint|check)\//' "$T/store.tsv" | while IFS='	' read -r _num _ _ _ _ _k _ _os _; do
    grep -qx "$_k" "$T/firing" && continue
    if ! grep -qx "$_k" "$T/registered"; then printf '%s (#%s, no such rule)\n' "$_k" "$_num" >> "$T/unclassified"
    elif grep -qx "$_k" "$T/ran"; then printf '%s #%s\n' "$_k" "$_num" >> "$T/r.fixed"
    else printf '%s (#%s, seen %s)\n' "$_k" "$_num" "$_os" >> "$T/r.notseen"; fi
  done
  if [ "$APPLY" = 1 ]; then
    while IFS=' ' read -r _k _n; do
      [ -n "$_k" ] || continue
      ensure_labels
      case "$_k" in
        check/*) _how="its receipt was fresh and green on $TODAY" ;;
        *)       _how="it ran on origin/main $SHA7 on $TODAY and did not fire" ;;
      esac
      gh issue close "${_n#\#}" -R "$REPO" --reason completed \
        --comment "fixed: \`$_k\` — $_how (CONTRACTS/finding.md)." >/dev/null \
        && gh issue edit "${_n#\#}" -R "$REPO" --add-label finding:fixed >/dev/null \
        || stop "could not close $_n" "gh issue view ${_n#\#} -R $REPO"
      _wrote=$((_wrote + 1))
    done < "$T/r.fixed"
  fi

  # 5 · the delta and the ages, never the census
  _mode="dry run, nothing written"; [ "$APPLY" = 0 ] || _mode="$_wrote write(s)"
  [ "$ON_MAIN" = 1 ] || _mode="$_mode; NOT the published default branch"
  printf 'findings: reconciled %s against %s at %s (%s) — examined %s rules and %s checks, could not classify %s\n' \
    "$TODAY" "$REPO" "$SHA7" "$_mode" "$(grep -vc '^check/' "$T/ran" | tr -d ' ')" "$(grep -c '^check/' "$T/ran" | tr -d ' ')" \
    "$(grep -c . "$T/unclassified" | tr -d ' ')"
  _since="new since $LAST:"; [ -n "$LAST" ] || _since="new (first reconcile):"
  _line() { [ -s "$2" ] || return 0; _h="$1"; while IFS= read -r _x; do printf '  %-27s %s\n' "$_h" "$_x"; _h=""; done < "$2"; }
  _line "$_since" "$T/r.new"
  _line "subjects changed:" "$T/r.changed"
  _line "fixed:" "$T/r.fixed"
  _line "re-filed:" "$T/r.reopened"
  _rkh="re-keyed (D-19):"; [ "$APPLY" = 1 ] || _rkh="would re-key (D-19):"
  _line "$_rkh" "$T/r.rekeyed"
  awk -F'\t' '$2 == "open" && $6 ~ /^(lint|check)\// { print $5 "\t" $6 "\t" $1 }' "$T/store.tsv" | sort | head -1 > "$T/oldest"
  if [ -s "$T/oldest" ]; then
    IFS='	' read -r _oc _ok _on < "$T/oldest"
    printf '  %-27s %s, %s day(s) (#%s)\n' "oldest open:" "$_ok" "$(age_days "$_oc")" "$_on"
  fi
  # Open AFTER this run: what stands, what changed, what was (or would be) filed, and what was not seen.
  printf '  open: %s · accepted: %s · superseded: %s · not seen this run: %s%s\n' \
    "$(cat "$T/r.standing" "$T/r.changed" "$T/r.new" "$T/r.reopened" "$T/r.notseen" | grep -c . | tr -d ' ')" \
    "$(grep -c . "$T/r.accepted" | tr -d ' ')" \
    "$(grep -c . "$T/r.superseded" | tr -d ' ')" "$(grep -c . "$T/r.notseen" | tr -d ' ')" \
    "$( [ ! -s "$T/r.notseen" ] || printf ' (%s — the rule did not run)' "$(tr '\n' ' ' < "$T/r.notseen" | sed 's/ $//')")"
  _line "could not classify:" "$T/unclassified"
  [ ! -s "$T/recovered" ] || printf '  %-27s %s\n' "missed by the list, read:" "$(sed 's/^/#/' "$T/recovered" | tr '\n' ' ' | sed 's/ $//') — GitHub's issue list lagged (harbor#893)"
  if [ -n "$LAST" ]; then printf '  %-27s %s (%s day(s) before this run)\n' "store last written:" "$LAST" "$(age_days "$LAST")"
  else printf '  %-27s never — this is the first reconcile of %s\n' "store last written:" "$REPO"; fi
  log_end || :
}

# ── heal (harbor#856) ────────────────────────────────────────────────────────
# Only a HEAL row repairs, and the repair is the row's own text: nothing here names a command. A
# subject reaches the repair as "$1", never spliced into the string, and one that is not a plain
# path or id is refused. Repairs run in a throwaway worktree at origin/main, so the operator's
# checkout is never touched; a tracked change there becomes a DRAFT PR, never a push to main.
# Each repair is written into its finding's issue, so one that keeps coming back reads as a recurrence.
heal_comment() { # <issue> <file>
  gh issue comment "$1" -R "$REPO" --body-file "$2" >/dev/null || stop "could not write the repair into #$1" "gh issue view $1 -R $REPO"
}
heal_who() { if [ "$2" = - ]; then printf '%s' "$1"; else printf '%s %s' "$1" "$2"; fi; }  # <key> <subject|->
cmd_heal() {
  APPLY=0; FROM=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply) APPLY=1 ;;
      --from)  FROM="${2:-}"; [ -n "$FROM" ] || usage "--from needs a directory"; shift ;;
      *) usage "heal: unknown option $1" ;;
    esac
    shift
  done
  REPO="$(repo)"; [ -n "$REPO" ] || stop "no store: this checkout has no origin" "HARBOR_FINDINGS_REPO=<owner/name> sh $HERE/findings.sh heal"
  [ -f "$CONTRACT" ] || stop "no contract at $CONTRACT — nothing says what may repair" "git -C $ROOT checkout origin/main -- CONTRACTS/finding.md"
  published heal
  census
  read_store
  lanes > "$T/lanes"
  for _f in plan fixed failed pr propose unfiled refused unseen; do : > "$T/h.$_f"; done
  _i=0

  # The HEAL keys this run has no record of (a rule that did not run, a check with no fresh receipt)
  # say so, never "healthy".
  awk -F'\t' '$1 == "HEAL" { print $2 }' "$T/lanes" | sort -u | while IFS= read -r _hk; do
    grep -qx "$_hk" "$T/ran" || printf '%s\n' "$_hk" >> "$T/h.unseen"
  done

  while IFS= read -r _k; do
    awk -F'\t' -v k="$_k" '$1 == k { print $2 }' "$T/pairs" > "$T/subj"
    # every subject a HEAL row matches → `repair TAB subject`; a repair with no <subject> runs once
    : > "$T/todo"; _nm=0; _ns=0
    while IFS= read -r _s; do
      _ns=$((_ns + 1))
      while IFS='	' read -r _rl _rk _rs _rr; do
        [ "$_rl" = HEAL ] && [ "$_rk" = "$_k" ] && [ "$_s" != stood-down ] || continue
        # shellcheck disable=SC2254
        case "$_s" in $_rs) ;; *) continue ;; esac
        _nm=$((_nm + 1))
        case "$_s" in *..*|-*|*[!A-Za-z0-9._/~:@+-]*)
          printf '%s %s (not a plain path or id)\n' "$_k" "$_s" >> "$T/h.refused"; break ;; esac
        case "$_rr" in
          *'<subject>'*) printf '%s\t%s\n' "$(printf '%s' "$_rr" | sed 's/<subject>/"$1"/g')" "$_s" >> "$T/todo" ;;
          *)             printf '%s\t-\n' "$_rr" >> "$T/todo" ;;
        esac
        break
      done < "$T/lanes"
    done < "$T/subj"
    [ "$_nm" -gt 0 ] || { printf '%s\n' "$_k" >> "$T/h.propose"; continue; }
    [ "$_nm" -eq "$_ns" ] || printf '%s (%s of %s subjects)\n' "$_k" "$((_ns - _nm))" "$_ns" >> "$T/h.propose"
    sort -u "$T/todo" > "$T/todo.u"
    [ -s "$T/todo.u" ] || continue
    _row="$(latest "$_k")"
    if [ -z "$_row" ] || [ "$(printf '%s' "$_row" | cut -f2)" != open ]; then
      printf '%s\n' "$_k" >> "$T/h.unfiled"; continue
    fi
    _num="$(printf '%s' "$_row" | cut -f1)"; _d="$(digest_of_file "$T/subj")"
    if [ "$APPLY" = 0 ]; then
      while IFS='	' read -r _c _s; do printf '%s → %s\n' "$(heal_who "$_k" "$_s")" "$_c" >> "$T/h.plan"; done < "$T/todo.u"
      continue
    fi
    # The branch carries main's commit, so a recurrence after a merged or closed PR never meets an
    # old branch; an open PR for the same key and digest, on any commit, is the one to reuse.
    _bp="heal/$(printf '%s' "$_k" | tr '/' '-')-$_d-"; _br="$_bp$SHA7"
    gh pr list -R "$REPO" --state open --limit 1000 --json number,headRefName,url,isCrossRepository > "$T/prs.json" 2>/dev/null \
      || stop "could not ask $REPO for an open heal PR" "gh pr list -R $REPO --state open"
    _open="$(jq -r --arg p "$_bp" '[.[] | select(.isCrossRepository == false and (.headRefName | startswith($p)))][0] | select(.) | "\(.number) \(.url)"' "$T/prs.json")"
    if [ -n "$_open" ]; then
      printf '%s → draft PR #%s, already open\n' "$_k" "${_open%% *}" >> "$T/h.pr"
      # a run that died between the PR and the comment left the finding without its record
      gh issue view "$_num" -R "$REPO" --json comments > "$T/cm.json" 2>/dev/null \
        || stop "could not read #$_num's comments" "gh issue view $_num -R $REPO"
      if [ "$(jq --arg u "${_open#* }" '[.comments[]?.body | select(contains($u))] | length' "$T/cm.json")" = 0 ]; then
        printf 'healed earlier as draft PR %s; the run that opened it did not write it here, so this is that record.\n' "${_open#* }" > "$T/note"
        heal_comment "$_num" "$T/note"
      fi
      continue
    fi

    _i=$((_i + 1)); _wt="$T/wt.$_i"; _bad=0; HEAL_BR="$_br"
    git -C "$ROOT" worktree add -q --detach "$_wt" "$SHA" 2>"$T/wt.err" \
      || stop "could not make a worktree to repair $_k in: $(head -1 "$T/wt.err")" "git -C $ROOT worktree prune"
    { printf 'healed %s on `origin/main` %s (HEAL lane, CONTRACTS/finding.md):\n\n' "$TODAY" "$SHA7"; } > "$T/note"
    while IFS='	' read -r _c _s; do
      _rc=0; ( cd "$_wt" && sh -c "$_c" heal "$_s" ) > "$T/out" 2>&1 || _rc=$?
      if [ "$_s" = - ]; then printf -- '- `%s` → exit %s\n' "$_c" "$_rc" >> "$T/note"
      else printf -- '- `%s` on `%s` → exit %s\n' "$_c" "$_s" "$_rc" >> "$T/note"; fi
      if [ "$_rc" -eq 0 ]; then printf '%s → %s\n' "$(heal_who "$_k" "$_s")" "$_c" >> "$T/h.fixed"
      else _bad=1; printf '%s → %s (exit %s)\n' "$(heal_who "$_k" "$_s")" "$_c" "$_rc" >> "$T/h.failed"
        printf '```text\n%s\n```\n' "$(tail -c 1500 "$T/out")" >> "$T/note"; fi
    done < "$T/todo.u"
    # A failed repair publishes nothing: its partial changes go with the worktree.
    if [ "$_bad" = 1 ]; then
      printf '\nA repair FAILED, so nothing was published: no branch, no PR. A person reads the output above.\n' >> "$T/note"
    elif [ -n "$(git -C "$_wt" status --porcelain --untracked-files=no)" ]; then
      # A branch already on origin is this same repair from a run whose PR failed: reuse it, never re-push.
      _pushed=0; git -C "$_wt" ls-remote --exit-code --heads origin "$_br" >/dev/null 2>&1 && _pushed=1 || :
      : > "$T/push.err"
      if [ "$_pushed" = 1 ] || { git -C "$_wt" checkout -q -b "$_br" \
           && git -C "$_wt" add -u \
           && git -C "$_wt" commit -q -m "heal($_k): the HEAL-lane repair for #$_num" \
           && git -C "$_wt" push -q -u origin "$_br" 2>"$T/push.err"; }; then
        { printf 'The HEAL-lane repair for finding #%s (`%s`), run by `sh bin/findings.sh heal --apply` (harbor#856).\n\n' "$_num" "$_k"
          sed 1,2d "$T/note"
          printf '\nA draft because a repair that changes a tracked file is reviewed, never pushed to main.\n'; } > "$T/prbody"
        if _pr="$(gh pr create -R "$REPO" --draft --base main --head "$_br" --title "heal $_k: the HEAL-lane repair for #$_num" --body-file "$T/prbody" 2>"$T/pr.err")"; then
          printf '\nA tracked file changed, so it is a draft PR: %s\n' "$_pr" >> "$T/note"
          printf '%s → draft PR %s\n' "$_k" "$_pr" >> "$T/h.pr"
        else
          _bad=1; printf '%s → pushed %s, could not open its PR: %s\n' "$_k" "$_br" "$(head -1 "$T/pr.err")" >> "$T/h.failed"
          printf '\n`%s` is on origin, and opening its draft PR FAILED. The next run reuses the branch.\n' "$_br" >> "$T/note"
        fi
      else
        _bad=1; printf '%s → could not push %s: %s\n' "$_k" "$_br" "$(head -1 "$T/push.err" 2>/dev/null)" >> "$T/h.failed"
        printf '\nThe repair changed a tracked file, and pushing `%s` FAILED, so there is no PR.\n' "$_br" >> "$T/note"
      fi
    else
      printf '\nNo tracked file changed, so there is no PR. The next reconcile closes this finding if the rule stops firing.\n' >> "$T/note"
    fi
    git -C "$ROOT" worktree remove --force "$_wt" 2>/dev/null || :
    git -C "$ROOT" branch -D "$_br" >/dev/null 2>&1 || :   # pushed or abandoned; origin holds what matters
    HEAL_BR=""
    heal_comment "$_num" "$T/note"
  done < "$T/firing"

  _mode="dry run, nothing repaired"; [ "$APPLY" = 0 ] || _mode="applied"
  [ "$ON_MAIN" = 1 ] || _mode="$_mode; NOT the published default branch"
  printf 'findings heal: %s at %s (%s) — %s rule(s) firing\n' "$TODAY" "$SHA7" "$_mode" "$(grep -c . "$T/firing" | tr -d ' ')"
  _line() { [ -s "$2" ] || return 0; _h="$1"; while IFS= read -r _x; do printf '  %-24s %s\n' "$_h" "$_x"; _h=""; done < "$2"; }
  _line "would repair:" "$T/h.plan"
  _line "repaired:" "$T/h.fixed"
  _line "FAILED:" "$T/h.failed"
  _line "proposed:" "$T/h.pr"
  _line "refused:" "$T/h.refused"
  _line "not filed yet:" "$T/h.unfiled"
  [ ! -s "$T/h.unfiled" ] || printf '  %-24s %s\n' "" "a repair is written into its finding, so reconcile --apply files it first"
  [ ! -s "$T/h.propose" ] || printf '  %-24s %s\n' "not HEAL, not repaired:" "$(tr '\n' ' ' < "$T/h.propose" | sed 's/ $//')"
  [ ! -s "$T/h.unseen" ] || printf '  %-24s %s — no fresh record this run (a rule that did not run, a check with no receipt), so it cannot be judged\n' "not visible:" "$(tr '\n' ' ' < "$T/h.unseen" | sed 's/ $//')"
  if [ -s "$T/h.failed" ]; then
    stop "$(grep -c . "$T/h.failed" | tr -d ' ') repair(s) failed and published nothing" "read the FAILED lines above, and the output written into each finding's issue"
  fi
  log_end || :
}

# ── a person's disposition ───────────────────────────────────────────────────
cmd_dispose() { # <accepted|superseded> <key> <--reason|--by> <text>
  _dn="$1"; _k="${2:-}"; _flag="${3:-}"; _txt="${4:-}"
  if [ "$_dn" = accepted ]; then _cmd=accept; _want=--reason; else _cmd=supersede; _want=--by; fi
  [ -n "$_k" ] && [ "$_flag" = "$_want" ] && [ -n "$_txt" ] || usage "usage: findings.sh $_cmd <key> $_want \"<text>\""
  [ -z "${CLAUDECODE:-}" ] \
    || stop "a disposition is a person's, and this is an agent session (CLAUDECODE is set)" "sh $HERE/findings.sh $_cmd $_k $_want \"...\"   # in your own terminal"
  { [ -t 0 ] && [ -t 1 ]; } \
    || stop "a disposition is a person's, and there is no terminal on stdin and stdout" "sh $HERE/findings.sh $_cmd $_k $_want \"...\"   # in your own terminal"
  REPO="$(repo)"; [ -n "$REPO" ] || stop "no store: this checkout has no origin" "HARBOR_FINDINGS_REPO=<owner/name> sh $HERE/findings.sh report"
  read_store
  _k="$(canon_key "$_k")"
  _row="$(latest "$_k")"
  [ -n "$_row" ] && [ "$(printf '%s' "$_row" | cut -f2)" = open ] \
    || stop "no open finding for $_k at $REPO" "sh $HERE/findings.sh report"
  _num="$(printf '%s' "$_row" | cut -f1)"
  printf 'Mark #%s (%s) %s: "%s"\nType the key to confirm: ' "$_num" "$_k" "$_dn" "$_txt"
  IFS= read -r _typed || _typed=""
  [ "$_typed" = "$_k" ] || stop "the key typed back was '$_typed', not $_k — nothing changed" "sh $HERE/findings.sh $_cmd $_k $_want \"$_txt\""
  LABELS_OK=0; ensure_labels
  gh issue close "$_num" -R "$REPO" --reason "not planned" \
    --comment "$_dn by a person at a terminal (findings.sh): $_txt" >/dev/null \
    && gh issue edit "$_num" -R "$REPO" --add-label "finding:$_dn" >/dev/null \
    || stop "could not mark #$_num $_dn" "gh issue view $_num -R $REPO"
  log_ok "#$_num ($_k) is $_dn. It stays closed while its digest holds; a changed subject set files it again."
  log_end || :
}

case "${1:-}" in
  reconcile) shift; cmd_reconcile "$@" ;;
  heal)      shift; cmd_heal "$@" ;;
  report)    shift; [ $# -eq 0 ] || usage "report takes no arguments"; cmd_report ;;
  accept)    shift; cmd_dispose accepted "$@" ;;
  supersede) shift; cmd_dispose superseded "$@" ;;
  lanes)     [ -f "$CONTRACT" ] || stop "no contract at $CONTRACT" "git -C $ROOT checkout origin/main -- CONTRACTS/finding.md"
             printf 'lane\tkey\tsubject\trepair\n'; lanes; printf '(every other key is PROPOSE — CONTRACTS/finding.md § Lanes)\n' ;;
  digest)    shift; [ $# -gt 0 ] || usage "digest needs at least one subject"
             printf '%s\n' "$@" > "$T/d"; digest_of_file "$T/d" ;;
  '')        usage "no command — reconcile, heal, report, accept, supersede, lanes or digest" ;;
  *)         usage "unknown command: $1" ;;
esac
