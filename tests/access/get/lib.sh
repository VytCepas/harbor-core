# Shared setup for the access get suites (harbor#1617): fixture register and deployed table, fake secrets in the
# Keychain stub, the curl stub, and the run/refused/mutant/red/remut helpers. Sourced after t_init.
. "$(dirname "$0")/../../cli/keychain-stub.sh"
BIN="$T_ROOT/bin"; W="$T_TMP/work"; mkdir -p "$W"
# The fixture private layer sits where the default resolution looks: <home>/port/harbor-private/access.
AD="$HOME/port/harbor-private/access"; mkdir -p "$AD"
for _r in example-tok-read example-bear-refresh example-bear-client; do printf '\n## %s\n\n    secret: %s\n' "$_r" "$_r" >> "$AD/register.md"; done
# The table is read only from the deployed copy in the config dir (second review of #1620), never the private checkout.
CT="$HOME/.claude/access"; mkdir -p "$CT"; cp "$(dirname "$0")/get.tsv" "$CT/get.tsv"
TOK='FAKE-TT-TOKEN-0123456789abcdef'; RT='FAKE-REFRESH-9876543210fedcba'; CSEC='FAKE-CLIENT-SECRET-55aa55aa'; ACC='FAKE-ACCESS-TOKEN-77bb77bb'
printf '%s' "$TOK" | "$BIN/secret" put example-tok-read >/dev/null 2>&1
printf '%s' "$RT" | "$BIN/secret" put example-bear-refresh >/dev/null 2>&1
printf '%s' "$CSEC" | "$BIN/secret" put example-bear-client >/dev/null 2>&1

