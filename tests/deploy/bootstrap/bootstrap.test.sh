#!/usr/bin/env sh
# deploy-bootstrap.sh (harbor#829, harbor#966): a throwaway HOME with no checkouts, against LOCAL bare remotes (git's
# insteadOf maps github.com to them; GIT_ALLOW_PROTOCOL=file keeps https off). gh, curl and uname are stubs; the uv and
# just "official installers" are the files the curl stub serves. The REAL deploy-bootstrap.sh, scope.sh, scope-roots.sh, roots.tsv
# and deploy.sh run; deploy's installers are stubs. The owner is "acme": bootstrap derives it from harbor's origin.
# What it proves: the private layer says what a machine is. core clones, downloads and needs nothing beyond harbor, and
# a repo whose registry row has a remote is cloned from THAT remote, not from <harbor's owner>/<id>.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE HARBOR_DEPLOY
T_TMP="$(cd "$T_TMP" && pwd -P)"
TAB='	'
_inst='#!/bin/sh
n=$(basename "$0"); printf "%s %s\n" "$n" "$*" >> "$STUB_LOG.inst"
case " $* " in *" --apply "*) m=apply ;; *) m=dry ;; esac
echo "  ok: $n stub ran ($m)"'
_just='#!/bin/sh
jf=""; wd=""
while [ $# -gt 0 ]; do case "$1" in --justfile) jf="$2"; shift 2 ;; --working-directory) wd="$2"; shift 2 ;; *) break ;; esac; done
case "${1:-}" in
  --version) echo "just 0.0-stub" ;;
  --summary) sed -n "s/^\([A-Za-z_-]*\):.*/\1/p" "$jf" | tr "\n" " " ;;
  install) echo "just install ($*) in $wd"; printf "just %s %s\n" "$wd" "$*" >> "$STUB_LOG.inst" ;;
esac'

# box <case> [<harbor.toml body>|none] [<repos.tsv rows>] → T, H (the throwaway HOME), REM (bare remotes), P (PATH)
# The layer is written before the run, as an operator's cloned private repo is; 'none' writes none (a stranger's start).
box() {
  T="$T_TMP/$1"; H="$T/home"; REM="$T/remotes"; S="$T/stub"; P="$S:/usr/bin:/bin:/usr/sbin:/sbin"
  mkdir -p "$H/.claude" "$REM/acme" "$S" "$T/src/harbor/bin" "$T/src/harbor/contracts"
  _h="$T/src/harbor"
  for f in deploy-bootstrap.sh deploy.sh scope-roots.sh scope.sh library-log.sh deploy-install-lib.sh deploy-restore.sh; do [ ! -f "$T_ROOT/bin/$f" ] || cp "$T_ROOT/bin/$f" "$_h/bin/"; done
  cp "$T_ROOT/contracts/roots.tsv" "$_h/contracts/roots.tsv"
  for s in policy-constitution-install.sh deploy-shim-install.sh deploy-harden.sh deploy-runtime-install.sh admission-install.sh pack.sh \
           prod-guard-install.sh skill-install.sh skill-catalog.sh context-injection-install.sh; do printf '%s\n' "$_inst" > "$_h/bin/$s"; done
  printf '#!/bin/sh\nexit 0\n' > "$_h/bin/deploy-install-stamp.sh"; chmod +x "$_h/bin/"*
  # The test's own reading of the table: every REPOS row's first path segment gets a bare remote.
  # ...plus the pack repo the pack sections clone: no core root names it since its paths left with the pack (harbor#1149).
  REPOS="$(awk -F"$TAB" '!/^#/ && $2 == "REPOS" { sub(/\/.*/, "", $3); print $3 }' "$_h/contracts/roots.tsv" | { cat; echo zorbcorp; } | sort -u | tr '\n' ' ')"
  for r in $REPOS; do
    mkdir -p "$T/src/$r"
    case "$r" in project-init|projects-orchestrator) printf 'install:\n\techo x\n' > "$T/src/$r/justfile" ;;
                 harbor) ;; *) echo "$r" > "$T/src/$r/README" ;; esac
    git -C "$T/src/$r" init -q -b main && git -C "$T/src/$r" add -A
    git -C "$T/src/$r" -c user.name=t -c user.email=t@t commit -qm init && git clone -q --bare "$T/src/$r" "$REM/acme/$r.git"
  done
  printf '[url "file://%s/"]\n\tinsteadOf = https://github.com/\n[url "file://%s/elsewhere/"]\n\tinsteadOf = https://git.example.test/\n' "$REM" "$REM" > "$H/.gitconfig"
  printf '{}\n' > "$H/.claude/settings.json"   # Claude Code started once: deploy's own precondition
  if [ "${2:-}" != none ]; then
    mkdir -p "$H/port/harbor-private"
    printf '%s\n' "${2:-components = [\"core\"]}" > "$H/port/harbor-private/harbor.toml"
    { printf 'id\tpath\tkind\tremote\n'; [ -z "${3:-}" ] || printf '%s\n' "$3"; } > "$H/port/harbor-private/repos.tsv"
  fi
  cat > "$S/gh" <<'EOS'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG.ghall"   # every call, `auth status` included; .gh below is the clones alone
