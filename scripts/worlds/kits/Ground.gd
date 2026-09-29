extends RoomKit
class_name Ground

## The floor, and how far below it the room goes.
## FLAT: one slab at y = 0.
## PIT: FREE sunk `depth`, lined, with stairs back up to the walkway.
## UNDERCUT: the whole room sunk except the pads, the walkway plus left as
## bridges over it. The lower level runs on under the doors into the next
## room's, like the maze above. Without rails, stairs in FREE lead back up
## (so depth is what they can climb); with rails the drop is fenced off and
## may be as deep as you like, its floor just seen far below.

enum Mode { FLAT, PIT, UNDERCUT }

@export var mode := Mode.FLAT
@export var depth := 2.0
@export var kind := "floor"
## The sunk floor.
@export var lower_kind := "floor"
## Pit sides, walls below the floor, pad blocks.
@export var liner_kind := "wall"
@export var stair_kind := "accent"
@export var rails := false
@export var rail_kind := "edge"
@export var bridge := 0.25
## Line along the top of every drop edge ("" = none).
@export var lip_kind := ""

func build(b: RoomBuilder) -> void:
	match mode:
		Mode.FLAT:
			b.box(Vector3(b.ROOM_SIZE, 0.5, b.ROOM_SIZE), Vector3(0, -0.25, 0), kind, true)
		Mode.PIT:
			_pit(b)
		Mode.UNDERCUT:
			_undercut(b)

func _pit(b: RoomBuilder) -> void:
	var f := b.FREE
	var half := b.ROOM_SIZE / 2.0
	var thick := depth + 0.5
	# Floor around the pit, thick enough that its edges line the pit.
	_slab(b, Rect2(-half, -half, b.ROOM_SIZE, f.position.y + half), thick)
	_slab(b, Rect2(f.end.x, f.position.y, half - f.end.x, half - f.position.y), thick)
	# The walls' footprint along the pit's outer sides.
	b.box(Vector3(half - b.INNER, depth, f.size.y + half - f.end.y), Vector3(-(half + b.INNER) / 2.0, -depth / 2.0, (f.position.y + half) / 2.0), liner_kind, true)
	b.box(Vector3(f.size.x, depth, half - b.INNER), Vector3(f.get_center().x, -depth / 2.0, (half + b.INNER) / 2.0), liner_kind, true)
	b.box(Vector3(f.size.x, 0.5, f.size.y), Vector3(f.get_center().x, -depth - 0.25, f.get_center().y), lower_kind, true)
	_lips(b, [[Vector2(f.end.x, f.position.y), Vector2(f.end.x, f.end.y)], [Vector2(f.position.x, f.position.y), Vector2(f.end.x, f.position.y)]])
	b.free_stairs(0.0, -depth, stair_kind)

func _undercut(b: RoomBuilder) -> void:
	var half := b.ROOM_SIZE / 2.0
	var w := b.WALK_HALF * 2.0
	b.box(Vector3(b.ROOM_SIZE, 0.5, b.ROOM_SIZE), Vector3(0, -depth - 0.25, 0), lower_kind, true)
	b.box(Vector3(b.ROOM_SIZE, bridge, w), Vector3(0, -bridge / 2.0, 0), kind, true)
	b.box(Vector3(w, bridge, b.ROOM_SIZE), Vector3(0, -bridge / 2.0, 0), kind, true)
	for pad in b.PADS:
		var c := pad.get_center()
		b.box(Vector3(pad.size.x, depth - 0.3, pad.size.y), Vector3(c.x, -depth + (depth - 0.3) / 2.0, c.y), liner_kind, true)
		b.box(Vector3(pad.size.x, 0.3, pad.size.y), Vector3(c.x, -0.15, c.y), kind, true)
	# The walls go on down (not under the doors: the lower level runs on).
	for seg in b.segments():
		b.box(b.sized(seg, b.length(seg), depth, b.WALL_THICKNESS), b.at(seg, b.mid(seg), 0.0, -depth / 2.0), liner_kind, true)
	var f := b.FREE
	var s := b.STRIP
	# Every edge where the bridges or pads meet the drop.
	var edges := [
		[Vector2(f.end.x, f.position.y), Vector2(f.end.x, half)],
		[Vector2(-half, f.position.y), Vector2(f.end.x, f.position.y)],
		[Vector2(s.position.x, s.position.y), Vector2(s.position.x, s.end.y)],
		[Vector2(s.position.x, s.end.y), Vector2(half, s.end.y)],
		[Vector2(s.position.x, s.position.y), Vector2(half, s.position.y)],
	]
	_lips(b, edges)
	if rails:
		for e: Array in edges:
			_rail(b, e[0], e[1])
	else:
		b.free_stairs(0.0, -depth, stair_kind)
		# Then on under the crossing: headroom under the bridges.
		var r := b.routes[-1]
		r.append(Vector3(-0.3, -depth, 0.3))
		b.routes[-1] = r

## Slab over rect (x, z) from y = 0 down `thick`.
func _slab(b: RoomBuilder, r: Rect2, thick: float) -> void:
	var c := r.get_center()
	b.box(Vector3(r.size.x, thick, r.size.y), Vector3(c.x, -thick / 2.0, c.y), kind, true)

func _lips(b: RoomBuilder, edges: Array) -> void:
	if lip_kind == "":
		return
	for e: Array in edges:
		var a: Vector2 = e[0]
		var z: Vector2 = e[1]
		var c := (a + z) / 2.0
		var along_x := absf(z.x - a.x) > absf(z.y - a.y)
		var l := (z - a).length()
		b.box(Vector3(l, 0.03, 0.06) if along_x else Vector3(0.06, 0.03, l), Vector3(c.x, 0.015, c.y), lip_kind)

## Posts and a top bar, 1.1 m: the player (who never jumps) can't pass.
func _rail(b: RoomBuilder, a: Vector2, z: Vector2) -> void:
	var c := (a + z) / 2.0
	var along_x := absf(z.x - a.x) > absf(z.y - a.y)
	var l := (z - a).length()
	var h := 1.1
	b.box(Vector3(l, 0.05, 0.05) if along_x else Vector3(0.05, 0.05, l), Vector3(c.x, h, c.y), rail_kind)
	b.box(Vector3(l, h, 0.1) if along_x else Vector3(0.1, h, l), Vector3(c.x, h / 2.0, c.y), "", true)
	var n := maxi(ceili(l / 1.2), 1)
	for i in n + 1:
		var p := a.lerp(z, float(i) / n)
		b.box(Vector3(0.05, h, 0.05), Vector3(p.x, h / 2.0, p.y), rail_kind)
