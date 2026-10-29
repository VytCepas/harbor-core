#!/usr/bin/env sh
# pr-wait.sh against a stub gh: each case scripts what successive polls return (harbor#552, #675).
# A fake clock: `sleep` advances a counter and `date +%s` reads it, so the timeout arithmetic runs
# for real and no case waits in wall time.
. "$(dirname "$0")/../lib/core.sh"; t_init
PW="$T_ROOT/bin/pr-wait.sh"; T="$T_TMP/pw"; mkdir -p "$T/bin"
cat >"$T/bin/sleep" <<'EOF'
#!/bin/sh
c="$(cat "$STUB_DIR/clock" 2>/dev/null || echo 0)"
echo $((c + ${1:-0})) >"$STUB_DIR/clock"
EOF
cat >"$T/bin/date" <<'EOF'
#!/bin/sh
[ "$*" = "+%s" ] || exec /bin/date "$@"
echo $((1000000000 + $(cat "$STUB_DIR/clock" 2>/dev/null || echo 0)))
EOF
# $T/case sets THREADS_P1, THREADS_P2 (JSON node arrays), HASNEXT, REQUIRED (newline list),
# CHECKS_<n> (tab rows) per poll n, and ANNOT_<job> per check-run annotation.
cat >"$T/bin/gh" <<'EOF'
#!/bin/sh
. "$STUB_DIR/case"
n="$(cat "$STUB_DIR/poll" 2>/dev/null || echo 1)"
case "$1 $2" in
  "pr view") printf 'main\n' ;;
  "api graphql")
    case "$*" in
      *c=*) printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":%s}}}}}' "$THREADS_P2" ;;
      *)    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":%s,"endCursor":"C1"},"nodes":%s}}}}}' "$HASNEXT" "$THREADS_P1" ;;
    esac ;;
  "api repos/"*)
    case "$2" in
      */check-runs/*/annotations)
        j="${2%/annotations}"; j="${j##*/}"
        eval "printf '%b' \"\${ANNOT_$j:-}\"" ;;
      *) [ -n "$REQUIRED" ] && printf '%s\n' "$REQUIRED" || exit 1 ;;
    esac ;;
  "pr checks")
    eval "printf '%b' \"\${CHECKS_$n:-\$CHECKS_LAST}\""
    echo $((n + 1)) >"$STUB_DIR/poll" ;;
esac
EOF
chmod +x "$T/bin/sleep" "$T/bin/date" "$T/bin/gh"
OPEN='[{"isResolved":false,"path":"x.sh","comments":{"nodes":[{"author":{"login":"bot"},"body":"finding"}]}}]'
DONE='[{"isResolved":true,"path":"y.sh","comments":{"nodes":[{"author":{"login":"bot"},"body":"old"}]}}]'
NONE="THREADS_P1='[]'; THREADS_P2='[]'; HASNEXT=false"
scene() { printf '%s\n' "$1" > "$T/case"; }  # <case shell>
wait_on() { # [script] → exit code of one scripted run; output in $T/out
  rm -f "$T/poll" "$T/clock"
  STUB_DIR="$T" PATH="$T/bin:$PATH" sh "${1:-$PW}" o/r 1 --timeout 40 --interval 10 >"$T/out" 2>&1; echo $?
}
out() { cat "$T/out"; }

t_section "green needs a stable, complete set"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\npass\tsuite\n'"
t_eq "a stable all-pass set is green" 0 "$(wait_on)"
LATE="$NONE; REQUIRED=''
CHECKS_1='pass\tlint\n'; CHECKS_2='pass\tlint\nfail\tsuite\n'; CHECKS_LAST='pass\tlint\nfail\tsuite\n'"
scene "$LATE"
t_eq "a check that registers late and fails is not missed" 1 "$(wait_on)"
NEVER="$NONE; REQUIRED='suite'
CHECKS_LAST='pass\tlint\n'"
scene "$NEVER"
t_eq "a required context never seen is never green" 4 "$(wait_on)"

