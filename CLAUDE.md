# Spooky Cozy Game

A cozy hotel management sim built in Godot 4.5 where you run a hotel for supernatural guests (ghosts, vampires, werewolves, etc.).

> **Read [MEMORY.md](MEMORY.md)** - Contains current work-in-progress, known issues, architecture decisions, and session notes. Keep it updated each session.

## Current Development Focus

**Build mode system** - Completing the construction and piece placement functionality.

## Code Principles (Non-Negotiables)

- **DRY** - Do not duplicate code. Extract shared logic into reusable functions or components.
- **Simplicity** - Keep code concise and readable. Value conciseness over verbosity, but never sacrifice readability.
- **Self-documenting code** - Avoid excessive comments. Code should be clear through good naming and structure. Only comment non-obvious logic.
- **Modular & extendable** - Design systems to be reusable and easy to extend.
- **Static typing** - Always use static types. Ask if unsure about a type.

## GDScript Conventions

### File Structure (Godot Style Guide)
```gdscript
class_name ClassName
extends ParentClass

signal something_happened

enum State { IDLE, ACTIVE }

const CONSTANT := 10

@export var exported_var: int
var public_var: String
var _private_var: float

@onready var _sprite := $AnimatedSprite2D

func _ready() -> void:
    pass

func _process(delta: float) -> void:
    pass

func public_method() -> void:
    pass

func _private_method() -> void:
    pass
```

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Signals | Past tense | `chest_opened`, `item_picked_up`, `floor_changed` |
| Private members | Underscore prefix | `_internal_state`, `_calculate_path()` |
| Constants | SCREAMING_SNAKE | `GRID_SIZE`, `MAX_SLOTS` |
| Classes | PascalCase | `NPCSimulationManager`, `BuildingPieceRegistry` |
| Functions/vars | snake_case | `get_current_floor()`, `player_position` |
| Managers | Manager suffix | `FloorManager`, `InventoryManager` |
| States | State suffix | `IdleState`, `WalkState` |
| Components | Component suffix | `HitComponent`, `InteractableComponent` |

### Node References

- Use `@onready` for internal child nodes: `@onready var _sprite := $Sprite2D`
- Use `@export` for injected dependencies: `@export var target_node: Node2D`

### Constants

- Local to file if used only there
- Centralized in globals/config if shared across systems

## Architecture

### Key Systems

| System | Location | Purpose |
|--------|----------|---------|
| State Machines | `scripts/state_machine/` | Player & NPC behavior via `NodeState`/`NodeStateMachine` |
| NPC Simulation | `scripts/npc/` | Schedule-driven NPCs with pathfinding |
| Floor Management | `scripts/globals/floor_manager.gd` | Multi-floor navigation with per-floor NavServer2D maps |
| Build Mode | `scripts/globals/build_*` | Piece placement, validation, persistence |
| Inventory | `scripts/globals/inventory_manager.gd` | Slot-based items with drag-drop |
| Signals | `scripts/globals/signal_bus.gd` | Decoupled game events |

### Autoloads (18 singletons)

Core managers are autoloaded. Before creating new autoloads, discuss whether it should be a singleton or scene component.

### Component Pattern

Reusable behaviors in `scenes/components/`. Attach to scenes for composition over inheritance.

## Error Handling

Mix based on severity:
- **Critical issues**: Use `assert()` to catch during development
- **Recoverable issues**: `push_warning()` / `push_error()` and continue gracefully
- **Expected edge cases**: Explicit `if` checks with early returns

## Testing

- Manual playtesting
- Strategic print statements and debug flags
- Debug functions in managers (e.g., `debug_npc()`, `debug_navigation_state()`)

## Project Structure

```
scripts/
├── globals/          # Autoload singletons (18)
├── state_machine/    # State machine base classes
├── npc/              # NPC simulation, behavior, scheduling
├── definitions/      # Data structures (Item, Floor, etc.)
└── [camera, debug, navigation, scene_helpers]

scenes/
├── characters/       # Player & NPCs with state machines
├── components/       # Reusable logic components
├── buildings/        # Building pieces (hallways, rooms)
├── objects/          # Interactables (trees, chests, doors)
├── floors/           # Floor1.tscn, Floor2.tscn, Floor3.tscn
├── ui/               # Inventory, HUD, menus
└── test/             # Test scenes

resources/            # Custom .tres definitions
tilesets/             # 16px tile definitions
addons/               # Dialogue Manager plugin (do not modify)
```

## Quick Reference

- **Grid size**: 16px tiles
- **Viewport**: 853x480 (2x scaled to 1706x960)
- **Input helper**: `GameInputEvents` static class
- **Game events**: Emit through `SignalBus`
- **Save/Load**: Orchestrated by `SaveGameManager`, each system handles its own data
