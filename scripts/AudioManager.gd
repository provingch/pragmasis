extends Node

## Autoload. One ambient track per w-layer plus the chase track. All four
## loop from launch and are mixed only by volume, so every switch is a
## cross-fade and each track keeps its place while silent.
##
## Exactly one track dominates: the chase while the entity hunts, otherwise
## the ambient of the layer the player is in. A layer change mid-chase only
## retargets which ambient comes back when the chase ends.

const FADE_TIME := 1.5
const SILENT_DB := -80.0

@onready var chase_player: AudioStreamPlayer = $ChasePlayer
@onready var ambient_players: Dictionary[int, AudioStreamPlayer] = {
	-1: $AmbientSedimento,
	0: $AmbientUmbral,
	1: $AmbientEter,
}

## Layer whose ambient plays (or will, once the chase ends).
var _active_w := 0
var _chasing := false
var _fade: Tween

func _ready() -> void:
	for p in _players():
		var mp3 := p.stream as AudioStreamMP3
		# ponytail: whole-file loop so a track never ends in silence; fine loop points come later
		mp3.loop = true
		mp3.loop_offset = 0.0
		p.play()
	_active_w = DimensionState.player_w
	_mix(0.0)
	DimensionState.layer_changed.connect(_on_layer_changed)

func start_chase() -> void:
	_chasing = true
	_mix(FADE_TIME)

func stop_chase() -> void:
	_chasing = false
	_mix(FADE_TIME)

## New run (the entity that was hunting is gone with the old scene): the
## current layer's ambient, no chase, no fade.
func reset() -> void:
	_chasing = false
	_active_w = DimensionState.player_w
	_mix(0.0)

func _on_layer_changed(new_w: int) -> void:
	_active_w = new_w
	_mix(FADE_TIME)

## Cross-fades every track toward its target: the dominant one up, the rest
## down. Starts from each player's current volume and replaces any fade in
## flight, so a switch mid-fade just turns around.
func _mix(time: float) -> void:
	var loud := chase_player if _chasing else ambient_players[_active_w]
	if _fade:
		_fade.kill()
	if time <= 0.0:
		for p in _players():
			p.volume_db = 0.0 if p == loud else SILENT_DB
		return
	_fade = create_tween().set_parallel()
	for p in _players():
		_fade.tween_property(p, "volume_db", 0.0 if p == loud else SILENT_DB, time)

func _players() -> Array[AudioStreamPlayer]:
	var all: Array[AudioStreamPlayer] = [chase_player]
	all.append_array(ambient_players.values())
	return all
