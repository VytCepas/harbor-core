#!/usr/bin/env sh
# M10 · MutationTier (harbor#44) — classify a path under a Helm config dir by what
# writing to it lets an agent DO to the floor.
#
#   sh admission-mutation-tier.sh <path>...        one line per path: tier, guard, deny
#   sh admission-mutation-tier.sh --json <path>...
#   sh admission-mutation-tier.sh --report [--live | <config-dir>]
#
# WHY A TIER AND NOT A BOOLEAN. `admission-self-edit.sh` answers protected / not
# protected, which is the right shape for a veto and the wrong shape for a
# question like "may a rule be strict about settings.json and relaxed about a
# cache". Tiers are that second question, and they are what a later rule would
# read. Nothing reads them yet, deliberately — see below.
#
# IT CHANGES NO GUARD BEHAVIOUR, AND IT IS NOT INERT EITHER. A tier table nothing
# reads is a wish (policy/constitution.md). What makes this one load-bearing without
# moving a B6 hash-pinned surface is `tests/admission/mutation-tier/mutation-tier.test.sh`: it fires the REAL
# admission-self-edit.sh at every fixture path and re-reads the whole permissions.deny
# array, so the table and the surface cannot drift apart. A divergence fails CI.
#
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): one predicate plus two
# renderers over one fixture. Splitting the classifier from the reporter would put
# two spellings of the tier globs in two files, and the globs are the whole rule.
#
# READ-ONLY. It writes nothing anywhere, in any mode. The classifier prints data; the report's own
# lines are log-lib's (contracts/logging.md, harbor#771), and its table stays data between them.
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

ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}}"
FIX="$ROOT/fixtures/mutation-tier/cases.json"
[ -n "$DIR" ] || { [ "$LIVE_OK" -eq 1 ] && DIR="$LIVE_DIR"; }
CFG="${DIR:-${CLAUDE_CONFIG_DIR:-$LIVE_DIR}}"

# TRAILING SLASHES ARE STRIPPED (PR #126 review). `rel_of()` matches the prefix
# `"$CFG"/*`, so a config dir spelled `~/.claude/` made the boundary a DOUBLE
# slash: `$CFG/settings.json` no longer matched, and the classifier reported
# `outside` — silently stopping judging every path — for one of the commonest
# spellings, and for `CLAUDE_CONFIG_DIR` values that legitimately carry one. The
# rest of the floor normalises trailing slashes, so a reader that does not is the
# odd one out. `/` itself is left alone rather than reduced to the empty string.
while [ "$CFG" != "/" ] && [ "${CFG%/}" != "$CFG" ]; do CFG="${CFG%/}"; done

# ── THE PREDICATE ────────────────────────────────────────────────────────────
# Matched against the path RELATIVE to the config dir, lowercased, because APFS is
# case-insensitive by default: `Settings.json` reaches the same inode, and a
# case-sensitive POSIX glob would call it tier 3. That exact one-character bypass
# was found against admission-self-edit.sh in red-team pass 2, so this reader must not
# reintroduce it.
#
# ORDER IS THE RULE. `bin/*` is tier 1 while `bin/` under a pins directory is not a
# thing — but `.helm-pins/*` must be tested before any broader glob, or a pin file
# with a `.sh` name would classify as code. Most specific first, always.
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

