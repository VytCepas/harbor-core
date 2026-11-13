# sim-linux-lib.sh (harbor#1278) — sim-linux.sh's inner half: the table and hook helpers, the hub admin, and step 0, the fixture.
# Sourced by sim-linux.sh --inner inside the container, which copies it to /sim beside itself; never run alone.
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$TABLE"; printf '%s %s: %s | %s\n' "$1" "$2" "$4" "$5" >> "$LOG"; }  # status id expected got note
want() { if meets "$3" "$4"; then row PASS "$1" "$3" "$4" "$2"; else row FAIL "$1" "$3" "$4" "$2"; fi; }   # id note expected got, deny matching any deny
eq() { if [ "$3" = "$4" ]; then row PASS "$1" "$3" "$4" "$2"; else row FAIL "$1" "$3" "$4" "$2"; fi; }   # id note expected got
say() { printf '── %s\n' "$*" | tee -a "$LOG" >&2; }
sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

# ── the member's process environment ───────────────────────────────────────────────────────────────────────
MUID=''
base_env() {
  printf '%s\n' "HOME=$MH" "USER=$M" "LOGNAME=$M" SHELL=/bin/bash PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 \
    TERM=xterm-256color "XDG_RUNTIME_DIR=/run/user/$MUID" "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$MUID/bus" "CLAUDE_PROJECT_DIR=$WD"
}
managed_env() { jq -r '.env | to_entries[] | .key + "=" + .value' "$MFILE" 2>/dev/null; }
# as_member <env-extra file|-> <managed 1|0> <cwd> <command...>: exactly that environment, as Claude Code's own process would hand it on:
# the inherited env, then the settings env over it. The argv is written into a launcher, quoted, so nothing reaches a shell string unquoted.
as_member() {
  _ex="$1"; _mg="$2"; _cd="$3"; shift 3
  { printf 'exec env -i -C %s' "$(sq "$_cd")"
    { base_env; [ "$_ex" = - ] || cat "$_ex"; [ "$_mg" = 0 ] || managed_env; } | while IFS= read -r _kv; do [ -z "$_kv" ] || printf ' %s' "$(sq "$_kv")"; done
    for _a in "$@"; do printf ' %s' "$(sq "$_a")"; done; printf '\n'; } > "$RUN/launch"
  chmod 644 "$RUN/launch"
  timeout 120 runuser -u "$M" -- /bin/sh "$RUN/launch"
}
# wsl_session <shell line>: the member's session as WSL opens one with systemd on (`login -f <user>`, wsl.dev, systemd), on a pty, no display.
# The line runs in the login shell; everything it prints lands in $RUN/wsl.out.
wsl_session() {
  printf '%s; exit\n' "$1" | timeout 60 script -qec "login -f $M" /dev/null > "$RUN/wsl.out" 2>&1 || :
  cat "$RUN/wsl.out" >> "$OUT/wsl-session.log"
}
# hook <event> <payload file> [env-extra file|-] [managed 1|0]: the command the managed settings name, through /bin/sh -c, as Claude Code runs it.
hook() {
  _hc="$(jq -r --arg e "$1" '.hooks[$e][0].hooks[0].command' "$MFILE")"
  H_RC=0; as_member "${3:--}" "${4:-1}" "$WD" /bin/sh -c "$_hc" < "$2" > "$RUN/h.out" 2> "$RUN/h.err" || H_RC=$?
  H_OUT="$(cat "$RUN/h.out")"
  printf '%s %s rc=%s out=%s\n' "$1" "$(head -c 160 "$2")" "$H_RC" "$(head -c 300 "$RUN/h.out")" >> "$OUT/hooks.log"
}
N=0
payload() { # <tool> <tool_input json> -> PreToolUse payload file path. The count is a file: most calls run in a subshell.
  N=$(( $(cat "$RUN/n" 2>/dev/null || echo 0) + 1 )); echo "$N" > "$RUN/n"
  jq -cn --arg t "$1" --argjson i "$2" --arg w "$WD" --arg c "toolu_sim$N" --arg tp "$MH/.claude/projects/-home-alice-port-work/sim-1.jsonl" \
    '{session_id:"sim-1",transcript_path:$tp,cwd:$w,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:$t,tool_input:$i,tool_use_id:$c}' > "$RUN/p.$N"
  chmod 644 "$RUN/p.$N"; printf '%s' "$RUN/p.$N"
}
# verdict: from the last hook. silent | ask | deny | allow | block (exit 2) | error-<rc>; a non-zero exit is a block under onFailure block.
verdict() {
  if [ "$H_RC" = 0 ]; then
    [ -n "$H_OUT" ] || { echo silent; return; }
    _d="$(printf '%s' "$H_OUT" | jq -r '.hookSpecificOutput.permissionDecision // "other"' 2>/dev/null)" || _d=unparsable
    echo "$_d"
  elif [ "$H_RC" = 2 ]; then echo block
  else echo "error-$H_RC"; fi
}
why() { printf '%s' "$H_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
klass() { # the verdict with its kind of deny, from the words the person sees
  _v="$(verdict)"
  case "$_v" in
    deny) case "$(why)" in
            *"no approval can change it"*) echo deny-integrity ;;
            *"approve this exact action"*|*"needs an admin's approval"*) echo deny-approval ;;
            *"company safety settings"*) echo deny-policy ;;
            *"could not finish"*) echo deny-fault ;;
            *) echo deny-other ;;
          esac ;;
    *) echo "$_v" ;;
  esac
}
strength() { case "$1" in silent|allow|other) echo 0 ;; ask) echo 1 ;; *) echo 2 ;; esac; }
meets() { # <expected> <got>: deny matches any deny; an exact kind must match exactly
  case "$1" in deny) case "$2" in deny*|block|error-*) return 0 ;; esac; return 1 ;; esac
  [ "$1" = "$2" ]
}
pre() { hook PreToolUse "$(payload "$1" "$2")" "${3:--}" "${4:-1}"; klass; }
bash_call() { pre Bash "$(jq -cn --arg c "$1" '{command:$c,description:"a step"}')" "${2:--}" "${3:-1}"; }
session() { # <start|end> [env-extra] [managed]
  _p="$RUN/s.$1"
  if [ "$1" = start ]; then jq -cn --arg w "$WD" '{session_id:"sim-1",hook_event_name:"SessionStart",source:"startup",cwd:$w}' > "$_p"
  else jq -cn --arg w "$WD" '{session_id:"sim-1",hook_event_name:"SessionEnd",reason:"other",cwd:$w}' > "$_p"; fi
  chmod 644 "$_p"
  if [ "$1" = start ]; then hook SessionStart "$_p" "${2:--}" "${3:-1}"; else hook SessionEnd "$_p" "${2:--}" "${3:-1}"; fi
}
hs() { as_member - 1 "$WD" sh "$MROOT/bin/hub-sync.sh" "$@"; }   # hub-sync as the member, as a hook reaches it
held_serial() { _p="$(hs path 2>/dev/null)"; [ -n "$_p" ] && jq -r .serial "$_p" 2>/dev/null || echo none; }

