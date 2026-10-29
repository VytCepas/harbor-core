#!/usr/bin/env sh
# prove.sh — a DETECTOR-RECALL engine. Mutate the artefact a gate guards, and
# measure whether the gate notices. Ticket: R5 / contracts/gates.md.
#
#   sh prove.sh <selector>...        run the targets a name or a path selects
#   sh prove.sh --all                every declared target
#   sh prove.sh --lane fast|deep     every target in that cost class
#   sh prove.sh --list               what is declared, applying nothing
#   sh prove.sh --explain <sel>      the parse plus every mutant that WOULD run
#   sh prove.sh --mutators           the mutator library (the only listing)
#   sh prove.sh --coverage           a census of checkers with and without a target
#   sh prove.sh --self-test          the portable self-proof
#
#   --file <p.target>  --only ID[,ID]  --json  --keep  --require-scanners
#   --live-triggers    opt in to subject-kind trigger-routing: REAL claude
#                      sessions, real money, minutes of wall clock. Excluded
#                      from --all and --lane without it, and COULD-NOT-LOOK
#                      (never a quiet pass) when named without it.
#
# Environment: PROVE_TARGETS  PROVE_WORK  PROVE_BUDGET (per-target seconds)
#              PROVE_RUN_TIMEOUT (per-run seconds; this box has no timeout(1))
#              PROVE_ALLOW_EXTERNAL  HARBOR_SCOPE_ROOT
#
# WHY THIS EXISTS. skills/test-strength/SKILL.md states three checks and had no
# mechanism, so nothing on this box could tell a checked suite from an unchecked
# one. A rule with no mechanism is a wish. This is the mechanism for checks 1
# and 2; check 3 is what the canary below does to the engine itself.
#
# WHY NOT `claude plugin eval`. Measured 2026-08-30 on v2.1.251: the verb is
# built into the binary but early-access gated — `claude plugin eval init`
# prints "plugin eval is currently in early access" and EXITS 0. Anything
# wrapping it in CI gets a green step that ran nothing, which is the exact
# failure this engine exists to detect. Do not wire it up. See the `scanner`
# implementation near the bottom for the same rule applied to every adapter.
#
# VOCABULARY, AND TWO COLLISIONS DELIBERATELY AVOIDED. `bin/admission-mutation-tier.sh`
# already owns the phrase "mutation tier" and means something else entirely
# (which config paths let an agent reach the floor), and "operator" means the
# human everywhere else in Harbor. So this file never says tier, mutation tier,
# mutant score, or operator-as-code-artefact. It says: target, subject, checker,
# seed, mutator, planting, mutant, control, canary, survivor, inert, lane.
#
# READ-ONLY, STRUCTURALLY RATHER THAN BY RESTORE. Every mutant is a COPY built
# under a mktemp workspace; no tracked file is ever opened for writing, so a
# crash cannot leave a mutated file behind and there is nothing to restore. That
# is why `sed -i` appears nowhere here and BSD's mandatory empty argument after
# -i never arises. A hash manifest of the repo is taken before the first stage
# and after the last run; a difference is exit 4, never a quiet pass.
#
# BSD USERLAND NOTES THAT COST TIME WHEN FORGOTTEN.
#   - `grep` on this box is ugrep carrying -I --ignore-files: it silently skips
#     binary and gitignored files. Every grep here is /usr/bin/grep, and file
#     lists are built with find, because a NEGATIVE rested on ugrep may mean it
#     declined to look rather than that nothing was there.
#   - There is no `timeout`. A checker that hangs hangs forever, which is why
#     the `floor` target points at floor-equiv rather than floor-test.
#   - `set -e` is NOT set. This engine runs commands that are SUPPOSED to fail —
#     that is the measurement — and under `set -e` a failing command
#     substitution aborts the script, making every fallback dead code.
#   - Never pipe a checker run into head or tail: a pipeline exits with the
#     status of its LAST command, so the verdict being measured is discarded.
#   - awk is one-true-awk: no mktime, and an apostrophe cannot appear inside a
#     single-quoted awk program. Where one is needed it is built with
#     sprintf("%c", 39).
set -u

ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)}}"
PROVE_TARGETS="${PROVE_TARGETS:-$ROOT/skills/test-strength/targets}"
PROVE_WORK="${PROVE_WORK:-${TMPDIR:-/tmp}}"
while :; do case "$PROVE_WORK" in */) PROVE_WORK="${PROVE_WORK%/}" ;; *) break ;; esac; done
PROVE_BUDGET="${PROVE_BUDGET:-900}"
PROVE_ALLOW_EXTERNAL="${PROVE_ALLOW_EXTERNAL:-0}"
TODAY="$(date +%F)"
# THE FIELD SEPARATOR IS \034, NOT A TAB, AND THE REASON IS AN EMPTY FIELD.
# `read` collapses runs of an IFS WHITESPACE character into one delimiter, so a
# tab-delimited row with an empty middle column silently loses a field and every
# column after it shifts left. Measured: a `mutate` with no argument shifted the
# site count into the argument slot and the loop compared an empty string with
# -eq. \034 is not whitespace, so an empty field stays a field.
SEP="$(printf '\034')"
SELF_INVOCATION="sh skills/test-strength/bin/prove.sh"

KEEP=0
JSON=0
REQUIRE_SCANNERS=0
LIVE_TRIGGERS=0
ONLY=""
BUDGETED=0        # 1 when the selection was --all/--lane, so the budget binds
GRC=0
WORKROOT=""
CHK_PID=""        # the checker run in flight, so a signal can kill its tree

# ---------------------------------------------------------------- diagnostics
# EVERYTHING GOES TO STDOUT EXCEPT EXIT-2 USAGE ERRORS. One stream is
# assertable; a report split across two is not, and a suite that captures only
# one of them reads a partial report as a whole one.
say() { printf '%s\n' "$*"; }
die_usage() { printf 'prove: %s\n' "$*" >&2; exit 2; }

# harbor#743: `kill -9` on the subshell alone left the checker under it running
# forever on PID 1. Stop each generation before listing its children, so nothing
# forks mid-walk, then kill them all. ps absent: only the root dies, as before.
_kill_tree() { # $1 = root pid
  _kt_all=" $1 "; _kt_new="$1"
  while [ -n "$_kt_new" ]; do
    kill -STOP $_kt_new 2>/dev/null
    _kt_new=$(ps -A -o pid= -o ppid= 2>/dev/null | awk -v all="$_kt_all" \
      'index(all, " " $2 " ") && !index(all, " " $1 " ") { printf "%s ", $1 }')
    _kt_all="$_kt_all$_kt_new"
  done
  kill -9 $_kt_all 2>/dev/null
}

_cleanup() {
  # harbor#743: an INT or TERM mid-run must not orphan the checker in flight.
  [ -n "$CHK_PID" ] && { _kill_tree "$CHK_PID"; wait "$CHK_PID" 2>/dev/null; CHK_PID=""; }
  [ "$KEEP" = 1 ] && return 0
  [ -n "$WORKROOT" ] && [ -d "$WORKROOT" ] && rm -rf "$WORKROOT"
  return 0
}
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT
trap '_cleanup; exit 143' TERM HUP

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ------------------------------------------------------------ the tripwire
# READ-ONLY IS ASSERTED, NOT ASSUMED. Built with find rather than a grep sweep
# for the reason at the top of this file: a negative rested on ugrep may mean it
# declined to look. Measured 2026-08-30: 851 files, 0.13s, so it is affordable
# on every run and there is no argument for making it optional.
#
# `-exec <hasher> {} +` BATCHES, and the batching is the difference between a
# tripwire and a hang: the one-fork-per-file shape cost seconds per manifest and
# turned a twenty-case self-test into minutes. Sort AFTER hashing so the order
# is stable without a second pass over the tree.
#
# THE HASHER IS RESOLVED ONCE, BY RUNNING IT, AND ITS ABSENCE IS EXIT 4 RATHER
# THAN A SILENT ZERO. Measured 2026-08-30 with a `shasum` shimmed to exit 127:
# the manifest was 0 bytes before AND after, and two empty files compare EQUAL,
# so the only control on the read-only claim became a zero that means "looked at
# nothing" — indistinguishable from "clean", which is the exact shape this
# engine exists to detect. `shasum` is perl-shipped and absent from slim
# containers; `cksum` is POSIX-mandated, so the fallback is real coverage rather
# than a gesture, and only the absence of BOTH is a refusal to run.
#
# EXISTENCE IS NOT IDENTITY, so the probe RUNS the candidate instead of asking
# `command -v` whether a name resolves: the measured failure above was a name
# that resolved and then exited 127.
#
# WHY EMPTINESS ITSELF IS NOT THE TEST: a legitimate HARBOR_SCOPE_ROOT may hold none
# of the six directories below — the self-test's own fixture root does, and its
# manifest is empty by construction — so an empty manifest cannot be treated as
# a fault without refusing every self-test child run.
HASHER=""
_resolve_hasher() {
  [ -n "$HASHER" ] && return 0
  if printf 'x' | shasum >/dev/null 2>&1; then HASHER=shasum; return 0; fi
  if printf 'x' | cksum  >/dev/null 2>&1; then HASHER=cksum;  return 0; fi
  return 1
}
_manifest() {
  ( cd "$ROOT" 2>/dev/null || return 0
    find bin CONTRACTS fixtures hooks skills vendor -type f 2>/dev/null \
      -exec "$HASHER" {} + | LC_ALL=C sort )
}

# ---------------------------------------------------------------- expansion
# `stage` and `place` values are NOT eval'd — a fixed verb vocabulary is the
# whole point of them — so the handful of variables they may name are expanded
# here by substitution instead. $WORK is a mktemp path and contains no `|`, so
# it is safe as a sed replacement.
_expand() {
  printf '%s' "$1" | sed \
    -e "s|\${WORK}|$WORK|g" -e "s|\$WORK|$WORK|g" \
    -e "s|\${TDIR}|$TDIR|g" -e "s|\$TDIR|$TDIR|g" \
    -e "s|\${ROOT}|$ROOT|g" -e "s|\$ROOT|$ROOT|g"
}

