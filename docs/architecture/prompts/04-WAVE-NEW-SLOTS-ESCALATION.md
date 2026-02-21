# Wave 4: New Bridge Slots, Escalation System, and Burst-Compiled Publish

> **Estimated scope**: ~500-700 lines of new/modified code
> **Assemblies**: `Sunderia.Map` (ECS systems), `Sunderia.DataBridge` (companion singleton)
> **Depends on**: Wave 1 (dirty bitfield) + Wave 2 (schema registration)
> **Reference docs**: `DECISION.md` §4 Phase 4, §9 Schema Appendix, `02-interaction-model.md` §5-6, `01-databridge-patterns.md` §6.3

---

## CORE TENETS (NON-NEGOTIABLE)

### Clean Break
- No backwards compatibility with old/broken implementations
- If something was done wrong before, DELETE it and redo it correctly
- Don't add workarounds for legacy behavior

### Future-Proofed Design
- Design for the architecture we want, not the one we have
- Think about how this will scale to full browser parity
- Don't paint ourselves into corners with short-term decisions

### Unlimited Time
- Do it right the first time
- No "fix later" TODOs for core functionality
- Quality over speed — we're building infrastructure

### Overwrite, Don't Preserve
- Delete legacy code, don't work around it
- Rewrite modules that are fundamentally broken
- Don't accumulate workarounds

### Unity ECS Rules
- Do NOT use EntityManager when you can avoid it
- Use Unity ECS Jobs (IJobEntity, IJobChunk) for processing
- Use SystemAPI over EntityManager
- Use ISystem with [BurstCompile] for new systems, not SystemBase
- All hot-path code must be Burst-compatible and zero-GC

---

## Pre-Read (MANDATORY)

1. `DECISION.md` — §4 Phase 4, §5 Burst compatibility, §8 Open Question #2 (managed singleton access from Burst), §9 Schema Appendix (exact slot IDs and types)
2. `02-interaction-model.md` — §5 (escalation detection), §6 (UX feedback slots)
3. `01-databridge-patterns.md` — §6.3 (Burst publish system pseudo-code)
4. **Existing code** — Read `CharacterDataBridgeWriteSystem.cs`, `CharacterControlBridgeSchema.cs`, `DataBridgeLifecycleSystem.cs`, `DataBridgeSingleton.cs`

---

## Tasks

### Task 1: Add new slot constants to `CharacterControlBridgeSchema`

From DECISION.md §9 Slot Table, add these constants (append-only, starting at SlotBase + 10):

```csharp
// Phase 4 additions — append only, never reorder existing
public const int CooldownTicksRemaining  = SlotBase + 10; // 266, Int
public const int CooldownTicksTotal      = SlotBase + 11; // 267, Int
public const int StaminaCurrent          = SlotBase + 12; // 268, Int
public const int StaminaMax              = SlotBase + 13; // 269, Int
public const int ManaCurrent             = SlotBase + 14; // 270, Int
public const int ManaMax                 = SlotBase + 15; // 271, Int
public const int CanManualAttack         = SlotBase + 16; // 272, Bool (computed)
public const int EscalationFlags         = SlotBase + 17; // 273, Int (bitfield)
public const int EscalationSeverity      = SlotBase + 18; // 274, Int (0-3)

// Update SlotCount
public const int SlotCount = 19; // was 10

// Path constants for new slots
public const string PathCooldownTicksRemaining = "character.control.cooldown_ticks_remaining";
public const string PathCooldownTicksTotal     = "character.control.cooldown_ticks_total";
public const string PathStaminaCurrent         = "character.control.stamina_current";
public const string PathStaminaMax             = "character.control.stamina_max";
public const string PathManaCurrent            = "character.control.mana_current";
public const string PathManaMax                = "character.control.mana_max";
public const string PathCanManualAttack        = "character.control.can_manual_attack";
public const string PathEscalationFlags        = "character.control.escalation_flags";
public const string PathEscalationSeverity     = "character.control.escalation_severity";
```

### Task 2: Register new slots in `CharacterControlSchemaProvider`

Update the provider from Wave 2 to register all 9 new slots:

```csharp
builder.AddSlot(CharacterControlBridgeSchema.CooldownTicksRemaining,
    CharacterControlBridgeSchema.PathCooldownTicksRemaining, PropertyType.Int, Namespace);
// ... all 9 new slots
```

### Task 3: Define escalation types

