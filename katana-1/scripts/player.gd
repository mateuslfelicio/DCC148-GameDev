extends CharacterBody2D

## Estados do personagem. Em cada estado so valem certas entradas
## (ex.: durante um ataque nao da para andar nem pular).
enum State { MOVE, DASH, ATTACK, BLOCK, HURT, DEAD }

signal health_changed(current: int, maximum: int)
signal died
signal invincible_changed(enabled: bool)

## Area de cada golpe, relativa aos pes, olhando para a direita (medida nos pixels
## azuis/vermelhos dos sprites). Vira o retangulo de colisao do no Hitbox durante os
## quadros ativos. "windows" = intervalos de quadros em que o golpe acerta;
## cada intervalo pode acertar o mesmo inimigo uma vez.
const ATTACK_HITBOXES := {
	&"attack_1": {"rect": Rect2(0, -18, 50, 18), "damage": 1, "windows": [Vector2i(1, 2)]},
	&"attack_2": {"rect": Rect2(0, -20, 49, 20), "damage": 1, "windows": [Vector2i(1, 2)]},
	&"attack_3": {"rect": Rect2(0, -36, 46, 36), "damage": 2, "windows": [Vector2i(1, 2)]},
	&"heavy_attack": {"rect": Rect2(-17, -55, 68, 55), "damage": 3, "windows": [Vector2i(8, 10)]},
	&"jump_attack": {"rect": Rect2(-10, -34, 59, 34), "damage": 1,
		"windows": [Vector2i(2, 3), Vector2i(7, 8), Vector2i(12, 13)]},
}

@export_group("Movimento")
## Velocidade maxima horizontal (px/s).
@export var speed := 110.0
## Quao rapido chega na velocidade maxima (px/s²).
@export var acceleration := 900.0
## Quao rapido para quando solta o direcional (px/s²).
@export var friction := 1100.0

@export_group("Pulo")
## Velocidade inicial do pulo (negativa = para cima).
@export var jump_velocity := -260.0
## Velocidade do pulo duplo (com a animacao de mortal).
@export var double_jump_velocity := -230.0
## Ao soltar o botao de pulo durante a subida, a velocidade e multiplicada por isto (pulo variavel).
@export_range(0.0, 1.0) var jump_cut := 0.45

@export_group("Dash")
@export var dash_speed := 260.0
## Duracao do dash em segundos.
@export var dash_duration := 0.25
## Tempo minimo entre dois dashes.
@export var dash_cooldown := 0.4

@export_group("Combo")
## Passo para frente a cada golpe do combo (px/s de impulso).
@export var combo_lunge := 130.0

@export_group("Bloqueio")
## Empurrao para tras ao bloquear um golpe (px/s).
@export var block_pushback := 70.0

@export_group("Dano")
@export var max_health := 5
## Tempo invencivel depois de levar dano (o sprite pisca).
@export var invulnerable_time := 1.0
## Empurrao ao levar dano: x = para tras, y = para cima.
@export var knockback_velocity := Vector2(140.0, -120.0)

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var state := State.MOVE
## 1 = olhando para a direita, -1 = para a esquerda.
var facing := 1.0
var health := max_health
var can_double_jump := true
var can_air_dash := true
var dash_timer := 0.0
var dash_cooldown_timer := 0.0
## Golpe atual do combo (1, 2 ou 3); 0 = fora do combo.
var combo_index := 0
## true se o jogador apertou ataque durante o golpe atual (vai encadear o proximo).
var combo_queued := false
## Tempo restante de invencibilidade depois de levar dano.
var invulnerable_timer := 0.0
## Janela de golpe atual (cada uma acerta o mesmo inimigo uma vez).
var hit_window := -1
## Modo invencivel (liga/desliga com a tecla I ou o botao do HUD): nenhum golpe causa dano.
var invincible := false

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox: Hitbox = $Hitbox


func _ready() -> void:
	health = max_health
	add_to_group("player")
	sprite.animation_finished.connect(_on_animation_finished)


func _physics_process(delta: float) -> void:
	dash_cooldown_timer = maxf(dash_cooldown_timer - delta, 0.0)
	_update_invulnerability(delta)
	_handle_debug_keys()

	var was_on_floor := is_on_floor()

	match state:
		State.MOVE:
			_state_move(delta)
		State.DASH:
			_state_dash(delta)
		State.ATTACK:
			_state_attack(delta)
		State.BLOCK:
			_state_block(delta)
		State.HURT, State.DEAD:
			_state_passive(delta)

	move_and_slide()

	var just_landed := is_on_floor() and not was_on_floor
	if is_on_floor():
		can_double_jump = true
		can_air_dash = true
	# Ataque aereo e cancelado ao tocar o chao.
	if just_landed and state == State.ATTACK and sprite.animation == &"jump_attack":
		state = State.MOVE

	if state == State.MOVE:
		_update_move_animation(just_landed)
	_update_facing()
	_update_hitbox()


