class_name ScheduledNPC
extends CharacterBody2D

@export var npc_name: String = "NPC"
@export var speed: float = 100.0
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D

var daily_schedule: Array = []

var current_target_zone: Area2D = null
var current_actions: Array = []
var is_traveling: bool = false
var completed_schedule_entries: Array = [] # store references to entries we've executed
var current_schedule_entry: Dictionary = {}

signal arrived_at_zone(zone: Node)
signal action_attempted(action_name: String)
signal action_failed(action_name: String, reason: String)

# -------------------------------
# Ready
# -------------------------------
func _ready():
	DayAndNightCycleManager.time_tick.connect(_on_time_tick)
	randomize()
	navigation_agent_2d.target_desired_distance = 4.0

# -------------------------------
# Time tick
# -------------------------------
func _on_time_tick(day: int, hour: int, minute: int) -> void:
	var total_minute = hour * 60 + minute
	_check_schedule(total_minute)

func _check_schedule(current_minute: int) -> void:
	for entry in daily_schedule:
		if entry in completed_schedule_entries:
			continue

		var start_minute = entry.get("start_minute", 0)
		var end_minute = entry.get("end_minute", 0)
		if current_minute >= start_minute and current_minute < end_minute:
			var zone_name = entry.get("zone", "")
			var actions = entry.get("actions", [])
			if zone_name != "":
				_start_travel_to_zone(zone_name, actions, entry)
			elif actions:
				_attempt_actions(actions)
				completed_schedule_entries.append(entry)
			break

# -------------------------------
# Start travel
# -------------------------------
func _start_travel_to_zone(zone_name: String, actions: Array, entry: Dictionary):
	if current_target_zone != null and current_target_zone.get("zone") == zone_name:
		return

	var zone = null
	for area in ZoneManager.get_zones():
		if area.name == zone_name:
			zone = area
			break

	if zone == null:
		push_warning("Zone not found: %s" % zone_name)
		return
	current_target_zone = ZoneManager.create_area_from_zone_data(zone)
	#current_target_zone = zone.polygon
	current_actions = actions
	is_traveling = true
	current_schedule_entry = entry

	var door_or_random_point = _get_path_to_zone_via_door(current_target_zone)
	navigation_agent_2d.target_position = door_or_random_point

# -------------------------------
# Physics movement
# -------------------------------
func _physics_process(delta: float) -> void:
	if not is_traveling:
		return

	if navigation_agent_2d.is_navigation_finished():
		is_traveling = false
		_zone_arrival()
		return

	var next_pos = navigation_agent_2d.get_next_path_position()
	var direction = global_position.direction_to(next_pos)
	velocity = direction * speed
	if animated_sprite_2d:
		animated_sprite_2d.flip_h = velocity.x < 0
	move_and_slide()

# -------------------------------
# Arrive at zone
# -------------------------------
func _zone_arrival() -> void:
	print("arrived at zone")
	emit_signal("arrived_at_zone", current_target_zone)
	_attempt_actions(current_actions)

	if !current_schedule_entry.is_empty():
		completed_schedule_entries.append(current_schedule_entry)

	current_schedule_entry = {}
	current_target_zone = null
	current_actions = []

# -------------------------------
# Get path to zone through a door
# -------------------------------
func _get_path_to_zone_via_door(target_zone: Area2D) -> Vector2:
	# Already inside target zone?
	#if current_target_zone == target_zone:
		#return _get_random_point_in_area(target_zone)

	# Get all doors from the global "door" group
	var doors: Array = get_tree().get_nodes_in_group("door")
	var chosen_door: Node2D = null  # <-- explicitly typed

	for door in doors:
		#if door.is_open:
			# Each door should have zone_a and zone_b properties linking zones
		#if (door.zone_a == current_target_zone and door.zone_b == target_zone) \
		#or (door.zone_b == current_target_zone and door.zone_a == target_zone):
			chosen_door = door
			break

	if chosen_door != null:
		# Navigate to door first
		return chosen_door.global_position
	else:
		# No door found, fallback to random point inside target zone
		return _get_random_point_in_area(target_zone)


# -------------------------------
# Get random point inside Area2D
# -------------------------------
func _get_random_point_in_area(area: Area2D) -> Vector2:
	# Use CollisionPolygon2D child
	var poly_node := area.get_node_or_null("CollisionPolygon2D")
	if poly_node == null:
		return area.global_position

	var polygon: PackedVector2Array = poly_node.polygon
	if polygon.size() == 0:
		return area.global_position

	# Convert local polygon points to global coordinates
	var points: Array[Vector2] = []
	var xf: Transform2D = poly_node.global_transform
	for p in polygon:
		points.append(xf * p)  # Godot 4 uses '*' to transform Vector2 by Transform2D

	# Compute bounding box
	var min_x = points[0].x
	var max_x = points[0].x
	var min_y = points[0].y
	var max_y = points[0].y
	for pt in points:
		min_x = min(min_x, pt.x)
		max_x = max(max_x, pt.x)
		min_y = min(min_y, pt.y)
		max_y = max(max_y, pt.y)

	# Random point sampling
	for i in range(40):
		var random_point = Vector2(randf_range(min_x, max_x), randf_range(min_y, max_y))
		if Geometry2D.is_point_in_polygon(random_point, points):
			return random_point

	return points[0]  # fallback


# -------------------------------
# Attempt actions
# -------------------------------
func _attempt_actions(actions: Array = []):
	for action in actions:
		if typeof(action) == TYPE_CALLABLE:
			var result = action.call()
			var success = true
			var reason = ""
			if typeof(result) == TYPE_ARRAY and result.size() == 2:
				success = result[0]
				reason = result[1]
			elif typeof(result) == TYPE_BOOL:
				success = result
			if success:
				emit_signal("action_attempted", str(action))
			else:
				emit_signal("action_failed", str(action), reason)
