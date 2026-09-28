extends Node3D
class_name Room

## Modular 10x10 m room, built procedurally so RoomGenerator can reuse one
## scene. The maze (which walls open into a 3 m door) is the same on every
## w-layer; each layer's `style` builds its own architecture around it:
## ceiling height, wall shape, ceiling, props, materials, light and flicker.
##
## Nothing collidable ever goes in the walkway (the plus joining the doors)
## or in the two portal corners, on any layer: a portal drops the player at
## the same x/z in the next layer, whatever stands there. The third corner
## (+x, -z) is kept for the hideout, so no style puts props there either.
##
## Geometry is plain boxes, batched into one surface per material and built
## once per (layer, exits, variant): every room with that key shares the
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
## Architectural variants per layer; RoomGenerator picks one per room from
## the world hash (which props appear, their sizes).
const VARIANTS := 4
## Inner face of the walls, from the room's centre.
const INNER := ROOM_SIZE / 2.0 - WALL_THICKNESS / 2.0
## Hideout (closet in the +x -z corner, opening west). Player body
## positions: inside, and just in front of its door.
const HIDE_POS := Vector3(4.05, 1.0, -4.05)
const HIDE_EXIT := Vector3(2.6, 1.0, -4.0)
const HIDE_YAW := PI / 2.0 # facing -x, out through the slit
const HIDE_REACH := 1.3
const PHASE_PORTAL_SCENE := preload("res://scenes/rooms/PhasePortal.tscn")
const ANCHOR_SCENE := preload("res://scenes/rooms/Anchor.tscn")
const GLITCH_SHADER := preload("res://shaders/glitch.gdshader")
## Every material kind a style may use; prewarmed for every layer.
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
## w -> {mesh, colliders}: the layer's hideout, added to rooms that have one.
static var _hideouts := {}

var _mesh: MeshInstance3D
var _fixture: MeshInstance3D
var _light: OmniLight3D
var _fixture_mat: StandardMaterial3D
var _style: Dictionary
var _base_energy := 1.0
var _t := 0.0
var _seed := 0.0
var _disturb_t := 0.0

# Build scratch, only while building a new key.
var _pieces := {} # kind -> [[size, pos], ...]
var _fixture_pieces: Array = []
var _colliders: Array = []
var _rng: RandomNumberGenerator

func _ready() -> void:
	_style = DimensionState.LAYERS[w]
	_seed = randf() * 100.0
	var built := geometry(w, exits, variant)
	_mesh = _instance(built.mesh)
	_fixture_mat = StandardMaterial3D.new()
	_fixture_mat.albedo_color = _style.light
	_fixture_mat.emission_enabled = true
	_fixture_mat.emission = _style.light
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
	portal.target_w = w + direction
	portal.position = pos
	add_child(portal)

func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.position = Vector3(0, _style.light_y, 0)
	# Just past the room's own corners. Without shadows a wider light only
	# leaks through walls into the neighbours, and every extra light
	# overlapping a pixel costs (1.6 rooms: ~4.5 ms more on an Iris GT1).
	_light.omni_range = ROOM_SIZE * 1.2
	_light.omni_attenuation = 0.8
	_light.light_color = _style.light
	_base_energy = _style.light_energy
	_light.shadow_enabled = false # see set_shadow()
	# ~50-70 rooms are attached; far lights aren't worth shading (begin: see
	# set_fog_end).
	_light.distance_fade_enabled = true
	_light.distance_fade_length = 10.0
	add_child(_light)

# --- geometry cache -------------------------------------------------------------

## Shared geometry for a room of layer `lw` with these exits and variant,
## built on first request.
static func geometry(lw: int, room_exits: Array[bool], v: int) -> Dictionary:
	var bits := 0
	for i in 4:
		bits |= int(room_exits[i]) << i
	var key := "%d:%d:%d" % [lw, bits, v]
	if not _built.has(key):
		var r := Room.new()
		r.w = lw
		r.exits = room_exits
		r.variant = v
		_built[key] = r._build()
		r.free()
	return _built[key]

