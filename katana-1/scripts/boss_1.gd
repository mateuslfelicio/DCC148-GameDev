extends CharacterBody2D

## Boss do Spin Dash. Mantém a arquitetura própria (enum State + current_state, ataques
## 1/2 de lâmina e ataque 3 em três fases), mas usa o mesmo sistema do Impaler:
##
##   - VISÃO: acha o jogador pelo grupo "player" e começa a luta ao chegar em aggro_range
##     (sem DetectionArea). Depois que a luta começa, ele persegue o jogador sempre.
##   - COLISÃO: a cada frame as áreas viram os retângulos dos nós Hurtbox (corpo) e Hitbox
##     (golpe), já espelhados pelo `facing`. A física do Godot detecta os acertos.

signal health_changed(current: int, maximum: int)
signal died


# =========================
# CONFIGURAÇÕES
# =========================

@export var speed: float = 80.0
@export var gravity: float = 980.0

@export var max_health: int = 20
@export var damage: int = 1

@export var attack_range: float = 100.0
## Tempo de espera entre um ataque e o próximo (o boss fica perseguindo/parado).
@export var attack_cooldown: float = 1.5
## Espera mínima antes de atacar de novo depois de levar um golpe.
@export var hit_attack_delay: float = 0.8

# Percepção
## O boss só começa a luta quando o jogador chega a esta distância.
@export var aggro_range: float = 260.0

# Spin Dash
@export var dash_speed: float = 450.0
@export var dash_duration: float = 0.7
@export var end_attack_blade_delay: float = 0.15

# Hit
@export var hit_duration: float = 0.3
@export var invulnerability_duration: float = 0.4

@export_group("Áreas de colisão")
## Retângulos em coordenadas locais do boss, desenhados OLHANDO PARA A DIREITA.
## O Hurtbox/Hitbox espelham sozinhos quando o boss vira. Ajuste vendo
## Depuração > Formas de colisão visíveis.
@export var body_rect: Rect2 = Rect2(-20, -40, 40, 80)
@export var blade_rect: Rect2 = Rect2(6, -10, 40, 42)
@export var dash_rect: Rect2 = Rect2(-24, -14, 40, 48)
## Desloca TODOS os retângulos de uma vez (olhando para a direita; o x é espelhado
## junto com o boss). Use para alinhar as áreas com o desenho do boss.
@export var rect_offset: Vector2 = Vector2.ZERO
## Desenha o contorno do que o script envia: azul = corpo, vermelho = golpe.
@export var debug_draw: bool = true


# =========================
# JANELAS DE DANO
# =========================

## Intervalos de quadros (inclusivos) em que a lâmina causa dano. Cada intervalo acerta
## uma vez só. O -1 no fim significa "até o último quadro da animação".
## Para um golpe só em quadros específicos, troque por ex. Vector2i(2, 5).
const BLADE_WINDOWS := {
	&"atack1": [Vector2i(0, -1)],
}

## Animações que precisam terminar para o boss seguir a rotina. Se alguma estiver com
## Loop ligado no SpriteFrames, o sinal animation_finished nunca dispara e o boss
## travaria no ataque. Por isso o loop é desligado aqui.
const ONE_SHOT_ANIMATIONS: Array[StringName] = [
	&"atack1", &"preAtack", &"endAtack", &"hit", &"death"
]

## Animações que devem repetir.
const LOOP_ANIMATIONS: Array[StringName] = [&"idle", &"walk"]

## Folga além da duração da animação antes do plano B encerrar o ataque.
const FAILSAFE_MARGIN := 0.25


# =========================
# NÓS
# =========================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox

@onready var target: Node2D = get_tree().get_first_node_in_group("player")


# =========================
# ESTADOS
# =========================

enum State {
	IDLE,
	WALK,
	ATTACK1,
	PRE_ATTACK3,
	MID_ATTACK3,
	END_ATTACK3,
	HIT,
	DEATH
}

var current_state: State = State.IDLE

var active: bool = false
var health: int
var dead: bool = false

var attack_timer: float = 0.0
var dash_timer: float = 0.0
var end_blade_timer: float = 0.0
var hit_timer: float = 0.0
var invulnerability_timer: float = 0.0

# Plano B: encerra o ataque por tempo se a animação nunca avisar que terminou
var failsafe_timer: float = 0.0

