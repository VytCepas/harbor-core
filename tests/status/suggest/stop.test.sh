#!/usr/bin/env sh
# stop.test.sh (harbor#1485) — bin/status-suggest.sh: state files, status --json shapes, origin trail, confinement row and class, install into the config bin.
. "$(dirname "$0")/../../lib/core.sh"; t_init
TOOL="$T_ROOT/bin/status-suggest.sh"
ST="$T_TMP/state"; HARBOR_STATUS_SUGGEST_DIR="$ST"; export HARBOR_STATUS_SUGGEST_DIR
# An installed-shaped tree: the tool in <tree>/bin finds the pack's table at <tree>/context-rules/user/suggest-tool.tsv.
TREE="$T_TMP/tree"; mkdir -p "$TREE/bin" "$TREE/context-rules/user"; cp "$TOOL" "$T_ROOT/bin/library-log.sh" "$TREE/bin/"
TAB="$(printf '\t')"
ss() { sh "$TREE/bin/status-suggest.sh" "$@"; }
js() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
row() { # id kind line -> a 12-column table row
  printf '%s\t%s\t%s\t-\t^x\t-\t%s\t-\tno\t-\t-\ttest\n' "$1" "$2" "${4:-Bash}" "$3"
}
reset() { rm -rf "$ST"; }

t_section "status --json with no state and no table: the empty shape, exit 0"
reset
OUT="$(ss status --json)"; RC=$?
t_eq "exit 0" 0 "$RC"
t_eq "the empty shape, byte for byte" '{"schema":1,"enabled":true,"stopped":[],"last":null,"rows":[],"intro_due":false}' "$OUT"
t_exit "status never creates the state folder" 1 test -e "$ST"

t_section "usage errors exit 2 and write nothing"
for a in "" "bogus" "stop" "stop x" "stop x --origin" "stop x --origin boss" "stop X --origin panel" "stop -x --origin panel" "start x --origin" "off" "off --origin nobody" "on" \
         "shown" "shown a b" "shown a --origin panel" "tick now" "status" "status --yaml" "stop a b --origin panel" "stop x --origin panel --force"; do
  # shellcheck disable=SC2086
  t_exit "'$a' is bad usage" 2 sh -c 'sh "$1" $2 >/dev/null 2>&1' _ "$TREE/bin/status-suggest.sh" "$a"
done
t_exit "...and a 28-character id is refused" 2 sh "$TREE/bin/status-suggest.sh" stop aaaaaaaaaaaaaaaaaaaaaaaaaaaa --origin panel
t_exit "...and no state folder appeared" 1 test -e "$ST"

t_section "stop, start, off, on: the files, the shapes and the origin trail"
reset
t_exit "stop x from the panel" 0 sh "$TREE/bin/status-suggest.sh" stop x --origin panel
t_exit "stop y from the agent" 0 sh "$TREE/bin/status-suggest.sh" stop y --origin agent
t_eq "stopped.tsv holds id, date, origin" "x${TAB}$(date +%Y-%m-%d)${TAB}panel
y${TAB}$(date +%Y-%m-%d)${TAB}agent" "$(cat "$ST/stopped.tsv")"
ss stop x --origin agent
t_eq "a second stop of x keeps the first row (idempotent, origin kept)" 2 "$(wc -l < "$ST/stopped.tsv" | tr -d ' ')"
S="$(ss status --json)"
t_eq "status lists both, with origin" "x:panel y:agent" "$(js "$S" '[.stopped[] | "\(.id):\(.origin)"] | join(" ")')"
t_eq "...and a since date" "$(date +%Y-%m-%d)" "$(js "$S" '.stopped[0].since')"
t_eq "...and a label, the id when the table has no row" x "$(js "$S" '.stopped[0].label')"
ss start x --origin panel
t_eq "start removes x only" "y" "$(cut -f1 "$ST/stopped.tsv")"
t_exit "start of an id never stopped is fine" 0 sh "$TREE/bin/status-suggest.sh" start nope --origin panel
t_exit "off" 0 sh "$TREE/bin/status-suggest.sh" off --origin agent
t_eq "the off file exists and status says disabled" false "$(js "$(ss status --json)" '.enabled')"
ss on --origin panel
t_eq "on removes it" true "$(js "$(ss status --json)" '.enabled')"
t_exit "...the off file is gone" 1 test -e "$ST/off"
ss on --origin panel
t_exit "on when already on is fine" 0 sh "$TREE/bin/status-suggest.sh" on --origin panel
t_has "switch.log names the origin of every write" "$(cat "$ST/switch.log")" "off${TAB}-${TAB}agent"
t_eq "...one line per write: 9 so far" 9 "$(wc -l < "$ST/switch.log" | tr -d ' ')"
t_has "...a stop line carries the id" "$(cat "$ST/switch.log")" "stop${TAB}y${TAB}agent"
# a failed log write never fails the verb
rm -f "$ST/switch.log"; mkdir "$ST/switch.log"
t_exit "a log that cannot be written does not fail the verb" 0 sh "$TREE/bin/status-suggest.sh" stop z --origin agent
rmdir "$ST/switch.log"
t_exit "...and the stop still landed" 0 grep -q '^z' "$ST/stopped.tsv"
t_eq "no temp or lock file is left behind" "" "$(ls -A "$ST" | grep '^\.' || :)"

