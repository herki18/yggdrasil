# Wave 1: Dirty-Flag Bitfield and Transition Ring

> **Estimated scope**: ~300-400 lines of new code, ~50 lines of modifications
> **Assembly**: `Sunderia.DataBridge` (allowUnsafeCode)
> **Depends on**: Nothing (foundational)
> **Reference docs**: `DECISION.md` §4 Phase 1, `01-databridge-patterns.md` §2.2, §4-6

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

Before writing any code, read these files in the project:

1. `DECISION.md` — Full document, focus on §4 Phase 1 and §5 Cross-Cutting Concerns
2. `01-databridge-patterns.md` — §2.2 (Pattern B2 dirty bitfield), §4.3 (heartbeat), §6 (implementation pseudo-code)
3. **Existing code** — Read the current `UIPropertyBuffer.cs` and `DoubleBufferedUI.cs` thoroughly. Understand the existing `Write()`, `Read()`, `ChangedSince()`, `_versions[]`, `NewFrame()`, and `Flip()` methods before changing anything.

---

## Context: What Exists Today

`UIPropertyBuffer` is an unmanaged buffer with:
- `PropertyValue* _values` — slot storage (16 bytes per slot)
- `ulong* _versions` — per-slot version counter
- `ulong _currentFrame` — frame counter for `ChangedSince()`
- `Write(int slot, PropertyValue value)` — writes with MemCmp dedup, bumps version on change
- `Read(int slot)` — direct pointer read
- `ChangedSince(int slot, ulong frame)` — checks if slot version > frame
- `NewFrame()` — increments `_currentFrame`
- `Flip()` on `DoubleBufferedUI` — swaps write/read buffer pointers

This all stays. We are ADDING to it, not replacing it.

---

## Tasks

### Task 1: Create `TransitionEntry` struct

**File**: New file `TransitionEntry.cs` in `Sunderia.DataBridge`

```csharp
// Unmanaged struct, ~24 bytes
public struct TransitionEntry
{
    public int Slot;
    public PropertyValue OldValue;
    public PropertyValue NewValue;
    // No frame field needed — all entries in ring are from current frame (cleared each NewFrame)
}
```

Wait — DECISION.md §4 Phase 1 says `(slot, oldValue, newValue, frame)`. Include the frame field:

```csharp
public struct TransitionEntry
{
    public int Slot;
    public PropertyValue OldValue;
    public PropertyValue NewValue;
    public uint Frame;
}
```

This struct must be:
- Unmanaged (no managed references)
- Burst-compatible
- No padding concerns at this size

### Task 2: Create `TransitionRing` struct

**File**: New file `TransitionRing.cs` in `Sunderia.DataBridge`

Fixed-capacity ring buffer. 256 entries. ~12KB total.

```
Design:
- TransitionEntry* _entries (256 capacity, allocated via UnsafeUtility or Allocator.Persistent)
- int _head (next write position, wraps at capacity)
- int _count (entries written this frame, capped at capacity)
- int Capacity => 256 (const)

Methods:
- Append(int slot, PropertyValue oldValue, PropertyValue newValue, uint frame)
    → writes at _head, advances _head % Capacity, increments _count (cap at Capacity)
- Reset() → _head = 0, _count = 0 (called by NewFrame)
- int Count => _count
- TransitionEntry Get(int index) => _entries[index] (0-based from oldest in current frame)
- Dispose() → free _entries
```

Make this a struct with pointer-based storage. It must be allocated/freed explicitly. NOT a NativeArray — we want raw control.

### Task 3: Add dirty bitfield to `UIPropertyBuffer`

**Modify**: `UIPropertyBuffer.cs`

Add a `ulong*` dirty bitfield alongside existing `_versions[]`:

```
Fields:
- ulong* _dirtyBits (1 bit per slot, ceil(capacity / 64) ulongs)
- int _dirtyWordCount (number of ulong words)
- TransitionRing _transitionRing

Allocate in constructor:
- _dirtyWordCount = (capacity + 63) / 64  // e.g., 32 words for 2048 slots = 256 bytes
- _dirtyBits = (ulong*)UnsafeUtility.Malloc(_dirtyWordCount * sizeof(ulong), 8, Allocator.Persistent)
- UnsafeUtility.MemClear(_dirtyBits, _dirtyWordCount * sizeof(ulong))
- _transitionRing = new TransitionRing(256, Allocator.Persistent)

Free in Dispose():
- UnsafeUtility.Free(_dirtyBits, Allocator.Persistent)
- _transitionRing.Dispose()
```

### Task 4: Set dirty bit on Write()

**Modify**: `UIPropertyBuffer.Write()`

