#!/usr/bin/env sh
# access.sh (harbor#1205, harbor#1149) - `harbor access`: the access register, the one list of every identity an
# agent may use, and the only door to a secret's name. contracts/access-register.md is the format.
#
#   harbor access add <id> --kind K --what T --use-when T --reaches T --cannot T --grant T
#                          (--secret REF | --no-secret) [--value-stdin] [--probe CMD]
#                          [--check CMD --expect T] [--expires YYYY-MM-DD] [--renew T] [--revoke T] [--held T]
#                          [--vendor-name "<ORG> API <Platform>[ <Client>]"]   required for kind token and app
#                          [--verbatim]   the value is stored byte for byte (a key file); else it is trimmed and one word
#   harbor access list                    the entries: id, kind, secret ref, what
#   harbor access has <ref>               exit 0 registered, 3 grandfathered (contracts/secret-legacy-refs.txt), 4 revoked, 1 neither
#   harbor access refs                    the registered secret refs, one per line
#   harbor access check                   is the register well formed, and free of a credential value
#   harbor access stored                  every item bin/secret holds, and whether an entry names it (exit 1 if not)
#   harbor access status [-v|--json] [id...]  is each credential stored, alive, in date: what is wrong, and since when; --json: the same facts as data
#   harbor access rotate <id> [--value-stdin] [--locked]   a new value, kept only if the entry's check passes on it
#
# A PIPED VALUE IS CHECKED BEFORE IT IS STORED (harbor#978, measured 2026-11-13: a clipboard copy put four characters and a
# space in front of an ad platform's app secret). With --value-stdin, add and rotate trim surrounding whitespace and newlines and refuse
# a value with whitespace inside it, saying only its length; an entry with `value-shape: verbatim` (add --verbatim) is
# stored byte for byte instead, for a key file or JSON. A value typed at bin/secret's own prompt is one line already.
#   harbor access revoke <id>             retire an entry: refuse its ref from now on, and remove the stored value
#   harbor access renamed <ref>           the registered ref, the other ref and remove_by of the open secret rename naming it; exit 1 when none
#   harbor access move <old-ref> [--locked]   the D-36 migration of one ref: the entry names the new ref, the value is copied
#                                         to it inside bin/secret (never shown), and the old item stays until remove_by
#
# NAMES (harbor#978). add refuses a --secret ref that `lint-name.sh --check secret` refuses (D-36,
# <system>-<service>-<identity>-<purpose>) and a --vendor-name that `--check vendor-credential` refuses, printing the
# compliant rendering as the fix. A ref renamed in standards/naming/renames.tsv (or the private <access>/renames.tsv,
# for a ref a workload reads or one naming a client) is the SAME credential under both names until the row's remove_by: has admits
# either, and bin/secret reads the one the register names, else the other, and writes the one the register names.
#
# add records an entry, then stores the value through bin/secret (the ref must be registered first, so it is written
# before the store and rolled back when the store fails). The value is read from stdin with --value-stdin, or by
# bin/secret's own prompt on a terminal; it is never an argument. A missing field is asked for on a terminal and a
# usage error (exit 2) elsewhere. --probe runs CMD after the store: a failing probe exits 1 and keeps the entry.
# With no private layer the register is empty: every ref is unregistered, add refuses, list prints nothing.
# status, rotate and revoke make the register the one controller of a credential's life (contracts/access-register.md,
# "Lifecycle"): the entry's check:/expect: is run by check-routes.sh --probe, the classifier the cards use.
set -eu
LC_ALL=C; export LC_ALL   # [a-z] below means ASCII lower case, whatever the caller's locale

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/library-log.sh"
log_init access
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2
GREP=/usr/bin/grep   # grep here is ugrep on the operator's box; BSD semantics are the contract
LEGACY="${ACCESS_LEGACY_REFS:-$ROOT/contracts/secret-legacy-refs.txt}"
PATTERNS="${ACCESS_CREDENTIAL_PATTERNS:-$ROOT/contracts/credential-patterns.tsv}"
KINDS='account role app mailbox token'
FIELDS='kind what use-when reaches cannot grant secret verified check expect expires renew revoke rotated revoked held vendor-name value-shape'
DATE_FIELDS='expires rotated revoked'
PROBE_RUNNER="$ROOT/skills/access-ledger/bin/check-routes.sh"
STATE="${ACCESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/harbor/access-status.tsv}"
REQUIRED='kind what use-when reaches cannot grant secret verified'
VENDOR_KINDS='token app'   # the kinds a vendor-side object stands behind, so their new entries carry its name (harbor#978)
RENAMES="${ACCESS_RENAMES:-$ROOT/standards/naming/renames.tsv}"
LINT_NAME="${ACCESS_LINT_NAME:-$SRC/lint-name.sh}"
MEMBER_MODE=0; [ ! -f "$SRC/harbor-member-mode" ] || [ -L "$SRC/harbor-member-mode" ] || MEMBER_MODE=1   # as bin/secret reads it

fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
usage() { sed -n '2,39p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# The register file: <access dir>/register.md. Empty stdout and exit 1 when there is no register directory.
register_file() {
  __d="$(sh "$SRC/scope-roots.sh" --access 2>/dev/null)" || return 1
  printf '%s/register.md' "$__d"
}

# The register as lines: "N<TAB>id" per entry, "R<TAB>id<TAB>field<TAB>value" per field, "E<TAB>message" per
# problem the grammar itself finds. An entry is `## <id>` and its indented `name: value` lines.
parse() { # <file>
  awk '
    function err(m) { printf "E\tline %d: %s\n", NR, m }
    { sub(/\r$/, "") }
    /^## / {
      id = $0; sub(/^## +/, "", id); sub(/[ \t]+$/, "", id)
      if (id !~ /^[a-z0-9][a-z0-9._-]*$/) { err("the entry id \"" id "\" is not [a-z0-9][a-z0-9._-]*"); cur = ""; next }
      if (id in seen) { err("the entry " id " repeats the one on line " seen[id]); cur = ""; next }
      seen[id] = NR; cur = id; delete have; printf "N\t%s\n", id; next
    }
    /^[ \t]+[A-Za-z_][A-Za-z0-9_-]*:/ {
      if (cur == "") { err("a field line outside any entry"); next }
      line = $0; sub(/^[ \t]+/, "", line)
      name = line; sub(/:.*/, "", name)
      val = line; sub(/^[^:]*:[ \t]*/, "", val); sub(/[ \t]+$/, "", val)
      if (name in have) { err(cur ": the field " name " is given twice"); next }
      have[name] = 1
      if (val ~ /\t/) { err(cur ": " name " holds a tab"); next }
      printf "R\t%s\t%s\t%s\n", cur, name, val
    }' "$1"
}

reg_state() { # <ref> - 0 an entry names it, 4 that entry is revoked, 1 none. Silent.
  __rf="$(register_file)" || __rf=""
  [ -n "$__rf" ] && [ -f "$__rf" ] || return 1
  # Any entry naming the ref with a revoked: line, whatever its value, refuses it, and the legacy list is
  # never consulted for it: a revoked ref that was also grandfathered must not come back through the list.
  parse "$__rf" | awk -F'\t' -v r="$1" '
    $1 == "R" && $3 == "secret" && $4 == r && r != "none" { named[$2] = 1 }
    $1 == "R" && $3 == "revoked" { rev[$2] = 1 }
    END { st = 1; for (i in named) { if (i in rev) { st = 4; break } st = 0 } exit st }'
}

# The open secret rename naming a ref: "old<TAB>new<TAB>remove_by", exit 1 when none. Rows are surface `secret`,
# old `secret:<ref>`, in core renames.tsv and in the private <access>/renames.tsv (a ref a workload reads, or one
# naming a client or a workload vendor, lives there, never in core: the leak gate and lint.domain). Open means today (UTC) is on or before remove_by.
rename_row() { # <ref>
  __ad="$(sh "$SRC/scope-roots.sh" --access 2>/dev/null)" || __ad=''
  __t="$(today)"
  for __rn in "$RENAMES" ${__ad:+"$__ad/renames.tsv"}; do
    [ -f "$__rn" ] || continue
    awk -F'\t' -v r="$1" -v t="$__t" '/^#/ || $1 == "id" { next }
      $4 == "secret" && substr($2, 1, 7) == "secret:" && (substr($2, 8) == r || $3 == r) && $6 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ && t <= $6 {
        printf "%s\t%s\t%s\n", substr($2, 8), $3, $6; f = 1; exit }
      END { exit !f }' "$__rn" && return 0
  done
  return 1
}

has_ref() { # <ref> - exit 0 registered, 3 grandfathered, 4 revoked, 1 neither. Silent.
  __ref="$1"
  __hs=0; reg_state "$__ref" || __hs=$?
  case "$__hs" in 0) return 0 ;; 4) return 4 ;; esac
  # A renamed ref is the same credential under both names until remove_by: either name is registered when one is.
  if __row="$(rename_row "$__ref")"; then
    __po="$(printf '%s' "$__row" | cut -f1)"; __pn="$(printf '%s' "$__row" | cut -f2)"
    __p="$__pn"; [ "$__ref" != "$__pn" ] || __p="$__po"
    __ps=0; reg_state "$__p" || __ps=$?
    case "$__ps" in 0) return 0 ;; 4) return 4 ;; esac
  fi
  if [ -f "$LEGACY" ] && awk -v r="$__ref" '/^[[:space:]]*(#|$)/ { next } $1 == r { f = 1 } END { exit !f }' "$LEGACY"; then return 3; fi
  return 1
}