var dash_direction: float = 0.0

# Último ataque usado (1, 2 ou 3), para variar a escolha
var last_attack: int = 0

# Lado para onde o boss está olhando (1 = direita, -1 = esquerda)
var facing: float = 1.0

# Intervalo de dano atual (cada um acerta o jogador uma vez)
var hit_window: int = -1

# Retângulos enviados no último frame (só para o desenho de depuração)
var _debug_body: Rect2 = Rect2()
var _debug_strike: Rect2 = Rect2()

# Jogador com quem a colisão física está desligada durante o dash
var _ghost_body: PhysicsBody2D = null


# =========================
# INICIALIZAÇÃO
# =========================

func _ready() -> void:
	health = max_health

	add_to_group("enemies")
	add_to_group("boss")

	_setup_animations()

	sprite.animation_finished.connect(_on_animation_finished)

	_face(1.0)
	sprite.play("idle")


## Garante que as animações de ataque terminam e que idle/walk repetem.
func _setup_animations() -> void:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return

	for anim in ONE_SHOT_ANIMATIONS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)

	for anim in LOOP_ANIMATIONS:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, true)


# =========================
# LOOP PRINCIPAL
# =========================

func _physics_process(delta: float) -> void:
	if dead:
		return

	_update_target()
	_run_state(delta)
	_update_boxes()


# =========================
# VISÃO DO JOGADOR
# =========================

## Começa a luta quando o jogador chega a aggro_range. Depois disso o boss persegue
## sempre. Se o jogador morrer, o boss para.
func _update_target() -> void:
	if _target_dead():
		active = false
		return

	if not active and absf(_dx()) <= aggro_range:
		active = true


func _dx() -> float:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")

	return target.global_position.x - global_position.x if target else INF


func _target_dead() -> bool:
	if not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")

	if target == null:
		return true

	return target.has_method("is_dead") and target.is_dead()


# =========================
# VIRAR O BOSS
# =========================

func _face(direction: float) -> void:
	if direction == 0.0:
		return

	facing = signf(direction)
	sprite.flip_h = facing < 0.0


# =========================
# MOVIMENTAÇÃO E CONTROLE
# =========================

func _run_state(delta: float) -> void:
	# Gravidade
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# Invulnerabilidade
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta

	# Recuperação do hit
	if current_state == State.HIT:
		hit_timer -= delta
		velocity.x = 0.0

		move_and_slide()

		if hit_timer <= 0.0:
			_return_to_normal()

		return

	# Cooldown dos ataques
	if attack_timer > 0.0:
		attack_timer -= delta

	# Plano B contra ataque travado
	_check_failsafe(delta)

	# Spin Dash
	if current_state == State.MID_ATTACK3:
		_dash_update(delta)
		move_and_slide()
		return

	# Finalização do Spin Dash
	if current_state == State.END_ATTACK3:
		_end_attack3_update(delta)
		velocity.x = 0.0
		move_and_slide()
		return

	# Durante animações de ataque, não se movimenta
	if current_state == State.ATTACK1 \
	or current_state == State.PRE_ATTACK3:
		velocity.x = 0.0
		move_and_slide()
		return

	# Jogador ainda não foi visto (ou morreu)
	if not active:
		velocity.x = 0.0
		_change_state(State.IDLE)
		move_and_slide()
		return

	# Direção e distância até o jogador
	var dx: float = _dx()
	var direction: float = signf(dx)
	var distance: float = absf(dx)

	_face(direction)

	# Decide se ataca ou persegue
	if distance <= attack_range and attack_timer <= 0.0:
		_choose_attack()
		velocity.x = 0.0

	elif distance > attack_range:
		velocity.x = direction * speed
		_change_state(State.WALK)

	else:
		# Perto, mas em cooldown: fica parado esperando
		velocity.x = 0.0
		_change_state(State.IDLE)

	move_and_slide()


## Se a animação do ataque não avisar que terminou, encerra o ataque pelo tempo.
func _check_failsafe(delta: float) -> void:
	if failsafe_timer <= 0.0:
		return

	failsafe_timer -= delta

	if failsafe_timer > 0.0:
		return

	if current_state == State.ATTACK1 \
	or current_state == State.PRE_ATTACK3 \
	or current_state == State.END_ATTACK3:
		_on_animation_finished()


