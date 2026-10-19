#!/usr/bin/env sh
# bin/findings.sh heal (harbor#856): HEAL rows only, every repair a draft PR off a published checkout with a
# real (bare) origin, never main, and every repair written into its finding. Split from findings-test.sh.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/findings-fixture.sh"

# ── heal (harbor#856) ────────────────────────────────────────────────────────
# A published checkout with a real (bare) origin, so a push and a draft PR are observable, and a
# contract whose HEAL rows name fixture repairs. Every case reads what was written or run.
GH_STATE="$TMP/gh-heal.json"; export GH_STATE
HO="$TMP/heal-origin.git"; HP="$TMP/heal"; MARK="$TMP/route.mark"; export MARK
git init -q --bare "$HO"; mkdir -p "$HP/CONTRACTS" "$HP/bin" "$HP/skills/skill-book"
awk '/^<!-- lanes:begin -->$/ { print; print "| lane | key | subject | repair | ticket |"; print "|---|---|---|---|---|"
       print "| HEAL | `lint/lint.exec-bit-kept` | `bin/*` | `chmod +x <subject>` | #574 |"
       print "| HEAL | `lint/skill.book-current` | `skills/skill-book/SKILL.md` | `sh bin/book.sh` | #591 |"
       print "| HEAL | `lint/memory.repo-reachable` | `*` | `sh bin/route.sh` | #589 |"
       print "| HEAL | `check/memory-route` | `*` | `sh bin/route.sh` | #589 |"
       print "| HEAL | `lint/skill.not-for-target-exists` | `*` | `sh bin/fail.sh` | #590 |"
       print "| PROPOSE | `lint/lint.long-file-reason` | `*` | `chmod +x <subject>` | #590 |"; t = 1; next }
     /^<!-- lanes:end -->$/ { t = 0 } !t' "$T_ROOT/CONTRACTS/finding.md" > "$HP/CONTRACTS/finding.md"
printf 'echo tool\n' > "$HP/bin/tool.sh"; chmod 644 "$HP/bin/tool.sh"
printf 'echo fresh > skills/skill-book/SKILL.md\n' > "$HP/bin/book.sh"
printf 'echo routed >> "$MARK"\n' > "$HP/bin/route.sh"
printf 'stale\n' > "$HP/skills/skill-book/SKILL.md"
printf 'echo half >> bin/tool.sh; echo "route table locked" >&2; exit 1\n' > "$HP/bin/fail.sh"
git -C "$HP" init -q; git -C "$HP" -c user.email=t@t -c user.name=t add -A
git -C "$HP" -c user.email=t@t -c user.name=t commit -qm fixture
git -C "$HP" remote add origin "$HO"; git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
git -C "$HP" config user.email t@t; git -C "$HP" config user.name t
MAIN0="$(git -C "$HO" rev-parse main)"
heal() { HARBOR_ROOT="$HP" HARBOR_FINDINGS_NOW="${NOW:-2026-10-10}" GH_NOW="${NOW:-2026-10-10}" sh "$F" heal --from "$@" 2>&1; }
hrec() { HARBOR_ROOT="$HP" HARBOR_FINDINGS_NOW="${NOW:-2026-10-10}" GH_NOW="${NOW:-2026-10-10}" sh "$F" reconcile --from "$@" 2>&1; }
comments_on() { jq -r --argjson n "$1" '[(.comments // [])[] | select(.issue == $n) | .body] | join("\n---\n")' "$GH_STATE"; }
num_of() { jq -r --arg k "$1" '[.issues[] | select(.body | contains("key=" + $k + " "))] | max_by(.number) | .number' "$GH_STATE"; }
records "$TMP/h1" lint.exec-bit-kept lint.long-file-reason memory.repo-reachable skill.book-current -- lint.exec-bit-kept:bin/tool.sh 'lint.exec-bit-kept:bin/x;touch PWNED' lint.long-file-reason:bin/tool.sh memory.repo-reachable:azimuth memory.repo-reachable:studio skill.book-current:generator-failed

t_section "heal · a finding with no issue is not repaired, because the repair has nowhere to be written"
: > "$GH_LOG"; OUT="$(heal "$TMP/h1" --apply)"
t_has "lint.exec-bit-kept waits for the reconcile" "$OUT" "not filed yet:"
t_eq "nothing was written" 0 "$(writes)"
t_eq "nothing ran" no "$([ -f "$MARK" ] && echo yes || echo no)"
hrec "$TMP/h1" --apply > /dev/null