# renamed <ref>: the ref the register names (the new one when both or neither are named), the other, and remove_by.
cmd_renamed() {
  [ $# -eq 1 ] || usage
  __row="$(rename_row "$1")" || return 1
  __o="$(printf '%s' "$__row" | cut -f1)"; __n="$(printf '%s' "$__row" | cut -f2)"; __d="$(printf '%s' "$__row" | cut -f3)"
  if reg_state "$__n" || ! reg_state "$__o"; then printf '%s\t%s\t%s\n' "$__n" "$__o" "$__d"
  else printf '%s\t%s\t%s\n' "$__o" "$__n" "$__d"; fi
}

# The naming gate of add (harbor#978): lint-name.sh judges, this prints its finding and the compliant form.
# 0 pass (a warn-mode finding is printed and passes), else it exits. A lint that cannot judge refuses: fail closed.
name_gate() { # <surface> <name> <fix function> <its argument> - the fix is rendered only for a refusal
  [ -f "$LINT_NAME" ] || fail "no $LINT_NAME, so the name '$2' cannot be judged and nothing was registered" "restore bin/lint-name.sh" 1
  __lr=0; __lo="$(sh "$LINT_NAME" --check "$1" "$2" 2>&1)" || __lr=$?
  case "$__lr" in
    0) printf '%s\n' "$__lo" | grep '^  WARN: ' >&2 || :; return 0 ;;
    1) __why="$(printf '%s\n' "$__lo" | sed -n 's/^  FAIL: //p' | head -1)"
       fail "the $1 name '$2' breaks the naming standard: ${__why:-see lint-name.sh --check $1}" "$("$3" "$4")" 2 ;;
    *) fail "lint-name.sh --check $1 exited $__lr, so the name '$2' was not judged and nothing was registered" "sh $LINT_NAME --check $1 '$2'" 1 ;;
  esac
}

# The compliant rendering of a refused secret ref: its renames row when it has one, else harbor-<ref> when that
# passes (github-tools-push), else the grammar with the slots to fill.
secret_fix() { # <ref>
  if __row="$(rename_row "$1")" && [ "$(printf '%s' "$__row" | cut -f1)" = "$1" ]; then
    printf 'use %s (renames.tsv; harbor access move %s moves an entry that already names it)' "$(printf '%s' "$__row" | cut -f2)" "$1"; return 0
  fi
  if sh "$LINT_NAME" --check secret "harbor-$1" > /dev/null 2>&1; then printf 'use harbor-%s' "$1"; return 0; fi
  printf 'name it harbor-<service>-<identity>-<purpose>: sh %s --render secret system=harbor service=<vendor> identity=<account> purpose=<use>' "$LINT_NAME"
}

# value_clean <id>: the piped value on stdout, surrounding whitespace trimmed; exit 1 (saying the length, never the value)
# when it is empty or holds whitespace inside. Held in a variable, as bin/secret holds it: never argv, never a file.
value_clean() {
  __v="$(cat; printf x)"; __v="${__v%x}"
  __n0=${#__v}
  __v="${__v#"${__v%%[![:space:]]*}"}"; __v="${__v%"${__v##*[![:space:]]}"}"
  [ -n "$__v" ] || { log_fail "the piped value for '$1' is empty after trimming whitespace ($__n0 characters came in)"; log_fix "pipe the credential itself"; log_end || :; return 1; }
  case "$__v" in *[[:space:]]*)
    log_fail "the piped value for '$1' holds whitespace inside it (${#__v} characters after trimming): a copy that carried more than the credential"
    log_fix "copy only the credential and pipe it again; a value that really holds spaces or lines (a key file) is an entry with --verbatim"
    log_end || :; return 1 ;;
  esac
  [ "${#__v}" = "$__n0" ] || log_note "trimmed $((__n0 - ${#__v})) whitespace character(s) around the value for '$1' (${#__v} characters kept)"
  printf '%s' "$__v"
}

renames_fix() { printf 'fix the renames row of %s: its new name must pass lint-name.sh --check secret' "$1"; }

# The compliant vendor-side name for a ref's service: <ORG> API <Platform>, rendered by the grammar.
vendor_fix() { # <ref or none>
  __svc="$(sh "$LINT_NAME" --parse secret "$1" 2>/dev/null | sed -n 's/^service=//p')" || __svc=''
  if [ -n "$__svc" ] && __vr="$(sh "$LINT_NAME" --render vendor-credential platform="$__svc" 2>/dev/null)" && [ -n "$__vr" ]; then
    printf 'rename it on the vendor to "%s" (add " <Client>" for a per-account key), then pass --vendor-name "%s"' "$__vr" "$__vr"; return 0
  fi
  printf 'name it on the vendor <ORG> API <Platform>[ <Client>]: sh %s --render vendor-credential platform=<vendor>' "$LINT_NAME"
}

today() { date -u +%Y-%m-%d; }   # UTC, as every date this file writes
# Calendar-valid ISO date, and a day number for differences: no mktime, which one-true-awk lacks.
AWK_DATES='
  function okdate(d,   a, y, m, dd, ml) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    split(d, a, "-"); y = a[1] + 0; m = a[2] + 0; dd = a[3] + 0
    if (m < 1 || m > 12) return 0
    ml = (m == 2) ? (((y % 4 == 0 && y % 100 != 0) || y % 400 == 0) ? 29 : 28) : ((m == 4 || m == 6 || m == 9 || m == 11) ? 30 : 31)
    return dd >= 1 && dd <= ml
  }
  function dayno(d,   a, y, m, dd) {
    split(d, a, "-"); y = a[1] + 0; m = a[2] + 0; dd = a[3] + 0
    if (m < 3) { y--; m += 12 }
    return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + dd
  }'
