#!/usr/bin/env sh
# worktree.sh deletes working directories, so every refusal is asserted by what survived on disk,
# never by the message (CI-4, harbor#150, #143, #163, #213). A throwaway repo, a `ps` stub and a
# fixture session registry; context-peers.sh itself is real, so that seam is exercised.
. "$(dirname "$0")/../../lib/core.sh"; t_init
WT="$T_ROOT/bin/worktree.sh"
P="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"  # git prints resolved paths; /var is a symlink here
mkdir -p "$P/stub" "$P/sessions" "$P/peers" "$P/cfg"
g() { _d="$1"; shift; git -C "$_d" -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }
yn() { if "$@"; then echo yes; else echo no; fi; }
REPO="$P/repo"; mkdir -p "$REPO"; git init -q "$REPO"; git -C "$REPO" symbolic-ref HEAD refs/heads/main
: > "$REPO/seed"; g "$REPO" add seed; g "$REPO" commit -qm seed
SEED="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" update-ref refs/remotes/origin/main "$SEED"  # a local stand-in; nothing is fetched
mkwt() { g "$REPO" worktree add -q -b "$2" "$P/$1" "$SEED" >/dev/null 2>&1; }  # <name> <branch>
mkwt clean b-clean; mkwt dirty b-dirty; mkwt ahead b-ahead; mkwt held b-held; mkwt gone b-gone
: > "$P/dirty/untracked"
: > "$P/ahead/f"; g "$P/ahead" add f; g "$P/ahead" commit -qm ahead
rm -rf "$P/gone"  # the orphan shape

# A live session in $P/held. The pid is this suite's own: is_live starts with `kill -0`, so a
# made-up pid fails before the ps stub is asked, and "nothing is held" would pass for the wrong reason.
NOW="$(date +%s)"
PS_LOCAL="$(date -r "$NOW" '+%a %b %e %T %Y' 2>/dev/null || date -d "@$NOW" '+%a %b %e %T %Y')"
REC_UTC="$(date -u -r "$NOW" '+%a %b %e %T %Y' 2>/dev/null || date -u -d "@$NOW" '+%a %b %e %T %Y')"
LIVE_PID=$$
cat > "$P/stub/ps" <<STUB
#!/bin/sh
for a in "\$@"; do case "\$a" in $LIVE_PID) echo "$PS_LOCAL"; exit 0 ;; esac; done
exit 1
STUB
chmod +x "$P/stub/ps"
printf '{"pid":%s,"sessionId":"sid-held","cwd":"%s","procStart":"%s","startedAt":%s,"status":"active","name":"held","kind":"interactive"}\n' \
  "$LIVE_PID" "$P/held" "$REC_UTC" "${NOW}000" > "$P/sessions/held.json"
wtb() { # <base ref> <args…>
  _wb="$1"; shift
  PATH="$P/stub:$PATH" PORT_ROOT="$P/port" HARBOR_SCOPE_ROOT="$REPO" HARBOR_CI_BASE="$_wb" CLAUDE_CONFIG_DIR="$P/cfg" \
    HARBOR_SESSION_REGISTRY_DIR="$P/sessions" HARBOR_CONTEXT_PEERS_DIR="$P/peers" sh "$WT" "$@" 2>&1
}
wt() { wtb origin/main "$@"; }
vof() { wt list | awk -v p="$P/$1" '$2 == p { print $1; exit }'; }        # <name> → verdict
vofb() { wtb "$1" list | awk -v p="$P/$2" '$2 == p { print $1; exit }'; }  # <base> <name>
there() { yn [ -d "$P/$1" ]; }

t_section "verdicts"
t_eq "a clean, merged, unheld worktree is collectable (or every refusal below is vacuous)" COLLECT "$(vof clean)"
t_eq "untracked content is kept" SKIP "$(vof dirty)"
t_eq "an unmerged branch is kept" SKIP "$(vof ahead)"
t_eq "a worktree a live session works in is kept" SKIP "$(vof held)"
t_eq "a worktree whose directory is gone is prunable" PRUNE "$(vof gone)"
t_eq "the main worktree is excluded" SKIP "$(wt list | awk -v p="$REPO" '$2 == p { print $1 }')"
t_has "the held verdict names the live session" "$(wt list)" 'live session'

