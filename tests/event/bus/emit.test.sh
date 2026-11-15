#!/usr/bin/env sh
# bin/event-bus.sh emit (harbor#1043): the record, the line cap, where the bus lives, and that emit
# never fails its caller. Runs under sh, and under dash where the host has it.
. "$(dirname "$0")/../../lib/core.sh"; t_init
EB="$T_ROOT/bin/event-bus.sh"
# The bus clock is pinned to noon UTC today, so a suite never straddles a day file.
set -- $(date -u "+%s %Y-%m-%d"); D="$2"; NOON=$(( $1 / 86400 * 86400 + 43200 - $1 )); export HARBOR_EVENT_BUS_SKEW="$NOON"
SHELLS=sh; if command -v dash >/dev/null 2>&1; then SHELLS="sh dash"; else echo "  skip: dash is not on this host — sh only"; fi

for SH in $SHELLS; do
  BUS="$T_TMP/bus-$SH"; export HARBOR_EVENT_DIR="$BUS"
  t_section "$SH: one line, the contract's keys in order"
  id="$($SH "$EB" emit pr.opened 'VytCepas/harbor#7' --src cli --repo harbor --cause c-1 --data '{"title":"t"}')"; rc=$?
  t_eq "exit 0" 0 "$rc"
  t_eq "prints an id: <ts compact>-<pid>-<4 hex>" yes \
    "$(printf '%s' "$id" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-[0-9]+-[0-9a-f]{4}$' && echo yes || echo no)"
  f="$(find "$BUS" -name '*.jsonl')"
  t_eq "the day file is named for today in UTC" "$BUS/$D.jsonl" "$f"
  line="$(cat "$f")"
  t_eq "the keys, in order" "id,ts,src,kind,subject,repo,cause,data" "$(printf '%s' "$line" | jq -r 'keys_unsorted | join(",")')"
  t_eq "the printed id is the line's id" "$id" "$(printf '%s' "$line" | jq -r .id)"
  t_eq "ts is UTC to the second" yes "$(printf '%s' "$line" | jq -r .ts | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' && echo yes || echo no)"
  t_eq "the fields as given" 'cli pr.opened VytCepas/harbor#7 harbor c-1 t' \
    "$(printf '%s' "$line" | jq -r '[.src, .kind, .subject, .repo, .cause, .data.title] | join(" ")')"

  t_section "$SH: defaults, and a subject kept verbatim through escaping"
  : > "$f"
  subj="$(printf 'a"b\\c\td')"
  $SH "$EB" emit git.commit "$subj" >/dev/null
  t_eq "the line parses" 1 "$(jq -c . "$f" 2>/dev/null | grep -c .)"
  t_eq "the subject round-trips byte for byte" "$subj" "$(jq -r .subject "$f")"
  t_eq "src defaults to cli, cause to empty, data to {}" 'cli||{}' "$(jq -r '[.src, .cause, (.data | tojson)] | join("|")' "$f")"
  t_eq "repo outside a repository is empty" '' "$(cd "$T_TMP" && $SH "$EB" emit a.b s >/dev/null; jq -r 'select(.subject == "s") | .repo' "$f")"
  t_eq "repo inside one is its name, from a worktree too" "$(basename "$(dirname "$(git -C "$T_ROOT" rev-parse --path-format=absolute --git-common-dir)")")" \
    "$(cd "$T_ROOT" && $SH "$EB" emit a.b r >/dev/null; jq -r 'select(.subject == "r") | .repo' "$f")"

  t_section "$SH: the 4096-byte cap — over-cap data becomes a marker, never a torn line"
  : > "$f"
  big="{\"title\":\"$(awk 'BEGIN { while (n++ < 5000) printf "y" }')\"}"
  $SH "$EB" emit check.x.ran big --data "$big" >/dev/null; rc=$?
  t_eq "exit 0" 0 "$rc"
  t_eq "one line, under the cap" yes "$([ "$(wc -c < "$f")" -le 4096 ] && [ "$(grep -c . "$f")" = 1 ] && echo yes || echo no)"
  t_eq "data is replaced by the marker" '{"truncated":true}' "$(jq -c .data "$f")"
  fit="{\"title\":\"$(awk 'BEGIN { while (n++ < 3800) printf "y" }')\"}"
  $SH "$EB" emit check.x.ran fit --data "$fit" >/dev/null
  t_eq "data that fits is kept whole" 3800 "$(jq -r 'select(.subject == "fit") | .data.title | length' "$f")"
  $SH "$EB" emit check.x.ran bad --data 'not json' >/dev/null 2>"$T_TMP/err"
  t_eq "data that is not a one-line object is marked invalid" '{"invalid":true}' "$(jq -c 'select(.subject == "bad") | .data' "$f")"
  t_has "...and says so on stderr" "$(cat "$T_TMP/err")" "WARN: emit: --data is not one JSON object"
  : > "$f"
  $SH "$EB" emit check.x.ran "$(awk 'BEGIN { while (n++ < 5000) printf "s" }')" >"$T_TMP/out" 2>"$T_TMP/err"; rc=$?
  t_eq "a subject over the cap: exit 0" 0 "$rc"
  t_eq "...nothing written" 0 "$(wc -c < "$f" | tr -d ' ')"
  t_eq "...no id printed" '' "$(cat "$T_TMP/out")"
  t_has "...and a FAIL then its fix" "$(cat "$T_TMP/err")" "fix: shorten the subject"

  t_section "$SH: --data is parsed, allowlisted and typed, never passed through"
  : > "$f"
  $SH "$EB" emit a.b inject --data '{}, "kind":"pr.merged", "x":{}' >/dev/null 2>&1
  $SH "$EB" emit a.b unparsed --data '{"title":"}' >/dev/null 2>&1
  $SH "$EB" emit a.b two --data '{"title":"a"} {"title":"b"}' >/dev/null 2>&1
  $SH "$EB" emit a.b keys --data '{"title":"t","link":"http://plain","exit":3,"command":"cmd text","tool":5,"evidence":"e","session_id":"s"}' >/dev/null 2>&1
  t_eq "every line parses" 4 "$(jq -c . "$f" 2>/dev/null | grep -c .)"
  t_eq "a key smuggled through --data cannot override the record's" 'a.b' "$(jq -r 'select(.subject == "inject") | .kind' "$f")"
  t_eq "...the data is marked invalid" '{"invalid":true}' "$(jq -c 'select(.subject == "inject") | .data' "$f")"
  t_eq "unparseable data is marked invalid" '{"invalid":true}' "$(jq -c 'select(.subject == "unparsed") | .data' "$f")"
  t_eq "two objects are not one" '{"invalid":true}' "$(jq -c 'select(.subject == "two") | .data' "$f")"
  t_eq "only allowlisted keys of the right type survive; link is https only" '{"title":"t","exit":3,"evidence":"e","session_id":"s"}' \
    "$(jq -c 'select(.subject == "keys") | .data' "$f")"

  t_section "$SH: bytes the line cannot carry"
  : > "$f"
  $SH "$EB" emit a.b "$(printf 'caf\303\251-\377-x')" >/dev/null 2>&1
  t_eq "invalid UTF-8 is dropped, valid UTF-8 kept: the file is strict UTF-8" ok "$(iconv -f UTF-8 -t UTF-8 < "$f" >/dev/null 2>&1 && echo ok)"
  t_eq "...and the subject keeps its valid characters" "$(printf 'caf\303\251--x')" "$(jq -r .subject "$f")"
  huge="$(awk 'BEGIN { while (n++ < 120000) printf "s" }')"  # under Linux's 128 KB per-argument limit
  $SH "$EB" emit a.b "$huge" >/dev/null 2>"$T_TMP/err"; rc=$?
  t_has "a 120 KB subject is refused before the (quadratic) escaper sees it" "$(cat "$T_TMP/err")" "subject, repo, cause and src exceed"
  t_eq "...exit 0" 0 "$rc"
  printf '{"id":"cut-short","ts":"t' >> "$f"
  $SH "$EB" emit a.b after-fragment >/dev/null 2>&1
  t_eq "a day file ending mid-line gets its newline first: the new line parses alone" after-fragment \
    "$(grep after-fragment "$f" | jq -r .subject 2>/dev/null)"
  t_eq "...and since steps over the fragment" 'café--x after-fragment' "$(sh "$EB" since "$T_TMP/o-$SH" | jq -r .subject | tr '\n' ' ' | sed 's/ $//')"
  { $SH "$EB" emit a.b piped; echo $? > "$T_TMP/rc"; } | true
  t_eq "a closed stdout (SIGPIPE) is still exit 0" 0 "$(cat "$T_TMP/rc")"

  t_section "$SH: emit exits 0 whatever goes wrong, and says so on stderr"
  : > "$T_TMP/afile"
  HARBOR_EVENT_DIR="$T_TMP/afile/events" $SH "$EB" emit a.b c >"$T_TMP/out" 2>"$T_TMP/err"; rc=$?
  t_eq "an unwritable bus dir: exit 0" 0 "$rc"
  t_eq "...no id printed" '' "$(cat "$T_TMP/out")"
  t_has "...the failure is on stderr" "$(cat "$T_TMP/err")" "FAIL: emit: cannot create $T_TMP/afile/events"
  if [ "$(id -u)" != 0 ]; then
    RO="$T_TMP/ro-$SH"; mkdir -p "$RO"; chmod 500 "$RO"
    HARBOR_EVENT_DIR="$RO" $SH "$EB" emit a.b c >"$T_TMP/out" 2>"$T_TMP/err"; rc=$?
    t_eq "a read-only bus dir: exit 0" 0 "$rc"
    t_eq "...no id printed" '' "$(cat "$T_TMP/out")"
    t_has "...the failure is on stderr, with its fix" "$(cat "$T_TMP/err")" "fix: chmod u+w '$RO'"
    chmod 700 "$RO"
  else echo "  skip: running as root, which writes into a read-only dir — that case is unprovable here"; fi
  for args in '' 'only-kind' 'Bad.Kind s' 'a.b s --data' 'a.b s --nope x' 'a.b ""'; do
    eval "set -- $args"
    $SH "$EB" emit "$@" >/dev/null 2>&1; rc=$?
    t_eq "emit $args: exit 0" 0 "$rc"
  done
