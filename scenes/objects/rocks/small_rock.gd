extends Sprite2D

@onready var hurt_component: HurtComponent = $HurtComponent
@onready var damage_component: DamageComponent = $DamageComponent

@onready var audio_players := [
	$AudioStreamPlayer2D,
	$AudioStreamPlayer2D2,
	$AudioStreamPlayer2D3,
	$AudioStreamPlayer2D4
]

@onready var audio_stream_player_2d_fell: AudioStreamPlayer2D = $AudioStreamPlayer2DFell

# Shader animation
var shader_mat: ShaderMaterial
var falling := false
var fall_progress := 0.0
var fall_speed := 0.5 # seconds to fully fall

func play_random_chop_sound() -> void:
	var player: Variant = audio_players.pick_random()
	player.play()

var rock_scene: Resource = preload("res://scenes/objects/rocks/rock_broken.tscn")

func _process(delta: float) -> void:
	if falling:
		fall_progress += fall_speed * delta
		fall_progress = clamp(fall_progress, 0.0, 1.0)
		shader_mat.set_shader_parameter("fall_progress", fall_progress)

func _ready() -> void:
	hurt_component.hurt.connect(on_hurt)
	damage_component.max_damage_reached.connect(on_max_damage_reached)
	
	# Duplicate material for per-instance shader
	shader_mat = material.duplicate() as ShaderMaterial
	material = shader_mat
	
func on_hurt(hit_damage: int) -> void:
	play_random_chop_sound()
	damage_component.apply_damage(hit_damage)
	shader_mat.set_shader_parameter("shake_intensity", 5.0)
	await get_tree().create_timer(1.0).timeout
	(material as ShaderMaterial).set_shader_parameter("shake_intensity", 0.0)

	
func on_max_damage_reached() -> void:
	audio_stream_player_2d_fell.play()
	falling = true
	shader_mat.set_shader_parameter("shake_intensity", 1.0)
	await audio_stream_player_2d_fell.finished	
	call_deferred("add_rock_scene")
	print("max damage reached")

	queue_free()
	
func add_rock_scene() -> void:
	var rock_instance: Node2D = rock_scene.instantiate() as Node2D
	rock_instance.global_position = global_position
	get_parent().add_child(rock_instance)
