#!/usr/bin/env sh
[ "${HELM_DISABLE_FLOOR:-0}" = "1" ] && exit 0
# guard-deliverables (harbor#402) — PreToolUse(Write|Edit|MultiEdit|Bash) FILING gate.
#
# THE RULE IT ENFORCES. A NEW document written for a human to read — .html, .md,
# .pdf, .docx, .pptx, .csv, .rtf, .txt — belongs in
#
#     ~/Deliverables/<YYYY-MM-DD>-<slug>/<file>
#
# and never loose in $HOME, ~/Desktop, ~/Documents or ~/Downloads.
#
# WHY IT EXISTS. Measured 2026-09-02 on this box: 14 loose .html deliverables
# sitting in $HOME and 4 in ~/Documents, written by sessions between 2026-08-25
# and 2026-09-01 — every one a report or a draft, opened once and never filed.
# The convention existed only as habit: the auto-memory
# drafts-and-deliverables-must-be-clickable says WRITE the file and open it, and
# says nothing about WHERE, so each session picked a directory and the estate
# scattered. CONSTITUTION, "Fix the system, not your notes": a rule with no
# mechanism is a wish, and a preference that belongs in a guard is a missed
# system patch when it goes into an assistant's scratch memory instead. This is
# the mechanism; the memory and the constitution line are the statement of it.
#
# POSTURE: deny, and NARROW. THREE conditions must ALL hold before it fires:
#
#   1. the extension is a document class (an image is not — a screenshot dropped
#      on the Desktop is ordinary macOS work and blocking it is a §2.11 defect
#      factory);
#   2. the target sits DIRECTLY in $HOME, or anywhere under ~/Desktop,
#      ~/Documents or ~/Downloads — the four places a session picks when it has
#      not been told where to write;
#   3. the file DOES NOT ALREADY EXIST.
#
# (3) is what keeps this off ordinary work, and it is the condition doing the
# real §2.11 labour: rewriting or editing a document the operator ALREADY keeps
# in ~/Documents is their filing, not a session's scatter, and a guard that
# blocks it gets switched off. A path inside a git repo parked under one of
# those directories is exempt for the same reason — that is project content,
# and the repo is already the folder of its own.
#
# WHAT IT DOES NOT CLAIM. This is a filing convention with teeth, NOT a security
# boundary, and the residuals are the ordinary ones: a runtime-assembled path, a
# python/node process writing through its own API, an interpreter the flat
# scanner cannot follow. It raises the cost of scattering to "notice the deny and
# use the right path"; it does not make scattering impossible, and the migration
# manifest is what makes a slip visible after the fact.
#
# STANDALONE, NOT WRAPPED IN floor-hook.sh, and deliberately NOT in
# guard-integrity's floor MINIMUM — exactly like guard-cloud and guard-destroy.
# floor-hook.sh's contract is fail-CLOSED: any guard it wraps that cannot reach a
# verdict DENIES THE CALL. Fail-closed is correct for the security floor and
# wrong for a filing convention: a broken tidiness rule must never be able to
# stop a session from writing code. So a failure here is a failure to file, not
# an outage, and the wiring records that choice rather than leaving it to be
# inferred.
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/guard-lib.sh"

floor_read_stdin
TOOL="$(floor_field '.tool_name')"
FLOOR_TOOL="$TOOL"

# The document classes. Extensions only — the whole rule is about where a file
# LANDS, and the harness gives a path long before it gives content.
DOC_EXT='html|htm|md|markdown|pdf|doc|docx|ppt|pptx|csv|rtf|txt'

