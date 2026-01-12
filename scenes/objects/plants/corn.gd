extends Node2D

var corn_harvest_scene: Resource = preload("res://scenes/objects/plants/corn_harvest.tscn")

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var flowering_particles: GPUParticles2D = $FloweringParticles
@onready var watering_particles: GPUParticles2D = $WateringParticles
@onready var growth_cycle_component: GrowCycleComponent = $GrowthCycleComponent
@onready var hurt_component: HurtComponent = $HurtComponent

var growth_state: DataTypes.GrowthStates = DataTypes.GrowthStates.Germination

func _ready() -> void:
	watering_particles.emitting = false
	flowering_particles.emitting = false
	
	hurt_component.hurt.connect(on_hurt)
	growth_cycle_component.crop_harvesting.connect(on_harvesting)
	
func _process(delta: float) -> void:
	growth_state = growth_cycle_component.get_current_growth_state()
	sprite_2d.frame = growth_state
	if growth_state == DataTypes.GrowthStates.Maturity:
		flowering_particles.emitting = true
	
func on_hurt(hit_damage: int) -> void:
	if !growth_cycle_component.is_watered:
		watering_particles.emitting = true
		await get_tree().create_timer(5.0).timeout
		watering_particles.emitting = false
		growth_cycle_component.is_watered = true
		
func on_crop_maturity() -> void:
	flowering_particles.emitting = true
	
func on_harvesting() -> void:
	call_deferred("add_corn_harvest_scene")
	queue_free()
	
func add_corn_harvest_scene() -> void:
	var corn_harvestable: Node2D = corn_harvest_scene.instantiate() as Node2D
	corn_harvestable.global_position = global_position
	get_parent().add_child(corn_harvestable)

	
	
