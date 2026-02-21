# Wave 5: Adapter Lifecycle and Hot-Swap

> **Estimated scope**: ~800-1000 lines of new code
> **Assembly**: `Assembly-CSharp` (future extraction to `Sunderia.UI.Abstractions`)
> **Depends on**: Wave 2 (capability validation) + Wave 3 (bitfield-based ConsumerBridge)
> **Reference docs**: `DECISION.md` §4 Phase 5, `04-frontend-adapters.md` §3-4

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

1. `DECISION.md` — §4 Phase 5, §5 Assembly boundaries
2. `04-frontend-adapters.md` — §3 (adapter interface design — READ ALL OF §3, this is the primary spec), §4 (adapter host), §5 (debug decorator), §6 (HTML/JS adapter considerations)
3. **Existing code** — Read `CharacterControlDataBridgePort.cs`, `CharacterControlStrip.cs`, `UIManager.cs`, `DataBridgeConnector.cs`

---

## Context: Replacing the Old Pattern

The current system uses:
- `CharacterControlDataBridgePort` — pulls all slots every frame via `TryGetState()`
- `CharacterControlStrip` — MonoBehaviour that uses the port to drive UI Toolkit

This is being replaced by:
- `ICharacterControlAdapter` — push-based, receives only changed state
- `CharacterControlAdapterHost` — manages adapter lifecycle, drives updates
- `CharacterControlUiToolkitAdapter` — first concrete adapter (replaces strip's bridge logic)

**The old port is DELETED once the new adapter is working.** Clean break.

---

## Tasks

### Task 1: Implement `CharacterControlSnapshot`

A readonly struct holding ALL current slot values. Built by the host from the read buffer.

```csharp
/// <summary>
/// Complete character control state at a point in time.
/// Built by AdapterHost from DataBridge read buffer.
/// </summary>
public readonly struct CharacterControlSnapshot
{
    public readonly bool Visible;
    public readonly bool AutomationEnabled;
    public readonly int ControllerOwner;
    public readonly int LockTicksRemaining;
    public readonly int PlayerHealthCurrent;
    public readonly int PlayerHealthMax;
    public readonly int EnemyHealthCurrent;
    public readonly int EnemyHealthMax;
    public readonly int ActionCode;
    public readonly int BlockReasonCode;
    // Phase 4 additions
    public readonly int CooldownTicksRemaining;
    public readonly int CooldownTicksTotal;
    public readonly int StaminaCurrent;
    public readonly int StaminaMax;
    public readonly int ManaCurrent;
    public readonly int ManaMax;
    public readonly bool CanManualAttack;
    public readonly int EscalationFlags;
    public readonly int EscalationSeverity;

    // Constructor that reads all slots from buffer given bindings
    // (implementation detail — the host builds this)
}
```

### Task 2: Implement `CharacterControlDelta`

A bitmask indicating WHICH slots changed this frame.

```csharp
/// <summary>
/// Bitmask indicating which character control slots changed.
/// Uses a ulong internally (supports up to 64 slots — more than enough).
/// </summary>
public readonly struct CharacterControlDelta
{
    private readonly ulong _bits;

    /// <summary>All bits set — forces full update (used for hot-swap snapshot replay).</summary>
    public static readonly CharacterControlDelta All = new(ulong.MaxValue);

    public static readonly CharacterControlDelta None = new(0UL);

    public CharacterControlDelta(ulong bits) => _bits = bits;

    /// <summary>Check if a specific slot (by offset within character.control range) changed.</summary>
    public bool Contains(int slotOffset) => (_bits & (1UL << slotOffset)) != 0;

    public bool IsEmpty => _bits == 0;

    // Builder helper — set bit for a slot offset
    public CharacterControlDelta With(int slotOffset) =>
        new(_bits | (1UL << slotOffset));
}
```

Slot offsets are relative to `CharacterControlBridgeSchema.SlotBase` (so slot 256 = offset 0, slot 257 = offset 1, etc.).

### Task 3: Implement `ICharacterControlAdapter` interface

**Copy the exact interface from `04-frontend-adapters.md` §3.1.** It's already fully specified:

```csharp
public interface ICharacterControlAdapter : System.IDisposable
{
    FixedString64Bytes AdapterKey { get; }
    void Register(in CharacterControlAdapterContext context);
    void Bind(in CharacterControlBindings bindings);
    void OnStateChanged(in CharacterControlSnapshot snapshot, in CharacterControlDelta delta);
    void Tick(float unscaledDeltaTime);
    void Cleanup();
}
```

### Task 4: Implement `CharacterControlAdapterContext`

```csharp
/// <summary>
/// Services provided to adapters during Register(). 
/// Adapters store what they need; host owns the lifetime.
/// </summary>
public readonly struct CharacterControlAdapterContext
{
    public readonly ICharacterControlCommandSink CommandSink;
    public readonly BridgeRegistrySnapshot Registry; // nullable if schema isn't loaded yet

    public CharacterControlAdapterContext(
        ICharacterControlCommandSink commandSink,
        BridgeRegistrySnapshot registry)
    {
        CommandSink = commandSink;
        Registry = registry;
    }
}
```

### Task 5: Implement `CharacterControlBindings`

**Copy from `04-frontend-adapters.md` §3.2.** Typed readonly struct with all slot and action IDs:

```csharp
public readonly struct CharacterControlBindings
{
    // Slot IDs (read)
    public readonly int VisibleSlotId;
    public readonly int AutomationEnabledSlotId;
    // ... all slots from §3.2

    // Action IDs (write)
    public readonly int ToggleAutomationActionId;
    public readonly int ManualAttackActionId;
    public readonly int PauseGameActionId;

    /// <summary>Resolve all IDs from compile-time constants.</summary>
    public static CharacterControlBindings Resolve()
    {
        return new CharacterControlBindings
        {
            VisibleSlotId = CharacterControlBridgeSchema.Visible,
            AutomationEnabledSlotId = CharacterControlBridgeSchema.AutomationEnabled,
            // ... all mappings
        };
    }

    /// <summary>Resolve from registry snapshot (for dynamic/mod schemas).</summary>
    public static CharacterControlBindings ResolveFromRegistry(BridgeRegistrySnapshot registry)
    {
        // Use TryGetSlotId for each path
        // Throw or log if required slots are missing
    }
}
```

### Task 6: Implement `ICharacterControlCommandSink`

```csharp
/// <summary>
/// Clean command submission surface, decoupling adapters from ConsumerBridge internals.
/// </summary>
public interface ICharacterControlCommandSink
{
    void EnqueueAction(int actionId);
    void EnqueueAction(int actionId, int payload);
}
```

And the concrete implementation:

```csharp
public class DataBridgeCommandSink : ICharacterControlCommandSink
{
    private readonly ConsumerBridge _consumer;

    public DataBridgeCommandSink(ConsumerBridge consumer) => _consumer = consumer;

    public void EnqueueAction(int actionId) =>
        _consumer.PushCommand(actionId, 0);

    public void EnqueueAction(int actionId, int payload) =>
        _consumer.PushCommand(actionId, payload);
}
```

### Task 7: Implement `CharacterControlAdapterHost`

The central orchestrator for adapter lifecycle. Manages one active adapter at a time.

```
CharacterControlAdapterHost:

Fields:
- ICharacterControlAdapter _activeAdapter
- CharacterControlBindings _bindings
- CharacterControlSnapshot _lastSnapshot
- ICharacterControlCommandSink _commandSink
- ConsumerBridge _consumer
- BridgeRegistrySnapshot _registry
- FrontendContract _contract
- bool _bound

Methods:
- Activate(ICharacterControlAdapter adapter)
    1. Validate adapter's required capabilities via ContractValidator
    2. Call adapter.Register(context)
    3. Call adapter.Bind(bindings)
    4. Build full snapshot from current buffer state
    5. Call adapter.OnStateChanged(snapshot, Delta.All)  ← full hydration
    6. Store as _activeAdapter
    
- SwapTo(ICharacterControlAdapter newAdapter)
    1. Build current snapshot
    2. Call _activeAdapter.Cleanup()
    3. Call _activeAdapter.Dispose()
    4. Activate(newAdapter)  ← new adapter gets Delta.All snapshot
    
- Update()  [called every frame from MonoBehaviour]
    1. If no active adapter, return
    2. Scan dirty bitfield via ConsumerBridge for character.control slots
    3. If any dirty: build snapshot + delta, call _activeAdapter.OnStateChanged(snapshot, delta)
    4. Call _activeAdapter.Tick(Time.unscaledDeltaTime)
    
- Shutdown()
    1. _activeAdapter?.Cleanup()
    2. _activeAdapter?.Dispose()
    3. _activeAdapter = null
```

**Key detail for SwapTo**: The new adapter receives `Delta.All` which forces it to read every slot value from the snapshot. This guarantees it starts with correct state even if the old adapter had stale views.

### Task 8: Implement `CharacterControlUiToolkitAdapter`

The first concrete adapter. This replaces the bridge-reading logic currently in `CharacterControlStrip`.

```csharp
public class CharacterControlUiToolkitAdapter : ICharacterControlAdapter
{
    public FixedString64Bytes AdapterKey => "uitk.character.control";

    private ICharacterControlCommandSink _commandSink;
    private CharacterControlBindings _bindings;
    // UI Toolkit element references (VisualElement, Button, Label, etc.)

    public void Register(in CharacterControlAdapterContext context)
    {
        _commandSink = context.CommandSink;
    }

    public void Bind(in CharacterControlBindings bindings)
    {
        _bindings = bindings;
    }

    public void OnStateChanged(
        in CharacterControlSnapshot snapshot,
        in CharacterControlDelta delta)
    {
        // Only update UI elements whose slots actually changed
        if (delta.Contains(0))  // Visible
            SetVisible(snapshot.Visible);
        if (delta.Contains(1))  // AutomationEnabled
            UpdateAutomationToggle(snapshot.AutomationEnabled);
        // ... etc for all slots
    }

    public void Tick(float unscaledDeltaTime)
    {
        // UI Toolkit is immediate — no-op for now
        // Future: animation ticking, tooltip timers
    }

    public void Cleanup()
    {
        // Unsubscribe UI Toolkit callbacks
        // Clear element references
    }

    public void Dispose()
    {
        Cleanup();
    }
}
```

**Important**: The adapter receives UI Toolkit root element references during construction (injected by the host or UIManager). It does NOT create UI elements — it binds to existing ones.

### Task 9: Implement `DebugCharacterControlAdapterDecorator`

```csharp
#if UNITY_EDITOR || DEVELOPMENT_BUILD
public class DebugCharacterControlAdapterDecorator : ICharacterControlAdapter
{
    private readonly ICharacterControlAdapter _inner;
    private readonly List<(double time, CharacterControlSnapshot snapshot)> _history;
    private const int MaxHistory = 300; // ~5 seconds at 60fps

    public FixedString64Bytes AdapterKey => _inner.AdapterKey;

    public DebugCharacterControlAdapterDecorator(ICharacterControlAdapter inner)
    {
        _inner = inner;
        _history = new List<(double, CharacterControlSnapshot)>(MaxHistory);
    }

    public void OnStateChanged(in CharacterControlSnapshot snapshot, in CharacterControlDelta delta)
    {
        // Record history
        if (_history.Count >= MaxHistory) _history.RemoveAt(0);
        _history.Add((Time.unscaledTimeAsDouble, snapshot));

        // Forward to inner
        _inner.OnStateChanged(snapshot, delta);
    }

    // Forward all other methods to _inner
    // ...
}
#endif
```

### Task 10: Implement `CharacterControlAdapterFactory`

```csharp
public static class CharacterControlAdapterFactory
{
    public static ICharacterControlAdapter Create(/* params for UI root, etc. */)
    {
        var adapter = new CharacterControlUiToolkitAdapter(/* ... */);

        #if UNITY_EDITOR || DEVELOPMENT_BUILD
        return new DebugCharacterControlAdapterDecorator(adapter);
        #else
        return adapter;
        #endif
    }
}
```

### Task 11: Delete old `CharacterControlDataBridgePort`

Once the adapter host and UI Toolkit adapter are working and verified:

1. **DELETE** `CharacterControlDataBridgePort.cs` entirely
2. **Modify** `CharacterControlStrip.cs` to use the adapter host instead of the port
3. **Modify** `UIManager.cs` to create and manage the adapter host

This is the clean break. The old polling pattern is gone.

---

## What NOT to Do

- Do NOT keep the old `CharacterControlDataBridgePort` as a fallback. Delete it.
- Do NOT add UI-specific types to the adapter interface. Keep it framework-agnostic.
- Do NOT put adapter types in an asmdef assembly (they reference Assembly-CSharp types). Future extraction is noted but not done now.
- Do NOT implement UGUI or HTML adapters yet. Only UI Toolkit.
- Do NOT add `EntityManager` calls in adapter code. Commands go through the sink.

---

## Verification Checklist

- [ ] **`OnStateChanged` receives correct snapshot**: All slot values in snapshot match DataBridge read buffer
- [ ] **Delta is accurate**: `CharacterControlDelta.Contains(offset)` returns true ONLY for slots that changed this frame
- [ ] **`SwapTo` delivers `Delta.All`**: New adapter receives full snapshot with all bits set
- [ ] **Command sink works**: `EnqueueAction(ActionToggleAutomation)` arrives in ECS command queue
- [ ] **Hot-swap preserves state**: After swap, new adapter's initial snapshot matches old adapter's last known state
- [ ] **Debug decorator records history**: In editor, decorator has snapshot history entries
- [ ] **Debug decorator stripped**: In non-development builds, the `#if` guard ensures decorator type doesn't exist
- [ ] **Old port deleted**: `CharacterControlDataBridgePort.cs` no longer exists
- [ ] **UI Toolkit adapter drives UI**: Character control strip shows correct values from push-based updates
- [ ] **No regression**: All character control UI functionality works as before (toggle automation, manual attack, health bars, etc.)
- [ ] **Capability validation**: If adapter requires a slot that doesn't exist, `Activate()` logs a warning (or throws, depending on Required vs Optional)

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| CREATE | `CharacterControlSnapshot.cs` | Assembly-CSharp |
| CREATE | `CharacterControlDelta.cs` | Assembly-CSharp |
| CREATE | `ICharacterControlAdapter.cs` | Assembly-CSharp |
| CREATE | `CharacterControlAdapterContext.cs` | Assembly-CSharp |
| CREATE | `CharacterControlBindings.cs` | Assembly-CSharp |
| CREATE | `ICharacterControlCommandSink.cs` | Assembly-CSharp |
| CREATE | `DataBridgeCommandSink.cs` | Assembly-CSharp |
| CREATE | `CharacterControlAdapterHost.cs` | Assembly-CSharp |
| CREATE | `CharacterControlUiToolkitAdapter.cs` | Assembly-CSharp |
| CREATE | `DebugCharacterControlAdapterDecorator.cs` | Assembly-CSharp |
| CREATE | `CharacterControlAdapterFactory.cs` | Assembly-CSharp |
| DELETE | `CharacterControlDataBridgePort.cs` | Assembly-CSharp |
| MODIFY | `CharacterControlStrip.cs` | Assembly-CSharp |
| MODIFY | `UIManager.cs` | Assembly-CSharp |