## Materials, their shaders and every room shape of every layer, at level
## load: first entry into a layer then attaches ~100 rooms without building
## anything (measured: see RoomGenerator.init_world).
static func prewarm() -> void:
	for lw in range(DimensionState.W_MIN, DimensionState.W_MAX + 1):
		for kind: String in KINDS:
			layer_material(lw, kind)
		hideout_geometry(lw)
		for bits in 16:
			var e: Array[bool] = [bits & 1 != 0, bits & 2 != 0, bits & 4 != 0, bits & 8 != 0]
			for v in VARIANTS:
				geometry(lw, e, v)

func _build() -> Dictionary:
	_pieces = {}
	_fixture_pieces = []
	_colliders = []
	_style = DimensionState.LAYERS[w]
	_rng = RandomNumberGenerator.new()
	_rng.seed = hash([w, variant])
	var h: float = _style.height
	match _style.style:
		"carne": _carne(h)
		"sedimento": _sedimento(h)
		"umbral": _umbral(h)
		"eter": _eter(h)
		"estatica": _estatica(h)
	return {"mesh": _commit(_pieces, true), "fixture": _commit({"": _fixture_pieces}, false), "colliders": _colliders}

## One surface per material kind; UV.x = the box's index (the glitch shader
## moves each box as a whole). Normals only otherwise: materials use world
## triplanar mapping.
func _commit(pieces: Dictionary, with_materials: bool) -> ArrayMesh:
	if _cube.is_empty():
		var bm := BoxMesh.new()
		_cube = bm.get_mesh_arrays()
	var mesh := ArrayMesh.new()
	var index := 0
	for kind: String in pieces:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for p: Array in pieces[kind]:
			var size: Vector3 = p[0]
			var pos: Vector3 = p[1]
			var base := verts.size()
			for v: Vector3 in _cube[Mesh.ARRAY_VERTEX]:
				verts.append(v * size + pos)
				uvs.append(Vector2(index, 0))
			normals.append_array(_cube[Mesh.ARRAY_NORMAL])
			for i: int in _cube[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
			index += 1
		if verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if with_materials:
			mesh.surface_set_material(mesh.get_surface_count() - 1, layer_material(w, kind))
	return mesh

static func hideout_geometry(lw: int) -> Dictionary:
	if not _hideouts.has(lw):
		var r := Room.new()
		r.w = lw
		r._pieces = {}
		r._colliders = []
		r._hideout_parts(DimensionState.LAYERS[lw].style)
		_hideouts[lw] = {"mesh": r._commit(r._pieces, true), "colliders": r._colliders}
		r.free()
	return _hideouts[lw]

## Closet in the reserved corner: x 3.25..4.75, z -4.75..-3.25, 3.2 m tall,
## its back and one side being the room's own walls. The front has a slit
## at eye height (2.6 m) to look out through. Dressed per world.
func _hideout_parts(style: String) -> void:
	var body: String = {"sedimento": "accent", "umbral": "accent", "carne": "accent", "eter": "wall", "estatica": "void"}[style]
	var front: String = {"sedimento": "accent", "umbral": "wall", "carne": "floor", "eter": "accent", "estatica": "void"}[style]
	var top := 3.2
	var slit := Vector2(2.5, 2.7)
	_box(Vector3(1.5, top, 0.1), Vector3(4.0, top / 2.0, -3.3), body, true) # side
	_box(Vector3(1.5, 0.1, 1.5), Vector3(4.0, top - 0.05, -4.0), body) # roof
	_box(Vector3(0.1, slit.x, 1.4), Vector3(3.3, slit.x / 2.0, -4.05), front) # door, below the slit
	_box(Vector3(0.1, top - slit.y, 1.4), Vector3(3.3, (top + slit.y) / 2.0, -4.05), front) # above it
	_box(Vector3(0.1, top, 1.4), Vector3(3.3, top / 2.0, -4.05), "", true)
	match style:
		"sedimento": # metal locker: vent slats
			for y: float in [1.9, 2.05, 2.2]:
				_box(Vector3(0.03, 0.04, 1.0), Vector3(3.24, y, -4.05), "grate")
		"umbral": # office cabinet: a handle and a seam between two doors
			_box(Vector3(0.04, 0.3, 0.04), Vector3(3.23, 1.4, -3.95), "dark")
			_box(Vector3(0.02, slit.x, 0.02), Vector3(3.24, slit.x / 2.0, -4.05), "dark")
		"carne": # cavity between ribs: two ribs frame it
			for z: float in [-3.3, -4.7]:
				_box(Vector3(0.35, top + 0.4, 0.25), Vector3(3.2, (top + 0.4) / 2.0, z), "accent")
		"eter": # niche: its broken outline glows like the walls' tops
			_box(Vector3(0.12, 0.05, 1.5), Vector3(3.3, top, -4.0), "trim")
		"estatica": # a black hole in the room, drawn by its edges
			for z: float in [-3.3, -4.72]:
				_box(Vector3(0.05, top, 0.05), Vector3(3.24, top / 2.0, z), "edge")
			_box(Vector3(0.05, 0.05, 1.5), Vector3(3.24, top, -4.0), "edge")

static func _shape(size: Vector3) -> BoxShape3D:
	if not _box_shapes.has(size):
		var bs := BoxShape3D.new()
		bs.size = size
		_box_shapes[size] = bs
	return _box_shapes[size]

# --- building blocks --------------------------------------------------------------

## A box drawn with `kind` ("" = collision only) and, if solid, collided.
func _box(size: Vector3, pos: Vector3, kind: String, collide := false) -> void:
	if kind != "":
		if not _pieces.has(kind):
			_pieces[kind] = []
		_pieces[kind].append([size, pos])
	if collide:
		_colliders.append([size, pos])

## Light fixture box: drawn with the room's own flickering material.
func _fix(size: Vector3, pos: Vector3) -> void:
	_fixture_pieces.append([size, pos])

## Wall pieces between doors: each {center (y=0), from, to (along the wall),
## side (east/west wall: along z), inward (unit, into the room)}.
func _segments() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half := ROOM_SIZE / 2.0
	for dir in 4:
		var side := dir == Exit.EAST or dir == Exit.WEST
		var sgn := -1.0 if dir == Exit.NORTH or dir == Exit.WEST else 1.0
		var ranges := [[-half, half]] if not exits[dir] else [[-half, -DOOR_WIDTH / 2.0], [DOOR_WIDTH / 2.0, half]]
		for r: Array in ranges:
			var mid: float = (r[0] + r[1]) / 2.0
			out.append({
				"center": Vector3(sgn * half, 0, mid) if side else Vector3(mid, 0, sgn * half),
				"from": r[0], "to": r[1], "side": side,
				"inward": Vector3(-sgn, 0, 0) if side else Vector3(0, 0, -sgn),
			})
	return out

## Point on a wall segment: `along` the wall, `inset` metres in from the
## wall's centre plane, at height y.
func _at(seg: Dictionary, along: float, inset: float, y: float) -> Vector3:
	var p: Vector3 = seg.center + seg.inward * inset
	if seg.side:
		p.z = along
	else:
		p.x = along
	p.y = y
	return p

## Box size oriented to a wall: `length` along it, `depth` across it.
func _sized(seg: Dictionary, length: float, height: float, depth: float) -> Vector3:
	return Vector3(depth, height, length) if seg.side else Vector3(length, height, depth)

func _mid(seg: Dictionary) -> float:
	return (seg.from + seg.to) / 2.0

func _len(seg: Dictionary) -> float:
	return seg.to - seg.from

func _wall(seg: Dictionary, height: float) -> void:
	_box(_sized(seg, _len(seg), height, WALL_THICKNESS), _at(seg, _mid(seg), 0.0, height / 2.0), "wall", true)

## Strip on the wall's inner face (baseboard, edge line...).
func _strip(seg: Dictionary, y: float, height: float, depth: float, kind: String) -> void:
	_box(_sized(seg, _len(seg), height, depth), _at(seg, _mid(seg), WALL_THICKNESS / 2.0 + depth / 2.0, y), kind)

## Inside the hideout corner (kept clear in every room).
func _reserved(p: Vector3) -> bool:
	return p.x > 3.0 and p.z < -3.0

func _floor(kind: String) -> void:
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, -WALL_THICKNESS / 2.0, 0), kind, true)