t_section "protection unreadable: the tracked declaration is the required set (harbor#1073)"
printf 'o/r\tsuite\n' > "$T/rc.tsv"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\n'"
t_eq "403 + a listed check never seen is never green" 4 "$(HARBOR_REQUIRED_CHECKS="$T/rc.tsv" wait_on)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\npass\tsuite\n'"
t_eq "403 + the listed check present and passing is green" 0 "$(HARBOR_REQUIRED_CHECKS="$T/rc.tsv" wait_on)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\n'"
t_eq "no declaration for this repo keeps today's behaviour" 0 "$(HARBOR_REQUIRED_CHECKS="$T/none.tsv" wait_on)"

t_section "protection unreadable: the private layer's rows join core's, run from a checkout (harbor#1149)"
PWC="$T/ck"; PV="$T/pv"; mkdir -p "$PWC/bin" "$PWC/CONTRACTS" "$PV"
cp "$T_ROOT/bin/pr-wait.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/gate-required-generate.sh" "$PWC/bin/"
printf 'o/harbor\tlint\n' > "$PWC/CONTRACTS/required-checks.tsv"
wait_ck() { rm -f "$T/poll" "$T/clock"; HARBOR_SCOPE_PRIVATE="$PV" STUB_DIR="$T" PATH="$T/bin:$PATH" sh "$PWC/bin/pr-wait.sh" o/r 1 --timeout 40 --interval 10 >"$T/out" 2>&1; echo $?; }
printf 'o/r\tsuite\n' > "$PV/required-checks.tsv"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\n'"
t_eq "a check only the layer lists, never seen: never green" 4 "$(wait_ck)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\npass\tsuite\n'"
t_eq "...present and passing: green" 0 "$(wait_ck)"
rm -f "$PV/required-checks.tsv"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\n'"
t_eq "no layer: nothing is listed for o/r, so today's behaviour" 0 "$(wait_ck)"
printf 'o/r suite\n' > "$PV/required-checks.tsv"
t_eq "a layer that does not compose is a stop, never a smaller list" 2 "$(wait_ck)"
t_has "...and says so" "$(cat "$T/out")" "does not compose"
rm -f "$PV/required-checks.tsv"; mkdir -p "$PV/required-checks.tsv"
t_eq "a layer file that exists and is not a file is a stop too, never no rows" 2 "$(wait_ck)"
rmdir "$PV/required-checks.tsv"

t_section "review threads, every page"
scene "THREADS_P1='$OPEN'; THREADS_P2='[]'; HASNEXT=false; REQUIRED=''
CHECKS_LAST='pending\tsuite\n'"
t_eq "an open thread returns before CI finishes" 3 "$(wait_on)"
PAGE2="THREADS_P1='$DONE'; THREADS_P2='$OPEN'; HASNEXT=true; REQUIRED=''
CHECKS_LAST='pass\tlint\n'"
scene "$PAGE2"
t_eq "an open thread on page two is seen" 3 "$(wait_on)"

