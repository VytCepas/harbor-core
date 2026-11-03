#!/usr/bin/env sh
# status-plan-generate.sh (harbor#117) — which plan tickets are DONE, derived and not stated.
#   sh bin/status-plan-generate.sh            write docs/generated/plan.md
#   sh bin/status-plan-generate.sh --check    exit 1 if docs/generated/plan.md is stale (lint T1c)
#   sh bin/status-plan-generate.sh --summary  the three counts, nothing else
#
# Why (harbor#117): the prose plan and the repo disagreed on which tickets were built, so each ticket
# declares its own falsifier and this tool evaluates it, e.g.
#     - Evidence: bin/memory.sh
#     - Evidence: cmd: sh bin/deploy-doctor.sh --json
# A path is tested for existence; a `cmd:` is run and judged by exit status. No Evidence line is
# UNDECLARED (unfalsifiable), neither done nor open. "DONE" written in a ticket is never read.
# Removed notes: docs/explanation/code-cases/bin-status-plan-generate.md
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# --summary prints the counts on stdout as data (lint T1c reads it), so the run log is on stderr throughout.
LOG_FD=2
. "$ROOT/bin/library-log.sh"
log_init plan-status

MODE=write
case "${1:-}" in
  --check)   MODE=check ;;
  --summary) MODE=summary ;;
  '')        ;;
  *)         log_fail "unknown flag $1"; log_fix "sh $0 --help"; log_end || :; exit 2 ;;
esac

SRC="${HARBOR_STATUS_PLAN_SRC:-$ROOT/docs/reports/platform-build-tickets.md}"
OUT="${HARBOR_STATUS_PLAN_OUT:-$ROOT/docs/generated/plan.md}"
if [ ! -f "$SRC" ]; then
  log_fail "no plan at ${SRC#$ROOT/}"
  log_fix "git -C $ROOT checkout -- ${SRC#$ROOT/}"
  log_end || :; exit 1
fi
log_head "$MODE"

TMP="${TMPDIR:-/tmp}/harbor-plan.$$"
trap 'rm -f "$TMP" "$TMP.rows"' EXIT INT TERM HUP

