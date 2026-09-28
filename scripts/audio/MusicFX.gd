extends Resource
class_name MusicFX

## Effects on the Music bus while the player is in a world (WorldDef.music_fx);
## AudioManager blends from one world's preset to the next. The defaults
## leave the music untouched.

@export var lowpass_hz := 20000.0
@export var highpass_hz := 20.0
@export_range(0.0, 1.0) var reverb := 0.0
@export_range(0.0, 1.0) var reverb_room := 0.8
@export_range(0.0, 1.0) var distortion := 0.0
@export_range(0.5, 2.0) var pitch := 1.0
@export var volume_db := 0.0
