#!/usr/bin/env sh
# deploy-install-lib.sh (harbor#765, harbor#771) — the install standard's shared half: argument parsing, target
# resolution, backups, atomic JSON writes and the dry-run exit rule. Sourced AFTER library-log.sh by every
# installer and box tool. Never run; it sets no shell option, and every function is safe under set -eu.
#
#   il_opt() { … }               optional, defined before il_parse: the tool's own arguments. Called with
#                                "$1" "${2-}"; sets IL_TAKE to 1 (one word), 2 (a flag and its value; check
#                                the value with il_value), -1 (a mode word il_cmd must not replay) or 0.
#   il_parse "$@"                [--apply] (--live | --dir PATH) [--accept-loss] [-h|--help], any order.
#                                Unknown → usage on stderr, exit 2. -h/--help prints the header, exit 0.
#   il_target                    IL_TARGET, the physical target. --dir onto the live dir is refused (exit 1);
#                                a set $IL_ENV that differs from the target exits 2. An apply run opens its log
#                                here, so a refused preflight is logged too.
#   il_spell                     --live, or --dir '<target>': the one target spelling every hint uses
#   il_cmd [--apply] [--accept-loss]   this script's own command line, respelled so its gate accepts it
#   il_run <cmd> [args…]         run a child tool against this run's target: args, then --live or --dir <t>
#   il_backup <path>             copy a file, dir or link into <state>/backups/<tool>/<TS>/, beside the log
#   il_write_json <json> <dest>  a temp file beside dest, jq-validated, then mv; never a truncate in place
#   il_refuse <what> <fix>       a reason --apply refuses: FAIL + fix in BOTH modes, so a dry run exits 1
#   il_session <fix>             inside a Claude session: FAIL on --apply, a note on a dry run (the exception)
#   il_loss <what> <fix>         refused without --accept-loss; with it, a WARN naming exactly what is lost
#   il_stop                      on --apply, end the run here (exit 1) if anything was refused
#   il_next [--deploy-does] <cmd>   a next step; under deploy (HARBOR_DEPLOY_ACTIVE=1) one deploy performs is skipped
#   il_apply_cmd <component> [<implied word>…]   this run's --apply: on the live box, deploy.sh beside this
#                                script with --only <component> (§4), unless the run holds a word deploy lacks;
#                                an implied word (skills-install's --all) is one --only <component> already means
#   il_apply_next <component> [<implied word>…]  that command as a dry run's next step
#   il_usage_error <msg>         "<tool>: <msg>" and the usage on stderr, exit 2
#   il_first_run_cmd [<checkout>]   the first-run step, spelled for its gate: `sh <checkout>/bin/harbor scope install`,
#                                which seeds <config dir>/settings.json when absent (harbor#457). The checkout is
#                                the argument, else the one this script runs from (a bin/harbor beside it), else
#                                HARBOR_SCOPE_REPO (scope-roots.sh beside this script), else the conventional path
#   il_installed <config dir>    0 when a deploy has installed here (bin/ or .harbor-manifest): a missing settings.json
#                                is then a file LOST after the first run, not a first run not yet taken
#   il_lost_settings_fix <config dir> <deploy-restore.sh>   the fix for that: restore's dry run when a deploy snapshot exists,
#                                else the first-run command (which seeds an empty {})
#   il_merge_hook <settings-json> <event> <matcher> <cmd> [<onfail>]   wire one hook, additively; new json on stdout
#   il_onfailure                 `block` when the client takes a hook's onFailure key (Claude Code >= 2.1.295),
#                                else nothing; FLOOR_ONFAILURE=1|0 decides where `claude` is not on PATH
#
# The install manifest (install standard §3): <target>/.harbor-manifest, one row per installed file,
# `<git-blob> <mode> <relpath> <installer> <commit>`, newest row per path. B6 never reads it: a tamper
# gate must not read a record written by the thing it checks. Its readers only learn "these bytes are
# ones an install put there", so a forged row can make them allow an overwrite, never hide a regression.
#   il_source <repo-dir>         the commit column for this run's rows: that checkout's HEAD, or - with none
#   il_manifest <relpath>…       on --apply, queue a row for each file, or every file under each dir
#   il_manifest_drop <relpath>…  on --apply, queue the removal of those rows (a dir: every row under it)
#   il_manifest_write            on --apply, merge the queue into the manifest: backup, temp, mv
#   il_blob <file>               a file's git blob id (a symlink: its target's, as git stores a link)
#   il_mf_rows <cfg>             the rows as <relpath> TAB <blob> TAB <installer> TAB <commit>
#   il_mf_blob <cfg> <relpath>   the blob recorded for one path, or nothing
#   il_known <cfg> <relpath> <file> <repo> <repo-path>…   0 when the file's bytes are recorded for relpath
#                                in the manifest, or were committed at a repo path: not a box-only edit
#   il_renamed_retire <repo> <pins 0|1> <name>…   the old names of these just-installed bin/ names (renames.tsv):
#                                each old copy becomes the checkout's shim (or goes), its pin goes when <pins> is 1
#   il_renamed_rewire <json> <repo> <cfg> <name>…   settings JSON with every hook command word <cfg>/bin/<old> of these
#                                names (renames.tsv) rewritten to <cfg>/bin/<new>, a duplicate it makes dropped
#   il_renamed_old <repo> <name>   the old names renames.tsv records for one bin/ name, one per line
#
# Set before il_target when the default is wrong: IL_LIVE_DIR (the live target, default $HOME/.claude),
# IL_ENV (the variable that must agree with the target, default CLAUDE_CONFIG_DIR, empty for none),
# IL_STATE (where backups/ and the log go, default the target) and IL_LOG=0 (a reporter whose --apply
# only refreshes its own cache, on a schedule, keeps no run log: one per tick would be the leftover).