```csharp
/// <summary>Bitfield flags for escalation conditions.</summary>
[System.Flags]
public enum EscalationFlags : int
{
    None           = 0,
    Idle           = 1 << 0,  // Character idle too long
    LowHealth      = 1 << 1,  // HP below threshold
    CriticalHealth = 1 << 2,  // HP <= 10%
    LongCombat     = 1 << 3,  // Combat duration exceeded threshold
    BossDetected   = 1 << 4,  // Boss-type enemy engaged
    ResourceDepleted = 1 << 5 // Stamina or mana at zero
}

/// <summary>Escalation severity tiers.</summary>
public enum EscalationSeverity : int
{
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}
```

### Task 4: Create `CharacterEscalationDetectionSystem`

**New ISystem** with `[BurstCompile]`. Runs AFTER `CharacterActionExecutionSystem`, BEFORE the write group.

```
System ordering:
  CharacterActionExecutionSystem
    → CharacterEscalationDetectionSystem (NEW)
      → MapDataBridgeWriteGroup
```

This system:
1. Reads character health, combat state, stamina, mana components
2. Computes `EscalationFlags` bitfield based on thresholds
3. Computes `EscalationSeverity` from flags (highest active flag determines severity)
4. Writes results to an ECS component (`CharacterEscalationState`) that the write system reads

```csharp
public struct CharacterEscalationState : IComponentData
{
    public EscalationFlags Flags;
    public EscalationSeverity Severity;
}
```

Threshold logic:
- `CriticalHealth`: HP ≤ 10% of max → severity = Critical
- `LowHealth`: HP ≤ 25% of max → severity = High
- `ResourceDepleted`: stamina == 0 OR mana == 0 → severity = Medium
- `LongCombat`: combat ticks > threshold → severity = Medium
- `Idle`: no action for N ticks → severity = Low

Severity = max severity of all active flags.

**Use IJobEntity** for the detection logic where possible. The system should process all character entities with the relevant components.

### Task 5: Compute `CanManualAttack` in the write system

`CanManualAttack` is a computed boolean: true only when ALL conditions are met:
- Automation is disabled (or soft override allows manual)
- Cooldown is zero
- Character is alive (health > 0)
- No blocking condition active

This computation happens in the write system (or a dedicated system right before it) and writes the result to the DataBridge slot.

### Task 6: Extend `CharacterDataBridgeWriteSystem` with new slot writes

Add writes for all 9 new slots. The write system reads the relevant ECS components and writes to the DataBridge:

```csharp
// Existing writes (256-265) stay unchanged
// Add new writes:
writeBuffer->Write(CharacterControlBridgeSchema.CooldownTicksRemaining,
    PropertyValue.FromInt(cooldownState.TicksRemaining));
writeBuffer->Write(CharacterControlBridgeSchema.CooldownTicksTotal,
    PropertyValue.FromInt(cooldownState.TicksTotal));
// ... stamina, mana from CharacterVitals or equivalent
writeBuffer->Write(CharacterControlBridgeSchema.CanManualAttack,
    PropertyValue.FromBool(canManualAttack));
writeBuffer->Write(CharacterControlBridgeSchema.EscalationFlags,
    PropertyValue.FromInt((int)escalationState.Flags));
writeBuffer->Write(CharacterControlBridgeSchema.EscalationSeverity,
    PropertyValue.FromInt((int)escalationState.Severity));
```

### Task 7: Create unmanaged `DataBridgePointers` companion singleton

**This is P0 Open Question #2 from DECISION.md §8.**

`DataBridgeSingleton` is a managed `IComponentData` class — Burst cannot access it. Create an unmanaged companion:

```csharp
/// <summary>
/// Unmanaged companion to DataBridgeSingleton, caching raw buffer pointers
/// for [BurstCompile] ISystem access. Set during DataBridgeLifecycleSystem.OnCreate.
/// </summary>
public struct DataBridgePointers : IComponentData
{
    // Pointer to the DoubleBufferedUI struct (or directly to write buffer)
    // The exact shape depends on how DoubleBufferedUI is structured
    public unsafe UIPropertyBuffer* WriteBuffer;
    public unsafe UIPropertyBuffer* ReadBuffer;
}
```

Set this in `DataBridgeLifecycleSystem.OnCreate` after allocating the double buffer. Update pointers after each flip if the flip swaps pointer values.

### Task 8: Convert publish systems to `[BurstCompile] ISystem`

Convert `CharacterDataBridgeWriteSystem` from `SystemBase` to `ISystem` with `[BurstCompile]`:

```csharp
[BurstCompile]
[UpdateInGroup(typeof(MapDataBridgeWriteGroup))]
public partial struct CharacterDataBridgeWriteSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Get unmanaged pointers
        var pointers = SystemAPI.GetSingleton<DataBridgePointers>();
        var writeBuffer = pointers.WriteBuffer;

        // Read ECS components via SystemAPI
        // Write to buffer via pointer
    }
}
```

