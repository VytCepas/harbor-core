#!/usr/bin/env sh
# access.sh (harbor#1205, harbor#1149) - `harbor access`: the access register, the one list of every identity an
# agent may use, and the only door to a secret's name. CONTRACTS/access-register.md is the format.
#
#   harbor access add <id> --kind K --what T --use-when T --reaches T --cannot T --grant T
#                          (--secret REF | --no-secret) [--value-stdin] [--probe CMD]
#   harbor access list                    the entries: id, kind, secret ref, what
#   harbor access has <ref>               exit 0 registered, 3 grandfathered (CONTRACTS/secret-legacy-refs.txt), 1 neither
#   harbor access refs                    the registered secret refs, one per line
#   harbor access check                   is the register well formed, and free of a credential value
#   harbor access stored                  every item bin/secret holds, and whether an entry names it (exit 1 if not)
#
# add records an entry, then stores the value through bin/secret (the ref must be registered first, so it is written
# before the store and rolled back when the store fails). The value is read from stdin with --value-stdin, or by
# bin/secret's own prompt on a terminal; it is never an argument. A missing field is asked for on a terminal and a
# usage error (exit 2) elsewhere. --probe runs CMD after the store: a failing probe exits 1 and keeps the entry.
# With no private layer the register is empty: every ref is unregistered, add refuses, list prints nothing.
set -eu
LC_ALL=C; export LC_ALL   # [a-z] below means ASCII lower case, whatever the caller's locale

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}"
. "$SRC/log-lib.sh"
log_init access
LOG_FD=2
GREP=/usr/bin/grep   # grep here is ugrep on the operator's box; BSD semantics are the contract
LEGACY="${ACCESS_LEGACY_REFS:-$ROOT/CONTRACTS/secret-legacy-refs.txt}"
PATTERNS="${ACCESS_CREDENTIAL_PATTERNS:-$ROOT/CONTRACTS/credential-patterns.tsv}"
KINDS='account role app mailbox token'
FIELDS='kind what use-when reaches cannot grant secret verified'
REQUIRED='kind what use-when reaches cannot grant secret verified'

fail() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-1}"; }
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

# The register file: <access dir>/register.md. Empty stdout and exit 1 when there is no register directory.
register_file() {
  __d="$(sh "$SRC/roots.sh" --access 2>/dev/null)" || return 1
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

has_ref() { # <ref> - exit 0 registered, 3 grandfathered, 1 neither. Silent.
  __ref="$1"
  __rf="$(register_file)" || __rf=""
  if [ -n "$__rf" ] && [ -f "$__rf" ]; then
    if parse "$__rf" | awk -F'\t' -v r="$__ref" '$1 == "R" && $3 == "secret" && $4 == r && r != "none" { f = 1 } END { exit !f }'; then return 0; fi
  fi
  if [ -f "$LEGACY" ] && awk -v r="$__ref" '/^[[:space:]]*(#|$)/ { next } $1 == r { f = 1 } END { exit !f }' "$LEGACY"; then return 3; fi
  return 1
}

today() { date -u +%Y-%m-%d; }
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
  __rf="$(register_file)" || { printf 'access check: no access register, so NOTHING was checked and this is not a pass.\n' >&2; printf '              Create the private layer first (harbor scope install, CONTRACTS/private-layer.md).\n' >&2; exit 2; }
  [ -f "$__rf" ] || { printf 'access check: %s does not exist, so NOTHING was checked and this is not a pass.\n' "$__rf" >&2; exit 2; }
  __tmp="$(mktemp -d "${TMPDIR:-/tmp}/access.XXXXXX")" || exit 2
  trap 'rm -rf "$__tmp"' EXIT INT TERM
  parse "$__rf" > "$__tmp/rows"
  __bad=0
  # The grammar's own problems.
  while IFS="$(printf '\t')" read -r _t _m; do
    [ "$_t" = E ] || continue
    log_fail "${__rf##*/} $_m"; log_fix "fix the line in $__rf (CONTRACTS/access-register.md)"; __bad=1
  done < "$__tmp/rows"
  # Required fields, the kind enum, the secret ref shape, the date, and a ref named by one entry only.
  awk -F'\t' -v req="$REQUIRED" -v all="$FIELDS" -v kinds="$KINDS" '
    BEGIN { nr = split(req, R, " "); na = split(all, A, " "); nk = split(kinds, K, " ") }
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
      }
    }' "$__tmp/rows" > "$__tmp/problems"
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    log_fail "${__rf##*/} $_p"; log_fix "fix the entry in $__rf (CONTRACTS/access-register.md)"; __bad=1
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
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind|--what|--use-when|--reaches|--cannot|--grant|--secret|--probe)
        [ $# -ge 2 ] || { log_fail "$1 needs a value"; log_fix "harbor access add --help"; log_end || :; exit 2; }
        case "$1" in
          --kind) KIND="$2" ;; --what) WHAT="$2" ;; --use-when) USEWHEN="$2" ;; --reaches) REACHES="$2" ;;
          --cannot) CANNOT="$2" ;; --grant) GRANT="$2" ;; --secret) REFNAME="$2" ;; --probe) PROBE="$2" ;;
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
  case " $KINDS " in *" $KIND "*) ;; *) fail "kind '$KIND' is not one of: $KINDS" "use one of them" 2 ;; esac
  [ "$REFNAME" = none ] || valid_ref "$REFNAME" || fail "secret ref '$REFNAME' is not [A-Za-z0-9._-]+" "use a plain reference, never the value" 2
  # A value pasted into a field is the mistake this refuses: no field may be shaped like a credential.
  if [ -f "$PATTERNS" ]; then
    awk -F'\t' '/^[[:space:]]*(#|$)/ { next } $1 == "id" { next } NF >= 2 { print $2 }' "$PATTERNS" > "${TMPDIR:-/tmp}/access-pats.$$"
    if printf '%s\n' "$WHAT" "$USEWHEN" "$REACHES" "$CANNOT" "$GRANT" "$REFNAME" | "$GREP" -qE -f "${TMPDIR:-/tmp}/access-pats.$$"; then
      rm -f "${TMPDIR:-/tmp}/access-pats.$$"
      fail "a field is shaped like a credential value; a register holds references, never values" "pipe the value with --value-stdin instead" 2
    fi
    rm -f "${TMPDIR:-/tmp}/access-pats.$$"
  fi
  REG="$(register_file)" || fail "no access register: there is no private layer to write one in" "harbor scope install" 1
  [ ! -L "$REG" ] || fail "$REG is a symlink; refusing to write through it" "replace it with a plain file" 1
  [ -f "$REG" ] || fail "$REG does not exist" "harbor scope install (it creates the register with a header only)" 1
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
  if [ -n "$PROBE" ]; then
    if sh -c "$PROBE" < /dev/null > /dev/null 2>&1; then log_ok "probe passed: $PROBE"
    else log_fail "probe failed: $PROBE"; log_fix "the entry is kept; fix the access, then rerun the probe"; log_end || :; exit 1; fi
  fi
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
  -h|--help|help|'') usage ;;
  *) fail "unknown verb '$VERB'" "harbor access --help" 2 ;;
esac
