#!/usr/bin/env sh
# eval-git-verbs-probe.sh (harbor#1291): the probe that decides "runs without a prompt" for every row of contracts/verbs/git.md
# from the permission rules and the Bash hooks, offline. Green on the real register with the rules this tree derives; then
# every disagreement kind driven red on a small register or a mutated rule set.
set -u
. "$(dirname "$0")/../../lib/core.sh"
t_init

P="$T_ROOT/bin/eval-git-verbs-probe.sh"
REG="$T_ROOT/contracts/verbs/git.md"

# _probe <args> — runs the probe; sets OUT and RC.
_probe() { OUT="$(sh "$P" "$@" 2>&1)"; RC=$?; }

mkdir -p "$T_TMP/d"; printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$T_TMP/d/settings.json"
CLAUDE_CONFIG_DIR="$T_TMP/d" sh "$T_ROOT/bin/admission-deny.sh" --apply --dir "$T_TMP/d" > "$T_TMP/d/log" 2>&1
t_eq "fixture: floor-deny derived the rules" 0 "$?"
S="$T_TMP/d/settings.json"

# A register of one row per kind: a derived allow, a built-in read, a classifier write, a floor ask, a floor block under a
# deny rule, and an ask rule.
cat > "$T_TMP/small.md" <<'REG'
| spelling | class | perm | floor | calls | refused | instead |
|---|---|---|---|---|---|---|
| `git ls-tree *` | read | allow | ro | 0 | 0 | |
| `git status *` | read | builtin | ro | 0 | 0 | |
| `git pull *` | write | classifier | - | 0 | 0 | |
| `git reset --hard *` | gated | classifier | ask:git-reset-hard | 0 | 0 | |
| `git push -f*main*` | gated | deny | block:force-push-protected | 0 | 0 | |
| `git fetch --u*` | gated | ask | - | 0 | 0 | |
REG

t_section "green: the real register against the rules this tree derives, every row as listed"
_probe
t_eq "exit 0" 0 "$RC"
t_has "no disagreement" "$OUT" ", 0 failed"
t_hasnt "no FAIL line" "$OUT" "  FAIL:"
t_has "an allow row is free" "$OUT" "git ls-tree *"
t_has "and shows the command it ran" "$OUT" "free          git ls-tree README.md"
t_has "a classifier row is a prompt" "$OUT" "prompt        git pull README.md"
t_has "a built-in read is named as such" "$OUT" "free-builtin  git status README.md"

t_section "green: the small register, one row per kind"
_probe --register "$T_TMP/small.md" --settings "$S"
t_eq "exit 0" 0 "$RC"
t_has "six rows as listed" "$OUT" "eval-git-verbs-probe: 6 ok, 0 failed"

t_section "red: the allow rule is gone"
jq '.permissions.allow -= ["Bash(git ls-tree *)"]' "$S" > "$T_TMP/no-allow.json"
_probe --register "$T_TMP/small.md" --settings "$T_TMP/no-allow.json"
t_eq "exit 1" 1 "$RC"
t_has "named" "$OUT" "FAIL: git ls-tree *"
t_has "with the reason" "$OUT" "rules say none, register says allow"

t_section "red: the deny rule is gone, the ask rule is gone, an allow rule appears over a classifier row"
jq '.permissions.deny -= ["Bash(git push -f*main*)"]' "$S" > "$T_TMP/no-deny.json"
_probe --register "$T_TMP/small.md" --settings "$T_TMP/no-deny.json"
t_has "deny gone" "$OUT" "FAIL: git push -f*main*"
jq '.permissions.ask -= ["Bash(git fetch --u*)"]' "$S" > "$T_TMP/no-ask.json"
_probe --register "$T_TMP/small.md" --settings "$T_TMP/no-ask.json"
t_has "ask gone" "$OUT" "FAIL: git fetch --u*"
jq '.permissions.allow += ["Bash(git pull *)"]' "$S" > "$T_TMP/extra.json"
_probe --register "$T_TMP/small.md" --settings "$T_TMP/extra.json"
t_has "a surplus allow rule" "$OUT" "rules say allow, register says classifier"

t_section "red: the register names a floor rule that does not fire, or says nothing where a hook asks"
sed 's/block:force-push-protected/block:force-pusher/' "$T_TMP/small.md" > "$T_TMP/bad-block.md"
_probe --register "$T_TMP/bad-block.md" --settings "$S"
t_has "a wrong rule id" "$OUT" "hooks say block:force-push-protected, register says block:force-pusher"
sed 's/ask:git-reset-hard/-/' "$T_TMP/small.md" > "$T_TMP/no-floor.md"
_probe --register "$T_TMP/no-floor.md" --settings "$S"
t_has "an ask the register does not know" "$OUT" "hooks say ask, register says -"
sed 's/| allow | ro |/| allow | - |/;s/block:force-push-protected/-/' "$T_TMP/small.md" > "$T_TMP/no-block.md"
_probe --register "$T_TMP/no-block.md" --settings "$S"
t_has "a refusal the register does not know" "$OUT" "hooks say block:force-push-protected, register says -"

t_section "red: a spelling the probe cannot turn into a command is a failure, not a skip"
printf '| `git frob*x` | read | allow | - | 0 | 0 | |\n' > "$T_TMP/odd.md"
_probe --register "$T_TMP/odd.md" --settings "$S"
t_eq "exit 1" 1 "$RC"
t_has "named" "$OUT" "no concrete command for this spelling"

t_section "no verdict is exit 2"
_probe --settings "$T_TMP/none.json"; t_eq "missing settings file" 2 "$RC"
echo '{"permissions":{}}' > "$T_TMP/empty.json"; _probe --settings "$T_TMP/empty.json"
t_eq "no Bash rules at all" 2 "$RC"
_probe --register "$T_TMP/absent.md"; t_eq "missing register" 2 "$RC"
_probe --bogus; t_eq "unknown argument" 2 "$RC"

t_done
