#!/usr/bin/env sh
# lint-dev-paths.sh (harbor#1275, harbor#1149) - the ratchet on core code that names a dev-layer path: a read or a write
# the exported core cannot satisfy, since harbor-core has no dev layer.
#
#   sh lint-dev-paths.sh --count    the number of hits: (file, dev path) pairs, not occurrences
#   sh lint-dev-paths.sh --list     each hit as file TAB dev path
#   sh lint-dev-paths.sh --check    red if the count is above CONTRACTS/lint-dev-paths-baseline.txt;
#                                      green but says to lower the baseline when it is below
#
# Dev paths: the `dev` rows of CONTRACTS/layers.tsv, never a copy. Scope: core code, i.e. tracked and untracked-not-ignored
# files whose layer is core (bin/layers.sh --core), minus documentation and data registers (.md .html .tsv .txt .json
# .jsonl .csv: a core document may NAME a dev path in code font, layers.tsv says so), on lines that are not comments
# (# or //). A path counts where no name character borders it, so PLAN.md is neither QA-PLAN.md nor PLAN.mdx. Allowed:
# CONTRACTS/dev-paths-allow.tsv (path TAB dev path or * TAB reason), the reason required.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
LAYERS="${LAYERS_FILE:-$ROOT/CONTRACTS/layers.tsv}"
ALLOW="${DEV_PATHS_ALLOW:-$ROOT/CONTRACTS/dev-paths-allow.tsv}"
BASE="${DEV_PATHS_BASELINE:-$ROOT/CONTRACTS/lint-dev-paths-baseline.txt}"
. "$SRC/log-lib.sh"
log_init lint-dev-paths
LOG_FD=2
TAB="$(printf '\t')"
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT

rows() { # <file> → its data rows: CR stripped, comments and blanks dropped, header dropped
  [ -f "$1" ] || return 0
  sed 's/\r$//' "$1" | grep -vE '^[[:space:]]*(#|$)' | sed 1d
}

devs() { rows "$LAYERS" | awk -F'\t' '$2 == "dev" && $1 != "" { print $1 }'; }

# A register that does not parse refuses the run (exit 2): a skipped row would read as "nothing to find".
valid() {
  [ -f "$LAYERS" ] || { echo "lint-dev-paths: no ${LAYERS#$ROOT/}" >&2; return 2; }
  devs > "$T/devs"
  [ -s "$T/devs" ] || { echo "lint-dev-paths: ${LAYERS#$ROOT/} has no dev row, so there is nothing to look for" >&2; return 2; }
  rows "$ALLOW" | awk -F'\t' -v f="${ALLOW#$ROOT/}" -v df="$T/devs" '
    BEGIN { while ((getline l < df) > 0) D[l] = 1 }
    NF < 3 || $1 == "" || $3 == "" { print "lint-dev-paths: " f ": a row needs a path, a dev path and a reason: " $0 > "/dev/stderr"; bad = 1; next }
    $2 != "*" && !($2 in D) { print "lint-dev-paths: " f ": not a dev row of layers.tsv: " $2 > "/dev/stderr"; bad = 1 }
    END { exit bad ? 2 : 0 }' || return 2
}

hits() { # file TAB dev path, one line per pair, sorted
  while IFS= read -r d; do
    _re="$(printf '%s' "$d" | sed 's/[].[\\*^$+?(){}|]/\\&/g')"
    # A file path ends where a name ends; a directory path already ends in its slash.
    case "$d" in */) ;; *) _re="$_re(\$|[^A-Za-z0-9_-])" ;; esac
    git -C "$ROOT" grep -I --untracked -n -E -e "(^|[^A-Za-z0-9_.-])$_re" -- . 2>/dev/null |
      awk -v d="$d" '{ f = $0; sub(/:.*/, "", f); l = $0; sub(/^[^:]*:[^:]*:/, "", l)
                       if (l ~ /^[ \t]*(#|\/\/)/) next
                       if (f ~ /\.(md|html|tsv|txt|json|jsonl|csv)$/) next
                       print f "\t" d }' || :
  done < "$T/devs" | sort -u > "$T/pairs"
  cut -f1 "$T/pairs" | sort -u | HARBOR_ROOT="$ROOT" LAYERS_FILE="$LAYERS" sh "$SRC/layers.sh" --core > "$T/core"
  rows "$ALLOW" > "$T/allow"
  awk -F'\t' -v core="$T/core" -v allow="$T/allow" '
    BEGIN { while ((getline l < core) > 0) C[l] = 1
            while ((getline l < allow) > 0) { n++; split(l, F, "\t"); AP[n] = F[1]; AT[n] = F[2] } }
    !($1 in C) { next }
    { for (i = 1; i <= n; i++)
        if ((AT[i] == "*" || AT[i] == $2) && (substr(AP[i], length(AP[i])) == "/" ? index($1, AP[i]) == 1 : $1 == AP[i])) next
      print }' "$T/pairs"
}

need_git() { git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }

case "${1:-}" in
  --count) need_git || { echo "lint-dev-paths: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits | wc -l | tr -d ' ' ;;
  --list)  need_git || { echo "lint-dev-paths: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits ;;
  --check)
    need_git || { log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-dev-paths.sh"; log_end || :; exit 2; }
    valid || { log_fail "a register does not parse, nothing was counted"; log_fix "correct the rows named above"; log_end || :; exit 2; }
    WANT="$(grep -vE '^[[:space:]]*(#|$)' "$BASE" 2>/dev/null | head -1 | tr -d ' ')" || WANT=""
    case "$WANT" in ''|*[!0-9]*) log_fail "no numeric baseline in ${BASE#$ROOT/}"; log_fix "write the current count (sh bin/lint-dev-paths.sh --count) into it"; log_end || :; exit 1 ;; esac
    hits > "$T/hits"; GOT="$(wc -l < "$T/hits" | tr -d ' ')"
    if [ "$GOT" -gt "$WANT" ]; then
      log_fail "$GOT core file(s)-and-dev-path pair(s), baseline is $WANT"
      log_fix "read the path behind a missing-is-fine check, move the data into core as a fixture, move the file to the dev layer, or allow-list it in ${ALLOW#$ROOT/} with a reason (harbor#1275)"
      # The delta, not the census: files this branch touched that hold a hit.
      __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
      cut -f1 "$T/hits" | sort -u | while IFS= read -r f; do
        case "
$__chg
" in *"
$f
"*) log_note "changed and names a dev path: $f ($(awk -F'\t' -v f="$f" '$1 == f { printf "%s%s", s, $2; s = "," }' "$T/hits"))" ;; esac
      done
    elif [ "$GOT" -lt "$WANT" ]; then
      log_ok "$GOT pair(s), under the baseline of $WANT"
      log_note "lower ${BASE#$ROOT/} to $GOT so the gain is kept"
    else
      log_ok "$GOT pair(s) of core code naming a dev path, equal to the baseline"
    fi
    log_end ;;
  -h|--help|help|'') sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-dev-paths: unknown argument '$1'" >&2; exit 2 ;;
esac
