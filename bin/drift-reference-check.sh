#!/usr/bin/env sh
# M8 · ReferenceCheck (harbor#44) — validate the INSTALLED surface.
#
#   sh drift-reference-check.sh [--live | <config-dir>] [--json]
#   sh drift-reference-check.sh [--live | <config-dir>] --status
#
# Exit 0 = every reference on the installed surface resolves. Exit 1 = it does
# not. Exit 2 = bad usage. Exit 3 = under --status only, it could not look (no
# jq): nothing was judged, which is never a green. READ-ONLY: this script opens
# files and writes none, except that `--status` keeps when each finding was first
# seen in <config-dir>/cache/reconcile/drift.reference-check.tsv.
#
# `--status` is the reconcile form (contracts/reconcile.md, harbor#1031): the same
# findings, one row each as desired / observed / delta / age, and its exit code
# is the plain run's. It cannot be combined with --json, and it never repairs.
#
# Why (harbor#44): lint K1/T3 check references in the repo, but ~/.claude/CLAUDE.md (loaded every session) is a different file from the checkout's policy/constitution.md, and nothing checked it. This tool checks the installed surface against itself; lint X2 owns live-vs-repo.
# Read-only on purpose: every surface it reads is one admission-self-edit.sh protects, so it reports and hands the operator a command, never repairs.
# permissions.deny is out of scope: a deny naming a missing path is fail-safe, and matching globs to the filesystem manufactures false positives (CONSTITUTION №2.11).
# One file on purpose (docs/explanation/modularity.md): the REF rules share one walk of the installed surface.
# Removed notes: docs/explanation/code-cases/bin-drift-reference-check.md
set -u

# --help before any work (S4, harbor#140). The text is this file's own header, read at runtime up to the first blank comment line, so it cannot drift.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
STATUS=0
for a in "$@"; do [ "$a" = "--status" ] && STATUS=1; done
if [ "$STATUS" = 1 ]; then
  # --status takes --live or one config dir and nothing else: a flag it does not know is a usage error, not ignored.
  DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _np=0
  for a in "$@"; do
    case "$a" in
      --status|--live) ;;
      -*) printf 'reference-check: unknown option with --status: %s\n' "$a" >&2
          printf 'usage: drift-reference-check.sh [--live | <config-dir>] --status\n' >&2
          exit 2 ;;
      *)  DIR="$a"; _np=$((_np + 1)) ;;
    esac
  done
  if [ "$_np" -gt 1 ]; then
    printf 'usage: drift-reference-check.sh [--live | <config-dir>] --status\n' >&2
    exit 2
  fi
else
  case "${1:-}" in
    ''|--live) DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    --json)    DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    -*) printf 'reference-check: unknown option: %s\n' "$1" >&2
        printf 'usage: drift-reference-check.sh [--live | <config-dir>] [--json]\n' >&2
        exit 2 ;;
    *)  DIR="$1" ;;
  esac
fi
JSON=0
for a in "$@"; do [ "$a" = "--json" ] && JSON=1; done

