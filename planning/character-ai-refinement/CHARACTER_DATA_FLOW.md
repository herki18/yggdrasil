# Character Data Flow (Refinement Draft)

## Scope
This document defines the runtime data flow for character systems so implementation can proceed without coupling mistakes.

References:
- `CHARACTER_SKILL_SYSTEM_PLAN.md`
- `AI_SYSTEM_REFINEMENT_PLAN.md`

---

## 0) Canonical Runtime Objects

Persistent runtime objects:
- `Character`
- `AbilityOwned` (per character-known ability)
- `ModifierInstance`
- `DefinitionCatalog` (singleton)

Transient runtime objects:
- `ActionExecution`
- `AbilityCandidate` (if materialized as entities instead of buffers)

Rule:
- Persistent state is host-owned and saveable.
- Transient state is frame/tick-scoped and never authoritative for saves.

---

## 1) Bootstrap Flow (Content -> Runtime Spawn)

Goal:
- Build runtime actor state from script definitions once content is loaded.

Input:
- Script blocks: character/skill/node/ability defs.

Output:
- `DefinitionCatalog`
- Spawned `Character` entities
- Spawned `AbilityOwned` entities linked to each character

Pipeline:
1. Load and validate all script definitions.
2. Compile/normalize IDs (no runtime string dependence in hot paths).
3. Populate `DefinitionCatalog`.
4. Spawn each `Character` from `CharacterDef`.
5. Initialize `SkillState` buffer and `KnownTier` buffer.
6. Spawn `AbilityOwned` per starting known ability and attach to owner via `KnownAbilityRef`.

Required invariants:
1. Every `KnownAbilityRef` points to a valid `AbilityOwned`.
2. `AbilityOwned.owner_entity` must match the character owning the reference.
3. Every node in `AbilityNodeEntry` resolves to a valid compiled `node_id`.

---

## 2) Decision Flow (Context -> Selected Action)

Goal:
- Convert world/perception state into one selected actionable ability.

Input:
- Character state (`Vitals`, cooldowns, known abilities, skills, known tiers).
- AI context/knowledge.
- Ability metadata (costs, reliability, risk, tags, range).

Output:
- Chosen `(ability_entity, target_entity)` for the character.

Pipeline:
1. Generate candidate list from `KnownAbilityRef`.
2. Apply hard gates first:
   - resource/cooldown checks
   - required skills exist
   - required tiers known
3. Score valid candidates with utility considerations.
4. Apply urgency + anti-thrash policy (inertia, commit window, replan cooldown).
5. Select best candidate and produce selection request.

Required invariants:
1. Hard-gate failures do not enter utility scoring.
2. Utility scores remain bounded and normalized.
3. Selection always returns explicit reason when no candidate is valid.

---

## 3) Execution Flow (Selection -> Resolved Outcome)

Goal:
- Execute one selected ability through node quality + outcome resolution.

Input:
- Selected ability/target.
- Character skills/tiers/resources.
- Ability node sequence and node definitions.

Output:
- Applied world changes (damage/heal/status/movement effects).
- Updated resources/cooldowns.
- Optional spawned delivery effects.

Pipeline:
1. Create `ActionExecution` transient context.
2. Re-check critical gates at execution start (target validity, resources).
3. Reserve/pay costs.
4. Iterate nodes in `AbilityNodeEntry`:
   - get complexity for node tier
   - compute margin/quality
   - evaluate failure/backfire paths
   - accumulate output/effect payload
5. Finalize hit/crit/outcome.
6. Apply outcome to world (`Vitals`, `ModifierInstance`, spawned effects).
7. Apply cooldown/charges updates.
8. Mark execution complete and destroy/pool `ActionExecution`.

Required invariants:
1. Node processing uses compiled IDs, not runtime string parsing.
2. Backfire/failure paths are explicit and produce reason codes.
3. World mutation is atomic at resolve boundary (or rollback-safe if split).

---

## 4) Progression Flow (Usage -> Growth)

Goal:
- Advance skills and unlock progression from actual usage/outcomes.

Input:
- Completed execution results.
- Skill/node participation info.
- Progression formulas/tables.

Output:
- Updated `SkillState` (xp/reps/technique/understanding/level).
- Feature unlock flags and possible new tier/ability unlocks.

Pipeline:
1. Map executed nodes to contributing skills.
2. Award progression tracks:
   - reps from use volume
   - technique from positive margins/success quality
   - understanding from discovery/research/observation events
3. Recompute level from tracks/xp policy.
4. Evaluate skill thresholds -> unlock features.
5. Optionally enqueue `LearningAttempt` for tier advancement pathways.

Required invariants:
1. Skill level changes do not implicitly grant tiers unless defined by learning rules.
2. Feature unlocks come from threshold policy, not ad hoc system checks.
3. Progression is deterministic for equal inputs.

---

## 5) Persistence Flow (Save/Load)

Goal:
- Persist only authoritative character progression/combat state.

Persist:
- Character identity and vitals
- skill buffers (`level`, `xp`, `reps`, `technique`, `understanding`)
- known tiers
- known abilities + runtime cooldown/charges state
- active modifiers (identity, remaining duration, stacks, deltas)

Do not persist:
- `ActionExecution` transient entities
- in-frame candidate lists unless needed for replay/debug

Load pipeline:
1. Restore `DefinitionCatalog` for current content version.
2. Restore persistent character/ability/modifier data.
3. Rebuild runtime links/references (`KnownAbilityRef` integrity pass).
4. Validate schema/content version compatibility.

Required invariants:
1. Saved ability/node IDs must resolve against current catalog.
2. Invalid references fail loudly with migration/error path.
3. No hidden defaulting of missing required data.

---

## 6) System Handoff Matrix

| Flow Stage | Reads | Writes |
|---|---|---|
| Bootstrap | Script defs | Catalog, Character, AbilityOwned, buffers |
| Decision | Character, AbilityOwned, Knowledge, Catalog | Selection request / candidate score data |
| Execution | Selection, Character, AbilityOwned, Catalog | ActionExecution, world state, modifiers, cooldowns |
| Progression | Execution outcome, Character | SkillState, feature unlock state, learning attempts |
| Persistence | Persistent runtime state | Save payload / restored runtime state |

---

## 7) Practical Build Sequence

1. Finalize ID scheme and compile boundary (`DefinitionCatalog` first).
2. Implement Bootstrap flow and integrity validation.
3. Implement Execution flow for one instant ability end-to-end.
4. Add Decision flow (hard gates + utility scoring).
5. Add Progression flow.
6. Add Persistence flow.

This order guarantees a playable vertical slice early while preserving clean architecture seams.