# ONE PATH RULE, STATED ONCE. `repo:` is the repo root; absolute is itself;
# everything else is relative to the directory holding the .target file, so a
# target and its fixtures move together.
_resolve() {
  case "$1" in
    repo:*) printf '%s' "$ROOT/${1#repo:}" ;;
    /*)     printf '%s' "$1" ;;
    *)      printf '%s' "$TDIR/$1" ;;
  esac
}

_trim() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
_word() { printf '%s' "$1" | awk -v n="$2" '{print $n}'; }
_after() { # everything after the first n whitespace-delimited words
  printf '%s' "$1" | awk -v n="$2" '{ for (i=1;i<=n;i++) sub(/^[[:space:]]*[^[:space:]]+/, ""); sub(/^[[:space:]]+/, ""); print }'
}
_jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

# ================================================================= MUTATORS
# THE LIBRARY IS THIS TABLE AND NOTHING ELSE READS A SECOND COPY. Lint C6
# resolves every declared mutator name against `--mutators` output rather than
# restating the list, so the linter cannot drift from the engine.
#
# NEVER A MUTATION SITE: a blank line, a comment line, and a line inside a
# fenced code block. Comment-only mutants are the largest source of
# equivalent-mutant noise and are excluded by construction rather than filtered
# afterwards.
#
# WHAT "COMMENT" MEANS IS PER SUBJECT-KIND, and it has to be. For posix-shell a
# comment is `#`-leading. For markdown-contract a `#`-leading line is a HEADING,
# which is the single most load-bearing structure in the contract and the
# subject of three mutators — excluding it would make section-delete
# unimplementable. So markdown excludes `<!-- -->` comment lines and fenced
# code, which is the same rule pointed at the same idea in the other syntax.
mutators_table() {
  cat <<'MUT'
markdown-contract section-delete
markdown-contract section-hollow
markdown-contract heading-demote
markdown-contract table-header-rename
markdown-contract table-cell-blank
markdown-contract table-row-drop
markdown-contract date-shift +Nd|-Nd
markdown-contract anchor-break
markdown-contract codefence-strip
markdown-contract probe-to-ask
markdown-contract edge-evidence-drop
markdown-contract edge-line-drop
posix-shell comparison-flip
posix-shell threshold-widen
posix-shell threshold-narrow
posix-shell guard-clause-delete
posix-shell exit-neuter
posix-shell negation-drop
posix-shell alternation-drop
posix-shell message-drop
trigger-routing trigger-phrase-drop
trigger-routing use-when-drop
trigger-routing negative-clause-drop
MUT
}

# _shift_one <iso-date> <+Nd|-Nd>  — BSD first, GNU fallback, and a REAL failure
# if neither works. A silently unshifted date would report the mutant as inert,
# which blames the declaration for a missing tool. Hence exit 4 with its own
# reason line instead.
_shift_one() {
  _so=$(date -j -v"$2" -f '%Y-%m-%d' "$1" '+%F' 2>/dev/null)
  [ -n "$_so" ] && { printf '%s' "$_so"; return 0; }
  _sn="${2%d}"
  _so=$(date -d "$1 $_sn days" '+%F' 2>/dev/null)
  [ -n "$_so" ] && { printf '%s' "$_so"; return 0; }
  return 1
}

# Each mutator answers the SAME three-mode contract, so the driver below needs
# no per-mutator knowledge:
#   count <seed> 0 <arg>  -> the number of sites
#   desc  <seed> N <arg>  -> a one-line description of site N
#   apply <seed> N <arg>  -> mutant N on stdout
# Sites are taken in SEED ORDER, so mutant ids are deterministic and no seed
# value or randomisation is needed anywhere in this engine.

m_section() { # mode seed want kind(delete|hollow|demote)
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    /^[ \t]*```/ { fence = 1 - fence; if (mode == "apply" && !drop) print; next }
    {
      if (!fence && $0 ~ /^## /) {
        idx++
        if (mode == "count") next
        if (idx == want) {
          if (mode == "desc") { print kind " " $0; exit }
          if (kind == "hollow") { print; print "TBD."; drop = 1; next }
          if (kind == "demote") { t = $0; sub(/^## /, "", t); print "**" t "**"; drop = 0; next }
          drop = 1; next
        }
        drop = 0
      }
      if (mode == "count" || mode == "desc") next
      if (drop) next
      print
    }
    END { if (mode == "count") print idx + 0 }
  ' "$2"
}

m_table() { # mode seed want kind(header|cell|row)
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    { L[NR] = $0 }
    END {
      f = 0
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[ \t]*```/) { inf[i] = 2; f = 1 - f; continue }
        inf[i] = f
      }
      cnt = 0; hitrow = 0; hitcell = 0
      for (i = 1; i <= NR; i++) {
        if (inf[i]) continue
        if (L[i] !~ /^[ \t]*\|/) continue
        if (L[i] ~ /^[ \t]*\|[ \t:|-]+$/) continue
        ishdr = (i < NR && L[i+1] ~ /^[ \t]*\|[ \t:|-]+$/)
        if (kind == "row") {
          if (ishdr) continue
          cnt++
          if (cnt == want) hitrow = i
          continue
        }
        if (kind == "header" && !ishdr) continue
        if (kind == "cell" && ishdr) continue
        n = split(L[i], c, "|")
        for (j = 2; j < n; j++) {
          # Blanking an already-blank cell, or renaming a header already called
          # zzz, writes the seed back. See the note in m_shell_span: an
          # equivalent-by-construction mutant is not a site.
          if (kind == "cell"   && trim(c[j]) == "")    continue
          if (kind == "header" && trim(c[j]) == "zzz") continue
          cnt++
          if (cnt == want) { hitrow = i; hitcell = j }
        }
      }
      if (mode == "count") { print cnt + 0; exit }
      if (hitrow == 0) exit
      if (mode == "desc") {
        if (kind == "row") { printf "line %d row %s\n", hitrow, substr(trim(L[hitrow]), 1, 52) }
        else { n = split(L[hitrow], c, "|"); printf "line %d cell %d (%s)\n", hitrow, hitcell - 1, trim(c[hitcell]) }
        exit
      }
      for (i = 1; i <= NR; i++) {
        if (i == hitrow) {
          if (kind == "row") continue
          n = split(L[i], c, "|")
          c[hitcell] = (kind == "header") ? " zzz " : "  "
          out = c[1]
          for (j = 2; j <= n; j++) out = out "|" c[j]
          print out
          continue
        }
        print L[i]
      }
    }
  ' "$2"
}

m_date_shift() { # mode seed want arg
  case "$1" in
    count)
      if /usr/bin/grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$2"; then printf '1\n'; else printf '0\n'; fi
      return 0 ;;
    desc) printf 'all ISO dates %s\n' "$4"; return 0 ;;
  esac
  _dsf="$WORK/.date-shift.sed"
  : > "$_dsf"
  for _d in $(/usr/bin/grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$2" | LC_ALL=C sort -u); do
    _nd=$(_shift_one "$_d" "$4") || return 1
    printf 's/%s/%s/g\n' "$_d" "$_nd" >> "$_dsf"
  done
  sed -f "$_dsf" "$2"
}

m_span() { # mode seed want kind(anchor|fence)
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    BEGIN { re = (kind == "anchor") ? "\\][(][^)]*[)]" : "`[^`]*`" }
    {
      line = $0
      if (line ~ /^[ \t]*```/) { fence = 1 - fence; if (mode == "apply") print line; next }
      if (fence || line ~ /^[ \t]*<!--/) { if (mode == "apply") print line; next }
      if (kind == "fence" && line !~ /^[ \t]*\|/) { if (mode == "apply") print line; next }
      out = ""; rest = line
      while (match(rest, re)) {
        # A ZERO-LENGTH MATCH NEVER ADVANCES `rest`, WHICH IS AN INFINITE LOOP.
        # It happens when `re` is empty, and `re` is empty when this awk program
        # itself has been mutated — which is exactly what prove-engine does.
        # Measured 2026-08-30: message-drop deleted the line that assigns `re`
        # for its own kind and the mutant spun forever with no output. An engine
        # that can be made to hang by its own subject cannot be its own harness.
        if (RLENGTH <= 0) break
        cnt++
        pre = substr(rest, 1, RSTART - 1)
        tok = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        if (cnt == want) {
          if (mode == "desc") { printf "line %d %s\n", FNR, tok; exit }
          tok = (kind == "anchor") ? "](NO/SUCH/PATH)" : substr(tok, 2, length(tok) - 2)
        }
        out = out pre tok
      }
      if (mode == "apply") print out rest
    }
    END { if (mode == "count") print cnt + 0 }
  ' "$2"
}

m_shell_span() { # mode seed want kind
  # ONE SCANNER, SEVEN MUTATORS. Every posix-shell mutator is "find the Nth
  # occurrence of a pattern on an eligible line and rewrite it", so they share a
  # scanner and differ only in the pattern and the rewrite. A per-mutator copy
  # of the comment/blank exclusion is seven chances to get the exclusion wrong
  # in one place and not the others.
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    function flip(o) {
      if (o == "-gt") return "-ge"; if (o == "-ge") return "-gt"
      if (o == "-lt") return "-le"; if (o == "-le") return "-lt"
      if (o == "-eq") return "-ne"; if (o == "-ne") return "-eq"
      return o
    }
    BEGIN {
      sq = sprintf("%c", 39)
      if (kind == "cmp")    re = "-(gt|ge|lt|le|eq|ne)([ \t]|$)"
      if (kind == "wide" || kind == "narrow") re = "[^A-Za-z0-9_.$][0-9]+[^A-Za-z0-9_.]"
      if (kind == "guard")  re = "[|][|][ \t]*[{][^}]*(exit|return)[ \t]+[0-9]+[^}]*[}]"
      if (kind == "exit")   re = "exit[ \t]+[1-9][0-9]*"
      if (kind == "neg")    re = "[ \t;&|(][!][ \t]"
      if (kind == "alt")    re = sq "[^" sq "]*" sq
      if (kind == "msg")    re = "printf[^\n]*>&2"
    }
    {
      line = $0
      if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/) { if (mode == "apply") print line; next }
      # Thresholds only inside a bracket test. Everywhere else an integer is a
      # port number, a field index or a retry count, and widening it produces
      # noise a reviewer learns to skim past.
      if ((kind == "wide" || kind == "narrow") && (line !~ /\[[ \t]/ || line !~ /[ \t]\]/)) {
        if (mode == "apply") print line; next
      }
      if (kind == "msg") {
        # THE LINE MUST *BE* A MESSAGE, NOT MERELY CONTAIN ONE. Measured
        # 2026-08-30 against this file: `line ~ /printf/ && line ~ />&2/` also
        # matched `die_usage() { printf ... >&2; exit 2; }` — a one-line FUNCTION
        # DEFINITION — and deleting it left the flag loop calling a command that
        # does not exist, never shifting, and spinning forever. It also matched
        # an awk assignment whose string literal happens to contain both tokens.
        # Neither is a wording dependency, which is the only thing this mutator
        # claims to test. Anchoring on `printf` as the first token is what makes
        # the class mean what its name says.
        _t = line
        sub(/^[ \t]+/, "", _t)
        if (_t ~ /^printf/ && line ~ />&2/) {
          cnt++
          if (cnt == want) {
            if (mode == "desc") { printf "line %d %s\n", FNR, substr(line, 1, 52); exit }
            next
          }
        }
        if (mode == "apply") print line
        next
      }
      out = ""; rest = line
      while (match(rest, re)) {
        # A ZERO-LENGTH MATCH NEVER ADVANCES `rest`, WHICH IS AN INFINITE LOOP.
        # It happens when `re` is empty, and `re` is empty when this awk program
        # itself has been mutated — which is exactly what prove-engine does.
        # Measured 2026-08-30: message-drop deleted the line that assigns `re`
        # for its own kind and the mutant spun forever with no output. An engine
        # that can be made to hang by its own subject cannot be its own harness.
        if (RLENGTH <= 0) break
        pre = substr(rest, 1, RSTART - 1)
        tok = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        # A MUTATION THAT CHANGES NOTHING IS NOT A SITE. `threshold-narrow` over
        # a literal that is already 0 writes a byte-identical mutant, which the
        # engine correctly reports as inert and correctly refuses to score — so
        # one `${VAR:-0}` default in the subject aborted the whole floor sweep
        # at exit 4. Equivalent by construction is not a finding; skip it here
        # rather than manufacture a vacuous run downstream.
        if ((kind == "wide" || kind == "narrow")) {
          _d = substr(tok, 2, length(tok) - 2)
          if ((kind == "wide" && _d == "999999") || (kind == "narrow" && _d == "0")) {
            out = out pre tok
            continue
          }
        }
        cnt++
        if (cnt == want) {
          if (mode == "desc") { printf "line %d %s\n", FNR, tok; exit }
          if (kind == "cmp")    tok = flip(substr(tok, 1, 3)) substr(tok, 4)
          else if (kind == "wide" || kind == "narrow") {
            lead = substr(tok, 1, 1); tail = substr(tok, length(tok), 1)
            tok = lead ((kind == "wide") ? "999999" : "0") tail
          }
          else if (kind == "guard") tok = "|| :"
          else if (kind == "exit")  tok = "exit 0"
          else if (kind == "neg")   tok = substr(tok, 1, 1) substr(tok, 3)
          else if (kind == "alt") {
            inner = substr(tok, 2, length(tok) - 2)
            tmp = inner; np = gsub(/[|]/, "|", tmp)
            if (np >= 2) { sub(/[|][^|]*$/, "", inner); tok = sq inner sq }
            else cnt--
          }
        } else if (kind == "alt") {
          tmp = tok; np = gsub(/[|]/, "|", tmp)
          if (np < 2) cnt--
        }
        out = out pre tok
      }
      if (mode == "apply") print out rest
    }
    END { if (mode == "count") print cnt + 0 }
  ' "$2"
}

# _mut <mode> <name> <seed> <want> <arg>
# ── trigger-routing ─────────────────────────────────────────────────────────
# THE SUBJECT IS A SKILL CARD AND THE SITES ARE ITS TRIGGER CLAUSES. Everything
# here reads the frontmatter `description:` line out of the seed; nothing is
# restated in the declaration, so the denominator grows when somebody adds a
# trigger phrase and no edit is needed anywhere.
#
# WHY `negative-clause-drop` IS ITS OWN CLASS RATHER THAN A PHRASE. The NOT FOR
# clause is the only part of a description that can make a router fire LESS, and
# a sweep that only drops positive triggers can never see it: dropping a trigger
# makes the skill fire less, which the positive queries catch, while dropping
# the NOT FOR makes it fire MORE, which only the declared negative queries
# catch. One class per direction, for the reason the shell library carries both
# threshold-widen and threshold-narrow.
#
# NO APOSTROPHE APPEARS IN ANY awk PROGRAM BELOW: one inside a single-quoted
# program closes the shell string. And no continuation line begins with an
# operator — one-true-awk ends a statement at a newline unless the line ENDS in
# one, and the other way round is a syntax error that a 2>/dev/null turns
# silent.
m_trigger() { # mode seed want kind(phrase|usewhen|notfor)
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    function tailq(s) { return (substr(s, length(s)) == "\"") ? "\"" : "" }
    NR == 1 && $0 != "---" { bad = 1; exit }
    NR == 1 { fm = 1; if (mode == "apply") print; next }
    fm && /^---[[:space:]]*$/ { fm = 0; if (mode == "apply") print; next }
    {
      if (!fm || index($0, "description:") != 1 || done) { if (mode == "apply") print; next }
      done = 1
      p = index($0, "USE WHEN")
      q = index($0, "NOT FOR")
      if (kind == "usewhen") {
        if (p == 0) { if (mode == "apply") print; next }
        n = 1
        if (mode == "count") { print 1; exit }
        if (mode == "desc")  { print "the whole USE WHEN clause removed"; exit }
        if (q > p) { print substr($0, 1, p - 1) substr($0, q) }
        else       { print substr($0, 1, p - 1) tailq($0) }
        next
      }
      if (kind == "notfor") {
        if (q == 0) { if (mode == "apply") print; next }
        if (mode == "count") { print 1; exit }
        if (mode == "desc")  { print "the NOT FOR clause removed — the router may now fire on the negative queries"; exit }
        print substr($0, 1, q - 1) tailq($0)
        next
      }
      # kind == phrase
      if (p == 0) { if (mode == "apply") print; next }
      head = substr($0, 1, p + 8)
      if (q > p) { run = substr($0, p + 9, q - p - 9); tail = substr($0, q) }
      else       { run = substr($0, p + 9); tail = tailq($0)
                   if (tail != "") run = substr(run, 1, length(run) - 1) }
      k = split(run, ph, /,[ ]*/)
      if (mode == "count") { print k; exit }
      if (mode == "desc")  { print "trigger phrase dropped: " ph[want]; exit }
      out = ""
      for (i = 1; i <= k; i++) {
        if (i == want) continue
        out = (out == "") ? ph[i] : out ", " ph[i]
      }
      print head out tail
      next
    }
    END { if (bad && mode == "count") print 0 }
  ' "$2"
}

# m_probe — downgrade one runnable probe to an ASK.
#
# THE ONLY MUTATOR THAT TESTS A RULE ABOUT WHAT IS *NOT* WRITTEN. Every other
# markdown mutator removes or corrupts something a reader can see is gone: a
# heading, a row, a cell. This one leaves a perfectly well-formed row behind —
# right cell count, legal enums, a probe cell in a legal form — and changes only
# whether the row records a measurement or a belief. It is what a map degrades
# INTO on an ordinary Tuesday: nobody deletes a probe, somebody just does not
# run it and writes down who to ask instead.
#
# Only the no-inference rule can kill it, which is the point: this mutator is
# that rule's falsifier, and a target that declares it and reports 0/N is
# reporting that the rule is not armed for that subject.
# m_edge — the enumeration that every case owes, attacked two ways.
#
# `evidence` strips what a verdict rests on and leaves the verdict standing. It
# is the same shape as probe-to-ask: nothing a reader can see is missing, a
# perfectly well-formed bullet, and the only thing changed is whether the line
# records something somebody looked at or something somebody believed. This is
# the Pandora failure as a mutation — `absent` written because checking felt
# like more work than concluding.
#
# `drop` deletes a whole verdict. Only the declared edge library can catch it,
# so this class measures whether that list is genuinely read rather than
# restated somewhere the checker forgot to update.
m_edge() { # mode seed want kind(evidence|drop)
  awk -v mode="$1" -v want="$3" -v kind="$4" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    { L[NR] = $0 }
    END {
      f = 0; ined = 0
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[ \t]*```/) { f = 1 - f; inf[i] = 1; continue }
        inf[i] = f
      }
      cnt = 0; hit = 0
      for (i = 1; i <= NR; i++) {
        if (inf[i]) continue
        if (L[i] ~ /^#{1,4}[ \t]/) { ined = (tolower(L[i]) ~ /(^|[^a-z])edges([^a-z]|$)/) ? 1 : 0; continue }
        if (!ined) continue
        if (L[i] !~ /^[ \t]*[-*]/) continue
        cp = index(L[i], ":")
        if (cp < 2) continue
        low = tolower(L[i])
        vd = ""
        if (low ~ /(^|[^a-z])present([^a-z]|$)/) vd = "present"
        else if (low ~ /(^|[^a-z])absent([^a-z]|$)/) vd = "absent"
        else if (low ~ /(^|[^a-z])yes([^a-z]|$)/) vd = "yes"
        else if (low ~ /(^|[^a-z])no([^a-z]|$)/) vd = "no"
        else if (low ~ /(^|[^a-z])unknown([^a-z]|$)/) vd = "unknown"
        if (vd == "") continue
        if (kind == "evidence") {
          # An unknown owes nothing, so stripping it writes the seed back, and
          # an equivalent-by-construction mutant is not a site.
          if (vd == "unknown") continue
          if (!(L[i] ~ /`[^`]+`/ || low ~ /(^|[^a-z])saw:[ \t]*[^ \t]/)) continue
        }
        cnt++
        if (cnt == want) { hit = i; hvd = vd }
      }
      if (mode == "count") { print cnt + 0; exit }
      if (hit == 0) exit
      if (mode == "desc") {
        printf "line %d %s (%s)\n", hit, (kind == "drop" ? "verdict dropped" : "evidence stripped"), \
               substr(trim(L[hit]), 1, 40)
        exit
      }
      for (i = 1; i <= NR; i++) {
        if (i != hit) { print L[i]; continue }
        if (kind == "drop") continue
        cp = index(L[i], ":")
        printf "%s: %s\n", substr(L[i], 1, cp - 1), hvd
      }
    }
  ' "$2"
}

