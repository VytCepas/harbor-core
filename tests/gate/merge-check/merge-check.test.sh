#!/usr/bin/env sh
# gate-merge-check.sh fails permissively if it fails at all: a refusal that becomes a pass is invisible
# (CI-3, harbor#150). `gh` is a stub that logs every call, so cases check what the tool DID.
. "$(dirname "$0")/../../lib/core.sh"; t_init
MC="$T_ROOT/bin/gate-merge-check.sh"; STUB="$T_TMP/stub"; mkdir -p "$STUB"
LOG="$T_TMP/gh.log"; CHECKS="$T_TMP/checks.tsv"; REQF="$T_TMP/required.tsv"
PROT="$T_TMP/protection.json"; PROT_RC="$T_TMP/protection.rc"; ANNOT="$T_TMP/annot.txt"
RCF="$T_TMP/required-checks.tsv"  # the local gate's declaration; absent unless a case writes it
# `pr checks` rows are TAB separated, as real gh emits and the tool cuts on. --required returns
# its own set: main requires 2 of ~13 jobs. A malformed repo id 404s, as real gh does.
cat > "$STUB/gh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$LOG"
case "\$1 \$2" in
  "repo view")  echo "VytCepas/harbor"; exit 0 ;;
  "pr checks")
                case " \$* " in *" --required "*) _f="$REQF" ;; *) _f="$CHECKS" ;; esac
                cat "\$_f"; [ -s "\$_f" ] || exit 1
                grep -qv 'pass' "\$_f" && exit 1
                exit 0 ;;
  "api repos"*)
                _p="\${2#repos/}"
                _o="\${_p%%/*}"; _rest="\${_p#*/}"
                _n="\${_rest%%/*}"; _tail="\${_rest#*/}"
                if [ -n "\$_o" ] && [ -n "\$_n" ]; then
                  case "\$_tail" in
                    branches/*) cat "$PROT"; exit "\$(cat "$PROT_RC")" ;;
                    check-runs/*/annotations) cat "$ANNOT" 2>/dev/null; exit 0 ;;
                  esac
                fi
                echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  "pr merge")   echo "merged"; exit 0 ;;
esac
case "\$1" in
  api) cat "$PROT"; exit "\$(cat "$PROT_RC")" ;;
esac
exit 0
STUB
chmod +x "$STUB/gh"

mc() { : > "$LOG"; PATH="$STUB:$PATH" HARBOR_REPO=VytCepas/harbor HARBOR_REQUIRED_CHECKS="$RCF" sh "$MC" "$@" 2>&1; }
rc() { mc "$@" >/dev/null; echo $?; }
merges() { grep -c '^pr merge' "$LOG"; }  # 1 when the last call ran gh pr merge
glog() { cat "$LOG"; }
rows() { printf '%s' "$1" > "$CHECKS"; printf '%s' "$1" > "$REQF"; }    # every row is required
rows2() { printf '%s' "$1" > "$CHECKS"; printf '%s' "$2" > "$REQF"; }  # <all> <required>
prot() { printf '%s' "$1" > "$PROT"; printf '%s' "$2" > "$PROT_RC"; }
TAB="$(printf '\t')"
GREEN="conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}pass${TAB}2m56s${TAB}https://x/run/2"
REDROW="conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}fail${TAB}24s${TAB}https://x/run/2"
PENDROW="conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}pending${TAB}0${TAB}https://x/run/2"
PROTECTED='{"required_status_checks":{"contexts":["conventions linter","security-floor suite"],"strict":true}}'
prot "$PROTECTED" 0

t_section "the verdict"
rows "$GREEN"
t_eq "an all-green PR passes (a gate that blocks ordinary work gets switched off)" 0 "$(rc 156)"
rows "$REDROW"
t_eq "a failing required check is refused" 1 "$(rc 156)"
t_has "the refusal says it refused" "$(mc 156)" 'REFUSED'
t_has "the refusal names the failed check's run URL" "$(mc 156)" 'https://x/run/2'
t_has "the refusal names which check failed" "$(mc 156)" 'security-floor suite'
rows "$PENDROW"
t_eq "a pending required check is not a pass" 1 "$(rc 156)"

