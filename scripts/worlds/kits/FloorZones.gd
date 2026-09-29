extends RoomKit
class_name FloorZones

## Patches on the floor that change the player's speed while they stand
## in them (water, roots): drawn over the floor, walkable, never solid, so
## they may cross the walkway. Fixed rects and/or random patches (random
## ones stay off the hideout corner), optionally rimmed, optionally
## crossed by thin raised strands (roots) so they read at a glance.

## Fixed patches (x, z, in room coordinates).
@export var rects: Array[Rect2] = []
@export var count_min := 0
@export var count_max := 0
@export var size_min := 1.5
@export var size_max := 3.0
## Height of the patch's surface.
@export var top := 0.03
@export var kind := "accent"
## Border around each patch ("" = none).
@export var rim_kind := ""
@export var rim := 0.15
@export var strands := 0
@export var strand_kind := "accent"
## Player speed multiplier inside (1 = just a look).
@export var speed := 0.6

func build(b: RoomBuilder) -> void:
	var patches: Array[Rect2] = rects.duplicate()
	for k in b.count(count_min, count_max):
		var s := Vector2(b.rng.randf_range(size_min, size_max), b.rng.randf_range(size_min, size_max))
		var c := Vector2(b.rng.randf_range(-b.INNER + s.x / 2.0, b.INNER - s.x / 2.0), b.rng.randf_range(-b.INNER + s.y / 2.0, b.INNER - s.y / 2.0))
		var r := Rect2(c - s / 2.0, s)
		if not r.intersects(b.HIDEOUT_CLEAR):
			patches.append(r)
	for r in patches:
		var c := r.get_center()
		b.box(Vector3(r.size.x, top, r.size.y), Vector3(c.x, top / 2.0, c.y), kind)
		if speed != 1.0:
			b.zone(r, speed)
		if rim_kind != "":
			var h := top + 0.04
			for sz: float in [-1.0, 1.0]:
				b.box(Vector3(r.size.x + 2.0 * rim, h, rim), Vector3(c.x, h / 2.0, c.y + sz * (r.size.y + rim) / 2.0), rim_kind)
				b.box(Vector3(rim, h, r.size.y), Vector3(c.x + sz * (r.size.x + rim) / 2.0, h / 2.0, c.y), rim_kind)
		for k in strands:
			var along_x := b.rng.randf() < 0.5
			var length := b.rng.randf_range(0.5, 1.0) * (r.size.x if along_x else r.size.y)
			var th := b.rng.randf_range(0.06, 0.14)
			var p := Vector3(b.rng.randf_range(r.position.x, r.end.x), top + th / 2.0, b.rng.randf_range(r.position.y, r.end.y))
			if along_x:
				p.x = clampf(p.x, r.position.x + length / 2.0, r.end.x - length / 2.0)
			else:
				p.z = clampf(p.z, r.position.y + length / 2.0, r.end.y - length / 2.0)
			b.box(Vector3(length, th, th) if along_x else Vector3(th, th, length), p, strand_kind)
