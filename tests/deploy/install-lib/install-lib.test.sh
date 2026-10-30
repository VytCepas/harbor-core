#!/usr/bin/env sh
# bin/deploy-install-lib.sh, the install standard's shared half (harbor#765, harbor#771): the argument parser, the
# target resolver, backups, the atomic JSON write and the dry-run exit rule. Each case runs a tiny tool that
# sources library-log.sh and deploy-install-lib.sh, then reads its stdout, stderr, exit code and files.
set -u
. "$(dirname "$0")/../../lib/core.sh"; t_init
LOGL="$T_ROOT/bin/library-log.sh"; IL="$T_ROOT/bin/deploy-install-lib.sh"; W="$T_TMP/w"; mkdir -p "$W"
LIVE="$HOME/.claude"; mkdir -p "$LIVE"; SB="$T_TMP/sb"; mkdir -p "$SB"
unset CLAUDE_CONFIG_DIR CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY  # a run inside a session or a deploy must not decide a case
mk() { # <body> — the tool is $W/demo.sh; its header is the usage il_usage prints
  printf '#!/bin/sh\n# demo — a tool on the install standard.\n#   sh demo.sh [--apply] (--live | --dir PATH)\n\nset -eu\n. "%s"\n. "%s"\nlog_init demo\n%s\n' \
    "$LOGL" "$IL" "$1" > "$W/demo.sh"
}
run() { sh "$W/demo.sh" "$@" > "$W/out" 2> "$W/err"; RC=$?; }  # fills $W/out, $W/err, $RC
# VAR=x before a function call persists after it in a POSIX shell, so an env case goes through env(1).
envrun() { _e="$1"; shift; env "$_e" sh "$W/demo.sh" "$@" > "$W/out" 2> "$W/err"; RC=$?; }
out() { cat "$W/out"; }
err() { cat "$W/err"; }
yn()  { "$@" && echo yes || echo no; }
PARSE='il_parse "$@"; il_target; printf "apply=%s live=%s loss=%s target=%s argv=[%s]\n" "$IL_APPLY" "$IL_LIVE" "$IL_ACCEPT_LOSS" "$IL_TARGET" "$IL_ARGV"'

t_section "il_parse: every flag in any position, --dir PATH, and nothing positional"
mk "$PARSE"
SBP="$(cd "$SB" && pwd -P)"
run --dir "$SB"
t_eq 'the default is a dry run of the --dir target' "apply=0 live=0 loss=0 target=$SBP argv=[]" "$(out)"
run --accept-loss --dir "$SB" --apply
t_eq 'order does not matter' "apply=1 live=0 loss=1 target=$SBP argv=[]" "$(out)"
run --live
t_eq '--live targets $HOME/.claude' "apply=0 live=1 loss=0 target=$(cd "$LIVE" && pwd -P) argv=[]" "$(out)"
run --dir "$SB" --bogus;           t_eq 'an unknown flag after a valid one exits 2' 2 "$RC"
t_has '...names it on stderr' "$(err)" 'demo: unknown flag: --bogus'
t_has '...and prints the usage from the header' "$(err)" 'sh demo.sh [--apply] (--live | --dir PATH)'
t_eq '...and nothing on stdout' '' "$(out)"
run --bogus --dir "$SB";           t_eq 'an unknown flag before one exits 2' 2 "$RC"
run "$SB";                          t_eq 'a positional target exits 2' 2 "$RC"
t_has '...and says there is none' "$(err)" 'there is no positional target'
run --dir "$SB" "$SB";              t_eq 'a stray operand after --dir exits 2' 2 "$RC"
run --dir;                          t_eq '--dir with no value exits 2' 2 "$RC"
run --dir --apply;                  t_eq '--dir followed by a flag exits 2' 2 "$RC"
t_has '...naming the flag it was given' "$(err)" '--dir needs a value, not the flag --apply'
run --dir '';                       t_eq '--dir with an empty value exits 2' 2 "$RC"
run --dir "$SB" --dir "$SB";        t_eq '--dir twice exits 2' 2 "$RC"
run --live --dir "$SB";             t_eq '--live and --dir together exit 2' 2 "$RC"
run --apply;                        t_eq 'no target exits 2' 2 "$RC"
t_has '...and names both ways to give one' "$(err)" 'no target: give --live or --dir PATH'
run;                                t_eq 'no arguments at all exits 2' 2 "$RC"
run --apply --dir "$SB" -h;         t_eq '-h in any position exits 0' 0 "$RC"
t_has '...printing the header' "$(out)" 'demo — a tool on the install standard.'
t_hasnt '...and doing no work' "$(out)" 'apply='
run --help;                         t_eq '--help exits 0 with no target' 0 "$RC"

