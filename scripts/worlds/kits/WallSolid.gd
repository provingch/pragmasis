extends RoomKit
class_name WallSolid

## The walls between doors. By default up to the ceiling; with a height
## range each segment stops at a random height (optionally outlined on top).

@export var kind := "wall"
## 0 = up to the ceiling.
@export var height_min := 0.0
@export var height_max := 0.0
@export var top_edge_kind := ""

func build(b: RoomBuilder) -> void:
	for seg in b.segments():
		var h := b.height if height_max <= 0.0 else b.rng.randf_range(height_min, height_max)
		b.wall_heights.append(h)
		b.box(b.sized(seg, b.length(seg), h, b.WALL_THICKNESS), b.at(seg, b.mid(seg), 0.0, h / 2.0), kind, true)
		if top_edge_kind != "":
			b.box(b.sized(seg, b.length(seg), 0.06, b.WALL_THICKNESS + 0.04), b.at(seg, b.mid(seg), 0.0, h), top_edge_kind)
