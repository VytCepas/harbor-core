#!/usr/bin/env sh
# access.sh (harbor#1205, harbor#1149) - `harbor access`: the access register, the one list of every identity an
# agent may use, and the only door to a secret's name. contracts/access-register.md is the format.
#
#   harbor access add <id> --kind K --what T --use-when T --reaches T --cannot T --grant T
#                          (--secret REF | --no-secret) [--value-stdin] [--probe CMD]
#                          [--check CMD --expect T] [--expires YYYY-MM-DD] [--renew T] [--revoke T]
#   harbor access list                    the entries: id, kind, secret ref, what
#   harbor access has <ref>               exit 0 registered, 3 grandfathered (contracts/secret-legacy-refs.txt), 4 revoked, 1 neither
#   harbor access refs                    the registered secret refs, one per line
#   harbor access check                   is the register well formed, and free of a credential value
#   harbor access stored                  every item bin/secret holds, and whether an entry names it (exit 1 if not)
#   harbor access status [-v] [id...]     is each credential stored, alive, in date: what is wrong, and since when
#   harbor access rotate <id> [--value-stdin] [--locked]   a new value, kept only if the entry's check passes on it
#   harbor access revoke <id>             retire an entry: refuse its ref from now on, and remove the stored value
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
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
. "$SRC/library-log.sh"
log_init access
LOG_FD=2
GREP=/usr/bin/grep   # grep here is ugrep on the operator's box; BSD semantics are the contract
LEGACY="${ACCESS_LEGACY_REFS:-$ROOT/contracts/secret-legacy-refs.txt}"
PATTERNS="${ACCESS_CREDENTIAL_PATTERNS:-$ROOT/contracts/credential-patterns.tsv}"
KINDS='account role app mailbox token'
FIELDS='kind what use-when reaches cannot grant secret verified check expect expires renew revoke rotated revoked'
DATE_FIELDS='expires rotated revoked'
PROBE_RUNNER="$ROOT/skills/access-ledger/bin/check-routes.sh"
STATE="${ACCESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/harbor/access-status.tsv}"
REQUIRED='kind what use-when reaches cannot grant secret verified'

fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

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

