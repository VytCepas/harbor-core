#!/usr/bin/env sh
# failure-observe.sh, the PostToolUseFailure sink (FO-1, harbor#465): the recurrence key, the refusals
# that write and create nothing, a sink that follows the writer and not $CLAUDE_CONFIG_DIR, and
# redactions under hostile input. Every fixture is a throwaway config dir under $T_TMP.
. "$(dirname "$0")/../../tests/lib/core.sh"; t_init
SRC="$T_ROOT/bin"; TMP="$T_TMP/fo"; mkdir -p "$TMP"
SALT=0123456789abcdef0123456789abcdef
# The state floor-observe.sh leaves at SessionStart: guard-lib beside the tool, host token, salt,
# and a sealed host dir holding a 0600 sink.
mkfix() { # <name> → prints the dir
  _d="$TMP/$1"; mkdir -p "$_d/bin" "$_d/MEMORY/OBSERVABILITY/h1"
  cp "$SRC/library-admission.sh" "$T_ROOT/hooks/failure-observe/failure-observe.sh" "$_d/bin/"
  printf 'h1\n' > "$_d/.helm-obs-host"
  printf '%s\n' "$SALT" > "$_d/.helm-obs-salt"
  : > "$_d/MEMORY/OBSERVABILITY/h1/tool-failures.jsonl"
  chmod 0600 "$_d/MEMORY/OBSERVABILITY/h1/tool-failures.jsonl"
  chmod 0500 "$_d/MEMORY/OBSERVABILITY/h1"
  printf '%s' "$_d"
}
sink_of() { printf '%s' "$1/MEMORY/OBSERVABILITY/h1/tool-failures.jsonl"; }
nrec()    { awk 'END{print NR+0}' "$(sink_of "$1")" 2>/dev/null || echo 0; }
payload() { # <session> <tool> <input-json> <error> <interrupt>
  jq -cn --arg s "$1" --arg t "$2" --argjson i "$3" --arg e "$4" --argjson x "$5" \
    '{session_id:$s, hook_event_name:"PostToolUseFailure", tool_name:$t,
      tool_input:$i, error:$e, is_interrupt:$x, duration_ms:7}'
}
fire() { printf '%s' "$2" | sh "$1/bin/failure-observe.sh"; }  # <dir> <payload>
last() { tail -1 "$(sink_of "$1")" 2>/dev/null; }
field() { sed -n "$2p" "$(sink_of "$1")" | jq -r ".$3"; }  # <dir> <line> <key>
parses() { printf '%s\n' "$1" | jq -e . >/dev/null 2>&1 && echo yes || echo no; }

t_section "a plain failure is recorded, and the record parses"
F="$(mkfix plain)"
fire "$F" "$(payload s1 Read '{"file_path":"/nowhere/x.md"}' 'File does not exist.' false)"
t_eq "one record" 1 "$(nrec "$F")"
t_eq "the record is valid JSON" yes "$(parses "$(last "$F")")"
t_eq "the tool name" Read "$(last "$F" | jq -r .t)"
t_eq "'File does not exist' is classed" not-found "$(last "$F" | jq -r .e)"
t_eq "the subject path" /nowhere/x.md "$(last "$F" | jq -r .k)"

t_section "an interrupt is not a failure"
F="$(mkfix interrupt)"
fire "$F" "$(payload s1 Bash '{"command":"sleep 900"}' 'Interrupted' true)"
t_eq "records" 0 "$(nrec "$F")"

t_section "the recurrence key: same input, two sessions"
F="$(mkfix recur)"
fire "$F" "$(payload s1 Read '{"file_path":"/a/b.md"}' 'File does not exist.' false)"
fire "$F" "$(payload s2 Read '{"file_path":"/a/b.md"}' 'File does not exist.' false)"
t_eq "the same tool and input give the same key" "$(field "$F" 1 h)" "$(field "$F" 2 h)"
t_eq "the key is a 16-hex digest, not the refusal dash" 16 "$(field "$F" 1 h | tr -cd '0-9a-f' | wc -c | tr -d ' ')"
t_eq "two sessions give two session digests" no "$([ "$(field "$F" 1 s)" = "$(field "$F" 2 s)" ] && echo yes || echo no)"

