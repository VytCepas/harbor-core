#!/usr/bin/env sh
# DOCS — generate docs/index.html, the architecture document (harbor#173).
# G1: deliberately one file. A generator split across modules is a generator
# whose output depends on which half you edited last; the whole point is that one
# command reproduces the page byte for byte.
#
# WHY A GENERATOR AND NOT A HAND-WRITTEN PAGE. The same argument STATUS.md is
# built on, applied to prose: a list of lint rules, CLI verbs, rule packs or CI
# jobs written into a document is a COPY of a fact that lives in a script, and
# copies drift while reading perfectly. A 2026-07-26 sweep found three documents
# each stating a different count of the same thing, none of them wrong when
# written. So this page derives every inventory from the repo at generation time
# and the prose around them is hand-authored, which is the split that lets the
# document be improved continuously without rotting:
#
#   docs/src/*.html   the ARGUMENT — hand-edited, this is where you write
#   <!--gen:NAME-->   a hole the generator fills from the repo
#   docs/index.html   BUILT, NOT COMMITTED (harbor#1197) — gitignored, overwritten by --apply
#
#   sh bin/docs-gen.sh            # print the page to stdout
#   sh bin/docs-gen.sh --apply    # build docs/index.html (~14 s), then `open docs/index.html`
#   sh bin/docs-gen.sh --check    # exit 1 if the page cannot be built or has an unknown hole (builds to a temp file)
#   sh bin/docs-gen.sh --tokens   # list every hole and whether it is filled
#
# ADDING A SECTION is one file: docs/src/NN-name.html, with an <h2 id="...">.
# The rail on the left is built from those headings, so nothing needs registering.
#
# ADDING A DERIVED TABLE is one function named `d_NAME` plus `<!--gen:NAME-->` in
# the prose. An unknown token is a build failure rather than an empty space —
# a hole that silently renders as nothing is how a document loses a section
# without anyone noticing.
set -eu

# --help BEFORE ANY WORK (S4, harbor#140). Placed immediately after strict mode
# so it is the first executable line: a --help that reaches an argument parser is
# a --help that a script with no parser ignores, and this file had none. Measured
# 2026-08-20: a sweep of `bin/*.sh --help` ran past five minutes because at least
# one script treated the flag as a request to do work, and five of the scripts
# with no --help at all are mutators. The text is the header, read out of THIS
# file at runtime, so a help message cannot drift from what the script says it is.
case "${1:-}" in
  -h|--help) awk 'NR<2{next} /^#/{ sub(/^# ?/,""); if ($0=="") exit; print; next } {exit}' "$0"
             printf '\n(flags, if any, are in the header above and the source below.)\n'
             exit 0 ;;
esac
SELF="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(CDPATH='' cd -- "$SELF/.." && pwd)"
# Its stdout is the page (or the token table), so its own lines go to stderr in every mode
# (CONTRACTS/logging.md, harbor#771) — never into a docs/index.html being built.
. "$SELF/log-lib.sh"
LOG_FD=2; log_init docs-gen
. "$SELF/install-lib.sh"  # il_src: a hook engine ships from its folder (D-88)
SRC="$ROOT/docs/src"
OUT="$ROOT/docs/index.html"
LC_ALL=C
export LC_ALL

MODE=print
case "${1:-}" in
  --apply)  MODE=apply ;;
  --check)  MODE=check ;;
  --tokens) MODE=tokens ;;
  '')       MODE=print ;;
  *) printf 'docs-gen: unknown flag %s (--apply|--check|--tokens)\n' "$1" >&2; exit 2 ;;
esac

# ── html escaping ───────────────────────────────────────────────────────────
# Every derived value passes through this. The inputs are repo files rather than
# anything remote, but a description containing `<` or `&` produces a page that
# renders differently from the file it describes, which is the one failure a
# document about truth cannot have.
esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

# THE SOURCE IS A SHELL STRING, AND ITS ESCAPES ARE NOT PART OF THE SENTENCE.
# Rule descriptions live inside double quotes in lint-conventions.sh, so a `$` is
# written `\$` and a backtick `\``. Rendered raw, the page showed
# `\$HOME/.claude` and `\`harbor\`` — a document about drift, displaying text
# that does not match the file it claims to be quoting. Unescape BEFORE escaping
# for HTML; the other order would double-encode the ampersand.
unesc() { sed -e 's/\\\$/$/g' -e 's/\\`/`/g' -e 's/\\"/"/g'; }

# Inline `code` -> <code>. Applied to derived prose only, never to src files,
# which are already HTML and say what they mean.
tick() { sed -e 's|`\([^`]*\)`|<code>\1</code>|g'; }

