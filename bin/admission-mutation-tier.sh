#!/usr/bin/env sh
# M10 · MutationTier (harbor#44) — classify a path under a Helm config dir by what
# writing to it lets an agent DO to the floor.
#
#   sh admission-mutation-tier.sh <path>...        one line per path: tier, guard, deny
#   sh admission-mutation-tier.sh --json <path>...
#   sh admission-mutation-tier.sh --report [--live | <config-dir>]
#
# WHY A TIER AND NOT A BOOLEAN. `admission-self-edit.sh` answers protected / not
# protected, which is the wrong shape for "strict about settings.json, relaxed about a cache". Tiers are that second question.
# Removed notes: docs/explanation/code-cases/bin-admission-mutation-tier.md
#
# NOT INERT: a tier table nothing reads is a wish (policy/constitution.md). tests/admission/mutation-tier/mutation-tier.test.sh fires the REAL
# admission-self-edit.sh at every fixture path and re-reads the whole permissions.deny array, so table and surface cannot drift; a divergence fails CI.
# ONE FILE (docs/explanation/modularity.md): splitting classifier from reporter would put two spellings of the tier globs in two files.
# READ-ONLY in every mode; the report's own lines are log-lib's (contracts/logging.md, harbor#771).
set -eu
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/library-log.sh"
log_init mutation-tier

MODE=classify
JSON=0
DIR=""
LIVE_OK=0
LIVE_DIR="$HOME/.claude"
PATHS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json)   JSON=1 ;;
    --report) MODE=report ;;
    --live)   LIVE_OK=1 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) printf 'mutation-tier: unknown option %s\n' "$1" >&2; exit 2 ;;
    *)  if [ "$MODE" = "report" ] && [ -z "$DIR" ]; then DIR="$1"; else PATHS="$PATHS $1"; fi ;;
  esac
  shift
done

ROOT="${HARBOR_SCOPE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}"
FIX="$ROOT/fixtures/mutation-tier/cases.json"
[ -n "$DIR" ] || { [ "$LIVE_OK" -eq 1 ] && DIR="$LIVE_DIR"; }
CFG="${DIR:-${CLAUDE_CONFIG_DIR:-$LIVE_DIR}}"

# Trailing slashes are stripped (PR #126): rel_of matches the prefix "$CFG"/*, so a config dir spelled with one made a double slash and every
# path read `outside`. `/` itself is left alone.
while [ "$CFG" != "/" ] && [ "${CFG%/}" != "$CFG" ]; do CFG="${CFG%/}"; done

