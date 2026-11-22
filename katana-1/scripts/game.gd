extends Node2D

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene
@export var boss_scene2: PackedScene
@export var spawn_cooldown: float = 3.0
@export var max_enemies: int = 4

const BOUNDS_THICKNESS: float = 32.0
# Altura extra acima da fase para o player não pular por cima da parede
const BOUNDS_EXTRA_HEIGHT: float = 1000.0

@onready var spawn_points: Array[Marker2D] = [
	$Spawn1,
	$Spawn2,
	$Spawn3,
	$Spawn4,
	$Spawn5
]

@onready var boss_spawn_point: Marker2D = $BossMk

@onready var camera: Camera2D = $Player/Camera2D

# Camadas usadas para calcular os limites da fase
@onready var level_layers: Array[TileMapLayer] = [
	$Fundo,
	$Diversos,
	$Props,
	$Plataforms,
	$Diversos2
]
@onready var boss_spawn_point2: Marker2D = $BossMk2

var spawn_timer: Timer
var rng := RandomNumberGenerator.new()

# Guarda qual inimigo está ocupando cada spawn
var occupied_spawns: Dictionary = {}

var boss_spawned: bool = false
var boss_spawned2: bool = false

func _ready() -> void:
	rng.randomize()

	var level_rect := _get_level_rect()
	_setup_camera_limits(level_rect)
	_setup_level_bounds(level_rect)

	spawn_timer = Timer.new()
	spawn_timer.wait_time = spawn_cooldown
	spawn_timer.timeout.connect(_spawn_enemy)
	add_child(spawn_timer)

	# Tenta criar o primeiro inimigo imediatamente
	_spawn_enemy()
	spawn_boss()
	spawn_boss2()
	spawn_timer.start()


func _spawn_enemy() -> void:
	if enemy_scene == null:
		return

	var enemies = get_tree().get_nodes_in_group("enemy")

	if enemies.size() >= max_enemies:
		return

	# Procura spawns livres
	var available_spawns: Array[Marker2D] = []

	for spawn_point in spawn_points:
		if not occupied_spawns.has(spawn_point):
			available_spawns.append(spawn_point)
		elif not is_instance_valid(occupied_spawns[spawn_point]):
			# O inimigo anterior morreu
			occupied_spawns.erase(spawn_point)
			available_spawns.append(spawn_point)

	# Se todos os spawns estão ocupados, espera
	if available_spawns.is_empty():
		return

	# Escolhe um spawn livre aleatoriamente
	var spawn_point = available_spawns[
		rng.randi_range(0, available_spawns.size() - 1)
	]

	# Cria o inimigo
	var enemy = enemy_scene.instantiate()

	enemy.global_position = spawn_point.global_position
	add_child(enemy)

	# Marca o spawn como ocupado
	occupied_spawns[spawn_point] = enemy


func spawn_boss() -> void:
	if boss_spawned:
		return

	if boss_scene == null:
		return

	var boss = boss_scene.instantiate()
	boss.global_position = boss_spawn_point.global_position

	add_child(boss)

	boss_spawned = true


func spawn_boss2() -> void:
	if boss_spawned2:
		return

	if boss_scene2 == null:
		return

	var boss2 = boss_scene2.instantiate()
	boss2.global_position = boss_spawn_point2.global_position

	add_child(boss2)

	boss_spawned2 = true


func _get_level_rect() -> Rect2:
	# Junta a área ocupada por todas as camadas de tiles
	var level_rect := Rect2()
	var first := true

	for layer in level_layers:
		var used := layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue

		var tile_size := Vector2(layer.tile_set.tile_size)
		var top_left := layer.to_global(Vector2(used.position) * tile_size)
		var bottom_right := layer.to_global(Vector2(used.end) * tile_size)
		var rect := Rect2(top_left, bottom_right - top_left)

		level_rect = rect if first else level_rect.merge(rect)
		first = false

	return level_rect


func _setup_level_bounds(level_rect: Rect2) -> void:
	# Paredes invisíveis nas pontas da fase para ninguém cair para fora
	var height := level_rect.size.y + BOUNDS_EXTRA_HEIGHT
	var center_y := level_rect.end.y - height * 0.5

	_create_wall("LevelBoundLeft", Vector2(level_rect.position.x - BOUNDS_THICKNESS * 0.5, center_y), height)
	_create_wall("LevelBoundRight", Vector2(level_rect.end.x + BOUNDS_THICKNESS * 0.5, center_y), height)


func _create_wall(wall_name: String, wall_position: Vector2, height: float) -> void:
	var wall := StaticBody2D.new()
	wall.name = wall_name
	wall.collision_mask = 0
	wall.global_position = wall_position

	var shape := RectangleShape2D.new()
	shape.size = Vector2(BOUNDS_THICKNESS, height)

	var collision := CollisionShape2D.new()
	collision.shape = shape
	wall.add_child(collision)

	add_child(wall)


func _setup_camera_limits(level_rect: Rect2) -> void:
	camera.limit_left = roundi(level_rect.position.x)
	camera.limit_top = roundi(level_rect.position.y)
	camera.limit_right = roundi(level_rect.end.x)
	camera.limit_bottom = roundi(level_rect.end.y)

	# Evita que a suavização da câmera passe dos limites
	camera.limit_smoothed = true

	# Se a janela for maior que a fase, centraliza em vez de grudar no canto
	var view_size := get_viewport_rect().size / camera.zoom
	if view_size.x > level_rect.size.x:
		var extra := (view_size.x - level_rect.size.x) * 0.5
		camera.limit_left = roundi(level_rect.position.x - extra)
		camera.limit_right = roundi(level_rect.end.x + extra)
	if view_size.y > level_rect.size.y:
		var extra := (view_size.y - level_rect.size.y) * 0.5
		camera.limit_top = roundi(level_rect.position.y - extra)
		camera.limit_bottom = roundi(level_rect.end.y + extra)