t_section "heal · a dry run prints the plan from the contract's rows and runs nothing"
: > "$GH_LOG"; OUT="$(heal "$TMP/h1")"
t_has "lint.exec-bit-kept on its path, the subject passed as \$1" "$OUT" 'lint/lint.exec-bit-kept bin/tool.sh → chmod +x "$1"'
t_eq "a repair with no <subject> runs once, not once per subject" 1 "$(printf '%s\n' "$OUT" | grep -c 'sh bin/route.sh')"
t_has "a subject that is not a plain path is refused" "$OUT" "refused:                 lint/lint.exec-bit-kept bin/x;touch PWNED"
t_has "PROPOSE keys, and a HEAL key's unmatched subject, are not repaired" "$OUT" "not HEAL, not repaired:  lint/lint.long-file-reason lint/skill.book-current"
t_has "a HEAL key the census cannot see says so" "$OUT" "not visible:             check/memory-route"
t_eq "no write" 0 "$(writes)"
t_eq "no repair ran" no "$([ -f "$MARK" ] && echo yes || echo no)"

t_section "heal · --apply refuses anything but the published default branch"
: > "$HP/dirty"
t_exit "a dirty tree" 1 env HARBOR_ROOT="$HP" sh "$F" heal --from "$TMP/h1" --apply
t_has "and says why" "$(heal "$TMP/h1" --apply)" "--apply heals only the published default branch"
rm -f "$HP/dirty"

t_section "heal · --apply repairs the HEAL rows only, a tracked change as a draft PR, never main"
: > "$GH_LOG"; OUT="$(heal "$TMP/h1" --apply)"
t_eq "the operator's checkout is untouched" 100644 "$(git -C "$HP" ls-files -s bin/tool.sh | cut -c1-6)"
t_eq "and its working file too" no "$([ -x "$HP/bin/tool.sh" ] && echo yes || echo no)"
_hb="$(git -C "$HO" for-each-ref --format='%(refname:short)' refs/heads/heal/)"
t_eq "one heal branch on origin, named for the digest and main's commit" \
  "heal/lint-lint.exec-bit-kept-$(sh "$F" digest bin/tool.sh 'bin/x;touch PWNED')-$(git -C "$HP" rev-parse --short=7 HEAD)" "$_hb"
t_eq "and no local heal branch is left behind" "" "$(git -C "$HP" branch --list 'heal/*')"
t_eq "carrying the repair" 100755 "$(git -C "$HO" ls-tree "$_hb" bin/tool.sh | cut -c1-6)"
t_eq "main on origin did not move" "$MAIN0" "$(git -C "$HO" rev-parse main)"
t_eq "the PR is a draft" true "$(jq -r '.prs[0].draft' "$GH_STATE")"
t_has "the repair is written into the lint.exec-bit-kept finding" "$(comments_on "$(num_of lint/lint.exec-bit-kept)")" 'chmod +x "$1"` on `bin/tool.sh` → exit 0'
t_has "with its PR" "$(comments_on "$(num_of lint/lint.exec-bit-kept)")" "draft PR: https://github.com/o/r/pull/101"
t_has "an untracked-only repair says there is no PR" "$(comments_on "$(num_of lint/memory.repo-reachable)")" "No tracked file changed"
t_eq "and ran once" 1 "$(grep -c . "$MARK")"
t_eq "the falsifier: a PROPOSE finding gets no repair" "" "$(comments_on "$(num_of lint/lint.long-file-reason)")"
t_eq "and a refused subject never reached a shell" "" "$(find "$TMP" -name PWNED)"
t_eq "no worktree is left behind" 1 "$(git -C "$HP" worktree list | grep -c .)"

t_section "heal · the next run does not open a second PR, and a recurring repair shows as a recurrence"
NOW=2026-10-11; OUT="$(heal "$TMP/h1" --apply)"
t_has "the open PR is named" "$OUT" "draft PR #101, already open"
t_eq "still one PR" 1 "$(jq '.prs | length' "$GH_STATE")"
t_eq "memory.repo-reachable now carries two repairs" 2 "$(comments_on "$(num_of lint/memory.repo-reachable)" | grep -c '^healed ')"

