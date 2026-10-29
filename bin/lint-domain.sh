#!/usr/bin/env sh
# lint-domain.sh (harbor#1274, harbor#1149) - the ratchet on workload knowledge in core: core files that name a workload tool.
#
#   sh lint-domain.sh --count    the number of hits: (file, term) pairs, not occurrences
#   sh lint-domain.sh --list     each hit as file TAB term-id
#   sh lint-domain.sh --check    red if the count is above contracts/lint-domain-baseline.txt;
#                                   green but says to lower the baseline when it is below
#   sh lint-domain.sh --zero     red on any hit: the export gate once harbor#1273 has emptied it (--repos: no registry is red too)
#   sh lint-domain.sh --repos <mode>   the same over workload repo names (harbor#1273), its own baseline and allow list
#
# Terms: contracts/domain-terms.tsv (id TAB pattern TAB note), each pattern an ERE matched case-insensitively as a whole
# word. Allowed: contracts/domain-allow.tsv (path TAB term TAB reason), harbor logic that must name a tool; path is a file
# or a dir/ prefix, term an id or *, and the reason is required. Scope: every tracked file, plus untracked ones git does
# not ignore, whose layer is core (bin/scope-layers.sh --core), minus the two registers. Workload repo ids are not in the
# register, since core cannot list them without naming them: --repos reads them from the private project registry
# (Harbor's own repos excluded) and matches each only where it reads as a repo (~/<id>, <id>/..., `<id>`, <id>#N,
# "<id> repo"), because several are English words too. With no registry, --repos judges nothing and says so.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
TERMS="${DOMAIN_TERMS:-$ROOT/contracts/domain-terms.tsv}"
ALLOW="${DOMAIN_ALLOW:-$ROOT/contracts/domain-allow.tsv}"
BASE="${DOMAIN_BASELINE:-$ROOT/contracts/lint-domain-baseline.txt}"
. "$SRC/library-log.sh"
log_init lint-domain
LOG_FD=2
TAB="$(printf '\t')"
T="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$T"' EXIT

GW=-w; REPOS=0; REG=''; WHAT="workload tool"
if [ "${1:-}" = --repos ]; then
  REPOS=1; GW=''; WHAT="workload repo"; shift
  _pvl="${HARBOR_SCOPE_PRIVATE:-${PORT_ROOT:-$HOME/port}/harbor-private}"
  _pvr="$_pvl/context-rules/user/projects.tsv"; [ -f "$_pvr" ] || _pvr="$_pvl/inject.d/box/projects.tsv"  # harbor#1010
  REG="${DOMAIN_REPO_REGISTRY:-$_pvr}"
  BASE="${DOMAIN_REPOS_BASELINE:-$ROOT/contracts/lint-domain-repos-baseline.txt}"
  ALLOW="${DOMAIN_REPOS_ALLOW:-$ROOT/contracts/domain-repos-allow.tsv}"
  # The platform's own repos (control plane, yard, fleet) are not workloads: their ids come from the registry (harbor#966).
  _pids="$(env -u HARBOR_ROOT sh "$SRC/scope-roots.sh" --platform-ids)" || { echo "lint-domain: scope-roots.sh --platform-ids failed" >&2; exit 2; }
  OWN=" $(printf '%s' "$_pids" | tr '\n' ' ') "
  TERMS="$T/repo-terms.tsv"
  { printf 'id\tpattern\tnote\n'
    [ ! -f "$REG" ] || sed 's/\r$//' "$REG" | grep -vE '^[[:space:]]*(#|$)' | cut -f1 | while read -r id; do
      case "$OWN" in *" $id "*) continue ;; esac
      case "$id" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) continue ;; esac
      printf '%s\t%s\tworkload repo\n' "$id" "(~|port|HOME|ROOT\\}?)/$id([^A-Za-z0-9_-]|\$)|(^|[^A-Za-z0-9_./-])$id(/[A-Za-z0-9_.]|#[0-9]| (repo|tree|checkout|worktree|pack)([^A-Za-z]|\$))|\`$id[\`/]|\\($id,"
    done; } > "$TERMS"
fi

rows() { # <file> → its data rows: CR stripped, comments and blanks dropped, header dropped
  [ -f "$1" ] || return 0
  sed 's/\r$//' "$1" | grep -vE '^[[:space:]]*(#|$)' | sed 1d
}

# A register that does not parse refuses the run (exit 2): a skipped row would read as "nothing to find".
valid() {
  [ -f "$TERMS" ] || { echo "lint-domain: no ${TERMS#$ROOT/}" >&2; return 2; }
  rows "$TERMS" | awk -F'\t' -v f="${TERMS#$ROOT/}" '
    NF < 2 || $1 !~ /^[a-z0-9][a-z0-9-]*$/ || $2 == "" { print "lint-domain: " f ": a row needs an id ([a-z0-9-]) and a pattern: " $0 > "/dev/stderr"; bad = 1 }
    ($1 in S) { print "lint-domain: " f ": id twice: " $1 > "/dev/stderr"; bad = 1 }
    { S[$1] = 1 } END { exit bad ? 2 : 0 }' || return 2
  rows "$ALLOW" | awk -F'\t' -v f="${ALLOW#$ROOT/}" -v tf="$TERMS" '
    BEGIN { while ((getline l < tf) > 0) { split(l, F, "\t"); I[F[1]] = 1 } }
    NF < 3 || $1 == "" || $3 == "" { print "lint-domain: " f ": a row needs a path, a term and a reason: " $0 > "/dev/stderr"; bad = 1; next }
    $2 != "*" && !($2 in I) { print "lint-domain: " f ": no such term: " $2 > "/dev/stderr"; bad = 1 }
    END { exit bad ? 2 : 0 }' || return 2
}