t_section "stop writes only inside the state folder"
HH="$T_TMP/hh"; mkdir -p "$HH"; ( unset HARBOR_STATUS_SUGGEST_DIR; HOME="$HH"; export HOME; find "$HH" | sort > "$T_TMP/before"
  sh "$TOOL" stop x --origin agent; sh "$TOOL" off --origin agent; sh "$TOOL" tick; sh "$TOOL" shown x; sh "$TOOL" scan-used
  find "$HH" | sort > "$T_TMP/after" )
NEW="$(comm -13 "$T_TMP/before" "$T_TMP/after" | grep -v -e "^$HH/.local/state/harbor/suggest" -e "^$HH/.local/state/harbor$" -e "^$HH/.local/state$" -e "^$HH/.local$" || :)"
t_eq "the default folder is ~/.local/state/harbor/suggest, and nothing else under HOME is new" "" "$NEW"
t_exit "...and it holds stopped.tsv" 0 test -f "$HH/.local/state/harbor/suggest/stopped.tsv"
t_eq "the TMPDIR gained nothing from a verb" "" "$(find "$T_TMP/tmp" -type f | head -3)"

t_section "status --json with a table: rows, stopped flags, last, valid JSON"
reset
{ printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n# a comment\n'
  row weekly skill 'A weekly report skill exists.'
  row quoty tool 'Say "hi" with a back\slash.'
  row intro-a intro 'Suggestions can be stopped here.' -
  row 'Bad Id' skill 'never shown'
  row weekly skill 'duplicate id, ignored'; } > "$TREE/context-rules/user/suggest-tool.tsv"
S="$(ss status --json)"
t_eq "the output is JSON" ok "$(printf '%s' "$S" | jq -e . >/dev/null 2>&1 && echo ok || echo bad)"
t_eq "rows: the header, comment, bad id and duplicate are skipped" "weekly quoty intro-a" "$(js "$S" '[.rows[].id] | join(" ")')"
t_eq "a row carries id, kind, line, stopped and nothing else" '["id","kind","line","stopped"]' "$(js "$S" '.rows[0] | keys_unsorted | tojson')"
t_eq "the line is the table's, with quote and backslash escaped" 'Say "hi" with a back\slash.' "$(js "$S" '.rows[1].line')"
ss stop weekly --origin panel
S="$(ss status --json)"
t_eq "a stopped row reads stopped:true" "true false false" "$(js "$S" '[.rows[].stopped] | map(tostring) | join(" ")')"
t_eq "...and its label in the stopped list is the line" 'A weekly report skill exists.' "$(js "$S" '.stopped[0].label')"
t_eq "last is null before anything was shown" null "$(js "$S" '.last')"
ss shown quoty
S="$(ss status --json)"
t_eq "shown records the id" quoty "$(js "$S" '.last.id')"
t_eq "...the line from the table by id" 'Say "hi" with a back\slash.' "$(js "$S" '.last.line')"
t_eq "...and the date" "$(date +%Y-%m-%d)" "$(js "$S" '.last.at')"
t_eq "shown.tsv holds one row: the last" 1 "$(wc -l < "$ST/shown.tsv" | tr -d ' ')"
ss shown weekly
t_eq "a later shown replaces it" weekly "$(js "$(ss status --json)" '.last.id')"
t_eq "an id the table lacks is recorded with no line, never an argument's text" "" "$(ss shown ghost; js "$(ss status --json)" '.last.line')"
t_eq "...the last id is ghost" ghost "$(js "$(ss status --json)" '.last.id')"

t_section "the state files carry no command text: ids, dates, origins and table lines only"
reset; cp "$TREE/context-rules/user/suggest-tool.tsv" "$T_TMP/table.keep"
{ printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n'
  printf 'cmdrow\tverb\tBash\tMARKWORD\t^MARKRECOGNISER run\tMARKQUIET\tA plain line.\tMARKSWITCH\tno\tMARKINSTALL\t-\tcore\n'; } > "$TREE/context-rules/user/suggest-tool.tsv"
