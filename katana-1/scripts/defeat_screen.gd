extends Control

const main_menu = "res://scenes/main_menu.tscn"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _on_panel_visibility_changed() -> void:
	get_tree().paused = visible

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		visible = !visible

func _on_resume_pressed() -> void:
	visible = false
	var scene = load("res://scenes/game.tscn")
	SceneManager.changeSceneTo(scene)

func _on_quit_pressed() -> void:
	visible = false
	print(visible)
	get_tree().paused = false
	var scene = load(main_menu)
	SceneManager.changeSceneTo(scene)