After the existing MemCmp detects a value change (and before/after version bump — match existing flow):

```csharp
// Existing: version bump happens here
// ADD: set dirty bit
int word = slot >> 6;       // slot / 64
int bit = slot & 63;        // slot % 64
_dirtyBits[word] |= (1UL << bit);

// ADD: record transition
_transitionRing.Append(slot, oldValue, newValue, (uint)_currentFrame);
```

**Important**: Only set the dirty bit when the value actually changed (inside the MemCmp-true branch). The existing code already has this guard — hook into it.

Capture `oldValue` BEFORE overwriting: `var oldValue = _values[slot];`

### Task 5: Clear dirty bits in NewFrame()

**Modify**: `UIPropertyBuffer.NewFrame()`

```csharp
// ADD at start of NewFrame():
UnsafeUtility.MemClear(_dirtyBits, _dirtyWordCount * sizeof(ulong));
_transitionRing.Reset();
```

This ensures dirty bits and ring only reflect changes from the CURRENT frame's writes.

### Task 6: Add public query APIs

**Modify**: `UIPropertyBuffer.cs`

```csharp
/// <summary>Returns true if ANY slot was written this frame.</summary>
public bool AnyDirty()
{
    for (int i = 0; i < _dirtyWordCount; i++)
    {
        if (_dirtyBits[i] != 0) return true;
    }
    return false;
}

/// <summary>Returns the dirty bitmask for the given word index (0-based).</summary>
public ulong GetDirtyWord(int wordIndex) => _dirtyBits[wordIndex];

/// <summary>Number of ulong words in the dirty bitfield.</summary>
public int DirtyWordCount => _dirtyWordCount;

/// <summary>Force all slots dirty (for heartbeat/reconnect scenarios).</summary>
public void MarkAllSlotsDirty()
{
    for (int i = 0; i < _dirtyWordCount; i++)
    {
        _dirtyBits[i] = ulong.MaxValue;
    }
}

/// <summary>Read-only access to the transition ring for this frame.</summary>
public ref readonly TransitionRing Transitions => ref _transitionRing;
// Or expose as property with getter — whatever matches existing style
```

### Task 7: Add HeartbeatConfig IComponentData

**File**: New file in `Sunderia.Map` or wherever ECS config components live

```csharp
public struct HeartbeatConfig : IComponentData
{
    public int SnapshotEveryNTicks;
}
```

This is a singleton component. The actual heartbeat trigger logic (calling `MarkAllSlotsDirty()` every N ticks) will be wired in Wave 4 when we convert publish systems to `[BurstCompile] ISystem`. For now, just define the component.

---

## What NOT to Do

- Do NOT remove `_versions[]` or `ChangedSince()`. They stay. Both paths coexist.
- Do NOT modify `ConsumerBridge` yet. That's Wave 3.
- Do NOT modify any ECS systems yet. That's Wave 4.
- Do NOT add any managed types to `UIPropertyBuffer`. It must remain fully unmanaged.
- Do NOT use NativeArray for the dirty bitfield. Use raw `ulong*` for Burst compatibility and direct pointer sharing with future JS frontends.

---

## Verification Checklist

After implementation, verify ALL of the following:

- [ ] **Compiles**: The entire `Sunderia.DataBridge` assembly compiles without errors
- [ ] **No leaks**: `UIPropertyBuffer.Dispose()` frees `_dirtyBits` and disposes `_transitionRing`
- [ ] **Write sets bit**: After `Write(slot, newValue)` where value differs, `GetDirtyWord(slot >> 6)` has the correct bit set
- [ ] **Write skips unchanged**: After `Write(slot, sameValue)`, dirty bit is NOT set
- [ ] **NewFrame clears**: After `NewFrame()`, `AnyDirty()` returns false and `Transitions.Count` is 0
- [ ] **AnyDirty works**: Returns false after `NewFrame()` with no writes; true after any write
- [ ] **GetDirtyWord correct**: Writing slots 0, 63, 64, 127 sets bits in words 0 and 1 correctly
- [ ] **TransitionRing records**: After writing a changed value, ring contains entry with correct old/new values
- [ ] **MarkAllSlotsDirty**: After calling, every word in dirty bitfield is `ulong.MaxValue`
- [ ] **Existing ChangedSince still works**: Existing version-based change detection is unaffected
- [ ] **Existing tests pass**: All existing DataBridge tests continue to pass

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| CREATE | `TransitionEntry.cs` | Sunderia.DataBridge |
| CREATE | `TransitionRing.cs` | Sunderia.DataBridge |
| MODIFY | `UIPropertyBuffer.cs` | Sunderia.DataBridge |
| CREATE | `HeartbeatConfig.cs` | Sunderia.Map |