# ── the hub admin ──────────────────────────────────────────────────────────────────────────────────────────
SERIAL=0; CONTRACT=1
adm_git() { git -C "$ADM/hub" -c user.name=acme-admin -c user.email=admin@acme.test "$@"; }
SIM_PACKS='[]'; SIM_LOGS=''; SIM_CONNECTORS='[]'   # the policy's packs (JSON), its logs recipient and its connectors (JSON): the sections that need them set these
mkpolicy() { # <out> <serial> <mode> <core commit> <revoked 0|1> [hosts, comma-separated]
  python3 - "$1" "$2" "$3" "$4" "$CONTRACT" "$5" "${6:-}" "$SIM_PACKS" "$SIM_LOGS" "$SIM_CONNECTORS" <<'PY'
import datetime, json, sys
out, serial, mode, commit, contract, revoked, hosts, packs, logs, conns = sys.argv[1:11]
rule = lambda i, l, t, tg, tool, field, v: {"id": i, "label": l, "tier": t, "target": tg, "tools": [tool], "when": [{"field": field, "op": "contains", "value": v}]}
p = {"schema": 1, "hub": "acme-hub", "serial": int(serial), "issued": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
     "core": {"commit": commit, "contract": int(contract)}, "rollout": {"mode": mode},
     "approval": {"approvers": ["acme-admin"], "ttl_hours": 24}, "silent_days": 5, "tiers": {},
     "rules": [rule("prod-bucket", "Touches the production bucket", "very-high", "cloud", "Bash", "command", "gs://prod-"),
               rule("stage-bucket", "Touches the staging bucket", "high", "cloud", "Bash", "command", "gs://stage-")],
     "packs": json.loads(packs), "hooks": [], "revoked": ["alice"] if revoked == "1" else []}
if hosts: p["hosts"] = hosts.split(",")
if logs: p["logs"] = {"recipient": logs}
if conns != "[]": p["connectors"] = json.loads(conns)
json.dump(p, open(out, "w"), indent=1)
PY
}
# publish <mode> [core commit] [revoked 0|1] [key] [hosts]: the next serial, signed with the admin's key (or another), committed and pushed to the hub.
publish() {
  SERIAL=$((SERIAL + 1))
  mkpolicy "$ADM/hub/policy.json" "$SERIAL" "$1" "${2:-$PIN}" "${3:-0}" "${5:-}"
  rm -f "$ADM/hub/policy.json.sig"
  ssh-keygen -q -Y sign -f "${4:-$ADM/key}" -n harbor-hub "$ADM/hub/policy.json" 2>>"$LOG"
  cp "$ADM/hub/policy.json" "$ADM/policy.$SERIAL.json"; cp "$ADM/hub/policy.json.sig" "$ADM/policy.$SERIAL.json.sig"
  adm_git add -A; adm_git commit -qm "policy $SERIAL"; adm_git push -q origin HEAD:main 2>>"$LOG"
}
replay() { # <serial>: put an older signed pair back at the hub's head
  cp "$ADM/policy.$1.json" "$ADM/hub/policy.json"; cp "$ADM/policy.$1.json.sig" "$ADM/hub/policy.json.sig"
  adm_git add -A; adm_git commit -qm "replay $1"; adm_git push -q origin HEAD:main 2>>"$LOG"
}
board_issues() { find "$BOARD/issues" -name '*.json' -exec cat {} + 2>/dev/null | jq -s "sort_by(.number) | $1"; }
admin_says() { # <issue> <body>: a comment through the API, so the board records its author and time
  printf '%s' "$ADMIN" > "$BOARD/login"
  jq -n --arg b "$2" '{body:$b}' | curl -q -sS -o /dev/null -X POST -H "Authorization: Bearer $TOKEN" --data-binary @- "https://api.github.com/repos/$HUB/issues/$1/comments"
  rm -f "$BOARD/login"
}