done

t_section "where the bus lives"
unset HARBOR_EVENT_DIR
sh "$EB" emit a.b home >/dev/null
t_eq "default: ~/.local/state/harbor/events, outside every synced tree" 1 \
  "$(find "$HOME/.local/state/harbor/events" -name '*.jsonl' 2>/dev/null | xargs cat 2>/dev/null | grep -c '"subject":"home"')"
t_eq "the bus dir is private to its owner" drwx------ "$(ls -ld "$HOME/.local/state/harbor/events" | cut -c1-10)"
HARBOR_EVENT_DIR="$T_TMP/elsewhere" sh "$EB" emit a.b there >/dev/null
t_eq "HARBOR_EVENT_DIR is honoured" 1 "$(cat "$T_TMP/elsewhere"/*.jsonl | grep -c '"subject":"there"')"
t_eq "...and the default saw nothing of it" 0 "$(cat "$HOME/.local/state/harbor/events"/*.jsonl | grep -c '"subject":"there"')"

t_section "with no jq, --data is dropped to {}, never passed through unread"
NJ="$T_TMP/nojq"; mkdir -p "$NJ"
for c in sh date awk od tr git mkdir tail wc mktemp cat mv rm sed iconv sleep grep head dirname; do
  p="$(command -v "$c")" && ln -sf "$p" "$NJ/$c"
done
HARBOR_EVENT_DIR="$T_TMP/nojq-bus" PATH="$NJ" sh "$EB" emit a.b nojq --data '{"title":"t","x":"y"}' >/dev/null 2>&1; rc=$?
t_eq "exit 0" 0 "$rc"
t_eq "the data is {}" '{}' "$(jq -c .data "$T_TMP/nojq-bus"/*.jsonl)"

t_section "the harbor verb"
export HARBOR_EVENT_DIR="$T_TMP/verb"
id="$(sh "$T_ROOT/bin/harbor" event emit a.b verb)"; rc=$?
t_eq "harbor event emit exits 0" 0 "$rc"
t_eq "...and wrote the line it printed the id of" "$id" "$(jq -r .id "$T_TMP/verb"/*.jsonl)"
t_done