case "$1 $2" in
  "auth status") [ "${STUB_GH_AUTH:-0}" = 0 ] || { echo "You are not logged into any GitHub hosts." >&2; exit 1; }; echo ok ;;
  "repo clone") printf 'clone %s %s\n' "$3" "$4" >> "$STUB_LOG.gh"; exec git clone -q "https://github.com/$3.git" "$4" ;;
  *) echo "gh stub: $*" >&2; exit 2 ;;
esac
EOS
  cat > "$S/curl" <<EOS
#!/bin/sh
printf '%s\n' "\$*" >> "\$STUB_LOG.curl"
o=''; u=''; while [ \$# -gt 0 ]; do case "\$1" in -o) o="\$2"; shift 2 ;; https://*) u="\$1"; shift ;; *) shift ;; esac; done
case "\$u" in
  https://astral.sh/uv/install.sh) printf '%s\n' '#!/bin/sh' 'd="\${UV_INSTALL_DIR:?}"; mkdir -p "\$d"' \
      '[ "\${UV_NO_MODIFY_PATH:-}" = 1 ] || echo x >> "\$STUB_LOG.rcedit"' \
      'printf "#!/bin/sh\necho uv 0.0-stub\n" > "\$d/uv"; chmod +x "\$d/uv"' > "\$o" ;;
  https://just.systems/install.sh) printf '%s\n' '#!/bin/sh' 'd=""; [ "\$1" = --to ] && d="\$2"; mkdir -p "\${d:?}"' \
      'cp "$S/just.bin" "\$d/just"; chmod +x "\$d/just"' > "\$o" ;;
  *) echo "curl: (6) stub: no network for \$u" >&2; exit 6 ;;
