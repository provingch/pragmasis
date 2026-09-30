extends Node3D
class_name Room

## Modular 10x10 m room, one cube (CELL_H tall) of an unbounded 3D grid,
## built procedurally so RoomGenerator can reuse one scene. The maze (which walls open into a 3 m door) is the same in every
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
## A cube's height: floors are this far apart, for every world (a world's
## ceiling sits somewhere inside its cube).
const CELL_H := 10.0
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
const BEAM_SHADER := preload("res://shaders/beam.gdshader")
const BLINK_SHADER := preload("res://shaders/blink.gdshader")
## Every material kind a kit may use; each world warms them all up.
const KINDS := ["floor", "wall", "accent", "trim", "edge", "dark", "void", "glitch", "beam", "blink"]
## Physics layer of see-through colliders (bars): the player collides with
## it, the entity's sight rays (world layer only) pass.
const SEE_THROUGH_LAYER := 8

enum Exit { NORTH, SOUTH, EAST, WEST }

## Order: [north(-z), south(+z), east(+x), west(-x)]
@export var exits: Array[bool] = [true, true, true, true]
## The room's portal: world it leads to (-1: none) and whether it's a
## fissure. Deeper targets stand in the +x +z corner, shallower in -x -z.
@export var link_target := -1
@export var link_fissure := false
@export var w := 0
var cell := Vector3i.ZERO
var variant := 0
## Shape flags (see shape()): spiral up / shaft from below, a void cell,
## faces open to the void.
var up := false
var down := false
var void_cell := false
var open: Array[bool] = [false, false, false, false, false]
var hideout := false
var has_anchor := false
## Has its light (see WorldDef.light_chance); a dark room has none at all.
var lit := true
var _zones: Array = []

static var _materials := {}
static var _grime := {} # Vector2(frequency, amount) -> ImageTexture
static var _grime_tasks := {} # Vector2(frequency, amount) -> WorkerThreadPool task id
# Unit cube's arrays, scaled per box on the CPU. (Reading a Mesh's arrays
# is a GPU readback with a sync: never per box.)
static var _cube: Array = []
static var _box_shapes := {}
## "w:exits:variant" -> {mesh, fixture, colliders}
static var _built := {}
## w -> {mesh, colliders}: the world's hideout, added to rooms that have one.
static var _hideouts := {}
## "w:target" -> mesh: ORIENTACIÓN's floor line from the centre to a door
## or a portal corner.
static var _guides := {}

var _mesh: MeshInstance3D
var _fixture: MeshInstance3D
var _light: Light3D
var _fixture_mat: StandardMaterial3D
var _def: WorldDef
var _base_energy := 1.0
var _t := 0.0
var _seed := 0.0
var _disturb_t := 0.0

func _ready() -> void:
	_def = Worlds.def(w)
	_seed = randf() * 100.0
	var built := geometry(w, exits, variant, shape())
	_zones = built.zones
	_mesh = _instance(built.mesh)
	_fixture_mat = StandardMaterial3D.new()
	_fixture_mat.albedo_color = _def.light_color if lit else _def.wall_color.darkened(0.6)
	_fixture_mat.emission_enabled = lit
	_fixture_mat.emission = _def.light_color
	_fixture = _instance(built.fixture)
	_fixture.material_override = _fixture_mat
	_fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	add_child(body)
	var bars := StaticBody3D.new()
	bars.collision_layer = SEE_THROUGH_LAYER
	add_child(bars)
	var colliders: Array = built.colliders
	if hideout:
		var h: Dictionary = hideout_geometry(w)
		_instance(h.mesh)
		colliders = colliders + h.colliders
	for c: Array in colliders:
		var cs := CollisionShape3D.new()
		cs.shape = _shape(c[0])
		cs.transform = Transform3D(c[2] if c.size() > 2 else Basis.IDENTITY, c[1])
		(bars if c.size() > 3 and c[3] else body).add_child(cs)
	if lit and not void_cell:
		_build_light()
	else:
		set_process(false)
	if has_anchor:
		add_child(ANCHOR_SCENE.instantiate())
	if _def.guide_lines:
		var to := RoomGenerator.guide(cell, w)
		if to != Vector2.ZERO:
			_instance(guide_mesh(w, to))
	if link_target >= 0:
		var corner := (ROOM_SIZE / 2.0 - PORTAL_INSET) * (1.0 if link_target > w else -1.0)
		var portal := PHASE_PORTAL_SCENE.instantiate() as PhasePortal
		portal.target_w = link_target
		portal.fissure = link_fissure
		portal.position = Vector3(corner, PORTAL_HEIGHT, corner)
		add_child(portal)

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

