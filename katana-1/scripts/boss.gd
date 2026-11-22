extends CharacterBody2D

## Impaler Boss. Segue uma rotina de comportamento em ciclos:
##
##   1. SEQUENCIA: faz de 2 a 3 ataques (3 a 4 na fase 2). Antes de cada um ele escolhe
##      o golpe, anda ate o jogador ficar ao alcance e brilha por um instante (aviso).
##      Depois de cada golpe fica parado um tempo (recuperacao = janela para contra-atacar).
##   2. CANSADO: no fim da sequencia fica ofegante, azulado e lento por uns 2 s.
##      E a maior janela para bater.
##   3. REPOSICIONA: se o jogador estiver colado, recua alguns passos; depois recomeca.
##
## Com metade da vida ele ruge (fica invencivel por um instante) e entra na fase 2:
## animacoes mais rapidas, sequencias maiores, pausas menores e o ataque 6.
##
## As areas de corpo e de golpe de cada quadro vem de boss_hitbox_data.gd, gerado pelos
## sprites (tools/build_boss_data.py). A cada quadro elas viram os retangulos de colisao
## dos nos Hurtbox (corpo) e Hitbox (golpe); a fisica do Godot detecta os acertos.

const DEFEAT_DELAY := 1.2

signal health_changed(current: int, maximum: int)
signal died

const Data := preload("res://scripts/boss_hitbox_data.gd")

enum State { WAIT, IDLE, WALK, RETREAT, WINDUP, ATTACK, TIRED, ROAR, DEAD }

## Dados de cada ataque:
## - windows: intervalos de quadros (inclusivos) em que o golpe causa dano; cada um acerta uma vez.
## - damage: dano por intervalo.
## - windup: tempo parado no 1o quadro, brilhando, antes de atacar (aviso para o jogador).
## - recover: tempo parado depois do golpe (janela para contra-atacar).
## - weight: chance relativa de ser escolhido.
const ATTACKS := {
	&"attack2": { # corte + giro (rapido, curto)
		"windows": [Vector2i(1, 3), Vector2i(4, 6)],
		"damage": 1, "windup": 0.25, "recover": 0.7, "weight": 3,
	},
	&"attack3": { # corte, giro, giro longo
		"windows": [Vector2i(5, 7), Vector2i(8, 11), Vector2i(12, 19)],
		"damage": 1, "windup": 0.3, "recover": 1.0, "weight": 2,
	},
	&"attack1": { # corte + estocadas + espinhos
		"windows": [Vector2i(2, 3), Vector2i(5, 13), Vector2i(18, 21)],
		"damage": 1, "windup": 0.35, "recover": 1.2, "weight": 2,
	},
	&"attack4": { # duas estocadas longas
		"windows": [Vector2i(4, 11), Vector2i(16, 24)],
		"damage": 1, "windup": 0.45, "recover": 1.4, "weight": 2,
	},
	&"attack5": { # avanco + clone (alcance enorme)
		"windows": [Vector2i(4, 7), Vector2i(8, 15), Vector2i(16, 18), Vector2i(20, 25)],
		"damage": 1, "windup": 0.5, "recover": 1.6, "weight": 1,
	},
	&"attack6": { # salto + onda (so na fase 2)
		"windows": [Vector2i(2, 5), Vector2i(6, 13), Vector2i(14, 17)],
		"damage": 2, "windup": 0.6, "recover": 1.8, "weight": 2,
	},
}
## Ataques que so aparecem quando o boss esta com metade da vida ou menos.
const PHASE_2_ATTACKS := [&"attack6"]

## Cor do aviso antes do golpe (vermelho = golpe que tira 2 de vida).
const WARN_COLOR := Color(1.8, 1.3, 0.5)
const WARN_COLOR_HEAVY := Color(2.2, 0.5, 0.4)
const TIRED_COLOR := Color(0.6, 0.75, 1.1)
const ROAR_COLOR := Color(1.8, 0.45, 0.45)

@export var max_health := 50

