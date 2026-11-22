extends CharacterBody2D

@export var speed: float = 60.0
@export var gravity: float = 980.0
@export var stopping_distance: float = 80.0
@export var projectile_scene: PackedScene

# Vida
@export var max_health: int = 3
@export var hit_invulnerability: float = 0.35

## Folga (px) somada em volta do CollisionShape2D para formar a área onde o inimigo
## recebe dano.
const HURTBOX_MARGIN := 2.0

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var shoot_timer: Timer = $Timer
@onready var shoot_point: Marker2D = $ShootPoint

## Nó Hurtbox (opcional): é por ele que o golpe do jogador acerta o inimigo.
@onready var hurtbox: Node = get_node_or_null("Hurtbox")

var player: CharacterBody2D = null
var active: bool = false
var dead: bool = false

var health: int
var hit_timer: float = 0.0
var invulnerability_timer: float = 0.0
var shoot_offset_x: float = 0.0

var is_hit: bool = false

# Animação que tocava antes de levar o golpe (volta para ela depois do hit)
var _resume_anim: StringName = &"idle"

# Lado para onde o inimigo olha (1 = direita, -1 = esquerda)
var facing: float = 1.0

# Área do corpo (olhando para a direita), tirada do CollisionShape2D
var body_rect: Rect2 = Rect2()


func _ready() -> void:
	health = max_health
	shoot_offset_x = abs(shoot_point.position.x)

	add_to_group("enemy")
	add_to_group("enemies")

	body_rect = _shape_rect()
	_setup_animations()
	sprite.play("idle")

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	sprite.animation_finished.connect(_on_animation_finished)


## Animações de dano e morte precisam terminar (sem loop) para o inimigo sumir.
func _setup_animations() -> void:
	var frames: SpriteFrames = sprite.sprite_frames
	if frames == null:
		return

	for anim in [&"hit", &"death"]:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)


func _physics_process(delta: float) -> void:
	if dead:
		return

	_update_hurtbox()

	# Gravidade
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0

	# Invulnerabilidade
	if invulnerability_timer > 0.0:
		invulnerability_timer -= delta

	# Recuperação após tomar dano
	if is_hit:
		hit_timer -= delta
		velocity.x = 0.0

		if hit_timer <= 0.0:
			is_hit = false
			_leave_hit_animation()

		move_and_slide()
		return

	# Sem jogador detectado
	if not active or not is_instance_valid(player):
		velocity.x = 0.0
		move_and_slide()
		return

	# Distância até o jogador
	var distance_x: float = abs(player.global_position.x - global_position.x)

	# Direção
	var direction: float = sign(player.global_position.x - global_position.x)

	# Vira o sprite e ajusta o ponto de tiro
	if direction != 0:
		facing = direction
		sprite.flip_h = direction < 0
		shoot_point.position.x = shoot_offset_x * (-1.0 if direction < 0 else 1.0)

	# Perseguição normal
	if distance_x > stopping_distance:
		velocity.x = direction * speed
	else:
		velocity.x = 0.0

	move_and_slide()


# =========================
# HURTBOX (ONDE O JOGADOR ACERTA O INIMIGO)
# =========================

## Área do corpo a partir do CollisionShape2D do próprio inimigo.
func _shape_rect() -> Rect2:
	for child in get_children():
		var collision := child as CollisionShape2D
		if collision == null or collision.shape == null:
			continue

		var size := Vector2.ZERO
		var shape: Shape2D = collision.shape

		if shape is RectangleShape2D:
			size = shape.size
		elif shape is CapsuleShape2D:
			size = Vector2(shape.radius * 2.0, shape.height)
		elif shape is CircleShape2D:
			size = Vector2(shape.radius * 2.0, shape.radius * 2.0)
		else:
			continue

		size += Vector2(HURTBOX_MARGIN, HURTBOX_MARGIN) * 2.0
		return Rect2(collision.position - size * 0.5, size)

	return Rect2(-12, -24, 24, 24)