t_section "and a different input is a different key"
F="$(mkfix distinct)"
fire "$F" "$(payload s1 Read '{"file_path":"/a/b.md"}' 'gone' false)"
fire "$F" "$(payload s1 Read '{"file_path":"/a/c.md"}' 'gone' false)"
t_eq "two inputs share no key" no "$([ "$(field "$F" 1 h)" = "$(field "$F" 2 h)" ] && echo yes || echo no)"
t_eq "one session gives one session digest" "$(field "$F" 1 s)" "$(field "$F" 2 s)"

t_section "a Bash subject records the command name, never its arguments"
F="$(mkfix bashsubj)"
P="$(payload s1 Bash '{"command":"curl -H Authorization:secret https://x/y"}' 'Exit code 7' false)"
t_has "the payload carries the arguments" "$P" "Authorization:secret"
fire "$F" "$P"
t_eq "the subject is the bare command name" curl "$(last "$F" | jq -r .k)"
t_hasnt "no argument reaches the ledger: the header" "$(last "$F")" "Authorization"
t_hasnt "no argument reaches the ledger: the value" "$(last "$F")" "secret"

t_section "\$HOME is redacted out of a recorded path"
F="$(mkfix homered)"
P="$(payload s1 Read "$(jq -cn --arg p "$HOME/port/harbor/x.md" '{file_path:$p}')" 'gone' false)"
t_has "the payload's path is under \$HOME" "$P" "$HOME"
fire "$F" "$P"
t_eq "\$HOME becomes ~" "~/port/harbor/x.md" "$(last "$F" | jq -r .k)"
t_hasnt "no absolute \$HOME path reaches the ledger" "$(last "$F")" "$HOME"

t_section "a hostile tool_name and a hostile path cannot forge a record"
F="$(mkfix hostile)"  # mcp__server__tool takes its middle from a repo-supplied .mcp.json
fire "$F" "$(payload s1 'mcp__evil__run' '{"file_path":"/tmp/a\"b"}' 'boom' false)"
t_eq "a clean mcp server name is kept, the tool part never" mcp__evil "$(last "$F" | jq -r .t)"
t_eq "a subject carrying a quote is refused" - "$(last "$F" | jq -r .k)"
t_eq "the record still parses" yes "$(parses "$(last "$F")")"
F="$(mkfix hostile2)"
fire "$F" "$(payload s1 'Read; rm -rf /' '{"file_path":"/x"}' 'boom' false)"
t_eq "a tool name with shell metacharacters" other "$(last "$F" | jq -r .t)"
F="$(mkfix hostile3)"
fire "$F" "$(payload s1 'mcp__ev"il;x__run' '{"file_path":"/x"}' 'boom' false)"
t_eq "an mcp server name failing the charset check maps to the constant" mcp "$(last "$F" | jq -r .t)"

t_section "the error classes"
_class() { _f="$(mkfix "cls$2")"; fire "$_f" "$(payload s1 Read '{"file_path":"/x"}' "$1" false)"; last "$_f" | jq -r .e; }
t_eq "'Permission denied'" permission "$(_class 'Permission denied' 1)"
t_eq "a timeout" timeout "$(_class 'Command timed out after 2m' 2)"
t_eq "'Exit code 1'" exit-nonzero "$(_class 'Exit code 1' 3)"
t_eq "an empty error" empty "$(_class '' 4)"
t_eq "an unrecognised error" other "$(_class 'nothing familiar here' 5)"
# A floor block is already one record in guard-decisions.jsonl; FC-10 excludes this class.
t_eq "a floor block" blocked "$(_class 'HELM FLOOR [bash:pipe-to-shell]: BLOCKED' 6)"
# browser-agent's operator hand-offs are its rules working; tagged on its own server only.
_mclass() { _f="$(mkfix "mcls$3")"; fire "$_f" "$(payload s1 "$2" '{"args":[]}' "$1" false)"; last "$_f" | jq -r .e; }
t_eq "a harbor_chrome hand-off" handoff "$(_mclass '  FAIL: hand-off: signed out: x' mcp__harbor_chrome__snapshot 1)"
t_eq "...the same text from another server is not" other "$(_mclass '  FAIL: hand-off: signed out: x' mcp__other__snapshot 2)"
t_eq "...nor a harbor_chrome failure without the tag" other "$(_mclass '  FAIL: ref e1 is not in the current snapshot' mcp__harbor_chrome__click 3)"