@export_group("Movimento")
@export var walk_speed := 38.0
@export var retreat_speed := 55.0
## O boss so comeca a luta quando o jogador chega a esta distancia.
@export var aggro_range := 260.0
## Tempo maximo andando atras de um ataque antes de trocar por outro que ja alcance.
@export var max_walk_time := 2.5
## Jogador mais perto que isto pode fazer o boss recuar.
@export var close_range := 45.0
## Chance de recuar (em vez de atacar) quando o jogador esta colado.
@export_range(0.0, 1.0) var retreat_chance := 0.3
@export var retreat_time := 0.7

@export_group("Rotina")
## Quantos ataques por sequencia (sorteado entre x e y).
@export var chain_length := Vector2i(2, 3)
@export var chain_length_phase_2 := Vector2i(3, 4)
## Tempo cansado no fim de cada sequencia.
@export var tired_time := 2.4
@export var tired_time_phase_2 := 1.8

@export_group("Fase 2")
## Velocidade das animacoes na fase 2.
@export var phase_2_speed := 1.25
## Multiplica o aviso e a recuperacao de cada golpe na fase 2 (menor = mais agressivo).
@export var phase_2_recover := 0.75
## Duracao do rugido ao entrar na fase 2 (invencivel).
@export var roar_time := 1.4

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var state := State.WAIT
var facing := -1.0
var health := max_health
var phase_2 := false
## Tempo restante do estado atual (IDLE, WALK, RETREAT, WINDUP, TIRED, ROAR).
var state_timer := 0.0
## Ataque escolhido para a proxima investida.
var planned_attack: StringName = &""
var last_attack: StringName = &""
## Ataques que faltam na sequencia atual.
var chain_left := 0
## Intervalo de dano atual (cada um acerta o jogador uma vez).
var hit_window := -1
var flash_timer := 0.0
## Para cada ataque, os trechos em x (min, max) que os golpes cobrem na altura do chao.
## Calculado uma vez dos dados; a IA usa para saber se o golpe alcanca o jogador.
var reach := {}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox
@onready var target: Node2D = get_tree().get_first_node_in_group("player")


func _ready() -> void:
	health = max_health
	add_to_group("enemies")
	add_to_group("boss")
	sprite.animation_finished.connect(_on_animation_finished)
	_build_reach()
	_play(&"idle")


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta

	if state != State.DEAD and (target == null or target.is_dead()):
		_set_idle(INF) # jogador morreu: o boss para

	state_timer -= delta
	match state:
		State.WAIT:
			velocity.x = 0.0
			if absf(_dx()) <= aggro_range:
				_begin_chain()
				_set_idle(0.6)
		State.IDLE:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_think()
		State.WALK:
			_face_target()
			velocity.x = facing * walk_speed
			if _in_range(planned_attack):
				_start_windup(planned_attack)
			elif state_timer <= 0.0:
				_replan()
		State.RETREAT:
			_face_target()
			velocity.x = -facing * retreat_speed
			if state_timer <= 0.0 or is_on_wall():
				_set_idle(0.2)
		State.WINDUP:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_start_attack()
		State.ATTACK:
			velocity.x = 0.0
		State.TIRED:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_end_tired()
		State.ROAR:
			velocity.x = 0.0
			if state_timer <= 0.0:
				_begin_chain()
				_set_idle(0.2)
		State.DEAD:
			velocity.x = 0.0

	move_and_slide()
	_update_sprite(delta)
	_update_boxes()


# ---------------------------------------------------------------- rotina

## Comeca uma nova sequencia de ataques.
func _begin_chain() -> void:
	var length := chain_length_phase_2 if phase_2 else chain_length
	chain_left = randi_range(length.x, length.y)


## Fim da pausa: decide o proximo passo da sequencia.
func _think() -> void:
	_face_target()
	if absf(_dx()) < close_range and randf() < retreat_chance:
		_start_retreat()
		return
	planned_attack = _pick_attack(_available_attacks())
	if _in_range(planned_attack):
		_start_windup(planned_attack)
	else:
		state = State.WALK
		state_timer = max_walk_time
		_play(&"walk")


