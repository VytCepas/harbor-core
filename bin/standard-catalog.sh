#!/usr/bin/env sh
# standard-catalog.sh (harbor#996 D1-D3) — the catalog: every tracked file placed on the D-57 levels, read from the registry.
#
#   sh bin/standard-catalog.sh --census        write build/catalog.tsv (one row per tracked file) and build/catalog-findings.tsv
#   sh bin/standard-catalog.sh --map           write docs/context-map.md from the catalog
#   sh bin/standard-catalog.sh --check         exit 0 if docs/context-map.md equals a fresh map, 1 if stale or absent
#   sh bin/standard-catalog.sh --find <term>   the scripts, tests, checks, docs and controls of a family, subsystem, domain or system
#   sh bin/standard-catalog.sh --tree [<term>] [--files]
#                                              the seven levels (metasystem > ... > element) as a tree; <term> narrows it
#   sh bin/standard-catalog.sh --targets       every instance and its kind, `<node> TAB <kind>`: each placed file, each control as
#                                              control:<id> (the graph's node names); the shape validator's target set (harbor#996 G2)
#   options: --root <dir> (the harbor tree; default this checkout) · --system <name> (default harbor) · --out <file> (--census)
#   exit 0 ok · 1 stale, absent, or no such term · 2 usage · 3 unchecked (no git, awk or registry)
#   `harbor find` and `harbor tree` are --find and --tree.
#
# COLUMNS of catalog.tsv, no header so `wc -l` is the row count: id path system domain subsystem family kind layer lifecycle owner purpose
#   id         <system>:<path>, the graph's node name (graph-gen.sh)
#   system     --system; domain is the term the system's codename is an alias of (aliases.tsv)
#   subsystem  the first non-family ancestor of the family in terms.tsv (the `broader` chain)
#   family     a kind that has one owner (standard, policy, eval, injection rule), the directory (tests/<family>, skills/<name>),
#              the first word of the name, then renames.tsv, the suite's subject and the control whose engine it is
#   kind       the longest kinds.tsv folder that holds the path; layer and lifecycle come from that row, or `generated` when
#              the file's first lines say so
#   owner      the family that answers for it (controls.tsv's definition of owner)
#   purpose    the first comment line or heading, at most 110 bytes; `-` when there is none
# A level column the registry cannot fill is `-`, and build/catalog-findings.tsv has a row naming the path, the columns and why.
# The census is a file census: rows equal `git ls-files`. Controls (lint rules, checks) are read from controls.tsv by --find and --tree.
#
# DELIBERATELY ONE FILE (DOCTRINE/modularity.md): the census, the three views and the map share one reading of the registry
# (families, the subsystem walk, kinds); split, each would carry a copy of it, and a copy is what drifts. POSIX sh and awk, so it
# runs where the lint runs (no python3).
set -eu
LC_ALL=C; export LC_ALL

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
. "$SRC/log-lib.sh"
LOG_FD=2; log_init standard-catalog

usage() { sed -n '2,13p' "$SRC/standard-catalog.sh" | sed 's/^# \{0,1\}//'; }
die() { log_fail "$1"; log_fix "$2"; log_end || :; exit "${3:-2}"; }

MODE=""; ROOT=""; SYSTEM=harbor; OUT=""; TERM_ARG=""; FILES=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --census) MODE=census ;;
    --map) MODE=map ;;
    --check) MODE=check ;;
    --find) MODE=find ;;
    --tree) MODE=tree ;;
    --targets) MODE=targets ;;
    --files) FILES=1 ;;
    --root) [ "$#" -ge 2 ] || die "--root needs a directory" "sh bin/standard-catalog.sh --help"; ROOT="$2"; shift ;;
    --system) [ "$#" -ge 2 ] || die "--system needs a name" "sh bin/standard-catalog.sh --help"; SYSTEM="$2"; shift ;;
    --out) [ "$#" -ge 2 ] || die "--out needs a file" "sh bin/standard-catalog.sh --help"; OUT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option $1" "sh bin/standard-catalog.sh --help" ;;
    *) [ -z "$TERM_ARG" ] || die "unexpected argument $1" "sh bin/standard-catalog.sh --help"; TERM_ARG="$1" ;;
  esac
  shift
done
[ -n "$MODE" ] || die "say what to do: --census, --map, --check, --find, --tree or --targets" "sh bin/standard-catalog.sh --help"
if [ "$MODE" = find ] && [ -z "$TERM_ARG" ]; then die "--find needs a term" "harbor find drift"; fi
if [ -n "$TERM_ARG" ] && [ "$MODE" != find ] && [ "$MODE" != tree ]; then die "unexpected argument $TERM_ARG" "sh bin/standard-catalog.sh --help"; fi
if [ "$FILES" = 1 ] && [ "$MODE" != tree ]; then die "--files only qualifies --tree" "harbor tree --files drift"; fi
case "$SYSTEM" in ''|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*) die "--system is a lowercase kebab name" "sh bin/standard-catalog.sh --system harbor --census" ;; esac

