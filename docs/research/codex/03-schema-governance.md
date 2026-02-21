---
title: CharacterControlBridgeSchema Governance
date: 2026-02-19
status: draft
agent: sub-agent-3
---

# CharacterControlBridgeSchema Governance

## TL;DR
- Keep `character.control.*` append-only with stable numeric IDs; add new slots by appending IDs, never renumbering or reusing deleted IDs.
- Use namespace-partitioned registries (`character.control.*`, `sunderia.*`, `mod.<id>.*`) plus capability negotiation at startup to prevent frontend/runtime mismatch.
- Treat enums as open at runtime: reserve numeric ranges per owner and require unknown-value fallback in UI adapters.
- Prefer layered schema composition (base + game + mod) in one registry build step, not fragile runtime inheritance chains.
- Fail gracefully on missing required capabilities: disable unsupported panels/actions, keep simulation authority and command flow intact.

## Context
Existing contract uses stable slot/action IDs and path resolution through `CharacterControlHookRegistry`. That is the right baseline for ECS-driven, one-way data flow. The governance problem is extension over time (core game + other games + mods) without consumer breakage.

## Approach Comparison

| Approach | Backward compatibility | Extension ergonomics | Modding/discovery fit | Runtime complexity | Key risks |
|---|---|---|---|---|---|
| Flat enum extension with reserved ranges | Good if append-only and ranges are enforced | Simple for small teams | Weak alone (global coordination bottleneck) | Low | ID/range collisions, central bottleneck |
| Schema inheritance (base + game + mod layers) | Medium (depends on merge semantics) | Medium | Medium | Medium | Ambiguous override order, hidden shadowing |
| Namespace-partitioned registries (`character.control.*`, `sunderia.*`, `mod.mymod.*`) | High (clear ownership boundaries) | High | High | Medium | Requires strict naming and registry validation |
| Capability negotiation (frontend declares required slots, registry validates) | Very high for consumer safety | High for frontend teams | High | Medium | If misconfigured, can hide integration bugs behind fallback |

## Recommended Governance Model
Use a **hybrid**:
1. Namespace-partitioned registry as the ownership model.
2. Capability negotiation at startup as the safety model.
3. Append-only numeric IDs with reserved ranges as the wire-compatibility model.
4. Layered composition (base/game/mod) at registry-build time, not object inheritance at runtime.

### Governance Rules
1. IDs are append-only per namespace. Never renumber. Never reuse removed IDs.
2. Paths are immutable once published.
3. Deletions are logical deprecations first; keep registry aliases for at least one schema epoch.
4. Enums use owner ranges and unknown-value fallback handling in all consumers.
5. Frontends must declare required and optional capabilities.
6. Startup validation blocks only the unsupported frontend surface, never simulation systems.

### Suggested ID Ownership
- Shared/core: `character.control.*`
  - Slots: `256-511` (current base starts at `256`)
  - Actions: dedicated shared range (for example `1024-1279`)
  - Enum values: low shared range (for example `0-127`)
- Game-specific: `sunderia.*`
  - Slots/actions/enums in non-overlapping game range
- Mods: `mod.<modid>.*`
  - Slots/actions/enums in per-mod assigned range (manifest-declared, validated at startup)

## 1) Slot Addition Without Breaking Bindings
Additive-only slot evolution for:
- `character.control.mana_current`
- `character.control.stamina_current`
- `character.control.combo_count`

