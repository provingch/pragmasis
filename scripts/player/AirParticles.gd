extends GPUParticles3D

## What drifts in the air around the player: the world's WorldDef.air
## preset, retuned on every crossing. One emitter for every world (one
## process shader, one draw material), moving with the player but emitting
## into world space; off where the world has none.

## y: emission box centre above the player's origin (null: under the ceiling).
const PRESETS := {
	"sparks": {"amount": 24, "life": 1.4, "box": Vector3(5, 0.05, 5), "y": -0.85, "dir": Vector3.UP, "spread": 25.0, "vel": Vector2(1.5, 4.0), "gravity": -5.0, "size": Vector2(0.03, 0.03)},
	"snow": {"amount": 360, "life": 2.5, "box": Vector3(9, 0.1, 9), "y": 3.0, "dir": Vector3(1, -0.5, 0.4), "spread": 15.0, "vel": Vector2(3.0, 6.0), "gravity": -1.0, "size": Vector2(0.035, 0.035)},
	"dust": {"amount": 90, "life": 7.0, "box": Vector3(6, 1.5, 6), "y": 0.8, "dir": Vector3.UP, "spread": 180.0, "vel": Vector2(0.03, 0.12), "gravity": 0.0, "size": Vector2(0.012, 0.012)},
	"drips": {"amount": 20, "life": 1.2, "box": Vector3(8, 0.05, 8), "y": null, "dir": Vector3.DOWN, "spread": 0.0, "vel": Vector2(0.0, 0.0), "gravity": -9.8, "size": Vector2(0.012, 0.1)},
}

var _pm := ParticleProcessMaterial.new()
var _quad := QuadMesh.new()
var _mat := StandardMaterial3D.new()

func _ready() -> void:
	local_coords = false
	visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 16, 24))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material = _pm
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_mat.billboard_keep_scale = true
	_quad.material = _mat
	draw_pass_1 = _quad
	_apply(DimensionState.player_w)
	DimensionState.layer_changed.connect(_apply)

func _apply(w: int) -> void:
	var def := Worlds.def(w)
	emitting = PRESETS.has(def.air)
	if not emitting:
		return
	var p: Dictionary = PRESETS[def.air]
	amount = p.amount
	lifetime = p.life
	_pm.emission_box_extents = p.box / 2.0
	_pm.emission_shape_offset = Vector3(0, def.height - 1.0 if p.y == null else p.y, 0)
	_pm.direction = p.dir
	_pm.spread = p.spread
	_pm.initial_velocity_min = p.vel.x
	_pm.initial_velocity_max = p.vel.y
	_pm.gravity = Vector3(0, p.gravity, 0)
	_quad.size = p.size
	_mat.albedo_color = {
		"sparks": def.trim_color * 2.0,
		"snow": def.light_color.lightened(0.5),
		"dust": def.light_color * 0.7,
		"drips": def.light_color.lightened(0.3),
	}[def.air]
	restart()
