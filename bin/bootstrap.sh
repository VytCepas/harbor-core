#!/usr/bin/env sh
# bootstrap.sh (harbor#829) — a fresh machine to a passing deploy dry run, in one command:
#   git clone <url> ~/port/harbor && sh ~/port/harbor/bin/harbor scope install && sh ~/port/harbor/bin/bootstrap.sh
#   -h, --help   this text
# (harbor#966) Reads the private layer's harbor.toml and clones only what it names: yard and prod-guard need the yard checkout,
# fleet needs the fleet checkout, each pack its own repo, from the registry's remote or else the owner of harbor's own
# origin. uv and just are installed into HARBOR_LOCAL_BIN for yard or fleet only. Then it hands off to `deploy.sh --live`:
# the DRY RUN. core alone clones nothing, downloads nothing and needs no gh. The apply stays the operator's; this never runs it.
# Refused before any write: a native Windows shell, a checkout outside HARBOR_REPO, no private layer (a stranger runs
# `harbor scope install` first). No token passes through here: gh and git hold the credential. A clone uses gh when it is
# logged in, else plain git over https.
set -eu

# ${0%/*}, not dirname: see bin/roots.sh (harbor#810).
case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
ROOT="$(CDPATH='' cd -P -- "$SRC/.." && pwd -P)"
. "$ROOT/bin/log-lib.sh"
log_init bootstrap

UV_URL='https://astral.sh/uv/install.sh'
JUST_URL='https://just.systems/install.sh'

case "${1-}" in
  '') ;;
  -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "bootstrap: unknown argument '$1' (it takes none; see --help)" >&2; exit 2 ;;
esac

FAILS=0
TAB="$(printf '\t')"
_bad() { FAILS=$((FAILS + 1)); log_fail "$1"; case "$2" in 'none: '*) log_nofix "${2#none: }" ;; *) log_fix "$2" ;; esac; }
_phys() { CDPATH='' cd -P -- "$1" 2>/dev/null && pwd -P || printf '%s' "$1"; }
_refused() { log_note "REFUSED ($FAILS) — nothing was cloned or installed"; log_end || :; exit 1; }
# owner/repo of a github.com URL, and whether it is shaped like one: log-lib's slug_of_url and slug_valid (harbor#1149),
# the same parser repo_slug names harbor's own repository with.
_url_ok() { # <url> — https only: no user:token, query or fragment, a host and a path, no .. segment
  case "$1" in https://*) ;; *) return 1 ;; esac
  case "${1#https://}" in ''|-*|*/|*//*|*/..|*/../*|*[!A-Za-z0-9._~:/-]*) return 1 ;; */*) ;; *) return 1 ;; esac
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/harbor-bootstrap.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM

log_head 'preflight · nothing is written unless every check here passes'

# CONTRACTS/platforms.md rule 3: a native Windows shell is refused, and WSL2 named as the way in.
_os="$(uname -s 2>/dev/null || printf unknown)"
case "$_os" in
  Darwin|Linux) log_ok "platform: $_os" ;;
  MINGW*|MSYS*|CYGWIN*) _bad "native Windows shell ($_os): Harbor runs on macOS and Linux, and on Windows only inside WSL2" \
                          'none: CONTRACTS/platforms.md — open a WSL2 shell, clone into ~/port/harbor there, and re-run' ;;
  *) _bad "unsupported platform: $_os" 'none: CONTRACTS/platforms.md — macOS, Linux, or WSL2' ;;
esac
[ "$FAILS" -eq 0 ] || _refused

