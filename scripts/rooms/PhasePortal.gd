extends Area3D
class_name PhasePortal

## Floating object inside a room (not a wall opening). Touching it moves
## the player to world `target_w`; x/z stay put since every world shares
## the same room footprint. Glows in the *destination* world's color.
## A fissure (crossing to another stratum) is a tall torn slit instead of
## an orb, rarer, brighter, humming lower.

@export var target_w := 0
@export var fissure := false

@onready var shell: MeshInstance3D = $Shell
@onready var ring: MeshInstance3D = $Ring
@onready var light: OmniLight3D = $Light
@onready var motes: CPUParticles3D = $Motes
@onready var label: Label3D = $Label
@onready var hum: AudioStreamPlayer3D = $Hum

var _t := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var def := Worlds.def(target_w)
	var c := def.trim_color
	shell.set_instance_shader_parameter("tint", c)
	ring.set_instance_shader_parameter("tint", c)
	light.light_color = c
	motes.color = c
	label.modulate = c
	label.font = Fonts.mono
	var deeper := target_w > _here()
	label.text = "%s%s %s\nESTRATO %d" % ["FISURA " if fissure else "", "▼" if deeper else "▲", def.tag(), def.stratum + 1]
	_t = randf() * 10.0
	# Findable by ear, and which way it leads: shallower hums higher.
	hum.pitch_scale = (0.89 if deeper else 1.12) * (0.6 if fissure else 1.0)
	if fissure:
		shell.scale = Vector3(0.3, 2.6, 0.3)
		ring.visible = false
		light.omni_range *= 1.5
		motes.speed_scale = 2.5
		label.position.y += 1.2

## The world this portal stands in (its room's).
func _here() -> int:
	var room := get_parent() as Room
	return room.w if room else DimensionState.player_w

func _process(delta: float) -> void:
	_t += delta
	shell.rotate_y(delta * 2.0)
	shell.rotate_x(delta * 0.9)
	ring.rotate_z(delta * 1.3)
	var breath := 0.5 + 0.5 * sin(_t * 2.4)
	ring.scale = Vector3.ONE * (1.0 + 0.12 * breath)
	light.light_energy = (0.9 + 0.8 * breath) * (1.8 if fissure else 1.0)
	if fissure:
		shell.scale.x = 0.3 * (1.0 + 0.25 * sin(_t * 17.0)) # torn edges shiver
	# Label flickers like a bad hologram.
	label.modulate.a = 0.15 if randf() < 0.05 else 0.55 + 0.35 * breath

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	DimensionState.request_shift(target_w)
