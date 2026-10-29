#!/usr/bin/env sh
# deploy-shim-install.sh must be able to refuse, and must never destroy (harbor#630); on the install standard
# (harbor#765, #771): --live or --dir, the dry-run exit rule, and a repointed link kept in the backup.
# The "live" dir is the sandbox HOME's ~/.local/bin, so a broken gate writes nowhere real.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY
SI="$T_ROOT/bin/deploy-shim-install.sh"; B="$T_TMP/bin-shims"; mkdir -p "$B"
run() { HARBOR_SCOPE_LOCAL_BIN="$B" sh "$SI" "$@" > "$T_TMP/out" 2>&1; echo $?; }  # $B is the live dir here
out() { cat "$T_TMP/out"; }
REPO="$(sh "$T_ROOT/bin/scope-roots.sh" --get HARBOR_SCOPE_REPO)"
NROWS="$(sed 's/#.*//' "$T_ROOT/contracts/shims.tsv" | awk -F'\t' 'NF>=3 && $1!="name" && $1!=""' | wc -l | tr -d ' ')"

t_section "the live dir needs --live, and there is no positional or env target"
mkdir -p "$HOME/.local/bin"
t_eq "--apply with no target is a usage error" 2 "$(sh "$SI" --apply >/dev/null 2>&1; echo $?)"
t_eq "--apply --dir onto the live dir is refused" 1 "$(sh "$SI" --apply --dir "$HOME/.local/bin" >/dev/null 2>&1; echo $?)"
t_eq "the refused run wrote nothing" "" "$(ls "$HOME/.local/bin")"
t_eq "a trailing slash is the same live dir" 1 "$(sh "$SI" --apply --dir "$HOME/.local/bin/" >/dev/null 2>&1; echo $?)"
t_eq "a positional target is a usage error" 2 "$(sh "$SI" --apply "$B" >/dev/null 2>&1; echo $?)"
t_eq "an unknown flag is a usage error" 2 "$(run --live --bogus)"

t_section "a dry run of an empty bin: every shim would be linked, and it is not a refusal"
t_eq "dry run on an empty bin" 0 "$(run --live)"
t_eq "names every missing shim as would link" "$NROWS" "$(grep -c '^  note: [^ ]*: would link -> ' "$T_TMP/out")"
t_has "...in the shape deploy reads" "$(out)" "  note: wait-for: would link -> $REPO/bin/wait-for"
t_has "...and ends on the apply, through deploy: the only live entry (install standard §4)" "$(out)" "  note: next: sh '$T_ROOT/bin/deploy.sh' --apply --only shim --live"
t_has "...while a sandbox bin keeps shim-install's own apply" "$(HARBOR_SCOPE_LOCAL_BIN="$B" sh "$SI" --dir "$T_TMP/other-bin" 2>&1)" "  note: next: sh $SI --apply --dir '"
t_eq "...and wrote nothing" "" "$(ls "$B")"

t_section "--apply creates the shims and the dry run then passes clean"
t_eq "--live --apply on an empty bin" 0 "$(run --live --apply)"
t_eq "every row is linked" "$NROWS" "$(grep -c '^  ok: [^ ]*: linked -> ' "$T_TMP/out")"
t_eq "dry run after --apply" 0 "$(run --live)"
t_eq "...with every shim current" "$NROWS" "$(grep -c '^  ok: [^ ]* -> ' "$T_TMP/out")"
t_hasnt "...and nothing left to do" "$(out)" ": would "

t_section "a mispointed shim is caught, repointed, and the old link kept"
ln -sfn /nowhere/harbor/bin/wait-for "$B/wait-for"
t_eq "dry run with a mispointed shim" 0 "$(run --live)"
t_has "reported as would repoint" "$(out)" "  note: wait-for: would repoint /nowhere/harbor/bin/wait-for -> $REPO/bin/wait-for"
t_eq "--live --apply repoints it" 0 "$(run --live --apply)"
t_eq "wait-for target" "$REPO/bin/wait-for" "$(readlink "$B/wait-for")"
LOGP="$(tail -1 "$T_TMP/out" | sed -n 's/^log: //p')"
t_has "the run's log is named last" "$LOGP" "/backups/shim-install/"
t_eq "the old link is in the backup beside the log, as a link" /nowhere/harbor/bin/wait-for "$(readlink "$(dirname "$LOGP")/wait-for" 2>/dev/null)"
t_has "...and the log records the repoint" "$(cat "$LOGP" 2>/dev/null)" "  ok: wait-for: repointed /nowhere/harbor/bin/wait-for -> $REPO/bin/wait-for"

