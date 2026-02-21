# Wave 3: ConsumerBridge Migration to Bitfield Scan

> **Estimated scope**: ~200-300 lines modified
> **Assembly**: `Sunderia.DataBridge.Managed`
> **Depends on**: Wave 1 (dirty bitfield APIs on UIPropertyBuffer)
> **Reference docs**: `DECISION.md` §4 Phase 3, `01-databridge-patterns.md` §6.2, §9.4-9.6

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

1. `DECISION.md` — §4 Phase 3
2. `01-databridge-patterns.md` — §6.2 (consumer scan pseudo-code), §9.4 (reverse lookup), §9.5 (guard slot interaction)
3. **Existing code** — Read `ConsumerBridge.cs` thoroughly. Understand `_bindings`, `Update()`, `ReadSlot()`, guard slot logic, and the `SlotBinding` type.

---

## Context: What Exists Today

`ConsumerBridge.Update()` currently iterates ALL bindings and checks `ChangedSince()` per binding:

```csharp
for (int i = 0; i < _bindings.Count; i++)
{
    if (!readBuffer->ChangedSince(binding.Slot, _lastReadFrame))
        continue;
    // apply binding...
}
```

This is O(total-bindings) even when nothing changed. With the dirty bitfield from Wave 1, we can make it O(changed-slots).

---

## Tasks

### Task 1: Add flat reverse-lookup array

Add a `SlotBinding?[]` array indexed by slot ID for O(1) lookup from slot → binding:

```
SlotBinding?[] _bindingsBySlot  // size = buffer capacity (2048)
// ~65KB at 2048 capacity (SlotBinding is ~32 bytes with object reference)
```

When a binding is registered, set `_bindingsBySlot[binding.Slot] = binding`. When removed, null it out.

This replaces dictionary lookups. 65KB is negligible.

### Task 2: Replace the main update loop with bitfield scan

Replace the per-binding `ChangedSince` loop with a `tzcnt`-based dirty word scan:

```csharp
public void Update()
{
    var readBuffer = /* get read buffer */;

    // Early-out: if nothing changed this frame, skip all work
    if (!readBuffer->AnyDirty())
        return;

    // Scan dirty words
    for (int word = 0; word < readBuffer->DirtyWordCount; word++)
    {
        ulong bits = readBuffer->GetDirtyWord(word);
        while (bits != 0)
        {
            // Find lowest set bit (tzcnt equivalent)
            int localBit = BitOperations.TrailingZeroCount(bits);
            int slot = (word << 6) | localBit;

            // Clear this bit so we advance
            bits &= bits - 1; // clears lowest set bit

            // Look up binding for this slot
            if (slot < _bindingsBySlot.Length)
            {
                var binding = _bindingsBySlot[slot];
                if (binding != null)
                {
                    // Guard slot check (§9.5): if binding has a guard, check guard value
                    if (binding.GuardSlot >= 0)
                    {
                        var guardValue = readBuffer->Read(binding.GuardSlot);
                        if (!guardValue.AsBool()) continue;
                    }

                    // Apply binding
                    ApplyBinding(binding, readBuffer);
                }
            }
        }
    }
}
```

Use `System.Numerics.BitOperations.TrailingZeroCount(ulong)` — this compiles to the hardware `tzcnt` instruction on x64.

### Task 3: Add TransitionWatcher support

Add an optional callback mechanism for slots that need transition-aware updates (e.g., animation triggers on `ActionCode` changes):

```csharp
public delegate void TransitionWatcherCallback(int slot, PropertyValue oldValue, PropertyValue newValue);

// Registration
private Dictionary<int, TransitionWatcherCallback> _transitionWatchers;

public void RegisterTransitionWatcher(int slot, TransitionWatcherCallback callback)
{
    _transitionWatchers ??= new Dictionary<int, TransitionWatcherCallback>();
    _transitionWatchers[slot] = callback;
}

public void UnregisterTransitionWatcher(int slot)
{
    _transitionWatchers?.Remove(slot);
}
```

After the main bitfield scan, drain the transition ring for registered watchers:

```csharp
// After main scan loop
if (_transitionWatchers != null && _transitionWatchers.Count > 0)
{
    ref readonly var ring = ref readBuffer->Transitions;
    for (int i = 0; i < ring.Count; i++)
    {
        var entry = ring.Get(i);
        if (_transitionWatchers.TryGetValue(entry.Slot, out var callback))
        {
            callback(entry.Slot, entry.OldValue, entry.NewValue);
        }
    }
}
```

### Task 4: Migrate `CharacterControlDataBridgePort` away from poll-all

`CharacterControlDataBridgePort.TryGetState()` currently reads ALL 10 slots unconditionally every frame (Pattern A). This should be migrated to use the binding system properly so it benefits from the bitfield scan.

**Approach**: Instead of `TryGetState()` reading all slots, the port should register bindings through `ConsumerBridge` and receive updates only when slots change. The snapshot struct (`CharacterControlState`) should be built incrementally from changed slots.

If this is too invasive for Wave 3, mark it with a clear TODO referencing Wave 5 (where the adapter host replaces this port entirely). But prefer doing it now — clean break.

---

## What NOT to Do

- Do NOT remove the `_bindings` list. Other code may iterate it. The flat array is an addition for fast reverse lookup.
- Do NOT modify `UIPropertyBuffer`. That was Wave 1's job.
- Do NOT add adapter interfaces yet. That's Wave 5.
- Do NOT use `Dictionary<int, SlotBinding>` for reverse lookup. Use the flat array (§9.4).

---

## Verification Checklist

- [ ] **Bitfield scan produces identical output**: Same bindings fire in the same order as the old per-binding version check (modulo ordering — order may differ, but the same set of bindings must fire)
- [ ] **AnyDirty early-out works**: When nothing changed, the update loop body is never entered (verify with a counter or breakpoint)
- [ ] **O(1) reverse lookup**: `_bindingsBySlot[slot]` resolves correctly for all registered bindings
- [ ] **Guard slot logic preserved**: Bindings with guard slots are only applied when guard value is true
- [ ] **TransitionWatcher fires**: Register a watcher on a slot, write a different value, confirm callback fires with correct old/new
- [ ] **TransitionWatcher does not fire for unchanged**: Write same value → no callback
- [ ] **All existing UI still works**: The character control strip, pipeline status, and any other DataBridge consumers display correctly
- [ ] **Compilation clean**: No warnings related to the migration

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| MODIFY | `ConsumerBridge.cs` | Sunderia.DataBridge.Managed |
| MODIFY | `CharacterControlDataBridgePort.cs` (if migrating) | Assembly-CSharp |
