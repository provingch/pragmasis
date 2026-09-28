extends Node3D
class_name Room

## Modular 10x10 m room, built procedurally so RoomGenerator can reuse one
## scene. The maze (which walls open into a 3 m door) is the same in every
## world; the world's WorldDef builds its own architecture around it from
## kits (see RoomKit), plus its materials, light and flicker.
##
## Nothing collidable ever goes in the walkway (the plus joining the doors)
## or in the two portal corners, in any world: a portal drops the player at
## the same x/z in the next world, whatever stands there. The third corner
## (+x, -z) is kept for the hideout, so no kit puts props there either.
##
## Geometry is plain boxes, batched into one surface per material and built
## once per (world, exits, variant): every room with that key shares the
## mesh. Per room there's only the collision boxes, the light, and a small
## fixture mesh carrying the room's own flickering material.

const ROOM_SIZE := 10.0
const WALL_THICKNESS := 0.5
const DOOR_WIDTH := 3.0
const PORTAL_INSET := 1.5
const PORTAL_HEIGHT := 1.5
const TRIM_HEIGHT := 0.3
## Past the fog's opaque end, the mesh still draws this far (its origin is
## the room's centre, its near wall half a room closer) then dithers out.
const VIS_MARGIN := 14.0
## Architectural variants per world; RoomGenerator picks one per room from
## the world hash (which props appear, their sizes).
const VARIANTS := 4
## Hideout (closet in the +x -z corner, opening west). Player body
## positions: inside, and just in front of its door.
const HIDE_POS := Vector3(4.05, 1.0, -4.05)
const HIDE_EXIT := Vector3(2.6, 1.0, -4.0)
const HIDE_YAW := PI / 2.0 # facing -x, out through the slit
const HIDE_REACH := 1.3
const PHASE_PORTAL_SCENE := preload("res://scenes/rooms/PhasePortal.tscn")
const ANCHOR_SCENE := preload("res://scenes/rooms/Anchor.tscn")
const GLITCH_SHADER := preload("res://shaders/glitch.gdshader")
## Every material kind a kit may use; prewarmed for every world.
const KINDS := ["floor", "wall", "accent", "trim", "edge", "grate", "dark", "void", "glitch"]

enum Exit { NORTH, SOUTH, EAST, WEST }

## Order: [north(-z), south(+z), east(+x), west(-x)]
@export var exits: Array[bool] = [true, true, true, true]
@export var phase_positive := false
@export var phase_negative := false
@export var w := 0
var variant := 0
var hideout := false
var has_anchor := false

static var _materials := {}
static var _grime := {}
# Unit cube's arrays, scaled per box on the CPU. (Reading a Mesh's arrays
# is a GPU readback with a sync: never per box.)
static var _cube: Array = []
static var _box_shapes := {}
## "w:exits:variant" -> {mesh, fixture, colliders}
static var _built := {}
## w -> {mesh, colliders}: the world's hideout, added to rooms that have one.
static var _hideouts := {}

var _mesh: MeshInstance3D
var _fixture: MeshInstance3D
var _light: OmniLight3D
var _fixture_mat: StandardMaterial3D
var _def: WorldDef
var _base_energy := 1.0
var _t := 0.0
var _seed := 0.0
var _disturb_t := 0.0

func _ready() -> void:
	_def = Worlds.def(w)
	_seed = randf() * 100.0
	var built := geometry(w, exits, variant)
	_mesh = _instance(built.mesh)
	_fixture_mat = StandardMaterial3D.new()
	_fixture_mat.albedo_color = _def.light_color
	_fixture_mat.emission_enabled = true
	_fixture_mat.emission = _def.light_color
	_fixture = _instance(built.fixture)
	_fixture.material_override = _fixture_mat
	_fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	add_child(body)
	var colliders: Array = built.colliders
	if hideout:
		var h: Dictionary = hideout_geometry(w)
		_instance(h.mesh)
		colliders = colliders + h.colliders
	for c: Array in colliders:
		var cs := CollisionShape3D.new()
		cs.shape = _shape(c[0])
		cs.position = c[1]
		body.add_child(cs)
	_build_light()
	if has_anchor:
		add_child(ANCHOR_SCENE.instantiate())
	# Opposite corners so both portals can coexist in one room.
	var corner := ROOM_SIZE / 2.0 - PORTAL_INSET
	if phase_positive:
		_build_phase_portal(1, Vector3(corner, PORTAL_HEIGHT, corner))
	if phase_negative:
		_build_phase_portal(-1, Vector3(-corner, PORTAL_HEIGHT, -corner))

func _process(delta: float) -> void:
	_t += delta
	var k := 1.0
	match _def.flicker:
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
		"heartbeat": # lub-dub, ~55 bpm
			var b := fmod(_t + _seed, 1.1)
			k = 0.45 + 0.55 * exp(-pow((b - 0.08) / 0.05, 2.0)) + 0.35 * exp(-pow((b - 0.3) / 0.06, 2.0))
		"glitch": # dead signal: holds, then cuts out or spikes
			k = 0.85
			var r := randf()
			if r < 0.025:
				k = 0.0
			elif r < 0.035:
				k = 1.8
	if _disturb_t > 0.0:
		_disturb_t -= delta
		k = 0.05 if randf() < 0.4 else randf_range(0.2, 1.7)
	_light.light_energy = _base_energy * k
	_fixture_mat.emission_energy_multiplier = 4.0 * k

## Violent flicker for a while: the entity is about to manifest, or the
## hideout is giving way.
func disturb(seconds: float) -> void:
	_disturb_t = maxf(_disturb_t, seconds)

