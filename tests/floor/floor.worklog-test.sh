#!/usr/bin/env sh
# The work log in a marked repo (harbor#954, D-46): a marker alone no longer stops it. worklog-push
# appends unless the repo's .agents/config.yaml says `worklog: off`, read from
# the marker the walk finds, so a subdirectory answers as its repo does. memory-harvest's half is in
# tests/memory/memory-test.sh; the opt-out's spelling rules are H2 in floor.session-test.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/floor-fixture.sh"

WL="$TMP/wl954"; mkdir -p "$WL/log" "$WL/gov/.agents" "$WL/gov/sub" "$WL/off/.agents" "$WL/off/sub"
printf 'context: repo\n' > "$WL/gov/.agents/config.yaml"
printf 'context: repo\nworklog: off\n' > "$WL/off/.agents/config.yaml"
git -C "$WL/log" init -q 2>/dev/null

t_section "WL-954 worklog-push: a marked repo appends unless it says worklog: off"
_wpush() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$2" \
  | CLAUDE_CONFIG_DIR="$CFG" HARBOR_LOG_DIR="$WL/log" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" >/dev/null 2>&1; }
_wrec() { find "$WL/log/WORK" -type f -name "*$1*" 2>/dev/null | grep -c . | tr -d ' '; }
_wpush WL-gov "$WL/gov";         t_eq "WL-954 a marked repo without worklog: off appends to the work log" 1 "$(_wrec WL-gov)"
_wpush WL-gov-sub "$WL/gov/sub"; t_eq "WL-954 …and so does a subdirectory of it" 1 "$(_wrec WL-gov-sub)"
_wpush WL-off "$WL/off";         t_eq "WL-954 a marked repo with worklog: off appends nothing" 0 "$(_wrec WL-off)"
_wpush WL-off-sub "$WL/off/sub"; t_eq "WL-954 …nor does a subdirectory of it" 0 "$(_wrec WL-off-sub)"

t_section "harbor#1181: signed checkpoints are on the push allowlist (the off-host anchor)"
mkdir -p "$WL/log/CHECKPOINTS/box"; printf '# day=2026-10-08\nf1\t10\tabc\n' > "$WL/log/CHECKPOINTS/box/2026-10-08.tsv"
# an explicit identity: a runner with none makes the commit fail silently (worklog-push: commit || reset; exit 0)
( export GIT_AUTHOR_NAME=harbor-test GIT_AUTHOR_EMAIL=harbor-test@example.invalid GIT_COMMITTER_NAME=harbor-test GIT_COMMITTER_EMAIL=harbor-test@example.invalid; _wpush WL-anchor "$WL/gov" )
t_eq "a checkpoint is committed with the work log" yes "$(git -C "$WL/log" log --name-only --format= 2>/dev/null | grep -qx CHECKPOINTS/box/2026-10-08.tsv && echo yes || echo no)"

_g() { git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

t_section "#311 worklog-pull is retired: no file, no wiring, no live reference"
t_eq "#311 bin/worklog-pull.sh is gone from the tree" no "$([ -e "$HROOT/bin/worklog-pull.sh" ] && echo yes || echo no)"
t_eq "#311 the reference scan reads a git checkout, so an empty result means none" yes \
  "$(git -C "$HROOT" rev-parse --git-dir >/dev/null 2>&1 && echo yes || echo no)"
# Dated records keep the name (evaluation runs, incident and plan ledgers, the estate exemption row).
# bin/idea.sh is frozen by lint's log-exempt ratchet until it moves onto log-lib.sh, so its comment stays.
# Everything else that WIRES or DOCUMENTS the hook is in scope: putting the wiring back turns this red.
_wpull_refs="$(git -C "$HROOT" grep -l -e 'worklog-pull' -- . ':!EVALS-DATA' ':!skills/topology/EVALS' \
  ':!COVERAGE-INCIDENTS.tsv' ':!CONTRACTS/port-paths-exempt.tsv' ':!PLAN.md' ':!harbor-build-tickets.md' \
  ':!tests/floor/floor.worklog-test.sh' ':!bin/idea.sh' 2>/dev/null)"
t_eq "#311 no live surface names worklog-pull (installer, lint, contract, doc, test)" "" "$_wpull_refs"

t_section "harbor#324 worklog-push: a failed push names the git error, not the pre-push scan banner"
# A local origin whose pre-receive refuses; the work log's pre-push prints gitleaks' two INF lines first.
_g init -q --bare "$WL/rej.git"; printf '#!/bin/sh\necho rejected-by-suite >&2; exit 1\n' > "$WL/rej.git/hooks/pre-receive"
chmod +x "$WL/rej.git/hooks/pre-receive"
_g clone -q "$WL/rej.git" "$WL/plog" 2>/dev/null
git -C "$WL/plog" config user.name t; git -C "$WL/plog" config user.email t@t   # hermetic: the runner has no global identity
printf '#!/bin/sh\necho "5:39PM INF 1532 commits scanned." >&2\necho "5:39PM INF scanned ~135644 bytes (135.64 KB) in 705ms" >&2\n' > "$WL/plog/.git/hooks/pre-push"
chmod +x "$WL/plog/.git/hooks/pre-push"
printf '#!/bin/sh\nexit 0\n' > "$T_BIN/gitleaks"; chmod +x "$T_BIN/gitleaks"
printf 'x-test-token\n' > "$WL/token"
_wpf() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$REPO_BARE" | CLAUDE_CONFIG_DIR="$CFG" HARBOR_LOG_DIR="$WL/plog" \
  HARBOR_LOG_TOKEN_FILE="$WL/token" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" 2>&1 >/dev/null; }