t_section "a job GitHub never dispatched is a refusal labelled as a re-run (harbor#675)"
rows "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
manifest shard 1${TAB}cancel${TAB}0${TAB}https://github.com/VytCepas/harbor/actions/runs/7/job/9"
printf 'The job was not acquired by Runner of type self-hosted even after multiple attempts\n' > "$ANNOT"
t_eq "a lost job has no green verdict to merge on" 1 "$(rc 156)"
t_has "a lost job is labelled LOST IN DISPATCH" "$(mc 156)" 'LOST IN DISPATCH'
t_has "…with its re-run command" "$(mc 156)" 'gh run rerun --job 9 --repo VytCepas/harbor'
printf 'Process completed with exit code 1.\n' > "$ANNOT"
t_hasnt "a job that ran and failed is not labelled lost" "$(mc 156)" 'LOST IN DISPATCH'
rm -f "$ANNOT"

t_section "a check refused for billing is a refusal labelled as such (harbor#1060)"
rows "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}fail${TAB}0${TAB}https://github.com/VytCepas/harbor/actions/runs/7/job/9"
printf 'The job was not started because recent account payments have failed or your spending limit needs to be increased\n' > "$ANNOT"
t_eq "a billing-refused check has no green verdict to merge on" 1 "$(rc 156)"
t_has "it is labelled REFUSED FOR BILLING" "$(mc 156)" 'REFUSED FOR BILLING'
t_has "...with the action" "$(mc 156)" 'do not raise the spending limit'
t_hasnt "...and not as lost in dispatch" "$(mc 156)" 'LOST IN DISPATCH'
printf 'Process completed with exit code 1.\n' > "$ANNOT"
t_hasnt "a job that ran and failed is not labelled billing" "$(mc 156)" 'REFUSED FOR BILLING'
rm -f "$ANNOT"

t_section "no rows is the dangerous one"
rows ""
t_eq "no checks reported at all is refused" 1 "$(rc 156)"
t_has "the empty case explains itself" "$(mc 156)" 'no required checks have reported'

t_section "--merge does not merge on a refusal"
rows "$GREEN";  mc --merge 156 >/dev/null; t_eq "--merge merges a PR whose checks pass" 1 "$(merges)"
rows "$REDROW"; mc --merge 156 >/dev/null; t_eq "--merge does not merge a failing required check" 0 "$(merges)"
rows "";        mc --merge 156 >/dev/null; t_eq "--merge does not merge a PR with no verdict" 0 "$(merges)"
rows "$REDROW"
t_has "the refusal names the override flag" "$(mc --merge 156)" '--force'

t_section "--force is recorded in the merge commit, not just printed"
rows "$REDROW"; mc --merge 156 --force >/dev/null
t_eq "--force merges" 1 "$(merges)"
t_has "the override is recorded in the merge commit" "$(glog)" 'Merged over a merge-check refusal'
t_has "the record names what was overridden" "$(glog)" 'security-floor suite'
rows "$GREEN"; mc --merge 156 --force >/dev/null
t_hasnt "no override note on a merge that needed none" "$(glog)" 'Merged over a merge-check refusal'

t_section "a red check that does not block (the 2026-08-06 defect)"
REQ_ONLY="conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}pass${TAB}2m56s${TAB}https://x/run/2"
rows2 "$REQ_ONLY
recover red-green${TAB}fail${TAB}24s${TAB}https://x/run/9" "$REQ_ONLY"
t_eq "a failing non-required check is refused" 1 "$(rc 156)"
t_has "the refusal names the non-required red check" "$(mc 156)" 'recover red-green'
mc --merge 156 >/dev/null; t_eq "--merge does not merge over a red non-required check" 0 "$(merges)"
t_eq "--required-only answers only what blocks" 0 "$(rc 156 --required-only)"
rows2 "conventions linter${TAB}fail${TAB}55s${TAB}https://x/run/1" "conventions linter${TAB}fail${TAB}55s${TAB}https://x/run/1"
t_has "a failing required check is labelled [required]" "$(mc 156)" '[required]'
rows2 "$REQ_ONLY
optional thing${TAB}skipping${TAB}0${TAB}https://x/run/8" "$REQ_ONLY"
t_eq "a skipped job is not a failure" 0 "$(rc 156)"

