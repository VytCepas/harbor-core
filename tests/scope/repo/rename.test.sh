#!/usr/bin/env sh
# `harbor repo rename <old> <new>` (harbor#966) on a throwaway box: HOME, PORT_ROOT, the private layer, a memory store, a repo with
# trees, sessions, rules, a fleet.yaml line and a PATH shim. The dry run names every place and writes nothing; --apply moves the
# checkout, its trees, sessions and memory, rewrites the rows, and the old command name still runs. Then each place is deleted from a
# copy of the command in turn, and that place's assertion must go red (a place nothing checks is not a place).
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
BIN0="$T_ROOT/bin"
TAB="$(printf '\t')"
# lsof reads every process (seconds a run): stubbed silent, but for the one case that puts a process inside a tree
mkdir -p "$T/stub"; printf '#!/bin/sh\n[ -f "%s/lsof.real" ] || exit 0\nexec %s "$@"\n' "$T" "$(command -v lsof || echo false)" > "$T/stub/lsof"
chmod +x "$T/stub/lsof"; PATH="$T/stub:$PATH"; export PATH
keyof() { printf '%s' "$1" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g'; }   # the harness's key (claude's bundle), never the tool's
G() { git -c user.email=t@t -c user.name=t "$@"; }
mkcopy() { mkdir -p "$1"; cp -R "$BIN0" "$1/bin"; cp -R "$T_ROOT/standards" "$1/standards"; cp -R "$T_ROOT/contracts" "$1/contracts"; }

box() { # <name> -> B PR PV CFG, a box whose repo `olda` (the scaffolder) is registered, routed and in use
  B="$T/$1"; HOME="$B/home"; PORT_ROOT="$HOME/port"; CLAUDE_CONFIG_DIR="$HOME/.claude"
  GIT_CONFIG_NOSYSTEM=1; GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  export HOME PORT_ROOT CLAUDE_CONFIG_DIR GIT_CONFIG_NOSYSTEM GIT_CONFIG_GLOBAL
  mkdir -p "$CLAUDE_CONFIG_DIR/projects" "$PORT_ROOT" "$HOME/.local/bin"; : > "$GIT_CONFIG_GLOBAL"
  sh "$BIN0/scope.sh" install >/dev/null 2>&1
  PR="$(CDPATH= cd -P -- "$PORT_ROOT" && pwd -P)"; PV="$PR/harbor-private"; CFG="$CLAUDE_CONFIG_DIR"
  for r in olda olda-other fl; do mkdir -p "$PR/$r/bin"; G -C "$PR/$r" init -q; : > "$PR/$r/f"; G -C "$PR/$r" add -A; G -C "$PR/$r" commit -qm base; done
  printf '#!/bin/sh\necho olda-cli ran\n' > "$PR/olda/bin/cli.sh"; chmod +x "$PR/olda/bin/cli.sh"; mkdir -p "$PR/olda/sub"
  G -C "$PR/olda" remote add origin https://github.com/acme/olda.git
  printf 'olda\tolda\tscaffolder\thttps://github.com/acme/olda.git\tplatform\t-\nolda-other\tolda-other\tworkload\t-\t-\t-\nfl\tfl\tfleet-controller\t-\tplatform\t-\n' >> "$PV/repos.tsv"
  mkdir -p "$PV/context-rules/user" "$PV/context-rules/olda"; : > "$PV/context-rules/olda/rule.md"
  printf 'olda\t~/port/olda\tthe scaffolder\nolda-other\t~/port/olda-other\ta sibling\n' > "$PV/context-rules/user/projects.tsv"
  printf 'projects:\n  - %s/olda\n  - %s/olda-other\n' "$PR" "$PR" > "$PR/fl/fleet.yaml"
  G -C "$PR/olda" worktree add -q -b feat "$PR/.worktrees/olda/feat" 2>/dev/null
  G -C "$PR/olda" worktree add -q -b leg "$PR/olda-wt-leg" 2>/dev/null
  mkdir -p "$CFG/projects/$(keyof "$HOME")/memory"; printf 'a note\n' > "$CFG/projects/$(keyof "$HOME")/memory/note.md"
  sh "$BIN0/memory-route.sh" --live --apply --quiet >/dev/null 2>&1
  G -C "$PR/olda" worktree add -q -b late "$PR/.worktrees/olda/late" 2>/dev/null   # born after the route: blind until a rename routes it
  # mkdir first: a failed redirect on the `:` special builtin aborts dash (Linux sh) before any `||` fallback runs
  for d in olda olda/sub .worktrees/olda/feat olda-other; do mkdir -p "$CFG/projects/$(keyof "$PR/$d")"; : > "$CFG/projects/$(keyof "$PR/$d")/s.jsonl"; done
  ln -s "$PR/olda/bin/cli.sh" "$HOME/.local/bin/olda-cli"
  mkdir -p "$HOME/.local/share/uv/tools/olda"
  printf '[tool]\nrequirements = [{ name = "olda", directory = "%s/olda" }]\nentrypoints = [\n    { name = "olda-cli", install-path = "%s/.local/bin/olda-cli", from = "olda" },\n]\n' "$PR" "$HOME" > "$HOME/.local/share/uv/tools/olda/uv-receipt.toml"
}
rr() { _b="$1"; shift; sh "$_b/scope-repo-rename.sh" "$@" > "$B/out" 2>&1 < /dev/null; echo "exit $?"; }   # output in $B/out
snap() { { find "$HOME" -print | LC_ALL=C sort; cat "$PV/repos.tsv" "$PV/context-rules/user/projects.tsv" "$PR/fl/fleet.yaml" "$PR/olda/.git/config"; } | cksum; }

evidence() { # <place> -> yes|no: the place's own trace on the box after an --apply olda -> newa
  case "$1" in
    checkout) [ -d "$PR/newa/.git" ] && [ ! -e "$PR/olda" ] ;;
    worktrees) [ -f "$PR/.worktrees/newa/feat/.git" ] && G -C "$PR/.worktrees/newa/feat" rev-parse --git-dir >/dev/null 2>&1 &&
               G -C "$PR/olda-wt-leg" rev-parse --git-dir >/dev/null 2>&1 && [ "$(G -C "$PR/newa" worktree list --porcelain 2>/dev/null | grep -c '^prunable')" = 0 ] ;;
    sessions) [ -f "$CFG/projects/$(keyof "$PR/newa")/s.jsonl" ] && [ -f "$CFG/projects/$(keyof "$PR/newa/sub")/s.jsonl" ] &&
              [ -f "$CFG/projects/$(keyof "$PR/.worktrees/newa/feat")/s.jsonl" ] && [ ! -e "$CFG/projects/$(keyof "$PR/olda")" ] ;;
    registry) awk -F'\t' '$1 == "newa" && $2 == "newa" && $3 == "scaffolder" && $4 == "https://github.com/acme/newa.git" { f = 1 } END { exit !f }' "$PV/repos.tsv" ;;
    projects) awk -F'\t' '$1 == "newa" && $2 == "~/port/newa" { f = 1 } END { exit !f }' "$PV/context-rules/user/projects.tsv" ;;
    rules) [ -f "$PV/context-rules/newa/rule.md" ] && [ ! -e "$PV/context-rules/olda" ] ;;
    fleet) grep -qx "  - $PR/newa" "$PR/fl/fleet.yaml" && grep -qx "  - $PR/olda-other" "$PR/fl/fleet.yaml" ;;
    remote) [ "$(G -C "$PR/newa" remote get-url origin 2>/dev/null)" = https://github.com/acme/newa.git ] ;;
    shims) [ "$("$HOME/.local/bin/olda-cli" 2>/dev/null)" = "olda-cli ran" ] ;;
    route) [ -L "$CFG/projects/$(keyof "$PR/.worktrees/newa/late")/memory" ] ;;
  esac && echo yes || echo no
}
PLACES="$(sed -n 's/^PLACES="\(.*\)"$/\1/p' "$BIN0/scope-repo-rename.sh")"

