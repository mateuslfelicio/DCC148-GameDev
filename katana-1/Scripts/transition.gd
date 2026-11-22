extends CanvasLayer

@onready var rect: ColorRect = $ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	mat = rect.material as ShaderMaterial
	mat.set_shader_parameter("progress", 0.0)
	mat.set_shader_parameter("reverse", false)
	rect.visible = false

## Sombra entra na diagonal e cobre a tela (fica coberta no fim).
func cover(duration := 0.6) -> void:
	mat.set_shader_parameter("reverse", false)
	mat.set_shader_parameter("progress", 0.0)
	rect.visible = true
	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/progress", 1.0, duration)
	await tween.finished

## Sombra continua no mesmo sentido e libera a tela.
func uncover(duration := 0.6) -> void:
	mat.set_shader_parameter("reverse", true)
	mat.set_shader_parameter("progress", 0.0)
	rect.visible = true
	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/progress", 1.0, duration)
	await tween.finished
	# limpa tudo: nada de preto sobrando
	rect.visible = false
	mat.set_shader_parameter("reverse", false)
	mat.set_shader_parameter("progress", 0.0)
