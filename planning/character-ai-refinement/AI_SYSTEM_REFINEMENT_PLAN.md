# AI System Refinement Plan (Separated Workspace)

## Scope
This document captures the target AI shape to refine before implementation.
It follows the IdleDungeon architecture direction:

- Utility-based goal selection
- Optional planner for complex goals
- Task VM executor with explicit control flow
- Activity layer as world-mutation boundary

---

## Target Decision Stack

1. Perception
2. Knowledge/Memory
3. Utility selection (goal + target)
4. Planner (only when required)
5. Task VM execution
6. Activity execution
7. World state mutation

---

## Core Runtime Contracts

### `AIContext`
- Read-only world snapshot for decisions
- Working memory keys for temporary bindings
- Current goal request payload

### `KnowledgeStore`
- Domain-agnostic fact records
- Timestamped facts, query helpers
- No decision logic inside the store

### `GoalRequest`
- `goal_type`
- `target_key` (optional)
- `urgency` (`Background`, `Normal`, `Urgent`)
- `score_delta` (for diagnostics)

### `TaskExecutor` (VM style)
- Program counter over instructions
- Instruction types: `EXECUTE`, `IF`, `WHILE`, `SELECT_BEST`, `EVALUATE`, `WAIT`, `COMPLETE`, `FAIL`
- Structured completion/failure reasons

### `Activity`
- Lifecycle: `OnStart`, `OnTick`, `OnInterrupt`, `OnComplete`
- Owns interruption semantics
- Only orchestration layer mutating world state

### `Query<T>`
- Candidate generation + scoring
- Reusable for utility and planner

---

## Interruption Policy (Must Be Explicit)

- `Background`: finish current program
- `Normal`: finish current node, then replan
- `Urgent`: immediate interrupt + cleanup, then replan

Anti-thrash controls:
- Goal inertia bonus
- Commit duration
- Replan cooldown

---

## Recommended Initial Goal Set

- Explore
- Fight
- Rest
- Retreat
- Search
- Descend

Add later:
- Investigate (sound/event driven)
- Camp (planner-heavy)
- Regroup

---

## Migration Phases

1. Scaffolding
   - Define interfaces/types and diagnostics structures.
2. Knowledge rewrite
   - Fact-store based visibility/frontiers/memory.
3. Utility core
   - Goal/option/consideration scoring + hysteresis.
4. Task VM + activities
   - Replace direct action logic with instruction execution.
5. Query + goal completion
   - Fill remaining goals and score breakdowns.
6. Planner
   - Time-sliced planner for complex goals only.
7. Domain expansion
   - Add second domain to validate architecture reuse.
8. Legacy removal
   - Remove old AI pathways after parity.

---

## Validation Checklist

1. AI never silently returns no action.
2. Every decision has inspectable score breakdowns.
3. Utility scores are normalized and bounded.
4. Replan behavior is stable (no flip-flop thrashing).
5. Executor/activity paths always emit completion/failure reason codes.