t_exit "a command as an extra argument is bad usage" 2 sh "$TREE/bin/status-suggest.sh" shown cmdrow MARKARG
ss shown cmdrow; ss stop cmdrow --origin agent; ss tick; ss scan-used; ss off --origin agent; ss on --origin panel
_all="$(find "$ST" -type f -exec cat {} +)"
for _m in MARKWORD MARKRECOGNISER MARKQUIET MARKSWITCH MARKINSTALL MARKARG; do t_hasnt "no $_m under the state folder" "$_all" "$_m"; done
t_has "...and the table's line, which it may carry, is there" "$_all" 'A plain line.'
D='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
t_eq "stopped.tsv is id, date, origin" 0 "$(/usr/bin/grep -cvE "^[a-z0-9-]+${TAB}${D}${TAB}(panel|agent)\$" "$ST/stopped.tsv")"
t_eq "shown.tsv is id, date, the table's line" "cmdrow${TAB}$(date +%Y-%m-%d)${TAB}A plain line." "$(cat "$ST/shown.tsv")"
t_eq "sessions.tsv is three numbers" 0 "$(/usr/bin/grep -cvE "^[0-9]+${TAB}[0-9]+${TAB}[01]\$" "$ST/sessions.tsv")"
t_eq "switch.log is date, verb, id, origin" 0 "$(/usr/bin/grep -cvE "^${D}${TAB}(stop|start|off|on|scan-used)${TAB}[a-z0-9-]+${TAB}(panel|agent|-)\$" "$ST/switch.log")"
cp "$T_TMP/table.keep" "$TREE/context-rules/user/suggest-tool.tsv"

t_section "intro_due: 20 sessions on, scan unused, intro row not stopped"
reset
i=0; while [ "$i" -lt 19 ]; do ss tick; i=$((i + 1)); done
t_eq "19 sessions: not due" false "$(js "$(ss status --json)" '.intro_due')"
ss tick
t_eq "sessions.tsv is count, intro_last_count, scan_used" "20${TAB}0${TAB}0" "$(cat "$ST/sessions.tsv")"
t_eq "20 sessions: due" true "$(js "$(ss status --json)" '.intro_due')"
ss shown intro-a
t_eq "shown of the intro row records the count" "20${TAB}20${TAB}0" "$(cat "$ST/sessions.tsv")"
t_eq "...and the intro is not due again at once" false "$(js "$(ss status --json)" '.intro_due')"
i=0; while [ "$i" -lt 20 ]; do ss tick; i=$((i + 1)); done
t_eq "20 sessions after the intro: due again" true "$(js "$(ss status --json)" '.intro_due')"
ss shown weekly
t_eq "shown of an ordinary row leaves intro_last_count alone" "40${TAB}20${TAB}0" "$(cat "$ST/sessions.tsv")"
ss scan-used
t_eq "scan-used ends the intro" false "$(js "$(ss status --json)" '.intro_due')"
t_eq "...count and intro_last_count survive" "40${TAB}20${TAB}1" "$(cat "$ST/sessions.tsv")"
t_has "...and the trail has it" "$(cat "$ST/switch.log")" "scan-used"
rm -f "$ST/sessions.tsv"; i=0; while [ "$i" -lt 20 ]; do ss tick; i=$((i + 1)); done
t_eq "back to due with the scan unused" true "$(js "$(ss status --json)" '.intro_due')"
ss stop intro-a --origin panel
t_eq "a stopped intro row is never due" false "$(js "$(ss status --json)" '.intro_due')"
ss start intro-a --origin panel
printf 'id\tkind\n' > "$TREE/context-rules/user/suggest-tool.tsv"
t_eq "no intro row in the table: nothing to be due" false "$(js "$(ss status --json)" '.intro_due')"
printf 'garbage\there\n' > "$ST/sessions.tsv"; ss tick
t_eq "a corrupt sessions.tsv reads as zero" "1${TAB}0${TAB}0" "$(cat "$ST/sessions.tsv")"
off_on="$(ss off --origin agent; js "$(ss status --json)" '[.enabled, .intro_due] | map(tostring) | join(" ")')"
t_eq "off shows enabled false" "false false" "$off_on"

t_section "no table: status reads no rows (the rule lane creates the table)"
rm -f "$TREE/context-rules/user/suggest-tool.tsv"; reset
t_eq "empty rows, exit 0" '[]' "$(js "$(ss status --json)" '.rows | tojson')"

t_section "parallel writers lose nothing"
reset
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do ss tick & done; wait
t_eq "12 parallel ticks count 12" "12${TAB}0${TAB}0" "$(cat "$ST/sessions.tsv")"
for n in a1 a2 a3 a4 a5 a6 a7 a8; do ss stop "$n" --origin agent & done; wait
t_eq "8 parallel stops leave 8 rows" 8 "$(wc -l < "$ST/stopped.tsv" | tr -d ' ')"
t_eq "...and no leftover temp or lock" "" "$(ls -A "$ST" | grep '^\.' || :)"
mkdir "$ST/.lock"
t_exit "a lock left by a killed writer is broken, not waited on forever" 0 sh "$TREE/bin/status-suggest.sh" tick
t_eq "...and the tick landed" "13${TAB}0${TAB}0" "$(cat "$ST/sessions.tsv")"

t_section "an unwritable state folder is exit 1, not a crash"
reset; mkdir -p "$ST"; chmod 500 "$ST"
t_exit "stop into a read-only folder" 1 sh "$TREE/bin/status-suggest.sh" stop x --origin panel
chmod 700 "$ST"
mkdir "$ST/.lock"; chmod 500 "$ST"
t_exit "a stale lock in a read-only folder is exit 1, not a hang" 1 sh "$TREE/bin/status-suggest.sh" tick
chmod 700 "$ST"; rmdir "$ST/.lock"
t_eq "status still answers on a read-only folder" ok "$(chmod 500 "$ST"; ss status --json | jq -e . >/dev/null 2>&1 && echo ok || echo bad; chmod 700 "$ST")"

