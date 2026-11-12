#!/usr/bin/env sh
# git-safe.test.sh (harbor#1278): the hooks and tools that run git on a repo the agent can write run no program that repo names.
# Nine plants (clean, process, smudge, textconv, diff.external, include.path -> filter, fsmonitor, hooksPath, pager), each carrying a marker
# file, are driven through the hardened paths: the admission-destroy snapshot (the executing path), pack.sh's dirty check (the other one),
# and gs_env over every read verb the hooks use. Section 3 swaps the library for plain git and watches the executing paths go red.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/scope/pack/fixture.sh"
export GIT_AUTHOR_NAME=m GIT_AUTHOR_EMAIL=m@example.invalid GIT_COMMITTER_NAME=m GIT_COMMITTER_EMAIL=m@example.invalid
ATK="$T_TMP/atk"; MK="$ATK/mk"; mkdir -p "$MK" "$ATK/hooks"
printf '#!/bin/sh\ntouch "%s/$1"\nshift\nexec "$@"\n' "$MK" > "$ATK/mark.sh"; chmod +x "$ATK/mark.sh"
printf '#!/bin/sh\ntouch "%s/hooksPath"\n' "$MK" > "$ATK/hooks/pre-commit"
for _h in post-index-change reference-transaction post-commit; do cp "$ATK/hooks/pre-commit" "$ATK/hooks/$_h"; done; chmod +x "$ATK/hooks/"*
printf 'import pty, sys\npty.spawn(sys.argv[1:])\n' > "$ATK/spawn_tty.py"   # git pages only on a terminal
LIB="$T_ROOT/bin/library-git-safe.sh"
GI="-c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c init.defaultBranch=main"

# A copy of the library that is plain git: what the hooks did before. The red arms run on it.
BYP="$T_TMP/bypass"; mkdir -p "$BYP"
printf 'gs_env() { git "$@"; }\ngs_open_at() { GS_DIR="$2"; GS_TREE="$1"; return 0; }\ngs_open() { GS_DIR="$1/.git"; GS_TREE="$1"; return 0; }\ngs_open_in() { GS_TREE="$(git -C "$1" rev-parse --show-toplevel)"; GS_DIR="$(git -C "$1" rev-parse --absolute-git-dir)"; GS_PREFIX="$(git -C "$1" rev-parse --show-prefix)"; return 0; }\ngs_track() { return 0; }\ngs_git() { git -C "$GS_TREE" "$@"; }\n' > "$BYP/library-git-safe.sh"

plant() { # <attack> <repo>
  _p="$2"; _c() { git -C "$_p" config --local "$@"; }
  _a() { printf '* filter=x diff=x\n' > "$_p/.gitattributes"; }
  case "$1" in
    clean) _a; _c filter.x.clean "$ATK/mark.sh clean cat" ;;
    process) _a; _c filter.x.process "$ATK/mark.sh process false" ;;
    smudge) _a; _c filter.x.smudge "$ATK/mark.sh smudge cat" ;;
    textconv) _a; _c diff.x.textconv "$ATK/mark.sh textconv cat" ;;
    external) _c diff.external "$ATK/mark.sh external true" ;;
    include) _a; printf '[filter "x"]\n\tclean = %s/mark.sh include cat\n' "$ATK" > "$ATK/inc.cfg"; _c include.path "$ATK/inc.cfg" ;;
    fsmonitor) _c core.fsmonitor "$ATK/mark.sh fsmonitor true" ;;
    hooksPath) _c core.hooksPath "$ATK/hooks" ;;
    pager) _c core.pager "$ATK/mark.sh pager cat" ;;
  esac
}
ATTACKS="clean process smudge textconv external include fsmonitor hooksPath pager"
EXEC="clean process include fsmonitor"   # the plants a plain `git add -A` / `git status` reaches
seen() { [ -e "$MK/$1" ] && echo yes || echo no; }
repo() { rm -rf "$1"; mkdir -p "$1"; git $GI -C "$1" init -q; printf 'x\n' > "$1/app.py"; printf 'y\n' > "$1/README.md"; git $GI -C "$1" add -A; git $GI -C "$1" commit -qm base; }

