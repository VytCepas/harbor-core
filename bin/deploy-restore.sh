#!/usr/bin/env sh
# RECOVER (harbor#34, #765) — put a config dir back from a deploy snapshot.
#   sh deploy-restore.sh --live                  DRY RUN: which snapshot, what moves aside, what comes back
#   sh deploy-restore.sh --apply --live          restore the live ~/.claude from its newest backups/deploy-*/
#   sh deploy-restore.sh [--apply] --dir PATH    the same for another config dir (the live one needs --live)
#   --from SNAPSHOT   a backups/deploy-*/ dir, or a .tgz, instead of the newest snapshot
#   --accept-loss     restore even though it removes floor files or wiring the target has now
#   --dry-run         the default, said out loud;  -h, --help  this text
# Restores exactly the entries the snapshot holds. What is there now is MOVED to
# <dir>/backups/restore/<TS>/, beside the run's log, never deleted. MEMORY, backups/ and the ledger
# are never touched. Only a snapshot whose sha256 deploy recorded in .helm-snapshots is restored (#769).
# With --live, the snapshot's ~/.local/bin record (local-bin.tsv, harbor#770) puts its links back; an
# entry the record does not name is never touched, and neither is a file where it had a link.
# Standalone POSIX sh: installed to ~/.claude/bin beside library-log.sh and deploy-install-lib.sh, runs with no
# checkout. Exit 0 ok, 1 refused, 2 usage. Deliberately one file: the recovery path must run when
# every other file may be what broke.
#
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# A recovery path says what it needs rather than dying on a missing source line.
for _lib in library-log.sh deploy-install-lib.sh; do
  [ -f "$HERE/$_lib" ] && continue
  printf 'restore: %s is missing beside %s, so this copy cannot run. Run the checkout copy instead:\n' "$_lib" "$HERE" >&2
  printf '  sh %s/bin/deploy-restore.sh %s\n' "${HARBOR_SCOPE_REPO:-${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}}" "$*" >&2
  exit 1
done
. "$HERE/library-log.sh"
. "$HERE/deploy-install-lib.sh"
log_init restore

_die() { log_fail "$1"; log_nofix "${2:-harbor#765 — bin/deploy-restore.sh}"; log_end || :; exit 1; }
DRY=0; FROM=''
il_opt() {
  case "$1" in
    --dry-run) DRY=1; IL_TAKE=-1 ;;  # a mode word: il_cmd never replays it
    --from) il_value --from "${2-}"; [ -z "$FROM" ] || il_usage_error '--from given twice'; FROM="$2"; IL_TAKE=2 ;;
    *) IL_TAKE=0 ;;
  esac
}
# Every argument is parsed, in any position (harbor#765: only $1 was read, so --live --dry-run restored).
il_parse "$@"
[ "$IL_APPLY" -eq 0 ] || [ "$DRY" -eq 0 ] || il_usage_error '--apply and --dry-run are two modes; give one'
# Physical paths, so a trailing slash or a symlink cannot reach live without --live (P11-01); a
# CLAUDE_CONFIG_DIR naming another dir exits 2. An apply run's log opens here, so a refusal is kept.
il_target
TARGET="$IL_TARGET"
[ -d "$TARGET" ] || _die "no config dir at $TARGET" "the path given to --dir: it must be an existing config dir"

# ── SOURCE: --from, else the newest deploy snapshot by name (deploy-YYYYmmdd-HHMMSS-PID) ──
_candidates() {
  for _d in "$TARGET"/backups/deploy-*/; do
    [ -f "${_d}config.tgz" ] && printf '%s\n' "${_d%/}"
  done | LC_ALL=C sort
}
_list_candidates() { # the snapshots here, oldest first, one note each
  _lc="$(_candidates)"
  if [ -z "$_lc" ]; then log_note "no recorded-or-not snapshot is in $TARGET/backups"; return 0; fi
  printf '%s\n' "$_lc" | while IFS= read -r _c; do log_note "snapshot here (oldest first; name one with --from): $_c"; done
}
if [ -n "$FROM" ]; then
  if [ -d "$FROM" ]; then SNAP="$(_il_phys "$FROM")"; ARCHIVE="$SNAP/config.tgz"
  elif [ -f "$FROM" ]; then SNAP="$(_il_phys "$(dirname -- "$FROM")")"; ARCHIVE="$SNAP/$(basename -- "$FROM")"
  else _die "--from $FROM: no such snapshot" "the path given to --from: a backups/deploy-*/ dir or its config.tgz"; fi
  [ -f "$ARCHIVE" ] || _die "--from $FROM: no config.tgz in it" "the path given to --from: a backups/deploy-*/ dir or its config.tgz"
