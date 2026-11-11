#!/usr/bin/env sh
# route.test.sh (harbor#1278, lane E) - a registered project's agent memory on a member: the route resolves, a note written there is found next
# session, a credential-shaped line is refused, nothing lands outside the route. A scratch member home with NO store, as a member's is.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/resolver.sh"
mkinst
HOME="$T_TMP/box/home"; PORT_ROOT="$HOME/port"; CLAUDE_CONFIG_DIR="$HOME/.claude"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"; export HOME PORT_ROOT CLAUDE_CONFIG_DIR
sh "$T_ROOT/bin/scope.sh" install >/dev/null 2>&1
mkdir -p "$PORT_ROOT/mywork/src" "$PORT_ROOT/other"; git -C "$PORT_ROOT/mywork" init -q; git -C "$PORT_ROOT/other" init -q
MM="$INST/bin/member-memory.sh"
out() { env -u CLAUDE_CONFIG_DIR CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" sh "$INST/bin/hub.sh" "$@" 2>&1; }
mm() { sh "$MM" "$@" 2>&1; }
key() { printf '%s' "$(CDPATH= cd -P -- "$1" && pwd -P)" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }
# a token-shaped value, built here so this file carries no literal (lint-secrets)
TOK="ghp_$(printf 'a%.0s' $(seq 1 36))"

t_section "1 - before register: no route, nothing written"
t_eq "no store on a fresh member" no "$([ -e "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME")/memory" ] && echo yes || echo no)"
t_eq "where: unregistered project has none (1)" 1 "$(cd "$PORT_ROOT/mywork" && sh "$MM" where >/dev/null 2>&1; echo $?)"
t_eq "add: refused with no route (1)" 1 "$(cd "$PORT_ROOT/mywork" && echo hi | sh "$MM" add n1 >/dev/null 2>&1; echo $?)"

t_section "2 - register makes the route"
out project register mywork --covers "a member project" >/dev/null
R="$CLAUDE_CONFIG_DIR/projects/$(key "$PORT_ROOT/mywork")/memory"
t_eq "the route is the harness key's memory dir, a link" yes "$([ -L "$R" ] && echo yes || echo no)"
t_eq "...onto the one home store" "$(CDPATH= cd -P -- "$CLAUDE_CONFIG_DIR/projects/$(key "$HOME")/memory" && pwd -P)" "$(CDPATH= cd -P -- "$R" && pwd -P)"
t_eq "...which holds an index" yes "$([ -s "$R/MEMORY.md" ] && echo yes || echo no)"
t_eq "memory-route.sh sees the project as routed" 0 "$(env -u HARBOR_SCOPE_ROOT HARBOR_SCOPE_REPO="$T_ROOT" sh "$T_ROOT/bin/memory-route.sh" --dir "$CLAUDE_CONFIG_DIR" --quiet >/dev/null 2>&1; echo $?)"
t_eq "where from the project root" "$R" "$(cd "$PORT_ROOT/mywork" && sh "$MM" where 2>/dev/null)"
t_eq "where from a subfolder" "$R" "$(cd "$PORT_ROOT/mywork/src" && sh "$MM" where 2>/dev/null)"
t_eq "an unregistered neighbour has none" 1 "$(cd "$PORT_ROOT/other" && sh "$MM" where >/dev/null 2>&1; echo $?)"
t_has "the agent is told where" "$(cd "$PORT_ROOT/mywork" && sh "$MM" note)" "notes live in $R"
t_has "...and that no credential goes in, in any form" "$(cd "$PORT_ROOT/mywork" && sh "$MM" note)" "Never paste a credential in any form"
t_has "the help names the limits" "$(sh "$MM" --help 2>&1)" "NOT CAUGHT"
t_eq "...and told nothing in an unregistered folder" '' "$(cd "$PORT_ROOT/other" && sh "$MM" note)"