has_ref() { # <ref> - exit 0 registered, 3 grandfathered, 4 revoked, 1 neither. Silent.
  __ref="$1"
  __rf="$(register_file)" || __rf=""
  if [ -n "$__rf" ] && [ -f "$__rf" ]; then
    # Any entry naming the ref with a revoked: line, whatever its value, refuses it, and the legacy list is
    # never consulted for it: a revoked ref that was also grandfathered must not come back through the list.
    __hs=0
    parse "$__rf" | awk -F'\t' -v r="$__ref" '
      $1 == "R" && $3 == "secret" && $4 == r && r != "none" { named[$2] = 1 }
      $1 == "R" && $3 == "revoked" { rev[$2] = 1 }
      END { st = 1; for (i in named) { if (i in rev) { st = 4; break } st = 0 } exit st }' || __hs=$?
    case "$__hs" in 0) return 0 ;; 4) return 4 ;; esac
  fi
  if [ -f "$LEGACY" ] && awk -v r="$__ref" '/^[[:space:]]*(#|$)/ { next } $1 == r { f = 1 } END { exit !f }' "$LEGACY"; then return 3; fi
  return 1
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
        if (h[id, "expect"] && v[id, "expect"] !~ /`[^`]+`/) printf "%s: expect carries no backticked literal, so no check can pass on it\n", id
      }
    }' "$__tmp/rows" > "$__tmp/problems"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    log_fail "${__rf##*/} $_p"; log_fix "fix the entry in $__rf (contracts/access-register.md)"; __bad=1
  done < "$__tmp/problems"
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
      0) printf 'registered\t%s\n' "$__svc" ;;
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
  CHECK=''; EXPECT=''; EXPIRES=''; RENEW=''; REVOKE=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind|--what|--use-when|--reaches|--cannot|--grant|--secret|--probe|--check|--expect|--expires|--renew|--revoke)
        [ $# -ge 2 ] || { log_fail "$1 needs a value"; log_fix "harbor access add --help"; log_end || :; exit 2; }
        case "$1" in
          --kind) KIND="$2" ;; --what) WHAT="$2" ;; --use-when) USEWHEN="$2" ;; --reaches) REACHES="$2" ;;
          --cannot) CANNOT="$2" ;; --grant) GRANT="$2" ;; --secret) REFNAME="$2" ;; --probe) PROBE="$2" ;;
          --check) CHECK="$2" ;; --expect) EXPECT="$2" ;; --expires) EXPIRES="$2" ;; --renew) RENEW="$2" ;;
          --revoke) REVOKE="$2" ;;
        esac
        shift 2 ;;
      --no-secret) NOREF=1; shift ;;
      --value-stdin) VALSTDIN=1; shift ;;
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
  __missing=''
  for __f in KIND WHAT USEWHEN REACHES CANNOT GRANT; do
    eval "__v=\${$__f}"; [ -n "$__v" ] || __missing="$__missing $__f"
  done
  [ -n "$REFNAME" ] || [ "$NOREF" = 1 ] || __missing="$__missing SECRET(--secret|--no-secret)"
  [ -z "$__missing" ] || fail "missing:$__missing" "give every field as a flag (harbor access add --help)" 2
  [ -z "$REFNAME" ] || [ "$NOREF" = 0 ] || fail "--secret and --no-secret together" "give one" 2
  [ "$VALSTDIN" = 0 ] || [ -n "$REFNAME" ] || fail "--value-stdin needs --secret <ref>" "name the ref the value is stored under" 2
  [ -n "$REFNAME" ] || REFNAME=none
  for __f in "$KIND" "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$ID"; do
    one_line "$__f" || fail "a field must be one non-empty line with no tab" "shorten it to a single line" 2
  done
  for __f in "$CHECK" "$EXPECT" "$EXPIRES" "$RENEW" "$REVOKE" "$PROBE"; do
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
    if printf '%s\n' "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$REFNAME" "$CHECK" "$EXPECT" "$RENEW" "$REVOKE" "$PROBE" \
        | "$GREP" -qE -f "${TMPDIR:-/tmp}/access-pats.$$"; then
      rm -f "${TMPDIR:-/tmp}/access-pats.$$"
      fail "a field is shaped like a credential value; a register holds references, never values" "pipe the value with --value-stdin instead" 2
    fi
    rm -f "${TMPDIR:-/tmp}/access-pats.$$"
  fi
  REG="$(register_file)" || fail "no access register: there is no private layer to write one in" "harbor scope install" 1
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install (it creates the register with a header only)" 1
  lock_register "$REG"
  parse "$REG" | awk -F'\t' -v i="$ID" '$1 == "N" && $2 == i { f = 1 } END { exit !f }' && fail "the entry '$ID' already exists" "pick another id, or edit $REG" 1
  if [ "$REFNAME" != none ]; then
    cmd_refs | grep -qxF -- "$REFNAME" && fail "the secret ref '$REFNAME' is already named by another entry" "one entry names a ref" 1
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
    if [ "$REFNAME" != none ] && { [ "$VALSTDIN" = 1 ] || [ -t 0 ]; }; then printf '    rotated: %s\n' "$(today)"; fi
  } > "$__new"
  mv -f "$__new" "$REG"
  log_ok "registered '$ID' ($KIND) in $REG"
  if [ "$REFNAME" != none ]; then
    # The ref is registered, so bin/secret admits it. A failed store leaves nothing behind.
    if [ "$VALSTDIN" = 1 ]; then
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
cmd_status() {
  __verbose=0
  while [ $# -gt 0 ]; do case "$1" in -v) __verbose=1; shift ;; -*) usage ;; *) break ;; esac; done
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
  : > "$__tmp/out"
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
    __st=''; __why=''
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
          pass) [ -n "$__st" ] || { __st=ok; __why="check passed"; } ;;
          fail) __st=FAIL; __why="the check ran and its output lacks the expected literal" ;;
          timeout) __st=TIMEOUT; __why="the check did not finish in ${PROBE_TIMEOUT:-30}s" ;;
          refused) __st=REFUSED; __why="the check is not a read, so it was not run" ;;
          browser|manual|uncheckable) [ -n "$__st" ] || { __st=undecided; __why="the check is $__pv: not machine-decidable"; } ;;
          *) __st=FAIL; __why="the probe runner gave no verdict" ;;
        esac
      fi
      if [ -z "$__st" ]; then
        if [ "$__ref" != none ]; then __st=unprobed; __why="stored, but no check: says it still works"
        else case "$__kind" in token|app) __st=unmanaged; __why="a credential the seam does not hold, with no check" ;; *) __st=n/a; __why="a sign-in or role with no check" ;; esac
        fi
      fi
      # A stored credential that cannot be renewed or retired by recipe is a gap even when it works today.
      if [ "$__ref" != none ] && { [ -z "$(entry_field "$__tmp/rows" "$__id" renew)" ] || [ -z "$(entry_field "$__tmp/rows" "$__id" revoke)" ]; }; then
        case "$__st" in ok|unprobed|undecided|expiring) __why="$__why; no renew:/revoke: recipe" ;; esac
      fi
    fi
    printf '%s\t%s\t%s\n' "$__id" "$__st" "$__why" >> "$__tmp/out"
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
  awk -F'\t' -v v="$__verbose" -v t="$__today" "$AWK_DATES"'
    { st = $2; red = (st ~ /^[A-Z]/); warn = (st == "expiring")
      age = dayno(t) - dayno($3); when = (age == 0) ? "new today" : "since " $3 " (" age " day" (age == 1 ? "" : "s") ")"
      if (red || warn || v) printf "%-15s %-28s %s; %s\n", st, $1, $4, when
      n[st]++; total++; if (red) nred++ }
    END {
      printf "%d entries:", total
      split("ok expiring unprobed undecided unmanaged n/a revoked", O, " ")
      for (i = 1; i in O; i++) if (n[O[i]]) printf " %d %s,", n[O[i]], O[i]
      printf " %d red\n", nred + 0
    }' "$__tmp/dated"
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
  # shellcheck disable=SC2086 # $__lock is empty or one word
  sh "$SRC/secret" rotate "$__ref" $__lock -- sh "$PROBE_RUNNER" --probe "$__chk" "$__exp" || __rc=$?
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
  fi
  if [ -n "$__rv" ]; then log_note "retire it at its source too: $__rv"
  else log_warn "'$__id' has no revoke: recipe; the value still works at its source until someone retires it there"; fi
  log_end || :
}

VERB="${1:-}"; [ $# -eq 0 ] || shift
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
  -h|--help|help|'') usage ;;
  *) fail "unknown verb '$VERB'" "harbor access --help" 2 ;;
esac
