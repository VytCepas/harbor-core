#!/usr/bin/env sh
# scope-system.sh (harbor#1436; check id `scope.system-register`) - `harbor <system> <verb>`, dispatched by register.
#
#   sh scope-system.sh run <system> <verb> [args...]   run the row's command with the caller's arguments; its exit status is ours
#   sh scope-system.sh systems                         the registered systems, one per line: system TAB summary
#   sh scope-system.sh tree                            the dispatch table as the command tree (what `harbor <system> <verb>` runs)
#   sh scope-system.sh --check                         every row resolvable, no row shadowing a frozen harbor verb, no system+verb twice
#
# THE TABLE is contracts/systems.tsv (bin/systems.tsv installed), then the private layer's systems.tsv, which may add rows and never
# replace one. HARBOR_SCOPE_SYSTEMS_TABLE names the only table read. A verb `*` passes every verb to the system's own CLI.
# Exit: the command's own on `run`; 2 usage / unknown system or verb; 127 a command that cannot be found; 1 a --check finding.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$SRC/library-log.sh"; log_init scope-system
TAB="$(printf '\t')"

die() { log_fail "$1"; log_fix "${2:-sh $SRC/scope-system.sh tree}"; log_end || :; exit "${3:-2}"; }

tables() { # the tables to read, in order
  if [ -n "${HARBOR_SCOPE_SYSTEMS_TABLE:-}" ]; then printf '%s\n' "$HARBOR_SCOPE_SYSTEMS_TABLE"; return; fi
  if [ -f "$SRC/../contracts/systems.tsv" ]; then printf '%s\n' "$SRC/../contracts/systems.tsv"
  elif [ -f "$SRC/systems.tsv" ]; then printf '%s\n' "$SRC/systems.tsv"; fi
  _pv="$(sh "$SRC/scope-roots.sh" --private 2>/dev/null || :)"
  [ -z "$_pv" ] || [ ! -f "$_pv/systems.tsv" ] || printf '%s\n' "$_pv/systems.tsv"
}
rows() { # data rows of every table: system verb run json summary
  tables | while IFS= read -r _t; do
    awk -F'\t' '/^#/ || /^[[:space:]]*$/ { next } !h++ { next } NF >= 5 { print }' "$_t"
  done
}
frozen_verbs() { # harbor's own verbs: the VERBS table of the dispatcher beside this script
  for _h in "$SRC/harbor" "$SRC/../bin/harbor"; do
    [ -f "$_h" ] && { awk '/^VERBS="/ { f = 1; next } f && /^"/ { exit } f && NF { print $1 }' "$_h"; return; }
  done
}
resolve() { # <run cell> -> the argv words, or nothing (exit 1) when the command cannot be found
  case "$1" in
    bin:*) _w="${1#bin:}"; _s="${_w%% *}"; [ -f "$SRC/$_s" ] || return 1; printf 'sh\n%s/%s\n' "$SRC" "$_s"; [ "$_w" = "$_s" ] || printf '%s\n' ${_w#"$_s" } ;;
    tool:*) _w="${1#tool:}"; _v="${_w%% *}"
      _p="$(eval "printf '%s' \"\${$_v:-}\"")"
      [ -n "$_p" ] || _p="$(sh "$SRC/scope-roots.sh" --get "$_v" 2>/dev/null || :)"
      [ -n "$_p" ] && [ -x "$_p" ] || return 1
      printf '%s\n' "$_p"; [ "$_w" = "$_v" ] || printf '%s\n' ${_w#"$_v" } ;;
    *) return 1 ;;
  esac
}

