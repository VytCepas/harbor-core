#!/usr/bin/env sh
# access-browser-hosts-add.sh: the refusals, a dry run that writes nothing, an --apply that writes the
# file's own shape, and the redirect note. Offline: the hosts file is a copy, curl is a stub.
. "$(dirname "$0")/../../lib/core.sh"; t_init
ADD="$T_ROOT/bin/access-browser-hosts-add.sh"
F="$T_TMP/hosts.txt"; cp "$T_ROOT/contracts/browser-agent-hosts.txt" "$F"
HARBOR_ACCESS_HOSTS_FILE="$F"; export HARBOR_ACCESS_HOSTS_FILE
STUB="$T_TMP/curl"
stub() { printf '#!/bin/sh\nprintf %%s %s\n' "'$1'" > "$STUB"; chmod +x "$STUB"; }  # <what curl -w prints>
HARBOR_TEST_CURL="$STUB"; export HARBOR_TEST_CURL
rc() { "$@" > "$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
sum() { cksum < "$F"; }
WHY='Example — a vendor UI'

t_section "the refusals leave the file untouched"
S0="$(sum)"
t_exit "--help answers" 0 sh "$ADD" --help
t_eq "no --why is refused" "exit 1" "$(rc sh "$ADD" --no-probe app.example.com)"
t_has "  and says why a comment is owed" "$(cat "$T_TMP/err")" "comment naming its vendor"
t_eq "no host is refused" "exit 1" "$(rc sh "$ADD" --why "$WHY")"
t_eq "a scheme is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" https://app.example.com)"
t_eq "a path is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" app.example.com/x)"
t_eq "upper case is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" App.example.com)"
t_eq "a double dot is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" app..example.com)"
t_eq "a backslash is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" 'app.example.com\x')"
t_eq "two labels are refused (admits a whole domain)" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" example.com)"
t_has "  and names the breadth" "$(cat "$T_TMP/err")" "would admit all of *.example.com"
t_eq "a listed host is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" ads.google.com)"
t_eq "a subdomain of a listed host is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" ui.ads.microsoft.com)"
t_has "  and names the admitting line" "$(cat "$T_TMP/err")" "'microsoft.com'"
t_eq "a two-line --why is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why 'a
b' app.example.com)"
t_eq "one bad host refuses the whole call" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" app.example.org example.com)"
t_eq "the file is untouched by every refusal" "$S0" "$(sum)"

t_section "the dry run proposes and writes nothing"
t_eq "a dry run exits 0" "exit 0" "$(rc sh "$ADD" --no-probe --why "$WHY" app.example.com)"
t_has "  the diff adds the host" "$(cat "$T_TMP/out")" "+app.example.com"
t_has "  under its comment" "$(cat "$T_TMP/out")" "+# Example — a vendor UI"
t_has "  and says nothing was written" "$(cat "$T_TMP/err")" "dry run: nothing written"
t_eq "the file is untouched by a dry run" "$S0" "$(sum)"

t_section "--apply writes the file's own shape"
t_eq "--apply exits 0" "exit 0" "$(rc sh "$ADD" --no-probe --why "$WHY" app.example.com other.example.com --apply)"
t_eq "the block is appended: blank, comment, hosts" "$(printf '\n# %s\napp.example.com\nother.example.com' "$WHY")" "$(tail -n 4 "$F")"
t_eq "every host line still sits under a comment (the browser suite's rule)" "" \
  "$(awk '/^#/ { why = 1; next } /^[[:space:]]*$/ { why = 0; next } !why { print }' "$F")"
t_eq "the same host again is refused" "exit 1" "$(rc sh "$ADD" --no-probe --why "$WHY" app.example.com --apply)"
t_eq "the host is now a line of its own in the file" yes \
  "$(grep -qx 'app.example.com' "$F" && echo yes)"

t_section "the redirect measurement lands in the comment"
stub '200 https://login.idp.example.net/v3/signin'
t_eq "an off-host landing is a warning, not a refusal" "exit 0" "$(rc sh "$ADD" --why "$WHY" docs.example.com)"
t_has "  the warning names where it lands" "$(cat "$T_TMP/err")" "lands on login.idp.example.net, which is NOT listed"
t_has "  and the proposed comment records it" "$(cat "$T_TMP/out")" "docs.example.com lands on login.idp.example.net"
stub '200 https://stay.example.com/login'
t_eq "a host that stays on itself passes" "exit 0" "$(rc sh "$ADD" --why "$WHY" stay.example.com)"
t_has "  and is recorded as staying" "$(cat "$T_TMP/out")" "stay.example.com stays on itself"
stub '000 '
t_eq "no answer is a warning" "exit 0" "$(rc sh "$ADD" --why "$WHY" dark.example.com)"
t_has "  said as unmeasured" "$(cat "$T_TMP/err")" "listed unmeasured"
t_done
