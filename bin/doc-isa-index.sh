#!/usr/bin/env sh
# doc-isa-index.sh (harbor#117 · F1) — the slug -> repo -> PR -> ADR pointer table.
#
#   sh bin/doc-isa-index.sh            write build/isa-index.md (gitignored)
#   sh bin/doc-isa-index.sh --summary  the counts, nothing else
#
# F1 after the 2026-07-26 rewrite: not a new ISA format (the full skill is vendored) but an index of ISA runs pointing AT repo-local
# sources, plus where a run's ledger lives (contracts/isa-ledger.md; this is its mechanism).
# The output is NOT committed: its input is ~/.claude/MEMORY/WORK, machine state, and a committed file depending on the box
# reddens its staleness lint on every clone. build/ is gitignored.
# By reference, never by copy: every cell is a slug, path or id; a copy is a second store that drifts (doc-truth.md).
# LC_ALL=C on every sort: locale-dependent order diffs between machines and BSD sort aborts on illegal byte sequences.
# Empty is a result, not a failure: zero ISA runs exist on this box (2026-08-22), and an index refusing to run on no rows cannot be tested before its first run.
# Removed notes: docs/explanation/code-cases/bin-doc-isa-index.md
set -eu

case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             exit 0 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
. "$ROOT/bin/library-log.sh"
log_init isa-index

MODE=write
case "${1:-}" in
  --summary) MODE=summary ;;
  '')        ;;
  *)         log_fail "unknown flag $1"; log_fix "sh bin/doc-isa-index.sh --help"; log_end || :; exit 2 ;;
esac

CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STORE="${HARBOR_DOC_ISA_STORE:-$CFG_DIR/MEMORY/WORK}"
OUT="${HARBOR_DOC_ISA_OUT:-$ROOT/build/isa-index.md}"

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

# The Log is a sibling, not a parent: work-log sessions live in MEMORY/WORK/sessions/<host>/ and an ISA run in
# MEMORY/WORK/<slug>/ISA.md (contracts/isa-ledger.md). Requiring ISA.md keeps them disjoint.
if [ -d "$STORE" ]; then
  for d in "$STORE"/*/; do
    f="${d%/}/ISA.md"
    [ -f "$f" ] || continue
    slug="$(fm "$f" slug)"; [ -n "$slug" ] || slug="$(basename "$d")"
    proj="$(fm "$f" project)"; [ -n "$proj" ] || proj='—'
    phase="$(fm "$f" phase)"; [ -n "$phase" ] || phase='—'
    prog="$(fm "$f" progress)"; [ -n "$prog" ] || prog='—'

    # Repo-local references are extracted from the ISA's own body (`<repo>#<n>`, `<org>/<repo>#<n>`, `adr-NNN-*`); nothing is inferred from the slug.
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
  printf '`sh bin/doc-isa-index.sh`. Where a run lives, and why this is not committed,\n'
  printf 'is [contracts/isa-ledger.md](../contracts/isa-ledger.md).\n\n'
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