# A pack's checkout and the other repos land beside HARBOR_REPO, so a checkout elsewhere would scatter them.
_hr="$(sh "$ROOT/bin/roots.sh" --get HARBOR_REPO 2>/dev/null || true)"
if [ -n "$_hr" ] && [ "$(_phys "$_hr")" = "$ROOT" ]; then log_ok "running from HARBOR_REPO ($ROOT)"
else _bad "running from $ROOT, but HARBOR_REPO is ${_hr:-<unresolved>}" "none: README.md — clone harbor into ${_hr:-${PORT_ROOT:-$HOME/port}/harbor} and run its bin/bootstrap.sh from there"; fi
LOCAL_BIN="$(sh "$ROOT/bin/roots.sh" --get HARBOR_LOCAL_BIN 2>/dev/null || true)"
case "$LOCAL_BIN" in /*) ;; *) _bad "HARBOR_LOCAL_BIN resolves to '${LOCAL_BIN}', not an absolute path" 'none: CONTRACTS/roots.tsv — HARBOR_LOCAL_BIN' ;; esac

if command -v git >/dev/null 2>&1; then log_ok 'git present'; else _bad 'git is missing' 'none: install git (on macOS: xcode-select --install)'; fi

# What this machine is: the private layer's components and packs, and nothing else. deploy reads the same two keys,
# and with no components key it installs every component (harbor#1149), so bootstrap prepares every one.
PRIV="$(sh "$ROOT/bin/roots.sh" --private 2>/dev/null || true)"
LAYER=0; YARD=0; FLEET=0; PGUARD=0
if [ -n "$PRIV" ] && [ -d "$PRIV" ]; then
  LAYER=1; log_ok "private layer: $PRIV"
  _crc=0; _comp="$(sh "$ROOT/bin/roots.sh" --conf components 2>"$WORK/conf.err")" || _crc=$?
  case "$_crc" in
    0) for _c in $_comp; do
         case "$_c" in
           core|collector) ;;
           yard) YARD=1 ;;
           fleet) FLEET=1 ;;
           prod-guard) PGUARD=1 ;;
           *) _bad "harbor.toml components: '$_c' is not a component (core, yard, fleet, prod-guard, collector)" 'none: CONTRACTS/private-layer.md — harbor.toml' ;;
         esac
       done
       log_ok "components (harbor.toml): $(printf '%s' "$_comp" | tr '\n' ' ')" ;;
    1) YARD=1; FLEET=1; PGUARD=1
       log_note 'harbor.toml names no components, so deploy installs every one and every one is prepared; components = ["core"] narrows it' ;;
    *) _bad "harbor.toml could not be read: $(head -1 "$WORK/conf.err")" 'none: CONTRACTS/private-layer.md — harbor.toml' ;;
  esac
else
  _bad "no private layer at ${PRIV:-<unresolved>}, so nothing says which components this machine installs (deploy would plan every one)" \
    "sh '$ROOT/bin/harbor' scope install"
  log_note "on the operator's own machine: clone the private layer into ${PRIV:-<unresolved>} instead, then re-run this"
fi

# The checkouts to have, <repo> TAB <dir>, once each. A component's directory is the one deploy reads (roots.sh --get),
# a pack's the one pack.sh reads (roots.sh --repo).
: >"$WORK/want"
_want() { # <name> <dir>
  D="$2" awk -F"$TAB" '$2 == ENVIRON["D"] { f = 1 } END { exit !f }' "$WORK/want" || printf '%s\t%s\n' "$1" "$2" >>"$WORK/want"
}
_want_var() { # <roots.tsv variable>: the repo is the one the table's default names, wherever the operator points the variable
  _wd="$(sh "$ROOT/bin/roots.sh" --get "$1" 2>/dev/null || true)"; _wd="${_wd%/}"
  _dd="$(env -u "$1" sh "$ROOT/bin/roots.sh" --get "$1" 2>/dev/null || true)"; _dd="${_dd%/}"
  if [ -n "$_wd" ] && [ -n "$_dd" ]; then _want "${_dd##*/}" "$_wd"; else _bad "$1 resolves to no directory" "none: CONTRACTS/roots.tsv — $1"; fi
}
[ "$YARD" -eq 0 ] || _want_var HARBOR_PROJECT_INIT
[ "$PGUARD" -eq 0 ] || _want_var PROJECT_INIT_SRC
[ "$FLEET" -eq 0 ] || _want_var HARBOR_ORCHESTRATOR
if [ "$LAYER" -eq 1 ]; then
  _prc=0; _packs="$(sh "$ROOT/bin/roots.sh" --conf packs 2>"$WORK/conf.err")" || _prc=$?
  case "$_prc" in
    0) for _p in $_packs; do
         # harbor-private is the layer's own pack (harbor#1273), present already: the layer is what this branch requires.
         [ "$_p" != harbor-private ] || continue
         if _pd="$(sh "$ROOT/bin/roots.sh" --repo "$_p" 2>"$WORK/conf.err")" && [ -n "$_pd" ]; then _want "$_p" "$_pd"
         else _bad "pack '$_p' has no checkout in the registry: $(head -1 "$WORK/conf.err")" "none: CONTRACTS/private-layer.md — add $_p to repos.tsv"; fi
       done ;;
    1) ;;
    *) _bad "harbor.toml packs could not be read: $(head -1 "$WORK/conf.err")" 'none: CONTRACTS/private-layer.md — harbor.toml' ;;
  esac
