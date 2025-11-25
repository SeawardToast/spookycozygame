class_name CropsCursorComponent
extends Node


@export var tilled_soil_tilemap_layer: TileMapLayer
@export var terrain_set: int = 0
@export var terrain: int = 3

@onready var player: Player = get_tree().get_first_node_in_group("player")

var mouse_position: Vector2
var cell_position: Vector2i
var cell_source_id: int
var local_cell_position: Vector2
var distance: float

var corn_plant_scene = preload("res://scenes/objects/plants/corn.tscn")
var tomato_plant_scene = preload("res://scenes/objects/plants/tomato.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("remove_dirt") and ToolManager.selected_tool == DataTypes.Tools.TillGround:
		get_cell_under_mouse()
		remove_crop()
		
	if event.is_action_pressed("hit") and ToolManager.selected_tool == DataTypes.Tools.PlantCorn:
		get_cell_under_mouse()
		add_corn_crop()
		
	elif event.is_action_pressed("hit") and ToolManager.selected_tool == DataTypes.Tools.PlantTomato:
		get_cell_under_mouse()
		add_tomato_crop()

func get_cell_under_mouse() -> void:
	mouse_position = tilled_soil_tilemap_layer.get_local_mouse_position()
	cell_position = tilled_soil_tilemap_layer.local_to_map(mouse_position)
	cell_source_id = tilled_soil_tilemap_layer.get_cell_source_id(cell_position)
	local_cell_position = tilled_soil_tilemap_layer.map_to_local(cell_position)
	distance = player.global_position.distance_to(local_cell_position)
	
	print("mouse position: ", mouse_position, "cell position: ", cell_position, "cell_source_id: ", cell_source_id)
	print('distance', distance)
	
func add_tomato_crop() -> void:
	if distance < 20.0 && cell_source_id == 6:
		var tomato_instance = tomato_plant_scene.instantiate() as Node2D
		tomato_instance.global_position = local_cell_position
		get_parent().find_child("CropFields").add_child(tomato_instance)

func add_corn_crop() -> void: # 
	if distance < 20.0 && cell_source_id == 6:
		var corn_instance = corn_plant_scene.instantiate() as Node2D
		corn_instance.global_position = local_cell_position
		get_parent().find_child("CropFields").add_child(corn_instance)
		
func remove_crop() -> void: 
	print("remove crop")
	if distance < 20.0:
		var crop_nodes = get_parent().find_child("CropFields").get_children()
		
		for node: Node2D in crop_nodes:
			if node.global_position == local_cell_position:
				node.queue_free()
