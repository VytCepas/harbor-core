#!/usr/bin/env sh
# merge-check.sh — refuse to merge a PR that has no green verdict (CI-3, harbor#150)
#
#   sh merge-check.sh <pr>              exit 0 = safe to merge, 1 = refused
#   sh merge-check.sh --merge <pr>      check, then merge only if it passes
#   sh merge-check.sh --merge <pr> --force
#                                       merge anyway; the override is written
#                                       into the merge commit, not just printed
#   sh merge-check.sh --protection      is branch protection still there at all?
#   --required-only                     only the checks that BLOCK, not every check
#   --subject <text> --delete-branch --match-head-commit <sha>
#                                       passed through to `gh pr merge`
#   --squash | --rebase | --merge-commit
#                                       how to land it (default: a merge commit,
#                                       which is what this tool has always done —
#                                       harbor#267). The chosen one is printed.
#
#   HARBOR_REPO   owner/name; default comes from the checkout's remote, and
#                 falling back to THIS SCRIPT'S checkout when cwd is elsewhere.
#                 NOT a path — bin/renew-check.sh reads the same name as a path;
#                 a value that is not owner/name is REFUSED here, see repo().
#   HARBOR_BRANCH the protected branch (default: main)
#   HARBOR_REQUIRED_CHECKS
#                 the local gate's declaration (default: CONTRACTS/required-checks.tsv
#                 beside this script, followed by the private layer's required-checks.tsv
#                 when gate-required-generate.sh is beside it): repo<TAB>check name, one
#                 row per required check. Set, it is the only list read
#
# WHY THIS EXISTS, AND WHY ITS SCOPE SHRANK. #150 specified this as the merge
# gate GitHub could not provide, because branch protection needs a paid plan on a
# private repo. The plan was bought on 2026-08-06 and protection now enforces, so
# this is no longer the gate — it is the BACKSTOP for the day it goes away.
#
# THE LAPSE IS SILENT, which is the whole argument for `--protection`. A private
# repo on a free plan does not report "your rules are off"; the protection
# endpoint simply answers 403 and every rule stops applying. Nothing in the UI
# turns red, no PR complains, and the next merge of a failing branch succeeds
# quietly. A subscription is a control with an expiry date and no alarm.
#
# `gh pr checks` IS THE ORACLE, deliberately, rather than a reimplementation over
# the check-runs API. It is what GitHub itself scores, and it already encodes the
# rule that cost this repo a morning: a CANCELLED check run counts as FAILING
# against a required context and never clears. A local reimplementation would
# have to rediscover that, and would drift the first time GitHub changed how a
# conclusion maps to a verdict. Copies of a fact that lives somewhere else drift
# silently while reading correctly.
#
# THE LAPSE HAPPENED (2026-10-05, harbor#1060): protection 403, or requiring
# nothing, gates on CONTRACTS/required-checks.tsv instead — each listed check
# must be on the PR head and pass. Protection that requires checks stays the gate.
#
# EVERY CHECK, NOT ONLY THE REQUIRED ONES — and this is a CORRECTION, made the
# first time the tool was pointed at a real merge. It ran with `--required`, and
# `main` then required exactly two of roughly thirteen jobs on purpose, so it reported
#
#   ok  #157 — every required check passes (2)
#
# while `recover red-green` sat at `failure`. It was not wrong by its own
# definition; it was answering a narrower question than the one being asked.
# "Would GitHub let this through" and "is anything red" are different questions
# on a repo that requires a subset, and a tool whose whole job is refusing to
# merge red must answer the second one by default. `--required-only` keeps the
# first available, because knowing what actually BLOCKS is a real question too.
set -eu
MC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# The log goes to stderr, where the refusals always went (CONTRACTS/logging.md, LOG1).
LOG_FD=2
. "$MC_DIR/log-lib.sh"

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