t_section "il_opt: a tool's own words, flags and flag values"
mk 'il_opt() { case "$1" in --with-x) X=1; IL_TAKE=1 ;; --from) il_value --from "$2"; FROM="$2"; IL_TAKE=2 ;; commands) K=c; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
X=0; FROM=-; K=-
'"$PARSE"'; printf "x=%s from=%s k=%s\n" "$X" "$FROM" "$K"; printf "cmd=%s\n" "$(il_cmd --apply)"'
run --with-x --dir "$SB" --from 'a b' commands
t_has 'a tool flag is consumed' "$(out)" 'x=1 from=a b k=c'
t_has '...and kept, quoted, for the command a hint respells' "$(out)" "argv=[--with-x --from 'a b' commands]"
t_eq 'il_cmd keeps the tool args and respells the target' \
  "cmd=sh $W/demo.sh --apply --with-x --from 'a b' commands --dir '$SBP'" "$(tail -1 "$W/out")"
mk 'il_opt() { case "$1" in --check|--dry-run) M="$1"; IL_TAKE=-1 ;; --keep) IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }; M=-
il_parse "$@"; il_target; printf "m=%s argv=[%s] cmd=%s\n" "$M" "$IL_ARGV" "$(il_cmd --apply)"'
run --check --keep --dir "$SB"
t_eq 'IL_TAKE=-1 consumes a mode word that il_cmd must not replay' "m=--check argv=[--keep] cmd=sh $W/demo.sh --apply --keep --dir '$SBP'" "$(out)"
mk 'il_opt() { case "$1" in --with-x) X=1; IL_TAKE=1 ;; --from) il_value --from "$2"; FROM="$2"; IL_TAKE=2 ;; commands) K=c; IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }
X=0; FROM=-; K=-
'"$PARSE"
run --dir "$SB" --from;             t_eq 'a tool flag with no value exits 2' 2 "$RC"
t_has '...said by il_value' "$(err)" '--from needs a value'
run --dir "$SB" --with-y;           t_eq 'an arg il_opt does not take exits 2' 2 "$RC"
mk "$PARSE"
run --with-x --dir "$SB";           t_eq 'with no il_opt, every tool flag is unknown' 2 "$RC"

t_section "il_target: physical paths, the live dir only by --live, and CLAUDE_CONFIG_DIR never picks it"
mk "$PARSE"
for spell in "$LIVE/" "$LIVE/." "$LIVE//" "$HOME/./.claude"; do
  run --apply --dir "$spell"
  t_eq "--dir $spell is the live dir: refused, exit 1" 1 "$RC"
