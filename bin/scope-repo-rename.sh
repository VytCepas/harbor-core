#!/usr/bin/env sh
# scope-repo-rename.sh (harbor#966; `harbor repo rename`) - rename a registered repo on this box, its sessions and memory with it.
#
#   harbor repo rename <old> <new> [--live | --dir <config-dir>]           DRY RUN: every place <old> lives, what --apply does there
#   harbor repo rename <old> <new> --apply (--live | --dir <config-dir>)   do it (--force: although a process has its cwd inside)
#
# THE GITHUB RENAME IS NEVER RUN HERE: it needs the repo's admin, so it is printed as the operator's step, before --apply.
# THE PLACES, in order (PLACES below; each prints `  <place>: <state> - <detail>`; tests/scope/repo/rename.test.sh deletes each
# from a copy in turn, and that place's assertion alone goes red):
#   checkout   PORT_ROOT/<path>, moved when its last segment is the id; refused while a process has its cwd in it or a tree of it
#   worktrees  `git worktree list`: a tree under .worktrees/<old>/ moves to .worktrees/<new>/; every tree is then repaired
#   sessions   <config>/projects/<key>/ of the checkout, two levels of its subdirectories and its trees, moved to the new path's
#              key (the harness's key, memory-route.sh --key), so transcripts and the memory route follow; never merged
#   registry   the private layer's repos.tsv row: id, path, and the remote's last segment
#   projects   the project registry's row (regenerated when the file is generated)
#   rules      <private>/context-rules/<old>/
#   fleet      fleet.yaml lines naming the checkout
#   remote     the checkout's origin URL
#   shims      ~/.local/bin links into the checkout, re-pointed under their own names, so the old command names keep working
#   route      memory-route.sh --apply: every new key loads the one store
# LISTED, NOT CHANGED (each line names its fix): uv tool receipts naming the checkout, pack ownership (harbor.toml packs, the
# installed manifest, checks.d, shims.d), roots.tsv rows resolving into it (they follow the registry row) and mentions in bin/.
# Exit 0 nothing blocks (dry run) or every step ran (--apply), 1 a place blocks or a step failed, 2 usage.
set -u
LC_ALL=C; export LC_ALL
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$SRC/library-log.sh"; log_init scope-repo-rename
TAB="$(printf '\t')"

PLACES="checkout worktrees sessions registry projects rules fleet remote shims route"

die() { log_fail "$1"; log_fix "${2:-sh $SRC/scope-repo-rename.sh --help}"; log_end || :; exit 2; }
usage() { awk 'NR < 2 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SRC/scope-repo-rename.sh"; }
SR() { sh "$SRC/scope-roots.sh" "$@"; }
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
keys() { sh "$SRC/memory-route.sh" --key -; }   # paths on stdin, the harness's key of each on stdout

OLD=''; NEW=''; APPLY=0; FORCE=0; LIVE=0; TARGETED=0; LIVE_DIR="$HOME/.claude"; CFG="${CLAUDE_CONFIG_DIR:-$LIVE_DIR}"
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --force) FORCE=1 ;;
    --live) CFG="$LIVE_DIR"; LIVE=1; TARGETED=1 ;;
    --dir) [ $# -ge 2 ] || die "--dir takes a config dir"; CFG="$2"; TARGETED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) if [ -z "$OLD" ]; then OLD="$1"; elif [ -z "$NEW" ]; then NEW="$1"; else die "rename takes two names, the old id and the new one"; fi ;;
  esac
  shift
done
[ -n "$OLD" ] && [ -n "$NEW" ] || die "rename takes the old id and the new one" "harbor repo rename <old> <new>"
for _n in "$OLD" "$NEW"; do case "$_n" in *[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) die "'$_n' is not a repo name ([A-Za-z0-9][A-Za-z0-9._-]*)" ;; esac; done
[ "$OLD" != "$NEW" ] || die "the old and the new name are the same"
# D2's rule, as memory-route.sh: a read defaults to the live config dir, a write there is spelled --live.
if [ "$APPLY" = 1 ]; then
  [ "$TARGETED" = 1 ] || die "--apply needs a target: --live, or --dir <config-dir>" "harbor repo rename $OLD $NEW --apply --live"
  [ "$LIVE" = 1 ] || [ "$(_phys "$CFG")" != "$(_phys "$LIVE_DIR")" ] || die "refusing to write $LIVE_DIR without an explicit --live" "harbor repo rename $OLD $NEW --apply --live"
fi

PR="$(SR --port-root)" || die "scope-roots.sh could not resolve the workspace root" "sh $SRC/scope-roots.sh --port-root"
PR="$(_phys "${PR%/}")"
PV="$(SR --private 2>/dev/null)" || PV="$PR/harbor-private"
REGF="$PV/repos.tsv"
[ -f "$REGF" ] || die "no registry at $REGF: a rename is a registry row's" "harbor scope install"
ROWS="$(SR --rows 2>/dev/null)" || die "the registry at $REGF does not validate" "sh $SRC/scope-roots.sh --registry-check"
ROW="$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$OLD" '$1 == n { print; exit }')"
if [ -z "$ROW" ]; then
  log_fail "'$OLD' is not in the registry ($REGF)$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$NEW" '$1 == n { printf ", and %s is: already renamed?", n }')"
  log_fix "harbor repo list"; log_end || :; exit 1
