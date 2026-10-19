#!/usr/bin/env sh
# The EVALS-DATA runners that start billed `claude -p` sessions in the background (harbor#768): a
# signal to the runner kills every session it started. Each runner runs from a copy in a temp tree,
# against a stub claude that records its pid and its child's, then hangs.
# The corpus (EVALS-DATA/) is dev-layer and not in the export: the runners are then the synthetic ones in
# fixtures/eval-runners/, whose reap.sh is a byte copy that this test holds equal to the corpus's where both exist.
. "$(dirname "$0")/../lib/core.sh"; t_init
E="$T_TMP/EVALS-DATA"; PIDS="$T_TMP/claude.pids"; export PIDS
FX="$T_ROOT/fixtures/eval-runners"; RR="$FX"; [ ! -f "$T_ROOT/EVALS-DATA/reap.sh" ] || RR="$T_ROOT/EVALS-DATA"
mkdir -p "$E" "$T_TMP/stub"
printf '#!/bin/sh\nsleep 7771 & printf "%%s\\n%%s\\n" "$$" "$!" >> "$PIDS"\nwait\n' > "$T_TMP/stub/claude"
chmod +x "$T_TMP/stub/claude"
alive() { _al=x; _ai=0; while [ -n "$_al" ] && [ "$_ai" -lt 20 ]; do  # pids in $PIDS alive after up to 2s
  _al="$(for _p in $(cat "$PIDS"); do kill -0 "$_p" 2>/dev/null && printf '%s ' "$_p"; done)"; [ -z "$_al" ] || sleep 0.1
  _ai=$((_ai + 1)); done; printf '%s' "$_al"; }
reap() { for _p in $(cat "$PIDS"); do kill -9 "$_p" 2>/dev/null; done; }  # a red run leaks nothing
live() { kill -0 "$1" 2>/dev/null || return 1; case "$(ps -o stat= -p "$1" 2>/dev/null)" in ''|*Z*) return 1 ;; esac; }  # a zombie is gone
# What each runner needs before it reaches claude, in the copy: run2's constitution is read from an
# absolute path, so the copy points it at a temp file; nokill copies an earlier run's .claude.
mkdir -p "$T_TMP/R/results_a" "$T_TMP/R/results" "$T_TMP/R/results2" "$T_TMP/R/results3" "$T_TMP/R/results4" "$T_TMP/R/nolog" "$T_TMP/R/out"
mkdir -p "$E/e10inject" "$E/e11live" "$E/e5trap" "$E/e7scale" "$E/e8dilute" "$E/e9ablate" "$E/sliced"
for _h in azimuth idea-to-live estate harbor-unify; do mkdir -p "$T_TMP/home/$_h"; done
printf 'print("p")\n' > "$T_TMP/R/getprompt.py"
# A run dir that satisfies every foreground runner: SPEC.json, PROMPT.txt and a work/ to cd into.
mkdir -p "$T_TMP/rd/work"; printf '{"prompt":"p","settings":"","cwd":"%s"}' "$T_TMP/rd/work" > "$T_TMP/rd/SPEC.json"; printf p > "$T_TMP/rd/PROMPT.txt"
mkdir -p "$E/e1real" "$E/e2add" "$E/e3scale/runs/MANY-N120-1/.claude" "$E/e3scale/runs/BOOK-N120-1/.claude" "$E/e12rule9"
printf 'a\nb\nc\nd\n' > "$T_TMP/CONST.md"; : > "$E/e12rule9/CONST-PRISTINE.md"; : > "$E/e12rule9/CONST-PATCHED.md"

