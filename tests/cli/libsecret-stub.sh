# tests/cli/libsecret-stub.sh — a file-backed `secret-tool` (libsecret) for the Linux cases (harbor#618).
# Source after t_init and linux-sim.sh: <dir> becomes a Linux PATH with no `security`, and this stub
# in it. Items live under $ST_STUB/items as <service>@<account>; every call is logged to
# $ST_STUB/argv.log, each argument closed by `|`. `search` prints values, as the real one does.
libsecret_stub() { # <linux-path-dir>
  ST_STUB="$T_TMP/st"; mkdir -p "$ST_STUB/items"; : > "$ST_STUB/argv.log"; export ST_STUB
  linux_path "$1" security secret-tool
  cat > "$1/secret-tool" <<'STSTUB'
#!/bin/sh
d="${ST_STUB:?ST_STUB is unset; the stub will not guess a store}"
{ for _a in "$@"; do printf '%s|' "$_a"; done; printf '\n'; } >> "$d/argv.log"
verb="${1:-}"; [ $# -gt 0 ] && shift
svc=''; acct=''; attrs=''
while [ $# -gt 0 ]; do
  case "$1" in
    --*) shift ;;
    *) [ $# -ge 2 ] || exit 2
       case "$1" in service) svc="$2" ;; account) acct="$2" ;; esac
       attrs="$attrs$1=$2 "; shift 2 ;;
  esac
done
f="$d/items/$svc@$acct"
case "$verb" in
  store) [ -n "$svc" ] || exit 2; cat > "$f"; printf '%s\n' "$attrs" > "$f.attrs" ;;
  lookup) [ -f "$f" ] || exit 1; cat "$f" ;;
  clear) rm -f "$f" "$f.attrs" ;;
  search)
    for _f in "$d/items"/*.attrs; do
      [ -f "$_f" ] || continue
      case " $(cat "$_f")" in *" $attrs"*) ;; *) continue ;; esac
      printf '[/1]\nlabel = x\nsecret = %s\n' "$(cat "${_f%.attrs}")"
      for _kv in $(cat "$_f"); do printf 'attribute.%s = %s\n' "${_kv%%=*}" "${_kv#*=}"; done
    done ;;
  *) echo "secret-tool stub: unsupported verb '$verb'" >&2; exit 1 ;;
esac
STSTUB
  chmod +x "$1/secret-tool"
}
