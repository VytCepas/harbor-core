# colleague.sh (harbor#1278) — everything a colleague and an operator do, start to finish. Sourced by sim-relay.sh and real-upterm.sh after their own helpers.
#   a colleague opens the Harbor Support shortcut (its own command line, from member-windows.sh, on a path with a space), a request reaches the board,
#   the operator lists, accepts and joins with hub-support.sh, both see the one shell, the colleague ends it, a stranger never gets in, nothing stays.
# The caller defines: real_policy, await, board_has, join, cw_target <sid>, and has the real upterm as $T_BIN/upterm. The board is the stub; the relay is real.
# Not member mode: the launch is the shortcut's argv, but identity and the board's address come from the environment, as in the other cases here.
FL_ADMIN=fixture-admin; FL_HUB=fixture-org/fixture-hub
FL_UP='upterm host .*--name hs |upterm (join|proxy) '   # this walkthrough's own: a host another section started is not its to judge

fl_gh() { # the admin's gh over the stub board: list and read as in the sims, and an accept comment as the admin
  cat > "$T_BIN/gh" <<'EOF'
#!/bin/sh
url=''; method=GET; input=''
while [ $# -gt 0 ]; do case "$1" in api|--paginate) ;; -H) shift ;; --method) method="$2"; shift ;; --input) input="$2"; shift ;; *) url="$1" ;; esac; shift; done
case "$method $url" in
  "POST repos/"*/issues/*/comments)
    n="${url#*/issues/}"; n="${n%%/*}"; f="$BE_ST/comments/$n.json"
    jq --arg l "$FL_ADMIN" --argjson b "$(jq .body "$input")" \
      '. + [{id: (length + 900), body: $b, created_at: "2026-11-07T10:00:00Z", updated_at: "2026-11-07T10:00:00Z", user: {login: $l, type: "User"}}]' "$f" > "$f.new" && mv "$f.new" "$f"
    printf '{}\n' ;;
  "GET repos/"*/issues/*/comments*) n="${url#*/issues/}"; cat "$BE_ST/comments/${n%%/*}.json" ;;
  "GET repos/"*/issues\?*) jq -s . "$BE_ST"/issues/*.json ;;
  "GET repos/"*/contents/*) cat "$T_FIX/${url##*/}" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$T_BIN/gh"
  T_FIX="$T_TMP/fix"; mkdir -p "$T_FIX"; export T_FIX BE_ST FL_ADMIN
  cp "$T_TMP/state-policy.json" "$T_FIX/policy.json"; cp "$T_TMP/state-policy.json.sig" "$T_FIX/policy.json.sig"; cp "$BE_ROOT/hub-signers" "$T_FIX/hub-signers"
}
fl_hub() { # <verb args...>: harbor hub support as the admin. HUB_OUT, HUB_RC
  HUB_RC=0
  HUB_OUT="$(unset HARBOR_MEMBER_ROLE HARBOR_MEMBER_LOGIN; sh "$T_ROOT/bin/hub-support.sh" "$@" --hub "$FL_HUB" 2>&1)" || HUB_RC=$?
}
fl_shortcut() { # the Harbor Support shortcut's own command line, as member-windows.sh writes it. FL_CD, FL_SH, FL_PATH
  mkdir -p "$T_TMP/stage/harbor/bin"; printf '{"env":{}}\n' > "$T_TMP/stage/managed-settings.json"; : > "$T_TMP/stage/harbor/bin/placeholder"
  _ps="$(sh "$T_ROOT/bin/member-windows.sh" --stage "$T_TMP/stage" --member someone 2>/dev/null)" || return 1
  _a="$(printf '%s\n' "$_ps" | grep -F '.Arguments = ' | grep -F 'member-support.sh' | head -n 1)"
  _a="${_a#*\'}"; _a="${_a%\'}"
  FL_CD="${_a#*--cd }"; FL_CD="${FL_CD%% *}"
  _x="${_a#*--exec }"; FL_SH="${_x%% *}"
  _p="${_x#* \"}"; FL_PATH="${_p%\"}"
  [ -n "$FL_CD" ] && [ -n "$FL_SH" ] && [ -n "$FL_PATH" ] && [ "$_a" != "" ]
}
fl_land() { # the managed root where the shortcut says it is, with a space in its path: FL_LAND, the member-support.sh the shortcut would run
  _sys="$T_TMP/Program Files/ClaudeCode"; rm -rf "$_sys"; mkdir -p "$_sys"
  cp -R "$BE_ROOT" "$_sys/harbor"; ln -s "$BE_ROOT/../managed-settings.json" "$_sys/managed-settings.json"
  FL_LAND="$_sys/harbor/bin/member-support.sh"
}
fl_snapshot() { find "$HOME" "$TMPDIR" 2>/dev/null | LC_ALL=C sort; }

