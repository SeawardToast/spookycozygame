extends Node

var item_data: Dictionary = {}

func _ready() -> void:
	item_data = load_data("res://resources/data/item_data.json") as Dictionary


func load_data(file_path: String) -> Variant:
	var json_data: Variant
	var file_data: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	var json_object: JSON = JSON.new()

	var err: int = json_object.parse(file_data.get_as_text())
	if err != OK:
		push_error("JSON parse error: %s (line %d)" % [
			json_object.get_error_message(), 
			json_object.get_error_line()
		])
		return null

	var object: Variant = json_object.get_data()
	return object
