# NPCTypeRegistry.gd
# Central registry for all available NPC types
# Add as autoload singleton
extends Node

# Registry of NPC type definitions
var npc_types: Dictionary = {}

func _ready() -> void:
	_register_default_types()

func _register_default_types() -> void:
	register_type("ghost", Ghost)
	register_type("vampire", Vampire)


func register_type(type_name: String, definition_class: Variant) -> void:
	npc_types[type_name] = definition_class


func create_npc_definition(type_name: String) -> Variant:
	if not npc_types.has(type_name):
		push_error("NPC type not registered: %s" % type_name)
		return null
	var definition_class: Variant = npc_types[type_name]
	return definition_class.new()


func get_all_types() -> Array:
	return npc_types.keys()


func get_random_type() -> String:
	var types: Array = get_all_types()
	if types.is_empty():
		return ""
	return types[randi() % types.size()]


func has_type(type_name: String) -> bool:
	return npc_types.has(type_name)