m_probe() { # mode seed want
  awk -v mode="$1" -v want="$3" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    # AN ESCAPED PIPE IS CONTENT, NOT A SEPARATOR, and hop names really carry
    # them: a live catalogue is named `ORG \| PANDORA SHOPIFY \| LT`. Splitting
    # on those read a 6-column row as 8 columns, so the row was not a hop row,
    # so it was not a site — and the target reported 3 sites where the seed had
    # 4, scoring the gate on a surface a real map would not have. Measured here
    # by planting an escaped pipe in this target own seed and watching a site
    # disappear. The rest of prove split naively, which is safe for the
    # mutators that only blank a fragment; it is NOT safe for one that must
    # identify a specific column.
    function cells(l, arr,   t, k, i) {
      t = l; gsub(/\\\|/, "\001", t)
      k = split(t, arr, "|")
      for (i = 1; i <= k; i++) gsub(/\001/, "\\|", arr[i])
      return k
    }
    function ishdr(l,   n, c) {
      n = cells(l, c)
      if (n != 7 && n != 8) return 0
      return (tolower(trim(c[2])) == "hop"   && tolower(trim(c[3])) == "owner" &&
              tolower(trim(c[4])) == "reach" && tolower(trim(c[5])) == "probe" &&
              tolower(trim(c[6])) == "verified")
    }
    { L[NR] = $0 }
    END {
      f = 0
      for (i = 1; i <= NR; i++) {
        if (L[i] ~ /^[ \t]*```/) { inf[i] = 2; f = 1 - f; continue }
        inf[i] = f
      }
      cnt = 0; hit = 0; inhop = 0
      for (i = 1; i <= NR; i++) {
        if (inf[i]) { inhop = 0; continue }
        if (L[i] ~ /^[ \t]*$/) { inhop = 0; continue }
        if (L[i] ~ /^[ \t]*\|[ \t:|-]+\|[ \t]*$/) { inhop = (i > 1 && ishdr(L[i-1])); continue }
        if (!inhop) continue
        if (L[i] !~ /^[ \t]*\|/) { inhop = 0; continue }
        n = cells(L[i], c)
        if (n != 7 && n != 8) continue
        # An ASK is already the degraded form. Rewriting it writes the seed back,
        # and an equivalent-by-construction mutant is not a site.
        if (trim(c[5]) ~ /^ASK:/) continue
        cnt++
        if (cnt == want) hit = i
      }
      if (mode == "count") { print cnt + 0; exit }
      if (hit == 0) exit
      if (mode == "desc") {
        n = cells(L[hit], c)
        printf "line %d probe %s -> ASK\n", hit, substr(trim(c[5]), 1, 34)
        exit
      }
      for (i = 1; i <= NR; i++) {
        if (i != hit) { print L[i]; continue }
        n = cells(L[i], c)
        c[5] = " ASK: the owner, can we reach this "
        out = c[1]
        for (j = 2; j <= n; j++) out = out "|" c[j]
        print out
      }
    }
  ' "$2"
}

_mut() {
  case "$2" in
    section-delete)       m_section "$1" "$3" "$4" delete ;;
    section-hollow)       m_section "$1" "$3" "$4" hollow ;;
    heading-demote)       m_section "$1" "$3" "$4" demote ;;
    table-header-rename)  m_table   "$1" "$3" "$4" header ;;
    table-cell-blank)     m_table   "$1" "$3" "$4" cell ;;
    table-row-drop)       m_table   "$1" "$3" "$4" row ;;
    date-shift)           m_date_shift "$1" "$3" "$4" "$5" ;;
    anchor-break)         m_span "$1" "$3" "$4" anchor ;;
    codefence-strip)      m_span "$1" "$3" "$4" fence ;;
    probe-to-ask)         m_probe "$1" "$3" "$4" ;;
    edge-evidence-drop)   m_edge  "$1" "$3" "$4" evidence ;;
    edge-line-drop)       m_edge  "$1" "$3" "$4" drop ;;
    comparison-flip)      m_shell_span "$1" "$3" "$4" cmp ;;
    threshold-widen)      m_shell_span "$1" "$3" "$4" wide ;;
    threshold-narrow)     m_shell_span "$1" "$3" "$4" narrow ;;
    guard-clause-delete)  m_shell_span "$1" "$3" "$4" guard ;;
    exit-neuter)          m_shell_span "$1" "$3" "$4" exit ;;
    negation-drop)        m_shell_span "$1" "$3" "$4" neg ;;
    alternation-drop)     m_shell_span "$1" "$3" "$4" alt ;;
    message-drop)         m_shell_span "$1" "$3" "$4" msg ;;
    trigger-phrase-drop)  m_trigger "$1" "$3" "$4" phrase ;;
    use-when-drop)        m_trigger "$1" "$3" "$4" usewhen ;;
    negative-clause-drop) m_trigger "$1" "$3" "$4" notfor ;;
    *) return 1 ;;
  esac
}

# The no-site reason a class prints. Written per class rather than derived,
# because "0" alone is the same ambiguity the SKILL's check 3 is about: it means
# either "the seed has none of these" or "the scanner is broken", and a reader
# cannot tell the two apart from a zero.
_nosite_reason() {
  case "$1" in
    section-delete|section-hollow|heading-demote) printf 'the seed carries no ## heading' ;;
    table-header-rename) printf 'the seed carries no table header row' ;;
    table-cell-blank)    printf 'the seed carries no table body cell' ;;
    table-row-drop)      printf 'the seed carries no table body row' ;;
    date-shift)          printf 'the seed carries no ISO date' ;;
    anchor-break)        printf 'the seed carries no markdown link' ;;
    codefence-strip)     printf 'the seed carries no backticked span in a table cell' ;;
    edge-evidence-drop)  printf 'the seed has no edge verdict carrying evidence — every claim in it already rests on nothing, or every verdict is unknown' ;;
    edge-line-drop)      printf 'the seed carries no ## Edges bullet with a verdict' ;;
    probe-to-ask)        printf 'the seed has no hop row whose probe is a command — every probe is already an ASK, so there is nothing to downgrade' ;;
    comparison-flip)     printf 'the seed carries no numeric comparison operator' ;;
    threshold-widen|threshold-narrow) printf 'the seed carries no integer literal inside a bracket test' ;;
    guard-clause-delete) printf 'the seed carries no single-line || { ... exit N; } guard' ;;
    exit-neuter)         printf 'the seed carries no non-zero exit' ;;
    negation-drop)       printf 'the seed carries no negated test or command' ;;
    alternation-drop)    printf 'the seed carries no quoted string with two or more alternation branches' ;;
    message-drop)        printf 'the seed carries no printf to stderr' ;;
    trigger-phrase-drop) printf 'the card has no USE WHEN clause in its frontmatter description' ;;
    use-when-drop)       printf 'the card has no USE WHEN clause in its frontmatter description' ;;
    negative-clause-drop) printf 'the card has no NOT FOR clause — nothing declares what it must NOT match' ;;
    *)                   printf 'no site' ;;
  esac
}

# ================================================================== PARSING
# An unknown directive, an unknown continuation key or an unknown mutator name
# REFUSES THE WHOLE FILE. Skipping the line is the tempting alternative and it
# is how a declaration silently loses the control it thought it had — the file
# still parses, the run still prints a number, and nobody can see the missing
# half. Refusal is the only outcome a reader cannot mistake for a pass.
PARSE_ERR=""
_perr() { [ -z "$PARSE_ERR" ] && PARSE_ERR="$1"; return 0; }

parse_target() { # $1 = .target path ; requires WORK to exist
  TFILE="$1"
  TDIR="$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)"
  PARSE_ERR=""
  T_NAME=""; T_KIND=""; T_LANE=""; T_COST=""; T_SITES=""; T_SEED=""
  T_PLACE=""; T_CMD=""; T_GREEN=""; T_RED=""; T_ENV=""; T_ABLATE=""; T_RTO=""
  P="$WORK/parse"; mkdir -p "$P"
  : > "$P/stages"; : > "$P/mutators"; : > "$P/plants"; : > "$P/manuals"
  : > "$P/controls"; : > "$P/scanners"; : > "$P/ids"; : > "$P/idsx"

  _last=""; _lastid=""; _lastn=0
  while IFS= read -r _ln || [ -n "$_ln" ]; do
    _t=$(_trim "$_ln")
    [ -z "$_t" ] && continue
    case "$_t" in '#'*) continue ;; esac
    # A CONTINUATION IS A LINE THAT STARTS WITH WHITESPACE. Written as two
    # literal patterns rather than a bracket expression, because an escaped
    # space inside `[...]` is a syntax error in some shells this must run under.
    case "$_ln" in
      ' '*)  _indent=1 ;;
      '	'*) _indent=1 ;;
      *)     _indent=0 ;;
    esac

    if [ "$_indent" = 1 ]; then
      case "$_t" in
        *:*) ;;
        *) _perr "continuation is not key: value -> $_t"; continue ;;
      esac
      _k=$(_trim "${_t%%:*}")
      _v=$(_trim "${_t#*:}")
      case "$_k" in
        sites)
          [ "$_last" = mutate ] || { _perr "sites: only follows a mutate line"; continue; }
          awk -v n="$_lastn" -v s="$_v" 'BEGIN{}' </dev/null
          _tmpf="$P/mutators.tmp"
          awk -v n="$_lastn" -v s="$_v" -F"$SEP" 'BEGIN{OFS="\034"} { if (NR == n) $4 = s; print }' "$P/mutators" > "$_tmpf"
          mv "$_tmpf" "$P/mutators" ;;
        why)
          [ -n "$_v" ] || { _perr "empty why: on $_lastid"; continue; }
          case "$_last" in
            plant)   _sed_col "$P/plants"   "$_lastn" 3 "$_v" ;;
            control) _sed_col "$P/controls" "$_lastn" 5 "$_v" ;;
            *) _perr "why: only follows a plant or a control" ;;
          esac ;;
        varies)
          [ "$_last" = control ] || { _perr "varies: only follows a control"; continue; }
          [ -n "$_v" ] || { _perr "empty varies: on $_lastid"; continue; }
          _sed_col "$P/controls" "$_lastn" 4 "$_v" ;;
        *) _perr "unknown continuation key: $_k" ;;
      esac
      continue
    fi

    _d=$(_word "$_t" 1)
    _rest=$(_after "$_t" 1)
    case "$_d" in
      target)       [ -z "$T_NAME" ]  || _perr "target declared twice"; T_NAME="$_rest" ;;
      subject-kind) [ -z "$T_KIND" ]  || _perr "subject-kind declared twice"; T_KIND="$_rest" ;;
      lane)         [ -z "$T_LANE" ]  || _perr "lane declared twice"; T_LANE="$_rest" ;;
      cost)         [ -z "$T_COST" ]  || _perr "cost declared twice"; T_COST="$_rest" ;;
      sites)        [ -z "$T_SITES" ] || _perr "sites declared twice"; T_SITES="$_rest" ;;
      seed)         [ -z "$T_SEED" ]  || _perr "seed declared twice"; T_SEED="$_rest" ;;
      place)        [ -z "$T_PLACE" ] || _perr "place declared twice"; T_PLACE="$_rest" ;;
      checker-cmd)  [ -z "$T_CMD" ]   || _perr "checker-cmd declared twice"; T_CMD="$_rest" ;;
      green)        [ -z "$T_GREEN" ] || _perr "green declared twice"; T_GREEN="$_rest" ;;
      red)          [ -z "$T_RED" ]   || _perr "red declared twice"; T_RED="$_rest" ;;
      checker-env)  T_ENV="$T_ENV $_rest" ;;
      ablate)       [ -z "$T_ABLATE" ] || _perr "ablate declared twice"; T_ABLATE="$_rest" ;;
      run-timeout)  [ -z "$T_RTO" ]    || _perr "run-timeout declared twice"; T_RTO="$_rest" ;;
      stage)
        _sv=$(_word "$_rest" 1)
        case "$_sv" in
          mkdir|copy|copy-tree) ;;
          *) _perr "unknown stage verb: $_sv (mkdir, copy, copy-tree)" ;;
        esac
        printf '%s\n' "$_rest" >> "$P/stages"
        _last=stage ;;
      mutate)
        _mp=$(_word "$_rest" 1); _mn=$(_word "$_rest" 2); _ma=$(_word "$_rest" 3)
        [ -n "$_mp" ] && [ -n "$_mn" ] || _perr "mutate needs a PREFIX and a mutator name"
        mutators_table | awk -v k="$T_KIND" -v n="$_mn" '$1 == k && $2 == n { f = 1 } END { exit !f }' \
          || _perr "unknown mutator for subject-kind $T_KIND: $_mn"
        printf '%s\034%s\034%s\034%s\n' "$_mp" "$_mn" "$_ma" "" >> "$P/mutators"
        printf '%s\n' "$_mp" >> "$P/ids"
        _last=mutate; _lastid="$_mp"; _lastn=$(_lines "$P/mutators") ;;
      plant)
        _pi=$(_word "$_rest" 1); _pr=$(_after "$_rest" 1)
        [ -n "$_pi" ] && [ -n "$_pr" ] || _perr "plant needs an ID and a recipe"
        printf '%s\034%s\034\n' "$_pi" "$_pr" >> "$P/plants"
        printf '%s\n' "$_pi" >> "$P/ids"; printf '%s\n' "$_pi" >> "$P/idsx"
        _last=plant; _lastid="$_pi"; _lastn=$(_lines "$P/plants") ;;
      manual)
        _mi=$(_word "$_rest" 1); _md=$(_after "$_rest" 1)
        [ -n "$_mi" ] && [ -n "$_md" ] || _perr "manual needs an ID and a description"
        printf '%s\034%s\n' "$_mi" "$_md" >> "$P/manuals"
        printf '%s\n' "$_mi" >> "$P/ids"; printf '%s\n' "$_mi" >> "$P/idsx"
        _last=manual; _lastid="$_mi" ;;
      control)
        _ci=$(_word "$_rest" 1); _ct=$(_word "$_rest" 2); _cv=$(_after "$_rest" 2)
        case "$_ct" in file|cmd) ;; *) _perr "control type must be file or cmd, got: $_ct" ;; esac
        [ -n "$_ci" ] && [ -n "$_cv" ] || _perr "control needs an ID, a type and a value"
        printf '%s\034%s\034%s\034\034\n' "$_ci" "$_ct" "$_cv" >> "$P/controls"
        printf '%s\n' "$_ci" >> "$P/ids"; printf '%s\n' "$_ci" >> "$P/idsx"
        _last=control; _lastid="$_ci"; _lastn=$(_lines "$P/controls") ;;
      scanner)
        _sn=$(_word "$_rest" 1); _sa=$(_after "$_rest" 1)
        [ -n "$_sn" ] || _perr "scanner needs a name"
        printf '%s\034%s\n' "$_sn" "$_sa" >> "$P/scanners"
        _last=scanner; _lastid="$_sn" ;;
      *) _perr "unknown directive: $_d" ;;
    esac
  done < "$TFILE"

  [ -n "$T_NAME" ]  || _perr "missing directive: target"
  [ -n "$T_KIND" ]  || _perr "missing directive: subject-kind"
  [ -n "$T_LANE" ]  || _perr "missing directive: lane"
  [ -n "$T_COST" ]  || _perr "missing directive: cost"
  [ -n "$T_SEED" ]  || _perr "missing directive: seed"
  [ -n "$T_PLACE" ] || _perr "missing directive: place"
  [ -n "$T_CMD" ]   || _perr "missing directive: checker-cmd"
  [ -n "$T_GREEN" ] || _perr "missing directive: green"
  [ -n "$T_RED" ]   || _perr "missing directive: red"
  [ -z "$T_SITES" ] && T_SITES=8

  _base=$(basename "$TFILE" .target)
  [ "$T_NAME" = "$_base" ] || _perr "target name '$T_NAME' does not equal the file basename '$_base'"
  case "$T_KIND" in posix-shell|markdown-contract|trigger-routing) ;; *) _perr "unknown subject-kind: $T_KIND" ;; esac
  [ -n "$T_RTO" ] && case "$T_RTO" in ''|*[!0-9]*) _perr "run-timeout must be an integer: $T_RTO" ;; esac
  # THE ABLATION ARM IS THE ONLY THING THAT MAKES A TRIGGER RUN NON-ENDOGENOUS,
  # so it is REQUIRED for that kind and REFUSED for every other. Without it the
  # check reads the system's own output: a detector that reports "fired" for
  # any reason at all scores a flawless positive rate, and nothing in the run
  # can tell that from a router that works. Declaring it elsewhere would be a
  # second arm nothing interprets, which is worse than absent.
  if [ "$T_KIND" = trigger-routing ]; then
    [ -n "$T_ABLATE" ] || _perr "subject-kind trigger-routing requires an ablate directive — without a skill-absent arm the measurement reads its own output"
    [ "$T_LANE" = deep ] || _perr "subject-kind trigger-routing must declare lane deep — a live sweep spends real money and wall-clock and can never be in the default lane"
  else
    [ -z "$T_ABLATE" ] || _perr "ablate is only meaningful for subject-kind trigger-routing; nothing interprets it for $T_KIND"
  fi
  case "$T_LANE" in fast|deep) ;; *) _perr "unknown lane: $T_LANE" ;; esac
  case "$T_COST" in ''|*[!0-9]*) _perr "cost must be an integer: $T_COST" ;; esac
  case "$T_SITES" in ''|*[!0-9]*) _perr "sites must be an integer: $T_SITES" ;; esac
  [ "${T_SITES:-8}" -gt 64 ] 2>/dev/null && _perr "sites ceiling is 64, got $T_SITES"
  case "$T_GREEN" in ''|*[!0-9]*) _perr "green must be an integer exit code" ;; esac
  case "$T_RED" in ''|*[!0-9]*) _perr "red must be an integer exit code" ;; esac
  # THE TYPO THAT PRODUCES A PERFECT SCORE. Every verdict this engine reaches is
  # a comparison against T_RED — baseline, canary, each control, each mutant. If
  # green and red are the same integer, a checker that cannot refuse ANYTHING
  # satisfies all of them at once: measured 2026-08-31 with `green 0 / red 0` and
  # a checker that is only `exit 0`, the report read CANARY KILLED, CONTROLS 1/1
  # green, GENERATED 5/5 killed, VERDICT PROVEN exit 0. Not one guard fired,
  # because each guard was asking a question whose two answers had been made
  # equal. Refused here rather than caught downstream: there is no downstream —
  # this is the one check no later layer can make on its behalf.
  [ "$T_GREEN" != "$T_RED" ] \
    || _perr "green and red are both $T_GREEN — every verdict is a comparison against red, so a checker that cannot fail would score canary-killed, controls-green and full recall at exit 0"

  _dup=$(LC_ALL=C sort "$P/ids" | uniq -d | tr '\n' ' ')
  [ -z "$(_trim "$_dup")" ] || _perr "duplicate id(s) within the target: $_dup"

  # A PREFIX AND A DECLARED ID COLLIDE SILENTLY OTHERWISE. `mutate STALE ...`
  # generates STALE-1, and `manual STALE-1` is then the same string naming two
  # different things — `--only STALE-1` cannot tell them apart and the report
  # prints one id twice. Caught here rather than discovered from a confusing
  # report, because the report would still look right.
  while IFS="$SEP" read -r _xp _xn _xa _xs; do
    [ -n "$_xp" ] || continue
    awk -v p="$_xp" '$0 ~ ("^" p "-[0-9]+$") { f = 1 } END { exit !f }' "$P/idsx" \
      && _perr "mutator prefix $_xp generates ids that collide with a declared id ${_xp}-N"
    # THE PER-MUTATOR SITE CAP WAS VALIDATED IN ONE PLACE AND USED IN TWO. The
    # global `sites` directive is checked above; this continuation was not, so
    # `sites eight` reached the arithmetic as a word — `[: eight: integer
    # expression expected` on stderr, the cap silently not applied, and the
    # report still saying `0 capped`. A cap that does not bind while claiming it
    # did is worse than no cap: it understates the surface that was searched.
    # Empty stays lawful and means "use the global".
    # THE CEILING TEST IS IN THE `*)` ARM, NOT AFTER THE case. `_perr` RECORDS a
    # parse error and returns — it does not abort — so a flat sequence ran the
    # arithmetic on the very value it had just rejected, and `[: eight: integer
    # expression expected` leaked to stderr underneath a correct verdict.
    if [ -n "$_xs" ]; then
      case "$_xs" in
        *[!0-9]*) _perr "mutate $_xn: sites must be an integer, got '$_xs'" ;;
        *) [ "$_xs" -le 64 ] || _perr "mutate $_xn: sites ceiling is 64, got $_xs" ;;
      esac
    fi
  done < "$P/mutators"

  # A TARGET WITHOUT A CONTROL IS NOT A TARGET. First of the five layers, and
  # the only one that fires before a single byte is mutated. A run with no
  # control can reach a flawless recall figure with a checker that refuses
  # everything; printing that number is worse than printing nothing.
  [ "$(_lines "$P/controls")" -ge 1 ] || _perr "no control declared — a target without a control is not a target"

  return 0
}

_lines() { [ -f "$1" ] && awk 'END{print NR+0}' "$1" || printf '0'; }

# _sed_col <file> <lineno> <col> <value> — set a tab column on one line.
#
# THE VALUE ARRIVES BY ENVIRONMENT, NOT BY -v, AND THAT IS THE WHOLE POINT.
# POSIX awk expands escape sequences in a -v assignment, so an ordinary English
# `why:` mentioning a backslash — "must keep its trailing \n", "a literal \| in
# the cell" — became a REAL newline inside this \034-delimited record and split
# one control row into two. Measured 2026-08-31: the target was refused at exit
# 5 naming a control the author never wrote, and the only clue was two
# characters inside a prose sentence. ENVIRON is not expanded, so the value
# survives byte-exact. Never reintroduce -v here.
_sed_col() {
  _t2="$1.tmp"
  _SC_V="$4" awk -F"$SEP" -v n="$2" -v c="$3" \
    'BEGIN{OFS="\034"; v=ENVIRON["_SC_V"]} { if (NR == n) $c = v; print }' "$1" > "$_t2"
  mv "$_t2" "$1"
}

# Layers 2 and 3 of the control rule, run once the seed is resolvable.
validate_controls() { # $1 = resolved seed path
  _vn=0
  _CTL_CMD=0
  _CTL_FILE=0
  while IFS="$SEP" read -r _ci _ct _cv _cvar _cwhy; do
    [ -n "$_ci" ] || continue
    _vn=$((_vn + 1))
    [ -n "$_cvar" ] || { _perr "control $_ci has no varies:"; continue; }
    [ -n "$_cwhy" ] || { _perr "control $_ci has no why:"; continue; }
    if [ "$_ct" = cmd ]; then
      # A cmd control that never names the subject is asserting something about
      # the world, not about this gate. Measured shape of the failure: `cmd true`.
      case "$_cv" in
        *'$SUBJECT'*|*'${SUBJECT}'*) ;;
        *) _perr "control $_ci does not exercise the subject (its command never names \$SUBJECT)" ;;
      esac
      _CTL_CMD=1
      continue
    fi
    _cf=$(_resolve "$_cv")
    [ -f "$_cf" ] || { _perr "control $_ci names a file that does not exist: $_cv"; continue; }
    # THE WAY THIS RULE ACTUALLY DIES IS A COPIED FILE NOBODY EDITED. Both
    # shapes are refused: byte-identical, and identical once the DISCOUNTABLE
    # lines are discounted.
    if cmp -s "$1" "$_cf"; then
      _perr "control $_ci is byte-identical to the seed; it asserts nothing"
      continue
    fi
    _CTL_FILE=1
    # THE BLANK-LINE DISCOUNT IS GONE, AND THE REASON IS THAT IT COULD NOT BE
    # MADE CORRECT. It tried to refuse a control that differs from the seed only
    # in lines "nobody could mean" — comments for a program, blank lines for a
    # document. Both classes turned out to be load-bearing for real gates on
    # this box, and both produced measured false positives on CORRECT
    # declarations (2026-08-31):
    #   · blank lines — `skills/casefile/bin/check-pack.sh` makes a blank line
    #     TERMINATE a markdown table, so whitespace is that gate's contract and
    #     the natural control for it was refused at exit 5;
    #   · `#` lines — `bin/lint-conventions.sh` rule S1 is a SHEBANG gate, and a
    #     `#!` line is an interpreter directive, not a comment. Its lawful
    #     variant differs from any seed in exactly two `#` lines, so S1 could
    #     never declare the control that proves its own waiver arm works.
    # Both times the message blamed the author for a correct control, and check
    # 2 is precisely the check that cannot be recovered any other way. Rule 11:
    # a false positive is a defect, and a guard that blocks ordinary work gets
    # switched off — at which point it protects nothing at all.
    #
    # WHAT WAS GIVEN UP, SO NOBODY RE-ADDS IT AS AN OVERSIGHT: a control that
    # differs from the seed ONLY in a comment now passes this layer. That is a
    # weak control, not a copied one, and three things still stand against it —
    # the byte-identical refusal above catches the actual observed failure (a
    # copied file nobody edited), the control must still be ACCEPTED by the
    # checker to score green, and `varies:` and `why:` are mandatory prose that
    # a human reads. Trading a bounded false negative for two proven false
    # positives is the trade this file exists to make. contracts/prove-targets.md
    # carries the binding wording.
    #
    # THE `#` DISCOUNT SURVIVES FOR posix-shell, MINUS THE SHEBANG. There a `#`
    # line really is a comment and a control that only rewords one asserts
    # nothing. But `#!` is an interpreter directive, not a comment, and a
    # shebang gate is the most ordinary posix-shell gate there is — measured
    # 2026-08-31, `bin/lint-conventions.sh` rule S1 IS one, and its lawful
    # variant differs from a seed in exactly two `#` lines, so S1 could not
    # declare the control proving its own waiver arm works. Discounting every
    # `#` refused that control; discounting every `#` EXCEPT a leading `#!`
    # keeps the guard and drops the false positive.
    if [ "$T_KIND" = posix-shell ]; then
      # awk, not `sed -e '1!{...}'`: BSD sed did not apply the negated block and
      # the filter silently passed both files through unchanged, so the guard
      # stopped firing while still looking present. Measured here 2026-08-31.
      _a="$WORK/.ctl-a"; _b="$WORK/.ctl-b"
      _shfil='NR == 1 && /^#!/ { print; next } /^[[:space:]]*#/ { next } /^[[:space:]]*$/ { next } { print }'
      awk "$_shfil" "$1"   > "$_a" 2>/dev/null
      awk "$_shfil" "$_cf" > "$_b" 2>/dev/null
      if cmp -s "$_a" "$_b"; then
        _perr "control $_ci is the seed wearing a control's name; it asserts nothing"
      fi
    fi
  done < "$P/controls"

  # THE MANDATORY CONTROL MUST BE DISCHARGED BY A FORM THAT REACHES THE CHECKER.
  # A cmd control runs its OWN command and scores that exit; the checker is
  # never invoked. When the subject is a program that is fine — the command
  # genuinely runs it, which is why `floor` and `prove-engine` declare only cmd
  # controls. When the subject is DATA, no command that merely mentions the file
  # can put it through the gate: measured 2026-08-31, `cmd [ -f "$SUBJECT" ]`
  # satisfied the mandatory control of an over-broad checker that refuses every
  # input but the byte-exact seed, and the run printed full recall at exit 0.
  # Requiring one FILE control rather than banning cmd controls outright keeps
  # them usable as the auxiliary mechanism they legitimately are — B24's own
  # fixture uses one to delete the next control's file — while making the
  # measured hole unspellable.
  if [ "$_vn" -gt 0 ] && [ "$_CTL_FILE" -eq 0 ] && [ "$T_KIND" != posix-shell ]; then
    _perr "subject-kind $T_KIND declares $_vn control(s), all cmd: a cmd control runs instead of the checker, so the gate never sees a lawful input — at least one control FILE is required"
  fi
  return 0
}

