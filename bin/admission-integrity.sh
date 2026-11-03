#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# B6 (harbor#3) — recurring fail-CLOSED SessionStart integrity gate.
# Asserts at every session start that the floor is intact: (1) permissions.deny + mode locks + plugins + marketplaces hash-match the pinned baseline (.sec0-baseline.sha256), (2) every floor guard is present, non-empty and still carries the kill-switch on its first live line, (3) every floor hook is wired in settings.json and every hook command wired into this bin/ names a file that runs as wired (harbor#960). On drift it BLOCKS the session; a clean state passes silently.
# INSTALLS LAST, after the floor is live and verified (docs/explanation/admission-baseline.md order): a gate that blocks sessions must never be what breaks the install.
# Mechanism: a SessionStart hook CANNOT block via exit code (exit 2 is a non-blocking error there); the only hard stop is {"continue": false} on stdout, alongside systemMessage (operator) and additionalContext (model). Threat model (REVIEW F10): InstallHooks.ts / InstallSettings.ts re-edit settings.json after any fork upgrade, which is the drift this catches.
# Removed notes: docs/explanation/code-cases/bin-admission-integrity.md
set -u
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"
# harbor#1390: a hook run carries a session id, and only a session records what B8 named (see B8 below); a terminal stdin is a hand run with no payload, never something to wait on.
FLOOR_IN=''
# shellcheck disable=SC2034 # FLOOR_IN is read by floor_field in library-admission.sh, not here.
[ -t 0 ] || floor_read_stdin || FLOOR_IN=''
SELF_SID="$(floor_field '.session_id')"
case "$SELF_SID" in *[!A-Za-z0-9_-]*) SELF_SID='' ;; esac

CFG="$(floor_config_dir)"
S="$CFG/settings.json"
PIN="$CFG/.sec0-baseline.sha256"
# pin-instructions.sh is here because B6 TRUSTS it: its advisory tells the operator to run it and floor-verify calls it; an edited copy reported the surfaces clean over a live injection (pass 10, RT10-03).
GUARDS="admission-bash.sh admission-egress.sh admission-self-edit.sh annotate-web.sh pin-instructions.sh"
PINDIR="$CFG/.helm-pins"


# Which dir the recovery command names (harbor#110): `--live` in admission-deny.sh and deploy-restore.sh means literally $HOME/.claude (the accident gate against rewriting the real box from a sandbox verdict), but $CFG follows CLAUDE_CONFIG_DIR. So the hint names the dir the verdict was measured against: `--live` when they are the same, the positional or --dir form when not. The physical compare is P11-01's (a trailing slash must not decide which box an operator is told to rewrite).
# LIVE_DIR, not a bare path: lint D1 allows naming the live dir to COMPARE it; nothing here operates on it, $CFG is the only dir this gate touches.
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
LIVE_DIR="$HOME/.claude"
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then TGT="--live"; else TGT="$CFG"; fi
# The hint is a command the operator PASTES, so every path in it is shell-quoted (PR #113): a config dir with a space split into two arguments and aimed deploy-restore.sh and admission-deny.sh at different dirs. Quoting `--live` too is harmless and leaves no branch to get wrong.
_shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
CFGQ="$(_shq "$CFG")"
# floor-deny takes --live or --dir PATH, never a positional dir (harbor#800): a sandbox is spelled --dir.
if [ "$TGT" = "--live" ]; then TGTQ="$(_shq "$TGT")"; else TGTQ="--dir $CFGQ"; fi
# deploy-restore.sh takes --live or --dir, and writes only with --apply (harbor#765).
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then RESTORE="sh $CFGQ/bin/deploy-restore.sh '--live' --apply"
else RESTORE="sh $CFGQ/bin/deploy-restore.sh --dir $CFGQ --apply"; fi
# pin-instructions.sh takes the same two spellings (harbor#765): its --live is $HOME/.claude only, so a sandbox verdict must name --dir or the re-pin blesses the wrong box.
if [ "$(_phys "$CFG")" = "$(_phys "$LIVE_DIR")" ]; then REPIN_B8="sh $CFGQ/bin/pin-instructions.sh --apply --live"
else REPIN_B8="sh $CFGQ/bin/pin-instructions.sh --apply --dir $CFGQ"; fi