esac
EOS
  printf '%s\n' "$_just" > "$S/just.bin"
  printf '#!/bin/sh\n[ -z "${STUB_UNAME:-}" ] || { echo "$STUB_UNAME"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$S/uname"
  chmod +x "$S/gh" "$S/curl" "$S/uname"
  : > "$T/log.gh"; : > "$T/log.ghall"; : > "$T/log.curl"; : > "$T/log.inst"
}
mkbare() { # <owner/name> <readme> [justfile] — a bare remote at REM/<owner>/<name>.git, for a box already built
  _w="$T/src2/$1"; mkdir -p "$_w" "$REM/${1%/*}"; printf '%s\n' "$2" > "$_w/README"
  [ -z "${3:-}" ] || printf 'install:\n\techo x\n' > "$_w/justfile"
  git -C "$_w" init -q -b main && git -C "$_w" add -A && git -C "$_w" -c user.name=t -c user.email=t@t commit -qm init
  git clone -q --bare "$_w" "$REM/$1.git"
}
# The documented commands, verbatim, in a clean environment (env -i: none of the caller's knobs).
GIT_HARBOR='git clone -q https://github.com/acme/harbor.git ~/port/harbor'
GH_HARBOR='gh repo clone acme/harbor ~/port/harbor'
BOOT='sh ~/port/harbor/bin/deploy-bootstrap.sh'
STRANGER="$GIT_HARBOR && sh ~/port/harbor/bin/scope.sh install && $BOOT"   # the README's fresh machine
ONE="$GH_HARBOR && $BOOT"                                                   # an operator whose layer is already there
run() { # [<command>] — default ONE; RC and $T/out.txt
  RC=0
  ( cd "$H" && env -i HOME="$H" PATH="$P" TMPDIR="$TMPDIR" LANG=C GIT_ALLOW_PROTOCOL=file STUB_LOG="$T/log" \
      STUB_GH_AUTH="${GH_AUTH:-0}" STUB_UNAME="${UNAME:-}" sh -c "${1:-$ONE}" ) >"$T/out.txt" 2>&1 </dev/null || RC=$?
}
out() { cat "$T/out.txt"; }
mark() { sleep 1; : > "$T/mark"; }
written() { # every path under HOME changed since mark, minus deploy's own `git fetch` (FETCH_HEAD)
  find "$H" -newer "$T/mark" ! -type d ! -path "$H/port/harbor/.git/FETCH_HEAD" | sed "s|^$H/||" | sort | tr '\n' ' '
}
clones() { awk '{print $2}' "$T/log.gh" | tr '\n' ' '; }
checkouts() { # every git checkout under ~/port, by name
  for _d in "$H"/port/*; do if [ -d "$_d/.git" ]; then printf '%s ' "${_d##*/}"; fi; done
}
dry_run_ok() { # <label> — the run ended on deploy's own summary, 0 failed
  t_exit "$1: ending on deploy's own summary, 0 failed" 0 grep -qE '^deploy: [0-9]+ ok, 0 failed, [0-9]+ warnings$' "$T/out.txt"
}

t_section "control: the fixture is the fresh machine it claims to be"
box ctl
t_eq "no uv or just on the suite's PATH before the run" "" "$(env PATH="$P" sh -c 'command -v uv just' 2>/dev/null || :)"
t_eq "no checkout under the throwaway HOME" no "$([ -d "$H/port/harbor" ] && echo yes || echo no)"
t_has "the table names the repos the suite built remotes for" "$REPOS" "project-init"
t_exit "https is refused under the suite's git (nothing can reach the network)" 128 \
  env HOME="$H" GIT_ALLOW_PROTOCOL=file git ls-remote https://example.invalid/x.git

t_section "a stranger: clone, scope install, bootstrap - core clones and downloads nothing"
box stranger none; GH_AUTH=1 run "$STRANGER"; GH_AUTH=''
t_eq "exit" 0 "$RC"
dry_run_ok "stranger"
t_has "scope install wrote the layer bootstrap then read" "$(out)" "components (harbor.toml): core"
t_has "...and deploy plans core alone" "$(out)" "components: core"
t_eq "the only checkout is harbor" "harbor " "$(checkouts)"
t_eq "gh was never called, auth status included, logged in or not" "" "$(cat "$T/log.ghall")"
t_eq "nothing was downloaded" "" "$(cat "$T/log.curl")"
t_eq "uv and just were not installed" no "$([ -e "$H/.local/bin/uv" ] || [ -e "$H/.local/bin/just" ] && echo yes || echo no)"
t_has "...and the run says why" "$(out)" "uv and just are not needed"
t_has "...and that nothing beyond harbor is named" "$(out)" "no checkout beyond harbor is named, so nothing is cloned"
t_hasnt "gh auth was not asked for" "$(out)" "gh auth"
t_has "deploy reached the installers' dry runs" "$(cat "$T/log.inst")" "deploy-runtime-install.sh --live"
t_eq "nothing ran with --apply: the apply is the operator's" "" "$(grep -- '--apply' "$T/log.inst" || :)"
t_has "the apply is named as the operator's next step" "$(out)" "sh '$H/port/harbor/bin/deploy.sh' --apply --live"

