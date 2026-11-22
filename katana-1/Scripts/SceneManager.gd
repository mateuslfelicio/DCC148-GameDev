extends Node

func changeSceneTo(scene : PackedScene):
	await Transition.cover()
	get_tree().change_scene_to_packed(scene)
	await Transition.uncover()
