#!/usr/bin/env sh
# standard-render-check.sh (harbor#967 done-when 1 and 2) — does a rendered repo pass the standard it was rendered for?
#
#   sh bin/standard-render-check.sh <dir>     the three questions below over <dir>, a scaffold or any governed repo
#
#   names    zero advisories: the repo's own gates/naming-check.sh when it has one (its "N finding(s)" line must say 0), else
#            its vendored lint (vendor/naming/lint-name.sh) run over the tree. A baselined finding is still a finding.
#   paths    no line of AGENTS.md names a path absent from the repo: every backticked token that reads as a repo path
#            (a slash inside it; a bare file name is a word, not a path; not absolute, not a glob, not a <placeholder>) must exist
#   readme   README.md carries the four newcomer answers as `##` sections: what this is, where the code lives,
#            how to run the tests, where decisions are
#
# exit 0 all three hold · 1 a finding · 2 usage · 3 unchecked (a question could not be asked: no AGENTS.md, no README.md,
# no judge for the names). Writes nothing in <dir>.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) _SRC="${0%/*}" ;; *) _SRC=. ;; esac
_SRC="$(CDPATH= cd -- "$_SRC" && pwd)"
. "$_SRC/library-log.sh"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
log_init standard-render-check

case "${1:-}" in -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
[ $# -eq 1 ] && [ -d "$1" ] || { log_fail "usage: standard-render-check.sh <dir>"; log_fix "sh $0 --help"; log_end || :; exit 2; }
D="$(CDPATH= cd -- "$1" && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/render-check.XXXXXX")"; trap 'rm -rf "$T"' EXIT INT TERM
UNCHECKED=0

# names: the gate is the repo's own definition of green; without one, the vendored lint over the tracked (else all) names.
if [ -f "$D/gates/naming-check.sh" ]; then
  out="$(cd "$D" && sh gates/naming-check.sh 2>&1)"; rc=$?
  n="$(printf '%s\n' "$out" | sed -n 's/^naming-check: \([0-9][0-9]*\) finding(s).*/\1/p' | tail -n 1)"
  if [ -z "$n" ] || [ "$rc" -gt 1 ]; then
    log_warn "names: the repo's naming gate gave no verdict (exit $rc)"; UNCHECKED=1
  elif [ "$n" -eq 0 ]; then log_ok "names: gates/naming-check.sh reports 0 findings"
  else log_fail "names: gates/naming-check.sh reports $n finding(s), baselined or not"; log_fix "rename them in the template that renders them, or register an exemption with a reason"; fi
elif [ -f "$D/vendor/naming/lint-name.sh" ] && [ -d "$D/vendor/naming/registry" ]; then
  # lint-name judges the files git lists; a scaffold that is not a repository yet is judged through a throwaway git dir.
  if (cd "$D" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then GD=""; else git init -q --bare "$T/gitdir" >/dev/null 2>&1; GD="$T/gitdir"; fi
  rc=0
  if [ -n "$GD" ]; then
    GIT_DIR="$GD" GIT_WORK_TREE="$D" GIT_INDEX_FILE="$T/index" sh -c 'cd "$GIT_WORK_TREE" && git add -A -- . >/dev/null 2>&1 && HOME="$1" sh vendor/naming/lint-name.sh --root . --registry vendor/naming/registry --format findings' sh "$T" > "$T/names" 2> "$T/err" || rc=$?
  else
    (cd "$D" && HOME="$T" sh vendor/naming/lint-name.sh --root . --registry vendor/naming/registry --format findings) > "$T/names" 2> "$T/err" || rc=$?
  fi
  if [ "$rc" -gt 1 ]; then log_warn "names: the vendored lint exited $rc"; UNCHECKED=1
  else
    n="$(awk -F'\t' 'NF >= 3 && $2 !~ /^name\.(registry-|exemption-|alias-expired|control-|surface-)/' "$T/names" | wc -l | tr -d ' ')"
    if [ "$n" -eq 0 ]; then log_ok "names: the vendored lint reports 0 findings"
    else log_fail "names: the vendored lint reports $n finding(s)"; log_fix "sh $D/vendor/naming/lint-name.sh --root $D --registry $D/vendor/naming/registry"; fi
  fi
else
  log_warn "names: no gates/naming-check.sh and no vendor/naming/ in $D"; UNCHECKED=1
fi

# paths: a backticked token is a repo path when it has a slash inside it (a bare `settings.json` names a file by context).
if [ ! -f "$D/AGENTS.md" ]; then log_warn "paths: no AGENTS.md in $D"; UNCHECKED=1
else
  grep -o '`[^`][^`]*`' "$D/AGENTS.md" | tr -d '`' | LC_ALL=C sort -u > "$T/tokens"
  : > "$T/absent"
  while IFS= read -r tok; do
    case "$tok" in
      *[[:space:]]*|*'<'*|*'>'*|*'*'*|*'$'*|*'{'*|*'('*|*'['*|*'|'*|*'='*|*','*|*':'*|*'@'*|/*|'~'*|-*|http*|*://*) continue ;;
      */*) ;;
      *) continue ;;
    esac
    [ -e "$D/$tok" ] || [ -L "$D/$tok" ] || printf '%s\n' "$tok" >> "$T/absent"
  done < "$T/tokens"
  na="$(wc -l < "$T/absent" | tr -d ' ')"
  if [ "$na" -eq 0 ]; then log_ok "paths: every path AGENTS.md names exists"
  else
    while IFS= read -r p; do log_fail "paths: AGENTS.md names $p, which is not in the repo"; log_fix "render a line only for a path that exists, or ship $p"; done < "$T/absent"
  fi
fi

# readme: the four newcomer answers, as second-level sections.
if [ ! -f "$D/README.md" ]; then log_warn "readme: no README.md in $D"; UNCHECKED=1
else
  heads="$(grep -i '^## ' "$D/README.md" | tr 'A-Z' 'a-z')"
  miss=0
  for want in "what this is" "where the code lives" "how to run the tests" "where decisions are"; do
    case "$heads" in *"$want"*) ;; *) log_fail "readme: README.md has no \`## $want\` section"; log_fix "restore the section from the README skeleton"; miss=1 ;; esac
  done
  [ "$miss" -eq 0 ] && log_ok "readme: the four newcomer sections are there"
fi

if log_end; then
  [ "$UNCHECKED" -eq 0 ] && exit 0
  exit 3
fi
exit 1
