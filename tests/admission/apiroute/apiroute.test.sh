#!/usr/bin/env sh
# admission-api-route.sh (harbor#545, #547): Claude Code's own API route is not a setting a session may
# change. Every case runs on a fixture config dir and project dir, since the guard REWRITES what it
# judges. INCIDENT is claude-code-router 3.1.0's 2026-09-17 edit, key for key, values made harmless.
. "$(dirname "$0")/../../lib/core.sh"; t_init
DIR="$T_ROOT/bin"; GUARD="$DIR/admission-api-route.sh"; TMP="$T_TMP/ar"; mkdir -p "$TMP"
CLEAN='{
  "model": "opus",
  "hooks": {}
}'
INCIDENT='{
  "apiKeyHelper": "/nonexistent/ccr-claude-code-api-key-default-claude-code",
  "env": {
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_API_BASE_URL": "http://127.0.0.1:3456",
    "CLAUDE_AGENT_API_BASE_URL": "http://127.0.0.1:3456",
    "ANTHROPIC_AUTH_TOKEN": "sk-TESTVALUE-must-never-be-printed",
    "NO_PROXY": "127.0.0.1,localhost,::1"
  },
  "model": "opus",
  "hooks": {}
}'
LEGIT='{
  "env": {
    "ANTHROPIC_API_KEY": "sk-LEGITVALUE-must-never-be-printed",
    "HTTPS_PROXY": "http://proxy.example:8080"
  },
  "model": "opus"
}'
fresh() { _d="$TMP/$1"; rm -rf "$_d"; mkdir -p "$_d/cfg" "$_d/proj"; printf '%s' "$_d"; }  # <name>
fire() { # <fixture> <event> [<guard>] → OUT, ERR
  _p="$(printf '{"hook_event_name":"%s","tool_name":"Bash","cwd":"/nonexistent-cwd"}' "$2")"
  OUT="$(printf '%s' "$_p" | env CLAUDE_CONFIG_DIR="$1/cfg" CLAUDE_PROJECT_DIR="$1/proj" "${FIRE_SH:-sh}" "${3:-$GUARD}" 2>"$TMP/err")"
  ERR="$(cat "$TMP/err" 2>/dev/null)"
}
routed() { jq -e '(.apiKeyHelper != null) or ((.env // {}) | has("ANTHROPIC_BASE_URL"))' "$1" >/dev/null 2>&1; }
yn() { "$@" && echo yes || echo no; }
put() { printf '%s\n' "$2" >"$1"; }
decision() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }

t_section "a clean settings file is accepted and left alone"
D="$(fresh clean)"; put "$D/cfg/settings.json" "$CLEAN"; cp "$D/cfg/settings.json" "$D/before"
fire "$D" PostToolUse
t_eq "no output" "" "$OUT"
t_eq "the file is unchanged" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"
t_eq "an accepted copy is kept" yes "$(yn test -f "$D/cfg/.helm-apiroute/${D#/}/cfg/settings.json.accepted")"

t_section "the 2026-09-17 edit is put back byte for byte, and the call is told why"
put "$D/cfg/settings.json" "$INCIDENT"
fire "$D" PostToolUse
t_eq "restored to its accepted bytes" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"
t_eq "the tool call is blocked" block "$(decision .decision)"
for _k in apiKeyHelper ANTHROPIC_BASE_URL ANTHROPIC_API_BASE_URL CLAUDE_AGENT_API_BASE_URL ANTHROPIC_AUTH_TOKEN; do
  t_has "the reason names $_k" "$OUT" "$_k"
done
t_eq "the rerouted copy is kept as evidence" 1 "$(find "$D/cfg" -maxdepth 1 -name 'settings.json.apiroute-*' | wc -l | tr -d ' ')"
t_has "the evidence copy carries the credential value" "$(cat "$D"/cfg/settings.json.apiroute-* 2>/dev/null)" "TESTVALUE"
t_hasnt "no credential VALUE reaches the output" "$OUT$ERR" "TESTVALUE"
t_eq "the repair is stamped [check:admission.api-route] in checks.log" 1 \
  "$(grep -c '^\[check:admission.api-route\] .*action=restored the last accepted copy' "$D/cfg/cache/checks.log" 2>/dev/null)"

t_section "first sight keeps an operator's existing route, and says so once (#547)"
D="$(fresh legit)"; put "$D/cfg/settings.json" "$LEGIT"; cp "$D/cfg/settings.json" "$D/before"
fire "$D" SessionStart
t_eq "a pre-existing credential or proxy is not rewritten" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"
t_eq "the note is SessionStart context" SessionStart "$(decision .hookSpecificOutput.hookEventName)"
case "$OUT" in *ANTHROPIC_API_KEY*HTTPS_PROXY*) _o=named ;; *) _o="$OUT" ;; esac
t_eq "the note names both keys, in order" named "$_o"
t_has "the guard's input held the key's value" "$(cat "$D/cfg/settings.json")" "LEGITVALUE"
t_has "and the proxy's" "$(cat "$D/cfg/settings.json")" "proxy.example"
t_hasnt "no key VALUE reaches the note" "$OUT$ERR" "LEGITVALUE"
t_hasnt "no proxy VALUE reaches the note" "$OUT$ERR" "proxy.example"
t_eq "the baseline is stamped in checks.log" 1 "$(grep -c 'action=kept as the baseline at first sight' "$D/cfg/cache/checks.log" 2>/dev/null)"
fire "$D" SessionStart
t_eq "the note does not repeat on the next run" "" "$OUT"