# Everything below plants what a confined command can plant, then runs the tool as an unconfined hook would. harbor#1485 finding 1.
OUT="$T_TMP/outside"; TOOLP="$TREE/bin/status-suggest.sh"
plant() { # a fresh folder, and a stand-in outside the wall: a file, a long file and a directory
  chmod -R u+rwx "$ST" 2>/dev/null; reset; rm -rf "$OUT"; mkdir -p "$ST" "$OUT/dir"
  printf 'OUTSIDE-BYTES one\nOUTSIDE-BYTES two\n' > "$OUT/secret"
  i=0; while [ "$i" -lt 500 ]; do echo "OUTSIDE-BYTES line $i"; i=$((i + 1)); done > "$OUT/long"
  OSUM="$(find "$OUT" -type f -exec cksum {} + | sort | cksum)"; OLS="$(find "$OUT" | sort | cksum)"
}
held() { # <label>: nothing outside changed, no outside byte is in the folder
  t_eq "$1: nothing outside changed" "$OSUM $OLS" "$(find "$OUT" -type f -exec cksum {} + | sort | cksum) $(find "$OUT" | sort | cksum)"
  t_hasnt "$1: no outside byte came in" "folder: $(find "$ST" -type f -exec cat {} + 2>/dev/null)" OUTSIDE-BYTES
}
still_link() { t_eq "$1: the plant is left, not followed" yes "$([ -L "$ST/$2" ] && echo yes || echo no)"; }

t_section "a planted state file: refused before every read and write, exit 1"
for _c in 'stopped.tsv|stop abc --origin panel' 'stopped.tsv|start abc --origin panel' 'shown.tsv|shown abc' \
          'sessions.tsv|tick' 'sessions.tsv|scan-used' 'off|off --origin panel'; do
  _f="${_c%%|*}"; _v="${_c#*|}"
  for _kind in file dir dangling; do
    plant
    case "$_kind" in file) ln -s "$OUT/secret" "$ST/$_f" ;; dir) ln -s "$OUT/dir" "$ST/$_f" ;; dangling) ln -s "$OUT/never" "$ST/$_f" ;; esac
    # shellcheck disable=SC2086 # _v is the verb and its arguments
    t_exit "$_f a link ($_kind), $_v" 1 sh "$TOOLP" $_v
    held "$_f $_kind"; still_link "$_f $_kind" "$_f"
    t_exit "...and no new name appeared beside it" 1 test -e "$OUT/never"
  done
done
for _c in 'stopped.tsv|stop abc --origin panel' 'stopped.tsv|start abc --origin panel' 'sessions.tsv|tick'; do
  _f="${_c%%|*}"; _v="${_c#*|}"
  plant; ln "$OUT/secret" "$ST/$_f"
  # shellcheck disable=SC2086
  t_exit "$_f a hard link, $_v" 1 sh "$TOOLP" $_v
  t_eq "...the outside file is unchanged" "$OSUM" "$(find "$OUT" -type f -exec cksum {} + | sort | cksum)"
  plant; mkfifo "$ST/$_f"
  # shellcheck disable=SC2086
  t_exit "$_f a FIFO, $_v: no hang, refused" 1 sh "$TOOLP" $_v
  plant; mkdir "$ST/$_f"
  # shellcheck disable=SC2086
  t_exit "$_f a directory, $_v" 1 sh "$TOOLP" $_v
  t_eq "...and nothing was moved into it" "" "$(ls -A "$ST/$_f")"
done

t_section "refused before the read itself: no reader is ever handed a planted file"
STUB="$T_TMP/stub"; mkdir -p "$STUB"
for _r in awk tail; do printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$T_TMP/reads" "$(command -v "$_r")" > "$STUB/$_r"; chmod +x "$STUB/$_r"; done
for _c in 'stopped.tsv|stop abc --origin panel' 'stopped.tsv|start abc --origin panel' 'sessions.tsv|tick' 'sessions.tsv|scan-used' 'switch.log|stop abc --origin panel'; do
  _f="${_c%%|*}"; _v="${_c#*|}"
  plant; ln -s "$OUT/secret" "$ST/$_f"; : > "$T_TMP/reads"
  # shellcheck disable=SC2086
  PATH="$STUB:$PATH" sh "$TOOLP" $_v 2>/dev/null
  t_eq "$_f a link, $_v: no reader opened it" 0 "$(/usr/bin/grep -cF "$_f" "$T_TMP/reads")"
  plant; printf '0\t0\t0\n' > "$ST/$_f"; : > "$T_TMP/reads"
  # shellcheck disable=SC2086
  PATH="$STUB:$PATH" sh "$TOOLP" $_v 2>/dev/null
  t_eq "...and a plain one is read (the check above can fail)" yes "$([ "$(/usr/bin/grep -cF "$_f" "$T_TMP/reads")" -gt 0 ] && echo yes || echo no)"