# ---------------------------------------------------------------- estados

func _state_move(delta: float) -> void:
	_apply_gravity(delta)

	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = signf(direction)

	# Acoes que trocam de estado
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer == 0.0 \
			and (is_on_floor() or can_air_dash):
		_start_dash()
		return
	if Input.is_action_just_pressed("attack"):
		if is_on_floor():
			_start_combo(1)
		else:
			_start_attack(&"jump_attack")
		return
	if Input.is_action_just_pressed("heavy_attack") and is_on_floor():
		_start_attack(&"heavy_attack")
		return
	if Input.is_action_pressed("block") and is_on_floor():
		_start_block()
		return

	# Pulo e pulo duplo
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_velocity
		elif can_double_jump:
			velocity.y = double_jump_velocity
			can_double_jump = false
			_restart(&"jump_flip")
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_cut

	# Movimento horizontal com aceleracao/atrito
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _state_dash(delta: float) -> void:
	# Sem gravidade: o dash e uma linha reta, inclusive no ar.
	velocity = Vector2(facing * dash_speed, 0.0)
	dash_timer -= delta
	if dash_timer <= 0.0:
		state = State.MOVE
		velocity.x = facing * speed


func _state_attack(delta: float) -> void:
	_apply_gravity(delta)
	# Bloquear cancela o golpe no chao (defesa de emergencia).
	if Input.is_action_just_pressed("block") and is_on_floor():
		_start_block()
		return
	# Apertar ataque durante um golpe do combo guarda o proximo golpe.
	if combo_index > 0 and combo_index < 3 and Input.is_action_just_pressed("attack"):
		combo_queued = true
	# No chao o personagem freia; no ar mantem o impulso do pulo.
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)


func _state_block(delta: float) -> void:
	_apply_gravity(delta)
	velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	if not Input.is_action_pressed("block"):
		state = State.MOVE


## Levando dano ou morto: so a fisica age, sem controle do jogador.
func _state_passive(delta: float) -> void:
	_apply_gravity(delta)
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, friction * 0.5 * delta)


# ---------------------------------------------------------------- acoes

func _start_dash() -> void:
	state = State.DASH
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	Sfx.play(&"player_dash")
	if is_on_floor():
		_restart(&"dash")
	else:
		can_air_dash = false
		_restart(&"air_dash")


func _start_block() -> void:
	state = State.BLOCK
	combo_index = 0
	combo_queued = false
	_restart(&"block")


func _start_attack(anim: StringName) -> void:
	state = State.ATTACK
	combo_index = 0
	combo_queued = false
	hit_window = -1
	_restart(anim)


## Comeca o golpe `index` (1 a 3) do combo do ataque normal.
func _start_combo(index: int) -> void:
	state = State.ATTACK
	combo_index = index
	combo_queued = false
	# Entre um golpe e outro o jogador pode virar de lado.
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		facing = signf(direction)
	velocity.x = facing * combo_lunge
	hit_window = -1
	_restart(StringName("attack_%d" % index))


## Chame isto quando algo atingir o personagem. `source_x` e a posicao x do golpe.
## Retorna true se o golpe foi resolvido (causou dano ou foi bloqueado) e false se foi
## ignorado (invencivel ou no dash); nesse caso o Hitbox pode tentar de novo.
func take_hit(source_x: float, damage := 1) -> bool:
	if state == State.DEAD or state == State.DASH or invulnerable_timer > 0.0:
		return false
	# Invencivel: o golpe e consumido, mas nao causa dano nem empurrao.
	if invincible:
		return true
	var hit_dir := signf(source_x - global_position.x)
	if hit_dir == 0.0:
		hit_dir = facing
	var away := -hit_dir

	# Bloqueando, nenhum golpe causa dano, venha de onde vier. O personagem vira para o
	# golpe e e empurrado um pouco. Retorna true para o golpe nao acertar de novo na
	# mesma janela se o jogador soltar o bloqueio logo depois.
	if state == State.BLOCK:
		facing = hit_dir
		velocity.x = away * block_pushback
		_block_flash()
		Sfx.play(&"player_block")
		return true

	health = maxi(health - damage, 0)
	combo_index = 0
	velocity = Vector2(away * knockback_velocity.x, knockback_velocity.y)
	health_changed.emit(health, max_health)
	Sfx.play(&"player_hurt")
	if health <= 0:
		state = State.DEAD
		_restart(&"death")
		died.emit()
	else:
		state = State.HURT
		invulnerable_timer = invulnerable_time
		_restart(&"knockback")
	return true


