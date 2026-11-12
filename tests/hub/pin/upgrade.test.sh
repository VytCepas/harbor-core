#!/usr/bin/env sh
# hub-pin-upgrade.sh (harbor#1278): scratch git repos only, no network, no real hub. Each refusal leaves the hub checkout as it was found.
. "$(dirname "$0")/../../lib/core.sh"; t_init
U="$T_ROOT/bin/hub-pin-upgrade.sh"
GIT="git -c user.name=t -c user.email=t@t"

# A harbor-core stand-in with a bare origin: the real format checker, a bin/harbor naming its contract.
CB="$T_TMP/core.git"; CORE="$T_TMP/core"
git init -q --bare -b main "$CB"; git clone -q "$CB" "$CORE" 2>/dev/null
git -C "$CORE" switch -q -c main 2>/dev/null || :
mkdir -p "$CORE/bin" "$CORE/contracts"
cp "$T_ROOT/bin/hub-format.sh" "$T_ROOT/bin/library-log.sh" "$CORE/bin/"
cp "$T_ROOT/contracts/hub-vocabulary.tsv" "$T_ROOT/contracts/support-upterm.tsv" "$CORE/contracts/"
core_commit() { # <contract> <note>: a commit on main, published to the bare origin
  printf 'CONTRACT_VERSION=%s\n# %s\n' "$1" "$2" > "$CORE/bin/harbor"
  $GIT -C "$CORE" add -A; $GIT -C "$CORE" commit -q -m "$2"; $GIT -C "$CORE" push -q origin main
  git -C "$CORE" rev-parse HEAD
}
P1="$(core_commit 1 one)"; P2="$(core_commit 1 two)"; P3="$(core_commit 2 three)"
git -C "$CORE" switch -q -c side; printf 'x\n' > "$CORE/side"; $GIT -C "$CORE" add -A; $GIT -C "$CORE" commit -qm side
PSIDE="$(git -C "$CORE" rev-parse HEAD)"   # a commit that is in no main

mkhub() { # <name>: a hub with a bare origin, policy pinned at P1
  rm -rf "$T_TMP/$1" "$T_TMP/$1.git"; git init -q --bare -b main "$T_TMP/$1.git"; git clone -q "$T_TMP/$1.git" "$T_TMP/$1" 2>/dev/null
  git -C "$T_TMP/$1" switch -q -c main 2>/dev/null || :
  jq --arg c "$P1" '.hub = "test-hub" | .core.commit = $c | .approval.approvers = ["someone"]' "$T_ROOT/templates/hub/policy.json" > "$T_TMP/$1/policy.json"
  $GIT -C "$T_TMP/$1" add -A; $GIT -C "$T_TMP/$1" commit -q -m init; $GIT -C "$T_TMP/$1" push -q origin main
}
run() { # <hub> <args...>: stdout+stderr in $T_TMP/out, rc in $RC
  _h="$1"; shift; sh "$U" --hub "$T_TMP/$_h" --core "$CORE" "$@" > "$T_TMP/out" 2>&1; RC=$?
}

t_section "a good raise"
mkhub hub
run hub --pin "$P2" --key /k/hub-key
t_eq "exit 0" 0 "$RC"
t_eq "on branch pin/<12 hex>" "pin/$(printf %.12s "$P2")" "$(git -C "$T_TMP/hub" branch --show-current)"
t_eq "serial 1 -> 2" 2 "$(jq .serial "$T_TMP/hub/policy.json")"
t_eq "core.commit is the pin" "$P2" "$(jq -r .core.commit "$T_TMP/hub/policy.json")"
t_eq "issued moved" "yes" "$([ "$(jq -r .issued "$T_TMP/hub/policy.json")" != 2026-01-01T00:00:00Z ] && echo yes)"
t_eq "only policy.json changed" "policy.json" "$(git -C "$T_TMP/hub" status --porcelain | sed 's/^ *M //')"
t_has "prints the signing line with the key given" "$(cat "$T_TMP/out")" 'ssh-keygen -Y sign -f "/k/hub-key" -n harbor-hub policy.json'
t_has "names the variable to raise" "$(cat "$T_TMP/out")" 'HARBOR_HUB_CORE_SHA'
t_eq "it never signs" "" "$(ls "$T_TMP/hub"/policy.json.sig 2>/dev/null)"

t_section "refusals: exit, message, nothing changed"
refusal() { # <label> <needle> <setup command> <pin>
  mkhub hub; ( eval "$3" ); _before="$(git -C "$T_TMP/hub" status --porcelain | wc -l | tr -d ' ')"
  run hub --pin "$4"
  t_eq "$1: exit" 1 "$RC"; t_has "$1: says why" "$(cat "$T_TMP/out")" "$2"
  t_eq "$1: no branch made" main "$(git -C "$T_TMP/hub" branch --show-current)"
  t_eq "$1: policy untouched" "1" "$(jq .serial "$T_TMP/hub/policy.json")"
  t_eq "$1: status as before" "$_before" "$(git -C "$T_TMP/hub" status --porcelain | wc -l | tr -d ' ')"
}
refusal "pin on a side branch" "not on harbor-core main" : "$PSIDE"
refusal "dirty hub" "uncommitted changes" "printf x > $T_TMP/hub/stray" "$P2"
refusal "already pinned" "already pins" : "$P1"
refusal "contract change" "contract changes" : "$P3"

t_section "usage: exit 2"
mkhub hub
t_eq "no pin" 2 "$(run hub; echo $RC)"
t_eq "short pin" 2 "$(run hub --pin abc; echo $RC)"
t_eq "non-hex pin" 2 "$(run hub --pin "${P2%?}Z"; echo $RC)"
t_eq "unknown flag" 2 "$(run hub --pin "$P2" --zap; echo $RC)"
t_eq "missing value" 2 "$(run hub --pin; echo $RC)"
sh "$U" --pin "$P2" --hub "$T_TMP/nowhere" --core "$CORE" >/dev/null 2>&1; t_eq "no hub folder" 2 "$?"
sh "$U" --pin "$P2" --hub "$T_TMP/hub" --core "$T_TMP/nowhere" >/dev/null 2>&1; t_eq "no core checkout" 2 "$?"
sh "$U" --help >/dev/null 2>&1; t_eq "--help exits 0" 0 "$?"

t_section "a policy the format refuses is rolled back"
mkhub hub
jq '.hub = "Bad Name"' "$T_TMP/hub/policy.json" > "$T_TMP/p.json"; cp "$T_TMP/p.json" "$T_TMP/hub/policy.json"
$GIT -C "$T_TMP/hub" commit -qam bad; $GIT -C "$T_TMP/hub" push -q origin main
run hub --pin "$P2"
t_eq "exit 1" 1 "$RC"; t_has "names the format" "$(cat "$T_TMP/out")" "fails contracts/hub.md"
t_eq "back on main" main "$(git -C "$T_TMP/hub" branch --show-current)"
t_eq "branch removed" "" "$(git -C "$T_TMP/hub" branch --list 'pin/*')"
t_eq "tree clean" "" "$(git -C "$T_TMP/hub" status --porcelain)"
t_done
