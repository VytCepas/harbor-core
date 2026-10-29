#!/usr/bin/env sh
# doc-refs.sh (harbor#996 E1, from #1015) — every path an entry doc cites resolves, and the doc is not left behind.
#
#   sh bin/doc-refs.sh                     judge this checkout's entry docs
#   sh bin/doc-refs.sh --root <dir>        judge that checkout (a CI job in a sibling repo points this at itself)
#   sh bin/doc-refs.sh --fleet             judge every checkout in the registry (roots.sh --repos), one count row each
#   sh bin/doc-refs.sh --self-test         every fixture yields exactly its expected ids, and both rules went red
#   sh bin/doc-refs.sh --list              each rule's id, mode and title, read from standards/naming/controls.tsv
#   sh bin/doc-refs.sh --help
#
#   --doc <file>          judge this doc (repeatable; relative to the root) instead of the entry docs
#   --system <id>=<dir>   a system's checkout, for a `<id>:path` citation (repeatable; wins over the registry)
#   --no-registry         know no system but the --system ones (the self-test and the suite use this)
#   --self <id>           which system this root is (default: the registry row sharing its git history)
#   --stale-after <N>     doc.refs-stale at N or more commits behind (default 100)
#   --format findings     also print one `<A|V> TAB <rule> TAB <doc> -> <token>` record per finding, then
#                         `S TAB docs TAB refs TAB dangling TAB stale TAB not-judged` on stdout
#   --registry <dir>      the registry (default: <root>/standards/naming, else this checkout's): controls.tsv modes
#
#   exit (D-49) 0 pass, warn and shadow findings allowed · 1 a block finding, or a failed self-test · 2 usage
#   · 3 unchecked: no entry doc could be read, or no controls.tsv row gives a rule its mode. A citation that
#   could not be looked at (a system whose checkout is absent, a shallow clone for staleness) is counted as
#   NOT JUDGED in the summary and never reads as "resolves". LINT_REDLOG=<file> appends the id of every rule that
#   goes red, shadow ones too, as bin/lint-module.sh does.
#
# THE RULES, each a standards/naming/controls.tsv row whose mode is read there and never here:
#   doc.refs-resolve   a path an entry doc cites does not exist where it says
#   doc.refs-stale     an entry doc has N or more commits behind the paths it cites
#
# WHAT IS CITED. Entry docs: README.md, AGENTS.md, CLAUDE.md, HANDOFF.md and docs/context-map*.md. In them:
#   [text](target)       a link target, relative to the doc, then to the root. URLs, mailto and #anchors are not paths.
#   `a/b.ext`            a backticked span that is one path with a slash: it ends in an extension or a slash, or
#                        its first segment is a top-level entry of the checkout. A bare `FILE.md` with no slash is
#                        PROSE (bin/cited-paths.awk argues it: guessing is how a rule gets muted).
#   `sh bin/x.sh -v`     a word inside a longer span counts only when it starts at a top-level entry and ends in a file
#                        extension or a slash.
#   `<system>:path`      a path in another checkout; <system> must be a registry id. Its checkout absent here (CI has
#                        none) means NOT JUDGED, said in the summary.
# Not read: fenced code blocks (commands and output; their line count is said), absolute and ~/ paths, anything with a
# glob, placeholder or shell character, and a path git ignores (a produced name such as build/ exists only after the
# generator ran). A `:12` or `#anchor` suffix is dropped before the test.
#
# THE EXEMPTION IS A MARKER, NOT A LIST. A deliberate example carries `example:` — as a span's prefix
# (`example:out/report.html`), a link target's, or lowercase in the line's own prose (not inside a link target or a span) (`for example: `a/b.sh``), which exempts
# the line's citations. It is counted in the summary, so a doc cannot hide its dead paths behind it unseen.
#
# STALENESS is commits that touched a cited FILE since the doc itself last changed: the doc says what the code did
# N commits ago. A cited directory is a claim that it exists, not about its contents, so it does not count here.
# A shallow clone cannot count, so it is NOT JUDGED rather than zero.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md): the extractor, the resolver and the staleness count share one list of
# cited paths; split, each would re-read the docs and could disagree about what was cited.
set -eu

