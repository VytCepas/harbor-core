#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-0}" = "1" ] && exit 0
# guard-destroy (harbor#201) - PreToolUse(Bash) ASK/DENY gate for LOCAL work destruction (git clean -f, git reset --hard, diskutil erase*), the class an unattended agent causes while tidying up.
# Two tiers: CATASTROPHIC (diskutil wipe) is DENY always, since an ASK would auto-approve unattended; WORK-LOSS (git clean -f*, reset --hard, ...) is ASK, DENY with HARBOR_ADMISSION_DESTROY_POSTURE=deny.
# A warning layer, not a boundary (runtime string assembly, a disabled floor). git checkout/restore are not gated (too routine to ask on); each discard snapshots the worktree to refs/snapshots/ first (harbor#1290).
# Fail-open at the ask tier only: when floor_seg_load yields nothing every argv rule vanishes, and the floor_seg_degraded block below backstops the deny tier (harbor#306).
# Removed notes: docs/explanation/code-cases/bin-admission-destroy.md
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./library-admission.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/library-admission.sh"

floor_read_stdin
floor_shell_tool "$(floor_field '.tool_name')" || exit 0
CMD="$(floor_field '.tool_input.command')"
[ -n "$CMD" ] || exit 0
# The digest subject (harbor#350), set as in admission-bash.sh: without it floor_obs_digest returns "-" for deny/ask records.
# shellcheck disable=SC2034 # FLOOR_OBS_SUBJECT: read by library-admission.sh
FLOOR_OBS_SUBJECT="$CMD"

floor_seg_load "$CMD"

# harbor#302: a heredoc body is a document here too, as in admission-bash.sh since harbor#89. The veto requires the heredoc to be opened by SEGMENT 1 and must NOT be widened:
# with the opener allowed anywhere, a heredoc piped into sh or curl becomes a total bypass, because FLOOR_SEGS carries no pipeline boundary (fixing that changes an output contract of admission-normalize.awk).
# --publisher-inert is correct for both: neither guard judges publication; guard-egress does, and does not pass the flag.
if floor_heredoc_inert_only --publisher-inert; then exit 0; fi

# harbor#781: unwrap a wrapper the peel does not know (`gtimeout 5 diskutil eraseDisk`) so it cannot hide the tool. After the veto; the case keeps awk off calls naming no gated verb.
# The snapshot verbs (harbor#1290) are listed too: none is a rule's verb, so unwrapping them changes no verdict.
case "${FLOOR_SEGS:-}" in
  *[dD][iI][sS][kK][uU][tT][iI][lL]*) floor_seg_unwrap '^([^:]*/)?(diskutil|git)$' ;;
  *[gG][iI][tT]*) case "$FLOOR_SEGS" in *clean*|*reset*|*stash*|*reflog*|*worktree*|*checkout*|*restore*|*switch*|*push*)
    floor_seg_unwrap '^([^:]*/)?(diskutil|git)$' ;; esac ;;
esac

# harbor#1313: mv/install with a raw /dev disk node as an operand replaces or removes the node: ASK (operator decision 2026-10-18; the device-content writers deny in guard-bash).
# Each operand is expanded and dot-collapsed first, so /dev/shm/../sda reads as /dev/sda.
dev_node_replace() {
  case "${FLOOR_SEGS:-}" in *[mM][vV]*|*[iI][nN][sS][tT][aA][lL][lL]*) ;; *) return 1 ;; esac
  _dnr_re='/dev/(sd|hd|vd|xvd|nvme|disk|rdisk|mmcblk|loop|dm-|mapper/|md[0-9])|^/dev/?$'
  for _dnr_id in $(_floor_seg_ids '^([a-zA-Z0-9_./-]*/)?(mv|install)$' ci); do
    printf '%s\n' "$FLOOR_SEGS" | sed -n "s/^SEGA:${_dnr_id}://p" \
      | while IFS= read -r _dnr_t; do floor_collapse_dots "$(floor_expand_paths "$_dnr_t")"; echo; done \
      | "$FLOOR_GREP" -Eq -- "$_dnr_re" && return 0
  done
  return 1
}

