# Character + Skill System Plan (Phased Entity Data Model)

## Scope
This plan defines the runtime entity/data shape for a character + skill + ability pipeline, starting with a minimal base and expanding in phases.

Design basis:
- `Skill` = proficiency (execution quality)
- `Tier` = node knowledge (what version is known)
- `Feature` = access unlocks from skill thresholds

Persistent gameplay state is host-owned (Unity ECS). Script blocks provide definitions and formulas.

---

## Phase 1 - Base (Build This First)

### 1) `Character` Entity
Purpose: authoritative runtime actor state.

Core data:

| Component | Fields |
|---|---|
| `CharacterIdentity` | `character_id`, `display_name_id`, `faction_id`, `archetype_id` |
| `Vitals` | `health_current`, `health_max`, `mana_current`, `mana_max`, `stamina_current`, `stamina_max` |
| `CombatStats` | `base_damage`, `base_armor`, `base_speed`, `attack_range` |
| `WorldPosition` | `x`, `y`, `z` (or tile/world split if needed) |
| `SkillState` (buffer) | `skill_id`, `level`, `xp`, `reps`, `technique`, `understanding` |
| `KnownTier` (buffer) | `node_id`, `tier` |
| `KnownAbilityRef` (buffer) | `ability_entity` |
| `CharacterFlags` | `is_alive`, `is_player_controlled`, `is_in_combat` |

Notes:
- Keep `SkillState` separate from attributes; skills are the progression layer.
- `KnownTier` is independent from `SkillState.level`.

### 2) `AbilityOwned` Entity (One per known ability per character)
Purpose: compiled ability payload bound to owner.

Core data:

| Component | Fields |
|---|---|
| `AbilityIdentity` | `ability_id`, `owner_entity`, `script_block_id`, `action_type` |
| `AbilityNodeEntry` (buffer) | `node_id`, `tier`, `sequence_index` |
| `AbilityCost` | `mana_cost`, `stamina_cost`, `cast_time_ticks` |
| `AbilityOutput` | `base_damage`, `damage_type`, `range`, `aoe_radius` |
| `AbilityReliability` | `success_pct`, `partial_pct`, `fail_pct`, `critical_pct` |
| `AbilityRisk` | `backfire_pct`, `friendly_fire_pct` |
| `AbilityTag` (buffer) | `tag_id` |
| `AbilityRuntimeState` | `cooldown_remaining_ticks`, `charges_current`, `charges_max` |

Notes:
- This should be compiled/normalized data. Avoid string parsing in runtime hot paths.

### 3) `ActionExecution` Entity (Transient)
Purpose: active execution instance for one ability use.

Core data:

| Component | Fields |
|---|---|
| `ExecutionContext` | `execution_id`, `caster_entity`, `ability_entity`, `target_entity`, `start_tick` |
| `ExecutionProgress` | `current_node_index`, `quality_accumulator`, `processed_node_count` |
| `ExecutionOutcome` | `did_hit`, `was_crit`, `was_backfire`, `damage_dealt`, `backfire_damage`, `is_complete` |
| `ExecutionTiming` | `cast_end_tick`, `resolve_tick` |

Notes:
- Destroy after resolve or pool/reuse.
- Keep this separate from character entity to avoid transient write-noise on long-lived entities.

### 4) `ModifierInstance` Entity
Purpose: active buff/debuff/status state.

Core data:

| Component | Fields |
|---|---|
| `ModifierIdentity` | `modifier_id`, `instance_key_hash`, `source_entity`, `target_entity` |
| `ModifierLifetime` | `applied_tick`, `duration_ticks`, `expires_tick`, `is_permanent` |
| `ModifierStacking` | `stacking_mode`, `stacks_current`, `stacks_max` |
| `ModifierDelta` (buffer) | `stat_id`, `op` (`add`/`mult_bps`), `value` |
| `ModifierTag` (buffer) | `tag_id` |

Notes:
- Modifier values are runtime instances, not persisted in script block fields.

