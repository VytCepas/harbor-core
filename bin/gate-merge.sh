#!/usr/bin/env sh
# gate-merge.sh (harbor#1018) — the unattended merge: a PR whose change touches no protected path, green on its
# exact head, squash-merged at that head. A protected PR is queued for the operator instead (ship contract §4).
#
#   <cfg>/bin/gate-merge.sh <owner/repo> <pr>
#
# Runs only as the installed copy, the path its allow rule names. Refuses while <cfg>/.harbor-autoship.off exists,
# for a repo with no .agents/ship.conf on its default branch, for a red or moving head, and for a protected change:
# that one is queued and its exact approve command printed. The manifest and register are read from GitHub, never
# from a local checkout. Exit 0 merged, 1 refused (the FAIL line says why), 2 usage. There is no override.
set -eu
case "$0" in */*) HERE="${0%/*}" ;; *) HERE=. ;; esac
HERE="$(CDPATH='' cd -P -- "$HERE" && pwd -P)"
LOG_FD=2   # stdout carries only a queued approve command
. "$HERE/log-lib.sh"
. "$HERE/gate-lib.sh"
log_init gate-merge
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
[ $# -eq 2 ] && gate_repo_ok "$1" && case "$2" in ''|*[!0-9]*) false ;; esac \
  || { usage >&2; exit 2; }
gate_init gate-merge.sh
R="$1"; N="$2"
log_head "merge $R#$N"
! gate_killed || die "the kill switch $GATE_CFG/.harbor-autoship.off exists: no unattended merge" "rm $GATE_CFG/.harbor-autoship.off   # the operator, from a terminal"
gate_fetch_conf "$R"
[ -f "$GATE_ROOT/$GATE_MANIFEST" ] || die "$R has no .agents/ship.conf on $GATE_MAIN: nothing about it is unattended" "gh pr view $N -R $R   # a person merges it"
A="$(gate_pr_head "$N")"
gate_pr_paths "$A" >"$GATE_TMP/paths"
rc=0; gate_classify "$GATE_ROOT" <"$GATE_TMP/paths" >"$GATE_TMP/protected" || rc=$?
case "$rc" in
  0) log_ok "$R#$N at $A touches no protected path ($(grep -c . "$GATE_TMP/paths") path(s))" ;;
  1) while IFS="$GATE_TAB" read -r _ p c; do log_note "protected: $p ($c)"; done <"$GATE_TMP/protected"
     _first="$(head -1 "$GATE_TMP/protected" | cut -f2-3 | tr '\t' ' ')"
     gate_ledger merge-auto "$R $N $A" queued-protected
     gate_queue_add merge "$R" "$N" "$A" "protected: $_first"   # first: its note must not split FAIL from fix
     log_fail "$R#$N touches $(grep -c . "$GATE_TMP/protected") protected path(s): only the operator merges it"
     log_fix "$GATE_QCMD"; printf '%s\n' "$GATE_QCMD"
     log_end || :; exit 1 ;;
  *) die "the register of $R could not be read" "gh api repos/$R/contents/$(gate_register_path "$GATE_ROOT")" ;;
esac
gate_merge_pr "$N" "$A" merge-auto
log_end
