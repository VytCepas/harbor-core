#!/usr/bin/env sh
# bin/lint-secrets.sh and lint.credential-reads: credential reads outside bin/secret only go down (harbor#1205).
# Each case is a throwaway git checkout; the baseline and a planted line are the only things that differ between green and red.
# The "credentials" below are made-up shapes, never real ones.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
LS() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-secrets.sh" "$2" 2>&1; }
rc() { HARBOR_ROOT="$1" sh "$T_ROOT/bin/lint-secrets.sh" --check >/dev/null 2>&1; echo $?; }
FAKE="ghp_$(printf 'b%.0s' $(seq 1 36))"
KCREAD='security find-generic-password -s k -w'
KCADD='security add-generic-password -s k -w v'
mk() { # <name> <baseline> → a checkout with one env read, a declared keychain file, comments, and excluded dirs
  _d="$T_TMP/$1"; mkdir -p "$_d/bin" "$_d/CONTRACTS" "$_d/tests" "$_d/fixtures" "$_d/docs" "$_d/EVALS-DATA"
  printf '#!/bin/sh\n# a comment about ${API_TOKEN} and %s\ncurl -H "X: ${API_TOKEN}" u\n' "$KCREAD" > "$_d/bin/uses-env.sh"
  printf '#!/bin/sh\n# secret-seam: macOS-only, because a test said so\n%s\n' "$KCREAD" > "$_d/bin/declared.sh"
  printf 'x=$(%s)\nT=%s\nP=${DB_PASSWORD}\n' "$KCREAD" "$FAKE" | tee "$_d/tests/t.sh" "$_d/fixtures/f.txt" "$_d/docs/d.md" "$_d/EVALS-DATA/e.txt" > /dev/null
  printf '#!/bin/sh\n%s\n' "$KCADD" | tee "$_d/bin/guard-x.sh" "$_d/bin/secret" > /dev/null
  cp "$T_ROOT/bin/lint-secrets.sh" "$T_ROOT/bin/log-lib.sh" "$_d/bin/"
  cp "$T_ROOT/CONTRACTS/credential-patterns.tsv" "$_d/CONTRACTS/"
  printf '%s\n' "$2" > "$_d/CONTRACTS/lint-secrets-baseline.txt"
  ( cd "$_d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  printf '%s' "$_d"
}

t_section "--count counts code reads, and leaves declared files, comments, the seam, the floor and excluded dirs out"
D="$(mk eq 1)"
t_eq "one hit: the env read in uses-env.sh" "1" "$(LS "$D" --count)"
t_has "--list names file:line and the class" "$(LS "$D" --list)" "bin/uses-env.sh:3	env"
for gone in tests/ fixtures/ docs/ EVALS-DATA/ declared.sh guard-x bin/secret; do t_hasnt "...not $gone" "$(LS "$D" --list)" "$gone"; done

t_section "--check: red above the baseline, green at it, a nudge below it"
D="$(mk at 1)"; t_eq "equal is green" "0" "$(rc "$D")"
D="$(mk over 0)"; OUT="$(LS "$D" --check)"
t_eq "above is red" "1" "$(rc "$D")"
t_has "...and says the count and the baseline" "$OUT" "1 credential read(s) outside bin/secret in the tree, baseline is 0"
t_has "...and the fix" "$OUT" "secret run"
D="$(mk under 5)"; OUT="$(LS "$D" --check)"
t_eq "below is still green" "0" "$(rc "$D")"
t_has "...and tells you to lower the baseline" "$OUT" "lower CONTRACTS/lint-secrets-baseline.txt to 1"
D="$(mk nobase x)"; t_eq "a non-numeric baseline is red" "1" "$(rc "$D")"
mkdir -p "$T_TMP/nogit"
t_exit "a non-checkout inspected nothing and is not a pass" 2 env HARBOR_ROOT="$T_TMP/nogit" sh "$T_ROOT/bin/lint-secrets.sh" --check

t_section "red-proof: each class of bypass, planted in a new file that was never added, is red"
D="$(mk plant1 1)"; printf '#!/bin/sh\nT=%s\n' "$FAKE" > "$D/bin/new.sh"
t_eq "a literal credential value" "1" "$(rc "$D")"; t_has "...as class literal" "$(LS "$D" --list)" "bin/new.sh:2	literal"
D="$(mk plant2 1)"; printf '#!/bin/sh\nx=$(%s)\n' "$KCREAD" > "$D/bin/new.sh"
t_eq "a direct Keychain read" "1" "$(rc "$D")"; t_has "...as class keychain" "$(LS "$D" --list)" "bin/new.sh:2	keychain"
D="$(mk plant3 1)"; printf '#!/bin/sh\nif secret-tool lookup service k account a; then :; fi\n' > "$D/bin/new.sh"
t_eq "a direct libsecret read" "1" "$(rc "$D")"
D="$(mk plant4 1)"; printf '#!/bin/sh\ncurl -H "Authorization: $SERVICE_API_KEY" u\n' > "$D/bin/new.sh"
t_eq "an env API key read" "1" "$(rc "$D")"; t_has "...as class env" "$(LS "$D" --list)" "bin/new.sh:2	env"
D="$(mk plant5 1)"; printf '#!/bin/sh\nx="${VENDOR_SECRET:-}"\n' > "$D/bin/new.sh"
t_eq "an env SECRET read" "1" "$(rc "$D")"
D="$(mk plant6 1)"; printf '[ -n "$MY_TOKEN" ]\n' > "$D/bin/new"
t_eq "an extensionless script" "1" "$(rc "$D")"
D="$(mk plant7 1)"; printf 'T=%s\n' "$FAKE" > "$D/README.md"
t_eq "a literal in prose counts: a value in a doc is still a value" "1" "$(rc "$D")"
D="$(mk plant8 1)"; printf '#!/bin/sh\nAPP_ID=123456\n' > "$D/bin/new.sh"
t_eq "an app id written into code" "1" "$(rc "$D")"; t_has "...as class appid" "$(LS "$D" --list)" "bin/new.sh:2	appid"
D="$(mk plant9 1)"; printf '#!/bin/sh\npay="{\\"iss\\":\\"123456\\"}"\n' > "$D/bin/new.sh"
t_eq "a GitHub App id as a JWT issuer, quotes escaped" "1" "$(rc "$D")"
D="$(mk plant10 1)"; printf '#!/bin/sh\ncurl "$API/app/installations/12345678/access_tokens"\n' > "$D/bin/new.sh"
t_eq "an installation id in a request path" "1" "$(rc "$D")"
D="$(mk plant11 1)"; printf 'c = "123456789012-%s.apps.googleusercontent.com"\n' "$(printf 'a%.0s' $(seq 1 32))" > "$D/bin/new.py"
t_eq "a Google OAuth client id" "1" "$(rc "$D")"

t_section "what is not a bypass stays green"
D="$(mk ok1 1)"; printf '#!/bin/sh\n# secret-seam: reads trust settings, never a credential\nsecurity dump-trust-settings\n' > "$D/bin/dec.sh"
t_eq "a file declared with a secret-seam header" "0" "$(rc "$D")"
D="$(mk ok2 1)"; printf '#!/bin/sh\n# %s is prose here, and so is ${OTHER_TOKEN}\n' "$KCREAD" > "$D/bin/c.sh"
t_eq "a comment" "0" "$(rc "$D")"
D="$(mk ok3 1)"; printf '#!/bin/sh\nsecret run my-ref V -- curl u\nx=${SOME_TOKEN} # secret-seam: the child env\n' > "$D/bin/seam.sh"
t_eq "the seam itself, and a line declared in place" "0" "$(rc "$D")"
D="$(mk ok4 1)"; printf 'T=%s\n' "$FAKE" > "$D/tests/more.sh"
t_eq "a fixture in tests/" "0" "$(rc "$D")"
D="$(mk ok5 1)"; printf '#!/bin/sh\n# the App id is 123456, in a comment\npay="{\\"iss\\":\\"$(cat app-id)\\"}"\njq -r '"'"'.app_id // "?"'"'"'\nVERSION=123456\n' > "$D/bin/app.sh"
printf 'app_id: 15368 is the GitHub Actions app, in prose\n' > "$D/README.md"
t_eq "an app id read from a file, a comment, a doc, and a number under another key" "0" "$(rc "$D")"

t_section "growth the file count missed is red"
D="$(mk grow 1)"; printf 'y=${OTHER_TOKEN}\n' >> "$D/bin/uses-env.sh"
t_eq "a second read in a file already listed" "1" "$(rc "$D")"

t_section "lint.credential-reads runs the same check"
D="$(mk lintok 1)"
t_eq "at the baseline the rule is silent" "0" "$(vcount "$(lint1 lint.credential-reads "$D")")"
D="$(mk lintbad 0)"
t_has "above the baseline the rule reports" "$(lint1 lint.credential-reads "$D")" "VIOLATION [lint.credential-reads]"

t_section "the tree itself"
t_eq "the repo is at or under its own baseline" "0" "$(rc "$T_ROOT")"
t_done
