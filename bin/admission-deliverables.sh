#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# guard-deliverables (harbor#402) — PreToolUse(Write|Edit|MultiEdit|Bash) FILING gate.
# RULE: a NEW document written for a human to read (.html .md .pdf .docx .pptx .csv .rtf .txt) belongs in ~/Deliverables/<YYYY-MM-DD>-<slug>/<file>,
# never loose in $HOME, ~/Desktop, ~/Documents or ~/Downloads.
# POSTURE: deny and NARROW. ALL must hold: (1) the extension is a document class (blocking a dropped screenshot is a §2.11 defect); (2) the
# target is directly in $HOME or under Desktop/Documents/Downloads; (3) the file does not already exist (editing the operator's own filing
# would get the guard switched off). A path inside a git repo is project content and exempt.
# NOT a security boundary: a filing convention with teeth; runtime-assembled paths and interpreters writing through their own API get past it.
# STANDALONE, not wrapped in admission-hook.sh nor in the floor MINIMUM (like guard-cloud and guard-destroy): the wrapper fails CLOSED, which
# is wrong for a tidiness rule that must never stop a session from writing code.
# Removed notes: docs/explanation/code-cases/bin-admission-deliverables.md
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin
TOOL="$(floor_field '.tool_name')"
# shellcheck disable=SC2034 # FLOOR_TOOL: read by library-admission.sh
FLOOR_TOOL="$TOOL"

DOC_EXT='html|htm|md|markdown|pdf|doc|docx|ppt|pptx|csv|rtf|txt'

# HOME is resolved physically AND collapsed lexically, and both spellings are roots. floor_norm_path resolves physically only when the
# target's parent exists, else keeps the unresolved prefix, so a home behind a symlink (macOS /var -> /private/var) matched one root for an
# existing dir and the other for a new one (measured: a deep new path ALLOWED while a file in an existing dir was denied).
HOMEP="$HOME"
if _rh="$(CDPATH= cd -P -- "$HOME" 2>/dev/null && pwd -P)"; then HOMEP="$_rh"; fi
# The raw spelling is collapsed (floor_collapse_dots): macOS hands out `//` in $HOME/TMPDIR, which would not match the collapsed target.
HOMER="$(floor_collapse_dots "$HOME")"
HOMES="$HOMEP"
[ "$HOMEP" = "$HOMER" ] || HOMES="$HOMEP
$HOMER"
ROOT="$HOMEP/Deliverables"

# ── THE CLASSIFIER — ONE definition, both arms ───────────────────────────────
# One definition for both arms: two spellings of one rule drift (docs/explanation/modularity.md). Returns 0 iff <path> is a NEW loose
# document and sets LOOSE_KIND; fails OPEN on anything it cannot resolve.
LOOSE_KIND=""
LOOSE_ABS=""
is_loose_doc() { # <raw path>
  _raw="$1"
  [ -n "$_raw" ] || return 1
  # An unresolved glob or substitution is not a path yet (it would deny a READ such as listing a glob).
  case "$_raw" in *'*'*|*'?'*|*'$'*|*'`'*|*'@SUB@'*) return 1 ;; esac
  _abs="$(floor_norm_path "$_raw")"
  _base="${_abs##*/}"
  case "_$_base" in _.*) return 1 ;; esac

  case "$_base" in *.*) ;; *) return 1 ;; esac
  _ext="$(printf '%s' "${_base##*.}" | tr '[:upper:]' '[:lower:]')"
  case "|$DOC_EXT|" in *"|$_ext|"*) ;; *) return 1 ;; esac

  _dir="${_abs%/*}"
  [ -n "$_dir" ] || _dir="/"
  _kind=""
  _oif="$IFS"; IFS='
'
  for _h in $HOMES; do
    IFS="$_oif"
    if [ "$_dir" = "$_h" ]; then _kind="home-loose"; fi
    for _l in "$_h/Desktop" "$_h/Documents" "$_h/Downloads"; do
      case "$_dir" in "$_l"|"$_l"/*) [ -n "$_kind" ] || _kind="dropzone" ;; esac
    done
    # The deliverables ROOT itself: a bare file there is the same scatter one level in. MANIFEST.md and README.md live at the root by design.
    if [ -z "$_kind" ] && [ "$_dir" = "$_h/Deliverables" ]; then
      case "$_base" in MANIFEST.md|README.md) ;; *) _kind="root-bare" ;; esac
    fi
    IFS='
'
  done
  IFS="$_oif"
  [ -n "$_kind" ] || return 1

  if [ -e "$_abs" ]; then return 1; fi

  _w="$_dir"
  while [ -n "$_w" ] && [ "$_w" != "/" ]; do
    if [ -e "$_w/.git" ]; then return 1; fi
    case "$_w" in "$HOMEP"|"$HOMER") break ;; esac
    _w="${_w%/*}"
  done

  LOOSE_KIND="$_kind"
  LOOSE_ABS="$_abs"
  return 0
}

suggest() { # <abs>
  _b="${1##*/}"
  _s="$(printf '%s' "${_b%.*}" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' \
              -e 's/-\{0,1\}[0-9]\{4\}-[0-9]\{2\}\(-[0-9]\{2\}\)\{0,1\}$//')"
  [ -n "$_s" ] || _s="deliverable"
  printf '%s/%s-%s/%s' "$ROOT" "$(date +%Y-%m-%d)" "$_s" "$_b"
}

