#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# B3 (harbor#3) - PreToolUse(Bash) shell-injection / local-exec guard: the code-execution and destruction class (ports upstream DANGEROUS_PATTERNS a4e8e74, trimmed for POSIX+WSL). Pure POSIX; FAIL-OPEN on parse error.
# LINUX (harbor#618): osascript, plutil and ditto are macOS tools named so they are REFUSED; their Linux forms are in the same lists.
# Blocking (exit 2): the floor is a hard veto. The anti-evasion pre-pass (floor_bash_targets) neutralizes single-quote-data false positives and executed-quoted-arg false negatives (issue #732).
# DELIBERATELY ONE FILE (docs/explanation/modularity.md): lint F1 needs the kill-switch as the first live line of a guard, B6 pins this file's hash, and a fork per rule once turned SessionStart into a fail-OPEN bypass (DE-09).
# B5 narrowing: CATASTROPHIC shapes fire everywhere; PROJECT-POLICY shapes (protected-branch git) are deferred only where the repo WIRES yard's github_command_guard (a marker alone is not that guard, harbor#954).
# Removed notes: docs/explanation/code-cases/bin-admission-bash.md
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin
# OBSERVE-1 needs the tool class; assigned from the same jq call the test already made (zero extra forks).
FLOOR_TOOL="$(floor_field '.tool_name')"
floor_shell_tool "$FLOOR_TOOL" || exit 0
CMD="$(floor_field '.tool_input.command')"
[ -n "$CMD" ] || exit 0
# The digest subject (harbor#41), not passed through the blocking function, so payload text never enters it.
# shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh (floor_obs_digest)
FLOOR_OBS_SUBJECT="$CMD"

# harbor#302: a document heredoc behind a pipe or a $( ) is judged by its consumer, not its body.
case "$CMD" in *'<<'*) CMD="$(floor_hd_doc_view "$CMD")" ;; esac
# P13C-2: `${HOME%/}`, `${HOME/x/x}`, `${HOME:+…}` name the home as surely as `${HOME}`; read them
# as `${HOME}` before any rule does, so every home rule sees one spelling (fails closed).
CMD="$(floor_home_param "$CMD")"
TARGETS="$(floor_bash_targets "$CMD")"
# harbor#757/#759 — an executed body (`bash -c '…'`) reaches TARGETS unexpanded and
# uncollapsed, so every line also gets its canonical spellings, beside the raw one:
# the shared collapse, now one linear pass, so a 32KB payload cannot time the hook out.
_TCN="$(floor_canon_lines "$TARGETS")"
[ -z "$_TCN" ] || TARGETS="$TARGETS
$_TCN"
# harbor#1313: an unquoted `$IFS` is whitespace to bash; the normalizer splits there, and this is the same reading for the flat half (a padded payload with no table).
# Only spellings whose value is a subset of IFS; the bare form is substituted twice because one pass misses a second `$IFS` directly beside it.
case "$CMD" in *'$IFS'*|*'${IFS'*)
  _TIF="$(printf '%s\n' "$TARGETS" | sed -E -e 's/\$\{IFS(:[0-9]+(:[0-9]+)?|[%#][%#]?[^}]*)?\}/ /g' \
    -e 's/\$IFS([^A-Za-z0-9_])/ \1/g' -e 's/\$IFS([^A-Za-z0-9_])/ \1/g' -e 's/\$IFS$/ /')"
  [ "$_TIF" = "$TARGETS" ] || TARGETS="$TARGETS
$_TIF" ;;
esac
# A heredoc, not `printf | grep`: one process per rule instead of two (harbor#264). Empty TARGETS
# returns 1 first, because grep on no input never matches but on one empty line it could.
hit() { [ -n "$TARGETS" ] || return 1; "$FLOOR_GREP" -iEq -- "$1" <<HARBOR_ADMISSION_HIT_EOF
$TARGETS
HARBOR_ADMISSION_HIT_EOF
}
# The structured table the migrated rules read (B-rewrite). Fail-open: an empty table makes floor_seg_* return "no match", never "block".
floor_seg_load "$CMD"

# harbor#89, QUOTED IS NOT EXECUTED: a command that is one INERT consumer of a heredoc (`git commit -F -`) carries a message, not code. The predicate is strict (floor_heredoc_inert_only); `sh` reading a heredoc is NOT inert and stays blocking.
# --publisher-inert (harbor#125): this guard judges execution and local writes, never publication; guard-egress does not pass the flag.
if floor_heredoc_inert_only --publisher-inert; then exit 0; fi

# floor_peel strips a leading NAME=value wrapper, so a rule that looks FOR an assignment reads the raw command (red-team pass 7).
rawhit() { printf '%s' "$CMD" | "$FLOOR_GREP" -iEq -- "$1"; }

# ── CATASTROPHIC shapes — always block ──────────────────────────────────────
# Pipe into ANY shell interpreter: the SINK is matched, because enumerating producers was evaded (xxd -r -p | sh, red-team 2026-07-24).
# A shell RUNNING A NAMED SCRIPT is not that act (harbor#222): floor_seg_shells_all_named_scripts refuses the exemption for `-s`, `-`, /dev/stdin, option-only calls and a table it could not build, so an oversized payload still blocks.
# harbor#1420: the sink may follow a brace group, a subshell paren, `!`, assignments, or a `time`/`doas`-style wrapper.
_PIPE_PRE='\|&?[[:space:]]*(\{[[:space:]]+|\(+[[:space:]]*|![[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(((/[a-zA-Z0-9_/.-]*/)?(sudo|env|command|builtin|exec|nohup|stdbuf|nice|ionice|setsid|xargs|timeout|time|doas|caffeinate|unshare|busybox))[[:space:]]+((-[^[:space:]]+|[0-9]+[smhd]?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|--)[[:space:]]+([^-][^[:space:]]*[[:space:]]+)?)*)*(((/[a-zA-Z0-9_/.-]*/)?(flock|chroot))[[:space:]]+(-[^[:space:]]+[[:space:]]+)*[^-[:space:]][^[:space:]]*[[:space:]]+)?(/[a-zA-Z0-9_/.-]*/)?'
if hit "${_PIPE_PRE}"'(sh|bash|zsh|dash|ksh|fish|ash|csh|tcsh|\$SHELL|\$\{SHELL\})([[:space:];&|)<>]|$)' \
   && ! floor_seg_shells_all_named_scripts \
   && ! floor_seg_all_inert; then  # harbor#1420: a quoted regex alternation is text, not a sink
  floor_block bash "pipe-to-shell (a pipeline's output executed as a shell script)" pipe-to-shell.flat
fi
# The shells are not the only sinks (harbor#1313): `source` and `.` with a stdin path operand, and a non-shell interpreter reading its PROGRAM from stdin (bare or `-`;
# given code or a script it reads data, harbor#607, which floor_seg_interps_all_programmed separates by argv).
if hit "${_PIPE_PRE}(source|\\.)[[:space:]]+(--[[:space:]]+)?(/+dev/+(stdin|fd/+[0-9]+)|/+proc/+(self|[0-9]+)/+fd/+[0-9]+)([[:space:];&|)<>]|\$)" \
   || { hit "${_PIPE_PRE}(python[0-9.]*|pypy[0-9.]*|perl|ruby|node|nodejs|php|lua|luajit|osascript)([[:space:];&|)<>]|\$)" \
        && ! floor_seg_interps_all_programmed && ! floor_seg_all_inert; }; then
  floor_block bash "pipe-to-shell (a pipeline's output executed as a program by a builtin or an interpreter reading stdin)" pipe-to-shell.flat
fi
# Fetch-then-execute, decoupled across the pipeline: curl -o p && sh p.
hit '(curl|wget)[^;&|]*(-o|-O|--output|>)[^;&|]*[;&|]+[[:space:]]*(sh|bash|zsh|dash|source|\.)([[:space:];&|)<>])' \
  && floor_block bash "fetch-then-execute (downloaded payload run by a shell)" fetch-then-exec.flat
# bash <(curl ...) and a shell reading its script from stdin (`sh < <(curl ...)`, red-team pass 6).
hit '(^|[^[:alnum:]_])(sh|bash|zsh|dash|source|\.)[[:space:]]+(<[[:space:]]*)?<[(<][[:space:]]*"?\$?[({]?[[:space:]]*(curl|wget|fetch)' \
  && floor_block bash "shell executing a fetched payload from a process substitution or stdin" fetch-exec-procsub.flat

# ── DEFERRED-EXECUTION SINKS ── code written where a LATER process runs is the same act time-shifted (red-team pass 6). The floor's own switches are the worst case: one append to ~/.zshrc disabled every guard.
# The shadow switch (harbor#482) is of the same class, so both rules stay enforcing in shadow (floor_shadow_enforces).
rawhit '(^|[^[:alnum:]_])(export[[:space:]]+)?(HARBOR_ADMISSION_DISABLE|HARBOR_ADMISSION_SHADOW)[[:space:]]*=' \
  && floor_block bash "assigning a floor switch (HARBOR_ADMISSION_DISABLE or HARBOR_ADMISSION_SHADOW) — both are set by the operator on the command line, never by a session" killswitch-assign.flat
# `launchctl setenv` puts a switch into every later process; the second alternative is a switch name REDIRECTED into a settings file (a settings.json env block reaches every hook).
rawhit "(>[|!&]?|>>!?|tee|sed|perl|python[0-9.]*|cat|launchctl[[:space:]]+setenv)[^;&|]*(HARBOR_ADMISSION_DISABLE|HARBOR_ADMISSION_SHADOW)|(HARBOR_ADMISSION_DISABLE|HARBOR_ADMISSION_SHADOW)[^;&|]*(>[|!&]?|>>!?)[^;&|]*settings[^;&|]*\.json" \
  && floor_block bash "persisting a floor switch into a file would disable or shadow the floor for every later session" killswitch-persist.flat
RCFILE='(\.zshrc|\.zshenv|\.zprofile|\.zlogin|\.bashrc|\.bash_profile|\.bash_login|\.profile|/etc/profile|/etc/profile\.d|/etc/paths|/etc/zsh(env|rc|profile|login)?|\.config/fish/(config\.fish|conf\.d)|\.cshrc|\.kshrc|\.ssh/(authorized_keys2?|config|rc|environment))([^.a-zA-Z0-9_-]|$)'
hit "(>[|!&]?|>>!?)[[:space:]]*[^[:space:];&|]*$RCFILE" \
  && floor_block bash "shell startup files are executed by every later session — writing one is a code-execution sink, not a file edit" startup-file-write.flat
hit "(^|[^[:alnum:]_])(cp|mv|install|rsync|ditto)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-][^[:space:];&|]*[[:space:]][^;&|]*$RCFILE" \
  && floor_block bash "a shell startup file is being overwritten (deferred code execution)" startup-file-overwrite.flat
hit "(^|[^[:alnum:]_])(tee|ln)([[:space:]]+-[^[:space:]]+)*[[:space:]][^;&|]*$RCFILE" \
  && floor_block bash "a shell startup file is being rewritten (deferred code execution)" startup-file-rewrite.flat
hit "(^|[^[:alnum:]_])dd[^;&|]*of=[^[:space:];&|]*$RCFILE" \
  && floor_block bash "dd writing a shell startup file (deferred code execution)" startup-file-dd.flat
hit "(^|[^[:alnum:]_])(sed|perl|python[0-9.]*)[^;&|]*([[:space:]]-[a-z]*i|--in-place)[^;&|]*$RCFILE" \
  && floor_block bash "in-place edit of a shell startup file (deferred code execution)" startup-file-inplace.flat
# CLAUDE CODE'S OWN API ROUTE (harbor#545, #549): claude-code-router's first run rewrites ~/.claude/settings.json to a dead proxy. The router and its installer are refused BY NAME, but only at COMMAND POSITION, as the script an interpreter or `source` runs,
# or as the package an install/exec verb takes; never a bare mention (ls, grep, git add of them stay open). Wrappers may carry a PATH and one option value; TARGETS has the leading wrapper already peeled.
# Residual, accepted: `sudo -E cat setup_models.sh` reads the reader as that option's value. admission-api-route.sh reads the settings files AFTER each call and catches what names neither.
_AR_P='([^[:space:];&|]*/)?'
_AR_ARG='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+|-[^[:space:]]*[[:space:]]+([^-[:space:];&|][^[:space:];&|]*[[:space:]]+)?)'
_AR_CMD='(^|[;&|(!]|&&|\|\|)[[:space:]]*'"$_AR_ARG"'*('"$_AR_P"'(sudo|exec|command|nohup|env|time|xargs)[[:space:]]+'"$_AR_ARG"'*)*'
hit "${_AR_CMD}${_AR_P}ccr([[:space:]]|\$)" \
  && floor_block bash "running claude-code-router (ccr): its first run rewrites Claude Code's API route, and the last time every session on this box was locked out" api-route-ccr.flat
# An install or exec verb taking the package, within ONE segment (`npm uninstall ... && npm install ...` still meets the ban); `node`/`bun` running a file inside the package is the same program.
hit "${_AR_CMD}${_AR_P}((npm|pnpm|yarn|bun)[[:space:]]+([^;&|]*[[:space:]])?(install|i|add|exec|x|dlx)|npx|bunx|pnpx)[[:space:]]+([^;&|]*[[:space:]])?[^[:space:];&|]*claude-code-router" \
  && floor_block bash "installing or running claude-code-router: its first run rewrites Claude Code's API route for every session on this box" api-route-router.flat
hit "${_AR_CMD}${_AR_P}(node|bun|deno)[[:space:]]+([^;&|]*[[:space:]])?[^[:space:];&|]*claude-code-router/" \
  && floor_block bash "running claude-code-router by path: its first run rewrites Claude Code's API route for every session on this box" api-route-router.flat
# The installer at command position, or as the script an interpreter or `source` runs.
hit "${_AR_CMD}((${_AR_P}(sh|bash|zsh|dash|ksh)|source|\\.)[[:space:]]+(-[^[:space:]]*[[:space:]]+)*)?${_AR_P}setup_models\\.sh([[:space:]]|\$)" \
  && floor_block bash "setup_models.sh installs claude-code-router and ignores --help; running it locked every session on this box out of the API" api-route-setup-models.flat
hit '(^|[^[:alnum:]_])claude[[:space:]]+config[[:space:]]+(set|add)[^;&|]*(apiKeyHelper|env|_BASE_URL|PROXY)' \
  && floor_block bash "claude config set of an API route, key helper or proxy: where Claude Code sends requests is the operator's to change" api-route-config.flat
# `gh alias set --shell` DEFINES A SHELL COMMAND THAT RUNS LATER (harbor#125): a deferred sink like an rc-file write. gh marks a shell expansion by --shell/-s, by a LEADING `!`, or by `-` (read from STDIN, so the payload never reaches the scanned command line: refused on the argument's absence).
# A `!` elsewhere in the expansion and a plain subcommand expansion (`pr checkout`) run no shell and stay allowed.
GH_ALIAS_SET='(^|[^[:alnum:]_])gh([[:space:]]+-[^[:space:]]+)*[[:space:]]+alias[[:space:]]+set([[:space:]]|$)'
hit "$GH_ALIAS_SET[^;&|]*(--shell|[[:space:]]-s([[:space:]]|$))" \
  && floor_block bash "gh alias set --shell stores a shell command that a later 'gh <alias>' executes (deferred code execution)" gh-alias-shell.flat
hit "$GH_ALIAS_SET[^;&|]*[[:space:]]('|\")?!" \
  && floor_block bash "a gh alias expansion starting with '!' is evaluated by sh exactly as --shell is, so a later 'gh <alias>' executes it (deferred code execution)" gh-alias-bang.flat
hit "$GH_ALIAS_SET[^;&|]*[[:space:]]-([[:space:]]|$)" \
  && floor_block bash "gh alias set - reads the expansion from stdin, so the shell string it stores never reaches this scanner (unreviewable deferred execution)" gh-alias-stdin.flat

# A FINDING'S DISPOSITION IS A PERSON'S (harbor#855, contracts/finding.md): lint-findings.sh accept refuses inside an agent session, but the session holds the same gh login. This hook runs only inside an agent session, so the reconcile's own finding:fixed is never refused.
# CASE-BLIND (GitHub matches labels that way, review #934); a label TOKEN, never prose; a hand CLOSE is not refused (the reconcile re-files it).
FDISP='[Ff][Ii][Nn][Dd][Ii][Nn][Gg](:|%3[Aa])([Aa][Cc][Cc][Ee][Pp][Tt][Ee][Dd]|[Ss][Uu][Pp][Ee][Rr][Ss][Ee][Dd][Ee][Dd]|[Ff][Ii][Xx][Ee][Dd])'
FTOK="^[^[:space:]]*${FDISP}([^[:alnum:]_-]|\$)|(^|,)[[:space:]]*${FDISP}[[:space:]]*(,|\$)"
GHC='^([a-zA-Z0-9_./-]*/)?gh$'
_fl_msg="a finding's disposition label is a person's act at their own terminal (sh bin/lint-findings.sh accept|supersede), never an agent's"
floor_seg_has "$GHC" '^issue$' '^(edit|create)$' "$FTOK" && floor_block bash "$_fl_msg" finding-label-issue.argv
# An alias or a renamed label is the same act one step removed (review #934); an alias is judged on its expansion naming a writing verb.
floor_seg_has "$GHC" '^alias$' '^set$' \
  "(issue[[:space:]]+(edit|create)|(^|[[:space:]])api([[:space:]]|\$)|label[[:space:]]+edit)[^;]*${FDISP}" \
  && floor_block bash "$_fl_msg" finding-label-alias.argv
floor_seg_has "$GHC" '^label$' '^edit$' "$FTOK" && floor_block bash "$_fl_msg" finding-label-rename.argv
# gh api is judged one segment at a time on the method gh will send (the LAST -X/--method wins, a field with no method is a POST, explicit GET is a query); tokens are percent-decoded first. GraphQL is not judged: its label mutations take ids (review #934).
_fl_api_write() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  printf '%s\n' "$FLOOR_SEGS" | awk -v ftok="$FTOK" '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
    function dec(s,   o, i, c, h, X) {
      o = ""; X = "0123456789abcdef"
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1); h = tolower(substr(s, i + 1, 2))
        if (c == "%" && h ~ /^[0-9a-f][0-9a-f]$/) {
          o = o sprintf("%c", (index(X, substr(h, 1, 1)) - 1) * 16 + index(X, substr(h, 2, 1)) - 1); i += 2
        } else o = o c
      }
      return o
    }
    /^SEGC:/ { s = substr($0, 6); p = index(s, ":"); id = substr(s, 1, p - 1) + 0
               c = substr(s, p + 1); sub(/.*\//, "", c); if (tolower(c) == "gh") GH[id] = 1; next }
    /^SEGA:/ { s = substr($0, 6); p = index(s, ":"); id = substr(s, 1, p - 1) + 0
               N[id]++; A[id, N[id]] = substr(s, p + 1); next }
    END {
      for (id in GH) {
        api = 0; gql = 0; m = ""; fld = 0; lab = 0
        for (i = 1; i <= N[id] + 0; i++) {
          t = A[id, i]
          if (t == "api") api = 1; else if (t == "graphql") gql = 1
          if ((t == "-X" || t == "--method") && i < N[id] + 0) m = A[id, i + 1]
          else if (t ~ /^--method=/) m = substr(t, 10)
          else if (t ~ /^-X./) m = substr(t, 3)
          if (t ~ /^(-[fF]|--field|--raw-field|--input)(=|$)/ || t ~ /^-[fF][^[:space:]]/) fld = 1
          if (dec(t) ~ ftok) lab = 1
        }
        m = toupper(m)
        if (api && !gql && lab && ((m != "" && m != "GET") || (m == "" && fld))) { print "write"; exit }
      }
    }' 2>/dev/null | "$FLOOR_GREP" -q write
}
_fl_api_write && floor_block bash "$_fl_msg" finding-label-api.argv

# THE EVENT DISPATCHER'S FOLLOWER AND ITS RULE WRITES ARE THE OPERATOR'S (harbor#1044): `dispatch` leaves a follower that outlives the session and spawns agents as the operator; `on` writes the rules it obeys.
# Refused by argv however reached (the script, `event-bus.sh dispatch|on`, `harbor event`); `on --list` and the other bus verbs stay open.
_ed_operator_verb() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  printf '%s\n' "$FLOOR_SEGS" | awk '
    /^SEGC:/ { s = substr($0, 6); p = index(s, ":"); C[substr(s, 1, p - 1)] = tolower(substr(s, p + 1)); next }
    /^SEGA:/ { s = substr($0, 6); p = index(s, ":"); id = substr(s, 1, p - 1); A[id, ++N[id]] = substr(s, p + 1); next }
    END {
      for (id in C) {
        c = C[id]; k = -1
        if (c ~ /(^|\/)event-(dispatch|bus)\.sh$/) k = 0
        else if (c ~ /(^|\/)harbor$/ && tolower(A[id, 1]) == "event") k = 1
        else if (c ~ /(^|\/)(sh|bash|dash|zsh|ksh)$/)
          for (i = 1; i <= N[id]; i++) if (tolower(A[id, i]) ~ /(^|\/)event-(dispatch|bus)\.sh$/) { k = i; break }
        if (k < 0) continue
        v = tolower(A[id, k + 1])
        if (v == "dispatch" || (v == "on" && A[id, k + 2] != "--list")) { print "hit"; exit }
      } }' | "$FLOOR_GREP" -q hit
}
case "${FLOOR_SEGS:-}" in   # a builtin gate: every form names "event", and most commands pay no awk
  *[Ee][Vv][Ee][Nn][Tt]*)
    _ed_operator_verb && floor_block bash "the event dispatcher's follower and its rules are the operator's: start it under launchd, or run harbor event on, from your own terminal (harbor#1044)" event-dispatch-operator.argv
    ;;
esac

# No `gh pr merge` rule here (harbor#254): the merge moment is owned by bin/govern-hook.sh's PreToolUse arm (contracts/hooks.md layer-split), which knows the PR and stays silent on green.

# ── Schedulers: the same act with a timer in front of it ──
# COMMAND POSITION, NOT "THE WORD APPEARS SOMEWHERE" (harbor#92): `at` is an English preposition, so a commit message carrying "green at 20:43:55" was refused (and the printed hatch turns off every other rule).
# The anchor also closes a bypass: `at 20:43:55` is not at(1) syntax while `at midnight` and `at teatime` are, so the flat rule names at(1)'s own time-spec vocabulary. `crontab -l`/`-v` only print.
CMDPOS='(^|[;&|(`])[[:space:]]*(sudo[[:space:]]+|env[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?crontab([[:space:]]+-[^[:space:]lv]|[[:space:]]+[^[:space:]-])" \
  && floor_block bash "crontab installs code that runs later, outside any guard" crontab-install.flat
AT_FLAT='(now|midnight|noon|teatime|tomorrow|next|\+[0-9]|-f|-t|-m|-q|[0-9]{3,4}([[:space:]]|$)|[0-9]{1,2}:[0-9]{2}([[:space:]]|[ap]m|$))'
hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?(at|batch)[[:space:]]+${AT_FLAT}" \
  && floor_block bash "at/batch schedules code that runs later, outside any guard" at-batch-schedule.flat
# THE ARGV TWIN, alongside the flat rules (flat reaches runtime-assembled operands and oversized payloads, argv is more precise; neither is a superset): the scheduler verb must be the segment's COMMAND.
# at/batch fire when an argument IS a job spec; crontab fires unless every argument is a listing flag; an EMPTY argument list fires either way (bare `crontab` replaces the table, bare `batch` runs its stdin).
sched_fires() { # <cmd-ERE> <arg-ERE> <any|unless>
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _sfre="$1"; _sfarg="$2"; _sfsense="$3"
  # `ci`: this filesystem is case-insensitive, so CRONTAB runs crontab (harbor#282); scoped to this helper (see _floor_seg_ids).
  for _sfid in $(_floor_seg_ids "$_sfre" ci); do
    _sfargs="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_sfid}://p")"
    [ -n "$_sfargs" ] || return 0
    if [ "$_sfsense" = any ]; then
      if printf '%s\n' "$_sfargs" | "$FLOOR_GREP" -Eq  -- "$_sfarg"; then return 0; fi
    else
      if printf '%s\n' "$_sfargs" | "$FLOOR_GREP" -Evq -- "$_sfarg"; then return 0; fi
    fi
  done
  return 1
}
AT_SPEC='^(now|midnight|noon|teatime|tomorrow|next|\+|-f|--file|-t|-m|-q|[0-9]{3,4}|[0-9]{1,2}:[0-9]{2}([ap]m)?|[0-9]{1,2}(am|pm))$'
sched_fires '^([a-zA-Z0-9_./-]*/)?(at|batch)$' "$AT_SPEC" any \
  && floor_block bash "at/batch schedules code that runs later, outside any guard" at-batch-schedule.argv