t_section "3 - a note written is found next session"
_g="$(cd "$PORT_ROOT/mywork/src" && printf -- '---\nname: build\n---\nthe build needs make first\n' | sh "$MM" add build-order 2>&1)"; _rc=$?
t_eq "add exits 0" 0 "$_rc"
t_eq "the file is in the route" yes "$([ -f "$R/build-order.md" ] && echo yes || echo no)"
t_has "a later session finds it by the route" "$(cat "$(cd "$PORT_ROOT/mywork" && sh "$MM" where)/build-order.md")" "make first"
# register also lays the project standard down (lane C); the memory write itself adds nothing to the repo
_st0="$(git -C "$PORT_ROOT/mywork" status --porcelain)"
printf 'a second note\n' | (cd "$PORT_ROOT/mywork" && sh "$MM" add second-note) > /dev/null 2>&1
t_eq "a memory write leaves the project repo as it was" "$_st0" "$(git -C "$PORT_ROOT/mywork" status --porcelain)"
t_eq "and no memory folder is in the project" '' "$(git -C "$PORT_ROOT/mywork" status --porcelain | grep -i memory)"

t_section "4 - refusals"
_rc=0; (cd "$PORT_ROOT/mywork" && printf 'token %s\n' "$TOK" | sh "$MM" add leaky >/dev/null 2>&1) || _rc=$?
t_eq "a credential-shaped line is refused (1)" 1 "$_rc"
t_eq "...and the file is absent" no "$([ -e "$R/leaky.md" ] && echo yes || echo no)"
t_eq "a traversing slug is refused (2)" 2 "$(cd "$PORT_ROOT/mywork" && echo x | sh "$MM" add ../escape >/dev/null 2>&1; echo $?)"
t_eq "...nothing outside the store" no "$([ -e "$CLAUDE_CONFIG_DIR/projects/escape.md" ] && echo yes || echo no)"
t_eq "a slash slug is refused (2)" 2 "$(cd "$PORT_ROOT/mywork" && echo x | sh "$MM" add a/b >/dev/null 2>&1; echo $?)"
t_eq "an empty note is refused (2)" 2 "$(cd "$PORT_ROOT/mywork" && sh "$MM" add empty </dev/null >/dev/null 2>&1; echo $?)"
ln -s "$T_TMP/outside.md" "$R/linked.md"
t_eq "a slug that is a link is not written through (1)" 1 "$(cd "$PORT_ROOT/mywork" && echo x | sh "$MM" add linked >/dev/null 2>&1; echo $?)"
t_eq "...the link target stays absent" no "$([ -e "$T_TMP/outside.md" ] && echo yes || echo no)"
rm -f "$R/linked.md"
# no pattern file: the gate cannot look, so nothing is written
mkdir -p "$T_TMP/nopat/bin"; for _f in "$T_ROOT"/bin/*; do ln -sf "$_f" "$T_TMP/nopat/bin/${_f##*/}"; done
rm -f "$T_TMP/nopat/bin/member-memory.sh"; cp "$T_ROOT/bin/member-memory.sh" "$T_TMP/nopat/bin/"
_rc=0; (cd "$PORT_ROOT/mywork" && echo fine | sh "$T_TMP/nopat/bin/member-memory.sh" add nopat >/dev/null 2>&1) || _rc=$?
t_eq "with no pattern file beside the tool, a clean note is refused (1)" 1 "$_rc"

t_section "4b - one note per slug, one per body, an index that is only appended to"
t_eq "the first add listed the note once" 1 "$(grep -c '](build-order.md)' "$R/MEMORY.md")"
t_eq "...and kept the index header" yes "$(head -n 1 "$R/MEMORY.md" | grep -q '^# Memory' && echo yes || echo no)"
_rc=0; _o="$(cd "$PORT_ROOT/mywork" && echo 'a different body' | sh "$MM" add build-order 2>&1)" || _rc=$?
t_eq "the same slug is refused (1)" 1 "$_rc"
t_has "...saying how to replace" "$_o" "--replace"
t_has "...and the note is unchanged" "$(cat "$R/build-order.md")" "make first"
_rc=0; (cd "$PORT_ROOT/mywork" && printf 'newer body\n' | sh "$MM" add build-order --replace >/dev/null 2>&1) || _rc=$?
t_eq "--replace replaces (0)" 0 "$_rc"
t_has "...the body changed" "$(cat "$R/build-order.md")" "newer body"
t_eq "...and the index still lists it once" 1 "$(grep -c '](build-order.md)' "$R/MEMORY.md")"
_rc=0; _o="$(cd "$PORT_ROOT/mywork" && printf 'newer body\n' | sh "$MM" add copycat 2>&1)" || _rc=$?
t_eq "an identical body under another slug is refused (1)" 1 "$_rc"
t_has "...naming the existing note" "$_o" "build-order.md"
t_eq "...and no second file" no "$([ -e "$R/copycat.md" ] && echo yes || echo no)"
SUM="$(cksum < "$R/MEMORY.md")"
for _s in MEMORY memory Memory; do
  t_eq "add $_s is refused (1)" 1 "$(cd "$PORT_ROOT/mywork" && echo 'x body' | sh "$MM" add $_s >/dev/null 2>&1; echo $?)"