fi

# Where a missing checkout is cloned from, one line each: name, dir, kind, source. The registry's remote column is the
# repo's own address (a pack may live under another owner); with none ('-', no row, no registry) the repo is
# <owner of harbor's origin>/<name>. A remote that is not a plain https URL or a github.com spelling is refused, never
# guessed at, and never printed (it is a private file's text).
: >"$WORK/clone"
_plan() { # <name> <dir>
  _rrc=0; _rem="$(sh "$ROOT/bin/roots.sh" --remote "$1" 2>"$WORK/conf.err" </dev/null)" || _rrc=$?
  case "$_rrc" in
    1) printf '%s\t%s\towner\t-\n' "$1" "$2" >>"$WORK/clone" ;;
    0) _sl="$(slug_of_url "$_rem")"
       if [ -n "$_sl" ] && slug_valid "$_sl"; then printf '%s\t%s\tslug\t%s\n' "$1" "$2" "$_sl" >>"$WORK/clone"
       elif [ -z "$_sl" ] && _url_ok "$_rem"; then printf '%s\t%s\turl\t%s\n' "$1" "$2" "$_rem" >>"$WORK/clone"
       else _bad "$1: its remote in repos.tsv is not an https URL bootstrap clones from (no user:token, query or fragment) or a github.com owner/repo" \
              "none: CONTRACTS/private-layer.md — correct the remote of the $1 row in repos.tsv, or set it to - to clone from the owner of harbor's origin"; fi ;;
    *) _bad "$1: repos.tsv could not be read: $(head -1 "$WORK/conf.err")" 'none: CONTRACTS/private-layer.md — repos.tsv' ;;
  esac
}
# A path that exists and is no checkout is refused.
while IFS="$TAB" read -r _n _d; do
  [ -n "$_n" ] || continue
  if [ ! -e "$_d" ]; then _plan "$_n" "$_d"
  elif git -C "$_d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then log_ok "$_n: present at $_d, not touched"
  else _bad "$_n: $_d exists and is not a git checkout" "none: harbor#829 — move $_d aside, then re-run"; fi
done <"$WORK/want"
[ -s "$WORK/want" ] || [ "$LAYER" -eq 0 ] || log_ok 'no checkout beyond harbor is named, so nothing is cloned'

# Only a clone from the origin's owner needs an owner, and only a github.com clone needs to choose a way to reach it: gh
# clones what it may see, a private repo included; without a login, git over https reaches public repositories only.
_has() { awk -F"$TAB" -v k="$1" '$3 == k { f = 1 } END { exit !f }' "$WORK/clone"; }
CLONER=''; OWNER=''
if _has owner; then
  # The owner every such repo is cloned from: the one harbor itself came from, read raw (no insteadOf).
  _url="$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null || true)"
  _rest="$(slug_of_url "$_url")"; OWNER="${_rest%%/*}"
  case "$OWNER" in
    ''|-*|*[!A-Za-z0-9-]*) OWNER=''; _bad "origin of $ROOT is not a github.com/<owner>/<repo> URL: '${_url:-<none>}', so the repos to clone have no owner" 'none: harbor#829 — clone harbor from its github.com URL, as documented, or give the repo a remote in repos.tsv' ;;
    *) log_ok "cloning from github.com/$OWNER" ;;
  esac
fi
if _has owner || _has slug; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then CLONER=gh; log_ok 'gh auth status passes'
  else CLONER=git; log_warn 'gh is missing or not logged in: cloning with git over https, which reaches public repositories only'; fi
fi

# uv and just: only yard and fleet run a repo's `just install`. Found on PATH (LOCAL_BIN first, where an earlier run put
# them) or installed there.
_path0="$PATH"; PATH="$LOCAL_BIN:$PATH"; export PATH
NEED=''
if [ "$YARD" -eq 1 ] || [ "$FLEET" -eq 1 ]; then
  for _t in uv just; do
    if command -v "$_t" >/dev/null 2>&1; then log_ok "$_t present ($(command -v "$_t"))"; else NEED="$NEED $_t"; fi
  done
  if [ -n "$NEED" ]; then
    command -v curl >/dev/null 2>&1 || _bad "curl is missing; it downloads the installer for:$NEED" 'none: install curl'
    case "$NEED" in *just*) command -v bash >/dev/null 2>&1 || _bad "bash is missing; just's official installer needs it" 'none: install bash' ;; esac
  fi
