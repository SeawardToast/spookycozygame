# camera_controller.gd
# Camera controller that follows the player while staying within tilemap bounds
extends Camera2D

@export var target: Node2D  # The player or entity to follow
@export var tilemap: TileMap  # Reference to the tilemap
@export var smoothing_enabled: bool = true
@export var smoothing_speed: float = 5.0

var map_limits: Rect2 = Rect2()
var half_viewport: Vector2 = Vector2.ZERO

# tilemap integration not setup yet
func _ready() -> void:
	# Get half the viewport size for boundary calculations
	_update_viewport_size()
	
	# Connect to viewport size changes
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	# Enable or disable smoothing
	position_smoothing_enabled = smoothing_enabled
	position_smoothing_speed = smoothing_speed
	
	# Try to calculate bounds if tilemap is already set
	if tilemap:
		_calculate_map_limits()

func _process(_delta: float) -> void:
	if not target:
		return
	
	# Get the target position
	var target_pos: Vector2 = target.global_position
	
	# Only clamp if we have valid map limits
	var clamped_pos: Vector2
	if map_limits.has_area():
		# Clamp the camera position to stay within map bounds
		clamped_pos = Vector2(
			clamp(target_pos.x, map_limits.position.x + half_viewport.x, map_limits.end.x - half_viewport.x),
			clamp(target_pos.y, map_limits.position.y + half_viewport.y, map_limits.end.y - half_viewport.y)
		)
	else:
		# No bounds set yet, just follow the target freely
		clamped_pos = target_pos
	
	# Update camera position (smoothing is handled automatically by Camera2D)
	global_position = clamped_pos

func _calculate_map_limits() -> void:
	if not tilemap:
		push_warning("CameraController: No tilemap assigned!")
		return
	
	var used_rect: Rect2i = tilemap.get_used_rect()
	var tile_size: Vector2i = tilemap.tile_set.tile_size
	
	# Convert tile coordinates to world coordinates
	var top_left: Vector2 = tilemap.map_to_local(used_rect.position)
	var bottom_right: Vector2 = tilemap.map_to_local(used_rect.position + used_rect.size)
	
	# Store the map limits as a Rect2
	map_limits = Rect2(top_left, bottom_right - top_left)
	
	print("Camera bounds set: ", map_limits)

func _update_viewport_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	half_viewport = (viewport_size / zoom) / 2.0

func _on_viewport_resized() -> void:
	_update_viewport_size()

## Call this if the tilemap changes during runtime
func recalculate_bounds() -> void:
	_calculate_map_limits()
	_update_viewport_size()

## Set a new target to follow
func set_target(new_target: Node2D) -> void:
	target = new_target

## Set a new tilemap and recalculate bounds
func set_tilemap(new_tilemap: TileMap) -> void:
	tilemap = new_tilemap
	_calculate_map_limits()

## Manually set camera limits (alternative to using tilemap)
func set_custom_limits(rect: Rect2) -> void:
	map_limits = rect
	print("Camera bounds manually set: ", map_limits)

## Get current camera bounds
func get_bounds() -> Rect2:
	return map_limits

## Check if camera is at a boundary
func is_at_left_edge() -> bool:
	return global_position.x <= map_limits.position.x + half_viewport.x

func is_at_right_edge() -> bool:
	return global_position.x >= map_limits.end.x - half_viewport.x

func is_at_top_edge() -> bool:
	return global_position.y <= map_limits.position.y + half_viewport.y

func is_at_bottom_edge() -> bool:
	return global_position.y >= map_limits.end.y - half_viewport.y
