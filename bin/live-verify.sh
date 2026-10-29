#!/usr/bin/env sh
# live-verify.sh (harbor#735) — does the INSTALLED box work? The read-only live tier of the test
# contract (CONTRACTS/test-contract.md rule 6): every live check, one line each with its id.
#   sh live-verify.sh --live [--probes]    or: harbor check --live [--probes]
#   READ-ONLY. The box is $HOME/.claude and the shims in HARBOR_LOCAL_BIN; a sandbox is a HOME.
#   --probes   also the real-system probes harbor#667 moved behind stubs: the Keychain lookup contract,
#              the live-dir refusal, and the browser consent arm when HARBOR_BROWSER_LIVE_URL names a
#              site whose analytics you own. None adds, reads or deletes a real secret.
#   Exit 0 = every check green. 1 = one is red. 2 = usage, --apply or --dir, or CI: it never runs there.
# secret-seam: macOS-only — probe:secret asks the Keychain for its own answer on an absent item (44), which
#   libsecret has no equivalent of; with no `security` on PATH it log_skips (harbor#618).

# WHY ONE COMMAND. The live checks existed and were scattered across five tools, and a clean
# environment cannot answer "does this box work": the hermetic suites prove the code, this proves
# the machine. Every line is stamped with the CHECKS.md id, so a red line resolves to its row.
set -u
HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/log-lib.sh"
. "$HERE/install-lib.sh"
log_init live-verify
PROBES=0
il_opt() { case "$1" in --probes) PROBES=1; IL_TAKE=1 ;; esac; }
il_parse "$@"
[ "$IL_APPLY" -eq 0 ] || il_usage_error '--apply: the live tier is read-only and writes nothing'
[ "$IL_ACCEPT_LOSS" -eq 0 ] || il_usage_error '--accept-loss: the live tier is read-only and loses nothing'
[ "$IL_DIR_SET" -eq 0 ] || il_usage_error '--dir: the live tier checks the installed box; a sandbox is a HOME: HOME=<dir> sh live-verify.sh --live'
if [ -n "${CI:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ]; then
  il_usage_error 'CI is set: the live tier never runs in CI (CONTRACTS/test-contract.md rule 6)'
fi
il_target
CFG="$IL_TARGET"
ID='[check:live-verify]'
_td="${TMPDIR:-/tmp}"; W="$(mktemp -d "${_td%/}/live-verify.XXXXXX")" || exit 1
trap 'rm -rf "$W"' EXIT
trap 'exit 130' INT TERM HUP
log_head "the installed box at $CFG (read-only)"

# THE PRECONDITION (harbor#457). Floor, install-drift, shims and sec0-env all read what a deploy installed, and a
# deploy needs the config dir and its settings.json. Without them each one failed on its own downstream error
# (measured on a stranger's box: four FAILs, none naming the missing file), so the cause is stated once, first,
# with the command that removes it, and the checks that cannot mean anything without it say they were not run.
# doctor and roots read the checkout and the tools, so they still run. A box that HAS an install but lost its
# settings.json is a different cause with a different fix (the snapshot), and only the two checks that read
# settings.json are skipped there: install-drift reads bin/ and shims read shims.tsv.
_pre=''; _lost=0
if [ ! -d "$CFG" ]; then
  _pre="no config dir at $CFG"; _why='the first-run step has not been taken, so nothing is installed here'
  _fx="$(il_first_run_cmd "$(CDPATH='' cd -- "$HERE/.." && pwd)")"
elif [ ! -f "$CFG/settings.json" ]; then
  _pre="no settings.json in $CFG"
  if il_installed "$CFG"; then
    _lost=1; _why='this box has an install (bin/ or .harbor-manifest), so the file was lost after the first run and the floor wiring went with it'
    _fx="$(il_lost_settings_fix "$CFG" "$HERE/restore.sh")"
  else
    _why='the first-run step has not been taken, so nothing is installed here'
    _fx="$(il_first_run_cmd "$(CDPATH='' cd -- "$HERE/.." && pwd)")"
  fi
fi
if [ -n "$_pre" ]; then
  log_fail "$ID precondition — $_pre: $_why"
  log_fix "$_fx"
fi
skipped() { # <check id> [settings] — 0 and a skip line when the precondition leaves the check meaningless
  [ -n "$_pre" ] || return 1
  [ "$_lost" -eq 0 ] || [ "${2-}" = settings ] || return 1  # a lost settings.json blocks only what reads it
  log_skip "$ID $1 — not run: $_pre (the precondition line above)"; return 0
}

# The first FAIL a log-lib tool printed, and the fix line under it.
first_fail() { sed -n 's/^  FAIL: //p' "$1" | head -1; }
first_fix() { awk '/^  FAIL: /{f=1; next} f && /^  fix: /{sub(/^  fix: /,""); print; exit}' "$1"; }
fails() { grep -c '^  FAIL: ' "$1" 2>/dev/null || :; }
summary() { grep -aE '^[a-z0-9-]+: [0-9]+ ok, [0-9]+ failed, [0-9]+ warnings$' "$1" | tail -1; }

# A check whose tool speaks the log format: green iff it exits 0; red relays its first FAIL and fix.
logged() { # <id> <what to re-run for the full report> <cmd> [args…]
  _i="$1"; _again="$2"; shift 2
  "$@" < /dev/null > "$W/$_i" 2>&1; _r=$?
  if [ "$_r" -eq 0 ]; then log_ok "$ID $_i — $(summary "$W/$_i")"; return 0; fi
  _f="$(first_fail "$W/$_i")"; _x="$(first_fix "$W/$_i")"; _n="$(fails "$W/$_i")"
  log_fail "$ID $_i — exited $_r: ${_f:-no FAIL line} (FAIL lines: ${_n:-0}; the whole report: $_again)"
  if [ -n "$_x" ]; then log_fix "$_x"; else log_nofix "$_again"; fi
}

# 1. The floor: fired at the installed guards. floor-verify fires them through a temp link, so the
#    guard-decision ledger never files a probe (harbor#735).
skipped floor settings || logged floor "sh $HERE/floor-verify.sh --live" env -u CLAUDE_CONFIG_DIR sh "$HERE/floor-verify.sh" --live

# 2. The external tools the floor and the recovery path need.
sh "$HERE/doctor.sh" < /dev/null > "$W/doctor" 2>&1; _r=$?
if [ "$_r" -eq 0 ]; then log_ok "$ID doctor — every fatal dependency present"
else
  log_fail "$ID doctor — exited $_r: $(awk '$2 == "missing" && $3 == "fatal" { printf "%s%s", s, $1; s = ", " }' "$W/doctor") missing"
  log_nofix "sh $HERE/doctor.sh (each row names what breaks without it)"
fi

# 3. The installed bin/ against the repo, by content. It needs the checkout, never the installed copy.
_ref="${HELM_DRIFT_REF:-origin/main}"
if skipped install-drift; then :
elif git -C "$HERE/.." rev-parse --git-dir > /dev/null 2>&1; then
  logged install-drift "sh $HERE/install-drift.sh --dir '$CFG' --ref $_ref" \
    sh "$HERE/install-drift.sh" --dir "$CFG" --ref "$_ref"
else log_skip "$ID install-drift — needs the repo checkout, and $HERE is not one"; fi

# 4. The commands the operator types. The dry run exits 0 on a link it would change, so a would-link or
#    would-repoint note is red here: the command on PATH is not the file shims.tsv names.
if skipped shims; then :; else  # shims.tsv's links come from the same deploy the precondition blocks
sh "$HERE/shim-install.sh" --live < /dev/null > "$W/shims" 2>&1; _r=$?
_off="$(sed -nE 's/^  note: ([^:]*): would (link|repoint) .*/\1/p' "$W/shims" | tr '\n' ' ')"
if [ "$_r" -eq 0 ] && [ -z "$_off" ]; then log_ok "$ID shims — $(summary "$W/shims")"
elif [ -n "$_off" ]; then
  log_fail "$ID shims — not what CONTRACTS/shims.tsv names: ${_off% }"
  log_fix "sh $HERE/shim-install.sh --apply --live"
else
  log_fail "$ID shims — exited $_r: $(first_fail "$W/shims")"
  _x="$(first_fix "$W/shims")"
  if [ -n "$_x" ]; then log_fix "$_x"; else log_nofix "sh $HERE/shim-install.sh --live"; fi
fi
fi

# 5. The named roots against the tree's own defaults.
sh "$HERE/roots.sh" --check < /dev/null > "$W/roots" 2>&1; _r=$?
if [ "$_r" -eq 0 ]; then log_ok "$ID roots — every root default matches CONTRACTS/roots.tsv"
else
  log_fail "$ID roots — exited $_r: $(grep -v '^roots --check: ' "$W/roots" | head -1)"
  log_nofix "sh $HERE/roots.sh --check (CONTRACTS/roots.tsv)"
fi

# 6. sec0's decided env keys (harbor#816): a read-only replay of sec0-harden's own dry-run plan —
#    it writes nothing (only --apply does), so relaying its report duplicates no logic and no list.
if skipped sec0-env settings; then :; else
sh "$HERE/sec0-harden.sh" --live < /dev/null > "$W/sec0-env" 2>&1
if grep -q '^  ok: every SEC-0 env key is present' "$W/sec0-env"; then
  log_ok "$ID sec0-env — every harbor#816 env key is present in settings.json"
else
  _missing="$(sed -n 's/^  note: env to add ([^)]*): \([A-Za-z_]*\)=1$/\1/p' "$W/sec0-env" | tr '\n' ' ')"
  log_fail "$ID sec0-env — missing from settings.json env: ${_missing:-see $HERE/sec0-harden.sh --live}"
  log_fix "sh $HERE/deploy.sh --only sec0 --apply --live"
fi
fi

# ── the opt-in probes: the real-system coverage the hermetic suites stub (harbor#667) ─────────────
if [ "$PROBES" -eq 0 ]; then
  for _p in probe:secret probe:live-dir probe:browser; do
    log_skip "$ID $_p — opt-in: $(il_cmd) --probes"
  done
  log_end; exit $?
fi

# The Keychain: `secret` and the suites' stub (tests/cli/keychain-stub.sh) both assume the real
# `security` answers 44 for an absent item. Asked about a name nothing stores, never with -w or -g.
_kn='zz-harbor-live-probe-absent'; _ks="secret.$_kn"; _ka="${USER:-$(id -un)}"
if ! command -v security > /dev/null 2>&1; then log_skip "$ID probe:secret — no security binary (not macOS)"
else
  security find-generic-password -s "$_ks" -a "$_ka" > /dev/null 2>&1; _r=$?
  sh "$HERE/secret" run "$_kn" LIVE_VERIFY_PROBE -- true > "$W/secret" 2>&1; _sr=$?
  if [ "$_r" -eq 0 ]; then
    log_fail "$ID probe:secret — a Keychain item $_ks exists; the probe needs that name absent"
    log_nofix "the item is not the probe's: look before removing it with: sh $HERE/secret rm $_kn"
  elif [ "$_r" -ne 44 ]; then
    log_fail "$ID probe:secret — security answered $_r for an absent item; tests/cli/keychain-stub.sh answers 44"
    log_nofix "tests/cli/keychain-stub.sh: the stub no longer models the real tool"
  elif [ "$_sr" -ne 1 ] || ! grep -q "no secret named '$_kn'" "$W/secret"; then
    log_fail "$ID probe:secret — secret run on an absent name exited $_sr: $(head -1 "$W/secret")"
    log_nofix "bin/secret load(): an absent name must fail with exit 1"
  else log_ok "$ID probe:secret — security answers 44 for an absent item, and secret refuses it with exit 1"
  fi
fi

# The live-dir refusal, against this HOME's real spelling: an installer's --dir onto the live dir, with
# and without a trailing slash, is refused before anything runs. A dry run, so nothing could write.
_bad=''
for _d in "$(CDPATH='' cd -- "${HOME:-/}" 2>/dev/null && pwd)/.claude" "${HOME:-}/.claude/"; do
  sh "$HERE/skills-install.sh" --dir "$_d" < /dev/null > "$W/livedir" 2>&1; _r=$?
  if [ "$_r" -ne 1 ] || ! grep -q 'refusing the live dir without an explicit --live' "$W/livedir"; then
    _bad="${_bad}--dir $_d exited $_r; "
  fi
done
if [ -z "$_bad" ]; then log_ok "$ID probe:live-dir — an installer refuses --dir onto $CFG, both spellings"
else
  log_fail "$ID probe:live-dir — the live-dir gate did not refuse: ${_bad%; }"
  log_nofix "bin/install-lib.sh il_target"
fi

# The browser's consent arm drives a real page, so it runs only on a URL the operator names: the
# default is a client's live site, and a probe there writes a visit into that client's analytics.
if [ -z "${HARBOR_BROWSER_LIVE_URL:-}" ]; then
  log_skip "$ID probe:browser — set HARBOR_BROWSER_LIVE_URL to a site whose analytics you own"
else
  sh "$HERE/browser.sh" --self-test-live < /dev/null > "$W/browser" 2>&1; _r=$?
  case "$_r" in
    0) log_ok "$ID probe:browser — the consent arms pass on $HARBOR_BROWSER_LIVE_URL" ;;
    2) log_skip "$ID probe:browser — $(grep -m1 'SKIP' "$W/browser" || echo 'backend unavailable')" ;;
    *) log_fail "$ID probe:browser — --self-test-live exited $_r: $(grep -m1 'FAIL' "$W/browser")"
       log_nofix "sh $HERE/browser.sh --self-test-live" ;;
  esac
fi
log_end; exit $?