else
  SNAP="$(_candidates | tail -1)"
  [ -n "$SNAP" ] || _die "no deploy snapshot in $TARGET/backups (every deploy takes one before it installs)" \
    "name one with --from, or take one: a deploy snapshots the config dir before it installs"
  ARCHIVE="$SNAP/config.tgz"
fi
# Every hint names the snapshot this run evaluated, so il_cmd respells it (and drops --dry-run).
IL_ARGV="--from $(_il_sq "$SNAP")"
# ── THE HASH LEDGER (harbor#769): only bytes deploy recorded are restored ──
# backups/ is writable by a session and .helm-snapshots is not, so a snapshot is trusted only
# through its row there. No row, no restore: a missing ledger refuses everything, and the way
# back is the operator appending the row by hand. Nothing here writes the ledger.
LEDGER="$TARGET/.helm-snapshots"
_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }
SHA="$(_sha <"$ARCHIVE" 2>/dev/null || true)"
case "$SHA" in *[!0-9abcdef]*|'') _die "cannot hash $ARCHIVE" ;; esac
[ "${#SHA}" -eq 64 ] || _die "cannot hash $ARCHIVE"
case "$ARCHIVE" in "$TARGET"/*) REL="${ARCHIVE#"$TARGET"/}" ;; *) REL="$ARCHIVE" ;; esac
SETSHA=''
if [ "$ARCHIVE" = "$SNAP/config.tgz" ] && [ -f "$SNAP/set.txt" ]; then SETSHA="$(_sha <"$SNAP/set.txt")"; fi
_recorded() { [ -f "$LEDGER" ] && awk -v h="$SHA" '$1 == h { f = 1 } END { exit !f }' "$LEDGER"; }
if ! _recorded; then
  if [ -f "$LEDGER" ] && awk -v p="$REL" '$2 == p { f = 1 } END { exit !f }' "$LEDGER"; then
    log_fail "refusing $ARCHIVE: it CHANGED after deploy recorded it — its sha256 $SHA is not the one $LEDGER holds for that path"
    log_nofix "harbor#769 — do not record these bytes; pick another snapshot with --from (listed below)"
  else
    _why=''; [ -f "$LEDGER" ] || _why=' (the ledger does not exist: no deploy has recorded a snapshot here)'
    log_fail "refusing $ARCHIVE (sha256 $SHA): it is not recorded in $LEDGER, the ledger deploy appends a row to for every snapshot it takes$_why"
    log_fix "printf '%s\\n' '$SHA $REL $(date -u +%Y-%m-%dT%H:%M:%SZ)${SETSHA:+ set=$SETSHA}' >> '$LEDGER'"
    log_note 'backups/ is writable by a session and the ledger is not, so an unrecorded snapshot is never restored'
    log_note 'if you have checked this snapshot yourself, record it from your own terminal with the fix line above, then re-run'
  fi
  _list_candidates
  log_note 'nothing was touched'
  log_end || :
  exit 1
fi
# set.txt decides what moves aside, so it is held to the same record.
if [ -n "$SETSHA" ] && ! awk -v h="$SHA" -v s="set=$SETSHA" '$1 == h { for (i = 4; i <= NF; i++) if ($i == s) f = 1 } END { exit !f }' "$LEDGER"; then
  _die "$SNAP/set.txt is not the set deploy recorded for this snapshot (its sha256 differs): refusing it; nothing was touched" \
    "harbor#769 — pick another snapshot with --from"
fi
# So is the ~/.local/bin record: a link it names lands on PATH (harbor#770).
LBREC=''
if [ "$ARCHIVE" = "$SNAP/config.tgz" ] && [ -f "$SNAP/local-bin.tsv" ]; then
  LBREC="$SNAP/local-bin.tsv"
  _lbsha="$(_sha <"$LBREC")"
  if ! awk -v h="$SHA" -v s="bin=$_lbsha" '$1 == h { for (i = 4; i <= NF; i++) if ($i == s) f = 1 } END { exit !f }' "$LEDGER"; then
    _die "$LBREC is not the ~/.local/bin record deploy made for this snapshot (its sha256 differs): refusing it; nothing was touched" \
      "harbor#770 — pick another snapshot with --from"
  fi
fi
# Unreadable is refused, never skipped for an older one: that would restore a state nobody picked.
if ! MEMBERS="$(tar -tzf "$ARCHIVE" 2>/dev/null)"; then
  log_fail "$ARCHIVE is unreadable (truncated, or not a tar.gz) — nothing was touched"
  log_nofix "harbor#765 — pick another snapshot with --from (listed below)"
  _list_candidates
  log_end || :
  exit 1
fi
PFX=''
case "$MEMBERS" in ./*) PFX='./' ;; esac
MEMBERS="$(printf '%s\n' "$MEMBERS" | sed 's|^\./||')"
if printf '%s\n' "$MEMBERS" | awk '/^\// || /(^|\/)\.\.(\/|$)/ || /^-/ { bad = 1 } END { exit !bad }'; then
  _die "$ARCHIVE has a member outside the config dir (absolute, .. or -): refusing it"
fi
TOPS="$(printf '%s\n' "$MEMBERS" | awk -F/ '$1 != "" && $1 != "." { print $1 }' | LC_ALL=C sort -u)"

# ── THE SET: deploy's set.txt (names and globs, absent ones included), else the archive's own entries ──
SET_GLOB=0
if [ "$ARCHIVE" = "$SNAP/config.tgz" ] && [ -f "$SNAP/set.txt" ]; then SET="$(cat "$SNAP/set.txt")"; SET_GLOB=1
else SET="$TOPS"; fi
_NL='
'
_skipped=''
_set=''
while IFS= read -r _e; do
  case "$_e" in
    '') continue ;;
    MEMORY|backups|.helm-snapshots) _skipped="$_skipped $_e" ;;  # kept in the set; _in_set is the one guard
    .|..|*/*|-*|[*?[]*) _die "the snapshot's set names '$_e', which is not a top-level entry: refusing it" ;;
  esac
  _set="$_set$_e$_NL"
