#!/usr/bin/env sh
# library-gate.sh (harbor#1018) — the approval gate's shared library.
# Never run: sourced after library-log.sh, it sets no shell option. Repo-agnostic: a repo opts in with
# .agents/ship.conf. Contract, CLI and residual risks: docs/design/approval-gate.md.
#
#   gate_classify <root> [<ref>]     paths on stdin → PROTECTED TAB path TAB class for each protected one; 1 if any
#   gate_init <tool>                 an installed gate tool's preamble: only the installed copy runs
#   the ledger, the queue, the trust check and the merge: below, one comment each

# Every caller sets HERE to its own bin/ and has sourced library-log.sh already; a second source keeps its counts.
[ -n "${_LOG_LIB:-}" ] || . "$HERE/library-log.sh"
. "$HERE/library-fs.sh"   # fs_mtime, one spelling on BSD and GNU stat
GATE_TAB="$(printf '\t')"
GATE_MANIFEST=.agents/ship.conf   # the ship contract §1: a repo opts in with this one file
gate_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi | awk '{ print $1 }'; }

# ── the manifest and the register (the ship contract §1, §2) ──────────────────
gate_conf() { # <root> <key> → its values, one per line (a missing manifest prints nothing)
  [ -f "$1/$GATE_MANIFEST" ] || return 0
  awk -v k="$2" '{ sub(/(^|[ \t])#.*/, "") } $1 == k { $1 = ""; sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); print }' "$1/$GATE_MANIFEST"
}
gate_register_path() { # <root> → the register's repo-relative path
  _grp="$(gate_conf "$1" protected | head -1)"; printf '%s' "${_grp:-.agents/protected-paths.tsv}"
}
# The register's rows plus the three paths every repo protects whatever it says: the register, the manifest
# and .github/. `**` crosses directories, `*` and `?` do not. An absolute path or a `..` segment is protected.
# A manifest naming a register that is absent cannot be judged: exit 2. No manifest: only the three.
gate_classify() { # <root>; paths on stdin
  _gcr="$(gate_register_path "$1")"
  if [ -f "$1/$GATE_MANIFEST" ] && [ ! -f "$1/$_gcr" ]; then
    log_fail "$1/$GATE_MANIFEST names the register $_gcr, which is absent"; log_fix "git -C $1 log -1 -- $_gcr"; return 2
  fi
  { printf '%s\tregister\talways protected\n.agents/ship.conf\tmanifest\talways protected\n.github/**\tci-gate\talways protected\n' "$_gcr"
    [ ! -f "$1/$_gcr" ] || cat "$1/$_gcr"; } >"$GATE_TMP/rows"
  awk -F'\t' '
    function re(g,   i, c, o, n) { o = ""; n = length(g)
      for (i = 1; i <= n; i++) { c = substr(g, i, 1)
        if (c == "*") { if (substr(g, i + 1, 1) == "*") { o = o ".*"; i++ } else o = o "[^/]*" }
        else if (c == "?") o = o "[^/]"
        else if (index(".^$+(){}[]|\\", c)) o = o "\\" c
        else o = o c }
      return "^" o "$" }
    NR == FNR { if ($0 ~ /^#/ || NF < 2 || $1 == "glob") next; n++; pat[n] = re(tolower($1)); cls[n] = $2; next }
    { p = $0; sub(/^\.\//, "", p); if (p == "") next
      c = ""; if (p ~ /^\// || ("/" p "/") ~ /\/\.\.?\//) c = "unsafe"
      lp = tolower(p)   # case-insensitive: on macOS Bin/admission-bash.sh IS bin/admission-bash.sh (review finding 4)
      for (i = 1; c == "" && i <= n; i++) if (lp ~ pat[i]) c = cls[i]
      if (c != "") { printf "PROTECTED\t%s\t%s\n", p, c; hit = 1 } }
    END { exit hit ? 1 : 0 }' "$GATE_TMP/rows" -
}

# ── an installed tool's preamble ───────────────────────────────────────────────
# The allow and ask rules name <cfg>/bin/<tool>, physically, and the floor guards that directory. A copy, a
# symlink or the repo checkout's file is not the tool a rule names, so it refuses: the guard refuses the
# spelling first, and this is the second wall, for a copy made where the guard could not see it.
gate_init() { # <tool file name>
  GATE_CFG="$(CDPATH='' cd -P -- "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" 2>/dev/null && pwd -P)" \
    || die "no config dir at ${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "harbor deploy --apply --live   # from a terminal"
  GATE_BIN="$GATE_CFG/bin"; GATE_STATE="$GATE_CFG/.helm-approvals"; GATE_QDIR="$HOME/.local/state/harbor/approvals"
  _gself="$0"; case "$_gself" in /*) ;; *) _gself="$PWD/$_gself" ;; esac
  _gdir="$(CDPATH='' cd -P -- "${_gself%/*}" 2>/dev/null && pwd -P)"
  if [ -L "$_gself" ] || [ "$_gdir/${_gself##*/}" != "$GATE_BIN/$1" ]; then
    die "$_gself is not the installed $1: the gate runs only as $GATE_BIN/$1, the path its permission rule names" "$GATE_BIN/$1"
  fi
  GATE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/gate.XXXXXX")" || die "no temp dir" "df -h \"\${TMPDIR:-/tmp}\""
  trap 'rm -rf "$GATE_TMP"' EXIT
  # FAIL CLOSED: a check that cannot run is a refusal, never a pass (jq absent once read as "no hook found").
  for _gt in jq gh awk ps; do command -v "$_gt" >/dev/null 2>&1 || die "$_gt is not on PATH, so the gate cannot check anything" "harbor doctor"; done
  [ "$(printf '{"a":1}' | jq -r .a 2>/dev/null)" = 1 ] || die "jq does not work here, so the gate cannot check anything" "jq --version"
}

# ── was this run launched by Claude Code's own Bash tool, as the exact text the ask rule names? ──────────
# Measured 2026-10-07 on Claude Code 2.1.290 (macOS, docs/design/approval-gate.md "The ancestry"): the tool's
# parent is the Bash-tool shell, argv `<shell> -c source <cfg>/shell-snapshots/snapshot-<…>.sh 2>/dev/null || true
# && … && eval '<command>' < /dev/null && pwd -P >| /tmp/claude-<hex>-cwd`, and that shell's parent is the
# signed `claude` process. A glob, `eval`, a function, `sh file`, make, a git alias or any wrapper changes the text
# inside eval '…' or puts another process between, so the click is the only way to reach the canonical text here.
# gate_ancestry_judge <shell-argv> <claude-argv> <canonical> <cfg> → prints the refusal, or nothing when it holds.
gate_ancestry_judge() {
  _js="${1%% *}"; _jn="${_js##*/}"
  case "$_jn" in zsh|bash) ;; *) printf "the tool's parent is '%s', not Claude Code's Bash-tool shell" "${_js:-nothing}"; return 1 ;; esac
  case "$1" in "$_js -c source $4/shell-snapshots/snapshot-"*) ;;
    *) printf "the parent shell is not a Bash-tool shell of this config dir (no snapshot source)"; return 1 ;; esac
  _jr="${1#* && eval \'}"
  [ "$_jr" != "$1" ] || { printf "the parent shell evaluates no command"; return 1; }
  # before the command: the snapshot source, then only the setup steps measured in the real argv, each of a fixed shape
  _jpre="${1%%" && eval '"*}"; _jpre="${_jpre#"$_js -c source $4/shell-snapshots/snapshot-"}"
  _jsn="${_jpre%%" "*}"; case "$_jsn" in *.sh) ;; *) printf "the parent shell's snapshot is not a .sh file"; return 1 ;; esac
  case "$_jsn" in *[!A-Za-z0-9._-]*) printf "the parent shell's snapshot name is not plain"; return 1 ;; esac
  printf '%s' "${_jpre#"$_jsn"}" | awk 'BEGIN { RS = "\001" } {
      n = split($0, g, / && /); if (g[1] != " 2>/dev/null || true") exit 1
      for (i = 2; i <= n; i++) {
        if (g[i] ~ /^setopt [A-Z_ ]+ 2>\/dev\/null \|\| true$/) continue
        if (g[i] ~ /^shopt -[su] [a-z_ ]+ 2>\/dev\/null \|\| true$/) continue
        if (g[i] ~ /^\{ \\builtin unalias -- .[A-Za-z_]+.; \\builtin unset -f -- .[A-Za-z_]+.; \} >\/dev\/null 2>&1 \|\| true$/) continue
        exit 1 } }' || { printf "the parent shell does more than source its snapshot before the command"; return 1; }
  _jt="${_jr#"$3"\' < /dev/null && pwd -P >| }"
  [ "$_jt" != "$_jr" ] || { printf "the command Claude Code evaluated is not exactly the canonical text (%s)" "$(printf '%s' "${_jr%%\' < /dev/null*}" | cut -c1-160)"; return 1; }
  case "$_jt" in *[[:space:]]*|'') printf "the parent shell runs more after the command"; return 1 ;; */claude-*-cwd) ;; *) printf "the parent shell's tail is not Claude Code's"; return 1 ;; esac
  _jc="${2%% *}"
  [ "${_jc##*/}" = claude ] || { printf "the Bash-tool shell's parent is '%s', not claude" "${_jc:-nothing}"; return 1; }
  for _jw in $2; do case "$_jw" in
    -p|--print|--settings|--settings=*|--plugin-dir|--plugin-dir=*|--permission-prompt-tool|--permission-prompt-tool=*|--dangerously-skip-permissions|--allow-dangerously-skip-permissions|--permission-mode|--permission-mode=*|--allowedTools|--allowedTools=*|--allowed-tools|--allowed-tools=*|--mcp-config|--mcp-config=*|--agents|--agents=*)
      printf "the claude session was started with %s, which can answer or skip the prompt" "$_jw"; return 1 ;; esac; done
  return 0
}
gate_live_cfg() { # the operator's own ~/.claude, from the account database, never from $HOME
  _gu="$(id -un)"; case "$_gu" in ''|*[!A-Za-z0-9._-]*) return 1 ;; esac
  eval "_gh=~$_gu"; CDPATH='' cd -P -- "$_gh/.claude" 2>/dev/null && pwd -P
}
gate_secs() { awk -F'[-:]' '{ s = 0; m = 1; for (i = NF; i >= 1; i--) { s += $i * m; m = (i == NF || i == NF - 1) ? m * 60 : (i == NF - 2 ? m * 24 : m) } print s }'; }
gate_claude_exe() { # <pid> → the executable's path
  if [ -r "/proc/$1/exe" ]; then readlink "/proc/$1/exe"; return; fi
  lsof -a -p "$1" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}
