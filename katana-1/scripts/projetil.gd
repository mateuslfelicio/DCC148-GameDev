extends Area2D

@export var speed: float = 250.0
@export var damage: int = 1
@export var lifetime: float = 8.0  # tempo até desaparecer (segundos)
@export var impact_scene: PackedScene

var direction: Vector2 = Vector2.RIGHT
var shooter: Node = null
var impacted: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_end)


# Chamado pelo inimigo logo após o add_child
func launch(new_direction: Vector2, new_shooter: Node) -> void:
	direction = new_direction.normalized()
	shooter = new_shooter
	rotation = direction.angle()  # sprite aponta para onde vai


func _physics_process(delta: float) -> void:
	if impacted:
		return

	global_position += direction * speed * delta


func _on_lifetime_end() -> void:
	if is_instance_valid(self) and not impacted:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	if impacted:
		return

	# Ignora quem atirou e outros inimigos
	if body == shooter:
		return
	if body.is_in_group("inimigos") or body.is_in_group("enemy"):
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(damage)

	_create_impact()


func _create_impact() -> void:
	impacted = true
	set_deferred("monitoring", false)

	if impact_scene != null:
		var impact = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position

	queue_free()