CMD="${1:-}"; [ $# -eq 0 ] || shift
case "$CMD" in
run)
  [ $# -ge 1 ] || die "run takes a system" "sh $SRC/scope-system.sh systems"
  SYS="$1"; shift
  ALL="$(rows)"
  printf '%s\n' "$ALL" | awk -F'\t' -v s="$SYS" '$1 == s { f = 1 } END { exit !f }' || die "unknown system '$SYS'" "sh $SRC/scope-system.sh systems"
  VERB="${1:-}"
  ROW="$(printf '%s\n' "$ALL" | awk -F'\t' -v s="$SYS" -v v="$VERB" '$1 == s && $2 == v { print; exit }')"
  PASS=0
  if [ -z "$ROW" ]; then ROW="$(printf '%s\n' "$ALL" | awk -F'\t' -v s="$SYS" '$1 == s && $2 == "*" { print; exit }')"; PASS=1; fi
  if [ -z "$ROW" ]; then
    die "harbor $SYS has no verb '$VERB' (it has: $(printf '%s\n' "$ALL" | awk -F'\t' -v s="$SYS" '$1 == s { printf "%s ", $2 }'))" "sh $SRC/scope-system.sh tree"
  fi
  [ "$PASS" = 1 ] || [ $# -eq 0 ] || shift          # a named verb row: the verb word is the row's, not an argument
  RUN="$(printf '%s\n' "$ROW" | cut -f3)"; JSON="$(printf '%s\n' "$ROW" | cut -f4)"
  if [ "$JSON" = no ]; then for _a in "$@"; do [ "$_a" != --json ] || die "harbor $SYS $VERB has no --json" "sh $SRC/scope-system.sh tree"; done; fi
  W="$(resolve "$RUN")" || die "harbor $SYS: ${RUN} cannot be found (the command or root it names is not installed here)" "sh $SRC/scope-roots.sh --get ${RUN#tool:}" 127
  set -f; IFS='
'; # shellcheck disable=SC2086
  set -- $W "$@"; unset IFS; set +f
  exec "$@" ;;
systems)
  rows | awk -F'\t' '!seen[$1]++ { printf "%s\t%s\n", $1, $5 }' ;;
tree)
  printf '# the dispatch table of contracts/systems.tsv (and the private layer\x27s), the same rows `harbor <system> <verb>` runs\n'
  rows | awk -F'\t' '{ printf "harbor %s %s%s    <- %s\n", $1, ($2 == "*" ? "<verb>" : $2), ($4 == "yes" ? " [--json]" : ""), $3 }' ;;
--check)
  F="${TMPDIR:-/tmp}/scope-system.$$"; : > "$F"
  RT="$SRC/../contracts/roots.tsv"; [ -f "$RT" ] || RT="$SRC/roots.tsv"
  frozen_verbs > "$F.frozen"
  [ -s "$F.frozen" ] || printf 'no dispatcher beside this script to take the frozen verbs from\n' >> "$F"
  rows | awk -F'\t' -v fz="$F.frozen" 'BEGIN { while ((getline l < fz) > 0) Z[l] = 1 }
    { k = $1 SUBSEP $2; if (seen[k]++) printf "%s %s is registered twice\n", $1, $2
      if ($1 in Z) printf "system %s shadows the frozen harbor verb of that name\n", $1
      if ($3 !~ /^(bin|tool):/) printf "%s %s: run %s is neither bin:<script> nor tool:<VAR>\n", $1, $2, $3
      if ($4 != "yes" && $4 != "no") printf "%s %s: json is %s, not yes or no\n", $1, $2, $4 }' >> "$F"
  rows | while IFS="$TAB" read -r _s _v _r _j _m; do
    case "$_r" in bin:*) _x="${_r#bin:}"; [ -f "$SRC/${_x%% *}" ] || printf '%s %s: bin script %s does not exist\n' "$_s" "$_v" "${_x%% *}" >> "$F" ;;
      tool:*) _x="${_r#tool:}"; _x="${_x%% *}"; awk -F'\t' -v v="$_x" '$1 == v { f = 1 } END { exit !f }' "$RT" 2>/dev/null || printf '%s %s: root %s is not a row of roots.tsv\n' "$_s" "$_v" "$_x" >> "$F" ;;
    esac
  done
  if [ ! -s "$F" ]; then log_ok "every registered system resolves to a script or a named root, and none shadows a frozen verb"; rm -f "$F" "$F.frozen"; log_end || :; exit 0; fi
  sed 's/^/  /' "$F" >&2; rm -f "$F" "$F.frozen"; log_fail "the systems register has findings"; log_fix "edit contracts/systems.tsv"; log_end || :; exit 1 ;;
-h|--help) awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SRC/scope-system.sh"; exit 0 ;;
*) die "usage: scope-system.sh run <system> <verb> [args] | systems | tree | --check" ;;
esac
