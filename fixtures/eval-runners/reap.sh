# EVALS-DATA/reap.sh — sourced by every runner that starts billed `claude -p` sessions in the background
# (harbor#768). An async list ignores SIGINT, and a TERM or HUP reaches the runner alone, so a signal
# left every session running and billing. Now INT, TERM and HUP kill every descendant, then exit.
_reap() {
  _rp_f="${TMPDIR:-/tmp}"; _rp_f="${_rp_f%/}/reap.$$"; _rp_all=" $$ "; _rp_kill=""
  # ps into a file, not a pipe: a pipeline would list its own subshell as this runner's child.
  while :; do
    ps -A -o pid= -o ppid= -o comm= > "$_rp_f" 2>/dev/null || :
    _rp_new="$(awk -v all="$_rp_all" '$3 !~ /(^|\/)ps$/ && index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }' "$_rp_f")" \
      || _rp_new=""
    [ -n "$_rp_new" ] || break
    kill -STOP $_rp_new 2>/dev/null || :
    _rp_all="$_rp_all$_rp_new"; _rp_kill="$_rp_kill $_rp_new"
  done
  rm -f "$_rp_f"
  [ -z "$_rp_kill" ] || kill -9 $_rp_kill 2>/dev/null || :
}
trap '_reap; exit 130' INT
trap '_reap; exit 143' TERM
trap '_reap; exit 129' HUP

# reap_wait <pid>... — `wait` on those pids, in one-second slices so a trap that is pending runs within about a
# second instead of after the sessions end (harbor#768). Returns the last pid's status, as `wait a b` does.
# NO command substitution and NO foreground command in here: measured on macOS /bin/sh (bash 3.2), a signal
# that lands while the shell forks one is lost outright (the second Ctrl-C works), and a ps(1) liveness check
# per slice lost 6 of 720 amplified trials. kill -0 and a background sleep lose none. Callers collect the pids:
#   for a in ...; do run_one "$a" & _wp="$_wp $!"; done; reap_wait $_wp || :
# A bare `wait` returned 0 whatever the arms did; under set -e a batch caller keeps that with `|| :`.
reap_wait() {
  _rw_rc=0
  for _rw_p in "$@"; do
    while kill -0 "$_rw_p" 2>/dev/null; do sleep 1 & wait $!; done
    _rw_rc=0; wait "$_rw_p" || _rw_rc=$?
  done
  return "$_rw_rc"
}
