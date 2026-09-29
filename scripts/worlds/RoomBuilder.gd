extends RefCounted
class_name RoomBuilder

## What a world's kits build a room through. Collects boxes (grouped by
## material kind), fixture boxes (the room's flickering light material) and
## collision boxes, then bakes them into meshes shared by every room with
## the same (world, exits, variant). Also the vocabulary kits place things
## with: wall segments between doors, points and sizes along them, the
## corners nothing solid may occupy (clear), and floor zones that change
## the player's speed.
##
## Levels: the walkway plus, both portal pads and the hideout pad are always
## floor at y = 0 and clear of anything solid (portals drop you at the same
## x/z at y = 1, in any world). Everything off them (FREE, the -x +z
## quadrant, and STRIP, beside the hideout) may rise or sink, reached by
## stairs: the player never jumps, so every height change is a ramp under
## 45 degrees (stair), and nothing reachable is ever a dead drop.

const ROOM_SIZE := Room.ROOM_SIZE
const WALL_THICKNESS := Room.WALL_THICKNESS
const DOOR_WIDTH := Room.DOOR_WIDTH
## Inner face of the walls, from the room's centre.
const INNER := ROOM_SIZE / 2.0 - WALL_THICKNESS / 2.0
## Half the walkway plus (a door's width, a hair wider).
const WALK_HALF := DOOR_WIDTH / 2.0 + 0.1
## Around each portal corner: its sphere, the player, and the way in from
## the walkway.
const PORTAL_CLEAR := 2.0
const PORTALS: Array[Vector2] = [Vector2(3.5, 3.5), Vector2(-3.5, -3.5)]
## The hideout, its door and the way to it (x, z).
const HIDEOUT_CLEAR := Rect2(1.5, -5.0, 3.5, 2.4)
## Floor pads kept at y = 0 around the portal corners and the hideout.
const PADS: Array[Rect2] = [Rect2(WALK_HALF, WALK_HALF, INNER - WALK_HALF, INNER - WALK_HALF), Rect2(-INNER, -INNER, INNER - WALK_HALF, INNER - WALK_HALF), Rect2(WALK_HALF, -INNER, INNER - WALK_HALF, INNER - 2.6)]
## What may rise or sink: the free quadrant and the strip by the hideout.
const FREE := Rect2(-INNER, WALK_HALF, INNER - WALK_HALF, INNER - WALK_HALF)
const STRIP := Rect2(WALK_HALF, -2.6, INNER - WALK_HALF, 2.6 - WALK_HALF)
## Stairs: steepest rise per metre of run (35 degrees; CharacterBody3D
## climbs up to 45) and the height of each visual step.
const MAX_SLOPE := 0.7
const STEP_RISE := 0.22

var world: WorldDef
var w: int
var exits: Array[bool]
var variant: int
var rng := RandomNumberGenerator.new()
## Ceiling height.
var height: float
## Height the wall kit gave each segment (same order as segments()).
var wall_heights: Array[float] = []

var pieces := {} # kind -> [[size, pos, basis], ...]
var fixture: Array = []
## [size, pos, basis, see_through]; see-through ones block the player but
## not the entity's line of sight (bars).
var colliders: Array = []
## Walks the validation harness takes (room coordinates, from a walkway
## point out and back): proof that every level is reachable.
var routes: Array[PackedVector3Array] = []
## [Rect2 (x, z), speed multiplier] per floor zone.
var zones: Array = []
var _segments: Array[Dictionary] = []

func _init(world_id: int, room_exits: Array[bool], v: int) -> void:
	w = world_id
	world = Worlds.def(world_id)
	exits = room_exits
	variant = v
	height = world.height
	rng.seed = hash([world_id, v])

## A box drawn with `kind` ("" = collision only) and, if solid, collided.
## `basis` turns it about its centre.
func box(size: Vector3, pos: Vector3, kind: String, collide := false, basis := Basis.IDENTITY) -> void:
	if kind != "":
		if not pieces.has(kind):
			pieces[kind] = []
		pieces[kind].append([size, pos, basis])
	if collide:
		colliders.append([size, pos, basis, false])

## Blocks the player, not the entity's sight (bars, grilles).
func see_through(size: Vector3, pos: Vector3) -> void:
	colliders.append([size, pos, Basis.IDENTITY, true])

