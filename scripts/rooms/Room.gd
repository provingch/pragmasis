extends Node3D
class_name Room

## Cubic modular room, built procedurally so RoomGenerator can reuse one
## scene and just flip which of the 4 walls open into a door. Its look
## (materials, light, flicker) comes from its w-layer's style.

const ROOM_SIZE := 10.0
const WALL_THICKNESS := 0.5
const DOOR_WIDTH := 3.0
const PORTAL_INSET := 1.5
const PORTAL_HEIGHT := 1.5
const TRIM_HEIGHT := 0.3
## Beyond this the fog has already eaten everything; skip drawing it.
const VIS_RANGE := 48.0
const PHASE_PORTAL_SCENE := preload("res://scenes/rooms/PhasePortal.tscn")

enum Exit { NORTH, SOUTH, EAST, WEST }

## Order: [north(-z), south(+z), east(+x), west(-x)]
@export var exits: Array[bool] = [true, true, true, true]
@export var phase_positive := false
@export var phase_negative := false
@export var w := 0

# Shared across all rooms of a layer: 3 materials per layer.
static var _materials := {}

# Each room is two merged meshes instead of ~20 boxes: one draw call per
# material instead of per box, which is what keeps ~70 attached rooms cheap.
var _solid: CSGCombiner3D
var _deco: CSGCombiner3D
var _light: OmniLight3D
var _fixture_mat: StandardMaterial3D
var _style: Dictionary
var _base_energy := 1.0
var _t := 0.0
var _seed := 0.0

func _ready() -> void:
	_style = DimensionState.LAYERS[w]
	_seed = randf() * 100.0
	_solid = _combiner(true)
	_deco = _combiner(false)
	_deco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_floor_ceiling()
	_build_walls()
	_build_light()
	# Opposite corners so both portals can coexist in one room.
	var corner := ROOM_SIZE / 2.0 - PORTAL_INSET
	if phase_positive:
		_build_phase_portal(1, Vector3(corner, PORTAL_HEIGHT, corner))
	if phase_negative:
		_build_phase_portal(-1, Vector3(-corner, PORTAL_HEIGHT, -corner))

func _process(delta: float) -> void:
	_t += delta
	var k := 1.0
	match _style.flicker:
		"stutter": # failing sodium tube: jittery, with dropouts
			k = 0.6 + 0.4 * sin(_t * 23.0 + _seed) * sin(_t * 7.0)
			if randf() < 0.03:
				k = 0.08
		"steady": # clinical hum, rare hiccup
			k = 1.0 - 0.05 * sin(_t * 60.0)
			if randf() < 0.004:
				k = 0.25
		"breathe": # slow tide
			k = 0.65 + 0.35 * sin(_t * 1.1 + _seed)
	_light.light_energy = _base_energy * k
	_fixture_mat.emission_energy_multiplier = 4.0 * k

func _build_phase_portal(direction: int, pos: Vector3) -> void:
	var portal := PHASE_PORTAL_SCENE.instantiate() as PhasePortal
	portal.direction = direction
	portal.target_w = w + direction
	portal.position = pos
	add_child(portal)

func _combiner(collide: bool) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	c.use_collision = collide
	c.visibility_range_end = VIS_RANGE
	add_child(c)
	return c

func _box(size: Vector3, pos: Vector3, mat: Material, collide := true) -> void:
	var box := CSGBox3D.new()
	box.size = size
	box.position = pos
	box.material = mat
	(_solid if collide else _deco).add_child(box)

func _build_floor_ceiling() -> void:
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, -WALL_THICKNESS / 2.0, 0), _layer_material("floor"))
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, ROOM_SIZE - WALL_THICKNESS / 2.0, 0), _layer_material("wall"))

func _build_walls() -> void:
	_build_wall(Exit.NORTH, Vector3(0, ROOM_SIZE / 2.0, -ROOM_SIZE / 2.0), false)
	_build_wall(Exit.SOUTH, Vector3(0, ROOM_SIZE / 2.0, ROOM_SIZE / 2.0), false)
	_build_wall(Exit.EAST, Vector3(ROOM_SIZE / 2.0, ROOM_SIZE / 2.0, 0), true)
	_build_wall(Exit.WEST, Vector3(-ROOM_SIZE / 2.0, ROOM_SIZE / 2.0, 0), true)

func _build_wall(exit_dir: int, center: Vector3, is_side: bool) -> void:
	if not exits[exit_dir]:
		_wall_segment(center, ROOM_SIZE, is_side)
		return
	# Door: two side segments instead of one solid wall, leaving a gap.
	var segment_len := (ROOM_SIZE - DOOR_WIDTH) / 2.0
	for side: float in [-1.0, 1.0]:
		var offset := (DOOR_WIDTH / 2.0 + segment_len / 2.0) * side
		var along := Vector3(0, 0, offset) if is_side else Vector3(offset, 0, 0)
		_wall_segment(center + along, segment_len, is_side)

func _wall_segment(center: Vector3, length: float, is_side: bool) -> void:
	var size := Vector3(WALL_THICKNESS, ROOM_SIZE, length) if is_side else Vector3(length, ROOM_SIZE, WALL_THICKNESS)
	_box(size, center, _layer_material("wall"))
	# Emissive baseboard strip on the inner face: the layer's signal color.
	var inward := Vector3(-signf(center.x), 0, 0) if is_side else Vector3(0, 0, -signf(center.z))
	var trim_size := Vector3(0.06, 0.08, length) if is_side else Vector3(length, 0.08, 0.06)
	var trim_pos := Vector3(center.x, TRIM_HEIGHT, center.z) + inward * (WALL_THICKNESS / 2.0 + 0.03)
	_box(trim_size, trim_pos, _layer_material("trim"), false)

func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0, ROOM_SIZE - 1.5, 0)
	_light.omni_range = ROOM_SIZE * 1.6
	_light.omni_attenuation = 0.8
	_light.light_color = _style.light
	_base_energy = _style.light_energy
	_light.shadow_enabled = true
	# Up to ~170 rooms are attached; only nearby lights are worth it, and
	# omni shadows re-render the scene 6x per light, so only the room you're
	# in (and a doorway's worth) keeps them.
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 32.0
	_light.distance_fade_shadow = 9.0
	_light.distance_fade_length = 10.0
	add_child(_light)

	# Per-room so its glow can flicker in sync with this room's light.
	_fixture_mat = StandardMaterial3D.new()
	_fixture_mat.albedo_color = _style.light
	_fixture_mat.emission_enabled = true
	_fixture_mat.emission = _style.light
	_box(Vector3(2.4, 0.08, 0.5), Vector3(0, ROOM_SIZE - WALL_THICKNESS - 0.04, 0), _fixture_mat, false)

func _layer_material(kind: String) -> StandardMaterial3D:
	var key := "%d:%s" % [w, kind]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _style[kind]
	if kind == "trim":
		mat.emission_enabled = true
		mat.emission = _style.trim
		# Low enough that the tonemapper keeps the hue instead of clipping to white.
		mat.emission_energy_multiplier = 1.1
	else:
		# Grime: world-space noise so adjacent boxes don't show seams.
		var noise := FastNoiseLite.new()
		noise.frequency = 0.12
		noise.fractal_octaves = 5
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.color_ramp = Gradient.new()
		tex.color_ramp.set_color(0, Color(0.8, 0.8, 0.8))
		tex.color_ramp.set_color(1, Color(1, 1, 1))
		mat.albedo_texture = tex
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE * 0.12
		mat.roughness = 0.92 if kind == "wall" else 0.75
	_materials[key] = mat
	return mat