### C# pseudo-code: additive slots
```csharp
public static class CharacterControlBridgeSchema
{
    public const int SlotBase = 256;

    // Existing stable slots (0..9)
    public const int Visible = SlotBase + 0;
    public const int AutomationEnabled = SlotBase + 1;
    public const int ControllerOwner = SlotBase + 2;
    public const int LockTicksRemaining = SlotBase + 3;
    public const int PlayerHealthCurrent = SlotBase + 4;
    public const int PlayerHealthMax = SlotBase + 5;
    public const int EnemyHealthCurrent = SlotBase + 6;
    public const int EnemyHealthMax = SlotBase + 7;
    public const int ActionCode = SlotBase + 8;
    public const int BlockReasonCode = SlotBase + 9;

    // New slots appended only (10..12)
    public const int ManaCurrent = SlotBase + 10;
    public const int StaminaCurrent = SlotBase + 11;
    public const int ComboCount = SlotBase + 12;

    public const string PathManaCurrent = "character.control.mana_current";
    public const string PathStaminaCurrent = "character.control.stamina_current";
    public const string PathComboCount = "character.control.combo_count";
}

public static class CharacterControlHookRegistry
{
    public static bool TryResolveSlotId(string path, out int slotId)
    {
        switch (path)
        {
            // Existing mappings...
            case CharacterControlBridgeSchema.PathManaCurrent:
                slotId = CharacterControlBridgeSchema.ManaCurrent;
                return true;
            case CharacterControlBridgeSchema.PathStaminaCurrent:
                slotId = CharacterControlBridgeSchema.StaminaCurrent;
                return true;
            case CharacterControlBridgeSchema.PathComboCount:
                slotId = CharacterControlBridgeSchema.ComboCount;
                return true;
            default:
                slotId = default;
                return false;
        }
    }
}
```

## 2) Enum Extension Strategy
Prefer numeric range ownership + tolerant readers.

### C# pseudo-code: extensible enums
```csharp
public enum CharacterActionCode : ushort
{
    None = 0,
    Ready = 1,
    Idle = 2,
    Attack = 3,
    TargetDefeated = 4,

    // Shared extension range: 32..95
    CastStart = 32,
    CastRelease = 33,

    // Game extension range: 96..191
    SunderiaParryWindow = 96,

    // Mod extension range begins at 512 (manifest-assigned per mod)
}

public enum CharacterBlockReasonCode : ushort
{
    None = 0,
    Cooldown = 1,
    LowStamina = 2,
    LowMana = 3,
    Invalid = 4,

    // Shared extension range
    Silenced = 32,
    OutOfRange = 33,
}

public static class CharacterEnumReadPolicy
{
    public static CharacterActionCode ToKnownOrFallback(ushort raw)
    {
        var code = (CharacterActionCode)raw;
        return Enum.IsDefined(typeof(CharacterActionCode), code)
            ? code
            : CharacterActionCode.None;
    }

    public static CharacterBlockReasonCode ToKnownOrFallback(ushort raw)
    {
        var code = (CharacterBlockReasonCode)raw;
        return Enum.IsDefined(typeof(CharacterBlockReasonCode), code)
            ? code
            : CharacterBlockReasonCode.Invalid;
    }
}
```

Notes:
- Treat unknown output enum values as expected forward-compatible cases.
- UI adapters should render unknown action/block reason as neutral fallback text/icon, not throw.

## 3) Shared vs Game-Specific Schemas
- `character.control.*` stays minimal, cross-game, and reusable.
- `sunderia.*` carries game mechanics that are not portable.
- Game UIs can request both shared and game namespaces through capability manifests.
- Other games reuse shared schema unchanged, then add their own namespace layer.

## 4) Modding Surface: Discovery + Runtime Binding
Avoid heavy runtime reflection scanning in player builds. Use manifest-driven provider registration and one startup registry build.

### C# pseudo-code: provider model
```csharp
public enum BridgeValueKind
{
    Bool,
    Int,
    Float,
    FixedString
}

public readonly struct HookSlotDescriptor
{
    public readonly string Path;
    public readonly int SlotId;
    public readonly BridgeValueKind ValueKind;

    public HookSlotDescriptor(string path, int slotId, BridgeValueKind valueKind)
    {
        Path = path;
        SlotId = slotId;
        ValueKind = valueKind;
    }
}

public interface ICharacterControlSchemaProvider
{
    string Namespace { get; } // e.g. "mod.mymod"
    int LayerOrder { get; }   // 0 shared, 100 game, 200+ mods
    void Register(ref CharacterControlRegistryBuilder builder);
}

public ref struct CharacterControlRegistryBuilder
{
    public void AddSlot(in HookSlotDescriptor slot);
    public void AddAction(string path, int actionId);
    public void AddEnumValue(string enumPath, int numericCode, string label);
}

public sealed class MyModSchemaProvider : ICharacterControlSchemaProvider
{
    public string Namespace => "mod.mymod";
    public int LayerOrder => 220;

    public void Register(ref CharacterControlRegistryBuilder builder)
    {
        builder.AddSlot(new HookSlotDescriptor(
            path: "mod.mymod.character.control.rage_current",
            slotId: 8300,
            valueKind: BridgeValueKind.Int));

        builder.AddAction(
            path: "mod.mymod.character.control.trigger_rage",
            actionId: 12300);

        builder.AddEnumValue(
            enumPath: "character.control.action_code",
            numericCode: 560,
            label: "MyModRageAttack");
    }
}
```