gate_ancestry() { # <canonical command text> → sets GATE_CLAUDE_PID; dies unless the click's path launched this run
  # System tools only (#1127 r2 #1): a session can put a shim earlier on PATH (~/.local/bin) that makes ps, lsof, id or tr lie.
  _gapath="$PATH"; PATH=/usr/bin:/bin:/usr/sbin:/sbin
  GATE_CLAUDE_PID="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"
  _gsa="$(ps -ww -o args= -p "$PPID" 2>/dev/null)" || _gsa=''
  _gca="$(ps -ww -o args= -p "${GATE_CLAUDE_PID:-0}" 2>/dev/null)" || _gca=''
  _glive="$(gate_live_cfg)" || _glive=''
  # an unreadable account dir is never a sandbox: the proof runs (#1127 r2 #1, an `id` shim skipped it)
  if [ -n "$_glive" ] && [ "$GATE_CFG" != "$_glive" ] && [ "${HARBOR_GATE_ENFORCE_ANCESTRY:-}" != 1 ]; then
    log_note "ancestry not checked: $GATE_CFG is not this account's ~/.claude (a sandbox install acts with nothing a direct gh call lacks)"
    PATH="$_gapath"; return 0
  fi
  _gwhy="$(gate_ancestry_judge "$_gsa" "$_gca" "$1" "$GATE_CFG")" \
    || die "no click launched this run: $_gwhy" "ask for it as exactly: $1"
  _gexe="$(gate_claude_exe "$GATE_CLAUDE_PID")"
  case "$(uname -s)" in
    Darwin) codesign --verify --strict -R='identifier "com.anthropic.claude-code" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW"' "$_gexe" 2>/dev/null \
              || die "the claude process ($GATE_CLAUDE_PID, ${_gexe:-no executable}) is not Anthropic's signed Claude Code" "ask for it from a Claude Code session: $1" ;;
    *) case "$_gexe" in "${_glive%/.claude}/.local/share/claude/versions/"*) ;;
         *) die "the claude process ($GATE_CLAUDE_PID, ${_gexe:-no executable}) is not this account's Claude Code install" "ask for it from a Claude Code session: $1" ;; esac ;;
  esac
  PATH="$_gapath"
  log_ok "launched by the Bash tool of Claude Code session $GATE_CLAUDE_PID, as the exact text the ask rule names"
}
gate_repo_ok() { case "$1" in */*/*|/*|*/|*[!A-Za-z0-9._/-]*) return 1 ;; ?*/?*) return 0 ;; *) return 1 ;; esac; }
gate_killed() { [ -e "$GATE_CFG/.harbor-autoship.off" ]; }
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit 1; }

