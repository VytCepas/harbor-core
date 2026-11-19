#!/usr/bin/env sh
# bin/hub-release.sh (harbor#1278): the release chain as one tool. Scratch git repos on local bare origins, a gh stub over JSON files,
# stubs for the tools it calls (red-team, ci-mirror, hub-pin-upgrade, member-setup-generate, the pin's suite runner). No network, no key.
# The preflight cases come first: each must leave every checkout, the PR stub and the call log exactly as found.
. "$(dirname "$0")/../../lib/core.sh"; t_init
U="$T_ROOT/bin/hub-release.sh"
GIT_AUTHOR_NAME=t; GIT_AUTHOR_EMAIL=t@t.test; GIT_COMMITTER_NAME=t; GIT_COMMITTER_EMAIL=t@t.test
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
unset CLAUDECODE
TOKEN="faketoken-Zq81"

# gh stub: PR state is a JSON file per PR in $STUB/pr; every call is logged. A <file>.<k> answers the k-th view (the
# merge step re-reads each PR); $STUB/merge_refused makes the merge fail; $STUB/diverge (a checkout path) gives that
# checkout a local commit and its origin another, so the fast-forward after the merges cannot run.
cat > "$T_BIN/gh" <<'STUBEOF'
#!/bin/sh
echo "gh $*" >> "$STUB/gh.log"
slug=''; p=''; for a in "$@"; do [ "$p" = -R ] && slug="$a"; p="$a"; done
case "$1 $2" in
  "pr view") f="$STUB/pr/$(printf %s "$slug" | tr / _)-$3.json"; [ -f "$f" ] || { echo "no such pull request" >&2; exit 1; }
    k=$(( $(cat "$f.views" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$f.views"
    if [ -f "$f.$k" ]; then cat "$f.$k"; else cat "$f"; fi ;;
  "pr merge") [ ! -f "$STUB/merge_refused" ] || { echo "stub: the base branch policy prohibits the merge" >&2; exit 1; }
    f="$STUB/pr/$(printf %s "$slug" | tr / _)-$3.json"; sed 's/"state":"OPEN"/"state":"MERGED"/' "$f" > "$f.n" && mv "$f.n" "$f"
    if [ -f "$STUB/diverge" ]; then d="$(cat "$STUB/diverge")"; git -C "$d" commit -q --allow-empty -m local
      git clone -q "$(git -C "$d" config --get remote.origin.url)" "$STUB/dv" && git -C "$STUB/dv" commit -q --allow-empty -m theirs && git -C "$STUB/dv" push -q origin main; fi ;;
  "pr review") : ;;
  *) echo "gh stub: unhandled $*" >&2; exit 9 ;;
esac
STUBEOF
chmod +x "$T_BIN/gh"

TPL="$T_TMP/tpl"; mkdir -p "$TPL"
mkorigin() { # <name> <file-writing commands, run inside the scratch clone>
  git init -q --bare -b main "$TPL/$1.git"; git clone -q "$TPL/$1.git" "$TPL/w-$1" 2>/dev/null
  ( cd "$TPL/w-$1" && git switch -q -c main 2>/dev/null; eval "$2"; git add -A; git commit -q -m init; git push -q origin main )
}
mkorigin harbor '
mkdir bin
cat > bin/eval-redteam-corpus.sh <<"X"
#!/bin/sh
echo "redteam $*" >> "$STUB/calls"
case "${1:-}" in
  --print) echo print >> "$STUB/order"; case "$(cat "$STUB/rt_mode")" in
      fresh) echo "  ok: stub"; exit 0 ;;
      stale) echo "  FAIL: stale: the guards or the pins changed since the last run"; exit 1 ;;
      never) echo "  FAIL: redteam-corpus has never run here"; exit 3 ;;
      red) echo "  FAIL: shguard/guardfall: 2 miss(es), 2 not accepted"; exit 1 ;;
    esac ;;
  *) echo refresh >> "$STUB/order"; if [ -f "$STUB/rt_moves_main" ]; then
       git clone -q "$HORIG" "$STUB/other" && git -C "$STUB/other" commit -q --allow-empty -m "another session merged" && git -C "$STUB/other" push -q origin main
     fi
     [ -f "$STUB/rt_stays_stale" ] || echo fresh > "$STUB/rt_mode"
     [ ! -f "$STUB/rt_refresh_red" ] || exit 1
     exit 0 ;;
