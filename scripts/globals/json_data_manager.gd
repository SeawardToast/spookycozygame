extends Node

var item_data: Dictionary

func _ready() -> void:
	item_data = load_data("res://resources/data/item_data.json")
	
func load_data(file_path: String):
	var json_data
	var file_data = FileAccess.open(file_path, FileAccess.READ)
	var json_object = JSON.new()
	var err = json_object.parse(file_data.get_as_text())
	if err != OK:
		push_error("JSON parse error: %s (line %d)" % [json_object.get_error_message(), json_object.get_error_line()])
		return null
	
	var object = json_object.get_data()
	return object
