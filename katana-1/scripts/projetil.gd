extends Area2D

@export var speed: float = 250.0
@export var damage: int = 1
## Tempo até desaparecer (segundos).
@export var lifetime: float = 8.0
## Distância máxima percorrida antes de desaparecer (pixels). Evita projéteis
## voando para sempre quando não batem em nada.
@export var max_distance: float = 1500.0
@export var impact_scene: PackedScene

var direction: Vector2 = Vector2.RIGHT
var shooter: Node = null
var impacted: bool = false

var _travelled: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


# Chamado pelo inimigo logo após o add_child
func launch(new_direction: Vector2, new_shooter: Node) -> void:
	direction = new_direction.normalized()
	shooter = new_shooter
	rotation = direction.angle()  # sprite aponta para onde vai


func _physics_process(delta: float) -> void:
	if impacted:
		return

	var step: Vector2 = direction * speed * delta
	global_position += step

	_travelled += step.length()
	lifetime -= delta

	if lifetime <= 0.0 or _travelled >= max_distance:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if impacted:
		return

	# Ignora quem atirou e outros inimigos
	if body == shooter:
		return
	if body.is_in_group("inimigos") \
	or body.is_in_group("enemy") \
	or body.is_in_group("enemies"):
		return

	if body.is_in_group("player"):
		if body.has_method("take_hit"):
			body.take_hit(global_position.x, damage)
		elif body.has_method("take_damage"):
			body.take_damage(damage)

	_create_impact()


func _create_impact() -> void:
	impacted = true
	set_deferred("monitoring", false)

	if impact_scene != null:
		var impact: Node2D = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position

	queue_free()