t_section "a stranger with no gh at all, whose harbor came from a path, not github"
box nogh none; rm -f "$T/stub/gh"
run "git clone -q '$REM/acme/harbor.git' ~/port/harbor && sh ~/port/harbor/bin/scope.sh install && $BOOT"
t_eq "exit" 0 "$RC"
dry_run_ok "no gh, origin a path"
t_has "origin is the path it was cloned from" "$(git -C "$H/port/harbor" config --get remote.origin.url)" "$REM/acme/harbor.git"
t_eq "the only checkout is harbor" "harbor " "$(checkouts)"
t_eq "nothing was downloaded" "" "$(cat "$T/log.curl")"

t_section "no private layer: refused before any write, and gh is not the reason"
box nolayer none; GH_AUTH=1 run "$GIT_HARBOR && $BOOT"; GH_AUTH=''
t_eq "exit" 1 "$RC"
t_has "reason" "$(out)" "no private layer at $H/port/harbor-private"
t_has "...the fix is scope install" "$(out)" "  fix: sh '$H/port/harbor/bin/harbor' scope install"
t_has "...and the operator's way is named" "$(out)" "clone the private layer into $H/port/harbor-private"
t_hasnt "...and it does not claim there was nothing to clone" "$(out)" "nothing is cloned"
t_hasnt "gh is not mentioned as missing" "$(out)" "gh is "
t_hasnt "...nor as the fix" "$(out)" "gh auth login"
t_eq "only the documented harbor clone" "harbor " "$(checkouts)"
t_eq "no layer was created" no "$([ -e "$H/port/harbor-private" ] && echo yes || echo no)"
t_eq "no download" "" "$(cat "$T/log.curl")"
t_eq "deploy never ran" "" "$(cat "$T/log.inst")"
t_eq "nothing under ~/.local" no "$([ -e "$H/.local" ] && echo yes || echo no)"

t_section "yard and fleet: exactly the repos they need, uv and just installed"
box fresh 'components = ["core", "yard", "fleet"]'; run
t_eq "exit" 0 "$RC"
dry_run_ok "fresh"
t_has "deploy's preflight passed" "$(out)" "Preflight passed"
t_eq "gh cloned harbor and the two the components name, nothing else" \
  "acme/harbor acme/project-init acme/projects-orchestrator " "$(clones | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/^ //')"
t_eq "...and the estate and workload repos the table also names were not cloned" "harbor project-init projects-orchestrator " "$(checkouts)"
for r in project-init projects-orchestrator; do
  t_eq "$r: a checkout on main at ~/port/$r" main "$(git -C "$H/port/$r" symbolic-ref --short HEAD 2>/dev/null || echo none)"
done
t_eq "...its origin is the github URL, not the local remote" "https://github.com/acme/project-init.git" \
  "$(git -C "$H/port/project-init" config --get remote.origin.url)"
t_eq "curl fetched exactly the two official installers" \
  "https://astral.sh/uv/install.sh https://just.systems/install.sh" "$(grep -o 'https://[^ ]*' "$T/log.curl" | tr '\n' ' ' | sed 's/ $//')"