hits() { # file TAB term-id, one line per pair, sorted
  rows "$TERMS" | while IFS="$TAB" read -r id pat _note; do
    git -C "$ROOT" grep -I --untracked -i $GW -l -E -e "$pat" -- . 2>/dev/null | awk -v id="$id" '{ print $0 "\t" id }' || :
  done > "$T/pairs"
  cut -f1 "$T/pairs" | sort -u | HARBOR_ROOT="$ROOT" sh "$SRC/scope-layers.sh" --core > "$T/core"
  rows "$ALLOW" > "$T/allow"
  awk -F'\t' -v core="$T/core" -v allow="$T/allow" -v t="${TERMS#$ROOT/}" -v a="${ALLOW#$ROOT/}" '
    BEGIN { while ((getline l < core) > 0) C[l] = 1
            while ((getline l < allow) > 0) { n++; split(l, F, "\t"); AP[n] = F[1]; AT[n] = F[2] } }
    !($1 in C) || $1 == t || $1 == a { next }
    { for (i = 1; i <= n; i++)
        if ((AT[i] == "*" || AT[i] == $2) && (substr(AP[i], length(AP[i])) == "/" ? index($1, AP[i]) == 1 : $1 == AP[i])) next
      print }' "$T/pairs" | sort -u
}

need_git() { git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; }

case "${1:-}" in
  --count) need_git || { echo "lint-domain: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits | wc -l | tr -d ' ' ;;
  --list)  need_git || { echo "lint-domain: $ROOT is not a git checkout" >&2; exit 2; }
           valid || exit 2; hits ;;
  --check|--zero)
    if [ "$REPOS" = 1 ] && [ ! -f "$REG" ]; then
      # The export gate refuses a silent pass: no registry there means no export (harbor#1273).
      if [ "$1" = --zero ]; then
        log_fail "no project registry at ${REG#$HOME/}: workload repo names were not judged"
        log_fix "export from the box, where the private layer holds context-rules/user/projects.tsv"; log_end || :; exit 2
      fi
      log_note "no project registry at ${REG#$HOME/}: workload repo names were not judged"; log_end; exit 0
    fi
    need_git ||{ log_fail "$ROOT is not a git checkout, nothing was inspected"; log_nofix "bin/lint-domain.sh"; log_end || :; exit 2; }
    valid || { log_fail "a domain register does not parse, nothing was counted"; log_fix "correct the rows named above"; log_end || :; exit 2; }
    if [ "$1" = --zero ]; then WANT=0; else
      WANT="$(grep -vE '^[[:space:]]*(#|$)' "$BASE" 2>/dev/null | head -1 | tr -d ' ')" || WANT=""
      case "$WANT" in ''|*[!0-9]*) log_fail "no numeric baseline in ${BASE#$ROOT/}"; log_fix "write the current count (sh bin/lint-domain.sh --count) into it"; log_end || :; exit 1 ;; esac
    fi
    hits > "$T/hits"; GOT="$(wc -l < "$T/hits" | tr -d ' ')"
    if [ "$GOT" -gt "$WANT" ]; then
      log_fail "$GOT core file(s)-and-term pair(s) name a $WHAT, the limit is $WANT"
      log_fix "move the workload knowledge to its pack or the private layer (harbor#1273), or allow-list harbor logic in ${ALLOW#$ROOT/} with a reason"
      # The delta, not the census: files this branch touched that hold a hit.
      __chg="$(git -C "$ROOT" diff --name-only "$(git -C "$ROOT" merge-base HEAD origin/main 2>/dev/null || echo HEAD)" 2>/dev/null || :)"
      cut -f1 "$T/hits" | sort -u | while IFS= read -r f; do
        case "
$__chg
" in *"
$f
"*) log_note "changed and names a workload tool: $f ($(awk -F'\t' -v f="$f" '$1 == f { printf "%s%s", s, $2; s = "," }' "$T/hits"))" ;; esac
      done
    elif [ "$GOT" -lt "$WANT" ]; then
      log_ok "$GOT pair(s), under the baseline of $WANT"
      log_note "lower ${BASE#$ROOT/} to $GOT so the gain is kept"
    else
      log_ok "$GOT pair(s) naming a $WHAT, equal to the limit"
    fi
    log_end ;;
  -h|--help|help|'') sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "lint-domain: unknown argument '$1'" >&2; exit 2 ;;
esac