## Stairs along x or z from `a` to `b` (their heights differ): solid steps
## down to `base_y`, `width` across, and one ramp to walk on (collision
## follows the ramp, the steps are only seen). Too steep for the run
## between them: the ramp is still built, and flagged in the log.
func stair(a: Vector3, b: Vector3, width: float, kind: String, base_y := 0.0) -> void:
	var low := a if a.y < b.y else b
	var high := b if a.y < b.y else a
	var run := Vector2(high.x - low.x, high.z - low.z)
	var rise := high.y - low.y
	if rise > run.length() * MAX_SLOPE + 0.01:
		push_warning("stair too steep in %s: %.2f over %.2f" % [world.id, rise, run.length()])
	var along_x := absf(run.x) > absf(run.y)
	var n := maxi(ceili(rise / STEP_RISE), 1)
	var dir := Vector3(run.x, 0, run.y).normalized()
	var tread := run.length() / n
	for i in n:
		var top := low.y + rise * (i + 1) / n
		var c := low + dir * tread * (i + 0.5)
		var h := top - base_y
		box(Vector3(tread if along_x else width, h, width if along_x else tread), Vector3(c.x, base_y + h / 2.0, c.z), kind)
	# The ramp: a thin slab whose top face runs from low to high.
	var t := 0.2
	var length := Vector3(high.x - low.x, rise, high.z - low.z).length()
	var basis: Basis
	var up: Vector3
	if along_x:
		var phi := atan(rise / run.x)
		basis = Basis(Vector3.BACK, phi)
		up = Vector3(-sin(phi), cos(phi), 0)
	else:
		var psi := -atan(rise / run.y)
		basis = Basis(Vector3.RIGHT, psi)
		up = Vector3(0, cos(psi), sin(psi))
	var size := Vector3(length, t, width) if along_x else Vector3(width, t, length)
	box(size, (low + high) / 2.0 - up * t / 2.0, "", true, basis)

## FREE's stairs, in an L hugging its walls: from the walkway's edge at
## y_walk west along the south wall to a landing in the corner, then north
## along the west wall to a landing at y_far, beside FREE's middle
## (a pit floor or a platform, which the caller builds). Every flight ends
## on something flat: stairs can't be walked onto from the side. Up to
## ~2.4 m either way. Adds its validation route.
const LANDING := 0.9
func free_stairs(y_walk: float, y_far: float, kind: String) -> void:
	var f := FREE
	var x_land := f.position.x + LANDING # east edge of both landings
	var z1 := f.end.y - 1.0 / 2.0 # first flight's middle line (1 m wide)
	var z_turn := f.end.y - 1.0 # where the second flight leaves the corner
	var z_end := f.position.y + LANDING
	var x2 := f.position.x + LANDING / 2.0
	var run1 := f.end.x - x_land
	var run2 := z_turn - z_end
	var y_mid := y_walk + (y_far - y_walk) * run1 / (run1 + run2)
	var base := minf(y_walk, y_far)
	stair(Vector3(f.end.x, y_walk, z1), Vector3(x_land, y_mid, z1), 1.0, kind, base)
	var h := y_mid - base
	box(Vector3(LANDING, h, 1.0), Vector3(x2, base + h / 2.0, z1), kind, true)
	stair(Vector3(x2, y_mid, z_turn), Vector3(x2, y_far, z_end), LANDING, kind, base)
	route([Vector3(-0.8, 0, z1), Vector3(f.end.x - 0.3, NAN, z1), Vector3(x2, y_mid, z1), Vector3(x2, NAN, (z_turn + z_end) / 2.0), Vector3(x2, y_far, z_end - 0.4), Vector3(f.get_center().x + 0.6, y_far, f.position.y + 0.8)])

## A validation walk (room coordinates; y = NAN: on a ramp, not checked).
func route(points: Array[Vector3]) -> void:
	routes.append(PackedVector3Array(points))

## Light fixture box: drawn with the room's own flickering material.
func fix(size: Vector3, pos: Vector3) -> void:
	fixture.append([size, pos])

## A floor zone: standing inside it multiplies the player's speed.
func zone(rect: Rect2, speed: float) -> void:
	zones.append([rect, speed])

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

## True if a solid footprint (centre, size; y ignored) stays inside the
## room and out of the walkway plus, the portal corners and the hideout
## corner: somewhere it can never block a way through.
func clear(center: Vector3, size: Vector3) -> bool:
	var r := Rect2(center.x - size.x / 2.0, center.z - size.z / 2.0, size.x, size.z)
	if r.position.x < -INNER or r.position.y < -INNER or r.end.x > INNER or r.end.y > INNER:
		return false
	if (r.position.x < WALK_HALF and r.end.x > -WALK_HALF) or (r.position.y < WALK_HALF and r.end.y > -WALK_HALF):
		return false
	for p in PORTALS:
		if p.distance_to(p.clamp(r.position, r.end)) < PORTAL_CLEAR:
			return false
	return not r.intersects(HIDEOUT_CLEAR)

func bake() -> Dictionary:
	return {"mesh": commit(pieces, w, true), "fixture": commit({"": fixture}, w, false), "colliders": colliders, "zones": zones, "routes": routes}

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
			var basis: Basis = p[2] if p.size() > 2 else Basis.IDENTITY
			var base := verts.size()
			for v: Vector3 in cube[Mesh.ARRAY_VERTEX]:
				verts.append(basis * (v * size) + pos)
				uvs.append(Vector2(index, 0))
			for nrm: Vector3 in cube[Mesh.ARRAY_NORMAL]:
				normals.append(basis * nrm)
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
