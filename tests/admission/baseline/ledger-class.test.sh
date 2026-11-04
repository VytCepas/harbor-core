#!/usr/bin/env sh
# O-34 (harbor#1441): the escape class `x` of the bash guard's ledger record. Split from ledger.test.sh when that file
# passed the 500-line budget; the sink setup below is the same lines as its OBSERVE-1 section.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"

t_section "O-34 (harbor#1441): the escape class of an unconfined Bash call"
OHOST="$(. "$SRC/library-admission.sh" 2>/dev/null; floor_host_token)"
ODIR="$CFG/MEMORY/OBSERVABILITY/$OHOST"
OSINK="$ODIR/guard-decisions.jsonl"
oopen()  { chmod 0700 "$ODIR" 2>/dev/null || :; }
oclose() { chmod 0500 "$ODIR" 2>/dev/null || :; }
otrunc() { oopen; : > "$OSINK" 2>/dev/null || :; oclose; }
CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/admission-observe.sh" </dev/null >/dev/null 2>&1
t_exit "O-34 the SessionStart writer created the sink" 0 test -f "$OSINK"
# O-34 (harbor#1441): the escape class `x` is a closed enum read from the command's first verb, never a payload byte. It is
# set only on the bash guard's record of an unconfined call; every other record writes `-`.
_oxu() { # <command> -> the class `x` of the bash guard's record for it, run as the unconfined retry
  otrunc; printf '%s' "$(jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c,dangerouslyDisableSandbox:true}}')" \
    | (cd "$T_ROOT" && CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/admission-bash.sh") >/dev/null 2>&1
  jq -r 'select(.g == "bash") | .x' "$OSINK" | tail -1
}
mkdir -p "$TMP/managed"; export HARBOR_MANAGED_SETTINGS="$TMP/managed/managed-settings.json"; : > "$TMP/managed/harbor-confinement"
t_eq "O-34 git is vcs" vcs "$(_oxu 'git status')"
t_eq "O-34 a cd prefix does not hide the verb" vcs "$(_oxu 'cd /tmp && gh pr list')"
t_eq "O-34 an env assignment does not hide the verb" vcs "$(_oxu 'GIT_PAGER=cat git log')"
t_eq "O-34 a path-form verb keeps its basename" vcs "$(_oxu '/usr/bin/git status')"
t_eq "O-34 grep is readonly" readonly "$(_oxu 'grep -rn foo .')"
t_eq "O-34 gcloud is cloud" cloud "$(_oxu 'gcloud projects list')"
t_eq "O-34 docker is container" container "$(_oxu 'docker ps')"
t_eq "O-34 sh is script" script "$(_oxu 'sh bin/status.sh')"
t_eq "O-34 python3 is interp" interp "$(_oxu 'python3 tool.py')"
t_eq "O-34 curl is network" network "$(_oxu 'curl -sS https://example.com')"
t_eq "O-34 mkdir is fsmutate" fsmutate "$(_oxu 'mkdir -p /tmp/zz')"
t_eq "O-34 launchctl is system" system "$(_oxu 'launchctl list')"
t_eq "O-34 a for loop is compound" compound "$(_oxu 'for f in a b; do echo "$f"; done')"
t_eq "O-34 an unknown verb is other" other "$(_oxu 'zzunknown --flag')"
t_eq "O-34 a bus emit is event-bus, whatever runs it" event-bus "$(_oxu 'sh bin/event-bus.sh emit obligation.open x')"
t_eq "O-34 a write to a session title is session-title" session-title "$(_oxu "echo t > $CFG/session-titles/s1.txt")"
otrunc
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git status ZZBYTESZZ"}}' | (cd "$T_ROOT" && CLAUDE_CONFIG_DIR="$CFG" sh "$CFG/bin/admission-bash.sh") >/dev/null 2>&1
t_eq "O-34 a confined call carries no class" - "$(jq -r 'select(.g == "bash") | .x' "$OSINK" | tail -1)"
t_hasnt "O-34 no command byte reaches the ledger" "$(cat "$OSINK")" 'ZZBYTESZZ'
rm -f "$TMP/managed/harbor-confinement"; unset HARBOR_MANAGED_SETTINGS
ff_sealed
t_done