else
  log_ok 'uv and just are not needed: only yard and fleet run just install'
fi
[ "$FAILS" -eq 0 ] || _refused

log_head 'clone · each missing checkout'
if [ ! -s "$WORK/clone" ]; then log_ok 'every checkout is already there'; fi
while IFS="$TAB" read -r _n _d _k _v; do
  [ -n "$_n" ] || continue
  case "$_k" in owner) _cs="$OWNER/$_n" ;; slug) _cs="$_v" ;; *) _cs='' ;; esac   # owner/repo on github.com, or none
  if [ -n "$_cs" ]; then _from="github.com/$_cs"; _src="https://$_from.git"; else _from="$_v"; _src="$_v"; fi
  _rc=0
  if [ -n "$_cs" ] && [ "$CLONER" = gh ]; then gh repo clone "$_cs" "$_d" >"$WORK/out" 2>&1 </dev/null || _rc=$?
  else GIT_TERMINAL_PROMPT=0 git clone -q -- "$_src" "$_d" >"$WORK/out" 2>&1 </dev/null || _rc=$?; fi
  if [ "$_rc" -eq 0 ]; then log_ok "$_n: cloned from $_from into $_d"
  elif [ -n "$_cs" ] && [ "$CLONER" = gh ]; then _bad "$_n: gh repo clone $_cs failed: $(tail -1 "$WORK/out")" "gh repo clone $_cs '$_d'"
  elif [ -n "$_cs" ]; then
    _bad "$_n: git clone of $_from failed, and without a gh login only a public repository can be cloned: $(tail -1 "$WORK/out")" \
         "none: harbor#829 — install gh (https://cli.github.com), gh auth login, then re-run this"
  else _bad "$_n: git clone of $_from failed: $(tail -1 "$WORK/out")" "none: harbor#966 — check the $_n row's remote in repos.tsv and the network, then re-run this"; fi
done <"$WORK/clone"

# Downloaded to a file and run from there, never piped: the bytes that run are the bytes on disk.
_fetch() { # <url> <file>
  case "$1" in https://*) ;; *) return 1 ;; esac
  curl --proto '=https' --tlsv1.2 -fsSL -o "$2" "$1" </dev/null
}
log_head "tools · uv and just into $LOCAL_BIN"
[ -n "$NEED" ] || log_ok 'nothing to install'
for _t in $NEED; do
  mkdir -p "$LOCAL_BIN"
  _rc=0
  case "$_t" in
    uv)   { _fetch "$UV_URL" "$WORK/uv.sh" && UV_INSTALL_DIR="$LOCAL_BIN" UV_NO_MODIFY_PATH=1 sh "$WORK/uv.sh"; } >"$WORK/out" 2>&1 </dev/null || _rc=$? ;;
    just) { _fetch "$JUST_URL" "$WORK/just.sh" && bash "$WORK/just.sh" --to "$LOCAL_BIN"; } >"$WORK/out" 2>&1 </dev/null || _rc=$? ;;
  esac
  if [ "$_rc" -eq 0 ] && [ -x "$LOCAL_BIN/$_t" ] && "$LOCAL_BIN/$_t" --version >/dev/null 2>&1; then
    log_ok "$_t: installed ($("$LOCAL_BIN/$_t" --version 2>&1 | head -1))"
  else
    _bad "$_t: its official installer failed (rc=$_rc): $(tail -1 "$WORK/out")" "none: harbor#829 — its last line above; then re-run this"
  fi
done
case ":$_path0:" in *":$LOCAL_BIN:"*) ;; *) log_warn "$LOCAL_BIN is not on your PATH; add it to your shell profile, or the harbor shims will not be found" ;; esac

if [ "$FAILS" -gt 0 ]; then log_note "STOPPED ($FAILS) — deploy was not run"; log_end || :; exit 1; fi
log_note "next: the deploy DRY RUN; the apply is yours: sh '$ROOT/bin/deploy.sh' --apply --live, from a terminal window"
log_end || :
rm -rf "$WORK"; trap - EXIT  # exec skips the EXIT trap
exec sh "$ROOT/bin/deploy.sh" --live
