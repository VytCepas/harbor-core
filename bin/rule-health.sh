#!/usr/bin/env sh
# rule-health.sh (harbor#577) — which lint rules are not earning their keep, on evidence; it proposes, never edits.
#   sh bin/rule-health.sh          run the lint suites with a red log, time every rule, read the ledger, write a receipt
#   sh bin/rule-health.sh --help   this text
#   sh bin/rule-health.sh --promotion   which warn rules may go to block, and when (harbor#968, D-64): reads, never writes
#   exit 0 = every rule earns its keep · 1 = candidates, named · 2 = usage · 3 = stood down, nothing judged
#   (D-29: 3 is unchecked; before D-49 it exited 2 for stood down. No script reads its exit, so no reader window.)
#   receipt: ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache/checks/rule-health.json, which the findings
#   reconcile files as check/rule-health in the PROPOSE lane (CONTRACTS/finding.md)
#
# THE OPERATOR'S DECISIONS (harbor#577, 2026-10-02), and what each one costs here:
# - A rule must be red-proved. That is DERIVED, never read off the test text: the lint suites run
#   with LINT_REDLOG set, the linter appends every rule id that goes red, and since the suites
#   pass, a rule in the log was watched fail. A static read of the suites missed red arms reached
#   through helpers (t2(), _c8(), OUT_CM1=…) and would have flagged about 17 healthy rules.
# - A rule is a candidate when it is unproven, or when it costs over 5 s a run, is not a declared
#   ratchet (its title says "ratchet"), and has no ledger fire in 8 weeks. "Never fired" alone never
#   is: a ratchet at zero is supposed to be silent. Until the ledger holds 8 weeks of history the
#   silence half is reported as not judged, never as passed.
# - It proposes, never acts: nothing here edits a rule. Retiring one is a person's PR, with its
#   defect class recorded in DEAD-ENDS.md.
# - The budget is two numbers, the linter's cost in seconds and the unproven count. Lines and rule
#   count are not budgeted, because they penalise the documentation this repo asks for.
#
# A SUITE THAT FAILS STANDS THE RUN DOWN. A red log from a failing suite proves nothing, so the
# receipt says stood-down and no rule is judged. So does a finding store that cannot be read: a
# green there would close an open silent: finding as fixed (review #909).
#
# WHAT A RECEIPT MAY CLAIM (harbor#915). The reconcile files it against main, so only a clean checkout
# at origin/main writes one; any other tree prints its verdict and writes nothing. Silence is judged
# only while the reconcile is alive (its receipt findings-state.json says ok, at most 8 days old: a
# seen= cannot say so, because an accepted or fixed finding's stops moving), and a rule that fires in this run's own
# `--only` pass has fired, whatever an accepted finding's frozen seen= says. A `--only` that exits
# above 1 crashed: it is filed as crashed:<ID>, never timed as cheap.
#
#   HARBOR_ROOT         the checkout to judge (default: the one this script is in)
#   HARBOR_RH_LINT      the linter (default: $HARBOR_ROOT/bin/lint-conventions.sh) — for the suite
#   HARBOR_RH_SUITES    the suites, space-separated (default: tests/checks/lint-test.sh and lint.*-test.sh)
#   HARBOR_RH_COST_S    the cost floor in whole seconds (default 5)
#   HARBOR_RH_NOW       today, YYYY-MM-DD (default: the date)
#   HARBOR_FINDINGS_REPO  owner/name of the finding store (default: this checkout's origin)
set -eu
PROMOTION=no
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; exit 0 ;;
  --promotion) PROMOTION=yes; shift ;;
esac
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init rule-health
# It takes no argument but --promotion: one it does not know is a usage error (exit 2, D-29), never a three-minute run of the wrong question.
# Not a run (CONTRACTS/logging.md): the words go to stderr and there is no summary line.
[ $# -eq 0 ] || { LOG_FD=2; log_fail "unknown argument: $1"; log_fix "sh $0 --help"; exit 2; }
ROOT="${HARBOR_ROOT:-$(CDPATH='' cd -- "$HERE/.." && pwd)}"
LINT="${HARBOR_RH_LINT:-$ROOT/bin/lint-conventions.sh}"
CTL="$ROOT/standards/naming/controls.tsv"
COST_S="${HARBOR_RH_COST_S:-5}"; case "$COST_S" in ''|*[!0-9]*) COST_S=5 ;; esac
TODAY="${HARBOR_RH_NOW:-$(date -u +%Y-%m-%d)}"
RD="$(receipt_dir)"
SILENT_DAYS=56
# D-64 (standards/naming.md section 10.3): a warn rule may go to block once it has gone red and run four
# weeks with no finding accepted as false. --promotion reads this number; nothing else in this file does.
PROMOTE_DAYS=28
T="$(mktemp -d "${TMPDIR:-/tmp}/rule-health.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM HUP

