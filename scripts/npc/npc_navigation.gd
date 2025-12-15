# npc_navigation.gd
# Handles pathfinding and multi-step navigation for NPCs
class_name NPCNavigation
extends RefCounted

var path: Array[NavWaypoint] = []
var current_waypoint_index: int = 0
var owner_npc: NPCSimulationManager.NPCSimulationState

##
## Waypoint class
##
class NavWaypoint:
	var position: Vector2
	var type: String              # "zone", "stairs_up", "stairs_down"
	var floor: int
	var metadata: Dictionary

	func _init(
		pos: Vector2 = Vector2.ZERO,
		waypoint_type: String = "",
		on_floor: int = 1,
		meta: Dictionary = {}
	) -> void:
		position = pos
		type = waypoint_type
		floor = on_floor
		metadata = meta


func _init(npc: NPCSimulationManager.NPCSimulationState = null) -> void:
	owner_npc = npc


##
## Route planning
##
func set_destination(zone_name: String, target_floor: int, zone_manager: Node) -> bool:
	clear_path()

	if owner_npc == null:
		push_error("Navigation has no owner NPC")
		return false

	var current_floor: int = owner_npc.current_floor

	# Add stair transitions
	if target_floor != current_floor:
		if not _add_floor_transitions(current_floor, target_floor):
			return false

	# Final destination
	var zone_pos: Vector2 = _get_zone_position(zone_name, target_floor, zone_manager)
	if zone_pos == Vector2.ZERO:
		push_warning("Could not find position for zone: %s" % zone_name)
		return false

	var final_waypoint: NavWaypoint = NavWaypoint.new(
		zone_pos,
		"zone",
		target_floor,
		{"zone_name": zone_name}
	)
	path.append(final_waypoint)

	return true


##
## Add floors/stair transitions
##
func _add_floor_transitions(from_floor: int, to_floor: int) -> bool:
	var current: int = from_floor
	var direction: int = 1 if to_floor > from_floor else -1
	var dir_string: String = "up" if direction > 0 else "down"

	while current != to_floor:
		var stairs_pos: Vector2 = _find_stairs_position(current, dir_string)
		if stairs_pos == Vector2.ZERO:
			push_error("No stairs found on floor %d going %s" % [current, dir_string])
			return false

		var waypoint: NavWaypoint = NavWaypoint.new(
			stairs_pos,
			"stairs_" + dir_string,
			current,
			{
				"target_floor": current + direction,
				"direction": dir_string
			}
		)
		path.append(waypoint)

		current += direction

	return true


##
## Find stair position on a floor
##
func _find_stairs_position(floor: int, direction: String) -> Vector2:
	var stairs: Array = Engine.get_main_loop().root.get_tree().get_nodes_in_group("stairs")
	for stairset: Node in stairs:
		# Assumes "floor" and "direction" properties exist
		if stairset.floor == floor and stairset.direction == direction:
			return stairset.global_position
	return Vector2.ZERO


##
## Get position of a zone
##
func _get_zone_position(zone_name: String, floor: int, zone_manager: Node) -> Vector2:
	if not is_instance_valid(zone_manager):
		return Vector2.ZERO

	var closest_zone_id: int = zone_manager.get_closest_zone_of_type_from_position(
		zone_name,
		owner_npc.current_position
	)

	var zone_data: ZoneData = zone_manager.get_zone_data(closest_zone_id)
	if zone_data == null:
		return Vector2.ZERO

	# A real zone area (floor present)
	var zone_area: Area2D = zone_manager.get_zone_area(closest_zone_id)
	if zone_area:
		return _get_random_point_in_zone(zone_area)

	# Fallback to stored registry position
	return zone_data.position


##
## Random point within polygon area of a zone
##
func _get_random_point_in_zone(area: Area2D) -> Vector2:
	var poly_node: CollisionPolygon2D = area.get_node_or_null("CollisionPolygon2D")
	if poly_node == null:
		return area.global_position

	var polygon: PackedVector2Array = poly_node.polygon
	if polygon.size() == 0:
		return area.global_position

	var points: Array[Vector2] = []
	var xf: Transform2D = poly_node.global_transform
	for p: Vector2 in polygon:
		points.append(xf * p)

	# AABB bounds
	var min_x: float = points[0].x
	var max_x: float = points[0].x
	var min_y: float = points[0].y
	var max_y: float = points[0].y

	for pt: Vector2 in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)

	# Try random points
	for i: int in range(40):
		var random_point: Vector2 = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)
		if Geometry2D.is_point_in_polygon(random_point, points):
			return random_point

	# Fallback
	return points[0]


##
## Waypoint helpers
##
func get_current_waypoint() -> NavWaypoint:
	if current_waypoint_index < path.size():
		return path[current_waypoint_index]
	return null


func advance_waypoint() -> bool:
	current_waypoint_index += 1
	return has_more_waypoints()


func has_more_waypoints() -> bool:
	return current_waypoint_index < path.size()


func is_complete() -> bool:
	return current_waypoint_index >= path.size()


func clear_path() -> void:
	path.clear()
	current_waypoint_index = 0


func get_waypoint_count() -> int:
	return path.size()