done
rm -f "$STUB/awk" "$STUB/tail"

t_section "a planted switch.log: never followed, and the verb still lands"
plant; ln -s "$OUT/secret" "$ST/switch.log"
t_exit "switch.log a link: the stop lands" 0 sh "$TOOLP" stop abc --origin panel
held "switch.log link"; still_link "switch.log link" switch.log
t_eq "...the stop is recorded" abc "$(cut -f1 "$ST/stopped.tsv")"
plant; ln -s "$OUT/long" "$ST/switch.log"
sh "$TOOLP" stop abc --origin panel 2>/dev/null
held "switch.log a link past the trim line"; still_link "past the trim line" switch.log
plant; ln "$OUT/secret" "$ST/switch.log"
t_exit "switch.log a hard link: the stop lands" 0 sh "$TOOLP" stop abc --origin panel
t_eq "...the outside file is unchanged" "$OSUM" "$(find "$OUT" -type f -exec cksum {} + | sort | cksum)"
plant; mkfifo "$ST/switch.log"
t_exit "switch.log a FIFO: no hang" 0 sh "$TOOLP" stop abc --origin panel

t_section "the trail: a real log past 400 lines keeps the last 200, and only its own shape"
plant; i=0; while [ "$i" -lt 405 ]; do printf '2026-11-06\tstop\tid-%s\tpanel\n' "$i"; i=$((i + 1)); done > "$ST/switch.log"
ss stop abc --origin panel
t_eq "trimmed to 200" 200 "$(wc -l < "$ST/switch.log" | tr -d ' ')"
t_eq "...ending with the new line" "stop${TAB}abc${TAB}panel" "$(tail -1 "$ST/switch.log" | cut -f2-)"
plant; printf 'free text from a confined command\n2026-11-06\tstop\tok-row\tpanel\n2026-11-06\tstop\tok-row\tthe operator\n' > "$ST/switch.log"
ss off --origin agent
t_hasnt "a line out of shape does not survive a write" "$(cat "$ST/switch.log")" 'free text'
t_hasnt "...nor a free-text origin" "$(cat "$ST/switch.log")" 'the operator'
t_has "...and a good line does" "$(cat "$ST/switch.log")" 'ok-row'

t_section "temp names: nothing to spray, and creation is exclusive"
plant
t_exit "the old predictable name is not used" 0 sh -c 'ln -s "$1" "$2/.stopped.tsv.$$"; exec sh "$3" stop abc --origin panel' _ "$OUT/secret" "$ST" "$TOOLP"
held "a link at .stopped.tsv.<pid>"
plant
t_exit "...nor for the trail's trim" 0 sh -c 'ln -s "$1" "$2/.switch.log.$$"; i=0; while [ "$i" -lt 405 ]; do printf "2026-11-06\tstop\tx\tpanel\n"; i=$((i + 1)); done > "$2/switch.log"; exec sh "$3" stop abc --origin panel' _ "$OUT/secret" "$ST" "$TOOLP"
held "a link at .switch.log.<pid>"
STUB="$T_TMP/stub"; mkdir -p "$STUB"
RM="$(command -v mktemp)"
printf '#!/bin/sh\n"%s" "$@" | tee -a "%s"\n' "$RM" "$T_TMP/names" > "$STUB/mktemp"; chmod +x "$STUB/mktemp"
plant; : > "$T_TMP/names"
PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel; PATH="$STUB:$PATH" sh "$TOOLP" stop abd --origin panel
t_eq "every write asks for a random name" 4 "$(sort -u "$T_TMP/names" | wc -l | tr -d ' ')"
t_hasnt "...and none is built from the file's name" "$(cat "$T_TMP/names")" stopped
printf '#!/bin/sh\nprintf .planted\n' > "$STUB/mktemp"
plant; ln -s "$OUT/secret" "$ST/.planted"
t_exit "a name that exists is refused, even a link: the create is exclusive" 1 env PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel
held "a link at the temp name"
plant; ln -s "$OUT/never" "$ST/.planted"
t_exit "...a dangling link too" 1 env PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel
t_exit "...and it made nothing outside" 1 test -e "$OUT/never"
rm -f "$STUB/mktemp"