# A branch's unproven: subjects would otherwise be filed as main's (review #915).
_head="$(git -C "$ROOT" rev-parse -q --verify HEAD 2>/dev/null)" || _head=""
_main="$(git -C "$ROOT" rev-parse -q --verify refs/remotes/origin/main 2>/dev/null)" || _main=""
_dirty="$(git -C "$ROOT" status --porcelain 2>/dev/null)" || _dirty="unreadable"
if [ -z "$_head" ]; then UNPUBLISHED="$ROOT is not a git checkout"
elif [ "$_head" != "$_main" ]; then UNPUBLISHED="$ROOT is at $(printf '%.7s' "$_head"), not origin/main"
elif [ -n "$_dirty" ]; then UNPUBLISHED="$ROOT has uncommitted changes"
else UNPUBLISHED=""; fi

receipt() { # <status> [subject...] — weekly, so it counts as a run for 8 days
  [ "$PROMOTION" != yes ] || return 0   # --promotion judges and writes no receipt
  if [ -n "$UNPUBLISHED" ]; then
    log_note "no receipt written: $UNPUBLISHED, and the reconcile files receipts against main"; return 0
  fi
  LOG_RECEIPT_FRESH_DAYS=8 log_receipt "$RD" rule-health "$@" || log_warn "no receipt written to $RD"
}
stand_down() { # <why> <fix>
  receipt stood-down
  log_fail "$1 — no rule was judged"; log_fix "$2"
  log_end || :; exit 3   # D-29 unchecked
}
now_s() { perl -MTime::HiRes=time -e 'printf "%.2f", time' 2>/dev/null || date +%s; }

[ -f "$LINT" ] || stand_down "no linter at $LINT" "HARBOR_RH_LINT=<linter> sh $0"
HARBOR_ROOT="$ROOT" sh "$LINT" --list 2>/dev/null | sed 's/^  //' > "$T/titles"
awk '{ print $1 }' "$T/titles" | sort -u > "$T/rules"
[ -s "$T/rules" ] || stand_down "the linter listed no rules" "sh $LINT --list"
awk 'tolower($0) ~ /ratchet/ { print $1 }' "$T/titles" | sort -u > "$T/ratchets"
_nr="$(grep -c . "$T/rules" | tr -d ' ')"

