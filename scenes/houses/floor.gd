extends TileMapLayer

@onready var walls: TileMapLayer = $"../Walls"
@onready var furniture: TileMapLayer = $"../Furniture"

func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	if coords in walls.get_used_cells_by_id(0) or coords in furniture.get_used_cells_by_id(0):
		return true
	return false
	
func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	if coords in walls.get_used_cells_by_id(0) or coords in furniture.get_used_cells_by_id(0):
		tile_data.set_navigation_polygon(0, null)