func _ceiling(h: float, kind: String) -> void:
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, h + WALL_THICKNESS / 2.0, 0), kind)

# --- styles -------------------------------------------------------------------------

## Ribbed gut: ribs every metre along the walls, a low ceiling crossed by
## stepped arches, floor slabs at slightly uneven heights (visual only: the
## collision floor stays flat under them).
func _carne(h: float) -> void:
	_floor("dark")
	for i in 5:
		for j in 5:
			var top := _rng.randf_range(0.02, 0.07)
			_box(Vector3(1.86, 0.1, 1.86), Vector3(-4 + i * 2, top - 0.05, -4 + j * 2), "floor")
	_ceiling(h, "wall")
	var depth := _rng.randf_range(0.28, 0.42)
	for seg in _segments():
		_wall(seg, h)
		_strip(seg, TRIM_HEIGHT, 0.08, 0.06, "trim")
		for a in range(-4, 5):
			# Clear of door jambs (>= 0.3 m from a segment's end).
			var at := _at(seg, a, WALL_THICKNESS / 2.0 + depth / 2.0, h / 2.0)
			if a > seg.from + 0.3 and a < seg.to - 0.3 and not _reserved(at):
				_box(_sized(seg, 0.22, h, depth), at, "accent", true)
	# Arches across the room, stepping down to the east/west ribs.
	for z: float in [-3.0, 0.0, 3.0]:
		for step: Array in [[INNER, 3.75, 1.6], [3.75, 2.5, 1.0], [2.5, 1.25, 0.6], [1.25, 0.0, 0.35]]:
			for sgn: float in [-1.0, 1.0]:
				_box(Vector3(step[0] - step[1], step[2], 0.3), Vector3(sgn * (step[0] + step[1]) / 2.0, h - step[2] / 2.0, z), "accent")
	_fix(Vector3(0.9, 0.5, 0.9), Vector3(0, h - 0.25, 0))