# The manifest and register of <repo> as its default branch holds them on GitHub: the merged truth, which no
# edit in a local checkout (a file, a ref) can change. Sets GATE_ROOT (a temp tree), GATE_MAIN and GATE_WF.
gate_fetch_conf() { # <repo>
  GATE_MAIN="$(gh api "repos/$1" --jq .default_branch 2>/dev/null)" || die "$1: gh api repos/$1 failed" "gh auth status"
  GATE_ROOT="$GATE_TMP/root"; mkdir -p "$GATE_ROOT/.agents"
  # merge-stack reads the required checks through git, from <checkout>'s origin (#1126 r5): a blobless repo whose only
  # remote is GitHub's copy of <repo>, so nothing local supplies them.
  { git init -q "$GATE_ROOT" && git -C "$GATE_ROOT" remote add origin "https://github.com/$1.git" \
      && git -C "$GATE_ROOT" config remote.origin.promisor true && git -C "$GATE_ROOT" config remote.origin.partialclonefilter blob:none; } \
    || die "$1: cannot set up the gate's git tree in $GATE_ROOT" "git --version"
  _graw() { gh api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$2?ref=$GATE_MAIN" 2>/dev/null; }
  _graw "$1" "$GATE_MANIFEST" >"$GATE_ROOT/$GATE_MANIFEST" || rm -f "$GATE_ROOT/$GATE_MANIFEST"
  if [ -f "$GATE_ROOT/$GATE_MANIFEST" ]; then
    _grg="$(gate_register_path "$GATE_ROOT")"; mkdir -p "$GATE_ROOT/$(dirname "$_grg")"
    _graw "$1" "$_grg" >"$GATE_ROOT/$_grg" || rm -f "$GATE_ROOT/$_grg"
    [ "$(gate_conf "$GATE_ROOT" repo | head -1)" = "$1" ] || die "$1: its .agents/ship.conf names repo '$(gate_conf "$GATE_ROOT" repo | head -1)'" "fix the repo line on $GATE_MAIN"
  fi
  GATE_WF="$(gate_conf "$GATE_ROOT" workflow | head -1)"
  # merge-stack reads <checkout>/.agents/required-checks.tsv: the repo's own declaration as merged (contract §5a.6), never
  # a working tree. Without one, merge-check falls back to branch protection, and refuses when nothing gates.
  _graw "$1" .agents/required-checks.tsv >"$GATE_ROOT/.agents/required-checks.tsv" && [ -s "$GATE_ROOT/.agents/required-checks.tsv" ] \
    || rm -f "$GATE_ROOT/.agents/required-checks.tsv"
}

# ── the ledger: one row per decision, under the config dir the floor guards ─────
# time TAB action TAB args TAB sha256(args) TAB outcome. A session cannot write it (guard-bash, guard-selfedit, B1).
gate_ledger() { # <action> <args> <outcome>
  mkdir -p "$GATE_STATE" 2>/dev/null && chmod 700 "$GATE_STATE" 2>/dev/null
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$(printf '%s' "$2" | gate_sha256)" "$3" \
    >>"$GATE_STATE/ledger.tsv" || log_warn "could not append to $GATE_STATE/ledger.tsv"
}

# ── the queue (contract §4): approvals waiting for the operator, never asked unattended ──
# queue.jsonl: {id, ts, kind, repo, pr?, sha, reason, command} opens a row, {id, ts, closed, outcome} closes it.
# Each open is an approval.open (subject = id) on the event bus, kind approval in the ledger, so it shows as ⧗N.
gate_qid() { # merge <repo> <pr> <sha> | deploy <repo> <sha> → <kind>-<owner>_<name>[-<pr>]-<sha12> (contract §5a.2)
  if [ "$1" = merge ]; then printf 'merge-%s-%s-%s' "$(printf '%s' "$2" | tr / _)" "$3" "$(printf '%s' "$4" | cut -c1-12)"
  else printf 'deploy-%s-%s' "$(printf '%s' "$2" | tr / _)" "$(printf '%s' "$3" | cut -c1-12)"; fi
}
gate_queue_state() { # <id> → open | closed | nothing
  [ -f "$GATE_QDIR/queue.jsonl" ] || return 0
  jq -r -n --arg i "$1" '[inputs | select(.id == $i)] | last | if . == null then "" elif .closed then "closed" else "open" end' \
    "$GATE_QDIR/queue.jsonl" 2>/dev/null || :
}
gate_bus() { [ ! -f "$GATE_BIN/event-bus.sh" ] || sh "$GATE_BIN/event-bus.sh" emit "$@" --src gate >/dev/null 2>&1 || :; }
gate_queue_add() { # <kind> <repo> <pr|-> <sha> <reason> → sets GATE_QID and GATE_QCMD (the exact approve command)
  if [ "$1" = merge ]; then _gqi="$(gate_qid merge "$2" "$3" "$4")"; _gqc="$GATE_BIN/gate-approve.sh merge $2 $3 $4"
  else _gqi="$(gate_qid deploy "$2" "$4")"; _gqc="$GATE_BIN/gate-approve.sh deploy $2 $4"; fi
  GATE_QID="$_gqi"; GATE_QCMD="$_gqc"
  mkdir -p "$GATE_QDIR" && chmod 700 "$GATE_QDIR" 2>/dev/null
  if [ "$(gate_queue_state "$_gqi")" = open ]; then log_note "already queued: $_gqi"; return 0; fi
  _gnow="$(date -u +%s)"
  _gdl="$(date -u -r $((_gnow + 86400)) +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$((_gnow + 86400))" +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn --arg i "$_gqi" --arg k "$1" --arg r "$2" --arg p "$3" --arg s "$4" --arg w "$5" --arg c "$_gqc" \
    '{id: $i, ts: (now | todate), kind: $k, repo: $r} + (if $p == "-" then {} else {pr: ($p | tonumber)} end)
     + {sha: $s, reason: $w, command: $c}' >>"$GATE_QDIR/queue.jsonl"
  _glk=''; [ "$1" != merge ] || _glk="https://github.com/$2/pull/$3"
  gate_bus approval.open "$_gqi" --repo "$2" --data "$(jq -cn --arg t "approve $_gqi: $5" --arg d "$_gdl" --arg l "$_glk" \
    '{title: $t[0:120], deadline_ts: $d} + (if $l == "" then {} else {link: $l} end)')"
  log_note "queued for the operator ($_gqi): $_gqc"
}
gate_queue_close() { # <id> <outcome>
  [ "$(gate_queue_state "$1")" = open ] || return 0
  jq -cn --arg i "$1" --arg o "$2" '{id: $i, ts: (now | todate), closed: true, outcome: $o}' >>"$GATE_QDIR/queue.jsonl"
  gate_bus approval.close "$1"
  log_note "closed in the queue: $1 ($2)"
}

# ── is a click in this session the operator's? ──────────────────────────────────
# The ask rule must be there (without it nothing asked anyone), bypass mode must be off, and no PermissionRequest
# hook Harbor does not own may exist: such a hook can grant a prompt with no person (harbor#1018). Managed settings
# are root's, so they are trusted. Not seen here: --settings on claude's command line, and mods (#940, #1022).
gate_trust() {
  _gts="$GATE_CFG/settings.json"; _gta="Bash($GATE_BIN/gate-approve.sh *)"
  jq -e --arg a "$_gta" '(.permissions.ask // []) | index($a) != null' "$_gts" >/dev/null 2>&1 \
    || die "the ask rule $_gta is not in $_gts, so nothing asked the operator" "harbor deploy --apply --live   # from a terminal: floor-deny adds it"
  [ "$(jq -r '.permissions.disableBypassPermissionsMode // ""' "$_gts" 2>/dev/null)" = disable ] \
    || die "bypass-permissions mode is not disabled in $_gts, so a prompt may never have been shown" "harbor deploy --apply --live   # from a terminal"
  # Harbor wires NO PermissionRequest hook, so the allow-list is empty and any one is foreign: it can answer the prompt.
  _gtf=''; _gtl_all=''
  for _gtl in "$_gts" "$GATE_CFG/settings.local.json" "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/settings.json" \
              "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/settings.local.json" "$PWD/.claude/settings.json" "$PWD/.claude/settings.local.json"; do
    [ -f "$_gtl" ] || continue
    _gtl_all="$_gtl_all $_gtl"
    _gtx="$(jq -r '[(.hooks.PermissionRequest // [])[]] | length' "$_gtl" 2>/dev/null)" || _gtx=unreadable
    [ "$_gtx" = 0 ] || _gtf="$_gtf $_gtl"
  done
  # every file a session can LOAD, whatever its name: a hook can be inline in plugin.json, and a mod's tool.check
  # approves. Skipped: marketplace checkouts and the top-level catalogue files, which list event names and never run;
  # installing copies a plugin into cache/, and an installPath outside it is scanned too (harbor#1018).
  _gti=''; _gtj="$GATE_CFG/plugins/installed_plugins.json"
  [ ! -f "$_gtj" ] || _gti="$(jq -r '[.plugins[]?[]?.installPath // empty] | .[]' "$_gtj" 2>/dev/null)" || _gtf="$_gtf $_gtj"
  # under set -e every step must not fail: a missing dir is skipped, an unreadable one or file is a hit (fail closed)
  _gtp="$( { [ ! -d "$GATE_CFG/plugins" ] || find "$GATE_CFG/plugins" -path "$GATE_CFG/plugins/marketplaces" -prune \
               -o -type f -path "$GATE_CFG/plugins/*/*" -print || echo "$GATE_CFG/plugins:unreadable"
             for _gtd in "$GATE_CFG/dev-mods" "$GATE_CFG/mods"; do
               [ ! -d "$_gtd" ] || find "$_gtd" -type f -print || echo "$_gtd:unreadable"; done
             [ -z "$_gti" ] || printf '%s\n' "$_gti" | while IFS= read -r _gtd; do
               [ ! -e "$_gtd" ] || find "$_gtd" -type f -print || echo "$_gtd:unreadable"; done
           } 2>/dev/null | while IFS= read -r _gtq; do
             case "$_gtq" in
               (*:unreadable) echo "$_gtq" ;;
               (*.json|*.js|*.mjs|*.ts) _gtr=0; grep -l -e PermissionRequest -e 'tool\.check' "$_gtq" 2>/dev/null || _gtr=$?
                                         [ "$_gtr" -lt 2 ] || echo "$_gtq:unreadable" ;;
             esac; done | head -3 | tr '\n' ' ')"
  [ -z "$_gtp" ] || _gtf="$_gtf $_gtp"
  [ -z "$_gtf" ] || die "a PermissionRequest hook or approving mod is configured ($(echo $_gtf)): it can answer the prompt, so this approval is not trusted" \
    "remove it, restart Claude Code, then ask again"
  # hooks are read when the session starts: a settings file changed since then may not be what this session runs
  _gtpath="$PATH"; PATH=/usr/bin:/bin:/usr/sbin:/sbin   # system ps and tr, as gate_ancestry (#1127 r2 #1)
  _gtpid="${GATE_CLAUDE_PID:-}"
  [ -n "$_gtpid" ] || _gtpid="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"
  case "$(ps -ww -o args= -p "${_gtpid:-0}" 2>/dev/null)" in claude|claude\ *|*/claude|*/claude\ *) ;; *) _gtpid='' ;; esac
  if [ -n "$_gtpid" ]; then
    _gte="$(ps -o etime= -p "$_gtpid" 2>/dev/null | tr -d ' ' | gate_secs)"; _gtnow="$(date +%s)"
    for _gtl in $_gtl_all; do
      _gtm="$(fs_mtime "$_gtl" 2>/dev/null)" || _gtm=''
      case "$_gtm" in ''|*[!0-9]*) die "cannot read when $_gtl changed" "ls -l $_gtl" ;; esac
      [ "$_gtm" -le $((_gtnow - ${_gte:-0})) ] || die "$_gtl changed after this Claude Code session started, so the session may run hooks it does not show" \
        "restart Claude Code, then ask again"
    done
  fi
  PATH="$_gtpath"
}

