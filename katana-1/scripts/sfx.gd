extends Node

## Efeitos sonoros do jogo (autoload "Sfx").
##
## Sfx.play(&"nome")             toca sem posicao (jogador, interface, vitoria/derrota).
## Sfx.play_at(&"nome", posicao) toca no mundo: some com a distancia (inimigos e bosses).
##
## Cada nome tem uma lista de sons; um deles e sorteado a cada vez e o tom varia um
## pouco para o mesmo golpe nao soar sempre igual. Os sons ficam em assets/sounds.
##
## Os botoes de qualquer cena ganham som sozinhos: passar o mouse/foco e clicar.

const SOUNDS := {
	# Jogador
	&"player_attack": [
		preload("res://assets/sounds/swipe.wav"),
		preload("res://assets/sounds/sword_slice.wav"),
		preload("res://assets/sounds/sword_light.wav"),
	],
	&"player_heavy_attack": [preload("res://assets/sounds/whoosh_2.wav")],
	&"player_dash": [preload("res://assets/sounds/air_burst.wav")],
	&"player_block": [preload("res://assets/sounds/sword_clash.wav")],
	&"player_hurt": [preload("res://assets/sounds/hurt.wav")],

	# Inimigo comum (robo)
	&"enemy_shoot": [preload("res://assets/sounds/shot_muffled.wav")],
	&"enemy_hurt": [preload("res://assets/sounds/punch.wav")],
	&"enemy_death": [preload("res://assets/sounds/explosion_small.wav")],

	# Bosses
	&"boss_attack": [
		preload("res://assets/sounds/whoosh_1.wav"),
		preload("res://assets/sounds/sword_slice.wav"),
	],
	&"boss_spin_dash": [preload("res://assets/sounds/drill_whizz.wav")],
	&"boss_hurt": [
		preload("res://assets/sounds/metal_clang.wav"),
		preload("res://assets/sounds/metal_blunt_tap.wav"),
	],
	&"boss_roar": [preload("res://assets/sounds/horror_sting.wav")],
	&"boss_death": [
		preload("res://assets/sounds/harsh_thud.wav"),
		preload("res://assets/sounds/explosion_large.wav"),
	],

	# Interface e fim de jogo
	&"ui_focus": [preload("res://assets/sounds/menu_blip.wav")],
	&"ui_press": [preload("res://assets/sounds/select_1.wav")],
	&"victory": [preload("res://assets/sounds/8_bit_level_complete.wav")],
	&"defeat": [preload("res://assets/sounds/8_bit_defeated.wav")],
}

## Variacao maxima de tom (0.06 = entre 94% e 106%).
const PITCH_VARIATION := 0.06
## Sons de jingle nao variam o tom.
const FIXED_PITCH := [&"victory", &"defeat"]
## Distancia (px) a partir da qual um som no mundo nao e mais ouvido.
const WORLD_MAX_DISTANCE := 700.0
## Botoes recem-criados nao tocam o som de foco (evita o "blip" ao abrir um menu).
const FOCUS_GRACE_MS := 250

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Os menus funcionam com o jogo pausado, entao os sons tambem precisam.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	get_tree().node_added.connect(_on_node_added)


## Toca um som sem posicao. Ele continua tocando mesmo se a cena trocar.
func play(sound: StringName, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	if not _setup(player, sound, volume_db):
		return
	add_child(player)
	player.play()


## Toca um som num ponto do mundo (fica mais baixo longe da camera).
func play_at(sound: StringName, position: Vector2, volume_db := 0.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		play(sound, volume_db)
		return
	var player := AudioStreamPlayer2D.new()
	if not _setup(player, sound, volume_db):
		return
	player.max_distance = WORLD_MAX_DISTANCE
	scene.add_child(player)
	player.global_position = position
	player.play()


func _setup(player: Node, sound: StringName, volume_db: float) -> bool:
	var options: Array = SOUNDS.get(sound, [])
	if options.is_empty():
		push_warning("Sfx: som desconhecido '%s'" % sound)
		player.free()
		return false
	player.stream = options[_rng.randi_range(0, options.size() - 1)]
	player.volume_db = volume_db
	if sound not in FIXED_PITCH:
		player.pitch_scale = 1.0 + _rng.randf_range(-PITCH_VARIATION, PITCH_VARIATION)
	player.finished.connect(player.queue_free)
	return true


# ---------------------------------------------------------------- botoes

func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	button.set_meta(&"sfx_added_at", Time.get_ticks_msec())
	button.pressed.connect(play.bind(&"ui_press"))
	button.mouse_entered.connect(_on_button_focus.bind(button))
	button.focus_entered.connect(_on_button_focus.bind(button))


func _on_button_focus(button: BaseButton) -> void:
	if button.disabled or not button.is_visible_in_tree():
		return
	if Time.get_ticks_msec() - int(button.get_meta(&"sfx_added_at", 0)) < FOCUS_GRACE_MS:
		return
	play(&"ui_focus", -4.0)