# =========================
# ESCOLHA DO ATAQUE
# =========================

func _choose_attack() -> void:
	hit_window = -1

	# Sorteia entre os ataques (1 = lâmina, 3 = spin dash), evitando repetir o último
	var options: Array[int] = [1, 3]
	options.erase(last_attack)

	var attack_choice: int = options[randi() % options.size()]
	last_attack = attack_choice

	match attack_choice:
		1:
			_start_attack1()

		3:
			_start_attack3()


func _start_attack1() -> void:
	current_state = State.ATTACK1
	_play_timed("atack1")


## Toca a animação e arma o plano B caso ela nunca termine.
func _play_timed(anim: StringName) -> void:
	sprite.play(anim)
	failsafe_timer = _anim_length(anim) + FAILSAFE_MARGIN


## Duração da animação em segundos.
func _anim_length(anim: StringName) -> float:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null or not frames.has_animation(anim):
		return 1.0

	var fps: float = frames.get_animation_speed(anim)
	if fps <= 0.0:
		return 1.0

	var total: float = 0.0
	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)

	return total / fps / maxf(sprite.speed_scale, 0.01)


# =========================
# SPIN DASH
# =========================

func _start_attack3() -> void:
	current_state = State.PRE_ATTACK3

	_update_dash_direction()

	_play_timed("preAtack")


# Calcula a direção do dash e vira o boss para esse lado
func _update_dash_direction() -> void:
	if not _target_dead():
		dash_direction = signf(_dx())

	if dash_direction == 0.0:
		dash_direction = facing

	_face(dash_direction)


func _dash_update(delta: float) -> void:
	dash_timer -= delta

	velocity.x = dash_direction * dash_speed

	if dash_timer <= 0.0:
		_start_end_attack3()


func _start_end_attack3() -> void:
	current_state = State.END_ATTACK3

	velocity.x = 0.0

	end_blade_timer = end_attack_blade_delay

	_play_timed("endAtack")


func _end_attack3_update(delta: float) -> void:
	end_blade_timer -= delta


# =========================
# FINALIZAÇÃO DAS ANIMAÇÕES
# =========================

func _on_animation_finished() -> void:
	if dead:
		if sprite.animation == "death":
			queue_free()
		return

	match current_state:

		State.ATTACK1:
			attack_timer = attack_cooldown
			_return_to_normal()

		State.PRE_ATTACK3:
			# Inicia a execução do Spin Dash (quem manda agora é o dash_timer)
			current_state = State.MID_ATTACK3
			dash_timer = dash_duration
			failsafe_timer = 0.0

			_update_dash_direction()

			# Durante o dash o boss atravessa o jogador (sem empurrar), mas o dano continua
			_set_dash_ghost(true)

			sprite.play("midAtack")

		State.MID_ATTACK3:
			_start_end_attack3()

		State.END_ATTACK3:
			attack_timer = attack_cooldown
			_return_to_normal()

		State.HIT:
			_return_to_normal()


# =========================
# COLISÃO (HURTBOX / HITBOX)
# =========================

## Copia as áreas do momento atual para os nós de colisão: o corpo vai para o Hurtbox
## (desligado quando morto) e, durante os golpes, a área do golpe vai para o Hitbox.
func _update_boxes() -> void:
	var body := Rect2()
	if not dead:
		body = _shifted(body_rect)
	hurtbox.set_rect(body, facing)
	_debug_body = body

	var window: int = -1
	var strike: Rect2 = Rect2()

	match current_state:
		# Golpes de lâmina: só nos quadros das janelas de dano
		State.ATTACK1:
			window = _window_index(sprite.animation, sprite.frame)
			strike = blade_rect

		# Spin Dash: só machuca durante a investida (a preparação é o aviso)
		State.MID_ATTACK3:
			window = 0
			strike = dash_rect

		# Finalização: primeiro o dash, depois a lâmina (janela nova = novo acerto)
		State.END_ATTACK3:
			if end_blade_timer > 0.0:
				window = 0
				strike = dash_rect
			else:
				window = 1
				strike = blade_rect

	if window == -1:
		hitbox.clear()
		_debug_strike = Rect2()
		queue_redraw()
		return

	strike = _shifted(strike)

	if window != hit_window:
		hit_window = window
		hitbox.new_window()

	hitbox.damage = damage

	var rects: Array[Rect2] = [strike]
	hitbox.set_rects(rects, facing)

	_debug_strike = strike
	queue_redraw()