# parse: one row per ticket (`**<ID> · <title>**`) with its Evidence line; sane() strips the pipes
# and backticks that would break the emitted table.
awk '
  function sane(s) { gsub(/\|/, "/", s); gsub(/`/, "", s); return s }
  /^\*\*[A-Z]+[0-9]+[a-z]? · / {
    if (id != "") printf "%s\t%s\t%s\t%s\n", id, title, ev, void
    line = $0
    id = line; sub(/^\*\*/, "", id); sub(/ · .*/, "", id)
    title = line; sub(/^\*\*[A-Z]+[0-9]+[a-z]? · /, "", title); sub(/\*\*.*/, "", title)
    title = sane(title); ev = ""
    # VOID is read from the heading only; see the note in the loop below.
    void = (line ~ /VOID/) ? "void" : ""
    next
  }
  /^- *Evidence: */ { if (id != "" && ev == "") { e = $0; sub(/^- *Evidence: */, "", e); ev = sane(e) } }
  END { if (id != "") printf "%s\t%s\t%s\t%s\n", id, title, ev, void }
' "$SRC" > "$TMP.rows"

done_n=0; open_n=0; undecl_n=0; host_n=0; void_n=0
: > "$TMP"
while IFS='	' read -r id title ev void; do
  [ -n "$id" ] || continue
  # VOID beats evidence and is the one thing read from prose. Cancelled is a decision, not a fact
  # about artifacts: a voided ticket whose path happens to exist (M4, M12) was reported DONE.
  # Only the heading line counts, so a body that merely discusses voiding cannot cancel a ticket.
  if [ -n "$void" ]; then
    void_n=$(( void_n + 1 ))
    printf '%s\tVOID\t%s\t%s\n' "$id" "$title" "cancelled by owner decision — not built, not open" >> "$TMP"
    continue
  fi
  case "$ev" in
    '')      st=UNDECLARED; undecl_n=$(( undecl_n + 1 )); detail='no Evidence line — unfalsifiable' ;;
    # host: evidence is named, never evaluated. docs/generated/plan.md is committed and must read the
    # same on every machine; a falsifier outside this repo would redden T1c on every clone.
    host:*)  st='HOST-DEPENDENT'; host_n=$(( host_n + 1 ))
             detail="${ev#host:} — outside this repo; ask the box, not this file" ;;
    cmd:*)   c="${ev#cmd:}"
             # A command is run, not pattern-matched: only its exit status is read. Keep it static and cheap
             # (`test -f`, a grep), never a suite: the pre-commit hook lints the staged snapshot, where a suite
             # resolves differently, so a falsifier that depends on where it runs makes T1c call its output stale.
             if ( cd "$ROOT" && eval "$c" ) >/dev/null 2>&1; then
               st=DONE; done_n=$(( done_n + 1 )); detail="cmd: $c"
             else
               st=OPEN; open_n=$(( open_n + 1 )); detail="cmd: $c"
             fi ;;
    *)       if [ -e "$ROOT/$ev" ] || [ -e "$ev" ]; then
               st=DONE; done_n=$(( done_n + 1 )); detail="$ev"
             else
               st=OPEN; open_n=$(( open_n + 1 )); detail="$ev — not present"
             fi ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$id" "$st" "$title" "$detail" >> "$TMP"
done < "$TMP.rows"

total=$(( done_n + open_n + undecl_n + host_n + void_n ))

if [ "$MODE" = summary ]; then
  printf 'plan: %s done, %s open, %s UNDECLARED, %s host-dependent, %s void, of %s ticket(s)\n' \
    "$done_n" "$open_n" "$undecl_n" "$host_n" "$void_n" "$total"
  log_ok "counted $total ticket(s) in ${SRC#$ROOT/}"
  log_end; exit $?
fi

emit() {
  printf -- '---\nkind: generated-doc\nowner: harbor#117\nstatus: generated\nsource: sh bin/status-plan-generate.sh\n---\n'
  printf '<!-- generated-by: sh bin/status-plan-generate.sh -->\n'
  printf '# PLAN — generated, do not edit\n\n'
  printf 'Which plan ticket is built, DERIVED from each ticket own falsifier rather\n'
  printf 'than from a checkbox. Regenerate with `sh bin/status-plan-generate.sh`; lint rule\n'
  printf '**T1c** fails when this file is stale.\n\n'
  printf 'Asked three ways on 2026-08-21, the prose plan gave three different answers\n'
  printf 'and the repo contradicted all of them. So nothing here reads the word "DONE"\n'
  printf 'in a ticket. A ticket is DONE when the artifact it names exists, or the\n'
  printf 'command it names exits zero, and UNDECLARED when it names neither.\n\n'
  printf '**UNDECLARED is the number that matters.** It is not "unknown" — it is\n'
  printf 'unfalsifiable: a ticket nobody can prove finished. Driving it to zero is\n'
  printf 'what makes "is Harbor done?" a question with an answer.\n\n'
  printf '| | |\n|---|---|\n'
  printf '| tickets | %s |\n| DONE | %s |\n| OPEN | %s |\n| UNDECLARED | %s |\n| host-dependent | %s |\n| VOID | %s |\n\n' \
    "$total" "$done_n" "$open_n" "$undecl_n" "$host_n" "$void_n"
  printf '## Every ticket\n\n| Ticket | State | What it is | Evidence |\n|---|---|---|---|\n'
  while IFS='	' read -r id st title detail; do
    printf '| `%s` | %s | %s | %s |\n' "$id" "$st" "$title" "$detail"
  done < "$TMP"
  printf '\n_Owner: **harbor#117**. Add an `- Evidence:` line to a ticket to make it\n'
  printf 'checkable — a path, or `cmd: <command>` judged purely by exit status._\n'
}

if [ "$MODE" = check ]; then
  emit > "$TMP.gen"
  if [ ! -f "$OUT" ] || ! diff -q "$TMP.gen" "$OUT" >/dev/null 2>&1; then
    log_fail "${OUT#$ROOT/} is stale"
    log_fix "sh $0"
    diff "$OUT" "$TMP.gen" 2>/dev/null | head -6 | while IFS= read -r _dl; do log_note "diff: $_dl"; done || true
    rm -f "$TMP.gen"; log_end || :; exit 1
  fi
  rm -f "$TMP.gen"
  log_ok "${OUT#$ROOT/} is current"
  log_end; exit $?
fi

emit > "$OUT"
log_ok "wrote ${OUT#$ROOT/} — $done_n done, $open_n open, $undecl_n UNDECLARED, $host_n host-dependent, $void_n void, of $total"
log_end; exit $?
