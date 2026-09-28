extends RoomKit
class_name WallPanels

## Thin panels stuck to random walls at random heights (with the glitch
## kind, they tremble). Visual only.

@export var count_min := 2
@export var count_max := 4
@export var length_min := 1.0
@export var length_max := 2.5
@export var height_min := 1.0
@export var height_max := 3.0
@export var kind := "glitch"

func build(b: RoomBuilder) -> void:
	var segs := b.segments()
	for k in b.count(count_min, count_max):
		var seg: Dictionary = segs[b.rng.randi() % segs.size()]
		var length := minf(b.rng.randf_range(length_min, length_max), b.length(seg) - 0.4)
		var along := b.rng.randf_range(seg.from + 0.2 + length / 2.0, seg.to - 0.2 - length / 2.0)
		var ph := b.rng.randf_range(height_min, height_max)
		var at := b.at(seg, along, b.WALL_THICKNESS / 2.0 + 0.06, b.rng.randf_range(1.0, b.height - 2.0 - ph / 2.0) + ph / 2.0)
		if not b.reserved(at):
			b.box(b.sized(seg, length, ph, 0.05), at, kind)