HERE="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
SELF="$HERE/$(basename -- "$0")"
LOG_FD=2   # stdout carries --format findings, the fleet table and --list; the log goes to stderr
. "$HERE/log-lib.sh"
log_init doc-refs

usage() { awk 'NR < 2 { next } /^# DELIBERATELY/ || !/^#/ { exit } { sub(/^# ?/, ""); print }' "$SELF"; }
unchecked() { log_fail "$1"; log_fix "$2"; log_end || :; exit 3; }
usage_err() { log_fail "$1"; log_fix "sh $SELF --help"; log_end || :; exit 2; }

ACTION=judge; FORMAT=""; ROOT=""; REG=""; DOCS=""; SYSMAP=""; NOREG=0; SELFID=""; STALE=100
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --self-test) ACTION=self-test ;;
    --list) ACTION=list ;;
    --fleet) ACTION=fleet ;;
    --no-registry) NOREG=1 ;;
    --doc) [ $# -ge 2 ] || usage_err "--doc needs a file"; DOCS="$DOCS
$2"; shift ;;
    --system) [ $# -ge 2 ] || usage_err "--system needs <id>=<dir>"
              case "$2" in [A-Za-z0-9]*=?*) ;; *) usage_err "--system needs <id>=<dir>, got $2" ;; esac
              SYSMAP="$SYSMAP
$2"; shift ;;
    --self) [ $# -ge 2 ] || usage_err "--self needs a system id"; SELFID="$2"; shift ;;
    --stale-after) [ $# -ge 2 ] || usage_err "--stale-after needs a number"
                   case "$2" in ''|*[!0-9]*|0) usage_err "--stale-after needs a positive number, got $2" ;; esac
                   STALE="$2"; shift ;;
    --root) [ $# -ge 2 ] || usage_err "--root needs a directory"; ROOT="$2"; shift ;;
    --registry) [ $# -ge 2 ] || usage_err "--registry needs a directory"; REG="$2"; shift ;;
    --format) [ $# -ge 2 ] || usage_err "--format needs a value"; FORMAT="$2"; shift ;;
    -*) usage_err "unknown option $1" ;;
    *) usage_err "unexpected argument $1" ;;
  esac
  shift
done
case "$FORMAT" in ''|findings) ;; *) usage_err "--format is findings" ;; esac
[ -n "$ROOT" ] || ROOT="$HERE/.."
ROOT="$(CDPATH='' cd -- "$ROOT" 2>/dev/null && pwd -P)" || usage_err "--root is not a directory"
# a sibling repo carries no registry: the modes are this checkout's, never a default invented here
if [ -z "$REG" ]; then REG="$ROOT/standards/naming"; [ -f "$REG/controls.tsv" ] || REG="$HERE/../standards/naming"; fi
CONTROLS="$REG/controls.tsv"
T="$(mktemp -d "${TMPDIR:-/tmp}/doc-refs.XXXXXX")"
trap 'rm -rf "$T"' EXIT INT TERM HUP

IDS="doc.refs-resolve doc.refs-stale"

mode_of() {
  awk -F'\t' -v id="$1" '/^#/ { next } $1 == id { m = $2; if (m == "advisory" || m == "inform") m = "warn"; print m; exit }' "$CONTROLS"
}

if [ "$ACTION" = list ]; then
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS" "ls $REG"
  awk -F'\t' -v ids="$IDS" 'BEGIN { n = split(ids, I, " "); for (i = 1; i <= n; i++) want[I[i]] = 1 }
    /^#/ || $1 == "id" { next } ($1 in want) { printf "  %-18s %-7s %s\n", $1, $2, $13 }' "$CONTROLS"
  exit 0