esac
X
cat > bin/ci-mirror.sh <<"X"
#!/bin/sh
echo "mirror argv: $*" >> "$STUB/calls"
echo "mirror env: token=${HARBOR_CI_CORE_MIRROR_TOKEN:-none} dir=${HARBOR_CI_CORE_MIRROR_DIR:-none}" >> "$STUB/env"
echo mirror >> "$STUB/order"
[ ! -f "$STUB/publish_fails" ] || { echo "  FAIL: a gate is red"; exit 1; }
[ -f "$STUB/publish_noop" ] || { git clone -q "$CORIG" "$STUB/corew" && git -C "$STUB/corew" commit -q --allow-empty -m publish && git -C "$STUB/corew" push -q origin main; }
X
cat > bin/hub-pin-upgrade.sh <<"X"
#!/bin/sh
echo "pin $*" >> "$STUB/calls"; echo pin >> "$STUB/order"
pin=""; hub=""; while [ $# -gt 0 ]; do case "$1" in --pin) pin="$2" ;; --hub) hub="$2" ;; esac; shift; done
git -C "$hub" switch -q -c "pin/$(printf %.12s "$pin")"
X
cat > bin/member-setup-generate.sh <<"X"
#!/bin/sh
echo "zips $*" >> "$STUB/calls"; echo zips >> "$STUB/order"
out=""; while [ $# -gt 0 ]; do case "$1" in --out) out="$2" ;; esac; shift; done
mkdir -p "$out/zips"
X
'
mkorigin core '
mkdir bin contracts
cat > bin/test-suite-run.sh <<"X"
#!/bin/sh
echo "suites $*" >> "$STUB/calls"; echo suites >> "$STUB/order"; cat "$2" >> "$STUB/calls"
[ ! -f "$STUB/suites_red" ] || { echo "  FAIL: member suite red"; exit 1; }
X
printf "tests/member/a.test.sh\ntests/hub/b.test.sh\ntests/other/x.test.sh\n" > contracts/suites.txt'
mkorigin hub 'printf "{\"core\":{\"commit\":\"x\"}}\n" > policy.json; printf "hub-signers\n" > hub-signers'

N=0
sc() { # a fresh scenario: three clones on their own bare origins, stub state, a roster and a kit
  N=$((N + 1)); S="$T_TMP/s$N"; mkdir -p "$S"
  for r in harbor core hub; do cp -R "$TPL/$r.git" "$S/$r.git"; git clone -q "$S/$r.git" "$S/$r" 2>/dev/null; done
  H="$S/harbor"; C="$S/core"; B="$S/hub"; STUB="$S/stub"; mkdir -p "$STUB/pr" "$S/kit"
  HORIG="$S/harbor.git"; CORIG="$S/core.git"; export STUB HORIG CORIG
  echo fresh > "$STUB/rt_mode"; : > "$STUB/calls"; : > "$STUB/gh.log"
  printf 'u\tl\n' > "$S/roster.tsv"; for f in run-setup.ps1 INSTALL-FOR-CLAUDE.md CLAUDE.md; do : > "$S/kit/$f"; done
}
GREEN='[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]'
pr() { # <slug> <n> <state> <mergeable> <mergeStateStatus> <review> <rollup> [base] [draft]; PR_VIEW=k: the k-th view only; PR_OID: the head
  printf '{"state":"%s","isDraft":%s,"mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"%s","headRefOid":"%s","baseRefName":"%s","statusCheckRollup":%s}\n' \
    "$3" "${9:-false}" "$4" "$5" "$6" "${PR_OID:-$(printf '%040d' "$2")}" "${8:-main}" "$7" > "$STUB/pr/$(printf %s "$1" | tr / _)-$2.json${PR_VIEW:+.$PR_VIEW}"
}
rel() { # <mode> [more args]: the tool over the scenario; output in $T_TMP/out, status in $RC
  _m="$1"; shift
  # the agent flag only for an agent session: a variable set in front of a shell function would outlive the call
  if [ -n "${AGENT:-}" ]; then _e=1; else _e=''; fi
  if [ -n "${NOTOKEN:-}" ]; then _tk=''; else _tk="$TOKEN"; fi
  if [ -n "${NOMIRPR:-}" ]; then set -- --log-dir "$S/logs" "$@"; else set -- --log-dir "$S/logs" --mirror-pr 99 "$@"; fi
  CLAUDECODE="$_e" HARBOR_CI_CORE_MIRROR_TOKEN="$_tk" sh "$U" "$_m" --harbor "$H" --core "$C" --hub "$B" --hub-repo o/hub --roster "$S/roster.tsv" --kit "$S/kit" --out "$S/out" \
    "$@" > "$T_TMP/out" 2>&1; RC=$?
}
OUT() { cat "$T_TMP/out"; }
ord() { tr '\n' ' ' < "$STUB/order" 2>/dev/null; }   # the steps the stubs saw, in order
state() { # everything a preflight must leave alone
  { for _d in "$H" "$C" "$B"; do git -C "$_d" rev-parse HEAD; git -C "$_d" status --porcelain; git -C "$_d" branch --show-current; done
    cat "$STUB/pr"/*.json 2>/dev/null; grep -c 'pr merge' "$STUB/gh.log" || :; } | cksum
}
pre_bad() { # <label> <needle>: a preflight that must find exactly this, and leave everything as it was
  _b="$(state)"; rel --preflight --pr o/r#7
  t_eq "$1: exit 1" 1 "$RC"; t_has "$1: names it" "$(OUT)" "$2"; t_has "$1: says nothing changed" "$(OUT)" "nothing was changed"
  t_eq "$1: nothing touched" "$_b" "$(state)"
}

t_section "preflight: a clean release"
sc; pr o/r 7 OPEN MERGEABLE CLEAN REVIEW_REQUIRED "$GREEN"
rel --preflight --pr o/r#7
t_eq "exit 0" 0 "$RC"; t_has "the PR is ok" "$(OUT)" "o/r#7 open, mergeable, up to date, 2 checks green"
t_has "an approval is noted" "$(OUT)" "needs an approval"
t_has "red-team fresh" "$(OUT)" "red-team record is fresh"
t_has "names its log" "$(OUT)" "log: $S/logs/backups/hub-release/"
t_eq "the log file exists" yes "$([ -s "$(OUT | sed -n 's/^log: //p')" ] && echo yes)"
t_eq "the red-team refresh did not run" "print " "$(ord)"

t_section "preflight: each problem is a finding, and nothing changes"
sc; pr o/r 7 OPEN CONFLICTING DIRTY - "$GREEN"; pre_bad "conflicting PR" "o/r#7 conflicts with its base"
sc; pr o/r 7 OPEN MERGEABLE BEHIND - "$GREEN"; pre_bad "BEHIND PR" "o/r#7 is BEHIND its base"
sc; pr o/r 7 CLOSED UNKNOWN UNKNOWN - "$GREEN"; pre_bad "landed through another PR" "o/r#7 is CLOSED, not open"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - '[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"},{"__typename":"StatusContext","state":"SUCCESS"}]'
pre_bad "a failed check" "1 of 2 checks are not green"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - '[{"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null}]'; pre_bad "a running check" "1 of 1 checks are not green"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - '[]'; pre_bad "no checks" "reports no checks"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN" develop; pre_bad "a PR not based on main" "based on develop, not main"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN" main true; pre_bad "a draft" "o/r#7 is a draft"
sc; pr o/r 7 OPEN UNKNOWN UNKNOWN - "$GREEN"; pre_bad "mergeability not computed" "has not worked out its mergeability"
sc; pre_bad "a PR gh cannot find" "o/r#7: cannot read it"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; git -C "$H" switch -q -c other; pre_bad "harbor on another branch" "is on other, not main"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; echo x > "$C/stray"; pre_bad "a dirty core checkout" "harbor-core: $C has uncommitted"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; git -C "$H" commit -q --allow-empty -m local; pre_bad "an unpushed commit on harbor main" "1 commit(s) ahead of origin/main"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; : > "$B/.git/index.lock"; touch -t 200001010000 "$B/.git/index.lock"
BP="$(cd "$B" && pwd -P)"
pre_bad "a stale 0-byte index.lock" "hub: $BP/.git/index.lock is stale (0 bytes"; t_has "the stale lock's fix is the rm line" "$(OUT)" "fix: rm -f $BP/.git/index.lock"
t_eq "the stale lock was NOT removed" yes "$([ -e "$B/.git/index.lock" ] && echo yes)"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; : > "$H/.git/index.lock"; pre_bad "a fresh index.lock" "a git process may hold it"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; echo red > "$STUB/rt_mode"; pre_bad "an unaccepted red-team finding" "1 corpus finding(s) are not accepted"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; rm "$S/roster.tsv"; pre_bad "no roster" "--roster: no file"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; rm "$S/kit/CLAUDE.md"; pre_bad "an incomplete kit" "--kit lacks CLAUDE.md"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; git -C "$B" rm -q hub-signers; git -C "$B" commit -q -m x; git -C "$B" push -q origin main; pre_bad "no hub-signers" "no hub-signers"

t_section "preflight: not findings"
sc; pr o/r 7 MERGED - - - "$GREEN"
rel --preflight --pr o/r#7; t_eq "a merged PR: exit 0" 0 "$RC"; t_has "a merged PR is skipped" "$(OUT)" "o/r#7 is already merged: skipped"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; git clone -q "$HORIG" "$S/o" && git -C "$S/o" commit -q --allow-empty -m moved && git -C "$S/o" push -q origin main
rel --preflight --pr o/r#7; t_eq "harbor behind origin: exit 0" 0 "$RC"; t_has "behind is a note" "$(OUT)" "1 commit(s) behind origin/main; the run fast-forwards it"
sc; echo stale > "$STUB/rt_mode"; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"
rel --preflight --pr o/r#7; t_eq "stale red-team with a merge pending: exit 0" 0 "$RC"; t_has "it says the run refreshes" "$(OUT)" "the run refreshes it immediately before the publish"
sc; echo stale > "$STUB/rt_mode"; pr o/r 7 MERGED - - - "$GREEN"
rel --preflight --pr o/r#7; t_eq "stale red-team, nothing to merge: exit 1" 1 "$RC"; t_has "it is a finding" "$(OUT)" "the record is stale for the current guards"
sc; echo never > "$STUB/rt_mode"; rel --preflight; t_eq "never run, nothing to merge: exit 1" 1 "$RC"
sc; git -C "$B" switch -q -c "pin/$(printf %.12s "$(git -C "$C" rev-parse HEAD)")"; printf '{"core":{"commit":"%s"}}\n' "$(git -C "$C" rev-parse HEAD)" > "$B/policy.json"
rel --preflight; t_eq "a hub already raised on its pin branch: exit 0" 0 "$RC"; t_has "it says the pin step is skipped" "$(OUT)" "the pin step will be skipped"
sc; git -C "$B" switch -q -c pin/aaaaaaaaaaaa; rel --preflight; t_eq "a hub on a stale pin branch: exit 1" 1 "$RC"; t_has "it names it" "$(OUT)" "does not hold core's tip"

t_section "preflight: every problem in one list"
sc; pr o/r 7 OPEN CONFLICTING DIRTY - "$GREEN"; pr o/s 8 OPEN MERGEABLE BEHIND - '[]'; pr o/t 9 CLOSED UNKNOWN UNKNOWN - "$GREEN"
git -C "$H" switch -q -c other; echo x > "$C/stray"; : > "$B/.git/index.lock"; touch -t 200001010000 "$B/.git/index.lock"; echo red > "$STUB/rt_mode"; rm "$S/roster.tsv"
_b="$(state)"; rel --preflight --pr o/r#7 --pr o/s#8 --pr o/t#9
t_eq "exit 1" 1 "$RC"
t_eq "nine findings in the one list" 9 "$(OUT | grep -c '^  FAIL: ')"
t_has "the count is named" "$(OUT)" "9 finding(s) above, each with its fix line: nothing was changed"
t_eq "nothing touched" "$_b" "$(state)"

t_section "usage"
sc
sh "$U" > "$T_TMP/out" 2>&1; t_eq "no mode: exit 2" 2 "$?"
rel --preflight --pr nope; t_eq "a bad --pr: exit 2" 2 "$RC"
rel --preflight --zap; t_eq "an unknown flag: exit 2" 2 "$RC"
sh "$U" --preflight --core "$C" --hub "$B" > "$T_TMP/out" 2>&1; t_eq "missing inputs: exit 2" 2 "$?"
sh "$U" --help > "$T_TMP/out" 2>&1; t_eq "--help: exit 0" 0 "$?"; t_has "--help says signing is not here" "$(OUT)" "SIGNING IS NOT HERE"

t_section "run: a list that is not empty stops it before anything moves"
sc; pr o/r 7 OPEN CONFLICTING DIRTY - "$GREEN"; _b="$(state)"
rel --run --pr o/r#7
t_eq "exit 1" 1 "$RC"; t_has "says nothing was changed" "$(OUT)" "nothing was changed"
t_eq "nothing touched" "$_b" "$(state)"
t_eq "no merge" 0 "$(grep -c 'pr merge' "$STUB/gh.log" || :)"; t_eq "only the read-only red-team print ran" "print " "$(ord)"

t_section "run: in an agent session the merges are printed, not run"
sc; pr o/r 7 OPEN MERGEABLE CLEAN REVIEW_REQUIRED "$GREEN"; pr o/s 8 OPEN MERGEABLE CLEAN - "$GREEN"
AGENT=1; rel --run --pr o/r#7 --pr o/s#8; AGENT=
t_eq "exit 3" 3 "$RC"
t_has "the merge line, pinned to the head" "$(OUT)" "gh pr merge 7 -R o/r --squash --delete-branch --match-head-commit $(printf '%040d' 7)"
t_has "the second" "$(OUT)" "gh pr merge 8 -R o/s --squash --delete-branch --match-head-commit $(printf '%040d' 8)"
t_has "the approval line where one is required" "$(OUT)" "gh pr review 7 -R o/r --approve"
t_eq "gh pr merge never ran" 0 "$(grep -c '^gh pr merge' "$STUB/gh.log" || :)"
t_eq "only the read-only red-team print ran" "print " "$(ord)"

t_section "run: the whole chain, in order"
sc; echo stale > "$STUB/rt_mode"; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"
rel --run --pr o/r#7
t_eq "exit 0" 0 "$RC"; t_eq "the merge ran, pinned to the head" 1 "$(grep -c "^gh pr merge 7 -R o/r --squash --delete-branch --match-head-commit $(printf '%040d' 7)" "$STUB/gh.log" || :)"
t_eq "order: preflight read, refresh, re-check, publish, hub pin, suites, zips" "print refresh print mirror pin suites zips " "$(ord)"
t_eq "the publish was named for --mirror-pr" "mirror argv: --publish 99" "$(grep '^mirror argv' "$STUB/calls")"
t_has "only the member and hub suites ran" "$(cat "$STUB/calls")" "tests/hub/b.test.sh"
t_hasnt "the other suite did not" "$(cat "$STUB/calls")" "tests/other/x.test.sh"
t_eq "the publish got the token in its environment and the dir" "mirror env: token=$TOKEN dir=$C" "$(cat "$STUB/env")"
t_eq "the tool never asked gh for a credential" 0 "$(grep -c '^gh auth' "$STUB/gh.log" || :)"
t_hasnt "the token is in no argv" "$(cat "$STUB/calls" "$STUB/gh.log")" "$TOKEN"
t_hasnt "the token is on neither screen nor log" "$(OUT; cat "$S"/logs/backups/hub-release/*/log)" "$TOKEN"
t_eq "the hub is on its pin branch" "pin/$(git -C "$S/core.git" rev-parse main | cut -c1-12)" "$(git -C "$B" branch --show-current)"
t_has "signing is handed to the admin" "$(OUT)" "signs BY HAND"
t_hasnt "no signing line is run or printed by the tool" "$(OUT)" "ssh-keygen"
t_has "names its log" "$(OUT)" "log: $S/logs/backups/hub-release/"
t_has "the log holds the children's output" "$(cat "$S"/logs/backups/hub-release/*/log)" "the new pin"

t_section "run: outside an agent session a required approval is given, then the merge"
sc; pr o/r 7 OPEN MERGEABLE CLEAN REVIEW_REQUIRED "$GREEN"
rel --run --pr o/r#7
t_eq "exit 0" 0 "$RC"
t_eq "the approval ran, then the merge" "review merge " "$(grep -E '^gh pr (review|merge)' "$STUB/gh.log" | awk '{ printf "%s ", $3 }')"
t_has "...the approval for that PR" "$(cat "$STUB/gh.log")" "gh pr review 7 -R o/r --approve"

t_section "run: a PR that changed or moved after the preflight is a stop"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"
PR_VIEW=2; pr o/r 7 OPEN MERGEABLE CLEAN - '[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"}]'; PR_VIEW=
rel --run --pr o/r#7
t_eq "a check went red since the preflight: exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "o/r#7 changed since the preflight; nothing further was merged"
t_eq "...no merge ran" 0 "$(grep -c '^gh pr merge' "$STUB/gh.log" || :)"; t_eq "...nothing was published" 0 "$(ord | grep -c mirror || :)"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; pr o/s 8 OPEN MERGEABLE CLEAN - "$GREEN"
PR_VIEW=2; PR_OID="abcdef123456$(printf '%028d' 0)"; pr o/s 8 OPEN MERGEABLE CLEAN - "$GREEN"; PR_VIEW=; PR_OID=
rel --run --pr o/r#7 --pr o/s#8
t_eq "a head that moved since the preflight, green at its new head: exit 1" 1 "$RC"
t_has "it names both heads" "$(OUT)" "o/s#8 moved from $(printf '%012d' 0) to abcdef123456 since the preflight; nothing further was merged"
t_eq "...the PR before it merged at its preflight head, the moved one not at all" "gh pr merge 7 -R o/r --squash --delete-branch --match-head-commit $(printf '%040d' 7)" "$(grep '^gh pr merge' "$STUB/gh.log")"
t_eq "...nothing was published" 0 "$(ord | grep -c mirror || :)"

t_section "run: a refused merge, and checkouts that cannot fast-forward, stop the chain"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; : > "$STUB/merge_refused"; rel --run --pr o/r#7
t_eq "merge refused: exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "gh pr merge refused o/r#7"; t_eq "...nothing after it ran" "print " "$(ord)"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; printf '%s\n' "$C" > "$STUB/diverge"; rel --run --pr o/r#7
t_eq "harbor-core diverged during the merges: exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "harbor-core: cannot fast-forward $C to origin/main"
t_eq "...nothing after it ran" "print " "$(ord)"

t_section "run: the publish names the last harbor PR when --mirror-pr is not given"
sc; HGH=https://github.com/o/harbor.git; git -C "$H" config "url.$HORIG.insteadOf" "$HGH"; git -C "$H" remote set-url origin "$HGH"
pr o/harbor 5 OPEN MERGEABLE CLEAN - "$GREEN"; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; pr o/harbor 6 OPEN MERGEABLE CLEAN - "$GREEN"
NOMIRPR=1; rel --run --pr o/harbor#5 --pr o/harbor#6 --pr o/r#7
t_eq "exit 0" 0 "$RC"; t_eq "the publish was named for the last harbor PR, not another repo's" "mirror argv: --publish 6" "$(grep '^mirror argv' "$STUB/calls")"
sc; rel --run; NOMIRPR=
t_eq "no harbor PR and no --mirror-pr: exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "no harbor PR to name for the publish"; t_eq "...nothing was published" 0 "$(ord | grep -c mirror || :)"

t_section "run: no push credential"
sc; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"; _b="$(state)"
NOTOKEN=1; rel --preflight --pr o/r#7; t_eq "a preflight without the token: exit 0" 0 "$RC"; t_has "it notes the token" "$(OUT)" "HARBOR_CI_CORE_MIRROR_TOKEN is not set; --run needs it"
rel --run --pr o/r#7; NOTOKEN=
t_eq "a run without the token: exit 1" 1 "$RC"; t_has "it is a finding" "$(OUT)" "so the publish could not reach harbor-core"
t_eq "nothing touched" "$_b" "$(state)"; t_eq "no merge ran" 0 "$(grep -c '^gh pr merge' "$STUB/gh.log" || :)"

t_section "run: main moves during the red-team refresh"
sc; echo stale > "$STUB/rt_mode"; : > "$STUB/rt_moves_main"; pr o/r 7 OPEN MERGEABLE CLEAN - "$GREEN"
rel --run --pr o/r#7
t_eq "exit 1" 1 "$RC"; t_has "it says main moved" "$(OUT)" "main moved while the red-team ran"
t_eq "nothing was published" 0 "$(ord | grep -c mirror || :)"

t_section "run: a record that is not fresh right before the publish"
sc; echo stale > "$STUB/rt_mode"; : > "$STUB/rt_stays_stale"; rel --run
t_eq "exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "not fresh and green right before the publish"; t_eq "nothing was published" 0 "$(ord | grep -c mirror || :)"
sc; echo stale > "$STUB/rt_mode"; : > "$STUB/rt_refresh_red"; rel --run
t_eq "a red refresh: exit 1" 1 "$RC"; t_has "it says so" "$(OUT)" "the red-team refresh is red"; t_eq "nothing was published" 0 "$(ord | grep -c mirror || :)"

t_section "run: each later step stops the chain"
sc; : > "$STUB/publish_fails"; rel --run
t_eq "publish refused: exit 1" 1 "$RC"; t_eq "no hub pin after it" 0 "$(grep -c '^pin ' "$STUB/calls" || :)"
sc; : > "$STUB/suites_red"; rel --run
t_eq "suites red: exit 1" 1 "$RC"; t_has "it says RED" "$(OUT)" "RED at"; t_eq "no zips after it" 0 "$(grep -c '^zips ' "$STUB/calls" || :)"
t_eq "the hub is on its pin branch (it stays: signing is the admin's)" 1 "$(git -C "$B" branch --show-current | grep -c '^pin/')"

t_section "run: a re-run skips what is done"
sc; : > "$STUB/publish_noop"; pr o/r 7 MERGED - - - "$GREEN"
_tip="$(git -C "$C" rev-parse HEAD)"; git -C "$B" switch -q -c "pin/$(printf %.12s "$_tip")"; printf '{"core":{"commit":"%s"}}\n' "$_tip" > "$B/policy.json"
rel --run --pr o/r#7
t_eq "exit 0" 0 "$RC"; t_has "the merged PR is skipped" "$(OUT)" "already merged"; t_has "no merge left" "$(OUT)" "no PR left to merge"
t_eq "gh pr merge never ran" 0 "$(grep -c '^gh pr merge' "$STUB/gh.log" || :)"
t_has "the hub step is skipped" "$(OUT)" "the hub is already on pin/"; t_eq "hub-pin-upgrade did not run" 0 "$(grep -c '^pin ' "$STUB/calls" || :)"
t_done
