#!/usr/bin/env sh
# scope-marker-backfill.sh's output follows contracts/logging.md (harbor#771): each repo is a log line (written or already
# declared is ok, would-write a note, a skip a WARN with its fix), a refused fleet is a FAIL with its fix, and the run
# ends with the summary. A stub projects-orchestrator and fixture repos stand in for the fleet.
. "$(dirname "$0")/../../lib/core.sh"; t_init
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE; export GIT_CONFIG_NOSYSTEM=1
TOOL="$T_ROOT/bin/scope-marker-backfill.sh"
H="$T_TMP/home"; B="$T_TMP/bin"; PO="$T_TMP/po"; F="$T_TMP/fleet"; mkdir -p "$H" "$B" "$PO" "$F"
for r in fresh declared dirty; do mkdir -p "$F/$r/.agents"; done
printf 'project:\n  name: fresh\n' > "$F/fresh/.agents/config.yaml"
printf 'context: ambient\nproject:\n  name: declared\n' > "$F/declared/.agents/config.yaml"
printf 'project:\n  name: dirty\n' > "$F/dirty/.agents/config.yaml"
git -C "$F/dirty" init -q; printf 'untracked\n' > "$F/dirty/stray"
cat > "$B/projects-orchestrator" <<EOT
#!/bin/sh
printf '[{"descriptor":{"name":"fresh","path":"$F/fresh","config_root":".agents"}},{"descriptor":{"name":"declared","path":"$F/declared","config_root":".agents"}},{"descriptor":{"name":"dirty","path":"$F/dirty","config_root":".agents"}}]\n'
EOT
chmod +x "$B/projects-orchestrator"
run() { env PATH="$B:$PATH" HOME="$H" CLAUDE_CONFIG_DIR="$H/.claude" HARBOR_SCOPE_FLEET_CONTROLLER="$PO" sh "$TOOL" "$@" >"$T_TMP/out" 2>"$T_TMP/err"; echo "exit $?"; }
OUT() { cat "$T_TMP/out"; }; ERR() { cat "$T_TMP/err"; }
after() { awk -v p="$1" '$0 ~ p { f = 1; next } f { print; exit }' "$T_TMP/out"; }

t_section "a dry run: notes and WARNs, nothing written, exit 0"
t_eq "exit 0" "exit 0" "$(run)"
t_eq "the header names the fleet" "── marker-backfill · fleet: 3 governed repos (read from $PO)" "$(OUT | head -1)"
t_has "the dry run is a note carrying the command" "$(OUT)" "  note: DRY RUN — nothing is written; to write: sh $TOOL --apply"
t_has "a repo it would write is a note" "$(OUT)" '  note: fresh: would prepend "context: repo"'
t_has "an already-declared repo is an ok line" "$(OUT)" "  ok: declared: already declares context: ambient"
t_has "a dirty tree is a WARN" "$(OUT)" "  WARN: dirty: WOULD WRITE, but the tree is dirty"
t_has "with its fix" "$(after '^  WARN: dirty')" "  fix: git -C $F/dirty status --short"
t_eq "the fresh config is untouched" "project:" "$(head -1 "$F/fresh/.agents/config.yaml")"
t_eq "the summary" "marker-backfill: 1 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"
t_eq "stderr is empty" "" "$(ERR)"
# Fixed strings, not a bracket: under LC_ALL=C a bracket matches single bytes, which `──` shares.
t_eq "no legacy glyph is left" 0 "$(OUT | grep -cF -e '⊘' -e '✓' -e '→')"

t_section "--apply: the write is an ok line"
t_eq "exit 0" "exit 0" "$(run --apply)"
t_has "the write" "$(OUT)" "  ok: fresh: wrote context: repo"
t_eq "the key is on disk" "context: repo" "$(head -1 "$F/fresh/.agents/config.yaml")"
t_eq "the summary" "marker-backfill: 2 ok, 0 failed, 1 warnings" "$(OUT | tail -1)"

t_section "the standard's scope: key is already a declaration (harbor#963)"
mkdir -p "$F/scoped/.agents" "$F/nested/.agents" "$H/.local/bin"
printf 'scope: project\nproject:\n  name: scoped\n' > "$F/scoped/.agents/config.yaml"
printf 'project:\n  scope: user\n' > "$F/nested/.agents/config.yaml"
# The CLI from the roots table's row (contracts/roots.tsv), with nothing of that name on PATH.
cat > "$H/.local/bin/projects-orchestrator" <<EOT
#!/bin/sh
printf '[{"descriptor":{"name":"scoped","path":"$F/scoped","config_root":".agents"}},{"descriptor":{"name":"nested","path":"$F/nested","config_root":".agents"}}]\n'
EOT
chmod +x "$H/.local/bin/projects-orchestrator"; mv "$B/projects-orchestrator" "$B/off"
t_eq "exit 0" "exit 0" "$(run --apply)"
t_has "the fleet CLI came from the roots row" "$(OUT | head -1)" "fleet: 2 governed repos"
t_has "scope: project is declared" "$(OUT)" "  ok: scoped: already declares scope: project"
t_eq "...and no context: line was added" "scope: project" "$(head -1 "$F/scoped/.agents/config.yaml")"
t_has "an indented scope: is left for a person" "$(OUT)" "  WARN: nested: has an INDENTED context: or scope: key; resolve by hand"
rm -f "$H/.local/bin/projects-orchestrator"; mv "$B/off" "$B/projects-orchestrator"

t_section "an empty fleet: FAIL, its fix, exit 1"
printf '#!/bin/sh\nprintf "[]\\n"\n' > "$B/projects-orchestrator"
t_eq "exit 1" "exit 1" "$(run)"
t_has "the FAIL" "$(OUT)" "  FAIL: the fleet is EMPTY as read from $PO"
t_has "its fix" "$(after '^  FAIL: the fleet')" "  fix: cd $PO"
t_eq "the summary" "marker-backfill: 0 ok, 1 failed, 0 warnings" "$(OUT | tail -1)"

t_section "an unknown argument: FAIL, its fix, exit 2"
t_eq "exit 2" "exit 2" "$(run --bogus)"
t_has "the FAIL" "$(OUT)" "  FAIL: unknown argument: --bogus"
t_eq "its fix" "  fix: sh $TOOL --help" "$(after '^  FAIL: unknown')"
t_done