## Industrial: pipes along the ceiling, one or two rusted columns in the
## corners without portals, faintly glowing floor grates.
func _sedimento(h: float) -> void:
	_floor("floor")
	_ceiling(h, "wall")
	for seg in _segments():
		_wall(seg, h)
		_strip(seg, TRIM_HEIGHT, 0.08, 0.06, "trim")
	var lanes := [-4.1, -3.5, -2.9, 2.9, 3.5, 4.1]
	for k in _rng.randi_range(2, 4):
		var z: float = lanes.pop_at(_rng.randi() % lanes.size())
		var s := 0.32 if _rng.randf() < 0.5 else 0.2
		var y := h - _rng.randf_range(0.4, 1.4)
		_box(Vector3(ROOM_SIZE - WALL_THICKNESS, s, s), Vector3(0, y, z), "accent")
		for x: float in [-3.0, 0.0, 3.0]:
			_box(Vector3(0.12, s + 0.1, s + 0.1), Vector3(x, y, z), "accent")
	# The one corner that's neither walkway, portal nor hideout.
	for p: Vector3 in [Vector3(-3.0, 0, 3.0)]:
		_box(Vector3(0.7, h, 0.7), p + Vector3(0, h / 2.0, 0), "accent", true)
		_box(Vector3(1.0, 0.35, 1.0), p + Vector3(0, 0.175, 0), "accent", true)
		_box(Vector3(1.0, 0.35, 1.0), p + Vector3(0, h - 0.175, 0), "accent")
	for x: float in [-3.2, 3.2]:
		_box(Vector3(0.6, 0.02, ROOM_SIZE - WALL_THICKNESS), Vector3(x, 0.01, 0), "grate")
	_fix(Vector3(2.4, 0.08, 0.5), Vector3(0, h - 0.04, 0))