done <<EOF
$SET
EOF
_in_set() { # <top-level name>
  case "$1" in MEMORY|backups|.helm-snapshots) return 1 ;; esac
  while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    if [ "$SET_GLOB" -eq 1 ]; then
      # shellcheck disable=SC2254
      case "$1" in $_p) return 0 ;; esac
    else
      [ "$1" = "$_p" ] && return 0
    fi
  done <<EOF
$_set
EOF
  return 1
}
_has_top() { case "$_NL$TOPS$_NL" in *"$_NL$1$_NL"*) return 0 ;; esac; return 1; }
_archive_has() { case "$_NL$MEMBERS$_NL" in *"$_NL$1$_NL"*|*"$_NL$1/$_NL"*) return 0 ;; esac; return 1; }

MOVE=''; BACK=''; GONE=''
while IFS= read -r _e; do
  if [ -z "$_e" ] || ! _in_set "$_e"; then continue; fi
  MOVE="$MOVE$_e$_NL"
  _has_top "$_e" || GONE="$GONE $_e"
done <<EOF
$(ls -A "$TARGET")
EOF
while IFS= read -r _e; do
  [ -n "$_e" ] && _in_set "$_e" && BACK="$BACK$_e$_NL"
done <<EOF
$TOPS
EOF
_moves() { case "$_NL$MOVE" in *"$_NL$1$_NL"*) return 0 ;; esac; return 1; }

