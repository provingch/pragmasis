extends Node3D

const OPTIONS := preload("res://scenes/ui/Options.tscn")

@onready var rooms_root: Node3D = $Rooms
@onready var player: Node3D = $Player

func _ready() -> void:
	GameManager.start_run()
	RoomGenerator.init_world(rooms_root, player, DimensionState.player_w)

## ESC pauses into the options screen; closing it resumes.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var options := OPTIONS.instantiate()
		options.closed.connect(func() -> void:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		add_child(options)
