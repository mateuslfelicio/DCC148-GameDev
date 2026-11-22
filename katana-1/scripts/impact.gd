extends Node2D

## Efeito de impacto. Some sozinho ao fim da animação. Se a animação "impact" estiver
## com Loop ligado, o sinal animation_finished nunca dispara e os efeitos se acumulam
## na cena; por isso o loop é desligado aqui e há um temporizador como plano B.

const ANIMATION := &"impact"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	var length: float = 0.6
	var frames: SpriteFrames = sprite.sprite_frames

	if frames != null and frames.has_animation(ANIMATION):
		frames.set_animation_loop(ANIMATION, false)
		length = _anim_length(frames, ANIMATION)

	sprite.animation_finished.connect(queue_free)
	sprite.play(ANIMATION)

	# Plano B: some mesmo que o sinal da animação nunca dispare
	get_tree().create_timer(length + 0.25).timeout.connect(queue_free)


func _anim_length(frames: SpriteFrames, anim: StringName) -> float:
	var fps: float = frames.get_animation_speed(anim)
	if fps <= 0.0:
		return 0.6

	var total: float = 0.0
	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)

	return total / fps / maxf(sprite.speed_scale, 0.01)
