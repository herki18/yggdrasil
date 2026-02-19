# Full ECS Rules (Non-Negotiable)

## Scope
These rules apply to character, skill, AI, and semi-idle control foundation work.

If a design violates these, do not implement it.

---

## 1) Core Rules

1. All authoritative gameplay state must live in ECS components/buffers.
2. Runtime hot paths must use unmanaged ECS data only (`IComponentData`, `IBufferElementData`).
3. No managed collections (`Dictionary`, `List`, `HashSet`) in gameplay simulation paths.
4. No string parsing in per-frame/per-action hot loops.
5. Script definitions are compile-time/runtime-load input only; execution reads normalized IDs.
6. One action pipeline for AI and player commands (no parallel manual code path).

### Scripting Engine integration mandate
7. Use scripting engine block discovery at load time (`GetBlocksByType`, block field reads) to build ECS definition catalogs.
8. Missing required script content is a load-time hard error (fail loudly), never a silent runtime fallback.

---

## 2) Data Ownership

### ECS-Owned (authoritative)
- Character state (vitals, cooldowns, skills, known tiers, known abilities)
- Ability-owned runtime state (charges/cooldowns/owner binding)
- Modifier instances
- Active execution state
- AI intent and arbitration state

### Definition/Read-Only Runtime Catalog
- Compiled definition tables keyed by stable IDs
- Node/skill/ability/character static data

### UI
- UI never owns simulation truth.
- UI reads ECS snapshots (or bridge copies) and emits input intents only.

---

## 3) Minimal Component Set for First Semi-Idle Slice

### Character
- `Vitals`
- `AttackCooldown`
- `AutomationEnabled`
- `ControlLockState`
- `KnownAbilityRef` (buffer)

### Intents and Selection
- `PlayerIntent` (buffer)
- `AiIntent` (buffer or single component)
- `SelectedAction`
- `ActionBlockReason` (for debug/UX feedback)

### Execution
- `ActionExecutionState`
- `ExecutionOutcome`

### Optional for UX visibility
- `ControlUiState` (small snapshot component)

---

## 4) Minimal System Order (First Slice)

1. `PlayerIntentInputSystem`
   - Write `PlayerIntent` from input/UI events.

2. `AutomationIntentSystem`
   - Produce simple AI intent when automation is enabled.

3. `IntentArbitrationSystem`
   - Apply lock/priority rules.
   - Write `SelectedAction` and `ActionBlockReason`.

4. `ActionDispatchSystem`
   - Convert `SelectedAction` into execution state.

5. `ActionExecutionSystem`
   - Resolve action through the shared pipeline.

6. `CooldownTickSystem`
   - Advance cooldown/lock timers.

7. `ControlUiSnapshotSystem`
   - Publish compact state for HUD.

---

## 5) Performance/Burst Rules

1. Use integer IDs (`skill_id`, `node_id`, `ability_id`, `tag_id`) in runtime.
2. Use fixed-size or dynamic buffers instead of managed nested structures.
3. Keep per-entity loops branch-light and cache-friendly.
4. Avoid structural changes in inner loops; batch through ECB where needed.
5. Keep system responsibilities narrow and explicit.

---

## 6) Validation Gates Before Merge

1. AI and player both pass through same `SelectedAction -> Execution` path.
2. Manual override works without bypassing gates/costs/cooldowns.
3. No managed type usage in simulation systems.
4. No runtime node-string parsing in execution systems.
5. HUD state matches ECS authoritative control state.

---

## 7) Foundation-First Rationale

Following this keeps the architecture portable to future games:
- swap content/defs, keep systems;
- add new actions/goals without changing control seam;
- keep deterministic, inspectable simulation behavior.