done
t_has '...with a FAIL naming the gate and the dir' "$(out)" "  FAIL: refusing the live dir without an explicit --live: --dir $HOME/./.claude is "
t_has '...and a fix that passes the gate' "$(out)" "  fix: sh $W/demo.sh --apply --live"
t_has '...then the summary' "$(out)" 'demo: 0 ok, 1 failed, 0 warnings'
t_hasnt '...and no work' "$(out)" 'apply='
ln -s "$LIVE" "$T_TMP/via-link"
run --dir "$T_TMP/via-link";         t_eq 'a symlink to the live dir is the live dir, refused' 1 "$RC"
t_eq 'the refused apply wrote nothing into the live dir' '' "$(ls -A "$LIVE")"
run --dir "$SB/"
t_has 'a trailing slash on a sandbox is the sandbox' "$(out)" "target=$SBP "
envrun CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" --dir "$SB"
t_eq 'CLAUDE_CONFIG_DIR set and different exits 2' 2 "$RC"
t_has '...saying it never picks the target' "$(err)" 'CLAUDE_CONFIG_DIR is '"$T_TMP/elsewhere"', not the target'
envrun CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" --live
t_eq '...for --live too: the env does not redirect it' 2 "$RC"
envrun CLAUDE_CONFIG_DIR="$SB/" --dir "$SB"
t_eq 'CLAUDE_CONFIG_DIR naming the same dir (a slash apart) is accepted' 0 "$RC"
envrun CLAUDE_CONFIG_DIR='' --dir "$SB"
t_eq 'an empty CLAUDE_CONFIG_DIR is unset' 0 "$RC"
mk 'IL_ENV=HARBOR_TEST_X; '"$PARSE"
envrun HARBOR_TEST_X="$T_TMP/elsewhere" --dir "$SB"; t_eq 'IL_ENV names the variable that must agree' 2 "$RC"
envrun CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" --dir "$SB"; t_eq '...and only that one' 0 "$RC"
mk 'IL_ENV=; '"$PARSE"
envrun CLAUDE_CONFIG_DIR="$T_TMP/elsewhere" --dir "$SB"; t_eq 'an empty IL_ENV checks none' 0 "$RC"
mkdir -p "$T_TMP/lbin"
mk 'IL_LIVE_DIR="$HOME/lbin-link"; '"$PARSE"
ln -s "$T_TMP/lbin" "$HOME/lbin-link"
run --dir "$T_TMP/lbin"; t_eq 'IL_LIVE_DIR moves the live dir, physically compared' 1 "$RC"
run --live; t_has '...and --live targets it' "$(out)" "target=$(cd "$T_TMP/lbin" && pwd -P) "

t_section "il_spell and il_cmd: the spelling every printed hint uses"
mk 'il_parse "$@"; il_target; printf "[%s]\n" "$(il_spell)" "$(il_cmd)" "$(il_cmd --apply)" "$(il_cmd --accept-loss)"'
SP="$T_TMP/a b"; mkdir -p "$SP"; SPP="$(cd "$SP" && pwd -P)"
run --dir "$SP"
t_eq 'a dir target is quoted, and a dry run adds only what is asked' \
  "$(printf '[%s]\n' "--dir '$SPP'" "sh $W/demo.sh --dir '$SPP'" "sh $W/demo.sh --apply --dir '$SPP'" \
     "sh $W/demo.sh --dir '$SPP' --accept-loss")" "$(out)"
run --live --apply --accept-loss
t_eq 'a live apply keeps --apply and --accept-loss once each' \
  "$(printf '[%s]\n' '--live' "sh $W/demo.sh --apply --live --accept-loss" "sh $W/demo.sh --apply --live --accept-loss" \
     "sh $W/demo.sh --apply --live --accept-loss")" "$(out)"
QD="$T_TMP/it's"; mkdir -p "$QD"; QDP="$(cd "$QD" && pwd -P)"
run --dir "$QD"
t_has 'a quote in the path survives a paste' "$(sh -c 'printf "%s\n" '"$(sed -n 1p "$W/out" | sed 's/^\[--dir //; s/\]$//')")" "$QDP"
mk 'il_parse "$@"; il_target; eval "set -- $(il_spell)"; printf "%s|%s\n" "$1" "$2"'
run --dir "$SP"
t_eq 'il_spell evaluates back to the same two words' "--dir|$SPP" "$(out)"

t_section "il_run: a child tool run against this run's own target, spelled the way its gate takes it"
printf '#!/bin/sh\nfor a in "$@"; do printf "[%%s]" "$a"; done; echo\n' > "$W/argv.sh"
mk 'il_parse "$@"; il_target; il_run sh "'"$W"'/argv.sh" --apply --check'
run --dir "$SP"
t_eq 'a --dir run passes --dir and the target as one word' "[--apply][--check][--dir][$SPP]" "$(out)"
run --live
t_eq 'a --live run passes --live, never the path' "[--apply][--check][--live]" "$(out)"
mk 'il_parse "$@"; il_target; il_run sh -c "exit 7" x || printf "rc=%s\n" "$?"'
run --dir "$SP"
t_eq "the child's exit code comes back" 'rc=7' "$(out)"

