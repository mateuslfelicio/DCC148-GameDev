class_name Hurtbox
extends Area2D

## Area onde o personagem pai toma dano. Quem bate e um Hitbox: a fisica do Godot
## detecta que as duas areas se encostaram e o Hitbox chama receive().
## O pai precisa ter take_hit(source_x: float, damage: int) -> bool.


func _ready() -> void:
	monitoring = false # so e detectada, nao detecta nada


## Repassa o golpe para o pai. Retorna true se o golpe foi resolvido (dano ou bloqueio).
func receive(damage: int, source_x: float) -> bool:
	return get_parent().take_hit(source_x, damage)


## Muda o retangulo da area (relativo aos pes, olhando para a direita) e espelha
## conforme `facing`. Um retangulo vazio desliga a area.
func set_rect(r: Rect2, facing: float) -> void:
	var shape_node: CollisionShape2D = get_child(0)
	shape_node.disabled = r.size == Vector2.ZERO
	if shape_node.disabled:
		return
	var center := r.get_center()
	center.x *= facing
	shape_node.position = center
	(shape_node.shape as RectangleShape2D).size = r.size
