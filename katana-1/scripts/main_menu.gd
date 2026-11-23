extends Node

@onready var main_menu = $"../MenuScreen"
@onready var controls_menu: Control = $"../ControlsMenu"
@export var game_scene : PackedScene

func _ready() -> void:
	$"../MenuScreen/VBoxContainer/Play".grab_focus()

func _on_play_pressed() -> void:
	SceneManager.changeSceneTo(game_scene)

func _on_credits_pressed() -> void:
	SceneManager.changeSceneTo(load("res://scenes/credits.tscn"))

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_controls_pressed() -> void:
	main_menu.hide()
	$"../ControlsMenu/VBoxContainer/Return".grab_focus()
	controls_menu.show()

func _on_return_pressed() -> void:
	main_menu.show()
	$"../MenuScreen/VBoxContainer/Play".grab_focus()
	controls_menu.hide()