t_section "an apply run's log and backups: backups/<tool>/<TS>/, the backups beside the log"
TG="$T_TMP/tg"; mkdir -p "$TG/d/sub"; printf 'one\n' > "$TG/f"; chmod 0600 "$TG/f"; printf 'x\n' > "$TG/d/sub/y"
ln -s f "$TG/lnk"
mk 'il_parse "$@"; il_target; printf "bk=%s\n" "$IL_BK" >&2
il_backup "$IL_TARGET/f"; il_backup "$IL_TARGET/d"; il_backup "$IL_TARGET/lnk"; il_backup "$IL_TARGET/absent"
printf "two\n" > "$IL_TARGET/f"; il_backup "$IL_TARGET/f"
log_ok done; log_end'
envrun LOG_TS=20260927-120000 --apply --dir "$TG"
BK="$(cd "$TG" && pwd -P)/backups/demo/20260927-120000"
t_eq 'the backup dir is the log dir' "bk=$BK" "$(err)"
t_eq 'the log is there' yes "$(yn [ -f "$BK/log" ])"
t_eq 'the last line names it' "log: $BK/log" "$(tail -1 "$W/out")"
t_eq 'a file is copied byte for byte' one "$(cat "$BK/f")"
t_eq '...with its mode' "$(ls -l "$TG/f" | cut -c1-10)" "$(ls -l "$BK/f" | cut -c1-10)"
t_eq 'a second backup in one run keeps the pre-run bytes' one "$(cat "$BK/f")"
t_eq 'a dir is copied whole' x "$(cat "$BK/d/sub/y")"
t_eq 'a link is copied as a link' 'yes f' "$(yn [ -L "$BK/lnk" ]) $(readlink "$BK/lnk")"
t_eq 'an absent path is not an error, and leaves nothing' no "$(yn [ -e "$BK/absent" ])"
t_eq 'the run exits 0' 0 "$RC"
DR="$T_TMP/dr"; mkdir -p "$DR"
mk 'il_parse "$@"; il_target; printf "bk=[%s]\n" "$IL_BK"; log_ok done; log_end'
run --dir "$DR"
t_eq 'a dry run opens no log and no backup dir' 'bk=[]' "$(head -1 "$W/out")"
t_eq '...and writes nothing' '' "$(ls -A "$DR")"
t_hasnt '...and names no log' "$(out)" 'log: '
RP="$T_TMP/rp"; mkdir -p "$RP"
mk 'il_parse "$@"; IL_LOG=0; il_target; printf "bk=[%s]\n" "$IL_BK"; log_ok cached; log_end'
run --apply --dir "$RP"
t_eq 'IL_LOG=0: an apply run of a scheduled reporter opens no log and no backup dir' 'bk=[]' "$(head -1 "$W/out")"
t_eq '...so each tick leaves nothing under backups/' '' "$(ls -A "$RP")"
mk 'il_parse "$@"; il_target; il_backup "$IL_TARGET/f" || { log_end; exit 1; }; log_ok never; log_end'
BAD="$T_TMP/bad"; mkdir -p "$BAD"; printf 'z\n' > "$BAD/f"; : > "$BAD/backups"
run --apply --dir "$BAD"
t_eq 'with no backup dir, il_backup fails the run' 1 "$RC"
t_has '...with a FAIL naming the file' "$(out)" "  FAIL: no backup dir for $(cd "$BAD" && pwd -P)/f"
t_has '...and its fix line' "$(out)" '  fix: none automatic'
t_hasnt '...before any later work' "$(out)" 'never'

