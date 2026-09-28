extends Node

## Autoload. Tracks the player's logical position along the 4th (phase)
## dimension. All w-layers share the same x/y/z room grid — only the
## active layer is attached to the scene tree (see RoomGenerator).

signal layer_changed(new_w: int)

const W_MIN := -1
const W_MAX := 1
const W_SPAN := W_MAX - W_MIN
# Destination room may have a portal at the same corner the player lands on;
# without this, shifts would chain instantly.
const SHIFT_COOLDOWN_MS := 800

## Per-layer identity. Same footprint, different "material" of reality:
## SEDIMENTO rots in sodium amber, UMBRAL is clinical bone-white, ÉTER is a
## cold violet that breathes. `trim` doubles as the layer's signal color
## (portal glow, entity tint, transition flash). `threat` multiplies how
## often the entity manifests while the player stands in that world,
## regardless of where the entity is.
const LAYERS := {
	-1: {
		"name": "SEDIMENTO", "wall": Color("7d6440"), "floor": Color("3b2f1e"),
		"trim": Color("ffa630"), "light": Color("ffc070"), "light_energy": 2.2,
		"fog": Color("2e1f0c"), "fog_begin": 4.0, "flicker": "stutter",
		"threat": 1.8,
	},
	0: {
		"name": "UMBRAL", "wall": Color("b9b6a6"), "floor": Color("6b695e"),
		"trim": Color("3fe0c8"), "light": Color("e6f2ea"), "light_energy": 1.6,
		"fog": Color("0c1411"), "fog_begin": 10.0, "flicker": "steady",
		"threat": 1.0,
	},
	1: {
		"name": "ÉTER", "wall": Color("5a5288"), "floor": Color("2a2650"),
		"trim": Color("b48cff"), "light": Color("b0c4ff"), "light_energy": 2.2,
		"fog": Color("1a1640"), "fog_begin": 7.0, "flicker": "breathe",
		"threat": 0.5,
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
	# Deferred: called from a portal's body_entered, and physics objects
	# can't leave the tree mid-callback.
	RoomGenerator.switch_layer.call_deferred(player_w)
	layer_changed.emit(player_w)