## Andou demais sem alcancar o jogador: usa um ataque que ja alcance, ou continua andando.
func _replan() -> void:
	var options := _attacks_in_range()
	if options.is_empty():
		state_timer = 1.0
	else:
		_start_windup(_pick_attack(options))


func _start_retreat() -> void:
	state = State.RETREAT
	state_timer = retreat_time
	sprite.play_backwards(&"walk")
	sprite.speed_scale = _anim_speed()


func _start_tired() -> void:
	state = State.TIRED
	state_timer = tired_time_phase_2 if phase_2 else tired_time
	_play(&"idle", 0.5)


## Recupera o folego: comeca outra sequencia, recuando antes se o jogador estiver colado.
func _end_tired() -> void:
	_begin_chain()
	_face_target()
	if absf(_dx()) < close_range * 1.5:
		_start_retreat()
	else:
		_set_idle(0.3)


func _start_roar() -> void:
	state = State.ROAR
	Sfx.play_at(&"boss_roar", global_position)
	state_timer = roar_time
	_play(&"idle", 0.0)


func _set_idle(wait: float) -> void:
	state = State.IDLE
	state_timer = wait
	_play(&"idle")


# ---------------------------------------------------------------- escolha do ataque

func _available_attacks() -> Array[StringName]:
	var result: Array[StringName] = []
	for anim: StringName in ATTACKS:
		if anim in PHASE_2_ATTACKS and not phase_2:
			continue
		result.append(anim)
	return result


## Ataques que acertariam o jogador na distancia em que ele esta agora.
func _attacks_in_range() -> Array[StringName]:
	var result: Array[StringName] = []
	for anim in _available_attacks():
		if _in_range(anim):
			result.append(anim)
	return result


## Sorteio com peso, evitando repetir o ultimo ataque se houver outra opcao.
func _pick_attack(options: Array[StringName]) -> StringName:
	if options.size() > 1:
		options.erase(last_attack)
	var total := 0
	for anim in options:
		total += ATTACKS[anim]["weight"]
	var roll := randi_range(1, total)
	for anim in options:
		roll -= ATTACKS[anim]["weight"]
		if roll <= 0:
			return anim
	return options.back()


## O golpe alcanca o jogador (10px de largura, no chao) na distancia em que ele esta agora?
## Isto e uma previsao da IA, nao um teste de colisao: os acertos de verdade sao da fisica.
func _in_range(anim: StringName) -> bool:
	var distance := absf(_dx())
	for span: Vector2 in reach[anim]:
		if distance + 5.0 > span.x and distance - 5.0 < span.y:
			return true
	return false


## Junta os trechos em x dos golpes que passam na altura do jogador (20px acima do chao).
func _build_reach() -> void:
	for anim: StringName in ATTACKS:
		var spans: Array[Vector2] = []
		for window: Vector2i in ATTACKS[anim]["windows"]:
			for f in range(window.x, window.y + 1):
				for r: Rect2 in Data.STRIKES[anim][f]:
					if r.end.y > -20.0 and r.position.y < 0.0:
						spans.append(Vector2(r.position.x, r.end.x))
		reach[anim] = spans


# ---------------------------------------------------------------- ataque

## Para no 1o quadro do ataque e brilha por um instante antes de golpear.
func _start_windup(anim: StringName) -> void:
	_face_target()
	state = State.WINDUP
	planned_attack = anim
	state_timer = ATTACKS[anim]["windup"] * _phase_factor()
	sprite.stop()
	sprite.animation = anim # fica parado no quadro 0


func _start_attack() -> void:
	state = State.ATTACK
	last_attack = planned_attack
	hit_window = -1
	_play(planned_attack)


func _on_animation_finished() -> void:
	if state != State.ATTACK:
		return
	chain_left -= 1
	if chain_left <= 0:
		_start_tired()
	else:
		_set_idle(ATTACKS[last_attack]["recover"] * _phase_factor())


# ---------------------------------------------------------------- dano