t_section "an unknown live-session list does not read as unheld"
# The stub fails only worktree.sh's filter (context-peers.sh has no `type=="array"`), so the
# failed extraction is reached; a jq that always fails breaks fleet-sessions first.
REALJQ="$(command -v jq 2>/dev/null || echo /usr/bin/jq)"
cat > "$P/stub/jq" <<STUB
#!/bin/sh
for a in "\$@"; do case "\$a" in *'type=="array"'*) exit 1 ;; esac; done
exec "$REALJQ" "\$@"
STUB
chmod +x "$P/stub/jq"
t_eq "with the list unavailable, nothing existing is collectable" SKIP "$(vof clean)"
t_eq "gc would not remove an existing worktree" 0 "$(wt gc | grep -c "would remove  *$P/clean")"
t_has "gc says why it collected nothing" "$(wt gc)" 'live-session list was unavailable'
t_eq "a directory that does not exist stays prunable" PRUNE "$(vof gone)"
rm -f "$P/stub/jq"
t_eq "the jq stub is gone again" COLLECT "$(vof clean)"

t_section "gc is a dry run until --apply"
OUT="$(wt gc)"
t_has "gc describes what it would remove" "$OUT" 'would remove'
t_has "gc says it is a dry run" "$OUT" 'dry run'
t_eq "the dry run deleted nothing" yes "$(there clean)"
for w in dirty ahead held; do t_eq "the dry run kept $w" yes "$(there "$w")"; done
wt gc --apply >/dev/null
t_eq "--apply removes the collectable worktree" no "$(there clean)"
t_eq "--apply keeps the dirty worktree" yes "$(there dirty)"
t_eq "--apply keeps the unmerged worktree" yes "$(there ahead)"
t_eq "--apply keeps the held worktree" yes "$(there held)"
t_eq "--apply leaves the main worktree" yes "$(yn [ -d "$REPO/.git" ])"
t_eq "the orphaned record is pruned" 0 "$(git -C "$REPO" worktree list --porcelain | grep -cx "worktree $P/gone")"
t_exit "the collected worktree's branch is no longer pinned" 0 git -C "$REPO" branch -q -D b-clean

t_section "a worktree on the base branch is never collected (harbor#163)"
# Two worktrees on one commit, differing only in branch name, with a commit of their own so the
# gc --apply above (base origin/main) could not reach them.
mkwt basewt b-base
: > "$P/basewt/tip"; g "$P/basewt" add tip; g "$P/basewt" commit -qm base-tip
BASETIP="$(git -C "$P/basewt" rev-parse HEAD)"
git -C "$REPO" branch -q b-peer "$BASETIP"
g "$REPO" worktree add -q "$P/peerwt" b-peer >/dev/null 2>&1
git -C "$REPO" update-ref refs/remotes/origin/b-base "$BASETIP"
t_eq "the base branch's worktree is kept" SKIP "$(vofb origin/b-base basewt)"
t_has "…and says it is the base branch" "$(wtb origin/b-base list)" 'is the base branch'
t_eq "a sibling on the same commit is collectable (the discriminator)" COLLECT "$(vofb origin/b-base peerwt)"
t_eq "under another base the branch is judged on mergedness" SKIP "$(vofb origin/main basewt)"
t_has "…and refused as unmerged, not as the base" "$(wtb origin/main list)" 'b-base is not merged'
wtb origin/b-base retire "$P/basewt" --force >/dev/null
t_eq "--force does not retire the base branch's worktree" yes "$(there basewt)"
t_has "…and says no flag overrides it" "$(wtb origin/b-base retire "$P/basewt" --force)" 'no flag overrides'
wtb origin/b-base gc --apply >/dev/null
t_eq "gc --apply keeps the base branch's worktree" yes "$(there basewt)"
t_eq "the same run collects the sibling" no "$(there peerwt)"