t_section "il_write_json: temp, validate, mv — never a truncate in place"
J="$T_TMP/j"; mkdir -p "$J"; printf '{"a":1}\n' > "$J/s.json"; chmod 0600 "$J/s.json"
INO0="$(ls -i "$J/s.json" | awk '{print $1}')"
mk 'il_write_json "$1" "$2" && log_ok written; log_end'
sh "$W/demo.sh" '{"a":2,"b":[1]}' "$J/s.json" > "$W/out" 2>&1; RC=$?
t_eq 'valid JSON is written' 2 "$(jq .a "$J/s.json")"
t_eq '...pretty-printed by jq' "$(printf '%s\n' '{"a":2,"b":[1]}' | jq .)" "$(cat "$J/s.json")"
t_eq '...by replacing the file, not truncating it (a new inode)' yes "$(yn [ "$(ls -i "$J/s.json" | awk '{print $1}')" != "$INO0" ])"
t_eq '...keeping its mode' '-rw-------' "$(ls -l "$J/s.json" | cut -c1-10)"
t_eq '...with no temp file left' 's.json' "$(ls -A "$J")"
t_eq '...and exit 0' 0 "$RC"
cp "$J/s.json" "$T_TMP/j.before"
sh "$W/demo.sh" '{"a":' "$J/s.json" > "$W/out" 2>&1; RC=$?
t_eq 'invalid JSON leaves the file byte-identical' same "$(cmp -s "$T_TMP/j.before" "$J/s.json" && echo same || echo changed)"
t_eq '...leaves no temp file' 's.json' "$(ls -A "$J")"
t_has '...says so with a FAIL' "$(cat "$W/out")" "  FAIL: refusing to write invalid JSON to $J/s.json"
t_has '...and a fix line' "$(cat "$W/out")" '  fix: none automatic'
t_eq '...and exits 1' 1 "$RC"
sh "$W/demo.sh" 'null' "$J/s.json" > "$W/out" 2>&1; RC=$?
t_eq 'a null document is refused too' '1 same' "$RC $(cmp -s "$T_TMP/j.before" "$J/s.json" && echo same || echo changed)"
mkdir -p "$J/real"; printf '{}\n' > "$J/real/t.json"; ln -s real/t.json "$J/lnk.json"
sh "$W/demo.sh" '{"via":"link"}' "$J/lnk.json" > "$W/out" 2>&1
t_eq 'a symlinked dest is written through' link "$(jq -r .via "$J/real/t.json")"
t_eq '...and stays a link' yes "$(yn [ -L "$J/lnk.json" ])"
RO="$T_TMP/ro"; mkdir -p "$RO"; printf '{"k":0}\n' > "$RO/s.json"; chmod 0500 "$RO"
sh "$W/demo.sh" '{"k":1}' "$RO/s.json" > "$W/out" 2>&1; RC=$?
chmod 0700 "$RO"
t_eq 'an unwritable dir fails the write, exit 1' 1 "$RC"
t_eq '...leaving the file as it was' 0 "$(jq .k "$RO/s.json")"
t_has '...and says what failed' "$(cat "$W/out")" "  FAIL: "