func is_dead() -> bool:
	return state == State.DEAD


## Alterna entre o modo invencivel e o estado normal.
func toggle_invincible() -> void:
	set_invincible(not invincible)


func set_invincible(enabled: bool) -> void:
	if invincible == enabled:
		return
	invincible = enabled
	invincible_changed.emit(invincible)


# ---------------------------------------------------------------- combate

## Liga o retangulo do golpe no Hitbox durante os quadros ativos e desliga fora deles.
## Quem testa se ele encostou no Hurtbox do inimigo e a fisica do Godot.
func _update_hitbox() -> void:
	if state != State.ATTACK or not ATTACK_HITBOXES.has(sprite.animation):
		hitbox.clear()
		return
	var data: Dictionary = ATTACK_HITBOXES[sprite.animation]
	var window := _window_index(data["windows"], sprite.frame)
	if window == -1:
		hitbox.clear()
		return
	if window != hit_window:
		hit_window = window
		hitbox.new_window()
		# Som do golpe no primeiro quadro que acerta (cada janela e um corte)
		Sfx.play(&"player_heavy_attack" if sprite.animation == &"heavy_attack" else &"player_attack")
	hitbox.damage = data["damage"]
	var rects: Array[Rect2] = [data["rect"]]
	hitbox.set_rects(rects, facing)


static func _window_index(windows: Array, frame: int) -> int:
	for i in windows.size():
		if frame >= windows[i].x and frame <= windows[i].y:
			return i
	return -1


## Brilho rapido ao bloquear, para o jogador ver que defendeu.
func _block_flash() -> void:
	sprite.self_modulate = Color(1.8, 1.8, 2.4)
	create_tween().tween_property(sprite, "self_modulate", Color.WHITE, 0.15)


func _update_invulnerability(delta: float) -> void:
	invulnerable_timer = maxf(invulnerable_timer - delta, 0.0)
	# Pisca enquanto esta invencivel.
	var blink := invulnerable_timer > 0.0 and fmod(invulnerable_timer, 0.16) < 0.08
	sprite.modulate.a = 0.35 if blink else 1.0


func _on_animation_finished() -> void:
	match state:
		State.ATTACK:
			if combo_queued:
				_start_combo(combo_index + 1)
			else:
				combo_index = 0
				state = State.MOVE
		State.HURT:
			state = State.MOVE


# ---------------------------------------------------------------- animacao

func _update_move_animation(just_landed: bool) -> void:
	var current := sprite.animation
	var direction := Input.get_axis("move_left", "move_right")

	if not is_on_floor():
		if current == &"jump_flip" and sprite.is_playing():
			pass # deixa o mortal terminar
		else:
			_play(&"jump" if velocity.y < 0.0 else &"fall")
	elif direction != 0.0:
		_play(&"run")
	elif just_landed:
		_play(&"land")
	elif current == &"run":
		_play(&"run_end")
	elif current in [&"run_end", &"land"] and sprite.is_playing():
		pass # deixa a animacao de transicao terminar
	else:
		_play(&"idle")


## Espelha o sprite e corrige o deslocamento dos quadros largos (128px).
## Em todos os quadros o personagem fica em x=32; num quadro de 128px o centro
## e x=64, entao o desenho e empurrado 32px para o lado do personagem ficar na origem.
func _update_facing() -> void:
	sprite.flip_h = facing < 0.0
	var frame_width := sprite.sprite_frames.get_frame_texture(sprite.animation, 0).get_width()
	sprite.offset.x = (frame_width / 2.0 - 32.0) * facing


## Toca a animacao, sem reiniciar se ela ja estiver tocando.
func _play(anim: StringName) -> void:
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


## Toca a animacao sempre do primeiro quadro.
func _restart(anim: StringName) -> void:
	sprite.stop()
	sprite.play(anim)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta


# ---------------------------------------------------------------- debug

## H = leva um golpe vindo da frente, R = reinicia a cena, I = liga/desliga invencivel.
func _handle_debug_keys() -> void:
	if Input.is_action_just_pressed("toggle_invincible"):
		toggle_invincible()
	if Input.is_action_just_pressed("debug_hit"):
		take_hit(global_position.x + facing * 10.0)
	if Input.is_action_just_pressed("debug_restart"):
		get_tree().reload_current_scene()
