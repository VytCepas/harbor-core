#!/usr/bin/env sh
# L0-5b (harbor#59) — SessionStart standing verdicts, printed ONCE per session.
# platform: macOS-only — the `launchctl kickstart` restart hint is the macOS arm of a uname switch; Linux prints the `systemctl --user` form instead (harbor#618).
#
# WHY THIS FILE EXISTS. The statusline carries the numbers that MOVE. This file
# carries the verdicts that do NOT: the worklog is dead, no guard is wired, the
# floor teeth drifted, the instruction surfaces are unpinned. Those are true
# until a human fixes them, so a statusline row for them is wallpaper by the
# third session — and once the operator has learned to look past a row, the row
# cannot carry an alarm any more. Once, loudly, at the top of the session is the
# correct cadence for a fact whose lifetime is measured in days.
#
# CONTRACT (verified against code.claude.com/docs/en/hooks):
# • `systemMessage` on stdout is a universal hook output field — shown to the
#   OPERATOR. That is deliberate: these verdicts are for the human who can fix
#   them, not for the model's context window, so `additionalContext` is NOT used
#   and none of this spends context tokens.
# • For SessionStart even exit 2 is non-blocking, and this hook has no business
#   blocking anything. It ends `exit 0` on every path.
# • It emits NOTHING when every verdict is clean. A hook that greets you every
#   session teaches you to dismiss it unread, which is the same failure as the
#   wallpaper row one paragraph up.
#
# NEVER routed through floor-hook.sh: that wrapper exits at its own line-2
# kill-switch, so an overridden session — the one where you most need to know the
# floor is standing down — would print nothing.
set -u

# Once per session means not again after /compact (asked 2026-10-27): compaction re-fires SessionStart
# in the same session, with source "compact". Read in the background under a 1 s timer, because a caller whose
# stdin is open and idle (a suite run from a tool shell) held a plain `read` for ten minutes; POSIX sh has no `read -t`.
_in=""
if [ ! -t 0 ] && _sf="$(mktemp "${TMPDIR:-/tmp}/sv-in.XXXXXX" 2>/dev/null)"; then
  exec 3<&0
  { IFS= read -r _l <&3; printf '%s' "$_l" > "$_sf"; } 2>/dev/null & _rp=$!
  { sleep 1; kill "$_rp" 2>/dev/null; } & _tp=$!
  { wait "$_rp"; kill "$_tp"; wait "$_tp"; } 2>/dev/null   # reaped here, so the shell prints no "Terminated"
  exec 3<&-
  _in="$(cat "$_sf" 2>/dev/null)"; rm -f "$_sf"
fi
case "$_in" in *'"source"'*) [ "$(printf '%s' "$_in" | jq -r '.source // empty' 2>/dev/null)" != compact ] || exit 0 ;; esac

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# The re-pin hints below name a TARGET, and `--live` in floor-deny.sh means
# literally $HOME/.claude — it does not follow CLAUDE_CONFIG_DIR (that flag is
# the accident gate protecting the real box). $CFG here does follow it, so a
# verdict measured against a sandbox printed a command aimed at live: harbor#110,
# fixed in the same change in guard-integrity.sh, which prints the same idiom.
# LIVE_DIR is lint D1's sanctioned idiom for naming the live dir to COMPARE it;
# nothing here reads or writes through it — $CFG is the only dir touched.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then TGT="--live"; else TGT="$CFG"; fi
# Shell-quoted because the hint is PASTED (PR #113, Codex P2) — a config dir with
# a space otherwise word-splits into two arguments and the pasted command targets
# a different directory than the one the verdict was measured against. Same fix,
# same reason, as guard-integrity.sh, which prints the twin of this idiom.
_shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
CFGQ="$(_shq "$CFG")"
# The floor-deny re-pin takes install-lib's spelling (harbor#800): '--live', or --dir '<cfg>' — never a
# positional dir, which it now refuses. drift-reference-check.sh still takes its target positionally.
if [ "$TGT" = --live ]; then TGTQ="$(_shq "$TGT")"; else TGTQ="--dir $CFGQ"; fi
RCQ="$(_shq "$TGT")"
S="$CFG/settings.json"
V=""