t_section "a regular file is never replaced, and a dry run predicts the refusal"
# rm first: $B/secret is a symlink into the repo, and writing through it truncated bin/secret once (2026-09-23).
rm -f "$B/secret"; printf 'real program\n' > "$B/secret"
t_eq "a dry run over a regular file exits 1" 1 "$(run --live)"
t_has "the collision is reported in the shape deploy reads" "$(out)" "  FAIL: secret: $(cd "$B" && pwd -P)/secret is a regular file, not a shim — not touched"
t_has "...followed by its fix" "$(grep -A1 '  FAIL: secret:' "$T_TMP/out" | tail -1)" "  fix: mv '"
t_hasnt "...and no apply command is offered past it" "$(out)" "  note: next:"
t_eq "--live --apply over a regular file" 1 "$(run --live --apply)"
t_eq "the file survives" "real program" "$(cat "$B/secret")"
t_has "...and the collision is reported" "$(out)" "is a regular file, not a shim"

t_section "--dir: a bin dir that is not the live one, and the log inside it"
D="$T_TMP/other-bin"
t_eq "a dry run of a --dir that does not exist yet" 0 "$(sh "$SI" --dir "$D" >"$T_TMP/out" 2>&1; echo $?)"
t_eq "...creates nothing" no "$([ -e "$D" ] && echo yes || echo no)"
t_eq "--apply --dir creates it and links every row" 0 "$(sh "$SI" --apply --dir "$D" >"$T_TMP/out" 2>&1; echo $?)"
t_eq "...with a real link" "$REPO/bin/wait-for" "$(readlink "$D/wait-for")"
t_has "...and its log under it" "$(tail -1 "$T_TMP/out")" "log: $(cd "$D" && pwd -P)/backups/shim-install/"

t_section "a pack's shims (harbor#1149): <config dir>/shims.d/<repo-id>.tsv, each row linked to the pack's installed bin/ file"
PC="$T_TMP/pcfg"; mkdir -p "$PC/shims.d" "$PC/bin"
printf '#!/bin/sh\necho pk\n' > "$PC/bin/pk-tool"; chmod +x "$PC/bin/pk-tool"
printf '# a pack'"'"'s shims\nname\trel\npk-tool\tbin/pk-tool\n' > "$PC/shims.d/pk.tsv"
PD="$T_TMP/pack-bin"
pshim() { HARBOR_PACK_SHIMS_DIR="$PC/shims.d" sh "$SI" "$@" >"$T_TMP/out" 2>&1; echo $?; }
t_eq "a dry run with the pack's fragment is not a refusal" 0 "$(pshim --dir "$PD")"
t_has "...and says the pack's command would link, to the installed copy" "$(out)" "  note: pk-tool: would link -> $(cd "$PC" && pwd -P)/bin/pk-tool"
t_eq "--apply links core's rows and the pack's" 0 "$(pshim --apply --dir "$PD")"
t_eq "the pack's link points at the installed bin/ file" "$(cd "$PC" && pwd -P)/bin/pk-tool" "$(readlink "$PD/pk-tool")"
t_eq "...and runs it" pk "$("$PD/pk-tool")"
t_eq "core's rows are linked beside it: every row, and the pack's one" "$((NROWS + 1))" "$(grep -c '^  ok: [^ ]*: linked -> ' "$T_TMP/out")"
t_eq "a second apply is current" 0 "$(pshim --apply --dir "$PD")"
t_hasnt "...and has nothing left to do" "$(out)" ": would "
# CONTROL: with no fragment directory a --dir run links core's table alone, so the pack's row above is what put pk-tool there.
D3="$T_TMP/core-only"
t_eq "control: without HARBOR_PACK_SHIMS_DIR a --dir run links core's table alone" 0 "$(sh "$SI" --apply --dir "$D3" >"$T_TMP/out" 2>&1; echo $?)"
t_eq "...and no pack command is among them" no "$([ -e "$D3/pk-tool" ] && echo yes || echo no)"
# --live reads the live config dir's shims.d (HOME is the sandbox here)
rm -f "$B/secret"   # the regular file the section above planted would be a refusal of its own
mkdir -p "$HOME/.claude/shims.d" "$HOME/.claude/bin"; cp "$PC/shims.d/pk.tsv" "$HOME/.claude/shims.d/pk.tsv"; cp -p "$PC/bin/pk-tool" "$HOME/.claude/bin/pk-tool"
t_eq "--live reads ~/.claude/shims.d" 0 "$(run --live --apply)"
t_has "...and links the pack's command" "$(out)" "  ok: pk-tool: linked -> $(cd "$HOME/.claude" && pwd -P)/bin/pk-tool"
rm -f "$B/pk-tool" "$HOME/.claude/shims.d/pk.tsv" "$HOME/.claude/bin/pk-tool"

