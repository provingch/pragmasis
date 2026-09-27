extends MultiMeshInstance3D
class_name Tesseract

## Actual 4D hypercube: 16 vertices rotated in the XW, YZ and ZW planes by
## `phase`, perspective-projected to 3D every frame. The shifting sizes are
## real projection effects, not a fake pulse. Edges and vertex knots are
## MultiMesh instances. Low `coherence` = thin, translucent, dropping edges.

const SIZE := 0.45
const PROJ_DIST := 4.0 # > max |w| (2) or the projection blows up
const EDGE_THICKNESS := 0.045
const KNOT_SIZE := 0.11

var phase := 0.0
var coherence := 1.0
var color := Color(1.0, 0.12, 0.1)

var _verts: Array[Vector4] = []
var _edges: Array[Vector2i] = []

func _ready() -> void:
	for i in 16:
		_verts.append(Vector4(1 if i & 1 else -1, 1 if i & 2 else -1, 1 if i & 4 else -1, 1 if i & 8 else -1))
	for i in 16:
		for bit in 4:
			var j := i ^ (1 << bit)
			if j > i:
				_edges.append(Vector2i(i, j))
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = box
	multimesh.instance_count = _edges.size() + _verts.size()

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var pts := _project()
	var thick := EDGE_THICKNESS * lerpf(0.35, 1.0, coherence)
	# Dimmer when incoherent so its layer hue survives the tonemapper.
	var edge_col := Color(color * lerpf(0.5, 1.0, coherence), lerpf(0.3, 1.0, coherence))
	var dropout := (1.0 - coherence) * 0.45

	for e in _edges.size():
		var a := pts[_edges[e].x]
		var b := pts[_edges[e].y]
		var dir := b - a
		var t := Transform3D(_basis_along(dir, thick), (a + b) * 0.5)
		if randf() < dropout:
			t.basis = Basis().scaled(Vector3.ZERO)
		multimesh.set_instance_transform(e, t)
		multimesh.set_instance_color(e, edge_col)

	var knot := KNOT_SIZE * lerpf(0.5, 1.0, coherence)
	for v in _verts.size():
		var spin := Basis(Vector3(1, 1, 0).normalized(), phase * 2.0 + v)
		multimesh.set_instance_transform(_edges.size() + v, Transform3D(spin.scaled(Vector3.ONE * knot), pts[v]))
		multimesh.set_instance_color(_edges.size() + v, Color(color.lightened(0.4), edge_col.a))

func _project() -> PackedVector3Array:
	var ca := cos(phase); var sa := sin(phase)
	var cb := cos(phase * 0.63); var sb := sin(phase * 0.63)
	var cc := cos(phase * 0.37); var sc := sin(phase * 0.37)
	var pts := PackedVector3Array()
	for v in _verts:
		var x := v.x * ca - v.w * sa
		var w := v.x * sa + v.w * ca
		var y := v.y * cb - v.z * sb
		var z := v.y * sb + v.z * cb
		var z2 := z * cc - w * sc
		var w2 := z * sc + w * cc
		pts.append(Vector3(x, y, z2) * (PROJ_DIST / (PROJ_DIST - w2)) * SIZE)
	return pts

func _basis_along(dir: Vector3, thick: float) -> Basis:
	var length := dir.length()
	var z := dir / length
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x)
	return Basis(x * thick, y * thick, z * length)