t_section "retire, and its refusals"
wt retire "$P/dirty" >/dev/null;         t_eq "retire keeps a dirty worktree" yes "$(there dirty)"
wt retire "$P/dirty" --force >/dev/null; t_eq "--force keeps a dirty worktree" yes "$(there dirty)"
t_has "…and says no flag overrides it" "$(wt retire "$P/dirty" --force)" 'no flag overrides'
wt retire "$P/held" --force >/dev/null;  t_eq "--force keeps a held worktree" yes "$(there held)"
wt retire "$P/ahead" >/dev/null;         t_eq "retire keeps an unmerged branch without --force" yes "$(there ahead)"
t_has "…and names the flag that accepts it" "$(wt retire "$P/ahead")" '--force'
wt retire "$P/ahead" --force >/dev/null; t_eq "--force accepts an unmerged branch" no "$(there ahead)"
t_exit "a path that is not a worktree of this repo" 1 wt retire "$P/not-a-worktree"
t_has "…is named as such" "$(wt retire "$P/not-a-worktree")" 'not a worktree of this repo'
# Probed through a worktree retire must refuse, so the spelling is all that varies (harbor#143).
for sp in "$P/dirty" "$P/dirty/" "$P/dirty/." "$P/dirty/../dirty"; do
  t_hasnt "retire resolves the spelling $sp" "$(wt retire "$sp")" 'not a worktree of this repo'
done
t_eq "the spelling probe removed nothing" yes "$(there dirty)"

t_section "new"
wt new feat/fresh >/dev/null
NW="port/.worktrees/repo/feat-fresh"   # harbor#1149: $PORT_ROOT/.worktrees/<repo>/<slug>
t_eq "new creates the worktree under PORT_ROOT/.worktrees/<repo>/" yes "$(there "$NW")"
t_eq "new leaves no sibling <repo>-wt-* behind" no "$(there repo-wt-feat-fresh)"
t_eq "new puts it on the branch asked for" feat/fresh "$(git -C "$P/$NW" rev-parse --abbrev-ref HEAD 2>/dev/null)"
t_eq "new branches off origin/main" "$SEED" "$(git -C "$P/$NW" rev-parse HEAD 2>/dev/null)"
t_eq "list shows the new-layout tree" yes "$(yn [ -n "$(vof "$NW")" ])"
t_exit "new refuses an existing branch" 1 wt new feat/fresh
for n in '../escape' '-rf' '/abs'; do t_exit "new refuses the hostile branch name $n" 2 wt new "$n"; done
t_eq "new wrote nothing outside the worktrees directory" no "$(yn [ -e "$P/escape" ])"
wt retire feat-fresh >/dev/null
t_eq "retire addresses a worktree by the slug new made" no "$(there "$NW")"

t_section "both layouts retire by bare name (harbor#1149)"
g "$REPO" worktree add -q -b b-legacy "$P/repo-wt-legacy" "$SEED" >/dev/null 2>&1
t_eq "a legacy sibling is listed" COLLECT "$(vof repo-wt-legacy)"
wt retire legacy >/dev/null
t_eq "a bare name retires the legacy sibling" no "$(there repo-wt-legacy)"

t_section "refusals hold in the new layout (harbor#1149)"
wt new feat/nd >/dev/null; wt new feat/nh >/dev/null; wt new feat/nc >/dev/null
ND="port/.worktrees/repo/feat-nd"; NH="port/.worktrees/repo/feat-nh"; NC="port/.worktrees/repo/feat-nc"
t_eq "premise: a clean new-layout tree is collectable" COLLECT "$(vof "$NC")"
: > "$P/$ND/untracked"
t_eq "a dirty new-layout tree is kept" SKIP "$(vof "$ND")"
wt retire "$P/$ND" --force >/dev/null; t_eq "--force keeps a dirty new-layout tree" yes "$(there "$ND")"
wt retire feat-nd >/dev/null;          t_eq "bare-name retire keeps a dirty new-layout tree" yes "$(there "$ND")"
printf '{"pid":%s,"sessionId":"sid-nh","cwd":"%s","procStart":"%s","startedAt":%s,"status":"active","name":"nh","kind":"interactive"}\n' \
  "$LIVE_PID" "$P/$NH" "$REC_UTC" "${NOW}000" > "$P/sessions/nh.json"