# ── a PR: its exact head, the paths that head changes, and the merge ─────────────
gate_pr_head() { # <n> → the head sha of an OPEN PR into the default branch, or die
  _gv="$(gh pr view "$1" -R "$R" --json state,baseRefName,headRefOid --jq '"\(.state) \(.baseRefName) \(.headRefOid)"' 2>/dev/null)" \
    || die "$R#$1: gh pr view failed" "gh pr view $1 -R $R"
  set -- "$1" $_gv
  [ "${2:-}" = OPEN ] || die "$R#$1 is ${2:-unknown}, not open" "gh pr view $1 -R $R"
  [ "${3:-}" = "$GATE_MAIN" ] || die "$R#$1 is based on ${3:-?}, not $GATE_MAIN: the gate merges into the default branch only" "gh pr edit $1 -R $R --base $GATE_MAIN"
  case "${4:-}" in [0-9abcdef]*) printf '%s' "$4" ;; *) die "$R#$1: no head sha" "gh pr view $1 -R $R" ;; esac
}
gate_pr_paths() { # <sha> → every path the change at <sha> touches against its merge-base: renames give both
  _gj="$(gh api "repos/$R/compare/$GATE_MAIN...$1" 2>/dev/null)" || die "could not compare $GATE_MAIN...$1" "gh api repos/$R/compare/$GATE_MAIN...$1"
  _gn="$(printf '%s' "$_gj" | jq '.files | length' 2>/dev/null || echo x)"
  case "$_gn" in ''|*[!0-9]*) die "the compare of $GATE_MAIN...$1 has no file list" "gh api repos/$R/compare/$GATE_MAIN...$1" ;; esac
  # GitHub lists at most 300 files, so a longer list cannot be judged complete: protected, for a person.
  [ "$_gn" -lt 300 ] || printf '/more-than-300-files\n'
  printf '%s' "$_gj" | jq -r '.files[] | .filename, (.previous_filename // empty)'
}
# gate_merge_pr <n> <sha> <action>: through merge-stack (contract §5b.10), on a plan pinned to <sha>: `pr N head <sha>`.
# merge-stack judges every workflow on that head green, runs merge-check, and squashes with --match-head-commit <sha>;
# any other head is needs-rebase (exit 3), never synced. The plan's checkout is the gate's own tree of what GitHub holds
# on the default branch, so no local checkout, and no edit in one, can change what the merge is judged against.
gate_merge_pr() {
  { printf 'repo %s\ncheckout %s\npr %s head %s\n' "$R" "$GATE_ROOT" "$1" "$2"; [ -z "$GATE_WF" ] || printf 'workflow %s\n' "$GATE_WF"
    _gm="$(gate_conf "$GATE_ROOT" method | head -1)"; [ -z "$_gm" ] || printf 'method %s\n' "$_gm"; } >"$GATE_TMP/plan"
  _gmr=0; sh "$GATE_BIN/gate-merge-stack.sh" merge "$GATE_TMP/plan" </dev/null >&2 || _gmr=$?
  case "$_gmr" in
    0) [ "$(gh pr view "$1" -R "$R" --json state --jq .state 2>/dev/null)" = MERGED ] \
         || { gate_ledger "$3" "$R $1 $2" merge-failed; die "$R#$1: merge-stack ended clean but the PR is not merged" "gh pr view $1 -R $R"; } ;;
    3) gate_ledger "$3" "$R $1 $2" refused-moved; die "$R#$1 moved off $2: needs-rebase, and an approval covers one exact head" "gh pr view $1 -R $R" ;;
    *) gate_ledger "$3" "$R $1 $2" refused-red; die "$R#$1: merge-stack refused it (red, or a check missing): nothing is merged red" "gh pr checks $1 -R $R" ;;
  esac
  gate_ledger "$3" "$R $1 $2" merged
  log_ok "$R#$1 merged at $2"
}
