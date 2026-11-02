---
kind: explanation
owner: @VytCepas
status: unreviewed
---

# Ideal-state prompting — the reasoning

**On-demand.** The rule is in [policy/constitution.md](../../policy/constitution.md)
§ *Ideal-state prompting*. These sentences moved out of it on 2026-11-01
(harbor#1392), when the resident file was cut to 15 KB.

**Load when:** writing or reviewing a skill, an agent brief or a workflow stage.

## Why the outcome, not the procedure

Choreographing execution ("first analyse X, then consider Y, then decide Z") caps
a capable model below its ability and rots as models improve. Precision goes *up*,
not down: an ideal-state prompt is more specific about the outcome, never vaguer.

## The four legitimate kinds of "how"

- **Safety gates:** confirmations, destructive-op guards.
- **Verified gotchas:** a documented non-obvious failure the model would otherwise
  hit.
- **Tool contracts:** exact CLI syntax, API params, paths.
- **Output-format contracts:** the required deliverable shape.

A procedural line a smarter model would make unnecessary is scaffolding; one it
would not is kept.
