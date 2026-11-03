#!/usr/bin/env sh
# `harbor repo new|adopt|list|audit` (harbor#1430): one run on a throwaway repo does every step the ticket lists and the repo is green on
# lint IJ2, IJ3, IJ6, the four sources, the kit, the label sync, the versions check and fleet's audit; then it is removed.
# STUBBED, because they would reach GitHub or need the sibling repos: the scaffolder (project-init: it renders the kit the way yard does,
# from standard-kit.sh --render), the fleet CLI (projects, register, audit) and gh (label list, apply). Everything else is harbor's real code.
# Every step has its own assertion, and the suite deletes each step from a copy of the command in turn: that step's assertion, and only
# that one, must go red (the wiring checklist's "A repo" row is this list).
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset CLAUDECODE HARBOR_DEPLOY_ACTIVE
T="$(CDPATH= cd -P -- "$T_TMP" && pwd -P)"
BIN0="$T_ROOT/bin"

# A copy of bin/ and the registers it reads, so a mutated command can run beside its siblings.
mkcopy() { # <dir> -> dir/bin, dir/standards, dir/contracts
  mkdir -p "$1"; cp -R "$BIN0" "$1/bin"; cp -R "$T_ROOT/standards" "$1/standards"; cp -R "$T_ROOT/contracts" "$1/contracts"
}
stubs() { # <dir for the stubs> <call log>
  S="$1"; mkdir -p "$S"
  cat > "$S/project-init" <<STUB
#!/bin/sh
# the scaffolder as yard would run it: render the kind's kit into the target
echo "project-init \$*" >> "$2"
[ "\$1" = new ] || exit 0; shift
tgt="\$1"; shift; kind=''; name=''; json=0; dry=0
while [ \$# -gt 0 ]; do case "\$1" in --kind) kind="\$2"; shift ;; --name) name="\$2"; shift ;; --json) json=1 ;; --dry-run) dry=1 ;; esac; shift; done
[ "\$dry" = 0 ] || { echo "would scaffold \$tgt as \$kind"; exit 0; }
mkdir -p "\$tgt/.agents" "\$tgt/.claude"
printf 'repo-kind: %s\n' "\$kind" > "\$tgt/.agents/config.yaml"; printf 'scaffolded\n' > "\$tgt/.claude/project-init.md"
sh "$BIN0/standard-kit.sh" --render "\$kind" | while IFS='	' read -r id item ref share vend; do
  case "\$item" in template|check) mkdir -p "\$tgt/\$(dirname "\$ref")"; [ -e "\$tgt/\$ref" ] || printf '%s\n' "\$id" > "\$tgt/\$ref" ;; esac
done
sh "$BIN0/standard-vendor.sh" "\$tgt" >/dev/null 2>&1
[ "\$json" = 0 ] || printf '{"name":"%s","path":"%s","kind":"%s"}\n' "\$name" "\$tgt" "\$kind"
STUB
  cat > "$S/projects-orchestrator" <<STUB
#!/bin/sh
echo "projects-orchestrator \$*" >> "$2"
sub="\$1"; shift
root=''; while [ \$# -gt 0 ]; do case "\$1" in --root) root="\$2"; shift ;; esac; shift; done
case "\$sub" in
  projects) for d in "\$root"/*/; do [ -f "\$d.agents/config.yaml" ] && printf '%s  (none, %s)\n' "\$(basename "\$d")" "\${d%/}"; done; exit 0 ;;
  audit) if [ -f "$S/fleet.red" ]; then echo '[{"project":"throwaway","findings":[{"category":"kit","severity":"warn","message":"as workload: kit: template.justfile lacks justfile"}]}]'; exit 1; fi
         echo '[{"project":"throwaway","findings":[{"category":"hooks","severity":"warn","message":"git hooks missing"},{"category":"freshness","severity":"warn","message":"never checked"}]}]'; exit 1 ;;
  *) exit 0 ;;
esac
STUB
  cat > "$S/gh" <<STUB
#!/bin/sh
echo "gh \$*" >> "$2"
[ "\$1 \$2" = "label list" ] && cat "$S/labels.tsv"
exit 0
STUB
  chmod +x "$S/project-init" "$S/projects-orchestrator" "$S/gh"
  mkdir -p "$S/gen"; sh "$BIN0/lint-name.sh" --gen labels --root "$S/gen" --registry "$T_ROOT/standards/naming" >/dev/null 2>&1
  grep -v -e '^#' -e '^name	' "$S/gen/build/naming/labels.tsv" > "$S/labels.tsv"
}
# A throwaway box: HOME, PORT_ROOT, the private layer (harbor scope install), a memory store, the stubs. $1 names it; sets B, PR, PV, CALLS.
box() {
  B="$T/$1"; HOME="$B/home"; PORT_ROOT="$B/home/port"; CLAUDE_CONFIG_DIR="$B/home/.claude"; mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
  export HOME PORT_ROOT CLAUDE_CONFIG_DIR
  CALLS="$B/calls"; : > "$CALLS"; stubs "$B/stubs" "$CALLS"
  HARBOR_SCOPE_SCAFFOLDER_BIN="$B/stubs/project-init"; HARBOR_SCOPE_FLEET_CONTROLLER_BIN="$B/stubs/projects-orchestrator"; HARBOR_SCOPE_GH="$B/stubs/gh"
  export HARBOR_SCOPE_SCAFFOLDER_BIN HARBOR_SCOPE_FLEET_CONTROLLER_BIN HARBOR_SCOPE_GH
  sh "$BIN0/scope.sh" install >/dev/null 2>&1
  PR="$PORT_ROOT"; PV="$PR/harbor-private"
  _hk="$(printf '%s' "$(CDPATH= cd -P -- "$HOME" && pwd -P)" | sed 's|/|-|g')"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/$_hk/memory"; printf 'a note\n' > "$CLAUDE_CONFIG_DIR/projects/$_hk/memory/note.md"
}
rp() { _c="$1"; shift; sh "$_c" "$@" > "$B/out" 2>&1 < /dev/null; _rc=$?; echo "exit $_rc"; }   # the output is in $B/out

NEW="new throwaway --kind workload --covers throwaway-case --domain - --owner op --slug acme/throwaway"

t_section "the command is in the table and the dispatcher: harbor repo --help lists the four"
box h
_h="$(sh "$BIN0/harbor" repo --help 2>&1)"
for v in new adopt list audit; do t_has "harbor repo --help lists $v" "$_h" "harbor repo $v"; done
t_has "the verb is a row of bin/harbor's help" "$(sh "$BIN0/harbor" help 2>&1)" "repo "
t_has "…and of contracts/cli.md" "$(cat "$T_ROOT/contracts/cli.md")" '| `harbor repo` | `scope-repo.sh` |'
. "$T_ROOT/tests/checks/lint-fixture.sh"
mkcopy "$T/cli"
t_eq "lint.cli-contract is green on a copy of the real tree" 0 "$(vcount "$(lint1 CLI1 "$T/cli")")"
grep -v '^| `harbor repo` |' "$T_ROOT/contracts/cli.md" > "$T/cli/contracts/cli.md"
t_has "…and red when the row is removed from the table" "$(lint1 CLI1 "$T/cli")" "VIOLATION [lint.cli-contract]"
sed 's/^repo	scope-repo.sh/repo	scope-ghost.sh/' "$T_ROOT/bin/harbor" > "$T/cli/bin/harbor"; cp "$T_ROOT/contracts/cli.md" "$T/cli/contracts/cli.md"
t_has "…and red when the dispatcher's verb points nowhere" "$(lint1 CLI1 "$T/cli")" "VIOLATION [lint.cli-contract]"

t_section "a dry run writes nothing and says what each step would do"
box d
t_eq "the dry run exits 0" "exit 0" "$(rp "$BIN0/scope-repo.sh" $NEW --dry-run)"
t_has "…it names the registry row it would append" "$(cat "$B/out")" "step registry: ok - would append: throwaway"
t_eq "…the registry still has only its header" 1 "$(grep -c . "$PV/repos.tsv")"
t_eq "…and no directory was made" no "$([ -e "$PR/throwaway" ] && echo yes || echo no)"

evidence() { # <step> -> yes|no : the step's own trace on the box and in the output
  case "$1" in
    scaffold) [ -f "$PR/throwaway/.agents/config.yaml" ] && [ -d "$PR/throwaway/.git" ] && grep -q '^  step scaffold: ok' "$B/out" ;;
    registry) awk -F'\t' '$1 == "throwaway" && $2 == "throwaway" && $3 == "workload" { f = 1 } END { exit !f }' "$PV/repos.tsv" ;;
    projects) awk -F'\t' '$1 == "throwaway" && $3 == "throwaway-case" { f = 1 } END { exit !f }' "$PV/context-rules/user/projects.tsv" 2>/dev/null ;;
    route) _k="$(printf '%s' "$(CDPATH= cd -P -- "$PR/throwaway" && pwd -P)" | sed 's|/|-|g')"; [ -n "$(find "$CLAUDE_CONFIG_DIR/projects/$_k/memory/" -name '*.md' 2>/dev/null | head -n 1)" ] ;;
    rules) [ -d "$PV/context-rules/throwaway" ] ;;
    labels) grep -q '^gh label list --repo acme/throwaway' "$CALLS" && grep -q '^  step labels: ok' "$B/out" ;;
    versions) grep -q '^  step versions: ok' "$B/out" ;;
    fleet) grep -q '^projects-orchestrator register' "$CALLS" && grep -q '^projects-orchestrator audit throwaway' "$CALLS" && grep -q '^  step fleet: ok' "$B/out" ;;
  esac && echo yes || echo no
}
STEPS="$(sed -n 's/^STEPS="\(.*\)"$/\1/p' "$BIN0/scope-repo.sh")"

t_section "repo new does every step in one run and the repo is green on every check"
box n
t_eq "repo new exits 0" "exit 0" "$(rp "$BIN0/scope-repo.sh" $NEW)"
for s in $STEPS; do t_eq "step $s left its trace" yes "$(evidence "$s")"; done
for c in ij2 ij3 ij6 sources kit labels versions fleet; do t_has "check $c is ok" "$(cat "$B/out")" "  check $c: ok"; done
t_has "the scaffolder was called through the dispatcher with the kind" "$(cat "$CALLS")" "project-init new $PR/throwaway --kind workload --name throwaway"
t_eq "the label sync read the repo and applied nothing without --github" 0 "$(grep -c '^gh label \(create\|edit\|delete\)' "$CALLS")"
t_eq "harbor repo list shows it in all four sources" "throwaway	throwaway	workload	yes	yes	yes	yes	yes" "$(sh "$BIN0/harbor" repo list 2>/dev/null | grep '^throwaway')"
t_eq "harbor repo audit exits 0" "exit 0" "$(rp "$BIN0/scope-repo.sh" audit throwaway)"
t_eq "a second repo new refuses a directory that exists" "exit 2" "$(rp "$BIN0/scope-repo.sh" $NEW)"
t_eq "adopt on the same checkout is idempotent" "exit 0" "$(rp "$BIN0/scope-repo.sh" adopt throwaway --kind workload --covers throwaway-case --slug acme/throwaway)"
t_eq "…and the registry still has one row for it" 1 "$(grep -c '^throwaway	' "$PV/repos.tsv")"
rm -rf "$PR/throwaway"
t_eq "the throwaway is removed" no "$([ -e "$PR/throwaway" ] && echo yes || echo no)"
t_has "…and with the checkout gone the audit is red on what the checkout carried" "$(rp "$BIN0/scope-repo.sh" audit throwaway; cat "$B/out")" "check kit"

t_section "an audit goes red when a source disagrees"
box a
rp "$BIN0/scope-repo.sh" $NEW >/dev/null
t_eq "a newborn repo's fleet warns (hooks, never checked) are not red: the audit above exited 0 while the stub's audit exits 1" "exit 0" "$(rp "$BIN0/scope-repo.sh" audit throwaway)"
: > "$B/stubs/fleet.red"
t_eq "a kit finding in fleet's audit is the repo's audit red" "exit 1" "$(rp "$BIN0/scope-repo.sh" audit throwaway)"
t_has "…and names the check" "$(cat "$B/out")" "check fleet: RED"
rm -f "$B/stubs/fleet.red"
grep -v '^throwaway	' "$PV/context-rules/user/projects.tsv" > "$B/p.tsv"; cp "$B/p.tsv" "$PV/context-rules/user/projects.tsv"
t_eq "a repo missing from projects.tsv fails the sources check" "exit 1" "$(rp "$BIN0/scope-repo.sh" audit throwaway)"
t_has "…and the line says what is present and what is missing" "$(cat "$B/out")" "present: registry,marker,fleet"

t_section "removing one step from the command turns that step's assertion red"
mkcopy "$T/mut"
for s in $STEPS; do
  box "m-$s"
  sed "/^STEPS=/ s/\\([\" ]\\)$s\\([\" ]\\)/\\1\\2/" "$BIN0/scope-repo.sh" > "$T/mut/bin/scope-repo.sh"
  t_eq "(the copy no longer lists $s)" 0 "$(sed -n 's/^STEPS="\(.*\)"$/\1/p' "$T/mut/bin/scope-repo.sh" | tr ' ' '\n' | grep -c "^$s\$")"
  rp "$T/mut/bin/scope-repo.sh" $NEW >/dev/null
  t_eq "without $s its assertion is red" no "$(evidence "$s")"
done
box "m-ctl"
rp "$BIN0/scope-repo.sh" $NEW >/dev/null
t_eq "control: the real command restored, every step's assertion is green again" "yes" "$(for s in $STEPS; do evidence "$s"; done | sort -u | tr '\n' ' ' | sed 's/ $//')"

t_done
