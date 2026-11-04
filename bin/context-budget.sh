#!/usr/bin/env sh
# context-budget.sh — measure what Harbor costs EVERY session.
# harbor#5 / M3, method from upstream `BudgetCheck` @ a4e8e74 (docs/reference/provenance.md).
#   sh bin/context-budget.sh            the full report, every always-on row
#   sh bin/context-budget.sh --check    fail if the DELIBERATE surface has moved
#                                       off the last row of registries/context-baseline.tsv
#   sh bin/context-budget.sh --record   append today's figure + instrument id; you write the why
#   sh bin/context-budget.sh --ratchet  deploy gate: fail when the CORE surface (policy/constitution.md + tracked ambient
#                                       skill descriptions, read from this checkout only) exceeds registries/context-ratchet.tsv
#   sh bin/context-budget.sh --check --kind   also print kind=<match|grew|shrank|instrument-changed|
#                                       no-baseline|unreadable|malformed> last on stdout: X3's subject (harbor#585)
# (the --help extractor stops at the first blank comment line, so the usage block
#  sits above it rather than after — S4 is satisfied by what it PRINTS, not by
#  what the header contains.)
#
# The verdict is a recorded prior measurement, not a ceiling (harbor#183): regrowth of always-on context is the concern, and regrowth needs a prior number, not an invented absolute.
# Every byte here is spent before the user's first word, in every session.
# Removed notes: docs/explanation/code-cases/bin-context-budget.md
set -eu

# --help BEFORE ANY WORK (S4, harbor#140): the first executable line, because a script that treats the flag as work makes a --help sweep run for minutes. The text is the header, read at runtime.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
MODE=report; KIND=0
case "${1:-}" in
  --check)  MODE=check
            case "${2:-}" in
              --kind) KIND=1 ;;
              '')     ;;
              *)      printf 'context-budget: unknown flag %s after --check (try --help)\n' "$2" >&2; exit 2 ;;
            esac ;;
  --record) MODE=record ;;
  --ratchet) MODE=ratchet ;;
  '')       ;;
  *)        printf 'context-budget: unknown flag %s (try --help)\n' "$1" >&2; exit 2 ;;
esac

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
# The --check failures speak in the house line shape (contracts/logging.md, LOG1). stderr, as before.
# shellcheck disable=SC2034 # LOG_FD: read by library-log.sh
LOG_FD=2; . "$(dirname -- "$0")/library-log.sh"
. "$(dirname -- "$0")/library-fs.sh"   # fs_session_key: the harness's key, as memory-route.sh (harbor#966)
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# The baseline is a file, not a number (harbor#183): growth becomes a DIFF with a reason in the commit message.
# WHERE IT LIVES (harbor#1275, harbor#1149): the user's state directory, never the checkout (a harbor-core clone has no registries/context-baseline.tsv; a file at its root is one `git add -A` from a PR).
# An in-tree file is only a SEED: read while the state file is absent, copied there before the first --record.
_STATE="${HARBOR_STATUS_DIR:-${HOME:-/nonexistent}/.local/state/harbor}"
_STATE_BL="$_STATE/context-baseline.tsv"
_BL_SEED=0
if [ -n "${HARBOR_CONTEXT_BASELINE:-}" ]; then BASELINE="$HARBOR_CONTEXT_BASELINE"
elif [ -e "$_STATE_BL" ] || [ -L "$_STATE_BL" ] || [ ! -f "$ROOT/registries/context-baseline.tsv" ]; then BASELINE="$_STATE_BL"
else BASELINE="$ROOT/registries/context-baseline.tsv"; _BL_SEED=1; fi

# Ceiling in bytes. Not the verdict (harbor#183) and no longer another tool's basis (harbor#316): it sets only the percentage and the OVER/headroom line this tool prints.
# The working backpressure is --check against the baseline. 40,000 came from the 19,381 B non-index surface + 133 pointers at 150 B + ~600 B of structure; memory-store-check.sh now applies that 150-and-600 itself.
CEIL="${HARBOR_CONTEXT_CEILING:-40000}"

bytes() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