t_section "the verb: harbor repo rename is dispatched and in the contract"
box h
t_has "harbor repo --help lists rename" "$(sh "$BIN0/harbor" repo --help 2>&1)" "harbor repo rename <old> <new>"
t_has "…and contracts/cli.md names it" "$(cat "$T_ROOT/contracts/cli.md")" 'harbor repo rename <old> <new>'
t_eq "harbor repo rename with one name is a usage error" "exit 2" "$(sh "$BIN0/harbor" repo rename olda > "$B/out" 2>&1; echo "exit $?")"

t_section "the dry run names every place the id lives, and writes nothing"
box d
_before="$(snap)"
t_eq "the dry run exits 0" "exit 0" "$(rr "$BIN0" olda newa)"
O="$(cat "$B/out")"
t_eq "…and wrote nothing (the tree under HOME and every file it would rewrite)" "$_before" "$(snap)"
t_has "the GitHub rename is the operator's line, never run" "$O" "github: operator - gh repo rename newa -R acme/olda --yes"
for p in $PLACES; do t_has "place $p has a plan line" "$O" "  $p: plan - "; done
t_has "the sessions plan carries the subdirectory's key" "$O" "projects/$(keyof "$PR/olda/sub") -> $(keyof "$PR/newa/sub")"
t_has "a sibling's key under the same prefix is named and left" "$O" "projects/$(keyof "$PR/olda-other") is not derived from a directory that moves"
t_hasnt "…and never planned to move" "$O" "move projects/$(keyof "$PR/olda-other")"
t_has "the uv receipt is listed with its reinstall" "$O" "uv tool install --force $PR/newa"
t_has "a roots row resolving into the checkout is listed as following the registry" "$O" "roots: listed - HARBOR_SCOPE_SCAFFOLDER $PR/olda"
t_has "the same run through the dispatcher" "$(sh "$BIN0/harbor" repo rename olda newa 2>&1)" "  checkout: plan - move $PR/olda -> $PR/newa"