t_section "a race won between the check and the use still reaches nothing outside"
# After cat fills the temp, plant a link to a directory at the final name: the check has already passed, and plain mv would move INTO it.
RC="$(command -v cat)"; RF="$(command -v find)"
printf '#!/bin/sh\n"%s"\n[ -e "%s" ] || { : > "%s"; ln -sf "%s" stopped.tsv; }\n' "$RC" "$T_TMP/once" "$T_TMP/once" "$OUT/dir" > "$STUB/cat"; chmod +x "$STUB/cat"
plant
PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel 2>/dev/null
held "a link to a directory swapped in before the rename"
t_eq "...the rename replaced the link" no "$([ -L "$ST/stopped.tsv" ] && echo yes || echo no)"
rm -f "$STUB/cat"
# The first look at <file> passes, then the link goes in for the read, then a plain file is back for put's look: the read is raced onto a secret.
racefind() { # <name>
  printf '#!/bin/sh\ncase "$*" in *%s*) ;; *) exec "%s" "$@" ;; esac\nn="$("%s" "%s" 2>/dev/null)"; echo x >> "%s"\ncase "$n" in\n  "") "%s" "$@"; ln -sf "%s" %s ;;\n  x) rm -f %s; : > %s; "%s" "$@" ;;\n  *) "%s" "$@" ;;\nesac\n' \
    "$1" "$RF" "$RC" "$T_TMP/seen" "$T_TMP/seen" "$RF" "$OUT/secret" "$1" "$1" "$1" "$RF" "$RF" > "$STUB/find"
  chmod +x "$STUB/find"; rm -f "$T_TMP/seen"
}
plant; printf 'kept\t2026-11-06\tpanel\n' > "$ST/stopped.tsv"; racefind stopped.tsv
PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel 2>/dev/null
t_has "stop raced onto a secret: the verb still lands" "$(cat "$ST/stopped.tsv")" abc
held "stop raced onto a secret"
plant; printf 'kept\t2026-11-06\tpanel\n' > "$ST/stopped.tsv"; racefind stopped.tsv
PATH="$STUB:$PATH" sh "$TOOLP" start abc --origin panel 2>/dev/null
held "start raced onto a secret"
plant; printf '2026-11-06\tstop\tkept\tpanel\n' > "$ST/switch.log"; racefind switch.log
PATH="$STUB:$PATH" sh "$TOOLP" off --origin panel 2>/dev/null
held "the trail raced onto a secret"
rm -f "$STUB/find"

t_section ".lock: a link or a file is refused, never followed or broken"
plant; ln -s "$OUT/dir" "$ST/.lock"
t_exit ".lock a link to a directory" 1 sh "$TOOLP" tick
held ".lock link"; still_link ".lock" .lock
t_exit "...and the tick did not land" 1 test -e "$ST/sessions.tsv"
plant; ln -s "$OUT/never" "$ST/.lock"
t_exit ".lock a dangling link" 1 sh "$TOOLP" stop abc --origin panel
held ".lock dangling"
plant; ln -s "$OUT/secret" "$ST/.lock"
t_exit ".lock a link to a file" 1 sh "$TOOLP" tick
plant; : > "$ST/.lock"
t_exit ".lock a file" 1 sh "$TOOLP" tick
plant; mkfifo "$ST/.lock"
t_exit ".lock a FIFO" 1 sh "$TOOLP" tick
plant; mkdir "$ST/.lock"; touch -t 202001010000 "$ST/.lock"; ln -s "$OUT/dir" "$ST/.lock.break"
t_exit ".lock.break a link" 1 sh "$TOOLP" tick
held ".lock.break link"

t_section "the state folder itself: a link is refused"
for _v in 'stop abc --origin panel' 'start abc --origin panel' 'off --origin agent' 'on --origin agent' 'shown abc' 'tick' 'scan-used'; do
  plant; rmdir "$ST"; printf 'kept\t2026-11-06\tpanel\n' > "$OUT/stopped.tsv"; OSUM="$(find "$OUT" -type f -exec cksum {} + | sort | cksum)"; OLS="$(find "$OUT" | sort | cksum)"
  ln -s "$OUT" "$ST"
  # shellcheck disable=SC2086
  t_exit "the folder a link, $_v" 1 sh "$TOOLP" $_v
  t_eq "...nothing outside changed" "$OSUM $OLS" "$(find "$OUT" -type f -exec cksum {} + | sort | cksum) $(find "$OUT" | sort | cksum)"
done
S="$(ss status --json 2>/dev/null)"; RC_S=$?
t_eq "status on a linked folder: exit 0, the empty shape, nothing read through it" '0 {"schema":1,"enabled":true,"stopped":[],"last":null,"rows":[],"intro_due":false}' "$RC_S $S"
rm -f "$ST"
plant; ln -s "$OUT/secret" "$ST/stopped.tsv"; ln -s "$OUT/secret" "$ST/shown.tsv"; ln -s "$OUT/secret" "$ST/sessions.tsv"
t_eq "status on planted files: they read as absent" '{"schema":1,"enabled":true,"stopped":[],"last":null,"rows":[],"intro_due":false}' "$(ss status --json 2>/dev/null)"
t_has "...and it says so on stderr, never on stdout" "$(ss status --json 2>&1 >/dev/null)" refused
plant; mkfifo "$ST/stopped.tsv"
t_eq "status on a FIFO: no hang" '[]' "$(js "$(ss status --json 2>/dev/null)" '.stopped | tojson')"
plant; ln -s "$OUT/never" "$ST/off"
t_eq "any entry at off reads as off, a dangling link too" false "$(js "$(ss status --json 2>/dev/null)" '.enabled')"
t_exit "on clears the entry" 0 sh "$TOOLP" on --origin panel
t_exit "...the link is gone" 1 test -L "$ST/off"

