# stub-gh.sh (harbor#1278) — sourced by the hub suites after t_init: a `gh` that never touches the network.
#   stub_gh <fixture-dir>    puts a gh stub first on PATH; GH_LOG gets every call (and the body of --body-file)
# The fixture dir holds issues.json (the repo's issues, each with number, title, state, user.login, created_at),
# comments-<number>.json and repo.json. `gh api` answers from them and applies --jq with jq -r. GH_FAIL=1 makes api fail.
stub_gh() {
  GH_FIX="$1"; GH_LOG="$T_TMP/gh.log"; export GH_FIX GH_LOG; : > "$GH_LOG"
  cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
echo "gh $*" >> "$GH_LOG"
case "$1" in
  api)
    shift; jqe=""; url=""
    while [ $# -gt 0 ]; do
      case "$1" in --paginate) ;; --jq) jqe="$2"; shift ;; *) url="$1" ;; esac
      shift
    done
    [ -z "${GH_FAIL:-}" ] || { echo "stub gh: HTTP 502" >&2; exit 1; }
    case "$url" in
      repos/*/issues/*/comments*) n="${url#*/issues/}"; n="${n%%/*}"; out="$(cat "$GH_FIX/comments-$n.json")" ;;
      repos/*/issues\?state=open*) out="$(jq '[.[] | select(.state == "open")]' "$GH_FIX/issues.json")" ;;
      repos/*/issues\?*) out="$(cat "$GH_FIX/issues.json")" ;;
      repos/*) out="$(cat "$GH_FIX/repo.json")" ;;
      *) echo "stub gh: no fixture for $url" >&2; exit 1 ;;
    esac
    if [ -n "$jqe" ]; then printf '%s' "$out" | jq -r "$jqe"; else printf '%s\n' "$out"; fi ;;
  issue)
    prev=""
    for a in "$@"; do [ "$prev" = --body-file ] && sed 's/^/BODY: /' "$a" >> "$GH_LOG"; prev="$a"; done
    [ "$2" != create ] || echo "https://example.invalid/fixture/issues/900" ;;
esac
exit 0
EOF
  chmod +x "$T_BIN/gh"
}