t_section "heal · the repair is the contract's text: a mutant row changes what runs"
sed -i.bak 's/`chmod +x <subject>`/`touch <subject>.mutant`/' "$HP/CONTRACTS/finding.md"; rm -f "$HP/CONTRACTS/finding.md.bak"
t_has "the mutant command is planned" "$(heal "$TMP/h1")" 'lint/lint.exec-bit-kept bin/tool.sh → touch "$1".mutant'
git -C "$HP" checkout -q -- CONTRACTS/finding.md

t_section "heal · review #891: a recurrence after the PR merged is healed again, on a new branch"
jq '(.prs[0].state) = "MERGED"' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
printf 'moved\n' > "$HP/moved"; git -C "$HP" add moved; git -C "$HP" commit -qm "main moves"
git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
NOW=2026-10-12; OUT="$(heal "$TMP/h1" --apply)"
t_eq "a second PR" 2 "$(jq '.prs | length' "$GH_STATE")"
t_eq "two heal branches on origin" 2 "$(git -C "$HO" for-each-ref refs/heads/heal/ | grep -c .)"
t_hasnt "and nothing failed" "$OUT" "FAILED"

t_section "heal · review #891: a PR whose record never reached the finding gets it on the next run"
_s6="$(num_of lint/lint.exec-bit-kept)"
jq --argjson n "$_s6" '.comments |= [.[] | select(.issue != $n)]' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
NOW=2026-10-13; heal "$TMP/h1" --apply > /dev/null
t_has "the missing record is written" "$(comments_on "$_s6")" "healed earlier as draft PR https://github.com/o/r/pull/102"
NOW=2026-10-14; heal "$TMP/h1" --apply > /dev/null
t_eq "and only once" 1 "$(comments_on "$_s6" | grep -c 'healed earlier')"

t_section "heal · review #891: a failed repair publishes nothing and fails the run"
records "$TMP/h2" skill.not-for-target-exists -- skill.not-for-target-exists:bin/tool.sh
hrec "$TMP/h2" --apply > /dev/null
_prs="$(jq '.prs | length' "$GH_STATE")"
t_exit "the run exits 1" 1 env HARBOR_ROOT="$HP" HARBOR_FINDINGS_NOW=2026-10-15 GH_NOW=2026-10-15 sh "$F" heal --from "$TMP/h2" --apply
t_eq "no PR for the partial change" "$_prs" "$(jq '.prs | length' "$GH_STATE")"
t_eq "no skill.not-for-target-exists branch on origin" "" "$(git -C "$HO" for-each-ref refs/heads/heal/lint-skill.not-for-target-exists-)"
t_has "the failure and its output are in the finding" "$(comments_on "$(num_of lint/skill.not-for-target-exists)")" "route table locked"
t_has "and it says nothing was published" "$(comments_on "$(num_of lint/skill.not-for-target-exists)")" "A repair FAILED, so nothing was published"
t_eq "the checkout is untouched" "" "$(git -C "$HP" status --porcelain)"

t_section "heal · review #891: a PR that failed to open is retried from the pushed branch, nothing left stale"
jq '(.prs[] | select(.state == "OPEN")).state = "MERGED"' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
printf 'again\n' > "$HP/moved"; git -C "$HP" commit -qam "main moves again"
git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
_prs="$(jq '.prs | length' "$GH_STATE")"
t_exit "a failed PR create fails the run" 1 env GIT_AUTHOR_DATE=2026-10-16T09:00:00 GIT_COMMITTER_DATE=2026-10-16T09:00:00 GH_FAIL=prcreate HARBOR_ROOT="$HP" HARBOR_FINDINGS_NOW=2026-10-16 GH_NOW=2026-10-16 sh "$F" heal --from "$TMP/h1" --apply
t_eq "no PR" "$_prs" "$(jq '.prs | length' "$GH_STATE")"
t_eq "no worktree left registered" 1 "$(git -C "$HP" worktree list | grep -c .)"
t_eq "no local heal branch" "" "$(git -C "$HP" branch --list 'heal/*')"
t_has "the finding says the branch waits" "$(comments_on "$(num_of lint/lint.exec-bit-kept)")" "opening its draft PR FAILED"
# a later commit time, so a re-push would be a different commit and rejected, as it is for real
NOW=2026-10-17; OUT="$(GIT_AUTHOR_DATE=2026-10-17T09:00:00 GIT_COMMITTER_DATE=2026-10-17T09:00:00 heal "$TMP/h1" --apply)"
t_eq "the retry opens the PR" "$((_prs + 1))" "$(jq '.prs | length' "$GH_STATE")"
t_hasnt "and does not fail" "$OUT" "FAILED"

