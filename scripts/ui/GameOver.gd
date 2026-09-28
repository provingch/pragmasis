extends CanvasLayer

@onready var root: Control = $Control
@onready var title: Label = $Control/VBox/Title
@onready var detail: Label = $Control/VBox/Detail
@onready var hint: Label = $Control/VBox/Hint

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	title.add_theme_font_override("font", Fonts.heavy)
	for l: Label in [detail, hint]:
		l.add_theme_font_override("font", Fonts.mono)
	GameManager.game_over.connect(_on_game_over)

func _on_game_over() -> void:
	AudioManager.play_sfx(&"game_over")
	var w := DimensionState.player_w
	detail.text = "%s EN %s\nSECUENCIAS COMPLETADAS %02d  //  RÉCORD %02d" % [
		GameManager.cause, Worlds.def(w).display_name, GameManager.score(), GameManager.best]
	visible = true
	# Slam in: overshoot then settle, like a signal locking on.
	root.modulate.a = 0.0
	title.scale = Vector2(1.6, 0.2)
	title.pivot_offset = title.size / 2.0
	var tw := create_tween().set_parallel()
	tw.tween_property(root, "modulate:a", 1.0, 0.25)
	tw.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if visible:
		hint.modulate.a = 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.6 else 0.2
		title.position.x = randf_range(-3.0, 3.0) if randf() < 0.08 else 0.0

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("restart"):
		GameManager.restart()