sched_fires '^([a-zA-Z0-9_./-]*/)?crontab$' '^(-l|-v|--list)$' unless \
  && floor_block bash "crontab installs code that runs later, outside any guard" crontab-install.argv
SCHED='(LaunchAgents|LaunchDaemons|systemd/user|/etc/cron|/etc/systemd|/var/spool/cron|/var/at/tabs|\.config/autostart|/etc/xdg/autostart)'
hit "(>[|!&]?|>>!?)[[:space:]]*[^[:space:];&|]*$SCHED" \
  && floor_block bash "writing a launchd/systemd/cron unit schedules code outside any guard" unit-file-write.flat
hit "(^|[^[:alnum:]_])(cp|mv|install|ln|tee|rsync|ditto)([[:space:]]+-[^[:space:]]+)*[[:space:]][^;&|]*$SCHED|(^|[^[:alnum:]_])dd[^;&|]*of=[^[:space:];&|]*$SCHED|(^|[^[:alnum:]_])(sed|perl)[^;&|]*([[:space:]]-[a-z]*i|--in-place)[^;&|]*$SCHED" \
  && floor_block bash "installing a launchd/systemd/cron unit schedules code outside any guard" unit-file-install.flat
hit '(^|[^[:alnum:]_])launchctl[[:space:]]+(setenv|load|bootstrap)' \
  && floor_block bash "launchctl setenv/load changes the environment or units of later processes" launchctl-mutate.flat
# The Linux forms (harbor#618): enable/link is launchctl load, set-environment is setenv, and a
# systemd-run timer is at(1). start, status and list-timers stay open, as kickstart and list do.
sched_fires '^([a-zA-Z0-9_./-]*/)?systemctl$' '^(enable|reenable|link|preset|edit|add-wants|add-requires|set-environment|import-environment)$' any \
  && floor_block bash "systemctl enable/link/set-environment changes the units or environment of later processes" systemctl-mutate.argv
sched_fires '^([a-zA-Z0-9_./-]*/)?systemd-run$' '^--on-(active|boot|startup|unit-active|unit-inactive|calendar|clock-change|timezone-change)(=|$)' any \
  && floor_block bash "systemd-run --on-* schedules code that runs later, outside any guard" systemd-run-timer.argv
# PATH POISONING: a former rule was removed as provably dead (harbor#280): its second condition equalled startup-file-write's only condition, which runs earlier and exits 2. `export PATH=/evil:$PATH >> ~/.zprofile` still blocks as startup-file-write.
# The dead rule's id and call are deliberately not spelled here: lint F5 counts mentions of the blocking function in comments as call sites, and admission-equivalence.sh scrapes this file's TEXT for rule ids, comments included.
# eval / shell -c of a FETCHED command substitution runs against the EXPD variant (the normalizer erases `$(` elsewhere, which made both rules dead, red-team pass 4); the body must be a fetch, so `eval $(ssh-agent -s)` stays allowed.
hit '(^|[^[:alnum:]_])(eval|source)[[:space:]][^;&|]*\$\([^)]*(curl|wget|fetch|base64|xxd|openssl)' \
  && floor_block bash "eval/source of a fetched command substitution" eval-fetched-subst.flat
hit '(^|[^[:alnum:]_])(sh|bash|zsh|dash|ksh)[[:space:]][^;&|]*-[a-z]*c[[:space:]][^;&|]*\$\([^)]*(curl|wget|fetch)' \
  && floor_block bash "shell -c executing a fetched payload" shell-c-fetched.flat
# A COMMAND WORD that is itself a decoding substitution runs the decoded text, the form eval above
# is refused for; no argv rule can read it, the word is a placeholder (harbor#1313).
hit "${CMDPOS}[\"']?(\\\$\\(|\`)[^)\`]*(base64|basenc|xxd|openssl[[:space:]]+(enc|base64))[^)\`]*[[:space:]]-([a-zA-Z]*[dDr]|-decode|-reverse)" \
  && floor_block bash "a command word decoded from a substitution (base64/xxd) runs text no rule can read" decoded-command-word.flat
# A zsh glob qualifier `(e:cmd:)` or `(+func)` RUNS code as the word expands, in a redirect, an
# argument or a bare glob; the tokenizer reads it as a quoted group (harbor#1313).
hit "[*?]\\((#q)?[A-Za-z^.,@/%=-]*e[:'\"+]|[*?]\\(([^)]*[^[:alnum:]])?\\+[A-Za-z_]" \
  && floor_block bash "a zsh glob qualifier that runs code while the word expands" zsh-glob-qualifier-exec.flat
# …and a head/substitute modifier on a glob moves a recursive delete's operand up the tree, to the root.
hit "(^|[^[:alnum:]_])rm[[:space:]]+([^;&|]*[[:space:]])?(-[a-zA-Z-]*[rR][a-zA-Z-]*|--recursive)[[:space:]]+[^;&|]*[*?]\\([^)]*:[hs]" \
  && floor_block bash "rm -r on a glob whose zsh modifier rewrites the operand (:h climbs to the root)" rm-rf-root.flat
# Netcat listener / -e backdoor
hit '(^|[^[:alnum:]_])nc([[:space:]]+-[a-z]*[le])' \
  && floor_block bash "netcat listener/exec backdoor" netcat-backdoor.flat
# Device write / filesystem make. dd is not the only writer: a plain redirect
# or tee destroys a raw disk identically (red-team 2026-07-24).
hit '(^|[^[:alnum:]_])dd[[:space:]].*of=/dev/' \
  && floor_block bash "dd writing to a device node" dd-to-device.flat
hit '>\|?[[:space:]]*/dev/(sd|hd|nvme|disk|rdisk|vd|xvd|mmcblk|loop|dm-|mapper/|md[0-9])' \
  && floor_block bash "shell redirect overwriting a raw device" redirect-to-device.flat
hit '(^|[^[:alnum:]_])tee([[:space:]]+-[a-z]+)*[[:space:]]+/(dev/(sd|hd|nvme|disk|rdisk)|etc/(passwd|shadow|sudoers|hosts))' \
  && floor_block bash "tee writing to a raw device or a critical system file" tee-to-device.flat
hit '>\|?[[:space:]]*/etc/(passwd|shadow|sudoers|hosts|ssh/)' \
  && floor_block bash "shell redirect overwriting a critical system file" redirect-system-file.flat
# A glob in the target is the file it matches: both shells glob a redirect target, so `passw?` is
# passwd. Each candidate is run through `case`, the shell's own matcher (harbor#1313).
_sysfile_glob_hit() {
  case "$TARGETS" in *'*'*|*'?'*|*'['*) ;; *) return 1 ;; esac
  printf '%s\n' "$TARGETS" \
    | "$FLOOR_GREP" -oE '(>\|?|tee([[:space:]]+-[a-z]+)*[[:space:]]+)[[:space:]]*/[^[:space:];&|<>()$`]*[*?[][^[:space:];&|<>()$`]*' \
    | sed -E 's/^(>\|?|tee([[:space:]]+-[a-z]+)*[[:space:]]+)[[:space:]]*//' \
    | while IFS= read -r _sgp; do
      for _sgn in passwd shadow sudoers hosts gshadow master.passwd ssh/sshd_config ssh/ssh_config; do
        # shellcheck disable=SC2254 # the operand IS the pattern: that is the question
        case "/etc/$_sgn" in $_sgp) echo hit; exit 0 ;; esac
        # shellcheck disable=SC2254
        case "/private/etc/$_sgn" in $_sgp) echo hit; exit 0 ;; esac
      done
    done
}
[ -z "$(_sysfile_glob_hit)" ] \
  || floor_block bash "shell redirect onto a glob that names a critical system file" redirect-system-file.flat
# newfs_<type> is macOS's mkfs (pass 13, P13D-6).
hit '(^|[^[:alnum:]_])(mkfs(\.|[[:space:]])|newfs(_[a-z0-9]+)?[[:space:]])' \
  && floor_block bash "mkfs (filesystem creation on a device)" mkfs-device.flat
# ── MORE DEVICE DESTROYERS (harbor#1313, lane L2) ── the other irreversible device-destruction spellings. Most are Linux-only, blocked anyway (docs/explanation/admission-baseline.md B-sd-3: a Linux CI sandbox is a session).
# Read-only inspection stays allowed (lsblk, blkid, fdisk -l, bare wipefs, badblocks without -w, parted print, dd imaging a disk into a file), so each rule needs more than the verb; a wrapper does not hide it because the flat scanner reads the normalized text.
_DEVN='(sd|hd|vd|xvd|nvme|disk|rdisk|mmcblk|loop|dm-|mapper/|md[0-9])'
# Verbs whose every invocation on a disk node is destruction.
hit "(^|[^[:alnum:]_])(blkdiscard|shred|mke2fs|mkswap)[[:space:]][^;&|]*/dev/$_DEVN" \
  && floor_block bash "raw-device discard/overwrite/format verb aimed at a disk node" device-wipe-verb.flat
# cp WRITES a disk node as dd does when the node is the destination: the last operand, or a file
# named like a node copied into /dev. Reading one into a file (imaging) is not (harbor#1313).
_DEVB='(sd|hd|vd|xvd|nvme|disk|rdisk|mmcblk|loop|dm-|md[0-9])[a-z0-9]*'
hit "(^|[^[:alnum:]_])cp[[:space:]]+[^;&|]*[[:space:]]/+dev/$_DEVN[^[:space:];&|]*[[:space:]]*(\$|[;&|)])" \
  && floor_block bash "cp writing onto a raw disk node" device-wipe-verb.flat
hit "(^|[^[:alnum:]_])cp[[:space:]]+(-[^;&|]*[[:space:]])?((-t|--target-directory)[=[:space:]]*/+dev/?[[:space:]]+([^;&|]*[[:space:]])?$_DEVB([[:space:]]|\$)|$_DEVB[[:space:]]+([^;&|]*[[:space:]])?(-t|--target-directory)[=[:space:]]*/+dev/?([[:space:]]|\$)|([^;&|]*[[:space:]])?$_DEVB[[:space:]]+/+dev/?[[:space:]]*(\$|[;&|)]))" \
  && floor_block bash "cp copying a node-named file into /dev, which writes the disk node" device-wipe-verb.flat
# wipefs erases signatures only with -a/--all or -o/--offset; bare wipefs just LISTS them.
hit "(^|[^[:alnum:]_])wipefs[[:space:]][^;&|]*(-[a-z]*a|--all|-o|--offset)[^;&|]*/dev/$_DEVN" \
  && floor_block bash "wipefs erasing a raw device's filesystem signatures" device-wipefs.flat
# badblocks is a surface scan; only -w/--write is destructive (it overwrites).
hit "(^|[^[:alnum:]_])badblocks[[:space:]][^;&|]*(-[a-z]*w|--write)[^;&|]*/dev/$_DEVN" \
  && floor_block bash "badblocks destructive write-mode scan of a raw device" device-badblocks.flat
# sgdisk edits the GPT with -Z/-o/-d/-n/-g/-G; `sgdisk -p` (print) stays allowed.
hit "(^|[^[:alnum:]_])sgdisk[[:space:]][^;&|]*(-Z|--zap|-o([[:space:]]|$)|--clear|-d|--delete|-n|--new|-g|-G)[^;&|]*/dev/$_DEVN" \
  && floor_block bash "sgdisk zapping or rewriting a device partition table" device-sgdisk.flat
# parted destroys only with a write subcommand; `parted … print/unit` stays allowed.
hit "(^|[^[:alnum:]_])parted[[:space:]][^;&|]*/dev/$_DEVN[^;&|]*[[:space:]](mklabel|mktable|mkpart|rm|resizepart|rescue|move)([[:space:]]|$)" \
  && floor_block bash "parted writing a new partition table/partition to a device" device-parted.flat
# The dd family beyond plain dd: dcfldd/dd_rescue/ddrescue to a device node
# (dd-to-device above requires a non-alnum before `dd`, so `dcfldd` slips it).
hit "(^|[^[:alnum:]_])(dcfldd|dd_rescue|ddrescue)[[:space:]][^;&|]*of=/+dev/$_DEVN" \
  && floor_block bash "dd-variant writing to a device node" dd-variant-to-device.flat
# A dd-family OUTPUT operand onto a critical /etc account file, a third writer beside the redirect and tee rules above.
hit '(^|[^[:alnum:]_])(dd|dcfldd|dd_rescue|ddrescue)[[:space:]][^;&|]*of=/+etc/(passwd|shadow|sudoers|gshadow|master\.passwd|hosts)' \
  && floor_block bash "dd-family output operand overwriting a critical system file" dd-to-system-file.flat
# chmod -R 777 (permission bomb, either arg order)
hit '(^|[^[:alnum:]_])chmod([[:space:]]+(-[a-zA-Z-]+|--))*[[:space:]]+(-[a-zA-Z]*R[a-zA-Z]*([[:space:]]+--)?[[:space:]]+0?777|0?777([[:space:]]+-[a-zA-Z-]+)*[[:space:]]+-[a-zA-Z]*R)' \
  && floor_block bash "recursive chmod 777 (permission bomb)" chmod-777-recursive.flat
# Fork bomb  :(){ :|:& };:
hit ':[[:space:]]*\([[:space:]]*\)[[:space:]]*\{[[:space:]]*:[[:space:]]*\|[[:space:]]*:' \
  && floor_block bash "fork bomb" fork-bomb.flat
# …and the same function under any other name, `name()` or `function name`, body a brace or a
# subshell (harbor#1313). The name must repeat, which only a BRE back-reference can say portably,
# and a back-reference over a padded 32KB line took 282 s: so ERE cuts the candidates out first.
_FBW='[^[:space:]|&;(){}<>]+'
if hit "${_FBW}[[:space:]]*(\\([[:space:]]*\\))?[[:space:]]*[{(][[:space:]]*${_FBW}[[:space:]]*[|&][[:space:]]*${_FBW}" \
   && "$FLOOR_GREP" -oE "(function[[:space:]]+)?${_FBW}[[:space:]]*(\\([[:space:]]*\\))?[[:space:]]*[{(][[:space:]]*${_FBW}[[:space:]]*[|&][[:space:]]*${_FBW}" <<HARBOR_ADMISSION_HIT_EOF \
      | "$FLOOR_GREP" -q -e '^\([^[:space:]|&;(){}<>]\{1,\}\)[[:space:]]*([[:space:]]*)[[:space:]]*[{(][[:space:]]*\1[[:space:]]*[|&][[:space:]]*\1$' \
          -e '^function[[:space:]]\{1,\}\([^[:space:]|&;(){}<>]\{1,\}\)[[:space:]]*\(([[:space:]]*)\)\{0,1\}[[:space:]]*[{(][[:space:]]*\1[[:space:]]*[|&][[:space:]]*\1$'
$TARGETS
HARBOR_ADMISSION_HIT_EOF
then
  floor_block bash "fork bomb" fork-bomb.flat
fi
# rm -rf against the filesystem root, $HOME itself, or a system tree. `~` and $HOME match only when they ARE the target (a path under them is ordinary work, red-team pass 2).
# `~<name>` is a home dir under a different spelling (pass 13), so the rule is the general SHAPE, not this host's login name.
TILDE_USER='~[A-Za-z_][A-Za-z0-9_.-]*'
# THE RECURSIVE FLAG NEED NOT COME FIRST: `(-flags )*` lets any run of non-recursive flags precede it, and cannot swallow the target because every element must begin with `-` (pass 13).
RMF='rm[[:space:]]+(-[a-zA-Z-]+[[:space:]]+)*(-[a-zA-Z-]*[rR][a-zA-Z-]*|--recursive)([[:space:]]+(-[a-zA-Z-]+|--[a-z-]+))*[[:space:]]+(--[[:space:]]+)?'
# The tail class keeps this off ordinary work: an alphanumeric after the slash reaches no terminator.
hit "(^|[^[:alnum:]_])$RMF(~|\\\$HOME|\\\$\\{HOME\\}|$TILDE_USER)/?\\*?([[:space:]]|[;&|\"')}]|\$)" \
  && floor_block bash "rm -rf against \$HOME itself" rm-rf-home.flat
hit "(^|[^[:alnum:]_])$RMF/\\*?([[:space:]]|[*;&|\"')}]|\$)" \
  && floor_block bash "rm -rf against the filesystem root" rm-rf-root.flat
# Catastrophic at a system-tree ROOT or ONE level in (/usr, /usr/local, /Users/someone); deeper paths are ordinary work (red-team pass 3).
# harbor#1313: /dev is a system tree, and /root is a home dir, so the tree itself and its contents only.
hit "(^|[^[:alnum:]_])$RMF/((etc|usr|bin|sbin|boot|lib|opt|var|System|Library|Applications|Users|home|dev)(/[^/[:space:]]+)?|root)/?\\*?([[:space:]]|[;&|\"')}]|\$)" \
  && floor_block bash "rm -rf against a system tree or an entire home directory" rm-rf-systree.flat
# THE SAME THREE RULES, AGAINST ARGV, alongside the flat ones (B-rewrite): flat reaches runtime-assembled operands and oversized payloads; argv fixes flag ORDER. RMF demands the FIRST flag contain `r`, so rm -f -r / and rm -v -r -f / passed.
# As argv it is set membership (some argument is recursive AND some argument is a catastrophic target). Whole-token anchoring (`$`) replaces the hand-drawn terminator class: a path UNDER home is not home.
RM_RECUR='^(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)$'
# `$` anchored, so `~someone` is the home dir and `~someone/proj` is not.
#
# ROOT- AND HOME-EQUIVALENT SPELLINGS (edge pass 2026-08-29): `/.`, `/..` and `~/.` deleted the root or $HOME and passed, because floor_collapse_dots leaves a TRAILING `/.` alone.
# Written as a repeating group of dot components, not an interval (this box's grep chokes on a bounded repeat); the group must consume the WHOLE component, so `/.hidden` and `/usr` stay out. Cases are in floor-test.sh.
# $HOME reaches these rules as a REGEX, so it is escaped (floor_surface_re), raw and canonical as every HOME-derived surface is (harbor#754).
HOME_RE="$(floor_surface_re "$HOME")"
RM_HOME="^(~|\\\$HOME|\\\$\\{HOME\\}|${HOME_RE})(/+(\\./+)*\\.?)?\\*?\$"
RM_ROOT='^/+((\.|\.\.)/*)*\*?$'
# THE SYMLINK SPELLINGS ARE NOT THE ONLY SPELLINGS (docs/explanation/admission-baseline.md P12-argv-09): /etc, /var and /tmp are symlinks into /private on macOS and the data volume has a firmlink, so rm -rf /private/var and rm -rf /System/Volumes/Data passed.
# The real roots are enumerated, because it is their NAMED children that are system trees. /dev and /root as in the flat rule (harbor#1313).
RM_SYS='^/(etc|usr|bin|sbin|boot|lib|opt|var|System|Library|Applications|Users|home|dev)(/[^/]+)?/?\*?$|^/root/?\*?$|^/private(/(etc|var|tmp)(/[^/]+)?)?/?\*?$|^/System/Volumes(/(Data|Preboot|VM|Update|Recovery)(/[^/]+)?)?/?\*?$'
RMCMD='^([a-zA-Z0-9_./-]*/)?s?rm$'   # srm is rm that overwrites first (pass 13, P13D-5)
floor_seg_has "$RMCMD" "$RM_RECUR" "$RM_HOME" \
  && floor_block bash "rm -rf against \$HOME itself" rm-rf-home.argv
floor_seg_has "$RMCMD" "$RM_RECUR" "$RM_ROOT" \
  && floor_block bash "rm -rf against the filesystem root" rm-rf-root.argv
# The root with a substitution glued on is the root to the flat rule (the body is blanked), but a
# brace alternative holding $IFS splits only in the table, which sees `/@SUB@` (harbor#1313).
floor_seg_has "$RMCMD" "$RM_RECUR" '^/+(@P?SUB@)+$' \
  && floor_block bash "rm -rf against the filesystem root" rm-rf-root.argv
floor_seg_has "$RMCMD" "$RM_RECUR" "$RM_SYS" \
  && floor_block bash "rm -rf against a system tree or an entire home directory" rm-rf-systree.argv

# A GLOB OR AN ANCESTOR REACHES A PROTECTED PATH (harbor#1313, L9): a glob in any component, or the parent dir itself, carried the gcloud store away unjudged. stdin is 'T:<id>:<u|->:<abs path>' targets then 'O:<verb>:<abs operand>' operands;
# an operand hits when its match set holds a target or an ancestor of one at least one component below $HOME. Per component, `**` as any depth, case-folded (APFS); prints '<id> <verb>' for the first hit.
_gl_reach() {
  awk '
    function comps(p, A,   n, k, i, a) {
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        A[++k] = a[i]
      }
      return k
    }
    function rx(g,   i, n, c, o, b, nb) {
      o = "^"; n = length(g)
      for (i = 1; i <= n; i++) {
        c = substr(g, i, 1)
        # index(), not a bracket: gawk reads `[.` inside one as a collating symbol and refuses the program
        if (c == "\\") { i++; c = substr(g, i, 1); o = o (index("][.*+?(){}|^$\\", c) ? "\\" c : c); continue }
        if (c == "*") { o = o "[^/]*"; continue }
        if (c == "?") { o = o "[^/]"; continue }
        if (c == "[") {
          b = index(substr(g, i + 1), "]")
          if (b < 2) { o = o "\\["; continue }
          nb = substr(g, i + 1, b - 1); if (substr(nb, 1, 1) == "!") nb = "^" substr(nb, 2)
          o = o "[" nb "]"; i += b; continue
        }
        if (index(".+(){}|^$", c)) o = o "\\" c; else o = o c
      }
      return o "$"
    }
    # A leading dot is matched only by a pattern that spells it, as pathname expansion does.
    function cm(g, t,   f) {
      f = substr(g, 1, 1)
      if (substr(t, 1, 1) == "." && f != "." && f != "[") return 0
      if (!(index(g, "*") || index(g, "?") || index(g, "[") || index(g, "\\"))) return g == t
      return (t ~ rx(g))
    }
    function m(i, j,   k) {
      if (i > n) return (j - 1 >= mn)
      if (j > nt) {
        if (under) return (j - 1 >= mn)
        for (k = i; k <= n; k++) if (oc[k] != "**") return 0
        return (j - 1 >= mn)
      }
      if (oc[i] == "**") return (m(i + 1, j) || (substr(tc[j], 1, 1) != "." && m(i, j + 1)))
      return (cm(oc[i], tc[j]) && m(i + 1, j + 1))
    }
    BEGIN { home = tolower(ENVIRON["HOME"]); nh = comps(home, hc) }
    /^T:/ { s = substr($0, 3); id = s; sub(/:.*/, "", id); s = substr(s, length(id) + 2)
            fl = substr(s, 1, 1); p = tolower(substr(s, 3))
            TI[++nT] = id; TU[nT] = (fl == "u"); TP[nT] = p; next }
    /^O:/ { s = substr($0, 3); vb = s; sub(/:.*/, "", vb); o = tolower(substr(s, length(vb) + 2))
            if (substr(o, 1, 1) != "/") next
            n = comps(o, oc)
            for (t = 1; t <= nT; t++) {
              nt = comps(TP[t], tc); under = TU[t]
              mn = (index(TP[t] "/", home "/") == 1) ? nh + 1 : nt
              if (m(1, 1)) { print TI[t] " " vb; exit }
            }
            next }'
}
_gl_cred_t() {
  for _gtp in '' /identities /oauth-clients /oauth-clients/client.json /oauth-clients/a /application_default_credentials.json \
              /identities/a/application_default_credentials.json /identities/z/application_default_credentials.json; do
    printf 'T:cred-destroy:-:%s\n' "$HOME/.config/gcloud$_gtp"
  done
}