# The installers write every hook command as an absolute path built from $DIR,
# which is the operator's config directory. Rendering that verbatim would put an
# absolute home path into a page meant to be readable anywhere, and would make
# the useful half of the cell — WHICH SCRIPT — the part you have to scroll to.
_short() { sed -e 's|^/bin/sh \$DIR/bin/||' -e 's|\$DIR/bin/||g'; }

row() { # <cells...> — one table row, each cell already escaped
  printf '<tr>'; for c in "$@"; do printf '<td>%s</td>' "$c"; done; printf '</tr>\n'
}

# ── the derivations ─────────────────────────────────────────────────────────
# Each reads the repo and prints an HTML fragment. NOTHING here states a number
# that it did not just count.

d_verbs() {
  printf '<table class="grid"><thead><tr><th>Verb</th><th>Runs</th><th><code>--json</code></th><th>What it does</th></tr></thead><tbody>\n'
  awk 'f && /^"$/ {exit} f' "$ROOT/bin/harbor" 2>/dev/null | true
  sed -n '/^VERBS="$/,/^"$/p' "$ROOT/bin/harbor" \
    | sed '1d;$d' \
    | while IFS="$(printf '\t')" read -r v s j d; do
        [ -n "${v:-}" ] || continue
        row "<code>harbor $(printf '%s' "$v" | esc)</code>" \
            "<code>$(printf '%s' "$s" | esc)</code>" \
            "$(printf '%s' "$j" | esc)" \
            "$(printf '%s' "$d" | unesc | esc | tick)"
      done
  printf '</tbody></table>\n'
}

d_lint() {
  printf '<table class="grid"><thead><tr><th>Rule</th><th>What fails the build</th></tr></thead><tbody>\n'
  sed -n 's/^rule "\([A-Za-z0-9._-]*\) \(.*\)"$/\1\t\2/p' "$ROOT/bin/lint-conventions.sh" \
    | while IFS="$(printf '\t')" read -r id desc; do
        [ -n "${id:-}" ] || continue
        _cls=''
        case "$desc" in *'(advisory)'*) _cls=' class="advisory"' ;; esac
        # the deprecated letter id it succeeds (harbor#957, D-19): what older docs and issues still cite
        _was="$(sh "$ROOT/bin/lint-conventions.sh" --ids 2>/dev/null | awk -F'\t' -v i="$id" '$1 == i && $2 != "-" { print " (was " $2 ")" }')"
        printf '<tr%s><td><code>%s</code>%s</td><td>%s</td></tr>\n' \
          "$_cls" "$(printf '%s' "$id" | esc)" "$(printf '%s' "$_was" | esc)" "$(printf '%s' "$desc" | unesc | esc | tick)"
      done
  printf '</tbody></table>\n'
}

d_guards() {
  printf '<table class="grid"><thead><tr><th>Guard</th><th>Role</th></tr></thead><tbody>\n'
  for f in "$ROOT"/bin/guard-*.sh "$ROOT"/bin/floor-hook.sh; do
    [ -f "$f" ] || continue
    _n="$(basename "$f")"
    _d="$(sed -n '2,4p' "$f" | sed -n 's/^# //p' | head -1)"
    row "<code>$(printf '%s' "$_n" | esc)</code>" "$(printf '%s' "$_d" | unesc | esc | tick)"
  done
  printf '</tbody></table>\n'
}