# The WHOLE `description:` value, not its first line: YAML block scalars run over many lines and a first-line read undercounts them (a plugin agent with three worked examples priced at 14 B against 2,348).
# Shared with the plugin-agent row below so both surfaces are measured by one rule.
desc_bytes() { # <file> -> bytes of the whole description: value
  [ -f "$1" ] || { echo 0; return; }
  awk '/^description:/            { inb=1; t=length($0); next }
       inb && /^[A-Za-z_-]+:/     { exit }
       inb && /^---[[:space:]]*$/ { exit }
       inb                        { t += length($0) + 1 }
       END                        { print t+0 }' "$1"
}

# ── THE DEPLOY RATCHET (--ratchet) ──
# Refuses only GROWTH past registries/context-ratchet.tsv (checked in, so a raise is a one-line edit whose commit says why). Covers only what this checkout controls: policy/constitution.md (what deploy installs as CLAUDE.md) plus ambient skill descriptions in skills/ and vendor/skills/; it reads nothing from ~/.claude, so CI and the box agree.
# Left out on purpose (a false positive gets the guard switched off): the memory index (model-authored; memory-store-check.sh bounds it), plugin and command descriptions (operator-installed) and the SessionStart injection (moves ~10 KB with the caller's directory). All three stay in the report.
if [ "$MODE" = ratchet ]; then
  RB="${HARBOR_CONTEXT_RATCHET_BASELINE:-$ROOT/registries/context-ratchet.tsv}"; RBN="${RB#$ROOT/}"
  rl="$(printf '%s\t%s\n' "$(bytes "$ROOT/policy/constitution.md")" policy/constitution.md)"
  for d in "$ROOT"/skills/*/ "$ROOT"/vendor/skills/*/; do
    f="$d/SKILL.md"; [ -f "$f" ] || continue
    grep -q '^disable-model-invocation:[[:space:]]*true' "$f" 2>/dev/null && continue
    rl="$rl
$(desc_bytes "$f")	skill description: $(basename "$d")"
  done
  now="$(printf '%s\n' "$rl" | awk -F'\t' '{ t += $1 } END { print t+0 }')"
  if [ ! -f "$RB" ]; then
    log_fail "context ratchet: no baseline file $RBN, so nothing was compared"
    log_fix "printf '%s\\t%s\\t%s\\n' $now \"\$(date +%Y-%m-%d)\" 'why' >> $RBN"
    log_end || :; exit 1
  fi
  base="$(grep -v '^#' "$RB" | grep -v '^[[:space:]]*$' | tail -1 | cut -f1)"
  case "$base" in ''|*[!0-9]*)
    log_fail "context ratchet: the last row of $RBN has no byte count in column 1 ('$base')"
    log_fix "edit $RBN: one row, <bytes><TAB><date><TAB><why>"; log_end || :; exit 1 ;; esac
  if [ "$now" -gt "$base" ]; then
    log_fail "context ratchet: the core always-on surface is $now B, over the $base B recorded in $RBN (+$(( now - base )) B); every session pays it"
    log_fix "cut the largest contributor, or raise deliberately: set the number in $RBN to $now and say why in the commit"
    printf '%s\n' "$rl" | sort -t"$(printf '\t')" -k1,1 -rn | head -5 | while IFS="$(printf '\t')" read -r _b _l; do
      log_note "top contributor: $_b B  $_l"; done
    log_end || :; exit 1
  fi
  if [ "$now" -lt "$base" ]; then
    log_ok "context ratchet: $now B, under the $base B recorded in $RBN (-$(( base - now )) B)"
    log_note "record the lower number so the saving cannot grow back: set $RBN to $now"
  else
    log_ok "context ratchet: $now B, at the $base B recorded in $RBN"
  fi
  log_end || :; exit 0
fi

# A check that prints a table is a check nobody reads in CI: --check and --record keep fd 3 for their one line and send the report to /dev/null.
exec 3>&1
[ "$MODE" = report ] || exec 1>/dev/null

total=0
printf '%-46s %8s  %s\n' SOURCE BYTES STATE
_rule='─────────────────────────────────────────────────────────────────────'; printf '%s\n' "$_rule"

row() { # <label> <bytes> <state>
  printf '%-46s %8s  %s\n' "$1" "$2" "$3"
  total=$(( total + $2 ))
}

