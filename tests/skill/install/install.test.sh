#!/usr/bin/env sh
# skill-install.sh: dry run by default, byte- and mode-identical installs, no nesting, safe
# renames, the live-dir gate, and the collision gate wired in (harbor#7 I1, #117 I3, #239).
# Runs on a fake repo whose bin/ carries skill-collision-verify.sh, so the collision gate is live.
# Then the install standard (harbor#765, #771): --live or --dir, the dry-run exit rule, --accept-loss,
# and a backup of what an install replaces or a rename removes.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY
SUT="$T_ROOT/bin/skill-install.sh"; ROOT="$T_TMP/repo"; CFG="$CLAUDE_CONFIG_DIR"
mkdir -p "$ROOT/bin" "$ROOT/skills/alpha" "$ROOT/vendor/skills/beta" "$CFG/skills"
cp "$SUT" "$T_ROOT/bin/library-log.sh" "$T_ROOT/bin/deploy-install-lib.sh" "$T_ROOT/bin/library-fs.sh" "$ROOT/bin/"
cp "$T_ROOT/bin/skill-collision-verify.sh" "$ROOT/bin/skill-collision-verify.sh"; chmod +x "$ROOT/bin/skill-collision-verify.sh"
printf -- '---\nname: alpha\ndescription: "A"\n---\n\n# alpha\nbody v1\n' > "$ROOT/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: "B"\n---\n\n# beta\n' > "$ROOT/vendor/skills/beta/SKILL.md"
# $CFG is the target: --dir names it, and CLAUDE_CONFIG_DIR (t_init's) agrees with it.
run() { sh "$ROOT/bin/skill-install.sh" --dir "$CFG" "$@" 2>&1 | tr -s ' '; }
rc() { sh "$ROOT/bin/skill-install.sh" --dir "$CFG" "$@" >/dev/null 2>&1; echo $?; }
same() { diff -r "$ROOT/skills/$1" "$CFG/skills/$1" >/dev/null 2>&1 && echo same || echo differs; }
gone() { [ -L "$1" ] || [ -e "$1" ] && echo present || echo gone; }

t_section "dry run, fresh install, drift and update"
run alpha >/dev/null
t_eq "dry run writes nothing" gone "$(gone "$CFG/skills/alpha")"
run alpha --apply >/dev/null
t_eq "fresh install is byte-identical" same "$(same alpha)"
printf 'body v2\n' >> "$ROOT/skills/alpha/SKILL.md"
t_has "a changed source reports DRIFTED" "$(run)" "note: alpha: DRIFTED"
run alpha --apply >/dev/null
t_eq "update re-syncs to byte-identical" same "$(same alpha)"

t_section "a hand-typed nested copy is seen, and the verb never nests"
cp -R "$ROOT/skills/alpha" "$CFG/skills/alpha/"  # no trailing /. — the trap
t_eq "the nested copy was staged" present "$(gone "$CFG/skills/alpha/alpha")"
t_has "a pre-existing nested copy reports NESTED" "$(run)" "WARN: alpha: NESTED"
t_eq "a nested copy fails the dry run of an install (--apply would fail)" 1 "$(rc alpha)"
t_has "...naming it, then the fix line" "$(run alpha | grep -A1 'FAIL: alpha:' | tail -1)" "fix: none automatic"
rm -rf "$CFG/skills/alpha/alpha"
run alpha --apply >/dev/null
t_eq "installing over an existing dir does not nest" gone "$(gone "$CFG/skills/alpha/alpha")"

