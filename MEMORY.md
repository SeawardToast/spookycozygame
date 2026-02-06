# Memory

Persistent notes updated each session. Read this alongside CLAUDE.md.

---

## Current Focus

**Room System** - Implementing hotel rooms that attach perpendicular to hallways.

Recent work:
- Implemented `RoomManager` autoload for room registration, furniture scanning, guest assignment
- Rooms attach to hallway walls (not openings)
- Door erases hallway wall tile, room's door-side wall layer is hidden
- Quality calculated from furniture inside room bounds
- Guest assignment with check-in/check-out tracking

---

## Architecture Decisions

| Decision | Rationale | Date |
|----------|-----------|------|
| Per-floor NavigationServer2D maps | Complete isolation between floors, avoids cross-floor pathfinding bugs | Pre-existing |
| No rotation for construction pieces | Complexity vs benefit tradeoff - not worth the effort | Recent |
| Connectable tiles via TileMapLayer groups | Cleaner edge detection approach than previous method | Recent |
| Rooms attach to hallway walls | Traditional hotel layout - rooms perpendicular to corridors | 2026-02-05 |
| Room door erases hallway wall tile | Creates passage; tile data stored for restoration on delete | 2026-02-05 |
| Room's door_side_wall layer hidden on placement | Hallway walls stay visible as boundary; room has 4 walls for ghost preview | 2026-02-05 |
| Furniture scanning via signals | Room listens to piece_added/removed; no cross-contamination with furniture | 2026-02-05 |

---

## Known Issues / TODOs

- **Create room_dark_small.tscn** - Room scene needs to be created in Godot editor at `scenes/constructions/rooms/room_dark_small.tscn` with:
  - `GameTileMap/Floor` - 7x7 interior floor tiles
  - `GameTileMap/Walls` - 3 sides of walls (not door side)
  - `GameTileMap/door_side_wall` - Wall on door side (gets hidden on placement)
  - `GameTileMap/door_edge` - Single tile in `connectable_tiles` group
  - `DoorPosition` Marker2D - Center of door for NPC navigation
  - `RoomInterior` Area2D with CollisionPolygon2D - Interior bounds for furniture scanning
  - Attach script: `room_dark_small.gd` (already created)

---

## System Gotchas

### Build Mode
- Building pieces use `BuildingPieceRegistry` for definitions with caching
- Pieces have `connectable_tiles` TileMapLayer group for edge detection
- Two building types: `CONSTRUCTION` (hallways/rooms) vs `FURNITURE` (chests, beds)

### Floor Management
- Each floor must have `floor_number` metadata set
- Floors are loaded/unloaded dynamically for memory efficiency
- `FloorManager.wait_for_all_floors_ready()` is async - must await it

### NPC System
- NPCs use inner class `NPCSimulationState` for all state data
- Schedule-driven with `ScheduleEntry` time ranges
- Multi-floor navigation requires explicit floor change handling

### Inventory
- Player main inventory: 25 slots (5 columns)
- Player hotbar: 5 slots
- Chest inventories are dynamic, created on demand

### Input
- `GameInputEvents` is a static helper class - use it for all input checks
- Build mode has its own input set: `build_rotate_cw/ccw`, `build_place`, `build_delete`, `build_cancel`

### Room System
- `RoomManager` autoload manages all room state
- Room scenes need: `door_side_wall` layer (hidden on placement), `door_edge` layer (single tile in connectable_tiles), `DoorPosition` Marker2D
- **Door position is determined by the `door_edge` layer in the scene** - not hardcoded in registry
- Room validation: door must be on top of hallway wall tile (checks Walls TileMapLayer directly)
- `PlacedRoom` stores covered hallway wall tile data for restoration
- `hallway_id` format: `piece_id_x_y` e.g. `hallway_straight_10_20`
- Hallway deletion blocked if `RoomManager.has_attached_rooms()` returns true
- Quality = sum of `FURNITURE_QUALITY` values for furniture in room cells
- Room scene needs `hide_door_side_wall()`, `get_door_world_position()`, `get_interior_cells()` methods

---

## What Didn't Work

| Approach | Problem | Better Solution |
|----------|---------|-----------------|
| Rotation for construction pieces | Too complex for the benefit | Removed - use fixed orientations with variants (hallway_L, hallway_L_inverted) |
| Openings-based room validation | Incorrectly filtered valid wall positions | Removed - just check for wall tile in Walls TileMapLayer |
| Including door layers in cell calculation | door_side_wall/door_edge caused false overlap with hallway | Skip these layers in _get_tilemap_cells_from_instance |

---

## Session Log

### 2026-02-05
- Created CLAUDE.md with coding guidelines and project overview
- Created MEMORY.md for persistent session notes
- Explored full codebase architecture
- Confirmed: Godot 4.5, 18 autoloads, state machine pattern, component-based design
- **Implemented Room System:**
  - Added `RoomType` enum to DataTypes
  - Created `PlacedRoom` and `GuestAssignment` classes
  - Created `RoomManager` autoload (19th autoload)
  - Added room validation to `BuildingLayoutData._validate_room_placement()`
  - Integrated room placement in `PlacementSystem`
  - Registered `room_dark_small` in `BuildingPieceRegistry`
  - Created `room_dark_small.gd` script
  - **TODO:** Create `room_dark_small.tscn` scene manually in Godot editor (attach the script)