add() { V="${V:+$V
}• $1"; }

sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# ── 1 · the work-log hooks ───────────────────────────────────────────────────
# The failure that ran silently for days: worklog-push.sh and its pull sibling (retired, #311)
# both `. "$DIR/guard-lib.sh"`, guard-lib.sh ships with the floor, the floor is
# not installed, so both exit 1 at SessionStart and Stop with zero output. Every
# session believed it was syncing a git-backed work-log and none of them were.
# Checked by SOURCE-ABILITY, not by mention: the file either exists or it does
# not, and a grep for the name would pass on the comment describing the bug.
for h in worklog-push.sh; do
  if [ -f "$CFG/bin/$h" ]; then
    dep="$(sed -n 's/^\. "\$DIR\/\([a-z-]*\.sh\)".*/\1/p' "$CFG/bin/$h" 2>/dev/null | head -1)"
    if [ -n "$dep" ] && [ ! -f "$CFG/bin/$dep" ]; then
      # VERIFY THE CHECKOUT FIRST, and that clause is not politeness. Unlike
      # floor-deny.sh, an installer cannot be moved into the config dir — it
      # resolves its source from its own directory, so a copy in $CFG/bin would
      # install $CFG/bin onto itself. It therefore stays at a path a session CAN
      # write to (measured: >>, cp, sed -i, > and the Edit tool are all allowed
      # under ~/harbor/bin, all blocked under $CFG/bin), and this line is pasted
      # into the operator's own unguarded shell with --live. `git status` is the
      # cheapest thing that turns "trust the path" into "check the path", and it
      # is the operator's own repo, so a dirty tree is information either way.
      #
      # `diff --quiet HEAD -- bin/`, NOT `status --short`. The first spelling of
      # this gated NOTHING: `git status --short` exits 0 whether the tree is
      # clean or filthy, so the && always fired and the check was theatre. It was
      # also scoped to one file while the installer copies the whole payload.
      # `diff --quiet` exits 1 on any modification, and `-- bin/` covers every
      # script the installer will read.
      # The live box is reinstalled through deploy, the one live entry (the install standard §4); a
      # sandbox by the installer at that dir, --dir spelled (harbor#800). Each behind the same check.
      _wl="work-log DEAD: bin/$h sources bin/$dep, which is not installed — the log has not synced. Fix, after confirming the checkout is clean (a session can write to it):"
      if [ "$TGT" = --live ]; then add "$_wl git -C ~/port/harbor diff --quiet HEAD -- bin/ && sh ~/port/harbor/bin/deploy.sh --only runtime --apply --live"
      else add "$_wl git -C ~/port/harbor diff --quiet HEAD -- bin/ && sh ~/port/harbor/bin/deploy-runtime-install.sh --apply --dir $CFGQ"; fi
      break
    fi
  fi
done

# ── 2 · the work-log remote ──────────────────────────────────────────────────
# A second, independent break: origin exists but the branch has no upstream, so
# even a repaired hook cannot `git push` without explicit refspec arguments.
if [ -d "$CFG/MEMORY/.git" ] && command -v git >/dev/null 2>&1; then
  if ! git -C "$CFG/MEMORY" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    add "work-log branch has NO UPSTREAM (origin exists) — a repaired push still needs one. Fix: git -C ~/.claude/MEMORY branch --set-upstream-to=origin/main main"
  fi
fi

