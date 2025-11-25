extends StaticBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var interactable_component: InteractableComponent = $InteractableComponent
@onready var door_close_audio: AudioStreamPlayer2D = $door_close_audio
@onready var door_open_audio: AudioStreamPlayer2D = $door_open_audio

func _ready() -> void:
	interactable_component.interactable_activated.connect(on_interactable_activated)
	interactable_component.interactable_deactivated.connect(on_interactable_deactivated)
	collision_layer = 1
	
func on_interactable_activated() -> void:
	animated_sprite_2d.play("open_door")
	door_open_audio.play()
	collision_layer = 2
	print("activated")
	
func on_interactable_deactivated() -> void:
	animated_sprite_2d.play("close_door")
	door_close_audio.play()
	collision_layer = 1
	print("deactivated")
	