# A GLOB IS ITS MATCH SET (pass 13, P13D-2/3): the shell's own `case` matches the glob's LAST component against the names each rule protects; a leading dot only by a pattern that spells it. Prints the rule id of the first hit.
# A RELATIVE GLOB IS JUDGED WHERE THE COMMAND STANDS (harbor#1313): the awk folds the cd/pushd chain and prints each relative glob under the directory the command stands in; STICKY (every directory it stood in) when the text has structure the table cannot see
# (subshell, pipeline, group, background job, expanded interpreter body), linear for a plain chain; an unresolvable hop leaves the directory unknown, and unknown judges nothing.
# THE HOME DIR'S CONTENTS ARE A HOME-STAR (harbor#1313): a last component matching EVERY probe name in the home dir deletes everything a home holds; a narrowing glob fails at least one probe and stays ordinary work.
_rm_glob_hit() {
  case "${FLOOR_SEGS:-}" in *'*'*|*'?'*|*'['*) ;; *) return 1 ;; esac
  _rgh="$(floor_canon_dir "$HOME")"
  # Both config dirs: CLAUDE_CONFIG_DIR can point elsewhere while ~/.claude is still the tree every session loads.
  LIVE_DIR="$HOME/.claude"
  _rgc="$(floor_canon_dir "$(floor_config_dir)")"; _rgl="$(floor_canon_dir "$LIVE_DIR")"
  _rglin=1
  case "$CMD" in *'('*|*')'*|*'|'*|*'`'*|*'{'*|*'}'*) _rglin=0 ;; esac
  case "$FLOOR_SEGS" in *SEGI:*|*SEGE:*|*SEGF:*) _rglin=0 ;; esac
  case "$CMD" in *'&'*) case "$(printf '%s' "$CMD" | sed 's/&&//g')" in *'&'*) _rglin=0 ;; esac ;; esac
  printf '%s\n' "$FLOOR_SEGS" | awk -v RC="$RMCMD" -v RR="$RM_RECUR" -v LIN="$_rglin" '
    # HOME through ENVIRON: awk runs escape processing over a -v value, never over this.
    BEGIN { home = ENVIRON["HOME"] }
    function addd(d) { if (d != "" && !(d in HAS)) { HAS[d] = 1; DL[++nd] = d } }
    function known(t) { return !(index(t, "@SUB@") || index(t, "@PSUB@") || t ~ /[$`*?[]/) }
    # Linear: the new directory replaces the old, and an unknown one empties the list.
    function land(k,   i) { if (LIN) { split("", HAS); nd = 0 }; for (i = 1; i <= k; i++) addd(NW[i]) }
    function cdto(t,   i, k) {
      split("", NW); k = 0
      if (t == "~" || t == "$HOME" || t == "${HOME}") NW[++k] = home
      else if (substr(t, 1, 2) == "~/")       NW[++k] = home substr(t, 2)
      else if (substr(t, 1, 6) == "$HOME/")   NW[++k] = home substr(t, 6)
      else if (substr(t, 1, 8) == "${HOME}/") NW[++k] = home substr(t, 8)
      else if (!known(t) || substr(t, 1, 1) == "~") k = 0
      else if (substr(t, 1, 1) == "/") NW[++k] = t
      else for (i = 1; i <= nd; i++) NW[++k] = DL[i] "/" t
      land(k)
    }
    /^SEGC:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); c = s; sub(/^[0-9]+:/, "", c)
               id += 0; if (id > MAX) MAX = id
               b = c; sub(/.*\//, "", b); if (b == "cd" || b == "pushd" || b == "popd") CD[id] = b
               if (tolower(c) ~ RC) RMS[id] = 1; next }
    /^SEGA:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); a = s; sub(/^[0-9]+:/, "", a)
               id += 0; if (id > MAX) MAX = id
               if (CD[id] && !(id in CDT) && a != "--" && a !~ /^-[LPenqs@]+$/) CDT[id] = a
               if (a ~ RR) REC[id] = 1; else if (a !~ /^-/) OP[id] = OP[id] a "\n"; next }
    END {
      for (id = 1; id <= MAX; id++) {
        # A bare cd is HOME; popd, a bare pushd, `-` and `+N` land where only the shell knows.
        if (CD[id] != "") {
          if (CD[id] == "popd" || (id in CDT && CDT[id] ~ /^([-+][0-9]*)$/)) land(0)
          else if (id in CDT) cdto(CDT[id])
          else if (CD[id] == "cd") { split("", NW); NW[1] = home; land(1) }
          else land(0)
          continue
        }
        if (!RMS[id] || !REC[id]) continue
        printf "%s", OP[id]
        n = split(OP[id], o, "\n")
        for (j = 1; j <= n; j++) {
          t = o[j]; c1 = substr(t, 1, 1)
          if (t == "" || t !~ /[*?[]/ || c1 == "/" || c1 == "~" || c1 == "$" || c1 == "@") continue
          for (i = 1; i <= nd; i++) print DL[i] "/" t
        }
      }
    }' \
  | floor_home_sed | { _rgm=''; while IFS= read -r _rgo; do
    case "$_rgo" in *'*'*|*'?'*|*'['*) ;; *) continue ;; esac
    # harbor#1313 (L9): kept for the multi-component judgement after the loop; and a glob in EVERY component under $HOME empties each directory a home holds.
    _rgm="$_rgm$_rgo
"
    case "$_rgo" in "$_rgh"/*/?*)
      _rgz="${_rgo#"$_rgh"/}"; _rgy=1
      while [ -n "$_rgz" ] && [ "$_rgy" = 1 ]; do
        _rgw="${_rgz%%/*}"; case "$_rgz" in */*) _rgz="${_rgz#*/}" ;; *) _rgz='' ;; esac
        [ -n "$_rgw" ] || continue
        for _rgx in Library Documents Desktop a z A Z 0 9 _; do
          # shellcheck disable=SC2254 # the operand IS the pattern: that is the question
          case "$_rgx" in $_rgw) ;; *) _rgy=0; break ;; esac
        done
      done
      [ "$_rgy" = 0 ] || { printf '%s\n' rm-rf-home; exit 0; } ;;
    esac
    _rgd="${_rgo%/*}"; _rgp="${_rgo##*/}"
    case "$_rgo" in */*) ;; *) continue ;; esac
    [ -n "$_rgd" ] || _rgd=/
    _rgd="$(floor_canon_dir "$_rgd")"
    case "$_rgd" in *'*'*|*'?'*|*'['*) continue ;; esac
    if [ "$_rgd" = "$_rgh" ]; then
      _rga=1
      for _rgx in Library Documents Desktop a z A Z 0 9 _; do
        # shellcheck disable=SC2254 # the operand IS the pattern: that is the question
        case "$_rgx" in $_rgp) ;; *) _rga=0; break ;; esac
      done
      [ "$_rga" = 0 ] || { printf '%s\n' rm-rf-home; exit 0; }
    fi
    # Candidates are '<rule>:<name>' pairs: one directory can be the parent of a home dir AND of a config dir (a sandbox), so every list that applies is checked.
    _rgn=''
    [ "$_rgd" != / ] || _rgn='etc usr bin sbin boot lib opt var System Library Applications Users home private dev root'
    _rgu="${_rgh%/*}"; [ -n "$_rgu" ] || _rgu=/
    [ "$_rgd" != "$_rgu" ] || _rgn="$_rgn ${_rgh##*/}"
    _rgn2=''; for _rgx in $_rgn; do _rgn2="$_rgn2 rm-rf-systree:$_rgx"; done; _rgn="$_rgn2"
    for _rgk in "$_rgc" "$_rgl"; do
      _rgu="${_rgk%/*}"; [ -n "$_rgu" ] || _rgu=/
      [ "$_rgd" != "$_rgu" ] || _rgn="$_rgn destructive-at-cfg:${_rgk##*/}"
      [ "$_rgd" != "$_rgk" ] || _rgn="$_rgn destructive-at-cfg:bin destructive-at-cfg:hooks destructive-at-cfg:backups destructive-at-cfg:settings.json"
    done
    [ -n "$_rgn" ] || continue
    for _rgx in $_rgn; do
      _rgr="${_rgx%%:*}"; _rgx="${_rgx#*:}"
      case "$_rgx" in .*) case "$_rgp" in .*) ;; *) continue ;; esac ;; esac
      # shellcheck disable=SC2254 # the operand IS the pattern: that is the question
      case "$_rgx" in $_rgp) printf '%s\n' "$_rgr"; exit 0 ;; esac
    done
  done
  # A glob in a parent component, judged whole against the gcloud store and the config dirs' control files (harbor#1313, L9).
  [ -z "$_rgm" ] || {
    _rgy="$( { _gl_cred_t
      for _rgk in "$_rgc" "$_rgl"; do
        [ -n "$_rgk" ] || continue
        for _rgx in '' /settings.json /settings.local.json /CLAUDE.md; do printf 'T:destructive-at-cfg-path:-:%s\n' "$_rgk$_rgx"; done
        for _rgx in /bin /hooks; do printf 'T:destructive-at-cfg-path:u:%s\n' "$_rgk$_rgx"; done
      done
      printf '%s' "$_rgm" | sed 's/^/O:rm:/'; } | _gl_reach)"
    [ -z "$_rgy" ] || printf '%s\n' "${_rgy%% *}"
  }
  }
}
_rgr="$(_rm_glob_hit)" || _rgr=""
[ "$_rgr" != rm-rf-home ] \
  || floor_block bash "rm -rf on a glob that matches every entry of \$HOME" rm-rf-home.glob
[ "$_rgr" != rm-rf-systree ] \
  || floor_block bash "rm -rf on a glob that matches a system tree or a whole home directory" rm-rf-systree.glob
[ "$_rgr" != destructive-at-cfg ] \
  || floor_block bash "a destructive command is aimed at the Helm config directory itself" destructive-at-cfg.glob
[ "$_rgr" != destructive-at-cfg-path ] \
  || floor_block bash "a glob in the path names the Helm config directory, a control file, or something under its bin/ or hooks/" destructive-at-cfg-path.glob
[ "$_rgr" != cred-destroy ] \
  || floor_block bash "a recursive delete on a glob that reaches the gcloud credential store, an ADC or the OAuth client" cred-destroy.glob

# A GLOB IN ANY COMPONENT (pass 13, P13C-1): rm ~/.cla?de/settings.json puts the glob before the last component, which _rm_glob_hit does not judge, and needs no -r. Each glob operand of a mutating verb (the destination only for cp/install/ln/rsync/ditto)
# and each glob redirect target is matched per component with the shell's own `case` against the config dirs, their control files, and anything under their bin/ and hooks/.
_glob_cfg_hit() {
  case "${FLOOR_SEGS:-}" in *'*'*|*'?'*|*'['*) ;; *) return 1 ;; esac
  LIVE_DIR="$HOME/.claude"
  _gcc="$(floor_canon_dir "$(floor_config_dir)")"; _gcl="$(floor_canon_dir "$LIVE_DIR")"
  printf '%s\n' "$FLOOR_SEGS" | awk '
    /^SEGC:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); c = s; sub(/^[0-9]+:/, "", c); sub(/^.*\//, "", c)
               c = tolower(c)
               if (c ~ /^(s?rm|unlink|shred|truncate|mv|chmod|chown|chgrp|chflags|touch|tee|sponge)$/) ANY[id] = 1
               else if (c ~ /^(cp|install|ln|rsync|ditto)$/) DST[id] = 1
               next }
    /^SEGA:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); a = s; sub(/^[0-9]+:/, "", a)
               if (a ~ /^-/) next
               if (ANY[id]) print a; else if (DST[id]) LAST[id] = a; next }
    /^SEGR:/ { s = substr($0, 6); sub(/^[0-9]+:/, "", s); if (s ~ /^[^<:]*>/) { sub(/^[^:]*:/, "", s); print s }; next }
    END { for (id in LAST) print LAST[id] }' \
  | floor_home_sed | while IFS= read -r _gco; do
    case "$_gco" in /*) ;; *) continue ;; esac
    case "$_gco" in *'*'*|*'?'*|*'['*) ;; *) continue ;; esac
    for _gck in "$_gcc" "$_gcl"; do
      for _gct in "=$_gck" "=$_gck/settings.json" "=$_gck/settings.local.json" "=$_gck/CLAUDE.md" "+$_gck/bin" "+$_gck/hooks"; do
        _gcm="${_gct%"${_gct#?}"}"; _gct="${_gct#?}"
        # Walk both paths one component at a time; the operand may be longer only under a `+` prefix.
        _gcp="${_gco#/}"; _gcq="${_gct#/}"; _gok=1
        while [ -n "$_gcq" ]; do
          [ -n "$_gcp" ] || { _gok=0; break; }
          _gpa="${_gcp%%/*}"; _gqa="${_gcq%%/*}"
          case "$_gqa" in .*) case "$_gpa" in .*|'['*) ;; *) _gok=0; break ;; esac ;; esac
          # shellcheck disable=SC2254 # the operand IS the pattern: that is the question
          case "$_gqa" in $_gpa) ;; *) _gok=0; break ;; esac
          case "$_gcp" in */*) _gcp="${_gcp#*/}" ;; *) _gcp='' ;; esac
          case "$_gcq" in */*) _gcq="${_gcq#*/}" ;; *) _gcq='' ;; esac
        done
        [ "$_gok" = 1 ] || continue
        _gcp="${_gcp%/}"
        if [ -z "$_gcp" ] || [ "$_gcm" = + ]; then echo hit; exit 0; fi
      done
    done
  done
}
[ -z "$(_glob_cfg_hit)" ] \
  || floor_block bash "a glob in the path names the Helm config directory, a control file, or something under its bin/ or hooks/" destructive-at-cfg-path.glob

# rsync --delete makes the DESTINATION match the source: from an empty dir it is rm -rf of the destination's contents (pass 13, P13D-4); the destination is the last operand, the source side is a read.
# Case-folded (harbor#282, pass 14 A-src-1); any number of `-word`s covers GNU's --delete-missing-args (harbor#1313).
_rsync_delete_dest() {
  case "${FLOOR_SEGS:-}" in *[rR][sS][yY][nN][cC]*) ;; *) return 1 ;; esac
  printf '%s\n' "$FLOOR_SEGS" | awk '
    /^SEGC:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); c = s; sub(/^[0-9]+:/, "", c)
               if (tolower(c) ~ /^([a-z0-9_.\/-]*\/)?rsync$/) RSY[id] = 1; next }
    /^SEGA:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); a = s; sub(/^[0-9]+:/, "", a)
               if (a ~ /^--del(ete(-[a-z]+)*)?$/) DEL[id] = 1; else if (a !~ /^-/) LAST[id] = a; next }
    END { for (id in RSY) if (DEL[id] && LAST[id] != "") print LAST[id] }' \
  | floor_home_sed | sed -e 's|/\.\.$|/../|' -e 's|/\.$|/./|' | awk "$FLOOR_COLLAPSE_AWK"' { fc($0, 0) }'
}
_rsd="$(_rsync_delete_dest)" || _rsd=""
if [ -n "$_rsd" ]; then
  _rsc="$(floor_canon_dir "$(floor_config_dir)")"
  # Two ids: the config-dir one guards the floor, so its '-cfg' name keeps it enforcing in shadow.
  printf '%s\n' "$_rsd" | "$FLOOR_GREP" -Eq -- "^$(floor_ere_quote "$_rsc")/*\$" \
    && floor_block bash "rsync --delete aimed at the Helm config directory itself" rsync-delete-cfg.argv
  printf '%s\n' "$_rsd" | "$FLOOR_GREP" -Eq -- "$RM_HOME|$RM_ROOT|$RM_SYS" \
    && floor_block bash "rsync --delete aimed at the filesystem root, a system tree or a home directory" rsync-delete-dest.argv
fi

# RECURSIVE OWNERSHIP/PERMISSION REWRITES OVER THE SAME THREE TARGETS (edge pass 2026-08-29): the flat chmod rule keys on `777`, but chmod -R 000 / and chown -R nobody / passed and are no lesser event.
# Deliberately the SAME three operand patterns as the rm rules, with no mode in the pattern; no -R means no rule, and the operand test excludes chmod -R 755 build.
CHMODCMD='^([a-zA-Z0-9_./-]*/)?(chmod|chown|chgrp)$'
floor_seg_has "$CHMODCMD" "$RM_RECUR" "$RM_ROOT" \
  && floor_block bash "recursive chmod/chown against the filesystem root" chmod-recursive-root.argv
floor_seg_has "$CHMODCMD" "$RM_RECUR" "$RM_HOME" \
  && floor_block bash "recursive chmod/chown against \$HOME itself" chmod-recursive-home.argv
floor_seg_has "$CHMODCMD" "$RM_RECUR" "$RM_SYS" \
  && floor_block bash "recursive chmod/chown against a system tree" chmod-recursive-systree.argv

# find -exec destructive spray. A FILTERED find (-name/-path/-regex) is ordinary build-artifact cleanup (red-team pass 3), but the exemption must test the filter's SELECTIVITY, not its presence: a find matching everything is a whole-filesystem spray (pass 8). The verb list covers plain rm, -delete and unlink.
# harbor#1313: rsync --delete <empty>/ {} is rm -rf of each match, and rsync-delete-dest sees only the placeholder. Same flag family.
FINDRSYNC='rsync([[:space:]]+[^[:space:];|&]+)*[[:space:]]+--del(ete(-[a-z]+)*)?([[:space:]]|$)'
FINDVERB='(s?rm([[:space:]]+-[a-zA-Z-]+)*[[:space:]]|unlink[[:space:]]|shred[[:space:]]|truncate[[:space:]]|chmod[[:space:]]+-R|chown[[:space:]]+-R|dd[[:space:]]|mkfs\.|'"$FINDRSYNC"'|(sh|bash|zsh)[[:space:]]+-c)'
FINDVERB_NOSH='(s?rm([[:space:]]+-[a-zA-Z-]+)*[[:space:]]|unlink[[:space:]]|shred[[:space:]]|truncate[[:space:]]|chmod[[:space:]]+-R|chown[[:space:]]+-R|dd[[:space:]]|mkfs\.|'"$FINDRSYNC"')'
# harbor#607: a shell exec under find is exempt ONLY when its whole payload is provably read-only (an allowlist). TARGETS carries the find child as its own `sh -c <payload> _ <path>` line.
# Allowed: every simple command starts with a bare verb from the set; no output redirect except /dev/null or an fd dup; no `$(`, backtick, `<(` or heredoc. awk and sed are left out (their programs can write); a multi-line payload is never judged.
_sh_payload_ro() {
  case "$CMD" in *'
'*) return 1 ;; esac
  printf '%s\n' "$TARGETS" | awk '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  BEGIN {
    n = split("true : echo printf test [ gr" "ep cat wc head tail stat file ls basename dirname cmp diff shasum md5", V, " ")
    for (i = 1; i <= n; i++) ok[V[i]] = 1
    n = split("if then else elif while until do !", K, " ")
    for (i = 1; i <= n; i++) kw[K[i]] = 1
    n = split("fi done esac else", E, " ")
    for (i = 1; i <= n; i++) endkw[E[i]] = 1
  }
  /^(sh|bash|zsh)[ \t]+-c[ \t]/ {
    seen = 1
    p = $0; sub(/^(sh|bash|zsh)[ \t]+-c[ \t]+/, "", p)
    if (p ~ /\$\(|`|<\(|<</) { fail = 1; next }
    orig = p
    gsub(/[0-9]*>&[0-9-]+/, " ", p)
    # the target must be exactly /dev/null: end, blank, or one of ; | & ) follows
    while (match(p, /(&|[0-9]*)>>?[ \t]*\/dev\/null/)) {
      nx = substr(p, RSTART + RLENGTH, 1)
      if (nx != "" && nx !~ /^[ \t;|&)]$/) { fail = 1; break }
      p = substr(p, 1, RSTART - 1) " " substr(p, RSTART + RLENGTH)
    }
    if (fail || p ~ />/) { fail = 1; next }
    gsub(/&&|\|\||[;|&]/, "\001", p)
    m = split(p, S, "\001")
    for (i = 1; i <= m; i++) {
      s = trim(S[i])
      while (1) {
        w = s; sub(/[ \t].*$/, "", w)
        if (w in kw) { s = trim(substr(s, length(w) + 1)) } else break
      }
      if (s == "") continue
      w = s; sub(/[ \t].*$/, "", w)
      rest = trim(substr(s, length(w) + 1))
      if (w in endkw) { if (rest != "" && rest !~ /^_/) fail = 1; continue }
      if (!(w in ok)) { fail = 1; continue }
      if (w == ":" && orig ~ />/) fail = 1
      if (w == "file" && rest ~ /(^|[ \t])-[A-Za-z]*C/) fail = 1
    }
  }
  END { exit (seen && !fail) ? 0 : 1 }'
}
# harbor#1313: a wrapper (`sudo xargs`), a group opener or a value-taking xargs flag (`-I {}`, `-n 1`) hid the verb. hit is case-blind, so a numeric flag takes digits only: `-r git rm` must not read as `-R <value>`.
_XW='(([a-zA-Z0-9_./-]*/)?(sudo|doas|env|command|builtin|exec|nohup|stdbuf|nice|ionice|setsid|timeout|time|caffeinate)[[:space:]]+((-[^[:space:]]+|[0-9]+[smhd]?|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|--)[[:space:]]+([^-][^[:space:]]*[[:space:]]+)?)*)*'
_XOPT='([[:space:]]+(-[IJEad][[:space:]]+[^[:space:]]+|-[LnPsSR][[:space:]]+[0-9]+|--(max-args|max-procs|max-chars|delimiter|arg-file|process-slot-var)[[:space:]]+[^[:space:]]+|-[^[:space:]]+))*'
XARGS_DESTROY="\|&?[[:space:]]*([{(][[:space:]]*)*${_XW}([a-zA-Z0-9_./-]*/)?g?xargs${_XOPT}[[:space:]]+${_XW}([a-zA-Z0-9_./-]*/)?(rm|unlink|chmod|chown|mv|dd)([[:space:]]|\$)"
# -ok/-okdir run their command as -exec does (admission-normalize.awk, find_destroys_cfg); only a y on stdin differs.
_shro=0
if hit "(^|[^[:alnum:]_])find([^|]*)-(exec|ok)(dir)?[[:space:]]+(sh|bash|zsh)[[:space:]]+-c" \
   && ! hit "(^|[^[:alnum:]_])find([^|]*)(-(exec|ok)(dir)?[[:space:]]+$FINDVERB_NOSH|[[:space:]]-delete([[:space:]]|\$))" \
   && ! hit "$XARGS_DESTROY" \
   && _sh_payload_ro; then
  _shro=1
fi
if [ "$_shro" != 1 ] && { hit "(^|[^[:alnum:]_])find([^|]*)(-(exec|ok)(dir)?[[:space:]]+$FINDVERB|[[:space:]]-delete([[:space:]]|\$))" \
   || hit "$XARGS_DESTROY"; }; then
  # A SELECTIVE filter makes it ordinary cleanup; a universal pattern is not a filter, and a search rooted at / ~ or $HOME is catastrophic regardless. The root must be a whole operand (harbor#758).
  _rooted=1; hit "(^|[^[:alnum:]_])find([[:space:]]+[^|]*)?[[:space:]](/+|~/*|\\\$HOME/*|\\\$\\{HOME\\}/*|${HOME_RE}/*)([[:space:];&|)]|\$)" || _rooted=0
  _filtered=0
  hit "(^|[^[:alnum:]_])(find|git[[:space:]]+ls-files)[^|]*[[:space:]]-(name|iname|path|ipath|regex|z)([[:space:]]|\$)" && _filtered=1
  # …unless the "filter" matches everything.
  hit "[[:space:]]-(name|iname|path|ipath|regex)[[:space:]]+[\"']?([*]|[.][*]|[?][*])[\"']?([[:space:]]|\$)" && _filtered=0
  [ "$_rooted" = "1" ] && _filtered=0
  [ "$_filtered" = "1" ] || floor_block bash "find/xargs destructive spray (no selective filter, or rooted at / ~ \$HOME)" find-xargs-spray.flat
fi
# Pass 14 A-src-2/3: a FILTERED find that deletes is cleanup anywhere but the config dir, where the filter can name the guards: a find rooted at the config dir, its bin/ or hooks/ is asked per segment.
find_destroys_cfg() {
  case "${FLOOR_SEGS:-}" in *[fF][iI][nN][dD]*) ;; *) return 1 ;; esac
  _fcd="$(floor_canon_dir "$(floor_config_dir)")"; [ -n "$_fcd" ] || return 1
  for _fid in $(_floor_seg_ids '^([a-zA-Z0-9_./-]*/)?find$' ci); do
    _fa="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_fid}://p")"
    printf '%s\n' "$_fa" | awk '
      /^-delete$/ { d = 1 }
      x { if (tolower($0) ~ /^([a-z0-9_.\/-]*\/)?(s?rm|unlink|shred|truncate|chmod|chown|dd|mv|sh|bash|zsh)$/) d = 1; x = 0 }
      /^-(exec|execdir|ok|okdir)$/ { x = 1 }
      END { exit d ? 0 : 1 }' || continue
    # The roots: leading -H/-L/-P/BSD options first, then operands up to the expression.
    printf '%s\n' "$_fa" | awk 'l == 0 && /^-[HLPEXdsx]+$/ { next } { l = 1 } /^[-(!)]/ { exit } { print }' \
      | while IFS= read -r _fr; do floor_expand_paths "$_fr"; echo; done \
      | sed 's|/*$||' | "$FLOOR_GREP" -Eq -- "^$(floor_ere_quote "$_fcd")(/+(bin|hooks)(/.*)?)?\$" && return 0
  done
  return 1
}
find_destroys_cfg \
  && floor_block bash "find deleting under the Helm config directory, its bin/ or its hooks/ (a filter there can name the guards)" find-destroy-at-cfg.argv
