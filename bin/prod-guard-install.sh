#!/usr/bin/env sh
# B10 (harbor#56) — install prod_guard AMBIENTLY, which nothing currently does.
#   sh prod-guard-install.sh [--apply] (--live | --dir PATH)   DRY RUN unless --apply; backup-first
#     --live is the only way to target ~/.claude. PROJECT_INIT_SRC names the yard checkout.
#
# WHY. yard's prod_guard.py owns the cloud/data destruction corpus by
# contract (bin/admission-bash.sh:6-8 — the floor's Bash guard omits that class on
# the understanding that this guard covers it). Measured machine-wide
# (harbor#56): the number of settings files that wire prod_guard is ZERO. The
# template wires it (templates/base/dot_agents/settings.json.tmpl:61); no
# rendered repo on this box does. So every gcloud/bq/gsutil/terraform/kubectl
# call has run with no guard from either layer, and the contract's
# complementarity was one-sided in practice. This is the wiring that makes it
# true.
#
# WHAT IT INSTALLS, AND WHY IT COPIES RATHER THAN POINTS AT bin/:
#   $DIR/hooks/prod_guard.py         ← byte copy of the AUTHORITATIVE prod_guard
#                                      (source repo preferred over the mirror —
#                                      see the source-selection note below)
#   $DIR/bin/prod-guard-ambient.sh   ← the deferral shim
# A hook wired at a git working tree changes meaning on `git checkout`, which
# would make the global guard depend on which branch happens to be out. Both
# copies land in the config dir, the same reasoning deploy-runtime-install.sh uses.
#
# IT WIRES ONE PreToolUse HOOK, which admission-install.sh's gate does not cover and
# should not: eval-pass-score.sh blocks the FLOOR (six guards, exit-2 vetoes). This is
# one `ask`-posture guard whose corpus the floor deliberately excludes, and
# harbor#56 argues at length why it is not a floor guard. Its blast radius is a
# prompt on ~0.4% of Bash calls (46 of 11,505 historical).
set -eu
SRC="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init prod-guard-install
il_parse "$@"
il_target
DIR="$IL_TARGET"
if [ "$IL_APPLY" -eq 1 ]; then log_head "apply to $DIR"; else log_head "plan for $DIR (dry run: nothing is written)"; fi
command -v jq >/dev/null 2>&1 || { log_fail "jq is required"; log_fix "$(pkg_hint jq)"; log_end; exit 1; }