# THE SAME LAYER, POINTED AT PLANTINGS, AND IT WAS ABSENT. `why:` is MANDATORY
# on a plant in contracts/prove-targets.md, and until 2026-08-30 only
# bin/lint-conventions.sh rule C6 enforced it: the engine ran the same file to a
# verdict while the linter refused it. Two enforcers of one contract disagreeing
# is worse than either rule alone, because whichever one a reader met first
# taught them the other was noise. The engine was the weaker of the two, and a
# DECLARED survivor — the highest-value line this tool prints — arrived as a
# bare id with an empty explanation after it.
validate_plants() {
  while IFS="$SEP" read -r _pi _pr _pw; do
    [ -n "$_pi" ] || continue
    [ -n "$_pw" ] || _perr "plant $_pi has no why:"
  done < "$P/plants"
  return 0
}

# A STAGE DESTINATION OUTSIDE THE WORKSPACE IS AN AUTHORING ERROR, NOT AN
# ENVIRONMENT ONE, so it is REFUSED (5) here rather than reported COULD-NOT-LOOK
# (4) from _stage_all. The destination is a static property of the declaration —
# every variable it may name is expanded from values known before a single byte
# is staged — so it is knowable without running, and the repair is to fix the
# `stage` line. A `mkdir` or `cp` that then FAILS is the environment, and stays
# COULD-NOT-LOOK where it was. This runs AHEAD of the budget test so an
# authoring error is reported whatever the budget says.
validate_stages() {
  while IFS= read -r _sl; do
    [ -n "$_sl" ] || continue
    case "$(_word "$_sl" 1)" in
      mkdir)          _sd=$(_expand "$(_word "$_sl" 2)") ;;
      copy|copy-tree) _sd=$(_expand "$(_word "$_sl" 3)") ;;
      *) continue ;;
    esac
    case "$_sd" in
      "$WORK"/*) ;;
      *) _perr "stage destination is outside the workspace: $_sd" ;;
    esac
  done < "$P/stages"
  return 0
}

# ================================================================== RUNNING
RUNS=0
RC=0
# SETS $RC, NEVER PRINTS IT. The obvious shape — `rc=$(_run_checker x)` — puts
# the whole function in a COMMAND SUBSTITUTION, which is a subshell, so the
# RUNS increment is discarded the moment it returns. Measured: every run
# reported "0 runs, expected 3" and the run-counter tripwire fired on a
# perfectly good target. A counter that cannot count is worse than none,
# because it fires on the innocent and gets switched off.
# A WATCHDOG, BECAUSE THIS BOX HAS NO `timeout`. Not hypothetical: on
# 2026-08-30 a prove-engine mutant put the engine into an infinite awk loop and
# the sweep ran for twenty minutes with no output and no way to tell it from
# slow work. A harness that cannot bound its own subject is not a harness, and
# the SKILL says so in those words.
#
# WHAT IT CANNOT DO, STATED: _kill_tree reaches every descendant still linked
# by parent pid (harbor#743). One that already detached to PID 1, by a double
# fork, survives and is reported nowhere. Smaller than a hang, not solved.
#
# A TIMEOUT IS COULD-NOT-LOOK, NEVER A KILL. The mutant may well have been
# refused; nobody watched it finish, so nobody knows, and a guess in the
# generous direction is how recall gets manufactured.
PROVE_RUN_TIMEOUT_SET="${PROVE_RUN_TIMEOUT:+1}"
PROVE_RUN_TIMEOUT="${PROVE_RUN_TIMEOUT:-120}"
RUN_TIMED_OUT=0
RUN_TO_SECS="$PROVE_RUN_TIMEOUT"
# THE NAP IS MEASURED, NOT ASSUMED. A whole-second poll makes every run cost at
# least a second, and topology's 74 mutants each take 0.08s — the watchdog would
# have been a tenfold slowdown on the cheapest target, which is how a gate
# becomes too expensive to run and gets stood down. A fractional sleep is not in
# POSIX, so it is TESTED once here and the loop falls back to whole seconds when
# it is refused rather than spinning hot on an error.
if sleep 0.05 2>/dev/null; then _NAP=0.05; _NAPS=20; else _NAP=1; _NAPS=1; fi
_run_checker() { # $1 = log tag ; $2 = command (default: the target's checker-cmd)
  RUNS=$((RUNS + 1))
  RUN_TIMED_OUT=0
  _rcc="${2:-$T_CMD}"
  ( cd "$ROOT" && eval "$T_ENV $_rcc" ) > "$WORK/runs/$1.log" 2>&1 &
  _wpid=$!
  CHK_PID=$_wpid
  _wpolls=0
  # A PER-TARGET BOUND, BECAUSE ONE NUMBER CANNOT FIT BOTH KINDS. A markdown
  # gate answers in 0.08s; one trigger-routing checker run is a whole sweep of
  # live sessions and is minutes. Leaving the global 120s default in place
  # would have killed every live run and reported it as COULD-NOT-LOOK, which
  # is honest but useless. `run-timeout` in the declaration overrides it, and
  # an explicit PROVE_RUN_TIMEOUT in the environment still wins over both.
  _wto="${PROVE_RUN_TIMEOUT_SET:+$PROVE_RUN_TIMEOUT}"
  [ -n "$_wto" ] || _wto="${T_RTO:-$PROVE_RUN_TIMEOUT}"
  RUN_TO_SECS="$_wto"
  _wmax=$((_wto * _NAPS))
  while kill -0 "$_wpid" 2>/dev/null; do
    if [ "$_wpolls" -ge "$_wmax" ]; then
      _kill_tree "$_wpid"
      wait "$_wpid" 2>/dev/null
      CHK_PID=""
      RUN_TIMED_OUT=1
      RC=-1
      return 0
    fi
    sleep "$_NAP"
    _wpolls=$((_wpolls + 1))
  done
  wait "$_wpid"
  RC=$?
  CHK_PID=""
}

# ONLY RUNTIME FAILURES ARE REPORTED FROM HERE. The destination-inside-$WORK
# rule used to live in this loop and returned COULD-NOT-LOOK, which pointed the
# repair at the harness for what is an authoring mistake; it is now enforced at
# parse time by validate_stages and REFUSES the declaration. Nothing re-checks
# it here, because a second copy of a rule is a copy that drifts.
_stage_all() {
  while IFS= read -r _sl; do
    [ -n "$_sl" ] || continue
    _sv=$(_word "$_sl" 1)
    case "$_sv" in
      mkdir)
        _dst=$(_expand "$(_word "$_sl" 2)")
        mkdir -p "$_dst" || { STAGE_ERR="stage mkdir failed: $_dst"; return 1; } ;;
      copy|copy-tree)
        _src=$(_resolve "$(_expand "$(_word "$_sl" 2)")")
        _dst=$(_expand "$(_word "$_sl" 3)")
        mkdir -p "$(dirname "$_dst")"
        if [ "$_sv" = copy-tree ]; then
          cp -R "$_src" "$_dst" || { STAGE_ERR="stage copy-tree failed: $_src -> $_dst"; return 1; }
        else
          cp "$_src" "$_dst" || { STAGE_ERR="stage copy failed: $_src -> $_dst"; return 1; }
        fi ;;
    esac
  done < "$P/stages"
  return 0
}

# THE TRIGGER-ROUTING CHECKER CONTRACT, READ BY LABEL. Its first stdout line is
# `trigger-probe: pos A/B  neg C/D  ...`; this pulls one labelled value out of
# it. By label, never by column, so adding a field to that line later cannot
# silently move what this reads — the failure would be a wrong number rather
# than an error, which is the worst shape a defect can have.
_probe_field() { # $1 = log ; $2 = label
  [ -f "$1" ] || return 0
  awk -v lab="$2" '/^trigger-probe: / { for (i = 2; i < NF; i++) if ($i == lab) { print $(i+1); exit } }' "$1"
}

_selected() { # $1 = mutant id ; 0 when it should run
  [ -z "$ONLY" ] && return 0
  printf '%s' "$ONLY" | tr ',' '\n' | /usr/bin/grep -Fxq "$1"
}

# ================================================================== REPORT
# ONE FUNCTION EMITS THE RECALL BLOCK, AND IT EMITS THE THREE NOTE LINES IN THE
# SAME CALL. A recall figure with no control count above it and no note below it
# is unreachable in this code rather than merely discouraged — nothing else in
# this file prints F10 or F16.
_recall_block() {
  printf '  GENERATED  %d/%d killed  %d inert  %d no-site  %d capped\n' \
    "$G_KILL" "$G_ELIG" "$G_INERT" "$G_NOSITE" "$G_CAPPED"
  while IFS="$SEP" read -r _cm _ck _ce _cs _cr; do
    [ -n "$_cm" ] || continue
    if [ "$_cs" = no-site ]; then
      printf '    %-20s no-site — %s\n' "$_cm" "$_cr"
    elif [ "$_cs" = unavailable ]; then
      printf '    %-20s unavailable — %s\n' "$_cm" "$_cr"
    else
      printf '    %-20s %d/%d killed\n' "$_cm" "$_ck" "$_ce"
      # A SUB-LINE, INDENTED LIKE A SURVIVOR'S. Repeating the mutator name in
      # column one would render one capped class as two classes, and the reader
      # counting classes would be counting wrong.
      [ -n "$_cr" ] && printf '      capped from %s sites\n' "$_cr"
    fi
  done < "$WORK/classes"
  while IFS="$SEP" read -r _si _sm _ss; do
    [ -n "$_si" ] || continue
    printf '    SURVIVOR  %-10s %-20s %s\n' "$_si" "$_sm" "$_ss"
    printf '      diff   mutants/%s.diff\n' "$_si"
    printf '      rerun  %s %s --only %s --keep\n' "$SELF_INVOCATION" "$T_NAME" "$_si"
  done < "$WORK/survivors"
  printf '  DECLARED   %d/%d killed\n' "$D_KILL" "$D_ELIG"
  while IFS="$SEP" read -r _di _dw; do
    [ -n "$_di" ] || continue
    printf '    SURVIVOR  %-10s %s\n' "$_di" "$_dw"
  done < "$WORK/dsurvivors"
  printf '  NOTE  %s\n' 'GENERATED and DECLARED do not add and are not comparable. GENERATED'
  printf '  NOTE  %s\n' 'measures the mechanical surface; DECLARED measures only what somebody'
  printf '  NOTE  %s\n' 'thought to write down. The survivor is the finding; the ratio is not.'
}

# ============================================================== ONE TARGET
# Returns the target's exit code in TRC. Everything is measured first and the
# report is emitted afterwards, because the GENERATED header carries counts that
# are only known once the last mutant has run.
run_target() {
  TRC=0
  # PER TARGET, NOT PER PROCESS. Left global, the second target in a multi-target
  # run inherits the first one's count and the run-counter tripwire fires on a
  # perfectly good target — measured: 71 runs, expected 21. A tripwire that
  # cries wolf gets deleted, and then the phase-skip it guards is invisible.
  RUNS=0
  T_START=$(date +%s)
  WORK="$WORKROOT/$(basename "$1" .target)"
  mkdir -p "$WORK/runs" "$WORK/mutants"
  : > "$WORK/classes"; : > "$WORK/survivors"; : > "$WORK/dsurvivors"
  G_KILL=0; G_ELIG=0; G_INERT=0; G_NOSITE=0; G_CAPPED=0
  D_KILL=0; D_ELIG=0; C_GREEN=0; C_TOTAL=0
  BASELINE=""; CANARY=""; PARTIAL=0; APPLIED=0; INERT_IDS=""
  STAGE_ERR=""; CTL_RED=0; VACUOUS=""; ABLATION=""
  # SAME RULE AS RUNS, AND IT WAS MISSED HERE. Initialised once in the driver,
  # `--require-scanners` LEAKED: measured 2026-08-30, a target that declares no
  # scanner at all reports PROVEN exit 0 alone and COULD-NOT-LOOK exit 4 — with
  # its whole GENERATED block suppressed — when it merely runs after a target
  # whose scanner is absent. A fully measured target reported as unmeasured is
  # the failure this engine exists to detect, arriving from the engine itself.
  SCAN_MISSING=0

  parse_target "$1"
  if [ -n "$PARSE_ERR" ]; then
    printf 'prove: %s  %s  %s\n' "$(basename "$1" .target)" REFUSED "$PARSE_ERR"
    TRC=5; return 0
  fi

  # THE COST GATE. A trigger-routing run bills a live session per query per
  # mutant, so it never runs by accident. Named explicitly without the flag it
  # is COULD-NOT-LOOK rather than a skip: asking for a measurement and getting
  # exit 0 with no measurement is the exact shape this engine exists to detect,
  # and `claude plugin eval init` printing an early-access notice and exiting 0
  # is the live example of it three lines from here.
  if [ "$T_KIND" = trigger-routing ] && [ "$LIVE_TRIGGERS" != 1 ]; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" COULD-NOT-LOOK \
      "NOT RUN  subject-kind trigger-routing spends real money on live sessions; re-run with --live-triggers (cost is declared in the target)"
    TRC=4; return 0
  fi

  SEED=$(_resolve "$T_SEED")
  if [ ! -f "$SEED" ]; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" REFUSED "seed does not exist: $T_SEED"
    TRC=5; return 0
  fi
  PLACE=$(_expand "$T_PLACE")
  case "$PLACE" in
    "$WORK"/*) ;;
    *) printf 'prove: %s  %s  %s\n' "$T_NAME" REFUSED "place is outside the workspace: $T_PLACE"
       TRC=5; return 0 ;;
  esac

  validate_controls "$SEED"
  validate_plants
  validate_stages
  if [ -n "$PARSE_ERR" ]; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" REFUSED "$PARSE_ERR"
    TRC=5; return 0
  fi
  C_TOTAL=$(_lines "$P/controls")

  # ---- planning: sites are counted before anything is staged, so the budget
  # decision costs nothing and a target that will not run says so up front.
  : > "$WORK/plan"
  _need_date=0
  _mn=0
  while IFS="$SEP" read -r _pfx _name _arg _sit; do
    [ -n "$_pfx" ] || continue
    _mn=$((_mn + 1))
    [ "$_name" = date-shift ] && _need_date=1
    _cap="$_sit"; [ -z "$_cap" ] && _cap="$T_SITES"
    _n=$(_mut count "$_name" "$SEED" 0 "$_arg" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    _use="$_n"
    [ "$_n" -gt "$_cap" ] && _use="$_cap"
    printf '%s\034%s\034%s\034%s\034%s\n' "$_pfx" "$_name" "$_arg" "$_n" "$_use" >> "$WORK/plan"
  done < "$P/mutators"

  _planned=$(awk -F"$SEP" '{ s += $5 } END { print s + 0 }' "$WORK/plan")
  _nplant=$(_lines "$P/plants")
  _nabl0=0; [ -n "$T_ABLATE" ] && _nabl0=1
  _totruns=$((1 + 1 + _nabl0 + C_TOTAL + _planned + _nplant))
  if [ "$BUDGETED" = 1 ]; then
    _est=$((T_COST * _totruns))
    if [ "$_est" -gt "$PROVE_BUDGET" ]; then
      printf 'prove: %s  %s  %s\n' "$T_NAME" COULD-NOT-LOOK \
        "NOT RUN  over budget (cost ${T_COST}s x $_totruns runs = ${_est}s > ${PROVE_BUDGET}s)"
      TRC=4; return 0
    fi
  fi

  if [ "$_need_date" = 1 ] && ! _shift_one 2026-01-01 +1d >/dev/null 2>&1; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" COULD-NOT-LOOK \
      "date-shift declared but unavailable — no usable date(1) on this box"
    TRC=4; return 0
  fi

  # THE RECIPE ENVIRONMENT, EXPORTED RATHER THAN INHERITED. A recipe, a control
  # command and a checker are all `eval`'d in a subshell, so a plain shell
  # variable would reach them — but a checker is a CHILD PROCESS and sees only
  # what is exported. Exporting all eight makes the two cases behave the same,
  # which is what a declaration author will assume.
  TARGET="$T_NAME"; SEED="$SEED"; WORK="$WORK"; TDIR="$TDIR"
  export ROOT WORK TDIR SEED TODAY TARGET

  # ---- stage
  if ! _stage_all; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" COULD-NOT-LOOK "$STAGE_ERR"
    TRC=4; return 0
  fi
  mkdir -p "$(dirname "$PLACE")" 2>/dev/null
  if ! cp "$SEED" "$PLACE" 2>/dev/null; then
    printf 'prove: %s  %s  %s\n' "$T_NAME" COULD-NOT-LOOK "place is not writable: $T_PLACE"
    TRC=4; return 0
  fi

  # ---- baseline. A checker that refuses its own pristine subject measures
  # nothing afterwards: every mutant would be "killed" by the same refusal.
  _run_checker baseline; _rc=$RC
  [ "$RUN_TIMED_OUT" = 1 ] && VACUOUS="the baseline run exceeded PROVE_RUN_TIMEOUT=${RUN_TO_SECS}s and was killed"
  if [ "$_rc" = "$T_GREEN" ]; then BASELINE=GREEN; else BASELINE=RED; VACUOUS="baseline is not green (exit $_rc)"; fi

  # ---- canary. GENERATED BY CONSTRUCTION AND UNSKIPPABLE. Its kill is
  # guaranteed unless the checker is not reading what this engine mutates — a
  # moved artefact, a renamed subject, a flag that changed what gets read. That
  # failure is otherwise SILENT: every mutant survives and the report reads as a
  # weak gate rather than as a broken harness.
  if [ -z "$VACUOUS" ]; then
    if [ "$T_KIND" = posix-shell ]; then
      printf '#!/usr/bin/env sh\nexit 7\n' > "$PLACE"
    else
      : > "$PLACE"
    fi
    _run_checker canary; _rc=$RC
    [ "$RUN_TIMED_OUT" = 1 ] && VACUOUS="the canary run exceeded PROVE_RUN_TIMEOUT=${RUN_TO_SECS}s and was killed"
    if [ "$_rc" = "$T_RED" ]; then CANARY=KILLED; else CANARY=SURVIVED; VACUOUS="canary survived — the checker does not read what this engine mutates"; fi
  fi

  # ---- ablation. RUN ONCE, NEVER PER MUTANT, and only where a declaration
  # asks for it. THE ARM EXISTS BECAUSE EVERY OTHER NUMBER HERE IS ENDOGENOUS:
  # a trigger checker reports how often a session routed to the thing this
  # engine planted, and a checker whose detector matches something other than
  # an invocation — the planted name echoed in the session's own skill listing,
  # say, which is in the init event of every single run — reports a flawless
  # rate while measuring nothing. Running the same queries with NOTHING PLANTED
  # is the falsifier: the token cannot be invoked, so the only correct answer is
  # zero, and a non-zero one condemns every figure above it.
  #
  # A NON-GREEN ABLATION IS COULD-NOT-LOOK, NOT A SURVIVOR. The repair is the
  # harness, not the checker under test.
  ABLATION=""
  if [ -z "$VACUOUS" ] && [ -n "$T_ABLATE" ]; then
    cp "$SEED" "$PLACE" 2>/dev/null
    SUBJECT="$PLACE"; export SUBJECT
    _run_checker ablation "$T_ABLATE"; _rc=$RC
    if [ "$RUN_TIMED_OUT" = 1 ]; then
      VACUOUS="the ablation run exceeded ${RUN_TO_SECS}s and was killed"
    elif [ "$_rc" != "$T_GREEN" ]; then
      VACUOUS="ablation exit $_rc: the queries fired with NOTHING planted, so the checker cannot tell presence from absence and every rate it prints is noise (runs/ablation.log)"
    else
      # THE DELTA IS READ OFF THE CHECKER'S OWN CONTRACT LINE, BY LABEL RATHER
      # THAN BY POSITION, so a field added to that line later cannot silently
      # shift the number this reads. contracts/prove-targets.md pins the line.
      _abp=$(_probe_field "$WORK/runs/ablation.log" pos)
      _bap=$(_probe_field "$WORK/runs/baseline.log" pos)
      if [ -n "$_abp" ] && [ -n "$_bap" ]; then
        _bn="${_bap%%/*}"; _an="${_abp%%/*}"
        ABLATION="pos $_bap with the pack, ${_an}/${_abp#*/} without  delta $((_bn - _an))"
      else
        ABLATION="ran green, but no 'trigger-probe: ... pos N/M' line was printed, so no delta is computable"
      fi
    fi
  fi

  # ---- controls, BEFORE the first mutant and with their own exit code. A rule
  # that refuses everything kills every mutant and would otherwise print a
  # flawless score; here it never reaches the mutant loop.
  : > "$WORK/ctlrows"
  if [ -z "$VACUOUS" ]; then
    _i=0
    while IFS="$SEP" read -r _ci _ct _cv _cvar _cwhy; do
      [ -n "$_ci" ] || continue
      _i=$((_i + 1))
      cp "$SEED" "$PLACE"
      SUBJECT="$PLACE"; export SUBJECT
      if [ "$_ct" = file ]; then
        # AN UNPLACEABLE CONTROL IS COULD-NOT-LOOK, AND THE UNCHECKED cp MADE IT
        # INVISIBLE. The seed is already at $PLACE from the line above, so a cp
        # that failed left the BASELINE sitting there and the run scored it as
        # the control: measured 2026-08-30 with an unreadable control file,
        # `CONTROLS 1/1 green` and `VERDICT PROVEN exit 0` over a control that
        # was never exercised and a baseline that ran twice. Not CONTROL-RED,
        # which would point the repair at the checker and invite loosening a
        # rule that is fine; not REFUSED, because the declaration is correct.
        # Nobody looked, so it says nobody looked.
        if ! cp "$(_resolve "$_cv")" "$PLACE" 2>/dev/null; then
          VACUOUS="control $_ci could not be placed: $_cv is unreadable — the control was never exercised"
          break
        fi
        _run_checker "control-$_ci"; _rc=$RC
      else
        RUNS=$((RUNS + 1))
        ( cd "$ROOT" && eval "$_cv" ) > "$WORK/runs/control-$_ci.log" 2>&1
        _rc=$?
        # 127 IS A TYPO, NOT A REFUSAL — the same distinction the file branch
        # above was repaired to make. A control command that was never found did
        # not measure the gate, and scoring it CONTROL-RED points the next
        # reader at the checker and invites loosening a rule that is fine.
        if [ "$_rc" -eq 127 ] && [ "$T_GREEN" != 127 ]; then
          VACUOUS="control $_ci could not run: its command exited 127 (command not found) — the control was never exercised"
          break
        fi
      fi
      if [ "$_rc" = "$T_GREEN" ]; then
        C_GREEN=$((C_GREEN + 1))
        printf 'ok\034%s\034%s\034%s\n' "$_ci" "$_cvar" "$_cwhy" >> "$WORK/ctlrows"
      else
        CTL_RED=1
        printf 'RED\034%s\034%s\034%s\n' "$_ci" "$_cvar" "$_cwhy" >> "$WORK/ctlrows"
      fi
    done < "$P/controls"
  fi

  # ---- mutants
  if [ -z "$VACUOUS" ] && [ "$CTL_RED" = 0 ]; then
    while IFS="$SEP" read -r _pfx _name _arg _nsite _use; do
      [ -n "$_pfx" ] || continue
      if [ "$_nsite" -eq 0 ]; then
        G_NOSITE=$((G_NOSITE + 1))
        printf '%s\0340\0340\034no-site\034%s\n' "$_name" "$(_nosite_reason "$_name")" >> "$WORK/classes"
        continue
      fi
      _capnote=""
      if [ "$_nsite" -gt "$_use" ]; then G_CAPPED=$((G_CAPPED + 1)); _capnote="$_nsite"; fi
      _ck=0; _ce=0
      _j=1
      while [ "$_j" -le "$_use" ]; do
        _id="$_pfx-$_j"
        if ! _selected "$_id"; then _j=$((_j + 1)); continue; fi
        _mf="$WORK/mutants/$_id"
        if ! _mut apply "$_name" "$SEED" "$_j" "$_arg" > "$_mf" 2>"$WORK/runs/$_id.err"; then
          VACUOUS="mutator $_name failed to produce mutant $_id"
          break
        fi
        # AN EMPTY MUTANT IS THE CANARY WEARING A MUTANT'S NAME, and this path
        # had no emptiness test at all. Measured 2026-08-30: a one-section seed
        # makes `section-delete` site 1 delete the whole file, and the zero-byte
        # result was scored `GENERATED 1/1 killed`, `VERDICT PROVEN`, exit 0 —
        # the checker's refusal was guaranteed by the emptiness this engine
        # already writes at `: > "$PLACE"`, so the canary was counted a second
        # time under another name and nothing new was measured.
        if [ ! -s "$_mf" ]; then
          VACUOUS="mutator $_name produced an empty mutant $_id — an empty subject IS the canary, so scoring it would count the canary twice"
          break
        fi
        # AN INERT MUTANT IS NEVER A FREE KILL. A recipe that matched nothing
        # produces a byte-identical copy; crediting the checker for refusing it
        # would be crediting it for refusing the seed, which it must not do.
        if cmp -s "$SEED" "$_mf"; then
          G_INERT=$((G_INERT + 1)); INERT_IDS="$INERT_IDS $_id"
          _j=$((_j + 1)); continue
        fi
        diff -u "$SEED" "$_mf" > "$WORK/mutants/$_id.diff" 2>/dev/null
        cp "$_mf" "$PLACE"
        _run_checker "$_id"; _rc=$RC
        if [ "$RUN_TIMED_OUT" = 1 ]; then
          VACUOUS="$_id exceeded PROVE_RUN_TIMEOUT=${RUN_TO_SECS}s and was killed — a mutant that HANGS is not a mutant that was refused"
          break
        fi
        APPLIED=$((APPLIED + 1))
        _ce=$((_ce + 1)); G_ELIG=$((G_ELIG + 1))
        if [ "$_rc" = "$T_RED" ]; then
          _ck=$((_ck + 1)); G_KILL=$((G_KILL + 1))
        elif [ "$_rc" = "$T_GREEN" ]; then
          _desc=$(_mut desc "$_name" "$SEED" "$_j" "$_arg" 2>/dev/null)
          printf '%s\034%s\034%s\n' "$_id" "$_name" "$_desc" >> "$WORK/survivors"
        else
          # A CRASH IS NOT A KILL. An exit that is neither green nor red says
          # the checker fell over, and counting it as a refusal manufactures
          # recall out of a broken run.
          VACUOUS="checker exited $_rc on $_id, which is neither green ($T_GREEN) nor red ($T_RED)"
          break
        fi
        _j=$((_j + 1))
      done
      printf '%s\034%d\034%d\034\034%s\n' "$_name" "$_ck" "$_ce" "$_capnote" >> "$WORK/classes"
      [ -n "$VACUOUS" ] && break
    done < "$WORK/plan"
  fi

  # ---- plantings
  if [ -z "$VACUOUS" ] && [ "$CTL_RED" = 0 ]; then
    while IFS="$SEP" read -r _pi _pr _pw; do
      [ -n "$_pi" ] || continue
      _selected "$_pi" || continue
      MUTANT="$WORK/mutants/$_pi"; export MUTANT
      ( cd "$ROOT" && eval "$_pr" ) > "$WORK/runs/$_pi.err" 2>&1
      _prc=$?
      # THE OLD TEST COULD NOT SEE AN EMPTY MUTANT. `[ ! -s ] && [ ! -f ]` is
      # true only when the file does NOT EXIST, so an existing-but-empty mutant
      # walked past it, then differed from the seed so the inertness test below
      # passed it too, and it was RUN — as a subject byte-identical to the
      # canary, whose refusal is therefore guaranteed and was banked as recall.
      # Measured 2026-08-30: a plant whose `grep` matched nothing, and a plant
      # with an unterminated `sed`, each reported `DECLARED 1/1 killed`,
      # `VERDICT PROVEN`, exit 0, with the failing recipe invisible.
      #
      # EMPTINESS IS THE TEST, NOT THE RECIPE'S EXIT STATUS. A legitimate
      # grep/sed recipe can exit non-zero having written a perfectly good
      # mutant, so failing on $? would refuse correct declarations. The status
      # goes in the reason instead, together with the path to the recipe's own
      # output, so the report names the cause rather than leaving it to be
      # guessed — a discarded exit status was the deeper defect here.
      if [ ! -s "$MUTANT" ]; then
        VACUOUS="plant $_pi produced no mutant — the recipe exited $_prc and wrote nothing; its output is in runs/$_pi.err (an empty subject IS the canary)"
        break
      fi
      if cmp -s "$SEED" "$MUTANT"; then
        G_INERT=$((G_INERT + 1)); INERT_IDS="$INERT_IDS $_pi"
        continue
      fi
      diff -u "$SEED" "$MUTANT" > "$WORK/mutants/$_pi.diff" 2>/dev/null
      cp "$MUTANT" "$PLACE"
      _run_checker "$_pi"; _rc=$RC
      if [ "$RUN_TIMED_OUT" = 1 ]; then
        VACUOUS="$_pi exceeded PROVE_RUN_TIMEOUT=${RUN_TO_SECS}s and was killed — a mutant that HANGS is not a mutant that was refused"
        break
      fi
      APPLIED=$((APPLIED + 1))
      D_ELIG=$((D_ELIG + 1))
      if [ "$_rc" = "$T_RED" ]; then
        D_KILL=$((D_KILL + 1))
      elif [ "$_rc" = "$T_GREEN" ]; then
        printf '%s\034%s\n' "$_pi" "$_pw" >> "$WORK/dsurvivors"
      else
        VACUOUS="checker exited $_rc on $_pi, which is neither green ($T_GREEN) nor red ($T_RED)"
        break
      fi
    done < "$P/plants"
  fi

  # ---- the run counter. A TRIPWIRE, NOT A STATISTIC: the identity holds by
  # construction, so a mismatch means a phase was skipped and the report is
  # describing runs that did not happen.
  if [ -z "$VACUOUS" ] && [ "$CTL_RED" = 0 ]; then
    _nabl=0; [ -n "$T_ABLATE" ] && _nabl=1
    _expect=$((1 + 1 + _nabl + C_TOTAL + APPLIED))
    if [ "$RUNS" -ne "$_expect" ]; then
      VACUOUS="run counter mismatch: $RUNS runs, expected $_expect (1 baseline + 1 canary + $_nabl ablation + $C_TOTAL controls + $APPLIED mutants)"
    fi
  fi
  if [ -z "$VACUOUS" ] && [ "$CTL_RED" = 0 ] && [ "$APPLIED" -eq 0 ]; then
    VACUOUS="zero mutants applied — nothing was measured"
  fi
  # AN INERT MUTANT IS A BROKEN RECIPE, NOT A CLEAN RESULT. The recipe matched
  # nothing, so the run measured the seed while reporting on a mutant. Counting
  # it as anything other than "could not look" hands the declaration a kill it
  # never earned, and the report would read identically to a real one.
  if [ -z "$VACUOUS" ] && [ "$CTL_RED" = 0 ] && [ "$G_INERT" -gt 0 ]; then
    VACUOUS="$G_INERT inert mutant(s) —$INERT_IDS — a recipe matched nothing, so the run measured the seed"
  fi

  # ---- scanners. ABSENCE NEVER COUNTS AS A PASS and never raises `killed`.
  : > "$WORK/scanrows"
  if [ "$CTL_RED" = 0 ] && [ -z "$VACUOUS" ]; then
    while IFS="$SEP" read -r _sn _sa; do
      [ -n "$_sn" ] || continue
      if command -v "$_sn" >/dev/null 2>&1; then
        ( cd "$ROOT" && eval "$_sa" ) > "$WORK/runs/scanner-$_sn.log" 2>&1
        _src=$?
        if [ "$_src" -eq 0 ]; then
          printf '%s\034ran, exit 0 — outside every fraction\n' "$_sn" >> "$WORK/scanrows"
        else
          printf '%s\034ADAPTER ERROR — %s\n' "$_sn" "$_src" >> "$WORK/scanrows"
        fi
      else
        printf '%s\034NOT INSTALLED — no coverage obtained, not a pass\n' "$_sn" >> "$WORK/scanrows"
        [ "$REQUIRE_SCANNERS" = 1 ] && SCAN_MISSING=1
      fi
    done < "$P/scanners"
  fi

  # ---- verdict
  _capnote2=""
  if [ -n "$VACUOUS" ]; then
    VERDICT=COULD-NOT-LOOK; TRC=4
  elif [ "$CTL_RED" = 1 ]; then
    VERDICT=CONTROL-RED; TRC=3
  elif [ "$(_lines "$WORK/survivors")" -gt 0 ] || [ "$(_lines "$WORK/dsurvivors")" -gt 0 ]; then
    VERDICT=SURVIVORS; TRC=1
  elif [ "${SCAN_MISSING:-0}" = 1 ]; then
    VERDICT=COULD-NOT-LOOK; TRC=4
    VACUOUS="--require-scanners: a declared scanner is absent from PATH"
  elif [ -n "$ONLY" ]; then
    VERDICT=PARTIAL; TRC=0; PARTIAL=1
  elif [ "$G_CAPPED" -gt 0 ]; then
    VERDICT="PROVEN (partial: $G_CAPPED classes capped)"; TRC=0
  else
    VERDICT=PROVEN; TRC=0
  fi
  [ -n "$_capnote2" ] && :

  T_ELAPSED=$(( $(date +%s) - T_START ))
  return 0
}

