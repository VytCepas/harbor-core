#!/usr/bin/env sh
# The numbers the floor suite feeds (harbor#727): status-gen's re-entry guard (harbor#288), the
# dashboard as a view of status-gen (VIZ-1), STATUS.md host-invariance and its observed twin (#91), and
# counts supplied by a run that already paid for them (#120). Every status-gen here is sandboxed by
# HARBOR_ROOT/HELM_LIVE_DIR, and every suite it could spawn is a stub.
. "$(dirname "$0")/../lib/core.sh"; t_init
. "$(dirname "$0")/floor-fixture.sh"
_ne() { [ "$1" != "$2" ] && echo differs || echo "same: $1"; }   # <a> <b>

t_section "RE-ENTRY-0 (harbor#773): the part inherits none of status-gen's inputs from its caller"
# Derived from status-gen itself; the re-entry marker is the fixture's own, and RE-ENTRY-1 pins it.
_sg_in="$(grep -oE '[$][{](HARBOR_[A-Z0-9_]+|HELM_[A-Z0-9_]+|FAST)' "$SRC/status-gen.sh" | sed 's/^..//' | sort -u | grep -vx HARBOR_IN_SUITE)"
t_eq "RE-ENTRY-0 status-gen reads the variables this row checks" yes "$(printf '%s\n' "$_sg_in" | grep -qx HARBOR_SUITE_COUNTS && echo yes)"
t_eq "RE-ENTRY-0 none of them is set in the part: $(printf '%s ' $_sg_in)" "" \
  "$(for _v in $_sg_in; do env | grep -q "^$_v=" && printf '%s ' "$_v"; done)"

