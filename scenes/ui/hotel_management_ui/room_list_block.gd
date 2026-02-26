class_name RoomListBlock
extends PanelContainer

@onready var _room_label: Label = $MarginContainer/VBoxContainer/Label
@onready var _quality_label: Label = $MarginContainer/VBoxContainer/HBoxContainer/RoomQualityLabel

var instance_id: String


func setup(room: PlacedRoom) -> void:
	instance_id = room.instance_id
	_room_label.text = room.instance_id
	_quality_label.text = str(room.current_quality)


func update_quality(new_quality: int) -> void:
	_quality_label.text = str(new_quality)