t_section "checks report, none of them required"
rows2 "some other job${TAB}pass${TAB}10s${TAB}https://x/run/7" ""
t_eq "required checks not yet reported is refused" 1 "$(rc 156)"
t_has "…and says what it is waiting on" "$(mc 156)" 'waiting on'
prot '{"required_status_checks":null}' 0
t_has "an unprotected branch is told apart from a pending one" "$(mc 156)" 'nothing gates this merge'
prot "$PROTECTED" 0

# harbor#1060: on a free plan the protection read answers 403 and GitHub requires nothing, so the
# tracked file is the gate. `pr checks --required` reports nothing then, which rows2 "" models.
t_section "local gate: GitHub protection unavailable (harbor#1060)"
P403='gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)'
GATE_L='gate: local (contracts/required-checks.tsv'
decl() { printf 'VytCepas/harbor\t%s\n' "$@" > "$RCF"; }
decl "conventions linter" "security-floor suite"
prot "$P403" 1
rows2 "$GREEN" ""
t_eq "403 + listed checks all passing: the local gate passes" 0 "$(rc 156)"
t_has "the gate line says local" "$(mc 156)" 'gate: local'
t_has "…with the file and the reason" "$(mc 156)" "$GATE_L — GitHub protection unavailable: "
t_has "…and the reason names the plan lapse" "$(mc 156)" 'free plan'
# harbor#1153: a GitHub App token is refused by design; that is not a plan lapse. Same gate, true reason.
PAPP='gh: Resource not accessible by integration (HTTP 403)'
prot "$PAPP" 1
t_eq "App 403 + listed checks passing: the local gate still passes" 0 "$(rc 156)"
t_has "…and the reason names the identity" "$(mc 156)" 'unreadable by this identity (a GitHub App token)'
t_hasnt "…and never the free plan" "$(mc 156)" 'free plan'
rows2 "$REDROW" ""
t_eq "App 403 + a listed check failing: still refused" 1 "$(rc 156)"
prot "$P403" 1
rows2 "$GREEN" ""
t_has "the ok line counts the listed checks as required" "$(mc 156)" '2 of them required'
rows2 "$REDROW" ""
t_eq "a listed check failing is refused" 1 "$(rc 156)"
t_has "…and named, with its run" "$(mc 156)" 'security-floor suite'
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}cancel${TAB}24s${TAB}https://x/run/2" ""
t_eq "a listed check cancelled is failing" 1 "$(rc 156)"
rows2 "$PENDROW" ""
t_eq "a listed check pending is not a pass" 1 "$(rc 156)"
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
some other job${TAB}pass${TAB}10s${TAB}https://x/run/7" ""
t_eq "a listed check that never reported is refused" 1 "$(rc 156)"
t_has "…and says which one never reported" "$(mc 156)" 'never reported'
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}skipping${TAB}0${TAB}https://x/run/2" ""
t_eq "a listed check skipped is not a pass" 1 "$(rc 156)"
rows2 "$GREEN
recover red-green${TAB}fail${TAB}24s${TAB}https://x/run/9" ""
t_eq "every check still counts: an unlisted red check is refused" 1 "$(rc 156)"
t_eq "--required-only answers only the listed ones" 0 "$(rc 156 --required-only)"
rows2 "$GREEN" ""; mc --merge 156 >/dev/null
t_eq "--merge merges when the local gate passes" 1 "$(merges)"
rows2 "$REDROW" ""; mc --merge 156 >/dev/null
t_eq "--merge does not merge on a local refusal" 0 "$(merges)"
mc --merge 156 --force >/dev/null
t_eq "--force still merges over a local refusal" 1 "$(merges)"
t_has "…and records the override" "$(glog)" 'Merged over a merge-check refusal'

t_section "local gate: protection readable but requiring nothing"
prot '{"required_status_checks":null}' 0
rows2 "$GREEN" ""
t_eq "unprotected-in-effect + a declaration: the local gate passes" 0 "$(rc 156)"
t_has "…and the reason says protection requires nothing" "$(mc 156)" 'requires no status checks'

