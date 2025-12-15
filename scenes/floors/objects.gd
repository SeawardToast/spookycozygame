extends TileMapLayer
@onready var objects: TileMapLayer = $"."

func _use_tile_data_runtime_update(coords: Vector2i) -> bool:
	# Convert this layer's coords into the object layer's coords
	var obj_coords: Vector2i = objects.local_to_map(map_to_local(coords))
	
	# If a fence exists at these coordinates, enable runtime update
	return obj_coords in objects.get_used_cells_by_id(0)


func _tile_data_runtime_update(coords: Vector2i, tile_data: TileData) -> void:
	var obj_coords: Vector2i = objects.local_to_map(map_to_local(coords))
	
	if obj_coords in objects.get_used_cells_by_id(0):
		# Disable navigation slot 0 (your nav layer)
		tile_data.set_navigation_enabled(0, false)
		
func _ready() -> void:
	for coords in get_used_cells():
		var obstacle: NavigationObstacle2D = NavigationObstacle2D.new()
		obstacle.position = map_to_local(coords)
		obstacle.avoidance_enabled = true        # instead of obstacle_mask
		obstacle.radius = 16                 # or whatever size your fence tile is
		add_child(obstacle)
