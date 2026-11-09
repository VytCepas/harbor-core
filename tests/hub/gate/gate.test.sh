#!/usr/bin/env sh
# gate.test.sh (harbor#1278) — bin/hub-gate.sh over a signed hub made from templates/hub: it passes clean, and goes red on a planted
# leak (including one in an untracked or ignored file), a planted secret, a bad or unsigned or replayed policy, a hook that is not the
# file policy approved, and a file with no kind (lint-share skips one, so the gate must not; R29). A missing gitleaks is a finding.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/make-hub.sh"
GATE="$T_ROOT/bin/hub-gate.sh"; H="$T_TMP/hub"
export LEAKS_OWN_USER=fixture-own
gate() { _o="$(sh "$GATE" "$@" 2>&1)" && _rc=0 || _rc=$?; OUT="$_o"; RC=$_rc; }
# gate_with VAR=value <args>: one run with a variable set; a bare VAR=x before a function would stay set in sh
gate_with() { _e="$1"; shift; _o="$(env "$_e" sh "$GATE" "$@" 2>&1)" && _rc=0 || _rc=$?; OUT="$_o"; RC=$_rc; }
# red <label> <expected text>: the last gate run exited 1 and said the text
red() { if [ "$RC" = 1 ]; then t_has "$1" "$OUT" "$2"; else t_fail "$1 (exit $RC: $OUT)"; fi; }

t_section "1 - a clean hub passes, and a bare scaffold does not"
make_hub "$H"; gate "$H"
t_eq "the signed scaffold is clean" "0" "$RC"
t_has "it says how many files it judged" "$OUT" "7 file(s) judged"
rm -rf "$T_TMP/bare"; mkdir "$T_TMP/bare"; ( cd "$T_ROOT/templates/hub" && tar -cf - . ) | ( cd "$T_TMP/bare" && tar -xf - )
gate "$T_TMP/bare"
red "the unsigned scaffold is red" "[signature]"
red "and its starter values are named" "starter"

t_section "2 - a planted leak is red"
make_hub "$H"; printf 'see /Users/%s/work for the file\n' realperson >> "$H/README.md"; gate "$H"
red "a home path in a tracked file" "[leaks]"
t_has "the pattern id is named, never the text" "$OUT" ":home-path"
t_hasnt "and the matched text is not printed" "$OUT" "realperson"
make_hub "$H"; mkdir -p "$H/packs/p"; printf 'x /Users/%s/y\n' realperson > "$H/packs/p/notes.swp"; gate "$H"
red "a leak in a file .gitignore hides" "packs/p/notes.swp"
make_hub "$H"; mkdir "$T_TMP/priv"; printf 'id\tkind\tpattern\tnote\nfixture-client\tword\tfixture-client\ta name from the company layer\n' > "$T_TMP/priv/leaks.tsv"
printf 'the fixture-client account\n' >> "$H/README.md"
gate "$H"; t_eq "a company name is not known without its patterns" "0" "$RC"
gate_with HARBOR_HUB_GATE_PRIVATE="$T_TMP/priv" "$H"
red "a company name from HARBOR_HUB_GATE_PRIVATE" ":fixture-client"

t_section "3 - a planted secret is red, and a missing scanner is a finding"
make_hub "$H"; gate_with HARBOR_HUB_GATE_GITLEAKS="$T_TMP/no-such-gitleaks" "$H"
red "no gitleaks is red, never a pass" "gitleaks is not installed"
if command -v gitleaks >/dev/null 2>&1; then
  make_hub "$H"; mkdir -p "$H/packs/p"
  # the token is assembled here so this file holds no scannable literal (.gitleaks.toml)
  printf 'token=%s%s\n' 'ghp' '_aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bD1fH3jL5' > "$H/packs/p/config.txt"
  gate "$H"; red "a GitHub token in a pack" "[secrets]"
  t_has "and the rule is named" "$OUT" "rule github-pat"
  make_hub "$H"; printf '[allowlist]\npaths=["packs"]\n' > "$H/.gitleaks.toml"; mkdir -p "$H/packs/p"
  printf 'token=%s%s\n' 'ghp' '_aB3dE5gH7jK9mN1pQ3sT5vW7yZ9bD1fH3jL5' > "$H/packs/p/config.txt"
  gate "$H"; red "a hub cannot allow-list its own secret" "[secrets]"
else
  echo "gate-test: SKIPPED the planted secret (no gitleaks on PATH); the missing-scanner case above ran"
fi

