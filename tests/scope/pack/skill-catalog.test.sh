#!/usr/bin/env sh
# The INSTALLED skill catalog is generated from what is installed, packs included (harbor#1149): an installed pack's skill has
# its rows, and a removed pack's rows are gone. The generator runs from a copy of the tree, so the tracked book is untouched,
# and the "live" config dir is the suite's sandbox HOME, never the real one.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$(dirname "$0")/fixture.sh"
case "$HOME" in "$T_TMP"/*) ;; *) echo "skill-catalog.test: HOME is not the sandbox: $HOME" >&2; exit 2 ;; esac
R="$T_TMP/root"; mkdir -p "$R/bin" "$R/skills/skill-catalog" "$R/contracts"
cp "$T_ROOT/bin/skill-catalog.sh" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/scope-roots.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$R/bin/"
cp "$T_ROOT/contracts/roots.tsv" "$T_ROOT/contracts/skill-book-router.tsv" "$R/contracts/"
cp "$T_ROOT/skills/skill-catalog/SKILL.md" "$R/skills/skill-catalog/SKILL.md"; TRACKED_SUM="$(cksum < "$R/skills/skill-catalog/SKILL.md")"
SK="$HOME/.claude/skills"; mkdir -p "$SK/alpha" "$SK/skill-catalog"
printf -- '---\nname: alpha\ndescription: "Alpha. USE WHEN alpha work."\n---\n' > "$SK/alpha/SKILL.md"
cp "$T_ROOT/skills/skill-catalog/SKILL.md" "$SK/skill-catalog/SKILL.md"   # installed by skills-install before the book is composed
NOPRIV="$T_TMP/nopriv"; mkdir -p "$NOPRIV"
book() { (cd "$R" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" install "$@" 2>&1); }
BOOK="$SK/skill-catalog/SKILL.md"
# A pack with one hidden skill and one visible one; both descriptions are single scalars, as the book requires.
mkpack bk; rm -rf "$PW/bk/harbor-pack/bin" "$PW/bk/harbor-pack/shims.tsv" "$PW/bk/harbor-pack/inject.d"; mkdir -p "$PW/bk/harbor-pack/skills/packhid"
printf -- '---\nname: demo\ndescription: "Demo pack skill. USE WHEN packvisible work."\n---\nBody.\n' > "$PW/bk/harbor-pack/skills/demo/SKILL.md"
printf -- '---\nname: packhid\ndescription: "Hidden pack skill. USE WHEN packhidden work."\ndisable-model-invocation: true\n---\nBody.\n' > "$PW/bk/harbor-pack/skills/packhid/SKILL.md"
G "$PW/bk" add -A; G "$PW/bk" commit -q -m skills; listed '"bk"'

t_section "before the pack: the book holds the box's own skills only"
book --apply --live >/dev/null; B0="$(cat "$BOOK")"
t_has "the box's skill has its row" "$B0" '| `alpha` |'
t_hasnt "the pack's skills have none" "$B0" 'packhid'

t_section "after install: the pack's skills have their rows, in the table that matches their visibility"
t_exit "pack install --live (the sandbox HOME's own config dir) exits 0" 0 pk install bk --apply --live
t_exit "the book is regenerated from what is installed" 0 book --apply --live
B1="$(cat "$BOOK")"
t_has "the hidden pack skill is listed among the skills you cannot see, with its path" "$B1" '| `packhid` | pack | Hidden pack skill.'
t_has "...its read path is the installed one" "$B1" '`~/.claude/skills/packhid/SKILL.md`'
t_has "the visible pack skill is listed among the invocable ones" "$B1" '| `demo` | pack | Demo pack skill.'
t_has "both have a line in the trigger index, with the words a task arrives with" "$B1" '- `packhid` — `~/.claude/skills/packhid/SKILL.md` — packhidden work.'
t_has "...and the visible one" "$B1" 'packvisible work.'
t_has "the box's own skill keeps its row" "$B1" '| `alpha` |'
t_exit "--check agrees: the book on disk is what is installed" 0 book --check --live
t_eq "...and the tracked book was never written: a pack's skill does not reach git" "$TRACKED_SUM" "$(cksum < "$R/skills/skill-catalog/SKILL.md")"

t_section "after remove: no pack row is left, and the book is the one it was before"
t_exit "pack remove exits 0" 0 pk remove bk --apply --live
t_has "--check now calls the book stale" "$(book --check --live)" 'STALE'
t_exit "the book is regenerated" 0 book --apply --live
t_eq "no row of either pack skill survives" 0 "$(grep -c 'packhid\|packvisible' "$BOOK")"
t_eq "...and the book is byte-identical to the one before the pack" "$B0" "$(cat "$BOOK")"
t_done