# The Playwright CLI or MCP run from a shell reaches the operator's attached Chrome with none of `harbor chrome`'s allowlists (harbor#835); `node <path>` counts too. harbor#1420: a `-c` payload and `--package=@playwright/cli@$P` spell the same run.
hit '(^|[;&|(`]|[[:space:]]-[A-Za-z]*c[[:space:]]+)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(env[[:space:]]+([^[:space:]]+[[:space:]]+)*)?((bunx|npx|bun[[:space:]]+x|pnpm[[:space:]]+dlx|yarn[[:space:]]+dlx|npm[[:space:]]+exec)([[:space:]]+-[^[:space:]]+)*[[:space:]]+((--package=|(-p|--package)[[:space:]]+))?@playwright/(cli|mcp)|([^[:space:]]*/)?playwright-(cli|mcp)|node[[:space:]]+([^[:space:]]+[[:space:]]+)*[^[:space:]]*(@playwright/(cli|mcp)|playwright-(cli|mcp)|clidaemon\.js))([@/[:space:]]|$)' \
  && floor_block bash "the Playwright CLI/MCP run directly skips harbor chrome's guardrails — use harbor chrome <verb>" playwright-direct.argv
# ── THE APPROVAL GATE (harbor#1018, docs/design/approval-gate.md) ── An `ask` rule on <cfg>/bin/gate-approve.sh is the operator's click and rules match TEXT, so a gate tool runs only as the exact command its rule names;
# copying or linking one is refused, and the raw merge/deploy routes it replaces are refused in a session too. Words are judged by position in each simple command, so `git add`, `grep` and `cat` of these files stay allowed.
# GATE_ROUTE_AWK prints EXEC, COPY, MERGE or DEPLOY per simple command, after peeling assignments, wrappers and interpreters (sh -c).
GATE_ROUTE_AWK='function base(t) { sub(/.*\//, "", t); return t }
function gate(t) { return base(t) ~ /^gate-(approve|merge)(\.sh)?$/ }
function judge(s,   n, w, i, j, p, k, prog, nx, redir, put) {
  gsub(q, "", s); gsub(/["\\]/, "", s); n = split(s, w, /[ \t]+/); i = 1
  while (i <= n && (w[i] == "" || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
  if (i > n) return
  if (base(w[i]) ~ /^(cp|ln|install|rsync|ditto|scp|mv|dd|tee|gcp|gln)$/) for (j = i + 1; j <= n; j++) if (gate(w[j])) { print "COPY"; break }
  redir = 0
  for (j = i + 1; j <= n; j++)
    if ((w[j] ~ /^[0-9]*>>?$/ && w[j + 1] != "" && w[j + 1] !~ /^&/ && w[j + 1] != "/dev/null") || (w[j] ~ /^[0-9]*>>?[^&>]/ && w[j] !~ />\/dev\/null$/)) redir = 1
  if (redir && base(w[i]) !~ /^(echo|printf)$/) for (j = i; j <= n; j++) if (gate(w[j])) { print "COPY"; break }
  for (;;) {
    k = base(w[i])
    if (k == "find") { for (j = i + 1; j <= n; j++) if (w[j] ~ /^-(exec|execdir|ok|okdir)$/) break
                       if (j >= n) return; i = j + 1; continue }
    if (k ~ /^(env|sudo|doas|nohup|nice|time|timeout|exec|command|builtin|xargs|stdbuf|setsid|ionice|caffeinate|parallel)$/) {
      i++; while (i <= n && (w[i] ~ /^-/ || w[i] ~ /^[0-9.]+[smhd]?$/ || w[i] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) i++
      if (i > n) return; continue }
    if (k ~ /^(sh|bash|dash|zsh|ksh|mksh|busybox|source|\.)$/) {
      i++; while (i <= n && w[i] ~ /^-/ && w[i] !~ /^-[A-Za-z]*c$/) i++
      if (i <= n && w[i] ~ /^-[A-Za-z]*c$/) i++
      if (i > n) return; continue }
    break }
  prog = base(w[i]); nx = (i < n) ? w[i + 1] : ""
  if (gate(w[i])) { print "EXEC"; return }
  if (prog == "gh") {
    # positional words, skipping every option and the value of those that take one (gh -R o/r pr merge, gh pr -R o/r merge)
    np = 0; meth = ""; fields = 0; ep = ""
    for (j = i + 1; j <= n; j++) {
      if (w[j] ~ /^-(R|X|H|f|F|q|t|p)$/ || w[j] ~ /^--(repo|method|header|field|raw-field|input|jq|template|preview|hostname|cache)$/) {
        if (w[j] ~ /^-(X)$|^--method$/) meth = toupper(w[j + 1])
        if (w[j] ~ /^-(f|F)$|^--(field|raw-field|input)$/) { fields = 1; if (w[j + 1] ~ /^query=@/) qfile = 1 }
        j++; continue }
      if (w[j] ~ /^-X./) { meth = toupper(substr(w[j], 3)); sub(/^=/, "", meth); continue }
      if (w[j] ~ /^--method=/) { meth = toupper(substr(w[j], 10)); continue }
      if (w[j] ~ /^-[fF]./ || w[j] ~ /^--(field|raw-field|input)=/) { fields = 1; if (w[j] ~ /query=@/) qfile = 1; continue }
      if (w[j] ~ /^-/) continue
      np++; pos[np] = w[j] }
    for (p = i + 1; p <= n; p++) if (w[p] ~ /^-(h|-help)$/) return
    if (pos[1] == "pr" && pos[2] == "merge") { print "MERGE"; return }
    if (pos[1] == "alias" && (pos[2] == "set" || pos[2] == "import")) { for (p = 3; p <= np; p++) if (pos[p] ~ /merge|api|push/) { print "MERGE"; return } }
    if (pos[1] == "repo" && pos[2] == "edit") { for (p = i + 1; p <= n; p++) if (w[p] ~ /^--default-branch/) { print "MERGE"; return } }
    if (pos[1] == "api") { ep = pos[2]; sub(/^\/+/, "", ep); sub(/\?.*/, "", ep); sub(/\/+$/, "", ep)
      for (p = i + 1; p <= n; p++) if (w[p] ~ /mergePullRequest|enablePullRequestAutoMerge|mergeBranch|updateRefs?|createCommitOnBranch/) { print "MERGE"; return }
      if (ep == "graphql" && qfile) { print "MERGE"; return }
      if (meth == "" && fields) meth = "POST"
      if (ep ~ /(^|\/)pulls\/[0-9]+\/merge$/ && meth != "" && meth != "GET") { print "MERGE"; return }
      if (ep ~ /(^|\/)merges$/) { print "MERGE"; return }
      # a ref DELETE removes a branch or tag and moves none: not a merge; gh api has no allow rule, so the classifier still judges it
      if (ep ~ /(^|\/)git\/refs(\/|$)/ && meth != "" && meth != "GET" && meth != "DELETE") { print "MERGE"; return }
      if (ep ~ /^repos\/[^\/]+\/[^\/]+$/ && meth != "" && meth != "GET") { print "MERGE"; return } }
    return }
  if (prog ~ /^(curl|wget|http|https|xh)$/) {
    gh_api = 0; wr = 0
    for (p = i + 1; p <= n; p++) {
      if (w[p] ~ /api\.github\.com|\/api\/graphql/) gh_api = 1
      if (w[p] ~ /^(-X|--request)$/ && toupper(w[p + 1]) !~ /^GET$/) wr = 1
      if (w[p] ~ /^-X./ && toupper(substr(w[p], 3)) !~ /^=?GET$/) wr = 1
      if (w[p] ~ /^(-d|--data|--data-raw|--data-binary|--json|-F|--form|--post-data|--method=)/ || w[p] ~ /^(PUT|POST|PATCH|DELETE)$/) wr = 1 }
    if (gh_api && wr) { print "MERGE"; return } }
  if (prog == "git") {
    for (j = i + 1; j <= n && w[j] ~ /^-/; j++) if (w[j] ~ /^-[Cc]$/) j++
    if (w[j] == "push") { for (p = j + 1; p <= n; p++) {
        if (w[p] ~ /^--(all|mirror)$/) { print "PUSHMAIN"; return }
        if (w[p] !~ /^-/ && w[p] ~ /^\+?([^:]*:)?(refs\/heads\/)?(main|master)$/ && p > j + 1 + (w[j + 1] ~ /^-/ ? 1 : 0)) { print "PUSHMAIN"; return } } } }
  if (prog ~ /^(gate-)?merge-check(\.sh)?$/) { for (j = i + 1; j <= n; j++) if (w[j] == "--merge") { print "MERGE"; return } }
  if (prog ~ /^gate-merge-stack(\.sh)?$/ && nx == "merge") { print "MERGE"; return }
  if (prog == "harbor" && nx == "merge-stack" && w[i + 2] == "merge") { print "MERGE"; return }
  if (prog ~ /^deploy-fleet(\.sh)?$/ || (prog == "harbor" && nx == "ship"))
    for (j = i + 1; j <= n; j++) if (w[j] ~ /^--approved(=|$)/) { print "APPROVED"; return }
  if (prog ~ /^deploy(\.sh)?$/ || (prog == "harbor" && nx ~ /^(deploy|install|uninstall|skills|inject|constitution|restore)$/))
    for (j = i + 1; j <= n; j++) if (w[j] ~ /^--apply(=|$)/) { print "DEPLOY"; return }
  # an installer run straight at the live box skips the deploy preflight and snapshot: --live with a write (p30)
  if (prog ~ /(-install|^sec0-harden|^deploy-harden|^floor-deny|^floor-uninstall|^admission-deny|^admission-remove|^restore|^deploy-restore|^pin-instructions)(\.sh)?$/) {
    lv = 0; wr = 0
    for (j = i + 1; j <= n; j++) { if (w[j] == "--live") lv = 1; if (w[j] ~ /^--(apply|repin)(=|$)/) wr = 1 }
    if (lv && wr) { print "DEPLOY"; return } }
}
{ line = $0; gsub(/\$\(|`|&&|\|\||[;|&()]/, "\n", line); m = split(line, seg, "\n"); for (z = 1; z <= m; z++) judge(seg[z]) }'
# harbor#1420: a refusal that names a command the agent must guess re-blocks it, so the hint is built from the refused argv and runs as printed; a field argv lacks makes the whole hint fall back to words, never a placeholder.
GATE_HINT_AWK='function base(t) { sub(/.*\//, "", t); return t }
function seg(s,   n, w, i, j, a, tool, kind, repo, pr, sha, np, pos, sel, m, u) {
  gsub(/["\047\\]/, "", s); n = split(s, w, /[ \t]+/)
  if (mode == "gate") {
    for (i = 1; i <= n; i++) if (base(w[i]) == "gate-merge.sh" || base(w[i]) == "gate-approve.sh") break
    if (i > n) return
    tool = base(w[i]); repo = ""; pr = ""; sha = ""; kind = ""
    for (j = i + 1; j <= n; j++) { a = w[j]
      if (tool == "gate-approve.sh" && kind == "" && (a == "merge" || a == "deploy")) { kind = a; continue }
      if (repo == "" && a ~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/) { repo = a; continue }
      if (sha == "" && length(a) == 40 && a ~ /^[0-9a-f]+$/) { sha = a; continue }
      if (pr == "" && a ~ /^[0-9]+$/) { pr = a; continue } }
    if (tool == "gate-merge.sh" && repo != "" && pr != "") print tool " " repo " " pr
    else if (kind == "merge" && repo != "" && pr != "" && sha != "") print tool " merge " repo " " pr " " sha
    else if (kind == "deploy" && repo != "" && sha != "") print tool " deploy " repo " " sha
    return }
  for (i = 1; i <= n; i++) if (base(w[i]) == "gh") break
  if (i > n) return
  np = 0; repo = ""; pr = ""
  for (j = i + 1; j <= n; j++) { a = w[j]
    if (a == "-R" || a == "--repo") { repo = w[j + 1]; j++; continue }
    if (a ~ /^--repo=/) { repo = substr(a, 8); continue }
    if (a ~ /^-R./) { repo = substr(a, 3); continue }
    if (a ~ /^(-b|--body|-t|--subject|-F|--body-file|--match-head-commit|-A|--author-email|--hostname)$/) { j++; continue }
    if (a ~ /^-/) continue
    pos[++np] = a }
  if (pos[1] != "pr" || pos[2] != "merge") return
  sel = pos[3]
  if (sel ~ /^https?:\/\/[^\/]+\/[^\/]+\/[^\/]+\/pull\/[0-9]+/) {
    m = sel; sub(/^https?:\/\/[^\/]+\//, "", m); split(m, u, "/"); repo = u[1] "/" u[2]; pr = u[4]; sub(/[^0-9].*/, "", pr) }
  else if (sel ~ /^[0-9]+$/) pr = sel
  if (pr == "") return
  if (repo !~ /^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/) repo = "-"
  print repo " " pr }
{ line = $0; gsub(/\$\(|`|&&|\|\||[;|&()]/, "\n", line); m = split(line, sg, "\n"); for (z = 1; z <= m; z++) seg(sg[z]) }'
gate_cfg_phys() { _hc="$(floor_config_dir)"; CDPATH= cd -P -- "$_hc" 2>/dev/null && pwd -P || printf '%s\n' "$_hc"; }
# gate_gh_merge_args — `owner/repo pr` from the refused merge argv, the repo from origin when argv has none; else nothing.
gate_gh_merge_args() {
  _hrp="$(printf '%s\n' "$TARGETS" | awk -v mode=gh "$GATE_HINT_AWK" 2>/dev/null | head -1)"
  case "$_hrp" in
    '- '*)
      _horig="$(git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#/+$##; s#\.git$##')"
      case "$_horig" in
        */*/*|*[!A-Za-z0-9._/-]*|''|/*|*/) _hrp="" ;;
        */*) _hrp="$_horig ${_hrp#- }" ;;
        *) _hrp="" ;;
      esac ;;
  esac
  printf '%s\n' "$_hrp"
}
# gate_merge_hint — what a refused agent should run instead of a raw merge, resolved from its own argv.
gate_merge_hint() {
  _hcfg="$(gate_cfg_phys)"; _hargs="$(gate_gh_merge_args)"
  if [ -n "$_hargs" ]; then printf 'run exactly: %s/bin/gate-merge.sh %s' "$_hcfg" "$_hargs"
  else printf 'run %s/bin/gate-merge.sh with the repo as OWNER/REPO and the PR number as two arguments' "$_hcfg"; fi
}
# gate_canon_hint — the canonical spelling of a refused gate-tool command, or words when argv lacks a field.
gate_canon_hint() { # <cfg>
  _hg="$(printf '%s\n' "$TARGETS" | awk -v mode=gate "$GATE_HINT_AWK" 2>/dev/null | head -1)"
  if [ -n "$_hg" ]; then printf 'run exactly, alone: %s/bin/%s' "$1" "$_hg"
  else printf 'run %s/bin/gate-merge.sh OWNER/REPO PR_NUMBER, or %s/bin/gate-approve.sh merge OWNER/REPO PR_NUMBER SHA, or %s/bin/gate-approve.sh deploy OWNER/REPO SHA, alone' "$1" "$1" "$1"; fi
}
case "$TARGETS" in
  *gate-approve*|*gate-merge*|*merge*|*--apply*|*--approved*|*--repin*|*api*|*push*|*alias*|*default-branch*|*graphql*)
    _gv="$(printf '%s\n' "$TARGETS" | awk -v q="'" "$GATE_ROUTE_AWK" 2>/dev/null | sort -u)"
    case "$_gv" in
      *EXEC*|*COPY*)
        _gcfg="$(floor_config_dir)"; _gcfg="$(CDPATH= cd -P -- "$_gcfg" 2>/dev/null && pwd -P)" || _gcfg="$(floor_config_dir)"
        _grepo='[A-Za-z0-9._-]+/[A-Za-z0-9._-]+'
        _gcanon="^$(floor_ere_quote "$_gcfg")/bin/gate-(approve\\.sh (merge $_grepo [0-9]+ [0-9a-f]{40}|deploy $_grepo [0-9a-f]{40})|merge\\.sh $_grepo [0-9]+)\$"
        case "$_gv" in *COPY*) _gok=0 ;; *) _gok=1 ;; esac
        case "$CMD" in *"
"*) _gok=0 ;; esac
        _ghint="$(gate_canon_hint "$_gcfg")"  # the message holds no inner quote, which the rule-coverage scan reads
        [ "$_gok" = 1 ] && printf '%s' "$CMD" | "$FLOOR_GREP" -Eq -- "$_gcanon" \
          || floor_block bash "a gate tool runs only as the exact command its permission rule names, never wrapped, copied or linked: $_ghint" gate-noncanonical.argv
        # an ask is auto-approved where no human can answer it (floor_no_human): the click is the whole gate (harbor#1018)
        case "$CMD" in "$_gcfg"/bin/gate-approve.sh\ *) if floor_no_human; then
          floor_block bash "gate-approve.sh needs a person to click its permission prompt, and nobody can answer one in a subagent, a workflow or an autonomous mode: hand the approve command to the operator" gate-nohuman.argv
        fi ;; esac
        ;;
    esac
    case "$_gv" in *MERGE*)
      floor_block bash "a merge in a session goes through the approval gate, never gh pr merge, merge-check --merge or merge-stack merge, which queues a protected PR for the operator: $(gate_merge_hint)" merge-raw.argv
        ;;
    esac
    case "$_gv" in *APPROVED*)
      floor_block bash "--approved on the ship runner is the operator's click alone: only gate-approve.sh runs it, under a one-shot token; queue it with <cfg>/bin/gate-queue.sh add deploy <owner/repo> <sha> --reason <text>" approved-raw.argv
        ;;
    esac
    # a push straight to the default branch skips the PR: judged in the B5 block below, where a wired repo guard defers it
    case "$_gv" in *PUSHMAIN*) _GATE_PUSHMAIN=1 ;; esac
    case "$_gv" in *DEPLOY*)
      floor_block bash "a live deploy is never applied from a session: the unattended runner applies an unprotected one and the operator approves the rest (<cfg>/bin/gate-approve.sh deploy <owner/repo> <sha>); the dry run, deploy.sh --live, stays open" deploy-raw.argv
        ;;
    esac ;;
esac
# Interpreter escape hatches with a dangerous token. The flag test accepts BUNDLED forms (python3 -Ec, node --experimental -pe; red-team 2026-07-24).
# harbor#1420: the flat regex spans `&&` and `;`, so text naming `eval(` beside a harmless -c fired; the table acquits only when python's own argv is clean and every other segment is an inert text consumer.
_PYC_DANGER='([^A-Za-z0-9_.](exec|eval|compile)[[:space:]]*\(|__import__|import[[:space:],]+[^;)]*(socket|subprocess|pty|ctypes)|subprocess\.|os\.system|os\.popen|socket\.|pty\.spawn|shutil\.rmtree|open\([^)]*,[^)]*w)'
hit '(^|[^[:alnum:]_])python[0-9.]*([[:space:]]+-[A-Za-z]*)*[[:space:]]+-[A-Za-z]*c([[:space:]]).*'"$_PYC_DANGER" \
  && ! floor_seg_flat_clear '(/[a-zA-Z0-9_/.-]*/)?python[0-9.]*' "$_PYC_DANGER" \
  && floor_block bash "python -c invoking exec/subprocess/socket, or opening a file for write" python-c-exec.flat
hit '(^|[^[:alnum:]_])(node|nodejs)([[:space:]]+-[A-Za-z-]*)*[[:space:]]+-[A-Za-z]*e([[:space:]]).*(child_process|require\(.?child|[^A-Za-z0-9_.](exec|eval)[[:space:]]*\(|net\.|writeFileSync|unlinkSync|rmSync)' \
  && floor_block bash "node -e invoking child_process/net/eval" node-e-exec.flat
hit '(^|[^[:alnum:]_])(ruby|perl)([[:space:]]+-[A-Za-z]*)*[[:space:]]+-[A-Za-z]*e([[:space:]]).*(system|exec|`|IO\.popen|open\()' \
  && floor_block bash "ruby/perl -e invoking system/exec" ruby-perl-e-exec.flat
hit '(^|[^[:alnum:]_])php([[:space:]]+-[A-Za-z]*)*[[:space:]]+-[A-Za-z]*r([[:space:]]).*(system|exec|passthru|shell_exec|proc_open|popen)' \
  && floor_block bash "php -r invoking system/exec" php-r-exec.flat
# Docker host-takeover
hit '(^|[^[:alnum:]_])docker[^|]*(--privileged|(-v|--volume)([[:space:]]+|=)/:|(-v|--volume)([[:space:]]+|=)(\$HOME|~|/):)' \
  && floor_block bash "docker --privileged or host-root/\$HOME bind-mount" docker-privileged.flat
# MUTATING PIPE INTO xargs: a former rule was removed as provably dead (harbor#280): its block condition was a strict subset of find-xargs-spray, which runs first. `cat list | xargs chmod 777` and `find / -name x | xargs rm -rf` still block, as find-xargs-spray and dd-to-device.

# ── Floor self-protection via the Bash tool ── guard-selfedit sees only Write|Edit|MultiEdit and permissions.deny binds the NAMED tool, so a redirect, `sed -i`, `cp`, `tee` or heredoc through Bash could rewrite settings.json or truncate a guard (red-team 2026-07-24); any Bash mutation aimed at a floor control surface is denied here.
# A config-dir reference in ANY spelling: anchored on the ACTUAL config dirs (the directory component, so relative spellings after a cd are covered), never on a bare `.claude` component, which made every project's own .claude/ a floor surface (red-team pass 5).
CFG_ABS="$(floor_canon_dir "$(floor_config_dir)")"   # the spelling floor_seg_* compare in (harbor#754)
# The same dir ESCAPED FOR USE INSIDE A RULE (P12-configdir-ere-injection-03): CFG_ABS is a path, these are the regex spellings; an unbalanced metacharacter in CLAUDE_CONFIG_DIR would invalidate every expression and switch the surface rules off silently (see floor_ere_quote).
CFG_ABS_RE="$(floor_surface_re "$(floor_config_dir)")"
# The live dir as a PATH, not a regex (floor_seg_cwd_under compares resolved paths), in lint D1's blessed `LIVE_DIR=` idiom: it names the dir in order to REFUSE writes to it.
# Separate from CFG_ABS because CLAUDE_CONFIG_DIR can point the guard at a sandbox while ~/.claude is still loaded into every session.
LIVE_DIR="$HOME/.claude"
# One unit, so HOME=/ reads `/.claude`, never `//.claude` (harbor#758).
LIVE_RE="$(floor_surface_re "$LIVE_DIR")"
LIVE_DIR="$(floor_canon_dir "$LIVE_DIR")"
# `~<name>/.claude` rides along with the rm fix above: a second account's floor on a shared host (pass 13).
TILDE_CFG="${TILDE_USER}/\\.claude"
CFG_RE="(${CFG_ABS_RE}|${LIVE_RE}|~/\\.claude|${TILDE_CFG}|\\\$HOME/\\.claude|\\\$\\{HOME\\}/\\.claude)/+"
# Why each surface is here: `.helm-pins/` (the per-guard content pins that let B6 notice a gutted guard) and the B8 instruction pin are named in permissions.deny, but deny binds the Write/Edit TOOLS, not a `>` inside a Bash call (red-team B7/B8).
# `.helm-peers/` is RENDERED INTO ANOTHER SESSION'S SYSTEM CONTEXT (harbor#75; pass 13, P13-peer-04). CLAUDE.md is the constitution loaded into every session: fetched content that rewrote it would be obeyed by all later sessions (2026-08-03).
# BLAST RADIUS IS THE CONFIG DIR ONLY: CFG_RE never anchors on a bare `.claude`, so a project's own .claude/CLAUDE.md stays writable. READS STAY OPEN: every rule anchored on SURFACE is a WRITE shape, and a guard that stopped an agent reading the constitution would be a false positive against it.
# harbor#779: every integrity row of contracts/control-plane-state.md and nothing else (lint F14 holds this line to the table). harbor#1044 review r3 #1: .helm-dispatch is a row; .harbor-autoship.off, the ship contract's kill switch, is not a .helm-* name but is here because deleting it lifts the switch.
FILES="(settings(\\.local)?\\.json|CLAUDE(\\.local)?\\.md|\\.sec0-baseline\\.sha256|\\.helm-baseline|\\.helm-snapshots|\\.helm-floor-teeth|\\.helm-log-token|\\.helm-instructions\\.sha256|\\.helm-apiroute-allow|\\.helm-apiroute(/[^[:space:];&|]*)?|\\.helm-pins(/[^[:space:];&|]*)?|\\.helm-peers(/[^[:space:];&|]*)?|\\.helm-govern-salt|\\.helm-obs-salt|\\.helm-obs-host|\\.helm-install-stamp|\\.helm-judge|\\.helm-context(/[^[:space:];&|]*)?|\\.helm-stop-gate(/[^[:space:];&|]*)?|\\.helm-dispatch(/[^[:space:];&|]*)?|\\.helm-approvals(/[^[:space:];&|]*)?|\\.helm-ship(/[^[:space:];&|]*)?|\\.harbor-autoship\\.off)"
# The config DIRECTORY is a surface in its own right: verbs writing INTO it with an implicit basename were invisible (`cp /tmp/settings.json ~/.claude/`, `mv ~/.claude/bin ~/.claude/bin.off`; red-team pass 5).
# harbor#772: deploy snapshots carry their own pins, so a rewritten one restores a weakened floor; top level only, never `*backups*`.
CFG_SNAPDIR=backups
CFGDIR_RE="(${CFG_ABS_RE}|${LIVE_RE}|~/\\.claude|${TILDE_CFG}|\\\$HOME/\\.claude|\\\$\\{HOME\\}/\\.claude)(/+(bin|hooks|${CFG_SNAPDIR})/*)?"
# No bare `./settings.json` alternative: it had no config-dir anchor, so any project's root settings.json was protected (red-team pass 4).
# CI WORKFLOW FILES ARE A SURFACE TOO (harbor#88): permissions.deny binds TOOLS, so a heredoc, `>>`, `sed -i` or `cp` through Bash reached them unseen, and they protect the gate that judges the agent.
# Added to SURFACE rather than as new rules so every verb family anchored on SURFACE covers them at once; reads stay untouched.
WORKFLOW_RE="[^[:space:];&|]*\\.github/+workflows/+[^[:space:];&|]*"
# P13-fs-05 (harbor#94): the bin/ arm enumerated names (`guard-|floor-`) while hooks/ protected its directory wholesale, so a write to <cfg>/bin/context-resolve.sh (wired at SessionStart and PostToolUse: code on every edit) exited 0.
# The enumeration is replaced by the shape `bin/+`: nothing under <cfg>/bin is a session's to write through Bash; installers run from the operator's terminal and reads stay allowed (harbor#107's veto is downstream).
# harbor#1181: the observability ledgers are the record of what the floor decided, so every write verb is refused under MEMORY/OBSERVABILITY (prefix-matched; the rest of MEMORY stays session-writable). Only hooks write there. Same-uid accident guard only: docs/design/telemetry.md.
OBS_SURFACE="${CFG_RE}MEMORY/+OBSERVABILITY"
SURFACE="(${CFG_RE}[^[:space:];&|]*${FILES}|${CFG_RE}[^[:space:];&|]*(bin/+|hooks/+)|${CFG_RE}${CFG_SNAPDIR}/+|${OBS_SURFACE}|${WORKFLOW_RE})"
# harbor#776: `cd ~ && echo {} > .claude/settings.json` named no surface; the fold re-spells each segment a cd points into a config dir, and every rule below reads it beside the raw one.
_FOLD=""
case "${FLOOR_SEGS:-}" in   # a builtin gate: no cd, no subshell fork on the hot path
  *cd*|*pushd*|*popd*) _FOLD="$(floor_seg_cd_fold "$CFG_ABS" "$LIVE_DIR" "+$CFG_ABS/$CFG_SNAPDIR" "+$LIVE_DIR/$CFG_SNAPDIR" +/etc/crontab +/etc/cron.d +/var/spool/cron +/etc/profile +/etc/zshrc)" ;;  # harbor#1313: cd /etc then a relative crontab/rc write
esac
if [ -n "$_FOLD" ]; then
  TARGETS="$TARGETS
$(printf '%s\n' "$_FOLD" | sed -n 's/^FOLD://p')"
  FLOOR_SEGS="$FLOOR_SEGS
$(printf '%s\n' "$_FOLD" | sed -n '/^SEG/p')"
  # harbor#1313: the startup/scheduler rules ran above, before this fold; a relative write after `cd /etc` re-reads them.
  hit "(>[|!&]?|>>!?)[[:space:]]*[^[:space:];&|]*$SCHED" \
    && floor_block bash "writing a launchd/systemd/cron unit schedules code outside any guard" unit-file-write.flat
  hit "(>[|!&]?|>>!?)[[:space:]]*[^[:space:];&|]*$RCFILE" \
    && floor_block bash "shell startup files are executed by every later session — writing one is a code-execution sink, not a file edit" startup-file-write.flat
fi
hit "(>[|!&]?|>>!?)[[:space:]]*$SURFACE" \
  && floor_block bash "shell redirect writing to a Helm floor control surface" redirect-floor-surface.flat

# ── harbor#107 · A SINK PROGRAM'S NAME IS NOT A SINK ── the two sink rules are FLAT regexes, so they fired on the WORD even as a search term handed to something that never writes (`grep -c sponge <guard file>` blocked, `grep -c hello` allowed), hardest when auditing the floor (§2.11).
# Not a flat inert list: inertness is rule-dependent (harbor#90), so this veto is scoped to the write-sink rules and consults the segment table, as admission-egress.sh's seg_all_inert does.
SEG_NOWRITE='(^|/)(grep|egrep|fgrep|rg|ag|cat|head|tail|less|more|wc|cmp|diff|file|stat|nl|od|xxd|strings|echo|printf|true|false|:|ls)$'
# `ls` (harbor#788): it opens nothing for writing; outflag's bundle read made `ls -lo <surface>` look like `-o <surface>`. ABSENT ON PURPOSE: sed, awk, perl, python, jq, tee, sponge, dd can open a file for writing. An UNKNOWN command word fails to match, the veto is withdrawn, and the flat rule decides.
# NOT EXTENDED FOR find (P13-fs-06): adding it was dead, because the flat line the normalizer emits for a find child follows the DATA variant's message model, so a grep child emits no flat line and nothing was left to veto; removing it changed no assertion.
# ── harbor#164 · A READ-ONLY git SUBCOMMAND IS A READER ── `git` cannot go in $SEG_NOWRITE, so every git segment withdrew the veto and `git grep -n <interpreter> -- <workflow>` blocked. The floor never modelled a git write, so the rule paid a false positive on reads for nothing; the git-write hole is real, NOT fixed here, tracked separately.
# THE SUBCOMMAND IS PARSED CONSERVATIVELY and any doubt means not read-only: global flags may precede it (`git -C /tmp grep`), so it is the first argument that is neither a flag nor the value of a value-taking global flag; an unrecognised shape falls through to the slow, correct path.
# -c IS REFUSED OUTRIGHT: `git -c core.pager=<command> grep` turns a read into execution, so a segment carrying -c, --config-env or --exec-path is never read-only. It is a grep over the args, independent of the subcommand parse.
# ONE PARSE, TWO READERS (harbor#265): the read side and the git-write rule below share one subcommand resolution so a global flag cannot be added to one and not the other. It sets variables rather than printing (a command substitution is a fork per git segment, and a timed-out hook fails OPEN, P12-perf-04).
# CONTRACT: sets GIT_SUBCMD ('' when none resolves) and GIT_SEGARGS (one argument per line); neither caller may assume anything else survives.
_git_seg_subcmd() { # <segment-id> -> sets GIT_SUBCMD + GIT_SEGARGS
  GIT_SEGARGS="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:$1://p")"
  GIT_SUBCMD=''; _gskip=0
  for _ga in $GIT_SEGARGS; do
    if [ "$_gskip" = 1 ]; then _gskip=0; continue; fi
    case "$_ga" in
      -C|--git-dir|--work-tree|--namespace|--super-prefix) _gskip=1; continue ;;
      -*) continue ;;
      # `-c <k>=<v>` and `--config-env <k>=<v>` put their VALUE in its own token; skipping key=value (no git subcommand contains `=`) keeps `git -c x=y checkout <surface>` resolving to `checkout`, so it blocks on the write side (harbor#265).
      *=*) continue ;;
      *)  GIT_SUBCMD="$_ga"; break ;;
    esac
  done
}
_git_seg_is_ro() { # <segment-id> -> 0 iff this git segment cannot write
  _git_seg_subcmd "$1"
  # Config and exec-path injection: a read subcommand is not a read any more.
  if printf '%s\n' "$GIT_SEGARGS" | "$FLOOR_GREP" -Eq '^(-c|--config-env|--exec-path)(=|$)'; then return 1; fi
  case "$GIT_SUBCMD" in
    grep|show|log|diff|blame|cat-file|ls-files|ls-tree|rev-parse|status|describe|shortlog|whatchanged) return 0 ;;
    *) return 1 ;;
  esac
}