t_section "4 - a file with no kind is still judged (R29)"
make_hub "$H"; printf '{"schema":1}\n' > "$H/policy-v2.json"
t_has "lint-share alone says nothing of it" "$(HARBOR_SCOPE_ROOT="$T_TMP/none" SHARE_KINDS="$T_ROOT/standards/naming/kinds.tsv" sh "$T_ROOT/bin/lint-share.sh" --list --tree "$H=hub" 2>&1; echo end)" "end"
t_eq "lint-share lists no judged file for it" "" "$(HARBOR_SCOPE_ROOT="$T_TMP/none" SHARE_KINDS="$T_ROOT/standards/naming/kinds.tsv" sh "$T_ROOT/bin/lint-share.sh" --list --tree "$H=hub" 2>/dev/null | grep 'policy-v2')"
gate "$H"; red "the gate flags the second policy file" "policy-v2.json is not part of a hub"
make_hub "$H"; jq '. + {extra: 1}' "$H/policy.json" > "$H/p" && mv "$H/p" "$H/policy.json"; resign "$H"; gate "$H"
red "a policy with an unknown key" "unknown key: extra"
make_hub "$H"; mkdir -p "$H/skills/x"; printf 'a\n' > "$H/skills/x/SKILL.md"; gate "$H"
red "a file whose kind the hub may not hold (share)" "[share]"

t_section "5 - the signature, and a serial that must rise"
make_hub "$H"; printf ' ' >> "$H/policy.json"; gate "$H"
red "a policy edited after signing" "does not verify"
make_hub "$H"; rm "$H/policy.json.sig"; gate "$H"
red "no signature" "no policy.json.sig"
make_hub "$H"; rm "$H/hub-signers"; gate "$H"
red "no signers file" "no signers file"
make_hub "$H"; ssh-keygen -q -t ed25519 -N '' -f "$T_TMP/other"; printf 'hub namespaces="harbor-hub" %s\n' "$(cut -d' ' -f1,2 "$T_TMP/other.pub")" > "$H/hub-signers"; gate "$H"
red "signed by another key" "does not verify"
make_hub "$H"; cp "$H/policy.json" "$T_TMP/base.json"
gate "$H" --base "$T_TMP/base.json"; [ "$RC" = 0 ] && t_pass || t_fail "the same policy against itself stands ($OUT)"
jq '.silent_days = 7' "$H/policy.json" > "$H/p" && mv "$H/p" "$H/policy.json"; resign "$H"
gate "$H" --base "$T_TMP/base.json"; red "a changed policy at the same serial" "does not rise"
jq '.serial = 2' "$H/policy.json" > "$H/p" && mv "$H/p" "$H/policy.json"; resign "$H"
gate "$H" --base "$T_TMP/base.json"; [ "$RC" = 0 ] && t_pass || t_fail "a changed policy at a higher serial ($OUT)"

t_section "6 - packs: the hook policy approves is the file that is there"
make_hub "$H"; mkdir -p "$H/packs/p/harbor-pack"; printf 'echo hi\n' > "$H/packs/p/harbor-pack/hook.sh"
HS="$(. "$T_ROOT/bin/library-hub.sh"; hub_sha256 < "$H/packs/p/harbor-pack/hook.sh")"
jq --arg h "$HS" '.packs = [{id:"p", commit:"0123456789abcdef0123456789abcdef01234567"}] | .hooks = [{pack:"p", path:"hook.sh", sha256:$h}]' "$H/policy.json" > "$H/p" && mv "$H/p" "$H/policy.json"
jq -n --arg h "$HS" '{schema:1,id:"p",version:"1.0",harbor_version:"1",provides:["hook"],files:[{path:"hook.sh",sha256:$h}]}' > "$H/packs/p/extension.json"
resign "$H"; gate "$H"; [ "$RC" = 0 ] && t_pass || t_fail "an approved hook with its manifest ($OUT)"
printf 'echo changed\n' > "$H/packs/p/harbor-pack/hook.sh"; gate "$H"
red "the hook file changed after approval" "is not the file policy approved"
red "and the manifest hash no longer matches" "differs from the sha256 its manifest lists"
make_hub "$H"; mkdir -p "$H/packs/q"; printf 'a\n' > "$H/packs/q/x"; gate "$H"
red "a pack with no manifest" "has no extension.json"

t_section "7 - usage"
t_exit "no folder" 2 sh "$GATE"
t_exit "a folder that is not there" 2 sh "$GATE" "$T_TMP/absent"
t_exit "--help" 0 sh "$GATE" --help
# the hub is read, never written: the gate left no file behind
make_hub "$H"; before="$(cd "$H" && find . -path ./.git -prune -o -type f -exec cksum {} + | sort)"; gate "$H"
t_eq "the hub is untouched by a run" "$before" "$(cd "$H" && find . -path ./.git -prune -o -type f -exec cksum {} + | sort)"
t_done
