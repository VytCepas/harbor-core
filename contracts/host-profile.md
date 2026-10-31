# Box-profile seam (L0 Helm → L3 Yard) — FROZEN v1 (the plan's ONLY up-pointing read)

Every other edge in Harbor points **down** (Helm consumes the trio). This seam is the single exception: project-init's wizard *reads* a box profile the L0 environment declares — the box's preferred harnesses and its MCP roster — as **advisory defaults** (epic §1/§4, ticket J1). Left uncontracted, this edge silently couples the Yard to Helm and breaks the **D7 standalone guarantee** ("a repo works with no upstream platform"). Frozen here. *(Added 2026-07-23, REVIEW F11; amended 2026-07-24: **TOML, not YAML** — project-init's conventions ban pyyaml, and stdlib `tomllib` parses TOML with zero new dependencies. Owner: **BOX-1** = harbor#22 + the project-init implementation. Consumers: J1/PI-2 (project-init).)*

## The file
- Location: `~/.claude/box-profile.toml` (one per box; machine-local, never synced into repos). Override with the **`PROJECT_INIT_BOX_PROFILE`** env var (absolute path) — how a relocated `HELM_ROOT` points the Yard at it, and how tests stay hermetic.
- Producer: Helm (Phase 2) — or the operator by hand (Phase 0 / no platform installed).
- Envelope carries **`schema_version`** (int, starts at 1). Unknown major ⇒ treated as absent.

## Fields Helm may declare (all optional) and their exact consumer mapping
| Field | Type | Wizard default it seeds (advisory — every one still changeable) |
|---|---|---|
| `schema_version` | int | required in any present file; `1` |
| `harnesses` | array of strings | the agent-surfaces default. Values = project-init surface names (`claude`, `vscode`, `cursor`, `codex`, …); unknown names are ignored with one advisory line, never an error |
| `mcp_roster` | array of strings | the MCP-selection default, filtered to ids present in project-init's catalog; unknown ids ignored, advisory line |
| `profile` | `"personal"` \| `"org"` | the distribution-profile default: `personal` → `individual`, `org` → `org` (which also drives the governance-gate default per epic PI-6) |

Additive-only within a major version — same rules as every seam (see `README.md`).

## The non-negotiable clause
**Absent ⇒ fully functional.** With no box profile present (missing file, unreadable, malformed TOML, wrong/unknown `schema_version`, wrong field types), the wizard runs on baked-in defaults with **zero degradation and zero warnings** — byte-identical behavior to the pre-seam wizard (pinned by project-init's Enter-only equivalence test). When a profile IS present and consulted, the wizard prints exactly **one advisory line** naming the file and the defaults it seeded. The read is *advisory input to defaults*, never a dependency: project-init MUST pass its full suite with no profile on disk, and the loader returns the empty mapping on every failure path (never raises to the wizard).

## Fixtures (the shared suite, like the marker seam)
Golden fixtures live with the consumer (project-init `tests/deploy/fixtures/host-profile/` + `tests/deploy/unit/test_host_profile.py`); Helm vendors the same fixtures when it becomes the producer:
- `present.toml` — full profile; wizard defaults reflect every field.
- `partial.toml` — some fields; unspecified ones fall back to baked-in defaults.
- *absent* — no file; wizard fully functional, zero output (guards D7).
- `invalid.toml` — malformed TOML / unknown `schema_version` / wrong types; treated exactly as absent.
