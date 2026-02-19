# Semi-Idle Control Model (Foundation-First)

## Goal
Support both:
- automated play (default loop), and
- manual player intervention (high-impact override),

without creating two separate gameplay pipelines.

This model is designed to be reusable across future games.

---

## 1) Core Principle

One simulation path for all actions:
- AI decisions and player manual actions both become the same `ActionRequest`.
- The same execution pipeline resolves them.

Manual input is an override layer, not a separate combat/ability system.

---

## 2) Control Layers

1. **Automation Layer**
   - Runs utility/planner/task execution.
   - Produces `ActionRequest(source = AI)`.

2. **Manual Intent Layer**
   - Receives player commands.
   - Produces `ActionRequest(source = Player)`.

3. **Arbitration Layer**
   - Chooses which request is active now.
   - Applies lock/priority/interrupt rules.

4. **Execution Layer**
   - Runs selected request through existing ability/action pipeline.

---

## 3) Minimal Runtime Contracts

### `PlayerIntent` (transient)
- `actor_entity`
- `intent_type` (cast_ability, move, retreat, target_focus, etc.)
- `ability_entity` (optional)
- `target_entity` or `target_position`
- `issued_tick`
- `priority` (default manual > AI unless blocked by hard constraints)

### `AutomationProfile` (persistent)
- `profile_id`
- `risk_tolerance`
- `resource_floor_mana`
- `resource_floor_stamina`
- `heal_threshold`
- `retreat_threshold`
- `forbidden_tags[]`
- `preferred_tags[]`

### `ControlLockState` (persistent)
- `lock_owner` (`AI` or `Player`)
- `lock_reason`
- `lock_started_tick`
- `lock_expires_tick`
- `can_urgent_interrupt` (bool)

### `ActionRequest` (normalized)
- `source` (`AI`/`Player`)
- `actor_entity`
- `ability_entity` (optional)
- `target_entity/position`
- `urgency`
- `reason_code`

---

## 4) Arbitration Rules

1. Hard safety/validity gates always run first.
2. Valid player intent overrides AI by default.
3. Manual override sets short `ControlLockState` window.
4. Urgent safety goals (e.g., death prevention) can interrupt manual lock if enabled.
5. After lock expiry, control returns to automation.

This preserves strategic player control while preventing constant click babysitting.

---

## 5) UX Model (Small, High-Signal On-Screen)

Show one compact control strip:

1. `Automation: ON/OFF` toggle
2. Current controller badge: `AI` or `PLAYER`
3. Current action text: `Casting Fireball -> Goblin A`
4. Lock timer bar (if manual lock active)
5. Last blocked intent reason (short text, e.g., `Blocked: Out of range`)

Optional next:
- Quick profile switch buttons: `Safe`, `Balanced`, `Aggro`.

---

## 6) Smallest Thing To Implement First (Vertical Slice)

### Slice objective
Put visible control UX on screen and prove manual override works end-to-end using existing execution foundations.

### Scope (strictly minimal)
1. Single controllable character.
2. Single enemy target.
3. One auto action (basic attack via AI).
4. One manual action button (same attack).
5. Arbitration + short manual lock.
6. On-screen control strip reflecting owner/action/lock.

### Success criteria
1. With automation ON, character repeatedly auto-attacks.
2. Clicking manual action immediately takes control and executes player request.
3. Manual lock is shown and expires.
4. After expiry, AI resumes automatically.
5. No separate manual execution code path.

### Why this is the right first step
- Gives immediate UX feedback.
- Validates the hardest architectural seam (AI vs player arbitration).
- Reusable in future games because contracts are generic.

---

## 7) Foundation Systems For This Slice

1. `PlayerIntentInputSystem`
   - Converts UI input into `PlayerIntent`.

2. `AutomationRequestSystem`
   - Produces one simple AI `ActionRequest` when automation is enabled.

3. `IntentArbitrationSystem`
   - Chooses winner, sets/updates `ControlLockState`.

4. `ActionDispatchSystem`
   - Sends normalized `ActionRequest` into current action execution pipeline.

5. `ControlHudPresenter`
   - Renders control strip fields from runtime state.

Keep these systems generic and game-agnostic; only ability IDs/targets are game-specific.

---

## 8) What Not To Build Yet

- Full multi-goal utility tuning UI
- Complex planner-driven manual interrupts
- Party-wide command hierarchies
- Offline/idle compression logic
- Deep profile editor

Ship the arbitration seam first, then expand.

---

## 9) Next Step After Slice

Add `AutomationProfile` switching (`Safe/Balanced/Aggro`) and feed profile values into candidate filtering/scoring.

That is the first meaningful extension while staying foundation-focused.