t_section "the dry-run exit rule: exit 1 when --apply would refuse, unless the only reason is a session"
mk 'il_parse "$@"; il_target; il_refuse "the source is older than what is installed" "$(il_cmd --apply --accept-loss)"
log_note "the plan goes on"; il_stop; log_ok "wrote it"; log_end'
run --dir "$SB"
t_eq 'a dry run that predicts a refusal exits 1' 1 "$RC"
t_has '...saying what --apply would refuse' "$(out)" '  FAIL: --apply would refuse: the source is older than what is installed'
t_has '...then the fix' "$(out)" "  fix: sh $W/demo.sh --apply --dir '$SBP' --accept-loss"
t_has '...and still prints the rest of the plan' "$(out)" '  note: the plan goes on'
t_has '...ending on the summary' "$(tail -1 "$W/out")" 'demo: 1 ok, 1 failed, 0 warnings'
t_has '...having reached the work, which a dry run only describes (the control for the apply below)' "$(out)" '  ok: wrote it'
run --apply --dir "$SB"
t_eq 'the apply refuses, exit 1' 1 "$RC"
t_has '...saying refused' "$(out)" '  FAIL: refused: the source is older'
t_has '...and that nothing was written' "$(out)" '  note: nothing was written'
t_hasnt '...and stops before the work' "$(out)" 'wrote it'
t_has '...with a log naming the refusal' "$(cat "$(tail -1 "$W/out" | sed 's/^log: //')" 2>/dev/null)" 'FAIL: refused:'
mk 'il_parse "$@"; il_target; il_session "$(il_cmd --apply)"; il_stop; log_ok planned; log_end'
envrun CLAUDECODE=1 --dir "$SB"
t_eq 'inside a Claude session a dry run exits 0' 0 "$RC"
t_has '...noting the refusal and the command for a terminal' "$(out)" "  note: --apply would refuse here, inside a Claude session; from a terminal: sh $W/demo.sh --apply --dir '$SBP'"
t_hasnt '...with no FAIL' "$(out)" 'FAIL'
envrun CLAUDECODE=1 --apply --dir "$SB"
t_eq '...and its apply refuses, exit 1' 1 "$RC"
t_has '...with a FAIL and the fix' "$(out)" '  FAIL: refused: this is a Claude session'
t_hasnt '...before any work' "$(out)" 'planned'
run --apply --dir "$SB"
t_eq 'outside a session il_session is silent' 0 "$RC"
t_hasnt '...and says nothing' "$(out)" 'Claude session'
mk 'il_parse "$@"; il_target; il_session x; il_refuse "a real reason" y; log_end'
envrun CLAUDECODE=1 --dir "$SB"
t_eq 'a session AND a real reason: the dry run exits 1' 1 "$RC"

t_section "il_loss: one loss flag, --accept-loss, which names what is lost"
mk 'il_parse "$@"; il_target; il_loss "3 installed commits are not in this source" "$(il_cmd --apply --accept-loss)"; il_stop; log_ok installed; log_end'
run --apply --dir "$SB"
t_eq 'without --accept-loss a loss refuses' 1 "$RC"
t_has '...naming it' "$(out)" '  FAIL: refused: 3 installed commits are not in this source'
run --dir "$SB"
t_eq '...and the dry run predicts it' 1 "$RC"
run --apply --dir "$SB" --accept-loss
t_eq 'with --accept-loss it proceeds' 0 "$RC"
t_has '...with a WARN that names exactly what is lost' "$(out)" '  WARN: --accept-loss: 3 installed commits are not in this source'
t_has '...then does the work' "$(out)" '  ok: installed'

t_section "il_next: a next step, and #285 — none that deploy itself performs"
mk 'il_next "sh x --apply --live"; il_next --deploy-does "sh pin --apply --live"; log_end'
sh "$W/demo.sh" > "$W/out" 2>&1
t_has 'a next step prints' "$(out)" '  note: next: sh x --apply --live'
t_has '...and so does a deploy step, outside deploy' "$(out)" '  note: next: sh pin --apply --live'
HARBOR_DEPLOY_ACTIVE=1 sh "$W/demo.sh" > "$W/out" 2>&1
t_has 'under deploy the ordinary next step still prints' "$(out)" '  note: next: sh x --apply --live'
t_hasnt '...and the one deploy performs does not' "$(out)" 'sh pin --apply'

t_section "il_apply_next: a live dry run's apply goes through deploy (§4)"
mk 'il_opt() { case "$1" in --with-b6|atlas) IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }; il_parse "$@"; il_target; il_apply_next floor; log_end'
: > "$W/deploy.sh"
run --live
t_has 'on the live box it is deploy, with --only this component' "$(out)" "  note: next: sh '$W/deploy.sh' --apply --only floor --live"
run --live --with-b6 --accept-loss
t_has '...keeping an opt-in deploy takes, and --accept-loss' "$(out)" "  note: next: sh '$W/deploy.sh' --apply --only floor --with-b6 --live --accept-loss"
run --live atlas
t_has 'a word deploy does not take keeps the tool'"'"'s own command' "$(out)" "  note: next: sh $W/demo.sh --apply atlas --live"
run --dir "$SB"
t_has 'a sandbox keeps the tool'"'"'s own command' "$(out)" "  note: next: sh $W/demo.sh --apply --dir '$SBP'"
HARBOR_DEPLOY_ACTIVE=1 sh "$W/demo.sh" --live > "$W/out" 2>&1
t_hasnt 'under deploy, deploy performs it, so it is not printed' "$(out)" 'next:'
mk 'il_opt() { case "$1" in --all|commands) IL_TAKE=1 ;; *) IL_TAKE=0 ;; esac; }; il_parse "$@"; il_target; il_apply_next skills --all; log_end'
run --live --all
t_has 'a word the component implies is dropped' "$(out)" "  note: next: sh '$W/deploy.sh' --apply --only skills --live"
run --live commands --all
t_has '...and one it does not imply keeps the tool'"'"'s own command' "$(out)" "  note: next: sh $W/demo.sh --apply commands --all --live"
rm -f "$W/deploy.sh"; run --live
t_has 'an installed copy, with no deploy.sh beside it, keeps its own command' "$(out)" "  note: next: sh $W/demo.sh --apply --live"