# The caller sources library-log.sh first; one that did not gets it from beside itself.
[ -n "${_LOG_LIB:-}" ] || . "$(dirname -- "$0")/library-log.sh"

IL_APPLY=0; IL_LIVE=0; IL_DIR=''; IL_DIR_SET=0; IL_ACCEPT_LOSS=0; IL_REFUSED=0; IL_TAKE=0
IL_ARGV=''; IL_TARGET=''; IL_BK=''; IL_COMMIT='-'; IL_MF_Q=''
IL_SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)/${0##*/}"

_il_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
_il_sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }  # always single-quoted
_il_q() { case "$1" in *[!A-Za-z0-9_./:=@%+,-]*|'') _il_sq "$1" ;; *) printf '%s' "$1" ;; esac; }

il_usage() { awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"; }
il_usage_error() { printf '%s: %s\n' "$LOG_TOOL" "$1" >&2; il_usage >&2; exit 2; }
il_value() { # <flag> <value> — a flag's value is a non-empty word that is not itself a flag
  case "${2-}" in
    '') il_usage_error "$1 needs a value" ;;
    -*) il_usage_error "$1 needs a value, not the flag $2" ;;
  esac
}

il_parse() {
  while [ $# -gt 0 ]; do
    IL_TAKE=0
    case "$1" in
      --apply) IL_APPLY=1; shift; continue ;;
      --live) IL_LIVE=1; shift; continue ;;
      --accept-loss) IL_ACCEPT_LOSS=1; shift; continue ;;
      --dir)
        il_value --dir "${2-}"
        [ "$IL_DIR_SET" -eq 0 ] || il_usage_error '--dir given twice'
        IL_DIR="$2"; IL_DIR_SET=1; shift 2; continue ;;
      -h|--help) il_usage; exit 0 ;;
    esac
    if command -v il_opt >/dev/null 2>&1; then il_opt "$1" "${2-}"; fi
    case "$IL_TAKE" in
      1) IL_ARGV="${IL_ARGV:+$IL_ARGV }$(_il_q "$1")"; shift ;;
      -1) shift ;;
      2) IL_ARGV="${IL_ARGV:+$IL_ARGV }$(_il_q "$1") $(_il_q "$2")"; shift 2 ;;
      *) case "$1" in
           -*) il_usage_error "unknown flag: $1" ;;
           *)  il_usage_error "unknown argument: $1 (there is no positional target; use --live or --dir PATH)" ;;
         esac ;;
    esac
  done
  [ "$IL_LIVE" -eq 0 ] || [ "$IL_DIR_SET" -eq 0 ] || il_usage_error '--live and --dir are two targets; give one'
  [ "$IL_LIVE" -eq 1 ] || [ "$IL_DIR_SET" -eq 1 ] || il_usage_error 'no target: give --live or --dir PATH'
}

il_spell() { if [ "$IL_LIVE" -eq 1 ]; then printf '%s' --live; else printf '%s %s' --dir "$(_il_sq "$IL_TARGET")"; fi; }

il_cmd() { # [--apply] [--accept-loss] — both are kept when this run already has them
  _il_a="$IL_APPLY"; _il_l="$IL_ACCEPT_LOSS"
  for _il_o in "$@"; do case "$_il_o" in --apply) _il_a=1 ;; --accept-loss) _il_l=1 ;; esac; done
  printf 'sh %s' "$(_il_q "$IL_SELF")"
  [ "$_il_a" -eq 0 ] || printf ' --apply'
  [ -z "$IL_ARGV" ] || printf ' %s' "$IL_ARGV"
  printf ' %s' "$(il_spell)"
  [ "$_il_l" -eq 0 ] || printf ' --accept-loss'
}

