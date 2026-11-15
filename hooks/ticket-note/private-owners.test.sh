#!/usr/bin/env sh
# ticket-note.sh counts a GitHub URL as the operator's ticket only under an owner it knows. Core names the
# operator's account; every other owner is github_owners in the private layer's harbor.toml (harbor#1149).
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
TOOL="$T_ROOT/hooks/ticket-note/ticket-note.sh"
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"; CFG="$T/cfg"; PV="$T/pv"; mkdir -p "$PV"
printf '%s\n' '{"m":"see https://github.com/org-one/widget/issues/7"}' > "$T/org.jsonl"
printf '%s\n' '{"m":"see https://github.com/VytCepas/harbor/issues/152"}' > "$T/own.jsonl"
n=0
run() { # <fixture> → stdout of the hook, with a fresh session each time
  n=$((n + 1))
  printf '{"session_id":"s%s","transcript_path":"%s/%s.jsonl","stop_hook_active":false}' "$n" "$T" "$1" > "$T/payload.json"
  CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_PRIVATE="$PV" sh "$TOOL" < "$T/payload.json" 2>/dev/null
}

t_section "no github_owners: the operator's own account only"
t_has "the account named in core is still a ticket" "$(run own)" 'VytCepas/harbor#152'
t_eq "another owner is research, silent" "" "$(run org)"

t_section "github_owners adds owners"
printf 'github_owners = ["org-one", "org-two"]\n' > "$PV/harbor.toml"
t_has "a listed owner is now a ticket" "$(run org)" 'org-one/widget#7'
t_has "the core account still is" "$(run own)" 'VytCepas/harbor#152'

t_section "the env override replaces the whole list"
printf '{"session_id":"s99","transcript_path":"%s/org.jsonl","stop_hook_active":false}' "$T" > "$T/payload.json"
t_eq "TICKET_NOTE_GH_OWNERS without the owner: silent" "" "$(CLAUDE_CONFIG_DIR="$CFG" HARBOR_SCOPE_PRIVATE="$PV" TICKET_NOTE_GH_OWNERS=nobody sh "$TOOL" < "$T/payload.json" 2>/dev/null)"

t_section "a malformed harbor.toml degrades to the core account, never a crash"
printf 'github_owners = oops\n' > "$PV/harbor.toml"
t_eq "the hook exits 0" 0 "$(run org >/dev/null; echo $?)"
t_eq "another owner stays silent" "" "$(run org)"
t_done
