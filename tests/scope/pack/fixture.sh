# tests/scope/pack/fixture.sh - the throwaway workspace, git helpers and fixture pack the pack suites share.
# Sourced after core.sh's t_init: every pack, private layer and target is a directory under the suite's own temp dir.
PW="$T_TMP/ws"; mkdir -p "$PW/harbor-private"
PRIV="$PW/harbor-private"
pk() { env -u CLAUDE_CONFIG_DIR PORT_ROOT="$PW" HARBOR_SCOPE_PRIVATE="$PRIV" sh "$T_ROOT/bin/pack.sh" "$@"; }
G() { _g="$1"; shift; git -C "$_g" -c user.name=t -c user.email=t@example.test "$@"; }
snap() { ( cd "$1" && find . | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort -k3 && find . -type f -perm -u+x | LC_ALL=C sort ); }
listed() { printf 'packs = [%s]\n' "$1" > "$PRIV/harbor.toml"; }

# mkpack <id> [<harbor_version>]: a clean, committed pack with one of each entry.
mkpack() {
  _d="$PW/$1"; rm -rf "$_d"; mkdir -p "$_d/harbor-pack/skills/demo" "$_d/harbor-pack/bin" "$_d/harbor-pack/inject.d"
  printf 'name = "demo-%s"\nversion = "1.2.0"\nharbor_version = "%s"\ndescription = "a fixture"\n' "$1" "${2:->=1.0}" > "$_d/harbor-pack/pack.toml"
  printf -- '---\nname: demo\n---\nA demo skill.\n' > "$_d/harbor-pack/skills/demo/SKILL.md"
  printf '#!/bin/sh\necho demo\n' > "$_d/harbor-pack/bin/demo-tool"; chmod +x "$_d/harbor-pack/bin/demo-tool"
  printf -- '---\nid: demo-note\nevent: SessionStart\nwhen: always\n---\nA note.\n' > "$_d/harbor-pack/inject.d/demo.md"
  printf '# a fixture pack'"'"'s commands\nname\trel\ndemo-tool\tbin/demo-tool\n' > "$_d/harbor-pack/shims.tsv"
  printf '## Register\n\n| `demo-%s` | the demo | hourly | desktop | broken |\n\n## Platforms\n\n| demo-%s | macOS only | fixture | `launchctl bootout x` |\n' "$1" "$1" > "$_d/harbor-pack/checks.md"
  { grep -v '^#' "$T_ROOT/standards/naming/controls.tsv" | awk 'NF { print; exit }'
    printf 'check.demo-%s\twarn\tcheck\tCHECKS.md\t-\tschedule\tdetective\texperimental\t-\tcheck\t-\tdemo-%s\ta demo\n' "$1" "$1"; } > "$_d/harbor-pack/controls.tsv"
  G "$_d" init -q; G "$_d" add -A; G "$_d" commit -q -m fixture
}