# The executed twin of il_spell: il_target already made the environment agree with the target.
il_run() { if [ "$IL_LIVE" -eq 1 ]; then "$@" --live; else "$@" --dir "$IL_TARGET"; fi; }

# Physical paths, never strings: a trailing slash or a symlink must not reach live without an explicit
# --live (P11-01). The env check: CLAUDE_CONFIG_DIR never picks the target (harbor#765).
il_target() {
  _il_live="$(_il_phys "${IL_LIVE_DIR:-${HOME:-}/.claude}")"
  if [ "$IL_LIVE" -eq 1 ]; then IL_TARGET="$_il_live"; else IL_TARGET="$(_il_phys "$IL_DIR")"; fi
  if [ "$IL_LIVE" -eq 0 ] && [ "$IL_TARGET" = "$_il_live" ]; then
    IL_LIVE=1
    log_fail "refusing the live dir without an explicit --live: --dir $IL_DIR is $_il_live"
    log_fix "$(il_cmd)"
    log_end; exit 1
  fi
  _il_env="${IL_ENV-CLAUDE_CONFIG_DIR}"
  if [ -n "$_il_env" ]; then
    eval "_il_ev=\${$_il_env:-}"
    if [ -n "$_il_ev" ] && [ "$(_il_phys "$_il_ev")" != "$IL_TARGET" ]; then
      printf '%s: %s is %s, not the target %s; it never picks the target, so unset it or make them agree\n' \
        "$LOG_TOOL" "$_il_env" "$_il_ev" "$IL_TARGET" >&2
      exit 2
    fi
  fi
  IL_STATE="$(_il_phys "${IL_STATE:-$IL_TARGET}")"
  if [ "$IL_APPLY" -eq 1 ] && [ "${IL_LOG:-1}" != 0 ] && [ -d "$IL_STATE" ]; then log_file "$IL_STATE"; fi
  IL_BK="$LOG_DIR"
}

# The pre-run bytes, once per run: a second backup of one path in the same run keeps the first.
il_backup() { # <path>
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ -z "$IL_BK" ]; then
    log_fail "no backup dir for $1: the run's log dir could not be made under ${IL_STATE:-the target}/backups"
    log_nofix "the log-lib line above, on stderr"
    return 1
  fi
  case "$1" in "$IL_STATE"/*) _il_rel="${1#"$IL_STATE"/}" ;; *) _il_rel="${1##*/}" ;; esac
  _il_dst="$IL_BK/$_il_rel"
  if [ -e "$_il_dst" ] || [ -L "$_il_dst" ]; then return 0; fi
  if mkdir -p "$(dirname -- "$_il_dst")" && cp -RPp "$1" "$_il_dst"; then return 0; fi
  log_fail "could not back up $1 to $_il_dst"
  log_nofix "the cp error above"
  return 1
}

