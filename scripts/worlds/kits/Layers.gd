extends RoomKit
class_name Layers

## Slabs jutting from the walls at stacked heights, like strata or shelves
## seen from below: they cut the view upward. All above head height;
## seen only.

@export var count_min := 4
@export var count_max := 8
@export var y_min := 3.4
@export var y_max := 9.0
@export var depth_min := 1.0
@export var depth_max := 3.0
@export var thickness := 0.35
@export var kind := "accent"
@export var edge_kind := ""

func build(b: RoomBuilder) -> void:
	var segs := b.segments()
	for k in b.count(count_min, count_max):
		var seg: Dictionary = segs[b.rng.randi() % segs.size()]
		var d := b.rng.randf_range(depth_min, depth_max)
		var y := b.rng.randf_range(y_min, minf(y_max, b.height - 0.5))
		var at := b.at(seg, b.mid(seg), b.WALL_THICKNESS / 2.0 + d / 2.0, y)
		if b.shaft() and b.in_free(at):
			continue
		b.box(b.sized(seg, b.length(seg), thickness, d), at, kind)
		if edge_kind != "":
			b.box(b.sized(seg, b.length(seg), 0.04, 0.04), at + seg.inward * d / 2.0 - Vector3(0, thickness / 2.0, 0), edge_kind)
