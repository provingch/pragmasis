extends RefCounted
class_name RoomBuilder

## What a world's kits build a room through. Collects boxes (grouped by
## material kind), fixture boxes (the room's flickering light material) and
## collision boxes, then bakes them into meshes shared by every room with
## the same (world, exits, variant). Also the vocabulary kits place things
## with: wall segments between doors, points and sizes along them, and the
## corners nothing solid may occupy.

const ROOM_SIZE := Room.ROOM_SIZE
const WALL_THICKNESS := Room.WALL_THICKNESS
const DOOR_WIDTH := Room.DOOR_WIDTH
## Inner face of the walls, from the room's centre.
const INNER := ROOM_SIZE / 2.0 - WALL_THICKNESS / 2.0

var world: WorldDef
var w: int
var exits: Array[bool]
var variant: int
var rng := RandomNumberGenerator.new()
## Ceiling height.
var height: float
## Height the wall kit gave each segment (same order as segments()).
var wall_heights: Array[float] = []

var pieces := {} # kind -> [[size, pos], ...]
var fixture: Array = []
var colliders: Array = []
var _segments: Array[Dictionary] = []

func _init(world_id: int, room_exits: Array[bool], v: int) -> void:
	w = world_id
	world = Worlds.def(world_id)
	exits = room_exits
	variant = v
	height = world.height
	rng.seed = hash([world_id, v])

## A box drawn with `kind` ("" = collision only) and, if solid, collided.
func box(size: Vector3, pos: Vector3, kind: String, collide := false) -> void:
	if kind != "":
		if not pieces.has(kind):
			pieces[kind] = []
		pieces[kind].append([size, pos])
	if collide:
		colliders.append([size, pos])

## Light fixture box: drawn with the room's own flickering material.
func fix(size: Vector3, pos: Vector3) -> void:
	fixture.append([size, pos])

## Random count from a kit's range, scaled by the world's prop density.
func count(lo: int, hi: int) -> int:
	return roundi(rng.randi_range(lo, hi) * world.prop_density)

## Wall pieces between doors: each {center (y=0), from, to (along the wall),
## side (east/west wall: along z), inward (unit, into the room)}.
func segments() -> Array[Dictionary]:
	if _segments.is_empty():
		var half := ROOM_SIZE / 2.0
		for dir in 4:
			var side := dir == Room.Exit.EAST or dir == Room.Exit.WEST
			var sgn := -1.0 if dir == Room.Exit.NORTH or dir == Room.Exit.WEST else 1.0
			var ranges := [[-half, half]] if not exits[dir] else [[-half, -DOOR_WIDTH / 2.0], [DOOR_WIDTH / 2.0, half]]
			for r: Array in ranges:
				var mid: float = (r[0] + r[1]) / 2.0
				_segments.append({
					"center": Vector3(sgn * half, 0, mid) if side else Vector3(mid, 0, sgn * half),
					"from": r[0], "to": r[1], "side": side,
					"inward": Vector3(-sgn, 0, 0) if side else Vector3(0, 0, -sgn),
				})
	return _segments

## Point on a wall segment: `along` the wall, `inset` metres in from the
## wall's centre plane, at height y.
func at(seg: Dictionary, along: float, inset: float, y: float) -> Vector3:
	var p: Vector3 = seg.center + seg.inward * inset
	if seg.side:
		p.z = along
	else:
		p.x = along
	p.y = y
	return p

## Box size oriented to a wall: `length` along it, `depth` across it.
func sized(seg: Dictionary, length: float, h: float, depth: float) -> Vector3:
	return Vector3(depth, h, length) if seg.side else Vector3(length, h, depth)

func mid(seg: Dictionary) -> float:
	return (seg.from + seg.to) / 2.0

func length(seg: Dictionary) -> float:
	return seg.to - seg.from

## Height of segment i's wall (the ceiling if no wall kit set it).
func wall_height(i: int) -> float:
	return wall_heights[i] if i < wall_heights.size() else height

## Strip on a wall's inner face (baseboard, edge line...).
func strip(seg: Dictionary, y: float, h: float, depth: float, kind: String) -> void:
	box(sized(seg, length(seg), h, depth), at(seg, mid(seg), WALL_THICKNESS / 2.0 + depth / 2.0, y), kind)

## The hideout corner, kept clear in every room.
func reserved(p: Vector3) -> bool:
	return p.x > 3.0 and p.z < -3.0

func bake() -> Dictionary:
	return {"mesh": commit(pieces, w, true), "fixture": commit({"": fixture}, w, false), "colliders": colliders}

## One surface per material kind; UV.x = the box's index (the glitch shader
## moves each box as a whole). Normals only otherwise: materials use world
## triplanar mapping.
static func commit(by_kind: Dictionary, world_id: int, with_materials: bool) -> ArrayMesh:
	var cube := Room.unit_cube()
	var mesh := ArrayMesh.new()
	var index := 0
	for kind: String in by_kind:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for p: Array in by_kind[kind]:
			var size: Vector3 = p[0]
			var pos: Vector3 = p[1]
			var base := verts.size()
			for v: Vector3 in cube[Mesh.ARRAY_VERTEX]:
				verts.append(v * size + pos)
				uvs.append(Vector2(index, 0))
			normals.append_array(cube[Mesh.ARRAY_NORMAL])
			for i: int in cube[Mesh.ARRAY_INDEX]:
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
			mesh.surface_set_material(mesh.get_surface_count() - 1, Room.layer_material(world_id, kind))
	return mesh
