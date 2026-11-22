extends CharacterBody2D

# =========================
# CONFIGURAÇÕES
# =========================

@export var speed: float = 80.0
@export var gravity: float = 980.0

@export var max_health: int = 20
@export var damage: int = 1

@export var attack_range: float = 100.0
@export var attack_cooldown: float = 1.5

# Spin Dash
@export var dash_speed: float = 450.0
@export var dash_duration: float = 0.7
@export var end_attack_blade_delay: float = 0.15

# Hit
@export var hit_duration: float = 0.3
@export var invulnerability_duration: float = 0.4


# =========================
# NÓS
# =========================

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

@onready var blade_hitbox: Area2D = $BladeHitbox
@onready var dash_hitbox: Area2D = $DashHitbox

@onready var detection_area: Area2D = $DetectionArea


# =========================
# ESTADOS
# =========================

enum State {
	IDLE,
	WALK,
	ATTACK1,
	ATTACK2,
	PRE_ATTACK3,
	MID_ATTACK3,
	END_ATTACK3,
	HIT,
	DEATH
}

var current_state: State = State.IDLE

var player: CharacterBody2D = null

var active: bool = false
var health: int
var dead: bool = false

var attack_timer: float = 0.0
var dash_timer: float = 0.0
var end_blade_timer: float = 0.0
var hit_timer: float = 0.0
var invulnerability_timer: float = 0.0

var dash_direction: float = 0.0

# Impede que um mesmo ataque cause dano várias vezes
var already_hit_player: bool = false


# =========================
# INICIALIZAÇÃO
# =========================

func _ready() -> void:
	health = max_health

	blade_hitbox.monitoring = false
	dash_hitbox.monitoring = false

	blade_hitbox.body_entered.connect(_on_attack_hit)
	dash_hitbox.body_entered.connect(_on_attack_hit)

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)

	sprite.animation_finished.connect(_on_animation_finished)

	sprite.play("idle")


# =========================
# MOVIMENTAÇÃO E CONTROLE
# =========================

func _physics_process(delta: float) -> void:
	if dead:
		return

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
	or current_state == State.ATTACK2 \
	or current_state == State.PRE_ATTACK3:
		velocity.x = 0.0
		move_and_slide()
		return

	# Sem player detectado
	if not active or not is_instance_valid(player):
		velocity.x = 0.0
		_change_state(State.IDLE)
		move_and_slide()
		return

	# Direção do jogador
	var direction: float = sign(player.global_position.x - global_position.x)
	var distance: float = abs(player.global_position.x - global_position.x)

	if direction != 0.0:
		sprite.flip_h = direction < 0

	# Decide se ataca ou persegue
	if distance <= attack_range and attack_timer <= 0.0:
		_choose_attack()
		velocity.x = 0.0

	elif distance > attack_range:
		velocity.x = direction * speed
		_change_state(State.WALK)

	else:
		velocity.x = 0.0
		_change_state(State.IDLE)

	move_and_slide()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	player = body
	active = true


func _on_body_exited(body: Node2D) -> void:
	if body != player:
		return

	player = null
	active = false
	velocity.x = 0.0

	if current_state == State.WALK:
		_change_state(State.IDLE)


func _choose_attack() -> void:
	already_hit_player = false

	var attack_choice: int = randi_range(1, 3)

	match attack_choice:
		1:
			_start_attack1()

		2:
			_start_attack2()

		3:
			_start_attack3()


func _start_attack1() -> void:
	current_state = State.ATTACK1

	blade_hitbox.monitoring = true
	dash_hitbox.monitoring = false

	sprite.play("attack1")

func _start_attack2() -> void:
	current_state = State.ATTACK2

	blade_hitbox.monitoring = true
	dash_hitbox.monitoring = false

	sprite.play("attack2")


func _start_attack3() -> void:
	current_state = State.PRE_ATTACK3

	blade_hitbox.monitoring = false
	dash_hitbox.monitoring = true

	if is_instance_valid(player):
		dash_direction = sign(player.global_position.x - global_position.x)

	if dash_direction == 0.0:
		dash_direction = 1.0

	sprite.play("pre_attack3")


func _dash_update(delta: float) -> void:
	dash_timer -= delta

	velocity.x = dash_direction * dash_speed

	if dash_timer <= 0.0:
		_start_end_attack3()


func _start_end_attack3() -> void:
	current_state = State.END_ATTACK3

	velocity.x = 0.0

	# Primeiro momento: dash ainda ativo
	dash_hitbox.monitoring = true
	blade_hitbox.monitoring = false

	end_blade_timer = end_attack_blade_delay

	sprite.play("end_attack3")


func _end_attack3_update(delta: float) -> void:
	end_blade_timer -= delta

	# Troca dash pela lâmina após o delay
	if end_blade_timer <= 0.0:
		dash_hitbox.monitoring = false
		blade_hitbox.monitoring = true


func _on_animation_finished() -> void:
	if dead:
		if sprite.animation == "death":
			queue_free()
		return

	match current_state:

		State.ATTACK1, State.ATTACK2:
			blade_hitbox.monitoring = false
			dash_hitbox.monitoring = false

			attack_timer = attack_cooldown
			_return_to_normal()

		State.PRE_ATTACK3:
			# Inicia a execução do Spin Dash
			current_state = State.MID_ATTACK3
			dash_timer = dash_duration

			if is_instance_valid(player):
				dash_direction = sign(player.global_position.x - global_position.x)

			if dash_direction == 0.0:
				dash_direction = 1.0

			sprite.play("mid_attack3")

		State.MID_ATTACK3:
			_start_end_attack3()

		State.END_ATTACK3:
			blade_hitbox.monitoring = false
			dash_hitbox.monitoring = false

			attack_timer = attack_cooldown
			_return_to_normal()

		State.HIT:
			_return_to_normal()


# =========================
# RECEBER DANO
# =========================

func take_damage(amount: int = 1) -> void:
	if dead or invulnerability_timer > 0.0:
		return

	health -= amount
	invulnerability_timer = invulnerability_duration

	if health <= 0:
		_die()
		return

	blade_hitbox.monitoring = false
	dash_hitbox.monitoring = false

	current_state = State.HIT
	hit_timer = hit_duration

	velocity.x = 0.0

	sprite.play("hit")


func _die() -> void:
	dead = true
	active = false
	current_state = State.DEATH

	velocity = Vector2.ZERO

	blade_hitbox.monitoring = false
	dash_hitbox.monitoring = false

	sprite.play("death")

func _on_attack_hit(body: Node2D) -> void:
	if dead or already_hit_player:
		return

	if not body.is_in_group("player"):
		return

	already_hit_player = true

	if body.has_method("take_damage"):
		body.take_damage(damage)


func _return_to_normal() -> void:
	if dead:
		return

	blade_hitbox.monitoring = false
	dash_hitbox.monitoring = false

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