# HOME RESOLVED PHYSICALLY, ONCE. floor_norm_path returns a physical path, and
# comparing a physical target against an unresolved root silently misses
# everything the moment a root sits under a symlink — the failure guard-selfedit
# records for $CFG/$LIVE, and macOS /var → /private/var is the everyday case.
#
# BOTH SPELLINGS ARE ROOTS, and the suite is what proved that necessary.
# floor_norm_path resolves physically only when the target's PARENT EXISTS; for a
# path whose parent does not exist yet — which is every "write a report into a
# folder that is not there" — it falls back to a lexical collapse and keeps the
# UNRESOLVED prefix. So a home behind a symlink matches the physical root for an
# existing directory and the raw one for a new directory, and a guard holding
# only one of them is blind to exactly half its own subject. Measured here: with
# HOME under macOS's /var → /private/var, `~/Documents/a/b/deep.html` classified
# ALLOW while `~/Documents/plan.pdf` denied.
HOMEP="$HOME"
if _rh="$(CDPATH= cd -P -- "$HOME" 2>/dev/null && pwd -P)"; then HOMEP="$_rh"; fi
# The raw spelling is COLLAPSED, not taken verbatim: floor_norm_path's lexical
# fallback runs floor_collapse_dots over its result, so a $HOME carrying `//` or
# `/./` — which macOS hands out routinely, TMPDIR ends in a slash — would be
# compared against a target that no longer spells it that way. Same defect as
# comparing an unresolved root, one layer of normalisation to the left.
HOMER="$(floor_collapse_dots "$HOME")"
HOMES="$HOMEP"
[ "$HOMEP" = "$HOMER" ] || HOMES="$HOMEP
$HOMER"
ROOT="$HOMEP/Deliverables"

# ── THE CLASSIFIER — ONE definition, both arms ───────────────────────────────
# The Write arm and the Bash arm ask the same question about a path, so they ask
# it in the same function. Two spellings of one rule is the drift
# DOCTRINE/modularity.md is about, and here it would be invisible: the arms would
# answer differently only for the paths nobody tested.
#
# Returns 0 iff <path> is a NEW loose document, and sets LOOSE_KIND to the rule
# that fired. Fails OPEN on anything it cannot resolve.
LOOSE_KIND=""
LOOSE_ABS=""
is_loose_doc() { # <raw path>
  _raw="$1"
  [ -n "$_raw" ] || return 1
  # An unresolved glob or substitution is not a path yet. Judging one would deny
  # `ls ~/*.html` — a READ — on the strength of a filename that does not exist.
  case "$_raw" in *'*'*|*'?'*|*'$'*|*'`'*|*'@SUB@'*) return 1 ;; esac
  _abs="$(floor_norm_path "$_raw")"
  _base="${_abs##*/}"
  # A dotfile is configuration, never a deliverable (~/.zshrc, ~/.gitconfig).
  case "_$_base" in _.*) return 1 ;; esac

  # 1 · document class. Case-folded: APFS is case-INSENSITIVE, so `REPORT.HTML`
  # reaches the same inode a case-sensitive match would call untouched.
  case "$_base" in *.*) ;; *) return 1 ;; esac
  _ext="$(printf '%s' "${_base##*.}" | tr '[:upper:]' '[:lower:]')"
  case "|$DOC_EXT|" in *"|$_ext|"*) ;; *) return 1 ;; esac

  # 2 · location
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
    # The deliverables ROOT itself. A bare file here is the same scatter one
    # level in — the shape the operator chose is a dated folder PER deliverable,
    # so its siblings (the .md source, a chart, a screenshot) have somewhere to
    # live.
    # THE ROOT'S OWN INDEX IS NOT SCATTER. MANIFEST.md — the old→new record the
    # migration writes — and a README live at the root by design, and a rule that
    # forbids its own record is a rule that cannot be written down.
    if [ -z "$_kind" ] && [ "$_dir" = "$_h/Deliverables" ]; then
      case "$_base" in MANIFEST.md|README.md) ;; *) _kind="root-bare" ;; esac
    fi
    IFS='
'
  done
  IFS="$_oif"
  [ -n "$_kind" ] || return 1

  # 3 · already there ⇒ the operator's own filing, not this session's scatter
  if [ -e "$_abs" ]; then return 1; fi

  # 4 · inside a git repo ⇒ project content. Walk up to $HOMEP, never past it.
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