t_section "renames: case-only, distinct, symlink (harbor#239, PR #241)"
mkdir -p "$CFG/skills/Alpha"; cp "$ROOT/skills/alpha/SKILL.md" "$CFG/skills/Alpha/SKILL.md"
run alpha --apply --from-old Alpha >/dev/null
t_eq "case-only rename keeps the skill" present "$(gone "$CFG/skills/alpha/SKILL.md")"
t_eq "case-only rename leaves exactly one directory" 1 "$(ls "$CFG/skills" | grep -c '^[Aa]lpha$')"
t_eq "the stored spelling is the new name" alpha "$(ls "$CFG/skills" | grep -i '^alpha$')"
mkdir -p "$CFG/skills/LegacyName"; cp "$ROOT/skills/alpha/SKILL.md" "$CFG/skills/LegacyName/SKILL.md"
run alpha --apply --from-old LegacyName >/dev/null
t_eq "a distinct old name is removed" gone "$(gone "$CFG/skills/LegacyName")"
t_eq "removing a distinct old name keeps the skill" present "$(gone "$CFG/skills/alpha/SKILL.md")"
t_eq "the skill is byte-identical after a rename" same "$(same alpha)"  # not mv'd inside it
ln -s "$CFG/skills/alpha" "$CFG/skills/LegacyLink"
run alpha --apply --from-old LegacyLink >/dev/null
t_eq "a symlinked old name is removed" gone "$(gone "$CFG/skills/LegacyLink")"
t_eq "a symlinked old name leaves nothing inside the skill" same "$(same alpha)"
t_eq "the same-dir probe is cleaned up" 0 "$(ls -a "$CFG/skills/alpha" | grep -c 'harbor-same-dir-probe')"

t_section "vendor is a source; unknown names and failed writes are loud"
run beta --apply >/dev/null
t_eq "a vendored skill installs" present "$(gone "$CFG/skills/beta/SKILL.md")"
t_eq "unknown skill" 1 "$(rc no-such-skill --apply)"
mkdir -p "$CFG/skills/gamma" "$ROOT/skills/gamma"; chmod 500 "$CFG/skills/gamma"
printf -- '---\nname: gamma\ndescription: "G"\n---\n' > "$ROOT/skills/gamma/SKILL.md"
t_eq "a write that cannot land" 1 "$(rc gamma --apply)"
chmod 700 "$CFG/skills/gamma"

t_section "the live skills dir needs --live (lint D2)"
FH="$T_TMP/fh"; mkdir -p "$FH/.claude/skills"
live() { HOME="$FH" CLAUDE_CONFIG_DIR="$FH/.claude" sh "$ROOT/bin/skill-install.sh" alpha "$@" >/dev/null 2>&1; echo $?; }
t_eq "live dir without --live" 1 "$(live --apply --dir "$FH/.claude")"
t_eq "the refused run changed nothing" gone "$(gone "$FH/.claude/skills/alpha")"
t_eq "the same write with --live" 0 "$(live --apply --live)"

t_section "the commands kind: the gate holds on both sides"
cmd() { _h="$1" _c="$2"; shift 2; HOME="$_h" CLAUDE_CONFIG_DIR="$_c" sh "$SUT" commands "$@" >/dev/null 2>&1; echo $?; }  # the repo's commands/, target from the flags
CH="$T_TMP/ch"; mkdir -p "$CH/.claude" "$T_TMP/ch2" "$T_TMP/ch3/elsewhere" "$T_TMP/ch4/.claude"
t_eq "live commands dir without --live" 1 "$(cmd "$CH" "$CH/.claude" --apply --dir "$CH/.claude")"
t_eq "the refused commands run left no directory" gone "$(gone "$CH/.claude/commands")"
t_eq "no config dir yet: the gate still holds" 1 "$(cmd "$T_TMP/ch2" "$T_TMP/ch2/.claude" --apply --dir "$T_TMP/ch2/.claude")"
t_eq "a non-live config dir is not refused" 0 "$(cmd "$T_TMP/ch3" "$T_TMP/ch3/elsewhere" --apply --dir "$T_TMP/ch3/elsewhere")"
t_eq "a dry run with the destination absent" 0 "$(cmd "$T_TMP/ch4" "$T_TMP/ch4/.claude" --live)"

t_section "the collision gate is wired in (harbor#117 I3)"
mkdir -p "$ROOT/skills/delta"
printf -- '---\nname: delta\ndescription: "D"\n---\n\n# delta\nv1\n' > "$ROOT/skills/delta/SKILL.md"
run delta --apply >/dev/null
printf -- '---\nname: delta\ndescription: "D"\n---\n\n# delta\nedited on the box only\n' > "$CFG/skills/delta/SKILL.md"
touch -t 203101010000 "$CFG/skills/delta/SKILL.md"; touch -t 203001010000 "$ROOT/skills/delta/SKILL.md"
t_eq "installing over a newer live copy" 1 "$(rc delta --apply)"
t_has "the live bytes survive the refusal" "$(cat "$CFG/skills/delta/SKILL.md")" "edited on the box only"
t_eq "the dry run predicts that refusal (the dry-run exit rule)" 1 "$(rc delta)"
t_has "...naming it, with the --accept-loss command as its fix" "$(run delta | grep -A1 'FAIL: delta:')" \
  "fix: sh $ROOT/bin/skill-install.sh --apply delta --dir '$(cd "$CFG" && pwd -P)' --accept-loss"
