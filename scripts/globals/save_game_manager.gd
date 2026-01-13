extends Node

var allow_save_game: bool

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game()

func save_game() -> void:
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	InventoryManager.save_inventory()
	DayAndNightCycleManager.save_time()
	NPCSimulationManager.save_npcs()
	if save_level_data_component != null:
		save_level_data_component.save_game()
	print("Game saved")

func load_game() -> void:
	await get_tree().process_frame
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	InventoryManager.load_inventory()
	DayAndNightCycleManager.load_time()
	NPCSimulationManager.load_npcs()
	if save_level_data_component != null:
		save_level_data_component.load_game()
		
func reset_game() -> void:
	await get_tree().process_frame
	var save_level_data_component: SaveLevelDataComponent = get_tree().get_first_node_in_group("save_level_data_component")
	InventoryManager.reset_inventory()
	DayAndNightCycleManager.reset_time()
	NPCSimulationManager.reset_npcs()
	if save_level_data_component != null:
		save_level_data_component.load_game()
