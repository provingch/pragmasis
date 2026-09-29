extends CanvasLayer

## With anchors: depth, record and sequences. Without: the worlds this run
## went through, and retry (same start world) or back to the menu.

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
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameManager.game_over.connect(_on_game_over)

func _on_game_over() -> void:
	AudioManager.play_sfx(&"game_over")
	var w := DimensionState.player_w
	if GameManager.mode.anchors:
		detail.text = "%s EN %s\nPROFUNDIDAD %d  //  RÉCORD %d  //  %d SECUENCIAS" % [
			GameManager.cause, Worlds.def(w).display_name, GameManager.score() + 1, GameManager.best + 1, GameManager.sequence - 1]
	else:
		var names := PackedStringArray()
		for v in GameManager.visited:
			names.append(Worlds.def(v).display_name)
		title.text = "FIN DE DERIVA"
		detail.text = "%s EN %s\nMUNDOS VISITADOS (%d)\n%s" % [GameManager.cause, Worlds.def(w).display_name, names.size(), "  ·  ".join(names)]
		hint.text = "[ R ] REINTENTAR EN %s   //   [ ESC ] VOLVER AL MENÚ" % Worlds.def(GameManager.mode.start_world()).display_name
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
	elif visible and not GameManager.mode.anchors and event.is_action_pressed("ui_cancel"):
		GameManager.to_menu()