DRIFT=""
# Tracked apart from $DRIFT because the RECOVERY differs by class: settings or teeth drift is re-pinned with admission-deny.sh, guard CONTENT drift is not (floor-deny never writes .helm-pins). See $RECOVER at the end.
PINDRIFT=""
WIREDRIFT=""  # a wired hook file that cannot run: its recovery is the file or the wiring (harbor#960)
OTHERDRIFT=""
note() { DRIFT="${DRIFT}${DRIFT:+; }$1"; OTHERDRIFT=1; }
wnote() { DRIFT="${DRIFT}${DRIFT:+; }$1"; WIREDRIFT=1; }

# Fail CLOSED: a missing pin or missing jq means the gate cannot verify, which is itself a drift verdict (the opposite of the fail-open guards).
if ! command -v jq >/dev/null 2>&1; then note "jq unavailable — integrity cannot be verified"
elif [ ! -f "$S" ];   then note "settings.json missing at $S"
elif [ ! -f "$PIN" ]; then note "baseline pin missing at $PIN"
else
  WANT="$(cat "$PIN" 2>/dev/null)"
  HAVE="$(jq -S '{perms:.permissions, plugins:(.enabledPlugins // {}), marketplaces:(.extraKnownMarketplaces // {}), keys:((keys) - ["hooks"])}' "$S" 2>/dev/null | floor_sha)"
  [ -n "$HAVE" ] || note "settings.json unreadable or invalid JSON"
  if [ -n "$HAVE" ] && [ "$HAVE" != "$WANT" ]; then
    # Distinguish the floor's TEETH from ordinary user state. enabledPlugins and extraKnownMarketplaces are written by the /plugin UI: hashing them into a fail-CLOSED gate locked the operator out of every session on installing a plugin, with a recovery hint that would silently uninstall it (red-team pass 3). Plugin drift is still reported, not blocking, because plugins ship hooks and skills (REVIEW F13).
    # harbor#221: the same tiering carries the rest of settings.json. The projection used to name four fields, so a slash command rewriting the file (a new top-level `autoMode` key) went unseen. `perms:.permissions` covers allow, ask, defaultMode and additionalDirectories; the `keys` arm watches top-level key NAMES without hashing volatile user state.
    # `hooks` is excluded from the key set: admission-install.sh writes the hook wiring AFTER it pins the baseline, so a fresh install reported drift against itself (No.2.11). No coverage is lost, since check_wired asserts each hook under the right event with a matcher that can fire.
    # The new coverage is ADVISORY, not teeth: "always allow" writes `permissions.allow`, an ordinary act, and a fail-closed gate over it would reproduce the /plugin lockout. deny and the two locks stay fail-closed; the rest is reported and re-pinnable.
    TEETH="$(jq -S '{deny:.permissions.deny, locks:{bypass:.permissions.disableBypassPermissionsMode, auto:.permissions.disableAutoMode}}' "$S" 2>/dev/null | floor_sha)"
    TEETH_WANT="$(cat "$CFG/.helm-floor-teeth" 2>/dev/null || true)"
    if [ -n "$TEETH_WANT" ] && [ "$TEETH" = "$TEETH_WANT" ]; then
      # `--repin`, NOT `--apply`: deny and the locks are intact (only plugin/marketplace hashes moved), and `--apply` re-adds the full B1 entry set, which RESURRECTS entries the operator withdrew (admission-deny.sh's WITHDRAWN list). Same idiom as session-verdicts.sh.
      ADVISORY="settings.json changed outside the floor's teeth since the baseline was pinned — plugins, marketplaces, a permissions field other than deny/the locks, or a new top-level key (deny + locks intact) — re-pin with: sh $CFGQ/bin/admission-deny.sh $TGTQ --repin (adds nothing)"
    else
      note "permissions.deny or the mode locks changed since the baseline was pinned"
    fi
  fi

  # Every floor hook still wired, under the RIGHT EVENT and a matcher that can fire for the tools the guard inspects.
  check_wired() { # <event> <tool> <guard>
    jq -e --arg ev "$1" --arg t "$2" --arg g "$3" '
      (.hooks[$ev] // [])
      | map(select(((.matcher // "") | split("|")) | index($t)))
      | map(.hooks[]?.command) | map(select(test("(^|/)" + $g + "( |$)"))) | length > 0' \
      "$S" >/dev/null 2>&1 || note "hook not wired: $3 for $1($2)"
  }
  check_wired PreToolUse  Bash      admission-bash.sh
  check_wired PreToolUse  Bash      admission-egress.sh
  check_wired PreToolUse  Write     admission-egress.sh
  check_wired PreToolUse  Edit      admission-egress.sh
  check_wired PreToolUse  Write     admission-self-edit.sh
  check_wired PreToolUse  Edit      admission-self-edit.sh
  # The surfaces guard-egress was never routed to until pass 11 (P11-W1).
  check_wired PreToolUse  WebFetch  admission-egress.sh
  check_wired PreToolUse  Task      admission-egress.sh
  check_wired PostToolUse WebFetch  annotate-web.sh
  # Gated on the pin so a box installed before these guards existed cannot false-alarm: admission-install.sh pins and wires them in one run, so a missing hook where the pin exists is real drift. Unwiring is cheaper than editing, and nothing caught a deleted hook entry.
  for _cg in admission-cloud.sh admission-destroy.sh admission-deliverables.sh; do
    [ -f "$PINDIR/$_cg.sha256" ] || continue
    check_wired PreToolUse Bash "$_cg"
  done
  # admission-deliverables answers on the FILE TOOLS too; narrowing the shared matcher to `Bash` is a one-word edit that would leave every Write of a loose document ungated, silently.
  if [ -f "$PINDIR/admission-deliverables.sh.sha256" ]; then
    check_wired PreToolUse Write admission-deliverables.sh
  fi
  # admission-api-route.sh repairs AFTER a call, so it is PostToolUse with a Bash matcher (the reroute came from a program a shell command ran). Gated on the pin as above.
  if [ -f "$PINDIR/admission-api-route.sh.sha256" ]; then
    check_wired PostToolUse Bash admission-api-route.sh
  fi
  # The box merge gate (harbor#516): an unwired entry is the cheap way to disarm it.
  if [ -f "$PINDIR/govern-hook.sh.sha256" ]; then
    check_wired PreToolUse Bash govern-hook.sh
  fi

  # Every wired command must name a file that RUNS, pinned or not (harbor#960): a hook whose file is gone exits 127, which Claude Code treats as non-blocking, so the guard is off. The checks above are gated on a pin under the OLD name, so renaming a script and its pin together passed silently. Scope is this config dir's bin/.
  # Tokens honour double and single quotes; $HOME, ${HOME}, ~ and $CLAUDE_CONFIG_DIR expand outside single quotes, as the hook's shell would. As wired: the command word needs +x (126 otherwise); a file handed to an interpreter must be readable and non-empty (an empty script exits 0).
  _wired="$(jq -r --arg sq "'" --arg home "$HOME" --arg cfg "$CFG" '
    def expand: sub("^~/"; $home + "/") | sub("^\\$(HOME|\\{HOME\\})/"; $home + "/")
              | sub("^\\$(CLAUDE_CONFIG_DIR|\\{CLAUDE_CONFIG_DIR\\})/"; $cfg + "/");
    (.hooks // {}) | to_entries[] | .key as $ev | (.value | arrays)[] | (.hooks | arrays)[]
    | (.command | strings)
    | [scan("\"[^\"]*\"|" + $sq + "[^" + $sq + "]*" + $sq + "|[^ \t\"" + $sq + ";|&()<>]+")]
    | to_entries[]
    | (if (.value | startswith($sq)) then .value[1:-1]
       elif (.value | startswith("\"")) then (.value[1:-1] | expand) else (.value | expand) end) as $p
    | select($p | startswith("/"))
    | [$ev, (if .key == 0 then "exec" else "read" end), $p] | @tsv' "$S" 2>/dev/null)" \
    || note "settings.json hooks could not be read — wired hook files cannot be verified"
  _bin="$CFG/bin"; _binp="$(_phys "$CFG")/bin"; _wseen=" "
  _tab="$(printf '\t')"
  while IFS="$_tab" read -r _wev _wmode _wp; do
    [ -n "$_wp" ] || continue
    case "$_wp" in
      "$_bin"/*|"$_binp"/*) ;;
      *) # Another spelling of the same dir (a symlink, /tmp vs /private/tmp): resolve it.
         _wd="${_wp%/*}"
         case "$_wd" in ''|/bin|/usr/bin|/usr/local/bin|/opt/homebrew/bin) continue ;; esac
         [ "$(_phys "$_wd")" = "$_binp" ] || continue ;;
    esac
    case "$_wseen" in *" $_wmode:$_wp "*) continue ;; esac
    _wseen="$_wseen$_wmode:$_wp "
    if [ ! -f "$_wp" ]; then
      wnote "wired hook file missing: $_wp ($_wev) — the hook exits 127 and is silently off"
    elif [ ! -r "$_wp" ] || [ ! -s "$_wp" ]; then
      wnote "wired hook file empty or unreadable: $_wp ($_wev) — the hook checks nothing"
    elif [ "$_wmode" = exec ] && [ ! -x "$_wp" ]; then
      wnote "wired hook not executable: $_wp ($_wev) — it is run directly and exits 126"
    fi
  done <<EOF
$_wired
EOF
fi

# ── WHAT GETS CHECKED IS DERIVED FROM THE PINS ON DISK, NOT LISTED HERE ──────
# This used to be a hand-written list, one of four copies of one set (admission-install.sh's payload, $GUARDS, deploy-runtime-install.sh's drift report, admission-verify.sh's presence loop), and they had drifted: admission-cloud.sh and admission-destroy.sh were shipped, wired and PINNED, yet no verifier read those pins back, so gutting both to `exit 0` passed silently.
# $GUARDS stays as the floor MINIMUM rather than being replaced by the pin dir: deriving only from pins means deleting a pin removes its guard from the check, and the `no content pin for` branch below is what makes a deleted pin visible. Union, so neither direction can hide a file.
CHECK="$GUARDS library-admission.sh admission-normalize.awk"
for _pf in "$PINDIR"/*.sha256; do
  # POSIX sh has no nullglob: an unmatched pattern arrives as the literal string, so this guard is real.
  [ -f "$_pf" ] || continue
  _g="${_pf##*/}"; _g="${_g%.sha256}"
  # B6 does not check B6 (No.2.11): deploy-runtime-install.sh carries admission-integrity.sh in REFRESH_ONLY and deliberately does NOT move its pin (the operator's to move), so checking it would make every `runtime-install --apply` block the next session.
  [ "$_g" = "admission-integrity.sh" ] && continue
  case " $CHECK " in *" $_g "*) ;; *) CHECK="$CHECK $_g" ;; esac
done

# Every guard present, non-empty, and still carrying the kill-switch.
for g in $CHECK; do
  f="$CFG/bin/$g"
  [ -s "$f" ] || { note "guard missing or empty: $g"; continue; }
  # Content hash, not mere presence: a guard truncated to its kill-switch line plus `exit 0` passed every earlier check (red-team pass 6).
  if [ -f "$PINDIR/$g.sha256" ]; then
    _want="$(cat "$PINDIR/$g.sha256" 2>/dev/null)"
    _have="$(floor_sha < "$f")"
    if [ "$_want" != "$_have" ]; then
      note "guard modified since it was pinned: $g"
      # Tracked separately: the RECOVERY for content drift is not the settings/teeth recovery (see $RECOVER below).
      PINDRIFT="${PINDRIFT}${PINDRIFT:+ }$g"
    fi
  else
    note "no content pin for $g (run admission-install.sh to pin)"
  fi
  case "$g" in
    # Not hooks: sourced library, data, and the operator's pinning tool. They are content-pinned above but have no kill-switch line to carry. Exempting a file needs measurement: requiring the kill-switch of files whose first live line is `set -u` would raise a session-BLOCKING alarm the moment the pin dir became the source of truth (No.2.11), as deploy-harden.sh showed by turning the RESTORE path into a lockout (Q-R6).
    # admission-observe.sh is a wired SessionStart hook, so its exemption is a finding rather than a category; left on purpose (an observer writing a ledger under a disabled floor is not a gate acting). floor-test X15 asserts the list below stays EXHAUSTIVE, so the next pinned file without a kill-switch goes red in CI, not at the operator's next SessionStart.
    # baseline-pin.sh is retired (harbor#765) but stays exempt while boxes still carry its pin. library-log.sh and deploy-install-lib.sh are sourced libraries of the recovery path (harbor#771, #765).
    # NO-KILLSWITCH (read by floor-test X15 — keep it one line, `|`-separated):
    library-admission.sh|admission-normalize.awk|pin-instructions.sh|admission-observe.sh|deploy-restore.sh|baseline-pin.sh|deploy-harden.sh|library-log.sh|deploy-install-lib.sh) ;;
    *)
      # $FLOOR_GREP, not bare grep: this IS the kill-switch presence check and the pinned interpreter is in scope; a grep-resolution difference decides whether the gate blocks the session.
      line="$("$FLOOR_GREP" -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | "$FLOOR_GREP" -vE '^#!' | head -1)"
      case "$line" in
        *HARBOR_ADMISSION_DISABLE*) ;;
        *) note "kill-switch missing from $g (first live line: ${line:-<empty>})" ;;
      esac
      ;;
  esac
