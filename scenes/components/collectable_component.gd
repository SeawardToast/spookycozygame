class_name CollectableComponent

extends Area2D

@export var item_name: String
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		InventoryManager.add_item(item_name)
		print("Collected ", item_name)
		get_parent().queue_free()