# A bare `jq . >tmp && mv` cannot fail loudly under set -e, and `jq . >file` truncates it in place
# (red-team pass 8, sec0-harden). The temp copy keeps dest's mode; a symlinked dest is written through.
il_write_json() { # <json-text> <dest>
  _il_d="$2"
  if [ -L "$_il_d" ]; then
    _il_t="$(readlink "$_il_d" 2>/dev/null || true)"
    case "$_il_t" in /*) _il_d="$_il_t" ;; ?*) _il_d="$(dirname -- "$2")/$_il_t" ;; esac
  fi
  _il_tmp="$_il_d.tmp.$$"
  [ ! -f "$_il_d" ] || cp -p "$_il_d" "$_il_tmp" 2>/dev/null || :
  if ! printf '%s\n' "$1" | jq . > "$_il_tmp" 2>/dev/null || ! jq -e . "$_il_tmp" >/dev/null 2>&1; then
    rm -f "$_il_tmp"
    log_fail "refusing to write invalid JSON to $2 — it is unchanged"
    log_nofix "bin/deploy-install-lib.sh il_write_json; the JSON came from $LOG_TOOL"
    return 1
  fi
  if ! mv -f "$_il_tmp" "$_il_d"; then
    rm -f "$_il_tmp"
    log_fail "could not replace $2 — it is unchanged"
    log_nofix "the mv error above"
    return 1
  fi
}

# Install a script by rename, never by overwrite. sh reads a script as it runs, so `cp` over a guard
# a hook is executing makes it resume mid-line in the new bytes; on 2026-10-15 that ran an example
# command quoted in a comment. mv swaps the inode; the running shell keeps reading the old one.
il_install_exec() { # <src> <dest>
  if cp "$1" "$2.tmp.$$" && chmod +x "$2.tmp.$$" && mv -f "$2.tmp.$$" "$2"; then return 0; fi
  rm -f "$2.tmp.$$"
  log_fail "could not install $2 — it is unchanged"
  log_nofix "the cp/mv error above"
  return 1
}

il_refuse() { # <what> <fix>
  IL_REFUSED=1
  _il_w='--apply would refuse'; [ "$IL_APPLY" -eq 0 ] || _il_w='refused'
  log_fail "$_il_w: $1"
  log_fix "$2"
}

# The dry-run exit rule (install standard, Wave A): a dry run exits 1 whenever --apply would refuse,
# except when the only reason is a Claude session, which a dry run notes and exits 0 on.
il_session() { # <fix>
  [ -n "${CLAUDECODE:-}" ] || return 0
  if [ "$IL_APPLY" -eq 1 ]; then IL_REFUSED=1; log_fail "refused: this is a Claude session, and --apply runs only from a terminal"; log_fix "$1"
  else log_note "--apply would refuse here, inside a Claude session; from a terminal: $1"; fi
}

il_loss() { # <what is lost> <fix>
  if [ "$IL_ACCEPT_LOSS" -eq 1 ]; then log_warn "--accept-loss: $1"; else il_refuse "$1" "$2"; fi
}

il_stop() {
  { [ "$IL_APPLY" -eq 1 ] && [ "$IL_REFUSED" -eq 1 ]; } || return 0
  log_note 'nothing was written'
  log_end || :
  exit 1
}

il_next() { # [--deploy-does] <command>
  if [ "${1-}" = --deploy-does ]; then shift; [ "${HARBOR_DEPLOY_ACTIVE:-${HARBOR_DEPLOY:-0}}" = 1 ] && return 0; fi
  log_note "next: ${1-}"
}

# deploy is the only live entry (install standard §4): a live dry run's apply goes through it, with one
# snapshot and one verify. deploy takes the floor's opt-ins; a skill name or --from-branch it does not, so
# such a run keeps its own command. An installed copy has no deploy.sh beside it, and keeps its own too.
il_apply_cmd() { # <component> [<implied word>…]
  _iac_d="${IL_SELF%/*}/deploy.sh"; _iac_c="${1-}"; shift 2>/dev/null || :
  if [ "$IL_LIVE" -eq 1 ] && [ -n "$_iac_c" ] && [ -f "$_iac_d" ]; then
    _iac_ok=1; _iac_w=''
    set -f
    for _iac_a in $IL_ARGV; do
      case " --with-b6 --with-stop-gate " in *" $_iac_a "*) _iac_w="$_iac_w $_iac_a"; continue ;; esac
      case " $* " in *" $_iac_a "*) continue ;; esac
      _iac_ok=0
    done
    set +f
    if [ "$_iac_ok" -eq 1 ]; then
      _iac_l=''; [ "$IL_ACCEPT_LOSS" -eq 0 ] || _iac_l=' --accept-loss'
      printf 'sh %s --apply --only %s%s --live%s' "$(_il_sq "$_iac_d")" "$_iac_c" "$_iac_w" "$_iac_l"
      return 0
    fi
  fi
  il_cmd --apply
}
il_apply_next() { # <component> [<implied word>…]
  _ian="$(il_apply_cmd "$@")"
  # A step deploy itself performs is not printed under deploy (#285).
  case "$_ian" in *"/deploy.sh' --apply --only "*) il_next --deploy-does "$_ian" ;; *) il_next "$_ian" ;; esac
}

# The one spelling of the first-run fix, so no FAIL line says "start Claude Code once" and leaves the reader to guess
# the command (harbor#457). `scope install` is idempotent: on a box that has settings.json it only reports `kept`.
il_first_run_cmd() { # [<checkout>]
  _fr_r="${1-}"
  if [ -z "$_fr_r" ] && [ -f "${IL_SELF%/*}/harbor" ]; then  # run from a checkout, wherever it was cloned: its own verb exists
    printf 'sh %s scope install' "$(_il_sq "${IL_SELF%/*}/harbor")"; return 0
  fi
  if [ -z "$_fr_r" ]; then
    _fr_r="$(sh "${IL_SELF%/*}/scope-roots.sh" --get HARBOR_SCOPE_REPO 2>/dev/null || :)"
    [ -n "$_fr_r" ] || _fr_r="${HARBOR_SCOPE_REPO:-${HARBOR_REPO:-${PORT_ROOT:-$HOME/port}/harbor}}"  # spelled as contracts/roots.tsv has it (scope-roots.sh --check)
  fi
  printf 'sh %s scope install' "$(_il_sq "$_fr_r/bin/harbor")"
}
# A box with bin/ or a manifest has been deployed to. Without settings.json it did not skip the first-run step: the
# file went missing afterwards, and the right recovery is the snapshot that holds the operator's own settings, not an
# empty {} (harbor#457).
il_installed() { [ -d "$1/bin" ] || [ -f "$1/.harbor-manifest" ]; }
il_lost_settings_fix() { # <config dir> <deploy-restore.sh>
  if [ -n "$(find "$1/backups" -maxdepth 1 -name 'deploy-*' 2>/dev/null | head -n 1)" ]; then
    printf 'sh %s --live' "$(_il_sq "$2")"  # the dry run: which snapshot comes back and what moves aside
  else il_first_run_cmd; fi
}
# Additive and idempotent: a command already under that matcher is left alone, but gains <onfail> when given.
il_merge_hook() { # <settings-json> <event> <matcher> <cmd> [<onfail>]  → new json on stdout
  jq --arg ev "$2" --arg m "$3" --arg cmd "$4" --arg of "${5:-}" '
    ({type:"command", command:$cmd} + (if $of == "" then {} else {onFailure:$of} end)) as $h
    | .hooks //= {}
    | .hooks[$ev] //= []
    | (.hooks[$ev] | map(.matcher == $m) | index(true)) as $i
    | if $i == null
      then .hooks[$ev] += [{matcher:$m, hooks:[$h]}]
      else (.hooks[$ev][$i].hooks |= (
              if (map(.command) | index($cmd)) == null
              then . + [$h]
              elif $of == "" then .
              else map(if .command == $cmd then . + {onFailure:$of} else . end) end)) end
  ' "$1"
}
# A PreToolUse veto that times out or crashes lets the call through unless onFailure is set
# (code.claude.com/docs/en/hooks). An unknown version gets no field: an older client may reject the key.
il_onfailure() {
  case "${FLOOR_ONFAILURE:-}" in 1) echo block; return 0 ;; 0) return 0 ;; esac
  _ofv="$(claude --version 2>/dev/null | sed -n 's/^\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\).*/\1 \2 \3/p' | head -n 1)"
  [ -n "$_ofv" ] || return 0
  set -- $_ofv
  if [ "$1" -gt 2 ] || { [ "$1" -eq 2 ] && { [ "$2" -gt 1 ] || { [ "$2" -eq 1 ] && [ "$3" -ge 295 ]; }; }; }; then echo block; fi
  return 0
}