t_section "after the baseline: an added key goes, a changed value goes, a dropped key stays dropped"
jq '.env.ANTHROPIC_BASE_URL = "http://127.0.0.1:3456"' "$D/before" >"$D/cfg/settings.json"
fire "$D" PostToolUse
t_eq "an added key is put back" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"
jq '.env.HTTPS_PROXY = "http://127.0.0.1:3456"' "$D/before" >"$D/cfg/settings.json"
fire "$D" PostToolUse
t_eq "a baselined key pointed somewhere new is put back" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"
t_has "the changed key is named" "$OUT" "HTTPS_PROXY"
jq 'del(.env.HTTPS_PROXY)' "$D/before" >"$D/cfg/settings.json"; cp "$D/cfg/settings.json" "$D/dropped"
fire "$D" PostToolUse
t_eq "a dropped route key is not restored" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/dropped")"
t_eq "nor reported as a reroute" "" "$OUT"

t_section "a file that ARRIVES under watch loses only its route keys"
D="$(fresh arrived)"
fire "$D" PostToolUse
put "$D/cfg/settings.json" "$INCIDENT"
fire "$D" PostToolUse
t_eq "the route keys are gone" no "$(yn routed "$D/cfg/settings.json")"
t_eq "a non-route env key survives" 1 "$(jq -r '.env.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY // "gone"' "$D/cfg/settings.json")"
t_eq "an unrelated top-level key survives" opus "$(jq -r '.model' "$D/cfg/settings.json")"

t_section "a file deleted after it was accepted is watched as absent"
D="$(fresh deleted)"; put "$D/cfg/settings.json" "$CLEAN"; fire "$D" PostToolUse
rm -f "$D/cfg/settings.json"; fire "$D" PostToolUse
put "$D/cfg/settings.json" "$INCIDENT"; fire "$D" PostToolUse
t_eq "a reroute written into a re-created file does not survive" no "$(yn routed "$D/cfg/settings.json")"

t_section "wiping cache/ in the same call as a reroute does not reset the baseline"
D="$(fresh wipe)"; put "$D/cfg/settings.json" "$CLEAN"; fire "$D" SessionStart
rm -rf "$D/cfg/cache"; put "$D/cfg/settings.json" "$INCIDENT"; fire "$D" PostToolUse
t_eq "the reroute does not pass as a first sight" no "$(yn routed "$D/cfg/settings.json")"

t_section "a half-written file is still seen, and the accepted copy repairs it"
D="$(fresh partial)"; put "$D/cfg/settings.json" "$CLEAN"; cp "$D/cfg/settings.json" "$D/before"; fire "$D" PostToolUse
printf '{\n  "env": {\n    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456",\n' >"$D/cfg/settings.json"
fire "$D" PostToolUse
t_eq "unparseable JSON setting a route key is repaired" yes "$(yn cmp -s "$D/cfg/settings.json" "$D/before")"

