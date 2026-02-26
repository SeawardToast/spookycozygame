# Rotation Validation Fix Options

## Problem

L-piece connects properly at rotation 0 from both sides, but after rotating, one connection fails validation.

## Root Cause (Suspected)

The piece's origin is at corner (0,0). After rotation:
- Parts extend in negative coordinates relative to origin
- Edge positions shift relative to where connectable tiles are
- Nav tile distribution on edges doesn't match after rotation

## Option 1: Relax Edge Validation (Allow Partial Overlap)

**Current behavior**: Edges must have EXACTLY matching nav tiles at same positions
**New behavior**: Edges must have AT LEAST SOME overlapping nav tiles

This would allow connections even if nav tile coverage isn't perfect.

### Implementation

Modify `_compare_edge_projections` to allow partial matches instead of requiring exact matches.

## Option 2: Fix Nav Tile Coverage

Ensure the piece has **symmetric nav tile coverage** on all edges so it works at all rotations.

### Steps:
1. Open hallway_L_inverted.tscn
2. Check Floor TileMapLayer
3. Ensure ALL floor tiles on ALL edges have navigation polygons
4. Make coverage symmetric so rotation doesn't change which tiles have nav

## Option 3: Adjust Piece Origin

Reposition the piece so its origin is at a point that makes sense for all rotations (e.g., center or consistent corner).

### Trade-offs:
- Requires redesigning the piece layout
- May affect other pieces if they're designed similarly
- Most work but most "correct" solution

## Recommended: Debug First, Then Fix

Before applying any fix:
1. Enable debug validation
2. Try placing in both rotations
3. Check console output to see exactly what's mismatching
4. Then apply the appropriate fix based on what we find

The debug output will show:
```
Projection comparison:
  Direction: (1, 0) (is_horizontal: false)
  Edge1 nav tiles: [(59, 12), (59, 13), ...]
  Edge2 nav tiles: [(58, 12), (58, 13), ...]
  Edge1 projections: [12, 13, 14, 15]
  Edge2 projections: [12, 13, 15, 16]  ← Mismatch here!
  ❌ MISMATCH: Position 3 differs (15 vs 16)
```

This will tell us whether it's:
- Missing nav tiles
- Off-by-one in coordinates
- Wrong axis projection
- Something else entirely