# ── 3 · floor teeth ──────────────────────────────────────────────────────────
# Drift here is not automatically a defect: a deliberate settings edit produces
# it, and the answer is a re-pin, not a rollback. So the verdict names BOTH
# possibilities rather than accusing the operator of tampering with their own box.
if [ -f "$S" ] && command -v jq >/dev/null 2>&1; then
  if [ -f "$CFG/.helm-floor-teeth" ]; then
    _pin="$(cat "$CFG/.helm-floor-teeth" 2>/dev/null)"
    _live="$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" 2>/dev/null | sha)"
    [ "$_pin" = "$_live" ] || \
      add "floor teeth DRIFT: settings.json no longer matches the pin. If you changed deny deliberately: sh $CFGQ/bin/floor-deny.sh $TGTQ --repin (adds nothing). If you did not, investigate before re-pinning."
  else
    add "floor teeth UNPINNED: nothing detects a change to permissions.deny. Fix: sh $CFGQ/bin/floor-deny.sh $TGTQ --repin"
  fi
fi

# ── 4 · the guards ───────────────────────────────────────────────────────────
# Asks the HOOK TABLE, not the filesystem, and not a substring of the file: a
# deny entry naming a guard is text, and pass-4 of the floor review caught that
# exact test reporting an uninstalled floor as installed.
if [ -f "$S" ] && command -v jq >/dev/null 2>&1; then
  _g="$(jq '[.hooks.PreToolUse[]?.hooks[]?.command // empty] | map(select(test("guard-"))) | length' "$S" 2>/dev/null || echo 0)"
  [ "${_g:-0}" -eq 0 ] && \
    add "no guard is wired: B1 deny is live, B2-B6 are not. bin/eval-pass-score.sh exits 2 — the latest adversarial pass still reports criticals, so this is the CURRENT CORRECT STATE, not a todo."
fi