# The pack registry, read from the frontmatter the engine itself parses — not
# from a list maintained beside it. A pack added to a directory appears here on
# the next generation with no second edit.
_fm() { awk 'NR==1 && $0 !~ /^---[[:space:]]*$/ { exit }
             NR>1  && $0 ~  /^---[[:space:]]*$/ { exit }
             NR>1' "$1"; }
_fmv() { _fm "$1" | awk -F': *' -v k="$2" '$1==k {sub(/^[^:]*: */,""); print; exit}'; }

d_packs() {
  printf '<table class="grid"><thead><tr><th>Tier</th><th>Pack</th><th>Event</th><th>Fires when</th><th>Repeats</th></tr></thead><tbody>\n'
  # `inject.d/*/*.md` ALREADY COVERS box/ — globbing box/ separately as well is
  # how the first cut listed every box pack twice, which is precisely the
  # duplicate-tier defect the engine itself shipped. One glob per tier.
  for f in "$ROOT"/inject.d/*/*.md "$ROOT"/.claude/inject.d/*.md; do
    [ -f "$f" ] || continue
    _rel="${f#"$ROOT"/}"
    case "$_rel" in inject.d/box/*) _tier='box' ;;
                    .claude/inject.d/*) _tier='repo · harbor' ;;
                    inject.d/*) _tier="repo · $(basename "$(dirname "$f")")" ;; esac
    # A pack may carry SEVERAL `when:` lines (they are ANDed), so the cell needs a
    # line break the escaper must not eat. Joined on a SENTINEL, escaped, then the
    # sentinel becomes the tag. Emitting a literal `<br>` before escaping produced
    # `&lt;br>` in the rendered table — half-escaped, because the escaper rewrites
    # `<` and `>` separately and the un-escape pattern was looking for a string
    # that by then no longer existed.
    _when="$(_fm "$f" | sed -n 's/^when:[[:space:]]*//p' | sed 's/$/@@BR@@/' | tr -d '\n')"
    _when="${_when%@@BR@@}"
    row "$(printf '%s' "$_tier" | esc)" \
        "<code>$(printf '%s' "$(basename "$f")" | esc)</code>" \
        "<code>$(_fmv "$f" event | esc)</code>" \
        "<code>$(printf '%s' "$_when" | esc | sed 's|@@BR@@|<br>|g')</code>" \
        "$(_fmv "$f" once | esc)"
  done
  printf '</tbody></table>\n'
}

d_predicates() {
  printf '<p class="derived">Read from the vocabulary gate in <code>bin/inject-hook.sh</code>: '
  sed -n 's/^    \(always|cmd-prefix.*\)) ;;$/\1/p' "$ROOT/bin/inject-hook.sh" \
    | head -1 | tr '|' '\n' \
    | while read -r p; do [ -n "$p" ] && printf '<code>%s</code> ' "$(printf '%s' "$p" | esc)"; done
  printf '— plus <code>not &lt;predicate&gt;</code>, which inverts any of them.</p>\n'
}

d_events() {
  printf '<table class="grid"><thead><tr><th>Event</th><th>Tools it is wired for</th></tr></thead><tbody>\n'
  sed -n 's/^add \([A-Za-z]*\) *"\([^"]*\)".*/\1\t\2/p' "$ROOT/bin/inject-install.sh" \
    | while IFS="$(printf '\t')" read -r ev m; do
        [ -n "${ev:-}" ] || continue
        case "${m:-}" in '') m='(every occurrence)' ;; esac
        row "<code>$(printf '%s' "$ev" | esc)</code>" "<code>$(printf '%s' "$m" | esc)</code>"
      done
  printf '</tbody></table>\n'
}

d_suites() {
  printf '<table class="grid"><thead><tr><th>Suite</th><th>Runs when these paths change</th></tr></thead><tbody>\n'
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    _s="${line%% *}"
    # `$_s`, NOT `${_s%.sh}`: suite-paths.txt keys on the FULL filename, so
    # stripping the extension made every lookup miss and every row on the
    # published page read `(always)` — all 53 of them, stating the exact opposite
    # of what CI-2 built, in the document whose whole purpose is to derive rather
    # than copy. Found 2026-09-01 while adding a suite and noticing its own
    # declaration had vanished from the page.
    _p="$(grep "^${_s} " "$ROOT/CONTRACTS/suite-paths.txt" 2>/dev/null | head -1)"
    _p="${_p#* }"
    [ -n "$_p" ] || _p='(always)'
    row "<code>$(printf '%s' "$_s" | esc)</code>" "<code>$(printf '%s' "$_p" | esc)</code>"
  done < "$ROOT/CONTRACTS/suites.txt"
  printf '</tbody></table>\n'
}

d_contracts() {
  printf '<table class="grid"><thead><tr><th>Contract</th><th>Freezes</th></tr></thead><tbody>\n'
  for f in "$ROOT"/CONTRACTS/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in README.md) continue ;; esac
    _t="$(sed -n 's/^# *//p' "$f" | head -1)"
    row "<code>CONTRACTS/$(basename "$f" | esc)</code>" "$(printf '%s' "$_t" | unesc | esc | tick)"
  done
  printf '</tbody></table>\n'
}

d_doctrine() {
  printf '<table class="grid"><thead><tr><th>Document</th><th>Argues</th></tr></thead><tbody>\n'
  for f in "$ROOT"/DOCTRINE/*.md; do
    [ -f "$f" ] || continue
    _t="$(sed -n 's/^# *//p' "$f" | head -1)"
    row "<code>DOCTRINE/$(basename "$f" | esc)</code>" "$(printf '%s' "$_t" | unesc | esc | tick)"
  done
  printf '</tbody></table>\n'
}