t_has "...over https only" "$(head -1 "$T/log.curl")" "--proto =https"
t_eq "uv installed into ~/.local/bin" "uv 0.0-stub" "$("$H/.local/bin/uv" --version 2>&1)"
t_eq "just installed into ~/.local/bin" "just 0.0-stub" "$("$H/.local/bin/just" --version 2>&1)"
t_eq "the uv installer was told not to edit shell profiles" no "$([ -s "$T/log.rcedit" ] && echo yes || echo no)"
t_has "deploy reached project-init's own dry run through the installed just" "$(cat "$T/log.inst")" "just $H/port/project-init"
t_has "...and projects-orchestrator's" "$(cat "$T/log.inst")" "just $H/port/projects-orchestrator"
t_has "deploy ran the installers' dry runs" "$(cat "$T/log.inst")" "deploy-runtime-install.sh --live"
t_eq "nothing ran with --apply: the apply is the operator's" "" "$(grep -- '--apply' "$T/log.inst" || :)"
t_has "the apply is named as the operator's next step" "$(out)" "sh '$H/port/harbor/bin/deploy.sh' --apply --live"
t_has "a PATH without ~/.local/bin is warned about" "$(out)" "is not on your PATH"
t_eq "bootstrap left no work dir in TMPDIR" "" "$(find "$TMPDIR" -maxdepth 1 -name 'harbor-bootstrap.*' | head -1)"

t_section "re-run on the populated box: nothing is written"
mark; : > "$T/log.gh"; : > "$T/log.ghall"; : > "$T/log.curl"; run 'sh ~/port/harbor/bin/deploy-bootstrap.sh'
t_eq "exit" 0 "$RC"
dry_run_ok "re-run"
t_eq "no file under HOME changed" "" "$(written)"
t_eq "no clone" "" "$(clones)"
t_eq "...and gh was not even asked whether it is logged in" "" "$(cat "$T/log.ghall")"
t_eq "no download" "" "$(cat "$T/log.curl")"
t_has "each repo is reported present and not touched" "$(out)" "project-init: present at $H/port/project-init, not touched"
t_has "uv found where the first run put it" "$(out)" "uv present ($H/.local/bin/uv)"
t_has "the control: the mark catches a write" "$(touch "$H/port/project-init/README"; written)" "port/project-init/README"

t_section "each component names its own repo"
box yard 'components = ["core", "yard"]'; run
t_eq "yard: exit" 0 "$RC"
t_eq "yard: project-init alone" "harbor project-init " "$(checkouts)"
t_eq "yard: uv and just are fetched (its recipe runs just)" "https://astral.sh/uv/install.sh https://just.systems/install.sh" \
  "$(grep -o 'https://[^ ]*' "$T/log.curl" | tr '\n' ' ' | sed 's/ $//')"
box fleet 'components = ["core", "fleet"]'; run
t_eq "fleet: exit" 0 "$RC"
t_eq "fleet: projects-orchestrator alone" "harbor projects-orchestrator " "$(checkouts)"
t_has "fleet: just ran its install" "$(cat "$T/log.inst")" "just $H/port/projects-orchestrator"
box pg 'components = ["core", "prod-guard"]'; run
t_eq "prod-guard: exit" 0 "$RC"
t_eq "prod-guard: its source is a project-init checkout, and that is all" "harbor project-init " "$(checkouts)"
t_eq "prod-guard: no uv or just (no repo's just install runs)" "" "$(cat "$T/log.curl")"
t_has "prod-guard: said so" "$(out)" "uv and just are not needed"
box both 'components = ["core", "yard", "prod-guard"]'; run
t_eq "yard and prod-guard name one checkout: exit" 0 "$RC"
t_eq "...and it is cloned once" "acme/harbor acme/project-init" "$(clones | sed 's/ $//')"
box coll 'components = ["core", "collector"]'; run
t_eq "collector: exit" 0 "$RC"
t_eq "collector: root installs it, so nothing is cloned" "harbor " "$(checkouts)"
box legacy 'channel = "main"'; run
t_eq "no components key: exit" 0 "$RC"
t_eq "...deploy's legacy default is every component, so both repos are prepared" "harbor project-init projects-orchestrator " "$(checkouts)"
t_has "...and the run says why" "$(out)" "harbor.toml names no components"