emit_report() {
  printf 'prove: %s  kind=%s  lane=%s  cost=%ss\n' "$T_NAME" "$T_KIND" "$T_LANE" "$T_COST"
  printf '  workspace  %s  (removed on exit; --keep to retain)\n' "$WORK"
  printf '  seed       %s\n' "$T_SEED"
  printf '  place      %s\n' "$T_PLACE"
  printf '  checker    %s\n' "$T_CMD"
  printf '\n'
  printf '  BASELINE   %s\n' "$BASELINE"
  [ -n "$CANARY" ] && printf '  CANARY     %s\n' "$CANARY"
  [ -n "${ABLATION:-}" ] && printf '  ABLATION   %s\n' "$ABLATION"
  if [ -n "$CANARY" ] && [ "$CANARY" = KILLED ]; then
    printf '  CONTROLS   %d/%d green\n' "$C_GREEN" "$C_TOTAL"
    while IFS="$SEP" read -r _st _ci _cvar _cwhy; do
      [ -n "$_ci" ] || continue
      printf '    %-4s %-16s varies=%-10s %s\n' "$_st" "$_ci" "$_cvar" "$_cwhy"
    done < "$WORK/ctlrows"
  fi
  printf '\n'
  if [ "$CTL_RED" = 0 ] && [ "$VERDICT" != COULD-NOT-LOOK ]; then
    _recall_block
    printf '\n'
    if [ "$(_lines "$P/manuals")" -gt 0 ]; then
      printf '  UNPROVEN   %d\n' "$(_lines "$P/manuals")"
      while IFS="$SEP" read -r _mi _md; do
        [ -n "$_mi" ] || continue
        printf '    %-10s %s\n' "$_mi" "$_md"
      done < "$P/manuals"
      printf '\n'
    fi
    if [ "$(_lines "$WORK/scanrows")" -gt 0 ]; then
      printf '  SCANNERS   %d declared\n' "$(_lines "$WORK/scanrows")"
      while IFS="$SEP" read -r _sn _ss; do
        [ -n "$_sn" ] || continue
        printf '    %-24s %s\n' "$_sn" "$_ss"
      done < "$WORK/scanrows"
      printf '\n'
    fi
  elif [ "$VERDICT" = COULD-NOT-LOOK ] && [ -n "$VACUOUS" ]; then
    printf '  REASON     %s\n' "$VACUOUS"
    printf '\n'
  fi
  printf '  VERDICT    %s  exit %d\n' "$VERDICT" "$TRC"
}

