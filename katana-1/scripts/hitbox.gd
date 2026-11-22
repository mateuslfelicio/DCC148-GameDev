class_name Hitbox
extends Area2D

## Area de golpe. O pai liga os retangulos do quadro atual com set_rects() e a fisica
## do Godot diz quais Hurtbox estao encostando. Cada Hurtbox e atingida no maximo uma
## vez por janela de golpe (um golpe bloqueado tambem conta); o pai chama new_window()
## quando uma janela nova comeca.
## As formas sao criadas aqui conforme a necessidade (o boss usa varias por quadro).

## Dano de cada acerto da janela atual.
var damage := 1

var _shapes: Array[CollisionShape2D] = []
var _already_hit: Array[Area2D] = []


func _ready() -> void:
	monitorable = false # so detecta, ninguem precisa detecta-la


## Liga um retangulo de colisao por item de `rects` (relativos aos pes, olhando para a
## direita) e espelha conforme `facing`. Os que sobram ficam desligados.
func set_rects(rects: Array[Rect2], facing: float) -> void:
	while _shapes.size() < rects.size():
		var shape_node := CollisionShape2D.new()
		shape_node.shape = RectangleShape2D.new()
		add_child(shape_node)
		_shapes.append(shape_node)
	for i in _shapes.size():
		var shape_node := _shapes[i]
		shape_node.disabled = i >= rects.size()
		if shape_node.disabled:
			continue
		var center := rects[i].get_center()
		center.x *= facing
		shape_node.position = center
		(shape_node.shape as RectangleShape2D).size = rects[i].size


## Desliga todos os retangulos (fora dos quadros ativos).
func clear() -> void:
	var none: Array[Rect2] = []
	set_rects(none, 1.0)


## Comeca uma janela de golpe nova: quem ja foi atingido pode ser atingido de novo.
func new_window() -> void:
	_already_hit.clear()


func is_active() -> bool:
	return _shapes.any(func(s: CollisionShape2D) -> bool: return not s.disabled)


func _physics_process(_delta: float) -> void:
	if not is_active():
		return
	for area in get_overlapping_areas():
		if area is Hurtbox and area not in _already_hit:
			if area.receive(damage, _source_x(area)):
				_already_hit.append(area)


## Posicao x do retangulo ligado mais perto de quem foi atingido: o empurrao e para longe
## do golpe, nao do dono (no ataque 6 do boss a onda fica do outro lado dele).
func _source_x(area: Area2D) -> float:
	var best := global_position.x
	var best_distance := INF
	for shape_node in _shapes:
		if shape_node.disabled:
			continue
		var distance := absf(shape_node.global_position.x - area.global_position.x)
		if distance < best_distance:
			best_distance = distance
			best = shape_node.global_position.x
	return best
