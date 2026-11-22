
extends Area2D

@export var speed: float = 250.0
@export var damage: int = 1
@export var lifetime: float = 5.0
@export var impact_scene: PackedScene

var direction: Vector2 = Vector2.RIGHT
var impacted: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if impacted:
		return

	global_position += direction * speed * delta

	lifetime -= delta

	if lifetime <= 0:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if impacted:
		return

	if body.is_in_group("enemy"):
		return

	# Causa dano se acertar o jogador
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)

	_create_impact()


func _create_impact() -> void:
	impacted = true

	# Para de detectar colisões e movimentação
	set_deferred("monitoring", false)

	if impact_scene != null:
		var impact = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position

	queue_free()