REASON=""; DECISION=""; RULE=""; SHAPE="argv"
# --- CATASTROPHIC: irreversible device wipe → deny, always ------------------
if floor_seg_has '^([^:]*/)?diskutil$' '^erase|^secureErase$|^reformat$|^zeroDisk$|^randomDisk$|^partitionDisk$|^deleteContainer$|^deleteVolume'; then
  DECISION="deny"; RULE="diskutil-wipe"; REASON="diskutil device/volume wipe — IRREVERSIBLE physical destruction"
# --- WORK-LOSS: git ops that destroy the working tree or its recovery net → ask
elif floor_seg_has '^([^:]*/)?git$' '^clean$' '^--force$|^-[a-zA-Z]*f[a-zA-Z]*$'; then
  DECISION="ask";  RULE="git-clean-force"; REASON="git clean -f permanently deletes untracked/ignored files (no reflog)"
# git takes any unambiguous prefix of a long flag, and --h is already --hard (harbor#1313).
elif floor_seg_has '^([^:]*/)?git$' '^reset$' '^--h(a(rd?)?)?$'; then
  DECISION="ask";  RULE="git-reset-hard"; REASON="git reset --hard discards the working tree"
elif floor_seg_has '^([^:]*/)?git$' '^stash$' '^clear$|^drop$'; then
  DECISION="ask";  RULE="git-stash-drop"; REASON="git stash clear/drop deletes stashed work (not in the branch reflog)"
elif floor_seg_has '^([^:]*/)?git$' '^reflog$' '^expire$'; then
  DECISION="ask";  RULE="git-reflog-expire"; REASON="git reflog expire destroys the recovery net reset/branch-D rely on"
elif floor_seg_has '^([^:]*/)?git$' '^worktree$' '^remove$' '^--force$|^-[a-zA-Z]*f[a-zA-Z]*$'; then
  DECISION="ask";  RULE="git-worktree-remove-force"; REASON="git worktree remove --force discards a worktree's uncommitted work"
elif dev_node_replace; then
  DECISION="ask";  RULE="device-node-replace"; REASON="mv/install with a raw /dev disk node as an operand replaces or removes the device node (harbor#1313)"
fi

# harbor#306, THE ARGV LAYER WENT BLIND: every rule above is floor_seg_has, so when floor_seg_load yields no table (over FLOOR_MAX_NORM, no awk, admission-normalize.awk missing) a diskutil wipe was a silent allow.
# The backstop asks only what it can answer without the tokenizer, whether the text names diskutil, and denies; a second copy of the rules would drift. The ask tier is deliberately not covered (git appears in huge commands constantly).
# jq absent is covered one layer up: admission-hook.sh's jq canary denies before this runs.
if [ -z "$DECISION" ] && floor_seg_degraded; then
  # floor_bash_targets forks awk and runs only here, so the allow path stays cheap; over the cap it returns the raw command.
  _DT="$(floor_bash_targets "$CMD")"
  if printf '%s' "$_DT" | "$FLOOR_GREP" -iEq -- '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?diskutil([[:space:]]|$)'; then
    DECISION="deny"; RULE="argv-blind-diskutil"; SHAPE="flat"
    REASON="the argv tokenizer could not parse this call (over the ${FLOOR_MAX_NORM}-byte normalizer cap, nested past what the normalizer expands, or awk/admission-normalize.awk unavailable) and the command names diskutil, whose erase/reformat/zero verbs are deny-always — so the guard cannot tell an IRREVERSIBLE device wipe from a diskutil list. Re-run it under the cap, or the operator runs it themselves as a \`!\` command, which is not a tool call"
  fi
fi