## Real-time omni shadows re-render the scene 6x per light; RoomGenerator
## turns them on only for the room the player is in.
func set_shadow(on: bool) -> void:
	if _light:
		_light.shadow_enabled = on

## Beyond the fog's opaque end everything is already eaten: stop drawing
## the room and shading its light there. Lights were the single biggest GPU
## cost measured on an integrated GPU.
func set_fog_end(d: float) -> void:
	if _mesh:
		for mi in get_children():
			if mi is MeshInstance3D:
				mi.visibility_range_end = d + VIS_MARGIN
		_light.distance_fade_begin = d - 2.0

func _instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	# Dither out over the last metres instead of popping to a black hole at
	# the end of long straight corridors. Range: see set_fog_end.
	mi.visibility_range_end_margin = 10.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mi)
	return mi

func _build_phase_portal(direction: int, pos: Vector3) -> void:
	var portal := PHASE_PORTAL_SCENE.instantiate() as PhasePortal
	portal.direction = direction
	portal.target_w = Worlds.neighbor(w, direction)
	portal.position = pos
	add_child(portal)

func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0, _def.light_y, 0)
	# Just past the room's own corners. Without shadows a wider light only
	# leaks through walls into the neighbours, and every extra light
	# overlapping a pixel costs (1.6 rooms: ~4.5 ms more on an Iris GT1).
	_light.omni_range = ROOM_SIZE * 1.2
	_light.omni_attenuation = 0.8
	_light.light_color = _def.light_color
	_base_energy = _def.light_energy
	_light.shadow_enabled = false # see set_shadow()
	# ~50-70 rooms are attached; far lights aren't worth shading (begin: see
	# set_fog_end).
	_light.distance_fade_enabled = true
	_light.distance_fade_length = 10.0
	add_child(_light)

# --- geometry cache -------------------------------------------------------------

## Shared geometry for a room of world `lw` with these exits and variant,
## built on first request by running the world's kits.
static func geometry(lw: int, room_exits: Array[bool], v: int) -> Dictionary:
	var bits := 0
	for i in 4:
		bits |= int(room_exits[i]) << i
	var key := "%d:%d:%d" % [lw, bits, v]
	if not _built.has(key):
		var b := RoomBuilder.new(lw, room_exits, v)
		for kit in b.world.kits():
			kit.build(b)
		_built[key] = b.bake()
	return _built[key]

static func hideout_geometry(lw: int) -> Dictionary:
	if not _hideouts.has(lw):
		var b := RoomBuilder.new(lw, [false, false, false, false], 0)
		Worlds.def(lw).hideout.build(b)
		_hideouts[lw] = {"mesh": RoomBuilder.commit(b.pieces, lw, true), "colliders": b.colliders}
	return _hideouts[lw]

## Materials, their shaders and every room shape of every world, at level
## load: first entry into a world then attaches ~100 rooms without building
## anything.
static func prewarm() -> void:
	for lw in Worlds.ids():
		for kind: String in KINDS:
			layer_material(lw, kind)
		hideout_geometry(lw)
		for bits in 16:
			var e: Array[bool] = [bits & 1 != 0, bits & 2 != 0, bits & 4 != 0, bits & 8 != 0]
			for v in VARIANTS:
				geometry(lw, e, v)

static func unit_cube() -> Array:
	if _cube.is_empty():
		_cube = BoxMesh.new().get_mesh_arrays()
	return _cube

static func _shape(size: Vector3) -> BoxShape3D:
	if not _box_shapes.has(size):
		var bs := BoxShape3D.new()
		bs.size = size
		_box_shapes[size] = bs
	return _box_shapes[size]

# --- materials ----------------------------------------------------------------------

## Shared across all rooms of a world. Creating one on first use costs a
## long frame; prewarm() makes them all at level load.
static func layer_material(lw: int, kind: String) -> Material:
	var key := "%d:%s" % [lw, kind]
	if _materials.has(key):
		return _materials[key]
	var s := Worlds.def(lw)
	var mat: Material
	match kind:
		"glitch":
			var sm := ShaderMaterial.new()
			sm.shader = GLITCH_SHADER
			sm.set_shader_parameter("albedo", s.accent_color)
			sm.set_shader_parameter("emission", s.trim_color)
			mat = sm
		"trim", "edge", "grate":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color.BLACK if kind == "grate" else s.trim_color
			sm.emission_enabled = true
			sm.emission = s.trim_color
			# Trim low enough that the tonemapper keeps the hue instead of
			# clipping to white; edges are the only light ESTÁTICA has.
			sm.emission_energy_multiplier = {"trim": 1.1, "edge": 2.2, "grate": 0.3}[kind]
			mat = sm
		"dark", "void":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color.BLACK if kind == "void" else s.wall_color.darkened(0.75)
			sm.roughness = 1.0
			mat = sm
		_: # floor, wall, accent
			var sm := StandardMaterial3D.new()
			sm.albedo_color = s.get(kind + "_color")
			sm.albedo_texture = _grime_texture(lw)
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.12
			sm.roughness = s.roughness
			sm.metallic = s.metallic if kind == "accent" else s.metallic * 0.3
			mat = sm
	_materials[key] = mat
	return mat

## World-space noise (no seams between adjacent boxes), one per world.
static func _grime_texture(lw: int) -> Texture2D:
	if not _grime.has(lw):
		var noise := FastNoiseLite.new()
		noise.frequency = Worlds.def(lw).grime_frequency
		noise.fractal_octaves = 5
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.color_ramp = Gradient.new()
		tex.color_ramp.set_color(0, Color(0.72, 0.72, 0.72))
		tex.color_ramp.set_color(1, Color(1, 1, 1))
		_grime[lw] = tex
	return _grime[lw]