# --promotion (harbor#968, D-64): which warn rules may go to block, and when. Every input is read here and
# none is trusted. The red proof is what the passing suites watched go red in THIS run. The clock is the
# latest of three dates: the row's landing (the rules.tsv -> controls.tsv rename does not reset it), the
# first commit of its red-proof suite (a bound: the suite's history, not a per-rule measurement), and the
# last accepted-false closing. An unreadable finding store stands down (review #909): a read that failed
# must never read as zero accepted, and neither may a count nobody took: open and acc print "-" when the
# rule's findings could not be counted, and a rule with no finding key is "not judged", never "ready".
# It proposes; a block is a person's PR. Its stdout is the report.
#
# THE FINDING KEY. The store holds one issue per conventions rule, keyed lint/<rule>. A rule whose own engine
# is bin/lint-conventions.sh is filed under its own id. A name.*, module.* or doc.refs-* rule is not: the
# conventions run relays its engine's findings under ONE rule (lint-conventions.sh rule_N4,
# rule_module_graph_conform, rule_doc_refs_conform, rule_lint_comment_conform), so the store cannot say which of them an acceptance was
# against, and an acceptance on the relay key restarts every rule behind it. relays() pairs each engine
# with that key; the suite pins it to controls.tsv, so a new engine fails there rather than counting zero.
relays() { printf '%s\t%s\n' bin/lint-name.sh standard.names-conform bin/lint-module.sh module.graph-conform bin/doc-refs.sh doc.refs-conform bin/standard-shape.sh standard.shape-conform bin/lint-comment.sh lint.comment-conform; }
engine_findings() { # <engine> — its own findings, one rule id per finding, appended to $T/p.cnt; 1 when it could not look
  [ -f "$ROOT/$1" ] || return 1
  _erc=0
  case "$1" in
    bin/lint-name.sh|bin/doc-refs.sh) sh "$ROOT/$1" --root "$ROOT" --format findings > "$T/p.eng" 2> /dev/null || _erc=$? ;;
    bin/lint-module.sh)
      [ -f "$ROOT/bin/graph-gen.sh" ] || return 1
      sh "$ROOT/bin/graph-gen.sh" --root "$ROOT" --out "$T/p.graph" > /dev/null 2>&1 || return 1
      sh "$ROOT/$1" --root "$ROOT" --graph "$T/p.graph" --format findings > "$T/p.eng" 2> /dev/null || _erc=$? ;;
    bin/standard-shape.sh)   # judged on a fresh graph, as lint-conventions' standard.shape-conform relay does
      [ -f "$ROOT/bin/graph-gen.sh" ] || return 1
      if [ ! -f "$T/p.graph" ]; then sh "$ROOT/bin/graph-gen.sh" --root "$ROOT" --out "$T/p.graph" > /dev/null 2>&1 || return 1; fi
      sh "$ROOT/$1" --root "$ROOT" --graph "$T/p.graph" --format findings > "$T/p.eng" 2> /dev/null || _erc=$? ;;
    *) return 1 ;;
  esac
  [ "$_erc" -le 1 ] || return 1   # above 1 the engine judged nothing (D-49)
  awk -F'\t' '$1 == "A" || $1 == "V" { print $2 }' "$T/p.eng" >> "$T/p.cnt"
}
promotion() {
  [ -f "$CTL" ] || stand_down "no control register at ${CTL#"$ROOT"/}" "ls $CTL"
  awk -F'\t' '$1 !~ /^#/ && $1 != "id" && $2 == "warn" { print $1 "\t" $3 "\t" $4 "\t" $11 }' "$CTL" > "$T/p.warn"
  [ -s "$T/p.warn" ] || { log_note "no warn rule in ${CTL#"$ROOT"/}, so none is up for block"; return 0; }
  git -C "$ROOT" log --reverse -p --format='@%cs' -- standards/naming/controls.tsv standards/naming/rules.tsv 2>/dev/null \
    | awk -F'\t' '/^@[0-9][0-9][0-9][0-9]-/ { d = substr($0, 2); next } /^[-+][^-+]/ { id = substr($1, 2); if (!(id in L)) { L[id] = d; print id "\t" d } }' > "$T/p.landed"
  : > "$T/p.suite"
  cut -f4 "$T/p.warn" | sort -u | while IFS= read -r _p; do
    [ -n "$_p" ] && [ "$_p" != - ] || continue
    _d="$(git -C "$ROOT" log --follow --diff-filter=A --format=%cs -- "$_p" 2>/dev/null | tail -n 1)" || _d=""
    printf '%s\t%s\n' "$_p" "$_d" >> "$T/p.suite"
  done
  # open findings per rule. A conventions rule is counted by the conventions run, and only if the run says it ran
  # (an R record); every other rule by its own engine, which reports its own rule ids. An engine that could not
  # look leaves its rules uncounted.
  : > "$T/p.cnt"; : > "$T/p.lc"; : > "$T/p.engok"
  awk -F'\t' '$2 == "lint" && $3 != "bin/lint-conventions.sh" { print $3 }' "$T/p.warn" | sort -u | while IFS= read -r _e; do
    if engine_findings "$_e"; then printf '%s\n' "$_e" >> "$T/p.engok"; else log_note "$_e could not be run, so its rules' open findings are not counted"; fi
  done
  HARBOR_FINDINGS_OUT="$T/p.lc" HARBOR_ROOT="$ROOT" sh "$LINT" > /dev/null 2>&1 || :
  awk -F'\t' '$1 == "R" { print $2 }' "$T/p.lc" | sort -u > "$T/p.ran"
  awk -F'\t' '$1 == "A" || $1 == "V" { print $2 }' "$T/p.lc" >> "$T/p.cnt"
  awk '{ c[$1]++ } END { for (k in c) print k "\t" c[k] }' "$T/p.cnt" > "$T/p.cntn"
  # accepted-as-false: the finding store's issues labelled finding:accepted, keyed lint/<key>
  _repo="${HARBOR_FINDINGS_REPO:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')}"
  [ -n "$_repo" ] || stand_down "no finding store to read, so accepted-as-false cannot be counted" "HARBOR_FINDINGS_REPO=<owner/name> sh $0 --promotion"
  gh issue list -R "$_repo" --label finding:accepted --state all --limit 1000 --json body,createdAt,closedAt > "$T/p.acc.json" 2>"$T/gh.err" \
    || stand_down "the finding store $_repo could not be read ($(head -1 "$T/gh.err")), so accepted-as-false cannot be counted" "gh auth status"
  jq -e 'type == "array" and all(.[]; ((.closedAt // .createdAt) // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))' "$T/p.acc.json" > /dev/null 2>&1 \
    || stand_down "the finding store $_repo holds an accepted finding whose date is not a date" "gh issue list -R $_repo --label finding:accepted --state all --json body,closedAt"
  jq -r '.[] | ((.body // "") | capture("key=lint/(?<k>[^ ]+) digest=")?) as $m | [$m.k, ((.closedAt // .createdAt) // "")[0:10]] | @tsv' "$T/p.acc.json" > "$T/p.acc" \
    || stand_down "the finding store $_repo could not be parsed for accepted findings" "gh issue list -R $_repo --label finding:accepted --state all --json body,closedAt"
  # a marker that still spells a deprecated letter id joins under its successor (CONTRACTS/finding.md)
  HARBOR_ROOT="$ROOT" sh "$LINT" --ids 2>/dev/null | awk -F'\t' 'NF == 2 && NR > 1 && $2 != "-" { print $2 "\t" $1 }' > "$T/succ" || :
  awk -F'\t' -v S="$T/succ" 'BEGIN { while ((getline l < S) > 0) { split(l, p, "\t"); s[p[1]] = p[2] } }
       $1 != "" { k = $1; if (k in s) k = s[k]; n[k]++; if ($2 > last[k]) last[k] = $2 }
       END { for (k in n) print k "\t" n[k] "\t" last[k] }' "$T/p.acc" > "$T/p.accn"
  relays > "$T/p.relay"
  # the join, then the verdict (dates in jq, which already reads this file's JSON)
  awk -F'\t' -v OFS='\t' -v L="$T/p.landed" -v S="$T/p.suite" -v R="$T/red" -v C="$T/p.cntn" -v A="$T/p.accn" -v W="$T/p.warn" \
      -v X="$T/p.relay" -v G="$T/rules" -v N="$T/p.ran" -v E="$T/p.engok" '
    BEGIN { while ((getline l < X) > 0) { split(l, p, "\t"); RK[p[1]] = p[2] } }
    FILENAME == L { LD[$1] = $2; next }
    FILENAME == S { SD[$1] = $2; next }
    FILENAME == R { RD[$1] = 1; next }
    FILENAME == C { CN[$1] = $2; next }
    FILENAME == A { AN[$1] = $2; AL[$1] = $3; next }
    FILENAME == G { REG[$1] = 1; next }
    FILENAME == N { RAN[$1] = 1; next }
    FILENAME == E { EOK[$1] = 1; next }
    FILENAME == W { id = $1; ty = $2; eng = $3; sp = $4
      conv = (eng == "bin/lint-conventions.sh")
      key = ""
      if (ty == "lint") { if (conv) key = id; else if ((eng in RK) && (RK[eng] in REG)) key = RK[eng] }
      op = "-"
      if (ty == "lint") { if (conv) { if (id in RAN) op = CN[id] + 0 } else if (eng in EOK) op = CN[id] + 0 }
      ac = "-"; la = ""
      if (key != "") { ac = (key in AN) ? AN[key] : 0; la = (key in AL) ? AL[key] : "" }
      print id, ty, eng, (sp in SD ? SD[sp] : ""), (id in LD ? LD[id] : ""), (id in RD ? "yes" : "no"), op, ac, la, key, (!conv && key != "" ? key : "") }' \
    "$T/p.landed" "$T/p.suite" "$T/red" "$T/p.cntn" "$T/p.accn" "$T/rules" "$T/p.ran" "$T/p.engok" "$T/p.warn" > "$T/p.joined"
  jq -rR --arg today "$TODAY" --argjson days "$PROMOTE_DAYS" '
    def day: if . == "" then null else (. + "T00:00:00Z" | fromdateiso8601 | . / 86400 | floor) end;
    def dstr: (. * 86400 | strftime("%Y-%m-%d"));
    split("\t") as $f
    | $f[0] as $id | $f[1] as $type | $f[2] as $eng | $f[3] as $first | $f[4] as $landed | $f[5] as $red
    | $f[6] as $open | $f[7] as $acc | $f[8] as $lastacc | $f[9] as $key | $f[10] as $via
    | ($today | day) as $now
    | (if $landed == "" then "not judged: no commit adds this row"
       elif $type != "lint" then
         (($landed | day) + $days) as $r
         | "not judged: no finding counter for a \($type) rule; row age alone: " + (if $r > $now then "not before \($r | dstr)" else "\($days) days elapsed" end)
       elif $key == "" then "not judged: no finding key for engine \($eng), so accepted-as-false cannot be counted"
       elif $first == "" then "not judged: its red-proof suite has no history"
       elif $red != "yes" then "not ready: no passing lint suite watched it red"
       else ([$first, $landed, $lastacc] | map(day) | map(select(. != null)) | max + $days) as $ready
         | if $ready > $now then "not before \($ready | dstr)"
           elif $open == "-" then "ready (open findings not counted)"
           elif ($open | tonumber) > 0 then "ready (\($open) open: a block fails the run until they clear)"
           else "ready" end
       end) as $verdict
    | [$id, $type, (if $type == "lint" and $first != "" then $first else "-" end), (if $landed == "" then "-" else $landed end),
       (if $landed == "" then "-" else (($now - ($landed | day)) | tostring) end),
       $open, ($acc + (if $via != "" then "*" else "" end)), $verdict, $via] | @tsv' "$T/p.joined" > "$T/p.out" \
    || stand_down "the joined promotion table could not be judged" "sh $0 --promotion"
  log_note "promotion, as of $TODAY: a warn rule is ready for block after $PROMOTE_DAYS days red with no accepted-as-false (standards/naming.md 10.3)"
  log_note "rule | first-red = its red-proof suite's first commit (a bound) | landed = its row | age = days since landed | open = findings now (- = not counted) | acc = accepted-as-false (- = no key)"
  LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k1,1 "$T/p.out" | awk -F'\t' '
    BEGIN { printf "%-38s %-10s %-10s %4s %4s %4s  %s\n", "rule", "first-red", "landed", "age", "open", "acc", "verdict" }
    $2 != "lint" { o[++no] = $0; next }
    { printf "%-38s %-10s %-10s %4s %4s %4s  %s\n", $1, $3, $4, $5, $6, $7, $8
      if ($9 != "") via[$9] = 1
      if ($8 ~ /^ready/) ready++
      if ($8 ~ /^not before /) { d = substr($8, 12); if (earliest == "" || d < earliest) earliest = d } }
    END {
      printf "%d lint rule(s) ready now; earliest not-before: %s\n", ready + 0, (earliest == "" ? "none" : earliest)
      if (length(via) > 0) { s = ""; for (k in via) s = s " lint/" k; printf "* acc is counted on the key the rule is relayed under (%s): the store cannot say which rule a finding was accepted against, so one acceptance restarts every rule behind that key\n", substr(s, 2) }
      if (no > 0) {
        printf "\nnot judged: %d warn rule(s) that are not lint rules have no finding counter here; row age alone is shown\n", no
        printf "%-38s %-10s %-10s %4s  %s\n", "rule", "type", "landed", "age", "row age alone"
        for (i = 1; i <= no; i++) { split(o[i], c, "\t"); v = c[8]; sub(/^not judged: no finding counter for a [a-z]+ rule; row age alone: /, "", v)
          printf "%-38s %-10s %-10s %4s  %s\n", c[1], c[2], c[4], c[5], v }
      }
    }'
}