# harbor#1290, a discard snapshots uncommitted work first. Before a checkout/restore with a pathspec, a hard or merge reset, a forced checkout/switch or a forced clean runs, the worktree it acts on (the call's .cwd, folded through cd/pushd and -C)
# is written to refs/snapshots/<epoch>-<pid> from a temp index (the real index is never written); clean trees and branch switches take none; refs older than 7 days go with the next write.
# A failure is one stderr line stamped [check:admission.destroy-snapshot], never a refusal; the one refusal is a push that would publish refs/snapshots. Contract and recovery: docs/explanation/admission-baseline.md.
_snap_plan() { # stdout rows: SNAP|MAYBE|PUSH <tab> <dir> <tab> <verb|arg|explicit>, or BLIND <tab> <verb> <tab> <why>
  # NO APOSTROPHES IN THIS PROGRAM: it is a single-quoted shell string.
  { printf 'CWD:%s\n' "$(floor_field '.cwd')"; printf '%s\n' "$FLOOR_SEGS"; } | awk -v home="$HOME" '
    function norm(p,   n, i, a, out, k, lead, r) {
      lead = (substr(p, 1, 1) == "/"); n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k > 0) k--; continue }
        out[++k] = a[i]
      }
      r = ""; for (i = 1; i <= k; i++) r = r ((i == 1 && !lead) ? "" : "/") out[i]
      return (r == "") ? (lead ? "/" : "") : r
    }
    # The cd-fold resolve of floor_seg_cwd_under, lexical: a substitution, a variable or a glob is unknown.
    function resolve(t, c) {
      if (t == "~" || t == "$HOME" || t == "${HOME}") return home
      if (substr(t, 1, 2) == "~/") return norm(home substr(t, 2))
      if (substr(t, 1, 6) == "$HOME/") return norm(home substr(t, 6))
      if (substr(t, 1, 8) == "${HOME}/") return norm(home substr(t, 8))
      if (index(t, "@SUB@") || index(t, "$") || index(t, "`") || t ~ /[*?]/ || substr(t, 1, 1) == "~") return ""
      if (substr(t, 1, 1) == "/") return norm(t)
      return (c == "") ? "" : norm(c "/" t)
    }
    function base(t) { sub(/.*\//, "", t); return tolower(t) }
    function short(t, ch) { return (t ~ /^-[a-zA-Z0-9]+$/ && index(substr(t, 2), ch) > 0) }
    function emit(kind, d, x) {
      if (kind == "PUSH" && x == 0 && (BL != "" || d == "")) return
      if (BL != "") { print "BLIND\t" VERB "\t" BL; return }
      if (d == "") { print "BLIND\t" VERB "\tthe folder it runs in is unknown"; return }
      print kind "\t" d "\t" x
    }
    function gitseg(i,   k, n, t, d, np, P, disc, dd, after, made, st, wt, force, dry) {
      n = N[i]; d = cwd; BL = (i in GE) ? "a GIT_DIR or GIT_WORK_TREE assignment moves it" : ""
      for (k = 1; k <= n; k++) {
        t = A[i, k]
        if (t == "-C") { k++; d = resolve(A[i, k], d); continue }
        if (t == "-c" || t == "--namespace" || t == "--config-env" || t == "--attr-source") { k++; continue }
        if (t == "--git-dir" || t == "--work-tree") { k++; BL = "it names --git-dir or --work-tree"; continue }
        if (t ~ /^--(git-dir|work-tree)=/) { BL = "it names --git-dir or --work-tree"; continue }
        if (substr(t, 1, 1) == "-") continue
        break
      }
      if (k > n) return
      VERB = A[i, k]
      if (VERB == "checkout") {
        np = 0; disc = 0; dd = 0; after = 0; made = 0
        for (k++; k <= n; k++) {
          t = A[i, k]
          if (dd) { after++; continue }
          if (t == "--") { dd = 1; continue }
          if (t == "-b" || t == "-B" || t == "--orphan") { made = 1; k++; continue }
          if (t ~ /^--(force|ours|theirs|patch|merge|pathspec-from-file)(=|$)/) { disc = 1; continue }
          if (t ~ /^-[a-zA-Z0-9]+$/) {
            if (short(t, "f") || short(t, "p") || short(t, "m")) disc = 1
            if (short(t, "b") || short(t, "B")) { made = 1; k++ }
            continue
          }
          if (substr(t, 1, 1) == "-") continue
          P[++np] = t
        }
        # One bare operand is a branch OR a path, which only the repository can say: MAYBE.
        if (disc || after > 0 || np >= 2) emit("SNAP", d, VERB)
        else if (np == 1 && !made && P[1] != "-") emit("MAYBE", d, P[1])
      } else if (VERB == "switch") {
        disc = 0
        for (k++; k <= n; k++) {
          t = A[i, k]
          if (t == "-c" || t == "-C" || t == "--create" || t == "--force-create" || t == "--orphan") { k++; continue }
          if (t ~ /^--(force|discard-changes|merge)$/ || short(t, "f") || short(t, "m")) disc = 1
        }
        if (disc) emit("SNAP", d, VERB)
      } else if (VERB == "restore") {
        st = 0; wt = 0
        for (k++; k <= n; k++) {
          t = A[i, k]
          if (t == "-s" || t == "--source") { k++; continue }
          if (t == "--staged" || short(t, "S")) st = 1
          if (t == "--worktree" || short(t, "W")) wt = 1
        }
        if (!st || wt) emit("SNAP", d, VERB)   # --staged alone rewrites only the index
      } else if (VERB == "reset") {
        # Abbreviations too, as the ask reads them: --h.. for --hard, --me.. for --merge (harbor#1313).
        for (k++; k <= n; k++) if (A[i, k] ~ /^--h(a(rd?)?)?$/ || A[i, k] ~ /^--me(r(ge?)?)?$/) { emit("SNAP", d, VERB); break }
      } else if (VERB == "clean") {
        force = 0; dry = 0
        for (k++; k <= n; k++) {
          t = A[i, k]
          if (t == "-e" || t == "--exclude") { k++; continue }
          if (t == "--force" || short(t, "f")) force = 1
          if (t == "--dry-run" || t == "--interactive" || short(t, "n") || short(t, "i")) dry = 1
        }
        if (force && !dry) emit("SNAP", d, VERB)
      } else if (VERB == "push") {
        force = 0
        for (k++; k <= n; k++) {
          t = A[i, k]
          if (t == "--mirror" || t ~ /(^|[+:]|refs\/)snapshots\// || t ~ /^\+?refs\/\*/ || t ~ /^\+?\*/) force = 1
        }
        emit("PUSH", d, force)
      }
    }
    function sid(s,   p) { p = index(s, ":"); V = substr(s, p + 1); return substr(s, 1, p - 1) + 0 }
    /^CWD:/  { c0 = substr($0, 5); next }
    /^SEGW:/ { i = sid(substr($0, 6)); if (V ~ /^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR)=/) GE[i] = 1; next }
    /^SEGC:/ { i = sid(substr($0, 6)); C[i] = V; if (i > M) M = i; next }
    /^SEGA:/ { i = sid(substr($0, 6)); N[i]++; A[i, N[i]] = V; if (i > M) M = i; next }
    /^SEGR:/ { i = sid(substr($0, 6)); if (substr(V, 1, 3) == "<<:") { h = substr(V, 4); sub(/^-/, "", h); H[i] = h }; next }
    END {
      cwd = (substr(c0, 1, 1) == "/") ? norm(c0) : ""
      delim = ""
      for (i = 1; i <= M; i++) {
        if (!(i in C)) continue
        # A heredoc body is data until its delimiter, as in inject-hook shell_targets.
        if (delim != "") { if (C[i] == delim) delim = ""; continue }
        w = base(C[i])
        if (w == "cd" || w == "pushd") {
          t = ""; got = 0
          for (k = 1; k <= N[i]; k++) {
            if (A[i, k] == "" || A[i, k] == "--" || A[i, k] ~ /^-[LPen@]+$/) continue
            t = A[i, k]; got = 1; break
          }
          if (!got) cwd = (w == "cd") ? home : ""
          else if (t == "-" || t ~ /^[-+][0-9]+$/) cwd = ""
          else cwd = resolve(t, cwd)
        } else if (w == "popd") cwd = ""
        else if (w == "git") gitseg(i)
        if (i in H) delim = H[i]
      }
    }' 2>/dev/null
}

_snap_say() { # <text> — the one stderr line a call gets, however many worktrees it touched
  [ -z "${_SNAP_SAID:-}" ] || return 0
  _SNAP_SAID=1
  printf '[check:admission.destroy-snapshot] guard-destroy: %s (harbor#1290)\n' "$1" >&2
}

# _snap_take <dir> <verb> — snapshot the worktree holding <dir>. Silent when <dir> is in no worktree
# (nothing to save), when the tree matches HEAD, or when <common git dir>/harbor-snapshot-off exists.
# Every fork here is paid on each discard of a dirty tree, so values are read with `read`, never sed.
_snap_take() {
  _st_top=""; _st_cd=""; _st_idx=""; _st_tmp=""; _st_ht=""; _st_head=""
  _st_r="$(git -C "$1" rev-parse --show-toplevel --git-common-dir --git-path index --git-path "harbor-snapshot.$$" 'HEAD^{tree}' HEAD 2>/dev/null)" \
    || _st_r="$(git -C "$1" rev-parse --show-toplevel --git-common-dir --git-path index --git-path "harbor-snapshot.$$" 2>/dev/null)" \
    || return 0
  { read -r _st_top; read -r _st_cd; read -r _st_idx; read -r _st_tmp; read -r _st_ht; read -r _st_head; } <<SNAP_EOF
$_st_r
SNAP_EOF
  [ -n "$_st_top" ] && [ -n "$_st_tmp" ] || return 0
  case "$_SNAP_TOPS" in *"
$_st_top
"*) return 0 ;; esac
  _SNAP_TOPS="$_SNAP_TOPS$_st_top
"
  case "$_st_cd" in /*) ;; *) _st_cd="$1/$_st_cd" ;; esac
  case "$_st_idx" in /*) ;; *) _st_idx="$1/$_st_idx" ;; esac
  case "$_st_tmp" in /*) ;; *) _st_tmp="$1/$_st_tmp" ;; esac
  [ ! -e "$_st_cd/harbor-snapshot-off" ] || return 0
  # The copy keeps the stat cache, so add rehashes only what changed. -p keeps the index mtime, which
  # git's racy-entry check compares against: a fresh mtime hid a same-second, same-size edit.
  if [ -f "$_st_idx" ]; then cp -p "$_st_idx" "$_st_tmp.index" 2>/dev/null || { rm -f "$_st_tmp.index"; _snap_say "could not snapshot $_st_top before git $2: its git dir is not writable — the command runs unprotected"; return 0; }; fi
  # No size cap, measured: a cap needs an untracked listing and a stat pass (+45 ms at load 16), more than the whole budget. Large untracked files are rehashed per discard; .gitignore them (docs/explanation/admission-baseline.md).
  _st_tree=""
  GIT_INDEX_FILE="$_st_tmp.index" git -C "$_st_top" add -A >/dev/null 2>&1 \
    && _st_tree="$(GIT_INDEX_FILE="$_st_tmp.index" git -C "$_st_top" write-tree 2>/dev/null)"
  rm -f "$_st_tmp.index" "$_st_tmp.index.lock"
  [ -n "$_st_tree" ] || { _snap_say "could not snapshot $_st_top before git $2: writing its objects failed (unwritable repository?) — the command runs unprotected"; return 0; }
  [ "$_st_tree" != "$_st_ht" ] || return 0   # nothing uncommitted: no snapshot to keep
  case "$_st_tree" in 4b825dc642cb6eb9a060e54bf8d69288fbee4904|6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321) [ -n "$_st_head" ] || return 0 ;; esac
  _st_c="$(GIT_AUTHOR_NAME=harbor-snapshot GIT_AUTHOR_EMAIL=snapshot@harbor.invalid \
           GIT_COMMITTER_NAME=harbor-snapshot GIT_COMMITTER_EMAIL=snapshot@harbor.invalid \
           git -C "$_st_top" commit-tree --no-gpg-sign ${_st_head:+-p "$_st_head"} -m "harbor snapshot before git $2" \
             -m "worktree: $_st_top" -m "command: $CMD" "$_st_tree" 2>/dev/null)" \
    || { _snap_say "could not snapshot $_st_top before git $2: commit-tree failed — the command runs unprotected"; return 0; }
  # One update-ref writes the new ref and drops every snapshot older than 7 days; awk srand() is the clock.
  git -C "$_st_top" for-each-ref --format='%(committerdate:unix) %(refname)' refs/snapshots/ 2>/dev/null \
    | awk -v c="$_st_c" -v p="$$" 'BEGIN { srand(); now = srand(); print "create refs/snapshots/" now "-" p " " c }
        $1 + 0 < now - 604800 { print "delete " $2 }' \
    | git -C "$_st_top" update-ref --stdin 2>/dev/null \
    || { _snap_say "could not snapshot $_st_top before git $2: the ref could not be written — the command runs unprotected"; return 0; }
  return 0
}

# _snap_push <dir> <explicit> — 0 iff this push would publish refs/snapshots: the repo holds some, and
# the call names --mirror or a refs/* or refs/snapshots refspec, or a remote is configured to mirror them.
_snap_push() {
  [ -n "$(git -C "$1" for-each-ref --count=1 --format=x refs/snapshots/ 2>/dev/null)" ] || return 1
  [ "$2" = 1 ] && return 0
  git -C "$1" config --get-regexp '^remote\..*\.(mirror|push)$' 2>/dev/null \
    | "$FLOOR_GREP" -Eq -- '\.mirror[[:space:]]+true$|[[:space:]]\+?(refs/\*|refs/snapshots|\*)'
}

_SNAP_TOPS="
"
_snap_run() {
  _sp="$(_snap_plan)" || return 0
  [ -n "$_sp" ] || return 0
  _stab="$(printf '\t')"
  while IFS="$_stab" read -r _sk _sd _sx; do
    case "$_sk" in
      PUSH) if _snap_push "$_sd" "$_sx"; then
              DECISION="deny"; RULE="git-push-snapshots"; _PLAIN=1
              REASON="this push would publish refs/snapshots/* from $_sd — local-only copies of uncommitted work that can hold untracked secrets such as a .env (harbor#1290). Push named branches instead, or drop the snapshots first: git -C $_sd for-each-ref --format='delete %(refname)' refs/snapshots/ | git -C $_sd update-ref --stdin"
            fi ;;
      BLIND) if [ "$_sd" = push ]; then
               DECISION="deny"; RULE="git-push-snapshots"; _PLAIN=1
               REASON="this push names --mirror or a refs/* refspec, and the guard cannot tell which repository it runs in ($_sx), so it cannot rule out publishing refs/snapshots/* — local-only copies of uncommitted work (harbor#1290). Run it with git -C <absolute path>, or push named branches"
             fi ;;
    esac
  done <<SNAP_EOF
$_sp
SNAP_EOF
  [ "$DECISION" != deny ] || return 0
  # The hook's environment is not the command's: a GIT_* the harness carries must not pick the repository.
  # No subshell (a fork per discard): -e is already off here, because the only caller runs this under ||.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
  while IFS="$_stab" read -r _sk _sd _sx; do
    case "$_sk" in
      SNAP) _snap_take "$_sd" "$_sx" ;;
      MAYBE) # a branch, a tag or a remote branch git would DWIM is a switch, never a discard
        git -C "$_sd" rev-parse -q --verify "$_sx^{commit}" >/dev/null 2>&1 && continue
        [ -z "$(git -C "$_sd" for-each-ref --count=1 --format=x "refs/remotes/*/$_sx" 2>/dev/null)" ] || continue
        _snap_take "$_sd" checkout ;;
      BLIND) [ "$_sd" = push ] || _snap_say "nothing was snapshotted before git $_sd: $_sx" ;;
    esac
  done <<SNAP_EOF