done

# ── B8 (harbor#38) · the persistent INSTRUCTION surfaces ────────────────────
# CLAUDE.md, agents/, skills/, commands/, output-styles/ load into every session, so a write there is an instruction followed from the NEXT session on. They stay writable by owner decision; this makes the change visible at the session where it first takes effect.
# ADVISORY, not blocking: these are edited as ordinary work, and fail-closed would turn "I added a skill" into a lockout (undone once already for plugins, red-team pass 3). Reported is not ignored: the message names the changed paths and the model sees it too.
if [ -f "$CFG/.helm-instructions.sha256" ]; then
  _now="$(floor_instr_manifest "$CFG" 2>/dev/null || true)"
  if [ ! -r "$CFG/.helm-instructions.sha256" ]; then
    # A pin that cannot be read used to fall through to the diff and print the content-free "(0 path(s): )" (red-team B8-07).
    ADVISORY="${ADVISORY:+$ADVISORY; }the instruction pin exists but cannot be read — the instruction surfaces are NOT being checked"
  elif [ -z "$_now" ]; then
    # An empty manifest is "could not build", never "nothing to see".
    ADVISORY="${ADVISORY:+$ADVISORY; }the instruction manifest came back empty — the instruction surfaces could NOT be checked"
  elif _d="$(printf '%s\n' "$_now" | floor_instr_diff "$CFG/.helm-instructions.sha256")"; [ -z "$_d" ]; then
    # Clean: nothing is standing, so the next change is named whatever was named before the re-pin (harbor#1390).
    [ -z "$SELF_SID" ] || rm -f "$CFG/.helm-context/instructions.seen" 2>/dev/null || :
  else
    # Count PATHS, not diff lines (a change yields a `<` and a `>`). The path is everything after the two-space separator: `awk '{print $NF}'` reported "skill.md" for "my evil skill.md" (red-team B8-06).
    _paths="$(printf '%s\n' "$_d" | sed -E 's/^[<>][[:space:]]//; s/^[^[:space:]]*[[:space:]][[:space:]]//' | sort -u)"
    _n="$(printf '%s\n' "$_paths" | "$FLOOR_GREP" -c . || true)"
    # ── DRIFT HAS TWO CLASSES (harbor#135): `projects/*/memory` is watched because auto-memory is injected into every session, but the MODEL writes it as ordinary work, so a permanently red advisory went unread. Dropping it from the watch list was refuted (B8-NOISE-06); the classes are SPLIT instead, so a real instruction-surface change does not arrive inside a sentence the reader learned to skip. Both are still reported and need the same deliberate re-pin.
    # `(/|$)`, not a bare `/`: floor_instr_manifest emits an unmatched glob LITERALLY, so a config dir with no memory yet carries `projects/*/memory`; requiring the slash made a pure memory write read as an instruction-surface change naming a path that does not exist (B8-05).
    # ── A STANDING ADVISORY NAMES WHAT IS NEW (harbor#1390): the same changed paths reprinted at every SessionStart is an alarm the reader learns to skip. Every changed path is still COUNTED, but a path is NAMED only in the first session that sees its current content; the rest are summed with the age of the oldest.
    # The record is <cfg>/.helm-context/instructions.seen, `<epoch> TAB <key>` per changed path (the key is its manifest line now, `gone  <path>` once removed, so an edited path is new again). .helm-context is an integrity row, so a session cannot write the record to keep its own edit unnamed. Only a run with a session id writes it (`harbor verify` consumes nothing); a lost record names everything; a clean manifest deletes it (the re-pin).
    _seen="$CFG/.helm-context/instructions.seen"
    _now_s="$(date +%s 2>/dev/null || echo 0)"
    _seenw=''
    if [ -n "$SELF_SID" ] && mkdir -p "$CFG/.helm-context" 2>/dev/null; then _seenw="$_seen.$$"; fi
    # Out: `S TAB <path>` per standing path, then `A TAB <epoch>`, the oldest of them.
    _stand="$(printf '%s\n' "$_d" | _B8_SEEN="$_seen" _B8_SEENW="$_seenw" awk -v now="$_now_s" '
      BEGIN { f = ENVIRON["_B8_SEEN"]; o = ENVIRON["_B8_SEENW"]
              while ((getline l < f) > 0) { t = index(l, "\t"); if (t) seen[substr(l, t + 1)] = substr(l, 1, t - 1) } }
      { s = substr($0, 3); i = index(s, "  "); if (!i) next; p = substr(s, i + 2)
        if (substr($0, 1, 1) == ">") { key[s] = p; has[p] = 1 } else gone[p] = 1 }
      END {
        for (p in gone) if (!(p in has)) key["gone  " p] = p
        for (k in key) { p = key[k]
          if (k in seen) { e = seen[k]; if (!(p in age) || e + 0 < age[p] + 0) age[p] = e } else { fresh[p] = 1; e = now }
          if (o != "") print e "\t" k > o }
        m = ""; for (p in age) if (!(p in fresh)) { print "S\t" p; if (m == "" || age[p] + 0 < m + 0) m = age[p] }
        if (m != "") print "A\t" m }' 2>/dev/null || true)"
    if [ -n "$_seenw" ]; then
      if [ -f "$_seenw" ]; then mv -f "$_seenw" "$_seen" 2>/dev/null || rm -f "$_seenw"; else rm -f "$_seen" 2>/dev/null || :; fi
    fi
    _old_s="$(printf '%s\n' "$_stand" | awk -F'\t' '$1 == "A" { print $2 }')"
    _agep=''; [ -z "$_old_s" ] || _agep=", the oldest named $(( (_now_s - _old_s) / 86400 ))d ago"
    # A path is standing only when the record says so: any doubt names it.
    _newof() { printf '%s\n' "$1" | _B8_ST="$_stand" awk 'BEGIN { n = split(ENVIRON["_B8_ST"], a, "\n"); for (i = 1; i <= n; i++) if (substr(a[i], 1, 2) == "S\t") st[substr(a[i], 3)] = 1 }
      NF && !($0 in st)'; }
    _mem="$(printf '%s\n' "$_paths" | "$FLOOR_GREP" -E '^projects/[^/]*/memory(/|$)' || true)"
    _oth="$(printf '%s\n' "$_paths" | "$FLOOR_GREP" -Ev '^projects/[^/]*/memory(/|$)' || true)"
    _nmem="$(printf '%s\n' "$_mem" | "$FLOOR_GREP" -c . || true)"
    _noth="$(printf '%s\n' "$_oth" | "$FLOOR_GREP" -c . || true)"
    _repin="review them, then re-pin from YOUR OWN TERMINAL (not from a session) with: $REPIN_B8"
    if [ "${_noth:-0}" -gt 0 ]; then
      # The named paths are the NON-memory ones, always: a real instruction surface must never be what `head -6` truncated away.
      _onew="$(_newof "$_oth")"; _nonew="$(printf '%s\n' "$_onew" | "$FLOOR_GREP" -c . || true)"
      _chg="$(printf '%s\n' "$_onew" | head -6 | tr '\n' ' ' | sed 's/ $//')"
      [ "${_nonew:-0}" -gt 6 ] && _chg="$_chg …"
      if [ "${_nonew:-0}" -eq 0 ]; then _chg="0 new since the last session; all ${_noth} already named${_agep}"
      elif [ "${_nonew:-0}" -lt "${_noth:-0}" ]; then _chg="$_chg; $((_noth - _nonew)) more already named${_agep}"; fi
      _also=""
      [ "${_nmem:-0}" -gt 0 ] && _also=" (and ${_nmem} auto-memory file(s), which the model writes as ordinary work)"
      ADVISORY="${ADVISORY:+$ADVISORY; }INSTRUCTION SURFACES changed since pinning (${_noth} path(s): ${_chg})${_also} — these load into EVERY session; $_repin"
    else
      # The paths are still NAMED here: a count alone left B8-05 red, since an operator who cannot see which file changed cannot review it. Nothing is crowded out in this branch (the mixed case is handled above by putting non-memory paths first).
      _mnew="$(_newof "$_mem")"; _nmnew="$(printf '%s\n' "$_mnew" | "$FLOOR_GREP" -c . || true)"
      _mchg="$(printf '%s\n' "$_mnew" | head -6 | tr '\n' ' ' | sed 's/ $//')"
      [ "${_nmnew:-0}" -gt 6 ] && _mchg="$_mchg …"
      if [ "${_nmnew:-0}" -eq 0 ]; then _mchg="0 new since the last session; all ${_nmem:-?} already named${_agep}"
      elif [ "${_nmnew:-0}" -lt "${_nmem:-0}" ]; then _mchg="$_mchg; $((_nmem - _nmnew)) more already named${_agep}"; fi
      ADVISORY="${ADVISORY:+$ADVISORY; }auto-memory changed since pinning (${_nmem:-?} file(s): ${_mchg}) and no other instruction surface did — model-authored content that loads into every session, so it is reported rather than blessed; $_repin"
    fi
  fi

  # ── the index BUDGET, reported on the same channel as the drift ────────────
  # Here and not every session: store-check is slow (it derives the allowance via context-budget), a tax on every session start is how a guard earns being switched off (No.2.11), and the index can only GROW when a memory file is written, which is the condition this branch already detected.
  # Known gap: an index already over budget, unchanged and re-pinned goes quiet until the next memory write. Caching the derived allowance would be a second copy of a number that must agree with HARBOR_CONTEXT_CEILING; a gap that re-fires beats a copy that silently disagrees.
  if [ "${_nmem:-0}" -gt 0 ] && [ -x "$CFG/bin/memory-store-check.sh" ]; then
    _sc="$(sh "$CFG/bin/memory-store-check.sh" --json 2>/dev/null || true)"
    # jq, not a greedy regex (harbor#1420): that read the last byte-count in the document, not index.bytes.
    case "$(printf '%s' "$_sc" | jq -r '.index.over // false' 2>/dev/null)" in
      true)
        _ib="$(printf '%s' "$_sc" | jq -r '.index.bytes // empty' 2>/dev/null | head -1)"
        _ia="$(printf '%s' "$_sc" | jq -r '.index.allowance // empty' 2>/dev/null | head -1)"
        case "$(printf '%s' "$_sc" | jq -r '.full_index.tiered // false' 2>/dev/null)" in
          true) _ihow="move more pointers to INDEX-FULL.md" ;;
          *)                 _ihow="tier it — keep the always-on pointers in MEMORY.md and move the rest to INDEX-FULL.md, which is searched and never loaded" ;;
        esac
        ADVISORY="${ADVISORY:+$ADVISORY; }the memory INDEX is OVER its allowance (${_ib:-?} B against ${_ia:-?} B) — that overage is spent before your first word in EVERY session; $_ihow, or raise HARBOR_CONTEXT_CEILING deliberately. What to move: sh $CFG/bin/memory-store-check.sh"
        ;;
    esac
  fi
