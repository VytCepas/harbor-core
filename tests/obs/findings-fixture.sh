# tests/obs/findings-fixture.sh — what the findings suites share (harbor#590): a stub GitHub that keeps
# its issues in one JSON file and logs every call, a published checkout, and the census and receipt writers.
# Sourced after core.sh's t_init.
F="$T_ROOT/bin/lint-findings.sh"
TMP="$T_TMP/f"; mkdir -p "$TMP"
GH_STATE="$TMP/gh.json"; GH_LOG="$TMP/gh.log"; export GH_STATE GH_LOG
HARBOR_LINT_FINDINGS_REPO=o/r; export HARBOR_LINT_FINDINGS_REPO
# never the live box's ~/.claude/cache/checks. The suites write through RCD: lint C10 reads a HARBOR_*
# assignment only in the file that reads it, so one made here would read as inherited.
RCD="$TMP/receipts"; HARBOR_CHECK_RECEIPTS="$RCD"; export HARBOR_CHECK_RECEIPTS
unset CLAUDECODE 2>/dev/null || :   # a person's terminal is simulated below; the agent case sets it back

# The stub keeps issues and labels in one JSON file and logs every call, so "wrote nothing" is a fact.
cat > "$T_BIN/gh" <<'GHSTUB'
#!/bin/sh
S="$GH_STATE"; printf '%s\n' "$*" >> "$GH_LOG"
[ -f "$S" ] || printf '{"issues":[],"labels":[]}\n' > "$S"
now="${GH_NOW:-2026-10-01}T09:00:00Z"
a="$1 $2"; shift 2
case "$a" in
  "issue list")
    [ "${GH_FAIL:-}" != list ] || { echo "HTTP 502: bad gateway" >&2; exit 1; }
    # GH_LAG_HIDE=<n>: the list lags and omits issue n, as GitHub's did on 2026-10-02 (harbor#893)
    jq --argjson h "${GH_LAG_HIDE:-0}" '[.issues[] | select(any(.labels[]; .name == "finding")) | select(.number != $h)]' "$S" ;;
  "issue create")
    t=""; b=""; l="[]"
    while [ $# -gt 0 ]; do case "$1" in
      --title) t="$2"; shift ;; --body-file) b="$(cat "$2")"; shift ;;
      --label) l="$(printf '%s' "$l" | jq -c --arg x "$2" '. + [{name: $x}]')"; shift ;; esac; shift; done
    n="$(jq '.issues | length + 1' "$S")"
    jq --argjson n "$n" --arg t "$t" --arg b "$b" --argjson l "$l" --arg c "$now" \
      '.issues += [{number: $n, state: "OPEN", stateReason: "", labels: $l, createdAt: $c, title: $t, body: $b}]' \
      "$S" > "$S.new" && mv "$S.new" "$S"
    echo "https://github.com/o/r/issues/$n" ;;
  "issue edit")
    n="$1"; shift
    while [ $# -gt 0 ]; do case "$1" in
      --body-file) jq --argjson n "$n" --arg b "$(cat "$2")" '(.issues[] | select(.number == $n) | .body) = $b' "$S" > "$S.new" && mv "$S.new" "$S"; shift ;;
      --add-label) jq --argjson n "$n" --arg x "$2" '(.issues[] | select(.number == $n) | .labels) += [{name: $x}]' "$S" > "$S.new" && mv "$S.new" "$S"; shift ;;
    esac; shift; done ;;
  "issue close")
    n="$1"; shift; r=""
    while [ $# -gt 0 ]; do case "$1" in --reason) r="$2"; shift ;; esac; shift; done
    case "$r" in completed) r=COMPLETED ;; "not planned") r=NOT_PLANNED ;; esac
    jq --argjson n "$n" --arg r "$r" '(.issues[] | select(.number == $n)) |= (.state = "CLOSED" | .stateReason = $r)' "$S" > "$S.new" && mv "$S.new" "$S" ;;
  "issue comment")
    n="$1"; shift; b=""
    while [ $# -gt 0 ]; do case "$1" in --body-file) b="$(cat "$2")"; shift ;; esac; shift; done
    jq --argjson n "$n" --arg b "$b" '.comments = ((.comments // []) + [{issue: $n, body: $b}])' "$S" > "$S.new" && mv "$S.new" "$S" ;;
  "pr list")
    case " $* " in *" --limit "*) ;; *) echo "gh stub: pr list without --limit returns 30 at most" >&2; exit 1 ;; esac
    jq '[(.prs // [])[] | select(.state == "OPEN") | {number, headRefName: .head, isCrossRepository: (.fork // false), url: ("https://github.com/o/r/pull/" + (.number | tostring))}]' "$S" ;;
  "issue view")
    n="$1"; jq --argjson n "$n" '{comments: [(.comments // [])[] | select(.issue == $n) | {body}]}' "$S" ;;
  "pr create")
    [ "${GH_FAIL:-}" != prcreate ] || { echo "HTTP 502: bad gateway" >&2; exit 1; }
    h=""; d=false
    while [ $# -gt 0 ]; do case "$1" in --head) h="$2"; shift ;; --draft) d=true ;; --title|--base|--body-file|-R) shift ;; esac; shift; done
    n="$(jq '(.prs // []) | length + 101' "$S")"
    jq --argjson n "$n" --arg h "$h" --argjson d "$d" '.prs = ((.prs // []) + [{number: $n, head: $h, draft: $d, state: "OPEN"}])' "$S" > "$S.new" && mv "$S.new" "$S"
    echo "https://github.com/o/r/pull/$n" ;;
  "label list") jq -r '.labels[]' "$S" ;;
  "label create") jq --arg x "$1" '.labels += [$x]' "$S" > "$S.new" && mv "$S.new" "$S" ;;
  "api graphql")
    # by number, never lagging: every n<k> alias in the query, an issue or null
    q=""; while [ $# -gt 0 ]; do case "$1" in query=*) q="${1#query=}" ;; esac; shift; done
    printf '%s' "$q" | grep -o 'number: [0-9]*' | awk '{ print $2 }' > "$S.nums"
    jq --rawfile ns "$S.nums" '{data: {repository: ([$ns | split("\n")[] | select(. != "") | tonumber] as $want
      | [$want[] as $n | {key: ("n" + ($n | tostring)), value: ([.issues[] | select(.number == $n)
          | {number, state, stateReason, createdAt, body, labels: {nodes: [.labels[] | {name}]}}][0] // null)}] | from_entries)}}' "$S" ;;
  "api repos/"*)
    jq '[([.issues[].number] + [(.prs // [])[].number] | max // 0) | {number: .}]' "$S" | jq -r '.[0].number // 0' ;;
  *) echo "gh stub: unhandled $a $*" >&2; exit 1 ;;
esac
GHSTUB
chmod +x "$T_BIN/gh"

# A published checkout: HEAD is origin/main and the tree is clean. The contract is the real one.
PUB="$TMP/pub"; mkdir -p "$PUB/contracts"
cp "$T_ROOT/contracts/finding.md" "$PUB/contracts/"; mkdir -p "$PUB/docs/reference"; cp "$T_ROOT/docs/reference/checks.md" "$PUB/docs/reference/"
git -C "$PUB" init -q; git -C "$PUB" -c user.email=t@t -c user.name=t add -A
git -C "$PUB" -c user.email=t@t -c user.name=t commit -qm fixture; git -C "$PUB" update-ref refs/remotes/origin/main HEAD

# records <dir> <ran ids> -- <ID:subject>… — a captured lint run, as bin/lint-conventions.sh writes one
records() {
  _rd="$1"; shift; mkdir -p "$_rd"; : > "$_rd/records.tsv"; : > "$_rd/lint.log"
  while [ $# -gt 0 ] && [ "$1" != -- ]; do printf 'R\t%s\n' "$1" >> "$_rd/records.tsv"; shift; done
  [ $# -eq 0 ] || shift
  for _p in "$@"; do
    printf 'A\t%s\t%s\n' "${_p%%:*}" "${_p#*:}" >> "$_rd/records.tsv"
    printf '  ADVISORY [%s] %s is 400 lines of code\n' "${_p%%:*}" "${_p#*:}" >> "$_rd/lint.log"
  done
}
rec() { HARBOR_SCOPE_ROOT="$PUB" HARBOR_LINT_FINDINGS_NOW="${NOW:-2026-10-01}" GH_NOW="${NOW:-2026-10-01}" sh "$F" reconcile --from "$@" 2>&1; }
open_n()   { jq '[.issues[] | select(.state == "OPEN")] | length' "$GH_STATE"; }
issue_of() { jq -r --arg k "$1" '[.issues[] | select(.body | contains("key=" + $k + " "))] | max_by(.number) | "\(.number) \(.state) \(.stateReason) \([.labels[].name] | join(","))"' "$GH_STATE"; }
writes()   { grep -cE '^(issue (create|edit|close)|label create)' "$GH_LOG" | tr -d ' '; }
# rcpt <id> <status> <YYYY-MM-DD> <subject>... — a receipt as a check would have left it
rcpt() {
  _ci="$1"; _cs="$2"; _cd="$3"; shift 3; mkdir -p "$RCD"
  jq -n --arg i "$_ci" --arg s "$_cs" --arg d "${_cd}T09:00:00Z" '{id: $i, ran_at: $d, status: $s, subjects: $ARGS.positional}' --args "$@" > "$RCD/$_ci.json"
}
: > "$GH_LOG"