[ -n "$ROOT" ] || ROOT="$SRC/.."
ROOT="$(CDPATH= cd -- "$ROOT" 2>/dev/null && pwd -P)" || die "--root is not a directory" "pass a checkout: --root <dir>"
REG="$ROOT/standards/naming"
command -v git >/dev/null 2>&1 || die "git is not on PATH: nothing was catalogued" "install git" 3
command -v awk >/dev/null 2>&1 || die "awk is not on PATH: nothing was catalogued" "install awk" 3
for _f in terms kinds controls aliases; do
  [ -f "$REG/$_f.tsv" ] || die "$REG/$_f.tsv is absent: the levels are read from the registry, so nothing was catalogued" "run it in a harbor checkout, or --root <dir>" 3
done
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git checkout: the census is git ls-files" "run it in a harbor checkout, or --root <dir>" 3

TMP="$(mktemp -d "${TMPDIR:-/tmp}/standard-catalog.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM
TAB="$(printf '\t')"

# ---- the awk programs. lib.awk is shared; census.awk and view.awk each load it. -------------------------
cat > "$TMP/lib.awk" <<'AWK'
function hascls(s, c) { return index("," s ",", "," c ",") > 0 }
function terms_line() {
  if ($0 ~ /^#/ || $1 == "id" || NF < 4) return
  cls[$1] = $2; brd[$1] = $4
  if (hascls($2, "family")) isfam[$1] = 1
  if (hascls($2, "system")) issys[$1] = 1
  if (hascls($2, "level")) islvl[$1] = 1
}
# The subsystem of a family: the first ancestor on the `broader` chain that is not itself a family (D-17, D-57).
function subsys_of(f,   c, i) {
  c = brd[f]
  for (i = 0; i < 20 && c != "" && c != "-" && (c in isfam); i++) c = brd[c]
  if (c == "" || c == "-" || (c in islvl)) return ""
  return c
}
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
AWK

cat > "$TMP/census.awk" <<'AWK'
BEGIN { FS = "\t"; OFS = "\t"; NR_ROWS = 0 }
F == "terms" { terms_line(); next }
F == "kinds" {
  if ($0 ~ /^#/ || $1 == "id" || NF < 8) next
  kid[$1] = 1; klayer[$1] = $6; klevel[$1] = $7; klife[$1] = $8
  f = $2
  # a lint-rule or a check is a controls.tsv row, not a file: it holds no folder of files
  if (f != "-" && f !~ /</ && $1 != "lint-rule" && $1 != "check") { lf = tolower(f); if (!(lf in fk)) { fk[lf] = $1; nf++; flist[nf] = lf } }
  next
}
F == "controls" {
  if ($0 ~ /^#/ || $1 == "id" || NF < 10) next
  if ($4 != "-") { if (!($4 in eng)) eng[$4] = $10; else if (eng[$4] != $10) eng[$4] = "*" }
  next
}
F == "renames" { if ($0 ~ /^#/ || $1 == "id" || NF < 3) next; rn[$2] = $3; rn[$3] = $3; next }
F == "aliases" { if ($0 ~ /^#/ || $1 == "id" || NF < 2) next; if ($1 == SYSTEM && ($2 in cls)) sysdom = $2; next }
F == "paths" {
  if ($0 ~ /^#/ || $0 ~ /^[ \t]*$/) next
  n = split($0, a, " ")
  for (i = 2; i <= n; i++)
    if (a[i] ~ /^bin\// && a[i] !~ /[*]/ && a[i] !~ /-lib\.sh$/ && a[i] !~ /^bin\/(harbor|log-lib)/) { subj[a[1]] = a[i]; break }
  next
}
F == "files" { one($0); next }
END { close_all() }

function close_all() { }
# the first word of a name, when it is a registered family; "" otherwise
function fw(s,   t) { t = tolower(s); sub(/[-._].*/, "", t); return (t in isfam) ? t : "" }
function stem_of(b,   t) { t = tolower(b); sub(/\..*/, "", t); sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-/, "", t); return t }

function kind_of(p, base,   lp, i, best, bl, f, k, ext) {
  lp = tolower(p); best = ""; bl = 0
  for (i = 1; i <= nf; i++) {
    f = flist[i]
    if (substr(f, length(f), 1) == "/") { if (substr(lp, 1, length(f)) == f && length(f) > bl) { best = f; bl = length(f) } }
    else if (lp == f) { best = f; bl = 9999 }
  }
  k = ""
  if (best == "bin/") k = (base ~ /-hook\.[a-z]+$/) ? "hook" : "script"
  else if (best == "registries/") k = "registry"
  else if (best != "") k = fk[best]
  if (k == "contract" && p ~ /\.(tsv|txt)$/) k = "registry"
  if (k == "") {
    # the pre-standard spellings of folders kinds.tsv names (folder -> kind), kept honest by the kid[] test
    if (lp ~ /^(hooks|githooks)\//) k = "hook"
    else if (lp ~ /^(inject\.d|\.claude\/inject\.d)\//) k = "injection-rule"
    else if (lp ~ /^doctrine\//) k = "policy"
    else if (lp ~ /^evals-data\//) k = "eval"
    else if (lp ~ /^vendor\/skills\//) k = "skill"
    else if (lp ~ /^docs\/audits\//) k = "report"
    else if (lp ~ /^handoff(-archive)?\.md$/) k = "handover"
    else if (lp == "constitution.md") k = "policy"
  }
  if (k != "" && !(k in kid)) k = ""
  return k
}

function text_ext(ext, p) {
  if (p ~ /^vendor\//) return 0
  return (ext ~ /^(sh|bash|zsh|py|awk|mjs|js|ts|md|tsv|txt|json|yml|yaml|plist|html|toml|conf|service|timer)$/)
}

# Reads the head of a file: GEN (its first lines say generated), PURPOSE (its first comment line or heading).
function head_scan(p, ext, base,   path, line, n, fm, t, l, pl) {
  GEN = 0; PURPOSE = ""; col = 0; cl = 0
  if (!text_ext(ext, p) && !(ext == "" && p ~ /^(bin|hooks|githooks)\//)) return
  path = ROOT "/" p; n = 0; fm = 0; pl = 0
  while ((getline line < path) > 0 && n < 40) {
    n++
    l = tolower(line)
    if (n <= 8 && (l ~ /do not edit/ || l ~ /^[#<!\/ *-]*generated (by|from)/)) GEN = 1
    if (col) {   # a purpose that runs on to the next comment lines: join up to three, until a sentence ends
      if (line ~ /^[#;]|^\/\/|^--/) {
        t = line; sub(/^[#;\/-]+[ \t]*/, "", t)
        if (t != "" && PURPOSE !~ /[.?!:]$/ && length(PURPOSE) < 110 && ++cl < 3) { PURPOSE = PURPOSE " " t; continue }
      }
      col = 0
    }
    if (PURPOSE != "") { if (n >= 8) break; continue }
    if (n == 1 && line ~ /^#!/) continue
    if (n == 1 && line == "---") { fm = 1; continue }
    if (fm) { if (line == "---") fm = 0; else if (line ~ /^description:/) { t = line; sub(/^description:[ \t]*/, "", t); gsub(/^["']|["']$/, "", t); PURPOSE = t } ; continue }
    if (ext == "md") { if (line ~ /^# /) PURPOSE = substr(line, 3); continue }
    if (ext == "html") { if (line ~ /<title>/) { t = line; sub(/.*<title>/, "", t); sub(/<\/title>.*/, "", t); PURPOSE = t } ; continue }
    if (line ~ /^[ \t]*$/) continue
    if (line ~ /^[#;]|^\/\/|^--/) {
      t = line; sub(/^[#;\/-]+[ \t]*/, "", t)
      if (t == "" || t ~ /^(shellcheck|vim:|-\*-|!)/ || t ~ /^=+$/ || t ~ /^-+$/) continue
      sub(/^[A-Za-z0-9_.\/-]+ \([^)]*\) +(—|--|-) +/, "", t)
      sub(/^[A-Za-z0-9_.\/-]+ +(—|--|-) +/, "", t)
      PURPOSE = t; col = 1; cl = 0
    } else if (n > 3) { break }
  }
  close(path)
  t = PURPOSE
  sub(/^[A-Za-z0-9_.\/-]+ \([^)]*\) +(—|--|-) +/, "", t)
  sub(/^[A-Za-z0-9_.\/-]+ +(—|--|-) +/, "", t)
  gsub(/[\t\r]/, " ", t); t = trim(t)
  if (match(t, /[.?!]( |$)/) && RSTART > 12) t = substr(t, 1, RSTART)
  if (length(t) > 110) { t = substr(t, 1, 110); sub(/ +[^ ]*$/, "", t) }
  PURPOSE = t
}

# Family of a path, with the way it was found in FVIA and the reason it was not in FWHY.
function resolve_family(p, kind, base, stem,   n, seg, d, f, t, nm) {
  FVIA = ""; FWHY = ""
  n = split(p, seg, "/")
  if (kind == "standard" || kind == "decision-record") { if ("standard" in isfam) { FVIA = "kind"; return "standard" } }
  if (kind == "policy" && ("policy" in isfam)) { FVIA = "kind"; return "policy" }
  if (kind == "eval" && ("eval" in isfam)) { FVIA = "kind"; return "eval" }
  if (kind == "injection-rule" && ("context" in isfam)) { FVIA = "kind"; return "context" }
  if (p ~ /^vendor\/skills\// && ("skill" in isfam)) { FVIA = "kind"; return "skill" }
  if (p ~ /^vendor\// && kind != "skill") { FWHY = "vendored tree (D-52): a world-name, no family of ours"; return "" }
  if (p ~ /^launchd\/com\.[a-z0-9]+\.[a-z0-9-]+\./) { split(base, d, "."); f = fw(d[3]); if (f != "") { FVIA = "launchd"; return f } }
  if (kind == "test" && seg[1] == "tests" && n >= 3 && (tolower(seg[2]) in isfam)) { FVIA = "tests dir"; return tolower(seg[2]) }
  if (kind == "skill") {
    nm = (seg[1] == "vendor") ? seg[3] : seg[2]
    f = fw(nm); if (f != "") { FVIA = "skill dir"; return f }
    FWHY = "skill " nm " starts with '" firstword(nm) "', not a registered family"; return ""
  }
  if (kind == "fixture" && seg[1] == "fixtures" && n >= 3 && (tolower(seg[2]) in isfam)) { FVIA = "fixtures dir"; return tolower(seg[2]) }
  f = fw(stem); if (f != "") { FVIA = "name"; return f }
  if (kind == "test" && (p in subj)) {
    t = subj[p]; n = split(t, d, "/"); f = fw(stem_of(d[n]))
    if (f != "") { FVIA = "suite subject"; return f }
  }
  if (p in rn) { n = split(rn[p], d, "/"); f = fw(stem_of(d[n])); if (f != "") { FVIA = "renames"; return f } }
  if ((p in eng) && eng[p] != "*" && (eng[p] in isfam)) { FVIA = "control engine"; return eng[p] }
  FWHY = "first word '" firstword(stem) "' of " base " is not a registered family"
  return ""
}
function firstword(s,   t) { t = tolower(s); sub(/[-._].*/, "", t); return t }

function one(p,   n, seg, base, stem, ext, kind, fam, sub_, dom, layer, life, owner, miss, why, id) {
  n = split(p, seg, "/"); base = seg[n]; stem = stem_of(base)
  ext = base; if (ext ~ /\./) { sub(/^.*\./, "", ext); ext = tolower(ext) } else ext = ""
  kind = kind_of(p, base)
  head_scan(p, ext, base)
  if (kind == "" && GEN) kind = ("generated-doc" in kid) ? "generated-doc" : ""
  fam = resolve_family(p, kind, base, stem)
  miss = ""; why = ""
  if (kind == "") { miss = miss ",kind"; why = why "; kind: " ((p ~ /^vendor\//) ? "vendored tree (D-52) has no kind" : (n > 1) ? "no kinds.tsv folder holds " seg[1] "/" : p " sits at the repo root, in no kinds.tsv row") }
  if (kind != "") { layer = klayer[kind]; life = klife[kind] } else { layer = ""; life = "" }
  if (GEN) { layer = "generated"; life = "generated" }
  if (layer == "" || layer == "-") { layer = "-"; miss = miss ",layer"; why = why "; layer: needs a kind" }
  if (life == "" || life == "-") { life = "-"; miss = miss ",lifecycle"; why = why "; lifecycle: needs a kind" }
  if (fam == "") { fam = "-"; miss = miss ",family"; why = why "; family: " FWHY }
  sub_ = (fam != "-") ? subsys_of(fam) : ""
  if (sub_ == "") { sub_ = "-"; miss = miss ",subsystem"; why = why "; subsystem: " ((fam == "-") ? "needs a family" : "family " fam " has no subsystem in terms.tsv") }
  owner = fam
  if (owner == "-") { miss = miss ",owner"; why = why "; owner: needs a family" }
  dom = sysdom
  if (dom == "") { dom = "-"; miss = miss ",domain"; why = why "; domain: aliases.tsv has no row for " SYSTEM }
  if (PURPOSE == "") PURPOSE = "-"
  print SYSTEM ":" p, p, SYSTEM, dom, sub_, fam, (kind == "" ? "-" : kind), layer, life, owner, PURPOSE
  if (miss != "") print p, substr(miss, 2), substr(why, 3) > FINDINGS
}
AWK

# ---- the registry operands, in the order the programs expect -------------------------------------------
_opt() { if [ -f "$1" ]; then printf '%s' "$1"; else printf '%s' /dev/null; fi; }

# the file list: git ls-files, plus the map itself (the map is part of the tree it describes, so it is counted before it is tracked)
_files() {
  git -C "$ROOT" ls-files > "$TMP/ls.raw"
  { cat "$TMP/ls.raw"; printf 'docs/context-map.md\n'; } | sort -u > "$TMP/files"
}

# <catalog-out> <findings-out>
_census() {
  _files
  : > "$2"
  _sp="$ROOT/CONTRACTS/suite-paths.txt"; [ -f "$_sp" ] || _sp="$ROOT/contracts/suite-paths.txt"
  awk -f "$TMP/lib.awk" -f "$TMP/census.awk" -v ROOT="$ROOT" -v SYSTEM="$SYSTEM" -v FINDINGS="$2" \
    F=terms "$REG/terms.tsv" F=kinds "$REG/kinds.tsv" F=controls "$REG/controls.tsv" \
    F=renames "$(_opt "$REG/renames.tsv")" F=aliases "$REG/aliases.tsv" \
    F=paths "$(_opt "$_sp")" F=files "$TMP/files" > "$1.part"
  # an error in the awk program must not leave a half catalog that reads as complete
  [ -s "$1.part" ] || die "the census produced no rows" "run it in a harbor checkout, or --root <dir>" 3
  mv "$1.part" "$1"
  sort -o "$2" "$2"
}

# ---- views: find, tree, map ----------------------------------------------------------------------------
cat > "$TMP/view.awk" <<'AWK'
BEGIN { FS = "\t"; OFS = "\t" }
F == "terms" { terms_line(); next }
F == "kinds" {
  if ($0 ~ /^#/ || $1 == "id" || NF < 8) next
  nk++; kord[nk] = $1; kfold[$1] = $2; klayer[$1] = $6; klevel[$1] = $7; klife[$1] = $8
  next
}
F == "controls" {
  if ($0 ~ /^#/ || $1 == "id" || NF < 13) next
  nc++; cid[nc] = $1; cmode[nc] = $2; ctype[nc] = $3; cowner[nc] = $10; ctitle[nc] = $13
  next
}
F == "findings" { if (NF >= 3) { nfd++; fcols[nfd] = $2; fwhy[nfd] = $3; fpath[nfd] = $1 } next }
F == "cat" {
  nr++; rp[nr] = $2; rsys[nr] = $3; rdom[nr] = $4; rsub[nr] = $5; rfam[nr] = $6; rkind[nr] = $7; rlayer[nr] = $8; rlife[nr] = $9; rpur[nr] = $11
  next
}
END {
  if (MODE == "find") do_find()
  else if (MODE == "targets") do_targets()
  else if (MODE == "tree") do_tree()
  else if (MODE == "map") do_map()
}

function isdoc(k) { return (k ~ /^(design|plan|runbook|report|handover|context-map|generated-doc|decision-record|contract|standard|policy)$/) }
function section_of(k) {
  if (k == "script" || k == "hook") return 1
  if (k == "test") return 2
  if (isdoc(k)) return 4
  return 6
}
function secname(s) { return (s == 1) ? "script" : (s == 2) ? "test" : (s == 3) ? "check" : (s == 4) ? "doc" : (s == 5) ? "control" : "other" }

# the way a --find or --tree term selects: a family, a subsystem, a domain or a system
function classify(t,   i) {
  if (t in isfam) return "family"
  for (i = 1; i <= nr; i++) if (rsub[i] == t) return "subsystem"
  for (i = 1; i <= nr; i++) if (rdom[i] == t) return "domain"
  for (i = 1; i <= nr; i++) if (rsys[i] == t) return "system"
  if (t in issys) { uncat = 1; return "system" }   # registered in terms.tsv, catalogued in another checkout: found, with nothing to list here
  return ""
}
function member(i, t, how) {
  if (how == "family") return rfam[i] == t
  if (how == "subsystem") return rsub[i] == t
  if (how == "domain") return rdom[i] == t
  return rsys[i] == t
}
function ctl_member(i, t, how,   o) {
  o = cowner[i]
  if (uncat) return 0   # a system catalogued elsewhere owns none of this checkout's controls
  if (how == "family") return o == t
  if (how == "subsystem") return ((o in isfam) && subsys_of(o) == t)
  return 1
}

function do_find(   how, i, n, s, sub_) {
  how = classify(TERM)
  if (how == "") { print "no such family, subsystem, domain or system: " TERM > "/dev/stderr"; exit 1 }
  n = 0
  for (i = 1; i <= nr; i++) if (member(i, TERM, how)) {
    s = section_of(rkind[i]); n++
    print s, ((s == 6) ? (rkind[i] != "-" ? rkind[i] : "other") : secname(s)), rp[i], rpur[i]
  }
  for (i = 1; i <= nc; i++) if (ctl_member(i, TERM, how)) {
    s = (ctype[i] == "check") ? 3 : 5; n++
    print s, secname(s), cid[i], cmode[i] " " (s == 5 ? ctype[i] ": " : "") ctitle[i]
  }
  sub_ = (how == "family" ? subsys_of(TERM) : "")
  print 0, "find " TERM " (" how (sub_ != "" ? "; subsystem " sub_ : "") ")", n " entries", ""
}

# ---- targets: what a shape (kinds.tsv required_relations) is checked on. A file the census could not place is no
# instance of any kind, and its finding already says why; a control is an instance of the kind its type names.
function do_targets(   i) {
  for (i = 1; i <= nr; i++) if (rkind[i] != "-") print SYSTEM ":" rp[i], rkind[i]
  for (i = 1; i <= nc; i++) print "control:" cid[i], ctl_kind(ctype[i])
}

# ---- tree ----
function ctl_kind(t) { return (t == "lint") ? "lint-rule" : (t == "check") ? "check" : (t == "injection") ? "injection-rule" : (t == "ci") ? "ci-gate" : (t == "vale") ? "vale-rule" : t "-rule" }
function lvl_chain(   t, root, ch, c, i, guard) {
  for (t in islvl) if (brd[t] == "-" || brd[t] == "") root = t
  ch = root; c = root
  for (guard = 0; guard < 12; guard++) {
    nxt = ""
    for (t in islvl) if (brd[t] == c) nxt = t
    if (nxt == "") break
    ch = ch " › " nxt; c = nxt
  }
  return ch
}
function ind(n,   s, i) { s = ""; for (i = 0; i < n; i++) s = s "  "; return s }
function sortn(a, n,   i, j, t) { for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]; a[j + 1] = t } }

function do_tree(   how, i, j, k, nfm, fams, f, nsub, subs, s, cnt, ndom, doms, d, nsys, syss, e, ukey, un, nsl, sl, lv, kinds_, nkk, key, c, ct, ce, b) {
  how = (TERM == "") ? "all" : classify(TERM)
  if (how == "") { print "no such family, subsystem, domain or system: " TERM > "/dev/stderr"; exit 1 }
  print "tree: " lvl_chain() " (D-57)"
  # which systems exist: the catalog's, plus every system term
  for (i = 1; i <= nr; i++) { if (!(rdom[i] in dseen)) { dseen[rdom[i]] = 1; ndom++; doms[ndom] = rdom[i] } ; ssys[rdom[i] SUBSEP rsys[i]] = 1 }
  for (t in issys) { d = brd[t]; if (d == "" || d == "-") continue; if (!(d in dseen)) { dseen[d] = 1; ndom++; doms[ndom] = d }; if (!((d SUBSEP t) in ssys)) ext[d SUBSEP t] = 1 }
  sortn(doms, ndom)
  for (t in islvl) if (brd[t] == "-" || brd[t] == "") rootlvl = t
  print rootlvl
  for (j = 1; j <= ndom; j++) {
    d = doms[j]
    if (how == "domain" && TERM != d) continue
    if ((how == "system" || how == "subsystem" || how == "family") && !tree_has_domain(d)) continue
    print ind(1) "domain  " d
    # systems of this domain
    nsys = 0
    for (i = 1; i <= nr; i++) { key = rdom[i] SUBSEP rsys[i]; if (rdom[i] == d && !(key in sysdone)) { sysdone[key] = 1; nsys++; syss[nsys] = rsys[i] } }
    for (k in ext) { split(k, e, SUBSEP); if (e[1] == d && how != "subsystem" && how != "family") { nsys++; syss[nsys] = e[2] } }
    sortn(syss, nsys)
    for (s = 1; s <= nsys; s++) {
      if (how == "system" && TERM != syss[s]) continue
      if (!((d SUBSEP syss[s]) in ssys)) { print ind(2) "system  " syss[s] "  (not in this tree)"; continue }
      print ind(2) "system  " syss[s]
      tree_system(d, syss[s], how)
    }
  }
}
function tree_has_domain(d,   i) { if (how_g() == "system" && ((d SUBSEP TERM) in ext)) return 1; for (i = 1; i <= nr; i++) if (rdom[i] == d && member(i, TERM, how_g())) return 1; return 0 }
function how_g() { return classify(TERM) }

function tree_system(d, sy, how,   i, k, nsl, sl, nsub, subs, sb, nf, fams, f, un, line) {
  # system-level kinds sit on the system node itself (kinds.tsv: level system)
  if (how == "all" || how == "domain" || how == "system") {
    nsl = 0; delete slc
    for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rkind[i] != "-" && klevel[rkind[i]] == "system") {
      if (!(rkind[i] in slc)) { nsl++; sl[nsl] = rkind[i] }
      slc[rkind[i]]++
    }
    sortn(sl, nsl)
    for (k = 1; k <= nsl; k++) print ind(3) "system artifact  " sl[k] "  (" slc[sl[k]] ")"
    if (FILES) for (k = 1; k <= nsl; k++) for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rkind[i] == sl[k]) print ind(4) rp[i]
  }
  # subsystems
  nsub = 0; delete sdone
  for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rsub[i] != "-" && !(rsub[i] in sdone)) { sdone[rsub[i]] = 1; nsub++; subs[nsub] = rsub[i] }
  sortn(subs, nsub)
  for (k = 1; k <= nsub; k++) {
    sb = subs[k]
    if (how == "subsystem" && TERM != sb) continue
    if (how == "family" && subsys_of(TERM) != sb) continue
    print ind(3) "subsystem  " sb
    nf = 0; delete fdone
    for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rsub[i] == sb && !(rfam[i] in fdone)) { fdone[rfam[i]] = 1; nf++; fams[nf] = rfam[i] }
    for (i = 1; i <= nc; i++) if ((cowner[i] in isfam) && subsys_of(cowner[i]) == sb && !(cowner[i] in fdone)) { fdone[cowner[i]] = 1; nf++; fams[nf] = cowner[i] }
    sortn(fams, nf)
    for (i = 1; i <= nf; i++) {
      if (how == "family" && TERM != fams[i]) continue
      tree_family(d, sy, fams[i])
    }
  }
  if (how == "all" || how == "domain" || how == "system") {
    un = 0
    for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rsub[i] == "-" && (rkind[i] == "-" || klevel[rkind[i]] != "system")) un++
    if (un > 0) print ind(3) "unassigned  " un " files with no family (sh bin/standard-catalog.sh --census says why, per path)"
  }
}

function tree_family(d, sy, f,   i, k, lv, nkk, kk, cnt, nm, files_, nfl) {
  nfl = 0
  for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rfam[i] == f) nfl++
  print ind(4) "family  " f "  (" nfl " files)"
  for (lv = 1; lv <= 2; lv++) {
    nkk = 0; delete kcnt; delete kk
    for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rfam[i] == f) {
      nm = rkind[i]
      if (nm == "-") { if (lv != 1) continue; nm = "unclassified" }
      else if (klevel[nm] != (lv == 1 ? "component" : "element")) continue
      if (!(nm in kcnt)) { nkk++; kk[nkk] = nm }
      kcnt[nm]++
    }
    if (lv == 2) for (i = 1; i <= nc; i++) if (cowner[i] == f) { nm = ctl_kind(ctype[i]); if (!(nm in kcnt)) { nkk++; kk[nkk] = nm }; kcnt[nm]++ }
    sortn(kk, nkk)
    for (k = 1; k <= nkk; k++) {
      print ind(4 + lv) (lv == 1 ? "component  " : "element  ") kk[k] "  (" kcnt[kk[k]] ")"
      if (FILES) {
        for (i = 1; i <= nr; i++) if (rdom[i] == d && rsys[i] == sy && rfam[i] == f && ((rkind[i] == "-" ? "unclassified" : rkind[i]) == kk[k])) print ind(5 + lv) rp[i]
        for (i = 1; i <= nc; i++) if (cowner[i] == f && ctl_kind(ctype[i]) == kk[k]) print ind(5 + lv) cid[i]
      }
    }
  }
}

# ---- map ----
function do_map(   i, j, k, n, kc, nkn, kn, nfam, fam, fc, tops, nt, tp, tc, tk, a, b, c, s, w, fcount, cfam, nfd2) {
  print "---"
  print "kind: context-map"
  print "status: generated"
  print "owner_issue: 996"
  print "layer: generated"
  print "---"
  print ""
  print "# Context map"
  print ""
  print "Where every tracked file sits on the levels of D-57, generated from the catalog; do not edit."
  print ""
  print "Regenerate with `sh bin/standard-catalog.sh --map`; `sh bin/standard-catalog.sh --check` is red when this file is stale."
  print "Ask the catalog instead of reading this page: `harbor find <family>` lists a family's scripts, tests, checks, docs and controls,"
  print "`harbor tree` renders the levels, and `sh bin/standard-catalog.sh --census` writes `build/catalog.tsv` with every row and"
  print "`build/catalog-findings.tsv` with every level the registry could not fill. The README and HANDOFF sections that describe the"
  print "layout stay; this page adds to them and never replaces them."
  print ""
  print "## Levels"
  print ""
  print lvl_chain()
  print ""
  print "System `" SYSTEM "` sits in domain `" (nr > 0 ? rdom[1] : "-") "`. A file's subsystem is read from its family's `broader` chain in `standards/naming/terms.tsv`."
  print ""
  print "## Kinds and where they live"
  print ""
  print "| Kind | Folder | Level | Layer | Lifecycle | Files |"
  print "|---|---|---|---|---|---|"
  for (i = 1; i <= nk; i++) {
    n = 0; for (j = 1; j <= nr; j++) if (rkind[j] == kord[i]) n++
    if (n > 0) print "| " kord[i] " | " kfold[kord[i]] " | " klevel[kord[i]] " | " klayer[kord[i]] " | " klife[kord[i]] " | " n " |"
  }
  n = 0; for (j = 1; j <= nr; j++) if (rkind[j] == "-") n++
  if (n > 0) print "| (no kind) | - | - | - | - | " n " |"
  print ""
  print "## Folders"
  print ""
  print "| Folder | Files | Families | Kinds |"
  print "|---|---|---|---|"
  nt = 0
  for (i = 1; i <= nr; i++) {
    tp = rp[i]; if (index(tp, "/") > 0) { sub(/\/.*/, "/", tp) } else tp = "(root)"
    if (!(tp in tc)) { nt++; tops[nt] = tp }
    tc[tp]++
    if (!((tp SUBSEP rfam[i]) in tf)) { tf[tp SUBSEP rfam[i]] = 1; tfn[tp]++ }
    if (!((tp SUBSEP rkind[i]) in tkk)) { tkk[tp SUBSEP rkind[i]] = 1; tkn[tp]++ }
  }
  sortn(tops, nt)
  for (i = 1; i <= nt; i++) print "| " (tops[i] == "(root)" ? "(repo root)" : "`" tops[i] "`") " | " tc[tops[i]] " | " tfn[tops[i]] " | " tkn[tops[i]] " |"
  print ""
  # families that own anything
  nfam = 0
  for (i = 1; i <= nr; i++) if (rfam[i] != "-" && !(rfam[i] in fseen)) { fseen[rfam[i]] = 1; nfam++; fam[nfam] = rfam[i] }
  for (i = 1; i <= nc; i++) if ((cowner[i] in isfam) && !(cowner[i] in fseen)) { fseen[cowner[i]] = 1; nfam++; fam[nfam] = cowner[i] }
  for (t in isfam) if (!(t in fseen)) { fseen[t] = 1; nfam++; fam[nfam] = t }
  sortn(fam, nfam)
  print "## Families"
  print ""
  print "| Family | Subsystem | Scripts | Tests | Docs | Other files | Checks | Controls |"
  print "|---|---|---|---|---|---|---|---|"
  for (i = 1; i <= nfam; i++) {
    f = fam[i]; a = 0; b = 0; c = 0; o = 0; ck = 0; ct = 0
    for (j = 1; j <= nr; j++) if (rfam[j] == f) { s = section_of(rkind[j]); if (s == 1) a++; else if (s == 2) b++; else if (s == 4) c++; else o++ }
    for (j = 1; j <= nc; j++) if (cowner[j] == f) { if (ctype[j] == "check") ck++; else ct++ }
    print "| " f " | " subsys_of(f) " | " a " | " b " | " c " | " o " | " ck " | " ct " |"
  }
  print ""
  print "## Per family"
  print ""
  print "Scripts, hooks, docs and other files by path; tests, fixtures and eval data are counted above and not listed. A path's purpose is in `harbor find <family>`."
  for (i = 1; i <= nfam; i++) {
    f = fam[i]; n = 0
    for (j = 1; j <= nr; j++) if (rfam[j] == f && listed(rkind[j], rp[j])) n++
    if (n == 0) continue
    print ""
    print "### " f
    print ""
    for (j = 1; j <= nr; j++) if (rfam[j] == f && listed(rkind[j], rp[j])) print "- `" rp[j] "`"
  }
  # findings
  print ""
  print "## Not placed"
  print ""
  n = 0; for (j = 1; j <= nr; j++) if (rfam[j] == "-") n++
  print "Files whose family the registry cannot name yet (`build/catalog-findings.tsv` lists each with its reason), by top folder:"
  print ""
  nt = 0; delete tc2
  for (i = 1; i <= nr; i++) if (rfam[i] == "-") {
    tp = rp[i]; if (index(tp, "/") > 0) { sub(/\/.*/, "/", tp) } else tp = "(root)"
    if (!(tp in tc2)) { nt++; tops2[nt] = tp }
    tc2[tp]++
  }
  sortn(tops2, nt)
  print "| Folder | Files without a family |"
  print "|---|---|"
  for (i = 1; i <= nt; i++) print "| " (tops2[i] == "(root)" ? "(repo root)" : "`" tops2[i] "`") " | " tc2[tops2[i]] " |"
}
function listed(k, p) {
  if (k == "test" || k == "fixture" || k == "eval") return 0
  if (k == "skill" && p !~ /SKILL\.md$/) return 0
  return 1
}
AWK

_view() { # <mode> -> stdout; needs $TMP/catalog.tsv
  awk -f "$TMP/lib.awk" -f "$TMP/view.awk" -v MODE="$1" -v TERM="$TERM_ARG" -v SYSTEM="$SYSTEM" -v FILES="$FILES" \
    F=terms "$REG/terms.tsv" F=kinds "$REG/kinds.tsv" F=controls "$REG/controls.tsv" \
    F=findings "$TMP/findings.tsv" F=cat "$TMP/catalog.tsv"
}

# The top-level layout map (harbor#1272): CONTRACTS/layout-map.tsv joined with layers.tsv, so ship is read, never stored.
_layout() {
  [ -f "$ROOT/CONTRACTS/layout-map.tsv" ] || return 0
  printf '\n## Top-level layout\n\nEvery tracked top-level entry, its kind and layer from `CONTRACTS/layout-map.tsv`; Ships is read from `CONTRACTS/layers.tsv` (core ships in harbor-core, dev is box or dev data). `bin/lint-layout-map.sh` is red on an entry with no row.\n\n'
  printf '| Entry | Kind | Layer | Ships |\n|---|---|---|---|\n'
  HARBOR_ROOT="$ROOT" sh "$ROOT/bin/lint-layout-map.sh" --list | awk -F'\t' '{ printf "| `%s` | %s | %s | %s |\n", $1, $2, $3, ($4 == "core" ? "core" : "dev") }'
}

_build() { _census "$TMP/catalog.tsv" "$TMP/findings.tsv"; }

case "$MODE" in
  census)
    _build
    [ -n "$OUT" ] || OUT="$ROOT/build/catalog.tsv"
    mkdir -p "$(dirname -- "$OUT")"
    cp "$TMP/catalog.tsv" "$OUT"
    _fo="$(dirname -- "$OUT")/catalog-findings.tsv"
    cp "$TMP/findings.tsv" "$_fo"
    _rows="$(wc -l < "$OUT" | tr -d ' ')"; _fn="$(wc -l < "$_fo" | tr -d ' ')"
    log_ok "$_rows rows in ${OUT#"$ROOT"/}; $_fn paths with a level the registry could not fill, each named in ${_fo#"$ROOT"/}"
    log_end || :
    ;;
  map)
    _build
    mkdir -p "$ROOT/docs"
    { _view map; _layout; } > "$TMP/map.md"
    cp "$TMP/map.md" "$ROOT/docs/context-map.md"
    log_ok "wrote docs/context-map.md"
    log_end || :
    ;;
  check)
    _build
    { _view map; _layout; } > "$TMP/map.md"
    if [ ! -f "$ROOT/docs/context-map.md" ]; then
      log_fail "docs/context-map.md is absent"; log_fix "sh bin/standard-catalog.sh --map"; log_end || :; exit 1
    fi
    if cmp -s "$TMP/map.md" "$ROOT/docs/context-map.md"; then
      log_ok "docs/context-map.md equals a fresh map"; log_end || :
    else
      diff "$ROOT/docs/context-map.md" "$TMP/map.md" | sed -n '1,12p' >&2 || :
      log_fail "docs/context-map.md is stale: it differs from the catalog"; log_fix "sh bin/standard-catalog.sh --map"; log_end || :; exit 1
    fi
    ;;
  find)
    _build
    _view find > "$TMP/view.out" || exit 1
    sort -t "$TAB" -k1,1n -k3,3 "$TMP/view.out" | awk -F'\t' '$1 == 0 { print $2 ": " $3; next } { print $2 "\t" $3 "\t" $4 }'
    ;;
  tree)
    _build
    _view tree
    ;;
  targets)
    _build
    _view targets
    ;;
esac