emit_json_target() {
  printf '  {\n'
  printf '    "target":"%s", "kind":"%s", "lane":"%s",\n' "$(_jesc "$T_NAME")" "$T_KIND" "$T_LANE"
  printf '    "workspace":"%s", "elapsed_s":%d,\n' "$(_jesc "$WORK")" "$T_ELAPSED"
  printf '    "baseline":"%s", "canary":"%s", "ablation":"%s", "partial":%s,\n' \
    "$BASELINE" "${CANARY:-NOT-RUN}" "$(_jesc "${ABLATION:-NOT-DECLARED}")" \
    "$( [ "$PARTIAL" = 1 ] && printf true || printf false )"
  printf '    "controls":{"green":%d,"red":%d,\n' "$C_GREEN" "$((C_TOTAL - C_GREEN))"
  printf '      "cases":['
  _first=1
  while IFS="$SEP" read -r _st _ci _cvar _cwhy; do
    [ -n "$_ci" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    printf '{"id":"%s","varies":"%s","status":"%s"}' \
      "$(_jesc "$_ci")" "$(_jesc "$_cvar")" "$( [ "$_st" = ok ] && printf green || printf red )"
  done < "$WORK/ctlrows"
  printf ']},\n'
  printf '    "generated":{"killed":%d,"eligible":%d,"inert":%d,"nosite":%d,"capped":%d,\n' \
    "$G_KILL" "$G_ELIG" "$G_INERT" "$G_NOSITE" "$G_CAPPED"
  printf '      "classes":['
  _first=1
  while IFS="$SEP" read -r _cm _ck _ce _cs _cr; do
    [ -n "$_cm" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    if [ -n "$_cs" ]; then
      printf '{"mutator":"%s","status":"%s"}' "$(_jesc "$_cm")" "$_cs"
    else
      printf '{"mutator":"%s","killed":%d,"eligible":%d}' "$(_jesc "$_cm")" "$_ck" "$_ce"
    fi
  done < "$WORK/classes"
  printf '],\n      "survivors":['
  _first=1
  while IFS="$SEP" read -r _si _sm _ss; do
    [ -n "$_si" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    printf '{"id":"%s","mutator":"%s","site":"%s"}' "$(_jesc "$_si")" "$(_jesc "$_sm")" "$(_jesc "$_ss")"
  done < "$WORK/survivors"
  printf ']},\n'
  printf '    "declared":{"killed":%d,"eligible":%d,"survivors":[' "$D_KILL" "$D_ELIG"
  _first=1
  while IFS="$SEP" read -r _di _dw; do
    [ -n "$_di" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    printf '{"id":"%s","why":"%s"}' "$(_jesc "$_di")" "$(_jesc "$_dw")"
  done < "$WORK/dsurvivors"
  printf ']},\n'
  printf '    "unproven":['
  _first=1
  while IFS="$SEP" read -r _mi _md; do
    [ -n "$_mi" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    printf '{"id":"%s","why":"%s"}' "$(_jesc "$_mi")" "$(_jesc "$_md")"
  done < "$P/manuals"
  printf '],\n'
  printf '    "scanners":['
  _first=1
  while IFS="$SEP" read -r _sn _ss; do
    [ -n "$_sn" ] || continue
    [ "$_first" = 1 ] || printf ','
    _first=0
    case "$_ss" in
      "NOT INSTALLED"*) _sv=absent ;;
      "ADAPTER ERROR"*) _sv=error ;;
      *) _sv=ran ;;
    esac
    printf '{"name":"%s","status":"%s"}' "$(_jesc "$_sn")" "$_sv"
  done < "$WORK/scanrows"
  printf '],\n'
  printf '    "verdict":"%s","exit":%d }' "$(_jesc "$VERDICT")" "$TRC"
}

# ============================================================== SELECTION
_all_targets() {
  find "$PROVE_TARGETS" -maxdepth 1 -name '*.target' -type f 2>/dev/null | LC_ALL=C sort
}

_resolve_selector() { # prints the .target path, or nothing
  if [ -f "$PROVE_TARGETS/$1.target" ]; then
    printf '%s' "$PROVE_TARGETS/$1.target"
    return 0
  fi
  _hits=""
  _n=0
  while IFS= read -r _tf; do
    [ -n "$_tf" ] || continue
    _sd=$(awk '$1 == "seed" { sub(/^[^[:space:]]*[[:space:]]*/, ""); print; exit }' "$_tf")
    _cc=$(awk '$1 == "checker-cmd" { sub(/^[^[:space:]]*[[:space:]]*/, ""); print; exit }' "$_tf")
    _match=0
    [ "$_sd" = "$1" ] && _match=1
    [ "$_sd" = "repo:$1" ] && _match=1
    case " $_cc " in *" $1 "*) _match=1 ;; esac
    if [ "$_match" = 1 ]; then
      _n=$((_n + 1)); _hits="$_hits $(basename "$_tf" .target)"
      _pick="$_tf"
    fi
  done <<SEL
$(_all_targets)
SEL
  [ "$_n" -eq 1 ] && { printf '%s' "$_pick"; return 0; }
  SEL_CANDIDATES="$_hits"
  return 1
}

# ================================================================== MODES
mode_list() {
  _rc=0
  while IFS= read -r _tf; do
    [ -n "$_tf" ] || continue
    WORK="$WORKROOT/list"; mkdir -p "$WORK"
    parse_target "$_tf"
    if [ -n "$PARSE_ERR" ]; then
      printf '%-22s INVALID  %s\n' "$(basename "$_tf" .target)" "$PARSE_ERR"
      _rc=5; continue
    fi
    printf '%-22s kind=%-18s lane=%-5s cost=%-4s mutators=%-3s plantings=%-3s manual=%-3s controls=%s\n' \
      "$T_NAME" "$T_KIND" "$T_LANE" "$T_COST" \
      "$(_lines "$P/mutators")" "$(_lines "$P/plants")" "$(_lines "$P/manuals")" "$(_lines "$P/controls")"
  done <<LIST
$(_all_targets)
LIST
  exit "$_rc"
}

mode_explain() {
  WORK="$WORKROOT/explain"; mkdir -p "$WORK"
  parse_target "$1"
  if [ -n "$PARSE_ERR" ]; then
    printf 'prove: %s  REFUSED  %s\n' "$(basename "$1" .target)" "$PARSE_ERR"
    exit 5
  fi
  SEED=$(_resolve "$T_SEED")
  [ -f "$SEED" ] || { printf 'prove: %s  REFUSED  seed does not exist: %s\n' "$T_NAME" "$T_SEED"; exit 5; }
  validate_controls "$SEED"
  if [ -n "$PARSE_ERR" ]; then
    printf 'prove: %s  REFUSED  %s\n' "$T_NAME" "$PARSE_ERR"
    exit 5
  fi
  printf 'prove: %s  kind=%s  lane=%s  cost=%ss\n' "$T_NAME" "$T_KIND" "$T_LANE" "$T_COST"
  printf '  seed       %s\n' "$T_SEED"
  printf '  place      %s\n' "$T_PLACE"
  printf '  checker    %s\n' "$T_CMD"
  printf '  sites cap  %s\n' "$T_SITES"
  printf '\n  GENERATED\n'
  while IFS="$SEP" read -r _pfx _name _arg _sit; do
    [ -n "$_pfx" ] || continue
    _cap="$_sit"; [ -z "$_cap" ] && _cap="$T_SITES"
    _n=$(_mut count "$_name" "$SEED" 0 "$_arg" 2>/dev/null)
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    if [ "$_n" -eq 0 ]; then
      printf '    %-20s no-site — %s\n' "$_name" "$(_nosite_reason "$_name")"
      continue
    fi
    _use="$_n"; [ "$_n" -gt "$_cap" ] && _use="$_cap"
    _j=1
    while [ "$_j" -le "$_use" ]; do
      printf '    %-10s %-20s %s\n' "$_pfx-$_j" "$_name" "$(_mut desc "$_name" "$SEED" "$_j" "$_arg" 2>/dev/null)"
      _j=$((_j + 1))
    done
    [ "$_n" -gt "$_use" ] && printf '      capped from %s sites (%s)\n' "$_n" "$_name"
  done < "$P/mutators"
  printf '\n  DECLARED\n'
  while IFS="$SEP" read -r _pi _pr _pw; do
    [ -n "$_pi" ] || continue
    printf '    %-10s %s\n' "$_pi" "$_pw"
  done < "$P/plants"
  printf '\n  CONTROLS\n'
  while IFS="$SEP" read -r _ci _ct _cv _cvar _cwhy; do
    [ -n "$_ci" ] || continue
    printf '    %-10s %-5s varies=%-10s %s\n' "$_ci" "$_ct" "$_cvar" "$_cwhy"
  done < "$P/controls"
  printf '\n  UNPROVEN\n'
  while IFS="$SEP" read -r _mi _md; do
    [ -n "$_mi" ] || continue
    printf '    %-10s %s\n' "$_mi" "$_md"
  done < "$P/manuals"
  exit 0
}

# The checkers the census counts: bin/ and tests/<area>/ suites (harbor#742: the suites moved to tests/
# kept their count only once this looked there), and every skill's check-*.sh.
_cov_checkers() {
  { find "$ROOT/bin" -maxdepth 1 -name '*-test.sh' -type f 2>/dev/null
    find "$ROOT/tests" -mindepth 2 -maxdepth 2 -name '*-test.sh' -type f 2>/dev/null
    find "$ROOT/tests" -mindepth 3 -maxdepth 3 -name '*.test.sh' -type f 2>/dev/null   # tests/<family>/<subject>/<aspect>.test.sh
    find "$ROOT/skills" -type f -name 'check-*.sh' 2>/dev/null; } | LC_ALL=C sort
}

# A CENSUS, NOT A SCORE. There is no percentage here and there must never be
# one: a coverage figure on a dashboard is the shape this whole engine exists to
# argue against, and a checker with a target is not thereby a checker that
# discriminates — only a run says that.
mode_coverage() {
  _cov="$WORKROOT/cov"; mkdir -p "$_cov"
  : > "$_cov/decls"
  while IFS= read -r _tf; do
    [ -n "$_tf" ] || continue
    _nm=$(basename "$_tf" .target)
    awk -v n="$_nm" '$1 == "checker-cmd" || $1 == "seed" { sub(/^[^[:space:]]*[[:space:]]*/, ""); print n "\034" $0 }' "$_tf" >> "$_cov/decls"
  done <<COV
$(_all_targets)
COV
  _tot=0; _have=0
  _cov_checkers | while IFS= read -r _ck; do
    [ -n "$_ck" ] || continue
    _rel="${_ck#$ROOT/}"
    # EVERY target, not the first one found. Three targets point at
    # check-topology.sh — bare, --all and --pack platform — and `exit` after the
    # first reported whichever sorted last, so a census whose entire job is
    # saying what is and is not covered under-reported its own coverage.
    _own=$(awk -F"$SEP" -v p="$_rel" 'index($2, p) { print $1 }' "$_cov/decls" \
           | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ $//' -e 's/ /, /g')
    if [ -n "$_own" ]; then printf '%-56s target: %s\n' "$_rel" "$_own"
    else printf '%-56s target: none\n' "$_rel"; fi
  done
  _tot=$(_cov_checkers | awk 'END{print NR+0}')
  _have=$(_cov_checkers | while IFS= read -r _ck; do
            _rel="${_ck#$ROOT/}"
            awk -F"$SEP" -v p="$_rel" 'index($2, p) { f = 1 } END { exit !f }' "$_cov/decls" && printf 'x\n'
          done | awk 'END{print NR+0}')
  printf '\n%s of %s checkers have a prove target\n' "$_have" "$_tot"
  exit 0
}

# ============================================================== SELF-TEST
# THE PORTABLE SELF-PROOF (contracts/gates.md property 3). Sections A and B of
# the build spec: the null-checker falsifier pair, and the vacuity guards. It
# builds its OWN fixtures in a mktemp dir and reads nothing from this repo, so
# the skill can be installed anywhere and still go red before anyone trusts it
# green.
#
# ITS FIXTURES ARE DELIBERATELY NOT THE SUITE'S. tests/skill/prove/prove.test.sh carries the
# pinned `demo` fixture and the byte-exact report sample; if this engine shipped
# a copy of that file the two implementations could drift into agreement by
# sharing it, which is the one thing a two-implementer split exists to prevent.
self_test() {
  pass=0; fail=0
  D=$(mktemp -d "${TMPDIR:-/tmp}/prove-self.XXXXXX")
  SELF="$0"
  mkdir -p "$D/targets/base"
  cat > "$D/targets/base/seed.md" <<'SD'
# SELFTEST

## Uno
| k | v |
|---|---|
| a | 1 |

## Dos
Body.
SD
  cat > "$D/targets/base/ctl.md" <<'CT'
# SELFTEST

## Uno
A lawful section carrying a diacritic (ž) and an escaped pipe `A \| B` and no table.

## Dos
Body.
CT
  cat > "$D/targets/base/check.sh" <<'CK'
#!/usr/bin/env sh
set -u
/usr/bin/grep -q '^## Uno$' "$1" || exit 1
/usr/bin/grep -q '^## Dos$' "$1" || exit 1
exit 0
CK
  cat > "$D/targets/base/over.sh" <<'OV'
#!/usr/bin/env sh
set -u
/usr/bin/grep -q '^## Uno$' "$1" || exit 1
/usr/bin/grep -q '^## Dos$' "$1" || exit 1
/usr/bin/grep -qF '| a | 1 |' "$1" || exit 1
exit 0
OV
  cat > "$D/targets/base/green.sh" <<'GR'
#!/usr/bin/env sh
exit 0
GR
  # GREEN ON THE SEED, 9 ON EVERYTHING ELSE. A checker that exits 9 on its own
  # seed would be caught by the baseline rule instead, which is a different
  # assertion; this one has to crash MID-SWEEP for the case to mean what it says.
  # RED ON THE CANARY, 9 ON ONE MUTANT, GREEN ON EVERYTHING ELSE. It has to
  # refuse the empty canary and accept the control, or the run aborts before the
  # sweep and the case would be asserting the baseline rule again instead.
  cat > "$D/targets/base/crash.sh" <<'CR'
#!/usr/bin/env sh
set -u
[ -s "$1" ] || exit 1
/usr/bin/grep -q "^## Uno$" "$1" || exit 9
exit 0
CR
  # WEAK, NOT NULL, AND THE DIFFERENCE IS THE WHOLE POINT. green.sh cannot fail
  # at all, so it dies on the canary and never reaches a sweep; this one refuses
  # exactly one thing — an empty subject — so the canary is killed, the control
  # is green, and every real mutant SURVIVES. It is the only fixture here that
  # reaches a survivor verdict, and until 2026-08-30 no case asserted one.
  cat > "$D/targets/base/weak.sh" <<'WK'
#!/usr/bin/env sh
set -u
[ -s "$1" ] || exit 1
exit 0
WK
  # A ONE-SECTION SUBJECT AND A CHECKER THAT ONLY WANTS THAT SECTION. Deleting
  # the only section empties the file, which is what B16 is about.
  printf '## Uno\n\nOnly section.\n' > "$D/targets/base/one.md"
  printf '## Uno\n\nA differently worded only section.\n' > "$D/targets/base/onectl.md"
  cat > "$D/targets/base/oneck.sh" <<'ON'
#!/usr/bin/env sh
set -u
/usr/bin/grep -q '^## Uno$' "$1" || exit 1
exit 0
ON
  # A CONTROL THAT VARIES BY A HEADING ALONE, AND ITS FALSIFIER PAIR. check.sh
  # accepts this file at exit 0, so refusing it would be a false positive — B19.
  # The posix-shell fixture below is the other half: there a `#` line IS a
  # comment, and a control that varies only in comments must STAY refused (B20).
  # Without both, "discount nothing anywhere" would pass as a fix.
  { cat "$D/targets/base/seed.md"; printf '\n## Tres (optional; this pack has none)\n'; } > "$D/targets/base/hdg.md"
  cat > "$D/targets/base/s.sh" <<'SS'
#!/usr/bin/env sh
set -u
[ "$#" -ge 1 ] || exit 1
printf 'ok\n'
SS
  # THE COMMENT GOES AFTER THE SHEBANG, AND THE PLACEMENT IS THE POINT. Prepending
  # it put a non-`#!` line first, which for a shebang gate is a REAL difference,
  # not a comment-only one — so the old fixture was asserting something other than
  # its own name, and it only passed because the filter discounted shebangs too.
  awk 'NR == 1 { print; print "# an added comment"; next } { print }' \
    "$D/targets/base/s.sh" > "$D/targets/base/sctl.sh"
  cat > "$D/targets/base/shck.sh" <<'SC'
#!/usr/bin/env sh
set -u
/usr/bin/grep -q '^set -u$' "$1" || exit 1
exit 0
SC

  _mk() { # _mk <name> <checker-script> [extra lines...]
    _n="$1"; _c="$2"; shift 2
    cat > "$D/targets/$_n.target" <<TT
target        $_n
subject-kind  markdown-contract
lane          fast
cost          1
seed          base/seed.md
place         \$WORK/doc.md
checker-cmd   sh \$TDIR/base/$_c \$WORK/doc.md
green         0
red           1
mutate  SEC   section-delete
control C-ODD file base/ctl.md
        varies: lexical
        why:    a lawful section with no table at all
TT
    for _x in "$@"; do printf '%s\n' "$_x" >> "$D/targets/$_n.target"; done
  }

  # HARBOR_SCOPE_ROOT POINTS AT THE FIXTURE DIR, NOT THE REPO. Two reasons, and both
  # are load-bearing. It makes this loop genuinely portable — the child runs
  # never read the repo, so the skill self-proves wherever it is installed. And
  # it aims the read-only tripwire at the fixture tree: pointed at the repo, a
  # second agent saving a file mid-run turns every case exit 4, so the self-test
  # would report the box rather than the engine.
  _case() { # _case <want-exit> <label> <grep-or-empty> <args...>
    _want="$1"; _lab="$2"; _need="$3"; shift 3
    _out=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" sh "$SELF" "$@" 2>&1); _got=$?
    _ok=1
    [ "$_got" = "$_want" ] || _ok=0
    if [ -n "$_need" ]; then printf '%s\n' "$_out" | /usr/bin/grep -q "$_need" || _ok=0; fi
    if [ "$_ok" = 1 ]; then
      printf '  PASS  %s\n' "$_lab"; pass=$((pass + 1))
    else
      printf '  FAIL  %s (exit %s, wanted %s)\n' "$_lab" "$_got" "$_want"; fail=$((fail + 1))
    fi
  }

  printf 'self-test A: the null-checker falsifier pair\n'
  _mk always-green green.sh
  _case 4 'A1 a checker that cannot fail is COULD-NOT-LOOK, never PROVEN' 'CANARY     SURVIVED' always-green
  _mk overbroad over.sh
  _case 3 'A2 an over-broad rule is CONTROL-RED' 'CONTROLS   0/1 green' overbroad
  _out=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" sh "$SELF" overbroad 2>&1)
  if printf '%s\n' "$_out" | /usr/bin/grep -q '^  GENERATED'; then
    printf '  FAIL  A2 a recall figure exists beside a broken guard\n'; fail=$((fail + 1))
  else
    printf '  PASS  A2 no recall figure exists beside a broken guard\n'; pass=$((pass + 1))
  fi
  _mk good check.sh
  _case 0 'A0 the discriminating checker is PROVEN' 'VERDICT    PROVEN' good

  printf 'self-test B: the vacuity guards\n'
  # NAMED `noctl`, NOT `nocontrol`, AND ANCHORED. A `grep -v control` over the
  # declaration also eats the line `target nocontrol`, and the run then refuses
  # for a missing `target` directive — a green-looking pass on the wrong rule.
  _mk noctl check.sh
  sed -e '/^control /d' -e '/varies:/d' -e '/why:/d' "$D/targets/noctl.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/noctl.target"
  _case 5 'B1 zero controls is REFUSED' 'no control declared' noctl

  cp "$D/targets/base/seed.md" "$D/targets/base/copy.md"
  _mk ctlcopy check.sh
  sed 's|base/ctl.md|base/copy.md|' "$D/targets/ctlcopy.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/ctlcopy.target"
  _case 5 'B2 a control copied from the seed is REFUSED' 'asserts nothing' ctlcopy

  { cat "$D/targets/base/seed.md"; printf '\n<!-- a comment -->\n'; } > "$D/targets/base/cmt.md"
  cp "$D/targets/base/seed.md" "$D/targets/base/blank.md"
  printf '\n\n' >> "$D/targets/base/blank.md"
  _mk ctlblank check.sh
  sed 's|base/ctl.md|base/blank.md|' "$D/targets/ctlblank.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/ctlblank.target"
  # B3 WAS INVERTED ON 2026-08-31, AND THE OLD ASSERTION WAS THE DEFECT. It
  # demanded that a markdown control differing only in blank lines be REFUSED.
  # But whitespace is load-bearing for real gates on this box —
  # `skills/casefile/bin/check-pack.sh` makes a blank line TERMINATE a markdown
  # table — so for that gate class the blank-line control is the most natural
  # control there is, and the rule refused it at exit 5 while blaming the author.
  # A false positive is a defect (§2.11), and check 2 is the one check nothing
  # else can recover. B2 above still holds the line that actually matters: a
  # control BYTE-IDENTICAL to the seed is refused, which is the copied-file
  # failure that was ever actually observed.
  _case 0 'B3 a markdown control varying only by blank lines is ACCEPTED, not refused' 'VERDICT    PROVEN' ctlblank

  _mk ctlcmd check.sh
  sed 's|control C-ODD file base/ctl.md|control C-ODD cmd true|' "$D/targets/ctlcmd.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/ctlcmd.target"
  _case 5 'B4 a cmd control that never names the subject is REFUSED' 'does not exercise the subject' ctlcmd

  _mk noop check.sh 'plant NOOP-1 sed -e "s/NOTHING-MATCHES-HERE/x/" "$SEED" > "$MUTANT"' '        why:    a recipe that matches nothing'
  _case 4 'B5 an inert planting is COULD-NOT-LOOK, never a free kill' '1 inert' noop

  _mk basered over.sh
  sed 's|base/seed.md|base/ctl.md|' "$D/targets/basered.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/basered.target"
  sed 's|control C-ODD file base/ctl.md|control C-ODD file base/seed.md|' "$D/targets/basered.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/basered.target"
  _case 4 'B6 a checker that rejects its own seed is COULD-NOT-LOOK' 'BASELINE   RED' basered

  _mk badmut check.sh
  sed 's|mutate  SEC   section-delete|mutate  SEC   no-such-mutator|' "$D/targets/badmut.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/badmut.target"
  _case 5 'B7a an unknown mutator name is REFUSED' 'unknown mutator' badmut
  _mk baddir check.sh 'wibble something'
  _case 5 'B7b an unknown directive is REFUSED' 'unknown directive' baddir
  _mk badkey check.sh 'manual M-1 a thing' '        wobble: nope'
  _case 5 'B7c an unknown continuation key is REFUSED' 'unknown continuation key' badkey

  mkdir -p "$D/empty"
  _out=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/empty" sh "$SELF" --all 2>&1); _got=$?
  if [ "$_got" = 5 ]; then printf '  PASS  B8 --all over an empty target dir is REFUSED\n'; pass=$((pass + 1))
  else printf '  FAIL  B8 --all over an empty target dir (exit %s, wanted 5)\n' "$_got"; fail=$((fail + 1)); fi

  _mk nosite check.sh
  sed 's|mutate  SEC   section-delete|mutate  ANCH  anchor-break|' "$D/targets/nosite.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/nosite.target"
  _case 4 'B9 a target whose only mutator has no sites applies nothing' 'zero mutants applied' nosite

  _mk crashy crash.sh
  _case 4 'B10 a checker exit that is neither green nor red is COULD-NOT-LOOK' 'neither green' crashy

  # B12 AND B13 EXIST BECAUSE prove-engine FOUND THEM MISSING. Mutating
  # `die_usage`'s `exit 2` to `exit 0`, and deleting its printf, both survived
  # the whole self-test on 2026-08-30 — nothing here asserted that a bad command
  # line is refused at all. Usage is the most-hit path in any tool and it had no
  # case.
  _case 2 'B12 an unknown flag is a usage error, and says so' 'unknown flag' --no-such-flag
  _case 2 'B13 a selector that matches no target is a usage error' 'matches nothing' no-such-target

  # ITS OWN DIRECTORY. --lane takes the max() over every target it selects, and
  # by this point the shared fixture dir holds a dozen deliberately-REFUSED
  # declarations whose 5 would mask the 4 this case is about.
  mkdir -p "$D/budget"
  cp "$D/targets/good.target" "$D/budget/good.target"
  ln -s "$D/targets/base" "$D/budget/base" 2>/dev/null || cp -R "$D/targets/base" "$D/budget/base"
  # B14 EXISTS BECAUSE IT HAPPENED. A prove-engine mutant put this engine into an
  # infinite awk loop on 2026-08-30 and the sweep ran twenty minutes with no
  # output; there is no `timeout` on this box to have caught it.
  cat > "$D/targets/base/hang.sh" <<'HG'
#!/usr/bin/env sh
[ -s "$1" ] || exit 1
/usr/bin/grep -q "^## Uno$" "$1" || { printf '%s\n' "$$" >> "${0%/*}/hang.pids"; while :; do sleep 1; done; }
exit 0
HG
  _mk hangs hang.sh
  _out=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" PROVE_RUN_TIMEOUT=2 sh "$SELF" hangs 2>&1); _got=$?
  if [ "$_got" = 4 ] && printf '%s\n' "$_out" | /usr/bin/grep -q 'PROVE_RUN_TIMEOUT'; then
    printf '  PASS  B14 a checker that never returns is killed and reported COULD-NOT-LOOK\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B14 hanging checker (exit %s, wanted 4)\n' "$_got"; fail=$((fail + 1))
  fi
  # harbor#743: the kill left hang.sh running on PID 1 for hours. A pid still
  # answering after a 2s settle (a zombie answers kill -0 until reaped) survived.
  _hp="$D/targets/base/hang.pids"; _left=x; _hn=0
  while [ -n "$_left" ] && [ "$_hn" -lt $((2 * _NAPS)) ]; do
    _left=""
    for _p in $(cat "$_hp" 2>/dev/null); do kill -0 "$_p" 2>/dev/null && _left="$_left $_p"; done
    [ -z "$_left" ] || sleep "$_NAP"; _hn=$((_hn + 1))
  done
  if [ -s "$_hp" ] && [ -z "$_left" ]; then
    printf '  PASS  B14b the timeout kills the hanging checker, not only the subshell around it\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B14b hanging checker left running:%s\n' "${_left:- none recorded, so the hang never ran}"; fail=$((fail + 1))
    for _p in $_left; do kill -9 "$_p" 2>/dev/null; done
  fi

  _mkbudget=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/budget" PROVE_BUDGET=1 sh "$SELF" --lane fast 2>&1); _got=$?
  if [ "$_got" = 4 ] && printf '%s\n' "$_mkbudget" | /usr/bin/grep -q 'NOT RUN  over budget'; then
    printf '  PASS  B11 a target over PROVE_BUDGET is NOT RUN and never reads as fine\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B11 over-budget target (exit %s, wanted 4)\n' "$_got"; fail=$((fail + 1))
  fi

  # B15-B20 EXIST BECAUSE EACH ONE SHIPPED BROKEN. Every case below was
  # measured failing against this engine on 2026-08-30 and is here as the
  # falsifier for the fix that follows it, not as decoration.
  _mk emptyplant check.sh 'plant EMP-1 /usr/bin/grep "NOTHING MATCHES THIS" "$SEED" > "$MUTANT"' '        why:    a recipe that silently writes nothing must never be scored as a kill'
  _case 4 'B15 a plant whose recipe writes nothing is COULD-NOT-LOOK, never a kill' 'produced no mutant' emptyplant

  _mk emptygen oneck.sh
  sed -e 's|base/seed.md|base/one.md|' -e 's|base/ctl.md|base/onectl.md|' "$D/targets/emptygen.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/emptygen.target"
  _case 4 'B16 a mutator that empties the subject is COULD-NOT-LOOK, never a kill' 'empty mutant' emptygen

  _mk plantnowhy check.sh 'plant PNW-1 sed -e "s/## Dos/## Deux/" "$SEED" > "$MUTANT"'
  _case 5 'B17 a plant with no why: is REFUSED, as the contract and lint C6 both say' 'has no why' plantnowhy

  _mk stageout check.sh 'stage mkdir /tmp/prove-selftest-outside-the-workspace'
  _case 5 'B18 a stage destination outside the workspace is REFUSED, not COULD-NOT-LOOK' 'outside the workspace' stageout

  _mk ctlhdg check.sh
  sed 's|base/ctl.md|base/hdg.md|' "$D/targets/ctlhdg.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/ctlhdg.target"
  _case 0 'B19 a markdown control varying by a heading alone is ACCEPTED, not refused' 'VERDICT    PROVEN' ctlhdg

  cat > "$D/targets/shctl.target" <<'ST'
target        shctl
subject-kind  posix-shell
lane          fast
cost          1
seed          base/s.sh
place         $WORK/s.sh
checker-cmd   sh $TDIR/base/shck.sh $WORK/s.sh
green         0
red           1
mutate  GRD   guard-clause-delete
control C-CMT file base/sctl.sh
        varies: comments
        why:    a comment-only variant of a shell script asserts nothing
ST
  _case 5 'B20 a posix-shell control differing only in comments is still REFUSED' 'asserts nothing' shctl

  # B21 NEEDS TWO TARGETS AND ONE RUN, because the defect it guards is a LEAK
  # between them: --require-scanners was initialised once per process, so a
  # target declaring no scanner at all read COULD-NOT-LOOK — with its whole
  # GENERATED block deleted from the report — merely for running after one whose
  # scanner is absent. A single-target case cannot see it.
  mkdir -p "$D/scan"
  ln -s "$D/targets/base" "$D/scan/base" 2>/dev/null || cp -R "$D/targets/base" "$D/scan/base"
  sed 's/^target        good$/target        a-scan/' "$D/targets/good.target" > "$D/scan/a-scan.target"
  printf 'scanner prove-absent-scanner prove-absent-scanner --run\n' >> "$D/scan/a-scan.target"
  sed 's/^target        good$/target        b-clean/' "$D/targets/good.target" > "$D/scan/b-clean.target"
  _out=$(HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/scan" sh "$SELF" --all --require-scanners 2>&1); _got=$?
  if [ "$_got" = 4 ] && printf '%s\n' "$_out" | /usr/bin/grep -q 'b-clean.*PROVEN'; then
    printf '  PASS  B21 --require-scanners does not leak an absent scanner onto the next target\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B21 --require-scanners leaked onto a target that declares none (exit %s, wanted 4 AND b-clean PROVEN)\n' "$_got"; fail=$((fail + 1))
  fi

  # B22/B23 SHIM THE HASHER, because its absence was SILENT. With shasum broken
  # the manifest was 0 bytes before AND after, and two empty files compare
  # equal, so the read-only tripwire never fired and printed nothing — a zero
  # that means "looked at nothing" reading exactly like "clean". The probe
  # points PROVE_WORK INSIDE the fixture root so the tripwire MUST fire: a case
  # that only checked the run still exits 0 would pass with no manifest at all.
  mkdir -p "$D/shim-sha" "$D/shim-both" "$D/skills/w"
  printf 'x\n' > "$D/skills/dummy.txt"
  printf '#!/bin/sh\nexit 127\n' > "$D/shim-sha/shasum";  chmod +x "$D/shim-sha/shasum"
  printf '#!/bin/sh\nexit 127\n' > "$D/shim-both/shasum"; chmod +x "$D/shim-both/shasum"
  printf '#!/bin/sh\nexit 127\n' > "$D/shim-both/cksum";  chmod +x "$D/shim-both/cksum"
  _out=$(PATH="$D/shim-sha:$PATH" HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" PROVE_WORK="$D/skills/w" sh "$SELF" good 2>&1); _got=$?
  if [ "$_got" = 4 ] && printf '%s\n' "$_out" | /usr/bin/grep -q 'TRIPWIRE'; then
    printf '  PASS  B22 with shasum absent the tripwire still fires, on cksum\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B22 tripwire went silent without shasum (exit %s, wanted 4)\n' "$_got"; fail=$((fail + 1))
  fi
  _out=$(PATH="$D/shim-both:$PATH" HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" sh "$SELF" good 2>&1); _got=$?
  if [ "$_got" = 4 ] && printf '%s\n' "$_out" | /usr/bin/grep -q 'needs shasum or cksum'; then
    printf '  PASS  B23 with no hasher at all the run REFUSES rather than comparing two nothings\n'; pass=$((pass + 1))
  else
    printf '  FAIL  B23 no hasher available (exit %s, wanted 4)\n' "$_got"; fail=$((fail + 1))
  fi

  # B24 MAKES THE CONTROL VANISH RATHER THAN chmod 000 IT, and the reason is
  # that root can read a 000 file: a permissions fixture passes for an ordinary
  # user and silently stops testing anything in a container that runs as root.
  # A cmd control that deletes the next control's file is deterministic on every
  # uid. What it exercises is the real path — the cp of a control that cannot be
  # placed — which used to be unchecked, leaving the SEED sitting at $PLACE from
  # the line above and scoring the BASELINE as the control: measured, `CONTROLS
  # 1/1 green` and `VERDICT PROVEN exit 0` over a control never exercised.
  cp "$D/targets/base/ctl.md" "$D/targets/base/vanish.md"
  _mk ctlgone check.sh \
    'control C-RM cmd rm -f "$TDIR/base/vanish.md"; [ -f "$SUBJECT" ]' \
    '        varies: nothing about the subject; it removes the next control'"'"'s file' \
    '        why:    sets up B24 by making the control below unreadable at run time' \
    'control C-GONE file base/vanish.md' \
    '        varies: lexical' \
    '        why:    a control that cannot be placed was never exercised'
  _case 4 'B24 a control that cannot be placed is COULD-NOT-LOOK, never green' 'could not be placed' ctlgone

  # B25-B29 PIN THE 2026-08-31 REPAIRS, and they exist because a check found the
  # repairs themselves unpinned. Five fixes were made, verified by hand, and
  # left with no assertion anywhere — a fix with no falsifier regresses in
  # silence, which is the exact defect this engine was built to find. It was
  # sitting in the repair set. §2.10 does not exempt the repairer.

  # B25 · ONE MISTYPED DIGIT MADE EVERY GUARD PASS AT ONCE. Every verdict here
  # is a comparison against red, so green == red asks a question whose two
  # answers have been made equal: measured with a checker that is only `exit 0`,
  # the report read CANARY KILLED, CONTROLS 1/1 green, 5/5 killed, PROVEN exit 0.
  # A1 above holds the other side — with a distinct red, that same null checker
  # is caught by the canary.
  _mk samecode check.sh
  sed 's/^red           1$/red           0/' "$D/targets/samecode.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/samecode.target"
  _case 5 'B25 green and red naming the same exit code is REFUSED' 'green and red are both' samecode

  # B26 · POSIX awk expands escape sequences in a -v assignment, so an ordinary
  # English `why:` mentioning a backslash became a REAL newline inside the
  # \034-delimited control record and split one row into two. The target was
  # refused naming a control the author never wrote. --explain stops at the
  # parse, which is where the defect lived.
  printf '## Uno\n\nA second lawful variant.\n\n## Dos\n\n| a | b |\n| - | - |\n| 1 | 2 |\n' \
    > "$D/targets/base/ctl2.md"
  _mk bslash check.sh \
    'control C-BS file base/ctl2.md' \
    '        varies: lexical' \
    '        why:    the file must keep its trailing \n after the last section, and the \| inside a cell'
  _case 0 'B26 a backslash inside why: prose does not split the control row' '' --explain bslash

  # B27 · A `#!` LINE IS AN INTERPRETER DIRECTIVE, NOT A COMMENT. bin/lint-
  # conventions.sh rule S1 IS a shebang gate, and discounting every `#` refused
  # the one control that could prove its waiver arm works. B20 holds the other
  # side: a genuinely comment-only variant is still refused.
  sed '1s|.*|#!/bin/sh|' "$D/targets/base/s.sh" > "$D/targets/base/sctl2.sh"
  sed -e 's|^target        shctl$|target        shbang|' -e 's|base/sctl.sh|base/sctl2.sh|' \
    "$D/targets/shctl.target" > "$D/targets/shbang.target"
  _case 0 'B27 a posix-shell control varying only by its shebang is ACCEPTED' '' --explain shbang

  # B28 · THE CONTINUATION WAS READ WHERE ONLY THE GLOBAL WAS VALIDATED, so
  # `sites: eight` reached the arithmetic as a word: `[: eight: integer
  # expression expected` on stderr, the cap silently not binding, and the report
  # still printing `0 capped`. A cap that does not bind while claiming it did
  # understates the surface that was searched.
  # The continuation must sit directly under its `mutate`, so it cannot be
  # appended by _mk — extras land at the end of the file, where this line would
  # bind to the CONTROL instead and the arm would go red for the wrong reason.
  _mk badsites check.sh
  awk '{ print; if ($1 == "mutate") print "        sites: eight" }' \
    "$D/targets/badsites.target" > "$D/t.tmp"
  mv "$D/t.tmp" "$D/targets/badsites.target"
  _case 5 'B28 a per-mutator sites continuation that is not an integer is REFUSED' 'sites must be an integer' badsites

  # B29 · 127 IS A TYPO, NOT A REFUSAL — the same distinction the file-control
  # branch was repaired to make. Scoring a command that was never found as
  # CONTROL-RED points the next reader at the checker and invites loosening a
  # rule that is fine.
  _mk ctl127 check.sh \
    'control C-127 cmd prove-selftest-no-such-command "$SUBJECT"' \
    '        varies: nothing about the subject; it exercises the not-found path' \
    '        why:    a control command that was never found did not measure the gate'
  _case 4 'B29 a cmd control whose command is not found is COULD-NOT-LOOK' 'exited 127' ctl127

  # B30 CAME OUT OF CHECKING B26 AND IS KEPT BECAUSE THE CHECK FOUND A HOLE. A
  # stand-in mutation that made _sed_col write one constant into every `varies:`
  # and `why:` column passed the whole suite: nothing asserted their CONTENT,
  # only that they were non-empty. Those two strings are the entire human-
  # readable justification a control carries — the engine's own header says no
  # machine can assert they are TRUE, which is exactly why it must assert they
  # are the author's words and not the engine's.
  _case 0 'B30 a control varies: and why: reach the report verbatim' 'a lawful section with no table at all' good

  printf 'self-test C: the failure verdicts, and the words they are printed in\n'
  # A FAILURE VERDICT HAD NO CASE AT ALL. Until 2026-08-30 the only case that
  # grepped a VERDICT token asserted the SUCCESS one, so `s/SURVIVORS/PROVEN/g`
  # and `s/CONTROL-RED/PROVEN/g` each left this self-test at 20 passed, 0 failed
  # while a real run printed PROVEN above 33 listed survivors. The exit code
  # still saved CI; the report is the deliverable, and it was lying.
  _mk weak weak.sh
  _case 1 'C1 a checker that accepts a mutant reports SURVIVORS, exit 1' 'VERDICT    SURVIVORS' weak
  _case 3 'C2 an over-broad rule reports CONTROL-RED, exit 3' 'VERDICT    CONTROL-RED' overbroad
  _case 1 'C3 a survivor is NAMED in the report, not merely counted' 'SURVIVOR  SEC-' weak

  # C8 IS THE ONE FIXTURE WHERE A HAND-WRITTEN PLANT SURVIVES, and until
  # 2026-08-30 no fixture and no shipped target had one: demo/clean/odd all kill
  # their plant, topology reports DECLARED 1/1, floor 0/0. So the `dsurvivors`
  # term in the verdict ladder was asserted NOWHERE — deleting it left the whole
  # suite byte-identically green while turning a surviving plant into PROVEN,
  # exit 0. That is this tool's highest-value output, a violation a human
  # specifically wrote down and the gate missed, silenced.
  # THE CHECKER HAS TO KILL EVERY GENERATED MUTANT for this case to mean what it
  # says: with a generated survivor present the verdict is SURVIVORS either way
  # and the deletion would still pass. check.sh refuses both section deletions
  # and accepts the reworded body, so the DECLARED survivor is the only one.
  _mk plantsurv check.sh 'plant PS-1 sed -e "s/Body/Corpus/" "$SEED" > "$MUTANT"' '        why:    rewording body prose is legitimate here, so this plant is expected to SURVIVE and the run must say so'
  _case 1 'C8 a surviving hand-written plant reaches the verdict, exit 1' 'SURVIVOR  PS-1' plantsurv

  # WHY C4-C7 ASSERT NO LITERAL AT ALL, AND WHAT THEY STILL CANNOT DO.
  # The expected string and the code that prints it live in ONE FILE, so a
  # global rename moves both in lockstep and no literal case can see it —
  # measured: `s/SURVIVORS/PROVEN/g` leaves C1 above green, because it rewrites
  # C1's own expectation too. These four compare one fixture's report against
  # ANOTHER'S instead: three verdicts that must be three DIFFERENT words, and a
  # canary that survived that must not read the same as one that was killed. A
  # global rename collapses two onto one word and turns them red, with no
  # literal anywhere for the sed to move.
  # THE CEILING, STATED SO NOBODY OVERSELLS IT: this pins that the words DIFFER,
  # never WHICH word is which. `s/PROVEN/SURVIVORS/g;s/SURVIVORS/PROVEN/g`-style
  # swaps, and any rename that keeps them distinct, still pass here. Only a file
  # the mutation cannot reach can pin the label contract, which is why
  # tests/skill/prove/prove.test.sh asserts the labels themselves and why prove-engine.target
  # calls this the bootstrap limit. These cases narrow it; they do not close it.
  _report_word() { # $1 = report label, $2 = target -> the word printed after it
    # The exit code is deliberately not the assertion here: these cases are
    # about the WORD, and the exits are already asserted by C1/C2/A0/A1.
    HARBOR_SCOPE_ROOT="$D" PROVE_TARGETS="$D/targets" sh "$SELF" "$2" 2>&1 \
      | awk -v k="$1" '$1 == k { print $2; exit }'
  }
  _differ() { # _differ <label> <a> <b>
    if [ -n "$2" ] && [ -n "$3" ] && [ "$2" != "$3" ]; then
      printf '  PASS  %s\n' "$1"; pass=$((pass + 1))
    else
      printf '  FAIL  %s (%s vs %s)\n' "$1" "${2:-<none>}" "${3:-<none>}"; fail=$((fail + 1))
    fi
  }
  _vg=$(_report_word VERDICT good)
  _vw=$(_report_word VERDICT weak)
  _vc=$(_report_word VERDICT overbroad)
  _differ 'C4 a run with a survivor is not printed in the same word as a clean one' "$_vg" "$_vw"
  _differ 'C5 a broken control is not printed in the same word as a clean run' "$_vg" "$_vc"
  _differ 'C6 a survivor run is not printed in the same word as a broken control' "$_vw" "$_vc"
  _cg=$(_report_word CANARY good)
  _cn=$(_report_word CANARY always-green)
  _differ 'C7 a canary that survived is not printed in the same word as one that was killed' "$_cg" "$_cn"

  rm -rf "$D"
  printf 'prove: %d passed, %d failed\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || return 1
  return 0
}

# ================================================================== DRIVER
SELECTORS=""
MODE=run
LANE=""
EXTFILE=""
SCAN_MISSING=0

[ $# -eq 0 ] && usage
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage ;;
    --all)     MODE=all; BUDGETED=1; shift ;;
    --lane)    shift; LANE="${1:-}"; [ -n "$LANE" ] || die_usage "--lane needs fast or deep"
               case "$LANE" in fast|deep) ;; *) die_usage "unknown lane: $LANE" ;; esac
               MODE=lane; BUDGETED=1; shift ;;
    --file)    shift; EXTFILE="${1:-}"; [ -n "$EXTFILE" ] || die_usage "--file needs a path"; MODE=file; shift ;;
    --only)    shift; ONLY="${1:-}"; [ -n "$ONLY" ] || die_usage "--only needs an ID"; shift ;;
    --list)      MODE=list; shift ;;
    --explain)   MODE=explain; shift ;;
    --mutators)  mutators_table; exit 0 ;;
    --coverage)  MODE=coverage; shift ;;
    --json)      JSON=1; shift ;;
    --keep)      KEEP=1; shift ;;
    --require-scanners) REQUIRE_SCANNERS=1; shift ;;
    --live-triggers) LIVE_TRIGGERS=1; shift ;;
    --self-test) MODE=selftest; shift ;;
    -*)        die_usage "unknown flag: $1" ;;
    *)         SELECTORS="$SELECTORS $1"; shift ;;
  esac
