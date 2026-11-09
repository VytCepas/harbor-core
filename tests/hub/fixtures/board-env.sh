# board-env.sh (harbor#1278) — a fake managed root and a running stub board for the approval and events suites. Sourced after
# t_init. Copies the real scripts beside interface stubs of the other lanes (lanes.md), signs a policy with a throwaway key.
#   be_up [ttl-hours]   build it all and start the stub
#   be_seed_issue <id>  a valid open request issue from alice, printing its number
#   be_comment <issue> <login> <body> [created] [updated] [type]
#   be_rc <cmd...>      the exit code alone, output discarded
BE_ROOT="$T_TMP/managed"; BE_BIN="$BE_ROOT/bin"; BE_ST="$T_TMP/board"; BE_ID=r-0123456789abcdef
BE_TOKEN=fixture_token_123

be_rc() { "$@" >/dev/null 2>&1; echo $?; }
be_sign() { # <policy-file>: the signature beside it
  rm -f "$1.sig"
  ssh-keygen -Y sign -q -f "$T_TMP/signing/k" -n harbor-hub "$1" 2>/dev/null
}
be_policy() { # <jq edit>: rewrites and re-signs the last good policy
  jq "$1" "$T_ROOT/tests/hub/fixtures/policy.json" > "$T_TMP/state-policy.json"
  be_sign "$T_TMP/state-policy.json"
}
be_stub_sibling() { # <name> <body>
  printf '#!/bin/sh\n%s\n' "$2" > "$BE_BIN/$1"; chmod +x "$BE_BIN/$1"
}
be_up() {
  mkdir -p "$BE_BIN" "$BE_ST" "$T_TMP/signing"
  cp "$T_ROOT/bin/hub-board.sh" "$T_ROOT/bin/hub-approval.sh" "$T_ROOT/bin/hub-events.sh" "$T_ROOT/bin/library-hub.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/library-board.sh" \
     "$T_ROOT/bin/hub-format.sh" "$T_ROOT/contracts/hub-vocabulary.tsv" "$T_ROOT/contracts/support-upterm.tsv" "$BE_BIN/"
  ssh-keygen -t ed25519 -q -N '' -C hub -f "$T_TMP/signing/k"
  printf 'hub %s\n' "$(cut -d' ' -f1,2 "$T_TMP/signing/k.pub")" > "$BE_ROOT/hub-signers"
  be_policy ".approval.ttl_hours = ${1:-24}"
  be_stub_sibling hub-sync.sh "[ \"\$1\" = path ] && printf '%s\\n' '$T_TMP/state-policy.json'; exit 0"
  be_stub_sibling hub-tier.sh "[ \"\$1\" = lookup ] && [ \"\$2\" = admission.key-material-egress ] && printf 'very-high\\tfixed\\tCredentials leaving the machine\\n'; exit 0"
  be_stub_sibling member-integrity.sh "[ \"\$1\" = hash ] && printf '0123456789abcdef\\n'; exit 0"
  be_stub_sibling secret-stub '[ "$1" = run ] || exit 1; export "$3=${BE_TOKEN_VALUE-fixture_token_123}"; shift 4; exec "$@"'
  printf '%s' "$BE_TOKEN" > "$BE_ST/token"
  printf 'Sat, 07 Nov 2026 12:00:00 GMT\n' > "$BE_ST/date"
  python3 "$T_ROOT/tests/hub/fixtures/stub_board.py" "$BE_ST" "$T_PID" &
  BE_PID=$!
  _i=0
  while [ ! -f "$BE_ST/port" ] && [ "$_i" -lt 100 ]; do sleep 0.1; _i=$((_i + 1)); done
  [ -f "$BE_ST/port" ] || { echo "stub board did not start" >&2; exit 2; }
  HARBOR_HUB_API_BASE="http://127.0.0.1:$(cat "$BE_ST/port")"
  BE_BASE="$HARBOR_HUB_API_BASE"
  HARBOR_ACCESS_SECRET_BIN="$BE_BIN/secret-stub"
  HARBOR_MEMBER_ROLE=member; HARBOR_MEMBER_LOGIN=alice; HARBOR_HUB_REPO=fixture-org/fixture-hub
  export HARBOR_HUB_API_BASE HARBOR_ACCESS_SECRET_BIN HARBOR_MEMBER_ROLE HARBOR_MEMBER_LOGIN HARBOR_HUB_REPO
  BE_HS="$HOME/.local/state/harbor/hub"
}
be_down() { kill "$BE_PID" 2>/dev/null; wait "$BE_PID" 2>/dev/null; :; }

be_issue_body() { # <id> [member]
  printf 'harbor-request: 1\nid: %s\nmember: %s\nrule: prod-bucket\nlabel: Touches the production bucket\ntier: very-high\ntarget: cloud\ncore: 0123456789ab\ncc: @fixture-admin\n' "$1" "${2:-alice}"
}
be_seed_issue() { # <id> [state] [body]
  _n=$(( $(cat "$BE_ST/next-issue" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_n" > "$BE_ST/next-issue"
  jq -n --argjson n "$_n" --arg t "request $1" --arg b "${3:-$(be_issue_body "$1")}" --arg s "${2:-open}" \
    '{number: $n, title: $t, body: $b, state: $s, user: {login: "alice", type: "User"}, created_at: "2026-11-07T09:00:00Z"}' > "$BE_ST/issues/$_n.json"
  printf '[]' > "$BE_ST/comments/$_n.json"
  printf '%s\n' "$_n"
}
be_comment() { # <issue> <login> <body> [created] [updated] [type]
  _f="$BE_ST/comments/$1.json"; _c="${4:-2026-11-07T10:00:00Z}"
  BE_CID=$(( ${BE_CID:-100} + 1 ))   # ids are global on GitHub, so one counter for every issue
  jq --argjson i "$BE_CID" --arg l "$2" --arg b "$3" --arg c "$_c" --arg u "${5:-$_c}" --arg t "${6:-User}" \
    '. + [{id: $i, body: $b, created_at: $c, updated_at: $u, user: {login: $l, type: $t}}]' "$_f" > "$_f.new" && mv "$_f.new" "$_f"
}
be_log_count() { # <jq select expression>
  jq -s "map(select($1)) | length" "$BE_ST/log.jsonl" 2>/dev/null
}
be_reset() { # a clean board and laptop state between cases
  rm -f "$BE_ST"/issues/* "$BE_ST"/comments/* "$BE_ST"/perm/* "$BE_ST/log.jsonl" "$BE_ST/force" "$BE_ST/force-post" \
        "$BE_ST/nodate" "$BE_ST/remaining0" "$BE_ST/expires" "$BE_ST/next-issue" "$BE_ST/perm-default" "$BE_ST/login"
  printf 'Sat, 07 Nov 2026 12:00:00 GMT\n' > "$BE_ST/date"
  printf '%s' "$BE_TOKEN" > "$BE_ST/token"
  rm -rf "$BE_HS"
}
