extends CanvasLayer

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameManager.game_over.connect(_on_game_over)

func _on_game_over() -> void:
	visible = true

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("restart"):
		GameManager.restart()
