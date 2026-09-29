extends Node3D
class_name PlayerAvatar

## The player's body (docs/referencias/personaje.png): rigid dark low-poly
## prisms with light emissive edges, an inverted triangle for a head. All
## geometry is built here; no rig, no animation assets: joints are Node3Ds
## turned procedurally from move_speed / running / crouching.
##
## Knows nothing about input or physics: whoever owns it (the local
## Player, a menu, later a remote player) sets those three each frame and
## edge_color once. Origin at the feet, facing -Z.

## Light edges' color (per player, once there are several).
@export var edge_color := Color("f2e6d4"):
	set(v):
		edge_color = v
		if _edge_mat:
			_edge_mat.albedo_color = v
			_edge_mat.emission = v
## Uniform scale over a ~2 m base figure (the game's eye sits at 2.5 m).
@export var size := 1.3:
	set(v):
		size = v
		scale = Vector3.ONE * v
## First person: everything above the legs only casts shadow (the camera
## sits inside the head), the legs stay visible when looking down.
@export var first_person := false:
	set(v):
		first_person = v
		_apply_view()

## Ground speed (m/s), set by the owner every frame.
var move_speed := 0.0
var running := false
var crouching := false

const WALK_AMP := 0.45
const RUN_AMP := 0.8
## Leg cycle radians per metre walked: two steps per cycle, in time with
## Player's head-bob (BOB_FREQ / 2).
const STRIDE := 0.8
const EDGE := 0.022

var _dark_mat := StandardMaterial3D.new()
var _edge_mat := StandardMaterial3D.new()
var _j := {} # joint name -> Node3D
var _upper: Array[MeshInstance3D] = [] # hidden in first person
var _phase := 0.0
var _t := 0.0
var _gait := 0.0 # 0 still .. 1 running, smoothed
var _crouch := 0.0

func _ready() -> void:
	_dark_mat.albedo_color = Color(0.035, 0.035, 0.04)
	_dark_mat.roughness = 0.55
	_dark_mat.metallic = 0.15
	_edge_mat.emission_enabled = true
	_edge_mat.emission_energy_multiplier = 1.6
	edge_color = edge_color
	scale = Vector3.ONE * size
	_build()
	_apply_view()

# --- the figure ----------------------------------------------------------------------

func _build() -> void:
	var hips := _joint("hips", self, Vector3(0, 1.0, 0))
	_part(hips, _prism(0.2, 0.42, 0.34, 0.2, true), Vector3(0, -0.1, 0), false)
	var torso := _joint("torso", hips, Vector3(0, 0.08, 0))
	_part(torso, _prism(0.5, 0.36, 0.56, 0.24, false), Vector3.ZERO, false)
	var neck := _joint("neck", torso, Vector3(0, 0.5, 0))
	_part(neck, _prism(0.09, 0.08, 0.08, 0.08, false), Vector3.ZERO, false)
	var head := _joint("head", neck, Vector3(0, 0.07, 0))
	_part(head, _triangle(0.62, 0.54, 0.15), Vector3.ZERO, false)
	for s: float in [-1.0, 1.0]:
		var side := "l" if s < 0.0 else "r"
		var shoulder := _joint("arm_" + side, torso, Vector3(s * 0.31, 0.46, 0))
		_part(shoulder, _prism(0.34, 0.12, 0.09, 0.1, true), Vector3.ZERO, false)
		var elbow := _joint("forearm_" + side, shoulder, Vector3(0, -0.34, 0))
		_part(elbow, _prism(0.3, 0.09, 0.06, 0.08, true), Vector3.ZERO, false)
		var wrist := _joint("hand_" + side, elbow, Vector3(0, -0.3, 0))
		_part(wrist, _diamond(0.2, 0.12, 0.06), Vector3.ZERO, false)
		var hip := _joint("thigh_" + side, hips, Vector3(s * 0.11, -0.02, 0))
		_part(hip, _prism(0.46, 0.16, 0.11, 0.14, true), Vector3.ZERO, true)
		var knee := _joint("shin_" + side, hip, Vector3(0, -0.46, 0))
		_part(knee, _prism(0.44, 0.11, 0.07, 0.1, true), Vector3.ZERO, true)
		var ankle := _joint("foot_" + side, knee, Vector3(0, -0.44, 0))
		_part(ankle, _foot(0.16, 0.32, 0.08), Vector3.ZERO, true)