## Backrooms: low drop ceiling of tiles hung under a dark slab (the gaps
## read as the grid), fluorescent tube pairs in four of the cells (one may
## be dead), a tall skirting board with the signal line on top.
func _umbral(h: float) -> void:
	_floor("floor")
	_box(Vector3(ROOM_SIZE, 0.3, ROOM_SIZE), Vector3(0, h + 0.15, 0), "dark")
	for seg in _segments():
		_wall(seg, h)
		_strip(seg, 0.175, 0.35, 0.06, "accent")
		_strip(seg, 0.36, 0.03, 0.07, "trim")
	var pitch := 1.25
	var panels := [Vector2i(2, 2), Vector2i(2, 5), Vector2i(5, 2), Vector2i(5, 5)]
	var dead := _rng.randi() % 6 # 4, 5: all lit
	var missing := [Vector2i(_rng.randi() % 8, _rng.randi() % 8)] if variant >= 2 else []
	for i in 8:
		for j in 8:
			var cell := Vector2i(i, j)
			var c := Vector3(-ROOM_SIZE / 2.0 + pitch * (i + 0.5), h - 0.02, -ROOM_SIZE / 2.0 + pitch * (j + 0.5))
			var p := panels.find(cell)
			if p >= 0:
				_box(Vector3(1.19, 0.04, 1.19), c, "accent")
				if p != dead:
					for dx: float in [-0.25, 0.25]:
						_fix(Vector3(0.1, 0.04, 1.1), c + Vector3(dx, -0.03, 0))
			elif not cell in missing:
				_box(Vector3(1.19, 0.04, 1.19), c, "wall")

## Violet hall: a ceiling lost 16 m up, walls that fall short of it at
## ragged heights (their broken tops outlined), floor tiles floating over
## a void with some missing (the collision floor underneath is continuous).
func _eter(h: float) -> void:
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, -WALL_THICKNESS / 2.0, 0), "", true)
	_box(Vector3(ROOM_SIZE, WALL_THICKNESS, ROOM_SIZE), Vector3(0, -WALL_THICKNESS / 2.0 - 0.08, 0), "void")
	for i in 5:
		for j in 5:
			if _rng.randf() < 0.2:
				continue
			_box(Vector3(1.7, 0.2, 1.7), Vector3(-4 + i * 2, -0.1, -4 + j * 2), "floor")
	_ceiling(h, "accent")
	for seg in _segments():
		var wh := _rng.randf_range(5.0, 11.0)
		_wall(seg, wh)
		_box(_sized(seg, _len(seg), 0.06, WALL_THICKNESS + 0.04), _at(seg, _mid(seg), 0.0, wh), "trim")
		_strip(seg, TRIM_HEIGHT, 0.08, 0.06, "trim")
	_fix(Vector3(0.5, 0.5, 0.5), Vector3(0, _style.light_y + 0.6, 0))

