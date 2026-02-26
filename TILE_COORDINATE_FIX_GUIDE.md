# L-Piece Placement Issue: Tile Coordinate Fix Guide

## The Problem

Your L-shaped and inverted L-shaped hallway pieces have **negative local tile coordinates**, which causes "off by one" placement validation issues when rotating the pieces.

### Why This Happens

When you create a TileMapLayer scene in Godot, tiles can have negative local coordinates (e.g., x: -3, -2, -1, 0). This is fine for static scenes, but causes problems for rotatable building pieces because:

1. **Rotation transforms apply to coordinates**: When rotating 90°, the formula is `new_pos = Vector2i(-y, x)`. Negative coordinates produce unexpected results.
2. **Origin point confusion**: The placement system assumes the piece's origin (0,0) is at the top-left of the occupied cells, but negative coordinates mean cells extend to the left or above the origin.

### Example of the Issue

**Inverted L with negative coordinates:**
```
Local coordinates: [(-3,0), (-2,0), (-1,0), (0,0), (0,1), (0,2), (0,3)]
                    └─ extends 3 cells LEFT of origin

When placed at grid (5,5):
Expected global: [(2,5), (3,5), (4,5), (5,5), (5,6), (5,7), (5,8)]
Actual (buggy):  varies by rotation due to negative coord math
```

**Inverted L with positive coordinates (correct):**
```
Local coordinates: [(0,0), (1,0), (2,0), (3,0), (0,1), (0,2), (0,3)]
                    └─ all cells at (0,0) or positive offsets

When placed at grid (5,5):
Correct global:    [(5,5), (6,5), (7,5), (8,5), (5,6), (5,7), (5,8)]
Rotations work:    ✓ All rotations calculated correctly
```

## The Solution

**All tiles in your piece scenes must have local coordinates starting from (0,0) with no negative values.**

## How to Fix in Godot Editor

### Method 1: Manual Repositioning (Recommended for understanding)

1. **Open the problematic scene** (e.g., `hallway_L_inverted.tscn`)
2. **Select the TileMapLayer node** (Floor or Walls)
3. **View current tiles**: Look at the TileMap editor
4. **Identify the offset needed**:
   - If tiles are at x: [-3, -2, -1, 0], you need to shift +3 in x
   - If tiles are at y: [-2, -1, 0, 1], you need to shift +2 in y
5. **Select all tiles**: Ctrl+A in TileMap editing mode
6. **Cut tiles**: Ctrl+X
7. **Click at the new origin (0,0)** in the TileMap grid
8. **Paste**: Ctrl+V
9. **Reposition manually** if needed to ensure all coordinates ≥ 0

### Method 2: Using Transform Position (Quick but affects scene hierarchy)

1. Open the scene
2. Select the **parent Node2D** containing the TileMapLayers
3. Note the TileMap's position offset
4. Select each TileMapLayer
5. In the Inspector, modify `Transform → Position` to shift tiles
   - Example: If tiles have x: [-3 to 0], set Position.x = 48 (3 cells × 16 pixels)

⚠️ **Important**: This shifts the visual position but doesn't change tile coordinates. You may need to adjust the root node's position compensation.

### Method 3: Using the Debug Script

1. **Add a Node to any test scene**
2. **Attach the debug script**: [debug_piece_cells.gd](scripts/debug/debug_piece_cells.gd)
3. **Set the piece_scene_path** in the Inspector to your L piece scene
4. **Run the scene** and check the console output
5. Look for the warning: "⚠️ WARNING: Negative coordinates detected!"
6. The script shows you exactly which coordinates need fixing

Example output:
```
=== DEBUG PIECE CELLS ===
Scene: res://scenes/buildings/hallway_L_inverted.tscn
Rotation: 0 (0 degrees)

Local cells (before rotation transform):
  Count: 7
    (-3, 0)
    (-2, 0)
    (-1, 0)
    (0, 0)
    (0, 1)
    (0, 2)
    (0, 3)

Bounds:
  X: [-3 to 0] (width: 4)
  Y: [0 to 3] (height: 4)

⚠️  WARNING: Negative coordinates detected!
   This will cause placement issues.
   All tiles should start from (0, 0) or positive coordinates.
```

This tells you that you need to shift all tiles +3 in the x-direction.

## Verification Steps

After fixing your scenes:

1. Run the debug script again - should show no negative coordinates
2. Test in build mode:
   - Place the piece at rotation 0°
   - Rotate and place at 90°, 180°, 270°
   - Verify all rotations align correctly to the grid
3. Check validation:
   - Ghost should turn green when correctly aligned
   - Should be able to place without "off by one" errors

## Which Files Need Fixing

Based on the BuildingPieceRegistry:
- ✅ `hallway_straight.tscn` - Likely correct (single cell)
- ⚠️ `hallway_L.tscn` - Check with debug script
- ⚠️ `hallway_L_inverted.tscn` - **Definitely has negative coords** (user confirmed)
- ⚠️ Any future multi-cell pieces

## Common Pitfall: "But I don't know how to shift without changing position"

**The Issue**: Moving tiles in the TileMap editor changes their local coordinates, but then the whole piece appears in a different position in the game world.

**The Solution**: After fixing tile coordinates, compensate by adjusting the scene's root Node2D position:

Example:
- Original: Tiles at x: [-3, -2, -1, 0], root at position (0, 0)
- After fix: Tiles at x: [0, 1, 2, 3], root at position (-48, 0) to compensate
  - (48 pixels = 3 cells × 16 pixels/cell)

This way:
- ✅ Tiles have correct local coordinates for rotation math
- ✅ Visual appearance in Godot editor stays the same
- ✅ Placement and rotation work correctly

## Technical Details (For Understanding)

The rotation transformation used is:
```gdscript
match rotation:
    0:  rotated = Vector2i(x, y)           # No rotation
    1:  rotated = Vector2i(-y, x)          # 90° CW
    2:  rotated = Vector2i(-x, -y)         # 180°
    3:  rotated = Vector2i(y, -x)          # 270° CW
```

With negative coordinates:
- Rotation 1: `(-y, x)` where `y < 0` → first component becomes positive (wrong!)
- Rotation 2: `(-x, -y)` where `x < 0` → first component becomes positive (wrong!)

This breaks the assumption that rotating a piece keeps all cells in a predictable pattern relative to the origin.

## Need Help?

Run the debug script and share the output. The script will show:
1. All local coordinates
2. The bounds (min/max x and y)
3. Warnings for negative coordinates
4. How the coordinates transform when rotated
