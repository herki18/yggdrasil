# Wave 6: UX Feedback Refresh

> **Estimated scope**: ~400-600 lines of new/modified code
> **Assembly**: `Assembly-CSharp` (UI layer)
> **Depends on**: Wave 4 (new slots + escalation) + Wave 5 (adapter lifecycle)
> **Reference docs**: `DECISION.md` §4 Phase 6, `02-interaction-model.md` §6 (UX mapping table)

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

1. `DECISION.md` — §4 Phase 6, §7 Verification Checklist Phase 6
2. `02-interaction-model.md` — §6 (complete UX feedback mapping table with all 25 action_code × block_reason_code combinations)
3. **Existing code** — Read the current `CharacterControlStrip.cs` and `CharacterControlUiToolkitAdapter.cs` (from Wave 5)

---

## Context

With Waves 1-5 complete, we now have:
- Push-based adapter receiving `OnStateChanged(snapshot, delta)` with all 19 slots
- New slots: cooldown, stamina, mana, can_manual_attack, escalation_flags, escalation_severity
- TransitionWatcher capability for animation triggers
- Everything flowing through the clean adapter pattern

This wave is about making the UX actually USE all that data.

---

## Tasks

### Task 1: Implement the UX Mapping Table

From `02-interaction-model.md` §6, there are 25 combinations of `ActionCode` × `BlockReasonCode` that produce specific visual states. Implement this as a deterministic lookup:

```csharp
/// <summary>
/// Maps (ActionCode, BlockReasonCode) → UX state for the character control panel.
/// This is the SINGLE SOURCE OF TRUTH for what the UI shows for each game state.
/// </summary>
public static class CharacterControlUxMapping
{
    public struct UxState
    {
        public string StatusText;         // e.g., "Attacking...", "On Cooldown"
        public string TooltipText;        // e.g., "AI is executing basic attack"
        public bool AttackButtonEnabled;  // Whether the manual attack button is interactable
        public string AttackButtonLabel;  // e.g., "Attack", "Wait...", "Blocked"
        public UxSeverity Severity;       // For color coding: Normal, Warning, Error
    }

    public enum UxSeverity { Normal, Warning, Error }

    /// <summary>
    /// Look up the UX state for the given action and block reason.
    /// Uses switch-based dispatch — no allocation, no reflection.
    /// </summary>
    public static UxState Resolve(int actionCode, int blockReasonCode)
    {
        // Implement ALL 25 combinations from 02-interaction-model §6
        // Use nested switch: outer on actionCode, inner on blockReasonCode
        // Default/unknown → safe fallback state
    }
}
```

**This must cover ALL combinations from the interaction model doc.** Read §6 carefully and implement every single one. Unknown values must produce a safe fallback (not a crash).

### Task 2: Manual Attack Button driven by `CanManualAttack`

The attack button's enabled/disabled state is now driven by the computed `can_manual_attack` slot (from Wave 4) rather than ad-hoc logic in the UI:

```csharp
// In OnStateChanged:
if (delta.Contains(/* CanManualAttack offset */))
{
    _attackButton.SetEnabled(snapshot.CanManualAttack);
}
```

This replaces any existing logic that manually checks cooldown, health, etc. in the UI layer. The ECS side computes the boolean; the UI just reflects it.

### Task 3: Cooldown Radial Indicator

Drive a radial/circular progress indicator from `cooldown_ticks_remaining` / `cooldown_ticks_total`:

```csharp
if (delta.Contains(/* CooldownTicksRemaining offset */) ||
    delta.Contains(/* CooldownTicksTotal offset */))
{
    float progress = snapshot.CooldownTicksTotal > 0
        ? 1f - ((float)snapshot.CooldownTicksRemaining / snapshot.CooldownTicksTotal)
        : 1f;
    _cooldownRadial.SetProgress(progress);

    bool onCooldown = snapshot.CooldownTicksRemaining > 0;
    _cooldownRadial.SetVisible(onCooldown);
    // Optionally show remaining time as text
}
```

Implementation details for the radial depend on the UI Toolkit approach (custom VisualElement with Mesh API, or USS clip/mask). Build whatever is clean and correct.

### Task 4: Escalation UI — Toast Notifications

When `escalation_severity` changes and is ≥ Medium, show a toast notification:

```csharp
if (delta.Contains(/* EscalationSeverity offset */))
{
    var severity = (EscalationSeverity)snapshot.EscalationSeverity;
    if (severity >= EscalationSeverity.Medium)
    {
        ShowEscalationToast(severity, (EscalationFlags)snapshot.EscalationFlags);
    }
}
```

