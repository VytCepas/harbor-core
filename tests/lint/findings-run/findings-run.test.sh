#!/usr/bin/env sh
# bin/lint-findings-run.sh (harbor#856): the scheduled reconcile-then-heal. A bare repo stands in for GitHub
# and a clone for ~/port/harbor; main's bin/lint-findings.sh is a fake that records how it was called.
# Every case reads what ran and what was written, never only what was printed.
. "$(dirname "$0")/../../lib/core.sh"; t_init
R="$T_ROOT/bin/lint-findings-run.sh"
TMP="$T_TMP/fr"; mkdir -p "$TMP"
CALLS="$TMP/calls"; EVIL="$TMP/evil"; export CALLS EVIL
CLAUDE_CONFIG_DIR="$TMP/cfg"; export CLAUDE_CONFIG_DIR
STATE="$CLAUDE_CONFIG_DIR/cache/findings-state.json"; CLOG="$CLAUDE_CONFIG_DIR/cache/checks.log"

G="$TMP/github.git"; S="$TMP/seed"; TMPDIR="$TMP/tmp"; export TMPDIR; mkdir -p "$TMPDIR"
git init -q --bare "$G"; git -C "$G" symbolic-ref HEAD refs/heads/main   # whatever init.defaultBranch says
mkdir -p "$S/bin"
cat > "$S/bin/lint-findings.sh" <<'FAKE'
#!/bin/sh
printf '%s %s %s\n' "$1" "${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-}}" "${HARBOR_LINT_FINDINGS_REPO:-${HARBOR_FINDINGS_REPO:-}}" >> "$CALLS"
env | grep -E '^(HARBOR_TEST_PLANTED|GIT_TRACE|https_proxy)=' >> "$CALLS.env" || :
case "$1" in
  reconcile) printf 'findings: reconciled — examined 1 rules\n'; [ -z "${FAKE_NEW:-}" ] || printf '  new (first reconcile):      lint/X1\n'; exit "${FAKE_RC_RECONCILE:-0}" ;;
  heal)      printf 'findings heal: dry\n'; exit "${FAKE_RC_HEAL:-0}" ;;
esac
FAKE
git -C "$S" init -q; git -C "$S" -c user.email=t@t -c user.name=t add -A
git -C "$S" -c user.email=t@t -c user.name=t commit -qm main; git -C "$S" push -q "$G" HEAD:main
# An attacker's repo: same layout, a lint-findings.sh that only leaves a mark.
E="$TMP/evil.git"; ES="$TMP/evil-seed"; git init -q --bare "$E"; git -C "$E" symbolic-ref HEAD refs/heads/main
mkdir -p "$ES/bin"; printf '#!/bin/sh\ntouch "$EVIL"\n' > "$ES/bin/lint-findings.sh"
git -C "$ES" init -q; git -C "$ES" -c user.email=t@t -c user.name=t add -A
git -C "$ES" -c user.email=t@t -c user.name=t commit -qm evil; git -C "$ES" push -q "$E" HEAD:main
t_section "the fixture is what the cases below assume"
t_eq "main has the recording lint-findings.sh" yes "$(git -C "$G" show main:bin/lint-findings.sh | grep -q CALLS && echo yes || echo no)"
MAIN="$(git -C "$G" rev-parse main)"; MAIN7="$(printf '%.7s' "$MAIN")"
run() { HARBOR_LINT_FINDINGS_URL="$G" HARBOR_LINT_FINDINGS_REPO=o/r sh "$R" --overrides 2>&1; }
wts() { find "$TMPDIR" -maxdepth 1 -name 'findings-run.*' | grep -c .; }

t_section "a clean run reconciles, then heals, main as the remote has it, and stamps ok"
: > "$CALLS"; run > /dev/null; _rc=$?
t_eq "exit 0" 0 "$_rc"
t_eq "reconcile then heal" "reconcile heal" "$(cut -d' ' -f1 "$CALLS" | tr '\n' ' ' | sed 's/ $//')"
t_eq "against the store it was given" "o/r o/r" "$(cut -d' ' -f3 "$CALLS" | tr '\n' ' ' | sed 's/ $//')"
t_has "in a fresh clone under its own temp dir" "$(cut -d' ' -f2 "$CALLS")" "$TMPDIR/findings-run."
t_eq "the receipt says ok, at main" "ok $MAIN7" "$(jq -r '"\(.status) \(.sha)"' "$STATE")"
t_has "and is stamped" "$(jq -r .ran_at "$STATE")" "T"
t_eq "the clone is gone" 0 "$(wts)"
t_eq "a run that changed nothing writes no checks.log line" no "$([ -s "$CLOG" ] && echo yes || echo no)"