func _update_hurtbox() -> void:
	if hurtbox != null and hurtbox.has_method("set_rect"):
		hurtbox.set_rect(body_rect, facing)


func _clear_hurtbox() -> void:
	if hurtbox != null and hurtbox.has_method("set_rect"):
		hurtbox.set_rect(Rect2(), facing)


# =========================
# DETECÇÃO DO JOGADOR
# =========================

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	player = body
	active = true

	if sprite.sprite_frames.has_animation("wake"):
		sprite.play("wake")

	if shoot_timer.is_stopped():
		shoot_timer.start()


func _on_body_exited(body: Node2D) -> void:
	if body != player:
		return

	player = null
	active = false
	velocity.x = 0.0

	shoot_timer.stop()

	if not is_hit:
		if sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")


# =========================
# TIRO
# =========================

func _on_shoot_timer_timeout() -> void:
	if dead or not active or not is_instance_valid(player):
		return

	if projectile_scene == null:
		return

	# Garante que o ponto de tiro está do lado certo
	var side: float = -1.0 if sprite.flip_h else 1.0
	shoot_point.position.x = shoot_offset_x * side

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	Sfx.play_at(&"enemy_shoot", shoot_point.global_position)
	projectile.global_position = shoot_point.global_position

	var direction: Vector2 = (
		player.global_position - shoot_point.global_position
	).normalized()

	if projectile.has_method("launch"):
		projectile.launch(direction, self)
	elif "direction" in projectile:
		projectile.direction = direction


# =========================
# RECEBER DANO
# =========================

## Chamado pelo Hurtbox quando um golpe do jogador acerta. Retorna true se causou dano.
func take_hit(_source_x: float, amount: int = 1) -> bool:
	if dead or invulnerability_timer > 0.0:
		return false

	health -= amount
	invulnerability_timer = hit_invulnerability
	Sfx.play_at(&"enemy_hurt", global_position)

	if health <= 0:
		die()
		return true

	is_hit = true
	hit_timer = _hit_duration()

	if sprite.animation != &"hit":
		_resume_anim = sprite.animation

	velocity.x = 0.0

	if sprite.sprite_frames.has_animation("hit"):
		sprite.play("hit")

	return true


## Tempo parado levando o golpe: pelo menos 0,15 s e a animação "hit" inteira.
func _hit_duration() -> float:
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("hit"):
		return maxf(0.15, _anim_length(&"hit"))
	return 0.15


## Sai da animação "hit": volta para a que tocava antes (ou idle, se o jogador saiu).
func _leave_hit_animation() -> void:
	if dead:
		return

	var frames: SpriteFrames = sprite.sprite_frames
	var anim: StringName = _resume_anim if active else &"idle"

	if anim == &"hit" or not frames.has_animation(anim):
		anim = &"idle"

	if frames.has_animation(anim):
		sprite.play(anim)


## Compatibilidade com quem chama take_damage diretamente.
func take_damage(amount: int = 1) -> void:
	take_hit(global_position.x, amount)


func die() -> void:
	dead = true
	Sfx.play_at(&"enemy_death", global_position)
	active = false
	is_hit = false

	velocity = Vector2.ZERO

	shoot_timer.stop()
	detection_area.set_deferred("monitoring", false)
	_clear_hurtbox()

	# Sai da contagem de inimigos vivos (usada pelo spawner)
	remove_from_group("enemy")

	var frames: SpriteFrames = sprite.sprite_frames
	if frames != null and frames.has_animation("death"):
		sprite.play("death")

		# Plano B: some mesmo que a animação nunca avise que terminou
		get_tree().create_timer(_anim_length(&"death") + 0.3).timeout.connect(queue_free)
	else:
		queue_free()


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


func _on_animation_finished() -> void:
	if dead and sprite.animation == "death":
		queue_free()
		return

	# Acabou a animação de hit: não deixa o inimigo preso no último quadro
	if not dead and sprite.animation == "hit" and not is_hit:
		_leave_hit_animation()
