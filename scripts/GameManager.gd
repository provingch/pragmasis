extends Node

## Autoload.

signal game_over

var is_game_over := false

func trigger_game_over() -> void:
	if is_game_over:
		return
	is_game_over = true
	get_tree().paused = true
	game_over.emit()

func restart() -> void:
	# Before reload, so every _ready() in the new scene sees w=0.
	DimensionState.reset()
	AudioManager.reset()
	is_game_over = false
	get_tree().paused = false
	get_tree().reload_current_scene()
