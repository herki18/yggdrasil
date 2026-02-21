# Lundarr — Game Design Document

## 1. Vision

Lundarr is an MC-centric idle dungeon RPG for Steam PC. The player controls a single character who auto-loops through procedurally generated dungeons, growing stronger through a deep skill system and strategic ability configuration. Inspired by Lootun's auto-dungeon loop and built on a V3 Node Graph skill system that gives players meaningful build choices without manual combat execution.

**Core fantasy**: You are a dungeon delver who grows from clearing rat-infested cellars to conquering ancient vaults. Your power comes not from clicking faster, but from mastering the right skills, equipping the right abilities, and configuring the right strategies.

**Target audience**: Players who enjoy idle/incremental games with meaningful depth — fans of Melvor Idle, Lootun, IdleOn, and Path of Exile's build system.

**Platform**: Steam PC (Windows). Potential future: Mac, Linux.

---

## 2. Core Loop

```
┌──────────────────────────────────────────────┐
│                  TOWN HUB                     │
│  Train skills ← Equip abilities ← Manage gear │
│         │                                      │
│         ▼                                      │
│    SELECT DUNGEON                              │
│         │                                      │
│         ▼                                      │
│  ┌─── AUTO-DUNGEON LOOP ────┐                 │
│  │  Room → Combat → Loot    │                 │
│  │    ↓                     │                 │
│  │  Next room (or floor)    │                 │
│  │    ↓                     │                 │
│  │  Boss checkpoint         │                 │
│  │    ↓                     │                 │
│  │  Continue / retreat      │                 │
│  └──────────────────────────┘                 │
│         │                                      │
│         ▼                                      │
│    REWARDS → Town                              │
└──────────────────────────────────────────────┘
```

### Session flow
1. **Town phase**: Review character, train skills, equip ability cards, upgrade gear
2. **Dungeon selection**: Choose dungeon tier and type (each has element/enemy themes)
3. **Auto-dungeon**: Character automatically fights through rooms. Player watches, adjusts strategy mid-run if needed
4. **Floor progression**: Clear rooms to reach floor boss. Beat boss to advance to next floor
5. **Run end**: Character dies or retreats. Keep all loot and XP earned. Return to town

### Idle mechanics
- Runs continue while the game is open (auto-loop: town → dungeon → town)
- Offline progress: simplified simulation for time away (reduced loot rate)
- No energy/stamina gates — play as much as desired

---

## 3. V3 Node Graph System

The V3 Node Graph is the core character-building system. It replaces traditional skill trees with a modular, composable graph.

### Hierarchy

```
Nodes → Skills → Abilities → Ability Cards
```

#### Nodes
Fundamental building blocks that define what a character can do. Each node represents a discrete capability.

- **Stat nodes**: Strength, Agility, Intelligence, Vitality, Spirit
- **Element nodes**: Fire, Ice, Lightning, Earth, Shadow, Holy
- **Technique nodes**: Slash, Pierce, Strike, Channel, Conjure
- **Utility nodes**: Block, Dodge, Heal, Buff, Debuff

Nodes are unlocked through gameplay and can be leveled up through training.

#### Skills
Skills are formed by connecting 2-3 nodes in the graph. The combination of nodes determines the skill's properties.

Example connections:
- Fire + Conjure = Fireball (ranged fire damage)
- Ice + Channel = Frost Nova (AoE ice damage)
- Strength + Slash = Power Strike (melee physical damage)
- Agility + Dodge + Strike = Counter (dodge-triggered melee)

Skills inherit properties from their component nodes:
- Damage type from element/technique nodes
- Scaling stats from stat nodes
- Special behaviors from utility nodes

#### Abilities
Abilities are refined skills with additional modifiers applied. A skill becomes an ability when the player configures:
- **Quality level**: Trained through repetition (affects base power)
- **Modifier slots**: Socket-like slots for ability modifiers
- **Trigger conditions**: When the AI should use this ability

#### Ability Cards
The final equipped form. Each character has a limited number of ability card slots (starts at 4, expands to 8 through progression). Cards are what the Utility AI evaluates during combat.

Each card contains:
- The ability definition (from the node graph)
- Priority/weight for AI scoring
- Cooldown settings
- Resource cost (mana, stamina, etc.)

### Node Graph UI
- Visual graph editor where players connect nodes with edges
- Discovered combinations highlight as "known skills"
- Experimentation encouraged — try new node combinations
- Graph layout persists per character

---

## 4. Idle Dungeon Loop

