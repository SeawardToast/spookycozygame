extends Area2D
class_name ZoneAutoRegister

@export var zone_name: String = ""
@export var zone_type: String = ""   # e.g. "bedroom", "kitchen", "spa"
@export var color: Color = Color.YELLOW  # optional, if your ZoneData uses it

var zone_data: Resource

func _ready() -> void:
	if not ZoneManager:
		push_error("ZoneManager is not autoloaded!")
		return

	# --- Validate ---
	if zone_name == "" or zone_type == "":
		push_warning("ZoneAutoRegister on '%s' is missing zone_name or zone_type" % name)
		return

	var collision_poly := get_node_or_null("CollisionPolygon2D")
	if collision_poly == null:
		push_warning("ZoneAutoRegister '%s' needs a CollisionPolygon2D child" % name)
		return

	if collision_poly.polygon.is_empty():
		push_warning("Zone '%s' polygon is empty" % zone_name)
		return

	# --- Create ZoneData resource ---
	zone_data = load("res://scripts/ZoneData.gd").new()
	zone_data.name = zone_name
	zone_data.type = zone_type
	zone_data.color = color
	zone_data.polygon = collision_poly.polygon
	zone_data.position = collision_poly.polygon[0]

	# --- Register with manager ---
	ZoneManager.register_zone(zone_data)
	print("✅ Registered zone:", zone_name, "as", zone_type)


func _exit_tree() -> void:
	if zone_data and ZoneManager:
		ZoneManager.remove_zone(zone_data)
		print("❎ Unregistered zone:", zone_name)
