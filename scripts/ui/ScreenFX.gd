extends CanvasLayer

## Full-screen post: phase-jump tearing, danger heartbeat vignette, grain.
## The screen-reading pass (FX) only runs while something is happening; in
## calm, Calm draws the same vignette/grain without reading the screen.

const DANGER_RANGE := 18.0
const ACTIVE_EPS := 0.01

@onready var fx: ColorRect = $FX
@onready var calm: ColorRect = $Calm
@onready var mat: ShaderMaterial = fx.material

var _danger := 0.0
var _shift := 0.0

func _ready() -> void:
	DimensionState.layer_changed.connect(_on_layer_changed)
	_set_active(false)

func _process(delta: float) -> void:
	var monster := get_tree().get_first_node_in_group("monster") as Monster
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var target := 0.0
	if monster and player and monster.is_hunting():
		var d := monster.global_position.distance_to(player.global_position)
		target = clampf(1.0 - d / DANGER_RANGE, 0.0, 1.0) * monster.coherence()
	_danger = move_toward(_danger, target, delta * 1.5)
	mat.set_shader_parameter("danger", _danger)
	_set_active(_danger > ACTIVE_EPS or _shift > ACTIVE_EPS)

func _on_layer_changed(new_w: int) -> void:
	mat.set_shader_parameter("tint", Worlds.def(new_w).trim_color)
	# Active right away: the room swap happens this frame, behind the tear.
	_set_shift(1.0)
	_set_active(true)
	create_tween().tween_method(_set_shift, 1.0, 0.0, 0.8) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

func _set_shift(v: float) -> void:
	_shift = v
	mat.set_shader_parameter("shift", v)

func _set_active(on: bool) -> void:
	fx.visible = on
	calm.visible = not on