done
t_eq "the index is byte-identical after them" "$SUM" "$(cksum < "$R/MEMORY.md")"
(cd "$PORT_ROOT/mywork" && printf -- '---\nname: described\ndescription: why the cache is cold\n---\nbody one\n' | sh "$MM" add described >/dev/null 2>&1)
t_has "the index line carries the description" "$(cat "$R/MEMORY.md")" "[described](described.md) - why the cache is cold"
t_eq "...and the earlier lines are still there" yes "$(grep -q '](build-order.md)' "$R/MEMORY.md" && echo yes || echo no)"

t_section "4c - a body that names a path, a link out, or an assignment is refused"
refused() { # <label> <body>: exit 1 and no file
  _rc=0; (cd "$PORT_ROOT/mywork" && printf '%s\n' "$2" | sh "$MM" add probe >/dev/null 2>&1) || _rc=$?
  t_eq "refused: $1 (1)" 1 "$_rc"; t_eq "...no file: $1" no "$([ -e "$R/probe.md" ] && echo yes || echo no)"; rm -f "$R/probe.md"
}
accepted() { # <label> <body>: exit 0; the probe note and its index line are removed again
  _rc=0; (cd "$PORT_ROOT/mywork" && printf '%s\n' "$2" | sh "$MM" add probe >/dev/null 2>&1) || _rc=$?
  t_eq "accepted: $1 (0)" 0 "$_rc"; rm -f "$R/probe.md"; grep -v '](probe.md)' "$R/MEMORY.md" > "$R/MEMORY.new" && mv "$R/MEMORY.new" "$R/MEMORY.md"
}
refused "absolute path" "see /etc/passwd for the users"
refused "home tilde path" "the key is at ~/.ssh/id_rsa"
refused "HOME path" 'copy from $HOME/work/x'
refused "a home directory" "it lives in /Users/zed/work"
refused "parent link" "see [x](../../../../etc/passwd)"
refused "file url" "open file:///etc/hosts"
refused "file link" "see [x](file:///etc/hosts)"
refused "rooted link" "see [x](/abs/where)"
refused "password assignment" "password: hunter2hunter2"
# the value is split so the source carries no secret-shaped literal (gitleaks); the gate sees it whole
refused "token assignment" "TOKEN=abcd""1234efgh"
refused "secret assignment" "the secret = longvalue99"
refused "a token value" "token: ghx7Kq2mZp9"
refused "an env-style password" 'DB_PASSWORD=Sup3r$ecret'
refused "a quoted api key" 'api_key = "a1b2c3d4e5"'
refused "a javascript link" "see [x](javascript:alert1)"
refused "an angle-bracket parent link" "see [z](<../up.md>)"
refused "a Windows backslash path" 'the file is C:\Users\me\x'
refused "a Windows drive D" 'copy D:\data\notes'
refused "a Windows forward-slash path" "open C:/Users/me/x"
refused "an Authorization Bearer value" "Authorization: Bearer ghx7Kq2mZp9abc"
refused "a Basic value" "Authorization: Basic dXNlcjpwYXNzd29yZA=="
refused "a pwd value" "pwd: Zx9!kLm2pq"
refused "a pw value" "pw=Zx9kLm2pq1"
refused "a passphrase value" "passphrase = Zx9kLm2pq1"
refused "a client_secret value" "client_secret: Zx9kLm2pq1"
refused "a bearer key value" "bearer: Zx9kLm2pq1"
accepted "an angle-bracket link to a note" "see [z](<other.md>)"
accepted "Bearer prose" "Authorization: Bearer scheme is used here"
accepted "basic prose" "basic usage notes for the build"
accepted "a drive mentioned in prose" "the C: drive is full"
accepted "token: prose" "token: rotation is quarterly"
accepted "a field named token" "the token: field is blank"
accepted "a mailto link" "[mail](mailto:a@b.co)"
accepted "Password: prose" "Password: see the runbook"
accepted "a hyphenated word" "token: short-lived-credentials"
accepted "plain prose with and/or" "use make and/or ninja"
accepted "an https link" "see [docs](https://example.test/a/b)"
accepted "a link to another note" "see [build](build-order.md)"
accepted "a word about passwords" "rotate the password monthly"