t_section "packs name their repos too"
box pack 'components = ["core"]
packs = ["zorbcorp"]' "zorbcorp${TAB}zorbcorp${TAB}workload${TAB}-"; run
t_eq "exit" 0 "$RC"
t_eq "the pack's repo is cloned, nothing else" "harbor zorbcorp " "$(checkouts)"
t_eq "...into the directory the registry gives" "acme/zorbcorp" "$(clones | tr ' ' '\n' | grep zorbcorp)"
t_eq "no download for a pack" "" "$(cat "$T/log.curl")"
box packreg 'components = ["core"]
packs = ["zorbcorp"]'; run
t_eq "a pack the registry lacks: exit" 1 "$RC"
t_has "...reason" "$(out)" "pack 'zorbcorp' has no checkout in the registry"
t_eq "...nothing cloned beyond the documented harbor step" "harbor " "$(checkouts)"
box packpriv 'components = ["core"]
packs = ["harbor-private"]'; run
t_eq "the private layer's own pack, with no registry row: exit (harbor#1273)" 0 "$RC"
t_eq "...nothing cloned for it" "harbor " "$(checkouts)"

t_section "a repo is cloned from its registry remote, not from <harbor's owner>/<id>"
PK='components = ["core"]
packs = ["thing"]'
ROW="thing${TAB}thing${TAB}workload${TAB}https://github.com/other/thing.git"
box otherowner "$PK" "$ROW"; mkbare other/thing real; mkbare acme/thing decoy; run
t_eq "a pack under another owner: exit" 0 "$RC"
t_eq "...gh cloned the registry's repo, not harbor's owner's namesake" "acme/harbor other/thing" "$(clones | sed 's/ $//')"
t_eq "...so the checkout is the real one" real "$(cat "$H/port/thing/README")"
t_eq "...and its origin is the registry's remote" "https://github.com/other/thing.git" "$(git -C "$H/port/thing" config --get remote.origin.url)"
t_has "...and the run says where it came from" "$(out)" "thing: cloned from github.com/other/thing into $H/port/thing"
box otherowner2 "$PK" "$ROW"; mkbare other/thing real; mkbare acme/thing decoy; GH_AUTH=1 run "$GIT_HARBOR && $BOOT"; GH_AUTH=''
t_eq "the same without a gh login: exit" 0 "$RC"
t_eq "...plain git cloned the registry's repo" real "$(cat "$H/port/thing/README")"
t_eq "...gh cloned nothing" "" "$(clones)"
box nothere "$PK" "$ROW"; mkbare acme/thing decoy; run
t_eq "a registry remote that does not exist, with a namesake under harbor's owner: exit" 1 "$RC"
t_has "...names the repo it tried" "$(out)" "gh repo clone other/thing failed"
t_eq "...and does not fall back to the namesake" "harbor " "$(checkouts)"
box dash "$PK" "thing${TAB}thing${TAB}workload${TAB}-"; mkbare acme/thing owners; run
t_eq "remote - means harbor's owner: exit" 0 "$RC"
t_eq "...and that is the repo cloned" owners "$(cat "$H/port/thing/README")"
t_has "...and the owner it came from is named" "$(out)" "cloning from github.com/acme"
box norow "$PK" "other${TAB}other${TAB}workload${TAB}https://github.com/other/other.git"; mkbare acme/thing owners; run
t_eq "a pack the registry lacks is still an error: exit" 1 "$RC"
box ssh "$PK" "thing${TAB}thing${TAB}workload${TAB}git@github.com:other/thing.git"; mkbare other/thing real; run
t_eq "a github ssh spelling is the same repo: exit" 0 "$RC"
t_eq "...cloned as other/thing" "acme/harbor other/thing" "$(clones | sed 's/ $//')"
box otherhost "$PK" "thing${TAB}thing${TAB}workload${TAB}https://git.example.test/team/thing.git"; mkbare elsewhere/team/thing hosted; mkbare acme/thing decoy; run "$GIT_HARBOR && $BOOT"
t_eq "a remote on another https host: exit" 0 "$RC"
t_eq "...is cloned from it, with git" hosted "$(cat "$H/port/thing/README")"
t_eq "...and gh was not asked about it" "" "$(cat "$T/log.ghall")"
t_has "...and the run says where it came from" "$(out)" "thing: cloned from https://git.example.test/team/thing.git into $H/port/thing"
box origpath "$PK" "$ROW"; mkbare other/thing real; run "git clone -q '$REM/acme/harbor.git' ~/port/harbor && $BOOT"
t_eq "every clone has a remote, so harbor's own origin may be a path: exit" 0 "$RC"
t_hasnt "...and no owner was looked for" "$(out)" "cloning from github.com/"
box compother 'components = ["core", "yard"]' "project-init${TAB}project-init${TAB}workload${TAB}https://github.com/other/project-init.git"
mkbare other/project-init realpi justfile; run
t_eq "a component's repo also comes from its registry row: exit" 0 "$RC"
t_eq "...gh cloned other/project-init" "acme/harbor other/project-init" "$(clones | sed 's/ $//')"
t_eq "...into the directory deploy reads" realpi "$(cat "$H/port/project-init/README")"

