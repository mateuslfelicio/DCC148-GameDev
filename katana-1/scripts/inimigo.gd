extends CharacterBody2D

@export var speed: float = 60.0
@export var gravity: float = 980.0
@export var stopping_distance: float = 80.0
@export var projectile_scene: PackedScene

# Vida
@export var max_health: int = 3
@export var hit_invulnerability: float = 0.35

@onready var sprite: AnimatedSprite2D = $Sprite2D
@onready var detection_area: Area2D = $DetectionArea
@onready var shoot_timer: Timer = $Timer
@onready var shoot_point: Marker2D = $ShootPoint

var player: CharacterBody2D = null
var active: bool = false
var dead: bool = false

var health: int
var hit_timer: float = 0.0
var invulnerability_timer: float = 0.0
var shoot_offset_x: float = 0.0

var is_hit: bool = false


func _ready() -> void:
	health = max_health
	shoot_offset_x = abs(shoot_point.position.x)
	sprite.play("idle")

	detection_area.body_entered.connect(_on_body_entered)
	detection_area.body_exited.connect(_on_body_exited)
	shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	sprite.animation_finished.connect(_on_animation_finished)


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

	# Recuperação após tomar dano
	if is_hit:
		hit_timer -= delta
		velocity.x = 0.0

		if hit_timer <= 0.0:
			is_hit = false

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
		sprite.flip_h = direction < 0
		shoot_point.position.x = shoot_offset_x * (-1.0 if direction < 0 else 1.0)

	# Perseguição normal
	if distance_x > stopping_distance:
		velocity.x = direction * speed
	else:
		velocity.x = 0.0

	move_and_slide()
	
	if is_on_wall():
		print("Estou batendo em uma parede!")


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


func _on_shoot_timer_timeout() -> void:
	if dead or not active or not is_instance_valid(player):
		return

	if projectile_scene == null:
		return

	# Garante que o ponto de tiro está do lado certo
	var facing: float = -1.0 if sprite.flip_h else 1.0
	shoot_point.position.x = shoot_offset_x * facing

	var projectile = projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = shoot_point.global_position

	var direction: Vector2 = (
		player.global_position - shoot_point.global_position
	).normalized()

	if projectile.has_method("launch"):
		projectile.launch(direction, self)

	if "direction" in projectile:
		projectile.direction = direction


func take_damage(amount: int = 1) -> void:
	if dead or invulnerability_timer > 0.0:
		return

	health -= amount
	invulnerability_timer = hit_invulnerability

	if health <= 0:
		die()
		return

	is_hit = true
	hit_timer = 0.15

	velocity.x = 0.0

	if sprite.sprite_frames.has_animation("hit"):
		sprite.play("hit")


func die() -> void:
	dead = true
	active = false
	is_hit = false

	velocity = Vector2.ZERO

	shoot_timer.stop()
	detection_area.set_deferred("monitoring", false)

	if sprite.sprite_frames.has_animation("death"):
		sprite.play("death")
	else:
		queue_free()


func _on_animation_finished() -> void:
	if dead and sprite.animation == "death":
		queue_free()
