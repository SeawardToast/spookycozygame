class_name ScheduledNPC
extends CharacterBody2D

@export var npc_name: String = "NPC"
@export var speed: float = 100.0
@export var animated_sprite_2d: AnimatedSprite2D
@export var navigation_agent_2d: NavigationAgent2D

var daily_schedule: Array = []

var current_target_zone: NavigationRegion2D = null
var current_actions: Array = []
var is_traveling: bool = false
var completed_schedule_entries: Array = []  # store references to entries we've executed
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
		# Skip if already completed
		if entry in completed_schedule_entries:
			continue

		var start_minute = entry.get("start_minute", 0)
		var end_minute = entry.get("end_minute", 0)
		if current_minute >= start_minute and current_minute < end_minute:
			var zone = entry.get("zone", null)
			var actions = entry.get("actions", [])
			if zone:
				_start_travel_to_zone(zone, actions, entry)
			elif actions:
				_attempt_actions(actions)
				completed_schedule_entries.append(entry)
			break

func _start_travel_to_zone(zone: NavigationRegion2D, actions: Array, entry: Dictionary):
	if current_target_zone == zone:
		return
	current_target_zone = zone
	current_actions = actions
	is_traveling = true

	# Store the entry so we can mark it completed on arrival
	current_schedule_entry = entry

	var random_point = _get_random_point_in_region(zone)
	navigation_agent_2d.target_position = random_point


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

	# Move toward next navigation path point
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
	emit_signal("arrived_at_zone", current_target_zone)
	_attempt_actions(current_actions)

	# Mark schedule entry as done
	if !current_schedule_entry.is_empty():
		completed_schedule_entries.append(current_schedule_entry)
		current_schedule_entry = {}

	current_target_zone = null
	current_actions = []


func _get_random_point_in_region(region: NavigationRegion2D) -> Vector2:
	var nav_map = region.get_navigation_map()
	if region == null or region.navigation_polygon == null:
		return global_position  # fallback

	var poly = region.navigation_polygon
	var indices: PackedInt32Array = poly.get_polygon(0)
	if indices.size() == 0:
		return global_position

	# Build actual polygon points
	var polygon_points: Array = []
	for idx in indices:
		polygon_points.append(poly.vertices[idx])

	# Compute bounding box manually
	var min_x = polygon_points[0].x
	var max_x = polygon_points[0].x
	var min_y = polygon_points[0].y
	var max_y = polygon_points[0].y

	for p in polygon_points:
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		min_y = min(min_y, p.y)
		max_y = max(max_y, p.y)

	# Try random points inside the bounding box
	for i in range(20):
		var point = Vector2(
			randf_range(min_x, max_x),
			randf_range(min_y, max_y)
		)
		if Geometry2D.is_point_in_polygon(point, polygon_points):
			return NavigationServer2D.map_get_closest_point(nav_map, point)

	# fallback
	return NavigationServer2D.map_get_closest_point(nav_map, Vector2(min_x, min_y))



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