t_section "each variable names its own checkout: HARBOR_PROJECT_INIT is yard's, PROJECT_INIT_SRC is prod-guard's"
box ovr 'components = ["core", "yard", "prod-guard"]'
run "$GIT_HARBOR && git clone -q https://github.com/acme/project-init.git ~/port/yard-src && git clone -q https://github.com/acme/project-init.git ~/port/guard-src && HARBOR_SCOPE_SCAFFOLDER=\$HOME/port/yard-src PROJECT_INIT_SRC=\$HOME/port/guard-src $BOOT"
t_eq "two different checkouts exported: exit" 0 "$RC"
t_has "yard's is the one HARBOR_PROJECT_INIT names" "$(out)" "project-init: present at $H/port/yard-src, not touched"
t_has "prod-guard's is the one PROJECT_INIT_SRC names" "$(out)" "project-init: present at $H/port/guard-src, not touched"
t_eq "...and the default directory was not made" no "$([ -e "$H/port/project-init" ] && echo yes || echo no)"
box ovrmiss 'components = ["core", "yard"]'
run "$GIT_HARBOR && HARBOR_SCOPE_SCAFFOLDER=\$HOME/port/yard-src $BOOT"
t_eq "an exported directory that is not there yet: exit" 0 "$RC"
t_eq "...gets the repo the table's default names, not one named for the directory" "acme/project-init" "$(clones | sed 's/ $//')"
t_eq "...and it is on main in the exported directory" main "$(git -C "$H/port/yard-src" symbolic-ref --short HEAD 2>/dev/null || echo none)"

t_section "gh is for private repos, not a precondition"
box nologin 'components = ["core", "yard"]'; GH_AUTH=1 run; GH_AUTH=''
t_eq "gh not logged in, a clone needed: exit" 0 "$RC"
t_eq "...plain git cloned it" "harbor project-init " "$(checkouts)"
t_eq "...gh cloned only the documented harbor step" "acme/harbor" "$(clones | sed 's/ $//')"
t_has "...warned that gh is missing or not logged in" "$(out)" "gh is missing or not logged in"
t_has "...and that only public repositories are reachable" "$(out)" "reaches public repositories only"
box private 'components = ["core", "yard"]'; rm -rf "$REM/acme/project-init.git"; GH_AUTH=1 run "$GIT_HARBOR && $BOOT"; GH_AUTH=''
t_eq "a repo plain git cannot reach: exit" 1 "$RC"
t_has "...reason" "$(out)" "only a public repository can be cloned"
t_has "...the fix is gh" "$(out)" "install gh (https://cli.github.com), gh auth login"
t_eq "...deploy never ran" "" "$(cat "$T/log.inst")"
box gone 'components = ["core", "yard"]'; rm -rf "$REM/acme/project-init.git"; run
t_eq "a repo gh cannot clone: exit" 1 "$RC"
t_has "...the fix is the gh command" "$(out)" "  fix: gh repo clone acme/project-init '$H/port/project-init'"

