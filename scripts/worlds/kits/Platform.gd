extends RoomKit
class_name Platform

## A raised block filling FREE, climbed by stairs along its outer (+z)
## side from the walkway: a lookout `height` above the floor (at most what
## the stairs climb, ~2.2 m). Optionally a second, taller block behind it
## that only the eye reaches.

@export var height := 2.0
@export var kind := "accent"
@export var top_kind := "floor"
@export var stair_kind := "accent"
## Line along the platform's open edges ("" = none).
@export var edge_kind := ""
## Unreachable block behind (0 = none): its height over the platform.
@export var tower := 0.0

func build(b: RoomBuilder) -> void:
	var f := b.FREE
	# The platform: FREE's middle, and the far landing beside it.
	var x_land := f.position.x + b.LANDING
	for r: Rect2 in [Rect2(x_land, f.position.y, f.end.x - x_land, f.size.y - 1.0), Rect2(f.position.x, f.position.y, b.LANDING, b.LANDING)]:
		var c := r.get_center()
		b.box(Vector3(r.size.x, height - 0.1, r.size.y), Vector3(c.x, (height - 0.1) / 2.0, c.y), kind, true)
		b.box(Vector3(r.size.x, 0.1, r.size.y), Vector3(c.x, height - 0.05, c.y), top_kind, true)
	b.free_stairs(0.0, height, stair_kind)
	var top := Rect2(x_land, f.position.y, f.end.x - x_land, f.size.y - 1.0)
	var c := top.get_center()
	if edge_kind != "":
		b.box(Vector3(0.05, 0.05, top.size.y), Vector3(top.end.x, height, c.y), edge_kind)
		b.box(Vector3(top.size.x, 0.05, 0.05), Vector3(c.x, height, top.position.y), edge_kind)
	if tower > 0.0:
		var t := Vector2(1.2, 1.2)
		b.box(Vector3(t.x, tower, t.y), Vector3(top.end.x - t.x / 2.0 - 0.3, height + tower / 2.0, top.position.y + t.y / 2.0), kind, true)