# SOURCE SELECTION IS A SECURITY DECISION, not a path convenience.
#
# The first version of this installer copied from the marketplace clone, and that
# clone is a MIRROR that goes stale silently. Measured: its HEAD is c2b81b1
# (2026-07-13, release 1.1.7) while the PI-903 symlink refusal landed upstream in
# ac85947 (2026-07-26, yard#904). All three installed plugin copies —
# marketplace, its templates, and the 0.8.0 cache — are 266 lines with ZERO
# `is_symlink` occurrences. So this installer would have deployed, ambiently and
# machine-wide, exactly the version a planted symlink defeats: `.agents` pointing
# anywhere supplies its own `safety.allow` and switches the destructive-command
# deny table off wholesale.
#
# The fix exists upstream and reaches nothing, because the distribution channel
# between them is stale. Preferring the source repo when it is present is the
# only ordering that cannot install a known-vulnerable guard.
PI_SRC="${PROJECT_INIT_SRC:-$(sh "$SRC/scope-roots.sh" --get HARBOR_SCOPE_SCAFFOLDER)}/templates/base/dot_agents/hooks/prod_guard.py"
# The mirror is the TARGET's own marketplace clone, never one CLAUDE_CONFIG_DIR points at.
# yard's marketplace and plugin names are its interface, read from contracts/scaffolder-plugins.tsv (harbor#999).
_spl() { awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$SRC/../contracts/scaffolder-plugins.tsv" 2>/dev/null; }
PI_MKT="$(_spl marketplace)"; PI_WF="$(_spl workflow)"
[ -n "$PI_MKT" ] && [ -n "$PI_WF" ] || { log_fail "no yard plugin names at $SRC/../contracts/scaffolder-plugins.tsv"
  log_nofix "harbor#999: the marketplace and workflow rows name yard's plugin"; log_end; exit 1; }
PLUGIN_MIRROR="$DIR/plugins/marketplaces/$PI_MKT/plugins/$PI_WF/hooks/prod_guard.py"
if [ -f "$PI_SRC" ]; then PLUGIN="$PI_SRC"; SRC_KIND="upstream source repo"
else PLUGIN="$PLUGIN_MIRROR"; SRC_KIND="marketplace mirror (source repo absent)"; fi
S="$DIR/settings.json"
if [ ! -f "$S" ]; then
  log_fail "no settings.json at $S"
  log_nofix "harbor#56: prod-guard-install wires an existing Claude Code config dir"
  log_end; exit 1
fi
if [ ! -f "$PLUGIN" ]; then
  log_fail "no prod_guard.py at $PLUGIN"
  log_nofix "harbor#56: prod_guard.py comes from a yard checkout (PROJECT_INIT_SRC, else the registry's yard checkout)"
  log_end; exit 1
fi
log_note "source: $PLUGIN ($SRC_KIND)"

# REFUSE TO INSTALL A GUARD THAT A SYMLINK DEFEATS. This is not a style check on
# the source: `_find_config` locates the file `safety.allow` is read from, so a
# copy without the refusal lets an allowlist planted outside the repo disable the
# whole deny table. Installing that ambiently would spread the bypass to every
# directory on the machine rather than close it — worse than not installing.
# Asserted on the CONTENT of whatever copy was selected, so it holds no matter
# which source won above or how the channel drifts later.
if ! grep -q 'is_symlink' "$PLUGIN"; then
  il_refuse "the selected prod_guard.py has no symlink refusal (PI-903): a planted .agents symlink would supply its own safety.allow and disable the deny table" \
    "none automatic — see yard#904 (ac85947); fix the source, then: $(il_cmd --apply)"
fi

# Verified at install time so the runtime never has to: the shim's own
# python3-missing path exists for a machine that breaks LATER, not for this one.
if ! command -v python3 >/dev/null 2>&1; then
  il_refuse "python3 is not on PATH, and the shim runs prod_guard.py with it" "$(pkg_hint python3)"
fi

G_DST="$DIR/hooks/prod_guard.py"
S_DST="$DIR/bin/prod-guard-ambient.sh"
CMD="/bin/sh $S_DST $G_DST"

# Wired as floor-install wires its vetoes, onFailure included: a prod_guard that times out otherwise lets
# the call through (harbor#1277). A hook already wired gains the key.
ONFAIL="$(il_onfailure)"
NEW="$(il_merge_hook "$S" PreToolUse "Bash" "$CMD" "$ONFAIL")"

if [ "$IL_APPLY" -eq 0 ]; then
  log_note "guard: would copy $PLUGIN to $G_DST"
  log_note "shim: would copy $SRC/prod-guard-ambient.sh to $S_DST"
fi
# Name the channel's staleness rather than let it pass silently: it is the defect
# that made the refusal above necessary, and it is invisible from here otherwise.
# This installer is now safe from it; anything SCAFFOLDED from the mirror is not.
if [ -f "$PI_SRC" ] && [ -f "$PLUGIN_MIRROR" ] && ! cmp -s "$PI_SRC" "$PLUGIN_MIRROR"; then
  log_warn "the marketplace mirror differs from the source repo, so a plugin update would install a stale guard — anything SCAFFOLDED from it is still vulnerable"
  log_nofix "yard#904: update the yard marketplace plugin"
fi
# The mirror is what an update WOULD install; the copy Claude Code loads is the installed one, and a
# current mirror over a stale install read green (harbor#925). One line per install path.
INSTALLED="$DIR/plugins/installed_plugins.json"
if [ -f "$PI_SRC" ] && [ -f "$INSTALLED" ]; then
  # Fields split on \037, never a tab: IFS merges empty tab fields, and @tsv escapes a tab in a path
  # (review #932). Every field is non-empty, and an entry with no installPath names nothing to compare.
  _ins="$(jq -r --arg id "$PI_WF@$PI_MKT" 'def f: if . == null or . == "" then "?" else tostring end;
      [.plugins[$id][]? | select((.installPath // "") != "")]
      | group_by(.installPath)[]
      | [(.[0].installPath | tostring), (.[0].version | f), ([.[] | "\(.scope | f):\(.projectPath // "-")"] | join(", "))]
      | join("\u001f")' "$INSTALLED" 2>/dev/null)" \
    || { _ins=""; log_warn "could not read $INSTALLED, so the installed plugin was not compared with the source repo"; }
  _us="$(printf '\037')"
  while IFS="$_us" read -r _ip _iv _iw; do
    [ -n "$_ip" ] || continue
    if [ -f "$_ip/hooks/prod_guard.py" ] && cmp -s "$PI_SRC" "$_ip/hooks/prod_guard.py"; then
      log_ok "installed $PI_WF $_iv matches the source repo ($_iw)"; continue
    fi
    if [ -f "$_ip/hooks/prod_guard.py" ]; then _how="differs from the source repo"; else _how="has no hooks/prod_guard.py at $_ip"; fi
    log_warn "the INSTALLED $PI_WF $_iv $_how, and it is the copy Claude Code loads ($_iw)"
    log_fix "claude plugin update $PI_WF@$PI_MKT --scope <scope>, run in each project named; a project path that no longer exists is harbor#709"
  done <<EOF
$_ins
EOF
fi
if [ "$(jq -r --arg c "$CMD" '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]?.command] | index($c) != null' "$S")" = true ]; then
  if [ -z "$ONFAIL" ] || [ "$(jq -r --arg c "$CMD" '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.command == $c) | .onFailure // ""] | first' "$S")" = "$ONFAIL" ]; then
    log_ok "PreToolUse Bash: $CMD already wired"
  else
    log_note "PreToolUse Bash: $CMD is wired; would set onFailure $ONFAIL on it"
  fi
else
  log_note "PreToolUse Bash: would wire $CMD"
fi

il_stop
if [ "$IL_APPLY" -eq 0 ]; then
  [ "$IL_REFUSED" -eq 1 ] || il_apply_next prod-guard
  log_end; exit $?
fi

# Backups beside the run's log (never settings.json.bak.* in the config root).
{ il_backup "$S" && il_backup "$G_DST" && il_backup "$S_DST"; } || { log_end; exit 1; }
mkdir -p "$DIR/hooks" "$DIR/bin"
if ! { cp "$PLUGIN" "$G_DST.tmp.$$" && mv -f "$G_DST.tmp.$$" "$G_DST" \
       && cp "$SRC/prod-guard-ambient.sh" "$S_DST.tmp.$$" && chmod 0755 "$S_DST.tmp.$$" && mv -f "$S_DST.tmp.$$" "$S_DST"; }; then
  rm -f "$G_DST.tmp.$$" "$S_DST.tmp.$$"
  log_fail "could not install $G_DST or $S_DST"
  log_nofix "the cp/mv error above; the previous copies are in $IL_BK"
  log_end; exit 1
fi
log_ok "guard: copied $PLUGIN to $G_DST"
log_ok "shim: copied $SRC/prod-guard-ambient.sh to $S_DST"
# Their rows in the install manifest (install standard §3), each with its own source's commit: the guard
# comes from yard (or the marketplace mirror), the shim from this checkout.
il_source "$(dirname -- "$PLUGIN")"; il_manifest hooks/prod_guard.py
il_source "$SRC/.."; il_manifest bin/prod-guard-ambient.sh
il_manifest_write || { log_end; exit 1; }
il_write_json "$NEW" "$S" || { log_end; exit 1; }
log_ok "settings.json: PreToolUse Bash wired to the shim"
log_note "backup: $IL_BK"

# RE-PIN, for the reason deploy-runtime-install.sh:139 gives and this installer originally
# missed: it just wrote settings.json, so the teeth pin is stale BY OUR OWN HAND.
# Leaving it would hand the operator a drift alarm caused by the tool that told them
# to run it — the statusline flips floor✓ → floor DRIFT — and would make B6, once
# installed, block every session. A false alarm is a defect, not caution (§2.11).
# --repin adds no deny entry, so a withdrawn entry stays withdrawn.
if [ -f "$DIR/.helm-floor-teeth" ] || [ -f "$DIR/.sec0-baseline.sha256" ]; then
  # floor-deny takes this run's own target, --live or --dir (the install standard, harbor#800).
  if il_run sh "$SRC/admission-deny.sh" --repin >/dev/null 2>&1; then
    log_ok "re-pinned: teeth + sec0 baseline now match the settings.json just written"
  else
    log_fail "admission-deny.sh could not re-pin the teeth and sec0 baseline for $DIR"
    log_fix "sh $SRC/admission-deny.sh --repin $(il_spell)"
  fi
fi

# Prove the installed pair actually answers, rather than asserting it did.
PAY='{"session_id":"install-verify","cwd":"/","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"gcloud sql instances delete prod-db"}}'
OUT="$(printf '%s' "$PAY" | /bin/sh "$S_DST" "$G_DST" 2>&1 || true)"
case "$OUT" in
  *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*) _asks=1 ;;
  *) _asks=0 ;;
esac
if [ "$_asks" -eq 1 ]; then
  log_ok "verified: a destructive gcloud command now returns ask"
else
  log_fail "the installed pair did not ask for a destructive gcloud command; it printed: $(printf '%s' "$OUT" | cut -c1-200)"
  log_nofix "harbor#56; the previous install is in $IL_BK"
fi
log_end; exit $?