t_section "4e - the index line reads cleanly, and --replace refreshes it in place"
(cd "$PORT_ROOT/mywork" && printf 'See [the runbook](runbook.md) and [[other-note]] for the # steps\n' | sh "$MM" add linky >/dev/null 2>&1)
t_has "a link is its label, with no target" "$(cat "$R/MEMORY.md")" "[linky](linky.md) - See the runbook and other-note for the # steps"
t_eq "...no target leaked into the index" 0 "$(grep -c 'runbook.md' "$R/MEMORY.md")"
(cd "$PORT_ROOT/mywork" && printf -- '---\nname: linky\n---\n## Changed heading for [x](y.md)\n' | sh "$MM" add linky --replace >/dev/null 2>&1)
t_eq "--replace leaves one line for the note" 1 "$(grep -c '](linky.md)' "$R/MEMORY.md")"
t_has "...refreshed in place" "$(cat "$R/MEMORY.md")" "[linky](linky.md) - Changed heading for x"
t_eq "...and the other lines are untouched" 1 "$(grep -c '](build-order.md)' "$R/MEMORY.md")"

t_section "4d - everything it says carries its check id"
_o="$(cd "$PORT_ROOT/mywork" && echo 'password: hunter2hunter2' | sh "$MM" add probe 2>&1)"
t_eq "every FAIL and fix line is tagged" 0 "$(printf '%s\n' "$_o" | grep -E '^  (FAIL|fix|ok|note)' | grep -vc 'check:memory.member-notes')"
t_has "the summary line carries it too" "$_o" "member-memory [check:memory.member-notes]:"
t_eq "the id is a row of controls.tsv" yes "$(grep -q 'memory.member-notes' "$T_ROOT/standards/naming/controls.tsv" && echo yes || echo no)"

t_section "5 - check finds a planted secret"
t_eq "check green on clean notes" 0 "$(cd "$PORT_ROOT/mywork" && sh "$MM" check >/dev/null 2>&1; echo $?)"
printf 'oops %s\n' "$TOK" > "$R/planted.md"
t_eq "check red on a planted one (1)" 1 "$(cd "$PORT_ROOT/mywork" && sh "$MM" check >/dev/null 2>&1; echo $?)"
printf 'see /etc/passwd\n' > "$R/planted.md"
t_eq "check red on a planted path (1)" 1 "$(cd "$PORT_ROOT/mywork" && sh "$MM" check >/dev/null 2>&1; echo $?)"
printf 'password: hunter2hunter2\n' > "$R/planted.md"
t_eq "check red on a planted assignment (1)" 1 "$(cd "$PORT_ROOT/mywork" && sh "$MM" check >/dev/null 2>&1; echo $?)"
t_has "check output is tagged" "$(cd "$PORT_ROOT/mywork" && sh "$MM" check 2>&1)" "[check:memory.member-notes]"
rm -f "$R/planted.md"
t_eq "check green again once removed" 0 "$(cd "$PORT_ROOT/mywork" && sh "$MM" check >/dev/null 2>&1; echo $?)"
t_done