func _joint(n: String, parent: Node3D, at: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = at
	parent.add_child(j)
	_j[n] = j
	return j

func _part(j: Node3D, mesh: ArrayMesh, at: Vector3, lower: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	j.add_child(mi)
	if not lower:
		_upper.append(mi)

func _apply_view() -> void:
	for mi in _upper:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

# --- meshes: dark faces (surface 0), light edges (surface 1) ------------------------

## Four-sided limb from y = 0 down to -length (up to +length if not `down`),
## a rhombus in section, `w0` wide at the joint, `w1` at the far end.
## Edges light along its two sides.
func _prism(length: float, w0: float, w1: float, depth: float, down: bool) -> ArrayMesh:
	var y1 := -length if down else length
	var ring := func(w: float, y: float) -> Array:
		return [Vector3(w / 2.0, y, 0), Vector3(0, y, -depth / 2.0), Vector3(-w / 2.0, y, 0), Vector3(0, y, depth / 2.0)]
	var a: Array = ring.call(w0, 0.0)
	var b: Array = ring.call(w1, y1)
	var faces := []
	for i in 4:
		var k := (i + 1) % 4
		faces.append([a[i], a[k], b[k], b[i]])
	faces.append([a[0], a[3], a[2], a[1]])
	faces.append([b[0], b[1], b[2], b[3]])
	var bars := [[a[0], b[0]], [a[2], b[2]]]
	return _mesh(faces, bars)

## The head: an inverted triangle (apex at y = 0), rimmed on both faces.
func _triangle(width: float, height: float, depth: float) -> ArrayMesh:
	var tris := []
	for z: float in [-depth / 2.0, depth / 2.0]:
		tris.append([Vector3(0, 0, z), Vector3(width / 2.0, height, z), Vector3(-width / 2.0, height, z)])
	var p: Array = tris[0]
	var q: Array = tris[1]
	var faces := [[p[0], p[1], p[2]], [q[0], q[2], q[1]]]
	for i in 3:
		var k := (i + 1) % 3
		faces.append([p[i], q[i], q[k], p[k]])
	var bars := []
	for tri: Array in [p, q]:
		for i in 3:
			bars.append([tri[i], tri[(i + 1) % 3]])
	return _mesh(faces, bars)

## Hand: a diamond hanging from the wrist.
func _diamond(length: float, width: float, depth: float) -> ArrayMesh:
	var top := Vector3.ZERO
	var tip := Vector3(0, -length, 0)
	var y := -length * 0.35
	var mid := [Vector3(width / 2.0, y, 0), Vector3(0, y, -depth / 2.0), Vector3(-width / 2.0, y, 0), Vector3(0, y, depth / 2.0)]
	var faces := []
	for i in 4:
		var k := (i + 1) % 4
		faces.append([top, mid[k], mid[i]])
		faces.append([tip, mid[i], mid[k]])
	return _mesh(faces, [[top, mid[0]], [mid[0], tip], [top, mid[2]], [mid[2], tip]])

## Foot: a wedge from the ankle to a point ahead, on the ground.
func _foot(width: float, length: float, height: float) -> ArrayMesh:
	var ankle := Vector3(0, 0, 0.02)
	var toe := Vector3(0, -height, -length * 0.75)
	var heel_l := Vector3(-width / 2.0, -height, length * 0.2)
	var heel_r := Vector3(width / 2.0, -height, length * 0.2)
	var faces := [[ankle, toe, heel_r], [ankle, heel_l, toe], [ankle, heel_r, heel_l], [toe, heel_l, heel_r]]
	return _mesh(faces, [[heel_l, toe], [heel_r, toe], [ankle, toe]])

## Flat-shaded faces (convex polygons, any winding: fixed to face outward
## from the centroid) and edge bars, as two surfaces.
func _mesh(faces: Array, bars: Array) -> ArrayMesh:
	var centre := Vector3.ZERO
	var n := 0
	for f: Array in faces:
		for v: Vector3 in f:
			centre += v
			n += 1
	centre /= n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var normal: Vector3 = (f[1] - f[0]).cross(f[2] - f[0]).normalized()
		if normal.dot(f[0] as Vector3 - centre) < 0.0:
			f = f.duplicate()
			f.reverse()
			normal = -normal
		for i in range(1, f.size() - 1):
			for v: Vector3 in [f[0], f[i + 1], f[i]]:
				st.set_normal(normal)
				st.add_vertex(v)
	st.set_material(_dark_mat)
	var mesh := st.commit()
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: Array in bars:
		_bar(st, b[0], b[1], centre)
	st.set_material(_edge_mat)
	return st.commit(mesh)

## A thin square bar from p0 to p1, nudged outward from `centre`.
func _bar(st: SurfaceTool, p0: Vector3, p1: Vector3, centre: Vector3) -> void:
	var axis := (p1 - p0).normalized()
	var out := ((p0 + p1) / 2.0 - centre)
	out = (out - axis * out.dot(axis)).normalized()
	var side := axis.cross(out).normalized()
	var h := EDGE / 2.0
	var c := [p0 + out * h, p1 + out * h]
	var corners := []
	for e: Vector3 in c:
		corners.append([e + (out + side) * h, e + (out - side) * h, e + (-out - side) * h, e + (-out + side) * h])
	for i in 4:
		var k := (i + 1) % 4
		var quad := [corners[0][i], corners[1][i], corners[1][k], corners[0][k]]
		var normal: Vector3 = ((quad[0] + quad[2]) / 2.0 - (c[0] + c[1]) / 2.0).normalized()
		for v: Vector3 in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			st.set_normal(normal)
			st.add_vertex(v)

# --- motion ------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	var target := clampf(move_speed / 7.0, 0.0, 1.0) if move_speed > 0.1 else 0.0
	_gait = move_toward(_gait, target, delta * 3.0)
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, delta * 4.0)
	_phase += delta * move_speed * STRIDE
	var run := clampf((_gait - 0.55) / 0.4, 0.0, 1.0) if running or _gait > 0.6 else 0.0
	var moving := clampf(_gait / 0.3, 0.0, 1.0)
	var amp := lerpf(WALK_AMP, RUN_AMP, run) * moving
	var breath := sin(_t * 1.4)
	for s: float in [-1.0, 1.0]:
		var side := "l" if s < 0.0 else "r"
		var swing := sin(_phase + (0.0 if s < 0.0 else PI)) * amp
		var knee := (0.15 + lerpf(0.45, 1.0, run) * maxf(0.0, sin(_phase + (0.0 if s < 0.0 else PI) - 1.3))) * moving
		_j["thigh_" + side].rotation.x = swing + _crouch * 1.15
		_j["shin_" + side].rotation.x = -knee - _crouch * 1.95
		_j["foot_" + side].rotation.x = -(_j["thigh_" + side].rotation.x + _j["shin_" + side].rotation.x) * 0.8
		_j["arm_" + side].rotation.x = -swing * lerpf(0.7, 1.0, run) + _crouch * 0.5
		_j["arm_" + side].rotation.z = s * (0.06 + 0.02 * breath * (1.0 - moving))
		_j["forearm_" + side].rotation.x = lerpf(0.15, 1.1, run) * moving + 0.1 + _crouch * 0.6
	var bob := absf(sin(_phase)) * 0.05 * moving
	_j["hips"].position.y = 1.0 - _crouch * 0.4 + bob + 0.004 * breath
	_j["torso"].rotation.x = -0.22 * run - 0.4 * _crouch + 0.015 * breath * (1.0 - moving)
	_j["head"].rotation.x = 0.1 * run + 0.25 * _crouch
	_j["head"].rotation.z = 0.04 * sin(_t * 0.5) * (1.0 - moving)