# 1 · which rules the passing lint suites watched go red
if [ -n "${HARBOR_RH_SUITES:-}" ]; then
  # shellcheck disable=SC2086 # a space-separated list, split on purpose
  printf '%s\n' $HARBOR_RH_SUITES > "$T/suites"
else
  find "$ROOT/tests/checks" -maxdepth 1 -type f \( -name 'lint-test.sh' -o -name 'lint.*-test.sh' \) | sort > "$T/suites"
fi
if [ "$PROMOTION" = yes ] && [ -f "$CTL" ]; then
  # a warn rule's own red_proof suite joins the list, so a suite outside the glob (lint-module's, doc-refs') counts
  awk -F'\t' -v R="$ROOT" '$1 !~ /^#/ && $2 == "warn" && $11 ~ /^tests\// { print R "/" $11 }' "$CTL" >> "$T/suites"
  sort -u "$T/suites" | while IFS= read -r _p; do [ -f "$_p" ] && printf '%s\n' "$_p" || :; done > "$T/suites.n"
  mv "$T/suites.n" "$T/suites"
fi
[ -s "$T/suites" ] || stand_down "no lint suites to run" "ls $ROOT/tests/checks/lint*-test.sh"
: > "$T/red"
while IFS= read -r _s; do
  _rc=0; LINT_REDLOG="$T/red" sh "$_s" > "$T/suite.out" 2>&1 || _rc=$?
  [ "$_rc" -eq 0 ] || stand_down "the lint suite ${_s#"$ROOT"/} exited $_rc, so its red log proves nothing" "sh $_s"