### Dungeon structure
- Each dungeon is a sequence of **floors**
- Each floor contains **5-10 rooms** plus a **floor boss**
- Rooms contain 1-3 enemy encounters
- Every 5 floors: **boss checkpoint** (harder boss, better loot, acts as progress save)

### Room progression (Lootun-inspired)
1. Enter room → enemies spawn
2. Character auto-attacks using equipped ability cards
3. AI evaluates ability cards each tick, executes highest-scoring valid ability
4. Room cleared → loot drops → move to next room
5. If character dies → run ends, keep all loot earned so far

### Floor scaling
- Enemy stats scale with floor number (linear base + exponential modifier)
- Enemy types cycle through themed pools per dungeon
- Loot quality scales with floor depth
- Boss floors have guaranteed drops from themed loot tables

### Dungeon types
- **Cellar**: Starting dungeon, undead/vermin theme
- **Caverns**: Underground, earth/crystal theme
- **Ruins**: Ancient, magical/construct theme
- **Abyss**: Deep, shadow/demon theme
- **Spire**: Vertical, elemental/boss rush theme
- More unlocked through progression

### Auto-loop
When enabled, the character automatically:
1. Finishes dungeon run (death or clear)
2. Returns to town
3. Auto-sells junk loot
4. Re-enters the same dungeon
5. Repeats until manually stopped

---

## 5. Progression Systems

### Skill training
Each node and skill has three training tracks:

| Track | How it trains | What it improves |
|-------|--------------|-----------------|
| **Reps** | Use the skill in combat | Raw power, base damage |
| **Technique** | Use in varied situations | Efficiency, crit chance, cost reduction |
| **Understanding** | Reach milestones, discover combos | Unlock modifiers, new combinations |

Training is passive — skills improve through use during dungeon runs.

### Equipment
- Weapons: Determine base damage range and attack speed
- Armor: Provides defense and resistance
- Accessories: Grant passive bonuses and special effects
- All equipment has rarity tiers: Common → Uncommon → Rare → Epic → Legendary
- Equipment can be enchanted with modifiers from the node graph system

### Prestige (Rebirth)
- After reaching a milestone (e.g., floor 100), player can prestige
- Resets: Floor progress, equipment, some skill levels
- Keeps: Node unlocks, discovered skills, prestige currency
- Prestige currency buys permanent upgrades: more ability slots, training speed, starting bonuses
- Each prestige increases the overall power ceiling

### Town upgrades
- **Training grounds**: Passive skill training while idle
- **Forge**: Equipment crafting and enhancement
- **Library**: Unlock new node combinations
- **Guild hall**: Unlock new dungeon types
- **Market**: Buy/sell equipment, trade materials

---

## 6. Combat System

### Utility AI with ability card scoring
Combat is fully automated. The AI evaluates each equipped ability card every decision tick.

**Scoring formula per card:**
```
Score = BasePriority
      × SituationMultiplier(enemies, health, buffs)
      × CooldownReadiness(0 if on cooldown, 1 if ready)
      × ResourceAvailability(0 if not enough, 1 if sufficient)
      × TargetQuality(how good the available targets are)
```

The highest-scoring valid ability is executed.

**Situation multipliers** (examples):
- Heal ability scores higher when health is low
- AoE scores higher when multiple enemies present
- Debuff scores higher against bosses
- Buff scores higher at start of combat

### Node execution with quality flow
When an ability executes:
1. **Node resolution**: Evaluate each node in the ability's graph path
2. **Quality roll**: Skill quality (from training) affects outcome variance
3. **Effect application**: Damage, healing, buffs, debuffs applied
4. **Feedback**: Visual effects, damage numbers, status indicators

### Combat stats
- **HP**: Health points, character dies at 0
- **MP/SP**: Mana/Stamina for ability costs
- **Attack**: Base damage modifier
- **Defense**: Damage reduction
- **Speed**: Action frequency
- **Crit Rate/Damage**: Critical hit chance and multiplier
- **Elemental Resistances**: Per-element damage reduction
- **Accuracy/Evasion**: Hit chance calculations

---

## 7. UI Design

### Tab structure
The main UI is organized into tabs, accessible at all times:

| Tab | Purpose |
|-----|---------|
| **Dungeon** | Current dungeon view, combat log, auto-loop controls |
| **Character** | Stats, equipment, inventory management |
| **Abilities** | Node graph editor, skill list, ability card configuration |
| **Town** | Town buildings, upgrades, NPC interactions |
| **Settings** | Game settings, controls, accessibility options |

