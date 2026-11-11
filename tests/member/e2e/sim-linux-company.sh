# sim-linux-company.sh (harbor#1278) - sim-linux.sh's sections 8-14: what the company layers add to the member's laptop.
# packs (hub packs land in the member's skills), yard (a repo they start is named), logging (counts, the sealed id, the receipt, the loader, the
# closed rows), ask_tool (the question tool and the waiting state), sandbox_floor (the managed floor's sandbox), law (the managed CLAUDE.md and
# the Stop hook), tools (a member's own tools and their private repo). Sourced by sim-linux.sh --inner inside the container after the helpers; never run alone. Every section ends on a row it can
# fail, and a CONTROL row shows the probe can see what it looks for.

CORE_NOW() { cat "$MROOT/core.commit" 2>/dev/null || echo "$PIN"; }   # the commit the laptop's floor is at; a policy that names another would move the updater
HS="$MH/.local/state/harbor/hub"
STUB_PORT=8788
stub_up() {
  pgrep -f stub_anthropic.py > /dev/null 2>&1 && return 0
  mkdir -p /srv/stub; : > /srv/stub/log; : > /srv/stub/queue
  nohup python3 /sim/stub_anthropic.py "$STUB_PORT" /srv/stub/queue /srv/stub/log > /srv/stub/out 2>&1 &
  _i=0; while [ "$_i" -lt 20 ] && ! curl -q -s -o /dev/null "http://127.0.0.1:$STUB_PORT/"; do sleep 0.3; _i=$((_i + 1)); done
  curl -q -s -o /dev/null "http://127.0.0.1:$STUB_PORT/" || row FAIL stub.up 'the stand-in Messages API answers' "no answer on $STUB_PORT: $(head -c 100 /srv/stub/out)" 'tests/member/e2e/stub_anthropic.py'
}
# claude_real <tag> <prompt> [queue file] [claude args...]: the real Claude Code CLI, a real session under the managed settings, against a stand-in
# Messages API (stub_anthropic.py). Seam: it runs as root with the member's HOME, because bubblewrap can't make a user namespace for the member in
# an unprivileged container; the files it leaves are handed back to the member. Output: $OUT/claude-<tag>.jsonl.
claude_real() {
  _ct="$1"; _cp="$2"; _cq="${3:--}"; [ $# -lt 3 ] || shift 3; [ $# -ge 3 ] || shift $#
  stub_up; : > /srv/stub/log
  if [ "$_cq" = - ]; then : > /srv/stub/queue; else cp "$_cq" /srv/stub/queue; fi
  ( cd "$WD" && env HOME="$MH" ANTHROPIC_API_KEY=sk-ant-sim-0000 "ANTHROPIC_BASE_URL=http://127.0.0.1:$STUB_PORT" DISABLE_TELEMETRY=1 \
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 timeout 150 claude -p "$_cp" --output-format stream-json --verbose --include-hook-events --max-turns 6 "$@" \
      > "$OUT/claude-$_ct.jsonl" 2> "$OUT/claude-$_ct.err" ) || :
  chown -R "$M:$M" "$MH" 2> /dev/null || :
}
jsonl() { jq -r "$1" "$OUT/claude-$2.jsonl" 2> /dev/null; }   # <filter> <tag>
# hook_env <event> [env-extra file]: the environment the managed hook for <event> starts its script in, by running the composed command with `env` as the program.
hook_env() {
  _he="$(jq -r --arg e "$1" '[.hooks[$e][0].hooks[].command][0]' "$MFILE" | sed "s#/bin/sh '[^']*'\$#/usr/bin/env#")"
  as_member "${2:--}" 1 "$WD" /bin/sh -c "$_he" < /dev/null
}

# ═══ 8 · company packs (c): the hub's packs/ land in <member HOME>/.claude/skills ═══
packs() {
  say packs
  _t="$ADM/hub/packs/sim-tools"; mkdir -p "$_t/harbor-pack/skills/sim-skill" "$_t/harbor-pack/bin"
  printf 'name = "sim-tools"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "the sim tools"\n' > "$_t/harbor-pack/pack.toml"
  printf -- '---\nname: sim-skill\ndescription: A sim skill. USE WHEN a test needs one. NOT FOR anything else.\n---\n\n# sim-skill\n' > "$_t/harbor-pack/skills/sim-skill/SKILL.md"
  printf '#!/bin/sh\necho sim\n' > "$_t/harbor-pack/bin/sim-tool.sh"
  python3 - "$_t" <<'PY'
import hashlib, json, sys
d = sys.argv[1]; fs = ["skills/sim-skill/SKILL.md", "bin/sim-tool.sh"]
json.dump({"schema": 1, "id": "sim-tools", "version": "1.0.0", "harbor_version": ">=1", "provides": ["skill", "script"],
           "files": [{"path": f, "sha256": hashlib.sha256(open(d + "/harbor-pack/" + f, "rb").read()).hexdigest()} for f in fs]}, open(d + "/extension.json", "w"))
PY
  adm_git add -A; adm_git commit -qm 'a company pack'; adm_git push -q origin HEAD:main 2>> "$LOG"
  _pc="$(adm_git rev-parse HEAD)"
  _sk="$MH/.claude/skills/sim-skill/SKILL.md"
  eq pack.control-before 'CONTROL: before the policy names the pack, the skill is not on the laptop' absent "$( [ -e "$_sk" ] && echo present || echo absent)"
  SIM_PACKS="[{\"id\":\"sim-tools\",\"commit\":\"$_pc\"}]"; publish enforce "$(CORE_NOW)"
  session start
  eq pack.policy-held 'the policy that names the pack is held' "$SERIAL" "$(held_serial)"
  eq pack.skill-landed "a session start lands the hub pack's skill in <member HOME>/.claude/skills" yes "$( [ -f "$_sk" ] && echo yes || echo no)"
  [ -f "$_sk" ] || { as_member - 1 "$WD" sh "$MROOT/bin/hub.sh" sync --no-fetch --live > "$OUT/pack-sync.log" 2>&1; cp "$RUN/h.err" "$OUT/pack-session.err" 2> /dev/null; }   # the why of a miss
  eq pack.skill-bytes "byte for byte the hub's file at the signed commit" "$(adm_git show "$_pc:packs/sim-tools/harbor-pack/skills/sim-skill/SKILL.md" | sha256sum | cut -d' ' -f1)" "$(sha256sum < "$_sk" 2> /dev/null | cut -d' ' -f1)"
  eq pack.skill-owner 'the member owns what landed' "$M" "$(stat -c %U "$_sk" 2> /dev/null)"
  eq pack.manifest-source 'its manifest says it came from the hub' hub "$(awk -F'\t' '$1 == "# source" { print $2 }' "$MH/.claude/.harbor-packs/hub-sim-tools.tsv" 2> /dev/null)"
  # the admin changes the pack and signs the new commit: ONE session start brings it
  printf 'second line\n' >> "$_t/harbor-pack/skills/sim-skill/SKILL.md"
  python3 - "$_t" <<'PY'
import hashlib, json, sys
d = sys.argv[1]; e = json.load(open(d + "/extension.json"))
for f in e["files"]: f["sha256"] = hashlib.sha256(open(d + "/harbor-pack/" + f["path"], "rb").read()).hexdigest()
json.dump(e, open(d + "/extension.json", "w"))
PY
  adm_git add -A; adm_git commit -qm 'a pack, second version'; adm_git push -q origin HEAD:main 2>> "$LOG"
  _pc2="$(adm_git rev-parse HEAD)"
  SIM_PACKS="[{\"id\":\"sim-tools\",\"commit\":\"$_pc2\"}]"; publish enforce "$(CORE_NOW)"
  session start
  eq pack.update 'a new signed commit of the pack lands at the next single session start' "$(adm_git show "$_pc2:packs/sim-tools/harbor-pack/skills/sim-skill/SKILL.md" | sha256sum | cut -d' ' -f1)" "$(sha256sum < "$_sk" 2> /dev/null | cut -d' ' -f1)"
  _pc="$_pc2"
  claude_real packs-list hello
  eq pack.claude-lists 'the real Claude Code lists the skill in a session' true "$(jsonl 'select(.subtype == "init") | .slash_commands | index("sim-skill") != null' packs-list)"
  # the policy drops the pack: the skill and its manifest go
  SIM_PACKS='[]'; publish enforce "$(CORE_NOW)"; session start
  eq pack.dropped 'a policy without the pack takes the skill away' absent "$( [ -e "$MH/.claude/skills/sim-skill" ] && echo present || echo absent)"
  eq pack.dropped-manifest 'and its manifest' absent "$( [ -e "$MH/.claude/.harbor-packs/hub-sim-tools.tsv" ] && echo present || echo absent)"
  # a pack pinned to a commit whose bytes differ from its manifest never lands
  printf 'tampered\n' >> "$_t/harbor-pack/skills/sim-skill/SKILL.md"; adm_git add -A; adm_git commit -qm 'a pack whose bytes drift from its manifest'; adm_git push -q origin HEAD:main 2>> "$LOG"
  SIM_PACKS="[{\"id\":\"sim-tools\",\"commit\":\"$(adm_git rev-parse HEAD)\"}]"; publish enforce "$(CORE_NOW)"; session start
  eq pack.drift-refused "a pack whose bytes differ from its extension.json's sha256 does not land" absent "$( [ -e "$_sk" ] && echo present || echo absent)"
  SIM_PACKS='[]'; publish enforce "$(CORE_NOW)"; session start
  # pack.sh --hub-tree: the hub gate's refusals, judged as a laptop judges them
  _ht=/srv/hubtree; rm -rf "$_ht"; mkdir -p "$_ht"; git init -q -b main "$_ht"
  _mk() { # <id> <extra file or -> : a pack with one skill
    _d="$_ht/packs/$1/harbor-pack"; mkdir -p "$_d/skills/s1"
    printf 'name = "%s"\nversion = "1.0.0"\nharbor_version = ">=1"\ndescription = "x"\n' "$1" > "$_d/pack.toml"
    printf -- '---\nname: s1\ndescription: A skill. USE WHEN a test needs one. NOT FOR anything else.\n---\n\n# s1\n' > "$_d/skills/s1/SKILL.md"
    _fs="skills/s1/SKILL.md"; if [ "$2" != - ]; then printf 'a\tb\n' > "$_d/$2"; _fs="$_fs $2"; fi
    python3 - "$1" $_fs <<'PY'
import hashlib, json, sys
i = sys.argv[1]; d = "/srv/hubtree/packs/%s/harbor-pack/" % i
json.dump({"schema": 1, "id": i, "version": "1.0.0", "harbor_version": ">=1", "provides": ["skill"],
           "files": [{"path": f, "sha256": hashlib.sha256(open(d + f, "rb").read()).hexdigest()} for f in sys.argv[2:]]}, open("/srv/hubtree/packs/%s/extension.json" % i, "w"))
PY
  }
  _mk good -; _mk withctl controls.tsv; _mk withterms terms.tsv; _mk withchecks checks.md; _mk badsha -; printf 'tamper\n' >> "$_ht/packs/badsha/harbor-pack/skills/s1/SKILL.md"
  _mk noext -; rm -f "$_ht/packs/noext/extension.json"
  git -C "$_ht" add -A; git -C "$_ht" -c user.name=sim -c user.email=sim@sim.test commit -qm packs
  _hubtree() { # <id> -> rc in _hr, output in $RUN/ht.out
    rm -rf /srv/hubtree-target; mkdir -p /srv/hubtree-target
    _hr=0; env -u CLAUDE_CONFIG_DIR HARBOR_SCOPE_ROOT=/opt/harbor-core sh /opt/harbor-core/bin/pack.sh install "$1" --hub --hub-tree "$_ht" --dir /srv/hubtree-target > "$RUN/ht.out" 2>&1 || _hr=$?
  }
  _hubtree good
  eq pack.tree-good 'CONTROL: pack.sh --hub-tree passes a sound pack' 0 "$_hr"
  for _c in withctl:controls.tsv withterms:terms.tsv withchecks:checks.md badsha:'differ' noext:'no extension.json'; do
    _hubtree "${_c%%:*}"
    if [ "$_hr" = 1 ] && grep -q "skipped hub-${_c%%:*}: .*${_c#*:}" "$RUN/ht.out"; then row PASS "pack.tree-${_c%%:*}" "refused, naming ${_c#*:}" "rc=$_hr" 'pack.sh --hub-tree'
    else row FAIL "pack.tree-${_c%%:*}" "refused, naming ${_c#*:}" "rc=$_hr, $(grep -m1 FAIL "$RUN/ht.out" | cut -c1-100)" 'pack.sh --hub-tree'; fi
  done
  _hubtree good; eq pack.tree-files 'the dry run writes nothing into its target' 0 "$(find /srv/hubtree-target -type f | wc -l | tr -d ' ')"
}

# ═══ 9 · enforcement on their own projects (d): a repo the member starts in ~/port is named at every session start ═══
yard() {
  say yard
  publish enforce "$(CORE_NOW)"
  as_member - 0 "$MH" sh -c "mkdir -p '$MH/port/notes-only' && git init -q '$MH/port/fresh-init' && git -C '$MH/port/fresh-init' -c user.name=alice -c user.email=alice@sim.test commit -q --allow-empty -m first && git clone -q '$MH/port/fresh-init' '$MH/port/cloned-hub'"
  session start
  _ctx="$(printf '%s' "$H_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2> /dev/null)"
  _msg="$(printf '%s' "$H_OUT" | jq -r '.systemMessage // ""' 2> /dev/null)"
  _names() { printf '%s' "$1" | sed -n 's/.*git repos Harbor does not govern yet: \(.*\)\. Ask your agent.*/\1/p'; }
  eq yard.person 'a fresh git init and a clone are named to the person, and nothing else is' 'cloned-hub, fresh-init' "$(_names "$_msg")"
  case "$_ctx" in *"harbor hub project register"*cloned-hub*|*cloned-hub*"harbor hub project register"*) row PASS yard.agent 'the agent is told the register command' named 'additionalContext' ;;
    *) row FAIL yard.agent 'the agent is told the register command' "${_ctx:-nothing}" 'additionalContext' ;; esac
  # the real Claude Code, a real session start under the managed settings
  claude_real yard hello
  _ss="$(jsonl 'select(.subtype == "hook_response" and .hook_event == "SessionStart") | .stdout' yard | jq -r '.systemMessage // empty' 2> /dev/null)"
  eq yard.real-session 'the real Claude Code session start carries the finding' 'cloned-hub, fresh-init' "$(_names "$_ss")"
  # fleet sees the repo: the disk scan that stands in for fleet's root scan lists both, as unregistered
  _fl="$(as_member - 1 "$WD" sh "$MROOT/bin/scope-repo-sources.sh" --not-adopted 2> /dev/null | sort | tr '\t\n' ' ')"
  eq yard.discovery 'the repo discovery lists both, unregistered, and not the core copy or a folder with no .git' 'cloned-hub - unregistered fresh-init - unregistered ' "$_fl"
  if command -v fleet > /dev/null 2>&1 || [ -x "$MH/port/fleet/bin/fleet" ]; then row INFO yard.fleet-cli 'the fleet CLI on a member laptop' present ''
  else row SEAM yard.fleet-cli 'fleet projects sees the repo' 'no fleet CLI on a member laptop' 'the member design ships no fleet (yard-fleet-design D3): the disk scan above is what stands in for it'; fi
  # registering one removes only that one
  _rc=0; as_member - 0 "$WD" sh "$MH/port/harbor/bin/harbor" hub project register fresh-init > "$OUT/yard-register.log" 2>&1 || _rc=$?
  case "$_rc" in 0|3) row PASS yard.register 'harbor hub project register fresh-init succeeds (0, or 3: checks that need yard could not look)' "rc=$_rc" "$(grep -m1 'health:' "$OUT/yard-register.log" | cut -c1-90)" ;;
    *) row FAIL yard.register 'harbor hub project register fresh-init succeeds (0, or 3)' "rc=$_rc" "$(tail -n 2 "$OUT/yard-register.log" | tr '\n' ' ' | cut -c1-120)" ;; esac
  eq yard.register-row 'and the registry holds a governed row for it' 1 "$(awk -F'\t' '$1 == "fresh-init" && $9 == "yes"' "$MH/port/harbor-private/repos.tsv" | wc -l | tr -d ' ')"
  # lane C: register also lays the project standard down; the project's own runner passes on the laptop, no yard, uv or just
  _fi="$MH/port/fresh-init"; _std='AGENTS.md CLAUDE.md docs/project-standard.md tests/run.sh tests/suites.txt tests/lib/core.sh tests/example/example.test.sh'
  _have=0; for _f in $_std; do as_member - 0 "$MH" test -f "$_fi/$_f" && _have=$((_have + 1)); done
  eq yard.standard 'register laid down the project standard: AGENTS.md, CLAUDE.md, the standard note, the runner, the harness and the example suite' 7 "$_have"
  eq yard.standard-import 'CLAUDE.md carries the bare @AGENTS.md import' 1 "$(as_member - 0 "$_fi" grep -cx @AGENTS.md CLAUDE.md 2> /dev/null)"
  eq yard.standard-marker 'and no governance marker: no .agents, no .claude/config.yaml' none "$([ -e "$_fi/.agents" ] || [ -e "$_fi/.claude/config.yaml" ] && echo marker || echo none)"
  _rc=0; as_member - 0 "$_fi" sh tests/run.sh > "$OUT/yard-standard-run.log" 2>&1 || _rc=$?
  eq yard.standard-runner "the project's own runner passes on the laptop (sh tests/run.sh)" '0 fresh-init: 5 passed, 0 failed' "$_rc $(tail -n 1 "$OUT/yard-standard-run.log")"
  _before="$(as_member - 0 "$_fi" git status --porcelain | cksum)"
  as_member - 0 "$WD" sh "$MH/port/harbor/bin/harbor" hub project register fresh-init > "$OUT/yard-register2.log" 2>&1 || :
  eq yard.standard-idempotent 'a second register changes nothing in the project' "$_before" "$(as_member - 0 "$_fi" git status --porcelain | cksum)"
  # lane E: the register made the memory route, the member's session can read and write it, the agent is told where, and a secret is refused
  _mm() { as_member - 1 "$MH/port/fresh-init" sh "$MROOT/bin/member-memory.sh" "$@"; }
  _route="$(_mm where 2> /dev/null)"
  case "$_route" in "$MH/.claude/projects/"*"-port-fresh-init/memory") row PASS memory.route 'register left a route at the harness key of the project' present "${_route##*/projects/}" ;;
    *) row FAIL memory.route 'register left a route at the harness key of the project' "${_route:-none}" 'member-memory.sh where, from the managed root' ;; esac
  eq memory.readable 'the member reads the store index through the route' yes "$(as_member - 0 "$MH" sh -c "[ -r '$_route/MEMORY.md' ] && [ -s '$_route/MEMORY.md' ] && echo yes || echo no")"
  _rc=0; printf 'the build needs make first\n' | as_member - 1 "$MH/port/fresh-init" sh "$MROOT/bin/member-memory.sh" add build-order > "$OUT/memory-add.log" 2>&1 || _rc=$?
  eq memory.write 'a note the agent writes lands in the route' 0 "$_rc"
  eq memory.found 'and is read back next session through the project key' yes "$(as_member - 0 "$MH" sh -c "grep -q 'make first' '$_route/build-order.md' && echo yes || echo no")"
  _tok="ghp_$(printf 'b%.0s' $(seq 1 36))"; _rc=0
  printf 'token %s\n' "$_tok" | as_member - 1 "$MH/port/fresh-init" sh "$MROOT/bin/member-memory.sh" add leaky > "$OUT/memory-leaky.log" 2>&1 || _rc=$?
  eq memory.secret-refused 'a credential-shaped note is refused (1)' 1 "$_rc"
  eq memory.secret-absent 'and no file is left' no "$(as_member - 0 "$MH" sh -c "[ -e '$_route/leaky.md' ] && echo yes || echo no")"
  _wd="$WD"; WD="$MH/port/fresh-init"; session start; WD="$_wd"
  case "$(printf '%s' "$H_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2> /dev/null)" in *"notes live in $_route"*) row PASS memory.told 'the session start tells the agent where the memory is' said 'additionalContext' ;;
    *) row FAIL memory.told 'the session start tells the agent where the memory is' "$(printf '%s' "$H_OUT" | cut -c1-80)" 'additionalContext' ;; esac
  session start; eq yard.registered 'registered, only the clone is still named' 'cloned-hub' "$(_names "$(printf '%s' "$H_OUT" | jq -r '.systemMessage // ""')")"
  # the member cannot switch it off
  eq yard.managed-only 'the user tier cannot add a hook: managed hooks only' true "$(jq -r '.allowManagedHooksOnly' "$MFILE")"
  as_member - 0 "$MH" sh -c "mkdir -p /tmp/sim-user-tier.keep && mv '$MH/.claude/settings.json' '$MH/.claude/context-rules' /tmp/sim-user-tier.keep/"
  session start
  eq yard.user-tier-removed "with the user tier's settings and context rules deleted, the finding stays" cloned-hub "$(_names "$(printf '%s' "$H_OUT" | jq -r '.systemMessage // ""')")"
  as_member - 0 "$MH" sh -c "mv /tmp/sim-user-tier.keep/settings.json /tmp/sim-user-tier.keep/context-rules '$MH/.claude/'"
  printf '%s\n' HARBOR_ADMISSION_DISABLE=1 HARBOR_SCOPE_REPO=/nonexistent PORT_ROOT=/nonexistent HARBOR_SCOPE_PRIVATE=/nonexistent "XDG_CONFIG_HOME=$RUN/nocfg" > "$RUN/env.yard"; chmod 644 "$RUN/env.yard"
  session start "$RUN/env.yard"
  eq yard.hostile-env 'with the switches an inherited environment can set, the finding stays' cloned-hub "$(_names "$(printf '%s' "$H_OUT" | jq -r '.systemMessage // ""')")"
  # a registry the member breaks must not read as "nothing to say"
  as_member - 0 "$MH" cp "$MH/port/harbor-private/repos.tsv" /tmp/sim-repos.keep
  as_member - 0 "$MH" sh -c "printf 'not a registry\\n' > '$MH/port/harbor-private/repos.tsv'"
  session start
  _broken="$(printf '%s' "$H_OUT" | jq -r '(.systemMessage // "") + (.hookSpecificOutput.additionalContext // "")' 2> /dev/null)"
  as_member - 0 "$MH" cp /tmp/sim-repos.keep "$MH/port/harbor-private/repos.tsv"
  case "$_broken" in *cloned-hub*|*registry*|*project\ list*) row PASS yard.registry-broken 'a broken registry is said, or the repos still named' said "$(printf '%s' "$_broken" | cut -c1-70)" '' ;;
    *) row FAIL yard.registry-broken 'a broken registry is said, or the repos still named' silent 'the member can mute the finding by corrupting repos.tsv' ;; esac
}