else
  ADVISORY="${ADVISORY:+$ADVISORY; }instruction surfaces are not pinned — CLAUDE.md/agents/skills/commands can change unseen; pin from your own terminal with: $REPIN_B8"
fi

if [ -z "$DRIFT" ]; then
  # Non-blocking advisory (plugin/marketplace drift): reported, never blocking.
  if [ -n "${ADVISORY:-}" ] && command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "HELM FLOOR: $ADVISORY" \
      '{systemMessage:$m, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$m}}'
  fi
  # OBSERVE-1 (harbor#41): this gate reaches a SESSION-BLOCKING verdict while exiting 0 (it denies via {"continue":false} on stdout, not exit 2), so a ledger built on "hook floor_block" would miss the only control that can stop a whole session. It is also the one script running `set -u` WITHOUT `-e`, so tests assert its stdout byte-for-byte rather than its exit code.
  if [ -n "${ADVISORY:-}" ]; then
    floor_log_decision integrity advise integrity-advisory.meta
  else
    floor_log_decision integrity allow integrity-clean.meta
  fi
  exit 0
fi

# THE RECOVERY DEPENDS ON WHAT DRIFTED: this message once named `admission-deny.sh --live --apply` for every class, including guard CONTENT drift, which it does nothing for (floor-deny never refreshes a content pin), so the gate blocked the session with an instruction that could not unblock it.
# The pin refresh is deliberately NOT wrapped in a tool: re-baselining the file that judges the agent is the operator's act (constitution, "Encoding a fix is a human-gated act"), and a script that did it would be reachable by the agent B6 exists to catch. So the gate hands over the exact command and stops, naming the hasher this machine has (sha256sum fails on macOS).
if command -v sha256sum >/dev/null 2>&1; then _shacmd="sha256sum"; else _shacmd="shasum -a 256"; fi
if [ -n "$PINDRIFT" ]; then
  # $TGTQ and $CFGQ, not `--live` and a bare $CFG (harbor#110): this branch kept a hardcoded `--live` (literally $HOME/.claude in deploy-restore.sh) and an unquoted $CFG, so a content drift measured on a SANDBOX printed a command that overwrites the real box.
  RECOVER="$RESTORE (restores the newest deploy snapshot and UNDOES the change; without --apply it shows the plan), or — if this content is intended — refresh the content pin from your OWN terminal: for g in $PINDRIFT; do $_shacmd < $CFGQ/bin/\$g | awk '{print \$1}' > $CFGQ/.helm-pins/\$g.sha256; done"