# ── FLOOR-LOSS PRE-FLIGHT (harbor#110): refuse a snapshot that silently removes floor the target has ──
# Target-relative: only what the target holds AND this restore replaces, so a floorless box restores freely.
_LOST=''
if _moves bin; then
  for _s in guard-bash.sh guard-selfedit.sh guard-integrity.sh guard-egress.sh guard-lib.sh \
            annotate-web.sh context-resolve.sh floor-hook.sh floor-deny.sh floor-observe.sh \
            floor-normalize.awk pin-instructions.sh deploy-restore.sh; do
    [ -f "$TARGET/bin/$_s" ] && ! _archive_has "bin/$_s" && _LOST="$_LOST bin/$_s"
  done
fi
for _s in .helm-floor-teeth .helm-instructions.sha256 .sec0-baseline.sha256; do
  [ -f "$TARGET/$_s" ] && _moves "$_s" && ! _has_top "$_s" && _LOST="$_LOST $_s"
done
# Per pin, not per dir: one missing pin is the R6 lockout (B6 blocks every session).
if [ -d "$TARGET/.helm-pins" ] && _moves .helm-pins; then
  for _p in "$TARGET"/.helm-pins/*; do
    [ -f "$_p" ] && ! _archive_has ".helm-pins/${_p##*/}" && _LOST="$_LOST .helm-pins/${_p##*/}"
  done
fi
# Wiring, not just presence. jq is optional here: a recovery path must not need what may have broken.
if [ -f "$TARGET/settings.json" ] && _moves settings.json; then
  _TGT_S="$(cat "$TARGET/settings.json" 2>/dev/null || true)"
  _ARC_S=''
  _has_top settings.json && _ARC_S="$(tar -xzOf "$ARCHIVE" "${PFX}settings.json" 2>/dev/null || true)"
  if [ -n "$_TGT_S" ] && [ -z "$_ARC_S" ]; then
    _LOST="$_LOST settings.json(absent-or-unreadable-in-snapshot)"
  elif command -v jq >/dev/null 2>&1; then
    # Same predicate as guard-integrity.sh: event, matcher AND command.
    _wired_in() { # <settings-text> <event> <tool> <guard>
      printf '%s' "$1" | jq -e --arg ev "$2" --arg t "$3" --arg g "$4" '
        (.hooks[$ev] // [])
        | map(select(((.matcher // "") | split("|")) | index($t)))
        | map(.hooks[]?.command) | map(select(test("(^|/)" + $g + "( |$)")))
        | length > 0' >/dev/null 2>&1
    }
    _chk() { _wired_in "$_TGT_S" "$1" "$2" "$3" || return 0; _wired_in "$_ARC_S" "$1" "$2" "$3" || _LOST="$_LOST wiring:$3($1/$2)"; }
    _chk PreToolUse  Bash      guard-bash.sh
    _chk PreToolUse  Bash      guard-egress.sh
    _chk PreToolUse  Write     guard-egress.sh
    _chk PreToolUse  Edit      guard-egress.sh
    _chk PreToolUse  Write     guard-selfedit.sh
    _chk PreToolUse  Edit      guard-selfedit.sh
    _chk PreToolUse  WebFetch  guard-egress.sh
    _chk PreToolUse  Task      guard-egress.sh
    _chk PostToolUse WebFetch  annotate-web.sh
  else
    for _s in guard-bash.sh guard-selfedit.sh guard-egress.sh guard-integrity.sh \
              floor-hook.sh annotate-web.sh context-resolve.sh; do
      case "$_TGT_S" in *"$_s"*) ;; *) continue ;; esac
      case "$_ARC_S" in *"$_s"*) ;; *) _LOST="$_LOST wiring:$_s" ;; esac
    done
  fi
fi

# ── THE PLAN: printed by the dry run and by --apply alike ──
_list() { printf '%s' "$1" | tr '\n' ' ' | sed 's/ *$//'; }
_snapname="${SNAP##*/}"
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $TARGET"; else log_head "plan for $TARGET (dry run: nothing is written)"; fi
log_note "snapshot: $ARCHIVE"
case "$_snapname" in deploy-*) log_note "taken: $(printf '%s' "$_snapname" | sed -E 's/^deploy-([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}).*/\1-\2-\3 \4:\5:\6/')" ;; esac
log_note "move aside to $TARGET/backups/restore/<TS>/: $(_list "$MOVE")"
log_note "put back from the snapshot: $(_list "$BACK")"
[ -z "$GONE" ] || log_note "not in the snapshot, so moved aside and not put back:$GONE"
log_note "never touched: MEMORY, backups, .helm-snapshots, and every entry the snapshot does not cover${_skipped:+ (the snapshot names:$_skipped)}"
# ~/.local/bin (harbor#770): only for --live, only the dir the record names, only the links it holds.
LB_ACT=''; LB_DIR=''
_lb_plan() {
  _lbd="$(sed -n 's/^# dir: //p' "$LBREC" | head -1)"
  _lbw="$(_il_phys "${HARBOR_SCOPE_LOCAL_BIN:-${HARBOR_LOCAL_BIN:-$HOME/.local/bin}}")"
  if [ -z "$_lbd" ] || [ "$_lbd" != "$_lbw" ]; then
    log_skip "~/.local/bin: the record names ${_lbd:-no dir}, and this box's is $_lbw, so no link is put back"; return 0
  fi
  LB_DIR="$_lbw"; _lbok=0
  while IFS='	' read -r _ln _lk _lv; do
    case "$_ln" in ''|'#'*) continue ;; esac
    _lp="$LB_DIR/$_ln"
    case "$_lk" in
      link)
        if [ -L "$_lp" ] && [ "$(readlink "$_lp")" = "$_lv" ]; then _lbok=$((_lbok + 1))
        elif [ -L "$_lp" ]; then LB_ACT="$LB_ACT$_ln	$_lv$_NL"; log_note "~/.local/bin/$_ln: put back -> $_lv (the link there now, -> $(readlink "$_lp"), is moved aside)"
        elif [ -e "$_lp" ]; then
          log_warn "~/.local/bin/$_ln: the snapshot had a link -> $_lv, and a file is there now; it is not touched"
          log_fix "mv '$_lp' '$_lp.not-a-link' && $(il_cmd --apply)"
        else LB_ACT="$LB_ACT$_ln	$_lv$_NL"; log_note "~/.local/bin/$_ln: put back -> $_lv (absent now)"; fi ;;
      copy|file)
        if [ -f "$_lp" ] && [ ! -L "$_lp" ] && [ "$(il_blob "$_lp")" = "$_lv" ]; then _lbok=$((_lbok + 1))
        else log_note "~/.local/bin/$_ln: a $_lk in the snapshot (blob $_lv) is not put back: a restore puts back links only"; fi ;;
    esac
  done <"$LBREC"
  _lbx=''
  for _le in "$LB_DIR"/* "$LB_DIR"/.[!.]*; do
    [ -e "$_le" ] || [ -L "$_le" ] || continue
    awk -F'\t' -v n="${_le##*/}" '$1 == n { f = 1 } END { exit !f }' "$LBREC" || _lbx="$_lbx ${_le##*/}"
  done
  log_note "~/.local/bin: $_lbok entr(ies) already as recorded${_lbx:+; not in the record, so left as they are:$_lbx}"
}
if [ "$IL_LIVE" -eq 1 ] && [ -n "$LBREC" ]; then _lb_plan
elif [ "$IL_LIVE" -eq 1 ] && [ -f "$SNAP/local-bin.txt" ]; then
  log_note "not covered: ~/.local/bin; its listing when the snapshot was taken is $SNAP/local-bin.txt"
