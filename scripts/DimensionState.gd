extends Node

## Autoload. Tracks which world (a Worlds id: "w", the 4th coordinate) the
## player is in. All worlds share the same x/z room grid; only the active
## one is attached to the scene tree (see RoomGenerator). What each world
## is lives in its WorldDef (res://worlds/).

signal layer_changed(new_w: int)

# Destination room may have a portal at the same corner the player lands on;
# without this, shifts would chain instantly.
const SHIFT_COOLDOWN_MS := 800

var player_w := 0
var _last_shift_ms := -SHIFT_COOLDOWN_MS

func _ready() -> void:
	player_w = Worlds.start()

func reset() -> void:
	player_w = Worlds.start()
	_last_shift_ms = -SHIFT_COOLDOWN_MS

func request_phase_shift(direction: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_shift_ms < SHIFT_COOLDOWN_MS:
		return
	var new_w := Worlds.neighbor(player_w, direction)
	if new_w < 0:
		return
	_last_shift_ms = now
	player_w = new_w
	# Called from a portal's body_entered, and physics objects can't leave the
	# tree mid-callback, so swap on the next process step. Not call_deferred:
	# attaching a never-seen layer during the message-queue flush costs ~1 s
	# of GPU on the next frame (measured on the integrated GPU); from
	# process_frame it doesn't.
	get_tree().process_frame.connect(RoomGenerator.switch_layer.bind(player_w), CONNECT_ONE_SHOT)
	layer_changed.emit(player_w)