t_eq "--clobber-newer is gone: it is an unknown flag now" 2 "$(rc delta --apply --clobber-newer)"
t_eq "--accept-loss overrides the refusal" 0 "$(rc delta --apply --accept-loss)"
t_eq "--accept-loss wrote the source bytes" same "$(same delta)"
t_has "...and the backup holds the box-only edit" "$(find "$CFG/backups/skills-install" -path '*/skills/delta/SKILL.md' -exec cat {} + 2>/dev/null)" "edited on the box only"

t_section "the exec bit is payload, and the repair copies the source mode"
mkdir -p "$ROOT/skills/epsilon/bin" "$CFG/skills/epsilon/bin"
printf -- '---\nname: epsilon\ndescription: "E"\n---\n\n# epsilon\n' > "$ROOT/skills/epsilon/SKILL.md"
printf '#!/usr/bin/env sh\nexit 0\n' > "$ROOT/skills/epsilon/bin/run.sh"; chmod 755 "$ROOT/skills/epsilon/bin/run.sh"
printf 'not a program\n' > "$ROOT/skills/epsilon/bin/notes.txt"; chmod 644 "$ROOT/skills/epsilon/bin/notes.txt"
cp "$ROOT/skills/epsilon/SKILL.md" "$CFG/skills/epsilon/"; cp "$ROOT/skills/epsilon/bin/"* "$CFG/skills/epsilon/bin/"
chmod 644 "$CFG/skills/epsilon/bin/run.sh"  # a hand-made live copy; a fresh install could not reach this
t_has "a mode-only difference reports DRIFTED" "$(run)" "epsilon: DRIFTED"
run epsilon --apply >/dev/null
t_eq "installing repairs the exec bit" yes "$([ -x "$CFG/skills/epsilon/bin/run.sh" ] && echo yes)"
t_eq "a plain data file stays non-executable" no "$([ -x "$CFG/skills/epsilon/bin/notes.txt" ] && echo yes || echo no)"
t_hasnt "a repaired skill no longer reports DRIFTED" "$(run)" "epsilon: DRIFTED"

t_section "a box-only __pycache__ is not a difference (#702)"
mkdir -p "$ROOT/skills/alpha/build"; echo 'print(1)' > "$ROOT/skills/alpha/build/m.py"
rm -rf "$CFG/skills/alpha"; run alpha --apply >/dev/null
mkdir -p "$CFG/skills/alpha/build/__pycache__"; echo x > "$CFG/skills/alpha/build/__pycache__/m.pyc"
t_has "a box-only cache leaves the skill current" "$(run)" "ok: alpha: current"
printf 'body v3\n' >> "$ROOT/skills/alpha/SKILL.md"
t_eq "a re-install beside a box-only cache" 0 "$(rc alpha --apply)"

t_section "box-only files: the dry run predicts the failure, --accept-loss moves the old copy into the backup"
echo 'box note' > "$CFG/skills/alpha/NOTES.md"; printf 'body v4\n' >> "$ROOT/skills/alpha/SKILL.md"
t_eq "a dry run over box-only files exits 1" 1 "$(rc alpha)"
t_has "...naming the file" "$(run alpha)" "FAIL: alpha: the installed copy holds 1 file(s) the repo does not (/NOTES.md)"
t_eq "the apply refuses too, and leaves the file" "1 box note" "$(rc alpha --apply) $(cat "$CFG/skills/alpha/NOTES.md")"
t_eq "with --accept-loss the install goes through" 0 "$(rc alpha --apply --accept-loss)"
t_eq "...byte-identical to the source" same "$(same alpha)"
t_eq "...with the box-only file in the backup, not deleted" "box note" "$(find "$CFG/backups/skills-install" -path '*/skills/alpha/NOTES.md' -exec cat {} + 2>/dev/null)"
t_eq "...and gone from the installed skill" gone "$(gone "$CFG/skills/alpha/NOTES.md")"