## Copia as areas do quadro atual para os nos de colisao: o corpo vai para o Hurtbox
## (desligado morto ou rugindo) e, nos quadros ativos do ataque, os golpes vao para o Hitbox.
func _update_boxes() -> void:
	var body := Rect2()
	if state != State.DEAD and state != State.ROAR:
		body = Data.BODY[sprite.animation][sprite.frame]
	hurtbox.set_rect(body, facing)

	var window := -1
	if state == State.ATTACK:
		window = _window_index(ATTACKS[sprite.animation]["windows"], sprite.frame)
	if window == -1:
		hitbox.clear()
		return
	if window != hit_window:
		hit_window = window
		hitbox.new_window()
		Sfx.play_at(&"boss_attack", global_position)
	hitbox.damage = ATTACKS[sprite.animation]["damage"]
	var rects: Array[Rect2] = []
	rects.assign(Data.STRIKES[sprite.animation][sprite.frame])
	hitbox.set_rects(rects, facing)


## Chamado pelo Hurtbox quando um golpe do jogador acerta. Retorna true se causou dano.
func take_hit(_source_x: float, amount := 1) -> bool:
	if state == State.DEAD or state == State.ROAR:
		return false
	if state == State.WAIT:
		_begin_chain()
		_set_idle(0.3) # atacar o boss tambem comeca a luta
	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	flash_timer = 0.1
	if health <= 0:
		state = State.DEAD
		Sfx.play_at(&"boss_death", global_position)
		_play(&"death")
		died.emit()
		return true
	Sfx.play_at(&"boss_hurt", global_position)
	if not phase_2 and health * 2 <= max_health:
		phase_2 = true
		_start_roar() # interrompe o que estiver fazendo
	return true


# ---------------------------------------------------------------- auxiliares

func _dx() -> float:
	return target.global_position.x - global_position.x if target else INF


func _face_target() -> void:
	var dx := _dx()
	if dx != 0.0:
		facing = signf(dx)


## Na fase 2 os avisos e as pausas ficam mais curtos.
func _phase_factor() -> float:
	return phase_2_recover if phase_2 else 1.0


func _anim_speed() -> float:
	return phase_2_speed if phase_2 and state != State.DEAD else 1.0


## Toca a animacao com a velocidade da fase (vezes `speed`).
func _play(anim: StringName, speed := 1.0) -> void:
	sprite.speed_scale = _anim_speed() * speed
	sprite.play(anim)


## Os sprites olham para a direita e o boss fica em ORIGIN dentro do quadro (centered = false).
## Ao espelhar, o boss passa para a posicao (largura - ORIGIN.x).
## A cor mostra o estado: brilho no aviso, azul cansado, vermelho tremendo no rugido.
func _update_sprite(delta: float) -> void:
	sprite.flip_h = facing < 0.0
	var frame_width := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame).get_width()
	var origin_x := frame_width - Data.ORIGIN.x if sprite.flip_h else Data.ORIGIN.x
	sprite.offset = Vector2(-origin_x, -Data.ORIGIN.y)

	var tint := Color.WHITE
	match state:
		State.WINDUP:
			var warn := WARN_COLOR_HEAVY if ATTACKS[planned_attack]["damage"] > 1 else WARN_COLOR
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03)
			tint = Color.WHITE.lerp(warn, pulse)
		State.TIRED:
			tint = TIRED_COLOR
		State.ROAR:
			tint = ROAR_COLOR
			sprite.offset.x += randf_range(-2.0, 2.0)
	flash_timer -= delta
	if flash_timer > 0.0:
		tint = Color(2.5, 2.5, 2.5)
	sprite.modulate = tint


static func _window_index(windows: Array, frame: int) -> int:
	for i in windows.size():
		if frame >= windows[i].x and frame <= windows[i].y:
			return i
	return -1


func _on_died() -> void:
	await get_tree().create_timer(DEFEAT_DELAY).timeout
	SceneManager.changeSceneTo(load("res://scenes/defeat_screen.tscn"))