# rel_of <path> — the path relative to $CFG, or the path itself when outside it.
# Physical resolution is NOT attempted here: this is a classifier over a NAME, and
# a name is all a caller may have (a path that does not exist yet still has a
# tier). admission-self-edit.sh resolves physically before deciding, which is correct
# for a veto and is a different job.
# A PATH OUTSIDE THE CONFIG DIR IS NOT TIER 3, IT IS UNJUDGED — and conflating the
# two was a real defect in the first draft. Everything unmatched fell through to
# tier 3 ("ordinary, session-writable by design"), so asking about
# /etc/passwd or a path under a DIFFERENT config dir returned a reassuring
# "tier 3" about a file this classifier knows nothing about. A caller acting on
# that would relax a rule over an unexamined path. It now says `outside`.
# BOTH SIDES ARE NORMALISED, and trimming only `CFG` was a regression (PR #128
# review). With a config dir spelled `/tmp/cfg/`, callers build the target the usual
# way as `$CFG/settings.json`, i.e. `/tmp/cfg//settings.json`. Trimming CFG to
# `/tmp/cfg` then strips the prefix `/tmp/cfg/` and leaves `/settings.json` — with a
# leading slash — which matches no tier glob and fell through to tier 3. The version
# BEFORE the trailing-slash fix classified that exact shell-built path correctly, so
# fixing one spelling had broken another.
#
# Leading separators are therefore dropped after prefix removal. Interior doubles
# need no handling: `bin//admission-bash.sh` still matches the `bin/*` glob.
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
# guard_blocks fires the REAL guard, in a sandbox config dir, because asking a
# case glob whether the guard would block is asking a copy of the guard.
guard_blocks() { # <abs-path> <sandbox-cfg> -> yes|no|unknown
  # `-r`, NOT `-x`: the guard is invoked as `sh <file>`, so readability is what
  # matters and the repo copies are 0644. Testing for the exec bit reported
  # `unknown` for every path — a whole column of "could not tell" that read as if
  # the probe had run.
  [ -r "$2/bin/admission-self-edit.sh" ] || { printf 'unknown'; return 0; }
  # THE PARENT DIRECTORY MUST EXIST, and leaving it out was a false-positive
  # factory. guard-selfedit resolves the target PHYSICALLY (floor_norm_path) before
  # matching, and an unresolvable path keeps a spelling the protected globs miss —
  # so `.helm-pins/x` and `hooks/h.sh` both reported "not protected" against a
  # sandbox that had no such directories, and the report printed "UNPROTECTED at
  # tier 1" for a path the guard demonstrably blocks. A probe that does not
  # reproduce the real tree measures the probe (§2.6).
  mkdir -p "$(dirname -- "$1")" 2>/dev/null || :
  _rc=0
  printf '{"tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" \
    | CLAUDE_CONFIG_DIR="$2" sh "$2/bin/admission-self-edit.sh" >/dev/null 2>&1 || _rc=$?
  [ "$_rc" = "2" ] && printf 'yes' || printf 'no'
}

# deny_covers reads the WHOLE array and matches the entry's glob against the path,
# rather than grepping settings.json for a substring — a deny entry naming a
# neighbouring path would otherwise read as coverage.
deny_covers() { # <relative-path> <config-dir> -> yes|no|unknown
  command -v jq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  [ -f "$2/settings.json" ] || { printf 'unknown'; return 0; }
  # `**` crosses directory separators, a single `*` does not. Translated through a
  # DOT ESCAPING IS ONE BACKSLASH, NOT TWO. `"\\\\."` is the jq string `\\.`, which as a
  # regex means "a literal backslash then any character" — so `settings.json` compiled
  # to `settings\\.json` and matched NOTHING, and every path reported deny=no. The
  # discriminating check is that `settings.json` matches while `settingsXjson` does
  # not, i.e. the dot stayed literal instead of becoming a wildcard.
  # PRINTABLE placeholder, and the reason is worth keeping: the first version used a
  # literal NUL, which worked correctly and made the whole script read as "binary
  # data" to this box's ugrep-backed grep. Lint D1 then reported a hardcoded live
  # config dir that does not appear in the file at all, because its pipeline saw
  # "Binary file matches" as a hit. A working trick that breaks the tools reading
  # the file is not a working trick.
  # placeholder rather than a lookbehind: `**` -> DBLSTAR -> `.*`, and any
  # remaining `*` -> `[^/]*`. A lookbehind works in jq's Oniguruma but is the kind
  # of cleverness that fails silently on a jq built without it.
  _hit="$(jq -r --arg p "$1" '
      def glob2re:
        gsub("\\."; "\\.")
        | gsub("\\*\\*"; "@@DS@@")
        | gsub("\\*"; "[^/]*")
        | gsub("@@DS@@"; ".*");
      [ .permissions.deny[]? | select(type == "string") | select(startswith("Edit(~/.claude/")) ]
    | map(sub("^Edit\\(~/\\.claude/"; "") | sub("\\)$"; ""))
      # BIND THE ENTRY FIRST. `$p | test("^" + (. | glob2re) + "$")` rebinds `.` to
      # $p for the whole pipeline INCLUDING the argument, so every entry compiled
      # the PATH as its own pattern and matched itself — the report claimed every
      # path was deny-covered, `cache/x` included. Measured, not theorised.
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
# The product of this ticket: where the two enforcement layers DISAGREE about one
# path. Neither layer can see the other, and nothing until now compared them.
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
  # A tier 0 or 1 path with only ONE layer behind it is the finding. Deny is
  # un-swallowable and evaluated before hooks; guard-selfedit is documented
  # FAIL-OPEN on a parse error. So each missing layer costs something different,
  # and the note says which.
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
  log_nofix "harbor#44 (deny entries: bin/floor-deny.sh; guard globs: bin/admission-self-edit.sh) — this report never repairs"
done <<EOF
$_gapl
EOF
log_note "single-layer or unprotected tier-0/1 paths: $_gaps"
log_note "it reports and never repairs: every path above is one admission-self-edit.sh protects, so a version that could close these could also open them"
log_end; exit $?
