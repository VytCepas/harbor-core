#!/usr/bin/env sh
# deploy.sh --prune (install standard §5): every leftover class is found by code and MOVED into
# backups/pruned-<TS>/ (a dry run unless --apply), box-only bytes are never taken for a leftover,
# a bin/ file moves with its B6 pin, and a second pass deletes pruned-* dirs older than 30 days.
# The throwaway repo is deploy-test's (deploy-fixture.sh), with history added and the REAL
# drift-install.sh, whose "deleted from the repo" rows are what the first class reads.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY  # a run inside a session or a deploy must not decide a case
T_TMP="$(cd "$T_TMP" && pwd -P)"  # deploy reports the config dir physically (install-lib's il_target)
. "$(dirname "$0")/../../install/deploy-fixture.sh"
yn() { if "$@"; then echo yes; else echo no; fi; }
tree() { (cd "$1" && find . -print | LC_ALL=C sort | while IFS= read -r f; do if [ -L "$f" ]; then echo "$f -> $(readlink "$f")"; elif [ -f "$f" ]; then cksum "$f"; else echo "$f"; fi; done) | cksum; }
g() { git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
ship() { # <path> <bytes> — commit a file into the repo's history and push
  mkdir -p "$REPO/$(dirname "$1")"; printf '%s\n' "$2" > "$REPO/$1"; g add -- "$1"; g commit -qm "ship $1"; g push -q origin main
}
retire() { g rm -q -r -- "$1"; g commit -qm "retire $1"; g push -q origin main; }  # <path>
ago() { date -v-"$1"d +%Y%m%d%H%M 2>/dev/null || date -d "$1 days ago" +%Y%m%d%H%M; }  # <days> → touch -t
old() { touch -t "$(ago 60)" "$@"; }
pruned() { ls -d "$C"/backups/pruned-2* 2>/dev/null | grep -v -e pruned-20250101-000000 -e pruned-20260920-000000 | tail -1; }  # this run's

build() { # <case> — a box holding one leftover of every class, and the controls beside them
  fixture "$1"
  cp "$T_ROOT/bin/drift-install.sh" "$REPO/bin/drift-install.sh"; g add bin/drift-install.sh; g commit -qm real-drift; g push -q origin main
  ship bin/old-tool.sh 'old tool v1'; retire bin/old-tool.sh
  ship bin/old-edited.sh 'edited v1'; retire bin/old-edited.sh
  ship skills/oldskill/SKILL.md 'old skill'; printf 'ref\n' > "$REPO/skills/oldskill/ref.md"; g add skills/oldskill; g commit -qm ref; g push -q origin main
  retire skills/oldskill
  ship skills/oldmixed/SKILL.md 'mixed'; retire skills/oldmixed
  ship skills/KeepMe/SKILL.md 'keep me'
  g mv skills/KeepMe skills/tmp-keep; g mv skills/tmp-keep skills/keepme; g commit -qm 'rename KeepMe'; g push -q origin main
  ship commands/gone.md 'gone v1'; retire commands/gone.md
  ship bin/gone-row.sh 'gone row'; retire bin/gone-row.sh; ship commands/kept-row.md 'still shipped'
  mkdir -p "$REPO/contracts"; printf 'name\troot\trel\nidea\tHARBOR_REPO\tbin/idea\n' > "$REPO/contracts/shims.tsv"
  g add contracts; g commit -qm shims; g push -q origin main
  # the box
  mkdir -p "$C/bin" "$C/skills/oldskill" "$C/skills/oldmixed" "$C/skills/KeepMe" "$C/commands" "$C/backups/floor-install"
  printf 'old tool v1\n' > "$C/bin/old-tool.sh"; printf 'pin\n' > "$C/.helm-pins/old-tool.sh.sha256"
  printf 'edited on the box\n' > "$C/bin/old-edited.sh"
  printf 'never committed\n' > "$C/bin/mine.sh"
  printf 'old skill\n' > "$C/skills/oldskill/SKILL.md"; printf 'ref\n' > "$C/skills/oldskill/ref.md"
  printf 'mixed\n' > "$C/skills/oldmixed/SKILL.md"; printf 'box only\n' > "$C/skills/oldmixed/notes.md"
  printf 'keep me\n' > "$C/skills/KeepMe/SKILL.md"
  printf 'gone v1\n' > "$C/commands/gone.md"
  printf '# .harbor-manifest\n%s 100644 commands/gone.md skills-install -\n' "$(git hash-object "$C/commands/gone.md")" > "$C/.harbor-manifest"
  printf '%s 100644 bin/gone-row.sh runtime-install -\n%s 100644 commands/kept-row.md skills-install -\n' abc abc >> "$C/.harbor-manifest"
  printf 'x\n' > "$C/.helm-baseline"; : > "$C/backups/config-baseline-20260801-000000.tgz"
  printf 'bp\n' > "$C/bin/baseline-pin.sh"; printf 'bppin\n' > "$C/.helm-pins/baseline-pin.sh.sha256"
  printf '{}\n' > "$C/settings.json.bak.20260801T000000Z"
  for _i in 01 02 03 04 05 06 07 08 09 10 11 12; do mkdir -p "$C/backups/floor-install/20260801-0000$_i"; done
  old "$C"/backups/floor-install/2*; touch "$C/backups/floor-install/20260801-000002"
  for _i in 01 02 03 04 05 06 07 08 09 10 11; do mkdir -p "$C/backups/deploy-202608$_i-000000-1"; done; old "$C"/backups/deploy-2*
  mkdir -p "$C/backups/pruned-20250101-000000/x" "$C/backups/pruned-20260920-000000/y"
  touch -t "$(ago 40)" "$C/backups/pruned-20250101-000000"; touch -t "$(ago 10)" "$C/backups/pruned-20260920-000000"
  mkdir -p "$H/.local/share/project-init"; git init -q "$H/.local/share/project-init"
  ln -s "$T/nowhere" "$H/.local/bin/gone"
  printf '#!/bin/sh\n' > "$C/bin/idea"; ln -s "$C/bin/idea" "$H/.local/bin/idea"
}

t_section "a dry run lists every leftover, and moves nothing"
build dry; BEFORE="$(tree "$H")"
run '' --prune --live
t_eq "the dry run" 0 "$RC"
t_eq "...writes nothing in HOME: the config dir, ~/.local/bin, ~/.local/share" "$BEFORE" "$(tree "$H")"
for _w in "$C/.helm-baseline" "$C/backups/config-baseline-20260801-000000.tgz" "$C/bin/baseline-pin.sh" \
          "$C/.helm-pins/baseline-pin.sh.sha256" "$C/bin/old-tool.sh" "$C/.helm-pins/old-tool.sh.sha256" \
          "$C/skills/oldskill" "$C/commands/gone.md" "$C/settings.json.bak.20260801T000000Z" \
          "$C/backups/floor-install/20260801-000001" "$C/backups/deploy-20260801-000000-1" \
          "$H/.local/share/project-init" "$H/.local/bin/gone" "$H/.local/bin/idea"; do
  t_has "would move ${_w#"$T"/}" "$(out)" "  note: would move $_w ("
done
t_has "a manifest row for a file gone from the box and the repo would be dropped" "$(out)" "  note: would drop the manifest row bin/gone-row.sh ("
t_eq "...a row for a path the repo still ships would not" 0 "$(out | grep -c 'manifest row commands/kept-row.md')"
t_has "...and would delete a pruned-* dir older than 30 days" "$(out)" "  note: would delete $C/backups/pruned-20250101-000000"
t_has "its next step is the apply, spelled for its gate" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --prune --live"

t_section "--apply moves every leftover into backups/pruned-<TS>/, at its own path"
build apply; run '' --apply --prune --live; P="$(pruned)"
t_eq "the apply" 0 "$RC"
t_eq "...made one pruned-<TS> dir" yes "$(yn [ -d "$P" ])"
for _m in .helm-baseline backups/config-baseline-20260801-000000.tgz bin/old-tool.sh skills/oldskill/ref.md commands/gone.md \
          settings.json.bak.20260801T000000Z backups/floor-install/20260801-000001 backups/deploy-20260801-000000-1; do
  t_eq "$_m moved, not deleted" "no yes" "$(yn [ -e "$C/$_m" ]) $(yn [ -e "$P/$_m" ])"
done
t_eq "baseline-pin.sh and its B6 pin moved together" "no no yes yes" \
  "$(yn [ -e "$C/bin/baseline-pin.sh" ]) $(yn [ -e "$C/.helm-pins/baseline-pin.sh.sha256" ]) $(yn [ -e "$P/bin/baseline-pin.sh" ]) $(yn [ -e "$P/.helm-pins/baseline-pin.sh.sha256" ])"
t_eq "...so did a retired tool and its pin" "no yes" "$(yn [ -e "$C/.helm-pins/old-tool.sh.sha256" ]) $(yn [ -e "$P/.helm-pins/old-tool.sh.sha256" ])"
t_eq "the project-init clone moved under HOME/" "no yes" "$(yn [ -e "$H/.local/share/project-init" ]) $(yn [ -d "$P/HOME/.local/share/project-init/.git" ])"
t_eq "the dangling link moved, as a link" "no $T/nowhere" "$(yn [ -L "$H/.local/bin/gone" ]) $(readlink "$P/HOME/.local/bin/gone")"
t_eq "the double-owned shim moved" "no $C/bin/idea" "$(yn [ -L "$H/.local/bin/idea" ]) $(readlink "$P/HOME/.local/bin/idea")"
t_has "...and the one-component deploy that links its owner back is the next step" "$(out)" "  note: next: sh '$REPO/bin/deploy.sh' --apply --only shim --live"
t_eq "the moved command's manifest row is dropped (§3)" 0 "$(grep -c ' commands/gone.md ' "$C/.harbor-manifest")"
t_eq "the stale row is dropped, and nothing was moved for it" "0 no" "$(grep -c ' bin/gone-row.sh ' "$C/.harbor-manifest") $(yn [ -e "$P/bin/gone-row.sh" ])"
t_eq "...a row the repo still ships is kept (the next install rewrites it)" 1 "$(grep -c ' commands/kept-row.md ' "$C/.harbor-manifest")"
t_eq "the pruned-* dir older than 30 days is deleted" no "$(yn [ -e "$C/backups/pruned-20250101-000000" ])"
t_eq "...and one moved there 10 days ago stays" yes "$(yn [ -d "$C/backups/pruned-20260920-000000/y" ])"
t_has "the run keeps its log" "$(dlog)" "  ok: moved $C/bin/old-tool.sh -> $P/bin/old-tool.sh"
t_eq "...and ends naming it" "log: $(ls "$C"/backups/deploy/*/log | head -1)" "$(tail -1 "$T/out.txt")"

t_section "what is kept: box-only bytes, a live skill under another letter case, retention"
t_eq "a retired path whose bytes are in no commit stays" yes "$(yn [ -f "$C/bin/old-edited.sh" ])"
t_has "...said with a skip line" "$(out)" "  skip: $C/bin/old-edited.sh: the repo once had this path, but these bytes are in no commit"
t_eq "a file in no commit of any path stays, unmentioned" "yes" "$(yn [ -f "$C/bin/mine.sh" ])"
t_eq "a retired skill holding a box-only file stays whole" "yes yes" "$(yn [ -f "$C/skills/oldmixed/notes.md" ]) $(yn [ -f "$C/skills/oldmixed/SKILL.md" ])"
t_eq "a live skill under its old letter case stays (one dir on a case-insensitive volume)" yes "$(yn [ -f "$C/skills/KeepMe/SKILL.md" ])"
t_eq "the newest 10 runs of an installer stay" 10 "$(ls -d "$C"/backups/floor-install/20260801-0000* | grep -cE '0000(0[3-9]|1[0-2])$')"
t_eq "...and so does an older one younger than 7 days" yes "$(yn [ -d "$C/backups/floor-install/20260801-000002" ])"
t_eq "...the 11th legacy snapshot of deploy goes, the 10 newest stay" "no 10" \
  "$(yn [ -e "$C/backups/deploy-20260801-000000-1" ]) $(ls -d "$C"/backups/deploy-2* | grep -c .)"
t_eq "settings.json stays" "{}" "$(cat "$C/settings.json")"
t_eq "the managed shim link stays" "$REPO/bin/harbor" "$(readlink "$H/.local/bin/harbor")"

t_section "a clone something still runs is kept; a second prune finds nothing"
build used; ln -s "$H/.local/share/project-init/install.sh" "$H/.local/bin/pi-boot"; : > "$H/.local/share/project-init/install.sh"
run '' --apply --prune --live
t_eq "a clone a link in ~/.local/bin runs" yes "$(yn [ -d "$H/.local/share/project-init/.git" ])"
t_has "...stays, naming that link" "$(out)" "still runs it, kept"
run '' --apply --prune --live
t_eq "a second prune" 0 "$RC"
t_hasnt "...moves nothing more" "$(out)" "  ok: moved "

t_section "refused up front, and the prune's own gates"
build cc; BEFORE="$(tree "$C")"; CC=1 run '' --apply --prune --live; CC=''
t_eq "--apply --prune inside a Claude session" 1 "$RC"
t_has "...is refused up front" "$(out)" "refused up front: running inside a Claude session"
t_eq "...with the prune's own command as the fix" "  fix: sh '$REPO/bin/deploy.sh' --apply --prune --live" "$(grep -A1 'refused up front' "$T/out.txt" | sed -n 2p)"
t_eq "...and nothing moved (outside its log)" "$(printf '%s' "$BEFORE")" "$(rm -rf "$C/backups/deploy"; tree "$C")"
build dirty; echo x > "$REPO/stray"; run '' --prune --live
t_eq "a dirty checkout, which the leftovers are judged against" 1 "$RC"; t_has "...is refused" "$(out)" "PREFLIGHT FAILED"
run '' --prune --with-b6 --live; t_eq "--prune with an opt-in is a usage error" 2 "$RC"
_pc="$(awk '/^# ── PRUNE/{p=1} /^# ── MAIN/{p=0} p && !/^[[:space:]]*#/' "$T_ROOT/bin/deploy.sh")"
t_eq "the prune code deletes with rm in one place only: the 30-day pass over pruned-* dirs" 1 "$(printf '%s\n' "$_pc" | grep -cE '(^|[^a-z_])rm -')"
t_has "...that one" "$(printf '%s\n' "$_pc" | grep -E '(^|[^a-z_])rm -')" 'rm -rf "$_o"'
t_done