fi

# the git history a checkout shares with its worktrees: empty when it is not a git checkout
common_dir() { # <dir>
  _g="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 0
  [ -n "$_g" ] || return 0
  case "$_g" in /*) ;; *) _g="$1/$_g" ;; esac
  ( cd "$_g" 2>/dev/null && pwd -P ) || :
}

# ── the systems: registry ids plus --system ones ────────────────────────────
# $T/systems: id TAB checkout (empty when the registry knows the id and this box has no checkout for it)
build_systems() {
  : > "$T/systems"
  if [ "$NOREG" = 0 ] && [ -f "$HERE/roots.sh" ]; then
    sh "$HERE/roots.sh" --repos 2>/dev/null > "$T/systems" || : > "$T/systems"
  fi
  printf '%s\n' "$SYSMAP" | awk -F= 'NF >= 2 { id = $1; d = $0; sub(/^[^=]*=/, "", d); printf "%s\t%s\n", id, d }' > "$T/sysmap"
  # --system wins over the registry for the same id
  awk -F'\t' 'FILENAME == ARGV[1] { over[$1] = 1; next } !($1 in over)' "$T/sysmap" "$T/systems" > "$T/systems.tmp"
  cat "$T/sysmap" >> "$T/systems.tmp"; mv "$T/systems.tmp" "$T/systems"
  # which system is THIS root: --self, else the registry row whose checkout shares its git history (a worktree of it)
  if [ -z "$SELFID" ] && command -v git >/dev/null 2>&1; then
    _ocd="$(common_dir "$ROOT")"
    if [ -n "$_ocd" ]; then
      while IFS='	' read -r _sid _sdir; do
        [ -n "$_sdir" ] && [ -d "$_sdir" ] || continue
        [ "$(common_dir "$_sdir")" = "$_ocd" ] || continue
        SELFID="$_sid"; break
      done < "$T/systems"
    fi
  fi
  return 0
}

# ── the extractor + shape filter (awk) ──────────────────────────────────────
# extract <doc relative to root> <abs doc> → `doc TAB line TAB kind TAB ex TAB mode TAB path TAB token` per citation.
# kind L link, C whole-span, W word of a longer span. mode R root first, D doc dir first, S:<id> another system.
# The fenced-block line count goes to stderr as `skipped TAB n`.
EXTRACT_AWK='
function strip(t) { sub(/#.*$/, "", t); sub(/\?.*$/, "", t); sub(/:L?[0-9]+(-L?[0-9]+)?$/, "", t); return t }
function lastseg(p,   a, k) { k = split(p, a, "/"); return a[k] }
function firstseg(p) { return substr(p, 1, index(p, "/") - 1) }
function emit(kind, tok,   t, p, sys, c, first, last, mode, hasslash, ok, exm) {
  t = tok
  gsub(/^[ \t(<]+|[ \t).,;>]+$/, "", t)
  exm = 0
  if (t ~ /^example:/) { exm = 1; t = substr(t, 9) }
  if (t == "" || t ~ /^[a-z][a-z0-9+.-]*:\/\// || t ~ /^(mailto|tel|data|javascript):/ || t ~ /^#/) return
  t = strip(t)
  if (t == "") return
  sys = ""
  c = index(t, ":")
  if (c > 1 && substr(t, 1, c - 1) in SYS) { sys = substr(t, 1, c - 1); p = substr(t, c + 1); if (p == "") return }
  else if (c > 0) return
  else p = t
  if (p ~ /[][*?<>{}|()=,;"\\$ \t]/ || p ~ /^[\/~@-]/ || p == "." || p == ".." || p ~ /\/\// ) return
  hasslash = index(p, "/") > 0; last = lastseg(p); first = hasslash ? firstseg(p) : p
  ok = 0
  if (sys != "") ok = 1
  else if (kind == "L") ok = 1
  else if (kind == "C") ok = hasslash && (p ~ /\/$/ || last ~ /\.[A-Za-z][A-Za-z0-9]*$/ || first in TOP || first == "." || first == "..")
  else ok = hasslash && (p ~ /\/$/ || last ~ /\.[A-Za-z][A-Za-z0-9]*$/) && (first in TOP || first == "." || first == "..")
  if (!ok) return
  mode = (sys != "") ? "S:" sys : ((kind == "L" || first == "." || first == "..") ? "D" : "R")
  printf "%s\t%d\t%s\t%d\t%s\t%s\t%s\n", DOC, NR, kind, (ex || exs || exm) ? 1 : 0, mode, p, tok
}
function words(span,   n, a, i) { n = split(span, a, /[ \t]+/); for (i = 1; i <= n; i++) emit("W", a[i]) }
BEGIN { n = split(TOPS, A, " "); for (i = 1; i <= n; i++) TOP[A[i]] = 1
        n = split(SYSS, B, " "); for (i = 1; i <= n; i++) SYS[B[i]] = 1 }
/^[ \t]*(```|~~~)/ { fence = !fence; skipped++; next }
fence { skipped++; next }
{
  s = $0; prose = $0; gsub(/`[^`]*`/, " ", prose); gsub(/\]\([^)]*\)/, "]", prose); ex = (prose ~ /(^|[ (])example:/) ? 1 : 0
  while (match(s, /\]\([^)]*\)/)) {
    tgt = substr(s, RSTART + 2, RLENGTH - 3); sub(/[ \t].*$/, "", tgt); emit("L", tgt)
    s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
  }
  while (match(s, /`[^`]+`/)) {
    span = substr(s, RSTART + 1, RLENGTH - 2)
    exs = 0
    if (span ~ /^example:/) { exs = 1; sub(/^example:[ \t]*/, "", span) }
    if (span ~ /[ \t]/) words(span)
    else emit("C", span)
    exs = 0
    s = substr(s, 1, RSTART - 1) " " substr(s, RSTART + RLENGTH)
  }
}
END { printf "skipped\t%d\n", skipped + 0 > "/dev/stderr" }'