# ═══ 10 · logging (e) ═══
board_fetch() { # the heartbeat issues of the sim board, as bin/hub-fetch.sh prints them
  for _bf in "$BOARD"/issues/*.json; do
    _bn="${_bf##*/}"; _bn="${_bn%.json}"
    jq -n --slurpfile i "$_bf" --slurpfile c "$( [ -f "$BOARD/comments/$_bn.json" ] && echo "$BOARD/comments/$_bn.json" || echo /dev/null)" \
      '{title: $i[0].title, author: $i[0].user.login, comments: (($c[0] // []) | map({author: .user.login, created_at, body}))}'
  done | jq -s .
}
b64id() { python3 -c 'import base64, sys; print(base64.b64encode(bytes.fromhex(sys.argv[1])).decode())' "$1"; }
send_now() { as_member - 0 "$MH" rm -f "$HS/last-send"; session end; }   # the sender waits 15 minutes between comments; a session end sends
logging() {
  say logging
  LDR=/srv/loader; mkdir -p "$LDR"; chmod 700 "$LDR"
  command -v age-keygen > /dev/null 2>&1 || { row FAIL log.age 'age-keygen is on the box' absent 'contracts/member-prereqs.txt names age'; return; }
  rm -f "$LDR/identity.txt"; age-keygen -o "$LDR/identity.txt" 2> "$LDR/pub.txt"; REC="$(sed -n 's/.*Public key: //p' "$LDR/pub.txt")"
  SIM_LOGS="$REC"; publish enforce "$(CORE_NOW)"; session start
  eq log.recipient 'the signed policy carries the loader recipient' "$REC" "$(jq -r '.logs.recipient // empty' "$(hs path)" 2> /dev/null)"
  eq log.policy-reads 'CONTROL: with the loader in the policy a harmless call still runs (the floor reads a policy that names logs)' silent "$(bash_call 'ls -la')"
  # the random id: made at install, root's, sealed (never in clear anywhere the laptop sends)
  _idf=/etc/claude-code/harbor-ids/alice.id; _id="$(cat "$_idf" 2> /dev/null)"
  eq log.id-shape 'a random logs id exists, 32 hex' 1 "$(printf '%s\n' "$_id" | grep -cE '^[0-9a-f]{32}$')"
  eq log.id-owner 'root owns it' root "$(stat -c %U "$_idf" 2> /dev/null)"
  eq log.id-random 'and it is not derived from the login or the home' 0 "$(printf '%s\n' "$_id" | grep -c -F -e "$(printf alice | sha256sum | cut -c1-32)" -e "$(printf alice | md5sum | cut -c1-32)" -e "$(printf '%s' "$MH" | md5sum | cut -c1-32)")"
  eq log.id-member-write 'the member cannot change it' refused "$(as_member - 0 "$MH" sh -c "printf x >> '$_idf'" > /dev/null 2>&1 && echo changed || echo refused)"
  # the receipt gate: before IT records the signed receipt, no count is kept and nothing is sealed
  eq log.control-marker 'CONTROL: no receipt marker yet' absent "$( [ -e "$MROOT/notice-received" ] && echo present || echo absent)"
  as_member - 0 "$MH" rm -f "$HS/tally.jsonl" "$HS/outbox.jsonl" "$HS/outbox.pending.jsonl"
  bash_call 'ls -la' > /dev/null; bash_call 'ls -la' > /dev/null; session start
  eq log.gate-kept 'without the receipt nothing is counted' 0 "$(cat "$HS/tally.jsonl" 2> /dev/null | wc -l | tr -d ' ')"
  send_now
  eq log.gate-sealed 'and no comment carries a sealed field' 0 "$(board_fetch | jq '[.[].comments[].body | select(test("\"sealed\""))] | length')"
  # IT records the receipt: the install, re-run with the flag. The id survives it.
  _rc=0; sudo sh /opt/harbor-core/bin/member-install.sh --user "$M" --hub "$HUB" --login "$M" --signers /root/it/hub-signers --pin "$PIN" --notice-received > "$OUT/install-notice.log" 2>&1 || _rc=$?
  case "$_rc" in 0|4) row PASS log.receipt-install 'the install takes --notice-received' "rc=$_rc" '' ;; *) row FAIL log.receipt-install 'the install takes --notice-received' "rc=$_rc" "$(grep -m1 FAIL "$OUT/install-notice.log" | cut -c1-120)" ;; esac
  eq log.marker 'the marker is root-owned' 'root 644' "$(stat -c '%U %a' "$MROOT/notice-received" 2> /dev/null)"
  eq log.id-kept 'the id is the same after the re-install' "$_id" "$(cat "$_idf" 2> /dev/null)"
  eq log.marker-integrity 'the floor still checks with the marker in it' 0 "$(as_member - 1 "$WD" sh "$MROOT/bin/member-integrity.sh" check > /dev/null 2>&1; echo $?)"
  eq log.marker-member 'the member cannot write the marker' refused "$(as_member - 0 "$MH" sh -c "rm -f '$MROOT/notice-received'" > /dev/null 2>&1; [ -e "$MROOT/notice-received" ] && echo refused || echo removed)"
  # activity and session events, counted per day: the hook calls below are the whole workload
  as_member - 0 "$MH" rm -f "$HS/tally.jsonl" "$HS/outbox.jsonl" "$HS/outbox.pending.jsonl"
  session start
  for _i in 1 2 3; do bash_call 'ls -la' > /dev/null; done
  bash_call 'git reset --hard' > /dev/null
  pre Read "$(jq -cn --arg f "$WD/README.md" '{file_path:$f}')" > /dev/null
  pre mcp__claude_ai_Acme__list '{}' > /dev/null
  _tl="$HS/tally.jsonl"
  eq log.tally-kinds 'only activity and session events are in the tally' 'activity session' "$(jq -r '.kind' "$_tl" 2> /dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
  eq log.tally-day 'every count is stamped with a day, never an hour' 0 "$(jq -r 'select(.ts | test("T00:00:00Z$") | not) | .ts' "$_tl" 2> /dev/null | wc -l | tr -d ' ')"
  eq log.tally-count 'the calls are counted by tool, class and verdict (3 ls, 1 reset, 1 read, 1 mcp)' 6 "$(jq -s '[.[] | select(.kind == "activity") | .count] | add' "$_tl" 2> /dev/null)"
  eq log.tally-mcp 'an mcp tool is the word mcp, never its name' '0 1' "$(grep -c 'Acme' "$_tl" | tr -d '\n'; printf ' '; jq -s '[.[] | select(.tool == "mcp")] | length' "$_tl")"
  eq log.tally-verdicts 'by verdict: allowed and asked, none denied' 'allow ask' "$(jq -r 'select(.kind == "activity") | .verdict' "$_tl" 2> /dev/null | sort -u | tr '\n' ' ' | sed 's/ $//')"
  eq log.tally-session 'the session start is counted' 1 "$(jq -s '[.[] | select(.kind == "session" and .outcome == "started") | .count] | add' "$_tl" 2> /dev/null)"
  eq log.tally-no-text 'no command text reached the tally' 0 "$(grep -c -e 'reset' -e 'ls -la' -e README -e "$WD" "$_tl")"
  # sending: counts leave only sealed, and only the loader opens them
  send_now
  _board="$(board_fetch)"
  printf '%s\n' "$_board" > "$OUT/board.json"
  eq log.sealed-present 'the heartbeat carries a sealed field' 1 "$(printf '%s' "$_board" | jq '[.[].comments[].body | select(test("\"sealed\""))] | length > 0 | if . then 1 else 0 end')"
  eq log.sealed-no-clear 'no activity or session event is on the board in clear' 0 "$(printf '%s' "$_board" | jq '[.[].comments[].body | select(test("\"kind\":\"(activity|session)\""))] | length')"
  eq log.sealed-no-id 'and the id is not on the board in clear' 0 "$(printf '%s' "$_board" | grep -c -F "$_id")"
  _last="$(printf '%s' "$_board" | jq -r '[.[].comments[].body | select(test("\"sealed\""))] | last')"
  _sealed="$(printf '%s' "$_last" | sed -n 's/.*"sealed":"\([^"]*\)".*/\1/p')"
  printf '%s' "$_sealed" | base64 -d > "$RUN/sealed.age" 2> /dev/null
  age -d -i "$LDR/identity.txt" < "$RUN/sealed.age" > "$RUN/sealed.json" 2> /dev/null
  eq log.sealed-opens 'the loader opens it and finds the laptop id' "$_id" "$(jq -r '.id' "$RUN/sealed.json" 2> /dev/null)"
  eq log.sealed-counts 'with the counts inside' 6 "$(jq '[.events[] | select(.kind == "activity") | .count] | add' "$RUN/sealed.json" 2> /dev/null)"
  _rc=0; age -d -i "$ADM/key" < "$RUN/sealed.age" > /dev/null 2>&1 || _rc=$?
  [ "$_rc" != 0 ] && row PASS log.sealed-others 'another key cannot open it' "rc=$_rc" 'CONTROL: only the loader identity opens the seal' || row FAIL log.sealed-others 'another key cannot open it' 'opened' ''
  # the loader: bq-load.sh builds closed rows from the board
  rm -rf "$RUN/bq"; mkdir -p "$RUN/bq"
  board_fetch > "$RUN/bq/issues.json"
  sh /opt/harbor-core/bin/bq-load.sh policies "$ADM/hub" "$RUN/bq/pol" > "$OUT/bq-policies.log" 2>&1
  _rc=0; sh /opt/harbor-core/bin/bq-load.sh build --issues "$RUN/bq/issues.json" --policies "$RUN/bq/pol" --identity "$LDR/identity.txt" --out "$RUN/bq/out" --load-id 1 > "$OUT/bq-build.log" 2>&1 || _rc=$?
  eq log.load-build 'bq-load.sh build exits 0' 0 "$_rc"
  _b0="$(jq '.refused["bad-event"] // 0' "$RUN/bq/out/summary.json" 2> /dev/null)"
  eq log.load-kept 'and keeps the member sealed comment' yes "$( [ "$(jq .comments_kept "$RUN/bq/out/summary.json" 2> /dev/null)" -ge 1 ] 2> /dev/null && echo yes || echo no)"
  _stg="$RUN/bq/out/staging"
  eq log.load-person 'the rows are keyed by the id, as base64, not by the login' "$(b64id "$_id")" "$(jq -r -s 'map(.person_id) | unique | .[0]' "$_stg/activity.jsonl" 2> /dev/null)"
  eq log.load-activity 'the activity rows hold the 6 calls' 6 "$(jq -s '[.[].calls] | add' "$_stg/activity.jsonl" 2> /dev/null)"
  eq log.load-no-at 'no @ in any staged row' 0 "$(cat "$_stg"/*.jsonl | grep -c '@')"
  eq log.load-no-login 'no login in any staged row' 0 "$(cat "$_stg"/*.jsonl | grep -c -i -e "$M" -e "$ADMIN")"
  eq log.load-no-path 'no path in any staged row' 0 "$(cat "$_stg"/*.jsonl | grep -c -E -e '/home|/etc/|~/|/srv|port/work')"
  eq log.load-no-time 'no time finer than a day is staged beside the id' 0 "$(cat "$_stg"/*.jsonl | jq -c 'select(.person_id != null) | to_entries[] | select(.value | type == "string" and test("T[0-9]{2}:"))' | grep -c .)"
  # the planted email: refused at the laptop, and again at the loader
  _d0="$(wc -c < "$HS/dropped" 2> /dev/null || echo 0)"
  as_member - 1 "$WD" sh "$MROOT/bin/hub-events.sh" record activity tool=alice@example.com verb_class=readonly verdict=allow count=1
  as_member - 1 "$WD" sh "$MROOT/bin/hub-events.sh" record refusal rule=alice@example.com tier=high target=cloud count=1
  eq log.email-laptop 'a planted email is not kept by the laptop (no event is recorded)' 0 "$(cat "$HS/tally.jsonl" "$HS/outbox.jsonl" 2> /dev/null | wc -l | tr -d ' ')"
  eq log.email-outbox 'in neither file the sender reads' 0 "$(cat "$HS/tally.jsonl" "$HS/outbox.jsonl" 2> /dev/null | grep -c 'example.com')"
  eq log.email-counted 'and the refusals are counted, never repeated' yes "$( [ "$(wc -c < "$HS/dropped" 2> /dev/null || echo 0)" -gt "$_d0" ] && echo yes || echo no)"
  # a hostile laptop seals a payload with an email in a field, and posts it as the member
  jq -cn --arg d "$(date -u +%Y-%m-%dT00:00:00Z)" '[{v:1,kind:"activity",ts:$d,member:"alice",tool:"alice@example.com",verb_class:"readonly",verdict:"allow",count:1}]' > "$RUN/evil-events.json"
  jq -cn --arg id "$_id" --slurpfile e "$RUN/evil-events.json" '{v:1,id:$id,events:$e[0]}' | age -r "$REC" | base64 | tr -d '\n' > "$RUN/evil.sealed"
  _hbn="$(board_issues 'map(select(.title == "heartbeat alice")) | .[0].number')"
  jq -cn --rawfile s "$RUN/evil.sealed" '[{v:1,kind:"heartbeat",ts:"2026-11-10T05:00:00Z",member:"alice",core:"000000000000",contract:1,floor:"0000000000000000",serial:1,mode:"enforce",refusals:0,asks:0,requests:0,packs:[],sealed:$s}]' > "$RUN/evil-hb.json"
  jq -n --rawfile b "$RUN/evil-hb.json" '{body: ("```json\n" + $b + "\n```")}' > "$RUN/evil-comment.json"
  curl -q -sS -o /dev/null -X POST -H "Authorization: Bearer $TOKEN" --data-binary @"$RUN/evil-comment.json" "https://api.github.com/repos/$HUB/issues/$_hbn/comments"
  jq -cn '[{v:1,kind:"heartbeat",ts:"2026-11-10T05:00:00Z",member:"alice",core:"000000000000",contract:1,floor:"0000000000000000",serial:1,mode:"enforce",refusals:0,asks:0,requests:0,packs:[]},{v:1,kind:"refusal",ts:"2026-11-10T05:00:00Z",member:"alice",rule:"alice@example.com",tier:"high",target:"cloud",count:1}]' > "$RUN/evil-hb2.json"
  jq -n --rawfile b "$RUN/evil-hb2.json" '{body: ("```json\n" + $b + "\n```")}' > "$RUN/evil-comment2.json"
  curl -q -sS -o /dev/null -X POST -H "Authorization: Bearer $TOKEN" --data-binary @"$RUN/evil-comment2.json" "https://api.github.com/repos/$HUB/issues/$_hbn/comments"
  board_fetch > "$RUN/bq/issues2.json"
  eq log.email-on-board 'CONTROL: the planted emails are on the board (sealed, and in clear)' 1 "$(grep -c 'alice@example.com' "$RUN/bq/issues2.json" | awk '{print ($1 >= 1)}')"
  _rc=0; sh /opt/harbor-core/bin/bq-load.sh build --issues "$RUN/bq/issues2.json" --policies "$RUN/bq/pol" --identity "$LDR/identity.txt" --out "$RUN/bq/out2" --load-id 2 > "$OUT/bq-build2.log" 2>&1 || _rc=$?
  eq log.email-load-exit 'the loader still builds from the good comment' 0 "$_rc"
  eq log.email-refused 'and refuses both planted comments (bad-event, two more than before)' "$((_b0 + 2))" "$(jq '.refused["bad-event"] // 0' "$RUN/bq/out2/summary.json" 2> /dev/null)"
  eq log.email-staged 'no @ and no example.com in any staged row' 0 "$(cat "$RUN/bq/out2/staging"/*.jsonl | grep -c -e '@' -e 'example.com')"
  # harbor logs push: the closed rows, judged by the schema's own validator
  _o="$MH/.claude/MEMORY/OBSERVABILITY/sim-host"; _day="$(date -u +%Y-%m-%d)"
  as_member - 0 "$MH" mkdir -p "$_o" "$MH/.local/state/harbor/events"
  printf '%s\n' "{\"v\":1,\"ts\":\"${_day}T10:13:22Z\",\"g\":\"egress\",\"d\":\"block\",\"r\":\"key-material-egress\",\"s\":\"argv\",\"t\":\"Bash\",\"h\":\"d1d1d1d1d1d1d1d1\",\"sk\":\"5e55105e55105e55\",\"c\":\"confined\",\"x\":\"-\"}" \
    "{\"v\":1,\"ts\":\"${_day}T10:15:00Z\",\"g\":\"bash\",\"d\":\"allow\",\"r\":\"bash-clean\",\"s\":\"meta\",\"t\":\"Bash\",\"h\":\"-\",\"sk\":\"-\",\"c\":\"unconfined\",\"x\":\"cloud\"}" > "$RUN/obs.jsonl"
  chmod 644 "$RUN/obs.jsonl"; as_member - 0 "$MH" cp "$RUN/obs.jsonl" "$_o/guard-decisions.jsonl"
  _push() { as_member "$RUN/env.push" 0 "$WD" sh "$MH/port/harbor/bin/bq-logs.sh" push --since "$_day" --until "$_day" > "$RUN/push.out" 2> "$RUN/push.err"; }
  printf '%s\n' "XDG_CONFIG_HOME=$MH/.config" "XDG_STATE_HOME=$MH/.local/state" "HARBOR_EVENT_DIR=$MH/.local/state/harbor/events" > "$RUN/env.push"; chmod 644 "$RUN/env.push"
  _rc=0; _push || _rc=$?
  eq log.push-exit 'harbor logs push (dry run) exits 0' 0 "$_rc"
  eq log.push-rows 'and prints rows' yes "$( [ "$(wc -l < "$RUN/push.out" | tr -d ' ')" -ge 1 ] && echo yes || echo no)"
  _bad=0
  for _tb in $(jq -r '.table' "$RUN/push.out" | sort -u); do
    jq -c --arg t "$_tb" 'select(.table == $t) | .row' "$RUN/push.out" > "$RUN/push.$_tb.rows"
    sh /opt/harbor-core/bin/bq-format.sh row "$_tb" "$RUN/push.$_tb.rows" > /dev/null 2>&1 || _bad=$((_bad + 1))
  done
  eq log.push-schema 'every table of rows passes the closed schema validator' 0 "$_bad"
  eq log.push-clean 'no @, path or digest in a row' 0 "$(grep -c -E -e '@' -e '/home' -e 'd1d1d1d1' -e '5e55105e' "$RUN/push.out")"
  eq log.push-marker 'the dry run needs no marker, --apply does' refused "$(as_member "$RUN/env.push" 0 "$WD" sh "$MH/port/harbor/bin/bq-logs.sh" push --apply --since "$_day" --until "$_day" > /dev/null 2>&1 && echo sent || echo refused)"
  printf '%s\n' "{\"v\":1,\"ts\":\"${_day}T10:13:22Z\",\"g\":\"egress\",\"d\":\"block\",\"r\":\"alice@example.com\",\"s\":\"argv\",\"t\":\"Bash\",\"h\":\"-\",\"sk\":\"-\",\"c\":\"confined\",\"x\":\"-\"}" > "$RUN/obs2.jsonl"
  chmod 644 "$RUN/obs2.jsonl"; as_member - 0 "$MH" cp "$RUN/obs2.jsonl" "$_o/guard-decisions.jsonl"
  _rc=0; _push || _rc=$?
  eq log.push-email 'a ledger row holding an email: no row carries it' 0 "$(grep -c -e '@' -e 'example.com' "$RUN/push.out")"
  # the receipt withdrawn: the sender stops again
  _rc=0; sudo sh /opt/harbor-core/bin/member-install.sh --user "$M" --hub "$HUB" --login "$M" --signers /root/it/hub-signers --pin "$PIN" --notice-withdrawn > "$OUT/install-withdrawn.log" 2>&1 || _rc=$?
  eq log.withdrawn-marker 'withdrawn, the marker is gone' absent "$( [ -e "$MROOT/notice-received" ] && echo present || echo absent)"
  as_member - 0 "$MH" rm -f "$HS/tally.jsonl"; bash_call 'ls -la' > /dev/null
  eq log.withdrawn-kept 'and no count is kept' 0 "$(cat "$HS/tally.jsonl" 2> /dev/null | wc -l | tr -d ' ')"
  sudo sh /opt/harbor-core/bin/member-install.sh --user "$M" --hub "$HUB" --login "$M" --signers /root/it/hub-signers --pin "$PIN" --notice-received > "$OUT/install-notice2.log" 2>&1 || :
}

# ═══ 11 · the question tool and the waiting state (f) ═══
ask_tool() {
  say ask
  publish enforce "$(CORE_NOW)"; session start
  _q='{"questions":[{"question":"Which report do you want?","header":"Report","multiSelect":false,"options":[{"label":"Weekly","description":"the last 7 days"},{"label":"Monthly","description":"the last 30 days"}]}]}'
  eq ask.hook 'the managed PreToolUse hook lets AskUserQuestion through' silent "$(pre AskUserQuestion "$_q")"
  eq ask.config 'no managed permission, hook or tool list names it' 0 "$(jq -r '[.. | strings | select(test("AskUserQuestion"))] | length' "$MFILE")"
  claude_real ask-tools hello
  eq ask.claude-headless 'CONTROL: headless claude -p lists no AskUserQuestion with or without the managed file (it is an interactive tool)' 0 "$(jsonl 'select(.subtype == "init") | .tools | map(select(. == "AskUserQuestion")) | length' ask-tools)"
  # the classifier, in the member's environment: the Stop hook script on a transcript
  _ss="$MH/.claude/bin/session-state.sh"
  eq ask.script 'the session-state script is installed for the member' yes "$( [ -f "$_ss" ] && echo yes || echo no)"
  _cls() { # <id> <transcript lines file> <last message> -> state and reason
    _sd="/tmp/sim-ss-$1"; as_member - 0 "$MH" rm -rf "$_sd"; as_member - 0 "$MH" mkdir -p "$_sd"
    cp "$2" "$RUN/tx-$1.jsonl"; chmod 644 "$RUN/tx-$1.jsonl"
    jq -cn --arg s "$1" --arg t "$RUN/tx-$1.jsonl" --arg m "$3" --arg w "$WD" '{session_id:$s,transcript_path:$t,cwd:$w,hook_event_name:"Stop",stop_hook_active:false,last_assistant_message:$m}' > "$RUN/stop-$1.json"; chmod 644 "$RUN/stop-$1.json"
    printf '%s\n' "HARBOR_STATUS_DIR=$_sd" "XDG_STATE_HOME=$_sd" "HARBOR_EVENT_DIR=$_sd/events" > "$RUN/env.ss"; chmod 644 "$RUN/env.ss"
    as_member "$RUN/env.ss" 0 "$WD" sh "$_ss" < "$RUN/stop-$1.json" > /dev/null 2>&1
    jq -r '"\(.state) \(.reason)"' "$_sd"/sessions/"$1".json "$_sd"/harbor/sessions/"$1".json 2> /dev/null | head -n 1
  }
  jq -cn '{type:"assistant",message:{content:[{type:"tool_use",id:"q1",name:"AskUserQuestion",input:{}}]}}' > "$RUN/tx-ask.jsonl.src"
  jq -cn '{type:"assistant",message:{content:[{type:"text",text:"Done."}]}}' > "$RUN/tx-idle.jsonl.src"
  eq ask.waiting-tool 'a turn ending on an AskUserQuestion with no result is waiting-operator' 'waiting-operator W-ask' "$(_cls ask1 "$RUN/tx-ask.jsonl.src" 'Pick one.')"
  eq ask.waiting-text 'a turn ending on a question is waiting-operator, by contracts/session-waiting.tsv' 'waiting-operator W-question' "$(_cls ask2 "$RUN/tx-idle.jsonl.src" 'Which of the two do you want?')"
  eq ask.not-waiting 'CONTROL: a plain statement is not waiting' 'idle -' "$(_cls ask3 "$RUN/tx-idle.jsonl.src" 'Built the fix. All 12 tests pass.' | sed 's/ [A-Za-z-]*$/ -/')"
  claude_real ask-hooks hello
  # the expected count is the managed file's own SessionStart hooks (the session hook, and the context engine since lane B)
  _want="$(jq '[.hooks.SessionStart[]?.hooks[]?] | length' "$MFILE")"
  eq ask.user-tier-hooks 'in a real session only the managed SessionStart hooks run: the user tier (session-state is one) is switched off by allowManagedHooksOnly' "$_want" "$(jsonl 'select(.subtype == "hook_started" and .hook_event == "SessionStart") | .hook_id' ask-hooks | sort -u | wc -l | tr -d ' ')"
}

# ═══ 12 · the managed floor's sandbox (a) ═══
sandbox_floor() {
  say sandbox
  eq floor.sandbox-config 'the sandbox is on, fails closed, allows no unsandboxed command, and takes only the managed hosts' 'true true false true' \
    "$(jq -r '.sandbox | "\(.enabled) \(.failIfUnavailable) \(.allowUnsandboxedCommands) \(.network.allowManagedDomainsOnly)"' "$MFILE")"
  eq floor.secret-denied "the sandbox denies ~/.local/share/secret to its commands" 1 "$(jq '[.sandbox.credentials.files[] | select(.path == "~/.local/share/secret" and .mode == "deny")] | length' "$MFILE")"
  eq floor.managed-only 'managed hooks, permission rules and MCP servers only; no bypass mode' 'true true true disable' \
    "$(jq -r '"\(.allowManagedHooksOnly) \(.allowManagedPermissionRulesOnly) \(.allowManagedMcpServersOnly) \(.permissions.disableBypassPermissionsMode)"' "$MFILE")"
  # hooks fire from an empty environment with the pinned PATH, whatever the member's environment holds
  printf '%s\n' "PATH=$EVIL/bin:/usr/local/bin:/usr/bin" BASH_ENV=/tmp/evil LD_PRELOAD=/tmp/evil.so SIM_PLANTED=1 ENV=/tmp/evil > "$RUN/env.floor"; chmod 644 "$RUN/env.floor"
  _env="$(hook_env SessionStart "$RUN/env.floor" | sort)"
  printf '%s\n' "$_env" > "$OUT/hook-env.log"
  eq floor.hook-path 'the hook starts with the pinned PATH, not the member one' 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' "$(printf '%s\n' "$_env" | grep '^PATH=')"
  eq floor.hook-clean 'and none of the planted variables' 0 "$(printf '%s\n' "$_env" | grep -c -e BASH_ENV -e LD_PRELOAD -e SIM_PLANTED -e '^ENV=')"
  eq floor.hook-env-i 'the composed command begins with env -i' 1 "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$MFILE" | grep -c '^/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin ')"
  # the token store round-trips with no keyring and no session bus
  eq floor.no-keyring 'no keyring daemon or secret-tool is installed' '' "$(command -v gnome-keyring-daemon secret-tool 2> /dev/null | tr '\n' ' ' | sed 's/ $//')"
  as_member - 0 "$MH" sh -c "kill -0 1 2> /dev/null; [ ! -S /run/user/$MUID/bus ]"; eq floor.no-bus 'and no session bus is running for the member' 0 "$?"
  _sv="sim-roundtrip-$$"
  printf '%s' "$_sv" | as_member - 1 "$WD" sh "$MROOT/bin/access.sh" add sim-probe --kind token --what 'a sim probe' --use-when 'the sim' --reaches 'nothing' --cannot 'anything' --grant 'sim' --revoke 'sim' --secret sim-probe --value-stdin > "$OUT/store-probe.log" 2>&1
  eq floor.store-roundtrip 'bin/secret stores a value and a hook-environment read returns it' "$_sv" "$(as_member - 1 "$WD" sh "$MROOT/bin/secret" run sim-probe SIMV -- printenv SIMV 2> /dev/null)"
  eq floor.store-blob 'the stored blob does not hold the value' 0 "$(grep -r -l -F "$_sv" "$MH/.local/share/secret" 2> /dev/null | wc -l | tr -d ' ')"
  # the agent cannot read the store: the hook layer, for the read tools and for the shell
  eq floor.store-read 'the Read tool on the store is refused' deny-approval "$(pre Read "$(jq -cn --arg f "$MH/.local/share/secret/sim-probe.enc" '{file_path:$f}')")"
  eq floor.store-shell 'a shell command that names the store is refused' deny-approval "$(bash_call "python3 -c \"print(open('$MH/.local/share/secret/sim-probe.key').read())\"")"
  # the real Claude Code, as the member: with no sandbox that can start, it does not start
  _cr=0; as_member - 1 "$WD" env ANTHROPIC_API_KEY=sk-ant-sim-0000 "ANTHROPIC_BASE_URL=http://127.0.0.1:$STUB_PORT" claude -p hello --output-format json > "$OUT/claude-failclosed.json" 2> "$OUT/claude-failclosed.err" || _cr=$?
  case "$(cat "$OUT/claude-failclosed.json" "$OUT/claude-failclosed.err" 2> /dev/null)" in
    *sandbox_required_unavailable*|*"sandbox required but unavailable"*) row PASS floor.fail-closed 'with the sandbox unable to start the member session refuses to start' "rc=$_cr, sandbox_required_unavailable" 'real Claude Code, the managed failIfUnavailable' ;;
    *) row FAIL floor.fail-closed 'with the sandbox unable to start the member session refuses to start' "rc=$_cr, $(head -c 100 "$OUT/claude-failclosed.err")" '' ;; esac
  # a sandboxed command, really: root's bubblewrap on the member's files fails in an unprivileged container, so this stays a recorded gap
  printf '%s\n' '{"name":"Bash","input":{"command":"cat '"$WD"'/README.md","description":"control"}}' > "$RUN/q.sandbox"
  claude_real sandbox-run hello "$RUN/q.sandbox" --allowedTools Bash
  _res="$(jsonl 'select(.type == "user") | .message.content[]? | select(.type == "tool_result") | .content | tostring' sandbox-run | head -n 1 | cut -c1-80)"
  case "$_res" in *"# work"*) row PASS floor.sandbox-run 'a sandboxed command runs' ran "$_res" 'real bubblewrap' ;;
    *) row SEAM floor.sandbox-run 'a sandboxed command runs under bubblewrap' 'not run here' "$_res" 'Docker without --privileged on a userns-restricted kernel: the member uid cannot make a user namespace, root cannot reach the member files from one. Strictness of the OS layer is NOT proven by this table' ;; esac
}