### 5) `DefinitionCatalog` Singleton Entity
Purpose: immutable runtime definition access.

Core data:

| Component | Fields |
|---|---|
| `DefinitionCatalogRef` | handles/refs to definition tables |
| `DefinitionVersion` | `content_version`, `build_hash`, `schema_version` |

Contained tables (logical shape):

| Definition | Required fields |
|---|---|
| `CharacterDef` | `display_name`, `base_health`, `base_mana`, `base_stamina`, `base_damage`, `base_armor`, `base_speed`, `attack_range`, `shape`, `skills[]`, `starting_abilities[]`, `known_tiers[]` |
| `SkillDef` | `display_name`, `category`, `threshold_levels[]`, `threshold_bonuses[]`, `threshold_types[]` |
| `NodeDef` | `name`, `category`, `complexity_t0`, `complexity_t1`, `complexity_t2`, `cost_mult_t0`, `cost_mult_t1`, `cost_mult_t2`, `output_type`, `tags[]`, `semantic_outputs[]` |
| `AbilityDef` | `display_name`, `description`, `character_type`, `mana_cost`, `stamina_cost`, `cast_time`, `range`, `aoe_radius`, `base_damage`, `damage_type`, `tags[]`, `node_sequence[]`, `required_skills[]`, `reliability_*`, `risk_*` |

---

## Phase 2 - Progression + Learning

### 6) `SkillTrainingSession` Entity
Purpose: timed training or practice pipelines.

Data:
- `owner_entity`
- `skill_id`
- `mode` (practice, mentor, study)
- `start_tick`, `end_tick`
- `rep_xp_gain`, `technique_xp_gain`, `understanding_xp_gain`

### 7) `LearningAttempt` Entity
Purpose: discovery/research/schema/mentor tier unlock attempts.

Data:
- `owner_entity`
- `node_id`, `target_tier`
- `method` (discovery, observation, research, schema, mentor)
- `requirements_snapshot`
- `success_chance_bps`
- `started_tick`, `resolve_tick`
- `result` (pending/success/fail)

---

## Phase 3 - Combat Delivery + AI Selection

### 8) `ProjectileOrAoEEffect` Entity
Purpose: delayed/impact/channel delivery runtime state.

Data:
- `source_execution_entity`
- `owner_entity`, `target_entity` (optional)
- `position`, `velocity`
- `radius`, `damage_payload`, `damage_type`
- `spawn_tick`, `expire_tick`
- `trigger_mode` (impact, delayed, channel_tick)

### 9) `AbilityCandidate` Entity or Buffer
Purpose: per-tick scored options for AI.

Data:
- `owner_entity`
- `ability_entity`
- `target_entity`
- `score_total`
- `score_breakdown` (kill, safety, success, range, resource)
- `instability_tax_pct`

### 10) `ReactiveTrigger` Entity
Purpose: auto-cast/reaction configuration and runtime checks.

Data:
- `owner_entity`
- `ability_entity`
- `trigger_type` (on_hit, on_damage_taken, on_threat_detected, etc.)
- `condition_params`
- `cooldown_group_id`

---

## Step-by-Step Build Order

1. Implement `DefinitionCatalog` + stable IDs for all definitions.
2. Implement `Character` + `AbilityOwned` entities and spawn wiring from definitions.
3. Implement `ActionExecution` flow for one instant ability path (no projectile yet).
4. Implement `ModifierInstance` application/expiry and derived stat aggregation.
5. Add `SkillTrainingSession` and `LearningAttempt`.
6. Add projectile/AoE delivery + AI candidate scoring + reactive triggers.

---

## Minimum Validation Rules (Start in Phase 1)

1. `AbilityReliability` percentages must be bounded and sum to 100 (or normalized once at compile).
2. `KnownTier(node, tier)` must be checked separately from skill level.
3. Required skills for an ability must exist on owner before execution.
4. No runtime string parsing for node execution in hot loops; compile to IDs up front.
5. Any modifier stat delta must validate `stat_id` and allowed op (`add`, `mult_bps`).