t_section "what blocks: a write to the live dir unspelled, a process inside a tree, a taken id"
t_eq "--apply with no target is refused" "exit 2" "$(rr "$BIN0" olda newa --apply)"
t_eq "--apply --dir naming the live dir is refused without --live" "exit 2" "$(rr "$BIN0" olda newa --apply --dir "$HOME/.claude/")"
( cd "$PR/.worktrees/olda/feat" && exec sleep 60 ) & _sp=$!
: > "$T/lsof.real"; sleep 1
t_eq "a process with its cwd in a tree blocks the dry run" "exit 1" "$(rr "$BIN0" olda newa)"
t_has "…naming the cwd" "$(cat "$B/out")" "process(es) have their cwd in a tree: $PR/.worktrees/olda/feat"
t_eq "…and --apply" "exit 1" "$(rr "$BIN0" olda newa --apply --live)"
t_eq "…which moved nothing" yes "$([ -d "$PR/olda" ] && [ ! -e "$PR/newa" ] && echo yes || echo no)"
kill "$_sp" 2>/dev/null; wait "$_sp" 2>/dev/null; rm -f "$T/lsof.real"
t_eq "a new id the registry has is refused" "exit 1" "$(rr "$BIN0" olda olda-other)"
t_has "…by the registry and the checkout" "$(cat "$B/out")" "registry: BLOCK - the registry already has an id 'olda-other'"

t_section "--apply moves every place, and the old command name still runs"
box a
t_eq "memory-route reads the late tree BLIND before the rename" 1 "$(sh "$BIN0/memory-route.sh" --live >/dev/null 2>&1; echo $?)"
t_eq "--apply --live exits 0" "exit 0" "$(rr "$BIN0" olda newa --apply --live)"
for p in $PLACES; do t_eq "place $p left its trace" yes "$(evidence "$p")"; done
t_eq "the sibling's session key is untouched" yes "$([ -f "$CFG/projects/$(keyof "$PR/olda-other")/s.jsonl" ] && echo yes || echo no)"
t_eq "the scaffolder role follows the registry row" "$PR/newa" "$(sh "$BIN0/scope-roots.sh" --get HARBOR_SCOPE_SCAFFOLDER 2>/dev/null)"
t_eq "memory-route is green after it" 0 "$(sh "$BIN0/memory-route.sh" --live >/dev/null 2>&1; echo $?)"
t_eq "a second rename of the old id finds nothing to rename" "exit 1" "$(rr "$BIN0" olda newa --apply --live)"
t_has "…and says it looks renamed already" "$(cat "$B/out")" "already renamed?"

t_section "each place, deleted from a copy, turns its own assertion red"
for p in $PLACES; do
  mkcopy "$T/mut-$p"
  _rest="$(printf '%s\n' $PLACES | grep -vx "$p" | tr '\n' ' ' | sed 's/ $//')"
  sed "s/^PLACES=\".*\"$/PLACES=\"$_rest\"/" "$BIN0/scope-repo-rename.sh" > "$T/mut-$p/bin/scope-repo-rename.sh"
  box "m-$p"
  rr "$T/mut-$p/bin" olda newa --apply --live >/dev/null
  t_eq "without $p, its trace is missing" no "$(evidence "$p")"
done

t_section "a mention in harbor's bin/ is listed, not rewritten"
mkcopy "$T/mention"; printf '# reads olda\n' > "$T/mention/bin/x-olda.sh"
G -C "$T/mention" init -q; G -C "$T/mention" add -A >/dev/null 2>&1; G -C "$T/mention" commit -qm m
box mn
t_eq "the dry run from that tree exits 0" "exit 0" "$(rr "$T/mention/bin" olda newa)"
t_has "…and lists the mention by file and line" "$(cat "$B/out")" "mentions: listed - 1 line(s) in harbor's bin/ name 'olda'"
t_eq "…which --apply leaves as it was" "# reads olda" "$(rr "$T/mention/bin" olda newa --apply --live >/dev/null; cat "$T/mention/bin/x-olda.sh")"
t_done
