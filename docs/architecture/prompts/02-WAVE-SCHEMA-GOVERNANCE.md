# Wave 2: Registry Builder and Capability Negotiation

> **Estimated scope**: ~600-800 lines of new code
> **Assembly**: New `Sunderia.DataBridge.Schema` asmdef (NO `allowUnsafeCode`)
> **Depends on**: Nothing (parallel with Wave 1)
> **Reference docs**: `DECISION.md` §4 Phase 2, `03-schema-governance.md` §4-5

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

1. `DECISION.md` — §4 Phase 2, §5 Assembly boundaries, §9 Schema Appendix (SINGLE SOURCE OF TRUTH for all slot/action IDs)
2. `03-schema-governance.md` — §4 (Approach C detailed design), §5 (enum governance), §6 (capability negotiation)
3. **Existing code** — Read `CharacterControlBridgeSchema.cs`, `CharacterControlHookRegistry.cs`, `PipelineSlots` (in `PipelineStateWriteSystem.cs`), `SlotCompiler.cs`, `ActionCompiler.cs`

---

## Context: What Exists Today

- `CharacterControlBridgeSchema` — static class with `const int` slot IDs (256-265) and action IDs (12000-12002), plus path strings
- `CharacterControlHookRegistry` — hand-written switch mapping path strings → int IDs
- `PipelineSlots` — static class with `const int` slots 0-7
- `SlotCompiler` / `ActionCompiler` — dynamic sequential allocation (NOT used by character control schema, potential collision risk)

The existing const-based approach STAYS for compile-time usage. The registry wraps it for runtime discovery, validation, and capability negotiation.

---

## Tasks

### Task 1: Create the `Sunderia.DataBridge.Schema` asmdef

Create a new assembly definition:
- Name: `Sunderia.DataBridge.Schema`
- **No** `allowUnsafeCode`
- References: None (standalone — this is intentional so mods can reference it without pulling in unsafe buffer types)
- Location: `Assets/Scripts/DataBridgeSchema/`

### Task 2: Define `PropertyType` enum

```csharp
/// <summary>
/// Type discriminator for DataBridge slot values.
/// Matches the PropertyValue union's actual storage types.
/// </summary>
public enum PropertyType : byte
{
    Bool = 0,
    Int = 1,
    Float = 2,
    String = 3,
    Entity = 4
}
```

### Task 3: Define `IBridgeSchemaProvider` interface

```csharp
/// <summary>
/// Implement this to register slots and actions into the bridge schema.
/// Called once at startup. Providers are ordered by LayerOrder (lower = earlier).
/// </summary>
public interface IBridgeSchemaProvider
{
    /// <summary>Root namespace this provider owns (e.g., "character.control", "sunderia", "mod.mymod").</summary>
    string Namespace { get; }

    /// <summary>Registration order. Lower = registered first. Shared=0, Game=100, Mod=200+.</summary>
    int LayerOrder { get; }

    /// <summary>Register all slots and actions into the builder.</summary>
    void Register(ref BridgeRegistryBuilder builder);
}
```

### Task 4: Implement `BridgeRegistryBuilder`

This is a `ref struct` (stack-allocated frame). Internal collections use standard heap allocation — this is fine since registration happens once at startup.

```
BridgeRegistryBuilder (ref struct):

Internal state:
- List<SlotRegistration> _slots
- List<ActionRegistration> _actions
- List<EnumRegistration> _enums
- List<string> _errors
- HashSet<int> _usedSlotIds
- HashSet<int> _usedActionIds
- HashSet<string> _usedSlotPaths
- HashSet<string> _usedActionPaths

Methods:
- AddSlot(int id, string path, PropertyType type, string ownerNamespace)
    → Validates: ID not already used, path not already used, path starts with ownerNamespace
    → On conflict: adds to _errors list, does NOT throw
    
- AddAction(int id, string path, string ownerNamespace)
    → Same validation pattern
    
- AddEnumValue(string enumName, int value, string label)
    → Registers human-readable label for enum values (e.g., ActionCode.BasicAttack = "Basic Attack")
    
- Build(out string[] errors) → BridgeRegistrySnapshot?
    → If _errors.Count > 0: returns null, populates errors
    → If clean: creates immutable snapshot, returns it

Validation rules:
- Slot ID uniqueness (across ALL providers)
- Action ID uniqueness (across ALL providers)
- Path uniqueness (no two slots can have same path)
- Namespace prefix enforcement (path must start with provider's namespace + ".")
    Exception: PipelineSlots use paths starting with "pipeline." — the provider's namespace must match
- ID range validation: warn (not error) if ID falls outside the expected range for its namespace
    (see DECISION.md §9 Namespace Range Allocation table)
```