# ── the judge ────────────────────────────────────────────────────────────────
# judge: reads $ROOT, writes $T/findings (`rule TAB subject TAB message`) and $T/stats
judge() {
  : > "$T/findings"; : > "$T/cands"; : > "$T/cited.all"; _docs=0; _refs=0; _exempt=0; _prod=0; _nj=0; _skipped=0
  _tops="$(ls -A "$ROOT" 2>/dev/null | grep -v '^\.git$' | tr '\n' ' ')"
  _syss="$(cut -f1 "$T/systems" | tr '\n' ' ')"
  _list="$T/doclist"
  if [ -n "$DOCS" ]; then printf '%s\n' "$DOCS" | grep . > "$_list" || : > "$_list"
  else
    ( cd "$ROOT" && for _f in README.md AGENTS.md CLAUDE.md HANDOFF.md docs/context-map*.md; do [ -f "$_f" ] && printf '%s\n' "$_f"; done ) > "$_list" || :
  fi
  while IFS= read -r _d; do
    [ -f "$ROOT/$_d" ] || continue
    _docs=$((_docs + 1))
    awk -F'\t' -v DOC="$_d" -v TOPS="$_tops" -v SYSS="$_syss" "$EXTRACT_AWK" "$ROOT/$_d" >> "$T/cands" 2> "$T/skip" || { unchecked "the extractor (awk) failed on $_d, so nothing was judged" "sh $SELF --doc $_d"; }
    _skipped=$((_skipped + $(awk -F'\t' '$1 == "skipped" { n += $2 } END { print n + 0 }' "$T/skip")))
  done < "$_list"
  [ "$_docs" -gt 0 ] || unchecked "no entry doc to judge in $ROOT (README.md AGENTS.md CLAUDE.md HANDOFF.md docs/context-map*.md), so nothing was judged" "sh $SELF --doc <file>"
  # one row per (doc, token): the first line, how many times it was cited
  LC_ALL=C sort -t '	' -k1,1 -k7,7 -k2,2n "$T/cands" | awk -F'\t' '
    { k = $1 SUBSEP $7; if (k in n) { n[k]++; if ($4 == 0) ex[k] = 0; next } n[k] = 1; ex[k] = $4; row[k] = $0; ord[++c] = k }
    END { for (i = 1; i <= c; i++) { k = ord[i]; print row[k] "\t" n[k] "\t" ex[k] } }' > "$T/uniq"
  while IFS='	' read -r _doc _ln _kind _ex _mode _path _tok _n _allex; do
    _refs=$((_refs + 1))
    if [ "$_allex" = 1 ]; then _exempt=$((_exempt + 1)); continue; fi
    _dd="$(dirname -- "$_doc")"; [ "$_dd" = . ] && _dd=""
    case "$_mode" in
      S:*)
        _sid="${_mode#S:}"; _sdir="$(awk -F'\t' -v i="$_sid" '$1 == i { print $2; exit }' "$T/systems")"
        if [ "$_sid" = "$SELFID" ]; then _sdir="$ROOT"; fi
        if [ -z "$_sdir" ] || [ ! -d "$_sdir" ]; then _nj=$((_nj + 1)); printf '%s\n' "$_sid" >> "$T/absent"; continue; fi
        if [ -e "$_sdir/$_path" ]; then
          [ "$_sdir" != "$ROOT" ] || printf '%s\t%s\n' "$_doc" "$_path" >> "$T/cited.all"
          continue
        fi
        printf 'doc.refs-resolve\t%s -> %s\t%s:%s cites %s, which does not exist in system %s\n' "$_doc" "$_tok" "$_doc" "$_ln" "$_tok" "$_sid" >> "$T/findings"
        continue ;;
    esac
    _hit=""
    if [ "$_mode" = D ]; then _try="$_dd/$_path $_path"; else _try="$_path $_dd/$_path"; fi
    for _c in $_try; do
      _c="${_c#/}"
      [ -e "$ROOT/$_c" ] && { _hit="$_c"; break; }
    done
    if [ -n "$_hit" ]; then printf '%s\t%s\n' "$_doc" "$_hit" >> "$T/cited.all"; continue; fi
    # a path git ignores is a produced name: it exists only after its generator ran
    if git -C "$ROOT" check-ignore -q -- "$_path" 2>/dev/null; then _prod=$((_prod + 1)); continue; fi
    printf 'doc.refs-resolve\t%s -> %s\t%s:%s cites %s, which does not exist%s\n' "$_doc" "$_tok" "$_doc" "$_ln" "$_tok" "$([ "$_n" -gt 1 ] && printf ' (cited %s times)' "$_n")" >> "$T/findings"
  done < "$T/uniq"
  # staleness: commits that touched a cited path since the doc last changed
  _stale_nj=""
  if ! command -v git >/dev/null 2>&1 || ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then _stale_nj="not a git checkout"
  elif [ "$(git -C "$ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = true ]; then _stale_nj="shallow clone"
  else
    while IFS= read -r _d; do
      [ -f "$ROOT/$_d" ] || continue
      _last="$(git -C "$ROOT" log -1 --format=%H -- "$_d" 2>/dev/null || :)"
      [ -n "$_last" ] || continue
      awk -F'\t' -v d="$_d" 'function norm(p,   n, a, i, k, o, r) { n = split(p, a, "/"); k = 0
          for (i = 1; i <= n; i++) { if (a[i] == "" || a[i] == ".") continue; if (a[i] == ".." && k > 0 && o[k] != "..") { k--; continue }; o[++k] = a[i] }
          r = ""; for (i = 1; i <= k; i++) r = r (i > 1 ? "/" : "") o[i]; return r }
        $1 == d { p = norm($2); if (p != d && p !~ /^\.\./ && p != "") print p }' "$T/cited.all" | LC_ALL=C sort -u | while IFS= read -r _cp; do [ -d "$ROOT/$_cp" ] || printf '%s\n' "$_cp"; done > "$T/cited.one"
      [ -s "$T/cited.one" ] || continue
      _np="$(wc -l < "$T/cited.one" | tr -d ' ')"
      set -f
      _behind="$(xargs git -C "$ROOT" rev-list --count "$_last..HEAD" -- < "$T/cited.one" 2>/dev/null || echo x)"
      set +f
      case "$_behind" in ''|*[!0-9]*) _stale_nj="git could not count commits"; continue ;; esac
      if [ "$_behind" -ge "$STALE" ]; then
        printf 'doc.refs-stale\t%s\t%s is %s commits behind the %s path(s) it cites (since it last changed; threshold %s)\n' "$_d" "$_d" "$_behind" "$_np" "$STALE" >> "$T/findings"
      fi
    done < "$_list"
  fi
  [ -z "$_stale_nj" ] || _nj=$((_nj + 1))
  LC_ALL=C sort -t '	' -k1,1 -k2,2 "$T/findings" -o "$T/findings"
  _dang="$(awk -F'\t' '$1 == "doc.refs-resolve"' "$T/findings" | wc -l | tr -d ' ')"
  _stl="$(awk -F'\t' '$1 == "doc.refs-stale"' "$T/findings" | wc -l | tr -d ' ')"
}