valid_ref() { case "$1" in ''|*[!A-Za-z0-9._-]*) return 1 ;; *) return 0 ;; esac; }
one_line() { case "$1" in *'
'*|*"$(printf '\r')"*|*"$(printf '\t')"*) return 1 ;; esac; [ -n "$1" ]; }

cmd_has() {
  [ $# -eq 1 ] || usage
  has_ref "$1" && return 0 || return $?
}

cmd_refs() {
  __rf="$(register_file)" || return 0
  [ -f "$__rf" ] || return 0
  parse "$__rf" | awk -F'\t' '$1 == "R" && $3 == "secret" && $4 != "none" && $4 != "" { print $4 }'
}

cmd_list() {
  __rf="$(register_file)" || { log_note "no access register: no private layer, so nothing is registered (harbor scope install)"; log_end || :; return 0; }
  [ -f "$__rf" ] || { log_note "$__rf does not exist yet (harbor scope install creates it)"; log_end || :; return 0; }
  parse "$__rf" | awk -F'\t' '
    $1 == "N" { ids[++n] = $2 }
    $1 == "R" { v[$2, $3] = $4 }
    END { for (i = 1; i <= n; i++) printf "%s\t%s\t%s\t%s\n", ids[i], v[ids[i], "kind"], v[ids[i], "secret"], v[ids[i], "what"] }'
}

# Is the register well formed, and does any value look like a credential? Prints FAIL lines; returns 1 on any.
cmd_check() {
  __rf="$(register_file)" || { printf 'access check: no access register, so NOTHING was checked and this is not a pass.\n' >&2; printf '              Create the private layer first (harbor scope install, contracts/private-layer.md).\n' >&2; exit 2; }
  [ -f "$__rf" ] || { printf 'access check: %s does not exist, so NOTHING was checked and this is not a pass.\n' "$__rf" >&2; exit 2; }
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  trap 'rm -rf "$__tmp"' EXIT INT TERM
  parse "$__rf" > "$__tmp/rows"
  __bad=0
  # The grammar's own problems.
  while IFS="$(printf '\t')" read -r _t _m; do
    [ "$_t" = E ] || continue
    log_fail "${__rf##*/} $_m"; log_fix "fix the line in $__rf (contracts/access-register.md)"; __bad=1
  done < "$__tmp/rows"
  # Required fields, the kind enum, the secret ref shape, the date, and a ref named by one entry only.
  awk -F'\t' -v req="$REQUIRED" -v all="$FIELDS" -v kinds="$KINDS" -v dates="$DATE_FIELDS" "$AWK_DATES"'
    BEGIN { nr = split(req, R, " "); na = split(all, A, " "); nk = split(kinds, K, " "); nd = split(dates, DF, " ") }
    $1 == "N" { ids[++n] = $2 }
    $1 == "R" { v[$2, $3] = $4; h[$2, $3] = 1 }
    END {
      for (i = 1; i <= n; i++) {
        id = ids[i]
        for (j = 1; j <= nr; j++) if (!h[id, R[j]] && R[j] != "verified") printf "%s: no %s field\n", id, R[j]
        for (j = 1; j <= nr; j++) if (h[id, R[j]] && v[id, R[j]] == "") printf "%s: %s is empty\n", id, R[j]
        for (key in h) { split(key, P, SUBSEP); if (P[1] == id) { ok = 0; for (j = 1; j <= na; j++) if (A[j] == P[2]) ok = 1; if (!ok) printf "%s: unknown field %s\n", id, P[2] } }
        if (h[id, "kind"]) { ok = 0; for (j = 1; j <= nk; j++) if (K[j] == v[id, "kind"]) ok = 1; if (!ok) printf "%s: kind %s is not one of %s\n", id, v[id, "kind"], kinds }
        if (h[id, "secret"]) {
          s = v[id, "secret"]
          if (s != "none" && s !~ /^[A-Za-z0-9._-]+$/) printf "%s: secret %s is neither none nor a reference [A-Za-z0-9._-]+\n", id, s
          else if (s != "none") { if (s in owner) printf "%s: secret %s is already named by %s\n", id, s, owner[s]; else owner[s] = id }
        }
        if (h[id, "verified"] && v[id, "verified"] !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) printf "%s: verified %s is not an ISO date\n", id, v[id, "verified"]
        for (j = 1; j <= nd; j++) if (h[id, DF[j]] && !okdate(v[id, DF[j]])) printf "%s: %s %s is not a calendar date YYYY-MM-DD\n", id, DF[j], v[id, DF[j]]
        if (h[id, "check"] != h[id, "expect"]) printf "%s: check and expect go together; one is missing\n", id
        if (h[id, "held"] && v[id, "held"] == "") printf "%s: held is empty\n", id
        else if (h[id, "held"] && v[id, "secret"] != "none") printf "%s: held says the value lives outside the seam, so it goes with secret: none, not %s\n", id, v[id, "secret"]
        if (h[id, "value-shape"] && v[id, "value-shape"] != "verbatim") printf "%s: value-shape %s is not verbatim, its one value\n", id, v[id, "value-shape"]
        if (h[id, "expect"] && v[id, "expect"] !~ /`[^`]+`/) printf "%s: expect carries no backticked literal, so no check can pass on it\n", id
      }
    }' "$__tmp/rows" > "$__tmp/problems"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    log_fail "${__rf##*/} $_p"; log_fix "fix the entry in $__rf (contracts/access-register.md)"; __bad=1
  done < "$__tmp/problems"
  # A vendor-name is judged as add judged it (harbor#978): an entry edited by hand is held to the same name.
  awk -F'\t' '$1 == "R" && $3 == "vendor-name" { print $2 "\t" $4 }' "$__tmp/rows" > "$__tmp/vnames"
  while IFS="$(printf '\t')" read -r _vi _vn; do
    [ -n "$_vn" ] || continue
    [ -f "$LINT_NAME" ] || { log_warn "no $LINT_NAME: the vendor-name of $_vi was not judged"; continue; }
    __vr=0; sh "$LINT_NAME" --check vendor-credential "$_vn" > "$__tmp/vout" 2>&1 || __vr=$?
    [ "$__vr" = 1 ] || continue
    log_fail "${__rf##*/} $_vi: vendor-name $(sed -n 's/^  FAIL: //p' "$__tmp/vout" | head -1)"; log_fix "rename it on the vendor, then fix vendor-name: in $__rf"; __bad=1
  done < "$__tmp/vnames"
  # A value that looks like a credential. The line is reported, never the value.
  if [ -f "$PATTERNS" ]; then
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next } $1 == "id" { next } NF >= 2 { print $2 }' "$PATTERNS" > "$__tmp/pats"
    if [ -s "$__tmp/pats" ]; then
      "$GREP" -nE -f "$__tmp/pats" "$__rf" 2>/dev/null | cut -d: -f1 | while IFS= read -r _ln; do
        printf '%s\n' "$_ln"
      done > "$__tmp/hits" || :
      while IFS= read -r _ln; do
        [ -n "$_ln" ] || continue
        log_fail "${__rf##*/} line $_ln holds something shaped like a credential value"
        log_fix "remove it, rotate the credential, and store it with: harbor access add <id> ... --value-stdin"; __bad=1
      done < "$__tmp/hits"
    fi
  else
    log_warn "no ${PATTERNS#$ROOT/}: the credential-shape scan did not run"
  fi
  __n="$(awk -F'\t' '$1 == "N"' "$__tmp/rows" | wc -l | tr -d ' ')"
  if [ "$__bad" = 0 ]; then log_ok "$__n entr$([ "$__n" = 1 ] && echo y || echo ies) in $__rf, well formed, no credential value"; fi
  # Grandfathered refs that the register now names: the legacy list can shrink.
  if [ -f "$LEGACY" ]; then
    awk '/^[[:space:]]*(#|$)/ { next } { print $1 }' "$LEGACY" | while IFS= read -r _lr; do
      cmd_refs | grep -qxF -- "$_lr" && printf '%s\n' "$_lr"
    done > "$__tmp/dup" || :
    while IFS= read -r _lr; do
      [ -n "$_lr" ] || continue
      log_note "$_lr is registered now: remove it from ${LEGACY#$ROOT/} so the list only goes down"
    done < "$__tmp/dup"
  fi
  log_end || :
  [ "$__bad" = 0 ]
}

# Every item the store holds, against the register: an item no entry names is a value bin/secret will not hand to its
# consumer, so that consumer is broken (harbor#1205: a stored token in no list was refused from the gate's merge on).
# Names only; bin/secret list never prints a value. Prints "<state><TAB><ref>" per item.
cmd_stored() {
  [ $# -eq 0 ] || usage
  __out="$(sh "$SRC/secret" list 2>/dev/null)" || fail "bin/secret list failed, so NOTHING was compared and this is not a pass" "run: secret list" 2
  __bad=0; __n=0
  for __svc in $(printf '%s\n' "$__out" | awk '{ print $1 }' | sed -n 's/^secret\.//p' | sort -u); do
    __n=$((__n + 1))
    __st=0; has_ref "$__svc" || __st=$?
    case "$__st" in
      0) if reg_state "$__svc"; then printf 'registered\t%s\n' "$__svc"
         else printf 'renamed\t%s\n' "$__svc"; log_note "secret.$__svc is the old twin of a renamed ref, served until remove_by: $(rename_row "$__svc" | cut -f2,3 | tr '\t' ' ')"; fi ;;
      3) printf 'grandfathered\t%s\n' "$__svc" ;;
      4) printf 'REVOKED\t%s\n' "$__svc"; __bad=1
         log_fail "secret.$__svc is still stored, but its entry is revoked"
         log_fix "remove it: secret rm $__svc" ;;
      *) printf 'UNREGISTERED\t%s\n' "$__svc"; __bad=1
         log_fail "secret.$__svc is stored but no entry names it, so bin/secret refuses it to every consumer"
         log_fix "register it: harbor access add <id> --kind token ... --secret $__svc   (or, if nothing uses it: secret rm $__svc)" ;;
    esac
  done
  [ "$__bad" = 1 ] || log_ok "$__n stored item$([ "$__n" = 1 ] || echo s), each named by the register or the legacy list"
  log_end || :
  [ "$__bad" = 0 ]
}

cmd_add() {
  [ $# -ge 1 ] || usage
  ID="$1"; shift
  KIND=''; WHAT=''; USEWHEN=''; REACHES=''; CANNOT=''; GRANT=''; REFNAME=''; NOREF=0; VALSTDIN=0; PROBE=''
  CHECK=''; EXPECT=''; EXPIRES=''; RENEW=''; REVOKE=''; HELD=''; VNAME=''; VERBATIM=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind|--what|--use-when|--reaches|--cannot|--grant|--secret|--probe|--check|--expect|--expires|--renew|--revoke|--held|--vendor-name)
        [ $# -ge 2 ] || { log_fail "$1 needs a value"; log_fix "harbor access add --help"; log_end || :; exit 2; }
        case "$1" in
          --kind) KIND="$2" ;; --what) WHAT="$2" ;; --use-when) USEWHEN="$2" ;; --reaches) REACHES="$2" ;;
          --cannot) CANNOT="$2" ;; --grant) GRANT="$2" ;; --secret) REFNAME="$2" ;; --probe) PROBE="$2" ;;
          --check) CHECK="$2" ;; --expect) EXPECT="$2" ;; --expires) EXPIRES="$2" ;; --renew) RENEW="$2" ;;
          --revoke) REVOKE="$2" ;; --held) HELD="$2" ;; --vendor-name) VNAME="$2" ;;
        esac
        shift 2 ;;
      --no-secret) NOREF=1; shift ;;
      --value-stdin) VALSTDIN=1; shift ;;
      --verbatim) VERBATIM=1; shift ;;
      -h|--help|help) usage ;;
      *) log_fail "unknown argument '$1'"; log_fix "harbor access add --help"; log_end || :; exit 2 ;;
    esac
  done
  case "$ID" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9._-]*|[!abcdefghijklmnopqrstuvwxyz0-9]*) fail "the id '$ID' is not [a-z0-9][a-z0-9._-]*" "pick a kebab-case id" 2 ;; esac
  # A missing field is asked for when stdin is a terminal and is a usage error otherwise.
  ask() { # <var> <label> - fills the variable named by $1 from the terminal when it is empty
    eval "__cur=\${$1}"
    [ -z "$__cur" ] || return 0
    if [ "$VALSTDIN" = 0 ] && [ -t 0 ]; then
      printf '%s: ' "$2" >&2; IFS= read -r __ans || __ans=''
      eval "$1=\$__ans"
    fi
  }
  ask KIND "kind ($KINDS)"; ask WHAT "what it is"; ask USEWHEN "when to use it"; ask REACHES "what it reaches"
  ask CANNOT "what it cannot do"; ask GRANT "who granted it"
  if [ -z "$REFNAME" ] && [ "$NOREF" = 0 ] && [ "$VALSTDIN" = 0 ] && [ -t 0 ]; then
    printf 'secret reference (empty for none): ' >&2; IFS= read -r REFNAME || REFNAME=''
    [ -n "$REFNAME" ] || NOREF=1
  fi
  case " $VENDOR_KINDS " in *" $KIND "*) [ "$MEMBER_MODE" = 1 ] || ask VNAME "its name on the vendor (<ORG> API <Platform>[ <Client>])" ;; esac
  __missing=''
  for __f in KIND WHAT USEWHEN REACHES CANNOT GRANT; do
    eval "__v=\${$__f}"; [ -n "$__v" ] || __missing="$__missing $__f"
  done
  [ -n "$REFNAME" ] || [ "$NOREF" = 1 ] || __missing="$__missing SECRET(--secret|--no-secret)"
  [ -z "$__missing" ] || fail "missing:$__missing" "give every field as a flag (harbor access add --help)" 2
  [ -z "$REFNAME" ] || [ "$NOREF" = 0 ] || fail "--secret and --no-secret together" "give one" 2
  [ "$VALSTDIN" = 0 ] || [ -n "$REFNAME" ] || fail "--value-stdin needs --secret <ref>" "name the ref the value is stored under" 2
  [ -n "$REFNAME" ] || REFNAME=none
  [ -z "$HELD" ] || [ "$REFNAME" = none ] || fail "--held says the value lives outside the seam, so it goes with --no-secret" "give one of --secret and --held" 2
  for __f in "$KIND" "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$ID"; do
    one_line "$__f" || fail "a field must be one non-empty line with no tab" "shorten it to a single line" 2
  done
  for __f in "$CHECK" "$EXPECT" "$EXPIRES" "$RENEW" "$REVOKE" "$PROBE" "$HELD" "$VNAME"; do
    [ -z "$__f" ] || one_line "$__f" || fail "a field must be one non-empty line with no tab" "shorten it to a single line" 2
  done
  [ -z "$CHECK" ] && [ -z "$EXPECT" ] || { [ -n "$CHECK" ] && [ -n "$EXPECT" ]; } || fail "--check and --expect go together" "give both" 2
  [ -z "$EXPECT" ] || case "$EXPECT" in *'`'?*'`'*) ;; *) fail "--expect carries no backticked literal" "quote what the check must print in backticks" 2 ;; esac
  # The shape is checked in the shell first and the value passed with -v: never spliced into awk's program text.
  [ -z "$EXPIRES" ] || { case "$EXPIRES" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) true ;; *) false ;; esac \
    && awk -v d="$EXPIRES" "BEGIN { exit !okdate(d) } $AWK_DATES"; } 2>/dev/null \
    || fail "--expires '$EXPIRES' is not a calendar date YYYY-MM-DD" "give the date the vendor shows" 2
  case " $KINDS " in *" $KIND "*) ;; *) fail "kind '$KIND' is not one of: $KINDS" "use one of them" 2 ;; esac
  [ "$REFNAME" = none ] || valid_ref "$REFNAME" || fail "secret ref '$REFNAME' is not [A-Za-z0-9._-]+" "use a plain reference, never the value" 2
  # A value pasted into a field is the mistake this refuses: no field may be shaped like a credential.
  if [ -f "$PATTERNS" ]; then
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next } $1 == "id" { next } NF >= 2 { print $2 }' "$PATTERNS" > "${TMPDIR:-/tmp}/access-pats.$$"
    if printf '%s\n' "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$REFNAME" "$CHECK" "$EXPECT" "$RENEW" "$REVOKE" "$PROBE" "$HELD" "$VNAME" \
        | "$GREP" -qE -f "${TMPDIR:-/tmp}/access-pats.$$"; then
      rm -f "${TMPDIR:-/tmp}/access-pats.$$"
      fail "a field is shaped like a credential value; a register holds references, never values" "pipe the value with --value-stdin instead" 2
    fi
    rm -f "${TMPDIR:-/tmp}/access-pats.$$"
  fi
  # harbor#978: a new ref is born under its D-36 name, and a token or app says what it is called on the vendor. A member
  # laptop gets the lint and its registry in the pinned floor (contracts/member-files.txt), so the ref gate runs there too;
  # hub-token, the one name the floor's guards require, is a tool-required exemption. The vendor-name gate needs the
  # company's org, which no hub channel delivers to a laptop yet, so on a member it stands down and says so.
  [ "$REFNAME" = none ] || name_gate secret "$REFNAME" secret_fix "$REFNAME"
  if [ "$MEMBER_MODE" = 1 ]; then
    case " $VENDOR_KINDS " in *" $KIND "*) log_note "member laptop: the vendor-name gate does not run here, since no hub channel delivers the company's org yet" ;; esac
  else
    case " $VENDOR_KINDS " in *" $KIND "*)
      [ -n "$VNAME" ] || fail "a $KIND entry names the credential as the vendor shows it, and --vendor-name is missing" "$(vendor_fix "$REFNAME")" 2 ;;
    esac
    [ -z "$VNAME" ] || name_gate vendor-credential "$VNAME" vendor_fix "$REFNAME"
  fi
  [ "$VERBATIM" = 0 ] || [ "$REFNAME" != none ] || fail "--verbatim describes a stored value, so it needs --secret" "give the ref" 2
  # The piped value is read and judged before anything is written, so a bad paste leaves no entry to roll back.
  VALUE=''
  if [ "$VALSTDIN" = 1 ] && [ "$VERBATIM" = 0 ]; then VALUE="$(value_clean "$ID")" || exit 2; fi
  REG="$(register_file)" || fail "no access register: there is no private layer to write one in" "harbor scope install" 1
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install (it creates the register with a header only)" 1
  lock_register "$REG"
  parse "$REG" | awk -F'\t' -v i="$ID" '$1 == "N" && $2 == i { f = 1 } END { exit !f }' && fail "the entry '$ID' already exists" "pick another id, or edit $REG" 1
  if [ "$REFNAME" != none ]; then
    cmd_refs | grep -qxF -- "$REFNAME" && fail "the secret ref '$REFNAME' is already named by another entry" "one entry names a ref" 1
    ! has_ref "$REFNAME" || fail "the secret ref '$REFNAME' is the renamed twin of a registered ref (renames.tsv)" "harbor access move <its old ref> moves that entry to it" 1
  fi
  __new="$REG.new.$$"; __old="$REG.old.$$"
  cp "$REG" "$__old"
  {
    cat "$REG"
    [ -z "$(tail -c1 "$REG")" ] || printf '\n'
    printf '\n## %s\n\n' "$ID"
    printf '    kind: %s\n    what: %s\n    use-when: %s\n    reaches: %s\n    cannot: %s\n    grant: %s\n    secret: %s\n    verified: %s\n' \
      "$KIND" "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$REFNAME" "$(today)"
    [ -z "$CHECK" ] || printf '    check: %s\n    expect: %s\n' "$CHECK" "$EXPECT"
    [ -z "$EXPIRES" ] || printf '    expires: %s\n' "$EXPIRES"
    [ -z "$RENEW" ] || printf '    renew: %s\n' "$RENEW"
    [ -z "$REVOKE" ] || printf '    revoke: %s\n' "$REVOKE"
    [ -z "$HELD" ] || printf '    held: %s\n' "$HELD"
    [ -z "$VNAME" ] || printf '    vendor-name: %s\n' "$VNAME"
    [ "$VERBATIM" = 0 ] || printf '    value-shape: verbatim\n'
    if [ "$REFNAME" != none ] && { [ "$VALSTDIN" = 1 ] || [ -t 0 ]; }; then printf '    rotated: %s\n' "$(today)"; fi
  } > "$__new"
  mv -f "$__new" "$REG"
  log_ok "registered '$ID' ($KIND) in $REG"
  if [ "$REFNAME" != none ]; then
    # The ref is registered, so bin/secret admits it. A failed store leaves nothing behind.
    if [ "$VALSTDIN" = 1 ] && [ "$VERBATIM" = 0 ]; then
      printf '%s' "$VALUE" | sh "$SRC/secret" put "$REFNAME" || { VALUE=''; mv -f "$__old" "$REG"; fail "storing '$REFNAME' failed, so the entry was rolled back" "check the credential store (bin/secret help)" 1; }
      VALUE=''
    elif [ "$VALSTDIN" = 1 ]; then
      sh "$SRC/secret" put "$REFNAME" || { mv -f "$__old" "$REG"; fail "storing '$REFNAME' failed, so the entry was rolled back" "check the credential store (bin/secret help)" 1; }
    elif [ -t 0 ]; then
      sh "$SRC/secret" put "$REFNAME" || { mv -f "$__old" "$REG"; fail "storing '$REFNAME' failed, so the entry was rolled back" "check the credential store (bin/secret help)" 1; }
    else
      log_note "the entry names '$REFNAME' but no value was stored (stdin is not a terminal and no --value-stdin): run: secret put $REFNAME"
    fi
  fi
  rm -f "$__old"
  unlock_register
  # The id, never the command: a probe line is the one field a credential could be typed into.
  if [ -n "$PROBE" ]; then
    if sh -c "$PROBE" < /dev/null > /dev/null 2>&1; then log_ok "probe passed for '$ID'"
    else log_fail "probe failed for '$ID'"; log_fix "the entry is kept; fix the access, then rerun the probe"; log_end || :; exit 1; fi
  fi
  log_end || :
}

# ── LIFECYCLE: status, rotate, revoke ────────────────────────────────────────────────────────────────────
# One writer at a time. mkdir is atomic on every filesystem this runs on; a lock left by a killed writer is
# named in the failure, never broken silently.
REG_LOCK=''
lock_register() { # <register file> [soft] - soft returns 1 on a timeout instead of exiting
  __lk="$1.lock"; __n=0
  until mkdir "$__lk" 2>/dev/null; do
    __n=$((__n + 1))
    [ "$__n" -lt "${ACCESS_LOCK_WAIT:-30}" ] || { [ "${2:-}" != soft ] || return 1
      fail "$1 is locked by another harbor access write" "wait for it; if no harbor access is running, rmdir $__lk" 1; }
    sleep 1
  done
  REG_LOCK="$__lk"
  trap 'unlock_register' EXIT
  trap 'unlock_register; exit 130' INT TERM HUP
}
unlock_register() { [ -z "$REG_LOCK" ] || rmdir "$REG_LOCK" 2>/dev/null || :; REG_LOCK=''; }

# Set one DATE field of one entry, in place: replaced where it is, else added after the entry's last field.
# Dates only, so no value can carry what awk -v would unescape. The caller holds the lock.
set_date() { # <register> <id> <field> <YYYY-MM-DD>
  case "$4" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;; *) return 1 ;; esac
  # FNR == 1 counts the passes: NR == FNR is also true in the second pass when the first file is empty.
  awk -v id="$2" -v f="$3" -v v="$4" '
    FNR == 1 { pass++ }
    pass == 1 {
      if ($0 ~ /^## /) { cur = $0; sub(/^## +/, "", cur); sub(/[ \t\r]+$/, "", cur); next }
      if (cur == id && $0 ~ /^[ \t]+[A-Za-z_][A-Za-z0-9_-]*:/) {
        last = FNR; n = $0; sub(/^[ \t]+/, "", n); sub(/:.*/, "", n); if (n == f) at = FNR
      }
      next
    }
    !last { exit 3 }
    FNR == at { printf "    %s: %s\n", f, v; next }
    { print }
    FNR == last && !at { printf "    %s: %s\n", f, v }' "$1" "$1" > "$1.new.$$" || { rm -f "$1.new.$$"; return 1; }
  mv -f "$1.new.$$" "$1"
}

entry_field() { # <rows file> <id> <field> - the value, empty when absent
  awk -F'\t' -v i="$2" -v f="$3" '$1 == "R" && $2 == i && $3 == f { print $4; exit }' "$1"
}

# The refs the store holds, one per line. Exit 2 when it cannot be listed: that is never "nothing stored".
store_refs() {
  __so="$(sh "$SRC/secret" list 2>/dev/null)" || return 2
  printf '%s\n' "$__so" | awk '{ print $1 }' | sed -n 's/^secret\.//p' | sort -u
}

# Is each credential stored, alive and in date? Read-only on the register. What it prints is what is WRONG,
# each with the day it was first seen so (a state file outside git keeps those days), and one tally line;
# -v prints every entry. Exit 1 on any red, 2 when the store or the register cannot be read.
# --json (harbor#1480) prints the same facts as ONE object on stdout, every entry, same ids, same exit codes:
#   {"ts":ISO,"entries":[{"id","kind","state","stored","alive","expires","days_left","problem","since"}]}
# state is ok | dead | expiring | expired | unstored | unknown (unprobed, undecided, held, unmanaged, n/a, revoked and a
# check with no verdict are unknown; alive is true or false only when a check ran and decided). problem is the text mode's
# reason on a red or expiring entry, else null. since is the day that state was first seen (YYYY-MM-DD). No field is read
# from the credential store but its NAMES; a value, and a check's output, never reach it.
cmd_status() {
  __verbose=0; __json=0
  while [ $# -gt 0 ]; do case "$1" in -v) __verbose=1; shift ;; --json) __json=1; shift ;; -*) usage ;; *) break ;; esac; done
  if [ "$__json" = 1 ] && ! command -v jq >/dev/null 2>&1; then fail "jq is required for --json" "$(pkg_hint jq)" 2; fi
  __rf="$(register_file)" || { printf 'access status: no access register, so NOTHING was checked and this is not a pass.\n' >&2; exit 2; }
  [ -f "$__rf" ] || { printf 'access status: %s does not exist, so NOTHING was checked and this is not a pass.\n' "$__rf" >&2; exit 2; }
  [ -f "$PROBE_RUNNER" ] || fail "no probe runner at $PROBE_RUNNER, so NOTHING was probed and this is not a pass" "restore skills/access-ledger" 2
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  trap 'rm -rf "$__tmp"' EXIT
  trap 'exit 130' INT TERM HUP
  parse "$__rf" > "$__tmp/rows"
  store_refs > "$__tmp/stored" || fail "bin/secret list failed, so NOTHING was compared and this is not a pass" "run: secret list" 2
  if [ $# -gt 0 ]; then printf '%s\n' "$@"; else awk -F'\t' '$1 == "N" { print $2 }' "$__tmp/rows"; fi > "$__tmp/ids"
  __today="$(today)"
  : > "$__tmp/out"; : > "$__tmp/meta"
  while IFS= read -r __id; do
    [ -n "$__id" ] || continue
    awk -F'\t' -v i="$__id" '$1 == "N" && $2 == i { f = 1 } END { exit !f }' "$__tmp/rows" \
      || fail "no entry '$__id' in the register" "harbor access list" 2
    __kind="$(entry_field "$__tmp/rows" "$__id" kind)"; __ref="$(entry_field "$__tmp/rows" "$__id" secret)"
    __chk="$(entry_field "$__tmp/rows" "$__id" check)"; __exp="$(entry_field "$__tmp/rows" "$__id" expect)"
    __exps="$(entry_field "$__tmp/rows" "$__id" expires)"
    __has_rev=0; awk -F'\t' -v i="$__id" '$1 == "R" && $2 == i && $3 == "revoked" { f = 1 } END { exit !f }' "$__tmp/rows" && __has_rev=1
    __stored=0; [ "$__ref" = none ] || [ -z "$__ref" ] || ! grep -qxF -- "$__ref" "$__tmp/stored" || __stored=1
    # The worst state wins: red, then warn, then a gap, then ok or n/a.
    __st=''; __why=''; __alive=''; __left=''
    if [ "$__has_rev" = 1 ]; then
      if [ "$__stored" = 1 ]; then __st=REVOKED-STORED; __why="revoked, but secret.$__ref is still stored: secret rm $__ref"
      else __st=revoked; __why="retired"; fi
    else
      if [ "$__ref" != none ] && [ "$__stored" = 0 ]; then __st=MISSING; __why="secret.$__ref is not in the store"; fi
      if [ -n "$__exps" ]; then
        case "$__exps" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) __left="$(awk -v d="$__exps" -v t="$__today" "BEGIN { if (!okdate(d)) { print \"x\"; exit } print dayno(d) - dayno(t) } $AWK_DATES")" ;;
          *) __left=x ;;   # check names a malformed date; status does not guess at it
        esac
        case "$__left" in
          x) : ;;
          -*) [ -n "$__st" ] || { __st=EXPIRED; __why="expired $__exps"; } ;;
          *) if [ "$__left" -le 14 ] && [ -z "$__st" ]; then __st=expiring; __why="expires $__exps, in $__left days"; fi ;;
        esac
      fi
      if [ -n "$__chk" ] && [ -z "$__st" ] || { [ -n "$__chk" ] && [ "$__st" = expiring ]; }; then
        __pv="$(PROBE_TIMEOUT="${PROBE_TIMEOUT:-30}" sh "$PROBE_RUNNER" --probe "$__chk" "$__exp" 2>/dev/null)" || :
        case "$__pv" in
          pass) __alive=true; [ -n "$__st" ] || { __st=ok; __why="check passed"; } ;;
          fail) __alive=false; __st=FAIL; __why="the check ran and its output lacks the expected literal" ;;
          timeout) __st=TIMEOUT; __why="the check did not finish in ${PROBE_TIMEOUT:-30}s" ;;
          refused) __st=REFUSED; __why="the check is not a read, so it was not run" ;;
          browser|manual|uncheckable) [ -n "$__st" ] || { __st=undecided; __why="the check is $__pv: not machine-decidable"; } ;;
          *) __st=FAIL; __why="the probe runner gave no verdict" ;;
        esac
      fi
      if [ -z "$__st" ]; then
        if [ "$__ref" != none ]; then __st=unprobed; __why="stored, but no check: says it still works"
        else
          __held="$(entry_field "$__tmp/rows" "$__id" held)"
          case "$__kind" in
            token|app) if [ -n "$__held" ]; then __st=held; __why="outside the seam by design: $__held"
                       else __st=unmanaged; __why="a credential the seam does not hold, and no held: says why: a migration debt"; fi ;;
            *) __st=n/a; __why="a sign-in or role with no check" ;;
          esac
        fi
      fi
      # A stored credential that cannot be renewed or retired by recipe is a gap even when it works today.
      if [ "$__ref" != none ] && { [ -z "$(entry_field "$__tmp/rows" "$__id" renew)" ] || [ -z "$(entry_field "$__tmp/rows" "$__id" revoke)" ]; }; then
        case "$__st" in ok|unprobed|undecided|expiring) __why="$__why; no renew:/revoke: recipe" ;; esac
      fi
    fi
    printf '%s\t%s\t%s\n' "$__id" "$__st" "$__why" >> "$__tmp/out"
    # For --json only: what the text line does not carry. A date or a number that is not one is null, never a guess.
    case "$__left" in ''|*[!0-9-]*|-) __left='' ;; esac
    [ -n "$__left" ] || __exps=''   # status could not read the date (okdate), so neither is reported
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$__id" "$__kind" "$__stored" "$__alive" "$__exps" "$__left" >> "$__tmp/meta"
  done < "$__tmp/ids"
  # The day each state was first seen: kept when the state is unchanged, today when it is new.
  mkdir -p "$(dirname "$STATE")" 2>/dev/null || :
  [ -f "$STATE" ] || : > "$STATE" 2>/dev/null || :
  awk -F'\t' -v t="$__today" 'FILENAME == ARGV[1] { since[$1, $2] = $3; next } { s = (($1, $2) in since) ? since[$1, $2] : t; print $1 "\t" $2 "\t" s "\t" $3 }' \
    "$STATE" "$__tmp/out" > "$__tmp/dated" 2>/dev/null || awk -F'\t' -v t="$__today" '{ print $1 "\t" $2 "\t" t "\t" $3 }' "$__tmp/out" > "$__tmp/dated"
  # Merge back: entries not probed this run keep their old line.
  { awk -F'\t' 'FILENAME == ARGV[1] { seen[$1] = 1; next } !($1 in seen)' "$__tmp/out" "$STATE" 2>/dev/null || :
    awk -F'\t' '{ print $1 "\t" $2 "\t" $3 }' "$__tmp/dated"; } > "$__tmp/state.new"
  mv -f "$__tmp/state.new" "$STATE" 2>/dev/null || log_warn "could not keep $STATE: every state reads as new today"
  if [ "$__json" = 1 ]; then
    # dated: id, state text, first-seen day, reason. meta: id, kind, stored (0|1), alive, expires, days_left. Joined on the id.
    awk -F'\t' -v OFS='\t' 'FILENAME == ARGV[1] { m[$1] = $0; next } { print $0, m[$1] }' "$__tmp/meta" "$__tmp/dated" \
      | jq -R -s -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
          { ts: $ts, entries: [ split("\n")[] | select(. != "") | split("\t") as $f
            | ($f[1]) as $st
            | { id: $f[0], kind: ($f[5] // ""),
                state: ({ok: "ok", MISSING: "unstored", EXPIRED: "expired", expiring: "expiring"}[$st] // (if $st == "FAIL" and $f[7] == "false" then "dead" else "unknown" end)),
                stored: ($f[6] == "1"),
                alive: (if $f[7] == "true" then true elif $f[7] == "false" then false else null end),
                expires: (if ($f[8] // "") == "" then null else $f[8] end),
                days_left: (if ($f[9] // "") == "" then null else ($f[9] | tonumber) end),
                problem: (if ($st | test("^[A-Z]")) or $st == "expiring" then $f[3] else null end),
                since: $f[2] } ] }' || fail "could not render the status as JSON" "check that jq works: jq --version" 2
  else
  awk -F'\t' -v v="$__verbose" -v t="$__today" "$AWK_DATES"'
    { st = $2; red = (st ~ /^[A-Z]/); warn = (st == "expiring")
      age = dayno(t) - dayno($3); when = (age == 0) ? "new today" : "since " $3 " (" age " day" (age == 1 ? "" : "s") ")"
      if (red || warn || v) printf "%-15s %-28s %s; %s\n", st, $1, $4, when
      n[st]++; total++; if (red) nred++ }
    END {
      printf "%d entries:", total
      split("ok expiring unprobed undecided held unmanaged n/a revoked", O, " ")
      for (i = 1; i in O; i++) if (n[O[i]]) printf " %d %s,", n[O[i]], O[i]
      printf " %d red\n", nred + 0
    }' "$__tmp/dated"
  fi
  ! awk -F'\t' '$2 ~ /^[A-Z]/ { f = 1 } END { exit !f }' "$__tmp/out"
}

# A new value for an entry's ref, kept only if the entry's check passes against it; else the old one is put
# back (bin/secret rotate). Then rotated: and verified: are today, and the entry's revoke: recipe is the
# operator's last step, since retiring the OLD value at its source is outside this box.
cmd_rotate() {
  [ $# -ge 1 ] || usage
  __id="$1"; shift; __vs=0
  __lock=''
  while [ $# -gt 0 ]; do case "$1" in --value-stdin) __vs=1; shift ;; --locked) __lock=--locked; shift ;; *) usage ;; esac; done
  REG="$(register_file)" || fail "no access register" "harbor scope install" 2
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install" 2
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  parse "$REG" > "$__tmp/rows"
  awk -F'\t' -v i="$__id" '$1 == "N" && $2 == i { f = 1 } END { exit !f }' "$__tmp/rows" || { rm -rf "$__tmp"; fail "no entry '$__id'" "harbor access list" 2; }
  # A register the grammar rejects (a repeated id, a bad heading) is one a date could be written into unread.
  ! grep -q '^E' "$__tmp/rows" || { rm -rf "$__tmp"; fail "the register does not parse cleanly, so nothing was rotated" "harbor access check, and fix what it names" 1; }
  __ref="$(entry_field "$__tmp/rows" "$__id" secret)"; __chk="$(entry_field "$__tmp/rows" "$__id" check)"
  __exp="$(entry_field "$__tmp/rows" "$__id" expect)"; __rv="$(entry_field "$__tmp/rows" "$__id" revoke)"
  __shape="$(entry_field "$__tmp/rows" "$__id" value-shape)"
  __revd=0; awk -F'\t' -v i="$__id" '$1 == "R" && $2 == i && $3 == "revoked" { f = 1 } END { exit !f }' "$__tmp/rows" && __revd=1
  rm -rf "$__tmp"
  [ -n "$__ref" ] && [ "$__ref" != none ] || fail "'$__id' names no secret ref, so there is no value to rotate" "a sign-in is renewed where it lives" 2
  [ "$__revd" = 0 ] || fail "'$__id' is revoked" "to re-issue, delete its revoked: line by hand (a deliberate edit), or add a new entry" 1
  [ -n "$__chk" ] && [ -n "$__exp" ] || fail "'$__id' has no check:/expect:, so a new value cannot be proved and nothing could be put back on a bad one" "add check: and expect: to the entry (or use secret put, which keeps no rollback)" 1
  # Only a runnable read can prove a new value; anything else would store it, fail, and put the old one back.
  [ -f "$PROBE_RUNNER" ] || fail "no probe runner at $PROBE_RUNNER, so a rotation cannot be proved" "restore skills/access-ledger" 2
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  __cls="$(sh "$PROBE_RUNNER" --classify "$__chk" "$__exp" 2>/dev/null)" || __cls=''
  [ "$__cls" = run ] || fail "'$__id' has a ${__cls:-unclassifiable} check, so a rotation cannot be proved here" "make its check a read that prints a backticked literal, or secret put $__ref and check it by hand" 1
  [ "$__vs" = 1 ] || [ -t 0 ] || fail "no value: stdin is not a terminal and --value-stdin was not given" "pipe the value in: <clipboard or file> | harbor access rotate $__id --value-stdin" 2
  __rc=0
  if [ "$__vs" = 1 ] && [ "$__shape" != verbatim ]; then
    __val="$(value_clean "$__id")" || exit 2
    # shellcheck disable=SC2086 # $__lock is empty or one word
    printf '%s' "$__val" | sh "$SRC/secret" rotate "$__ref" $__lock -- sh "$PROBE_RUNNER" --probe "$__chk" "$__exp" || __rc=$?
    __val=''
  else
    # shellcheck disable=SC2086 # $__lock is empty or one word
    sh "$SRC/secret" rotate "$__ref" $__lock -- sh "$PROBE_RUNNER" --probe "$__chk" "$__exp" || __rc=$?
  fi
  case "$__rc" in
    0) ;;
    1) fail "'$__id' was NOT rotated: its check failed against the new value, and the old one is back" "check the new value at its source, then rotate again" 1 ;;
    5) fail "'$__id' was NOT rotated: the new value could not be stored, and the old one is back" "read bin/secret's lines above (docs/how-to/harden-the-host.md)" 1 ;;
    *) fail "'$__id': bin/secret rotate exited $__rc; read its lines above before anything else" "docs/how-to/harden-the-host.md" "$__rc" ;;
  esac
  # The value is already kept: a busy or unwritable register costs the dates, never the rotation.
  if lock_register "$REG" soft && set_date "$REG" "$__id" rotated "$(today)" && set_date "$REG" "$__id" verified "$(today)"; then :
  else log_warn "the value is rotated, but $REG could not be dated: set rotated: and verified: to $(today) by hand"; fi
  unlock_register
  log_ok "rotated '$__id' ($__ref); rotated: and verified: are $(today)"
  if [ -n "$__rv" ]; then log_note "the OLD value still works at its source until you retire it: $__rv"
  else log_warn "'$__id' has no revoke: recipe; the OLD value still works at its source until someone retires it"; fi
  log_end || :
}

# Retire an entry: revoked: is written FIRST, so the ref is refused before the value goes (rm is ungated), and
# a failure between the two leaves a refused ref, never a live one. Retiring it at its source is the operator's.
# move <old-ref>: the D-36 migration of one ref, inside its renames row's window (harbor#978). The entry that names the
# old ref names the new one, then bin/secret copies the stored value to the new name in its own process (secret copy:
# never printed, proved by hash) and leaves the old item, which every reader still gets until remove_by. Reruns are
# safe: a moved entry is not moved again and a stored new value is not overwritten. Removing the old item is the
# operator's, once no reader asks for it: secret rm <old-ref>.
cmd_move() {
  [ $# -ge 1 ] || usage
  __old="$1"; shift; __lock=''
  while [ $# -gt 0 ]; do case "$1" in --locked) __lock=--locked; shift ;; *) usage ;; esac; done
  valid_ref "$__old" || fail "'$__old' is not a ref [A-Za-z0-9._-]+" "harbor access list" 2
  __row="$(rename_row "$__old")" || fail "no open secret rename names '$__old' (or its remove_by has passed)" "add a row to standards/naming/renames.tsv, or to the private <access>/renames.tsv for a name that carries a client" 2
  [ "$(printf '%s' "$__row" | cut -f1)" = "$__old" ] || fail "'$__old' is the new name of its rename; move takes the old one" "harbor access move $(printf '%s' "$__row" | cut -f1)" 2
  __new="$(printf '%s' "$__row" | cut -f2)"; __until="$(printf '%s' "$__row" | cut -f3)"
  name_gate secret "$__new" renames_fix "$__new"
  REG="$(register_file)" || fail "no access register" "harbor scope install" 2
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install" 2
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  lock_register "$REG"
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  parse "$REG" > "$__tmp/rows"
  ! grep -q '^E' "$__tmp/rows" || { rm -rf "$__tmp"; fail "the register does not parse cleanly, so nothing was moved" "harbor access check, and fix what it names" 1; }
  __io="$(awk -F'\t' -v r="$__old" '$1 == "R" && $3 == "secret" && $4 == r { print $2; exit }' "$__tmp/rows")"
  __in="$(awk -F'\t' -v r="$__new" '$1 == "R" && $3 == "secret" && $4 == r { print $2; exit }' "$__tmp/rows")"
  rm -rf "$__tmp"
  [ -n "$__io$__in" ] || fail "no entry names $__old or $__new" "register it under the new name, storing nothing: harbor access add <id> --kind ... --secret $__new < /dev/null; then rerun" 1
  [ -z "$__io" ] || [ -z "$__in" ] || fail "two entries name the pair: $__io names $__old and $__in names $__new" "merge them into one entry, then rerun" 1
  __back="$REG.move.$$"; __moved=0
  if [ -n "$__io" ]; then
    cp "$REG" "$__back"
    # The ref is [A-Za-z0-9._-]+ (valid_ref, and the renames row passed the lint), so -v carries nothing awk unescapes.
    awk -v id="$__io" -v o="$__old" -v n="$__new" '
      /^## / { cur = $0; sub(/^## +/, "", cur); sub(/[ \t]+$/, "", cur) }
      cur == id && $0 ~ /^[ \t]+secret:[ \t]/ { v = $0; sub(/^[ \t]+secret:[ \t]*/, "", v); sub(/[ \t]+$/, "", v); if (v == o) { sub(/secret:.*/, "secret: " n) } }
      { print }' "$REG" > "$REG.new.$$" && mv -f "$REG.new.$$" "$REG"
    reg_state "$__new" || { mv -f "$__back" "$REG"; fail "the entry $__io still does not name $__new, so nothing was moved" "harbor access check" 1; }
    __moved=1; log_ok "the entry $__io names $__new now (was $__old)"
  else log_note "the entry $__in already names $__new"; fi
  unlock_register
  __sr="$(store_refs)" || { [ "$__moved" = 0 ] || mv -f "$__back" "$REG"; fail "bin/secret list failed, so the value was not copied and the entry was put back" "secret list; then rerun" 2; }
  if printf '%s\n' "$__sr" | grep -qxF -- "$__new"; then log_note "secret.$__new holds a value already; nothing was copied"
  elif printf '%s\n' "$__sr" | grep -qxF -- "$__old"; then
    # shellcheck disable=SC2086 # $__lock is empty or one word
    sh "$SRC/secret" copy "$__old" "$__new" $__lock || { [ "$__moved" = 0 ] || mv -f "$__back" "$REG"; fail "copying secret.$__old to secret.$__new failed, so the entry was put back" "secret list; then rerun" 1; }
  else log_note "nothing is stored under $__old or $__new: store the value with harbor access rotate $__io$__in, or secret put $__new"; fi
  rm -f "$__back"
  log_note "secret.$__old is kept and read in place of $__new only while $__new holds nothing, until $__until; once no reader asks for $__old: secret rm $__old"
  log_end || :
}

cmd_revoke() {
  [ $# -eq 1 ] || usage
  __id="$1"
  REG="$(register_file)" || fail "no access register" "harbor scope install" 2
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install" 2
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  parse "$REG" > "$__tmp/rows"
  awk -F'\t' -v i="$__id" '$1 == "N" && $2 == i { f = 1 } END { exit !f }' "$__tmp/rows" || { rm -rf "$__tmp"; fail "no entry '$__id'" "harbor access list" 2; }
  ! grep -q '^E' "$__tmp/rows" || { rm -rf "$__tmp"; fail "the register does not parse cleanly, so nothing was revoked" "harbor access check, and fix what it names" 1; }
  __ref="$(entry_field "$__tmp/rows" "$__id" secret)"; __rv="$(entry_field "$__tmp/rows" "$__id" revoke)"
  __was="$(entry_field "$__tmp/rows" "$__id" revoked)"
  rm -rf "$__tmp"
  if [ -n "$__was" ]; then log_note "'$__id' was revoked already ($__was)"
  else
    lock_register "$REG"
    set_date "$REG" "$__id" revoked "$(today)" || fail "could not write revoked: into $REG, so nothing was removed" "check the file, then revoke again" 1
    unlock_register
    # Proved by the gate's own reader, not by the write: the value is removed only once the ref is refused.
    case "$__ref" in ''|none) ;; *) __hs=0; has_ref "$__ref" || __hs=$?
      [ "$__hs" = 4 ] || fail "revoked: was written, but has $__ref still says $__hs, so nothing was removed" "harbor access check" 1 ;; esac
    case "$__ref" in ''|none) log_ok "'$__id' is revoked (it names no stored value; commit the register so other checkouts agree)" ;;
      *) log_ok "'$__id' is revoked: bin/secret refuses $__ref from now on (commit the register so other checkouts agree)" ;; esac
  fi
  if [ -n "$__ref" ] && [ "$__ref" != none ]; then
    __sr="$(store_refs)" || fail "bin/secret list failed, so whether secret.$__ref is still stored is unknown" "secret list; then secret rm $__ref" 2
    if printf '%s\n' "$__sr" | grep -qxF -- "$__ref"; then
      sh "$SRC/secret" rm "$__ref" || fail "secret.$__ref is still stored" "secret rm $__ref" 1
    else log_note "nothing was stored under secret.$__ref"; fi
    # The other name of a renamed ref holds the same credential (harbor#978): it goes with it.
    if __tw="$(cmd_renamed "$__ref" | cut -f2)" && [ -n "$__tw" ] && printf '%s\n' "$__sr" | grep -qxF -- "$__tw"; then
      sh "$SRC/secret" rm "$__tw" || fail "secret.$__tw, the renamed twin of $__ref, is still stored" "secret rm $__tw" 1
    fi
  fi
  if [ -n "$__rv" ]; then log_note "retire it at its source too: $__rv"
  else log_warn "'$__id' has no revoke: recipe; the value still works at its source until someone retires it there"; fi
  log_end || :
}

VERB="${1:-}"; [ $# -eq 0 ] || shift
# --json is status'"'"'s alone (harbor#1480): `harbor access` is a json-passing verb, so any other verb must refuse the flag
# rather than ignore it, or a caller parsing the output could not tell "no data" from "not supported".
if [ "$VERB" != status ]; then
  for _a in "$@"; do [ "$_a" != --json ] || fail "'$VERB' has no --json; only status does" "harbor access status --json" 2; done
fi
case "$VERB" in
  add) cmd_add "$@" ;;
  list) cmd_list ;;
  has) cmd_has "$@" ;;
  refs) cmd_refs ;;
  check) cmd_check ;;
  stored) cmd_stored "$@" ;;
  status) cmd_status "$@" ;;
  rotate) cmd_rotate "$@" ;;
  revoke) cmd_revoke "$@" ;;
  renamed) cmd_renamed "$@" ;;
  move) cmd_move "$@" ;;
  -h|--help|help|'') usage ;;
  *) fail "unknown verb '$VERB'" "harbor access --help" 2 ;;
esac