t_eq "a held new-layout tree is kept" SKIP "$(vof "$NH")"
wt retire feat-nh --force >/dev/null;  t_eq "--force keeps a held new-layout tree" yes "$(there "$NH")"
wt gc --apply >/dev/null
t_eq "gc --apply keeps the dirty new-layout tree" yes "$(there "$ND")"
t_eq "gc --apply keeps the held new-layout tree" yes "$(there "$NH")"
t_eq "gc --apply collects the clean new-layout tree" no "$(there "$NC")"
rm -f "$P/sessions/nh.json"; rm -f "$P/$ND/untracked"
wt retire feat-nd >/dev/null; wt retire feat-nh >/dev/null
t_eq "once clean and unheld they retire" nono "$(there "$ND")$(there "$NH")"

t_section "new links the parent's memory store (harbor#589)"
# The store is keyed by the session's cwd, so a worktree born without a route starts blind.
# HOME is pinned to the fixture dir so the registry row `~/repo` is the fixture repo; PORT_ROOT is
# pinned so a host value adds no directory to the sweep.
HK="$(printf '%s' "$P" | sed 's|/|-|g')"
mkdir -p "$P/cfg/projects/$HK/memory" "$P/mrrepo" "$P/priv/inject.d/box"   # the registry is the private layer's (harbor#1149)
printf 'note\n' > "$P/cfg/projects/$HK/memory/a.md"
printf 'repo\t~/repo\tw\n' > "$P/priv/inject.d/box/projects.tsv"
HOME="$P" PORT_ROOT="$P/port" HARBOR_SCOPE_PRIVATE="$P/priv" HARBOR_SCOPE_REPO="$P/mrrepo" wt new feat/mem >/dev/null
WK="$(printf '%s' "$P/port/.worktrees/repo/feat-mem" | sed 's|/|-|g')"
t_eq "the new worktree's memory route is a symlink" yes "$(yn [ -L "$P/cfg/projects/$WK/memory" ])"
t_eq "it resolves to a non-empty store (what a session there loads)" 1 "$(find "$P/cfg/projects/$WK/memory/" -maxdepth 1 -name '*.md' | grep -c .)"
wt retire feat-mem >/dev/null

t_section "a squash-merged branch retires without --force (harbor#213)"
g "$REPO" checkout -q -b b-squash "$SEED"
printf 'sq1\n' > "$REPO/sq"; g "$REPO" add sq; g "$REPO" commit -qm sq1
printf 'sq2\n' >> "$REPO/sq"; g "$REPO" commit -qam sq2
g "$REPO" checkout -q main; g "$REPO" merge -q --squash b-squash >/dev/null 2>&1; g "$REPO" commit -qm "squash: b-squash"
git -C "$REPO" update-ref refs/remotes/origin/main "$(git -C "$REPO" rev-parse main)"
t_eq "premise: the squash fixture holds 2+ commits (the case git cherry gets wrong)" yes \
  "$(yn [ "$(git -C "$REPO" rev-list --count "$(git -C "$REPO" merge-base origin/main b-squash)..b-squash")" -ge 2 ])"
t_exit "premise: the squash fixture is not an ancestor of origin/main" 1 git -C "$REPO" merge-base --is-ancestor b-squash origin/main
g "$REPO" worktree add -q "$P/sqwt" b-squash >/dev/null 2>&1
wt retire "$P/sqwt" >/dev/null
t_eq "retire accepts a squash-merged worktree without --force" no "$(there sqwt)"
g "$REPO" checkout -q -b b-notmerged origin/main
printf 'never-merged\n' > "$REPO/nm"; g "$REPO" add nm; g "$REPO" commit -qm nm
g "$REPO" checkout -q main
g "$REPO" worktree add -q "$P/nmwt" b-notmerged >/dev/null 2>&1
wt retire "$P/nmwt" >/dev/null
t_eq "retire keeps genuinely unmerged work" yes "$(there nmwt)"
t_has "…and says it is not merged" "$(wt retire "$P/nmwt")" 'not merged'
t_done