seg_all_nowrite() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  # harbor#776 — a cd writes nothing; counted, it made `cd ~ && grep tee .claude/bin/x` a write.
  _snc="$(printf '%s\n' "$FLOOR_SEGS" | sed -E -n -e '/^SEGC:[0-9]+:([^[:space:]]*\/)?(cd|pushd|popd)$/d' -e 's/^SEGC:[0-9]+://p')"
  [ -n "$_snc" ] || return 1
  # The fast path (one grep over every command word) still runs first: per-segment forks took an 8KB payload 10s (P12-perf-04), past the hook timeout, and a hook that times out fails OPEN. Per-segment work is reached only when git is why the fast path failed.
  _snbad="$(printf '%s\n' "$_snc" | "$FLOOR_GREP" -Ev -- "$SEG_NOWRITE" 2>/dev/null)"
  if [ -n "$_snbad" ]; then
    # Anything that is not a reader and not git withdraws the veto immediately.
    printf '%s\n' "$_snbad" | "$FLOOR_GREP" -Evq '^([^[:space:]]*/)?git$' && return 1
    for _snid in $(printf '%s\n' "$FLOOR_SEGS" \
                   | sed -n 's/^SEGC:\([0-9]*\):\([^[:space:]]*\/\)\{0,1\}git$/\1/p'); do
      _git_seg_is_ro "$_snid" || return 1
    done
  fi
  # AN OUTPUT REDIRECT ONTO A SURFACE WITHDRAWS THE VETO (redirect-floor-surface already blocks it above; belt and braces). Scoped to the TARGET: withdrawing on any redirect would restore the false positive for `grep -c sponge <surface> > /tmp/out`.
  if printf '%s\n' "$FLOOR_SEGS" \
     | "$FLOOR_GREP" -E '^SEGR:[0-9]+:&?[0-9]*>>?[|!&]?:' 2>/dev/null \
     | sed -n 's/^SEGR:[0-9]*:[^:]*://p' \
     | "$FLOOR_GREP" -Eq -- "$SURFACE"; then return 1; fi
  return 0
}
SINK_RO=0; seg_all_nowrite && SINK_RO=1

# ── harbor#265 · git RESTORES A CONTROL SURFACE AND NO RULE FIRED ── `git checkout <workflow>`, `git restore <workflow>` and `git checkout HEAD~5 -- <workflow>` changed a surface while a redirect onto the same path blocked (measured 2026-08-22/23).
# PATH-SCOPED, NEVER VERB-SCOPED: a verb rule would fire on `git checkout main`, many times an hour (§2.11), so the surface must appear in ARGUMENT position in the same segment. The suite pins as allowed: checkout main, checkout -b, switch main, restore <ordinary path>, status, git grep.
# THREE SUBCOMMANDS, ON PURPOSE: checkout, restore and checkout-index write the path they are GIVEN. The others would add a rule that cannot fire or inverts a read into a write (harbor#280): `switch` takes a branch, `apply` writes the paths inside the patch, `read-tree` writes the index.
# NOT CAUGHT, because they name no surface: `git checkout -- .`, `git stash pop`, `git reset --hard`; `git clean -fdx` is decided `ask` by admission-destroy.sh.
# THE -c BYPASS IS CLOSED BY PARSING, NOT SUSPICION: refusing any -c/--config-env/--exec-path segment re-introduced the harbor#164 false positive on `git -c core.pager=id grep`. The parse fix (`*=*` in _git_seg_subcmd) makes `git -c x=y checkout <surface>` resolve to `checkout`; -c as an execution channel applies to every git subcommand and is not this rule's business.
git_write_at_surface() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  # harbor#265 + harbor#804: two writes a redirect rule cannot see: (1) a checkout/restore/checkout-index whose PATHSPEC names a surface, and (2) a working-tree write (checkout/switch/restore/checkout-index, reset --hard/--merge/--keep, clean -f, stash pop/apply/push) whose EFFECTIVE TREE is the config dir or a surface subtree,
  # reached by cd/pushd, -C, --work-tree or --git-dir. The cd chain is folded as floor_seg_cwd_under folds it; read subcommands and a write in a PROJECT tree stay allowed; an unknown location (no cd, no -C) is fail-open.
  { printf 'EXACT:%s\n' "$CFG_ABS" "$LIVE_DIR"
    printf 'SUB:%s\n'   "$CFG_ABS/bin" "$CFG_ABS/hooks" "$CFG_ABS/$CFG_SNAPDIR" \
                        "$LIVE_DIR/bin" "$LIVE_DIR/hooks" "$LIVE_DIR/$CFG_SNAPDIR"
    printf 'SURF:%s\n'  "$SURFACE"
    printf '%s\n' "$FLOOR_SEGS"
  } | awk -v home="$HOME" '
    # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
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
    # tree_hit(T): a whole-tree write standing at T rewrites a floor surface — T is the config/live
    # dir itself (settings.json, CLAUDE.md, the .helm-* files live directly there) or is at-or-below
    # its bin/hooks/backups. A writable subtree such as <cfg>/MEMORY is NOT a surface (S7).
    function tree_hit(T,   i) {
      if (T == "") return 0
      for (i = 1; i <= nx; i++) if (T == EX[i]) return 1
      for (i = 1; i <= ns; i++) if (T == SB[i] || index(T, SB[i] "/") == 1) return 1
      return 0
    }
    # path_hit(op, T): a pathspec op names a surface, as spelled (absolute/workflow) or resolved
    # against the effective tree T.
    function path_hit(op, T,   P) {
      if (op ~ SURF) return 1
      P = resolve(op, T)
      return (P != "" && P ~ SURF)
    }
    /^EXACT:/ { d = substr($0, 7); sub(/\/+$/, "", d); if (d != "") EX[++nx] = d; next }
    /^SUB:/   { d = substr($0, 5); sub(/\/+$/, "", d); if (d != "") SB[++ns] = d; next }
    /^SURF:/  { SURF = substr($0, 6); next }
    /^SEGC:/  { n = $0; sub(/^SEGC:/, "", n); sub(/:.*/, "", n)
                v = $0; sub(/^SEGC:[0-9]+:/, "", v); C[n + 0] = v; if (n + 0 > MAX) MAX = n + 0; next }
    /^SEGA:/  { n = $0; sub(/^SEGA:/, "", n); sub(/:.*/, "", n)
                v = $0; sub(/^SEGA:[0-9]+:/, "", v); A[n + 0] = A[n + 0] "\n" v; if (n + 0 > MAX) MAX = n + 0; next }
    END {
      if (SURF == "") exit 1
      cwd = ""; hit = 0
      for (k = 1; k <= MAX && !hit; k++) {
        w = C[k]; if (w == "") continue
        base = w; sub(/.*\//, "", base)
        if (base == "popd") { cwd = ""; continue }
        if (base == "cd" || base == "pushd") {
          t = ""; got = 0; m = split(A[k], ar, "\n")
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
        if (base != "git") continue
        # Location flags, then the subcommand. -C stacks a directory (each relative to the last),
        # --work-tree overrides the tree, --git-dir/-c/… are consumed so the verb resolves.
        m = split(A[k], ar, "\n"); gcwd = cwd; wt = ""; scmd = ""; si = 0; j = 1
        while (j <= m) {
          ag = ar[j]
          if (ag == "") { j++; continue }
          if (ag == "-C") { if (j < m) gcwd = resolve(ar[j + 1], gcwd); j += 2; continue }
          if (ag ~ /^--work-tree=/) { wt = substr(ag, 13); j++; continue }
          if (ag == "--work-tree")  { if (j < m) wt = ar[j + 1]; j += 2; continue }
          if (ag == "--git-dir" || ag == "--namespace" || ag == "--super-prefix" || ag == "-c" || ag == "--config-env") { j += 2; continue }
          if (substr(ag, 1, 1) == "-") { j++; continue }
          scmd = ag; si = j; break
        }
        if (scmd == "") continue
        T = (wt != "") ? resolve(wt, gcwd) : gcwd
        seendd = 0; nop = 0; hard = 0; force = 0; stashsub = ""
        for (j = si + 1; j <= m; j++) {
          ag = ar[j]; if (ag == "") continue
          if (ag == "--") { seendd = 1; continue }
          if (!seendd && substr(ag, 1, 1) == "-") {
            if (ag == "--hard" || ag == "--merge" || ag == "--keep") hard = 1
            if (ag ~ /^-[a-zA-Z]*f/ || ag == "--force") force = 1
            continue
          }
          nop++; OP[nop] = ag
          if (stashsub == "") stashsub = ag
        }
        if (scmd == "checkout" || scmd == "switch" || scmd == "restore" || scmd == "checkout-index") {
          for (j = 1; j <= nop; j++) if (path_hit(OP[j], T)) { hit = 1; break }
          if (!hit && (scmd == "checkout" || scmd == "switch") && !seendd && tree_hit(T)) hit = 1
        } else if (scmd == "reset") {
          if (hard && tree_hit(T)) hit = 1
        } else if (scmd == "clean") {
          if (force && tree_hit(T)) hit = 1
        } else if (scmd == "stash") {
          if ((stashsub == "" || stashsub == "pop" || stashsub == "apply" || stashsub == "push" || stashsub == "save") && tree_hit(T)) hit = 1
        }
      }
      exit (hit ? 0 : 1)
    }'
}
# The `case` gate is a builtin, so a command with no `git` in it costs zero forks. THE `;;` GOES ON ITS OWN LINE for lint F5, which requires the call to END at its id (at most one `;`); widening F5 to accept `;;` would weaken the gate to fit the code.
case "$CMD" in
  *git*)
    git_write_at_surface \
      && floor_block bash "git is restoring a Helm floor control surface from the index or a commit — a write no redirect rule can see" git-write-at-surface.path
    ;;
esac
# harbor#797 — a bind mount hands the container its source read-write, read-only flag or not:
# binding a surface, the config dir or a dir above it is a write no redirect rule can see.
case "$CMD" in
  *[dD][oO][cC][kK][eE][rR]*|*[pP][oO][dD][mM][aA][nN]*)
    _BANC="$( { _d="$CFG_ABS"; while _d="${_d%/*}"; [ -n "$_d" ]; do printf '%s\n' "$_d"; done
                _d="$LIVE_DIR"; while _d="${_d%/*}"; [ -n "$_d" ]; do printf '%s\n' "$_d"; done; } \
              | sort -u | sed 's/[][\\^$.*+?(){}|]/\\&/g' | tr '\n' '|')"
    _BSRC="(${CFGDIR_RE}/*|${CFG_RE}[^[:space:];&|:]*(${FILES}|(bin|hooks|${CFG_SNAPDIR})/+[^[:space:];&|:]*)|(${_BANC}~|\\\$HOME|\\\$\\{HOME\\})/*|/+|[^[:space:];&|:]*\\.github/+workflows(/+[^[:space:];&|:]*)?)"
    [ "$SINK_RO" = 0 ] \
      && { hit "(^|[^[:alnum:]_])(docker|podman)[^;&|]*[[:space:]](-[a-zA-Z]*v|--volume)([[:space:]]+|=)?${_BSRC}:" \
           || hit "(^|[^[:alnum:]_])(docker|podman)[^;&|]*[[:space:]]--mount([[:space:]]+|=)([^[:space:]]*,)?(source|src)=${_BSRC}(,|[[:space:]]|\$)"; } \
      && floor_block bash "a container bind-mounts a Helm floor control surface, the config dir or a dir above it — the container can rewrite it" container-bind-surface.flat
    ;;
esac
# harbor#788 — harbor#289's left anchor, for the absolute-path rules too: a verb after a dash is a
# flag cluster or a filename (`ls -ln <cfg>/bin`, `ls <cfg>/a-ln …`), unless it is git's dashed alias.
# `--` stays a boundary (it no longer carries the `docker run --rm -v <surface>` block: harbor#797).
_VERBL='(^|[^[:alnum:]_-]|--)(git-)?'
# cp/mv/install/rsync: only a surface in DESTINATION position is a mutation (copying one OUT is a backup). The destination is the LAST argument, so match a surface that runs to the end of its segment, including the rest of the operand token.
[ "$SINK_RO" = 0 ] \
  && hit "${_VERBL}(cp|mv|install|rsync)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-][^[:space:];&|]*[[:space:]][^;&|]*$SURFACE" \
  && floor_block bash "a file-mutating command is writing ONTO a Helm floor control surface" mutate-onto-surface.flat
# `sponge` BELONGS WITH tee: it reads stdin, then WRITES ITS ARGUMENT, and was named only inside the jq rule, so a surface named only AFTER sponge was invisible (measured 2026-08-03: `curl ... | sponge ~/.claude/settings.json` put REMOTE CONTENT onto the deny list past pipe-to-shell and redirect-floor-surface).
# The rule fires on the SURFACE, not the verb, so `| sponge /tmp/scratch.json` stays allowed.
# harbor#794: `touch` too — session-verdicts.sh and REF-7 trust mtimes, and it creates a missing file.
[ "$SINK_RO" = 0 ] \
  && hit "${_VERBL}(tee|sponge|truncate|ln|link|chmod|chown|chgrp|chflags|setfacl|rm|shred|mv|rename|touch)([[:space:]]+-[^[:space:]]+)*[[:space:]][^;&|]*$SURFACE" \
  && floor_block bash "file-mutating command aimed at a Helm floor control surface" mutate-aimed-surface.flat

# P13C-4: chmod 000 <cfg>/bin makes every hook fail to start, and a hook that cannot start fails OPEN. The surface rule above needs a file or a trailing `/`, so the bare directory, the config dir and any directory above it walked; any mode, any owner, no -R needed.
case "$CMD" in
  *[cC][hH][mM][oO][dD]*|*[cC][hH][oO][wW][nN]*|*[cC][hH][gG][rR][pP]*|*[cC][hH][fF][lL][aA][gG][sS]*|*[sS][eE][tT][fF][aA][cC][lL]*)
    _PERM_T="$( { for _d in "$CFG_ABS" "$LIVE_DIR"; do
                    printf '%s\n' "$_d" "$_d/bin" "$_d/hooks" "$_d/$CFG_SNAPDIR"
                    while _d="${_d%/*}"; [ -n "$_d" ]; do printf '%s\n' "$_d"; done
                  done; } | sort -u | sed 's/[][\\^$.*+?(){}|]/\\&/g' | tr '\n' '|')"
    floor_seg_has '^([a-zA-Z0-9_./-]*/)?(chmod|chown|chgrp|chflags|setfacl)$' "^(${_PERM_T%|}|/|~)/*\$" \
      && floor_block bash "a permission or ownership change on the config dir, its bin/ or hooks/, or a directory above it — a hook that cannot start fails open" perm-onto-surface.argv
    ;;
esac

# ── harbor#196 / P13-fs-03 · AN OUTPUT-DESTINATION FLAG WHOSE VALUE IS A SURFACE ── `curl -o`, `sort -o` and `openssl enc -out` onto a guard were allowed beside a blocked redirect (2026-08-16): curl/wget were named only in fetch-then-EXECUTE rules, and B6 reports the altered guard only at the NEXT SessionStart (detection, never containment).
# NO VERB IS NAMED (harbor#196, harbor#94's replace-a-list-with-a-shape): the shape catches gcc/ld/objcopy/plutil/xz/ffmpeg -o and whatever ships next. TWO THINGS KEEP READS OPEN: $SINK_RO (harbor#107's veto; `grep -o <guard file>` searches for the path as a PATTERN)
# and POSITION (floor_seg_flagval asks whether the surface is the VALUE of the flag, so `curl <url> -o /tmp/x` and `cat <guard>` stay allowed).
# THE FLAG LIST IS A SPELLING TABLE of how the UNIX world says "write your output here"; `-O` is wget's (curl's takes no value). DELIBERATELY ABSENT: `--file`/`-f` (read flags: grep --file, awk -f, make -f), `-w` (curl format string, grep word-match), `-of` (ffmpeg format), and dd of= (left to the flat dd rule: `of` is a bare word).
OUTFLAG='^(-o|-O|--output|--output-file|--output-document|--outfile|-out|--out|--out-file)$'
# harbor#788 — `--short` reads a bundle as getopt does: `curl -so <surface>`, `-sSLo`, `-o<surface>`.
[ "$SINK_RO" = 0 ] \
  && floor_seg_flagval '.*' "$OUTFLAG" "$SURFACE" --short \
  && floor_block bash "an output-destination flag is writing onto a Helm floor control surface" outflag-onto-surface.argv