t_section "the operator's allow list is honoured, and only it"
D="$(fresh allow)"; printf 'ANTHROPIC_BASE_URL\n' >"$D/cfg/.helm-apiroute-allow"
fire "$D" PostToolUse
put "$D/cfg/settings.json" "$INCIDENT"; fire "$D" PostToolUse
t_eq "an allowed key stays" "http://127.0.0.1:3456" "$(jq -r '.env.ANTHROPIC_BASE_URL // "gone"' "$D/cfg/settings.json")"
t_eq "a key not on the list goes" gone "$(jq -r '.apiKeyHelper // "gone"' "$D/cfg/settings.json")"

t_section "the project's settings count (CLAUDE_PROJECT_DIR, not the payload cwd)"
D="$(fresh project)"; put "$D/cfg/settings.json" "$CLEAN"; mkdir -p "$D/proj/.claude"
fire "$D" SessionStart
printf '{\n  "env": {\n    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3456"\n  }\n}\n' >"$D/proj/.claude/settings.local.json"
fire "$D" SessionStart
t_eq "SessionStart answers as additionalContext" SessionStart "$(decision .hookSpecificOutput.hookEventName)"
t_eq "the project file loses its route key" false "$(jq '.env | has("ANTHROPIC_BASE_URL")' "$D/proj/.claude/settings.local.json" 2>/dev/null)"

t_section "the kill switch stands the guard down"
D="$(fresh kill)"; put "$D/cfg/settings.json" "$CLEAN"; fire "$D" PostToolUse
put "$D/cfg/settings.json" "$INCIDENT"
printf '{"hook_event_name":"PostToolUse","tool_name":"Bash"}' \
  | env HARBOR_ADMISSION_DISABLE=1 CLAUDE_CONFIG_DIR="$D/cfg" CLAUDE_PROJECT_DIR="$D/proj" sh "$GUARD" >/dev/null 2>&1
t_eq "HARBOR_ADMISSION_DISABLE=1 leaves the reroute in place" yes "$(yn routed "$D/cfg/settings.json")"

t_section "the accepted copy follows its file's mtime both ways, under sh and dash (harbor#811)"
# accept() recopies only when the two mtimes differ, either way; #811 moved that off test's
# -nt/-ot. Explicit sub-second stamps: two writes inside one second must not look "in step".
acc() { printf '%s' "$1/cfg/.helm-apiroute/${1#/}/cfg/settings.json.accepted"; }  # <fixture>
mtime() { touch -d "2020-01-01 00:00:$2" "$1"; }  # <file> <SS[.frac]>
SONNET='{"model":"sonnet"}'
mt_base() { # <guard> <name> <SS> — CLEAN accepted at 00:00:<SS>, then SONNET written; → _d
  _d="$(fresh "$2")"; put "$_d/cfg/settings.json" "$CLEAN"; mtime "$_d/cfg/settings.json" "$3"
  cp "$_d/cfg/settings.json" "$_d/before"; fire "$_d" PostToolUse "$1"; put "$_d/cfg/settings.json" "$SONNET"
}
sc_newer() { mt_base "$1" mtn 10; mtime "$_d/cfg/settings.json" 20; fire "$_d" PostToolUse "$1"; cmp -s "$_d/cfg/settings.json" "$(acc "$_d")"; }
sc_older() { mt_base "$1" mto 10; mtime "$_d/cfg/settings.json" 05; fire "$_d" PostToolUse "$1"; cmp -s "$_d/cfg/settings.json" "$(acc "$_d")"; }
sc_subsec() { mt_base "$1" mts 10.1; mtime "$_d/cfg/settings.json" 10.6; fire "$_d" PostToolUse "$1"; cmp -s "$_d/cfg/settings.json" "$(acc "$_d")"; }
sc_instep() { # same mtime as the accepted copy → no copy is made, so the copy keeps its bytes
  mt_base "$1" mti 10; touch -r "$(acc "$_d")" "$_d/cfg/settings.json"; fire "$_d" PostToolUse "$1"
  cmp -s "$(acc "$_d")" "$_d/before"
}
sc_symlink() { # a symlinked settings file is judged by its target's mtime, as test's operators did
  _d="$(fresh mtl)"; put "$_d/real.json" "$CLEAN"; mtime "$_d/real.json" 10; cp "$_d/real.json" "$_d/before"
  ln -s "$_d/real.json" "$_d/cfg/settings.json"; fire "$_d" PostToolUse "$1"
  put "$_d/real.json" "$SONNET"; touch -r "$(acc "$_d")" "$_d/real.json"; fire "$_d" PostToolUse "$1"
  cmp -s "$(acc "$_d")" "$_d/before"
}
sc_redrop() { # a route key dropped within its accepted copy's second, then re-added → put back
  _d="$(fresh mtr)"; put "$_d/cfg/settings.json" "$LEGIT"; mtime "$_d/cfg/settings.json" 10.1; fire "$_d" SessionStart "$1"
  jq 'del(.env.HTTPS_PROXY)' "$_d/cfg/settings.json" >"$_d/dropped"; cp "$_d/dropped" "$_d/cfg/settings.json"
  mtime "$_d/cfg/settings.json" 10.6; fire "$_d" PostToolUse "$1"
  put "$_d/cfg/settings.json" "$LEGIT"; fire "$_d" PostToolUse "$1"
  cmp -s "$_d/cfg/settings.json" "$_d/dropped"
}
_shells=sh
if command -v dash >/dev/null 2>&1; then _shells="sh dash"; else printf '  note: dash is absent, so these rows ran under sh only\n'; fi
for FIRE_SH in $_shells; do
  t_eq "$FIRE_SH: a file newer than its accepted copy is accepted again" yes "$(yn sc_newer "$GUARD")"
  t_eq "$FIRE_SH: a file OLDER than its accepted copy is accepted again" yes "$(yn sc_older "$GUARD")"
  t_eq "$FIRE_SH: a rewrite in the same second as the accepted copy is accepted again" yes "$(yn sc_subsec "$GUARD")"
  t_eq "$FIRE_SH: a file in step with its accepted copy is not copied again" yes "$(yn sc_instep "$GUARD")"
  t_eq "$FIRE_SH: a symlinked file is in step by its target's mtime" yes "$(yn sc_symlink "$GUARD")"
  t_eq "$FIRE_SH: a key dropped in that same second, then re-added, is put back" yes "$(yn sc_redrop "$GUARD")"