# ── 5 · the judge ────────────────────────────────────────────────────────────
# bin/audit-triage-run.sh writes this cache from a scheduled job; nothing here runs the
# judge, because judging is 7 seconds and this hook is on the session's own path.
#
# SILENT WHEN THE CACHE IS ABSENT, and that is not an oversight. A box where the
# operator chose not to install the job would otherwise be told so at the top of
# every session — the wallpaper failure this file's own header exists to prevent,
# and §2.11's false-positive rule. So the only two things that speak are a cache
# that says `crit` and a cache that has STOPPED BEING WRITTEN, which is the
# scheduled job dying: the state a zero-byte log cannot distinguish from health.
#
# AGE COMES FROM mtime, DISPLAY FROM THE STAMP. `find -mtime` is POSIX and needs
# no date arithmetic; the writer renames the file into place on every run, so
# mtime is the write time. The stamp is printed because it is the thing the
# operator can check against the judge's own output if the two ever disagree.
JV="$CFG/.helm-judge"
if [ -f "$JV" ]; then
  _jhead="$(head -1 "$JV" 2>/dev/null)"
  _jstamp="$(printf '%s' "$_jhead" | awk '{print $2}')"
  if [ -n "$(find "$JV" -mtime +2 -print 2>/dev/null)" ]; then
    # The job's own restart, per platform (harbor#618): launchd on macOS, a systemd user unit elsewhere.
    case "$(uname -s 2>/dev/null)" in
      Darwin) _jcheck="launchctl kickstart -k gui/\$(id -u)/com.harbor.judge" ;;
      *) _jcheck="systemctl --user start harbor-judge.service; journalctl --user -u harbor-judge.service -n 20" ;;
    esac
    add "ledger judge STALE: last verdict $_jstamp and the daily job has not written since. The judge is not reporting clean — it is not reporting. Check: $_jcheck"
  else
    # One verdict per crit finding, carrying the judge's own repair text. Warns
    # are deliberately NOT surfaced here: they are the batch-review tier, and a
    # session-start channel that carries nine warnings is one nobody reads.
    while IFS= read -r _jl; do
      case "$_jl" in
        crit\ *) add "ledger judge CRIT: $(printf '%s' "${_jl#crit }" | awk -F'|' '{print $1": "$2" — fix: "$3}')" ;;
      esac
    done < "$JV"
  fi
fi

# ── 6 · the installed surface's own references (harbor#462) ─────────────────
# WHY THIS IS HERE AND NOT ON A SCHEDULE. bin/drift-reference-check.sh asks whether the
# copy of Harbor that actually RUNS holds together: every hook command names a
# file that exists, every pin has its file, every citation in the constitution
# resolves. It has existed since 2026-08-03 and NOTHING HAS EVER RUN IT — it is
# in no hook, no plist and no CI job, only in docs/how-to/handover.md as a command a human
# types. A checker nobody runs is a checker that does not exist.
#
# INLINE, NOT A CACHE, AND THE REASON IS THE MEASUREMENT. audit-triage-run.sh was moved
# off the session path because a full judge is 7 SECONDS; this is 0.22s, measured
# five times on this box 2026-09-06 AFTER this rewrite — the pre-rewrite figure
# was 0.19s and citing it would be quoting a number for code that does not ship. Below a threshold the cache stops being an
# optimisation and becomes a second failure mode — §5's own header records that a
# cache which has STOPPED BEING WRITTEN is indistinguishable from a clean box, and
# it needs a staleness rule to tell those apart. Running the check is cheaper than
# owning that problem.
#
# ONE LINE PER RULE, NOT ONE PER FINDING, and that is this file's own doctrine
# rather than a preference: the live box carries TEN dead citations from a single
# cause with a single repair, and ten lines at every session start is the
# wallpaper failure the header opens by naming. The detail is one command away and
# the line says which one.
#
# STAMPED `[check:reference-check]` because docs/reference/checks.md requires it: every alert
# resolves to its registry row, and from there to the command that switches it
# off, without anyone opening the source.
#
# IT READS $CFG/bin, NEVER THE REPO. The judge plist argues this at length and it
# is a security property, not a convention: a session can write to ~/port/harbor/bin
# and cannot write under $CFG/bin, so a SessionStart hook that executed the repo
# copy would let any session inject code into every future session on this box.
# Silent when it is not installed — a box whose operator has not deployed it is
# not a box to nag every session (§2.11).
RCHK="$CFG/bin/drift-reference-check.sh"
if [ -f "$RCHK" ] && command -v jq >/dev/null 2>&1; then
  _rj="$(sh "$RCHK" "$CFG" --json 2>/dev/null)"
  # An unparseable payload is NOT silence. Same rule as audit-triage-run.sh applies to
  # its own cache: "I could not look" must never render as "there is nothing to
  # see", which is the precise failure this whole section exists to end.
  if printf '%s' "$_rj" | jq -e 'has("findings")' >/dev/null 2>&1; then
    _rn="$(printf '%s' "$_rj" | jq -r '.findings | length')"
    if [ "${_rn:-0}" -gt 0 ] 2>/dev/null; then
      _rr="$(printf '%s' "$_rj" | jq -r '[.findings[].rule] | group_by(.) | map("\(.[0])x\(length)") | join(" ")')"
      add "[check:reference-check] INSTALLED SURFACE: $_rn reference(s) do not resolve ($_rr). This is the copy every session loads. Detail: sh $CFGQ/bin/drift-reference-check.sh $RCQ"
    fi
  else
    add "[check:reference-check] could not run the installed-surface check — that is not a clean result. Try: sh $CFGQ/bin/drift-reference-check.sh $RCQ"
  fi
fi

[ -z "$V" ] && exit 0

MSG="HARBOR — standing verdicts (once per session; the statusline carries what moves)
$V"

if command -v jq >/dev/null 2>&1; then
  jq -n --arg m "$MSG" '{systemMessage: $m}'
else
  # No jq: say it on stderr rather than emit malformed JSON that the harness
  # would report as a hook error. Degrading to silence would hide a dead worklog.
  printf '%s\n' "$MSG" >&2
fi
exit 0