# P13C-5, the DIRECTORY spelling: `curl --output-dir <cfg>/bin -O <url>/admission-bash.sh` and `wget -P <cfg>/bin <url>` name only the directory. `-P` is wget's alone; the long spellings are unambiguous in any tool.
_OUTDIR_V="^${CFGDIR_RE}/*\$"
[ "$SINK_RO" = 0 ] \
  && { floor_seg_flagval '.*' '^(--output-dir|--directory-prefix|--target-directory)$' "$_OUTDIR_V" \
       || floor_seg_flagval '^([a-zA-Z0-9_./-]*/)?wget2?$' '^(-P)$' "$_OUTDIR_V" --short; } \
  && floor_block bash "an output-directory flag is writing into the config dir, its bin/ or hooks/" outdir-onto-surface.argv
# ARCHIVE EXTRACTORS write arbitrary paths under a root given by a FLAG (pass 10: `tar -x -C ~/.claude -f evil.tar`; also `unzip -d`, `patch -d`, `cpio -D`, `ditto`). tar needs an explicit extract flag (`tar -cf backup.tar ~/.claude` only READS).
# COMMAND POSITION, not "the word appears somewhere" (pass 11): `tar xzf e.tgz -C ~/.claude`, the dominant spelling, walked past a leading-dash demand, and `grep -n patch ~/.claude/CLAUDE.md` was blocked as extraction. $CMDPOS is defined once, with the scheduler rules (harbor#92).
# ── harbor#111 · -O IS NOT AN EXTRACTION ── `tar xzOf <archive> <member>` writes to STDOUT. The segment path lets it through; the FLAT path, the only one when the tokenizer bails, could not, so reading the floor to check the floor blocked.
# THE ANCHOR IS THE WHOLE FIX: the bundle is matched only immediately after the tar verb, where an operand cannot appear, because a bare `-?[a-zA-Z]*O[a-zA-Z]*` would read a MEMBER NAME as outbound. Uppercase O only (GNU -o is no-same-owner). Residual: `tar -xf a.tgz --to-stdout -C <cfg>` still blocks, a false positive that fails SAFE.
TAR_XNOO='([[:space:]]+(-?[a-np-zA-NP-Z]{0,4}x[a-np-zA-NP-Z]{0,4}|--(extract|get))([[:space:]]|=|$))'
# MIGRATED TO ARGV, 2026-07-25 (B-rewrite stage 2, the first rule moved). The flat form needed a hand-built command-position anchor, a length-bounded flag bundle and a `[^;&|]*` span, three approximations that each broke once. Now: a segment whose COMMAND is tar, with an extract flag among its ARGS and an argument (or redirect target) inside the config dir.
# So `tar xzf e.tgz -C ~/.claude` and `tar -x -C ... -f` are one rule, `patch` as an argument of grep cannot match, `tar -tf a.tar; cp x ~/.claude` is two segments (floor_seg_has needs ONE segment to satisfy every pattern), and `sudo tar` needs no wrapper clause. `tar -cf backup.tar ~/.claude` still passes. The extract flag is a WHOLE token.
CFG_TOK="(${CFG_ABS_RE}|${LIVE_RE}|~/\\.claude|${TILDE_CFG}|\\\$HOME/\\.claude|\\\$\\{HOME\\}/\\.claude)(/|\$)"
# ONE dash for a letter bundle, two only for the long options: `-{0,2}` let `--xz` (a compression selector) read as extract (pass 12, P12-argv-fp-04); `--get` is GNU tar's third spelling of extract (P12-argv-08).
# THE BUNDLE IS NOT LENGTH-BOUNDED (docs/explanation/admission-baseline.md P12-argv-10): `tar -xvvvzf a.tgz -C ~/.claude` was not recognised, scored read-only and bought the exemption that skips all four archive rules. THE DIRECTION IS TOWARD BLOCKING: a token matching TAR_XTOK clears _ARCH_RO, so a wider match exempts LESS.
TAR_XTOK='^(-?[a-zA-Z]*x[a-zA-Z]*|--(extract|get)(=.*)?)$'
EXTRACTOR='^([a-zA-Z0-9_./-]*/)?(unzip|ditto|patch|cpio|pax)$'
ARCHCMD='^SEGC:[0-9]+:([a-zA-Z0-9_./-]*/)?(tar|bsdtar|gtar|unzip|ditto|cpio|pax|patch)$'

# ── ARCHIVE MODE AND DIRECTION (pass 13) ── The four rules below fire when an archive verb NAMES the config dir, but naming is not writing: the operator's own backup-and-restore path (`unzip -l`, `tar -xzf <backup> -C /tmp/restore`, `ditto ~/.claude /tmp/backup`) was refused end to end, while B6's own block message sends the operator to deploy-restore.sh. A control that forbids the recovery it prescribes gets turned off (§2.11).
# Two questions separate a backup from an overwrite. MODE: `tar -t`, `tar -c`, `unzip -l/-t`, `cpio -t` and bare `pax` cannot create a file, so the config dir in their argv is a SOURCE. DIRECTION: the config dir has to be the DESTINATION (tar `-C`, unzip `-d`, cpio `-D`, ditto's LAST operand: argv position, not string presence).
# EVERYTHING UNPROVEN BLOCKS: an EMPTY segment table (oversized payload, missing awk, an operand the tokenizer cannot see: the flat rules exist for those shapes); NO destination in argv (the cwd, which this hook is not told, and may be the config dir); and `patch`, which reconstructs its targets from the diff body and is never exemptible.
# arch_dests <letter> <long-ERE> <dashless-first-arg 0|1> - every destination argv names, one per line, from args on stdin: `-C dir`, a bundle whose LAST letter is the option (`tar -xzC dir`), `--directory dir` and `--directory=dir`. ALL of them, not the last: tar honours `-C` repeatedly. NOT case-folded: tar's `-c` (create) and `-C` (chdir) differ.
# THE DASHLESS BUNDLE IS NOT OPTIONAL: `tar xzC ~/.claude -f /tmp/evil.tgz` has no leading dash (pass 11, critical). It is accepted ONLY as the FIRST argument, which is tar's own constraint; anywhere else a member named `C` would manufacture a destination and buy an exemption.
arch_dests() { # <letter> <long-name-ERE> <dashless-first-arg 0|1>
  _adl="$1"; _adlong="$2"; _adbare="${3:-0}"; _adtake=0; _adn=0
  while IFS= read -r _adt; do
    [ -n "$_adt" ] || continue
    _adn=$((_adn + 1))
    if [ "$_adtake" = 1 ]; then printf '%s\n' "$_adt"; _adtake=0; continue; fi
    if [ "$_adbare" = 1 ] && [ "$_adn" = 1 ]; then _adre="^(-?[A-Za-z]*${_adl}|${_adlong})\$"
    else _adre="^(-[A-Za-z]*${_adl}|${_adlong})\$"; fi
    case "$_adt" in
      --*=*)
        if printf '%s' "$_adt" | "$FLOOR_GREP" -Eq -- "^($_adlong)="; then
          printf '%s\n' "${_adt#*=}"
        fi ;;
      *)
        if printf '%s' "$_adt" | "$FLOOR_GREP" -Eq -- "$_adre"; then _adtake=1
        # harbor#1313: the value attached to its letter, `-C/`. Only a non-letter start, so a
        # bundle like `-xCf` keeps its reading and a relative letter-led value stays unjudged.
        elif case "$_adt" in -*"$_adl"[![:alpha:]]*) true ;; *) false ;; esac \
             && printf '%s' "$_adt" | "$FLOOR_GREP" -Eq -- "^-[A-Za-z]*${_adl}[^A-Za-z]"; then
          printf '%s\n' "$_adt" | sed -E "s/^-[A-Za-z]*${_adl}//"
        fi ;;
    esac
  done
  return 0
}
# ditto's destination is its LAST operand — `ditto src… dst`. Flags are skipped;
# a flag's VALUE cannot be last in a well-formed invocation, so it never wins.
arch_last_operand() {
  _alo=""
  while IFS= read -r _alt; do
    [ -n "$_alt" ] || continue
    case "$_alt" in -*) continue ;; esac
    _alo="$_alt"
  done
  printf '%s\n' "$_alo"
}
# arch_seg_class <cmd-basename> <args> — sets _ARCH_RO (1 iff this invocation
# creates no file) and _ARCH_DEST (the destination argv names; empty = the cwd).
# Returns 1 when the destination is not decidable from argv at all.
#   _ARCH_CWD  1 iff an EMPTY _ARCH_DEST means "the current directory" — true of
#              tar/unzip/cpio, false of ditto and `pax -rw`, whose destination is
#              an operand and is therefore never implicit.
arch_seg_class() {
  _acn="$1"; _aca="$2"; _ARCH_RO=0; _ARCH_DEST=""; _ARCH_CWD=1
  case "$_acn" in
    tar|bsdtar|gtar)
      printf '%s\n' "$_aca" | "$FLOOR_GREP" -Eq -- "$TAR_XTOK" || _ARCH_RO=1
      _ARCH_DEST="$(printf '%s\n' "$_aca" | arch_dests C '--directory' 1)" ;;
    unzip)
      # -l -t -v -z -p -c are unzip's read-only modes; lowercase only (-L, -C, -P and -V are unrelated).
      if printf '%s\n' "$_aca" | "$FLOOR_GREP" -Eq -- '^-[A-Za-z]*[ltvzpc][A-Za-z]*$'; then _ARCH_RO=1; fi
      _ARCH_DEST="$(printf '%s\n' "$_aca" | arch_dests d '--directory')" ;;
    cpio)
      if printf '%s\n' "$_aca" | "$FLOOR_GREP" -Eq -- '^(-[A-Za-z]*t[A-Za-z]*|--list)$'; then _ARCH_RO=1; fi
      _ARCH_DEST="$(printf '%s\n' "$_aca" | arch_dests D '--directory')" ;;
    pax)
      # No -r: bare pax lists and `pax -w` writes an archive to stdout — both
      # read the named tree. `-rw` is COPY mode and its destination is the last
      # operand; a lone -r extracts into the cwd, the unknowable case.
      if printf '%s\n' "$_aca" | "$FLOOR_GREP" -Eq -- '^-[A-Za-z]*r[A-Za-z]*$'; then
        if printf '%s\n' "$_aca" | "$FLOOR_GREP" -Eq -- '^-[A-Za-z]*w[A-Za-z]*$'; then
          _ARCH_CWD=0; _ARCH_DEST="$(printf '%s\n' "$_aca" | arch_last_operand)"
        fi
      else _ARCH_RO=1; fi ;;
    ditto)
      _ARCH_CWD=0; _ARCH_DEST="$(printf '%s\n' "$_aca" | arch_last_operand)" ;;
    *) return 1 ;;
  esac
  return 0
}
# Provably not writing into the config dir?
arch_seg_outbound() {
  arch_seg_class "$1" "$2" || return 1
  if [ -n "$_ARCH_DEST" ]; then
    # A destination INSIDE the config dir settles the segment whatever the mode
    # says: a read-only letter must never be usable as a cloak for `-d ~/.claude`.
    if printf '%s\n%s\n' "$_ARCH_DEST" "$(floor_expand_paths "$_ARCH_DEST")" \
       | "$FLOOR_GREP" -Eq -- "$CFG_TOK"; then return 1; fi
    return 0
  fi
  # NO destination in argv: for a verb that then targets the CWD, the config dir named here is a SOURCE (the archive being read), so `cd /tmp/restore && tar xzf ~/.claude/backups/b.tgz` is not refused. The cwd question has one owner, the cd-then-extract rule below, where the cd is in the same command and the answer is knowable.
  [ "$_ARCH_RO" = 1 ] || [ "$_ARCH_CWD" = 1 ]
}
# Writes into the CURRENT directory — a writing mode with no destination in argv.
arch_seg_writes_cwd() {
  arch_seg_class "$1" "$2" || return 0
  [ "$_ARCH_RO" = 0 ] && [ -z "$_ARCH_DEST" ]
}
_arch_ids() { printf '%s\n' "${FLOOR_SEGS:-}" | "$FLOOR_GREP" -E "$ARCHCMD" 2>/dev/null \
  | sed -n 's/^SEGC:\([0-9][0-9]*\):.*/\1/p' | sort -un | tr '\n' ' '; }
_arch_cmd()  { printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGC:$1://p" | head -n 1; }
_arch_args() { printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:$1://p"; }
# Redirect targets, split by DIRECTION: floor_seg_has folds them in with the arguments, wrong here: `cpio -t < ~/.claude/backups/b.cpio` reads an archive and was blocked for naming it. `<` is a source, `>` a write.
_arch_rd()     { printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGR:$1:[^:]*://p"; }
_arch_rd_out() { printf '%s\n' "$FLOOR_SEGS" | "$FLOOR_GREP" -E "^SEGR:$1:(>|>>|>\||[0-9]+>>?):" 2>/dev/null \
  | sed -n 's/^SEGR:[0-9]*:[^:]*://p'; }
# Does this text name the config dir, in any spelling?
_arch_names_cfg() {
  printf '%s\n%s\n' "$1" "$(floor_expand_paths "$1")" | "$FLOOR_GREP" -Eq -- "$CFG_TOK"
}
# EVERY archive segment that names the config dir must be provably outbound or read-only; one that is not refuses the whole command.
arch_cfg_outbound() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  _arseen=0
  for _arid in $(_arch_ids); do
    _arargs="$(_arch_args "$_arid")"
    _arall="$_arargs
$(_arch_rd "$_arid")"
    _arch_names_cfg "$_arall" || continue
    _arseen=1
    # An OUTPUT redirect landing in the config dir is a write whatever the verb's own mode says.
    _arch_names_cfg "$(_arch_rd_out "$_arid")" && return 1
    # AN INPUT REDIRECT IS A SOURCE (docs/explanation/admission-baseline.md P12-argv-fp-05): if the config dir is named ONLY in a `<` redirect, the segment READS an archive or diff out of it (`patch -p1 < ~/.claude/patches/fix.patch` patches the CURRENT project).
    # The test sits here, not in arch_seg_class, where patch stays never-exemptible because its targets come from the diff body.
    _arch_names_cfg "$_arargs" || continue
    _arcmd="$(_arch_cmd "$_arid")"
    arch_seg_outbound "${_arcmd##*/}" "$_arargs" || return 1
  done
  [ "$_arseen" = 1 ]
}
arch_any_writes_cwd() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  for _arid in $(_arch_ids); do
    _arcmd="$(_arch_cmd "$_arid")"
    arch_seg_writes_cwd "${_arcmd##*/}" "$(_arch_args "$_arid")" && return 0
  done
  return 1
}
# ── find -exec WITH NO PATH IN IT ── `cd <cfg>/bin && find . -name '*.sh' -exec cp /tmp/evil {}` names the config dir nowhere (the search root is `.`), so no path-matching rule sees it; the cwd is knowable here because the `cd` is in the same command.
# THREE CONDITIONS, each a false positive if dropped: RELATIVE ROOT (an absolute root is judged by the path rules); PLACEHOLDER LAST (the destination of cp/mv/install/rsync/ditto is the last operand: `-exec cp {} /tmp/backup` copies OUT and passes, `-exec cp /tmp/evil {}` blocks);
# A WRITING VERB (`-exec grep -l x {}` audits the floor, harbor#107). The list is NOT the flat arm's: this one matches a segment's RESOLVED COMMAND, so a search term cannot trigger it; in-place editors join on their own flag.
SEG_CWD_WRITER='^([a-zA-Z0-9_./-]*/)?(cp|mv|install|rsync|ditto|tee|sponge|truncate|ln|link|shred|rm|rename|chmod|chown|dd|touch)$'
SEG_CWD_INPLACE='^([a-zA-Z0-9_./-]*/)?(sed|perl|python[0-9.]*|yq|gojq|ruby)$'
SEG_INPLACE_TOK='^(-[A-Za-z]*i([.=].*)?|--in-?place)$'
# The placeholder-position test is one variable read in exactly one place: inline it was two copies, and a mutation of either left the other enforcing, so the assertion pinning DIRECTION could not fail (No.2.10).
FIND_PH_WRITE='last'
# ONE AWK PASS, NOT A LOOP OF FORKS, a security property: a cap on how many find children the tokenizer expands can be pushed past (six `-exec ls {}` ahead of the payload measured exit 0, QA plan R4), and an uncapped table is affordable only if a child is cheap here too
# (the shell walk cost four forks per child, and latency in a PreToolUse hook is itself a fail-open path). The four inputs arrive as INPUT LINES, not `-v` assignments (awk escape-processes -v values, as floor_seg_cwd_under notes); only the first four lines are configuration, so no table row can pose as one.
find_exec_writes_cwd() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  # A builtin test before any fork: no find child, nothing to ask (latency is a fail-open path).
  case "$FLOOR_SEGS" in *"SEGF:"*) ;; *) return 1 ;; esac
  { printf '%s\n%s\n%s\n%s\n' "$FIND_PH_WRITE" "$SEG_CWD_WRITER" "$SEG_CWD_INPLACE" "$SEG_INPLACE_TOK"
    printf '%s\n' "$FLOOR_SEGS"; } | awk '
    # NO APOSTROPHES ANYWHERE BELOW, comments included: this awk program is a single-quoted shell string, so one apostrophe ends it. Two in a comment once made a heredoc veto return 0 for every heredoc (total fail-open) with lint green.
    NR == 1 { PH = $0; next }
    NR == 2 { RW = $0; next }
    NR == 3 { IP = $0; next }
    NR == 4 { IT = $0; next }
    # SEGF:<child>:<parent>:<ph>:<root> - a child whose placeholder lands in the LAST argument (destination position) and whose search root is RELATIVE; an ABSOLUTE root is judged by the path rules.
    /^SEGF:/ {
      s = substr($0, 6)
      id = s; sub(/:.*/, "", id)
      r = s; sub(/^[0-9]+:[0-9]+:/, "", r)
      p = r; sub(/:.*/, "", p)
      root = r; sub(/^[^:]*:/, "", root)
      if (p != PH) next
      if (root == "" || substr(root, 1, 1) == "/" || substr(root, 1, 1) == "~" \
          || substr(root, 1, 1) == "$") next
      WANT[id + 0] = 1
      next
    }
    # Collected for every segment, consulted only for the wanted ones, so the answer cannot depend on SEGF/SEGC emission order.
    /^SEGC:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id)
               v = s; sub(/^[0-9]+:/, "", v); CMD[id + 0] = v; next }
    /^SEGA:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id)
               v = s; sub(/^[0-9]+:/, "", v); if (v ~ IT) INPL[id + 0] = 1; next }
    END {
      for (id in WANT) {
        c = CMD[id]
        if (c == "") continue
        if (c ~ RW) exit 0
        if (c ~ IP && INPL[id]) exit 0
      }
      exit 1
    }'
}
# Computed ONCE: a PreToolUse hook that exceeds its timeout is SKIPPED, so latency is a fail-open path. harbor#715's unwrap for the extractor family (P12-argv-04), before ARCH_OUT so the direction test reads the same table.
# NOT patch or ditto (pass 13, P13E-1): neither has a mode the direction test can read, so `git log -S patch -- <cfg>/settings.json` became a write.
case "${FLOOR_SEGS:-}" in
  *[tT][aA][rR]*|*[uU][nN][zZ][iI][pP]*|*[cC][pP][iI][oO]*|*[pP][aA][xX]*)
    floor_seg_unwrap '^([^:]*/)?(tar|bsdtar|gtar|unzip|cpio|pax)$' ;;
esac
ARCH_OUT=0; arch_cfg_outbound && ARCH_OUT=1

# ONE gate over ALL FOUR rules: the flat pair matches the same commands, so exempting only the argv pair would move the false positive (`unzip -l ~/.claude/backups/x.tgz` would exit 2 under a different rule id).
if [ "$ARCH_OUT" = 0 ]; then
floor_seg_has '^([a-zA-Z0-9_./-]*/)?(tar|bsdtar|gtar)$' "$TAR_XTOK" "$CFG_TOK" \
  && floor_block bash "an archive is being extracted into the Helm config directory" extract-into-cfg.argv
floor_seg_has "$EXTRACTOR" "$CFG_TOK" \
  && floor_block bash "an extractor is writing into the Helm config directory" extractor-writes-cfg.argv
# THE FLAT FORM, RESTORED ALONGSIDE (pass 12, P12-migration-01, critical): stage 2 replaced these instead of keeping them, and twelve shapes that blocked before passed, each an operand that is not a literal token (`-C $(echo ~/.claude)`, a runtime-assembled variable, an oversized payload). argv is more precise, flat reaches further; neither is a superset.
# TAR_XNOO, not TAR_X (harbor#111): a bundle carrying O extracts to stdout. `[^;&|]*` already bounds the match to ONE segment, so a compound that reads with -O in one segment and extracts for real in the next still blocks. The argv pair keeps the plain extract mode.
hit "${CMDPOS}(tar|bsdtar|gtar)${TAR_XNOO}[^;&|]*(${CFG_RE}|${CFGDIR_RE}([[:space:]/]|\$))" \
  && floor_block bash "an archive is being extracted into the Helm config directory" extract-into-cfg.flat
hit "${CMDPOS}(unzip|ditto|patch|cpio|pax)([[:space:]]|$)[^;&|]*(${CFG_RE}|${CFGDIR_RE}([[:space:]/]|\$))" \
  && floor_block bash "an extractor is writing into the Helm config directory" extractor-writes-cfg.flat