t_section "every refusal writes nothing and creates nothing"
F="$(mkfix nosink)"  # only floor-observe.sh may create a sink
chmod 0700 "$F/MEMORY/OBSERVABILITY/h1"; rm -f "$(sink_of "$F")"; chmod 0500 "$F/MEMORY/OBSERVABILITY/h1"
fire "$F" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "no sink: none is created" no "$([ -e "$(sink_of "$F")" ] && echo yes || echo no)"
F="$(mkfix writabledir)"
chmod 0700 "$F/MEMORY/OBSERVABILITY/h1"
fire "$F" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "a writable host dir gets no record" 0 "$(nrec "$F")"
chmod 0500 "$F/MEMORY/OBSERVABILITY/h1"
F="$(mkfix symlinksink)"
chmod 0700 "$F/MEMORY/OBSERVABILITY/h1"
rm -f "$(sink_of "$F")"; : > "$F/victim"; ln -s "$F/victim" "$(sink_of "$F")"
chmod 0500 "$F/MEMORY/OBSERVABILITY/h1"
fire "$F" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "nothing is appended through a symlinked sink" 0 "$(wc -c < "$F/victim" | tr -d ' ')"
F="$(mkfix nolib)"
rm -f "$F/bin/library-admission.sh"
fire "$F" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "no library-admission.sh: no record" 0 "$(nrec "$F")"
F="$(mkfix nosalt)"
rm -f "$F/.helm-obs-salt"
fire "$F" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "no salt: no record under a key that groups everything" 0 "$(nrec "$F")"

t_section "the sink follows the writer, not the caller's environment"
TRUE="$(mkfix realtree)"; COPY="$(mkfix copytree)"
_before="$(nrec "$TRUE")"
CLAUDE_CONFIG_DIR="$TRUE" fire "$COPY" "$(payload s1 Read '{"file_path":"/x"}' 'gone' false)"
t_eq "the tree CLAUDE_CONFIG_DIR names gets nothing" "$_before" "$(nrec "$TRUE")"
t_eq "the copy writes into its own tree" 1 "$(nrec "$COPY")"

t_section "an empty or unparseable payload is silent"
F="$(mkfix junk)"
printf '' | sh "$F/bin/failure-observe.sh"
printf 'not json at all' | sh "$F/bin/failure-observe.sh"
t_eq "no record" 0 "$(nrec "$F")"
t_exit "junk exits" 0 sh -c 'printf "not json at all" | sh "$1/bin/failure-observe.sh"' _ "$F"

t_section "mutation: the interrupt check is load-bearing"
MUT="$TMP/mut-interrupt"; mkdir -p "$MUT"
sed '/^\[ "\${F_INT:-0}" = "1" \] && exit 0$/d' "$T_ROOT/hooks/failure-observe/failure-observe.sh" > "$MUT/failure-observe.sh"
t_eq "the mutation applies" no "$(cmp -s "$T_ROOT/hooks/failure-observe/failure-observe.sh" "$MUT/failure-observe.sh" && echo yes || echo no)"
F="$(mkfix mutint)"; cp "$MUT/failure-observe.sh" "$F/bin/failure-observe.sh"
fire "$F" "$(payload s1 Bash '{"command":"sleep 9"}' 'Interrupted' true)"
t_eq "without it an interrupt is recorded" 1 "$(nrec "$F")"

t_section "mutation: the digest subject is tool+input, not the whole payload"
MUT2="$TMP/mut-subject"; mkdir -p "$MUT2"
sed 's|^FLOOR_OBS_SUBJECT="\$F_SUBJ"; export FLOOR_OBS_SUBJECT$|FLOOR_OBS_SUBJECT="$PAYLOAD"; export FLOOR_OBS_SUBJECT|' \
  "$T_ROOT/hooks/failure-observe/failure-observe.sh" > "$MUT2/failure-observe.sh"
t_eq "the mutation applies" no "$(cmp -s "$T_ROOT/hooks/failure-observe/failure-observe.sh" "$MUT2/failure-observe.sh" && echo yes || echo no)"
F="$(mkfix mutsubj)"; cp "$MUT2/failure-observe.sh" "$F/bin/failure-observe.sh"
fire "$F" "$(payload s1 Read '{"file_path":"/a/b.md"}' 'gone' false)"
fire "$F" "$(payload s2 Read '{"file_path":"/a/b.md"}' 'gone' false)"
t_eq "hashing the whole payload splits two sessions" no "$([ "$(field "$F" 1 h)" = "$(field "$F" 2 h)" ] && echo yes || echo no)"
t_done