# <runner> <signal>: start the copy, wait for a session, signal the runner, then look.
fire() {
  : > "$PIDS"; _r="$1"; mkdir -p "$E/${_r%/*}"; cp "$_rr/reap.sh" "$E/"; cp "$_rr/$_r" "$E/$_r"
  sed -i.bak -e "s#^CONST=.*#CONST=\"$T_TMP/CONST.md\"#" -e "s#^ROOT=/private.*#ROOT=$T_TMP/R#" "$E/$_r" && rm -f "$E/$_r.bak"
  # A background job of a non-interactive shell starts with INT ignored, and a suite run under nohup with HUP
  # ignored (an ignored signal cannot be trapped, so every HUP row failed); a terminal's session has neither.
  env HOME="$T_TMP/home" PATH="$T_TMP/stub:$PATH" perl -e '$SIG{INT} = $SIG{TERM} = $SIG{HUP} = "DEFAULT"; exec @ARGV' sh "$E/$_r" "${3:-1}" > "$T_TMP/out" 2>&1 &
  _rp=$!; _wi=0; while [ "$(grep -c . "$PIDS")" -lt 2 ] && [ "$_wi" -lt 100 ]; do sleep 0.1; _wi=$((_wi + 1)); done
  sleep 0.2; kill -"$2" "$_rp"; RC=0
  # The wait is bounded (harbor#768): a lost signal is a FAILED row and a killed stub tree, never a hung suite.
  _dl="$(( ${EVAL_RUNNERS_DEADLINE:-40} * 10 ))"; _di=0
  while live "$_rp" && [ "$_di" -lt "$_dl" ]; do sleep 0.1; _di=$((_di + 1)); done
  if live "$_rp"; then
    t_fail "FAILED $_r on $2: the runner was still alive ${EVAL_RUNNERS_DEADLINE:-40}s after the signal (lost); its stub tree was killed"
    reap; kill -9 "$_rp" 2>/dev/null; RC=hung
  else
    wait "$_rp" || RC=$?
  fi
}
# <label> <runner root> <background batch runners> <foreground runners>: both signal sections, over one root.
over_runners() {
_rr="$2"; _bg="$3"; _fg="$4"
t_section "$1: a signal to a runner kills every session it started"
for _r in $_bg; do
  fire "$_r" INT
  t_eq "$_r reached a session, or the next row is vacuous" yes "$([ "$(grep -c . "$PIDS")" -ge 2 ] && echo yes || echo no)"
  t_eq "$_r: an INT kills every session it started, and each one's child" '' "$(alive)"
  t_eq "$_r exits 130 on INT" 130 "$RC"
  reap
done
for _s in TERM:143 HUP:129; do
  fire "${_bg%% *}" "${_s%:*}"
  t_eq "${_bg%% *}: a ${_s%:*} kills every session it started" '' "$(alive)"
  t_eq "${_bg%% *} exits ${_s#*:} on ${_s%:*}" "${_s#*:}" "$RC"
  reap
done

# The foreground runners (harbor#806): the session is a foreground child, so a TERM or HUP used to
# kill the runner alone. Each one now sources reap.sh and waits on the session, which a trap can interrupt.
t_section "$1: a TERM or HUP to a foreground runner kills the session it started"
for _r in $_fg; do
  case "$_r" in sliced/run_two.sh|sliced/run_four.sh) _a="$T_TMP/rd|t" ;; *) _a="$T_TMP/rd" ;; esac
  for _s in TERM:143 HUP:129; do
    fire "$_r" "${_s%:*}" "$_a"
    t_eq "$_r reached a session, or the next row is vacuous" yes "$([ "$(grep -c . "$PIDS")" -ge 2 ] && echo yes || echo no)"
    t_eq "$_r: a ${_s%:*} kills the session and its child" '' "$(alive)"
    t_eq "$_r exits ${_s#*:} on ${_s%:*}" "${_s#*:}" "$RC"
    reap
  done
done
}
over_runners "fixtures" "$FX" "batch/run.sh" "fg/run_one.sh"
if [ "$RR" != "$FX" ]; then
  t_exit "fixtures/eval-runners/reap.sh is the corpus's reap.sh, byte for byte" 0 cmp -s "$FX/reap.sh" "$RR/reap.sh"
  over_runners "corpus" "$RR" "e1real/run.sh e1real/run2.sh e2add/run.sh e3scale/run.sh e3scale/nokill.sh \
          e12rule9/run.sh e12rule9/run-inturn.sh e12rule9/run-mid.sh e12rule9/run-disclose.sh" "e10inject/run_one.sh e11live/probe.sh e5trap/run_one.sh e7scale/run_one.sh e8dilute/run_one.sh \
          e9ablate/run_one.sh sliced/run_one.sh sliced/run_two.sh sliced/run_four.sh"
