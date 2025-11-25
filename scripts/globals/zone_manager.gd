extends Node
# Make this autoload singleton: ZoneManager

var zones: Array[Resource] = []

func add_zone(zone_data: Resource):
	zones.append(zone_data)

func remove_zone(zone_data: Resource):
	if zone_data in zones:
		zones.erase(zone_data)

func get_zones_by_type(zone_type: String) -> Array[Resource]:
	var result: Array[Resource] = []
	for z in zones:
		if z.zone_type == zone_type:
			result.append(z)
	return result
	
func get_zones() -> Array[Resource]:
	return zones

func clear_zones():
	zones.clear()
	
func create_area_from_zone_data(zone_data: Resource) -> Area2D:
	var area := Area2D.new()
	area.name = zone_data.name

	# ✅ Explicit type so Godot won't complain
	var poly: PackedVector2Array = zone_data.polygon

	if poly.is_empty():
		push_warning("ZoneData has no polygon!")
		return null

	# ---- Compute centroid ----
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= poly.size()

	area.global_position = centroid

	# ---- Collision polygon ----
	var collision := CollisionPolygon2D.new()
	var local_poly := PackedVector2Array()

	for p in poly:
		local_poly.append(p - centroid)

	collision.polygon = local_poly
	area.add_child(collision)

	area.monitoring = true
	area.collision_layer = 1
	area.collision_mask = 1

	# ---- Optional visual ----
	#var visual := Polygon2D.new()
	#visual.polygon = local_poly
	#visual.color = zone_data.color
	#area.add_child(visual)

	get_tree().current_scene.add_child(area)

	return area
