#!/usr/bin/env sh
# isa-index.sh (harbor#117 · F1) — the slug -> repo -> PR -> ADR pointer table.
#
#   sh bin/isa-index.sh            write build/isa-index.md (gitignored)
#   sh bin/isa-index.sh --summary  the counts, nothing else
#
# WHAT F1 OWES, AFTER THE 2026-07-26 REWRITE. Not a new ISA format: the full
# fourteen-section skill is vendored and installed, and the original F1 proposed
# replacing it with a four-section version — a downgrade caught only because
# three documents disagreed about one live asset. What is left is the part
# upstream has no equivalent of: an index of ISA runs that points AT repo-local
# sources instead of copying them, and the decision about where a run's ledger
# lives now that the Log is the storage layer. That decision is
# CONTRACTS/isa-ledger.md; this is its mechanism.
#
# THE OUTPUT IS NOT COMMITTED, AND THAT IS THE WHOLE DESIGN. Its input is
# ~/.claude/MEMORY/WORK — machine state. A generated file in git whose content
# depends on the box reddens its own staleness lint on every clone, and this
# repo has already paid for that shape once: PLAN.md's first L2 declaration
# pointed under the live config dir and would have read DONE here and OPEN on a
# fresh checkout. status-gen.sh settled the pattern — STATUS.md is committed and
# repo-derived, build/observed.md is machine state and gitignored. An ISA index
# is entirely machine state, so all of it goes to build/.
#
# BY REFERENCE, NEVER BY COPY. Every cell is a slug, a path or an id. Copying an
# ISA's content here would make this a second store that drifts against the
# first, which is the defect DOCTRINE/doc-truth.md exists to prevent — and an ISA
# is a living document whose whole value is that one copy moves.
#
# LC_ALL=C ON EVERY SORT. A generated file whose row order depends on the
# operator's locale diffs against itself between machines, and BSD sort aborts
# outright on an illegal byte sequence in the default locale — both already
# measured on this box.
#
# EMPTY IS A RESULT, NOT A FAILURE. Zero ISA runs exist on this box (measured
# 2026-08-22). An index that refused to run until it had rows would be one
# nobody could test before the first run, and the first run is exactly when a
# silent bug costs something.
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/log-lib.sh"
log_init isa-index

MODE=write
case "${1:-}" in
  --summary) MODE=summary ;;
  '')        ;;
  *)         log_fail "unknown flag $1"; log_fix "sh bin/isa-index.sh --help"; log_end || :; exit 2 ;;
esac

CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STORE="${HARBOR_ISA_STORE:-$CFG_DIR/MEMORY/WORK}"
OUT="${HARBOR_ISA_OUT:-$ROOT/build/isa-index.md}"

fm() { # <file> <key> -> the frontmatter value, or empty
  awk -v k="$2" '
    NR==1 && $0 != "---" { exit }
    NR>1 && $0 == "---"  { exit }
    { if (index($0, k ":") == 1) { v = substr($0, length(k) + 2); gsub(/^[ \t"]+|[ \t"]+$/, "", v); print v; exit } }
  ' "$1"
}

TMP="${TMPDIR:-/tmp}/harbor-isa-index.$$"
trap 'rm -f "$TMP"' EXIT INT TERM HUP
: > "$TMP"
n=0

# THE LOG IS A SIBLING, NOT A PARENT. Harbor's G2 work-log owns
# MEMORY/WORK/sessions/<host>/, and the ISA skill's unmodified contract puts a
# run at MEMORY/WORK/<slug>/ISA.md. They share a directory and are disjoint
# because one reserves `sessions` — CONTRACTS/isa-ledger.md is where that is
# decided rather than assumed. Requiring ISA.md is what enforces it: a session
# directory has none.
if [ -d "$STORE" ]; then
  for d in "$STORE"/*/; do
    f="${d%/}/ISA.md"
    [ -f "$f" ] || continue
    slug="$(fm "$f" slug)"; [ -n "$slug" ] || slug="$(basename "$d")"
    proj="$(fm "$f" project)"; [ -n "$proj" ] || proj='—'
    phase="$(fm "$f" phase)"; [ -n "$phase" ] || phase='—'
    prog="$(fm "$f" progress)"; [ -n "$prog" ] || prog='—'

    # REPO-LOCAL REFERENCES, EXTRACTED FROM THE ISA'S OWN BODY. An issue or PR
    # is `<repo>#<n>` or `<org>/<repo>#<n>`; an ADR is the `adr-NNN-*` filename
    # convention this fleet
    # already uses. Nothing is inferred from the slug — a reference the ISA does
    # not make is not one this index may invent.
    refs="$(grep -ohE '[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)?#[0-9]+|adr-[0-9]{3}[a-z0-9-]*' "$f" 2>/dev/null \
            | LC_ALL=C sort -u | tr '\n' ' ' | sed 's/ $//')"
    [ -n "$refs" ] || refs='—'

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$proj" "$phase" "$prog" "$refs" "${f#"$CFG_DIR"/}" >> "$TMP"
    n=$(( n + 1 ))
  done
fi

if [ "$MODE" = summary ]; then
  log_ok "$n ISA run(s) in ${STORE#"$HOME"/}"
  log_end; exit $?
fi

mkdir -p "$(dirname "$OUT")"
{
  printf '# ISA INDEX — generated, machine state, NOT tracked\n\n'
  printf 'The `slug -> repo -> PR -> ADR` pointer table F1 owes. Regenerate with\n'
  printf '`sh bin/isa-index.sh`. Where a run lives, and why this is not committed,\n'
  printf 'is [CONTRACTS/isa-ledger.md](../CONTRACTS/isa-ledger.md).\n\n'
  printf 'Every cell is a pointer — a slug, a path, an id. Nothing here is a copy of\n'
  printf 'an ISA body: one copy of a living document is the point.\n\n'
  printf '| | |\n|---|---|\n| store | `%s` |\n| ISA runs | %s |\n\n' "${STORE#"$HOME"/}" "$n"
  if [ "$n" -eq 0 ]; then
    printf '_No ISA runs on this box. Empty is a result, not a failure — the skill is\n'
    printf 'installed and invoked-only, so a run happens when somebody asks for one._\n'
  else
    printf '| Slug | Project | Phase | Progress | Repo-local references | Path |\n'
    printf '|---|---|---|---|---|---|\n'
    LC_ALL=C sort "$TMP" | while IFS='	' read -r slug proj phase prog refs path; do
      printf '| `%s` | %s | %s | %s | %s | `%s` |\n' "$slug" "$proj" "$phase" "$prog" "$refs" "$path"
    done
  fi
} > "$OUT"

log_ok "wrote ${OUT#"$ROOT"/} — $n ISA run(s)"
log_end
