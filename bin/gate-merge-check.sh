#!/usr/bin/env sh
# gate-merge-check.sh — refuse to merge a PR that has no green verdict (CI-3, harbor#150)
#
#   sh gate-merge-check.sh <pr>              exit 0 = safe to merge, 1 = refused
#   sh gate-merge-check.sh --merge <pr>      check, then merge only if it passes
#   sh gate-merge-check.sh --merge <pr> --force
#                                       merge anyway; the override is written
#                                       into the merge commit, not just printed
#   sh gate-merge-check.sh --protection      is branch protection still there at all?
#   --required-only                     only the checks that BLOCK, not every check
#   --subject <text> --delete-branch --match-head-commit <sha>
#                                       passed through to `gh pr merge`
#   --squash | --rebase | --merge-commit
#                                       how to land it (default: a merge commit,
#                                       which is what this tool has always done —
#                                       harbor#267). The chosen one is printed.
#
#   HARBOR_SCOPE_REPO   owner/name (default: the checkout's remote, else this script's checkout). NOT a path
#   (bin/drift-renew-check.sh reads the same name as a path); a non-owner/name value is REFUSED, see repo().
#   HARBOR_GATE_BRANCH the protected branch (default: main)
#   HARBOR_GATE_REQUIRED_CHECKS  the local gate's declaration, rows repo<TAB>check name (default:
#   contracts/required-checks.tsv, then the private layer's via gate-required-generate.sh). Set, it is the only list read.
# Removed notes: docs/explanation/code-cases/bin-gate-merge-check.md
#
# Backstop for the day branch protection lapses (#150; protection has enforced since 2026-08-06). The lapse is
# silent: a private repo on a free plan answers 403 and every rule stops applying, hence --protection.
# `gh pr checks` is the oracle, not a reimplementation: it already scores a CANCELLED run as failing against a
# required context. Protection 403, or requiring nothing, gates on contracts/required-checks.tsv (harbor#1060).
# EVERY check is judged by default, not only the required ones: with --required it reported ok while a
# non-required check was red. --required-only keeps the narrow "what blocks" question.
set -eu
MC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# The log goes to stderr, where the refusals always went (contracts/logging.md, LOG1).
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
. "$MC_DIR/library-log.sh"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

BRANCH="${HARBOR_GATE_BRANCH:-main}"
DO_MERGE=0; FORCE=0; PR=""; MODE=check; SUBJECT=""; MATCH=""; DELETE=0; REQUIRED_ONLY=0
# STRATEGY (harbor#267): harbor's --merge means "do the merge", gh's --merge is the merge-commit strategy.
# The default stays merge-commit; --squash/--rebase/--merge-commit select, and the chosen one is printed.
STRATEGY=merge
[ $# -gt 0 ] || { usage; exit 0; }
# --subject keeps the repo's `Merge harbor#N: <what>` title instead of GitHub's default.
while [ $# -gt 0 ]; do
  case "$1" in
    --merge)         DO_MERGE=1 ;;
    # A second, different strategy is refused up front, not discovered as a gh argument error after the check passed.
    --squash|--rebase|--merge-commit)
      _s="${1#--}"; [ "$_s" = merge-commit ] && _s=merge
      if [ -n "${STRATEGY_SET:-}" ] && [ "$_s" != "$STRATEGY" ]; then
        printf 'merge-check: two merge strategies given (--%s and %s)\n' "$STRATEGY" "$1" >&2
        exit 2
      fi
      STRATEGY="$_s"; STRATEGY_SET=1 ;;
    --force)         FORCE=1 ;;
    --protection)    MODE=protection ;;
    --required-only) REQUIRED_ONLY=1 ;;
    --delete-branch) DELETE=1 ;;
    --subject)       shift; [ $# -gt 0 ] || { echo "merge-check: --subject needs a value" >&2; exit 2; }; SUBJECT="$1" ;;
    # passed through untouched: gh refuses the merge if the head is no longer this commit (harbor#1060)
    # a pin that is empty or not a full sha would be dropped or matched loosely, so it is a usage error, never a no-op
    --match-head-commit) shift; [ $# -gt 0 ] || { echo "merge-check: --match-head-commit needs a sha" >&2; exit 2; }
      printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$' || { echo "merge-check: --match-head-commit needs a full 40-hex sha, got '$1'" >&2; exit 2; }
      MATCH="$1" ;;
    -h|--help)       usage; exit 0 ;;
    -*)              printf 'merge-check: unknown flag: %s\n' "$1" >&2; exit 2 ;;
    *)               PR="$1" ;;
  esac
  shift
