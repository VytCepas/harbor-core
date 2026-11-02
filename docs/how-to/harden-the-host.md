# SEC-0 — hand-harden the box (do first, platform-independent)

The one step to run **before** any Harbor building, on whichever machine you build on. It makes your box safe regardless of the fork decision. Script: [`bin/deploy-harden.sh`](../../bin/deploy-harden.sh).

*Reconciled 2026-07-23 against the actual build box (the Mac) and the implementation-readiness review — see `docs/reports/2026-07-23-review.md`, findings F1/F2/F3/F12/F13.*

## Run it (dry-run first, always)
```sh
sh bin/deploy.sh --only sec0 --live           # DRY RUN — deploy's preflight, then exactly what would change
sh bin/deploy.sh --only sec0 --apply --live   # writes, through deploy: snapshot first, verify after (the pre-run settings.json also goes to backups/sec0-harden/<TS>/)
sh bin/deploy-harden.sh --apply --dir <sandbox> # the script itself, against a throwaway config dir
```
The live box is written only through `deploy.sh`, the one live entry (the install standard §4, harbor#800); `deploy-harden.sh --live` still prints its own plan. Needs `jq` + `gh`. Cross-platform (macOS + WSL). Idempotent — safe to run twice. The target is always named: `--live` for `~/.claude`, `--dir PATH` for anything else; `CLAUDE_CONFIG_DIR` never picks it, and one that disagrees with the target is refused (the install standard, harbor#765).

## What it does
1. **Removes interpreter / arbitrary-install auto-allows** from `permissions.allow` — `python3 */awk */sed */perl/ruby/node/npx/bunx` and `bun add / uv pip install / npm install / pip install / cargo add`. They no longer auto-run; they prompt. *(On the Mac this is a verify-only no-op — its settings.json has no `permissions` key at all; the step matters on the WSL box.)*
2. **Resets a permissive `defaultMode`** (`acceptEdits` or `bypassPermissions`) **→ `default`** and sets the one **un-overridable mode lock** — `permissions.disableBypassPermissionsMode: "disable"` — so the box can never silently enter bypass mode, from any scope or CLI flag. *(Amended 2026-07-24, owner decision: `disableAutoMode` is no longer set — the script now deletes it if present — and `defaultMode: "auto"` is permitted, to allow low-prompt agent operation. Auto mode's classifier still prompts on risky actions, and the deny set applies in every mode.)*
3. **Adds a `permissions.deny` set** for secret reads — `~/.ssh`, `~/.config/gh`, `~/.aws`, `~/.config/gcloud`, `~/.gnupg`, `~/.password-store`, `~/.kube`, `~/.docker/config.json`, `~/.netrc`, `~/.npmrc`, `~/.pypirc`, `**/.env*`, `**/secrets/**`, `*.pem`, `id_rsa/id_ed25519`, and (on WSL) `/mnt/c/Users/**`. Project-relative patterns are **depth-any (`**/`)** — a `./`-anchored pattern only matches the repo root and would leave nested monorepo secrets (`packages/*/.env.production`) silently readable. Deny overrides allow in every mode.
4. **Backs up** `settings.json` to `~/.claude/backups/` before writing, and **hash-pins a baseline** to `~/.claude/.sec0-baseline.sha256` covering the deny array, the mode locks, **and the plugin surface** (`enabledPlugins` + `extraKnownMarketplaces`) — plugins ship hooks/skills/MCP servers and auto-update, so drift there must alarm exactly like a deny-array edit. This is the drift baseline for the later B6 integrity gate.
5. **Merges four decided `env` keys** into `.env`, each forced to `"1"` (harbor#816, operator 2026-09-29): `DISABLE_ERROR_REPORTING`, `DISABLE_FEEDBACK_COMMAND`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`, `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL`. Deliberately **not** set — the operator keeps Remote Control, which needs them: `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`. No other `env` key is ever removed or changed; if the operator later sets one of those three by hand, it survives every re-run. Adding `.env` for the first time is a new top-level key, which the baseline's `keys` field (item 4) already tracks — the same re-pin covers it. `bin/deploy-live-verify.sh`'s `sec0-env` check reports these four live, read-only, with a `fix:` line naming `deploy.sh --only sec0 --apply --live`.

## The gh token — two tokens, two roles (corrected)
The old advice ("drop `workflow`, `gh auth login` with a fine-grained token") was wrong on three counts and is superseded:
- Classic `workflow` scope governs **writing** `.github/workflows` files, not triggering runs — dropping it does **not** stop workflow dispatch (that needs only `repo`), but it **does** break any push that touches workflow files, which Harbor's own tickets (D6, K5) do.
- `gh auth login --with-token` with a narrow token **replaces the keyring credential**, cutting `gh` off from every other repo.
- Therefore: **keep the interactive daily-driver login as-is** (it must stay able to author CI), and **mint a separate fine-grained token** — Contents: read/write on `helm-log` only — for the automated work-log sync (G1/G2), fed to the sync hook via its own credential (`GH_TOKEN` env / dedicated git credential entry). Optional tightening later: move the daily driver itself to a fine-grained token scoped to the repos you build, keeping Actions/workflow write.
- **Gotcha, measured and easy to misdiagnose:** a freshly-minted fine-grained PAT can lag several minutes before its first push is accepted. The failure looks exactly like a wrong scope, so the natural response is to widen the token — which is the opposite of what SEC-0 is for. Wait, retry, and only then suspect the scopes.

## Done when (SEC-0's real scope — nothing borrowed from Phase 2)
- A non-empty baseline hash exists and covers deny + mode lock (bypass; auto pinned absent) + plugins + marketplaces.
- A `Read` of `~/.ssh/id_*` **and** of a nested `packages/x/.env` is denied by the harness (red→green test).
- `defaultMode` is not `acceptEdits`/`bypassPermissions` (`auto` is allowed — owner decision 2026-07-24); the bypass lock reads `"disable"` and `disableAutoMode` is absent.
- The four harbor#816 `env` keys read `"1"`; `DISABLE_TELEMETRY`/`DO_NOT_TRACK`/`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are never set by this script, and no other `env` key is disturbed. A second run changes nothing.
- The G1 sync token plan is understood (separate fine-grained token; minted at G1, not now).

## What it deliberately does NOT do (owned by later workstreams)
- **Block `python3 -c` / shell-injection shapes** — glob deny-rules can't contain an interpreter; they still *prompt* (defaultMode `default`), nothing more. Red→green tests for these belong to **B3/K1** (Phase 2).
- **Protect `~/.claude` from self-edits/self-merge** — that's the **B2** containment guard (Phase 2); its test belongs to **K1**.
- **Prevent workflow self-dispatch** — a permissions question for the *separate* sync token (G1), not achievable by rescoping the daily driver.
- **Pin plugin *content*** — the baseline pins the plugin *list*; content integrity is the **B6** gate.
- **Split the web-fetching role** — do that per-subagent (no git/gh/write tools on any web-fetching agent); the script reminds you.

## Order
`SEC-0` → **FLEET-0** (orchestrator bootstrap on this box) → **Phase 0** (the decoupled slice) → Phase 2, gated on Phase-0 completion. See `docs/explanation/approach.md`.