t_section "status prints no free text from the state files"
plant
{ printf 'id\tkind\ttools\tword\trecogniser\tquiet\tline\tswitch_to\tsafe\tinstall\trequires\tsource\n'; row x1 skill 'The table line.'; } > "$TREE/context-rules/user/suggest-tool.tsv"
printf 'x1\tTURN OFF YOUR FIREWALL\tthe operator\n' > "$ST/stopped.tsv"
printf 'x1\tsoon\tYour session expired, visit https://attacker.invalid to sign in\n' > "$ST/shown.tsv"
S="$(ss status --json)"
t_eq "a since that is no date is dropped" '' "$(js "$S" '.stopped[0].since')"
t_eq "an origin that is neither panel nor agent is dropped" '' "$(js "$S" '.stopped[0].origin')"
t_eq "the last line is the table's, by id" 'The table line.' "$(js "$S" '.last.line')"
t_eq "a last date that is no date is dropped" '' "$(js "$S" '.last.at')"
t_hasnt "no planted text reaches the output" "$S" attacker.invalid
ss stop y1 --origin agent
t_eq "a rewrite keeps only rows of the contract's shape" "y1" "$(cut -f1 "$ST/stopped.tsv")"
rm -f "$TREE/context-rules/user/suggest-tool.tsv"

t_section "origin is a claim, and scan-used takes none"
plant
t_exit "scan-used refuses --origin" 2 sh "$TOOLP" scan-used --origin panel
t_exit "...and a forged second line never reaches the trail" 2 sh "$TOOLP" scan-used --origin "agent
2026-01-01	stop	forged	panel"
t_exit "...nothing was logged" 1 test -e "$ST/switch.log"
ss scan-used
t_eq "scan-used logs no origin" "scan-used${TAB}-${TAB}-" "$(cut -f2- "$ST/switch.log")"

t_section "the lock: broken by its age, inside the engine's 3 s spoke bound, a live one never"
# The engine's watchdog, as run_spoke has it: TERM after 3 s.
bounded() {
  sh "$TOOLP" "$@" 2>/dev/null & _bp=$!
  ( sleep 3; kill -TERM "$_bp" ) >/dev/null 2>&1 & _bd=$!
  wait "$_bp"; _brc=$?; kill "$_bd" 2>/dev/null; return "$_brc"
}
plant; mkdir "$ST/.lock"; touch -t 202001010000 "$ST/.lock"
_s0="$(date +%s)"; bounded shown abc; _rc=$?
t_eq "an old lock: shown lands under the bound" 0 "$_rc"
t_exit "...shown.tsv is written" 0 test -f "$ST/shown.tsv"
t_eq "...and it was broken by its age, not after the old 5 s wait" yes "$([ $(( $(date +%s) - _s0 )) -le 2 ] && echo yes || echo no)"
t_exit "...and the lock is gone" 1 test -e "$ST/.lock"
# Twice at most: this one has a second of margin, and a stalled box is not a defect. A limit past the bound fails both.
for _try in 1 2; do plant; mkdir "$ST/.lock"; bounded shown abc; _rc=$?; [ "$_rc" != 0 ] || break; done
t_eq "a lock killed just now: shown still lands under the bound" 0 "$_rc"
t_exit "...shown.tsv is written" 0 test -f "$ST/shown.tsv"
plant; mkdir -p "$ST/.lock/x/y"; : > "$ST/.lock/z"; touch -t 202001010000 "$ST/.lock"
t_exit "a stale lock that is not empty is cleared, not a jam" 0 sh "$TOOLP" stop abc --origin agent
t_exit "...the stop landed" 0 test -f "$ST/stopped.tsv"
plant; mkdir "$ST/.lock"; touch -t 209901010000 "$ST/.lock"
t_exit "a lock dated in the future is no live writer's" 0 sh "$TOOLP" tick
plant; mkdir "$ST/.lock" "$ST/.lock/theirs"
( n=0; while [ "$n" -lt 13 ] && [ -d "$ST/.lock" ]; do touch "$ST/.lock" 2>/dev/null; n=$((n + 1)); sleep 0.2; done ) & _h=$!
sh "$TOOLP" tick 2>/dev/null & _w=$!
wait "$_h"
t_exit "a live lock younger than the limit is waited on, never stolen" 0 test -d "$ST/.lock/theirs"
t_exit "...and the waiter has not written" 1 test -e "$ST/sessions.tsv"
rm -rf "$ST/.lock"; wait "$_w"; _rc=$?
t_eq "...it lands once the holder lets go" "0 1${TAB}0${TAB}0" "$_rc $(cat "$ST/sessions.tsv")"
plant; mkdir "$ST/.lock" "$ST/.lock/theirs" "$ST/.lock.break"; touch -t 202001010000 "$ST/.lock"
sh "$TOOLP" tick 2>/dev/null & _w=$!
sleep 0.6
t_exit "one breaker at a time: a waiter leaves a lock another is breaking" 0 test -d "$ST/.lock/theirs"
rmdir "$ST/.lock.break"; wait "$_w"; _rc=$?
t_eq "...and goes on once that one is done" 0 "$_rc"
plant; mkdir "$ST/.lock" "$ST/.lock.break"; touch -t 202001010000 "$ST/.lock" "$ST/.lock.break"
t_exit "a breaker killed mid-break leaves no jam" 0 sh "$TOOLP" tick
t_eq "...no lock, guard or mark is left" "" "$(ls -A "$ST" | /usr/bin/grep '^\.' || :)"
RD="$(command -v date)"
printf '#!/bin/sh\ncase "$1" in +%%s) ;; *) sleep 1.5 ;; esac\nexec "%s" "$@"\n' "$RD" > "$STUB/date"; chmod +x "$STUB/date"
plant
PATH="$STUB:$PATH" sh "$TOOLP" stop abc --origin panel 2>/dev/null & _w=$!
# Its mark, not .lock: the mark lands a moment later, and breaking in between would break a lock nobody yet holds.
n=0; until [ -n "$(find "$ST" -maxdepth 1 -name '.held.*')" ] || [ "$n" -gt 200 ]; do sleep 0.02; n=$((n + 1)); done
rm -rf "$ST"/.held.* "$ST/.lock"; mkdir "$ST/.lock" "$ST/.lock/theirs"
wait "$_w"; _rc=$?
t_eq "a holder whose lock was broken fails rather than commits" 1 "$_rc"
t_exit "...it wrote nothing" 1 test -e "$ST/stopped.tsv"
t_exit "...and it left the new holder's lock alone" 0 test -d "$ST/.lock/theirs"
rm -f "$STUB/date"
plant; mkdir "$ST/.lock"
_rc=0; ( n=0; while [ "$n" -lt 40 ]; do touch "$ST/.lock" 2>/dev/null; n=$((n + 1)); sleep 0.2; done ) & _h=$!
sh "$TOOLP" tick 2>/dev/null; _rc=$?
kill "$_h" 2>/dev/null; wait "$_h" 2>/dev/null
t_eq "a lock kept fresh for good is a give-up, exit 1, not a hang" 1 "$_rc"
rmdir "$ST/.lock"