t_section "local gate: branch carries no protection rule (404, the Flow forks)"
prot 'gh: Branch not protected (HTTP 404)' 1
rows2 "$GREEN" ""
t_eq "not protected + a declaration: the local gate passes" 0 "$(rc 156)"
t_has "…and the reason says the branch is not protected" "$(mc 156)" 'branch is not protected'
rows2 "$REDROW" ""
t_eq "…and a listed check failing is still refused" 1 "$(rc 156)"
prot 'gh: Not Found (HTTP 404)' 1
rows2 "$GREEN" ""
t_hasnt "any other 404 is not read as unprotected" "$(mc 156)" 'gate: local'

t_section "GitHub protection, when readable and requiring checks, stays the gate"
prot "$PROTECTED" 0
rows "$GREEN"
t_has "the gate line says GitHub branch protection" "$(mc 156)" 'gate: GitHub branch protection'
t_hasnt "…and not local" "$(mc 156)" 'gate: local'
t_hasnt "a file agreeing with GitHub draws no warning" "$(mc 156)" 'disagrees'
prot '{"required_status_checks":{"contexts":["Check PR title, branch, and linked issue","CI gate"]}}' 0
printf 'VytCepas/harbor\tCheck PR title, branch, and linked issue\nVytCepas/harbor\tCI gate\n' > "$RCF"
t_hasnt "a context containing commas is compared whole, not split" "$(mc 156)" 'disagrees'
prot "$PROTECTED" 0
decl "conventions linter"
t_has "a file that disagrees with GitHub warns" "$(mc 156)" 'disagrees with branch protection'
t_eq "…and GitHub's verdict still decides (green)" 0 "$(rc 156)"
rows "$REDROW"
t_eq "…and (red)" 1 "$(rc 156)"
rows2 "$GREEN" ""; decl "security-floor suite"
t_eq "listed checks passing never overrides a refusal GitHub's rule gives" 1 "$(rc 156)"

t_section "a required context that never reported is refused (harbor#1073)"
prot "$PROTECTED" 0
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1" "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1"
t_eq "GitHub gate: one required context absent, the rest green, is refused" 1 "$(rc 156)"
t_has "...and names the one that never reported" "$(mc 156)" 'security-floor suite'
t_has "...as never reported" "$(mc 156)" 'never reported'
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1
security-floor suite${TAB}skipping${TAB}0${TAB}https://x/run/2" "$GREEN"
t_eq "GitHub gate: a skipped required context still passes, as GitHub scores it" 0 "$(rc 156)"
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1" "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1"
t_eq "--required-only does not hide the absent context" 1 "$(rc 156 --required-only)"

t_section "neither gate: today's refusal"
prot "$P403" 1
rm -f "$RCF"
rows2 "$GREEN" ""
t_eq "403 and no file: refused as before" 1 "$(rc 156)"
t_has "…with today's reason" "$(mc 156)" 'nothing gates this merge'
t_hasnt "…and no local gate line" "$(mc 156)" 'gate: local'
printf 'VytCepas/other\tCI gate\n' > "$RCF"
t_eq "403 and a file with rows only for other repos: refused" 1 "$(rc 156)"
printf '# a comment\n\nVytCepas/other\tCI gate\n' > "$RCF"
t_eq "comments and blanks in the file are ignored" 1 "$(rc 156)"
rm -f "$RCF"; prot "$PROTECTED" 0