## Aplica o rect_offset a um retângulo.
func _shifted(rect: Rect2) -> Rect2:
	return Rect2(rect.position + rect_offset, rect.size)


## Contorno do que o script está enviando para o Hurtbox/Hitbox.
## Se isto não bater com as formas de colisão do Godot, o problema está nos
## nós Hurtbox/Hitbox; se bater mas não cobrir o desenho, ajuste os retângulos.
func _draw() -> void:
	if not debug_draw:
		return

	if _debug_body.has_area():
		draw_rect(_mirrored(_debug_body), Color(0.2, 0.5, 1.0), false, 1.0)

	if _debug_strike.has_area():
		draw_rect(_mirrored(_debug_strike), Color(1.0, 0.2, 0.2), false, 1.0)


func _mirrored(rect: Rect2) -> Rect2:
	if facing < 0.0:
		return Rect2(-rect.position.x - rect.size.x, rect.position.y, rect.size.x, rect.size.y)
	return rect


## Em qual janela de dano da lâmina o quadro atual está (-1 se em nenhuma).
func _window_index(anim: StringName, frame: int) -> int:
	var windows: Array = BLADE_WINDOWS.get(anim, [])
	var last_frame: int = sprite.sprite_frames.get_frame_count(anim) - 1

	for i in windows.size():
		var window: Vector2i = windows[i]
		var to_frame: int = last_frame if window.y < 0 else window.y

		if frame >= window.x and frame <= to_frame:
			return i

	return -1


# =========================
# RECEBER DANO
# =========================

## Chamado pelo Hurtbox quando um golpe do jogador acerta. Retorna true se causou dano.
func take_hit(_source_x: float, amount: int = 1) -> bool:
	if dead or invulnerability_timer > 0.0:
		return false

	# Atacar o boss também começa a luta
	active = true

	health = maxi(health - amount, 0)
	health_changed.emit(health, max_health)
	invulnerability_timer = invulnerability_duration

	if health <= 0:
		_die()
		return true

	current_state = State.HIT
	hit_timer = hit_duration
	failsafe_timer = 0.0
	_set_dash_ghost(false)

	# Ataque interrompido: não deixa o boss atacar de novo na hora
	attack_timer = maxf(attack_timer, hit_attack_delay)

	velocity.x = 0.0

	sprite.play("hit")
	return true


## Compatibilidade com quem ainda chama take_damage diretamente.
func take_damage(amount: int = 1) -> void:
	take_hit(global_position.x, amount)


# =========================
# MORTE
# =========================

func _die() -> void:
	dead = true
	active = false
	current_state = State.DEATH
	failsafe_timer = 0.0
	_set_dash_ghost(false)

	velocity = Vector2.ZERO

	hitbox.clear()
	hurtbox.set_rect(Rect2(), facing)

	sprite.play("death")
	died.emit()


func _return_to_normal() -> void:
	if dead:
		return

	failsafe_timer = 0.0
	_set_dash_ghost(false)
	_change_state(State.IDLE)


func _change_state(new_state: State) -> void:
	if current_state == new_state:
		return

	current_state = new_state

	match current_state:
		State.IDLE:
			sprite.play("idle")

		State.WALK:
			sprite.play("walk")


## Liga/desliga a colisão física entre o boss e o jogador. Com ela desligada o boss
## atravessa o jogador no dash e não o empurra. O dano não é afetado, pois vem das
## áreas Hurtbox/Hitbox.
func _set_dash_ghost(enabled: bool) -> void:
	if enabled:
		if _ghost_body != null:
			return

		var body := target as PhysicsBody2D
		if body == null:
			return

		_ghost_body = body
		add_collision_exception_with(_ghost_body)
		_ghost_body.add_collision_exception_with(self)
		return

	if is_instance_valid(_ghost_body):
		remove_collision_exception_with(_ghost_body)
		_ghost_body.remove_collision_exception_with(self)

	_ghost_body = null


func _exit_tree() -> void:
	_set_dash_ghost(false)
