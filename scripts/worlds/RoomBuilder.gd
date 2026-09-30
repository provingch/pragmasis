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
## floor at y = 0 and clear of anything solid. Everything off them (FREE,
## the -x +z quadrant, and STRIP, beside the hideout) may rise or sink,
## reached by stairs: the player never jumps, so every height change is a
## ramp under 45 degrees (stair), and nothing reachable is ever a dead drop.
##
## The room is one cube of a 3D grid (Room.CELL_H tall). A cube joined to
## the one above (`up`) holds the spiral stairs in FREE (spiral); the one
## above sees them as a railed shaft in its floor (`down`, hole_rails).
## Either way FREE is the shaft's and kits leave it alone (shaft()). Faces
## toward a void cell may be open (`open`: walls without a door, the
## ceiling), railed; a void cell itself is only bridges (void_cell).

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
## Stairs: steepest rise per metre of run (39 degrees; CharacterBody3D
## climbs up to 45) and the height of each visual step.
const MAX_SLOPE := 0.8
const STEP_RISE := 0.22
## Railings: height (the player never jumps: this stops anyone).
const RAIL := 1.1
## The spiral: ring width, laps per cube, and the corner by the walkway
## crossing where it's entered at every floor.
const SPIRAL_RING := 1.0
const SPIRAL_LAPS := 3
const SPIRAL_ENTRY := Rect2(-WALK_HALF - SPIRAL_RING, WALK_HALF, SPIRAL_RING, SPIRAL_RING)
## What the entry is open for, at the foot (you walk in under this).
const SPIRAL_DOOR := 2.3

var world: WorldDef
var w: int
var exits: Array[bool]
var variant: int
## Joined to the cube above / below (spiral stairs in FREE).
var up := false
var down := false
## [north, south, east, west, ceiling]: faces open to the void.
var open: Array[bool] = [false, false, false, false, false]
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
## Width of every flight and landing (the player is 0.8 m across).
const FLIGHT := 1.1
func free_stairs(y_walk: float, y_far: float, kind: String) -> void:
	var f := FREE
	var x_land := f.position.x + FLIGHT # east edge of both landings
	var z1 := f.end.y - FLIGHT / 2.0 # first flight's middle line
	var z_turn := f.end.y - FLIGHT # where the second flight leaves the corner
	var z_end := f.position.y + FLIGHT
	var x2 := f.position.x + FLIGHT / 2.0
	var run1 := f.end.x - x_land
	var run2 := z_turn - z_end
	var y_mid := y_walk + (y_far - y_walk) * run1 / (run1 + run2)
	var base := minf(y_walk, y_far)
	stair(Vector3(f.end.x, y_walk, z1), Vector3(x_land, y_mid, z1), FLIGHT, kind, base)
	var h := y_mid - base
	box(Vector3(FLIGHT, h, FLIGHT), Vector3(x2, base + h / 2.0, z1), kind, true)
	stair(Vector3(x2, y_mid, z_turn), Vector3(x2, y_far, z_end), FLIGHT, kind, base)
	route([Vector3(-0.8, 0, z1), Vector3(f.end.x - 0.3, NAN, z1), Vector3(x2, y_mid, z1), Vector3(x2, NAN, (z_turn + z_end) / 2.0), Vector3(x2, y_far, z_end - 0.5), Vector3(f.get_center().x, y_far, f.position.y + 0.7)])

## FREE belongs to a spiral shaft here: kits keep out of it.
func shaft() -> bool:
	return up or down

## A bar from p0 to p1 (any direction), `t` thick.
func bar(p0: Vector3, p1: Vector3, t: float, kind: String, collide := false) -> void:
	var x := (p1 - p0).normalized()
	var helper := Vector3.UP if absf(x.y) < 0.9 else Vector3.RIGHT
	var z := x.cross(helper).normalized()
	box(Vector3((p1 - p0).length(), t, t), (p0 + p1) / 2.0, kind, collide, Basis(x, z.cross(x), z))

