extends Node3D

const OPTIONS := preload("res://scenes/ui/Options.tscn")

## Debug: PgUp / PgDn jump straight to the previous / next world (with
## Shift: a whole stratum), landing where the room you're in sets arrivals
## down (RoomGenerator.landing). Off by default: tick it here, or run with
## `-- --saltar-mundos`. `-- --mundo=<id>` (e.g. --mundo=jaula) starts the
## run in that world.
@export var debug_world_jump := false

@onready var rooms_root: Node3D = $Rooms
@onready var player: Node3D = $Player

func _ready() -> void:
	GameManager.start_run()
	RoomGenerator.init_world(rooms_root, player, DimensionState.player_w)
	var args := OS.get_cmdline_user_args()
	debug_world_jump = debug_world_jump or args.has("--saltar-mundos")
	for a in args:
		if a.begins_with("--mundo="):
			for w in Worlds.ids():
				if Worlds.def(w).id == a.trim_prefix("--mundo="):
					jump_to(w)

## ESC pauses into the options screen; closing it resumes.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not get_tree().paused:
		get_viewport().set_input_as_handled()
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		var options := OPTIONS.instantiate()
		options.in_game = true
		options.closed.connect(func() -> void:
			get_tree().paused = false
			if Player.capture_mouse:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
		add_child(options)
	var key := event as InputEventKey
	if debug_world_jump and key and key.pressed and not key.echo and key.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		var ids := Worlds.ids()
		var step := (1 if key.keycode == KEY_PAGEDOWN else -1) * (Worlds.STRATUM_SIZE if key.shift_pressed else 1)
		jump_to(ids[posmod(ids.find(DimensionState.player_w) + step, ids.size())])

func jump_to(w: int) -> void:
	DimensionState.request_shift(w)
