extends Node

var game_menu_screen: Resource = preload("res://scenes/ui/game_menu_screen.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("game_menu"):
		show_game_menu_screen()


func start_game() -> void:
	print("game started")
	SceneManager.load_main_scene_container()
	SceneManager.load_level("level1") 
	SaveGameManager.load_game()
	SaveGameManager.allow_save_game = true

func exit_game() -> void:
	get_tree().quit()

func show_game_menu_screen() -> void:
	var game_menu_screen_instance: Node = game_menu_screen.instantiate()
	get_tree().root.add_child(game_menu_screen_instance)
