#!/usr/bin/env sh
# doc-lithuanian-rewrite.sh (harbor#1572) - Lithuanian text rewritten in plain publicist Lithuanian by a small model, kept only when nothing a
# reader pastes or counts has changed (skills/doc-lithuanian-prose).
#
#   sh doc-lithuanian-rewrite.sh [--model haiku|sonnet] [FILE]    FILE, or stdin when there is none
#
# stdout is always the text to use: the rewrite, or the original when the rewrite fails the check. stderr says which.
# Exit 0 rewritten (or already good), 3 original kept (the check failed or the model did not answer), 2 usage.
#
# The check, byte-exact as a multiset: URLs, `code` and „quoted“ spans, identifiers with _ , ALL-CAPS terms, numbers, and
# the stem of every apostrophe term (tag'ą may become tag'as, never žymė); and the same number of non-empty lines, because
# a mail body is one line per paragraph. The model runs with no tools, no setting sources (so no hooks) and no MCP.
# HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND replaces the model call (stdin text, stdout rewrite): the suite's fake model.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="$(CDPATH= cd -- "$SRC/.." && pwd)"
. "$SRC/library-log.sh"
log_init doc-lithuanian-rewrite
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2

MODEL=haiku
while [ $# -gt 0 ]; do
  case "$1" in
    --model) [ $# -ge 2 ] || { echo "usage: doc-lithuanian-rewrite.sh [--model haiku|sonnet] [FILE]" >&2; exit 2; }
             MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#--model=}"; shift ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    -*) echo "doc-lithuanian-rewrite: unknown flag $1" >&2; exit 2 ;;
    *) break ;;
  esac
done
case "$MODEL" in haiku|sonnet) ;; *) echo "doc-lithuanian-rewrite: --model is haiku or sonnet, not $MODEL" >&2; exit 2 ;; esac

T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT
if [ $# -ge 1 ]; then cat -- "$1" > "$T/in"; else cat > "$T/in"; fi
[ -s "$T/in" ] || { echo "doc-lithuanian-rewrite: no text" >&2; exit 2; }

SKILL="$ROOT/skills/doc-lithuanian-prose/SKILL.md"
[ -f "$SKILL" ] || SKILL="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/doc-lithuanian-prose/SKILL.md"
{ [ ! -f "$SKILL" ] || awk 'NR==1 && /^---$/ {f=1; next} f && /^---$/ {f=0; next} !f' "$SKILL"
  cat <<'EOF'

## Your task

Rewrite the Lithuanian text you are given so it reads as a colleague wrote it, by the rules above.

Keep exactly: the meaning and every fact; every line, in order — one output line per input line, with the same leading
labels and bullets; every URL, `code` span, „quoted“ span, identifier, number and ALL-CAPS term; every English term. A
term written with an apostrophe ending keeps its stem and apostrophe; only the ending may change to fit the grammar. Never
translate an English term into Lithuanian. Add nothing and drop nothing: no greeting, no sign-off, no comment. A line that
is already good comes back unchanged. Output the rewritten text only.
EOF
} > "$T/system"

_model() {
  if [ -n "${HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND:-}" ]; then
    sh -c "$HARBOR_DOC_LITHUANIAN_REWRITE_COMMAND" < "$T/in"
  else
    command -v claude >/dev/null 2>&1 || return 1
    claude -p --model "$MODEL" --setting-sources "" --strict-mcp-config --tools "" --no-session-persistence \
      --system-prompt-file "$T/system" < "$T/in"
  fi
}

_keep() { log_warn "kept the original: $1"; log_fix "rewrite it by hand from skills/doc-lithuanian-prose/SKILL.md"; log_end || :; cat "$T/in"; exit 3; }

_model > "$T/out" 2> "$T/err" || _keep "the $MODEL call failed ($(head -c 200 "$T/err" | tr '\n' ' '))"
[ -s "$T/out" ] || _keep "the $MODEL call returned nothing"

V="$(jq -r -n --rawfile a "$T/in" --rawfile b "$T/out" --arg q "'" '
  def toks: [ scan("https?://[^\\s)>\\]]+"), scan("`[^`]+`"), scan("„[^“]+“"), scan("[A-Za-z0-9_.]+[" + $q + "’]"),
              scan("\\b[A-Za-z0-9]*_[A-Za-z0-9_]*\\b"), scan("\\b[A-Z][A-Z0-9]+\\b"), scan("[0-9]+(?:[.,][0-9]+)*") ] | sort;
  def lines: [ split("\n")[] | select(test("\\S")) ] | length;
  ($a | toks) as $x | ($b | toks) as $y
  | if ($a | lines) != ($b | lines) then "lines \($a | lines) became \($b | lines)"
    elif $x != $y then "tokens changed: lost \(($x - $y) | unique | join(" ")), added \(($y - $x) | unique | join(" "))"
    else "ok" end' 2>/dev/null || echo "the check could not run (jq)")"

[ "$V" = ok ] || _keep "$V"
if cmp -s "$T/in" "$T/out"; then log_ok "already good, unchanged ($MODEL)"; else log_ok "rewritten by $MODEL, every protected token kept"; fi
cat "$T/out"
log_end