## The player's speed multiplier at a point in this room (local x/z):
## the slowest floor zone it's in.
func speed_at(local: Vector3) -> float:
	var k := 1.0
	for z: Array in _zones:
		if (z[0] as Rect2).has_point(Vector2(local.x, local.z)):
			k = minf(k, z[1])
	return k

## Violent flicker for a while: the entity is about to manifest, or the
## hideout is giving way.
func disturb(seconds: float) -> void:
	_disturb_t = maxf(_disturb_t, seconds)

## Room lights shine only on the player's floor: the others are seen
## through shafts and open faces, where ambient light does.
func set_floor_active(on: bool) -> void:
	if _light:
		_light.visible = on

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
		if _light:
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

## Omni, or with WorldDef.spot_angle a spot aimed straight down: a hard
## pool of light under it and the rest of the room left dark.
func _build_light() -> void:
	if _def.spot_angle > 0.0:
		var spot := SpotLight3D.new()
		spot.rotation.x = -PI / 2.0
		spot.spot_angle = _def.spot_angle
		spot.spot_range = _def.light_y + 4.0
		spot.spot_attenuation = 0.6
		_light = spot
	else:
		var omni := OmniLight3D.new()
		# Just past the room's own corners. Without shadows a wider light only
		# leaks through walls into the neighbours, and every extra light
		# overlapping a pixel costs (1.6 rooms: ~4.5 ms more on an Iris GT1).
		omni.omni_range = maxf(ROOM_SIZE * 1.2, _def.light_y + 3.0)
		omni.omni_attenuation = 0.8
		_light = omni
	_light.position = Vector3(0, _def.light_y, 0)
	_light.light_color = _def.light_color
	_base_energy = _def.light_energy
	_light.shadow_enabled = false # see set_shadow()
	# ~50-70 rooms are attached; far lights aren't worth shading (begin: see
	# set_fog_end).
	_light.distance_fade_enabled = true
	_light.distance_fade_length = 10.0
	add_child(_light)

# --- geometry cache -------------------------------------------------------------

## This room's shape flags, as one int (part of the geometry's cache key):
## 1 spiral up, 2 shaft from below, 4 void cell, 8.. open faces (N, S, E,
## W, ceiling), 256/512 a void cell's portal pad (+x +z / -x -z).
func shape() -> int:
	var s := int(up) | int(down) << 1 | int(void_cell) << 2
	for i in 5:
		s |= int(open[i]) << (3 + i)
	if void_cell and link_target >= 0:
		s |= 256 if link_target > w else 512
	return s

## Shared geometry for a room of world `lw` with these exits, variant and
## shape, built on first request: a void cell's bridges, or the world's
## kits (plus the spiral, and rails where faces are open).
static func geometry(lw: int, room_exits: Array[bool], v: int, s := 0) -> Dictionary:
	var bits := 0
	for i in 4:
		bits |= int(room_exits[i]) << i
	var key := "%d:%d:%d:%d" % [lw, bits, v, s]
	if not _built.has(key):
		var b := RoomBuilder.new(lw, room_exits, v)
		b.up = s & 1 != 0
		b.down = s & 2 != 0
		for i in 5:
			b.open[i] = s & (8 << i) != 0
		if s & 4 != 0:
			b.void_cell(1 if s & 256 else (-1 if s & 512 else 0))
		else:
			for kit in b.world.kits():
				kit.build(b)
			b.open_rails()
		if b.up:
			b.spiral()
		_built[key] = b.bake()
	return _built[key]

## A laser line on the floor from the room's centre to `to` (room x/z),
## ending in an arrowhead.
static func guide_mesh(lw: int, to: Vector2) -> ArrayMesh:
	var key := "%d:%s" % [lw, to]
	if not _guides.has(key):
		var yaw := atan2(-to.y, to.x) # about +y: +x toward `to`
		var turn := Basis(Vector3.UP, yaw)
		var length := to.length() - 0.3
		var line: Array = [[Vector3(length, 0.02, 0.05), turn * Vector3(length / 2.0, 0.012, 0), turn]]
		for s: float in [-1.0, 1.0]:
			var head := Basis(Vector3.UP, yaw + s * 2.5)
			line.append([Vector3(0.5, 0.02, 0.05), turn * Vector3(length, 0.012, 0) + head * Vector3(0.25, 0, 0), head])
		_guides[key] = RoomBuilder.commit({"edge": line}, lw, true)
	return _guides[key]