t_section "refused before any write"
refused() { # <label> <reason> — after the documented clone, bootstrap writes nothing and runs no deploy
  t_eq "$1: exit" 1 "$RC"
  t_has "$1: reason" "$(out)" "$2"
  t_eq "$1: only the documented harbor clone" "harbor " "$(checkouts)"
  t_eq "$1: no download" "" "$(cat "$T/log.curl")"
  t_eq "$1: nothing under ~/.local" no "$([ -e "$H/.local" ] && echo yes || echo no)"
  t_eq "$1: deploy never ran" "" "$(cat "$T/log.inst")"
}
box win 'components = ["core", "yard"]'; UNAME=MINGW64_NT-10.0-22631 run; UNAME=''
refused "a native Windows shell" "native Windows shell"
t_has "...naming WSL2 as the way in" "$(out)" "WSL2"
box notgit 'components = ["core", "yard"]'; mkdir -p "$H/port/project-init"; run
refused "a non-checkout where a repo belongs" "project-init: $H/port/project-init exists and is not a git checkout"
box badtoml 'components = ["core", "bogus"]'; run
refused "a component that does not exist" "harbor.toml components: 'bogus' is not a component"
box oddowner 'components = ["core", "yard"]'; run "git clone -q '$REM/acme/harbor.git' ~/port/harbor && $BOOT"
refused "repos to clone and an origin that names no owner" "so the repos to clone have no owner"
box elsewhere 'components = ["core"]'; run "gh repo clone acme/harbor ~/src/harbor && sh ~/src/harbor/bin/deploy-bootstrap.sh"
t_eq "a checkout outside HARBOR_SCOPE_REPO: exit" 1 "$RC"
t_has "...reason" "$(out)" "but HARBOR_SCOPE_REPO is $H/port/harbor"
t_eq "...nothing cloned beside it" "acme/harbor" "$(clones | sed 's/ $//')"
for badrem in 'https://user:s3cr3tT0ken@github.com/other/thing.git' 'http://github.com/other/thing.git' 'ext::sh -c id' \
              'file:///etc/passwd' '--upload-pack=id' 'git@gitlab.com:other/thing.git' 'https://github.com/other/thing/extra.git' \
              'https://git.example.test/a/../b.git' 'https://git.example.test/a?x=1' 'https://git.example.test'; do
  BR=$((${BR:-0} + 1)); box "badrem$BR" "$PK" "thing${TAB}thing${TAB}workload${TAB}$badrem"; mkbare acme/thing decoy; run "$GIT_HARBOR && $BOOT"
  refused "remote '$badrem'" "thing: its remote in repos.tsv is not an https URL"
  t_has "remote '$badrem': the fix names the row" "$(out)" "correct the remote of the thing row in repos.tsv"
  t_hasnt "remote '$badrem': the registry's text is not echoed" "$(out)" "s3cr3tT0ken"
done
box help 'components = ["core"]'; run "$GH_HARBOR && sh ~/port/harbor/bin/deploy-bootstrap.sh --help"
t_eq "--help: exit" 0 "$RC"
t_has "--help: opens on the tool's name" "$(out)" "deploy-bootstrap.sh (harbor#829) — a fresh machine"
t_has "--help: reads to the end of the header" "$(out)" "logged in, else plain git over https."
t_eq "--help: and stops there, ten header lines" 10 "$(wc -l < "$T/out.txt" | tr -d ' ')"
t_eq "--help: ran nothing" "" "$(cat "$T/log.inst")$(cat "$T/log.curl")"
box args 'components = ["core"]'; run "$GH_HARBOR && sh ~/port/harbor/bin/deploy-bootstrap.sh --apply"
t_eq "an argument (--apply included) is a usage error" 2 "$RC"
t_eq "...and nothing ran" "" "$(cat "$T/log.inst")$(cat "$T/log.curl")"
t_done