t_section "F1 - the colleague opens the Harbor Support shortcut"
fl_gh; real_policy; fl_gh
fl_shortcut && t_pass || t_fail "member-windows.sh --stage wrote no Harbor Support shortcut: $(printf '%s' "${_ps:-}" | head -c 300)"
t_eq "the shortcut starts a shell script with /bin/sh" /bin/sh "${FL_SH:-}"
t_eq "in the member's ~/port" /home/someone/port "${FL_CD:-}"
case "${FL_PATH:-}" in *' '*) t_pass ;; *) t_fail "the managed root has no space in its path any more: ${FL_PATH:-}" ;; esac
# The shortcut's path is under C:\Program Files on WSL's /mnt/c: here the same tree sits under a folder with a space.
fl_land
case "$FL_PATH" in /mnt/c/Program\ Files/ClaudeCode/harbor/bin/member-support.sh) t_pass ;; *) t_fail "the shortcut names another script: $FL_PATH" ;; esac
mkdir -p "$HOME/port"; fl_snapshot > "$T_TMP/fl-before"
: > "$T_TMP/fl-keep"
printf '%s\n' "$ASK1" "$ASK2" "$ASK3" "$ASK4" 'expect Start the session? [y/n]' "wait-file $T_TMP/fl-y" 'key y' 'wait 0.5' 'send' \
  "wait-file $T_TMP/fl-type" 'send echo member-says-$((5*5))' "wait-file $T_TMP/fl-end" 'hup' > "$T_TMP/fl-person.steps"
( cd "$HOME/port" && python3 "$TERMINAL_RUN" "$T_TMP/fl-person.steps" "$T_TMP/fl-person.out" -- "$FL_SH" "$FL_LAND" ) &
PERSON=$!
await "$T_TMP/fl-person.out" 'REMOTE SUPPORT' 200 && t_pass || t_fail "the shortcut's command did not start member-support.sh: $(tail -5 "$T_TMP/fl-person.out" 2>/dev/null)"
t_has "the colleague is told what an admin can do" "$(cat "$T_TMP/fl-person.out")" 'working as you'

t_section "F2 - the request reaches the board, and the admin is the one it names"
await "$T_TMP/fl-person.out" 'Your admin has been told' 300 && t_pass || t_fail "no request was filed: $(tail -5 "$T_TMP/fl-person.out")"
FLID="$(se_id)"
t_eq "the request's last line mentions the admin, which is the mail GitHub sends" "cc: @$FL_ADMIN" "$(jq -r .body "$BE_ST/issues/1.json" | grep . | tail -n 1)"
t_hasnt "and never the member who asks" "$(jq -r .body "$BE_ST/issues/1.json" | grep '^cc:')" '@alice'
fl_hub list
t_eq "the admin's list shows it, waiting" "$(printf '%s\talice\tfix\twaiting' "$FLID")" "$HUB_OUT"

t_section "F3 - the operator accepts, the colleague says yes, a session appears on the board"
fl_hub accept "$FLID"
t_eq "harbor hub support accept exits 0" 0 "$HUB_RC"
await "$T_TMP/fl-person.out" "$FL_ADMIN has accepted" 300 && t_pass || t_fail "the colleague was never told who accepted: $(tail -5 "$T_TMP/fl-person.out")"
t_eq "no session before the colleague says yes" '' "$(se_comments | grep '^session' || :)"
: > "$T_TMP/fl-y"
board_has session && t_pass || t_fail "no session reached the board: $(tail -5 "$T_TMP/fl-person.out")"
FLSID="$(se_comments | sed -n 's/^session s-[0-9a-f]* //p')"
fl_hub list
t_eq "the admin's list shows the session up" "$(printf '%s\talice\tfix\tsession-up' "$FLID")" "$HUB_OUT"

