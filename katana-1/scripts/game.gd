extends Node2D

@export var enemy_scene: PackedScene
@export var boss_scene: PackedScene
@export var boss_scene2: PackedScene
@export var spawn_cooldown: float = 3.0
@export var max_enemies: int = 4

@onready var spawn_points: Array[Marker2D] = [
	$Spawn1,
	$Spawn2,
	$Spawn3,
	$Spawn4,
	$Spawn5
]

@onready var boss_spawn_point: Marker2D = $BossMk
@onready var boss_spawn_point2: Marker2D = $BossMk2

var spawn_timer: Timer
var rng := RandomNumberGenerator.new()

# Guarda qual inimigo está ocupando cada spawn
var occupied_spawns: Dictionary = {}

var boss_spawned: bool = false
var boss_spawned2: bool = false

func _ready() -> void:
	rng.randomize()

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
	print("spawnou")
	boss_spawned = true