done < "$T/suites"
sort -u "$T/red" -o "$T/red"
comm -23 "$T/rules" "$T/red" > "$T/unproven"
if [ "$PROMOTION" = yes ]; then promotion; log_end || :; exit 0; fi

# 2 · what each rule costs alone, and whether it fires today
# The linter exits 0 clean and 1 on a finding; above 1 the rule crashed, and a crash is not cheap.
: > "$T/costs"; : > "$T/now"; : > "$T/crashed"
while IFS= read -r _id; do
  _a="$(now_s)"; _rc=0
  LINT_REDLOG="$T/now" HARBOR_ROOT="$ROOT" sh "$LINT" --only "$_id" > /dev/null 2>&1 || _rc=$?
  _b="$(now_s)"
  [ "$_rc" -le 1 ] || printf '%s\n' "$_id" >> "$T/crashed"
  printf '%s %s\n' "$_id" "$(awk -v a="$_a" -v b="$_b" 'BEGIN { printf "%.1f", b - a }')" >> "$T/costs"
done < "$T/rules"
sort -u "$T/now" -o "$T/now"
_total="$(awk '{ s += $2 } END { printf "%.0f", s }' "$T/costs")"
awk -v f="$COST_S" '$2 > f { print $1 }' "$T/costs" | sort -u > "$T/costly"

