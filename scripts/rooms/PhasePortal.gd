extends Area3D
class_name PhasePortal

## Floating object inside a room (not a wall opening). Touching it shifts
## the player's w by `direction`; x/z stay put since every layer shares
## the same room footprint. Glows in the *destination* layer's color.

@export var direction := 1
@export var target_w := 1

@onready var shell: MeshInstance3D = $Shell
@onready var ring: MeshInstance3D = $Ring
@onready var light: OmniLight3D = $Light
@onready var motes: CPUParticles3D = $Motes
@onready var label: Label3D = $Label
@onready var hum: AudioStreamPlayer3D = $Hum

var _t := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var style: Dictionary = DimensionState.LAYERS[target_w]
	var c: Color = style.trim
	shell.set_instance_shader_parameter("tint", c)
	ring.set_instance_shader_parameter("tint", c)
	light.light_color = c
	motes.color = c
	label.modulate = c
	label.font = Fonts.mono
	label.text = "%s W%+d\n%s" % ["▲" if direction > 0 else "▼", target_w, style.name]
	_t = randf() * 10.0
	# Findable by ear, and which way it leads: up-portals hum higher.
	hum.pitch_scale = 1.12 if direction > 0 else 0.89

func _process(delta: float) -> void:
	_t += delta
	shell.rotate_y(delta * 2.0)
	shell.rotate_x(delta * 0.9)
	ring.rotate_z(delta * 1.3)
	var breath := 0.5 + 0.5 * sin(_t * 2.4)
	ring.scale = Vector3.ONE * (1.0 + 0.12 * breath)
	light.light_energy = 0.9 + 0.8 * breath
	# Label flickers like a bad hologram.
	label.modulate.a = 0.15 if randf() < 0.05 else 0.55 + 0.35 * breath

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	DimensionState.request_phase_shift(direction)
	body.global_position.y = 1.0