# The curl stub: logs argv (each argument closed by |), its stdin config, its environment and every argv `ps` shows. curl
# runs under env -i, so the stub's paths are written into it, not read from the environment.
CS="$T_TMP/curlstub"
cat > "$T_BIN/curl" <<STUB
#!/bin/sh
CS='$CS'; ACC='$ACC'
STUB
cat >> "$T_BIN/curl" <<'STUB'
n=$(($(cat "$CS/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$CS/n"
{ for a in "$@"; do printf '%s|' "$a"; done; printf '\n'; } >> "$CS/argv.log"
cat > "$CS/config.$n"
env > "$CS/env.$n"
ps -A -o args= > "$CS/ps.$n" 2>/dev/null
out=''; prev=''
for a in "$@"; do [ "$prev" != -o ] || out="$a"; prev="$a"; done
# With -o the body goes to that file and -w's code to stdout; without it (curl's default) the body, a newline, the code.
if grep -q 'grant_type=refresh_token' "$CS/config.$n"; then
  [ ! -e "$CS/slow" ] || sleep 2
  printf '{"access_token":"%s","token_type":"bearer","expires_in":3600}' "$ACC" > "$CS/resp.$n"; printf 200 > "$CS/rc.$n"
else
  cat "$CS/body" > "$CS/resp.$n"; cat "$CS/code" > "$CS/rc.$n"
fi
if [ -n "$out" ]; then cat "$CS/resp.$n" > "$out"; cat "$CS/rc.$n"; else cat "$CS/resp.$n"; printf '\n'; cat "$CS/rc.$n"; fi
STUB
chmod +x "$T_BIN/curl"
DEFBODY='{"code":0,"message":"OK","data":{"email":"person@example.com","display_name":"Example","access_token":"LEAKED-IN-BODY"}}'
stub() { # [body] [code]
  rm -rf "$CS"; mkdir -p "$CS"
  _sb="${1:-}"; [ -n "$_sb" ] || _sb="$DEFBODY"
  printf '%s' "$_sb" > "$CS/body"; printf '%s' "${2:-200}" > "$CS/code"
}
calls() { cat "$CS/n" 2>/dev/null || echo 0; }
# ps is setuid and the macOS sandbox refuses it: there the ps checks are DEFERRED, never passed. On Linux (CI) they must run.
PS_OK=0; ps -A -o args= >/dev/null 2>&1 && PS_OK=1
pscheck() { if [ "$PS_OK" = 1 ]; then "$@"; else printf '  DEFERRED (ps is refused here; run outside the sandbox): %s\n' "$2" >&2; fi; }

# mktree <dir> <GET_PATH>: <dir>/bin, a copy of the scripts access-get.sh runs, with its two seam lines rewritten.
mktree() {
  rm -rf "$1"; mkdir -p "$1/bin"; ln -s "$T_ROOT/contracts" "$1/contracts"; ln -s "$T_ROOT/standards" "$1/standards"
  for _f in access.sh access-oauth.sh access-redact.sh admission-egress.sh library-log.sh scope-roots.sh secret lint-name.sh; do cp "$BIN/$_f" "$1/bin/"; done
  P="$2" H="$HOME" awk '$0 == "GET_PATH=/usr/bin:/bin" { print "GET_PATH='"'"'" ENVIRON["P"] "'"'"'"; n++; next }
    $0 == "GET_HOME='"''"'" { print "GET_HOME='"'"'" ENVIRON["H"] "'"'"'"; n++; next } { print } END { exit n != 2 }' \
    "$BIN/access-get.sh" > "$1/bin/access-get.sh" || { echo "mktree: the GET_PATH/GET_HOME lines moved"; return 1; }
}
TREE="$W/tree"; mktree "$TREE" "$T_BIN:/usr/bin:/bin"; TB="$TREE/bin"
RC=0
run() { # <bin dir> <args...>: stdout in $W/o, stderr in $W/e, exit in RC
  # A BODY= or CODE= prefix outlives a function call in bash's sh mode, so run consumes both.
  _b="$1"; shift; RC=0; stub "${BODY:-}" "${CODE:-}"; unset BODY CODE
  sh "$_b/access-get.sh" "$@" > "$W/o" 2> "$W/e" || RC=$?
}
# refused <label> <needle> <args...>: exit 2, the refusal names its class, and no request was made
refused() {
  _l="$1"; _n="$2"; shift 2; run "${MB:-$TB}" "$@"
  t_eq "$_l: exit 2" 2 "$RC"; t_has "$_l: the refusal names it" "$(cat "$W/e")" "$_n"; t_eq "$_l: curl never ran" 0 "$(calls)"
}
# mutant <exact line> <replacement> [file]: a copy of the tree with that line of bin/<file> (access-get.sh) replaced;
# prints its bin dir, or NOT-APPLIED when the line is absent.
mutant() {
  _f="${3:-access-get.sh}"; _d="$W/mut.$(printf '%s%s' "$1" "$_f" | cksum | cut -d' ' -f1)"; rm -rf "$_d"; cp -R "$TREE" "$_d"
  M="$1" R="$2" awk '$0 == ENVIRON["M"] { print ENVIRON["R"]; next } { print }' "$TB/$_f" > "$_d/bin/$_f"
  cmp -s "$TB/$_f" "$_d/bin/$_f" && { echo NOT-APPLIED; return; }
  echo "$_d/bin"
}
# red <control> <exact line> <replacement> <needle> <args...>: with the guard removed, the refusal is gone (seen red).
red() {
  _c="$1"; _m="$(mutant "$2" "$3")"; _nd="$4"; shift 4
  t_has "red $_c: the mutant applied" "$_m" "/"
  [ "$_m" != NOT-APPLIED ] || return 0
  run "$_m" "$@"
  if [ "$RC" = 2 ] && grep -qF -- "$_nd" "$W/e"; then t_fail "red $_c: the mutant still refused, so the assertion cannot fail"
  else t_pass; t_red "$_c"; fi
}
# The exact lines the mutants replace, read from the script so a quoting slip cannot make a mutant silently not apply.
CURL_LINE="$(grep -F '| env -i PATH="$GET_PATH" HOME=/ LC_ALL=C curl -q' "$BIN/access-get.sh")"
EXCH_LINE="$(grep -F 'then env -i PATH="$PATH" HOME=/ LC_ALL=C curl -q' "$BIN/access-oauth.sh")"
FLOOR_LINE="$(grep "^FLOOR='" "$BIN/access-get.sh")"
UNSET_LINE="$(grep '^unset ACCESS_DIR ' "$BIN/access-get.sh")"
# remut <bin dir> <file> <exact line> <replacement>: one more replacement inside a mutant, in place; a miss fails the case.
remut() {
  M="$3" R="$4" awk '$0 == ENVIRON["M"] { print ENVIRON["R"]; n++; next } { print } END { exit n == 0 }' "$1/$2" > "$1/$2.new" \
    && mv "$1/$2.new" "$1/$2" || t_fail "remut: the line is not in $1/$2: $3"
}