fi
RELP="$(printf '%s' "$ROW" | cut -f2)"; REMOTE="$(printf '%s' "$ROW" | cut -f4)"
case "$RELP" in */*) _pd="${RELP%/*}/" ;; *) _pd='' ;; esac
if [ "${RELP##*/}" = "$OLD" ]; then NRELP="$_pd$NEW"; else NRELP="$RELP"; fi
OP="$PR/$RELP"; NP="$PR/$NRELP"
new_url() { case "$1" in */"$OLD".git) printf '%s' "${1%/*}/$NEW.git" ;; */"$OLD") printf '%s' "${1%/*}/$NEW" ;; *) printf '%s' "$1" ;; esac; }
NREMOTE="$(new_url "$REMOTE")"
SLUG=''; case "$REMOTE" in *github.com[:/]*) SLUG="${REMOTE#*github.com[:/]}"; SLUG="${SLUG%.git}" ;; esac

# The live dir is spelled --live in every line this prints, as the write gate above demands.
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then TGT="--live"; else TGT="--dir $CFG"; fi
W="${TMPDIR:-/tmp}/scope-repo-rename.$$"; mkdir -p "$W" || exit 2
trap 'rm -rf "$W"' EXIT
: > "$W/moves"; : > "$W/keys"; : > "$W/shims"
BLOCKS=0; FAILS=0
say()   { printf '  %s: %s - %s\n' "$1" "$2" "$3"; }
block() { BLOCKS=$((BLOCKS + 1)); say "$1" BLOCK "$2"; }
fail()  { FAILS=$((FAILS + 1)); say "$1" FAIL "$2"; }
# every process's cwd, read once (/proc where there is one, else lsof, which takes seconds); a path is inside when it is the dir or under it
cwds() {
  if [ -d /proc/self ]; then for _q in /proc/[0-9]*; do readlink "$_q/cwd" 2>/dev/null; done
  elif command -v lsof >/dev/null 2>&1; then lsof -nP -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
  else log_warn "no /proc and no lsof: a process inside the checkout cannot be seen"; fi
}
cwds_in() { [ -f "$W/cwds" ] || cwds | sort -u > "$W/cwds"
  while IFS= read -r _p; do awk -v p="$_p" '$0 == p || index($0, p "/") == 1' "$W/cwds"; done | sort -u; }