t_section "the install manifest: one row per installed file, <git-blob> <mode> <relpath> <installer> <commit> (§3)"
MR="$T_TMP/mfrepo"; mkdir -p "$MR"; git init -q "$MR"
printf 'committed once\n' > "$MR/k.txt"
git -C "$MR" add k.txt; git -C "$MR" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm k
HEADC="$(git -C "$MR" rev-parse HEAD)"
MT="$T_TMP/mft"; mkdir -p "$MT/bin" "$MT/skills/a/__pycache__" "$MT/skills/ab" "$MT/skills/a/ref"
printf 'tool\n' > "$MT/bin/t.sh"; chmod 0755 "$MT/bin/t.sh"; printf 'doc\n' > "$MT/bin/d.txt"; chmod 0644 "$MT/bin/d.txt"
printf 'A\n' > "$MT/skills/a/SKILL.md"; printf 'r\n' > "$MT/skills/a/ref/one two.md"; printf 'c\n' > "$MT/skills/a/__pycache__/x.pyc"
printf 'y\n' > "$MT/skills/a/.DS_Store"; printf 'B\n' > "$MT/skills/ab/SKILL.md"; ln -s t.sh "$MT/bin/lnk"
MF="$(cd "$MT" && pwd -P)/.harbor-manifest"
mk 'il_parse "$@"; il_target; il_source "'"$MR"'"; il_manifest bin/t.sh bin/d.txt bin/lnk skills/a skills/ab bin/absent; il_manifest_write; log_end'
envrun LOG_TS=20260927-130000 --dir "$MT"
t_eq 'a dry run writes no manifest' no "$(yn [ -e "$MF" ])"
envrun LOG_TS=20260927-130001 --apply --dir "$MT"
t_eq 'an apply run writes it' yes "$(yn [ -f "$MF" ])"
t_eq '...and exits 0' 0 "$RC"
t_has '...saying how many files it recorded' "$(out)" "  note: recorded 6 installed file(s) in $MF"
t_eq 'its first line names the row shape' '# .harbor-manifest (install standard §3, bin/deploy-install-lib.sh): <git-blob> <mode> <relpath> <installer> <commit>' "$(head -1 "$MF")"
t_eq 'a row carries the blob git would store, the mode, the path, the installer and the commit' \
  "$(git hash-object "$MT/bin/t.sh") 100755 bin/t.sh demo $HEADC" "$(grep ' bin/t.sh ' "$MF")"
t_eq 'a file without x is 100644' "100644" "$(grep ' bin/d.txt ' "$MF" | awk '{print $2}')"
t_eq 'a link is 120000, its blob the target string' "$(printf t.sh | git hash-object --stdin) 120000 bin/lnk" "$(grep ' bin/lnk ' "$MF" | awk '{print $1, $2, $3}')"
t_eq 'a dir records every file under it, and no cache' 'skills/a/SKILL.md,skills/a/ref/one two.md,skills/ab/SKILL.md,' \
  "$(grep ' skills/' "$MF" | awk '{ r = $0; sub(/^[^ ]+ [^ ]+ /, "", r); sub(/ [^ ]+ [^ ]+$/, "", r); print r }' | tr '\n' ',')"