static func hideout_geometry(lw: int) -> Dictionary:
	if not _hideouts.has(lw):
		var b := RoomBuilder.new(lw, [false, false, false, false], 0)
		HideoutKit.build(b)
		_hideouts[lw] = {"mesh": RoomBuilder.commit(b.pieces, lw, true), "colliders": b.colliders}
	return _hideouts[lw]

## Everything a world needs before its rooms can appear without a hitch,
## as small steps (one material, the hideout, one room shape each) that
## RoomGenerator spreads over frames. Built things are cached, so running a
## step twice costs nothing.
static func warm_steps(lw: int) -> Array[Callable]:
	var steps: Array[Callable] = []
	for kind: String in KINDS:
		steps.append(func() -> void: layer_material(lw, kind))
	steps.append(func() -> void: hideout_geometry(lw))
	for bits in 16:
		var e: Array[bool] = [bits & 1 != 0, bits & 2 != 0, bits & 4 != 0, bits & 8 != 0]
		for v in VARIANTS:
			steps.append(func() -> void: geometry(lw, e, v))
	return steps

static func clear_caches() -> void:
	for task: int in _grime_tasks.values():
		WorkerThreadPool.wait_for_task_completion(task)
	for cache: Dictionary in [_materials, _grime, _grime_tasks, _box_shapes, _built, _hideouts, _guides]:
		cache.clear()

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
## long frame; warm_steps() makes them ahead of time.
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
			sm.set_shader_parameter("emission_energy", 0.12)
			mat = sm
		"blink": # lines of light that drop out and spike
			var sm := ShaderMaterial.new()
			sm.shader = BLINK_SHADER
			sm.set_shader_parameter("emission", s.trim_color)
			sm.set_shader_parameter("emission2", s.light_color)
			mat = sm
		"beam": # a shaft of light: additive, fading toward its silhouette
			var sm := ShaderMaterial.new()
			sm.shader = BEAM_SHADER
			sm.set_shader_parameter("color", s.light_color)
			mat = sm
		"trim", "edge":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = s.trim_color
			sm.emission_enabled = true
			sm.emission = s.trim_color
			# Trim low enough that the tonemapper keeps the hue instead of
			# clipping to white; edges are the only light ESTÁTICA has.
			sm.emission_energy_multiplier = {"trim": 1.1, "edge": 2.2}[kind]
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
			sm.roughness = s.floor_roughness if kind == "floor" and s.floor_roughness >= 0.0 else s.roughness
			sm.metallic = s.metallic if kind == "accent" else s.metallic * 0.3
			mat = sm
	_materials[key] = mat
	return mat

## World-space grime noise (no seams between adjacent boxes), one per
## frequency: worlds that share it share the texture. Made on a worker
## thread (a flat white 1x1 stands in until it's there): NoiseTexture2D does
## its first generation on the main thread, ~100 ms for this one (measured
## on the integrated GPU's host), a hitch every time a world warmed up.
## `now`: generate right here (level load).
static func _grime_texture(lw: int, now := false) -> Texture2D:
	var f := Vector2(Worlds.def(lw).grime_frequency, Worlds.def(lw).grime)
	if not _grime.has(f):
		var blank := Image.create_empty(1, 1, false, Image.FORMAT_L8)
		blank.fill(Color.WHITE)
		var tex := ImageTexture.create_from_image(blank)
		_grime[f] = tex
		if now:
			tex.set_image(_grime_image(f))
		else:
			_grime_tasks[f] = WorkerThreadPool.add_task(func() -> void: _grime_ready.call_deferred(f, _grime_image(f)))
	return _grime[f]

static func _grime_ready(f: Vector2, img: Image) -> void:
	# Tasks must be waited on to release what they hold (here: the texture).
	WorkerThreadPool.wait_for_task_completion(_grime_tasks[f])
	_grime_tasks.erase(f)
	if _grime.has(f):
		_grime[f].set_image(img)

## 512x512 seamless fractal noise (x: frequency), remapped to
## (1 - y)..1.0 grey (y: amount), with mipmaps.
static func _grime_image(f: Vector2) -> Image:
	var noise := FastNoiseLite.new()
	noise.frequency = f.x
	noise.fractal_octaves = 5
	var img := noise.get_seamless_image(512, 512)
	var data := img.get_data()
	var low := roundi(255 * (1.0 - f.y))
	for i in data.size():
		data[i] = low + data[i] * (255 - low) / 255
	img.set_data(512, 512, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return img