t_section "--protection: is the gate still there"
prot '{"required_status_checks":{"contexts":["conventions linter"],"strict":true}}' 0
t_eq "a branch with required contexts is fine" 0 "$(rc --protection)"
t_has "it names the required contexts" "$(mc --protection)" 'conventions linter'
prot '{"required_status_checks":null}' 0
t_eq "protected but requiring nothing is a problem" 1 "$(rc --protection)"
prot 'HTTP 403: Upgrade to GitHub Pro or make this repository public' 1
t_eq "a 403 means the gate is gone" 1 "$(rc --protection)"
t_has "the lapse says PROTECTION GONE" "$(mc --protection)" 'PROTECTION GONE'
prot 'gh: Resource not accessible by integration (HTTP 403)' 1
t_eq "an App 403 is still not a pass" 1 "$(rc --protection)"
t_has "…but says unreadable by this identity" "$(mc --protection)" 'unreadable by this identity (a GitHub App token)'
t_hasnt "…and not PROTECTION GONE" "$(mc --protection)" 'PROTECTION GONE'
prot 'HTTP 404: Branch not protected' 1
t_eq "an unprotected branch is a problem" 1 "$(rc --protection)"
t_has "the 404 says PROTECTION ABSENT" "$(mc --protection)" 'PROTECTION ABSENT'
prot 'dial tcp: lookup api.github.com: no such host' 1
t_eq "an unreadable endpoint is not protected" 1 "$(rc --protection)"
t_has "the unreadable case says PROTECTION UNKNOWN" "$(mc --protection)" 'PROTECTION UNKNOWN'

t_section "passthrough to gh pr merge"
rows "$GREEN"; prot "$PROTECTED" 0
mc --merge 156 --subject "Merge harbor#156: CI-4 — session worktrees (#150)" --delete-branch >/dev/null
t_has "--subject reaches gh" "$(glog)" '--subject Merge harbor#156'
t_has "--delete-branch reaches gh" "$(glog)" '--delete-branch'
SHA40=0123456789abcdef0123456789abcdef01234567
mc --merge 156 --match-head-commit $SHA40 >/dev/null
t_has "--match-head-commit reaches gh with its sha (harbor#1060)" "$(glog)" "--match-head-commit $SHA40"
mc --merge 156 >/dev/null
t_hasnt "without it, gh is not given one" "$(glog)" 'match-head-commit'

t_section "the strategy is a choice (harbor#267)"
mc --merge 156 >/dev/null;                t_has "the default is a merge commit" "$(glog)" '--merge'
mc --merge 156 --squash >/dev/null;       t_has "--squash reaches gh" "$(glog)" '--squash'
t_hasnt "--squash replaces --merge; gh rejects two" "$(glog)" '--merge '
mc --merge 156 --rebase >/dev/null;       t_has "--rebase reaches gh" "$(glog)" '--rebase'
mc --merge 156 --merge-commit >/dev/null; t_has "--merge-commit selects a merge commit" "$(glog)" '--merge'
t_eq "two conflicting strategies are refused" 2 "$(rc --merge 156 --squash --rebase)"
mc --merge 156 --squash --squash >/dev/null; t_has "the same strategy twice is accepted" "$(glog)" '--squash'

t_section "an override that cannot be recorded is refused (PR #270)"
rows "$REDROW"
t_eq "--force --rebase is refused" 2 "$(rc --merge 156 --force --rebase)"
t_hasnt "gh is not invoked for a forced rebase" "$(glog)" '--rebase'
mc --merge 156 --force --squash >/dev/null
t_has "a forced squash keeps the override note" "$(glog)" '--body'
t_has "a forced squash uses the squash strategy" "$(glog)" '--squash'
rows "$GREEN"; mc --merge 156 --rebase >/dev/null
t_has "an unforced green rebase goes through" "$(glog)" '--rebase'
t_eq "--subject with no value is a usage error" 2 "$(rc --merge 156 --subject)"
t_eq "--match-head-commit with no value is a usage error" 2 "$(rc --merge 156 --match-head-commit)"
t_eq "an empty --match-head-commit is a usage error, never a dropped pin" 2 "$(rc --merge 156 --match-head-commit '')"
t_eq "a short sha is refused" 2 "$(rc --merge 156 --match-head-commit abc123def)"
t_eq "a non-hex 40 is refused" 2 "$(rc --merge 156 --match-head-commit zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz)"
t_eq "an upper-case sha is refused (gh reports lower case)" 2 "$(rc --merge 156 --match-head-commit 0123456789ABCDEF0123456789ABCDEF01234567)"

