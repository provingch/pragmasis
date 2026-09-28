extends Node

## Autoload. Music: one ambient MusicTrack per world (worlds may share
## one) plus the chase track, looping and mixed only by volume, so every
## switch is a cross-fade. Loop points live in each track's .tres. Only the
## current world's track and its neighbours' (one portal or fissure away)
## are loaded and playing; neighbours load on a thread, and tracks nobody
## is next to anymore are dropped once faded out.
##
## Exactly one track dominates: the chase while the entity hunts, otherwise
## the ambient of the world the player is in. A world change mid-chase only
## retargets which ambient comes back when the chase ends.
##
## Each world may colour the Music bus (WorldDef.music_fx: filters, reverb,
## drive, pitch, level); crossing blends to the new world's preset over the
## same fade. A world may also keep the entity's sounds from the player
## (WorldDef.entity_audio): no stinger, no omen, no chase track there.
##
## Also plays the non-positional one-shot SFX (play_sfx). Those keep playing
## while the tree is paused (game over, options); the music pauses with it.

const FADE_TIME := 1.5
const SILENT_DB := -80.0
const CHASE_TRACK := "res://audio/music/persecucion.tres"
const SFX := {
	&"monster": preload("res://audio/sfx/monster_stinger.wav"),
	&"game_over": preload("res://audio/sfx/game_over.wav"),
	&"whoosh_up": preload("res://audio/sfx/whoosh_up.wav"),
	&"whoosh_down": preload("res://audio/sfx/whoosh_down.wav"),
	&"ui_hover": preload("res://audio/sfx/ui_hover.wav"),
	&"ui_select": preload("res://audio/sfx/ui_select.wav"),
	&"scanner_open": preload("res://audio/sfx/scanner_open.wav"),
	&"scanner_close": preload("res://audio/sfx/scanner_close.wav"),
	&"omen": preload("res://audio/sfx/omen.wav"),
	&"hide_in": preload("res://audio/sfx/hide_in.wav"),
	&"hide_out": preload("res://audio/sfx/hide_out.wav"),
	&"hide_unstable": preload("res://audio/sfx/hide_unstable.wav"),
	&"sequence_done": preload("res://audio/sfx/sequence_done.wav"),
	&"collapse": preload("res://audio/sfx/collapse.wav"),
}
## SFX that are the entity's: silent in worlds without entity_audio.
const ENTITY_SFX: Array[StringName] = [&"monster", &"omen"]

## The Music bus's effect chain, in order.
enum Fx { HIGHPASS, LOWPASS, DISTORTION, PITCH, REVERB }

var chase_player: AudioStreamPlayer
## Track path -> its player (loaded tracks only).
var _music: Dictionary[String, AudioStreamPlayer] = {}
## Track paths loading on a thread.
var _loading := {}

## World whose ambient plays (or will, once the chase ends).
var _active_w := 0
var _chasing := false
var _fade: Tween
var _sfx: Dictionary[StringName, AudioStreamPlayer] = {}
var _bus := 0
var _neutral := MusicFX.new()
## The preset the Music bus is at right now (mid-blend: in between).
var _fx_now := MusicFX.new()
var _fx_tween: Tween

func _ready() -> void:
	chase_player = _track_player(CHASE_TRACK)
	for key: StringName in SFX:
		var p := AudioStreamPlayer.new()
		p.stream = SFX[key]
		p.bus = &"SFX"
		p.max_polyphony = 4 # UI hovers can overlap
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx[key] = p
	_setup_fx()
	_active_w = DimensionState.player_w
	_track_player(Worlds.def(_active_w).music)
	_want_neighbours()
	_mix(0.0)
	_music_fx(0.0)
	DimensionState.layer_changed.connect(_on_layer_changed)

func _process(_delta: float) -> void:
	for path in _loading.keys():
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.erase(path)
			_track_player(path)
			_mix(FADE_TIME)
	# Drop tracks no longer next to the player, once silent.
	if _fade and _fade.is_running():
		return
	var keep := _wanted()
	for path in _music.keys():
		var p := _music[path]
		if p != chase_player and not keep.has(path) and p.volume_db <= SILENT_DB + 0.5:
			_music.erase(path)
			p.queue_free()

## Track paths that should be loaded: here and one hop away.
func _wanted() -> Dictionary:
	var out := {Worlds.def(_active_w).music: true}
	for n in Worlds.links(_active_w):
		out[Worlds.def(n).music] = true
	return out

func _want_neighbours() -> void:
	for path: String in _wanted():
		if not _music.has(path) and not _loading.has(path):
			ResourceLoader.load_threaded_request(path)
			_loading[path] = true