t_section "confinement: the write row, composed, and the class"
PORT_ROOT="$T_TMP/port"; mkdir -p "$PORT_ROOT"; export PORT_ROOT
CMP="$(HARBOR_DEPLOY_CONFINEMENT_OS=Darwin sh "$T_ROOT/bin/deploy-confinement.sh" --compose 2>&1)"
t_has "deploy-confinement --compose carries the suggest state folder" "$(js "$CMP" '.filesystem.allowWrite[]')" '~/.local/state/harbor/suggest'
t_has "...and the paths file says why (origin trail)" "$(cat "$T_ROOT/contracts/confinement-paths.txt")" "write ~/.local/state/harbor/suggest"
CL="$(sed 's/#.*//' "$T_ROOT/contracts/confinement-classes.tsv" | awk -F'\t' '$1 == "suggest-stop" { print $2 "|" $4 }')"
t_eq "suggest-stop is a class with kind allow pointing at the paths file" "allow|contracts/confinement-paths.txt" "$CL"
t_has "the writer's enum names it" "$(grep '^HARBOR_ADMISSION_CLASSES=' "$T_ROOT/bin/library-admission.sh")" " suggest-stop "
cls() { ( . "$T_ROOT/bin/library-admission.sh" >/dev/null 2>&1; floor_obs_class "$1"; printf '%s' "$_xo" ); }
t_eq "a stop run by path is class suggest-stop" suggest-stop "$(cls 'sh /x/.claude/bin/status-suggest.sh stop abc --origin agent')"
t_eq "a bare sh of the tool is suggest-stop" suggest-stop "$(cls 'sh bin/status-suggest.sh off --origin agent')"
t_eq "an ordinary sh script stays script" script "$(cls 'sh bin/status.sh')"

t_section "install: the tool lands in the config bin directory where hooks call it"
IDIR="$T_TMP/inst"; mkdir -p "$IDIR"; printf '{}' > "$IDIR/settings.json"
env -u CLAUDE_CONFIG_DIR sh "$T_ROOT/bin/deploy-runtime-install.sh" --dir "$IDIR" --apply >/dev/null 2>&1
t_exit "status-suggest.sh is in <dir>/bin after a runtime install" 0 test -f "$IDIR/bin/status-suggest.sh"
t_eq "...and the installed copy is the repo's, byte for byte" "$(cksum < "$TOOL")" "$(cksum < "$IDIR/bin/status-suggest.sh" 2>/dev/null)"
reset
sh "$IDIR/bin/status-suggest.sh" shown anything
t_exit "...and a hook-side shown through the installed path writes shown.tsv" 0 grep -q '^anything' "$ST/shown.tsv"
t_done
