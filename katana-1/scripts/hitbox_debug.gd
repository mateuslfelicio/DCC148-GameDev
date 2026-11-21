extends Node2D

## Desenha as areas de colisao de combate do personagem pai. Aperte F3 para ligar/desligar.
## Verde = Hurtbox (onde ele toma dano); vermelho = Hitbox (onde o golpe dele acerta).
## So os retangulos ligados aparecem. (Debug > Visible Collision Shapes mostra tudo.)

static var enabled := false
static var _toggled_on_frame := -1


func _ready() -> void:
	z_index = 100


func _process(_delta: float) -> void:
	# Varias instancias leem a mesma tecla; so a primeira de cada quadro alterna.
	if Input.is_action_just_pressed("debug_hitboxes") and _toggled_on_frame != Engine.get_process_frames():
		_toggled_on_frame = Engine.get_process_frames()
		enabled = not enabled
	queue_redraw()


func _draw() -> void:
	if not enabled:
		return
	for area in get_parent().get_children():
		if area is Hurtbox:
			_draw_area(area, Color(0.2, 1.0, 0.3))
		elif area is Hitbox:
			_draw_area(area, Color(1.0, 0.2, 0.2))


func _draw_area(area: Area2D, color: Color) -> void:
	for shape_node in area.get_children():
		if shape_node is CollisionShape2D and not shape_node.disabled \
				and shape_node.shape is RectangleShape2D:
			var size: Vector2 = shape_node.shape.size
			var local := Rect2(shape_node.global_position - size / 2.0 - global_position, size)
			draw_rect(local, Color(color, 0.25))
			draw_rect(local, color, false, 1.0)
