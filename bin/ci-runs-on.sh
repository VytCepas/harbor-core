#!/usr/bin/env sh
# ci-runs-on.sh (harbor#1060) — make a checkout's workflows read vars.CI_RUNS_ON, so the repo can move to local CI.
#
#   sh ci-runs-on.sh <checkout>            dry run: the skip/rewrite report and a unified diff, writes nothing
#   sh ci-runs-on.sh <checkout> --apply    writes the files; never commits, never pushes, prints the commands
#
# Rewrites a job's single-string hosted label (ubuntu-latest, ubuntu-24.04, ubuntu-22.04) to
#   ${{ vars.CI_RUNS_ON || '<the original label>' }}   so an unset variable keeps the job on hosted minutes.
# SKIPPED, each with its reason: an expression, an array / matrix / group form, macos-* / windows-* or any other
# label, no runs-on (a reusable-workflow call), and any job that deploys or holds credentials (secrets other than
# GITHUB_TOKEN, environment:, id-token:, a cloud auth action, a deploy tool or a deploy/release/publish job). A
# self-hosted runner executes PR code on this Mac, so those stay hosted until the operator decides otherwise.
# Idempotent: a rewritten job is an expression, so a second --apply finds nothing. POSIX sh and awk, no yq.
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
log_init ci-runs-on

case "${1:-}" in -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;; esac
DIR=""; APPLY=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    -*) log_fail "unknown option $a"; log_fix "sh $0 --help"; exit 2 ;;
    *) [ -z "$DIR" ] || { log_fail "one checkout at a time, got a second: $a"; log_fix "sh $0 --help"; exit 2; }; DIR="$a" ;;
  esac
done
[ -n "$DIR" ] || { log_fail "want a checkout directory"; log_fix "sh $0 --help"; exit 2; }
WF="$DIR/.github/workflows"
[ -d "$WF" ] || { log_fail "no workflows directory in $DIR"; log_fix "sh $0 <a local checkout of a repo>"; exit 2; }

