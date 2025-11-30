extends Node
# Autoload this as ZoneManager

var zones: Array[Resource] = []     # Still keep the raw ZoneData resources
var zone_registry: Dictionary = {}  # zone_id -> metadata
var next_zone_id: int = 1           # Or use UUIDs if you prefer


# =====================================================================
#  ZONE REGISTRATION
# =====================================================================

func register_zone(zone_data: Resource) -> int:
	#"""
	#Registers the ZoneData, assigns a unique ID, creates an Area2D,
	#and stores everything in zone_registry.
	#Returns the zone_id.
	#"""

	if not zone_data:
		push_warning("ZoneManager: Tried to register a null ZoneData")
		return -1

	# ---- Create Unique ID ----
	var zone_id: int = next_zone_id
	next_zone_id += 1

	# Store the ID inside the ZoneData (runtime only, safe)
	zone_data.id = zone_id

	zones.append(zone_data)

	# Create Area2D instance
	var area := create_area_from_zone_data(zone_data)

	# Populate registry record
	zone_registry[zone_id] = {
		"data": zone_data,
		"floor": zone_data.floor,
		"polygon": zone_data.polygon,
		"area": area,
		"position": area.global_position
	}

	print("ZoneManager: Registered zone_id %d ('%s') on floor %d"
		  % [zone_id, zone_data.name, zone_data.floor])

	return zone_id


func unregister_zone(zone_id: int):
	if zone_id not in zone_registry:
		return

	var zone_data: Resource = zone_registry[zone_id]["data"]
	zones.erase(zone_data)

	var area = zone_registry[zone_id]["area"]
	if area and area.is_inside_tree():
		area.queue_free()

	zone_registry.erase(zone_id)
	print("ZoneManager: Unregistered zone %d" % zone_id)


func clear_zones():
	for id in zone_registry:
		var area = zone_registry[id]["area"]
		if area and area.is_inside_tree():
			area.queue_free()

	zones.clear()
	zone_registry.clear()
	next_zone_id = 1
	
func get_closest_zone_of_type_from_position(zone_type: String, from_position: Vector2) -> int:
	#"""
	#Returns the zone_id of the closest zone of the given type.
	#Returns -1 if no matching zone exists.
	#"""

	var closest_zone_id := -1
	var closest_distance := INF

	for zone_id in zone_registry:
		var meta = zone_registry[zone_id]
		var zd: Resource = meta["data"]

		# Filter by type
		if zd.type != zone_type:
			continue

		# Distance check
		var pos: Vector2 = meta["position"]
		var dist := from_position.distance_squared_to(pos) # faster

		if dist < closest_distance:
			closest_distance = dist
			closest_zone_id = zone_id

	return closest_zone_id



# =====================================================================
#  AREA CREATION
# =====================================================================

func create_area_from_zone_data(zone_data: Resource) -> Area2D:
	var poly: PackedVector2Array = zone_data.polygon

	if poly.is_empty():
		push_warning("ZoneData '%s' has empty polygon!" % zone_data.name)
		return null

	var area := Area2D.new()
	area.name = zone_data.name

	# ---- Compute centroid ----
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= poly.size()

	area.global_position = centroid

	# ---- Collision ----
	var collision := CollisionPolygon2D.new()
	var local_poly := PackedVector2Array()

	for p in poly:
		local_poly.append(p - centroid)

	collision.polygon = local_poly
	area.add_child(collision)

	area.monitoring = true
	area.collision_layer = 1
	area.collision_mask = 1

	get_tree().current_scene.add_child(area)
	return area


# =====================================================================
#  GETTERS (ALL USE zone_id)
# =====================================================================

func get_zone_data(zone_id: int) -> Resource:
	return zone_registry.get(zone_id, {}).get("data")


func get_zone_floor(zone_id: int) -> int:
	if zone_id in zone_registry:
		return zone_registry[zone_id]["floor"]
	return -1

func get_zone_area(zone_id: int) -> Area2D:
	if zone_id in zone_registry:
		return zone_registry[zone_id]["area"]
	return null

func get_zone_position(zone_id: int) -> Vector2:
	if zone_id in zone_registry:
		return zone_registry[zone_id]["position"]
	return Vector2.ZERO


func is_zone_loaded(zone_id: int) -> bool:
	if zone_id not in zone_registry:
		return false

	var fl = zone_registry[zone_id]["floor"]
	var floor_data = FloorManager.get_floor_data(fl)

	return floor_data and floor_data.is_loaded


func get_all_zones_on_floor(floor_number: int) -> Array[int]:
	var out := []
	for zone_id in zone_registry:
		if zone_registry[zone_id]["floor"] == floor_number:
			out.append(zone_id)
	return out


func get_zones_by_type(zone_type: String) -> Array[int]:
	var out := []
	for zone_id in zone_registry:
		var zd = zone_registry[zone_id]["data"]
		if zd.zone_type == zone_type:
			out.append(zone_id)
	return out


func get_all_zone_ids() -> Array[int]:
	return zone_registry.keys()