fi

[ -z "$_LOST" ] || il_loss "this snapshot does not hold floor surfaces the target has, so restoring it removes them:$_LOST" \
  "$(il_cmd --apply --accept-loss)"
il_stop
if [ "$IL_APPLY" -eq 0 ]; then
  [ "$IL_REFUSED" -eq 1 ] || il_next "$(il_cmd --apply)"
  log_end; exit $?
fi

# ── APPLY: move aside (rolled back if any move fails), then unpack exactly the entries put back ──
ASIDE="$IL_BK"  # backups/restore/<TS>/, beside this run's log: one backup scheme (install standard)
[ -n "$ASIDE" ] || _die "no dir to move the current entries into: $TARGET/backups/restore could not be made" \
  "the log-lib line above, on stderr"
_done=''
while IFS= read -r _e; do
  [ -n "$_e" ] || continue
  if mv "$TARGET/$_e" "$ASIDE/$_e"; then _done="$_done$_e$_NL"; continue; fi
  log_fail "could not move $_e aside into $ASIDE; putting back what was moved, nothing restored"
  log_nofix "the mv error above"
  while IFS= read -r _b; do
    [ -n "$_b" ] || continue
    mv "$ASIDE/$_b" "$TARGET/$_b" || log_warn "still aside, put it back by hand: $ASIDE/$_b"
  done <<EOF2