deny() { # <rule> <shape> <what>
  # The rule's row decides (harbor#1030); shadow (harbor#482) and warn are recorded, not refused — floor_block's contract, for a
  # JSON-verdict guard. No decision function beside the guard: a shadow session shadows, otherwise the rule denies.
  if floor_decide deliverables "$1"; then _dv="$FLOOR_VERDICT"; elif [ "${HARBOR_ADMISSION_SHADOW:-0}" = 1 ]; then _dv=shadow; else _dv=block; fi
  case "$_dv" in
    shadow|warn)
      { floor_log_decision deliverables "$( [ "$_dv" = warn ] && echo advise || echo shadow )" "$1.$2" 2>/dev/null || :; } 2>/dev/null || :
      exit 0 ;;
  esac
  _msg="$3 belongs in a deliverables folder, not loose in $(printf '%s' "${LOOSE_ABS%/*}" | sed "s#^$HOMEP#~#"). Write it to ${WANT} instead — one dated folder per deliverable, so its siblings (source, charts, screenshots) have somewhere to live. Then open it and hand over the file:// link. If this file genuinely belongs where it is, say so: the operator can put it there themselves from their own terminal or with a \`!\` command, neither of which is a tool call."
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$_msg" | "$FLOOR_JQ" -Rs .)"
  { floor_log_decision deliverables deny "$1.$2" 2>/dev/null || :; } 2>/dev/null || :
  exit 0
}

case "$TOOL" in
  Write|Edit|MultiEdit)
    P="$(floor_field '.tool_input.file_path')"
    [ -n "$P" ] || exit 0
    # The digest subject is the RESOLVED path: ./x, //x and bin/../x are one target for recurrence counts.
    FLOOR_OBS_SUBJECT="$(floor_norm_path "$P")"
    if is_loose_doc "$P"; then
      WANT="$(suggest "$LOOSE_ABS")"
      deny "$LOOSE_KIND" path "$(printf '%s' "$LOOSE_ABS" | sed "s#^$HOMEP#~#")"
    fi
    ;;
  Bash|Monitor)
    CMD="$(floor_field '.tool_input.command')"
    [ -n "$CMD" ] || exit 0
    # shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
    FLOOR_OBS_SUBJECT="$CMD"
    # No floor_heredoc_inert_only veto, deliberately: it exits on a cat/tee opener, i.e. a heredoc redirected into a document, the commonest way
    # to write one, so this arm would be blind to its main case. harbor#716: document bodies are unwrapped BEFORE floor_bash_targets (its
    # home-expanded variant still carried the body); the opener line is still judged and a body fed to a shell is kept. harbor#782:
    # floor_hd_unwrap_doc_bodies also drops bodies behind a compound opener or a git commit -m command substitution.
    _BCMD="$CMD"
    case "$CMD" in *'<<'*) _BCMD="$(floor_hd_unwrap_doc_bodies --writers "$CMD")" ;; esac
    TXT="$(floor_bash_targets "$_BCMD" || true)"
    [ -n "$TXT" ] || exit 0
    # WRITE POSITION, not mere mention (a cat or open of a document is a read). Judged: a redirection target; the operand of a verb that
    # writes its argument (tee, touch, install...); the LAST operand of a copy/move/converter, i.e. the destination, trailing redirects allowed
    # (harbor#714, #785).
    TOK='[~/$][^[:space:];|&()<>"'"'"']*\.[A-Za-z0-9]{1,9}'
    _RD='([[:space:]]+[0-9]{0,1}[<>]{1,2}&{0,1}[[:space:]]*[^[:space:];&|<>]+)*'
    LASTV='cp|mv|install|rsync|ln|wkhtmltopdf|weasyprint|ps2pdf[0-9]*|dvipdf|pdftotext|pdftohtml|pdfunite|qpdf|magick|convert|ebook-convert'
    # harbor#793: a verb may be spelled with its path (/bin/cp, ~/.local/bin/pandoc); the prefix ends in `/`.
    _VP='(^|[[:space:]])([^[:space:];&|<>]*/)?'
    CANDS="$(
      { printf '%s\n' "$TXT" | "$FLOOR_GREP" -oE -- '(^|[[:space:]])[0-9]{0,1}>>{0,1}[[:space:]]*'"$TOK" || true
        printf '%s\n' "$TXT" | "$FLOOR_GREP" -oE -- "$_VP"'(tee|touch|install|pandoc)([[:space:]]{1,}-[^[:space:]]{1,})*[[:space:]]{1,}'"$TOK" || true
        printf '%s\n' "$TXT" | "$FLOOR_GREP" -oE -- '(^|[[:space:]])(-o|--output|--output-file)[=[:space:]][[:space:]]*'"$TOK" || true
        printf '%s\n' "$TXT" | "$FLOOR_GREP" -oE -- "$_VP"'('"$LASTV"')[[:space:]][^;&|]{1,}[[:space:]]'"$TOK$_RD"'[[:space:]]*($|[;&|])' \
          | sed -E 's/'"$_RD"'[[:space:]]*($|[;&|])$//' || true
      } | sed -e 's/[[:space:]]*[;&|]*$//' -e 's/.*[[:space:]]//' -e 's/^[0-9]*>>*//' -e 's/^[^~/$]*=//' \
        | sort -u || true
    )"
    [ -n "$CANDS" ] || exit 0
    _oldifs="$IFS"; IFS='
'
    for _c in $CANDS; do
      IFS="$_oldifs"
      if is_loose_doc "$_c"; then
        WANT="$(suggest "$LOOSE_ABS")"
        deny "$LOOSE_KIND" argv "$(printf '%s' "$LOOSE_ABS" | sed "s#^$HOMEP#~#")"
      fi
      IFS='
'
    done
    IFS="$_oldifs"
    ;;
  *) exit 0 ;;
esac

{ floor_log_decision deliverables allow deliverables-clean.meta 2>/dev/null || :; } 2>/dev/null || :
exit 0