## Railing along the floor from a to b (x, z) at height y: posts, a top
## rail, and a wall of collision RAIL tall.
func rail(a: Vector2, b: Vector2, y := 0.0, kind := "edge") -> void:
	var l := (b - a).length()
	if l < 0.05:
		return
	var c := (a + b) / 2.0
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	box(Vector3(l, RAIL, 0.1) if along_x else Vector3(0.1, RAIL, l), Vector3(c.x, y + RAIL / 2.0, c.y), "", true)
	bar(Vector3(a.x, y + RAIL, a.y), Vector3(b.x, y + RAIL, b.y), 0.05, kind)
	var n := maxi(ceili(l / 1.2), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		box(Vector3(0.05, RAIL, 0.05), Vector3(p.x, y + RAIL / 2.0, p.y), kind)

## The room's floor area (x, z) minus `holes`, as few rectangles as a
## grid over their edges allows.
func cover(area: Rect2, holes: Array) -> Array[Rect2]:
	var xs := [area.position.x, area.end.x]
	var zs := [area.position.y, area.end.y]
	for h in holes:
		xs.append_array([clampf(h.position.x, area.position.x, area.end.x), clampf(h.end.x, area.position.x, area.end.x)])
		zs.append_array([clampf(h.position.y, area.position.y, area.end.y), clampf(h.end.y, area.position.y, area.end.y)])
	xs.sort()
	zs.sort()
	var out: Array[Rect2] = []
	for j in zs.size() - 1:
		var run := -1
		for i in xs.size():
			var inside := false
			if i < xs.size() - 1 and xs[i + 1] - xs[i] > 0.001 and zs[j + 1] - zs[j] > 0.001:
				var mid := Vector2((xs[i] + xs[i + 1]) / 2.0, (zs[j] + zs[j + 1]) / 2.0)
				inside = not holes.any(func(h: Rect2) -> bool: return h.has_point(mid))
			if inside and run < 0:
				run = i
			elif not inside and run >= 0:
				out.append(Rect2(xs[run], zs[j], xs[i] - xs[run], zs[j + 1] - zs[j]))
				run = -1
	return out

## What of FREE the shaft takes from this cube's floor: all of it but the
## entry corner, where the stairs from below come out.
func shaft_hole() -> Array[Rect2]:
	var f := FREE
	var e := SPIRAL_ENTRY
	return [Rect2(f.position, Vector2(e.position.x - f.position.x, f.size.y)), Rect2(e.position.x, e.end.y, e.size.x, f.end.y - e.end.y)]

## Spiral stairs filling FREE from this cube's floor to the next one's:
## a ring SPIRAL_RING wide around a solid core, SPIRAL_LAPS laps, a flat
## landing at every corner, and the entry corner (by the walkway
## crossing) at every floor. Railed on the outside all the way up, open
## only at the foot of the entry; the cube above opens its floor for it.
func spiral() -> void:
	var f := FREE
	var r := SPIRAL_RING
	var h := Room.CELL_H
	var corners: Array[Rect2] = [SPIRAL_ENTRY, Rect2(f.position.x, f.position.y, r, r), Rect2(f.position.x, f.end.y - r, r, r), Rect2(f.end.x - r, f.end.y - r, r, r)]
	var flights := 4 * SPIRAL_LAPS
	var rise := h / flights
	for k in flights + 1:
		var y := k * rise
		var c := corners[k % 4].get_center()
		box(Vector3(r, 0.25, r), Vector3(c.x, y - 0.125, c.y), "accent", true)
		if k == flights:
			break
		# To the next corner, along the side between them.
		var n := corners[(k + 1) % 4].get_center()
		var dir := (n - c).normalized()
		var a := c + dir * r / 2.0
		var b := n - dir * r / 2.0
		stair(Vector3(a.x, y, a.y), Vector3(b.x, y + rise, b.y), r, "accent", y - 0.35)
		# Outer rail: the side of the ring away from the core.
		var out := Vector2(dir.y, -dir.x)
		if out.dot(c - f.get_center()) < 0.0:
			out = -out
		var o0 := c + out * r / 2.0 - dir * r / 2.0
		var o1 := n + out * r / 2.0 + dir * r / 2.0
		bar(Vector3(o0.x, y + RAIL, o0.y), Vector3(o1.x, y + rise + RAIL, o1.y), 0.05, "edge")
	# The core, a little narrower than the well: a slot too thin to fall
	# into, so brushing the core never pins you to a flight.
	var core := Rect2(f.position + Vector2(r, r), f.size - Vector2(2 * r, 2 * r)).grow(-0.15)
	box(Vector3(core.size.x, h, core.size.y), Vector3(core.get_center().x, h / 2.0, core.get_center().y), "wall", true)
	# Invisible walls around FREE, bottom to top, but for the way in.
	var e := SPIRAL_ENTRY
	for side: Array in [
			[Vector2(f.position.x, f.position.y), Vector2(e.position.x, f.position.y)], # north, up to the entry
			[Vector2(f.end.x, e.end.y), Vector2(f.end.x, f.end.y)], # east, past the entry
			[Vector2(f.position.x, f.position.y), Vector2(f.position.x, f.end.y)], # west
			[Vector2(f.position.x, f.end.y), Vector2(f.end.x, f.end.y)]]: # south
		_wall(side[0], side[1], 0.0, h)
	_wall(Vector2(e.position.x, f.position.y), Vector2(f.end.x, f.position.y), SPIRAL_DOOR, h)
	_wall(Vector2(f.end.x, f.position.y), Vector2(f.end.x, e.end.y), SPIRAL_DOOR, h)
	# Walked up one whole cube: out on the walkway above.
	var pts: Array[Vector3] = [Vector3(-0.8, 0, 0.8), Vector3(e.get_center().x, 0, e.get_center().y)]
	for k in range(1, flights + 1):
		var c := corners[k % 4].get_center()
		pts.append(Vector3(c.x, k * rise, c.y))
	pts.append(Vector3(-0.8, h, 0.8))
	route(pts)

func _wall(a: Vector2, b: Vector2, y0: float, y1: float) -> void:
	var c := (a + b) / 2.0
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var l := (b - a).length()
	box(Vector3(l, y1 - y0, 0.1) if along_x else Vector3(0.1, y1 - y0, l), Vector3(c.x, (y0 + y1) / 2.0, c.y), "", true)

## The cube above a spiral: rails around its shaft hole (not when this
## cube's own spiral starts there: its walls already fence it).
func hole_rails() -> void:
	if up:
		return
	var f := FREE
	var e := SPIRAL_ENTRY
	rail(Vector2(f.position.x, f.position.y), Vector2(e.position.x, f.position.y))
	rail(Vector2(e.position.x, f.position.y), Vector2(e.position.x, e.end.y))
	rail(Vector2(f.end.x, e.end.y), Vector2(f.end.x, f.end.y))
	# (The entry's south edge stays open: the last flight comes up there.)

## Rails along the walls left open to the void.
func open_rails() -> void:
	var i := INNER - 0.05
	var sides := [[Vector2(-i, -i), Vector2(i, -i)], [Vector2(-i, i), Vector2(i, i)], [Vector2(i, -i), Vector2(i, i)], [Vector2(-i, -i), Vector2(-i, i)]]
	for dir in 4:
		if open[dir]:
			rail(sides[dir][0], sides[dir][1])

## A void cell: no walls, floor or ceiling; only what walking needs, as
## bridges in the air: the crossing, an arm to every door, the pad of its
## portal if it has one, and the spiral's entry corner. Railed wherever
## an edge drops into the void (not where it meets a door).
func void_cell(link_corner: int) -> void:
	var half := ROOM_SIZE / 2.0
	var wk := WALK_HALF
	var walk: Array[Rect2] = [Rect2(-wk, -wk - 1.0, 2 * wk + 1.0, 2 * wk + 2.0), Rect2(-wk - 1.0, -wk - 1.0, 1.0, 2 * wk + 1.0)]
	var arms: Array[Rect2] = [Rect2(-wk, -half, 2 * wk, half), Rect2(-wk, 0, 2 * wk, half), Rect2(0, -wk, half, 2 * wk), Rect2(-half, -wk, half, 2 * wk)]
	for dir in 4:
		if exits[dir]:
			walk.append(arms[dir])
	if link_corner != 0:
		walk.append(PADS[0] if link_corner > 0 else PADS[1])
	for r in walk:
		var c := r.get_center()
		box(Vector3(r.size.x, 0.3, r.size.y), Vector3(c.x, -0.15, c.y), "floor", true)
	# Rails: every grid edge between walkable and not, but at the doors.
	var xs := [-half, half]
	var zs := [-half, half]
	for r in walk:
		xs.append_array([r.position.x, r.end.x])
		zs.append_array([r.position.y, r.end.y])
	xs.sort()
	zs.sort()
	var on := func(p: Vector2) -> bool:
		return walk.any(func(r: Rect2) -> bool: return r.has_point(p)) and absf(p.x) < half and absf(p.y) < half
	for j in zs.size() - 1:
		for i in xs.size() - 1:
			var lo := Vector2(xs[i], zs[j])
			var hi := Vector2(xs[i + 1], zs[j + 1])
			if hi.x - lo.x < 0.001 or hi.y - lo.y < 0.001 or not on.call((lo + hi) / 2.0):
				continue
			var m := (lo + hi) / 2.0
			var eps := 0.01
			for side: Array in [[Vector2(m.x, lo.y - eps), lo, Vector2(hi.x, lo.y), 0], [Vector2(m.x, hi.y + eps), Vector2(lo.x, hi.y), hi, 1], [Vector2(hi.x + eps, m.y), Vector2(hi.x, lo.y), hi, 2], [Vector2(lo.x - eps, m.y), lo, Vector2(lo.x, hi.y), 3]]:
				var beyond: Vector2 = side[0]
				if on.call(beyond):
					continue
				# The room's edge where a door is: the next cell goes on.
				var at_door: bool = (side[3] == 0 and lo.y <= -half + eps and exits[0]) or (side[3] == 1 and hi.y >= half - eps and exits[1]) \
					or (side[3] == 2 and hi.x >= half - eps and exits[2]) or (side[3] == 3 and lo.x <= -half + eps and exits[3])
				if at_door:
					continue
				# The spiral's entry corner comes out of the shaft: no rail there.
				if shaft() and SPIRAL_ENTRY.grow(0.02).has_point(beyond):
					continue
				var inset: Vector2 = (m - beyond).normalized() * 0.05
				rail(side[1] + inset, side[2] + inset)

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
			if open[dir]:
				continue # open to the void: no wall there
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

## In (or within `margin` of) FREE, where stairs hug the walls: no solid
## wall props there.
func in_free(p: Vector3, margin := 0.5) -> bool:
	return FREE.grow(margin).has_point(Vector2(p.x, p.z))

## True if a solid footprint (centre, size; y ignored) stays inside the
## room and out of the walkway plus, the portal corners, the hideout corner
## and a spiral shaft: somewhere it can never block a way through.
func clear(center: Vector3, size: Vector3) -> bool:
	var r := Rect2(center.x - size.x / 2.0, center.z - size.z / 2.0, size.x, size.z)
	if shaft() and r.intersects(FREE):
		return false
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