$_sp
SNAP_EOF
  return 0
}

_PLAIN=""
if [ "$DECISION" != deny ] && [ -n "${FLOOR_SEGS:-}" ]; then
  case "$FLOOR_SEGS" in *[gG][iI][tT]*)
    case "$FLOOR_SEGS" in *checkout*|*restore*|*reset*|*switch*|*clean*|*push*) _snap_run || : ;; esac ;;
  esac
fi

[ -n "$DECISION" ] || exit 0   # no destructive op — allow

# Unattended hardening: an ASK auto-approves where no human can answer it, so escalate to deny when the operator set the posture or floor_no_human detects an autonomous caller. Fail-safe toward "human present".
_NHNOTE=""
if [ "$DECISION" = "ask" ]; then
  if [ "${HARBOR_ADMISSION_DESTROY_POSTURE:-ask}" = "deny" ]; then DECISION="deny"
  elif floor_no_human; then DECISION="deny"; _NHNOTE=" [no-human context — an ask would auto-approve here, so escalated to deny]"
  fi
fi

# The tail is per shape: "diskutil list/info are never gated" is false for the degraded block.
if [ "$SHAPE" = "flat" ] || [ -n "$_PLAIN" ]; then  # _PLAIN: the push rule is no work-loss ask
  MSG="$REASON."
else
  MSG="$REASON. Confirm a HUMAN intends this — an unattended agent should not destroy uncommitted or untracked work. Non-destructive forms (git clean -n, git reset --soft, diskutil list/info) are never gated.$_NHNOTE"
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
  "$DECISION" "$(printf '%s' "$MSG" | jq -Rs .)"

# RULE is the per-branch token, so "rules that fired" is answerable; SHAPE is a variable, not the literal argv, so the degraded block's record is distinguishable from the working rules.
{ floor_log_decision destroy "$DECISION" "${RULE:-unclassified}.$SHAPE" 2>/dev/null || :; } 2>/dev/null || :
exit 0
