# Harbor — Execution Approach

How to actually build this: thin slices, gates between them, dogfood everything, and **the security floor + a sandbox exist before upstream ever executes against anything real.**

## The rhythm (one line)
**SEC-0 today → FLEET-0 → Phase 0 (value, no platform), each ticket shipped + verified before the next → when Phase 0 is complete and stable: fork → floor → sandbox-install → diff → wrapped live install → ratchet up A–K, each reversible.**

## Start today, independent of everything: SEC-0
Hand-harden the live box now (`bin/sec0-harden.sh` — corrected 2026-07-23, REVIEW F1/F2/F3/F12/F13) — it makes your machine safe whether or not you ever touch upstream, and it's the prerequisite for anything that widens reach:
- Depth-any (`**/`) secret-read `permissions.deny` (incl. `~/.kube`, `~/.docker/config.json`, `~/.netrc`, `~/.npmrc`, `~/.pypirc`) + a hash-pinned baseline covering deny + mode locks + the plugin surface.
- Reset a permissive `defaultMode` (`acceptEdits`/`bypassPermissions`); set the un-overridable `disableBypassPermissionsMode` lock. *(`disableAutoMode` dropped 2026-07-24, owner decision — auto mode allowed for low-prompt agents.)*
- Remove interpreter auto-allows + arbitrary-package installs from `~/.claude/settings.json` (verify-only no-op on the Mac — no `permissions` key exists there).
- Token: **keep** the daily-driver `gh` login (its `workflow` scope is required to push CI changes); the separate fine-grained `helm-log`-only token is minted at G1. Do NOT `gh auth login` with a narrow token — it replaces keyring auth.
- Split the web-fetching role from the acting role.

## Phase 0 — value WITHOUT the platform (no upstream platform install)
- FLEET-0: bootstrap the orchestrator CLI + a real `fleet.yaml` on this box (neither exists on the Mac — REVIEW F6).
- `helm-log` repo + the git-backed work-log.
- Vendor a handful of skills as plain markdown (they're prompts — `cp`, no engine) from the tracked home `harbor/vendor/skills/` (Phase-0 home rule, REVIEW F14).
- Statusline glyph over an **interval-written snapshot cache file** — never the live CLI per tick (REVIEW F6).
- Contract-preserving Yard wizard tweak (real baseline: ~22–26 prompts, not ~17 — REVIEW F9).

**The gate (decision 2026-07-23): step-by-step, completion-gated — no timed probation window.** The operator confirmed the full build is wanted; each ticket's Done-when is verified before the next starts, and Phase 2 begins when Phase 0 is complete and stable. The safety ORDER below is unchanged and non-negotiable. (History note: upstream v7.1.1 was live-installed on this Mac 2026-07-21 and fully removed 2026-07-23 — a deliberate clean-slate reset to avoid incidental conflicts before Harbor, **not** a platform verdict; the platform question stays open and Phase 2 remains planned.)

## WHEN to install upstream — Phase 2 only, in this exact order
1. **Fork + read (A1/A2)** — pure git + reading. Zero execution against `~/.claude`.
2. **Build the POSIX security floor FIRST (B), in a throwaway `CLAUDE_CONFIG_DIR`.** The thing that would contain a bad install must exist before the install.
3. **Install into the SANDBOX, never live** — a disposable copy of `~/.claude`, floor active; **diff the dir before/after** to see exactly what it wrote.
4. **Review the diff** vs the `FORK_CHANGES` ledger + the curated system prompt; reconcile surprises.
5. **Only then, a controlled live install** (checklist below).

Never in Phase 0, never before the floor, never live-first, never `curl | bash`.

## HOW to manage the live install (hard checklist)
- **From your fork at a pinned commit** — never `curl <upstream-site>/install.sh | bash`, never the "read-the-URL and install" flow.
- **Fresh backup + a *proven* restore** — `cp -r ~/.claude ~/.claude.bak-$DATE`; `restore.sh` already tested with a corrupt-then-restore run.
- **Append-only merge** — install ADDS, never overwrites your existing skills / `CLAUDE.md` / `permissions.deny`; verify byte-identity of pre-existing dirs afterward.
- **Kill-switch in place** — `HELM_DISABLE_FLOOR` so a self-locking guard (B2/B6) can't trap you.
- **Floor before, integrity gate after** — POSIX floor already live; install the recurring fail-closed integrity gate LAST so it doesn't fight the install.
- **Treat the installer tools as untrusted** — the `settings.json`-hooks mutators are `InstallHooks.ts`/`InstallSettings.ts` (verified 2026-07-23: additive, backup-first, consent-gated — `Doctor.ts` is read-only); never let them run unattended, review their diff. Harvest upstream's read-only `ScanConflicts.ts` for the I3 collision scan instead of rebuilding it.
- **One reversible step, verify, use, then next** — never batch risky changes.

## Platform: macOS is the primary Harbor home

**Decision (2026-07-23): macOS is the primary Harbor home and build target; WSL is the secondary / portability target.** The Mac is fully owned (CTO's own machine — no IT-policy constraint), so the earlier work-ownership objection does not apply.

**Why macOS is the easier build for the main solution (the Helm fork + monitoring):**
- It is upstream's **most-tested path** — the fork, Bun, the installer, and Doctor are developed and tested there, so far fewer platform edges to debug.
- **Pulse works fully** — always-on monitoring, menubar, voice, `launchd` scheduling — so the monitoring layer is built and tested for real, not spiked.
- **No platform-branch work:** native Keychain auth (no `SPIKE-WSL-AUTH`), no `XDG_STATE_HOME` gotcha, no dead `systemd --user`, no `/mnt/c` `fs.watch` caveats.

**Nothing was dropped — we KEEP both Pulse and the indexes:**
- **Pulse is kept.** "No daemon" only meant the *core* doesn't *require* a standing daemon; Pulse is an optional monitoring layer that runs fully on macOS.
- **The memory indexes are kept** — the KnowledgeGraph entity graph **and** BM25. "No DB" only means they are **rebuildable from canonical markdown**, not a persistent database that is the source of truth.

**WSL as the portability target:** the core (trio, POSIX floor, memory, work-log, skills) is identical on both and runs fine on WSL. The **only feature** that doesn't run on WSL is **Pulse always-on monitoring** — and it **breaks nothing else** (the core is reactive/on-demand); on WSL, monitoring degrades to on-demand `pulse serve` + cloud-side alerting. The one non-Pulse WSL asterisk is the auth path (`SPIKE-WSL-AUTH`: env-auth instead of Keychain) + a trivial `XDG` fallback — adaptations, not broken features.

**Cross-machine build order:** build the upstream-fork happy-path + Pulse on **macOS first** (where it's tested), then add the small WSL platform-branches so the core also runs on WSL. Easy build **and** portability.

> Practical note: the build agent runs where the Claude Code session runs — to build on the Mac, run the session on the Mac.
