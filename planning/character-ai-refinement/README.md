# Character + AI Refinement Workspace

This folder is a separate planning workspace for character and AI design work.
It is intentionally outside active runtime systems/submodules so you can refine
architecture without touching production code paths.

## Files

- `CHARACTER_SKILL_SYSTEM_PLAN.md`
  - Phased entity/data model for character, skills, abilities, and execution.
- `CHARACTER_DATA_FLOW.md`
  - End-to-end character runtime data flow (bootstrap, decision, execution, progression, persistence).
- `AI_SYSTEM_REFINEMENT_PLAN.md`
  - AI architecture baseline and migration phases for utility + planner + task VM.
- `SEMI_IDLE_CONTROL_MODEL.md`
  - Semi-idle control architecture, arbitration rules, and smallest vertical slice with on-screen UX.
- `FULL_ECS_RULES.md`
  - Non-negotiable DOTS/ECS constraints, minimal ECS component/system order, and merge validation gates.
- `SCRIPTING_ENGINE_ECS_INTEGRATION_PLAN.md`
  - Verified scripting-engine integration points, block contracts, and smallest scripted character-to-screen slice.

## How to use this workspace

1. Refine data contracts here first.
2. Lock a "v1" schema before implementation changes.
3. Port only approved pieces into runtime systems.