t_section "the interface, the dry-run shape deploy reads, and a rename's old dir in the backup"
t_eq "a positional target is still a name, but a second one is a usage error" 2 "$(rc alpha beta)"
t_eq "an unknown flag is a usage error" 2 "$(rc --bogus)"
t_eq "a name and --all together are a usage error" 2 "$(rc alpha --all)"
t_eq "no target is a usage error" 2 "$(sh "$ROOT/bin/skill-install.sh" alpha >/dev/null 2>&1; echo $?)"
t_eq "CLAUDE_CONFIG_DIR naming another dir is a usage error" 2 "$(CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" sh "$ROOT/bin/skill-install.sh" --dir "$CFG" >/dev/null 2>&1; echo $?)"
printf 'body v5\n' >> "$ROOT/skills/alpha/SKILL.md"; rm -rf "$CFG/skills/beta"
DRY="$(sh "$ROOT/bin/skill-install.sh" --dir "$CFG" --all 2>&1)"
t_has "--all dry run: a drifted skill is would update" "$DRY" "  note: alpha: would update (drifted)"
t_has "--all dry run: an absent one is would install" "$DRY" "  note: beta: would install (absent)"
t_has "--all dry run: a current one is ok" "$DRY" "  ok: epsilon: current"
t_has "--all dry run: ends with its apply command" "$DRY" "  note: next: sh $ROOT/bin/skill-install.sh --apply --all --dir '$(cd "$CFG" && pwd -P)'"
CDRY="$(HOME="$T_TMP/ch3" CLAUDE_CONFIG_DIR="$T_TMP/ch3/elsewhere" sh "$SUT" commands --all --dir "$T_TMP/ch3/elsewhere" 2>&1)"
t_has "commands dry run: the same shapes" "$CDRY" "  ok: harbor-merge: current"
mkdir -p "$CFG/skills/OldAlpha"; echo old > "$CFG/skills/OldAlpha/SKILL.md"
t_eq "a rename applies" 0 "$(rc alpha --apply --from-old OldAlpha)"
t_eq "...the old dir is gone from the skills dir" gone "$(gone "$CFG/skills/OldAlpha")"
t_eq "...and kept in the backup, not deleted" old "$(find "$CFG/backups/skills-install" -path '*/skills/OldAlpha/SKILL.md' -exec cat {} + 2>/dev/null)"
LOGF="$(sh "$ROOT/bin/skill-install.sh" --dir "$CFG" alpha --apply 2>&1 | tail -1 | sed -n 's/^log: //p')"
t_has "every apply names its log, in backups/skills-install/<TS>/" "$LOGF" "$(cd "$CFG" && pwd -P)/backups/skills-install/"
t_has "...which holds the run" "$(cat "$LOGF" 2>/dev/null)" "  ok: alpha: current"

t_section "every install is a row of .harbor-manifest (install standard §3)"
MF="$CFG/.harbor-manifest"
t_eq "an apply run recorded the skill's files" "$(git hash-object "$CFG/skills/alpha/SKILL.md") 100644 skills/alpha/SKILL.md skills-install -" \
  "$(grep ' skills/alpha/SKILL.md ' "$MF")"
t_eq "...one row per file, every file of the skill" "$(cd "$CFG" && find skills/alpha -type f ! -name '*.pyc' ! -path '*__pycache__*' | wc -l | tr -d ' ')" \
  "$(grep -c ' skills/alpha/' "$MF")"