t_eq 'a path absent on disk gets no row' 0 "$(grep -c ' bin/absent ' "$MF")"
t_eq 'il_mf_blob reads a name with a space back' "$(git hash-object "$MT/skills/a/ref/one two.md")" \
  "$(sh -c '. "$1"; . "$2"; il_mf_blob "$3" "skills/a/ref/one two.md"' _ "$LOGL" "$IL" "$MT")"
mk 'il_parse "$@"; il_target; il_manifest bin/t.sh; il_manifest_drop skills/a; il_manifest_write; log_end'
printf 'tool v2\n' > "$MT/bin/t.sh"
envrun LOG_TS=20260927-130002 --apply --dir "$MT"
t_eq 'a later run replaces its path: one row, the new bytes, no repo so commit -' \
  "$(git hash-object "$MT/bin/t.sh") 100755 bin/t.sh demo -" "$(grep ' bin/t.sh ' "$MF")"
t_eq '...and keeps every row it did not touch' 1 "$(grep -c ' bin/d.txt ' "$MF")"
t_eq 'dropping a dir drops every row under it' 0 "$(grep -c ' skills/a/' "$MF")"
t_eq '...and not a sibling that shares its prefix' 1 "$(grep -c ' skills/ab/SKILL.md ' "$MF")"
t_eq 'the manifest it replaced is in the run'"'"'s backup' yes \
  "$(yn grep -q "$(git hash-object "$MT/skills/a/SKILL.md")" "$(cd "$MT" && pwd -P)/backups/demo/20260927-130002/.harbor-manifest")"
t_eq 'the rows stay sorted by path' "$(grep -v '^#' "$MF" | awk '{print $3}' | LC_ALL=C sort | tr '\n' ,)" "$(grep -v '^#' "$MF" | awk '{print $3}' | tr '\n' ,)"
MI="$MR/cfg-inside"; mkdir -p "$MI/bin"; printf 'x\n' > "$MI/bin/t.sh"
mk 'il_parse "$@"; il_target; il_source "'"$MR"'"; il_manifest bin/t.sh; il_manifest_write; log_end'
envrun LOG_TS=20260927-130003 --apply --dir "$MI"
t_eq 'a target inside the source checkout records no commit: that HEAD is not these bytes'"'"' source' '-' \
  "$(grep ' bin/t.sh ' "$MI/.harbor-manifest" | awk '{print $NF}')"
KN='. "$1"; . "$2"; if il_known "$3" "$4" "$5" "$6" k.txt; then echo known; else echo unknown; fi'
t_eq 'il_known: bytes the manifest records for the path are known' known \
  "$(sh -c "$KN" _ "$LOGL" "$IL" "$MT" bin/t.sh "$MT/bin/t.sh" "$MR")"
printf 'committed once\n' > "$T_TMP/kk"
t_eq '...so are bytes committed at the repo path' known "$(sh -c "$KN" _ "$LOGL" "$IL" "$MT" x/kk "$T_TMP/kk" "$MR")"
printf 'box only\n' > "$T_TMP/kb"
t_eq '...and bytes in neither are not' unknown "$(sh -c "$KN" _ "$LOGL" "$IL" "$MT" x/kb "$T_TMP/kb" "$MR")"
t_eq '...nor the recorded path'"'"'s old bytes once it is edited' unknown \
  "$(printf 'hand edit\n' > "$T_TMP/ke"; sh -c "$KN" _ "$LOGL" "$IL" "$MT" bin/t.sh "$T_TMP/ke" "$MR")"

t_section "sourcing sets nothing in the caller"
printf '#!/bin/sh\nset +eu\n. "%s"\n. "%s"\ncase $- in *u*|*e*) echo LEAK ;; *) echo clean ;; esac\n' "$LOGL" "$IL" > "$W/opts.sh"
t_eq 'no shell option leaks' clean "$(sh "$W/opts.sh" 2>&1)"
t_eq 'no terminal probe or escape code' '' "$(grep -nE 'tput|\[ -t |\\033|\\e\[' "$IL")"
t_done