# The path it SHOULD have used. A deny that names only what is wrong costs the
# reader a decision; this one is copy-pasteable.
suggest() { # <abs>
  _b="${1##*/}"
  _s="$(printf '%s' "${_b%.*}" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' \
              -e 's/-\{0,1\}[0-9]\{4\}-[0-9]\{2\}\(-[0-9]\{2\}\)\{0,1\}$//')"
  [ -n "$_s" ] || _s="deliverable"
  printf '%s/%s-%s/%s' "$ROOT" "$(date +%Y-%m-%d)" "$_s" "$_b"
}

deny() { # <rule> <shape> <what>
  # Shadow (harbor#482): recorded, not refused — floor_block's contract, for a JSON-verdict guard.
  if [ "${HELM_FLOOR_SHADOW:-0}" = 1 ]; then
    { floor_log_decision deliverables shadow "$1.$2" 2>/dev/null || :; } 2>/dev/null || :
    exit 0
  fi
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
    # The digest subject is the RESOLVED path, for guard-selfedit's reason: ./x,
    # //x and bin/../x are one target, and a recurrence count that treats them as
    # three cannot answer "is this the same block again?".
    FLOOR_OBS_SUBJECT="$(floor_norm_path "$P")"
    if is_loose_doc "$P"; then
      WANT="$(suggest "$LOOSE_ABS")"
      deny "$LOOSE_KIND" path "$(printf '%s' "$LOOSE_ABS" | sed "s#^$HOMEP#~#")"
    fi
    ;;
  Bash|Monitor)
    CMD="$(floor_field '.tool_input.command')"
    [ -n "$CMD" ] || exit 0
    FLOOR_OBS_SUBJECT="$CMD"
    # NO floor_heredoc_inert_only VETO HERE, DELIBERATELY, AND IT IS THE ONE
    # CHOICE THAT DECIDES WHETHER THIS ARM SEES ANYTHING AT ALL. That veto exits
    # the guard for the WHOLE call when a heredoc opener is `cat`/`tee` and not an
    # interpreter — which is precisely `cat > ~/report.html <<'HTML' … HTML`, the
    # single most common way a session writes a document from the shell. Consulting
    # it would have left this arm blind to its own main case while every test that
    # used a one-line redirect still passed.
    #
    # harbor#716: floor_bash_targets strips a body from DATA only, and its home-expanded
    # variant still carried it, so document bodies go BEFORE it. The opener line is
    # still judged (`cat > ~/report.html <<'HD'`), and a body fed to a shell is kept.
    # harbor#782: floor_hd_unwrap_doc_bodies also drops a body behind a compound
    # opener (`mkdir … && cat > f <<EOF`) or the `git commit -m "$(cat <<EOF)"`
    # argument form; `sh -c "$(cat <<EOF)"` still runs the body and is kept.
    _BCMD="$CMD"
    case "$CMD" in *'<<'*) _BCMD="$(floor_hd_unwrap_doc_bodies --writers "$CMD")" ;; esac
    TXT="$(floor_bash_targets "$_BCMD" || true)"
    [ -n "$TXT" ] || exit 0
    # WRITE POSITION, NOT MERE MENTION. `cat ~/report.html` is a read and
    # `open ~/x.pdf` is a read; only a destination is judged. Four shapes:
    #   · a redirection target
    #   · the operand of a verb that WRITES its argument (tee, touch, install…)
    #   · the LAST operand of a copy/move or of a converter whose output comes
    #     after its input — the destination, never the source (the P12-argv-fp
    #     distinction floor_seg_operand_under records), trailing redirects allowed
    #     (harbor#714, #785). The converters left the verb-then-path shape because
    #     that path is their INPUT.
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
    # A newline-delimited list of paths: IFS is set to newline alone so a
    # directory with a space in it stays one candidate.
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
