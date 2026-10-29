#!/usr/bin/env sh
# status-plan-generate.sh (harbor#117) — which plan tickets are DONE, derived and not stated.
#   sh bin/status-plan-generate.sh            write docs/generated/plan.md
#   sh bin/status-plan-generate.sh --check    exit 1 if docs/generated/plan.md is stale (lint T1c)
#   sh bin/status-plan-generate.sh --summary  the three counts, nothing else
#
# WHY THIS EXISTS. Harbor could state every COUNT about itself (docs/generated/status.md, lint
# T1/T2) and could not state which of its own PLAN was built. Asked on
# 2026-08-21, three methods gave three answers: parsing docs/reports/platform-build-tickets.md
# for "DONE" said B1-B6, L3, M5, M8, M9 were open; parsing each ticket's whole
# block said the same; probing for the artifacts said every one of them exists.
# The prose and the repo disagreed and the prose lost. That is harbor#117 —
# "a workstream tracked only in prose … stale checkboxes" — and it means nobody,
# including the tool writing this, could say when Harbor is finished.
#
# THE MECHANISM IS THE TICKET'S OWN FALSIFIER, NOT A SECOND LIST. A registry
# mapping ids to artifacts would be a copy of the plan and would drift against it
# exactly the way the checkboxes did (T2). Instead each ticket declares, in its
# own block, what would prove it shipped:
#
#     - Evidence: bin/memory.sh
#     - Evidence: cmd: sh bin/deploy-doctor.sh --json
#
# and this tool EVALUATES that. A path is tested for existence; a `cmd:` is run
# and judged by exit status. The plan stays one document.
#
# UNDECLARED IS ITS OWN STATE, and that is the point rather than an omission. A
# ticket with no Evidence line is neither done nor open — it is unfalsifiable,
# and the count of those is the honest measure of how much of this plan is still
# prose. It starts high. Driving it to zero is the work; hiding it behind a
# default would reproduce the defect.
#
# NOTHING HERE INFERS. "DONE" written in a ticket is deliberately NOT read: that
# is the copy that was wrong. Only evidence counts.
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

SRC="${HARBOR_STATUS_PLAN_SRC:-${HARBOR_PLAN_SRC:-$ROOT/docs/reports/platform-build-tickets.md}}"
OUT="${HARBOR_STATUS_PLAN_OUT:-${HARBOR_PLAN_OUT:-$ROOT/docs/generated/plan.md}}"
if [ ! -f "$SRC" ]; then
  log_fail "no plan at ${SRC#$ROOT/}"
  log_fix "git -C $ROOT checkout -- ${SRC#$ROOT/}"
  log_end || :; exit 1
fi
log_head "$MODE"

TMP="${TMPDIR:-/tmp}/harbor-plan.$$"
trap 'rm -f "$TMP" "$TMP.rows"' EXIT INT TERM HUP

# ── parse: one row per ticket, with its Evidence line if it has one ──────────
# A ticket heading is `**<ID> · <title>** — effort <S|M|L>`; the id is what the
# rest of the estate cites, so it is the key. `sane()` strips the pipes and
# backticks that would break the emitted table.
awk '
  function sane(s) { gsub(/\|/, "/", s); gsub(/`/, "", s); return s }
  /^\*\*[A-Z]+[0-9]+[a-z]? · / {
    if (id != "") printf "%s\t%s\t%s\t%s\n", id, title, ev, void
    line = $0
    id = line; sub(/^\*\*/, "", id); sub(/ · .*/, "", id)
    title = line; sub(/^\*\*[A-Z]+[0-9]+[a-z]? · /, "", title); sub(/\*\*.*/, "", title)
    title = sane(title); ev = ""
    # VOID IS READ FROM THE HEADING, AND ONLY THE HEADING. See the note above the
    # state machine below for why this one word is trusted when "DONE" is not.
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
  # ── VOID BEATS EVIDENCE, AND IS THE ONE THING READ FROM PROSE ────────────────
  # A cancelled ticket is not open and is not built, and evidence cannot tell you
  # which. M4 (SessionHarvester) and M12 (ProposalGC) were VOIDED by the owner on
  # 2026-08-05 and this file reported both DONE, because each named a path that
  # happens to exist — `hooks/memory-harvest/memory-harvest.sh`, `bin/proposal.sh`. A reader saw
  # "shipped as specified"; what shipped was something adjacent, after the ticket
  # was closed. That is harbor#117's own defect, reappearing inside the tool built
  # to end it, so the check runs BEFORE any evidence is looked at.
  #
  # WHY "VOID" IS TRUSTED WHEN "DONE" IS NOT — the distinction is the whole
  # design, not an exception to it. DONE is a claim about the world: an artifact
  # either exists or it does not, so prose asserting it is redundant at best and
  # wrong at worst, and we probe instead. VOID is a DECISION. No artifact's
  # presence or absence can prove a ticket was cancelled — an unbuilt void ticket
  # and an unbuilt open ticket leave identical traces on disk. The owner's written
  # decision is the only possible source, so reading it is not the defect; it is
  # the only correct move.
  #
  # The discriminator is the HEADING LINE. A body that merely discusses voiding
  # something (M6's does, at length) must not silently cancel the ticket.
  if [ -n "$void" ]; then
    void_n=$(( void_n + 1 ))
    printf '%s\tVOID\t%s\t%s\n' "$id" "$title" "cancelled by owner decision — not built, not open" >> "$TMP"
    continue
  fi
  case "$ev" in
    '')      st=UNDECLARED; undecl_n=$(( undecl_n + 1 )); detail='no Evidence line — unfalsifiable' ;;
    # ── HOST-DEPENDENT EVIDENCE IS NAMED, NEVER EVALUATED ───────────────────
    # docs/generated/plan.md is committed, so it must read the same on every machine — the same
    # rule docs/generated/status.md follows, and for the same reason: a generated file whose
    # content depends on the box reddens T1c on every clone until somebody
    # regenerates it. Caught on my own first pass: L2's falsifier was a path
    # under the live config dir, which would have made this file say DONE here
    # and OPEN on a fresh checkout.
    #
    # So a ticket whose proof lives OUTSIDE this repo — another repository, or
    # machine state — declares `host:` and is reported rather than judged. It is
    # excluded from done and open because it is neither: it is a claim this file
    # cannot settle, and saying so is the honest form. `harbor status --observed`
    # is where machine truth belongs.
    host:*)  st='HOST-DEPENDENT'; host_n=$(( host_n + 1 ))
             detail="${ev#host:} — outside this repo; ask the box, not this file" ;;
    cmd:*)   c="${ev#cmd:}"
             # A COMMAND IS RUN, NOT PATTERN-MATCHED. Output is discarded and only
             # the exit status is read, so a check cannot pass by printing the
             # right words — the failure mode this whole file exists to stop.
             #
             # KEEP IT STATIC AND CHEAP: `test -f`, `test -d`, a grep. NOT a suite
             # run. My first pass declared `cmd: sh bin/marker-test.sh` for four
             # tickets and the pre-commit hook rejected the result — that hook
             # lints the STAGED SNAPSHOT, where a suite resolves differently than
             # in the working tree, so docs/generated/plan.md came out one way here and another
             # way there and T1c called its own output stale. A falsifier that
             # depends on where it runs is not a falsifier. It also made this file
             # cost minutes; it now costs milliseconds.
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