# 3 · the ledger's fire history, and whether it is long enough to judge silence
_repo="${HARBOR_FINDINGS_REPO:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##')}"
# An unread store STANDS DOWN, never "not judged": a green receipt would close an open silent:
# finding as fixed. A young ledger is green honestly — no silent: can be filed before 8 weeks of it.
: > "$T/silent"; _judged=no
[ -n "$_repo" ] || stand_down "no finding store to read, so silence cannot be judged" "HARBOR_FINDINGS_REPO=<owner/name> sh $0"
gh issue list -R "$_repo" --label finding --state all --limit 1000 --json createdAt,body > "$T/store.json" 2>"$T/gh.err" \
  || stand_down "the finding store $_repo could not be read ($(head -1 "$T/gh.err")), so silence cannot be judged" "gh auth status"
jq -e 'type == "array"' "$T/store.json" > /dev/null 2>&1 \
  || stand_down "the finding store $_repo answered with something that is not a list of issues" "gh issue list -R $_repo --label finding --limit 1"
jq -e 'all(.[]; (.createdAt | type) == "string" and (.createdAt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")))' "$T/store.json" > /dev/null 2>&1 \
  || stand_down "the finding store $_repo holds an issue whose createdAt is not a date, so the ledger's age cannot be read" "gh issue list -R $_repo --label finding --state all --json number,createdAt"
days() { # <from YYYY-MM-DD> → whole days to TODAY, or nothing when either date does not parse
  jq -rn --arg a "$1" --arg b "$TODAY" '((($b|strptime("%Y-%m-%d")|mktime) - ($a|strptime("%Y-%m-%d")|mktime)) / 86400) | floor' 2>/dev/null || :
}
_oldest="$(jq -r '[.[].createdAt[0:10]] | min // empty' "$T/store.json")"
RS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache/findings-state.json"   # the reconcile's receipt (findings-run.sh)
_rstat="$(jq -r '.status // empty' "$RS" 2>/dev/null)" || _rstat=""
_rran="$(jq -r '.ran_at // empty | .[0:10]' "$RS" 2>/dev/null)" || _rran=""
_span="$(days "${_oldest:-$TODAY}")"
case "$_span" in ''|*[!0-9-]*) stand_down "the ledger's age could not be computed from $_oldest to $TODAY" "HARBOR_RH_NOW=YYYY-MM-DD sh $0" ;; esac
_live=""; [ -z "$_rran" ] || _live="$(days "$_rran")"
if [ "$_span" -lt "$SILENT_DAYS" ]; then
  _why="the ledger is $_span day(s) old, under the $SILENT_DAYS it needs"
