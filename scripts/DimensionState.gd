extends Node

## Autoload. Tracks the player's logical position along the 4th (phase)
## dimension. All w-layers share the same x/y/z room grid — only the
## active layer is attached to the scene tree (see RoomGenerator).

signal layer_changed(new_w: int)

const W_MIN := -2
const W_MAX := 2
const W_SPAN := W_MAX - W_MIN
# Destination room may have a portal at the same corner the player lands on;
# without this, shifts would chain instantly.
const SHIFT_COOLDOWN_MS := 800

## Per-layer identity. Same maze footprint, different "material" of reality:
## CARNE is a ribbed organic gut lit by a heartbeat, SEDIMENTO rots in
## sodium amber among pipes and rusted columns, UMBRAL is the low
## drop-ceiling office of the backrooms, ÉTER is a violet hall whose walls
## fall short of a ceiling lost in fog, ESTÁTICA is black geometry drawn
## only by its glowing edges.
##
## `trim` doubles as the layer's signal color (portal glow, entity tint,
## transition flash). `threat` multiplies how often the entity manifests
## while the player stands in that world; `entity_speed` how fast it moves
## there. `style` picks Room's builder; `height` is the ceiling and
## `light_y` where the room's one light hangs. `accent` colors the style's
## props (ribs, pipes, tiles...); `rough`/`metal`/`noise` shape the grime
## texture every surface of that world shares.
const LAYERS := {
	-2: {
		"name": "CARNE", "style": "carne", "height": 6.0, "light_y": 4.8,
		"wall": Color("5e211d"), "floor": Color("2b0d0b"), "accent": Color("7d2f2a"),
		"rough": 0.4, "metal": 0.0, "noise": 0.3,
		"trim": Color("ff5c7a"), "light": Color("ff9070"), "light_energy": 2.6,
		"fog": Color("220605"), "fog_begin": 3.0, "flicker": "heartbeat",
		"threat": 2.2, "entity_speed": 1.0,
	},
	-1: {
		"name": "SEDIMENTO", "style": "sedimento", "height": 8.0, "light_y": 6.5,
		"wall": Color("7d6440"), "floor": Color("3b2f1e"), "accent": Color("6a3a1c"),
		"rough": 0.9, "metal": 0.35, "noise": 0.12,
		"trim": Color("ffa630"), "light": Color("ffc070"), "light_energy": 2.2,
		"fog": Color("2e1f0c"), "fog_begin": 4.0, "flicker": "stutter",
		"threat": 1.8, "entity_speed": 1.0,
	},
	0: {
		"name": "UMBRAL", "style": "umbral", "height": 4.0, "light_y": 3.5,
		"wall": Color("b9b6a6"), "floor": Color("6b695e"), "accent": Color("8f8c7e"),
		"rough": 0.92, "metal": 0.0, "noise": 0.12,
		"trim": Color("3fe0c8"), "light": Color("e6f2ea"), "light_energy": 1.6,
		"fog": Color("0c1411"), "fog_begin": 10.0, "flicker": "steady",
		"threat": 1.0, "entity_speed": 1.0,
	},
	1: {
		"name": "ÉTER", "style": "eter", "height": 16.0, "light_y": 7.0,
		"wall": Color("5a5288"), "floor": Color("2a2650"), "accent": Color("403a6e"),
		"rough": 0.7, "metal": 0.1, "noise": 0.06,
		"trim": Color("b48cff"), "light": Color("b0c4ff"), "light_energy": 2.2,
		"fog": Color("1a1640"), "fog_begin": 7.0, "flicker": "breathe",
		"threat": 0.5, "entity_speed": 1.0,
	},
	2: {
		"name": "ESTÁTICA", "style": "estatica", "height": 10.0, "light_y": 8.5,
		"wall": Color("0e1013"), "floor": Color("08090b"), "accent": Color("12161b"),
		"rough": 0.75, "metal": 0.0, "noise": 0.5,
		"trim": Color("d8fbff"), "light": Color("cfe9ff"), "light_energy": 1.4,
		"fog": Color("020304"), "fog_begin": 6.0, "flicker": "glitch",
		"threat": 0.6, "entity_speed": 1.6,
	},
}

var player_w: int = 0
var _last_shift_ms := -SHIFT_COOLDOWN_MS

func reset() -> void:
	player_w = 0
	_last_shift_ms = -SHIFT_COOLDOWN_MS

func request_phase_shift(direction: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_shift_ms < SHIFT_COOLDOWN_MS:
		return
	var new_w := clampi(player_w + direction, W_MIN, W_MAX)
	if new_w == player_w:
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
