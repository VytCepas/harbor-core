#!/usr/bin/env sh
# tools.test.sh (harbor#1278, control hub.tools-admin) — bin/hub-tools.sh. `create` runs a fake gh and the exact calls are asserted: one private repo, the person
# write, every admin read, refused where the org shows private repos to every member. `admit` copies a proposed skill into a hub pack and runs the real
# hub-gate.sh: a clean skill passes, and a skill the gate refuses (a hooks: key, a core name, a symlink) is refused and leaves the hub as it was.
. "$(dirname "$0")/../../lib/core.sh"; t_init
. "$T_ROOT/tests/hub/fixtures/make-hub.sh"
T="$T_ROOT/bin/hub-tools.sh"; CALLS="$T_TMP/gh-calls"; GHBIN="$T_TMP/ghbin"; mkdir -p "$GHBIN"
cat > "$GHBIN/gh" <<'SH'
#!/bin/sh
{ printf 'CALL'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\n'; } >> "$GH_FAKE_LOG"
case "$1 $2" in
  "api orgs/acme") printf '%s\n' "${GH_FAKE_DEFAULT_PERM:-none}" ;;
  "repo view") exit "${GH_FAKE_EXISTS:-1}" ;;
esac
exit 0
SH
chmod +x "$GHBIN/gh"
export GH_FAKE_LOG="$CALLS" PATH="$GHBIN:$PATH" LEAKS_OWN_USER=fixture-own
unset HARBOR_MEMBER_ROLE
run() { _o="$(sh "$T" "$@" 2>&1)" && RC=0 || RC=$?; OUT="$_o"; }

t_section "1 - create: the exact calls"
: > "$CALLS"; run create bob --hub acme/hub --admin carol --admin dave
t_eq "exit 0" 0 "$RC"
t_eq "the org default permission is read first" 1 "$(grep -c '^CALL \[api\] \[orgs/acme\] \[--jq\] \[.default_repository_permission\]$' "$CALLS")"
t_eq "one private repo in the hub's own org, named for the login" 1 "$(grep -c '^CALL \[repo\] \[create\] \[acme/tools-bob\] \[--private\] \[--description\]' "$CALLS")"
t_eq "the person gets write" 1 "$(grep -c '^CALL \[api\] \[-X\] \[PUT\] \[repos/acme/tools-bob/collaborators/bob\] \[-f\] \[permission=push\]$' "$CALLS")"
t_eq "each admin gets read" 2 "$(grep -c 'collaborators/\(carol\|dave\)\] \[-f\] \[permission=pull\]$' "$CALLS")"
t_eq "nothing else was called" 0 "$(grep '^CALL' "$CALLS" | grep -vc 'repo\] \[view\|repo\] \[create\|orgs/acme\]\|collaborators')"
t_has "it says what the member's token needs, under its id" "$OUT" "hub.tools-admin: the member's hub token must list acme/tools-bob"
: > "$CALLS"; jq -n '{approval:{approvers:["erin"]}}' > "$T_TMP/policy.json"; run create bob --hub acme/hub --policy "$T_TMP/policy.json"
t_eq "admins come from a policy's approvers" 1 "$(grep -c 'collaborators/erin\] \[-f\] \[permission=pull\]$' "$CALLS")"
: > "$CALLS"; _o="$(GH_FAKE_EXISTS=0 sh "$T" create bob --hub acme/hub --admin carol 2>&1)" || :
t_eq "an existing repo is not created again" 0 "$(grep -c '\[repo\] \[create\]' "$CALLS")"
t_eq "...and its access is still set" 1 "$(grep -c 'collaborators/bob\]' "$CALLS")"

t_section "2 - create refuses what would expose or break"
: > "$CALLS"; _o="$(GH_FAKE_DEFAULT_PERM=read sh "$T" create bob --hub acme/hub --admin carol 2>&1)" && RC=0 || RC=$?; OUT="$_o"
t_eq "an org whose members read every private repo is refused" 1 "$RC"; t_has "...naming why" "$OUT" "default repository permission is 'read'"
t_eq "...before a repo exists" 0 "$(grep -c '\[repo\] \[create\]' "$CALLS")"
run create bob --hub acme/hub; t_eq "no admin source is refused" 2 "$RC"
run create 'bo b' --hub acme/hub --admin carol; t_eq "a login that is not one is refused" 2 "$RC"
run create bob --admin carol; t_eq "no hub is refused" 2 "$RC"
_o="$(HARBOR_MEMBER_ROLE=member sh "$T" create bob --hub acme/hub --admin carol 2>&1)" && RC=0 || RC=$?; t_eq "a member laptop has no admin side" 1 "$RC"
t_exit "usage" 2 sh "$T" frob

t_section "3 - admit: through the real hub gate"
H="$T_TMP/hub"; P="$T_TMP/personal"
skill() { mkdir -p "$1/skills/$2"; printf -- '---\nname: %s\ndescription: A proposed skill. USE WHEN a test needs one.\n%s---\n\n# %s\n' "$2" "${3:+$3
}" "$2" > "$1/skills/$2/SKILL.md"; }
tree() { ( cd "$1" && find . -path ./.git -prune -o -type f -exec cksum {} + | LC_ALL=C sort ); }
make_hub "$H"; rm -rf "$P"; skill "$P" fresh-skill
run admit skills/fresh-skill --hub-dir "$H" --pack member-tools --from "$P"
t_eq "a clean skill is admitted" 0 "$RC"; t_eq "...into the pack" yes "$([ -f "$H/packs/member-tools/harbor-pack/skills/fresh-skill/SKILL.md" ] && echo yes || echo no)"
t_eq "...listed in extension.json with its sha256" 1 "$(jq '[.files[] | select(.path == "skills/fresh-skill/SKILL.md")] | length' "$H/packs/member-tools/extension.json")"
_g="$(sh "$T_ROOT/bin/hub-gate.sh" "$H" 2>&1)" && t_pass || t_fail "the hub gate agrees ($_g)"
t_has "it names the manual steps" "$OUT" "list the pack's commit in policy.json"
# the refusals
refuse() { # <label> <expected gate text> <skill> <front matter> [after-hook]
  make_hub "$H"; rm -rf "$P"; skill "$P" "$3" "${4:-}"; [ -z "${5:-}" ] || "$5"
  _b="$(tree "$H")"; run admit "skills/$3" --hub-dir "$H" --pack member-tools --from "$P"
  t_eq "$1: refused" 1 "$RC"; t_has "$1: the gate's words" "$OUT" "$2"; t_eq "$1: the hub is as it was" "$_b" "$(tree "$H")"
  t_eq "$1: no pack folder left" no "$([ -e "$H/packs/member-tools" ] && echo yes || echo no)"
}
refuse "a hooks: key" "has a hooks: key" hooked 'hooks: x'
refuse "a key outside the allowlist" "is not in contracts/pack-frontmatter-keys.txt" odd 'user-invocable: true'
refuse "a core skill's name" "shadows a core skill" audit-claims
mklink() { ln -s SKILL.md "$P/skills/linked/alias.md"; }
refuse "a symlink" "symlink" linked '' mklink
t_exit "no --pack is usage" 2 sh "$T" admit skills/x --hub-dir "$H" --from "$P"
t_done