# run <label> → reports $T/findings per mode; returns 1 on a block finding
run() {
  _n=0; _blk=0; _shd=0
  for _r in $IDS; do
    _m="$(mode_of "$_r")"
    [ -n "$_m" ] || unchecked "no controls.tsv row for $_r, so its mode is unknown" "add the row to $CONTROLS"
    printf '%s\t%s\n' "$_r" "$_m"
  done > "$T/modes"
  [ -z "${LINT_REDLOG:-}" ] || cut -f1 "$T/findings" >> "$LINT_REDLOG" 2>/dev/null || :
  awk -F'\t' 'NR == FNR { m[$1] = $2; next } { print m[$1] "\t" $1 "\t" $2 "\t" $3 }' "$T/modes" "$T/findings" > "$T/judged"
  if [ "$FORMAT" = findings ]; then
    awk -F'\t' '$1 != "shadow" { printf "%s\t%s\t%s\n", ($1 == "block" ? "V" : "A"), $2, $3 }' "$T/judged"
    printf 'S\t%s\t%s\t%s\t%s\t%s\n' "$_docs" "$_refs" "$_dang" "$_stl" "$_nj"
  fi
  while IFS='	' read -r _l _r _s _msg; do
    case "$_l" in
      shadow) _shd=$((_shd + 1)); continue ;;
      block)  _blk=$((_blk + 1)); log_fail "[$_r] $_s — $_msg"; log_nofix "bin/doc-refs.sh --help" ;;
      *)      log_warn "[$_r] $_s — $_msg" ;;
    esac
    _n=$((_n + 1))
  done < "$T/judged"
  _sum="$_docs doc(s), $_refs citation(s): $_dang dangling, $_stl stale, $_exempt example-marked, $_prod produced (git-ignored), $_skipped fenced line(s) not read"
  if [ -s "$T/absent" ]; then _sum="$_sum; not judged, system checkout absent: $(LC_ALL=C sort -u "$T/absent" | tr '\n' ' ' | sed 's/ $//')"; fi
  [ -z "$_stale_nj" ] || _sum="$_sum; staleness not judged ($_stale_nj)"
  # "ok" is for a run that looked at everything it was pointed at; a partial look is a note, never a clean pass
  if [ "$_n" -gt 0 ]; then log_note "$_sum"
  elif [ "$_nj" -eq 0 ]; then log_ok "no finding in $_sum"
  else log_note "no finding in the part judged: $_sum"; fi
  [ "$_shd" -eq 0 ] || log_note "$_shd shadow finding(s) recorded, not shown: their rules are in shadow mode (D-29)"
  [ "$_blk" -eq 0 ]
}