fi
# harbor#1313 - an extraction INTO a dir above the config dir writes into it: the archive's member paths, not argv, decide where files land, so `-C /` or `-C ~` reaches <cfg>. The set is the bind-mount rule's (harbor#797): `/`, `~`, `$HOME` and each ancestor of the config and live dirs.
# Outside ARCH_OUT, which a config backup restored over `/` would otherwise buy. A relative destination stays unjudged (harbor#776); a writing mode only.
case "$CMD" in
  *[tT][aA][rR]*|*[uU][nN][zZ][iI][pP]*|*[cC][pP][iI][oO]*|*[pP][aA][xX]*|*[dD][iI][tT][tT][oO]*)
    _AANC="$( { _d="$CFG_ABS"; while _d="${_d%/*}"; [ -n "$_d" ]; do printf '%s\n' "$_d"; done
                _d="$LIVE_DIR"; while _d="${_d%/*}"; [ -n "$_d" ]; do printf '%s\n' "$_d"; done; } | sort -u)"
    arch_anc_dest() {
      [ -n "${FLOOR_SEGS:-}" ] || return 1
      for _arid in $(_arch_ids); do
        _arcmd="$(_arch_cmd "$_arid")"
        arch_seg_class "${_arcmd##*/}" "$(_arch_args "$_arid")" || continue
        [ "$_ARCH_RO" = 0 ] || continue
        while IFS= read -r _aad; do
          case "$_aad" in /*|'~'*|'$HOME'*|'${HOME'*) ;; *) continue ;; esac
          # The added `/` lets `~` expand and `/.` or `~/..` collapse, as floor_canon_dir does.
          _aad="$(floor_canon_dir "$(floor_expand_paths "$_aad/")")"
          [ "$_aad" = / ] && return 0
          printf '%s\n' "$_AANC" | "$FLOOR_GREP" -Fxq -- "$_aad" && return 0
        done <<ARCH_ANC_EOF
$_ARCH_DEST
ARCH_ANC_EOF
      done
      return 1
    }
    arch_anc_dest \
      && floor_block bash "an archive is being extracted into the root, the home dir or a dir above the config dir — its members can land in the config dir" extract-over-cfg-ancestor.argv
    # The flat form, for the payload with no table (oversized): `(/+..?)*` keeps any climb from an ancestor an ancestor. Root needs its `/`: an empty alternative would read every `-C dir` as `-C` and a space.
    _AANC_RE="$(printf '%s\n' "$_AANC" | sed '/^$/d; s/[][\\^$.*+?(){}|]/\\&/g' | tr '\n' '|')"
    # Three orders: the mode before the flag, after it, or the flag closing the mode bundle. A
    # dashless mode only as the first argument, tar's own rule: a padded tail of x-words is no mode.
    _ADEST="[\"']?((${_AANC_RE}~|\\\$HOME|\\\$\\{HOME\\})(/+\\.\\.?)*/*|/+(\\.\\.?/*)*)[\"']?"
    _ADIR="(-[a-zA-Z]*C[[:space:]]*|--directory[=[:space:]]+)${_ADEST}"
    _AXD='[[:space:]]+(-[a-np-zA-NP-Z]*x[a-np-zA-NP-Z]*|--(extract|get))([[:space:]]|=|$)'
    { hit "${CMDPOS}(tar|bsdtar|gtar)(${TAR_XNOO}|[^;&|]*${_AXD})([^;&|]*[[:space:]])?${_ADIR}([[:space:]]|\$)" \
      || hit "${CMDPOS}(tar|bsdtar|gtar)[^;&|]*[[:space:]]${_ADIR}([[:space:]][^;&|]*)?${_AXD}" \
      || hit "${CMDPOS}(tar|bsdtar|gtar)([[:space:]]+-?|[^;&|]*[[:space:]]-)[a-np-zA-NP-Z]*x[a-np-zA-NP-Z]*C[[:space:]]*${_ADEST}([[:space:]]|\$)"; } \
      && floor_block bash "an archive is being extracted into the root, the home dir or a dir above the config dir — its members can land in the config dir" extract-over-cfg-ancestor.flat
    ;;
esac
# ORDERING, AND THE COMMAND LIST: this rule accepts the in-place FLAG anywhere AHEAD of the surface (how these tools are invoked); jq-rewrites-surface below accepts it only AFTER. The writers are named here rather than bolting an ordering onto the sink rule.
# `yq` IS THE ONE THAT MATTERS (2026-08-03): `yq -i '.permissions.deny = []' ~/.claude/settings.json` and the workflow-file shape (harbor#88) exited 0; its long flag is `--inplace`, GNU's `--in-place`, hence `--in-?place`. jq is DELIBERATELY NOT IN THIS LIST and should not be restored:
# jq has no in-place mode (that is why sponge exists), so `jq -i` writes nothing, and adding it cost three false positives on reads.
# NO LEFT BOUNDARY, deliberately: requiring whitespace before the flag (to stop a filename ending in -i reading as in-place) regressed, because whitespace in the TEXT is not "this token starts a word" and an IFS-spelled separator walked through; no left-character test can fix that. The false positives were killed at their source instead (jq left the rule).
# One known residual: a command substitution carrying a -i flag (`$(uname -i)`) still matches.
# THE FLAG IS A TOKEN, NOT A SUBSTRING (`yq --indent 4 . <surface>` is a read): the short form must END at a separator, `-i.bak` and `-i=x` included. AND LOWERCASE: hit() is grep -i deliberately (a case-insensitive filesystem resolves `SED`), but yq's `-i` (write) and `-I` (indent) differ only by case, so the flag needs a second CASE-SENSITIVE pass.
# THE BUNDLE FORM (`sed -Ei`, `-ni`, `-nEi`) is an in-place write with no `-i` substring. The tail class is "not a flag character" rather than a list of separators: `[.=]` missed an IFS-spelled tail, and a bare `$` in an alternation is the anchor. Nor a slash: a path segment such as `harbor-ci/` was a bundle.
_IPF="(-i([^[:alnum:]/-]|\$)|-[[:alpha:]]*i([^[:alnum:]/-]|\$)|--in-?place)"
# Case-blind command + case-strict flag needs both greps; $FLOOR_GREP either way,
# per lint F3.
hit_cs() { printf '%s' "$CMD" | "$FLOOR_GREP" -Eq -- "$1"; }
hit "(^|[^[:alnum:]_])(sed|perl|python[0-9.]*|yq|gojq)[^;&|]*$_IPF[^;&|]*$SURFACE" \
  && hit_cs "$_IPF" \
  && floor_block bash "in-place edit of a Helm floor control surface" inplace-floor-surface.flat
# dasel EDITS IN PLACE WITH NO FLAG TO KEY ON (`dasel put -f`, `dasel delete -f`), so it is named by VERB: there is no reading form of `put` or `delete`.
hit "(^|[^[:alnum:]_])dasel[^;&|]*[[:space:]](put|delete)[^;&|]*$SURFACE" \
  && floor_block bash "dasel is rewriting a Helm floor control surface in place" dasel-at-surface.flat

# ── P13-fs-04 · plutil MODE (harbor#94) ── `plutil -replace permissions.deny -json '[]' ~/.claude/settings.json` empties the deny array and leaves valid JSON (measured 2026-08-05): B1's whole containment layer removed by a macOS binary in no verb list.
# This HAS a shape: knowing what a verb does to the file it names is what arch_seg_class is, and a verb's documented behaviour is a checkable FACT where a list of dangerous words is a drifting judgement. plutil is an easier case than tar (each measured): the MODE is ONE LEADING SUBCOMMAND (`plutil <file> -remove k` is rejected), with no letter bundling, no dashless spelling and no case pair.
# WRITE MODES: -replace, -insert, -remove, -convert, -create. READ MODES: -p, -lint (the default), -type, -extract, -help (input proved byte-identical). DIRECTION NEEDS NO POSITION WALK: a write mode rewrites EVERY file operand, so "some token names the config dir" IS the answer.
# -create IGNORES -o AND -e: it truncates the named file to `{}`, even a non-plist, so it reaches <cfg>/bin too.
# THE ONE EXEMPTION: `-o path` diverts the output and leaves the file untouched, so `plutil -convert json -o - <surface>` is a READ (§2.11). Granted ONLY for -convert, where `-o` is provably the option: for -replace/-insert a `-type value` pair can have the value `-o` and REWRITE the file, while plutil rejects `-o` as a -convert format specifier.
# ALL -o values count, not the last. An `-e` token CANCELS the exemption (`-convert xml1 -e json f.json` rewrote f.json itself).
# A SEGMENT RULE, NOT A FLAT ONE: it reads SEGC with wrappers peeled (`sudo plutil` needs no clause of its own), and a flat `plutil` would fire on the word anywhere (a commit message or heredoc documenting this rule: the harbor#107 and pass-11 `patch` false positives).
PLU_SEG='^SEGC:[0-9]+:([a-zA-Z0-9_./-]*/)?plutil$'
PLU_WMODE='^(-replace|-insert|-remove|-convert|-create)$'
# Every value of a literal `-o`, one per line: plutil CREATES that file whatever the mode is, so an -o value is a write target unconditionally (and agrees with P13-fs-03's shape).
plu_o_values() {
  _pltake=0
  while IFS= read -r _plt; do
    if [ "$_pltake" = 1 ]; then printf '%s\n' "$_plt"; _pltake=0; continue; fi
    if [ "$_plt" = "-o" ]; then _pltake=1; fi
  done
  return 0
}
# plu_classify - one line per fact: `W:<token>` a token this invocation can WRITE; `X` this segment writes its OPERANDS; `D` it does not (a read mode, or output diverted by -o).
# plu_operands - the FILE operands of a write-mode invocation, with mode METADATA excluded: `plutil -replace k -string <surface> /tmp/prefs.plist` stores the path as a STRING and leaves the surface untouched (Codex, harbor#138).
# EXCLUSION IS POSITIVE, NEVER A GUESS: only a token the function can NAME as metadata is dropped (the keypath or format after the mode flag, a type flag and its value); anything unrecognised stays an operand and blocks. `-array`/`-dict` carry no value.
# Prints `O:<tok>` for an operand and `M:<tok>` for metadata; BOTH are needed so the flat arm's veto is a POSITIVE determination, since `S=<surface>; plutil -remove k $S` also has no config path among its operands.
plu_split() {
  _pl_post=0; _pl_skip=0
  while IFS= read -r _pt; do
    [ -n "$_pt" ] || continue
    if [ "$_pl_skip" = 1 ]; then _pl_skip=0; printf 'M:%s\n' "$_pt"; continue; fi
    case "$_pt" in
      -replace|-insert|-remove|-convert|-create|-extract)
        _pl_post=1; _pl_skip=1; printf 'M:%s\n' "$_pt"; continue ;;
    esac
    if [ "$_pl_post" = 1 ]; then
      case "$_pt" in
        -array|-dict) printf 'M:%s\n' "$_pt"; continue ;;
        -bool|-integer|-float|-string|-date|-data|-xml|-json|-plist)
          _pl_skip=1; printf 'M:%s\n' "$_pt"; continue ;;
      esac
    fi
    printf 'O:%s\n' "$_pt"
  done
}
plu_classify() {
  [ -n "${FLOOR_SEGS:-}" ] || return 0
  _plids="$(printf '%s\n' "$FLOOR_SEGS" | "$FLOOR_GREP" -E "$PLU_SEG" 2>/dev/null \
            | sed -n 's/^SEGC:\([0-9][0-9]*\):.*/\1/p' | sort -un | tr '\n' ' ')"
  for _plid in $_plids; do
    _plargs="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_plid}://p")"
    _plout="$(printf '%s\n' "$_plargs" | plu_o_values)"
    [ -n "$_plout" ] && printf '%s\n' "$_plout" | sed -e 's/^/W:/'
    _plmode=""
    if printf '%s\n' "$_plargs" | "$FLOOR_GREP" -Eq -- "$PLU_WMODE"; then
      _plmode="$(printf '%s\n' "$_plargs" | "$FLOOR_GREP" -E -- "$PLU_WMODE" | head -n 1)"
    fi
    # DIVERTED: `-convert … -o PATH` with no `-e`. Then the operands are SOURCES
    # and the -o values already printed above are the whole answer.
    _pldiv=0
    if [ "$_plmode" = "-convert" ] && [ -n "$_plout" ]; then
      _pldiv=1
      if printf '%s\n' "$_plargs" | "$FLOOR_GREP" -Eq -- '^-e$'; then _pldiv=0; fi
    fi
    if [ -n "$_plmode" ] && [ "$_pldiv" = 0 ]; then
      printf 'X\n'
      _plsp="$(printf '%s\n' "$_plargs" | plu_split)"
      printf '%s\n' "$_plsp" | sed -n 's/^O:/W:/p'
      printf '%s\n' "$_plsp" | sed -n 's/^M:/M:/p'
      printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGR:${_plid}:[^:]*:/W:/p"
    else
      printf 'D\n'
    fi
    :
  done
  return 0
}
# Computed ONCE, like ARCH_OUT (latency is a fail-open path); the argv arm, the flat arm and the cwd-fold arm far below all read these.
PLU_C="$(plu_classify)"
PLU_WT="$(printf '%s\n' "$PLU_C" | sed -n 's/^W://p')"
# PLU_RO - the table POSITIVELY determined every plutil segment is a read or diverted. Not "no config path found", which would veto the flat arm for `S=<surface>; plutil -remove k $S`.
PLU_RO=0
if [ -n "$PLU_C" ]; then
  if printf '%s\n' "$PLU_C" | "$FLOOR_GREP" -qx -e X; then PLU_RO=0; else PLU_RO=1; fi
fi
# PLU_META_ONLY - the argv layer SAW a config path and classified it as MODE METADATA (`plutil -replace k -string <surface> /tmp/prefs.plist` writes /tmp), as opposed to `S=<surface>; plutil -remove k $S`, whose argv carries no path at all; vetoing the flat arm on "no operand named the config dir" would hand back the second (Codex, harbor#138).
PLU_MT="$(printf '%s\n' "$PLU_C" | sed -n 's/^M://p')"
PLU_META_ONLY=0
if [ -n "$PLU_MT" ] \
   && printf '%s\n%s\n' "$PLU_MT" "$(floor_expand_paths "$PLU_MT")" \
      | "$FLOOR_GREP" -Eq -- "$CFG_TOK"; then
  # ...and NOT also an operand: a surface that is both is a write and must not buy an exemption from its own appearance as a value.
  if ! { [ -n "$PLU_WT" ] && printf '%s\n%s\n' "$PLU_WT" "$(floor_expand_paths "$PLU_WT")" \
         | "$FLOOR_GREP" -Eq -- "$CFG_TOK"; }; then
    PLU_META_ONLY=1
  fi
fi
if [ -n "$PLU_WT" ] \
   && printf '%s\n%s\n' "$PLU_WT" "$(floor_expand_paths "$PLU_WT")" \
      | "$FLOOR_GREP" -Eq -- "$CFG_TOK"; then
  floor_block bash "plutil is rewriting a file inside the Helm config directory in place" plutil-writes-cfg.argv
fi
# THE FLAT ARM IS NOT A DUPLICATE OF THE ONE ABOVE: it answers two shapes argv cannot see, both measured open (`S=<surface>; plutil -remove permissions.deny $S`, and the same with `$(echo <surface>)`): the segment table carries the LITERAL `$S`, while $TARGETS carries floor_expand_vars' renderings. Over FLOOR_MAX_NORM it is the only arm left (QA plan R4).
# THREE GATES KEEP IT OFF ORDINARY WORK: $CMDPOS (plutil must START a command; a single-quoted argument reaches $TARGETS, so `git commit -am '<this command>'` blocked, harbor#107); $SINK_RO (the harbor#107 veto; measured redundant alone, red together with $CMDPOS, kept because every other flat write rule gates on it);
# PLU_RO (the flat form cannot model the -o exemption, so `plutil -convert json -o - <surface>` defers to the argv layer). NARROWER than the argv arm by design: $SURFACE, not the whole config dir, because a flat regex has no token boundaries for CFG_TOK's `(/|$)`.
if [ "$PLU_RO" = 0 ] && [ "$SINK_RO" = 0 ] && [ "$PLU_META_ONLY" = 0 ]; then
  hit "${CMDPOS}plutil([[:space:]]+-[^[:space:]]+)*[[:space:]]+(-replace|-insert|-remove|-convert|-create)([[:space:]]|\$)[^;&|]*$SURFACE" \
    && floor_block bash "plutil is rewriting a Helm floor control surface in place" plutil-writes-cfg.flat
fi