# Resolved from this script's own directory, never the inspected tree, which may be hostile (audit-triage.sh). No dirname: B9's PATH has none.
case "$0" in */*) SELF="${0%/*}" ;; *) SELF=. ;; esac
SELF="$(CDPATH= cd -- "$SELF" && pwd -P)"
EXTRACT="$SELF/doc-cited-paths.awk"
# One log format (contracts/logging.md, harbor#809). A copy with no library-log.sh says so, never reads clean.
if [ ! -f "$SELF/library-log.sh" ]; then
  printf 'reference-check: library-log.sh is missing beside %s, so this copy cannot report; run the checkout copy: sh ~/port/harbor/bin/drift-reference-check.sh %s\n' "$SELF" "$*" >&2
  if [ "$STATUS" = 1 ]; then printf 'reconcile\t1\treference-check\nunchecked\tlibrary-log.sh is missing beside this copy, so nothing was judged\n'; exit 3; fi
  exit 1
fi
if [ ! -f "$SELF/library-fs.sh" ]; then
  printf 'reference-check: library-fs.sh is missing beside %s, so this copy cannot read mtimes; run the checkout copy: sh ~/port/harbor/bin/drift-reference-check.sh %s\n' "$SELF" "$*" >&2
  if [ "$STATUS" = 1 ]; then printf 'reconcile\t1\treference-check\nunchecked\tlibrary-fs.sh is missing beside this copy, so nothing was judged\n'; exit 3; fi
  exit 1
fi
. "$SELF/library-log.sh"
. "$SELF/library-fs.sh"
log_init reference-check
# --json's stdout is data, byte-identical to before; its log lines, if any, go to stderr. So is --status's.
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
[ "$JSON$STATUS" = 00 ] || LOG_FD=2
[ "$STATUS" = 0 ] || status_init drift.reference-check "$DIR" || exit 3
# A shell that cannot create a here-document's temp file runs every report loop below on nothing and reads clean; refuse instead.
_hd=""
{ IFS= read -r _hd <<EOF
ok
EOF
} 2>/dev/null || _hd=""
if [ "$_hd" != ok ]; then
  log_fail "this shell cannot create a here-document (TMPDIR=${TMPDIR:-unset} is not writable), so no rule could be judged"
  log_fix "TMPDIR=\"\$HOME/tmp\" sh $0 $*"
  log_end || :; exit 2
fi

# An absent config dir is an answer, not misuse (as admission-verify.sh): nothing installed, nothing dangles.
if [ ! -d "$DIR" ]; then
  if [ "$STATUS" = 1 ]; then status_end; exit $?; fi
  if [ "$JSON" = 1 ]; then printf '{"dir":"%s","installed":false,"findings":[]}\n' "$DIR"; exit 0; fi
  log_ok "no config dir at $DIR — nothing is installed here, so nothing dangles"
  log_end; exit $?
fi

# B9: a missing jq must never read as a clean run. Exit 1, not 2, which a caller would filter as "I typed it wrong".
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq not found, so $DIR/settings.json cannot be read — this is NOT a clean result"
  log_fix "$(pkg_hint jq)"
  # --status is D-29: could not look is 3. The plain run keeps its 1 (this note), and a reader accepts both.
  if [ "$STATUS" = 1 ]; then log_end || :; status_unjudged "jq is not on PATH, so settings.json was not read and nothing was judged"; exit 3; fi
  log_end; exit 1
fi

# the declared-root reader (harbor#462): the root is the first backticked token after the literal `**Path root:**`, `~/` expanded. Prints nothing when undeclared or malformed; REF-8 makes that fallback visible.
_declared_root() { # <file> -> absolute root, or empty
  _dr="$(awk '
    /\*\*Path root:\*\*/ {
      s = substr($0, index($0, "**Path root:**"))
      if (match(s, /`[^`]+`/)) { print substr(s, RSTART + 1, RLENGTH - 2); exit }
    }' "$1" 2>/dev/null)"
  case "${_dr:-}" in
    '')    printf '' ;;
    '~/'*) printf '%s/%s' "$HOME" "${_dr#\~/}" ;;
    '~')   printf '%s' "$HOME" ;;
    *)     printf '%s' "$_dr" ;;
  esac
}

# Where one citation resolves; REF-5 and REF-9 share it. The declared root binds `./` only: a skill mixes `./contracts/cu.md` (the repo) with `references/x.md` (beside SKILL.md), and one base breaks whichever form it is not for.
_cite_target() { # <ref> <document-dir> <declared-root-or-empty> -> absolute path
  _ct_p="${1%%#*}"                        # the fragment is not part of the path
  case "$_ct_p" in
    /*)  printf '%s' "$_ct_p" ;;           # already rooted; nothing to declare
    ./*) printf '%s/%s' "${3:-$2}" "${_ct_p#./}" ;;
    *)   printf '%s/%s' "$2" "$_ct_p" ;;   # ships beside the document
  esac
}

S="$DIR/settings.json"
FAIL=0
REL_DEAD=0   # ./-prefixed citations REF-5 found dead; REF-8's predicate
FINDINGS=""   # one `rule<TAB>subject<TAB>what breaks` per line
CITED_CLAUDE=0   # rows the extractor returned for CLAUDE.md; REF-10's predicate
CITED_SKILLS=0   # the same, across the installed skills
SKILL_FILES=0    # how many markdown files those rows were extracted from

# Findings are accumulated rather than printed as they are found, so --json and
# the human report are the same data rendered twice. A reporter that builds its
# JSON from a second pass is a reporter whose two outputs can disagree.
finding() { # <rule> <subject> <what-breaks> [<fix command>] — the fix is the human report's, never --json's
  FAIL=$((FAIL+1))
  FINDINGS="$FINDINGS$1	$2	$3	${4-}
"
}

# The command that installs <component>'s part of this dir: through deploy on the live box, the installer itself (--dir) elsewhere (harbor#809).
_phys() { CDPATH= cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
_sq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
_install_fix() { # <component> <installer>
  _if_r="$(sh "$SELF/scope-roots.sh" --get HARBOR_SCOPE_REPO 2>/dev/null || :)"; [ -n "$_if_r" ] || _if_r="${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}"
  LIVE="$HOME/.claude"  # deploy's live target, whatever CLAUDE_CONFIG_DIR says: deploy refuses a differing one
  if [ "$(_phys "$DIR")" = "$(_phys "$LIVE")" ]; then
    printf 'sh %s --apply --only %s --live' "$(_sq "$_if_r/bin/deploy.sh")" "$1"
  else
    _if_b="$SELF"; [ -f "$_if_b/$2.sh" ] || _if_b="$_if_r/bin"
    printf 'sh %s --apply --dir %s' "$(_sq "$_if_b/$2.sh")" "$(_sq "$DIR")"
  fi
}

# THE DENOMINATOR (harbor#467). Every extracting rule records what it examined and the report prints it on clean runs too: "0 findings" and "0 items examined" look identical, and REF-5 once reported "resolves" over zero extracted citations. REF-10 turns an extractor that found nothing in a cited document into a finding.
EXAMINED=""   # one `rule<TAB>count<TAB>what` per line
examined() { # <rule> <count> <what>
  EXAMINED="$EXAMINED$1	$2	$3
"
}

# Deliberately broader than the extractor and consulted only where it returned zero (harbor#467), so it can neither inflate a count nor block ordinary work (№2.11). It cannot see partial blindness (nine of ten found). URLs are blanked first: REF-5 scopes them out on purpose.
_looks_cited() { # <file> -> 0 if the file contains anything citation-shaped
  awk '
    { line = $0
      gsub(/(https?:\/\/|mailto:)[^ \t]*/, " ", line)
      if (line ~ /\]\(/) { found = 1; exit }
      if (line ~ /[A-Za-z0-9_.~-]\/[A-Za-z0-9_.~\/-]*\.[A-Za-z][A-Za-z]/) { found = 1; exit }
    }
    END { exit !found }' "$1" 2>/dev/null
}

# Every absolute path inside a hook command: a command names the wrapper AND the scanner, and the wrapper existing says nothing about the scanner. awk, not grep: grep here is ugrep and skips gitignored and binary files, which gives fewer findings, a false clean.
cmd_paths() { printf '%s\n' "$1" | tr ' ' '\n' | awk '/^\//'; }

# settings.json must PARSE before any rule claims to have read it: the rules below send jq's complaint to /dev/null, so a malformed file once produced no rows and "clean": true. "Could not look" must never render as "nothing to see".
SETTINGS_OK=0
if [ -f "$S" ]; then
  if jq -e . "$S" >/dev/null 2>&1; then
    SETTINGS_OK=1
  else
    finding "REF-0" "settings.json" \
      "does not parse — the hook, duplicate-wiring and statusline rules could not run, and a result with no findings would have meant nothing"
  fi
fi

# ── REF-1 · every hook command names a file that exists ──────────────────────
# What breaks: the harness spawns a hook whose script does not exist; for a PreToolUse guard that is a hole in the floor.
if [ "$SETTINGS_OK" = 1 ]; then
  jq -r '.hooks // {} | to_entries[] | .key as $e | .value[]? | .hooks[]?.command // empty | "\($e)\t\(.)"' "$S" 2>/dev/null \
  | while IFS='	' read -r ev cmd; do
      [ -n "${cmd:-}" ] || continue
      for p in $(cmd_paths "$cmd"); do
        # `_n` is a count row, not a finding (harbor#467): the loop runs in a pipeline subshell, so the denominator travels in the same file as the findings.
        printf '_n\t\t\n'
        [ -e "$p" ] || printf 'REF-1\t%s: %s\tthe harness will spawn a hook whose script does not exist\n' "$ev" "$p"
      done
    done > "${TMPDIR:-/tmp}/refchk-1.$$"
  _r1_n=0
  while IFS='	' read -r r s w; do
    [ "$r" = "_n" ] && { _r1_n=$((_r1_n+1)); continue; }
    [ -n "${r:-}" ] && finding "$r" "$s" "$w"
  done < "${TMPDIR:-/tmp}/refchk-1.$$"
  rm -f "${TMPDIR:-/tmp}/refchk-1.$$"
  examined "REF-1" "$_r1_n" "absolute path(s) inside wired hook commands"
fi

# ── REF-2 · no command wired twice under the SAME selector ───────────────────
# A duplicate is the same command under an EQUIVALENT selector (a missing `matcher` key equals ""; harbor#95), not merely twice in one event: admission-egress.sh is wired twice on purpose (write tools, web/MCP).
# What breaks: the hook runs once per wiring (context-resolve.sh injected its notice twice).
# This tool never fixes; the installers are append-only, so the repair is the operator's, from their own terminal:
#   jq --arg c "/bin/sh $HOME/.claude/bin/context-resolve.sh" \
#      '.hooks.SessionStart |= map(select(has("matcher") or ([.hooks[].command] | index($c) | not)))' \
#      ~/.claude/settings.json
# Direction matters: this drops the bucket with NO `matcher` key and keeps `matcher: ""`, the one that also carries admission-observe.sh and admission-integrity.sh; the opposite filter removes two hooks and reports success.
# Re-pin afterwards with pin-instructions.sh or B8 alarms on the repair, then run `sh bin/drift-reference-check.sh --live`.
if [ "$SETTINGS_OK" = 1 ]; then
  jq -r '.hooks // {} | to_entries[] | .key as $e | .value[]? | (.matcher // "") as $m
         | .hooks[]?.command // empty | [$e, $m, .] | @tsv' "$S" 2>/dev/null \
  | sort | uniq -c \
  | sed -E 's/^ *//' \
  | awk -F'\t' '{
        n = $1; sub(/ .*/, "", n)          # uniq -c prefixes "<count> " onto field 1
        ev = $1; sub(/^[0-9]+ /, "", ev)
        if (n + 0 > 1)
          printf "REF-2\t%s: %s\twired %s times under one selector, so the hook runs once per wiring\n", ev, $3, n
      }' > "${TMPDIR:-/tmp}/refchk-2.$$"
  while IFS='	' read -r r s w; do [ -n "${r:-}" ] && finding "$r" "$s" "$w"; done < "${TMPDIR:-/tmp}/refchk-2.$$"
  rm -f "${TMPDIR:-/tmp}/refchk-2.$$"
fi

# ── REF-3 · the statusline command exists ────────────────────────────────────
# What breaks: the status line goes blank or errors into the prompt every refresh, with no log.
if [ "$SETTINGS_OK" = 1 ]; then
  _sl="$(jq -r '.statusLine.command // empty' "$S" 2>/dev/null)"
  _r3_n=0
  if [ -n "${_sl:-}" ]; then
    for p in $(cmd_paths "$_sl"); do
      _r3_n=$((_r3_n+1))
      [ -e "$p" ] || finding "REF-3" "statusLine: $p" "the status line runs a script that does not exist"
    done
  fi
  examined "REF-3" "$_r3_n" "path(s) in the statusline command"
fi

# ── REF-4 · every content pin names a file that is still there ───────────────
# What breaks: B6 blocks the session on a tampered pin and cannot tell a pin whose file is gone from tampering, so a stale pin is a boot failure at the next restart.
if [ -d "$DIR/.helm-pins" ]; then
  _r4_n=0
  for pin in "$DIR"/.helm-pins/*.sha256; do
    [ -e "$pin" ] || continue
    _r4_n=$((_r4_n+1))
    _b="$(basename "$pin" .sha256)"
    [ -e "$DIR/bin/$_b" ] || finding "REF-4" ".helm-pins/$_b.sha256" \
      "a pin with no file — B6 cannot tell that from tampering, and its answer to tampering is to block the session"
  done
  examined "REF-4" "$_r4_n" "content pin(s)"
fi

# ── REF-7 · the governance token's install ORDER (harbor#7) ──────────────────
# CONSTITUTION §4: a note with any token but THIS session's is external content. The token is sha256(box salt || session id), empty until govern-token.sh --init mints the salt. Install, then salt minted mid-session is the dangerous order: --announce already ran silent while notes arrive stamped (contracts/hooks.md install-order rule).
# The proxy is mtime, since no record of session start exists: a salt NEWER than the settings.json that wired the announce. A salt minted mid-session before the wiring is safe anyway.
if [ -f "$S" ] && command -v jq >/dev/null 2>&1; then
  _ref7_wired="$(jq -r '[.hooks.SessionStart[]?.hooks[]?.command // empty | select(test("govern-token"))] | length' "$S" 2>/dev/null || echo 0)"
  _ref7_salt="$DIR/.helm-govern-salt"
  if [ "${_ref7_wired:-0}" -gt 0 ] 2>/dev/null; then
    if [ ! -f "$_ref7_salt" ]; then
      # Not a finding: the honest degrade (govern-token.sh exits silent with no salt). Reporting it would train skipping REF-7 on an unconfigured box (§2.11).
      # unconfigured — §2.11, the rule that a false positive is not safety.
      :
    else
      # Whole-second mtimes on BSD and GNU, so EQUAL is undecidable rather than safe.
      # The dialect probe must not leak into the answer (harbor#226): GNU `stat -f` is --file-system, writes a filesystem report to stdout before failing, and its `x` read as "no mtime" (a false REF-7 on every GNU box; not reproducible on BSD CI).
      _ref7_m() { # <file> -> epoch mtime, or empty (bin/library-fs.sh, harbor#618)
        fs_mtime "$1"
      }
      # A one-session hazard must not be a permanent finding (harbor#226): both mtimes are frozen, so the comparison alone would stay red forever.
      # Evidence the config dir already carries: a $CFG/sessions/<pid>.json newer than the salt means a session began since, so its announce saw the salt. mtime, not the JSON (records are heterogeneous: epoch-ms startedAt, or only a procStart string). No marker file: govern-token.sh never writes, by design. No sessions dir is no evidence, and the finding stays.
      _ref7_discharged() { # <salt-mtime> -> 0 when a session has started since
        _sd="$DIR/sessions"
        [ -d "$_sd" ] || return 1
        for _f in "$_sd"/*; do
          [ -f "$_f" ] || continue
          _fm="$(_ref7_m "$_f")"
          [ -n "$_fm" ] || continue
          [ "$_fm" -gt "$1" ] 2>/dev/null && return 0
        done
        return 1
      }
      _sm="$(_ref7_m "$_ref7_salt")"; _wm="$(_ref7_m "$S")"
      case "${_sm:-x}${_wm:-x}" in
        *x*) finding "REF-7" ".helm-govern-salt" \
               "could not read an mtime for the salt or settings.json, so the install-order rule was NOT checked — this is not a pass" ;;
        *)
          if [ "$_sm" -gt "$_wm" ] 2>/dev/null && ! _ref7_discharged "$_sm"; then
            finding "REF-7" ".helm-govern-salt" \
              "the salt is NEWER than the settings.json that wires --announce, so it was minted after the hook was installed: this session's announce ran silent while notes carry a token nobody announced (contracts/hooks.md install-order rule). Start a NEW session — the token is derived, so nothing needs rewriting, and the new session's own record in sessions/ is what clears this finding" \
              "none: contracts/hooks.md's install-order rule — start a new session"
          fi ;;
      esac
    fi
  elif [ -f "$DIR/.helm-govern-salt" ]; then
    finding "REF-7" "settings.json" \
      "a governance salt is minted but no SessionStart hook announces the token — injection-rule.sh stamps notes with a value the reader never receives from a trusted channel, which CONSTITUTION §4 tells them to reject" \
      "$(_install_fix inject context-injection-install)"
  fi
fi

# ── REF-5 · the installed CLAUDE.md's citations resolve ──────────────────────
# The K1 analogue for the surface that is read: K1 checks policy/constitution.md in the repo, this checks the deployed copy, where the installers do not deploy every doc. What breaks: a dead citation teaches the reader that parts of the document are inert.
# Blind until harbor#462: it extracted only `](target)` links after the constitution moved to backticked `./path`s, so findings went 12 -> 0 and read like a repair. The extractor is now bin/doc-cited-paths.awk, shared with K1 and resolved from this script's own directory, never the tree under inspection (audit-triage.sh).
# Declared root: a document may carry a `**Path root:**` line naming one backticked root (one parseable line); a root that is not a directory is a finding. No declaration falls back to the document's own directory, and REF-8 makes that visible.
# Anchors, URLs and mailto are skipped (doc-cite-verify.sh owns URLs). A #fragment is stripped before the filesystem test and kept in the report.
if [ -f "$DIR/CLAUDE.md" ]; then
  if [ ! -f "$EXTRACT" ]; then
    # B9 one layer in: a missing extractor must never read as a clean citation sweep.
    finding "REF-5" "doc-cited-paths.awk" \
      "the shared extractor is not beside this script ($EXTRACT) — NO citation was checked, and this is not a pass"
  else
    _root="$(_declared_root "$DIR/CLAUDE.md")"
    if [ -n "$_root" ] && [ ! -d "$_root" ]; then
      finding "REF-5" "CLAUDE.md → path root $_root" \
        "the document declares a path root that is not a directory on this box, so every ./ citation in it resolves nowhere"
      _root=""
    fi
    # The denominator is the extractor's output, not the subset reaching the filesystem (harbor#467): a URL-only document was seen and scoped out, not missed. Extracted once into a file so the printed count is the one REF-5 used.
    awk -f "$EXTRACT" "$DIR/CLAUDE.md" 2>/dev/null | sort -u > "${TMPDIR:-/tmp}/refchk-5c.$$"
    CITED_CLAUDE="$(awk 'NF { n++ } END { print n+0 }' "${TMPDIR:-/tmp}/refchk-5c.$$")"
    while read -r ref; do
        case "$ref" in http://*|https://*|mailto:*|'#'*|'') continue ;; esac
        [ -n "${ref%%#*}" ] || continue       # a pure `#anchor` is intra-document
        _t="$(_cite_target "$ref" "$DIR" "$_root")"
        [ -e "$_t" ] || printf 'REF-5\tCLAUDE.md → %s\ta cited path that does not resolve, looked for at %s\n' "$ref" "$_t"
      done < "${TMPDIR:-/tmp}/refchk-5c.$$" > "${TMPDIR:-/tmp}/refchk-5.$$"
    rm -f "${TMPDIR:-/tmp}/refchk-5c.$$"
    examined "REF-5" "$CITED_CLAUDE" "citation(s) extracted from CLAUDE.md"
    while IFS='	' read -r r s w; do [ -n "${r:-}" ] && finding "$r" "$s" "$w"; done < "${TMPDIR:-/tmp}/refchk-5.$$"
    # REF-8's predicate, counted from REF-5's own findings so the two cannot disagree: did a ./ citation FAIL, not are there any.
    REL_DEAD="$(awk -F'	' 'index($2, "CLAUDE.md \xe2\x86\x92 ./") == 1' \
                "${TMPDIR:-/tmp}/refchk-5.$$" | wc -l | tr -d ' ')"
    rm -f "${TMPDIR:-/tmp}/refchk-5.$$"
  fi
fi

# ── REF-5 · and the installed surface's own dangling edges (harbor#996 C2) ───
# The reference graph's `deploys_to` edges ending on a file this config dir lacks (harbor#996 C2). doc-graph-generate.sh --dangling owns the definition (manifest only, no tree scan); it is found beside this script or in the harbor checkout, never in the inspected tree. With neither, the count says 0 examined, which is not a pass.
_gg="$SELF/doc-graph-generate.sh"
if [ ! -f "$_gg" ]; then
  _gg="$(sh "$SELF/scope-roots.sh" --get HARBOR_SCOPE_REPO 2>/dev/null || :)"; _gg="${_gg:-${HARBOR_SCOPE_REPO:-${PORT_ROOT:-$HOME/port}/harbor}}/bin/doc-graph-generate.sh"
fi
if [ -f "$DIR/.harbor-manifest" ] && [ -f "$_gg" ] && command -v python3 >/dev/null 2>&1; then
  # Held in a variable, not a temp file: an unwritable TMPDIR made 473 rows read as none. graph-gen exits 0 or 1 (dangling rows); anything else judged nothing.
  _gr=0; _dang="$(CLAUDE_CONFIG_DIR="$DIR" sh "$_gg" --dangling 2>/dev/null)" || _gr=$?
  if [ "$_gr" -le 1 ]; then
    while IFS='	' read -r _dp _ds _dw; do
      [ -n "${_dp:-}" ] && finding "REF-5" "manifest → $_dp" "$_dw ($_ds), so a dangling deploys_to edge in the reference graph"
    done <<EOF
$_dang
EOF
    examined "REF-5" "$(grep -vc -e '^#' -e '^[[:space:]]*$' "$DIR/.harbor-manifest" || :)" "manifest row(s) checked for a dangling installed file"
  else
    finding "REF-5" "doc-graph-generate.sh --dangling" "it exited $_gr, so no installed file was checked against the manifest" "CLAUDE_CONFIG_DIR=$DIR sh $_gg --dangling"
  fi
elif [ -f "$DIR/.harbor-manifest" ]; then
  examined "REF-5" 0 "manifest row(s) checked for a dangling installed file (doc-graph-generate.sh or python3 not found, so none judged)"
fi

# ── REF-8 · a document citing ./paths declares which root they resolve against ─
# harbor#462: `./docs/...` is not a wrong path but an unrooted one. The constitution is authored where `./` works and installed where it does not, so each reader resolved against wherever they stood and a followed citation gave nothing.
# Warn-shaped, and fires only on a FAILURE: a ./ citation that failed in a document declaring no root. Firing on every document that cites ./paths (the first cut) turned the clean fixture red (§2.11).
if [ -f "$DIR/CLAUDE.md" ] && [ -f "$EXTRACT" ] && [ "${REL_DEAD:-0}" -gt 0 ] 2>/dev/null; then
  if [ -z "$(_declared_root "$DIR/CLAUDE.md")" ]; then
    finding "REF-8" "CLAUDE.md" \
      "$REL_DEAD ./-prefixed citation(s) above are dead AND the document declares no path root, so each one resolved against whichever directory the reader happened to be in — name the root in one line: > **Path root:** \`~/port/harbor\`"
  fi
fi

# ── REF-9 · the installed SKILLS' citations resolve where they are read ──────
# REF-5 generalised to the skills corpus: same extractor, resolver and declared-root rule, separate because the blast radius differs (the constitution is in every session, a skill when its subject comes up). Found by harbor#462: skills escaping their own directory (../../contracts/cu.md) to repo docs the installer does not deploy, green from the repo and dead from ~/.claude/skills/<name>/.
# Relative citations only (§2.11): an absolute /x is already rooted, and vendored corpora hold web paths such as /favicon.png that are not files. Config-owned absolutes are REF-1's and REF-4's.
# One awk process, not one per file (539 files measured 687 ms against 135 ms); the total is docs/reference/checks.md's, not restated here.
# Not skills/synced/: an ownership line, not a pattern. The harness rewrites that tree on every sync, so no edit here survives, and its only findings were a `[Source](URL)` placeholder template (a red nobody can act on, §2.11). It is counted, not examined, so the exclusion shows on every run (harbor#527).
_owned_skill_md() { # <find action> → every installed skill markdown file outside skills/synced/ and skills/.trash/ (a skill the harness moved aside, harbor#1437)
  find "$DIR/skills" -path "$DIR/skills/synced" -prune -o -path "$DIR/skills/.trash" -prune -o -name '*.md' "$@" 2>/dev/null
}
if [ -d "$DIR/skills" ]; then
  if [ ! -f "$EXTRACT" ]; then
    finding "REF-9" "doc-cited-paths.awk" \
      "the shared extractor is not beside this script ($EXTRACT) — NO skill citation was checked, and this is not a pass"
  else
    _owned_skill_md -print0 \
      | xargs -0 awk -v WITHFILE=1 -f "$EXTRACT" 2>/dev/null \
      | sort -u > "${TMPDIR:-/tmp}/refchk-9.$$"
    # REF-9's denominator (harbor#467): rows returned and files they could come from; 0 over 0 files is an empty tree, 0 over many is a broken extractor.
    SKILL_FILES="$(_owned_skill_md -print | awk 'END { print NR+0 }')"
    CITED_SKILLS="$(awk 'NF { n++ } END { print n+0 }' "${TMPDIR:-/tmp}/refchk-9.$$")"
    _r9_synced="$(find "$DIR/skills/synced" -name '*.md' 2>/dev/null | awk 'END { print NR+0 }')"
    if [ "$_r9_synced" -gt 0 ]; then
      examined "REF-9" "$CITED_SKILLS" "citation(s) extracted from $SKILL_FILES installed skill file(s); $_r9_synced under skills/synced/ counted, not examined — the harness rewrites them on sync"
    else
      examined "REF-9" "$CITED_SKILLS" "citation(s) extracted from $SKILL_FILES installed skill file(s)"
    fi
    # The declared root is read once per document, not once per citation.
    _r9_doc=''; _r9_root=''; _r9_dir=''
    while IFS='	' read -r _doc ref; do
      [ -n "${_doc:-}" ] || continue
      case "$ref" in http://*|https://*|mailto:*|'#'*|'') continue ;; esac
      case "${ref%%#*}" in ''|/*) continue ;; esac   # rooted already, or a pure anchor
      if [ "$_doc" != "$_r9_doc" ]; then
        _r9_doc="$_doc"
        _r9_dir="$(dirname -- "$_doc")"
        _r9_root="$(_declared_root "$_doc")"
        if [ -n "$_r9_root" ] && [ ! -d "$_r9_root" ]; then
          finding "REF-9" "${_doc#"$DIR"/} → path root $_r9_root" \
            "the document declares a path root that is not a directory on this box, so every ./ citation in it resolves nowhere"
          _r9_root=''
        fi
      fi
      _t="$(_cite_target "$ref" "$_r9_dir" "$_r9_root")"
      [ -e "$_t" ] || finding "REF-9" "${_doc#"$DIR"/} → $ref" \
        "a skill cites a path that does not resolve from where the skill is READ, looked for at $_t"
    done < "${TMPDIR:-/tmp}/refchk-9.$$"
    rm -f "${TMPDIR:-/tmp}/refchk-9.$$"
  fi
fi

# ── REF-10 · an extractor that returned NOTHING from a cited document ────────
# harbor#467, the rule the 34 days of green needed. The rules above ask "does what I found resolve"; this asks "did I find anything". Asymmetric on purpose: the extractor decides by returning zero and `_looks_cited` only whether that zero is suspicious, so neither fires alone.
if [ -f "$DIR/CLAUDE.md" ] && [ -f "$EXTRACT" ] && [ "$CITED_CLAUDE" -eq 0 ]; then
  _looks_cited "$DIR/CLAUDE.md" && finding "REF-10" "CLAUDE.md" \
    "the citation extractor returned NOTHING from a document that carries citation-shaped text — REF-5's clean line would have meant 'I checked zero paths', which is not the claim it appears to make"
fi
if [ -f "$EXTRACT" ] && [ "$SKILL_FILES" -gt 0 ] && [ "$CITED_SKILLS" -eq 0 ]; then
  # Reached only when the corpus produced zero rows, over the same corpus REF-9 read (not synced files).
  _r10_hit="$(_owned_skill_md -print \
              | while IFS= read -r _f; do _looks_cited "$_f" && { printf '%s' "$_f"; break; }; done)"
  [ -n "${_r10_hit:-}" ] && finding "REF-10" "skills/ → ${_r10_hit#"$DIR"/}" \
    "the extractor returned NOTHING across $SKILL_FILES installed skill file(s) while at least one of them carries citation-shaped text — REF-9 reported on a corpus it could not read"
fi

# ── REF-6 · an INSTALLED config dir with no constitution ─────────────────────
# REF-5 is guarded on CLAUDE.md existing, so its absence was the quietest state: zero findings, exit 0. The predicate is settings.json, not the directory (an empty dir is answered above): a configured box with no CLAUDE.md runs hooks and loads no doctrine.
# Before turning this into a hard failure in floor-verify or a gate: test-sandbox-make.sh aborts when floor-verify fails and writes no CLAUDE.md into a sandbox, so give sandboxes a constitution first (№2.11).
if [ -f "$S" ] && [ ! -f "$DIR/CLAUDE.md" ]; then
  finding "REF-6" "CLAUDE.md" \
    "a configured box with no constitution — hooks and guards run, doctrine does not, and every other rule here reports clean" \
    "$(_install_fix constitution policy-constitution-install)"
fi

# ── report ───────────────────────────────────────────────────────────────────
# --status: the findings as reconcile rows (contracts/reconcile.md). What each rule wants, in its own words;
# the rest of the row is the finding's.
_ref_desired() { # <rule>
  case "$1" in
    REF-0)  printf 'settings.json parses' ;;
    REF-1)  printf 'every hook command names a file that exists' ;;
    REF-2)  printf 'no command is wired twice under one selector' ;;
    REF-3)  printf 'the statusline command exists' ;;
    REF-4)  printf 'every content pin names a file that is there' ;;
    REF-5)  printf 'every citation in the installed CLAUDE.md resolves' ;;
    REF-6)  printf 'an installed config dir holds a constitution' ;;
    REF-7)  printf 'the governance salt is not newer than the hook that announces it' ;;
    REF-8)  printf 'a document that cites ./ paths declares their root' ;;
    REF-9)  printf 'every citation in an installed skill resolves where it is read' ;;
    REF-10) printf 'the extractor reads what a cited document cites' ;;
    *)      printf 'the rule holds' ;;
  esac
}
if [ "$STATUS" = 1 ]; then
  # Items examined and fine = what the rules counted, less the findings inside those counts; a finding of a rule with no count
  # (REF-0, 6, 8, 10) is an item of its own, which status_drift adds.
  status_ok "$(RC_EX="$EXAMINED" RC_FN="$FINDINGS" awk 'BEGIN { m = split(ENVIRON["RC_EX"], E, "\n"); for (i = 1; i <= m; i++) { split(E[i], f, "\t"); if (f[1] != "") { d[f[1]] = 1; n += f[2] } }
    m = split(ENVIRON["RC_FN"], F, "\n"); for (i = 1; i <= m; i++) { split(F[i], g, "\t"); if (g[1] in d) k++ }
    c = n - k; print (c > 0 ? c : 0) }')"
  while IFS='	' read -r r s w fx; do
    [ -n "${r:-}" ] || continue
    case "${fx:-}" in ''|'none: '*) fx='-' ;; esac
    status_drift "$r $s" "$(_ref_desired "$r")" "$w" "$fx"
  done <<EOF
$FINDINGS
EOF
  status_end; exit $?
fi
if [ "$JSON" = 1 ]; then
  printf '%s' "$FINDINGS" | jq -R -s --arg dir "$DIR" --arg ex "$EXAMINED" '
    { dir: $dir, installed: true,
      findings: [ split("\n")[] | select(length > 0) | split("\t")
                  | {rule: .[0], subject: .[1], breaks: .[2]} ],
      examined: [ $ex | split("\n")[] | select(length > 0) | split("\t")
                  | {rule: .[0], count: (.[1] | tonumber), what: .[2]} ] }
    | . + {clean: ((.findings | length) == 0)}'
  [ "$FAIL" -eq 0 ] || exit 1
  exit 0
fi
# The human report on log-lib (harbor#809): a finding is a FAIL line, then its fix. Loops read a
# heredoc, not a pipe, so log-lib's counts are this shell's and the summary agrees with the exit code.
log_head "$DIR"
if [ "$FAIL" -eq 0 ]; then
  log_ok 'every hook, pin and citation on the installed surface resolves'
else
  while IFS='	' read -r r s w fx; do
    [ -n "${r:-}" ] || continue
    log_fail "$(printf '%-6s %s — %s' "$r" "$s" "$w")"
    case "${fx:-}" in
      '')      log_nofix "bin/drift-reference-check.sh $r" ;;
      'none: '*) log_nofix "${fx#none: }" ;;
      *)       log_fix "$fx" ;;
    esac
  done <<EOF
$FINDINGS
EOF
fi
# The denominator is part of the verdict (harbor#467), printed on clean runs too.
while IFS='	' read -r r n w; do
  [ -n "${r:-}" ] || continue
  log_note "$(printf '%-6s examined %s %s' "$r" "$n" "$w")"
done <<EOF
$EXAMINED
EOF
[ "$FAIL" -eq 0 ] || log_note "$FAIL finding(s). Nothing here is repaired by this tool — every surface it reads is one admission-self-edit.sh protects, deliberately."
log_end; exit $?