d_ci() {
  printf '<table class="grid"><thead><tr><th>Job</th><th>Waits for</th></tr></thead><tbody>\n'
  # ONE ROW PER JOB, EMITTED AT THE NEXT JOB HEADER. Keying the row off `needs:`
  # dropped every job that waits for nothing — including the preflight the rest
  # of the graph hangs from, so the doc showed a dependency tree with no root.
  awk '
    # ONLY UNDER `jobs:`. `on:` has two-space keys too, so without this gate the
    # trigger names `push` and `run` were rendered as CI jobs that do not exist.
    /^jobs:/ { injobs=1; next }
    !injobs { next }
    /^  [a-z0-9-]+:$/ {
      if (j != "") { print (n == "" ? j : n) "\t" (d == "" ? "—" : d) }
      j=$1; sub(/:$/,"",j); n=""; d=""; next
    }
    /^    name: /  { n=$0; sub(/^    name: /,"",n) }
    /^    needs: / { d=$0; sub(/^    needs: /,"",d) }
    END { if (j != "") print (n == "" ? j : n) "\t" (d == "" ? "—" : d) }
  ' "$ROOT/.github/workflows/governance.yml" \
    | while IFS="$(printf '\t')" read -r n d; do
        row "$(printf '%s' "$n" | esc)" "<code>$(printf '%s' "$d" | esc)</code>"
      done
  printf '</tbody></table>\n'
}

d_skills() {
  printf '<table class="grid"><thead><tr><th>Skill</th><th>Invocation</th><th>What it is for</th></tr></thead><tbody>\n'
  for f in "$ROOT"/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    _n="$(_fmv "$f" name)"; [ -n "$_n" ] || _n="$(basename "$(dirname "$f")")"
    _d="$(_fmv "$f" description | cut -c1-150)"
    case "$(_fm "$f" | grep -c 'disable-model-invocation: *true' || true)" in
      0) _i='ambient' ;; *) _i='invoked only' ;;
    esac
    row "<code>$(printf '%s' "$_n" | esc)</code>" "$_i" "$(printf '%s' "$_d" | esc)"
  done
  printf '</tbody></table>\n'
}

# THE DISPOSITION MAP, read from skills/UNIFICATION.md's own three lists. Upstream
# names are CamelCase and the directories are kebab-case, so both sides are
# normalised to letters-only-lowercase before comparing — `RootCauseAnalysis` and
# `root-cause-analysis` are the same skill and must not render as two.
_disp_map() {
  awk '
    /^\*\*(CONVERT|REWRITE|HOLD) / { cls=$1; sub(/^\*\*/,"",cls); on=1 }
    /^$/ { on=0 }
    on { s=$0
         while (match(s, /`[A-Za-z]+`/)) {
           n=substr(s, RSTART+1, RLENGTH-2)
           print cls "\t" tolower(n)
           s=substr(s, RSTART+RLENGTH) } }
  ' "$ROOT/skills/UNIFICATION.md"
}