done

command -v gh >/dev/null 2>&1 || { echo "merge-check: gh is not installed" >&2; exit 2; }

# HARBOR_SCOPE_REPO is owner/name here but a PATH in bin/drift-renew-check.sh. A path 404s the protection endpoint
# and reads as "no rule", a confident wrong answer, so the shape is validated (one slash, no leading slash, no
# whitespace) rather than renamed. Falls back to this script's own checkout: /harbor-merge runs from any cwd.
repo() {
  if [ -n "${HARBOR_SCOPE_REPO:-}" ]; then
    case "${HARBOR_SCOPE_REPO:-}" in
      */*/*|/*|*[[:space:]]*|*/)
        printf 'merge-check: HARBOR_SCOPE_REPO=%s is not owner/name.\n' "${HARBOR_SCOPE_REPO:-}" >&2
        printf '  This tool wants a GitHub repo id; bin/drift-renew-check.sh wants a PATH from the\n' >&2
        printf '  same variable name. Unset it here, or export HARBOR_SCOPE_REPO=owner/name.\n' >&2
        printf '' ;;
      */*) printf '%s' "${HARBOR_SCOPE_REPO:-}" ;;
      *)
        printf 'merge-check: HARBOR_SCOPE_REPO=%s is not owner/name (no slash).\n' "${HARBOR_SCOPE_REPO:-}" >&2
        printf '' ;;
    esac
    return 0
  fi
  _r="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || printf '')"
  [ -n "$_r" ] || _r="$(cd "$(dirname -- "$0")/.." 2>/dev/null && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || printf '')"
  printf '%s' "$_r"
}

# ── is the gate itself still there ──────────────────────────────────────────
if [ "$MODE" = protection ]; then
  R="$(repo)"
  [ -n "$R" ] || { echo "merge-check: could not determine the repository" >&2; exit 2; }
  # 200: rules exist, report the contexts (a typo'd context leaves the branch unmergeable). 403: plan lapsed. 404: no rule.
  _out="$(gh api "repos/$R/branches/$BRANCH/protection" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    _ctx="$(printf '%s' "$_out" | jq -r '.required_status_checks.contexts // [] | join(", ")' 2>/dev/null || printf '')"
    _strict="$(printf '%s' "$_out" | jq -r '.required_status_checks.strict // false' 2>/dev/null || printf '?')"
    if [ -z "$_ctx" ]; then
      log_fail "PROTECTION WEAK  $R/$BRANCH is protected but requires NO status checks"
      log_fix "require status checks on $BRANCH, or list them in contracts/required-checks.tsv (the local gate)"
      log_end || exit 1
    fi
    log_ok "protected  $R/$BRANCH"
    log_note "required: $_ctx"
    log_note "strict:   $_strict"
    log_end; exit 0
  fi
  case "$_out" in
    # A GitHub App installation token is refused by design: that says nothing about the plan.
    *"Resource not accessible by integration"*)
      log_fail "PROTECTION UNREADABLE  $R/$BRANCH protection is unreadable by this identity (a GitHub App token): HTTP 403, not a verdict on the repo"
      log_fix "run as a user token to read it; the gate is contracts/required-checks.tsv meanwhile"
      log_end || exit 1 ;;
    *"Upgrade to GitHub Pro"*|*403*)
      log_fail "PROTECTION GONE  $R/$BRANCH has NO branch protection: the API answers 403, a private repo on a free plan cannot carry rules"
      log_fix "list the required checks in contracts/required-checks.tsv; merge-check gates on it while GitHub cannot"
      log_note "nothing on GitHub reports this; the next red merge simply succeeds"
      log_end || exit 1 ;;
    *"Branch not protected"*|*404*)
      log_fail "PROTECTION ABSENT  $R/$BRANCH is reachable and carries no rule"
      log_fix "gh api -X PUT repos/$R/branches/$BRANCH/protection, or list the checks in contracts/required-checks.tsv"
      log_end || exit 1 ;;
    *)
      # UNKNOWN IS NOT OK: offline, unauthenticated or rate-limited is no evidence that the gate is up.
      log_fail "PROTECTION UNKNOWN  could not read $R/$BRANCH protection: $_out"
      log_fix "gh auth status; then re-run sh bin/gate-merge-check.sh --protection"
      log_end || exit 1 ;;
  esac
fi

# ── is this PR safe to merge ────────────────────────────────────────────────
case "$PR" in
  ''|*[!0-9]*) echo "merge-check: needs a PR number (see --help)" >&2; exit 2 ;;
esac
R="$(repo)"
[ -n "$R" ] || { echo "merge-check: could not determine the repository" >&2; exit 2; }

# WHICH GATE. GitHub's rule if it is readable and requires checks; else the tracked
# declaration for this repo, if it has rows; else neither (today's refusal).
_pout="$(gh api "repos/$R/branches/$BRANCH/protection" 2>&1)" && _prc=0 || _prc=$?
_pctx=""; _plist=""; GATE=none; GATE_WHY=""
if [ "$_prc" -eq 0 ]; then
  _pctx="$(printf '%s' "$_pout" | jq -r '.required_status_checks.contexts // [] | join(", ")' 2>/dev/null || printf '')"
  _plist="$(printf '%s' "$_pout" | jq -r '.required_status_checks.contexts // [] | .[]' 2>/dev/null || printf '')"
  [ -n "$_pctx" ] || GATE_WHY="branch protection requires no status checks"
else
  case "$_pout" in
    *"Resource not accessible by integration"*) GATE_WHY="protection unreadable by this identity (a GitHub App token), HTTP 403" ;;
    *"Upgrade to GitHub Pro"*|*403*) GATE_WHY="private repo on a free plan, HTTP 403" ;;
    # An org repo with no rule (the Flow forks): GitHub's exact 404 text, never any 404.
    *"Branch not protected"*) GATE_WHY="branch is not protected, HTTP 404" ;;
  esac
fi
RCFILE="${HARBOR_GATE_REQUIRED_CHECKS:-$MC_DIR/../contracts/required-checks.tsv}"
LISTED=""
if [ -r "$RCFILE" ]; then
  # With no list handed in, rows are core's then the private layer's (harbor#1149); a repo with no row has no local gate.
  _rcrows=""
  if [ -z "${HARBOR_GATE_REQUIRED_CHECKS:-}" ] && [ -f "$MC_DIR/gate-required-generate.sh" ]; then
    _rcrows="$(sh "$MC_DIR/gate-required-generate.sh" --core "$RCFILE" 2>/dev/null)" \
      || { _rcrows=""; log_warn "the private layer's required-checks.tsv does not compose with core's (or cannot be read), so only core's rows are read"; log_fix "sh $MC_DIR/gate-required-generate.sh   # names the line"; }
  fi
  [ -n "$_rcrows" ] || _rcrows="$(cat "$RCFILE")"
  LISTED="$(printf '%s\n' "$_rcrows" | awk -F'\t' -v r="$R" '$1 == r && $2 != "" { print $2 }')"
fi
if [ -n "$_pctx" ]; then
  GATE=github
  log_note "gate: GitHub branch protection"
  if [ -n "$LISTED" ] && [ "$(printf '%s\n' "$LISTED" | sort)" != "$(printf '%s\n' "$_plist" | sort)" ]; then
    log_warn "contracts/required-checks.tsv disagrees with branch protection for $R; file: $(printf '%s' "$LISTED" | paste -sd'|' - | sed 's/|/ | /g'); GitHub: $(printf '%s' "$_plist" | paste -sd'|' - | sed 's/|/ | /g')"
  fi
elif [ -n "$LISTED" ] && [ -n "$GATE_WHY" ]; then
  GATE=local
  log_note "gate: local (contracts/required-checks.tsv — GitHub protection unavailable: $GATE_WHY)"
fi

# gh exits non-zero both when a check fails and when nothing has reported, so the rows are the signal, not the
# status; captured so `set -e` survives.
if [ "$REQUIRED_ONLY" -eq 1 ] && [ "$GATE" != local ]; then
  CHECKS="$(gh pr checks "$PR" --repo "$R" --required 2>&1)" || :
else
  CHECKS="$(gh pr checks "$PR" --repo "$R" 2>&1)" || :
fi
# The required set is read separately so each row can be labelled.
if [ "$GATE" = local ]; then
  REQNAMES="$LISTED"
else
  REQNAMES="$(gh pr checks "$PR" --repo "$R" --required 2>/dev/null | cut -f1 || :)"
fi
REQROWS=0
while IFS= read -r _r; do [ -n "$_r" ] && REQROWS=$((REQROWS + 1)); done <<REQL
$REQNAMES
REQL

BAD=""
ROWS=0
while IFS= read -r _line; do
  [ -n "$_line" ] || continue
  ROWS=$((ROWS + 1))
  _name="$(printf '%s' "$_line" | cut -f1)"
  _state="$(printf '%s' "$_line" | cut -f2)"
  _url="$(printf '%s' "$_line" | cut -f4)"
  _tag=""
  printf '%s\n' "$REQNAMES" | grep -Fxq "$_name" && _tag=" [required]"
  [ "$GATE" = local ] && [ "$REQUIRED_ONLY" -eq 1 ] && [ -z "$_tag" ] && continue
  case "$_state" in
    # `skipping` is a job that did not run, not a failure (CONSTITUTION §2.11).
    pass|skipping) ;;
    *) # A JOB NO RUNNER EVER TOOK STILL REFUSES — nothing green exists to merge
       # A job no runner took still refuses but is labelled a re-run, not a failure (harbor#675; bin/ci-lost-job.sh).
       _lost=""
       case "$_state" in
         fail|cancel)
           _lrc=0; _re="$(sh "$MC_DIR/ci-lost-job.sh" "$R" "$_url" 2>/dev/null)" || _lrc=$?
           case "$_lrc" in
             0) _lost=" — LOST IN DISPATCH: no runner took it, nothing failed. Re-run: $_re" ;;
             3) _lost=" — REFUSED FOR BILLING: nothing failed. $_re" ;;
           esac ;;
       esac
       BAD="$BAD$(printf '\n  %-22s %-9s %s%s%s' "$_name" "$_state" "$_url" "$_tag" "$_lost")" ;;
  esac
done <<CHECKROWS
$CHECKS
CHECKROWS

# A required check must have reported (harbor#1073): `gh pr checks --required` lists only existing contexts.
# Local gate: `skipping` is no pass either; the GitHub gate scores skipped as met.
if [ "$GATE" != none ]; then
  if [ "$GATE" = local ]; then _need="$LISTED"; else _need="$_plist"; fi
  while IFS= read -r _n; do
    [ -n "$_n" ] || continue
    _sts="$(printf '%s\n' "$CHECKS" | awk -F'\t' -v n="$_n" '$1 == n { print $2 }')"
    if [ -z "$_sts" ]; then
      BAD="$BAD$(printf '\n  %-22s %-9s %s [required]' "$_n" missing 'never reported on this PR head')"
    elif [ "$GATE" = local ] && printf '%s\n' "$_sts" | grep -qx skipping; then
      BAD="$BAD$(printf '\n  %-22s %-9s %s [required]' "$_n" skipping 'a listed check must run and pass')"
    fi
  done <<LISTL
$_need
LISTL
fi

VERDICT=pass
WHY=""
if [ "$ROWS" -eq 0 ]; then
  # No rows is not a pass: nothing has reported yet, or the repo has no protection.
  VERDICT=refuse
  WHY="no required checks have reported on #$PR
  $CHECKS"
elif [ "$GATE" != local ] && [ "$REQROWS" -eq 0 ]; then
  # Rows but nothing REQUIRED is two cases (no rule: nothing gates; rule exists, run not there yet); `--required`
  # is empty for both, so the branch rule is the tiebreaker.
  VERDICT=refuse
  if [ -n "$_pctx" ]; then
    WHY="#$PR has $ROWS check(s) reporting, but none of the REQUIRED contexts has:
  waiting on: $_pctx"
  else
    WHY="checks are reporting on #$PR and NONE of them is required — nothing gates this merge"
  fi
elif [ -n "$BAD" ]; then
  VERDICT=refuse
  WHY="a check is not passing on #$PR:$BAD"
fi

# THE AMENDMENT GATE (harbor#1026). A PR that changes a constitutional clause (its row or its prose) is merged only with the
# `amendment:approved` label, which an agent cannot apply (the disposition-label refusal, harbor#855). --force does not lift it:
# an override of a red check is a person's call recorded in the commit; an amendment is the person's approval itself.
AMEND_REFUSE=""
# GitHub refuses a diff over 300 files (HTTP 406); the files API lists up to 3000, and a list at that cap may be cut short.
pr_files() {
  gh pr diff "$PR" --repo "$R" --name-only 2>/dev/null && return 0
  _pf="$(gh api "repos/$R/pulls/$PR/files" --paginate -q '.[].filename' 2>/dev/null)" || return 1
  [ "$(printf '%s\n' "$_pf" | grep -c .)" -lt 3000 ] || return 1
  printf '%s\n' "$_pf"
}
if _afiles="$(pr_files)"; then
  if printf '%s\n' "$_afiles" | grep -qxE 'policy/(constitution\.md|clauses\.tsv)'; then
    _ameta="$(gh pr view "$PR" --repo "$R" --json baseRefOid,headRefOid,labels 2>/dev/null || printf '')"
    _abase="$(printf '%s' "$_ameta" | jq -r '.baseRefOid // empty' 2>/dev/null || printf '')"
    _ahead="$(printf '%s' "$_ameta" | jq -r '.headRefOid // empty' 2>/dev/null || printf '')"
    _alab="$(printf '%s' "$_ameta" | jq -r '.labels[]?.name' 2>/dev/null || printf '')"
    _atmp="$(mktemp -d "${TMPDIR:-/tmp}/amend.XXXXXX")"; _aok=1
    for _side in base head; do
      if [ "$_side" = base ]; then _aref="$_abase"; else _aref="$_ahead"; fi
      mkdir -p "$_atmp/$_side/policy"
      for _af in constitution.md clauses.tsv; do
        [ -n "$_aref" ] && gh api "repos/$R/contents/policy/$_af?ref=$_aref" -H "Accept: application/vnd.github.raw" > "$_atmp/$_side/policy/$_af" 2>"$_atmp/err" && continue
        # A base without the file is a first publish: every clause is new, so the label is still asked (harbor-core#88).
        [ "$_side" = base ] && [ -n "$_aref" ] && grep -q 'HTTP 404' "$_atmp/err" && { : > "$_atmp/$_side/policy/$_af"; continue; }
        _aok=0
      done
    done
    if [ "$_aok" -eq 0 ]; then
      AMEND_REFUSE="the PR changes policy/ and its base or head could not be read, so whether a constitutional clause changed is unknown"
    elif _aout="$(sh "$MC_DIR/policy-check.sh" --amends "$_atmp/base" "$_atmp/head" 2>&1)"; then
      :
    elif ! printf '%s\n' "$_alab" | grep -qx 'amendment:approved'; then
      AMEND_REFUSE="the PR amends a constitutional clause and carries no amendment:approved label (a person applies it): $(printf '%s' "$_aout" | grep 'WARN:' | sed 's/.*\] //' | paste -sd';' - )"
    fi
    rm -rf "$_atmp"
  fi
else
  AMEND_REFUSE="the PR's changed files could not be read, so whether it amends the constitution is unknown"
fi

if [ -n "$AMEND_REFUSE" ]; then
  log_fail "REFUSED  $AMEND_REFUSE"
  log_fix "the operator applies the label amendment:approved after reading the diff; --force does not lift this"
  log_end || :
  exit 1
fi

if [ "$VERDICT" = pass ]; then
  log_ok "#$PR — $ROWS check(s) pass, $REQROWS of them required"
else
  log_fail "REFUSED  $(printf '%s\n' "$WHY" | sed -n 1p)"
  log_fix "re-run once the check passes; sh bin/gate-merge-check.sh --merge $PR --force overrides and records it"
  printf '%s\n' "$WHY" | sed 1d | sed 's/^ *//' | while IFS= read -r _wl; do [ -z "$_wl" ] || log_note "$_wl"; done