T="$(mktemp -d "${TMPDIR:-/tmp}/ci-runs-on.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM HUP
: > "$T/report"; : > "$T/diff"
# jobs: its children sit at one indent (J); a job's runs-on sits at its first child's indent. Every job is read whole before any is judged.
AWK='
function indent(s) { match(s, /^ */); return RLENGTH }
function judge(a, b,   i, ln, body, v, c, id) {
  id = jid[a]; ro = 0; body = ""; K = -1
  for (i = a + 1; i <= b; i++) {
    ln = L[i]
    if (ln ~ /^[ ]*(#.*)?$/) continue
    if (K < 0) K = indent(ln)
    if (indent(ln) == K && ln ~ /^ *runs-on:/) ro = i
    body = body "\n" ln
  }
  if (!ro) { rep("skip", id, "no runs-on (a reusable-workflow call)"); return }
  v = L[ro]; sub(/^ *runs-on:[ ]*/, "", v); sub(/[ ]+#.*$/, "", v); sub(/[ ]+$/, "", v)
  c = v; gsub(/^["\047]|["\047]$/, "", c)
  if (v == "") { rep("skip", id, "array, matrix or group form"); return }
  if (v ~ /^\[/ || v ~ /^\{/) { rep("skip", id, "array or group form"); return }
  if (c ~ /vars\.CI_RUNS_ON/) { rep("skip", id, "already adopted"); return }
  if (c ~ /\$\{\{/) { rep("skip", id, "already an expression"); return }
  if (c ~ /^macos-/) { rep("skip", id, "macOS runner (" c ")"); return }
  if (c ~ /^windows-/) { rep("skip", id, "Windows runner (" c ")"); return }
  if (c !~ /^ubuntu-(latest|24\.04|22\.04)$/) { rep("skip", id, "label not a hosted ubuntu one (" c ")"); return }
  if (id ~ /(deploy|release|publish)/) { rep("skip", id, "job id says deploy/release/publish: stays hosted"); return }
  tmp = body; gsub(/secrets\.GITHUB_TOKEN/, "", tmp)
  if (tmp ~ /secrets\.[A-Za-z_]/ || tmp ~ /secrets: *inherit/) { rep("skip", id, "uses secrets beyond GITHUB_TOKEN: stays hosted"); return }
  if (body ~ /\n *environment:/) { rep("skip", id, "uses an environment: stays hosted"); return }
  if (body ~ /id-token:/) { rep("skip", id, "requests an OIDC token (id-token): stays hosted"); return }
  if (tolower(body) ~ /(google-github-actions|aws-actions|azure\/|hashicorp\/|cloudflare\/|firebase|gcloud|wrangler|flyctl|vercel|netlify|kubectl|helm upgrade|terraform apply|npm publish|docker push|twine upload|(^|[^a-z])deploy)/) {
    rep("skip", id, "deploys or uses cloud credentials: stays hosted"); return }
  newv = "${{ vars.CI_RUNS_ON || \047" c "\047 }}"
  cmt = L[ro]; if (match(cmt, /[ ]+#.*$/)) cmt = substr(cmt, RSTART); else cmt = ""
  L[ro] = substr(L[ro], 1, indent(L[ro])) "runs-on: " newv cmt
  rep("rewrite", id, c)
}
function rep(kind, id, why) { print kind "\t" FILE "\t" id "\t" why >> REPORT }
{ L[NR] = $0 }
END {
  n = NR; J = -1; njob = 0
  for (i = 1; i <= n; i++) {
    if (L[i] ~ /^jobs:[ ]*(#.*)?$/) { inj = 1; continue }
    if (inj && L[i] ~ /^[^ #]/) { inj = 0 }
    if (!inj || L[i] ~ /^[ ]*(#.*)?$/) continue
    if (J < 0) J = indent(L[i])
    if (indent(L[i]) == J && L[i] ~ /^ *[A-Za-z0-9_"\047-]+:/) {
      njob++; jstart[njob] = i; id = L[i]; sub(/^ */, "", id); sub(/:.*$/, "", id); gsub(/["\047]/, "", id); jid[i] = id
    }
  }
  for (k = 1; k <= njob; k++) {
    e = (k < njob) ? jstart[k + 1] - 1 : n
    judge(jstart[k], e)
  }
  for (i = 1; i <= n; i++) print L[i]
}'

nrw=0
for f in "$WF"/*.yml "$WF"/*.yaml; do
  [ -f "$f" ] || continue
  rel=".github/workflows/${f##*/}"
  awk -v FILE="$rel" -v REPORT="$T/report" "$AWK" "$f" > "$T/new"
  if ! cmp -s "$f" "$T/new"; then
    diff -u -L "a/$rel" -L "b/$rel" "$f" "$T/new" >> "$T/diff" || :
    nrw=$((nrw + 1))
    [ "$APPLY" = 1 ] && cat "$T/new" > "$f"
  fi
done

log_head "$DIR"
if [ ! -s "$T/report" ]; then log_note "no jobs found in any workflow"; fi
while IFS="$(printf '\t')" read -r kind file job why; do
  case "$kind" in
    rewrite) log_ok "rewrite $file :: $job  ($why -> \${{ vars.CI_RUNS_ON || '$why' }})" ;;
    skip) case "$why" in "already adopted") log_note "skip    $file :: $job  ($why)" ;; *) log_skip "$file :: $job  ($why)" ;; esac ;;
  esac
done < "$T/report"
nj="$(grep -c '^rewrite' "$T/report" || :)"

if [ "$nj" -eq 0 ]; then log_note "nothing to rewrite"; log_end; exit 0; fi
if [ "$APPLY" = 0 ]; then
  cat "$T/diff"
  log_note "dry run: $nj job(s) in $nrw file(s) would change"
  log_fix "sh $0 $DIR --apply"
  log_end; exit 0
fi
log_note "applied: $nj job(s) in $nrw file(s) rewritten; nothing committed, nothing pushed"
SLUG="$(git -C "$DIR" remote get-url origin 2>/dev/null | sed -e 's#^.*github\.com[:/]##' -e 's#\.git$##' || :)"
[ -n "$SLUG" ] || SLUG="<owner/repo>"
cat <<EOF
Next, by hand (this tool never commits or pushes):
  git -C $DIR switch -c ci/runs-on-adopt
  git -C $DIR add .github/workflows
  git -C $DIR commit -m 'ci: read vars.CI_RUNS_ON so the repo can move to local CI (harbor#1060)'
  git -C $DIR push -u origin ci/runs-on-adopt
  gh pr create -R $SLUG --head ci/runs-on-adopt --title 'ci: read vars.CI_RUNS_ON (harbor#1060)' --body 'Hosted label stays the fallback while CI_RUNS_ON is unset.'
EOF
log_end