# THE VENDORED TIER, AND WHY IT IS A SEPARATE TABLE FROM d_skills. A tracked skill
# is Harbor's own and is answerable to lint; a vendored one arrived from upstream
# and carries a disposition that is not yet spent. Merging the two into one list
# would render "we wrote this" and "we have not yet judged this" as the same row,
# which is the one distinction the hold banner exists to make.
#
# TWO STATUS COLUMNS, ON PURPOSE, FROM TWO DIFFERENT FILES. `Banner` is read from
# the skill's own body — it is what a session actually sees when it opens the file.
# `Disposition` is read from skills/UNIFICATION.md, which is where the decision was
# taken. They are supposed to agree, and rendering both means a render is the check:
# a skill classed HOLD with no banner is a decision that never reached the file, and
# a banner with no HOLD row is a file nobody has a decision for. Neither is visible
# in a table that states the answer once.
#
# NEITHER COLUMN IS vendor/skills/PROVENANCE.md's `Installed` column. That column is
# typed by hand, has already been measured wrong against the lint rule that derives
# the same answer, and PROVENANCE.md now says in its own words to believe the rule.
d_vendor() {
  _DMAP="$(_disp_map)"
  printf '<table class="grid"><thead><tr><th>Skill</th><th>Banner</th><th>Disposition</th><th>Invocation</th><th>What it is for</th></tr></thead><tbody>\n'
  for f in "$ROOT"/vendor/skills/*/SKILL.md; do
    [ -f "$f" ] || continue
    _dir="$(basename "$(dirname "$f")")"
    _n="$(_fmv "$f" name)"; [ -n "$_n" ] || _n="$_dir"
    # Descriptions here are YAML-quoted where upstream quoted them; the quotes are
    # the file format, not part of the sentence.
    _d="$(_fmv "$f" description | sed -e 's/^"//' -e 's/"$//' | cut -c1-140)"
    _b='—'
    case "$(sed -n '1,30p' "$f" | grep -c 'ON HOLD' || true)" in *[1-9]*) _b='held' ;; esac
    case "$(sed -n '1,30p' "$f" | grep -c 'harbor: DORMANT' || true)" in *[1-9]*) _b='dormant' ;; esac
    _key="$(printf '%s' "$_dir" | tr -d '-' | tr 'A-Z' 'a-z')"
    _c="$(printf '%s' "$_DMAP" | awk -F'\t' -v k="$_key" '$2==k{print $1; exit}')"
    [ -n "$_c" ] || _c='—'
    case "$(_fm "$f" | grep -c 'disable-model-invocation: *true' || true)" in
      0) _i='ambient' ;; *) _i='invoked only' ;;
    esac
    row "<code>$(printf '%s' "$_n" | esc)</code>" "$_b" "$_c" "$_i" "$(printf '%s' "$_d" | esc)"
  done
  printf '</tbody></table>\n'
}

# WHAT RUNS WITHOUT BEING ASKED, read out of the two installers rather than
# listed beside them. This is the table that answers "what is actually armed",
# and it is derived precisely because the wrong version of this fact is the
# expensive one: a document claiming a guard is wired, on a box where it is not,
# reads as coverage and is its opposite.
#
# floor-install.sh declares its wiring as rows of its floor_hooks table.
# runtime-install.sh routes its hooks through variables, so the variable is
# resolved here — parsing the merge_* calls alone would print `$VERDICT_HOOK`,
# which is a row nobody can act on.
d_cadence() {
  printf '<table class="grid"><thead><tr><th>Event</th><th>Matcher</th><th>Runs</th><th>Installer</th></tr></thead><tbody>\n'
  # AWK AND NOT sed|read, BECAUSE THE EMPTY MATCHER IS THE INTERESTING ROW.
  # `SessionStart ""` means "every session", and a tab-separated line with an
  # empty middle field is silently re-split by `read`: tab is IFS whitespace, so
  # two adjacent tabs collapse into one and the command lands in the matcher
  # column. Every SessionStart hook rendered one cell to the left, which is a
  # table that reads fine and is wrong. Filled here, before the field can vanish.
  # floor-install.sh's rows are its floor_hooks table (harbor#766); an opt-in row
  # (--with-b6, --with-stop-gate) is not armed by a default install, so it is left out.
  awk -F';' '
    /^floor_hooks\(\)/ { f = 1; next }
    f && /^ROWS$/ { exit }
    f && !/^#/ && NF >= 3 && $4 == "" {
      ev=$1; m=$2; c=$3
      if (m == "") m = (ev ~ /^(SessionStart|Stop|SessionEnd)$/) ? "(every session)" : "(every tool)"
      print ev "\t" m "\t" c
    }
  ' "$ROOT/bin/floor-install.sh" \
    | while IFS="$(printf '\t')" read -r ev m cmd; do
        [ -n "${ev:-}" ] || continue
        row "<code>$(printf '%s' "$ev" | esc)</code>" \
            "<code>$(printf '%s' "$m" | esc)</code>" \
            "<code>$(printf '%s' "$cmd" | _short | esc)</code>" \
            "<code>floor-install</code>"
      done
  awk '
    /^[A-Z_]+_HOOK="/ { k=$0; sub(/=.*/,"",k); v=$0; sub(/^[^=]*="/,"",v); sub(/"$/,"",v); H[k]=v; next }
    /merge_session_hook "\$NEW" "\$/ { k=$0; sub(/.*"\$/,"",k); sub(/".*/,"",k)
                                       print "SessionStart\t(every session)\t" H[k]; next }
    /merge_event_hook "\$NEW" "/ { e=$0; sub(/.*merge_event_hook "\$NEW" "/,"",e); sub(/".*/,"",e)
                                   k=$0; sub(/.*"\$/,"",k); sub(/".*/,"",k)
                                   print e "\t(every session)\t" H[k]; next }
    /\.statusLine = \{type: "command"/        { print "statusLine\t(every tick)\tfleet-glyph.sh" }
    /\.subagentStatusLine = \{type: "command"/ { print "subagentStatusLine\t(every tick)\tsubagent-glyph.sh" }
  ' "$ROOT/bin/runtime-install.sh" \
    | while IFS="$(printf '\t')" read -r ev m cmd; do
        [ -n "${ev:-}" ] || continue
        row "<code>$(printf '%s' "$ev" | esc)</code>" \
            "<code>$(printf '%s' "$m" | esc)</code>" \
            "<code>$(printf '%s' "$cmd" | _short | esc)</code>" \
            "<code>runtime-install</code>"
      done
  printf '</tbody></table>\n'
}

# THE RUNTIME PAYLOAD, read from the installer's own FILES= line. Two installers
# ship DISJOINT payloads and neither is a superset of the other, so "is it on the
# box?" has two answers and no single list to read them off. This is the runtime
# half; the floor half is the guard table in the floor section.
d_runtime() {
  printf '<table class="grid"><thead><tr><th>Script</th><th>What it answers</th></tr></thead><tbody>\n'
  # FILES plus $SUITE's scripts (harbor#727), each as <installed name> <checkout path>.
  { sed -n 's/^FILES="\(.*\)"$/\1/p' "$ROOT/bin/runtime-install.sh" | head -1 | tr ' ' '\n' | awk 'NF { print $0 " bin/" $0 }'
    sed -n 's/^SUITE="\(.*\)"$/\1/p' "$ROOT/bin/runtime-install.sh" | head -1 | tr ' ' '\n' \
      | awk -F: '$2 ~ /^bin\// { sub(/^bin\//, "", $2); print $2 " " $1 }'
  } | sort -u | while read -r s p; do
        [ -n "$s" ] || continue
        _f="$ROOT/$p"
        case "$p" in bin/*) _f="$ROOT/$(il_src "$ROOT" "$s")" ;; esac
        if [ -f "$_f" ]; then
          _d="$(sed -n '2,4p' "$_f" | sed -n 's/^# //p' | head -1)"
        else
          _d='(not present in this tree)'
        fi
        row "<code>$(printf '%s' "$s" | esc)</code>" "$(printf '%s' "$_d" | unesc | esc | tick)"
      done
  printf '</tbody></table>\n'
}

d_evals() {
  printf '<table class="grid"><thead><tr><th>Eval</th><th>Question</th></tr></thead><tbody>\n'
  sed -n 's/^## *//p' "$ROOT/EVALS.md" \
    | while IFS= read -r h; do
        case "$h" in [EA][0-9]*) ;; *) continue ;; esac
        _id="${h%% *}"; _rest="${h#* }"
        row "<code>$(printf '%s' "$_id" | esc)</code>" "$(printf '%s' "$_rest" | esc | tick)"
      done
  printf '</tbody></table>\n'
}