# ═══ 0 · fixture: the core source, GitHub on loopback, the hub, the member ═══
fixture() {
  say fixture
  mkdir -p "$GIT/VytCepas" "$GIT/acme" "$BOARD" "$ADM" /srv/dl /srv/tls
  git clone -q --bare /sim/core.bundle "$GIT/VytCepas/harbor-core.git" || { row FAIL fixture.core - 'the bundle does not clone'; return 1; }
  git -C "$GIT/VytCepas/harbor-core.git" config uploadpack.allowAnySHA1InWant true   # github.com serves a commit by id
  BASE="$(cat /sim/core.commit)"   # the bundle's one ref may not be HEAD: main is set to the commit under test
  git -C "$GIT/VytCepas/harbor-core.git" update-ref refs/heads/main "$BASE" && git -C "$GIT/VytCepas/harbor-core.git" symbolic-ref HEAD refs/heads/main \
    || { row FAIL fixture.core "$BASE" - 'the commit is not in the bundle'; return 1; }
  CONTRACT="$(git -C "$GIT/VytCepas/harbor-core.git" show "$BASE:bin/harbor" | sed -n 's/^CONTRACT_VERSION=\([0-9][0-9]*\)$/\1/p' | head -n 1)"
  row INFO fixture.core "$BASE" "contract $CONTRACT" 'the commit under test'
  git clone -q "$GIT/VytCepas/harbor-core.git" "$ADM/core"
  _arch="$(dpkg --print-architecture)"; _f="upterm_linux_$_arch.tar.gz"
  _pin="$(git -C "$ADM/core" show "$BASE:contracts/support-upterm.tsv" | awk -F'\t' -v k="sha256-linux-$_arch" '$1 == k { print $2 }')"
  if [ -f "/sim/dl/$_f" ] && [ "$(sha256sum < "/sim/dl/$_f" | cut -d' ' -f1)" = "$_pin" ]; then
    cp "/sim/dl/$_f" /srv/dl/; PIN="$BASE"; row PASS fixture.upterm "$_pin" real 'the pinned upterm archive, from SIM_UPTERM_DIR'
  else
    # No GitHub here, so a stand-in archive, and a fixture commit on top that pins its digest. Only the data row moves.
    mkdir -p /srv/dl/x; printf '#!/bin/sh\necho "upterm stand-in for sim-linux"\n' > /srv/dl/x/upterm; chmod 755 /srv/dl/x/upterm
    tar -czf "/srv/dl/$_f" -C /srv/dl/x upterm
    _sum="$(sha256sum < "/srv/dl/$_f" | cut -d' ' -f1)"
    sed -i "s/^sha256-linux-$_arch\t.*/sha256-linux-$_arch\t$_sum/" "$ADM/core/contracts/support-upterm.tsv"
    git -C "$ADM/core" -c user.name=sim -c user.email=sim@sim.test commit -qam 'sim: a stand-in upterm digest'
    git -C "$ADM/core" push -q origin HEAD:refs/heads/sim-pin
    PIN="$(git -C "$ADM/core" rev-parse HEAD)"
    row SEAM fixture.upterm 'pinned archive' "stand-in, pin $PIN" 'no GitHub: contracts/support-upterm.tsv digest rewritten in a fixture commit'
  fi
  # TLS for github.com and api.github.com, trusted by the system store only.
  ( cd /srv/tls && openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 7 -subj /CN=sim-linux-ca >/dev/null 2>&1 \
    && openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj /CN=github.com >/dev/null 2>&1 \
    && printf 'subjectAltName=DNS:github.com,DNS:api.github.com\nbasicConstraints=CA:FALSE\nextendedKeyUsage=serverAuth\n' > ext \
    && openssl x509 -req -in leaf.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out leaf.crt -days 7 -extfile ext >/dev/null 2>&1 ) \
    || { row FAIL fixture.tls - 'openssl failed'; return 1; }
  cp /srv/tls/ca.crt /usr/local/share/ca-certificates/sim-linux-ca.crt && update-ca-certificates >/dev/null 2>&1
  printf '%s' "$TOKEN" > "$BOARD/token"
  nohup python3 /sim/sim_github.py "$BOARD" "$GIT" /srv/dl /srv/tls/leaf.crt /srv/tls/leaf.key > "$OUT/github.log" 2>&1 &
  _i=0; while [ ! -f "$BOARD/up" ] && [ "$_i" -lt 50 ]; do sleep 0.2; _i=$((_i + 1)); done
  [ -f "$BOARD/up" ] || { row FAIL fixture.github - 'sim_github.py did not start'; return 1; }
  # A listener for a planted proxy: anything that connects here honoured an inherited proxy variable.
  nohup python3 -c 'import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind(("127.0.0.1", 8899)); s.listen(16)
while True:
    c, a = s.accept(); open("/srv/evil-proxy.log", "a").write("connection\n"); c.close()' > /dev/null 2>&1 &
  # The hub: a bare repo the board's owner holds, the admin's key, the signers file IT receives.
  ssh-keygen -q -t ed25519 -N '' -C hub -f "$ADM/key"; ssh-keygen -q -t ed25519 -N '' -C stranger -f "$ADM/stranger"
  git init -q --bare -b main "$GIT/acme/hub.git"
  git init -q -b main "$ADM/hub"; adm_git remote add origin "$GIT/acme/hub.git"
  printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$ADM/key.pub")" > "$ADM/hub/hub-signers"
  publish shadow   # serial 1: a new hub starts in shadow
  # The member: not an admin, and the files a laptop holds that must not leave.
  useradd -m -s /bin/bash "$M"; MUID="$(id -u "$M")"
  mkdir -p "/run/user/$MUID"; chown "$M:$M" "/run/user/$MUID"; chmod 700 "/run/user/$MUID"
  runuser -u "$M" -- sh -c "mkdir -p '$MH/.ssh' '$MH/.aws' '$WD' && ssh-keygen -q -t ed25519 -N '' -f '$MH/.ssh/id_ed25519' && printf '[default]\naws_access_key_id = AKIASIMFIXTURE\n' > '$MH/.aws/credentials' && printf 'API_KEY=sim-fixture-value\n' > '$WD/.env' && printf '# work\n' > '$WD/README.md' && printf 'hello\n' > '$WD/notes.md'"
  eq fixture.member 'the member is in no admin group' "$M" "$(id -Gn "$M")"
}