t_section "a run that changed something writes one checks.log line"
FAKE_NEW=1 run > /dev/null
t_eq "one line" 1 "$(grep -c '^\[check:lint.findings\]' "$CLOG")"
t_has "naming main" "$(cat "$CLOG")" "ok at $MAIN7"

t_section "review #895: a session-written global git config cannot redirect the fetch"
printf '[url "%s"]\n\tinsteadOf = %s\n' "$E" "$G" > "$TMP/trap.gitconfig"
t_eq "positive control: that config does redirect a plain clone" yes \
  "$(GIT_CONFIG_GLOBAL="$TMP/trap.gitconfig" git clone -q "$G" "$TMP/probe" 2>/dev/null; [ -f "$TMP/probe/bin/lint-findings.sh" ] && grep -q EVIL "$TMP/probe/bin/lint-findings.sh" && echo yes || echo no)"
: > "$CALLS"; GIT_CONFIG_GLOBAL="$TMP/trap.gitconfig" run > /dev/null
t_eq "the attacker's script never ran" no "$([ -f "$EVIL" ] && echo yes || echo no)"
t_eq "main's ran, twice" 2 "$(grep -c . "$CALLS")"

t_section "review #895: a hooksPath in a session-written global config cannot run a hook"
mkdir -p "$TMP/hooks"; printf '#!/bin/sh\ntouch "$EVIL.hook"\n' > "$TMP/hooks/post-checkout"; chmod +x "$TMP/hooks/post-checkout"
printf '[core]\n\thooksPath = %s\n' "$TMP/hooks" > "$TMP/hooks.gitconfig"
t_eq "positive control: that config does run the hook on a plain clone" yes \
  "$(GIT_CONFIG_GLOBAL="$TMP/hooks.gitconfig" git clone -q "$G" "$TMP/probe2" 2>/dev/null; [ -f "$EVIL.hook" ] && echo yes || echo no)"
rm -f "$EVIL.hook"
: > "$CALLS"; GIT_CONFIG_GLOBAL="$TMP/hooks.gitconfig" run > /dev/null
t_eq "the hook never ran" no "$([ -f "$EVIL.hook" ] && echo yes || echo no)"
t_eq "main's ran, twice" 2 "$(grep -c . "$CALLS")"

t_section "review #895: a planted symlink in the cache is never written through"
printf 'protected\n' > "$TMP/protected"
rm -f "$STATE"; ln -s "$TMP/protected" "$STATE"   # the receipt's own name, which is what a write would follow
mv -f "$CLOG" "$TMP/clog.real"; ln -s "$TMP/protected" "$CLOG"
FAKE_NEW=1 run > /dev/null
t_eq "the protected file is untouched" protected "$(cat "$TMP/protected")"
t_eq "the receipt is a plain file again" "file ok" "$([ -L "$STATE" ] && echo link || echo file) $(jq -r .status "$STATE")"
rm -f "$CLOG"; mv -f "$TMP/clog.real" "$CLOG"

t_section "review #895: an inherited GIT_INDEX_FILE does not reach another repo's index"
O="$TMP/other"; mkdir -p "$O"; git -C "$O" init -q; printf 'x\n' > "$O/f"; git -C "$O" add f
_before="$(cksum < "$O/.git/index")"
GIT_INDEX_FILE="$O/.git/index" run > /dev/null
t_eq "the other repo's index is unchanged" "$_before" "$(cksum < "$O/.git/index")"
t_eq "and main still ran" ok "$(jq -r .status "$STATE")"