$_done
EOF2
  log_end || :
  exit 1
done <<EOF
$MOVE
EOF
set --
while IFS= read -r _e; do [ -n "$_e" ] && set -- "$@" "$PFX$_e"; done <<EOF
$BACK
EOF
if [ $# -gt 0 ] && ! tar -xzf "$ARCHIVE" -C "$TARGET" "$@"; then
  log_fail "unpacking $ARCHIVE failed: $TARGET is part-restored, and what was there is in $ASIDE"
  log_fix "$(il_cmd --apply)"
  log_end || :
  exit 1
fi
log_ok "restored $TARGET from $ARCHIVE"
log_note "what was there before: $ASIDE"
# The recorded links, each backed up as a link first; a failure is named and the rest still go back.
while IFS='	' read -r _ln _lv; do
  [ -n "$_ln" ] || continue
  _lp="$LB_DIR/$_ln"
  if { [ ! -L "$_lp" ] || { mkdir -p "$ASIDE/local-bin" && mv "$_lp" "$ASIDE/local-bin/$_ln"; }; } \
     && mkdir -p "$LB_DIR" && ln -s "$_lv" "$_lp"; then log_ok "~/.local/bin/$_ln -> $_lv, as the snapshot had it"
  else log_fail "could not put ~/.local/bin/$_ln back -> $_lv"; log_fix "ln -sfn '$_lv' '$_lp'"; fi
done <<EOF
$LB_ACT
EOF

# B6 as the next SessionStart will see it, from the restored guard (harbor#765).
_g="$TARGET/bin/guard-integrity.sh"
_v=''; _vk=note
if [ ! -f "$_g" ]; then _v='not installed (no bin/guard-integrity.sh)'; _vk=skip
else
  _o="$(env -u HARBOR_ADMISSION_DISABLE -u HARBOR_ADMISSION_SHADOW -u HELM_DISABLE_FLOOR -u HELM_FLOOR_SHADOW CLAUDE_CONFIG_DIR="$TARGET" sh "$_g" </dev/null 2>/dev/null || true)"
  if [ -z "$_o" ]; then _v='clean'; _vk=ok
  elif command -v jq >/dev/null 2>&1; then
    if printf '%s' "$_o" | jq -e '.continue == false' >/dev/null 2>&1; then
      _v="BLOCKED: $(printf '%s' "$_o" | jq -r '.stopReason // "no reason given"' 2>/dev/null | cut -c1-400)"; _vk=warn
    else
      _v="advisory: $(printf '%s' "$_o" | jq -r '.systemMessage // .hookSpecificOutput.additionalContext // "?"' 2>/dev/null | cut -c1-400)"
    fi
  else
    case "$_o" in *'"continue":false'*|*'"continue": false'*) _v="BLOCKED (no jq): $(printf '%s' "$_o" | cut -c1-400)"; _vk=warn ;;
                  *) _v="advisory (no jq): $(printf '%s' "$_o" | cut -c1-400)" ;; esac
  fi
fi
case "$_vk" in
  ok)   log_ok "the next session's B6 verdict: $_v" ;;
  skip) log_skip "the next session's B6 verdict: $_v" ;;
  warn) log_warn "the next session's B6 verdict: $_v"; log_nofix "the B6 reason above, which names its own recovery" ;;
  *)    log_note "the next session's B6 verdict: $_v" ;;
esac
log_end; exit $?