**Important**: All component reads must use `SystemAPI.GetSingleton<T>()` or queries — no `EntityManager` calls.

### Task 9: Add tick-stamped command struct

```csharp
/// <summary>
/// Tick-stamped command for deterministic ordering. Created by the ECS ingress
/// system when draining the DataBridge command queue.
/// </summary>
public struct CharacterControlCommand : IBufferElementData
{
    public uint Tick;          // Simulation tick when command was ingested
    public uint Sequence;      // Monotonic counter for same-tick ordering
    public int ActionId;       // From CharacterControlBridgeSchema action constants
    public int Payload;        // Action-specific payload (e.g., target entity index)
    public byte Source;        // 0=UI, 1=Script, 2=Network (future)
}
```

Modify `CharacterDataBridgeCommandIngressSystem` to stamp commands with the current tick and an incrementing sequence number when draining from the `NativeQueue`.

### Task 10: Wire heartbeat trigger

In the publish system (or a dedicated heartbeat system), check `HeartbeatConfig.SnapshotEveryNTicks`:

```csharp
var heartbeat = SystemAPI.GetSingleton<HeartbeatConfig>();
if (heartbeat.SnapshotEveryNTicks > 0)
{
    var tick = SystemAPI.GetSingleton<CharacterTickState>(); // or however you track ticks
    if (tick.CurrentTick % heartbeat.SnapshotEveryNTicks == 0)
    {
        writeBuffer->MarkAllSlotsDirty();
    }
}
```

---

## What NOT to Do

- Do NOT change slot IDs for existing slots (256-265). Append only.
- Do NOT use `EntityManager` in the Burst-compiled publish system. Use `SystemAPI`.
- Do NOT put managed references in `DataBridgePointers`. It must be fully unmanaged.
- Do NOT create the escalation UI. That's Wave 6.
- Do NOT modify `ConsumerBridge`. That was Wave 3.

---

## Verification Checklist

- [ ] **All 9 new slots registered**: `CharacterControlSchemaProvider` registers all new paths and IDs
- [ ] **Schema validation passes**: `BridgeRegistryBuilder.Build()` succeeds with no errors after adding new slots
- [ ] **Escalation flags compute**: `CharacterEscalationDetectionSystem` sets `CriticalHealth` when HP ≤ 10%
- [ ] **Escalation severity correct**: Severity = max of all active flags' individual severities
- [ ] **CanManualAttack computed**: Slot is true only when all conditions met; false otherwise
- [ ] **Tick-stamped commands**: Commands ingested from queue have correct tick and incrementing sequence
- [ ] **Deterministic ordering**: Two commands in same tick sort by `(Tick, Sequence)`
- [ ] **Burst compiles**: `CharacterDataBridgeWriteSystem` as `[BurstCompile] ISystem` produces no Burst errors
- [ ] **DataBridgePointers set**: Companion singleton has valid pointers after lifecycle system runs
- [ ] **Heartbeat triggers**: With `SnapshotEveryNTicks = 60`, `MarkAllSlotsDirty()` fires every 60 ticks
- [ ] **New slots appear in DataBridge**: ReadBuffer contains correct values for all 9 new slots
- [ ] **Existing slots unaffected**: Slots 256-265 continue to have correct values

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| MODIFY | `CharacterControlBridgeSchema.cs` | Sunderia.Map |
| MODIFY | `CharacterControlSchemaProvider.cs` | Sunderia.Map |
| CREATE | `EscalationFlags.cs` | Sunderia.Map |
| CREATE | `EscalationSeverity.cs` | Sunderia.Map |
| CREATE | `CharacterEscalationState.cs` | Sunderia.Map |
| CREATE | `CharacterEscalationDetectionSystem.cs` | Sunderia.Map |
| CREATE | `DataBridgePointers.cs` | Sunderia.DataBridge |
| CREATE | `CharacterControlCommand.cs` | Sunderia.Map |
| MODIFY | `CharacterDataBridgeWriteSystem.cs` (convert to ISystem + new slots) | Sunderia.Map |
| MODIFY | `DataBridgeLifecycleSystem.cs` (set DataBridgePointers) | Sunderia.Map |
| MODIFY | `CharacterDataBridgeCommandIngressSystem.cs` (tick stamping) | Sunderia.Map |
| MODIFY | `CharacterControlHookRegistry.cs` (add new path lookups) | Sunderia.Map |