d_scripts() {
  printf '<table class="grid"><thead><tr><th>Script</th><th>Ticket / purpose line</th></tr></thead><tbody>\n'
  for f in "$ROOT"/bin/*.sh $(sh "$ROOT/bin/deploy-hooks.sh" --engines --root "$ROOT" 2>/dev/null); do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in *-test.sh) continue ;; esac
    _d="$(sed -n '2,4p' "$f" | sed -n 's/^# //p' | head -1)"
    row "<code>bin/$(basename "$f" | esc)</code>" "$(printf '%s' "$_d" | unesc | esc | tick)"
  done
  printf '</tbody></table>\n'
}

# The decision table (harbor#1029): one row per record in docs/decisions/, read from the front matter each
# record already carries. A record added is a row on the next --apply; a hand edit of a row is what --check
# and doc.site-generated find. superseded_by is `-` for a record that names no successor.
d_decisions() {
  printf '<table class="grid"><thead><tr><th>Id</th><th>Title</th><th>Status</th><th>Date</th><th>Superseded by</th></tr></thead><tbody>\n'
  for f in "$ROOT"/docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    [ -f "$f" ] || continue
    _sup="$(_fmv "$f" superseded_by)"
    row "<code>$(_fmv "$f" alias | esc)</code>" \
        "$(sed -n 's/^# //p' "$f" | head -1 | esc | tick)" \
        "$(_fmv "$f" status | esc)" \
        "$(_fmv "$f" date | esc)" \
        "$(printf '%s' "${_sup:--}" | esc)"
  done
  printf '</tbody></table>\n'
}

# ── assembly ────────────────────────────────────────────────────────────────
# A token with no `d_` function is a BUILD FAILURE. The alternative — rendering
# nothing where a table was meant to be — is a section quietly disappearing from
# a document whose entire claim is that it does not drift.
expand() {
  while IFS= read -r line; do
    case "$line" in
      *'<!--gen:'*'-->'*)
        _t="${line#*<!--gen:}"; _t="${_t%%-->*}"
        if ! command -v "d_$_t" >/dev/null 2>&1; then
          log_fail "unknown token <!--gen:$_t--> in the prose (docs/src): no d_$_t in bin/docs-gen.sh"
          log_nofix "bin/docs-gen.sh's header, ADDING A DERIVED TABLE: add d_$_t, or drop the token"
          log_end || :
          exit 3
        fi
        "d_$_t"
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

sections() { ls "$SRC"/*.html 2>/dev/null || true; }

# The rail is built from the <h2 id> in each section, so a new section needs no
# registration anywhere. A heading with no id is skipped rather than linked to
# nothing — and reported, because an unreachable section is a silent omission.
nav() {
  for f in $(sections); do
    sed -n 's|.*<h2 id="\([^"]*\)"[^>]*>\(.*\)</h2>.*|<a href="#\1">\2</a>|p' "$f"
  done
}

page() {
  cat <<'HEAD'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Harbor — architecture</title>
<style>
:root{
  --bg:#f5f6f8; --surface:#ffffff; --ink:#1b1f24; --muted:#5a636e;
  --rule:#dee2e7; --rule-strong:#c3cad2;
  --accent:#7a1f3d; --accent-soft:#f3e6ea;
  --signal:#0b6e4f; --warn:#8a5a00;
  --code-bg:#eef1f4;
  --serif:ui-serif,"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;
  --mono:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,monospace;
}
:root:not([data-theme="light"]) { }
@media (prefers-color-scheme: dark){
  :root:not([data-theme="light"]){
    --bg:#14171b; --surface:#1b1f24; --ink:#e6e8ea; --muted:#98a1ab;
    --rule:#2b3138; --rule-strong:#3a424b;
    --accent:#e4869f; --accent-soft:#2c1c22;
    --signal:#58c295; --warn:#d8a24a;
    --code-bg:#232830;
  }
}
:root[data-theme="dark"]{
  --bg:#14171b; --surface:#1b1f24; --ink:#e6e8ea; --muted:#98a1ab;
  --rule:#2b3138; --rule-strong:#3a424b;
  --accent:#e4869f; --accent-soft:#2c1c22;
  --signal:#58c295; --warn:#d8a24a;
  --code-bg:#232830;
}
*{box-sizing:border-box}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font-family:var(--serif); font-size:17px; line-height:1.62;
  -webkit-text-size-adjust:100%;
}
.wrap{display:grid; grid-template-columns:16rem minmax(0,1fr); gap:3rem; max-width:78rem; margin:0 auto; padding:0 1.5rem}
@media (max-width:60rem){ .wrap{grid-template-columns:1fr; gap:0} }

/* ── the rail ── */
.rail{position:sticky; top:0; align-self:start; max-height:100vh; overflow-y:auto; padding:2.5rem 0 3rem}
@media (max-width:60rem){ .rail{position:static; max-height:none; border-bottom:1px solid var(--rule); margin-bottom:1.5rem} }
.rail .brand{font-family:var(--mono); font-size:.68rem; letter-spacing:.14em; text-transform:uppercase; color:var(--muted); margin-bottom:1.25rem}
.rail a{display:block; font-family:var(--mono); font-size:.75rem; line-height:1.5; color:var(--muted); text-decoration:none; padding:.3rem 0 .3rem .75rem; border-left:2px solid var(--rule)}
.rail a:hover,.rail a:focus{color:var(--accent); border-left-color:var(--accent); outline:none}
.rail a:focus-visible{outline:2px solid var(--accent); outline-offset:2px}

/* ── content ── */
main{padding:2.5rem 0 6rem; min-width:0}
main > section{margin-bottom:4.5rem}
h1{font-size:2.6rem; line-height:1.12; margin:0 0 .5rem; letter-spacing:-.015em; text-wrap:balance}
h2{font-size:1.7rem; line-height:1.2; margin:0 0 1.1rem; letter-spacing:-.01em; text-wrap:balance;
   padding-bottom:.5rem; border-bottom:1px solid var(--rule-strong)}
h3{font-size:1.12rem; margin:2.2rem 0 .6rem; letter-spacing:.005em}
h4{font-family:var(--mono); font-size:.72rem; letter-spacing:.13em; text-transform:uppercase;
   color:var(--muted); margin:2rem 0 .5rem}
p,li{max-width:64ch}
p{margin:0 0 1rem}
ul,ol{margin:0 0 1rem; padding-left:1.2rem}
li{margin-bottom:.35rem}
a{color:var(--accent)}
code{font-family:var(--mono); font-size:.86em; background:var(--code-bg); padding:.1em .34em; border-radius:3px}
pre{background:var(--code-bg); border:1px solid var(--rule); border-radius:6px; padding:.9rem 1rem;
    overflow-x:auto; font-family:var(--mono); font-size:.8rem; line-height:1.5}
pre code{background:none; padding:0; font-size:1em}
strong{font-weight:700}

.lede{font-size:1.16rem; color:var(--muted); max-width:60ch; margin-bottom:2rem}
.eyebrow{font-family:var(--mono); font-size:.68rem; letter-spacing:.14em; text-transform:uppercase; color:var(--accent); margin:0 0 .6rem}

/* a claim the repo enforces, vs one it only asserts */
.note{border-left:3px solid var(--rule-strong); background:var(--surface); padding:.9rem 1.1rem; margin:1.4rem 0; border-radius:0 5px 5px 0}
.note.why{border-left-color:var(--accent)}
.note.hazard{border-left-color:var(--warn)}
.note p:last-child{margin-bottom:0}
.note .tag{font-family:var(--mono); font-size:.66rem; letter-spacing:.12em; text-transform:uppercase; color:var(--muted); display:block; margin-bottom:.35rem}

/* ── tables ── */
.scroll{overflow-x:auto; margin:1.2rem 0; border:1px solid var(--rule); border-radius:6px; background:var(--surface)}
table.grid{border-collapse:collapse; width:100%; font-family:var(--mono); font-size:.76rem; line-height:1.45}
table.grid th{text-align:left; font-weight:600; letter-spacing:.06em; text-transform:uppercase; font-size:.66rem;
  color:var(--muted); padding:.6rem .8rem; border-bottom:1px solid var(--rule-strong); white-space:nowrap}
table.grid td{padding:.5rem .8rem; border-bottom:1px solid var(--rule); vertical-align:top; font-family:var(--serif); font-size:.88rem}
table.grid td:first-child{font-family:var(--mono); font-size:.76rem; white-space:nowrap}
table.grid tr:last-child td{border-bottom:none}
table.grid tr.advisory td{color:var(--muted)}
table.grid code{background:none; padding:0}
p.derived{font-size:.95rem}

figure{margin:1.8rem 0; padding:0}
figure svg{display:block; max-width:100%; height:auto; margin:0 auto; color:var(--ink)}
figcaption{font-size:.86rem; color:var(--muted); margin-top:.7rem; max-width:60ch}

.gen{font-family:var(--mono); font-size:.7rem; color:var(--muted); border-top:1px solid var(--rule); padding-top:1rem; margin-top:3rem}
@media (prefers-reduced-motion:reduce){ *{animation:none!important; transition:none!important} }
</style>
</head>
<body>
<div class="wrap">
<nav class="rail" aria-label="Sections">
<div class="brand">Harbor · architecture</div>
HEAD
  nav
  cat <<'MID'
</nav>
<main>
MID
  for f in $(sections); do
    expand < "$f"
  done
  cat <<'FOOT'
<p class="gen">This page is generated by <code>bin/docs-gen.sh</code> from <code>docs/src/*.html</code>.
Every table above is derived from the repository at generation time — edit the prose, never this file.
<code>sh bin/docs-gen.sh --apply</code> builds it; it is not committed.</p>
</main>
</div>
</body>
</html>
FOOT
}

case "$MODE" in
  tokens)
    for f in $(sections); do
      grep -o '<!--gen:[a-z_]*-->' "$f" 2>/dev/null | while IFS= read -r t; do
        _n="${t#<!--gen:}"; _n="${_n%-->}"
        if command -v "d_$_n" >/dev/null 2>&1; then _s='ok'; else _s='MISSING'; fi
        printf '%-14s %-10s %s\n' "$_n" "$_s" "${f#"$ROOT"/}"
      done
    done
    ;;
  print) page ;;
  apply)
    mkdir -p "$ROOT/docs"
    # THE TEMPORARIES LIVE IN THE WORKING TREE, so an interrupt leaves one behind
    # as an untracked file next to the document it was building (measured: a
    # killed `--check` left docs/index.html.check.tmp, and the next `git status`
    # offers it for staging). Both arms clean up on the happy path already; the
    # trap is for the path where there is no happy path. Cleared and re-raised
    # rather than left armed, so a caller sourcing this file does not inherit it.
    trap 'rm -f "$OUT.tmp" "$OUT.check.tmp"; trap - INT TERM HUP EXIT' INT TERM HUP EXIT
    log_head apply
    # In the && list, as before: a d_ table that fails renders what it has rather than killing the page.
    if ! { page > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"; }; then
      log_fail "could not build and replace ${OUT#"$ROOT"/}"
      log_nofix "the error above"
      log_end || :; exit 1
    fi
    log_ok "wrote ${OUT#"$ROOT"/} ($(wc -c < "$OUT" | tr -d ' ') bytes)"
    log_end; exit $?
    ;;
  check)
    # NOT A FRESHNESS CHECK (harbor#1197): docs/index.html is not committed, so there is nothing to be stale against.
    # What can still be wrong is the build itself: a d_ table that fails, or an unknown <!--gen:NAME--> hole (exit 3,
    # its FAIL line on stderr). The page goes to a temp file outside the tree; docs/index.html is never touched.
    log_head check
    _tmp="$(mktemp "${TMPDIR:-/tmp}/docs-gen.check.XXXXXX")" || { log_fail "could not make a temp file"; log_nofix "TMPDIR"; log_end || :; exit 1; }
    trap 'rm -f "$_tmp"; trap - INT TERM HUP EXIT' INT TERM HUP EXIT
    if page > "$_tmp" && [ "$(tail -n 1 "$_tmp")" = "</html>" ]; then
      log_ok "the page builds from docs/src ($(wc -c < "$_tmp" | tr -d ' ') bytes, no unknown hole)"
    else
      log_fail "the page could not be built: it does not end in </html>"
      log_nofix "the error above, or sh '$SELF/docs-gen.sh' --tokens"
    fi
    rm -f "$_tmp"
    log_end; exit $?
    ;;
esac