done

WORKROOT="$(mktemp -d "$PROVE_WORK/prove.XXXXXX")" || { printf 'prove: cannot create a workspace under %s\n' "$PROVE_WORK" >&2; exit 4; }

if [ "$MODE" = selftest ]; then
  self_test
  exit $?
fi

if ! _resolve_hasher; then
  printf 'prove: %s  %s\n' COULD-NOT-LOOK \
    'the read-only tripwire needs shasum or cksum and neither runs on this box; refusing rather than comparing two empty manifests'
  exit 4
fi
MANIFEST_BEFORE="$WORKROOT/manifest.before"
_manifest > "$MANIFEST_BEFORE"

case "$MODE" in
  list)     mode_list ;;
  coverage) mode_coverage ;;
esac

# ---- build the target list
LIST="$WORKROOT/targets.list"
: > "$LIST"
case "$MODE" in
  all)
    _all_targets > "$LIST"
    if [ ! -s "$LIST" ]; then
      printf 'prove: --all found no *.target under %s\n' "$PROVE_TARGETS"
      exit 5
    fi ;;
  lane)
    while IFS= read -r _tf; do
      [ -n "$_tf" ] || continue
      awk -v l="$LANE" '$1 == "lane" && $2 == l { f = 1 } END { exit !f }' "$_tf" && printf '%s\n' "$_tf" >> "$LIST"
    done <<LN
