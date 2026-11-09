#!/usr/bin/env sh
# guard.test.sh (harbor#1278) — the dispatcher's integrity rule: an agent's tool call never starts or reaches a support session, in shadow too, and no approval helps.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/member-root.sh"
denied() { m_reset; m_enforce; m_call "$(m_bash "$2")"; t_eq "$1" deny "$M_DEC"; }
passes() { m_reset; m_enforce; m_call "$(m_bash "$2")"; t_eq "$1" silent "$M_DEC"; }

t_section "1 - the commands, however they are spelled"
denied "upterm host" 'upterm host --server wss://uptermd.upterm.dev'
denied "upterm join" 'upterm join ssh://abc@uptermd.upterm.dev'
denied "upterm attach, the local way in" 'upterm attach hs'
denied "by its managed path" '"/etc/claude-code/harbor/bin/upterm" session info hs'
denied "the relay's daemon" 'uptermd --ssh-addr 127.0.0.1:2222'
denied "member-support, by sh" 'sh /etc/claude-code/harbor/bin/member-support.sh'
denied "member-support, bare" 'member-support.sh'
denied "harbor hub support" 'harbor hub support connect s-0123456789abcdef'
denied "hub-support.sh" 'sh bin/hub-support.sh list'
denied "hub.sh support" 'sh bin/hub.sh support accept s-0123456789abcdef'
denied "quoted in the word" "up'te'rm host"
denied "a backslash in the word" 'up\term host'
denied "upper case" 'UPTERM host'
denied "behind env" 'env A=1 upterm host'
denied "behind sh -c" "sh -c 'upterm host'"
denied "after a semicolon" 'true; upterm host'
denied "down a pipe" 'printf y | upterm host'
denied "in a substitution" 'echo $(upterm host)'
denied "through xargs" 'echo host | xargs upterm'
denied "through find" 'find . -name x -exec upterm host \;'
denied "under script, for a terminal" 'script -qc "sh member-support.sh" /dev/null'
denied "under tmux" 'tmux new -d "upterm host"'
denied "under script, with the word broken up" "script -qc \"up'te'rm host\" /dev/null"
denied "a reader can't carry it past the pipe" 'cat notes | upterm host'

t_section "2 - any tool with a command, not only Bash"
m_reset; m_enforce
m_call "$(m_tool Monitor '{"command":"upterm host"}')"
t_eq "Monitor" deny "$M_DEC"

t_section "3 - integrity: in shadow too, and no route"
m_reset; m_policy '.'
m_call "$(m_bash 'upterm host')"
t_eq "shadow enforces it" deny "$M_DEC"
t_has "and says no approval helps" "$M_WHY" 'no approval can change it'
t_eq "it never asks an admin" '' "$(m_approvals)"
t_has "the row is the integrity set" "$(sh "$MB/hub-tier.sh" lookup admission.member-support)" 'integrity'
m_reset; m_policy '.tiers["admission.member-support"] = "low"'
m_call "$(m_bash 'upterm host')"
t_eq "a hub can't re-tier it" deny "$M_DEC"
t_has "the refusal is recorded" "$(m_events)" 'admission.member-support'

t_section "4 - a broken guard is a refusal, never a pass"
m_reset; m_enforce
mv "$MB/member-support-guard.sh" "$T_TMP/guard.away"
m_call "$(m_bash 'ls')"
t_eq "with the guard gone, the call stops" deny "$M_DEC"
mv "$T_TMP/guard.away" "$MB/member-support-guard.sh"

t_section "5 - reading about support is free (a false positive is a defect)"
passes "reading the how-to" 'cat docs/how-to/member-support.md'
passes "searching for the word" "grep -rn upterm docs"
passes "a commit message" 'git commit -m "explain upterm in the docs"'
passes "printing the word" "echo 'upterm is a terminal sharing tool'"
passes "a longer word" 'ls myupterm-notes'
passes "the how-to, in another tool's hands" 'wc -l docs/how-to/member-support.md'
passes "CONTROL: an ordinary command" 'ls -la'
m_reset; m_enforce
m_call "$(m_tool Read '{"file_path":"/x/member-support.sh"}')"
t_eq "the Read tool has no command to judge" silent "$M_DEC"
t_done