_o="$(_wpf WL-324)"
t_has "324 the failure is reported" "$_o" "push FAILED"
t_has "324 …with git's own reason" "$_o" "remote rejected"
t_hasnt "324 …and not the scan banner" "$_o" " INF "
rm -f "$WL/rej.git/hooks/pre-receive"
t_eq "324 control: a push that succeeds prints nothing" "" "$(_wpf WL-324-ok)"

t_section "harbor#1191 worklog-push: no identity falls back per command and says so; any other failure is FAIL"
# No identity anywhere: no global or system config, and useConfigOnly refuses to auto-detect one.
_nid="$WL/nid"; mkdir -p "$_nid"; git -C "$_nid" init -q 2>/dev/null; git -C "$_nid" config user.useConfigOnly true
_nid_run() { ( unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
  printf '{"session_id":"%s","cwd":"%s"}' "$1" "$WL/gov" \
    | CLAUDE_CONFIG_DIR="$CFG" HARBOR_LOG_DIR="$_nid" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" >/dev/null 2>"$WL/nid.err" ); }
_nid_run WL-1191
t_has "1191 with no identity the commit lands under the fallback author" "$(git -C "$_nid" log -1 --format=%ae 2>/dev/null)" "harbor@"
t_has "1191 …and the fallback is said on stderr" "$(cat "$WL/nid.err")" "WARN"
t_hasnt "1191 …and it is not a failure" "$(cat "$WL/nid.err")" "commit FAILED"
git -C "$_nid" config user.name harbor-test; git -C "$_nid" config user.email harbor-test@example.invalid
_nid_run WL-1191-ok
t_has "1191 control: with a real identity the record is committed as that identity" "$(git -C "$_nid" log -1 --format=%ae 2>/dev/null)" "harbor-test@"
t_eq "1191 control: and nothing is shown" "" "$(cat "$WL/nid.err")"

# A commit rejected by a hook is not an identity problem: no fallback, a FAIL with the hook's reason, no commit.
# The repo has a real identity, so git reaches pre-commit. With none, git fails first and the hook never runs
# (probed: rc=128, no hook output), so a hook assertion there only ever sees the fallback attempt.
_hk="$WL/hk"; mkdir -p "$_hk"; git -C "$_hk" init -q 2>/dev/null; git -C "$_hk" config user.useConfigOnly true
git -C "$_hk" config user.name harbor-test; git -C "$_hk" config user.email harbor-test@example.invalid
git -C "$_hk" -c commit.gpgsign=false commit -q --allow-empty -m base; _hk_head="$(git -C "$_hk" rev-parse HEAD)"
printf '#!/bin/sh\ngit var GIT_AUTHOR_IDENT > "%s" 2>/dev/null\necho hook-rejected-1191 >&2\nexit 1\n' "$WL/hk.ident" > "$_hk/.git/hooks/pre-commit"
chmod +x "$_hk/.git/hooks/pre-commit"
( unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
  printf '{"session_id":"WL-1191-hook","cwd":"%s"}' "$WL/gov" \
    | CLAUDE_CONFIG_DIR="$CFG" HARBOR_LOG_DIR="$_hk" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" >/dev/null 2>"$WL/hk.err" )
_hk_rc=$?
t_has "1191 a hook-rejected commit is shown as FAIL" "$(cat "$WL/hk.err")" "commit FAILED"
t_has "1191 …with the hook's own reason" "$(cat "$WL/hk.err")" "hook-rejected-1191"
t_has "1191 …and the hook saw the repo's real identity, so no fallback was attempted" "$(cat "$WL/hk.ident" 2>/dev/null)" "harbor-test <harbor-test@example.invalid>"
t_hasnt "1191 …and no fallback is claimed" "$(cat "$WL/hk.err")" "fallback"
t_eq "1191 …and HEAD is unchanged" "$_hk_head" "$(git -C "$_hk" rev-parse HEAD 2>/dev/null)"
t_eq "1191 …and the hook rejection does not block the session (exit 0)" 0 "$_hk_rc"

# No identity AND a rejecting hook: the fallback is tried (so the hook runs), the hook rejects it, FAIL shows, no commit lands.
_nh="$WL/nh"; mkdir -p "$_nh"; git -C "$_nh" init -q 2>/dev/null; git -C "$_nh" config user.useConfigOnly true
printf '#!/bin/sh\ngit var GIT_AUTHOR_IDENT > "%s" 2>/dev/null\necho hook-rejected-1191-nid >&2\nexit 1\n' "$WL/nh.ident" > "$_nh/.git/hooks/pre-commit"
chmod +x "$_nh/.git/hooks/pre-commit"
( unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1; export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
  printf '{"session_id":"WL-1191-nid-hook","cwd":"%s"}' "$WL/gov" \
    | CLAUDE_CONFIG_DIR="$CFG" HARBOR_LOG_DIR="$_nh" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" >/dev/null 2>"$WL/nh.err" )
_nh_rc=$?
t_has "1191 no identity + rejecting hook: the fallback is tried, so the hook runs under it" "$(cat "$WL/nh.ident" 2>/dev/null)" "harbor@"
t_has "1191 …and the rejection is shown as FAIL with the hook's reason" "$(cat "$WL/nh.err")" "commit FAILED"
t_has "1191 …naming the hook" "$(cat "$WL/nh.err")" "hook-rejected-1191-nid"
t_eq "1191 …and no commit lands" "" "$(git -C "$_nh" rev-parse --verify -q HEAD 2>/dev/null)"
t_eq "1191 …and the session is not blocked (exit 0)" 0 "$_nh_rc"

t_section "harbor#1205 worklog-push: the token is the store's worklog-token; the plaintext file warns once"
# The store stub logs each call; `run` serves FAKE_STORE as the named variable.
cat > "$WL/secret" <<'STUB'
#!/bin/sh
echo "$*" >> "$FAKE_STORE.calls"
case "$1" in
  run) [ -f "$FAKE_STORE" ] || { echo "no secret named '$2'" >&2; exit 1; }; v="$(cat "$FAKE_STORE")"; export "$3=$v"; shift 4; exec "$@" ;;
  *) exit 2 ;;
esac
STUB
_sc="$WL/scfg"; mkdir -p "$_sc"
_wps() { printf '{"session_id":"%s","cwd":"%s"}' "$1" "$REPO_BARE" | CLAUDE_CONFIG_DIR="$_sc" HARBOR_LOG_DIR="$WL/plog" \
  HARBOR_SECRET_BIN="$WL/secret" FAKE_STORE="$WL/store" HARBOR_LOG_TOKEN_FILE="$WL/legacy" sh "$T_ROOT/hooks/worklog-push/worklog-push.sh" 2>&1 >/dev/null; }
rm -f "$WL/store" "$WL/legacy"
t_has "1205 no token anywhere: it says the log is never pushed" "$(_wps WL-1205-a)" "never pushed"
t_eq "1205 …once: the next Stop is silent" "" "$(_wps WL-1205-b)"
printf 'x-test-token\n' > "$WL/legacy"
t_has "1205 a plaintext file only: it warns that the token is not in the store" "$(_wps WL-1205-c)" "still the plaintext"
t_eq "1205 …once" "" "$(_wps WL-1205-d)"
printf 'x-test-token\n' > "$WL/store"; : > "$WL/store.calls"
t_eq "1205 with the token in the store: a push that succeeds prints nothing" "" "$(_wps WL-1205-e)"
t_has "1205 …and the push ran under secret run" "$(cat "$WL/store.calls")" "run worklog-token WORKLOG_TOKEN -- git"
t_eq "1205 …and the warn-once stamps are cleared, so a regression warns again" no \
  "$([ -e "$_sc/.worklog-token-warned.legacy" ] || [ -e "$_sc/.worklog-token-warned.missing" ] && echo yes || echo no)"

ff_sealed
t_done
