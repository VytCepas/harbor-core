#!/usr/bin/env sh
# gate-classify.sh (harbor#1018, the ship contract §2): `classify <repo-root> [paths | stdin]` prints PROTECTED lines
# and exits 1 when any path is protected. Then harbor's own register: every path the policy names, and every script an
# installer wires as a hook, is protected, derived from the installers rather than listed here.
. "$(dirname "$0")/../../lib/core.sh"; t_init
C="$T_ROOT/bin/gate-classify.sh"; W="$T_TMP/repo"
mkdir -p "$W/.agents"; printf 'repo acme/widgets\nprotected .agents/reg.tsv\n' > "$W/.agents/ship.conf"
printf 'glob\tclass\treason\nsrc/core/**\tcore\tthe core\nbin/guard-*\tguard\tguards\n# a comment\nconfig.json\tsettings\tit\n' > "$W/.agents/reg.tsv"
cls() { RC=0; OUT="$(sh "${CL:-$C}" "$W" "$@" 2>/dev/null)" || RC=$?; }

t_section "the verdict: PROTECTED lines and the exit code"
cls src/core/a/b.c docs/x.md bin/guard-x.sh config.json
t_eq "exit 1 when any is protected" 1 "$RC"
t_eq "one line per protected path, with its class" "PROTECTED	src/core/a/b.c	core
PROTECTED	bin/guard-x.sh	guard
PROTECTED	config.json	settings" "$OUT"
cls docs/x.md src/other.c
t_eq "exit 0 and no output when none is" "0:" "$RC:$OUT"
RC=0; OUT="$(printf 'docs/x.md\nbin/guard-y\n' | sh "$C" "$W" 2>/dev/null)" || RC=$?
t_eq "paths on stdin" "1:PROTECTED	bin/guard-y	guard" "$RC:$OUT"

t_section "globs: ** crosses directories, * does not"
cls bin/guard-x/y.sh
t_eq "bin/guard-* does not reach a subdirectory" 0 "$RC"
cls src/core
t_eq "src/core/** does not name the directory itself" 0 "$RC"
cls src/core/deep/er/x
t_eq "...but everything under it" 1 "$RC"

t_section "case: a path that differs from a protected one only by case is protected (macOS, review finding 4)"
cls Bin/guard-x.sh SRC/Core/a.c CONFIG.JSON .GitHub/workflows/x.yml .Agents/Ship.conf
t_eq "every case variant is protected" "guard core settings ci-gate manifest" "$(printf '%s\n' "$OUT" | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
t_eq "...and reported as spelled" "Bin/guard-x.sh" "$(printf '%s\n' "$OUT" | head -1 | cut -f2)"
mkdir -p "$T_TMP/mutc"; cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/fs-lib.sh" "$C" "$T_TMP/mutc/"
sed 's/if (lp ~ pat\[i\]) c = cls\[i\]/if (p ~ pat[i]) c = cls[i]/' "$T_ROOT/bin/gate-lib.sh" > "$T_TMP/mutc/gate-lib.sh"
t_exit "M2: the mutation applies" 1 cmp -s "$T_TMP/mutc/gate-lib.sh" "$T_ROOT/bin/gate-lib.sh"
RC=0; sh "$T_TMP/mutc/gate-classify.sh" "$W" Bin/guard-x.sh >/dev/null 2>&1 || RC=$?
t_eq "M2: matched by case, Bin/guard-x.sh is open" 0 "$RC"

t_section "always protected, whatever the register says"
cls .agents/reg.tsv .agents/ship.conf .github/workflows/ci.yml
t_eq "the register the manifest names, the manifest and .github/" "register manifest ci-gate" "$(printf '%s\n' "$OUT" | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
cls ../escape /etc/passwd ./bin/guard-x.sh
t_eq "an absolute path or a .. is protected; ./ is stripped" "unsafe unsafe guard" "$(printf '%s\n' "$OUT" | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
mkdir -p "$T_TMP/mut"; cp "$T_ROOT/bin/log-lib.sh" "$T_ROOT/bin/fs-lib.sh" "$C" "$T_TMP/mut/"
sed 's|\.agents/ship.conf\\tmanifest\\talways protected\\n||' "$T_ROOT/bin/gate-lib.sh" > "$T_TMP/mut/gate-lib.sh"
t_exit "M1: the mutation applies" 1 cmp -s "$T_TMP/mut/gate-lib.sh" "$T_ROOT/bin/gate-lib.sh"
CL="$T_TMP/mut/gate-classify.sh" cls .agents/ship.conf
t_eq "M1: without the fixed row the manifest is open" 0 "$RC"