fi
log_end || :

[ "$DO_MERGE" -eq 1 ] || { [ "$VERDICT" = pass ] || exit 1; exit 0; }

if [ "$VERDICT" != pass ] && [ "$FORCE" -eq 0 ]; then
  printf '\n  not merging. Pass --force to override, and it will be recorded.\n' >&2
  exit 1
fi

# The override goes in the merge commit body, so `git log` can answer "was this merged red, and who decided?".
BODY=""
if [ "$VERDICT" != pass ]; then
  # A rebase creates no merge commit, so the --body override record has nowhere to land: refused, not dropped
  # (PR #270 review). --squash is fine.
  if [ "$STRATEGY" = rebase ]; then
    printf 'merge-check: --force cannot be recorded under --rebase.\n' >&2
    printf '  A rebase creates no merge commit, so the override note has nowhere to live\n' >&2
    printf '  and "was this merged red, and did someone decide that?" stops being\n' >&2
    printf '  answerable from git log. Use --squash or --merge-commit to override.\n' >&2
    exit 2
  fi
  printf '\n  OVERRIDING a refusal. This will be written into the merge commit.\n' >&2
  BODY="$(printf 'Merged over a merge-check refusal.\n\n%s' "$WHY")"
fi
printf '  strategy: --%s\n' "$STRATEGY" >&2
set -- "$PR" --repo "$R" "--$STRATEGY"
[ "$DELETE" -eq 1 ] && set -- "$@" --delete-branch
[ -n "$SUBJECT" ] && set -- "$@" --subject "$SUBJECT"
[ -n "$MATCH" ]   && set -- "$@" --match-head-commit "$MATCH"
[ -n "$BODY" ]    && set -- "$@" --body "$BODY"
gh pr merge "$@"
