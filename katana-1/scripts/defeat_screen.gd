extends Control

## Tela de fim de jogo (usada pela derrota e pela vitoria).

const main_menu = "res://scenes/main_menu.tscn"
const game_scene = "res://scenes/game.tscn"

@onready var play_again: Button = $VBoxContainer/Resume
@onready var quit: Button = $VBoxContainer/Quit


func _ready() -> void:
	# Garante que o jogo nao fique pausado ao chegar nesta tela
	get_tree().paused = false

	if play_again.visible:
		play_again.grab_focus()
	else:
		quit.grab_focus()


func _on_resume_pressed() -> void:
	SceneManager.changeSceneTo(load(game_scene))


func _on_quit_pressed() -> void:
	SceneManager.changeSceneTo(load(main_menu))