# ── --self-test ──────────────────────────────────────────────────────────────
# fixtures/doc-refs/<case>/: doc.md is the README the case judges; files.txt the tree it lives in (`path=text` gives a file
# its text), `---` starting the next commit; sibling.txt the files of a system `sysb` checkout (`sysc` has none); options.txt extra arguments;
# expect.tsv the ids the case MUST yield, one per line, and nothing else may go red (empty = a pass case). Whether a
# rule went red is read from the red log the run writes, never from the fixture text.
if [ "$ACTION" = self-test ]; then
  FX="$ROOT/fixtures/doc-refs"
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the modes are unknown" "ls $REG"
  [ -d "$FX" ] || unchecked "no fixtures at fixtures/doc-refs — the self-test judged NOTHING" "ls $ROOT/fixtures"
  command -v git >/dev/null 2>&1 || unchecked "git is absent, so the fixture trees cannot be built" "install git"
  log_head "self-test: fixtures/doc-refs"
  : > "$T/allred"; _cases=0
  for _d in "$FX"/*/; do
    [ -f "${_d}doc.md" ] || continue
    _c="$(basename "$_d")"; _cases=$((_cases + 1))
    _w="$T/case-$_c"; mkdir -p "$_w/tree" "$_w/sysb"
    ( cd "$_w/tree" && git init -q . && git config user.email t@t && git config user.name t
      _first=1
      if [ -f "${_d}files.txt" ]; then
        while IFS= read -r _p || [ -n "$_p" ]; do
          if [ "$_p" = "---" ]; then git add -A && git commit -qm c --allow-empty; continue; fi
          [ -n "$_p" ] || continue
          case "$_p" in *=*) _body="${_p#*=}"; _p="${_p%%=*}" ;; *) _body=x ;; esac
          mkdir -p "$(dirname -- "$_p")"
          if [ "$_p" = README.md ]; then cp "${_d}doc.md" README.md; else printf '%s\n' "$_body" >> "$_p"; fi
        done < "${_d}files.txt"
      fi
      [ -f README.md ] || cp "${_d}doc.md" README.md
      git add -A && git commit -qm c --allow-empty ) > /dev/null 2>&1 || { log_fail "$_c: the fixture tree could not be built"; log_fix "sh $SELF --self-test"; continue; }
    if [ -f "${_d}sibling.txt" ]; then
      while IFS= read -r _p || [ -n "$_p" ]; do [ -n "$_p" ] || continue; mkdir -p "$_w/sysb/$(dirname -- "$_p")"; : > "$_w/sysb/$_p"; done < "${_d}sibling.txt"
    fi
    _extra=""; [ ! -f "${_d}options.txt" ] || _extra="$(cat "${_d}options.txt")"
    : > "$T/red"; _rc=0
    # shellcheck disable=SC2086
    LINT_REDLOG="$T/red" sh "$SELF" --root "$_w/tree" --registry "$REG" --no-registry --system "sysb=$_w/sysb" --system "sysc=$_w/absent" $_extra > /dev/null 2> "$T/case.err" || _rc=$?
    [ "$_rc" -le 1 ] || { log_fail "$_c: exited $_rc, so it judged nothing ($(grep -m1 'FAIL:' "$T/case.err" | sed 's/^ *FAIL: //'))"; log_fix "sh $SELF --root $_w/tree --no-registry"; continue; }
    sort -u "$T/red" -o "$T/red"; cat "$T/red" >> "$T/allred"
    [ -z "${LINT_REDLOG:-}" ] || cat "$T/red" >> "$LINT_REDLOG" 2>/dev/null || :
    if [ -f "${_d}expect.tsv" ]; then grep -v '^#' "${_d}expect.tsv" | grep . | sort -u > "$T/want" || :; else : > "$T/want"; fi
    [ -f "$T/want" ] || : > "$T/want"
    if cmp -s "$T/want" "$T/red"; then
      log_ok "$_c: $( [ -s "$T/want" ] && tr '\n' ' ' < "$T/want" | sed 's/ $//' || echo 'stays green' )"
    else
      log_fail "$_c: expected [$(tr '\n' ' ' < "$T/want" | sed 's/ $//')] but went red on [$(tr '\n' ' ' < "$T/red" | sed 's/ $//')]"
      log_fix "sh $SELF --root $_w/tree --no-registry"
    fi
  done
  [ "$_cases" -gt 0 ] || unchecked "fixtures/doc-refs holds no case — nothing to judge" "add fixtures/doc-refs/<case>/doc.md"
  sort -u "$T/allred" -o "$T/allred"
  for _r in $IDS; do
    grep -qx -- "$_r" "$T/allred" || { log_fail "$_r never went red in this self-test"; log_fix "add a fixture under fixtures/doc-refs/ that yields $_r"; }
  done
  # No entry doc at all must be unchecked (3), never a pass: the red proof of the exit-3 contract.
  mkdir -p "$T/empty"; _rc=0; sh "$SELF" --root "$T/empty" --registry "$REG" --no-registry > /dev/null 2>&1 || _rc=$?
  if [ "$_rc" -eq 3 ]; then log_ok "a tree with no entry doc exits 3"; else log_fail "a tree with no entry doc exited $_rc, not 3"; log_fix "sh $SELF --root $T/empty"; fi
  log_end; exit $?
fi

# ── --fleet ──────────────────────────────────────────────────────────────────
if [ "$ACTION" = fleet ]; then
  [ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the modes are unknown" "ls $REG"
  build_systems
  [ -s "$T/systems" ] || unchecked "the registry lists no checkout (sh bin/roots.sh --repos), so no repo was judged" "sh $HERE/roots.sh --repos"
  log_head "fleet: every registry checkout"
  printf 'system\tdocs\tcitations\tdangling\tstale\tnot-judged\n'
  _tot_d=0; _tot_s=0; _skip=0
  while IFS='	' read -r _sid _sdir; do
    if [ ! -d "$_sdir" ]; then _skip=$((_skip + 1)); printf '%s\t-\t-\t-\t-\tcheckout absent\n' "$_sid"; continue; fi
    _rc=0; _o="$(sh "$SELF" --root "$_sdir" --self "$_sid" --registry "$REG" --format findings 2>/dev/null)" || _rc=$?
    case "$_rc" in
      0|1) _s="$(printf '%s\n' "$_o" | awk -F'\t' '$1 == "S" { print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }')"
           printf '%s\t%s\n' "$_sid" "$_s"
           _tot_d=$((_tot_d + $(printf '%s' "$_s" | cut -f3))); _tot_s=$((_tot_s + $(printf '%s' "$_s" | cut -f4))) ;;
      3) _skip=$((_skip + 1)); printf '%s\t-\t-\t-\t-\tunchecked (no entry doc)\n' "$_sid" ;;
      *) _skip=$((_skip + 1)); printf '%s\t-\t-\t-\t-\tfailed (exit %s)\n' "$_sid" "$_rc" ;;
    esac
  done < "$T/systems"
  log_note "fleet: $_tot_d dangling and $_tot_s stale across the judged checkouts; $_skip not judged"
  log_end || :; exit 0
fi

# ── judge a checkout ─────────────────────────────────────────────────────────
[ -f "$CONTROLS" ] || unchecked "no controls.tsv at $CONTROLS, so the modes are unknown" "ls $REG"
build_systems
: > "$T/absent"
judge
run || { log_end || :; exit 1; }
log_end || :
exit 0