t_eq "...and the renamed-away dir has no row left" 0 "$(grep -c ' skills/OldAlpha/' "$MF")"
mkdir -p "$ROOT/skills/legacy"; printf -- '---\nname: legacy\ndescription: "L"\n---\n' > "$ROOT/skills/legacy/SKILL.md"
run legacy --apply >/dev/null
t_eq "a skill installed under its old name has rows" 1 "$(grep -c ' skills/legacy/SKILL.md ' "$MF")"
mv "$ROOT/skills/legacy" "$ROOT/skills/renamed"; sed -i '' 's/name: legacy/name: renamed/' "$ROOT/skills/renamed/SKILL.md"
run renamed --apply --from-old legacy >/dev/null
t_eq "...a rename drops them, with the old dir it moved into the backup" 0 "$(grep -c ' skills/legacy/' "$MF")"
t_eq "...and records the new name" 1 "$(grep -c ' skills/renamed/SKILL.md ' "$MF")"
_mfb="$(cat "$MF")"; sh "$ROOT/bin/skill-install.sh" --dir "$CFG" alpha >/dev/null 2>&1
t_eq "a dry run leaves the manifest as it was" "$_mfb" "$(cat "$MF")"
mkdir -p "$ROOT/skills/retiree" "$ROOT/skills/kept"
printf -- '---\nname: retiree\ndescription: "R"\n---\n' > "$ROOT/skills/retiree/SKILL.md"
printf -- '---\nname: kept\ndescription: "K"\n---\n' > "$ROOT/skills/kept/SKILL.md"
run retiree --apply >/dev/null; run kept --apply >/dev/null
rm -rf "$ROOT/skills/retiree" "$CFG/skills/retiree" "$CFG/skills/kept"
_mfb="$(cat "$MF")"; run --all >/dev/null
t_eq "a dry --all leaves a retired skill's rows" "$_mfb" "$(cat "$MF")"
run --all --apply >/dev/null
t_eq "--all --apply drops the rows of a skill retired from the repo and gone from disk" 0 "$(grep -c ' skills/retiree/' "$MF")"
t_eq "...keeps a still-tracked skill's rows (it is reinstalled)" 1 "$(grep -c ' skills/kept/SKILL.md ' "$MF")"
mkdir -p "$ROOT/skills/boxonly"; printf -- '---\nname: boxonly\ndescription: "B"\n---\n' > "$ROOT/skills/boxonly/SKILL.md"
run boxonly --apply >/dev/null; rm -rf "$ROOT/skills/boxonly"; run --all --apply >/dev/null
t_eq "...and keeps a retired skill's rows while its dir is still on disk" 1 "$(grep -c ' skills/boxonly/SKILL.md ' "$MF")"
rm -rf "$ROOT/skills/kept" "$CFG/skills/boxonly"; run --all --apply >/dev/null
cmd "$T_TMP/ch3" "$T_TMP/ch3/elsewhere" --apply --dir "$T_TMP/ch3/elsewhere" >/dev/null
t_has "a command install is a row too" "$(cat "$T_TMP/ch3/elsewhere/.harbor-manifest")" " commands/gate-merge.md skills-install "

t_section "harbor#641: box-only files that an install recorded are no loss; the rest still are"
mkdir -p "$ROOT/skills/omega/refs"
printf -- '---\nname: omega\ndescription: "O"\n---\n' > "$ROOT/skills/omega/SKILL.md"; printf 'old ref\n' > "$ROOT/skills/omega/refs/old.md"
run omega --apply >/dev/null
rm -rf "$ROOT/skills/omega/refs"; printf 'moved\n' > "$ROOT/skills/omega/new.md"  # the repo moved it
t_eq "a dry run over a file the repo dropped, which the manifest recorded, exits 0" 0 "$(rc omega)"
t_has "...saying the install moves it into the backup" "$(run omega)" "note: omega: the installed copy's extra files are older commits or install records"
t_eq "the apply needs no --accept-loss" 0 "$(rc omega --apply)"
t_eq "...lands byte-identical" same "$(same omega)"
t_eq "...with the dropped file in the backup, not deleted" "old ref" "$(find "$CFG/backups/skills-install" -path '*/skills/omega/refs/old.md' -exec cat {} + 2>/dev/null | head -1)"
t_eq "...and its row gone from the manifest" 0 "$(grep -c ' skills/omega/refs/old.md ' "$MF")"
printf 'mine\n' > "$CFG/skills/omega/MINE.md"; printf 'v2\n' >> "$ROOT/skills/omega/new.md"
t_eq "a box-only file in no commit and no record is still refused" 1 "$(rc omega)"
t_has "...naming it" "$(run omega)" "FAIL: omega: the installed copy holds 1 file(s) the repo does not (/MINE.md)"
t_done