### UX principles
- **Information density**: Show relevant stats without overwhelming
- **One-click depth**: Any stat should be explainable in one click/hover
- **Idle-friendly**: Important info visible at a glance, no mandatory interaction during runs
- **Keyboard navigation**: Full keyboard support, hotkeys for common actions
- **Responsive panels**: Panels resize and reflow for different window sizes

### Key UI components
- **Dungeon HUD**: Floor/room counter, HP/MP bars, ability cooldowns, loot ticker
- **Node graph canvas**: Zoomable, pannable graph editor with snap-to-grid
- **Ability card tray**: Drag-and-drop card arrangement with quick-swap
- **Equipment paper doll**: Visual character with equipment slots
- **Training progress bars**: Per-skill training track visualization

---

## 8. Technical Architecture

### Assembly graph
```
Lundarr.DataBridge.Schema    ← pure C# types, no Unity refs
    ↑
Lundarr.DataBridge           ← unmanaged data types, buffer mgmt (unsafe)
    ↑           ↑
Lundarr.Game    Lundarr.DataBridge.Managed
(ECS systems)   (consumer bridge)
```

### ECS system groups (planned)
```
InitializationSystemGroup
  ├── GameBootstrapSystem          — one-shot setup
  ├── DataBridgeLifecycleSystem    — allocate bridge
  └── ScriptRuntimeBootstrapSystem — load .se definitions

SimulationSystemGroup
  ├── InputProcessingGroup
  │   └── PlayerInputSystem        — read input actions
  ├── GameSimulationGroup
  │   ├── DungeonProgressionSystem — room/floor advancement
  │   ├── CombatTickSystem         — AI scoring + ability execution
  │   ├── AbilityExecutionSystem   — node resolution + effect apply
  │   ├── StatusEffectSystem       — buff/debuff tick
  │   ├── LootGenerationSystem     — drop rolls on kill
  │   └── TrainingProgressSystem   — skill training updates
  └── DataBridgeWriteGroup
      ├── CombatStateWriteSystem   — HP/MP/cooldowns → bridge
      ├── ProgressWriteSystem      — floor/room/XP → bridge
      └── InventoryWriteSystem     — equipment/loot → bridge

PresentationSystemGroup
  ├── DataBridgeFlipSystem         — swap read/write buffers
  └── UIUpdateGroup                — consumers read bridge
```

### Script integration
- Node definitions loaded from `.se` script files
- Skills defined as block compositions in script
- Modifiers use the Paradox-style modifier system from ScriptingEngine
- Dungeon templates scripted for procedural generation rules

---

## 9. Implementation Roadmap

### Phase 0: Project Setup (current)
- [x] Create repo, Unity project, assembly definitions
- [x] Copy DataBridge from Sunderia
- [x] Package manifest, URP pipeline, project settings
- [ ] Verify in Unity Editor (0 compilation errors)

### Phase 1: Core Bootstrap
- Game bootstrap system (lifecycle state machine)
- DataBridge writer for game state
- Basic UI shell with tab navigation (UI Toolkit)
- Script runtime initialization

### Phase 2: Character Foundation
- Character entity with base stats
- Equipment component data
- Inventory system (NativeHashMap-based)
- Character panel UI

### Phase 3: Node Graph — Data Layer
- Node definitions in .se scripts
- Skill composition logic (node + node → skill)
- Ability and ability card data structures
- Graph serialization/deserialization

### Phase 4: Node Graph — UI
- Visual graph editor (UI Toolkit canvas)
- Node placement, edge drawing, snap-to-grid
- Skill discovery feedback
- Ability card configuration panel

### Phase 5: Combat System
- Enemy entity spawning
- Utility AI ability scoring
- Node execution pipeline
- Damage/healing/status effect application
- Combat log

### Phase 6: Dungeon Loop
- Room/floor progression state machine
- Enemy wave generation per room
- Floor boss encounters
- Loot drop system
- Auto-loop controller

### Phase 7: Progression
- Skill training (reps/technique/understanding)
- Equipment enhancement
- Town buildings (training grounds, forge, library)
- Prestige system

### Phase 8: Content
- Multiple dungeon types with themes
- Enemy variety and scaling
- Loot tables and equipment sets
- Node/skill variety expansion

### Phase 9: Polish
- Visual effects and animation
- Sound design
- Tutorial / onboarding
- Steam integration (achievements, cloud saves)
- Performance optimization and profiling