Toast behavior:
- **Medium**: Informational toast, auto-dismiss after 3 seconds
- **High**: Warning toast, stays until dismissed or severity drops
- **Critical**: Urgent toast with auto-pause prompt ("Your character is critically wounded. Pause?")
    - Auto-pause is frontend-owned (DECISION.md §8 OQ #6): the frontend decides whether to send a pause command through the command sink

Design the toast system to be generic (not character-control-specific) so it can be reused for other notifications later.

### Task 5: Deprecate `LockTicksRemaining` from Player-Facing UI

`LockTicksRemaining` (slot 259) is now debug-only. Remove any display of it from the player-facing character control panel. Keep it in the debug overlay/panel only.

The player-facing UI should show `CooldownTicksRemaining` via the radial indicator instead.

### Task 6: Register TransitionWatcher for Animation Triggers

Use the TransitionWatcher from Wave 3 to trigger animations when `ActionCode` changes:

```csharp
// During adapter setup (Register or Bind):
_consumerBridge.RegisterTransitionWatcher(
    CharacterControlBridgeSchema.ActionCode,
    OnActionCodeTransition);

private void OnActionCodeTransition(int slot, PropertyValue oldValue, PropertyValue newValue)
{
    int oldAction = oldValue.AsInt();
    int newAction = newValue.AsInt();

    // Trigger animation/VFX based on transition
    if (newAction == (int)CharacterActionCode.BasicAttack)
    {
        PlayAttackAnimation();
    }
    // ... other transitions
}
```

This provides immediate visual feedback on action changes without waiting for the next `OnStateChanged` call. The transition callback fires in the same frame as the change.

### Task 7: Resource Bars (Stamina, Mana)

Add stamina and mana bar displays:

```csharp
if (delta.Contains(/* StaminaCurrent offset */) ||
    delta.Contains(/* StaminaMax offset */))
{
    float staminaPercent = snapshot.StaminaMax > 0
        ? (float)snapshot.StaminaCurrent / snapshot.StaminaMax
        : 0f;
    _staminaBar.SetProgress(staminaPercent);
    _staminaLabel.text = $"{snapshot.StaminaCurrent}/{snapshot.StaminaMax}";
}

// Same pattern for mana
```

### Task 8: Wire Everything into the UI Toolkit Adapter

Ensure the `CharacterControlUiToolkitAdapter.OnStateChanged()` method handles ALL slots through the UX mapping + individual slot handlers. The adapter should now be the complete, authoritative translation layer between DataBridge state and visual output.

Clean up any remaining ad-hoc state reading in UI MonoBehaviours. Everything goes through the adapter.

---

## What NOT to Do

- Do NOT add ECS queries in UI code. All state comes through the adapter's snapshot.
- Do NOT use `EntityManager` anywhere in this wave.
- Do NOT keep `LockTicksRemaining` visible in player UI. Debug panel only.
- Do NOT create new DataBridge slots. All slots were defined in Wave 4.
- Do NOT modify the adapter interface. If something doesn't fit, extend the adapter's internal implementation.

---

## Verification Checklist

- [ ] **All 25 action/block combinations correct**: Each combination from §6 produces the expected button state, status text, and tooltip
- [ ] **Unknown action/block values handled**: An unrecognized `ActionCode` produces a safe fallback, not a crash or empty UI
- [ ] **Attack button reflects `can_manual_attack`**: Button is enabled only when the slot is true
- [ ] **Cooldown radial shows correctly**: Progress goes from 0% to 100% as cooldown expires; hidden when no cooldown active
- [ ] **Cooldown radial edge cases**: Total = 0 doesn't divide by zero; remaining > total doesn't show > 100%
- [ ] **Escalation toast at Medium+**: Severity change to Medium or above shows a toast
- [ ] **Escalation toast auto-dismiss**: Medium severity toast auto-dismisses after ~3 seconds
- [ ] **Critical escalation auto-pause prompt**: Critical severity shows pause prompt; clicking it sends pause command
- [ ] **LockTicksRemaining hidden**: No player-facing UI shows lock ticks; debug panel still can
- [ ] **Transition animation fires**: Changing `ActionCode` in the DataBridge triggers the correct animation callback
- [ ] **Stamina/mana bars display**: Both bars show correct values and update only when their slots change
- [ ] **No regression**: All previously working UI (health bars, automation toggle, controller owner) still functions correctly
- [ ] **No GC in hot path**: Profile the `OnStateChanged` path — no allocations per frame (string formatting should use cached/pooled strings)

---

## Files Created/Modified Summary

| Action | File | Assembly |
|--------|------|----------|
| CREATE | `CharacterControlUxMapping.cs` | Assembly-CSharp |
| CREATE | Escalation toast UI (VisualElement/USS) | Assembly-CSharp |
| MODIFY | `CharacterControlUiToolkitAdapter.cs` | Assembly-CSharp |
| MODIFY | `CharacterControlStrip.cs` (remove old mapping logic) | Assembly-CSharp |
| MODIFY | UXML/USS for cooldown radial, resource bars | Assembly-CSharp |