Runtime binding behavior:
- Mod registers descriptors once during bootstrap.
- Registry validates namespace ownership, path uniqueness, and ID collisions.
- Successful descriptors become part of immutable runtime registry snapshot consumed by DataBridge/UI adapters.

## 5) Contract Validation at Startup
Frontend declares required capabilities; registry validates before first bind.

### C# pseudo-code: capability negotiation
```csharp
public readonly struct FrontendCapability
{
    public readonly string Path;
    public readonly bool Required;

    public FrontendCapability(string path, bool required)
    {
        Path = path;
        Required = required;
    }
}

public sealed class FrontendContract
{
    public string FrontendId;
    public FrontendCapability[] Capabilities;
}

public readonly struct ContractValidationIssue
{
    public readonly string Path;
    public readonly bool Blocking;

    public ContractValidationIssue(string path, bool blocking)
    {
        Path = path;
        Blocking = blocking;
    }
}

public static class CharacterControlContractValidator
{
    public static ContractValidationIssue[] Validate(
        in FrontendContract contract,
        in CharacterControlHookRegistrySnapshot registry)
    {
        // Pseudo-code: iterate declared capabilities and return missing entries.
        throw new NotImplementedException();
    }
}
```

Graceful failure policy:
- Missing required slot/action: mark frontend as `Degraded`, disable dependent widgets/actions, show diagnostics.
- Missing optional slot/action: hide that widget/feature only.
- ECS simulation continues; DataBridge publish/command flow remains authoritative.

## Mermaid: Namespace + Registry Topology
```mermaid
flowchart LR
    A[Shared Provider<br/>character.control.*] --> R[Hook Registry Builder]
    B[Game Provider<br/>sunderia.*] --> R
    C[Mod Provider(s)<br/>mod.<id>.*] --> R

    R --> V[Startup Contract Validator]
    F1[UI Toolkit Frontend<br/>required + optional capabilities] --> V
    F2[UGUI Frontend<br/>required + optional capabilities] --> V
    F3[HTML/JS Frontend<br/>required + optional capabilities] --> V

    V -->|ok| S[Registry Snapshot]
    V -->|missing required| D[Degraded Frontend Mode]

    S --> DB[DataBridge Publish/Bind]
    DB --> UI[View Adapters]
    UI --> CMD[DataBridge Actions]
    CMD --> ECS[ECS Command Inbox/ECB]
```

## External Signals Checked (2026-02-19)
- Unity Entities docs emphasize job scheduling and minimizing main-thread work in systems (`ISystem`, `IJobEntity` guidance): https://docs.unity.cn/Packages/com.unity.entities%401.2/manual/systems-isystem.html
- Unity warns about runtime reflection overhead in player builds; prefer precomputed discovery/registration data: https://docs.unity3d.com/ja/6000.0/Manual/dotnet-reflection-overhead.html
- Protobuf schema evolution guidance supports append-only numeric IDs, reserving removed values, and tolerant handling of unknown enum values: https://protobuf.dev/best-practices/dos-donts/ and https://protobuf.dev/programming-guides/enum/

## Open Questions
1. Should mod ID ranges be centrally assigned per published mod, or deterministically derived from `mod.<id>` with collision fail-fast?
2. Do we want alias support for renamed paths, or enforce strict immutable paths only and require frontend updates?
3. Should unknown enum values map to `None`/`Invalid`, or should UI receive raw numeric codes for custom renderer plug-ins?
4. Where should capability manifests live for each frontend type (authoring asset, generated code, or both)?
5. Do we need telemetry thresholds that escalate degraded frontend mode to hard-fail in CI/nightly builds?
