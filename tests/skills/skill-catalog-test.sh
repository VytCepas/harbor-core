#!/usr/bin/env sh
# bin/skill-catalog.sh (harbor#646, harbor#1149): the TRACKED book lists only the skills the checkout tracks and is the same
# bytes on every machine; the INSTALLED book lists everything the config dir holds, its CLI table and the private layer's
# router rows included. The generator runs from a copy of the tree, so the real tracked book is never touched.
. "$(dirname "$0")/../lib/core.sh"; t_init
R="$T_TMP/root"; mkdir -p "$R/bin" "$R/skills/skill-catalog" "$R/skills/alpha" "$R/skills/beta" "$R/vendor/skills/vend" "$R/vendor/skills/beta" "$R/CONTRACTS" "$T_TMP/neutral"
cp "$T_ROOT/bin/skill-catalog.sh" "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/roots.sh" "$T_ROOT/bin/install-lib.sh" "$R/bin/"
cp "$T_ROOT/bin/skills-install.sh" "$T_ROOT/bin/skills-collide.sh" "$T_ROOT/bin/fs-lib.sh" "$R/bin/"
cp "$T_ROOT/CONTRACTS/roots.tsv" "$T_ROOT/CONTRACTS/catalog-non-tools.tsv" "$R/CONTRACTS/"
printf 'skill\tsituation\nalpha\tAlpha work\nbeta\tBeta work\nmissing\tA skill nobody ships\n' > "$R/CONTRACTS/skill-book-router.tsv"
printf -- '---\nname: alpha\ndescription: "Alpha. USE WHEN alpha work."\ndisable-model-invocation: true\n---\n' > "$R/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: "Beta from skills. USE WHEN beta work."\n---\n' > "$R/skills/beta/SKILL.md"
printf -- '---\nname: beta\ndescription: "Beta from vendor. USE WHEN vendor beta work."\n---\n' > "$R/vendor/skills/beta/SKILL.md"
printf -- '---\nname: vend\ndescription: "Vendored. USE WHEN vend work."\n---\n' > "$R/vendor/skills/vend/SKILL.md"
# The box: a skill nothing tracks, a tool, a directory in the tool dir, and a checkout that carries its own .claude/skills.
SK="$HOME/.claude/skills"; mkdir -p "$SK/boxonly" "$SK/skill-catalog" "$HOME/.local/bin/__pycache__"
printf -- '---\nname: boxonly\ndescription: "Box only. USE WHEN boxonly work."\n---\n' > "$SK/boxonly/SKILL.md"
# What skills-install.sh --all leaves in the config dir: the installed skills, ahead of the book (skills/ wins over vendor/skills/).
cp -R "$R/vendor/skills/vend" "$R/vendor/skills/beta" "$SK/"; cp -R "$R/skills/alpha" "$R/skills/beta" "$SK/"
printf '#!/bin/sh\n' > "$HOME/.local/bin/tool"; chmod +x "$HOME/.local/bin/tool"
GOV="$T_TMP/gov"; mkdir -p "$GOV/.claude/skills/gamma"
printf -- '---\nname: gamma\ndescription: "Gamma. USE WHEN gamma work."\n---\n' > "$GOV/.claude/skills/gamma/SKILL.md"
NOPRIV="$T_TMP/nopriv"; mkdir -p "$NOPRIV"
TRACKED="$R/skills/skill-catalog/SKILL.md"; LIVEBOOK="$SK/skill-catalog/SKILL.md"
# The book is itself a skill, so it is in its own tables once installed: seed both copies as skills-install leaves them.
cp "$T_ROOT/skills/skill-catalog/SKILL.md" "$TRACKED"; cp "$T_ROOT/skills/skill-catalog/SKILL.md" "$LIVEBOOK"
book() { (cd "$1" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" ${2:+"$2"} 2>&1); }
inst() { (cd "$R" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="${PRIVDIR:-$NOPRIV}" sh "$R/bin/skill-catalog.sh" install "$@" 2>&1); }

t_section "the tracked book is written from a neutral cwd"
t_has "write succeeds" "$(book "$T_TMP/neutral")" "ok: wrote skills/skill-catalog/SKILL.md"
T1="$(cat "$TRACKED")"

t_section "the tracked book lists the skills the checkout tracks, and only those"
t_has "a skill/ skill has its row, in the hidden table" "$T1" '| `alpha` | core | Alpha.'
t_has "a skills/ skill is listed" "$T1" '| `beta` | core | Beta from skills.'
t_hasnt "a vendor/skills skill is not listed: that tree is dev-layer, absent from the export" "$T1" '`vend`'
t_eq "a name in skills/ is listed once" 1 "$(grep -c '^- `beta` ' "$TRACKED")"
# Positive control: without skills/beta the book has no beta row at all, so the vendored one never stands in.
mv "$R/skills/beta" "$T_TMP/beta-held"; book "$R" >/dev/null
t_hasnt "...and a checkout without skills/beta lists no beta" "$(cat "$TRACKED")" 'Beta from'
mv "$T_TMP/beta-held" "$R/skills/beta"; book "$R" >/dev/null
t_eq "...and putting skills/beta back restores the book" "$T1" "$(cat "$TRACKED")"
t_hasnt "a skill only the box holds is not in the tracked book" "$T1" 'boxonly'
t_hasnt "a repo-scoped skill never enters the book (harbor#646)" "$T1" 'gamma'
t_hasnt "the tracked book carries no tool: ~/.local/bin is the box's" "$T1" '| `tool` |'
t_has "...and says so" "$T1" 'The tracked book lists none'

t_section "the tracked book is the same bytes whatever machine writes it"
OTHER="$T_TMP/otherhome"; mkdir -p "$OTHER/.claude/skills/zzz" "$OTHER/.local/bin"
printf -- '---\nname: zzz\ndescription: "Zzz. USE WHEN zzz work."\n---\n' > "$OTHER/.claude/skills/zzz/SKILL.md"; printf '#!/bin/sh\n' > "$OTHER/.local/bin/othertool"; chmod +x "$OTHER/.local/bin/othertool"
(cd "$GOV" && HOME="$OTHER" CLAUDE_CONFIG_DIR="$OTHER/.claude" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" >/dev/null 2>&1)
t_eq "another HOME, config dir, cwd and tool dir: byte-identical" "$T1" "$(cat "$TRACKED")"
t_exit "--check from \$HOME" 0 book "$HOME" --check
t_exit "--check from the generator's repo root" 0 book "$R" --check
t_exit "--check from a checkout with its own .claude/skills" 0 book "$GOV" --check
t_has "a current book says so" "$(book "$GOV" --check)" "ok: current"
t_eq "--check never writes" "$T1" "$(cat "$TRACKED")"

t_section "a stale tracked book fails with its fix, and a new tracked skill makes it stale"
printf 'stale\n' >> "$TRACKED"
t_exit "--check on a stale book" 1 book "$R" --check
t_has "the stale FAIL names its fix" "$(book "$R" --check)" "fix: sh bin/skill-catalog.sh"
book "$R" >/dev/null
t_exit "regenerated, it is current again" 0 book "$R" --check
mkdir -p "$R/skills/delta"; printf -- '---\nname: delta\ndescription: "Delta. USE WHEN delta work."\n---\n' > "$R/skills/delta/SKILL.md"
t_exit "a skill the repo gained since the last write makes --check red" 1 book "$R" --check
book "$R" >/dev/null; t_has "...and the write adds its row" "$(cat "$TRACKED")" '| `delta` |'
rm -rf "$R/skills/delta"; book "$R" >/dev/null
t_eq "...and dropping it takes the row out again" "$T1" "$(cat "$TRACKED")"
SUM0="$(cksum < "$TRACKED")"
t_exit "a mistyped flag is a usage error (exit 2)" 2 book "$R" --chekc
t_exit "install is not the default: a stray word is a usage error" 2 book "$R" extra
t_eq "...and a typo leaves the book it was asked to check untouched" "$SUM0" "$(cksum < "$TRACKED")"

t_section "the start-here rows follow the book: a row whose skill is not listed is not printed"
t_has "a listed skill is routed" "$T1" '| Alpha work | `alpha` |'
t_has "...in the file's order" "$T1" '| Beta work | `beta` |'
t_hasnt "a routed skill nobody ships is dropped" "$T1" 'A skill nobody ships'
t_hasnt "the worked example that names two siblings is dropped with them" "$T1" 'both look right'
# Positive controls: the same phrases print once the skills they need are tracked.
for _s in missing measurement-debug reporting-apis; do
  mkdir -p "$R/skills/$_s"; printf -- '---\nname: %s\ndescription: "Stand-in. USE WHEN %s work."\n---\n' "$_s" "$_s" > "$R/skills/$_s/SKILL.md"
done
book "$R" >/dev/null; T1B="$(cat "$TRACKED")"
t_has "...a routed skill's row prints once the checkout ships it" "$T1B" 'A skill nobody ships'
t_has "...and the worked example prints once both siblings are tracked" "$T1B" 'both look right'
rm -rf "$R/skills/missing" "$R/skills/measurement-debug" "$R/skills/reporting-apis"; book "$R" >/dev/null
t_eq "...and dropping them restores the book" "$T1" "$(cat "$TRACKED")"

t_section "install: a dry run writes nothing and says what it would do"
SEED="$(cksum < "$LIVEBOOK")"
t_has "the dry run says it would update" "$(inst --live)" "would update"
t_eq "...and writes nothing: the installed book is the seed" "$SEED" "$(cksum < "$LIVEBOOK")"
t_exit "--check on the seed (the core book skills-install leaves) is red: it lacks the box's skills" 1 inst --check --live
t_exit "a target is required" 2 inst
t_exit "the tracked file is not a target: --dir onto the live dir without --live is refused" 1 inst --dir "$HOME/.claude"

t_section "install: the installed book lists the box's skills, the tracked ones and the CLIs"
SUMT="$(cksum < "$TRACKED")"
t_exit "install --apply --live exits 0" 0 inst --apply --live
B1="$(cat "$LIVEBOOK")"
t_has "the box's own skill has its row" "$B1" '| `boxonly` | box | Box only.'
t_has "...and a line in the trigger index with the installed path" "$B1" '- `boxonly` — `~/.claude/skills/boxonly/SKILL.md` — boxonly work.'
t_has "the box's skill is listed in the table of skills in the listing" "$B1" '| `boxonly` | box | Box only.'
t_has "an executable gets a CLI row" "$B1" '| `tool` |'
t_hasnt "a directory gets no CLI row" "$B1" '__pycache__'
t_eq "the tracked book was not touched by the install" "$SUMT" "$(cksum < "$TRACKED")"
t_exit "--check agrees" 0 inst --check --live
t_has "a second --apply finds it current" "$(inst --apply --live)" "installed book: current"
mkdir -p "$SK/laterskill"; printf -- '---\nname: laterskill\ndescription: "Later. USE WHEN later work."\ndisable-model-invocation: true\n---\n' > "$SK/laterskill/SKILL.md"
t_exit "a skill installed since makes --check red" 1 inst --check --live
t_has "...and the fix is the install" "$(inst --check --live)" "install --apply --live"
inst --apply --live >/dev/null; t_has "...and the install adds the row" "$(cat "$LIVEBOOK")" '| `laterskill` |'
rm -rf "$SK/laterskill"; inst --apply --live >/dev/null
t_eq "...and removing it takes the row out: the book is the one it was" "$B1" "$(cat "$LIVEBOOK")"
BL="$(git hash-object "$LIVEBOOK")"
t_eq "the install manifest records the installed bytes" "$BL" "$(awk '$3 == "skills/skill-catalog/SKILL.md" { b = $1 } END { print b }' "$HOME/.claude/.harbor-manifest")"
t_eq "the pre-run copy of the book is kept" yes "$(find "$HOME/.claude/backups/skill-catalog" -name SKILL.md 2>/dev/null | grep -q . && echo yes || echo no)"

t_section "install: skills-install composes the book instead of copying the tracked one over it (harbor#1149)"
# The tracked book lists what the checkout ships and the composed one what the box holds. skills-install used to treat the book as an
# ordinary payload: its listing called the composed book DRIFTED after every deploy, and the one-skill apply the contract documents
# replaced it with the tracked one, so every box and pack row and the whole CLI table were gone until the next deploy.
sk() { (cd "$R" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skills-install.sh" "$@" --live 2>&1); }
COMP="$(cat "$LIVEBOOK")"
t_has "the composed book carries what only the box holds (the control for the assertions below)" "$COMP" '| `boxonly` |'
t_has "...and its CLI table" "$COMP" '| `tool` |'
t_exit "the dry run over the composed book exits 0" 0 sk skill-catalog
t_has "...and says it is current, not drifted" "$(sk skill-catalog)" "skill-catalog: current"
t_has "the listing says current too" "$(sk)" "skill-catalog: current"
t_hasnt "...and never drifted" "$(sk)" "skill-catalog: DRIFTED"
t_exit "the one-skill apply over the composed book exits 0" 0 sk skill-catalog --apply
t_eq "...and leaves the composed book as it was: the tracked book was not installed over it" "$COMP" "$(cat "$LIVEBOOK")"
mkdir -p "$SK/laterskill"; printf -- '---\nname: laterskill\ndescription: "Later. USE WHEN later work."\ndisable-model-invocation: true\n---\n' > "$SK/laterskill/SKILL.md"
t_has "a skill installed since makes the book drifted, as the generator says" "$(sk skill-catalog)" "skill-catalog: would update (drifted)"
t_exit "...the dry run still exits 0, a plan being no refusal" 0 sk skill-catalog
t_has "...and the listing calls a stale book DRIFTED, so the 'never drifted' check above can fail" "$(sk)" "skill-catalog: DRIFTED"
sk skill-catalog --apply >/dev/null
t_has "...and the one-skill apply adds its row" "$(cat "$LIVEBOOK")" '| `laterskill` |'
t_has "...keeping the box's own rows and the CLI table" "$(cat "$LIVEBOOK")" '| `boxonly` |'
t_exit "...so the generator agrees" 0 inst --check --live
t_eq "the manifest records the composed bytes after the one-skill apply" "$(git hash-object "$LIVEBOOK")" "$(awk '$3 == "skills/skill-catalog/SKILL.md" { b = $1 } END { print b }' "$HOME/.claude/.harbor-manifest")"
rm -rf "$SK/laterskill"; inst --apply --live >/dev/null
t_eq "...and removing the skill and composing again is the book it was" "$COMP" "$(cat "$LIVEBOOK")"
# A live file whose bytes no commit and no install record holds is still refused: the manifest row the install writes is what lets
# the composed book through, and a hand edit has no row.
cp "$LIVEBOOK" "$T_TMP/composed.keep"; printf 'a hand edit\n' >> "$LIVEBOOK"
t_exit "a hand edit the manifest has never seen is still refused" 1 sk skill-catalog
t_exit "...and the refused apply is a refusal too (exit 1)" 1 sk skill-catalog --apply
t_has "...and the refused apply wrote nothing: the hand edit is still there" "$(cat "$LIVEBOOK")" "a hand edit"
cp "$T_TMP/composed.keep" "$LIVEBOOK"
cp "$R/CONTRACTS/skill-book-router.tsv" "$T_TMP/router.keep"; printf 'exampletool\n' >> "$R/CONTRACTS/skill-book-router.tsv"
t_exit "a router the generator cannot read fails the one-skill apply" 1 sk skill-catalog --apply
t_has "...saying the installed book was not touched" "$(sk skill-catalog --apply)" "so it was not touched"
t_eq "...and the installed book is as it was" "$COMP" "$(cat "$LIVEBOOK")"
t_has "the listing says it cannot tell, rather than drifted" "$(sk)" "cannot say whether the installed book is current"
cp "$T_TMP/router.keep" "$R/CONTRACTS/skill-book-router.tsv"
# --all installs the book LAST: vend sits after skill-catalog in the loop, and the book lists what the run installed.
skall() { (cd "$R" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skills-install.sh" "$@" 2>&1); }
FRESH="$HOME/freshcfg"; mkdir -p "$FRESH"
t_exit "--all onto an empty config dir exits 0" 0 skall --all --apply --dir "$FRESH"
t_has "the book --all composed lists a skill installed after it in the loop" "$(cat "$FRESH/skills/skill-catalog/SKILL.md")" '| `vend` |'
t_has "...and one installed before it" "$(cat "$FRESH/skills/skill-catalog/SKILL.md")" '| `alpha` |'
t_exit "...and it is what the generator writes for that dir" 0 inst --check --dir "$FRESH"
t_eq "a second --all finds the book current and rewrites nothing" "$(cksum < "$FRESH/skills/skill-catalog/SKILL.md")" "$(skall --all --apply --dir "$FRESH" >/dev/null; cksum < "$FRESH/skills/skill-catalog/SKILL.md")"

t_section "install: a config dir that is not the live one is shown by its own path"
SCRATCH="$HOME/scratchcfg"; mkdir -p "$SCRATCH/skills/solo"
printf -- '---\nname: solo\ndescription: "Solo. USE WHEN solo work."\n---\n' > "$SCRATCH/skills/solo/SKILL.md"
t_exit "--dir onto a scratch config dir" 0 inst --apply --dir "$SCRATCH"
t_exit "...and a first install is a fixed point: the book it wrote lists itself, so --check finds it current" 0 inst --check --dir "$SCRATCH"
t_has "...with its own row" "$(cat "$SCRATCH/skills/skill-catalog/SKILL.md")" '| `skill-catalog` |'
t_has "its rows carry its path, \$HOME shortened" "$(cat "$SCRATCH/skills/skill-catalog/SKILL.md")" '`~/scratchcfg/skills/solo/SKILL.md`'
t_hasnt "...and it holds nothing of the live box" "$(cat "$SCRATCH/skills/skill-catalog/SKILL.md")" 'boxonly'
t_exit "a CLAUDE_CONFIG_DIR that disagrees with the target is a usage error (exit 2)" 2 env CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" install --apply --live
t_exit "an install into a config dir with no skills dir is refused" 1 inst --apply --dir "$T_TMP/emptycfg"

t_section "the private layer's router rows: replace in place, append, and refuse what cannot be read"
PRIVDIR="$T_TMP/priv"; mkdir -p "$PRIVDIR"
printf '# private rows\nskill\tsituation\nalpha\tAlpha work, the private way\nboxonly\tBox only work\nnotinstalled\tNot installed anywhere\n' > "$PRIVDIR/skill-book-router.tsv"
inst --apply --live >/dev/null; B2="$(cat "$LIVEBOOK")"
t_has "a private row replaces the text of core's row for the same skill" "$B2" '| Alpha work, the private way | `alpha` |'
t_hasnt "...and the core text is gone from the table" "$B2" '| Alpha work | `alpha` |'
t_has "a private row for another skill is appended" "$B2" '| Box only work | `boxonly` |'
t_hasnt "a private row for a skill that is not installed is dropped" "$B2" 'Not installed anywhere'
# Positive control: install that skill and the same row prints.
mkdir -p "$SK/notinstalled"; printf -- '---\nname: notinstalled\ndescription: "Late. USE WHEN late work."\n---\n' > "$SK/notinstalled/SKILL.md"
inst --apply --live >/dev/null
t_has "...and the same private row prints once its skill is installed" "$(cat "$LIVEBOOK")" '| Not installed anywhere | `notinstalled` |'
rm -rf "$SK/notinstalled"; inst --apply --live >/dev/null
t_eq "replaced rows keep their place: alpha stays above beta" "alpha beta boxonly" "$(printf '%s\n' "$B2" | awk -F'`' '/^\| (Alpha|Beta|Box)/ { printf "%s ", $2 }' | sed 's/ $//')"
inst --apply --live >/dev/null
printf 'skill\tsituation\nalpha\n' > "$PRIVDIR/skill-book-router.tsv"
SUMB="$(cksum < "$LIVEBOOK")"
t_exit "a private row with a missing column refuses the whole read (exit 1)" 1 inst --apply --live
t_has "...naming the file and the line" "$(inst --apply --live)" "skill-book-router.tsv line 2: expected 2 columns, got 1"
t_eq "...and the installed book is as it was" "$SUMB" "$(cksum < "$LIVEBOOK")"
# --check has three answers (0 current, 1 stale, 3 cannot say): a row the generator cannot read is not a stale book, and lint T9 and X8
# send the reader of a stale book to a regenerate that would fail with the real error.
t_exit "--check over the unreadable row says it cannot answer (exit 3), not stale (exit 1)" 3 inst --check --live
t_has "...and names the row" "$(inst --check --live)" "skill-book-router.tsv line 2: expected 2 columns, got 1"
printf 'skill\tsituation\nalpha\tAlpha work\n' > "$PRIVDIR/skill-book-router.tsv"
printf 'zzz-late\n' >> "$LIVEBOOK"
t_exit "...while a book that is merely stale stays exit 1, so the two answers differ" 1 inst --check --live
inst --apply --live >/dev/null
cp "$R/CONTRACTS/skill-book-router.tsv" "$T_TMP/router.keep"; printf 'exampletool\n' >> "$R/CONTRACTS/skill-book-router.tsv"
t_exit "the tracked --check over an unreadable core row exits 3 as well" 3 book "$R" --check
t_has "...naming the line" "$(book "$R" --check)" "skill-book-router.tsv line 5: expected 2 columns, got 1"
t_exit "...the write mode keeps the standard's exit 1" 1 book "$R"
t_eq "...and the tracked book was not touched" "$T1" "$(cat "$TRACKED")"
cp "$T_TMP/router.keep" "$R/CONTRACTS/skill-book-router.tsv"
t_exit "...restored, the tracked --check is current again" 0 book "$R" --check
t_exit "an install --check into a config dir with no skills dir cannot answer (exit 3)" 3 inst --check --dir "$T_TMP/emptycfg"
t_exit "...and an --apply there is still the install standard's refusal (exit 1)" 1 inst --apply --dir "$T_TMP/emptycfg"
printf 'skill\tsituation\nalpha\tA\nalpha\tB\n' > "$PRIVDIR/skill-book-router.tsv"
t_has "a skill twice in one file is refused" "$(inst --apply --live)" "repeats the skill of line 2"
printf 'skill\tsituation\nbad name\tA\n' > "$PRIVDIR/skill-book-router.tsv"
t_has "a skill that is not a name is refused" "$(inst --apply --live)" "the skill is not"
printf 'skill\tstuff\nalpha\tA\n' > "$PRIVDIR/skill-book-router.tsv"
t_has "a wrong header is refused" "$(inst --apply --live)" "the header is not skill, situation"
printf 'skill\tsituation\nalpha\tAlpha work, the private way\n' > "$PRIVDIR/skill-book-router.tsv"
(cd "$R" && HARBOR_SCOPE_PRIVATE="$PRIVDIR" sh "$R/bin/skill-catalog.sh" >/dev/null 2>&1)
t_eq "the TRACKED book never reads the private layer: byte-identical with a router file present" "$T1" "$(cat "$TRACKED")"
unset PRIVDIR

t_section "a sibling's CLI contract: the tool from the private cli-contracts.tsv, the path from the registry (harbor#966, #1273)"
PRIV="$T_TMP/priv2"; mkdir -p "$PRIV"; printf 'calrepo\tcal-checkout\tworkload\t-\ntagrepo\ttag-checkout\tworkload\t-\n' > "$PRIV/repos.tsv"
printf '# c\ntool\trepo\tfile\tnote\ncal-read\tcalrepo\tAGENTS.md\t-\ntagx\ttagrepo\t-\t+ the `tagx` skill\ntagx-auth\t-\t-\tthe `tagx` skill access section\n' > "$PRIV/cli-contracts.tsv"
reg() { (cd "$R" && unset CLAUDE_CONFIG_DIR && PORT_ROOT="$T_TMP/pr" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$R/bin/skill-catalog.sh" install --apply --live "$@" 2>&1); }
mkdir -p "$T_TMP/pr"
for _t in cal-read tagx tagx-auth; do printf '#!/bin/sh\n' > "$HOME/.local/bin/$_t"; chmod +x "$HOME/.local/bin/$_t"; done
reg >/dev/null
t_has "a registered repo gives its AGENTS.md" "$(cat "$LIVEBOOK")" "| \`cal-read\` | cli | \`$T_TMP/pr/cal-checkout/AGENTS.md\` |"
t_has "a repo row with no file gives its directory and the note" "$(cat "$LIVEBOOK")" "\`$T_TMP/pr/tag-checkout/\` + the \`tagx\` skill"
t_has "a row with no repo is its note" "$(cat "$LIVEBOOK")" "| \`tagx-auth\` | cli | the \`tagx\` skill access section |"
printf 'other\tx\tworkload\t-\n' > "$PRIV/repos.tsv"
t_exit "an unregistered sibling still writes the book" 0 reg
t_has "an unregistered repo is named, not guessed" "$(cat "$LIVEBOOK")" "repo \`calrepo\` not registered on this box"
t_hasnt "and no literal path is left in its place" "$(cat "$LIVEBOOK")" "/pr/calrepo"
printf 'tool\trepo\tfile\ncal-read\tcalrepo\tAGENTS.md\n' > "$PRIV/cli-contracts.tsv"
t_exit "a cli-contracts.tsv that does not read refuses the book" 1 reg
t_has "...naming the file" "$(reg)" "cli-contracts.tsv line 1: the header is not tool, repo, file, note"
EMPTY="$T_TMP/emptypriv"; mkdir -p "$EMPTY"
reg0() { (cd "$R" && unset CLAUDE_CONFIG_DIR && PORT_ROOT="$T_TMP/pr" HARBOR_SCOPE_PRIVATE="$EMPTY" sh "$R/bin/skill-catalog.sh" install --apply --live "$@" 2>&1); }
t_exit "with no private layer the book is still written" 0 reg0
t_has "no private layer: a sibling's tool has no contract, and says so" "$(cat "$LIVEBOOK")" "| \`cal-read\` | cli | **none yet** |"
t_hasnt "no private layer: nothing is called unregistered" "$(cat "$LIVEBOOK")" "not registered on this box"

t_section "tier is derived from where a skill lives; a non-tool leaves the CLI table; skill-book.sh is an alias (harbor#1010)"
cp "$T_ROOT/bin/skill-book.sh" "$R/bin/"; printf '#!/bin/sh\n' > "$HOME/.local/bin/helper.sh"; printf '#!/bin/sh\n' > "$HOME/.local/bin/python3.12"; chmod +x "$HOME/.local/bin/helper.sh" "$HOME/.local/bin/python3.12"
t_exit "the book is written with a script and an interpreter on the tool dir" 0 reg0
TB="$(cat "$LIVEBOOK")"
t_has "a skills/ skill is tier core" "$TB" '| `alpha` | core |'
t_has "a vendor/skills/ skill is tier vendored" "$TB" '| `vend` | vendored |'
t_has "a skill nothing here tracks is tier box" "$TB" '| `boxonly` | box |'
t_has "a real tool is a cli row" "$TB" '| `tool` | cli |'
t_hasnt "a script is not a tool row" "$TB" '| `helper.sh` |'
t_hasnt "an interpreter is not a tool row" "$TB" '| `python3.12` |'
t_has "...and both are named once under the table, so nothing is silently dropped" "$TB" 'Not tools, so not rows (CONTRACTS/catalog-non-tools.tsv): `helper.sh`, `python3.12`'
AL="$(cd "$R" && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-book.sh" --check 2>&1)"
t_has "the old script name says it was renamed" "$AL" 'renamed to skill-catalog.sh'
t_has "...and really runs the new one (its own summary line)" "$AL" 'skill-catalog: ' 
t_eq "...with the same exit code as the new name" "$(cd "$R" && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" --check >/dev/null 2>&1; echo $?)" "$(cd "$R" && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-book.sh" --check >/dev/null 2>&1; echo $?)"

t_section "manifest drift: every installed skill has a manifest row, and every skill row an installed skill (harbor#1010)"
MFD="$T_TMP/mfcfg"; mkdir -p "$MFD/skills/one" "$MFD/skills/two" "$MFD/.harbor-packs"
for _s in one two; do printf -- '---\nname: %s\ndescription: "X. USE WHEN x."\n---\n' "$_s" > "$MFD/skills/$_s/SKILL.md"; done
mfi() { (cd "$R" && unset CLAUDE_CONFIG_DIR && HARBOR_SCOPE_PRIVATE="$NOPRIV" sh "$R/bin/skill-catalog.sh" install --manifest --dir "$MFD" 2>&1); }
mfx() { mfi >/dev/null; echo $?; }
t_eq "no manifest at all is unchecked (3), never a green" 3 "$(mfx)"
printf '# .harbor-manifest\nabc 100644 skills/one/SKILL.md skills-install deadbeef\n' > "$MFD/.harbor-manifest"
printf 'F\tskills/two/SKILL.md\n' > "$MFD/.harbor-packs/pk.tsv"
t_eq "one skill in the deploy manifest and one in a pack's is clean" 0 "$(mfx)"
t_has "...and says how many it judged" "$(mfi)" 'every one of the 2 installed skill(s) has a manifest row'
mkdir -p "$MFD/skills/three"; printf -- '---\nname: three\ndescription: "X. USE WHEN x."\n---\n' > "$MFD/skills/three/SKILL.md"
t_eq "a hand-installed skill with no row is red" 1 "$(mfx)"
t_has "...and named" "$(mfi)" 'installed skill three has no row'
rm -rf "$MFD/skills/three"; printf 'abc 100644 skills/ghost/SKILL.md skills-install deadbeef\n' >> "$MFD/.harbor-manifest"
t_eq "a manifest row whose skill is gone is red" 1 "$(mfx)"
t_has "...and named" "$(mfi)" 'manifest row for skill ghost names a skill that is not installed'
t_done
