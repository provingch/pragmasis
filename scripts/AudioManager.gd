extends Node

## Autoload. One ambient track per w-layer plus the chase track. All four
## loop from launch and are mixed only by volume, so every switch is a
## cross-fade and each track keeps its place while silent.
##
## Exactly one track dominates: the chase while the entity hunts, otherwise
## the ambient of the layer the player is in. A layer change mid-chase only
## retargets which ambient comes back when the chase ends.
##
## Also plays the non-positional one-shot SFX (play_sfx). Those keep playing
## while the tree is paused (game over, options); the music pauses with it.

const FADE_TIME := 1.5
const SILENT_DB := -80.0
## Seconds each track jumps back to when it reaches its end. The only place
## these live: tools/loop_music.py finds them (and bakes the crossfade that
## makes the jump seamless) and prints them; paste the output here.
const LOOP_OFFSETS := {
	"sedimento": 3.727927,
	"umbral": 8.605240,
	"eter": 8.374719,
	"persecucion": 12.019010,
}
const SFX := {
	&"monster": preload("res://audio/sfx/monster_stinger.wav"),
	&"game_over": preload("res://audio/sfx/game_over.wav"),
	&"whoosh_up": preload("res://audio/sfx/whoosh_up.wav"),
	&"whoosh_down": preload("res://audio/sfx/whoosh_down.wav"),
	&"ui_hover": preload("res://audio/sfx/ui_hover.wav"),
	&"ui_select": preload("res://audio/sfx/ui_select.wav"),
	&"scanner_open": preload("res://audio/sfx/scanner_open.wav"),
	&"scanner_close": preload("res://audio/sfx/scanner_close.wav"),
}

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
var _sfx: Dictionary[StringName, AudioStreamPlayer] = {}

func _ready() -> void:
	for p in _players():
		var ogg := p.stream as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = LOOP_OFFSETS[ogg.resource_path.get_file().get_basename()]
		p.play()
	for key: StringName in SFX:
		var p := AudioStreamPlayer.new()
		p.stream = SFX[key]
		p.bus = &"SFX"
		p.max_polyphony = 4 # UI hovers can overlap
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx[key] = p
	_active_w = DimensionState.player_w
	_mix(0.0)
	DimensionState.layer_changed.connect(_on_layer_changed)

func play_sfx(key: StringName) -> void:
	_sfx[key].play()

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
	play_sfx(&"whoosh_up" if new_w > _active_w else &"whoosh_down")
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