# The guard on a discarding command in <repo>, with the library <dir> beside it; prints nothing, leaves a snapshot ref or none.
GD="$T_TMP/guard"; mkdir -p "$GD"
for _f in admission-destroy.sh library-admission.sh library-log.sh admission-normalize.awk; do cp "$T_ROOT/bin/$_f" "$GD/"; done
cp "$LIB" "$GD/library-git-safe.sh"
GB="$T_TMP/guard-bypass"; mkdir -p "$GB"; cp "$GD"/* "$GB/"; cp "$BYP/library-git-safe.sh" "$GB/library-git-safe.sh"
guard() { # <guard dir> <cwd> <command>
  jq -n --arg c "$3" --arg d "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | sh "$1/admission-destroy.sh" > /dev/null 2>&1 || :; }
nsnap() { git -C "$1" for-each-ref refs/snapshots/ | wc -l | tr -d ' '; }

t_section "1 - the admission-destroy snapshot runs nothing the repo names, and is still a faithful snapshot"
for A in $ATTACKS; do
  R="$T_TMP/r-$A"; repo "$R"; plant "$A" "$R"; printf 'two\n' > "$R/app.py"; printf 'new\n' > "$R/u.txt"; rm -f "$MK/$A"
  guard "$GD" "$R" "git reset --hard"
  t_eq "$A: the guard ran no program" no "$(seen "$A")"
  t_eq "$A: one snapshot was taken" 1 "$(nsnap "$R")"
  S="$(git -C "$R" for-each-ref --count=1 --format='%(refname)' refs/snapshots/)"
  t_eq "$A: it holds the edited file as it sat on disk" two "$(git -C "$R" cat-file -p "$S:app.py" 2>/dev/null)"
  t_eq "$A: and the untracked one" new "$(git -C "$R" cat-file -p "$S:u.txt" 2>/dev/null)"
done
# A clean filter must not rewrite what is stored: the snapshot is the bytes, never the filter's output.
R="$T_TMP/r-bytes"; repo "$R"; printf '*.py filter=x\n' > "$R/.gitattributes"; git -C "$R" config filter.x.clean 'tr a-z A-Z'
printf 'lower\n' > "$R/app.py"; guard "$GD" "$R" "git reset --hard"
S="$(git -C "$R" for-each-ref --count=1 --format='%(refname)' refs/snapshots/)"
t_eq "a configured clean filter did not rewrite the stored bytes" lower "$(git -C "$R" cat-file -p "$S:app.py" 2>/dev/null)"
R="$T_TMP/r-wt"; repo "$R"; git $GI -C "$R" worktree add -q -b wt "$T_TMP/wt-linked" 2>/dev/null; plant clean "$R"; plant fsmonitor "$R"
printf 'two\n' > "$T_TMP/wt-linked/app.py"; rm -f "$MK/clean" "$MK/fsmonitor"; _ib="$(cksum < "$R/.git/index")"
guard "$GD" "$T_TMP/wt-linked" "git reset --hard"
t_eq "a linked worktree: the clean filter did not run" no "$(seen clean)"
t_eq "a linked worktree: fsmonitor did not run" no "$(seen fsmonitor)"
t_eq "a linked worktree: snapshot taken" 1 "$(nsnap "$R")"
S="$(git -C "$R" for-each-ref --count=1 --format='%(refname)' refs/snapshots/)"
t_eq "a linked worktree: it holds the edit" two "$(git -C "$R" cat-file -p "$S:app.py" 2>/dev/null)"
t_eq "the main repo's own index was not written" "$_ib" "$(cksum < "$R/.git/index")"

t_section "2 - pack.sh's dirty check runs nothing the pack repo names, and still refuses a real change"
for A in clean process include fsmonitor textconv external hooksPath pager smudge; do
  _i="g$(printf '%s' "$A" | tr 'A-Z' 'a-z')"; mkpack "$_i"; listed "\"$_i\""; plant "$A" "$PW/$_i"; rm -f "$MK/$A"
  TG="$T_TMP/tg-$A"; rm -rf "$TG"; mkdir -p "$TG/bin" "$TG/skills"
  _o="$(pk install "$_i" --dir "$TG" 2>&1 < /dev/null)"; _rc=$?
  t_eq "$A: nothing ran" no "$(seen "$A")"
  t_eq "$A: a clean pack is not called dirty" 0 "$([ "$_rc" -eq 0 ] && echo 0 || echo "$_rc: $_o")"
  # A filter runs only when git must hash a file its stat cannot clear: a same-size edit, as the agent's real attack makes: the check must refuse it and still run nothing.
  printf '#!/bin/sh\necho demX\n' > "$PW/$_i/harbor-pack/bin/demo-tool"; rm -f "$MK/$A"
  _o="$(pk install "$_i" --dir "$TG" 2>&1 < /dev/null)"
  t_eq "$A: an edited file is refused as dirty" yes "$(printf '%s' "$_o" | grep -q dirty && echo yes || echo no)"
  t_eq "$A: and the check on it ran nothing" no "$(seen "$A")"
done
TD="$T_TMP/tg-d"; mkdir -p "$TD"
mkpack gdirty; listed '"gdirty"'; plant clean "$PW/gdirty"; printf 'extra\n' >> "$PW/gdirty/harbor-pack/bin/demo-tool"
t_has "a real edit is still refused as dirty, filter or no" "$(pk install gdirty --dir "$TD" 2>&1 < /dev/null)" "dirty"
mkpack guntr; listed '"guntr"'; printf 'n\n' > "$PW/guntr/harbor-pack/new.txt"
t_has "an untracked file is still refused" "$(pk install guntr --dir "$TD" 2>&1 < /dev/null)" "dirty"

t_section "3 - gs_env, the read calls of govern-hook, hub, hub-sync, deploy-install-lib and pack, runs nothing either"
reads() { # <repo> — each read verb the tools use, under a pty so a pager would show
  python3 "$ATK/spawn_tty.py" sh -c '. "$1"; r="$2"
    gs_env -C "$r" rev-parse --show-toplevel --git-common-dir --abbrev-ref HEAD
    gs_env -C "$r" rev-parse --verify -q "HEAD^{commit}"; gs_env -C "$r" cat-file -e HEAD; gs_env -C "$r" cat-file -s HEAD:app.py
    gs_env -C "$r" show --no-textconv HEAD:app.py; gs_env -C "$r" ls-tree -r HEAD; gs_env -C "$r" ls-files -s
    gs_env -C "$r" for-each-ref --format="%(refname)"; gs_env -C "$r" rev-list --count HEAD; gs_env -C "$r" worktree list --porcelain
    gs_env -C "$r" config --get remote.origin.url; gs_env -C "$r" remote get-url origin; gs_env -C "$r" log --format= --raw -- app.py
    gs_env -C "$r" hash-object --no-filters -- "$r/app.py"' sh "$LIB" "$1" > /dev/null 2>&1 < /dev/null || :; }
for A in $ATTACKS; do
  R="$T_TMP/rr-$A"; repo "$R"; git -C "$R" remote add origin https://example.invalid/x.git; plant "$A" "$R"; printf 'z\n' > "$R/app.py"; rm -f "$MK/$A"
  reads "$R"
  t_eq "$A: no read verb ran it" no "$(seen "$A")"
done
t_eq "gs_open_at refuses a git dir that is not one" 1 "$(sh -c '. "$1"; gs_open_at /x /nowhere /nowhere "$2" && echo 0 || echo 1' sh "$LIB" "$T_TMP")"

t_section "4 - red: the library swapped for plain git, the executing paths run the program"
for A in $EXEC; do
  R="$T_TMP/rb-$A"; repo "$R"; plant "$A" "$R"; printf 'two\n' > "$R/app.py"; rm -f "$MK/$A"
  guard "$GB" "$R" "git reset --hard"
  t_eq "$A: the snapshot on plain git runs the planted program" yes "$(seen "$A")"
done
# pack.sh on a copy whose library is plain git: the dirty check runs the filter.
FB="$T_TMP/farm"; mkdir -p "$FB/bin"
for _d in contracts standards docs; do [ ! -e "$T_ROOT/$_d" ] || ln -s "$T_ROOT/$_d" "$FB/$_d"; done
for _f in "$T_ROOT"/bin/*; do ln -s "$_f" "$FB/bin/${_f##*/}"; done
rm -f "$FB/bin/library-git-safe.sh"; cp "$BYP/library-git-safe.sh" "$FB/bin/library-git-safe.sh"
pkb() { env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$FB/bin/pack.sh" "$@"; }
for A in clean process include fsmonitor; do
  mkpack "r$A"; listed "\"r$A\""; plant "$A" "$PW/r$A"; printf '#!/bin/sh\necho demX\n' > "$PW/r$A/harbor-pack/bin/demo-tool"; rm -f "$MK/$A"; mkdir -p "$T_TMP/tg-r$A"
  pkb install "r$A" --dir "$T_TMP/tg-r$A" > /dev/null 2>&1 < /dev/null || :
  t_eq "$A: pack.sh on plain git runs the planted program" yes "$(seen "$A")"
done

t_section "5 - the Stop hook session-state.sh runs git status in the session's cwd: nothing the repo names runs"
SS="$T_TMP/ss"; mkdir -p "$SS/bin" "$SS/st"; cp "$T_ROOT/hooks/session-state/session-state.sh" "$T_ROOT/bin/library-fs.sh" "$T_ROOT/bin/library-log.sh" "$SS/bin/"
cp "$LIB" "$SS/bin/library-git-safe.sh"
SB="$T_TMP/ss-bypass"; mkdir -p "$SB"; cp "$SS/bin/"* "$SB/"; cp "$BYP/library-git-safe.sh" "$SB/library-git-safe.sh"
cat >> "$SB/library-git-safe.sh" <<'BYPASS'
gs_track() { return 0; }
gs_open_in() { GS_TREE="$(git -C "$1" rev-parse --show-toplevel)"; GS_DIR="$(git -C "$1" rev-parse --absolute-git-dir)"; return 0; }
BYPASS
stop_hook() { # <bin dir> <cwd>
  printf '{"session_id":"ss1","cwd":"%s","transcript_path":"/nonexistent"}' "$2" | env -i PATH=/usr/bin:/bin:/opt/homebrew/bin HOME="$T_TMP" HARBOR_STATUS_DIR="$SS/st" sh "$1/session-state.sh" > /dev/null 2>&1 || :; }
for A in $ATTACKS; do
  R="$T_TMP/ssr-$A"; repo "$R"; plant "$A" "$R"; printf 'z\n' > "$R/app.py"; rm -f "$MK/$A"
  stop_hook "$SS/bin" "$R"
  t_eq "$A: the Stop hook ran no program" no "$(seen "$A")"
done
t_eq "the hook still reads the tree: one changed file is counted" 1 "$(jq -r '.dirty // empty' "$SS/st/sessions/ss1.json" 2>/dev/null)"
for A in clean process include fsmonitor; do
  R="$T_TMP/ssb-$A"; repo "$R"; plant "$A" "$R"; printf 'z\n' > "$R/app.py"; rm -f "$MK/$A"
  stop_hook "$SB" "$R"
  t_eq "$A: red, session-state on plain git runs the planted program" yes "$(seen "$A")"
done
t_done