t_section "F4 - a stranger cannot join, the operator joins with hub-support.sh and sees the one shell"
join "$T_TMP/stranger" "$(cw_target "$FLSID")" "$T_TMP/fl-stranger.out" 'wait 2' 'send echo stranger-$((6*7))' 'wait 3'
t_has "the stranger is told the relay refused the key" "$(cat "$T_TMP/fl-stranger.out")" 'refused your keys'
t_eq "and left with no session" 255 "$JOIN_RC"
t_hasnt "nothing the stranger typed reached the colleague's shell" "$(cat "$T_TMP/fl-person.out"; printf ' .')" 'stranger-42'
printf '%s\n' 'wait 3' 'send echo guest-$((6*7))-$(id -un)' "expect guest-42-$(id -un)" 'expect member-says-25' 'expect connection to the session ended' > "$T_TMP/fl-admin.steps"
(
  unset HARBOR_MEMBER_ROLE HARBOR_MEMBER_LOGIN
  PTY_RUN_TIMEOUT=60 python3 "$TERMINAL_RUN" "$T_TMP/fl-admin.steps" "$T_TMP/fl-admin.out" -- sh "$T_ROOT/bin/hub-support.sh" connect "$FLID" --key "$T_TMP/admin" --hub "$FL_HUB"
  printf '%s' "$?" > "$T_TMP/fl-admin.rc"
) &
ADMINP=$!
await "$T_TMP/fl-person.out" "guest-42-$(id -un)" 200 && t_pass || t_fail "the colleague did not see what the operator typed: $(tail -5 "$T_TMP/fl-person.out"); admin: $(tail -5 "$T_TMP/fl-admin.out" 2>/dev/null)"
: > "$T_TMP/fl-type"
await "$T_TMP/fl-admin.out" 'member-says-25' 200 && t_pass || t_fail "the operator did not see what the colleague typed: $(tail -5 "$T_TMP/fl-admin.out")"
t_has "the operator's screen holds the colleague's own command line too" "$(cat "$T_TMP/fl-admin.out")" 'echo member-says-'

t_section "F5 - the colleague ends it, and nothing stays"
: > "$T_TMP/fl-end"
wait "$PERSON" 2>/dev/null || :
wait "$ADMINP" 2>/dev/null || :
t_has "the operator is put out when the window closes" "$(cat "$T_TMP/fl-admin.out")" 'connection to the session ended'
board_has "closed $FLID" && t_pass || t_fail "no closed comment: $(se_comments | tail -3)"
t_eq "the request is closed" closed "$(jq -r .state "$BE_ST/issues/1.json")"
t_eq "the record" "requested accepted started ended " "$(se_events)"
_i=0; while pgrep -f "$FL_UP" >/dev/null 2>&1 && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
_left="$(pgrep -a -f "$FL_UP" || :)"
t_eq "no upterm host, guest or proxy is left running: $_left" '' "$_left"
t_eq "no session folder" '' "$(find "$BE_HS" -maxdepth 1 -name 'sup.*')"
join "$T_TMP/admin" "$(cw_target "$FLSID")" "$T_TMP/fl-after.out" 'wait 4'
t_eq "the session id is dead for the operator too" 255 "$JOIN_RC"
fl_snapshot > "$T_TMP/fl-after"
# What is left is the board's date mark and the record of the request's states (hub-events.sh): no terminal text, no key, no socket.
t_eq "the laptop gained only those two files" "$BE_HS/board-state
$BE_HS/outbox.jsonl" "$(diff "$T_TMP/fl-before" "$T_TMP/fl-after" | sed -n 's/^> //p')"
t_hasnt "and none of it is what was typed" "$(cat "$BE_HS"/* 2>/dev/null; printf ' .')" 'member-says'