fi
# reap_wait keeps wait's contract (harbor#768): a child's status, the last of several, and a trap that runs.
t_section "reap_wait: status, several pids, and a trap that lands while it waits"
cat > "$T_TMP/rw.sh" <<'RW'
. "$1"; D="$2"
( exit 7 ) & reap_wait $!; printf 'one=%s\n' $? > "$D/one"
( sleep 1; : > "$D/late" ) & _a=$!; ( exit 3 ) & _b=$!; reap_wait $_a $_b; printf 'last=%s late=%s\n' $? "$([ -f "$D/late" ] && echo yes || echo no)" > "$D/all"
( exit 5 ) & _c=$!; ( exit 0 ) & _d=$!; reap_wait $_c $_d; printf 'tail=%s\n' $? > "$D/tail"
sleep 7772 & _s=$!; printf '%s\n' $_s > "$D/sleeper"; trap 'printf trapped > "$D/trap"; exit 143' TERM
( sleep 1; kill -TERM $$ ) & reap_wait $_s
RW
mkdir -p "$T_TMP/rw"; sh "$T_TMP/rw.sh" "$RR/reap.sh" "$T_TMP/rw" > /dev/null 2>&1 &
_bp=$!; _bi=0; while live "$_bp" && [ "$_bi" -lt 150 ]; do sleep 0.1; _bi=$((_bi + 1)); done
if live "$_bp"; then t_fail "FAILED reap_wait did not return after a TERM within 15s"; RC=hung; else wait "$_bp" || RC=$?; fi
kill -9 "$(cat "$T_TMP/rw/sleeper" 2>/dev/null)" 2>/dev/null; kill -9 "$_bp" 2>/dev/null
t_eq "reap_wait \$! returns the child's status" 'one=7' "$(cat "$T_TMP/rw/one" 2>/dev/null)"
t_eq "reap_wait on several pids waits for all and returns the last one's status" 'last=3 late=yes' "$(cat "$T_TMP/rw/all" 2>/dev/null)"
t_eq "reap_wait returns the LAST pid's status, as wait a b does (an earlier failure does not stick)" 'tail=0' "$(cat "$T_TMP/rw/tail" 2>/dev/null)"
t_eq "a TERM during reap_wait runs the trap" trapped "$(cat "$T_TMP/rw/trap" 2>/dev/null)"
t_eq "the trap's exit status survives reap_wait" 143 "$RC"
# The slices are the property reap_wait adds: a trap already pending when the wait starts runs within about a second.
# A plain `wait` on the pid is the pre-fix behaviour, so count the slice sleeps through a PATH stub (harbor#768).
mkdir -p "$T_TMP/sl/bin"
printf '#!/bin/sh\nprintf x >> "$SLICE_LOG"\nexec /bin/sleep "$@"\n' > "$T_TMP/sl/bin/sleep"; chmod +x "$T_TMP/sl/bin/sleep"
cat > "$T_TMP/sl/run.sh" <<'SL'
. "$1"; /bin/sleep 3 & reap_wait $!
SL
: > "$T_TMP/sl/log"; SLICE_LOG="$T_TMP/sl/log" PATH="$T_TMP/sl/bin:$PATH" sh "$T_TMP/sl/run.sh" "$RR/reap.sh" > /dev/null 2>&1
t_eq "reap_wait waits in one-second slices (a 3 s child took 2 or more)" yes "$([ "$(wc -c < "$T_TMP/sl/log")" -ge 2 ] && echo yes || echo no)"
# Under set -eu a batch runner must go on to the next batch when an arm fails, as the bare wait it replaced did.
cat > "$T_TMP/sl/eu.sh" <<'EU'
set -eu
. "$1"
run_one() { [ "$1" != B ] || return 4; sleep 0.2; }
for _b in 1 2 3; do
  _wp=""; for _a in A B; do run_one "$_a" & _wp="$_wp $!"; done
  reap_wait $_wp || :
  printf 'batch %s done\n' "$_b"
done
EU
t_eq "a set -eu batch runner with a failing arm still completes every batch" 'batch 1 done batch 2 done batch 3 done' \
  "$(sh "$T_TMP/sl/eu.sh" "$RR/reap.sh" 2>&1 | tr '\n' ' ' | sed 's/ $//')"
# The runners that source reap.sh must wait through it: a bare `wait` brings the starved-trap hang back, and a reap_wait with no pids waits for nothing.
t_section "every runner that sources reap.sh waits through reap_wait"
_rn=0; _bare=""; _noor=""
for _sr in "$FX" $([ "$RR" = "$FX" ] || echo "$RR"); do   # the fixtures always, the corpus where it is shipped
  for _f in $(cd "$_sr" && grep -l 'reap\.sh' */*.sh); do
    _rn=$((_rn + 1)); _bare="$_bare$(grep -nE '(^[[:space:]]*|[;&(|{][[:space:]]*|(do|then|else)[[:space:]]+)(wait([[:space:]]|;|$)|reap_wait[[:space:]]*($|[;&)}]))' "$_sr/$_f" | sed "s#^#$_f:#")"
    _noor="$_noor$(grep -nE 'reap_wait[[:space:]]+[$]_wp' "$_sr/$_f" | grep -v '|| :' | sed "s#^#$_f:#")"
  done
done
t_eq "the scan reached the runners, or the next row is vacuous" yes "$([ "$_rn" -ge "$([ "$RR" = "$FX" ] && echo 2 || echo 17)" ] && echo yes || echo no)"
t_eq "no runner calls wait, or reap_wait without the pids it waits for" '' "$_bare"
t_eq "every batch reap_wait carries || : (set -e must not stop a runner at a failed arm)" '' "$_noor"
t_done