# ── THE INSTALL MANIFEST (install standard §3) ────────────────────────────────
# Rows are queued as `+<TAB><row>` or `-<TAB><relpath>` and merged once, at the end of an apply run.
_il_nl='
'
# WHERE AN INSTALLED NAME'S BYTES COME FROM (D-88, harbor#1272): bin/<name>, or the engine folder a hook engine moved to.
# Deployed flat either way, so payload lists keep the installed name. il_engine_path is the one spelling, for git readers too.
il_engine_path() { printf 'hooks/%s/%s' "${1%.*}" "$1"; }
il_src() { # <repo root> <installed name> -> the repo-relative path it is installed from
  if [ ! -f "$1/bin/$2" ] && [ -f "$1/$(il_engine_path "$2")" ]; then il_engine_path "$2"; else printf 'bin/%s' "$2"; fi
}
il_blob() { # <file>
  if [ -L "$1" ]; then printf '%s' "$(readlink "$1")" | git hash-object --no-filters --stdin 2>/dev/null
  else git hash-object --no-filters -- "$1" 2>/dev/null; fi
}
# A target inside the source's own checkout is an installed copy in a repo that is not its source (a
# config dir under a dotfiles repo): that repo's HEAD says nothing about these bytes.
il_source() { # <repo-dir>
  IL_COMMIT='-'
  _is_t="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 0
  case "$(_il_phys "${IL_TARGET:-/nonexistent}")/" in "$(_il_phys "$_is_t")"/*) return 0 ;; esac
  IL_COMMIT="$(git -C "$1" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null || :)"
  [ -n "$IL_COMMIT" ] || IL_COMMIT='-'
}
il_manifest() { # <relpath>…
  [ "$IL_APPLY" -eq 1 ] || return 0
  for _im in "$@"; do
    _im="${_im%/}"
    if [ -d "$IL_TARGET/$_im" ] && [ ! -L "$IL_TARGET/$_im" ]; then
      # Caches are not payload: skills-install's byte check excludes the same three.
      _im_l="$(cd "$IL_TARGET" && find "./$_im" -name __pycache__ -prune -o \( -type f -o -type l \) \
                 ! -name '*.pyc' ! -name .DS_Store -print 2>/dev/null | sed 's|^\./||' | LC_ALL=C sort)"
    elif [ -e "$IL_TARGET/$_im" ] || [ -L "$IL_TARGET/$_im" ]; then _im_l="$_im"
    else continue; fi
    [ -n "$_im_l" ] || continue
    # One git spawn per batch: skills-install --all records hundreds of files.
    _im_f=''; _im_x=''
    while IFS= read -r _im_r; do
      [ -n "$_im_r" ] || continue
      if [ -L "$IL_TARGET/$_im_r" ]; then
        IL_MF_Q="$IL_MF_Q+	$(il_blob "$IL_TARGET/$_im_r") 120000 $_im_r $LOG_TOOL $IL_COMMIT$_il_nl"; continue
      fi
      _im_f="$_im_f$_im_r$_il_nl"
      if [ -x "$IL_TARGET/$_im_r" ]; then _im_x="${_im_x}100755$_il_nl"; else _im_x="${_im_x}100644$_il_nl"; fi
    done <<IMEOF
$_im_l
IMEOF
    [ -n "$_im_f" ] || continue
    # Absolute paths: inside a work tree, --stdin-paths resolves a relative one from the top, not the cwd.
    _im_b="$(printf '%s' "$_im_f" | IL_T="$IL_TARGET" awk '{ print ENVIRON["IL_T"] "/" $0 }' \
               | git hash-object --no-filters --stdin-paths 2>/dev/null)" || _im_b=''
    if [ "$(printf '%s\n' "$_im_b" | grep -c .)" -ne "$(printf '%s' "$_im_f" | grep -c .)" ]; then
      log_warn "could not hash what was installed under $IL_TARGET/$_im, so it has no .harbor-manifest row"
      log_nofix "git hash-object on the files above; install-drift and skills-collide then read git history alone"
      continue
    fi
    IL_MF_Q="$IL_MF_Q$(printf '%s\n' "$_im_b" | IL_P="$_im_f" IL_X="$_im_x" IL_I="$LOG_TOOL" IL_C="$IL_COMMIT" awk '
      BEGIN { split(ENVIRON["IL_P"], P, "\n"); split(ENVIRON["IL_X"], X, "\n") }
      { printf "+\t%s %s %s %s %s\n", $1, X[NR], P[NR], ENVIRON["IL_I"], ENVIRON["IL_C"] }')$_il_nl"
  done
}
il_manifest_drop() { # <relpath>…
  [ "$IL_APPLY" -eq 1 ] || return 0
  for _id in "$@"; do IL_MF_Q="$IL_MF_Q-	${_id%/}$_il_nl"; done
}
# A row's relpath is everything between its second and its second-to-last field, so a space in a name
# cannot shift the columns.
_IL_MF_AWK='function rel(r) { sub(/^[^ ]+ [^ ]+ /, "", r); sub(/ [^ ]+ [^ ]+$/, "", r); return r }'
il_manifest_write() {
  { [ "$IL_APPLY" -eq 1 ] && [ -n "$IL_MF_Q" ] && [ -d "$IL_TARGET" ]; } || return 0
  _iw_m="$IL_TARGET/.harbor-manifest"; _iw_t="$_iw_m.tmp.$$"
  il_backup "$_iw_m" || return 1
  if { printf '# .harbor-manifest (install standard §3, bin/deploy-install-lib.sh): <git-blob> <mode> <relpath> <installer> <commit>\n'
       { [ ! -f "$_iw_m" ] || grep -v '^#' "$_iw_m" | sed 's/^/=	/'; printf '%s' "$IL_MF_Q"; } \
         | awk -F'\t' "$_IL_MF_AWK"'
             $1 == "-" { d = $2; n = 0; for (k in row) if (k == d || index(k, d "/") == 1) gone[++n] = k
                         for (i = 1; i <= n; i++) delete row[gone[i]]; next }
             ($1 == "=" || $1 == "+") && NF >= 2 { row[rel($2)] = $2 }
             END { for (k in row) printf "%s\t%s\n", k, row[k] }' \
         | LC_ALL=C sort | cut -f2-
     } >"$_iw_t" 2>/dev/null && mv -f "$_iw_t" "$_iw_m"; then
    log_note "recorded $(printf '%s' "$IL_MF_Q" | grep -c '^+') installed file(s) in $_iw_m"
    IL_MF_Q=''
    return 0
  fi
  rm -f "$_iw_t"
  log_fail "could not write $_iw_m — what this run installed has no manifest row"
  log_nofix "the error above; install-drift and skills-collide then read git history alone"
  return 1
}
il_mf_rows() { # <cfg>
  [ -f "$1/.harbor-manifest" ] || return 0
  awk "$_IL_MF_AWK"' /^#/ || NF < 5 { next } { printf "%s\t%s\t%s\t%s\n", rel($0), $1, $(NF-1), $NF }' "$1/.harbor-manifest"
}
il_mf_blob() { # <cfg> <relpath>
  il_mf_rows "$1" | awk -F'\t' -v p="$2" '$1 == p { b = $2 } END { if (b != "") print b }'
}
il_known() { # <cfg> <relpath> <file> <repo> <repo-path>…
  _ik_b="$(il_blob "$3")"
  [ -n "$_ik_b" ] || return 1
  [ "$(il_mf_blob "$1" "$2")" != "$_ik_b" ] || return 0
  _ik_r="$4"; shift 4
  [ $# -gt 0 ] && git -C "$_ik_r" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$_ik_r" log --format= --raw --no-abbrev -- "$@" 2>/dev/null \
    | awk -v h="$_ik_b" '$3 == h || $4 == h { f = 1 } END { exit !f }'
}

# THE OLD NAME OF A RENAMED FILE (harbor#949). A box installed before a rename keeps the old name's copy and,
# for a floor file, its B6 pin: B6 then checks a file no installer writes, install-drift reads it stale, and
# the deploy that ships the rename fails its own verify and restores itself. The installer of the new name
# leaves the old one as the checkout has it: the shim while renames.tsv keeps it, nothing once it is gone.
# The shim, not a removal: LaunchAgents and notes still name old paths until standard-rename's box half
# rewrites them. The checkout's link is copied as it is (cp -P); no link is made here (harbor#708).
# A pinned copy is floor-install's (<pins> 1) and is never touched by another installer. Bytes in no commit
# and not matching their pin are box-only work: kept with their pin, and named. Everything moved is backed up.
il_renamed_retire() { # <repo root> <own the pins: 0|1> <installed name>…
  _ir_r="$1"; _ir_own="$2"; shift 2
  [ -f "$_ir_r/standards/naming/renames.tsv" ] || return 0
  _ir_rows="$(printf '%s\n' "$@" | awk -F'\t' 'NR == FNR { w[$0] = 1; next }
      /^#/ || NF < 3 { next }
      $2 ~ /^bin\/[^\/]+$/ && $3 ~ /^bin\/[^\/]+$/ {
        o = substr($2, 5); n = substr($3, 5); if ((n in w) && o != n) print o " " n }' - "$_ir_r/standards/naming/renames.tsv")"
  _ir_done=''; _ir_kept=''
  while read -r _ir_o _ir_n; do
    [ -n "$_ir_o" ] && [ -f "$IL_TARGET/bin/$_ir_n" ] || continue
    _ir_c="$IL_TARGET/bin/$_ir_o"; _ir_p="$IL_TARGET/.helm-pins/$_ir_o.sha256"
    if [ -f "$_ir_p" ] && [ "$_ir_own" != 1 ]; then continue; fi
    _ir_file=0; [ -f "$_ir_c" ] && [ ! -L "$_ir_c" ] && _ir_file=1
    [ "$_ir_file" -eq 1 ] || [ -f "$_ir_p" ] || continue
    if [ "$_ir_file" -eq 1 ] && ! il_known "$IL_TARGET" "bin/$_ir_o" "$_ir_c" "$_ir_r" "bin/$_ir_o"; then
      _ir_h="$( { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } < "$_ir_c" | awk '{print $1}')"
      if [ ! -f "$_ir_p" ] || [ "$(cat "$_ir_p" 2>/dev/null)" != "$_ir_h" ]; then _ir_kept="$_ir_kept bin/$_ir_o"; continue; fi
    fi
    _ir_done="$_ir_done $_ir_o->$_ir_n"
    [ "$IL_APPLY" -eq 1 ] || continue
    il_backup "$_ir_p" || return 1
    if [ "$_ir_file" -eq 1 ]; then
      il_backup "$_ir_c" || return 1
      if [ -L "$_ir_r/bin/$_ir_o" ]; then
        cp -P "$_ir_r/bin/$_ir_o" "$_ir_c.tmp.$$" && mv -f "$_ir_c.tmp.$$" "$_ir_c" || {
          rm -f "$_ir_c.tmp.$$"; log_fail "could not replace bin/$_ir_o with its shim — it is unchanged"; log_nofix "the cp/mv error above"; return 1; }
        il_manifest "bin/$_ir_o"
      else
        rm -f "$_ir_c"; il_manifest_drop "bin/$_ir_o"
      fi
    fi
    rm -f "$_ir_p"
  done <<IREOF
$_ir_rows
IREOF
  if [ -n "$_ir_done" ]; then
    if [ "$IL_APPLY" -eq 1 ]; then log_ok "the old name of a renamed file is now the checkout's shim or gone, its B6 pin removed, both backed up in $IL_BK:$_ir_done"
    else log_note "the old name of a renamed file WOULD become the checkout's shim or go, with its B6 pin:$_ir_done"; fi
  fi
  if [ -n "$_ir_kept" ]; then
    log_warn "kept the old name of a renamed file:$_ir_kept — its bytes are in no commit and match no pin, so it is box-only work; B6 and install-drift go on naming it"
    log_fix "compare it with the file it was renamed to (standards/naming/renames.tsv), keep what you need, then delete it and its .helm-pins entry"
  fi
  return 0
}

# THE HOOK COMMANDS OF A RENAMED FILE (harbor#961 W6). A box wired before a rename runs its guards under the old
# names; the installer that ships the new ones merges its table additively, so both would be wired and every call
# would run each guard twice, the old through its shim. So before the merge, a hook command word that is exactly
# <cfg>/bin/<old> of a file this installer installs becomes <cfg>/bin/<new>, and an entry that is now the same
# command as one before it in its matcher group is dropped (the first keeps its onFailure). A command naming
# anything else, an operator's own hook among them, is untouched.
il_renamed_pairs() { # <repo root> <installed name>… -> old TAB new, one per renames.tsv bin/ row whose new name is listed
  _rp_r="$1"; shift
  [ -f "$_rp_r/standards/naming/renames.tsv" ] || return 0
  printf '%s\n' "$@" | awk -F'\t' 'NR == FNR { w[$0] = 1; next }
      /^#/ || NF < 3 { next }
      $2 ~ /^bin\/[^\/]+$/ && $3 ~ /^bin\/[^\/]+$/ {
        o = substr($2, 5); n = substr($3, 5); if ((n in w) && o != n) print o "\t" n }' - "$_rp_r/standards/naming/renames.tsv"
}
il_renamed_old() { il_renamed_pairs "$1" "$2" | cut -f1; }
il_renamed_rewire() { # <settings-json> <repo root> <cfg dir> <installed name>… -> new json on stdout
  _rw_j="$1"; _rw_r="$2"; _rw_d="$3"; shift 3
  _rw_m="$(il_renamed_pairs "$_rw_r" "$@" | jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {o: .[0], n: .[1]})')" || _rw_m='[]'
  jq --arg d "$_rw_d/bin/" --argjson m "${_rw_m:-[]}" '
    def rw: split(" ") | map(. as $t | ([$m[] | select($d + .o == $t) | $d + .n][0] // $t)) | join(" ");
    def dedupe: reduce .[] as $h ([]; if ($h | type) == "object" and ($h.command | type) == "string"
                                          and (map(select(type == "object") | .command) | index($h.command)) != null
                                       then . else . + [$h] end);
    if ($m | length) == 0 or (.hooks | type) != "object" then . else
      .hooks |= with_entries(.value |= (if type != "array" then . else map(
        if type == "object" and (.hooks | type) == "array"
        then .hooks |= (map(if type == "object" and (.command | type) == "string" then .command |= rw else . end) | dedupe)
        else . end) end))
    end' "$_rw_j"
}

# THE GIT VERBS REGISTER (harbor#1291). floor-deny adds the allow and ask rules contracts/git-verbs.md's rows imply
# and floor-uninstall takes the same rules out, so both read them here. A spelling that does not start
# `git <subcommand>`, or names an <argument> or a shell metacharacter, comes back BAD and is never a rule.
IL_GIT_VERBS="${IL_SELF%/*}/../contracts/git-verbs.md"
il_git_verbs() { # <allow|ask> -> "OK<TAB><spelling>" or "BAD<TAB><spelling>" per register row with that perm
  [ -f "$IL_GIT_VERBS" ] || return 0
  awk -F'|' -v want="$1" '/^\| `/ {
      s = $2; p = $4; gsub(/^[ \t`]+|[ \t`]+$/, "", s); gsub(/^[ \t]+|[ \t]+$/, "", p)
      if (p != want) next
      if (s !~ /^git [a-z][a-z-]*( |$)/ || s ~ /[<>`|;&$]/) { print "BAD\t" s; next }
      print "OK\t" s }' "$IL_GIT_VERBS"
}