t_section "a manifest naming an absent register cannot be judged; no manifest leaves only the three"
mv "$W/.agents/reg.tsv" "$W/.agents/gone.tsv"
cls docs/x.md
t_eq "exit 2" 2 "$RC"
rm "$W/.agents/ship.conf"
cls src/core/a .agents/protected-paths.tsv .github/x
t_eq "no manifest: the default register path, the manifest and .github/ only" "PROTECTED	.agents/protected-paths.tsv	register
PROTECTED	.github/x	ci-gate" "$OUT"
RC=0; sh "$C" >/dev/null 2>&1 || RC=$?
t_eq "no repo root: usage, exit 2" 2 "$RC"

t_section "harbor's register: the policy's paths are protected"
for p in CONSTITUTION.md DOCTRINE/verification-expanded.md bin/guard-bash.sh bin/floor-install.sh bin/guard-lib.sh \
         bin/floor-normalize.awk hooks/pre-commit inject.d/box/x.md .claude/inject.d/merge-note.sh skills/x/SKILL.md \
         bin/runtime-install.sh bin/deploy.sh bin/restore.sh bin/sec0-harden.sh bin/pin-instructions.sh \
         CONTRACTS/required-checks.tsv CONTRACTS/hooks.md .github/workflows/governance.yml bin/gate-approve.sh \
         bin/gate-lib.sh bin/merge-check.sh .agents/protected-paths.tsv .agents/ship.conf; do
  t_exit "$p is protected" 1 sh "$C" "$T_ROOT" "$p"
done
t_exit "docs/design/approval-gate.md is not" 0 sh "$C" "$T_ROOT" docs/design/approval-gate.md

t_section "harbor's register: the leak gate's patterns are human-gated (harbor#1149)"
t_exit "CONTRACTS/leak-patterns.tsv is protected: an allow row cannot forgive a leak unseen" 1 sh "$C" "$T_ROOT" CONTRACTS/leak-patterns.tsv
mkdir -p "$T_TMP/lp/.agents"; cp "$T_ROOT/.agents/ship.conf" "$T_TMP/lp/.agents/"
grep -v '	ci-gate	the generic patterns of the leak gate' "$T_ROOT/.agents/protected-paths.tsv" > "$T_TMP/lp/.agents/protected-paths.tsv"
t_exit "RED-PROOF: without the leak-patterns row, the register is open there" 0 \
  sh "$C" "$T_TMP/lp" CONTRACTS/leak-patterns.tsv

t_section "harbor's register: the skill book's router is an instruction surface (harbor#1149)"
# deploy writes this file's text into the installed skill book, so a change to it is a change to what every session reads.
t_eq "CONTRACTS/skill-book-router.tsv is protected as instructions" instructions "$(sh "$C" "$T_ROOT" CONTRACTS/skill-book-router.tsv | cut -f3)"
t_eq "...as is the generator that reads it, and the tracked book it writes" "ship instructions" "$(sh "$C" "$T_ROOT" bin/skill-book.sh skills/skill-book/SKILL.md | cut -f3 | tr '\n' ' ' | sed 's/ $//')"
mkdir -p "$T_TMP/sbr/.agents"; cp "$T_ROOT/.agents/ship.conf" "$T_TMP/sbr/.agents/"
grep -v '	instructions	the Start-here text deploy writes' "$T_ROOT/.agents/protected-paths.tsv" > "$T_TMP/sbr/.agents/protected-paths.tsv"
t_exit "RED-PROOF: without the router row, a change touching only the router is open" 0 \
  sh "$C" "$T_TMP/sbr" CONTRACTS/skill-book-router.tsv
t_exit "...and the row is the only difference: the generator is still protected there" 1 sh "$C" "$T_TMP/sbr" bin/skill-book.sh
t_eq "CODEOWNERS owns it too" "/CONTRACTS/skill-book-router.tsv" "$(grep -o '^/CONTRACTS/skill-book-router.tsv' "$T_ROOT/.github/CODEOWNERS")"

t_section "harbor's register: a persistent job always queues for the click"
for p in launchd/com.harbor.event.dispatch.plist systemd/harbor-event-dispatch.service systemd/harbor-event-dispatch.timer \
         tools/dispatch/com.harbor.event.dispatch.plist runners/linux/harbor-x.timer; do
  t_eq "$p is protected as a persistent job" persistent-job "$(sh "$C" "$T_ROOT" "$p" | cut -f3)"
