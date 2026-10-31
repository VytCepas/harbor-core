#!/usr/bin/env sh
# test-suite-cache.sh — a suite whose inputs already passed is reported cached, not re-run (harbor#1288)
#
#   sh test-suite-cache.sh lookup <queue> <keys> <hits>   gate the run, key each queued suite into <keys>, write a row per hit to <hits>
#   sh test-suite-cache.sh record <keys> <results>        keep a pass for each `pass` row whose key still holds after the run
#   sh test-suite-cache.sh key <suite>...                 each suite's key, or `-` and why it is never cached
#   sh test-suite-cache.sh manifest <suite>               the text that key hashes: a header, then `<oid> <path>` per input
#   sh test-suite-cache.sh undeclared [suite...]          paths a suite names (directly or through code it names) that its declaration misses
#
#   HARBOR_TEST_SUITE_CACHE_DIR   the store (default ${XDG_CACHE_HOME:-$HOME/.cache}/harbor/suite-cache)
#   HARBOR_TEST_SUITE_CACHE_DAYS  an entry no run has used for this many days is pruned (default 30)
#   HARBOR_TEST_SUITE_CACHE_SALT  any text, hashed into every key: changing it is a cold cache
#
# bin/test-suite-run.sh calls this only under HARBOR_SUITE_CACHE=1, so with the variable unset nothing here runs.
# The key, the store, what is trusted and what the key cannot see: contracts/suite-cache.md.
#
# A FALSE PASS IS THE DEFECT TO DESIGN AGAINST. A suite is served from the cache when every input the key
# holds is byte-identical to a run that passed, so an input the key does not hold is a change that cannot
# make it run. Every uncertainty here therefore resolves to RUN: an `always` or missing declaration, a
# suite that reads the checkout's own git state, a run selecting everything, a main run, a store this
# user did not write, an entry that does not parse. The key holds more than the declaration on purpose —
# every path the suite names, followed through the code it names — because declarations are written by
# hand and under-declare (`undeclared` lists what they miss).
set -eu

DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$DIR/.." && pwd)}}"
DECL="$ROOT/contracts/suite-paths.txt"
TAB="$(printf '\t')"
FORMAT=v1   # the entry and manifest format; bumping it is a cold cache
LC_ALL=C; export LC_ALL   # one sort order: a locale that moved between two runs must not move a key

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
[ $# -gt 0 ] || usage
case "$1" in -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;; esac
CMD="$1"; shift
# stdout is data for bin/test-suite-run.sh (a row file, one note line); a log line, when there is one, is log-lib's.
. "$DIR/library-log.sh"
log_init suite-cache

_td="${TMPDIR:-/tmp}"
W="$(mktemp -d "${_td%/}/suite-cache.XXXXXX")"
trap 'rm -rf "$W"' EXIT

_path() { case "$1" in */*) printf '%s' "$1" ;; *) printf 'bin/%s' "$1" ;; esac; }  # a manifest entry, repo-relative
_g() { git -C "$ROOT" -c core.quotePath=false "$@"; }

# ── the working tree as git sees it: <oid> TAB <path>, for every tracked and every untracked, unignored file ──
# The index's oid unless the file differs from it (then its content's, hashed by git), `absent` for a tracked
# file the tree has lost. Untracked files are in: a new fixture a suite globs is an input before it is committed.
_inventory() { # > $W/inv
  _g ls-files -s > "$W/idx"
  _g ls-files -m > "$W/mod"
  _g ls-files -d > "$W/del"
  _g ls-files -o --exclude-standard > "$W/new"
  # A quoted path (a tab, a newline, a quote in its name) would not match its declaration: refuse, never guess.
  if grep -q '^"' "$W/mod" "$W/del" "$W/new" 2>/dev/null || cut -f2 "$W/idx" | grep -q '^"'; then return 1; fi
  awk -v df="$W/del" 'FILENAME == df { d[$0] = 1; next } !($0 in d)' "$W/del" "$W/mod" > "$W/rehash"
  # Regular files only (an untracked nested repo lists as a directory), and one oid per path or no inventory:
  # a short answer from git would hand every later path its neighbour's oid.
  while IFS= read -r _p; do [ ! -f "$ROOT/$_p" ] || printf '%s\n' "$_p"; done < "$W/new" >> "$W/rehash"
  if [ -s "$W/rehash" ]; then _g hash-object --stdin-paths < "$W/rehash" > "$W/rehash.oid" || return 1; else : > "$W/rehash.oid"; fi
  [ "$(grep -c . "$W/rehash.oid" || :)" = "$(grep -c . "$W/rehash" || :)" ] || return 1
  awk -F '\t' -v OFS='\t' -v rf="$W/rehash" -v of="$W/rehash.oid" -v df="$W/del" '
    BEGIN { while ((getline p < rf) > 0) { getline o < of; h[p] = o }
            while ((getline p < df) > 0) gone[p] = 1 }
    { split($1, m, " "); p = $2; if (p in seen) next; seen[p] = 1
      print ((p in gone) ? "absent" : (p in h) ? h[p] : m[2]), p }
    END { for (p in h) if (!(p in seen)) print h[p], p }' "$W/idx" > "$W/inv"
}

# ── the trust domain: hashed into every key, so an entry is only ever found by the identity that wrote it ──
_domain() {
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    [ -n "${RUNNER_NAME:-}" ] || return 1
    printf 'ci:%s' "$RUNNER_NAME"
  else
    printf 'local:%s' "$(hostname 2>/dev/null || uname -n)"
  fi
}

# ── keys: <suite> TAB <key>, or <suite> TAB - TAB <why it is never cached>, for each suite in <file> ──
_keys() { # <suites-file> <out>
  _inventory || { awk -v OFS='\t' '{ print $1, "-", "no inventory of the tree: a path git quotes, or git could not hash it" }' "$1" > "$2"; return 0; }
  _dom="$(_domain)" || { awk -v OFS='\t' '{ print $1, "-", "under Actions with no RUNNER_NAME" }' "$1" > "$2"; return 0; }
  {
    printf 'harbor suite-cache %s\n' "$FORMAT"
    printf 'runner %s\n' "$(git hash-object "$DIR/test-suite-run.sh")"
    printf 'cache %s\n' "$(git hash-object "$DIR/test-suite-cache.sh")"
    printf 'trust %s\n' "$_dom"
    printf 'host %s\n' "$(uname -srm)"
    printf 'salt %s\n' "${HARBOR_TEST_SUITE_CACHE_SALT:-${HARBOR_SUITE_CACHE_SALT:-}}"
  } > "$W/head"
  # The references: every code file the suites name, followed, memoised across suites in one awk.
  awk -F '\t' -v root="$ROOT" -v inv="$W/inv" -v OFS='\t' '
    function norm(p,   n, a, i, k, o, s) {
      n = split(p, a, "/"); k = 0
      for (i = 1; i <= n; i++) {
        if (a[i] == "" || a[i] == ".") continue
        if (a[i] == "..") { if (k == 0) return ""; k--; continue }
        o[++k] = a[i]
      }
      s = ""; for (i = 1; i <= k; i++) s = s (i > 1 ? "/" : "") o[i]
      return s
    }
    function dirof(p) { return (p ~ /\//) ? substr(p, 1, match(p, /\/[^\/]*$/) - 1) : "" }
    # Followed: code. A data file the suite names is an input, but what it names is not run.
    function code(p) { return p ~ /\.(sh|awk|py|mjs|cjs|js|ts|bash|pl|rb)$/ || (p ~ /^(bin|hooks)\// && p !~ /\/[^\/]*\.[^\/]*$/) }
    function try(f, c) { if (c ~ /(^|\/)\.\.?(\/|$)|\/\/|^\//) c = norm(c); if (c != "" && (c in P) && !((f SUBSEP c) in E)) { E[f SUBSEP c] = 1; ed[f] = ed[f] " " c } }
    function scan(f,   line, d, n, t, i, s, x, k) {
      if (f in done) return
      done[f] = 1; ed[f] = ""
      if (!code(f)) return
      delete tk; d = dirof(f); js = (f ~ /\.(mjs|cjs|js|ts)$/)
      while ((getline line < (root "/" f)) > 0) {
        # A whole-line comment runs nothing: prose naming a tool is not a read of it, and following
        # prose drags most of the repo into every key. A comment at the end of a line is kept.
        if (js ? (line ~ /^[[:space:]]*\/\//) : (line ~ /^[[:space:]]*#/)) continue
        gsub(/[^A-Za-z0-9_.\/@+-]/, " ", line)
        n = split(line, t, " ")
        for (i = 1; i <= n; i++) {
          s = t[i]
          if (s !~ /[\/.]/ || (s in tk)) continue   # a word with neither names no file; a word seen is done
          tk[s] = 1
          # every /-suffix ($ROOT/bin/x.sh splits to ROOT/bin/x.sh), each tried from the root, the file and bin/
          while (1) {
            x = s; sub(/^(\.\/)+/, "", x)
            # bin/ only for a name with a dot ($BIN/x.sh): a bare word after a slash (owner/harbor) is not bin/harbor
            if (x != "") { try(f, x); if (d != "") try(f, d "/" x); if (x ~ /\./) try(f, "bin/" x) }
            k = index(s, "/"); if (!k) break
            s = substr(s, k + 1)
          }
        }
      }
      close(root "/" f)
    }
    BEGIN { while ((getline l < inv) > 0) { split(l, a, "\t"); P[a[2]] = 1 } }
    { s = $1; q[1] = s; nq = 1; h = 1; delete seen; seen[s] = 1
      while (h <= nq) { f = q[h++]; scan(f); m = split(ed[f], c, " ")
        for (i = 1; i <= m; i++) if (!(c[i] in seen)) { seen[c[i]] = 1; q[++nq] = c[i]; print s, c[i] } } }
  ' "$W/paths" > "$W/refs"
  # The manifests. Each output line is <n> TAB <class> TAB <text>: class 0 the suite and its declaration,
  # 1 an input (<oid> <path>), 8 a reference the declaration misses (for `undeclared`), - why it has no key.
  # Globs are `case` patterns where `*` crosses `/`, matched as bin/test-suite-select.sh matches them.
  awk -F '\t' -v OFS='\t' -v inv="$W/inv" -v decl="$DECL" -v refs="$W/refs" -v root="$ROOT" '
    function g2re(g,   r, i, n, c, j, cls) {
      r = "^"; n = length(g)
      for (i = 1; i <= n; i++) {
        c = substr(g, i, 1)
        if (c == "*") r = r ".*"
        else if (c == "?") r = r "."
        else if (c == "[" && (j = index(substr(g, i + 1), "]")) > 1) {
          cls = substr(g, i + 1, j - 1); if (substr(cls, 1, 1) == "!") cls = "^" substr(cls, 2)
          r = r "[" cls "]"; i += j
        }
        else if (c == "\\" && i < n) { i++; c = substr(g, i, 1); r = r ((c ~ /[A-Za-z0-9]/) ? c : "\\" c) }
        else if (c ~ /[.+(){}|^$\\\[\]]/) r = r "\\" c
        else r = r c
      }
      return r "$"
    }
    BEGIN {
      while ((getline l < inv) > 0) { split(l, a, "\t"); O[a[2]] = a[1]; IP[++np] = a[2] }
      while ((getline l < decl) > 0) {
        if (l ~ /^[[:space:]]*(#|$)/) continue
        n = split(l, a, " "); if (a[1] in D) continue       # the first row for a key wins, as in suite-select
        D[a[1]] = ""; for (i = 2; i <= n; i++) D[a[1]] = D[a[1]] (i > 2 ? " " : "") a[i]
      }
      while ((getline l < refs) > 0) { split(l, a, "\t"); R[a[1]] = R[a[1]] SUBSEP a[2] }
    }
    { s = $1; p = $2; n = NR
      if (!(s in D) || D[s] == "") { print n, "-", "no declaration in contracts/suite-paths.txt"; next }
      if (D[s] == "always") { print n, "-", "declared always: its inputs are not declared"; next }
      if (!(p in O) || O[p] == "absent") { print n, "-", "its file is not in the working tree"; next }
      git = 0
      while ((getline l < (root "/" p)) > 0) if (l ~ /git[^|;&]*-C[[:space:]]+"?[$][{]?T_ROOT[}]?"?([[:space:]\/]|$)/) { git = 1; break }
      close(root "/" p)
      if (git) { print n, "-", "it runs git on the checkout (git -C $T_ROOT), whose history the key does not hold"; next }
      delete in_
      m = split(D[s], g, " ")
      for (i = 1; i <= m; i++) {
        if (g[i] !~ /[*?\[\\]/) { if (g[i] in O) in_[g[i]] = 1; continue }   # a literal path: a lookup
        if (!(g[i] in M)) { re = g2re(g[i]); M[g[i]] = ""; for (j = 1; j <= np; j++) if (IP[j] ~ re) M[g[i]] = M[g[i]] SUBSEP IP[j] }
        k = split(M[g[i]], x, SUBSEP); for (j = 2; j <= k; j++) in_[x[j]] = 1
      }
      m = split(R[s], c, SUBSEP)
      # a reference no glob covered: in the key, and reported by `undeclared`
      for (i = 2; i <= m; i++) if (!(c[i] in in_)) { in_[c[i]] = 1; print n, 8, c[i] }
      in_[p] = 1; in_["tests/lib/core.sh"] = 1
      print n, 0, "suite " s
      print n, 0, "declared " D[s]
      for (q in in_) if (q in O) print n, 1, O[q] " " q
    }
  ' "$W/paths" | LC_ALL=C sort -t "$TAB" -k1,1n -k2,2 -k3,3 > "$W/lines"
  # One manifest file per keyed suite, named by its line number, listed in order; one git call hashes them all.
  rm -rf "$W/m"; mkdir -p "$W/m"
  awk -F '\t' -v d="$W/m" -v head="$W/head" -v ml="$W/mlist" '
    $2 == "-" || $2 == 8 { next }
    $1 != cur { if (cur != "") close(f); cur = $1; f = d "/" $1; print f > ml
                while ((getline h < head) > 0) print h > f; close(head) }
    { print $3 > f }' "$W/lines"
  [ -f "$W/mlist" ] || : > "$W/mlist"
  if [ -s "$W/mlist" ]; then _g hash-object --no-filters --stdin-paths < "$W/mlist" > "$W/mkeys"; else : > "$W/mkeys"; fi
  awk -F '\t' -v OFS='\t' -v ml="$W/mlist" -v mk="$W/mkeys" -v ln="$W/lines" '
    BEGIN { while ((getline f < ml) > 0) { if ((getline k < mk) <= 0) k = ""; sub(/.*\//, "", f); K[f] = k }
            while ((getline l < ln) > 0) { split(l, a, "\t"); if (a[2] == "-") Y[a[1]] = a[3] } }
    { if (K[NR] ~ /^[0-9a-f]+$/) print $1, K[NR]; else print $1, "-", ((NR in Y) ? Y[NR] : "no key could be made") }' "$W/paths" > "$2"
}

# Suites file -> "<suite> TAB <repo path>" for _keys.
_prep() { # <suites-file>
  while IFS= read -r _s; do [ -n "$_s" ] && printf '%s\t%s\n' "$_s" "$(_path "$_s")"; done < "$1" > "$W/paths"
}

# ── the store: <dir>/<domain>/<key>, a regular file this user wrote in a dir this user owns ──
_store() {
  _base="${HARBOR_TEST_SUITE_CACHE_DIR:-${HARBOR_SUITE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/harbor/suite-cache}}"
  _dom="$(_domain)" || return 1
  STORE="$_base/$(printf '%s' "$_dom" | tr -c 'A-Za-z0-9._-' '_')"
  mkdir -p "$STORE" 2>/dev/null || return 1
  [ ! -L "$STORE" ] && [ -w "$STORE" ] || return 1
  [ -n "$(find "$STORE" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" ] || return 1
}

# ── the gate: why this run may not use the cache at all, or nothing ──
_gate() {
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git checkout: there is nothing to key on"; return; }
  if [ "${GITHUB_REF:-}" = refs/heads/main ]; then echo "a run on main keeps a full verdict"; return; fi
  if [ "$(git -C "$ROOT" symbolic-ref -q --short HEAD 2>/dev/null || :)" = main ]; then echo "the checkout is on main, which keeps a full verdict"; return; fi
  if [ "${GITHUB_ACTIONS:-}" = true ] && [ -z "${RUNNER_NAME:-}" ]; then echo "under Actions with no RUNNER_NAME, so no trust domain"; return; fi
  _rc=0; _all="$(HARBOR_SCOPE_ROOT="$ROOT" sh "$DIR/test-suite-select.sh" --why-all 2>/dev/null)" || _rc=$?
  case "$_rc" in
    0) echo "every suite runs: $_all"; return ;;
    1) ;;
    *) echo "bin/test-suite-select.sh --why-all exited $_rc: the selection could not be judged"; return ;;
  esac
  _store || { echo "no store this user owns and can write at ${HARBOR_TEST_SUITE_CACHE_DIR:-${HARBOR_SUITE_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/harbor/suite-cache}}"; return; }
}

case "$CMD" in
  lookup)
    [ $# -eq 3 ] || usage
    _q="$1"; _k="$2"; _h="$3"; : > "$_h"; : > "$_k"
    _why="$(_gate)"
    if [ -n "$_why" ]; then printf 'off — %s\n' "$_why"; exit 1; fi
    _store
    _prep "$_q"; _keys "$_q" "$_k"
    find "$STORE" -maxdepth 1 -type f -user "$(id -u)" > "$W/owned" 2>/dev/null || :
    # An entry is v1 TAB secs TAB count TAB when TAB suite TAB commit, in a file this user owns; anything
    # else is not a pass this code wrote, and the suite runs. A hit replays the pass's time and count.
    awk -F '\t' -v OFS='\t' -v st="$STORE" -v ow="$W/owned" -v used="$W/used" '
      BEGIN { while ((getline f < ow) > 0) own[f] = 1 }
      $2 == "-" { next }
      { f = st "/" $2; if (!(f in own)) next
        if ((getline e < f) <= 0) next
        close(f); split(e, a, "\t")
        if (a[1] != "v1" || a[2] !~ /^[0-9]+$/ || (a[3] !~ /^[0-9]+$/ && a[3] != "-") || a[5] != $1) next
        print f > used
        print "cached", a[2], 0, a[3], $1, "passed " a[4] " (commit " a[6] "), key " substr($2, 1, 12) }' "$_k" > "$_h"
    # A hit is a use: it keeps the entry from being pruned.
    [ ! -s "$W/used" ] || { set --; while IFS= read -r _f; do set -- "$@" "$_f"; done < "$W/used"; touch "$@" 2>/dev/null || :; }
    printf 'on — %s hit(s) of %s keyed suite(s), %s never cached; store %s\n' "$(grep -c . "$_h" || :)" \
      "$(awk -F '\t' '$2 != "-"' "$_k" | grep -c . || :)" "$(awk -F '\t' '$2 == "-"' "$_k" | grep -c . || :)" "$STORE"
    ;;

  record)
    [ $# -eq 2 ] || usage
    _k="$1"; _r="$2"
    _store || { echo "not recorded: no store this user owns and can write"; exit 1; }
    # A pass row whose suite was keyed before the run, keyed AGAIN after it: a file edited while the suite
    # ran means the pass is not the key's, and it is not kept.
    awk -F '\t' -v kf="$_k" 'FILENAME == kf { if ($2 != "-") k[$1] = $2; next } $1 == "pass" && ($5 in k) { print $5 }' "$_k" "$_r" > "$W/passed"
    _prep "$W/passed"; _keys "$W/passed" "$W/after"
    _when="$(date -u +%Y-%m-%dT%H:%M:%SZ)"; _c="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo -)"
    awk -F '\t' -v OFS='\t' -v kf="$_k" -v rf="$_r" '
      FILENAME == kf { if ($2 != "-") was[$1] = $2; next }
      FILENAME == rf { if ($1 == "pass" && !($5 in row)) row[$5] = $2 "\t" $4; next }
      { print (($2 != "-" && $2 == was[$1]) ? "keep" : "moved"), $2, $1, row[$1] }' "$_k" "$_r" "$W/after" > "$W/plan"
    _n=0; _moved=0
    while IFS="$TAB" read -r _do _key _s _secs _cnt; do
      if [ "$_do" != keep ]; then _moved=$((_moved + 1)); continue; fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$FORMAT" "$_secs" "$_cnt" "$_when" "$_s" "$_c" > "$STORE/.$_key.$$"
      mv -f "$STORE/.$_key.$$" "$STORE/$_key"; _n=$((_n + 1))
    done < "$W/plan"
    find "$STORE" -type f -mtime +"${HARBOR_TEST_SUITE_CACHE_DAYS:-${HARBOR_SUITE_CACHE_DAYS:-30}}" -exec rm -f {} + 2>/dev/null || :
    printf 'recorded %s pass(es)%s\n' "$_n" "$([ "$_moved" = 0 ] || printf '; %s not, an input changed during the run' "$_moved")"
    ;;

  key)
    [ $# -gt 0 ] || usage
    printf '%s\n' "$@" > "$W/q"; _prep "$W/q"; _keys "$W/q" "$W/k"; cat "$W/k"
    ;;

  manifest)
    [ $# -eq 1 ] || usage
    printf '%s\n' "$1" > "$W/q"; _prep "$W/q"; _keys "$W/q" "$W/k"
    if [ -f "$W/m/1" ]; then cat "$W/m/1"; else cut -f3 "$W/k" >&2; exit 1; fi
    ;;

  undeclared)
    if [ $# -gt 0 ]; then printf '%s\n' "$@" > "$W/q"
    else grep -vE '^[[:space:]]*(#|$)' "$ROOT/contracts/suites.txt" | awk '{ print $1 }' > "$W/q"; fi
    _prep "$W/q"; _keys "$W/q" "$W/k"
    # Inputs the key holds that the declaration — and so suite-select — never sees: <suite> TAB <path>.
    awk -F '\t' -v OFS='\t' -v pf="$W/paths" 'FILENAME == pf { s[FNR] = $1; next } $2 == 8 { print s[$1], $3 }' "$W/paths" "$W/lines"
    ;;

  *) usage ;;
esac
