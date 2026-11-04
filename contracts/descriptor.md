# Descriptor seam (L3 → L2 + L0) — ALREADY FIRST-CLASS: EXTEND, do not reinvent

**Source of truth:** `project-init` `schemas/descriptor.schema.json` — **contract version 2**, additive-only.
**Existing tests/CI (do not duplicate):** project-init `tests/policy/contracts/test_descriptor_schema.py`; orchestrator vendored copy + `tests/test_contract.py` + golden `config.v2.yaml` + `check_contract_freshness.py` + `.github/workflows/contract-freshness.yml`.

## The memory tier field (the one Harbor must not break)
`memory.tier` is an integer on the **REAL** ladder — verified against `_MEMORY_TIERS`:

| stack | tier |
|---|---|
| `auto` | **0** |
| `obsidian-only` (alias `obsidian`) | **1** |
| `obsidian-graphify` | **2** |
| `obsidian-graphify-rag` | **3** |

Orchestrator gates `graph_path` at tier ≥ 2 and `rag_endpoint` at tier ≥ 3. doctor **FAILs** a child whose `project_init_contract_version` is absent or below v1, and **WARNs** one newer than its `CONTRACT_VERSION_MAX` (pinned by the orchestrator's `doctor.py`, `descriptor-contract-v2.md` and `test_doctor.py`). A WARN does not change doctor's exit code, so doctor is not the lock-step guard for the v3 rule below (projects-orchestrator#221).

## Harbor rules for this seam
- **EXTEND** this schema + its tests **by path**; never author a parallel copy or a second conformance test (that is the exact drift `contract-freshness.yml` exists to prevent).
- Any new field (e.g. the `context` marker) is **ADDITIVE** within v2.
- Keep **every legacy stack name as a permanent recognized alias**; add an upgrade fixture so already-scaffolded repos don't blank their tier on upgrade (see the PI-606 rename-regression scar).
- Removing/renaming a value = **breaking v3** = lock-step orchestrator `CONTRACT_VERSION_MAX` bump in the same release.

_Owner: PI-4 / D4 (project-init). Consumers: orchestrator (D6), helm (D1–D3)._