else
  # The re-pin command is `--repin`, not `--apply` (which re-adds the full B1 entry set and resurrects anything the operator withdrew), matching what session-verdicts.sh prints for this drift (harbor#103).
  # It stays a command for the operator to run from their own terminal rather than a script inside the config dir: `--repin` re-pins .sec0-baseline and .helm-floor-teeth, the two hashes this gate checks, so shipping it beside the gate would install a one-command amnesty.
  RECOVER="$RESTORE (restores the newest deploy snapshot; without --apply it shows the plan), or — if you changed deny deliberately — re-pin it deliberately: sh $CFGQ/bin/admission-deny.sh $TGTQ --repin (adds nothing)"
fi
# A dangling hook is fixed by the file or the wiring; floor-deny re-pins neither, so a wiring-only verdict does not name it.
if [ -n "$WIREDRIFT" ]; then
  if [ -z "$PINDRIFT" ] && [ -z "$OTHERDRIFT" ]; then RECOVER=""; else RECOVER="${RECOVER}; "; fi
  RECOVER="${RECOVER}for a wired hook file: $RESTORE puts back the file it last deployed, or — if the script was renamed on purpose — point the hook in $CFGQ/settings.json at its new path from your OWN terminal (hook wiring is outside the baseline, so no re-pin is needed)"
fi
MSG="HELM FLOOR INTEGRITY GATE — session BLOCKED. Drift detected: ${DRIFT}. Recover: ${RECOVER}. To open an unguarded session: HARBOR_ADMISSION_DISABLE=1 claude"

if command -v jq >/dev/null 2>&1; then
  jq -cn --arg m "$MSG" \
    '{continue:false, stopReason:$m, systemMessage:$m,
      hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$m}}'
else
  # No jq — emit the literal JSON rather than failing open on a drift verdict.
  printf '{"continue":false,"stopReason":"HELM FLOOR INTEGRITY GATE: drift detected and jq is unavailable to describe it. Run %s, or HARBOR_ADMISSION_DISABLE=1 claude."}\n' "$RESTORE"
fi
floor_log_decision integrity gate integrity-drift.meta
exit 0