**IMPORTANT**: `ref struct` means it cannot be boxed, cannot be a field in a class, and cannot be captured by lambdas. This is intentional — it enforces that registration is a synchronous stack-scoped operation.

### Task 5: Implement `BridgeRegistrySnapshot`

Immutable after construction. This is the runtime lookup surface.

```
BridgeRegistrySnapshot (sealed class, immutable):

Internal state:
- Dictionary<string, int> _slotPathToId
- Dictionary<string, int> _actionPathToId
- Dictionary<int, SlotInfo> _slots (id → info)
- Dictionary<int, ActionInfo> _actions (id → info)
- Dictionary<(string enumName, int value), string> _enumLabels

Public API:
- bool TryGetSlotId(string path, out int id)
- bool TryGetActionId(string path, out int id)
- SlotInfo GetSlotInfo(int id)     // throws if not found
- ActionInfo GetActionInfo(int id)  // throws if not found
- IReadOnlyList<string> AllSlotPaths { get; }
- IReadOnlyList<string> AllActionPaths { get; }
- string GetEnumLabel(string enumName, int value, string fallback = "Unknown")
- bool HasSlot(string path)
- bool HasAction(string path)

Supporting types:
- readonly struct SlotInfo { int Id; string Path; PropertyType Type; string OwnerNamespace; }
- readonly struct ActionInfo { int Id; string Path; string OwnerNamespace; }
```

### Task 6: Implement Capability Negotiation

```
FrontendContract (class):
- List<CapabilityRequirement> Requirements

CapabilityRequirement (readonly struct):
- string Path           // slot or action path
- CapabilityKind Kind   // Slot or Action
- bool Required         // true = must exist, false = optional

CapabilityKind (enum): Slot, Action

ContractValidator (static class):
- ContractValidationResult Validate(FrontendContract contract, BridgeRegistrySnapshot registry)

ContractValidationResult:
- bool AllRequiredSatisfied
- IReadOnlyList<CapabilityResult> Results

CapabilityResult:
- string Path
- CapabilityKind Kind
- bool Satisfied
- bool Required
```

The validator iterates requirements, checks `registry.HasSlot()` or `registry.HasAction()`, and builds results. Simple and deterministic.

### Task 7: Create `CharacterControlSchemaProvider`

**File**: In `Sunderia.Map` (or wherever `CharacterControlBridgeSchema` lives — this assembly must reference `Sunderia.DataBridge.Schema`)

Wraps the existing `CharacterControlBridgeSchema` const values:

```csharp
public class CharacterControlSchemaProvider : IBridgeSchemaProvider
{
    public string Namespace => "character.control";
    public int LayerOrder => 0; // shared framework = lowest

    public void Register(ref BridgeRegistryBuilder builder)
    {
        // Slots — from DECISION.md §9 Slot Table
        builder.AddSlot(CharacterControlBridgeSchema.Visible,
            CharacterControlBridgeSchema.PathVisible, PropertyType.Bool, Namespace);
        builder.AddSlot(CharacterControlBridgeSchema.AutomationEnabled,
            CharacterControlBridgeSchema.PathAutomationEnabled, PropertyType.Bool, Namespace);
        // ... all existing slots (256-265)

        // Actions — from DECISION.md §9 Action Table
        builder.AddAction(CharacterControlBridgeSchema.ActionToggleAutomation,
            "character.control.toggle_automation", Namespace);
        builder.AddAction(CharacterControlBridgeSchema.ActionManualAttack,
            "character.control.manual_attack", Namespace);
        builder.AddAction(CharacterControlBridgeSchema.ActionPauseGame,
            "character.control.pause_game", Namespace);

        // Enum labels
        builder.AddEnumValue("CharacterActionCode", 0, "None");
        builder.AddEnumValue("CharacterActionCode", 1, "BasicAttack");
        // ... all existing enum values

        builder.AddEnumValue("CharacterBlockReasonCode", 0, "None");
        builder.AddEnumValue("CharacterBlockReasonCode", 1, "OnCooldown");
        // ... all existing enum values
    }
}
```

### Task 8: Create `PipelineSchemaProvider`

Same pattern, wrapping `PipelineSlots`:

```csharp
public class PipelineSchemaProvider : IBridgeSchemaProvider
{
    public string Namespace => "pipeline";
    public int LayerOrder => 0;

    public void Register(ref BridgeRegistryBuilder builder)
    {
        builder.AddSlot(PipelineSlots.PipelineState, "pipeline.state", PropertyType.Int, Namespace);
        // ... all pipeline slots 0-7
    }
}
```

### Task 9: Wire into Startup

Create a bootstrap method/system that:

1. Discovers all `IBridgeSchemaProvider` implementations (via reflection or explicit registration — explicit is preferred for Burst/AOT safety)
2. Sorts by `LayerOrder`
3. Creates `BridgeRegistryBuilder`
4. Calls `Register()` on each provider in order
5. Calls `Build(out errors)` — logs errors if any, stores snapshot as a static singleton or managed IComponentData
6. This runs AFTER `DataBridgeLifecycleSystem.OnCreate` (buffers must exist) but BEFORE any consumer binds

**Placement**: This should run in a startup system or be triggered from `DataBridgeLifecycleSystem.OnCreate` after buffer allocation.

### Task 10: Wire `CharacterControlHookRegistry` to snapshot

Modify `CharacterControlHookRegistry` to delegate to the snapshot for dynamic lookups while keeping its switch statement as a fast path:

```csharp
// Existing fast path stays for known paths
// Add fallback to registry for unknown paths (mod slots, future additions)
public static bool TryGetSlotId(string path, out int id)
{
    // Try existing switch first (zero-allocation, compile-time)
    if (TryGetSlotIdFast(path, out id)) return true;

    // Fall back to registry snapshot
    var registry = BridgeSchemaRegistry.Snapshot; // however you expose it
    return registry != null && registry.TryGetSlotId(path, out id);
}
```

---

## What NOT to Do

- Do NOT remove or modify existing `CharacterControlBridgeSchema` const values. They stay as compile-time constants.
- Do NOT remove `SlotCompiler` or `ActionCompiler` yet. They're used by other systems. That's future cleanup.
- Do NOT add unsafe code to this assembly. The whole point of the separate asmdef is to keep it safe for mod references.
- Do NOT use `Enum.IsDefined` anywhere. It uses reflection, allocates, and is Burst-incompatible. Use switch-based fallback.
- Do NOT make the builder a class. It MUST be a `ref struct`.

---

## Verification Checklist

- [ ] **New asmdef exists**: `Sunderia.DataBridge.Schema.asmdef` with no `allowUnsafeCode`
- [ ] **Compiles**: Both `Sunderia.DataBridge.Schema` and assemblies referencing it compile
- [ ] **Duplicate path detection**: `builder.AddSlot(256, "character.control.visible", ...); builder.AddSlot(257, "character.control.visible", ...)` → `Build()` returns null with error
- [ ] **Duplicate ID detection**: `builder.AddSlot(256, "path.a", ...); builder.AddSlot(256, "path.b", ...)` → `Build()` returns null with error
- [ ] **Namespace enforcement**: `builder.AddSlot(256, "wrong.namespace.slot", ..., ownerNamespace: "character.control")` → error
- [ ] **TryGetSlotId resolves all existing slots**: Every `CharacterControlBridgeSchema` path resolves to the correct integer ID
- [ ] **TryGetActionId resolves all actions**: All 3 action paths resolve correctly
- [ ] **ContractValidator satisfied**: A contract requiring all existing slots → `AllRequiredSatisfied = true`
- [ ] **ContractValidator unsatisfied**: A contract requiring `"character.control.nonexistent"` → `AllRequiredSatisfied = false`
- [ ] **ContractValidator optional**: A contract with optional missing capability → `AllRequiredSatisfied = true`, specific result shows `Satisfied = false, Required = false`
- [ ] **Provider ordering**: If two providers register, lower `LayerOrder` goes first
- [ ] **Enum labels**: `GetEnumLabel("CharacterActionCode", 1)` returns `"BasicAttack"`

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| CREATE | `Sunderia.DataBridge.Schema.asmdef` | — |
| CREATE | `PropertyType.cs` | Sunderia.DataBridge.Schema |
| CREATE | `IBridgeSchemaProvider.cs` | Sunderia.DataBridge.Schema |
| CREATE | `BridgeRegistryBuilder.cs` | Sunderia.DataBridge.Schema |
| CREATE | `BridgeRegistrySnapshot.cs` | Sunderia.DataBridge.Schema |
| CREATE | `SlotInfo.cs` | Sunderia.DataBridge.Schema |
| CREATE | `ActionInfo.cs` | Sunderia.DataBridge.Schema |
| CREATE | `FrontendContract.cs` | Sunderia.DataBridge.Schema |
| CREATE | `CapabilityRequirement.cs` | Sunderia.DataBridge.Schema |
| CREATE | `ContractValidator.cs` | Sunderia.DataBridge.Schema |
| CREATE | `BridgeSchemaRegistry.cs` (static accessor) | Sunderia.DataBridge.Schema |
| CREATE | `CharacterControlSchemaProvider.cs` | Sunderia.Map |
| CREATE | `PipelineSchemaProvider.cs` | Sunderia.Map |
| MODIFY | `CharacterControlHookRegistry.cs` | Sunderia.Map |
| MODIFY | `Sunderia.Map.asmdef` (add Schema reference) | — |
