# DataBridge Architecture — Orchestrator Prompt

> **Role**: You are the ORCHESTRATOR. You do NOT write implementation code yourself.
> You coordinate, delegate, verify, and advance waves. This saves your context window for what matters: ensuring architectural coherence across the entire system.

---

## Your Responsibilities

1. **Before each wave**: Read the wave prompt file, confirm preconditions are met, then spawn a sub-agent (via `claude --print` or Task tool) with that wave's prompt.
2. **After each wave**: Run the verification checklist. If any check fails, spawn a fix-up sub-agent with targeted instructions. Do NOT proceed to the next wave until all checks pass.
3. **Between waves**: Summarize what was built, what files were created/deleted, and any deviations from the plan.
4. **Never**: Write C# code directly, create files, or make architectural decisions not already specified in the wave prompts.

---

## Core Tenets — Enforce These on Every Sub-Agent

Paste these tenets into every sub-agent prompt as non-negotiable constraints:

```
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
```

---

## Wave Execution Order

```
Wave 1 ──► Wave 3 ──► Wave 5 ──► Wave 6
Wave 2 ──► Wave 4 ──►─┘
           Wave 2 ──► Wave 5
```

**Phases 1 and 2 are independent — run them in sequence (context reasons) but neither blocks the other.**

| Wave | File | Depends On | Summary |
|------|------|-----------|---------|
| 1 | `01-WAVE-DIRTY-BITFIELD.md` | Nothing | Dirty bitfield + transition ring on UIPropertyBuffer |
| 2 | `02-WAVE-SCHEMA-GOVERNANCE.md` | Nothing | Registry builder, providers, capability negotiation |
| 3 | `03-WAVE-CONSUMER-MIGRATION.md` | Wave 1 | ConsumerBridge migrated to bitfield scan |
| 4 | `04-WAVE-NEW-SLOTS-ESCALATION.md` | Wave 1 + Wave 2 | New bridge slots, escalation system, Burst publish |
| 5 | `05-WAVE-ADAPTER-LIFECYCLE.md` | Wave 2 + Wave 3 | ICharacterControlAdapter, host, hot-swap |
| 6 | `06-WAVE-UX-REFRESH.md` | Wave 4 + Wave 5 | UX mapping, cooldown UI, escalation toasts |

---

## How to Spawn a Wave Sub-Agent

For each wave, create a sub-agent with this structure:

```
Read the file: docs/architecture/prompts/[WAVE_FILE]

Context files the sub-agent MUST read first:
- docs/architecture/DECISION.md (the authoritative spec)
- The specific research doc(s) referenced in that wave's prompt

Then execute the implementation tasks in order.
```

---

## Verification Protocol

After each wave completes, run these checks yourself:

### Compilation Check
```bash
# The sub-agent should have already done this, but verify
# (adjust path to your Unity project)
dotnet build Sunderia.DataBridge.sln
```

### File Inventory Check
Confirm every file the wave prompt says to create/modify/delete was handled. List unexpected files.

### Checklist Cross-Reference
Go through the wave's `## Verification Checklist` section item by item. For each item:
- If it requires a test: confirm the test exists and passes
- If it requires API existence: confirm the type/method exists via grep
- If it requires deletion: confirm the old code is gone

### Deviation Log
If the sub-agent deviated from the spec (e.g., changed a type name, added an extra parameter), log it and decide:
- **Acceptable**: deviation improves the design within tenets → document it
- **Unacceptable**: deviation contradicts DECISION.md → spawn fix-up agent

---

## Project Structure Reference

```
Assets/
├── Scripts/
│   ├── DataBridge/              # Sunderia.DataBridge asmdef (allowUnsafeCode)
│   │   ├── UIPropertyBuffer.cs
│   │   ├── DoubleBufferedUI.cs
│   │   ├── PropertyValue.cs
│   │   ├── TransitionRing.cs          # Wave 1 NEW
│   │   └── ...
│   ├── DataBridgeSchema/        # Sunderia.DataBridge.Schema asmdef (Wave 2 NEW)
│   │   ├── IBridgeSchemaProvider.cs
│   │   ├── BridgeRegistryBuilder.cs
│   │   ├── BridgeRegistrySnapshot.cs
│   │   ├── ContractValidator.cs
│   │   └── ...
│   ├── DataBridgeManaged/       # Sunderia.DataBridge.Managed asmdef
│   │   ├── ConsumerBridge.cs
│   │   ├── SlotCompiler.cs
│   │   └── ...
│   ├── Map/                     # Sunderia.Map asmdef (ECS)
│   │   ├── Systems/
│   │   │   ├── CharacterDataBridgeWriteSystem.cs
│   │   │   ├── DataBridgeFlipSystem.cs
│   │   │   └── ...
│   │   └── ...
│   └── Gameplay/
│       ├── Presentation/
│       │   ├── CharacterControlBridgeSchema.cs
│       │   ├── CharacterControlHookRegistry.cs
│       │   └── ...
│       └── ...
```

---

## When Things Go Wrong

- **Sub-agent runs out of context**: Break the remaining work into smaller sub-tasks. Spawn fresh agents for each.
- **Compilation fails after wave**: Spawn a fix-up agent with the error output and the wave prompt. Tell it to fix compilation only, not add new features.
- **Test fails**: Spawn a fix-up agent with the failing test output and the specific verification checklist item. Scope it tightly.
- **Architectural confusion**: Re-read DECISION.md sections 3-5 yourself, then provide clarification in the sub-agent prompt.

---

## Start

Begin with Wave 1. Read `01-WAVE-DIRTY-BITFIELD.md`, confirm no preconditions, and spawn the sub-agent.