elif [ "$_rstat" != ok ] || [ -z "$_live" ]; then
  _why="the reconcile's receipt $RS does not say ok (status: ${_rstat:-none}), so the ledger may have stopped moving"
elif [ "$_live" -gt 8 ]; then
  # a dead reconcile freezes every seen=, and every costly rule would then read as silent
  _why="the reconcile last ran $_live day(s) ago, so the ledger has stopped moving"
else
  _judged=yes
  # the lint keys seen firing within the window, and every rule that fired in this run
  jq -r --arg b "$TODAY" --argjson w "$SILENT_DAYS" '.[] | (.body | capture("key=lint/(?<k>[^ ]+) digest=[^ ]+ seen=(?<s>[0-9]{4}-[0-9]{2}-[0-9]{2}) ")?) // empty
      | select((($b|strptime("%Y-%m-%d")|mktime) - (.s|strptime("%Y-%m-%d")|mktime)) / 86400 <= $w) | .k' "$T/store.json" > "$T/fired" 2>/dev/null \
    || stand_down "a seen= date in the finding store $_repo does not parse" "gh issue list -R $_repo --label finding --state all --json number,body"
  # A finding filed under a deprecated letter (lint/X5) fired as its successor (D-19, harbor#957).
  HARBOR_ROOT="$ROOT" sh "$LINT" --ids 2>/dev/null | awk -F'\t' 'NF == 2 && NR > 1 && $2 != "-" { print $2 "\t" $1 }' > "$T/succ" || :
  awk -F'\t' -v S="$T/succ" 'BEGIN { while ((getline l < S) > 0) { split(l, p, "\t"); s[p[1]] = p[2] } }
       { print (($1 in s) ? s[$1] : $1) }' "$T/fired" > "$T/fired.c" && mv "$T/fired.c" "$T/fired"
  sort -u "$T/now" "$T/crashed" "$T/fired" -o "$T/fired"
  comm -23 "$T/costly" "$T/ratchets" | comm -23 - "$T/fired" > "$T/silent"
fi

# 4 · the receipt, and the two budget numbers
_nu="$(grep -c . "$T/unproven" | tr -d ' ')"; _ns="$(grep -c . "$T/silent" | tr -d ' ')"
{ sed 's/^/unproven:/' "$T/unproven"; sed 's/^/silent:/' "$T/silent"; sed 's/^/crashed:/' "$T/crashed"; } > "$T/subjects"
_oifs=$IFS; IFS='
'; set -f
# shellcheck disable=SC2046 # one subject per line, split on the newline IFS above
if [ -s "$T/subjects" ]; then receipt red $(cat "$T/subjects"); else receipt green; fi
set +f; IFS=$_oifs
log_note "budget: the linter costs ${_total} s across $_nr rules run alone; $_nu of $_nr have no red proof"
[ ! -s "$T/costly" ] || log_note "over ${COST_S} s alone: $(tr '\n' ' ' < "$T/costly" | sed 's/ $//')"
[ ! -s "$T/unproven" ] || log_warn "unproven (never went red in a passing lint suite): $(tr '\n' ' ' < "$T/unproven" | sed 's/ $//')"
if [ "$_judged" = yes ]; then
  [ ! -s "$T/silent" ] || log_warn "costly and silent for $SILENT_DAYS days, not a ratchet: $(tr '\n' ' ' < "$T/silent" | sed 's/ $//')"
else
  log_note "silence not judged: $_why"
fi
[ ! -s "$T/crashed" ] || log_warn "crashed when run alone (--only exited above 1): $(tr '\n' ' ' < "$T/crashed" | sed 's/ $//')"
[ -n "$UNPUBLISHED" ] || log_note "receipt: $RD/rule-health.json"
log_end || :
[ ! -s "$T/subjects" ] || exit 1
exit 0
