# Platforms — where every solution runs

**Seam:** shared canonical — Harbor, `project-init`, `projects-orchestrator`, and every repo
`project-init` scaffolds. **Status: written 2026-09-30 (harbor#832, epic harbor#831), not yet
enforced:** each refusal below names the ticket that will build it, so no one reads it as checked.

**The decision (operator, 2026-09-30):** macOS and Linux. On Windows, only inside WSL2. It
reverses harbor#615 (2026-09-22, native Windows 11 under Git Bash), closed as not planned.

## The rules

1. **Supported: macOS and Linux.** WSL2 is Linux, and is supported on the same terms.
2. **On Windows, work inside the WSL filesystem** (`~/…`), never across `/mnt/c/…`. Editing WSL
   files from the Windows side mangles executable bits and line endings (project-init's README,
   "WSL: phantom permission/CRLF changes").
3. **A native Windows shell is refused at every entry point: what installs, and what a person
   types.** Native means `uname -s` starts with `MINGW`, `MSYS` or `CYGWIN` (Git Bash, MSYS2,
   Cygwin), or Python's `platform.system()` is `Windows`. The refusal names WSL2 as the way in. A
   refusal, not a best-effort run: a guard that loads on a platform nobody proved it on and then
   fails to match is worse than one that never loads. Hooks need no gate of their own, because
   only the refusing installer wires them. A script run by its path from a checkout is not an
   entry point and is not gated.

## Per implementation

| Repo | Refuses at | Status |
|---|---|---|
| Harbor | `bin/deploy.sh`, the one install entry, so no floor is wired on an unproved platform; and `bin/harbor`, the dispatcher every verb goes through | enforced (harbor#833): `tests/deploy/deploy/standard.test.sh`, `tests/deploy/cli/cli.test.sh` |
| `project-init` | the scaffolder (scaffold and upgrade), and the SessionStart hook it scaffolds | project-init#1070, which also removes the `windows-portability` CI job and the Windows-only branches |
| `projects-orchestrator` | CLI entry | projects-orchestrator#326 |

## What Linux support does not yet cover

Harbor runs its suites on `ubuntu-latest`, but one of its parts is macOS-only today, and on WSL2
it is Linux work: the seven `docs/reference/checks.md` rows scheduled through launchd (harbor#617).

The macOS-only tool calls of harbor#618 are ported: the Keychain (libsecret), clipboard, BSD
`stat -f`, `date -j`/`-v`, `base64 -D`, `open` and the install hint (`pkg_hint` in `bin/library-log.sh`
names brew on macOS and apt-get, dnf, pacman, apk or zypper on Linux). A notifier with no sink or
no daemon (WSL2 often has neither) is a no-op that logs one note per run and keeps the edge for a
run that has one. What stays macOS-only says so in its header (`# platform: macOS-only — <reason>`),
and `tests/lint/platform/calls.test.sh` refuses a new bare call.
