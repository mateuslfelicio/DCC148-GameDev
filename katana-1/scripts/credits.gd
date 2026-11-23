extends Control

## Tela de creditos (aberta pelo menu principal): devs e origem dos assets.
## Os links do texto abrem no navegador.

const main_menu = "res://scenes/main_menu.tscn"

@onready var text: RichTextLabel = $Scroll/Text
@onready var back: Button = $Back


func _ready() -> void:
	text.meta_clicked.connect(_on_link_clicked)
	back.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()


func _on_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _on_back_pressed() -> void:
	SceneManager.changeSceneTo(load(main_menu))