t_section "a pack's row never takes a name another row owns, and a link no pack lists is reported"
printf 'name\trel\nsecret\tbin/pk-tool\n' > "$PC/shims.d/clash.tsv"
D4="$T_TMP/clash-bin"
t_eq "a pack row naming a core shim is refused (exit 1)" 1 "$(pshim --apply --dir "$D4")"
t_has "...by name, with the owner" "$(out)" "  FAIL: pack clash: secret is already in the table (core), so its row is skipped"
t_eq "...and core's own link is the one that stands" "$REPO/bin/secret" "$(readlink "$D4/secret")"
rm -f "$PC/shims.d/clash.tsv"
printf 'name\trel\npk-tool\tbin/pk-tool\n' > "$PC/shims.d/two.tsv"
t_eq "two packs listing one name is refused too" 1 "$(pshim --apply --dir "$PD")"
t_has "...naming the first pack" "$(out)" "pack two: pk-tool is already in the table (another pack)"
rm -f "$PC/shims.d/two.tsv"
ln -sfn "$(cd "$PC" && pwd -P)/bin/gone-tool" "$PD/gone-tool"
t_eq "a stale link into the config dir's bin/ is a warning, not a refusal" 0 "$(pshim --dir "$PD")"
t_has "...and names the link" "$(out)" "  WARN: gone-tool -> $(cd "$PC" && pwd -P)/bin/gone-tool is a pack's command and no installed pack's shims.tsv lists it"

t_section "an unmanaged link into a repo: the repo ids are the registry's (harbor#1273)"
D6="$T_TMP/unmanaged-bin"; mkdir -p "$D6"; ln -sfn "$HOME/widget/tool" "$D6/w-tool"
REG="$T_TMP/reg"; mkdir -p "$REG"; printf 'id\tpath\tkind\tremote\nwidget\twidget\tworkload\t-\n' > "$REG/repos.tsv"
HARBOR_SCOPE_PRIVATE="$REG" sh "$SI" --dir "$D6" > "$T_TMP/out" 2>&1
t_has "a link into a registered repo is reported" "$(out)" "  WARN: w-tool -> $HOME/widget/tool is unmanaged"
HARBOR_SCOPE_PRIVATE="$T_TMP/no-layer" sh "$SI" --dir "$D6" > "$T_TMP/out" 2>&1
t_hasnt "no registry: a repo only the registry names is not guessed" "$(out)" "w-tool"
printf 'id\tpath\tkind\tremote\nbad\t../x\tworkload\t-\n' > "$REG/repos.tsv"
HARBOR_SCOPE_PRIVATE="$REG" sh "$SI" --dir "$D6" > "$T_TMP/out" 2>&1
t_has "an unreadable registry says the scan did not run" "$(out)" "were not scanned"

t_section "RED-PROOF: shim-install without the pack half does not link the pack's command"
MUT="$T_TMP/mut"; mkdir -p "$MUT"; cp -R "$T_ROOT/bin" "$T_ROOT/contracts" "$MUT/"
sed 's|for _pf in "\$PSD"/\*.tsv; do|for _pf in; do|' "$T_ROOT/bin/deploy-shim-install.sh" > "$MUT/bin/deploy-shim-install.sh"
t_exit "the mutation applies" 1 cmp -s "$MUT/bin/deploy-shim-install.sh" "$T_ROOT/bin/deploy-shim-install.sh"
D5="$T_TMP/mut-bin"
HARBOR_PACK_SHIMS_DIR="$PC/shims.d" sh "$MUT/bin/deploy-shim-install.sh" --apply --dir "$D5" >"$T_TMP/out" 2>&1
t_eq "mutated: the pack's command is not linked" no "$([ -e "$D5/pk-tool" ] && echo yes || echo no)"
t_eq "restored: it is" yes "$([ -e "$PD/pk-tool" ] && echo yes || echo no)"
t_done
