# Scripting Engine + Full ECS Integration Plan

## Status: Verified

Integration points were checked in repo code:

- Definition discovery from blocks:
  - `repos/scripting-engine-rust/examples/monogame/IdleDungeon/Game/Data/BlockDiscovery.cs`
  - Uses `GetBlocksByType("character"|"skill"|"node"|"ability")`
  - Uses `GetBlockFieldByName` and `GetBlockFieldArrayByName`
- Runtime/project load lifecycle:
  - `repos/scripting-engine-rust/bindings/dotnet/ScriptingEngine.Hosting/ScriptRuntime.cs`
  - `repos/scripting-engine-unity/Runtime/World.cs`
  - `LoadProject(...)`, `GetBlocksByType(...)`, `ResolveBlock(...)`
- Script-authored content examples:
  - `repos/scripting-engine-rust/examples/monogame/IdleDungeon/Scripts/src/characters.se`
  - `repos/scripting-engine-rust/examples/monogame/IdleDungeon/Scripts/src/abilities/*.se`
  - `repos/scripting-engine-rust/examples/monogame/IdleDungeon/Scripts/src/skills/*.se`
  - `repos/scripting-engine-rust/examples/monogame/IdleDungeon/Scripts/src/nodes/*.se`

---

## 1) Non-Negotiable Boundary

Scripts define content; ECS owns runtime state.

### Script-owned (definition-time)
- `block<character>`
- `block<skill>`
- `block<node>`
- `block<ability>`
- optional exported math/scoring functions

### ECS-owned (runtime authoritative)
- Character vitals/state
- Skill levels/xp/tracks
- Known tiers/abilities
- Active executions
- Modifiers/cooldowns
- AI intent/arbitration state

---

## 2) Compile/Load Pipeline (Do This Once Per Content Load)

1. Load project with scripting runtime.
2. Discover all required block types.
3. Validate required fields and references.
4. Normalize into stable numeric IDs (`character_id`, `skill_id`, `node_id`, `ability_id`, `tag_id`).
5. Build `DefinitionCatalog` ECS singleton from normalized data.
6. Release raw string-heavy lookup usage from hot loops.

Rule:
- Runtime combat/AI systems must use IDs only, never parse node strings per action tick.

---

## 3) Required Block Contracts for First Slice

## `block<character>` minimal fields
- `display_name`
- `base_health`
- `base_stamina`
- `base_damage`
- `base_armor`
- `base_speed`
- `attack_range`
- `shape`
- `skills[]`
- `starting_abilities[]`
- `known_tiers[]`

Optional:
- `base_mana`

## `block<ability>` minimal fields
- `display_name`
- `description`
- `character_type`
- `mana_cost`
- `stamina_cost`
- `cast_time`
- `range`
- `aoe_radius`
- `base_damage`
- `damage_type`
- `tags[]`
- `node_sequence[]`
- `required_skills[]`
- `reliability_success`
- `reliability_partial`
- `reliability_fail`
- `reliability_critical`
- `risk_backfire`
- `risk_friendly_fire`

## `block<skill>` minimal fields
- `display_name`
- `category`
- `threshold_levels[]`
- `threshold_bonuses[]`
- `threshold_types[]`

## `block<node>` minimal fields
- `name`
- `category`
- `complexity_t0/t1/t2`
- `cost_mult_t0/t1/t2`
- `output_type`
- `tags[]`

---

## 4) Smallest "Get Something On Screen" Slice

Goal:
- Define a scripted character + scripted ability and see autonomous + manual control in ECS with visible HUD state.

Scope:
1. One scripted character (e.g., `Warrior`).
2. One scripted ability (e.g., `Slash`).
3. One dummy enemy entity.
4. Automation ON/OFF UI.
5. Manual action button (same `Slash` ability).
6. Arbitration lock indicator (`AI` vs `PLAYER`) on screen.

Flow:
1. Load script project -> build `DefinitionCatalog`.
2. Spawn character from `block<character>`.
3. Spawn `AbilityOwned` from `starting_abilities[]`.
4. AI emits auto `ActionRequest`.
5. UI emits manual `PlayerIntent`.
6. `IntentArbitrationSystem` selects winner.
7. Shared execution pipeline resolves action and updates HUD snapshot.

Success criteria:
1. Character and enemy are visible.
2. With automation ON, repeated auto attacks occur.
3. Clicking manual action overrides temporarily.
4. After lock expiry, automation resumes.
5. Both paths run through identical ECS execution.

---

## 5) Validation Rules (Before Expanding)

1. Every `starting_abilities[]` entry resolves to a discovered `block<ability>`.
2. Every `required_skills[]` entry resolves to discovered `block<skill>`.
3. Every node token in `node_sequence[]` resolves to discovered `block<node>` + valid tier.
4. Reliability values are bounded and normalized policy is applied.
5. Missing required content fails loudly during load (not at runtime action execution).

---

## 6) Expansion After First Slice

1. Add second character archetype and second ability category.
2. Add `AutomationProfile` (Safe/Balanced/Aggro) with script-driven tags.
3. Add progression writes (`SkillState` xp/reps/technique/understanding).
4. Add basic modifier instance application from script-defined effect tags.

Keep the same boundary: script definitions feed ECS runtime, never replace it.
