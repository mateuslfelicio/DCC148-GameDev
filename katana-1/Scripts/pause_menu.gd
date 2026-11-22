extends Control

const main_menu = "res://Scenes/main_menu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_panel_visibility_changed() -> void:
	get_tree().paused = visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		global_position = get_viewport().get_camera_2d().get_screen_center_position() - size * 0.5
		visible = !visible

func _on_resume_pressed() -> void:
	visible = false	
	var scene = load("res://Scenes/game.tscn")
	SceneManager.changeSceneTo(scene)
	

func _on_quit_pressed() -> void:
	visible = false
	print(visible)
	get_tree().paused = false
	var scene = load(main_menu)
	SceneManager.changeSceneTo(scene)