## The (shared) player for a MusicTrack, created and started on first use.
## Only call it once the track is loaded (or at load time): fetching a track
## still loading on its thread blocks until it's done (~250 ms measured).
func _track_player(path: String) -> AudioStreamPlayer:
	if not _music.has(path):
		var track: MusicTrack
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
			track = ResourceLoader.load_threaded_get(path)
		else:
			track = load(path)
		var ogg := track.stream as AudioStreamOggVorbis
		ogg.loop = true
		ogg.loop_offset = track.loop_offset
		var p := AudioStreamPlayer.new()
		p.stream = ogg
		p.bus = &"Music"
		p.volume_db = SILENT_DB
		add_child(p)
		p.play()
		_music[path] = p
	return _music[path]

func play_sfx(key: StringName) -> void:
	if key in ENTITY_SFX and not Worlds.def(_active_w).entity_audio:
		return
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
	_track_player(Worlds.def(_active_w).music)
	_want_neighbours()
	_mix(0.0)
	_music_fx(0.0)

func _on_layer_changed(new_w: int) -> void:
	play_sfx(&"whoosh_down" if new_w > _active_w else &"whoosh_up")
	_active_w = new_w
	_want_neighbours()
	_mix(FADE_TIME)
	_music_fx(FADE_TIME)

## Cross-fades every track toward its target: the dominant one up, the rest
## down. Starts from each player's current volume and replaces any fade in
## flight, so a switch mid-fade just turns around.
func _mix(time: float) -> void:
	# The world's track may still be loading (crossed right after arriving):
	# then everything fades out and _process fades it in once it's there.
	var chase := _chasing and Worlds.def(_active_w).entity_audio
	var loud: AudioStreamPlayer = chase_player if chase else _music.get(Worlds.def(_active_w).music)
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
	return _music.values()

# --- music bus effects -------------------------------------------------------

func _setup_fx() -> void:
	_bus = AudioServer.get_bus_index(&"Music")
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	for e: AudioEffect in [AudioEffectHighPassFilter.new(), AudioEffectLowPassFilter.new(), drive, AudioEffectPitchShift.new(), AudioEffectReverb.new()]:
		AudioServer.add_bus_effect(_bus, e)
	_set_fx(_neutral)

## Blends the bus from where it is to the active world's preset.
func _music_fx(time: float) -> void:
	var to: MusicFX = Worlds.def(_active_w).music_fx if Worlds.def(_active_w).music_fx else _neutral
	if _fx_tween:
		_fx_tween.kill()
	if time <= 0.0:
		_set_fx(to)
		return
	var from := _fx_now
	_fx_tween = create_tween()
	_fx_tween.tween_method(func(t: float) -> void: _set_fx(_blend(from, to, t)), 0.0, 1.0, time)

static func _blend(a: MusicFX, b: MusicFX, t: float) -> MusicFX:
	var m := MusicFX.new()
	# Cutoffs glide in log frequency: what the ear hears as even.
	m.lowpass_hz = exp(lerpf(log(a.lowpass_hz), log(b.lowpass_hz), t))
	m.highpass_hz = exp(lerpf(log(a.highpass_hz), log(b.highpass_hz), t))
	for key: String in ["reverb", "reverb_room", "distortion", "pitch", "volume_db"]:
		m.set(key, lerpf(a.get(key), b.get(key), t))
	return m

## Effects left neutral are bypassed: reverb and pitch shift cost CPU and
## colour the sound even at rest.
func _set_fx(m: MusicFX) -> void:
	_fx_now = m
	var hp := AudioServer.get_bus_effect(_bus, Fx.HIGHPASS) as AudioEffectHighPassFilter
	var lp := AudioServer.get_bus_effect(_bus, Fx.LOWPASS) as AudioEffectLowPassFilter
	var drive := AudioServer.get_bus_effect(_bus, Fx.DISTORTION) as AudioEffectDistortion
	var pitch := AudioServer.get_bus_effect(_bus, Fx.PITCH) as AudioEffectPitchShift
	var verb := AudioServer.get_bus_effect(_bus, Fx.REVERB) as AudioEffectReverb
	hp.cutoff_hz = m.highpass_hz
	lp.cutoff_hz = m.lowpass_hz
	drive.drive = m.distortion
	drive.post_gain = -8.0 * m.distortion
	pitch.pitch_scale = m.pitch
	verb.wet = m.reverb
	verb.dry = 1.0 - 0.4 * m.reverb
	verb.room_size = m.reverb_room
	AudioServer.set_bus_effect_enabled(_bus, Fx.HIGHPASS, m.highpass_hz > _neutral.highpass_hz + 1.0)
	AudioServer.set_bus_effect_enabled(_bus, Fx.LOWPASS, m.lowpass_hz < _neutral.lowpass_hz - 1.0)
	AudioServer.set_bus_effect_enabled(_bus, Fx.DISTORTION, m.distortion > 0.001)
	AudioServer.set_bus_effect_enabled(_bus, Fx.PITCH, absf(m.pitch - 1.0) > 0.002)
	AudioServer.set_bus_effect_enabled(_bus, Fx.REVERB, m.reverb > 0.001)
	AudioServer.set_bus_volume_db(_bus, m.volume_db)