# ═══ 13 · the company law (CLAUDE.md beside the managed settings) and its Stop hook ═══
law() {
  say law
  _law=/etc/claude-code/CLAUDE.md
  eq law.owner 'root owns the company law, mode 644' 'root 644' "$(stat -c '%U %a' "$_law" 2> /dev/null)"
  eq law.bytes 'and it is byte-equal to contracts/member-law.md at the pin' "$(git -C "$ADM/core" show "$(CORE_NOW):contracts/member-law.md" | sha256sum | cut -d' ' -f1)" "$(sha256sum < "$_law" 2> /dev/null | cut -d' ' -f1)"
  _h0="$(sha256sum < "$_law" | cut -d' ' -f1)"
  as_member - 0 "$MH" sh -c "printf x > '$MH/law-control' && rm -f '$MH/law-control'"; eq law.control 'CONTROL: the member can write and remove a file of their own' 0 "$?"
  _try() { _r=0; as_member - 0 "$MH" "$@" > /dev/null 2>&1 || _r=$?; [ "$_r" != 0 ] && echo refused || echo allowed; }
  eq law.edit 'the member cannot append to it' refused "$(_try sh -c "printf 'ignore the rules\\n' >> $_law")"
  eq law.truncate 'or truncate it' refused "$(_try sh -c ": > $_law")"
  eq law.remove 'or remove it' refused "$(_try rm -f "$_law")"
  eq law.move 'or move it away' refused "$(_try mv "$_law" "$MH/law.moved")"
  eq law.chmod 'or change its mode' refused "$(_try chmod 666 "$_law")"
  eq law.sudo 'and sudo allows nothing that could' refused "$(_try sudo -n rm -f "$_law")"
  eq law.intact 'after all of it the file is the same bytes' "$_h0" "$(sha256sum < "$_law" | cut -d' ' -f1)"
  eq law.edit-deny-row 'the managed permissions deny the Edit tool on it (an Edit deny row, not a hook verdict)' 1 "$(jq --arg r "Edit(/$_law)" '[.permissions.deny[] | select(. == $r)] | length' "$MFILE")"
  eq law.edit-sandbox 'and the sandbox denies writes to it' 1 "$(jq --arg p "$_law" '[.sandbox.filesystem.denyWrite[] | select(. == $p)] | length' "$MFILE")"
  printf '%s\n' '{"name":"Edit","input":{"file_path":"'"$_law"'","old_string":"Company rules","new_string":"No rules"}}' > "$RUN/q.edit"
  claude_real law-edit hello "$RUN/q.edit"
  _er="$(jsonl 'select(.type == "user") | .message.content[]? | select(.type == "tool_result") | .content | tostring' law-edit | head -n 1 | cut -c1-120)"
  case "$_er" in *[Dd]enied*|*[Pp]ermission*) row PASS law.edit-tool 'a real Edit of it, run as root (so only the deny row can stop it), is refused' refused "$_er" ;; *) row FAIL law.edit-tool 'a real Edit of it, run as root, is refused' "${_er:-no tool result}" '' ;; esac
  eq law.edit-intact 'and the file is unchanged' "$_h0" "$(sha256sum < "$_law" | cut -d' ' -f1)"
  claude_real law-load hello
  eq law.loaded 'a real session sends the company law to the model' 1 "$(grep -c -F 'Company rules for Claude Code' /srv/stub/log | awk '{print ($1 >= 1)}')"
  # the Stop hook, as composed
  _sc="$(jq -r '[.hooks.Stop[0].hooks[].command | select(test("member-upgrade.sh"))][0] // empty' "$MFILE")"
  [ -n "$_sc" ] && row PASS law.stop-wired 'a Stop hook runs member-upgrade.sh' wired "$(printf '%s' "$_sc" | cut -c1-60)" || row FAIL law.stop-wired 'a Stop hook runs member-upgrade.sh' absent ''
  eq law.stop-env 'and it starts from env -i with the pinned PATH' 1 "$(printf '%s' "$_sc" | grep -c "^/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin .* /bin/sh '$MROOT/bin/member-upgrade.sh'\$")"
  # a turn that used a tool and answered at length
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"build me the report"}}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}' > "$RUN/tx-law.jsonl"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"build me the report"}}' \
    '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}},{"type":"tool_use","id":"t2","name":"Agent","input":{}}]}}' > "$RUN/tx-law-agent.jsonl"
  chmod 644 "$RUN"/tx-law*.jsonl
  _long='I built the report from the three exports, checked the totals against the dashboard, and it works: the weekly revenue is 12 percent up on last week, and the file is saved in the work folder where you asked for it, with the chart on the first sheet and the raw rows on the second.'
  _stop() { # <transcript> <active true|false> <message> -> the hook's stdout in $S_OUT, rc in $S_RC
    jq -cn --arg t "$1" --argjson a "$2" --arg m "$3" '{session_id:"sim-1",transcript_path:$t,hook_event_name:"Stop",stop_hook_active:$a,last_assistant_message:$m}' > "$RUN/stop.json"; chmod 644 "$RUN/stop.json"
    S_RC=0; S_OUT="$(as_member - 1 "$WD" /bin/sh -c "$_sc" < "$RUN/stop.json" 2> /dev/null)" || S_RC=$?
  }
  _stop "$RUN/tx-law.jsonl" false "$_long"
  eq law.stop-block 'a worked answer with no Upgrade line is blocked' block "$(printf '%s' "$S_OUT" | jq -r '.decision // "none"' 2> /dev/null)"
  case "$(printf '%s' "$S_OUT" | jq -r '.reason // ""' 2> /dev/null)" in member.upgrade:*Upgrade:*) row PASS law.stop-reason 'and the reason names the check and the Upgrade line' named '' ;; *) row FAIL law.stop-reason 'and the reason names the check and the Upgrade line' "$(printf '%s' "$S_OUT" | cut -c1-80)" '' ;; esac
  _stop "$RUN/tx-law.jsonl" true "$_long"
  eq law.stop-active 'with stop_hook_active true it says nothing' '' "$S_OUT"
  eq law.stop-active-rc '...and exits 0' 0 "$S_RC"
  _stop "$RUN/tx-law-agent.jsonl" false "$_long