if [ -f "$CFG/CLAUDE.md" ]; then
  row "~/.claude/CLAUDE.md" "$(bytes "$CFG/CLAUDE.md")" live
else
  row "policy/constitution.md (would become ~/.claude/CLAUDE.md)" "$(bytes "$ROOT/policy/constitution.md")" "NOT INSTALLED — projected"
fi

# ── ambient skill descriptions ──
# Only AMBIENT skills cost per session; `disable-model-invocation: true` keeps a skill out of the listing.
sk_dir="$CFG/skills"; [ -d "$sk_dir" ] || sk_dir="$ROOT/vendor/skills"
amb=0; ambn=0; invn=0
for d in "$sk_dir"/*/; do
  [ -d "$d" ] || continue
  f="$d/SKILL.md"; [ -f "$f" ] || continue
  if grep -q '^disable-model-invocation:[[:space:]]*true' "$f" 2>/dev/null; then
    invn=$(( invn + 1 )); continue
  fi
  ambn=$(( ambn + 1 ))
  amb=$(( amb + $(desc_bytes "$f") ))
done
row "ambient skill descriptions ($ambn ambient, $invn invoked-only)" "$amb" "${sk_dir#$HOME/}"

# ── plugin agent and command descriptions (harbor#316) ──
# A subagent's description is listed in EVERY session's prefix like an ambient skill's (pr-review-toolkit charged 6,360 B a session on 2026-09-20), and this file once had no row for the surface at all.
# Resolved from installed_plugins.json, never by globbing the cache (17 version directories, one loaded); only `scope: user` entries are charged.
plug=0; plugn=0
_reg="$CFG/plugins/installed_plugins.json"
if [ -f "$_reg" ]; then
  # Split on commas FIRST so the parse does not depend on the writer's formatting (a one-line JSON once read as 0, a wrong number posing as an absent surface).
  for _p in $(tr ',' '\n' < "$_reg" | awk '
      /"scope"/       { s=$0; sub(/.*"scope"[^"]*"/,"",s); sub(/".*/,"",s) }
      /"installPath"/ { p=$0; sub(/.*"installPath"[^"]*"/,"",p); sub(/".*/,"",p)
                        if (s == "user") print p }' | sort -u); do
    [ -d "$_p" ] || continue
    for _f in "$_p"/agents/*.md "$_p"/commands/*.md; do
      [ -f "$_f" ] || continue
      _d="$(desc_bytes "$_f")"
      [ "$_d" -gt 0 ] || continue
      plug=$(( plug + _d )); plugn=$(( plugn + 1 ))
    done
  done
fi
[ "$plugn" -gt 0 ] && row "plugin agent + command descriptions ($plugn)" "$plug" "installed_plugins.json, scope user"

# ── local slash-command descriptions ──
# Same listing and prefix as plugin agents, authored here; counted because it is small only because nobody has written many.
cmd=0; cmdn=0
for _c in "$CFG"/commands/*.md; do
  [ -f "$_c" ] || continue
  _d="$(desc_bytes "$_c")"
  [ "$_d" -gt 0 ] || continue
  cmd=$(( cmd + _d )); cmdn=$(( cmdn + 1 ))
done
[ "$cmdn" -gt 0 ] && row "local slash-command descriptions ($cmdn)" "$cmd" "${CFG#$HOME/}/commands"

# ── the cwd-keyed auto-memory index ──
# The largest always-on item, once unmeasured (reported 22,035 B while the true figure was 32,506 B). The key is the harness's (library-fs.sh) and there is NO walk-up: a walk-up built on a misread
# observation overcounted by 10,908 B for a session in a repo with no store. The resolved path is PRINTED so the row is falsifiable at a glance.
mem_idx="$CFG/projects/$(fs_session_key "$PWD")/memory/MEMORY.md"
mem_local=0
if [ -f "$mem_idx" ]; then
  mem_local="$(bytes "$mem_idx")"
  row "auto-memory index (cwd-keyed)" "$mem_local" "${mem_idx#$HOME/}"
else
  printf '%-46s %8s  %s\n' "auto-memory index (cwd-keyed)" 0 "no store for this cwd — not charged"
fi

# ── THE WORST CASE, NOT THE LOCAL ONE (harbor#243) ──
# The index is cwd-keyed, so lint X3 (which runs inside this checkout) measured the cheapest possible session. The VERDICT is the largest store on the box; the local row stays as the answer to what THIS session costs.
# `SPENT EVERY SESSION` keeps its exact shape, held now by this tool's own suite. Bounded on purpose: only the memory index is scanned, because a slug (`/` -> `-`) does not invert, so the worst case is a lower bound.
mem_max=0
mem_max_path=""
for _i in "$CFG"/projects/*/memory/MEMORY.md; do
  [ -f "$_i" ] || continue
  _b="$(bytes "$_i")"
  if [ "$_b" -gt "$mem_max" ]; then
    mem_max="$_b"
    mem_max_path="$_i"
  fi
done
if [ -n "$mem_max_path" ] && [ "$mem_max" -gt "$mem_local" ]; then
  printf '%-46s %8s  %s\n' "  ↳ largest store on this box (not this cwd)" "$mem_max" "${mem_max_path#$HOME/}"
fi

# ── repo-scoped surfaces, which DO load and were never counted ──
# `.claude/rules/*.md` declaring `alwaysApply: false` with `globs:` still load unconditionally (measured in a fresh headless session), so the frontmatter is inert here. Repo CLAUDE.md is injected too.
# A bare `@path` import line in the repo's own CLAUDE.md is counted (harbor#1010 PR 2, #1013, D-72; measured 2026-10-28 with one headless session): one level, a file once.
repo_amb=0; repo_n=0; imp_n=0
if [ -f "$PWD/CLAUDE.md" ]; then
  repo_amb=$(( repo_amb + $(bytes "$PWD/CLAUDE.md") )); repo_n=$(( repo_n + 1 ))
  for _imp in $(sed -n 's/^@\([A-Za-z0-9._-][A-Za-z0-9._\/-]*\)[[:space:]]*$/\1/p' "$PWD/CLAUDE.md" | sort -u); do
    case "$_imp" in */../*|../*) continue ;; esac
    [ -f "$PWD/$_imp" ] || continue
    repo_amb=$(( repo_amb + $(bytes "$PWD/$_imp") )); repo_n=$(( repo_n + 1 )); imp_n=$(( imp_n + 1 ))
  done
fi
for _r in "$PWD"/.claude/rules/*.md; do
  [ -f "$_r" ] || continue
  repo_amb=$(( repo_amb + $(bytes "$_r") )); repo_n=$(( repo_n + 1 ))
done
[ "$repo_n" -gt 0 ] && row "repo-scoped (CLAUDE.md + @imports + .claude/rules, $repo_n file(s))" "$repo_amb" "${PWD#$HOME/}"

# ── the SessionStart injection (harbor#316) ──
# Delivered into the prefix before the first word (hook_additional_context) and once uncounted (11,389 B). Ask the injector, do not re-implement its dispatch: which packs fire is decided by
# frontmatter predicates in inject-hook.sh, so this feeds it a real SessionStart payload and measures the answer (the path the session takes).
# The answer depends on the directory by ~7x ($HOME 11,804 B, inside a governed repo ~1.7 KB): the local row is what THIS session pays and the verdict takes the worst case (harbor#243).
inj_local=0; inj_max=0; inj_max_where=""
_injector="$ROOT/hooks/injection-rule/injection-rule.sh"
_inject_bytes() { # <cwd> -> bytes the SessionStart injection would deliver there
  [ -d "$1" ] || { echo 0; return; }
  # `CLAUDE_CONFIG_DIR="$CFG"` is load-bearing: inject-hook.sh reads its packs from it, so without it the probe measures the LIVE box from inside a fixture.
  ( cd "$1" 2>/dev/null || exit 0
    printf '{"hook_event_name":"SessionStart","source":"startup","session_id":"context-budget-probe","cwd":"%s"}' "$1" \
      | CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$1" sh "$_injector" 2>/dev/null | wc -c | tr -d ' ' ) 2>/dev/null || echo 0
}
# Only for the live config dir: CLAUDE_CONFIG_DIR does NOT isolate this surface (inject-hook.sh's second tier, $REPO/context-rules/<repo>, resolves under $HOME and loads the live packs
# whatever $CFG says), so a shadow-dir run would charge a fixture the real box's ~11 KB. `LIVE_DIR=` is lint D1's idiom for naming the live dir; it is only compared against $CFG, physically.
LIVE_DIR="$HOME/.claude"
_cfg_is_live=0
[ "$(cd -P -- "$CFG" 2>/dev/null && pwd -P)" = "$(cd -P -- "$LIVE_DIR" 2>/dev/null && pwd -P)" ] && _cfg_is_live=1
if [ "$_cfg_is_live" -eq 0 ]; then
  printf '%-46s %8s  %s\n' "SessionStart injection" 0 "NOT MEASURABLE — \$CLAUDE_CONFIG_DIR is not the live dir"
elif [ -f "$_injector" ] && [ "${HARBOR_CONTEXT_BUDGET_NO_PROBE:-0}" != 1 ]; then
  inj_local="$(_inject_bytes "$PWD")"; : "${inj_local:=0}"
  row "SessionStart injection (this cwd)" "$inj_local" "probed via hooks/injection-rule/injection-rule.sh"
  # The worst case is a session started where no repo governs, which carries the full hidden-skill listing.
  inj_max="$(_inject_bytes "$HOME")"; : "${inj_max:=0}"
  inj_max_where='$HOME (no repo — carries the hidden-skill index)'
  if [ "$inj_max" -le "$inj_local" ]; then inj_max="$inj_local"; inj_max_where="this cwd"; fi
  [ "$inj_max" -gt "$inj_local" ] && \
    printf '%-46s %8s  %s\n' "  ↳ largest injection on this box (not this cwd)" "$inj_max" "$inj_max_where"
else
  printf '%-46s %8s  %s\n' "SessionStart injection" 0 "NOT PROBED — no injector, or HARBOR_CONTEXT_BUDGET_NO_PROBE=1"
fi

# ── what L2 and D WILL add: projected, counted separately ──
# Not spent yet (nothing injects TELOS or IDENTITY; the telos skill loads on invocation): counting them as live pushed X3 from 96% to 133% over bytes no session pays. The ceiling binds what is SPENT; the projection is printed beside it.
proj=0
projn=0
for p in "$CFG/MEMORY/TELOS/TELOS.md" "$CFG/MEMORY/TELOS/GOALS.md" \
         "$CFG/MEMORY/TELOS/BELIEFS.md" "$CFG/IDENTITY.md" "$CFG/MEMORY/IDENTITY.md"; do
  if [ -f "$p" ]; then
    _b="$(bytes "$p")"
    printf '%-46s %8s  %s\n' "${p#$HOME/}" "$_b" "projected — nothing injects it today"
    proj=$(( proj + _b )); projn=$(( projn + 1 ))
  fi
done

# The worst case swaps THIS cwd's index for the largest on the box; where this cwd owns the largest store (or the box has none) the two are equal and the verdict says so.
# ── THE DELIBERATE SURFACE, WHICH IS THE HALF A BASELINE CAN BIND ──
# harbor#183 measured what a byte ceiling protects and found nothing (capacity, cost and dilution all refuted); the real concern is REGROWTH, which needs a prior measurement, so the gate is a recorded baseline that must match
# and changing it is a commit that says why. Only the DELIBERATE surface is baselined (CLAUDE.md, ambient skill descriptions, repo-scoped files, plugin and command descriptions: they change when somebody deploys).
# The memory index is excluded (it changes with every memory written; memory-store-check.sh owns it) and so is the injection (it moves ~10 KB with the caller's directory, so a baseline of it would report on the caller).
deliberate=$(( total - mem_local - inj_local ))

worst=$(( total - mem_local + mem_max - inj_local + inj_max ))
if [ -n "$mem_max_path" ]; then
  # Resolve the symlink or the label lies: memory-route.sh routes governed repos to the ONE $HOME silo by symlink (200 MEMORY.md files, 3 distinct inodes), so the loop's first equal-size slug named a link;
  # both maxima must read as one real directory someone starts in.
  _mm_real="$(cd -P -- "$(dirname -- "$mem_max_path")" 2>/dev/null && pwd -P)/$(basename -- "$mem_max_path")"
  worst_where="${mem_max_path#$HOME/}"
  [ "$_mm_real" != "$mem_max_path" ] && worst_where="${mem_max_path#$HOME/} -> ${_mm_real#$HOME/}"
else
  worst_where="this cwd (${PWD#$HOME/}) — no memory store on this box"
fi

# ── THE BASELINE VERDICT (harbor#183) ──
# --check fails when the DELIBERATE surface no longer matches the last recorded row; --record appends today's. Placed before the report so both modes exit having said one thing.
_bl_last=''; _bl_inst=''; _bl_bad=''
# A baseline that is there and cannot be read is not "no baseline" (review #971): --record cannot fix it.
if [ -e "$BASELINE" ] || [ -L "$BASELINE" ]; then
  if [ ! -f "$BASELINE" ]; then _bl_bad="is not a regular file"
  elif [ ! -r "$BASELINE" ]; then _bl_bad="is not readable"; fi
fi
if [ -z "$_bl_bad" ] && [ -f "$BASELINE" ]; then
  _bl_row="$(grep -v '^#' "$BASELINE" | grep -v '^[[:space:]]*$' | tail -1)"
  _bl_last="$(printf '%s' "$_bl_row" | cut -f2)"
  _bl_inst="$(printf '%s' "$_bl_row" | cut -f4)"
fi
# INSTRUMENT IDENTITY (harbor#585): a byte count means nothing without the ruler. Identity = the surface set counted into `deliberate` + a digest of the two measuring functions, so a scope change and a method change both change it.
_surf="$( [ -f "$CFG/CLAUDE.md" ] && printf claude-md || printf constitution-projected )+skills"
[ "$plugn" -gt 0 ] && _surf="$_surf+plugins"
[ "$cmdn" -gt 0 ] && _surf="$_surf+commands"
[ "$repo_n" -gt 0 ] && _surf="$_surf+repo"
[ "$imp_n" -gt 0 ] && _surf="$_surf+imports"
_digest="$( { grep '^bytes()' "$0"; sed -n '/^desc_bytes()/,/^}/p' "$0"; } | cksum | cut -d' ' -f1 )"
INSTRUMENT="$_surf@$_digest"
case "$MODE" in
  record)
    # The reason is NOT generated: a why written by this script would be the machine restating the number beside it. It writes an obviously unfinished placeholder.
    if [ "$_BL_SEED" = 1 ]; then
      # Migration: the first record moves the history to the state directory and appends there.
      mkdir -p "$_STATE" && cp "$BASELINE" "$_STATE_BL" && BASELINE="$_STATE_BL" || { echo "context-budget: could not seed $_STATE_BL" >&2; exit 1; }
    fi
    mkdir -p "${BASELINE%/*}"
    printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d)" "$deliberate" \
      "REPLACE THIS with why the surface changed" "$INSTRUMENT" >> "$BASELINE"
    printf 'recorded %s B in %s — now write the reason in that row.\n' \
      "$deliberate" "${BASELINE#$ROOT/}" >&3
    exit 0 ;;
  check)
    # The kind is the finding's subject, not its message (harbor#585, contracts/finding.md): accepting an instrument change must not silence regrowth. Printed only under --kind, last, on its own line.
    kind() { [ "$KIND" = 0 ] || printf 'kind=%s\n' "$1" >&3; }
    if [ -n "$_bl_bad" ]; then
      log_fail "context-budget: the baseline ${BASELINE#$ROOT/} $_bl_bad, so nothing was compared"
      log_fix "ls -l ${BASELINE#$ROOT/}   # restore it from the in-tree seed: cp registries/context-baseline.tsv ${_STATE_BL}"
      log_end || :
      kind unreadable; exit 1
    fi
    if [ -z "$_bl_last" ]; then
      log_fail "context-budget: no baseline recorded in ${BASELINE#$ROOT/}"
      log_fix "sh bin/context-budget.sh --record"
      log_end || :
      kind no-baseline; exit 1
    fi
    # A byte count that is not an integer makes -eq and -gt error out, and the fall-through once read
    # it as `shrank`, the kind most likely to be accepted as harmless (review #971).
    case "$_bl_last" in
      *[!0-9]*)
        log_fail "context-budget: the last row of ${BASELINE#$ROOT/} records '$_bl_last', not a byte count; nothing was compared"
        log_fix "sh bin/context-budget.sh --record   # then write the reason, and say the previous row was malformed"
        log_end || :
        kind malformed; exit 1 ;;
    esac
    if [ "$INSTRUMENT" != "$_bl_inst" ]; then
      # Not a delta: two numbers from two rulers have no difference to print.
      log_fail "INSTRUMENT CHANGED: last row measured with ${_bl_inst:-no instrument recorded}, this run with $INSTRUMENT; refusing to compare $_bl_last B with $deliberate B"
      log_fix "sh bin/context-budget.sh --record   # then state the split, instrument vs regrowth, in the row"
      log_end || :
      kind instrument-changed; exit 1
    fi
    if [ "$deliberate" -eq "$_bl_last" ]; then
      printf 'the deliberate always-on surface is %s B, matching the recorded baseline.\n' "$deliberate" >&3
      kind match; exit 0
    fi
    log_fail "DELIBERATE SURFACE MOVED: $_bl_last B recorded, $deliberate B measured ($( [ "$deliberate" -gt "$_bl_last" ] && printf '+' )$(( deliberate - _bl_last )) B). Every session pays this."
    log_fix "sh bin/context-budget.sh --record   # and write the reason in the row"
    log_end || :
    if [ "$deliberate" -gt "$_bl_last" ]; then kind grew; elif [ "$deliberate" -lt "$_bl_last" ]; then kind shrank; fi
    exit 1 ;;
esac

printf '%s\n' "$_rule"
printf '%-46s %8s  %s\n' "DELIBERATE SURFACE (baselined)" "$deliberate" \
  "$( [ -n "$_bl_last" ] && printf 'recorded %s' "$_bl_last" || printf 'no baseline recorded' )"
# The `ceiling <n>` token is an INTERFACE: memory-store-check.sh seds this exact line. The annotation goes AFTER the number, where its trailing `.*` absorbs it.
printf '%-46s %8s  ceiling %s — an allowance basis, NOT a surface bound (harbor#183)\n' \
  "SPENT EVERY SESSION" "$total" "$CEIL"
printf '%-46s %8s  %s\n' "WORST CASE (largest store, any cwd)" "$worst" "$worst_where"
# No row for the index allowance (harbor#316): memory-store-check.sh derives its own (pointers x 150 + 600), so a row describing another tool's formula would be a stale copy.
[ "$projn" -gt 0 ] && printf '%-46s %8s  %s\n' "PROJECTED if D lands (memory injection)" "$(( worst + proj ))" "$projn file(s)"
printf '\n'

# The verdict is the WORST CASE (harbor#243): $total depended on the invoking directory, and lint X3 runs from the cheapest one.
pct=$(( worst * 100 / CEIL ))
lpct=$(( total * 100 / CEIL ))
if [ "$worst" -gt "$CEIL" ]; then
  echo "OVER by $(( worst - CEIL )) bytes (${pct}% of ceiling) in: $worst_where"
  [ "$worst" -ne "$total" ] && echo "This cwd costs $total (${lpct}%); the verdict is the worst case, not the local one."
  echo "Trim, or raise HARBOR_CONTEXT_CEILING deliberately and say why in the commit."
  exit 1
fi
echo "${pct}% of ceiling, $(( CEIL - worst )) bytes of headroom, worst case in: $worst_where"
[ "$worst" -ne "$total" ] && echo "This cwd costs $total (${lpct}%)."
if [ "$projn" -gt 0 ]; then
  ppct=$(( (worst + proj) * 100 / CEIL ))
  echo "Projected ${ppct}% once memory injection lands — that is the wall upstream"
  echo "built this ceiling for, and $projn file(s) are already written and waiting."
  [ "$ppct" -gt 100 ] && echo "The projection is ALREADY over. Decide before D lands, not after."
fi
if [ "$pct" -gt 75 ]; then
  echo "Above 75% on the SPENT line alone, before injection."
fi
exit 0
