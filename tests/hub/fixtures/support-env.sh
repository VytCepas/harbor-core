# support-env.sh (harbor#1278) — a member root for the remote support suites, on board-env.sh's stub board. Sourced after t_init and board-env.sh.
#   se_up [policy jq edit]     the board, the real member-support.sh, a stub upterm, and managed settings that deny the relay
#   se_policy <jq edit>        rewrites and re-signs the policy, with a support block on the hub's own relay unless the edit removes it
#   se_run <steps...>          member-support.sh on a real terminal: each argument is one terminal_run step. SE_RC, SE_OUT
#   se_issue / se_id           the request just filed: its number, its id
# The stub upterm records its argv and env in $SE_UP, answers `session info` as a started session, and holds `host` open until it is stopped.
SE_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICiecex8Dq718eSe1CCLgLvDmI7AagvCtax7brPFWkh4 fixture-admin'
# The hub's own relay, as policy names it. There is no default relay (contracts/hub.md).
SE_RELAY=wss://relay.example
SE_RELAY_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEHgOIqSyRvRS2h4FU2jQDTiBjLst/FpdsBYa61VIpo4'
SE_UP="$T_TMP/upterm-calls"
SE_STEPS="$T_TMP/steps"

se_policy() {
  be_policy ".support = {keys: [\"$SE_KEY\"], relay: \"$SE_RELAY\", relay_key: \"$SE_RELAY_KEY\"} | ${1:-.}"
}
se_settings() { # <host...>: managed settings as the install writes them, one above the root
  jq -n --args '{env: {}, sandbox: {network: {deniedDomains: $ARGS.positional}}}' "$@" > "$BE_ROOT/../managed-settings.json"
}
se_stub_upterm() {
  # upterm runs under env -i, so the stub carries its own paths.
  { printf '#!/bin/sh\nSE_UP="%s"\n' "$SE_UP"; cat <<'EOF'
{ printf 'argv'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; env | sed 's/^/env /'; } >> "$SE_UP"
[ "${1:-}" != host ] || cp "$XDG_RUNTIME_DIR/../authorized_keys" "$SE_UP.keys" 2>/dev/null
[ "${1:-}" != host ] || cp "$XDG_RUNTIME_DIR/../known_hosts" "$SE_UP.known" 2>/dev/null
case "$1 ${2:-}" in
  'session info')
    [ -e "$SE_UP.confirmed" ] || exit 4
    printf '{"status":"ready","startConfirmed":true,"joinCommand":"upterm join ssh://%s@relay.example:443"}\n' "${SE_SID:-abc123:bm9kZQ==}" ;;
  'session stop') : > "$SE_UP.stopped" ;;
  host*)
    printf 'Start the session? [y/n] '
    IFS= read -r a
    [ "$a" = y ] || exit 0
    : > "$SE_UP.confirmed"
    i=0; while [ ! -e "$SE_UP.stopped" ] && [ "$i" -lt 400 ]; do sleep 0.1; i=$((i + 1)); done ;;
esac
exit 0
EOF
  } > "$BE_BIN/upterm"
  chmod +x "$BE_BIN/upterm"
}
se_up() {
  be_up
  cp "$T_ROOT/bin/member-support.sh" "$BE_BIN/"
  SE_SUPPORT="$BE_BIN/member-support.sh"
  se_stub_upterm
  se_settings uptermd.upterm.dev relay.example
  se_policy "${1:-.}"
  HARBOR_MEMBER_SUPPORT_POLL_SECONDS=1; HARBOR_MEMBER_SUPPORT_WAIT_SECONDS=20
  export SE_UP HARBOR_MEMBER_SUPPORT_POLL_SECONDS HARBOR_MEMBER_SUPPORT_WAIT_SECONDS
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_SSE_PORT
}
se_reset() {
  be_reset
  rm -f "$SE_UP" "$SE_UP".*
  se_settings uptermd.upterm.dev relay.example
  se_policy "${1:-.}"
  # A send just happened, so the events stay in the outbox where a case can read them.
  mkdir -p "$BE_HS"; date +%s > "$BE_HS/last-send"
}
se_run() {
  printf '%s\n' "$@" > "$SE_STEPS"
  SE_RC=0; python3 "$T_ROOT/tests/hub/fixtures/terminal_run.py" "$SE_STEPS" "$T_TMP/transcript" -- sh "$SE_SUPPORT" || SE_RC=$?
  SE_OUT="$(cat "$T_TMP/transcript")"
}
se_issue() { jq -r .number "$BE_ST/issues/1.json"; }
se_id() { jq -r '.title | sub("^support "; "")' "$BE_ST/issues/1.json"; }
# se_accept_soon [login] [delay]: a real admin's comment lands while the member waits, as it does on the board.
se_accept_soon() {
  (
    _i=0
    while [ ! -f "$BE_ST/issues/1.json" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
    sleep "${2:-0}"
    be_comment 1 "${1:-fixture-admin}" "accept $(se_id)"
  ) &
}
se_comments() { jq -r '.[].body' "$BE_ST/comments/1.json" 2>/dev/null; }
se_events() { jq -r 'select(.kind == "support") | .outcome' "$BE_HS/outbox.jsonl" 2>/dev/null | tr '\n' ' '; }
se_alive_steps() { printf '%s\n' 'expect Type update' 'send fix' 'expect the word allow' 'send allow'; }