t_section "RE-ENTRY-1 (harbor#288): a floor part runs status-gen, which must not run the suite back"
# The leaf is a STUB at the suite's moved path, so this costs milliseconds and never spawns the real
# suite. The failing shape is a copied bin/ with no STATUS.md to read and no build/ to cache in.
RE="$TMP/reentry"
_re_fixture() { # <dir> — a bin-only tree, a stub tests/floor/floor-test.sh, no STATUS.md
  mkdir -p "$1/bin" "$1/tests/floor"
  cp "$SRC"/*.sh "$SRC"/*.awk "$1/bin/" 2>/dev/null || true
  rm -f "$1/bin/floor-test.sh"  # a legacy bin/ copy would shadow the stub (status-gen prefers bin/)
  printf '#!/bin/sh\nprintf "spawned\\n" >> "%s/spawned"\nprintf "floor-test: 7 passed, 0 failed\\n"\n' \
    "$1" > "$1/tests/floor/floor-test.sh"
  chmod +x "$1/tests/floor/floor-test.sh"
}
_re_spawns() { [ -f "$1/spawned" ] && grep -c spawned "$1/spawned" 2>/dev/null || echo 0; }  # <dir>
# The marker must reach a CHILD: a plain assignment satisfies an in-shell test and blinds every child.
t_eq "RE-ENTRY-1 HARBOR_IN_SUITE reaches a child" 1 "$(sh -c 'printf %s "${HARBOR_IN_SUITE:-}"' 2>/dev/null)"
t_eq "RE-ENTRY-1 HARBOR_IN_SUITE is set in the part's own shell" 1 "${HARBOR_IN_SUITE:-}"
_re_fixture "$RE/nested"
HARBOR_IN_SUITE=1 HARBOR_ROOT="$RE/nested" sh "$SRC/status-gen.sh" --json-fast \
  >"$RE/nested/out" 2>"$RE/nested/err" || true
t_eq "RE-ENTRY-1 nested: status-gen runs no suite from inside one" 0 "$(_re_spawns "$RE/nested")"
t_has "RE-ENTRY-1 nested: the refusal says why" "$(cat "$RE/nested/err" 2>/dev/null)" 'harbor#288'
# The negative control: marker cleared, same fixture, the stub MUST run, or the two above prove nothing.
_re_fixture "$RE/toplevel"
env -u HARBOR_IN_SUITE HARBOR_ROOT="$RE/toplevel" sh "$SRC/status-gen.sh" --json-fast \
  >"$RE/toplevel/out" 2>/dev/null || true
t_eq "RE-ENTRY-1 control: top level reaches the run branch" 1 "$(_re_spawns "$RE/toplevel")"
t_eq "RE-ENTRY-1 control: the stub's count is read" 7 "$(jq -r '.assertions."floor-test"' "$RE/toplevel/out" 2>/dev/null)"
# The legitimate nested reads still answer: the guard sits below the no-run branches (VIZ-1's shape).
mkdir -p "$RE/warm/bin" "$RE/warm/tests/floor"; cp "$SRC"/*.sh "$SRC"/*.awk "$RE/warm/bin/" 2>/dev/null || true
rm -f "$RE/warm/bin/floor-test.sh"
printf '#!/bin/sh\nprintf "spawned\\n" >> "%s/spawned"\nexit 0\n' "$RE/warm" > "$RE/warm/tests/floor/floor-test.sh"
chmod +x "$RE/warm/tests/floor/floor-test.sh"
printf '| `floor-test` assertions | 4242 |\n' > "$RE/warm/STATUS.md"
_re_warm="$(HARBOR_IN_SUITE=1 HARBOR_ROOT="$RE/warm" sh "$SRC/status-gen.sh" --json-fast 2>/dev/null \
            | jq -r '.assertions."floor-test"' 2>/dev/null)"
t_eq "RE-ENTRY-1 a nested FAST read of STATUS.md still answers" 4242 "$_re_warm"
t_eq "RE-ENTRY-1 the FAST branch runs no suite" 0 "$(_re_spawns "$RE/warm")"

t_section "VIZ-1: the dashboard is a VIEW of the numbers, and says when it cannot draw"
# A failing `gh` is the offline case and keeps this hermetic: no live GitHub call.
VZ="$TMP/viz"; mkdir -p "$VZ/stub"
printf '#!/bin/sh\nexit 1\n' > "$VZ/stub/gh"; chmod +x "$VZ/stub/gh"
_viz="$(PATH="$VZ/stub:$PATH" sh "$SRC/dashboard-gen.sh" --stdout 2>/dev/null || true)"
t_has "VIZ-1 dashboard-gen produced a page" "$_viz" '<title>Harbor'
_vzn="$(sh "$SRC/status-gen.sh" --json-fast 2>/dev/null | jq -r '.assertions."floor-test"' 2>/dev/null || echo x)"
t_has "VIZ-1 the page carries status-gen's current floor-test total ($_vzn)" "$_viz" ">$_vzn<"
t_has "VIZ-1 with gh failing the ticket panel says unavailable" "$_viz" 'unavailable'
_vzre='(src|href)="https?:'  # the control proves the pattern can match a CDN reference at all
t_eq "VIZ-1 the page references no external resource (renders with the wifi off)" "pattern:hit page:none" \
  "pattern:$(printf '%s' '<script src="https://cdn.example/x.js">' | grep -qE "$_vzre" && echo hit || echo miss) page:$(printf '%s' "$_viz" | grep -qE "$_vzre" && echo external || echo none)"
mkdir -p "$VZ/hollow/bin"
t_exit "VIZ-1 no numbers behind it: dashboard-gen refuses to render" 1 \
  env HARBOR_ROOT="$VZ/hollow" sh "$SRC/dashboard-gen.sh" --stdout

t_section "VIZ-1: --open uses the opener this OS has, and says where the page is when it has none (harbor#618)"
# A PATH of every tool this host has minus the openers and gh; each case adds only the opener under test.
. "$T_ROOT/tests/lib/linux-sim.sh"; linux_path "$VZ/noopen" open xdg-open wslview gh
VO="$VZ/open"; mkdir -p "$VO/bin"; cp "$SRC"/*.sh "$SRC"/*.awk "$VO/bin/" 2>/dev/null; cp "$T_ROOT/fixtures/status/seed.md" "$VO/STATUS.md"
: > "$VZ/opened.log"
for _op in open xdg-open wslview; do
  mkdir -p "$VZ/o-$_op"; printf '#!/bin/sh\nprintf "%s %%s\\n" "$1" >> "%s"\n' "$_op" "$VZ/opened.log" > "$VZ/o-$_op/$_op"; chmod +x "$VZ/o-$_op/$_op"
done
mkdir -p "$VZ/o-none"
oprun() { env HARBOR_IN_SUITE=1 HARBOR_ROOT="$VO" PATH="$VZ/stub:$VZ/o-$1:$VZ/noopen" sh "$VO/bin/dashboard-gen.sh" --open 2>&1; }
t_eq "control: the opener-free PATH has none of them" "" "$(PATH="$VZ/noopen" command -v open xdg-open wslview)"
oprun open >/dev/null
t_eq "macOS: open gets the page" "open $VO/build/dashboard.html" "$(cat "$VZ/opened.log")"
: > "$VZ/opened.log"; oprun xdg-open >/dev/null
t_eq "Linux: xdg-open gets the page" "xdg-open $VO/build/dashboard.html" "$(cat "$VZ/opened.log")"
: > "$VZ/opened.log"; oprun wslview >/dev/null
t_eq "WSL2: wslview gets the page" "wslview $VO/build/dashboard.html" "$(cat "$VZ/opened.log")"
: > "$VZ/opened.log"; _no="$(oprun none)"
t_has "no opener: the page is still written" "$_no" "  ok: wrote $VO/build/dashboard.html"
t_has "...and one note says where it is" "$_no" "  note: no opener (open, xdg-open, wslview) on PATH: the page is at $VO/build/dashboard.html"
t_eq "...and nothing was opened" "" "$(cat "$VZ/opened.log")"

t_section "STATUS-1: the installed-floor row cannot be satisfied by a non-floor hook"
# 2026-08-01: `test("guard-")` matched the prod-guard-ambient shim, so STATUS.md said the floor was
# installed on a box with none of B2-B6. HELM_LIVE_DIR keeps this off the operator's real ~/.claude.
SG="$TMP/statusgen"; mkdir -p "$SG/decoy/bin" "$SG/full/bin" "$SG/hollow/bin"
_wire() { # <dir> <command string>
  mkdir -p "$1"
  jq -n --arg c "$2" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' \
    > "$1/settings.json"
}
_obs() { # <dir> <field> -> the value status-gen reports for that live dir
  HELM_LIVE_DIR="$1" sh "$SRC/status-gen.sh" --json-fast 2>/dev/null | jq -r ".observed.$2" 2>/dev/null
}
_wire "$SG/decoy" "/bin/sh $SG/decoy/bin/prod-guard-ambient.sh $SG/decoy/hooks/prod_guard.py"
: > "$SG/decoy/bin/prod-guard-ambient.sh"
t_eq "STATUS-1 a prod-guard-ambient-only settings.json does not report the floor" no "$(_obs "$SG/decoy" guard_hooks)"
t_eq "STATUS-1 the same fixture still credits prod_guard" yes "$(_obs "$SG/decoy" prod_guard)"
_wire "$SG/full" "/bin/sh $SG/full/bin/floor-hook.sh $SG/full/bin/guard-bash.sh"
for _g in floor-hook.sh guard-lib.sh guard-bash.sh guard-egress.sh \
          guard-selfedit.sh annotate-web.sh floor-normalize.awk; do
  printf '#\n' > "$SG/full/bin/$_g"
done
t_eq "STATUS-1 a correctly wired floor with every guard present reports installed" yes "$(_obs "$SG/full" guard_hooks)"
_wire "$SG/hollow" "/bin/sh $SG/hollow/bin/floor-hook.sh $SG/hollow/bin/guard-bash.sh"
t_eq "STATUS-1 wiring alone, no guard files on disk, is not reported installed" not-yes \
  "$(case "$(_obs "$SG/hollow" guard_hooks)" in (yes) echo yes ;; ('') echo empty ;; (*) echo not-yes ;; esac)"
# harbor#91: STATUS.md is host-invariant. A root of symlinks (tests/ too: the suites live there now)
# with a scratch STATUS.md; FAST=1 throughout, or suite_count RUNS the suites.
SGR="$SG/root"; mkdir -p "$SGR"
for _l in bin vendor CONTRACTS fixtures tests; do
  [ -e "$HROOT/$_l" ] && ln -sf "$HROOT/$_l" "$SGR/$_l"
done
_sgen() { FAST=1 HARBOR_ROOT="$SGR" HELM_LIVE_DIR="$1" sh "$SRC/status-gen.sh" ${2:-} 2>/dev/null; }
cp "$T_ROOT/fixtures/status/seed.md" "$SGR/STATUS.md"   # a seed, not the repo's STATUS.md: that is dev-layer and not in the export
_s_full="$(_sgen "$SG/full")"
_s_decoy="$(_sgen "$SG/decoy")"
t_eq "STATUS-1/#91 STATUS.md is byte-identical across two live dirs" same \
  "$([ -n "$_s_full" ] && [ "$_s_full" = "$_s_decoy" ] && echo same || echo differs-or-empty)"
_o_full="$(_sgen "$SG/full" --observed)"
_o_decoy="$(_sgen "$SG/decoy" --observed)"
t_eq "STATUS-1/#91 --observed tells a wired live dir from an unwired one" differs "$(_ne "$_o_full" "$_o_decoy")"
t_has "STATUS-1/#91 --observed keeps the guard-hooks row" "$_o_full" 'guard hooks installed'
t_eq "STATUS-1/#91 the tracked file carries no machine-observed row (the observed report does)" \
  "observed:has tracked:none" \
  "observed:$(case "$_o_full" in (*'lagging the repo'*) echo has ;; (*) echo none ;; esac) tracked:$(case "$_s_full" in
    (*'Observed on this machine'*|*'lagging the repo'*) echo has ;; ('') echo empty ;; (*) echo none ;; esac)"
# Red-green for T1's mechanism: a stale REPO-DERIVED count must still fail --check-fast.
_sgen "$SG/full" --apply >/dev/null 2>&1
t_exit "STATUS-1/#91 a freshly generated STATUS.md passes --check-fast" 0 \
  env FAST=1 HARBOR_ROOT="$SGR" HELM_LIVE_DIR="$SG/full" sh "$SRC/status-gen.sh" --check-fast
sed 's/^| lint rules | [0-9]*/| lint rules | 99999/' "$SGR/STATUS.md" > "$SGR/STATUS.md.x" \
  && mv "$SGR/STATUS.md.x" "$SGR/STATUS.md"
t_exit "STATUS-1/#91 a wrong repo-derived count fails --check-fast" 1 \
  env FAST=1 HARBOR_ROOT="$SGR" HELM_LIVE_DIR="$SG/full" sh "$SRC/status-gen.sh" --check-fast

t_section "SUPPLIED-1 (harbor#120): a count a real run paid for, without re-running it"
# Pinned both ways: a supplied count must skip the run, and must still be able to go red.
_sgen "$SG/full" --apply >/dev/null 2>&1        # undo the perturbation above
_tf="$(grep -F '`floor-test` assertions' "$SGR/STATUS.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
_tn="$(grep -F '`normalize-test` assertions' "$SGR/STATUS.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
_tm="$(grep -F '`marker-test` assertions' "$SGR/STATUS.md" 2>/dev/null | grep -oE '[0-9]+' | head -1)"
_sgc() { # <counts> — --check with NO FAST, so only the supplied value can stop a suite running
  _sgc_out="$(HARBOR_SUITE_COUNTS="$1" HARBOR_ROOT="$SGR" HELM_LIVE_DIR="$SG/full" \
    sh "$SRC/status-gen.sh" --check 2>&1)"; _sgc_rc=$?
}
_sgc "floor-test=$_tf normalize-test=$_tn marker-test=$_tm"
t_eq "SUPPLIED-1 --check passes with the TRUE counts supplied" 0 "$_sgc_rc"
# An absurd count must appear VERBATIM in the diff: a re-run would have printed the real total.
_sgc "floor-test=424242 normalize-test=$_tn marker-test=$_tm"
t_has "SUPPLIED-1 the supplied count reached the output (the suite was not re-run)" "$_sgc_out" '424242'
t_eq "SUPPLIED-1 a wrong supplied count fails --check" 1 "$_sgc_rc"
# Malformed is exit 2, never a silent fallback to running the suite, and never 1 ("stale").
for _badv in 'floor-test' 'flor-test=1' 'floor-test=abc' 'floor-test=' 'floor-test=1,normalize-test=x'; do
  _sgc "$_badv"
  t_eq "SUPPLIED-1 malformed HARBOR_SUITE_COUNTS '$_badv' exits 2" 2 "$_sgc_rc"
done
t_exit "SUPPLIED-1 --check-fast is unmoved by a supplied count" 0 \
  env FAST=1 HARBOR_SUITE_COUNTS="floor-test=424242" HARBOR_ROOT="$SGR" HELM_LIVE_DIR="$SG/full" \
  sh "$SRC/status-gen.sh" --check-fast
ff_sealed
t_done