done
FIRE_SH=sh

t_section "mutants: each removes one part, and its scenario must fail"
sc_incident() { # accepted clean file, then the 2026-09-17 edit → put back
  _d="$(fresh "sc$$i")"; put "$_d/cfg/settings.json" "$CLEAN"; fire "$_d" PostToolUse "$1"
  put "$_d/cfg/settings.json" "$INCIDENT"; fire "$_d" PostToolUse "$1"
  ! routed "$_d/cfg/settings.json"
}
sc_first_sight() { # an operator's route at first sight → untouched
  _d="$(fresh "sc$$f")"; put "$_d/cfg/settings.json" "$LEGIT"; cp "$_d/cfg/settings.json" "$_d/before"
  fire "$_d" SessionStart "$1"
  cmp -s "$_d/cfg/settings.json" "$_d/before"
}
sc_changed() { # a baselined key pointed at the dead port → put back
  _d="$(fresh "sc$$c")"; put "$_d/cfg/settings.json" "$LEGIT"; cp "$_d/cfg/settings.json" "$_d/before"
  fire "$_d" SessionStart "$1"
  jq '.env.HTTPS_PROXY = "http://127.0.0.1:3456"' "$_d/before" >"$_d/cfg/settings.json"; fire "$_d" PostToolUse "$1"
  cmp -s "$_d/cfg/settings.json" "$_d/before"
}
sc_arrived() { # absent, then created with the incident's keys → keys gone
  _d="$(fresh "sc$$a")"; fire "$_d" PostToolUse "$1"
  put "$_d/cfg/settings.json" "$INCIDENT"; fire "$_d" PostToolUse "$1"
  ! routed "$_d/cfg/settings.json"
}
sc_wipe() { # cache/ wiped in the same call as the reroute → still put back
  _d="$(fresh "sc$$w")"; put "$_d/cfg/settings.json" "$CLEAN"; fire "$_d" SessionStart "$1"
  rm -rf "$_d/cfg/cache"; put "$_d/cfg/settings.json" "$INCIDENT"; fire "$_d" PostToolUse "$1"
  ! routed "$_d/cfg/settings.json"
}
mutate() { # <sed expression> <label> <scenario>
  _m="$TMP/mutant.sh"; sed "$1" "$GUARD" >"$_m"
  t_eq "$2: the mutation applies" no "$(yn cmp -s "$_m" "$GUARD")"
  t_eq "$2: $3 on the real guard / on the mutant" "pass/fail" \
    "$("$3" "$GUARD" && echo pass || echo fail)/$("$3" "$_m" && echo pass || echo fail)"
}
# The mutant sits in $TMP, so its sourcing of library-admission.sh is pointed back at bin/.
sed_lib="s#^DIR=.*#DIR=\"$DIR\"#"
# The whole list: the incident sets five route keys, so dropping one leaves the others to catch it.
mutate "$sed_lib; s#^ROUTE_KEYS=.*#ROUTE_KEYS='NO_SUCH_KEY'#" 'M1 route-key list' sc_incident
mutate "$sed_lib; s#&& mv \"\$f.apiroute.\$\$\" \"\$f\" 2>/dev/null; then#\&\& false; then#g" 'M2 the restore' sc_incident
mutate "$sed_lib; s#^\$(\"\$FLOOR_GREP\" -l -E.*##" 'M3 the fast-path grep' sc_incident
# #547: first sight sent down the arrived-under-watch branch deleted an operator's credential.
mutate "$sed_lib; s#^  elif \[ -f \"\$s.absent\" \]; then#  elif :; then#" 'M4 first sight is a baseline' sc_first_sight
mutate "$sed_lib; s#{k: .key, v: .value}#{k: .key}#; s#{k: \"apiKeyHelper\", v: .apiKeyHelper}#{k: \"apiKeyHelper\"}#" 'M5 values are compared' sc_changed
mutate "$sed_lib; s#^  : >\"\$1\" 2>/dev/null#  :#" 'M6 the absent marker' sc_arrived
mutate "$sed_lib; s#^SNAPDIR=.*#SNAPDIR=\"\$CFG/cache/apiroute\"#" 'M7 accepted copies outside cache' sc_wipe
# harbor#811: in_step is the mtime test; each mutant loses one of its properties.
mutate "$sed_lib; s#\"\$2\" ! -newer \"\$1\" ! -newer#\"\$2\" ! -newer#" 'M8 older counts as changed' sc_older
mutate "$sed_lib; s#! in_step \"\$1\" \"\$2\"#:#" 'M9 in step is not copied' sc_instep
mutate "$sed_lib; s#! in_step \"\$1\" \"\$2\"#false#" 'M10 newer is copied' sc_newer
mutate "$sed_lib; s#find -L #find #" 'M11 a symlink is followed' sc_symlink