$(_all_targets)
LN
    if [ ! -s "$LIST" ]; then
      printf 'prove: no target declares lane %s\n' "$LANE"
      exit 5
    fi ;;
  file)
    case "$EXTFILE" in
      "$ROOT"/*) ;;
      *) [ "$PROVE_ALLOW_EXTERNAL" = 1 ] || die_usage "--file is outside $ROOT; set PROVE_ALLOW_EXTERNAL=1 to run it anyway" ;;
    esac
    [ -f "$EXTFILE" ] || die_usage "--file: no such file: $EXTFILE"
    printf '%s\n' "$EXTFILE" > "$LIST" ;;
  explain)
    _sel=$(_trim "$SELECTORS")
    [ -n "$_sel" ] || die_usage "--explain needs a selector"
    _tf=$(_resolve_selector "$_sel") || die_usage "selector '$_sel' matches ${SEL_CANDIDATES:-nothing}"
    mode_explain "$_tf" ;;
  run)
    _sel=$(_trim "$SELECTORS")
    [ -n "$_sel" ] || die_usage "no selector given (try --all, --list or --help)"
    for _s in $SELECTORS; do
      _tf=$(_resolve_selector "$_s") || die_usage "selector '$_s' matches ${SEL_CANDIDATES:-nothing}"
      printf '%s\n' "$_tf" >> "$LIST"
    done ;;
esac

# A SWEEP DOES NOT SILENTLY BILL THE OPERATOR, AND IT DOES NOT SILENTLY DROP A
# TARGET EITHER. Without --live-triggers a trigger-routing target is removed
# from --all/--lane and NAMED on its way out, so it is visible-and-unrun rather
# than invisible. It is not scored 4 here, because not selecting a target is not
# a failed measurement — asking for one and not getting it is, which is what the
# gate inside run_target does for an explicitly named selector.
if [ "$LIVE_TRIGGERS" != 1 ] && { [ "$MODE" = all ] || [ "$MODE" = lane ]; }; then
  _excl=""
  : > "$LIST.keep"
  while IFS= read -r _tf; do
    [ -n "$_tf" ] || continue
    if awk '$1 == "subject-kind" && $2 == "trigger-routing" { f = 1 } END { exit !f }' "$_tf"; then
      _excl="$_excl $(basename "$_tf" .target)"
    else
      printf '%s\n' "$_tf" >> "$LIST.keep"
    fi
  done < "$LIST"
  mv "$LIST.keep" "$LIST"
  if [ -n "$_excl" ]; then
    printf 'prove: excluded from this sweep —%s (subject-kind trigger-routing: live sessions, real money; add --live-triggers to include)\n\n' "$_excl"
  fi
  if [ ! -s "$LIST" ]; then
    printf 'prove: every selected target is trigger-routing and none was run; add --live-triggers\n'
    exit 4
  fi
fi

NTARGETS=$(awk 'END{print NR+0}' "$LIST")
: > "$WORKROOT/summary"
[ "$JSON" = 1 ] && printf '{ "targets": [\n'
_first_target=1
while IFS= read -r _tf; do
  [ -n "$_tf" ] || continue
  run_target "$_tf"
  if [ "$JSON" = 1 ]; then
    [ "$_first_target" = 1 ] || printf ',\n'
    if [ -n "${T_NAME:-}" ] && [ -n "${VERDICT:-}" ]; then emit_json_target; fi
  else
    [ "$_first_target" = 1 ] || printf '\n'
    if [ -n "${VERDICT:-}" ]; then emit_report; fi
  fi
  _first_target=0
  printf '%s\034%s\034%s\n' "${T_NAME:-$(basename "$_tf" .target)}" "${VERDICT:-REFUSED}" "$TRC" >> "$WORKROOT/summary"
  [ "$TRC" -gt "$GRC" ] && GRC="$TRC"
  VERDICT=""
done < "$LIST"
[ "$JSON" = 1 ] && printf '\n],\n  "exit": %d }\n' "$GRC"

# ---- the repo tripwire, closing the read-only claim
_manifest > "$WORKROOT/manifest.after"
if ! cmp -s "$MANIFEST_BEFORE" "$WORKROOT/manifest.after"; then
  _delta=$(diff "$MANIFEST_BEFORE" "$WORKROOT/manifest.after" 2>/dev/null | awk '/^[<>]/ { print $NF; exit }')
  printf 'prove: TRIPWIRE  repo modified during run: %s\n' "${_delta:-unknown}"
  [ 4 -gt "$GRC" ] && GRC=4
fi

if [ "$NTARGETS" -gt 1 ] && [ "$JSON" = 0 ]; then
  printf '\n=== prove: %d targets ===\n' "$NTARGETS"
  while IFS="$SEP" read -r _n _v _e; do
    [ -n "$_n" ] || continue
    printf '  %-12s %-16s exit %d\n' "$_n" "$_v" "$_e"
  done < "$WORKROOT/summary"
  printf '  EXIT %d\n' "$GRC"
fi

[ "$KEEP" = 1 ] && printf 'prove: workspace kept at %s\n' "$WORKROOT"
exit "$GRC"