t_section "review #895: without --overrides the environment cannot pick the repo or the config dir"
# HOME points at a sandbox, so the pinned URL's clone is what is attempted and the receipt lands there
# A stub git that records its arguments and refuses: the pinned URL is real, and this case must never
# reach the network or run the real main's lint-findings.sh.
mkdir -p "$TMP/home" "$TMP/stubgit"; : > "$CALLS"; : > "$TMP/git.args"
# (an origin read is logged and then answered by the real git: repo_slug asks it for a checkout's origin, the clone never gets there)
# (repo_slug runs git under `env -i`, so the real git's path is baked into the stub, not passed in the environment)
REALGIT="$(command -v git)"
printf '#!/bin/sh
printf "%%s\n" "$*" >> "%s"
case "$*" in *"--get remote.origin.url") exec "%s" "$@" ;; esac
echo "fatal: stub git" >&2
exit 128
' "$TMP/git.args" "$REALGIT" > "$TMP/stubgit/git"
chmod +x "$TMP/stubgit/git"
# installed the way runtime-install lays it out: <config>/bin/lint-findings-run.sh beside library-log.sh and the pin repo-slug.txt
# (harbor#1149), a name no tree spells: the pin here is not harbor's own, so a literal in the script could not pass.
mkdir -p "$TMP/home/.claude/bin"; cp "$R" "$T_ROOT/bin/library-log.sh" "$TMP/home/.claude/bin/"
printf '# pin\nacme/pinned\n' > "$TMP/home/.claude/bin/repo-slug.txt"
# the registered checkout as a session could leave it: its origin and its own pin both redirected to another repo
mkdir -p "$TMP/home/port/harbor/contracts"; git -C "$TMP/home/port/harbor" init -q
git -C "$TMP/home/port/harbor" remote add origin https://github.com/evil/harbor.git; printf 'evil/harbor\n' > "$TMP/home/port/harbor/contracts/repo-slug.txt"
OUT="$(PATH="$TMP/stubgit:$PATH" HOME="$TMP/home" HARBOR_LINT_FINDINGS_URL="$E" CLAUDE_CONFIG_DIR="$TMP/elsewhere" \
  sh "$TMP/home/.claude/bin/lint-findings-run.sh" 2>&1)"
t_eq "the attacker's repo was never run" no "$([ -f "$EVIL" ] && echo yes || echo no)"
t_has "the clone asked for the URL the install pins" "$(cat "$TMP/git.args")" "https://github.com/acme/pinned.git"
t_hasnt "and not the overridden one" "$(cat "$TMP/git.args")" "$E"
t_hasnt "nor the registered checkout's origin" "$(cat "$TMP/git.args")" "evil"
t_hasnt "git was never asked for an origin: an install reads only its pin" "$(cat "$TMP/git.args")" "remote.origin.url"
t_eq "the receipt is in the config dir it is installed in, not the overridden one" "refused no" \
  "$(jq -r .status "$TMP/home/.claude/cache/findings-state.json") $([ -e "$TMP/elsewhere" ] && echo yes || echo no)"
# an install with no pin names no repository: it fetches nothing and says so in its receipt
rm -f "$TMP/home/.claude/bin/repo-slug.txt" "$TMP/home/.claude/cache/findings-state.json"; : > "$TMP/git.args"
OUT="$(PATH="$TMP/stubgit:$PATH" HOME="$TMP/home" sh "$TMP/home/.claude/bin/lint-findings-run.sh" 2>&1)"; _rc=$?
t_eq "an install with no repo-slug.txt exits 1" 1 "$_rc"
t_has "and names why" "$OUT" "names no repository"
t_eq "and fetched nothing" "" "$(cat "$TMP/git.args")"
t_eq "the receipt says refused" refused "$(jq -r .status "$TMP/home/.claude/cache/findings-state.json")"
# run from a checkout, it names that checkout's own origin: the pin is only the fallback (a copy under another owner needs no edit)
mkdir -p "$TMP/tree/bin" "$TMP/tree/contracts" "$TMP/treecfg"; cp "$R" "$T_ROOT/bin/library-log.sh" "$TMP/tree/bin/"
printf 'acme/pinned\n' > "$TMP/tree/contracts/repo-slug.txt"; git -C "$TMP/tree" init -q
git -C "$TMP/tree" remote add origin https://github.com/other/fork.git; : > "$TMP/git.args"
OUT="$(PATH="$TMP/stubgit:$PATH" HOME="$TMP/home" sh "$TMP/tree/bin/lint-findings-run.sh" 2>&1)"
t_has "from a checkout the clone asks for that checkout's origin" "$(cat "$TMP/git.args")" "https://github.com/other/fork.git"
t_hasnt "and not the pin" "$(cat "$TMP/git.args")" "acme/pinned"