t_section "heal · review #891: a fork's PR on the heal prefix is not the repair"
jq '(.prs[] | select(.state == "OPEN")).state = "MERGED"' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
_hb="heal/lint-lint.exec-bit-kept-$(sh "$F" digest bin/tool.sh 'bin/x;touch PWNED')-$(git -C "$HP" rev-parse --short=7 HEAD)"
jq --arg h "$_hb" '.prs += [{number: 900, head: $h, draft: false, state: "OPEN", fork: true}]' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
_prs="$(jq '.prs | length' "$GH_STATE")"
NOW=2026-10-18; OUT="$(heal "$TMP/h1" --apply)"
t_has "the fork's PR is not reused: a new draft is named" "$OUT" "lint/lint.exec-bit-kept → draft PR https://github.com/o/r/pull/"
t_eq "our own draft PR is opened" "$((_prs + 1))" "$(jq '.prs | length' "$GH_STATE")"

t_section "heal · review #891: a signal mid-repair leaves no worktree and no branch behind"
jq '(.prs[] | select(.state == "OPEN" and (.fork | not))).state = "MERGED"' "$GH_STATE" > "$GH_STATE.n" && mv "$GH_STATE.n" "$GH_STATE"
printf 'and again\n' > "$HP/moved"; git -C "$HP" commit -qam "main moves a third time"
git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
# the repair sends TERM to the runner, the way a person's ^C or a timeout would arrive
printf 'chmod +x "$1"; kill -TERM $PPID_HEAL\n' > "$TMP/killer.sh"
sed -i.bak 's#`chmod +x <subject>` | \#574#`sh '"$TMP"'/killer.sh <subject>` | \#574#' "$HP/CONTRACTS/finding.md"; rm -f "$HP/CONTRACTS/finding.md.bak"
git -C "$HP" commit -qam "a repair that is interrupted"; git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
HARBOR_ROOT="$HP" HARBOR_FINDINGS_NOW=2026-10-19 GH_NOW=2026-10-19 sh -c 'PPID_HEAL=$$; export PPID_HEAL; exec sh "$0" heal --from "$1" --apply' "$F" "$TMP/h1" > /dev/null 2>&1
t_eq "no worktree left registered" 1 "$(git -C "$HP" worktree list | grep -c .)"
t_eq "no local heal branch" "" "$(git -C "$HP" branch --list 'heal/*')"

t_section "check tier · heal sees check/memory-route and runs its repair"
GH_STATE="$TMP/gh-heal.json"; export GH_STATE
cp "$T_ROOT/CHECKS.md" "$HP/CHECKS.md"; git -C "$HP" add CHECKS.md; git -C "$HP" commit -qm "the registry"
git -C "$HP" push -q origin HEAD:main; git -C "$HP" fetch -q origin
rcpt memory-route red 2026-10-27 harbor/wt-a
records "$TMP/c1" lint.long-file-reason -- lint.long-file-reason:bin/big.sh
NOW=2026-10-27; hrec "$TMP/c1" --apply > /dev/null
: > "$MARK"; NOW=2026-10-27; OUT="$(heal "$TMP/c1" --apply)"
t_has "planned and run" "$OUT" "check/memory-route → sh bin/route.sh"
t_eq "the repair ran once" 1 "$(grep -c . "$MARK")"
t_has "and is written into the finding" "$(comments_on "$(num_of check/memory-route)")" '`sh bin/route.sh` → exit 0'
t_hasnt "it is no longer reported as not visible" "$OUT" "not visible:             check/memory-route"
t_has "positive control: the run printed its header" "$OUT" "findings heal:"

t_section "check tier · review: a stood-down subject is never repaired, whatever the HEAL glob"
GH_STATE="$TMP/gh-heal.json"; export GH_STATE
rcpt memory-route stood-down 2026-10-28
NOW=2026-10-28; hrec "$TMP/c1" --apply > /dev/null
: > "$MARK"; OUT="$(NOW=2026-10-28 heal "$TMP/c1" --apply)"; _rc=$?
t_eq "the repair did not run" 0 "$(grep -c . "$MARK")"
t_eq "and heal does not fail on it" 0 "$_rc"
t_has "it is listed as not repaired" "$OUT" "check/memory-route"

t_done