# ── the plan: what each place holds, and what --apply would do there ─────────────────────────────────────
plan_checkout() {
  [ -d "$OP" ] || { block checkout "no checkout at $OP (registry path '$RELP')"; return; }
  printf '%s\t%s\n' "$OP" "$NP" >> "$W/moves"
  [ "$OP" != "$NP" ] || { say checkout keep "the path '$RELP' does not end in the id, so the checkout stays at $OP"; return; }
  [ ! -e "$NP" ] || { block checkout "$NP exists already"; return; }
  say checkout plan "move $OP -> $NP"
  # a session or shell inside the tree breaks when it moves: every process cwd is read, never guessed
  _in="$(cut -f1 "$W/moves" | cwds_in)"
  if [ -n "$_in" ]; then
    _m="$(printf '%s\n' "$_in" | grep -c .) process(es) have their cwd inside: $(printf '%s' "$_in" | head -n 3 | tr '\n' ' ')"
    if [ "$FORCE" = 1 ]; then say checkout warn "$_m(--force: moving anyway)"; else block checkout "$_m(stop them, or --force)"; fi
  fi
}
plan_worktrees() {
  [ -d "$OP" ] || return 0
  git -C "$OP" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | tail -n +2 > "$W/trees"
  [ -s "$W/trees" ] || { say worktrees none "no linked worktree"; return; }
  while IFS= read -r _t; do
    case "$_t/" in
      "$OP"/*) _n="$NP/${_t#"$OP"/}" ;;
      "$PR/.worktrees/$OLD"/*) _n="$PR/.worktrees/$NEW/${_t#"$PR/.worktrees/$OLD"/}" ;;
      *) _n="$_t" ;;
    esac
    if [ "$_n" != "$_t" ] && [ -e "$_n" ]; then block worktrees "$_n exists already"; continue; fi
    printf '%s\t%s\n' "$_t" "$_n" >> "$W/moves"
    [ "$_n" = "$_t" ] && say worktrees plan "repair $_t (stays)" || say worktrees plan "move $_t -> $_n, repair"
  done < "$W/trees"
  # the trees just listed were added to the cwd check only after it ran: run it again for them
  _in="$(tail -n +2 "$W/moves" | cut -f1 | cwds_in)"
  if [ -n "$_in" ] && [ "$FORCE" = 0 ]; then block worktrees "$(printf '%s\n' "$_in" | grep -c .) process(es) have their cwd in a tree: $(printf '%s' "$_in" | head -n 3 | tr '\n' ' ')(stop them, or --force)"; fi
}
plan_sessions() {
  # each directory that moves, and two levels under it: a session started in a subdirectory has its own key
  while IFS="$TAB" read -r _o _n; do
    [ "$_o" != "$_n" ] || continue
    { printf '%s\n' "$_o"; find "$_o" -mindepth 1 -maxdepth 2 \( -name .git -o -name node_modules -o -name .venv \) -prune -o -type d -print 2>/dev/null; } |
      while IFS= read -r _d; do printf '%s\t%s\n' "$_d" "$_n${_d#"$_o"}"; done
  done < "$W/moves" > "$W/dirs"
  cut -f1 "$W/dirs" | keys > "$W/k.old"; cut -f2 "$W/dirs" | keys > "$W/k.new"
  paste "$W/k.old" "$W/k.new" | while IFS="$TAB" read -r _k _nk; do [ ! -d "$CFG/projects/$_k" ] || printf '%s\t%s\n' "$_k" "$_nk"; done | sort -u > "$W/keys"
  [ -s "$W/keys" ] || { say sessions none "no session or memory directory under $CFG/projects for these paths"; return; }
  while IFS="$TAB" read -r _k _nk; do
    _s="$(find "$CFG/projects/$_k" -maxdepth 1 -name '*.jsonl' 2>/dev/null | grep -c .)"
    if [ -L "$CFG/projects/$_k/memory" ]; then _m="memory routed"; elif [ -d "$CFG/projects/$_k/memory" ]; then _m="an OWN memory store"; else _m="no memory"; fi
    if [ -e "$CFG/projects/$_nk" ]; then block sessions "$_nk exists already: two key dirs are never merged"; continue; fi
    say sessions plan "move projects/$_k -> $_nk ($_s session(s), $_m)"
  done < "$W/keys"
  # a key under an old prefix that no directory derives (a retired tree, a sibling): named, not moved
  printf '%s\n%s\n' "$OP" "$PR/.worktrees/$OLD" | keys | while IFS= read -r _ok; do
    find "$CFG/projects" -mindepth 1 -maxdepth 1 -name "$_ok-*" 2>/dev/null; done | sed 's|.*/||' | sort -u | while IFS= read -r _k; do
    awk -F'\t' -v k="$_k" '$1 == k { f = 1 } END { exit !f }' "$W/keys" || say sessions listed "projects/$_k is not derived from a directory that moves (a retired tree or a sibling): left"
  done
}
plan_registry() {
  printf '%s\n' "$ROWS" | awk -F'\t' -v n="$NEW" '$1 == n { f = 1 } END { exit !f }' && { block registry "the registry already has an id '$NEW'"; return; }
  awk -F'\t' -v OFS='\t' -v o="$OLD" -v n="$NEW" -v op="$RELP" -v np="$NRELP" -v orm="$REMOTE" -v nrm="$NREMOTE" '
    !/^[ \t]*#/ && $1 == o { $1 = n; if ($2 == op || $2 == op "/") $2 = np; if ($4 == orm) $4 = nrm } { print }' "$REGF" > "$W/repos.new"
  SR --registry-check "$W/repos.new" > "$W/regcheck" 2>&1 || { block registry "the rewritten row does not validate: $(grep -m1 'roots:' "$W/regcheck" | cut -c1-160)"; return; }
  say registry plan "$REGF: $OLD $RELP $REMOTE -> $NEW $NRELP $NREMOTE"
}
PF="$(SR --projects 2>/dev/null || :)"
plan_projects() {
  [ -n "$PF" ] && [ -f "$PF" ] || { say projects none "no project registry"; return; }
  _l="$(awk -F'\t' -v o="$OLD" '!/^#/ && $1 == o { print NR ": " $1 " " $2; exit }' "$PF")"
  [ -n "$_l" ] || { say projects none "$OLD has no row in $PF"; return; }
  awk -F'\t' -v n="$NEW" '!/^#/ && $1 == n { f = 1 } END { exit !f }' "$PF" && { block projects "$PF already has a row '$NEW'"; return; }
  if grep -q 'GENERATED by bin/scope-repo' "$PF"; then say projects plan "regenerate $PF from the registry (row $_l)"
  else say projects plan "rewrite $PF row $_l -> $NEW, path .../$NRELP"; fi
}
plan_rules() {
  [ -d "$PV/context-rules/$OLD" ] || { say rules none "no $PV/context-rules/$OLD/"; return; }
  [ ! -e "$PV/context-rules/$NEW" ] || { block rules "$PV/context-rules/$NEW exists already"; return; }
  say rules plan "move $PV/context-rules/$OLD/ -> $NEW/ ($(find "$PV/context-rules/$OLD" -type f | grep -c .) file(s))"
}
FF="$(SR --get HARBOR_SCOPE_FLEET_FILE 2>/dev/null || :)"
case "$FF" in "$OP"/*) FFN="$NP/${FF#"$OP"/}" ;; *) FFN="$FF" ;; esac
fleet_hits() { awk -v p="$OP" '{ i = index($0, p); if (i) { c = substr($0, i + length(p), 1); if (c == "" || c ~ /[\/ "'"'"'#:]/) print NR ": " $0 } }' "$1"; }
plan_fleet() {
  [ -n "$FF" ] && [ -f "$FF" ] || { say fleet none "no fleet.yaml (roots.tsv HARBOR_SCOPE_FLEET_FILE)"; return; }
  _h="$(fleet_hits "$FF")"
  [ -n "$_h" ] || { say fleet none "$FF names no path of $OLD (discovery finds it by scanning)"; return; }
  printf '%s\n' "$_h" | while IFS= read -r _l; do say fleet plan "$FF:$(printf '%s' "$_l" | sed 's/^ *//') -> $NP"; done
}
plan_remote() {
  [ -d "$OP" ] || return 0
  _u="$(git -C "$OP" remote get-url origin 2>/dev/null || :)"
  [ -n "$_u" ] || { say remote none "no origin remote"; return; }
  _nu="$(new_url "$_u")"
  [ "$_nu" != "$_u" ] || { say remote none "origin $_u does not end in $OLD"; return; }
  say remote plan "origin $_u -> $_nu"
}
plan_shims() {
  for _f in "$HOME/.local/bin"/*; do
    [ -L "$_f" ] || continue
    _t="$(readlink "$_f")"
    case "$_t" in "$OP"/*) printf '%s\t%s\n' "$_f" "$NP/${_t#"$OP"/}" >> "$W/shims"; say shims plan "re-point $_f ($_t) -> $NP/${_t#"$OP"/}, its name kept" ;; esac
  done
  [ -s "$W/shims" ] || say shims none "no ~/.local/bin link into $OP"
}
plan_route() { say route plan "memory-route.sh $TGT --apply, so every moved key loads the store"; }

# ── listed only: each is someone else's to change, and its line says how ─────────────────────────────────
listed() {
  for _r in "$HOME/.local/share/uv/tools"/*/uv-receipt.toml; do
    [ -f "$_r" ] && grep -qF "\"$OP\"" "$_r" || continue
    _tool="$(basename "$(dirname "$_r")")"; _eps="$(sed -n 's/.*{ *name *= *"\([^"]*\)".*install-path.*/\1/p' "$_r" | tr '\n' ' ')"
    if grep -q 'editable *=' "$_r"; then say uv listed "$_tool is an EDITABLE install of $OP: ${_eps}breaks when it moves; after --apply: uv tool install --force --editable $NP"
    else say uv listed "$_tool's receipt names $OP; the installed ${_eps}is a copy and keeps working; after --apply, so upgrades find the source: uv tool install --force $NP"; fi
  done
  _pk="$(SR --conf packs 2>/dev/null | grep -x -F "$OLD" || :)"
  [ -z "$_pk" ] || say packs listed "harbor.toml packs names $OLD: harbor pack remove $OLD --apply --live; rename it in harbor.toml; harbor pack install $NEW --apply --live"
  for _p in ".harbor-packs/$OLD.tsv" "checks.d/$OLD.md" "checks.d/$OLD.controls.tsv" "shims.d/$OLD.tsv"; do
    [ ! -e "$CFG/$_p" ] || say packs listed "$CFG/$_p is owned by pack $OLD (the reinstall above moves it)"
  done
  # --get, not --list: only --get follows the registry row (a role row by its kind)
  SR --list 2>/dev/null | awk '$2 == "REPOS" { print $1 }' | while IFS= read -r _v; do
    _g="$(SR --get "$_v" 2>/dev/null)" || continue; _g="$(_phys "${_g%/*}")/${_g##*/}"
    case "$_g/" in "$OP"/*) say roots listed "$_v $_g: follows the registry row, so it resolves under $NP after --apply" ;; esac
  done
  if git -C "$SRC/.." rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$SRC/.." grep -n -w -F -e "$OLD" -- bin > "$W/mentions" 2>/dev/null || :
    _c="$(grep -c . "$W/mentions" || :)"
    if [ "$_c" -gt 0 ]; then say mentions listed "$_c line(s) in harbor's bin/ name '$OLD' (a harbor commit, not this command): $(cut -d: -f1,2 "$W/mentions" | head -n 5 | tr '\n' ' ')"
    else say mentions none "harbor's bin/ names '$OLD' nowhere"; fi
  fi
}

printf 'rename %s -> %s in %s, config %s%s\n' "$OLD" "$NEW" "$PR" "$CFG" "$([ "$APPLY" = 1 ] || echo ' [dry run: nothing is written]')"
if [ -n "$SLUG" ]; then printf '  github: operator - gh repo rename %s -R %s --yes   (needs the repo admin; this command never runs it)\n' "$NEW" "$SLUG"
else printf '  github: none - the registry remote (%s) is not on GitHub\n' "$REMOTE"; fi
for _s in $PLACES; do "plan_$_s"; done
listed

if [ "$APPLY" = 0 ]; then
  [ "$BLOCKS" -eq 0 ] || { log_fail "dry run: $BLOCKS place(s) block the rename"; log_fix "read the BLOCK lines above, then run again"; log_end || :; exit 1; }
  log_ok "dry run: nothing blocks; --apply $TGT would do every plan line"; log_end || :; exit 0
fi
[ "$BLOCKS" -eq 0 ] || { log_fail "$BLOCKS place(s) block the rename: nothing was written"; log_fix "read the BLOCK lines above"; log_end || :; exit 1; }

# ── --apply: the moving places, in PLACES order; the checkout first, and nothing after it if it fails ─────
do_checkout() {
  [ "$OP" != "$NP" ] || return 0
  mkdir -p "${NP%/*}" && mv "$OP" "$NP" && say checkout ok "$NP" || { fail checkout "could not move $OP"; log_fix "mv '$OP' '$NP'"; log_end || :; exit 1; }
}
do_worktrees() {
  tail -n +2 "$W/moves" | while IFS="$TAB" read -r _o _n; do
    [ "$_o" = "$_n" ] || [ ! -d "$_o" ] || { mkdir -p "${_n%/*}" && mv "$_o" "$_n"; } || echo "move $_o"
    [ -d "$_n" ] || { echo "missing $_n"; continue; }
    git -C "$NP" worktree repair "$_n" >/dev/null 2>&1 || echo "repair $_n"
  done > "$W/wt.err"
  rmdir "$PR/.worktrees/$OLD" 2>/dev/null || :
  _pr="$(git -C "$NP" worktree list --porcelain 2>/dev/null | grep -c '^prunable' || :)"
  if [ -s "$W/wt.err" ] || [ "$_pr" -gt 0 ]; then fail worktrees "$(head -n 1 "$W/wt.err") $_pr prunable: git -C $NP worktree repair <path>"
  else say worktrees ok "$(($(grep -c . "$W/moves") - 1)) tree(s) repaired"; fi
}
do_sessions() {
  [ -s "$W/keys" ] || return 0
  _n=0; while IFS="$TAB" read -r _k _nk; do
    mv "$CFG/projects/$_k" "$CFG/projects/$_nk" 2>/dev/null && _n=$((_n + 1)) || fail sessions "could not move projects/$_k"
  done < "$W/keys"
  say sessions ok "$_n key dir(s) moved"
}
do_registry() { cp "$W/repos.new" "$REGF" && say registry ok "$REGF" || fail registry "could not write $REGF"; }
do_projects() {
  [ -n "$PF" ] && [ -f "$PF" ] && awk -F'\t' -v o="$OLD" '!/^#/ && $1 == o { f = 1 } END { exit !f }' "$PF" || return 0
  if grep -q 'GENERATED by bin/scope-repo' "$PF"; then
    sh "$SRC/scope-repos-generate.sh" --projects > "$W/projects.new" 2> "$W/projects.err" || { fail projects "the generator failed: $(head -n 1 "$W/projects.err")"; return; }
  else
    awk -F'\t' -v OFS='\t' -v o="$OLD" -v n="$NEW" -v op="/$RELP" -v np="/$NRELP" '
      !/^#/ && $1 == o { $1 = n; l = length($2) - length(op); if (l >= 0 && substr($2, l + 1) == op) $2 = substr($2, 1, l) np } { print }' "$PF" > "$W/projects.new"
  fi
  cp "$W/projects.new" "$PF" && say projects ok "$PF" || fail projects "could not write $PF"
}
do_rules() { [ -d "$PV/context-rules/$OLD" ] || return 0; mv "$PV/context-rules/$OLD" "$PV/context-rules/$NEW" && say rules ok "$PV/context-rules/$NEW/" || fail rules "could not move context-rules/$OLD"; }
do_fleet() {
  [ -n "$FFN" ] && [ -f "$FFN" ] && [ -n "$(fleet_hits "$FFN")" ] || return 0
  awk -v p="$OP" -v n="$NP" '{ o = ""; r = $0
    while ((i = index(r, p)) > 0) { c = substr(r, i + length(p), 1)
      if (c == "" || c ~ /[\/ "'"'"'#:]/) { o = o substr(r, 1, i - 1) n } else o = o substr(r, 1, i - 1 + length(p))
      r = substr(r, i + length(p)) }
    print o r }' "$FFN" > "$W/fleet.new" && cp "$W/fleet.new" "$FFN" && say fleet ok "$FFN" || fail fleet "could not rewrite $FFN"
}
do_remote() {
  _u="$(git -C "$NP" remote get-url origin 2>/dev/null || :)"; _nu="$(new_url "$_u")"
  [ -n "$_u" ] && [ "$_nu" != "$_u" ] || return 0
  git -C "$NP" remote set-url origin "$_nu" && say remote ok "origin $_nu" || fail remote "git -C $NP remote set-url origin $_nu"
}
do_shims() {
  [ -s "$W/shims" ] || return 0
  while IFS="$TAB" read -r _f _t; do ln -sfn "$_t" "$_f" && say shims ok "$_f -> $_t" || fail shims "ln -sfn '$_t' '$_f'"; done < "$W/shims"
}
do_route() {
  if [ "$LIVE" = 1 ]; then set -- --live; else set -- --dir "$CFG"; fi
  sh "$SRC/memory-route.sh" "$@" --apply --quiet > "$W/route.out" 2>&1; _r=$?
  case "$_r" in 0) say route ok "every routed key loads the store" ;; 3) say route warn "memory-route could not look: $(grep -m1 -i 'stood' "$W/route.out" | cut -c1-120)" ;;
    *) fail route "memory-route exited $_r: sh $SRC/memory-route.sh $* --apply" ;; esac
}
printf 'apply\n'
for _s in $PLACES; do "do_$_s"; done
printf 'next, by hand: the plan lines marked listed above; commit the private layer (git -C %s status); then sh %s/memory-route.sh %s\n' \
  "$PV" "$SRC" "$TGT"
[ "$FAILS" -eq 0 ] || { log_fail "$FAILS step(s) failed"; log_fix "read the FAIL lines above: each names its repair"; log_end || :; exit 1; }
log_ok "$OLD is $NEW on this box"; log_end || :; exit 0