# ── THE PREDICATE ────────────────────────────────────────────────────────────
# Matched against the path RELATIVE to the config dir, LOWERCASED (APFS is case-insensitive; red-team pass 2 bypassed admission-self-edit.sh with
# `Settings.json`). ORDER IS THE RULE: most specific first, so `.helm-pins/*` is tested before any broader glob.
tier_of() { # <relative-path-lowercased> -> 0|1|2|3
  case "$1" in
    settings.json|settings.local.json)                       echo 0 ;;
    .sec0-baseline.sha256|.helm-baseline|.helm-floor-teeth)   echo 0 ;;
    .helm-snapshots)                                         echo 0 ;;
    .helm-instructions.sha256|.helm-log-token|.helm-obs-salt) echo 0 ;;
    .helm-pins/*|.helm-peers/*)                              echo 0 ;;
    # harbor#779: the rest of contracts/control-plane-state.md's integrity rows.
    .helm-obs-host|.helm-govern-salt|.helm-install-stamp|.helm-judge) echo 0 ;;
    .helm-context/*|.helm-stop-gate/*|.helm-apiroute/*|.helm-apiroute-allow) echo 0 ;;
    .helm-approvals/*|.helm-ship/*)                          echo 0 ;;
    claude.md|claude.local.md)                               echo 1 ;;
    bin/*|hooks/*)                                           echo 1 ;;
    memory/observability/*|memory/work/*|memory/knowledge/*)  echo 2 ;;
    memory/learning/*|memory/wisdom/*|memory/telos/*)         echo 2 ;;
    memory/identity.md|memory/ideas.md)                       echo 2 ;;
    *)                                                        echo 3 ;;
  esac
}

_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# rel_of: the path relative to $CFG, or empty when outside. A classifier over a NAME, so no physical resolution (a path that does not exist yet
# still has a tier); admission-self-edit.sh resolves physically, which is a different job. OUTSIDE IS NOT TIER 3, it is unjudged: unmatched
# paths fell to tier 3 and /etc/passwd read as reassuringly ordinary. BOTH SIDES ARE NORMALISED (PR #128): with a config dir spelled
# `/tmp/cfg/` a shell-built `$CFG/settings.json` leaves a leading slash that matched no glob, so leading separators are dropped after the prefix.
rel_of() {
  case "$1" in
    "$CFG"/*)
      _rel="${1#"$CFG"/}"
      while [ "${_rel#/}" != "$_rel" ]; do _rel="${_rel#/}"; done
      printf '%s' "$_rel" ;;
    *) printf '%s' "" ;;
  esac
}

# ── LIVE LAYER PROBES (report mode) ──────────────────────────────────────────
# guard_blocks fires the REAL guard in a sandbox config dir: a case glob would only ask a copy of the guard.
guard_blocks() { # <abs-path> <sandbox-cfg> -> yes|no|unknown
  # `-r`, not `-x`: the guard runs as `sh <file>` and repo copies are 0644; `-x` reported `unknown` for every path.
  [ -r "$2/bin/admission-self-edit.sh" ] || { printf 'unknown'; return 0; }
  # The parent dir must exist: the guard resolves the target physically (floor_norm_path), and an unresolvable path keeps a spelling the protected
  # globs miss, which printed UNPROTECTED for a path the guard blocks (§2.6).
  mkdir -p "$(dirname -- "$1")" 2>/dev/null || :
  _rc=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
    | CLAUDE_CONFIG_DIR="$2" sh "$2/bin/admission-self-edit.sh" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = "2" ] && printf 'yes' || printf 'no'
}

# deny_covers matches each entry's glob against the path over the WHOLE array, not a substring grep (a neighbouring entry would read as coverage).
deny_covers() { # <relative-path> <config-dir> -> yes|no|unknown
  command -v jq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  [ -f "$2/settings.json" ] || { printf 'unknown'; return 0; }
  # `**` crosses `/`, a single `*` does not, via the placeholder @@DS@@: printable, because a literal NUL made ugrep treat the file as binary and
  # lint D1 misfire; and no lookbehind, which fails silently on a jq built without it. Dot escaping is ONE backslash, not two (two compiled to a
  # literal backslash plus any character and matched nothing).
  _hit="$(jq -r --arg p "$1" '
      def glob2re:
        gsub("\\."; "\\.")
        | gsub("\\*\\*"; "@@DS@@")
        | gsub("\\*"; "[^/]*")
        | gsub("@@DS@@"; ".*");
      [ .permissions.deny[]? | select(type == "string") | select(startswith("Edit(~/.claude/")) ]
    | map(sub("^Edit\\(~/\\.claude/"; "") | sub("\\)$"; ""))
      # Bind the entry FIRST: testing against the path inside the pipeline rebinds the dot to the path, so every path matched itself and read as covered.
    | map(. as $e | select($p | test("^" + ($e | glob2re) + "$")))
    | length' "$2/settings.json" 2>/dev/null || echo 0)"
  [ "${_hit:-0}" -gt 0 ] 2>/dev/null && printf 'yes' || printf 'no'
}

# ── CLASSIFY ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "classify" ]; then
  [ -n "$PATHS" ] || { printf 'mutation-tier: no paths given (see --help)\n' >&2; exit 2; }
  if [ "$JSON" = "1" ]; then printf '['; _sep=""; fi
  for _p in $PATHS; do
    _r="$(rel_of "$_p")"
    if [ -z "$_r" ]; then
      if [ "$JSON" = "1" ]; then
        printf '%s{"path":"%s","relative":null,"tier":null,"scope":"outside"}' "$_sep" "$_p"; _sep=","
      else
        printf 'outside %s\n' "$_p"
      fi
      continue
    fi
    _t="$(tier_of "$(_lower "$_r")")"
    if [ "$JSON" = "1" ]; then
      printf '%s{"path":"%s","relative":"%s","tier":%s,"scope":"inside"}' "$_sep" "$_p" "$_r" "$_t"; _sep=","
    else
      printf 'tier %s  %s\n' "$_t" "$_r"
    fi
  done
  [ "$JSON" = "1" ] && printf ']\n'
  exit 0
fi

# ── REPORT ───────────────────────────────────────────────────────────────────
# The product: where the two enforcement layers DISAGREE about one path.
log_head "report on $CFG"
if ! command -v jq >/dev/null 2>&1; then
  log_fail "jq is required for --report, and it is not on PATH"
  log_fix "$(pkg_hint jq)"
  log_end || :; exit 1
fi
if [ ! -f "$FIX" ]; then
  log_fail "no fixture at $FIX — the tier table the report is built from"
  log_nofix "fixtures/mutation-tier/cases.json in a harbor checkout (HARBOR_SCOPE_ROOT names it)"
  log_end || :; exit 1
fi

SB="$(mktemp -d "${TMPDIR:-/tmp}/harbor.XXXXXX")"; trap 'rm -rf "$SB"' EXIT INT TERM
mkdir -p "$SB/cfg/bin"
for _g in library-admission.sh admission-self-edit.sh; do
  [ -f "$ROOT/bin/$_g" ] && cp "$ROOT/bin/$_g" "$SB/cfg/bin/$_g"
done
printf '{"permissions":{"allow":[],"deny":[]}}\n' > "$SB/cfg/settings.json"

log_note "fixture: $FIX"
log_note "deny read from: $CFG/settings.json"
printf '%-46s %-5s %-7s %-6s %s\n' PATH TIER GUARD DENY NOTE
_gaps=0; _gapl=''
while IFS='	' read -r _fp _ft; do
  [ -n "$_fp" ] || continue
  _g="$(guard_blocks "$SB/cfg/$_fp" "$SB/cfg")"
  _d="$(deny_covers "$_fp" "$CFG")"
  _note=""
  # A tier 0/1 path with only ONE layer is the finding: deny is evaluated before hooks and cannot be swallowed, while admission-self-edit.sh is
  # FAIL-OPEN on a parse error.
  if [ "$_ft" -le 1 ]; then
    if [ "$_g" = "no" ] && [ "$_d" = "yes" ]; then
      _note="guard does not cover it — deny only"; _gaps=$((_gaps+1))
    elif [ "$_g" = "yes" ] && [ "$_d" = "no" ]; then
      _note="NO DENY BACKSTOP — the fail-open guard is the only layer"; _gaps=$((_gaps+1))
    elif [ "$_g" = "no" ] && [ "$_d" = "no" ]; then
      _note="UNPROTECTED at tier $_ft"; _gaps=$((_gaps+1))
    fi
  fi
  printf '%-46s %-5s %-7s %-6s %s\n' "$_fp" "$_ft" "$_g" "$_d" "$_note"
  [ -z "$_note" ] || _gapl="$_gapl$_fp (tier $_ft): $_note
"
done <<EOF
$(jq -r '.cases[] | [.path, (.tier|tostring)] | @tsv' "$FIX")
EOF

# One WARN per single-layer path, after the table: each is a finding, and the report never repairs it.
while IFS= read -r _gl; do
  [ -n "$_gl" ] || continue
  log_warn "$_gl"
  log_nofix "harbor#44 (deny entries: bin/admission-deny.sh; guard globs: bin/admission-self-edit.sh) — this report never repairs"
done <<EOF
$_gapl
EOF
log_note "single-layer or unprotected tier-0/1 paths: $_gaps"
log_note "it reports and never repairs: every path above is one admission-self-edit.sh protects, so a version that could close these could also open them"
log_end; exit $?