t_section "usage"
t_eq "no arguments prints usage" 0 "$(rc)"
t_eq "an unknown flag" 2 "$(rc --nonesuch)"
t_eq "a non-numeric PR" 2 "$(rc not-a-number)"

t_section "HARBOR_REPO is owner/name here, a PATH in renew-check"
mcenv() { _v="$1"; shift; : > "$LOG"; PATH="$STUB:$PATH" HARBOR_REPO="$_v" sh "$MC" "$@" 2>&1; }
OUT="$(mcenv "$HOME/port/harbor" --protection)"
t_has "a path is named as the wrong kind of value" "$OUT" 'not owner/name'
t_hasnt "a path never reads PROTECTION ABSENT" "$OUT" 'PROTECTION ABSENT'
t_eq "it refuses before querying the API" 0 "$(grep -c '^api repos' "$LOG")"
t_eq "a path exits 2" 2 "$(mcenv "$HOME/port/harbor" --protection >/dev/null; echo $?)"
t_has "a slashless value is refused" "$(mcenv harbor --protection)" 'not owner/name'
t_has "a three-segment value is refused" "$(mcenv a/b/c --protection)" 'not owner/name'
t_has "the documented owner/name still works" "$(mcenv VytCepas/harbor --protection)" 'protected'
t_eq "the documented value exits 0" 0 "$(mcenv VytCepas/harbor --protection >/dev/null; echo $?)"
t_section "local gate: the private layer's rows join core's when run from a checkout (harbor#1149)"
# A checkout-shaped tree, the composer beside merge-check, whose core list names harbor only; the layer lists another repo.
CK="$T_TMP/ck"; PV="$T_TMP/pv"; mkdir -p "$CK/bin" "$CK/contracts" "$PV"
cp "$T_ROOT/bin/gate-merge-check.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/gate-required-generate.sh" "$CK/bin/"
printf 'acme/harbor\tconventions linter\n' > "$CK/contracts/required-checks.tsv"
mcck() { _r="$1"; shift; : > "$LOG"; PATH="$STUB:$PATH" HARBOR_REPO="$_r" HARBOR_SCOPE_PRIVATE="$PV" sh "$CK/bin/gate-merge-check.sh" "$@" 2>&1; }
rcck() { mcck "$@" >/dev/null; echo $?; }
prot "$P403" 1
rows2 "$GREEN" ""
printf 'acme/other\tconventions linter\nacme/other\tsecurity-floor suite\n' > "$PV/required-checks.tsv"
t_eq "a repo only the layer lists, its checks passing: the local gate passes" 0 "$(rcck acme/other 156)"
t_has "...on the local gate, counting both listed checks" "$(mcck acme/other 156)" '2 of them required'
rows2 "$REDROW" ""
t_eq "...a listed check failing: refused" 1 "$(rcck acme/other 156)"
rows2 "conventions linter${TAB}pass${TAB}55s${TAB}https://x/run/1" ""
t_eq "...a layer row that never reported: refused" 1 "$(rcck acme/other 156)"
rows2 "$GREEN" ""
t_eq "core's own repo is unchanged by the layer" 0 "$(rcck acme/harbor 156)"
rm -f "$PV/required-checks.tsv"
t_eq "no layer: the repo has no row, so no local gate, so refused" 1 "$(rcck acme/other 156)"
t_has "...saying nothing gates it" "$(mcck acme/other 156)" 'nothing gates this merge'
printf 'acme/other conventions linter\n' > "$PV/required-checks.tsv"
t_eq "a layer that does not compose: the repo it names is refused, not waved through" 1 "$(rcck acme/other 156)"
t_has "...and the warning names the layer" "$(mcck acme/other 156)" "required-checks.tsv does not compose"
t_eq "...while core's own repo still passes on core's rows" 0 "$(rcck acme/harbor 156)"
rm -f "$PV/required-checks.tsv"; mkdir -p "$PV/required-checks.tsv"
t_eq "a layer file that exists and is not a file: the repo it would name is refused, not waved through" 1 "$(rcck acme/other 156)"
t_has "...and the warning names the layer" "$(mcck acme/other 156)" "required-checks.tsv does not compose"
rmdir "$PV/required-checks.tsv"

t_done