t_section "review #895: a hard-linked checks.log is never appended to"
printf 'protected\n' > "$TMP/protected2"; rm -f "$CLOG"; ln "$TMP/protected2" "$CLOG"
FAKE_NEW=1 run > /dev/null
t_eq "the linked file is untouched" protected "$(cat "$TMP/protected2")"
rm -f "$CLOG"

t_section "review #895: a receipt that cannot be installed fails the run"
rm -f "$STATE"; mkdir -p "$STATE"
OUT="$(run)"; _rc=$?
t_eq "exit 1" 1 "$_rc"
t_has "and says why" "$OUT" "no receipt could be installed at $STATE"
rmdir "$STATE"

t_section "an inherited HARBOR_*, proxy or trace variable never reaches main's lint-findings.sh"
: > "$CALLS.env"
HARBOR_TEST_PLANTED=1 GIT_TRACE="$TMP/trace" https_proxy=http://127.0.0.1:9 run > /dev/null
t_eq "none of the three arrived" "" "$(cat "$CALLS.env")"
t_eq "and git wrote no trace" no "$([ -e "$TMP/trace" ] && echo yes || echo no)"
t_eq "positive control: main still ran" ok "$(jq -r .status "$STATE")"

t_section "a failed reconcile skips heal and fails the run"
: > "$CALLS"; OUT="$(FAKE_RC_RECONCILE=1 run)"; _rc=$?
t_eq "exit 1" 1 "$_rc"
t_eq "heal did not run" "reconcile" "$(cut -d' ' -f1 "$CALLS" | tr '\n' ' ' | sed 's/ $//')"
t_eq "the receipt says failed" "failed reconcile exited 1; heal not run" "$(jq -r '"\(.status) \(.note)"' "$STATE")"
t_has "checks.log carries the failure" "$(tail -1 "$CLOG")" "failed at $MAIN7 — reconcile exited 1"
t_eq "the clone is gone" 0 "$(wts)"

t_section "a failed heal fails the run"
OUT="$(FAKE_RC_HEAL=1 run)"; _rc=$?
t_eq "exit 1" 1 "$_rc"
t_eq "the receipt says so" "failed heal exited 1" "$(jq -r '"\(.status) \(.note)"' "$STATE")"

t_section "a fetch that fails is refused: nothing runs, and the receipt says so"
: > "$CALLS"; OUT="$(HARBOR_LINT_FINDINGS_URL="$TMP/nowhere.git" HARBOR_LINT_FINDINGS_REPO=o/r sh "$R" --overrides 2>&1)"; _rc=$?
t_eq "exit 1" 1 "$_rc"
t_eq "nothing ran" "" "$(cat "$CALLS")"
t_eq "refused" refused "$(jq -r .status "$STATE")"
t_has "naming the URL" "$OUT" "could not fetch main from $TMP/nowhere.git"

t_section "the schedule runs the installed copy, and the installer ships it"
# The plist is a template (harbor#630): what launchd runs is what it renders to, so that is what is read.
FPL="$(sh "$T_ROOT/bin/deploy-launchd-render.sh" "$T_ROOT/launchd/com.harbor.lint.findings.plist")"
t_has "the plist names ~/.claude/bin/lint-findings-run.sh" "$FPL" "$HOME/.claude/bin/lint-findings-run.sh</string>"
t_hasnt "its PATH searches no ~/.local/bin, where a session can Write a git" "$(printf '%s\n' "$FPL" | grep -A0 '<key>PATH</key>')" ".local/bin"
t_has "positive control: the PATH line was read" "$(printf '%s\n' "$FPL" | grep -A0 '<key>PATH</key>')" "/usr/bin:/bin"
t_has "runtime-install's payload carries it" "$(grep '^FILES=' "$T_ROOT/bin/deploy-runtime-install.sh")" " lint-findings-run.sh "

t_done