done
mkdir -p "$T_TMP/pj/.agents"; cp "$T_ROOT/.agents/ship.conf" "$T_TMP/pj/.agents/"
grep -v '	persistent-job	' "$T_ROOT/.agents/protected-paths.tsv" > "$T_TMP/pj/.agents/protected-paths.tsv"
t_exit "RED-PROOF: without the persistent-job rows, a change touching only the dispatcher plist is open" 0 \
  sh "$C" "$T_TMP/pj" launchd/com.harbor.event.dispatch.plist
t_exit "bin/browser-hosts-add.sh, which nothing protected calls, is not" 0 sh "$C" "$T_ROOT" bin/browser-hosts-add.sh

t_section "harbor's register: what installers ship, and what hooks and gate tools call, is derived and current"
D="$T_ROOT/bin/gate-register-derive.sh"
t_exit "the derived block is current" 0 sh "$D" --check
t_exit "...whatever the caller's locale: a Mac writes it, a Linux runner checks it (harbor#1149)" 0 env LC_ALL=en_US.UTF-8 sh "$D" --check

t_section ".github/CODEOWNERS is derived from the register, so GitHub asks the operator for a protected change"
CO="$T_ROOT/bin/gate-codeowners.sh"
t_exit "CODEOWNERS is current" 0 sh "$CO" --check
t_has "...the register's rows are owned" "$(cat "$T_ROOT/.github/CODEOWNERS")" "/bin/guard-* @"
t_has "...and CODEOWNERS owns itself" "$(cat "$T_ROOT/.github/CODEOWNERS")" "/.github/ @"
mkdir -p "$T_TMP/co/bin" "$T_TMP/co/.agents" "$T_TMP/co/.github"
cp "$CO" "$T_ROOT/bin/log-lib.sh" "$T_TMP/co/bin/"; cp "$T_ROOT/.agents/ship.conf" "$T_ROOT/.agents/protected-paths.tsv" "$T_TMP/co/.agents/"
cp "$T_ROOT/.github/CODEOWNERS" "$T_TMP/co/.github/"
t_exit "a copy of the tree is current too" 0 sh "$T_TMP/co/bin/gate-codeowners.sh" --check
printf 'newly/protected.sh\tfloor\ta row added to the register\n' >> "$T_TMP/co/.agents/protected-paths.tsv"
t_exit "RED-PROOF: a register row CODEOWNERS lacks fails the check" 1 sh "$T_TMP/co/bin/gate-codeowners.sh" --check
for p in bin/event-bus.sh bin/failure-capture.sh bin/ci-governor.sh bin/status-obligations.sh bin/fs-lib.sh CONTRACTS/obligation-kinds.tsv; do
  t_exit "$p is protected (shipped, or called by a protected entry point)" 1 sh "$C" "$T_ROOT" "$p"
done
_drv="$(sh "$D" --print 2>/dev/null | cut -f1)"
t_eq "every derived path classifies protected" "" "$(printf '%s\n' "$_drv" | sh "$C" "$T_ROOT" | cut -f2 | sort | comm -13 - "$(printf '%s\n' "$_drv" | sort > "$T_TMP/drv"; echo "$T_TMP/drv")")"
grep -v '^bin/event-bus.sh	' "$T_ROOT/.agents/protected-paths.tsv" > "$T_TMP/reg-minus"
t_exit "RED-PROOF: a register missing one derived row fails the check" 1 sh "$D" --check "$T_TMP/reg-minus"
mkdir -p "$T_TMP/rr/.agents"; cp "$T_TMP/reg-minus" "$T_TMP/rr/.agents/protected-paths.tsv"; cp "$T_ROOT/.agents/ship.conf" "$T_TMP/rr/.agents/"
t_exit "...and the file it dropped is open there" 0 sh "$C" "$T_TMP/rr" bin/event-bus.sh

t_section "harbor's register: what runs as the operator outside a session, what ship.conf runs, what decides the checks"
_five="bin/gcloud-wrapper.sh bin/gcloud-creds bin/secret bin/idea.sh bin/wait-for"
t_eq "the five core shim targets in ~/.local/bin are protected (a pack's own shims are in its repo, harbor#1149)" "$_five" \
  "$(printf '%s\n' $_five | sh "$C" "$T_ROOT" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
