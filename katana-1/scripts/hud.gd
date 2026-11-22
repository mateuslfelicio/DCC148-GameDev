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
	player.died.connect(_call_defeat)


func _call_defeat() -> void:
	var scene = load("res://Scenes/defeat_screen.tscn")
	print(scene)
	
	SceneManager.changeSceneTo(scene)
