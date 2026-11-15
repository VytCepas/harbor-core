# tests/cli/keychain-stub.sh — a file-backed `security` first on PATH (SEC-0, harbor#724).
# Source after t_init. No case may reach the login Keychain: the Keychain is not under
# HOME, so the sandbox alone does not protect it. Items live under $KC_STUB/items, and
# every call is logged to $KC_STUB/argv.log, each argument closed by `|`.
KC_STUB="$T_TMP/kc"; mkdir -p "$KC_STUB/items"; : > "$KC_STUB/argv.log"; export KC_STUB
unset XDG_DATA_HOME  # `secret` keeps its blobs under it; the sandbox HOME must decide
cat > "$T_BIN/security" <<'KCSTUB'
#!/bin/sh
d="${KC_STUB:?KC_STUB is unset; the stub will not guess a store}"
{ for _a in "$@"; do printf '%s|' "$_a"; done; printf '\n'; } >> "$d/argv.log"
verb="${1:-}"; [ $# -gt 0 ] && shift
s=''; a=''; w=''; hasw=0; upd=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s|-a|-l|-T) [ $# -ge 2 ] || exit 2
                 case "$1" in -s) s="$2" ;; -a) a="$2" ;; esac; shift 2 ;;
    -w) hasw=1; if [ $# -ge 2 ]; then w="$2"; shift 2; else shift; fi ;;
    -U) upd=1; shift ;;
    *) shift ;;
  esac
done
f="$d/items/$s@$a"
case "$verb" in
  add-generic-password)
    [ -n "$w" ] || exit 0  # like the real tool: a bare -w prompts, stores nothing, exits 0
    if [ -e "$f" ] && [ "$upd" = 0 ]; then echo "security: the item already exists" >&2; exit 45; fi
    printf '%s' "$w" > "$f" ;;
  find-generic-password)
    [ -e "$f" ] || { echo "security: the item could not be found" >&2; exit 44; }
    if [ "$hasw" = 1 ]; then cat "$f"; echo; else printf 'keychain: "stub"\n'; fi ;;
  delete-generic-password)
    [ -e "$f" ] || { echo "security: the item could not be found" >&2; exit 44; }
    rm -f "$f" ;;
  dump-keychain)
    for _f in "$d/items"/*; do
      [ -e "$_f" ] || continue; _n="${_f##*/}"
      printf 'class: "genp"\nattributes:\n    "svce"<blob>="%s"\n' "${_n%@*}"
    done ;;
  *) echo "security stub: unsupported verb '$verb'" >&2; exit 1 ;;
esac
KCSTUB
chmod +x "$T_BIN/security"
[ "$(command -v security)" = "$T_BIN/security" ] \
  || { echo "keychain-stub: security is $(command -v security), not the stub; refusing to run" >&2; exit 2; }