for p in CONTRACTS/shims.tsv CONTRACTS/roots.tsv bin/live-verify.sh CONTRACTS/suites.txt CONTRACTS/suites-quick.txt \
         CONTRACTS/suites-dash.txt CONTRACTS/suites-tally.txt CONTRACTS/suite-paths.txt CONTRACTS/required-checks.tsv \
         bin/ci-verified.sh bin/suite-run.sh bin/suite-select.sh runners/linux/entrypoint.sh tests/lib/core.sh; do
  t_exit "$p is protected" 1 sh "$C" "$T_ROOT" "$p"
done
t_exit "an individual test file is not (the register's recorded trade-off)" 0 sh "$C" "$T_ROOT" tests/gate/approval/classify.test.sh
t_eq "harbor's local required list names the one check protection requires (harbor#1149: public-ci)" \
  "public-ci" \
  "$(awk -F'\t' '$1 == "VytCepas/harbor" { print $2 }' "$T_ROOT/CONTRACTS/required-checks.tsv" | tr '\n' '|' | sed 's/|$//')"
# RED-PROOFS: a copy of the tree whose derive lost one source, its register rewritten from it
RP="$T_TMP/rp"; mkdir -p "$RP/tests" "$RP/.github"
cp -R "$T_ROOT/bin" "$T_ROOT/CONTRACTS" "$T_ROOT/.agents" "$T_ROOT/runners" "$RP/"
cp -R "$T_ROOT/tests/lib" "$RP/tests/"; cp -R "$T_ROOT/.github/workflows" "$RP/.github/"
rp() { # <what> <sed expression> <path it alone protected>
  sed "$2" "$T_ROOT/bin/gate-register-derive.sh" > "$RP/bin/gate-register-derive.sh"
  t_exit "RED-PROOF $1: the mutation applies" 1 cmp -s "$RP/bin/gate-register-derive.sh" "$T_ROOT/bin/gate-register-derive.sh"
  sh "$RP/bin/gate-register-derive.sh" --write >/dev/null 2>&1
  t_exit "RED-PROOF $1: without it, $3 is open" 0 sh "$C" "$RP" "$3"
}
rp "shim targets" 's|"\$ROOT/CONTRACTS/shims.tsv" >>|/dev/null >>|' bin/wait-for
rp "the two registers" '/decides what ~\/.local\/bin points at/d' CONTRACTS/shims.tsv
rp "ship.conf commands" 's/^for _k in plan apply verify restore deployed;/for _k in none;/' bin/live-verify.sh
rp "the suite manifests" 's|"\$ROOT"/CONTRACTS/suites\*\.txt ||' CONTRACTS/suites.txt
rp "the runner and test-library globs" 's/^for _d in runners tests\/lib;/for _d in none;/' tests/lib/row.sh

t_section "harbor's register: every script an installer wires as a hook or statusline, and every installer"
wired() { # the bin/ files an installer names as <dir>/bin/<file> (hooks, statusline), and floor-install's wiring table
  grep -ohE '\$DIR/bin/[a-z0-9_-]+\.(sh|awk|py)' "$1"/bin/*-install.sh | sed 's|\$DIR/||'
  awk '/^floor_hooks\(\)/ { f = 1; next } f && /^ROWS$/ { exit } f && !/^#/ && /;/' "$1/bin/floor-install.sh" | cut -d';' -f3 \
    | tr ' ' '\n' | grep -v '^-' | sed 's|^|bin/|'
  git -C "$1" ls-files 'bin/*-install.sh'
}
_w="$(wired "$T_ROOT" | sort -u)"
t_eq "the derivation finds them (more than 30)" yes "$([ "$(printf '%s\n' "$_w" | grep -c .)" -gt 30 ] && echo yes || echo no)"
_open="$(printf '%s\n' "$_w" | sh "$C" "$T_ROOT" | cut -f2 | sort | comm -13 - "$(printf '%s\n' "$_w" > "$T_TMP/w"; echo "$T_TMP/w")")"
t_eq "none of them is open" "" "$_open"
cp -R "$T_ROOT/.agents" "$T_TMP/h"; mkdir -p "$T_TMP/hr"; mv "$T_TMP/h" "$T_TMP/hr/.agents"
grep -v '^bin/reply-shape.sh' "$T_ROOT/.agents/protected-paths.tsv" > "$T_TMP/hr/.agents/protected-paths.tsv"
_open="$(printf '%s\n' "$_w" | sh "$C" "$T_TMP/hr" | cut -f2 | sort | comm -13 - "$T_TMP/w")"
t_eq "RED-PROOF: a register missing a hook row leaves exactly that hook open" bin/reply-shape.sh "$_open"
t_done