Upgrade: ask for the weekly report pack next time, it builds this in one step."
  eq law.stop-pass 'CONTROL: an answer with the Upgrade line and a second reader passes' '' "$S_OUT"
  # the same hook inside a real session: Claude is sent back once, then stops
  printf '%s\n' '{"name":"Bash","input":{"command":"ls","description":"a step"}}' '{"text":"'"$_long"'"}' > "$RUN/q.law"
  claude_real law-stop hello "$RUN/q.law" --allowedTools Bash
  eq law.real-block 'in a real session the Stop hook sends Claude back with member.upgrade' 1 "$(jsonl 'select(.subtype == "hook_response" and .hook_event == "Stop") | .stdout' law-stop | grep -c '"decision":"block"' | awk '{print ($1 >= 1)}')"
}

# ═══ 14 · personal tools (member.tools-sync): a new skill lands in the personal repo, and an unreachable repo changes nothing ═══
# The personal repo <org>/tools-<login> is a bare repo under the stand-in GitHub (sim_github.py serves it with git http-backend, receive-pack on).
tools_sync() {
  say tools
  _tr="$GIT/acme/tools-alice.git"; _own="$MH/.claude/skills/sim-own"
  _tstate() { { find "$MH/.claude/skills" "$MH/.claude/agents" "$MH/.claude/commands" "$MH/.local/state/harbor/tools" -type f 2> /dev/null | sort | xargs -r cksum 2> /dev/null; } | sha256sum | cut -d' ' -f1; }
  _tstop() { jq -cn --arg w "$WD" '{session_id:"sim-1",hook_event_name:"Stop",stop_hook_active:false,cwd:$w}' > "$RUN/tools-stop.json"; chmod 644 "$RUN/tools-stop.json"
    _tc="$(jq -r '[.hooks.Stop[0].hooks[].command | select(test("member-tools.sh"))][0] // empty' "$MFILE")"
    [ -n "$_tc" ] || { row FAIL tools.stop-wired 'a Stop hook runs member-tools.sh push' absent ''; return 1; }
    TS_RC=0; as_member - 1 "$WD" /bin/sh -c "$_tc" < "$RUN/tools-stop.json" > "$RUN/tools-stop.out" 2> "$RUN/tools-stop.err" || TS_RC=$?; }
  _tstop; eq tools.stop-wired 'a managed Stop hook runs member-tools.sh push, and with no repo it exits 0' 0 "$TS_RC"
  eq tools.stop-silent 'the Stop hook says nothing on stdout, which is the hook reply' '' "$(cat "$RUN/tools-stop.out")"
  # the personal repo does not exist: a session start and a Stop change nothing
  _t0="$(_tstate)"; session start; _tstop
  eq tools.missing-repo 'no personal repo: a session start and a Stop change nothing in the personal place or the tools state' "$_t0" "$(_tstate)"
  # it exists, and another laptop of the person put a skill there
  git init -q --bare -b main "$_tr"; git -C "$_tr" config http.receivepack true
  rm -rf "$ADM/tools-seed"; git init -q -b main "$ADM/tools-seed"; mkdir -p "$ADM/tools-seed/skills/sim-remote"
  printf -- '---\nname: sim-remote\ndescription: A skill from the other laptop. USE WHEN a test needs one.\n---\n\n# sim-remote\n' > "$ADM/tools-seed/skills/sim-remote/SKILL.md"
  git -C "$ADM/tools-seed" add -A; git -C "$ADM/tools-seed" -c user.name=sim -c user.email=sim@sim.test commit -qm seed; git -C "$ADM/tools-seed" push -q "$_tr" HEAD:refs/heads/main 2>> "$LOG"
  eq tools.control-before 'CONTROL: before the next session start the skill is not on the laptop' absent "$( [ -e "$MH/.claude/skills/sim-remote" ] && echo present || echo absent)"
  session start
  eq tools.pull 'a session start pulls the personal repo: its skill lands in <member HOME>/.claude/skills' yes "$( [ -f "$MH/.claude/skills/sim-remote/SKILL.md" ] && echo yes || echo no)"
  eq tools.owner 'the member owns it' "$M" "$(stat -c %U "$MH/.claude/skills/sim-remote/SKILL.md" 2> /dev/null)"
  eq tools.not-in-root 'and nothing of it is under the managed root' 0 "$(find "$MROOT" -path '*sim-remote*' | wc -l | tr -d ' ')"
  # the agent writes a new skill in the personal place; the end of the turn saves it
  as_member - 0 "$MH" sh -c "mkdir -p '$_own' && printf -- '---\nname: sim-own\ndescription: Written by the agent for the person. USE WHEN a test needs one.\n---\n\n# sim-own\n' > '$_own/SKILL.md'"
  _tstop
  eq tools.push 'a new skill in the personal place is in the personal repo after the Stop hook' yes "$(git -C "$_tr" cat-file -e main:skills/sim-own/SKILL.md 2> /dev/null && echo yes || echo no)"
  eq tools.push-keeps 'and the skill from the other laptop is still there' yes "$(git -C "$_tr" cat-file -e main:skills/sim-remote/SKILL.md 2> /dev/null && echo yes || echo no)"
  # the repo goes away: nothing changes, nothing blocks
  mv "$_tr" "$_tr.away"; as_member - 0 "$MH" sh -c "printf 'more\n' >> '$_own/SKILL.md'"
  _t0="$(_tstate)"; session start; _ss="$H_RC"; _tstop
  eq tools.unreachable 'an unreachable personal repo: a session start and a Stop change nothing on disk' "$_t0" "$(_tstate)"
  eq tools.unreachable-rc 'and neither blocks (session exit 0, Stop exit 0)' '0 0' "$_ss $TS_RC"
  mv "$_tr.away" "$_tr"; _tstop
  eq tools.recovers 'when the repo is back the next Stop sends the edit' yes "$(git -C "$_tr" show main:skills/sim-own/SKILL.md 2> /dev/null | grep -c '^more$' | awk '{print ($1 >= 1) ? "yes" : "no"}')"
}