# An interpreter is a universal file writer, so no verb list can be complete (node -e fs.writeFileSync, python -c open(...,'w'); red-team pass 3): any interpreter naming a floor surface is denied.
# $SINK_RO IS THE ONLY GATE, AND IT CANNOT OPEN A HOLE (harbor#164): SINK_RO=1 means EVERY segment command word is in $SEG_NOWRITE, and an interpreter actually INVOKED is itself a command word outside it, so the exemption is reachable only when the interpreter's name arrives as an ARGUMENT
# (`grep bun <workflow>` was blocked: quote-stripping makes it the same token sequence as `bun <workflow>`).
#
# ── harbor#334-B · WHOSE ARGUMENT IS THE SURFACE ── $SINK_RO asks whether ANYTHING in the command can write, so an interpreter segment naming no surface (`python3 -c 'print(1)'; grep -n x <workflow>`) withdrew the veto for the LATER read and `.*` carried the rule across the `;`. Reversing the order allowed it: the block was positional (2026-09-07).
# THE OBVIOUS FIX IS A BYPASS: narrowing the span to `[^;&|]*` turns `S6 heredoc interpreter` red, because floor-normalize folds a heredoc newline AS `;`, so a fed interpreter and a `;`-separated later read are the same shape to any flat regex.
# THE SEGMENT TABLE SEPARATES THEM: in the heredoc fold the surface is a command WORD, in the false positives an ARGUMENT of a reader (`SEGC:2:grep`, `SEGA:2:<workflow>`). ONE AWK PASS, NO PER-SEGMENT FORKS (P12-perf-04: a hook that times out FAILS OPEN). DEGRADES CLOSED: no table means return 1 and the rule decides as before.
# AN UNRESOLVED PATH ANYWHERE WITHDRAWS THE VETO (Codex P1 on #470): floor_bash_targets emits an EXPANDED variant while FLOOR_SEGS keeps the literal `$S`, so without this arm `S=<workflow>; bun $S; wc -l <file>` was blocked before and allowed after, and appending a dummy reader would switch the interpreter protection off for every variable-expanded surface.
# Residual: a genuine read whose surface arrives through a variable still blocks when an interpreter shares the compound; fixing that means expanding per segment, a segment-table change.
seg_surface_read_only() { # <surface-ERE> — 0 iff every mention is a reader's arg
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  { printf 'SRE:%s\n' "$1"; printf 'NWR:%s\n' "$SEG_NOWRITE"
    printf '%s\n' "$FLOOR_SEGS"; } | awk '
    NR == 1 { sub(/^SRE:/, ""); sre = $0; next }
    NR == 2 { sub(/^NWR:/, ""); nwr = $0; next }
    {
      if (!match($0, /^SEG[CA]:[0-9]+:/)) next
      tag = substr($0, 4, 1)
      val = substr($0, RLENGTH + 1)
      n   = substr($0, 6, RLENGTH - 6)
      # A path this pass cannot resolve (checked on words and args alike) makes every conclusion below a guess.
      if (val ~ /\$/ || val ~ /`/) unresolved = 1
      if (tag == "C") {
        word[n] = val
        if (val ~ sre) wordhit = 1       # the surface IS a command word
      } else if (val ~ sre) {
        arghit = 1; seen[n] = 1          # …or an argument of one
      }
    }
    END {
      if (unresolved || wordhit || !arghit) exit 1
      for (n in seen) if (word[n] !~ nwr) exit 1
      exit 0
    }'
}

if [ "$SINK_RO" = 0 ] && ! seg_surface_read_only "$SURFACE"; then
  hit "(^|[^[:alnum:]_])(python[0-9.]*|node|nodejs|ruby|perl|php|osascript|bun|deno)[[:space:]].*$SURFACE" \
    && floor_block bash "an interpreter is being pointed at a Helm floor control surface" interpreter-at-surface.flat
fi
# Pass 14 B-sd-2: ex/vi/vim/ed rewrite their file operand, and awk writes through print/printf >, a pipe, system() or gawk -i inplace. An awk program that only reads a surface still passes (tok-206).
# Asked per segment, so a writing awk in one segment and a read of a surface in the next is not one finding.
AWK_WRITE='(print|printf)[^>|]*(>[^&]|\|)|system[[:space:]]*\(|^-i[[:space:]]*inplace$|^inplace$|^--inplace'
seg_tool_at_surface() { # <cmd-ERE> [<arg-ERE one arg must match>] — 0 iff such a segment names a surface
  for _tsid in $(_floor_seg_ids "$1" ci); do
    _tsa="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_tsid}://p")"
    [ -z "${2:-}" ] || printf '%s\n' "$_tsa" | "$FLOOR_GREP" -Eq -- "$2" || continue
    printf '%s\n%s\n' "$_tsa" "$(floor_expand_paths "$_tsa")" | "$FLOOR_GREP" -iEq -- "$SURFACE" && return 0
  done
  return 1
}
seg_tool_at_surface '^([a-zA-Z0-9_./-]*/)?(ex|ed|vi|vim|nvim)$' \
  && floor_block bash "a scriptable editor is being pointed at a Helm floor control surface" editor-at-surface.argv
seg_tool_at_surface '^([a-zA-Z0-9_./-]*/)?(awk|gawk|mawk|nawk)$' "$AWK_WRITE" \
  && floor_block bash "an awk program that writes or runs commands is being pointed at a Helm floor control surface" awk-write-at-surface.argv
# The flat twins cover a payload the table could not hold (QA plan R4).
if floor_seg_degraded; then
  hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?(ex|ed|vi|vim|nvim)[[:space:]].*$SURFACE" \
    && floor_block bash "a scriptable editor is being pointed at a Helm floor control surface" editor-at-surface.flat
  hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?(awk|gawk|mawk|nawk)[[:space:]].*((print|printf)[^>|]*(>[^&]|\|)|system[[:space:]]*\(|-i[[:space:]]*inplace|--inplace).*$SURFACE" \
    && floor_block bash "an awk program that writes or runs commands is being pointed at a Helm floor control surface" awk-write-at-surface.flat
fi
hit "(^|[^[:alnum:]_])dd[^;&|]*$SURFACE" \
  && floor_block bash "dd rewrite aimed at a Helm floor control surface" dd-at-surface.flat
# harbor#776/#772 — create, append and update WRITE the -f archive: `tar -czf <surface> x` rewrote a
# pin or a deploy snapshot at exit 0. The mode is case-strict (`-C` is chdir); archiving a surface OUT reads it.
TAR_CTOK='^(-[A-Za-z]*[cru][A-Za-z]*|--(create|append|update|catenate|concatenate))$'
tar_archive_at_surface() {
  case "${FLOOR_SEGS:-}" in *[tT][aA][rR]*) ;; *) return 1 ;; esac   # builtin gate before any fork
  for _tcid in $(_floor_seg_ids '^([a-zA-Z0-9_./-]*/)?(tar|bsdtar|gtar)$' ci); do
    _tca="$(printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_tcid}://p")"
    if printf '%s\n' "$_tca" | "$FLOOR_GREP" -Eq -- "$TAR_CTOK" \
       || printf '%s\n' "$_tca" | sed -n 1p | "$FLOOR_GREP" -Eq '^[A-Za-z]*[cru][A-Za-z]*$'; then
      _tcf="$(printf '%s\n' "$_tca" | arch_dests f '--file' 1)"
      if [ -n "$_tcf" ] && printf '%s\n%s\n' "$_tcf" "$(floor_expand_paths "$_tcf")" \
           | "$FLOOR_GREP" -iEq -- "$SURFACE"; then return 0; fi
    fi
  done
  return 1
}
tar_archive_at_surface \
  && floor_block bash "tar is writing its archive onto a Helm floor control surface" tar-archive-at-surface.argv
# The flat twin keeps an oversized payload covered (QA plan R4); its bundle excludes x and t.
hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?(tar|bsdtar|gtar)[[:space:]]+-?[a-su-wyz]*[cru][a-su-wyz]*f[[:space:]]+$SURFACE" \
  && floor_block bash "tar is writing its archive onto a Helm floor control surface" tar-archive-at-surface.flat
# jq/cat/grep only READ unless a write sink is present. THE SINK LIST IS NARROWER THAN IT LOOKS: `>`, `>>` and `| tee` are not this rule's to catch (a bare `>` after the surface blocked `jq -e . settings.json >/dev/null`, the check that an install did not corrupt settings.json; §2.11).
# Deleting them loses nothing: redirect-floor-surface and mutate-aimed-surface key on the TARGET and still block. What is left is sponge (writes back to its own input) and a TRAILING in-place flag, whose leading form lives with sed and perl above.
# The trailing flag needs the SAME left boundary as the leading one: a filename ending in -i (`jq -r .x <surface> > /tmp/out-i`) counted as a request to edit in place.
hit "(^|[^[:alnum:]_])jq[^;&|]*$SURFACE[^;&|]*(--in-?place|[^[:alnum:]_./]-i([[:space:]]|$)|\\| *sponge)" \
  && floor_block bash "jq rewriting a Helm floor control surface" jq-rewrites-surface.flat
# A verb aimed at the config DIRECTORY itself (implicit basename, or removing
# and renaming the dir that holds the guards).
hit "${_VERBL}(cp|mv|install|rsync)([[:space:]]+-[^[:space:]]+)*[[:space:]]+[^-][^[:space:];&|]*[[:space:]][^;&|]*${CFGDIR_RE}/*([[:space:]]|[;&|\"')}]|\$)" \
  && floor_block bash "a file-mutating command is writing INTO the Helm config directory" mutate-into-cfg.flat
hit "${_VERBL}(rm|shred|truncate|ln|mv)([[:space:]]+-[^[:space:]]+)*[[:space:]][^;&|]*${CFGDIR_RE}/*([[:space:]]|[;&|\"')}]|\$)" \
  && floor_block bash "a destructive command is aimed at the Helm config directory itself" destructive-at-cfg.flat
# The argv twin reads the brace-expanded operands: 'rm -rf ~/{.claude,x}' hides the
# boundary the flat form needs (pass 13, P13A-2). Same scope, one token, anchored.
CFGDIR_TOK="^(${CFG_ABS_RE}|${LIVE_RE}|~/\\.claude|${TILDE_CFG}|\\\$HOME/\\.claude|\\\$\\{HOME\\}/\\.claude)(/+(bin|hooks|${CFG_SNAPDIR}))?/*\$"
floor_seg_has '^([a-zA-Z0-9_./-]*/)?(rm|shred|truncate|ln|mv)$' "$CFGDIR_TOK" \
  && floor_block bash "a destructive command is aimed at the Helm config directory itself" destructive-at-cfg.argv
# ── harbor#280 · THE CONFIG DIRECTORY, NOT JUST ITS PINNED SURFACES ── the rule this replaces advertised the directory but matched only a redirect at the BARE directory, so `echo hi > <cfg>/notes.txt` was allowed (measured 2026-08-23); harbor#280 found it by asking which rules the corpus can reach.
# POSTURE (the operator's call): block writes under the config dir EXCEPT the subtrees a session legitimately writes: MEMORY (never MEMORY/OBSERVABILITY, a surface since harbor#1181) and projects. `.helm-pins` is deliberately NOT allowlisted: a session that can rewrite a pin can disarm the detector that watches the floor.
# Cache, sessions, plans and file-history are harness-managed. READS ARE UNTOUCHED: this keys on a redirect TARGET.
# PER-REDIRECT, VIA THE SEGMENT TABLE, NOT A FLAT REGEX: with two redirects in one command the allowlisted one would waive the block for the other (`echo a > <cfg>/MEMORY/x ; echo b > <cfg>/notes.txt`); each target is judged on its own.
CFG_SESSION_WRITABLE='(MEMORY|projects)(/|$)'
cfg_redirect_outside_allowlist() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  printf '%s\n' "$FLOOR_SEGS" \
    | "$FLOOR_GREP" -E '^SEGR:[0-9]+:&?[0-9]*>>?[|!&]?:' 2>/dev/null \
    | sed -n 's/^SEGR:[0-9]*:[^:]*://p' \
    | "$FLOOR_GREP" -E -- "^${CFG_RE}" 2>/dev/null \
    | "$FLOOR_GREP" -Evq -- "^${CFG_RE}${CFG_SESSION_WRITABLE}" 2>/dev/null
}
# harbor#1420: 28 of 33 blocks were a redirect into session-titles/, the file the SessionStart note asks for.
# Message only: the block stays, and the file-write tool is what the note meant.
if cfg_redirect_outside_allowlist; then
  _rtail="only MEMORY/ and projects/ are session-writable"
  case "$CMD" in *session-titles/*) _rtail="a session title is written with the file-write tool (Write) on its session-titles/ path, not a shell redirect" ;; esac
  floor_block bash "shell redirect writing inside the Helm config directory — §3 private state; $_rtail" redirect-into-cfg.path
fi

# RE-PINNING IS THE OPERATOR'S ACT, but this is NOT the place to enforce it (withdrawn in pass 10): matching the pinner's filename in command text walked on four spellings (the repo copy with the dir as an argument, a bare invocation that defaults to the live dir, a cd bridge, a copy of the script)
# and blocked ordinary text that quotes a command. "Is this command RUNNING that script against that directory?" is not decidable from command text; pin-instructions.sh and baseline-pin.sh carry the in-script live-dir refusal and lint rule D2 holds all six to it.
# Residual (docs/explanation/admission-baseline.md): a session with unrestricted Bash can still silence the B8 advisory; B8 is a detection control, never containment.

# `cd <config dir> ... <mutate> <bare filename>`: after the cd the target is a relative name with no path to match (red-team pass 2). The cd is STICKY for the whole command (a third command inserted escaped the one-segment bridge), with a BOUNDARY after the config path so `~/.claudex` does not arm it (pass 6).
# THE BRIDGE ARMED ON ONE HOP (pass 13, P13-fs-01): `cd ~ && cd .claude && echo {} > settings.json`, the `;` spelling and `pushd` armed nothing. floor_seg_cwd_under now FOLDS the cd/pushd chain out of the segment table and compares by component, so hop count, `..` and `./` stop mattering.
# The flat regex STAYS, second, as the fallback over FLOOR_MAX_NORM where every argv question goes silent (QA plan R4).
# THE CD-BRIDGE, ANSWERED WHERE IT IS ASKED (edge pass 2026-08-29, docs/explanation/admission-baseline.md P12-argv-01): the rule armed when the command STANDS in the config dir, never for standing NEXT to it and reaching in by a relative name (`cd ~ && rm -rf .claude`).
# ONLY THE UNAMBIGUOUS VERBS: rm, shred and truncate destroy whatever they name; cp, mv, ditto and rsync are ABSENT because their config-dir operand may be the SOURCE (P12-argv-fp-01/02/03). `=` PREFIX MEANS EXACT: the config dir is passed exact and its teeth as subtrees, since ~/.claude is WRITABLE by design (B8): `cd ~/.claude/MEMORY && rm stale-note.md` must pass (S7).
if floor_seg_operand_under '^([a-zA-Z0-9_./-]*/)?(rm|shred|truncate)$' \
     "=$CFG_ABS" "=$LIVE_DIR" \
     "$CFG_ABS/bin" "$CFG_ABS/hooks" "$LIVE_DIR/bin" "$LIVE_DIR/hooks" \
     "%^${CFG_ABS_RE}/+(${FILES})\$" "%^${LIVE_RE}/+(${FILES})\$"; then
  floor_block bash "a relative destroy of the config dir, a pinned surface in it, or its guards after a cd into the parent" cd-bridge-destroy.argv
fi

# ── THE SAME BRIDGE FOR mv AND cp (harbor#362 follow-on) ── `cd ~ && mv .claude/settings.json /tmp` walked past while the rm shape blocked (measured 2026-08-30).
# THE TWO VERBS NEED DIFFERENT RULES (P12-argv-fp-01/02/03): mv takes ANY operand (moving a pinned file OUT loses it, IN overwrites it); cp DESTINATION ONLY (`cp <cfg>/settings.json /tmp/backup` is a read). Standing INSIDE the config dir is already cd-cfg-then-mutate; this covers standing OUTSIDE and reaching in.
if floor_seg_operand_under '^([a-zA-Z0-9_./-]*/)?mv$' \
     "=$CFG_ABS" "=$LIVE_DIR" \
     "$CFG_ABS/bin" "$CFG_ABS/hooks" "$LIVE_DIR/bin" "$LIVE_DIR/hooks" \
     "%^${CFG_ABS_RE}/+(${FILES})\$" "%^${LIVE_RE}/+(${FILES})\$"; then
  floor_block bash "a relative mv of the config dir, a pinned surface in it, or its guards after a cd into the parent" cd-bridge-move.argv
fi
if floor_seg_operand_under --dest-only '^([a-zA-Z0-9_./-]*/)?cp$' \
     "=$CFG_ABS" "=$LIVE_DIR" \
     "$CFG_ABS/bin" "$CFG_ABS/hooks" "$LIVE_DIR/bin" "$LIVE_DIR/hooks" \
     "%^${CFG_ABS_RE}/+(${FILES})\$" "%^${LIVE_RE}/+(${FILES})\$"; then
  floor_block bash "a relative cp ONTO the config dir, a pinned surface in it, or its guards after a cd into the parent" cd-bridge-copy.argv
fi

# ── THE GCLOUD CREDENTIAL STORE (incident 2026-09-03) ── ~/.config/gcloud was destroyed and recreated inside one session; recovery needed five interactive browser logins because Google refuses its shared gcloud client for a workload API's scopes, and the OAuth client file is the only route back.
# This rule did not catch the incident and cannot claim to (no delete appears in any record, so the actor is unidentified); the recoverable copy (`gcloud-creds snapshot`) is the real control.
# EXACT FOR THE DIRECTORIES, SURFACE REGEX FOR THE FILES (the scoping S7 forced on the config dir): the store is WRITABLE by design (rm ~/.config/gcloud/identities/<role>/expected-account and rm -rf ~/.config/gcloud/logs are real commands), asserted as controls.
CRED_ABS="$(floor_canon_dir "$HOME/.config/gcloud")"
CRED_ABS_RE="$(floor_surface_re "$HOME/.config/gcloud")"
# `floor_expand_paths` canonicalises ~, $HOME and ${HOME} into the absolute
# spelling before a rule sees an argument, so only the absolute form is written.
CRED_ADC_RE="^${CRED_ABS_RE}/.*application_default_credentials\\.json\$"
CRED_ANY="^${CRED_ABS_RE}/?\\*?\$|^${CRED_ABS_RE}/identities/?\\*?\$|^${CRED_ABS_RE}/oauth-clients(/[^[:space:];&|]*)?\$|${CRED_ADC_RE}"
CRED_DESTROY_CMD='^([a-zA-Z0-9_./-]*/)?(rm|shred|truncate)$'

floor_seg_has "$CRED_DESTROY_CMD" "$CRED_ANY" \
  && floor_block bash "destroying the gcloud credential store, its identities dir, an ADC or the OAuth client" cred-destroy.argv
# `mv` destroys in BOTH directions — out loses the credential, in overwrites it —
# so any operand counts, exactly as the config dir's mv rule argues.
floor_seg_has '^([a-zA-Z0-9_./-]*/)?mv$' "$CRED_ANY" \
  && floor_block bash "moving the gcloud credential store, an ADC or the OAuth client" cred-move.argv
# harbor#1313 (L9): the store's PARENT (~/.config) and any glob whose match set holds the store, its
# identities dir, the OAuth client or an ADC carry it away too, and CRED_ANY compares only the store's
# own spellings. Every operand of rm/shred/truncate/mv, like the rules above; a zsh `:h` modifier on a
# glob (the parser drops the parenthesised part) is applied to the operand before it is judged.
_cred_glob_hit() {
  [ -n "${FLOOR_SEGS:-}" ] || return 1
  { _gl_cred_t
    printf '%s\n' "$FLOOR_SEGS" | awk '
      /^SEGC:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); c = s; sub(/^[0-9]+:/, "", c); sub(/^.*\//, "", c)
                 c = tolower(c)
                 if (c ~ /^(s?rm|shred|truncate)$/) V[id] = "rm"; else if (c == "mv") V[id] = "mv"
                 next }
      /^SEGA:/ { s = substr($0, 6); id = s; sub(/:.*/, "", id); a = s; sub(/^[0-9]+:/, "", a)
                 if (V[id] != "" && a !~ /^-/) print "O:" V[id] ":" a; next }'
    case "$CMD" in *':h'*) hit '(^|[^[:alnum:]_-])(s?rm|shred|truncate|mv)[[:space:]]' || exit 0
      printf '%s\n' "$TARGETS" | awk '
        { for (i = 1; i <= NF; i++) {
            w = $i
            if (!match(w, /\([^()]*:h[^()]*\)[^()]*$/)) continue
            md = substr(w, RSTART); g = substr(w, 1, RSTART - 1)
            n = 0; while (match(md, /:h[0-9]*/)) { d = substr(md, RSTART + 2, RLENGTH - 2); n += (d == "" ? 1 : d + 0); md = substr(md, RSTART + RLENGTH) }
            k = split(g, p, "/"); out = ""
            for (j = 1; j <= k - n; j++) out = out (j > 1 ? "/" : "") p[j]
            if (out != "") print "O:rm:" out
          } }' ;;
    esac; } | floor_home_sed | _gl_reach
}
_cgr="$(_cred_glob_hit)" || _cgr=""
[ -z "$_cgr" ] || case "${_cgr#* }" in
  mv) floor_block bash "moving a path whose match set holds the gcloud credential store, an ADC or the OAuth client" cred-move.glob
    ;;
  *) floor_block bash "destroying a path whose match set holds the gcloud credential store, an ADC or the OAuth client" cred-destroy.glob
    ;;
esac

# RESIDUAL: a FLAT `cp /tmp/x <store>/.../adc.json` is not covered: floor_seg_has cannot ask which side of the copy an operand is on, and matching any operand would block taking a backup (`cp <adc> /tmp/backup`, what gcloud-creds exists to encourage).
# The cd-bridge form below IS covered (--dest-only); closing the flat half needs a position-aware argv helper.
if floor_seg_operand_under "$CRED_DESTROY_CMD" \
     "=$CRED_ABS" "=$CRED_ABS/identities" "$CRED_ABS/oauth-clients" \
     "%${CRED_ADC_RE}"; then
  floor_block bash "a relative destroy of the gcloud credential store, an ADC or the OAuth client after a cd into a parent" cred-cd-bridge-destroy.argv
fi
if floor_seg_operand_under '^([a-zA-Z0-9_./-]*/)?mv$' \
     "=$CRED_ABS" "=$CRED_ABS/identities" "$CRED_ABS/oauth-clients" \
     "%${CRED_ADC_RE}"; then
  floor_block bash "a relative mv of the gcloud credential store, an ADC or the OAuth client after a cd into a parent" cred-cd-bridge-move.argv
fi
if floor_seg_operand_under --dest-only '^([a-zA-Z0-9_./-]*/)?cp$' \
     "=$CRED_ABS" "=$CRED_ABS/identities" "$CRED_ABS/oauth-clients" \
     "%${CRED_ADC_RE}"; then
  floor_block bash "a relative cp ONTO the gcloud credential store, an ADC or the OAuth client after a cd into a parent" cred-cd-bridge-copy.argv
fi

if floor_seg_cwd_under "$CFG_ABS" "$LIVE_DIR" \
   || hit "(^|[^[:alnum:]_])cd[[:space:]]+[^;&|]*(${CFG_ABS_RE}|${LIVE_RE})(/[^[:space:];&|]*)?([[:space:]]|[;&|]|\$)"; then
  # THE VERB LIST IS ANCHORED ON BOTH SIDES (harbor#222, #289, #116; each was the gate blocking the auditing of the gate, §2.11). A right boundary stops `tee` inside `.helm-floor-teeth` and `notes.rm.bak` arming the rule (operand ORDER decided the verdict); a real invocation always has a separator after the verb, so no true positive is lost. `>` keeps NO right boundary (`>settings.json` is its ordinary spelling).
  # TWO hits, because the DIRECTORY branch owns its own anchor (start of the operand list, or after a space): the verb's right anchor ate the shared space and `cd <cfg> && mv hooks hooks.off` stopped blocking (floor-test V4).
  # `sed` IS NOT IN THIS LIST: it writes only with an in-place flag, so a read-only `sed -n` inside the config dir was refused (harbor#116); it is handled below on the surface rule's in-place predicate, so there is ONE definition of "this sed writes".
  # THE LEFT ANCHOR EXCLUDES A DASH (harbor#289): `-` is not alphanumeric or `_`, so a FLAG CLUSTER PARSED AS A COMMAND (`ls -ln bin`, `grep -ln p bin/*.sh`, `ls a-ln settings.json`). `/` MUST STAY ACCEPTED (`cd <cfg> && /bin/rm bin/admission-bash.sh`). `git-` IS AN ANCHOR IN ITS OWN RIGHT: git's dashed aliases (git-rm, git-mv) are real programs. ONE verb list, two anchors.
  # THE REDIRECT BRANCH KEEPS THE ORIGINAL ANCHOR, so no redirect that blocks today can stop; `(^|` is unusable in any of them (lint F2 forbids a mid-pattern alternation with it, and BSD grep never matches that branch).
  # P13C-5 — a fetcher names its file after the URL: `cd <cfg>/bin && curl -O <url>/admission-bash.sh` names no
  # surface anywhere, and wget writes into the cwd by default. Output to stdout (`curl -s`, `wget -O-`) passes.
  if floor_seg_has '^([a-zA-Z0-9_./-]*/)?curl$' '^(-[a-zA-Z]*[OJ][a-zA-Z]*|--remote-name(-all)?|--remote-header-name)$' \
     || floor_seg_flagval '^([a-zA-Z0-9_./-]*/)?curl$' '^(-o|--output)$' '^[^/~$-]' --short \
     || { floor_seg_has '^([a-zA-Z0-9_./-]*/)?wget2?$' \
          && ! floor_seg_flagval '^([a-zA-Z0-9_./-]*/)?wget2?$' '^(-O|--output-document)$' '^(-|/.*)$' --short \
          && ! floor_seg_has '^([a-zA-Z0-9_./-]*/)?wget2?$' '^(-[a-zA-Z]*O-|--spider)$'; }; then
    floor_block bash "cd into the config dir followed by a fetch that writes its file there" cd-cfg-then-fetch.argv
  fi
  _MUTV='(tee|cp|mv|install|truncate|ln|shred|rm|dd|chmod|chown|touch)'
  _MUT="(([^[:alnum:]_-]|[^[:alnum:]_]git-)${_MUTV}[[:space:]]|[^[:alnum:]_]>)"
  hit "${_MUT}[^;&|]*(${FILES}|(guard|floor|admission)-[a-z-]*\.(sh|awk)|library-admission\.sh)" \
    && floor_block bash "cd into the config dir followed by a file-mutating command" cd-cfg-then-mutate.flat
  hit "${_MUT}([^;&|]*[[:space:]])?(bin|hooks)([[:space:]/]|\$)" \
    && floor_block bash "cd into the config dir followed by a file-mutating command" cd-cfg-then-mutate.flat
  # sed, in place only, in BOTH operand orders (`sed s/a/b/ settings.json -i` blocks today; mirroring the surface rule's leading-only ordering would fix a false positive by opening a false negative; GNU sed accepts options after operands).
  # $_IPF and hit_cs are the surface rule's: the flag is a TOKEN, and the case-strict second pass keeps yq's `-I` from reading as `-i`.
  _SEDV="[^[:alnum:]_]sed[[:space:]]"
  _SEDF="(${FILES}|(guard|floor|admission)-[a-z-]*\.(sh|awk)|library-admission\.sh)"
  _SEDD="([^;&|]*[[:space:]])?(bin|hooks)([[:space:]/]|\$)"
  if hit_cs "$_IPF" && { hit "${_SEDV}[^;&|]*${_IPF}[^;&|]*${_SEDF}" \
                      || hit "${_SEDV}[^;&|]*${_SEDF}[^;&|]*${_IPF}" \
                      || hit "${_SEDV}[^;&|]*${_IPF}${_SEDD}" \
                      || hit "${_SEDV}${_SEDD}[^;&|]*${_IPF}"; }; then
    floor_block bash "cd into the config dir followed by a file-mutating command" cd-cfg-then-mutate.flat
  fi
  # harbor#280, the cd half: the rule keyed on ${FILES} (the pinned basenames), so cd-cfg-then-mutate above shadowed it and `cd <cfg>; echo hi > notes.txt` was ALLOWED (2026-08-23). THE cwd IS KNOWABLE HERE (the cd is in the same command), so a RELATIVE redirect target resolves inside the config dir; an ABSOLUTE one (`> /tmp/out`) or `> ../x` stays allowed.
  # `&1` IS NOT A FILE: the redirection table records `2>&1` with target `&1`, relative-looking and in no allowlist; blocking it would refuse the most common spelling in this repo's scripts. Excluded by prefix, pinned in the suite.
  cd_cfg_redirect_outside_allowlist() {
    [ -n "${FLOOR_SEGS:-}" ] || return 1
    printf '%s\n' "$FLOOR_SEGS" \
      | "$FLOOR_GREP" -E '^SEGR:[0-9]+:&?[0-9]*>>?[|!&]?:' 2>/dev/null \
      | sed -n 's/^SEGR:[0-9]*:[^:]*://p' \
      | "$FLOOR_GREP" -Ev '^([/~$&]|\.\./)' 2>/dev/null \
      | "$FLOOR_GREP" -Evq -- "^(\./)?${CFG_SESSION_WRITABLE}" 2>/dev/null
  }
  cd_cfg_redirect_outside_allowlist \
    && floor_block bash "cd into the config directory followed by a redirect inside it — §3 private state; only MEMORY/ and projects/ are session-writable" cd-cfg-then-redirect.path
  # THE SHAPE WITH NO PATH IN IT (pass 13): `cd ~/.claude && tar xzf /tmp/evil.tgz` extracts into the CURRENT directory, so no argument names the config dir and every path-matching rule sees a tar whose only operand is under /tmp. This is the one place the cwd is knowable (the cd is in the same command);
  # elsewhere a bare `tar xzf x.tgz` stays allowed, since a hook is not told the working directory. The verb list above cannot cover it: there is no name to match.
  arch_any_writes_cwd \
    && floor_block bash "cd into the config dir followed by an archive extracted into it" cd-cfg-then-extract.argv
  # AND THE SAME SHAPE FOR plutil (P13-fs-04): `cd ~/.claude && plutil -replace permissions.deny -json '[]' settings.json` names no path, so the argv rule above cannot see it, and a new rule outside this fold would hand back the cd bypass. cd-cfg-then-mutate.flat cannot take `plutil` (it would block the pure read `plutil -p settings.json`), so this arm reads the computed write-target list and the -o exemption comes with it.
  # THE TARGET TEST IS A RELATIVE NAME in the same set the two flat arms use ($FILES, a guard/floor script, or a path under bin/ or hooks/): "any relative target" would block a write to /tmp when the fold armed on its FLAT trigger with the cwd outside the config dir.
  # Residual: `cd <cfg> && plutil -create json skills/x/other.json` writes a non-surface file inside the config dir and is not caught.
  if [ -n "${PLU_WT:-}" ] \
     && printf '%s\n' "$PLU_WT" | "$FLOOR_GREP" -Eq -- \
        "^(\\./)*(${FILES}|(guard|floor|admission)-[a-z-]*\\.(sh|awk)|library-admission\\.sh|(bin|hooks)/+[^/]*)\$"; then
    floor_block bash "cd into the config dir followed by plutil rewriting a floor surface" cd-cfg-then-plutil.argv
  fi
  # The same shape reached through find's `{}` — see find_exec_writes_cwd.
  find_exec_writes_cwd \
    && floor_block bash "cd into the config dir followed by find -exec writing into it" cd-cfg-then-find-exec.argv
fi

# ── PROJECT-POLICY shapes ── deferred only to a wired repo guard (B5, harbor#954). Protected-branch force-push / hard reset: where the governing repo wires github_command_guard (a PreToolUse hook, or the scaffolder's lifecycle plugin installed and enabled) that guard owns it;
# anywhere else the floor is the sole gate (a marker alone left those repos unguarded).
if ! floor_repo_wires github_command_guard "$FLOOR_SCAFFOLDER_LIFECYCLE_PLUGIN"; then
  hit '(^|[^[:alnum:]_])git([[:space:]]+-[CcP][[:space:]]*[^[:space:]]*)*[[:space:]]+push([^|]*)(--force|--force-with-lease|-f)([^|]*)[[:space:]:/](main|master|production|prod)([[:space:]]|$)' \
    && floor_block bash "git push --force to a protected branch (no wired repo guard — floor is sole gate)" force-push-protected.flat
  hit '(^|[^[:alnum:]_])git([[:space:]]+-[CcP][[:space:]]*[^[:space:]]*)*[[:space:]]+push([^|]*)(--force|-f)([[:space:]]|$)' \
    && floor_block bash "git push --force (no wired repo guard — floor is sole gate)" force-push.flat
  # A leading `+` on a refspec forces that ref exactly as the flag does (harbor#1313). Bounded to the
  # push's own segment, so a later `date +%s` is not read as a refspec. A push option's VALUE can
  # start with `+` (`-o +x`): it is cut before the two rules below read the text.
  _TPO="$TARGETS"
  case "$CMD" in *push*) case "$CMD" in *' -o '*|*' --push-option '*)
    _TPO="$(printf '%s\n' "$TARGETS" | sed -E 's/[[:space:]](-o|--push-option)[[:space:]]+[^[:space:]]+/ /g')" ;; esac ;; esac
  hit_po() { [ -n "$_TPO" ] && "$FLOOR_GREP" -iEq -- "$1" <<HARBOR_ADMISSION_HIT_EOF
$_TPO
HARBOR_ADMISSION_HIT_EOF
  }
  hit_po '(^|[^[:alnum:]_])git([[:space:]]+-[CcP][[:space:]]*[^[:space:]]*)*[[:space:]]+push([^|;&]*)[[:space:]]["'"'"']?\+([^[:space:]]*[:/])?(main|master|production|prod)["'"'"']?([[:space:]]|$)' \
    && floor_block bash "git push of a +refspec to a protected branch (no wired repo guard — floor is sole gate)" force-push-protected.flat
  hit_po '(^|[^[:alnum:]_])git([[:space:]]+-[CcP][[:space:]]*[^[:space:]]*)*[[:space:]]+push([^|;&]*)[[:space:]]["'"'"']?\+[^[:space:]]' \
    && floor_block bash "git push of a +refspec, which forces it (no wired repo guard — floor is sole gate)" force-push.flat
  [ "${_GATE_PUSHMAIN:-0}" != 1 ] \
    || floor_block bash "a push straight to main or master skips the PR and its CI: push a branch, open its PR, then $(gate_merge_hint)" merge-raw.argv
fi

# Pass 14 E-1: over FLOOR_MAX_NORM (or past the normalizer) the segment table is empty and every
# argv-only rule goes silent, so padding a filesystem verb switched them off. Same backstop as
# guard-destroy's argv-blind-diskutil: name the verb, refuse the blind call. tar is not listed: its
# writes have flat twins over the cap, and an oversized `tar xO` read must pass (arch-o-oversized-payload-pure-read).
if floor_seg_degraded \
   && hit "${CMDPOS}([a-zA-Z0-9_./-]*/)?(rm|rmdir|unlink|shred|truncate|chmod|chown|chgrp|chflags|xattr|cp|mv|install|ditto|rsync|ln|dd|find)([[:space:]]|$)"; then
  floor_block bash "the argv tokenizer could not parse this call (over the ${FLOOR_MAX_NORM}-byte normalizer cap, or nested past what it expands) and it runs a filesystem verb, so the argv rules could not judge it. Re-run it under the cap, or the operator runs it as a \`!\` command" argv-blind-filesystem.flat
fi

# The TERMINAL clean pass: a command this guard actually judged and allowed. The early bails above emit nothing (declining to look is not an allow, and counting them poisons the false-positive-rate denominator).
floor_log_decision bash allow bash-clean.meta
exit 0