t_section "a job no runner ever took is not a failure (harbor#675)"
LOSTMSG='The job was not acquired by Runner of type self-hosted even after multiple attempts\n'
L9='https://github.com/o/r/actions/runs/7/job/9'; L8='https://github.com/o/r/actions/runs/7/job/8'
LOST="$NONE; REQUIRED=''
CHECKS_LAST='cancel\tshard\t$L9\n'; ANNOT_9='$LOSTMSG'"
scene "$NONE; REQUIRED=''
CHECKS_LAST='pass\tlint\t\ncancel\tshard\t$L9\n'; ANNOT_9='$LOSTMSG'"
t_eq "a red check whose only annotation is 'not acquired' is lost" 5 "$(wait_on)"
t_has "a lost job prints its re-run command" "$(out)" 'gh run rerun --job 9 --repo o/r'
scene "$NONE; REQUIRED=''
CHECKS_LAST='fail\tsuite\t$L8\ncancel\tshard\t$L9\n'; ANNOT_9='$LOSTMSG'"
t_eq "a real failure beside a lost job is a failure" 1 "$(wait_on)"
t_has "…and the lost job is still named lost" "$(out)" 'lost in dispatch'
scene "$NONE; REQUIRED=''
CHECKS_LAST='cancel\tshard\t$L9\n'; ANNOT_9='Canceling since a higher priority waiting request for governance exists\n'"
t_eq "a cancel for any other reason is not lost" 1 "$(wait_on)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='fail\tshard\t$L9\n'; ANNOT_9='${LOSTMSG}Process completed with exit code 1.\n'"
t_eq "a job that ran and failed is a failure beside the lost annotation" 1 "$(wait_on)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='fail\tsuite\t$L8\n'"
t_eq "a failed step with no annotation is a failure" 1 "$(wait_on)"
BILLMSG='The job was not started because recent account payments have failed or your spending limit needs to be increased\n'
BILLED="$NONE; REQUIRED=''
CHECKS_LAST='fail\tsuite\t$L8\n'; ANNOT_8='$BILLMSG'"
scene "$BILLED"
t_eq "a check refused for billing is not a failure: exit 5" 5 "$(wait_on)"
t_has "…and says refused for billing" "$(out)" 'refused for billing'
t_has "…with the action: re-run locally, never raise the limit" "$(out)" 'do not raise the spending limit'
scene "$NONE; REQUIRED=''
CHECKS_LAST='fail\tsuite\t$L8\nfail\tshard\t$L9\n'; ANNOT_8='$BILLMSG'; ANNOT_9='Process completed with exit code 1.\n'"
t_eq "a real failure beside a billing refusal is a failure" 1 "$(wait_on)"
scene "$NONE; REQUIRED=''
CHECKS_LAST='fail\tsuite\t$L8\n'; ANNOT_8='${BILLMSG}Process completed with exit code 1.\n'"
t_eq "a job that ran, failed and was also annotated is a failure" 1 "$(wait_on)"
t_eq "ci-lost-job hands out the billing phrase for ci-runners" "spending limit|payments have failed" "$(sh "$T_ROOT/bin/ci-lost-job.sh" --billing-pattern)"
t_exit "ci-lost-job refuses a link that is not an Actions job, before any API call" 2 \
  sh "$T_ROOT/bin/ci-lost-job.sh" o/r 'https://github.com/o/r/pull/3/checks'
# Mutants run a copy from $T, which finds its helper beside itself; the unmutated copy must
# still answer 5, or M4 would pass merely because the helper was missing.
cp "$T_ROOT/bin/ci-lost-job.sh" "$T/ci-lost-job.sh"; cp "$T_ROOT/bin/log-lib.sh" "$T/log-lib.sh"; cp "$PW" "$T/mut.sh"
scene "$LOST"
t_eq "the unmutated copy in \$T answers 5" 5 "$(wait_on "$T/mut.sh")"

t_section "mutants: each fix removed, its case goes red"
mutant() { # <label> <sed expr> <case> <exit the real tool gives>
  sed "$2" "$PW" > "$T/mut.sh"
  t_exit "$1: the mutation applies" 1 cmp -s "$T/mut.sh" "$PW"
  scene "$3"
  t_eq "$1: the case fails without the fix" yes "$([ "$(wait_on "$T/mut.sh")" != "$4" ] && echo yes || echo no)"
}
mutant "M1 the two-poll stability check" 's/ && \[ "\$names" = "\$prev_names" \]//' "$LATE" 1
mutant "M2 the required-context check" 's/&& \[ -z "\$missing" \] //' "$NEVER" 4
mutant "M3 thread pagination" 's/hasNextPage\x27)" = true \] || break/hasNextPage\x27)" = never ] || break/' "$PAGE2" 3
mutant "M4 the lost-by-dispatch read (harbor#675)" \
  's/case "\$_lrc" in/case 9 in/' "$LOST" 5
mutant "M5 the billing-refusal read (harbor#1060)" \
  's/^        3) lost=/        9) lost=/' "$BILLED" 5

t_section "usage"
t_exit "no arguments" 2 sh "$PW"
t_exit "an unknown option" 2 sh "$PW" o/r 1 --bogus
t_has "--help documents the exit 2 the private layer can cause" "$(sh "$PW" --help)" "does not compose with core's"
t_done
