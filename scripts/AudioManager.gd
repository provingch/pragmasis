extends Node

## Autoload (scene-backed so the two AudioStream exports are assignable
## in the Inspector). Assign ambient_music / chase_music to your files
## under res://audio/music/ once you have them.

const FADE_TIME := 1.5

@export var ambient_music: AudioStream
@export var chase_music: AudioStream

@onready var ambient_player: AudioStreamPlayer = $AmbientPlayer
@onready var chase_player: AudioStreamPlayer = $ChasePlayer

func _ready() -> void:
	ambient_player.stream = ambient_music
	chase_player.stream = chase_music
	chase_player.volume_db = -80.0
	if ambient_music:
		ambient_player.play()
	if chase_music:
		chase_player.play()

func start_chase() -> void:
	_crossfade(chase_player, ambient_player)

func stop_chase() -> void:
	_crossfade(ambient_player, chase_player)

func _crossfade(fade_in: AudioStreamPlayer, fade_out: AudioStreamPlayer) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(fade_in, "volume_db", 0.0, FADE_TIME)
	tween.tween_property(fade_out, "volume_db", -80.0, FADE_TIME)
