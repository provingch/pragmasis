extends CanvasLayer

## Full-screen post: phase-jump tearing, danger heartbeat vignette, grain.

const DANGER_RANGE := 18.0

@onready var fx: ColorRect = $FX
@onready var mat: ShaderMaterial = fx.material

var _danger := 0.0

func _ready() -> void:
	DimensionState.layer_changed.connect(_on_layer_changed)

func _process(delta: float) -> void:
	var monster := get_tree().get_first_node_in_group("monster") as Monster
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target := 0.0
	if monster and player and monster.is_hunting():
		var d := monster.global_position.distance_to(player.global_position)
		target = clampf(1.0 - d / DANGER_RANGE, 0.0, 1.0) * monster.coherence()
	_danger = move_toward(_danger, target, delta * 1.5)
	mat.set_shader_parameter("danger", _danger)

func _on_layer_changed(new_w: int) -> void:
	mat.set_shader_parameter("tint", DimensionState.LAYERS[new_w].trim)
	# Starts torn at 1 so the room swap happens behind the glitch.
	create_tween().tween_method(func(v: float) -> void: mat.set_shader_parameter("shift", v), 1.0, 0.0, 0.8) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