## Black geometry drawn only by its glowing edges: lines where walls meet
## floor and ceiling, at every jamb and corner, a cross on the floor. Some
## dark panels and floating blocks tremble (glitch shader).
func _estatica(h: float) -> void:
	_floor("floor")
	_ceiling(h, "wall")
	for seg in _segments():
		_wall(seg, h)
		_strip(seg, 0.025, 0.05, 0.05, "edge")
		_strip(seg, h - 0.025, 0.05, 0.05, "edge")
		for a: float in [seg.from, seg.to]:
			var edge := clampf(a, -INNER + 0.025, INNER - 0.025)
			_box(Vector3(0.05, h, 0.05), _at(seg, edge, WALL_THICKNESS / 2.0 + 0.025, h / 2.0), "edge")
	_box(Vector3(ROOM_SIZE - WALL_THICKNESS, 0.01, 0.04), Vector3(0, 0.005, 0), "edge")
	_box(Vector3(0.04, 0.01, ROOM_SIZE - WALL_THICKNESS), Vector3(0, 0.005, 0), "edge")
	var segs := _segments()
	for k in _rng.randi_range(2, 4):
		var seg: Dictionary = segs[_rng.randi() % segs.size()]
		var length := minf(_rng.randf_range(1.0, 2.5), _len(seg) - 0.4)
		var along := _rng.randf_range(seg.from + 0.2 + length / 2.0, seg.to - 0.2 - length / 2.0)
		var ph := _rng.randf_range(1.0, 3.0)
		var at := _at(seg, along, WALL_THICKNESS / 2.0 + 0.06, _rng.randf_range(1.0, h - 2.0 - ph / 2.0) + ph / 2.0)
		if not _reserved(at):
			_box(_sized(seg, length, ph, 0.05), at, "glitch")
	for k in 1 + variant % 2:
		var s := _rng.randf_range(0.4, 1.0)
		_box(Vector3.ONE * s, Vector3(_rng.randf_range(-3, 3), _rng.randf_range(3.5, 7.0), _rng.randf_range(-3, 3)), "glitch")
	_fix(Vector3(3.0, 0.03, 0.03), Vector3(0, h - 0.05, 0))

# --- materials ----------------------------------------------------------------------

## Shared across all rooms of a layer. Creating one on first use costs a
## long frame; prewarm() makes them all at level load.
static func layer_material(lw: int, kind: String) -> Material:
	var key := "%d:%s" % [lw, kind]
	if _materials.has(key):
		return _materials[key]
	var s: Dictionary = DimensionState.LAYERS[lw]
	var mat: Material
	match kind:
		"glitch":
			var sm := ShaderMaterial.new()
			sm.shader = GLITCH_SHADER
			sm.set_shader_parameter("albedo", s.accent)
			sm.set_shader_parameter("emission", s.trim)
			mat = sm
		"trim", "edge", "grate":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color.BLACK if kind == "grate" else s.trim
			sm.emission_enabled = true
			sm.emission = s.trim
			# Trim low enough that the tonemapper keeps the hue instead of
			# clipping to white; edges are the only light ESTÁTICA has.
			sm.emission_energy_multiplier = {"trim": 1.1, "edge": 2.2, "grate": 0.3}[kind]
			mat = sm
		"dark", "void":
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color.BLACK if kind == "void" else (s.wall as Color).darkened(0.75)
			sm.roughness = 1.0
			mat = sm
		_: # floor, wall, accent
			var sm := StandardMaterial3D.new()
			sm.albedo_color = s[kind]
			sm.albedo_texture = _grime_texture(lw)
			sm.uv1_triplanar = true
			sm.uv1_world_triplanar = true
			sm.uv1_scale = Vector3.ONE * 0.12
			sm.roughness = s.rough
			sm.metallic = s.metal if kind == "accent" else s.metal * 0.3
			mat = sm
	_materials[key] = mat
	return mat

## World-space noise (no seams between adjacent boxes), one per layer.
static func _grime_texture(lw: int) -> Texture2D:
	if not _grime.has(lw):
		var noise := FastNoiseLite.new()
		noise.frequency = DimensionState.LAYERS[lw].noise
		noise.fractal_octaves = 5
		var tex := NoiseTexture2D.new()
		tex.noise = noise
		tex.seamless = true
		tex.color_ramp = Gradient.new()
		tex.color_ramp.set_color(0, Color(0.72, 0.72, 0.72))
		tex.color_ramp.set_color(1, Color(1, 1, 1))
		_grime[lw] = tex
	return _grime[lw]