t_section "the decision log (harbor#957): a repair is one advise record, a clean read none"
mkledger() { # <dir> <script>… → a config dir whose bin/ holds the scripts and library-admission.sh, with a sink; prints the sink
  mkdir -p "$1/bin" "$1/MEMORY/OBSERVABILITY/probehost"; _lt="$1"; shift
  cp "$@" "$T_ROOT/bin/library-admission.sh" "$_lt/bin/"; printf 'probehost\n' > "$_lt/.helm-obs-host"
  : > "$_lt/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"; chmod 0500 "$_lt/MEMORY/OBSERVABILITY/probehost"
  printf '%s' "$_lt/MEMORY/OBSERVABILITY/probehost/guard-decisions.jsonl"
}
LS="$(mkledger "$TMP/ledger" "$GUARD")"; LG="$TMP/ledger/bin/admission-api-route.sh"
D="$(fresh ledgerfx)"; put "$D/cfg/settings.json" "$CLEAN"; fire "$D" PostToolUse "$LG"
t_eq "a clean file writes no record" 0 "$(grep -c . "$LS")"
put "$D/cfg/settings.json" "$INCIDENT"; fire "$D" PostToolUse "$LG"
t_eq "the repair is still made through the ledger copy (control)" block "$(decision .decision)"
t_has "...and recorded under g=apiroute" "$(cat "$LS")" '"g":"apiroute"'
t_has "...as advise, since nothing was refused" "$(cat "$LS")" '"d":"advise"'
t_eq "...with nothing in the catch-all" 0 "$(grep -c '"g":"other"' "$LS")"
t_done
