#!/usr/bin/env sh
# bin/event-dispatch.sh pull (harbor#1044): the catch-up line. One line of a repo's events since the session's
# last turn, nothing (0 bytes) when there are none, never the session's own; as a UserPromptSubmit hook it is
# bounded, exits 0 on every path and prints nothing on any failure.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/event/dispatch/fixture.sh"
for r in repo-a repo-b; do git init -q "$T_TMP/$r"; done
pull() { sh "$ED" pull --session "$1" --repo repo-a 2>"$T_TMP/pull.err"; }
bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }
payload() { printf '{"session_id":"%s","cwd":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$1" "$T_TMP/repo-a"; }

t_section "a session's first turn starts at the end of the bus"
emit git.merge before --repo repo-a >/dev/null
o="$(pull s1)"; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "0 bytes: history is not news" 0 "$(bytes "$o")"

t_section "the next turn: one line, this repo's events only"
emit git.merge 3f2a1c9 --repo repo-a >/dev/null; emit pr.opened 'VytCepas/harbor#12' --repo repo-a >/dev/null
emit git.merge elsewhere --repo repo-b >/dev/null
o="$(pull s1)"
t_eq "one line" 1 "$(printf '%s\n' "$o" | grep -c .)"
t_has "it names the repo and the count" "$o" "events in repo-a since your last turn (2):"
t_has "...and each event" "$o" "git.merge 3f2a1c9, pr.opened VytCepas/harbor#12"
t_hasnt "another repo's event is not in it" "$o" "elsewhere"
t_eq "nothing new: 0 bytes" 0 "$(bytes "$(pull s1)")"

t_section "the session's own events are left out"
emit session.start s1 --repo repo-a >/dev/null
emit tool.background.start s1:tu-1 --repo repo-a --data '{"session_id":"s1","tool":"Monitor"}' >/dev/null
emit agent.spawn a-7 --repo repo-a --data '{"session_id":"s1"}' >/dev/null
emit session.start s2 --repo repo-a >/dev/null
o="$(pull s1)"
t_eq "only the other session's start is news" "events in repo-a since your last turn (1): session.start s2" "$o"

t_section "a busy stretch is still one bounded line"
for i in 1 2 3 4 5 6; do emit git.commit "c$i" --repo repo-a >/dev/null; done
o="$(pull s1)"
t_eq "one line" 1 "$(printf '%s\n' "$o" | grep -c .)"
t_has "four named, the rest counted" "$o" "git.commit c4 (+2 more: harbor event tail)"
t_eq "at most 400 bytes" yes "$([ "$(bytes "$o")" -le 400 ] && echo yes || echo no)"

t_section "the UserPromptSubmit hook"
payload s9 > "$T_TMP/p9"
o="$(sh "$ED" pull --hook < "$T_TMP/p9" 2>&1)"; rc=$?
t_eq "first prompt: exit 0, 0 bytes" "0 0" "$rc $(bytes "$o")"
emit pr.merged 'VytCepas/harbor#13' --repo repo-a >/dev/null
o="$(sh "$ED" pull --hook < "$T_TMP/p9" 2>&1)"; rc=$?
t_eq "next prompt: exit 0 and the one line" "0 events in repo-a since your last turn (1): pr.merged VytCepas/harbor#13" "$rc $o"
o="$(sh "$ED" pull --hook < "$T_TMP/p9" 2>&1)"; rc=$?
t_eq "nothing new: exit 0, 0 bytes added to the prompt" "0 0" "$rc $(bytes "$o")"

t_section "the hook never fails a prompt"
hook_rc() { _s="$(date +%s)"; o="$(sh "$@" 2>&1)"; rc=$?; el=$(( $(date +%s) - _s )); }
printf 'not json at all' > "$T_TMP/garbage"
hook_rc "$ED" pull --hook < "$T_TMP/garbage"; t_eq "a garbage payload: exit 0, nothing printed" "0 0" "$rc $(bytes "$o")"
printf '{"session_id":"../../etc","cwd":"/"}' > "$T_TMP/badid"
hook_rc "$ED" pull --hook < "$T_TMP/badid"; t_eq "a session id that is not an id: exit 0, nothing" "0 0" "$rc $(bytes "$o")"
t_eq "...and no offsets file was made from it" no "$([ -e "$BUSDIR/etc" ] && echo yes || echo no)"
mkdir -p "$T_TMP/hung"; cp "$T_ROOT/bin/event-dispatch.sh" "$T_ROOT/bin/library-log.sh" "$T_TMP/hung/"
printf 'sleep 30\n' > "$T_TMP/hung/event-bus.sh"
emit git.merge hungtest --repo repo-a >/dev/null
HARBOR_EVENT_BUS_TIMEOUT=1 hook_rc "$T_TMP/hung/event-dispatch.sh" pull --hook < "$T_TMP/p9"
t_eq "a hung bus: exit 0, nothing printed" "0 0" "$rc $(bytes "$o")"
t_eq "...within the bound (1 s each for the payload and the read)" yes "$([ "$el" -le 4 ] && echo yes || echo no)"
mkfifo "$T_TMP/never"; ( sleep 8 > "$T_TMP/never" ) & HP=$!
HARBOR_EVENT_BUS_TIMEOUT=1 hook_rc "$ED" pull --hook < "$T_TMP/never"
t_eq "a stdin that never closes: exit 0, nothing printed, within the bound" "0 0 yes" "$rc $(bytes "$o") $([ "$el" -le 4 ] && echo yes || echo no)"
kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
mkdir -p "$T_TMP/nolib"; cp "$T_ROOT/bin/event-dispatch.sh" "$T_ROOT/bin/event-bus.sh" "$T_TMP/nolib/"
hook_rc "$T_TMP/nolib/event-dispatch.sh" pull --hook < "$T_TMP/p9"; t_eq "library-log.sh missing: exit 0, nothing" "0 0" "$rc $(bytes "$o")"
: > "$ST/pull.off"; emit git.merge offtest --repo repo-a >/dev/null
hook_rc "$ED" pull --hook < "$T_TMP/p9"; t_eq "pull.off: exit 0, nothing" "0 0" "$rc $(bytes "$o")"
rm -f "$ST/pull.off"
hook_rc "$ED" pull --hook < "$T_TMP/p9"; t_has "...and removing it brings the line back" "$o" "offtest"


t_section "a session's first offset is set from the day files' sizes, not by reading the bus (review #7)"
payload s-first > "$T_TMP/pf"
HARBOR_EVENT_BUS_TIMEOUT=1 hook_rc "$T_TMP/hung/event-dispatch.sh" pull --hook < "$T_TMP/pf"
t_eq "with a bus that never answers, the first prompt still exits 0 with nothing" "0 0" "$rc $(bytes "$o")"
t_eq "...and its offset stands at the end of today's file" "pull $D $(wc -c < "$BUSDIR/$D.jsonl" | tr -d ' ')" "$(cat "$ST/sessions/s-first" 2>/dev/null)"
emit git.merge after-first --repo repo-a >/dev/null
t_eq "the next turn sees only what came after" "events in repo-a since your last turn (1): git.merge after-first" "$(pull s-first)"

t_section "a git that hangs never holds a prompt"
mkdir -p "$T_TMP/slowgit"; printf '#!/bin/sh\nsleep 30\n' > "$T_TMP/slowgit/git"; chmod +x "$T_TMP/slowgit/git"
PATH="$T_TMP/slowgit:$PATH" HARBOR_EVENT_BUS_TIMEOUT=1 hook_rc "$ED" pull --hook < "$T_TMP/p9"
t_eq "exit 0, nothing printed, within the bound" "0 0 yes" "$rc $(bytes "$o") $([ "$el" -le 4 ] && echo yes || echo no)"

t_section "usage"
t_exit "pull with no session is a usage error" 2 sh "$ED" pull
t_done
