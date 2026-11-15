#!/usr/bin/env sh
# gate-verbs.sh (harbor#1419) — the one reader of the verb registers in contracts/verbs/, one file per CLI.
# The installer's rules (deploy-install-lib.sh il_verbs) and the planner's hand-over both read the tables here, so a
# row is parsed in one place. Read-only: it runs nothing it prints.
#
#   sh gate-verbs.sh rows [<register.md>...]      file, spelling, class, perm, actor, instead: tab-separated
#   sh gate-verbs.sh rules <allow|ask>            "OK<TAB>spelling<TAB>file" per row with that perm that may
#                                                      become a rule, "BAD<TAB>spelling<TAB>file" per row that may not
#   sh gate-verbs.sh --actor [--owner <owner>] <cli> <verb> [args]
#                                                 who runs this command: prints `operator` or `app`, exit 0;
#                                                 a command no row matches prints `unknown`, exit 3; an `own-org`
#                                                 row whose owner is not given or found prints `owner?`, exit 4
#
# --actor matches the command against every row's spelling as a permission rule does (`*` is any text, and a
# trailing ` *` also matches nothing); the longest matching spelling wins, and on a tie the stricter actor does
# (operator, then own-org, then app). A row with no actor column is the App's. An `own-org` row is the App's inside
# its own org and the operator's in any other: the owner is `--owner`, else the `-R`/`--repo` owner in the command.
# gate-pr-plan.sh asks `--actor gh pr ready 5 -R <owner>/<repo>` (or `--owner <owner> gh pr ready 5`) to know whose
# step it is.
# ENV  HARBOR_GATE_VERBS_DIR      the registers' directory (default: contracts/verbs beside this script's bin/)
#      HARBOR_GATE_VERBS_OWN_ORG  the App's own org (default: the owner of this checkout's repo slug)
set -eu
. "$(dirname -- "$0")/library-log.sh"
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); print; next } {exit}' "$0"; exit 0 ;;
esac
D="${HARBOR_GATE_VERBS_DIR:-$(dirname -- "$0")/../contracts/verbs}"

# A table's header row names its columns, so git's seven (floor, calls, refused) and the other registers' five
# (actor) share one reader. spelling, class and perm are required; actor defaults to app, instead to empty.
_rows() { # <register.md>... -> file TAB spelling TAB class TAB perm TAB actor TAB instead
  awk -F'|' '
    function trim(v) { gsub(/^[ \t`]+|[ \t`]+$/, "", v); return v }
    FNR == 1 { delete col; n = FILENAME; sub(/^.*\//, "", n) }
    /^\| *spelling *\|/ { delete col; for (i = 2; i < NF; i++) col[trim($i)] = i; next }
    /^\| `/ && ("spelling" in col) && ("class" in col) && ("perm" in col) {
      a = ("actor" in col) ? trim($(col["actor"])) : "app"
      ins = ("instead" in col) ? trim($(col["instead"])) : ""
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", n, trim($(col["spelling"])), trim($(col["class"])), trim($(col["perm"])), a, ins }' "$@"
}
_files() { find "$D" -maxdepth 1 -name '*.md' ! -name 'README.md' 2>/dev/null | sort; }

case "${1:-}" in
  rows) shift
    if [ "$#" -gt 0 ]; then _rows "$@"; else
      _f="$(_files)"; [ -n "$_f" ] || exit 0
      # shellcheck disable=SC2086
      _rows $_f
    fi ;;
  rules) [ "${2:-}" = allow ] || [ "${2:-}" = ask ] || { echo "usage: gate-verbs.sh rules <allow|ask>" >&2; exit 2; }
    _f="$(_files)"; [ -n "$_f" ] || exit 0
    # shellcheck disable=SC2086
    _rows $_f | awk -F'\t' -v want="$2" '$4 == want {
      s = $2
      # A rule has to start `<cli> <subcommand>`: a leading flag or wildcard lets the `*` absorb a flag that turns a
      # read into execution. An ask may be the catch-all `<cli> *`, since a broader ask only prompts more.
      ok = (s ~ /^[a-z][a-z-]* [a-z][a-z-]*( |$)/) || (want == "ask" && s ~ /^[a-z][a-z-]* \*$/)
      if (!ok || s ~ /[<>`|;&$]/) print "BAD\t" s "\t" $1; else print "OK\t" s "\t" $1 }' ;;
  --actor) shift
    _own=""; [ "${1:-}" != --owner ] || { [ "$#" -ge 2 ] || { echo "usage: gate-verbs.sh --actor [--owner <owner>] <cli> <verb> [args]" >&2; exit 2; }; _own="$2"; shift 2; }
    [ "$#" -ge 2 ] || { echo "usage: gate-verbs.sh --actor [--owner <owner>] <cli> <verb> [args]" >&2; exit 2; }
    _f="$(_files)"; [ -n "$_f" ] || { echo unknown; exit 3; }
    # The spelling becomes a regex (`*` is any text; a trailing ` *` may match nothing); the longest match wins, and
    # on a tie the stricter actor does, because the longest spelling is the most specific row and strict the safer error.
    # shellcheck disable=SC2086
    _a="$(_rows $_f | awk -F'\t' -v cmd="$*" '
      function rank(a) { return a == "operator" ? 2 : (a == "own-org" ? 1 : 0) }
      { s = $2; r = ""; n = length(s)
        for (i = 1; i <= n; i++) { c = substr(s, i, 1)
          if (c == "*") { r = r ".*" } else if (index("\\.[](){}+?^$|", c)) { r = r "\\" c } else { r = r c } }
        sub(/ \.\*$/, "( .*)?", r)
        if (cmd ~ ("^" r "$") && (length(s) > best || (length(s) == best && rank($5) > rank(who)))) { best = length(s); who = $5 } }
      END { if (who != "") print who }')"
    [ -n "$_a" ] || { echo unknown; exit 3; }
    if [ "$_a" = own-org ]; then
      if [ -z "$_own" ]; then
        _prev=""
        for _w in "$@"; do
          case "$_prev" in -R|--repo) _own="${_w%%/*}"; break ;; esac
          case "$_w" in --repo=*) _own="${_w#--repo=}"; _own="${_own%%/*}"; break ;; esac
          _prev="$_w"
        done
      fi
      [ -n "$_own" ] || { echo "owner?"; exit 4; }
      _me="${HARBOR_GATE_VERBS_OWN_ORG:-$(repo_slug 2>/dev/null | sed 's#/.*##')}"
      [ -n "$_me" ] || { echo "owner?"; exit 4; }
      _l1="$(printf '%s' "$_own" | tr '[:upper:]' '[:lower:]')"; _l2="$(printf '%s' "$_me" | tr '[:upper:]' '[:lower:]')"
      if [ "$_l1" = "$_l2" ]; then _a=app; else _a=operator; fi
    fi
    echo "$_a" ;;
  *) echo "usage: gate-verbs.sh rows [<register.md>...] | rules <allow|ask> | --actor [--owner <owner>] <cli> <verb> [args]" >&2; exit 2 ;;
esac