# ═══ 15 · tests are written (lane D): a code change in a registered project without a test is sent back, once; with a test it passes ═══
tests_written() {
  say tests
  _p="$MH/port/member-proj"
  as_member - 0 "$MH" sh -c "rm -rf '$_p' && mkdir -p '$_p' && git init -q '$_p' && printf 'def f():\n    return 1\n' > '$_p/app.py' && printf 'notes\n' > '$_p/README.md' && git -C '$_p' add -A && git -C '$_p' -c user.name=alice -c user.email=alice@sim.test commit -q -m first"
  as_member - 0 "$WD" sh "$MH/port/harbor/bin/harbor" hub project register member-proj > "$OUT/tests-register.log" 2>&1 || :
  eq tests.registered 'the project is registered and has its own runner' '1 yes' "$(awk -F'\t' '$1 == "member-proj"' "$MH/port/harbor-private/repos.tsv" | wc -l | tr -d ' ') $([ -f "$_p/tests/run.sh" ] && echo yes || echo no)"
  _sn="$(jq -r '.hooks.UserPromptSubmit[0].hooks[1].command // empty' "$MFILE")"; _st="$(jq -r '.hooks.Stop[0].hooks[2].command // empty' "$MFILE")"
  case "$_sn" in *"member-tests.sh' snap") row PASS tests.snap-wired 'UserPromptSubmit runs the snapshot' wired "$(printf '%s' "$_sn" | cut -c1-60)" ;; *) row FAIL tests.snap-wired 'UserPromptSubmit runs the snapshot' "${_sn:-absent}" '' ;; esac
  case "$_st" in *"member-tests.sh'") row PASS tests.stop-wired 'Stop runs the test check' wired "$(printf '%s' "$_st" | cut -c1-60)" ;; *) row FAIL tests.stop-wired 'Stop runs the test check' "${_st:-absent}" '' ;; esac
  _run() { # <command> [stop_hook_active] -> the hook's stdout in $T_OUT
    jq -cn --arg a "${2:-false}" '{session_id:"sim-t",hook_event_name:"Stop",stop_hook_active:($a == "true")}' > "$RUN/ts.json"; chmod 644 "$RUN/ts.json"
    T_OUT="$(as_member - 1 "$WD" /bin/sh -c "$1" < "$RUN/ts.json" 2> /dev/null)" || :
  }
  _run "$_sn"; _run "$_st"
  eq tests.control 'CONTROL: a turn that wrote nothing is not sent back' '' "$T_OUT"
  as_member - 0 "$MH" sh -c "printf 'def g():\n    return 2\n' >> '$_p/app.py'"   # a write by a command: no Edit, no transcript
  _run "$_st"
  eq tests.block 'a code change with no test is sent back' block "$(printf '%s' "$T_OUT" | jq -r '.decision // "none"' 2> /dev/null)"
  case "$(printf '%s' "$T_OUT" | jq -r '.reason // ""' 2> /dev/null)" in member.tests:*test-writing-trivial*tests/run.sh*) row PASS tests.reason 'the reason names the check, the architecture and the runner' named '' ;; *) row FAIL tests.reason 'the reason names the check, the architecture and the runner' "$(printf '%s' "$T_OUT" | cut -c1-80)" '' ;; esac
  _run "$_st" true; eq tests.once 'with stop_hook_active it never blocks twice' '' "$T_OUT"
  _run "$_sn"; as_member - 0 "$MH" sh -c "printf 'def h():\n    return 3\n' >> '$_p/app.py'; mkdir -p '$_p/tests/app'; printf '#!/bin/sh\nexit 0\n' > '$_p/tests/app/app.test.sh'"
  _run "$_st"; eq tests.pass 'the same kind of change with a test beside it passes' '' "$T_OUT"
  _run "$_sn"; as_member - 0 "$MH" sh -c "printf 'more notes\n' >> '$_p/README.md'"
  _run "$_st"; eq tests.docs 'a docs-only change passes' '' "$T_OUT"
  # the same checks inside a real session: a Write tool call creates a code file, the Stop hook sends Claude back. A Bash call can't carry it here: the
  # container has no user namespace, so the Bash tool's own sandbox (bwrap) refuses to start; the command-write path is the rows above.
  as_member - 0 "$MH" sh -c "git config --global --add safe.directory '$_p'"
  jq -cn --arg f "$_p/extra.py" '{name:"Write",input:{file_path:$f,content:"def k():\n    return 4\n"}}' > "$RUN/q.tests"
  printf '%s\n' '{"text":"I added the function in extra.py so it returns the new value, and the file is saved in the project folder where you asked for it."}' >> "$RUN/q.tests"
  claude_real tests-stop hello "$RUN/q.tests" --permission-mode acceptEdits --add-dir "$_p"
  eq tests.real-block 'in a real session the Stop hook sends Claude back with member.tests' 1 "$(jsonl 'select(.subtype == "hook_response" and .hook_event == "Stop") | .stdout' tests-stop | grep -c 'member.tests' | awk '{print ($1 >= 1)}')"
}
