extends RoomKit
class_name WallRibs

## Vertical ribs standing out of the walls at a regular spacing, clear of
## door jambs and the hideout corner. Solid.

@export var spacing := 1.0
@export var width := 0.22
@export var depth_min := 0.28
@export var depth_max := 0.42
@export var kind := "accent"

func build(b: RoomBuilder) -> void:
	var depth := b.rng.randf_range(depth_min, depth_max)
	var n := int(4.0 / spacing)
	var segs := b.segments()
	for i in segs.size():
		var seg: Dictionary = segs[i]
		var h := b.wall_height(i)
		for k in range(-n, n + 1):
			var a := k * spacing
			var at := b.at(seg, a, b.WALL_THICKNESS / 2.0 + depth / 2.0, h / 2.0)
			if a > seg.from + 0.3 and a < seg.to - 0.3 and not b.reserved(at):
				b.box(b.sized(seg, width, h, depth), at, kind, true)
