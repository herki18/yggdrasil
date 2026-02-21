# Lundarr Option 3 - Orchestrated Bootstrap + Replaceable UI

## Decision

Use **Option 3** as the default architecture:

1. `GameFlowManager` is the managed UX orchestrator.
2. `GameFlowBridgeSystem` is the ECS command bridge.
3. Startup is blocked by a strict startup payload gate (no implicit fallbacks).
4. Save/load uses real slot persistence (3 fixed JSON slots).
5. UI Toolkit assets live in a replaceable folder contract.

This option gives clean separation between UX, ECS runtime, and persistence, while remaining easy to replace later.

---

## Why This Is The Best Fit Now

1. It supports your requested flow immediately:
   - Main Menu
   - New Game
   - Load Game
   - Settings
   - Character creation (simple dummy)
   - Enter game shell
2. It avoids hidden coupling by forcing startup payload validation.
3. It keeps UI replaceable by contract (name-based element bindings).
4. It keeps future migration cheap (UI and runtime systems can evolve independently).

---

## Implemented Runtime Shape

## Managed orchestrator

- `GameFlowManager` controls user flow states:
  - `MainMenu -> CharacterCreation/LoadGame/Settings -> Loading -> Running/Paused`
- Queues startup payload:
  - `isLoad`, `slot`, `characterName`, `archetype`
- Bridges commands:
  - trigger start
  - set paused
  - push startup payload

## ECS bootstrap pipeline

`BootstrapAuthored -> AwaitingGameStart -> ScriptRuntimeReady -> BrowserReady -> SchemaReady -> Running`

- `BootstrapValidationSystem` validates singleton and required components.
- `GameStartGateSystem` enforces startup payload presence/validity.
- `ScriptRuntimeBootstrapSystem` initializes scripting runtime.
- `BrowserRuntimeBootstrapSystem` initializes browser + web/script bridge.
- `SchemaRegistryBootstrapSystem` builds bridge schema.
- `StartupFinalizeSystem` advances to `Running`.

---

## Persistence Contract

- Save store: `CharacterSaveStore`
- Slots: 3 fixed slots (`character_slot_1..3.json`)
- Path: `Application.persistentDataPath/saves/`
- Status per slot: `Empty`, `Valid`, `Corrupt`
- Validation:
  - slot index
  - name required
  - archetype required
  - version present

---

## Replaceable UI Contract

Primary UI folder:

- `Assets/UI Toolkit/LundarrShell/`

Critical binding contract:

- UXML document names and element names used by `GameShellController`
- If replacing the UI, keep names or update controller bindings

Current flow UXML docs:

1. `MainMenu.uxml`
2. `CharacterCreation.uxml`
3. `LoadGame.uxml`
4. `Settings.uxml`
5. `LoadingScreen.uxml`
6. `GameShell.uxml`

---

## Execution Checklist (Refined)

1. Keep Option 3 architecture as baseline for all next features.
2. Add gameplay systems that consume `GameActiveCharacterProfile`.
3. Add save migration policy when `CharacterSaveSlotData.Version` changes.
4. Add tests:
   - startup payload missing/invalid -> fail
   - valid payload -> running
   - save/load slot validation
5. Add UI replacement guide versioning:
   - contract version number
   - required element IDs per view

---

## Explicit Non-Goals For This Step

1. Full gameplay persistence beyond character identity.
2. Full character customization depth.
3. Runtime world reset/restart architecture.

