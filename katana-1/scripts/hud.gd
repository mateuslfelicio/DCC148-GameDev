extends CanvasLayer

## Barras de vida do jogador e do boss, e a mensagem de fim de luta.

@onready var player_bar: ProgressBar = $PlayerBar
@onready var boss_bar: ProgressBar = $BossBar
@onready var boss_name: Label = $BossName
@onready var message: Label = $Message


func _ready() -> void:
	message.hide()

	var player := get_tree().get_first_node_in_group("player")
	player_bar.max_value = player.max_health
	player_bar.value = player.health
	player.health_changed.connect(func(current: int, _max: int) -> void: player_bar.value = current)
	player.died.connect(_show_message.bind("VOCE MORREU\nR para reiniciar"))

	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null:
		boss_bar.hide()
		boss_name.hide()
		return
	boss_bar.max_value = boss.max_health
	boss_bar.value = boss.health
	boss.health_changed.connect(func(current: int, _max: int) -> void: boss_bar.value = current)
	boss.died.connect(_show_message.bind("IMPALER DERROTADO\nR para reiniciar"))


func _show_message(text: String) -> void:
	message.text = text
	message.show()