BRANCH="${HARBOR_BRANCH:-main}"
DO_MERGE=0; FORCE=0; PR=""; MODE=check; SUBJECT=""; MATCH=""; DELETE=0; REQUIRED_ONLY=0
# ── THE STRATEGY IS A CHOICE, AND IT WAS HARDCODED (harbor#267) ──────────────
# `--merge` MEANS TWO DIFFERENT THINGS in this file, which is the whole reason
# this was easy to miss: harbor's `--merge` is "do the merge", and gh's `--merge`
# is the merge-COMMIT strategy. The second one was written into the argv below
# with no way to choose it, so the squash shape was unreachable through the
# sanctioned route — and squash is what 95 of 287 commits on `main` use, 18 of
# the last 20. Measured 2026-08-22.
#
# THE DEFAULT DOES NOT MOVE. Both shapes are established here — 29 of the last 80
# commits have two parents, and `--subject` exists to give those the conventional
# `Merge harbor#N: …` title — so which one this repo should prefer is a convention
# decision for the operator, not a side effect of a bug fix. What changes is that
# the other two are now reachable, and that the chosen one is PRINTED: a strategy
# nobody can see is one nobody notices is wrong.
STRATEGY=merge
[ $# -gt 0 ] || { usage; exit 0; }
# `--subject` EXISTS BECAUSE OF THE FIRST REAL USE. Without it `--merge` produces
# GitHub's default "Merge pull request #N from <branch>", and this repo's history
# is "Merge harbor#N: <what it does>". A gate that costs you the commit
# convention is a gate people route around, and a gate nobody uses enforces
# nothing — which is the same "a rule with no mechanism is a wish" trap this
# whole tool exists to avoid falling into.
while [ $# -gt 0 ]; do
  case "$1" in
    --merge)         DO_MERGE=1 ;;
    # ONE STRATEGY, AND A SECOND ONE IS REFUSED rather than silently overwriting
    # the first. `--squash --rebase` is a caller who does not know what they want,
    # and learning that from gh's error AFTER the backstop has already run is
    # learning it too late — the check would have passed and the merge would then
    # fail on argument parsing, which reads like the gate broke.
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

# ONE NAME, TWO MEANINGS — and only one of them can be right here. This file
# documents HARBOR_REPO as `owner/name`; bin/renew-check.sh:38 uses the SAME
# variable as a FILESYSTEM PATH (`REPO="${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}"`) and its
# header tells the operator to set it that way. Measured 2026-08-13 with the
# renew-check spelling exported:
#
#   HARBOR_REPO="$HOME/harbor" sh bin/merge-check.sh --protection
#   -> PROTECTION ABSENT  $HOME/harbor/main is reachable and carries no rule
#
# Wrong, on the one question this file exists to answer. `gh api
# repos/$HARBOR_REPO/branches/main/protection` 404s, and the 404 arm
# below correctly means "reachable, no rule configured" — so a nonsense repo id
# is indistinguishable from a real lapse. The asymmetry is what makes it a
# defect rather than a nuisance: renew-check STANDS DOWN and says so when the
# value is the wrong kind, while this file returned a confident wrong answer
# about whether the merge gate still exists.
#
# So VALIDATE THE SHAPE rather than rename. Renaming would break the operator's
# muscle memory for whichever tool lost, and both headers already document their
# own meaning; what was missing is a refusal when the value cannot possibly be
# what this file needs. `owner/name` is exactly one slash, no leading slash, and
# no whitespace — a path fails all three.
#
# AND FALL BACK TO THIS SCRIPT'S OWN CHECKOUT, because /harbor-merge runs from
# whatever cwd the session is in and `gh repo view` needs to be inside a git
# remote. Same shape as bin/status-gen.sh:80: the script knows where it lives.
repo() {
  if [ -n "${HARBOR_REPO:-}" ]; then
    case "$HARBOR_REPO" in
      */*/*|/*|*[[:space:]]*|*/)
        printf 'merge-check: HARBOR_REPO=%s is not owner/name.\n' "$HARBOR_REPO" >&2
        printf '  This tool wants a GitHub repo id; bin/renew-check.sh wants a PATH from the\n' >&2
        printf '  same variable name. Unset it here, or export HARBOR_REPO=owner/name.\n' >&2
        printf '' ;;
      */*) printf '%s' "$HARBOR_REPO" ;;
      *)
        printf 'merge-check: HARBOR_REPO=%s is not owner/name (no slash).\n' "$HARBOR_REPO" >&2
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
  # The three answers are genuinely different and only one of them is fine.
  #   200  rules exist — report which contexts, so a TYPO is visible too. A
  #        required context naming a check nobody reports never goes green and
  #        makes the branch permanently unmergeable, silently.
  #   403  the plan no longer allows protection on a private repo. THE LAPSE.
  #   404  the endpoint is reachable and no rule is configured.
  _out="$(gh api "repos/$R/branches/$BRANCH/protection" 2>&1)" && _rc=0 || _rc=$?
  if [ "$_rc" -eq 0 ]; then
    _ctx="$(printf '%s' "$_out" | jq -r '.required_status_checks.contexts // [] | join(", ")' 2>/dev/null || printf '')"
    _strict="$(printf '%s' "$_out" | jq -r '.required_status_checks.strict // false' 2>/dev/null || printf '?')"
    if [ -z "$_ctx" ]; then
      log_fail "PROTECTION WEAK  $R/$BRANCH is protected but requires NO status checks"
      log_fix "require status checks on $BRANCH, or list them in CONTRACTS/required-checks.tsv (the local gate)"
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
      log_fix "run as a user token to read it; the gate is CONTRACTS/required-checks.tsv meanwhile"
      log_end || exit 1 ;;
    *"Upgrade to GitHub Pro"*|*403*)
      log_fail "PROTECTION GONE  $R/$BRANCH has NO branch protection: the API answers 403, a private repo on a free plan cannot carry rules"
      log_fix "list the required checks in CONTRACTS/required-checks.tsv; merge-check gates on it while GitHub cannot"
      log_note "nothing on GitHub reports this; the next red merge simply succeeds"
      log_end || exit 1 ;;
    *"Branch not protected"*|*404*)
      log_fail "PROTECTION ABSENT  $R/$BRANCH is reachable and carries no rule"
      log_fix "gh api -X PUT repos/$R/branches/$BRANCH/protection, or list the checks in CONTRACTS/required-checks.tsv"
      log_end || exit 1 ;;
    *)
      # UNKNOWN IS NOT OK. Offline, unauthenticated, rate-limited — none of them
      # are evidence that the gate is up, and reporting them as fine is how a
      # backstop becomes decoration.
      log_fail "PROTECTION UNKNOWN  could not read $R/$BRANCH protection: $_out"
      log_fix "gh auth status; then re-run sh bin/merge-check.sh --protection"
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
RCFILE="${HARBOR_REQUIRED_CHECKS:-$MC_DIR/../CONTRACTS/required-checks.tsv}"
LISTED=""
if [ -r "$RCFILE" ]; then
  # Run from a checkout with no list handed in, the rows are core's then the private layer's (gate-required-generate.sh, harbor#1149).
  # An overlay that does not compose leaves core's rows alone, and says so: a repo with no row has no local gate, which refuses.
  _rcrows=""
  if [ -z "${HARBOR_REQUIRED_CHECKS:-}" ] && [ -f "$MC_DIR/gate-required-generate.sh" ]; then
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
    log_warn "CONTRACTS/required-checks.tsv disagrees with branch protection for $R; file: $(printf '%s' "$LISTED" | paste -sd'|' - | sed 's/|/ | /g'); GitHub: $(printf '%s' "$_plist" | paste -sd'|' - | sed 's/|/ | /g')"
  fi
elif [ -n "$LISTED" ] && [ -n "$GATE_WHY" ]; then
  GATE=local
  log_note "gate: local (CONTRACTS/required-checks.tsv — GitHub protection unavailable: $GATE_WHY)"
fi

# `gh pr checks` exits non-zero when anything is not passing AND when nothing has
# reported yet; both must refuse, so the exit status is not the signal — the rows
# are. Captured rather than piped so a failing exit does not end the script under
# `set -e`.
if [ "$REQUIRED_ONLY" -eq 1 ] && [ "$GATE" != local ]; then
  CHECKS="$(gh pr checks "$PR" --repo "$R" --required 2>&1)" || :
else
  CHECKS="$(gh pr checks "$PR" --repo "$R" 2>&1)" || :
fi
# The required set is read separately so each row can be LABELLED. A refusal that
# does not say whether the red check actually blocks the merge sends the reader
# to the settings page to find out.
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
    # `skipping` is gh's word for a job that did not run. It is not a failure and
    # must not be treated as one, or the tool refuses every ordinary PR the
    # moment a conditional job exists — CONSTITUTION §2.11.
    pass|skipping) ;;
    *) # A JOB NO RUNNER EVER TOOK STILL REFUSES — nothing green exists to merge
       # on — but it is labelled, because it is a re-run and not a failure
       # (harbor#675). bin/ci-lost-job.sh owns the read; a link that is not an
       # Actions job, or an annotation it cannot read, leaves the row unlabelled.
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

# A REQUIRED CHECK MUST HAVE REPORTED. Missing is not a pass: `gh pr checks
# --required` lists only the contexts that exist, so a required check not yet
# created reads as "all present checks green" (harbor#1073). Local gate: the
# listed names, and `skipping` is no pass either — a listed check is a relay
# that runs every time. GitHub gate: its contexts; GitHub itself scores skipped as met.
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
  # NO ROWS IS NOT A PASS. It is the state a PR sits in before anything has
  # reported, and it is also what a repo with no protection looks like — the
  # case this tool exists for. Either way there is no verdict to merge on.
  VERDICT=refuse
  WHY="no required checks have reported on #$PR
  $CHECKS"
elif [ "$GATE" != local ] && [ "$REQROWS" -eq 0 ]; then
  # ROWS > 0 and nothing is REQUIRED. That is TWO different situations and a
  # refusal that cannot tell them apart is not actionable:
  #
  #   the branch carries no rule          → nothing gates this merge, ever
  #   the rule exists, nothing reported   → the required run has not got there
  #
  # `gh pr checks --required` returns empty for both, so the branch rule itself
  # is the tiebreaker. Measured against #158 while its run was still queued: the
  # first draft of this arm reported "nothing gates this merge" about a properly
  # protected branch, which is exactly the kind of confidently wrong refusal that
  # gets a gate switched off.
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

if [ "$VERDICT" = pass ]; then
  log_ok "#$PR — $ROWS check(s) pass, $REQROWS of them required"
else
  log_fail "REFUSED  $(printf '%s\n' "$WHY" | sed -n 1p)"
  log_fix "re-run once the check passes; sh bin/merge-check.sh --merge $PR --force overrides and records it"
  printf '%s\n' "$WHY" | sed 1d | sed 's/^ *//' | while IFS= read -r _wl; do [ -z "$_wl" ] || log_note "$_wl"; done
fi
log_end || :

[ "$DO_MERGE" -eq 1 ] || { [ "$VERDICT" = pass ] || exit 1; exit 0; }

if [ "$VERDICT" != pass ] && [ "$FORCE" -eq 0 ]; then
  printf '\n  not merging. Pass --force to override, and it will be recorded.\n' >&2
  exit 1
fi

# THE OVERRIDE GOES IN THE MERGE COMMIT, not only on the terminal. A warning
# printed at the moment of the merge is gone as soon as the scrollback is, and
# the question a reader asks six weeks later — "was this merged red, and did
# someone decide that?" — is answerable only from the history. `git log` is the
# one place that cannot be lost.
BODY=""
if [ "$VERDICT" != pass ]; then
  # ── A REBASE CANNOT CARRY THE RECORD, SO IT IS REFUSED (PR #270 review) ────
  # The override is only worth anything because it survives the scrollback, and
  # it survives by riding in a commit body. Read out of the installed
  # `gh pr merge --help`: `--body` is "Body text for the merge commit", and
  # `--rebase` replays the existing commits onto the base — it creates no merge
  # commit at all. So `--force --rebase` printed the promise and wrote it
  # nowhere: the one path where the guarantee matters most is the one where it
  # silently evaporated.
  #
  # REFUSED RATHER THAN DEGRADED. Merging red is the operator's call to make;
  # making it and leaving no trace is not, and a warning that the trace was
  # dropped would be read past. `--squash` is fine — a squash produces a commit
  # and `--body` lands in it — so this refusal is exactly as narrow as the defect.
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
